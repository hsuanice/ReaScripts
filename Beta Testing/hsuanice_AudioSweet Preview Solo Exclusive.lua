--[[
@description AudioSweet Preview (loop play, item solo exclusive)
@author Hsuanice
@version 2510051520 WIP 修toggle
@about Toggle-style preview using hsuanice_AS Preview Core.lua (solo exclusive)
@changelog
  v2510051520 WIP — Toggle via ExtState + placeholder guard (Solo wrapper)
    - Wrapper no longer relies on in-memory is_running(); it now detects “preview running” by scanning the focused FX track for the placeholder item note prefix ("PREVIEWING @ ...").
    - Uses project ExtState (hsuanice_AS_PREVIEW / MODE) to store current preview mode.
    - If placeholder exists: a single trigger flips MODE (solo ↔ normal) in ExtState only — no rebuild, no extra placeholders.
    - If not running: sets MODE=solo and calls Core once to start preview.
    - Keeps console logs persistent (does not clear), making step-by-step debugging easier.

    Known notes (still WIP, untested)
    - Core must poll ExtState MODE and switch item-solo/FX-bypass live; wrapper only flips the flag.
    - Normal wrapper should receive the same placeholder/ExtState logic to allow cross-wrapper toggling without rebuilds.
    - Razor edits not yet considered (follows Core).
    
  v2510050105 WIP — One-tap toggle via Core
    - ✅ Items are sent to the focused FX track for loop-play and get restored on stop.
    - ⚠️ Behavior looks like “copy + mute originals”; originals return to their prior mute state after stop. (OK for now.)
    - ❗ When re-triggering to toggle modes, REAPER pops the “ReaScript task control” dialog. See “How to avoid the dialog” below.
    - Uses Preview Core API to start in SOLO mode; if already running, a single trigger flips to NORMAL without stopping.
    - Remembers current focused FX (track/index) and hands them to Core for consistent preview routing.
    - Continuous debug marker on entry (“--- Solo Exclusive entry ---”) when DEBUG=1 to aid step-by-step tracing.
    - Stop playback automatically cleans up (via Core’s watcher), removing preview copies and restoring selection/repeat.

    Known issues
    - Requires all selected items to be on the same track (multi-track selection will be guarded in a later iteration).
    - Razor edits not supported yet; follows Core behavior (TS or selected items).

  v251004 — Initial toggle entry for solo-exclusive preview.
]]

-- 找到 Library 目錄並載入 Preview Core（同層的 /Library/；找不到就往上一層找）
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*/)")

local function try_dofile(path)
  local f = io.open(path, "r")
  if f then f:close(); return dofile(path), path end
  return nil, path
end

local lib_rel = "Library/hsuanice_AS Preview Core.lua"
local ASP, p1 = try_dofile(SCRIPT_DIR .. lib_rel)

-- === Solo wrapper helpers (project-scoped) ===
local NS = "hsuanice_AS_PREVIEW"
local NOTE_PREFIX = "PREVIEWING @ "  -- placeholder item note 前綴

-- 掃描 FX 軌是否存在 placeholder（以 item note 前綴識別）
local function has_placeholder_on_fx_track(FXtrack)
  if not FXtrack then return false end
  local item_cnt = reaper.CountTrackMediaItems(FXtrack)
  for i = 0, item_cnt-1 do
    local it = reaper.GetTrackMediaItem(FXtrack, i)
    local ok, note = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
    if ok and note and note:find(NOTE_PREFIX, 1, true) == 1 then
      return true
    end
  end
  return false
end

-- 讀/寫 ExtState 的目前模式（core 亦會使用）
local function get_mode_from_extstate(default_mode)
  local m = reaper.GetExtState(NS, "MODE")
  if m == nil or m == "" then return default_mode end
  return m
end

local function set_mode_to_extstate(mode)
  reaper.SetExtState(NS, "MODE", mode, true) -- persist = true
end

if not ASP then
  -- 往上一層資料夾找（把 SCRIPT_DIR 最後一段砍掉）
  local parent = SCRIPT_DIR:match("^(.-)[^/]+/?$") or SCRIPT_DIR
  local ASP2, p2 = try_dofile(parent .. lib_rel)
  if not ASP2 then
    reaper.MB(
      ("Cannot load hsuanice_AS Preview Core.lua.\nTried:\n- %s\n- %s"):format(p1, p2),
      "AudioSweet Preview", 0
    )
    return
  end
  ASP = ASP2
end


-- 取得目前 Focused FX 的 Track 與 FX Index（僅支援 Track FX）
local function get_focused_track_fx()
  local rv, trackNum, itemNum, fxNum = reaper.GetFocusedFX()
  if rv & 1 ~= 1 then
    reaper.MB("Focused FX is not a Track FX (or no FX focused).", "AudioSweet Preview", 0)
    return nil, nil
  end
  local tr = reaper.CSurf_TrackFromID(trackNum, false)
  if not tr then
    reaper.MB("Cannot resolve focused FX track.", "AudioSweet Preview", 0)
    return nil, nil
  end
  return tr, fxNum
end

-- Debug console：只在 DEBUG=1 時持續輸出
if reaper.GetExtState("hsuanice_AS", "DEBUG") == "1" then
  -- 不清空，累積看比較容易追
  reaper.ShowConsoleMsg("[AS][PREVIEW] --- Solo Exclusive entry ---\n")
end

local FXtrack, fxIndex = get_focused_track_fx()
if not FXtrack or not fxIndex then return end

-- 讓 Library 記住當前焦點，未啟動時可從這裡起始
ASP._state.fx_track = FXtrack
ASP._state.fx_index = fxIndex

-- 讀目前 ExtState 的模式（若未設，預設以 'solo' 起手）
local current_mode = get_mode_from_extstate("solo")

-- 用「FX 軌是否存在 placeholder」判斷 Core 是否在跑
if has_placeholder_on_fx_track(FXtrack) then
  -- Core 正在跑 ➜ 單次觸發就直接切到相反模式（不重建、不搬移）
  local new_mode = (current_mode == "solo") and "normal" or "solo"
  set_mode_to_extstate(new_mode)
  ASP.log(("entry(solo): running -> toggle %s → %s"):format(current_mode, new_mode))
  -- 交給 Core 的 watcher 讀取 ExtState 後切換（不會新增 placeholder）
  return
end

-- Core 未在跑 ➜ 設定為 solo 並啟動一次
set_mode_to_extstate("solo")
ASP.log("entry(solo): start")
ASP.run{ mode = "solo", focus_track = FXtrack, focus_fxindex = fxIndex }
