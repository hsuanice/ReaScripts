# hsuanice_Delete Selected Tracks with Warning.lua — Changelog

Delete Selected Tracks (safe; prompt if content/folders/FX/routing; show selection, children & FX/routing counts)

## 26.1012.1024

- First release in the hsuanice/ReaScripts repository.

History before 26.1012.1024 (moved out of the script header; last header version: `260303.2350`).

```text
v260303.2350
  + Changed delete method to use native Action 40005 (Track: Remove tracks)
  + Prevent folder depth corruption when deleting folder parent tracks
  + Now matches REAPER native delete behavior
v0.3.0
      - Added detection and summary for FX inserts, Input FX, Sends, and Receives; any non-zero count now forces a confirmation dialog.
      - Confirmation dialog now shows totals for these four categories.
      - Kept all previous safety checks (items, automation, folder parents, child count) and instant delete behavior when truly empty.
v0.2.1 - Add summary lines for "Selected tracks" and total "Child tracks".
v0.2.0 - English messages; prompt when selection includes folder parents with children.
v0.1.0 - Initial release.
```
