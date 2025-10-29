--[[
@description AudioSweet GUI - ImGui Interface for AudioSweet
@author hsuanice
@version 251029.1934
@about
  Complete AudioSweet control center with:
  - Focused/Chain modes with FX chain display
  - Apply/Copy actions
  - Saved Chains (memory-based, no focus required)
  - History tracking (auto-record recent operations)
  - Compact, intuitive UI with radio buttons
  - Persistent settings (remembers all settings between sessions)
  - Configurable history size via Settings menu
  - Improved auto-focus FX with CLAP plugin support
  - Clear History button for quick cleanup
  - Debug mode with detailed console logging

@usage
  Run this script in REAPER to open the AudioSweet GUI window.

@changelog
  251029.1934
    - Verified: Channel Mode (Auto/Mono/Multi) now working correctly with AudioSweet Core v251029.1400.
      - Auto mode now correctly detects mono items (e.g., chanmode=2/3/4) and renders as mono
      - Fixed root cause: AudioSweet Core was using wrong API for chanmode detection
      - Integration confirmed: GUI → ExtState → AudioSweet Core → RGWH Core all working
    - Note: This version is compatible with:
      - AudioSweet Core v251029.1400+ (REQUIRED - contains critical chanmode API fix)
      - AudioSweet Template v251028_2315+
      - RGWH Core v251029.1400+ (contains matching chanmode fix)

  251029_1230
    - Added: Channel Mode control (Auto/Mono/Multi) in Apply settings.
      - New UI: Radio buttons below Apply method (lines 1182-1198)
      - Auto: Automatically decides based on item's channel mode setting (not just source)
      - Mono: Force mono render (single channel output)
      - Multi: Force multi-channel render (stereo/multi output)
      - Setting persists between sessions (saved in ExtState)
      - Passes to AudioSweet Core via AS_APPLY_FX_MODE ExtState (line 484)
    - Fixed: AS_APPLY_FX_MODE now properly set (was missing, causing auto-detect issues)

  251029_1218
    - Fixed: History recall now reliably focuses correct FX using REAPER native actions.
      - Previous: Used TrackFX_Show which failed for CLAP/VST3 plugins (focus detection issues)
      - Now: Uses REAPER actions 41749-41756 (Open/close UI for FX #1-8 on last touched track)
      - History now stores FX index (0-based) along with track GUID and name
      - For FX #1-8: Uses native action 41749+idx for reliable focus
      - For FX #9+: Falls back to TrackFX_Show (limitation of REAPER actions)
      - Validates FX still exists at stored index before execution
      - Lines: 349-401 (history storage), 788-862 (focused apply with action)
    - Technical: History storage format changed from "name|guid|trackname|mode" to "name|guid|trackname|mode|fxidx"
    - Integration: Works with AudioSweet Template v251028_2315 (ExtState override support)

  251028_2245
    - Added: FX Name Formatting UI in Settings menu.
      - New menu item: Settings → FX Name Formatting... (line 961-963)
      - Popup modal with three checkboxes and examples (lines 1010-1045)
      - Show Plugin Type: Adds format prefix (CLAP:, VST3:, AU:, VST:) to file names
      - Show Vendor Name: Includes vendor in parentheses (FabFilter)
      - Strip Spaces & Symbols: Removes spaces/symbols for cleaner names (ProQ4 vs Pro-Q 4)
      - Changes auto-save to ExtState and propagate to AudioSweet Core
      - Solves issue where code default changes didn't apply due to ExtState caching
      - Example display shows different combinations: 'AS1-CLAP: Pro-Q 4 (FabFilter)' vs 'AS1-CLAP:ProQ4'

  251028_2240
    - Added: FX name formatting control via ExtState.
      - New GUI state variables: fxname_show_type (true), fxname_show_vendor (false), fxname_strip_symbol (true)
      - GUI sets ExtState keys: FXNAME_SHOW_TYPE, FXNAME_SHOW_VENDOR, FXNAME_STRIP_SYMBOL
      - AudioSweet Core reads these ExtState values to format FX names in rendered file names
      - Show Type = true → includes plugin format prefix (CLAP:, VST3:, AU:, VST:)
      - Show Vendor = true → includes vendor name in parentheses (FabFilter)
      - Strip Symbol = true → removes spaces and symbols from names
      - Lines: 161-163, 193-195, 225-227, 444-446

  251028_2235
    - Fixed: History button now calls run_history_item() instead of run_saved_chain_apply_mode().
      - Previous: History buttons were hardcoded to always use chain mode
      - Now: History buttons respect the original mode (focused/chain)
      - Line 1155: Changed from run_saved_chain_apply_mode() to run_history_item()

  251028_2230
    - Fixed: History items from Focused mode now correctly execute in focused mode.
      - Previous: All history items executed as chain mode (processed entire FX chain)
      - Now: Focused history items find and focus the specific FX by name
      - New function: run_history_focused_apply() searches FX by name, focuses it, runs Template in focused mode
      - Chain mode history items continue to use chain mode (correct behavior)
      - Lines: 733-824, 851-857
    - Improved: FX name matching for history replay (supports partial matching)

  251028_2215
    - Added: Debug console logging with [AS GUI] prefix.
      - Shows saved chain execution details (name, items, FX count)
      - Reports FX focus attempts and timing
      - Displays execution parameters (mode, action, handle)
      - Logs success/error results
      - Lines: 587-589, 599-601, 620-621, 627-629, 637-647, 663-680

  251028_2210
    - Added: Clear History button in History panel.
      - Small button positioned at top-right of History section
      - Clears all history items from memory and ProjExtState
      - Lines 991-1000

  251028_2200
    - Improved: Enhanced FX focus mechanism for better CLAP plugin compatibility.
      - Extended timeout from 500ms to 1 second
      - Multiple focus attempts with different methods:
        1. Show FX chain window (TrackFX_Show flag 3)
        2. Show floating FX window (TrackFX_Show flag 1)
        3. Retry FX chain window
      - Better error message: "CLAP plugins may need manual focus"
      - Chain mode: Lines 452-483
      - Saved chain apply: Lines 561-592
    - Fixed: History items now properly execute with their original mode (focused/chain).
      - run_history_item() rewritten to respect stored mode
      - Lines 644-690

  251028_2145
    - Fixed: Saved Chains and History now auto-focus FX before execution.
      - Previous: Failed when all FX windows were closed (GetFocusedFX returned 0)
      - Now: Automatically shows and focuses track FX, waits up to 500ms for focus
      - Displays clear error if FX cannot be focused
      - Chain mode: Lines 442-460
      - Saved chain apply: Lines 534-552
    - Fixed: load_history() error - changed MAX_HISTORY to gui.max_history (line 266)

  251028_2130
    - Added: Settings menu with configurable History size (1-50 items, default 10).
      - Menu: Settings → History Settings...
      - Setting saved persistently in ExtState
      - History auto-trims when size is reduced
      - Functions: Lines 91, 120, 149, 638-685
    - Fixed: Saved Chains and History now properly use AudioSweet/RGWH pipeline.
      - Previous: Used native REAPER command 40361 (direct render, no naming/handle)
      - Now: Focus track FX and execute via AudioSweet Template
      - Properly applies AudioSweet naming conventions and RGWH handle settings
      - Chain mode execution: Lines 420-451
      - Saved chain apply: Lines 520-556

  251028_2045
    - Added: GUI settings persistence - all settings now saved and restored between sessions.
      - Settings saved: mode, action, copy_scope, copy_pos, apply_method, handle_seconds, debug
      - Uses ExtState (hsuanice_AS_GUI namespace) for persistent storage
      - Auto-saves whenever any setting is changed
      - Auto-loads on startup (line 819)
      - Functions: save_gui_settings() / load_gui_settings() (lines 99-137)

  251028_2030
    - Fixed: Handle seconds setting now works correctly in Focused mode.
      - Root cause: AudioSweet Template v251022_1617 was using hardcoded 5.0s default
      - Solution: Updated Template to v251028_2050 (reads from ProjExtState first)
      - GUI already correctly sets ProjExtState before execution (line 302)
      - Requires: AudioSweet Template v251028_2050 or later

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
  channel_mode = 0,      -- 0=auto, 1=mono, 2=multi
  handle_seconds = 5.0,
  debug = false,
  show_summary = true,
  warn_takefx = true,
  max_history = 10,      -- Maximum number of history items to keep
  fxname_show_type = true,     -- Show FX type prefix (CLAP:, VST3:, etc.)
  fxname_show_vendor = true,  -- Show vendor name in parentheses
  fxname_strip_symbol = true,  -- Strip spaces and symbols
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
  show_settings_popup = false,
  show_fxname_popup = false,
}

------------------------------------------------------------
-- GUI Settings Persistence
------------------------------------------------------------
local SETTINGS_NAMESPACE = "hsuanice_AS_GUI"

local function save_gui_settings()
  r.SetExtState(SETTINGS_NAMESPACE, "mode", tostring(gui.mode), true)
  r.SetExtState(SETTINGS_NAMESPACE, "action", tostring(gui.action), true)
  r.SetExtState(SETTINGS_NAMESPACE, "copy_scope", tostring(gui.copy_scope), true)
  r.SetExtState(SETTINGS_NAMESPACE, "copy_pos", tostring(gui.copy_pos), true)
  r.SetExtState(SETTINGS_NAMESPACE, "apply_method", tostring(gui.apply_method), true)
  r.SetExtState(SETTINGS_NAMESPACE, "channel_mode", tostring(gui.channel_mode), true)
  r.SetExtState(SETTINGS_NAMESPACE, "handle_seconds", tostring(gui.handle_seconds), true)
  r.SetExtState(SETTINGS_NAMESPACE, "debug", gui.debug and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "show_summary", gui.show_summary and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "warn_takefx", gui.warn_takefx and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "max_history", tostring(gui.max_history), true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_show_type", gui.fxname_show_type and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_show_vendor", gui.fxname_show_vendor and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_strip_symbol", gui.fxname_strip_symbol and "1" or "0", true)
end

local function load_gui_settings()
  local function get_int(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and tonumber(val) or default
  end

  local function get_bool(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    if val == "" then return default end
    return val == "1"
  end

  local function get_float(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and tonumber(val) or default
  end

  gui.mode = get_int("mode", 0)
  gui.action = get_int("action", 0)
  gui.copy_scope = get_int("copy_scope", 0)
  gui.copy_pos = get_int("copy_pos", 0)
  gui.apply_method = get_int("apply_method", 0)
  gui.channel_mode = get_int("channel_mode", 0)
  gui.handle_seconds = get_float("handle_seconds", 5.0)
  gui.debug = get_bool("debug", false)
  gui.show_summary = get_bool("show_summary", true)
  gui.warn_takefx = get_bool("warn_takefx", true)
  gui.max_history = get_int("max_history", 10)
  gui.fxname_show_type = get_bool("fxname_show_type", true)
  gui.fxname_show_vendor = get_bool("fxname_show_vendor", false)
  gui.fxname_strip_symbol = get_bool("fxname_strip_symbol", true)
end

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
  while idx < gui.max_history do
    local ok, data = r.GetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. idx)
    if ok == 0 or data == "" then break end
    local name, guid, track_name, mode, fx_idx_str = data:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name and guid then
      gui.history[#gui.history + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
        mode = mode or "chain",
        fx_index = tonumber(fx_idx_str) or 0,
      }
    end
    idx = idx + 1
  end
end

local function add_to_history(name, track_guid, track_name, mode, fx_index)
  fx_index = fx_index or 0

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
    fx_index = fx_index,
  })

  -- Trim to max_history
  while #gui.history > gui.max_history do
    table.remove(gui.history)
  end

  -- Save to ExtState
  for i = 0, gui.max_history - 1 do
    r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
  end
  for i, item in ipairs(gui.history) do
    local data = string.format("%s|%s|%s|%s|%d", item.name, item.track_guid, item.track_name, item.mode, item.fx_index)
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
  local channel_names = { "auto", "mono", "multi" }

  r.SetExtState("hsuanice_AS", "AS_MODE", mode_names[gui.mode + 1], false)
  r.SetExtState("hsuanice_AS", "AS_ACTION", action_names[gui.action + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_SCOPE", scope_names[gui.copy_scope + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_POS", pos_names[gui.copy_pos + 1], false)
  r.SetExtState("hsuanice_AS", "AS_APPLY", method_names[gui.apply_method + 1], false)
  r.SetExtState("hsuanice_AS", "AS_APPLY_FX_MODE", channel_names[gui.channel_mode + 1], false)
  r.SetExtState("hsuanice_AS", "DEBUG", gui.debug and "1" or "0", false)

  -- Debug output
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] ExtState: channel_mode=%s (gui.channel_mode=%d)\n",
      channel_names[gui.channel_mode + 1], gui.channel_mode))
  end
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)  -- Always disable summary dialog
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))

  -- Set RGWH Core debug level (0 = silent, no console output)
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", gui.debug and "2" or "0")

  -- Set FX name formatting options
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_TYPE", gui.fxname_show_type and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_VENDOR", gui.fxname_show_vendor and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_STRIP_SYMBOL", gui.fxname_strip_symbol and "1" or "0", false)
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
        -- Get FX index from GetFocusedFX
        local retval, trackidx, itemidx, fxidx = r.GetFocusedFX()
        local fx_index = (retval == 1) and normalize_focused_fx_index(fxidx or 0) or 0
        add_to_history(name, track_guid, gui.focused_track_name, "focused", fx_index)
      end
    else
      gui.last_result = "Error: " .. tostring(err)
    end
  else
    -- For chain mode, focus first FX and use AudioSweet Template
    local fx_count = r.TrackFX_GetCount(target_track)
    if fx_count == 0 then
      gui.last_result = "Error: No FX on target track"
      gui.is_running = false
      return
    end

    -- Show and focus the first FX on target track
    -- Try method 1: Show FX chain window (3 = show chain + focus)
    r.TrackFX_Show(target_track, 0, 3)

    -- Wait and check if focused (up to 1 second)
    local start_time = r.time_precise()
    local focused = false
    local attempts = 0
    while r.time_precise() - start_time < 1.0 do
      local retval, trackidx, itemidx, fxidx = r.GetFocusedFX()
      if retval > 0 then
        focused = true
        break
      end

      -- Try alternative methods every 250ms
      if attempts == 0 and r.time_precise() - start_time > 0.25 then
        -- Method 2: Show individual FX window
        r.TrackFX_Show(target_track, 0, 1)  -- 1 = show floating window
        attempts = attempts + 1
      elseif attempts == 1 and r.time_precise() - start_time > 0.5 then
        -- Method 3: Try showing chain again
        r.TrackFX_Show(target_track, 0, 3)
        attempts = attempts + 1
      end
    end

    if not focused then
      gui.last_result = "Error: Could not focus FX (CLAP plugins may need manual focus)"
      gui.is_running = false
      return
    end

    -- Set ExtState for AudioSweet (chain mode)
    set_extstate_from_gui()
    r.SetExtState("hsuanice_AS", "AS_MODE", "chain", false)

    -- Run AudioSweet Template
    local ok, err = pcall(dofile, TEMPLATE_PATH)
    r.UpdateArrange()

    if ok then
      gui.last_result = string.format("Success! (%d items)", item_count)

      -- Add to history
      if target_track then
        local track_guid = get_track_guid(target_track)
        local track_name, track_num = get_track_name_and_number(target_track)
        local name = string.format("#%d - %s", track_num, track_name)
        add_to_history(name, track_guid, name, "chain", 0)  -- chain mode uses index 0
      end
    else
      gui.last_result = "Error: " .. tostring(err)
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
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Saved chain apply: '%s' (items=%d)\n", chain_name, item_count))
  end

  -- Focus first FX on the track to allow AudioSweet Template to work
  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = "Error: No FX on track"
    gui.is_running = false
    return
  end

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Track has %d FX, attempting to focus...\n", fx_count))
  end

  -- Show and focus the first FX
  -- Try method 1: Show FX chain window (3 = show chain + focus)
  r.TrackFX_Show(tr, 0, 3)

  -- Wait and check if focused (up to 1 second, check every 50ms)
  local start_time = r.time_precise()
  local focused = false
  local attempts = 0
  while r.time_precise() - start_time < 1.0 do
    local retval, trackidx, itemidx, fxidx = r.GetFocusedFX()
    if retval > 0 then
      focused = true
      break
    end

    -- Try alternative methods every 250ms
    if attempts == 0 and r.time_precise() - start_time > 0.25 then
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] Focus method 1 failed, trying floating window...\n")
      end
      -- Method 2: Show individual FX window
      r.TrackFX_Show(tr, 0, 1)  -- 1 = show floating window
      attempts = attempts + 1
    elseif attempts == 1 and r.time_precise() - start_time > 0.5 then
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] Focus method 2 failed, retrying chain window...\n")
      end
      -- Method 3: Try showing chain again
      r.TrackFX_Show(tr, 0, 3)
      attempts = attempts + 1
    end
  end

  if not focused then
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] ERROR: Could not focus FX after all attempts\n")
    end
    gui.last_result = "Error: Could not focus FX (CLAP plugins may need manual focus)"
    gui.is_running = false
    return
  end

  if gui.debug then
    local elapsed = r.time_precise() - start_time
    r.ShowConsoleMsg(string.format("[AS GUI] FX focused successfully (%.3fs, %d attempts)\n", elapsed, attempts + 1))
  end

  -- Set ExtState for AudioSweet (chain mode)
  local mode_names = { "focused", "chain" }
  local action_names = { "apply", "copy" }
  local method_names = { "auto", "render", "glue" }

  r.SetExtState("hsuanice_AS", "AS_MODE", "chain", false)
  r.SetExtState("hsuanice_AS", "AS_ACTION", action_names[gui.action + 1], false)
  r.SetExtState("hsuanice_AS", "AS_APPLY", method_names[gui.apply_method + 1], false)
  r.SetExtState("hsuanice_AS", "DEBUG", gui.debug and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", gui.debug and "2" or "0")

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Executing AudioSweet Template (mode=chain, action=%s, handle=%.1fs)\n",
      gui.action == 0 and "apply" or "copy", gui.handle_seconds))
  end

  -- Run AudioSweet Template (it will use the focused track's FX chain)
  local ok, err = pcall(dofile, TEMPLATE_PATH)
  r.UpdateArrange()

  if ok then
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] Execution completed successfully\n"))
    end
    gui.last_result = string.format("Success! [%s] Apply (%d items)", chain_name, item_count)
  else
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] ERROR: %s\n", tostring(err)))
    end
    gui.last_result = "Error: " .. tostring(err)
  end

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
  add_to_history(chain.name, chain.track_guid, chain.track_name, "chain", 0)

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", gui.action == 1 and "Copy" or "Apply", chain.name), -1)
end

