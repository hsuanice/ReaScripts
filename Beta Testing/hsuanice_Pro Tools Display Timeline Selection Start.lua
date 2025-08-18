--[[
@description Pro Tools - Display Timeline Selection Start
@version 0.1
@author hsuanice
@about
  Mimics Pro Tools' "Display Timeline Selection Start" behavior.  
    - Priority: Razor Edit > Time Selection > Item Selection.  
    - View scrolls to the start of the active selection without changing zoom level or play/edit cursor.  
    - Useful for navigating to timeline boundaries in a non-destructive way.  
    
  Features:
  - Designed for fast, keyboard-light workflows.
  - Integrates with Razor Edit regions when available.
  - Uses SWS extension APIs where available.

  References:
  - REAPER ReaScript API (Lua)
  - SWS Extension API

  Note:
  - This is a 0.1 beta release for internal testing.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.1 - Beta release
--]]

-- Keep current view size
local view_start, view_end = reaper.BR_GetArrangeView(0)
local view_width = view_end - view_start

-- Earliest start among all Razor Edit ranges
local function GetRazorEditStart()
  local earliest = nil
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    local ok, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    -- Format: "start end \"..." repeated
    for s, e in area:gmatch("([%d%.]+) ([%d%.]+) \"") do
      s = tonumber(s)
      if s and (not earliest or s < earliest) then
        earliest = s
      end
    end
  end
  return earliest
end

-- Time selection start (only if a time selection exists)
local function GetTimeSelStart()
  local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts_start ~= ts_end then return ts_start end
  return nil
end

-- Earliest left edge among selected items
local function GetItemSelStart()
  local earliest = nil
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    if not earliest or pos < earliest then
      earliest = pos
    end
  end
  return earliest
end

-- Priority: Razor > Time > Item
local pos = GetRazorEditStart() or GetTimeSelStart() or GetItemSelStart()
if not pos then return end

-- Place the start near 10% from the left edge, keep zoom unchanged
local new_start = math.max(pos - view_width * 0.1, 0)
local new_end   = new_start + view_width

reaper.BR_SetArrangeView(0, new_start, new_end)
