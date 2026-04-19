--[[
@description hsuanice_PT_Nudge - Nudge Library
@version 0.4.2 [260419.1211]
@author hsuanice
@about
  Library for all hsuanice nudge scripts.
  Reads nudge mode and preset from hsuanice_Grid Nudge Panel ExtState.
  All nudge scripts require this file.

  nudgewhat values (ApplyNudge):
    0 = position, 1 = left trim, 2 = left edge,
    3 = right edge, 4 = contents, 6 = edit cursor

@changelog
  0.2.0 [260418.1931]
    - Sync NUDGE_PRESETS with Grid Nudge Panel (Feet+Frames restored)
  0.1.0 [260418.1534]
    - Initial release
--]]

local EXT = 'hsuanice_GridNudgePanel'

local NUDGE_MODES = {'Measure', 'Min:Secs', 'Timecode', 'Feet+Frames', 'Samples'}

local NUDGE_PRESETS = {
  ['Measure'] = {
    {label='1 bar',         unit=16, value=1.0},
    {label='1/2 note',      unit=10, value=1},
    {label='1/4 note',      unit=9,  value=1},
    {label='1/8 note',      unit=8,  value=1},
    {label='1/16 note',     unit=7,  value=1},
    {label='1/32 note',     unit=6,  value=1},
    {label='1/64 note',     unit=5,  value=1},
  },
  ['Min:Secs'] = {
    {label='1 second',      unit=1,  value=1},
    {label='500 msec',      unit=0,  value=500},
    {label='100 msec',      unit=0,  value=100},
    {label='10 msec',       unit=0,  value=10},
    {label='1 msec',        unit=0,  value=1},
  },
  ['Timecode'] = {
    {label='1 second',      unit=1,  value=1},
    {label='6 frames',      unit=18, value=6},
    {label='1 frame',       unit=18, value=1},
    {label='1/2 frame',     unit=18, value=0.5},
    {label='1/4 frame',     unit=18, value=0.25},
    {label='1 sub frame',   unit=18, value=0.01},
  },
  ['Feet+Frames'] = {
    {label='1 foot',        unit=18, value=16},
    {label='1 frame',       unit=18, value=1},
    {label='1/4 frame',     unit=18, value=0.25},
    {label='1 sub frame',   unit=18, value=0.01},
  },
  ['Samples'] = {
    {label='10000 samples', unit=17, value=10000},
    {label='1000 samples',  unit=17, value=1000},
    {label='100 samples',   unit=17, value=100},
    {label='10 samples',    unit=17, value=10},
    {label='2 samples',     unit=17, value=2},
    {label='1 sample',      unit=17, value=1},
  },
}

local M = {}
M.MODES   = NUDGE_MODES
M.PRESETS = NUDGE_PRESETS

