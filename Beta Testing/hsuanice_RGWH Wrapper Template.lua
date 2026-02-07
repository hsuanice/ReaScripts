--[[
@description RGWH Wrapper Template - Template for Custom RGWH Wrappers
@author hsuanice
@version 0.2.2
@provides
  [main] .
@about
  Thin wrapper for calling RGWH Core via a single entry `RGWH.core(args)`.
  Use this as a starting point to test and ship wrappers that render/glue with handles.

  NEW: ExtState Mode
  - Set USE_EXTSTATE = true to read ALL settings from RGWH ExtState (GUI settings)
  - Set USE_EXTSTATE = false to use the hardcoded settings below
  - This allows creating keyboard shortcuts that mirror GUI configuration

@usage
  1) Choose your mode:
     - USE_EXTSTATE = true  -> acts like hsuanice_RGWH Render/Glue.lua (reads GUI settings)
     - USE_EXTSTATE = false -> uses the USER CONFIG block below
  2) Run this script in REAPER. It will call RGWH.core(args) with your chosen settings.
  3) When USE_EXTSTATE = false, all non-specified options keep the project's ExtState defaults (then DEFAULTS).

@notes
  - op:
      "render" : always single-item (selection_scope is ignored).
      "glue"   : uses selection_scope ("units" | "ts" | "item" | "auto").
      "auto"   : if single item AND GLUE_SINGLE_ITEMS=false => render; else glue(auto scope).
  - selection_scope (for glue/auto):
      "auto"  : TS empty or = selection span => Units; otherwise => TS window.
      "units" : glue by Item Units (same-track grouping).
      "ts"    : glue strictly by the current Time Selection window (never render).
      "item"  : glue per item (SINGLE respects GLUE_SINGLE_ITEMS).
  - channel_mode maps to GLUE/RENDER_APPLY_MODE: "auto" | "mono" | "multi".
  - handle/epsilon/cues/policies/debug: one-run overrides; omit or use "ext" to read ExtState as-is.

@changelog
  0.2.2 (260207.0230)
    - FIXED: Force selection_scope = "auto" in ExtState mode (ignore GUI SELECTION_SCOPE)
      • Prevents "no_time_selection" error when GUI is set to TS mode
      • Wrapper now works with both item selection and time selection
    - ADDED: Error message display when Core fails (always shown)

  0.2.1 (260206.2345)
    - ADDED: MULTI_CHANNEL_POLICY reading in ExtState mode
    - ADDED: SELECTION_SCOPE reading in ExtState mode
    - ADDED: SELECTION_POLICY reading in ExtState mode (replaces hardcoded value)
    - ADDED: MERGE_TO_ITEM reading in ExtState mode
    - IMPACT: Now reads ALL GUI settings from ExtState when USE_EXTSTATE = true

  0.2.0 (260206.2230)
    - ADDED: USE_EXTSTATE toggle at top of USER CONFIG
      • When true: reads ALL settings from RGWH ExtState (same as GUI)
      • When false: uses hardcoded settings in this file (original behavior)
      • Allows creating keyboard shortcuts that mirror GUI configuration
    - ADDED: ExtState reading functions (get_ext, get_ext_bool, get_ext_num)
    - ADDED: read_extstate_settings() and build_args_from_extstate()
    - Note: Volume merge options only affect render operations; glue always forces merge+print

  0.1.0 (251214.0040)
    - Simplified: Volume merge logic (matches RGWH Core v251214.0040)
        • Valid combinations: OFF | merge_to_item | merge_to_take + print OFF | merge_to_take + print ON
        • merge_to_item + print_volumes=true is NOT supported (GUI auto-switches to merge_to_take)
        • Rationale: REAPER can only print take volume, not item volume
        • When using GUI: auto-switches to merge_to_take if you try to enable print with merge_to_item
    - Updated: Bidirectional volume merge support
        • Changed: merge_volumes -> merge_to_item + merge_to_take (mutually exclusive)
        • merge_to_item: merge take volume INTO item volume (all takes -> 1.0, print OFF only)
        • merge_to_take: merge item volume INTO take volume (item -> 1.0, consolidates all takes)
        • print_volumes: bake volumes into rendered audio (false = restore original volumes)
        • Default: merge_to_item=false, merge_to_take=true (preserves original behavior)
    - Cleanup: Removed deprecated policies to match RGWH Core v251212.2300
        • Removed: rename_mode (was never implemented, no functional change)
        • Kept: glue_single_items, glue_no_trackfx_output_policy, render_no_trackfx_output_policy
    - Note: These options only affect render operations; glue operations unchanged
    - Previous: merge_volumes now affects ALL takes (not just active take) in RGWH Core [v251022_2200]
        • Rationale: Ensures consistent audio output when switching between takes after merge
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
-- USER CONFIG: ExtState Mode Toggle
------------------------------------------------------------
-- Set to true to read ALL settings from RGWH ExtState (same settings as GUI).
-- Set to false to use the hardcoded settings in the USER CONFIG block below.
local USE_EXTSTATE = false

