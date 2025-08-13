--[[
@description ReaImGui - Display Edit Cursor Position (Unit Selector)
@version 0.1
@author hsuanice

@about
  Displays the current edit cursor position in various time formats.  
  - Supports project default, minutes:seconds, timecode, and beats.  
  - Includes unit selector dropdown.  
  - Window auto-resizes and updates in real time.  
  - Right-click inside window to close instantly.

  💡 Ideal for timeline navigation and precision editing at-a-glance.  
    Integrates seamlessly with hsuanice’s ReaImGui-based HUD workflows.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.  
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.1 - Beta testing
--]]

local ctx = reaper.ImGui_CreateContext('Edit Cursor Position')
local window_flags =
    reaper.ImGui_WindowFlags_NoTitleBar() |
    reaper.ImGui_WindowFlags_NoCollapse() |
    reaper.ImGui_WindowFlags_NoResize() |
    reaper.ImGui_WindowFlags_AlwaysAutoResize()

local units = { "Project Default", "Minutes:Seconds", "Timecode", "Beats" }
local current_unit = "Project Default"

local function format_project_default(pos)
  return reaper.format_timestr_pos(pos, "", -1)
end

local function format_minsec(pos)
  return reaper.format_timestr_pos(pos, "", 0)
end

local function format_timecode(pos)
  return reaper.format_timestr_pos(pos, "", 5)
end

local function format_beats(pos)
  return reaper.format_timestr_pos(pos, "", 2)
end

local function format_position(pos)
  if current_unit == "Project Default" then
    return format_project_default(pos)
  elseif current_unit == "Minutes:Seconds" then
    return format_minsec(pos)
  elseif current_unit == "Timecode" then
    return format_timecode(pos)
  elseif current_unit == "Beats" then
    return format_beats(pos)
  else
    return string.format("%.3f", pos)
  end
end

local function loop()
  local visible, open = reaper.ImGui_Begin(ctx, 'Edit Cursor Position', true, window_flags)
  if visible then
    local pos = reaper.GetCursorPosition()

    reaper.ImGui_Text(ctx, "Cursor: " .. format_position(pos))
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 16)

    if reaper.ImGui_BeginCombo(ctx, "##unit_selector", current_unit) then
      for _, unit in ipairs(units) do
        local selected = (unit == current_unit)
        if reaper.ImGui_Selectable(ctx, unit, selected) then
          current_unit = unit
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    
    if reaper.ImGui_IsMouseClicked(ctx, 1) and reaper.ImGui_IsWindowHovered(ctx) then
      open = false
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  else
    ctx = nil 
  end
end

reaper.defer(loop)
