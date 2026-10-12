--[[
@description Fix Tools - clean up edits before moving a REAPER session to Pro Tools or Nuendo
@version 26.1012.0736
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Fix Edges Off Grid.lua
  [main] hsuanice_Fix Looped Source Items.lua
  [main] hsuanice_Fix Misaligned Crossfades.lua
  [main] hsuanice_Fix Overlap Items Partial or Complete.lua
  [main] hsuanice_Fix Split Items at Fade Edges.lua
@changelog
  - First release in the hsuanice/ReaScripts repository.
  - Known issue: Fix Edges Off Grid can also move crossfades when run on many items; a fix is planned (crossfades will be skipped).
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  # Fix Tools

  Find and fix edit details that other DAWs handle differently when a REAPER session is exported.

  - Fix Edges Off Grid
  - Fix Looped Source Items
  - Fix Misaligned Crossfades
  - Fix Overlap Items (partial or complete)
  - Fix Split Items at Fade Edges
--]]
-- This file only describes the package for ReaPack; it is not installed.
