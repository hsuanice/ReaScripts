--[[
@description hsuanice ReaImGui Theme Color (library + simple editor API)
@version 0.2.1
@changelog
  v0.2.1  Fix: use reaper.ImGui_ColorEdit4(ctx,label,rgba[,flags]) to avoid arg-count error.

@author hsuanice
@about
  Shared theme palette + helpers for ReaImGui UIs, plus a minimal editor API.
  - apply()/pop() to push/pop a unified color scheme across scripts
  - ExtState overrides per-key, and named Presets (save/load/delete/activate)
  - Simple editor drawer (M.editor) for quick color picking & preset management
@changelog
  v0.2.0  Add presets (save/load/delete/activate) and a minimal GUI editor (M.editor).
  v0.1.0  First release: default dark palette, apply()/pop(), set_accent(), ExtState override.
@noindex
]]

local M = {}

----------------------------------------------------------------
-- Namespaces and constants
----------------------------------------------------------------
M.NS_COLORS  = "hsuanice_ImGui_Col"          -- per-key overrides used by apply()
M.NS_PRESETS = "hsuanice_ImGui_Col_Presets"  -- presets storage (name -> serialized palette)
M.KEY_PRESETS_LIST = "PRESETS"               -- comma-separated preset names
M.KEY_ACTIVE       = "ACTIVE"                -- active preset name

----------------------------------------------------------------
-- Default palette (0xRRGGBBAA). Add/remove keys as you like.
----------------------------------------------------------------
M.colors = {
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
  CheckMark         = 0xffffffff,
}

----------------------------------------------------------------
-- Utilities
----------------------------------------------------------------
local function copy_table(t)
  local r = {}
  for k,v in pairs(t) do r[k] = v end
  return r
end

