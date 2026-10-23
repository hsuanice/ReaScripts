--[[
@description Fade Tool - Scene Cut to Razor (trim or extend the edge items to the scene with transition fades)
@version 26.1023.2008pre1
@author hsuanice
@noindex
@changelog
  - Credits: written out in full - Fade Tool is heavily based on AZ's Fade tool (ReaTeam Scripts).
@about
  The razor edit area is the scene. Per track (and per fixed lane) inside each razor area:
  - The first item of the scene gets its start trimmed or extended to the scene start, plus a
    fade-in; the last item gets its end trimmed or extended to the scene end, plus a fade-out.
  - Items in between are never changed (e.g. a room tone built from several copied items).
  - Fade length (frames) and position (before / center / after the scene edge) come from
    Fade Tool - Settings. Default: 1-frame fade-in just before the scene start and 1-frame
    fade-out on the last frame of the scene, both Linear.

  An item without enough source handle, or a locked item, is skipped and listed.

  Credits: heavily based on AZ's "Fade tool (work on context of mouse, razor or time
  selection)" (ReaTeam Scripts) by AZ - https://forum.cockos.com/member.php?u=135221 ,
  forum thread https://forum.cockos.com/showthread.php?t=293335 . Fade Tool follows its design
  closely: the context order (razor, time selection, mouse), top half = fade-in / bottom half
  = fade-out, the item name bar moving a crossfade (including AZ's way of detecting the name
  bar), razor crossfades and razor fades. The code is a new implementation by hsuanice with
  AI (Claude Code), with hsuanice's changes: frame-based defaults, no pop-up windows, Hover
  Mode support, one-sided crossfade adjustment and Scene Cut.
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
local TITLE = "Fade Tool - Scene Cut to Razor"

local function main()
  local areas = FT.get_razor_areas()
  if #areas == 0 then return end
  local S = FT.load_settings()
  local fl = FT.frame_len()
  local fin_len, fout_len = S.scene_in_frames * fl, S.scene_out_frames * fl
  local skipped, touched, changed = {}, {}, 0

  local function skip(area, t, why)
    skipped[#skipped + 1] = string.format("%s @ %s: %s", FT.track_name(area.track), FT.fmt_time(t), why)
  end

  for _, area in ipairs(areas) do
    touched[area.track] = true
    local rs, re = area.s, area.e
    local new_s = FT.aligned_range(rs, fin_len, S.scene_in_align)
    local _, new_e = FT.aligned_range(re, fout_len, S.scene_out_align)
    for _, list in pairs(FT.lane_items(area, rs, re)) do
      -- only items that really overlap the scene (not just touching its edges)
      local first, last
      for _, info in ipairs(list) do
        if info.pos < re - FT.TOL and info.fin > rs + FT.TOL then
          if not first then first = info end
          if not last or info.fin > last.fin then last = info end
        end
      end

      if first then
        local same = (first == last)
        -- check both edges before changing anything
        local s_ok, e_ok, why_s, why_e = true, true, nil, nil
        if FT.is_locked(first.item) then s_ok, why_s = false, "locked item" end
        if FT.is_locked(last.item) then e_ok, why_e = false, "locked item" end
        if s_ok then
          local ok, miss = FT.can_set_edges(first.item, new_s, first.fin)
          if not ok then s_ok, why_s = false, string.format("first item needs %.3f s more handle", miss) end
        end
        if e_ok then
          local ok, miss = FT.can_set_edges(last.item, last.pos, new_e)
          if not ok then e_ok, why_e = false, string.format("last item needs %.3f s more handle", miss) end
        end
        if s_ok and not same and new_s >= first.fin - FT.TOL then
          s_ok, why_s = false, "first item would become empty"
        end
        if e_ok and not same and new_e <= last.pos + FT.TOL then
          e_ok, why_e = false, "last item would become empty"
        end

        if s_ok then
          FT.set_start(first.item, new_s)
          FT.set_fade(first.item, "IN", fin_len, S.scene_shape, false)
          changed = changed + 1
        else
          skip(area, rs, why_s)
        end
        if e_ok then
          FT.set_end(last.item, new_e)
          FT.set_fade(last.item, "OUT", fout_len, S.scene_shape, false)
          changed = changed + 1
        else
          skip(area, re, why_e)
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
