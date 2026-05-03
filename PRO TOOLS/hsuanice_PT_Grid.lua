--[[
@description hsuanice_PT_Grid - Grid Library
@version 0.1.0 [260503.1314]
@author hsuanice
@about
  Library for grid mode handling, parallel to hsuanice_PT_Nudge.lua.
  Reads grid mode and preset from hsuanice_Grid Nudge Panel ExtState.

  Modes (parallel to Nudge):
    Measure     - REAPER native bar divisions (no tempo dependence)
    Min:Secs    - simulated via tempo: secs * BPM / 240 = grid_div
    Timecode    - simulated via tempo + project FPS
    Feet+Frames - simulated via tempo + project FPS (1 foot = 16 frames)
    Samples     - simulated via tempo + project sample rate

  Simulated modes assume constant project tempo. ensure_tempo() prompts
  the user to set BPM to 120 (or proceed at current BPM, or cancel).

@changelog
  0.1.0 [260503.1314]
    - Initial release. Replaces the inline Native/Timecode-only logic in
      hsuanice_Grid Nudge Panel.lua and the Increase/Decrease scripts.
--]]

local r = reaper
local EXT = 'hsuanice_GridNudgePanel'

local GRID_MODES = {'Measure', 'Min:Secs', 'Timecode', 'Feet+Frames', 'Samples'}

