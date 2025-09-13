-- @description hsuanice_Split Tracks by Item Channel
-- @version 0.1.0
-- @author hsuanice
-- @changelog
--   v0.1.0 - Initial release:
--     • Scan all non-hidden tracks and detect mixed item channel counts
--     • Optional auto-split into separate tracks per channel (Mono/Stereo/N-Ch)
--     • Duplicates track settings/FX/routing (no Fixed Lanes), then moves items
--     • Uses take playback channel (source channels + I_CHANMODE)
-- @about
--   Detects tracks that contain items with mixed channel counts (1/2/3+).
--   If the user confirms, the script creates new tracks per channel group:
--     "OriginalName Mono", "OriginalName Stereo", "OriginalName N-Ch" (N>=3),
--   keeps the original track for the most frequent group, and moves items
--   accordingly. It does not use Fixed Lanes; new tracks are made by duplicating
--   the original track (to preserve FX/routing), then clearing items.
-- @link https://www.reaper.fm/sdk/reascript/reascript.php

-- hsuanice_Split Tracks by Item Channel.lua
-- v0.1.0

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

local function deselect_all_tracks()
  for i = 0, r.CountTracks(0)-1 do
    r.SetTrackSelected(r.GetTrack(0, i), false)
  end
end

local function clear_items_on_selected_tracks()
  r.Main_OnCommand(40129, 0) -- Select all items on selected tracks
  r.Main_OnCommand(40006, 0) -- Remove items
end

-- Duplicate a track (preserving settings/FX/routing), then clear copied items.
local function duplicate_track_empty(tr)
  deselect_all_tracks()
  r.SetTrackSelected(tr, true)
  r.Main_OnCommand(40062, 0) -- Track: Duplicate tracks
  local idx = get_track_index(tr)
  local new_tr = r.GetTrack(0, idx + 1)
  deselect_all_tracks()
  r.SetTrackSelected(new_tr, true)
  clear_items_on_selected_tracks()
  return new_tr
end

-- ========== scan ==========
local function scan_mixed_tracks()
  local mixed = {}  -- entries: { track, name, groups={ [ch]={count, items{...}} }, total_items }
  for ti = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, ti)
    if is_track_visible(tr) then
      local item_cnt = count_track_items(tr)
      if item_cnt > 0 then
        local groups, totals = {}, 0
        for ii = 0, item_cnt-1 do
          local it = r.GetTrackMediaItem(tr, ii)
          local tk = r.GetActiveTake(it)
          local ch = take_effective_channels(tk)
          if ch then
            groups[ch] = groups[ch] or {count=0, items={}}
            groups[ch].count = groups[ch].count + 1
            table.insert(groups[ch].items, it)
            totals = totals + 1
          end
        end
        local kind = 0
        for _ in pairs(groups) do kind = kind + 1 end
        if kind > 1 then
          table.insert(mixed, { track = tr, name = get_track_name(tr), groups = groups, total_items = totals })
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
        r.MoveMediaItemToTrack(it, target_tracks[ch])
      end
    end
  end
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
  console(string.format("• %s  ->  %s", e.name, groups_to_text(e.groups)))
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
