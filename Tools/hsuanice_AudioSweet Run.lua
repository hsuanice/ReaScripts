--[[
@description AudioSweet Run
@author hsuanice
@version 0.1.0
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
  v0.1.0 (2025-12-21) [internal: v251221.1652]
    - REFACTOR: Unified terminology throughout codebase for clarity
      • Renamed: "focused mode" → "single FX mode" (clearer intent)
      • Renamed: focused_fx_floating → single_fx_floating (variable names)
      • Updated: All comments, debug messages, and documentation
      • NOTE: ExtState still uses "focused"|"chain" for backward compatibility with AudioSweet Core
      • Impact: Code is now self-documenting and consistent with user-facing terminology
    - Terminology mapping (for maintainers):
      • "single FX mode" (internal) = "focused" (ExtState value for AudioSweet Core)
      • "chain mode" (internal) = "chain" (ExtState value)
    - No functional changes - purely documentation and variable naming improvements

  v251221.1644]
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

------------------------------------------------------------
-- Constants
------------------------------------------------------------
local SETTINGS_NAMESPACE = "hsuanice_AS_GUI"
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*/)")

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
    r.ShowConsoleMsg("\n========================================\n")
    r.ShowConsoleMsg("[AudioSweet Run] NORMAL MODE\n")
    r.ShowConsoleMsg("========================================\n")
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
    r.ShowConsoleMsg(string.format("[Normal Mode] GetFocusedFX: retval=%d, track=%d, item=%d, fx=%d\n",
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
        r.ShowConsoleMsg(string.format("  • Track: %s\n", track_name))
        r.ShowConsoleMsg(string.format("  • FX: #%d - %s\n", fxidx, fx_name))
        r.ShowConsoleMsg(string.format("  • FX floating window open: %s\n", tostring(fx_window_open)))
        r.ShowConsoleMsg(string.format("  • FX chain window visible: %d\n", chain_visible))
      end

      -- Determine window type
      -- TrackFX_GetOpen returns: true if floating window is open, false otherwise
      -- TrackFX_GetChainVisible returns: -1 if closed, >= 0 if open
      if fx_window_open and chain_visible == -1 then
        -- FX has floating window AND chain is closed → single FX mode
        single_fx_floating = true
        if DEBUG then
          r.ShowConsoleMsg(string.format("  → Decision: SINGLE FX mode (floating window open, chain closed)\n"))
        end
      elseif chain_visible ~= -1 then
        -- Chain window is open → chain mode (regardless of FX floating window)
        chain_window_track = focused_track
        chain_window_open = true
        if DEBUG then
          r.ShowConsoleMsg(string.format("  → Decision: CHAIN mode (chain window open)\n"))
        end
      else
        -- FX is selected but no window is open
        if DEBUG then
          r.ShowConsoleMsg(string.format("  → Decision: No visible window (will check other tracks)\n"))
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
        "[AudioSweet Run v251221.1652]\n\n" ..
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

      r.ShowConsoleMsg("\n" .. debug_msg .. "\n")
      r.MB(debug_msg, "AudioSweet Run - Debug", 0)
    end
  elseif single_fx_floating and retval == 1 then
    -- Priority 2: Single FX floating window (NOT chain window)
    mode_to_use = 0  -- single FX mode

    if DEBUG then
      local fx_track = r.GetTrack(0, trackidx - 1)
      local _, fx_name = r.TrackFX_GetFXName(fx_track, fxidx, "")
      local _, track_name = r.GetSetMediaTrackInfo_String(fx_track, "P_NAME", "", false)
      local debug_msg = string.format(
        "[AudioSweet Run v251221.1652]\n\n" ..
        "[Priority 2] SINGLE FX FLOATING WINDOW detected\n" ..
        "→ Track: %s\n" ..
        "→ FX: #%d - %s\n" ..
        "→ Using SINGLE FX mode",
        track_name, fxidx, fx_name
      )
      r.ShowConsoleMsg("\n" .. debug_msg .. "\n")
      r.MB(debug_msg, "AudioSweet Run - Debug", 0)
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
        r.ShowConsoleMsg("\n" .. debug_msg .. "\n")
        r.MB(debug_msg, "AudioSweet Run - Debug", 0)
      end
    else
      -- No target track found → error
      r.MB("Cannot find preview target track for Normal Mode execution.", "AudioSweet Run - Normal Mode", 0)
      if DEBUG then
        r.ShowConsoleMsg("\n[ERROR] No target track found\n")
        r.ShowConsoleMsg("========================================\n")
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
      r.ShowConsoleMsg(string.format("  → Setting OVERRIDE: track_idx=%d, fx_idx=%d\n", override_track_idx, override_fx_idx))
    end
  end

  if DEBUG then
    r.ShowConsoleMsg(string.format("\n[Normal Mode] Final mode: %s (ExtState: \"%s\")\n",
      mode_to_use == 0 and "SINGLE FX" or "CHAIN", mode_str))
    r.ShowConsoleMsg("[Normal Mode] Calling AudioSweet Core...\n\n")
  end

  -- Load and execute AudioSweet Core
  local AS_CORE = dofile(SCRIPT_DIR .. "../Library/hsuanice_AudioSweet Core.lua")

  -- AudioSweet Core's main() is called during dofile()
  -- It will read the mode from ExtState and execute accordingly

  if DEBUG then
    r.ShowConsoleMsg(string.format("\n[AudioSweet Run] AudioSweet Core execution completed\n"))
    r.ShowConsoleMsg(string.format("[AudioSweet Run] Mode used: %s\n",
      mode_to_use == 0 and "SINGLE FX" or "CHAIN"))
  end
end

------------------------------------------------------------
-- Preview Mode Execution
------------------------------------------------------------

local function execute_preview_mode(preview_info)
  if DEBUG then
    r.ShowConsoleMsg("\n========================================\n")
    r.ShowConsoleMsg("[AudioSweet Run] PREVIEW MODE\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg(string.format("  Source track: #%d\n", preview_info.source_track_num))
    r.ShowConsoleMsg(string.format("  Placeholder found: %s\n", preview_info.placeholder and "yes" or "no"))
  end

  -- 1. Validate item selection
  local sel_item_count = r.CountSelectedMediaItems(0)
  if sel_item_count == 0 then
    r.MB("Preview Mode requires item selection.\n\nPlease select items on the preview target track.", "AudioSweet Run - Preview Mode", 0)
    if DEBUG then
      r.ShowConsoleMsg("[Preview Mode] ERROR: No item selection\n")
      r.ShowConsoleMsg("========================================\n")
    end
    return
  end

  if DEBUG then
    r.ShowConsoleMsg(string.format("  Selected items: %d\n", sel_item_count))
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
      r.ShowConsoleMsg(string.format("[Preview Mode] ERROR: Preview target track not found: %s\n", preview_target_track_name))
      r.ShowConsoleMsg("========================================\n")
    end
    return
  end

  if DEBUG then
    local _, track_name = r.GetSetMediaTrackInfo_String(preview_target_track, "P_NAME", "", false)
    r.ShowConsoleMsg(string.format("  Preview target track: %s\n", track_name))
  end

  -- 3. Verify all selected items are on preview target track
  for i = 0, sel_item_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local item_track = r.GetMediaItemTrack(item)
    if item_track ~= preview_target_track then
      r.MB("All selected items must be on the preview target track.", "AudioSweet Run - Preview Mode", 0)
      if DEBUG then
        r.ShowConsoleMsg("[Preview Mode] ERROR: Selected items not all on preview target track\n")
        r.ShowConsoleMsg("========================================\n")
      end
      return
    end
  end

  -- 4. Stop preview: Delete placeholder and unsolo
  if DEBUG then
    r.ShowConsoleMsg("\n[Preview Mode] Step 1: Stop preview\n")
  end

  -- Delete placeholder
  r.DeleteTrackMediaItem(r.GetMediaItemTrack(preview_info.placeholder), preview_info.placeholder)
  if DEBUG then
    r.ShowConsoleMsg("  • Placeholder deleted\n")
  end

  -- Unsolo all
  r.Main_OnCommand(41185, 0) -- Item: Unsolo all
  r.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks
  if DEBUG then
    r.ShowConsoleMsg("  • Unsolo all (items + tracks)\n")
  end

  -- 5. Check for time selection
  local start_time, end_time = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local has_time_selection = (end_time - start_time) > 0.0001

  if DEBUG then
    r.ShowConsoleMsg(string.format("\n[Preview Mode] Step 2: Time selection check\n"))
    r.ShowConsoleMsg(string.format("  • Has time selection: %s\n", has_time_selection and "yes" or "no"))
    if has_time_selection then
      r.ShowConsoleMsg(string.format("  • Time range: %.3f - %.3f\n", start_time, end_time))
    end
  end

  -- 6. Load RGWH Core
  if DEBUG then
    r.ShowConsoleMsg("\n[Preview Mode] Step 3: Load RGWH Core\n")
  end

  local RGWH = dofile(SCRIPT_DIR .. "../Library/hsuanice_RGWH Core.lua")

  -- 7. Prepare RGWH arguments
  local channel_mode = get_int("channel_mode", 0)  -- 0=auto, 1=mono, 2=multi
  local channel_mode_str = (channel_mode == 1) and "mono" or (channel_mode == 2) and "multi" or "auto"

  local action = get_int("action", 0)  -- 0=glue, 1=render, 2=auto
  local op_str = (action == 1) and "render" or (action == 2) and "auto" or "glue"

  -- Determine selection_scope based on time selection
  local selection_scope = "auto"  -- Let RGWH determine

  if DEBUG then
    r.ShowConsoleMsg(string.format("  • channel_mode: %s\n", channel_mode_str))
    r.ShowConsoleMsg(string.format("  • op: %s\n", op_str))
    r.ShowConsoleMsg(string.format("  • selection_scope: %s (RGWH will determine)\n", selection_scope))
  end

  -- 8. Execute RGWH Core
  if DEBUG then
    r.ShowConsoleMsg("\n[Preview Mode] Step 4: Execute RGWH Core\n")
  end

  local ok, err = RGWH.core({
    op = op_str,
    selection_scope = selection_scope,
    channel_mode = channel_mode_str,
  })

  if not ok then
    r.MB(string.format("RGWH Core error: %s", err or "unknown"), "AudioSweet Run - Preview Mode", 0)
    if DEBUG then
      r.ShowConsoleMsg(string.format("[Preview Mode] ERROR: RGWH Core failed: %s\n", err or "unknown"))
      r.ShowConsoleMsg("========================================\n")
    end
    return
  end

  if DEBUG then
    r.ShowConsoleMsg("  • RGWH Core execution completed\n")
  end

  -- 9. Move rendered items back to source track
  if DEBUG then
    r.ShowConsoleMsg(string.format("\n[Preview Mode] Step 5: Move items back to source track #%d\n", preview_info.source_track_num))
  end

  -- Collect all items on preview target track (these are the rendered results)
  local items_to_move = {}
  local item_count = r.CountTrackMediaItems(preview_target_track)
  for i = 0, item_count - 1 do
    local item = r.GetTrackMediaItem(preview_target_track, i)
    items_to_move[#items_to_move + 1] = item
  end

  if DEBUG then
    r.ShowConsoleMsg(string.format("  • Items to move: %d\n", #items_to_move))
  end

  -- Move items to source track
  for _, item in ipairs(items_to_move) do
    r.MoveMediaItemToTrack(item, preview_info.source_track)
  end

  if DEBUG then
    r.ShowConsoleMsg(string.format("  • Moved %d items to source track\n", #items_to_move))
    r.ShowConsoleMsg("\n[Preview Mode] Complete - Staying in normal state\n")
    r.ShowConsoleMsg("========================================\n")
  end
end

------------------------------------------------------------
-- Main Execution
------------------------------------------------------------

local function main()
  -- CRITICAL: Output debug message BEFORE anything else
  if DEBUG then
    r.ShowConsoleMsg("\n" .. string.rep("=", 60) .. "\n")
    r.ShowConsoleMsg("[AudioSweet Run] Script Started (DEBUG=true)\n")
    r.ShowConsoleMsg(string.rep("=", 60) .. "\n")
    r.ShowConsoleMsg("[AudioSweet Run] Version: v0.1.1 (251221.1652)\n")
  end

  r.Undo_BeginBlock()

  -- Detect mode
  local mode, info = detect_mode()

  if DEBUG then
    r.ShowConsoleMsg(string.format("\n[AudioSweet Run] Detected mode: %s\n", mode:upper()))
  end

  if mode == "normal" then
    execute_normal_mode()
    r.Undo_EndBlock("AudioSweet Run (Normal)", -1)
  elseif mode == "preview" then
    execute_preview_mode(info)
    r.Undo_EndBlock("AudioSweet Run (Preview)", -1)
  end
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
main()
