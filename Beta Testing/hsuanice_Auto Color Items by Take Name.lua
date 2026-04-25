--[[
@description Auto Color Items by Take Name
@version 260425.1857
@author hsuanice
@about
  Config-driven color palette with keyword rules — colors items by take name.

  Palette is generated from Hue + per-row Saturation/Value settings (like rodilab's Color palette).
  Right-click any swatch → Edit Keyword / Clear Keyword
  Left-click a swatch  → apply that color to selected items
  Auto Color mode colors all items automatically on project changes

  No external dependencies — REAPER built-in GFX library.

@changelog
  v260425.1857
  - Fix: Export Keywords failed with "Could not write to: 1" — JS_Dialog_BrowseForSaveFile returns (retval, fileName); only the retval (1) was being captured as the path. Now captures both return values correctly.

  v260325.1752
  - Add: file-based state persistence — all presets, keywords, and prefs saved to hsuanice Scripts/Tools/hsuanice_AutoColorItems_state.dat on script exit and on every explicit "Save Preset"
  - On startup: file is loaded first so ExtState is repopulated even if reaper-extstate.ini was lost across REAPER restarts

  v260325.1647
  - Fix: startup no longer overwrites palette_v3 keywords with (possibly older) saved preset — load_preset() now only fires as fallback when palette_v3 has no keywords at all
  - Add: Export / Import buttons in List View footer — tab-separated text file (hex_color TAB keyword, one line per palette entry)
  - Export uses native macOS/Windows save dialog via js_ReaScriptAPI (JS_Dialog_BrowseForSaveFile); falls back to text-input if extension not installed
  - Import/Export default location is the REAPER session (.rpp) folder, not the media recording folder

  v260325.1620
  - Fix: add atexit handler to flush palette + pconf to ExtState when script exits (guards against data lost on normal close without prior save_pconf trigger)
  - Fix: save_pconf() called immediately on startup (so last_preset is always current after init)
  - Fix: clicking Default preset now immediately persists last_preset = "Default" to prevent stale restore on next open

  v260325.1605
  - Fix: saved preset now reliably restored on script reopen — startup now calls load_preset() directly instead of relying on palette_v3 (which could become stale)
  - Fix: saving a preset (Save Preset button) now also persists last_preset so it survives reopen even without any other settings change

  v260324.1912
  - Fix: Daemon no longer slows REAPER on track selection — debounce added (15-frame stable window before recolor); GUI settings polled every 10 frames instead of every frame
  - Add: Audio / Empty / MIDI item-type filter checkboxes always visible below toolbar (not gated on Auto Color)
  - Fix: Auto Color checkbox restored to toolbar
  - Fix: Empty items (audio take with no source file) correctly skipped when Empty is unchecked

  v260324.1800
  - Add: Collapse button (▾/▴) in toolbar — shrinks window to a single bar for unobtrusive background use; state persisted
  - Add: Background Daemon script (hsuanice_Auto Color Daemon.lua) — headless, no window, reads GUI settings in real time; toggle state (on/off checkmark) shown in Action List and toolbar buttons via SetToggleCommandState

  v260324.1434
  - Fix: last active preset now correctly restored on script reopen (was a Lua scoping bug — current_preset declared after save/load_pconf, so they accessed separate globals)
  - Fix: CJK characters in color swatches now vertically centered (was offset low due to ASCII-only line height measurement)
  - Add: "Preview chars" setting in Settings panel to control how many characters show per keyword segment in Color View (range 1–9, persisted)
  - Change: Auto Update now defaults to ON at startup
  - Change: Auto Color always starts OFF at startup (prevents accidental coloring before user is ready)

  v260324.1407
  - Fix: Chinese/CJK characters in color swatches now render correctly (was garbled due to byte-level sub)
  - Change: color swatch now shows first 3 characters of each keyword segment (was 1)

  v260324.1349
  - Fix: mouse wheel scrolling now works in List View (was consumed by color grid before reaching list)
  - Add: font size control in Settings panel (Font − / +, range 8–24pt, persisted)

  v260324.1340
  - Fix: Paste Color button now correctly previews the copied color (was dividing by 255 twice)
  - Add: Paste Color button — applies copied color to all selected items; button background shows the copied color
  - Add: List View — toggle between ⊞ Colors (palette grid) and ≡ List (scrollable keyword editor)
  - List View: each row shows color swatch, hex code, and keyword; left-click applies, right-click edits
  - Fix: default window width widened to 620px to prevent toolbar button overlap

  v260324.1225
  - Fix: Preset panel open/closed state now saved across sessions (was always resetting to closed on restart)
  - Add: Right-click preset → Rename option (in addition to existing Delete)

  v260324.0451
  - Add: Preset panel — save/load/delete named presets; all presets stored in ExtState
  - Add: Built-in "Default" preset that clears all keywords
  - Add: Preset name + save status (● clean / * dirty) displayed in toolbar
  - Add: Auto Update checkbox — auto-saves to current preset on any change
  - Add: Confirm dialog before deleting a preset (right-click)
  - Add: Grey row toggle (white → black grayscale) in Settings panel
  - Add: Settings and Presets panels auto-resize window; palette area never compressed
  - Fix: Window size and position now remembered across sessions
  - Fix: Active buttons (Settings, Presets) show dark background + green underline, white text
  - Fix: Keyword matching uses longest-match-wins — "NAN" beats "NA"
  - Fix: Cells always show at full brightness regardless of keyword assignment
  - Remove: "Apply to Selected" button
  - Change: "Clear Selected" renamed to "Remove Color" (removes custom color from selected items)
  v260324.0403
  - Redesign: config-driven palette generator (Hue offset, Span, Sat/Val per row)
  - Add: interactive sliders for all palette parameters, live preview
  - Add: Settings panel (toggle with ⚙ button)
  - Remove: manual Add Color / Generate Gradient — palette fully driven by config
  - Remove: color labels — cells show keyword only
  - Simplify: right-click popup → Edit Keyword / Clear Keyword
  v260324.1700
  - Add: dynamic palette — add/remove/edit individual swatches
  - Add: Generate Gradient, Columns +/−, right-click context popup
  v260324.1600
  - Redesign: palette-first UX
  v260324.1500
  - Rewrite: GFX library replaces ReaImGui
]]

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

-- ─── palette config ───────────────────────────────────────────────────────────
-- hue_offset: 0-360 — first column hue
-- hue_range:  10-360 — total degrees spanned across columns
-- rows: array of {sat, val}  (0.0–1.0 each), one entry per row
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

-- PALETTE: { color=0xRRGGBB, keyword="" }  — regenerated from PCONF
local PALETTE = {}

-- ─── color helpers ────────────────────────────────────────────────────────────
local function cr(c) return ((c>>16)&0xFF)/255 end
local function cg(c) return ((c>> 8)&0xFF)/255 end
local function cb(c) return ( c     &0xFF)/255 end
local function lum(c) return cr(c)*.299+cg(c)*.587+cb(c)*.114 end

-- Returns first n Unicode characters from a UTF-8 string
local function utf8_take(s, n)
  local result = ""
  local i = 1
  for _ = 1, n do
    if i > #s then break end
    local b = s:byte(i)
    local len
    if     b < 0x80 then len = 1
    elseif b < 0xE0 then len = 2
    elseif b < 0xF0 then len = 3
    else                  len = 4
    end
    result = result .. s:sub(i, i + len - 1)
    i = i + len
  end
  return result
end

local function apply_color_to_item(item, rrggbb)
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR",
    reaper.ColorToNative((rrggbb>>16)&0xFF,(rrggbb>>8)&0xFF,rrggbb&0xFF)|0x1000000)
end

