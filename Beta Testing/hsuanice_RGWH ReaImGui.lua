--[[
@description RGWH GUI - ImGui Interface for RGWH Core
@author hsuanice
@version 0.1.0-beta (251106.1800)
@about
  ImGui-based GUI for configuring and running RGWH Core operations.
  Provides visual controls for all RGWH Wrapper Template parameters.

@usage
  Run this script in REAPER to open the RGWH GUI window.
  Adjust parameters using the visual controls and click operation buttons to execute.

@changelog
  v251106.1800 (0.1.0-beta)
    - Add: Complete settings persistence - all GUI settings are now automatically saved and restored between sessions
    - Add: Debug mode console output - when debug level >= 1:
      • Print all settings on startup with prefix "[RGWH GUI - STARTUP]"
      • Print all settings on close with prefix "[RGWH GUI - CLOSING]"
    - Improve: Settings are automatically saved whenever any parameter is changed
    - Technical: Added print_all_settings() function to display all current settings in organized format
  v251102.1500 (0.1.0-beta)
    - Fix: Correct GLUE button hover/active colors to yellow shades.
  v251102.0735 (0.1.0-beta)
    - Add: Press ESC to close the GUI window when the window is focused.
  v251102.0730 (0.1.0-beta)
    - Change: Move Channel Mode to the right of Selection Scope and use a two-column layout so Channel Mode takes the right column.
    - Change: Replace the 'View' menu in the menu bar with a direct 'Settings...' menu item for quicker access.
    - Change: Reorder the bottom operation buttons to [RENDER] [AUTO] [GLUE]. Buttons use the default colors but their hover color becomes red (0xFFCC3333).
    - Improve: Persist GUI settings across runs (save/load via ExtState so user choices are remembered between sessions).

  v251102.0030 (0.1.0-beta)
    - Changed: Renamed "RENDER SETTINGS" to "PRINTING" for consistency
    - Changed: Reorganized printing options into two-column layout:
        • Left column: FX Processing (Print Take FX, Print Track FX)
        • Right column: Volume Handling (Merge Volumes, Print Volumes)
    - Changed: Updated terminology from "Bake" to "Print" for REAPER standard compliance
    - Improved: More compact layout with parallel columns

  v251102.0015 (0.1.0-beta)
    - Changed: Converted Selection Scope to radio button format for direct visibility
        • Auto / Units / Time Selection / Per Item
    - Changed: Converted Channel Mode to radio button format for direct visibility
        • Auto / Mono / Multi
    - Improved: All options now visible at once without dropdown menus

  v251102.0000 (0.1.0-beta)
    - Changed: Removed Operation mode radio button selection
    - Changed: Replaced single RUN RGWH button with three operation buttons:
        • AUTO (blue) - Smart auto-detection based on selection
        • RENDER (green) - Force single-item render
        • GLUE (orange) - Force multi-item glue
    - Added: Settings window (View > Settings) containing:
        • Timecode Mode
        • Epsilon settings
        • Cue write options
        • Policies (glue single items, no-trackfx policies, rename mode)
        • Debug level and console options
        • Selection Policy
    - Changed: Main GUI now shows only frequently-used parameters:
        • Selection Scope, Channel Mode, Handle
        • Render settings (FX processing, volume handling)
    - Improved: One-click workflow - directly execute operation without mode switching
    - Improved: Color-coded buttons for quick visual identification

  v251028_1900
    - Initial GUI implementation
    - All core parameters exposed as visual controls
    - Real-time parameter validation
    - Preset system for common workflows
]]--

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------
local r = reaper
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

-- Load RGWH Core
local RES_PATH = r.GetResourcePath()
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua'

local ok_load, RGWH = pcall(dofile, CORE_PATH)
if not ok_load or type(RGWH) ~= "table" or type(RGWH.core) ~= "function" then
  r.ShowConsoleMsg(("[RGWH GUI] Failed to load Core at:\n  %s\nError: %s\n")
    :format(CORE_PATH, tostring(RGWH)))
  return
end

------------------------------------------------------------
-- ImGui Context
------------------------------------------------------------
local ctx = ImGui.CreateContext('RGWH GUI')
local font = nil

