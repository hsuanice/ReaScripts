--[[
  @description Pro Tools Extend Edit Insertion Up (Expand razor area upward by one track)
  @author hsuanice
  @version 1.0.0
  @about Expand existing Razor Edit area upward by exactly one track. If no Razor Edit exists, move to previous track and select items crossing the edit cursor (PT-style convenience).
  @changelog
    v1.0.0 - Initial release (mirror of "down by one track" logic but scanning bottom->top to expand upward; PT-style fallback when no razor area)
  @links
    - Based on technique of propagating P_RAZOREDITS one track (see reference "Resize razor edit down by one track.lua")
]]

local r = reaper

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local GetSetTrackInfo = r.GetSetMediaTrackInfo_String

-- Expand razor area UP: scan from bottom to top, clone first encountered razor to the first empty track above it
local has_razor_edit = false
local carry_razor = nil

for i = r.CountTracks(0) - 1, 0, -1 do
  local tr = r.GetTrack(0, i)
  local _, razor = GetSetTrackInfo(tr, 'P_RAZOREDITS', '', false)

  if razor ~= '' then
    has_razor_edit = true
    carry_razor = razor  -- remember the topmost (so far) razor definition while moving upward
  elseif carry_razor then
    -- The first empty track above a razor area: copy the same razor area here, then stop carrying
    GetSetTrackInfo(tr, 'P_RAZOREDITS', carry_razor, true)
    carry_razor = nil
    -- NOTE: Do not break; continuing allows behavior to be identical to the "down" script style if multiple blocks exist.
    -- If you'd prefer to only ever expand the very topmost group once, uncomment the next line:
    -- break
  end
end

-- PT-style fallback: if there was no razor area at all, move to previous track and select items crossing edit cursor
if not has_razor_edit then
  -- Track: Go to previous track (mirror of 40285 "next track" used by the down script)
  r.Main_OnCommand(40286, 0)

  local cursor_pos = r.GetCursorPosition()
  r.SelectAllMediaItems(0, false)

  -- Select all items on selected tracks that cross the edit cursor (strict > for end with a tiny epsilon like the reference)
  for t = 0, r.CountSelectedTracks(0) - 1 do
    local tr = r.GetSelectedTrack(0, t)
    local cnt = r.CountTrackMediaItems(tr)
    for i = 0, cnt - 1 do
      local it = r.GetTrackMediaItem(tr, i)
      local len = r.GetMediaItemInfo_Value(it, 'D_LENGTH')
      local pos = r.GetMediaItemInfo_Value(it, 'D_POSITION')
      local endpos = pos + len

      if pos <= cursor_pos and (endpos - 0.0001) > cursor_pos then
        r.SetMediaItemSelected(it, true)
      end

      if pos > cursor_pos then
        break
      end
    end
  end
  r.UpdateArrange()
end

r.PreventUIRefresh(-1)
r.Undo_EndBlock('Pro Tools Extend Edit Insertion Up (expand razor area upward)', -1)
