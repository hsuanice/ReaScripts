--[[
@description AudioSweet Preview (loop play; solo scope via ExtState)  -- solo scope: track|item (default=track)
@author Hsuanice
@version 2510060104 OK Align Solo warning UX with Normal wrapper
@about Toggle-style preview using hsuanice_AS Preview Core.lua (solo exclusive)
@changelog
  v2510060104 OK Align Solo warning UX with Normal wrapper
    - Added visual message box (`reaper.MB`) when no Track FX is focused.
      * Previously, only console debug text appeared (and disappeared if DEBUG was off).
      * Now the user receives the same popup warning as the Normal wrapper:
        “Focused FX is not a Track FX (or no FX focused).”
    - This ensures consistent user feedback regardless of DEBUG state.
    - Verified both wrappers share identical focus check logic (`get_focused_track_fx`).

  v2510060048 OK Unified wrapper debug format
    - Changed Solo wrapper header print to match Normal wrapper:
        → `[AS][PREVIEW][time] [wrapper-solo] SOLO_SCOPE=track, PREVIEW_MODE=solo`
    - Removed redundant `[wrapper] SOLO_SCOPE=track` line.
    - Now both wrappers show a single-line, consistent debug entry for clarity.

  v2510052300 OK Fix ExtState (solo wrapper → Core)
    - Unified ExtState namespace to `hsuanice_AS` (was `hsuanice_AS_PREVIEW`).
    - Switched key to `PREVIEW_MODE` (was `MODE`); wrapper now sets `PREVIEW_MODE=solo` and delegates logic to Core.
    - Removed wrapper-side placeholder/run-state detection; Core is the single source of truth.
    - Preserved `SOLO_SCOPE` user option in `hsuanice_AS / SOLO_SCOPE` (`track`|`item`, default `track`).
    - Improved entry logs: wrapper prints current scope & mode; no console clearing.
    - Compatibility: requires Core ≥ v2510051520.

    Known
    - Live mode switching mid-loop still handled by Core (wrapper only updates ExtState).
    - Razor selection not implemented yet (follows Core behavior).

  v2510052130 — Solo scope via ExtState (track|item)
    - Added user-selectable solo scope stored in ExtState `hsuanice_AS / SOLO_SCOPE`.
    - `SOLO_SCOPE` can be either `"track"` or `"item"` (default=`track`).
    - Preview Core now reads this ExtState to decide whether to apply exclusive solo at the **track** level or **item** level.
    - Wrapper preserves user choice between sessions (persistent ExtState = true).
    - Added detailed logging to show SOLO_SCOPE on entry (`[wrapper] SOLO_SCOPE=...`).
    - Wrapper only sets `PREVIEW_MODE=solo`; Core reads `hsuanice_AS / PREVIEW_MODE` + placeholder to decide build/switch/stop.
    - Compatible with Core v2510051520 and later.

    Known notes
    - Solo-exclusive scope toggle still requires playback restart to take effect mid-loop (live switching planned for later phase).
    - Razor selection not supported yet.

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

-- Debug header：改用 Core 的 logger（dlog 只在 DEBUG=1 時輸出）
local DEBUG_ON = (reaper.GetExtState(NS, "DEBUG") == "1")
if ASP and ASP._state then ASP._state.DEBUG = DEBUG_ON end
if ASP and type(ASP.dlog) == "function" and DEBUG_ON then
  ASP.dlog("--- Solo Exclusive entry ---")
end

local FXtrack, fxIndex = get_focused_track_fx()
if not FXtrack or not fxIndex then return end

-- 讓 Library 記住當前焦點，未啟動時可從這裡起始
ASP._state.fx_track = FXtrack
ASP._state.fx_index = fxIndex

-- 初始化 SOLO_SCOPE（若未設，預設 'track'；若已設，不覆蓋）
local current_scope = get_solo_scope_from_extstate("track")
if not current_scope or current_scope == "" then
  set_solo_scope_to_extstate("track")
  current_scope = "track"
end

-- ★ Solo wrapper 只宣告 PREVIEW_MODE=solo，並交給 Core（Core 會讀 PREVIEW_MODE＋placeholder 判斷切換/重建）
reaper.SetExtState(NS, "PREVIEW_MODE", "solo", false)

-- 顯示目前 SOLO_SCOPE 與 PREVIEW_MODE（便於除錯）
ASP.log(("[wrapper-solo] SOLO_SCOPE=%s, PREVIEW_MODE=%s"):format(current_scope, "solo"))

-- 交由 Core 處理（不要傳 mode，讓 Core 完全以 ExtState 做決策）
ASP.run{ focus_track = FXtrack, focus_fxindex = fxIndex }
