#!/usr/bin/env python3
"""
aaf_to_otio.py
Convert AAF files to OpenTimelineIO JSON via LibAAF's aaftool.

Usage:
  python3 aaf_to_otio.py input.aaf [output.otio]
  python3 aaf_to_otio.py input.aaf -           # stdout

  --pt-true-fades     Pass through to aaftool (ProTools fade handling)
  --pt-remove-sae     Pass through to aaftool (remove ProTools SAE clips)

If output path is omitted, writes to stdout.

Dependencies:
  - aaftool  (LibAAF, https://github.com/agfline/LibAAF)
    brew install libaaf   OR   pre-built binary at /usr/local/bin/aaftool
  - Python 3.8+, stdlib only

Architecture:
  1. aaftool --aaf-summary          → FPS, drop/NDF, global start TC, title
  2. aaftool --aaf-clips …          → track / clip / xfade structure
  3. aaftool --aaf-essences …       → file paths keyed by unique name
  4. Build OTIO JSON dict
  5. Write JSON to file (or stdout)

Version: 260402.1405
"""

import sys
import os
import re
import json
import subprocess
import shutil
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

AAFTOOL = shutil.which("aaftool") or "/usr/local/bin/aaftool"

# All diagnostic output from aaftool lands on stdout (not stderr),
# mixed with real data. Strip ANSI colour codes before parsing.
_ANSI_RE = re.compile(r'\x1b\[[0-9;]*[mKJH]')


# ---------------------------------------------------------------------------
# Helper: run aaftool
# ---------------------------------------------------------------------------

def _run(aaf_path, *flags):
    """
    Run aaftool with given flags on aaf_path.
    Combines stdout + stderr and strips ANSI codes.
    Raises RuntimeError on tool-not-found or timeout.
    """
    cmd = [AAFTOOL] + list(flags) + [str(aaf_path)]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        raw = r.stdout + r.stderr        # warnings live on stdout
        return _ANSI_RE.sub('', raw)
    except FileNotFoundError:
        raise RuntimeError(
            f"aaftool not found at {AAFTOOL!r}.\n"
            "Install LibAAF: https://github.com/agfline/LibAAF"
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"aaftool timed out on: {aaf_path}")


# ---------------------------------------------------------------------------
# Timecode utilities
# ---------------------------------------------------------------------------

def _parse_fps_ratio(ratio_str):
    """'30000/1001' → (30000, 1001, 29.97…)   '24/1' → (24, 1, 24.0)"""
    m = re.match(r'(\d+)/(\d+)', ratio_str.strip())
    if not m:
        return None, None, None
    n, d = int(m.group(1)), int(m.group(2))
    return n, d, (n / d) if d else None


