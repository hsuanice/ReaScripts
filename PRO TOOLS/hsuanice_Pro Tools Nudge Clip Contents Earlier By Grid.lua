-- @description hsuanice_Pro Tools Nudge Clip Contents Earlier By Grid
-- @version 0.1.1 [260416.1336]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Replicates Pro Tools: **Nudge Clip Contents Earlier By Grid**
--
--   Shifts the content (start offset) of selected audio items earlier
--   by 1 grid division. Item position and length remain unchanged.
--
--   - Mac shortcut (PT) : Command + Numpad Minus
--   - Tags              : Editing
--
-- @changelog
--   0.1.1 [260416.1336]
--     - Remove: no selection sync or cursor follow (content-only nudge)
--   0.1.0 [260416.1323]
--     - Initial release

local r = reaper

local function get_grid_size_at(pos)
  local prev_g       = r.BR_GetPrevGridDivision(pos)
  local next_of_prev = r.BR_GetNextGridDivision(prev_g + 0.0001)
  local interval     = next_of_prev - prev_g
  if interval > 0 then return interval end
  local division = r.GetSetProjectGrid(0, false)
  local bpm      = r.GetProjectTimeSignature2(0)
  return (60.0 / bpm) * division * 4
end

local sel_count = r.CountSelectedMediaItems(0)
if sel_count == 0 then
  r.ShowMessageBox("No items selected.", "Nudge Clip Contents Earlier By Grid", 0)
  return
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

for i = 0, sel_count - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  local take = r.GetActiveTake(item)
  if take and not r.TakeIsMIDI(take) then
    local pos     = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local grid_sz = get_grid_size_at(pos)
    local offs    = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", math.max(0, offs - grid_sz))
  end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Pro Tools: Nudge Clip Contents Earlier By Grid", -1)
