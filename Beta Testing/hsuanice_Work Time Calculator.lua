-- hsuanice_Work Timer.lua
-- Real-time 24H system clock. Right-click to change color/font.
-- Window is resizable; clock auto-scales to fill it.
-- Settings and window geometry are remembered across sessions.
--
-- Version: 260228.1730
--
-- Changelog:
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
}
local FONTS = {
  { name="Courier New", face="Courier New" },
  { name="Monaco",      face="Monaco"      },
  { name="Arial",       face="Arial"       },
  { name="Helvetica",   face="Helvetica"   },
}

-- ── Persistence ────────────────────────────────────────────────────────────
local EXT = "hsuanice_WorkTimer"

local function load_settings()
  local function gi(key, default)
    local v = reaper.GetExtState(EXT, key)
    return (v ~= "" and tonumber(v)) or default
  end
  return {
    color = gi("color", 1),
    font  = gi("font",  1),
    win_w = gi("win_w", 360),
    win_h = gi("win_h", 110),
    win_x = gi("win_x", 100),
    win_y = gi("win_y", 100),
    dock  = gi("dock",  0),
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
local rmb_prev  = false

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
--   1 .. #COLORS        → color choice
--   #COLORS+1 .. +#FONTS → font choice
--   #COLORS+#FONTS+1    → dock toggle
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

  local sel = gfx.showmenu(table.concat(parts, "|"))
  if sel <= 0 then return end

  local nc, nf = #COLORS, #FONTS
  if sel <= nc then
    cur_color = sel
  elseif sel <= nc + nf then
    cur_font = sel - nc
  else
    -- Toggle dock
    local new_dock = (dockstate ~= 0) and 0 or 1
    gfx.dock(new_dock)
    last_dock = new_dock
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
