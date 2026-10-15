# hsuanice_Toggle Console to Work Log.lua — Changelog

(formerly `hsuanice_Console to Work Log Daemon.lua`)

Console to Work Log Daemon


**Removed from ReaPack** (2026-10-15) with the other Project Manager scripts; the script stays in the repository (`@noindex`) as a backup.

## 26.1012.1641

- Renamed to "Toggle Console to Work Log" (was "Console to Work Log Daemon") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1358

- First release in the hsuanice/ReaScripts repository.
- Requires the js_ReaScriptAPI extension.
- Fix: the log folder is created with REAPER's API (works on Windows, no shell call on every write).

History before 26.1012.1358 (moved out of the script header; last header version: `260823.1538`).

```text
v260823.1538 (Taipei Time)
- Fix: JS_Window_ListAllChild return handling is now API-version compatible (supports both `list` and `count, list` forms).
- Stability: avoids "attempt to index a number value (local 'list')" crash on some js_ReaScriptAPI builds.

v260823.0001 (Taipei Time)
- Initial release: background daemon that monitors ReaScript console output and appends timestamped lines to work.log.
- Log path: writes to current project folder; falls back to Scripts/Tools/work.log when project is unsaved.
```
