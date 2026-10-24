--[[
@description Fade Tool - Scene Cut to Razor (trim or extend the edge items to the scene with transition fades)
@version 26.1024.1910
@author hsuanice
@noindex
@changelog
  - Add: no razor - select the items to cut and the scene they cover completely on the "Scene Cut" track is used (partly covered scenes do not count; several whole scenes are listed, not guessed). Razor still wins.
  - Release: tested in REAPER 7.82.
@about
  The scene comes from the razor edit area, or - with no razor - from the "Scene Cut" track:
  select the items to cut (they must cover the whole scene, start to end) and the scene
  they cover completely is used. A scene they only partly cover does not count; covering
  several whole scenes is listed instead of guessed. Unselected items are never changed.

  Per track (and per fixed lane):
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
  Mode support, hold-and-drag crossfade edges and Scene Cut.
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

local SCENE_TRACK_NAME = "Scene Cut"

local S, fl, fin_len, fout_len
local skipped, changed = {}, 0
local function skip(tr, t, why)
  skipped[#skipped + 1] = string.format("%s @ %s: %s", FT.track_name(tr), FT.fmt_time(t), why)
end

-- Scene [rs, re] on one track / lane: trim or extend the first and the last of the items
-- in list (sorted by position) that overlap the scene, with the transition fades
local function cut_scene(tr, list, rs, re)
  local new_s = FT.aligned_range(rs, fin_len, S.scene_in_align)
  local _, new_e = FT.aligned_range(re, fout_len, S.scene_out_align)
  -- only items that really overlap the scene (not just touching its edges)
  local first, last
  for _, info in ipairs(list) do
    if info.pos < re - FT.TOL and info.fin > rs + FT.TOL then
      if not first then first = info end
      if not last or info.fin > last.fin then last = info end
    end
  end
  if not first then return end

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
    skip(tr, rs, why_s)
  end
  if e_ok then
    FT.set_end(last.item, new_e)
    FT.set_fade(last.item, "OUT", fout_len, S.scene_shape, false)
    changed = changed + 1
  else
    skip(tr, re, why_e)
  end
end

-- Razor areas are the scenes
local function razor_scenes(areas)
  local touched = {}
  for _, area in ipairs(areas) do
    touched[area.track] = true
    for _, list in pairs(FT.lane_items(area, area.s, area.e)) do
      cut_scene(area.track, list, area.s, area.e)
    end
  end
  if changed > 0 and S.clear_razor == 1 then FT.clear_razors(touched) end
end

-- The Scene Cut track and its folder children (work logs): never cut there
local function scene_folder()
  local folder, scene_track = {}, nil
  local depth = 0
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if scene_track then
      if depth <= 0 then break end
      folder[tr] = true
      depth = depth + r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    elseif FT.track_name(tr) == SCENE_TRACK_NAME then
      scene_track, folder[tr] = tr, true
      depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
    end
  end
  return scene_track, folder
end

-- No razor: the selected items of each track (and fixed lane) are cut to the scene of the
-- Scene Cut track that they cover completely (start to end). A scene they only partly
-- cover does not count; covering several whole scenes is listed instead of guessed.
local function selection_scenes()
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then return end
  local scene_track, folder = scene_folder()
  if not scene_track then
    skipped[#skipped + 1] = 'No "' .. SCENE_TRACK_NAME .. '" track: use a razor area as the scene.'
    return
  end
  local scenes = {}
  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local info = FT.info(r.GetTrackMediaItem(scene_track, i))
    local take = r.GetActiveTake(info.item)
    info.name = take and r.GetTakeName(take) or ""
    scenes[#scenes + 1] = info
  end

  local groups, order = {}, {}
  for i = 0, n - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    local tr = r.GetMediaItem_Track(it)
    if not folder[tr] then
      local lane = r.GetMediaItemInfo_Value(it, "I_FIXEDLANE")
      local key = tostring(tr) .. "|" .. lane
      if not groups[key] then groups[key] = { track = tr, list = {} }; order[#order + 1] = key end
      table.insert(groups[key].list, FT.info(it))
    end
  end

  for _, key in ipairs(order) do
    local g = groups[key]
    table.sort(g.list, function(a, b) return a.pos < b.pos end)
    local s0, e0 = math.huge, -math.huge
    for _, info in ipairs(g.list) do s0, e0 = math.min(s0, info.pos), math.max(e0, info.fin) end
    local covered = {}
    for _, sc in ipairs(scenes) do
      if s0 <= sc.pos + FT.TOL and e0 >= sc.fin - FT.TOL then covered[#covered + 1] = sc end
    end
    if #covered == 1 then
      cut_scene(g.track, g.list, covered[1].pos, covered[1].fin)
    elseif #covered == 0 then
      skip(g.track, s0, "the selected items do not cover a whole scene")
    else
      local names = {}
      for _, sc in ipairs(covered) do names[#names + 1] = sc.name end
      skip(g.track, s0, "the selected items cover several whole scenes (" .. table.concat(names, ", ")
        .. "); select fewer items or use a razor area")
    end
  end
end

local function main()
  S = FT.load_settings()
  fl = FT.frame_len()
  fin_len, fout_len = S.scene_in_frames * fl, S.scene_out_frames * fl
  local areas = FT.get_razor_areas()
  if #areas > 0 then razor_scenes(areas) else selection_scenes() end
  return changed, skipped
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
local changed, skipped = main()
r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock(TITLE, -1)
if skipped then FT.report(TITLE, skipped) end
