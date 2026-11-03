--[[
@description Dual Recorder Sync - DRS Waveform Sync (move a second recorder's items onto the reference by waveform, optional length match)
@version 26.1103.1543pre1
@author hsuanice
@provides
  [main] .
  [main] hsuanice_Dual Recorder Sync - DRS Set Reference Track.lua
@changelog
  - Change: the results are printed in the ReaScript console instead of a message box.
  - Tested by hsuanice on 9 takes (75-1 to 75-5): all synced, drift 0.0 frames.
@about
  Syncs the items of a second recorder to the first recorder by waveform, when the second
  recorder's timecode is right but its recording started late (or early).

  Setup: the first recorder records the second recorder's mix on one channel (e.g. "Ch 10 -
  2nd mix-in"). Select that track and run "Dual Recorder Sync - DRS Set Reference Track"
  (saved in the project).

  Use: select the second recorder's items (any number of takes, all their channels) and run
  this script.
  - Each selected item is paired with the reference item it overlaps most; all selected items
    on the same reference item are one take and move together (summed to mono for the match).
  - The offset is found by cross-correlation (GCC-PHAT: timing only, level and EQ do not
    matter): a coarse pass over +/- 10 s (setting), then sample-accurate at the source rate.
    It is checked on the loudest part near the start and near the end of the take.
  - Never guessed: a take is NOT moved when no clear match is found, or when the start and
    end checks disagree by more than 1 frame (clock drift or a wrong match). Those takes are
    listed for a manual check (Auto Align Post can do the rest).
  - Match length (setting, on by default): after the move, each item gets the reference item's
    start and length - "Loop source" is turned off first, so added space is silence, and the
    excess is trimmed. Timecode then equals the reference: render with RGWH TC mode "current".
  - The offset is written in each item's note ("DRS: +3s16f ..."); the results are printed in
    the ReaScript console.
  - Progress window (native gfx); Esc or closing it cancels with nothing changed. All moves are
    applied together at the end: one undo point. Locked items are skipped and listed.

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
local TITLE = "Dual Recorder Sync"
local NS, KEY = "hsuanice_DRS", "REF_TRACK"

---------------------------------------------------------------------------
-- Reference track and selection
---------------------------------------------------------------------------
local function ref_track()
  local _, guid = r.GetProjExtState(0, NS, KEY)
  if guid == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if r.GetTrackGUID(t) == guid then return t end
  end
end

local function take_name(item)
  local tk = r.GetActiveTake(item)
  return tk and r.GetTakeName(tk) or "(empty item)"
end

local REF = ref_track()
if not REF then
  r.MB('No reference track yet.\n\nSelect the track with the second recorder\'s mix (e.g. "2nd mix-in") '
    .. 'and run "Dual Recorder Sync - DRS Set Reference Track" first.', TITLE, 0)
  return
end
local _, REF_NAME = r.GetTrackName(REF)

local function span(item)
  local p = r.GetMediaItemInfo_Value(item, "D_POSITION")
  return p, p + r.GetMediaItemInfo_Value(item, "D_LENGTH")
end

-- Reference item a target item overlaps most
local function best_ref(item)
  local s, e = span(item)
  local best, best_ov = nil, 0
  for i = 0, r.CountTrackMediaItems(REF) - 1 do
    local it = r.GetTrackMediaItem(REF, i)
    local rs, re = span(it)
    local ov = math.min(e, re) - math.max(s, rs)
    if ov > best_ov and r.GetActiveTake(it) then best, best_ov = it, ov end
  end
  return best
end

local groups, by_ref, skipped = {}, {}, {}
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local it = r.GetSelectedMediaItem(0, i)
  if r.GetMediaItem_Track(it) ~= REF then
    if not r.GetActiveTake(it) or r.TakeIsMIDI(r.GetActiveTake(it)) then
      skipped[#skipped + 1] = take_name(it) .. ": not an audio item"
    else
      local ref = best_ref(it)
      if not ref then
        skipped[#skipped + 1] = take_name(it) .. ": no reference item on '" .. REF_NAME .. "'"
      else
        local g = by_ref[ref]
        if not g then
          g = { ref = ref, items = {} }
          by_ref[ref] = g
          groups[#groups + 1] = g
        end
        g.items[#g.items + 1] = it
      end
    end
  end
end
if #groups == 0 then
  r.MB("Select the second recorder's items to sync (not the reference track '" .. REF_NAME .. "')."
    .. (#skipped > 0 and ("\n\n" .. table.concat(skipped, "\n")) or ""), TITLE, 0)
  return
end
table.sort(groups, function(a, b) return span(a.ref) < span(b.ref) end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local match_def = r.GetExtState(NS, "MATCH_LENGTH")
local lag_def = r.GetExtState(NS, "MAX_LAG")
local ok_in, csv = r.GetUserInputs(TITLE .. " - ref: " .. REF_NAME, 2,
  "Match length to reference (y/n),Max search +/- (seconds),extrawidth=60",
  (match_def ~= "" and match_def or "y") .. "," .. (lag_def ~= "" and lag_def or "10"))
if not ok_in then return end
local match_s, lag_s = csv:match("^([^,]*),([^,]*)$")
local MATCH_LENGTH = (match_s or "y"):lower():sub(1, 1) ~= "n"
local MAX_LAG = tonumber(lag_s) or 10
MAX_LAG = math.max(1, math.min(MAX_LAG, 15))   -- 15 s keeps the coarse pass inside one FFT
r.SetExtState(NS, "MATCH_LENGTH", MATCH_LENGTH and "y" or "n", true)
r.SetExtState(NS, "MAX_LAG", tostring(MAX_LAG), true)
WS.MAX_LAG_SEC = MAX_LAG
WS.CHUNK_SEC = math.min(10, 32768 / WS.COARSE_SR - 2 * MAX_LAG - 0.1)

local FPS = r.TimeMap_curFrameRate(0)
if not FPS or FPS <= 0 then FPS = 24 end

local function fmt_off(sec)
  local sign = sec < 0 and "-" or "+"
  local a = math.abs(sec)
  local s = math.floor(a)
  local f = math.floor((a - s) * FPS + 0.5)
  if f >= math.floor(FPS + 0.5) then s, f = s + 1, 0 end
  return string.format("%s%ds%02df", sign, s, f)
end

---------------------------------------------------------------------------
-- Analysis (one take per defer cycle; the accessor reads nothing inside a coroutine)
---------------------------------------------------------------------------
local function analyse(g)
  local s, e = math.huge, -math.huge
  local tgt = {}
  for _, it in ipairs(g.items) do
    local a, b = span(it)
    s, e = math.min(s, a), math.max(e, b)
    tgt[#tgt + 1] = { take = r.GetActiveTake(it), pos = a }
  end
  local rs, re = span(g.ref)
  local ref = { { take = r.GetActiveTake(g.ref), pos = rs } }
  -- only the part that can overlap the reference within the search range
  s = math.max(s, rs - MAX_LAG)
  e = math.min(e, re + MAX_LAG)
  g.res = WS.find_offset(ref, tgt, s, e, { fps = FPS })
end

local PROG = { i = 0, n = #groups, label = "", cancel = false }
local W, H = 460, 96
local function draw()
  gfx.set(0.16, 0.16, 0.17, 1); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  gfx.setfont(1, "Arial", 15)
  gfx.set(0.9, 0.9, 0.9, 1)
  gfx.x, gfx.y = 12, 10
  gfx.drawstr(PROG.cancel and "Cancelling..." or string.format("Matching waveforms %d / %d", PROG.i, PROG.n))
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
-- Apply
---------------------------------------------------------------------------
local function append_note(item, line)
  local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  note = (note ~= "" and (note:gsub("%s+$", "") .. "\n") or "") .. line
  r.GetSetMediaItemInfo_String(item, "P_NOTES", note, true)
end

local function apply()
  local lines, moved = {}, 0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, g in ipairs(groups) do
    local res = g.res or {}
    local name = take_name(g.items[1])
    if not res.ok then
      lines[#lines + 1] = "NOT MOVED  " .. name .. ": " .. (res.reason or "no result")
      for _, c in ipairs(res.checks or {}) do
        if not c.failed then lines[#lines + 1] = "    check: " .. fmt_off(c.offset) end
      end
    else
      local rs, re = span(g.ref)
      local drift = res.drift and string.format(", drift %+.1f f", res.drift * FPS) or ", checked once"
      local text = string.format("%s (%+d smp @ %d Hz)", fmt_off(res.offset), res.samples, res.sr)
      local locked = 0
      for _, it in ipairs(g.items) do
        if r.GetMediaItemInfo_Value(it, "C_LOCK") % 2 == 1 then
          locked = locked + 1
        else
          local p = r.GetMediaItemInfo_Value(it, "D_POSITION") + res.offset
          if MATCH_LENGTH then
            r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)          -- added space = silence
            for t = 0, r.CountTakes(it) - 1 do
              local tk = r.GetTake(it, t)
              if tk then
                local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
                local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
                r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", offs - (p - rs) * rate)
              end
            end
            r.SetMediaItemInfo_Value(it, "D_POSITION", rs)
            r.SetMediaItemInfo_Value(it, "D_LENGTH", re - rs)
          else
            r.SetMediaItemInfo_Value(it, "D_POSITION", p)
          end
          append_note(it, "DRS: " .. text .. " to " .. take_name(g.ref)
            .. (MATCH_LENGTH and ", length matched" or ""))
          moved = moved + 1
        end
      end
      lines[#lines + 1] = string.format("%s  %s: %s%s, match %.1f", locked > 0 and "PARTLY" or "OK", name,
        text, drift, res.ratio or 0)
      if locked > 0 then lines[#lines + 1] = string.format("    %d locked item(s) skipped", locked) end
    end
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Dual Recorder Sync: waveform sync", -1)
  for _, s in ipairs(skipped) do lines[#lines + 1] = "SKIPPED  " .. s end
  table.insert(lines, 1, string.format("Reference: %s\nItems moved: %d\n", REF_NAME, moved))
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
  local lines = apply()
  r.defer(function() show_lines(lines) end)
end

local function step()
  if window then
    local ch = gfx.getchar()
    if ch == 27 or ch < 0 then PROG.cancel = true end
  end
  if PROG.cancel or next_i > #groups then return finish() end
  local g = groups[next_i]
  next_i = next_i + 1
  PROG.i, PROG.label = next_i - 1, take_name(g.items[1])
  analyse(g)
  if next_i > #groups then return finish() end
  if not window then gfx.init(TITLE, W, H); window = true end
  draw()
  r.defer(step)
end
step()
