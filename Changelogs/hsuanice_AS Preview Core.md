# hsuanice_AS Preview Core.lua — Changelog

AudioSweet Preview Core

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.7`).

```text
0.2.7 (2026-02-10) [internal: v260210.1935]
  - FIXED: Toggle now reliably stops preview on 2nd press
    • Root cause: REAPER terminates the deferred script instance (L1) on re-trigger
      instead of starting a new instance — Toggle script never ran on 2nd press
    • Fix: reaper.atexit() registered alongside watcher defer
    • When REAPER terminates L1, atexit fires with full ASP._state — clean stop
    • No cross-instance bootstrap needed; atexit has the original state
  - NEW: reaper.atexit() cleanup handler for script termination
    • Stops transport, reads GUI restore_mode, runs cleanup_if_any()
    • Only registered when watcher is active (Toggle-initiated preview)
    • No-op if watcher already cleaned up (running=false guard)
  - CHANGED: Removed temporary ShowConsoleMsg debug output
  - CHANGED: Watcher simplified — removed ShowConsoleMsg, kept ASP.log() for debug mode

0.2.6 (2026-02-10) [internal: v260210.1303]
  - FIXED: Toggle stop now works reliably on 2nd execution
    • Root cause: stop_preview() ran in a fresh Lua state (cross-instance),
      racing with the watcher in the original instance that has the real state
    • Fix: Toggle now sets PREVIEW_STOP_REQ ExtState flag instead of calling stop_preview()
    • Watcher (in the original instance with full ASP._state) picks up the flag and does cleanup
    • Eliminates all cross-instance state bootstrapping issues
  - NEW: PREVIEW_STOP_REQ ExtState — cross-instance stop signal from Toggle to watcher
  - CHANGED: Watcher now reads GUI preview_restore_mode on both toggle-stop and manual-stop
    • User can change restore mode between preview start and stop
  - CHANGED: STOP_REQ processed before grace period (toggle-stop is always immediate)

0.2.5 (2026-02-10) [internal: v260210.1224]
  - FIXED: stop_preview() now sets moved_count for timesel count check
    • Previously moved_count was unset (nil→0) causing "Count mismatch" error dialog
      on every toggle-stop when restore_mode=timesel
  - FIXED: Watcher race — replaced 3-frame debounce with 500ms startup grace period
    • Watcher now ignores all transport state changes for 500ms after preview starts
    • Eliminates false-positive stop detection during play startup
    • After grace period, watcher monitors normally for manual stop

0.2.4 (2026-02-10) [internal: v260210.1212]
  - FIXED: Stop-watcher debounce — requires 3 consecutive non-playing frames (~100ms)
    before triggering cleanup, preventing false-positive race with toggle script
  - NEW: stop_preview() now accepts opts.restore_mode ("guid"|"timesel")
    • Allows caller to specify move-back strategy matching the GUI setting
    • Ensures newly-generated items (from AudioSweet Run during preview) are moved back
      when timesel mode is selected
  - CHANGED: no_watcher option retained but no longer used by Toggle script
    • Toggle re-enables watcher for manual-stop cleanup support
    • Debounce eliminates the race condition that previously required no_watcher

0.2.3 (2026-02-10) [internal: v260210.1113]
  - NEW: ASP.stop_preview() public method for cross-instance preview stop
    • Stops transport, finds FX track via saved GUID, locates placeholder on any track
    • Bootstraps ASP._state from placeholder + ExtState, then runs cleanup_if_any()
    • Enables reliable toggle behavior from fresh Lua instances
  - NEW: PREVIEW_FX_GUID ExtState — stores FX track GUID on preview start, cleared on cleanup
  - NEW: no_watcher option for ASP.run() / ASP.preview()
    • When true, skips registering the deferred stop-watcher
    • Allows caller (e.g. Toggle script) to manage preview lifecycle exclusively
  - CHANGED: ASP.preview() now passes args.no_watcher through to ASP.run()

