--[[
@description AudioSweet GUI - ImGui Interface for AudioSweet
@author hsuanice
@version 251028_2015
@about
  Complete AudioSweet control center with:
  - Focused/Chain modes with FX chain display
  - Apply/Copy actions
  - Saved Chains (memory-based, no focus required)
  - History tracking (auto-record recent operations)
  - Compact, intuitive UI with radio buttons

@usage
  Run this script in REAPER to open the AudioSweet GUI window.

@changelog
  251028_2015
    - Changed: Status display moved to below RUN button (above Saved Chains/History).
      - Previous: Status appeared at bottom of window
      - Now: Immediate feedback right after clicking RUN
    - Changed: RUN AUDIOSWEET button repositioned above Saved Chains/History.
      - More logical flow: configure → run → see status → quick actions
    - Fixed: Handle seconds setting now properly applied to saved chain execution.
      - Handle value forwarded to RGWH Core via ProjExtState before apply
    - Fixed: Debug mode fully functional - no console output when disabled.
      - Chain/Saved execution uses native command (bypass AudioSweet Template)
      - Focused mode respects ExtState debug flag
    - Integration: Full ExtState control for debug output (hsuanice_AS/DEBUG).
      - Works seamlessly with AudioSweet Core v251028_2011
    - UI: Cleaner visual hierarchy and workflow

  v251028_0003
    - Changed: Combo boxes replaced with Radio buttons for better UX
    - Changed: Compact horizontal layout for controls
    - Added: History tracking for recent FX/Chain operations
    - Changed: Debug moved to Menu Bar
    - Improved: Quick Process area (Saved Chains + History)

  v251028_0002
    - Added: Chain mode displays track FX chain
    - Added: FX Chain memory system
    - Added: One-click saved chain execution
]]--

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------
local r = reaper
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local RES_PATH = r.GetResourcePath()
local TEMPLATE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Beta Testing/hsuanice_AudioSweet Template.lua'
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_AudioSweet Core.lua'

------------------------------------------------------------
-- ImGui Context
------------------------------------------------------------
local ctx = ImGui.CreateContext('AudioSweet GUI')

------------------------------------------------------------
-- GUI State
------------------------------------------------------------
local gui = {
  open = true,
  mode = 0,              -- 0=focused, 1=chain
  action = 0,            -- 0=apply, 1=copy
  copy_scope = 0,
  copy_pos = 0,
  apply_method = 0,
  handle_seconds = 5.0,
  debug = false,
  show_summary = true,
  warn_takefx = true,
  is_running = false,
  last_result = "",
  focused_fx_name = "",
  focused_track = nil,
  focused_track_name = "",
  focused_track_fx_list = {},
  saved_chains = {},
  history = {},
  new_chain_name = "",
  show_save_popup = false,
}

------------------------------------------------------------
-- Track FX Chain Helpers
------------------------------------------------------------
local function get_track_guid(tr)
  if not tr then return nil end
  return r.GetTrackGUID(tr)
end

local function get_track_name_and_number(tr)
  if not tr then return "", 0 end
  local track_num = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0
  local _, track_name = r.GetTrackName(tr, "")
  return track_name or "", track_num
end

local function get_track_fx_chain(tr)
  local fx_list = {}
  if not tr then return fx_list end
  local fx_count = r.TrackFX_GetCount(tr)
  for i = 0, fx_count - 1 do
    local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
    fx_list[#fx_list + 1] = {
      index = i,
      name = fx_name or "(unknown)",
      enabled = r.TrackFX_GetEnabled(tr, i),
      offline = r.TrackFX_GetOffline(tr, i),
    }
  end
  return fx_list
end

------------------------------------------------------------
-- Saved Chain Management
------------------------------------------------------------
local CHAIN_NAMESPACE = "hsuanice_AS_SavedChains"
local HISTORY_NAMESPACE = "hsuanice_AS_History"
local MAX_HISTORY = 10

local function load_saved_chains()
  gui.saved_chains = {}
  local idx = 0
  while true do
    local ok, data = r.GetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx)
    if ok == 0 or data == "" then break end
    local name, guid, track_name = data:match("^([^|]*)|([^|]*)|(.*)$")
    if name and guid then
      gui.saved_chains[#gui.saved_chains + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
      }
    end
    idx = idx + 1
  end
