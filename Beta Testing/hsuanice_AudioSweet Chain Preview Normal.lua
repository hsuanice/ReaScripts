--[[
@description AudioSweet Chain Preview (loop play, no solo)
@author Hsuanice
@version 251010_1313 Chain Normal Mode OK
@about Toggle-style preview using hsuanice_AS Preview Core.lua
@changelog
  v251010_1313 — Chain Normal Mode OK
    - Fixed: Chain-mode (no solo) could not start preview due to focused FX dependency.
    - Changed: Removed all get_focused_track_fx() logic; now delegates target resolution to Core’s ASP._resolve_target().
    - Added: Wrapper now calls ASP.preview{ chain_mode=true, mode="normal" }, letting Core handle fallback and FX resolution.
    - Improved: No isolate or FX enable toggling in Chain Mode; track FX chain is kept as-is.
    - Confirmed: All modes (Solo, Normal, Chain Solo, Chain Normal) now function correctly with Core unified interface.

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


-- Debug header：改用 Core 的 logger（dlog 只在 DEBUG=1 時輸出）
local DEBUG_ON = (reaper.GetExtState(NS, "DEBUG") == "1")
if ASP and ASP._state then ASP._state.DEBUG = DEBUG_ON end
if ASP and type(ASP.dlog) == "function" and DEBUG_ON then
  ASP.dlog("--- Chain Normal (no solo) entry ---")
end

-- 初始化 SOLO_SCOPE（若未設，預設 'track'；若已設，不覆蓋）
local current_scope = get_solo_scope_from_extstate("track")
if not current_scope or current_scope == "" then
  set_solo_scope_to_extstate("track")
  current_scope = "track"
end

-- 顯示目前 SOLO_SCOPE 與 PREVIEW_MODE（便於除錯）
if ASP and type(ASP.log) == "function" then
  ASP.log(("[wrapper-normal][CHAIN] SOLO_SCOPE=%s, PREVIEW_MODE=%s"):format(current_scope, "normal"))
end

-- ✅ 直接使用 Core 的統一入口（Chain 模式；不 isolate、不動 FX enable/offline）
if ASP and type(ASP.preview) == "function" then
  ASP.preview{
    mode         = "normal",        -- loop play, no solo
    target       = "focused",       -- 若無焦點會在 Core 內 fallback -> name:AudioSweet
    chain_mode   = true,            -- Chain 模式：不 isolate
    solo_scope   = current_scope,   -- "track" / "item"
    restore_mode = "guid",          -- 清理時用 GUID collect
    debug        = DEBUG_ON,
  }
else
  reaper.MB("ASP.preview() not found in Core. Please update hsuanice_AS Preview Core.lua.", "AudioSweet Chain Preview", 0)
end