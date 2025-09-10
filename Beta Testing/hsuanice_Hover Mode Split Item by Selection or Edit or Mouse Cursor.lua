--[[
@description Hover Mode - Split Items (Selection-first in Hover, Mouse/Edit aware) + Simple Debug Switch
@version 0.2.1
@author hsuanice
@about
  Context-aware item splitting with unified hover/edit logic via library, but performs the split
  using the native Action 40757 (Split items at edit cursor) to avoid visual fade artifacts.

  Priority:
    1) Razor Edit spans → split at time selection, keep overlapped items selected, clear razor visuals.
    2) Time Selection (with selected items) → split, then unselect all（可在 USER OPTIONS 設定忽略）.
    3) Hover/Edit path:
       - True Hover (mouse over arrange, not Ruler/TCP):
           If there are selected items, split only those crossing the mouse time.
           Otherwise split the item strictly under the mouse.
       - Non-hover (Ruler/TCP or Hover OFF):
           Split items crossing Edit Cursor on selected tracks (fallback).

  Library path: REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua

  Debug:
    • Toggle in USER OPTIONS: DEBUG = true/false
    • Output → ReaScript console (View → Show console output).

@changelog
  v0.2.1
    - Added: USER OPTION `IGNORE_TIME_SELECTION` (default false). When true, time selection priority is skipped.
  v0.2.0
    - Change: Use Action 40757 for splitting (parity with v0.1) to avoid transient fade visuals from SplitMediaItem().
    - Refactor: Uses hsuanice_Hover.lua (v0.1.0) for position/targets; selection-first when true hover.
    - Kept: Razor Edit & Time Selection priority; forced UpdateArrange for immediate redraw.
  v0.1
    - Initial beta (pre-library)
--]]

----------------------------------------
-- USER OPTIONS
----------------------------------------
local DEBUG                 = false  -- ← 設 true 開啟除錯輸出
local CLEAR_ON_RUN          = false  -- ← 設 true 在每次執行且 DEBUG=ON 時先清空 console
local IGNORE_TIME_SELECTION = true  -- ← 設 true 直接忽略 Time Selection 優先權（走下一層流程）

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
local function log(line)
  if not DEBUG then return end
  reaper.ShowConsoleMsg(tostring(line).."\n")
end
local function logf(fmt, ...)
  if not DEBUG then return end
  reaper.ShowConsoleMsg(string.format(fmt, ...).."\n")
end
if DEBUG and CLEAR_ON_RUN then reaper.ShowConsoleMsg("") end
log("[HoverSplit] --- run ---")