end

local function save_chains_to_extstate()
  local idx = 0
  while true do
    local ok = r.GetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx)
    if ok == 0 then break end
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx, "")
    idx = idx + 1
  end
  for i, chain in ipairs(gui.saved_chains) do
    local data = string.format("%s|%s|%s", chain.name, chain.track_guid, chain.track_name)
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. (i - 1), data)
  end
end

local function add_saved_chain(name, track_guid, track_name)
  gui.saved_chains[#gui.saved_chains + 1] = {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
  }
  save_chains_to_extstate()
end

local function delete_saved_chain(idx)
  table.remove(gui.saved_chains, idx)
  save_chains_to_extstate()
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if get_track_guid(tr) == guid then
      return tr
    end
  end
  return nil
end

------------------------------------------------------------
-- History Management
------------------------------------------------------------
local function load_history()
  gui.history = {}
  local idx = 0
  while idx < MAX_HISTORY do
    local ok, data = r.GetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. idx)
    if ok == 0 or data == "" then break end
    local name, guid, track_name, mode = data:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name and guid then
      gui.history[#gui.history + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
        mode = mode or "chain",
      }
    end
    idx = idx + 1
  end
end

local function add_to_history(name, track_guid, track_name, mode)
  -- Remove if already exists
  for i = #gui.history, 1, -1 do
    if gui.history[i].name == name and gui.history[i].track_guid == track_guid then
      table.remove(gui.history, i)
    end
  end

  -- Add to front
  table.insert(gui.history, 1, {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
    mode = mode,
  })

  -- Trim to MAX_HISTORY
  while #gui.history > MAX_HISTORY do
    table.remove(gui.history)
  end

  -- Save to ExtState
  for i = 0, MAX_HISTORY - 1 do
    r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
  end
  for i, item in ipairs(gui.history) do
    local data = string.format("%s|%s|%s|%s", item.name, item.track_guid, item.track_name, item.mode)
    r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. (i - 1), data)
  end
end

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
    local tr = r.GetTrack(0, math.max(0, (trackOut or 1) - 1))
    if tr then
      local fx_index = normalize_focused_fx_index(fxOut or 0)
      local _, name = r.TrackFX_GetFXName(tr, fx_index, "")
      return true, "Track FX", name or "(unknown)", tr
    end
  elseif retval == 2 then
    return true, "Take FX", "(Take FX not supported)", nil
  end
  return false, "None", "No focused FX", nil
end

local function update_focused_fx_display()
  local found, fx_type, fx_name, tr = get_focused_fx_info()
  gui.focused_track = tr
  if found then
    if fx_type == "Track FX" then
      gui.focused_fx_name = fx_name
      if tr then
        local track_name, track_num = get_track_name_and_number(tr)
        gui.focused_track_name = string.format("#%d - %s", track_num, track_name)
        gui.focused_track_fx_list = get_track_fx_chain(tr)
      end
      return true
    else
      gui.focused_fx_name = fx_name .. " (WARNING)"
      gui.focused_track_name = ""
      gui.focused_track_fx_list = {}
      return false
    end
  else
    gui.focused_fx_name = "No focused FX"
    gui.focused_track_name = ""
    gui.focused_track_fx_list = {}
    return false
  end
end

------------------------------------------------------------
-- AudioSweet Execution
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
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)  -- Always disable summary dialog
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))

  -- Set RGWH Core debug level (0 = silent, no console output)
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", gui.debug and "2" or "0")
end