------------------------------------------------------------
-- GUI State
------------------------------------------------------------
local gui = {
  -- Window state
  open = true,
  show_settings = false,

  -- Operation settings
  op = 0,                    -- 0=auto, 1=render, 2=glue
  selection_scope = 0,       -- 0=auto, 1=units, 2=ts, 3=item
  channel_mode = 0,          -- 0=auto, 1=mono, 2=multi

  -- Render toggles
  take_fx = true,
  track_fx = false,
  tc_mode = 1,              -- 0=previous, 1=current, 2=off

  -- Volume handling
  merge_volumes = true,
  print_volumes = false,

  -- Handle settings
  handle_mode = 0,          -- 0=ext, 1=seconds, 2=frames
  handle_length = 5.0,

  -- Epsilon settings
  epsilon_mode = 0,         -- 0=ext, 1=frames, 2=seconds
  epsilon_value = 0.5,

  -- Cues
  cue_write_edge = true,
  cue_write_glue = true,

  -- Policies
  glue_single_items = true,
  glue_no_trackfx_policy = 0,    -- 0=preserve, 1=force_multi
  render_no_trackfx_policy = 0,  -- 0=preserve, 1=force_multi
  rename_mode = 0,               -- 0=auto, 1=glue, 2=render

  -- Debug
  debug_level = 2,           -- 0=silent, 1=normal, 2=verbose
  debug_no_clear = true,

  -- Selection policy (wrapper-only)
  selection_policy = 1,      -- 0=progress, 1=restore, 2=none

  -- Status
  is_running = false,
  last_result = "",
}

-- Persistence namespace and helpers (save/load GUI state)
local P_NS = "hsuanice_RGWH_GUI_state_v1"

local persist_keys = {
  'op','selection_scope','channel_mode',
  'take_fx','track_fx','tc_mode',
  'merge_volumes','print_volumes',
  'handle_mode','handle_length',
  'epsilon_mode','epsilon_value',
  'cue_write_edge','cue_write_glue',
  'glue_single_items','glue_no_trackfx_policy','render_no_trackfx_policy','rename_mode',
  'debug_level','debug_no_clear','selection_policy'
}