local function run_history_focused_apply(tr, fx_name, fx_idx, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] History focused apply: '%s' (fx_idx=%d, items=%d)\n", fx_name, fx_idx, item_count))
  end

  -- Validate FX still exists at this index
  local fx_count = r.TrackFX_GetCount(tr)
  if fx_idx >= fx_count then
    gui.last_result = string.format("Error: FX #%d not found (track only has %d FX)", fx_idx + 1, fx_count)
    gui.is_running = false
    return
  end

  -- Set track as last touched
  r.SetOnlyTrackSelected(tr)
  r.SetMixerScroll(tr)

  -- Use REAPER action to open/focus specific FX
  -- Actions 41749-41756 = Open/close UI for FX #1-8 on last touched track
  if fx_idx <= 7 then
    local action_id = 41749 + fx_idx  -- 41749 = FX #1, 41750 = FX #2, etc.
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] Using REAPER action %d to focus FX #%d\n", action_id, fx_idx + 1))
    end
    r.Main_OnCommand(action_id, 0)
  else
    -- For FX #9+, use TrackFX_Show
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] Using TrackFX_Show for FX #%d (beyond action range)\n", fx_idx + 1))
    end
    r.TrackFX_Show(tr, fx_idx, 3)
  end

  -- Wait for FX to be focused (up to 500ms)
  local start_time = r.time_precise()
  local focused = false
  while r.time_precise() - start_time < 0.5 do
    local retval, trackOut, itemOut, fxOut = r.GetFocusedFX()
    if retval == 1 and normalize_focused_fx_index(fxOut) == fx_idx then
      focused = true
      if gui.debug then
        r.ShowConsoleMsg(string.format("[AS GUI] FX focused successfully after %.3fs\n", r.time_precise() - start_time))
      end
      break
    end
  end

  if not focused then
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] WARNING: FX focus timeout, proceeding anyway\n")
    end
  end

  -- Set ExtState for AudioSweet (focused mode)
  set_extstate_from_gui()
  r.SetExtState("hsuanice_AS", "AS_MODE", "focused", false)

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Executing AudioSweet Template (mode=focused, action=%s, handle=%.1fs)\n",
      gui.action == 0 and "apply" or "copy", gui.handle_seconds))
  end

  -- Run AudioSweet Template
  local ok, err = pcall(dofile, TEMPLATE_PATH)
  r.UpdateArrange()

  if ok then
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Execution completed successfully\n")
    end
    gui.last_result = string.format("Success! [%s] Apply (%d items)", fx_name, item_count)
  else
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] ERROR: %s\n", tostring(err)))
    end
    gui.last_result = "Error: " .. tostring(err)
  end

  gui.is_running = false
