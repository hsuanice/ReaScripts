-- hsuanice_Work Time Calculator.lua
-- Calculates editing work time from empty items on dedicated time-log tracks.
--
-- Usage:
--   1. Create tracks named exactly as configured below.
--   2. On each track, add empty items where:
--        item start position  = time-of-day you started (using 24H timeline)
--        item end position    = time-of-day you stopped
--      The item LENGTH is what gets summed as work duration.
--   3. Run this script to see a summary.
--
-- Version: 260228.1200

-- ============================================================
-- CONFIGURATION — edit these to match your track names
-- ============================================================

-- Tracks whose empty-item lengths are summed as "Editing" time
-- Add multiple track names if you split across tracks
local EDITING_TRACK_NAMES = {
  "Editing",
}

-- Tracks whose empty-item lengths are summed as "Denoise" time
local DENOISE_TRACK_NAMES = {
  "Denoise",
}

-- Tracks to count total items on (for material count)
-- Leave empty {} to skip
local PICTURE_TRACK_NAMES = {
  "Picture Cut",
}

local SCENE_TRACK_NAMES = {
  "Scene Cut",
}

-- If true, match is case-insensitive and allows partial match (contains)
-- If false, track name must match exactly
local FUZZY_MATCH = false

-- ============================================================
-- HELPERS
-- ============================================================

local function track_matches(track_name, patterns)
  for _, pattern in ipairs(patterns) do
    if FUZZY_MATCH then
      if track_name:lower():find(pattern:lower(), 1, true) then
        return true
      end
    else
      if track_name == pattern then
        return true
      end
    end
  end
  return false
end

local function find_tracks(patterns)
  local found = {}
  local count = reaper.CountTracks(0)
  for i = 0, count - 1 do
    local track = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(track)
    if track_matches(name, patterns) then
      table.insert(found, { track = track, name = name })
    end
  end
  return found
end

local function is_empty_item(item)
  return reaper.GetMediaItemNumTakes(item) == 0
end

-- Returns total length (seconds) and session count of empty items across tracks
local function sum_empty_item_durations(tracks)
  local total_sec = 0
  local sessions   = 0
  for _, t in ipairs(tracks) do
    local n = reaper.CountTrackMediaItems(t.track)
    for i = 0, n - 1 do
      local item = reaper.GetTrackMediaItem(t.track, i)
      if is_empty_item(item) then
        total_sec = total_sec + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        sessions  = sessions + 1
      end
    end
  end
  return total_sec, sessions
end

-- Returns total item count (all items, not just empty) across tracks
local function count_all_items(tracks)
  local total = 0
  for _, t in ipairs(tracks) do
    total = total + reaper.CountTrackMediaItems(t.track)
  end
  return total
end

local function format_duration(seconds)
  seconds = math.floor(seconds + 0.5)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%d h %02d m %02d s", h, m, s)
  else
    return string.format("%d m %02d s", m, s)
  end
end

local function track_list_label(tracks)
  if #tracks == 0 then return "(none found)" end
  local names = {}
  for _, t in ipairs(tracks) do table.insert(names, '"' .. t.name .. '"') end
  return table.concat(names, ", ")
end

-- ============================================================
-- MAIN
-- ============================================================

local function run()
  local editing_tracks = find_tracks(EDITING_TRACK_NAMES)
  local denoise_tracks = find_tracks(DENOISE_TRACK_NAMES)
  local picture_tracks = find_tracks(PICTURE_TRACK_NAMES)
  local scene_tracks   = find_tracks(SCENE_TRACK_NAMES)

  local editing_sec, editing_sessions = sum_empty_item_durations(editing_tracks)
  local denoise_sec,  denoise_sessions = sum_empty_item_durations(denoise_tracks)
  local total_sec = editing_sec + denoise_sec

  local picture_items = count_all_items(picture_tracks)
  local scene_items   = count_all_items(scene_tracks)

  -- Build report string
  local lines = {}
  local sep = string.rep("─", 36)

  local proj_name = reaper.GetProjectName(0, "")
  if proj_name == "" then proj_name = "(unsaved project)" end
  table.insert(lines, "Project: " .. proj_name)
  table.insert(lines, sep)

  -- Material section
  if #picture_tracks > 0 or #scene_tracks > 0 then
    table.insert(lines, "MATERIAL")
    if #picture_tracks > 0 then
      table.insert(lines, string.format("  Picture cuts : %d items", picture_items))
    end
    if #scene_tracks > 0 then
      table.insert(lines, string.format("  Scenes       : %d items", scene_items))
    end
    table.insert(lines, sep)
  end

  -- Work time section
  table.insert(lines, "WORK TIME")

  if #editing_tracks > 0 then
    table.insert(lines, string.format(
      "  Editing   : %s  (%d session%s)",
      format_duration(editing_sec),
      editing_sessions,
      editing_sessions == 1 and "" or "s"
    ))
  else
    table.insert(lines, "  Editing   : (track not found)")
  end

  if #denoise_tracks > 0 then
    table.insert(lines, string.format(
      "  Denoise   : %s  (%d session%s)",
      format_duration(denoise_sec),
      denoise_sessions,
      denoise_sessions == 1 and "" or "s"
    ))
  else
    table.insert(lines, "  Denoise   : (track not found)")
  end

  table.insert(lines, sep)
  table.insert(lines, string.format("  Total     : %s", format_duration(total_sec)))

  reaper.ShowMessageBox(table.concat(lines, "\n"), "Work Time Calculator", 0)
end

run()
