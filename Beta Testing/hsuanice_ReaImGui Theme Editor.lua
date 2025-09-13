--[[
@description hsuanice ReaImGui Theme Editor
@version 0.3.3
@author hsuanice
@about
  Dedicated GUI for editing the shared ReaImGui theme (colors + presets).
  Library holds only data/APIs; all UI belongs here.
  Requires: "Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua"

@changelog
  v0.3.3  Layout: move the "(not saved) · Active: <name>" status to its own top line.
          Preset row: reintroduce a plain "Preset:" label before the dropdown (no button),
          keeping the unified width for the dropdown (`field_w`). No API changes.
  v0.3.2  UI cleanup: remove the redundant "Preset" label below the title bar.
          Move the "Saved / (not saved) · Active: <name>" status to that header slot.
          Unify widths for the Preset dropdown and Name input using a single `field_w`.
          No API changes; color grid and preset actions unchanged.
  v0.3.1  Stability: move PushFont to after Begin() and PopFont before End().
          Integrate TitleText (push before Begin, pop right after) to color only the title bar text.
          Remove duplicated Begin/apply block and deduplicate library loading.
  v0.3.0  Move all editor GUI out of the library into this script; add width controls.
  v0.2.0  Previous rename and future-proof notes.

]]

-- 1) Load ReaImGui (lock version)
local imgui_path = reaper.ImGui_GetBuiltinPath() .. '/imgui.lua'
local ImGui = dofile(imgui_path)('0.9.3.2')

-- 2) Load Theme Color Library (data/APIs only)
local LIB_PATH = reaper.GetResourcePath()
  .. '/Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua'

reaper.ShowConsoleMsg("[Theme Editor] Loading library:\n" .. LIB_PATH .. "\n")

local ok, mod_or_err = pcall(dofile, LIB_PATH)
if not ok then
  reaper.MB("Theme library error:\n" .. tostring(mod_or_err) .. "\n\nPath:\n" .. LIB_PATH, "Error", 0)
  return
end

local THEME = mod_or_err
if type(THEME) ~= 'table' then
  reaper.MB("Theme library returned a non-table.\nPath:\n" .. LIB_PATH, "Error", 0)
  return
end



-- 3) Context + font
local ctx  = ImGui.CreateContext('hsuanice Theme Editor')
local font = ImGui.CreateFont('sans-serif', 16)  -- 或你的字型/大小
ImGui.Attach(ctx, font)  -- 很重要：把字型綁到該 ctx【Attach】

-- 4) UI width presets (adjust here)
local UI = {
  field_w       = 160,  -- NEW: 統一給 Preset 下拉與 Name 輸入用
  color_edit_w  = 200,
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

  -- （可選）在 Begin 前暫時覆蓋標題字色
  local did_title = THEME.push_title_text(ctx, ImGui)

  ImGui.SetNextWindowSize(ctx, 720, 520, ImGui.Cond_FirstUseEver)
  local vis; vis, open = ImGui.Begin(ctx, "hsuanice Theme Editor", true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_MenuBar)

  -- 一進 Begin 立刻還原，避免內文字色被換掉
  if did_title then THEME.pop_title_text(ctx, ImGui) end

  -- 現在開始才 PushFont（在視窗 frame 內）
  ImGui.PushFont(ctx, font)

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

    -- Row 0: Status line（獨立一行）
    ImGui.TextDisabled(ctx, S.changed and "(not saved)" or "Saved")
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Active: " .. (S.active_name or "(none)"))

    -- Row 1: Preset label + dropdown + Activate/Delete
    local list = THEME.list_presets()
    local labels = {"(none)"}; local current_idx = 0
    for i,n in ipairs(list) do
      labels[#labels+1] = n
      if n == S.active_name then current_idx = i end
    end

    ImGui.Text(ctx, "Preset:")                 -- 純文字標籤
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, UI.field_w)    -- 下拉寬度統一
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
            S.current = {}; for k,v in pairs(THEME.colors) do S.current[k] = v end
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
    ImGui.SetNextItemWidth(ctx, UI.field_w)  -- 統一寬度
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

    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end

  if pushed > 0 then THEME.pop(ctx, ImGui) end

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
