#!/usr/bin/env python3
"""
otio_to_clb.py
Convert timeline files to CLB JSON for hsuanice_OTIO Bridge.lua.

Called by Library/hsuanice_OTIO Bridge.lua:
  python3 otio_to_clb.py <filepath>

Supported formats:
  .xml   FCP7 XML (Final Cut Pro 7) via opentimelineio fcp_xml adapter
  .xml   DaVinci Resolve XML        via opentimelineio fcp_xml adapter
  .otio  Native OpenTimelineIO      via opentimelineio otio_json adapter
  .aaf   AAF via LibAAF aaftool     via aaf_to_otio module (same directory)

Output (stdout): CLB JSON
  {
    "format":  "FCP7_XML" | "RESOLVE_XML" | "PREMIERE_XML" | "OTIO" | "AAF",
    "title":   str,
    "fps":     float,
    "is_drop": bool,
    "events":  [ { event_num, reel, track, edit_type, dissolve_len,
                   src_tc_in, src_tc_out, rec_tc_in, rec_tc_out,
                   clip_name, source_file, scene, take }, ... ]
  }

On error outputs: { "error": "...", "traceback": "..." }

Dependencies:
  pip install opentimelineio
  aaftool in PATH (LibAAF) — only needed for .aaf files

Version: 260402.1405
"""

import sys
import os
import re
import json
import traceback
from pathlib import Path


# ---------------------------------------------------------------------------
# Lazy imports
# ---------------------------------------------------------------------------

def _import_otio():
    try:
        import opentimelineio as otio
        import opentimelineio.opentime as ot
        return otio, ot
    except ImportError:
        raise RuntimeError(
            "opentimelineio is not installed.\n"
            "Run: pip3 install opentimelineio"
        )


def _import_aaf_to_otio():
    """Import aaf_to_otio from the same directory as this script."""
    script_dir = Path(__file__).parent
    aaf_script = script_dir / "aaf_to_otio.py"
    if not aaf_script.exists():
        raise RuntimeError(
            f"aaf_to_otio.py not found.\nExpected: {aaf_script}"
        )
    import importlib.util
    spec = importlib.util.spec_from_file_location("aaf_to_otio", aaf_script)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---------------------------------------------------------------------------
# Format detection
# ---------------------------------------------------------------------------

_XML_PREMIERE_RE = re.compile(
    r'<PremiereData\b|xmeml.*?application.*?premiere',
    re.IGNORECASE | re.DOTALL,
)
_XML_RESOLVE_RE = re.compile(
    r'<xmeml.*?version|<fcpxml|DaVinci Resolve',
    re.IGNORECASE | re.DOTALL,
)

def _detect_xml_format(path):
    """
    Sniff the first 2 KB of an XML file to distinguish:
      'PREMIERE_XML', 'RESOLVE_XML', 'FCP7_XML'
    """
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            head = f.read(2048)
    except OSError:
        return "FCP7_XML"

    if _XML_PREMIERE_RE.search(head):
        return "PREMIERE_XML"
    if re.search(r'DaVinci\s*Resolve', head, re.IGNORECASE):
        return "RESOLVE_XML"
    return "FCP7_XML"


def detect_format(path):
    """Return a format string for the given file path."""
    ext = Path(path).suffix.lower()
    if ext == ".xml":
        return _detect_xml_format(path)
    if ext == ".aaf":
        return "AAF"
    return "OTIO"


# ---------------------------------------------------------------------------
# Timecode helpers
# ---------------------------------------------------------------------------

def _rt_to_tc(rt, fps, is_drop, otio_opentime):
    """
    Convert a RationalTime to a TC string at the given project fps.
    Always rescales to fps first, so high-rate audio timecodes (48 kHz)
    from the OTIO native AAF adapter are handled correctly.
    """
    ot = otio_opentime
    rt_fps = rt.rescaled_to(fps)
    return ot.to_timecode(rt_fps, fps, drop_frame=is_drop)


def _infer_is_drop(tl_metadata, fps_float):
    """
    Determine drop-frame flag.
    AAF files store 'aaf:is_drop' in metadata.
    For XML, assume NDF (the safe default; user can override via CLB fps setting).
    """
    if "aaf:is_drop" in tl_metadata:
        return bool(tl_metadata["aaf:is_drop"])
    # Common DF rates: 29.97, 59.94, 119.88
    # Without explicit metadata we default to NDF for XML.
    return False


def _fps_from_rate(rate):
    """Convert a RationalTime rate (float) to a sensible fps float."""
    # Common fractions: 30000/1001 = 29.97002997…, 24000/1001 = 23.976…
    # OTIO stores the exact float.
    return float(rate)


# ---------------------------------------------------------------------------
# Metadata extraction helpers
# ---------------------------------------------------------------------------

