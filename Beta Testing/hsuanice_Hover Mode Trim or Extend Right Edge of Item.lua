--[[
@description Hover_Mode_-_Trim_or_Extend_Right_Edge_of_Item (Preserve Fade Start, No Flicker)
@version 0.3.0
@author hsuanice
@about
  Right-edge trim/extend that preserves the FADE-OUT START time (not the length), using the shared
  Hover library for position & target selection. Implements a no-flicker write order and no-overlap
  extend behavior.

  Behavior summary:
    • True Hover (mouse over arrange, not Ruler/TCP):
        - selection-first via library.
        - When there IS selection: only process the RIGHTMOST selected item per track (skip others).
        - When there is NO selection and mouse is on a GAP: extend the previous item on the mouse track
          (nearest item whose END ≤ mouse time).
        - Only strictly-inside hits TRIM; edge-as-gap avoids accidental trims on boundaries.
    • Non-hover (Ruler/TCP or Hover OFF):
        - Edit Cursor + selected tracks fallback:
            inside → trim; otherwise → extend nearest left (prev) item.
    • Snap only in true hover (per library).

  Fade policy:
    • Preserve FADE-OUT START. If original fade-out = 0, stays 0.
    • Clear D_FADEOUTLEN_AUTO to avoid transient auto-fade visuals.
    • Fade shape is not modified.

  Library path:
    REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua

@changelog
  v0.3.0
    - Library integration; DEBUG option.
    - True Hover: selection-first; with selection only the RIGHTMOST selected item per track is processed.
    - No-selection + gap on mouse track → extend the previous (left) item on that track.
    - Extend clamps to next item start - epsilon on the same track and to audio source tail (when non-loop).
    - No-flicker write order; preserve fade-OUT START.
--]]

----------------------------------------
-- USER OPTIONS
----------------------------------------
local DEBUG        = false  -- set true to print debug logs
local CLEAR_ON_RUN = false  -- set true to clear console on each run when DEBUG=true

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
log("[RightEdge] --- run ---")

----------------------------------------
-- Helpers
----------------------------------------

