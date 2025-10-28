--[[
@description RGWH GUI - ImGui Interface for RGWH Core
@author hsuanice
@version v251028_1900
@about
  ImGui-based GUI for configuring and running RGWH Core operations.
  Provides visual controls for all RGWH Wrapper Template parameters.

@usage
  Run this script in REAPER to open the RGWH GUI window.
  Adjust parameters using the visual controls and click "Run RGWH" to execute.

@changelog
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

local function run_rgwh()
  if gui.is_running then return end

  gui.is_running = true
  gui.last_result = "Running..."

  local args = build_args_from_gui()

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

local function draw_gui()
  local window_flags = ImGui.WindowFlags_MenuBar

  local visible, open = ImGui.Begin(ctx, 'RGWH Control Panel', true, window_flags)
  if not visible then
    ImGui.End(ctx)
    return open
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

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg("[RGWH GUI] Version v251028_0001\nImGui interface for RGWH Core\n")
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  -- Main content
  ImGui.PushItemWidth(ctx, 200)

  -- === OPERATION SECTION ===
  draw_section_header("OPERATION")

  local rv, new_val = ImGui.Combo(ctx, "Operation", gui.op, "Auto\0Render\0Glue\0")
  if rv then gui.op = new_val end
  draw_help_marker("auto: decide based on selection\nrender: single-item render\nglue: multi-item glue")

  rv, new_val = ImGui.Combo(ctx, "Selection Scope", gui.selection_scope, "Auto\0Units\0Time Selection\0Per Item\0")
  if rv then gui.selection_scope = new_val end
  draw_help_marker("How to group items for glue operation\n(ignored when op=render)")

  rv, new_val = ImGui.Combo(ctx, "Channel Mode", gui.channel_mode, "Auto\0Mono\0Multi\0")
  if rv then gui.channel_mode = new_val end
  draw_help_marker("Output channel routing mode")

  -- === RENDER SETTINGS ===
  draw_section_header("RENDER SETTINGS")

  ImGui.Text(ctx, "FX Processing:")
  rv, new_val = ImGui.Checkbox(ctx, "Bake Take FX", gui.take_fx)
  if rv then gui.take_fx = new_val end

  rv, new_val = ImGui.Checkbox(ctx, "Bake Track FX", gui.track_fx)
  if rv then gui.track_fx = new_val end

  ImGui.Spacing(ctx)
  ImGui.Text(ctx, "Volume Handling:")
  rv, new_val = ImGui.Checkbox(ctx, "Merge Volumes", gui.merge_volumes)
  if rv then gui.merge_volumes = new_val end
  draw_help_marker("Merge item volume into take volume before render")

  rv, new_val = ImGui.Checkbox(ctx, "Print Volumes", gui.print_volumes)
  if rv then gui.print_volumes = new_val end
  draw_help_marker("Bake volumes into rendered audio\n(false = restore original volumes)")

  ImGui.Spacing(ctx)
  rv, new_val = ImGui.Combo(ctx, "Timecode Mode", gui.tc_mode, "Previous\0Current\0Off\0")
  if rv then gui.tc_mode = new_val end
  draw_help_marker("BWF TimeReference embed mode")

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

  -- === EPSILON SETTINGS ===
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

  -- === DEBUG & SELECTION ===
  draw_section_header("DEBUG & SELECTION")

  rv, new_val = ImGui.SliderInt(ctx, "Debug Level", gui.debug_level, 0, 2,
    gui.debug_level == 0 and "Silent" or (gui.debug_level == 1 and "Normal" or "Verbose"))
  if rv then gui.debug_level = new_val end

  rv, new_val = ImGui.Checkbox(ctx, "No Clear Console", gui.debug_no_clear)
  if rv then gui.debug_no_clear = new_val end

  rv, new_val = ImGui.Combo(ctx, "Selection Policy", gui.selection_policy, "Progress\0Restore\0None\0")
  if rv then gui.selection_policy = new_val end
  draw_help_marker("progress: keep in-run selections\nrestore: restore original selection\nnone: clear all")

  -- === RUN BUTTON ===
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  if gui.is_running then
    ImGui.BeginDisabled(ctx)
  end

  if ImGui.Button(ctx, "RUN RGWH", -1, 40) then
    run_rgwh()
  end

  if gui.is_running then
    ImGui.EndDisabled(ctx)
  end

  -- Status display
  if gui.last_result ~= "" then
    ImGui.Spacing(ctx)
    ImGui.Text(ctx, "Status: " .. gui.last_result)
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
