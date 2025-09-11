-- @description Set Time to Item on Right-Drag Release (Toggle)
-- @version 0.4.0
-- @author hsuanice
-- @about
--   偵測「右鍵拖曳 → 放開」這段操作（不限於 marquee），在釋放後（含右鍵選單冷卻結束）把
--   「目前被選取的 items」之最小開始/最大結束設定為 time selection。
--   若右鍵只是點擊、或拖曳後 selection 沒有變化，則不動。
--   需要 hsuanice_Mouse.lua（會自動多路徑尋找，含 `/Scripts/hsuanice Scripts/Library/`）。
--
-- @changelog
--   v0.4.0  新：改為偵測「右鍵拖曳」釋放後觸發；以 selection 是否改變作為保險；保留 toolbar toggle。
--   v0.3.x  MouseUp on marquee（舊邏輯）
--   v0.2.0  加入 toolbar toggle
--   v0.1.0  初版

----------------------------------------
-- Toggle helpers
----------------------------------------
local _, _, sectionID, cmdID = reaper.get_action_context()

local function set_toggle(state)
  reaper.SetToggleCommandState(sectionID, cmdID, state and 1 or 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
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
  -- 嘗試與本腳本同資料夾
  local info = debug.getinfo(1, "S")
  local this_dir = (info and info.source or ""):match("^@(.+[\\/])")
  if this_dir then
    table.insert(candidates, this_dir .. "hsuanice_Mouse.lua")
    table.insert(candidates, this_dir .. "Library/hsuanice_Mouse.lua")
  end

  for _, p in ipairs(candidates) do
    if file_exists(p) then
      local ok, lib = pcall(dofile, p)
      if ok and type(lib) == "table" and lib.new then return lib end
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
local mouse = MouseLib.new{ debug = false }

----------------------------------------
-- Selection helpers
----------------------------------------
local function snapshot_sel()
  local t = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    t[g] = true
  end
  return t
end

local function sel_changed(old, new)
  for g in pairs(new) do if not old[g] then return true end end
  for g in pairs(old) do if not new[g] then return true end end
  return false
end

local function set_time_to_items()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return end
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
end

----------------------------------------
-- State
----------------------------------------
local running = true
local sel_before = snapshot_sel()
local rmb_watch_active = false   -- 是否正在監看一段 RMB session
local rmb_started_t = -1         -- RMB session 開始時間（資訊用）
-- MouseLib 內部會在 rmb 期間「blocked」整段過程，並於冷卻後解除。

----------------------------------------
-- Main loop
----------------------------------------
local function main()
  if not running then return end

  local ev = mouse:tick()
  -- 只要呼叫了 tick()，即使 blocked，MouseLib 也已更新自身的 rmb_session 狀態。

  local now = reaper.time_precise()
  -- 1) RMB session 起點：偵測開始監看（當 MouseLib 內判斷進入 RMB session 會把回傳標成 blocked）
  if (not rmb_watch_active) and mouse.rmb_session == true then
    rmb_watch_active = true
    rmb_started_t = now
    sel_before = snapshot_sel()  -- 記錄開始前的 selection
  end

  -- 2) RMB session 結束：等到 MouseLib 清掉 rmb_session（含選單/冷卻期都結束）
  --    這時檢查 selection 是否變化，若有就 set time。
  if rmb_watch_active and (mouse.rmb_session == false) and (ev.blocked == false) then
    rmb_watch_active = false
    local sel_after = snapshot_sel()
    if sel_changed(sel_before, sel_after) then
      set_time_to_items()
    end
    sel_before = sel_after
  end

  reaper.defer(main)
end

----------------------------------------
-- Toggle
----------------------------------------
if reaper.GetToggleCommandStateEx(sectionID, cmdID) == 1 then
  running = false
  set_toggle(false)
else
  sel_before = snapshot_sel()
  set_toggle(true)
  main()
end