local function run_audiosweet(override_track)
  if gui.is_running then return end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  local target_track = override_track or gui.focused_track

  if not override_track then
    local has_valid_fx = update_focused_fx_display()
    if not has_valid_fx then
      gui.last_result = "Error: No valid Track FX focused"
      return
    end
  end

  if not target_track then
    gui.last_result = "Error: Target track not found"
    return
  end

  gui.is_running = true
  gui.last_result = "Running..."

  -- Only use Template for focused FX mode
  -- (Template needs GetFocusedFX to work properly)
  if gui.mode == 0 and not override_track then
    set_extstate_from_gui()

    local ok, err = pcall(dofile, TEMPLATE_PATH)
    r.UpdateArrange()

    if ok then
      gui.last_result = string.format("Success! (%d items)", item_count)

      -- Add to history
      if gui.focused_track then
        local track_guid = get_track_guid(gui.focused_track)
        local name = gui.focused_fx_name
        add_to_history(name, track_guid, gui.focused_track_name, "focused")
      end
    else
      gui.last_result = "Error: " .. tostring(err)
    end
  else
    -- For chain mode or saved chains, use native REAPER command
    -- This avoids all AudioSweet console output
    local orig_selected_tracks = {}
    for i = 0, r.CountTracks(0) - 1 do
      local track = r.GetTrack(0, i)
      if r.IsTrackSelected(track) then
        orig_selected_tracks[#orig_selected_tracks + 1] = track
      end
    end

    for i = 0, r.CountTracks(0) - 1 do
      r.SetTrackSelected(r.GetTrack(0, i), false)
    end

    r.SetTrackSelected(target_track, true)

    -- Set handle before running
    r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))

    -- Use native REAPER command
    r.Main_OnCommand(40361, 0)  -- Apply track FX to items as new take

    for i = 0, r.CountTracks(0) - 1 do
      r.SetTrackSelected(r.GetTrack(0, i), false)
    end
    for _, track in ipairs(orig_selected_tracks) do
      if r.ValidatePtr2(0, track, "MediaTrack*") then
        r.SetTrackSelected(track, true)
      end
    end

    r.UpdateArrange()
    gui.last_result = string.format("Success! (%d items)", item_count)

    -- Add to history
    if target_track then
      local track_guid = get_track_guid(target_track)
      local track_name, track_num = get_track_name_and_number(target_track)
      local name = string.format("#%d - %s", track_num, track_name)
      add_to_history(name, track_guid, name, "chain")
    end
  end

  gui.is_running = false
end

local function run_saved_chain_copy_mode(tr, chain_name, item_count)
  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = "Error: No FX on track"
    gui.is_running = false
    return
  end

  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local scope = scope_names[gui.copy_scope + 1]
  local pos = pos_names[gui.copy_pos + 1]

  local ops = 0
  for i = 0, item_count - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then
      if scope == "all_takes" then
        local take_count = r.CountTakes(it)
        for t = 0, take_count - 1 do
          local tk = r.GetTake(it, t)
          if tk then
            for fx = 0, fx_count - 1 do
              local dest_idx = (pos == "head") and 0 or r.TakeFX_GetCount(tk)
              r.TrackFX_CopyToTake(tr, fx, tk, dest_idx, false)
              ops = ops + 1
            end
          end
        end
      else
        local tk = r.GetActiveTake(it)
        if tk then
          if pos == "head" then
            for fx = fx_count - 1, 0, -1 do
              r.TrackFX_CopyToTake(tr, fx, tk, 0, false)
              ops = ops + 1
            end
          else
            for fx = 0, fx_count - 1 do
              local dest_idx = r.TakeFX_GetCount(tk)
              r.TrackFX_CopyToTake(tr, fx, tk, dest_idx, false)
              ops = ops + 1
            end
          end
        end
      end
    end
  end

  r.UpdateArrange()
  gui.last_result = string.format("Success! [%s] Copy (%d ops)", chain_name, ops)
  gui.is_running = false
end

