--[[
@description Auto Color All ShinyColor
@version 261002.1042
@author hsuanice
@about
  Standalone wrapper for the "All Shiny" action from
  hsuanice_Auto Color Items by Take Name.lua.

  Reads the same color-apply settings ExtState written by the main GUI script
  (namespace "hsuanice_AutoColorItems") — Normal Primary Target
  (Background/Peak, used to decide which field holds an item's "identity"
  color before converting it) and the BG Bright / BG Sat background scaling.
  No settings are duplicated here; edit them in the main GUI script and this
  wrapper follows automatically.

  If items are selected, converts just those items to Shiny color. If
  nothing is selected, asks for confirmation (OK/Cancel) before converting
  every item in the whole project. Always forces Shiny regardless of the
  main GUI's current Normal/Shiny mode setting. Items with no custom color
  are left alone, and items that already look Shiny (background already a
  pastel derivative of the peak color) are left alone too, so running this
  repeatedly does not keep fading colors out further.

  Run the main GUI script at least once first so the color-apply settings
  exist in ExtState.

@changelog
  v261002.1042
  - Fix: items already in Shiny mode were being re-pastelized on every run (background
    recomputed from the already-pale background instead of the true peak color), fading
    everything out more each time. Now detects "already shiny" by checking whether the
    background's hue matches the peak's hue and its saturation is meaningfully lower
    (the shiny formula's signature) and skips those items instead of reprocessing them.
  - Change: now converts just the selected items when any are selected; only falls back to
    the whole project (with an OK/Cancel confirmation prompt) when nothing is selected.

  v261002.1021
  - Initial extraction from hsuanice_Auto Color Items by Take Name.lua
]]

local PREF_NS = "hsuanice_AutoColorItems"

-- ─── HSV → 0xRRGGBB ──────────────────────────────────────────────────────────
local function hsv(h, s, v)
  h = h % 360
  local i = math.floor(h/60) % 6
  local f = h/60 - math.floor(h/60)
  local p,q,t = v*(1-s), v*(1-f*s), v*(1-(1-f)*s)
  local r,g,b
  if     i==0 then r,g,b=v,t,p elseif i==1 then r,g,b=q,v,p
  elseif i==2 then r,g,b=p,v,t elseif i==3 then r,g,b=p,q,v
  elseif i==4 then r,g,b=t,p,v else                r,g,b=v,p,q end
  return math.floor(r*255+.5)<<16 | math.floor(g*255+.5)<<8 | math.floor(b*255+.5)
end

local function rgb_to_hsv(r, g, b)
  local maxc = math.max(r, g, b)
  local minc = math.min(r, g, b)
  local d = maxc - minc
  local h = 0
  local s = maxc == 0 and 0 or (d / maxc)
  local v = maxc
  if d ~= 0 then
    if maxc == r then h = ((g - b) / d) % 6
    elseif maxc == g then h = ((b - r) / d) + 2
    else h = ((r - g) / d) + 4 end
    h = h * 60
  end
  return h, s, v
end

-- ─── color-apply mode (mirrors main script) ──────────────────────────────────
local NORMAL_PRIMARY_BG   = "background"
local NORMAL_PRIMARY_PEAK = "peak"
local normal_primary_target  = NORMAL_PRIMARY_BG
local bg_brightness_scale = 1.0   -- 0.0-2.0, scales item background Value; 1.0 = no change
local bg_saturation_scale = 1.0   -- 0.0-2.0, scales item background Saturation; 1.0 = no change

-- ─── load settings from ExtState (follows main GUI script) ───────────────────
local function load_pconf()
  local npt = reaper.GetExtState(PREF_NS, "normal_primary_target")
  if npt == NORMAL_PRIMARY_BG or npt == NORMAL_PRIMARY_PEAK then
    normal_primary_target = npt
  end
  local bbs = tonumber(reaper.GetExtState(PREF_NS, "bg_brightness_scale"))
  bg_brightness_scale = (bbs and bbs >= 0 and bbs <= 2) and bbs or 1.0
  local bss = tonumber(reaper.GetExtState(PREF_NS, "bg_saturation_scale"))
  bg_saturation_scale = (bss and bss >= 0 and bss <= 2) and bss or 1.0
end

-- ─── color application (mirrors main script; always Shiny here) ──────────────
local function shiny_background_rrggbb(rrggbb)
  local r = ((rrggbb >> 16) & 0xFF) / 255
  local g = ((rrggbb >> 8) & 0xFF) / 255
  local b = (rrggbb & 0xFF) / 255
  local h, s, v = rgb_to_hsv(r, g, b)
  s = s / 3.7
  v = v + ((0.92 - v) / 1.3)
  if v > 0.99 then v = 0.99 end
  return hsv(h, s, v)
end

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

local function adjust_bg_color(rrggbb)
  if bg_brightness_scale == 1.0 and bg_saturation_scale == 1.0 then return rrggbb end
  local r = ((rrggbb >> 16) & 0xFF) / 255
  local g = ((rrggbb >> 8) & 0xFF) / 255
  local b = (rrggbb & 0xFF) / 255
  local h, s, v = rgb_to_hsv(r, g, b)
  s = clamp01(s * bg_saturation_scale)
  v = clamp01(v * bg_brightness_scale)
  return hsv(h, s, v)
end

local function apply_item_background_color(item, rrggbb)
  rrggbb = adjust_bg_color(rrggbb)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR",
    reaper.ColorToNative((rrggbb>>16)&0xFF,(rrggbb>>8)&0xFF,rrggbb&0xFF)|0x1000000)
