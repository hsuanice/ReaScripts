-- @description Set Time to Item on Right-Drag Release (Toggle, Fast)
-- @version 0.4.4
-- @author hsuanice
-- @about
--   偵測「右鍵拖曳 → 放開」後，立即把目前選取的 items 範圍設為 time selection。
--   移除右鍵冷卻與選單/焦點緩衝，做到幾乎「即放即設」。
--   需要 hsuanice_Mouse.lua（自動尋找含 `/Scripts/hsuanice Scripts/Library/`）。
--
-- @changelog
--   v0.4.4  改為直接偵測當幀右鍵釋放；Mouse lib 用零冷卻（menu_grace/rmb_cooldown/focus_grace=0）

----------------------------------------
-- 參數
----------------------------------------
local DEBUG         = false   -- 設 true 可看 Console 日誌
local ARRANGE_ONLY  = false   -- 只在 Arrange 區域才處理
local SNAPSHOT_DEFER_ONE_FRAME = false  -- 如遇到極少數皮秒級 race，可設 true 讓釋放後等 1 幀再讀 selection

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
    R.."/Scripts/hsuanice Scripts/Library/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice scripts/Library/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice_Scripts/Library/hsuanice_Mouse.lua",
  }
  local info = debug.getinfo(1,"S"); local this_dir = (info and info.source or ""):match("^@(.+[\\/])")
  if this_dir then
    cands[#cands+1] = this_dir.."hsuanice_Mouse.lua"
    cands[#cands+1] = this_dir.."Library/hsuanice_Mouse.lua"
  end
  for _,p in ipairs(cands) do
    if file_exists(p) then local ok,lib=pcall(dofile,p); if ok and type(lib)=="table" and lib.new then return lib end end
  end
  reaper.ShowMessageBox("找不到 hsuanice_Mouse.lua。","Missing library",0); return nil
end

----------------------------------------
-- Selection helpers
----------------------------------------
local function snapshot_sel_tbl()
  local t = {}; local n = reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0,i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    t[g]=true
  end
  return t, n
end
local function sel_changed(a,b)
  for g in pairs(b) do if not a[g] then return true end end
  for g in pairs(a) do if not b[g] then return true end end
  return false
end
local function set_time_to_items()
  local n = reaper.CountSelectedMediaItems(0); if n==0 then return false end
  local min_pos=math.huge; local max_end=-math.huge
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0,i)
    local p  = reaper.GetMediaItemInfo_Value(it,"D_POSITION")
    local L  = reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
    if p<min_pos then min_pos=p end
    if p+L>max_end then max_end=p+L end
  end
  reaper.GetSet_LoopTimeRange(true,false,min_pos,max_end,false)
  log(("[set] time=%.3f→%.3f items=%d"):format(min_pos,max_end,n))
  return true
end

----------------------------------------
-- State
----------------------------------------
local running=false
local mouse=nil
local prev_sel_tbl=nil
local rmb_was_down=false
local arm_post_release=false   -- 只用於 SNAPSHOT_DEFER_ONE_FRAME

----------------------------------------
-- Main
----------------------------------------
local function main()
  if not running then return end

  local ev = mouse:tick()
  -- Arrange 限制（可選）
  if ARRANGE_ONLY and not ev.blocked then
    local hit = mouse:hit()
    if not (hit and hit.in_arrange) then return reaper.defer(main) end
  end

  -- 立即偵測「當幀右鍵釋放」
  local released_now = (rmb_was_down and not mouse.rmb and not ev.blocked)
  rmb_was_down = mouse.rmb  -- 更新前一幀狀態

  if released_now then
    if SNAPSHOT_DEFER_ONE_FRAME then
      arm_post_release = true
    else
      local after_tbl = select(1, snapshot_sel_tbl())
      if sel_changed(prev_sel_tbl, after_tbl) then set_time_to_items() end
      prev_sel_tbl = after_tbl
    end
  elseif arm_post_release then
    -- 釋放後延一幀再取 selection（必要時才開）
    local after_tbl = select(1, snapshot_sel_tbl())
    if sel_changed(prev_sel_tbl, after_tbl) then set_time_to_items() end
    prev_sel_tbl = after_tbl
    arm_post_release = false
  end

  reaper.defer(main)
end

----------------------------------------
-- Toggle（真兩段）
----------------------------------------
local is_on = (reaper.GetToggleCommandStateEx(sectionID, cmdID) == 1)
if is_on then
  running=false
  set_toggle(false)
  log("[state] disabled")
  return
else
  local MouseLib = load_mouse_lib(); if not MouseLib then set_toggle(false); return end
  -- ★ 這裡把所有冷卻/緩衝設為 0，做到即放即判
  mouse = MouseLib.new{
    debug=false,
    menu_grace=0.0,
    rmb_cooldown=0.0,
    focus_grace=0.0,
    require_fresh_lmb=false,
  }
  if DEBUG then reaper.ShowConsoleMsg("") end
  running=true
  set_toggle(true)
  prev_sel_tbl = select(1, snapshot_sel_tbl())
  log("[state] enabled")
  main()
  reaper.atexit(function() set_toggle(false) end)
end