0.2.2 (2025-12-25) [internal: v251225.2220]
  - REFACTORED: Removed unused unit detection code
    • Removed build_units_from_selection() function (~30 lines of dead code)
    • Function was defined but never called in Preview Core
    • Preview Core uses direct item manipulation, not unit-based workflow
    • Helper functions (project_epsilon, approx_eq, ranges_touch_or_overlap) retained for Preview-specific use
  - IMPACT: Cleaner codebase, no functionality change

0.2.0.0.1 (2025-12-23) [internal: v251223.2328]
  - CHANGED: Version bump to 0.2.0.0.1
  - CHANGED: Default debug disabled

0.2.0 (2025-12-23) [internal: v251223.2256]
  - CHANGED: Version bump to 0.2.0 (public beta)

0.1.2 (2025-12-22) [internal: v251222.1035]
  - ADDED: Source track channel count protection
    • Snapshots source track I_NCHAN before moving items to FX track
    • Restores source track channel count after moving items back
    • Prevents REAPER auto-adjust from changing source track when items return
    • Essential for post-production workflows and project interchange (Pro Tools/Nuendo)
    • Stored in ASP._state.src_track_nchan
    • Restored in _move_back_and_remove_placeholder()

0.1.1 (2025-12-21) [internal: v251221.2141]
  - ADDED: Track channel count restoration after preview
    • Snapshots track I_NCHAN before preview starts
    • Restores original channel count in cleanup_if_any()
    • Prevents REAPER auto-expansion from persisting after preview
    • Works in both focused and chain preview modes
0.1.0 (2025-12-13) - Initial Public Beta Release
  Minimal preview runtime for AudioSweet with:
  - High-precision timing using reaper.time_precise()
  - Handle-aware edge/glue cue policies
  - Selection restore with verification
  - Integration with AudioSweet ReaImGui and RGWH Core
  - Fixed: Preview item move bug when FX track is below source track (collect-then-move pattern)
  - Enhanced debug logging for item move verification

Internal Build v251213.0008
  - Fixed: Preview item move bug when FX track is below source track.
    * Previously: moving items during iteration caused selection index shift, resulting in even-indexed items being skipped.
    * Now: collect all items first, then move them in a separate loop to avoid index invalidation.
    * Affected scenario: when preview target track has a higher track number than the source track.
  - Added: Enhanced debug logging for item move verification (shows item count and positions before/after move).
  - Behavior: No change to audio path or preview workflow; only fixes the move operation reliability.

Internal Build v251017_1337
  - Verified: removed all Chinese inline comments; file is now fully English-only for public release.
  - Checked: indentation, spacing, and comment alignment preserved exactly.
  - No functional or behavioral changes; logic identical to v251016_2305.
  - Purpose: finalize English translation pass for consistency across the AudioSweet Core libraries.

v251016_2305
  - Changed: Translated all remaining inline comments from Chinese to English for consistency.
    * Areas covered: function headers and inline notes within Core state, switch mode, and placeholder handling.
  - No functional change. Behavior identical to v251016_1851.
  - Purpose: maintain unified English documentation style for public release.

v251016_1851
  - Added: High-precision timing using reaper.time_precise().
    * Exports: snapshot_ms, core_ms, restore_ms, total_ms.
    * Printed via "[WRAPPER][Perf] snapshot=... core=... restore=... total=...".
  - Added: Compact one-line "Selection Debug/Perf" summary for large-scale sessions.
  - Changed: Wrapper overhead minimized (≈1–5 ms typical); Core remains the only heavy stage.
  - Changed: Edge/Glue cue policy aligned with Core.
    * WRITE_EDGE_CUES=true, WRITE_GLUE_CUES=true.
    * GLUE_CUE_POLICY="adjacent-different-source".
  - Fixed: Selection restore now verified only once after Core cleanup (no redundant selection updates).
  - Fixed: Error guards — Core error messages (e.g. "focus track missing") are passed through as summaries only.
  - Removed: Dependency on SWS extension (BR_GetMediaItemGUID).
    * Before: reaper.BR_GetMediaItemGUID(item)
    * After:  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
    * Validation: Native and SWS GUIDs identical ("Equal? true").
  - Dev: DEBUG flag affects verbosity only; functional behavior unchanged.
  - Dev: Legacy target="track" removed.
    * chain_mode=true  → target="name:<TrackName>" or target_track_name.
    * chain_mode=false → forced target="focused".

