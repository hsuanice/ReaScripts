-- @description Toggle Mute Item under Mouse Cursor
-- @version 260318.1353
-- @author hsuanice
-- @changelog
--   260318.1353 # Fix GetItemFromPoint argument order
--   260318.1200 # Initial release

local mx, my = reaper.GetMousePosition()
local item, _ = reaper.GetItemFromPoint(mx, my, true)
if not item then return end

local muted = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
reaper.SetMediaItemInfo_Value(item, "B_MUTE", muted == 1 and 0 or 1)
reaper.UpdateItemInProject(item)

reaper.Undo_OnStateChangeEx2(
  nil,
  muted == 1 and "Unmute item under mouse cursor" or "Mute item under mouse cursor",
  -1, -1
)
