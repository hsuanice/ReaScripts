--[[
@description hsuanice ReaImGui Theme Editor
@version 0.3.0
@author hsuanice
@about
  Dedicated GUI for editing the shared ReaImGui theme (colors + presets).
  Library holds only data/APIs; all UI belongs here.
  Requires: "Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua"
@changelog
  v0.3.0  Move all editor GUI out of the library into this script.
          Add width controls (preset combo, name input, color editor).
  v0.2.0  Previous rename and future-proof notes.
]]

-- 1) Load ReaImGui (lock version)
local imgui_path = reaper.ImGui_GetBuiltinPath() .. '/imgui.lua'
local ImGui = dofile(imgui_path)('0.9.3.2')

-- 2) Load Theme Color Library (data/APIs only)
local LIB_PATH = reaper.GetResourcePath()
  .. '/Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua'

local ok, THEME = pcall(dofile, LIB_PATH)
if not ok or type(THEME) ~= 'table' then
  reaper.MB("Missing or invalid theme color library:\n" .. LIB_PATH, "Error", 0)
  return
end

-- 3) Context + font
local ctx = ImGui.CreateContext("hsuanice Theme Editor",
  ImGui.ConfigFlags_DockingEnable | ImGui.ConfigFlags_NavEnableKeyboard)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)

local font = ImGui.CreateFont('sans-serif', 16)
ImGui.Attach(ctx, font)

-- 4) UI width presets (adjust here)
local UI = {
  preset_combo_w = 140,
  name_input_w   = 160,
  color_edit_w   = 200, -- overall width for ColorEdit4 (controls R/G/B/A widths)
}

-- 5) Local editor state (kept inside the editor script)
local S = { init=false, current={}, changed=false, active_name=nil, name_field="" }

local function init_state()
  S.current     = THEME.get_effective_colors()
  S.active_name = THEME.get_active_preset()
  S.name_field  = S.active_name or ""
  S.changed     = false
  S.init        = true
end

local function draw_color_grid()
  local flags = 0 -- e.g. ImGui.ColorEditFlags_NoInputs if you want no numeric inputs
  local i = 0
  for k,_ in pairs(THEME.colors) do
    if i % 2 == 1 then ImGui.SameLine(ctx) end
    ImGui.BeginGroup(ctx)
    ImGui.Text(ctx, k)
    local rgba = S.current[k] or THEME.colors[k] or 0xffffffff
    ImGui.SetNextItemWidth(ctx, UI.color_edit_w)
    local changed, new_rgba = reaper.ImGui_ColorEdit4(ctx, "##"..k, rgba, flags)
    if changed then S.current[k] = new_rgba; S.changed = true end
    ImGui.EndGroup(ctx)
    i = i + 1
  end
end

-- 6) Main loop
local open = true
local function loop()
  if not S.init then init_state() end

  local pushed = THEME.apply(ctx, ImGui) or 0 -- preview current theme
  ImGui.PushFont(ctx, font)

  ImGui.SetNextWindowSize(ctx, 720, 520, ImGui.Cond_FirstUseEver)
  local vis; vis, open = ImGui.Begin(ctx, "hsuanice Theme Editor", true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_MenuBar)

  if vis then
    -- Menu Bar (optional quick ops)
    if ImGui.BeginMenuBar(ctx) then
      if ImGui.BeginMenu(ctx, "Preset") then
        if ImGui.MenuItem(ctx, "Activate") then
          if S.active_name then THEME.activate_preset(S.active_name, true) end
        end
        if ImGui.MenuItem(ctx, "Reset to Defaults") then
          S.current = {}
          for k,v in pairs(THEME.colors) do S.current[k] = v end
          S.changed = true
        end
        ImGui.EndMenu(ctx)
      end
      ImGui.EndMenuBar(ctx)
    end

    -- Row 1: preset dropdown + Activate/Delete
    local list = THEME.list_presets()
    local labels = {"(none)"}; local current_idx = 0
    for i,n in ipairs(list) do
      labels[#labels+1] = n
      if n == S.active_name then current_idx = i end
    end

    ImGui.Text(ctx, "Preset:")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, UI.preset_combo_w)
    if ImGui.BeginCombo(ctx, "##preset", labels[current_idx+1] or "(none)") then
      if ImGui.Selectable(ctx, "(none)", current_idx==0) then
        S.active_name = nil; S.name_field = ""
      end
      for i,n in ipairs(list) do
        local sel = (i == current_idx)
        if ImGui.Selectable(ctx, n, sel) then
          S.active_name = n
          S.name_field  = n
          local pal = THEME.load_preset(n)
          if pal and next(pal) then
            S.current = {}
            for k,v in pairs(THEME.colors) do S.current[k] = v end
            for k,v in pairs(pal) do S.current[k] = v end
            S.changed = false
          end
        end
      end
      ImGui.EndCombo(ctx)
    end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Activate") then
      if S.active_name then THEME.activate_preset(S.active_name, true) end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Delete") then
      if S.active_name then
        THEME.delete_preset(S.active_name)
        S.active_name = nil
        S.name_field  = ""
      end
    end

    -- Row 2: Name + Save/Save As/Reset
    ImGui.NewLine(ctx)
    ImGui.Text(ctx, "Name:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, UI.name_input_w)
    local changed, newname = ImGui.InputText(ctx, "##name", S.name_field, ImGui.InputTextFlags_CharsNoBlank)
    if changed then S.name_field = newname end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Save") then
      local nm = (S.name_field ~= "" and S.name_field) or (S.active_name or "default")
      THEME.save_preset(nm, S.current)
      S.active_name = nm
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Save As") then
      if S.name_field ~= "" then
        THEME.save_preset(S.name_field, S.current)
        S.active_name = S.name_field
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Reset Defaults") then
      S.current = {}
      for k,v in pairs(THEME.colors) do S.current[k] = v end
      S.changed = true
    end

    ImGui.Separator(ctx)

    -- Color grid
    draw_color_grid()

    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, S.changed and "(not saved)" or "Saved")
    if S.active_name then
      ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, "Active: " .. S.active_name)
    end

    ImGui.End(ctx)
  end

  ImGui.PopFont(ctx)
  if pushed > 0 then THEME.pop(ctx, ImGui) end
  if open then reaper.defer(loop) end
end

reaper.defer(loop)
