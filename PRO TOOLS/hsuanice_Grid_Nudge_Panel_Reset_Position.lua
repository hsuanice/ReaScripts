-- @description hsuanice_Grid Nudge Panel - Reset Position
-- @version 1.0
-- @about Run this to reset the Grid Nudge Panel position back to default.

local EXT = 'hsuanice_GridNudgePanel'
reaper.DeleteExtState(EXT, 'screen_x', true)
reaper.DeleteExtState(EXT, 'screen_y', true)
reaper.DeleteExtState(EXT, 'bm_x', true)
reaper.DeleteExtState(EXT, 'bm_y', true)
reaper.DeleteExtState(EXT, 'attach_title', true)
reaper.ShowMessageBox('Position reset! Restart Grid Nudge Panel to see changes.', 'Reset', 0)
