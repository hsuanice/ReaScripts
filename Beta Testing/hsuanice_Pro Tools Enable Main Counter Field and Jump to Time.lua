--[[
@description Pro Tools Enable Main Counter Field and Jump to Time
@author hsuanice
@version 1.0.0
@provides
  [main] .
@about
  # Pro Tools-Style Counter Field and Jump to Time

  Mimics Pro Tools' Main Counter Field behavior with cycling numeric input.

  ## Features
  - Auto-detects project time format (Timecode/Time/Samples/Beat)
  - Cycling input: when digits exceed max length, automatically wraps to first position
  - Auto-formats as you type (e.g., 00595800 → 00:59:58:00)
  - No need to type separators (: or .)
  - Supports multiple time formats based on project settings

  ## Supported Formats
  - Timecode (HH:MM:SS:FF) - 8 digits
  - Time (HH:MM:SS.mmm) - 9 digits
  - Samples - variable length
  - Beat (BBB.BB.hundredths) - 7 digits

  ## Usage
  1. Run script to open the Counter window
  2. Type numbers continuously (no separators needed)
  3. Press Enter to navigate
  4. Press + for relative forward offset (e.g., +01000000 = +1 hour from current)
  5. Press - for relative backward offset (e.g., -00300000 = -30 minutes from current)
  6. Press Delete to reset to current timeline position
  7. Press Escape or Backspace to clear input

@changelog
  [Internal Build 251220.1230]
    + IMPROVED: Adjusted window size to 320x105 (compact but clear)
    + IMPROVED: Increased main font to 28pt for better visibility on macOS
    + IMPROVED: Cycling input now replaces digit-by-digit (true Pro Tools behavior)
    + IMPROVED: Blinking cursor shows exact input position
    + IMPROVED: +/- prefix displayed with space before timecode for clarity
  [Internal Build 251220.0200]
    + Rewritten using native gfx library (removed ReaImGui dependency)
    + Minimal, compact interface (Pro Tools style)
    + All core features preserved: cycling input, relative mode, auto-format
  [Internal Build 251220.0100]
    + Initial release with ReaImGui
--]]

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local r = reaper

-- Key codes for gfx
local KEY_BACKSPACE = 8
local KEY_ENTER = 13
local KEY_ESC = 27
local KEY_DELETE = 6579564
local KEY_MINUS = 45
local KEY_PLUS = 43

-- ============================================================================
-- GLOBAL STATE
-- ============================================================================

local state = {
  input_buffer = "",
  max_digits = 8,
  frame_rate = 30,
  sample_rate = 48000,
  is_relative = false,
  relative_sign = "",
  cursor_pos = 0, -- Track which digit position we're at (0-based)
}

-- GUI settings
local window_w = 320
local window_h = 105
local font_name = "Arial"
local font_size = 28  -- Larger for better visibility on macOS
local font_size_small = 11

-- ============================================================================
-- TIME FORMAT UTILITIES
-- ============================================================================

function update_project_settings()
  state.frame_rate = r.TimeMap_curFrameRate(0) or 30
  if state.frame_rate == 0 then state.frame_rate = 30 end

  state.sample_rate = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if state.sample_rate == 0 then state.sample_rate = 48000 end
end

function get_format_info()
  local format_name = "Timecode"
  local format_pattern = "HH:MM:SS:FF"
  local max_digits = 8

  -- Detect current time mode from toggle states
  if r.GetToggleCommandState(40365) == 1 then -- Time
    format_name = "Time"
    format_pattern = "HH:MM:SS.mmm"
    max_digits = 9
  elseif r.GetToggleCommandState(41973) == 1 then -- SMPTE
    format_name = "Timecode"
    format_pattern = "HH:MM:SS:FF"
    max_digits = 8
  elseif r.GetToggleCommandState(40368) == 1 then -- Samples
    format_name = "Samples"
    format_pattern = "samples"
    max_digits = 12
  elseif r.GetToggleCommandState(40364) == 1 then -- Measures
    format_name = "Beat"
    format_pattern = "BBB.BB.hh"
    max_digits = 7
  end

  state.max_digits = max_digits
  return format_name, format_pattern
end

