--[[
@description Pro Tools - Display Timeline Selection End
@version 1.0
@author hsuanice

@about
  Mimics Pro Tools' "Display Timeline Selection End" behavior.  
  - Priority: Razor Edit > Time Selection > Item Selection.  
  - View scrolls to the end of the active selection without changing zoom level or play/edit cursor.  
  - Useful for navigating to timeline boundaries in a non-destructive way.  
  

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.  
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v1.0 - Initial release
--]]

local view_start, view_end = reaper.BR_GetArrangeView(0)
local view_width = view_end - view_start

local function GetRazorEditEnd()
  local latest = nil
  for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    local ok, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    for s, e in area:gmatch("([%d%.]+) ([%d%.]+) \"") do
      e = tonumber(e)
      if not latest or e > latest then
        latest = e
      end
    end
  end
  return latest
end

local function GetTimeSelEnd()
  local start_time, end_time = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if start_time ~= end_time then return end_time else return nil end
end

local function GetItemSelEnd()
  local latest = nil
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local right = pos + len
    if not latest or right > latest then latest = right end
  end
  return latest
end

local pos = GetRazorEditEnd() or GetTimeSelEnd() or GetItemSelEnd()
if not pos then return end

local new_start = math.max(pos - view_width * 0.9, 0)
local new_end = new_start + view_width

reaper.BR_SetArrangeView(0, new_start, new_end)
