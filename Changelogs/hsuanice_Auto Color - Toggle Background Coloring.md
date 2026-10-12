# hsuanice_Auto Color - Toggle Background Coloring.lua — Changelog

(formerly `hsuanice_Auto Color Daemon.lua`)

Auto Color Items by Take Name — Background Daemon

## 26.1012.1641

- Renamed to "Auto Color - Toggle Background Coloring" (was "Auto Color Daemon") as part of the 2026-10-12 naming clean-up.

## 26.1012.0930

- Released as part of the 26.1012.0930 package update.

History before 26.1012.0930 (moved out of the script header; last header version: `260908.1427`).

```text
v260908.1427
- Change: BG Bright / BG Sat now only take effect in Shiny mode, matching the main GUI script

v260908.1404
- Add: follows the main GUI script's new BG Bright / BG Sat sliders (bg_brightness_scale /
  bg_saturation_scale in ExtState) — scales item background Value/Saturation on every recolor

v260823.1429 (Taipei Time)
- Fix: daemon now runs independently of GUI heartbeat gating (no need to open GUI first).
- Fix: stale heartbeat values from prior REAPER sessions no longer block daemon processing.
- Fix: daemon keyword matching now follows GUI's split model (take_keyword for items, track_keyword for tracks).
- Add: periodic safety recolor pass to avoid missed updates when state-count changes are not emitted.
- Debug: added runtime logs for startup/recolor diagnostics; default logging is now OFF.

v260804.1623
- Add: supports color_mode from GUI (normal/shiny)
- Add: ShinyColor mode now writes take peak color and applies lighter item background color in daemon auto-coloring
- Fix: include color_mode in settings fingerprint so daemon reacts immediately to mode changes

v260403.1810
- Fix: Daemon now works on REAPER startup without needing to open the GUI script first
- On init, reads hsuanice_AutoColorItems_state.dat directly and populates ExtState,
  so keywords and palette are available even after reaper-extstate.ini is cleared on restart

v260324.1912
- Fix: Daemon no longer slows REAPER on track selection — debounce added (15-frame stable
  window before recolor); GUI settings polled every 10 frames instead of every frame
- Add: Initial release of headless background daemon
```
