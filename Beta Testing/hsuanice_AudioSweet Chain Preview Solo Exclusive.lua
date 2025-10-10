--[[
@description AudioSweet Chain Preview (solo exclusive; loop play; solo scope via ExtState) — full Track FX chain, no FX isolation
@author Hsuanice
@version 251010_1313 Switch wrapper to call ASP.preview({...}) unified API (mode=solo, chain, no isolate).
@about Toggle-style preview of the **entire Track FX chain** using hsuanice_AS Preview Core.lua (solo exclusive).
       This wrapper does **not** isolate a focused FX and **does not** change FX enable states.
@changelog
  v251010_1313
    - Added complete CHAIN Solo Exclusive implementation using ASP.run.
    - Retained full Track FX chain (no FX isolation).
    - Added focus dump logger for debugging current FX focus and track context.
    - Added fallback track resolver (focused track → "AudioSweet" named track).
    - Preserved SOLO_SCOPE ExtState ('track'|'item') and PREVIEW_MODE=solo.
    - Removed all FX enable/disable toggles for clean chain preview.
    - Switch wrapper to call ASP.preview({...}) unified API (mode=solo, chain, no isolate).
    - Stop writing PREVIEW_MODE ExtState; pass solo scope/flags via arguments.

  v251010_0051
    - Change to CHAIN preview: use full Track FX chain (no FX isolation).
    - Wrapper no longer requires a focused Track FX; it resolves a target track:
        1) Focused Track (if any), else 2) Track named "AudioSweet", else abort.
    - Do not pass focus_fxindex to Core; Core must NOT isolate FX.
    - Keep existing SOLO_SCOPE behavior (`track`|`item`) via ExtState.
    - Logging now indicates CHAIN target track.

]]--
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





-- 讀取/保存 SOLO_SCOPE（預設 'track'），供日志與 Core 使用
local current_scope = get_solo_scope_from_extstate("track")
set_solo_scope_to_extstate(current_scope)
-- Debug header：改用 Core 的 logger（dlog 只在 DEBUG=1 時輸出）
local DEBUG_ON = (reaper.GetExtState(NS, "DEBUG") == "1")
if ASP and ASP._state then ASP._state.DEBUG = DEBUG_ON end
if ASP and type(ASP.dlog) == "function" and DEBUG_ON then
  ASP.dlog("--- Solo Exclusive entry ---")
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

-- 偵錯：列印目前焦點 FX 與對應 Track
local function dump_focused_fx_to_console()
  local rv, trackNum, itemNum, fxNum = reaper.GetFocusedFX()
  local kind = "none"
  local tr = nil
  local name = ""
  if rv == 1 then
    if trackNum and trackNum > 0 then
      kind = "trackfx"
      tr = reaper.CSurf_TrackFromID(trackNum, false)
      if tr then
        local _, tn = reaper.GetTrackName(tr, "")
        name = tn or ""
      end
    elseif itemNum and itemNum >= 0 then
      kind = "takefx"
      local item = reaper.GetMediaItem(0, itemNum)
      if item then
        tr = reaper.GetMediaItem_Track(item)
        if tr then
          local _, tn = reaper.GetTrackName(tr, "")
          name = tn or ""
        end
      end
    end
  end
  local msg = ("[wrapper-solo][CHAIN][FOCUS] rv=%s kind=%s trackNum=%s itemNum=%s fxNum=%s trackName=%s"):format(
    tostring(rv), tostring(kind), tostring(trackNum), tostring(itemNum), tostring(fxNum), tostring(name)
  )
  if ASP and type(ASP.log) == "function" then ASP.log(msg) else reaper.ShowConsoleMsg(msg .. "\n") end
end
-- 解析目標 Track（CHAIN 版不需要 focused FX）
-- 規則：
--   1) 若有 Focused Track（不限是否聚焦到 FX），用該 Track。
--   2) 否則尋找名為 "AudioSweet" 的 Track。
--   3) 都沒有則跳出錯誤。
local function resolve_target_track()
  -- 先嘗試從 FocusedFX 取得目標：優先 Track FX，其次 Take FX 的母 Track
  local rv, trackNum, itemNum, fxNum = reaper.GetFocusedFX()
  if rv == 1 then
    if trackNum and trackNum > 0 then
      local tr = reaper.CSurf_TrackFromID(trackNum, false)
      if tr then return tr end
    elseif itemNum and itemNum >= 0 then
      local item = reaper.GetMediaItem(0, itemNum)
      if item then
        local tr = reaper.GetMediaItem_Track(item)
        if tr then return tr end
      end
    end
  end
  -- 找名為 "AudioSweet" 的 track（備援）
  local cnt = reaper.CountTracks(0)
  for i = 0, cnt-1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr, "")
    if name == "AudioSweet" then
      return tr
    end
  end
  reaper.MB(
    "No focused FX/track and no track named 'AudioSweet' found.\nFocus any FX (track or take), or create a track named 'AudioSweet'.",
    "AudioSweet Chain Preview",
    0
  )
  return nil
end



local FXtrack = resolve_target_track()
if not FXtrack then return end

-- 直接使用 MediaTrack 物件給 Core（CHAIN 模式不 isolate 單一 FX）
local track_ptr = FXtrack
if not track_ptr then
  reaper.MB("Failed to resolve target track pointer.", "AudioSweet Chain Preview", 0)
  return
end

-- 如 Core 仍會讀 _state，則同步寫入「物件」而非編號（避免 Core 誤用數字）
ASP._state.fx_track = track_ptr
ASP._state.fx_index = nil

-- ★ Solo wrapper 只宣告 PREVIEW_MODE=solo；Core 端不應 isolate FX
reaper.SetExtState(NS, "PREVIEW_MODE", "solo", false)

-- 顯示目前 SOLO_SCOPE / PREVIEW_MODE / 目標 Track 名稱（便於除錯）
local _, tr_name = reaper.GetTrackName(FXtrack, "")
if ASP and type(ASP.log) == "function" then
  ASP.log(("[wrapper-solo][CHAIN] SOLO_SCOPE=%s, PREVIEW_MODE=%s, target=%s")
    :format(current_scope, "solo", tr_name))
end

-- 額外列印目前「焦點 FX」狀態（可判斷是 Track FX 還是 Take FX、所在 Track）
dump_focused_fx_to_console()

-- 交由 Core 處理：
--   * focus_track 傳「編號或 MediaTrack 物件」→ 我們傳 MediaTrack 物件
--   * focus_fxindex=nil → Core 不 isolate 單一 FX（走整條 Track FX Chain）
--   * no_isolate=true（若 Core 支援此旗標，可更明確表達）
ASP.run{
  focus_track   = track_ptr,  -- MediaTrack 物件
  focus_fxindex = nil,        -- 不 isolate；整條 Track FX Chain
  no_isolate    = true,
}