def _meta_str(d, *keys):
    """Walk nested dict by keys, return string or ''."""
    for k in keys:
        if not isinstance(d, dict):
            return ""
        d = d.get(k, {})
    return str(d) if (d and d != {}) else ""


def _url_decode(s):
    """URL-decode a string that may be percent-encoded (once or twice)."""
    from urllib.parse import unquote
    decoded = unquote(s)
    # If still percent-encoded (double-encoded AAF names), decode again
    if "%" in decoded:
        decoded = unquote(decoded)
    return decoded


def _parse_scene_take_from_name(clip_name):
    """
    Try to extract a normalised scene string and take number from a
    structured clip name such as:

        06_01B_02_T01 - Merged   →  ('6-1B-2', '1')
        06_01B_01_T05_A - Merged →  ('6-1B-1', '5')
        12_03C_01_T02            →  ('12-3C-1', '2')

    Convention assumed:
        {part1}_{part2}_…_{partN}_T{take}[_{channel}] [- Merged/Synced/…]

    Each underscore-delimited part has its leading zeros stripped and
    alpha suffix uppercased; the parts are joined with '-' to form the
    scene key that can be compared against audio iXML SCENE metadata.

    Returns ('', '') if the pattern is not recognised.
    """
    import re
    if not clip_name:
        return '', ''

    # Strip common trailing annotations: " - Merged", " - Synced", " - MOS" …
    name = re.sub(
        r'\s*[-–]\s*(Merged|Synced|MOS|Mix|Stem)\b.*$',
        '', clip_name, flags=re.IGNORECASE).strip()

    # Strip single-letter channel suffix at the very end: _A, _B, _a …
    name = re.sub(r'_([A-Za-z])$', '', name)

    # Require pattern: {body}_T{digits}
    m = re.match(r'^(.+)_[Tt](\d+)$', name)
    if not m:
        return '', ''

    body, take_raw = m.group(1), m.group(2)

    # Normalise take: strip leading zeros
    take = str(int(take_raw))

    # Normalise scene: split body on '_', strip leading zeros from each part
    def _norm(p):
        mp = re.match(r'^0*(\d*)([A-Za-z]*)$', p)
        if mp:
            num   = str(int(mp.group(1))) if mp.group(1) else ''
            alpha = mp.group(2).upper()
            return (num or '0') + alpha if (num or alpha) else p.upper()
        return p.upper()

    parts = [_norm(p) for p in body.split('_') if p]
    scene = '-'.join(parts)

    return scene, take


def _aaf_user_comments(clip):
    """
    Return the AAF UserComments dict from a clip loaded by the OTIO native
    AAF adapter.  The adapter stores them under clip.metadata['AAF']['UserComments'].
    Returns an empty dict if not found.
    """
    meta = clip.metadata or {}
    aaf_m = meta.get("AAF", {})
    if not isinstance(aaf_m, dict):
        return {}
    uc = aaf_m.get("UserComments", {})
    return uc if isinstance(uc, dict) else {}


def _reel_from_clip(clip):
    """
    Derive a reel/tape name from clip metadata, then fall back to
    the clip name (= original source filename for AAF clips), then
    the target URL stem.  URL-decodes the result.
    """
    meta = clip.metadata or {}

    # FCP7 XML: masterComment1 / masterComment2 often carry scene / tape
    for key in ("reel", "tape", "masterComment2", "masterComment1"):
        v = _meta_str(meta, key) or _meta_str(meta, "fcp_xml", key)
        if v:
            return _url_decode(v)

    # OTIO native AAF adapter: UserComments TAPE field
    uc = _aaf_user_comments(clip)
    tape = uc.get("TAPE") or uc.get("Tape") or ""
    if tape:
        return str(tape)

    # Clip name (aaf_to_otio sets this to original source filename;
    # native AAF adapter uses MasterMob name)
    if clip.name:
        return _url_decode(clip.name)

    # Last resort: source file stem
    mr = clip.media_reference
    if mr and hasattr(mr, "target_url") and mr.target_url:
        return Path(mr.target_url.split("?")[0]).stem

    return ""


def _scene_take(clip):
    """Return (scene, take) strings from clip metadata."""
    meta = clip.metadata or {}
    uc   = _aaf_user_comments(clip)

    scene = (
        _meta_str(meta, "scene")
        or _meta_str(meta, "fcp_xml", "scene")
        or _meta_str(meta, "fcp_xml", "masterComment1")
        or str(uc.get("SCENE") or uc.get("Scene") or "")
    )
    take = (
        _meta_str(meta, "take")
        or _meta_str(meta, "fcp_xml", "take")
        or _meta_str(meta, "fcp_xml", "masterComment2")
        or str(uc.get("TAKE") or uc.get("Take") or "")
    )

    # Last resort: parse scene/take from the clip name itself.
    # Handles AAF clips whose UserComments don't carry iXML metadata but
    # whose name follows the  EP_SCENE_SHOT_T## [- Merged]  convention.
    if not scene and not take and clip.name:
        scene, take = _parse_scene_take_from_name(clip.name)

    return scene, take


