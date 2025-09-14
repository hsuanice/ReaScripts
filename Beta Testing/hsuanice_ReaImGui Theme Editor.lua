--[[
@description hsuanice ReaImGui Theme Editor
@version 0.5.0
@author hsuanice
@about
  Dedicated GUI for editing the shared ReaImGui theme (colors + presets).
  Works with ReaImGui 0.10.x.
@changelog
  v0.5.0
  - Change: stop pinning to 0.9.3.2; require ReaImGui ≥ 0.10 (use dofile(... )('0.10')).
  - Fix: avoid "ImGui__init: version number is empty" by always passing a non-empty version string.
  - Keep: all editor behaviors and the Theme Color library APIs unchanged.
  v0.4.2 (2025-09-14)
    - Add: BodyText color slot support in the editor UI.
      * Color grid now includes BodyText alongside TitleText.
      * Live preview: pushes BodyText after Begin(), pops before End(),
        so content text uses the configured color while the window is open.
    - Update: clarified TitleText preview logic 
      (push before Begin(), pop immediately after) so only the title bar text
      is affected.
    - Behavior: no changes to presets, saving, or other editor features.

  v0.4.1  Save-awareness: the status now reflects whether changes are saved to the current preset
          (including overwriting an existing preset). Internally tracks a saved snapshot
          (name + palette) and marks "(not saved)" whenever the in-memory palette differs.
          Live apply: color edits still update ExtState immediately; the status purely indicates
          preset persistence. Preset selection auto-activates and also resets the saved snapshot.
          No library API changes.

  v0.4.0  Live preview & global apply:
          - The editor now previews from the in-memory palette (S.current) instead of ExtState.
          - Any color change immediately writes to ExtState via THEME.set_overrides(), so all
            scripts using THEME.apply() update in real time (no more reselect/Activate needed).
          - Title bar text color (TitleText) is previewed from S.current by pushing before Begin()
            and popping right after.
          - Preset selection still auto-activates and loads into S.current; Save/Save As only
            control preset files (not required for live applying).
          No API changes to the library.

  v0.3.4  Layout: dedicate a top status line for "(not saved) / Saved"; move the "Preset:" row below it.
          Preset: replace the titlebar Preset menu/button with a plain "Preset:" label + dropdown.
          Behavior: auto-activate the selected preset immediately; remove the separate Activate button.
          Spacing: remove the extra blank line between the Preset and Name rows.
          Keyboard: press ESC to close the editor window.
          No API changes; presets and color grid behavior are unchanged.

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

-- 1) Load ReaImGui (no version lock; follow installed ReaImGui, e.g. 0.10.0.2)
local imgui_path = reaper.ImGui_GetBuiltinPath() .. '/imgui.lua'
local ImGui = dofile(imgui_path)('0.10')   -- 允許 0.10.x（含 0.10.0.2）

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
local ctx = ImGui.CreateContext('hsuanice Theme Editor')

-- 建議在建立 ctx 後設定一次預設字型給 library（專案統一基準）
THEME.set_font('default', 'sans-serif', 16)

-- 4) UI width presets (adjust here)
local UI = {
  field_w       = 160,  -- NEW: 統一給 Preset 下拉與 Name 輸入用
  color_edit_w  = 200,
}

-- 5) Local editor state (kept inside the editor script)
local S = {
  init=false, current={}, changed=false,
  active_name=nil, name_field="",
  saved_name=nil, saved_serial=nil,  -- ★ 新增：最後一次「已儲存」的名稱與內容快照
  dirty=false,                        -- ★ 新增：是否有未儲存變更
}

