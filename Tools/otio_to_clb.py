#!/usr/bin/env python3
"""
otio_to_clb.py
v0.3.1 (260228.1309)

Converts timeline files to CLB simplified JSON for REAPER Conform List Browser.

Usage:
  python3 otio_to_clb.py <input_file>
  python3 otio_to_clb.py <input_file> <output_json_file>

Output JSON goes to stdout unless output_json_file is specified.
On error: outputs {"error": "..."} to stdout and exits with code 1.

Supported adapters (via OpenTimelineIO):
  .edl   -> native Lua EDL parser (not OTIO)
  .xml   -> fcp_xml  (FCP7 XML, DaVinci Resolve XML, Premiere Pro XML)
  .aaf   -> aaf      (requires: pip3 install aaf2)

Output JSON schema:
  {
    "format":      "CMX3600" | "FCP7_XML" | "PREMIERE_XML" | "AAF",
    "title":       string,
    "fps":         number,
    "is_drop":     bool,
    "source_path": string,
    "events": [
      {
        "event_num":    "001",
        "reel":         string,
        "track":        string,   // "V", "V1", "A1", "A2", ...
        "edit_type":    "C" | "D" | "W" | "K",
        "dissolve_len": number | null,
        "src_tc_in":    "HH:MM:SS:FF",
        "src_tc_out":   "HH:MM:SS:FF",
        "rec_tc_in":    "HH:MM:SS:FF",
        "rec_tc_out":   "HH:MM:SS:FF",
        "clip_name":    string,
        "source_file":  string,   // full path to media file
        "scene":        string,   // FCP7/Premiere XML masterComment1 (Resolve=Scene)
        "take":         string    // FCP7/Premiere XML masterComment2 (Resolve=Take)
      },
      ...
    ]
  }

Changelog:
  v0.3.1 (260228.1309)
    - Fix source TC > 24h bug for FCP7/Premiere XML: source_range.start_time is the
      absolute source TC in OTIO's fcp_xml adapter; do NOT add available_range offset.
    - Fix scene/take extraction for Premiere XML: check fcp_xml["logginginfo"]["scene"]
      and ["shottake"] (OTIO stores <logginginfo> as a nested dict).
  v0.3.0
    - Reel extraction via direct XML pre-parse (<file><timecode><reel><name>).
    - get_reel() returns empty string for XML when no reel metadata found (no filename fallback).
    - scene/take: added logginginfo key path, shottake key for Premiere XML.
  v0.2.0
    - Added scene/take columns (get_scene, get_take).
    - Added _parse_xml_reels() for reliable reel extraction.
  v0.1.0
    - Initial release.
"""

import sys
import json
import os
import re
import urllib.parse

try:
    import opentimelineio as otio
except ImportError:
    sys.stdout.write(json.dumps({
        "error": "OpenTimelineIO not installed. Run: pip3 install opentimelineio"
    }))
    sys.exit(1)


# ---------------------------------------------------------------------------
# Timecode utilities
# ---------------------------------------------------------------------------

