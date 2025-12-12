--[[
@description RGWH Wrapper Template - Template for Custom RGWH Wrappers
@author hsuanice
@version 0.1.0
@provides
  [main] hsuanice Scripts/Beta Testing/hsuanice_RGWH Wrapper Template.lua
  hsuanice Scripts/Library/hsuanice_RGWH Core.lua
  hsuanice Scripts/Library/hsuanice_Metadata Embed.lua
@about
  Thin wrapper for calling RGWH Core via a single entry `RGWH.core(args)`.
  Use this as a starting point to test and ship wrappers that render/glue with handles.

@usage
  1) Adjust the USER CONFIG block below.
  2) Run this script in REAPER. It will call RGWH.core(args) with one-run overrides.
  3) All non-specified options keep the project's ExtState defaults (then DEFAULTS).

@notes
  - op:
      "render" : always single-item (selection_scope is ignored).
      "glue"   : uses selection_scope ("units" | "ts" | "item" | "auto").
      "auto"   : if single item AND GLUE_SINGLE_ITEMS=false => render; else glue(auto scope).
  - selection_scope (for glue/auto):
      "auto"  : TS empty or ≈ selection span => Units; otherwise => TS window.
      "units" : glue by Item Units (same-track grouping).
      "ts"    : glue strictly by the current Time Selection window (never render).
      "item"  : glue per item (SINGLE respects GLUE_SINGLE_ITEMS).
  - channel_mode maps to GLUE/RENDER_APPLY_MODE: "auto" | "mono" | "multi".
  - handle/epsilon/cues/policies/debug: one-run overrides; omit or use "ext" to read ExtState as-is.

@changelog
  0.1.0 (2025-12-12) [internal: v251022_2200]
    - Changed: merge_volumes now affects ALL takes (not just active take) in RGWH Core
    - Rationale: Ensures consistent audio output when switching between takes after merge
    - Added: Volume control options for Render operations [internal: v251022_1745]
        • merge_volumes (default: true) - merge item volume into take volume before render
        • print_volumes (default: true) - bake volumes into rendered audio; false = restore original volumes
    - Changed: args table now includes merge_volumes and print_volumes toggles in Render section
    - Note: These options only affect render operations; glue operations unchanged
    - Initial public template for RGWH Wrapper [internal: v251016_1357]
    - Provides unified entry for calling `RGWH.core(args)`
    - Includes per-run overrides for handle/epsilon/debug/cues/policies
    - Adds `QUICK_DEBUG` one-line toggle ("silent", "normal", "verbose", "use-detailed")
    - Adds wrapper-only `SELECTION_POLICY` ("progress", "restore", "none") with snapshot/restore logic
    - Adds performance measurement (snapshot/core/restore/total) using `reaper.time_precise()`
    - Supports auto conversion between frames and seconds for handle and epsilon
    - Implements robust selection restore via track GUID and time overlap matching
    - Console summary includes selection debug and timing results
]]--

------------------------------------------------------------
-- Resolve RGWH Core
------------------------------------------------------------
local r = reaper
local RES_PATH = r.GetResourcePath()
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua'

local ok_load, RGWH = pcall(dofile, CORE_PATH)
if not ok_load or type(RGWH) ~= "table" or type(RGWH.core) ~= "function" then
  r.ShowConsoleMsg(("[RGWH WRAPPER] Failed to load Core at:\n  %s\nError: %s\n")
    :format(CORE_PATH, tostring(RGWH)))
  return
end

------------------------------------------------------------
-- QUICK DEBUG SWITCH (one-line toggle)
--   "silent"      → level=0,  no_clear=true
--   "normal"      → level=1,  no_clear=false
--   "verbose"     → level=2,  no_clear=true
--   "use-detailed"→ keep the detailed args.debug settings below
------------------------------------------------------------
local QUICK_DEBUG = "verbose"  
-- change to: "silent" | "normal" | "verbose" | "use-detailed"

local function apply_quick_debug(quick, detailed)
  if quick == "silent"  then return { level = 0, no_clear = true  } end
  if quick == "normal"  then return { level = 1, no_clear = false } end  -- clear console on normal
  if quick == "verbose" then return { level = 2, no_clear = true  } end
  return detailed
end

