--[[
@description Auto Color Follow Track Color
@version 260918.1405
@author hsuanice
@about
  Standalone wrapper for the "Follow Track Color" action from
  hsuanice_Auto Color Items by Take Name.lua.

  Reads the same color-apply settings ExtState written by the main GUI script
  (namespace "hsuanice_AutoColorItems") — color-apply mode (Normal/Shiny,
  background/peak, secondary color), and the BG Bright / BG Sat background
  scaling. No settings are duplicated here; edit them in the main GUI script
  and this wrapper follows automatically.

  Colors each selected item to match its own track's current custom color
  (using the same Normal/Shiny color-apply logic as the main GUI). Tracks
  with no custom color set are left unchanged. Only applies to items — if
  tracks are selected instead (or nothing is selected), shows a reminder and
  does nothing.

  Run the main GUI script at least once first so the color-apply settings
  exist in ExtState.

@changelog
  v260918.1405
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
local COLOR_MODE_NORMAL = "normal"
local COLOR_MODE_SHINY  = "shiny"
local color_mode        = COLOR_MODE_NORMAL
local NORMAL_PRIMARY_BG   = "background"
local NORMAL_PRIMARY_PEAK = "peak"
local NORMAL_SECONDARY_MATCH = "match"
local NORMAL_SECONDARY_BLACK = "black"
local NORMAL_SECONDARY_WHITE = "white"
local normal_primary_target  = NORMAL_PRIMARY_BG
local normal_secondary_color = NORMAL_SECONDARY_WHITE
local bg_brightness_scale = 1.0   -- 0.0-2.0, scales item background Value; 1.0 = no change
local bg_saturation_scale = 1.0   -- 0.0-2.0, scales item background Saturation; 1.0 = no change

-- ─── load settings from ExtState (follows main GUI script) ───────────────────
local function load_pconf()
  local cm = reaper.GetExtState(PREF_NS, "color_mode")
  if cm == COLOR_MODE_SHINY or cm == COLOR_MODE_NORMAL then color_mode = cm end
  local npt = reaper.GetExtState(PREF_NS, "normal_primary_target")
  if npt == NORMAL_PRIMARY_BG or npt == NORMAL_PRIMARY_PEAK then
    normal_primary_target = npt
  end
  local nsc = reaper.GetExtState(PREF_NS, "normal_secondary_color")
  if nsc == "keep" then nsc = NORMAL_SECONDARY_MATCH end
  if nsc == NORMAL_SECONDARY_MATCH or nsc == NORMAL_SECONDARY_BLACK or nsc == NORMAL_SECONDARY_WHITE or nsc == "transparent" then
    normal_secondary_color = nsc
  end
  local bbs = tonumber(reaper.GetExtState(PREF_NS, "bg_brightness_scale"))
  bg_brightness_scale = (bbs and bbs >= 0 and bbs <= 2) and bbs or 1.0
  local bss = tonumber(reaper.GetExtState(PREF_NS, "bg_saturation_scale"))
  bg_saturation_scale = (bss and bss >= 0 and bss <= 2) and bss or 1.0
end

-- ─── color application (mirrors main script) ─────────────────────────────────
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
  if color_mode ~= COLOR_MODE_SHINY then return rrggbb end
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

local function normal_secondary_rrggbb(primary_rrggbb)
  if normal_secondary_color == NORMAL_SECONDARY_MATCH then return primary_rrggbb end
  if normal_secondary_color == NORMAL_SECONDARY_BLACK then return 0x000000 end
  if normal_secondary_color == NORMAL_SECONDARY_WHITE then return 0xFFFFFF end
  return primary_rrggbb
end

local function apply_normal_color_to_item(item, rrggbb)
  if normal_primary_target == NORMAL_PRIMARY_PEAK then
    apply_item_peak_color_all_takes(item, rrggbb)
    if normal_secondary_color == "transparent" then
      reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)
    else
      apply_item_background_color(item, normal_secondary_rrggbb(rrggbb))
    end
  else
    apply_item_background_color(item, rrggbb)
    if normal_secondary_color == "transparent" then
      local take_count = reaper.GetMediaItemNumTakes(item)
      if take_count and take_count > 0 then
        for t = 0, take_count - 1 do
          local take = reaper.GetMediaItemTake(item, t)
          if take then reaper.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", 0) end
        end
      end
    else
      apply_item_peak_color_all_takes(item, normal_secondary_rrggbb(rrggbb))
    end
  end
end

local function apply_shiny_color_to_item(item, rrggbb)
  apply_item_peak_color_all_takes(item, rrggbb)
  apply_item_background_color(item, shiny_background_rrggbb(rrggbb))
end

local function apply_color_by_mode(item, rrggbb)
  if color_mode == COLOR_MODE_SHINY then
    apply_shiny_color_to_item(item, rrggbb)
  else
    apply_normal_color_to_item(item, rrggbb)
  end
end

-- ─── target selection (selected items only; no track/whole-project fallback) ─
local function get_selected_items_row_major()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return nil end
  local items = {}
  for i = 0, n - 1 do items[#items + 1] = reaper.GetSelectedMediaItem(0, i) end
  table.sort(items, function(a, b)
    local ta, tb = reaper.GetMediaItem_Track(a), reaper.GetMediaItem_Track(b)
    local ya = math.floor((reaper.GetMediaTrackInfo_Value(ta, "IP_TRACKNUMBER") or 0) + 0.5)
    local yb = math.floor((reaper.GetMediaTrackInfo_Value(tb, "IP_TRACKNUMBER") or 0) + 0.5)
    if ya ~= yb then return ya < yb end
    local xa = reaper.GetMediaItemInfo_Value(a, "D_POSITION") or 0
    local xb = reaper.GetMediaItemInfo_Value(b, "D_POSITION") or 0
    if xa ~= xb then return xa < xb end
    local la = reaper.GetMediaItemInfo_Value(a, "D_LENGTH") or 0
    local lb2 = reaper.GetMediaItemInfo_Value(b, "D_LENGTH") or 0
    if la ~= lb2 then return la < lb2 end
    return tostring(a) < tostring(b)
  end)
  return items
end

-- ─── main ─────────────────────────────────────────────────────────────────────
load_pconf()

local items = get_selected_items_row_major()
if not items then
  if reaper.CountSelectedTracks(0) > 0 then
    reaper.ShowMessageBox("Follow Track Color only applies to items. Select items, not tracks.",
      "Auto Color Follow Track Color", 0)
  else
    reaper.ShowMessageBox("Select items first.", "Auto Color Follow Track Color", 0)
  end
  return
end

reaper.Undo_BeginBlock()
local applied, skipped = 0, 0
for _, item in ipairs(items) do
  local track = reaper.GetMediaItem_Track(item)
  local native = track and reaper.GetTrackColor(track) or 0
  if native ~= 0 then
    local r, g, b = reaper.ColorFromNative(native)
    apply_color_by_mode(item, math.floor(r) * 65536 + math.floor(g) * 256 + math.floor(b))
    applied = applied + 1
  else
    skipped = skipped + 1
  end
end
reaper.Undo_EndBlock("Follow Track Color", -1)
reaper.UpdateArrange()

if applied == 0 then
  reaper.ShowMessageBox("None of the selected items' tracks have a custom color set.",
    "Auto Color Follow Track Color", 0)
end
