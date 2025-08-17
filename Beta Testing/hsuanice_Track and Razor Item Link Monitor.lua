--[[
@description hsuanice_Track and Razor Item Link Monitor (names only + per-item ranges)
@version 0.8.1
@author hsuanice
@about
  Console monitor for the link relationships among Tracks, Razor Areas, and Items.

  It prints:
    • Toggle status (ON/OFF) of your link scripts, showing HUMAN-READABLE SCRIPT NAMES (no IDs shown)
    • REAPER Preference state: Arrange click selects track (requires SWS to read)
    • Selected Tracks (names)
    • Track-level Razor Areas (per track) + GLOBAL UNION
    • Selected Items (GLOBAL): lists active-take names + each item's [start..end] time range
    • For each track that HAS Razor Areas: lists that track's SELECTED items (take names + ranges)
    • Link summary (which link scripts are ACTIVE)

  Controls:
    • Small gfx window shows “Cancel” button; press ESC or click the button to stop the monitor.

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

  Reference:
    Script: X_Raym_Ugurcan Orcun_Toggle Mouse Click for track selection in preference.lua
@changelog
  v0.8.1 - Metadata: added Note and Reference sections.
  v0.8   - Fix undefined compute_item_sel_range(); add Cancel UI; add preference monitoring.
]]


----------------------------
-- Config: scripts to watch
----------------------------
-- { <Display Name in Console>, <Command ID>, <type> }
local SCRIPTS = {
  {"hsuanice_Razor and Item Link with Mode Switch to Overlap or Contain like Pro Tools.lua",
    "_RS6f4e0dfffa0b2d8dbfb1d1f52ed8053bfb935b93", "razor_item"},
  {"hsuanice_Track and Razor Item Link like Pro Tools.lua",
    "_RScb810d93e985a5df273b63589ec315d81fa18529", "track_razor_item"},
}

-- Truncation to avoid flooding console (tune if needed)
local MAX_ITEMS_LIST_GLOBAL    = 500  -- global selected items section
local MAX_ITEMS_LIST_PER_TRACK = 100  -- per-razor-track selected items section

----------------
-- Small utils
----------------
local function fmt_time(t)
  if not t or t < 0 then return "n/a" end
  local h = math.floor(t / 3600)
  local m = math.floor((t % 3600) / 60)
  local s = math.floor(t % 60)
  local ms = math.floor((t - math.floor(t)) * 1000 + 0.5)
  return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

