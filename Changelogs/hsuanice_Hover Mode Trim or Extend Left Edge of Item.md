# hsuanice_Hover Mode Trim or Extend Left Edge of Item.lua — Changelog

Hover_Mode_-_Trim_or_Extend_Left_Edge_of_Item (Preserve Fade End, No Flicker)

## 26.1012.0736

- Released as part of the 26.1012.0736 package update.

History before 26.1012.0736 (moved out of the script header; last header version: `2510051925 Fix Pin Track issue`).

```text
v2510051925
  - Pin Track compatibility: switched hover hit-testing to prefer REAPER native APIs
    (GetItemFromPoint / GetTrackFromPoint) with SWS as fallback.
  - Left: gap→extend now uses library’s pin-safe mouse-track resolver; removed local
    “visible-only” gate to avoid false skips. Delegates to apply_left_edge_no_flicker.
  - Right: (no logic change required if already using library picks) — ensure gap→extend
    uses hover.pick_on_gap("right", pos) and delegates to apply_right_edge_no_flicker.
  - Monitor: added native vs SWS diagnostics to help verify mis-hits under pinned tracks.
  - Behavior unchanged otherwise (no flicker; preserves fade endpoints; no-overlap extends).

v250926_1610
  - Update: Sync Start in Source offset across all takes when trimming/extending left edge.
v0.3.4
  - Fix: Single selected item in True Hover no longer forces selection-sync.
         We now pass `prefer_selection` to the library, gate the leftmost-per-track filter by this flag,
         and enable the gap→extend fallback only when selection-sync is OFF (no selection or single selection).
  - Behavior: With ≥2 selected items, selection-sync remains unchanged.
v0.3.3
  - Selection-sync in True Hover now requires ≥2 selected items. With a single selected item, behave like no-selection (individual editing).
  - Added debug logs for selection count and prefer_selection flag.
v0.3.2
  - True Hover + selection: only process the LEFTMOST selected item on each track (skip others).
  - Extend now clamps to previous item end + epsilon on the same track (no overlap).
v0.3.1
  - No-selection + gap on mouse track → extend next item on that track.
v0.3.0
  - Library integration, DEBUG switch, no-flicker write order, preserve fade END.
```
