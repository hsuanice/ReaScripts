--[[
@description ReaImGui - Show Project Frame Rate (XR-style font & theme)
@version 0.2.0
@author hsuanice
@about
  Minimal HUD that displays current project frame rate, styled like X-Raym ReaImGui scripts:
  - ReaImGui version lock, dark theme, 16pt sans-serif font
  - No title bar, auto-resize, compact and easy to read
  - Drag window from title bar only (avoid誤拖), right-click inside window to close
@changelog
  v0.2.0
  - Switch to XR-style stack: ReaImGui version lock (0.9.3.2), dark theme table, 16pt font, docking config
  - Keep HUD behavior: auto-resize, right-click to close
  v0.1.0
  - Initial minimal HUD (no custom font/theme)
]]

---------------------------------------
-- User Config
---------------------------------------
local reaimgui_force_version = "0.9.3.2"  -- match XR scripts style
local FONT_SIZE = 16                      -- 16pt like XR scripts for comfy reading
local WINDOW_TITLE = "Project Frame Rate"

-- Dark theme palette similar to XR scripts
local theme_colors = {
  WindowBg          = 0x292929ff,
  Border            = 0x2a2a2aff,
  Button            = 0x454545ff,
  ButtonActive      = 0x404040ff,
  ButtonHovered     = 0x606060ff,
  FrameBg           = 0x454545ff,
  FrameBgHovered    = 0x606060ff,
  FrameBgActive     = 0x404040ff,
  TitleBg           = 0x292929ff,
  TitleBgActive     = 0x000000ff,
  Header            = 0x323232ff,
  HeaderHovered     = 0x323232ff,
  HeaderActive      = 0x05050587,
  ResizeGrip        = 0x323232ff,
  ResizeGripHovered = 0x323232ff,
  ResizeGripActive  = 0x05050587,
  TextSelectedBg    = 0x404040ff,
  SeparatorHovered  = 0x606060ff,
  SeparatorActive   = 0x404040ff,
}

---------------------------------------
-- Load ReaImGui shim (XR-style)
---------------------------------------
local imgui_path = reaper.ImGui_GetBuiltinPath and (reaper.ImGui_GetBuiltinPath() .. '/imgui.lua')
if not imgui_path then
  reaper.MB("Missing dependency: ReaImGui extension.\nInstall via ReaPack (ReaTeam Extensions).", "Error", 0)
  return
end
local ImGui = dofile(imgui_path)(reaimgui_force_version)  -- XR: lock version

---------------------------------------
-- Context, Fonts, Flags
---------------------------------------
local ctx = ImGui.CreateContext(WINDOW_TITLE,
  ImGui.ConfigFlags_DockingEnable | ImGui.ConfigFlags_NavEnableKeyboard)

-- XR-style window behaviors
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_DockingNoSplit, 1)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)

-- Fonts (16pt sans-serif + optional bold if你想之後加)
local font = ImGui.CreateFont('sans-serif', FONT_SIZE)
ImGui.Attach(ctx, font)

-- Compact HUD flags
local window_flags =
  ImGui.WindowFlags_NoTitleBar |
  ImGui.WindowFlags_NoCollapse |
  ImGui.WindowFlags_NoResize |
  ImGui.WindowFlags_AlwaysAutoResize

---------------------------------------
-- Helpers
---------------------------------------
local function push_theme()
  local pushed = 0
  for k, color in pairs(theme_colors) do
    -- 這裡不要加 ()，因為 ImGui["Col_*"] 是常數
    local col_enum = ImGui["Col_" .. k]
    if col_enum then
      ImGui.PushStyleColor(ctx, col_enum, color)
      pushed = pushed + 1
    end
  end
  return pushed
end
---------------------------------------
-- Main Loop
---------------------------------------
local open = true

local function loop()
  -- Set a comfy initial size once
  ImGui.SetNextWindowSize(ctx, 220, 40, ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowBgAlpha(ctx, 1.0)

  local pushed = push_theme()
  local visible
  visible, open = ImGui.Begin(ctx, WINDOW_TITLE, open, window_flags)

  if visible then
    ImGui.PushFont(ctx, font)

    local fps = reaper.TimeMap_curFrameRate(0) -- current project FPS
    ImGui.Text(ctx, string.format("Frame Rate: %.3f fps", fps))

    -- Right-click inside window to close
    if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then
      open = false
    end

    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end

  if pushed > 0 then ImGui.PopStyleColor(ctx, pushed) end

  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
