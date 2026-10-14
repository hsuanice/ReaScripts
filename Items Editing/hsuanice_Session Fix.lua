--[[
@description Session Fix - check and fix a REAPER session before moving it to Pro Tools, Nuendo or Cubase (Interchanger)
@version 26.1014.2216
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Session Fix - Interchange Prep.lua
@changelog
  - New: Session Fix - Interchange Prep, one window that checks and fixes a session before Interchanger (Pro Tools / Nuendo / Cubase).
  - Removed: the five separate scripts (Edges Off Grid, Looped Source Items, Misaligned Crossfades, Overlap Items, Split Items at Fade Edges) - their checks are part of the new window. Re-assign shortcuts / toolbar buttons to the new script.
  - Requires ReaImGui and the hsuanice Library package.
@about
  # Session Fix

  Find and fix edit details that other DAWs handle differently when a REAPER session is
  converted (for example with Interchanger): one window, "Session Fix - Interchange Prep",
  with a checklist, automatic fixes, a before / after check of every fix and review tracks.

  Requires ReaImGui and the "hsuanice Library" package; js_ReaScriptAPI is optional.
--]]
-- This file only describes the package for ReaPack; it is not installed.
