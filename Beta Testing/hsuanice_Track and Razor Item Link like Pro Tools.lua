--[[
@description Track and Razor Item Link like Pro Tools
@version 0.7.1
@author hsuanice
@about
  Pro Tools-style "Link Track and Edit Selection" script. Edit Selection = Razor Area or Item Selection.
  Independent: Does not require or interact with any other link scripts, ExtState, or external state.
  - Razor Area and Item Selection will automatically sync track selection (Razor takes priority).
  - With Time Selection, (un)selecting tracks will create/move/remove Razor Area on those tracks and sync item selection.
  - All logic is self-contained and does not depend on other scripts.

  Main features:
    1. If Time Selection exists, selecting/deselecting tracks automatically creates/moves/removes Razor Area on those tracks (using the Time Selection range).
    2. When Razor Area follows track selection, item selection under the area is also synced (select/unselect).
    3. Razor Area or Item Selection will sync track selection (Razor > Item).
    4. Envelope lane razors are preserved but ignored for syncing.
    5. Toolbar-friendly: auto-terminates previous instance and supports toggle.

  Note: Only track-level Razor Areas are processed; envelope-lane razors are preserved.

  This script was generated using ChatGPT and Copilot based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.7.1 - Fix: Track selection now updates when selected items are MOVED between tracks (even if the item set itself didn't change).
  v0.7.0 - Independent version: Track selection is always synced to Razor or Item selection (Razor priority). No external state or link scripts needed.
]]

-------------------------
-- === USER OPTIONS === --
-------------------------
-- RANGE_MODE:
--   1 = overlap : Item is selected if it overlaps the target range
--   2 = contain : Item must be fully within the target range (Pro Tools style)
local RANGE_MODE = 1

---------------------------------------
-- Toolbar auto-terminate + toggle support
---------------------------------------
if reaper.set_action_options then
  reaper.set_action_options(1 | 4) -- auto-terminate + toolbar ON
end
reaper.atexit(function()
  if reaper.set_action_options then
    reaper.set_action_options(8)   -- toolbar OFF
  end
end)

----------------
-- Helper functions
----------------
local function track_selected(tr)
  return (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5
end

local function set_track_selected(tr, sel)
  reaper.SetTrackSelected(tr, sel and true or false)
end

local function track_guid(tr) return reaper.GetTrackGUID(tr) end

-- Parse P_RAZOREDITS into triplets {start, end, guid_str}
local function parse_triplets(s)
  local out = {}
  if not s or s == "" then return out end
  local toks = {}
  for w in s:gmatch("%S+") do
    toks[#toks+1] = w
  end
  for i = 1, #toks, 3 do
    local a = tonumber(toks[i])
    local b = tonumber(toks[i+1])
    local g = toks[i+2] or "\"\""
    if a and b and b > a then
      out[#out+1] = {a, b, g}
    end
  end
  return out
end

-- Get ONLY track-level ranges on a track (GUID == "")
local function get_track_level_ranges(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok then return {} end
  local out = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] == "\"\"" then
      out[#out+1] = {t[1], t[2]}
    end
  end
  return out
end

local function track_has_razor(tr)
  return #get_track_level_ranges(tr) > 0
end

local function any_razor_exists()
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    if track_has_razor(reaper.GetTrack(0, i)) then
      return true
    end
  end
  return false
end

-- Set track-level Razor Areas (preserves envelope-lane razors)
local function set_track_level_ranges(tr, newRanges)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  s = (ok and s) and s or ""
  local keep = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] ~= "\"\"" then
      keep[#keep+1] = string.format("%.17f %.17f %s", t[1], t[2], t[3])
    end
  end
  for _, r in ipairs(newRanges) do
    keep[#keep+1] = string.format("%.17f %.17f \"\"", r[1], r[2])
  end
  reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", table.concat(keep, " "), true)
end

local function build_razor_sig()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local _, s = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_RAZOREDITS", "", false)
    t[#t+1] = s or ""
  end
  return table.concat(t, "|")
end

local function build_track_sel_sig()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    if track_selected(tr) then
      t[#t+1] = track_guid(tr)
    end
  end
  return table.concat(t, "|")
end

local function build_item_sel_sig()
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

-- NEW: signature of TRACKS that contain at least one selected item
local function build_item_tracks_sig()
  local tset = {}
  local icnt = reaper.CountMediaItems(0)
  for i = 0, icnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      local tr = reaper.GetMediaItem_Track(it)
      if tr then tset[track_guid(tr)] = true end
    end
  end
  local keys = {}
  for g,_ in pairs(tset) do keys[#keys+1] = g end
  table.sort(keys)
  return table.concat(keys, "|")
end

-- Item utility (range-based)
local function item_bounds(it)
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  return pos, pos + len
end

-- Determine if item matches the range (overlap/contain)
local EPS = 1e-9
local function item_matches_range(s, e, rs, re_)
  if RANGE_MODE == 1 then
    return (e > rs + EPS) and (s < re_ - EPS)        -- overlap
  else
    return (s >= rs - EPS) and (e <= re_ + EPS)      -- contain
  end
end

-- Select/unselect items in track that match the range
local function track_select_items_matching_range(tr, rs, re_, sel)
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local s, e = item_bounds(it)
    if item_matches_range(s, e, rs, re_) then
      reaper.SetMediaItemInfo_Value(it, "B_UISEL", sel and 1 or 0)
    end
  end
end

-- Check if track has any selected item
local function track_has_any_selected_item(tr)
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    if reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(tr, i), "B_UISEL") == 1 then
      return true
    end
  end
  return false
end

-------------------------------
-- Get current Time Selection range
-------------------------------
local function get_time_selection()
  local start, end_ = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if end_ > start then
    return start, end_
  end
end

-------------------------------
-- Main watcher loop
-------------------------------
local last_razor_sig       = build_razor_sig()
local last_trk_sig         = build_track_sel_sig()
local last_item_sig        = build_item_sel_sig()
local last_item_tracks_sig = build_item_tracks_sig()   -- NEW

local function mainloop()
  local prev_razor_sig       = last_razor_sig
  local prev_trk_sig         = last_trk_sig
  local prev_item_sig        = last_item_sig
  local prev_item_tracks_sig = last_item_tracks_sig   -- NEW

  local cur_razor_sig       = build_razor_sig()
  local cur_trk_sig         = build_track_sel_sig()
  local cur_item_sig        = build_item_sel_sig()
  local cur_item_tracks_sig = build_item_tracks_sig() -- NEW
  local hasRazor            = any_razor_exists()
  local tcnt = reaper.CountTracks(0)
  local ts, te = get_time_selection()

  -- 1) Razor Area -> Track selection (highest priority)
  if cur_razor_sig ~= prev_razor_sig and hasRazor then
    reaper.PreventUIRefresh(1)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      set_track_selected(tr, track_has_razor(tr))
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
  end

  -- 2) Item selection OR the set of tracks containing selected items -> Track selection (only if NO Razor)
  --    This covers both: selecting/deselecting items AND MOVING selected items across tracks.
  if not hasRazor and (cur_item_sig ~= prev_item_sig or cur_item_tracks_sig ~= prev_item_tracks_sig) then
    reaper.PreventUIRefresh(1)
    -- Build a quick lookup of tracks that should be selected
    local want = {}
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      want[track_guid(tr)] = track_has_any_selected_item(tr)
    end
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      set_track_selected(tr, want[track_guid(tr)] or false)
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
  end

  -- 3) Track selection + Time selection -> Razor Area + Item selection
  if ts and te and cur_trk_sig ~= prev_trk_sig then
    reaper.PreventUIRefresh(1)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if track_selected(tr) then
        set_track_level_ranges(tr, { {ts, te} })
        track_select_items_matching_range(tr, ts, te, true)
      else
        set_track_level_ranges(tr, {})
        track_select_items_matching_range(tr, ts, te, false)
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_razor_sig = build_razor_sig()
    cur_item_sig  = build_item_sel_sig()
  end

  -- 4) Razor Area + Track selection -> Item selection (sync items under razor area)
  if cur_razor_sig ~= prev_razor_sig or cur_trk_sig ~= prev_trk_sig then
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      local ranges = get_track_level_ranges(tr)
      for _, r in ipairs(ranges) do
        track_select_items_matching_range(tr, r[1], r[2], track_selected(tr))
      end
    end
    cur_item_sig = build_item_sel_sig()
  end

  -- persist
  last_razor_sig       = cur_razor_sig
  last_trk_sig         = cur_trk_sig
  last_item_sig        = cur_item_sig
  last_item_tracks_sig = cur_item_tracks_sig -- NEW
  reaper.defer(mainloop)
end

mainloop()
