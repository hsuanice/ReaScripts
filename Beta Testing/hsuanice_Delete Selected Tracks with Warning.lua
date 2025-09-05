--[[
@description Delete Selected Tracks (safe; prompt if content/folders/FX/routing; show selection, children & FX/routing counts)
@version 0.3.0
@author hsuanice
@about
  Delete selected tracks with safety:
    • If ALL selected tracks are empty (no items, no automation/envelope data, no FX inserts, no input FX, no sends/receives)
      AND none is a folder parent with children, delete immediately with no prompt.
    • Otherwise (any content, folder parents with children, or FX/routing present), show a detailed summary and ask for confirmation.
    • Summary includes: selected track count, items, automation tracks, folder parents, total child tracks, FX inserts, input FX, sends, receives.
  Notes:
    - "Automation present" = any track envelope has ≥1 point OR ≥1 automation item.
    - "Folder parent with children" = a selected track whose next track depth is greater than its own.
    - Child tracks counting includes all descendants under each selected folder parent (until depth returns to or above the parent's depth).
    - Master track is ignored by REAPER's CountSelectedTracks().

@changelog
  v0.3.0
        - Added detection and summary for FX inserts, Input FX, Sends, and Receives; any non-zero count now forces a confirmation dialog.
        - Confirmation dialog now shows totals for these four categories.
        - Kept all previous safety checks (items, automation, folder parents, child count) and instant delete behavior when truly empty.
  v0.2.1 - Add summary lines for "Selected tracks" and total "Child tracks".
  v0.2.0 - English messages; prompt when selection includes folder parents with children.
  v0.1.0 - Initial release.
]]

local r = reaper

-- --- Utilities ---------------------------------------------------------------

local function collect_selected_tracks()
  local t = {}
  local n = r.CountSelectedTracks(0) -- master ignored
  for i = 0, n-1 do
    t[#t+1] = r.GetSelectedTrack(0, i)
  end
  return t
end

local function track_has_automation(tr)
  local env_count = r.CountTrackEnvelopes(tr)
  for i = 0, env_count-1 do
    local env = r.GetTrackEnvelope(tr, i)
    if env then
      if r.CountAutomationItems(env) > 0 then return true end
      if r.CountEnvelopePointsEx(env, -1) > 0 then return true end
    end
  end
  return false
end

-- Is this track a folder parent (with at least one child) by depth comparison?
local function is_folder_parent_with_children(tr)
  if not tr then return false end
  local idx_1 = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") -- 1-based
  if not idx_1 or idx_1 <= 0 then return false end
  local idx0 = math.floor(idx_1) - 1                            -- 0-based
  local this_depth = r.GetTrackDepth(tr)
  local next_tr = r.GetTrack(0, idx0 + 1)
  if not next_tr then return false end
  local next_depth = r.GetTrackDepth(next_tr)
  return (next_depth or 0) > (this_depth or 0)
end

-- Count ALL descendant tracks of a folder parent (direct + nested) until depth returns.
local function count_children_for_parent(tr)
  if not tr then return 0 end
  local idx_1 = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") -- 1-based
  if not idx_1 or idx_1 <= 0 then return 0 end
  local start_idx = math.floor(idx_1) - 1                        -- 0-based
  local parent_depth = r.GetTrackDepth(tr)
  local total = 0

  local i = start_idx + 1
  while true do
    local t = r.GetTrack(0, i)
    if not t then break end
    local d = r.GetTrackDepth(t)
    if (d or 0) <= (parent_depth or 0) then
      break -- scope ended
    end
    total = total + 1
    i = i + 1
  end
  return total
end

-- Count FX and routing on a track
local function count_fx_and_routing(tr)
  local fx_inserts = r.TrackFX_GetCount(tr) or 0       -- normal insert FX
  local fx_input   = r.TrackFX_GetRecCount(tr) or 0     -- input/monitor FX
  local sends      = r.GetTrackNumSends(tr, 0) or 0     -- 0 = track sends
  local receives   = r.GetTrackNumSends(tr, -1) or 0    -- -1 = track receives
  return fx_inserts, fx_input, sends, receives
end

local function summarize_selection(tracks)
  local total_items = 0
  local tracks_with_auto = 0
  local folder_parents_with_children = 0
  local total_children = 0

  local total_fx_inserts = 0
  local total_fx_input   = 0
  local total_sends      = 0
  local total_receives   = 0

  for _, tr in ipairs(tracks) do
    total_items = total_items + r.CountTrackMediaItems(tr)

    if track_has_automation(tr) then
      tracks_with_auto = tracks_with_auto + 1
    end

    if is_folder_parent_with_children(tr) then
      folder_parents_with_children = folder_parents_with_children + 1
      total_children = total_children + count_children_for_parent(tr)
    end

    local fx_ins, fx_inp, snds, rcvs = count_fx_and_routing(tr)
    total_fx_inserts = total_fx_inserts + fx_ins
    total_fx_input   = total_fx_input   + fx_inp
    total_sends      = total_sends      + snds
    total_receives   = total_receives   + rcvs
  end

  return total_items, tracks_with_auto, folder_parents_with_children, total_children,
         total_fx_inserts, total_fx_input, total_sends, total_receives
end

local function delete_tracks(tracks)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for i = #tracks, 1, -1 do
    r.DeleteTrack(tracks[i])
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Delete selected tracks (safe)", -1)
end

-- --- Entry -------------------------------------------------------------------

local sel_tracks = collect_selected_tracks()
local sel_count = #sel_tracks
if sel_count == 0 then
  r.ShowMessageBox("No track is selected.", "Delete Selected Tracks", 0)
  return
end

local total_items, tracks_with_auto, folder_parents_with_children, total_children,
      total_fx_inserts, total_fx_input, total_sends, total_receives =
  summarize_selection(sel_tracks)

-- Prompt if there is any content/folder/FX/routing involved.
local should_prompt =
  (total_items > 0) or
  (tracks_with_auto > 0) or
  (folder_parents_with_children > 0) or
  (total_fx_inserts > 0) or
  (total_fx_input > 0) or
  (total_sends > 0) or
  (total_receives > 0)

if not should_prompt then
  delete_tracks(sel_tracks)
  return
end

-- Build confirmation summary (English UI)
local msg = string.format(
  "Your selection includes content, folders, or FX/routing:\n\n" ..
  "• Selected tracks: %d\n" ..
  "• Items: %d\n" ..
  "• Tracks with automation/envelope data: %d\n" ..
  "• Folder parents with child tracks: %d\n" ..
  "• Child tracks (total): %d\n" ..
  "• FX inserts: %d\n" ..
  "• Input FX: %d\n" ..
  "• Sends: %d\n" ..
  "• Receives: %d\n\n" ..
  "Do you still want to DELETE the selected track(s)?",
  sel_count, total_items, tracks_with_auto, folder_parents_with_children, total_children,
  total_fx_inserts, total_fx_input, total_sends, total_receives
)

-- 4 = MB_YESNO, returns 6 if Yes
local ret = r.ShowMessageBox(msg, "Delete Selected Tracks — Confirm", 4)
if ret == 6 then
  delete_tracks(sel_tracks)
else
  -- User canceled.
end
