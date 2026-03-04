---@diagnostic disable: undefined-global
--[[
@description GFX - Count Items/Tracks and Toggle Show Item Details
@version 260304.1530
@author hsuanice
@about
  Selection monitor HUD using native gfx (no ReaImGui required).
  Left-click: toggle detail panel
  Right-click: font size / dock / close
  Supports docking; remembers position, dock state, font size, panel state.
@changelog
  v260304.1530
    - Rewritten from ReaImGui → native gfx (no ReaImGui dependency)
    - Persistent window position, dock state, font size, panel state across restarts
    - Right-click menu: font size (S/M/L/XL), dock toggle, close
    - Left-click anywhere: toggle detail panel
    - Fix: ensure_size() skips when docked (prevents docker interference)
    - Fix: detect undock-by-drag and trigger resize automatically
  v0.3.1 (2025-09-14)
    - Fix: Guarded Begin/End pairing during docking/undocking and project switching
    - Fix: Theme push/pop balanced, preventing "PushStyleColor/PopStyleColor Mismatch" assertions
  v0.3.0 (2025-09-14)
    - New: XR-style GUI with shared color theme + 16pt font (warn once if theme lib missing)
    - Keep: Same counting logic and throttled details scanning as prior version
    - Fix: Always End() after Begin(), mirroring stability guard in 0.2.0.1
  v0.2.0.1 (2025-09-13)
    - Fix: Always call ImGui_End() after ImGui_Begin(), regardless of visible flag
--]]

local r      = reaper
local EXT_NS = "hsuanice_CountItems"

------------------------------------------------------------
-- Persistent settings
------------------------------------------------------------
local show_details = r.GetExtState(EXT_NS, "SHOW_DETAILS") == "1"
local font_size    = tonumber(r.GetExtState(EXT_NS, "FONT_SIZE"))  or 16
local win_x        = tonumber(r.GetExtState(EXT_NS, "WIN_X"))      or 200
local win_y        = tonumber(r.GetExtState(EXT_NS, "WIN_Y"))      or 200
local dock_state   = tonumber(r.GetExtState(EXT_NS, "DOCK_STATE")) or 0

------------------------------------------------------------
-- Layout constants
------------------------------------------------------------
local SCAN_INTERVAL = 0.15
local PAD   = 10   -- window padding
local LPAD  = 5    -- extra vertical space per line
local FSLOT = 1    -- gfx font slot

------------------------------------------------------------
-- Colors { r, g, b }
------------------------------------------------------------
local CB = { 0.13, 0.13, 0.13 }  -- background
local CT = { 0.87, 0.87, 0.87 }  -- text
local CD = { 0.55, 0.55, 0.55 }  -- dim labels
local CH = { 1.00, 1.00, 1.00 }  -- section header
local CA = { 0.60, 0.80, 1.00 }  -- arrow accent

local function setcol(c) gfx.set(c[1], c[2], c[3], 1) end
local function setfont() gfx.setfont(FSLOT, "Arial", font_size) end
local function lh()      return font_size + LPAD end

------------------------------------------------------------
-- Scan cache
------------------------------------------------------------
local cached = {
  item_count  = 0,
  track_count = 0,
  types    = { midi=0, audio=0, empty=0 },
  channels = {},
}
local scan_pv, scan_ic, scan_tc = -1, -1, -1
local next_scan = 0.0

------------------------------------------------------------
-- Window state
------------------------------------------------------------
local cur_w, cur_h = 0, 0
local prev_cap     = 0
local prev_dock    = dock_state  -- track dock state changes

------------------------------------------------------------
-- Size helpers
------------------------------------------------------------
local function ch_line_count()
  local n = 0
  for _ in pairs(cached.channels) do n = n + 1 end
  return n
end

local function want_h()
  local rows = 1  -- summary row
  if show_details then
    rows = rows + 3  -- midi / audio / empty
    rows = rows + 1  -- "Channel Count:" header
    rows = rows + ch_line_count()
  end
  return PAD * 2 + rows * lh()
