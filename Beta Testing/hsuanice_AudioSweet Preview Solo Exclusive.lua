--[[
@description AudioSweet Preview (loop play, item solo exclusive)
@author Hsuanice
@version 2510050105 One-tap toggle via Core
@about Toggle-style preview using hsuanice_AS Preview Core.lua (solo exclusive)
@changelog
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

if ASP.is_running() then
  -- 單次觸發 -> 切到相反模式（目前是 solo，就切 normal）
  ASP.log("entry(solo): running -> toggle")
  ASP.toggle_mode("solo")
else
  -- 尚未預覽 -> 以 solo 啟動
  ASP.log("entry(solo): start")
  ASP.run{ mode = "solo", focus_track = FXtrack, focus_fxindex = fxIndex }
end
