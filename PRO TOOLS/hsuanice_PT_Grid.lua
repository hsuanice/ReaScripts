--[[
@description hsuanice_PT_Grid - Grid Library
@version 0.3.1 [260503.1528]
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

  "1 frame" presets in Timecode and Feet+Frames are flagged native_frame:
  they engage REAPER's built-in Frame grid (command 40904) instead of
  tempo simulation, so they're exact regardless of tempo. The panel still
  shows the TC string (e.g. "00:00:00:01.00") — the difference is
  internal only.

@changelog
  0.3.1 [260503.1528]
    - Remove Metronome preset (added in 0.3.0). Reasons:
      (1) REAPER's native "Metronome" dropdown isn't a distinct API state,
          so we couldn't reliably sync it from REAPER → panel.
      (2) The dynamic 1/denom calculation depended on
          TimeMap_GetTimeSigAtTime returning denominator at index 3, but
          empirically position 3 is tempo (e.g. 120), not denominator —
          so apply produced grid_div = 1/120, not 1/4 at 4/4.
      Use a specific beat preset (1/4, 1/8, etc.) for the equivalent grid.
    - DEFAULT_IDX[Measure] reverts 6 → 5.
  0.3.0 [260503.1509]
    - Add "Metronome" preset to Measure mode (idx 1). Sets grid_div to
      1/denom based on the current time signature (4/4 → 1/4 note, 6/8
      → 1/8 note, 3/2 → 1/2 note). Display label: "Metronome".
    - REAPER's native "Metronome" dropdown isn't a distinct API state — it
      just clears Frame/Measure flags back to the last beat grid_div. So
      we can't auto-sync our panel into "Metronome" when the user picks
      it natively; auto-sync prefers fixed presets instead. To get
      "Metronome" behavior in our panel, pick it from our menu.
    - Increase/Decrease skip Metronome in the cycle (its idx position
      doesn't reflect its grid_div magnitude, so stepping onto it would
      cause an unnatural jump).
    - DEFAULT_IDX[Measure] bumped 5 → 6 because Metronome was inserted
      at idx 1; "1/4" is still the default.
  0.2.3 [260503.1442]
    - Fix: get_text was logging "sim_mismatch" on every frame in non-Measure
      modes when grid_div drifted from saved preset, flooding the ReaScript
      console (~30 Hz) when REAPER's native grid was changed externally.
      The mismatch case now relies on the wrapper's per-transition log.
    - Add: Measure mode preset_idx auto-syncs to grid_div when an exact
      preset match is found (e.g. user picks "1/8" via REAPER's native grid
      menu → our panel's check-mark moves to "1/8").
  0.2.2 [260503.1439]
    - Add debug logging gated by ExtState 'debug' = '1'. Toggle from the
      Grid Nudge Panel's right-click menu. Logs each apply() step
      (40904 state, grid_div, swing, BPM) and get_text() decisions
      (rate-limited to transitions). Use to diagnose stuck-on-Frame.
    - Add M.set_debug(bool) and M.is_debug() helpers.
  0.2.1 [260503.1428]
    - Fix: switching from a native_frame preset (Frame grid on) to a
      simulated preset (e.g. Timecode "1/2 frame") sometimes displayed
      the previous grid value (e.g. "1/8") on the first attempt and only
      worked on the second. REAPER's command 40904 (toggle Frame grid)
      appears to reset grid_div as a side-effect when going on→off.
      apply() now writes grid_div BEFORE the toggle, AFTER the toggle,
      and once more on the next event loop iteration via r.defer.
    - Loosen get_text validation tolerance from 0.5% to 1% to handle
      finer grids (e.g. 1 sub frame ≈ 1/4800) where REAPER's float
      storage may round slightly.
  0.2.0 [260503.1409]
    - Add native_frame flag on Timecode/Feet+Frames "1 frame" presets.
      Engages REAPER's command 40904 (Frame grid) — exact, tempo-free.
      Panel still displays the TC format string for these presets.
    - Add M.DEFAULT_IDX so mode toggle picks the most useful starting
      preset (e.g. switching to Timecode lands on "1 frame" / native).
    - ensure_tempo accepts an optional preset arg and skips the prompt
      when preset.native_frame is set.
    - increase/decrease bail when external Frame grid is engaged AND
      saved state isn't a native_frame preset (preserves user intent).
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
    -- Note: REAPER's native "Metronome" dropdown entry isn't a distinct API
    -- state (it just clears Frame/Measure flags back to the last beat
    -- grid_div), so we can't sync it from our side. Use a specific beat
    -- preset (e.g. 1/4) for the same effect.
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
    {label='1 frame',     unit=18, value=1, native_frame=true},
    {label='1/2 frame',   unit=18, value=0.5},
    {label='1/4 frame',   unit=18, value=0.25},
    {label='1 sub frame', unit=18, value=0.01},
  },
  ['Feet+Frames'] = {
    {label='1 foot',      unit=18, value=16},
    {label='1 frame',     unit=18, value=1, native_frame=true},
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

-- Smart default preset per mode (used when switching mode via the panel).
-- Prefers native_frame where available so the user lands on a tempo-free
-- preset by default (no tempo prompt on mode switch).
local DEFAULT_IDX = {
  ['Measure']     = 5,  -- "1/4"
  ['Min:Secs']    = 1,  -- "1 second"
  ['Timecode']    = 3,  -- "1 frame"   (native_frame)
  ['Feet+Frames'] = 2,  -- "1 frame"   (native_frame)
  ['Samples']     = 2,  -- "1000 samples"
}

local M = {}
M.MODES       = GRID_MODES
M.PRESETS     = GRID_PRESETS
M.DEFAULT_IDX = DEFAULT_IDX

function M.get_default_idx(mode)
  return DEFAULT_IDX[mode] or 1
end

-- ============================================================
-- DEBUG LOGGING (gated by ExtState "debug" = "1")
-- Toggle via the Grid Nudge Panel's right-click menu, or:
--   reaper.SetExtState('hsuanice_GridNudgePanel', 'debug', '1', false)
-- Output goes to the ReaScript console (View → Show ReaScript console).
-- ============================================================
local function dbg_enabled()
  return r.GetExtState(EXT, 'debug') == '1'
end

function M.set_debug(on)
  r.SetExtState(EXT, 'debug', on and '1' or '0', false)
  if on then
    r.ShowConsoleMsg('[hsuanice_PT_Grid] debug ON\n')
  end
end

function M.is_debug()
  return dbg_enabled()
end

local function snapshot()
  local frame_on = r.GetToggleCommandState(40904) == 1
  local _, gd, sw = r.GetSetProjectGrid(0, 0)
  local bpm = r.GetProjectTimeSignature2(0) or 0
  return string.format('40904=%s grid_div=%.6f swing=%d bpm=%.2f',
    frame_on and 'ON' or 'OFF', gd or 0, sw or 0, bpm)
end

local function dbg(fmt, ...)
  if not dbg_enabled() then return end
  r.ShowConsoleMsg('[Grid] ' .. string.format(fmt, ...) .. '\n')
end

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
-- For non-Measure / non-native_frame presets, prompts user if BPM != 120.
-- "Yes"    → sets BPM to 120 then proceeds (accurate).
-- "No"     → proceeds at current BPM (may drift).
-- "Cancel" → abort.
function M.ensure_tempo(mode, preset)
  if mode == 'Measure' then return true end
  if preset and preset.native_frame then return true end
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

-- Set grid_div, normalising swing=3 (Measure) to 0 if needed.
local function write_grid_div(div, swing)
  if swing == 3 then
    r.GetSetProjectGrid(0, 1, div, 0)
  else
    r.GetSetProjectGrid(0, 1, div)
  end
end

function M.apply(mode, idx)
  local preset = M.get_preset(mode, idx)
  if not preset then return end

  dbg('apply(%s,%d)=%s native=%s | START %s',
    mode, idx, preset.label, tostring(preset.native_frame == true), snapshot())

  if preset.native_frame then
    if r.GetToggleCommandState(40904) ~= 1 then
      r.Main_OnCommand(40904, 0)
      dbg('  toggled 40904 ON | %s', snapshot())
    end
    M.set_state(mode, idx)
    dbg('apply END (native_frame) | %s', snapshot())
    return
  end

  -- Non-native_frame: write grid_div, BEFORE and AFTER toggling Frame grid
  -- off, plus once more on the next event loop. This is defensive against
  -- REAPER's command 40904 resetting grid_div as a side-effect when going
  -- from Frame-grid-on to Frame-grid-off (observed: first attempt at a
  -- new Timecode preset displays the previous grid value; second attempt
  -- works).
  local _, _, swing = r.GetSetProjectGrid(0, 0)
  local div = M.preset_to_div(mode, preset)
  dbg('  computed div=%.6f swing=%d', div, swing or 0)

  -- 1) Pre-toggle write (in case REAPER reads grid_div during the toggle)
  write_grid_div(div, swing)
  dbg('  step1 (pre-toggle write) | %s', snapshot())

  -- 2) Toggle Frame grid off if currently on
  if r.GetToggleCommandState(40904) == 1 then
    r.Main_OnCommand(40904, 0)
    dbg('  step2 (toggle 40904 OFF) | %s', snapshot())
  end

  -- 3) Post-toggle write (clobber any side-effect reset from the toggle)
  write_grid_div(div, swing)
  dbg('  step3 (post-toggle write) | %s', snapshot())

  M.set_state(mode, idx)
  dbg('apply END (sync) | %s', snapshot())

  -- 4) Deferred re-write — runs on the next event loop iteration, after
  -- REAPER has fully processed the toggle and any internal grid refresh.
  r.defer(function()
    -- Only re-apply if the user is still on the same preset (could have
    -- changed mode/idx via a fast keyboard repeat).
    local cur_mode, cur_idx = M.get_state()
    if cur_mode == mode and cur_idx == idx then
      local _, _, sw = r.GetSetProjectGrid(0, 0)
      write_grid_div(div, sw)
      dbg('  step4 (deferred write) | %s', snapshot())
    else
      dbg('  step4 SKIPPED (state moved to %s/%d)', cur_mode, cur_idx)
    end
  end)
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

