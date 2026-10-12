--[[
@description AudioSweet Preview Core
@version 26.1011.2142
@author hsuanice
@noindex
@changelog
  - Released as part of the 26.1011.2142 package update.
  - Full history of earlier versions: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Minimal, self-contained preview runtime. Later we can extract helpers to "hsuanice_AS Core.lua".
--]]

-- Solo scope for preview isolation: "track" or "item"
local USER_SOLO_SCOPE = "track"
-- Enable Core debug logs (printed via ASP.log / ASP.dlog)
local USER_DEBUG = false
-- Move-back strategy on cleanup:
--   "guid"     → move back only the items this preview moved (by GUID)
--   "timesel"  → move back ALL items on the FX track that overlap the placeholder/time selection
-- If overlap with destination (source track) is detected, a warning dialog is shown and the move-back is aborted.
local USER_RESTORE_MODE = "guid"  -- "guid" | "timesel"
-- =========================================================================

-- === [AS PREVIEW CORE · Debug / State] ======================================
local ASP = _G.ASP or {}
_G.ASP = ASP

-- ===== Forward declarations (must appear before any use) =====
local project_epsilon
local ranges_touch_or_overlap
local ranges_strict_overlap
local undo_begin
local undo_end_no_undo

-- ExtState keys
ASP.ES_NS         = "hsuanice_AS"
ASP.ES_STATE      = "PREVIEW_STATE"     -- json: {running=true/false, mode="solo"/"normal"}
ASP.ES_DEBUG      = "DEBUG"             -- "1" to enable logs
ASP.ES_MODE       = "PREVIEW_MODE"      -- "solo" | "normal" ; written by wrappers, read-only for Core

-- NEW: simple run-flag for cross-script handshake
ASP.ES_RUN        = "PREVIEW_RUN"       -- "1" while preview is running, else "0"
ASP.ES_FX_GUID    = "PREVIEW_FX_GUID"   -- GUID of the FX track used during preview
ASP.ES_STOP_REQ   = "PREVIEW_STOP_REQ"  -- "1" = toggle requests watcher to stop & cleanup

local function _set_run_flag(on)
  reaper.SetExtState(ASP.ES_NS, ASP.ES_RUN, on and "1" or "0", false)
end

-- Mode from ExtState (fallback to opts.default_mode or "solo")
local function read_mode(default_mode)
  local m = reaper.GetExtState(ASP.ES_NS, ASP.ES_MODE)
  if m == "solo" or m == "normal" then return m end
  return default_mode or "solo"
end

-- Solo scope from Core user option only
local function read_solo_scope()
  return (USER_SOLO_SCOPE == "item") and "item" or "track"
end

-- FX enable snapshot/restore on a track
local function snapshot_fx_enabled(track)
  local t = {}
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do
    t[i] = reaper.TrackFX_GetEnabled(track, i)
  end
  return t
end

local function restore_fx_enabled(track, shot)
  if not shot then return end
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do
    local want = shot[i]
    if want ~= nil then reaper.TrackFX_SetEnabled(track, i, want) end
  end
end

-- Isolate focused FX but keep a mask to restore later
local function isolate_only_focused_fx(track, fxindex)
  local mask = snapshot_fx_enabled(track)
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do reaper.TrackFX_SetEnabled(track, i, i == fxindex) end
  return mask
end

-- Compute preview span: Time Selection > items span
local function compute_preview_span()
  local L,R = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if R > L then return L, R end
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return nil,nil end
  local UL, UR
  for i=0, cnt-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    UL = UL and math.min(UL, pos) or pos
    UR = UR and math.max(UR, pos+len) or (pos+len)
  end
  return UL, UR
end

-- Placeholder: one red empty item with note = PREVIEWING @ Track <n> - <FXName>
local function make_placeholder(track, UL, UR, note)
  local it = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", UL or 0)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",  (UR and UL) and (UR-UL) or 1.0)
  local tk = reaper.AddTakeToMediaItem(it) -- just to satisfy note storage
  reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", true) -- keep empty name
  reaper.GetSetMediaItemInfo_String(it, "P_NOTES", note or "", true)
  -- set red tint for clarity (RGB | 0x1000000 enables the tint)
  reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", reaper.ColorToNative(255,0,0)|0x1000000)
  reaper.UpdateItemInProject(it)
  return it
end

local function remove_placeholder(it)
  if not it then return end
  reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it)
end

-- get item bounds [L, R]
local function item_bounds(it)
  local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  return L, R
end

-- check if moving an interval [UL,UR] into target track would overlap any existing item (excluding a given set and excluding a placeholder)
local function track_has_overlap(tr, UL, UR, exclude_set, placeholder_it, allow_guid_map)
  if not tr then return false end
  local ic = reaper.CountTrackMediaItems(tr)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if it ~= placeholder_it then
      local skip = false
      if exclude_set and it and exclude_set[it] then skip = true end
      if not skip then
        local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if ranges_strict_overlap(L, R, UL, UR) then
          if allow_guid_map then
            local g = guid_of(it)
            if g and allow_guid_map[g] then
              -- allowed to overlap (original neighbor / crossfade partner)
              goto continue
            end
          end
          return true
        end
      end
    end
    ::continue::
  end
  return false
end
-- Find the placeholder item on the source track (identified by note prefix "PREVIEWING @")
local function find_placeholder_on_track(track)
  if not track then return nil end
  local ic = reaper.CountTrackMediaItems(track)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local _, note = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
    if note and note:find("^PREVIEWING @") then
      local UL  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local LEN = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      return it, UL, UL + LEN
    end
  end
  return nil
end