end

local function want_w()
  setfont()
  local candidates = {
    string.format("Items: %d    Tracks: %d  v", cached.item_count, cached.track_count),
    "Channel Count:",
    "Stereo: 999",
    "Audio: 999",
  }
  local max_w = 120
  for _, s in ipairs(candidates) do
    local w = gfx.measurestr(s)
    if w > max_w then max_w = w end
  end
  return PAD * 2 + max_w
end

------------------------------------------------------------
-- Scanners
------------------------------------------------------------
local function scan_summary()
  cached.item_count  = r.CountSelectedMediaItems(0)
  cached.track_count = r.CountSelectedTracks(0)
end

local function scan_full()
  local ic    = r.CountSelectedMediaItems(0)
  local tc    = r.CountSelectedTracks(0)
  local types = { midi=0, audio=0, empty=0 }
  local chs   = {}
  for i = 0, ic - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local take = r.GetActiveTake(item)
    if not take then
      types.empty = types.empty + 1
    else
      local src = r.GetMediaItemTake_Source(take)
      local st  = r.GetMediaSourceType(src, "")
      if st == "MIDI" or st == "REX" then
        types.midi  = types.midi  + 1
      else
        types.audio = types.audio + 1
      end
      local ch = r.GetMediaSourceNumChannels(src) or 0
      if ch > 0 then chs[ch] = (chs[ch] or 0) + 1 end
    end
  end
  cached.item_count  = ic
  cached.track_count = tc
  cached.types       = types
  cached.channels    = chs
end

local function maybe_scan(now)
  local pv = r.GetProjectStateChangeCount(0) or 0
  local ic = r.CountSelectedMediaItems(0)
  local tc = r.CountSelectedTracks(0)
  local changed = pv ~= scan_pv or ic ~= scan_ic or tc ~= scan_tc
  if not changed or now < next_scan then return end
  scan_pv   = pv
  scan_ic   = ic
  scan_tc   = tc
  next_scan = now + SCAN_INTERVAL
  if show_details then scan_full() else scan_summary() end
end

------------------------------------------------------------
-- Window resize  (only when floating; docker manages its own size)
------------------------------------------------------------
local function ensure_size()
  if gfx.dock(-1) ~= 0 then return end  -- skip when docked
  local wh = want_h()
  local ww = want_w()
  if ww == cur_w and wh == cur_h then return end
  cur_w, cur_h = ww, wh
  local cx, cy = gfx.clienttoscreen(0, 0)
  gfx.init("Selection Monitor", cur_w, cur_h, 0, cx, cy)
end

------------------------------------------------------------
-- Save state
------------------------------------------------------------
local function save_state()
  local cd = gfx.dock(-1)
  if cd == 0 then
    local x, y = gfx.clienttoscreen(0, 0)
    r.SetExtState(EXT_NS, "WIN_X", tostring(x), true)
    r.SetExtState(EXT_NS, "WIN_Y", tostring(y), true)
  end
  r.SetExtState(EXT_NS, "DOCK_STATE",   tostring(cd),                true)
  r.SetExtState(EXT_NS, "SHOW_DETAILS", show_details and "1" or "0", true)
  r.SetExtState(EXT_NS, "FONT_SIZE",    tostring(font_size),         true)
end