-- True when REAPER's Frame grid is engaged but our saved state isn't a
-- native_frame preset — signals user enabled Frame grid externally and we
-- shouldn't override their intent from a keyboard shortcut.
local function frame_grid_external(mode, idx)
  if r.GetToggleCommandState(40904) ~= 1 then return false end
  local preset = M.get_preset(mode, idx)
  return not (preset and preset.native_frame)
end

function M.increase()
  local mode, idx = M.get_state()
  if frame_grid_external(mode, idx) then return mode, idx end
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
  if frame_grid_external(mode, idx) then return mode, idx end
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

local _last_dbg_sig
local function get_text_inner()
  local mode, idx = M.get_state()
  local preset = M.get_preset(mode, idx)
  local frame_on = r.GetToggleCommandState(40904) == 1

  -- Saved preset is native_frame: TC display when Frame grid is on
  if preset and preset.native_frame and frame_on then
    return M.format_value(mode, preset), 'native_frame+frame_on'
  end

  -- Frame grid on but saved preset isn't native_frame → external state
  if frame_on then return 'Frame', 'frame_on,not_native' end

  local _, grid_div, swing = r.GetSetProjectGrid(0, 0)
  if grid_div ~= grid_div then grid_div = 1 end

  if mode == 'Measure' then
    if swing == 3 then return 'Measure', 'measure_swing' end
    if preset and math.abs(grid_div - preset.div) < 1e-8 then
      return preset.label, 'measure_preset_match'
    end
    -- Auto-sync: in Measure mode, if grid_div changed externally (REAPER's
    -- native grid menu), find the closest matching preset and update
    -- preset_idx so the menu's check-mark stays accurate.
    local best_i, best_d = nil, math.huge
    for i, p in ipairs(GRID_PRESETS['Measure']) do
      local d = math.abs(grid_div - p.div)
      if d < best_d then best_d = d; best_i = i end
    end
    if best_i and best_i ~= idx and best_d < 1e-8 then
      M.set_state('Measure', best_i)
      return GRID_PRESETS['Measure'][best_i].label, 'measure_synced'
    end
    if grid_div >= 1 then
      return string.format('%d bar', math.floor(grid_div+0.5)), 'measure_bar'
    end
    local denom = math.floor(1/grid_div + 0.5)
    return '1/' .. denom, 'measure_div'
  end

  -- Simulated mode: validate against saved (non-native_frame) preset
  -- Tolerance is 1% (1e-2) — generous for fine grids like 1/4800 where
  -- REAPER's float storage may round slightly. (No per-frame log here —
  -- the wrapper rate-limits on text/why transition.)
  if preset and not preset.native_frame then
    local expected = M.preset_to_div(mode, preset)
    local denom = math.max(math.abs(expected), 1e-9)
    if math.abs(grid_div - expected) / denom < 1e-2 then
      return M.format_value(mode, preset), 'sim_match'
    end
  end

  -- Mismatch (user changed grid externally): show fallback text WITHOUT
  -- auto-reverting the saved mode, so the menu still shows the user's
  -- chosen mode and presets — they can pick one to re-align.
  if swing == 3 then return 'Measure', 'fallback_measure' end
  if grid_div >= 1 then
    return string.format('%d bar', math.floor(grid_div+0.5)), 'fallback_bar'
  end
  local denom = math.floor(1/grid_div + 0.5)
  return '1/' .. denom, 'fallback_div'
end

function M.get_text()
  local text, why = get_text_inner()
  if dbg_enabled() then
    -- Log on transition (text or "why" branch changed) to avoid frame-rate spam.
    local sig = (text or '') .. '|' .. (why or '')
    if sig ~= _last_dbg_sig then
      dbg('get_text -> "%s" (%s) | %s', text or '?', why or '?', snapshot())
      _last_dbg_sig = sig
    end
  end
  return text
end

return M
