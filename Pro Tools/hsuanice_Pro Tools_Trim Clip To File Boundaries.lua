--[[
@description Pro Tools - Trim Clip To File Boundaries
@version 1.0
@author hsuanice

@about
  Emulates Pro Tools' "Trim Clip to File Boundaries" behavior.  
  - Extends both left and right edges of selected item(s) based on neighboring items.  
  - Falls back to full file start/end if no neighbors exist.  
  - Always respects file content bounds, avoiding empty/unrecorded areas.

  💡 Ideal for reclaiming full usable media without overshooting source boundaries.  
    Integrates well with hsuanice's Pro Tools-style editing workflow.

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
  local max_total_len = src_len / playrate
  local available_tail = max_total_len - (take_offset / playrate + len)

  local item_count = reaper.CountTrackMediaItems(track)
  local prev_edge = 0
  local next_pos = math.huge

  for j = 0, item_count - 1 do
    local other = reaper.GetTrackMediaItem(track, j)
    if other ~= item then
      local other_pos = reaper.GetMediaItemInfo_Value(other, "D_POSITION")
      local other_len = reaper.GetMediaItemInfo_Value(other, "D_LENGTH")
      local other_end = other_pos + other_len

      if other_end <= pos and other_end > prev_edge then
        prev_edge = other_end
      end
      if other_pos >= item_end and other_pos < next_pos then
        next_pos = other_pos
      end
    end
  end

  
  local want_extend = (next_pos < math.huge) and (next_pos - item_end) or available_tail
  local actual_extend = math.min(want_extend, available_tail)
  if actual_extend > 0 then
    len = len + actual_extend
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
    item_end = pos + len
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
reaper.Undo_EndBlock("Extend item both edges to item or full content", -1)
