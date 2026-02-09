--[[
@description AudioSweet Preview Toggle - Auto Detect Focused/Chain
@version 0.2.1
@author Hsuanice
@provides
  [main] .
@changelog
  0.2.1 (2026-02-09) [internal: v260209.2130]
    - FIXED: Cross-platform path resolution for Windows/Linux compatibility
      • Replaced debug.getinfo() relative path with reaper.GetResourcePath() absolute path
      • Fixes "attempt to concatenate a nil value (local 'SCRIPT_DIR')" on Windows

  0.2.0 (2025-12-23) [internal: v251223.2256]
    - CHANGED: Version bump to 0.2.0 (public beta)

  0.1.0 (2025-12-21) [internal: v251221.1915]
    - NEW: Unified preview script that auto-detects focused vs chain window
    - Priority: Chain FX window → chain preview, Single FX floating → focused preview
    - Fallback: No FX window → chain preview on preview target track
    - Reads preview settings from AudioSweet GUI ExtState
]]--

--========================================
-- AudioSweet Preview Toggle
--========================================
-- Auto-detect focused vs chain mode based on window state.
-- Uses GUI ExtState for preview settings and target track.
--========================================

------------------------------------------------------------
-- 1) Load Core Library
------------------------------------------------------------
local RES_PATH = reaper.GetResourcePath()
local ASP = dofile(RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_AS Preview Core.lua')

------------------------------------------------------------
-- 2) Read Settings from GUI ExtState
------------------------------------------------------------
local SETTINGS_NAMESPACE = "hsuanice_AS_GUI"

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

local preview_target_track = get_string("preview_target_track", "AudioSweet")
local preview_target_track_guid = get_string("preview_target_track_guid", "")
local preview_solo_scope = get_int("preview_solo_scope", 0)  -- 0=track, 1=item
local preview_restore_mode = get_int("preview_restore_mode", 0)  -- 0=timesel, 1=guid
local debug_mode = get_bool("debug", false)

local solo_scope_str = (preview_solo_scope == 0) and "track" or "item"
local restore_mode_str = (preview_restore_mode == 0) and "timesel" or "guid"

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------
local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(tr) == guid then
      return tr
    end
  end
  return nil
end

------------------------------------------------------------
-- 3) Detect Window State (Chain vs Focused)
------------------------------------------------------------
local chain_mode = true
local target_track_name = preview_target_track
local target_track_obj = nil
local decision = "chain: default"

local retval, trackOut, _, fxOut = reaper.GetFocusedFX()
if retval == 1 then
  local tr = reaper.GetTrack(0, math.max(0, (trackOut or 1) - 1))
  if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then
    local chain_visible = reaper.TrackFX_GetChainVisible(tr)
    local fx_window_open = reaper.TrackFX_GetOpen(tr, fxOut or 0)

    if chain_visible ~= -1 then
      chain_mode = true
      target_track_obj = tr
      local _, pure_name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      target_track_name = pure_name
      decision = "chain: chain window visible"
    elseif fx_window_open then
      chain_mode = false
      decision = "focused: single FX floating"
    else
      chain_mode = true
      decision = "chain: no visible window"
    end

    if debug_mode then
      reaper.ShowConsoleMsg(string.format(
        "\n[AudioSweet Preview Toggle] FocusedFX: chain_visible=%d, fx_open=%s\n",
        chain_visible, tostring(fx_window_open)
      ))
    end
  end
else
  chain_mode = true
  decision = "chain: no focused FX"
end

------------------------------------------------------------
-- 4) Resolve Target Track (Chain Mode Only)
------------------------------------------------------------
if chain_mode and not target_track_obj then
  if preview_target_track_guid ~= "" then
    local tr = find_track_by_guid(preview_target_track_guid)
    if tr and reaper.ValidatePtr2(0, tr, "MediaTrack*") then
      target_track_obj = tr
      local _, current_name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      target_track_name = current_name
    end
  end
end

if debug_mode then
  reaper.ShowConsoleMsg("\n[AudioSweet Preview Toggle] === MODE DECISION ===\n")
  reaper.ShowConsoleMsg(string.format("  Decision: %s\n", decision))
  reaper.ShowConsoleMsg(string.format("  chain_mode: %s\n", tostring(chain_mode)))
  reaper.ShowConsoleMsg(string.format("  preview_target_track: %s\n", preview_target_track))
  reaper.ShowConsoleMsg(string.format("  preview_target_track_guid: %s\n",
    preview_target_track_guid ~= "" and preview_target_track_guid or "(empty)"))
  reaper.ShowConsoleMsg(string.format("  target_track_name: %s\n", target_track_name))
  reaper.ShowConsoleMsg(string.format("  target_track_obj: %s\n", target_track_obj and "MediaTrack*" or "nil"))
  reaper.ShowConsoleMsg("[AudioSweet Preview Toggle] =======================\n\n")
end

------------------------------------------------------------
-- 5) Define Parameters
------------------------------------------------------------
local args = {
  debug       = debug_mode,
  chain_mode  = chain_mode,
  mode        = "solo",
  solo_scope  = solo_scope_str,
  restore_mode = restore_mode_str,
}

if chain_mode then
  args.target = target_track_obj or nil
  args.target_track_name = target_track_obj and nil or target_track_name
  _G.TARGET_TRACK_NAME = target_track_name
else
  args.target = "focused"
end

------------------------------------------------------------
-- 6) Log Parameters (only if debug) and Run Preview
------------------------------------------------------------
if args.debug then
  reaper.ShowConsoleMsg(string.format(
    "[AS][PREVIEW TOGGLE] mode=%s  target=%s  trackName=%s  chain=%s  scope=%s  restore=%s\n",
    args.mode, tostring(args.target), args.target_track_name or target_track_name,
    tostring(args.chain_mode), args.solo_scope, args.restore_mode
  ))
end

ASP.preview(args)
