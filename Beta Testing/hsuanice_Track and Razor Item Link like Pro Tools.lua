--[[
@description Track and Razor Item Link like Pro Tools
@version 0.7.5-hotfix1
@author hsuanice
@about
  Pro Tools-style "Link Track and Edit Selection". Edit Selection = Razor Area or Item Selection.
  Priority:
    1) Razor exists → use Razor (highest)
    2) Else Item Selection → use VIRTUAL range [min item start, max item end], but now it is LATCHED
       (sticky) until you explicitly change selection or create a real Time Selection.
    3) Else no active range.

  Behaviors (unchanged except for latching):
    - Razor/Item auto-sync Track selection (Razor priority).
    - With a REAL Time Selection present, changing Track selection creates/moves/removes Razor on those tracks
      and syncs items under the range.
    - Moving selected items across tracks updates Track selection (no Razor).

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.7.5-hotfix1 - Fix Lua syntax: replace patterns like `local a={},b=...` with `local a, b = ..., ...`.
  v0.7.5 - LATCHED VIRTUAL RANGE (see previous notes).
]]

-------------------------
-- === USER OPTIONS === --
-------------------------
local RANGE_MODE = 2  -- 1=overlap, 2=contain (Pro Tools style)
local LATCH_CLEAR_ON_CURSOR_MOVE = true  -- true: moving edit cursor clears virtual latch when no TS/Razor

---------------------------------------
-- Toolbar auto-terminate + toggle support
---------------------------------------
if reaper.set_action_options then reaper.set_action_options(1|4) end
reaper.atexit(function() if reaper.set_action_options then reaper.set_action_options(8) end end)

----------------
-- Helpers
----------------
local function track_selected(tr) return (reaper.GetMediaTrackInfo_Value(tr,"I_SELECTED") or 0) > 0.5 end
local function set_track_selected(tr,sel) reaper.SetTrackSelected(tr, sel and true or false) end
local function track_guid(tr) return reaper.GetTrackGUID(tr) end

