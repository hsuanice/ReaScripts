--[[
@description ReaImGui - Item Reposition Tool (Interval + Mode + Undo)
@version 0.1
@author hsuanice

@about
  A GUI tool for repositioning selected items with flexible options.  
  - Supports interval units: Seconds / Frames / Grid.  
  - Choose position from Item Start or End.  
  - Cross-track or per-track modes supported.  
  - Includes Undo / Redo buttons for keyboard-less workflows.  
  - Real-time adjustable via ImGUI with auto-resize.

  💡 Designed for precise spacing and layout control in complex editing sessions.  
    Integrates with hsuanice’s ReaImGui workflow tools for item/selection editing.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.  
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.1 - Beta release
--]]

-- ▼▼▼ Script body starts here ▼▼▼

local ctx = reaper.ImGui_CreateContext('Reposition Items Plus')
local font_scale = 1.0
local window_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()

local time_interval = 1.0
local interval_unit = "Seconds" 
local from_end = false
local cross_track_mode = false
local first_frame = true

local function get_grid_interval()
  local cursor_pos = reaper.GetCursorPosition()
  local snap1 = reaper.SnapToGrid(0, cursor_pos)
  local step = 0.0001
  for i = 1, 100000 do
    local test_pos = cursor_pos + step * i
    local snap2 = reaper.SnapToGrid(0, test_pos)
    if math.abs(snap2 - snap1) > 0.0000001 then
      return math.abs(snap2 - snap1)
    end
  end
  return 0.25 -- fallback
end

local function get_interval_seconds()
  if interval_unit == "Seconds" then
    return time_interval
  elseif interval_unit == "Frames" then
    local fps = reaper.TimeMap_curFrameRate(0)
    return time_interval / fps
  elseif interval_unit == "Grid" then
    return get_grid_interval() * time_interval
  end
end

local function reposition_items()
  local interval_sec = get_interval_seconds()
  local num_items = reaper.CountSelectedMediaItems(0)
  if num_items == 0 then return end

  reaper.Undo_BeginBlock()

  if cross_track_mode then
    local items = {}
    for i = 0, num_items - 1 do
      table.insert(items, reaper.GetSelectedMediaItem(0, i))
    end
    table.sort(items, function(a, b)
      local pa = reaper.GetMediaItemInfo_Value(a, "D_POSITION")
      local la = reaper.GetMediaItemInfo_Value(a, "D_LENGTH")
      local pb = reaper.GetMediaItemInfo_Value(b, "D_POSITION")
      local lb = reaper.GetMediaItemInfo_Value(b, "D_LENGTH")
      return (from_end and (pa + la) or pa) < (from_end and (pb + lb) or pb)
    end)

    if from_end then
      local pos = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION") + reaper.GetMediaItemInfo_Value(items[1], "D_LENGTH")
      for i = 2, #items do
        local item = items[i]
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local new_pos = pos + interval_sec
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
        pos = new_pos + len
      end
    else
      local pos = reaper.GetMediaItemInfo_Value(items[1], "D_POSITION")
      for i = 1, #items do
        local item = items[i]
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
        pos = pos + interval_sec
      end
    end

  else
    local track_table = {}
    for i = 0, num_items - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      local track = reaper.GetMediaItem_Track(item)
      track_table[track] = track_table[track] or {}
      table.insert(track_table[track], item)
    end

    for _, list in pairs(track_table) do
      table.sort(list, function(a, b)
        return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
      end)

      if from_end then
        local pos = reaper.GetMediaItemInfo_Value(list[1], "D_POSITION") + reaper.GetMediaItemInfo_Value(list[1], "D_LENGTH")
        for i = 2, #list do
          local item = list[i]
          local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local new_pos = pos + interval_sec
          reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
          pos = new_pos + len
        end
      else
        local pos = reaper.GetMediaItemInfo_Value(list[1], "D_POSITION")
        for i = 1, #list do
          local item = list[i]
          reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
          pos = pos + interval_sec
        end
      end
    end
  end

  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Reposition Items Plus", -1)
end

local function loop()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, 320, 140)
    first_frame = false
  end

  local visible, open = reaper.ImGui_Begin(ctx, 'Reposition Items', true, window_flags)
  if visible then
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then open = false end

    
    if reaper.ImGui_Button(ctx, "Undo") then
      reaper.Main_OnCommand(40029, 0)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Redo") then
      reaper.Main_OnCommand(40030, 0)
    end

    
    reaper.ImGui_SetNextItemWidth(ctx, 112)
    local _, val = reaper.ImGui_InputDouble(ctx, "Interval", time_interval, 1.0, 1.0, "%.2f")
    time_interval = val

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 100)
    if reaper.ImGui_BeginCombo(ctx, "##interval_unit", interval_unit) then
      if reaper.ImGui_Selectable(ctx, "Seconds", interval_unit == "Seconds") then interval_unit = "Seconds" end
      if reaper.ImGui_Selectable(ctx, "Frames", interval_unit == "Frames") then interval_unit = "Frames" end
      if reaper.ImGui_Selectable(ctx, "Grid", interval_unit == "Grid") then interval_unit = "Grid" end
      reaper.ImGui_EndCombo(ctx)
    end

    if interval_unit == "Grid" then
      local grid_display = string.format("Current Grid Spacing: %.5f s", get_grid_interval())
      reaper.ImGui_Text(ctx, grid_display)
    end

    if reaper.ImGui_RadioButton(ctx, "Item Start", not from_end) then from_end = false end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Item End", from_end) then from_end = true end

    if reaper.ImGui_RadioButton(ctx, "Single Track", not cross_track_mode) then cross_track_mode = false end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Cross Track", cross_track_mode) then cross_track_mode = true end

    if reaper.ImGui_Button(ctx, "Apply") then reposition_items() end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Apply && Close") then reposition_items() open = false end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel") then open = false end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  else
    if reaper.ImGui_DestroyContext then
      reaper.ImGui_DestroyContext(ctx)
    end
  end
end

reaper.defer(loop)
