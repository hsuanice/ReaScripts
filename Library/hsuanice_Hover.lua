--[[
@description hsuanice Hover Library (Shared helpers for Hover Mode editing tools)
@version 250926_1610 update start in source to all takes
@author hsuanice
@about
  Common utilities for Hover Mode scripts (Split / Trim / Extend).
  Centralizes hover/edit cursor decision, snap behavior, pixel epsilon,
  target selection (hover, edit, or selection priority), and write helpers.

  This version keeps full backward compatibility with v0.1.0:
    • resolve_target_pos / snap_in_true_hover
    • half_pixel_sec / is_item_visible
    • build_targets_for_split / build_targets_for_trim_extend
  …and adds a comprehensive set of high/mid/low ROI helpers (see changelog).

  Path: REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua
@changelog
  v250926_1610
    • Left-edge edits propagate SrcStart (D_STARTOFFS) delta to all takes (matches REAPER prefs behavior).
  v0.2.0
    HIGH ROI
      • selection_sync_enabled(is_true_hover, min)  → bool, sel_count
      • filter_leftmost_selected_per_track(picks)   → picks (left only)
      • filter_rightmost_selected_per_track(picks)  → picks (right only)
      • pick_on_gap(side, pos)                      → { {item=…, mode="extend"} } from mouse track
      • clamp_left_extend_no_overlap(item, new_st, eps)  → clamped start
      • clamp_right_extend_no_overlap(item, new_en, eps) → clamped end
      • apply_left_edge_no_flicker(item, target_pos)     (preserve fade-in END, audio offset, no flicker)
      • apply_right_edge_no_flicker(item, target_pos)    (preserve fade-out START, no flicker)
      • collect_edit_mode_picks(side, pos)          → picks for non-hover (Edit Cursor + selected tracks)

    MID ROI
      • ts_overlap_stats(ts_start, ts_end, items_opt) → {overlaps, boundary_hits, edges_only, list}
      • run_split_by_time_selection(overlapped_items) → do 40061 + reselect overlapped
      • log / logf with library-level toggle: set_debug(true/false)
      • eps() alias to half_pixel_sec()

    LOW ROI
      • save_item_selection() / restore_item_selection(list)
      • build_selected_items_split_info(pos, eps) & select_right_halves_after_split(split_info, pos, eps)
      • add_hover_item_outside_selection_crossing(targets, pos, eps)  (for split “hover also”)
--]]

local M = {}

----------------------------------------
-- Config / Debug
----------------------------------------
M.EXT_NS        = "hsuanice_TrimTools"
M.EXT_HOVER_KEY = "HoverMode"
M.DEBUG         = true

function M.set_debug(on) M.DEBUG = not not on end
local function LOG(s)  if M.DEBUG then reaper.ShowConsoleMsg(tostring(s).."\n") end end
local function LOGF(f, ...) if M.DEBUG then reaper.ShowConsoleMsg(string.format(f, ...).."\n") end end

----------------------------------------
-- Basic state & geometry
----------------------------------------

-- Check if Hover Mode is enabled via ExtState
function M.is_hover_enabled()
  local v = reaper.GetExtState(M.EXT_NS, M.EXT_HOVER_KEY)
  return (v == "true" or v == "1")
end

-- Check if mouse is over Ruler or TCP (forces Edit Cursor mode)
function M.is_mouse_over_ruler_or_tcp()
  if not reaper.JS_Window_FromPoint then return false end
  local x, y = reaper.GetMousePosition()
  local hwnd = reaper.JS_Window_FromPoint(x, y)
  if not hwnd then return false end
  local class = reaper.JS_Window_GetClassName(hwnd)
  -- Classes may vary per REAPER build/theme; keep conservative
  return (class == "REAPERTimeDisplay" or class == "REAPERTCPDisplay" or class == "REAPERTimeline")
end

-- Timeline position under mouse (SWS preferred)
function M.mouse_timeline_pos()
  if reaper.BR_GetMouseCursorContext_Position then
    reaper.BR_GetMouseCursorContext()
    return reaper.BR_GetMouseCursorContext_Position()
  end
  if reaper.BR_PositionAtMouseCursor then
    return reaper.BR_PositionAtMouseCursor(true)
  end
  return nil
end

-- Half pixel in seconds (zoom adaptive)
function M.half_pixel_sec()
  local pps = reaper.GetHZoomLevel() or 100.0
  if pps <= 0 then pps = 100.0 end
  return 0.5 / pps
end
function M.eps() return M.half_pixel_sec() end

