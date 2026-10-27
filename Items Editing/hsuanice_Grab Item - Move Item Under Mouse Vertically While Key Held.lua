--[[
@description Grab Item - Move Item Under Mouse Vertically While Key Held (keeps the timeline position)
@version 26.1027.1547
@author hsuanice
@noindex
@changelog
  - Release: tested in REAPER.
@about
  Vertical-only variant of Grab Item - Move Item Under Mouse While Key Held: the item keeps
  its timeline position and only follows the mouse across tracks. See that script for details.
--]]
-- Runs the main Grab Item script (same folder) in vertical-only mode
GRAB_ITEM_VERTICAL = true
local dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
dofile(dir .. "hsuanice_Grab Item - Move Item Under Mouse While Key Held.lua")