def rt_to_tc(rt, fps, is_drop=False):
    """Convert RationalTime to HH:MM:SS:FF (or HH:MM:SS;FF for drop) string."""
    if rt is None:
        return "00:00:00:00"

    rt = rt.rescaled_to(fps)

    try:
        if is_drop:
            drop_flag = otio.opentime.IsDropFrameRate.ForceYes
        else:
            drop_flag = otio.opentime.IsDropFrameRate.ForceNo
        return otio.opentime.to_timecode(rt, fps, drop_flag)
    except Exception:
        # Manual fallback (integer arithmetic)
        total_frames = max(0, int(round(rt.value)))
        round_fps = max(1, int(round(fps)))
        f = total_frames % round_fps
        total_secs = total_frames // round_fps
        s = total_secs % 60
        m = (total_secs // 60) % 60
        h = total_secs // 3600
        sep = ";" if is_drop else ":"
        return f"{h:02d}:{m:02d}:{s:02d}{sep}{f:02d}"


# ---------------------------------------------------------------------------
# Format detection
# ---------------------------------------------------------------------------

def _detect_xml_format(filepath):
    """Peek at XML content to distinguish Premiere Pro XML from FCP7/Resolve XML."""
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            head = f.read(2048)
    except Exception:
        return "FCP7_XML"
    # Premiere Pro XML files contain "Premiere Pro" in the xmeml application attribute
    if "Premiere Pro" in head or "premiere pro" in head.lower():
        return "PREMIERE_XML"
    return "FCP7_XML"


def detect_format(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    if ext == ".edl":
        return "CMX3600"
    elif ext == ".xml":
        return _detect_xml_format(filepath)
    elif ext == ".aaf":
        return "AAF"
    return "UNKNOWN"


# ---------------------------------------------------------------------------
# Track name normalization
# ---------------------------------------------------------------------------

def normalize_track_name(track):
    """Return a normalized short track name from an OTIO track."""
    name = (track.name or "").strip()
    kind = getattr(track, "kind", None)

    if name:
        # "Video 1" / "Video" -> "V" / "V1"
        m = re.match(r"^(?:video|v)\s*(\d*)$", name, re.IGNORECASE)
        if m:
            return "V" + m.group(1)

        # "Audio 1" / "Audio" -> "A" / "A1"
        m = re.match(r"^(?:audio|a)\s*(\d*)$", name, re.IGNORECASE)
        if m:
            return "A" + m.group(1)

        # Already short (e.g. "V1", "A2", "FX") — use as-is uppercased
        if len(name) <= 8:
            return name.upper()

        # Long name — fall back to kind

    if kind == otio.schema.TrackKind.Video:
        return "V"
    if kind == otio.schema.TrackKind.Audio:
        return "A"
    return "A"


# ---------------------------------------------------------------------------
# Media reference utilities
# ---------------------------------------------------------------------------

def get_media_path(clip):
    """Return the media file path from the clip's media_reference, or ''."""
    ref = getattr(clip, "media_reference", None)
    if ref is None:
        return ""
    url = getattr(ref, "target_url", None)
    if not url:
        return ""

    # Strip file:// scheme and URL-decode
    if url.startswith("file://"):
        path = urllib.parse.unquote(url[7:])
        # Windows: /C:/foo -> C:/foo
        if re.match(r"^/[A-Za-z]:/", path):
            path = path[1:]
        return path

    return url


def get_media_available_start(clip, fps):
    """Return the media reference's available_range start time (for source TC offset)."""
    ref = getattr(clip, "media_reference", None)
    if ref is None:
        return otio.opentime.RationalTime(0, fps)
    avail = getattr(ref, "available_range", None)
    if avail is None:
        return otio.opentime.RationalTime(0, fps)
    return avail.start_time.rescaled_to(fps)


# ---------------------------------------------------------------------------
# Reel extraction
# ---------------------------------------------------------------------------

def _parse_xml_reels(filepath):
    """
    Pre-parse FCP7/Premiere XML to build a URL → reel_name mapping.

    In FCP7/Premiere XML the reel lives at:
        <file id="…">
          <pathurl>file://…</pathurl>
          <timecode>
            <reel>
              <name>221004</name>     ← this
            </reel>
          </timecode>
        </file>

    Returns dict: { pathurl_string: reel_name, ... }
    """
    try:
        import xml.etree.ElementTree as ET
        tree = ET.parse(filepath)
        root = tree.getroot()
    except Exception:
        return {}

    reels = {}
    seen_ids = set()
    for file_elem in root.iter("file"):
        file_id = file_elem.get("id", "")
        if file_id in seen_ids:
            continue          # skip back-references (same <file id> used twice)
        seen_ids.add(file_id)

        reel_name = ""
        tc = file_elem.find("timecode")
        if tc is not None:
            reel_elem = tc.find("reel/name")
            if reel_elem is not None and reel_elem.text:
                reel_name = reel_elem.text.strip()

        if not reel_name:
            continue

        pathurl_elem = file_elem.find("pathurl")
        if pathurl_elem is not None and pathurl_elem.text:
            reels[pathurl_elem.text.strip()] = reel_name

    return reels


def get_reel(clip, format_name, xml_reels=None):
    """
    Extract reel/tape name for a clip.

    Priority:
      1. cmx_3600 metadata "reel"                 (EDL)
      2. xml_reels[target_url]                     (FCP7/Premiere XML pre-parsed)
      3. fcp_xml clip/media-ref metadata keys      (FCP7/Premiere XML OTIO metadata)
      4. Media file basename (no ext)              (other formats only)
      5. Clip name                                 (other formats only)
    """
    meta = clip.metadata or {}

    if format_name == "CMX3600":
        cmx = meta.get("cmx_3600", {}) or {}
        reel = cmx.get("reel", "") or cmx.get("Reel", "")
        if reel:
            return str(reel).strip()

    if format_name in ("FCP7_XML", "PREMIERE_XML"):
        # 1. Direct XML parse: look up file URL in pre-built reel table
        if xml_reels:
            ref = getattr(clip, "media_reference", None)
            url = getattr(ref, "target_url", "") if ref else ""
            if url and url in xml_reels:
                return xml_reels[url]

        # 2. OTIO metadata fallback: clip-level fcp_xml keys
        fcp = meta.get("fcp_xml", {}) or {}
        for key in ("reel", "tape", "Reel", "Tape"):
            val = fcp.get(key)
            if val:
                return str(val).strip()

        # 3. OTIO metadata fallback: media_reference-level fcp_xml keys
        ref = getattr(clip, "media_reference", None)
        if ref is not None:
            ref_fcp = (getattr(ref, "metadata", {}) or {}).get("fcp_xml", {}) or {}
            for key in ("reel", "tape", "Reel", "Tape"):
                val = ref_fcp.get(key)
                if val:
                    return str(val).strip()
            # <file><timecode><reel><name> nested path
            tc_meta = ref_fcp.get("timecode", {}) or {}
            reel_meta = (tc_meta.get("reel", {}) or {}) if isinstance(tc_meta, dict) else {}
            if isinstance(reel_meta, dict):
                val = reel_meta.get("name", "")
                if val:
                    return str(val).strip()

        # No reel/tape metadata found — return empty (don't use filename or clip name)
        return ""

    # Other formats: use media basename as identifier
    path = get_media_path(clip)
    if path:
        return os.path.splitext(os.path.basename(path))[0]

    return clip.name or ""


# ---------------------------------------------------------------------------
# FPS + drop-frame detection
# ---------------------------------------------------------------------------

def detect_fps_drop(timeline, format_name):
    """
    Detect FPS and drop-frame flag from the timeline.

    For CMX3600: reads timeline.metadata["cmx_3600"]["FCM"]
    For FCP7_XML: reads timeline.metadata["fcp_xml"]["timecode"]["displayformat"]
    Falls back to global_start_time.rate or first clip rate.
    """
    fps = 25.0
    is_drop = False

    meta = timeline.metadata or {}

    # --- CMX3600: FCM line gives FPS + drop flag ---
    if format_name == "CMX3600":
        cmx = meta.get("cmx_3600", {})
        fcm = cmx.get("FCM", "")
        if "DROP FRAME" in fcm.upper() and "NON" not in fcm.upper():
            is_drop = True
            fps = 29.97
        elif "29.97" in fcm or "30" in fcm:
            fps = 29.97
        elif "24" in fcm:
            fps = 24.0
        elif "25" in fcm:
            fps = 25.0
        elif "50" in fcm:
            fps = 50.0
        elif "60" in fcm:
            fps = 60.0

    # --- FCP7 XML / Premiere XML: timecode displayformat ---
    elif format_name in ("FCP7_XML", "PREMIERE_XML"):
        fcp = meta.get("fcp_xml", {})
        tc_meta = fcp.get("timecode", {})
        df = tc_meta.get("displayformat", "NDF")
        if isinstance(df, str) and df.upper() == "DF":
            is_drop = True

    # --- Rate from global_start_time (most reliable regardless of format) ---
    gst = getattr(timeline, "global_start_time", None)
    if gst and gst.rate and gst.rate > 1.0:
        fps = float(gst.rate)
    else:
        # Fall back to first clip's rate
        for track in timeline.tracks:
            for item in track:
                sr = getattr(item, "source_range", None)
                if sr and sr.start_time.rate > 1.0:
                    fps = float(sr.start_time.rate)
                    break
            break

    return fps, is_drop


# ---------------------------------------------------------------------------
# FCP XML comment/metadata helpers
# ---------------------------------------------------------------------------

def get_scene(clip, format_name):
    """
    Return Scene value from available metadata.
    Checks (in order):
      logginginfo.scene  (Premiere XML — OTIO stores <logginginfo> as a nested dict)
      masterComment1     (FCP7 XML)
      scene/Scene        (Resolve-style)
      comment1
    """
    if format_name not in ("FCP7_XML", "PREMIERE_XML"):
        return ""
    meta = clip.metadata or {}
    fcp = meta.get("fcp_xml", {}) or {}
    # Premiere XML: <logginginfo><scene>
    li = fcp.get("logginginfo") or {}
    if isinstance(li, dict):
        val = li.get("scene")
        if val:
            return str(val).strip()
    # FCP7 / Resolve flat keys
    for key in ("masterComment1", "scene", "Scene", "comment1", "Comment1"):
        val = fcp.get(key)
        if val:
            return str(val).strip()
    return ""


def get_take(clip, format_name):
    """
    Return Take value from available metadata.
    Checks (in order):
      logginginfo.shottake  (Premiere XML)
      masterComment2        (FCP7 XML)
      take/Take             (Resolve-style)
      comment2
    """
    if format_name not in ("FCP7_XML", "PREMIERE_XML"):
        return ""
    meta = clip.metadata or {}
    fcp = meta.get("fcp_xml", {}) or {}
    # Premiere XML: <logginginfo><shottake>
    li = fcp.get("logginginfo") or {}
    if isinstance(li, dict):
        val = li.get("shottake")
        if val:
            return str(val).strip()
    # FCP7 / Resolve flat keys
    for key in ("masterComment2", "take", "Take", "comment2", "Comment2"):
        val = fcp.get(key)
        if val:
            return str(val).strip()
    return ""


# ---------------------------------------------------------------------------
# Clip name + source file extraction (EDL metadata override)
# ---------------------------------------------------------------------------

def get_clip_name_and_source(clip, format_name):
    """
    Return (clip_name, source_file) for a clip.

    For CMX3600: OTIO stores FROM CLIP NAME and SOURCE FILE in cmx_3600 metadata.
    For FCP7_XML: clip.name is the clip name; media_reference.target_url is the file.
    """
    meta = clip.metadata or {}
    clip_name = clip.name or ""
    source_file = get_media_path(clip)

    if format_name == "CMX3600":
        cmx = meta.get("cmx_3600", {})
        if cmx.get("clip_name"):
            clip_name = cmx["clip_name"]
        if cmx.get("source_file"):
            source_file = cmx["source_file"]

    return clip_name, source_file


# ---------------------------------------------------------------------------
# Main conversion
# ---------------------------------------------------------------------------

def convert_timeline(timeline, source_path):
    """Convert an OTIO Timeline to the CLB parsed dict."""

    format_name = detect_format(source_path)
    fps, is_drop = detect_fps_drop(timeline, format_name)
    title = getattr(timeline, "name", "") or ""

    # Global start time offset (record TC zero-point)
    gst = getattr(timeline, "global_start_time", None)
    global_offset = gst.rescaled_to(fps) if gst else otio.opentime.RationalTime(0, fps)

    # Pre-parse XML for reel names (<file><timecode><reel><name>)
    xml_reels = {}
    if format_name in ("FCP7_XML", "PREMIERE_XML"):
        xml_reels = _parse_xml_reels(source_path)

    events = []
    event_num = 1
    first_fcp_meta = None   # collect for scene/take diagnostic

    for track in timeline.tracks:
        track_name = normalize_track_name(track)

        for i, item in enumerate(track):
            # Record range: position within the track
            try:
                record_range = track.range_of_child_at_index(i)
            except Exception:
                continue

            rec_start = record_range.start_time.rescaled_to(fps) + global_offset
            rec_end = (record_range.start_time + record_range.duration).rescaled_to(fps) + global_offset

            # ---- Gap: skip ----
            if isinstance(item, otio.schema.Gap):
                continue

            # ---- Clip ----
            elif isinstance(item, otio.schema.Clip):
                if first_fcp_meta is None:
                    first_fcp_meta = (item.metadata or {}).get("fcp_xml", {}) or {}

                src_range = item.source_range
                if src_range:
                    # Source TC:
                    # For FCP7/Premiere XML, source_range.start_time IS the absolute
                    # source TC (confirmed by diagnostic: adding available_range start
                    # doubles the value, producing impossible >24h timecodes).
                    # For CMX3600/AAF/other, add the media available_range offset.
                    if format_name in ("FCP7_XML", "PREMIERE_XML"):
                        src_start = src_range.start_time.rescaled_to(fps)
                        src_end = (src_range.start_time + src_range.duration).rescaled_to(fps)
                    else:
                        media_start = get_media_available_start(item, fps)
                        src_start = src_range.start_time.rescaled_to(fps) + media_start
                        src_end = (src_range.start_time + src_range.duration).rescaled_to(fps) + media_start
                else:
                    # No source range: use 00:00:00:00 with same duration as record
                    src_start = otio.opentime.RationalTime(0, fps)
                    src_end = src_start + record_range.duration.rescaled_to(fps)

                clip_name, source_file = get_clip_name_and_source(item, format_name)
                reel = get_reel(item, format_name, xml_reels)

                events.append({
                    "event_num":    f"{event_num:03d}",
                    "reel":         reel,
                    "track":        track_name,
                    "edit_type":    "C",
                    "dissolve_len": None,
                    "src_tc_in":    rt_to_tc(src_start, fps, is_drop),
                    "src_tc_out":   rt_to_tc(src_end,   fps, is_drop),
                    "rec_tc_in":    rt_to_tc(rec_start,  fps, is_drop),
                    "rec_tc_out":   rt_to_tc(rec_end,    fps, is_drop),
                    "clip_name":    clip_name,
                    "source_file":  source_file,
                    "scene":        get_scene(item, format_name),
                    "take":         get_take(item, format_name),
                })
                event_num += 1

            # ---- Transition (dissolve/wipe) ----
            elif isinstance(item, otio.schema.Transition):
                # OTIO transitions overlap adjacent clips.
                # We record them as a dissolve modifier on the preceding clip.
                # For now: skip — the adjacent clips already carry the full TCs.
                # TODO: if dissolve events need to be explicit (EDL D-type), revisit.
                pass

    result = {
        "format":      format_name,
        "title":       title,
        "fps":         fps,
        "is_drop":     is_drop,
        "source_path": source_path,
        "events":      events,
    }

    # Diagnostic: if XML and all scene/take are empty, report available fcp_xml keys
    if format_name in ("FCP7_XML", "PREMIERE_XML") and events:
        all_empty = all(not e.get("scene") and not e.get("take") for e in events)
        if all_empty and first_fcp_meta is not None:
            keys = sorted(first_fcp_meta.keys())
            if keys:
                result["warning"] = (
                    "Scene/Take columns are empty. "
                    "fcp_xml metadata keys in first clip: " + ", ".join(keys)
                )
            else:
                result["warning"] = "Scene/Take columns are empty — no fcp_xml metadata found."

    return result


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        sys.stdout.write(json.dumps({
            "error": "Usage: otio_to_clb.py <input_file> [output_json_file]"
        }))
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    if not os.path.isfile(input_path):
        sys.stdout.write(json.dumps({"error": f"File not found: {input_path}"}))
        sys.exit(1)

    # AAF: verify that the aaf2 library (OTIO AAF adapter) is available.
    if input_path.lower().endswith(".aaf"):
        try:
            import aaf2  # noqa: F401
        except ImportError:
            sys.stdout.write(json.dumps({
                "error": (
                    "AAF support requires the aaf2 library.\n"
                    "Install it with:  pip3 install aaf2\n"
                    "Then try loading the AAF file again."
                )
            }))
            sys.exit(1)

    # EDL files are handled by the native Lua parser (hsuanice_EDL Parser.lua).
    # OTIO's CMX3600 adapter loses record TC offsets and has bugs with
    # dual-track (V+A same event number) EDLs — not usable for conform workflows.
    if input_path.lower().endswith(".edl"):
        sys.stdout.write(json.dumps({
            "error": ("EDL files are parsed by the native Lua EDL parser, not OTIO. "
                      "This code path should not be reached. "
                      "Check hsuanice_OTIO Bridge.lua routing logic.")
        }))
        sys.exit(1)

    # ---- Load ----
    # Try strict mode first; if OTIO raises an Overlapping / timecode-mismatch
    # error (common in multi-track EDLs), retry with ignore_timecode_mismatch=True.
    import traceback as _tb

    timeline = None
    lenient_mode = False

    try:
        timeline = otio.adapters.read_from_file(input_path)
    except Exception as e_strict:
        e_str = str(e_strict)
        # Overlapping record / timecode mismatch: retry lenient
        if any(k in e_str for k in ("verlapping", "imecode", "mismatch")):
            try:
                timeline = otio.adapters.read_from_file(
                    input_path, ignore_timecode_mismatch=True)
                lenient_mode = True
            except Exception as e_lenient:
                sys.stdout.write(json.dumps({
                    "error": f"OTIO read failed (strict + lenient): {e_lenient}",
                    "traceback": _tb.format_exc(),
                    "original_error": e_str,
                }))
                sys.exit(1)
        else:
            sys.stdout.write(json.dumps({
                "error": f"OTIO read failed: {e_strict}",
                "traceback": _tb.format_exc(),
            }))
            sys.exit(1)

    # ---- Convert ----
    try:
        result = convert_timeline(timeline, input_path)
    except Exception as e:
        sys.stdout.write(json.dumps({
            "error":     f"Conversion error: {e}",
            "traceback": _tb.format_exc(),
        }))
        sys.exit(1)

    if lenient_mode:
        result["warning"] = ("Overlapping record TCs detected — loaded with "
                             "ignore_timecode_mismatch=True. TC values may be approximate.")

    # ---- Output ----
    output_json = json.dumps(result, indent=2, ensure_ascii=False)

    if output_path:
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(output_json)
        sys.stdout.write(json.dumps({"ok": True, "events": len(result["events"])}))
    else:
        sys.stdout.write(output_json)


if __name__ == "__main__":
    main()
