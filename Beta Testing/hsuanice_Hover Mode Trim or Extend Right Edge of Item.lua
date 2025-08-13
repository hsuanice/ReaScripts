--[[
@description Hover Mode - Trim or Extend Right Edge of Item (Preserve Fade)
@version 0.1
@author hsuanice

@about
  Trims or extends the **right edge** of audio/MIDI/empty items depending on context.  
  - Hover Mode ON: Uses mouse cursor position.  
  - Hover Mode OFF: Uses edit cursor and selected tracks.  
  - 🧠 Special behavior: When the mouse is hovering over the **Ruler (Timeline)**, the script temporarily switches to **Edit Cursor Mode**, even if Hover Mode is enabled.  
  - Preserves existing fade-out shape and position.  
  - Ignores invisible items; partial visibility is accepted.

  💡 Supports extensible hover-edit system. Hover Mode is toggled via ExtState:  
    hsuanice_TrimTools / HoverMode  

  Inspired by:
    • X-Raym: Trim Item Edges — Script: X-Raym_Trim right edge of item under mouse or the previous one to mouse cursor without changing fade-out start.lua  
@changelog
  v0.1 - Initial beta release with trim/extend logic, fade preservation, and edit fallback behavior.
--]]

local is_hover = (reaper.GetExtState("hsuanice_TrimTools", "HoverMode") == "true")

function IsMouseOverTimeline()
  if not reaper.JS_Window_FromPoint then return false end
  local x, y = reaper.GetMousePosition()
  local hwnd = reaper.JS_Window_FromPoint(x, y)
  return hwnd and reaper.JS_Window_GetClassName(hwnd) == "REAPERTimeDisplay"
end

function IsItemVisible(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local right = pos + len
  local view_start, view_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  return right >= view_start and pos <= view_end
end

function AdjustFadeOut(item, old_end, new_end)
  local fade_len = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  local fade_start = old_end - fade_len
  if math.abs(fade_len) < 0.00001 then
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
    return
  end
  local new_fade = math.max(0, new_end - fade_start)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", new_fade)
end

function FindItems_Mouse()
  local x, y = reaper.GetMousePosition()
  local pos = reaper.BR_PositionAtMouseCursor(true)
  if not pos then return pos, {} end

  local track = reaper.GetTrackFromPoint(x, y)
  if not track then return pos, {} end

  local inside = nil
  local extend_from = nil
  local min_dist = math.huge

  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos_i = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local end_i = pos_i + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if pos > pos_i and pos < end_i then
      inside = item
      break
    elseif math.abs(end_i - pos) < 0.00001 then
      -- cursor exactly at end of item → do NOT count as inside
    elseif end_i <= pos and (pos - end_i < min_dist) then
      extend_from = item
      min_dist = pos - end_i
    end
  end

  if inside then
    return pos, {{ item = inside, mode = "trim" }}
  elseif extend_from then
    return pos, {{ item = extend_from, mode = "extend" }}
  else
    return pos, {}
  end
end

function FindItems_EditMode()
  local pos = reaper.GetCursorPosition()
  local list = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, i)
    local inside, best_left = nil, -math.huge
    local extend_target = nil
    for j = 0, reaper.CountTrackMediaItems(track) - 1 do
      local item = reaper.GetTrackMediaItem(track, j)
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_end = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if pos > item_pos and pos < item_end then
        inside = item
        break
      elseif item_end <= pos and item_end > best_left then
        extend_target = item
        best_left = item_end
      end
    end
    if inside then
      table.insert(list, { item = inside, mode = "trim" })
    elseif extend_target then
      table.insert(list, { item = extend_target, mode = "extend" })
    end
  end
  return pos, list
end

function TrimOrExtendRight(entry, target_pos)
  local item = entry.item
  if not IsItemVisible(item) then return end
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local endpos = pos + len
  local take = reaper.GetActiveTake(item)
  local is_midi = take and reaper.TakeIsMIDI(take)
  local is_empty = not take

  local max_right = (is_empty or is_midi) and math.huge or (pos + reaper.GetMediaSourceLength(reaper.GetMediaItemTake_Source(take)))
  local new_end = math.max(math.min(target_pos, max_right), pos + 0.001)
  local new_len = new_end - pos

  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
  AdjustFadeOut(item, endpos, new_end)
end

-- Main
local items, target_pos = {}, 0
local from_ruler = false

if is_hover then
  if IsMouseOverTimeline() then
    target_pos, items = FindItems_EditMode()
    from_ruler = true
  else
    target_pos, items = FindItems_Mouse()
  end
else
  target_pos, items = FindItems_EditMode()
end

if is_hover and not from_ruler and reaper.GetToggleCommandState(1157) == 1 then
  target_pos = reaper.SnapToGrid(0, target_pos)
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
for _, entry in ipairs(items) do TrimOrExtendRight(entry, target_pos) end
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Trim or extend item right edge (hover/edit mode)", -1)