-- Check if item is visible in arrange view (partial ok)
function M.is_item_visible(item)
  local st = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local en = st + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local v0, v1 = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  return (en >= v0 and st <= v1)
end

----------------------------------------
-- Position resolution & snap
----------------------------------------

-- Decide working position (pos, is_true_hover)
-- • Hover ON + not ruler/tcp → mouse pos
-- • Else → edit cursor
function M.resolve_target_pos()
  if M.is_hover_enabled() and not M.is_mouse_over_ruler_or_tcp() then
    local pos = M.mouse_timeline_pos()
    return pos, true
  else
    return reaper.GetCursorPosition(), false
  end
end

-- Apply snap only in true hover mode
function M.snap_in_true_hover(pos, is_true_hover)
  if is_true_hover and reaper.GetToggleCommandState(1157) == 1 then
    return reaper.SnapToGrid(0, pos)
  end
  return pos
end

----------------------------------------
-- Selection-sync helpers (HIGH ROI)
----------------------------------------

-- Returns: prefer_selection (bool), sel_count (int)
function M.selection_sync_enabled(is_true_hover, min_threshold)
  local sel = reaper.CountSelectedMediaItems(0)
  local ok = is_true_hover and (sel >= (min_threshold or 2))
  return ok, sel
end

-- Map helpers for per-track extremums
local function _map_leftmost_selected_start_by_track()
  local e = M.eps()
  local m = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = reaper.GetMediaItemTrack(it)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local cur = m[tr]
    if (not cur) or (st < cur.st - e) then m[tr] = { st = st, it = it } end
  end
  return m
end

local function _map_rightmost_selected_end_by_track()
  local e = M.eps()
  local m = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = reaper.GetMediaItemTrack(it)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local cur = m[tr]
    if (not cur) or (en > cur.en + e) then m[tr] = { en = en, it = it } end
  end
  return m
end

