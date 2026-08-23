--[[
@description Auto Color Items by Take Name — Background Daemon
@version 260823.1429
@author hsuanice
@about
  Headless background daemon for hsuanice_Auto Color Items by Take Name.

  - Runs with no window; add to Action List and assign a shortcut or toolbar button.
  - Toggle on/off: running it again stops it (REAPER toggle script behaviour).
  - Reads the same palette/keyword settings saved by the GUI script in real time.
    Changes made in the GUI take effect within the next loop cycle (~30ms).
  - On start, immediately colors all items in the project.
  - While running, re-colors whenever the project changes or settings change.

  Workflow:
    1. Run this daemon to keep colors applied automatically in the background.
    2. Open GUI script to configure palette and keywords (optional; daemon works independently).
    3. The GUI can be closed; the daemon runs independently.

@changelog
  v260823.1429 (Taipei Time)
  - Fix: daemon now runs independently of GUI heartbeat gating (no need to open GUI first).
  - Fix: stale heartbeat values from prior REAPER sessions no longer block daemon processing.
  - Fix: daemon keyword matching now follows GUI's split model (take_keyword for items, track_keyword for tracks).
  - Add: periodic safety recolor pass to avoid missed updates when state-count changes are not emitted.
  - Debug: added runtime logs for startup/recolor diagnostics; default logging is now OFF.

  v260804.1623
  - Add: supports color_mode from GUI (normal/shiny)
  - Add: ShinyColor mode now writes take peak color and applies lighter item background color in daemon auto-coloring
  - Fix: include color_mode in settings fingerprint so daemon reacts immediately to mode changes

  v260403.1810
  - Fix: Daemon now works on REAPER startup without needing to open the GUI script first
  - On init, reads hsuanice_AutoColorItems_state.dat directly and populates ExtState,
    so keywords and palette are available even after reaper-extstate.ini is cleared on restart

  v260324.1912
  - Fix: Daemon no longer slows REAPER on track selection — debounce added (15-frame stable
    window before recolor); GUI settings polled every 10 frames instead of every frame
  - Add: Initial release of headless background daemon
]]

local _, SCRIPT_PATH, sectionID, cmdID = reaper.get_action_context()

local PREF_NS = "hsuanice_AutoColorItems"
local UI_HEARTBEAT_KEY = "ui_heartbeat"
local DEBUG = false

local function log(msg)
  if DEBUG then reaper.ShowConsoleMsg("[AutoColorDaemon] " .. tostring(msg) .. "\n") end
end

-- ─── file-based state bootstrap ───────────────────────────────────────────────
-- On startup, always write the .dat file contents into ExtState so that
-- load_settings() has valid data even when reaper-extstate.ini was cleared.
-- (The GUI script writes the .dat file on every clean exit and on every
--  explicit "Save Preset", making it the most reliable source of truth.)
local state_bootstrap_loaded = false
local STATE_FILE do
  local script_dir = SCRIPT_PATH:match("^(.*[/\\])") or "./"
  STATE_FILE = script_dir .. "../Tools/hsuanice_AutoColorItems_state.dat"
  local f = io.open(STATE_FILE, "r")
  if f then
    state_bootstrap_loaded = true
    local function dec(s) return (s:gsub("\\\\", "\1"):gsub("\\n", "\n"):gsub("\1", "\\")) end
    for line in f:lines() do
      if not line:match("^%s*#") and line ~= "" then
        local key, val = line:match("^([^=]+)=(.*)")
        if key and val then
          reaper.SetExtState(PREF_NS, key, dec(val), true)
        end
      end
    end
    f:close()
  end
end

-- ─── palette state (mirrors GUI script structures) ────────────────────────────
local PCONF = {
  hue_offset = 0,
  hue_range  = 330,
  grey_row   = true,
  rows = {
    { sat=0.20, val=0.90 },
    { sat=0.65, val=0.75 },
    { sat=0.90, val=0.55 },
  }
}
local PALETTE_COLS = 10
local PALETTE = {}

local COLOR_MODE_NORMAL = "normal"
local COLOR_MODE_SHINY  = "shiny"
local color_mode        = COLOR_MODE_NORMAL
local NORMAL_PRIMARY_BG   = "background"
local NORMAL_PRIMARY_PEAK = "peak"
local NORMAL_SECONDARY_MATCH = "match"
local NORMAL_SECONDARY_BLACK = "black"
local NORMAL_SECONDARY_WHITE = "white"
local NORMAL_SECONDARY_TRANSPARENT = "transparent"
local normal_primary_target  = NORMAL_PRIMARY_BG
local normal_secondary_color = NORMAL_SECONDARY_WHITE

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
    if maxc == r then
      h = ((g - b) / d) % 6
    elseif maxc == g then
      h = ((b - r) / d) + 2
    else
      h = ((r - g) / d) + 4
    end
    h = h * 60
  end

  return h, s, v
