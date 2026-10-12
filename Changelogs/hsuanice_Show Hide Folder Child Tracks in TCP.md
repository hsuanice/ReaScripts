# hsuanice_Show Hide Folder Child Tracks in TCP.lua — Changelog

(formerly `hsuanice_Show Hide Tracks of Selected Parent or Childred Folder Tracks in TCP.lua`)

Show/Hide TCP children of selected folder parents, or of the parent of selected children

## 26.1012.1641

- Renamed to "Show Hide Folder Child Tracks in TCP" (was "Show Hide Tracks of Selected Parent or Childred Folder Tracks in TCP") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1024

- First release in the hsuanice/ReaScripts repository.
- Comments translated to English.

History before 26.1012.1024 (moved out of the script header; last header version: `0.1.2`).

```text
v0.1.2
- Fix: robust parent detection when no parent (avoid invalid MediaTrack errors).
- Change: use I_FOLDERCOMPACT for TCP folding (0 normal, 1 collapsed, 2 fully collapsed).
- Add: multi-select de-duplication, UI refresh guard, Undo block.
v0.1.1
- Options draft (not released): MODE/TOPMOST_ANCESTOR.
v0.1.0
- Initial minimal toggle from selected parent or parent-of-selected-child.
```
