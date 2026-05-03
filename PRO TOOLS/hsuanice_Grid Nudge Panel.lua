--[[
@description hsuanice_Grid Nudge Panel
@version 0.4.9 [260503.1918]
@author hsuanice
@link https://forum.cockos.com/showthread.php?p=2910884#post2910884
@about
  Persistent GFX panel showing current Grid and Nudge settings.
  Can be docked into Reaper's docker.
  Click Grid row to change grid. Click Nudge row to change nudge.

  Inspired by Pro Tools transport display.

  Grid logic now lives in hsuanice_PT_Grid.lua (parallel to PT_Nudge).

@changelog
  0.4.9 [260503.1918]
    - Picks up hsuanice_PT_Grid 0.3.4: auto-resync on project fps/BPM
      change so grid panel doesn't jump to a fallback when fps changes.
  0.4.8 [260503.1909]
    - Fix: format_nudge_value swapped TimeMap_curFrameRate return values.
      Same bug as PT_Grid 0.3.3 — fps was being captured as isdrop, so
      Nudge "Timecode" mode display was always computed at 24 fps and
      crashed on drop-frame projects.
    - Picks up hsuanice_PT_Grid 0.3.3.
  0.4.7 [260503.1550]
    - Picks up hsuanice_PT_Grid 0.3.2: deferred retry chain to keep
      Frame grid OFF when REAPER state re-engages it after our toggle.
  0.4.6 [260503.1528]
    - Picks up hsuanice_PT_Grid 0.3.1: Metronome preset removed (couldn't
      sync reliably and the implementation had a denominator/tempo bug).
  0.4.5 [260503.1509]
    - Picks up hsuanice_PT_Grid 0.3.0: adds "Metronome" preset to Measure
      mode. Sets grid_div = 1/denom (4/4 → 1/4, 6/8 → 1/8, etc.).
  0.4.4 [260503.1442]
    - Picks up hsuanice_PT_Grid 0.2.3: log spam fix + Measure auto-sync.
  0.4.3 [260503.1439]
    - Right-click menu adds "Debug log" toggle and "Clear ReaScript console".
      Output goes to View → Show ReaScript console output. Useful for
      diagnosing intermittent grid-switch issues.
  0.4.2 [260503.1428]
    - Picks up hsuanice_PT_Grid 0.2.1: defensive grid_div writes around
      command 40904 toggle. Fixes "first attempt fails, second works"
      symptom when leaving Timecode "1 frame" (native_frame).
  0.4.1 [260503.1409]
    - Timecode "1 frame" and Feet+Frames "1 frame" now engage REAPER's
      built-in Frame grid (cmd 40904) under the hood — exact, tempo-free.
      Display still shows the TC string (e.g. "00:00:00:01.00").
    - Mode switch picks DEFAULT_IDX per mode (Timecode / Feet+Frames land
      on "1 frame" → no tempo prompt fires when you just switch modes).
  0.4.0 [260503.1314]
    - Restructure: Grid menu now mirrors Nudge — 5 modes
      (Measure / Min:Secs / Timecode / Feet+Frames / Samples).
      Top half = preset values, bottom half = mode list.
    - Fix: simulated modes (non-Measure) at BPM != 120 used to silently
      auto-revert to Native because of float-rounding mismatch. Tolerance
      loosened (5e-3) and auto-revert removed.
    - Add: when switching into a simulated mode at BPM != 120, prompt
      Yes/No/Cancel — Yes sets BPM to 120, No proceeds (may drift).
    - Refactor: shared logic moved to Library/PRO TOOLS/hsuanice_PT_Grid.lua,
      which Increase/Decrease Grid Value scripts also consume.
    - Note: Frame grid (40904) is still detected and displayed as "Frame",
      but no longer a menu entry — pick a Measure / Timecode preset instead.
  0.3.0 [260502.1928]
    - Add: Grid "Timecode" mode (1 sec / 6 frames / 1 frame / 1/2 / 1/4 / 1 sub frame)
      Simulated via tempo calculation; assumes constant tempo (post-production).
    - Add: Tempo warning when switching Grid into Timecode mode if BPM != 120.
    - Add: Auto-revert Grid mode to Native when grid_div changes externally.
    - Sync: Increase/Decrease Grid Value scripts iterate TC presets in TC mode.
  0.2.0 [260418.2036]
    - Rewrite: GFX window instead of JS_Composite (more stable, dockable)
    - Fix: menu index was off-by-one (gfx.showmenu is 1-based)
    - Fix: Bars+Beats and Min-Secs display names
  0.1.8 [260418.2031]
    - Fix: Min:Secs colon was triggering submenu in gfx menu
  0.1.7 [260418.2017]
    - Fix: window switch during drag
  0.1.6 [260418.1943]
    - TC format: always HH:MM:SS:FF.XX
  0.1.5 [260418.1931]
    - Fix: NUDGE_MODES, grid menu Reaper native values
  0.1.0 [260418.1534]
    - Initial release (JS_Composite)
--]]

