--[[
@description Hover_Mode_-_Trim_or_Extend_Left_Edge_of_Item (Preserve Fade End, No Flicker)
@version 0.3.1
@author hsuanice
@about
  Left-edge trim/extend that preserves the fade-in END (not the length), using a shared Hover library
  for position & target selection. Implements a no-flicker write order:
    • compute new fade-in length (keep end),
    • clear D_FADEINLEN_AUTO,
    • write take start offset → item start → item length → fade-in length,
    • then force a redraw.

  Behavior summary:
    • True Hover (mouse over arrange, not Ruler/TCP):
        - library decides trim vs extend (boundary-as-gap).
        - selection-first when Hover is ON (per library).
        - NEW in 0.3.1: When there is NO selection and mouse is on a GAP,
          also extend the next item on the mouse track (nearest start ≥ position).
    • Non-hover (Ruler/TCP or Hover OFF):
        - Edit Cursor + selected tracks fallback:
            inside → trim; else extend nearest item to the right.
    • Snap only in true hover (per library).

  Fade policy:
    • Preserve fade-in END. If original fade-in = 0, stays 0.
    • Clear D_FADEINLEN_AUTO to avoid transient auto-fade visuals.
    • Fade shape is not modified.

  Library path:
    REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua

@changelog
  v0.3.1
    - True Hover: when there is NO selection and the mouse is over a GAP, also extend the next item on the mouse track.
  v0.3.0
    - Switched to hsuanice_Hover.lua for position/targets/snap.
    - Added DEBUG option; no-flicker write order with D_FADEINLEN_AUTO cleared; preserves fade-in END.
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
local function log(s)   if DEBUG then reaper.ShowConsoleMsg(tostring(s).."\n") end end
local function logf(f, ...) if DEBUG then reaper.ShowConsoleMsg(string.format(f, ...).."\n") end end
if DEBUG and CLEAR_ON_RUN then reaper.ShowConsoleMsg("") end
log("[LeftEdge] --- run ---")

----------------------------------------
-- Helpers
----------------------------------------

-- Build picks in Edit-Cursor mode on selected tracks:
-- per track: if inside → trim; else extend nearest start >= pos
local function collect_picks_edit_mode(pos)
  local picks = {}
  local eps = hover.half_pixel_sec()

  -- gather selected tracks
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

-- NEW in 0.3.1:
-- If true hover, NO selection, and mouse is over a GAP (library returned empty),
-- find the next item on the mouse TRACK (nearest start >= pos) and extend it.
local function picks_extend_from_gap_on_mouse_track(pos)
  local picks = {}
  if not reaper.BR_GetMouseCursorContext then
    return picks
  end
  local window, segment = reaper.BR_GetMouseCursorContext()
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

-- Apply left-edge trim/extend preserving fade-in END, with no flicker.
-- One-shot write order inside PreventUIRefresh:
--   1) compute new fade-in length (keep end time)
--   2) Set D_FADEINLEN_AUTO=0 (avoid transient auto-fade)
--   3) Set take D_STARTOFFS (audio only) → item D_POSITION → item D_LENGTH → item D_FADEINLEN
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
  local is_empty = (take == nil)
  local is_midi  = (take and reaper.TakeIsMIDI(take)) or false
  local is_audio = (take and (not is_midi)) or false

  -- clamp new start by source offset (no negative start in source)
  local new_st
  if entry.mode == "trim" then
    new_st = math.min(target_pos, en - 1e-9)
  else -- "extend"
    new_st = target_pos
  end

  if is_audio then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    if rate <= 0 then rate = 1.0 end
    -- minimal start allowed without making source offset negative:
    local min_st = st - (offs / rate)
    if new_st < min_st then new_st = min_st end
  end

  -- no-op?
  if math.abs(new_st - st) < 1e-12 then
    log("[LeftEdge] no-op: start unchanged"); return
  end

  local new_ln = en - new_st

  -- Compute fade-in END preservation
  local old_fi = reaper.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0
  local fade_end = st + math.max(0, old_fi)  -- absolute time of fade-in end
  local new_fi = 0
  if old_fi > 0 then
    new_fi = math.max(0, fade_end - new_st)
  else
    new_fi = 0
  end

  -- Write (no flicker): clear auto first, then offsets → pos → len → fade
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0) -- avoid transient auto-fade drawing

  if is_audio then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    if rate <= 0 then rate = 1.0 end
    local new_offs = offs + (new_st - st) * rate
    if new_offs < 0 then new_offs = 0 end  -- clamp
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offs)
  end

  reaper.SetMediaItemInfo_Value(it, "D_POSITION", new_st)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",  new_ln)
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

  -- 2.1) NEW in 0.3.1:
  -- If TRUE HOVER, NO selection, and library returned nothing (likely mouse on a GAP),
  -- also extend next item on the MOUSE TRACK.
  if is_true_hover and (#picks == 0) and (reaper.CountSelectedMediaItems(0) == 0) then
    local extra = picks_extend_from_gap_on_mouse_track(pos)
    for i = 1, #extra do picks[#picks+1] = extra[i] end
    logf("[LeftEdge] added gap-extend pick(s): %d", #extra)
  end

  -- 2.2) Non-hover fallback: Edit Cursor + Selected Tracks
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
