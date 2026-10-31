--[[
@description Hover Editing - Nudge Take Volume Timer (background helper)
@version 26.1031.1833pre1
@author hsuanice
@noindex
@changelog
  - New: background timer for Nudge Take Volume with Mousewheel.
@about
  Started by "Hover Editing - Nudge Take Volume with Mousewheel"; not meant to be run by hand.
  Runs in the background only while a wheel burst is going on: once the wheel has been still
  long enough it writes one undo point for the whole burst, clears the value display and stops.
--]]
local NS = "hsuanice_HoverWheelVol"
local function ext_num(k) return tonumber(reaper.GetExtState(NS, k)) end
local function ext_set(k, v) reaper.SetExtState(NS, k, tostring(v), false) end

reaper.atexit(function() ext_set("alive", "") end)

local function loop()
  local now = reaper.time_precise()
  ext_set("alive", now)

  local tip = ext_num("tip_until")
  if tip and now >= tip then
    reaper.TrackCtl_SetToolTip("", 0, 0, true)
    ext_set("tip_until", "")
    tip = nil
  end

  local burst = ext_num("burst_db")
  if burst and now - (ext_num("last_time") or 0) >= (ext_num("merge_s") or 1) then
    ext_set("burst_db", "")
    reaper.Undo_OnStateChange2(0, string.format("Nudge take volume %+.1f dB", burst))
    burst = nil
  end

  if burst or tip then reaper.defer(loop) end
end

loop()
