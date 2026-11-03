--[[
@description Dual Recorder Sync - DRS Set Reference Track (the selected track, e.g. the 2nd mix-in of the first recorder)
@version 26.1103.2023
@author hsuanice
@noindex
@changelog
  - Initial release
@about
  Remembers the selected track as the reference track for "Dual Recorder Sync - DRS Waveform
  Sync" (saved in the project). Run it again with no track selected to see the current one.

  Written with Claude Code (AI); designed and tested by hsuanice.
--]]
local r = reaper
local TITLE = "Dual Recorder Sync - Reference Track"
local NS, KEY = "hsuanice_DRS", "REF_TRACK"

local tr = r.GetSelectedTrack(0, 0)
if not tr then
  local _, guid = r.GetProjExtState(0, NS, KEY)
  local cur = guid ~= "" and r.BR_GetMediaTrackByGUID and r.BR_GetMediaTrackByGUID(0, guid)
  if not cur and guid ~= "" then
    for i = 0, r.CountTracks(0) - 1 do
      local t = r.GetTrack(0, i)
      if r.GetTrackGUID(t) == guid then cur = t; break end
    end
  end
  local name = cur and select(2, r.GetTrackName(cur)) or "(none)"
  r.MB("Select one track, then run this again.\n\nCurrent reference track: " .. name, TITLE, 0)
  return
end
if r.CountSelectedTracks(0) > 1 then
  r.MB("Select only one track: the reference (e.g. the 2nd mix-in of the first recorder).", TITLE, 0)
  return
end
r.SetProjExtState(0, NS, KEY, r.GetTrackGUID(tr))
r.MarkProjectDirty(0)
local _, name = r.GetTrackName(tr)
r.MB("Reference track: " .. name, TITLE, 0)
