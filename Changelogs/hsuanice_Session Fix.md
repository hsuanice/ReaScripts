# hsuanice_Session Fix.lua — Changelog

(formerly `hsuanice_Fix Tools.lua`)

Fix Tools - clean up edits before moving a REAPER session to Pro Tools or Nuendo

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

