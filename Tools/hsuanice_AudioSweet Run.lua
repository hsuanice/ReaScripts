--[[
@description AudioSweet Run
@author hsuanice
@version 0.2.0
@provides
  [main] .
@about
  # AudioSweet Run

  Intelligent AudioSweet execution with automatic mode detection.

  ## Behavior
  - **Normal Mode** (no placeholder found):
    • Intelligent window detection:
      - Priority 1: Chain FX window open → Chain mode (process full FX chain)
      - Priority 2: Single FX floating window → Single FX mode (process one FX)
      - Priority 3: No FX window → Chain mode on preview target track (default)
    • Executes AudioSweet Core with auto-detected mode
    • Window state always overrides GUI settings
    • Reads all settings from GUI ExtState

  - **Preview Mode** (placeholder found):
    • Validates item selection on preview target track
    • Stops current preview (removes placeholder, unsolo)
    • Executes RGWH Core on selected items
    • Moves rendered results back to original source track
    • Stays in normal state (does not restore preview)

  ## Preview Mode Requirements
  - Must have item selection (otherwise shows warning)
  - Items must be on the preview target track
  - Respects current FX state (does not modify FX chain)
  - Time selection: if present, RGWH determines scope automatically
  - No time selection: uses item units mode

  ## Debug Mode
  Set DEBUG = true in script to enable detailed console logging:
  - Mode detection (Normal vs Preview)
  - Window state detection (chain/single/none)
  - ExtState settings loaded
  - Preview cleanup steps
  - Item move operations

  ## Requirements
  - AudioSweet ReaImGui GUI for ExtState configuration
  - AudioSweet Core library
  - RGWH Core library (for Preview Mode)
  - Works independently - can be assigned to keyboard shortcuts

@changelog
  v0.2.0 (2025-12-23) [internal: v251223.2256]
    - CHANGED: Version bump to 0.2.0 (public beta)

  v0.1.2 (2025-12-23) [internal: v251223.1924]
    - CHANGED: Added Copy+Apply action name support for GUI/Core integration

  v0.1.1 (2025-12-22) [internal: v251222.1706]
    - CHANGED: All executions now produce single undo operation
      • External undo control enabled before calling AudioSweet Core
      • AudioSweet Core v0.1.7: Skips internal undo when EXTERNAL_UNDO_CONTROL="1"
      • Cleaner undo stack (one "AudioSweet Run (Normal/Preview)" entry)
      • Matches GUI v0.1.24 behavior for consistent user experience

  v0.1.0 (2025-12-21) [internal: v251221.1803]
    - ADDED: Sync GUI settings to AudioSweet Core + RGWH Core before execution
      • Apply/Copy action, copy scope/pos now set in hsuanice_AS ExtState
      • File naming settings now set in hsuanice_AS ExtState
      • Channel mode now set in hsuanice_AS (AS_APPLY_FX_MODE)
      • Handle seconds now set in RGWH project ExtState
    - ADDED: Optional debug file log on Desktop (Console + file)
    - COMPLETE: Unified AudioSweet execution script with automatic mode detection
    - Normal Mode: Intelligent window detection system
      • Chain FX window focused → Chain mode (full FX chain processing)
      • Single FX floating window → Single FX mode (isolated FX processing)
      • No FX window → Chain mode on default preview target track
      • Window state detection via GetFocusedFX + TrackFX_GetChainVisible + TrackFX_GetOpen
      • Window state always takes priority over GUI settings
      • Sets correct ExtState for AudioSweet Core: "hsuanice_AS/AS_MODE" = "focused"|"chain"
      • Sets OVERRIDE ExtState for chain mode without focused FX
    - Preview Mode: Complete workflow for preview execution
      • Detects placeholder items (note format: "PREVIEWING @ Track <n> - <FXName>")
      • Validates item selection on preview target track
      • Stops preview: deletes placeholder, unsolo all
      • Executes RGWH Core on selected items
      • Moves rendered results back to original source track
      • Stays in normal state (no preview restoration)
      • Respects time selection for RGWH scope determination
    - Integration:
      • Reads all settings from AudioSweet GUI ExtState ("hsuanice_AS_GUI" namespace)
      • Supports GUID-based track lookup for duplicate track names
      • Compatible with AudioSweet Core OVERRIDE mechanism
    - Debug Mode: Optional detailed logging (set DEBUG = true)
    - Single script for unified workflow - no manual mode switching needed

  [internal: v251221.1556]
    - FIXED: Correct ExtState namespace and key for AudioSweet Core integration
      • Changed from "hsuanice_AS_GUI/mode" to "hsuanice_AS/AS_MODE"
      • Mode values changed from numeric (0/1) to string ("focused"/"chain")
      • Resolves issue where chain mode was executing as focused mode
    - DEBUG: Added MessageBox debug output (later removed - caused execution interference)

  [internal: v251221.1158]
    - Initial implementation of unified AudioSweet Run script
    - Placeholder detection for Normal vs Preview mode split
    - Basic window detection logic (later revised for correct priority)
--]]

