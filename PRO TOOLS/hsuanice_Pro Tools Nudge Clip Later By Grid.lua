-- @description hsuanice_Pro Tools Nudge Clip Later By Grid
-- @version 0.3.0 [260419.1806]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools: **Nudge Clip Later By Grid**
--
--   Selection-aware nudge using Razor area as selection.
--   Each selected item is judged independently based on
--   how the razor area overlaps its fade/clip zones.
--
--   Rules (move later, earlier is reversed):
--   fade_in+clip+fade_out covered -> item position move
--   clip only covered             -> contents +delta, fade_in +delta, fade_out -delta
--   clip+fade_out covered         -> contents +delta, fade_in +delta, right end moves
--   fade_in+clip covered          -> left end moves, fade_out -delta
--   fade_out only covered         -> right end moves, clip gets longer
--   fade_in only covered          -> left end moves, clip gets longer
--   nothing covered               -> selection only moves (no item change)
--
--   Tags: Editing
-- @changelog
--   0.3.0 [260419.1806] - Rewrite: full PT selection-aware nudge logic
--   0.2.0 [260418.1931] - ApplyNudge via PT_Nudge library

local r = reaper
local info = debug.getinfo(1, "S")
local dir = info.source:match("^@(.*[/\\])") or ""
local ok, Nudge = pcall(dofile, dir .. "hsuanice_PT_Nudge.lua")
if not ok then
  r.ShowMessageBox("Could not load hsuanice_PT_Nudge.lua", "Error", 0)
  return
end

local EPS = 1e-4

-- Get nudge delta in seconds
local function get_delta()
  local mode, idx = Nudge.get_state()
  local preset = Nudge.get_preset(mode, idx)
  if not preset then return 0 end
  local unit  = preset.unit
  local value = preset.value
  if unit == 0  then return value / 1000.0 end
  if unit == 1  then return value end
  if unit == 17 then
    local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    return value / sr
  end
  if unit == 18 then
    local _, fps = r.TimeMap_curFrameRate(0)
    fps = (fps and fps > 0) and fps or 24
    return value / fps
  end
  if unit == 16 then
    local pos = r.GetCursorPosition()
    local bpm, _ = r.GetProjectTimeSignature2(0)
    local _, bps = r.TimeMap_GetTimeSigAtTime(0, pos)
    return math.floor(value) * (60.0/bpm) * bps
  end
  if unit >= 3 and unit <= 15 then
    local bpm, _ = r.GetProjectTimeSignature2(0)
    local beat_sec = 60.0 / bpm
    local note_map = {[3]=1/64,[4]=1/32,[5]=1/16,[6]=1/8,[7]=1/4,
      [8]=1/2,[9]=1,[10]=2,[11]=4,[12]=8,[13]=16,[14]=32,[15]=64}
    return beat_sec * (note_map[unit] or 1) * value
  end
  return 0
end

-- Get razor range for a track (guid="" track-level only)
local function get_track_razor(track)
  local _, s = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
  if not s or s == "" then return nil end
  local rs, re = s:match('(%S+)%s+(%S+)%s+""')
  if rs and re then return tonumber(rs), tonumber(re) end
  return nil
end

