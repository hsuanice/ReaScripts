--[[
@description Hover_Mode_-_Trim_or_Extend_Right_Edge_of_Item (Preserve Fade Start, No Flicker)
@version 2510051925 Fix Pin Track issue
@author hsuanice
@about
  Right-edge trim/extend that preserves the FADE-OUT START time (not the length), using the shared
  Hover library for position & target selection. No-flicker write order and no-overlap extends.

  Behavior summary:
    • True Hover (mouse over arrange, not Ruler/TCP):
        - Selection-sync only when selected item count ≥ SYNC_SELECTION_MIN (default: 2).
          If only ONE item is selected, treat as no-selection (individual editing feel).
        - When selection-sync is ON: only process the RIGHTMOST selected item per track (skip others).
        - When selection-sync is OFF (no/one selection) and mouse is on a GAP:
          extend the previous item on the mouse track (nearest item whose END ≤ mouse time).
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
  v251005_1925
    - Fixed: Hover and extend behavior when “Pin Track” feature is active.
      * Updated the library to use REAPER’s native mouse-track resolver instead of SWS functions,
        ensuring correct detection of items even when tracks are pinned in the TCP/MCP.
    - Verified consistency with Left-Edge implementation:
      * True hover, gap-extend, and selection-sync logic identical to left-edge behavior.
      * All SWS dependencies removed for native safety and performance.
    - Result: Right-edge trim/extend now functions normally on pinned tracks and ruler/TCP hover modes.
    
  v250926_1810
    - Read Hover library and print loaded path in console.
    - Delegate right-edge handling to shared no-flicker logic.
    - Add detailed [HoverLib] right-edge logs (st/en/target, new_en, delta_len, applied).
  v250926_1610
    - reading Hover library; added debug path output and delegated right-edge handling to shared library.
  v0.3.2
    - Selection-sync in True Hover now requires ≥2 selected items. With a single selected item, behave like no-selection.
    - Passed `prefer_selection` into the library, gated the rightmost-per-track filter with this flag,
      and enabled the gap→extend fallback only when selection-sync is OFF (no/one selection).
  v0.3.1
    - Initial Right-edge port with no-flicker writes and no-overlap extends; library integration.
--]]

----------------------------------------
-- USER OPTIONS
----------------------------------------
local DEBUG              = true  -- set true to print debug logs
local CLEAR_ON_RUN       = false  -- set true to clear console on each run when DEBUG=true
local SYNC_SELECTION_MIN = 2      -- selection-sync threshold in True Hover (default: 2)

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
local function log(s)       if DEBUG then reaper.ShowConsoleMsg(tostring(s).."\n") end end
local function logf(f, ...) if DEBUG then reaper.ShowConsoleMsg(string.format(f, ...).."\n") end end
if DEBUG and CLEAR_ON_RUN then reaper.ShowConsoleMsg("") end
log("[RightEdge] --- run ---")
logf("[RightEdge] Hover lib: %s", LIB_PATH)

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

-- True hover, selection-sync OFF (no/one selection), and library returned nothing (likely on GAP) → extend PREV on mouse track
local function picks_extend_from_gap_on_mouse_track_right(pos)
  -- Pin-safe: use library's native-first mouse-track resolver
  local picks = hover.pick_on_gap("right", pos)
  if #picks > 0 then
    local st = reaper.GetMediaItemInfo_Value(picks[1].item, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(picks[1].item, "D_LENGTH")
    logf("[RightEdge] gap→extend prev: pick end=%.6f", en)
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

-- Filter: when selection-sync is ON → keep ONLY rightmost selected per track
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
  -- Delegate to shared library: no-overlap clamp, preserve fade-out START, no-flicker
  hover.apply_right_edge_no_flicker(entry.item, target_pos, entry.mode)
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

  -- 2) decide selection-sync (≥ SYNC_SELECTION_MIN)
  local sel_count = reaper.CountSelectedMediaItems(0)
  local prefer_selection = is_true_hover and (sel_count >= (SYNC_SELECTION_MIN or 2))
  logf("[RightEdge] sel_count=%d, prefer_selection=%s", sel_count, tostring(prefer_selection))

  -- 3) build picks
  local picks
  if is_true_hover then
    -- pass prefer_selection into library
    picks = hover.build_targets_for_trim_extend("right", pos, {
      prefer_selection_when_hover = prefer_selection
    })
    logf("[RightEdge] library picks: %d", #picks)

    -- selection-sync ON → keep ONLY rightmost selected per track
    if prefer_selection and (#picks > 0) then
      picks = filter_picks_rightmost_selected_per_track(picks)
    end

    -- selection-sync OFF（no/one selection）+ nothing from library → gap extend on mouse track
    if (not prefer_selection) and (#picks == 0) then
      local extra = picks_extend_from_gap_on_mouse_track_right(pos)
      for i = 1, #extra do picks[#picks+1] = extra[i] end
      logf("[RightEdge] added gap-extend prev pick(s): %d", #extra)
    end
  else
    -- Non-hover fallback
    picks = collect_picks_edit_mode_right(pos)
  end

  if (not picks) or (#picks == 0) then log("[RightEdge] no picks; exit"); return end

  -- 4) apply in one UI freeze to avoid flicker
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
