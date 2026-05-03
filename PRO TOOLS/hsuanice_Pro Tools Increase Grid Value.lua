-- @description hsuanice_Pro Tools Increase Grid Value
-- @version 0.4.0 [260503.1314]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Increases grid to next larger value within the current mode
--   (Measure / Min:Secs / Timecode / Feet+Frames / Samples).
--   Mode and current preset are read from the Grid Nudge Panel ExtState.
--   Mac shortcut (PT): Shift + =
--   Tags: Editing
-- @changelog
--   0.4.0 [260503.1314] - Use shared hsuanice_PT_Grid.lua library; supports all 5 modes
--   0.3.0 [260502.1928] - Honor Timecode grid mode from Grid Nudge Panel
--   0.2.0 [260419.0934] - Remove tooltip (blocks rapid switching)
--   0.1.0 [260419.0921] - Initial release

local r = reaper
local info = debug.getinfo(1, 'S')
local dir = info.source:match('^@(.*[/\\])') or ''
local ok, Grid = pcall(dofile, dir .. 'hsuanice_PT_Grid.lua')
if not ok or type(Grid) ~= 'table' then return end

-- Frame grid (40904) is special — only Measure-style nav makes sense there
if r.GetToggleCommandState(40904) == 1 then r.defer(function() end); return end

Grid.increase()
r.defer(function() end)
