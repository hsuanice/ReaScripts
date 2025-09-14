--[[
@description ReaImGui - Show Project Frame Rate (XR-style font & shared theme, warn once if theme missing)
@version 0.2.2.1
@author hsuanice
@about
  Minimal HUD that displays current project frame rate, styled like X-Raym ReaImGui scripts:
  - ReaImGui version lock, 16pt sans-serif font
  - Shared theme via library: "hsuanice_ReaImGui Theme Color.lua"
  - No title bar, auto-resize, compact and easy to read
  - Warn once if theme library is missing, then continue with default colors
  - Right-click inside window to close
@changelog
  v0.2.2.1 (2025-09-14)
    - Fix: Added ensure_ctx() guard to handle project switching.
      When loading a new project, the old ImGui context/font may
      be invalidated; ensure_ctx() now recreates them before any
      ImGui calls. Prevents errors like
      "ImGui_SetNextWindowSize: expected a valid ImGui_Context*".
    - Internal: validate font pointer each frame and recreate if
      needed.
    - No functional/UI changes; only stability improvement.

  v0.2.2
  - Implement mode B: show a warning dialog once if the theme library is missing, but do not abort.
  v0.2.1
  - Use shared color library: hsuanice_ReaImGui Theme Color.lua (apply/pop per frame)
  - Remove local theme table and push_theme(); add safe fallback if library missing
  v0.2.0
  - XR-style stack: ReaImGui lock (0.9.3.2), dark theme table, 16pt font, docking config
  v0.1.0
  - Initial minimal HUD (no custom font/theme)
]]

---------------------------------------
-- User Config
---------------------------------------
local reaimgui_force_version = "0.9.3.2"  -- match XR scripts style
local FONT_SIZE = 16                      -- 16pt like XR scripts for comfy reading
local WINDOW_TITLE = "Project Frame Rate"

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
-- Load Shared Theme Library (WARN ONCE if missing)
---------------------------------------
-- NOTE: 檔名含空白，請確保路徑正確：
-- Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua
local THEME_PATH = (reaper.GetResourcePath() ..
  '/Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua')

local THEME = nil
do
  local ok, mod = pcall(dofile, THEME_PATH)
  if ok and type(mod)=="table" and mod.apply and mod.pop then
    THEME = mod
    -- 如需品牌橘色，取消註解：
    -- THEME.set_accent(0xFFC700ff)
  else
    reaper.MB("Theme library not found.\nUsing default ImGui colors.\n\n" .. THEME_PATH, "Warning", 0)
    THEME = nil
  end
end

---------------------------------------
-- Context, Fonts, Flags
---------------------------------------
local ctx = ImGui.CreateContext(WINDOW_TITLE,
  ImGui.ConfigFlags_DockingEnable | ImGui.ConfigFlags_NavEnableKeyboard)

-- XR-style window behaviors
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_DockingNoSplit, 1)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)

-- Fonts (16pt sans-serif; 可再加粗體字自行使用)
local font = ImGui.CreateFont('sans-serif', FONT_SIZE)
ImGui.Attach(ctx, font)

-- Compact HUD flags (注意：這些是常數，不能加 ())
local window_flags =
  ImGui.WindowFlags_NoTitleBar |
  ImGui.WindowFlags_NoCollapse |
  ImGui.WindowFlags_NoResize |
  ImGui.WindowFlags_AlwaysAutoResize


-- Guard: re-create context/font when project switching invalidates ctx
local function ensure_ctx()
  if not reaper.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
    -- recreate context
    ctx = ImGui.CreateContext(WINDOW_TITLE,
      ImGui.ConfigFlags_DockingEnable | ImGui.ConfigFlags_NavEnableKeyboard)
    ImGui.SetConfigVar(ctx, ImGui.ConfigVar_DockingNoSplit, 1)
    ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)

    -- recreate font
    font = ImGui.CreateFont('sans-serif', FONT_SIZE)
    ImGui.Attach(ctx, font)
  elseif not reaper.ImGui_ValidatePtr(font, 'ImGui_Font*') then
    font = ImGui.CreateFont('sans-serif', FONT_SIZE)
    ImGui.Attach(ctx, font)
  end
end

---------------------------------------
-- Main Loop
---------------------------------------
local open = true

local function loop()
  ensure_ctx()  -- <== 新增這行，確保 ctx/font 有效

  ImGui.SetNextWindowSize(ctx, 220, 40, ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowBgAlpha(ctx, 1.0)

  -- 套用共享主題（若 library 不存在，pushed = 0）
  local pushed = 0
  if THEME then
    pushed = THEME.apply(ctx, ImGui, {
      extstate_ns = 'hsuanice_ImGui_Col',   -- 你的 themer 也可用這個 NS 寫入覆蓋
      -- overrides = { Header = 0xFFC700ff }, -- 某腳本想定制就放這裡；false 代表略過某鍵
    }) or 0
  end

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

  -- 還原主題
  if THEME and pushed > 0 then
    THEME.pop(ctx, ImGui)
  end

  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
