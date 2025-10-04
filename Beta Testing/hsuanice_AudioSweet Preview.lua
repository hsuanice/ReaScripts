--[[
@description AudioSweet Preview (loop play, no solo)
@author Hsuanice
@version 2510050105 WIP — Stub to Core, pending original-mute snapshot
@about Toggle-style preview using hsuanice_AS Preview Core.lua
@changelog
  v2510050105 WIP — Stub to Core, pending original-mute snapshot
    - ✅ Move/restore flow works.
    - 🐞 Originals are not auto-muted during preview, so playback doubles (FX-track copy + originals). Needs “mute-snapshot + restore” in Core.
    - ❗ Same pop-up dialog appears when toggling.  
    - Calls Preview Core to start in NORMAL mode; if already running, a single trigger flips to SOLO without stopping.
    - Shares the same focused-FX discovery path as the Solo script for consistent routing to the FX track.
    - Inherits Core’s loop arming, stop watcher, and debug stream.

    Known issues
    - Preventing level doubling: original items are not yet auto-muted during normal preview (next patch will add snapshot & restore).
    - Same single-track guard and no-Razor limitation as the Core for now.
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

-- 共享 ExtState：兩支腳本共用，以支持「自切換 + 互切換」
local ES_NS = "hsuanice_AS_PREVIEW"

local function get_state()
  local run = reaper.GetExtState(ES_NS, "RUN") == "1"
  local mode = reaper.GetExtState(ES_NS, "MODE")
  return run, mode
end

local function set_state(run, mode)
  reaper.SetExtState(ES_NS, "RUN", run and "1" or "0", false)
  if mode then reaper.SetExtState(ES_NS, "MODE", mode, false) end
end

local function is_playing()
  -- bit1 表示正在播放
  return (reaper.GetPlayState() & 1) == 1
end

-- 取得目前 Focused FX
local FXtrack, fxIndex = get_focused_track_fx()
if not FXtrack or not fxIndex then return end

-- 共享 ExtState：兩支腳本共用，以支持「自切換 + 互切換」
local ES_NS = "hsuanice_AS_PREVIEW"
local function get_state()
  local run = reaper.GetExtState(ES_NS, "RUN") == "1"
  local mode = reaper.GetExtState(ES_NS, "MODE")
  return run, mode
end
local function set_state(run, mode)
  reaper.SetExtState(ES_NS, "RUN", run and "1" or "0", false)
  if mode then reaper.SetExtState(ES_NS, "MODE", mode, false) end
end

local running, curmode = get_state()

-- 規則（不再依賴「當下是否播放」）：
-- - 若已有 session：
--     * 同模式 → 停止（toggle off）
--     * 不同模式 → 熱切換（不中斷播放）
-- - 若沒有 session → 以目標模式啟動
if running then
  if curmode == TARGET_MODE then
    -- 同模式 → 停止
    set_state(false, curmode)  -- 先寫狀態，避免第二次執行讀到舊值
    ASP.cleanup_if_any({ restore_playstate = true })
  else
    -- 不同模式 → 切換（不中斷播放）
    set_state(true, TARGET_MODE) -- 先寫 MODE，避免「要按兩次」
    if ASP.switch_mode then
      ASP.switch_mode{ mode = TARGET_MODE, focus_track = FXtrack, focus_fxindex = fxIndex }
    else
      -- 向後相容：沒有 switch_mode 時，直接 run 相同會覆寫模式
      ASP.run{ mode = TARGET_MODE, focus_track = FXtrack, focus_fxindex = fxIndex }
    end
  end
else
  -- 尚未運行 → 啟動指定模式
  set_state(true, TARGET_MODE) -- 先寫 MODE，再啟動
  ASP.run{ mode = TARGET_MODE, focus_track = FXtrack, focus_fxindex = fxIndex }
end
