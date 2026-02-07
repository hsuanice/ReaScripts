--[[
@description RGWH Glue - Glue with Handles (ExtState Shortcut)
@author hsuanice
@version 0.2.2
@provides
  [main] .
@about
  Keyboard shortcut wrapper for RGWH Glue operation.
  Reads ALL settings from RGWH ExtState (same settings as GUI).

  This script acts as a quick-launch shortcut:
  - Bind to a keyboard shortcut for instant glue access
  - Uses the same settings you configured in RGWH GUI
  - No need to open GUI - just press the shortcut

  Settings are read from:
  - Project ExtState namespace "RGWH" (set by RGWH GUI)

@usage
  1) Configure your preferred settings in RGWH GUI (hsuanice_RGWH ReaImGui.lua)
  2) Assign this script to a keyboard shortcut in REAPER
  3) Select item(s) and press the shortcut to glue with handles

@notes
  - op is forced to "glue" (this is a glue shortcut)
  - selection_scope is forced to "auto" (works with items or time selection)
  - All other settings come from RGWH ExtState
  - If ExtState is empty, uses RGWH Core defaults

@changelog
  0.2.2 (260207.0230)
    - FIXED: Force selection_scope = "auto" (ignore GUI SELECTION_SCOPE)
      • Prevents "no_time_selection" error when GUI is set to TS mode
      • Wrapper now works with both item selection and time selection
    - ADDED: Error message display when Core fails (always shown)

  0.2.1 (260206.2345)
    - ADDED: MULTI_CHANNEL_POLICY reading
    - ADDED: SELECTION_SCOPE reading
    - ADDED: SELECTION_POLICY reading (replaces hardcoded value)
    - ADDED: GLUE_MERGE_TO_ITEM reading
    - IMPACT: Now reads ALL GUI settings from ExtState

  0.2.0 (260206.2230)
    - BREAKING: Now reads ALL settings from RGWH ExtState
    - Acts as keyboard shortcut for RGWH GUI glue operation
    - No more hardcoded settings - mirrors GUI configuration
    - Simplified code: removed manual args table
    - TS-aware selection restore for split items

  0.1.0 (2025-12-12) [internal: v251022_2200]
    - Initial release with hardcoded settings
]]--

------------------------------------------------------------
-- Resolve RGWH Core
------------------------------------------------------------
local r = reaper
local RES_PATH = r.GetResourcePath()
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua'

local ok_load, RGWH = pcall(dofile, CORE_PATH)
if not ok_load or type(RGWH) ~= "table" or type(RGWH.core) ~= "function" then
  r.ShowConsoleMsg(("[RGWH GLUE] Failed to load Core at:\n  %s\nError: %s\n")
    :format(CORE_PATH, tostring(RGWH)))
  return
end

