--[[
@description hsuanice_PT_Nudge - Nudge Library
@version 0.3.2 [260419.1037]
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

function M.apply(nudgewhat, reverse)
  local mode, idx = M.get_state()
  local preset = M.get_preset(mode, idx)
  if not preset then return end

  -- Record first selected item position before nudge
  local r = reaper
  local first_it = r.GetSelectedMediaItem(0, 0)
  local pos_before, len_before
  if first_it then
    pos_before = r.GetMediaItemInfo_Value(first_it, 'D_POSITION')
    len_before  = r.GetMediaItemInfo_Value(first_it, 'D_LENGTH')
  end

  -- Apply nudge
  r.ApplyNudge(0, 0, nudgewhat, preset.unit, preset.value, reverse, 0)

  -- Calculate actual delta from first selected item
  local delta = 0
  if first_it and pos_before then
    if nudgewhat == 0 or nudgewhat == 5 then
      -- position: delta = new pos - old pos
      delta = r.GetMediaItemInfo_Value(first_it, 'D_POSITION') - pos_before
    elseif nudgewhat == 1 then
      -- left trim: delta = new pos - old pos
      delta = r.GetMediaItemInfo_Value(first_it, 'D_POSITION') - pos_before
    elseif nudgewhat == 3 then
      -- right edge: delta = new end - old end
      local new_end = r.GetMediaItemInfo_Value(first_it, 'D_POSITION') +
                      r.GetMediaItemInfo_Value(first_it, 'D_LENGTH')
      delta = new_end - (pos_before + len_before)
    end
    -- nudgewhat==4 (contents): delta stays 0, selection doesn't move
  end

  -- Update time selection, razor areas, and edit cursor
  if math.abs(delta) > 1e-10 then
    local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    local has_ts = te > ts + 1e-4

    if has_ts then
      if nudgewhat == 0 or nudgewhat == 5 then
        -- position: move both ends
        r.GetSet_LoopTimeRange(true, false, ts + delta, te + delta, false)
      elseif nudgewhat == 1 then
        -- start: move left end only
        r.GetSet_LoopTimeRange(true, false, ts + delta, te, false)
      elseif nudgewhat == 3 then
        -- end: move right end only
        r.GetSet_LoopTimeRange(true, false, ts, te + delta, false)
      end
    end

    -- Move edit cursor when Loop linked to time selection is ON
    -- and nudge affects item position or start
    local linked = r.GetToggleCommandState(40621) == 1
    if linked and (nudgewhat == 0 or nudgewhat == 1 or nudgewhat == 5) then
      local cursor = r.GetCursorPosition()
      r.SetEditCurPos(cursor + delta, false, false)
    end

    -- Update razor areas by same delta
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
            end
          end
          return a..' '..b..' '..c
        end)
        r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', new_s, true)
      end
    end
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