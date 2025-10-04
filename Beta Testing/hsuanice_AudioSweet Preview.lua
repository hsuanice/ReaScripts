--[[
@description AudioSweet Preview (loop play, no solo)
@author Hsuanice
@version 2510042327
@about Toggle-style preview using hsuanice_AS Preview Core.lua
@changelog
  v2510042327 — Initial toggle entry for normal (non-solo) preview.
]]

-- 找到 Library 目錄並載入 Preview Core（同層的 /Library/）
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*/)")
local ASP = dofile(SCRIPT_DIR .. "Library/hsuanice_AS Preview Core.lua")

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

-- 用 ExtState 做簡單 toggle
local ES_KEY = "hsuanice_AS_PREVIEW_RUNNING"
local running = reaper.GetExtState("hsuanice_AS", ES_KEY) == "1"

if running then
  ASP.cleanup_if_any()
  reaper.SetExtState("hsuanice_AS", ES_KEY, "0", false)
else
  local FXtrack, fxIndex = get_focused_track_fx()
  if not FXtrack or not fxIndex then return end
  ASP.run{ mode = "normal", focus_track = FXtrack, focus_fxindex = fxIndex }
  reaper.SetExtState("hsuanice_AS", ES_KEY, "1", false)
end