end

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

-- ─── palette generation (identical to GUI script) ────────────────────────────
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
      local hue = cols <= 1 and PCONF.hue_offset
                             or (PCONF.hue_offset + PCONF.hue_range * (c-1) / (cols-1))
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

-- ─── load settings from ExtState ─────────────────────────────────────────────
local ac_audio = true
local ac_empty = true
local ac_midi  = true

-- Returns a fingerprint string; compare across frames to detect GUI edits.
local function settings_fingerprint()
  return reaper.GetExtState(PREF_NS, "pconf_v1")
      .. reaper.GetExtState(PREF_NS, "grey_row")
      .. reaper.GetExtState(PREF_NS, "palette_v3")
      .. reaper.GetExtState(PREF_NS, "ac_audio")
      .. reaper.GetExtState(PREF_NS, "ac_empty")
  .. reaper.GetExtState(PREF_NS, "ac_midi")
  .. reaper.GetExtState(PREF_NS, "color_mode")
      .. reaper.GetExtState(PREF_NS, "normal_primary_target")
      .. reaper.GetExtState(PREF_NS, "normal_secondary_color")
end

local function load_settings()
  -- pconf
  local s = reaper.GetExtState(PREF_NS, "pconf_v1")
  if s ~= "" then
    local nums = {}
    for n in (s..","):gmatch("([^,]*),") do nums[#nums+1] = tonumber(n) end
    if #nums >= 4 then
      PCONF.hue_offset = nums[1] or 0
      PCONF.hue_range  = nums[2] or 330
      local rows, i = {}, 3
      while i+1 <= #nums do
        rows[#rows+1] = { sat=nums[i], val=nums[i+1] }
        i = i + 2
      end
      if #rows > 0 then PCONF.rows = rows end
    end
  end
  local gr = reaper.GetExtState(PREF_NS, "grey_row")
  if gr ~= "" then PCONF.grey_row = (gr == "1") end

  local function b(key, default)
    local v = reaper.GetExtState(PREF_NS, key)
    return v == "" and default or v == "1"
  end
  ac_audio = b("ac_audio", true)
  ac_empty = b("ac_empty", true)
  ac_midi  = b("ac_midi",  true)
  local cm = reaper.GetExtState(PREF_NS, "color_mode")
  if cm == COLOR_MODE_SHINY or cm == COLOR_MODE_NORMAL then
    color_mode = cm
  else
    color_mode = COLOR_MODE_NORMAL
  end
  local npt = reaper.GetExtState(PREF_NS, "normal_primary_target")
  if npt == NORMAL_PRIMARY_BG or npt == NORMAL_PRIMARY_PEAK then
    normal_primary_target = npt
  else
    normal_primary_target = NORMAL_PRIMARY_BG
  end
  local nsc = reaper.GetExtState(PREF_NS, "normal_secondary_color")
  if nsc == "keep" then nsc = NORMAL_SECONDARY_MATCH end
  if nsc == NORMAL_SECONDARY_MATCH or nsc == NORMAL_SECONDARY_BLACK or nsc == NORMAL_SECONDARY_WHITE or nsc == NORMAL_SECONDARY_TRANSPARENT then
    normal_secondary_color = nsc
  else
    normal_secondary_color = NORMAL_SECONDARY_WHITE
  end

  -- palette_v3
  -- Supports:
  --   cols=N
  --   RRGGBB<TAB>take_keyword
  --   RRGGBB<TAB>take_keyword<TAB>track_keyword   (newer GUI format)
  local raw = reaper.GetExtState(PREF_NS, "palette_v3")
  local colors = {}
  local take_kws = {}
  local track_kws = {}
  local row = 0
  for line in (raw.."\n"):gmatch("(.-)\n") do
    if row == 0 then
      PALETTE_COLS = math.max(1, tonumber(line:match("cols=(%d+)")) or PALETTE_COLS)
    else
      local hx, take_kw, track_kw = line:match("^(%x+)\t(.-)\t(.-)$")
      if not hx then
        hx, take_kw = line:match("^(%x+)\t(.-)$")
        track_kw = ""
      end
      colors[#colors+1] = tonumber(hx or "0", 16) or 0
      take_kws[#take_kws+1] = take_kw or ""
      track_kws[#track_kws+1] = track_kw or ""
    end
    row = row + 1
  end
  gen_palette()
  for i, p in ipairs(PALETTE) do
    if colors[i] and colors[i] > 0 then
      p.color = colors[i]
    end
    p.take_keyword = take_kws[i] or ""
    p.track_keyword = track_kws[i] or ""
    p.keyword = p.take_keyword -- compatibility alias
  end
end

-- ─── coloring logic (identical to GUI script) ─────────────────────────────────
local function apply_item_background_color(item, rrggbb)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR",
    reaper.ColorToNative((rrggbb>>16)&0xFF,(rrggbb>>8)&0xFF,rrggbb&0xFF)|0x1000000)
end

local function clear_item_background_color(item)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)
end

local function apply_item_peak_color_all_takes(item, rrggbb)
  local peak_native = reaper.ColorToNative((rrggbb >> 16) & 0xFF, (rrggbb >> 8) & 0xFF, rrggbb & 0xFF) | 0x1000000
  local take_count = reaper.GetMediaItemNumTakes(item)
  if take_count and take_count > 0 then
    for t = 0, take_count - 1 do
      local take = reaper.GetMediaItemTake(item, t)
      if take then
        reaper.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", peak_native)
      end
    end
  end
end

local function clear_item_peak_color_all_takes(item)
  local take_count = reaper.GetMediaItemNumTakes(item)
  if take_count and take_count > 0 then
    for t = 0, take_count - 1 do
      local take = reaper.GetMediaItemTake(item, t)
      if take then
        reaper.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", 0)
      end
    end
  end
end

local function normal_secondary_rrggbb(primary_rrggbb)
  if normal_secondary_color == NORMAL_SECONDARY_MATCH then return primary_rrggbb end
  if normal_secondary_color == NORMAL_SECONDARY_BLACK then return 0x000000 end
  if normal_secondary_color == NORMAL_SECONDARY_WHITE then return 0xFFFFFF end
  return primary_rrggbb
end

local function apply_normal_secondary_background(item, primary_rrggbb)
  if normal_secondary_color == NORMAL_SECONDARY_TRANSPARENT then
    clear_item_background_color(item)
  else
    apply_item_background_color(item, normal_secondary_rrggbb(primary_rrggbb))
  end
end

local function apply_normal_secondary_peak(item, primary_rrggbb)
  if normal_secondary_color == NORMAL_SECONDARY_TRANSPARENT then
    clear_item_peak_color_all_takes(item)
  else
    apply_item_peak_color_all_takes(item, normal_secondary_rrggbb(primary_rrggbb))
  end
end

local function apply_normal_color_to_item(item, rrggbb)
  if normal_primary_target == NORMAL_PRIMARY_PEAK then
    apply_item_peak_color_all_takes(item, rrggbb)
    apply_normal_secondary_background(item, rrggbb)
  else
    apply_item_background_color(item, rrggbb)
    apply_normal_secondary_peak(item, rrggbb)
  end
end

local function apply_color_to_track(track, rrggbb)
  reaper.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR",
    reaper.ColorToNative((rrggbb>>16)&0xFF,(rrggbb>>8)&0xFF,rrggbb&0xFF)|0x1000000)
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

local function match_take(take_name)
  local lo = (take_name or ""):lower()
  if lo == "" then return nil end
  local best_p, best_len = nil, 0
  for _, p in ipairs(PALETTE) do
    local keyword = p.take_keyword or p.keyword or ""
    if keyword ~= "" then
      for kw in (keyword.."|"):gmatch("([^|]+)|") do
        local kw_trim = kw:match("^%s*(.-)%s*$")
        if kw_trim ~= "" and #kw_trim > best_len and lo:find(kw_trim:lower(), 1, true) then
          best_p, best_len = p, #kw_trim
        end
      end
    end
  end
  return best_p
end

local function match_track(track_name)
  local lo = (track_name or ""):lower()
  if lo == "" then return nil end
  local best_p, best_len = nil, 0
  for _, p in ipairs(PALETTE) do
    local keyword = p.track_keyword or ""
    if keyword ~= "" then
      for kw in (keyword.."|"):gmatch("([^|]+)|") do
        local kw_trim = kw:match("^%s*(.-)%s*$")
        if kw_trim ~= "" and #kw_trim > best_len and lo:find(kw_trim:lower(), 1, true) then
          best_p, best_len = p, #kw_trim
        end
      end
    end
  end
  return best_p
end

local function do_auto_color_tracks()
  local trn = reaper.CountTracks(0)
  if trn == 0 then return 0, 0 end
  local track_hits = 0
  for i = 0, trn - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, tn = reaper.GetTrackName(tr)
    local p = match_track(tn)
    if p then
      apply_color_to_track(tr, p.color)
      track_hits = track_hits + 1
    end
  end
  reaper.TrackList_AdjustWindows(false)
  return trn, track_hits
end

local function do_auto_color()
  local trn, track_hits = do_auto_color_tracks()
  local n = reaper.CountMediaItems(0)
  if n == 0 then return trn, track_hits, 0, 0 end
  local item_hits = 0
  for i = 0, n-1 do
    local item = reaper.GetMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if take == nil then
      -- no take: skip
    elseif reaper.TakeIsMIDI(take) then
      if ac_midi then
        local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local p = match_take(tn)
        if p then
          apply_color_by_mode(item, p.color)
          item_hits = item_hits + 1
        end
      end
    else
      local src = reaper.GetMediaItemTake_Source(take)
      local fn  = reaper.GetMediaSourceFileName(src, "")
      if fn == "" then
        if ac_empty then
          local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          local p = match_take(tn)
          if p then
            apply_color_by_mode(item, p.color)
            item_hits = item_hits + 1
          end
        end
      else
        if ac_audio then
          local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          local p = match_take(tn)
          if p then
            apply_color_by_mode(item, p.color)
            item_hits = item_hits + 1
          end
        end
      end
    end
  end
  reaper.UpdateArrange()
  return trn, track_hits, n, item_hits
end

-- ─── init ─────────────────────────────────────────────────────────────────────
reaper.SetToggleCommandState(sectionID, cmdID, 1)
reaper.RefreshToolbar2(sectionID, cmdID)
reaper.atexit(function()
  reaper.SetToggleCommandState(sectionID, cmdID, 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
end)

load_settings()
-- Clear any residual GUI heartbeat so daemon can start independently.
reaper.SetExtState(PREF_NS, UI_HEARTBEAT_KEY, "0", false)
local last_fingerprint  = settings_fingerprint()
local last_state_count  = reaper.GetProjectStateChangeCount(0)
local itrn, ihit_tr, iitm, ihit_itm = do_auto_color()
log(string.format("start: bootstrap=%s, tracks=%d hit=%d, items=%d hit=%d", tostring(state_bootstrap_loaded), itrn or 0, ihit_tr or 0, iitm or 0, ihit_itm or 0))

-- ─── loop ─────────────────────────────────────────────────────────────────────
-- Debounce: only recolor after the project state has been stable for
-- DEBOUNCE_N frames (~0.5 s).  This prevents do_auto_color from firing
-- on every track-selection click (which also increments state count).
local DEBOUNCE_N           = 15   -- frames of stability required
local FINGERPRINT_INTERVAL = 10   -- check GUI settings every N frames
local FORCE_RECOLOR_INTERVAL = 120 -- safety refresh (~3.6s @ ~30ms defer cadence)
local pending_recolor      = 0
local frame_count          = 0

local function loop()
  frame_count = frame_count + 1

  -- Check for GUI settings changes less frequently
  if frame_count % FINGERPRINT_INTERVAL == 0 then
    local fp = settings_fingerprint()
    if fp ~= last_fingerprint then
      load_settings()
      last_fingerprint  = fp
      pending_recolor   = 0
      local trn, th, itm, ih = do_auto_color()
      log(string.format("recolor: settings changed | tracks=%d hit=%d, items=%d hit=%d", trn or 0, th or 0, itm or 0, ih or 0))
      last_state_count  = reaper.GetProjectStateChangeCount(0)
      reaper.defer(loop)
      return
    end
  end

  -- Debounce project state changes
  local sc = reaper.GetProjectStateChangeCount(0)
  if sc ~= last_state_count then
    last_state_count = sc
    pending_recolor  = DEBOUNCE_N   -- reset countdown on each change
  elseif pending_recolor > 0 then
    pending_recolor = pending_recolor - 1
    if pending_recolor == 0 then
      local trn, th, itm, ih = do_auto_color()
      log(string.format("recolor: state settled | tracks=%d hit=%d, items=%d hit=%d", trn or 0, th or 0, itm or 0, ih or 0))
    end
  end

  -- Safety pass: even without detected state changes, refresh periodically.
  -- This covers edge cases where some edits don't bump state count reliably.
  if frame_count % FORCE_RECOLOR_INTERVAL == 0 then
    local trn, th, itm, ih = do_auto_color()
    log(string.format("recolor: interval | tracks=%d hit=%d, items=%d hit=%d", trn or 0, th or 0, itm or 0, ih or 0))
  end

  reaper.defer(loop)
end

loop()
