--[[
@description AudioSweet GUI - ImGui Interface for AudioSweet Template
@author hsuanice
@version v251028_0001
@about
  ImGui-based GUI for AudioSweet-style operations:
  - Focused/Chain modes
  - Apply/Copy actions
  - Visual controls for all AudioSweet Template parameters

@usage
  Run this script in REAPER to open the AudioSweet GUI window.
  Adjust parameters using the visual controls and click "Run AudioSweet" to execute.

@changelog
  v251028_0001
    - Initial GUI implementation
    - Focused/Chain mode selection
    - Apply/Copy action controls
    - Copy scope and position settings
    - Apply method with handle control
    - Debug and summary toggles
]]--

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------
local r = reaper
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

-- Load AudioSweet Template (will be executed with our ExtState settings)
local RES_PATH = r.GetResourcePath()
local TEMPLATE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Beta Testing/hsuanice_AudioSweet Template.lua'

------------------------------------------------------------
-- ImGui Context
------------------------------------------------------------
local ctx = ImGui.CreateContext('AudioSweet GUI')

------------------------------------------------------------
-- GUI State
------------------------------------------------------------
local gui = {
  -- Window state
  open = true,

  -- Core controls (ExtState: hsuanice_AS)
  mode = 0,              -- 0=focused, 1=chain
  action = 0,            -- 0=apply, 1=copy

  -- Copy settings
  copy_scope = 0,        -- 0=active, 1=all_takes
  copy_pos = 0,          -- 0=tail, 1=head

  -- Apply settings
  apply_method = 0,      -- 0=auto, 1=render, 2=glue
  handle_seconds = 5.0,

  -- Other settings
  debug = false,
  show_summary = true,
  warn_takefx = true,

  -- Status
  is_running = false,
  last_result = "",
  focused_fx_name = "",
}

------------------------------------------------------------
-- Focused FX Detection
------------------------------------------------------------
local function normalize_focused_fx_index(idx)
  if idx >= 0x2000000 then idx = idx - 0x2000000 end
  if idx >= 0x1000000 then idx = idx - 0x1000000 end
  return idx
end

local function get_focused_fx_info()
  local retval, trackOut, itemOut, fxOut = r.GetFocusedFX()

  if retval == 1 then
    -- Track FX
    local tr = r.GetTrack(0, math.max(0, (trackOut or 1) - 1))
    if tr then
      local fx_index = normalize_focused_fx_index(fxOut or 0)
      local _, name = r.TrackFX_GetFXName(tr, fx_index, "")
      return true, "Track FX", name or "(unknown)", tr
    end
  elseif retval == 2 then
    -- Take FX (not supported by template)
    return true, "Take FX", "(Take FX not supported)", nil
  end

  return false, "None", "No focused FX", nil
end

local function update_focused_fx_display()
  local found, fx_type, fx_name, tr = get_focused_fx_info()
  if found then
    if fx_type == "Track FX" then
      gui.focused_fx_name = fx_name
      return true
    else
      gui.focused_fx_name = fx_name .. " (WARNING)"
      return false
    end
  else
    gui.focused_fx_name = "No focused FX"
    return false
  end
end

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------
local function set_extstate_from_gui()
  local mode_names = { "focused", "chain" }
  local action_names = { "apply", "copy" }
  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local method_names = { "auto", "render", "glue" }

  r.SetExtState("hsuanice_AS", "AS_MODE", mode_names[gui.mode + 1], false)
  r.SetExtState("hsuanice_AS", "AS_ACTION", action_names[gui.action + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_SCOPE", scope_names[gui.copy_scope + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_POS", pos_names[gui.copy_pos + 1], false)
  r.SetExtState("hsuanice_AS", "AS_APPLY", method_names[gui.apply_method + 1], false)
  r.SetExtState("hsuanice_AS", "DEBUG", gui.debug and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", gui.show_summary and "1" or "0", false)

  -- Set handle seconds via ProjExtState (RGWH Core reads from here)
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))
end

local function run_audiosweet()
  if gui.is_running then return end

  -- Check for focused FX
  local has_valid_fx = update_focused_fx_display()
  if not has_valid_fx then
    gui.last_result = "Error: No valid Track FX focused"
    return
  end

  -- Check for selected items
  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  gui.is_running = true
  gui.last_result = "Running..."

  -- Set ExtState from GUI
  set_extstate_from_gui()

  -- Run AudioSweet Template
  local ok, err = pcall(dofile, TEMPLATE_PATH)

  r.UpdateArrange()

  if ok then
    gui.last_result = string.format("Success! (%d items)", item_count)
  else
    gui.last_result = "Error: " .. tostring(err)
  end

  gui.is_running = false
end

------------------------------------------------------------
-- GUI Rendering
------------------------------------------------------------
local function draw_section_header(label)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, label)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
end

local function draw_help_marker(desc)
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '(?)')
  if ImGui.BeginItemTooltip(ctx) then
    ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 35.0)
    ImGui.Text(ctx, desc)
    ImGui.PopTextWrapPos(ctx)
    ImGui.EndTooltip(ctx)
  end
end