local function serialize_palette(colors)
  -- key=hex;key=hex; ...
  local parts = {}
  for k,v in pairs(colors) do
    parts[#parts+1] = string.format("%s=%08x", k, v)
  end
  table.sort(parts)
  return table.concat(parts, ";")
end

local function deserialize_palette(s)
  local t = {}
  if not s or s == "" then return t end
  for kv in s:gmatch("[^;]+") do
    local k, hex = kv:match("^([^=]+)=([0-9a-fA-F]+)$")
    if k and hex then t[k] = tonumber(hex, 16) end
  end
  return t
end

-- internal: resolve ImGui color enum by key, tolerant to both styles.
local function col_enum(ImGui, key)
  return (ImGui["Col_" .. key])
      or (reaper and reaper["ImGui_Col_" .. key] and reaper["ImGui_Col_" .. key]())
end

-- internal: parse hex string from ExtState; accept "0xAABBCCDD" or "AABBCCDD"
local function parse_ext_hex(s)
  if not s or s == "" then return nil end
  s = tostring(s):gsub("^0[xX]", "")
  local n = tonumber(s, 16)
  return n
end

-- Convert U32 <-> double4
local function u32_to_d4(ImGui, u32)
  local r,g,b,a = ImGui.ColorConvertU32ToDouble4(u32)
  return r,g,b,a
end
local function d4_to_u32(ImGui, r,g,b,a)
  return ImGui.ColorConvertDouble4ToU32(r,g,b,a)
end

----------------------------------------------------------------
-- ExtState: per-key overrides used by apply()
----------------------------------------------------------------
local function read_overrides()
  local t = {}
  for k,_ in pairs(M.colors) do
    if reaper.HasExtState(M.NS_COLORS, k) then
      local n = parse_ext_hex(reaper.GetExtState(M.NS_COLORS, k))
      if n then t[k] = n end
    end
  end
  return t
end

local function write_overrides(colors, persist)
  for k,v in pairs(M.colors) do
    local val = colors[k]
    if val then
      reaper.SetExtState(M.NS_COLORS, k, string.format("%08x", val), persist and true or false)
    else
      reaper.DeleteExtState(M.NS_COLORS, k, persist and true or false)
    end
  end
end

function M.reset_overrides(persist)
  for k,_ in pairs(M.colors) do
    reaper.DeleteExtState(M.NS_COLORS, k, persist and true or false)
  end
end

----------------------------------------------------------------
-- Public: Apply/Pop in scripts
----------------------------------------------------------------
local _push_counts = setmetatable({}, { __mode = "k" })

function M.apply(ctx, ImGui, opts)
  opts = opts or {}
  local use_ext   = (opts.use_extstate ~= false)
  local overrides = opts.overrides or {}
  local from_ext  = use_ext and read_overrides() or {}

  local pushed = 0
  for k, def in pairs(M.colors) do
    -- overrides[k] = false → skip pushing
    if overrides[k] ~= false then
      local color = overrides[k] or from_ext[k] or def
      local ce = col_enum(ImGui, k)
      if ce then
        ImGui.PushStyleColor(ctx, ce, color)
        pushed = pushed + 1
      end
    end
  end
  _push_counts[ctx] = pushed
  return pushed
end

function M.pop(ctx, ImGui)
  local n = _push_counts[ctx] or 0
  if n > 0 then ImGui.PopStyleColor(ctx, n) end
  _push_counts[ctx] = 0
end

function M.set_accent(rgba)
  M.colors.Header           = rgba
  M.colors.HeaderHovered    = rgba
  M.colors.HeaderActive     = rgba
  M.colors.CheckMark        = rgba
  M.colors.ButtonHovered    = rgba
  M.colors.ButtonActive     = rgba
  M.colors.SeparatorHovered = rgba
  M.colors.SeparatorActive  = rgba
end

function M.hex_u32(ImGui, hex, alpha)
  alpha = (alpha == nil) and 1 or alpha
  local h = tostring(hex):gsub("#","")
  local r = tonumber(h:sub(1,2),16) or 0
  local g = tonumber(h:sub(3,4),16) or 0
  local b = tonumber(h:sub(5,6),16) or 0
  return ImGui.ColorConvertDouble4ToU32(r/255, g/255, b/255, alpha)
end

----------------------------------------------------------------
-- Presets API
----------------------------------------------------------------
local function read_presets_list()
  local s = reaper.GetExtState(M.NS_PRESETS, M.KEY_PRESETS_LIST) or ""
  local list = {}
  for name in s:gmatch("[^,]+") do
    list[#list+1] = name
  end
  return list
end

local function write_presets_list(list)
  -- de-dupe
  local seen, out = {}, {}
  for _,name in ipairs(list) do
    if name ~= "" and not seen[name] then
      seen[name] = true
      out[#out+1] = name
    end
  end
  reaper.SetExtState(M.NS_PRESETS, M.KEY_PRESETS_LIST, table.concat(out, ","), true)
end

function M.list_presets()
  return read_presets_list()
end

function M.save_preset(name, colors)
  if not name or name == "" then return false, "empty name" end
  local pal = colors or (read_overrides())
  -- if nothing in overrides, save current defaults so it’s explicit
  if not next(pal) then pal = copy_table(M.colors) end
  reaper.SetExtState(M.NS_PRESETS, name, serialize_palette(pal), true)
  local list = read_presets_list()
  local exists = false
  for _,n in ipairs(list) do if n == name then exists = true break end end
  if not exists then
    list[#list+1] = name
    write_presets_list(list)
  end
  return true
end

function M.load_preset(name)
  if not name or name == "" then return nil end
  local s = reaper.GetExtState(M.NS_PRESETS, name)
  if not s or s == "" then return nil end
  return deserialize_palette(s)
end

function M.delete_preset(name)
  if not name or name == "" then return false end
  reaper.DeleteExtState(M.NS_PRESETS, name, true)
  local list = read_presets_list()
  local out = {}
  for _,n in ipairs(list) do if n ~= name then out[#out+1] = n end end
  write_presets_list(out)
  local active = reaper.GetExtState(M.NS_PRESETS, M.KEY_ACTIVE)
  if active == name then
    reaper.DeleteExtState(M.NS_PRESETS, M.KEY_ACTIVE, true)
  end
  return true
end

function M.activate_preset(name, persist)
  local pal = M.load_preset(name)
  if not pal then return false, "preset not found" end
  write_overrides(pal, persist ~= false)
  reaper.SetExtState(M.NS_PRESETS, M.KEY_ACTIVE, name, true)
  return true
end

function M.get_active_preset()
  local n = reaper.GetExtState(M.NS_PRESETS, M.KEY_ACTIVE)
  return n ~= "" and n or nil
end

----------------------------------------------------------------
-- Minimal Editor (draw inside your ImGui context)
----------------------------------------------------------------
-- Usage in a script:
--   local pushed = THEME.apply(ctx, ImGui) -- optional, for preview
--   THEME.editor(ctx, ImGui)               -- draw editor window
--   if pushed>0 then THEME.pop(ctx, ImGui) end
--
-- Or run from the provided "Theme Editor" launcher script.

local EDITOR = { init = false, current = {}, changed = false, active_name = nil, renamed = "" }

local function ensure_editor_state(ImGui)
  if EDITOR.init then return end
  -- Start from effective colors (defaults + overrides)
  local effective = copy_table(M.colors)
  local ov = read_overrides()
  for k,v in pairs(ov) do effective[k] = v end
  EDITOR.current = effective
  EDITOR.active_name = M.get_active_preset()
  EDITOR.renamed = EDITOR.active_name or ""
  EDITOR.init = true
end

local function draw_color_grid(ctx, ImGui)
  local flags = 0 -- ImGui.ColorEditFlags_NoInputs etc. (可依喜好加)
  local two_cols = true
  local i = 0
  for k,_ in pairs(M.colors) do
    -- 兩欄排版
    if two_cols then
      if i % 2 ~= 0 then ImGui.SameLine(ctx) end
    end
    ImGui.BeginGroup(ctx)
    ImGui.Text(ctx, k)
    local r,g,b,a = u32_to_d4(ImGui, EDITOR.current[k])
    local changed, new_rgba = reaper.ImGui_ColorEdit4(ctx, "##"..k, rgba, flags)
    if changed then
      EDITOR.current[k] = d4_to_u32(ImGui, nr,ng,nb,na)
      EDITOR.changed = true
    end
    ImGui.EndGroup(ctx)
    i = i + 1
  end
end

function M.editor(ctx, ImGui)
  ensure_editor_state(ImGui)

  ImGui.SetNextWindowSize(ctx, 680, 480, ImGui.Cond_FirstUseEver)
  local open = true
  local visible; visible, open = ImGui.Begin(ctx, "hsuanice Theme Editor", true,
    ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_MenuBar)

  if visible then
    -- Menu bar: Preset ops
    if ImGui.BeginMenuBar(ctx) then
      if ImGui.BeginMenu(ctx, "Preset") then
        if ImGui.MenuItem(ctx, "Save", "Ctrl+S") then
          local name = EDITOR.renamed ~= "" and EDITOR.renamed or (EDITOR.active_name or "default")
          M.save_preset(name, EDITOR.current)
          EDITOR.active_name = name
        end
        if ImGui.MenuItem(ctx, "Save As...") then
          -- use the input box below in body; here just a shortcut
        end
        if ImGui.MenuItem(ctx, "Activate") then
          if EDITOR.active_name then M.activate_preset(EDITOR.active_name, true) end
        end
        if ImGui.MenuItem(ctx, "Delete") then
          if EDITOR.active_name then
            M.delete_preset(EDITOR.active_name)
            EDITOR.active_name = nil
            EDITOR.renamed = ""
          end
        end
        if ImGui.MenuItem(ctx, "Reset to Defaults") then
          EDITOR.current = copy_table(M.colors)
          EDITOR.changed = true
        end
        ImGui.EndMenu(ctx)
      end
      ImGui.EndMenuBar(ctx)
    end

    -- Active preset selector + name edit
    local list = M.list_presets()
    local current_idx = 0
    local labels = {"(none)"}
    for i,n in ipairs(list) do
      labels[#labels+1] = n
      if n == EDITOR.active_name then current_idx = i end
    end

    ImGui.Text(ctx, "Active Preset:")
    ImGui.SameLine(ctx)
    if ImGui.BeginCombo(ctx, "##preset", labels[current_idx+1] or "(none)") then
      if ImGui.Selectable(ctx, "(none)", current_idx==0) then
        EDITOR.active_name = nil
        EDITOR.renamed = ""
      end
      for i,n in ipairs(list) do
        local sel = (i == current_idx)
        if ImGui.Selectable(ctx, n, sel) then
          EDITOR.active_name = n
          EDITOR.renamed = n
          local pal = M.load_preset(n)
          if pal and next(pal) then
            EDITOR.current = copy_table(M.colors)
            for k,v in pairs(pal) do EDITOR.current[k] = v end
            EDITOR.changed = false
          end
        end
      end
      ImGui.EndCombo(ctx)
    end

    ImGui.SameLine(ctx); ImGui.Text(ctx, "Name:")
    ImGui.SameLine(ctx)
    local changed, newname = ImGui.InputText(ctx, "##name", EDITOR.renamed, ImGui.InputTextFlags_CharsNoBlank)
    if changed then EDITOR.renamed = newname end

    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Save") then
      local name = EDITOR.renamed ~= "" and EDITOR.renamed or (EDITOR.active_name or "default")
      M.save_preset(name, EDITOR.current)
      EDITOR.active_name = name
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Save As") then
      if EDITOR.renamed ~= "" then
        M.save_preset(EDITOR.renamed, EDITOR.current)
        EDITOR.active_name = EDITOR.renamed
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Activate") then
      if EDITOR.active_name then M.activate_preset(EDITOR.active_name, true) end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Delete") then
      if EDITOR.active_name then
        M.delete_preset(EDITOR.active_name)
        EDITOR.active_name = nil
        EDITOR.renamed = ""
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Reset Defaults") then
      EDITOR.current = copy_table(M.colors)
      EDITOR.changed = true
    end

    ImGui.Separator(ctx)
    -- Color grid
    draw_color_grid(ctx, ImGui)

    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, EDITOR.changed and "Changed (not saved)" or "Saved")
    if EDITOR.active_name then
      ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, "Active: " .. EDITOR.active_name)
    end

    ImGui.End(ctx)
  end

  return open
end

return M
