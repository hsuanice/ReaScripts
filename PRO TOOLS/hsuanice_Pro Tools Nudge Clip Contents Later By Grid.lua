-- @description hsuanice_Pro Tools Nudge Clip Contents Later By Grid
-- @version 0.2.0 [260418.1931]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools: **Nudge Clip Contents Later By Grid**
--   Nudges the contents (audio offset) of selected items later.
--   Uses nudge value from hsuanice_Grid Nudge Panel.
--   - Tags: Editing
-- @changelog
--   0.2.0 [260418.1931] - Rewrite: use ApplyNudge with hsuanice_PT_Nudge library

local r = reaper
local info = debug.getinfo(1,'S')
local dir  = info.source:match('^@(.+)[\\/]') or ''
local ok, Nudge = pcall(dofile, dir .. '/hsuanice_PT_Nudge.lua')
if not ok then
  r.ShowMessageBox('Could not load hsuanice_PT_Nudge.lua\n' .. tostring(Nudge), 'Error', 0)
  return
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
Nudge.apply(4, false)  -- nudge contents right (nudgewhat=4)
r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock('Pro Tools: Nudge Clip Contents Later By Grid', -1)