-- Presets are ordered LARGEST -> SMALLEST so increase = idx-1, decrease = idx+1
-- (matches hsuanice_PT_Nudge.lua convention)
local GRID_PRESETS = {
  ['Measure'] = {
    {label='4 bars',  div=4},
    {label='2 bars',  div=2},
    {label='1 bar',   div=1},
    {label='1/2',     div=1/2},
    {label='1/4',     div=1/4},
    {label='1/4T',    div=1/(4*1.5)},
    {label='1/8',     div=1/8},
    {label='1/8T',    div=1/(8*1.5)},
    {label='1/16',    div=1/16},
    {label='1/16T',   div=1/(16*1.5)},
    {label='1/32',    div=1/32},
    {label='1/32T',   div=1/(32*1.5)},
    {label='1/64',    div=1/64},
    {label='1/128',   div=1/128},
  },
  ['Min:Secs'] = {
    {label='1 second', unit=1, value=1},
    {label='500 msec', unit=0, value=500},
    {label='100 msec', unit=0, value=100},
    {label='10 msec',  unit=0, value=10},
    {label='1 msec',   unit=0, value=1},
  },
  ['Timecode'] = {
    {label='1 second',    unit=1,  value=1},
    {label='6 frames',    unit=18, value=6},
    {label='1 frame',     unit=18, value=1},
    {label='1/2 frame',   unit=18, value=0.5},
    {label='1/4 frame',   unit=18, value=0.25},
    {label='1 sub frame', unit=18, value=0.01},
  },
  ['Feet+Frames'] = {
    {label='1 foot',      unit=18, value=16},
    {label='1 frame',     unit=18, value=1},
    {label='1/4 frame',   unit=18, value=0.25},
    {label='1 sub frame', unit=18, value=0.01},
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
M.MODES   = GRID_MODES
M.PRESETS = GRID_PRESETS

local function is_valid_mode(m)
  for _, v in ipairs(GRID_MODES) do if v == m then return true end end
  return false
end

function M.get_state()
  local mode = r.GetExtState(EXT, 'grid_mode')
  -- Migrate old key from earlier 0.3.0 design (Native/Timecode dichotomy)
  if mode == 'Native' then mode = 'Measure' end
  if not is_valid_mode(mode) then mode = 'Measure' end
  local presets = GRID_PRESETS[mode]
  local idx = tonumber(r.GetExtState(EXT, 'grid_preset_idx')) or 1
  if idx < 1 then idx = 1 elseif idx > #presets then idx = #presets end
  return mode, idx
end

function M.set_state(mode, idx)
  r.SetExtState(EXT, 'grid_mode',       mode,          true)
  r.SetExtState(EXT, 'grid_preset_idx', tostring(idx), true)
end

function M.get_preset(mode, idx)
  local p = GRID_PRESETS[mode]
  if not p then return nil end
  return p[idx]
end

function M.preset_to_seconds(preset)
  if not preset or not preset.unit then return 0 end
  if preset.unit == 0 then return preset.value / 1000 end
  if preset.unit == 1 then return preset.value end
  if preset.unit == 17 then
    local sr = r.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false)
    if not sr or sr <= 0 then sr = 48000 end
    return preset.value / sr
  end
  if preset.unit == 18 then
    local _, fps = r.TimeMap_curFrameRate(0)
    if not fps or fps <= 0 then fps = 24 end
    return preset.value / fps
  end
  return 0
end

function M.preset_to_div(mode, preset)
  if not preset then return 1 end
  if mode == 'Measure' then return preset.div end
  local secs = M.preset_to_seconds(preset)
  local bpm  = r.GetProjectTimeSignature2(0)
  if not bpm or bpm <= 0 then bpm = 120 end
  -- 1 bar at 4/4 = 240/BPM seconds → bar_div = secs * BPM / 240
  return secs * bpm / 240
end

function M.format_value(mode, preset)
  if not preset then return '?' end

  if mode == 'Measure' then return preset.label end

  if mode == 'Timecode' then
    local _, fps = r.TimeMap_curFrameRate(0)
    if not fps or fps <= 0 then fps = 24 end
    if preset.unit == 1 then return '00:00:01:00.00' end
    local frames = preset.value
    local whole_f = math.floor(frames)
    local sub = frames - whole_f
    local secs = math.floor(whole_f / fps)
    local ff = whole_f % fps
    local mm = math.floor(secs / 60); local ss = secs % 60
    local hh = math.floor(mm / 60);   mm = mm % 60
    return string.format('%02d:%02d:%02d:%02d.%02d',
      hh, mm, ss, ff, math.floor(sub * 100 + 0.5))
  end

  if mode == 'Feet+Frames' then
    if preset.label == '1 foot' then return '1+00.00' end
    local f = preset.value
    if f < 1 then return string.format('0+00.%02d', math.floor(f*100)) end
    return string.format('0+%02d.00', math.floor(f))
  end

  if mode == 'Min:Secs' then
    local ms = preset.unit == 1 and (preset.value * 1000) or preset.value
    local total_s = math.floor(ms / 1000)
    local rem_ms  = math.floor(ms % 1000)
    local mm = math.floor(total_s / 60); local ss = total_s % 60
    if rem_ms > 0 then return string.format('%02d:%02d.%03d', mm, ss, rem_ms) end
    return string.format('%02d:%02d.000', mm, ss)
  end

  if mode == 'Samples' then
    return tostring(math.floor(preset.value))
  end

  return preset.label
end

-- Returns: ok (true to proceed, false to cancel)
-- For non-Measure modes, prompts user if BPM != 120.
-- "Yes"    → sets BPM to 120 then proceeds (accurate).
-- "No"     → proceeds at current BPM (may drift).
-- "Cancel" → abort.
function M.ensure_tempo(mode)
  if mode == 'Measure' then return true end
  local bpm = r.GetProjectTimeSignature2(0)
  if bpm and math.abs(bpm - 120) <= 0.01 then return true end

  local msg = string.format(
    'Project tempo is %.2f BPM (not 120).\n\n' ..
    'The "%s" grid is simulated via tempo calculation.\n' ..
    'Spacing is exact at 120 BPM and may drift if tempo changes.\n\n' ..
    'Set project tempo to 120 BPM now?\n\n' ..
    '  Yes    - set BPM to 120 and apply the grid\n' ..
    '  No     - apply the grid at current BPM (may drift)\n' ..
    '  Cancel - abort',
    bpm or 0, mode)
  local ret = r.MB(msg, 'Grid: Tempo Mismatch', 3)  -- 3 = Yes/No/Cancel
  if ret == 6 then  -- Yes
    r.SetCurrentBPM(0, 120, true)
    return true
  elseif ret == 7 then  -- No
    return true
  end
  return false  -- Cancel (2) or window closed
end

function M.apply(mode, idx)
  local preset = M.get_preset(mode, idx)
  if not preset then return end
  if r.GetToggleCommandState(40904) == 1 then
    r.Main_OnCommand(40904, 0)  -- turn off Frame grid
  end
  local _, _, swing = r.GetSetProjectGrid(0, 0)
  local div = M.preset_to_div(mode, preset)
  if swing == 3 then
    r.GetSetProjectGrid(0, 1, div, 0)  -- clear Measure swing
  else
    r.GetSetProjectGrid(0, 1, div)
  end
  M.set_state(mode, idx)
end

-- Find closest preset to current grid_div (for Measure resync after the
-- user changed grid externally via REAPER's native UI).
local function closest_idx(mode, grid_div)
  local presets = GRID_PRESETS[mode]
  if not presets then return 1 end
  local best_i, best_d = 1, math.huge
  for i, p in ipairs(presets) do
    local pd = (mode == 'Measure') and p.div or M.preset_to_div(mode, p)
    local d = math.abs(grid_div - pd)
    if d < best_d then best_d = d; best_i = i end
  end
  return best_i
end

function M.increase()
  local mode, idx = M.get_state()
  if mode == 'Measure' then
    local _, grid_div = r.GetSetProjectGrid(0, 0)
    idx = closest_idx(mode, grid_div)
  end
  local new_idx = math.max(1, idx - 1)
  if new_idx ~= idx or mode == 'Measure' then
    M.apply(mode, new_idx)
  end
  return mode, new_idx
end

function M.decrease()
  local mode, idx = M.get_state()
  if mode == 'Measure' then
    local _, grid_div = r.GetSetProjectGrid(0, 0)
    idx = closest_idx(mode, grid_div)
  end
  local presets = GRID_PRESETS[mode]
  local new_idx = math.min(#presets, idx + 1)
  if new_idx ~= idx or mode == 'Measure' then
    M.apply(mode, new_idx)
  end
  return mode, new_idx
end

function M.get_text()
  if r.GetToggleCommandState(40904) == 1 then return 'Frame' end

  local _, grid_div, swing = r.GetSetProjectGrid(0, 0)
  if grid_div ~= grid_div then grid_div = 1 end

  local mode, idx = M.get_state()
  local preset = M.get_preset(mode, idx)

  if mode == 'Measure' then
    if swing == 3 then return 'Measure' end
    if preset and math.abs(grid_div - preset.div) < 1e-8 then
      return preset.label
    end
    if grid_div >= 1 then return string.format('%d bar', math.floor(grid_div+0.5)) end
    local denom = math.floor(1/grid_div + 0.5)
    return '1/' .. denom
  end

  -- Simulated mode: validate against the saved preset
  if preset then
    local expected = M.preset_to_div(mode, preset)
    local denom = math.max(math.abs(expected), 1e-9)
    if math.abs(grid_div - expected) / denom < 5e-3 then
      return M.format_value(mode, preset)
    end
  end

  -- Mismatch (user changed grid externally): show fallback text WITHOUT
  -- auto-reverting the saved mode, so the menu still shows the user's
  -- chosen mode and presets — they can pick one to re-align.
  if swing == 3 then return 'Measure' end
  if grid_div >= 1 then return string.format('%d bar', math.floor(grid_div+0.5)) end
  local denom = math.floor(1/grid_div + 0.5)
  return '1/' .. denom
end

return M
