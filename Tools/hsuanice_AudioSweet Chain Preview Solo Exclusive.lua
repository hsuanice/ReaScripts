--[[
@description AudioSweet Chain Preview - Reads GUI Settings
@version 0.1.0
@author Hsuanice
@provides
  [main] Tools/hsuanice_AudioSweet Chain Preview Solo Exclusive.lua
  Library/hsuanice_AS Preview Core.lua
@changelog
  0.1.0 (2025-12-15) [internal: v251215.1220]
    - FIXED: GetFocusedFX() now correctly detects focused FX chain track.
      • Problem: Script used wrong API call format, always fell back to settings target track
      • Root cause: Used `local focused_track = reaper.GetFocusedFX()` (wrong - only gets first return value)
      • Solution: Use correct format `local retval, trackOut, itemOut, fxOut = reaper.GetFocusedFX()`
      • Impact: Now matches GUI behavior - prioritizes focused FX track over settings
      • Lines: 112-115 (correct GetFocusedFX usage with retval check)
    - Previous: [internal: v251213.1330] Duplicate track name handling with GUID support
    - Previous: [internal: v251213.0336] Smart chain preview target selection
    - Previous: [internal: v251030.2335] Integration with AudioSweet GUI ExtState settings
]]--


--========================================
-- AudioSweet Preview Template
--========================================
-- This template calls the AudioSweet Core preview function
-- with a track target specified by name or by focused FX.
-- Organized by logical sections for clarity.
--========================================

------------------------------------------------------------
-- 1) Load Core Library
------------------------------------------------------------
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*/)")
local ASP = dofile(SCRIPT_DIR .. "../Library/hsuanice_AS Preview Core.lua")

------------------------------------------------------------
-- 2) Read Settings from GUI ExtState
------------------------------------------------------------
local SETTINGS_NAMESPACE = "hsuanice_AS_GUI"

-- Helper functions to read ExtState
local function get_string(key, default)
  local val = reaper.GetExtState(SETTINGS_NAMESPACE, key)
  return (val ~= "") and val or default
end

local function get_int(key, default)
  local val = reaper.GetExtState(SETTINGS_NAMESPACE, key)
  return (val ~= "") and tonumber(val) or default
end

local function get_bool(key, default)
  local val = reaper.GetExtState(SETTINGS_NAMESPACE, key)
  if val == "" then return default end
  return val == "1"
end

-- Read preview settings from GUI
local preview_target_track = get_string("preview_target_track", "AudioSweet")
local preview_target_track_guid = get_string("preview_target_track_guid", "")
local preview_solo_scope = get_int("preview_solo_scope", 0)  -- 0=track, 1=item
local preview_restore_mode = get_int("preview_restore_mode", 0)  -- 0=timesel, 1=guid
local debug_mode = get_bool("debug", false)

-- Convert solo_scope to string
local solo_scope_str = (preview_solo_scope == 0) and "track" or "item"
-- Convert restore_mode to string
local restore_mode_str = (preview_restore_mode == 0) and "timesel" or "guid"

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------
local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local track_guid = reaper.GetTrackGUID(tr)
    if track_guid == guid then
      return tr
    end
  end
  return nil
end

------------------------------------------------------------
-- 3) Determine Target Track (Smart Selection with GUID Support)
------------------------------------------------------------
-- Chain mode: prioritize focused FX chain track if available, otherwise use GUI settings
local target_track_name = preview_target_track  -- Default to GUI settings
local target_track_obj = nil  -- Store the actual track object to pass directly

if debug_mode then
  reaper.ShowConsoleMsg("\n[AudioSweet Chain Preview] === TARGET SELECTION DEBUG ===\n")
  reaper.ShowConsoleMsg(string.format("  Settings preview_target_track: %s\n", preview_target_track))
  reaper.ShowConsoleMsg(string.format("  Settings preview_target_track_guid: %s\n", preview_target_track_guid ~= "" and preview_target_track_guid or "(empty)"))
end

