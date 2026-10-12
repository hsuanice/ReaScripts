# hsuanice_Clock with Date 24H.lua — Changelog

(formerly `hsuanice_Work Timer.lua`)

Work Timer - real-time 24H clock (resizable, dockable, follows the project frame rate)

## 26.1012.1641

- Renamed to "Clock with Date 24H" (was "Work Timer") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1358

- First release in the hsuanice/ReaScripts repository.

History before 26.1012.1358 (moved out of the script header; last header version: `260917.1054`).

```text
v260917.1054
  - Right-click "Show Seconds" / "Show Frames" toggles (independent, persist across sessions)
  - Date text enlarged (~2x)
v260228.1930
  - Persistent widget: window auto-reopens if closed by project switch
  - Right-click "Close Work Timer" is now the only way to fully stop
v260228.1858
  - Hover info: shows "⌘+click → set edit cursor" hint when mouse is over window
  - ⌘+click (Ctrl+click on Windows): moves REAPER edit cursor to the clicked TC position
v260228.1800
  - Custom color: right-click "Color: Custom > Edit..." to enter HEX
  - Custom hex persists across sessions (custom_hex ExtState key)
v260228.1730
  - Dock support: right-click "Dock window" to dock/undock
  - Dock state persists across sessions (gfx.init dockstate arg)
v260228.1600
  - Remember window position across sessions (gfx.dock)
  - Fix right-click menu index offset (flat list, no #-headers)
  - Color and font persist via reaper.GetExtState / SetExtState
v260228.1200
  - Right-click menu: 5 color presets + 4 font presets
  - Clock auto-scales to window size (width + height limit)
  - Date row scales proportionally, vertically centred
v260228
  - Initial release
  - 24H TC clock with project frame rate (TimeMap_curFrameRate)
  - gfx-based, no dependencies
```
