-- @description hsuanice_Pro Tools Delete Selection
-- @version 0.1.0 [260415.1250]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Wrapper replicating Pro Tools: **Delete Selection**
--
--   ## Mapping
--   Pro Tools Delete is context-aware. This script mirrors that:
--   - Selected items exist        → Remove items (40006)
--   - Time selection exists       → Remove time selection (40635)
--   - Selected envelope points    → Delete envelope points (40333)
--   - Automation items selected   → Delete automation items (42086)
--
--   Priority: items → envelope points → automation items → time selection
--
--   - Mac shortcut (PT) : Delete
--   - Tags              : Editing
--
-- @changelog
--   0.1.0 [260415.1250]
--     - Initial release: context-aware delete mirroring PT behaviour

local r = reaper

r.Undo_BeginBlock()

local did_something = false

-- 1. Selected media items
if r.CountSelectedMediaItems(0) > 0 then
  r.Main_OnCommand(40006, 0) -- Item: Remove items
  did_something = true
end

-- 2. Selected envelope points (check all track envelopes)
if not did_something then
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    for ei = 0, r.CountTrackEnvelopes(track) - 1 do
      local env = r.GetTrackEnvelope(track, ei)
      -- Check if any points are selected
      for pi = 0, r.CountEnvelopePoints(env) - 1 do
        local _, _, _, _, _, selected = r.GetEnvelopePoint(env, pi)
        if selected then
          r.Main_OnCommand(40333, 0) -- Envelope: Delete all selected points
          did_something = true
          break
        end
      end
      if did_something then break end
    end
    if did_something then break end
  end
end

-- 3. Automation items selected
if not did_something then
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    for ei = 0, r.CountTrackEnvelopes(track) - 1 do
      local env = r.GetTrackEnvelope(track, ei)
      for ai = 0, r.CountAutomationItems(env) - 1 do
        local sel = r.GetSetAutomationItemInfo(env, ai, "D_UISEL", 0, false)
        if sel > 0.5 then
          r.Main_OnCommand(42086, 0) -- Envelope: Delete automation items
          did_something = true
          break
        end
      end
      if did_something then break end
    end
    if did_something then break end
  end
end

-- 4. Time selection fallback
if not did_something then
  local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if te > ts then
    r.Main_OnCommand(40635, 0) -- Time selection: Remove (unselect) time selection
  end
end

r.Undo_EndBlock("Pro Tools: Delete Selection", -1)
