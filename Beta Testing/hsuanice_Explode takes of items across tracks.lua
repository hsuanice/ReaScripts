--[[
@description hsuanice_Explode takes of items across tracks
@version 260324.1235
@author hsuanice
@about
  Runs REAPER's built-in "Take: Explode takes of items across tracks" (action 40224)
  and then renames all resulting tracks based on the source track name.

  Items with only 1 take are copied to all new tracks (action 40224 normally
  leaves them only on the source track).

  Example: source track "EDL - A1" with items that have 3 takes → results in:
    EDL - A1          (source track, untouched)
    EDL - A1 - 1
    EDL - A1 - 2
    EDL - A1 - 3

@changelog
  v260324.1235
  - Single-take items are copied to only the first new track (one copy).
  v260322.1715
  - Single-take items are now copied to all new tracks (reverted — caused duplicates).
  v260322.1712
  - New tracks now inherit the source track's color.
  v260322.1710
  - Source track is now left untouched; new tracks are numbered from 1.
  v260322.1638
  - Back to wrapping action 40224 for correct take-cropping behaviour.
  v260322.1624
  - Rewritten with manual clone approach (incorrect — reverted).
  v260322.1552
  - Initial release.
]]

local r = reaper

-- ========== helpers ==========

local function get_track_name(tr)
  local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return name
end

local function set_track_name(tr, name)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
end

-- ========== snapshot tracks before action ==========

-- Record every existing track GUID so we can detect new ones afterward.
local before_guids = {}
local track_count_before = r.CountTracks(0)
for i = 0, track_count_before - 1 do
  local tr = r.GetTrack(0, i)
  before_guids[r.GetTrackGUID(tr)] = true
end

-- For each source track (has at least one selected item): record name, color,
-- and the state chunks of selected items that have only 1 take.
local source_names       = {}  -- GUID -> track name
local source_colors      = {}  -- GUID -> track color
local single_take_chunks = {}  -- GUID -> list of item state chunk strings

for i = 0, track_count_before - 1 do
  local tr   = r.GetTrack(0, i)
  local guid = r.GetTrackGUID(tr)
  local has_selected = false

  for j = 0, r.CountTrackMediaItems(tr) - 1 do
    local item = r.GetTrackMediaItem(tr, j)
    if r.IsMediaItemSelected(item) then
      if not has_selected then
        has_selected         = true
        source_names[guid]   = get_track_name(tr)
        source_colors[guid]  = r.GetTrackColor(tr)
        single_take_chunks[guid] = {}
      end
      -- Snapshot items that have only 1 take for later re-placement.
      if r.GetMediaItemNumTakes(item) == 1 then
        local ok, chunk = r.GetItemStateChunk(item, "", false)
        if ok then
          table.insert(single_take_chunks[guid], chunk)
        end
      end
    end
  end
end

if next(source_names) == nil then
  r.ShowMessageBox(
    "No selected items found.\nPlease select items with multiple takes first.",
    "Explode Takes Across Tracks", 0)
  return
end

-- ========== run action ==========

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

r.Main_OnCommand(40224, 0)  -- Take: Explode takes of items across tracks

-- ========== rename resulting tracks + collect new track refs ==========
--
-- After 40224, new tracks are inserted immediately after each source track.
-- We walk the full track list; new tracks (GUID not in before_guids) belong
-- to the most recent source track context.

local cur_source_guid  = nil
local cur_source_name  = nil
local cur_source_color = nil
local cur_take_idx     = 0
local new_tracks_by_source = {}  -- GUID -> ordered list of new track objects

for i = 0, r.CountTracks(0) - 1 do
  local tr   = r.GetTrack(0, i)
  local guid = r.GetTrackGUID(tr)

  if before_guids[guid] then
    if source_names[guid] then
      cur_source_guid  = guid
      cur_source_name  = source_names[guid]
      cur_source_color = source_colors[guid]
      cur_take_idx     = 0
      new_tracks_by_source[guid] = new_tracks_by_source[guid] or {}
    else
      cur_source_guid  = nil
      cur_source_name  = nil
      cur_source_color = nil
      cur_take_idx     = 0
    end
  else
    -- New track created by action 40224.
    if cur_source_name then
      cur_take_idx = cur_take_idx + 1
      set_track_name(tr, cur_source_name .. " - " .. cur_take_idx)
      if cur_source_color and cur_source_color ~= 0 then
        r.SetTrackColor(tr, cur_source_color)
      end
      table.insert(new_tracks_by_source[cur_source_guid], tr)
    end
  end
end

-- ========== copy single-take items to the first new track only ==========
--
-- action 40224 leaves items that had only 1 take only on the source track.
-- Copy each such item once to the first new track for that source.

for guid, chunks in pairs(single_take_chunks) do
  if #chunks > 0 then
    local new_tracks = new_tracks_by_source[guid]
    if new_tracks and #new_tracks > 0 then
      local first_new_tr = new_tracks[1]
      for _, chunk in ipairs(chunks) do
        local new_item = r.AddMediaItemToTrack(first_new_tr)
        r.SetItemStateChunk(new_item, chunk, false)
      end
    end
  end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Explode takes across tracks (renamed)", -1)