-- Collect items on the FX track that belong to the "previewed" set within the placeholder span (excluding the placeholder itself)
local function collect_preview_items_on_fx_track(track, ph_item, UL, UR)
  local items = {}
  if not track then return items end
  local ic = reaper.CountTrackMediaItems(track)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    if it ~= ph_item then
      local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if ranges_touch_or_overlap(L, R, UL, UR) then
        table.insert(items, it)
      end
    end
  end
  return items
end

-- Debug helpers
local function now_ts()
  return os.date("%H:%M:%S")
end

function ASP._dbg_enabled()
  return USER_DEBUG
end

function ASP.log(fmt, ...)
  if not ASP._dbg_enabled() then return end
  local msg = ("[AS][PREVIEW][%s] " .. fmt):format(now_ts(), ...)
  reaper.ShowConsoleMsg(msg .. "\n")
end

-- Resolve different "target" specs into (track, fxindex, kind)
-- target supports:
--   "focused" | "name:<TrackName>" | { by="name", value="<TrackName>" }
-- Return values:
--   FXtrack :: MediaTrack*
--   FXindex :: integer or nil  (nil for Chain mode; 0-based index for Focused mode)
--   kind    :: "trackfx" | "takefx" | "none"
function ASP._resolve_target(target)
  -- 1) Directly given a MediaTrack* object
  if type(target) == "userdata" then
    return target, nil, "trackfx"
  end

  -- 2) focused
  local function read_focused()
    local rv, trNum, itNum, fxNum = reaper.GetFocusedFX()
    -- rv: 0 none, 1 trackfx, 2 takefx
    if rv == 1 then
      local tr = reaper.GetTrack(0, trNum-1)
      return tr, fxNum, "trackfx"
    elseif rv == 2 then
      -- Take FX also maps back to the item's track; Chain preview uses the entire track FX chain
      local it = reaper.GetMediaItem(0, itNum)
      if it then
        local tr = reaper.GetMediaItem_Track(it)
        return tr, fxNum, "takefx"
      end
    end
    return nil, nil, "none"
  end

  if target == "focused" or (type(target)=="table" and target.by=="focused") then
    return read_focused()
  end

  -- 3) "name:XXX"
  if type(target) == "string" then
    local name = target:match("^name:(.+)$")
    if name then
      local tc = reaper.CountTracks(0)
      for i=0, tc-1 do
        local tr = reaper.GetTrack(0, i)
        local _, tn = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if (tn or "") == name then return tr, nil, "trackfx" end
      end
      return nil, nil, "none"
    end
  end

  -- 4) { by="name"/"guid"/"index", value=... }
  if type(target) == "table" then
    if target.by == "name" then
      local want = tostring(target.value or "")
      local tc = reaper.CountTracks(0)
      for i=0, tc-1 do
        local tr = reaper.GetTrack(0, i)
        local _, tn = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if (tn or "") == want then return tr, nil, "trackfx" end
      end
      return nil,nil,"none"
    elseif target.by == "guid" then
      -- Searching GUIDs track-by-track and item-by-item is too heavy; not recommended.
      -- You may inject your own GUID→Track mapping externally. Returns "none" here.
      return nil,nil,"none"
    elseif target.by == "index" then
      local idx = tonumber(target.value or 1)
      local tr = reaper.GetTrack(0, (idx or 1)-1)
      return tr, nil, tr and "trackfx" or "none"
    end
  end

  return nil, nil, "none"
end

-- Minimal JSON encode for small tables (no nested tables needed here)
local function tbl2json(t)
  local parts = {"{"}
  local first = true
  for k,v in pairs(t) do
    if not first then table.insert(parts, ",") end
    first = false
    local vv = (type(v)=="string") and ('"'..v..'"') or tostring(v)
    table.insert(parts, ('"%s":%s'):format(k, vv))
  end
  table.insert(parts, "}")
  return table.concat(parts)
end

local function write_state(t)
  reaper.SetExtState(ASP.ES_NS, ASP.ES_STATE, tbl2json(t), false)
end

-- args = {
--   mode        = "solo"|"normal",         -- default "solo"
--   target      = "focused"|"name:<TrackName>"|{by="name", value="<TrackName>"},
--   target_track_name = "MyChain",         -- convenience: same as target={by="name", value="MyChain"}
--   chain_mode  = true|false,              -- true = Track FX Chain preview (no isolate)
--                                          -- false = Focused preview; Core will FORCE target to "focused"
--                                          --          (ignores any name-based target or TARGET_TRACK_NAME)
--   isolate_focused = true|false,          -- only meaningful when chain_mode=false; default true
--   solo_scope  = "track"|"item",          -- override USER_SOLO_SCOPE (optional)
--   restore_mode= "guid"|"timesel",        -- override USER_RESTORE_MODE (optional)
--   debug       = true|false,              -- override USER_DEBUG (optional)
-- }
function ASP.preview(args)
  args = args or {}

  -- Read-only normalization: produce a single target_spec without mutating args
  -- inside ASP.preview(args)
  local function normalize_target(a)
    -- A) explicit mode: focused / pass-through
    if a.target == "focused" then
      return "focused"                       -- ignore target_track_name
    end
    if a.target ~= nil and a.target ~= "TARGET_TRACK_NAME" then
      return a.target                        -- pass-through ("name:<X>" or table spec)
    end

    -- B) sentinel: target = "TARGET_TRACK_NAME"
    if a.target == "TARGET_TRACK_NAME" then
      local name = a.target_track_name
      if type(name) ~= "string" or name == "" then
        name = _G.TARGET_TRACK_NAME
      end
      if type(name) == "string" and name ~= "" then
        return { by = "name", value = name } -- use provided name
      end
      return { by = "name", value = "AudioSweet" } -- last-resort fallback
    end

    -- C) no explicit target: allow direct name when target is nil
    if a.target == nil and type(a.target_track_name) == "string" and a.target_track_name ~= "" then
      return { by = "name", value = a.target_track_name }
    end

    -- D) default when nothing specified
    return "focused"
  end

  local mode       = (args.mode == "normal") and "normal" or "solo"
  local chain_mode = args.chain_mode == true

  -- Override Core user options (optional)
  if args.debug ~= nil then USER_DEBUG = args.debug and true or false end
  USER_SOLO_SCOPE = (args.solo_scope == "item") and "item" or "track"
  USER_RESTORE_MODE = (args.restore_mode == "timesel") and "timesel" or "guid"

  -- Resolve target once
  -- Focused preview (chain_mode=false) always uses "focused", ignoring any name-based targets.
  local target_spec = chain_mode and normalize_target(args) or "focused"
  local FXtrack, FXindex, kind = ASP._resolve_target(target_spec)

  -- Fallback: if resolution failed, try name:AudioSweet
  if not FXtrack then
    FXtrack, FXindex, kind = ASP._resolve_target("name:AudioSweet")
  end

  -- Chain mode does not need an FX index
  local focus_index = chain_mode and nil or FXindex

  -- Mirror the chosen mode into ExtState (for cross-wrapper toggle)
  reaper.SetExtState(ASP.ES_NS, ASP.ES_MODE, mode, false)

  return ASP.run{
    mode          = mode,
    focus_track   = FXtrack,
    focus_fxindex = focus_index,
    no_isolate    = chain_mode,
    no_watcher    = args.no_watcher,
  }
