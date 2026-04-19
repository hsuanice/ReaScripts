-- @description hsuanice_Pro Tools Increase Grid Value
-- @version 0.2.0 [260419.0934]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Increases grid to next larger division. Stops at list boundary.
--   Mac shortcut (PT): Shift + =
--   Tags: Editing
-- @changelog
--   0.2.0 [260419.0934] - Remove tooltip (blocks rapid switching)
--   0.1.0 [260419.0921] - Initial release

local r = reaper

local GRIDS = {
  {label='1/128', value=1/128},
  {label='1/64',  value=1/64},
  {label='1/32T', value=1/(32*1.5)},
  {label='1/32',  value=1/32},
  {label='1/16T', value=1/(16*1.5)},
  {label='1/16',  value=1/16},
  {label='1/8T',  value=1/(8*1.5)},
  {label='1/8',   value=1/8},
  {label='1/4T',  value=1/(4*1.5)},
  {label='1/4',   value=1/4},
  {label='1/2',   value=1/2},
  {label='1',     value=1},
  {label='2',     value=2},
  {label='4',     value=4},
}

if r.GetToggleCommandState(40904) == 1 then r.defer(function() end); return end
local _, grid_div, swing = r.GetSetProjectGrid(0, 0)
if swing == 3 then r.defer(function() end); return end

local cur_idx = 1
local best_d = math.huge
for i, g in ipairs(GRIDS) do
  local d = math.abs(grid_div - g.value)
  if d < best_d then best_d = d; cur_idx = i end
end

local new_idx = math.min(cur_idx + 1, #GRIDS)
r.GetSetProjectGrid(0, 1, GRIDS[new_idx].value)
r.defer(function() end)
