--[[
@description Conform List Browser - CLB Waveform Check (compare conformed ISO audio with the AAF's audio; markers, mute verified AAF items)
@version 26.1104.0911pre1
@author hsuanice
@noindex
@changelog
  - Initial release (pairs by track number; checks every overlapping event)
@about
  Checks a conform by waveform: every AAF item (the editor's audio, on the "AAF - ..." tracks
  that CLB generates) is compared with the conformed ISO items under it (items CLB placed with
  Conform, carrying CLB_EVENT).

  Use: run it with nothing selected to check every AAF item (or only those inside the time
  selection), or select AAF items to check just those.
  - Pairing: an AAF track "AAF - A1" is compared with the conformed tracks whose name has the
    same track label ("EDL - A1", or "EDL - A1 - 1", "EDL - A1 - 2" ... after exploding takes);
    "AAF - A3_L" / "AAF - A3_R" count as A3. When no track has that label, or nothing is
    conformed under an AAF item on it (e.g. A2 = the other channel of A1's mix, removed by
    Remove Dups), or no clear match there (tracks packed by Consolidate), with all conformed
    tracks. Every conformed event under an AAF item is checked, every channel on its own (each
    take of a conformed item - one per ISO channel - or one track per channel after exploding
    takes); the channel closest to the AAF gives the result (any channel on the sample = in sync).
  - The offset is found by cross-correlation (GCC-PHAT, Waveform Sync Core) within +/- the
    search range (setting, default 1 s).
  - Results:
      OK          the ISO is on the AAF's sample (+/- 1 sample)
      ~ x ms      within a frame but not on the sample - usually a channel that Auto Align
                  Post moved, or a mic further away; normal for those channels
      SYNC +2f    one frame or more out (ISO early / late)
      NO MATCH    no clear match: another take, or not the same sound
      ?           too short (under 0.25 s) or silent to tell
      NO AUDIO    nothing conformed under this AAF item
    "cut differs" is added when the conformed event covers only part of the AAF item (the part
    a crossfade adds to the AAF item does not count).
  - Markers (setting): project markers or take markers on the AAF items, named "WC ...";
    the previous "WC" markers there are replaced on every run.
  - Fix ISO (setting, on by default): after the check, a question lists what is out (any offset
    of a sample or more: OK +/- 1 sample, ~ x ms and SYNC) and, on Yes, slides the conformed
    ISO content onto the AAF: every take of the event's items (all ISO channels together, so
    their relation stays as it is) moves by the measured offset inside the item - the item's
    start and end stay where they are, and the AAF is never changed. The item note gets a
    "WC: content slid ..." line. Locked items, and items whose content would start before the
    file's start, are left as they are and listed. Running the check again then shows OK.
  - Mute verified (setting, on by default): AAF items whose conformed audio matched (OK or
    ~ x ms, or fixed) are muted, so what is left playing still needs a look. Items are never
    unmuted.
  - Results are also printed in the ReaScript console. Everything is one undo point.
  - Progress window (native gfx); Esc or closing it cancels with nothing changed.

  Requires the hsuanice Library package.

  Written with Claude Code (AI); designed and tested by hsuanice.
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Waveform Sync Core.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

local r = reaper
local WS = dofile(r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Waveform Sync Core.lua")
local TITLE = "CLB Waveform Check"
local NS = "hsuanice_CLB_WaveCheck"
local MARK = "WC "            -- prefix of every marker this script writes
local MIN_OVERLAP = 0.1       -- seconds of overlap for a conformed item to count

---------------------------------------------------------------------------
-- Tracks and items
---------------------------------------------------------------------------
local function track_name(tr) return select(2, r.GetTrackName(tr)) end

local function tokens(name)
  local t = {}
  for part in (name .. " - "):gmatch("(.-)%s+%-%s+") do t[#t + 1] = part end
  return t
end

-- "AAF - A1" -> "A1"; "AAF - A3_L" / "AAF - A3_R" -> "A3" (the stereo clips of the
-- editor's track A3); nil for other tracks
local function aaf_label(name)
  local t = tokens(name)
  if t[1] == "AAF" and t[2] and t[2] ~= "" then return (t[2]:gsub("_[LR]$", "")) end
end

local function span(item)
  local p = r.GetMediaItemInfo_Value(item, "D_POSITION")
  return p, p + r.GetMediaItemInfo_Value(item, "D_LENGTH")
end

local function file_take(item)
  local tk = r.GetActiveTake(item)
  if not tk or r.TakeIsMIDI(tk) then return nil end
  local src = r.GetMediaItemTake_Source(tk)
  local fn = src and r.GetMediaSourceFileName(src, "") or ""
  return fn ~= "" and tk or nil
end

local function take_name(item)
  local tk = r.GetActiveTake(item)
  return tk and r.GetTakeName(tk) or "(empty item)"
end

local ref_tracks, conf_tracks = {}, {}
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  local name = track_name(tr)
  local label = aaf_label(name)
  if label then
    ref_tracks[#ref_tracks + 1] = { track = tr, label = label, name = name }
  else
    -- conformed takes: every take carrying CLB_EVENT (written by CLB Conform) -
    -- an item holds one take per ISO channel, and each channel is checked
    local items = {}
    for j = 0, r.CountTrackMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, j)
      local s, e = span(it)
      for t = 0, r.CountTakes(it) - 1 do
        local tk = r.GetTake(it, t)
        local src = tk and not r.TakeIsMIDI(tk) and r.GetMediaItemTake_Source(tk)
        if src and (r.GetMediaSourceFileName(src, "") or "") ~= "" then
          local _, ev = r.GetSetMediaItemTakeInfo_String(tk, "P_EXT:CLB_EVENT", "", false)
          if ev ~= "" then
            items[#items + 1] = { item = it, take = tk, s = s, e = e, event = ev, name = r.GetTakeName(tk) }
          end
        end
      end
    end
    if #items > 0 then
      local set = {}
      for _, tkn in ipairs(tokens(name)) do set[tkn] = true end
      conf_tracks[#conf_tracks + 1] = { track = tr, name = name, items = items, labels = set }
    end
  end
end
if #ref_tracks == 0 then
  r.MB('No AAF tracks found.\n\nThe editor\'s audio is expected on tracks named "AAF - A1", "AAF - A2" ... '
    .. '(CLB: load the AAF and Generate Items / Conform).', TITLE, 0)
  return
end
if #conf_tracks == 0 then
  r.MB("No conformed items found (items placed by CLB Conform carry CLB_EVENT).", TITLE, 0)
  return
end

-- AAF items to check: selected ones on AAF tracks; else those in the time selection; else all
local is_ref, label_of = {}, {}
for _, rt in ipairs(ref_tracks) do is_ref[rt.track] = true; label_of[rt.track] = rt.label end
local checks = {}
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local it = r.GetSelectedMediaItem(0, i)
  if is_ref[r.GetMediaItem_Track(it)] and file_take(it) then checks[#checks + 1] = { item = it } end
end
local scope = "selected AAF items"
if #checks == 0 then
  local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local use_ts = te > ts
  scope = use_ts and "AAF items in the time selection" or "all AAF items"
  for _, rt in ipairs(ref_tracks) do
    for j = 0, r.CountTrackMediaItems(rt.track) - 1 do
      local it = r.GetTrackMediaItem(rt.track, j)
      local s, e = span(it)
      if file_take(it) and (not use_ts or (e > ts and s < te)) then checks[#checks + 1] = { item = it } end
    end
  end
end
if #checks == 0 then
  r.MB("No AAF items to check (" .. scope .. ").", TITLE, 0)
  return
end
table.sort(checks, function(a, b) return span(a.item) < span(b.item) end)

-- Conformed tracks compared with an AAF track: same label, else all
local tracks_for = {}
local function targets_for(label)
  if tracks_for[label] then return tracks_for[label] end
  local list = {}
  for _, ct in ipairs(conf_tracks) do if ct.labels[label] then list[#list + 1] = ct end end
  if #list == 0 then list = conf_tracks end
  tracks_for[label] = list
  return list
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local mark_def = r.GetExtState(NS, "MARKERS")
local lag_def = r.GetExtState(NS, "MAX_LAG")
local mute_def = r.GetExtState(NS, "MUTE")
local fix_def = r.GetExtState(NS, "FIX")
local ok_in, csv = r.GetUserInputs(TITLE .. " - " .. #checks .. " " .. scope, 4,
  "Markers (project / take / none),Max search +/- (seconds),Mute verified AAF items (y/n),"
    .. "Fix ISO: slide onto AAF (y/n),extrawidth=60",
  (mark_def ~= "" and mark_def or "project") .. "," .. (lag_def ~= "" and lag_def or "1") .. ","
    .. (mute_def ~= "" and mute_def or "y") .. "," .. (fix_def ~= "" and fix_def or "y"))
if not ok_in then return end
local mark_s, lag_s, mute_s, fix_s = csv:match("^([^,]*),([^,]*),([^,]*),([^,]*)$")
local MARKERS = (mark_s or ""):lower():match("^%s*(%a)") or "p"
MARKERS = (MARKERS == "t" and "take") or (MARKERS == "n" and "none") or "project"
local MAX_LAG = math.max(0.1, math.min(tonumber(lag_s) or 1, 10))
local MUTE = (mute_s or "y"):lower():match("^%s*n") == nil
r.SetExtState(NS, "MARKERS", MARKERS, true)
r.SetExtState(NS, "MAX_LAG", tostring(MAX_LAG), true)
local FIX = (fix_s or "y"):lower():match("^%s*n") == nil
r.SetExtState(NS, "MUTE", MUTE and "y" or "n", true)
r.SetExtState(NS, "FIX", FIX and "y" or "n", true)
WS.MAX_LAG_SEC = MAX_LAG
WS.MIN_SPAN_SEC = 0.25        -- dialogue pieces under a second are checked too
WS.CHUNK_SEC = math.min(10, 32768 / WS.COARSE_SR - 2 * MAX_LAG - 0.1)

local FPS = r.TimeMap_curFrameRate(0)
if not FPS or FPS <= 0 then FPS = 24 end

---------------------------------------------------------------------------
-- Analysis (one AAF item per defer cycle; the accessor reads nothing inside a coroutine)
---------------------------------------------------------------------------
local function fmt_off(res)
  local smp, sec = res.samples, res.offset
  local dir = sec > 0 and "ISO early" or "ISO late"
  if math.abs(sec) * FPS < 1 then return string.format("%+.2f ms", sec * 1000), dir end
  local f = math.floor(math.abs(sec) * FPS + 0.5)
  return string.format("%s%df (%+d smp)", sec < 0 and "-" or "+", f, smp), dir
end

local function analyse(c)
  local item = c.item
  local rs, re = span(item)
  c.rs, c.re = rs, re
  -- a crossfade extends the AAF item past the list's cut (half the fade each
  -- side): that part is not "cut differs"
  local fade = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") + r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  local function partial(ov) return ov < (re - rs) - fade - 2 / FPS end
  -- conformed event overlapping this AAF item most
  local events = {}
  local function collect(tracks)
    for _, ct in ipairs(tracks) do
      for _, ti in ipairs(ct.items) do
        local ov = math.min(re, ti.e) - math.max(rs, ti.s)
        if ov >= MIN_OVERLAP then
          -- one event = its number at one position (several list files can share numbers)
          local key = ti.event .. "@" .. string.format("%.4f", ti.s)
          local g = events[key]
          if not g then g = { event = ti.event, ov = 0, items = {} }; events[key] = g end
          g.ov = math.max(g.ov, ov)
          g.items[#g.items + 1] = { ti = ti, track = ct.name }
        end
      end
    end
  end
  -- every overlapping event is checked (several tracks can overlap here),
  -- most overlap first; the clearest channel of any of them gives the result
  local ref = { { take = r.GetActiveTake(item), pos = rs } }
  local list, done = {}, {}
  local best, best_g, best_why
  local function check_events()
    local new = {}
    for ev, g in pairs(events) do if not done[ev] then done[ev] = true; new[#new + 1] = g end end
    table.sort(new, function(a, b) return a.ov > b.ov end)
    for _, g in ipairs(new) do
      list[#list + 1] = g
      for _, x in ipairs(g.items) do
        local ti = x.ti
        local s, e = math.max(rs, ti.s), math.min(re, ti.e)
        local res = WS.find_offset(ref, { { take = ti.take, pos = ti.s } }, s, e, { fps = FPS })
        res.track, res.file = x.track, ti.name
        if res.ok then
          -- the channel closest to the AAF wins (any channel on the sample = in
          -- sync; the others are Auto Align-moved or further mics); ties: clearest
          local d, bd = math.abs(res.samples), best and math.abs(best.samples)
          if not best or d < bd or (d == bd and res.ratio > best.ratio) then best, best_g = res, g end
        elseif not best_why then
          best_why = res
        end
      end
    end
  end
  collect(targets_for(label_of[r.GetMediaItem_Track(item)]))
  check_events()
  -- no clear match on the same track number (A2 = the other channel of A1's
  -- mix removed by Remove Dups, or tracks packed by Consolidate): every
  -- conformed track
  if not best then collect(conf_tracks); check_events() end
  if #list == 0 then c.kind = "NO AUDIO"; return end
  if not best then
    local why = best_why and best_why.reason or "no result"
    c.kind = (why == "too short" or why:find("silent", 1, true)) and "?" or "NO MATCH"
    c.why = why
    c.file = list[1].items[1] and list[1].items[1].ti.name
    c.partial = partial(list[1].ov)
    return
  end
  c.event = best_g.event
  c.group = best_g
  c.partial = partial(best_g.ov)
  c.res = best
  if math.abs(best.samples) <= 1 then c.kind = "OK"
  elseif math.abs(best.offset) * FPS < 1 then c.kind = "~"
  else c.kind = "SYNC" end
end

local PROG = { i = 0, n = #checks, label = "", cancel = false }
local W, H = 460, 96
local function draw()
  gfx.set(0.16, 0.16, 0.17, 1); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  gfx.setfont(1, "Arial", 15)
  gfx.set(0.9, 0.9, 0.9, 1)
  gfx.x, gfx.y = 12, 10
  gfx.drawstr(PROG.cancel and "Cancelling..." or string.format("Checking waveforms %d / %d", PROG.i, PROG.n))
  gfx.set(0.6, 0.6, 0.6, 1)
  gfx.x, gfx.y = 12, 30
  local label = PROG.label
  while #label > 4 and gfx.measurestr(label) > gfx.w - 24 do label = label:sub(1, -5) .. "..." end
  gfx.drawstr(label)
  local frac = PROG.n > 0 and PROG.i / PROG.n or 0
  gfx.set(0.3, 0.3, 0.32, 1); gfx.rect(12, 52, gfx.w - 70, 12, 1)
  gfx.set(0.30, 0.58, 0.92, 1); gfx.rect(12, 52, math.floor((gfx.w - 70) * frac), 12, 1)
  gfx.set(0.9, 0.9, 0.9, 1)
  gfx.x, gfx.y = gfx.w - 50, 50
  gfx.drawstr(string.format("%d%%", math.floor(frac * 100)))
  gfx.set(0.5, 0.5, 0.5, 1)
  gfx.x, gfx.y = 12, 72
  gfx.drawstr("Esc or close = cancel (nothing is changed)")
  gfx.update()
end

---------------------------------------------------------------------------
-- Apply: markers, mute, console
---------------------------------------------------------------------------
local COLORS = {
  ["OK"] = { 60, 180, 90 }, ["~"] = { 220, 190, 60 }, ["SYNC"] = { 220, 70, 60 },
  ["NO MATCH"] = { 220, 70, 60 }, ["?"] = { 150, 150, 150 }, ["NO AUDIO"] = { 110, 110, 110 },
}

local function result_text(c)
  local t
  if c.kind == "OK" then
    t = "OK " .. (c.res.track or "")
  elseif c.kind == "~" or c.kind == "SYNC" then
    local off, dir = fmt_off(c.res)
    t = (c.kind == "~" and "~ " or "SYNC ") .. off .. " " .. dir .. " " .. (c.res.track or "")
  elseif c.kind == "NO MATCH" or c.kind == "?" then
    t = c.kind .. " (" .. (c.why or "") .. ")"
  else
    t = c.kind
  end
  if c.partial then t = t .. ", cut differs" end
  return t
end

local function tc(pos) return r.format_timestr_pos(pos, "", 5) end

local function clear_markers(lo, hi)
  if MARKERS == "project" then
    local _, nm, nr = r.CountProjectMarkers(0)
    for idx = nm + nr - 1, 0, -1 do
      local _, isrgn, pos, _, name, num = r.EnumProjectMarkers(idx)
      if not isrgn and name:sub(1, #MARK) == MARK and pos >= lo - 1e-6 and pos <= hi + 1e-6 then
        r.DeleteProjectMarker(0, num, false)
      end
    end
  end
end

-- Fixes: every conformed item of an event that is out by a sample or more, with
-- the offset of the AAF item that overlaps it most (an event under two AAF
-- items moves once)
local function plan_fixes()
  local by_item, order = {}, {}
  for _, c in ipairs(checks) do
    if c.res and c.group and math.abs(c.res.samples) >= 1 then
      for _, x in ipairs(c.group.items) do
        local it = x.ti.item
        local f = by_item[it]
        if not f then order[#order + 1] = it end
        if not f or c.group.ov > f.ov then by_item[it] = { item = it, c = c, ov = c.group.ov } end
      end
    end
  end
  local list, events = {}, {}
  for _, it in ipairs(order) do
    list[#list + 1] = by_item[it]
    events[by_item[it].c] = true
  end
  local n_ev = 0
  for _ in pairs(events) do n_ev = n_ev + 1 end
  return list, n_ev
end

-- Slide every take of the item by the offset inside the item (edges stay)
local function slide(f)
  local it, off = f.item, f.c.res.offset
  if r.GetMediaItemInfo_Value(it, "C_LOCK") % 2 == 1 then return "locked" end
  local new = {}
  for t = 0, r.CountTakes(it) - 1 do
    local tk = r.GetTake(it, t)
    if tk then
      local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
        - off * r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
      if offs < -1e-9 then return "would start before the file's start" end
      new[#new + 1] = { tk, math.max(0, offs) }
    end
  end
  for _, x in ipairs(new) do r.SetMediaItemTakeInfo_Value(x[1], "D_STARTOFFS", x[2]) end
  local _, note = r.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
  note = (note ~= "" and (note:gsub("%s+$", "") .. "\n") or "")
    .. string.format("WC: content slid %+d smp at %d Hz (%+.2f ms) onto the AAF",
      f.c.res.samples, f.c.res.sr or 0, off * 1000)
  r.GetSetMediaItemInfo_String(it, "P_NOTES", note, true)
  f.c.fixed = true
end

local function apply(fixes)
  local counts, lines, muted = {}, {}, 0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local fixed_items, not_fixed = 0, {}
  for _, f in ipairs(fixes or {}) do
    local why = slide(f)
    if why then
      not_fixed[#not_fixed + 1] = string.format("%s  %s: not moved, %s", tc(r.GetMediaItemInfo_Value(f.item, "D_POSITION")),
        take_name(f.item), why)
    else
      fixed_items = fixed_items + 1
    end
  end
  local lo, hi = math.huge, -math.huge
  for _, c in ipairs(checks) do lo, hi = math.min(lo, c.rs), math.max(hi, c.rs) end
  clear_markers(lo, hi)
  for _, c in ipairs(checks) do
    counts[c.kind] = (counts[c.kind] or 0) + 1
    local text = (c.fixed and "FIXED " or "") .. result_text(c)
    local col = COLORS[c.kind] or COLORS["?"]
    local native = r.ColorToNative(col[1], col[2], col[3]) | 0x1000000
    if MARKERS == "project" then
      r.AddProjectMarker2(0, false, c.rs, 0, MARK .. text, -1, native)
    elseif MARKERS == "take" then
      local tk = r.GetActiveTake(c.item)
      for m = r.GetNumTakeMarkers(tk) - 1, 0, -1 do
        local _, name = r.GetTakeMarker(tk, m)
        if name:sub(1, #MARK) == MARK then r.DeleteTakeMarker(tk, m) end
      end
      r.SetTakeMarker(tk, -1, MARK .. text, r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"), native)
    end
    local verified = c.kind == "OK" or c.kind == "~" or c.fixed
    if MUTE and verified and r.GetMediaItemInfo_Value(c.item, "B_MUTE") == 0 then
      r.SetMediaItemInfo_Value(c.item, "B_MUTE", 1)
      muted = muted + 1
    end
    if c.kind ~= "OK" then
      lines[#lines + 1] = string.format("%s  %-24s %s%s", tc(c.rs), take_name(c.item), text,
        c.file and ("  [" .. c.file .. "]") or (c.res and c.res.file and ("  [" .. c.res.file .. "]") or ""))
    end
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("CLB Waveform Check", -1)
  local summary = {}
  for _, k in ipairs({ "OK", "~", "SYNC", "NO MATCH", "?", "NO AUDIO" }) do
    if counts[k] then summary[#summary + 1] = string.format("%s %d", k, counts[k]) end
  end
  for _, l in ipairs(not_fixed) do lines[#lines + 1] = l end
  table.insert(lines, 1, string.format("Checked %d %s (search +/- %g s). %s\nAAF items muted: %d\n"
    .. "ISO items slid onto the AAF: %d%s%s\n",
    #checks, scope, MAX_LAG, table.concat(summary, ", "), muted, fixed_items,
    #not_fixed > 0 and string.format(" (%d not moved, listed at the end)", #not_fixed) or "",
    #lines > 0 and "\n\nNot OK (OK lines are not listed; FIXED = slid onto the AAF):" or ""))
  return lines
end

local function show_lines(lines)
  r.ShowConsoleMsg("\n=== " .. TITLE .. "  " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n"
    .. table.concat(lines, "\n") .. "\n")
end

local window = false
local next_i = 1
local function finish()
  if window then gfx.quit() end
  if PROG.cancel then return end
  local fixes = {}
  if FIX then
    local list, n_ev = plan_fixes()
    if #list > 0 then
      local ans = r.MB(string.format("%d event(s) are out by a sample or more (%d conformed item(s)).\n\n"
        .. "Slide their ISO content onto the AAF?\n"
        .. "The items' start and end stay; all ISO channels of an event move together; the AAF is not changed.\n\n"
        .. "Yes = slide and mark, No = only mark, Cancel = nothing", n_ev, #list), TITLE, 3)
      if ans == 2 then return end
      if ans == 6 then fixes = list end
    end
  end
  local lines = apply(fixes)
  r.defer(function() show_lines(lines) end)
end

local function step()
  if window then
    local ch = gfx.getchar()
    if ch == 27 or ch < 0 then PROG.cancel = true end
  end
  if PROG.cancel or next_i > #checks then return finish() end
  local c = checks[next_i]
  next_i = next_i + 1
  PROG.i, PROG.label = next_i - 1, take_name(c.item)
  analyse(c)
  if next_i > #checks then return finish() end
  if not window then gfx.init(TITLE, W, H); window = true end
  draw()
  r.defer(step)
end
step()