local function draw_gui()
  local window_flags = ImGui.WindowFlags_MenuBar

  local visible, open = ImGui.Begin(ctx, 'AudioSweet Control Panel', true, window_flags)
  if not visible then
    ImGui.End(ctx)
    return open
  end

  -- Menu Bar
  if ImGui.BeginMenuBar(ctx) then
    if ImGui.BeginMenu(ctx, 'Presets') then
      if ImGui.MenuItem(ctx, 'Focused Apply (Auto)', nil, false, true) then
        gui.mode = 0
        gui.action = 0
        gui.apply_method = 0
      end
      if ImGui.MenuItem(ctx, 'Focused Copy', nil, false, true) then
        gui.mode = 0
        gui.action = 1
        gui.copy_scope = 0
        gui.copy_pos = 0
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'Chain Apply (Render)', nil, false, true) then
        gui.mode = 1
        gui.action = 0
        gui.apply_method = 1
      end
      if ImGui.MenuItem(ctx, 'Chain Copy', nil, false, true) then
        gui.mode = 1
        gui.action = 1
        gui.copy_scope = 0
        gui.copy_pos = 0
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg("[AudioSweet GUI] Version v251028_0001\nImGui interface for AudioSweet Template\n")
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  -- Main content
  ImGui.PushItemWidth(ctx, 200)

  -- === FOCUSED FX STATUS ===
  draw_section_header("FOCUSED FX STATUS")

  -- Auto-update focused FX display
  local has_valid_fx = update_focused_fx_display()

  if has_valid_fx then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF) -- Green
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF) -- Red
  end
  ImGui.Text(ctx, gui.focused_fx_name)
  ImGui.PopStyleColor(ctx)

  if not has_valid_fx then
    ImGui.TextWrapped(ctx, "Open FX window and focus a Track FX to continue")
  end

  -- Item count display
  local item_count = r.CountSelectedMediaItems(0)
  ImGui.Spacing(ctx)
  ImGui.Text(ctx, string.format("Selected Items: %d", item_count))

  -- === MODE & ACTION ===
  draw_section_header("MODE & ACTION")

  local rv, new_val = ImGui.Combo(ctx, "Mode", gui.mode, "Focused FX\0FX Chain\0")
  if rv then gui.mode = new_val end
  draw_help_marker("Focused: Apply/Copy single focused FX\nChain: Apply/Copy entire FX chain")

  rv, new_val = ImGui.Combo(ctx, "Action", gui.action, "Apply\0Copy\0")
  if rv then gui.action = new_val end
  draw_help_marker("Apply: Destructive render/glue\nCopy: Non-destructive FX copy to take FX")

  -- === COPY SETTINGS (only shown when action=copy) ===
  if gui.action == 1 then
    draw_section_header("COPY SETTINGS")

    rv, new_val = ImGui.Combo(ctx, "Copy Scope", gui.copy_scope, "Active Take\0All Takes\0")
    if rv then gui.copy_scope = new_val end
    draw_help_marker("Active: Copy to active take only\nAll Takes: Copy to all takes in item")

    rv, new_val = ImGui.Combo(ctx, "Append Position", gui.copy_pos, "Tail (End)\0Head (Start)\0")
    if rv then gui.copy_pos = new_val end
    draw_help_marker("Tail: Append FX at end of take FX chain\nHead: Insert FX at start")
  end

  -- === APPLY SETTINGS (only shown when action=apply) ===
  if gui.action == 0 then
    draw_section_header("APPLY SETTINGS")

    rv, new_val = ImGui.Combo(ctx, "Apply Method", gui.apply_method, "Auto\0Render\0Glue\0")
    if rv then gui.apply_method = new_val end
    draw_help_marker("Auto: Decide based on selection\nRender: Single-item render\nGlue: Multi-item glue")

    ImGui.Spacing(ctx)
    ImGui.Text(ctx, "Handle (Pre/Post Roll):")
    rv, new_val = ImGui.InputDouble(ctx, "Handle Seconds", gui.handle_seconds, 0.5, 1.0, "%.1f")
    if rv then gui.handle_seconds = math.max(0, new_val) end
    draw_help_marker("Pre/post roll length in seconds\nForwarded to RGWH Core for apply operations")
  end

  -- === DEBUG & OPTIONS ===
  draw_section_header("DEBUG & OPTIONS")

  rv, new_val = ImGui.Checkbox(ctx, "Debug Mode", gui.debug)
  if rv then gui.debug = new_val end
  draw_help_marker("Enable detailed console logging [AS][STEP]")

  rv, new_val = ImGui.Checkbox(ctx, "Show Summary Dialog", gui.show_summary)
  if rv then gui.show_summary = new_val end
  draw_help_marker("Show confirmation dialog before copy operations")

  rv, new_val = ImGui.Checkbox(ctx, "Warn Take FX", gui.warn_takefx)
  if rv then gui.warn_takefx = new_val end
  draw_help_marker("Show warning when Take FX is focused (not supported)")

  -- === RUN BUTTON ===
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  local can_run = has_valid_fx and item_count > 0 and not gui.is_running

  if not can_run then
    ImGui.BeginDisabled(ctx)
  end

  if ImGui.Button(ctx, "RUN AUDIOSWEET", -1, 40) then
    run_audiosweet()
  end

  if not can_run then
    ImGui.EndDisabled(ctx)
  end

  -- Status display
  if gui.last_result ~= "" then
    ImGui.Spacing(ctx)

    -- Color based on result
    if gui.last_result:match("^Success") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF) -- Green
    elseif gui.last_result:match("^Error") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF) -- Red
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFF00FF) -- Yellow
    end

    ImGui.Text(ctx, "Status: " .. gui.last_result)
    ImGui.PopStyleColor(ctx)
  end

  ImGui.PopItemWidth(ctx)
  ImGui.End(ctx)

  return open
end

------------------------------------------------------------
-- Main Loop
------------------------------------------------------------
local function loop()
  gui.open = draw_gui()

  if gui.open then
    r.defer(loop)
  end
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
r.defer(loop)
