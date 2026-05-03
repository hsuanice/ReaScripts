-- @description hsuanice_Pro Tools Nudge Clip End Later By Grid
-- @version 0.4.0 [260420.1523]
-- @author hsuanice
-- @about
--   Replicates Pro Tools: **Nudge Clip End Later By Grid**
--   Fill + nudge mechanism: boundary fills to selection edge first, then nudges.
--   Zone-aware stop guard prevents zone from disappearing.
--   Tags: Editing
-- @changelog
--   0.4.0 [260420.1523] - Add fill mechanism + correct zone-size stop guard
--   0.3.0 [260420.1247] - 3-boundary logic with stop guard
--   0.2.0 [260420.1132] - PT selection-aware nudge
--   0.1.0 [260419.1012] - Initial release

local r = reaper
local info = debug.getinfo(1, 'S')
local dir = info.source:match('^@(.*[/\\])') or ''
local ok, Nudge = pcall(dofile, dir .. 'hsuanice_PT_Nudge.lua')
if not ok then
  r.ShowMessageBox('Could not load hsuanice_PT_Nudge.lua', 'Error', 0)
  return
end

local EPS = 1e-4

local function get_delta()
  local mode, idx = Nudge.get_state()
  local preset = Nudge.get_preset(mode, idx)
  if not preset then return 0 end
  local unit, value = preset.unit, preset.value
  if unit == 0  then return value / 1000.0 end
  if unit == 1  then return value end
  if unit == 17 then
    local sr = r.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false)
    return value / sr
  end
  if unit == 18 then
    local fps = r.TimeMap_curFrameRate(0)  -- returns (fps, isdrop) — fps FIRST
    fps = (fps and fps > 0) and fps or 24
    return value / fps
  end
  if unit == 16 then
    local bpm = r.GetProjectTimeSignature2(0)
    local _, bps = r.TimeMap_GetTimeSigAtTime(0, r.GetCursorPosition())
    return math.floor(value) * (60.0/bpm) * bps
  end
  if unit >= 3 and unit <= 15 then
    local bpm = r.GetProjectTimeSignature2(0)
    local beat_sec = 60.0 / bpm
    local note_map = {[3]=1/64,[4]=1/32,[5]=1/16,[6]=1/8,[7]=1/4,
      [8]=1/2,[9]=1,[10]=2,[11]=4,[12]=8,[13]=16,[14]=32,[15]=64}
    return beat_sec * (note_map[unit] or 1) * value
  end
  return 0
end

local function get_track_razor(track)
  local _, s = r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
  if not s or s == '' then return nil, nil end
  local rs, re = s:match('(%S+)%s+(%S+)%s+""')
  if rs and re then return tonumber(rs), tonumber(re) end
  return nil, nil
end

local function update_razor(track, new_s, new_e)
  local _, s = r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
  if not s or s == '' then return end
  local updated = s:gsub('(%S+)%s+(%S+)%s+""', function()
    return string.format('%.14f %.14f ""', new_s, new_e)
  end)
  r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', updated, true)
end

-- Nudge End: fill boundary to sel_e, then nudge
-- Priority: C end > B end > A end
local function nudge_end(item, sel_s, sel_e, delta)
  local pos      = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len      = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local fi_len   = r.GetMediaItemInfo_Value(item, 'D_FADEINLEN')
  local fo_len   = r.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN')
  local item_e   = pos + len
  local fi_end   = pos + fi_len
  local fo_start = item_e - fo_len
  local take     = r.GetActiveTake(item)

  -- Priority 1: C end (item_e) in selection
  if sel_s <= item_e + EPS and sel_e >= item_e - EPS then
    -- Fill: fo_len expands to reach sel_e, then nudge
    local fill_amt = sel_e - item_e  -- how much to fill (can be negative)
    local new_fo_len = fo_len + fill_amt  -- after fill
    -- Guard: after fill, new_fo_len must be > delta (for Earlier)
    if delta < 0 and new_fo_len <= math.abs(delta) + EPS then return sel_s, sel_e end
    -- Apply fill + nudge
    local total = fill_amt + delta
    reaper.ShowConsoleMsg(string.format("DEBUG C end: fill=%.4f total=%.4f len+total=%.4f fo+total=%.4f\n",
      fill_amt, total, len+total, fo_len+total))
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',     len + total)
    r.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN', fo_len + total)
    reaper.ShowConsoleMsg(string.format("DEBUG after: D_LENGTH=%.4f D_FADEOUTLEN=%.4f\n",
      r.GetMediaItemInfo_Value(item,'D_LENGTH'),
      r.GetMediaItemInfo_Value(item,'D_FADEOUTLEN')))
    return sel_s, item_e + total

  -- Priority 2: B end (fo_start) in selection
  elseif sel_s <= fo_start + EPS and sel_e >= fo_start - EPS then
    local fill_amt = sel_e - fo_start
    local new_clip_len = (fo_start - fi_end) + fill_amt
    if delta < 0 and new_clip_len <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', len + total)
    return sel_s, fo_start + total

  -- Priority 3: A end (fi_end) in selection
  elseif sel_s <= fi_end + EPS and sel_e >= fi_end - EPS then
    local fill_amt = sel_e - fi_end
    local new_fi_len = fi_len + fill_amt
    local clip_len_after = (fo_start - fi_end) - fill_amt
    if delta < 0 and new_fi_len   <= math.abs(delta) + EPS then return sel_s, sel_e end
    if delta > 0 and clip_len_after <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    r.SetMediaItemInfo_Value(item, 'D_FADEINLEN', fi_len + total)
    return sel_s, fi_end + total

  else
    return sel_s, sel_e + delta
  end
end

local delta = get_delta()
local delta = get_delta()
if math.abs(delta) < 1e-10 then return end

local has_items = r.CountSelectedMediaItems(0) > 0
local has_razor = false
for ti = 0, r.CountTracks(0)-1 do
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

local new_sel_e_global = nil

for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item  = r.GetSelectedMediaItem(0, i)
  local track = r.GetMediaItemTrack(item)
  local sel_s, sel_e = get_track_razor(track)
  local pos    = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local item_e = pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH')

  if sel_s and sel_e then
    if sel_e > pos + EPS and sel_s < item_e - EPS then
      local new_s, new_e = nudge_end(item, sel_s, sel_e, delta)
      if math.abs(new_s - sel_s) > 1e-10 or math.abs(new_e - sel_e) > 1e-10 then
        new_sel_e_global = new_e
        update_razor(track, new_s, new_e)
      end
    end
  else
    local mode, idx = Nudge.get_state()
    local preset = Nudge.get_preset(mode, idx)
    r.ApplyNudge(0, 0, 3, preset.unit, preset.value, false, 0)
  end
end

local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
if te > ts + EPS and new_sel_e_global then
  r.GetSet_LoopTimeRange(true, false, ts, new_sel_e_global, false)
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock('Pro Tools: Nudge Clip End Later By Grid', -1)
