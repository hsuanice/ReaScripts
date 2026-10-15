# hsuanice_Session Fix Core.lua — Changelog

hsuanice Session Fix Core - checks and fixes for preparing a REAPER session for Interchanger / Pro Tools / Nuendo

## 26.1015.1303

- Add: Mixed channels can be fixed - one track per channel count as played ("<track> mono / stereo / 4ch ..."); the group with the most items stays on the original track, fewer channels above, more below; folders stay intact. Runs after Channel mode.
- Change: Off grid and the Source length limit trim use the project grid (SWS BR_GetClosest/Next/PrevGridDivision; frame grid without SWS); grid_label() describes it.
- Fix: an edge 1 sample off the grid was listed but never snapped (the fix used a 1-sample tolerance, the scan half a sample).

## 26.1015.1125

- Add: short title, description and impact level for every check.

## 26.1014.2216

- First release: the checks and fixes behind "Session Fix - Interchange Prep".