local r = reaper

------------------------------------------------------------
-- User Settings
------------------------------------------------------------
local DEBUG = false  -- Set to true for detailed console logging
local DEBUG_LOG_PATH = (os.getenv("HOME") or "") .. "/Desktop/AudioSweet Run Debug.log"

------------------------------------------------------------
-- Constants
------------------------------------------------------------
local SETTINGS_NAMESPACE = "hsuanice_AS_GUI"
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*/)")

local function debug_log(msg)
  if not DEBUG then
    return
  end

  r.ShowConsoleMsg(msg)

  if DEBUG_LOG_PATH ~= "/Desktop/AudioSweet Run Debug.log" then
    local f = io.open(DEBUG_LOG_PATH, "a")
    if f then
      f:write(msg)
      f:close()
    end
  end
end

------------------------------------------------------------
-- Helper Functions: ExtState Readers
------------------------------------------------------------

-- Get ExtState as integer
local function get_int(key, default)
  local val = r.GetExtState(SETTINGS_NAMESPACE, key)
  if val == "" then return default end
  return tonumber(val) or default
end

-- Get ExtState as string
local function get_string(key, default)
  local val = r.GetExtState(SETTINGS_NAMESPACE, key)
  if val == "" then return default end
  return val
end

-- Get ExtState as boolean
local function get_bool(key, default)
  local val = r.GetExtState(SETTINGS_NAMESPACE, key)
  if val == "" then return default end
  return val == "1"
end