------------------------------------------------------------
-- WRAPPER-ONLY SELECTION POLICY (not sent to Core)
--   "progress" -> keep Core's in-run selections (selection follows process)
--   "restore"  -> restore selection context (tracks/TS/cursor + re-select items
--                 by same-track time overlap). Item count may differ after glue.
--   "none"     -> clear all selections after run
local SELECTION_POLICY = "restore"
------------------------------------------------------------
-- USER CONFIG (edit here)
------------------------------------------------------------
-- Quick presets (uncomment ONE block or set manually below):
-- [AUTO scope with one-run defaults from ExtState]
-- local _PRESET = { op="auto", selection_scope="auto", channel_mode="auto" }

-- [Force Units glue]
-- local _PRESET = { op="glue", selection_scope="units", channel_mode="auto" }

-- [Force TS-Window glue]
-- local _PRESET = { op="glue", selection_scope="ts", channel_mode="auto" }

-- [Single-item Render]
-- local _PRESET = { op="render", channel_mode="auto", take_fx=true, track_fx=false, tc_mode="previous" }

-- If you didn’t choose a preset, configure manually here:
local args = (_PRESET) or {
  -- Core operation
  op              = "render",        -- "auto" | "render" | "glue"
  selection_scope = "auto",          -- "auto" | "units" | "ts" | "item"  (ignored when op="render")
  channel_mode    = "auto",        -- "auto" | "mono" | "multi"

  -- Render toggles (only effective when op resolves to render)
  take_fx  = true,                 -- bake take FX on render
  track_fx = false,                 -- bake track FX on render
  tc_mode  = "current",           -- "previous" | "current" | "off" (BWF TimeReference embed)

  -- Volume handling (only effective when op resolves to render)
  merge_volumes = true,             -- merge item volume into take volume before render
  print_volumes = false,            -- bake volumes into rendered audio (false = restore original volumes)

  -- One-run overrides (simple knobs)
  -- Handle: choose how to interpret length; wrapper will convert to Core format
  handle_mode   = "seconds",     -- "ext" | "seconds" | "frames"
  handle_length = 5.0,       -- value; if "frames", wrapper converts to seconds using project FPS

  -- Epsilon: native support for frames/seconds in Core
  epsilon_mode  = "frames",  -- "ext" | "frames" | "seconds"
  epsilon_value = 0.5,       -- threshold value in selected unit

  cues = {
    write_edge = true,             -- #in/#out edge cues as media cues
    write_glue = true,             -- #Glue: <TakeName> cues inside glued media when sources change
  },

  policies = {
    glue_single_items = true,     -- in op="auto": single item => render (if false)
    glue_no_trackfx_output_policy   = "preserve",   -- "preserve" | "force_multi"
    render_no_trackfx_output_policy = "preserve",   -- "preserve" | "force_multi"
    rename_mode = "auto",          -- "auto" | "glue" | "render" (kept for compatibility)
  },

}

------------------------------------------------------------
-- Build handle/epsilon objects for Core from simple knobs
------------------------------------------------------------
local function resolve_handle_from_knobs(a)
  local mode = (a.handle_mode or "ext")
  if mode == "ext" then return "ext" end
  local len = tonumber(a.handle_length) or 0
  if mode == "seconds" then
    return { mode = "seconds", seconds = len }
  elseif mode == "frames" then
    local fps = reaper.TimeMap_curFrameRate(0) or 30
    -- Core expects seconds for handle; convert frames → seconds
    return { mode = "seconds", seconds = (len / fps) }
  else
    return "ext"
  end
end

local function resolve_epsilon_from_knobs(a)
  local mode = (a.epsilon_mode or "ext")
  if mode == "ext" then return "ext" end
  local val = tonumber(a.epsilon_value) or 0
  if mode == "frames" then
    return { mode = "frames",  value = val }
  elseif mode == "seconds" then
    return { mode = "seconds", value = val }
  else
    return "ext"
  end
end

-- apply conversions
args.handle  = resolve_handle_from_knobs(args)
args.epsilon = resolve_epsilon_from_knobs(args)
-- Apply quick debug policy to args.debug
args.debug = apply_quick_debug(QUICK_DEBUG, args.debug or {})
-- Helpers for smart item-restore
local function track_guid(tr)
  local ok, guid = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  return ok and guid or nil
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for t = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, t)
    local ok, g = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
    if ok and g == guid then return tr end
  end
  return nil
