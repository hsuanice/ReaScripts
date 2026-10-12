--[[
@description Toggle Mute Item under Mouse Cursor
@version 26.1012.0736
@author hsuanice
@changelog
  - First release in the hsuanice/ReaScripts repository.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  ## Suggested shortcuts
  - Toggle Mute Item under Mouse Cursor: Control+M

  Shortcuts are suggestions only — nothing is assigned automatically. macOS names; on Windows Cmd = Ctrl, Option = Alt, Control = Win.
--]]
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
