--[[
@description AudioSweet Preview (loop play, no solo)
@author Hsuanice
@version 251010_1313 Confirmed stable operation of Normal wrapper after fallback and Core refactor.
@about Toggle-style preview using hsuanice_AS Preview Core.lua
@changelog
  v251010_1313
    - Confirmed stable operation of Normal wrapper after fallback and Core refactor.
    - Added consistent behavior with Solo and Chain variants (silent fallback, no dialog).
    - Verified placeholder lifecycle, loop handling, and cleanup are identical across modes.
    - Confirmed Core correctly restores FX enables and item positions.
    - Behavior verified under both focused-FX and fallback-to-AudioSweet conditions.

  v2510060046 — Align normal wrapper behavior with solo version
    - Removed any blocking checks that prevented Core from running when `fxIndex == 0`.
    - Unified initialization logic with Solo wrapper to ensure consistent startup and ExtState propagation.
    - Eliminated redundant placeholder scanning (FX track only); Core now handles all placement and lifecycle.
    - Normal mode now correctly passes `PREVIEW_MODE="normal"` to Core, ensuring no solo-exclusive action is triggered.
    - Confirmed wrapper no longer triggers modal dialogs or extra message boxes.

  v2510060008 — Fix debug switch
    - Removed leftover debug output from wrapper ("[wrapper-normal] SOLO_SCOPE=track, PREVIEW_MODE=normal").
    - Wrapper now respects Core’s internal debug toggle only.
    - Ensured no redundant ExtState or print() calls remain in wrapper.

  v2510052130 — OK Solo scope via ExtState (track|item)
    - ExtState namespace unified to `hsuanice_AS` (no legacy keys).
    - Wrapper now only sets `PREVIEW_MODE="normal"` and (if empty) `SOLO_SCOPE`, then calls Core.
    - Toggle/switch/stop logic is handled entirely by Core using placeholder + PREVIEW_MODE.

  v2510051520 WIP — Normal wrapper aligned (no mute)
    - Normal vs Solo difference is now **only** whether Core runs 41561 (Item: Solo exclusive) on the moved preview items.
    - Removed any mention/plan of “mute originals” – no longer needed (both modes always move items off the source track).
    - Cleaned duplicate ExtState helpers in this wrapper.

    Known
    - REAPER’s “ReaScript task control” dialog can still appear when re-running while Core is running. You can allow “New instance” & remember, or disable the warning globally.  
    - Toggle-once behavior depends on Core’s `switch_mode` (which flips 41561 state without rebuilding).
  v2510042327 — Initial toggle entry for normal (non-solo) preview.
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

-- === Wrapper helpers (project-scoped; shared with solo) ===
-- 統一與 Core 相同命名空間
local NS = "hsuanice_AS"
local NOTE_PREFIX = "PREVIEWING @ "  -- placeholder item note 前綴

-- Solo 範圍：'track' 或 'item'，由 ExtState 控制
local function get_solo_scope_from_extstate(default_scope)
  local s = reaper.GetExtState(NS, "SOLO_SCOPE")
  if not s or s == "" then return default_scope end
  return s
end

local function set_solo_scope_to_extstate(scope)
  -- 僅接受 'track' | 'item'
  if scope ~= "track" and scope ~= "item" then return end
  reaper.SetExtState(NS, "SOLO_SCOPE", scope, true) -- persist=true
end



-- （可選）若要保留 API 外型：鍵改成 PREVIEW_MODE
local function set_preview_mode_to_extstate(mode)
  reaper.SetExtState(NS, "PREVIEW_MODE", mode or "", false) -- 不需 persist
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


-- 取得目前 Focused FX 的 Track 與 FX Index（僅支援 Track FX；失敗則回傳 nil,nil）
local function get_focused_track_fx()
  local rv, trackNum, itemNum, fxNum = reaper.GetFocusedFX()
  if (rv & 1) ~= 1 then
    -- 無聚焦或非 Track FX：交給呼叫端決定 fallback
    if ASP and type(ASP.log) == "function" then
      ASP.log("[wrapper-normal] no focused Track FX (rv=" .. tostring(rv) .. ")")
    end
    return nil, nil
  end
  local tr = reaper.CSurf_TrackFromID(trackNum, false)
  if not tr then
    if ASP and type(ASP.log) == "function" then
      ASP.log("[wrapper-normal] cannot resolve focused FX track (trackNum=" .. tostring(trackNum) .. ")")
    end
    return nil, nil
  end
  return tr, fxNum
end

-- 名稱尋軌（單純比對可見名；大小寫不敏感）
local function find_track_by_name(name)
  if not name or name == "" then return nil end
  local want = name:lower()
  local cnt = reaper.CountTracks(0)
  for i = 0, cnt-1 do
    local tr = reaper.GetTrack(0, i)
    local _, trname = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if trname and trname:lower() == want then
      return tr
    end
  end
  return nil
end

-- Debug header：改用 Core 的 logger（dlog 只在 DEBUG=1 時輸出）
local DEBUG_ON = (reaper.GetExtState(NS, "DEBUG") == "1")
if ASP and ASP._state then ASP._state.DEBUG = DEBUG_ON end
if ASP and type(ASP.dlog) == "function" and DEBUG_ON then
  ASP.dlog("--- Normal (no solo) entry ---")
end

local FXtrack, fxIndex = get_focused_track_fx()
if not FXtrack then
  -- Fallback：嘗試以 "AudioSweet" 軌作為預覽目標（與 Chain 行為一致）
  FXtrack = find_track_by_name("AudioSweet")
  if ASP and type(ASP.log) == "function" then
    ASP.log(("[wrapper-normal] focus missing; fallback to track='%s': %s")
      :format("AudioSweet", FXtrack and "HIT" or "MISS"))
  end
  -- 若找不到 fallback，這次就不做事（安靜結束）
  if not FXtrack then return end
  fxIndex = 0  -- 無特定 FX；交由 Core 以 track 為目標處理
end

-- 讓 Library 記住當前焦點（或 fallback）
ASP._state.fx_track  = FXtrack
ASP._state.fx_index  = fxIndex

-- 初始化 SOLO_SCOPE（若未設，預設 'track'；若已設，不覆蓋）
local current_scope = get_solo_scope_from_extstate("track")
if not current_scope or current_scope == "" then
  set_solo_scope_to_extstate("track")
  current_scope = "track"
end
-- （不在 wrapper 印 log；統一使用 Core 的 debug 控制）

-- 額外印 focused FX（僅在 DEBUG 開時會出）
if ASP and type(ASP.dlog) == "function" and DEBUG_ON then
  local guid = reaper.GetTrackGUID(FXtrack) or "?"
  ASP.dlog(("focused FX: trackGUID=%s  fxIndex=%d"):format(guid, fxIndex or -1))
end

-- ★ Normal wrapper 只宣告 PREVIEW_MODE=normal，並交給 Core（Core 會讀 PREVIEW_MODE＋placeholder 判斷切換/重建）
reaper.SetExtState(NS, "PREVIEW_MODE", "normal", false)

if ASP and type(ASP.log) == "function" then
  local _, trname = reaper.GetSetMediaTrackInfo_String(FXtrack, "P_NAME", "", false)
  ASP.log(("[wrapper-normal] SOLO_SCOPE=%s, PREVIEW_MODE=%s, target=%s%s")
    :format(current_scope, "normal", trname or "?", (fxIndex and fxIndex > 0) and (" (fxIndex=" .. fxIndex .. ")") or ""))
end

ASP.run{ focus_track = FXtrack, focus_fxindex = fxIndex }