-- Filter picks: keep ONLY leftmost selected per track
function M.filter_leftmost_selected_per_track(picks)
  if reaper.CountSelectedMediaItems(0) == 0 then return picks end
  local e = M.eps()
  local leftmost = _map_leftmost_selected_start_by_track()
  local out = {}
  for _, p in ipairs(picks) do
    local it = p.item
    if reaper.IsMediaItemSelected(it) then
      local tr  = reaper.GetMediaItemTrack(it)
      local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local lm  = leftmost[tr]
      if lm and math.abs(st - lm.st) <= e then
        out[#out+1] = p
      else
        LOGF("[HoverLib] drop (not leftmost): start=%.6f", st)
      end
    else
      LOG("[HoverLib] drop (not selected) while selection present")
    end
  end
  LOGF("[HoverLib] leftmost-filter picks: %d → %d", #picks, #out)
  return out
end

-- Filter picks: keep ONLY rightmost selected per track
function M.filter_rightmost_selected_per_track(picks)
  if reaper.CountSelectedMediaItems(0) == 0 then return picks end
  local e = M.eps()
  local rightmost = _map_rightmost_selected_end_by_track()
  local out = {}
  for _, p in ipairs(picks) do
    local it = p.item
    if reaper.IsMediaItemSelected(it) then
      local tr  = reaper.GetMediaItemTrack(it)
      local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en  = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local rm  = rightmost[tr]
      if rm and math.abs(en - rm.en) <= e then
        out[#out+1] = p
      else
        LOGF("[HoverLib] drop (not rightmost): end=%.6f", en)
      end
    else
      LOG("[HoverLib] drop (not selected) while selection present")
    end
  end
  LOGF("[HoverLib] rightmost-filter picks: %d → %d", #picks, #out)
  return out
end

----------------------------------------
-- Gap fallback from mouse track (HIGH ROI)
----------------------------------------

-- side ∈ { "left", "right" }
-- returns picks (0..1) with {item=…, mode="extend"}
function M.pick_on_gap(side, pos)
  local picks = {}
  if not reaper.BR_GetMouseCursorContext then return picks end
  if reaper.BR_GetMouseCursorContext() ~= "arrange" then return picks end
  local tr = reaper.BR_GetMouseCursorContext_Track()
  if not tr then return picks end

  local e = M.eps()
  if side == "left" then
    -- extend next on mouse track (start ≥ pos)
    local target, best_st = nil, math.huge
    local n = reaper.CountTrackMediaItems(tr)
    for i = 0, n - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      if st >= pos - e and st < best_st then target, best_st = it, st end
    end
    if target then picks[1] = { item = target, mode = "extend" } end
  else
    -- right: extend prev on mouse track (end ≤ pos)
    local target, best_en = nil, -math.huge
    local n = reaper.CountTrackMediaItems(tr)
    for i = 0, n - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if en <= pos + e and en > best_en then target, best_en = it, en end
    end
    if target then picks[1] = { item = target, mode = "extend" } end
  end
  return picks
end

----------------------------------------
-- Overlap clamp (HIGH ROI)
----------------------------------------

-- previous item end on same track (strictly left of 'it'); returns -inf when none
local function _prev_item_end_on_track(it)
  local tr = reaper.GetMediaItemTrack(it)
  local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local best = -math.huge
  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n - 1 do
    local jt = reaper.GetTrackMediaItem(tr, i)
    if jt ~= it then
      local js = reaper.GetMediaItemInfo_Value(jt, "D_POSITION")
      local je = js + reaper.GetMediaItemInfo_Value(jt, "D_LENGTH")
      if je <= st and je > best then best = je end
    end
  end
  return best
end

-- next item start on same track (strictly right of 'it'); returns +inf when none
local function _next_item_start_on_track(it)
  local tr = reaper.GetMediaItemTrack(it)
  local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local best = math.huge
  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n - 1 do
    local jt = reaper.GetTrackMediaItem(tr, i)
    if jt ~= it then
      local js = reaper.GetMediaItemInfo_Value(jt, "D_POSITION")
      if js > st and js < best then best = js end
    end
  end
  return best
end

function M.clamp_left_extend_no_overlap(it, new_st, eps)
  local e = eps or M.eps()
  local prev_end = _prev_item_end_on_track(it)
  if prev_end > -math.huge then
    local lim = prev_end + e
    if new_st < lim then new_st = lim end
  end
  return new_st
end

function M.clamp_right_extend_no_overlap(it, new_en, eps)
  local e = eps or M.eps()
  local next_start = _next_item_start_on_track(it)
  if next_start < math.huge then
    local lim = next_start - e
    if new_en > lim then new_en = lim end
  end
  return new_en
end

----------------------------------------
-- Start-offset sync across takes (HIGH ROI)
----------------------------------------

-- Shift D_STARTOFFS for all non-MIDI takes in an item by delta timeline seconds.
-- Each take uses its own playrate for correct conversion.
local function _shift_all_takes_start_offset(item, delta_pos)
  if not item or delta_pos == 0 then return end
  local nt = reaper.CountTakes(item)
  local guid = reaper.BR_GetMediaItemGUID and reaper.BR_GetMediaItemGUID(item) or tostring(item)
  LOGF("[HoverLib] shift_all_takes: item=%s  delta_pos=%.9f  takes=%d", guid, delta_pos, nt)
  for i = 0, nt - 1 do
    local tk = reaper.GetTake(item, i)
    if tk and not reaper.TakeIsMIDI(tk) then
      local rate = reaper.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1.0
      if rate <= 0 then rate = 1.0 end
      local offs = reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0.0
      local src  = reaper.GetMediaItemTake_Source(tk)
      local src_len, isQN = reaper.GetMediaSourceLength(src)
      if isQN then src_len = reaper.TimeMap_QNToTime(src_len) end
      local new_offs = offs + delta_pos * rate
      if new_offs < 0 then new_offs = 0 end
      if src_len and src_len > 0 and new_offs > src_len then new_offs = src_len end
      LOGF("[HoverLib]   take#%d rate=%.6f offs_old=%.9f -> offs_new=%.9f src_len=%.9f", i+1, rate, offs, new_offs, src_len or -1)
      reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", new_offs)
    end
  end
end

----------------------------------------
-- No-flicker edge apply (HIGH ROI)
----------------------------------------

-- Audio right-end limit (non-loop)
local function _max_right_end_audio(it, take)
  local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  if rate <= 0 then rate = 1.0 end
  local src = reaper.GetMediaItemTake_Source(take)
  local src_len, isQN = reaper.GetMediaSourceLength(src)
  if isQN then src_len = reaper.TimeMap_QNToTime(src_len) end
  local tail = math.max(0, (src_len - offs) / rate)
  return st + tail
end

-- Left edge: preserve fade-in END; update audio offset; no flicker
function M.apply_left_edge_no_flicker(it, target_pos)
  if not M.is_item_visible(it) then return end
  local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local ln = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local en = st + ln
  if target_pos >= en - 1e-9 then return end

  local take = reaper.GetActiveTake(it)
  local is_midi  = (take and reaper.TakeIsMIDI(take)) or false
  local is_audio = (take and (not is_midi)) or false
  local e = M.eps()

  local new_st = target_pos
  -- clamp overlap when extending
  if target_pos < st then new_st = M.clamp_left_extend_no_overlap(it, target_pos, e) end

  -- source offset clamp (audio)
  if is_audio then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    if rate <= 0 then rate = 1.0 end
    local min_st = st - (offs / rate)
    if new_st < min_st then new_st = min_st end
  end

  LOGF("[HoverLib] left-edge: st=%.9f target=%.9f -> new_st=%.9f", st, target_pos, new_st)
  if math.abs(new_st - st) < 1e-12 then return end
  local new_ln = en - new_st

  local old_fi  = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0
  local fade_end = st + math.max(0, old_fi)
  local new_fi  = (old_fi > 0) and math.max(0, fade_end - new_st) or 0

  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0)
  local delta_pos = new_st - st
  LOGF("[HoverLib] left-edge: delta_pos=%.9f (seconds)", delta_pos)
  if delta_pos ~= 0 then
    _shift_all_takes_start_offset(it, delta_pos)
  end
  reaper.SetMediaItemInfo_Value(it, "D_POSITION",  new_st)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",    new_ln)
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", new_fi)
  LOGF("[HoverLib] left-edge: applied pos=%.9f len=%.9f fade_in=%.9f", new_st, new_ln, new_fi)
end

-- Right edge: preserve fade-out START; clamp no-overlap & audio tail; no flicker
function M.apply_right_edge_no_flicker(it, target_pos)
  if not M.is_item_visible(it) then return end
  local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local ln  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local en0 = st + ln
  local e   = M.eps()

  local take = reaper.GetActiveTake(it)
  local is_midi  = (take and reaper.TakeIsMIDI(take)) or false
  local is_audio = (take and (not is_midi)) or false
  local loopsrc  = (reaper.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 1)

  local desired = target_pos
  -- clamp no-overlap when extending
  if target_pos > en0 then desired = M.clamp_right_extend_no_overlap(it, target_pos, e) end
  -- clamp to audio tail (non-loop)
  if is_audio and (not loopsrc) and desired > en0 then
    local max_tail = _max_right_end_audio(it, take)
    if desired > max_tail then desired = max_tail end
  end

  if desired <= st + 1e-9 then desired = st + 1e-9 end
  if math.abs(desired - en0) < 1e-9 then return end
  local new_ln = desired - st

  local old_fo = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0
  local fade_start = en0 - math.max(0, old_fo)
  local new_fo = (old_fo > 0) and math.max(0, desired - fade_start) or 0

  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", 0)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", new_ln)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", new_fo)
end

----------------------------------------
-- Edit-mode picks (HIGH ROI)
----------------------------------------

-- side ∈ { "left", "right" }
-- returns array of { item=…, mode="trim|extend" } on selected tracks
function M.collect_edit_mode_picks(side, pos)
  local picks, e = {}, M.eps()
  local tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    tracks[#tracks+1] = reaper.GetSelectedTrack(0, i)
  end
  for _, tr in ipairs(tracks) do
    local inside, candidate = nil, nil
    local best_right, best_left_end = math.huge, -math.huge
    local n = reaper.CountTrackMediaItems(tr)
    for j = 0, n - 1 do
      local it = reaper.GetTrackMediaItem(tr, j)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local inside_open = (pos > st + e and pos < en - e)
      if inside_open then
        inside = it; break
      end
      if side == "left" then
        if st >= pos and st < best_right then candidate, best_right = it, st end
      else
        if en <= pos and en > best_left_end then candidate, best_left_end = it, en end
      end
    end
    if inside then
      picks[#picks+1] = { item = inside, mode = "trim" }
    elseif candidate then
      picks[#picks+1] = { item = candidate, mode = "extend" }
    end
  end
  return picks
end

----------------------------------------
-- Split helpers (MID/LOW ROI)
----------------------------------------

-- TS stats for selected items; items_opt overrides current selection if provided
function M.ts_overlap_stats(ts_start, ts_end, items_opt)
  if not ts_start or not ts_end then
    ts_start, ts_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  end
  local list = {}
  if items_opt then
    for _, it in ipairs(items_opt) do list[#list+1] = it end
  else
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      list[#list+1] = reaper.GetSelectedMediaItem(0, i)
    end
  end

  local overlaps, boundary_hits, edges_only = 0, 0, 0
  for _, it in ipairs(list) do
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if en > ts_start and st < ts_end then
      overlaps = overlaps + 1
      local hit_start = (st < ts_start and en > ts_start)
      local hit_end   = (st < ts_end   and en > ts_end)
      if hit_start or hit_end then boundary_hits = boundary_hits + 1
      else edges_only = edges_only + 1 end
    end
  end
  return { overlaps = overlaps, boundary_hits = boundary_hits, edges_only = edges_only, list = list }
end

-- Execute 40061 and reselect the 'overlapped' list; returns true if executed
function M.run_split_by_time_selection(overlapped_items)
  if not overlapped_items or #overlapped_items == 0 then return false end
  reaper.Main_OnCommand(40061, 0) -- Split at time selection
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  for _, it in ipairs(overlapped_items) do
    if reaper.ValidatePtr(it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
  return true
end

-- Selection save/restore (LOW ROI)
function M.save_item_selection()
  local list = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    list[#list+1] = reaper.GetSelectedMediaItem(0, i)
  end
  return list
end
function M.restore_item_selection(list)
  reaper.Main_OnCommand(40289, 0)
  for _, it in ipairs(list or {}) do
    if reaper.ValidatePtr(it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end

-- For split: record selected items that will be split (so we can reselect right halves later)
function M.build_selected_items_split_info(pos, eps)
  local info, e = {}, (eps or M.eps())
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en  = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos > st + e and pos < en - e then
      info[#info+1] = { track = reaper.GetMediaItemTrack(it), old_end = en }
    end
  end
  return info
end

function M.select_right_halves_after_split(split_info, pos, eps)
  local e = (eps or M.eps()) * 2
  for _, s in ipairs(split_info or {}) do
    local tr = s.track
    local old_end = s.old_end
    if reaper.ValidatePtr(tr, "MediaTrack*") then
      local n = reaper.CountTrackMediaItems(tr)
      for i = 0, n - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if math.abs(st - pos) <= e and math.abs(en - old_end) <= e then
          reaper.SetMediaItemSelected(it, true)
          break
        end
      end
    end
  end
end

-- For split: if hovered item is OUTSIDE selection but crosses pos, include it
function M.add_hover_item_outside_selection_crossing(targets, pos, eps)
  local x, y = reaper.GetMousePosition()
  local hit  = reaper.GetItemFromPoint(x, y, false)
  if not hit or reaper.IsMediaItemSelected(hit) then return false end
  local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
  local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
  local e  = eps or M.eps()
  if not (pos > st + e and pos < en - e) then return false end
  for _, it in ipairs(targets) do if it == hit then return false end end
  table.insert(targets, hit)
  return true
end

----------------------------------------
-- Target builders (BACKWARD-COMPAT)
----------------------------------------

-- Build target items for Split
--   opts: { prefer_selection_when_hover=true }
function M.build_targets_for_split(pos, opts)
  local items = {}
  local e = M.eps()
  local prefer_sel = opts and opts.prefer_selection_when_hover

  if prefer_sel and reaper.CountSelectedMediaItems(0) > 0 and M.is_hover_enabled() then
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local it = reaper.GetSelectedMediaItem(0, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if pos > st + e and pos < en - e then items[#items+1] = it end
    end
  else
    local x, y = reaper.GetMousePosition()
    local hit = reaper.GetItemFromPoint(x, y, false)
    if hit then
      local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
      if pos > st + e and pos < en - e then items[#items+1] = hit end
    end
  end
  return items
end

-- Build picks for Trim/Extend
--   side = "left" or "right"
--   returns { {item=..., mode="trim|extend"}, ... }
function M.build_targets_for_trim_extend(side, pos, opts)
  local picks = {}
  local e = M.eps()
  local prefer_sel = opts and opts.prefer_selection_when_hover

  if prefer_sel and reaper.CountSelectedMediaItems(0) > 0 and M.is_hover_enabled() then
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local it = reaper.GetSelectedMediaItem(0, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local inside = (pos > st + e and pos < en - e)
      if side == "left" then
        if inside then picks[#picks+1] = { item = it, mode = "trim" }
        elseif st >= pos then picks[#picks+1] = { item = it, mode = "extend" } end
      else
        if inside then picks[#picks+1] = { item = it, mode = "trim" }
        elseif en <= pos then picks[#picks+1] = { item = it, mode = "extend" } end
      end
    end
  else
    local x, y = reaper.GetMousePosition()
    local hit = reaper.GetItemFromPoint(x, y, false)
    if hit then
      local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
      local inside = (pos > st + e and pos < en - e)
      if inside then
        picks[#picks+1] = { item = hit, mode = "trim" }
      elseif side == "left" and st >= pos then
        picks[#picks+1] = { item = hit, mode = "extend" }
      elseif side == "right" and en <= pos then
        picks[#picks+1] = { item = hit, mode = "extend" }
      end
    end
  end
  return picks
end

----------------------------------------
return M
