--[[
@description AudioSweet Chain Preview - Reads GUI Settings
@version 251030.2335
@author Hsuanice
@changelog
  v251030.2335
    - Changed: Now reads all preview settings from AudioSweet GUI ExtState
    - Reads: preview_target_track, preview_solo_scope, preview_restore_mode, debug
    - Benefit: Single source of truth - change settings in GUI, all preview scripts use same settings
    - Compatible: Works with AudioSweet ReaImGui v251030.2300 or newer
    - Usage: Bind to keyboard shortcut for Chain Preview with GUI settings

  v251012_2025
    - Reordered: `chain_mode` moved to top of Core Behavior section for priority control.
    - Updated: `mode` now follows `chain_mode` to reflect most-used toggles order.
    - Grouped: `target` and `target_track_name` remain together for clarity.
    - Note: `solo_scope` and `restore_mode` kept at bottom since they are rarely changed.
    - No logic change; purely visual reorganization for user convenience.

  v251012_1320
    - Clean: Simplified to match latest ASP Core (focused + target_track_name only).
    - Removed: Deprecated `target="track"` support.
    - Added: Clear inline comments describing each target mode.
    - Behavior: Fully compatible with Core v251012_1302 or newer.

  v251010_2152 (Core: hsuanice_AS Preview Core.lua)
    - Added: Convenience arg `target_track_name` for ASP.preview(); equivalent to `target={by="name", value="<name>"}`.
    - Added: Default target fallback "AudioSweet" when neither `target` nor `target_track_name` is provided.
    - Docs: Updated args comment to include `target_track_name`.
    - Behavior: Non-breaking; sugar only applies when `args.target` is nil.

  v251010_1800 (Template: hsuanice_AudioSweet Preview Template.lua)
    - Clean: Reorganized into clear sections (Load Core / Utility / Target / Params / Run).
    - Option: Console logging now guarded by `args.debug` (no output when false).
    - Note: Current template still uses manual name lookup and `focus_track`; can migrate to `target_track_name` sugar later.
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
-- 3) Define Target Track Name (expose for Core sugar)
------------------------------------------------------------
_G.TARGET_TRACK_NAME = preview_target_track

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
  target            = "TARGET_TRACK_NAME", -- "TARGET_TRACK_NAME" → resolve by name via target_track_name or _G.TARGET_TRACK_NAME
                                           -- "focused"           → isolate currently focused FX (ignores target_track_name)
                                           -- (If omitted, Core defaults to "focused".)
  target_track_name = preview_target_track,      -- Read from GUI ExtState

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