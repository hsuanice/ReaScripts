-- @description hsuanice_Pro Tools Decrease Nudge Value
-- @version 0.1.0 [260418.1534]
-- @author hsuanice
-- @about
--   Decreases nudge value to next preset in current mode. Stops at list boundary.
--   Reads/writes state shared with hsuanice_Grid Nudge Panel.
--   Mac shortcut (PT): Option + Shift + -
-- @changelog
--   0.1.0 [260418.1534] - Initial release

local r = reaper
local info = debug.getinfo(1,'S')
local dir  = info.source:match('^@(.+)[\/]') or ''
local Nudge = dofile(dir .. '/hsuanice_PT_Nudge.lua')

local mode, idx = Nudge.decrease()
local preset = Nudge.get_preset(mode, idx)
if not preset then r.defer(function() end); return end

-- Show floating tooltip via GFX
local label = preset.label
local mx, my = r.GetMousePosition()

local TOOLTIP_DURATION = 2.0
local start_time = r.time_precise()

gfx.init('hsuanice_NudgeTooltip', 1, 1, 0, mx + 20, my - 40)
local tooltip_hwnd = r.JS_Window_Find('hsuanice_NudgeTooltip', true)
if tooltip_hwnd then
  r.JS_Window_SetOpacity(tooltip_hwnd, 'ALPHA', 0)
end

-- Measure text for sizing
gfx.setfont(1, 'Arial', 13)
local tw, th = gfx.measurestr(label)
local W = tw + 20
local H = th + 10

gfx.quit()
gfx.init('hsuanice_NudgeTooltip', W, H, 0, mx + 20, my - H - 10)
tooltip_hwnd = r.JS_Window_Find('hsuanice_NudgeTooltip', true)

local function draw_tooltip()
  gfx.clear = 0x242424
  gfx.set(0.15, 0.15, 0.15)
  gfx.rect(0, 0, W, H, 1)
  gfx.set(0.27, 0.27, 0.27)
  gfx.rect(0, 0, W, H, 0)
  gfx.setfont(1, 'Arial', 13)
  gfx.set(0.8, 0.8, 0.8)
  gfx.x = 10; gfx.y = 5
  gfx.drawstr(label)
  gfx.update()
end

local function tooltip_loop()
  local elapsed = r.time_precise() - start_time
  if elapsed > TOOLTIP_DURATION then
    gfx.quit()
    return
  end
  if gfx.getchar() == -1 then return end
  draw_tooltip()
  r.defer(tooltip_loop)
end

draw_tooltip()
r.defer(tooltip_loop)
