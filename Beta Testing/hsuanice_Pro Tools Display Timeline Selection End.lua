--[[
@description Pro Tools - Display Timeline Selection End
@version 0.2 beta x
@author hsuanice

@about
  Mimics Pro Tools' "Display Timeline Selection End" behavior.
    - Priority: Razor Edit > Time Selection > Item Selection.
    - Keeps zoom level and play/edit cursor; only scrolls the view.
    - User option (below metadata): set an "anchor" ratio so the end appears at N% of the viewport width.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.2 - Add top-of-file USER OPTION for anchor (0..1 or % string).
  v0.1 - Beta release
--]]

-- === USER OPTIONS ===
-- Put 0..1 or a percent string. Examples: 0.6  |  "60%"
local USER_ANCHOR = "40%"   -- default for END (place end at 60% from left)

-- === Dependency check (SWS) ===
if not (reaper and reaper.BR_GetArrangeView and reaper.BR_SetArrangeView) then
  reaper.ShowMessageBox("SWS extension is required (BR_Get/SetArrangeView).", "Missing dependency", 0)
  return
end

-- === Helpers ===
local function parse_user_anchor(v, fallback)
  if v == nil then return fallback end
  local t = type(v)
  if t == "number" then
    if v > 1 then v = v / 100 end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
  elseif t == "string" then
    local s = v:match("^%s*(.-)%s*$"):gsub("%%","")
    local n = tonumber(s)
    if not n then return fallback end
    if n > 1 then n = n / 100 end
    if n < 0 then n = 0 elseif n > 1 then n = 1 end
    return n
  end
  return fallback
end

-- === Query current view (keep zoom) ===
local view_start, view_end = reaper.BR_GetArrangeView(0)
local view_width = (view_end or 0) - (view_start or 0)
if view_width <= 0 then return end

-- === Selection queries (priority: Razor > Time > Item) ===
local function GetRazorEditEnd()
  local latest = nil
  for t = 0, reaper.CountTracks(0)-1 do
    local track = reaper.GetTrack(0, t)
    local ok, area = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    for s,e in (area or ""):gmatch("([%d%.]+) ([%d%.]+) \"") do
      e = tonumber(e)
      if e and (not latest or e > latest) then latest = e end
    end
  end
  return latest
end

local function GetTimeSelEnd()
  local ts_s, ts_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts_s ~= ts_e then return ts_e end
  return nil
end

local function GetItemSelEnd()
  local latest = nil
  for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    local it   = reaper.GetSelectedMediaItem(0, i)
    local pos  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local right = pos + len
    if not latest or right > latest then latest = right end
  end
  return latest
end

-- === Compute target and scroll ===
local anchor = parse_user_anchor(USER_ANCHOR, 0.9)  -- fallback = 90%
local pos = GetRazorEditEnd() or GetTimeSelEnd() or GetItemSelEnd()
if not pos then return end

local new_start = math.max(pos - view_width * anchor, 0)
local new_end   = new_start + view_width
reaper.BR_SetArrangeView(0, new_start, new_end)
