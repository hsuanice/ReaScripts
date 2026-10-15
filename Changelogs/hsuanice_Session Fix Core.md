# hsuanice_Session Fix Core.lua — Changelog

hsuanice Session Fix Core - checks and fixes for preparing a REAPER session for Interchanger / Pro Tools / Nuendo

## 26.1015.1425

- Fix: Fade shapes on hidden tracks / inside collapsed folders were not fixed (REAPER's actions skip them); those tracks are shown for the actions and restored, and any fade still not reached gets the values read from the actions.
- Change: Folders comes right after Hidden tracks.
- Fix: crossfade shapes are only set by REAPER's action (the API reads values such as 7 but cannot write them - a crossfade became shape -1); broken crossfades are flagged "fix Crossfades first"; plain fades are written directly only with a value the API accepts, checked and restored otherwise.
- Add: issue.needs ("visibility" for items on hidden tracks / in collapsed folders, "crossfades" for broken crossfades in Fade shapes) and M.NEEDS labels / questions.

## 26.1015.1303

- Add: Mixed channels can be fixed - one track per channel count as played ("<track> mono / stereo / 4ch ..."); the group with the most items stays on the original track, fewer channels above, more below; folders stay intact. Runs after Channel mode.
- Change: Off grid and the Source length limit trim use the project grid (SWS BR_GetClosest/Next/PrevGridDivision; frame grid without SWS); grid_label() describes it.
- Fix: an edge 1 sample off the grid was listed but never snapped (the fix used a 1-sample tolerance, the scan half a sample).

## 26.1015.1125

- Add: short title, description and impact level for every check.

## 26.1014.2216

- First release: the checks and fixes behind "Session Fix - Interchange Prep".