end

local function apply_item_peak_color_all_takes(item, rrggbb)
  local peak_native = reaper.ColorToNative((rrggbb >> 16) & 0xFF, (rrggbb >> 8) & 0xFF, rrggbb & 0xFF) | 0x1000000
  local take_count = reaper.GetMediaItemNumTakes(item)
  if take_count and take_count > 0 then
    for t = 0, take_count - 1 do
      local take = reaper.GetMediaItemTake(item, t)
      if take then reaper.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", peak_native) end
    end
  end
end

local function apply_shiny_color_to_item(item, rrggbb)
  apply_item_peak_color_all_takes(item, rrggbb)
  apply_item_background_color(item, shiny_background_rrggbb(rrggbb))
end

local function item_custom_rrggbb(custom)
  if (custom & 0x1000000) == 0 then return nil end
  local r, g, b = reaper.ColorFromNative(custom & 0xFFFFFF)
  return math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b)
end

-- Does bg look like the shiny-pastel derivative of peak? Checked by the
-- shape of the transform (same hue, meaningfully lower saturation) rather
-- than recomputing+comparing against the exact formula, so it stays correct
-- even if BG Bright/BG Sat have been changed since the item was colored.
-- Guards against false positives from black/white/grayscale secondary
-- colors (sb<=0.01) and grayscale peaks (sp<=0.01), where hue is meaningless.
local function looks_already_shiny(peak_rrggbb, bg_rrggbb)
  local hp, sp = rgb_to_hsv(((peak_rrggbb>>16)&0xFF)/255, ((peak_rrggbb>>8)&0xFF)/255, (peak_rrggbb&0xFF)/255)
  local hb, sb = rgb_to_hsv(((bg_rrggbb>>16)&0xFF)/255, ((bg_rrggbb>>8)&0xFF)/255, (bg_rrggbb&0xFF)/255)
  if sp <= 0.01 or sb <= 0.01 then return false end
  local hue_diff = math.abs(hp - hb)
  hue_diff = math.min(hue_diff, 360 - hue_diff)
  if hue_diff > 4 then return false end
  return sb <= sp * 0.6
end

-- Figures out what to do with one item: returns (seed_rrggbb, nil) when it
-- should be converted to Shiny from that seed color, or (nil, reason) when
-- it should be left alone — reason is "no_color" (nothing custom set) or
-- "already_shiny" (background already looks like a pastel of the peak
-- color, so re-deriving from it would just pastel it further).
local function get_item_shiny_seed(item)
  local bg_rrggbb = item_custom_rrggbb(math.floor(reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR") or 0))
  local take = reaper.GetActiveTake(item) or reaper.GetMediaItemTake(item, 0)
  local peak_rrggbb = take and item_custom_rrggbb(math.floor(reaper.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR") or 0)) or nil

  if not bg_rrggbb and not peak_rrggbb then return nil, "no_color" end
  if bg_rrggbb and peak_rrggbb and looks_already_shiny(peak_rrggbb, bg_rrggbb) then
    return nil, "already_shiny"
  end
  if normal_primary_target == NORMAL_PRIMARY_PEAK then
    return peak_rrggbb or bg_rrggbb
  else
    return bg_rrggbb or peak_rrggbb
  end
end

-- ─── main ─────────────────────────────────────────────────────────────────────
load_pconf()

local sel_n = reaper.CountSelectedMediaItems(0)
local items

if sel_n > 0 then
  items = {}
  for i = 0, sel_n - 1 do items[#items + 1] = reaper.GetSelectedMediaItem(0, i) end
else
  local choice = reaper.ShowMessageBox(
    "No items are selected.\n\nConvert ALL items in the project to Shiny color?",
    "Auto Color All ShinyColor", 1)
  if choice ~= 1 then return end
  local n = reaper.CountMediaItems(0)
  if n == 0 then
    reaper.ShowMessageBox("No items in project.", "Auto Color All ShinyColor", 0)
    return
  end
  items = {}
  for i = 0, n - 1 do items[#items + 1] = reaper.GetMediaItem(0, i) end
end

reaper.Undo_BeginBlock()
local applied, already_shiny, no_color = 0, 0, 0
for _, item in ipairs(items) do
  local rrggbb, reason = get_item_shiny_seed(item)
  if rrggbb then
    apply_shiny_color_to_item(item, rrggbb)
    applied = applied + 1
  elseif reason == "already_shiny" then
    already_shiny = already_shiny + 1
  else
    no_color = no_color + 1
  end
end
reaper.Undo_EndBlock("All Shiny Color", -1)
reaper.UpdateArrange()

if applied == 0 then
  reaper.ShowMessageBox("Nothing to convert (already shiny or no custom color).", "Auto Color All ShinyColor", 0)
end