-- Check if there's a focused FX with a track
local retval, trackOut, itemOut, fxOut = reaper.GetFocusedFX()
if retval == 1 then
  -- Track FX is focused
  local tr = reaper.GetTrack(0, math.max(0, (trackOut or 1) - 1))

  if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    -- Get pure track name from track object (P_NAME doesn't include track number prefix)
    local _, pure_name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    target_track_name = pure_name
    target_track_obj = tr

    if debug_mode then
      local focused_guid = reaper.GetTrackGUID(tr)
      reaper.ShowConsoleMsg("  DECISION: Using focused FX chain track\n")
      reaper.ShowConsoleMsg(string.format("  → Track: %s (GUID: %s)\n", pure_name, focused_guid))
    end
  end
else
  -- No focused FX: use settings target track
  if debug_mode then
    reaper.ShowConsoleMsg("  DECISION: No focused FX, using settings\n")
  end

  -- Try to find track by GUID first (more reliable for duplicate names)
  if preview_target_track_guid ~= "" then
    local target_track = find_track_by_guid(preview_target_track_guid)
    if target_track and reaper.ValidatePtr2(0, target_track, "MediaTrack*") then
      -- Found by GUID: get current track name and store track object
      local _, current_name = reaper.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
      target_track_name = current_name
      target_track_obj = target_track  -- IMPORTANT: Pass track object directly to avoid duplicate name issues

      if debug_mode then
        reaper.ShowConsoleMsg(string.format("  → Found by GUID: %s\n", preview_target_track_guid))
        reaper.ShowConsoleMsg(string.format("  → Track name: %s\n", current_name))
        reaper.ShowConsoleMsg("  → Will pass MediaTrack* directly to Preview Core\n")
      end
    else
      -- GUID not found: fallback to name
      if debug_mode then
        reaper.ShowConsoleMsg(string.format("  → GUID not found: %s\n", preview_target_track_guid))
        reaper.ShowConsoleMsg(string.format("  → Fallback to track name search: %s\n", target_track_name))
      end
    end
  else
    -- No GUID: use track name directly
    if debug_mode then
      reaper.ShowConsoleMsg(string.format("  → No GUID stored, using track name: %s\n", target_track_name))
    end
  end
end

if debug_mode then
  reaper.ShowConsoleMsg(string.format("  FINAL target_track_name: %s\n", target_track_name))
  reaper.ShowConsoleMsg(string.format("  FINAL target_track_obj: %s\n", target_track_obj and "MediaTrack*" or "nil (will use name search)"))
  reaper.ShowConsoleMsg("[AudioSweet Chain Preview] =====================================\n\n")
end

-- Expose for Core sugar (for backward compatibility)
_G.TARGET_TRACK_NAME = target_track_name

------------------------------------------------------------
-- 4) Define Parameters
------------------------------------------------------------
local args = {
  debug       = debug_mode,

  ----------------------------------------------------------
  ----------------------------------------------------------
  -- Core Behavior
  ----------------------------------------------------------
  chain_mode        = true,              -- true  = Chain preview (no FX isolation)
                                         -- false = Focused preview (isolate active FX)
  mode              = "solo",            -- "solo" or "normal"

  -- Pass track object directly if available (avoids duplicate name issues)
  -- Otherwise fall back to track name search
  target            = target_track_obj or nil,
  target_track_name = target_track_obj and nil or target_track_name,

  ----------------------------------------------------------
  -- Behavior Options (Read from GUI ExtState)
  ----------------------------------------------------------
  solo_scope   = solo_scope_str,         -- "track" or "item" (from GUI)
  restore_mode = restore_mode_str,       -- "guid" | "timesel" (from GUI)
}

------------------------------------------------------------
-- 4) Log Parameters (only if debug) and Run Preview
------------------------------------------------------------
if args.debug then
  reaper.ShowConsoleMsg(string.format(
    "[AS][PREVIEW TEMPLATE] mode=%s  target=%s  trackName=%s  chain=%s  scope=%s  restore=%s\n",
    args.mode, tostring(args.target), args.target_track_name,
    tostring(args.chain_mode), args.solo_scope, args.restore_mode
  ))
end

ASP.preview(args)
