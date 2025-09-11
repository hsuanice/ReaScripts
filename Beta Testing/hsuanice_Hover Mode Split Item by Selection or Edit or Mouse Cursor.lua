--[[
@description Hover Mode - Split Items (Selection-first in Hover, Mouse/Edit aware) + Simple Debug Switch
@version 0.2.4
@author hsuanice
@about
  Context-aware item splitting with unified hover/edit logic via library, but performs the split
  using the native Action 40757 (Split items at edit cursor) to avoid visual fade artifacts.

  Priority:
    1) Razor Edit spans → split at time selection, keep overlapped items selected, clear razor visuals.
    2) Time Selection (with selected items) → split, then unselect all（可在 USER OPTIONS 設定忽略）.
    3) Hover/Edit path:
       - True Hover (mouse over arrange, not Ruler/TCP):
           • If there are selected items, split those crossing the mouse time;
             additionally, if the item under mouse is OUTSIDE selection but crosses the time, split it too.
           • If there is no selection, split the item strictly under the mouse.
       - Non-hover (Ruler/TCP or Hover OFF):
           Split items crossing Edit Cursor on selected tracks (fallback).

  Selection policy:
    • Original selection is preserved. If a previously-selected item is split, BOTH resulting halves remain selected.

  Library path: REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua

  Debug:
    • Toggle in USER OPTIONS: DEBUG = true/false
    • Output → ReaScript console (View → Show console output).

@changelog
@changelog
  v0.2.4
    - Fix: When both a Time Selection and a single selected item existed with no overlap, the first run would clear the selection without splitting.
            Now the Time Selection branch runs only if at least one selected item overlaps the TS range; otherwise it falls through to the Hover/Edit path.
    - Logging: Added debug output showing the Time Selection overlap count.
    - No other changes: Razor priority, IGNORE_TIME_SELECTION, hover behavior, selection-sync threshold (≥2), and “preserve both halves of originally selected items” remain unchanged.
  v0.2.3 - Hover selection-sync requires >=2 selected items; single selection behaves like no-selection.
  v0.2.2
    - True Hover: When selection exists, also split the item under mouse if it's outside selection but crosses the time.
  v0.2.1.1
    - Preserve original selection across split (both halves stay selected for originally-selected items).
  v0.2.1
    - USER OPTION `IGNORE_TIME_SELECTION`.
  v0.2.0
    - Use Action 40757 for splitting; integrated hover library and forced redraw.
--]]

----------------------------------------
-- USER OPTIONS
----------------------------------------
local DEBUG                 = false  -- ← 設 true 開啟除錯輸出
local CLEAR_ON_RUN          = false  -- ← 設 true 在每次執行且 DEBUG=ON 時先清空 console
local IGNORE_TIME_SELECTION = true  -- ← 設 true 直接忽略 Time Selection 優先權（走下一層流程）
local SYNC_SELECTION_MIN = 2  -- Hover 下啟用「選取同步」的最小選取數

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
-- Local helpers (selection save/restore & split)
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

-- 事先記錄「原本已選且會被切到的 items」資訊（track + 舊的 end），以便分割後選到右半
local function build_selected_items_split_info(pos, eps)
  local info = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en  = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos > st + eps and pos < en - eps then
      info[#info+1] = {
        track   = reaper.GetMediaItemTrack(it),
        old_end = en
      }
    end
  end
  logf("[HoverSplit] will-split selected items: %d", #info)
  return info
end

-- 分割後，針對「原本已選且被切」的每個 item，把右半也選回來（start≈pos 且 end≈old_end）
local function select_right_halves_after_split(split_info, pos, eps)
  for _, s in ipairs(split_info) do
    local tr = s.track
    local old_end = s.old_end
    if reaper.ValidatePtr(tr, "MediaTrack*") then
      for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, i)
        local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if math.abs(st - pos) <= (eps * 2) and math.abs(en - old_end) <= (eps * 2) then
          reaper.SetMediaItemSelected(it, true)
          logf("[HoverSplit] select right-half: start=%.6f end=%.6f", st, en)
          break
        end
      end
    end
  end
end

