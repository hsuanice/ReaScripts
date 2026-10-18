# hsuanice_Session Fix Core.lua — Changelog

hsuanice Session Fix Core - checks and fixes for preparing a REAPER session for Interchanger / Pro Tools / Nuendo

## 26.1018.1239

- Add: workflow_cues check and M.strip_workflow_cues (in-place cue / adtl rewrite with a JUNK filler; RIFF WAV only).
- Add: the scan can pause (opts.yield, inside a coroutine) so the window can draw progress; it starts again when the project is edited during a pause.
- Add: time of each check in the scan summary (summary.times, M.slowest), slowest checks in the report.
- Add: Tiny items check (tiny_items, review only); 2-pops at xx:59:58:00 or after all other audio are left out and counted (summary.two_pops, report).
- Change: Overlaps lists only stacked-crossfade slivers, not tiny items on their own.
- Add: 2-pops marked by hand are left out of Tiny items: item flag (M.mark_pops / M.clear_pop_marks) or "2-pop" / "tail pop" in the Item Notes.

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
