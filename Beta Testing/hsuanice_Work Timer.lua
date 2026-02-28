-- hsuanice_Work Timer.lua
-- Real-time 24H system clock. Right-click to change color/font.
-- Window is resizable; clock auto-scales to fill it.
-- Settings and window geometry are remembered across sessions.
--
-- Version: 260228.1858
--
-- Changelog:
--   v260228.1858
--     - Hover info: shows "⌘+click → set edit cursor" hint when mouse is over window
--     - ⌘+click (Ctrl+click on Windows): moves REAPER edit cursor to the clicked TC position
--   v260228.1800
--     - Custom color: right-click "Color: Custom > Edit..." to enter HEX
--     - Custom hex persists across sessions (custom_hex ExtState key)
--   v260228.1730
--     - Dock support: right-click "Dock window" to dock/undock
--     - Dock state persists across sessions (gfx.init dockstate arg)
--   v260228.1600
--     - Remember window position across sessions (gfx.dock)
--     - Fix right-click menu index offset (flat list, no #-headers)
--     - Color and font persist via reaper.GetExtState / SetExtState
--   v260228.1200
--     - Right-click menu: 5 color presets + 4 font presets
--     - Clock auto-scales to window size (width + height limit)
--     - Date row scales proportionally, vertically centred
--   v260228
--     - Initial release
--     - 24H TC clock with project frame rate (TimeMap_curFrameRate)
--     - gfx-based, no dependencies

-- ── Presets ────────────────────────────────────────────────────────────────
local COLORS = {
  { name="Green",  r=0.20, g=0.88, b=0.38 },
  { name="Amber",  r=0.95, g=0.75, b=0.15 },
  { name="White",  r=0.90, g=0.90, b=0.90 },
  { name="Cyan",   r=0.15, g=0.88, b=0.95 },
  { name="Red",    r=0.92, g=0.22, b=0.18 },
  { name="Custom", r=0.50, g=0.50, b=0.50 },  -- slot 6, updated from saved hex at startup
}
local FONTS = {
  { name="Courier New", face="Courier New" },
  { name="Monaco",      face="Monaco"      },
  { name="Arial",       face="Arial"       },
  { name="Helvetica",   face="Helvetica"   },
}

-- ── Hex helpers ────────────────────────────────────────────────────────────
local function hex_to_rgb(hex)
  hex = hex:gsub("^#", ""):upper()
  if #hex ~= 6 then return nil end
  local r = tonumber(hex:sub(1,2), 16)
  local g = tonumber(hex:sub(3,4), 16)
  local b = tonumber(hex:sub(5,6), 16)
  if not (r and g and b) then return nil end
  return r/255, g/255, b/255
end

local function rgb_to_hex(r, g, b)
  return string.format("%02X%02X%02X",
    math.floor(r * 255 + 0.5),
    math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5))
end

-- ── Persistence ────────────────────────────────────────────────────────────
local EXT = "hsuanice_WorkTimer"

local function load_settings()
  local function gi(key, default)
    local v = reaper.GetExtState(EXT, key)
    return (v ~= "" and tonumber(v)) or default
  end
  return {
    color      = gi("color", 1),
    font       = gi("font",  1),
    win_w      = gi("win_w", 360),
    win_h      = gi("win_h", 110),
    win_x      = gi("win_x", 100),
    win_y      = gi("win_y", 100),
    dock       = gi("dock",  0),
    custom_hex = reaper.GetExtState(EXT, "custom_hex"),
  }
end

local function save_settings(color, font, w, h, x, y, dock)
  reaper.SetExtState(EXT, "color", tostring(color), true)
  reaper.SetExtState(EXT, "font",  tostring(font),  true)
  reaper.SetExtState(EXT, "win_w", tostring(w),     true)
  reaper.SetExtState(EXT, "win_h", tostring(h),     true)
  reaper.SetExtState(EXT, "win_x", tostring(x),     true)
  reaper.SetExtState(EXT, "win_y", tostring(y),     true)
  reaper.SetExtState(EXT, "dock",  tostring(dock),  true)
  -- Always write current custom color
  reaper.SetExtState(EXT, "custom_hex",
    rgb_to_hex(COLORS[6].r, COLORS[6].g, COLORS[6].b), true)
