-- @description hsuanice_Pro Tools Nudge Clip Later By Grid
-- @version 0.2.0 [260418.1931]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools: **Nudge Clip Later By Grid**
--   Uses nudge value from hsuanice_Grid Nudge Panel (not grid size).
--   - Mac shortcut (PT): Numpad Plus
--   - Tags: Editing
-- @changelog
--   0.2.0 [260418.1931]
--     - Rewrite: use ApplyNudge with hsuanice_PT_Nudge library
--   0.1.4 [260415.1629]
--     - Add: nudge razor areas; fallback to edit cursor only when nothing selected

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

local has_items = r.CountSelectedMediaItems(0) > 0

if has_items then
  Nudge.apply(0, false)  -- nudge position right
else
  Nudge.apply(6, false)  -- fallback: move edit cursor
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock('Pro Tools: Nudge Clip Later By Grid', -1)