----------------------------------------
-- Local helpers
----------------------------------------
local function save_item_selection()
  local list = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    list[#list+1] = reaper.GetSelectedMediaItem(0, i)
  end
  return list
end

local function restore_item_selection(list)
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  for _, it in ipairs(list) do
    if reaper.ValidatePtr(it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end

-- Use native Action 40757 to perform the actual split (parity with v0.1 visuals)
local function split_via_action(pos, targets)
  if #targets == 0 then return end
  local old_cur = reaper.GetCursorPosition()
  local prev_sel = save_item_selection()

  reaper.Main_OnCommand(40289, 0)              -- Unselect all
  for _, it in ipairs(targets) do
    reaper.SetMediaItemSelected(it, true)       -- select only intended items
  end
  reaper.SetEditCurPos(pos, false, false)
  reaper.Main_OnCommand(40757, 0)               -- Split items at edit cursor
  reaper.SetEditCurPos(old_cur, false, false)

  restore_item_selection(prev_sel)
  logf("[HoverSplit] split_via_action: %d items", #targets)
end

-- Collect items on currently selected tracks that strictly cover 'pos'
local function collect_items_on_selected_tracks_at(pos)
  local result = {}
  local selected_tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    selected_tracks[reaper.GetSelectedTrack(0, i)] = true
  end
  local eps = hover.half_pixel_sec()
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local it = reaper.GetMediaItem(0, i)
    local tr = reaper.GetMediaItemTrack(it)
    if selected_tracks[tr] then
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if pos > st + eps and pos < en - eps then
        result[#result+1] = it
      end
    end
  end
  logf("[HoverSplit] collect_items_on_selected_tracks_at: pos=%.6f, hits=%d", pos, #result)
  return result
end

----------------------------------------
-- 1) Razor Edit priority (unchanged in spirit)
----------------------------------------
local function handle_razor_edit_if_any()
  local razor_items, razor_found = {}, false
  local spans = 0

  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    local _, razor = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor ~= "" then
      razor_found = true
      for span in string.gmatch(razor, "[^%s]+") do
        local s, e = span:match("([%d%.]+) ([%d%.]+)")
        if s and e then
          spans = spans + 1
          s, e = tonumber(s), tonumber(e)
          for i = 0, reaper.CountTrackMediaItems(track) - 1 do
            local it = reaper.GetTrackMediaItem(track, i)
            local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
            local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
            if en > s and st < e then
              razor_items[#razor_items+1] = it
            end
          end
        end
      end
    end
  end

  if not razor_found then return false end
  logf("[HoverSplit] Razor found: spans=%d, items=%d", spans, #razor_items)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(40061, 0) -- Split items at time selection
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  for _, it in ipairs(razor_items) do
    reaper.SetMediaItemSelected(it, true)
  end
  -- Clear razor visuals
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Split Razor Area and Keep Selection", -1)
  return true
end

----------------------------------------
-- 2) Time Selection priority (respect user option)
----------------------------------------
local function handle_time_selection_if_any()
  if IGNORE_TIME_SELECTION then
    log("[HoverSplit] TimeSelection: ignored by user option")
    return false
  end

  local ts_start, ts_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local sel_items = reaper.CountSelectedMediaItems(0)
  if ts_start == ts_end or sel_items == 0 then return false end

  logf("[HoverSplit] TimeSelection: start=%.6f end=%.6f, selected_items=%d", ts_start, ts_end, sel_items)

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(40061, 0) -- Split at time selection
  reaper.Main_OnCommand(40289, 0) -- Unselect all (parity with previous behavior)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Split by Time Selection (selected items only)", -1)
  return true
end

----------------------------------------
-- 3) Hover/Edit path (via library for position/targets, action for split)
----------------------------------------
local function main_hover_or_edit()
  local pos, is_true_hover = hover.resolve_target_pos()
  if not pos then
    log("[HoverSplit] resolve_target_pos: nil (abort)")
    return
  end
  local pos0 = pos
  pos = hover.snap_in_true_hover(pos, is_true_hover)
  if is_true_hover then
    logf("[HoverSplit] TrueHover pos: raw=%.6f snapped=%s%.6f",
         pos0, (pos~=pos0 and "*" or ""), pos)
  else
    logf("[HoverSplit] EditCursor pos: %.6f", pos)
  end

  local targets
  if is_true_hover then
    -- Hover=ON & not over Ruler/TCP → selection-first via library
    targets = hover.build_targets_for_split(pos, { prefer_selection_when_hover = true })
    logf("[HoverSplit] targets via library (true hover): %d", #targets)
  else
    -- Non-hover path: edit cursor on selected tracks
    targets = collect_items_on_selected_tracks_at(pos)
  end

  if #targets == 0 then
    log("[HoverSplit] No targets. Abort.")
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  split_via_action(pos, targets)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Split items at position (hover/edit aware)", -1)
  logf("[HoverSplit] Done. Split count=%d", #targets)
end

----------------------------------------
-- Entry: Priority chain
----------------------------------------
if handle_razor_edit_if_any() then
  log("[HoverSplit] Exit via Razor branch."); return
end
if handle_time_selection_if_any() then
  log("[HoverSplit] Exit via TimeSelection branch."); return
end
main_hover_or_edit()
log("[HoverSplit] Exit via Hover/Edit branch.")