end

-- Internal runtime state (persist across re-loads)
ASP._state = ASP._state or {
  running           = false,
  mode              = nil,
  play_was_on       = nil,
  repeat_was_on     = nil,
  selection_cache   = nil,
  fx_track          = nil,
  fx_index          = nil,
  moved_items       = {},
  placeholder       = nil,
  fx_enable_shot    = nil,
  track_nchan       = nil,  -- Snapshot of FX track channel count
  src_track_nchan   = nil,  -- Snapshot of source track channel count
  stop_watcher      = false,
  allow_overlap_guids = nil,
}

function ASP.is_running()
  return ASP._state.running
end



function ASP.toggle_mode(start_hint)
  -- if not running -> start with start_hint
  if not ASP._state.running then
    return ASP.run{ mode = start_hint, focus_track = ASP._state.fx_track, focus_fxindex = ASP._state.fx_index }
  end
  local target = (ASP._state.mode == "solo") and "normal" or "solo"
  ASP._switch_mode(target)
end

function ASP._switch_mode(newmode)
  ASP.log("switch mode: %s -> %s", tostring(ASP._state.mode), newmode)
  if newmode == ASP._state.mode then return end

  -- ==== NO-UNDO GUARD (entire mode switch) ====
  undo_begin()  -- Ensure the following Main_OnCommand / I_SOLO operations create no Undo points

  local scope = read_solo_scope()
  local FXtr  = ASP._state.fx_track

  -- Before switching, clear both solo states to ensure a clean state
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  if ASP._state.moved_items and #ASP._state.moved_items > 0 then
    ASP._select_items(ASP._state.moved_items, true)

    if newmode == "solo" then
      if scope == "track" then
        if FXtr then reaper.SetMediaTrackInfo_Value(FXtr, "I_SOLO", 1) end
        ASP.log("switch→solo TRACK: FX track solo ON")
      else
        reaper.Main_OnCommand(41558, 0) -- Item: Solo exclusive
        ASP.log("switch→solo ITEM: item-solo-exclusive ON")
      end
    else
      -- normal: keep non-solo (already cleared above)
      ASP.log("switch→normal: solo cleared (items & tracks)")
    end
  end

  ASP._state.mode = newmode
  write_state({running=true, mode=newmode})
  ASP.log("switch done: now=%s (scope=%s)", newmode, scope)

  undo_end_no_undo("AS Preview: switch mode (no undo)")  
  -- ==== END NO-UNDO GUARD ====
end


----------------------------------------------------------------
-- (A) Debug / log (built-in for now; may be moved to AS Core later)
----------------------------------------------------------------
local function debug_enabled()
  return USER_DEBUG
end
local function log_step(tag, fmt, ...)
  if not debug_enabled() then return end
  local msg = fmt and string.format(fmt, ...) or ""
  reaper.ShowConsoleMsg(string.format("[AS][PREVIEW] %s %s\n", tostring(tag or ""), msg))
end

-- === Undo helpers: wrap mutating ops but do NOT create undo points ===
undo_begin = function()
  reaper.Undo_BeginBlock2(0)
end

undo_end_no_undo = function(desc)
  -- desc is for debug readability only; -1 means **no** undo point will be created
  reaper.Undo_EndBlock2(0, desc or "AS Preview (no undo)", -1)
end

----------------------------------------------------------------
-- (B) Basic utilities (epsilon / selection / units / items / fx)
--   Currently includes minimal subset; will later be extracted to AS Core
----------------------------------------------------------------
project_epsilon = function()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end
local function approx_eq(a,b,eps) eps = eps or project_epsilon(); return math.abs(a-b) <= eps end
ranges_touch_or_overlap = function(a0,a1,b0,b1,eps)
  eps = eps or project_epsilon()
  return not (a1 < b0 - eps or b1 < a0 - eps)
end
-- NEW: strict overlap (edges touching are NOT overlap)
ranges_strict_overlap = function(a0,a1,b0,b1,eps)
  eps = eps or project_epsilon()
  -- true only if interiors intersect strictly
  return (a0 < b1 - eps) and (a1 > b0 + eps)
end

-- ==========================================================
-- v0.2.2: build_units_from_selection() removed (dead code, never called)
-- Note: Preview Core uses direct item manipulation, not unit-based workflow
-- ==========================================================

