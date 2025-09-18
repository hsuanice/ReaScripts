--[[
@description hsuanice_Split Tracks by Item Channel
@version 0.1.2 split improve but not perfect yet
@author hsuanice
@about
  Scan all non-hidden tracks and detect mixed item channel counts (1/2/3+).
  If confirmed, split items into separate tracks per channel group:
    "OriginalName Mono", "OriginalName Stereo", "OriginalName N-Ch" (N>=3).
  The original track is duplicated to preserve FX/routing; the duplicates are
  cleared via API and the relevant items are moved to them. No Fixed Lanes used.
  Effective channel count is taken from the source; takes with I_CHANMODE set to
  downmix/left/right are treated as Mono.

@changelog


  v0.1.1
  - Make duplicated tracks truly empty via API (no action IDs).
  - Fix case where the "Mono" track ended up containing all items.
  v0.1.0
  - Initial release.
]]

local r = reaper

-- ========== helpers ==========

local function console(msg)
  r.ShowConsoleMsg(tostring(msg) .. "\n")
end

local function is_track_visible(tr)
  local tcp = r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") or 1
  local mcp = r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") or 1
  return (tcp ~= 0) or (mcp ~= 0)
end

-- Determine the effective playback channel count for a take.
-- Source channels via GetMediaSourceNumChannels; treat I_CHANMODE 2/3/4 as Mono.
local function take_effective_channels(take)
  if not take then return nil end
  local src = r.GetMediaItemTake_Source(take)
  if not src then return nil end
  local typ = r.GetMediaSourceType(src, "")
  if typ == "MIDI" then return nil end
  local nch = r.GetMediaSourceNumChannels(src) or 0
  local chanmode = r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0
  -- 2 = downmix, 3 = left, 4 = right  -> treat as Mono
  if chanmode == 2 or chanmode == 3 or chanmode == 4 then return 1 end
  if nch <= 1 then return 1 end
  if nch == 2 then return 2 end
  return math.max(3, math.floor(nch))
end

local function ch_suffix(n)
  if n == 1 then return "Mono"
  elseif n == 2 then return "Stereo"
  else return tostring(n) .. "-Ch" end
end

local function get_track_name(tr)
  local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return name
end

local function set_track_name(tr, name)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
end

local function count_track_items(tr)
  return r.CountTrackMediaItems(tr)
end

local function get_track_index(tr)
  return r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") - 1
end

-- Delete all items on a given track (robust, no reliance on actions)
local function delete_all_items_in_track(tr)
  local n = r.CountTrackMediaItems(tr)
  for i = n-1, 0, -1 do
    local it = r.GetTrackMediaItem(tr, i)
    r.DeleteTrackMediaItem(tr, it)
  end
end

-- Duplicate a track (preserving settings/FX/routing), then clear copied items.
local function duplicate_track_empty(tr)
  -- Select only the source track and duplicate
  for i = 0, r.CountTracks(0)-1 do r.SetTrackSelected(r.GetTrack(0, i), false) end
  r.SetTrackSelected(tr, true)
  r.Main_OnCommand(40062, 0) -- Track: Duplicate tracks

  -- The duplicate is placed right after the original
  local idx = get_track_index(tr)
  local new_tr = r.GetTrack(0, idx + 1)

  -- Make absolutely sure it has no items
  delete_all_items_in_track(new_tr)

  -- Deselect to keep state clean
  r.SetTrackSelected(new_tr, false)
  return new_tr
end

-- strict mode: also flag tracks where source_nch is mixed OR source_nch != effective_nch
local STRICT_INCLUDE_MISMATCH = true

-- Return (source_nch, effective_nch, chanmode)
local function take_channels(take)
  if not take then return nil end
  local src = r.GetMediaItemTake_Source(take)
  if not src then return nil end
  local typ = r.GetMediaSourceType(src, "")
  if typ == "MIDI" then return nil end
  local src_nch = r.GetMediaSourceNumChannels(src) or 0
  local chanmode = r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0
  -- effective nch follows your original rule
  local eff
  if chanmode == 2 or chanmode == 3 or chanmode == 4 then
    eff = 1
  else
    if src_nch <= 1 then eff = 1
    elseif src_nch == 2 then eff = 2
    else eff = math.max(3, math.floor(src_nch)) end
  end
  return src_nch, eff, chanmode
