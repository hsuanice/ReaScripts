# hsuanice_Count Items and Tracks - Selection HUD.lua — Changelog

(formerly `hsuanice_Count Item and Track and Toggle Show Item Details.lua`)

GFX - Count Items/Tracks and Toggle Show Item Details

## 26.1012.1641

- Renamed to "Count Items and Tracks - Selection HUD" (was "Count Item and Track and Toggle Show Item Details") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1358

- First release in the hsuanice/ReaScripts repository.

History before 26.1012.1358 (moved out of the script header; last header version: `260505.1742`).

```text
v260505.1742
  - Selection range priority changed to: Razor edits > Time selection >
    Item selection > Edit cursor. Razor scan walks every track's
    P_RAZOREDITS and takes the min start / max end across all areas.
v260505.1520
  - Remove "Follow Transport" option: REAPER's transport primary time
    mode is not exposed by any native lua API (and projtimemode actually
    reflects the ruler / project default, not the transport). Pick the
    matching explicit format (Timecode / Min:Secs / etc.) instead.
v260505.1506
  - Rename time-format menu entries for clarity:
      Project default (ruler)  → Follow Ruler
      Timecode (h:m:s:f)       → Project Timecode (h:m:s:f)
    "Project Timecode" uses Project Settings → frame rate + start time
    and is fixed regardless of the ruler / grid display (matches Pro Tools).
v260505.1457
  - Time format is now selectable via right-click menu:
      * Project default (ruler)   — mode -1
      * Timecode (h:m:s:f)        — mode 5
      * Min:Secs                  — mode 0
      * Measures.Beats            — mode 2
      * Seconds                   — mode 3
      * Samples                   — mode 4
    Persisted in TIME_MODE ext state.
v260505.1451
  - Start / End / Length now follow the project's primary time unit
    (ruler setting, format_timestr_pos mode -1) instead of being locked
    to timecode. Switching the ruler updates the display live.
v260505.1443
  - Redesign layout to mirror Pro Tools transport selection display:
    * Top row keeps Items / Tracks counts + arrow toggle.
    * New Start / End / Length timecode rows beneath the counts.
    * Detail panel (MIDI / Audio / Empty / Channel Count) still toggles via
      the arrow / left-click.
  - Selection range source: selected items if any → time selection → edit cursor.
  - Timecodes formatted via reaper.format_timestr_pos(t, "", 5) (HH:MM:SS:FF).
  - Auto-resize accounts for the new TC rows; UI scale (font 13/16/20/24)
    reflows everything proportionally.
v260304.1650
  - Fix: r.atexit(save_state) ensures dock state and position are saved even when
    REAPER is closed without manually closing the script window
  - Fix: save_state() now uses cached vars only (safe when gfx is already gone)
  - Fix: floating position cached every frame so it's accurate at atexit time
v260304.1530
  - Rewritten from ReaImGui → native gfx (no ReaImGui dependency)
  - Persistent window position, dock state, font size, panel state across restarts
  - Right-click menu: font size (S/M/L/XL), dock toggle, close
  - Left-click anywhere: toggle detail panel
  - Fix: ensure_size() skips when docked (prevents docker interference)
  - Fix: detect undock-by-drag and trigger resize automatically
v0.3.1 (2025-09-14)
  - Fix: Guarded Begin/End pairing during docking/undocking and project switching
  - Fix: Theme push/pop balanced, preventing "PushStyleColor/PopStyleColor Mismatch" assertions
v0.3.0 (2025-09-14)
  - New: XR-style GUI with shared color theme + 16pt font (warn once if theme lib missing)
  - Keep: Same counting logic and throttled details scanning as prior version
  - Fix: Always End() after Begin(), mirroring stability guard in 0.2.0.1
v0.2.0.1 (2025-09-13)
  - Fix: Always call ImGui_End() after ImGui_Begin(), regardless of visible flag
```
