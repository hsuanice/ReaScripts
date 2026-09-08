--[[
@description Auto Color Smart Random
@version 260908.1220
@author hsuanice
@about
  Standalone wrapper for the "Smart Random" action from
  hsuanice_Auto Color Items by Take Name.lua.

  Reads the same palette + settings ExtState written by the main GUI script
  (namespace "hsuanice_AutoColorItems") — palette colors and color-apply mode
  (Normal/Shiny, background/peak, secondary color). No settings are
  duplicated here; edit them in the main GUI script and this wrapper follows
  automatically.

  Colors the selected tracks, or the selected items (row-major: top-to-bottom
  by track, left-to-right by position) if no tracks are selected, picking a
  random palette color per track/item while avoiding similar colors on
  adjacent tracks/items (and excluding grayscale/low-saturation swatches).
  If nothing is selected, does nothing (shows a reminder instead of falling
  back to the whole project).

  Run the main GUI script at least once first so the palette/settings exist
  in ExtState.

@changelog
  v260908.1220
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

-- ─── palette config (mirrors main script defaults) ───────────────────────────
local PCONF = {
  hue_offset = 0,
  hue_range  = 330,
  grey_row   = false,
  rows = {
    { sat=0.20, val=0.90 },
    { sat=0.65, val=0.75 },
    { sat=0.90, val=0.55 },
  }
}
local PALETTE_COLS = 8
local PALETTE = {}

local DEFAULT_PALETTE_COLORS = {
  0xFF0000, 0xFF7600, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xA000FF, 0xFF00FF,
  0x990000, 0x994700, 0x808000, 0x008000, 0x008080, 0x000080, 0x800080, 0xB400B4,
  0x000000, 0x242424, 0x494949, 0x6D6D6D, 0x929292, 0xB6B6B6, 0xDBDBDB, 0xFFFFFF,
}

local function gen_palette()
  local old_take_kw, old_track_kw = {}, {}
  for i, p in ipairs(PALETTE) do
    old_take_kw[i] = p.take_keyword or p.keyword or ""
    old_track_kw[i] = p.track_keyword or ""
  end
  while #PALETTE > 0 do table.remove(PALETTE) end
  local cols = PALETTE_COLS
  for r = 1, #PCONF.rows do
    local row = PCONF.rows[r]
    for c = 1, cols do
      local hue
      if cols <= 1 then
        hue = PCONF.hue_offset
      else
        hue = PCONF.hue_offset + PCONF.hue_range * (c-1) / (cols-1)
      end
      local idx = (r-1)*cols + c
      PALETTE[#PALETTE+1] = {
        color=hsv(hue % 360, row.sat, row.val),
        take_keyword=old_take_kw[idx] or "",
        track_keyword=old_track_kw[idx] or "",
      }
    end
  end
  if PCONF.grey_row then
    local base = #PCONF.rows * cols
    for c = 1, cols do
      local v = cols <= 1 and 0.5 or (1.0 - (c-1)/(cols-1))
      PALETTE[#PALETTE+1] = {
        color=hsv(0, 0, v),
        take_keyword=old_take_kw[base+c] or "",
        track_keyword=old_track_kw[base+c] or "",
      }
    end
  end
end

local function apply_builtin_default_palette()
  PCONF.hue_offset = 0
  PCONF.hue_range = 330
  PCONF.grey_row = false
  PCONF.rows = {
    { sat=0.20, val=0.90 },
    { sat=0.65, val=0.75 },
    { sat=0.90, val=0.55 },
  }
  PALETTE_COLS = 8
  gen_palette()
  for i, color in ipairs(DEFAULT_PALETTE_COLORS) do
    if PALETTE[i] then PALETTE[i].color = color end
  end
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

-- ─── load settings + palette from ExtState (follows main GUI script) ─────────
local function load_pconf()
  local s = reaper.GetExtState(PREF_NS, "pconf_v1")
  if s ~= "" then
    local nums = {}
    for n in (s..","):gmatch("([^,]*),") do nums[#nums+1] = tonumber(n) end
    if #nums >= 4 then
      PCONF.hue_offset = nums[1] or 0
      PCONF.hue_range  = nums[2] or 330
      local rows = {}
      local i = 3
      while i+1 <= #nums do
        rows[#rows+1] = { sat=nums[i], val=nums[i+1] }
        i = i + 2
      end
      if #rows > 0 then PCONF.rows = rows end
    end
  end
  local gr = reaper.GetExtState(PREF_NS, "grey_row")
  if gr ~= "" then PCONF.grey_row = (gr == "1") end
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
end

local function load_palette()
  local raw = reaper.GetExtState(PREF_NS, "palette_v3")
  if raw == "" then
    apply_builtin_default_palette()
    return
  end
  local colors = {}
  local row = 0
  for line in (raw.."\n"):gmatch("(.-)\n") do
    if row == 0 then
      PALETTE_COLS = math.max(1, tonumber(line:match("cols=(%d+)")) or PALETTE_COLS)
    else
      local hx = line:match("^(%x+)\t")
      colors[#colors+1] = tonumber(hx or "0", 16) or 0
    end
    row = row + 1
  end
  gen_palette()
  for i, p in ipairs(PALETTE) do
    p.color = colors[i] or p.color
  end
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

local function apply_item_background_color(item, rrggbb)
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

local function apply_color_to_track(track, rrggbb)
  reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR",
    reaper.ColorToNative((rrggbb>>16)&0xFF,(rrggbb>>8)&0xFF,rrggbb&0xFF)|0x1000000)
end

-- ─── smart-random helpers (mirrors main script) ──────────────────────────────
local function weighted_rgb_distance(c1, c2)
  local r1, g1, b1 = (c1 >> 16) & 0xFF, (c1 >> 8) & 0xFF, c1 & 0xFF
  local r2, g2, b2 = (c2 >> 16) & 0xFF, (c2 >> 8) & 0xFF, c2 & 0xFF
  local dr, dg, db = r1 - r2, g1 - g2, b1 - b2
  return math.sqrt(0.299 * dr * dr + 0.587 * dg * dg + 0.114 * db * db)
end

local function hue_gap_degrees(c1, c2)
  local h1 = select(1, rgb_to_hsv(((c1 >> 16) & 0xFF) / 255, ((c1 >> 8) & 0xFF) / 255, (c1 & 0xFF) / 255))
  local h2 = select(1, rgb_to_hsv(((c2 >> 16) & 0xFF) / 255, ((c2 >> 8) & 0xFF) / 255, (c2 & 0xFF) / 255))
  local d = math.abs(h1 - h2)
  return math.min(d, 360 - d)
end

local function smart_color_distance(c1, c2)
  local rgbd = weighted_rgb_distance(c1, c2)
  local huew = (hue_gap_degrees(c1, c2) / 180) * 255
  return rgbd * 0.65 + huew * 0.35
end

local function is_grayscale_color(c)
  local r = ((c >> 16) & 0xFF) / 255
  local g = ((c >> 8) & 0xFF) / 255
  local b = (c & 0xFF) / 255
  local _, s = rgb_to_hsv(r, g, b)
  return (s or 0) < 0.08
end

local function non_grayscale_palette_indices()
  local t = {}
  for i, p in ipairs(PALETTE) do
    if not is_grayscale_color(p.color) then t[#t+1] = i end
  end
  return t
end

local function shuffled_values(src)
  local t = {}
  for i = 1, #src do t[i] = src[i] end
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- ─── target selection (selected tracks, else selected items; no "all" fallback) ─
local function get_selected_tracks()
  local n = reaper.CountSelectedTracks(0)
  if n == 0 then return nil end
  local tracks = {}
  for i = 0, n - 1 do tracks[#tracks + 1] = reaper.GetSelectedTrack(0, i) end
  return tracks
end

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

local function resolve_targets()
  local has_items = reaper.CountSelectedMediaItems(0) > 0
  local has_tracks = reaper.CountSelectedTracks(0) > 0
  if not has_items and not has_tracks then return nil end
  if has_items then return "items", get_selected_items_row_major() end
  return "tracks", get_selected_tracks()
end

-- ─── main ─────────────────────────────────────────────────────────────────────
math.randomseed(math.floor(reaper.time_precise() * 1000000) % 2147483647)

load_pconf()
load_palette()

local kind, targets = resolve_targets()
if not kind then
  reaper.ShowMessageBox("Select items or tracks first.", "Auto Color Smart Random", 0)
  return
end

if #PALETTE == 0 then
  reaper.ShowMessageBox("Palette is empty.", "Auto Color Smart Random", 0)
  return
end

local candidate_idxs = non_grayscale_palette_indices()
if #candidate_idxs == 0 then
  reaper.ShowMessageBox("Smart Random: no colorful swatches (all grayscale).", "Auto Color Smart Random", 0)
  return
end

local min_dist = 95
local prev1, prev2 = nil, nil

reaper.Undo_BeginBlock()
if kind == "tracks" then
  for _, track in ipairs(targets) do
    local choice_color, best_color, best_score = nil, nil, -1
    local order = shuffled_values(candidate_idxs)
    for _, idx in ipairs(order) do
      local c = PALETTE[idx].color
      local ok1 = (not prev1) or (smart_color_distance(c, prev1) >= min_dist)
      local ok2 = (not prev2) or (smart_color_distance(c, prev2) >= (min_dist * 0.75))
      if ok1 and ok2 then
        choice_color = c
        break
      end
      if prev1 then
        local s = smart_color_distance(c, prev1)
        if s > best_score then best_score = s; best_color = c end
      else
        best_color = c
      end
    end
    choice_color = choice_color or best_color or PALETTE[candidate_idxs[math.random(#candidate_idxs)]].color
    apply_color_to_track(track, choice_color)
    prev2, prev1 = prev1, choice_color
  end
  reaper.Undo_EndBlock("Smart Random Track Color", -1)
  reaper.TrackList_AdjustWindows(false)
else
  for i, item in ipairs(targets) do
    local choice_color, best_color, best_score = nil, nil, -1
    local order = shuffled_values(candidate_idxs)
    for _, idx in ipairs(order) do
      local c = PALETTE[idx].color
      local ok1 = (not prev1) or (smart_color_distance(c, prev1) >= min_dist)
      local ok2 = (not prev2) or (smart_color_distance(c, prev2) >= (min_dist * 0.75))
      if ok1 and ok2 then
        choice_color = c
        break
      end
      if prev1 then
        local s = smart_color_distance(c, prev1)
        if s > best_score then best_score = s; best_color = c end
      else
        best_color = c
      end
    end
    choice_color = choice_color or best_color or PALETTE[candidate_idxs[((i - 1) % #candidate_idxs) + 1]].color
    apply_color_by_mode(item, choice_color)
    prev2, prev1 = prev1, choice_color
  end
  reaper.Undo_EndBlock("Smart Random Color", -1)
end
reaper.UpdateArrange()
