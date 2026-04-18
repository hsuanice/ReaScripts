-- @description hsuanice_Pro Tools Nudge Clip Later By Grid
-- @version 0.1.4 [260415.1629]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools: **Nudge Clip Later By Grid**
--
--   ## Behaviour (all can happen simultaneously)
--   1. Items selected    → nudge items right by 1 grid, time selection follows
--   2. Razor area exists → nudge all razor areas right by 1 grid
--   3. Neither           → move edit cursor right by 1 grid (fallback)
--
--   - Mac shortcut (PT) : Numpad Plus
--   - Tags              : Editing
--
-- @changelog
--   0.1.4 [260415.1629]
--     - Add: nudge razor areas; fallback to edit cursor only when nothing selected
--   0.1.3 [260415.1620]
--     - Fix: time selection follows via Sync; no-item fallback moves cursor
--   0.1.1 [260415.1610]
--     - Fix: correct 1-grid measurement (Method D)
--   0.1.0 [260415.1600]
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

local function load_sync()
  local info = debug.getinfo(1, 'S').source:match("^@?(.*[/\\])")
  if not info then return nil end
  local ok, mod = pcall(dofile, info .. "../Library/hsuanice_PT_SelectionSync.lua")
  return ok and mod or nil
end

local function get_all_razor_areas()
  local areas = {}
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, razor_str = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor_str and razor_str ~= "" then
      local toks = {}
      for t in razor_str:gmatch("%S+") do toks[#toks+1] = t end
      for i = 1, #toks - 2, 3 do
        local s = tonumber(toks[i])
        local e = tonumber(toks[i+1])
        local g = toks[i+2]
        if s and e and e > s then
          areas[#areas+1] = { track=track, start=s, finish=e, guid=g }
        end
      end
    end
  end
  return areas
end

local function nudge_razor_areas(areas, delta)
  local by_track = {}
  for _, a in ipairs(areas) do
    local key = tostring(a.track)
    if not by_track[key] then by_track[key] = { track=a.track, areas={} } end
    by_track[key].areas[#by_track[key].areas+1] = a
  end
  for _, entry in pairs(by_track) do
    local parts = {}
    for _, a in ipairs(entry.areas) do
      local new_s = math.max(0, a.start + delta)
      local new_e = math.max(0, a.finish + delta)
      parts[#parts+1] = string.format("%.14f %.14f %s", new_s, new_e, a.guid)
    end
    r.GetSetMediaTrackInfo_String(entry.track, "P_RAZOREDITS", table.concat(parts, " "), true)
  end
end

-- ── Main ──────────────────────────────────────────────────────────────────

local sel_count   = r.CountSelectedMediaItems(0)
local razor_areas = get_all_razor_areas()
local has_items   = sel_count > 0
local has_razor   = #razor_areas > 0

if not has_items and not has_razor then
  local cursor  = r.GetCursorPosition()
  local grid_sz = get_grid_size_at(cursor)
  r.SetEditCurPos(cursor + grid_sz, true, false)
  return
end

local Sync = load_sync()

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

if has_items then
  for i = 0, sel_count - 1 do
    local item    = r.GetSelectedMediaItem(0, i)
    local pos     = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local grid_sz = get_grid_size_at(pos)
    r.SetMediaItemInfo_Value(item, "D_POSITION", pos + grid_sz)
  end
  if Sync then Sync.notify() end
end

if has_razor then
  local ref_pos = razor_areas[1].start
  local grid_sz = get_grid_size_at(ref_pos)
  nudge_razor_areas(razor_areas, grid_sz)
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Pro Tools: Nudge Clip Later By Grid", -1)
