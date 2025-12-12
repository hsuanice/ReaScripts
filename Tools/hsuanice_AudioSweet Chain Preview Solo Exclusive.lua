--[[
@description AudioSweet Chain Preview - Reads GUI Settings
@version 0.1.0
@author Hsuanice
@provides
  [main] Tools/hsuanice_AudioSweet Chain Preview Solo Exclusive.lua
  Library/hsuanice_AS Preview Core.lua
@changelog
  0.1.0 (2025-12-13) [internal: v251213.0336]
    - Enhanced: Smart chain preview target selection
    - New: Prioritizes focused FX chain track if available, falls back to GUI settings
    - Fixed: Extracts pure track name from focused track using P_NAME (without track number prefix)
    - Previous: Now reads all preview settings from AudioSweet GUI ExtState [internal: v251030.2335]
    - Reads: preview_target_track, preview_solo_scope, preview_restore_mode, debug
    - Benefit: Single source of truth - change settings in GUI, all preview scripts use same settings
    - Compatible: Works with AudioSweet ReaImGui v251030.2300 or newer
    - Usage: Bind to keyboard shortcut for Chain Preview with GUI settings
    - Reordered: `chain_mode` moved to top of Core Behavior section [internal: v251012_2025]
    - Updated: `mode` now follows `chain_mode` to reflect most-used toggles order
    - Grouped: `target` and `target_track_name` remain together for clarity
    - Clean: Simplified to match latest ASP Core [internal: v251012_1320]
    - Removed: Deprecated `target="track"` support
    - Added: Clear inline comments describing each target mode
    - Added: Convenience arg `target_track_name` for ASP.preview() [internal: v251010_2152]
    - Added: Default target fallback "AudioSweet"
    - Clean: Reorganized into clear sections [internal: v251010_1800]
    - Option: Console logging now guarded by `args.debug`
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
local preview_solo_scope = get_int("preview_solo_scope", 0)  -- 0=track, 1=item
local preview_restore_mode = get_int("preview_restore_mode", 0)  -- 0=timesel, 1=guid
local debug_mode = get_bool("debug", false)

-- Convert solo_scope to string
local solo_scope_str = (preview_solo_scope == 0) and "track" or "item"
-- Convert restore_mode to string
local restore_mode_str = (preview_restore_mode == 0) and "timesel" or "guid"

------------------------------------------------------------
-- 3) Determine Target Track Name (Smart Selection)
------------------------------------------------------------
-- Chain mode: prioritize focused FX chain track if available, otherwise use GUI settings
local target_track_name = preview_target_track  -- Default to GUI settings

-- Check if there's a focused FX with a track
local focused_track = reaper.GetFocusedFX()
if focused_track > 0 then
  -- Extract track from focused FX
  local track_number = (focused_track & 0xFFFF) - 1
  local tr = reaper.GetTrack(0, track_number)

  if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    -- Get pure track name from track object (P_NAME doesn't include track number prefix)
    local _, pure_name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    target_track_name = pure_name

    if debug_mode then
      reaper.ShowConsoleMsg("[AudioSweet Chain Preview] Using focused FX chain track: " .. pure_name .. "\n")
    end
  end
else
  if debug_mode then
    reaper.ShowConsoleMsg("[AudioSweet Chain Preview] Using GUI settings target track: " .. target_track_name .. "\n")
  end
end

-- Expose for Core sugar
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
  -- Don't set target explicitly; let Preview Core use target_track_name directly
  target_track_name = target_track_name, -- Smart selection: focused FX track or GUI settings

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
