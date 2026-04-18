-- @description hsuanice_Pro Tools Repeat
-- @version 0.1.3 [260415.1629]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Replicates Pro Tools: **Repeat**
--
--   ## Behaviour
--   - Error shown first if no items selected
--   - Dialog: "Number Of Repeats:" (matches Pro Tools)
--   - Remembers last entered value across sessions
--   - Each repeat placed on the SAME track as source, ignoring track selection
--   - Only newly created items are selected after repeat
--   - Notifies hsuanice_PT_SelectionSync so active link daemons update immediately
--   - Undo in one step
--
--   - Mac shortcut (PT) : Option + R
--   - Tags              : Edit menu, Editing
--
-- @changelog
--   0.1.3 [260415.1629]
--     - Add: calls hsuanice_PT_SelectionSync.notify() after selection change
--   0.1.2 [260415.1620]
--     - Fix: use GetItemStateChunk/SetItemStateChunk for proper item copy
--   0.1.1 [260415.1615]
--     - Fix: error before dialog if no selection; track-aware placement
--   0.1.0 [260415.1600]
--     - Initial release

local r = reaper

-- Load SelectionSync library (same directory as this script → ../Library/)
local function load_sync()
  local info = debug.getinfo(1, 'S').source:match("^@?(.*[/\\])")
  if not info then return nil end
  local lib_path = info .. "../Library/hsuanice_PT_SelectionSync.lua"
  local ok, mod = pcall(dofile, lib_path)
  return ok and mod or nil
end
local Sync = load_sync()

local EXT_SECTION = "hsuanice_PT2Reaper"
local EXT_KEY     = "Repeat_LastCount"

-- Helper: deep-copy an item onto a track at new_pos via state chunk
local function copy_item_to(src_item, dst_track, new_pos)
  local _, chunk = r.GetItemStateChunk(src_item, "", false)
  local tmp = r.AddMediaItemToTrack(dst_track)
  local new_guid = r.BR_GetMediaItemGUID(tmp)
  r.DeleteTrackMediaItem(dst_track, tmp)
  chunk = chunk:gsub("IGUID {[^}]+}", "IGUID " .. new_guid)
  local new_item = r.AddMediaItemToTrack(dst_track)
  r.SetItemStateChunk(new_item, chunk, false)
  r.SetMediaItemInfo_Value(new_item, "D_POSITION", new_pos)
  r.UpdateItemInProject(new_item)
  return new_item
end

-- 1. Check selection FIRST
local sel_count = r.CountSelectedMediaItems(0)
if sel_count == 0 then
  r.ShowMessageBox("No items selected.", "Repeat", 0)
  return
end

-- 2. Ask for count
local last_val = r.GetExtState(EXT_SECTION, EXT_KEY)
if last_val == "" then last_val = "2" end
local ok, input = r.GetUserInputs("Repeat", 1, "Number Of Repeats:,extrawidth=80", last_val)
if not ok or input == "" then return end

local count = math.floor(tonumber(input) or 0)
if count < 1 then
  r.ShowMessageBox("Please enter a number greater than 0.", "Repeat", 0)
  return
end
r.SetExtState(EXT_SECTION, EXT_KEY, tostring(count), true)

-- 3. Snapshot sources
local sources   = {}
local sel_start = math.huge
local sel_end   = 0

for i = 0, sel_count - 1 do
  local item  = r.GetSelectedMediaItem(0, i)
  local track = r.GetMediaItemTrack(item)
  local pos   = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len   = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  sources[#sources + 1] = { item=item, track=track, pos=pos, len=len }
  if pos < sel_start then sel_start = pos end
  if pos + len > sel_end then sel_end = pos + len end
end

local block_len = sel_end - sel_start

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local new_items = {}

for rep = 1, count do
  local offset = block_len * rep
  for _, s in ipairs(sources) do
    local new_item = copy_item_to(s.item, s.track, s.pos + offset)
    new_items[#new_items + 1] = new_item
  end
end

-- Select only new items
r.Main_OnCommand(40289, 0) -- Unselect all items
for _, item in ipairs(new_items) do
  r.SetMediaItemSelected(item, true)
end

-- Notify link daemons
if Sync then Sync.notify() end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Pro Tools: Repeat x" .. count, -1)
