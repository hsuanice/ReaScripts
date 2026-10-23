--[[
@description Fade Tool - Settings (crossfade and scene cut fade lengths, positions and shapes)
@version 26.1023.1942pre1
@author hsuanice
@noindex
@changelog
  - Change: shape menu lists all eight REAPER fade shapes (Linear and Equal Power first).
@about
  The only Fade Tool script that opens a window (native gfx: steppers, radio buttons, shape
  menu, checkbox; Enter = Save, Esc = Cancel). The other Fade Tool scripts just read these
  values and run.

  - Lengths are in frames (project frame rate), decimals allowed.
  - Position: before / center / after the cut or the scene edge.
  - Shape: Linear, Equal Power, Slight / Sharp Convex, Slight / Sharp Concave, Slight / Sharp S-Curve.
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Fade Tool Core.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

local r = reaper
local FT = dofile(r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Fade Tool Core.lua")
local TITLE = "Fade Tool - Settings"

local vals = FT.load_settings()

-- Layout rows: { kind, key, label }
local ROWS = {
  { "head",  nil,                "Crossfade" },
  { "len",   "xfade_frames",     "Length (frames)" },
  { "align", "xfade_align",      "Position" },
  { "shape", "xfade_shape",      "Shape" },
  { "head",  nil,                "Scene Cut" },
  { "len",   "scene_in_frames",  "Fade-in length (frames)" },
  { "align", "scene_in_align",   "Fade-in position" },
  { "len",   "scene_out_frames", "Fade-out length (frames)" },
  { "align", "scene_out_align",  "Fade-out position" },
  { "shape", "scene_shape",      "Fade shape" },
  { "head",  nil,                "After run" },
  { "check", "clear_razor",      "Clear razor after run" },
}
local ALIGN_HINT = {
  before = "before: the fade ends at the cut / scene edge",
  center = "center: the fade is centered on the cut / scene edge",
  after  = "after: the fade starts at the cut / scene edge",
}
local HEAD_H, ROW_H, CTRL_X = 26, 28, 200
local W = 500
local H = 16 + 62
for _, row in ipairs(ROWS) do H = H + ((row[1] == "head") and HEAD_H or ROW_H) end

gfx.ext_retina = 1
gfx.init(TITLE, W, H)
local sc = (gfx.ext_retina and gfx.ext_retina > 0) and gfx.ext_retina or 1
local function P(v) return math.floor(v * sc + 0.5) end

local prev_cap, mx, my, clicked = 0, 0, 0, false
local hint = ""

local function color(c) gfx.set(c, c, c, 1) end
local function accent() gfx.set(0.30, 0.58, 0.92, 1) end
local function over(x, y, w, h)
  return mx >= P(x) and mx < P(x + w) and my >= P(y) and my < P(y + h)
end
local function text(s, x, y, h)
  local _, th = gfx.measurestr(s)
  gfx.x, gfx.y = P(x), P(y) + math.floor((P(h) - th) / 2)
  gfx.drawstr(s)
end
local function box(x, y, w, h, fill, hover)
  color(hover and 0.36 or fill)
  gfx.rect(P(x), P(y), P(w), P(h), 1)
  color(0.45)
  gfx.rect(P(x), P(y), P(w), P(h), 0)
end

local function draw_len(key, y)
  local v = vals[key]
  local function btn(x, label)
    local h = over(x, y + 3, 22, 22)
    box(x, y + 3, 22, 22, 0.28, h)
    color(0.9); text(label, x + 7, y + 3, 22)
    return h and clicked
  end
  if btn(CTRL_X, "-") and v - 1 >= 1 then vals[key] = v - 1 end
  local vx, vw = CTRL_X + 28, 60
  local hv = over(vx, y + 3, vw, 22)
  box(vx, y + 3, vw, 22, 0.16, hv)
  color(0.95); text(string.format("%g", vals[key]), vx + 8, y + 3, 22)
  if btn(vx + vw + 6, "+") then vals[key] = vals[key] + 1 end
  if hv then hint = "Click the number to type a value (decimals allowed)" end
  if hv and clicked then
    local ok, s = r.GetUserInputs(TITLE, 1, "Length (frames)", string.format("%g", vals[key]))
    local n = ok and tonumber(s)
    if n and n > 0 then vals[key] = n end
  end
end

local function draw_align(key, y)
  local x = CTRL_X
  for _, a in ipairs(FT.ALIGNS) do
    local w = gfx.measurestr(a) / sc + 26
    local h = over(x, y, w, ROW_H)
    local cx, cy = P(x + 8), P(y + ROW_H / 2)
    color(h and 0.75 or 0.6); gfx.circle(cx, cy, P(6), 0, 1)
    if vals[key] == a then accent(); gfx.circle(cx, cy, P(3.5), 1, 1) end
    color(0.9); text(a, x + 20, y, ROW_H)
    if h then hint = ALIGN_HINT[a] end
    if h and clicked then vals[key] = a end
    x = x + w + 14
  end
end

local function draw_shape(key, y)
  local w = 170
  local h = over(CTRL_X, y + 3, w, 22)
  box(CTRL_X, y + 3, w, 22, 0.16, h)
  color(0.95); text(FT.SHAPE_NAMES[vals[key]] or "?", CTRL_X + 8, y + 3, 22)
  text("v", CTRL_X + w - 16, y + 3, 22)
  if h and clicked then
    local items = {}
    for _, i in ipairs(FT.SHAPE_ORDER) do items[#items + 1] = ((vals[key] == i) and "!" or "") .. FT.SHAPE_NAMES[i] end
    gfx.x, gfx.y = P(CTRL_X), P(y + 25)
    local pick = gfx.showmenu(table.concat(items, "|"))
    if pick > 0 then vals[key] = FT.SHAPE_ORDER[pick] end
  end
end

local function draw_check(key, label, y)
  local w = gfx.measurestr(label) / sc + 32
  local h = over(16, y, w, ROW_H)
  box(18, y + 7, 14, 14, 0.16, h)
  if vals[key] == 1 then accent(); gfx.rect(P(21), P(y + 10), P(8), P(8), 1) end
  color(0.9); text(label, 40, y, ROW_H)
  if h and clicked then vals[key] = (vals[key] == 1) and 0 or 1 end
end

local function button(label, x, y, w)
  local h = over(x, y, w, 26)
  box(x, y, w, 26, 0.28, h)
  color(0.95)
  text(label, x + (w - gfx.measurestr(label) / sc) / 2, y, 26)
  return h and clicked
end

local function loop()
  local cap = gfx.mouse_cap
  mx, my = gfx.mouse_x, gfx.mouse_y
  clicked = (cap & 1 == 1) and (prev_cap & 1 == 0)
  prev_cap = cap
  hint = ""

  gfx.setfont(1, "Arial", P(14))
  color(0.2); gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local y = 8
  for _, row in ipairs(ROWS) do
    local kind, key, label = row[1], row[2], row[3]
    if kind == "head" then
      gfx.setfont(2, "Arial", P(14), string.byte("b"))
      accent(); text(label, 12, y, HEAD_H)
      gfx.setfont(1)
      y = y + HEAD_H
    else
      if kind == "check" then
        draw_check(key, label, y)
      else
        color(0.85); text(label, 24, y, ROW_H)
        if kind == "len" then draw_len(key, y)
        elseif kind == "align" then draw_align(key, y)
        elseif kind == "shape" then draw_shape(key, y) end
      end
      y = y + ROW_H
    end
  end

  color(0.6); text(hint, 16, y + 2, 20)
  local by = y + 28
  local save = button("Save", W - 196, by, 86)
  local cancel = button("Cancel", W - 100, by, 86)

  local ch = gfx.getchar()
  if save or ch == 13 then FT.save_settings(vals); gfx.quit(); return end
  if cancel or ch == 27 or ch < 0 then gfx.quit(); return end
  gfx.update()
  r.defer(loop)
end

loop()
