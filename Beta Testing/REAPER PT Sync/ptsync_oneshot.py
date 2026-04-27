#!/usr/bin/env python3
"""ptsync_oneshot.py — Reaper -> Pro Tools spot bridge (v1).

Reads a manifest JSON written by the Reaper-side script and, for each entry:
  1. Selects the target track in Pro Tools by name
  2. Imports the audio file (TC-based, so PT honors the BWF Time Reference)
  3. Renames the resulting clip to the Reaper take name
     (rename_file=False — we never touch the file on disk)

Manifest schema:
{
  "items": [
    {
      "source_path":  "/abs/path/to/file.wav",
      "target_track": "REAPER<>PT_01",
      "clip_name":    "VO_take_03",
      "tc_samples":   12345678,
      "sample_rate":  48000
    },
    ...
  ]
}

Usage:
    python3 ptsync_oneshot.py /path/to/manifest.json

Requirements:
    pip install py-ptsl
    Pro Tools 2022.12 or later, running, with a session open.
    Avid Developer SDK certificate registered (one-time, free signup at
    https://developer.avid.com/).
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path
from typing import Any

try:
    from ptsl import open_engine
    from ptsl import PTSL_pb2 as pt
    from ptsl import ops
except ImportError:
    sys.stderr.write(
        "Error: py-ptsl not installed.\n"
        "Install with:  pip install py-ptsl\n"
    )
    sys.exit(2)


# ----------------------------------------------------------------------------
# Per-item spot
# ----------------------------------------------------------------------------

def spot_one(engine: Any, item: dict) -> tuple[bool, str]:
    """Spot a single manifest entry into the open PT session.

    Returns (success, message).
    """
    source_path = item["source_path"]
    target_track = item["target_track"]
    clip_name = item["clip_name"]
    tc_samples = item["tc_samples"]

    if not Path(source_path).is_file():
        return False, f"source not found: {source_path}"

    # 1. Select the target track by exact name match.
    #    py-ptsl select_tracks_by_name takes a list of names.
    try:
        engine.select_tracks_by_name([target_track])
    except Exception as e:
        return False, f"select_tracks_by_name({target_track!r}) failed: {e}"

    # 2. Import audio onto the selected track at the spot TC.
    #    NOTE: py-ptsl's Engine.import_audio() hard-codes import_type=1 which
    #    is IType_Session, not IType_Audio (= 2), and uses MD_NewTrack which
    #    forces a brand-new track. We bypass it:
    #      * import_type = Audio
    #      * audio_destination = None (don't create a new track; goes to the
    #        currently-selected track)
    #      * audio_location = Spot, with location_value = tc_samples in samples
    try:
        location_data = pt.SpotLocationData(
            location_type=pt.SLType_Start,
            location_options=pt.TOOptions_Samples,
            location_value=str(tc_samples),
        )
        audio_data = pt.AudioData(
            file_list=[source_path],
            audio_operations=pt.AMOptions_LinkToSourceAudio,
            audio_destination=pt.MDestination_None,
            audio_location=pt.MLocation_Spot,
            location_data=location_data,
        )
        op = ops.CId_Import(import_type=pt.IType_Audio, audio_data=audio_data)
        engine.client.run(op)
    except Exception as e:
        return False, f"import_audio failed: {e}"

    # Give PT a moment to register the import.
    time.sleep(0.25)

    # 3. Rename. PT creates an auto-track named after the imported file's
    #    basename (with channel suffix like ".A7" for poly siblings). The
    #    spotted clip lands on that auto-track. We:
    #      a) select every clip on the auto-track, then rename_selected_clip
    #         — handles the timeline instance(s)
    #      b) rename_target_clip on the bare stem — handles the whole-file
    #         entry in the Clip List
    file_stem = Path(source_path).stem  # "...AAP_A7__pt1422242001"
    m = re.search(r"[._-](A\d+)(?:[._-]|$)", file_stem)
    chan_suffix = f".{m.group(1)}" if m else ""
    auto_track = f"{file_stem}{chan_suffix}"

    actions = []

    # (a) Timeline clip(s) via select-all-on-track + rename_selected_clip
    try:
        engine.select_all_clips_on_track(auto_track)
        engine.rename_selected_clip(
            new_name=clip_name,
            rename_file=False,
        )
        actions.append(f"timeline:{auto_track}")
    except Exception as e:
        actions.append(f"timeline:FAIL({e})")

    # (b) Clip-list whole-file entry (named <stem>, no channel suffix).
    # Often this entry doesn't exist — PT may only create the channel-suffixed
    # clip when iXML has CHANNEL_INDEX. "Can't found clip" is expected then.
    try:
        engine.rename_target_clip(
            clip_name=file_stem,
            new_name=clip_name,
            rename_file=False,
        )
        actions.append(f"cliplist:{file_stem}")
    except Exception as e:
        msg = str(e)
        if "Can't found clip" in msg or "Can't find clip" in msg:
            actions.append("cliplist:none")
        else:
            actions.append(f"cliplist:FAIL({e})")

    return True, "ok (" + "; ".join(actions) + ")"


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

def main() -> int:
    if len(sys.argv) < 2:
        sys.stderr.write("Usage: ptsync_oneshot.py <manifest.json>\n")
        return 1

    manifest_path = Path(sys.argv[1])
    if not manifest_path.is_file():
        sys.stderr.write(f"Manifest not found: {manifest_path}\n")
        return 1

    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = json.load(f)

    items = manifest.get("items", [])
    if not items:
        print("[ptsync] manifest has no items.")
        return 0

    print(f"[ptsync] Connecting to Pro Tools…")
    try:
        engine_ctx = open_engine(
            company_name="reaper-pt-sync",
            application_name="ptsync_oneshot",
        )
    except Exception as e:
        sys.stderr.write(
            f"[ptsync] Could not open PTSL engine: {e}\n"
            f"  - Is Pro Tools running?\n"
            f"  - Is your developer certificate registered?\n"
        )
        return 3

    ok_count = 0
    with engine_ctx as engine:
        try:
            session_name = engine.session_name()
        except Exception as e:
            sys.stderr.write(f"[ptsync] No open session? ({e})\n")
            return 4

        print(f"[ptsync] Connected. Open session: {session_name!r}")
        print(f"[ptsync] Spotting {len(items)} item(s)...")

        for idx, item in enumerate(items, start=1):
            success, info = spot_one(engine, item)
            tag = "OK  " if success else "FAIL"
            print(
                f"  [{tag}] {idx}/{len(items)}  "
                f"track={item['target_track']!r}  "
                f"clip={item['clip_name']!r}  "
                f":: {info}"
            )
            if success:
                ok_count += 1

    print(f"[ptsync] Done. {ok_count}/{len(items)} succeeded.")
    return 0 if ok_count == len(items) else 5


if __name__ == "__main__":
    sys.exit(main())


# ----------------------------------------------------------------------------
# Troubleshooting notes
# ----------------------------------------------------------------------------
#
# If `engine.import_audio(source_path)` puts the clip in the Clip List instead
# of dropping it on the selected track at the BWF Time Reference, try the
# following alternative flow (uncomment in spot_one and adapt):
#
#   from ptsl import PTSL_pb2 as pt
#
#   # Lower-level call: build an ImportAudio request with explicit options.
#   # The exact field names depend on your installed PTSL version; inspect
#   # PTSL_pb2.py to confirm. Typical pattern:
#   req = pt.ImportAudioRequestBody(
#       file_list=[source_path],
#       audio_options=pt.IAO_TC,         # use bext Time Reference
#       location=pt.IL_Spot,             # spot to TC, not Selection / Session Start
#       # destination=pt.ID_SelectedTrack, # if your version exposes this
#   )
#   engine.client.run(pt.ImportAudio, req)
#
# Once you've confirmed which combination of options actually drops the clip
# on the selected track at the right TC, lift it into spot_one and remove
# the high-level engine.import_audio call.