function format_display()
  local input = state.input_buffer
  local len = #input

  if len == 0 then
    return "", 0 -- Return empty string and cursor position
  end

  local format_name, _ = get_format_info()
  local padded = input .. string.rep("0", state.max_digits - len)
  padded = padded:sub(1, state.max_digits)

  local formatted = ""
  local cursor_display_pos = 0 -- Position in formatted string where cursor should appear

  -- Use actual cursor position for display (for cycling mode)
  local display_cursor = len < state.max_digits and len or state.cursor_pos

  if format_name == "Timecode" then
    local hh = padded:sub(1, 2)
    local mm = padded:sub(3, 4)
    local ss = padded:sub(5, 6)
    local ff = padded:sub(7, 8)
    formatted = string.format("%s:%s:%s:%s", hh, mm, ss, ff)

    -- Calculate cursor position (account for colons)
    if display_cursor <= 2 then cursor_display_pos = display_cursor
    elseif display_cursor <= 4 then cursor_display_pos = display_cursor + 1 -- After first ":"
    elseif display_cursor <= 6 then cursor_display_pos = display_cursor + 2 -- After second ":"
    else cursor_display_pos = display_cursor + 3 end -- After third ":"

  elseif format_name == "Time" then
    local hh = padded:sub(1, 2)
    local mm = padded:sub(3, 4)
    local ss = padded:sub(5, 6)
    local mmm = padded:sub(7, 9)
    formatted = string.format("%s:%s:%s.%s", hh, mm, ss, mmm)

    -- Calculate cursor position (account for colons and dot)
    if display_cursor <= 2 then cursor_display_pos = display_cursor
    elseif display_cursor <= 4 then cursor_display_pos = display_cursor + 1
    elseif display_cursor <= 6 then cursor_display_pos = display_cursor + 2
    else cursor_display_pos = display_cursor + 3 end

  elseif format_name == "Samples" then
    formatted = input
    cursor_display_pos = display_cursor

  elseif format_name == "Beat" then
    local bbb = padded:sub(1, 3)
    local bb = padded:sub(4, 5)
    local hh = padded:sub(6, 7)
    formatted = string.format("%s.%s.%s", bbb, bb, hh)

    -- Calculate cursor position (account for dots)
    if display_cursor <= 3 then cursor_display_pos = display_cursor
    elseif display_cursor <= 5 then cursor_display_pos = display_cursor + 1
    else cursor_display_pos = display_cursor + 2 end

  else
    formatted = input
    cursor_display_pos = display_cursor
  end

  if state.is_relative then
    formatted = state.relative_sign .. " " .. formatted
    cursor_display_pos = cursor_display_pos + 2 -- Account for "+ " or "- "
  end

  return formatted, cursor_display_pos
end

