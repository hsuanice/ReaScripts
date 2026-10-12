--[[
@description Hover_Mode_-_Trim_or_Extend_Left_Edge_of_Item (Preserve Fade End, No Flicker)
@version 26.1012.1641
@author hsuanice
@noindex
@changelog
  - Renamed to "Hover Editing - Trim or Extend Left Edge" (was "Hover Mode Trim or Extend Left Edge of Item") as part of the 2026-10-12 naming clean-up.
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
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Hover.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

----------------------------------------
-- USER OPTIONS
----------------------------------------
local DEBUG        = false  -- ← set true to print debug logs to ReaScript console
local CLEAR_ON_RUN = false  -- ← set true to clear console on each run when DEBUG=true
local SYNC_SELECTION_MIN = 2  -- selection-sync threshold in True Hover (default: 2)

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

-- 👇 added: show the library path that was actually loaded
logf("[LeftEdge] Hover lib: %s", LIB_PATH)

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
  -- Use library's Pin-safe gap picker (native-first hover track)
  local picks = hover.pick_on_gap("left", pos)
  if #picks > 0 then
    local st = reaper.GetMediaItemInfo_Value(picks[1].item, "D_POSITION")
    logf("[LeftEdge] gap→extend on mouse track: pick start=%.6f", st)
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
  -- Delegate to Hover library: clamp/overlap, preserve fade end, no-flicker order
  hover.apply_left_edge_no_flicker(entry.item, target_pos, entry.mode)
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

  -- decide selection-sync (≥ SYNC_SELECTION_MIN)
  local sel_count = reaper.CountSelectedMediaItems(0)
  local prefer_selection = is_true_hover and (sel_count >= (SYNC_SELECTION_MIN or 2))
  logf("[LeftEdge] sel_count=%d, prefer_selection=%s", sel_count, tostring(prefer_selection))


  -- 2) build picks via library
  local picks = hover.build_targets_for_trim_extend("left", pos, {
    prefer_selection_when_hover = prefer_selection
  })
  logf("[LeftEdge] library picks: %d", #picks)

  -- 2.1) True Hover + selection present → keep ONLY leftmost selected item per track
  if is_true_hover and prefer_selection and (#picks > 0) then
    picks = filter_picks_leftmost_selected_per_track(picks)
  end

  -- 2.2) True Hover + NO selection + nothing from library → extend next on mouse track
  if is_true_hover and (not prefer_selection) and (#picks == 0) then
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