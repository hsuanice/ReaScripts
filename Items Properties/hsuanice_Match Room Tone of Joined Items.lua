--[[
@description Match Room Tone of Joined Items - level-match the background noise of touching / crossfaded items (take volume)
@version 26.1026.1523pre1
@author hsuanice
@changelog
  - Initial release: level-match the room tone of touching / crossfaded selected items by take volume - however far apart the levels are; only groups fully in view.
  - Room tone is measured on the WHOLE source file (quietest 10 %), so movement in the trimmed pauses does not count; an item whose own part is more than 6 dB louder than its file's quietest is listed. Items that play the same file share one analysis.
  - Spectrum check: the room tone's 1/3-octave spectrum (63 Hz - 6.3 kHz, level removed) is compared with the group's median; only a different room tone (generator, air conditioning, another room, or speech all the way through) is moved to a '<track> - RT mismatch' track, with the band named.
  - Progress window (gfx), updated between items; Esc / close cancels with nothing changed; all changes applied together at the end.
  - Fix: an item was left opened up across defer cycles while measuring - REAPER drew it stretched and its audio stopped reading ('nothing to measure', no volume change). Each item is now measured in one go; items that cannot be measured are listed with the reason.
@about
  Makes the room tone of joined items the same level, so they can be glued and denoised in one
  pass (e.g. in RX) without the background jumping between takes.

  - Selected items on the same track (and fixed lane) that touch or crossfade form a group;
    a gap starts a new group. Unselected items are never changed.
  - Room tone level of an item = the mean of the quietest 10 % of its WHOLE source file (50 ms
    windows, all channels; digital silence ignored), so pauses full of movement in the trimmed
    part do not count; the item volume is included. When the item's own part is more than 6 dB
    louder than that, the item is listed (noise may change within the file).
  - Each group matches the room tone of its longest item that has pauses (quiet and loud parts),
    else of its longest item: only the take volume of the other items changes (dialogue level
    changes with it).
  - The room tone's spectrum is compared too (1/3-octave bands from 63 Hz to 6.3 kHz, level
    removed) against the group's median: an item with a different room tone - a generator, air
    conditioning, another room - is not level-matched. Different = one band more than 8 dB off
    or the bands more than 3 dB off on average. With only 2 items there is no majority: when
    they differ, both are listed and left alone.
  - The level difference alone never moves an item: the same room tone is level-matched however
    far apart (user rule 26.1026). An item with a different room tone is not adjusted: it moves
    to a track "<track> - RT mismatch" right below its track (created once, reused), so it can
    be checked by ear; the window says why (e.g. "+14 dB around 100 Hz"). An item with speech
    all the way through measures speech, whose spectrum differs, so it ends up there too.
  - The reference is chosen among the items whose room tone matches the majority.
  - Only groups fully inside the arrange view are processed (never changes what you cannot see).
  - A progress window (native gfx) shows the analysis; Esc or closing it cancels, and then
    nothing is changed. All changes are applied together at the end: one undo point. A window
    only lists what was moved or skipped.

  Take volume envelopes are not taken into account.

  Written with Claude Code (AI); designed and tested by hsuanice.
--]]
local r = reaper
local TITLE = "Match Room Tone of Joined Items"

---------------------------------------------------------------------------
-- USER OPTIONS
---------------------------------------------------------------------------
local QUIET_SHARE   = 0.10   -- the quietest share of the item that counts as room tone
local WINDOW_SEC    = 0.05   -- analysis window
local MAX_CHANGE_DB = nil    -- nil = no limit: a matching room tone is level-matched however far
                             -- (set e.g. 24 to move items needing more to the mismatch track)
local SPREAD_DB     = 10     -- quiet part this much below the loud part = the item has pauses
local ANALYSIS_SR   = 16000  -- analysis sample rate (the accessor resamples; whole files are read)
local NOTE_DIFF_DB  = 6      -- whole file this much quieter than the item's own part: listed
local MISMATCH_SUFFIX = " - RT mismatch"
-- Spectrum check: the room tone's spectral shape (level removed) against the group's median
local SPEC_BAND_DB  = 8      -- any 1/3-octave band this far off = a different room tone (e.g. generator)
local SPEC_MEAN_DB  = 3      -- or the bands this far off on average (e.g. another room)
local FFT_SIZE      = 2048   -- at ANALYSIS_SR: 7.8 Hz bins
local MAX_FFT_WINS  = 120    -- quiet windows used for the spectrum (spread over the file)
local SPEC_NEAR_DB  = 6      -- FFT windows must stay within this of the room tone level (no speech)
---------------------------------------------------------------------------

