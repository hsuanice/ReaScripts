# hsuanice_Copy Unmuted Child Items to Parent Folder Track.lua — Changelog

Copy UNMUTED child items to the parent folder track (pre-check overlaps → mark & abort)

## 26.1012.0736

- First release in the hsuanice/ReaScripts repository.

History before 26.1012.0736 (moved out of the script header; last header version: `0.1.1`).

```text
v0.1.1
  - Fix: Use GetTrackMediaItem(track, i) instead of GetMediaItem(proj, i) when iterating items on a track.
v0.1.0
  - Initial release:
    * Select a FOLDER (parent) track and run
    * Scan all children; if ANY unmuted child item would overlap existing parent items:
        - add a TAKE MARKER "OVERLAP" on that child item's active take (at source start)
        - abort without copying anything
    * If no overlaps detected, copy all unmuted items in-place to the parent (state-chunk)
    * Show a simple summary dialog
```