------------------------------------------------------------
-- QUICK DEBUG SWITCH (one-line toggle)
--   "silent"      -> level=0,  no_clear=true
--   "normal"      -> level=1,  no_clear=false
--   "verbose"     -> level=2,  no_clear=true
--   "use-detailed"-> keep the detailed args.debug settings below
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
-- ExtState Reading (project-scope, namespace "RGWH")
-- Only used when USE_EXTSTATE = true
------------------------------------------------------------
local NS = "RGWH"

local function get_ext(key, fallback)
  local _, v = r.GetProjExtState(0, NS, key)
  if v == nil or v == "" then return fallback end
  return v
end

local function get_ext_bool(key, fallback_bool)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_bool end
  v = tostring(v)
  if v == "1" or v:lower() == "true" then return true end
  return false
end

local function get_ext_num(key, fallback_num)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_num end
  local n = tonumber(v)
  return n or fallback_num
end

------------------------------------------------------------
-- Read Settings from ExtState (for USE_EXTSTATE mode)
------------------------------------------------------------
local function read_extstate_settings(op_mode)
  local is_render = (op_mode == "render")
  local prefix = is_render and "RENDER" or "GLUE"

  return {
    -- Channel mode
    channel_mode = get_ext(prefix .. "_APPLY_MODE", "auto"),
    multi_channel_policy = get_ext("MULTI_CHANNEL_POLICY", "source_playback"),

    -- FX settings
    take_fx = get_ext_bool(prefix .. "_TAKE_FX", true),
    track_fx = get_ext_bool(prefix .. "_TRACK_FX", false),

    -- Timecode embed (render only)
    tc_mode = get_ext("RENDER_TC_EMBED", "current"),

    -- Selection (from GUI)
    selection_scope = get_ext("SELECTION_SCOPE", "auto"),
    selection_policy = get_ext("SELECTION_POLICY", "restore"),

    -- Volume handling
    merge_to_item = get_ext_bool(prefix .. "_MERGE_TO_ITEM", false),
    merge_to_take = get_ext_bool(prefix .. "_MERGE_VOLUMES", true),
    print_volumes = get_ext_bool(prefix .. "_PRINT_VOLUMES", true),

    -- Handle
    handle_mode = get_ext("HANDLE_MODE", "seconds"),
    handle_seconds = get_ext_num("HANDLE_SECONDS", 5.0),

    -- Cues
    write_edge_cues = get_ext_bool("WRITE_EDGE_CUES", true),
    write_glue_cues = get_ext_bool("WRITE_GLUE_CUES", true),

    -- Policies
    glue_single_items = get_ext_bool("GLUE_SINGLE_ITEMS", true),

    -- Debug
    debug_level = get_ext_num("DEBUG_LEVEL", 0),
    debug_no_clear = get_ext_bool("DEBUG_NO_CLEAR", true),
  }
end

------------------------------------------------------------
-- Build args table from ExtState
------------------------------------------------------------
local function build_args_from_extstate(op_mode)
  local cfg = read_extstate_settings(op_mode)

  local args = {
    -- Operation (passed in)
    op = op_mode,
    selection_scope = "auto",  -- Always auto for wrapper (ignore GUI selection_scope)
    channel_mode = cfg.channel_mode,
    multi_channel_policy = cfg.multi_channel_policy,

    -- FX toggles
    take_fx = cfg.take_fx,
    track_fx = cfg.track_fx,
    tc_mode = cfg.tc_mode,

    -- Volume handling
    merge_to_item = cfg.merge_to_item,
    merge_to_take = cfg.merge_to_take,
    print_volumes = cfg.print_volumes,

    -- Handle
    handle = (cfg.handle_mode == "ext") and "ext" or {
      mode = "seconds",
      seconds = cfg.handle_seconds,
    },

    -- Epsilon: use Core internal constant
    epsilon = "ext",

    -- Cues
    cues = {
      write_edge = cfg.write_edge_cues,
      write_glue = cfg.write_glue_cues,
    },

    -- Policies
    policies = {
      glue_single_items = cfg.glue_single_items,
      glue_no_trackfx_output_policy = "preserve",
      render_no_trackfx_output_policy = "preserve",
    },

    -- Debug (override with QUICK_DEBUG if not using ExtState debug)
    debug = {
      level = cfg.debug_level,
      no_clear = cfg.debug_no_clear,
    },

    -- Store selection_policy for wrapper use
    _selection_policy = cfg.selection_policy,
  }

  return args