end

-- ── State ──────────────────────────────────────────────────────────────────
local cfg       = load_settings()
local cur_color = cfg.color
local cur_font  = cfg.font
local last_w    = cfg.win_w
local last_h    = cfg.win_h
local last_x    = cfg.win_x
local last_y    = cfg.win_y
local last_dock = cfg.dock
local rmb_prev      = false
local lmb_ctrl_prev = false

-- Apply saved custom hex to COLORS[6] at startup
do
  local hex = cfg.custom_hex
  if hex and hex ~= "" then
    local r, g, b = hex_to_rgb(hex)
    if r then
      COLORS[6].r, COLORS[6].g, COLORS[6].b = r, g, b
    end
  end
end

-- ── Clock strings ──────────────────────────────────────────────────────────
local function clock_str()
  local t   = os.date("*t")
  local fps = reaper.TimeMap_curFrameRate(0)
  local f   = math.floor(reaper.time_precise() % 1 * fps)
  return string.format("%02d:%02d:%02d:%02d", t.hour, t.min, t.sec, f)
end

local function date_str()
  return os.date("%A  %Y-%m-%d")
end

-- Convert current system time (as TC) to seconds for SetEditCurPos
local function tc_to_seconds()
  local t   = os.date("*t")
  local fps = reaper.TimeMap_curFrameRate(0)
  local f   = math.floor(reaper.time_precise() % 1 * fps)
  return t.hour * 3600 + t.min * 60 + t.sec + f / fps
end

-- ── Font-size calculation ──────────────────────────────────────────────────
local function calc_clock_sz(face)
  local TRIAL = 50
  gfx.setfont(1, face, TRIAL, string.byte("b"))
  local tw = gfx.measurestr("00:00:00:00")
  if tw == 0 then return TRIAL end
  local by_w = math.floor(TRIAL * (gfx.w * 0.88) / tw)
  local by_h = math.floor(gfx.h * 0.62)
  return math.max(12, math.min(by_w, by_h))
end