-- 用原生 Action 40757 來分割，並正確保留原本選取（若原本已選且被切 → 左右半都保持選取）
local function split_via_action_preserve_selection(pos, targets, eps)
  if #targets == 0 then return end
  local old_cur   = reaper.GetCursorPosition()
  local prev_sel  = save_item_selection()
  local sel_split = build_selected_items_split_info(pos, eps)

  reaper.Main_OnCommand(40289, 0)              -- Unselect all
  for _, it in ipairs(targets) do
    reaper.SetMediaItemSelected(it, true)       -- 只選要切的目標
  end
  reaper.SetEditCurPos(pos, false, false)
  reaper.Main_OnCommand(40757, 0)               -- Split items at edit cursor
  reaper.SetEditCurPos(old_cur, false, false)

  -- 還原原本選取（此時原 item 指標對應「左半」），再把右半也補選回來
  restore_item_selection(prev_sel)
  select_right_halves_after_split(sel_split, pos, eps)

  logf("[HoverSplit] split_via_action_preserve_selection: targets=%d, split_sel=%d", #targets, #sel_split)
end

-- Fallback：在已選軌上收集覆蓋 pos 的 items
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

-- 工具：把 hovered item（若未選且覆蓋 pos）加入 targets
local function maybe_add_hover_item_outside_selection(targets, pos, eps)
  local x, y = reaper.GetMousePosition()
  local hit  = reaper.GetItemFromPoint(x, y, false)
  if not hit then
    log("[HoverSplit] hover item: none")
    return
  end
  -- 未選才考慮（需求：在 selection 以外才補切 hovered）
  if reaper.IsMediaItemSelected(hit) then
    log("[HoverSplit] hover item: is selected → already covered by selection path")
    return
  end
  local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
  local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
  local inside = (pos > st + eps and pos < en - eps)
  if not inside then
    log("[HoverSplit] hover item: exists but not crossing time")
    return
  end
  -- 避免重複
  for _, it in ipairs(targets) do
    if it == hit then
      log("[HoverSplit] hover item: already in targets")
      return
    end
  end
  table.insert(targets, hit)
  logf("[HoverSplit] hover item added (outside selection): start=%.6f end=%.6f", st, en)
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
-- 2) Time Selection priority (respect user option) + DEBUG classification
----------------------------------------
local function handle_time_selection_if_any()
  if IGNORE_TIME_SELECTION then
    log("[HoverSplit] TS: ignored by user option")
    return false
  end

  local ts_start, ts_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if ts_start == ts_end then return false end

  local sel_items = reaper.CountSelectedMediaItems(0)
  if sel_items == 0 then return false end

  local overlapped = {}
  local boundary_hits, edges_only = 0, 0

  for i = 0, sel_items - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")

    -- 是否和 TS 有重疊（開區間重疊檢查）
    local has_overlap = (en > ts_start and st < ts_end)
    if has_overlap then
      overlapped[#overlapped+1] = it

      -- 是否「TS 邊界有落在 item 內部」→ 40061 會切
      local hit_start = (st < ts_start and en > ts_start)
      local hit_end   = (st < ts_end   and en > ts_end)
      if hit_start or hit_end then
        boundary_hits = boundary_hits + 1
      else
        -- 只有重疊，但兩個邊界都沒穿進 item（例如 TS 正好等於 item 邊界）
        edges_only = edges_only + 1
      end
    end
  end

  logf("[HoverSplit] TS dbg: ts=[%.6f, %.6f] sel=%d overlaps=%d boundary_hits=%d edges_only=%d",
       ts_start, ts_end, sel_items, #overlapped, boundary_hits, edges_only)

  -- 注意：為了「只加除錯不改行為」，下面仍沿用 0.2.4 的邏輯：
  -- 只要有 overlapped 就跑 40061（即使 boundary_hits=0 的時候其實不會切）
  if #overlapped == 0 then
    return false
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  reaper.Main_OnCommand(40061, 0) -- Split at time selection
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  for _, it in ipairs(overlapped) do
    if reaper.ValidatePtr(it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Split by Time Selection (selected items with overlap)", -1)
  return true
end

----------------------------------------
-- 3) Hover/Edit path (via library for position/targets, action for split)
----------------------------------------
local function main_hover_or_edit()
  local pos, is_true_hover = hover.resolve_target_pos()
  local sel_count = reaper.CountSelectedMediaItems(0)
  local prefer_selection = is_true_hover and (sel_count >= (SYNC_SELECTION_MIN or 2))
  if DEBUG then
    logf("[HoverSplit] selection count=%d; prefer_selection=%s",
        sel_count, tostring(prefer_selection))
  end  
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
  local eps = hover.half_pixel_sec()

  if is_true_hover then
    targets = hover.build_targets_for_split(pos, { prefer_selection_when_hover = prefer_selection })
    logf("[HoverSplit] targets via library (true hover, prefer_selection=%s): %d",
        tostring(prefer_selection), #targets)

    -- 只有在啟用「選取同步」（≥2）時，才同時把 selection 以外、滑鼠下那顆也納入
    if prefer_selection then
      local eps = hover.half_pixel_sec()
      maybe_add_hover_item_outside_selection(targets, pos, eps)
    end
  else
    -- 非 hover 路徑：以 Edit Cursor 在已選軌上收集目標
    targets = collect_items_on_selected_tracks_at(pos)
  end

  if #targets == 0 then
    log("[HoverSplit] No targets. Abort.")
    return
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  split_via_action_preserve_selection(pos, targets, eps)

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