local r = reaper
local EXT = 'hsuanice_GridNudgePanel'

-- ============================================================
-- LOAD GRID LIBRARY (parallel to hsuanice_PT_Nudge.lua)
-- ============================================================
local Grid
do
  local info = debug.getinfo(1, 'S')
  local script_dir = info.source:match('^@(.*[/\\])') or ''
  local ok, lib = pcall(dofile, script_dir .. 'hsuanice_PT_Grid.lua')
  if not ok or type(lib) ~= 'table' then
    r.MB('Failed to load hsuanice_PT_Grid.lua from:\n' .. script_dir,
      'Grid Nudge Panel', 0)
    return
  end
  Grid = lib
end

-- ============================================================
-- NUDGE PRESET DEFINITIONS
-- ============================================================
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

-- ============================================================
-- NUDGE VALUE FORMATTER
-- ============================================================
local function format_nudge_value(mode, preset)
  if not preset then return '?' end
  -- NB: TimeMap_curFrameRate returns (fps, isdrop) — fps FIRST. Capturing
  -- the second return as fps was a long-standing bug that defaulted to 24
  -- everywhere and crashed on drop-frame projects.
  local fps = r.TimeMap_curFrameRate(0)
  if not fps or fps <= 0 then fps = 24 end

  if mode == 'Timecode' then
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

  elseif mode == 'Feet+Frames' then
    if preset.label == '1 foot' then return '1+00.00' end
    local f = preset.value
    if f < 1 then return string.format('0+00.%02d', math.floor(f*100)) end
    return string.format('0+%02d.00', math.floor(f))

  elseif mode == 'Min:Secs' then
    local ms = preset.unit == 1 and (preset.value * 1000) or preset.value
    local total_s = math.floor(ms / 1000)
    local rem_ms  = math.floor(ms % 1000)
    local mm = math.floor(total_s / 60); local ss = total_s % 60
    if rem_ms > 0 then return string.format('%02d:%02d.%03d', mm, ss, rem_ms) end
    return string.format('%02d:%02d.000', mm, ss)

  elseif mode == 'Measure' then
    if preset.unit == 16 then
      local bars = math.floor(preset.value)
      if bars >= 1 then return string.format('%d|00|000', bars) end
      return '0|01|000'
    else
      local ticks = ({[10]=1920,[9]=960,[8]=480,[7]=240,[6]=120,[5]=60})[preset.unit] or 960
      if ticks >= 960 then return string.format('0|%02d|000', ticks//960) end
      return string.format('0|00|%03d', ticks)
    end

  elseif mode == 'Samples' then
    return tostring(math.floor(preset.value))
  end
  return preset.label
end

-- ============================================================
-- STATE
-- ============================================================
local function save_nudge(mode, idx)
  r.SetExtState(EXT, 'nudge_mode',       mode,          true)
  r.SetExtState(EXT, 'nudge_preset_idx', tostring(idx), true)
  r.SetExtState(EXT, 'nudge_changed',    '1',           false)
end

local function load_nudge()
  local mode = r.GetExtState(EXT, 'nudge_mode')
  if mode == '' then mode = 'Timecode' end
  -- Migrate old key names
  if mode == 'Frames' or mode == 'Feet+Frames' then mode = 'Feet+Frames' end
  if mode == 'Bars|Beats' or mode == 'Bars' or mode == 'Beats' then mode = 'Measure' end
  local idx = tonumber(r.GetExtState(EXT, 'nudge_preset_idx')) or 3
  local valid = false
  for _, m in ipairs(NUDGE_MODES) do if m == mode then valid=true; break end end
  if not valid then mode='Timecode'; idx=3 end
  local p = NUDGE_PRESETS[mode]
  return mode, math.max(1, math.min(idx, #p))
end

-- ============================================================
-- GRID HELPERS (delegated to hsuanice_PT_Grid.lua)
-- ============================================================
local function get_grid_text()
  return Grid.get_text()
end

-- ============================================================
-- MENUS  (gfx.showmenu is 1-based)
-- ============================================================
local function popup_menu(items)
  -- items: list of strings, '' = separator
  -- returns 1-based index of selected item (0 = nothing)
  local menu_str = ''
  for _, item in ipairs(items) do
    if item == '' then menu_str = menu_str .. '|'
    else menu_str = menu_str .. item .. '|' end
  end
  gfx.x, gfx.y = gfx.mouse_x, gfx.mouse_y
  return gfx.showmenu(menu_str)
end

local function show_grid_menu()
  local cur_mode, cur_idx = Grid.get_state()
  local presets = Grid.PRESETS[cur_mode] or {}
  local entries = {}

  -- Top half: preset values for the current mode
  for i, p in ipairs(presets) do
    local target_idx = i
    local target_preset = p
    entries[#entries+1] = {
      label = (i == cur_idx and '!' or '') .. p.label,
      action = function()
        if Grid.ensure_tempo(cur_mode, target_preset) then
          Grid.apply(cur_mode, target_idx)
        end
      end,
    }
  end
  entries[#entries+1] = {sep=true}

  -- Bottom half: mode list. Mode switch picks a sensible default preset
  -- (DEFAULT_IDX prefers native_frame when available → no tempo prompt).
  for _, m in ipairs(Grid.MODES) do
    local target_mode = m
    entries[#entries+1] = {
      label = (m == cur_mode and '!' or '') .. m,
      action = function()
        if target_mode == cur_mode then return end
        local def_idx = Grid.get_default_idx(target_mode)
        local def_preset = Grid.get_preset(target_mode, def_idx)
        if Grid.ensure_tempo(target_mode, def_preset) then
          Grid.apply(target_mode, def_idx)
        end
      end,
    }
  end

  -- Render to gfx menu and dispatch
  local labels = {}
  for _, e in ipairs(entries) do
    labels[#labels+1] = e.sep and '' or e.label
  end
  local ret = popup_menu(labels)
  if ret == 0 then return end

  local count = 0
  for _, e in ipairs(entries) do
    if not e.sep then
      count = count + 1
      if count == ret then e.action(); return end
    end
  end
end

local function show_nudge_menu(cur_mode, cur_idx)
  local presets = NUDGE_PRESETS[cur_mode]
  local items = {}

  -- Presets first (ret 1..#presets)
  for i, p in ipairs(presets) do
    items[#items+1] = (i == cur_idx and '!' or '') .. p.label
  end
  -- Separator (not counted in ret)
  items[#items+1] = ''
  -- Modes (ret #presets+1 .. #presets+#NUDGE_MODES)
  for _, m in ipairs(NUDGE_MODES) do
    items[#items+1] = (m == cur_mode and '!' or '') .. m
  end

  local ret = popup_menu(items)
  if ret == 0 then return cur_mode, cur_idx end

  -- Preset selected
  if ret <= #presets then
    return cur_mode, ret
  end
  -- Mode selected: separator skipped, so mode index = ret - #presets
  local mi = ret - #presets
  if mi >= 1 and mi <= #NUDGE_MODES then
    return NUDGE_MODES[mi], 1
  end
  return cur_mode, cur_idx
end

-- ============================================================
-- DRAWING
-- ============================================================
local FONT_SIZE = 13  -- fixed font size regardless of window size
local PAD = 6
local LABEL_W = 46

local function set_col(hex)
  local n = tonumber(hex, 16) or 0
  gfx.r = ((n>>16)&0xFF)/255
  gfx.g = ((n>>8)&0xFF)/255
  gfx.b = (n&0xFF)/255
  gfx.a = 1
end

local function draw(grid_text, nudge_mode, nudge_text)
  local w, h = gfx.w, gfx.h
  local row = h // 2

  -- Clear entire background first
  set_col('1a1a1a'); gfx.rect(0, 0, w, h, 1)

  -- Label backgrounds
  set_col('111111')
  gfx.rect(0, 0,   LABEL_W, row, 1)
  gfx.rect(0, row, LABEL_W, h - row, 1)

  -- Dividers
  set_col('333333')
  gfx.rect(0, row, w, 1, 1)          -- horizontal
  gfx.rect(LABEL_W, 0, 1, h, 1)      -- vertical

  -- Fixed font size
  gfx.setfont(1, 'Arial', FONT_SIZE)
  local th = gfx.texth

  -- Labels (grey)
  set_col('888888')
  gfx.x = PAD; gfx.y = (row - th) // 2
  gfx.drawstr('Grid')
  gfx.x = PAD; gfx.y = row + (row - th) // 2
  gfx.drawstr('Nudge')

  -- Values (green)
  set_col('00dd00')
  gfx.x = LABEL_W + PAD; gfx.y = (row - th) // 2
  gfx.drawstr(grid_text)
  gfx.x = LABEL_W + PAD; gfx.y = row + (row - th) // 2
  gfx.drawstr(nudge_text)
end

-- ============================================================
-- MAIN
-- ============================================================
local nudge_mode, nudge_idx = load_nudge()
local prev_mouse_cap = 0
local done = false

-- Load saved size
local init_w = tonumber(r.GetExtState(EXT, 'gfx_w')) or 220
local init_h = tonumber(r.GetExtState(EXT, 'gfx_h')) or 36
init_w = math.max(80, init_w)
init_h = math.max(28, init_h)

gfx.init('hsuanice_Grid Nudge Panel', init_w, init_h, -1)
gfx.clear = 0x1a1a1a
-- Pass keyboard shortcuts through to Reaper (don't steal focus)
if reaper.set_action_options then reaper.set_action_options(1) end

local function frame()
  if done then return end
  local c = gfx.getchar()
  if c == -1 then done = true; return end
  -- Note: no key handling here — all keys pass through to Reaper

  -- Mouse click handling (on button release)
  local mb = gfx.mouse_cap & 3
  local just_released_l = (mb & 1 == 0) and (prev_mouse_cap & 1 == 1)
  local just_released_r = (mb & 2 == 0) and (prev_mouse_cap & 2 == 2)

  -- After any interaction, return focus to main window so shortcuts work
  local function refocus_main()
    r.JS_Window_SetFocus(r.GetMainHwnd())
  end

  if just_released_l then
    local row = gfx.h // 2
    if gfx.mouse_y < row then
      show_grid_menu()
    else
      local nm, ni = show_nudge_menu(nudge_mode, nudge_idx)
      if nm ~= nudge_mode or ni ~= nudge_idx then
        nudge_mode, nudge_idx = nm, ni
        save_nudge(nudge_mode, nudge_idx)
      end
    end
    refocus_main()
  end

  if just_released_r then
    local dbg_on = Grid.is_debug()
    local items = {
      'Size: Small (160x28)',
      'Size: Medium (220x36)',
      'Size: Large (280x46)',
      'Size: Custom...',
      '',  -- separator
      (dbg_on and '!' or '') .. 'Debug log (ReaScript console)',
      'Clear ReaScript console',
    }
    local ret = popup_menu(items)
    local nw, nh
    if     ret == 1 then nw, nh = 160, 28
    elseif ret == 2 then nw, nh = 220, 36
    elseif ret == 3 then nw, nh = 280, 46
    elseif ret == 4 then
      local ok, vals = r.GetUserInputs('Size', 2, 'Width:,Height:',
        gfx.w..','..gfx.h)
      if ok then
        local p = {}
        for v in (vals..','):gmatch('([^,]*),') do p[#p+1]=tonumber(v) end
        nw = p[1] and math.max(80, p[1])
        nh = p[2] and math.max(28, p[2])
      end
    elseif ret == 5 then
      Grid.set_debug(not dbg_on)
      -- Grid.set_debug already appends a line to the console when turning ON,
      -- which auto-opens the console window.
    elseif ret == 6 then
      if r.ClearConsole then r.ClearConsole() end
    end
    if nw and nh then
      gfx.quit()
      gfx.init('hsuanice_Grid Nudge Panel', nw, nh, -1)
      gfx.clear = 0x1a1a1a
      r.SetExtState(EXT, 'gfx_w', tostring(nw), true)
      r.SetExtState(EXT, 'gfx_h', tostring(nh), true)
    end
    refocus_main()
  end

  prev_mouse_cap = mb

  -- Check nudge changed externally
  if r.GetExtState(EXT, 'nudge_changed') == '1' then
    r.SetExtState(EXT, 'nudge_changed', '0', false)
    nudge_mode, nudge_idx = load_nudge()
  end

  local grid_text  = get_grid_text()
  local nudge_text = format_nudge_value(nudge_mode, NUDGE_PRESETS[nudge_mode][nudge_idx])

  draw(grid_text, nudge_mode, nudge_text)
  gfx.update()

  r.defer(frame)
end

local _, _, sec, cmd = r.get_action_context()
r.SetToggleCommandState(sec, cmd, 1)
r.RefreshToolbar2(sec, cmd)

r.atexit(function()
  r.SetToggleCommandState(sec, cmd, 0)
  r.RefreshToolbar2(sec, cmd)
  r.SetExtState(EXT, 'gfx_w', tostring(gfx.w), true)
  r.SetExtState(EXT, 'gfx_h', tostring(gfx.h), true)
  gfx.quit()
end)

r.defer(frame)