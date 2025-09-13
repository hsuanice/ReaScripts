--[[
@description hsuanice ReaImGui Theme Editor
@version 0.2.0
@author hsuanice
@about
  Launch a GUI to edit the shared ReaImGui theme. Currently includes Color editor & presets.
  Future-ready to add Style (padding/rounding/etc.) as another tab in the same editor.
  Requires: "Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua"
@changelog
  v0.2.0  Rename to 'hsuanice_ReaImGui Theme Editor.lua' and keep future-proof naming.
  v0.1.1  (prev) Theme Color Editor rename & title update.
]]

-- 1) Load ReaImGui (lock version for consistent UI)
local imgui_path = reaper.ImGui_GetBuiltinPath() .. '/imgui.lua'
local ImGui = dofile(imgui_path)('0.9.3.2')

-- 2) Load Theme Color Library
local LIB_PATH = reaper.GetResourcePath()
  .. '/Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua'

local ok, THEME = pcall(dofile, LIB_PATH)
if not ok or type(THEME) ~= 'table' or not THEME.editor then
  reaper.MB("Missing or invalid theme library:\n" .. LIB_PATH, "Error", 0)
  return
end

-- 3) Context + font
local ctx = ImGui.CreateContext("hsuanice Theme Editor",
  ImGui.ConfigFlags_DockingEnable | ImGui.ConfigFlags_NavEnableKeyboard)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)

local font = ImGui.CreateFont('sans-serif', 16)
ImGui.Attach(ctx, font)

-- 4) Main loop
local open = true
local function loop()
  local pushed = THEME.apply(ctx, ImGui) or 0   -- preview with current theme colors
  ImGui.PushFont(ctx, font)
  -- NOTE: THEME.editor 目前只含 Colors 分頁；未來可在 library 裡擴充為 Colors / Style 分頁
  open = THEME.editor(ctx, ImGui)
  ImGui.PopFont(ctx)
  if pushed > 0 then THEME.pop(ctx, ImGui) end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
