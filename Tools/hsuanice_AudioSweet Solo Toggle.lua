--[[
@description AudioSweet Solo Toggle
@author hsuanice
@version 0.2.0
@provides
  [main] .
@about
  # AudioSweet Solo Toggle

  Toggles solo state for the AudioSweet target track.

  ## Behavior
  - **Track Solo Mode (preview_solo_scope = 0)**:
    • Priority 1: If AudioSweet Preview is active (placeholder found) → Toggle the preview target track
    • Priority 2: If any track is currently soloed → Toggle that track's solo
    • Priority 3: No preview/solo → Toggle preview target track solo (from GUI settings)
  - **Item Solo Mode (preview_solo_scope = 1)**:
    • Toggle solo for selected items (REAPER command 41561)

  Note: Detects active preview via placeholder item, stays locked to preview target track

  ## Debug Mode
  Set DEBUG = true in script to enable detailed console logging:
  - ExtState settings loaded
  - Soloed track detection
  - Target track resolution steps
  - Final solo toggle action

  ## Requirements
  - AudioSweet ReaImGui GUI for ExtState configuration
  - Works independently - can be assigned to keyboard shortcuts in action list

@changelog
  v0.2.0 [Internal Build 251223.2256] - Public Beta Release
    - CHANGED: Version bump to 0.2.0 (public beta)

  v0.1.0 [Internal Build 251221.1123] - Public Beta Release
    - Intelligent solo toggle for AudioSweet Preview workflow
    - 3-priority target detection:
      • Priority 1: Active preview (placeholder found) → Toggle preview target track
      • Priority 2: Soloed track found → Toggle that track
      • Priority 3: No preview/solo → Toggle default preview target track
    - Stays locked to preview target track during active preview
    - Supports both track solo and item solo modes
    - Placeholder detection: extracts track number from "PREVIEWING @ Track <n>" note
    - Works in both Focused and Chain preview modes
    - Handles user editing/selection changes during preview
    - Built-in debug mode (set DEBUG = true for detailed logging)
    - Reads settings from AudioSweet ReaImGui GUI ExtState
    - Can be assigned to keyboard shortcuts in action list
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

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------

-- Get track GUID
local function get_track_guid(track)
  if not track or not r.ValidatePtr2(0, track, "MediaTrack*") then
    return nil
  end
  local guid = r.BR_GetMediaTrackGUID(track)
  return guid
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

-- Find AudioSweet Preview placeholder and extract target track
-- Returns: track_name (string or nil), track_obj (MediaTrack* or nil)
local function find_preview_target_from_placeholder()
  local item_count = r.CountMediaItems(0)
  for i = 0, item_count - 1 do
    local item = r.GetMediaItem(0, i)
    local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)

    -- Check if this is a preview placeholder
    if note and note:match("^PREVIEWING @") then
      -- Parse: "PREVIEWING @ Track <n> - <anything>"
      -- Extract the track number (1-based) from the note
      local track_num = note:match("PREVIEWING @ Track (%d+)")
      if track_num then
        track_num = tonumber(track_num)
        -- Get track by number (convert 1-based to 0-based index)
        local track = r.GetTrack(0, track_num - 1)
        if track and r.ValidatePtr2(0, track, "MediaTrack*") then
          local _, track_name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
          return track_name, track
        end
      end
    end
  end
  return nil, nil
end

------------------------------------------------------------
-- Main Solo Toggle Function
------------------------------------------------------------
local function toggle_solo()
  if DEBUG then
    r.ShowConsoleMsg("\n========================================\n")
    r.ShowConsoleMsg("[AS Solo Toggle] Script Executed\n")
    r.ShowConsoleMsg("========================================\n")
  end

  -- Load settings from ExtState
  local preview_solo_scope = get_int("preview_solo_scope", 0)  -- 0 = Track Solo, 1 = Item Solo
  local preview_target_track = get_string("preview_target_track", "AudioSweet")
  local preview_target_track_guid = get_string("preview_target_track_guid", "")

  -- Debug logging: ExtState settings
  if DEBUG then
    r.ShowConsoleMsg("\n[1] ExtState Settings Loaded:\n")
    r.ShowConsoleMsg(string.format("  • preview_solo_scope = %d (%s)\n", preview_solo_scope,
      preview_solo_scope == 0 and "Track Solo" or "Item Solo"))
    r.ShowConsoleMsg(string.format("  • preview_target_track = \"%s\"\n", preview_target_track))
    r.ShowConsoleMsg(string.format("  • preview_target_track_guid = \"%s\"\n",
      preview_target_track_guid ~= "" and preview_target_track_guid or "(empty)"))
  end

  -- Toggle solo based on solo_scope setting
  if preview_solo_scope == 0 then
    if DEBUG then
      r.ShowConsoleMsg("\n[2] Track Solo Mode - Starting target track resolution...\n")
    end

    -- Track solo: Check for active preview, then soloed track, then preview target
    local target_track = nil
    local track_name = ""
    local resolution_method = ""

    -- Priority 1: Check for AudioSweet Preview placeholder
    if DEBUG then
      r.ShowConsoleMsg("  [Priority 1] Checking for active AudioSweet Preview...\n")
    end

    local preview_track_name, preview_track_obj = find_preview_target_from_placeholder()
    if preview_track_obj then
      target_track = preview_track_obj
      track_name = preview_track_name
      resolution_method = "Active preview target track (Priority 1)"

      if DEBUG then
        local track_num = r.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER")
        r.ShowConsoleMsg(string.format("    ✓ Found active preview: \"%s\" (track #%d)\n",
          track_name, track_num))
      end
    end

    -- Priority 2: Find the first soloed track (fallback if no preview)
    if not target_track then
      if DEBUG then
        r.ShowConsoleMsg("    ✗ No active preview found\n")
        r.ShowConsoleMsg("  [Priority 2] Searching for currently soloed tracks...\n")
      end

      local track_count = r.CountTracks(0)
      for i = 0, track_count - 1 do
        local tr = r.GetTrack(0, i)
        local solo_state = r.GetMediaTrackInfo_Value(tr, "I_SOLO")

        if solo_state > 0 then
          -- Found a soloed track
          target_track = tr
          local _, tn = r.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
          track_name = tn
          resolution_method = "Currently soloed track (Priority 2)"

          if DEBUG then
            r.ShowConsoleMsg(string.format("    ✓ Found soloed track: \"%s\" (track #%d, solo_state=%d)\n",
              track_name, i + 1, solo_state))
          end
          break
        end
      end
    end

    if not target_track then
      if DEBUG then
        r.ShowConsoleMsg("    ✗ No soloed tracks found\n")
      end

      -- Priority 3: No soloed tracks - use preview target track from GUI settings
      if DEBUG then
        r.ShowConsoleMsg("  [Priority 3] Trying preview target track from GUI settings...\n")
      end

      -- Try GUID first
      if preview_target_track_guid and preview_target_track_guid ~= "" then
        if DEBUG then
          r.ShowConsoleMsg(string.format("    [3a] Searching by GUID: %s\n", preview_target_track_guid))
        end

        target_track = find_track_by_guid(preview_target_track_guid)
        if target_track and r.ValidatePtr2(0, target_track, "MediaTrack*") then
          local _, tn = r.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
          track_name = tn
          resolution_method = "Preview target track by GUID (Priority 3a)"

          if DEBUG then
            r.ShowConsoleMsg(string.format("    ✓ Found track by GUID: \"%s\"\n", track_name))
          end
        else
          if DEBUG then
            r.ShowConsoleMsg("    ✗ Track not found by GUID\n")
          end
        end
      end

      -- Fallback to name search if GUID not found
      if not target_track then
        if DEBUG then
          r.ShowConsoleMsg(string.format("    [3b] Searching by name: \"%s\"\n", preview_target_track))
        end

        local track_count = r.CountTracks(0)
        for i = 0, track_count - 1 do
          local tr = r.GetTrack(0, i)
          local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
          if tn == preview_target_track then
            target_track = tr
            track_name = preview_target_track
            resolution_method = "Preview target track by name (Priority 3b)"

            if DEBUG then
              r.ShowConsoleMsg(string.format("    ✓ Found track by name: \"%s\" (track #%d)\n", track_name, i + 1))
            end
            break
          end
        end

        if not target_track and DEBUG then
          r.ShowConsoleMsg("    ✗ Track not found by name\n")
        end
      end
    end

    if DEBUG then
      r.ShowConsoleMsg(string.format("\n[3] Target Track Resolution Result:\n"))
      if target_track then
        local track_num = r.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER")
        local track_guid = get_track_guid(target_track)
        r.ShowConsoleMsg(string.format("  ✓ SUCCESS\n"))
        r.ShowConsoleMsg(string.format("  • Track Name: \"%s\"\n", track_name))
        r.ShowConsoleMsg(string.format("  • Track Number: #%d\n", track_num))
        r.ShowConsoleMsg(string.format("  • Track GUID: %s\n", track_guid or "(none)"))
        r.ShowConsoleMsg(string.format("  • Resolution Method: %s\n", resolution_method))
      else
        r.ShowConsoleMsg(string.format("  ✗ FAILED - No target track found\n"))
      end
    end

    if target_track then
      local current_solo = r.GetMediaTrackInfo_Value(target_track, "I_SOLO")
      -- Toggle: 0=unsolo, 1=solo, 2=solo in place
      -- Simple toggle: if any solo state, set to 0; if 0, set to 1
      local new_solo = (current_solo == 0) and 1 or 0
      r.SetMediaTrackInfo_Value(target_track, "I_SOLO", new_solo)

      if DEBUG then
        local solo_state_name = {"unsolo", "solo", "solo in place"}
        r.ShowConsoleMsg(string.format("\n[4] Solo Toggle Executed:\n"))
        r.ShowConsoleMsg(string.format("  • Previous State: %s (%d)\n", solo_state_name[current_solo + 1] or "unknown", current_solo))
        r.ShowConsoleMsg(string.format("  • New State: %s (%d)\n", solo_state_name[new_solo + 1] or "unknown", new_solo))
        r.ShowConsoleMsg(string.format("  • Target Track: \"%s\"\n", track_name))
        r.ShowConsoleMsg("========================================\n")
      end
    else
      if DEBUG then
        r.ShowConsoleMsg("\n[4] Solo Toggle SKIPPED - No target track\n")
        r.ShowConsoleMsg("========================================\n")
      end
    end
  else
    if DEBUG then
      r.ShowConsoleMsg("\n[2] Item Solo Mode - Executing command 41561...\n")
      local item_count = r.CountSelectedMediaItems(0)
      r.ShowConsoleMsg(string.format("  • Selected Items: %d\n", item_count))
    end

    -- Item solo (41561): operate on selected items
    r.Main_OnCommand(41561, 0)

    if DEBUG then
      r.ShowConsoleMsg("\n[3] Item Solo Toggle Executed\n")
      r.ShowConsoleMsg("========================================\n")
    end
  end
end

------------------------------------------------------------
-- Main Execution
------------------------------------------------------------
r.Undo_BeginBlock()
toggle_solo()
r.Undo_EndBlock("AudioSweet Solo Toggle", -1)