v251012_2008
  - Change: Focused preview (chain_mode=false) now forces target="focused".
    * Any name-based target (including `target="TARGET_TRACK_NAME"` or `target_track_name`) is ignored in focused mode.
    * This makes switching between chain and focused modes trivial from the template: just flip `chain_mode`.
  - Docs: Updated ASP.preview() arg comments to clarify forced-focused behavior when chain_mode=false.

v251012_1615
  - Change: Removed support for the literal mode `target = "track"`.
    * Core now only exposes two target forms: "focused" and name-based targets
      (via `target_track_name`, `target = "name:<TrackName>"`, or the sentinel `target = "TARGET_TRACK_NAME"`).
    * The normalization path no longer accepts `"track"`; any previous wrapper relying on
      `target="track"` must switch to name-based or focused mode.
  - Docs: Updated comments in `_resolve_target` and `ASP.preview` to reflect supported forms.
  - Behavior: No change to focused/name-based flows; fallbacks and logs unchanged.

v251012_0030
  - Change: Single-pass target normalization in ASP.preview(); no mutation of args.
    * All accepted forms now normalize to a single target spec before resolution:
      - target = "focused"
      - target = "name:<TrackName>"
      - target = MediaTrack*
      - target = { by="name"|"guid"|"index"|"focused", value=... }
      - target_track_name = "<TrackName>"
      - target = "TARGET_TRACK_NAME"  (reads _G.TARGET_TRACK_NAME)
    * Only one call to _resolve_target() is made after normalization.
  - Added: Convenience support for `target = "TARGET_TRACK_NAME"` (reads `_G.TARGET_TRACK_NAME`).
  - Behavior: Unchanged audio path and fallbacks:
    * Default target when nothing specified → {by="name", value="AudioSweet"}.
    * If resolution fails, fallback to "name:AudioSweet".
    * Chain mode still ignores FX index; focused mode still requires a valid FX index.
  - Dev Notes: Clearer, faster code path; logs and loop behavior unchanged.

v251012_0010
  - Added: Support for `target = "TARGET_TRACK_NAME"` sugar.
    * When this is used and `_G.TARGET_TRACK_NAME` is defined,
      the Core will resolve it as a track name target automatically.
    * Internally converts it to `args.target_track_name = _G.TARGET_TRACK_NAME`
      and clears `args.target` to reuse existing name-based logic.
  - Purpose: Simplify Template usage — no need for `target_track_name = TARGET_TRACK_NAME`.
    The user now only sets `local TARGET_TRACK_NAME = "YourTrack"`
    and switches mode with `target = "TARGET_TRACK_NAME"`.

v251010_2152
  - Added: Convenience arg `target_track_name` for ASP.preview(); equivalent to `target={by="name", value="<name>"}`.
  - Added: Default target fallback to `"AudioSweet"` when neither `target` nor `target_track_name` is provided.
  - Improved: Argument docs for ASP.preview() to include `target_track_name`.
  - Behavior: Non-breaking — sugar only applies when `args.target` is nil; existing wrappers continue to work.
  - Notes: Chain vs Focused behavior unchanged; placeholder label logic unchanged (FX name in focused mode, track name in chain mode).

