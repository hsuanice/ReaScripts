# hsuanice_AudioSweet Preview Toggle.lua — Changelog

AudioSweet Preview Toggle - Auto Detect Focused/Chain

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.8`).

```text
0.2.8 [260330.1809]
  - ADDED: Auto track FX chain online/offline restore on preview
    • Before starting preview: brings FX chain track online if offline (I_FXEN or per-FX offline bits)
    • State is persisted via ExtState (PREVIEW_TOGGLE_FXCHAIN_SAVED) so the stop-path (2nd toggle press) can restore it
    • On stop: restores original offline state then calls ASP.stop_preview()
    • FX track resolved from: chain target_track_obj → focused FX track → name lookup

0.2.7 (2026-02-10) [internal: v260210.1935]
  - FIXED: Toggle now reliably stops preview on 2nd press
    • Root cause: REAPER terminates the deferred script (watcher) on re-trigger,
      never starting a new instance — 2nd press produced zero output
    • Fix: Core now registers reaper.atexit() alongside watcher
    • atexit fires on script termination with full L1 state — clean cleanup
  - CHANGED: Removed temporary ShowConsoleMsg debug output
  - CHANGED: Version synced with Preview Core 0.2.7

0.2.6 (2026-02-10) [internal: v260210.1303]
  - FIXED: Toggle stop now works reliably on 2nd execution
    • Replaced cross-instance stop_preview() call with PREVIEW_STOP_REQ ExtState flag
    • Watcher in original instance (with full state) handles cleanup — no state bootstrapping
    • Toggle check moved before dofile() — stop path doesn't load Core at all
  - CHANGED: Version synced with Preview Core 0.2.6

0.2.5 (2026-02-10) [internal: v260210.1224]
  - FIXED: Toggle self-toggle now works reliably (was failing on 2nd tap)
    • Core fix: stop_preview() now sets moved_count for timesel count check
    • Core fix: Watcher race replaced 3-frame debounce with 500ms startup grace period
  - CHANGED: Version synced with Preview Core 0.2.5

0.2.4 (2026-02-10) [internal: v260210.1212]
  - FIXED: Manual stop (spacebar etc.) now auto-cleans up preview again
    • Re-enabled Core's stop-watcher (was disabled in 0.2.3 to avoid race)
    • Core watcher now uses 3-frame debounce to prevent false-positive race
  - FIXED: stop_preview() now respects GUI restore_mode setting (GUID vs timesel)
    • Reads preview_restore_mode from GUI ExtState before stopping
    • timesel mode: moves back ALL items in placeholder span (including new items from Run)
    • guid mode: moves back only the originally-moved items (safe when FX track has other items)
  - CHANGED: Removed no_watcher=true from args — watcher re-enabled for manual stop support
  - CHANGED: Version synced with Preview Core 0.2.4

0.2.3 (2026-02-10) [internal: v260210.1113]
  - FIXED: Toggle now reliably stops on 2nd execution (was requiring 3 taps)
    • Root cause: Core's stop-watcher raced with toggle — watcher auto-cleaned up,
      clearing PREVIEW_RUN flag, so toggle fell through and restarted preview
    • Fix: Toggle passes no_watcher=true to Core, disabling the deferred stop-watcher
    • Toggle script now exclusively controls the preview lifecycle via stop_preview()
    • Core's stop_preview() bootstraps state from placeholder + ExtState for full cleanup
  - NEW: Core stores FX track GUID in ExtState (PREVIEW_FX_GUID) for cross-instance lookup
  - NEW: Core.stop_preview() public method — stops transport, finds placeholder,
    bootstraps state, and runs cleanup from a fresh Lua instance

0.2.2 (2026-02-10) [internal: v260210]
  - NEW: True toggle behavior — re-running while preview is active now stops preview
    • Checks PREVIEW_RUN ExtState flag set by Preview Core
    • If preview is running, calls Core.stop_preview() for full cleanup
    • Previous behavior (mode switch on re-entry) replaced by clean stop/start toggle

0.2.1 (2026-02-09) [internal: v260209.2130]
  - FIXED: Cross-platform path resolution for Windows/Linux compatibility
    • Replaced debug.getinfo() relative path with reaper.GetResourcePath() absolute path
    • Fixes "attempt to concatenate a nil value (local 'SCRIPT_DIR')" on Windows

0.2.0 (2025-12-23) [internal: v251223.2256]
  - CHANGED: Version bump to 0.2.0 (public beta)

0.1.0 (2025-12-21) [internal: v251221.1915]
  - NEW: Unified preview script that auto-detects focused vs chain window
  - Priority: Chain FX window → chain preview, Single FX floating → focused preview
  - Fallback: No FX window → chain preview on preview target track
  - Reads preview settings from AudioSweet GUI ExtState
```