------------------------------------------------------------
-- Draw
------------------------------------------------------------
local function draw()
  setfont()

  -- Background
  setcol(CB)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local y = PAD
  local h = lh()

  -- Summary row
  local sum = string.format("Items: %d    Tracks: %d", cached.item_count, cached.track_count)
  local arr = show_details and "v" or ">"
  local aw  = gfx.measurestr(arr)

  setcol(CT)
  gfx.x, gfx.y = PAD, y
  gfx.drawstr(sum)

  setcol(CA)
  gfx.x = gfx.w - PAD - aw - 2
  gfx.y = y
  gfx.drawstr(arr)

  y = y + h
  if not show_details then return end

  -- Detail rows helper
  local function drow(label, val, lc, vc)
    setcol(lc or CD)
    gfx.x, gfx.y = PAD, y
    gfx.drawstr(label)
    setcol(vc or CT)
    gfx.x = PAD + gfx.measurestr(label)
    gfx.y = y
    gfx.drawstr(tostring(val))
    y = y + h
  end

  drow("MIDI:   ", cached.types.midi)
  drow("Audio: ", cached.types.audio)
  drow("Empty: ", cached.types.empty)

  setcol(CH)
  gfx.x, gfx.y = PAD, y
  gfx.drawstr("Channel Count:")
  y = y + h

  local chl = {}
  for ch, cnt in pairs(cached.channels) do
    chl[#chl + 1] = { ch=ch, cnt=cnt }
  end
  table.sort(chl, function(a, b) return a.ch < b.ch end)
  for _, e in ipairs(chl) do
    local lbl = e.ch == 1 and "Mono" or e.ch == 2 and "Stereo" or (e.ch .. "-Ch")
    drow(lbl .. ": ", e.cnt)
  end
end

------------------------------------------------------------
-- Right-click context menu  (returns true = close requested)
------------------------------------------------------------
local function do_menu()
  local function mk(lbl, sz)
    return (font_size == sz and "!" or "") .. lbl
  end
  local cd         = gfx.dock(-1)
  local dock_label = cd == 0 and "Dock Window" or "Undock Window"
  local menu = mk("Font: Small (13)", 13)  .. "|" ..
               mk("Font: Medium (16)", 16) .. "|" ..
               mk("Font: Large (20)", 20)  .. "|" ..
               mk("Font: XL (24)", 24)     .. "|" ..
               dock_label                  .. "|" ..
               "Close"
  local sel = gfx.showmenu(menu)
  if     sel == 1 then font_size = 13; cur_w, cur_h = 0, 0
  elseif sel == 2 then font_size = 16; cur_w, cur_h = 0, 0
  elseif sel == 3 then font_size = 20; cur_w, cur_h = 0, 0
  elseif sel == 4 then font_size = 24; cur_w, cur_h = 0, 0
  elseif sel == 5 then
    if cd == 0 then gfx.dock(1) else gfx.dock(0) end
  elseif sel == 6 then return true
  end
  return false
end

------------------------------------------------------------
-- Main loop
------------------------------------------------------------
local function loop()
  local now = r.time_precise()
  maybe_scan(now)
  ensure_size()
  draw()

  local cap  = gfx.mouse_cap
  local char = gfx.getchar()

  -- Window closed or Escape
  if char == -1 or char == 27 then
    save_state()
    gfx.quit()
    return
  end

  -- Right-click (bit 2) on press → menu
  if cap & 2 ~= 0 and prev_cap & 2 == 0 then
    if do_menu() then
      save_state()
      gfx.quit()
      return
    end
  end

  -- Left-click (bit 1) on press → toggle detail panel
  if cap & 1 ~= 0 and prev_cap & 1 == 0 then
    show_details = not show_details
    cur_w, cur_h = 0, 0          -- force resize
    if show_details then scan_ic = -1 end  -- force full rescan
  end

  prev_cap = cap

  -- Track dock state; if user dragged window out of docker, force resize
  local cd = gfx.dock(-1)
  if cd ~= prev_dock then
    if cd == 0 then cur_w, cur_h = 0, 0 end  -- just undocked → resize to content
    prev_dock  = cd
    dock_state = cd
  end

  r.defer(loop)
end

------------------------------------------------------------
-- Init
------------------------------------------------------------
local init_h = PAD * 2 + lh()
gfx.init("Selection Monitor", math.max(200, font_size * 16), init_h, dock_state, win_x, win_y)
r.defer(loop)