-- Nudge one item based on razor selection overlap
local function nudge_item(item, sel_s, sel_e, delta)
  local pos     = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len     = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local fi_len  = r.GetMediaItemInfo_Value(item, "D_FADEINLEN")
  local fo_len  = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  local item_e  = pos + len

  -- Zone boundaries
  local fi_end  = pos + fi_len      -- fade in end = clip start
  local fo_start = item_e - fo_len  -- fade out start = clip end

  -- Coverage check (fully covered = selection covers entire zone)
  local fi_covered   = sel_s <= pos      + EPS and sel_e >= fi_end    - EPS
  local fo_covered   = sel_s <= fo_start + EPS and sel_e >= item_e   - EPS
  local clip_covered = sel_s <= fi_end   + EPS and sel_e >= fo_start - EPS

  -- No overlap with item at all
  if sel_e <= pos + EPS or sel_s >= item_e - EPS then return end

  local take = r.GetActiveTake(item)

  if fi_covered and clip_covered and fo_covered then
    -- Case 1: entire item covered -> position move
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)

  elseif clip_covered and not fi_covered and not fo_covered then
    -- Case 2: clip only -> contents move, fi grows, fo shrinks
    -- Move later: fade_in grows (left fixed), fade_out shrinks (right fixed)
    -- contents shift right = startoffs decreases
    r.SetMediaItemInfo_Value(item, 'D_FADEINLEN',  fi_len + delta)
    r.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN', math.max(0, fo_len - delta))
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs - delta)
    end

  elseif clip_covered and not fi_covered and fo_covered then
    -- Case 3: clip + fade_out -> fi grows, right end moves, contents move right
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',    len + delta)
    r.SetMediaItemInfo_Value(item, 'D_FADEINLEN', fi_len + delta)
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs - delta)
    end

  elseif clip_covered and fi_covered and not fo_covered then
    -- Case 4: fade_in + clip -> left end moves, fo shrinks, contents move right
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',   len - delta)
    r.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN', math.max(0, fo_len - delta))
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs - delta)
    end

  elseif fo_covered and not clip_covered then
    -- Case 6: fade_out only -> right end moves, clip grows (contents don't move)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', len + delta)

  elseif fi_covered and not clip_covered then
    -- Case 7: fade_in only -> left end moves, clip grows (contents don't move)
    -- pos + delta, len - delta keeps right end fixed
    -- startoffs + delta keeps contents at same absolute position
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',   len - delta)
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs + delta)
    end

  -- else: Case 5 - nothing covered, item untouched
  end
end

-- Main
local delta = get_delta()
if math.abs(delta) < 1e-10 then return end

-- Fallback: no items selected and no razor -> move edit cursor only
local has_items = r.CountSelectedMediaItems(0) > 0
local has_razor = false
for ti = 0, r.CountTracks(0) - 1 do
  local _, s = r.GetSetMediaTrackInfo_String(r.GetTrack(0,ti), 'P_RAZOREDITS', '', false)
  if s and s ~= '' then has_razor = true; break end
end

if not has_items and not has_razor then
  r.SetEditCurPos(r.GetCursorPosition() + delta, true, false)
  r.defer(function() end)
  return
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local any_item_nudged = false
local position_moved = false  -- track if any item did a full position move

for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item  = r.GetSelectedMediaItem(0, i)
  local track = r.GetMediaItemTrack(item)
  local sel_s, sel_e = get_track_razor(track)
  local pos   = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len   = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local item_e = pos + len

  if sel_s and sel_e then
    -- Razor exists: use razor as selection
    if sel_e > pos + EPS and sel_s < item_e - EPS then
      -- Check if this will be a full position move (case 1)
      local fi_len  = r.GetMediaItemInfo_Value(item, 'D_FADEINLEN')
      local fo_len  = r.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN')
      local fi_end  = pos + fi_len
      local fo_start = item_e - fo_len
      local clamped_s = math.max(sel_s, pos)
      local clamped_e = math.min(sel_e, item_e)
      local fi_cov = clamped_s <= pos      + EPS and clamped_e >= fi_end    - EPS
      local fo_cov = clamped_s <= fo_start + EPS and clamped_e >= item_e   - EPS
      local cl_cov = clamped_s <= fi_end   + EPS and clamped_e >= fo_start - EPS
      if fi_cov and cl_cov and fo_cov then position_moved = true end
      nudge_item(item, clamped_s, clamped_e, delta)
      any_item_nudged = true
    end
  else
    -- No razor: item selection = entire item -> position move
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)
    any_item_nudged = true
    position_moved = true
  end
end

-- Move razor + time selection
for ti = 0, r.CountTracks(0) - 1 do
  local track = r.GetTrack(0, ti)
  local _, s = r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
  if s and s ~= '' then
    local new_s = s:gsub('(%S+)%s+(%S+)%s+""', function(a, b)
      local rs, re = tonumber(a), tonumber(b)
      if rs and re then
        return string.format('%.14f %.14f ""', rs + delta, re + delta)
      end
      return a .. ' ' .. b .. ' ""'
    end)
    r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', new_s, true)
  end
end

local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
if te > ts + EPS then
  r.GetSet_LoopTimeRange(true, false, ts + delta, te + delta, false)
end

-- Move edit cursor when Loop linked to time selection is ON and item position moved
local linked = r.GetToggleCommandState(40621) == 1
if linked and position_moved then
  r.SetEditCurPos(r.GetCursorPosition() + delta, false, false)
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock('Pro Tools: Nudge Clip Later By Grid', -1)
