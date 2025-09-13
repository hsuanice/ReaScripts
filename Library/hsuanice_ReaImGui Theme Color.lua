--[[
@description hsuanice ReaImGui Theme Color (library only)
@version 0.3.0
@author hsuanice
@about
  Library for shared ReaImGui theme colors: palette, apply/pop, ExtState overrides, presets API.
  GUI/editor code has been removed from the library; use a dedicated Editor script instead.
@changelog
  v0.3.0  Split responsibilities: remove all editor/GUI from the library. Keep only data & APIs.
          Add helpers: get_effective_colors(), set_overrides(colors[, persist]).
  v0.2.2  Fixes for ColorEdit and robustness (now handled by the external editor).
  v0.2.0  Presets API; minimal GUI editor (removed in v0.3.0).
  v0.1.0  Initial: default palette + apply()/pop() + set_accent() + ExtState overrides.
@noindex
]]

local M = {}

----------------------------------------------------------------
-- Namespaces and constants
----------------------------------------------------------------
M.NS_COLORS        = "hsuanice_ImGui_Col"           -- per-key overrides used by apply()
M.NS_PRESETS       = "hsuanice_ImGui_Col_Presets"   -- presets storage (name -> serialized palette)
M.KEY_PRESETS_LIST = "PRESETS"                      -- comma-separated preset names
M.KEY_ACTIVE       = "ACTIVE"                       -- active preset name

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
  return tonumber(s, 16)
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
  for k,_ in pairs(M.colors) do
    local val = colors and colors[k] or nil
    if val then
      reaper.SetExtState(M.NS_COLORS, k, string.format("%08x", val), persist and true or false)
    else
      reaper.DeleteExtState(M.NS_COLORS, k, persist and true or false)
    end
  end
end

-- Public helpers for callers/editor
function M.get_effective_colors()
  local effective = copy_table(M.colors)
  local ov = read_overrides()
  for k,v in pairs(ov) do effective[k] = v end
  return effective
end

function M.set_overrides(colors, persist)
  write_overrides(colors, persist ~= false)
end

function M.reset_overrides(persist)
  write_overrides(nil, persist)
end

----------------------------------------------------------------
-- Apply/Pop in scripts
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

-- Optional helper: convert "#RRGGBB" + alpha(0..1) to U32.
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
  for name in s:gmatch("[^,]+") do list[#list+1] = name end
  return list
end

local function write_presets_list(list)
  local seen, out = {}, {}
  for _,name in ipairs(list) do
    if name ~= "" and not seen[name] then
      seen[name] = true
      out[#out+1] = name
    end
  end
  reaper.SetExtState(M.NS_PRESETS, M.KEY_PRESETS_LIST, table.concat(out, ","), true)
end

function M.list_presets() return read_presets_list() end

function M.save_preset(name, colors)
  if not name or name == "" then return false, "empty name" end
  local pal = colors or M.get_effective_colors()
  reaper.SetExtState(M.NS_PRESETS, name, serialize_palette(pal), true)
  local list = read_presets_list()
  local exists = false
  for _,n in ipairs(list) do if n == name then exists = true break end end
  if not exists then list[#list+1] = name; write_presets_list(list) end
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
  if active == name then reaper.DeleteExtState(M.NS_PRESETS, M.KEY_ACTIVE, true) end
  return true
end

function M.activate_preset(name, persist)
  local pal = M.load_preset(name)
  if not pal then return false, "preset not found" end
  M.set_overrides(pal, persist ~= false)
  reaper.SetExtState(M.NS_PRESETS, M.KEY_ACTIVE, name, true)
  return true
end

function M.get_active_preset()
  local n = reaper.GetExtState(M.NS_PRESETS, M.KEY_ACTIVE)
  return n ~= "" and n or nil
end

return M