local function getLoopSelection()
  local isSet, isLoop = false, false
  local allowautoseek = false
  local L,R = reaper.GetSet_LoopTimeRange(isSet, isLoop, 0,0, allowautoseek)
  local has = not (L==0 and R==0)
  return has, L, R
end



local function items_all_on_track(items, tr)
  for _,it in ipairs(items) do if reaper.GetMediaItem_Track(it) ~= tr then return false end end
  return true
end

local function select_only_items(items)
  reaper.Main_OnCommand(40289, 0)
  for _,it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
end

local function item_guid(it)
  return select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false))
end



local function snapshot_selection()
  local map = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then map[item_guid(it)] = true end
  end
  return map
end

local function restore_selection(selmap)
  if not selmap then return end
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  local tr_cnt = reaper.CountTracks(0)
  for ti=0, tr_cnt-1 do
    local tr = reaper.GetTrack(0, ti)
    local ic = reaper.CountTrackMediaItems(tr)
    for ii=0, ic-1 do
      local it = reaper.GetTrackMediaItem(tr, ii)
      if it and selmap[item_guid(it)] then
        reaper.SetMediaItemSelected(it, true)
      end
    end
  end
end

-- helper: get item GUID
local function guid_of(it)
  return select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false))
end

-- snapshot neighbors on source track that touch/overlap the preview span
local function snapshot_allow_overlap_neighbors(src_tr, UL, UR, exclude_set)
  local map = {}
  if not src_tr then return map end
  local ic = reaper.CountTrackMediaItems(src_tr)
  local eps = project_epsilon()
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(src_tr, i)
    if not (exclude_set and exclude_set[it]) then
      local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if ranges_touch_or_overlap(L, R, UL, UR, eps) then
        local g = guid_of(it)
        if g and g ~= "" then map[g] = true end
      end
    end
  end
  return map
end

----------------------------------------------------------------
-- (C) Transport / mute snapshot and restore
----------------------------------------------------------------
local function snapshot_transport()
  return {
    repeat_on = (reaper.GetToggleCommandState(1068) == 1),
    playing   = (reaper.GetPlayState() & 1) == 1
  }
end

local function set_loop_and_repeat(L,R, want_repeat)
  reaper.GetSet_LoopTimeRange(true, true, L, R, false)
  if want_repeat and reaper.GetToggleCommandState(1068) ~= 1 then
    reaper.Main_OnCommand(1068, 0) -- Toggle repeat
  end
end

local function restore_transport(snap)
  if not snap then return end
  -- Turn off Repeat (if it was originally off)
  if not snap.repeat_on and reaper.GetToggleCommandState(1068) == 1 then
    reaper.Main_OnCommand(1068, 0)
  end
  -- Stop playback (if it was not playing initially)
  if not snap.playing and (reaper.GetPlayState() & 1) == 1 then
    reaper.Main_OnCommand(1016, 0) -- Stop
  end
end

local function snapshot_and_mute(items)
  local shot = {}
  for _,it in ipairs(items) do
    local m = reaper.GetMediaItemInfo_Value(it, "B_MUTE")
    table.insert(shot, {it=it, m=m})
    reaper.SetMediaItemInfo_Value(it, "B_MUTE", 1)
  end
  return shot
end

local function restore_mutes(shot)
  if not shot then return end
  for _,e in ipairs(shot) do
    if e.it then reaper.SetMediaItemInfo_Value(e.it, "B_MUTE", e.m or 0) end
  end
end