local function track_guid(tr) return reaper.GetTrackGUID(tr) end
local function track_name(tr) local _, n = reaper.GetTrackName(tr, "") return n end
local function track_selected(tr) return (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5 end

local function get_toggle_txt(cmd_str)
  local cmd = reaper.NamedCommandLookup(cmd_str)
  if cmd == 0 then return "UNKNOWN" end
  local st = reaper.GetToggleCommandStateEx(0, cmd)
  return (st == 1 and "ON") or (st == 0 and "OFF") or "UNKNOWN"
end

-- Active take name (fallbacks to source filename, then <unnamed>)
local function active_take_name(it)
  local tk = reaper.GetActiveTake(it)
  if not tk then return "<no take>" end
  local ok, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  if ok and nm ~= "" then return nm end
  local src = reaper.GetMediaItemTake_Source(tk)
  if src then
    local buf = reaper.GetMediaSourceFileName(src, "")
    if buf and buf ~= "" then
      local base = buf:match("[^/\\]+$") or buf
      return base
    end
  end
  return "<unnamed>"
end

-- Parse P_RAZOREDITS into triplets {start, end, guid_str}
local function parse_triplets(s)
  local out = {}
  if not s or s == "" then return out end
  local toks = {}
  for w in s:gmatch("%S+") do toks[#toks+1] = w end
  for i = 1, #toks, 3 do
    local a = tonumber(toks[i]); local b = tonumber(toks[i+1]); local g = toks[i+2] or "\"\""
    if a and b and b > a then out[#out+1] = {a, b, g} end
  end
  return out
end

-- Track-level (GUID=="") Razor ranges on one track
local function track_level_ranges(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok then return {} end
  local out = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] == "\"\"" then out[#out+1] = {t[1], t[2]} end
  end
  table.sort(out, function(a,b) return a[1] < b[1] end)
  return out
end

-- Union (dedup exact [start,end]) of all track-level ranges
local function razor_union_all_tracks()
  local set, out = {}, {}
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    for _, r in ipairs(track_level_ranges(tr)) do
      local key = string.format("%.17f|%.17f", r[1], r[2])
      if not set[key] then set[key] = true; out[#out+1] = {r[1], r[2]} end
    end
  end
  table.sort(out, function(a,b) return a[1] < b[1] end)
  return out
end

--------------------------
-- REAPER Pref monitoring
--------------------------
-- Requires SWS to read: SNM_GetIntConfigVar('trackselonmouse')
local function read_pref_selects_track_raw()
  if reaper.APIExists and reaper.APIExists("SNM_GetIntConfigVar") then
    return reaper.SNM_GetIntConfigVar("trackselonmouse", -1) -- 1=ON, 0=OFF, -1=unknown
  end
  return -999  -- means "SWS not installed"
end

local function pref_selects_track_label()
  local v = read_pref_selects_track_raw()
  if v == 1 then return "ON"
  elseif v == 0 then return "OFF"
  elseif v == -1 then return "UNKNOWN"
  elseif v == -999 then return "UNKNOWN (SWS not installed)"
  else return ("UNKNOWN ("..tostring(v)..")")
  end
end

----------------------
-- Change signatures
----------------------
local function sig_tracks_selected()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    if track_selected(tr) then t[#t+1] = track_guid(tr) end
  end
  return table.concat(t, "|")
end

local function sig_items_selected()
  local parts, icnt = {}, reaper.CountMediaItems(0)
  for i = 0, icnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      parts[#parts+1] = g or tostring(it)
    end
  end
  return table.concat(parts, "|")
end

local function sig_razor_all()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    t[#t+1] = (ok and s) and s or ""
  end
  return table.concat(t, "|")
end

local function sig_scripts_toggle()
  local parts = {}
  for i=1,#SCRIPTS do parts[#parts+1] = get_toggle_txt(SCRIPTS[i][2]) end
  return table.concat(parts, "|")
end

-- Preference signature so monitor refreshes when user toggles it
local function sig_pref_selects_track()
  return tostring(read_pref_selects_track_raw())
end

-----------------
-- Item range util (FIX for undefined function)
-----------------
local function compute_item_sel_range()
  local icnt = reaper.CountMediaItems(0)
  local min_s, max_e = math.huge, -math.huge
  local any = false
  for i = 0, icnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      any = true
      local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if s < min_s then min_s = s end
      if e > max_e then max_e = e end
    end
  end
  if any and max_e > min_s then return true, min_s, max_e end
  return false, 0, 0
end

-----------------
-- Pretty print
-----------------
local function print_script_toggles()
  for _, rec in ipairs(SCRIPTS) do
    local name, id = rec[1], rec[2]
    reaper.ShowConsoleMsg(string.format("  %s: %s\n", name, get_toggle_txt(id)))
  end
end

local function print_pref_state()
  reaper.ShowConsoleMsg(("REAPER Preference — Arrange click selects track: %s\n\n"):format(pref_selects_track_label()))
end

local function print_selected_tracks()
  local tcnt = reaper.CountTracks(0)
  local sel = {}
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    if track_selected(tr) then sel[#sel+1] = track_name(tr) end
  end
  reaper.ShowConsoleMsg(("# Selected Tracks: %d\n"):format(#sel))
  if #sel > 0 then reaper.ShowConsoleMsg("  " .. table.concat(sel, ", ") .. "\n") end
  reaper.ShowConsoleMsg("\n")
end

local function print_razors_and_selected_items_per_track()
  local tcnt = reaper.CountTracks(0)
  reaper.ShowConsoleMsg("Razor Areas (TRACK-LEVEL only):\n")
  local any = false
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    local ranges = track_level_ranges(tr)
    if #ranges > 0 then
      any = true
      reaper.ShowConsoleMsg(("  - %s:\n"):format(track_name(tr)))
      for _, r in ipairs(ranges) do
        reaper.ShowConsoleMsg(("      [%s .. %s]  (%.6f .. %.6f)\n"):format(
          fmt_time(r[1]), fmt_time(r[2]), r[1], r[2]))
      end
      -- List SELECTED items on this track (take names + ranges)
      local icnt = reaper.CountTrackMediaItems(tr)
      local rows, total_sel = {}, 0
      for j = 0, icnt - 1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
          total_sel = total_sel + 1
          if #rows < MAX_ITEMS_LIST_PER_TRACK then
            local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
            local s, e = pos, pos+len
            rows[#rows+1] = string.format("%s [%s..%s]", active_take_name(it), fmt_time(s), fmt_time(e))
          end
        end
      end
      if total_sel > 0 then
        local extra = total_sel - #rows
        reaper.ShowConsoleMsg("      Selected items (take names + ranges):\n")
        for _, line in ipairs(rows) do reaper.ShowConsoleMsg("        • "..line.."\n") end
        if extra > 0 then reaper.ShowConsoleMsg(("        (+%d more)\n"):format(extra)) end
      end
    end
  end
  if not any then reaper.ShowConsoleMsg("  (none)\n") end

  -- Union
  local uni = razor_union_all_tracks()
  reaper.ShowConsoleMsg(("\nRazor UNION ranges: %d\n"):format(#uni))
  for _, r in ipairs(uni) do
    reaper.ShowConsoleMsg(("  [%s .. %s]  (%.6f .. %.6f)\n"):format(
      fmt_time(r[1]), fmt_time(r[2]), r[1], r[2]))
  end
  reaper.ShowConsoleMsg("\n")
end

local function print_selected_items_global()
  local icnt = reaper.CountMediaItems(0)
  local rows, total = {}, 0
  for i = 0, icnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      total = total + 1
      if #rows < MAX_ITEMS_LIST_GLOBAL then
        local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        local s, e = pos, pos+len
        rows[#rows+1] = string.format("%s  [%s..%s]", active_take_name(it), fmt_time(s), fmt_time(e))
      end
    end
  end
  reaper.ShowConsoleMsg(("# Selected Items: %d\n"):format(total))
  if total > 0 then
    for _, line in ipairs(rows) do reaper.ShowConsoleMsg("  • "..line.."\n") end
    local extra = total - #rows
    if extra > 0 then reaper.ShowConsoleMsg(("  (+%d more)\n"):format(extra)) end
  end
  local has_rng, s, e = compute_item_sel_range()
  if has_rng then
    reaper.ShowConsoleMsg(("  Computed item range: [%s .. %s]  (%.6f .. %.6f)\n\n"):format(
      fmt_time(s), fmt_time(e), s, e))
  else
    reaper.ShowConsoleMsg("  Computed item range: (none)\n\n")
  end
end

local function print_link_summary()
  local on_raz_it, on_trk = false, false
  for _, rec in ipairs(SCRIPTS) do
    local on = (get_toggle_txt(rec[2]) == "ON")
    if rec[3] == "razor_item" then on_raz_it = on end
    if rec[3] == "track_razor_item" then on_trk = on end
  end
  reaper.ShowConsoleMsg("Link summary:\n")
  reaper.ShowConsoleMsg(string.format("  Razor >> Item link: %s\n", on_raz_it and "ACTIVE" or "OFF"))
  reaper.ShowConsoleMsg(string.format("  Track <> Razor+Item link: %s\n", on_trk and "ACTIVE" or "OFF"))
end

local function print_snapshot()
  reaper.ClearConsole()
  reaper.ShowConsoleMsg("=== Track • Razor • Item LINK — MONITOR ===\n")
  print_script_toggles()
  print_pref_state()
  print_selected_tracks()
  print_razors_and_selected_items_per_track()
  print_selected_items_global()
  print_link_summary()
end

-----------------
-- Change watcher
-----------------
local last_sig = ""
local function build_sig()
  return table.concat({
    sig_tracks_selected(),
    sig_items_selected(),
    sig_razor_all(),
    sig_scripts_toggle(),
    sig_pref_selects_track(),   -- include preference in signature
  }, "||")
end

-----------------
-- Tiny Cancel UI
-----------------
local GFX_W, GFX_H = 420, 64
local BTN_W, BTN_H = 96, 26
local BTN_X, BTN_Y = GFX_W - BTN_W - 12, 12
local prev_cap = 0

local function btn_clicked(x,y,w,h)
  local mx,my = gfx.mouse_x, gfx.mouse_y
  local over  = (mx>=x and mx<=x+w and my>=y and my<=y+h)
  local cap   = gfx.mouse_cap
  local clicked = over and (prev_cap&1==0) and (cap&1==1)
  prev_cap = cap
  return clicked
end

local function draw_cancel_ui()
  gfx.set(0.12,0.12,0.12,1); gfx.rect(0,0,GFX_W,GFX_H,1)
  gfx.set(0.9,0.9,0.9,1); gfx.x=12; gfx.y=12
  gfx.drawstr("Monitor running... ESC or click Cancel to quit")
  -- button
  gfx.set(0.15,0.15,0.15,1); gfx.rect(BTN_X,BTN_Y,BTN_W,BTN_H,1)
  gfx.set(0.55,0.55,0.55,1); gfx.rect(BTN_X,BTN_Y,BTN_W,BTN_H,0)
  gfx.x = BTN_X+20; gfx.y = BTN_Y+6; gfx.set(0.9,0.9,0.9,1); gfx.drawstr("Cancel")
  gfx.update()
  if btn_clicked(BTN_X,BTN_Y,BTN_W,BTN_H) then return true end
  local ch = gfx.getchar()
  if ch == 27 or ch == -1 then return true end
  return false
end

-----------------
-- Main loop
-----------------
local function loop()
  -- Cancel UI
  if draw_cancel_ui() then
    gfx.quit()
    -- keep console content; just stop
    return
  end

  local cur = build_sig()
  if cur ~= last_sig then
    print_snapshot()
    last_sig = cur
  end
  reaper.defer(loop)
end

-- Kick off
gfx.init("Track • Razor • Item LINK — MONITOR (ESC/Cancel)", GFX_W, GFX_H, 0, 100, 100)
reaper.ShowConsoleMsg("") -- ensure console exists
print_snapshot()
last_sig = build_sig()
loop()