------------------------------------------------------------
-- ExtState Reading (project-scope, namespace "RGWH")
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
-- Read Settings from ExtState
------------------------------------------------------------
local function read_extstate_settings()
  return {
    -- Channel mode
    channel_mode = get_ext("GLUE_APPLY_MODE", "auto"),
    multi_channel_policy = get_ext("MULTI_CHANNEL_POLICY", "source_playback"),

    -- FX settings
    take_fx = get_ext_bool("GLUE_TAKE_FX", true),
    track_fx = get_ext_bool("GLUE_TRACK_FX", false),

    -- Selection (from GUI)
    selection_scope = get_ext("SELECTION_SCOPE", "auto"),
    selection_policy = get_ext("SELECTION_POLICY", "restore"),

    -- Volume handling
    merge_to_item = get_ext_bool("GLUE_MERGE_TO_ITEM", false),
    merge_to_take = get_ext_bool("GLUE_MERGE_VOLUMES", true),
    print_volumes = get_ext_bool("GLUE_PRINT_VOLUMES", true),

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
local function build_args_from_extstate()
  local cfg = read_extstate_settings()

  local args = {
    -- Force glue operation
    op = "glue",
    selection_scope = "auto",  -- Always auto for wrapper (ignore GUI selection_scope)
    channel_mode = cfg.channel_mode,
    multi_channel_policy = cfg.multi_channel_policy,

    -- FX toggles (for glue post-processing)
    take_fx = cfg.take_fx,
    track_fx = cfg.track_fx,
    tc_mode = "current",  -- glue always uses current

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

    -- Debug
    debug = {
      level = cfg.debug_level,
      no_clear = cfg.debug_no_clear,
    },
  }

  return args
end

------------------------------------------------------------
-- Selection Policy from ExtState (replaces hardcoded value)
------------------------------------------------------------
local SELECTION_POLICY = get_ext("SELECTION_POLICY", "restore")

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

local function _ms(dt)
  if not dt then return "0.0" end
  return string.format("%.1f", dt * 1000.0)
end

------------------------------------------------------------
-- Snapshot / Restore Selection (TS-aware for glue)
------------------------------------------------------------
local function snapshot_selection()
  local s = {}
  s.items = {}
  for i = 0, r.CountSelectedMediaItems(0)-1 do
    local it = r.GetSelectedMediaItem(0, i)
    local tr = it and r.GetMediaItem_Track(it) or nil
    local tgd = tr and track_guid(tr) or nil
    local pos = it and r.GetMediaItemInfo_Value(it, "D_POSITION") or nil
    local len = it and r.GetMediaItemInfo_Value(it, "D_LENGTH") or nil
    s.items[#s.items+1] = {
      ptr = it,
      tr = tr,
      tr_guid = tgd,
      start = pos,
      finish = (pos and len) and (pos + len) or nil,
    }
  end
  s.tracks = {}
  for t = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, t)
    if r.IsTrackSelected(tr) then
      s.tracks[#s.tracks+1] = tr
    end
  end
  s.ts_start, s.ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  s.edit_pos = r.GetCursorPosition()
  return s
end

local function restore_selection(s, args)
  if not s then return end
  r.SelectAllMediaItems(0, false)
  if s.items then
    local eps = seconds_epsilon_from_args(args)
    -- Check if TS exists for smart TS-aware restore
    local tsL, tsR = s.ts_start, s.ts_end
    local has_ts = (tsL and tsR and tsR > tsL)

    for _, desc in ipairs(s.items) do
      local selected = false

      -- When TS exists and may have caused splits, verify pointer still matches original position
      if has_ts and desc.ptr and r.ValidatePtr2(0, desc.ptr, "MediaItem*") then
        local p = r.GetMediaItemInfo_Value(desc.ptr, "D_POSITION")
        local l = r.GetMediaItemInfo_Value(desc.ptr, "D_LENGTH")
        -- Check if position/length still matches original (within epsilon)
        if math.abs(p - desc.start) < eps and math.abs((p + l) - desc.finish) < eps then
          r.SetMediaItemSelected(desc.ptr, true)
          selected = true
        end
        -- If position changed (due to split), fall through to TS-aware restore
      elseif desc.ptr and r.ValidatePtr2(0, desc.ptr, "MediaItem*") then
        -- No TS: simple pointer restore
        r.SetMediaItemSelected(desc.ptr, true)
        selected = true
      end

      if not selected then
        -- fallback: match by same-track + time overlap
        local tr = desc.tr
        if (not tr or not r.ValidatePtr2(0, tr, "MediaTrack*")) and desc.tr_guid then
          tr = find_track_by_guid(desc.tr_guid)
        end
        if tr and desc.start and desc.finish then
          local N = r.CountTrackMediaItems(tr)
          local best_item = nil
          local best_overlap = 0

          -- When TS exists, prefer items that overlap with TS (smart TS-aware restore)
          if has_ts then
            for i = 0, N - 1 do
              local it2 = r.GetTrackMediaItem(tr, i)
              local p = r.GetMediaItemInfo_Value(it2, "D_POSITION")
              local l = r.GetMediaItemInfo_Value(it2, "D_LENGTH")
              local q1, q2 = p, p + l
              local a1, a2 = desc.start - eps, desc.finish + eps

              -- Check overlap with original item
              if (q1 < a2) and (q2 > a1) then
                -- Calculate overlap with TS
                local ts_overlap_start = math.max(q1, tsL)
                local ts_overlap_end = math.min(q2, tsR)
                local ts_overlap = math.max(0, ts_overlap_end - ts_overlap_start)

                -- Prefer items with maximum TS overlap
                if ts_overlap > best_overlap then
                  best_item = it2
                  best_overlap = ts_overlap
                end
              end
            end
            if best_item then
              r.SetMediaItemSelected(best_item, true)
              selected = true
            end
          else
            -- No TS: use original logic (first overlap)
            for i = 0, N - 1 do
              local it2 = r.GetTrackMediaItem(tr, i)
              local p = r.GetMediaItemInfo_Value(it2, "D_POSITION")
              local l = r.GetMediaItemInfo_Value(it2, "D_LENGTH")
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
      end
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
end

local function summarize_selection(s)
  if not s then return "  (no snapshot)\n" end
  local items = s.items and #s.items or 0
  local tracks = s.tracks and #s.tracks or 0
  local ts
  if s.ts_start and s.ts_end and (s.ts_end > s.ts_start) then
    ts = string.format("%.3f..%.3f", s.ts_start, s.ts_end)
  else
    ts = "empty"
  end
  local cursor = s.edit_pos or -1
  return string.format("  items=%d  tracks=%d  ts=%s  cursor=%.3f\n", items, tracks, ts, cursor)
end

------------------------------------------------------------
-- RUN
------------------------------------------------------------
local args = build_args_from_extstate()
local policy = tostring(SELECTION_POLICY or "restore")

local sel_before = nil
local _t_all0, _t_all1 = r.time_precise(), nil
local _t_snap0, _t_snap1 = nil, nil
local _t_core0, _t_core1 = nil, nil
local _t_rest0, _t_rest1 = nil, nil

if policy == "restore" then
  _t_snap0 = r.time_precise()
  sel_before = snapshot_selection()
  _t_snap1 = r.time_precise()
end

if args.debug and (args.debug.level or 0) > 0 then
  if args.debug.no_clear == false then r.ClearConsole() end
  r.ShowConsoleMsg(("[RGWH GLUE][Selection Debug] policy=%s  [before]\n%s")
    :format(policy, summarize_selection(sel_before)))
end

_t_core0 = r.time_precise()
local ok_run, err = RGWH.core(args)
_t_core1 = r.time_precise()

-- Show error if Core failed (always, regardless of debug level)
if not ok_run then
  r.ShowConsoleMsg(("[RGWH GLUE] Error: %s\n"):format(tostring(err)))
end

if policy == "restore" and sel_before then
  _t_rest0 = r.time_precise()
  restore_selection(sel_before, args)
  _t_rest1 = r.time_precise()
elseif policy == "none" then
  r.SelectAllMediaItems(0, false)
end

r.UpdateArrange()
_t_all1 = r.time_precise()

if args.debug and (args.debug.level or 0) > 0 then
  local d_snap = (_t_snap0 and _t_snap1) and (_t_snap1 - _t_snap0) or 0
  local d_core = (_t_core0 and _t_core1) and (_t_core1 - _t_core0) or 0
  local d_rest = (_t_rest0 and _t_rest1) and (_t_rest1 - _t_rest0) or 0
  local d_all = (_t_all0 and _t_all1) and (_t_all1 - _t_all0) or 0
  r.ShowConsoleMsg(("[RGWH GLUE][Perf] snapshot=%sms  core=%sms  restore=%sms  total=%sms\n")
    :format(_ms(d_snap), _ms(d_core), _ms(d_rest), _ms(d_all)))

  local sel_after = snapshot_selection()
  r.ShowConsoleMsg(("[RGWH GLUE][Selection Debug] [after]\n%s")
    :format(summarize_selection(sel_after)))
end