end

local function run_history_item(hist_idx)
  local hist_item = gui.history[hist_idx]
  if not hist_item then return end

  local tr = find_track_by_guid(hist_item.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", hist_item.track_name)
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

  -- Check if this was originally a focused FX or chain
  if hist_item.mode == "focused" then
    -- For focused mode, use stored FX index
    if gui.action == 1 then
      run_saved_chain_copy_mode(tr, hist_item.name, item_count)
    else
      run_history_focused_apply(tr, hist_item.name, hist_item.fx_index or 0, item_count)
    end
  else
    -- Chain mode - use saved chain execution
    if gui.action == 1 then
      run_saved_chain_copy_mode(tr, hist_item.name, item_count)
    else
      run_saved_chain_apply_mode(tr, hist_item.name, item_count)
    end
  end

  -- Note: History doesn't re-add to history to avoid duplication

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", gui.action == 1 and "Copy" or "Apply", hist_item.name), -1)
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
        save_gui_settings()
      end
      if ImGui.MenuItem(ctx, 'Focused Copy', nil, false, true) then
        gui.mode = 0; gui.action = 1; gui.copy_scope = 0; gui.copy_pos = 0
        save_gui_settings()
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'Chain Apply (Render)', nil, false, true) then
        gui.mode = 1; gui.action = 0; gui.apply_method = 1
        save_gui_settings()
      end
      if ImGui.MenuItem(ctx, 'Chain Copy', nil, false, true) then
        gui.mode = 1; gui.action = 1; gui.copy_scope = 0; gui.copy_pos = 0
        save_gui_settings()
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Debug') then
      local rv, new_val = ImGui.MenuItem(ctx, 'Enable Debug Mode', nil, gui.debug, true)
      if rv then
        gui.debug = new_val
        save_gui_settings()
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Settings') then
      if ImGui.MenuItem(ctx, 'History Settings...', nil, false, true) then
        gui.show_settings_popup = true
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'FX Name Formatting...', nil, false, true) then
        gui.show_fxname_popup = true
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg("[AudioSweet GUI] Version v251028_2130\n" ..
          "Complete AudioSweet control center\n" ..
          "Features: Saved Chains, History tracking, Persistent settings, Configurable history, Compact UI\n")
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  -- Settings Popup
  if gui.show_settings_popup then
    ImGui.OpenPopup(ctx, 'History Settings')
    gui.show_settings_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'History Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Maximum History Items:")
    ImGui.SetNextItemWidth(ctx, 120)
    local rv, new_val = ImGui.InputInt(ctx, "##max_history", gui.max_history)
    if rv then
      gui.max_history = math.max(1, math.min(50, new_val))  -- Limit 1-50
      save_gui_settings()
      -- Trim history if needed
      while #gui.history > gui.max_history do
        table.remove(gui.history)
      end
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Range: 1-50 items")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- FX Name Formatting Popup
  if gui.show_fxname_popup then
    ImGui.OpenPopup(ctx, 'FX Name Formatting')
    gui.show_fxname_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'FX Name Formatting', true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Control how FX names appear in rendered file names:")
    ImGui.Separator(ctx)

    local changed = false
    local rv

    rv, gui.fxname_show_type = ImGui.Checkbox(ctx, "Show Plugin Type (CLAP:, VST3:, AU:, VST:)", gui.fxname_show_type)
    if rv then changed = true end

    rv, gui.fxname_show_vendor = ImGui.Checkbox(ctx, "Show Vendor Name (FabFilter)", gui.fxname_show_vendor)
    if rv then changed = true end

    rv, gui.fxname_strip_symbol = ImGui.Checkbox(ctx, "Strip Spaces & Symbols (ProQ4 vs Pro-Q 4)", gui.fxname_strip_symbol)
    if rv then changed = true end

    if changed then
      save_gui_settings()
    end

    ImGui.Separator(ctx)
    ImGui.TextWrapped(ctx, "Example:\nType=ON, Vendor=ON, Strip=OFF → 'AS1-CLAP: Pro-Q 4 (FabFilter)'\nType=ON, Vendor=OFF, Strip=ON → 'AS1-CLAP:ProQ4'")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
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
  if ImGui.RadioButton(ctx, "Focused", gui.mode == 0) then
    gui.mode = 0
    save_gui_settings()
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Chain", gui.mode == 1) then
    gui.mode = 1
    save_gui_settings()
  end

  ImGui.SameLine(ctx, 0, 30)
  ImGui.Text(ctx, "Action:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Apply", gui.action == 0) then
    gui.action = 0
    save_gui_settings()
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Copy", gui.action == 1) then
    gui.action = 1
    save_gui_settings()
  end

  -- === COPY/APPLY SETTINGS (Compact horizontal) ===
  if gui.action == 1 then
    ImGui.Text(ctx, "Copy:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Active##scope", gui.copy_scope == 0) then
      gui.copy_scope = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "All Takes##scope", gui.copy_scope == 1) then
      gui.copy_scope = 1
      save_gui_settings()
    end
    ImGui.SameLine(ctx, 0, 20)
    if ImGui.RadioButton(ctx, "Tail##pos", gui.copy_pos == 0) then
      gui.copy_pos = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Head##pos", gui.copy_pos == 1) then
      gui.copy_pos = 1
      save_gui_settings()
    end
  else
    ImGui.Text(ctx, "Apply:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Auto##method", gui.apply_method == 0) then
      gui.apply_method = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Render##method", gui.apply_method == 1) then
      gui.apply_method = 1
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Glue##method", gui.apply_method == 2) then
      gui.apply_method = 2
      save_gui_settings()
    end
    ImGui.SameLine(ctx, 0, 20)
    ImGui.SetNextItemWidth(ctx, 80)
    local rv, new_val = ImGui.InputDouble(ctx, "Handle(s)", gui.handle_seconds, 0, 0, "%.1f")
    if rv then
      gui.handle_seconds = math.max(0, new_val)
      save_gui_settings()
    end

    -- Channel Mode (second line under Apply)
    ImGui.Text(ctx, "Channel:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Auto##channel", gui.channel_mode == 0) then
      gui.channel_mode = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Mono##channel", gui.channel_mode == 1) then
      gui.channel_mode = 1
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Multi##channel", gui.channel_mode == 2) then
      gui.channel_mode = 2
      save_gui_settings()
    end
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
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + ImGui.GetContentRegionAvail(ctx) - 45)
    if ImGui.SmallButton(ctx, "Clear") then
      gui.history = {}
      -- Clear from ProjExtState
      for i = 0, gui.max_history - 1 do
        r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
      end
    end
    ImGui.Separator(ctx)
    for i, item in ipairs(gui.history) do
      ImGui.PushID(ctx, 1000 + i)
      if ImGui.Button(ctx, item.name, -1, 0) then
        run_history_item(i)
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
load_gui_settings()  -- Load saved GUI settings first
load_saved_chains()
load_history()
r.defer(loop)
