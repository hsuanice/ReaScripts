--[[
@description Fade Tool - Crossfade in Razor (fit one cut to the razor area, or crossfade every cut inside it)
@version 26.1023.1958pre1
@author hsuanice
@noindex
@changelog
  - Add: an item start or end inside the razor area without a neighbour gets a plain fade over the area.
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
  - An item start or end inside the area without a neighbour: a plain fade-in / fade-out over
    the area (Fade shape from Settings, Linear by default).

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
  local changed, skipped, touched = FT.fade_areas(areas, S)
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
