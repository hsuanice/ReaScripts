--[[
@description Fade Tool - Crossfade in Razor (fit one cut to the razor area, or crossfade every cut inside it)
@version 26.1023.1800pre1
@author hsuanice
@noindex
@changelog
  - Initial release.
@about
  Works only on razor edit areas (tracks and time range of each area). Never opens a window
  unless something had to be skipped.

  Per track (and per fixed lane) inside each razor area:
  - One cut in the area: the crossfade fills the razor area exactly.
  - No cut in the area: the nearest cut inside the visible arrange view is moved into the
    area and crossfaded over it (no need to move the cut first). Two equally near cuts are
    reported instead of guessed.
  - Two or more cuts in the area: every cut gets the default crossfade
    (length in frames and position before / center / after the cut, from Fade Tool - Settings).

  Items are trimmed or extended as needed; an item without enough source handle, or a locked
  item, is skipped and listed. Default crossfade shape: Equal Power.

  Design inspired by AZ's "Fade tool (work on context of mouse, razor or time selection)"
  (ReaTeam Scripts).
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Fade Tool Core.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

local r = reaper
local FT = dofile(r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Fade Tool Core.lua")
local TITLE = "Fade Tool - Crossfade in Razor"

local function main()
  local areas = FT.get_razor_areas()
  if #areas == 0 then return end
  local S = FT.load_settings()
  local fl = FT.frame_len()
  local view_s, view_e = r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  local skipped, touched, changed = {}, {}, 0

  local function skip(area, t, why)
    skipped[#skipped + 1] = string.format("%s @ %s: %s", FT.track_name(area.track), FT.fmt_time(t), why)
  end
  local function apply(area, c, xs, xe)
    local ok, why = FT.crossfade(c.a, c.b, xs, xe, S.xfade_shape)
    if ok then changed = changed + 1 else skip(area, xs, why) end
  end

  for _, area in ipairs(areas) do
    touched[area.track] = true
    local rs, re = area.s, area.e
    local lanes = FT.lane_items(area, math.min(rs, view_s), math.max(re, view_e))
    for _, list in pairs(lanes) do
      local inside, outside = {}, {}
      for _, c in ipairs(FT.find_cuts(list)) do
        if c.je >= rs - FT.TOL and c.js <= re + FT.TOL then
          inside[#inside + 1] = c
        elseif c.je >= view_s and c.js <= view_e then
          outside[#outside + 1] = c
        end
      end

      if #inside == 1 then
        apply(area, inside[1], rs, re)
      elseif #inside >= 2 then
        local len = S.xfade_frames * fl
        for _, c in ipairs(inside) do
          local xs, xe = FT.aligned_range(c.cut, len, S.xfade_align)
          apply(area, c, xs, xe)
        end
      elseif #outside > 0 then
        -- distance from each cut to the razor area; nearest wins, a tie is reported
        local best, best_d, tie
        for _, c in ipairs(outside) do
          local d = (c.js > re) and (c.js - re) or (rs - c.je)
          if not best or d < best_d - FT.TOL then
            best, best_d, tie = c, d, false
          elseif math.abs(d - best_d) <= FT.TOL then
            tie = true
          end
        end
        if tie then
          skip(area, rs, "two cuts are equally near; put the razor over the one you want")
        else
          apply(area, best, rs, re)
        end
      end
    end
  end

  if changed > 0 and S.clear_razor == 1 then FT.clear_razors(touched) end
  return changed, skipped
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
local changed, skipped = main()
r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock(TITLE, -1)
if skipped then FT.report(TITLE, skipped) end
