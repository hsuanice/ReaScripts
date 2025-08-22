--[[
@description Track and Razor Item Link like Pro Tools
@version 0.7.4
@author hsuanice
@about
  Pro Tools-style "Link Track and Edit Selection" script. Edit Selection = Razor Area or Item Selection.
  Independent and toolbar-friendly.

  Priority & range source:
    1) Razor Area exists -> use Razor ranges (highest priority)
    2) Else if Item Selection exists -> use VIRTUAL range [min item start, max item end] (internal only; does NOT write to Time Selection)
    3) Else no active range

  Behaviors:
    - Razor or Item Selection will auto-sync Track selection (Razor priority).
    - If a REAL Time Selection exists and Track selection changes, it creates/moves/removes Razor Area on those tracks and syncs item selection.
    - When there is NO Razor: moving selected items across tracks updates track selection.
    - Envelope-lane razors are preserved but ignored for syncing.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.7.4 - New: Publish current link state to Project ExtState (extname="hsuanice_Link") so the Monitor can read:
           active_src (razor|virtual|none), active_start/end, item_span_start/end, ts_start/end, has_razor.
  v0.7.3 - Do NOT modify real Time Selection when there is no Razor; use VIRTUAL range internally.
  v0.7.2 - Auto TS from items (reverted by 0.7.3).
  v0.7.1 - Track selection updates when selected items move between tracks.
]]