v2510082330
  - Fix: Forward-declare `undo_begin` / `undo_end_no_undo` and bind locals so early callers never hit nil.
  - Change: Consolidated no-undo guards (start, mode switch, cleanup) to suppress all undo points.
  - Added: `USER_RESTORE_MODE` option ("guid" | "timesel") with overlap preflight and clear warning dialog.
  - Added: Source-track placeholder detection and re-entry bootstrap; time-selection windowing in timesel restore.
  - Improved: Debug logs (counts, chosen restore mode, FX isolation) for easier tracing.
  - Behavior: Audio path unchanged; solo scope still via `USER_SOLO_SCOPE` ("track" | "item"); wrappers unchanged.

v2510082151
  - Added: USER_RESTORE_MODE user option ("guid" | "timesel") to control move-back behavior on cleanup.
    * "guid": only move back items that were explicitly moved during this preview session.
    * "timesel": move back all FX-track items overlapping the placeholder or time selection.
  - Added: Overlap-check safeguard before moving items back to source track.
    * If overlap is detected, a warning dialog appears:
      "Move-back aborted: one or more items would overlap existing items on the source track."
      The move-back process aborts safely to prevent collisions.
  - Implemented: Helper functions item_bounds() and track_has_overlap() for robust span checks.
  - Improved: Cleanup flow now logs which restore mode was used and how many items were restored.
  - Behavior: Maintains no-undo protection; integrates seamlessly with existing Preview Core state machine.
  - Note: USER_RESTORE_MODE is a Core-only option; wrappers do not need to set this.
v2510061248 WIP — No-undo hardening (switch/apply paths)
  - _switch_mode(): wrapped entire body in Undo_BeginBlock2/EndBlock2(...,-1) to suppress all undo points when toggling solo/normal.
  - _apply_mode_flags(): added a protective no-undo block around solo clear/apply + Transport:Play.
  - Rationale: many native actions create undo points unless executed inside a -1 end block; this guarantees Preview Core leaves no undo traces.

v2510060105 WIP — No-undo scaffolding landed (partial)
  - Added undo_begin()/undo_end_no_undo() around preview start, mode switch, and cleanup paths.
  - Core debug/user options kept as-is; wrappers unchanged.

  Still creates undo points (TO-DO)
  - Moving selected items to the FX track (preview enter).
  - Isolating/restoring focused FX enable mask.
  - Moving items back to source track & removing the placeholder (preview exit).

  Notes
  - Console debug stream unchanged (no auto-clear).
  - Behavior/functionality unaffected; only undo suppression is in progress.

v2510060105 Change to no undo
  - Wrap mutating ops in undo_begin()/undo_end_no_undo() to avoid creating undo points.
  - Cleanup and mode switch now do not create undo points.
v2510052349 — Core-only user options for SOLO_SCOPE/DEBUG
  - Moved user-configurable options into Core:
    - USER_SOLO_SCOPE = "track" | "item" (default "track")
    - USER_DEBUG = false (enable Core logs when true)
  - Core no longer reads/writes ExtState for SOLO_SCOPE/DEBUG. Wrappers do not need to set these anymore.
  - PREVIEW_MODE still comes from ExtState so wrappers can choose solo vs normal.
  - Added a startup log line to print the current SOLO_SCOPE and DEBUG states.

v2510052343 — Clarify item tint constant
  - Documentation: explained that `0x1000000` sets the high bit of the color integer, which tells REAPER the custom color is *active*.
  - The color field `I_CUSTOMCOLOR` is stored as `RGB | 0x1000000` where the high bit (0x1000000) enables the tint.
  - Functionally unchanged: placeholder items still tinted bright red for visibility.

v2510052318 — Fix ranges_touch_or_overlap() nil on re-entry
  - Moved forward declarations (project_epsilon, ranges_touch_or_overlap) to the top so any caller can resolve them.
  - Removed the later duplicate forward-decl block to prevent late-binding/globals turning nil at runtime.
  - Behavior unchanged otherwise: placeholder on source track, re-entry bootstrap, mode switch, and cleanup all intact.
  - Debug stream unchanged (no auto-clear).

