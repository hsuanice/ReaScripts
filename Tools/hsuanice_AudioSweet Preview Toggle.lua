--[[
@description AudioSweet Preview Toggle - Auto Detect Focused/Chain
@version 0.2.7
@author hsuanice
@provides
  [main] .
@changelog
  0.2.7 (2026-02-10) [internal: v260210.1935]
    - FIXED: Toggle now reliably stops preview on 2nd press
      • Root cause: REAPER terminates the deferred script (watcher) on re-trigger,
        never starting a new instance — 2nd press produced zero output
      • Fix: Core now registers reaper.atexit() alongside watcher
      • atexit fires on script termination with full L1 state — clean cleanup
    - CHANGED: Removed temporary ShowConsoleMsg debug output
    - CHANGED: Version synced with Preview Core 0.2.7

  0.2.6 (2026-02-10) [internal: v260210.1303]
    - FIXED: Toggle stop now works reliably on 2nd execution
      • Replaced cross-instance stop_preview() call with PREVIEW_STOP_REQ ExtState flag
      • Watcher in original instance (with full state) handles cleanup — no state bootstrapping
      • Toggle check moved before dofile() — stop path doesn't load Core at all
    - CHANGED: Version synced with Preview Core 0.2.6

  0.2.5 (2026-02-10) [internal: v260210.1224]
    - FIXED: Toggle self-toggle now works reliably (was failing on 2nd tap)
      • Core fix: stop_preview() now sets moved_count for timesel count check
      • Core fix: Watcher race replaced 3-frame debounce with 500ms startup grace period
    - CHANGED: Version synced with Preview Core 0.2.5

  0.2.4 (2026-02-10) [internal: v260210.1212]
    - FIXED: Manual stop (spacebar etc.) now auto-cleans up preview again
      • Re-enabled Core's stop-watcher (was disabled in 0.2.3 to avoid race)
      • Core watcher now uses 3-frame debounce to prevent false-positive race
    - FIXED: stop_preview() now respects GUI restore_mode setting (GUID vs timesel)
      • Reads preview_restore_mode from GUI ExtState before stopping
      • timesel mode: moves back ALL items in placeholder span (including new items from Run)
      • guid mode: moves back only the originally-moved items (safe when FX track has other items)
    - CHANGED: Removed no_watcher=true from args — watcher re-enabled for manual stop support
    - CHANGED: Version synced with Preview Core 0.2.4

  0.2.3 (2026-02-10) [internal: v260210.1113]
    - FIXED: Toggle now reliably stops on 2nd execution (was requiring 3 taps)
      • Root cause: Core's stop-watcher raced with toggle — watcher auto-cleaned up,
        clearing PREVIEW_RUN flag, so toggle fell through and restarted preview
      • Fix: Toggle passes no_watcher=true to Core, disabling the deferred stop-watcher
      • Toggle script now exclusively controls the preview lifecycle via stop_preview()
      • Core's stop_preview() bootstraps state from placeholder + ExtState for full cleanup
    - NEW: Core stores FX track GUID in ExtState (PREVIEW_FX_GUID) for cross-instance lookup
    - NEW: Core.stop_preview() public method — stops transport, finds placeholder,
      bootstraps state, and runs cleanup from a fresh Lua instance

  0.2.2 (2026-02-10) [internal: v260210]
    - NEW: True toggle behavior — re-running while preview is active now stops preview
      • Checks PREVIEW_RUN ExtState flag set by Preview Core
      • If preview is running, calls Core.stop_preview() for full cleanup
      • Previous behavior (mode switch on re-entry) replaced by clean stop/start toggle

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

ASP.preview(args)
