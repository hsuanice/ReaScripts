--[[
@description Auto Color Items by Take Name — Background Daemon
@version 260324.1912
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
    1. Open GUI script to configure palette and keywords.
    2. Run this daemon to keep colors applied automatically in the background.
    3. The GUI can be closed; the daemon runs independently.
]]

local _, _, sectionID, cmdID = reaper.get_action_context()

local PREF_NS = "hsuanice_AutoColorItems"

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

-- ─── palette generation (identical to GUI script) ────────────────────────────
local function gen_palette()
  local old_kw = {}
  for i, p in ipairs(PALETTE) do old_kw[i] = p.keyword end
  while #PALETTE > 0 do table.remove(PALETTE) end
  local cols = PALETTE_COLS
  for r = 1, #PCONF.rows do
    local row = PCONF.rows[r]
    for c = 1, cols do
      local hue = cols <= 1 and PCONF.hue_offset
                             or (PCONF.hue_offset + PCONF.hue_range * (c-1) / (cols-1))
      local idx = (r-1)*cols + c
      PALETTE[#PALETTE+1] = { color=hsv(hue % 360, row.sat, row.val), keyword=old_kw[idx] or "" }
    end
  end
  if PCONF.grey_row then
    local base = #PCONF.rows * cols
    for c = 1, cols do
      local v = cols <= 1 and 0.5 or (1.0 - (c-1)/(cols-1))
      PALETTE[#PALETTE+1] = { color=hsv(0, 0, v), keyword=old_kw[base+c] or "" }
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

  -- palette_v3
  local raw = reaper.GetExtState(PREF_NS, "palette_v3")
  local kws = {}
  local row = 0
  for line in (raw.."\n"):gmatch("(.-)\n") do
    if row == 0 then
      PALETTE_COLS = math.max(1, tonumber(line:match("cols=(%d+)")) or PALETTE_COLS)
    else
      local _, kw = line:match("^(%x+)\t(.-)$")
      kws[#kws+1] = kw or ""
    end
    row = row + 1
  end
  gen_palette()
  for i, p in ipairs(PALETTE) do p.keyword = kws[i] or "" end
end

-- ─── coloring logic (identical to GUI script) ─────────────────────────────────
local function apply_color_to_item(item, rrggbb)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR",
    reaper.ColorToNative((rrggbb>>16)&0xFF,(rrggbb>>8)&0xFF,rrggbb&0xFF)|0x1000000)
end

local function match_take(take_name)
  local lo = (take_name or ""):lower()
  if lo == "" then return nil end
  local best_p, best_len = nil, 0
  for _, p in ipairs(PALETTE) do
    if p.keyword ~= "" then
      for kw in (p.keyword.."|"):gmatch("([^|]+)|") do
        kw = kw:match("^%s*(.-)%s*$")
        if kw ~= "" and #kw > best_len and lo:find(kw:lower(), 1, true) then
          best_p, best_len = p, #kw
        end
      end
    end
  end
  return best_p
end

local function do_auto_color()
  local n = reaper.CountMediaItems(0)
  if n == 0 then return end
  for i = 0, n-1 do
    local item = reaper.GetMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if take == nil then
      -- no take: skip
    elseif reaper.TakeIsMIDI(take) then
      if ac_midi then
        local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local p = match_take(tn)
        if p then apply_color_to_item(item, p.color) end
      end
    else
      local src = reaper.GetMediaItemTake_Source(take)
      local fn  = reaper.GetMediaSourceFileName(src, "")
      if fn == "" then
        if ac_empty then
          local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          local p = match_take(tn)
          if p then apply_color_to_item(item, p.color) end
        end
      else
        if ac_audio then
          local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          local p = match_take(tn)
          if p then apply_color_to_item(item, p.color) end
        end
      end
    end
  end
  reaper.UpdateArrange()
end

-- ─── init ─────────────────────────────────────────────────────────────────────
reaper.SetToggleCommandState(sectionID, cmdID, 1)
reaper.RefreshToolbar2(sectionID, cmdID)
reaper.atexit(function()
  reaper.SetToggleCommandState(sectionID, cmdID, 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
end)

load_settings()
local last_fingerprint  = settings_fingerprint()
local last_state_count  = reaper.GetProjectStateChangeCount(0)
do_auto_color()

-- ─── loop ─────────────────────────────────────────────────────────────────────
-- Debounce: only recolor after the project state has been stable for
-- DEBOUNCE_N frames (~0.5 s).  This prevents do_auto_color from firing
-- on every track-selection click (which also increments state count).
local DEBOUNCE_N           = 15   -- frames of stability required
local FINGERPRINT_INTERVAL = 10   -- check GUI settings every N frames
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
      do_auto_color()
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
      do_auto_color()
    end
  end

  reaper.defer(loop)
end

loop()