end



-- ========== scan ==========
local function scan_mixed_tracks()
  local mixed = {}  -- { track, name, groups(=eff), src_groups, mismatch_cnt, mismatch_hist, total_items }

  for ti = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, ti)
    if is_track_visible(tr) then
      local item_cnt = count_track_items(tr)
      if item_cnt > 0 then
        -- per-track accumulators (每條軌都重置)
        local eff_groups, src_groups = {}, {}
        local mismatch_cnt, mismatch_hist = 0, {}
        local totals = 0

        for ii = 0, item_cnt-1 do
          local it = r.GetTrackMediaItem(tr, ii)
          local tk = r.GetActiveTake(it)
          local src_nch, eff_nch = take_channels(tk)
          if src_nch and eff_nch then
            -- 有效播放聲道（用來 split）
            local eg = eff_groups[eff_nch]
            if not eg then eg = {count=0, items={}}; eff_groups[eff_nch] = eg end
            eg.count = eg.count + 1
            eg.items[#eg.items+1] = it

            -- 來源聲道（用來嚴格偵測）
            local sg = src_groups[src_nch]
            if not sg then sg = {count=0, items={}}; src_groups[src_nch] = sg end
            sg.count = sg.count + 1
            sg.items[#sg.items+1] = it

            -- 不一致：來源>=2，但實際播放縮到更少（例 2→1、10→1/2）
            if src_nch >= 2 and eff_nch < src_nch then
              mismatch_cnt = mismatch_cnt + 1
              mismatch_hist[src_nch] = mismatch_hist[src_nch] or {}
              mismatch_hist[src_nch][eff_nch] = (mismatch_hist[src_nch][eff_nch] or 0) + 1
            end
            totals = totals + 1
          end
        end

        -- 判斷是否列入 mixed
        local eff_kinds, src_kinds = 0, 0
        for _ in pairs(eff_groups) do eff_kinds = eff_kinds + 1 end
        for _ in pairs(src_groups) do src_kinds = src_kinds + 1 end

        local is_mixed =
          (eff_kinds > 1) or
          (src_kinds > 1) or
          (STRICT_INCLUDE_MISMATCH and mismatch_cnt > 0)

        -- 決定本次 split 用哪一組
        local split_mode, groups_for_split
        if eff_kinds > 1 then
          split_mode, groups_for_split = "eff", eff_groups
        elseif (src_kinds > 1) or (STRICT_INCLUDE_MISMATCH and mismatch_cnt > 0) then
          split_mode, groups_for_split = "src", src_groups
        end

        if is_mixed then
          mixed[#mixed+1] = {
            track = tr,
            name  = get_track_name(tr),
            groups = groups_for_split,   -- ← 這裡要用選好的分組
            src_groups = src_groups,
            mismatch_cnt = mismatch_cnt,
            mismatch_hist = mismatch_hist,
            split_mode = split_mode,
            total_items = totals
          }
        end


      end
    end
  end

  return mixed
end

local function groups_to_text(groups)
  local list, order = {}, {}
  for ch in pairs(groups) do table.insert(order, ch) end
  table.sort(order)
  for _, ch in ipairs(order) do
    table.insert(list, string.format("%s: %d", ch_suffix(ch), groups[ch].count))
  end
  return table.concat(list, ", ")
end

----------
local rescan_track_groups -- forward declaration

-- ========== split logic ==========
local function split_track_by_groups(entry)
  local tr, name, groups = entry.track, entry.name, entry.groups

  -- Keep the most frequent channel group on the original track.
  local primary_ch, primary_count = nil, -1
  for ch, g in pairs(groups) do
    if g.count > primary_count or (g.count == primary_count and (primary_ch or 99) > ch) then
      primary_ch, primary_count = ch, g.count
    end
  end

  -- Create destination tracks for the non-primary groups by duplicating.
  local target_tracks = {} -- ch -> track
  target_tracks[primary_ch] = tr
  local ch_list = {}
  for ch in pairs(groups) do table.insert(ch_list, ch) end
  table.sort(ch_list)

  for _, ch in ipairs(ch_list) do
    if ch ~= primary_ch then
      local new_tr = duplicate_track_empty(tr)
      target_tracks[ch] = new_tr
    end
  end

  -- Rename tracks.
  for ch, dst in pairs(target_tracks) do
    set_track_name(dst, string.format("%s %s", name, ch_suffix(ch)))
  end

  -- Move items of non-primary groups to their tracks.
  for ch, g in pairs(groups) do
    if ch ~= primary_ch then
      for _, it in ipairs(g.items) do
        r.MoveMediaItemToTrack(it, target_tracks[ch]) -- move (not copy)
      end
    end
  end

  -- -- Verify & second pass (fix residuals if any) --------------------------
  -- Recount live state on the original track; if still has non-primary groups,
  -- move them now (handles cases where cached item lists got stale).
  local live_eff, live_src = rescan_track_groups(tr)

  -- Decide which taxonomy we should be "clean" against: eff or src
  local want_eff = true
  if entry.split_mode == "src" then want_eff = false end

  local live_groups = want_eff and live_eff or live_src
  for ch, g in pairs(live_groups) do
    if ch ~= primary_ch then
      -- if we don't have a target yet (e.g. missed creation), create it now
      if not target_tracks[ch] then
        local new_tr = duplicate_track_empty(tr)
        target_tracks[ch] = new_tr
        set_track_name(new_tr, string.format("%s %s", name, ch_suffix(ch)))
      end
      for _, it in ipairs(g.items) do
        r.MoveMediaItemToTrack(it, target_tracks[ch])
      end
    end
  end


end

-- Re-scan one track on-the-fly and rebuild eff/src groups from current items.
rescan_track_groups = function(tr)
  local eff_groups, src_groups = {}, {}
  local function add_item(tbl, key, it)
    local g = tbl[key]; if not g then g = {count=0, items={}}; tbl[key] = g end
    g.count = g.count + 1
    g.items[#g.items+1] = it
  end
  local n = r.CountTrackMediaItems(tr)
  for i = 0, n-1 do
    local it = r.GetTrackMediaItem(tr, i)
    local tk = r.GetActiveTake(it)
    local src_nch, eff_nch = take_channels(tk)
    if src_nch and eff_nch then
      add_item(eff_groups, eff_nch, it)
      add_item(src_groups, src_nch, it)
    end
  end
  return eff_groups, src_groups
end




-- ========== run ==========
r.Undo_BeginBlock()
r.PreventUIRefresh(1)

r.ShowConsoleMsg("") -- clear console
console("=== Mixed-channel tracks (scan) ===")

local mixed = scan_mixed_tracks()
if #mixed == 0 then
  console("No mixed-channel tracks found.")
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Split tracks by item channel (scan)", -1)
  return
end

for _, e in ipairs(mixed) do
  local function groups_to_text_src(src_groups)
    local order, out = {}, {}
    for ch in pairs(src_groups) do table.insert(order, ch) end
    table.sort(order)
    for _, ch in ipairs(order) do
      local label = (ch==1 and "Mono") or (ch==2 and "Stereo") or (tostring(ch) .. "-Ch")
      table.insert(out, string.format("%s: %d", label, src_groups[ch].count))
    end
    return table.concat(out, ", ")
  end

  console(string.format("• %s", e.name))
  console(string.format("    eff -> %s", groups_to_text(e.groups)))
  console(string.format("    src -> %s", groups_to_text_src(e.src_groups or {})))
  if (e.mismatch_cnt or 0) > 0 then
    local parts = {}
    for s, to in pairs(e.mismatch_hist or {}) do
      for d, c in pairs(to) do
        table.insert(parts, string.format("%d→%d:%d", s, d, c))
      end
    end
    table.sort(parts)
    console(string.format("    mismatch -> %d (%s)", e.mismatch_cnt, table.concat(parts, ", ")))
  end
end
console("")


local prompt = ("%d track(s) contain mixed item channel counts.\n\nSplit them into separate tracks now?\n\n(Naming: \"OriginalName Mono/Stereo/N-Ch\")"):format(#mixed)
local ret = r.ShowMessageBox(prompt, "Split Tracks by Item Channel", 4) -- 4 = Yes/No

if ret == 6 then -- Yes
  for _, e in ipairs(mixed) do
    split_track_by_groups(e)
  end
  console("Done: tracks have been split by item channel.")
else
  console("Aborted by user. No changes made.")
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Split tracks by item channel", -1)
