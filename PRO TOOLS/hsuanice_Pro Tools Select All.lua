-- @description hsuanice_Pro Tools Select All
-- @version 0.1.1 [260416.1347]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Replicates Pro Tools: **Select All**
--
--   ## Behaviour
--   Selects all items on the selected track(s), then sets time selection
--   and razor area to cover the full span of selected items —
--   mirroring PT's "Select All sets Edit Selection" behaviour.
--
--   - Mac shortcut (PT) : Command + A
--   - Tags              : Edit menu, Editing
--
-- @changelog
--   0.1.1 [260416.1347]
--     - Rewrite: now sets time selection + razor to cover all items
--   0.1.0 [260416.1323]
--     - Initial release (simple 40421 map)

local r = reaper

local function load_sync()
  local info = debug.getinfo(1, 'S').source:match("^@?(.*[/\\])")
  if not info then return nil end
  local ok, mod = pcall(dofile, info .. "../Library/hsuanice_PT_SelectionSync.lua")
  return ok and mod or nil
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- 1. Select all items on selected tracks
r.Main_OnCommand(40421, 0) -- Item: Select all items in track

local n = r.CountSelectedMediaItems(0)
if n == 0 then
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Pro Tools: Select All", -1)
  return
end

-- 2. Find bounding box of all selected items
local min_pos = math.huge
local max_end = -math.huge

for i = 0, n - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  local pos  = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len  = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  if pos < min_pos then min_pos = pos end
  if pos + len > max_end then max_end = pos + len end
end

-- 3. Set time selection
r.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)

-- 4. Set razor area on all selected tracks
for ti = 0, r.CountTracks(0) - 1 do
  local track = r.GetTrack(0, ti)
  if r.GetMediaTrackInfo_Value(track, "I_SELECTED") == 1 then
    local razor_str = string.format('%.14f %.14f ""', min_pos, max_end)
    r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", razor_str, true)
  end
end

-- 5. Move edit cursor to start
local Sync = load_sync()
if Sync then Sync.cursor_follow() end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Pro Tools: Select All", -1)