def _tc_to_frames(tc, fps_float, force_drop=False):
    """
    Convert timecode string 'HH:MM:SS:FF' (NDF) or 'HH:MM:SS;FF' (DF)
    to an integer frame count.

    is_drop is inferred from the separator (';') or from force_drop.
    """
    is_drop = force_drop or (';' in tc)
    tc_clean = tc.replace(';', ':')
    parts = tc_clean.split(':')
    if len(parts) != 4:
        return 0
    h, m, s, f = int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
    fps_r = round(fps_float)

    if is_drop and fps_r in (30, 60):
        # SMPTE drop-frame formula
        dpf = 2 if fps_r == 30 else 4          # dropped frames per minute
        total_min = 60 * h + m
        frames = (fps_r * 3600 * h
                  + fps_r * 60 * m
                  + fps_r * s
                  + f
                  - dpf * (total_min - total_min // 10))
    else:
        frames = (h * 3600 + m * 60 + s) * fps_r + f

    return frames


def _rt(frames, rate):
    """OTIO RationalTime dict."""
    return {"OTIO_SCHEMA": "RationalTime.1", "rate": rate, "value": int(frames)}


def _tr(start_frames, dur_frames, rate):
    """OTIO TimeRange dict."""
    return {
        "OTIO_SCHEMA": "TimeRange.1",
        "start_time": _rt(start_frames, rate),
        "duration":   _rt(dur_frames,   rate),
    }


# ---------------------------------------------------------------------------
# Section 1: parse --aaf-summary
# ---------------------------------------------------------------------------

def parse_summary(text):
    """
    Return dict:
      fps        float    edit-rate fps (e.g. 29.97002997)
      fps_num    int      numerator   (e.g. 30000)
      fps_den    int      denominator (e.g. 1001)
      is_drop    bool
      start_tc   str      'HH:MM:SS:FF' or 'HH:MM:SS;FF'
      title      str
    """
    out = {
        "fps":     25.0,
        "fps_num": 25,
        "fps_den": 1,
        "is_drop": False,
        "start_tc": "00:00:00:00",
        "title":   "",
    }

    # TC EditRate / TC EditRrate (both seen in the wild)
    m = re.search(r'\bTC\s+Edit\w+\s*:\s*(\d+/\d+)', text)
    if m:
        n, d, fp = _parse_fps_ratio(m.group(1))
        if fp:
            out["fps"], out["fps_num"], out["fps_den"] = fp, n, d

    # TC FPS: 29.97 DF  /  24 NDF
    m = re.search(r'TC FPS\s*:.*?\b(DF|NDF)\b', text)
    if m:
        out["is_drop"] = (m.group(1) == "DF")

    # Composition Start: 01:00:00:00  (last match = plain TC, not the EU/samples lines)
    for m in re.finditer(r'Composition Start\s*:\s*([0-9]{2}:[0-9]{2}:[0-9]{2}[;:][0-9]{2})', text):
        out["start_tc"] = m.group(1)

    # Composition Name: ...
    m = re.search(r'Composition Name\s*:\s*(.+)', text)
    if m:
        out["title"] = m.group(1).strip()

    return out


# ---------------------------------------------------------------------------
# Section 2: parse --aaf-essences
# ---------------------------------------------------------------------------

def parse_essences(text):
    """
    Returns two dicts keyed by UniqueName and Name respectively.
    Each value is an essence dict:
      {
        "file_url": str,          # file:// or other URL
        "scene":    str,          # from AAF metadata "Scene" tag
        "take":     str,          # from AAF metadata "Take" tag
        "tape":     str,          # from AAF metadata "Tape" tag
      }

    Prior version only captured the File: URL and discarded subsequent
    metadata lines; this version continues parsing after the File: line.
    """
    unique_map = {}   # UniqueName → essence dict
    name_map   = {}   # Name       → essence dict

    cur_name    = None
    cur_unique  = None
    cur_essence = None

    for line in text.splitlines():
        s = line.strip()

        # Audio[N] :: ...  Name: "X"  UniqueName: "Y"
        m = re.search(
            r'Audio\[\d+\]\s*::.*?Name:\s*"([^"]*)".*?UniqueName:\s*"([^"]*)"', s)
        if m:
            cur_name, cur_unique = m.group(1), m.group(2)
            cur_essence = {"file_url": "", "scene": "", "take": "", "tape": ""}
            continue

        if cur_essence is None:
            continue

        # └── File: "url"   or  ├── File: "url"
        m = re.search(r'File:\s*"([^"]+)"', s)
        if m:
            cur_essence["file_url"] = m.group(1)
            if cur_unique:
                unique_map[cur_unique] = cur_essence
            if cur_name:
                name_map[cur_name] = cur_essence
            # Do NOT reset cur_essence here — keep reading metadata lines below
            continue

        # Metadata lines:  - Name: "Scene"  Text: "6-1B-2"
        #                  - Name: "Take"   Text: "1"
        #                  - Name: "Tape"   Text: "25Y04M14"
        m = re.search(r'Name:\s*"([^"]*)".*?Text:\s*"([^"]*)"', s)
        if m:
            key = m.group(1).strip().lower()
            val = m.group(2).strip()
            if key in cur_essence:
                cur_essence[key] = val

    return unique_map, name_map


# ---------------------------------------------------------------------------
# Section 3: parse --aaf-clips
# ---------------------------------------------------------------------------

def parse_clips(text, fps, is_drop):
    """
    Parse the 'Tracks & Clips' section.

    Returns a list of track dicts:
    {
      "kind"  : "Audio" | "Video",
      "index" : int,
      "name"  : str,
      "items" : [clip_dict | xfade_dict, ...]
    }

    clip_dict:
    {
      "type"          : "clip",
      "num"           : int,
      "start_tc"      : str,   # timeline position
      "len_tc"        : str,   # duration
      "end_tc"        : str,
      "src_offset_tc" : str,   # source in-point
      "source_files"  : [str, ...],   # one per channel
      "fade_in"       : {"curve": str, "len_tc": str} | None,
      "fade_out"      : {"curve": str, "len_tc": str} | None,
    }

    xfade_dict:
    {
      "type"          : "xfade",
      "curve"         : str,
      "length_tc"     : str,
      "cut_point_tc"  : str,
    }
    """
    tracks       = []
    cur_track    = None
    cur_clip     = None
    in_clips_sec = False

    for line in text.splitlines():
        s = line.strip()

        # Section header
        if re.match(r'Tracks\s*&\s*Clips\s*:', s):
            in_clips_sec = True
            continue
        if re.match(r'Media\s*Essences\s*:', s):
            in_clips_sec = False
            continue
        if not in_clips_sec:
            continue

        # ── Track header ──────────────────────────────────────────
        # AudioTrack[1] ::  EditRate: 48000/1 (48000.00)  Format: MONO  Name: "Audio 1"
        m = re.match(r'(Audio|Video)Track\[(\d+)\]\s*::', s)
        if m:
            if cur_clip and cur_track is not None:
                cur_track["items"].append(cur_clip)
                cur_clip = None
            kind = m.group(1)
            idx  = int(m.group(2))
            nm   = re.search(r'Name:\s*"([^"]*)"', s)
            cur_track = {
                "kind":  kind,
                "index": idx,
                "name":  nm.group(1) if nm else f"{kind} {idx}",
                "items": [],
            }
            tracks.append(cur_track)
            continue

        if cur_track is None:
            continue

        # ── Clip line ─────────────────────────────────────────────
        # ├── Clip (1):  Start: TC  Len: TC  End: TC  SourceOffset: TC  Channels: N …
        m = re.search(
            r'Clip\s*\(\d+\):\s*'
            r'Start:\s*([0-9:;]+)\s+'
            r'Len:\s*([0-9:;]+)\s+'
            r'End:\s*([0-9:;]+)\s+'
            r'SourceOffset:\s*([0-9:;]+)', s)
        if m:
            if cur_clip:
                cur_track["items"].append(cur_clip)
            cur_clip = {
                "type":          "clip",
                "start_tc":      m.group(1),
                "len_tc":        m.group(2),
                "end_tc":        m.group(3),
                "src_offset_tc": m.group(4),
                "source_files":  [],
                "fade_in":       None,
                "fade_out":      None,
            }
            fi = re.search(r'FadeIn:\s*(\w+)\s*\(([0-9:;]+)\)', s)
            if fi:
                cur_clip["fade_in"]  = {"curve": fi.group(1), "len_tc": fi.group(2)}
            fo = re.search(r'FadeOut:\s*(\w+)\s*\(([0-9:;]+)\)', s)
            if fo:
                cur_clip["fade_out"] = {"curve": fo.group(1), "len_tc": fo.group(2)}
            continue

        # ── SourceFile line ───────────────────────────────────────
        # │   └── SourceFile [ch 1]: "filename"
        m = re.search(r'SourceFile\s*\[ch\s*\d+\]:\s*"([^"]*)"', s)
        if m and cur_clip:
            cur_clip["source_files"].append(m.group(1))
            continue

        # ── X-FADE line ───────────────────────────────────────────
        # ├── X-FADE: CURV_LOG  Length: TC  CutPoint: TC
        m = re.search(
            r'X-FADE:\s*(\w+)\s+Length:\s*([0-9:;]+)\s+CutPoint:\s*([0-9:;]+)', s)
        if m:
            if cur_clip:
                cur_track["items"].append(cur_clip)
                cur_clip = None
            cur_track["items"].append({
                "type":          "xfade",
                "curve":         m.group(1),
                "length_tc":     m.group(2),
                "cut_point_tc":  m.group(3),
            })
            continue

    # flush last clip
    if cur_clip and cur_track is not None:
        cur_track["items"].append(cur_clip)

    return tracks


# ---------------------------------------------------------------------------
# Build OTIO JSON
# ---------------------------------------------------------------------------

def build_otio(summary, tracks, unique_map, name_map, aaf_path):
    fps      = summary["fps"]
    is_drop  = summary["is_drop"]
    fps_num  = summary["fps_num"]
    fps_den  = summary["fps_den"]

    # OTIO rate: use exact float (29.97002997… for 30000/1001, 24.0 for 24/1)
    otio_rate = fps_num / fps_den

    start_frames = _tc_to_frames(summary["start_tc"], fps, is_drop)

    otio_tracks = []

    for track in tracks:
        children = []
        # cursor = position of the next expected item on the timeline
        cursor = start_frames

        for item in track["items"]:

            if item["type"] == "clip":
                clip_start  = _tc_to_frames(item["start_tc"],      fps, is_drop)
                clip_len    = _tc_to_frames(item["len_tc"],         fps, is_drop)
                src_offset  = _tc_to_frames(item["src_offset_tc"],  fps, is_drop)

                # ── gap before clip (if any) ──────────────────────
                gap_frames = clip_start - cursor
                if gap_frames > 0:
                    children.append({
                        "OTIO_SCHEMA": "Gap.1",
                        "metadata":    {},
                        "name":        "",
                        "source_range": _tr(0, gap_frames, otio_rate),
                        "effects":     [],
                        "markers":     [],
                    })

                # ── resolve source file ───────────────────────────
                src_name = item["source_files"][0] if item["source_files"] else ""
                essence  = (unique_map.get(src_name)
                            or name_map.get(src_name)
                            or {})
                file_url = essence.get("file_url", "") if isinstance(essence, dict) else str(essence)

                if file_url:
                    media_ref = {
                        "OTIO_SCHEMA":          "ExternalReference.1",
                        "metadata":             {},
                        "name":                 src_name,
                        "available_range":      None,
                        "available_image_bounds": None,
                        "target_url":           file_url,
                    }
                else:
                    media_ref = {
                        "OTIO_SCHEMA":          "MissingReference.1",
                        "metadata":             {"aaf:source_name": src_name},
                        "name":                 src_name,
                        "available_range":      None,
                        "available_image_bounds": None,
                    }

                # ── clip metadata: scene / take / tape ────────────
                clip_meta = {}
                if isinstance(essence, dict):
                    if essence.get("scene"):
                        clip_meta["scene"] = essence["scene"]
                    if essence.get("take"):
                        clip_meta["take"]  = essence["take"]
                    if essence.get("tape"):
                        clip_meta["tape"]  = essence["tape"]

                # ── fades as LinearTimeWarp effects ───────────────
                effects = []
                if item["fade_in"]:
                    fi_frames = _tc_to_frames(item["fade_in"]["len_tc"], fps, is_drop)
                    effects.append({
                        "OTIO_SCHEMA":  "Effect.1",
                        "metadata":     {
                            "aaf:fade_type":   "FadeIn",
                            "aaf:fade_curve":  item["fade_in"]["curve"],
                            "aaf:fade_frames": fi_frames,
                        },
                        "name":         "FadeIn",
                        "effect_name":  "FadeIn",
                    })
                if item["fade_out"]:
                    fo_frames = _tc_to_frames(item["fade_out"]["len_tc"], fps, is_drop)
                    effects.append({
                        "OTIO_SCHEMA":  "Effect.1",
                        "metadata":     {
                            "aaf:fade_type":   "FadeOut",
                            "aaf:fade_curve":  item["fade_out"]["curve"],
                            "aaf:fade_frames": fo_frames,
                        },
                        "name":         "FadeOut",
                        "effect_name":  "FadeOut",
                    })

                children.append({
                    "OTIO_SCHEMA":   "Clip.1",
                    "metadata":      clip_meta,
                    "name":          src_name,
                    "source_range":  _tr(src_offset, clip_len, otio_rate),
                    "effects":       effects,
                    "markers":       [],
                    "media_reference": media_ref,
                })
                cursor = clip_start + clip_len

            elif item["type"] == "xfade":
                xfade_len  = _tc_to_frames(item["length_tc"],    fps, is_drop)
                cut_point  = _tc_to_frames(item["cut_point_tc"], fps, is_drop)
                out_offset = xfade_len - cut_point

                # In OTIO a Transition overlaps the preceding and following clip.
                # in_offset  = overlap into the clip BEFORE the transition
                # out_offset = overlap into the clip AFTER  the transition
                children.append({
                    "OTIO_SCHEMA":      "Transition.1",
                    "metadata":         {"aaf:xfade_curve": item["curve"]},
                    "name":             f"X-FADE ({item['curve']})",
                    "transition_type":  "SMPTE_Dissolve",
                    "in_offset":        _rt(cut_point,  otio_rate),
                    "out_offset":       _rt(out_offset, otio_rate),
                    "effects":          [],
                    "markers":          [],
                })
                # cursor does NOT advance for transitions

        otio_tracks.append({
            "OTIO_SCHEMA":  "Track.1",
            "metadata":     {},
            "name":         track["name"],
            "source_range": None,
            "effects":      [],
            "markers":      [],
            "kind":         "Audio" if track["kind"] == "Audio" else "Video",
            "children":     children,
        })

    return {
        "OTIO_SCHEMA": "Timeline.1",
        "metadata": {
            "aaf:source":   str(aaf_path),
            "aaf:fps_num":  fps_num,
            "aaf:fps_den":  fps_den,
            "aaf:is_drop":  is_drop,
        },
        "name": summary.get("title") or Path(str(aaf_path)).stem,
        "global_start_time": _rt(start_frames, otio_rate),
        "tracks": {
            "OTIO_SCHEMA":  "Stack.1",
            "metadata":     {},
            "name":         "tracks",
            "source_range": None,
            "effects":      [],
            "markers":      [],
            "children":     otio_tracks,
        },
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def convert(aaf_path, extra_flags=None):
    """
    Convert aaf_path → OTIO dict.
    extra_flags: list of additional aaftool flags, e.g. ['--pt-true-fades'].
    """
    extra = extra_flags or []

    summary_text = _run(aaf_path, "--aaf-summary")
    summary      = parse_summary(summary_text)

    clips_text   = _run(aaf_path, "--aaf-clips", "--show-metadata",
                        "--pos-format", "tc", *extra)
    tracks       = parse_clips(clips_text, summary["fps"], summary["is_drop"])

    ess_text     = _run(aaf_path, "--aaf-essences", "--show-metadata",
                        "--pos-format", "tc", *extra)
    unique_map, name_map = parse_essences(ess_text)

    return build_otio(summary, tracks, unique_map, name_map, aaf_path)


def main():
    args = sys.argv[1:]

    # Collect passthrough flags
    extra_flags = []
    positional  = []
    for a in args:
        if a.startswith("--pt-"):
            extra_flags.append(a)
        else:
            positional.append(a)

    if not positional:
        print(
            "Usage: python3 aaf_to_otio.py input.aaf [output.otio | -]\n"
            "       -  writes to stdout\n"
            "       Flags: --pt-true-fades  --pt-remove-sae",
            file=sys.stderr,
        )
        sys.exit(1)

    aaf_path = positional[0]
    out_path = positional[1] if len(positional) > 1 else None

    if not os.path.isfile(aaf_path):
        print(f"Error: file not found: {aaf_path}", file=sys.stderr)
        sys.exit(1)

    try:
        otio = convert(aaf_path, extra_flags)
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    json_str = json.dumps(otio, indent=2, ensure_ascii=False)

    if out_path and out_path != "-":
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(json_str)
        n_tracks = len(otio["tracks"]["children"])
        n_clips  = sum(
            sum(1 for i in t["children"] if i.get("OTIO_SCHEMA") == "Clip.1")
            for t in otio["tracks"]["children"]
        )
        print(
            f"Written: {out_path}\n"
            f"  Title:  {otio['name']}\n"
            f"  Tracks: {n_tracks}\n"
            f"  Clips:  {n_clips}",
            file=sys.stderr,
        )
    else:
        print(json_str)


if __name__ == "__main__":
    main()
