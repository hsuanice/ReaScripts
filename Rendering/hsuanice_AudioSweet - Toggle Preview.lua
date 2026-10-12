--[[
@description AudioSweet Preview Toggle - Auto Detect Focused/Chain
@version 26.1012.1641
@author hsuanice
@noindex
@changelog
  - Renamed to "AudioSweet - Toggle Preview" (was "AudioSweet Preview Toggle") as part of the 2026-10-12 naming clean-up.
@links
  https://forum.cockos.com/showthread.php?p=2910884#post2910884
--]]

-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_AS Preview Core.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

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
-- FX Chain Online/Offline Helpers
------------------------------------------------------------
local function save_and_enable_track_fx_chain(tr)
  if not tr or not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return nil end
  local saved = {}
  local any_change = false
  local fxen = math.floor(reaper.GetMediaTrackInfo_Value(tr, "I_FXEN") + 0.5)
  saved.fxen = fxen
  if fxen == 0 then reaper.SetMediaTrackInfo_Value(tr, "I_FXEN", 1); any_change = true end
  local fx_count = reaper.TrackFX_GetCount(tr)
  saved.offline = {}
  for i = 0, fx_count - 1 do
    local is_offline = reaper.TrackFX_GetOffline(tr, i)
    saved.offline[i] = is_offline
    if is_offline then reaper.TrackFX_SetOffline(tr, i, false); any_change = true end
  end
  return any_change and saved or nil
end

local function restore_track_fx_chain_state(tr, saved)
  if not tr or not saved then return end
  if not reaper.ValidatePtr2(0, tr, "MediaTrack*") then return end
  if saved.fxen ~= nil then reaper.SetMediaTrackInfo_Value(tr, "I_FXEN", saved.fxen) end
  if saved.offline then
    for i, was_offline in pairs(saved.offline) do
      if was_offline then reaper.TrackFX_SetOffline(tr, i, true) end
    end
  end
end

-- Serialise/deserialise saved state via ExtState so the stop-path
-- (a second script instance) can restore the original offline state.
local FXCHAIN_NS = "hsuanice_AS"
local FXCHAIN_KEY = "PREVIEW_TOGGLE_FXCHAIN_SAVED"

local function persist_saved_state(tr, saved)
  if not tr or not saved then
    reaper.SetExtState(FXCHAIN_NS, FXCHAIN_KEY, "", false)
    return
  end
  local guid = reaper.GetTrackGUID(tr)
  local offline_parts = {}
  if saved.offline then
    for i, v in pairs(saved.offline) do
      offline_parts[#offline_parts + 1] = tostring(i) .. ":" .. (v and "1" or "0")
    end
  end
  local payload = guid .. "|" .. tostring(saved.fxen or 1) .. "|" .. table.concat(offline_parts, ",")
  reaper.SetExtState(FXCHAIN_NS, FXCHAIN_KEY, payload, false)
end

local function restore_from_persisted_state()
  local payload = reaper.GetExtState(FXCHAIN_NS, FXCHAIN_KEY)
  if not payload or payload == "" then return end
  reaper.SetExtState(FXCHAIN_NS, FXCHAIN_KEY, "", false)  -- consume
  local guid, fxen_str, offline_str = payload:match("^([^|]+)|([^|]+)|(.*)$")
  if not guid then return end
  -- Find track by GUID
  local tr = nil
  for i = 0, reaper.CountTracks(0) - 1 do
    local t = reaper.GetTrack(0, i)
    if reaper.GetTrackGUID(t) == guid then tr = t; break end
  end
  if not tr then return end
  local saved = { fxen = tonumber(fxen_str), offline = {} }
  if offline_str and offline_str ~= "" then
    for part in offline_str:gmatch("[^,]+") do
      local idx, val = part:match("^(%d+):([01])$")
      if idx then saved.offline[tonumber(idx)] = (val == "1") end
    end
  end
  restore_track_fx_chain_state(tr, saved)
end

------------------------------------------------------------
-- 1.5) Toggle: if preview is already running, stop it
------------------------------------------------------------
-- Dual approach:
--   a) Set STOP_REQ flag (so watcher can handle it with full state if running)
--   b) Call stop_preview() as fallback (handles stale flag / dead watcher)
local _run_flag = reaper.GetExtState("hsuanice_AS", "PREVIEW_RUN")
if _run_flag == "1" then
  reaper.SetExtState("hsuanice_AS", "PREVIEW_STOP_REQ", "1", false)
  local rm_val = reaper.GetExtState("hsuanice_AS_GUI", "preview_restore_mode")
  local rm = (rm_val ~= "1") and "timesel" or "guid"
  ASP.stop_preview({ restore_mode = rm })
  restore_from_persisted_state()
  return
end

------------------------------------------------------------
-- 3) Read Settings from GUI ExtState
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
-- 4) Detect Window State (Chain vs Focused)
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
-- 5) Resolve Target Track (Chain Mode Only)
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
-- 6) Define Parameters
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
-- 7) Log Parameters (only if debug) and Run Preview
------------------------------------------------------------
if args.debug then
  reaper.ShowConsoleMsg(string.format(
    "[AS][PREVIEW TOGGLE] mode=%s  target=%s  trackName=%s  chain=%s  scope=%s  restore=%s\n",
    args.mode, tostring(args.target), args.target_track_name or target_track_name,
    tostring(args.chain_mode), args.solo_scope, args.restore_mode
  ))
end

-- Resolve FX track: chain mode uses target_track_obj or name lookup; focused mode uses GetFocusedFX
local fx_track_for_toggle = target_track_obj
if not fx_track_for_toggle and not chain_mode then
  local retval2, trackidx2 = reaper.GetFocusedFX()
  if retval2 == 1 and trackidx2 then
    fx_track_for_toggle = reaper.GetTrack(0, trackidx2 - 1)
  end
end
if not fx_track_for_toggle and target_track_name ~= "" then
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tn = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if tn == target_track_name then fx_track_for_toggle = tr; break end
  end
end

local saved_fxchain = save_and_enable_track_fx_chain(fx_track_for_toggle)
persist_saved_state(fx_track_for_toggle, saved_fxchain)

ASP.preview(args)