local function run_saved_chain_apply_mode(tr, chain_name, item_count)
  -- Set handle before running
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))

  local orig_selected_tracks = {}
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    if r.IsTrackSelected(track) then
      orig_selected_tracks[#orig_selected_tracks + 1] = track
    end
  end

  for i = 0, r.CountTracks(0) - 1 do
    r.SetTrackSelected(r.GetTrack(0, i), false)
  end

  r.SetTrackSelected(tr, true)
  r.Main_OnCommand(40361, 0)

  for i = 0, r.CountTracks(0) - 1 do
    r.SetTrackSelected(r.GetTrack(0, i), false)
  end
  for _, track in ipairs(orig_selected_tracks) do
    if r.ValidatePtr2(0, track, "MediaTrack*") then
      r.SetTrackSelected(track, true)
    end
  end

  r.UpdateArrange()
  gui.last_result = string.format("Success! [%s] Apply (%d items)", chain_name, item_count)
  gui.is_running = false
end

local function run_saved_chain(chain_idx)
  local chain = gui.saved_chains[chain_idx]
  if not chain then return end

  local tr = find_track_by_guid(chain.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", chain.track_name)
    return
  end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  if gui.is_running then return end

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  if gui.action == 1 then
    run_saved_chain_copy_mode(tr, chain.name, item_count)
  else
    run_saved_chain_apply_mode(tr, chain.name, item_count)
  end

  -- Add to history
  add_to_history(chain.name, chain.track_guid, chain.track_name, "chain")

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", gui.action == 1 and "Copy" or "Apply", chain.name), -1)
end

local function run_history_item(hist_idx)
  run_saved_chain(hist_idx)  -- Same execution as saved chain
end

------------------------------------------------------------
-- GUI Rendering
------------------------------------------------------------
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
        gui.mode = 0; gui.action = 0; gui.apply_method = 0
      end
      if ImGui.MenuItem(ctx, 'Focused Copy', nil, false, true) then
        gui.mode = 0; gui.action = 1; gui.copy_scope = 0; gui.copy_pos = 0
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'Chain Apply (Render)', nil, false, true) then
        gui.mode = 1; gui.action = 0; gui.apply_method = 1
      end
      if ImGui.MenuItem(ctx, 'Chain Copy', nil, false, true) then
        gui.mode = 1; gui.action = 1; gui.copy_scope = 0; gui.copy_pos = 0
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Debug') then
      local rv, new_val = ImGui.MenuItem(ctx, 'Enable Debug Mode', nil, gui.debug, true)
      if rv then gui.debug = new_val end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg("[AudioSweet GUI] Version v251028_0003\n" ..
          "Complete AudioSweet control center\n" ..
          "Features: Saved Chains, History tracking, Compact UI\n")
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  -- Main content with compact layout
  local has_valid_fx = update_focused_fx_display()
  local item_count = r.CountSelectedMediaItems(0)

  -- === STATUS BAR ===
  if has_valid_fx then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
  end

  if gui.mode == 0 then
    ImGui.Text(ctx, gui.focused_fx_name)
  else
    ImGui.Text(ctx, gui.focused_track_name ~= "" and ("Track: " .. gui.focused_track_name) or "No track focused")
  end
  ImGui.PopStyleColor(ctx)

  ImGui.SameLine(ctx)
  ImGui.Text(ctx, string.format(" | Items: %d", item_count))

  -- Show FX chain in Chain mode
  if gui.mode == 1 and #gui.focused_track_fx_list > 0 then
    ImGui.BeginChild(ctx, "FXChainList", 0, 80, ImGui.WindowFlags_None)
    for _, fx in ipairs(gui.focused_track_fx_list) do
      local status = fx.offline and "[offline]" or (fx.enabled and "[on]" or "[byp]")
      ImGui.Text(ctx, string.format("%02d) %s %s", fx.index + 1, fx.name, status))
    end
    ImGui.EndChild(ctx)

    if has_valid_fx and ImGui.Button(ctx, "Save This Chain", -1, 0) then
      gui.show_save_popup = true
      gui.new_chain_name = gui.focused_track_name
    end
  end

  ImGui.Separator(ctx)

  -- === MODE & ACTION (Radio buttons, horizontal) ===
  ImGui.Text(ctx, "Mode:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Focused", gui.mode == 0) then gui.mode = 0 end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Chain", gui.mode == 1) then gui.mode = 1 end

  ImGui.SameLine(ctx, 0, 30)
  ImGui.Text(ctx, "Action:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Apply", gui.action == 0) then gui.action = 0 end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Copy", gui.action == 1) then gui.action = 1 end

  -- === COPY/APPLY SETTINGS (Compact horizontal) ===
  if gui.action == 1 then
    ImGui.Text(ctx, "Copy:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Active##scope", gui.copy_scope == 0) then gui.copy_scope = 0 end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "All Takes##scope", gui.copy_scope == 1) then gui.copy_scope = 1 end
    ImGui.SameLine(ctx, 0, 20)
    if ImGui.RadioButton(ctx, "Tail##pos", gui.copy_pos == 0) then gui.copy_pos = 0 end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Head##pos", gui.copy_pos == 1) then gui.copy_pos = 1 end
  else
    ImGui.Text(ctx, "Apply:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Auto##method", gui.apply_method == 0) then gui.apply_method = 0 end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Render##method", gui.apply_method == 1) then gui.apply_method = 1 end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Glue##method", gui.apply_method == 2) then gui.apply_method = 2 end
    ImGui.SameLine(ctx, 0, 20)
    ImGui.SetNextItemWidth(ctx, 80)
    local rv, new_val = ImGui.InputDouble(ctx, "Handle(s)", gui.handle_seconds, 0, 0, "%.1f")
    if rv then gui.handle_seconds = math.max(0, new_val) end
  end

  ImGui.Separator(ctx)

  -- === RUN BUTTON (moved before Quick Process) ===
  local can_run = has_valid_fx and item_count > 0 and not gui.is_running
  if not can_run then ImGui.BeginDisabled(ctx) end
  if ImGui.Button(ctx, "RUN AUDIOSWEET", -1, 35) then
    run_audiosweet(nil)
  end
  if not can_run then ImGui.EndDisabled(ctx) end

  -- === STATUS (below RUN button) ===
  if gui.last_result ~= "" then
    if gui.last_result:match("^Success") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
    elseif gui.last_result:match("^Error") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFF00FF)
    end
    ImGui.Text(ctx, gui.last_result)
    ImGui.PopStyleColor(ctx)
  end

  ImGui.Separator(ctx)

  -- === QUICK PROCESS (Saved + History, side by side) ===
  if #gui.saved_chains > 0 or #gui.history > 0 then
    local avail_w = ImGui.GetContentRegionAvail(ctx)
    local col1_w = avail_w * 0.5 - 5

    -- Left: Saved Chains
    ImGui.BeginChild(ctx, "SavedCol", col1_w, 150, ImGui.WindowFlags_None)
    ImGui.Text(ctx, "SAVED CHAINS")
    ImGui.Separator(ctx)
    local to_delete = nil
    for i, chain in ipairs(gui.saved_chains) do
      ImGui.PushID(ctx, i)
      if ImGui.Button(ctx, chain.name, col1_w - 25, 0) then
        run_saved_chain(i)
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "X", 20, 0) then
        to_delete = i
      end
      ImGui.PopID(ctx)
    end
    if to_delete then delete_saved_chain(to_delete) end
    ImGui.EndChild(ctx)

    ImGui.SameLine(ctx)

    -- Right: History
    ImGui.BeginChild(ctx, "HistoryCol", 0, 150, ImGui.WindowFlags_None)
    ImGui.Text(ctx, "HISTORY")
    ImGui.Separator(ctx)
    for i, item in ipairs(gui.history) do
      ImGui.PushID(ctx, 1000 + i)
      if ImGui.Button(ctx, item.name, -1, 0) then
        local tr = find_track_by_guid(item.track_guid)
        if tr then
          run_saved_chain_apply_mode(tr, item.name, r.CountSelectedMediaItems(0))
        end
      end
      ImGui.PopID(ctx)
    end
    ImGui.EndChild(ctx)
  end

  ImGui.End(ctx)

  -- === SAVE CHAIN POPUP ===
  if gui.show_save_popup then
    ImGui.OpenPopup(ctx, "Save Chain")
    gui.show_save_popup = false
  end

  if ImGui.BeginPopupModal(ctx, "Save Chain", true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Enter a name for this FX chain:")
    local rv, new_name = ImGui.InputText(ctx, "##chainname", gui.new_chain_name, 256)
    if rv then gui.new_chain_name = new_name end

    if ImGui.Button(ctx, "Save", 100, 0) then
      if gui.new_chain_name ~= "" and gui.focused_track then
        local track_guid = get_track_guid(gui.focused_track)
        add_saved_chain(gui.new_chain_name, track_guid, gui.focused_track_name)
        gui.new_chain_name = ""
        ImGui.CloseCurrentPopup(ctx)
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 100, 0) then
      gui.new_chain_name = ""
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  return open
end

------------------------------------------------------------
-- Main Loop
------------------------------------------------------------
local function loop()
  gui.open = draw_gui()
  if gui.open then r.defer(loop) end
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
load_saved_chains()
load_history()
r.defer(loop)
