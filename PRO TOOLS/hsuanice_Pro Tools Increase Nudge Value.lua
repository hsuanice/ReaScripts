-- @description hsuanice_Pro Tools Increase Nudge Value
-- @version 0.3.0 [260419.0934]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Increases nudge value to next preset in current mode. Stops at list boundary.
--   Mac shortcut (PT): Option + Shift + =
--   Tags: Editing
-- @changelog
--   0.3.0 [260419.0934] - Remove tooltip (blocks rapid switching)
--   0.2.0 [260419.0921] - Cleaner GFX tooltip
--   0.1.0 [260418.1534] - Initial release

local r = reaper
local info = debug.getinfo(1, 'S')
local dir = info.source:match('^@(.*[/\\])') or ''
local ok, Nudge = pcall(dofile, dir .. 'hsuanice_PT_Nudge.lua')
if not ok then return end

Nudge.increase()
r.defer(function() end)
