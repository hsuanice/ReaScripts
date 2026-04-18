-- @description hsuanice_Pro Tools Move Edit Insertion To Session End [Extend Selection]
-- @version 0.1.0 [260418.1158]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools:
--   **Move Edit Insertion To Session End [Extend Selection]**
--
--   ## Behaviour
--   - Extends selection rightward to session end (last item end)
--   - Cursor stays at left edge (anchor)
--   - Left edge of existing selection is preserved
--   - Selection only grows, never shrinks
--
--   - Tags : Editing, Navigation, Selection
--
-- @changelog
--   0.1.0 [260418.1158]
--     - Initial release

local r = reaper

local function get_selected_tracks()
  local tracks = {}
  for i = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, i)
    if r.GetMediaTrackInfo_Value(tr, "I_SELECTED") == 1 then
      tracks[#tracks+1] = tr
    end
  end
  return tracks
end

local function get_session_end()
  -- Find the end of the last item in the project
  local session_end = 0
  for ti = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, ti)
    for ii = 0, r.CountTrackMediaItems(tr)-1 do
      local it  = r.GetTrackMediaItem(tr, ii)
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if pos + len > session_end then session_end = pos + len end
    end
  end
  return session_end
end

local EPS = 1e-4
local cursor_pos = r.GetCursorPosition()
local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
local has_ts = te > ts + EPS

-- Left anchor = cursor or selection start (whichever is leftmost)
local anchor = has_ts and math.min(ts, cursor_pos) or cursor_pos

-- New right edge = session end
local new_pos = get_session_end()

-- Cursor stays at left anchor
r.SetEditCurPos(anchor, false, false)

-- Set time selection + razor
r.GetSet_LoopTimeRange(true, false, anchor, new_pos, false)

local tracks = get_selected_tracks()
for _, tr in ipairs(tracks) do
  local razor_str = string.format('%.14f %.14f ""', anchor, new_pos)
  r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", razor_str, true)
end

r.defer(function() end)
