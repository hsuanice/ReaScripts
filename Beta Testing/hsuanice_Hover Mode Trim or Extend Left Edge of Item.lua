--[[
@description Hover_Mode_-_Trim_or_Extend_Left_Edge_of_Item (Preserve Fade End, No Flicker)
@version 0.3.2 overlap fixed
@author hsuanice
@about
  Left-edge trim/extend that preserves the fade-in END (not the length), using a shared Hover library
  for position & target selection. No-flicker write order and no-overlap extends.

  Behavior summary:
    • True Hover (mouse over arrange, not Ruler/TCP):
        - selection-first via library.
        - NEW: When there IS selection, only process the LEFTMOST selected item per track
          (ignore middle/right selected items to avoid extend-overlap).
        - When there is NO selection and mouse is on a GAP, extend the next item on the mouse track.
    • Non-hover (Ruler/TCP or Hover OFF):
        - Edit Cursor + selected tracks fallback: inside → trim; else extend nearest item to the right.
    • Snap only in true hover (per library).

  Fade policy:
    • Preserve fade-in END. If original fade-in = 0, stays 0.
    • Clear D_FADEINLEN_AUTO to avoid transient auto-fade visuals.
    • Fade shape is not modified.

  Library path:
    REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua

@changelog
  v0.3.2
    - True Hover + selection: only process the LEFTMOST selected item on each track (skip others).
    - Extend now clamps to previous item end + epsilon on the same track (no overlap).
  v0.3.1
    - No-selection + gap on mouse track → extend next item on that track.
  v0.3.0
    - Library integration, DEBUG switch, no-flicker write order, preserve fade END.
--]]

----------------------------------------
-- USER OPTIONS
----------------------------------------
local DEBUG        = false  -- ← set true to print debug logs to ReaScript console
local CLEAR_ON_RUN = false  -- ← set true to clear console on each run when DEBUG=true

----------------------------------------
-- Load shared Hover library
----------------------------------------
local LIB_PATH = reaper.GetResourcePath().."/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua"
local ok, hover = pcall(dofile, LIB_PATH)
if not ok or type(hover) ~= "table" then
  reaper.ShowMessageBox("Missing or invalid library:\n"..LIB_PATH..
    "\n\nPlease install hsuanice_Hover.lua v0.1.0+.", "hsuanice Hover Library", 0)
  return
end

----------------------------------------
-- Debug helpers
----------------------------------------
local function log(s)              if DEBUG then reaper.ShowConsoleMsg(tostring(s).."\n") end end
local function logf(f, ...)        if DEBUG then reaper.ShowConsoleMsg(string.format(f, ...).."\n") end end
if DEBUG and CLEAR_ON_RUN then reaper.ShowConsoleMsg("") end
log("[LeftEdge] --- run ---")

----------------------------------------
-- Helpers
----------------------------------------

