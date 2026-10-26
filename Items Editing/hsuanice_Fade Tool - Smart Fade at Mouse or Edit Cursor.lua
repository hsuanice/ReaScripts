--[[
@description Fade Tool - Smart Fade at Mouse or Edit Cursor (razor, time selection, mouse top / bottom / label, Hover Mode aware)
@version 26.1026.1232
@author hsuanice
@noindex
@changelog
  - Add: a razor area inside an item with no neighbour on either side fades in from the item start to the area start and fades out from the area end to the item end (as AZ's Fade tool). An item with a neighbour still gets its nearest cut pulled into the area.
  - Release: tested in REAPER 7.82.
@about
  One shortcut for fades and crossfades. Never opens a window unless something had to be
  skipped. The first context that applies wins:

  1. Razor edit areas: same as Fade Tool - Crossfade in Razor (one cut -> crossfade fills
     the area, several cuts -> default crossfade on each, no cut -> plain fade on a free item
     edge in the area, else the nearest visible cut is pulled in).
  2. Time selection + selected tracks: the same, using the time selection on every selected
     track (can be turned off in Fade Tool - Settings).
  3. Hover Mode ON (toggle: Hover Editing - Toggle Hover Mode), at the mouse:
     - top half: fade-in from the item start to the mouse
     - bottom half: fade-out from the mouse to the item end
     - item name bar (labels drawn above items): move the nearest crossfade of the item so it
       is centered on the mouse (length and shape kept)
     - empty arrange space: open Fade Tool - Settings
     If the item under the mouse is selected, the fade goes to every selected item under the
     mouse position. The mouse position follows Snap (e.g. a 1-frame grid).
  4. Hover Mode OFF (or the mouse on the ruler / TCP), at the edit cursor, on the selected
     items under it (or the items on the selected tracks):
     - mouse left of the edit cursor: fade-in to the cursor
     - mouse right of the edit cursor: fade-out from the cursor
     - mouse on an item name bar: move its nearest crossfade, centered on the cursor
     - mouse outside the arrange view or within 3 pixels of the cursor: the nearer item edge

  Plain fades never touch a crossfade: a crossfaded edge, or a position inside a crossfade,
  is left alone. Crossfades are changed by razor, the name bar, or hold-and-drag:

  Hold the shortcut (needs js_ReaScriptAPI) with the mouse within 1 frame (at least 4 pixels)
  of a crossfade edge to grab that edge, or on the item name bar / inside a crossfade to grab
  the whole crossfade; it follows the mouse (and Snap) until the key is released, one undo
  point. The two edges stop 1 frame apart. Hold Cmd (Ctrl on Windows) while dragging to
  invert Snap: free fine-tuning when Snap is on, grid snapping when it is off. A short press
  without moving the mouse is a normal Smart Fade.

  Never changes anything outside the arrange view: the razor / time selection part outside
  it, tracks scrolled out of view and an edit cursor outside the view are ignored.
  Plain fades use the Fade shape from Settings (Linear by default), new crossfades the
  Crossfade shape (Equal Power by default).

  Requires SWS (mouse timeline position) for Hover Mode; without it the edit cursor is used.

  Credits: heavily based on AZ's "Fade tool (work on context of mouse, razor or time
  selection)" (ReaTeam Scripts) by AZ - https://forum.cockos.com/member.php?u=135221 ,
  forum thread https://forum.cockos.com/showthread.php?t=293335 . Fade Tool follows its design
  closely: the context order (razor, time selection, mouse), top half = fade-in / bottom half
  = fade-out, the item name bar moving a crossfade (including AZ's way of detecting the name
  bar), razor crossfades and razor fades. The code is a new implementation by hsuanice with
  AI (Claude Code), with hsuanice's changes: frame-based defaults, no pop-up windows, Hover
  Mode support, hold-and-drag crossfade edges and Scene Cut.

  Hold-the-shortcut detection follows Sexan's "VT_SWIPE to Comp HOLD" (Virtual Track,
  Sexan_Scripts).
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
local SIDE_PX = 3   -- mouse closer than this to the edit cursor = no side
local GRAB_PX = 4   -- minimum grab distance; the normal one is 1 frame
local skipped = {}
local function skip(info, t, why)
  skipped[#skipped + 1] = string.format("%s @ %s: %s",
    FT.track_name(r.GetMediaItem_Track(info.item)), FT.fmt_time(t), why)
end

local function px_to_sec(px) return px / math.max(r.GetHZoomLevel(), 1e-6) end
-- on: true / false forces snapping on or off; nil follows the project's Snap setting
local function snap(t, on)
  local project_on = r.GetToggleCommandState(1157) == 1
  if on == nil then on = project_on end
  if t and on then
    if not project_on and r.BR_GetClosestGridDivision then return r.BR_GetClosestGridDivision(t) end
    return r.SnapToGrid(0, t)
  end
  return t
end

-- Cmd (macOS) / Ctrl (Windows) held right now
local function cmd_down()
  return r.JS_Mouse_GetState and (r.JS_Mouse_GetState(4) & 4) == 4
end
local function mouse_time()
  if r.BR_PositionAtMouseCursor then
    local t = r.BR_PositionAtMouseCursor(false)
    if t and t >= 0 then return t end
  end
  return nil
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

-- Visible crossfades of an item: list of { a = left info, b = right info }
local function item_crossfades(info)
  local list = {}
  local left = FT.xfade_neighbour(info, "left")
  if left and FT.in_view(info.pos, left.fin) then list[#list + 1] = { a = left, b = info } end
  local right = FT.xfade_neighbour(info, "right")
  if right and FT.in_view(right.pos, info.fin) then list[#list + 1] = { a = info, b = right } end
  return list
end

local function nearest_crossfade(info, t)
  local best, best_d
  for _, x in ipairs(item_crossfades(info)) do
    local d = math.abs(t - (x.b.pos + x.a.fin) / 2)
    if not best_d or d < best_d then best, best_d = x, d end
  end
  return best
end

-- Name bar: center the item's nearest visible crossfade on t
local function move_nearest(it, t)
  local info = FT.info(it)
  local x = nearest_crossfade(info, t)
  if not x then skip(info, t, "no crossfade on this item") return end
  local ok, why = FT.move_crossfade(x.a, x.b, t)
  if not ok then skip(info, t, why) end
end

local function side_fades(items, t, side_of)
  for _, it in ipairs(items) do
    local info = FT.info(it)
    if t > info.pos + FT.TOL and t < info.fin - FT.TOL
      and FT.track_visible(r.GetMediaItem_Track(it)) then
      local ok, why = FT.side_fade(info, t, side_of(info), S)
      if not ok then skip(info, t, why) end
    end
  end
end

-- Context 3: Hover Mode. Mouse over an item: top = "in", bottom = "out", name bar = move.
-- Over empty arrange space: open Fade Tool - Settings.
local function mouse_context(t)
  local it, part = FT.mouse_item_part()
  if not it then return "settings" end
  if part == "label" then move_nearest(it, t) return end
  local items = { it }
  if r.IsMediaItemSelected(it) and r.CountSelectedMediaItems(0) > 1 then
    items = {}
    for i = 0, r.CountSelectedMediaItems(0) - 1 do items[#items + 1] = r.GetSelectedMediaItem(0, i) end
  end
  local side = (part == "top") and "in" or "out"
  side_fades(items, t, function() return side end)
end

-- Mouse side of the edit cursor in the arrange view: "in" (left), "out" (right) or nil
local function mouse_side(t)
  if not r.BR_GetMouseCursorContext then return nil end
  if r.BR_GetMouseCursorContext() ~= "arrange" then return nil end
  local m = r.BR_GetMouseCursorContext_Position()
  if not m then return nil end
  if m < t - px_to_sec(SIDE_PX) then return "in" end
  if m > t + px_to_sec(SIDE_PX) then return "out" end
  return nil
end

-- Context 4: edit cursor (Hover Mode off). Mouse left of the cursor = "in", right = "out",
-- on an item name bar = move its nearest crossfade to the cursor; else the nearer edge.
local function cursor_context(t)
  if not FT.in_view(t) then return end
  local side = mouse_side(t)
  if side then
    local it, part = FT.mouse_item_part()
    if it and part == "label" then move_nearest(it, t) return end
  end
  local items = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do items[#items + 1] = r.GetSelectedMediaItem(0, i) end
  if #items == 0 then
    for i = 0, r.CountSelectedTracks(0) - 1 do
      local tr = r.GetSelectedTrack(0, i)
      for j = 0, r.CountTrackMediaItems(tr) - 1 do items[#items + 1] = r.GetTrackMediaItem(tr, j) end
    end
  end
  side_fades(items, t, function(info)
    return side or ((t - info.pos <= info.fin - t) and "in" or "out")
  end)
end

-- Short press: the normal Smart Fade, one undo point
local function tap()
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local result
  if not areas_context() then
    local t, is_hover = H.resolve_target_pos()
    if is_hover and t then
      result = mouse_context(snap(t))
    else
      cursor_context(r.GetCursorPosition())
    end
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock(TITLE, -1)
  FT.report(TITLE, skipped)
  if result == "settings" then
    local dir = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
    dofile(dir .. "hsuanice_Fade Tool - Settings.lua")
  end
end

-- What a held key would grab at the mouse: { mode = "start" | "end" | "move", a, b } or nil
local function grab_target(t)
  local it, part = FT.mouse_item_part()
  if not it then return nil end
  local info = FT.info(it)
  if part == "label" then
    local x = nearest_crossfade(info, t)
    return x and { mode = "move", a = x.a, b = x.b }
  end
  local reach = math.max(FT.frame_len(), px_to_sec(GRAB_PX))
  local best, best_d
  for _, x in ipairs(item_crossfades(info)) do
    local ds, de = math.abs(t - x.b.pos), math.abs(t - x.a.fin)
    if ds <= reach and (not best_d or ds < best_d) then best, best_d = { mode = "start", a = x.a, b = x.b }, ds end
    if de <= reach and (not best_d or de < best_d) then best, best_d = { mode = "end", a = x.a, b = x.b }, de end
    if not best and t > x.b.pos and t < x.a.fin then best = { mode = "move", a = x.a, b = x.b } end
  end
  return best
end

-- Hold-and-drag: follow the mouse until every key is released (pattern from Sexan's
-- "VT_SWIPE to Comp HOLD": JS_VKeys state since launch, keys intercepted meanwhile)
local VK_LO, VK_HI = 8, 0xFE
-- Modifier keys do not keep a drag alive: Shift, Ctrl, Alt, Win (left / right variants)
local VK_MOD = { [0x10] = true, [0x11] = true, [0x12] = true, [0x5B] = true, [0x5C] = true,
  [0xA0] = true, [0xA1] = true, [0xA2] = true, [0xA3] = true, [0xA4] = true, [0xA5] = true }
local CMD_GRACE = 0.2  -- Cmd released this short before the shortcut keeps the free position

local function hold(grab, t0)
  local start = r.time_precise()
  local fl = FT.frame_len()
  local xs0, xe0 = grab.b.pos, grab.a.fin
  local moved, intercepted = false, true
  local project_snap = r.GetToggleCommandState(1157) == 1
  local cmd0 = cmd_down()  -- Cmd that is part of the shortcut itself does not count
  local inverted, cmd_up_at = false, nil
  local function release_keys()
    if intercepted then intercepted = false; r.JS_VKeys_Intercept(-1, -1) end
  end
  local function shortcut_down()
    local st = r.JS_VKeys_GetState(start - 0.5)
    for vk = VK_LO, VK_HI do
      if not VK_MOD[vk] and st:byte(vk) ~= 0 then return true end
    end
    return false
  end
  r.JS_VKeys_Intercept(-1, 1)
  r.atexit(release_keys)

  local function step()
    -- releasing the shortcut ends the drag where it is (no new position on that frame)
    if not shortcut_down() then
      release_keys()
      if moved then r.Undo_OnStateChange(TITLE .. " (drag crossfade)") else tap() end
      return
    end
    -- Cmd / Ctrl inverts Snap (snap on -> free fine-tune, snap off -> grid); after Cmd is
    -- released the snap comes back only once CMD_GRACE has passed
    local now = r.time_precise()
    if cmd_down() ~= cmd0 then
      inverted, cmd_up_at = true, nil
    elseif inverted then
      cmd_up_at = cmd_up_at or now
      if now - cmd_up_at >= CMD_GRACE then inverted = false end
    end
    local t = snap(mouse_time(), project_snap ~= inverted)
    if t and math.abs(t - t0) > 1e-9 then moved = true end
    if moved and t then
      local xs, xe = xs0, xe0
      if grab.mode == "start" then xs = math.min(t, xe0 - fl)
      elseif grab.mode == "end" then xe = math.max(t, xs0 + fl)
      else xs, xe = xs0 + (t - t0), xe0 + (t - t0) end
      r.PreventUIRefresh(1)
      FT.crossfade(FT.info(grab.a.item), FT.info(grab.b.item), xs, xe, nil)  -- invalid = stays
      r.PreventUIRefresh(-1)
      r.UpdateArrange()
    end
    r.defer(step)
  end
  step()
end

local function main()
  if r.JS_VKeys_GetState and #FT.get_razor_areas() == 0
    and not (S.use_ts == 1 and FT.time_selection_areas()) then
    local t0 = snap(mouse_time())
    local grab = t0 and grab_target(t0)
    if grab then hold(grab, t0) return end
  end
  tap()
end

main()
