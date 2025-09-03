--[[
@description Delete Selected Tracks (safe: skip prompt if empty; prompt if folder parents with children)
@version 0.2.0
@author hsuanice
@about
  Delete selected tracks with safety:
    • If ALL selected tracks are empty (no items, no automation/envelope data) AND none of them is a folder parent with children, delete immediately with no prompt.
    • If ANY selected track contains items or automation, OR is a folder parent that currently has child tracks, show a summary and ask for confirmation.
    • When no track is selected, show an info message.

  Definitions:
    - "Automation present" = any track envelope has ≥1 point OR ≥1 automation item.
    - "Folder parent with children" = a selected track whose folder depth is less than the next track's depth (i.e., it currently has at least one child track underneath).

  Notes:
    - Master track is ignored by REAPER's CountSelectedTracks().

@changelog
  v0.2.0 - Messages in English; added safety prompt when selection includes any folder parent with child tracks.
  v0.1.0 - Initial release.
]]

local r = reaper

-- --- Utilities ---------------------------------------------------------------

local function collect_selected_tracks()
  local t = {}
  local n = r.CountSelectedTracks(0) -- master ignored
  for i = 0, n-1 do
    local tr = r.GetSelectedTrack(0, i)
    t[#t+1] = tr
  end
  return t
end

local function track_has_automation(tr)
  local env_count = r.CountTrackEnvelopes(tr)
  for i = 0, env_count-1 do
    local env = r.GetTrackEnvelope(tr, i)
    if env then
      -- any automation items?
      if r.CountAutomationItems(env) > 0 then
        return true
      end
      -- any underlying envelope points?
      if r.CountEnvelopePointsEx(env, -1) > 0 then
        return true
      end
    end
  end
  return false
end

-- Determine if a track is a folder parent with at least one child.
-- Strategy: compare this track's depth to the NEXT track's depth.
-- If next depth > current depth, then this is a parent with children.
local function is_folder_parent_with_children(tr)
  if not tr then return false end
  local idx_1based = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") -- 1-based
  if not idx_1based or idx_1based <= 0 then return false end
  local idx = math.floor(idx_1based) - 1                              -- 0-based
  local this_depth = r.GetTrackDepth(tr)
  local next_tr = r.GetTrack(0, idx + 1)
  if not next_tr then return false end
  local next_depth = r.GetTrackDepth(next_tr)
  return (next_depth or 0) > (this_depth or 0)
end

local function summarize_selection(tracks)
  local total_items = 0
  local tracks_with_auto = 0
  local folder_parents_with_children = 0

  for _, tr in ipairs(tracks) do
    total_items = total_items + r.CountTrackMediaItems(tr)
    if track_has_automation(tr) then
      tracks_with_auto = tracks_with_auto + 1
    end
    if is_folder_parent_with_children(tr) then
      folder_parents_with_children = folder_parents_with_children + 1
    end
  end

  return total_items, tracks_with_auto, folder_parents_with_children
end

local function delete_tracks(tracks)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  -- delete bottom-up
  for i = #tracks, 1, -1 do
    r.DeleteTrack(tracks[i])
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Delete selected tracks (safe)", -1)
end

-- --- Entry -------------------------------------------------------------------

local sel_tracks = collect_selected_tracks()
if #sel_tracks == 0 then
  r.ShowMessageBox("No track is selected.", "Delete Selected Tracks", 0)
  return
end

local total_items, tracks_with_auto, folder_parents_with_children = summarize_selection(sel_tracks)

-- If everything is empty and there is no folder parent-with-children, delete with no prompt.
local should_prompt =
  (total_items > 0) or
  (tracks_with_auto > 0) or
  (folder_parents_with_children > 0)

if not should_prompt then
  delete_tracks(sel_tracks)
  return
end

-- Build confirmation summary (English UI)
local msg = string.format(
  "Your selection includes content or folder parents:\n\n" ..
  "• Items: %d\n" ..
  "• Tracks with automation/envelope data: %d\n" ..
  "• Folder parents with child tracks: %d\n\n" ..
  "Do you still want to DELETE the selected track(s)?",
  total_items, tracks_with_auto, folder_parents_with_children
)

-- 4 = MB_YESNO, returns 6 if Yes
local ret = r.ShowMessageBox(msg, "Delete Selected Tracks — Confirm", 4)
if ret == 6 then
  delete_tracks(sel_tracks)
else
  -- User canceled.
end