local function sync_gui_settings_to_core()
  local action = get_int("action", 0)
  local copy_scope = get_int("copy_scope", 0)
  local copy_pos = get_int("copy_pos", 0)
  local channel_mode = get_int("channel_mode", 0)
  local channel_mode_str = (channel_mode == 1) and "mono" or (channel_mode == 2) and "multi" or "auto"
  local multi_channel_policy = get_string("multi_channel_policy", "source_playback")
  local handle_seconds_str = get_string("handle_seconds", "0")
  local handle_seconds = tonumber(handle_seconds_str) or 0
  local use_whole_file = get_bool("use_whole_file", false)
  local debug_enabled = get_bool("debug", false)
  local use_alias = get_bool("use_alias", false)
  local fxname_show_type = get_bool("fxname_show_type", true)
  local fxname_show_vendor = get_bool("fxname_show_vendor", false)
  local fxname_strip_symbol = get_bool("fxname_strip_symbol", true)
  local chain_token_source = get_int("chain_token_source", 0)
  local chain_alias_joiner = get_string("chain_alias_joiner", "")
  local max_fx_tokens = get_int("max_fx_tokens", 3)
  local trackname_strip_symbols = get_bool("trackname_strip_symbols", true)
  local sanitize_token = get_bool("sanitize_token", false)
  local handle_to_set = use_whole_file and 999999 or handle_seconds

  -- AudioSweet Core reads from "hsuanice_AS"
  local action_names = { "apply", "copy", "apply_after_copy" }
  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local chain_token_names = { "track", "aliases", "fxchain" }

  r.SetExtState("hsuanice_AS", "AS_ACTION", action_names[action + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_SCOPE", scope_names[copy_scope + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_POS", pos_names[copy_pos + 1], false)
  r.SetExtState("hsuanice_AS", "AS_APPLY_FX_MODE", channel_mode_str, false)
  r.SetExtState("hsuanice_AS", "AS_MULTI_CHANNEL_POLICY", multi_channel_policy, false)
  r.SetExtState("hsuanice_AS", "DEBUG", debug_enabled and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)

  -- File naming settings
  r.SetExtState("hsuanice_AS", "USE_ALIAS", use_alias and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_TYPE", fxname_show_type and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_VENDOR", fxname_show_vendor and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_STRIP_SYMBOL", fxname_strip_symbol and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "AS_CHAIN_TOKEN_SOURCE", chain_token_names[chain_token_source + 1], false)
  r.SetExtState("hsuanice_AS", "AS_CHAIN_ALIAS_JOINER", chain_alias_joiner, false)
  r.SetExtState("hsuanice_AS", "AS_MAX_FX_TOKENS", tostring(max_fx_tokens), false)
  r.SetExtState("hsuanice_AS", "TRACKNAME_STRIP_SYMBOLS", trackname_strip_symbols and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "SANITIZE_TOKEN_FOR_FILENAME", sanitize_token and "1" or "0", false)

  -- RGWH Core reads handle settings from project ExtState "RGWH"
  r.SetProjExtState(0, "RGWH", "HANDLE_MODE", "seconds")
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(handle_to_set))
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", debug_enabled and "2" or "0")

  return {
    action = action,
    copy_scope = copy_scope,
    copy_pos = copy_pos,
    channel_mode = channel_mode,
    channel_mode_str = channel_mode_str,
    multi_channel_policy = multi_channel_policy,
    handle_seconds_str = handle_seconds_str,
    handle_seconds = handle_seconds,
    use_whole_file = use_whole_file,
    debug_enabled = debug_enabled,
    use_alias = use_alias,
    fxname_show_type = fxname_show_type,
    fxname_show_vendor = fxname_show_vendor,
    fxname_strip_symbol = fxname_strip_symbol,
    chain_token_source = chain_token_source,
    chain_alias_joiner = chain_alias_joiner,
    max_fx_tokens = max_fx_tokens,
    trackname_strip_symbols = trackname_strip_symbols,
    sanitize_token = sanitize_token,
    action_str = action_names[action + 1],
    copy_scope_str = scope_names[copy_scope + 1],
    copy_pos_str = pos_names[copy_pos + 1],
    chain_token_str = chain_token_names[chain_token_source + 1],
    handle_to_set = handle_to_set,
  }
end

------------------------------------------------------------
-- Helper Functions: Track Utilities
------------------------------------------------------------

-- Get track GUID
local function get_track_guid(track)
  if not track or not r.ValidatePtr2(0, track, "MediaTrack*") then
    return nil
  end
  return r.GetTrackGUID(track)
end

-- Find track by GUID
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
-- Helper Functions: Preview Detection
------------------------------------------------------------

-- Find AudioSweet Preview placeholder and extract source track info
-- Returns: source_track_num (1-based), source_track_obj (MediaTrack*), placeholder_item (MediaItem*)
local function find_preview_placeholder()
  local item_count = r.CountMediaItems(0)
  for i = 0, item_count - 1 do
    local item = r.GetMediaItem(0, i)
    local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)

    -- Check if this is a preview placeholder
    if note and note:match("^PREVIEWING @") then
      -- Parse: "PREVIEWING @ Track <n> - <FXName>"
      -- Extract the source track number (1-based) from the note
      local track_num = note:match("PREVIEWING @ Track (%d+)")
      if track_num then
        track_num = tonumber(track_num)
        -- Get source track by number (convert 1-based to 0-based index)
        local source_track = r.GetTrack(0, track_num - 1)
        if source_track and r.ValidatePtr2(0, source_track, "MediaTrack*") then
          return track_num, source_track, item
        end
      end
    end
  end
  return nil, nil, nil
end

------------------------------------------------------------
-- Mode Detection
------------------------------------------------------------

local function detect_mode()
  local source_track_num, source_track_obj, placeholder_item = find_preview_placeholder()

  if placeholder_item then
    return "preview", {
      source_track_num = source_track_num,
      source_track = source_track_obj,
      placeholder = placeholder_item
    }
  else
    return "normal", nil
  end
end

------------------------------------------------------------
-- Normal Mode Execution
------------------------------------------------------------

