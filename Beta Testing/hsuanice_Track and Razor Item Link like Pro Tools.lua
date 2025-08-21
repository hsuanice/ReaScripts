--[[
@description Track and Razor Item Link like Pro Tools
@version 0.6.0
@author hsuanice
@about
  Pro Tools-style "Link Track and Edit Selection" script. Edit Selection = Razor Area or Item Selection.
  Now supports automatic Razor Area creation/move/remove on track select/unselect based on current Time Selection.
  Razor and Item selection are synced: when operating on the Track TCP, item selection will follow razor selection.
  Envelope lane razors are preserved but ignored for syncing.
  Toolbar-friendly: auto-terminates previous instance and supports toggle.

  Main features:
    1. If Time Selection exists, selecting/deselecting tracks automatically creates/moves/removes Razor Area on those tracks (using the Time Selection range).
    2. When Razor Area follows track selection, item selection under the area is also synced (select/unselect).
    3. Razor Area and Item Selection are always kept in sync. Track TCP operations are fully reflected.

  Note: Only track-level Razor Areas are processed; envelope-lane razors are preserved. 
        Script is designed for background toolbar operation (toggle).

  This script was generated using ChatGPT and Copilot based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.6.0 - Added automatic Razor Area creation/move/remove based on Time Selection; Razor/Item selection sync; Track TCP full sync.
--]]

-------------------------
-- === USER OPTIONS === --
-------------------------
-- RANGE_MODE:
--   1 = overlap : Item is selected if it overlaps the target range
--   2 = contain : Item must be fully within the target range (Pro Tools style)
local RANGE_MODE = 2

---------------------------------------
-- Toolbar auto-terminate + toggle support
---------------------------------------
if reaper.set_action_options then
  -- 1: Auto-terminate previous instance
  -- 4: Toolbar button ON
  reaper.set_action_options(1 | 4)
end
reaper.atexit(function()
  if reaper.set_action_options then
    -- 8: Toolbar button OFF
    reaper.set_action_options(8)
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

-- Collect the union of all track-level Razor Area ranges
local function collect_union_ranges()
  local tcnt = reaper.CountTracks(0)
  local set, out = {}, {}
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    for _, r in ipairs(get_track_level_ranges(tr)) do
      local key = string.format("%.17f|%.17f", r[1], r[2])
      if not set[key] then
        set[key] = true
        out[#out+1] = {r[1], r[2]}
      end
    end
  end
  return out
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
  local changed = false
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local s, e = item_bounds(it)
    if item_matches_range(s, e, rs, re_) then
      local cur = reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1
      if sel and (not cur) then
        reaper.SetMediaItemInfo_Value(it, "B_UISEL", 1)
        changed = true
      elseif (not sel) and cur then
        reaper.SetMediaItemInfo_Value(it, "B_UISEL", 0)
        changed = true
      end
    end
  end
  return changed
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
local last_razor_sig = build_razor_sig()
local last_trk_sig   = build_track_sel_sig()
local last_item_sig  = build_item_sel_sig()

local function mainloop()
  -- Snapshot previous states
  local prev_razor_sig = last_razor_sig
  local prev_trk_sig   = last_trk_sig
  local prev_item_sig  = last_item_sig

  -- Get current states
  local cur_razor_sig = build_razor_sig()
  local cur_trk_sig   = build_track_sel_sig()
  local cur_item_sig  = build_item_sel_sig()
  local hasRazor      = any_razor_exists()
  local ts, te        = get_time_selection()

  -- 1. If time selection exists, selecting/unselecting tracks will create/move/remove Razor Area on those tracks
  if ts and te and cur_trk_sig ~= prev_trk_sig then
    local tcnt = reaper.CountTracks(0)
    reaper.PreventUIRefresh(1)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if track_selected(tr) then
        -- Create/move Razor Area to time selection range
        set_track_level_ranges(tr, { {ts, te} })
        -- Razor sync: if the track has item selection, item selection is synced
        track_select_items_matching_range(tr, ts, te, true)
      else
        -- Unselecting track removes Razor Area
        set_track_level_ranges(tr, {})
        -- Razor sync: items in range are unselected
        track_select_items_matching_range(tr, ts, te, false)
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_razor_sig = build_razor_sig()
    cur_item_sig  = build_item_sel_sig()
  end

  -- 2. When Razor and track selection change, item selection is synced
  if cur_razor_sig ~= prev_razor_sig or cur_trk_sig ~= prev_trk_sig then
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      local ranges = get_track_level_ranges(tr)
      for _, r in ipairs(ranges) do
        -- Items within Razor Area are synced with track selection
        track_select_items_matching_range(tr, r[1], r[2], track_selected(tr))
      end
    end
    cur_item_sig = build_item_sel_sig()
  end

  -- 3. Additional syncing logic can be added here

  -- Update last states
  last_razor_sig = cur_razor_sig
  last_trk_sig   = cur_trk_sig
  last_item_sig  = cur_item_sig

  reaper.defer(mainloop)
end

mainloop()