local TOL = 0.0005
local function db(x) return 20 * math.log(x, 10) end

local function track_name(tr)
  local _, n = r.GetTrackName(tr)
  return n
end

local function fmt_time(t) return r.format_timestr_pos(t, "", 5) end

-- Mean power of the quietest QUIET_SHARE of a list of window powers (dB), and whether the
-- list has pauses (its loud part is SPREAD_DB above the quiet part)
local function quiet_level(powers)
  if #powers < 4 then return nil end
  table.sort(powers)
  local n = math.max(1, math.floor(#powers * QUIET_SHARE))
  local q = 0
  for i = 1, n do q = q + powers[i] end
  q = q / n
  local loud = powers[math.max(1, math.floor(#powers * 0.9))]
  return 10 * math.log(q, 10), 10 * math.log(loud / q, 10) >= SPREAD_DB
end

-- Progress (shown in a gfx window while analyzing): the analysis runs in a coroutine that
-- yields BETWEEN items, so the window can redraw; Esc / closing the window cancels. An item is
-- always measured in one go (opened up, read, restored in the same defer cycle): an item left
-- opened up across cycles was drawn by REAPER, and its audio accessor stopped reading.
local PROG = { total = 0, done = 0, n = 0, i = 0, label = "", cancel = false, restore = nil }
local function next_item(sec)
  PROG.done = PROG.done + (sec or 0)
  if coroutine.isyieldable() then coroutine.yield() end
  return PROG.cancel
end

-- 1/3-octave bands from 63 Hz to 6.3 kHz
local BANDS = {}
for i = 0, 20 do
  local fc = 63 * 2 ^ (i / 3)
  BANDS[#BANDS + 1] = { fc = fc, lo = fc * 2 ^ (-1 / 6), hi = fc * 2 ^ (1 / 6) }
end
local HANN = {}
for i = 0, FFT_SIZE - 1 do HANN[i + 1] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (FFT_SIZE - 1)) end

local function band_label(i)
  local fc = BANDS[i].fc
  if fc >= 1000 then return string.format("%.1f kHz", fc / 1000) end
  return string.format("%d Hz", math.floor(fc / 10 + 0.5) * 10)
end

-- Band powers (dB) of the quiet windows at times `times` (mono mix, Hann window)
local function quiet_spectrum(acc, nch, times)
  local raw = r.new_array(FFT_SIZE * nch)
  local mono = r.new_array(FFT_SIZE)
  local acc_pow = {}
  for b = 1, #BANDS do acc_pow[b] = 0 end
  local bin_hz = ANALYSIS_SR / FFT_SIZE
  for _, t in ipairs(times) do
    raw.clear()
    r.GetAudioAccessorSamples(acc, ANALYSIS_SR, nch, t, FFT_SIZE, raw)
    for i = 0, FFT_SIZE - 1 do
      local v = 0
      for c = 1, nch do v = v + raw[i * nch + c] end
      mono[i + 1] = v / nch * HANN[i + 1]
    end
    mono.fft_real(FFT_SIZE, true)
    -- layout: [1],[2] = DC / Nyquist, then (re, im) pairs for bins 1 .. FFT_SIZE/2 - 1
    for k = 1, FFT_SIZE / 2 - 1 do
      local f = k * bin_hz
      local re, im = mono[2 * k + 1], mono[2 * k + 2]
      for b = 1, #BANDS do
        if f >= BANDS[b].lo and f < BANDS[b].hi then acc_pow[b] = acc_pow[b] + re * re + im * im; break end
      end
    end
  end
  local out = {}
  for b = 1, #BANDS do out[b] = 10 * math.log(acc_pow[b] / math.max(1, #times) + 1e-20, 10) end
  return out
end

-- Room tone of the whole source file of the item's take (dB, take and item volume excluded).
-- The item is opened up to the full source for the measurement (position kept, take volume 1,
-- no fades) and restored right after. Returns
--   { full = dB of the whole file, item = dB of the part the item plays, pauses = item has
--     pauses }  or nil + reason
-- Whole-file analysis is shared by every item that plays the same file at the same rate
local FILE_CACHE = {}

local function room_tone(item)
  local take = r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return nil, "no audio take" end
  local src = r.GetMediaItemTake_Source(take)
  local nch = math.max(1, math.floor(r.GetMediaSourceNumChannels(src)))
  local src_len = r.GetMediaSourceLength(src)
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate <= 0 then rate = 1 end
  local saved = {
    len = r.GetMediaItemInfo_Value(item, "D_LENGTH"),
    offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
    vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL"),
    fin = r.GetMediaItemInfo_Value(item, "D_FADEINLEN"), fout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
    fina = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO"), fouta = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO"),
  }
  if saved.len < WINDOW_SEC * 4 then return nil, "too short to measure" end
  local full_len = src_len / rate
  local item_s = saved.offs / rate                -- the item's part, in timeline seconds of the file
  local item_e = item_s + saved.len

  local key
  if not r.GetMediaSourceParent(src) then        -- a section source plays only part of its file
    key = (r.GetMediaSourceFileName(src, "") or "") .. "|" .. rate .. "|" .. nch
  end
  local cached = key and FILE_CACHE[key]
  local all, times, spec
  if cached then
    all, times, spec = cached.all, cached.times, cached.spec
  else

  -- the arrange is not redrawn while the item is opened up
  r.PreventUIRefresh(1)
  local function restore()
    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", saved.offs)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", saved.len)
    r.SetMediaItemTakeInfo_Value(take, "D_VOL", saved.vol)
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN", saved.fin)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", saved.fout)
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", saved.fina)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", saved.fouta)
    r.PreventUIRefresh(-1)
    PROG.restore = nil
  end
  PROG.restore = restore
  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", full_len)
  r.SetMediaItemTakeInfo_Value(take, "D_VOL", 1)
  for _, k in ipairs({ "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO", "D_FADEOUTLEN_AUTO" }) do
    r.SetMediaItemInfo_Value(item, k, 0)
  end
  local acc = r.CreateTakeAudioAccessor(take)
  local win = math.floor(ANALYSIS_SR * WINDOW_SEC)
  all, times = {}, {}
  local buf = r.new_array(win * nch)
  local t = 0
  while t + WINDOW_SEC <= full_len + 1e-9 do
    buf.clear()
    r.GetAudioAccessorSamples(acc, ANALYSIS_SR, nch, t, win, buf)
    local sum = 0
    for i = 1, win * nch do local v = buf[i]; sum = sum + v * v end
    local p = sum / (win * nch)
    if p > 1e-12 then                              -- digital silence (-120 dB) ignored
      all[#all + 1] = p
      times[#times + 1] = t
    end
    t = t + WINDOW_SEC
  end
  -- spectrum of the room tone: FFT windows (longer than the level windows) that stay at room
  -- tone level all the way through - every level window they cover is within SPEC_NEAR_DB of
  -- the quietest QUIET_SHARE's level - so no speech edge leaks in; not overlapping, spread over
  -- the file
  if #all >= 4 then
    local sorted = {}
    for i = 1, #all do sorted[i] = all[i] end
    table.sort(sorted)
    local n_q, q = math.max(1, math.floor(#sorted * QUIET_SHARE)), 0
    for i = 1, n_q do q = q + sorted[i] end
    local thr = q / n_q * 10 ^ (SPEC_NEAR_DB / 10)
    local span = math.ceil((FFT_SIZE / ANALYSIS_SR) / WINDOW_SEC)   -- level windows per FFT window
    local quiet, i = {}, 1
    while i + span - 1 <= #all do
      local ok = times[i] + FFT_SIZE / ANALYSIS_SR <= full_len + 1e-9
      for j = 0, span - 1 do
        if not ok then break end
        ok = all[i + j] <= thr and math.abs(times[i + j] - (times[i] + j * WINDOW_SEC)) < 1e-6
      end
      if ok then quiet[#quiet + 1] = times[i]; i = i + span else i = i + 1 end
    end
    if #quiet > MAX_FFT_WINS then
      local pick, step = {}, #quiet / MAX_FFT_WINS
      for k = 0, MAX_FFT_WINS - 1 do pick[#pick + 1] = quiet[math.floor(k * step) + 1] end
      quiet = pick
    end
    if #quiet >= 3 then spec = quiet_spectrum(acc, nch, quiet) end
  end
  r.DestroyAudioAccessor(acc)
  restore()
  if key then FILE_CACHE[key] = { all = all, times = times, spec = spec } end
  end

  local part = {}
  for i = 1, #all do
    if times[i] >= item_s - 1e-9 and times[i] + WINDOW_SEC <= item_e + 1e-9 then part[#part + 1] = all[i] end
  end

  local copy = {}
  for i = 1, #all do copy[i] = all[i] end
  local full = quiet_level(copy)
  if not full then return nil, "no audio to measure" end
  local item_db, pauses = quiet_level(part)
  return { full = full, item = item_db, pauses = pauses or false, spec = spec }
end

-- Effective room tone of an item as heard: source level x take volume x item volume
local function heard_db(info)
  return info.rt + db(math.max(1e-12, info.take_vol)) + db(math.max(1e-12, info.item_vol))
end

local function in_view(s, e)
  local vs, ve = r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  return s >= vs - TOL and e <= ve + TOL
end

-- Groups of selected items: same track and lane, touching or overlapping
local function build_groups()
  local by_lane, order = {}, {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    local tr = r.GetMediaItem_Track(it)
    local key = tostring(tr) .. "|" .. r.GetMediaItemInfo_Value(it, "I_FIXEDLANE")
    if not by_lane[key] then by_lane[key] = { track = tr, items = {} }; order[#order + 1] = key end
    local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
    table.insert(by_lane[key].items, { item = it, pos = pos, fin = pos + r.GetMediaItemInfo_Value(it, "D_LENGTH") })
  end
  local groups = {}
  for _, key in ipairs(order) do
    local lane = by_lane[key]
    table.sort(lane.items, function(a, b) return a.pos < b.pos end)
    local cur, reach
    for _, info in ipairs(lane.items) do
      if cur and info.pos <= reach + TOL then
        cur.items[#cur.items + 1] = info
        reach = math.max(reach, info.fin)
      else
        cur = { track = lane.track, items = { info } }
        groups[#groups + 1] = cur
        reach = info.fin
      end
    end
  end
  return groups
end

-- "<track> - RT mismatch" right below the track (reused when it is already there)
local function mismatch_track(tr)
  local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))   -- 1-based
  local want = track_name(tr) .. MISMATCH_SUFFIX
  local nxt = r.GetTrack(0, idx)
  if nxt and track_name(nxt) == want then return nxt end
  r.InsertTrackAtIndex(idx, true)
  local new = r.GetTrack(0, idx)
  r.GetSetMediaTrackInfo_String(new, "P_NAME", want, true)
  -- keep the folder structure: a folder's last track hands its folder end to the new track
  local depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
  if depth < 0 then
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    r.SetMediaTrackInfo_Value(new, "I_FOLDERDEPTH", depth)
  end
  return new
end

-- Seconds of audio to analyze for an item (its whole source file)
local function file_secs(item)
  local take = r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return 0 end
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  return r.GetMediaSourceLength(r.GetMediaItemTake_Source(take)) / ((rate > 0) and rate or 1)
end

-- Analyze every group (slow, yields for the progress window) and decide what to do; nothing is
-- changed here. Returns lines (for the window), actions (applied by apply_actions) or nil when
-- cancelled.
local function analyze(groups)
  local lines, actions = {}, {}
  local function note(info, tr, why)
    lines[#lines + 1] = string.format("%s @ %s: %s", track_name(tr), fmt_time(info.pos), why)
  end

  for _, g in ipairs(groups) do
    local s0, e0 = g.items[1].pos, g.items[1].fin
    for _, info in ipairs(g.items) do s0, e0 = math.min(s0, info.pos), math.max(e0, info.fin) end
    g.run = #g.items >= 2 and in_view(s0, e0)
    g.s0, g.e0 = s0, e0
    if g.run then
      for _, info in ipairs(g.items) do PROG.total, PROG.n = PROG.total + file_secs(info.item), PROG.n + 1 end
    end
  end

  for _, g in ipairs(groups) do
    local s0, e0 = g.s0, g.e0
    if PROG.cancel then return nil end
    if #g.items < 2 then
      -- a single item has nothing to match
    elseif not in_view(s0, e0) then
      note(g.items[1], g.track, "group not fully in view - skipped")
    else
      -- measure every item. Reference = the longest item with pauses (quiet and loud parts, so
      -- its quiet part is surely room tone); without one, the longest measured item
      local ref, ref_any
      for _, info in ipairs(g.items) do
        local take = r.GetActiveTake(info.item)
        PROG.i = PROG.i + 1
        PROG.label = take and r.GetTakeName(take) or ""
        if next_item() then return nil end            -- redraw the window, check for cancel
        local m, why = room_tone(info.item)
        PROG.done = PROG.done + file_secs(info.item)
        if m then
          info.rt, info.pauses = m.full, m.pauses
          if m.item and m.item - m.full > NOTE_DIFF_DB then
            note(info, g.track, string.format("own part %.1f dB louder than the quietest of its file (noise or "
              .. "movement in the pauses?) - matched by the whole file", m.item - m.full))
          end
        else
          info.why = why
        end
        info.take_vol = take and r.GetMediaItemTakeInfo_Value(take, "D_VOL") or 1
        info.item_vol = r.GetMediaItemInfo_Value(info.item, "D_VOL")
        info.len = info.fin - info.pos
        if m and m.spec then
          -- spectral shape: band levels with the overall level removed
          local mean = 0
          for b = 1, #m.spec do mean = mean + m.spec[b] end
          mean = mean / #m.spec
          info.shape = {}
          for b = 1, #m.spec do info.shape[b] = m.spec[b] - mean end
        end
      end

      -- Spectrum check against the group's median shape: a room tone that differs (generator,
      -- air conditioning, another room) is not level-matched. With 2 items there is no
      -- majority, so both are listed instead.
      local shaped = {}
      for _, info in ipairs(g.items) do if info.rt and info.shape then shaped[#shaped + 1] = info end end
      local function compare(a_shape, b_shape)
        local worst, worst_b, sum = 0, 1, 0
        for b = 1, #BANDS do
          local d = a_shape[b] - b_shape[b]
          sum = sum + math.abs(d)
          if math.abs(d) > math.abs(worst) then worst, worst_b = d, b end
        end
        local avg = sum / #BANDS
        return (math.abs(worst) > SPEC_BAND_DB or avg > SPEC_MEAN_DB), worst, worst_b, avg
      end
      if #shaped >= 3 then
        local median = {}
        for b = 1, #BANDS do
          local v = {}
          for _, info in ipairs(shaped) do v[#v + 1] = info.shape[b] end
          table.sort(v)
          median[b] = (#v % 2 == 1) and v[(#v + 1) / 2] or (v[#v / 2] + v[#v / 2 + 1]) / 2
        end
        for _, info in ipairs(shaped) do
          local off, worst, wb, avg = compare(info.shape, median)
          if off then info.spec_off = string.format("%+.1f dB around %s (bands %.1f dB off on average)", worst, band_label(wb), avg) end
        end
      elseif #shaped == 2 then
        local off, worst, wb, avg = compare(shaped[1].shape, shaped[2].shape)
        if off then
          for _, info in ipairs(shaped) do
            info.spec_pair = string.format("the two items' room tone differs (%+.1f dB around %s, %.1f dB on average) - "
              .. "not matched, check by ear", worst, band_label(wb), avg)
          end
        end
      end

      local ref, ref_any
      for _, info in ipairs(g.items) do
        if info.rt and not info.spec_off and not info.spec_pair then
          if info.pauses and (not ref or info.len > ref.len) then ref = info end
          if not ref_any or info.len > ref_any.len then ref_any = info end
        end
      end
      ref = ref or ref_any
      if not ref then
        if shaped[1] and shaped[1].spec_pair then
          note(shaped[1], g.track, shaped[1].spec_pair)
          note(shaped[2], g.track, shaped[2].spec_pair)
        else
          for _, info in ipairs(g.items) do
            note(info, g.track, "not measured: " .. (info.why or (info.spec_off and ("different room tone: " .. info.spec_off)) or "?"))
          end
          note(g.items[1], g.track, "no item to match against in this group - skipped")
        end
      else
        local target = heard_db(ref)
        for _, info in ipairs(g.items) do
          if info ~= ref then
            if not info.rt then
              note(info, g.track, info.why)
            elseif r.GetMediaItemInfo_Value(info.item, "C_LOCK") % 2 == 1 then
              note(info, g.track, "locked item")
            elseif info.spec_off then
              actions[#actions + 1] = { move = info.item, track = g.track }
              note(info, g.track, "different room tone: " .. info.spec_off .. " - moved to the mismatch track")
            else
              local diff = target - heard_db(info)
              if MAX_CHANGE_DB and math.abs(diff) > MAX_CHANGE_DB then
                actions[#actions + 1] = { move = info.item, track = g.track }
                note(info, g.track, string.format("needs %+.1f dB - moved to the mismatch track", diff))
              elseif math.abs(diff) >= 0.05 then
                actions[#actions + 1] = { take = r.GetActiveTake(info.item), vol = info.take_vol * 10 ^ (diff / 20) }
              end
            end
          end
        end
      end
    end
  end
  return lines, actions
end

local function apply_actions(actions)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, a in ipairs(actions) do
    if a.move then r.MoveMediaItemToTrack(a.move, mismatch_track(a.track))
    else r.SetMediaItemTakeInfo_Value(a.take, "D_VOL", a.vol) end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock(TITLE, -1)
end

local function show_lines(lines)
  if lines and #lines > 0 then
    local out = {}
    for i = 1, math.min(#lines, 25) do out[#out + 1] = lines[i] end
    if #lines > 25 then out[#out + 1] = string.format("... and %d more", #lines - 25) end
    r.MB(table.concat(out, "\n"), TITLE, 0)
  end
end

-- Progress window (native gfx)
local W, H = 460, 96
local function draw()
  gfx.set(0.16, 0.16, 0.17, 1); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  gfx.setfont(1, "Arial", 15)
  gfx.set(0.9, 0.9, 0.9, 1)
  gfx.x, gfx.y = 12, 10
  gfx.drawstr(PROG.cancel and "Cancelling..." or string.format("Analyzing room tone %d / %d", PROG.i, PROG.n))
  gfx.set(0.6, 0.6, 0.6, 1)
  gfx.x, gfx.y = 12, 30
  local label = PROG.label
  while #label > 4 and gfx.measurestr(label) > gfx.w - 24 do label = label:sub(1, -5) .. "..." end
  gfx.drawstr(label)
  local frac = PROG.total > 0 and math.min(1, PROG.done / PROG.total) or 0
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

local groups = build_groups()
if #groups == 0 then return end
local co = coroutine.create(analyze)
local window = false
r.atexit(function() if PROG.restore then PROG.restore() end end)   -- never leave an item opened up

local function step()
  if window then
    local ch = gfx.getchar()
    if ch == 27 or ch < 0 then PROG.cancel = true end
  end
  PROG.last = r.time_precise()
  local ok, lines, actions = coroutine.resume(co, groups)
  if not ok then
    if PROG.restore then PROG.restore() end
    if window then gfx.quit() end
    error(lines)
  end
  if coroutine.status(co) == "dead" then
    if window then gfx.quit() end
    if lines and not PROG.cancel then
      apply_actions(actions)
      -- next cycle: the arrange redraws first, so the window never shows a stale picture
      r.defer(function() show_lines(lines) end)
    end
    return
  end
  if not window then gfx.init(TITLE, W, H); window = true end
  draw()
  r.defer(step)
end
step()