Known issues
  - Razor selection not implemented yet (current order: Time Selection > items span).
  - Cross-wrapper toggle still relies on wrappers updating ExtState hsuanice_AS:PREVIEW_MODE before calling Core.
  - If the placeholder is manually moved/deleted during playback, next run will rebuild by design.
v2510052130 WIP — Preview Core: Solo scope via ExtState; item-solo uses 41558
  - Options: Core reads ExtState hsuanice_AS:SOLO_SCOPE = "track" (default) | "item".
  - Solo(track): clears item-solo (41185) & track-solo (40340), then forces FX track solo (I_SOLO=1).
  - Solo(item): selects moved items and uses 41558 “Item: Solo exclusive” (no prior unsolo needed).
  - Normal/cleanup: always clear both item-solo (41185) and track-solo (40340) to avoid leftover states.
  - Logs: switch/apply path now prints which scope was applied (TRACK/ITEM).

v2510052021 Fix no item selection warning
  - Guard: Core now aborts early (no state changes) when there are no selected items.
  - Guard: If a Time Selection exists but none of the selected items intersect it, show a warning and abort.
  - UX: Clear dialog explains “select at least one item (or an item inside the time selection)”.
  - Logs: Prints `no-targets: abort` reasons in the continuous [AS][PREVIEW] stream when DEBUG=1.

v2510051609 WIP — Preview Core: source-track placeholder detection, safer re-entry
  - Re-entry guard: run() now searches the placeholder **only on the original (source) track**, not the whole project, preventing duplicate placeholders and avoiding heavy scans.
  - State capture: when creating a preview, Core persists `src_track` so subsequent runs can resolve the placeholder even if selection focus moved to the FX track.
  - Cleanup hygiene: `cleanup_if_any()` now also clears `src_track` in state after restoring items and removing the placeholder.
  - Bootstrap on re-entry: if a placeholder is found on the source track, Core **does not rebuild**; it bootstraps runtime (collects moved items by the placeholder span) and only performs mode switching.
  - Logs: unchanged continuous `[AS][PREVIEW]` stream; no console clearing.

  Known issues / notes
  - Razor selection still pending (current order: Time Selection > items span).
  - Cross-wrapper toggle requires the wrapper to flip `hsuanice_AS:PREVIEW_MODE` before calling Core.
  - If the user manually deletes/moves the placeholder during playback, next run will rebuild (by design).
  - Not yet auto-aborting preview when launching full AudioSweet; planned follow-up.

v2510051520 WIP — Placeholder-guarded reentry; no rebuild; true single-tap toggle
  - Core now treats the "PREVIEWING @ …" placeholder on the focused FX track as the ground-truth running flag.
  - On every run() call:
    - If a placeholder is found, Core bootstraps its runtime state (collects current preview items by the placeholder’s time span) and ONLY switches mode (solo↔normal). No re-glue, no re-move, no new placeholder.
    - If no placeholder is found, Core builds a fresh preview as before.
  - Mode switching in _switch_mode() now safely re-selects the moved items before toggling Item-Solo-Exclusive.
  - (Optional) You can pin the placeholder to the FX track (Hunk C) for simpler detection; or skip Hunk C to keep placeholders on source tracks.
  - Keeps your continuous debug stream intact; no console clearing.

  Known notes
  - Normal wrapper should mirror the same ExtState flip to allow cross-wrapper toggling.
  - If the user deletes/moves the placeholder during playback, Core will rebuild on next run (by design).
  - Razor selection still pending; current logic follows Time Selection > item span.

