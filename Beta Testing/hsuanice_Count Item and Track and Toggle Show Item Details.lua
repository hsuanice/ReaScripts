---@diagnostic disable: undefined-global
--[[
@description GFX - Count Items/Tracks and Toggle Show Item Details
@version 260505.1520
@author hsuanice
@about
  Pro Tools-style selection monitor HUD using native gfx (no ReaImGui).
    Top row    : Items count (left)  +  Tracks count (right)
    Mid rows   : Start / End / Length timecodes  (PT transport style)
    Detail rows: MIDI / Audio / Empty + Channel Count  (toggle with arrow / left-click)
  Right-click: font size (UI scale) / dock / close.
  Window position, dock state, font size, and panel state persist across restarts.
@changelog
  v260505.1520
    - Remove "Follow Transport" option: REAPER's transport primary time
      mode is not exposed by any native lua API (and projtimemode actually
      reflects the ruler / project default, not the transport). Pick the
      matching explicit format (Timecode / Min:Secs / etc.) instead.
  v260505.1506
    - Rename time-format menu entries for clarity:
        Project default (ruler)  → Follow Ruler
        Timecode (h:m:s:f)       → Project Timecode (h:m:s:f)
      "Project Timecode" uses Project Settings → frame rate + start time
      and is fixed regardless of the ruler / grid display (matches Pro Tools).
  v260505.1457
    - Time format is now selectable via right-click menu:
        * Project default (ruler)   — mode -1
        * Timecode (h:m:s:f)        — mode 5
        * Min:Secs                  — mode 0
        * Measures.Beats            — mode 2
        * Seconds                   — mode 3
        * Samples                   — mode 4
      Persisted in TIME_MODE ext state.
  v260505.1451
    - Start / End / Length now follow the project's primary time unit
      (ruler setting, format_timestr_pos mode -1) instead of being locked
      to timecode. Switching the ruler updates the display live.
  v260505.1443
    - Redesign layout to mirror Pro Tools transport selection display:
      * Top row keeps Items / Tracks counts + arrow toggle.
      * New Start / End / Length timecode rows beneath the counts.
      * Detail panel (MIDI / Audio / Empty / Channel Count) still toggles via
        the arrow / left-click.
    - Selection range source: selected items if any → time selection → edit cursor.
    - Timecodes formatted via reaper.format_timestr_pos(t, "", 5) (HH:MM:SS:FF).
    - Auto-resize accounts for the new TC rows; UI scale (font 13/16/20/24)
      reflows everything proportionally.
  v260304.1650
    - Fix: r.atexit(save_state) ensures dock state and position are saved even when
      REAPER is closed without manually closing the script window
    - Fix: save_state() now uses cached vars only (safe when gfx is already gone)
    - Fix: floating position cached every frame so it's accurate at atexit time
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
-- Time format passed to format_timestr_pos:
--   -1 = project default (ruler) | 0 = Min:Secs | 2 = Measures.Beats
--    3 = Seconds | 4 = Samples   | 5 = Timecode (h:m:s:f)
local time_mode    = tonumber(r.GetExtState(EXT_NS, "TIME_MODE"))  or -1
-- Migrate: previous beta default was -2 (Follow Transport), now removed.
if time_mode == -2 then time_mode = -1 end

------------------------------------------------------------
-- Layout constants
------------------------------------------------------------
local SCAN_INTERVAL = 0.10
local PAD   = 10   -- window padding
local LPAD  = 5    -- extra vertical space per line
local FSLOT = 1    -- gfx font slot

------------------------------------------------------------
-- Colors { r, g, b }
------------------------------------------------------------
local CB = { 0.10, 0.10, 0.10 }  -- background
local CT = { 0.87, 0.87, 0.87 }  -- text (counts / values)
local CV = { 0.00, 0.87, 0.00 }  -- timecode value (PT-style green)
local CL = { 0.55, 0.55, 0.55 }  -- timecode labels (Start/End/Length)
local CD = { 0.55, 0.55, 0.55 }  -- dim labels (details)
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
  start_str   = "00:00:00:00",
  end_str     = "00:00:00:00",
  len_str     = "00:00:00:00",
  types       = { midi=0, audio=0, empty=0 },
  channels    = {},
}
local scan_pv, scan_ic, scan_tc           = -1, -1, -1
local scan_cur, scan_ts1, scan_ts2        = -1, -1, -1
local next_scan = 0.0

------------------------------------------------------------
-- Window state
------------------------------------------------------------
local cur_w, cur_h = 0, 0
local prev_cap     = 0
local prev_dock    = dock_state

-- Cached position/dock (updated each frame; safe to read in atexit when gfx is gone)
local cur_x, cur_y = win_x, win_y

------------------------------------------------------------
-- Helpers
------------------------------------------------------------
local function fmt_tc(t)
  return r.format_timestr_pos(t or 0, "", time_mode)
end

-- Selection range: items if any → time selection → edit cursor
local function compute_range()
  local ic = r.CountSelectedMediaItems(0)
  if ic > 0 then
    local s, e = math.huge, -math.huge
    for i = 0, ic - 1 do
      local it = r.GetSelectedMediaItem(0, i)
      local p  = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if p < s then s = p end
      if p + l > e then e = p + l end
    end
    return s, e
  end
  local ts1, ts2 = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts2 > ts1 then return ts1, ts2 end
  local cp = r.GetCursorPosition()
  return cp, cp
end

------------------------------------------------------------
-- Size helpers
------------------------------------------------------------
local function ch_line_count()
  local n = 0
  for _ in pairs(cached.channels) do n = n + 1 end
  return n
end

local function want_h()
  local rows = 1   -- summary row (Items / Tracks)
  rows = rows + 3  -- Start / End / Length
  if show_details then
    rows = rows + 3   -- midi / audio / empty
    rows = rows + 1   -- "Channel Count:" header
    rows = rows + ch_line_count()
  end
  return PAD * 2 + rows * lh()
end

local function want_w()
  setfont()
  local candidates = {
    string.format("Items: %d    Tracks: %d   v", cached.item_count, cached.track_count),
    "Length    " .. cached.len_str,
    "Channel Count:",
    "Stereo: 999",
  }
  local max_w = 160
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
  local s, e = compute_range()
  cached.start_str = fmt_tc(s)
  cached.end_str   = fmt_tc(e)
  cached.len_str   = fmt_tc(e - s)
end

local function scan_full()
  scan_summary()
  local ic    = cached.item_count
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
  cached.types    = types
  cached.channels = chs
end

local function maybe_scan(now)
  local pv  = r.GetProjectStateChangeCount(0) or 0
  local ic  = r.CountSelectedMediaItems(0)
  local tc  = r.CountSelectedTracks(0)
  local cp  = r.GetCursorPosition()
  local ts1, ts2 = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local changed = pv ~= scan_pv or ic ~= scan_ic or tc ~= scan_tc
              or cp ~= scan_cur or ts1 ~= scan_ts1 or ts2 ~= scan_ts2
  if not changed or now < next_scan then return end
  scan_pv,  scan_ic,  scan_tc  = pv, ic, tc
  scan_cur, scan_ts1, scan_ts2 = cp, ts1, ts2
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
-- Save state  (uses only cached vars — safe to call from atexit when gfx is gone)
------------------------------------------------------------
local function save_state()
  r.SetExtState(EXT_NS, "DOCK_STATE",   tostring(dock_state),           true)
  r.SetExtState(EXT_NS, "WIN_X",        tostring(cur_x),                true)
  r.SetExtState(EXT_NS, "WIN_Y",        tostring(cur_y),                true)
  r.SetExtState(EXT_NS, "SHOW_DETAILS", show_details and "1" or "0",    true)
  r.SetExtState(EXT_NS, "FONT_SIZE",    tostring(font_size),            true)
  r.SetExtState(EXT_NS, "TIME_MODE",    tostring(time_mode),            true)
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

  -- ── Summary row: Items (left) | Tracks (right) | arrow (far right)
  local items_str  = string.format("Items: %d",  cached.item_count)
  local tracks_str = string.format("Tracks: %d", cached.track_count)
  local arr        = show_details and "v" or ">"
  local aw         = gfx.measurestr(arr)

  setcol(CT)
  gfx.x, gfx.y = PAD, y
  gfx.drawstr(items_str)

  local tw = gfx.measurestr(tracks_str)
  gfx.x = gfx.w - PAD - aw - 8 - tw
  gfx.y = y
  gfx.drawstr(tracks_str)

  setcol(CA)
  gfx.x = gfx.w - PAD - aw - 2
  gfx.y = y
  gfx.drawstr(arr)

  y = y + h

  -- ── Start / End / Length rows (PT transport style)
  local function trow(label, val)
    setcol(CL)
    gfx.x, gfx.y = PAD, y
    gfx.drawstr(label)
    setcol(CV)
    local vw = gfx.measurestr(val)
    gfx.x = gfx.w - PAD - vw
    gfx.y = y
    gfx.drawstr(val)
    y = y + h
  end

  trow("Start",  cached.start_str)
  trow("End",    cached.end_str)
  trow("Length", cached.len_str)

  if not show_details then return end

  -- ── Detail rows
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
  drow("Audio: ",  cached.types.audio)
  drow("Empty: ",  cached.types.empty)

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
  local function fmark(sz) return font_size == sz and "!" or "" end
  local function tmark(m)  return time_mode == m  and "!" or "" end
  local cd         = gfx.dock(-1)
  local dock_label = cd == 0 and "Dock Window" or "Undock Window"

  local items = {
    tmark(-1) .. "Time: Follow Ruler / Project default",
    tmark( 5) .. "Time: Timecode (h:m:s:f)",
    tmark( 0) .. "Time: Min:Secs",
    tmark( 2) .. "Time: Measures.Beats",
    tmark( 3) .. "Time: Seconds",
    tmark( 4) .. "Time: Samples",
    "",
    fmark(13) .. "Font: Small (13)",
    fmark(16) .. "Font: Medium (16)",
    fmark(20) .. "Font: Large (20)",
    fmark(24) .. "Font: XL (24)",
    "",
    dock_label,
    "Close",
  }
  local menu = ""
  for i, it in ipairs(items) do
    menu = menu .. it
    if i < #items then menu = menu .. "|" end
  end

  local sel = gfx.showmenu(menu)

  -- Time format (separators are NOT counted in the return index)
  local function set_time_mode(m)
    if time_mode ~= m then
      time_mode = m
      scan_pv = -1                 -- force rescan to refresh formatted strings
      cur_w, cur_h = 0, 0          -- new format may need a different window width
    end
  end

  if     sel ==  1 then set_time_mode(-1)
  elseif sel ==  2 then set_time_mode( 5)
  elseif sel ==  3 then set_time_mode( 0)
  elseif sel ==  4 then set_time_mode( 2)
  elseif sel ==  5 then set_time_mode( 3)
  elseif sel ==  6 then set_time_mode( 4)
  elseif sel ==  7 then font_size = 13; cur_w, cur_h = 0, 0
  elseif sel ==  8 then font_size = 16; cur_w, cur_h = 0, 0
  elseif sel ==  9 then font_size = 20; cur_w, cur_h = 0, 0
  elseif sel == 10 then font_size = 24; cur_w, cur_h = 0, 0
  elseif sel == 11 then
    if cd == 0 then gfx.dock(1) else gfx.dock(0) end
  elseif sel == 12 then return true
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
  gfx.update()

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

  -- Update cached position and dock state every frame
  local cd = gfx.dock(-1)
  if cd == 0 then
    cur_x, cur_y = gfx.clienttoscreen(0, 0)
  end
  if cd ~= prev_dock then
    if cd == 0 then cur_w, cur_h = 0, 0 end
    prev_dock  = cd
    dock_state = cd
  end

  r.defer(loop)
end

------------------------------------------------------------
-- Init
------------------------------------------------------------
local init_h = PAD * 2 + 4 * lh()  -- summary + start/end/length
gfx.init("Selection Monitor", math.max(220, font_size * 16), init_h, dock_state, win_x, win_y)
r.atexit(save_state)
r.defer(loop)