local function execute_normal_mode()
  if DEBUG then
    debug_log("\n========================================\n")
    debug_log("[AudioSweet Run] NORMAL MODE\n")
    debug_log("========================================\n")
  end

  -- Determine execution mode: single FX vs chain
  -- Priority:
  --   1. Has FX chain window open → chain mode (process full FX chain)
  --   2. Has single FX floating window → single FX mode (process one FX)
  --   3. Neither → default to chain mode on preview target track

  local mode_to_use = 1  -- Default: chain mode (0 = single FX mode, 1 = chain mode)
  local override_track_idx = nil
  local override_fx_idx = nil

  -- First, check GetFocusedFX to get potential track/FX info
  local retval, trackidx, itemidx, fxidx = r.GetFocusedFX()

  if DEBUG then
    debug_log(string.format("[Normal Mode] GetFocusedFX: retval=%d, track=%d, item=%d, fx=%d\n",
      retval, trackidx or -1, itemidx or -1, fxidx or -1))
  end

  -- Window detection: Determine if chain window or single FX window is open
  local chain_window_track = nil
  local chain_window_open = false
  local single_fx_floating = false

  -- If GetFocusedFX detected a track FX, check window type
  if retval == 1 and trackidx then
    local focused_track = r.GetTrack(0, trackidx - 1)
    if focused_track then
      -- Check if the specific FX has a floating window open
      local fx_window_open = r.TrackFX_GetOpen(focused_track, fxidx)

      -- Check if the FX chain window is open
      local chain_visible = r.TrackFX_GetChainVisible(focused_track)

      if DEBUG then
        local _, fx_name = r.TrackFX_GetFXName(focused_track, fxidx, "")
        local _, track_name = r.GetSetMediaTrackInfo_String(focused_track, "P_NAME", "", false)
        debug_log(string.format("  • Track: %s\n", track_name))
        debug_log(string.format("  • FX: #%d - %s\n", fxidx, fx_name))
        debug_log(string.format("  • FX floating window open: %s\n", tostring(fx_window_open)))
        debug_log(string.format("  • FX chain window visible: %d\n", chain_visible))
      end

      -- Determine window type
      -- TrackFX_GetOpen returns: true if floating window is open, false otherwise
      -- TrackFX_GetChainVisible returns: -1 if closed, >= 0 if open
      if fx_window_open and chain_visible == -1 then
        -- FX has floating window AND chain is closed → single FX mode
        single_fx_floating = true
        if DEBUG then
          debug_log(string.format("  → Decision: SINGLE FX mode (floating window open, chain closed)\n"))
        end
      elseif chain_visible ~= -1 then
        -- Chain window is open → chain mode (regardless of FX floating window)
        chain_window_track = focused_track
        chain_window_open = true
        if DEBUG then
          debug_log(string.format("  → Decision: CHAIN mode (chain window open)\n"))
        end
      else
        -- FX is selected but no window is open
        if DEBUG then
          debug_log(string.format("  → Decision: No visible window (will check other tracks)\n"))
        end
      end
    end
  end

  -- If no chain window on focused track, check selected track
  if not chain_window_open then
    local selected_track = r.GetSelectedTrack(0, 0)
    if selected_track then
      local chain_visible = r.TrackFX_GetChainVisible(selected_track)
      if chain_visible ~= -1 then
        chain_window_track = selected_track
        chain_window_open = true
      end
    end
  end

  -- If still no chain window, check preview target track
  if not chain_window_open then
    local preview_target_track_name = get_string("preview_target_track", "AudioSweet")
    local preview_target_track_guid = get_string("preview_target_track_guid", "")
    local preview_track = nil

    -- Try GUID first
    if preview_target_track_guid ~= "" then
      preview_track = find_track_by_guid(preview_target_track_guid)
    end

    -- Fallback to name search
    if not preview_track then
      for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tn == preview_target_track_name then
          preview_track = tr
          break
        end
      end
    end

    if preview_track then
      local chain_visible = r.TrackFX_GetChainVisible(preview_track)
      if chain_visible ~= -1 then
        chain_window_track = preview_track
        chain_window_open = true
      end
    end
  end

  -- Decision logic: Select execution mode based on window state
  if chain_window_open and chain_window_track then
    -- Priority 1: FX chain window is open → use chain mode
    mode_to_use = 1  -- chain mode
    override_track_idx = r.CSurf_TrackToID(chain_window_track, false) - 1
    override_fx_idx = 0

    if DEBUG then
      local _, track_name = r.GetSetMediaTrackInfo_String(chain_window_track, "P_NAME", "", false)
      local debug_msg = string.format(
        "[AudioSweet Run v251221.1803]\n\n" ..
        "[Priority 1] FX CHAIN WINDOW detected\n" ..
        "→ Track: %s\n" ..
        "→ Using CHAIN mode\n",
        track_name
      )

      if retval == 1 then
        -- Get FX name for debug
        local fx_track = r.GetTrack(0, trackidx - 1)
        local _, fx_name = r.TrackFX_GetFXName(fx_track, fxidx, "")
        debug_msg = debug_msg .. string.format("\n→ Note: FX #%d (%s) is selected inside chain\n   (ignored for mode detection)",
          fxidx, fx_name)
      end

      debug_log("\n" .. debug_msg .. "\n")
    end
  elseif single_fx_floating and retval == 1 then
    -- Priority 2: Single FX floating window (NOT chain window)
    mode_to_use = 0  -- single FX mode

    if DEBUG then
      local fx_track = r.GetTrack(0, trackidx - 1)
      local _, fx_name = r.TrackFX_GetFXName(fx_track, fxidx, "")
      local _, track_name = r.GetSetMediaTrackInfo_String(fx_track, "P_NAME", "", false)
      local debug_msg = string.format(
        "[AudioSweet Run v251221.1803]\n\n" ..
        "[Priority 2] SINGLE FX FLOATING WINDOW detected\n" ..
        "→ Track: %s\n" ..
        "→ FX: #%d - %s\n" ..
        "→ Using SINGLE FX mode",
        track_name, fxidx, fx_name
      )
      debug_log("\n" .. debug_msg .. "\n")
    end
  else
    -- Priority 3: No FX activity → default to chain mode on preview target track
    local preview_target_track_name = get_string("preview_target_track", "AudioSweet")
    local preview_target_track_guid = get_string("preview_target_track_guid", "")
    local target_track = nil

    -- Try GUID first
    if preview_target_track_guid ~= "" then
      target_track = find_track_by_guid(preview_target_track_guid)
    end

    -- Fallback to name search
    if not target_track then
      for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tn == preview_target_track_name then
          target_track = tr
          break
        end
      end
    end

    if target_track then
      mode_to_use = 1  -- chain mode
      override_track_idx = r.CSurf_TrackToID(target_track, false) - 1
      override_fx_idx = 0

      if DEBUG then
        local _, track_name = r.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
        local debug_msg = string.format(
          "[AudioSweet Run v251221.1556]\n\n" ..
          "[Priority 3] NO FX ACTIVITY detected\n" ..
          "→ Using default preview target track: %s\n" ..
          "→ Using CHAIN mode (default)",
          track_name
        )
        debug_log("\n" .. debug_msg .. "\n")
      end
    else
      -- No target track found → error
      r.MB("Cannot find preview target track for Normal Mode execution.", "AudioSweet Run - Normal Mode", 0)
      if DEBUG then
        debug_log("\n[ERROR] No target track found\n")
        debug_log("========================================\n")
      end
      return
    end
  end

  -- Set mode in ExtState for AudioSweet Core to read
  -- NOTE: AudioSweet Core reads from "hsuanice_AS" namespace with key "AS_MODE"
  -- Terminology mapping for backward compatibility:
  --   mode_to_use = 0 (single FX mode internally) → ExtState = "focused" (for AudioSweet Core)
  --   mode_to_use = 1 (chain mode internally)     → ExtState = "chain" (for AudioSweet Core)
  local mode_str = (mode_to_use == 0) and "focused" or "chain"
  r.SetExtState("hsuanice_AS", "AS_MODE", mode_str, false)

  -- Set OVERRIDE if needed (for chain mode without focused FX)
  if override_track_idx and override_fx_idx then
    r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(override_track_idx), false)
    r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", tostring(override_fx_idx), false)

    if DEBUG then
      debug_log(string.format("  → Setting OVERRIDE: track_idx=%d, fx_idx=%d\n", override_track_idx, override_fx_idx))
    end
  end

  if DEBUG then
    debug_log(string.format("\n[Normal Mode] Final mode: %s (ExtState: \"%s\")\n",
      mode_to_use == 0 and "SINGLE FX" or "CHAIN", mode_str))
    debug_log("[Normal Mode] Calling AudioSweet Core...\n\n")
  end

  -- Load and execute AudioSweet Core
  local AS_CORE = dofile(SCRIPT_DIR .. "../Library/hsuanice_AudioSweet Core.lua")

  -- AudioSweet Core's main() is called during dofile()
  -- It will read the mode from ExtState and execute accordingly

  if DEBUG then
    debug_log(string.format("\n[AudioSweet Run] AudioSweet Core execution completed\n"))
    debug_log(string.format("[AudioSweet Run] Mode used: %s\n",
      mode_to_use == 0 and "SINGLE FX" or "CHAIN"))
  end
