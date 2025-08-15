--[[
@description Pro Tools - Trim Clip To File Boundaries
@version 0.1.1
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
  
  Features:
  - Designed for fast, keyboard-light workflows.
  
  References:
  - REAPER ReaScript API (Lua)
  
  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
  
@changelog
  v0.1.1 - Fix: items stretched beyond source by "SWS/AW: Trim selected items to fill selection"
           could create a blank loop on the left (negative D_STARTOFFS). Now:
           • Left side is clamped back to true file start (D_STARTOFFS → 0).
           • Right side overrun/loop is unlooped and clamped to file end.
           • normalize_loop_and_clamp() refactor to handle both sides robustly.
           • Turn off B_LOOPSRC before clamping to honor pref 42218.
           • Minor: take_offset/playrate/src_len declared local (avoid globals).
           • Behavior preserved: never overlaps neighbors; fades untouched.
  v0.1   - Beta release
--]]
reaper.Undo_BeginBlock()

local num_items = reaper.CountSelectedMediaItems(0)
if num_items == 0 then return end

-- Drop-in replacement for normalize_loop_and_clamp()
local function normalize_loop_and_clamp(item, take)
  -- Read current geometry
  local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  rate = math.max(1e-12, rate)

  local src  = reaper.GetMediaItemTake_Source(take)
  local src_len, isQN = reaper.GetMediaSourceLength(src)
  if isQN then return len, offs, rate, src_len end

  -- ---- Right-side: unloop + clamp to file end ----
  local max_len_from_offs = math.max(0, (src_len - offs) / rate)

  if reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1 or len > max_len_from_offs + 1e-9 then
    -- turn off looping so 42218 can actually constrain the item
    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
    if len > max_len_from_offs then
      len = max_len_from_offs
      reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
    end
  end

  -- ---- Left-side: clamp if start offset went negative (blank loop on the left) ----
  if offs < 0 then
    local overshoot = (-offs) / rate     -- seconds exceeded before file start
    local new_pos   = pos + overshoot
    local new_len   = math.max(0, len - overshoot)

    reaper.SetMediaItemInfo_Value(item, "D_POSITION", new_pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH",   new_len)
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)

    -- update locals so callers see the corrected geometry
    pos  = new_pos
    len  = new_len
    offs = 0
  end

  return len, offs, rate, src_len
end

for i = 0, num_items - 1 do
  local item = reaper.GetSelectedMediaItem(0, i)
  local track = reaper.GetMediaItemTrack(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local item_end = pos + len
  local take = reaper.GetActiveTake(item)

  if not take or reaper.TakeIsMIDI(take) then goto continue end

  -- Normalize loop/length first (handles both right overrun and left blank-loop)
  local take_offset, playrate, src_len
  len, take_offset, playrate, src_len = normalize_loop_and_clamp(item, take)
  pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  item_end = pos + len

  local max_total_len = src_len / math.max(1e-12, playrate)
  local available_tail = max_total_len - (take_offset / playrate + len)
  if available_tail < 0 then available_tail = 0 end

  -- Find neighbors on the same track
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

  -- Extend right edge up to next item or file end
  local want_extend = (next_pos < math.huge) and (next_pos - item_end) or available_tail
  local actual_extend = math.min(want_extend, available_tail)
  if actual_extend > 0 then
    len = len + actual_extend
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", len)
    item_end = pos + len
  end

  -- Reveal left edge up to previous item or file start
  local max_reveal = (take_offset / playrate)
  local want_reveal = pos - prev_edge
  local actual_reveal = math.min(want_reveal, math.max(0, max_reveal))
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
