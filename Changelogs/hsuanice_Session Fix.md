# hsuanice_Session Fix.lua — Changelog

(formerly `hsuanice_Fix Tools.lua`)

Fix Tools - clean up edits before moving a REAPER session to Pro Tools or Nuendo

## 26.1015.1303

- Add: Mixed channels can be fixed - one track per channel count as played ("<track> mono / stereo / 4ch ..."); the group with the most items stays on the original track, fewer channels above, more below; folders stay intact. Runs after Channel mode.
- Change: Off grid follows the project grid setting and shows the grid unit; edges 1 sample off the grid are snapped (inward to the next grid line).
- Change: off-grid edges zoom to one grid step either side; Save report asks where to save; no fold arrow in the title bar.
- Change: in the lists only the first column stretches; Track / Position / Take keep their width when a column is resized.

## 26.1015.1125

- Change: each check shows a short coloured title and a one-line description; colour = impact on the sound in an editing session (red print / delete, orange big change, yellow small change, green sound unchanged, grey review only), with a legend above the list.

## 26.1014.2216

- New: Session Fix - Interchange Prep, one window that checks and fixes a session before Interchanger (Pro Tools / Nuendo / Cubase).
- Removed: the five separate scripts (Edges Off Grid, Looped Source Items, Misaligned Crossfades, Overlap Items, Split Items at Fade Edges) - their checks are part of the new window. Re-assign shortcuts / toolbar buttons to the new script.
- Requires ReaImGui and the hsuanice Library package.

## 26.1012.1641

- Renamed to "Session Fix" (was "Fix Tools") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.0736

- First release in the hsuanice/ReaScripts repository.
- Known issue: Fix Edges Off Grid can also move crossfades when run on many items; a fix is planned (crossfades will be skipped).