-- Non-hover fallback: per selected track, inside→trim; else extend nearest start >= pos
local function collect_picks_edit_mode(pos)
  local picks, eps = {}, hover.half_pixel_sec()

  local tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    tracks[#tracks+1] = reaper.GetSelectedTrack(0, i)
  end

  for _, tr in ipairs(tracks) do
    local inside, extend_target = nil, nil
    local best_right = math.huge

    local n = reaper.CountTrackMediaItems(tr)
    for i = 0, n - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local inside_open = (pos > st + eps and pos < en - eps)

      if inside_open then
        inside = it; break
      elseif st >= pos and st < best_right then
        extend_target = it; best_right = st
      end
    end

    if inside then
      table.insert(picks, { item = inside, mode = "trim" })
    elseif extend_target then
      table.insert(picks, { item = extend_target, mode = "extend" })
    end
  end

  logf("[LeftEdge] collect_picks_edit_mode: pos=%.6f, picks=%d", pos, #picks)
  return picks
end

-- When true hover & NO selection & library returned nothing (likely on a GAP),
-- extend the next item on the mouse TRACK.
local function picks_extend_from_gap_on_mouse_track(pos)
  local picks = {}
  if not reaper.BR_GetMouseCursorContext then return picks end
  local window = reaper.BR_GetMouseCursorContext()
  if window ~= "arrange" then return picks end
  local tr = reaper.BR_GetMouseCursorContext_Track()
  if not tr then return picks end

  local eps = hover.half_pixel_sec()
  local target, best_st = nil, math.huge
  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    if st >= pos - eps and st < best_st then
      target, best_st = it, st
    end
  end
  if target then
    table.insert(picks, { item = target, mode = "extend" })
    logf("[LeftEdge] gap→extend on mouse track: pick start=%.6f", best_st)
  else
    log("[LeftEdge] gap→extend on mouse track: no item to the right")
  end
  return picks
end

-- Build a map: track -> earliest (leftmost) selected item start time
local function map_leftmost_selected_start_by_track()
  local eps = hover.half_pixel_sec()
  local m = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = reaper.GetMediaItemTrack(it)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local cur = m[tr]
    if (not cur) or (st < cur.st - eps) then
      m[tr] = { st = st, it = it }
    end
  end
  return m
end

-- Filter: in true hover & selection present → keep ONLY leftmost selected item on each track
local function filter_picks_leftmost_selected_per_track(picks)
  if reaper.CountSelectedMediaItems(0) == 0 then return picks end
  local eps = hover.half_pixel_sec()
  local leftmost = map_leftmost_selected_start_by_track()
  local out = {}
  for _, e in ipairs(picks) do
    local it  = e.item
    if reaper.IsMediaItemSelected(it) then
      local tr  = reaper.GetMediaItemTrack(it)
      local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local lm  = leftmost[tr]
      if lm and math.abs(st - lm.st) <= eps then
        out[#out+1] = e
      else
        logf("[LeftEdge] drop (not leftmost on track): start=%.6f", st)
      end
    else
      log("[LeftEdge] drop (not selected) while selection present")
    end
  end
  logf("[LeftEdge] leftmost-filter picks: %d → %d", #picks, #out)
  return out
end

-- Find previous item's END on the same track (strictly to the left of 'it')
local function prev_item_end_on_track(it)
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

-- Apply left-edge trim/extend preserving fade-in END, with no flicker & no overlap.
local function apply_left_edge(entry, target_pos)
  local it = entry.item
  if not hover.is_item_visible(it) then
    log("[LeftEdge] skip: item not visible"); return
  end

  local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local ln = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local en = st + ln
  if target_pos >= en - 1e-9 then
    logf("[LeftEdge] skip: target beyond end (pos=%.6f, end=%.6f)", target_pos, en)
    return
  end

  local take = reaper.GetActiveTake(it)
  local is_midi  = (take and reaper.TakeIsMIDI(take)) or false
  local is_audio = (take and (not is_midi)) or false
  local eps = hover.half_pixel_sec()

  -- Decide new start (trim/extend), with clamping to avoid overlap & negative source offset
  local new_st
  if entry.mode == "trim" then
    new_st = math.min(target_pos, en - 1e-9)
  else -- "extend"
    new_st = target_pos
    -- clamp to previous item end on same track to avoid overlap
    local prev_end = prev_item_end_on_track(it)
    if prev_end > -math.huge then
      local lim = prev_end + eps
      if new_st < lim then new_st = lim end
    end
  end

  if is_audio then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    if rate <= 0 then rate = 1.0 end
    local min_st = st - (offs / rate)
    if new_st < min_st then new_st = min_st end
  end

  if math.abs(new_st - st) < 1e-12 then
    log("[LeftEdge] no-op: start unchanged"); return
  end

  local new_ln = en - new_st

  -- Preserve fade-in END
  local old_fi  = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0
  local fade_end = st + math.max(0, old_fi)
  local new_fi  = (old_fi > 0) and math.max(0, fade_end - new_st) or 0

  -- No-flicker write order
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0)
  if is_audio then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    if rate <= 0 then rate = 1.0 end
    local new_offs = offs + (new_st - st) * rate
    if new_offs < 0 then new_offs = 0 end
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offs)
  end
  reaper.SetMediaItemInfo_Value(it, "D_POSITION",  new_st)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",    new_ln)
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN", new_fi)

  logf("[LeftEdge] %s  st:%.6f→%.6f  len:%.6f→%.6f  fi:%.6f→%.6f",
       entry.mode, st, new_st, ln, new_ln, old_fi, new_fi)
end

----------------------------------------
-- Main
----------------------------------------
local function main()
  -- 1) resolve pos + snap (snap only in true hover)
  local pos, is_true_hover = hover.resolve_target_pos()
  if not pos then log("[LeftEdge] abort: pos=nil"); return end
  local raw_pos = pos
  pos = hover.snap_in_true_hover(pos, is_true_hover)
  if is_true_hover then
    logf("[LeftEdge] TrueHover: raw=%.6f snapped=%s%.6f", raw_pos, (pos~=raw_pos and "*" or ""), pos)
  else
    logf("[LeftEdge] EditCursor: %.6f", pos)
  end

  -- 2) build picks via library
  local picks = hover.build_targets_for_trim_extend("left", pos, { prefer_selection_when_hover = true })
  logf("[LeftEdge] library picks: %d", #picks)

  -- 2.1) True Hover + selection present → keep ONLY leftmost selected item per track
  if is_true_hover and reaper.CountSelectedMediaItems(0) > 0 then
    picks = filter_picks_leftmost_selected_per_track(picks)
  end

  -- 2.2) True Hover + NO selection + nothing from library → extend next on mouse track
  if is_true_hover and (#picks == 0) and (reaper.CountSelectedMediaItems(0) == 0) then
    local extra = picks_extend_from_gap_on_mouse_track(pos)
    for i = 1, #extra do picks[#picks+1] = extra[i] end
    logf("[LeftEdge] added gap-extend pick(s): %d", #extra)
  end

  -- 2.3) Non-hover fallback: Edit Cursor + Selected Tracks
  if (not is_true_hover) and (#picks == 0) then
    picks = collect_picks_edit_mode(pos)
  end

  if #picks == 0 then log("[LeftEdge] no picks; exit"); return end

  -- 3) apply in one UI freeze to avoid flicker
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for _, entry in ipairs(picks) do
    apply_left_edge(entry, pos)
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Trim/Extend Left Edge (hover/edit aware, preserve fade end)", -1)
  log("[LeftEdge] done")
end

main()
