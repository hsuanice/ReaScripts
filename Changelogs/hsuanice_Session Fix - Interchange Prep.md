# hsuanice_Session Fix - Interchange Prep.lua — Changelog

Session Fix - Interchange Prep: check and fix a REAPER session before converting it with Interchanger

## 26.1015.1425

- Fix: list columns were squeezed and jumped back when resized; columns now keep their width and the list scrolls sideways when it is wider than the window.
- Add: lists can be sorted - click a column header (up / down / original order); Shift+click selects a range in the order shown.
- Fix: Fix on Fade shapes missed fades on hidden tracks / inside collapsed folders (only Fix All reached them); they are fixed now.
- Change: Folders comes right after Hidden tracks; the title bar and its close button use the chosen font size.
- Fix: a broken crossfade (fades not matching the overlap) could not get its shape and was set to an invalid value; it is now marked "fix Crossfades first" and left alone until Crossfades has fixed it.
- Add: issues that need another check first (hidden tracks / collapsed folders, broken crossfades) show it in colour in front; fixing such a check alone asks to fix that first (Yes = first that, then this check).

## 26.1015.1303

- Add: Mixed channels can be fixed - one track per channel count as played ("<track> mono / stereo / 4ch ..."); the group with the most items stays on the original track, fewer channels above, more below; folders stay intact. Runs after Channel mode.
- Change: Off grid (was Frame grid) follows the project grid setting (frames, beats ... as set in REAPER; needs SWS, otherwise the frame grid) and shows the current grid unit.
- Fix: an edge 1 sample off the grid (e.g. a file whose TimeReference is 1 sample late) was listed but never snapped; it is trimmed inward to the next grid line now.
- Change: clicking an off-grid edge zooms to one grid step either side of it.
- Change: Save report asks where to save (default: the session folder; needs js_ReaScriptAPI, otherwise the session folder).
- Change: the title bar has no fold arrow any more.
- Change: in the lists only the first column stretches; Track / Position / Take keep their width when a column is resized.

## 26.1015.1125

- Change: each check shows a short coloured title and a one-line description; colour = impact on the sound in an editing session (red print / delete, orange big change, yellow small change, green sound unchanged, grey review only), with a legend above the list.

## 26.1014.2216

- First release: one window replaces the five Session Fix scripts (Edges Off Grid, Looped Source Items, Misaligned Crossfades, Overlap Items, Split Items at Fade Edges).
- Developed and tested with hsuanice in Beta Testing from 2026-10-13 to 2026-10-14 (scan, fixes, Fix All, before / after audit, review tracks, razor highlight and zoom).
