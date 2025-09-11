-- @description Set Time to Item on Right-Drag Release (Toggle, One-Pass Perf)
-- @version 0.4.5
-- @author hsuanice
-- @about
--   右鍵「有拖曳」→ 在「放開」當幀（可選延一幀）把目前選取 items 的最小開始/最大結束設為 time selection。
--   專為大專案優化：放開時僅「單趟掃描」選取 items（不建立 GUID 表、不做前後比對），可選擇避免重複設值。
--   自動尋找 hsuanice_Mouse.lua（含 `/Scripts/hsuanice Scripts/Library/` 路徑）。
--
-- @changelog
--   v0.4.5  大專案優化：放開時單趟掃描、可啟用 RMB 真拖曳偵測、加入 time 快取避免重複設值；維持真兩段 toggle

----------------------------------------
-- 可調參數
----------------------------------------
local DEBUG                = false  -- 設 true 會在 Console 簡單列印事件
local ARRANGE_ONLY         = false  -- 只在 Arrange 區域才處理
local REQUIRE_RMB_DRAG     = true   -- 只在「右鍵有拖曳（移動超過門檻）」時才觸發（建議 true）
local SNAPSHOT_DEFER_ONE_FRAME = false -- 如遇個別專案在放開當幀 selection 尚未更新，設 true 只延 1 幀
local DRAG_THRESHOLD_PX    = 4      -- 判定「有拖曳」的像素門檻
local AVOID_REDUNDANT_SET  = true   -- 若新舊 time selection 幾乎相同就不重設
local LOOP_EPS             = 1e-6   -- 上述比較的誤差容忍（秒）

----------------------------------------
-- Toggle helpers
----------------------------------------
local _, _, sectionID, cmdID = reaper.get_action_context()
local function set_toggle(state)
  reaper.SetToggleCommandState(sectionID, cmdID, state and 1 or 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
end
local function log(s) if DEBUG then reaper.ShowConsoleMsg("[RDragSetTime] "..s.."\n") end end

----------------------------------------
-- Mouse library loader（多路徑）
----------------------------------------
local function file_exists(p) local f=io.open(p,"r"); if f then f:close(); return true end end
local function load_mouse_lib()
  local R = reaper.GetResourcePath()
  local cands = {
    R.."/Scripts/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice Scripts/Library/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice scripts/Library/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice_Scripts/Library/hsuanice_Mouse.lua",
  }
  local info=debug.getinfo(1,"S"); local this_dir=(info and info.source or ""):match("^@(.+[\\/])")
  if this_dir then
    cands[#cands+1]=this_dir.."hsuanice_Mouse.lua"
    cands[#cands+1]=this_dir.."Library/hsuanice_Mouse.lua"
  end
  for _,p in ipairs(cands) do
    if file_exists(p) then local ok,lib=pcall(dofile,p); if ok and type(lib)=="table" and lib.new then return lib end end
  end
  reaper.ShowMessageBox("找不到 hsuanice_Mouse.lua。","Missing library",0)
  return nil
end

----------------------------------------
-- 單趟掃描：直接取出選取 items 的 min/max（O(#selected)）
----------------------------------------
local function compute_bounds_of_selected_items()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return 0, 0.0, 0.0 end
  local min_pos = math.huge
  local max_end = -math.huge
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0,i)
    local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local L  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < min_pos then min_pos = p end
    local e = p + L
    if e > max_end then max_end = e end
  end
  return n, min_pos, max_end
end

-- 取得目前 time selection（避免重複設值時使用）
local function get_time_sel()
  local st, en = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return st, en
end

local function set_time_if_needed(min_pos, max_end)
  if AVOID_REDUNDANT_SET then
    local old_s, old_e = get_time_sel()
    if math.abs(old_s - min_pos) <= LOOP_EPS and math.abs(old_e - max_end) <= LOOP_EPS then
      log(("[skip] unchanged time: %.6f → %.6f"):format(min_pos, max_end))
      return false
    end
  end
  -- 設置 time selection
  reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
  log(("[set] time %.6f → %.6f"):format(min_pos, max_end))
  return true
end

----------------------------------------
-- 狀態
----------------------------------------
local running = false
local mouse = nil

-- 右鍵拖曳判斷
local rmb_down = false
local rmb_down_x, rmb_down_y = 0, 0
local rmb_dragged = false

local arm_post_release = false -- 延一幀用

----------------------------------------
-- Main
----------------------------------------
local function main()
  if not running then return end

  local ev = mouse:tick()

  -- 只在 Arrange（可選）
  if ARRANGE_ONLY and not ev.blocked then
    local hit = mouse:hit()
    if not (hit and hit.in_arrange) then
      return reaper.defer(main)
    end
  end

  -- 追蹤右鍵按下/拖曳
  if mouse.rmb and not rmb_down then
    rmb_down = true
    rmb_dragged = false
    rmb_down_x, rmb_down_y = reaper.GetMousePosition()
  elseif mouse.rmb and rmb_down then
    if REQUIRE_RMB_DRAG and not rmb_dragged then
      local x,y = reaper.GetMousePosition()
      if (math.abs(x - rmb_down_x) >= DRAG_THRESHOLD_PX) or (math.abs(y - rmb_down_y) >= DRAG_THRESHOLD_PX) then
        rmb_dragged = true
      end
    end
  end

  -- 當幀「右鍵放開」
  local released_now = (rmb_down and not mouse.rmb and not ev.blocked)
  if released_now then
    rmb_down = false
    -- 若需要「一定要有拖曳」才觸發，沒拖曳就忽略
    if REQUIRE_RMB_DRAG and not rmb_dragged then
      log("[ignore] RMB click w/o drag")
    else
      if SNAPSHOT_DEFER_ONE_FRAME then
        arm_post_release = true
      else
        local cnt, s, e = compute_bounds_of_selected_items()
        if cnt > 0 then set_time_if_needed(s, e) end
      end
    end
  elseif arm_post_release then
    -- 延一幀版本（極少數專案需要）
    local cnt, s, e = compute_bounds_of_selected_items()
    if cnt > 0 then set_time_if_needed(s, e) end
    arm_post_release = false
  end

  reaper.defer(main)
end

----------------------------------------
-- Toggle（真兩段）
----------------------------------------
local is_on = (reaper.GetToggleCommandStateEx(sectionID, cmdID) == 1)
if is_on then
  running = false
  set_toggle(false)
  log("[state] disabled")
  return
else
  local MouseLib = load_mouse_lib(); if not MouseLib then set_toggle(false); return end
  mouse = MouseLib.new{
    debug=false,
    -- 完全零緩衝：即放即判（視你 mouse lib 實作，這些會略過選單/焦點緩衝）
    menu_grace=0.0,
    rmb_cooldown=0.0,
    focus_grace=0.0,
    require_fresh_lmb=false,
    drag_threshold_px = DRAG_THRESHOLD_PX,
  }
  if DEBUG then reaper.ShowConsoleMsg("") end
  running = true
  set_toggle(true)
  log("[state] enabled")
  main()
  reaper.atexit(function() set_toggle(false) end)
end
