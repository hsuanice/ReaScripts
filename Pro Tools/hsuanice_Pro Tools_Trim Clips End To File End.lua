--[[
@description Pro Tools - Trim Clips End To File End
@version 1.0
@author hsuanice

@about
  Emulates Pro Tools' "Trim Clip End to File End" behavior.  
  - Extends the right edge of selected item(s) to the next item's start, or to the source media end.  
  - Prevents extending into unrecorded/empty content area.  
  - Automatically respects source limits and adjusts for playrate and offset.

  💡 Ideal for reclaiming usable audio content without overshooting media length.  
    Integrates well with hsuanice's Pro Tools-style timeline workflows.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.  
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v1.0 - Initial release
--]]

reaper.Undo_BeginBlock()

local num_items = reaper.CountSelectedMediaItems(0)
if num_items == 0 then return end

for i = 0, num_items - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local track = reaper.GetMediaItemTrack(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = pos + len
  local take = reaper.GetActiveTake(item)

  if not take or reaper.TakeIsMIDI(take) then goto continue end

  local take_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local source = reaper.GetMediaItemTake_Source(take)
  local src_len, isQN = reaper.GetMediaSourceLength(source)
  if isQN then goto continue end

  
  local max_total_len = src_len / playrate
  local available_tail = max_total_len - (take_offset / playrate + len)

  
  local next_pos = math.huge
  local item_count = reaper.CountTrackMediaItems(track)
  for j = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, j)
    if other ~= item then
      local other_pos = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      if other_pos >= item_end and other_pos < next_pos then
        next_pos = other_pos
      end
    end
  end

  local want_extend = (next_pos < math.huge) and (next_pos - item_end) or available_tail
  local actual_extend = math.min(want_extend, available_tail)

  if actual_extend > 0 then
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len + actual_extend)
  end

  ::continue::
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Extend item right edge to next item or full content", -1)