end

local function seconds_epsilon_from_args(a)
  -- Wrapper already built args.epsilon = {mode="frames"/"seconds", value=...} or "ext"
  if type(a.epsilon) == "table" then
    if a.epsilon.mode == "seconds" then
      return tonumber(a.epsilon.value) or 0.02
    elseif a.epsilon.mode == "frames" then
      local fps = r.TimeMap_curFrameRate(0) or 30
      return (tonumber(a.epsilon.value) or 0) / fps
    end
  end
return 0.02 -- fallback
end

-- Perf helper (format seconds to milliseconds string)
local function _ms(dt)
  if not dt then return "0.0" end
  return string.format("%.1f", dt * 1000.0)
end

------------------------------------------------------------
-- RUN
-------------------------------------------------------------- Helper: snapshot current selection/context
local function snapshot_selection()
  local s = {}

  -- items
  s.items = {}
  for i = 0, r.CountSelectedMediaItems(0)-1 do
    local it  = r.GetSelectedMediaItem(0, i)
    local tr  = it and r.GetMediaItem_Track(it) or nil
    local tgd = tr and track_guid(tr) or nil
    local pos = it and r.GetMediaItemInfo_Value(it, "D_POSITION") or nil
    local len = it and r.GetMediaItemInfo_Value(it, "D_LENGTH")   or nil
    s.items[#s.items+1] = {
      ptr      = it,          -- original pointer (may become invalid after glue)
      tr       = tr,          -- original track ptr (may be fine)
      tr_guid  = tgd,         -- robust identifier to refind track
      start    = pos,         -- seconds
      finish   = (pos and len) and (pos + len) or nil,
    }
  end

  -- tracks
  s.tracks = {}
  for t = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, t)
    if r.IsTrackSelected(tr) then
      s.tracks[#s.tracks+1] = tr
    end
  end

  -- time selection
  s.ts_start, s.ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

  -- edit cursor
  s.edit_pos = r.GetCursorPosition()

  return s
end

-- Helper: restore selection/context from snapshot
local function restore_selection(s)
  if not s then return end

  -- items (smart restore)
  r.SelectAllMediaItems(0, false)
  if s.items then
    local eps = seconds_epsilon_from_args(args)
    for _, desc in ipairs(s.items) do
      local selected = false
      -- 1) try original pointer
      if desc.ptr and r.ValidatePtr2(0, desc.ptr, "MediaItem*") then
        r.SetMediaItemSelected(desc.ptr, true)
        selected = true
      else
        -- 2) fallback: match by same-track + time overlap
        local tr = desc.tr
        if (not tr or not r.ValidatePtr2(0, tr, "MediaTrack*")) and desc.tr_guid then
          tr = find_track_by_guid(desc.tr_guid)
        end
        if tr and desc.start and desc.finish then
          local N = r.CountTrackMediaItems(tr)
          for i = 0, N - 1 do
            local it2 = r.GetTrackMediaItem(tr, i)
            local p   = r.GetMediaItemInfo_Value(it2, "D_POSITION")
            local l   = r.GetMediaItemInfo_Value(it2, "D_LENGTH")
            local q1, q2 = p, p + l
            local a1, a2 = desc.start - eps, desc.finish + eps
            -- Overlap test
            if (q1 < a2) and (q2 > a1) then
              r.SetMediaItemSelected(it2, true)
              selected = true
              break
            end
          end
        end
      end
      -- (optional) if not selected, we simply skip; no error thrown
    end
  end
  -- tracks
  for t = 0, r.CountTracks(0)-1 do
    r.SetTrackSelected(r.GetTrack(0, t), false)
  end
  if s.tracks then
    for _, tr in ipairs(s.tracks) do
      if r.ValidatePtr2(0, tr, "MediaTrack*") then
        r.SetTrackSelected(tr, true)
      end
    end
  end

  -- time selection
  if s.ts_start and s.ts_end then
    r.GetSet_LoopTimeRange2(0, true, false, s.ts_start, s.ts_end, false)
  end

  -- edit cursor
  if s.edit_pos then
    r.SetEditCurPos(s.edit_pos, false, false)
  end

  -- optional: print matching stats
  if args.debug and (args.debug.level or 0) > 0 then
    local total = (s.items and #s.items) or 0
    local matched = 0
    do
      -- re-count selected items overlapping previous spans on same tracks
      local eps = seconds_epsilon_from_args(args)
      for _, desc in ipairs(s.items or {}) do
        local tr = desc.tr
        if (not tr or not r.ValidatePtr2(0, tr, "MediaTrack*")) and desc.tr_guid then
          tr = find_track_by_guid(desc.tr_guid)
        end
        if tr and desc.start and desc.finish then
          local found = false
          local N = r.CountTrackMediaItems(tr)
          for i = 0, N - 1 do
            local it2 = r.GetTrackMediaItem(tr, i)
            if r.IsMediaItemSelected(it2) then
              local p = r.GetMediaItemInfo_Value(it2, "D_POSITION")
              local l = r.GetMediaItemInfo_Value(it2, "D_LENGTH")
              local q1, q2 = p, p + l
              local a1, a2 = desc.start - eps, desc.finish + eps
              if (q1 < a2) and (q2 > a1) then
                found = true; break
              end
            end
          end
          if found then matched = matched + 1 end
        end
      end
    end
    r.ShowConsoleMsg(("[WRAPPER][Selection Debug] restore matched %d / %d (time-overlap)\n")
      :format(matched, total))
  end
end

-- Helper: summarize selection/context for debug
local function summarize_selection(s)
  if not s then return "  (no snapshot)\n" end
  local items  = s.items and #s.items or 0
  local tracks = s.tracks and #s.tracks or 0
  local ts
  if s.ts_start and s.ts_end and (s.ts_end > s.ts_start) then
    ts = string.format("%.3f..%.3f", s.ts_start, s.ts_end)
  else
    ts = "empty"
  end
  local cursor = s.edit_pos or -1
  local buf = {}
  buf[#buf+1] = string.format("  items=%d  tracks=%d  ts=%s  cursor=%.3f",
                              items, tracks, ts, cursor)
  return table.concat(buf, "\n") .. "\n"
end

-- Decide selection policy: "progress" | "restore" | "none"
local policy = tostring(SELECTION_POLICY or "restore")

-- Snapshot BEFORE
local sel_before = nil
-- perf timers
local _t_all0, _t_all1 = r.time_precise(), nil
local _t_snap0, _t_snap1 = nil, nil
local _t_core0, _t_core1 = nil, nil
local _t_rest0, _t_rest1 = nil, nil

if policy == "restore" then
  _t_snap0 = r.time_precise()
  sel_before = snapshot_selection()
  _t_snap1 = r.time_precise()
end

-- Debug (before)
if args.debug and (args.debug.level or 0) > 0 then
  if args.debug.no_clear == false then r.ClearConsole() end
  r.ShowConsoleMsg(("[WRAPPER][Selection Debug] policy=%s  [before]\n%s")
    :format(policy, summarize_selection(sel_before)))
end

-- Run Core
_t_core0 = r.time_precise()
local ok_run, err = RGWH.core(args)
_t_core1 = r.time_precise()

-- Post-run handling
if policy == "restore" and sel_before then
  _t_rest0 = r.time_precise()
  restore_selection(sel_before)
  _t_rest1 = r.time_precise()
elseif policy == "none" then
  -- Clear item selection only (conservative)
  r.SelectAllMediaItems(0, false)
else
  -- "progress": do nothing
end

r.UpdateArrange()
_t_all1 = r.time_precise()

-- Debug (after)
if args.debug and (args.debug.level or 0) > 0 then
  -- One-line perf summary
  local d_snap = (_t_snap0 and _t_snap1) and (_t_snap1 - _t_snap0) or 0
  local d_core = (_t_core0 and _t_core1) and (_t_core1 - _t_core0) or 0
  local d_rest = (_t_rest0 and _t_rest1) and (_t_rest1 - _t_rest0) or 0
  local d_all  = (_t_all0 and _t_all1) and (_t_all1 - _t_all0) or 0
  r.ShowConsoleMsg(("[WRAPPER][Perf] snapshot=%sms  core=%sms  restore=%sms  total=%sms\n")
    :format(_ms(d_snap), _ms(d_core), _ms(d_rest), _ms(d_all)))

  local sel_after = snapshot_selection()
  r.ShowConsoleMsg(("[WRAPPER][Selection Debug] [after]\n%s")
    :format(summarize_selection(sel_after)))
end
