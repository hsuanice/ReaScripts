--[[
@description Session Fix - check and fix a REAPER session before moving it to Pro Tools, Nuendo or Cubase (Interchanger)
@version 26.1015.1303
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Session Fix - Interchange Prep.lua
@changelog
  - Add: Mixed channels can be fixed - one track per channel count as played ("<track> mono / stereo / 4ch ..."); the group with the most items stays on the original track, fewer channels above, more below; folders stay intact. Runs after Channel mode.
  - Change: Off grid follows the project grid setting and shows the grid unit; edges 1 sample off the grid are snapped (inward to the next grid line).
  - Change: off-grid edges zoom to one grid step either side; Save report asks where to save; no fold arrow in the title bar.
  - Change: in the lists only the first column stretches; Track / Position / Take keep their width when a column is resized.
@about
  # Session Fix

  Find and fix edit details that other DAWs handle differently when a REAPER session is
  converted (for example with Interchanger): one window, "Session Fix - Interchange Prep",
  with a checklist, automatic fixes, a before / after check of every fix and review tracks.

  Requires ReaImGui and the "hsuanice Library" package; js_ReaScriptAPI is optional.
--]]
-- This file only describes the package for ReaPack; it is not installed.