-- Non-hover fallback: per selected track, inside→trim; else extend nearest left (prev) item (end ≤ pos)
local function collect_picks_edit_mode_right(pos)
  local picks, eps = {}, hover.half_pixel_sec()
  local tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    tracks[#tracks+1] = reaper.GetSelectedTrack(0, i)
  end
  for _, tr in ipairs(tracks) do
    local inside, extend_from = nil, nil
    local best_left_end = -math.huge
    local n = reaper.CountTrackMediaItems(tr)
    for j = 0, n - 1 do
      local it = reaper.GetTrackMediaItem(tr, j)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local inside_open = (pos > st + eps and pos < en - eps)
      if inside_open then
        inside = it; break
      elseif en <= pos and en > best_left_end then
        extend_from = it; best_left_end = en
      end
    end
    if inside then
      picks[#picks+1] = { item = inside, mode = "trim" }
    elseif extend_from then
      picks[#picks+1] = { item = extend_from, mode = "extend" }
    end
  end
  logf("[RightEdge] collect_picks_edit_mode_right: pos=%.6f, picks=%d", pos, #picks)
  return picks
end

-- True hover, NO selection, and library returned nothing (likely on GAP) → extend PREV on mouse track
local function picks_extend_from_gap_on_mouse_track_right(pos)
  local picks = {}
  if not reaper.BR_GetMouseCursorContext then return picks end
  local window = reaper.BR_GetMouseCursorContext()
  if window ~= "arrange" then return picks end
  local tr = reaper.BR_GetMouseCursorContext_Track()
  if not tr then return picks end
  local eps = hover.half_pixel_sec()
  local target, best_end = nil, -math.huge
  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if en <= pos + eps and en > best_end then
      target, best_end = it, en
    end
  end
  if target then
    picks[#picks+1] = { item = target, mode = "extend" }
    logf("[RightEdge] gap→extend prev: pick end=%.6f", best_end)
  else
    log("[RightEdge] gap→extend prev: no item to the left")
  end
  return picks
end

-- Map: track -> rightmost (max end) selected item info
local function map_rightmost_selected_end_by_track()
  local eps = hover.half_pixel_sec()
  local m = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local tr = reaper.GetMediaItemTrack(it)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local cur = m[tr]
    if (not cur) or (en > cur.en + eps) then
      m[tr] = { en = en, it = it }
    end
  end
  return m
end

-- Filter: when selection present → keep ONLY rightmost selected per track
local function filter_picks_rightmost_selected_per_track(picks)
  if reaper.CountSelectedMediaItems(0) == 0 then return picks end
  local eps = hover.half_pixel_sec()
  local rightmost = map_rightmost_selected_end_by_track()
  local out = {}
  for _, e in ipairs(picks) do
    local it  = e.item
    if reaper.IsMediaItemSelected(it) then
      local tr  = reaper.GetMediaItemTrack(it)
      local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en  = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local rm  = rightmost[tr]
      if rm and math.abs(en - rm.en) <= eps then
        out[#out+1] = e
      else
        logf("[RightEdge] drop (not rightmost on track): end=%.6f", en)
      end
    else
      log("[RightEdge] drop (not selected) while selection present")
    end
  end
  logf("[RightEdge] rightmost-filter picks: %d → %d", #picks, #out)
  return out
end

-- Find NEXT item start on the same track (to clamp extension and avoid overlap)
local function next_item_start_on_track(it)
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

-- Compute max extend end time for audio (non-loop) given current start/offs/rate
local function max_right_end_audio(it, take)
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

-- Apply right-edge trim/extend preserving FADE-OUT START, with no flicker & no overlap.
local function apply_right_edge(entry, target_pos)
  local it = entry.item
  if not hover.is_item_visible(it) then
    log("[RightEdge] skip: item not visible"); return
  end

  local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local ln  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local en0 = st + ln
  local eps = hover.half_pixel_sec()

  local take = reaper.GetActiveTake(it)
  local is_midi  = (take and reaper.TakeIsMIDI(take)) or false
  local is_audio = (take and (not is_midi)) or false
  local loopsrc  = (reaper.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 1)

  -- Desired new end per mode
  local desired_en
  if entry.mode == "trim" then
    desired_en = math.max(st + 1e-9, target_pos)
  else -- "extend"
    desired_en = target_pos
  end

  -- Clamp 1: avoid overlapping NEXT item on same track
  local next_start = next_item_start_on_track(it)
  if next_start < math.huge then
    local max_no_overlap = next_start - eps
    if entry.mode == "extend" then
      -- never reduce length when extending
      if desired_en > max_no_overlap then desired_en = max_no_overlap end
      if desired_en < en0 then desired_en = en0 end
    else
      -- trim 不需要特別考慮下一顆
      -- 但仍確保最小長度
    end
  end

  -- Clamp 2: audio source tail (non-loop only)
  if is_audio and (not loopsrc) then
    local max_tail = max_right_end_audio(it, take)
    if desired_en > max_tail then desired_en = max_tail end
  end

  -- Final guard
  if desired_en <= st + 1e-9 then desired_en = st + 1e-9 end
  if math.abs(desired_en - en0) < 1e-9 then
    log("[RightEdge] no-op: end unchanged"); return
  end

  local new_ln = desired_en - st

  -- Preserve FADE-OUT START
  local old_fo = reaper.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0
  local fade_start = en0 - math.max(0, old_fo)   -- absolute time
  local new_fo = 0
  if old_fo > 0 then
    new_fo = math.max(0, desired_en - fade_start)
  else
    new_fo = 0
  end

  -- No-flicker write order
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", 0) -- avoid transient auto-fade drawing
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", new_ln)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", new_fo)

  logf("[RightEdge] %s  en:%.6f→%.6f  len:%.6f→%.6f  fo:%.6f→%.6f",
       entry.mode, en0, desired_en, ln, new_ln, old_fo, new_fo)
end

----------------------------------------
-- Main
----------------------------------------
local function main()
  -- 1) resolve pos + snap (snap only in true hover)
  local pos, is_true_hover = hover.resolve_target_pos()
  if not pos then log("[RightEdge] abort: pos=nil"); return end
  local raw_pos = pos
  pos = hover.snap_in_true_hover(pos, is_true_hover)
  if is_true_hover then
    logf("[RightEdge] TrueHover: raw=%.6f snapped=%s%.6f", raw_pos, (pos~=raw_pos and "*" or ""), pos)
  else
    logf("[RightEdge] EditCursor: %.6f", pos)
  end

  -- 2) build picks via library (right edge)
  local picks = hover.build_targets_for_trim_extend("right", pos, { prefer_selection_when_hover = true })
  logf("[RightEdge] library picks: %d", #picks)

  -- 2.1) True Hover + selection present → keep ONLY rightmost selected item per track
  if is_true_hover and reaper.CountSelectedMediaItems(0) > 0 then
    picks = filter_picks_rightmost_selected_per_track(picks)
  end

  -- 2.2) True Hover + NO selection + nothing from library → extend prev on mouse track
  if is_true_hover and (#picks == 0) and (reaper.CountSelectedMediaItems(0) == 0) then
    local extra = picks_extend_from_gap_on_mouse_track_right(pos)
    for i = 1, #extra do picks[#picks+1] = extra[i] end
    logf("[RightEdge] added gap-extend prev pick(s): %d", #extra)
  end

  -- 2.3) Non-hover fallback: Edit Cursor + Selected Tracks
  if (not is_true_hover) and (#picks == 0) then
    picks = collect_picks_edit_mode_right(pos)
  end

  if #picks == 0 then log("[RightEdge] no picks; exit"); return end

  -- 3) apply in one UI freeze to avoid flicker
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for _, entry in ipairs(picks) do
    apply_right_edge(entry, pos)
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Trim/Extend Right Edge (hover/edit aware, preserve fade start)", -1)
  log("[RightEdge] done")
end

main()
