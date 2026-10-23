--[[
@description Fade Tool - Smart Fade at Mouse or Edit Cursor (razor, time selection, mouse top / bottom / label, Hover Mode aware)
@version 26.1023.1958pre1
@author hsuanice
@noindex
@changelog
  - Initial release.
@about
  One shortcut for fades and crossfades. Never opens a window unless something had to be
  skipped. The first context that applies wins:

  1. Razor edit areas: same as Fade Tool - Crossfade in Razor (one cut -> crossfade fills
     the area, several cuts -> default crossfade on each, no cut -> plain fade on a free item
     edge in the area, else the nearest visible cut is pulled in).
  2. Time selection + selected tracks: the same, using the time selection on every selected
     track (can be turned off in Fade Tool - Settings).
  3. Hover Mode ON, mouse over an item (toggle: Hover Editing - Toggle Hover Mode):
     - top half: fade-in from the item start to the mouse
     - bottom half: fade-out from the mouse to the item end
     - item name bar (labels drawn above items): move the nearest crossfade of the item so it
       is centered on the mouse (length and shape kept)
     If the item under the mouse is selected, the fade goes to every selected item under the
     mouse position. The mouse position follows Snap (e.g. a 1-frame grid).
  4. Hover Mode OFF (or the mouse on the ruler / TCP): the edit cursor, on the selected items
     under it (or the items on the selected tracks): the nearer item edge decides fade-in or
     fade-out; inside a crossfade, the crossfade is centered on the cursor.

  A fade on a crossfaded edge stretches or shortens that crossfade instead of breaking it.
  Plain fades use the Fade shape from Settings (Linear by default), new crossfades the
  Crossfade shape (Equal Power by default).

  Requires SWS (mouse timeline position) for Hover Mode; without it the edit cursor is used.

  Design inspired by AZ's "Fade tool (work on context of mouse, razor or time selection)"
  (ReaTeam Scripts); the item name bar detection follows its probing technique.
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Fade Tool Core.lua', 'hsuanice_Hover.lua' }) do
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
local LIB = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/"
local FT = dofile(LIB .. "hsuanice_Fade Tool Core.lua")
local H = dofile(LIB .. "hsuanice_Hover.lua")
local TITLE = "Fade Tool - Smart Fade"

local S = FT.load_settings()
local skipped = {}
local function skip(info, t, why)
  skipped[#skipped + 1] = string.format("%s @ %s: %s",
    FT.track_name(r.GetMediaItem_Track(info.item)), FT.fmt_time(t), why)
end
local function run(fn, info, t)
  local ok, why = fn(info, t, S)
  if not ok then skip(info, t, why) end
end

-- Contexts 1 and 2: razor, then time selection + selected tracks
local function areas_context()
  local areas = FT.get_razor_areas()
  local is_razor = #areas > 0
  if not is_razor then
    areas = (S.use_ts == 1) and FT.time_selection_areas() or nil
    if not areas then return false end
  end
  local _, sk, touched = FT.fade_areas(areas, S)
  skipped = sk
  if is_razor and S.clear_razor == 1 then FT.clear_razors(touched) end
  return true
end

-- Nearest crossfade of info to t: returns left, right items or nil
local function nearest_crossfade(info, t)
  local best_a, best_b, best_d
  local left = FT.xfade_neighbour(info, "left")
  if left then best_a, best_b, best_d = left, info, math.abs(t - (info.pos + left.fin) / 2) end
  local right = FT.xfade_neighbour(info, "right")
  if right then
    local d = math.abs(t - (right.pos + info.fin) / 2)
    if not best_d or d < best_d then best_a, best_b = info, right end
  end
  return best_a, best_b
end

-- Context 3: Hover Mode, item under the mouse
local function mouse_context(t)
  local it, part = FT.mouse_item_part()
  if not it then return end
  local info = FT.info(it)
  if part == "label" then
    local a, b = nearest_crossfade(info, t)
    if not a then skip(info, t, "no crossfade on this item") return end
    local ok, why = FT.move_crossfade(a, b, t)
    if not ok then skip(info, t, why) end
    return
  end
  local fn = (part == "top") and FT.fade_in_to or FT.fade_out_from
  local targets = { info }
  if r.IsMediaItemSelected(it) and r.CountSelectedMediaItems(0) > 1 then
    targets = {}
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
      local o = FT.info(r.GetSelectedMediaItem(0, i))
      if t > o.pos + FT.TOL and t < o.fin - FT.TOL then targets[#targets + 1] = o end
    end
  end
  for _, o in ipairs(targets) do run(fn, o, t) end
end

-- Context 4: edit cursor
local function cursor_context(t)
  local function under(it)
    local o = FT.info(it)
    if t > o.pos + FT.TOL and t < o.fin - FT.TOL then return o end
  end
  local targets = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    targets[#targets + 1] = under(r.GetSelectedMediaItem(0, i))
  end
  if #targets == 0 then
    for i = 0, r.CountSelectedTracks(0) - 1 do
      local tr = r.GetSelectedTrack(0, i)
      for j = 0, r.CountTrackMediaItems(tr) - 1 do
        targets[#targets + 1] = under(r.GetTrackMediaItem(tr, j))
      end
    end
  end
  -- read every target before changing any (edges move during the pass)
  local done, jobs = {}, {}
  for _, o in ipairs(targets) do
    if not done[o.item] then
      local right = FT.xfade_neighbour(o, "right")
      if right and t > right.pos + FT.TOL then
        -- cursor inside a crossfade: center it on the cursor
        done[o.item], done[right.item] = true, true
        jobs[#jobs + 1] = { kind = "move", a = o, b = right }
      end
    end
  end
  for _, o in ipairs(targets) do
    if not done[o.item] then
      local left = FT.xfade_neighbour(o, "left")
      done[o.item] = true
      if left and t < left.fin - FT.TOL then
        if not done[left.item] then
          done[left.item] = true
          jobs[#jobs + 1] = { kind = "move", a = left, b = o }
        end
      else
        jobs[#jobs + 1] = { kind = (t - o.pos <= o.fin - t) and "in" or "out", o = o }
      end
    end
  end
  for _, j in ipairs(jobs) do
    if j.kind == "move" then
      local ok, why = FT.move_crossfade(FT.info(j.a.item), FT.info(j.b.item), t)
      if not ok then skip(j.a, t, why) end
    else
      run(j.kind == "in" and FT.fade_in_to or FT.fade_out_from, FT.info(j.o.item), t)
    end
  end
end

local function main()
  if areas_context() then return end
  local t, is_hover = H.resolve_target_pos()
  if is_hover and t then
    mouse_context(H.snap_in_true_hover(t, true))
  else
    cursor_context(r.GetCursorPosition())
  end
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
main()
r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock(TITLE, -1)
FT.report(TITLE, skipped)
