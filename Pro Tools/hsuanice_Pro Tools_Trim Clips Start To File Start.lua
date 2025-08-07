--[[
@description Pro Tools - Trim Clips Start To File Start
@version 1.0
@author hsuanice

@about
  Emulates Pro Tools' "Trim Clip Start to File Start" behavior.  
  - Extends the left edge of selected item(s) to the previous item's end, or to the source media start.  
  - Prevents revealing beyond recorded content, preserving original sync and offset.

  💡 Useful for reclaiming pre-roll or missed in-point material without shifting content.  
    Integrates well with hsuanice's Pro Tools-style clip editing and timeline workflows.

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

  local max_reveal = take_offset / playrate

  
  local prev_edge = 0 
  local item_count = reaper.CountTrackMediaItems(track)
  for j = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, j)
    if other ~= item then
      local other_pos = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      local other_len = reaper.GetMediaItemInfo_Value(other, "D_LENGTH")
      local other_end = other_pos + other_len
      if other_end <= pos and other_end > prev_edge then
        prev_edge = other_end
      end
    end
  end

  local want_reveal = pos - prev_edge
  local actual_reveal = math.min(want_reveal, max_reveal)

  if actual_reveal > 0 then
    local new_pos = pos - actual_reveal
    local new_len = item_end - new_pos
    local new_offset = take_offset - (actual_reveal * playrate)

    reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offset)
  end

  ::continue::
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Extend item left edge to prev item or full content", -1)