end

------------------------------------------------------------
-- USER CONFIG (edit here) - Only used when USE_EXTSTATE = false
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

-- If you didn't choose a preset, configure manually here:
local manual_args = (_PRESET) or {
  -- Core operation
  op              = "render",        -- "auto" | "render" | "glue"
  selection_scope = "auto",          -- "auto" | "units" | "ts" | "item"  (ignored when op="render")
  channel_mode    = "mono",        -- "auto" | "mono" | "multi"

  -- Render toggles (only effective when op resolves to render)
  take_fx  = false,                 -- bake take FX on render
  track_fx = false,                 -- bake track FX on render
  tc_mode  = "current",           -- "previous" | "current" | "off" (BWF TimeReference embed)

  -- Volume handling (only effective when op resolves to render)
  -- NOTE: merge_to_item + print_volumes=true is NOT supported (REAPER can only print take volume)
  -- Valid: OFF | merge_to_item (print OFF) | merge_to_take + print OFF/ON
  merge_to_item = false,            -- merge take volume into item volume (print OFF only; mutually exclusive with merge_to_take)
  merge_to_take = true,             -- merge item volume into take volume (supports both print OFF/ON; mutually exclusive with merge_to_item)
  print_volumes = false,            -- bake volumes into rendered audio (false = restore original volumes; requires merge_to_take if enabled)

  -- One-run overrides (simple knobs)
  -- Handle: choose how to interpret length; wrapper will convert to Core format
  handle_mode   = "seconds",     -- "ext" | "seconds" | "frames"
  handle_length = 1.5,       -- value; if "frames", wrapper converts to seconds using project FPS

  -- Epsilon: native support for frames/seconds in Core
  epsilon_mode  = "frames",  -- "ext" | "frames" | "seconds"
  epsilon_value = 0.5,       -- threshold value in selected unit

  cues = {
    write_edge = false,             -- #in/#out edge cues as media cues
    write_glue = false,             -- #Glue: <TakeName> cues inside glued media when sources change
  },

  policies = {
    glue_single_items = true,                       -- in op="auto": single item => render (if false)
    glue_no_trackfx_output_policy   = "preserve",   -- "preserve" | "force_multi"
    render_no_trackfx_output_policy = "preserve",   -- "preserve" | "force_multi"
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
    local fps = r.TimeMap_curFrameRate(0) or 30
    -- Core expects seconds for handle; convert frames -> seconds
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

------------------------------------------------------------
-- Build final args table
------------------------------------------------------------
local args
if USE_EXTSTATE then
  -- Read from ExtState (same as GUI settings)
  -- You can change this to "glue" or "auto" as needed
  local op_mode = "render"  -- Change this to your desired operation
  args = build_args_from_extstate(op_mode)
  -- Override debug with QUICK_DEBUG setting
  args.debug = apply_quick_debug(QUICK_DEBUG, args.debug or {})
else
  -- Use manual config
  args = manual_args
  -- Apply conversions for manual config
  args.handle  = resolve_handle_from_knobs(args)
  args.epsilon = resolve_epsilon_from_knobs(args)
  -- Apply quick debug policy to args.debug
  args.debug = apply_quick_debug(QUICK_DEBUG, args.debug or {})
end

------------------------------------------------------------
-- Helpers for smart item-restore
------------------------------------------------------------
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
------------------------------------------------------------
-- Helper: snapshot current selection/context
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
-- When USE_EXTSTATE is true, read from ExtState; otherwise use hardcoded SELECTION_POLICY
local policy
if USE_EXTSTATE and args._selection_policy then
  policy = tostring(args._selection_policy)
else
  policy = tostring(SELECTION_POLICY or "restore")
end

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
  if USE_EXTSTATE then
    r.ShowConsoleMsg("[WRAPPER] Mode: ExtState (reading from GUI settings)\n")
  else
    r.ShowConsoleMsg("[WRAPPER] Mode: Manual (using hardcoded settings)\n")
  end
end

-- Run Core
_t_core0 = r.time_precise()
local ok_run, err = RGWH.core(args)
_t_core1 = r.time_precise()

-- Show error if Core failed (always, regardless of debug level)
if not ok_run then
  r.ShowConsoleMsg(("[WRAPPER] Error: %s\n"):format(tostring(err)))
end

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