function input_to_position()
  local input = state.input_buffer
  local format_name = get_format_info()

  if #input == 0 then
    return nil
  end

  local padded = input .. string.rep("0", state.max_digits - #input)
  padded = padded:sub(1, state.max_digits)
  local offset_time = 0

  if format_name == "Timecode" then
    local hh = tonumber(padded:sub(1, 2)) or 0
    local mm = tonumber(padded:sub(3, 4)) or 0
    local ss = tonumber(padded:sub(5, 6)) or 0
    local ff = tonumber(padded:sub(7, 8)) or 0
    offset_time = hh * 3600 + mm * 60 + ss + (ff / state.frame_rate)
  elseif format_name == "Time" then
    local hh = tonumber(padded:sub(1, 2)) or 0
    local mm = tonumber(padded:sub(3, 4)) or 0
    local ss = tonumber(padded:sub(5, 6)) or 0
    local mmm = tonumber(padded:sub(7, 9)) or 0
    offset_time = hh * 3600 + mm * 60 + ss + (mmm / 1000)
  elseif format_name == "Samples" then
    local samples = tonumber(input) or 0
    offset_time = samples / state.sample_rate
  elseif format_name == "Beat" then
    local bbb = tonumber(padded:sub(1, 3)) or 1
    local bb = tonumber(padded:sub(4, 5)) or 1
    local hh = tonumber(padded:sub(6, 7)) or 0
    local measure_pos = (bbb - 1) + ((bb - 1) / 4) + (hh / 400)
    offset_time = r.TimeMap2_beatsToTime(0, measure_pos * 4)
  end

  if state.is_relative then
    local current_pos = r.GetCursorPosition()
    if state.relative_sign == "-" then
      return current_pos - offset_time
    else
      return current_pos + offset_time
    end
  end

  return offset_time
end

function position_to_input(pos_seconds)
  local format_name = get_format_info()

  if format_name == "Timecode" then
    local total_frames = math.floor(pos_seconds * state.frame_rate)
    local ff = total_frames % math.floor(state.frame_rate)
    local total_secs = math.floor(total_frames / state.frame_rate)
    local ss = total_secs % 60
    local total_mins = math.floor(total_secs / 60)
    local mm = total_mins % 60
    local hh = math.floor(total_mins / 60)
    state.input_buffer = string.format("%02d%02d%02d%02d", hh, mm, ss, ff)
  elseif format_name == "Time" then
    local hh = math.floor(pos_seconds / 3600)
    local mm = math.floor((pos_seconds % 3600) / 60)
    local ss = math.floor(pos_seconds % 60)
    local mmm = math.floor((pos_seconds % 1) * 1000)
    state.input_buffer = string.format("%02d%02d%02d%03d", hh, mm, ss, mmm)
  elseif format_name == "Samples" then
    local samples = math.floor(pos_seconds * state.sample_rate)
    state.input_buffer = tostring(samples)
  elseif format_name == "Beat" then
    local beats = r.TimeMap2_timeToBeats(0, pos_seconds)
    local measures = math.floor(beats / 4)
    local beat_fraction = (beats % 4)
    local beat_num = math.floor(beat_fraction) + 1
    local hundredths = math.floor((beat_fraction % 1) * 100)
    state.input_buffer = string.format("%03d%02d%02d", measures + 1, beat_num, hundredths)
  end
end

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================

function handle_numeric_input(digit)
  local len = #state.input_buffer

  if len < state.max_digits then
    -- Still have space, append
    state.input_buffer = state.input_buffer .. digit
    state.cursor_pos = #state.input_buffer
  else
    -- Buffer full, cycle: replace digit at cursor position
    -- Convert to character array for easier replacement
    local chars = {}
    for i = 1, #state.input_buffer do
      chars[i] = state.input_buffer:sub(i, i)
    end

    -- Replace character at cursor position
    chars[state.cursor_pos + 1] = digit

    -- Rebuild string
    state.input_buffer = table.concat(chars)

    -- Move cursor to next position (wrap around)
    state.cursor_pos = (state.cursor_pos + 1) % state.max_digits
  end
end

function handle_relative_input(sign)
  state.input_buffer = ""
  state.is_relative = true
  state.relative_sign = sign
  state.cursor_pos = 0
end

function clear_input()
  state.input_buffer = ""
  state.is_relative = false
  state.relative_sign = ""
  state.cursor_pos = 0
end

function reset_to_current()
  local current_pos = r.GetCursorPosition()
  clear_input()
  position_to_input(current_pos)
end

function jump_to_time()
  local pos = input_to_position()
  if pos then
    r.SetEditCurPos(pos, true, true)
    clear_input()
  end
end

-- ============================================================================
-- GUI RENDERING
-- ============================================================================

function draw_gui()
  update_project_settings()

  -- Background
  gfx.set(0.15, 0.15, 0.15, 1)
  gfx.rect(0, 0, window_w, window_h, 1)

  -- Header: Format info
  gfx.setfont(1, font_name, font_size_small)
  local format_name, format_pattern = get_format_info()
  local mode_text = ""
  if state.is_relative then
    mode_text = state.relative_sign == "+" and " [+]" or " [-]"
  end

  gfx.set(0.5, 0.5, 0.5, 1)
  gfx.x = 8
  gfx.y = 6
  gfx.drawstr(string.format("%s%s", format_name, mode_text))

  -- Main display: Large time code (28pt for better visibility)
  gfx.setfont(2, font_name, font_size)
  local display_text, cursor_pos = format_display()
  if #display_text == 0 then
    local _, pattern = get_format_info()
    display_text = pattern:gsub("[A-Z]", "0"):gsub("[a-z]", "0")
    cursor_pos = 0
  end

  -- Color based on mode
  if state.is_relative then
    if state.relative_sign == "+" then
      gfx.set(0.4, 0.7, 1.0, 1) -- Cyan
    else
      gfx.set(1.0, 0.5, 0.3, 1) -- Orange
    end
  else
    gfx.set(0.4, 1.0, 0.4, 1) -- Green
  end

  -- Center the text
  local text_w, text_h = gfx.measurestr(display_text)
  local text_x = (window_w - text_w) / 2
  gfx.x = text_x
  gfx.y = 33
  gfx.drawstr(display_text)

  -- Draw blinking cursor at current input position
  if #state.input_buffer > 0 then
    local blink_alpha = math.abs((os.clock() % 1) - 0.5) * 2 -- Blink effect
    gfx.set(1, 1, 1, blink_alpha)

    -- Get width of text up to cursor position
    local text_before_cursor = display_text:sub(1, cursor_pos)
    local cursor_x_offset = gfx.measurestr(text_before_cursor)

    gfx.x = text_x + cursor_x_offset
    gfx.y = 33
    gfx.drawstr("|")
  end

  -- Footer: Help text (compact)
  gfx.setfont(1, font_name, font_size_small)
  gfx.set(0.4, 0.4, 0.4, 1)
  local help_text = "+/- Rel • Del Reset • Esc Clear"
  local help_w = gfx.measurestr(help_text)
  gfx.x = (window_w - help_w) / 2
  gfx.y = window_h - 19
  gfx.drawstr(help_text)

  gfx.update()
end

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

function main()
  local char = gfx.getchar()

  -- Exit conditions
  if char == -1 or char == KEY_ESC then
    gfx.quit()
    return
  end

  -- Handle numeric input (0-9)
  if char >= 48 and char <= 57 then
    handle_numeric_input(string.char(char))
  end

  -- Handle special keys
  if char == KEY_BACKSPACE then
    clear_input()
  elseif char == KEY_DELETE then
    reset_to_current()
  elseif char == KEY_PLUS then
    handle_relative_input("+")
  elseif char == KEY_MINUS then
    handle_relative_input("-")
  elseif char == KEY_ENTER then
    jump_to_time()
    gfx.quit()
    return
  end

  draw_gui()
  r.defer(main)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function init_window()
  -- Center window on screen
  local _, _, screen_w, screen_h = r.my_getViewport(0, 0, 0, 0, 0, 0, 0, 0, 1)
  local x = (screen_w - window_w) / 2
  local y = (screen_h - window_h) / 2

  gfx.init("Pro Tools Counter Field", window_w, window_h, 0, x, y)
  gfx.clear = 0x262626 -- Dark background
end

-- Start
update_project_settings()
init_window()
main()
