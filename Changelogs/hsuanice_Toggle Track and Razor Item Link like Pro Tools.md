# hsuanice_Toggle Track and Razor Item Link like Pro Tools.lua — Changelog

(formerly `hsuanice_Track and Razor Item Link like Pro Tools.lua`)

Track↔Edit link (Pro Tools style). Performance edition; focuses on Razor & item virtual ranges. This build removes menu guards for snappier click-select.

## 26.1017.1609

- Add: remembers the last razor area (range + tracks) for Extend Razor Edit to Mouse Cursor like Pro Tools, because REAPER clears razor areas when an item is clicked. Session-only, not saved with the project.

## 26.1012.1641

- Renamed to "Toggle Track and Razor Item Link like Pro Tools" (was "Track and Razor Item Link like Pro Tools") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.0958

- First release in the hsuanice/ReaScripts repository.
- Works best with the js_ReaScriptAPI and SWS extensions installed (optional).

History before 26.1012.0958 (moved out of the script header; last header version: `260412.1450`).

```text
v260412.1450
  - Fix: fast-click race condition. When LMB-down and LMB-up both arrive
    in the same defer frame (<33ms), the SNM pref-toggle path is bypassed.
    The fast-click path now calls _restore_tracks() directly and sets
    _suppress_D so Section D does not deselect items in the same frame.
v260412.1436
  - Fix: zero-flash Pro Tools guard. On LMB-down over a selected item,
    SNM_SetIntConfigVar disables 'trackselonmouse' before REAPER's
    mouse-up handler fires, so REAPER never selects the wrong track.
    Pref is restored on LMB-up. Uses WM_LBUTTONDOWN/UP intercept
    (JS extension, passthrough=true) for reliable edge detection;
    polling fallback when JS unavailable. Manual-restore fallback when
    SWS/SNM unavailable (flash possible, original behaviour).
v260412.1218
  - Fix: clicking empty arrange space (which deselects items) no longer also
    deselects track selection. Section B now only fires when items ARE selected
    (it_info.count > 0), so clearing item selection is decoupled from track
    selection. Item→Track link still works normally when items are present.
v260412.1146
  - New: ENABLE_TRACKS_TO_RAZOR (C sub-switch) — when false, track-selection
    changes no longer build/clear Razor areas (ENABLE_C must also be true).
  - New: ENABLE_TRACKS_TO_ITEMS (D sub-switch) — when false, track-selection
    changes no longer trigger item sync; Razor→Items (D) still works normally.
    Set this to false to prevent automatic item re-selection when clicking tracks.
v260410.1022
  - Fix: clicking on a selected item no longer resets item/track selection.
  - New: Pro Tools-style guard — if LMB is held on a selected item (no Razor),
    track selection is immediately restored from item selection before ABCD logic runs,
    preventing section D from deselecting items on other tracks.
  - Change: ENABLE_CLICK_SELECT_TRACK now defaults to true so the script fully
    owns track selection management (required for correct Pro Tools behavior).
v250925_2241
  - Revert: removed all context-menu click-through mitigations (popup/menu guards, RMB sessions, soft latch, stability gate).
  - Change: removed mouse-up delay guards to restore immediate, reliable selection.
  - Cleanup: deleted related options/helpers (e.g., CLICK_SUPPRESS_RBUTTON_MENU, CLICK_MENU_CLOSE_GRACE_SEC, CLICK_MENU_SOFT_LATCH_SEC, Click_IsPopupMenuOpen, stability tracking).
  - Note: kept focus-return grace (prevents ghost clicks when returning focus); ABCD linking logic unchanged.
v0.13.0 — Gesture FSM Click Module
  - New: Rewrote the click handler as a finite-state machine (FSM).
    States: IDLE, LMB_GESTURE, RMB_SESSION, MENU_COOLDOWN, FOCUS_COOLDOWN.
    A “click” only registers as a complete LMB gesture (down→up) outside any session/cooldown.

  - Fix: Eliminates menu-close click-through and RMB→LMB residual triggers.
    • Popup/menu is treated as modal: latch open/close and enforce a post-menu grace window.
    • RMB session with cooldown prevents accidental LMB after right-click interactions.
    • Focus-return grace suppresses ghost clicks when returning from plugin/OS UI.

  - Behavior: Hook timing unchanged; click watcher still runs at mainloop "post",
    so ABCD observes selection on the next cycle for stability.

  - Compatibility: Helpers (Click_IsPopupMenuOpen, hit test, track select) unchanged and used by the FSM.

  - Options: Existing click options remain honored (mouse-up/mouse-down, item upper-half toggle,
    tolerance, RMB cooldown, menu-close grace, focus-return grace).
    Current defaults (this build): RMB cooldown 0.15s, menu grace 0.20s, focus grace 0.15s.

  - Notes: Legacy block-left-sequence flags are no longer needed by the FSM (safe to keep or remove later).

v0.12.1
  - Change: Added CLICK_HOOK_PHASE option ("pre" or "post"). Default to "post" so the integrated
    click-to-select-track runs at the end of mainloop. ABCD logic now consumes the track-selection
    change on the next cycle, reducing timing contention with other watchers (menu guards, TS suppress).
  - No changes to ABCD semantics; only the timing of when they observe selection changes.
v0.12.0
  - NEW: Integrated "Click-select Track" watcher (mouse-up/down, item upper-half option, popup guard).
    • Runs at the start of each cycle so ABCD logic sees the fresh track selection.
    • Options: ENABLE_CLICK_SELECT_TRACK, CLICK_SELECT_ON_MOUSE_UP, CLICK_ENABLE_ITEM_UPPER_HALF, etc.
  - No changes to ABCD semantics. Interop with Razor↔Item master toggle preserved.
v0.11.0
  - NEW: ABCD per-section switches in USER OPTIONS (ENABLE_A..D) for fast isolation & debugging.
  - NEW: DEBUG_PRINT flag + dbg() helper to log which section fires (A/B/C/D) each tick.
  - Behavior unchanged when all ENABLE_* = true (backward-compatible).
  - Tip presets (commented): set ENABLE_A=false & ENABLE_B=false to fully disable Arrange→TCP linking.
v0.10.2
  - temp turn off AB block
v0.10.1
  - TCP → Razor toggle honors Edit Link (ON) with Overlap selection:
      • When Edit Link is ON, items overlapping the Razor range are selected/unselected
        as you toggle tracks in TCP (C block now calls Overlap explicitly).
      • When Edit Link is OFF, still builds/clears Razor for visualization but does not touch item selection.
  - Align Razor-sourced sync (D block) to Overlap as well, so it won’t “rewrite” C’s Overlap with Contain.
  - Internal: item/range matcher and per-track selector now accept an explicit match mode parameter;
    no extra enumeration or UI refresh added (perf-neutral).
v0.10.0
  - Interop: respect external Edit Link master toggle (Project ExtState):
      • Namespace "hsuanice_RazorItemLink", Key "enabled" ("1"/"0")
      • OFF → skip Razor→Items sync (D) AND suppress TS→Items in C
             (still builds/clears Razor ranges for visual feedback)
      • ON / unset → behavior unchanged (backward-compatible)
  - Fix: C-block if/else structure (remove stray "..." placeholder) and
         avoid duplicate local RIL_enabled; eliminates syntax error/crash.
  - Perf: only adds a constant-time flag check; no extra enumerations;
          UpdateArrange usage unchanged.
  - Meta: align namespace names; keep "Note" credits in header.
  v0.9.0
    - NEW: One-side trigger guard — prevents "ping-pong" (items→tracks→items) within the same cycle.
    - Stable across all test cases (Razor, Virtual, Time Selection, Select-All 40182).
    - Confirmed performance-friendly under large sessions (200+ tracks, thousands of items).
  v0.8.5 - perf-bugfix4  - Internal testing build (single-side trigger, pre-official).
  v0.8.5 - perf-bugfix3  - Gate: skip C/D if tracks changed due to items this tick (e.g. Select-All).
  v0.8.4 - perf-bugfix2  - Step B: absolute set for track selection to avoid edge cases after 40182.
  v0.8.3 - perf-bugfix   - Fix "need to click twice" with Razor; canonical Razor signature.
  v0.8.2 - perf          - Suppress relatch shrink after script-driven item changes.
  v0.8.1 - perf-hotfix   - Restore set_track_level_ranges().
  v0.8.0 - perf          - Major perf pass.
```
