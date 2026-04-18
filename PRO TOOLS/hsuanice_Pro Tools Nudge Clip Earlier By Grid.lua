-- @description hsuanice_Pro Tools Nudge Clip Earlier By Grid
-- @version 0.2.0 [260418.1931]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools: **Nudge Clip Earlier By Grid**
--   Uses nudge value from hsuanice_Grid Nudge Panel (not grid size).
--   - Mac shortcut (PT): Numpad Minus
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

local has_items  = r.CountSelectedMediaItems(0) > 0
local has_razor  = false
for ti = 0, r.CountTracks(0)-1 do
  local _, s = r.GetSetMediaTrackInfo_String(r.GetTrack(0,ti), 'P_RAZOREDITS', '', false)
  if s and s ~= '' then has_razor = true; break end
end

if has_items then
  Nudge.apply(0, true)   -- nudge position left
elseif has_razor then
  -- Move razor areas: nudge cursor left, then re-apply razor
  Nudge.apply(6, true)   -- nudge edit cursor left
else
  Nudge.apply(6, true)   -- fallback: move edit cursor
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock('Pro Tools: Nudge Clip Earlier By Grid', -1)
