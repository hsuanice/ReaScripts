-- @description hsuanice_Pro Tools Move Edit Insertion To Previous Edit [Extend Selection]
-- @version 0.1.1 [260418.1151]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools:
--   **Move Edit Insertion To Previous Edit [Extend Selection]**
--
--   ## Behaviour
--   - Finds previous transient/edge from selection LEFT edge (cursor pos)
--   - Edit cursor moves to new left edge
--   - Selection right edge is preserved; selection only grows leftward
--   - Selection only grows, never shrinks
--
--   Works with "Tab to Transient" toggle (ON=transients, OFF=item edges)
--
--   - Tags : Editing, Navigation, Selection
--
-- @changelog
--   0.1.1 [260418.1151]
--     - Rewrite: cursor moves to new left edge; right edge preserved
--   0.1.0 [260418.1138]
--     - Initial release

local r = reaper

local function get_tab_toggle_state()
  local section = r.SectionFromUniqueID(0)
  local idx = 0
  while true do
    local cid, cname = r.kbd_enumerateActions(section, idx)
    if cid == 0 and idx > 0 then break end
    if cname and cname:lower():find("pro tools tab to transient", 1, true) then
      return r.GetToggleCommandStateEx(0, cid) == 1
    end
    idx = idx + 1
    if idx > 200000 then break end
  end
  return false
end

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

local EPS = 1e-4
local cursor_pos = r.GetCursorPosition()
local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
local has_ts = te > ts + EPS

-- Right anchor = selection end (or cursor if no selection)
local right_anchor = has_ts and math.max(te, cursor_pos) or cursor_pos

-- Search from selection left end = cursor (cursor is always at left)
local search_from = has_ts and math.min(ts, cursor_pos) or cursor_pos

-- Move cursor to search_from to find previous transient/edge
r.SetEditCurPos(search_from, false, false)
r.Main_OnCommand(41229, 0)  -- Save selection set
r.Main_OnCommand(40421, 0)  -- Select all items in track

if get_tab_toggle_state() then
  r.Main_OnCommand(40376, 0)  -- Previous transient
else
  r.Main_OnCommand(40318, 0)  -- Previous item edge
end

local new_pos = r.GetCursorPosition()
r.Main_OnCommand(41239, 0)  -- Restore selection set

if math.abs(new_pos - search_from) > EPS then
  -- Cursor moves to new left edge; right anchor preserved
  r.SetEditCurPos(new_pos, false, false)
  r.GetSet_LoopTimeRange(true, false, new_pos, right_anchor, false)

  local tracks = get_selected_tracks()
  for _, tr in ipairs(tracks) do
    local razor_str = string.format('%.14f %.14f ""', new_pos, right_anchor)
    r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", razor_str, true)
  end
end

r.defer(function() end)