local function serialize_gui_state(tbl)
  local parts = {}
  for _,k in ipairs(persist_keys) do
    local v = tbl[k]
    if v == nil then v = '' end
    parts[#parts+1] = k .. '=' .. tostring(v)
  end
  return table.concat(parts, ';')
end

local function deserialize_into_gui(s, tbl)
  if not s or s == '' then return end
  for kv in s:gmatch('[^;]+') do
    local k, v = kv:match('([^=]+)=(.*)')
    if k and v and tbl[k] ~= nil then
      -- try to coerce numeric
      local n = tonumber(v)
      if n then tbl[k] = n
      elseif v == 'true' then tbl[k] = true
      elseif v == 'false' then tbl[k] = false
      else tbl[k] = v end
    end
  end
end

local function save_persist()
  local s = serialize_gui_state(gui)
  reaper.SetExtState(P_NS, 'state', s, true)
end

local function load_persist()
  local s = reaper.GetExtState(P_NS, 'state') or ''
  deserialize_into_gui(s, gui)
end

-- Helper function to print all current settings to console
local function print_all_settings(prefix)
  prefix = prefix or "[RGWH GUI]"

  local function bool_str(v) return v and "ON" or "OFF" end

  local op_names = {"Auto", "Render", "Glue"}
  local scope_names = {"Auto", "Units", "Time Selection", "Per Item"}
  local channel_names = {"Auto", "Mono", "Multi"}
  local tc_names = {"Previous", "Current", "Off"}
  local handle_names = {"Use ExtState", "Seconds", "Frames"}
  local epsilon_names = {"Use ExtState", "Frames", "Seconds"}
  local policy_names = {"Preserve", "Force Multi"}
  local rename_names = {"Auto", "Glue", "Render"}
  local debug_names = {"Silent", "Normal", "Verbose"}
  local selection_policy_names = {"Progress", "Restore", "None"}

  r.ShowConsoleMsg("========================================\n")
  r.ShowConsoleMsg(string.format("%s settings:\n", prefix))
  r.ShowConsoleMsg("========================================\n")

  r.ShowConsoleMsg(string.format("  Operation: %s\n", op_names[gui.op + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Selection Scope: %s\n", scope_names[gui.selection_scope + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Channel Mode: %s\n", channel_names[gui.channel_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Take FX: %s\n", bool_str(gui.take_fx)))
  r.ShowConsoleMsg(string.format("  Track FX: %s\n", bool_str(gui.track_fx)))
  r.ShowConsoleMsg(string.format("  TC Mode: %s\n", tc_names[gui.tc_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Merge Volumes: %s\n", bool_str(gui.merge_volumes)))
  r.ShowConsoleMsg(string.format("  Print Volumes: %s\n", bool_str(gui.print_volumes)))
  r.ShowConsoleMsg(string.format("  Handle Mode: %s\n", handle_names[gui.handle_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Handle Length: %.2f\n", gui.handle_length))
  r.ShowConsoleMsg(string.format("  Epsilon Mode: %s\n", epsilon_names[gui.epsilon_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Epsilon Value: %.5f\n", gui.epsilon_value))
  r.ShowConsoleMsg(string.format("  Write Edge Cues: %s\n", bool_str(gui.cue_write_edge)))
  r.ShowConsoleMsg(string.format("  Write Glue Cues: %s\n", bool_str(gui.cue_write_glue)))
  r.ShowConsoleMsg(string.format("  Glue Single Items: %s\n", bool_str(gui.glue_single_items)))
  r.ShowConsoleMsg(string.format("  Glue No-TrackFX Policy: %s\n", policy_names[gui.glue_no_trackfx_policy + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Render No-TrackFX Policy: %s\n", policy_names[gui.render_no_trackfx_policy + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Rename Mode: %s\n", rename_names[gui.rename_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Debug Level: %s\n", debug_names[gui.debug_level + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Debug No Clear: %s\n", bool_str(gui.debug_no_clear)))
  r.ShowConsoleMsg(string.format("  Selection Policy: %s\n", selection_policy_names[gui.selection_policy + 1] or "Unknown"))

  r.ShowConsoleMsg("========================================\n")
end

-- call load immediately so gui gets initial persisted values
load_persist()

-- If debug level >= 1, print settings on startup
if gui.debug_level >= 1 then
  print_all_settings("[RGWH GUI - STARTUP]")
end

------------------------------------------------------------
-- Preset System
------------------------------------------------------------
local presets = {
  {
    name = "Auto (ExtState defaults)",
    op = 0,
    selection_scope = 0,
    channel_mode = 0,
  },
  {
    name = "Force Units Glue",
    op = 2,
    selection_scope = 1,
    channel_mode = 0,
  },
  {
    name = "Force TS-Window Glue",
    op = 2,
    selection_scope = 2,
    channel_mode = 0,
  },
  {
    name = "Single-Item Render",
    op = 1,
    channel_mode = 0,
    take_fx = true,
    track_fx = false,
    tc_mode = 0,
  },
}

local selected_preset = -1

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------

-- Selection Snapshot/Restore (from Wrapper Template)
local function track_guid(tr)
  local ok, guid = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  return ok and guid or nil
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for t = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, t)
    local ok, g = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
    if ok and g == guid then return tr end
  end
  return nil
end

local function seconds_epsilon_from_args(args)
  if type(args.epsilon) == "table" then
    if args.epsilon.mode == "seconds" then
      return tonumber(args.epsilon.value) or 0.02
    elseif args.epsilon.mode == "frames" then
      local fps = r.TimeMap_curFrameRate(0) or 30
      return (tonumber(args.epsilon.value) or 0) / fps
    end
  end
  return 0.02
end

local function snapshot_selection()
  local s = {}

  -- items
  s.items = {}
  for i = 0, r.CountSelectedMediaItems(0)-1 do
    local it  = r.GetSelectedMediaItem(0, i)
    local tr  = it and r.GetMediaItem_Track(it) or nil
    local tgd = tr and track_guid(tr) or nil
    local pos = it and r.GetMediaItemInfo_Value(it, "D_POSITION") or nil
    local len = it and r.GetMediaItemInfo_Value(it, "D_LENGTH")   or nil
    s.items[#s.items+1] = {
      ptr      = it,
      tr       = tr,
      tr_guid  = tgd,
      start    = pos,
      finish   = (pos and len) and (pos + len) or nil,
    }
  end

  -- tracks
  s.tracks = {}
  for t = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, t)
    if r.IsTrackSelected(tr) then
      s.tracks[#s.tracks+1] = tr
    end
  end

  -- time selection
  s.ts_start, s.ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

  -- edit cursor
  s.edit_pos = r.GetCursorPosition()

  return s
end

local function restore_selection(s, args)
  if not s then return end

  -- items (smart restore)
  r.SelectAllMediaItems(0, false)
  if s.items then
    local eps = seconds_epsilon_from_args(args)
    for _, desc in ipairs(s.items) do
      -- try original pointer
      if desc.ptr and r.ValidatePtr2(0, desc.ptr, "MediaItem*") then
        r.SetMediaItemSelected(desc.ptr, true)
      else
        -- fallback: match by same-track + time overlap
        local tr = desc.tr
        if (not tr or not r.ValidatePtr2(0, tr, "MediaTrack*")) and desc.tr_guid then
          tr = find_track_by_guid(desc.tr_guid)
        end
        if tr and desc.start and desc.finish then
          local N = r.CountTrackMediaItems(tr)
          for i = 0, N - 1 do
            local it2 = r.GetTrackMediaItem(tr, i)
            local p   = r.GetMediaItemInfo_Value(it2, "D_POSITION")
            local l   = r.GetMediaItemInfo_Value(it2, "D_LENGTH")
            local q1, q2 = p, p + l
            local a1, a2 = desc.start - eps, desc.finish + eps
            if (q1 < a2) and (q2 > a1) then
              r.SetMediaItemSelected(it2, true)
              break
            end
          end
        end
      end
    end
  end

  -- tracks
  for t = 0, r.CountTracks(0)-1 do
    r.SetTrackSelected(r.GetTrack(0, t), false)
  end
  if s.tracks then
    for _, tr in ipairs(s.tracks) do
      if r.ValidatePtr2(0, tr, "MediaTrack*") then
        r.SetTrackSelected(tr, true)
      end
    end
  end

  -- time selection
  if s.ts_start and s.ts_end then
    r.GetSet_LoopTimeRange2(0, true, false, s.ts_start, s.ts_end, false)
  end

  -- edit cursor
  if s.edit_pos then
    r.SetEditCurPos(s.edit_pos, false, false)
  end
end

local function apply_preset(idx)
  if idx < 0 or idx >= #presets then return end
  local p = presets[idx + 1]

  if p.op then gui.op = p.op end
  if p.selection_scope then gui.selection_scope = p.selection_scope end
  if p.channel_mode then gui.channel_mode = p.channel_mode end
  if p.take_fx ~= nil then gui.take_fx = p.take_fx end
  if p.track_fx ~= nil then gui.track_fx = p.track_fx end
  if p.tc_mode then gui.tc_mode = p.tc_mode end
end

local function build_args_from_gui()
  -- Map GUI state to RGWH Core args format
  local op_names = { "auto", "render", "glue" }
  local scope_names = { "auto", "units", "ts", "item" }
  local channel_names = { "auto", "mono", "multi" }
  local tc_names = { "previous", "current", "off" }
  local policy_names = { "preserve", "force_multi" }
  local rename_names = { "auto", "glue", "render" }

  local args = {
    op = op_names[gui.op + 1],
    selection_scope = scope_names[gui.selection_scope + 1],
    channel_mode = channel_names[gui.channel_mode + 1],

    take_fx = gui.take_fx,
    track_fx = gui.track_fx,
    tc_mode = tc_names[gui.tc_mode + 1],

    merge_volumes = gui.merge_volumes,
    print_volumes = gui.print_volumes,

    cues = {
      write_edge = gui.cue_write_edge,
      write_glue = gui.cue_write_glue,
    },

    policies = {
      glue_single_items = gui.glue_single_items,
      glue_no_trackfx_output_policy = policy_names[gui.glue_no_trackfx_policy + 1],
      render_no_trackfx_output_policy = policy_names[gui.render_no_trackfx_policy + 1],
      rename_mode = rename_names[gui.rename_mode + 1],
    },
  }

  -- Handle
  if gui.handle_mode == 0 then
    args.handle = "ext"
  elseif gui.handle_mode == 1 then
    args.handle = { mode = "seconds", seconds = gui.handle_length }
  else -- frames
    local fps = r.TimeMap_curFrameRate(0) or 30
    args.handle = { mode = "seconds", seconds = gui.handle_length / fps }
  end

  -- Epsilon
  if gui.epsilon_mode == 0 then
    args.epsilon = "ext"
  elseif gui.epsilon_mode == 1 then
    args.epsilon = { mode = "frames", value = gui.epsilon_value }
  else -- seconds
    args.epsilon = { mode = "seconds", value = gui.epsilon_value }
  end

  -- Debug
  args.debug = {
    level = gui.debug_level,
    no_clear = gui.debug_no_clear,
  }

  return args
end

local function run_rgwh(operation)
  if gui.is_running then return end

  gui.is_running = true
  gui.last_result = "Running..."

  -- Temporarily override operation mode
  local original_op = gui.op
  if operation == "auto" then
    gui.op = 0
  elseif operation == "render" then
    gui.op = 1
  elseif operation == "glue" then
    gui.op = 2
  end

  local args = build_args_from_gui()
  gui.op = original_op  -- Restore original

  -- Selection policy handling (wrapper logic)
  local policy_names = { "progress", "restore", "none" }
  local policy = policy_names[gui.selection_policy + 1]

  -- Snapshot BEFORE (if restore policy)
  local sel_before = nil
  if policy == "restore" then
    sel_before = snapshot_selection()
  end

  -- Clear console if needed
  if args.debug and args.debug.no_clear == false then
    r.ClearConsole()
  end

  -- Run Core
  local ok, err = RGWH.core(args)

  -- Post-run handling
  if policy == "restore" and sel_before then
    restore_selection(sel_before, args)
  elseif policy == "none" then
    r.SelectAllMediaItems(0, false)
  end
  -- "progress": do nothing, keep Core's selections

  r.UpdateArrange()

  if ok then
    gui.last_result = "Success!"
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

local function draw_settings_popup()
  if not gui.show_settings then return end

  local before_state = serialize_gui_state(gui)

  ImGui.SetNextWindowSize(ctx, 500, 600, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Settings', true)
  if not visible then
    ImGui.End(ctx)
    gui.show_settings = open
    return
  end

  ImGui.PushItemWidth(ctx, 200)
  local rv, new_val

  -- === TIMECODE MODE ===
  draw_section_header("TIMECODE MODE")
  rv, new_val = ImGui.Combo(ctx, "Timecode Mode", gui.tc_mode, "Previous\0Current\0Off\0")
  if rv then gui.tc_mode = new_val end
  draw_help_marker("BWF TimeReference embed mode")

  -- === EPSILON ===
  draw_section_header("EPSILON (Tolerance)")
  rv, new_val = ImGui.Combo(ctx, "Epsilon Mode", gui.epsilon_mode, "Use ExtState\0Frames\0Seconds\0")
  if rv then gui.epsilon_mode = new_val end

  if gui.epsilon_mode > 0 then
    rv, new_val = ImGui.InputDouble(ctx, "Epsilon Value", gui.epsilon_value, 0.01, 0.1, "%.3f")
    if rv then gui.epsilon_value = math.max(0, new_val) end

    local unit = gui.epsilon_mode == 1 and "frames" or "seconds"
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, unit)
  end

  -- === CUES ===
  draw_section_header("CUES")
  rv, new_val = ImGui.Checkbox(ctx, "Write Edge Cues", gui.cue_write_edge)
  if rv then gui.cue_write_edge = new_val end
  draw_help_marker("#in/#out edge cues as media cues")

  rv, new_val = ImGui.Checkbox(ctx, "Write Glue Cues", gui.cue_write_glue)
  if rv then gui.cue_write_glue = new_val end
  draw_help_marker("#Glue: <TakeName> cues when sources change")

  -- === POLICIES ===
  draw_section_header("POLICIES")
  rv, new_val = ImGui.Checkbox(ctx, "Glue Single Items", gui.glue_single_items)
  if rv then gui.glue_single_items = new_val end
  draw_help_marker("In auto mode: single item => render (if false)")

  rv, new_val = ImGui.Combo(ctx, "Glue No-TrackFX Policy", gui.glue_no_trackfx_policy, "Preserve\0Force Multi\0")
  if rv then gui.glue_no_trackfx_policy = new_val end

  rv, new_val = ImGui.Combo(ctx, "Render No-TrackFX Policy", gui.render_no_trackfx_policy, "Preserve\0Force Multi\0")
  if rv then gui.render_no_trackfx_policy = new_val end

  rv, new_val = ImGui.Combo(ctx, "Rename Mode", gui.rename_mode, "Auto\0Glue\0Render\0")
  if rv then gui.rename_mode = new_val end

  -- === DEBUG ===
  draw_section_header("DEBUG")
  rv, new_val = ImGui.SliderInt(ctx, "Debug Level", gui.debug_level, 0, 2,
    gui.debug_level == 0 and "Silent" or (gui.debug_level == 1 and "Normal" or "Verbose"))
  if rv then gui.debug_level = new_val end

  rv, new_val = ImGui.Checkbox(ctx, "No Clear Console", gui.debug_no_clear)
  if rv then gui.debug_no_clear = new_val end

  -- === SELECTION POLICY ===
  draw_section_header("SELECTION POLICY")
  rv, new_val = ImGui.Combo(ctx, "Selection Policy", gui.selection_policy, "Progress\0Restore\0None\0")
  if rv then gui.selection_policy = new_val end
  draw_help_marker("progress: keep in-run selections\nrestore: restore original selection\nnone: clear all")

  -- persist if changed
  local after_state = serialize_gui_state(gui)
  if after_state ~= before_state then save_persist() end

  ImGui.PopItemWidth(ctx)
  ImGui.End(ctx)
  gui.show_settings = open
end

local function draw_gui()
  local before_state = serialize_gui_state(gui)
  local window_flags = ImGui.WindowFlags_MenuBar | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoResize

  local visible, open = ImGui.Begin(ctx, 'RGWH Control Panel', true, window_flags)
  if not visible then
    ImGui.End(ctx)
    return open
  end

  -- Close the window when ESC is pressed and the window is focused
  if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    open = false
    gui.open = false
  end

  -- Menu Bar
  if ImGui.BeginMenuBar(ctx) then
    if ImGui.BeginMenu(ctx, 'Presets') then
      for i, preset in ipairs(presets) do
        if ImGui.MenuItem(ctx, preset.name, nil, false, true) then
          apply_preset(i - 1)
          selected_preset = i - 1
        end
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.MenuItem(ctx, 'Settings...', nil, false, true) then
      gui.show_settings = true
    end

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg("[RGWH GUI] Version 0.1.0-beta (251102.1500)\nImGui interface for RGWH Core\n")
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  -- Main content
  ImGui.PushItemWidth(ctx, 200)

  -- === OPERATION SECTION ===
  draw_section_header("OPERATION")

  -- Selection Scope (left) and Channel Mode (right) in two-column layout
  local col_width = ImGui.GetContentRegionAvail(ctx) / 2 - 10

  -- Left column: Selection Scope
  ImGui.BeginGroup(ctx)
  ImGui.Text(ctx, "Selection Scope:")
  if ImGui.RadioButton(ctx, "Auto##scope", gui.selection_scope == 0) then gui.selection_scope = 0 end
  draw_help_marker("Auto: decide based on time selection")

  if ImGui.RadioButton(ctx, "Units##scope", gui.selection_scope == 1) then gui.selection_scope = 1 end
  draw_help_marker("Group items by same-track units")

  if ImGui.RadioButton(ctx, "Time Selection##scope", gui.selection_scope == 2) then gui.selection_scope = 2 end
  draw_help_marker("Glue strictly within time selection window")

  if ImGui.RadioButton(ctx, "Per Item##scope", gui.selection_scope == 3) then gui.selection_scope = 3 end
  draw_help_marker("Process each item individually")
  ImGui.EndGroup(ctx)

  -- Right column: Channel Mode
  ImGui.SameLine(ctx, col_width + 20)
  ImGui.BeginGroup(ctx)
  ImGui.Text(ctx, "Channel Mode:")
  if ImGui.RadioButton(ctx, "Auto##channel", gui.channel_mode == 0) then gui.channel_mode = 0 end
  draw_help_marker("Auto: decide based on source material")

  if ImGui.RadioButton(ctx, "Mono##channel", gui.channel_mode == 1) then gui.channel_mode = 1 end
  draw_help_marker("Force mono output")

  if ImGui.RadioButton(ctx, "Multi##channel", gui.channel_mode == 2) then gui.channel_mode = 2 end
  draw_help_marker("Force multi-channel output")
  ImGui.EndGroup(ctx)

  -- === PRINTING ===
  draw_section_header("PRINTING")

  -- Two-column layout
  local col_width = ImGui.GetContentRegionAvail(ctx) / 2 - 10

  -- Left column: FX Processing
  ImGui.BeginGroup(ctx)
  ImGui.Text(ctx, "FX Processing:")
  rv, new_val = ImGui.Checkbox(ctx, "Print Take FX", gui.take_fx)
  if rv then gui.take_fx = new_val end
  draw_help_marker("Print take FX into rendered audio")

  rv, new_val = ImGui.Checkbox(ctx, "Print Track FX", gui.track_fx)
  if rv then gui.track_fx = new_val end
  draw_help_marker("Print track FX into rendered audio")
  ImGui.EndGroup(ctx)

  ImGui.SameLine(ctx, col_width + 20)

  -- Right column: Volume Handling
  ImGui.BeginGroup(ctx)
  ImGui.Text(ctx, "Volume Handling:")
  rv, new_val = ImGui.Checkbox(ctx, "Merge Volumes", gui.merge_volumes)
  if rv then gui.merge_volumes = new_val end
  draw_help_marker("Merge item volume into take volume before render")

  rv, new_val = ImGui.Checkbox(ctx, "Print Volumes", gui.print_volumes)
  if rv then gui.print_volumes = new_val end
  draw_help_marker("Print volumes into rendered audio\n(false = restore original volumes)")
  ImGui.EndGroup(ctx)

  -- === HANDLE SETTINGS ===
  draw_section_header("HANDLE (Pre/Post Roll)")

  rv, new_val = ImGui.Combo(ctx, "Handle Mode", gui.handle_mode, "Use ExtState\0Seconds\0Frames\0")
  if rv then gui.handle_mode = new_val end

  if gui.handle_mode > 0 then
    rv, new_val = ImGui.InputDouble(ctx, "Handle Length", gui.handle_length, 0.1, 1.0, "%.3f")
    if rv then gui.handle_length = math.max(0, new_val) end

    local unit = gui.handle_mode == 1 and "seconds" or "frames"
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, unit)
  end

  -- === OPERATION BUTTONS ===
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  if gui.is_running then
    ImGui.BeginDisabled(ctx)
  end

  -- Calculate button width (3 buttons with spacing)
  local avail_width = ImGui.GetContentRegionAvail(ctx)
  local button_width = (avail_width - 2 * ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)) / 3

  -- RENDER button (base blue, hover -> green)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button,        0xFF) -- base blue (same as GUI default)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF3399FF) -- hover becomes green
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  0xFF1A75FF) -- active deep green
  if ImGui.Button(ctx, "RENDER", button_width, 40) then
    run_rgwh("render")
  end
  ImGui.PopStyleColor(ctx, 3)

  ImGui.SameLine(ctx)

  -- AUTO button (base blue, hover -> brighter blue)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button,        0xFF) -- base blue
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF3399FF) -- hover brighter blue
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  0xFF1A75FF) -- active slightly darker
  if ImGui.Button(ctx, "AUTO", button_width, 40) then
    run_rgwh("auto")
  end
  ImGui.PopStyleColor(ctx, 3)

  ImGui.SameLine(ctx)

  -- GLUE button (base blue, hover -> yellow)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button,        0xFF) -- base blue
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF3399FF) -- hover becomes yellow
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  0xFF1A75FF) -- active deeper yellow/orange
  if ImGui.Button(ctx, "GLUE", button_width, 40) then
    run_rgwh("glue")
  end
  ImGui.PopStyleColor(ctx, 3)

  if gui.is_running then
    ImGui.EndDisabled(ctx)
  end

  -- Status display
  if gui.last_result ~= "" then
    ImGui.Spacing(ctx)
    ImGui.Text(ctx, "Status: " .. gui.last_result)
  end

  -- persist if changed
  local after_state = serialize_gui_state(gui)
  if after_state ~= before_state then save_persist() end

  ImGui.PopItemWidth(ctx)
  ImGui.End(ctx)

  return open
end

------------------------------------------------------------
-- Main Loop
------------------------------------------------------------
local function loop()
  gui.open = draw_gui()
  draw_settings_popup()

  if gui.open then
    r.defer(loop)
  else
    -- Window is closing - print settings if debug level >= 1
    if gui.debug_level >= 1 then
      print_all_settings("[RGWH GUI - CLOSING]")
    end
  end
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
r.defer(loop)