-- Parse P_RAZOREDITS into triplets {start,end,guid}
local function parse_triplets(s)
  local out, toks = {}, {}
  if not s or s=="" then return out end
  for w in s:gmatch("%S+") do toks[#toks+1] = w end
  for i=1,#toks,3 do
    local a = tonumber(toks[i]); local b = tonumber(toks[i+1]); local g = toks[i+2] or "\"\""
    if a and b and b > a then out[#out+1] = {a, b, g} end
  end
  return out
end

local function get_track_level_ranges(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr,"P_RAZOREDITS","",false)
  if not ok then return {} end
  local out = {}
  for _, t in ipairs(parse_triplets(s)) do if t[3] == "\"\"" then out[#out+1] = {t[1], t[2]} end end
  return out
end
local function track_has_razor(tr) return #get_track_level_ranges(tr) > 0 end
local function any_razor_exists()
  local n = reaper.CountTracks(0)
  for i=0, n-1 do if track_has_razor(reaper.GetTrack(0,i)) then return true end end
  return false
end

local function set_track_level_ranges(tr, newRanges)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr,"P_RAZOREDITS","",false)
  s = (ok and s) and s or ""
  local keep = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] ~= "\"\"" then keep[#keep+1] = string.format("%.17f %.17f %s", t[1], t[2], t[3]) end
  end
  for _, r in ipairs(newRanges) do keep[#keep+1] = string.format("%.17f %.17f \"\"", r[1], r[2]) end
  reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", table.concat(keep, " "), true)
end

local function build_razor_sig()
  local t, n = {}, reaper.CountTracks(0)
  for i=0, n-1 do
    local _, s = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0,i),"P_RAZOREDITS","",false)
    t[#t+1] = s or ""
  end
  return table.concat(t, "|")
end

local function build_track_sel_sig()
  local t, n = {}, reaper.CountTracks(0)
  for i=0, n-1 do
    local tr = reaper.GetTrack(0, i)
    if track_selected(tr) then t[#t+1] = track_guid(tr) end
  end
  return table.concat(t, "|")
end

local function build_item_sel_sig()
  local parts, n = {}, reaper.CountMediaItems(0)
  for i=0, n-1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      parts[#parts+1] = g or tostring(it)
    end
  end
  return table.concat(parts, "|")
end

local function build_item_tracks_sig()
  local set, n = {}, reaper.CountMediaItems(0)
  for i=0, n-1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      local tr = reaper.GetMediaItem_Track(it)
      if tr then set[track_guid(tr)] = true end
    end
  end
  local keys = {}
  for g,_ in pairs(set) do keys[#keys+1] = g end
  table.sort(keys)
  return table.concat(keys, "|")
end

-- Item/Range utils
local function item_bounds(it)
  local pos = reaper.GetMediaItemInfo_Value(it,"D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
  return pos, pos+len
end

local EPS = 1e-9
local function item_matches_range(s,e,rs,re_)
  if RANGE_MODE == 1 then return (e > rs + EPS) and (s < re_ - EPS)
  else                     return (s >= rs - EPS) and (e <= re_ + EPS)
  end
end

local function track_select_items_matching_range(tr, rs, re_, sel)
  local n = reaper.CountTrackMediaItems(tr)
  for i=0, n-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local s, e = item_bounds(it)
    if item_matches_range(s, e, rs, re_) then
      reaper.SetMediaItemInfo_Value(it, "B_UISEL", sel and 1 or 0)
    end
  end
end

local function track_has_any_selected_item(tr)
  local n = reaper.CountTrackMediaItems(tr)
  for i=0, n-1 do
    if reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(tr, i), "B_UISEL") == 1 then return true end
  end
  return false
end

-- Real TS (we don't modify it when none)
local function get_time_selection()
  local ts, te = reaper.GetSet_LoopTimeRange(false,false,0,0,false)
  if te > ts then return ts, te end
end

-- Selected items span (no side effects)
local function selected_items_span()
  local n = reaper.CountMediaItems(0)
  local have = false; local min_s = math.huge; local max_e = -math.huge
  for i=0, n-1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      local s, e = item_bounds(it)
      if s < min_s then min_s = s end
      if e > max_e then max_e = e end
      have = true
    end
  end
  if have and max_e > min_s then return min_s, max_e end
end

-------------------------------------------------
-- LATCHED virtual range state
-------------------------------------------------
local latched_vs, latched_ve = nil, nil
local last_cursor = reaper.GetCursorPosition()

-- Active range resolver (uses latch when present)
-- returns rs,re,src where src = "razor"|"virtual_latched"|"virtual"|nil
local function resolve_active_range()
  -- Razor (union)
  local n = reaper.CountTracks(0); local found = false; local rs, re_ = math.huge, -math.huge
  for i=0, n-1 do
    for _, r in ipairs(get_track_level_ranges(reaper.GetTrack(0,i))) do
      if r[1] < rs then rs = r[1] end
      if r[2] > re_ then re_ = r[2] end
      found = true
    end
  end
  if found and re_ > rs then return rs, re_, "razor" end

  -- latched virtual
  if latched_vs and latched_ve and latched_ve > latched_vs then return latched_vs, latched_ve, "virtual_latched" end

  -- current virtual (not latched yet)
  local vs, ve = selected_items_span()
  if vs and ve and ve > vs then return vs, ve, "virtual" end

  return nil, nil, nil
end

-----------------------------
-- Shared state publisher (for Monitor)
-----------------------------
local EXT_NS = "hsuanice_Link"
local function publish_state(args)
  local function setk(k,v) reaper.SetProjExtState(0, EXT_NS, k, v or "") end
  setk("active_src", args.active_src or "none")
  setk("active_start", args.active_s and string.format("%.17f",args.active_s) or "")
  setk("active_end",   args.active_e and string.format("%.17f",args.active_e) or "")
  setk("item_span_start", args.item_s and string.format("%.17f",args.item_s) or "")
  setk("item_span_end",   args.item_e and string.format("%.17f",args.item_e) or "")
  setk("virt_latched_start", latched_vs and string.format("%.17f",latched_vs) or "")
  setk("virt_latched_end",   latched_ve and string.format("%.17f",latched_ve) or "")
  setk("ts_start", args.ts_s and string.format("%.17f",args.ts_s) or "")
  setk("ts_end",   args.ts_e and string.format("%.17f",args.ts_e) or "")
  setk("has_razor", args.has_razor and "1" or "0")
  setk("ts_has_real", (args.ts_s and args.ts_e) and "1" or "0")
end

-------------------------------
-- Main watcher loop
-------------------------------
local last_razor_sig     = build_razor_sig()
local last_trk_sig       = build_track_sel_sig()
local last_item_sig      = build_item_sel_sig()
local last_item_trk_sig  = build_item_tracks_sig()

local function mainloop()
  local prev_razor_sig      = last_razor_sig
  local prev_trk_sig        = last_trk_sig
  local prev_item_sig       = last_item_sig
  local prev_item_trk_sig   = last_item_trk_sig

  local cur_razor_sig       = build_razor_sig()
  local cur_trk_sig         = build_track_sel_sig()
  local cur_item_sig        = build_item_sel_sig()
  local cur_item_trk_sig    = build_item_tracks_sig()
  local hasRazor            = any_razor_exists()
  local ts, te              = get_time_selection()
  local cursor              = reaper.GetCursorPosition()
  local tcnt                = reaper.CountTracks(0)

  -------------------------------------------------
  -- LATCH management (no side effects on selection)
  -------------------------------------------------
  if hasRazor or (ts and te) then
    -- explicit edit selection exists → clear latch
    latched_vs, latched_ve = nil, nil
  else
    -- Create latch if none yet and items exist now
    local vs, ve = selected_items_span()
    if (not latched_vs) and vs and ve then
      latched_vs, latched_ve = vs, ve
    end
    -- Refresh latch ONLY when it looks like a user did item reselect (items changed but tracks didn't)
    if (cur_item_sig ~= prev_item_sig) and (cur_trk_sig == prev_trk_sig) and (not hasRazor) and (not (ts and te)) then
      if vs and ve then latched_vs, latched_ve = vs, ve else latched_vs, latched_ve = nil, nil end
    end
    -- Optional: moving edit cursor clears latch
    if LATCH_CLEAR_ON_CURSOR_MOVE and math.abs(cursor - last_cursor) > EPS then
      latched_vs, latched_ve = nil, nil
    end
  end
  last_cursor = cursor

  -------------------------------------------------
  -- 1) Razor change → Track selection (highest)
  -------------------------------------------------
  if cur_razor_sig ~= prev_razor_sig and hasRazor then
    reaper.PreventUIRefresh(1)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      set_track_selected(tr, track_has_razor(tr))
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
  end

  -------------------------------------------------
  -- 2) Item selection OR its TRACK set changed and NO Razor → Track selection
  -------------------------------------------------
  if not hasRazor and (cur_item_sig ~= prev_item_sig or cur_item_trk_sig ~= prev_item_trk_sig) then
    reaper.PreventUIRefresh(1)
    local want = {}
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      want[track_guid(tr)] = track_has_any_selected_item(tr)
    end
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      set_track_selected(tr, want[track_guid(tr)] or false)
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
  end

  -------------------------------------------------
  -- 3) Track selection changed + REAL TS present → create Razor + sync items
  -------------------------------------------------
  if ts and te and cur_trk_sig ~= prev_trk_sig then
    reaper.PreventUIRefresh(1)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      if track_selected(tr) then
        set_track_level_ranges(tr, { {ts, te} })
        track_select_items_matching_range(tr, ts, te, true)
      else
        set_track_level_ranges(tr, {})
        track_select_items_matching_range(tr, ts, te, false)
      end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    cur_razor_sig = build_razor_sig(); cur_item_sig = build_item_sel_sig()
  end

  -------------------------------------------------
  -- 4) Razor/Track changes → sync items under ACTIVE range (razor or latched virtual)
  -------------------------------------------------
  if cur_razor_sig ~= prev_razor_sig or cur_trk_sig ~= prev_trk_sig then
    local rs, re_, src = resolve_active_range()
    if rs and re_ and src then
      for i=0, tcnt-1 do
        local tr  = reaper.GetTrack(0,i)
        local sel = track_selected(tr)
        if src == "razor" then
          local ranges = get_track_level_ranges(tr)
          if #ranges > 0 then
            for _, r in ipairs(ranges) do track_select_items_matching_range(tr, r[1], r[2], sel) end
          else
            track_select_items_matching_range(tr, rs, re_, false)
          end
        else  -- virtual / virtual_latched
          track_select_items_matching_range(tr, rs, re_, sel)
        end
      end
      cur_item_sig = build_item_sel_sig()
    end
  end

  -- Publish shared state for Monitor (includes latched)
  do
    local a_s, a_e, a_src = resolve_active_range()
    local i_s, i_e = selected_items_span()
    publish_state{
      active_src = a_src or "none",
      active_s   = a_s, active_e = a_e,
      item_s     = i_s, item_e   = i_e,
      ts_s       = ts,  ts_e     = te,
      has_razor  = hasRazor
    }
  end

  -- persist signatures
  last_razor_sig     = cur_razor_sig
  last_trk_sig       = cur_trk_sig
  last_item_sig      = cur_item_sig
  last_item_trk_sig  = cur_item_trk_sig
  reaper.defer(mainloop)
end

mainloop()
