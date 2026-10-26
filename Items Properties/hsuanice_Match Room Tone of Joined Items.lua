--[[
@description Match Room Tone of Joined Items - level-match the background noise of touching / crossfaded items (take volume)
@version 26.1026.1446pre1
@author hsuanice
@changelog
  - Initial release: level-match the room tone of touching / crossfaded selected items by take volume (reference = the longest item with pauses); more than 12 dB off -> moved to a '<track> - RT mismatch' track; only groups fully in view.
  - Room tone is measured on the WHOLE source file (quietest 10 %), so movement in the trimmed pauses does not count; an item whose own part is more than 6 dB louder than its file's quietest is listed.
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
  - An item needing more than 12 dB is not adjusted: it moves to a track "<track> - RT mismatch"
    right below its track (created once, reused), so it can be checked by ear. An item with
    speech all the way through measures far too loud and ends up there too.
  - Only groups fully inside the arrange view are processed (never changes what you cannot see).
  - One undo point. A window only lists what was moved or skipped.

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
local MAX_CHANGE_DB = 12     -- more than this: move the item to the mismatch track
local SPREAD_DB     = 10     -- quiet part this much below the loud part = the item has pauses
local ANALYSIS_SR   = 16000  -- analysis sample rate (the accessor resamples; whole files are read)
local NOTE_DIFF_DB  = 6      -- whole file this much quieter than the item's own part: listed
local MISMATCH_SUFFIX = " - RT mismatch"
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

-- Room tone of the whole source file of the item's take (dB, take and item volume excluded).
-- The item is opened up to the full source for the measurement (position kept, take volume 1,
-- no fades) and restored right after. Returns
--   { full = dB of the whole file, item = dB of the part the item plays, pauses = item has
--     pauses }  or nil + reason
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

  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", full_len)
  r.SetMediaItemTakeInfo_Value(take, "D_VOL", 1)
  for _, k in ipairs({ "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINLEN_AUTO", "D_FADEOUTLEN_AUTO" }) do
    r.SetMediaItemInfo_Value(item, k, 0)
  end
  local acc = r.CreateTakeAudioAccessor(take)
  local win = math.floor(ANALYSIS_SR * WINDOW_SEC)
  local all, part = {}, {}
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
      if t >= item_s - 1e-9 and t + WINDOW_SEC <= item_e + 1e-9 then part[#part + 1] = p end
    end
    t = t + WINDOW_SEC
  end
  r.DestroyAudioAccessor(acc)
  r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", saved.offs)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", saved.len)
  r.SetMediaItemTakeInfo_Value(take, "D_VOL", saved.vol)
  r.SetMediaItemInfo_Value(item, "D_FADEINLEN", saved.fin)
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", saved.fout)
  r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", saved.fina)
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", saved.fouta)

  local full = quiet_level(all)
  if not full then return nil, "no audio to measure" end
  local item_db, pauses = quiet_level(part)
  return { full = full, item = item_db, pauses = pauses or false }
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

local function main()
  local groups = build_groups()
  if #groups == 0 then return {} end
  local lines, moved, adjusted = {}, 0, 0
  local function note(info, tr, why)
    lines[#lines + 1] = string.format("%s @ %s: %s", track_name(tr), fmt_time(info.pos), why)
  end

  for _, g in ipairs(groups) do
    local s0, e0 = g.items[1].pos, g.items[1].fin
    for _, info in ipairs(g.items) do s0, e0 = math.min(s0, info.pos), math.max(e0, info.fin) end
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
        local m, why = room_tone(info.item)
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
        if info.rt and info.pauses and (not ref or info.len > ref.len) then ref = info end
        if info.rt and (not ref_any or info.len > ref_any.len) then ref_any = info end
      end
      ref = ref or ref_any
      if not ref then
        note(g.items[1], g.track, "nothing to measure in this group - skipped")
      else
        local target = heard_db(ref)
        for _, info in ipairs(g.items) do
          if info ~= ref then
            if not info.rt then
              note(info, g.track, info.why)
            elseif r.GetMediaItemInfo_Value(info.item, "C_LOCK") % 2 == 1 then
              note(info, g.track, "locked item")
            else
              local diff = target - heard_db(info)
              if math.abs(diff) > MAX_CHANGE_DB then
                r.MoveMediaItemToTrack(info.item, mismatch_track(g.track))
                moved = moved + 1
                note(info, g.track, string.format("needs %+.1f dB - moved to the mismatch track", diff))
              elseif math.abs(diff) >= 0.05 then
                local take = r.GetActiveTake(info.item)
                r.SetMediaItemTakeInfo_Value(take, "D_VOL", info.take_vol * 10 ^ (diff / 20))
                adjusted = adjusted + 1
              end
            end
          end
        end
      end
    end
  end
  return lines, moved, adjusted
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
local lines = main()
r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock(TITLE, -1)
if lines and #lines > 0 then
  local out = {}
  for i = 1, math.min(#lines, 25) do out[#out + 1] = lines[i] end
  if #lines > 25 then out[#out + 1] = string.format("... and %d more", #lines - 25) end
  r.MB(table.concat(out, "\n"), TITLE, 0)
end