v2510051403 WIP — Preview Core: ExtState-driven mode, move-based preview, placeholder lifecycle
  - ExtState mode: Core reads hsuanice_AS:PREVIEW_MODE ("solo"/"normal"); wrappers only flip this ExtState then call Core (fallback to opts.default_mode if empty).
  - Focused-FX isolation: snapshots per-FX enable mask on the focused track, enables only the focused FX during preview, restores the mask on cleanup.
  - Move-based preview: selected items are MOVED to the focused-FX track (no level-doubling); originals are replaced by a single white placeholder item.
  - Placeholder marker: one empty item with note `PREVIEWING @ Track <n> - <FXName>` spanning Time Selection (or selected-items span); also serves as the “preview is alive” flag.
  - Loop & stop: uses Time Selection if present else items span; forces Repeat ON; a stop-watcher detects transport stop and triggers full cleanup.
  - Cleanup: runs Unsolo-all (41185), moves items back to the placeholder’s track, removes the placeholder, restores FX-enable mask, selection, and Repeat state.
  - Live toggle: re-running Core while active flips solo↔normal without rebuilding or re-moving items (mode switch only).
  - Debug stream: continuous `[AS][PREVIEW]` logs when `hsuanice_AS:DEBUG=1` (no console clear).

  Known issues
  - Wrappers must set `hsuanice_AS:PREVIEW_MODE` before calling Core; legacy `opts.mode` still works as a fallback.
  - Razor selection not implemented yet (Time Selection / item selection only).
  - If the user manually deletes/moves the placeholder or preview items during playback, cleanup may be incomplete.
  - Not yet auto-aborting preview when launching full AudioSweet; planned: end preview first, then proceed.

v2510050105 WIP — Preview Core: one-tap mode toggle, stop-to-cleanup, continuous debug
  - New state machine (ASP._state) with unified flags for running/mode/focused FX/preview items.
  - Single-tap live switching: calling run() with a different mode seamlessly flips solo↔normal during loop playback.
  - Stop watcher: auto-detects transport stop and performs full cleanup (delete preview items, restore repeat/selection).
  - Loop arming: honors Time Selection; otherwise spans selected items; auto-enables Repeat and restores to prior state.
  - Preview copies: selected items are cloned to the focused-FX track; per-mode flags are applied on the clones only.
  - Solo mode: applies “Item Solo Exclusive” to the preview copies (original items untouched).
  - Debug stream: enable with ExtState hsuanice_AS:DEBUG=1; prints continuous [AS][PREVIEW] logs (no console clear).
  - Public API: ASP.run{mode, focus_track, focus_fxindex}, ASP.toggle_mode(start_hint), ASP.is_running(), ASP.cleanup_if_any().

  Known issues
  - Normal (non-solo) mode currently clones without muting originals (will add original-mute snapshot in next pass).
  - Razor edits not yet parsed (TS or selected items only).
  - FX enable snapshot/restore is simplified; per-FX enable mask restore is planned.

v2510050103 — Preview Core: seamless mode toggle, full state restore
  - Added run/switch/cleanup state machine: ASP._state tracks running/mode/fx target/unit/moved items.
  - One-track guard: preview only runs when all selected items are on a single track (multi-items OK).
  - Loop region: uses Time Selection if present; otherwise unit span; auto-enables Repeat and restores it after.
  - Normal (non-solo) mode: snapshots & mutes original items to avoid level doubling; copies items to FX track and plays.
  - Solo mode: toggles “Item solo exclusive” on the preview copies; original items remain unmuted.
  - Live mode switch: calling Preview again with the other mode flips normal↔solo without stopping playback.
  - Cleanup: on stop/end, turns off solo (if any), moves items back to original track, restores mutes/selection/FX enables/transport.
  - Debug: honors ExtState "hsuanice_AS:DEBUG" == "1" to print [AS][PREVIEW] steps.

  Known issues
  - Razor edits not yet parsed; preview spans Time Selection or unit range only.
  - FX enable restore is simplified to “re-enable all on FX track”; per-FX enable snapshot/restore can be added later.
  - If items are manually moved/deleted during preview, cleanup may not fully restore the original scene.

2510042327 Initial version.
```
