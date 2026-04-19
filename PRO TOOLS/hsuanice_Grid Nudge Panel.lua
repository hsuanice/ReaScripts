--[[
@description hsuanice_Grid Nudge Panel
@version 0.2.3 [260419.1002]
@author hsuanice
@link https://forum.cockos.com/showthread.php?p=2910884#post2910884
@about
  Persistent GFX panel showing current Grid and Nudge settings.
  Can be docked into Reaper's docker.
  Click Grid row to change grid. Click Nudge row to change nudge.

  Inspired by Pro Tools transport display.

@changelog
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
  local _, fps = r.TimeMap_curFrameRate(0)
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
-- GRID HELPERS
-- ============================================================
local function get_grid_text()
  if r.GetToggleCommandState(40904) == 1 then return 'Frame' end
  local _, grid_div, swing = r.GetSetProjectGrid(0, 0)
  if grid_div ~= grid_div then grid_div = 1 end
  if swing == 3 then return 'Measure' end
  if grid_div >= 1 then return string.format('%d bar', math.floor(grid_div+0.5)) end
  local denom = math.floor(1/grid_div + 0.5)
  return '1/' .. denom
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
  local _, grid_div, swing = r.GetSetProjectGrid(0, 0)
  local is_frame   = r.GetToggleCommandState(40904) == 1
  local is_measure = (swing == 3)

  local grids = {
    {'Frame',    nil}, {'Measure', nil}, {''},
    {'1/128', 1/128}, {'1/64', 1/64}, {'1/32T', 1/(32*1.5)}, {'1/32', 1/32},
    {'1/16T', 1/(16*1.5)}, {'1/16', 1/16}, {'1/8T', 1/(8*1.5)}, {'1/8', 1/8},
    {'1/4T',  1/(4*1.5)},  {'1/4',  1/4},  {'1/2',  1/2},
    {'1',  1}, {'2', 2}, {'4', 4},
  }

  local items = {}
  for _, g in ipairs(grids) do
    if g[1] == '' then
      items[#items+1] = ''  -- separator
    else
      local checked = false
      if g[1] == 'Frame'   then checked = is_frame
      elseif g[1] == 'Measure' then checked = is_measure and not is_frame
      elseif g[2] then
        checked = not is_frame and not is_measure and math.abs(grid_div - g[2]) < 1e-8
      end
      items[#items+1] = (checked and '!' or '') .. g[1]
    end
  end

  local ret = popup_menu(items)
  if ret == 0 then return end

  -- Find the actual grid entry (skip separators)
  local count = 0
  for _, g in ipairs(grids) do
    if g[1] ~= '' then
      count = count + 1
      if count == ret then
        if g[1] == 'Frame' then
          r.Main_OnCommand(40904, 0)  -- toggle frame grid
        elseif g[1] == 'Measure' then
          if is_frame then r.Main_OnCommand(40904, 0) end
          r.GetSetProjectGrid(0, 1, grid_div, 3)
        else
          if is_frame then r.Main_OnCommand(40904, 0) end
          if is_measure then r.GetSetProjectGrid(0, 1, g[2], 0)
          else r.GetSetProjectGrid(0, 1, g[2]) end
        end
        break
      end
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
    local items = {'Size: Small (160x28)', 'Size: Medium (220x36)', 'Size: Large (280x46)', 'Size: Custom...'}
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