def _source_file(clip):
    """Return a file path / URL string from the clip's media reference."""
    mr = clip.media_reference
    if mr is None:
        return ""
    if hasattr(mr, "target_url") and mr.target_url:
        url = mr.target_url
        # Convert file:// URLs to plain paths where possible
        if url.startswith("file://"):
            from urllib.parse import urlparse, unquote
            parsed = urlparse(url)
            # file://localhost/path  or  file:///path
            path = unquote(parsed.path)
            if os.path.isabs(path):
                return path
        return url
    return ""


# ---------------------------------------------------------------------------
# Progress reporting
# ---------------------------------------------------------------------------

def _write_progress(progress_file, phase, current, total, name=""):
    """
    Write a single-line progress record to progress_file (overwrites each time).
    Format:  phase TAB current TAB total TAB name NEWLINE
    Safe to call frequently; silently ignores write errors.
    """
    if not progress_file:
        return
    try:
        with open(progress_file, "w", encoding="utf-8") as f:
            f.write(f"{phase}\t{current}\t{total}\t{name}\n")
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Track-kind helpers
# ---------------------------------------------------------------------------

def _track_label(track, audio_idx, video_idx):
    """Return a track label like 'A1', 'A2', 'V', 'V2'."""
    import opentimelineio as otio
    kind = getattr(track, "kind", None)
    if kind == otio.schema.TrackKind.Audio:
        return f"A{audio_idx}" if audio_idx > 1 else "A1"
    if kind == otio.schema.TrackKind.Video:
        return "V" if video_idx == 1 else f"V{video_idx}"
    return track.name or "X"


# ---------------------------------------------------------------------------
# OTIO timeline → CLB events
# ---------------------------------------------------------------------------

def _timeline_to_clb(tl, fmt, progress_file=""):
    """
    Convert an opentimelineio Timeline to a CLB dict.
    progress_file: optional path; if given, writes phase/current/total/name
                   progress records so the caller can display a progress bar.
    """
    otio, ot = _import_otio()

    meta     = tl.metadata or {}
    fps      = _fps_from_rate(tl.global_start_time.rate if tl.global_start_time
                               else 25.0)
    is_drop  = _infer_is_drop(meta, fps)
    gstart   = tl.global_start_time  # absolute origin

    # Count total clips for progress denominator (fast pass)
    import opentimelineio as _otio_count
    total_clips = sum(
        1 for track in tl.tracks
        for item in track
        if isinstance(item, _otio_count.schema.Clip)
    )
    if progress_file:
        _write_progress(progress_file, "converting", 0, total_clips, "")

    events    = []
    event_num = 0
    a_idx = v_idx = 0

    for track in tl.tracks:
        import opentimelineio as otio_inner
        kind = getattr(track, "kind", None)
        if kind == otio_inner.schema.TrackKind.Audio:
            a_idx += 1
            v_idx  = max(v_idx, 0)
        else:
            v_idx += 1

        trk_label = _track_label(track, a_idx, v_idx)
        pending_transition = None   # (in_offset_rt, out_offset_rt, name)

        children = list(track)

        for i, item in enumerate(children):
            schema = getattr(item, "OTIO_SCHEMA", type(item).__name__)

            # ── Transition ──────────────────────────────────────────────
            if isinstance(item, otio_inner.schema.Transition):
                pending_transition = item
                continue

            # ── Gap → skip ──────────────────────────────────────────────
            if isinstance(item, otio_inner.schema.Gap):
                pending_transition = None
                continue

            # ── Clip ─────────────────────────────────────────────────────
            if not isinstance(item, otio_inner.schema.Clip):
                pending_transition = None
                continue

            clip = item
            event_num += 1

            # Progress: write every 50 events (cheap enough, visible granularity)
            if progress_file and event_num % 50 == 1:
                _write_progress(progress_file, "converting", event_num, total_clips,
                                (clip.name or "").replace("\t", " "))

            # Timeline (record) range
            rp        = clip.range_in_parent()
            rec_start = rp.start_time + gstart
            rec_end   = rec_start + rp.duration

            # Source range
            sr       = clip.source_range
            src_start = sr.start_time if sr else ot.RationalTime(0, fps)
            src_end   = src_start + (sr.duration if sr else rp.duration)

            # Convert to TC strings (rescale to project fps so 48 kHz
            # audio RationalTimes from the native AAF adapter work correctly)
            rec_in  = _rt_to_tc(rec_start, fps, is_drop, ot)
            rec_out = _rt_to_tc(rec_end,   fps, is_drop, ot)
            src_in  = _rt_to_tc(src_start, fps, is_drop, ot)
            src_out = _rt_to_tc(src_end,   fps, is_drop, ot)

            # Edit type / dissolve
            edit_type    = "C"
            dissolve_len = None
            if pending_transition is not None:
                edit_type    = "D"
                xfade_total  = (pending_transition.in_offset
                                + pending_transition.out_offset)
                dissolve_len = int(round(xfade_total.value))
            pending_transition = None

            # Metadata
            reel         = _reel_from_clip(clip)
            scene, take  = _scene_take(clip)
            clip_name    = _url_decode(clip.name) if clip.name else reel
            source_file  = _source_file(clip)

            events.append({
                "event_num":    str(event_num),
                "reel":         reel,
                "track":        trk_label,
                "edit_type":    edit_type,
                "dissolve_len": dissolve_len,
                "src_tc_in":    src_in,
                "src_tc_out":   src_out,
                "rec_tc_in":    rec_in,
                "rec_tc_out":   rec_out,
                "clip_name":    clip_name,
                "source_file":  source_file,
                "scene":        scene,
                "take":         take,
            })

    return {
        "format":   fmt,
        "title":    tl.name or "",
        "fps":      fps,
        "is_drop":  is_drop,
        "events":   events,
    }