function M.get_state()
  local mode = reaper.GetExtState(EXT, 'nudge_mode')
  if mode == '' then mode = 'Timecode' end
  -- Migrate old key names
  if mode == 'Frames' then mode = 'Feet+Frames' end
  if mode == 'Bars|Beats' or mode == 'Bars' or mode == 'Beats' then mode = 'Measure' end
  local idx = tonumber(reaper.GetExtState(EXT, 'nudge_preset_idx')) or 3
  local presets = NUDGE_PRESETS[mode]
  if not presets then mode = 'Timecode'; presets = NUDGE_PRESETS[mode]; idx = 3 end
  idx = math.max(1, math.min(idx, #presets))
  return mode, idx
end

function M.set_state(mode, idx)
  reaper.SetExtState(EXT, 'nudge_mode',       mode,          true)
  reaper.SetExtState(EXT, 'nudge_preset_idx', tostring(idx), true)
  reaper.SetExtState(EXT, 'nudge_changed',    '1',           false)
end

function M.get_preset(mode, idx)
  local presets = NUDGE_PRESETS[mode]
  if not presets then return nil end
  return presets[idx]
end

-- Helper: calculate nudge delta in seconds from preset
-- Converts preset unit/value directly to seconds without moving cursor
local function calc_delta_sec(preset, reverse)
  local r = reaper
  local unit  = preset.unit
  local value = preset.value
  local delta = 0

  if unit == 0 then
    -- milliseconds
    delta = value / 1000.0
  elseif unit == 1 then
    -- seconds
    delta = value
  elseif unit == 17 then
    -- samples
    local sr = r.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false)
    delta = value / sr
  elseif unit == 18 then
    -- frames
    local _, fps = r.TimeMap_curFrameRate(0)
    fps = (fps and fps > 0) and fps or 24
    delta = value / fps
  elseif unit == 16 then
    -- measures.beats: value=1.0 means 1 measure
    -- Get current tempo and time sig at cursor
    local pos = r.GetCursorPosition()
    local _, beats_per_measure, _ = r.TimeMap_GetTimeSigAtTime(0, pos)
    local bpm, _ = r.GetProjectTimeSignature2(0)
    local beat_sec = 60.0 / bpm
    local measure_sec = beat_sec * beats_per_measure
    local bars = math.floor(value)
    local frac = value - bars
    delta = bars * measure_sec + frac * beat_sec
  elseif unit >= 3 and unit <= 15 then
    -- note divisions: unit 9 = quarter note, 8 = 8th, etc.
    -- unit 9 = 1 beat (quarter note)
    local bpm, _ = r.GetProjectTimeSignature2(0)
    local beat_sec = 60.0 / bpm
    -- note value relative to quarter note
    local note_map = {
      [3]=1/64, [4]=1/32, [5]=1/16, [6]=1/8, [7]=1/4,
      [8]=1/2,  [9]=1,    [10]=2,   [11]=4,  [12]=8,
      [13]=16,  [14]=32,  [15]=64
    }
    local ratio = note_map[unit] or 1
    delta = beat_sec * ratio * value
  end

  return reverse and -delta or delta
end

-- Helper: nudge all razor areas
local function nudge_razor(delta, nudgewhat)
  local r = reaper
  for ti = 0, r.CountTracks(0)-1 do
    local track = r.GetTrack(0, ti)
    local _, s = r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
    if s and s ~= '' then
      local new_s = s:gsub('(%S+)%s+(%S+)%s+(%S+)', function(a, b, c)
        local rs, re = tonumber(a), tonumber(b)
        if rs and re and c == '""' then
          if nudgewhat == 0 or nudgewhat == 5 then
            return string.format('%.14f %.14f ""', rs+delta, re+delta)
          elseif nudgewhat == 1 then
            return string.format('%.14f %.14f ""', rs+delta, re)
          elseif nudgewhat == 3 then
            return string.format('%.14f %.14f ""', rs, re+delta)
          else
            return string.format('%.14f %.14f ""', rs+delta, re+delta)
          end
        end
        return a..' '..b..' '..c
      end)
      r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', new_s, true)
    end
  end
end

-- Helper: check if any razor area exists
local function has_razor()
  local r = reaper
  for ti = 0, r.CountTracks(0)-1 do
    local _, s = r.GetSetMediaTrackInfo_String(r.GetTrack(0,ti), 'P_RAZOREDITS', '', false)
    if s and s ~= '' then return true end
  end
  return false
end

function M.apply(nudgewhat, reverse)
  local mode, idx = M.get_state()
  local preset = M.get_preset(mode, idx)
  if not preset then return end

  local r = reaper
  local has_items = r.CountSelectedMediaItems(0) > 0
  local razor_exists = has_razor()

  -- Contents nudge not applicable to razor-only
  if nudgewhat == 4 and not has_items then return end

  -- RAZOR-ONLY MODE: no items selected, but razor exists
  -- Nudge the razor area itself (like nudging Edit Selection in PT)
  if not has_items and razor_exists then
    local delta = calc_delta_sec(preset, reverse)
    if math.abs(delta) < 1e-10 then return end

    local linked = r.GetToggleCommandState(40621) == 1

    -- Move razor first
    nudge_razor(delta, nudgewhat)

    -- Set cursor first to new razor start
    if linked and (nudgewhat == 0 or nudgewhat == 1 or nudgewhat == 5) then
      local min_start = math.huge
      for ti = 0, r.CountTracks(0)-1 do
        local _, s = r.GetSetMediaTrackInfo_String(r.GetTrack(0,ti), 'P_RAZOREDITS', '', false)
        if s and s ~= '' then
          local v = tonumber(s:match('%d+%.%d+'))
          if v and v < min_start then min_start = v end
        end
      end
      if min_start < math.huge then
        r.SetEditCurPos(min_start, false, false)
      end
    end

    -- Then move time selection (loop-link may reset cursor,
    -- but we defer a second correction after)
    local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if te > ts + 1e-4 then
      if nudgewhat == 0 or nudgewhat == 5 then
        r.GetSet_LoopTimeRange(true, false, ts+delta, te+delta, false)
      elseif nudgewhat == 1 then
        r.GetSet_LoopTimeRange(true, false, ts+delta, te, false)
      elseif nudgewhat == 3 then
        r.GetSet_LoopTimeRange(true, false, ts, te+delta, false)
      else
        r.GetSet_LoopTimeRange(true, false, ts+delta, te+delta, false)
      end
    end

    -- Deferred second correction in case loop-link reset cursor
    if linked and (nudgewhat == 0 or nudgewhat == 1 or nudgewhat == 5) then
      r.defer(function()
        local min_start = math.huge
        for ti = 0, r.CountTracks(0)-1 do
          local _, s = r.GetSetMediaTrackInfo_String(r.GetTrack(0,ti), 'P_RAZOREDITS', '', false)
          if s and s ~= '' then
            local v = tonumber(s:match('%d+%.%d+'))
            if v and v < min_start then min_start = v end
          end
        end
        if min_start < math.huge then
          r.SetEditCurPos(min_start, false, false)
        end
      end)
    end
    return
  end

  -- ITEM MODE: items selected — nudge items
  local first_it = r.GetSelectedMediaItem(0, 0)
  local pos_before, len_before
  if first_it then
    pos_before = r.GetMediaItemInfo_Value(first_it, 'D_POSITION')
    len_before  = r.GetMediaItemInfo_Value(first_it, 'D_LENGTH')
  end

  r.ApplyNudge(0, 0, nudgewhat, preset.unit, preset.value, reverse, 0)

  -- Calculate actual delta
  local delta = 0
  if first_it and pos_before then
    if nudgewhat == 0 or nudgewhat == 1 or nudgewhat == 5 then
      delta = r.GetMediaItemInfo_Value(first_it, 'D_POSITION') - pos_before
    elseif nudgewhat == 3 then
      local new_end = r.GetMediaItemInfo_Value(first_it, 'D_POSITION') +
                      r.GetMediaItemInfo_Value(first_it, 'D_LENGTH')
      delta = new_end - (pos_before + len_before)
    end
  end

  if math.abs(delta) > 1e-10 then
    -- Update time selection
    local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if te > ts + 1e-4 then
      if nudgewhat == 0 or nudgewhat == 5 then
        r.GetSet_LoopTimeRange(true, false, ts+delta, te+delta, false)
      elseif nudgewhat == 1 then
        r.GetSet_LoopTimeRange(true, false, ts+delta, te, false)
      elseif nudgewhat == 3 then
        r.GetSet_LoopTimeRange(true, false, ts, te+delta, false)
      end
    end

    -- Move cursor if linked
    local linked = r.GetToggleCommandState(40621) == 1
    if linked and (nudgewhat == 0 or nudgewhat == 1 or nudgewhat == 5) then
      r.SetEditCurPos(r.GetCursorPosition() + delta, false, false)
    end

    -- Update razor areas
    nudge_razor(delta, nudgewhat)
  end
end

function M.increase()
  local mode, idx = M.get_state()
  local presets = NUDGE_PRESETS[mode]
  local new_idx = math.max(1, idx - 1)
  if new_idx ~= idx then M.set_state(mode, new_idx) end
  return mode, new_idx
end

function M.decrease()
  local mode, idx = M.get_state()
  local presets = NUDGE_PRESETS[mode]
  local new_idx = math.min(#presets, idx + 1)
  if new_idx ~= idx then M.set_state(mode, new_idx) end
  return mode, new_idx
end

function M.get_label()
  local mode, idx = M.get_state()
  local preset = M.get_preset(mode, idx)
  if not preset then return '?' end
  return preset.label
end

return M