-- ★ 用於比對內容是否與已儲存相同（key 排序，避免順序造成差異）
local function serialize_palette_for_compare(colors)
  local keys = {}
  for k in pairs(colors) do keys[#keys+1] = k end
  table.sort(keys)
  local out = {}
  for _,k in ipairs(keys) do
    out[#out+1] = string.format("%s=%08x", k, colors[k] or 0)
  end
  return table.concat(out, ";")
end

-- ★ 更新 dirty 狀態（名稱或內容有任何差異就視為未儲存）
local function update_dirty()
  local cur_serial = serialize_palette_for_compare(S.current)
  S.dirty = (cur_serial ~= S.saved_serial) or (S.active_name ~= S.saved_name)
  S.changed = S.dirty  -- 沿用舊標籤的語意
end

-- ★ 設定「已儲存」快照（在 Save/Save As/載入 preset 後呼叫）
local function mark_saved()
  S.saved_name   = S.active_name
  S.saved_serial = serialize_palette_for_compare(S.current)
  update_dirty()
end


local function init_state()
  S.active_name = THEME.get_active_preset()
  S.name_field  = S.active_name or ""

  -- 以預設表為底，再覆蓋 active preset（若有）
  S.current = {}; for k,v in pairs(THEME.colors) do S.current[k] = v end
  if S.active_name then
    local pal = THEME.load_preset(S.active_name)
    if pal and next(pal) then for k,v in pairs(pal) do S.current[k] = v end end
  end

  mark_saved()     -- ★ 一開始就把目前狀態當成「已儲存」
  S.init = true
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
    if changed then
      S.current[k] = new_rgba
      THEME.set_overrides(S.current, true)  -- live 全域（維持）
      update_dirty()                        -- ★ 變更後立刻更新狀態
    end

    ImGui.EndGroup(ctx)
    i = i + 1
  end
end

-- 6) Main loop
local open = true
local function loop()
  local pushed = THEME.apply(ctx, ImGui, { use_extstate = false, overrides = S.current }) or 0
  if not S.init then init_state() end




  -- Begin 之前：只上「標題字色」
  THEME.push_title_text(ctx, ImGui)
  local vis; vis, open = ImGui.Begin(ctx, "hsuanice Theme Editor", true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_MenuBar)
  THEME.pop_title_text(ctx, ImGui)  -- 立刻彈回，避免影響內文

  -- ESC 關閉（僅當視窗被聚焦時）
  if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    open = false
  end

  if vis then
    -- Begin 之後才上「內文字色」與「字型」
    THEME.push_body_text(ctx, ImGui, (S.current and S.current.BodyText) or THEME.colors.BodyText)
    THEME.push_font(ctx, ImGui, 'default')  -- 交給 library，內含第三參數（基準字級）

    -- Row 0: Status line（獨立一行）
    ImGui.TextDisabled(ctx, S.dirty and "(Not saved)" or "Saved")

    -- Row 1: Preset label + dropdown + Delete
    local list = THEME.list_presets()
    local labels = {"(none)"}; local current_idx = 0
    for i,n in ipairs(list) do
      labels[#labels+1] = n
      if n == S.active_name then current_idx = i end
    end

    ImGui.Text(ctx, "Preset:")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, UI.field_w)
    if ImGui.BeginCombo(ctx, "##preset", labels[current_idx+1] or "(none)") then
      if ImGui.Selectable(ctx, "(none)", current_idx==0) then
        S.active_name = nil
        S.name_field  = ""
        S.current = {}; for k,v in pairs(THEME.colors) do S.current[k] = v end
        S.changed = false
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
            THEME.activate_preset(n, true)  -- 自動啟用（寫入 ExtState）
            mark_saved()
          end
        end
      end
      ImGui.EndCombo(ctx)
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
    ImGui.Text(ctx, "Name: "); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, UI.field_w)
    local changed, newname = ImGui.InputText(ctx, "##name", S.name_field, ImGui.InputTextFlags_CharsNoBlank)
    if changed then S.name_field = newname end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Save") then
      local nm = (S.name_field ~= "" and S.name_field) or (S.active_name or "default")
      THEME.save_preset(nm, S.current)
      S.active_name = nm
      mark_saved()
    end

    if ImGui.Button(ctx, "Save As") then
      if S.name_field ~= "" then
        THEME.save_preset(S.name_field, S.current)
        S.active_name = S.name_field
        mark_saved()
      end
    end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Reset Defaults") then
      S.current = {}; for k,v in pairs(THEME.colors) do S.current[k] = v end
      THEME.set_overrides(S.current, true)
      update_dirty()
    end

    ImGui.Separator(ctx)

    -- Color grid
    draw_color_grid()

    -- 先彈字型，再彈內文字色（順序與 Push 對應）
    THEME.pop_font(ctx, ImGui)
    THEME.pop_body_text(ctx, ImGui)
  end

  -- 無論 vis 真或假，都一定要 End 一次
  ImGui.End(ctx)

  -- 套用主題的 Pop（跟 loop 開頭的 apply 配對）
  if pushed > 0 then THEME.pop(ctx, ImGui) end

  -- 循環
  if open then reaper.defer(loop) end

end

reaper.defer(loop)
