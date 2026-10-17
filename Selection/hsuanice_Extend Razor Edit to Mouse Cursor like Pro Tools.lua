--[[
@description Extend Razor Edit to Mouse Cursor like Pro Tools - Shift-click extends the edit selection
@version 26.1017.1551
@author hsuanice
@changelog
  - First release: Shift-click adds the clicked track and extends the shared time range (grow only).
@about
  Pro Tools-style Shift-click: extends the current edit selection to the mouse position.
  The selection is one time range shared by a set of tracks.

  Behavior:
    • Only grows, never shrinks. Clicking before the range extends its start, clicking after it
      extends its end, clicking inside it keeps the time range as it is.
    • Tracks: only the clicked track is added (like Cmd-click in Pro Tools); tracks in between
      are not. Every track of the selection gets the same, extended time range.
    • The current selection is read from the existing razor areas (all tracks, union of their
      time ranges). Without razor areas: time selection + selected tracks. Without those:
      the edit cursor + the selected tracks (or the last touched track).
    • The clicked position follows snap / grid settings. The edit cursor does not move.
    • Track-level razor areas only; envelope-lane razor areas are kept but not extended.
    • Options inside the script: also set the time selection, the track selection and the item
      selection to the result.

  Suggested setup (suggestions only — nothing is assigned automatically):
    Preferences > Editing Behavior > Mouse Modifiers > Track > Left click > Shift.

  Credits:
    Inspired by Daniel Kharrat's "Extend razor edit area to mouse cursor (select tracks in between)".
    Designed and tested by hsuanice; code written with Claude Code (AI).
--]]

-------------------- USER OPTIONS --------------------
local SYNC_TIME_SELECTION  = true   -- time selection = the new razor time range
local SYNC_TRACK_SELECTION = true   -- selected tracks = the tracks in the new razor area
local SELECT_ITEMS         = false  -- also select items overlapping the new razor area
                                     -- (leave off when "Toggle Track and Razor Item Link like Pro Tools" runs)
local EPS = 1e-9
------------------------------------------------------

local function track_index(tr)
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) - 1 -- master = -2
end

-- Split P_RAZOREDITS into track-level ranges and envelope-lane triples (kept as-is)
local function parse_razor(tr)
  local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  local ranges, env = {}, {}
  for a, b, guid in (s or ""):gmatch('(%S+)%s+(%S+)%s+"([^"]*)"') do
    local st, en = tonumber(a), tonumber(b)
    if st and en then
      if guid == "" then
        ranges[#ranges + 1] = { st, en }
      else
        env[#env + 1] = string.format('%s %s "%s"', a, b, guid)
      end
    end
  end
  return ranges, env
end

-- Snapped mouse time: let REAPER move the edit cursor (honors snap), read it, put it back
local function mouse_time()
  local old = reaper.GetCursorPosition()
  reaper.Main_OnCommand(40513, 0) -- View: Move edit cursor to mouse cursor
  local t = reaper.GetCursorPosition()
  reaper.SetEditCurPos(old, false, false)
  return t
end

local function main()
  local n_tracks = reaper.CountTracks(0)
  if n_tracks == 0 then return end

  local click_t = mouse_time()
  local x, y = reaper.GetMousePosition()
  local click_tr = reaper.GetTrackFromPoint(x, y)
  local click_idx = click_tr and track_index(click_tr) or -1
  if click_idx < 0 then click_idx = nil end

  -- 1) Current selection: union time range + set of tracks
  local t0, t1
  local sel, has_sel = {}, false
  for i = 0, n_tracks - 1 do
    local ranges = parse_razor(reaper.GetTrack(0, i))
    for _, r in ipairs(ranges) do
      t0 = t0 and math.min(t0, r[1]) or r[1]
      t1 = t1 and math.max(t1, r[2]) or r[2]
      sel[i], has_sel = true, true
    end
  end

  if not t0 then
    local ts0, ts1 = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts1 - ts0 > EPS then
      t0, t1 = ts0, ts1
    else
      local cur = reaper.GetCursorPosition()
      t0, t1 = cur, cur
    end
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
      local idx = track_index(reaper.GetSelectedTrack(0, i))
      if idx >= 0 then sel[idx], has_sel = true, true end
    end
    if not has_sel then
      local lt = reaper.GetLastTouchedTrack()
      local idx = lt and track_index(lt) or -1
      if idx >= 0 then sel[idx], has_sel = true, true end
    end
  end

  -- 2) Grow only: union with the clicked point / track
  t0, t1 = math.min(t0, click_t), math.max(t1, click_t)
  if click_idx then sel[click_idx], has_sel = true, true end
  if not has_sel or t1 - t0 <= EPS then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- 3) Write the range on every selected track (track-level razor; others cleared)
  local area = string.format('%.14f %.14f ""', t0, t1)
  for i = 0, n_tracks - 1 do
    local tr = reaper.GetTrack(0, i)
    local ranges, env = parse_razor(tr)
    local in_area = sel[i] == true
    if in_area or #ranges > 0 then
      local parts = {}
      if in_area then parts[1] = area end
      for _, e in ipairs(env) do parts[#parts + 1] = e end
      reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", table.concat(parts, " "), true)
    end
    if SYNC_TRACK_SELECTION then
      if reaper.IsTrackSelected(tr) ~= in_area then reaper.SetTrackSelected(tr, in_area) end
    end
    if SELECT_ITEMS and in_area then
      for j = 0, reaper.CountTrackMediaItems(tr) - 1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local l = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if p < t1 - EPS and p + l > t0 + EPS then reaper.SetMediaItemSelected(it, true) end
      end
    end
  end

  if SYNC_TIME_SELECTION then
    reaper.GetSet_LoopTimeRange(true, false, t0, t1, false)
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("Extend razor edit to mouse cursor", -1)
end

main()
