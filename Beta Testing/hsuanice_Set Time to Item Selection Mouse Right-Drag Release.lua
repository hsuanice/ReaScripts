-- @description Set Time to Item on Right-Drag Release (Toggle, Debug)
-- @version 0.4.1
-- @author hsuanice
-- @about
--   偵測「右鍵拖曳 → 放開」這段操作（不限於 marquee），在釋放後把
--   目前被選取的 items 之最小開始/最大結束設定為 time selection。
--   加入 Debug 與效能量測與可調參數。
--   需要 hsuanice_Mouse.lua（會自動多路徑尋找，含 `/Scripts/hsuanice Scripts/Library/`）。
--
-- @changelog
--   v0.4.1  新：Debug 日誌、觸發延遲/節流參數、簡易 profiler；改善 rmb release 判斷
--   v0.4.0  初版（右鍵拖曳後在 release 觸發）
--   v0.3.x  MouseUp on marquee（舊邏輯）
--   v0.2.0  Toolbar toggle
--   v0.1.0  初版

----------------------------------------
-- 可調參數（依需求調整）
----------------------------------------
local DEBUG                = true        -- 總開關
local DEBUG_VERBOSE        = false       -- 額外逐步輸出（每幀事件）
local DEBUG_CLEAR_ON_START = true        -- 啟動時清空 Console

local POST_RMB_COOLDOWN_SEC      = 0.00  -- 右鍵放開後再等多久才檢查（0~0.20 視右鍵選單/冷卻情況）
local MIN_FRAMES_BETWEEN_CHECKS  = 0     -- 至少跳過幾幀才跑一次重活（0=每幀）
local SNAPSHOT_THROTTLE_SEC      = 0.00  -- 兩次 snapshot 的最小間隔（0=不節流）

