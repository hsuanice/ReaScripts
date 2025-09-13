--[[
@description hsuanice ReaImGui Theme Color (library)
@version 0.1.0
@author hsuanice
@about
  Shared theme palette + helpers for ReaImGui UIs.
  - One-call apply()/pop() to push/pop a unified color scheme
  - ExtState override (per-key) so an external "themer" can persist user colors
  - Per-script overrides supported at call site
@changelog
  v0.1.0  First release: default dark palette, apply()/pop(), set_accent(), ExtState override.
@noindex
]]

local M = {}

-- Default dark palette (0xRRGGBBAA). Add/remove keys as you like.
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

-- track push counts per ImGui context (auto-GC when ctx dies)
local _push_counts = setmetatable({}, { __mode = "k" })

-- internal: resolve ImGui color enum by key, tolerant to both styles.
local function col_enum(ImGui, key)
  -- Prefer ImGui.Col_* constant, fallback to reaper.ImGui_Col_*() if needed.
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

-- Apply theme to current frame.
-- opts:
--   extstate_ns   : string, ExtState namespace for per-key overrides (default "hsuanice_ImGui_Col")
--   use_extstate  : boolean, read overrides from ExtState (default true)
--   overrides     : table { KeyName = 0xRRGGBBAA | false }  -- false = skip pushing that key
function M.apply(ctx, ImGui, opts)
  opts = opts or {}
  local ns        = opts.extstate_ns  or "hsuanice_ImGui_Col"
  local use_ext   = (opts.use_extstate ~= false)
  local overrides = opts.overrides or {}

  local pushed = 0
  for k, def in pairs(M.colors) do
    -- allow caller to skip a key by setting overrides[k] = false
    if overrides[k] ~= false then
      local color = overrides[k] or def

      if use_ext and reaper and reaper.HasExtState(ns, k) then
        local s = reaper.GetExtState(ns, k)
        local n = parse_ext_hex(s)
        if n then color = n end
      end

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

-- Pop what apply() pushed for this ctx.
function M.pop(ctx, ImGui)
  local n = _push_counts[ctx] or 0
  if n > 0 then ImGui.PopStyleColor(ctx, n) end
  _push_counts[ctx] = 0
end

-- Convenience: set an accent color across common slots.
-- Pass a single 0xRRGGBBAA value (e.g. 0xFFC700ff).
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
-- Usage: M.hex_u32(ImGui, "#FFA500", 1.0)
function M.hex_u32(ImGui, hex, alpha)
  alpha = (alpha == nil) and 1 or alpha
  local h = tostring(hex):gsub("#","")
  local r = tonumber(h:sub(1,2),16) or 0
  local g = tonumber(h:sub(3,4),16) or 0
  local b = tonumber(h:sub(5,6),16) or 0
  return ImGui.ColorConvertDouble4ToU32(r/255, g/255, b/255, alpha)
end

return M