-- ─── palette generation ───────────────────────────────────────────────────────
local function gen_palette()
  local old_kw = {}
  for i, p in ipairs(PALETTE) do old_kw[i] = p.keyword end
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
      local color = hsv(hue % 360, row.sat, row.val)
      local idx = (r-1)*cols + c
      PALETTE[#PALETTE+1] = { color=color, keyword=old_kw[idx] or "" }
    end
  end
  -- grey row: white → black
  if PCONF.grey_row then
    local base = #PCONF.rows * cols
    for c = 1, cols do
      local v = cols <= 1 and 0.5 or (1.0 - (c-1)/(cols-1))
      PALETTE[#PALETTE+1] = { color=hsv(0, 0, v), keyword=old_kw[base+c] or "" }
    end
  end
end

-- ─── script path (used for export/import default location) ───────────────────
local _, SCRIPT_PATH = reaper.get_action_context()
local SCRIPT_DIR     = SCRIPT_PATH:match("^(.*[/\\])") or "./"

-- ─── state ────────────────────────────────────────────────────────────────────
local PREF_NS            = "hsuanice_AutoColorItems"
local auto_color_enabled = false
local ac_audio           = true   -- color audio items
local ac_empty           = true   -- color empty items (no takes)
local ac_midi            = true   -- color MIDI items
local last_state_count   = -1
local status_msg         = ""
local status_until       = 0
local show_settings      = false
local show_presets       = false
local collapsed          = false    -- true = window shrunk to toolbar-only bar
local view_mode          = "color"  -- "color" or "list"
local current_preset     = nil      -- name of loaded preset, nil = unsaved
local preset_dirty       = false    -- true when state differs from loaded preset
local list_scroll        = 0
local list_sb_drag       = false    -- true while dragging the list scrollbar thumb
local font_size          = 12       -- base font size (pt); small font = font_size - 2
local font_dirty         = true     -- force font re-init when true
local swatch_chars       = 3        -- number of UTF-8 chars shown per keyword segment in Color View

-- ─── persistence ─────────────────────────────────────────────────────────────
-- palette_v3: line 0 = "cols=N"
--             lines 1+ = "RRGGBB\tkeyword"

local function save_palette()
  local lines = { "cols=" .. PALETTE_COLS }
  for _, p in ipairs(PALETTE) do
    lines[#lines+1] = string.format("%06X\t%s", p.color & 0xFFFFFF, p.keyword or "")
  end
  reaper.SetExtState(PREF_NS, "palette_v3", table.concat(lines, "\n"), true)
end

local function save_pconf()
  local parts = { string.format("%.2f", PCONF.hue_offset),
                  string.format("%.2f", PCONF.hue_range) }
  for _, row in ipairs(PCONF.rows) do
    parts[#parts+1] = string.format("%.4f", row.sat)
    parts[#parts+1] = string.format("%.4f", row.val)
  end
  reaper.SetExtState(PREF_NS, "pconf_v1", table.concat(parts, ","), true)
  reaper.SetExtState(PREF_NS, "grey_row",     PCONF.grey_row and "1" or "0", true)
  reaper.SetExtState(PREF_NS, "show_settings", show_settings and "1" or "0", true)
  reaper.SetExtState(PREF_NS, "show_presets",  show_presets  and "1" or "0", true)
  reaper.SetExtState(PREF_NS, "view_mode",     view_mode,                    true)
  reaper.SetExtState(PREF_NS, "font_size",     tostring(font_size),          true)
  reaper.SetExtState(PREF_NS, "swatch_chars",  tostring(swatch_chars),       true)
  reaper.SetExtState(PREF_NS, "last_preset",   current_preset or "",         true)
  reaper.SetExtState(PREF_NS, "collapsed",     collapsed and "1" or "0",     true)
end

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
  show_settings = reaper.GetExtState(PREF_NS, "show_settings") == "1"
  show_presets  = reaper.GetExtState(PREF_NS, "show_presets")  == "1"
  local vm = reaper.GetExtState(PREF_NS, "view_mode")
  if vm == "list" then view_mode = "list" end
  local fs = tonumber(reaper.GetExtState(PREF_NS, "font_size"))
  if fs and fs >= 8 and fs <= 24 then font_size = fs end
  local sc = tonumber(reaper.GetExtState(PREF_NS, "swatch_chars"))
  if sc and sc >= 1 and sc <= 9 then swatch_chars = sc end
  local lp = reaper.GetExtState(PREF_NS, "last_preset")
  if lp ~= "" then current_preset = lp; preset_dirty = false end
  collapsed = reaper.GetExtState(PREF_NS, "collapsed") == "1"
end

local function load_palette()
  local raw = reaper.GetExtState(PREF_NS, "palette_v3")
  if raw == "" then
    -- try migrating keywords from v2 (has label field)
    local v2 = reaper.GetExtState(PREF_NS, "palette_v2")
    if v2 ~= "" then
      local kws, row = {}, 0
      for line in (v2.."\n"):gmatch("(.-)\n") do
        if row > 0 then
          local _, _, kw = line:match("^(%x+)\t(.-)\t(.-)$")
          kws[#kws+1] = kw or ""
        end
        row = row + 1
      end
      gen_palette()
      for i, p in ipairs(PALETTE) do p.keyword = kws[i] or "" end
    else
      gen_palette()
    end
    return
  end
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

local function save_auto_pref()
  reaper.SetExtState(PREF_NS, "auto_color", auto_color_enabled and "1" or "0", true)
  reaper.SetExtState(PREF_NS, "ac_audio",   ac_audio and "1" or "0",           true)
  reaper.SetExtState(PREF_NS, "ac_empty",   ac_empty and "1" or "0",           true)
  reaper.SetExtState(PREF_NS, "ac_midi",    ac_midi  and "1" or "0",           true)
end
local function load_auto_pref()
  -- auto_color_enabled intentionally not restored: always starts OFF so the
  -- user can review before coloring begins
  local function b(key, default)
    local v = reaper.GetExtState(PREF_NS, key)
    return v == "" and default or v == "1"
  end
  ac_audio = b("ac_audio", true)
  ac_empty = b("ac_empty", true)
  ac_midi  = b("ac_midi",  true)
end

local function set_status(msg)
  status_msg   = msg
  status_until = reaper.time_precise() + 3.5
end

-- ─── matching ─────────────────────────────────────────────────────────────────
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

-- ─── core operations ─────────────────────────────────────────────────────────
local function do_auto_color()
  local n = reaper.CountMediaItems(0)
  if n == 0 then return end
  for i = 0, n-1 do
    local item = reaper.GetMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if take == nil then
      -- no take at all: skip (cannot keyword-match)
    elseif reaper.TakeIsMIDI(take) then
      if ac_midi then
        local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        local p = match_take(tn)
        if p then apply_color_to_item(item, p.color) end
      end
    else
      -- audio take: check whether source has an actual file
      local src = reaper.GetMediaItemTake_Source(take)
      local fn  = reaper.GetMediaSourceFileName(src, "")
      if fn == "" then
        -- empty audio source (no media file): controlled by ac_empty
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


local copied_color = nil  -- 0xRRGGBB, set by Copy Color

local function do_copy_color()
  if reaper.CountSelectedMediaItems(0) == 0 then set_status("No items selected"); return end
  local item   = reaper.GetSelectedMediaItem(0, 0)
  local native = reaper.GetDisplayedMediaItemColor(item)
  local r, g, b = reaper.ColorFromNative(native)
  r, g, b = math.floor(r), math.floor(g), math.floor(b)
  copied_color = r*65536 + g*256 + b
  set_status(string.format("Copied: #%02X%02X%02X", r, g, b))
end

local function do_paste_color()
  if not copied_color then set_status("Nothing copied"); return end
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then set_status("No items selected"); return end
  reaper.Undo_BeginBlock()
  for i = 0, n-1 do
    apply_color_to_item(reaper.GetSelectedMediaItem(0, i), copied_color)
  end
  reaper.Undo_EndBlock("Paste Item Color", -1)
  reaper.UpdateArrange()
  set_status(string.format("Pasted color to %d item(s)", n))
end

local function do_clear_selected()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then set_status("No items selected"); return end
  reaper.Undo_BeginBlock()
  for i = 0, n-1 do
    reaper.SetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0,i),"I_CUSTOMCOLOR",0)
  end
  reaper.Undo_EndBlock("Clear Item Colors", -1)
  reaper.UpdateArrange()
  set_status(string.format("Cleared %d item(s)", n))
end

-- ─── GFX init ─────────────────────────────────────────────────────────────────
local MARGIN        = 8
local BAR_H         = 24
local AC_BAR_H      = 20   -- height of the item-type filter sub-bar below main toolbar
local LIST_FOOTER_H = 24   -- export/import toolbar below list view

-- base_win_w/h = palette-only window size; base_win_x/y = screen position
local base_win_w = 620
local base_win_h = 300
local base_win_x = -1   -- -1 = let OS decide on first run
local base_win_y = -1
local prog_resize = 0   -- frames to suppress resize/move detection after gfx.init calls

-- On macOS, gfx.clienttoscreen(0,0) returns Y measured from screen bottom (macOS native),
-- but gfx.init ypos positions the window bottom in that same system.
-- So ypos_for_init = saved_y - window_height.
local is_mac = reaper.GetOS():find("OSX") ~= nil

local function gfx_init(w, h)
  if base_win_x >= 0 then
    local ypos = is_mac and (base_win_y - h) or base_win_y
    gfx.init("Auto Color by Take Name", w, h, 0, base_win_x, ypos)
  else
    gfx.init("Auto Color by Take Name", w, h)
  end
end

local function save_win_size()
  reaper.SetExtState(PREF_NS, "win_w", tostring(base_win_w), true)
  reaper.SetExtState(PREF_NS, "win_h", tostring(base_win_h), true)
  reaper.SetExtState(PREF_NS, "win_x", tostring(base_win_x), true)
  reaper.SetExtState(PREF_NS, "win_y", tostring(base_win_y), true)
end

local function load_win_size()
  local w = tonumber(reaper.GetExtState(PREF_NS, "win_w"))
  local h = tonumber(reaper.GetExtState(PREF_NS, "win_h"))
  local x = tonumber(reaper.GetExtState(PREF_NS, "win_x"))
  local y = tonumber(reaper.GetExtState(PREF_NS, "win_y"))
  if w and w >= 580 then base_win_w = w else base_win_w = math.max(base_win_w, 620) end
  if h and h >= 100 then base_win_h = h end
  if x then base_win_x = x end
  if y then base_win_y = y end
end

-- ─── mouse ────────────────────────────────────────────────────────────────────
local mx, my        = 0, 0
local lb, prev_lb   = 0, 0
local rb, prev_rb   = 0, 0
local lclicked      = false
local rclicked      = false

local function hit(x, y, w, h)
  return mx>=x and mx<x+w and my>=y and my<y+h
end

-- ─── draw helpers ─────────────────────────────────────────────────────────────
local function fill(x,y,w,h,r,g,b,a) gfx.set(r,g,b,a or 1); gfx.rect(x,y,w,h,1) end
local function stroke(x,y,w,h,r,g,b,a) gfx.set(r,g,b,a or 1); gfx.rect(x,y,w,h,0) end
local function txt(x,y,s,r,g,b,a)
  gfx.set(r or .9,g or .9,b or .9,a or 1); gfx.x,gfx.y=x,y; gfx.drawstr(s)
end

local function btn(x,y,w,h,label,active)
  local hov=hit(x,y,w,h)
  if active then
    -- active: dark background with a bright bottom border, white text
    fill(x,y,w,h, .20,.20,.20)
    gfx.set(.35,.75,.35,1); gfx.line(x,y+h-2,x+w-1,y+h-2); gfx.line(x,y+h-1,x+w-1,y+h-1)
    stroke(x,y,w,h, .35,.55,.35)
  else
    fill(x,y,w,h, hov and .40 or .27, hov and .40 or .27, hov and .40 or .27)
    stroke(x,y,w,h, .50,.50,.50)
  end
  local tw,th=gfx.measurestr(label)
  txt(x+(w-tw)*.5,y+(h-th)*.5,label, .92,.92,.92)
  return lclicked and hov
end

local function chkbox(x,y,val,label)
  stroke(x,y,14,14,.55,.55,.55)
  if val then fill(x+3,y+3,8,8,.25,.85,.25) end
  local _,th=gfx.measurestr("A")
  txt(x+18,y+(14-th)*.5,label)
  local tw=gfx.measurestr(label)
  return lclicked and hit(x,y,tw+22,16)
end

local function smbtn(x,y,w,h,label)
  local hov=hit(x,y,w,h)
  fill(x,y,w,h,hov and .42 or .28,.28,.28)
  stroke(x,y,w,h,.5,.5,.5)
  local tw,th=gfx.measurestr(label)
  txt(x+(w-tw)*.5,y+(h-th)*.5,label)
  return lclicked and hov
end

-- ─── slider ───────────────────────────────────────────────────────────────────
local slider_drag_id = nil

local function hslider(id, x, y, w, val, vmin, vmax)
  local h    = 14
  local frac = math.max(0, math.min(1, (val - vmin) / (vmax - vmin)))
  -- track
  fill(x, y+5, w, 4, .18, .18, .18)
  fill(x, y+5, math.floor(w * frac), 4, .30, .52, .82)
  -- handle
  local hx  = x + math.floor(w * frac) - 5
  local act = slider_drag_id == id
  local hov = act or hit(x-2, y, w+4, h)
  fill(hx, y, 10, h, hov and .82 or .60, hov and .82 or .60, hov and .82 or .60)
  stroke(hx, y, 10, h, .22, .22, .22)
  -- interaction
  if lb == 1 and (act or (hit(x-2, y, w+4, h) and slider_drag_id == nil)) then
    slider_drag_id = id
    val = vmin + (vmax - vmin) * math.max(0, math.min(1, (mx - x) / w))
    return val, true
  end
  if lb == 0 and act then slider_drag_id = nil end
  return val, false
end

-- ─── settings panel ───────────────────────────────────────────────────────────
local SROW_H = 22   -- settings row height

local function settings_panel_h()
  return SROW_H*2 + SROW_H * #PCONF.rows + SROW_H*2 + MARGIN*2
end

-- Total expanded window height (palette area + all optional panels)
local function expanded_h()
  return base_win_h
    + (show_settings and settings_panel_h() or 0)
    + (show_presets  and 120                or 0)
    + AC_BAR_H
end

-- draws the settings panel starting at screen y; returns whether palette should regenerate
local function draw_settings_panel(start_y)
  local W      = gfx.w
  local px     = MARGIN
  local pw     = W - MARGIN*2
  local dirty  = false

  fill(0, start_y, W, settings_panel_h(), .13, .13, .13)
  gfx.set(.30,.30,.30,1); gfx.line(0, start_y + settings_panel_h()-1, W, start_y + settings_panel_h()-1)

  local iy = start_y + MARGIN

  -- ── Row 1: Hue offset + Span ───────────────────────────────────────────
  gfx.setfont(2)
  local lw = 32   -- label column width
  local vw = 34   -- value display width
  local gap = 12  -- gap between Hue block and Span block
  local sw = (pw - lw*2 - vw*2 - gap) // 2  -- slider width

  txt(px, iy+5, "Hue", .55,.55,.55)
  local new_h, ch = hslider("hue", px+lw, iy, sw, PCONF.hue_offset, 0, 360)
  if ch then PCONF.hue_offset = math.floor(new_h+.5); dirty = true end
  txt(px+lw+sw+4, iy+5, string.format("%d°", PCONF.hue_offset), .72,.72,.72)

  local sx2 = px + lw + sw + vw + gap
  txt(sx2, iy+5, "Span", .55,.55,.55)
  local new_r, cr2 = hslider("span", sx2+lw, iy, sw, PCONF.hue_range, 10, 360)
  if cr2 then PCONF.hue_range = math.floor(new_r+.5); dirty = true end
  txt(sx2+lw+sw+4, iy+5, string.format("%d°", PCONF.hue_range), .72,.72,.72)

  iy = iy + SROW_H

  -- ── Row 2+: per-row Sat / Val sliders ──────────────────────────────────
  local rlw = 22  -- "R1" label
  local svlbl = 12  -- "S" or "V" label
  local svval = 30  -- "XX%" value display
  local svslw = (pw - rlw - (svlbl+svval)*2 - 10) // 2  -- sat/val slider width

  for r = 1, #PCONF.rows do
    local row = PCONF.rows[r]
    local x = px

    -- row label
    txt(x, iy+5, "R"..r, .45,.45,.45)
    x = x + rlw

    -- Sat
    txt(x, iy+5, "S", .40,.60,.90)
    x = x + svlbl
    local ns, cs2 = hslider("s"..r, x, iy, svslw, row.sat, 0, 1)
    if cs2 then row.sat = math.floor(ns*100+.5)/100; dirty = true end
    x = x + svslw + 2
    txt(x, iy+5, string.format("%d%%", math.floor(row.sat*100+.5)), .62,.62,.62)
    x = x + svval

    -- Val
    txt(x, iy+5, "V", .90,.78,.40)
    x = x + svlbl
    local nv, cv2 = hslider("v"..r, x, iy, svslw, row.val, 0, 1)
    if cv2 then row.val = math.floor(nv*100+.5)/100; dirty = true end
    x = x + svslw + 2
    txt(x, iy+5, string.format("%d%%", math.floor(row.val*100+.5)), .62,.62,.62)

    iy = iy + SROW_H
  end

  -- ── Footer: Rows ±, Cols ±, Reset ──────────────────────────────────────
  gfx.setfont(2)
  local fx = px

  txt(fx, iy+6, "Rows", .55,.55,.55); fx = fx + 34
  if smbtn(fx, iy+2, 16, 18, "−") and #PCONF.rows > 1 then
    table.remove(PCONF.rows); dirty = true
  end
  fx = fx + 18
  local rs = tostring(#PCONF.rows); local rsw = gfx.measurestr(rs)
  txt(fx + (12-rsw)*.5, iy+6, rs, .80,.80,.80); fx = fx + 14
  if smbtn(fx, iy+2, 16, 18, "+") and #PCONF.rows < 8 then
    local last = PCONF.rows[#PCONF.rows]
    PCONF.rows[#PCONF.rows+1] = { sat=last.sat, val=math.max(0.10, last.val - 0.15) }
    dirty = true
  end
  fx = fx + 22

  txt(fx, iy+6, "Cols", .55,.55,.55); fx = fx + 32
  if smbtn(fx, iy+2, 16, 18, "−") and PALETTE_COLS > 1 then
    PALETTE_COLS = PALETTE_COLS - 1; dirty = true
  end
  fx = fx + 18
  local cs3 = tostring(PALETTE_COLS); local csw = gfx.measurestr(cs3)
  txt(fx + (14-csw)*.5, iy+6, cs3, .80,.80,.80); fx = fx + 16
  if smbtn(fx, iy+2, 16, 18, "+") and PALETTE_COLS < 24 then
    PALETTE_COLS = PALETTE_COLS + 1; dirty = true
  end

  -- grey row checkbox
  fx = fx + 16
  if chkbox(fx, iy+1, PCONF.grey_row, "Grey row") then
    PCONF.grey_row = not PCONF.grey_row; dirty = true
  end

  if btn(W-100, iy+2, 92, 18, "Reset Default") then
    PCONF.hue_offset = 0; PCONF.hue_range = 330; PCONF.grey_row = true
    PCONF.rows = {{sat=0.20,val=0.90},{sat=0.65,val=0.75},{sat=0.90,val=0.55}}
    PALETTE_COLS = 10; dirty = true
  end

  -- ── Font size row ───────────────────────────────────────────────────────
  iy = iy + SROW_H
  txt(px, iy+6, "Font", .55,.55,.55)
  local ffx = px + 34
  if smbtn(ffx, iy+2, 16, 18, "−") and font_size > 8 then
    font_size = font_size - 1; font_dirty = true; save_pconf()
  end
  ffx = ffx + 18
  local fsz = tostring(font_size); local fszw = gfx.measurestr(fsz)
  txt(ffx + (16-fszw)*.5, iy+6, fsz, .80,.80,.80)
  ffx = ffx + 18
  if smbtn(ffx, iy+2, 16, 18, "+") and font_size < 24 then
    font_size = font_size + 1; font_dirty = true; save_pconf()
  end
  ffx = ffx + 24

  txt(ffx, iy+6, "Preview chars", .55,.55,.55); ffx = ffx + 90
  if smbtn(ffx, iy+2, 16, 18, "−") and swatch_chars > 1 then
    swatch_chars = swatch_chars - 1; save_pconf()
  end
  ffx = ffx + 18
  local scstr = tostring(swatch_chars); local scw = gfx.measurestr(scstr)
  txt(ffx + (16-scw)*.5, iy+6, scstr, .80,.80,.80)
  ffx = ffx + 18
  if smbtn(ffx, iy+2, 16, 18, "+") and swatch_chars < 9 then
    swatch_chars = swatch_chars + 1; save_pconf()
  end

  gfx.setfont(1)
  return dirty
end

-- ─── right-click popup ────────────────────────────────────────────────────────
local popup_idx = nil
local popup_x, popup_y = 0, 0
local POPUP_ITEMS = { "Edit Keyword", "────", "Clear Keyword" }

-- ─── scroll & panel state ────────────────────────────────────────────────────
local scroll_row         = 0
local preset_scroll      = 0
local preset_auto_update = true   -- auto-save to current_preset on changes

local draw_preset_panel  -- forward declaration (defined in presets section below)
local draw_list_view     -- forward declaration (defined in presets section below)
local export_keywords    -- forward declaration (defined in presets section below)
local import_keywords    -- forward declaration (defined in presets section below)

-- ─── main draw ────────────────────────────────────────────────────────────────
local hover_info = ""

local function draw()
  if font_dirty then
    -- PingFang SC (macOS) / Microsoft YaHei (Windows) both cover CJK + Latin
    local face = is_mac and "PingFang SC" or "Microsoft YaHei"
    gfx.setfont(1, face, font_size)
    gfx.setfont(2, face, math.max(8, font_size - 2))
    font_dirty = false
  end
  local W = gfx.w
  local H = gfx.h

  prev_lb, prev_rb = lb, rb
  mx, my = gfx.mouse_x, gfx.mouse_y
  lb = (gfx.mouse_cap&1)~=0 and 1 or 0
  rb = (gfx.mouse_cap&2)~=0 and 1 or 0
  lclicked = (prev_lb==1 and lb==0)
  rclicked = (prev_rb==1 and rb==0)
  -- grid scroll only in color view; list view handles its own wheel inside draw_list_view
  if view_mode == "color" and gfx.mouse_wheel ~= 0 then
    scroll_row = scroll_row + (gfx.mouse_wheel>0 and -1 or 1)
    gfx.mouse_wheel = 0
  end

  fill(0, 0, W, H, .17, .17, .17)

  -- ── toolbar ────────────────────────────────────────────────────────────────
  local ty = (BAR_H-14)//2
  if chkbox(MARGIN, ty+1, auto_color_enabled, "Auto Color") then
    auto_color_enabled = not auto_color_enabled
    save_auto_pref()
    if auto_color_enabled then last_state_count=-1 end
  end
  if btn(148, 1, 80, BAR_H-2, "Copy Color") then do_copy_color() end
  do  -- Paste Color: background shows the copied color when available
    local px2, py2, pw, ph = 232, 1, 82, BAR_H-2
    local hov = hit(px2, py2, pw, ph)
    if copied_color then
      local br = cr(copied_color) * (hov and 1.15 or 1)
      local bg = cg(copied_color) * (hov and 1.15 or 1)
      local bb = cb(copied_color) * (hov and 1.15 or 1)
      br, bg, bb = math.min(br,1), math.min(bg,1), math.min(bb,1)
      fill(px2, py2, pw, ph, br, bg, bb)
      stroke(px2, py2, pw, ph, .60,.60,.60)
      local tw2, th2 = gfx.measurestr("Paste Color")
      local tl = lum(copied_color) > 0.4 and 0 or 1  -- dark text on light bg
      txt(px2+(pw-tw2)*.5, py2+(ph-th2)*.5, "Paste Color", tl, tl, tl)
    else
      fill(px2, py2, pw, ph, .20,.20,.20)
      stroke(px2, py2, pw, ph, .38,.38,.38)
      local tw2, th2 = gfx.measurestr("Paste Color")
      txt(px2+(pw-tw2)*.5, py2+(ph-th2)*.5, "Paste Color", .45,.45,.45)
    end
    if lclicked and hov then do_paste_color() end
  end
  if btn(318, 1, 100, BAR_H-2, "Remove Color") then do_clear_selected() end

  -- preset name + save status (to the left of ☰ Presets)
  local preset_btn_x   = W - 194
  local settings_btn_x = W - 108
  local collapse_btn_x = W - 24
  do
    gfx.setfont(2)
    local label, lr, lg, lb2
    if current_preset then
      if preset_dirty then
        label = current_preset .. "  *"
        lr, lg, lb2 = .88, .65, .28
      else
        label = current_preset .. "  ●"
        lr, lg, lb2 = .40, .80, .40
      end
    end
    if label then
      local tw = gfx.measurestr(label)
      local px = preset_btn_x - tw - 10
      if px > 424 then
        local _, th = gfx.measurestr("A")
        txt(px, (BAR_H-th)//2, label, lr, lg, lb2)
      end
    end
    gfx.setfont(1)
  end

  if not collapsed then
    if btn(preset_btn_x,   1, 80, BAR_H-2, "☰ Presets", show_presets) then
      show_presets = not show_presets
      save_pconf()
      prog_resize = 4
      gfx_init(gfx.w, expanded_h())
    end
    if btn(settings_btn_x, 1, 78, BAR_H-2, "⚙ Settings", show_settings) then
      show_settings = not show_settings
      save_pconf()
      prog_resize = 4
      gfx_init(gfx.w, expanded_h())
    end
  end
  if btn(collapse_btn_x, 1, 22, BAR_H-2, collapsed and "▴" or "▾") then
    collapsed = not collapsed
    save_pconf()
    prog_resize = 4
    gfx_init(gfx.w, collapsed and BAR_H or expanded_h())
  end

  if collapsed then return end

  -- ── item-type filter sub-bar (always visible) ─────────────────────────────
  do
    local sy = BAR_H
    fill(0, sy, W, AC_BAR_H, .12, .12, .12)
    gfx.set(.28,.28,.28,1); gfx.line(0, sy + AC_BAR_H - 1, W, sy + AC_BAR_H - 1)
    local ty2 = sy + (AC_BAR_H - 14) // 2
    local fx2 = MARGIN
    txt(fx2, ty2 + 1, "Types:", .45,.45,.45); fx2 = fx2 + 46
    if chkbox(fx2, ty2, ac_audio, "Audio") then ac_audio = not ac_audio; save_auto_pref() end
    fx2 = fx2 + 58
    if chkbox(fx2, ty2, ac_empty, "Empty") then ac_empty = not ac_empty; save_auto_pref() end
    fx2 = fx2 + 60
    if chkbox(fx2, ty2, ac_midi,  "MIDI")  then ac_midi  = not ac_midi;  save_auto_pref() end
  end
  local content_top = BAR_H + AC_BAR_H

  -- ── separator + optional panels ────────────────────────────────────────────
  if show_presets then
    draw_preset_panel(content_top)
    content_top = content_top + 120
  end
  if show_settings then
    local dirty = draw_settings_panel(content_top)
    if dirty then
      gen_palette()
      save_palette()
      save_pconf()
      preset_dirty = true
      if auto_color_enabled then last_state_count = -1 end
    end
    content_top = content_top + settings_panel_h()
  end
  gfx.set(.28,.28,.28,1); gfx.line(0, content_top, W, content_top)
  content_top = content_top + 1

  -- ── view toggle row ────────────────────────────────────────────────────────
  local TOGGLE_H = 22
  fill(0, content_top, W, TOGGLE_H, .14,.14,.14)
  if btn(MARGIN, content_top+2, 72, TOGGLE_H-4, "⊞ Colors", view_mode == "color") then
    view_mode = "color"; save_pconf()
  end
  if btn(MARGIN+76, content_top+2, 56, TOGGLE_H-4, "≡ List", view_mode == "list") then
    view_mode = "list"; save_pconf()
  end
  content_top = content_top + TOGGLE_H

  -- ── palette grid or list view ──────────────────────────────────────────────
  if view_mode == "list" then
    draw_list_view(content_top, H - content_top - 16 - MARGIN - LIST_FOOTER_H)
    -- ── export / import footer ────────────────────────────────────────────
    local fy = H - 16 - MARGIN - LIST_FOOTER_H
    fill(0, fy, W, LIST_FOOTER_H, .11, .11, .11)
    gfx.set(.28,.28,.28,1); gfx.line(0, fy, W, fy)
    if btn(MARGIN, fy+3, 72, LIST_FOOTER_H-6, "⬆ Export") then export_keywords() end
    if btn(MARGIN+76, fy+3, 72, LIST_FOOTER_H-6, "⬇ Import") then import_keywords() end
  else
    local grid_y   = content_top + 4
    local cw       = math.max(28, (W - MARGIN*2) // PALETTE_COLS)
    local avail_h  = H - grid_y - 16 - MARGIN
    local max_rows = math.max(1, math.ceil(#PALETTE / PALETTE_COLS))
    local cell_h   = math.max(24, math.floor(avail_h / max_rows))
    local ch       = cell_h - 2
    local vis_rows = math.floor(avail_h / cell_h)
    scroll_row = math.max(0, math.min(scroll_row, math.max(0, max_rows - vis_rows)))

    for slot = 1, vis_rows * PALETTE_COLS do
      local gi  = slot + scroll_row * PALETTE_COLS
      if gi > #PALETTE then break end
      local col = (slot-1) % PALETTE_COLS
      local row = (slot-1) // PALETTE_COLS
      local cx  = MARGIN + col * cw
      local cy  = grid_y + row * cell_h
      local hov = hit(cx, cy, cw-1, ch)

      local p   = PALETTE[gi]
      local has = p.keyword ~= ""

      fill(cx, cy, cw-1, ch, cr(p.color), cg(p.color), cb(p.color))
      if hov then
        stroke(cx, cy, cw-1, ch, 1, 1, 1, .8)
        hover_info = string.format("#%06X", p.color) ..
          (has and ("   →  " .. p.keyword) or "   (no keyword)")
      else
        stroke(cx, cy, cw-1, ch, 0, 0, 0, .30)
      end

      if has then
        gfx.setfont(2)
        local tc  = lum(p.color) > .45 and 0.0 or 1.0
        -- split by | and collect parts
        local parts = {}
        for seg in (p.keyword .. "|"):gmatch("([^|]*)|") do
          local s = seg:match("^%s*(.-)%s*$")
          if s ~= "" then parts[#parts+1] = utf8_take(s, swatch_chars) end
        end
        -- measure line height from actual content so CJK glyphs center correctly
        local lh = select(2, gfx.measurestr("Aq"))
        for _, c1 in ipairs(parts) do
          local _, h = gfx.measurestr(c1)
          if h > lh then lh = h end
        end
        local total_h = #parts * lh
        local text_y = cy + math.max(2, (ch - total_h) * .5)
        for _, c1 in ipairs(parts) do
          local tw2 = gfx.measurestr(c1)
          txt(cx + (cw-1-tw2)*.5, text_y, c1, tc,tc,tc,1.0)
          text_y = text_y + lh
        end
        gfx.setfont(1)
      end

      if lclicked and hov and popup_idx == nil then
        local n = reaper.CountSelectedMediaItems(0)
        if n > 0 then
          reaper.Undo_BeginBlock()
          for j = 0, n-1 do apply_color_to_item(reaper.GetSelectedMediaItem(0,j), p.color) end
          reaper.Undo_EndBlock("Apply Color "..string.format("#%06X",p.color), -1)
          reaper.UpdateArrange()
          set_status(string.format("Applied to %d item(s)", n))
        else
          set_status("No items selected")
        end
      end

      if rclicked and hov then
        popup_idx = gi
        popup_x   = math.min(mx, W-140)
        popup_y   = math.min(my, H-#POPUP_ITEMS*20-10)
      end
    end
  end  -- view_mode == "list" / else

  -- ── right-click popup ────────────────────────────────────────────────────
  if popup_idx then
    local p  = PALETTE[popup_idx]
    local pw2 = 140
    local ph = #POPUP_ITEMS * 20 + 6
    fill(popup_x, popup_y, pw2, ph, .22,.22,.22)
    stroke(popup_x, popup_y, pw2, ph, .65,.65,.65)

    for i, item in ipairs(POPUP_ITEMS) do
      local iy2 = popup_y + 3 + (i-1)*20
      local hov2 = item~="────" and hit(popup_x, iy2, pw2, 20)
      if hov2 then fill(popup_x, iy2, pw2, 20, .38,.38,.38) end

      if item == "────" then
        gfx.set(.4,.4,.4,1); gfx.line(popup_x+6, iy2+9, popup_x+pw2-6, iy2+9)
      else
        gfx.setfont(2)
        txt(popup_x+8, iy2+5, item, .88,.88,.88)
        gfx.setfont(1)
      end

      if lclicked and hov2 and p then
        if item == "Edit Keyword" then
          local ok, val = reaper.GetUserInputs(
            "Keyword — " .. string.format("#%06X", p.color), 1,
            "Keyword (| for multiple, e.g. boom|lavmic)  [clear to remove]:",
            p.keyword, 600)
          if ok and val ~= nil then
            p.keyword = val:match("^%s*(.-)%s*$")
            save_palette(); preset_dirty = true
            if auto_color_enabled then last_state_count=-1 end
          end
        elseif item == "Clear Keyword" then
          p.keyword = ""
          save_palette(); preset_dirty = true
        end
        popup_idx = nil
      end
    end

    -- close on click outside
    if (lclicked or rclicked) and not hit(popup_x, popup_y, pw2, ph) then
      popup_idx = nil
    end
  end

  -- ── hint bar ─────────────────────────────────────────────────────────────
  local bot_y = H - 13
  gfx.setfont(2)
  if status_msg ~= "" and reaper.time_precise() < status_until then
    txt(MARGIN, bot_y, status_msg, .45,.85,.45)
  elseif hover_info ~= "" then
    txt(MARGIN, bot_y, hover_info, .62,.62,.62)
  else
    txt(MARGIN, bot_y, "Left-click: apply to selected   Right-click: set keyword", .34,.34,.34)
  end
  gfx.setfont(1)

  gfx.update()
end

-- ─── presets ─────────────────────────────────────────────────────────────────
local function preset_key(name) return "preset:" .. name end

local function list_presets()
  local raw = reaper.GetExtState(PREF_NS, "preset_list")
  local names = {}
  for n in (raw.."|"):gmatch("([^|]+)|") do names[#names+1] = n end
  return names
end

local function save_preset(name)
  -- save current pconf + palette keywords under this name
  local parts = { string.format("%.2f", PCONF.hue_offset),
                  string.format("%.2f", PCONF.hue_range),
                  PCONF.grey_row and "1" or "0",
                  tostring(PALETTE_COLS) }
  for _, row in ipairs(PCONF.rows) do
    parts[#parts+1] = string.format("%.4f,%.4f", row.sat, row.val)
  end
  parts[#parts+1] = "---"
  for _, p in ipairs(PALETTE) do
    parts[#parts+1] = p.keyword or ""
  end
  reaper.SetExtState(PREF_NS, preset_key(name), table.concat(parts, "\n"), true)
  -- add to list
  local names = list_presets()
  local found = false
  for _, n in ipairs(names) do if n == name then found = true; break end end
  if not found then
    names[#names+1] = name
    reaper.SetExtState(PREF_NS, "preset_list", table.concat(names, "|"), true)
  end
end

local function load_preset(name)
  local raw = reaper.GetExtState(PREF_NS, preset_key(name))
  if raw == "" then return false end
  local parts = {}
  -- new format uses \n as separator (safe for keywords containing |)
  for v in (raw.."\n"):gmatch("([^\n]*)\n") do parts[#parts+1] = v end
  if #parts < 5 then
    -- fallback: old format used | as separator (may mangle keywords with |)
    parts = {}
    for v in (raw.."|"):gmatch("([^|]*)|") do parts[#parts+1] = v end
  end
  if #parts < 5 then return false end
  PCONF.hue_offset = tonumber(parts[1]) or 0
  PCONF.hue_range  = tonumber(parts[2]) or 330
  PCONF.grey_row   = parts[3] == "1"
  PALETTE_COLS     = tonumber(parts[4]) or 10
  local rows = {}
  local i = 5
  while i <= #parts and parts[i] ~= "---" do
    local s, v = parts[i]:match("([^,]+),([^,]+)")
    if s and v then rows[#rows+1] = { sat=tonumber(s) or 0.5, val=tonumber(v) or 0.75 } end
    i = i + 1
  end
  if #rows > 0 then PCONF.rows = rows end
  gen_palette()
  -- restore keywords
  local ki = i + 1
  for _, p in ipairs(PALETTE) do
    p.keyword = parts[ki] or ""
    ki = ki + 1
  end
  save_palette(); save_pconf()
  current_preset = name
  preset_dirty   = false
  if auto_color_enabled then last_state_count = -1 end
  return true
end

local function delete_preset(name)
  reaper.DeleteExtState(PREF_NS, preset_key(name), true)
  local names = list_presets()
  local new_names = {}
  for _, n in ipairs(names) do if n ~= name then new_names[#new_names+1] = n end end
  reaper.SetExtState(PREF_NS, "preset_list", table.concat(new_names, "|"), true)
end

local function rename_preset(old_name, new_name)
  local data = reaper.GetExtState(PREF_NS, preset_key(old_name))
  reaper.SetExtState(PREF_NS, preset_key(new_name), data, true)
  reaper.DeleteExtState(PREF_NS, preset_key(old_name), true)
  local names = list_presets()
  local new_names = {}
  for _, n in ipairs(names) do
    new_names[#new_names+1] = (n == old_name) and new_name or n
  end
  reaper.SetExtState(PREF_NS, "preset_list", table.concat(new_names, "|"), true)
  if current_preset == old_name then current_preset = new_name end
end

-- ─── keyword export / import ──────────────────────────────────────────────────
-- Format: one line per palette entry — "RRGGBB\tkeyword"
-- Empty keyword = empty string after the tab (line still present for position).
-- Comment lines starting with # are skipped on import.

local function proj_dir()
  -- EnumProjects(-1) gives the current project's .rpp file path (session folder),
  -- unlike GetProjectPath which returns the media/recording folder.
  local _, rpp = reaper.EnumProjects(-1, "")
  local p = (rpp ~= "" and rpp:match("^(.*[/\\])")) or SCRIPT_DIR
  if not p:match("[/\\]$") then p = p .. "/" end
  return p
end

export_keywords = function()
  local dir  = proj_dir()
  local path
  if reaper.JS_Dialog_BrowseForSaveFile then
    -- js_ReaScriptAPI available: native macOS/Windows save dialog
    -- JS_Dialog_BrowseForSaveFile returns (retval, fileName) — must capture both
    local ret
    ret, path = reaper.JS_Dialog_BrowseForSaveFile(
      "Export Keywords", dir, "hsuanice_keywords.txt",
      "Text files (.txt)\0*.txt\0All files (*.*)\0*.*\0")
    if not ret or ret ~= 1 or not path or path == "" then return end
  else
    -- fallback: plain text-input dialog
    local ok, p = reaper.GetUserInputs("Export Keywords", 1,
      "Save to file (full path):", dir .. "hsuanice_keywords.txt", 512)
    if not ok or p == "" then return end
    path = p:match("^%s*(.-)%s*$")
  end
  local f = io.open(path, "w")
  if not f then
    reaper.ShowMessageBox("Could not write to:\n" .. path, "Export Error", 0)
    return
  end
  f:write("# hsuanice Auto Color Items — keyword export\n")
  f:write("# hex_color\tkeyword\n")
  for _, p in ipairs(PALETTE) do
    f:write(string.format("%06X\t%s\n", p.color & 0xFFFFFF, p.keyword or ""))
  end
  f:close()
  set_status("Exported " .. #PALETTE .. " entries → " .. path)
end

import_keywords = function()
  local ok, path = reaper.GetUserFileNameForRead(
    proj_dir() .. "hsuanice_keywords.txt", "Import Keywords", "txt")
  if not ok or path == "" then return end
  local f = io.open(path, "r")
  if not f then
    reaper.ShowMessageBox("Could not open:\n" .. path, "Import Error", 0)
    return
  end
  local kws = {}
  for line in f:lines() do
    if not line:match("^%s*#") then          -- skip comment lines
      -- accept "hex\tkeyword" or just "keyword"
      local kw = line:match("\t(.*)$") or line
      kws[#kws+1] = kw:match("^%s*(.-)%s*$")
    end
  end
  f:close()
  local count = 0
  for i, p in ipairs(PALETTE) do
    if kws[i] ~= nil then
      p.keyword = kws[i]
      count = count + 1
    end
  end
  save_palette()
  preset_dirty = true
  if auto_color_enabled then last_state_count = -1 end
  set_status("Imported " .. count .. " keywords from file")
end

-- ─── file-based state persistence ────────────────────────────────────────────
-- Saves/loads ALL ExtState keys (palette, presets, prefs) to a plain-text file
-- in Tools/ so data survives REAPER restarts even if reaper-extstate.ini is lost.
local STATE_DIR  = SCRIPT_DIR .. "../Tools/"
local STATE_FILE = STATE_DIR  .. "hsuanice_AutoColorItems_state.dat"

-- Encode/decode newlines so each key fits on one line.
local function enc(s) return (s:gsub("\\", "\\\\"):gsub("\n", "\\n")) end
local function dec(s) return (s:gsub("\\\\", "\1"):gsub("\\n", "\n"):gsub("\1", "\\")) end

local PERSIST_KEYS = {
  "pconf_v1", "grey_row", "palette_v3", "last_preset",
  "collapsed", "show_settings", "show_presets", "view_mode",
  "font_size", "swatch_chars", "ac_audio", "ac_empty", "ac_midi",
  "win_w", "win_h", "win_x", "win_y", "preset_list",
}

local function save_state_to_file()
  os.execute('mkdir -p "' .. STATE_DIR .. '"')
  local f = io.open(STATE_FILE, "w")
  if not f then return end
  f:write("# hsuanice_AutoColorItems state v1\n")
  for _, key in ipairs(PERSIST_KEYS) do
    local val = reaper.GetExtState(PREF_NS, key)
    if val ~= "" then f:write(key .. "=" .. enc(val) .. "\n") end
  end
  -- write each saved preset
  local names = list_presets()
  for _, name in ipairs(names) do
    local pk  = "preset:" .. name
    local val = reaper.GetExtState(PREF_NS, pk)
    if val ~= "" then f:write(pk .. "=" .. enc(val) .. "\n") end
  end
  f:close()
end

local function load_state_from_file()
  local f = io.open(STATE_FILE, "r")
  if not f then return false end
  for line in f:lines() do
    if not line:match("^%s*#") and line ~= "" then
      -- split on first '=' only (preset names / keywords may contain '=')
      local key, val = line:match("^([^=]+)=(.*)")
      if key and val then
        reaper.SetExtState(PREF_NS, key, dec(val), true)
      end
    end
  end
  f:close()
  return true
end

draw_list_view = function(top_y, avail_h)
  local W        = gfx.w
  local ROW_H    = 22
  local SWATCH_W = 20
  local HEX_W    = 62
  local SB_W     = 10   -- scrollbar width
  local n        = #PALETTE

  local vis      = math.max(1, math.floor(avail_h / ROW_H))
  local max_sc   = math.max(0, n - vis)
  list_scroll    = math.max(0, math.min(list_scroll, max_sc))

  -- ── scrollbar geometry ───────────────────────────────────────────────────
  local need_sb  = n > vis
  local sb_x     = W - SB_W
  local content_w = need_sb and (W - SB_W) or W

  if need_sb then
    local track_h  = avail_h
    local thumb_h  = math.max(20, math.floor(track_h * vis / n))
    local thumb_y  = top_y + math.floor((track_h - thumb_h) * list_scroll / math.max(1, max_sc))

    -- track
    fill(sb_x, top_y, SB_W, track_h, .13,.13,.13)

    -- handle drag
    local on_track = hit(sb_x, top_y, SB_W, track_h)
    if lb == 1 and (list_sb_drag or on_track) then
      list_sb_drag = true
      local rel = math.max(0, math.min(1, (my - top_y - thumb_h/2) / math.max(1, track_h - thumb_h)))
      list_scroll = math.floor(rel * max_sc + .5)
      list_scroll = math.max(0, math.min(list_scroll, max_sc))
      thumb_y = top_y + math.floor((track_h - thumb_h) * list_scroll / math.max(1, max_sc))
    elseif lb == 0 then
      list_sb_drag = false
    end

    -- thumb
    local thumb_hov = list_sb_drag or hit(sb_x, thumb_y, SB_W, thumb_h)
    fill(sb_x+2, thumb_y+1, SB_W-4, thumb_h-2,
         thumb_hov and .58 or .38, thumb_hov and .58 or .38, thumb_hov and .58 or .38)
  end

  -- ── mouse wheel ─────────────────────────────────────────────────────────
  if gfx.mouse_wheel ~= 0 and hit(0, top_y, W, avail_h) then
    list_scroll = list_scroll + (gfx.mouse_wheel > 0 and -1 or 1)
    list_scroll = math.max(0, math.min(list_scroll, max_sc))
    gfx.mouse_wheel = 0
  end

  -- ── rows ─────────────────────────────────────────────────────────────────
  for i = 1, vis do
    local gi = i + list_scroll
    if gi > n then break end
    local p   = PALETTE[gi]
    local ry  = top_y + (i-1) * ROW_H
    local hov = (not list_sb_drag) and hit(0, ry, content_w, ROW_H)

    fill(0, ry, content_w, ROW_H, hov and .24 or (gi%2==0 and .19 or .17),
                                   hov and .24 or (gi%2==0 and .19 or .17),
                                   hov and .24 or (gi%2==0 and .19 or .17))

    -- color swatch
    fill(MARGIN, ry+3, SWATCH_W, ROW_H-6, cr(p.color), cg(p.color), cb(p.color))
    stroke(MARGIN, ry+3, SWATCH_W, ROW_H-6, 0, 0, 0, .35)

    -- hex label
    gfx.setfont(2)
    local _, th = gfx.measurestr("A")
    txt(MARGIN+SWATCH_W+6, ry+(ROW_H-th)*.5,
        string.format("#%06X", p.color), .48,.48,.48)

    -- keyword
    local kx = MARGIN + SWATCH_W + 6 + HEX_W
    if p.keyword ~= "" then
      txt(kx, ry+(ROW_H-th)*.5, p.keyword, .88,.88,.88)
    else
      txt(kx, ry+(ROW_H-th)*.5, "—", .28,.28,.28)
    end
    gfx.setfont(1)

    -- row divider
    gfx.set(.25,.25,.25,1); gfx.line(0, ry+ROW_H-1, content_w-1, ry+ROW_H-1)

    -- hover info
    if hov then
      hover_info = string.format("#%06X", p.color) ..
        (p.keyword ~= "" and ("   →  " .. p.keyword) or "   (no keyword)")
    end

    -- left-click: apply color
    if lclicked and hov and popup_idx == nil then
      local cnt = reaper.CountSelectedMediaItems(0)
      if cnt > 0 then
        reaper.Undo_BeginBlock()
        for j = 0, cnt-1 do apply_color_to_item(reaper.GetSelectedMediaItem(0,j), p.color) end
        reaper.Undo_EndBlock("Apply Color "..string.format("#%06X",p.color), -1)
        reaper.UpdateArrange()
        set_status(string.format("Applied to %d item(s)", cnt))
      else
        set_status("No items selected")
      end
    end

    -- right-click: open keyword popup
    if rclicked and hov then
      popup_idx = gi
      popup_x   = math.min(mx, W-140)
      popup_y   = math.min(my, top_y+avail_h-#POPUP_ITEMS*20-10)
    end
  end
end

draw_preset_panel = function(start_y)
  local W   = gfx.w
  local ph  = 120
  fill(0, start_y, W, ph, .12, .12, .12)
  gfx.set(.30,.30,.30,1); gfx.line(0, start_y+ph-1, W, start_y+ph-1)

  local names  = list_presets()
  local row_h  = 20
  local lx     = MARGIN
  local btn_x  = W - 96

  -- ── header row: status + Auto Update + Save ──────────────────────────────
  local hdr_y = start_y + 4
  gfx.setfont(2)
  if current_preset and not preset_dirty then
    txt(lx, hdr_y+4, "● " .. current_preset, .40,.82,.40)
  else
    local label = preset_dirty and ("✎ " .. (current_preset or "Unsaved changes"))
                                or "No preset loaded"
    txt(lx, hdr_y+4, label, .85,.65,.25)
  end

  if chkbox(btn_x - 108, hdr_y+2, preset_auto_update, "Auto Update") then
    preset_auto_update = not preset_auto_update
  end
  if btn(btn_x, hdr_y, 88, 18, "Save Preset") then
    local ok, val = reaper.GetUserInputs("Save Preset", 1, "Preset name:",
      current_preset or "", 260)
    if ok and val ~= "" then
      local n = val:match("^%s*(.-)%s*$")
      save_preset(n)
      current_preset = n
      preset_dirty   = false
      save_pconf()
      save_state_to_file()   -- write to Tools/ immediately on explicit save
      set_status("Saved: " .. n)
    end
  end

  -- ── preset list ───────────────────────────────────────────────────────────
  local ly      = start_y + 28
  local list_h  = ph - 32
  local list_w  = W - MARGIN*2

  -- built-in Default (always first, can't delete)
  local def_hov = hit(lx, ly, list_w, row_h-2)
  fill(lx, ly, list_w, row_h-2, def_hov and .26 or .20, def_hov and .26 or .20, def_hov and .26 or .20)
  gfx.setfont(2)
  txt(lx+4, ly+4, "Default  (clear all keywords)", .55,.55,.55)
  gfx.setfont(1)
  if lclicked and def_hov then
    for _, p in ipairs(PALETTE) do p.keyword = "" end
    save_palette()
    current_preset = "Default"
    preset_dirty   = false
    save_pconf()   -- persist last_preset = "Default" immediately
    if auto_color_enabled then last_state_count = -1 end
    set_status("Loaded: Default")
  end
  ly = ly + row_h

  -- user presets
  local vis = math.max(0, math.floor((list_h - row_h) / row_h))
  local max_scroll = math.max(0, #names - vis)
  preset_scroll = math.max(0, math.min(preset_scroll, max_scroll))

  if gfx.mouse_wheel ~= 0 and hit(lx, ly, list_w, list_h - row_h) then
    preset_scroll = preset_scroll + (gfx.mouse_wheel > 0 and -1 or 1)
    gfx.mouse_wheel = 0
  end

  for i = 1, vis do
    local ni   = i + preset_scroll
    if ni > #names then break end
    local name = names[ni]
    local ry   = ly + (i-1)*row_h
    local is_cur = (name == current_preset)
    local hov  = hit(lx, ry, list_w, row_h-2)
    local bg   = is_cur and .22 or (hov and .30 or .15)
    fill(lx, ry, list_w, row_h-2, bg, bg, bg)
    gfx.setfont(2)
    local nr = is_cur and .40 or .80
    local ng = is_cur and .75 or .80
    local nb = is_cur and .40 or .80
    txt(lx+4, ry+4, (is_cur and "▶ " or "  ") .. name, nr, ng, nb)
    gfx.setfont(1)
    if lclicked and hov then
      if load_preset(name) then set_status("Loaded: "..name) end
    end
    if rclicked and hov then
      local choice = gfx.showmenu("Rename|Delete")
      if choice == 1 then
        local ok, val = reaper.GetUserInputs("Rename Preset", 1, "New name:", name, 260)
        if ok then
          local new_name = val:match("^%s*(.-)%s*$")
          if new_name ~= "" and new_name ~= name then
            rename_preset(name, new_name)
            set_status("Renamed: " .. name .. " → " .. new_name)
          end
        end
      elseif choice == 2 then
        local confirm = reaper.ShowMessageBox(
          'Delete preset "' .. name .. '"?', "Confirm Delete", 4)
        if confirm == 6 then  -- 6 = Yes
          delete_preset(name)
          if current_preset == name then current_preset = nil end
          set_status("Deleted: "..name)
        end
      end
    end
  end

  if #names == 0 then
    gfx.setfont(2)
    txt(lx+4, ly+4, "No saved presets  (right-click to delete)", .35,.35,.35)
    gfx.setfont(1)
  end
end

-- ─── init & loop ─────────────────────────────────────────────────────────────
reaper.set_action_options(1)  -- mark as toggle script (checkmark in Action List)
-- Restore from Tools/ file first so ExtState is populated even after a
-- REAPER restart that wiped reaper-extstate.ini.
load_state_from_file()
load_win_size()
load_pconf()
load_palette()
load_auto_pref()
-- If a named preset was active last session, reload it from saved data
-- (guards against palette_v3 becoming stale between sessions)
-- On startup: trust palette_v3 (updated on every keyword edit) as the
-- authoritative state.  Only fall back to the saved preset if palette_v3
-- has no keywords at all (e.g. user loaded Default just before closing).
do
  local has_kw = false
  for _, p in ipairs(PALETTE) do
    if p.keyword ~= "" then has_kw = true; break end
  end
  if not has_kw and current_preset and current_preset ~= "Default" then
    load_preset(current_preset)
  end
end
save_pconf()   -- flush last_preset to ExtState immediately

-- On exit: save both palette and preset so they stay in sync.
-- This means load_preset() on next startup loads the same content as palette_v3.
reaper.atexit(function()
  save_palette()
  if current_preset and current_preset ~= "Default" then
    save_preset(current_preset)
  end
  save_pconf()
  save_state_to_file()   -- write complete snapshot to Tools/ for reliable persistence
end)

do
  gfx_init(base_win_w, collapsed and BAR_H or expanded_h())
end
-- fonts initialized each frame via font_dirty flag in draw()

local prev_gfx_w, prev_gfx_h = gfx.w, gfx.h
local prev_win_x, prev_win_y = gfx.clienttoscreen(0, 0)

local function loop()
  if auto_color_enabled then
    local sc = reaper.GetProjectStateChangeCount(0)
    if sc ~= last_state_count then
      do_auto_color()
      last_state_count = reaper.GetProjectStateChangeCount(0)
    end
  end

  -- detect user resize/move → update base_win_w/h and position
  local cur_x, cur_y = gfx.clienttoscreen(0, 0)
  local size_changed = gfx.w ~= prev_gfx_w or gfx.h ~= prev_gfx_h
  local pos_changed  = cur_x ~= prev_win_x  or cur_y ~= prev_win_y
  if prog_resize > 0 then
    prog_resize = prog_resize - 1
    prev_gfx_w, prev_gfx_h = gfx.w, gfx.h
    prev_win_x, prev_win_y  = cur_x, cur_y
  elseif size_changed or pos_changed then
    if size_changed and not collapsed then
      local panels_h = (show_settings and settings_panel_h() or 0)
                     + (show_presets  and 120                or 0)
                     + AC_BAR_H
      base_win_w = math.max(200, gfx.w)
      base_win_h = math.max(100, gfx.h - panels_h)
    end
    if pos_changed then
      base_win_x = cur_x
      base_win_y = cur_y
    end
    save_win_size()
    prev_gfx_w, prev_gfx_h = gfx.w, gfx.h
    prev_win_x, prev_win_y  = cur_x, cur_y
  end

  -- auto-update current preset when dirty
  if preset_auto_update and preset_dirty and current_preset and current_preset ~= "Default" then
    save_preset(current_preset)
    preset_dirty = false
  end

  draw()
  if gfx.getchar() >= 0 then reaper.defer(loop) end
end

loop()