-------------------------
-- === USER OPTIONS === --
-------------------------
local RANGE_MODE = 2  -- 1=overlap, 2=contain (PT style)

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
-- Helpers
----------------
local function track_selected(tr)
  return (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5
end
local function set_track_selected(tr, sel) reaper.SetTrackSelected(tr, sel and true or false) end
local function track_guid(tr) return reaper.GetTrackGUID(tr) end

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
local function get_track_level_ranges(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok then return {} end
  local out = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] == "\"\"" then out[#out+1] = {t[1], t[2]} end
  end
  return out
end

local function track_has_razor(tr) return #get_track_level_ranges(tr) > 0 end
local function any_razor_exists()
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt - 1 do if track_has_razor(reaper.GetTrack(0, i)) then return true end end
  return false
end

-- Preserve envelope-lane razors
local function set_track_level_ranges(tr, newRanges)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  s = (ok and s) and s or ""
  local keep = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] ~= "\"\"" then keep[#keep+1] = string.format("%.17f %.17f %s", t[1], t[2], t[3]) end
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
    if track_selected(tr) then t[#t+1] = track_guid(tr) end
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

-- Item utilities
local function item_bounds(it)
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  return pos, pos + len
end

local EPS = 1e-9
local function item_matches_range(s,e,rs,re_)
  if RANGE_MODE == 1 then return (e > rs + EPS) and (s < re_ - EPS)
  else                     return (s >= rs - EPS) and (e <= re_ + EPS)
  end
end

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

local function track_has_any_selected_item(tr)
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    if reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(tr, i), "B_UISEL") == 1 then return true end
  end
  return false
end

-- REAL Time Selection (we don't modify it when none)
local function get_time_selection()
  local ts, te = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if te > ts then return ts, te end
end

-- VIRTUAL range = item selection span (internal only)
local function selected_items_span()
  local icnt = reaper.CountMediaItems(0)
  local have = false
  local min_s, max_e = math.huge, -math.huge
  for i = 0, icnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      local s, e = item_bounds(it)
      if s < min_s then min_s = s end
      if e > max_e then max_e = e end
      have = true
    end
  end
  if have then return min_s, max_e end
end

-- Active range resolver: returns (rs, re_, source) where source is "razor" | "virtual" | nil
local function resolve_active_range()
  -- Razor has priority (union across tracks)
  local tcnt = reaper.CountTracks(0)
  local found, rs, re_ = false, math.huge, -math.huge
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    for _, r in ipairs(get_track_level_ranges(tr)) do
      if r[1] < rs then rs = r[1] end
      if r[2] > re_ then re_ = r[2] end
      found = true
    end
  end
  if found and re_ > rs then return rs, re_, "razor" end
  -- else try virtual from items
  local vs, ve = selected_items_span()
  if vs and ve and ve > vs then return vs, ve, "virtual" end
  return nil, nil, nil
end

-----------------------------
-- NEW: publish shared state
-----------------------------
local EXT_NS = "hsuanice_Link"  -- Project ExtState namespace
local function publish_state(args)
  -- args: {active_src, active_s, active_e, item_s, item_e, ts_s, ts_e, has_razor}
  local function setk(k, v)
    reaper.SetProjExtState(0, EXT_NS, k, v or "")
  end
  setk("active_src", args.active_src or "none")
  setk("active_start", args.active_s and string.format("%.17f", args.active_s) or "")
  setk("active_end",   args.active_e and string.format("%.17f", args.active_e) or "")
  setk("item_span_start", args.item_s and string.format("%.17f", args.item_s) or "")
  setk("item_span_end",   args.item_e and string.format("%.17f", args.item_e) or "")
  setk("ts_start", args.ts_s and string.format("%.17f", args.ts_s) or "")
  setk("ts_end",   args.ts_e and string.format("%.17f", args.ts_e) or "")
  setk("has_razor", args.has_razor and "1" or "0")
  setk("ts_has_real", (args.ts_s and args.ts_e) and "1" or "0")
end

-------------------------------
-- Main watcher loop
-------------------------------
local last_razor_sig       = build_razor_sig()
local last_trk_sig         = build_track_sel_sig()
local last_item_sig        = build_item_sel_sig()
local last_item_tracks_sig = build_item_tracks_sig()

local function mainloop()
  local prev_razor_sig       = last_razor_sig
  local prev_trk_sig         = last_trk_sig
  local prev_item_sig        = last_item_sig
  local prev_item_tracks_sig = last_item_tracks_sig

  local cur_razor_sig       = build_razor_sig()
  local cur_trk_sig         = build_track_sel_sig()
  local cur_item_sig        = build_item_sel_sig()
  local cur_item_tracks_sig = build_item_tracks_sig()
  local hasRazor            = any_razor_exists()
  local tcnt = reaper.CountTracks(0)

  -- 1) Razor change -> sync Track selection (highest priority)
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

  -- 2) Item selection (or its TRACK set) changed and NO Razor -> sync Track selection
  if not hasRazor and (cur_item_sig ~= prev_item_sig or cur_item_tracks_sig ~= prev_item_tracks_sig) then
    reaper.PreventUIRefresh(1)
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

  -- 3) Track selection changed + REAL Time Selection exists -> create Razor + sync items
  local ts, te = get_time_selection() -- only real TS; we don't auto-create it
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

  -- 4) Any change in Razor/Track selection -> sync items under the ACTIVE range
  if cur_razor_sig ~= prev_razor_sig or cur_trk_sig ~= prev_trk_sig then
    local rs, re_, src = resolve_active_range()
    if rs and re_ and src then
      for i = 0, tcnt - 1 do
        local tr = reaper.GetTrack(0, i)
        local sel = track_selected(tr)
        if src == "razor" then
          local ranges = get_track_level_ranges(tr)
          if #ranges > 0 then
            for _, r in ipairs(ranges) do
              track_select_items_matching_range(tr, r[1], r[2], sel)
            end
          else
            track_select_items_matching_range(tr, rs, re_, false)
          end
        else -- "virtual"
          track_select_items_matching_range(tr, rs, re_, sel)
        end
      end
      cur_item_sig = build_item_sel_sig()
    end
  end

  -- NEW: Publish shared state for the Monitor
  do
    local a_s, a_e, a_src = resolve_active_range()
    local i_s, i_e        = selected_items_span()
    publish_state{
      active_src = a_src or "none",
      active_s   = a_s, active_e = a_e,
      item_s     = i_s, item_e   = i_e,
      ts_s       = ts,  ts_e     = te,
      has_razor  = hasRazor
    }
  end

  -- persist
  last_razor_sig       = cur_razor_sig
  last_trk_sig         = cur_trk_sig
  last_item_sig        = cur_item_sig
  last_item_tracks_sig = cur_item_tracks_sig
  reaper.defer(mainloop)
end

mainloop()
