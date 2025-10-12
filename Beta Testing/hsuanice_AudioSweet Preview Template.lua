--[[
@description AudioSweet Preview Template
@version 251012_2025 (reordered for clarity; no logic change)
@author Hsuanice
@changelog
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
-- 2) Define Target Track Name (used when target="TARGET_TRACK_NAME")
------------------------------------------------------------
local TARGET_TRACK_NAME = "AudioSweet"
_G.TARGET_TRACK_NAME = TARGET_TRACK_NAME -- expose for Core sugar

------------------------------------------------------------
-- 3) Define Parameters
------------------------------------------------------------
local args = {
  debug       = true,

  ----------------------------------------------------------
  ----------------------------------------------------------
  -- Core Behavior
  ----------------------------------------------------------
  chain_mode        = false,              -- true  = Chain preview (no FX isolation)
                                         -- false = Focused preview (isolate active FX)
  mode              = "solo",            -- "solo" or "normal"
  target            = "TARGET_TRACK_NAME", -- "TARGET_TRACK_NAME" → resolve by name via target_track_name or _G.TARGET_TRACK_NAME
                                           -- "focused"           → isolate currently focused FX (ignores target_track_name)
                                           -- (If omitted, Core defaults to "focused".)
  target_track_name = "AudioSweet",      -- Direct track name; used only when target="TARGET_TRACK_NAME"

  ----------------------------------------------------------
  -- Behavior Options
  ----------------------------------------------------------
  solo_scope   = "track",                -- "track" or "item"
  restore_mode = "guid",                 -- "guid" | "timesel"
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
