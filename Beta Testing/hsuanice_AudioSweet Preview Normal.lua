--[[
@description AudioSweet Preview (loop play, no solo)
@author Hsuanice
@version 2510052130 OK Solo scope via ExtState (track|item)
@about Toggle-style preview using hsuanice_AS Preview Core.lua
@changelog
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

-- 本腳本的預設 Preview 模式（這支是非 solo）
local TARGET_MODE = "normal"

-- 找到 Library 目錄並載入 Preview Core（同層的 /Library/；找不到就往上一層找）
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*/)")

local function try_dofile(path)
  local f = io.open(path, "r")
  if f then f:close(); return dofile(path), path end
  return nil, path
end

local lib_rel = "Library/hsuanice_AS Preview Core.lua"
local ASP, p1 = try_dofile(SCRIPT_DIR .. lib_rel)

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

-- 共享 ExtState（與 Core 統一）：只用新 NS
local ES_NS = "hsuanice_AS"

-- ExtState helpers (generic)
local function es_get(key) return reaper.GetExtState(ES_NS, key) end
local function es_set(key, val, persist) reaper.SetExtState(ES_NS, key, tostring(val or ""), persist == true) end

-- Ensure a default SOLO_SCOPE for Core (track|item). Default = track.
local solo_scope = es_get("SOLO_SCOPE")
if solo_scope == nil or solo_scope == "" then
  es_set("SOLO_SCOPE", "track", true) -- persist user's default choice
  solo_scope = "track"
end

-- 取得目前 Focused FX
local FXtrack, fxIndex = get_focused_track_fx()
if not FXtrack or not fxIndex then return end

-- ★ 統一寫入新鍵值給 Core：只負責宣告目標模式與 solo 範圍，其餘交給 Core 判斷
es_set("PREVIEW_MODE", TARGET_MODE, false)
-- SOLO_SCOPE 已在上面確保預設，如需在此覆寫也可：
-- es_set("SOLO_SCOPE", "track", true) -- 或 "item"

-- 記錄 wrapper 狀態（除錯用）
reaper.ShowConsoleMsg(("[wrapper-normal] SOLO_SCOPE=%s, PREVIEW_MODE=%s\n"):format(solo_scope, TARGET_MODE))

-- 直接交 Core 執行（不再傳 mode，讓 Core 從 ExtState 讀）
ASP.run{ focus_track = FXtrack, focus_fxindex = fxIndex }
