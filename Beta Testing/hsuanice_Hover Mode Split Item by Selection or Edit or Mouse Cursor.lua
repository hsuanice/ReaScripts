--[[
@description Hover Mode - Split Item by Selection or Edit or Mouse Cursor
@version 0.1
@author hsuanice

@about
  Context-aware item splitting script that prioritizes razor area, time selection, and mouse/edit cursor logic.
  Follows snap-to-grid setting only when using mouse position.
  
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

  References:
    • TJF: Split Item (Hover Mode Dependant)
    • TJF: Hover Mode Toggle
    • LKC: HOVER EDIT - Toggle hovering
    • az: Smart split items by mouse cursor
    • ek: Smart split items by mouse cursor
@changelog
  v0.1 - Stable beta release. Supports Razor Area, Time Selection, Hover Mode, and Edit Cursor logic.
         Snap behavior matches other Hover Mode tools.
--]]

reaper.Undo_BeginBlock()

-- === Settings ===
local snap_enabled = reaper.GetToggleCommandState(1157) == 1 -- Snap to grid toggle
local hover_value = reaper.GetExtState("hsuanice_TrimTools", "HoverMode")
local hover_mode = (hover_value == "true" or hover_value == "1")

-- === Razor Edit Check ===
local razor_items = {}
local razor_found = false

for t = 0, reaper.CountTracks(0) - 1 do
  local track = reaper.GetTrack(0, t)
  local retval, razor = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)

  if razor ~= "" then
    razor_found = true
    for span in string.gmatch(razor, "[^%s]+") do
      local start, end_ = span:match("([%d%.]+) ([%d%.]+)")
      if start and end_ then
        start, end_ = tonumber(start), tonumber(end_)
        for i = 0, reaper.CountTrackMediaItems(track) - 1 do
          local item = reaper.GetTrackMediaItem(track, i)
          local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local item_end = pos + len
          if item_end > start and pos < end_ then
            table.insert(razor_items, item)
          end
        end
      end
    end
  end
end

-- === Split Razor Items ===
if razor_found then
  reaper.Main_OnCommand(40061, 0) -- Split at time selection
  for _, item in ipairs(razor_items) do
    reaper.SetMediaItemSelected(item, true)
  end
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
  end
  reaper.Undo_EndBlock("Split Razor Area and Keep Selection", -1)
  return
end

-- === Time Selection Split ===
local start_time, end_time = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
local has_selected_item = reaper.CountSelectedMediaItems(0) > 0

if start_time ~= end_time and has_selected_item then
  reaper.Main_OnCommand(40061, 0)
  reaper.Main_OnCommand(40289, 0)
  reaper.Undo_EndBlock("Split by Time Selection (no razor)", -1)
  return
end

-- === Determine Split Position ===
local window, segment, details = reaper.BR_GetMouseCursorContext()
local item = reaper.BR_GetMouseCursorContext_Item()
local use_mouse = hover_mode and window == "arrange" and details == "item" and segment ~= "timeline"

local split_pos
if use_mouse and item then
  local mouse_pos = reaper.BR_GetMouseCursorContext_Position()
  split_pos = snap_enabled and reaper.SnapToGrid(0, mouse_pos) or mouse_pos
else
  split_pos = reaper.GetCursorPosition() -- Raw, unsnapped
end

-- === Execute Split ===
if use_mouse and item then
  local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = item_start + item_len
  if split_pos > item_start and split_pos < item_end then
    local was_selected = reaper.IsMediaItemSelected(item)
    if not was_selected then reaper.SetMediaItemSelected(item, true) end

    local old_cursor = reaper.GetCursorPosition()
    reaper.SetEditCurPos(split_pos, false, false)
    reaper.Main_OnCommand(40757, 0)
    reaper.SetEditCurPos(old_cursor, false, false)

    if not was_selected then reaper.SetMediaItemSelected(item, false) end
    reaper.Main_OnCommand(40289, 0)
    reaper.Undo_EndBlock("Split under Mouse (snap if enabled)", -1)
    return
  end
end

-- === Fallback: Edit Cursor + Selected Track ===
local item_found = false
local selected_tracks = {}
for i = 0, reaper.CountSelectedTracks(0) - 1 do
  selected_tracks[reaper.GetSelectedTrack(0, i)] = true
end

for i = 0, reaper.CountMediaItems(0) - 1 do
  local item = reaper.GetMediaItem(0, i)
  local track = reaper.GetMediaItemTrack(item)
  if selected_tracks[track] then
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_start + item_len
    if split_pos > item_start and split_pos < item_end then
      reaper.SetMediaItemSelected(item, true)
      item_found = true
    end
  end
end

if item_found then
  reaper.SetEditCurPos(split_pos, false, false)
  reaper.Main_OnCommand(40757, 0)
end

reaper.Main_OnCommand(40289, 0)
reaper.Undo_EndBlock("Split by Edit Cursor + Selected Track", -1)