----------------------------------------------------------------
-- (D) Entry: allow only a single track (multiple items allowed); Time Selection takes priority over item selection
----------------------------------------------------------------
-- Begin preview (or switch if already running)
function ASP.run(opts)
  opts = opts or {}
  local FXtrack, FXindex = opts.focus_track, opts.focus_fxindex
  local mode = read_mode(opts.default_mode or "solo")  -- ExtState takes precedence
  local no_isolate = opts.no_isolate and true or false

  if not (mode == "solo" or mode == "normal") then
    reaper.MB("ASP.run: invalid mode", "AudioSweet Preview", 0); return
  end
  if not FXtrack then
    reaper.MB("ASP.run: focus track missing", "AudioSweet Preview", 0); return
  end
  if (not no_isolate) and (FXindex == nil) then
    reaper.MB("ASP.run: focus FX index missing (focused-FX preview requires a valid FX index)", "AudioSweet Preview", 0); return
  end

  ASP.log("run called, mode=%s", mode)
  ASP.log("Core options: SOLO_SCOPE=%s DEBUG=%s", read_solo_scope(), tostring(USER_DEBUG))
  -- Guard A: require at least one selected item (and if TS exists, require intersection)
  do
    local sel_cnt = reaper.CountSelectedMediaItems(0)
    if sel_cnt == 0 then
      ASP.log("no-targets: abort (no selected items)")
      reaper.MB("No preview targets found. Please select at least one item (or items within the time selection). Preview was not started.","AudioSweet Preview",0)
      return
    end
    local hasTS, tsL, tsR = getLoopSelection()
    if hasTS and tsR > tsL then
      local eps = project_epsilon()
      local overlap_found = false
      for i=0, sel_cnt-1 do
        local it  = reaper.GetSelectedMediaItem(0, i)
        if it then
          local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local fin = pos + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          if ranges_touch_or_overlap(pos, fin, tsL, tsR, eps) then overlap_found = true; break end
        end
      end
      if not overlap_found then
        ASP.log("no-targets: abort (TS set but no selected items intersect %.3f..%.3f)", tsL, tsR)
        reaper.MB("No preview targets found within the current time selection. Please select at least one item inside the time selection.","AudioSweet Preview",0)
        return
      end
    end
  end

  -- (1) Detect preview via a placeholder item (search only on the source track)
  local src_tr = ASP._state.src_track
  if not src_tr then
    local first_sel = reaper.GetSelectedMediaItem(0, 0)
    if first_sel then src_tr = reaper.GetMediaItem_Track(first_sel) end
  end

  local ph, UL, UR = nil, nil, nil
  if src_tr then
    ph, UL, UR = find_placeholder_on_track(src_tr)
  end

  if ph then
    ASP._state.running       = true
    ASP._state.fx_track      = FXtrack
    ASP._state.fx_index      = FXindex   -- allow nil (Chain mode)
    ASP._state.placeholder   = ph
    ASP._state.src_track     = src_tr
    ASP._state.moved_items   = collect_preview_items_on_fx_track(FXtrack, ph, UL, UR)
    ASP._state.mode          = (mode == "solo") and "normal" or "solo"
    ASP.log("detected existing placeholder on source track; bootstrap (items=%d)", #ASP._state.moved_items)

    _set_run_flag(true)  -- NEW: handshake ON

    undo_begin()
    ASP._switch_mode(mode)
    undo_end_no_undo("AS Preview: switch mode (no undo)")
    return
  end

  -- (2) Legacy path: if same instance with state.running=true (placeholder missing), allow rebuild (rare)
  if ASP._state.running then
    ASP.log("run: state.running=true but placeholder missing; rebuilding preview")
  end

  -- start preview (no-undo wrapper)
  undo_begin()
  _set_run_flag(true)  -- NEW: handshake ON
  reaper.SetExtState(ASP.ES_NS, ASP.ES_FX_GUID, reaper.GetTrackGUID(FXtrack), false)
  ASP._state.running       = true
  ASP._state.mode          = mode
  ASP._state.fx_track      = FXtrack
  ASP._state.fx_index      = FXindex     -- nil allowed (Chain)
  ASP._state.selection_cache = ASP._snapshot_item_selection()
  ASP._state.play_was_on   = (reaper.GetPlayState() & 1) == 1
  ASP._state.repeat_was_on = reaper.GetToggleCommandState(1068) == 1

  -- Snapshot track channel count before preview
  ASP._state.track_nchan = reaper.GetMediaTrackInfo_Value(FXtrack, "I_NCHAN")
  ASP.log("snapshot: track channel count = %d", ASP._state.track_nchan or -1)

  ASP._arm_loop_region_or_unit()
  ASP._ensure_repeat_on()

  -- Isolate focused FX (Chain mode: no isolate)
  if (not no_isolate) and (FXindex ~= nil) then
    ASP._state.fx_enable_shot = isolate_only_focused_fx(FXtrack, FXindex)
    ASP.log("focused FX isolated (index=%d)", FXindex or -1)
  else
    ASP._state.fx_enable_shot = nil
    ASP.log("chain-mode: no isolate; keep track FX enables as-is")
  end

  ASP._prepare_preview_items_on_fx_track(mode)
  ASP._apply_mode_flags(mode)

  write_state({running=true, mode=mode})
  ASP.log("preview started: mode=%s", mode)
  undo_end_no_undo("AS Preview: start (no undo)")

  if not opts.no_watcher and not ASP._state.stop_watcher then
    ASP._state.stop_watcher = true
    ASP._state._watcher_grace_until = reaper.time_precise() + 0.5  -- 500ms grace
    reaper.defer(ASP._watch_stop_and_cleanup)

    -- atexit: when REAPER terminates this script (e.g. user re-triggers the Toggle action),
    -- do full cleanup using L1's complete state — no bootstrap needed.
    reaper.atexit(function()
      if not ASP._state.running then return end  -- already cleaned up (e.g. by watcher)
      if (reaper.GetPlayState() & 1) == 1 then
        reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
      end
      local rm_val = reaper.GetExtState("hsuanice_AS_GUI", "preview_restore_mode")
      USER_RESTORE_MODE = (rm_val ~= "1") and "timesel" or "guid"
      ASP.cleanup_if_any()
    end)
  end
end

function ASP.switch_mode(opts)
  opts = opts or {}
  local want = opts.mode
  local st   = ASP._state
  if not st.running or not want or want == st.mode then return end

  -- target is "solo"
  if want == "solo" then
    -- restore original mutes first (avoid additive artifacts)
    restore_mutes(st.mute_shot); st.mute_shot = nil
    -- select preview items on the FX track → enable solo
    if st.moved_items and #st.moved_items > 0 then
      select_only_items(st.moved_items)
      reaper.Main_OnCommand(41561, 0) -- Toggle solo exclusive (entering from non-solo → becomes ON)
    end

  -- target is "normal"
  elseif want == "normal" then
    -- turn off item solo (toggle again)
    if st.moved_items and #st.moved_items > 0 then
      select_only_items(st.moved_items)
      reaper.Main_OnCommand(41561, 0) -- Toggle solo exclusive (leaving solo → becomes OFF)
    end
    -- then mute originals to avoid doubling
    if st.unit and st.unit.items then
      st.mute_shot = snapshot_and_mute(st.unit.items)
    end
  end

  st.mode = want
end

function ASP.cleanup_if_any()
  if not ASP._state.running then return end
  undo_begin()  -- ← added: pairs with undo_end_no_undo at the end
  ASP.log("cleanup begin")

  -- Safety: clear item-solo and track-solo
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  -- Restore FX enable state (only if focused mode isolated earlier)
  if ASP._state.fx_track and ASP._state.fx_enable_shot ~= nil then
    restore_fx_enabled(ASP._state.fx_track, ASP._state.fx_enable_shot)
    ASP._state.fx_enable_shot = nil
    ASP.log("FX enables restored")
  end

  -- Restore track channel count
  if ASP._state.fx_track and ASP._state.track_nchan then
    reaper.SetMediaTrackInfo_Value(ASP._state.fx_track, "I_NCHAN", ASP._state.track_nchan)
    ASP.log("restore: track channel count = %d", ASP._state.track_nchan)
    ASP._state.track_nchan = nil
  end

  -- Move the items back and delete the placeholder
  ASP._move_back_and_remove_placeholder()

  -- Restore Repeat / selection
  ASP._restore_repeat()
  ASP._restore_item_selection()

  ASP._state.running       = false
  ASP._state.mode          = nil
  ASP._state.fx_track      = nil
  ASP._state.fx_index      = nil
  ASP._state.moved_items   = {}
  ASP._state.placeholder   = nil
  ASP._state.src_track     = nil
  ASP._state.stop_watcher  = false

  write_state({running=false, mode=""})
  _set_run_flag(false)  -- NEW: handshake OFF
  reaper.SetExtState(ASP.ES_NS, ASP.ES_FX_GUID, "", false)
  reaper.SetExtState(ASP.ES_NS, ASP.ES_STOP_REQ, "", false)  -- clear any stale stop request
  ASP.log("cleanup done")
  undo_end_no_undo("AS Preview: cleanup (no undo)")
end

function ASP._watch_stop_and_cleanup()
  if not ASP._state.running then return end
  -- Zombie detection: if PREVIEW_RUN was externally cleared (e.g. by stop_preview
  -- from another instance), this watcher is orphaned — exit gracefully.
  if reaper.GetExtState(ASP.ES_NS, ASP.ES_RUN) ~= "1" then
    ASP._state.running = false
    ASP._state.stop_watcher = false
    return
  end

  -- (A) Check for stop-request from Toggle (cross-instance signal via ExtState)
  --     Processed immediately, even during grace period.
  local stop_req = reaper.GetExtState(ASP.ES_NS, ASP.ES_STOP_REQ)
  if stop_req == "1" then
    reaper.SetExtState(ASP.ES_NS, ASP.ES_STOP_REQ, "", false)  -- consume flag
    local rm_val = reaper.GetExtState("hsuanice_AS_GUI", "preview_restore_mode")
    USER_RESTORE_MODE = (rm_val ~= "1") and "timesel" or "guid"
    if (reaper.GetPlayState() & 1) == 1 then
      reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
    end
    ASP.log("stop requested via toggle -> cleanup")
    ASP.cleanup_if_any()
    return
  end

  -- (B) Grace period: ignore transport state for 500ms after preview start
  if ASP._state._watcher_grace_until then
    if reaper.time_precise() < ASP._state._watcher_grace_until then
      reaper.defer(ASP._watch_stop_and_cleanup)
      return
    end
    ASP._state._watcher_grace_until = nil  -- grace period over
  end

  -- (C) Normal stop detection: transport stopped + placeholder still alive
  local playing = (reaper.GetPlayState() & 1) == 1
  local ph_ok   = ASP._state.placeholder and reaper.ValidatePtr2(0, ASP._state.placeholder, "MediaItem*")
  if (not playing) and ph_ok then
    local rm_val = reaper.GetExtState("hsuanice_AS_GUI", "preview_restore_mode")
    USER_RESTORE_MODE = (rm_val ~= "1") and "timesel" or "guid"
    ASP.log("detected stop + placeholder alive -> cleanup")
    ASP.cleanup_if_any()
    return
  end
  reaper.defer(ASP._watch_stop_and_cleanup)
end

function ASP._snapshot_item_selection()
  local t = {}
  local cnt = reaper.CountSelectedMediaItems(0)
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    t[guid] = true
  end
  ASP.log("snapshot selection: %d items", cnt)
  return t
end

function ASP._restore_item_selection()
  if not ASP._state.selection_cache then return end
  -- clear current
  reaper.Main_OnCommand(40289,0) -- unselect all
  -- reselect previous
  local tot = reaper.CountMediaItems(0)
  for i=0, tot-1 do
    local it = reaper.GetMediaItem(0, i)
    local guid = select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false))
    if ASP._state.selection_cache[guid] then
      reaper.SetMediaItemSelected(it, true)
    end
  end
  reaper.UpdateArrange()
  ASP.log("restore selection done")