end

------------------------------------------------------------
-- Preview Mode Execution
------------------------------------------------------------

local function execute_preview_mode(preview_info)
  if DEBUG then
    debug_log("\n========================================\n")
    debug_log("[AudioSweet Run] PREVIEW MODE\n")
    debug_log("========================================\n")
    debug_log(string.format("  Source track: #%d\n", preview_info.source_track_num))
    debug_log(string.format("  Placeholder found: %s\n", preview_info.placeholder and "yes" or "no"))
  end

  -- 1. Validate item selection
  local sel_item_count = r.CountSelectedMediaItems(0)
  if sel_item_count == 0 then
    r.MB("Preview Mode requires item selection.\n\nPlease select items on the preview target track.", "AudioSweet Run - Preview Mode", 0)
    if DEBUG then
      debug_log("[Preview Mode] ERROR: No item selection\n")
      debug_log("========================================\n")
    end
    return
  end

  if DEBUG then
    debug_log(string.format("  Selected items: %d\n", sel_item_count))
  end

  -- 2. Get preview target track (where items currently are)
  local preview_target_track_name = get_string("preview_target_track", "AudioSweet")
  local preview_target_track_guid = get_string("preview_target_track_guid", "")

  local preview_target_track = nil

  -- Try GUID first
  if preview_target_track_guid ~= "" then
    preview_target_track = find_track_by_guid(preview_target_track_guid)
  end

  -- Fallback to name search
  if not preview_target_track then
    for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      if tn == preview_target_track_name then
        preview_target_track = tr
        break
      end
    end
  end

  if not preview_target_track then
    r.MB(string.format("Cannot find preview target track: %s", preview_target_track_name), "AudioSweet Run - Preview Mode", 0)
    if DEBUG then
      debug_log(string.format("[Preview Mode] ERROR: Preview target track not found: %s\n", preview_target_track_name))
      debug_log("========================================\n")
    end
    return
  end

  if DEBUG then
    local _, track_name = r.GetSetMediaTrackInfo_String(preview_target_track, "P_NAME", "", false)
    debug_log(string.format("  Preview target track: %s\n", track_name))
  end

  -- 3. Check for time selection
  local start_time, end_time = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local has_time_selection = (end_time - start_time) > 0.0001

  if DEBUG then
    debug_log(string.format("\n[Preview Mode] Step 2: Time selection check\n"))
    debug_log(string.format("  • Has time selection: %s\n", has_time_selection and "yes" or "no"))
    if has_time_selection then
      debug_log(string.format("  • Time range: %.3f - %.3f\n", start_time, end_time))
    end
  end

  -- 6. Load AudioSweet Core
  if DEBUG then
    debug_log("\n[Preview Mode] Step 3: Load AudioSweet Core\n")
  end

  -- Sync GUI settings to Core before execution
  sync_gui_settings_to_core()

  -- Use GUI mode in preview (focused/chain), fallback to chain on preview target track
  local gui_mode = get_int("mode", 0) -- 0=focused, 1=chain
  local mode_str = "chain"
  local override_track_idx = r.CSurf_TrackToID(preview_target_track, false) - 1
  local override_fx_idx = 0

  if gui_mode == 0 then
    local retval, trackidx, _, fxidx = r.GetFocusedFX()
    if retval == 1 and trackidx then
      local focused_track = r.GetTrack(0, trackidx - 1)
      if focused_track then
        mode_str = "focused"
        override_track_idx = r.CSurf_TrackToID(focused_track, false) - 1
        override_fx_idx = fxidx or 0
      end
    end
  end

  r.SetExtState("hsuanice_AS", "AS_MODE", mode_str, false)
  r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(override_track_idx), false)
  r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", tostring(override_fx_idx), false)

  if DEBUG then
    debug_log(string.format("  • GUI mode: %s\n", gui_mode == 0 and "focused" or "chain"))
    debug_log(string.format("  • AS_MODE: %s\n", mode_str))
    debug_log(string.format("  • OVERRIDE_TRACK_IDX: %d\n", override_track_idx))
    debug_log(string.format("  • OVERRIDE_FX_IDX: %d\n", override_fx_idx))
  end

  -- 7. Execute AudioSweet Core
  if DEBUG then
    debug_log("\n[Preview Mode] Step 4: Execute AudioSweet Core\n")
  end

  local ok, err = pcall(dofile, SCRIPT_DIR .. "../Library/hsuanice_AudioSweet Core.lua")

  if not ok then
    r.MB(string.format("AudioSweet Core error: %s", err or "unknown"), "AudioSweet Run - Preview Mode", 0)
    if DEBUG then
      debug_log(string.format("[Preview Mode] ERROR: AudioSweet Core failed: %s\n", err or "unknown"))
      debug_log("========================================\n")
    end
    return
  end

  if DEBUG then
    debug_log("  • AudioSweet Core execution completed\n")
  end

  -- 8. Move rendered items back to source track
  if DEBUG then
    debug_log(string.format("\n[Preview Mode] Step 5: Move items back to source track #%d\n", preview_info.source_track_num))
  end

  -- Collect all items on preview target track (these are the rendered results)
  local items_to_move = {}
  local item_count = r.CountTrackMediaItems(preview_target_track)
  for i = 0, item_count - 1 do
    local item = r.GetTrackMediaItem(preview_target_track, i)
    items_to_move[#items_to_move + 1] = item
  end

  if DEBUG then
    debug_log(string.format("  • Items to move: %d\n", #items_to_move))
  end

  -- Move items to source track
  for _, item in ipairs(items_to_move) do
    r.MoveMediaItemToTrack(item, preview_info.source_track)
  end

  if DEBUG then
    debug_log(string.format("  • Moved %d items to source track\n", #items_to_move))
    debug_log("\n[Preview Mode] Complete - Staying in normal state\n")
    debug_log("========================================\n")
  end
end

------------------------------------------------------------
-- Main Execution
------------------------------------------------------------

local function main()
  -- CRITICAL: Output debug message BEFORE anything else
  if DEBUG then
    debug_log("\n" .. string.rep("=", 60) .. "\n")
    debug_log("[AudioSweet Run] Script Started (DEBUG=true)\n")
    debug_log(string.rep("=", 60) .. "\n")
    debug_log("[AudioSweet Run] Version: v0.2.0 (251223.2256)\n")
    debug_log(string.format("[AudioSweet Run] Debug log file: %s\n", DEBUG_LOG_PATH))

    -- Log GUI ExtState values as read by this script
    local action = get_int("action", 0)
    local action_names = { "apply", "copy", "apply_after_copy" }
    local action_str = action_names[action + 1] or "apply"
    local preview_target_track_name = get_string("preview_target_track", "AudioSweet")
    local preview_target_track_guid = get_string("preview_target_track_guid", "")
    local sync = sync_gui_settings_to_core()

    debug_log("[AudioSweet Run] GUI ExtState read:\n")
    debug_log(string.format("  * channel_mode: %s (%d)\n", sync.channel_mode_str, sync.channel_mode))
    debug_log(string.format("  * action: %s (%d)\n", action_str, action))
    debug_log(string.format("  * copy_scope: %s (%d)\n", sync.copy_scope_str, sync.copy_scope))
    debug_log(string.format("  * copy_pos: %s (%d)\n", sync.copy_pos_str, sync.copy_pos))
    debug_log(string.format("  * handle_seconds: %s (parsed=%.3f)\n", sync.handle_seconds_str, sync.handle_seconds))
    debug_log(string.format("  * use_whole_file: %s\n", sync.use_whole_file and "true" or "false"))
    debug_log(string.format("  * preview_target_track: %s\n", preview_target_track_name))
    if preview_target_track_guid ~= "" then
      debug_log(string.format("  * preview_target_track_guid: %s\n", preview_target_track_guid))
    end
    debug_log(string.format("  * use_alias: %s\n", sync.use_alias and "true" or "false"))
    debug_log(string.format("  * fxname_show_type: %s\n", sync.fxname_show_type and "true" or "false"))
    debug_log(string.format("  * fxname_show_vendor: %s\n", sync.fxname_show_vendor and "true" or "false"))
    debug_log(string.format("  * fxname_strip_symbol: %s\n", sync.fxname_strip_symbol and "true" or "false"))
    debug_log(string.format("  * chain_token_source: %s (%d)\n", sync.chain_token_str, sync.chain_token_source))
    debug_log(string.format("  * chain_alias_joiner: %s\n", sync.chain_alias_joiner))
    debug_log(string.format("  * max_fx_tokens: %d\n", sync.max_fx_tokens))
    debug_log(string.format("  * trackname_strip_symbols: %s\n", sync.trackname_strip_symbols and "true" or "false"))
    debug_log(string.format("  * sanitize_token: %s\n", sync.sanitize_token and "true" or "false"))
    debug_log(string.rep("-", 60) .. "\n")

    debug_log("[AudioSweet Run] Synced ExtState:\n")
    debug_log(string.format("  * hsuanice_AS/AS_ACTION: %s\n", sync.action_str))
    debug_log(string.format("  * hsuanice_AS/AS_COPY_SCOPE: %s\n", sync.copy_scope_str))
    debug_log(string.format("  * hsuanice_AS/AS_COPY_POS: %s\n", sync.copy_pos_str))
    debug_log(string.format("  * hsuanice_AS/AS_APPLY_FX_MODE: %s\n", sync.channel_mode_str))
    debug_log(string.format("  * hsuanice_AS/USE_ALIAS: %s\n", sync.use_alias and "1" or "0"))
    debug_log(string.format("  * hsuanice_AS/FXNAME_SHOW_TYPE: %s\n", sync.fxname_show_type and "1" or "0"))
    debug_log(string.format("  * hsuanice_AS/FXNAME_SHOW_VENDOR: %s\n", sync.fxname_show_vendor and "1" or "0"))
    debug_log(string.format("  * hsuanice_AS/FXNAME_STRIP_SYMBOL: %s\n", sync.fxname_strip_symbol and "1" or "0"))
    debug_log(string.format("  * hsuanice_AS/AS_CHAIN_TOKEN_SOURCE: %s\n", sync.chain_token_str))
    debug_log(string.format("  * hsuanice_AS/AS_CHAIN_ALIAS_JOINER: %s\n", sync.chain_alias_joiner))
    debug_log(string.format("  * hsuanice_AS/AS_MAX_FX_TOKENS: %d\n", sync.max_fx_tokens))
    debug_log(string.format("  * hsuanice_AS/TRACKNAME_STRIP_SYMBOLS: %s\n", sync.trackname_strip_symbols and "1" or "0"))
    debug_log(string.format("  * hsuanice_AS/SANITIZE_TOKEN_FOR_FILENAME: %s\n", sync.sanitize_token and "1" or "0"))
    debug_log(string.format("  * RGWH/HANDLE_SECONDS: %.3f%s\n", sync.handle_to_set,
      sync.use_whole_file and " (whole file)" or ""))
    debug_log(string.rep("-", 60) .. "\n")
  else
    sync_gui_settings_to_core()
  end

  r.Undo_BeginBlock()

  -- Tell AudioSweet Core to NOT create its own undo block (we're managing it here for single undo)
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "1", false)

  -- Detect mode
  local mode, info = detect_mode()

  if DEBUG then
    debug_log(string.format("\n[AudioSweet Run] Detected mode: %s\n", mode:upper()))
  end

  if mode == "normal" then
    execute_normal_mode()
    r.Undo_EndBlock("AudioSweet Run (Normal)", -1)
  elseif mode == "preview" then
    -- Temporary: Use normal execution flow during preview for observation
    execute_normal_mode()
    r.Undo_EndBlock("AudioSweet Run (Preview)", -1)
  end

  -- Clear external undo control flag after execution
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "", false)
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
main()