-- ── Right-click menu ───────────────────────────────────────────────────────
-- Flat list, unambiguous indices:
--   1 .. #COLORS          → color choice
--   #COLORS+1 .. +#FONTS  → font choice
--   #COLORS+#FONTS+1      → dock toggle
--   #COLORS+#FONTS+2      → edit custom color
local function show_rmenu()
  local parts = {}
  for i, c in ipairs(COLORS) do
    parts[#parts+1] = (i == cur_color and "!" or "") .. "Color: " .. c.name
  end
  for i, f in ipairs(FONTS) do
    parts[#parts+1] = (i == cur_font and "!" or "") .. "Font: "  .. f.name
  end
  local dockstate = gfx.dock(-1)
  parts[#parts+1] = (dockstate ~= 0 and "!" or "") .. "Dock window"
  parts[#parts+1] = "Edit custom color..."

  local sel = gfx.showmenu(table.concat(parts, "|"))
  if sel <= 0 then return end

  local nc, nf = #COLORS, #FONTS
  if sel <= nc then
    cur_color = sel
  elseif sel <= nc + nf then
    cur_font = sel - nc
  elseif sel == nc + nf + 1 then
    -- Toggle dock
    local new_dock = (dockstate ~= 0) and 0 or 1
    gfx.dock(new_dock)
    last_dock = new_dock
  else
    -- Edit custom color via hex input
    local current_hex = rgb_to_hex(COLORS[6].r, COLORS[6].g, COLORS[6].b)
    local ok, result = reaper.GetUserInputs(
      "Custom Color", 1,
      "Enter hex color (e.g. FF8C00):",
      current_hex)
    if ok and result ~= "" then
      local r, g, b = hex_to_rgb(result)
      if r then
        COLORS[6].r, COLORS[6].g, COLORS[6].b = r, g, b
        cur_color = 6  -- switch to Custom slot
      else
        reaper.MB("Invalid hex color. Use 6 hex digits (e.g. FF8C00 or #FF8C00).", "Invalid Input", 0)
      end
    end
  end

  local _, wx, wy = gfx.dock(-1, 0, 0, 0, 0)
  save_settings(cur_color, cur_font, gfx.w, gfx.h, wx, wy, last_dock)
end

-- ── Main draw loop ─────────────────────────────────────────────────────────
local function frame()
  -- Background
  gfx.r=0.07; gfx.g=0.07; gfx.b=0.09; gfx.a=1
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local face     = FONTS[cur_font].face
  local clock_sz = calc_clock_sz(face)
  local date_sz  = math.max(10, math.floor(clock_sz / 4))

  -- Measure both strings for vertical centering
  local tc = clock_str()
  local ds = date_str()

  gfx.setfont(1, face, clock_sz, string.byte("b"))
  local tw, th = gfx.measurestr(tc)

  gfx.setfont(2, "Arial", date_sz)
  local dw, dh = gfx.measurestr(ds)

  local gap     = math.max(2, math.floor(gfx.h * 0.04))
  local start_y = math.floor((gfx.h - th - gap - dh) / 2)

  -- Draw clock
  local c = COLORS[cur_color]
  gfx.setfont(1)
  gfx.r=c.r; gfx.g=c.g; gfx.b=c.b; gfx.a=1
  gfx.x = math.floor((gfx.w - tw) / 2)
  gfx.y = start_y
  gfx.drawstr(tc)

  -- Draw date (same hue, dimmed)
  gfx.setfont(2)
  gfx.r=c.r*0.48; gfx.g=c.g*0.48; gfx.b=c.b*0.48; gfx.a=1
  gfx.x = math.floor((gfx.w - dw) / 2)
  gfx.y = start_y + th + gap
  gfx.drawstr(ds)

  -- Hover hint: visible when mouse is over the window
  local in_win = gfx.mouse_x >= 0 and gfx.mouse_x <= gfx.w
              and gfx.mouse_y >= 0 and gfx.mouse_y <= gfx.h
  if in_win then
    local hint    = "⌘+click → set edit cursor"
    local hint_sz = math.max(9, math.floor(clock_sz / 6))
    gfx.setfont(3, "Arial", hint_sz)
    local hw, hh  = gfx.measurestr(hint)
    local pad     = math.max(3, math.floor(gfx.h * 0.03))
    gfx.r=c.r*0.35; gfx.g=c.g*0.35; gfx.b=c.b*0.35; gfx.a=1
    gfx.x = math.floor((gfx.w - hw) / 2)
    gfx.y = gfx.h - hh - pad
    gfx.drawstr(hint)
  end

  -- Save window geometry / dock state when anything changes
  local dockstate, wx, wy = gfx.dock(-1, 0, 0, 0, 0)
  if gfx.w ~= last_w or gfx.h ~= last_h or wx ~= last_x or wy ~= last_y
      or dockstate ~= last_dock then
    last_w, last_h, last_x, last_y, last_dock = gfx.w, gfx.h, wx, wy, dockstate
    save_settings(cur_color, cur_font, gfx.w, gfx.h, wx, wy, dockstate)
  end

  -- Right-click detection (rising edge)
  local rmb = (gfx.mouse_cap & 2) ~= 0
  if rmb and not rmb_prev then show_rmenu() end
  rmb_prev = rmb

  -- Ctrl+left-click: move REAPER edit cursor to current TC position
  local lmb_ctrl = (gfx.mouse_cap & 5) == 5
  if lmb_ctrl and not lmb_ctrl_prev then
    reaper.SetEditCurPos(tc_to_seconds(), true, false)
  end
  lmb_ctrl_prev = lmb_ctrl

  gfx.update()

  if gfx.getchar() >= 0 then
    reaper.defer(frame)
  else
    -- Window closed — save final geometry (reuse locals from above)
    save_settings(cur_color, cur_font, gfx.w, gfx.h, wx, wy, dockstate)
  end
end

-- ── Init ───────────────────────────────────────────────────────────────────
gfx.init("Work Timer", cfg.win_w, cfg.win_h, cfg.dock, cfg.win_x, cfg.win_y)
frame()