# ---------------------------------------------------------------------------
# Loaders per format
# ---------------------------------------------------------------------------

def _load_xml(path, progress_file=""):
    otio, ot = _import_otio()
    _write_progress(progress_file, "parsing", 0, 0, Path(path).name)
    tl = otio.adapters.read_from_file(path, adapter_name="fcp_xml")
    fmt = detect_format(path)
    return _timeline_to_clb(tl, fmt, progress_file)


def _load_otio(path, progress_file=""):
    otio, ot = _import_otio()
    _write_progress(progress_file, "parsing", 0, 0, Path(path).name)
    tl = otio.adapters.read_from_file(path, adapter_name="otio_json")
    return _timeline_to_clb(tl, "OTIO", progress_file)


def _load_aaf(path, progress_file=""):
    """
    Load an AAF file via the OTIO native AAF adapter (aaf2 / pyaaf2).

    The native adapter traverses the full AAF Mob chain and therefore
    returns absolute recording timecodes (PhysicalSourceMob TC) as source
    in/out points — matching what tools like EdiLoad report.

    Falls back to the aaf_to_otio.py / aaftool pipeline if the native
    adapter is unavailable (e.g. aaf2 not installed).
    """
    otio, ot = _import_otio()

    # Signal that we're in the slow AAF parse phase (no clip count yet)
    _write_progress(progress_file, "parsing", 0, 0, Path(path).name)

    # Prefer native OTIO AAF adapter: gives correct absolute source TC
    try:
        tl = otio.adapters.read_from_file(path, adapter_name="AAF")
        return _timeline_to_clb(tl, "AAF", progress_file)
    except Exception:
        pass

    # Fallback: aaf_to_otio.py / aaftool pipeline
    aaf_mod   = _import_aaf_to_otio()
    otio_dict = aaf_mod.convert(path)
    json_str  = __import__("json").dumps(otio_dict)
    tl        = otio.adapters.read_from_string(json_str, adapter_name="otio_json")
    return _timeline_to_clb(tl, "AAF", progress_file)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def convert(path, progress_file=""):
    """Convert timeline file at path → CLB dict. Raises on failure."""
    ext = Path(path).suffix.lower()
    if ext == ".xml":
        return _load_xml(path, progress_file)
    if ext == ".aaf":
        return _load_aaf(path, progress_file)
    return _load_otio(path, progress_file)


def main():
    # Suppress library-level warnings (e.g. pyaaf2 "fat sector count mismatch")
    # so they don't pollute stdout and break JSON parsing by the caller.
    # Actual errors (logging.ERROR and above) are still captured.
    import logging
    logging.getLogger().setLevel(logging.ERROR)

    # Parse args: positional = filepath, optional --progress-file <path>
    progress_file = ""
    positional = []
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--progress-file" and i + 1 < len(args):
            progress_file = args[i + 1]
            i += 2
        else:
            positional.append(args[i])
            i += 1

    if not positional:
        sys.stderr.write(
            "Usage: python3 otio_to_clb.py <timeline_file> [--progress-file <path>]\n"
            "  Supported: .xml  .aaf  .otio\n"
        )
        sys.exit(1)

    path = positional[0]
    if not os.path.isfile(path):
        print(json.dumps({"error": f"File not found: {path}"}))
        sys.exit(0)

    try:
        clb = convert(path, progress_file)
        print(json.dumps(clb, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({
            "error":     str(e),
            "traceback": traceback.format_exc(),
        }))


if __name__ == "__main__":
    main()
