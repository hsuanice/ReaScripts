# hsuanice_Session Fix.lua — Changelog

(formerly `hsuanice_Fix Tools.lua`)

Fix Tools - clean up edits before moving a REAPER session to Pro Tools or Nuendo

## 26.1018.1239

- Add: Workflow cues (last check) - removes the #in / #out / #Glue cues that glue / render leave in WAV files, only for files inside the session folder, in place (same file, audio untouched); other cues, take markers and project markers stay. Asks first (cannot be undone with Undo).
- Add: Scan shows a progress bar with Cancel instead of freezing REAPER, and the time of each check (the slowest are shown).
- Add: Tiny items check - editing slivers under 2 frames for review; 2-pops (xx:59:58:00 or after the last audio) are recognized and left out.
- Add: Tiny items - mark tail pops as 2-pop from the list, or write "2-pop" / "tail pop" in the Item Notes, so they are left out.

## 26.1015.1425

- Fix: list columns were squeezed and jumped back when resized; columns now keep their width and the list scrolls sideways when it is wider than the window.
- Add: lists can be sorted - click a column header (up / down / original order); Shift+click selects a range in the order shown.
- Fix: Fix on Fade shapes missed fades on hidden tracks / inside collapsed folders (only Fix All reached them); they are fixed now.
- Change: Folders comes right after Hidden tracks; the title bar and its close button use the chosen font size.
- Fix: a broken crossfade (fades not matching the overlap) could not get its shape and was set to an invalid value; it is now marked "fix Crossfades first" and left alone until Crossfades has fixed it.
- Add: issues that need another check first (hidden tracks / collapsed folders, broken crossfades) show it in colour in front; fixing such a check alone asks to fix that first (Yes = first that, then this check).

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