end

function ASP._ensure_repeat_on()
  if reaper.GetToggleCommandState(1068) ~= 1 then
    reaper.Main_OnCommand(1068, 0) -- Toggle repeat
    ASP.log("repeat ON")
  else
    ASP.log("repeat already ON")
  end
end

function ASP._restore_repeat()
  local want_on = ASP._state.repeat_was_on
  local now_on = (reaper.GetToggleCommandState(1068) == 1)
  if want_on ~= now_on then
    reaper.Main_OnCommand(1068, 0) -- Toggle repeat
    ASP.log("repeat restored to %s", want_on and "ON" or "OFF")
  end
end

function ASP._arm_loop_region_or_unit()
  local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts_end > ts_start then
    ASP.log("loop by Time Selection: %.3f..%.3f", ts_start, ts_end)
    return -- Loop is controlled by REAPER's time selection
  end

  -- No Time Selection: use the envelope span of currently selected items
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return end
  local UL, UR
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local L, R = pos, pos+len
    UL = UL and math.min(UL, L) or L
    UR = UR and math.max(UR, R) or R
  end
  reaper.GetSet_LoopTimeRange(true, false, UL, UR, false)
  ASP.log("loop armed by items span: %.3f..%.3f", UL, UR)
end

local function clone_item_to_track(src_it, dst_tr)
  local pos   = reaper.GetMediaItemInfo_Value(src_it, "D_POSITION")
  local len   = reaper.GetMediaItemInfo_Value(src_it, "D_LENGTH")
  local newit = reaper.AddMediaItemToTrack(dst_tr)
  reaper.SetMediaItemInfo_Value(newit, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(newit, "D_LENGTH",   len)

  local take  = reaper.GetActiveTake(src_it)
  if take then
    local src   = reaper.GetMediaItemTake_Source(take)
    local newtk = reaper.AddTakeToMediaItem(newit)
    reaper.SetMediaItemTake_Source(newtk, src)
    -- Common properties
    reaper.SetMediaItemTakeInfo_Value(newtk, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"))
    reaper.SetMediaItemTakeInfo_Value(newtk, "D_PLAYRATE",  reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"))
    reaper.SetMediaItemTakeInfo_Value(newtk, "I_CHANMODE",  reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"))
  end
  return newit
end

function ASP._prepare_preview_items_on_fx_track(mode)
  local cnt = reaper.CountSelectedMediaItems(0)
  ASP.log("_prepare_preview: counted %d selected items in REAPER", cnt)

  -- Debug: print each selected item
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local tr = reaper.GetMediaItem_Track(it)
      local tr_num = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
      ASP.log("  [%d] item pos=%.3f track=#%d", i, pos, tr_num or -1)
    end
  end

  if cnt == 0 then return end
  -- remember how many items were moved out in this preview session (for timesel count sanity check)
  ASP._state.moved_count = cnt or 0

  -- Compute preview span and create a placeholder (white empty item)
  local UL, UR = compute_preview_span()
  local tridx  = reaper.GetMediaTrackInfo_Value(ASP._state.fx_track, "IP_TRACKNUMBER")
  tridx = (tridx and tridx > 0) and math.floor(tridx) or 0

  local label
  if ASP._state.fx_index ~= nil then
    local _, fxname = reaper.TrackFX_GetFXName(ASP._state.fx_track, ASP._state.fx_index, "")
    label = fxname or "Focused FX"
  else
    local _, tn = reaper.GetSetMediaTrackInfo_String(ASP._state.fx_track, "P_NAME", "", false)
    label = tn and (#tn>0 and tn or "FX Track") or "FX Track"
  end
  local note = string.format("PREVIEWING @ Track %d - %s", tridx, label)

  -- Place on the source track: use the track of the first selected item
  local first_sel = reaper.GetSelectedMediaItem(0, 0)
  local src_tr = first_sel and reaper.GetMediaItem_Track(first_sel) or ASP._state.fx_track
  ASP._state.src_track = src_tr  -- Remember the source track for placeholder lookup on re-entry

  -- ★ Snapshot source track channel count (protect from REAPER auto-adjust on move back)
  ASP._state.src_track_nchan = tonumber(reaper.GetMediaTrackInfo_Value(src_tr, "I_NCHAN")) or 2
  ASP.log("snapshot: source track channel count = %d", ASP._state.src_track_nchan)

  ASP._state.placeholder = make_placeholder(src_tr, UL or 0, UR or (UL and UL+1 or 1), note)

  ASP.log("placeholder created: [%0.3f..%0.3f] %s", UL or -1, UR or -1, note)

  -- Move the selected items to the FX track
  -- IMPORTANT: Collect all items FIRST, then move them.
  -- If we move items during iteration, the selection indices shift when FX track is below the source track.
  ASP._state.moved_items = {}
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      table.insert(ASP._state.moved_items, it)
    end
  end

  -- Now move all collected items
  for _, it in ipairs(ASP._state.moved_items) do
    reaper.MoveMediaItemToTrack(it, ASP._state.fx_track)
  end
  reaper.UpdateArrange()
  ASP.log("moved %d items -> FX track", #ASP._state.moved_items)

  -- Debug: verify items are on FX track after move
  local fx_track_num = reaper.GetMediaTrackInfo_Value(ASP._state.fx_track, "IP_TRACKNUMBER")
  ASP.log("Verification: FX track #%d now has %d items total",
    fx_track_num or -1,
    reaper.CountTrackMediaItems(ASP._state.fx_track))
  for i, it in ipairs(ASP._state.moved_items) do
    local now_tr = reaper.GetMediaItem_Track(it)
    local now_tr_num = reaper.GetMediaTrackInfo_Value(now_tr, "IP_TRACKNUMBER")
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    ASP.log("  moved_items[%d]: now on track #%d, pos=%.3f", i, now_tr_num or -1, pos)
  end
end

function ASP._clear_preview_items_only()
  -- In the new flow we no longer delete preview items; we move them back.
  -- Keep this function name for compatibility.
  if ASP._state.moved_items and #ASP._state.moved_items > 0 then
    ASP.log("clear_preview_items_only(): nothing to delete under move-based preview")
  end
end

local function move_items_to_track(items, tr)
  for _,it in ipairs(items or {}) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      reaper.MoveMediaItemToTrack(it, tr)
    end
  end
end

function ASP._move_back_and_remove_placeholder()
  -- Decide which items to move back based on USER_RESTORE_MODE.
  local move_list = {}

  if not ASP._state.placeholder then
    ASP.log("no placeholder; skip move-back")
    ASP._state.moved_items = {}
    return
  end

  local ph_it = ASP._state.placeholder
  local ph_tr = reaper.GetMediaItem_Track(ph_it)
  local UL    = reaper.GetMediaItemInfo_Value(ph_it, "D_POSITION")
  local UR    = UL + reaper.GetMediaItemInfo_Value(ph_it, "D_LENGTH")

  if USER_RESTORE_MODE == "timesel" then
    -- Collect all items on FX track that overlap the placeholder span
    move_list = collect_preview_items_on_fx_track(ASP._state.fx_track, ph_it, UL, UR)
    ASP.log("restore-mode=timesel: collected %d item(s) on FX track by placeholder span", #move_list)
    -- sanity check: if returning more items than originally moved out for this preview, abort
    local moved_out = tonumber(ASP._state.moved_count or 0) or 0
    ASP.log("preflight: timesel count check; moved_out=%d  to_move_back=%d", moved_out, #move_list)
    if #move_list > moved_out then
      reaper.MB(
        "Move-back aborted: returning items exceed the original count for this time selection.\n\n" ..
        "Tip: adjust the time selection, or use GUID restore mode (restore_mode=\"guid\") to return only the previewed items, then try again.",
        "AudioSweet Preview — Count mismatch",
        0
      )
      ASP.log("move-back aborted due to count mismatch in timesel restore (to_move_back > moved_out)")
      return
    end
  else
    -- Default: only the ones we moved during this preview session
    for i=1, #(ASP._state.moved_items or {}) do
      local it = ASP._state.moved_items[i]
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        table.insert(move_list, it)
      end
    end
    ASP.log("restore-mode=guid: prepared %d item(s) to move back", #move_list)
  end

  -- Perform the move-back (no overlap policing)
  for _, it in ipairs(move_list) do
    reaper.MoveMediaItemToTrack(it, ph_tr)
  end

  -- ★ Restore source track channel count (protect from REAPER auto-adjust)
  if ASP._state.src_track_nchan and ph_tr then
    reaper.SetMediaTrackInfo_Value(ph_tr, "I_NCHAN", ASP._state.src_track_nchan)
    ASP.log("restored source track I_NCHAN to %d", ASP._state.src_track_nchan)
    ASP._state.src_track_nchan = nil
  end

  remove_placeholder(ph_it)
  ASP._state.placeholder = nil
  ASP._state.moved_items = {}
  ASP.log("moved %d item(s) back & removed placeholder", #move_list)
end

function ASP._select_items(list, exclusive)
  if exclusive then reaper.Main_OnCommand(40289, 0) end -- Unselect all
  for _,it in ipairs(list or {}) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
  reaper.UpdateArrange()
end

function ASP._apply_mode_flags(mode)
  -- Wrap the entire section to avoid fragmented Undo operations
  undo_begin()

  local scope = read_solo_scope()
  local FXtr  = ASP._state.fx_track

  -- Always clear first: reset item-solo and track-solo
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  if mode == "solo" then
    if scope == "track" then
      if FXtr then
        reaper.SetMediaTrackInfo_Value(FXtr, "I_SOLO", 1)
        ASP.log("solo TRACK scope: FX track solo ON")
      end
      ASP._select_items(ASP._state.moved_items, true)
    else
      ASP._select_items(ASP._state.moved_items, true)
      reaper.Main_OnCommand(41558, 0) -- Item: Solo exclusive
      ASP.log("solo ITEM scope: item-solo-exclusive ON")
    end
  else
    ASP._select_items(ASP._state.moved_items, true)
    ASP.log("normal mode: solo cleared (items & tracks)")
  end

  reaper.Main_OnCommand(1007, 0) -- Transport: Play

  undo_end_no_undo("AS Preview: apply mode flags (no undo)")
end

----------------------------------------------------------------
-- Public: stop preview from a fresh script instance
-- Bootstraps state from placeholder + ExtState, then cleans up.
----------------------------------------------------------------
function ASP.stop_preview(opts)
  opts = opts or {}

  -- Respect caller's restore_mode setting (read from GUI ExtState)
  if opts.restore_mode then
    USER_RESTORE_MODE = (opts.restore_mode == "timesel") and "timesel" or "guid"
  end

  -- 1. Stop transport
  if (reaper.GetPlayState() & 1) == 1 then
    reaper.Main_OnCommand(1016, 0)  -- Transport: Stop
  end

  -- 2. Find FX track via saved GUID
  local fx_guid = reaper.GetExtState(ASP.ES_NS, ASP.ES_FX_GUID)
  local fx_track = nil
  if fx_guid and fx_guid ~= "" then
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      if reaper.GetTrackGUID(tr) == fx_guid then
        fx_track = tr
        break
      end
    end
  end

  -- 3. Find placeholder on any track
  local src_tr, ph_item, UL, UR
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local ph, pUL, pUR = find_placeholder_on_track(tr)
    if ph then
      src_tr = tr
      ph_item = ph
      UL = pUL
      UR = pUR
      break
    end
  end

  if not ph_item then
    -- No placeholder: just clear flags (stale PREVIEW_RUN)
    _set_run_flag(false)
    reaper.SetExtState(ASP.ES_NS, ASP.ES_FX_GUID, "", false)
    write_state({running=false, mode=""})
    return
  end

  -- 4. Bootstrap state for cleanup
  ASP._state.running       = true
  ASP._state.placeholder   = ph_item
  ASP._state.src_track     = src_tr
  ASP._state.fx_track      = fx_track
  ASP._state.moved_items   = fx_track
    and collect_preview_items_on_fx_track(fx_track, ph_item, UL, UR)
    or {}
  ASP._state.moved_count   = #ASP._state.moved_items  -- match timesel count check
  -- These snapshots are lost across instances; set safe defaults
  ASP._state.fx_enable_shot  = nil  -- skip FX enable restore
  ASP._state.track_nchan     = nil  -- skip channel count restore
  ASP._state.src_track_nchan = nil
  ASP._state.selection_cache = nil  -- skip selection restore
  -- Keep repeat as-is (no-op in _restore_repeat)
  ASP._state.repeat_was_on = (reaper.GetToggleCommandState(1068) == 1)

  ASP.log("stop_preview: bootstrapped from placeholder (items=%d)", #ASP._state.moved_items)

  -- 5. Run the standard cleanup
  ASP.cleanup_if_any()
end


return ASP