----------------------------------------
-- Toggle helpers
----------------------------------------
local _, _, sectionID, cmdID = reaper.get_action_context()
local function set_toggle(state)
  reaper.SetToggleCommandState(sectionID, cmdID, state and 1 or 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
end

----------------------------------------
-- Debug helpers / profiler
----------------------------------------
local PREFIX = "[RDragSetTime] "
local function log(s)
  if DEBUG then reaper.ShowConsoleMsg(PREFIX .. s .. "\n") end
end
local function vlog(s)
  if DEBUG and DEBUG_VERBOSE then reaper.ShowConsoleMsg(PREFIX .. s .. "\n") end
end

local loop_count = 0
local last_prof_t = reaper.time_precise()
local avg_loop_dt = 0.0

local function profiler_tick()
  loop_count = loop_count + 1
  local now = reaper.time_precise()
  local dt  = now - last_prof_t
  -- 指數平滑平均（避免太抖）
  avg_loop_dt = (avg_loop_dt==0 and dt) or (avg_loop_dt*0.9 + dt*0.1)
  -- 每 ~0.5s 報一次（不刷太勤）
  if dt >= 0.5 then
    local fps = loop_count / dt
    log(("[perf] loop=%.1f fps, avg_dt=%.3f ms"):format(fps, avg_loop_dt*1000.0))
    loop_count, last_prof_t = 0, now
  end
end

----------------------------------------
-- Mouse library loader (multi-path)
----------------------------------------
local function file_exists(p)
  local f = io.open(p, "r"); if f then f:close(); return true end; return false
end

local function load_mouse_lib()
  local R = reaper.GetResourcePath()
  local candidates = {
    R .. "/Scripts/hsuanice_Mouse.lua",
    R .. "/Scripts/hsuanice Scripts/Library/hsuanice_Mouse.lua", -- 你的既有路徑
    R .. "/Scripts/hsuanice scripts/Library/hsuanice_Mouse.lua", -- 大小寫容錯
    R .. "/Scripts/hsuanice_Scripts/Library/hsuanice_Mouse.lua",
  }
  local info = debug.getinfo(1, "S")
  local this_dir = (info and info.source or ""):match("^@(.+[\\/])")
  if this_dir then
    table.insert(candidates, this_dir .. "hsuanice_Mouse.lua")
    table.insert(candidates, this_dir .. "Library/hsuanice_Mouse.lua")
  end
  for _, p in ipairs(candidates) do
    if file_exists(p) then
      local ok, lib = pcall(dofile, p)
      if ok and type(lib) == "table" and lib.new then
        log("[lib] loaded: " .. p)
        return lib
      end
    end
  end
  reaper.ShowMessageBox(
    "找不到 hsuanice_Mouse.lua。\n請確認以下任一路徑存在：\n" ..
    "• REAPER/Scripts/hsuanice_Mouse.lua\n" ..
    "• REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Mouse.lua\n" ..
    "或將檔案放在本腳本同資料夾。",
    "Missing library", 0)
  return nil
end

local MouseLib = load_mouse_lib()
if not MouseLib then return end
local mouse = MouseLib.new{ debug = DEBUG_VERBOSE }

----------------------------------------
-- Selection helpers
----------------------------------------
local last_snapshot_t = -1
local function snapshot_sel()
  local now = reaper.time_precise()
  if SNAPSHOT_THROTTLE_SEC > 0 and last_snapshot_t > 0 and (now - last_snapshot_t) < SNAPSHOT_THROTTLE_SEC then
    -- 節流：照樣回傳最新（仍需抓當前），只是避免你把 throttle 設太大時不知道在發生什麼
    vlog(("[snap] throttled (%.0f ms remain)"):format((SNAPSHOT_THROTTLE_SEC - (now-last_snapshot_t))*1000))
  end
  local t = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    t[g] = true
  end
  last_snapshot_t = now
  return t, n
end

local function sel_changed(old, new)
  for g in pairs(new) do if not old[g] then return true end end
  for g in pairs(old) do if not new[g] then return true end end
  return false
end

local function set_time_to_items()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then vlog("[set] no items, skip"); return false end
  local min_pos = math.huge
  local max_end = -math.huge
  for i=0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local L  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < min_pos then min_pos = p end
    if p+L > max_end then max_end = p+L end
  end
  reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
  log(("[set] time=%.3f → %.3f , items=%d"):format(min_pos, max_end, n))
  return true
end

----------------------------------------
-- State
----------------------------------------
local running = true
local sel_before, _ = snapshot_sel()
local rmb_watch_active = false
local rmb_started_t = -1
local rmb_release_t = -1
local frames_since_heavy = 0

----------------------------------------
-- Main loop
----------------------------------------
local function main()
  if not running then return end
  profiler_tick()

  local ev = mouse:tick()
  if DEBUG_VERBOSE then
    vlog(("tick blocked=%s lmb=%s rmb=%s"):format(tostring(ev.blocked), tostring(mouse.lmb), tostring(mouse.rmb)))
  end

  local now = reaper.time_precise()

  -- 進入右鍵會話
  if (not rmb_watch_active) and mouse.rmb_session == true then
    rmb_watch_active = true
    rmb_started_t = now
    sel_before = snapshot_sel()
    log(("[rmb] start t=%.3f sel=%d"):format(rmb_started_t, reaper.CountSelectedMediaItems(0)))
  end

  -- 右鍵放開之後，MouseLib 會先處於 blocked（冷卻/選單），等解除後 rmb_session=false & ev.blocked=false
  if rmb_watch_active and (mouse.rmb_session == false) and (ev.blocked == false) then
    -- 第一次到這裡記錄「放開時間」
    if rmb_release_t < 0 then rmb_release_t = now end
    local since_release = now - rmb_release_t

    -- 可設定放開後再等待一點點時間（避免 race）
    if since_release >= POST_RMB_COOLDOWN_SEC then
      -- 節流重工作業（snapshot + diff）
      if frames_since_heavy >= (MIN_FRAMES_BETWEEN_CHECKS or 0) then
        local sel_after = snapshot_sel()
        local changed = sel_changed(sel_before, sel_after)
        log(("[rmb] end dt=%.1f ms, changed=%s"):format((now - rmb_started_t)*1000.0, tostring(changed)))
        if changed then
          local t0 = reaper.time_precise()
          set_time_to_items()
          log(("[rmb] trigger latency=%.1f ms (release→set)"):format((t0 - rmb_release_t)*1000.0))
        end
        sel_before = sel_after
        rmb_watch_active = false
        rmb_started_t = -1
        rmb_release_t = -1
        frames_since_heavy = 0
      else
        frames_since_heavy = frames_since_heavy + 1
      end
    end
  end

  reaper.defer(main)
end

----------------------------------------
-- Toggle
----------------------------------------
if reaper.GetToggleCommandStateEx(sectionID, cmdID) == 1 then
  running = false
  set_toggle(false)
  log("[state] disabled")
else
  if DEBUG and DEBUG_CLEAR_ON_START then reaper.ShowConsoleMsg("") end
  set_toggle(true)
  log("[state] enabled")
  main()
end
