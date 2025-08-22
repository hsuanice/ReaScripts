--[[
@description Track and Razor Item Link like Pro Tools (performance edition)
@version 0.8.2-perf
@author hsuanice
@about
  Pro Tools-style "Link Track and Edit Selection". Edit Selection = Razor Area or Item Selection.

  Performance principles:
    • Event-gated scans using GetProjectStateChangeCount(): do nothing heavy when nothing changed.
    • Enumerate ONLY selected tracks/items (no full project sweeps unless necessary).
    • Cache per-track Razor info and recompute only when project-state changed.
    • Apply item selection only on tracks whose selection state changed.
    • Keep Latched Virtual Range; publish ProjExtState only when changed.

  Priority (unchanged):
    1) Razor exists → use Razor (highest)
    2) Else Item Selection → use VIRTUAL (latched) span [min..max] of selected items
    3) Else no active range

  Change log:
    v0.8.2-perf - FIX: Do not shrink latched span after Track Toggle.
                   Added suppress_latch_next flag to skip one-shot relatch when items were changed by script.
    v0.8.1-perf-hotfix - Restore set_track_level_ranges().
    v0.8.0-perf - Major perf pass.
]]

-------------------------
-- === USER OPTIONS === --
-------------------------
local RANGE_MODE = 2  -- 1=overlap, 2=contain (Pro Tools style)
local LATCH_CLEAR_ON_CURSOR_MOVE = true  -- moving edit cursor clears virtual latch when no TS/Razor

---------------------------------------
-- Toolbar auto-terminate + toggle support
---------------------------------------
if reaper.set_action_options then reaper.set_action_options(1|4) end
reaper.atexit(function() if reaper.set_action_options then reaper.set_action_options(8) end end)

----------------
-- Tiny utils
----------------
local EPS = 1e-9
local function nearly_eq(a,b) return math.abs((a or 0)-(b or 0)) < 1e-12 end
local function tconcat_keys_sorted(set)
  local keys = {}; for k,_ in pairs(set) do keys[#keys+1]=k end
  table.sort(keys); return table.concat(keys, "|")
end

----------------
-- Track helpers
----------------
local function track_selected(tr) return (reaper.GetMediaTrackInfo_Value(tr,"I_SELECTED") or 0) > 0.5 end
local function set_track_selected(tr, sel) reaper.SetTrackSelected(tr, sel and true or false) end
local function track_guid(tr) return reaper.GetTrackGUID(tr) end
local function get_selected_tracks_set_and_sig()
  local set = {}
  local n = reaper.CountSelectedTracks(0)
  for i=0, n-1 do
    local tr = reaper.GetSelectedTrack(0, i)
    set[track_guid(tr)] = true
  end
  return set, tconcat_keys_sorted(set)
end

----------------
-- Item helpers (selected only)
----------------
local function item_bounds(it)
  local pos = reaper.GetMediaItemInfo_Value(it,"D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
  return pos, pos+len
end

local function get_selected_items_info()
  local n = reaper.CountSelectedMediaItems(0)
  local sig_parts = {}
  local span_min, span_max = math.huge, -math.huge
  local tracks_with_sel_items = {}

  for i=0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    sig_parts[#sig_parts+1] = g or tostring(it)
    local s, e = item_bounds(it)
    if s < span_min then span_min = s end
    if e > span_max then span_max = e end
    local tr = reaper.GetMediaItem_Track(it)
    if tr then tracks_with_sel_items[track_guid(tr)] = true end
  end

  local has_span = (#sig_parts > 0) and (span_max > span_min)
  return {
    count = n,
    sig   = table.concat(sig_parts, "|"),
    span_s= has_span and span_min or nil,
    span_e= has_span and span_max or nil,
    tr_set= tracks_with_sel_items,
    tr_sig= tconcat_keys_sorted(tracks_with_sel_items),
  }
end

local function item_matches_range(s,e,rs,re_)
  if RANGE_MODE == 1 then return (e > rs + EPS) and (s < re_ - EPS)
  else                     return (s >= rs - EPS) and (e <= re_ + EPS)
  end
end

local function track_select_items_matching_range(tr, rs, re_, sel)
  local n = reaper.CountTrackMediaItems(tr)
  if n == 0 then return end
  for i=0, n-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local s, e = item_bounds(it)
    if item_matches_range(s, e, rs, re_) then
      reaper.SetMediaItemInfo_Value(it, "B_UISEL", sel and 1 or 0)
    end
  end
end

----------------
-- Razor cache & helpers
----------------
local Razor = {
  sig = "",
  t_has = {},     -- [track_guid] = true/false
  t_ranges = {},  -- [track_guid] = { {s,e}, ... } (track-level only)
  union_s = nil,
  union_e = nil,
  cnt_tracks_with = 0,
  last_scan_psc = -1,
}

local function parse_triplets(s)
  local out = {}
  if not s or s=="" then return out end
  local toks = {}
  for w in s:gmatch("%S+") do toks[#toks+1] = w end
  for i=1,#toks,3 do
    local a = tonumber(toks[i]); local b = tonumber(toks[i+1]); local g = toks[i+2] or "\"\""
    if a and b and b>a then out[#out+1] = {a,b,g} end
  end
  return out
end

local function set_track_level_ranges(tr, newRanges)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr,"P_RAZOREDITS","",false)
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

local function scan_razors_if_needed(psc)
  if Razor.last_scan_psc == psc then return end
  Razor.last_scan_psc = psc
  Razor.sig = ""
  Razor.t_has, Razor.t_ranges = {}, {}
  Razor.union_s, Razor.union_e = nil, nil
  Razor.cnt_tracks_with = 0

  local tcnt = reaper.CountTracks(0)
  local parts = {}
  for i=0, tcnt-1 do
    local tr = reaper.GetTrack(0,i)
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr,"P_RAZOREDITS","",false)
    s = (ok and s) and s or ""
    parts[#parts+1] = s
    local g = track_guid(tr)
    local ranges = {}
    for _, t in ipairs(parse_triplets(s)) do
      if t[3] == "\"\"" then
        ranges[#ranges+1] = {t[1], t[2]}
        Razor.union_s = (not Razor.union_s) and t[1] or math.min(Razor.union_s, t[1])
        Razor.union_e = (not Razor.union_e) and t[2] or math.max(Razor.union_e, t[2])
      end
    end
    if #ranges > 0 then
      Razor.t_has[g] = true
      Razor.t_ranges[g] = ranges
      Razor.cnt_tracks_with = Razor.cnt_tracks_with + 1
    else
      Razor.t_has[g] = false
    end
  end
  Razor.sig = table.concat(parts, "|")
end

----------------
-- Time selection helpers
----------------
local function get_time_selection()
  local ts, te = reaper.GetSet_LoopTimeRange(false,false,0,0,false)
  if te > ts then return ts, te end
end

----------------
-- Latched virtual range + suppression
----------------
local latched_vs, latched_ve = nil, nil
local suppress_latch_next = false   -- NEW: skip next relatch if items were changed by script
local last_cursor = reaper.GetCursorPosition()

local function active_range(selected_items_info)
  if Razor.cnt_tracks_with > 0 and Razor.union_s and Razor.union_e and Razor.union_e > Razor.union_s then
    return Razor.union_s, Razor.union_e, "razor"
  end
  if latched_vs and latched_ve and latched_ve > latched_vs then
    return latched_vs, latched_ve, "virtual_latched"
  end
  if selected_items_info and selected_items_info.span_s and selected_items_info.span_e then
    return selected_items_info.span_s, selected_items_info.span_e, "virtual"
  end
  return nil, nil, nil
end

----------------
-- Shared state publisher (only on change)
----------------
local EXT_NS = "hsuanice_Link"
local last_published = {}
local function publish_once(args)
  local function fmtf(x) return x and string.format("%.17f",x) or "" end
  local payload = {
    active_src = args.active_src or "none",
    active_s   = fmtf(args.active_s),
    active_e   = fmtf(args.active_e),
    item_s     = fmtf(args.item_s),
    item_e     = fmtf(args.item_e),
    virt_s     = fmtf(args.virt_s),
    virt_e     = fmtf(args.virt_e),
    ts_s       = fmtf(args.ts_s),
    ts_e       = fmtf(args.ts_e),
    has_razor  = args.has_razor and "1" or "0",
    ts_has_real= (args.ts_s and args.ts_e) and "1" or "0",
  }
  local dirty = false
  for k,v in pairs(payload) do if last_published[k] ~= v then dirty = true; break end end
  if not dirty then return end
  reaper.SetProjExtState(0, EXT_NS, "active_src", payload.active_src)
  reaper.SetProjExtState(0, EXT_NS, "active_start", payload.active_s)
  reaper.SetProjExtState(0, EXT_NS, "active_end",   payload.active_e)
  reaper.SetProjExtState(0, EXT_NS, "item_span_start", payload.item_s)
  reaper.SetProjExtState(0, EXT_NS, "item_span_end",   payload.item_e)
  reaper.SetProjExtState(0, EXT_NS, "virt_latched_start", payload.virt_s)
  reaper.SetProjExtState(0, EXT_NS, "virt_latched_end",   payload.virt_e)
  reaper.SetProjExtState(0, EXT_NS, "ts_start", payload.ts_s)
  reaper.SetProjExtState(0, EXT_NS, "ts_end",   payload.ts_e)
  reaper.SetProjExtState(0, EXT_NS, "has_razor", payload.has_razor)
  reaper.SetProjExtState(0, EXT_NS, "ts_has_real", payload.ts_has_real)
  last_published = payload
end

----------------
-- Signatures / state
----------------
local prev = {
  psc = -1,
  ts_s = nil, ts_e = nil,
  cursor = last_cursor,
  tr_sel_sig = "",
  it_sel_sig = "",
  it_tr_sig  = "",
  razor_sig  = "",
}

----------------
-- Main loop
----------------
local function mainloop()
  local psc = reaper.GetProjectStateChangeCount(0)
  local cursor = reaper.GetCursorPosition()
  local ts, te = get_time_selection()

  local sel_tracks_set, tr_sel_sig = get_selected_tracks_set_and_sig()
  local it_info = get_selected_items_info()
  local it_sel_sig = it_info.sig
  local it_tr_sig  = it_info.tr_sig

  if psc ~= prev.psc then scan_razors_if_needed(psc) end

  -- LATCH management (with suppression)
  if Razor.cnt_tracks_with > 0 or (ts and te) then
    latched_vs, latched_ve = nil, nil
    suppress_latch_next = false
  else
    if (not latched_vs) and it_info.span_s and it_info.span_e and (not suppress_latch_next) then
      latched_vs, latched_ve = it_info.span_s, it_info.span_e
    end
    if (it_sel_sig ~= prev.it_sel_sig) and (tr_sel_sig == prev.tr_sel_sig) and (not ts) then
      if not suppress_latch_next then
        if it_info.span_s and it_info.span_e then
          latched_vs, latched_ve = it_info.span_s, it_info.span_e
        else
          latched_vs, latched_ve = nil, nil
        end
      end
    end
    if LATCH_CLEAR_ON_CURSOR_MOVE and (not nearly_eq(cursor, prev.cursor)) then
      latched_vs, latched_ve = nil, nil
      suppress_latch_next = false
    end
  end
  -- consume suppression after decision phase
  suppress_latch_next = false

  -- === Sync logic ===

  -- A) Razor changed → Track selection equals "tracks with razor"
  if (Razor.sig ~= prev.razor_sig) and (Razor.cnt_tracks_with > 0) then
    reaper.PreventUIRefresh(1)
    local want = Razor.t_has
    local tcnt = reaper.CountTracks(0)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local g  = track_guid(tr)
      local should = want[g] or false
      local is     = sel_tracks_set[g] or false
      if should ~= is then set_track_selected(tr, should) end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    sel_tracks_set, tr_sel_sig = get_selected_tracks_set_and_sig()
  end

  -- B) Items changed (or their track set) and NO Razor → Track selection follows items' tracks
  if (Razor.cnt_tracks_with == 0) and ((it_sel_sig ~= prev.it_sel_sig) or (it_tr_sig ~= prev.it_tr_sig)) then
    reaper.PreventUIRefresh(1)
    local want = it_info.tr_set
    for g,_ in pairs(sel_tracks_set) do
      if not want[g] then
        local tr = reaper.BR_GetMediaTrackByGUID and reaper.BR_GetMediaTrackByGUID(0, g) or nil
        if not tr then
          local tcnt2 = reaper.CountTracks(0)
          for i=0, tcnt2-1 do
            local tr2 = reaper.GetTrack(0,i)
            if track_guid(tr2) == g then tr = tr2; break end
          end
        end
        if tr then set_track_selected(tr, false) end
      end
    end
    local tcnt = reaper.CountTracks(0)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local g  = track_guid(tr)
      if want[g] and (not sel_tracks_set[g]) then set_track_selected(tr, true) end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    sel_tracks_set, tr_sel_sig = get_selected_tracks_set_and_sig()
  end

  -- C) Track selection changed + REAL TS present → build/remove Razor on changed tracks + sync items
  if tr_sel_sig ~= prev.tr_sel_sig and ts and te then
    local prev_set = {}; for g in string.gmatch(prev.tr_sel_sig or "", "[^|]+") do prev_set[g] = true end
    local changed = {}
    for g,_ in pairs(sel_tracks_set) do if not prev_set[g] then changed[g] = true end end
    for g,_ in pairs(prev_set) do if not sel_tracks_set[g] then changed[g] = true end end

    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local g  = track_guid(tr)
      if changed[g] then
        if sel_tracks_set[g] then
          set_track_level_ranges(tr, { {ts, te} })
          track_select_items_matching_range(tr, ts, te, true)
        else
          set_track_level_ranges(tr, {})
          track_select_items_matching_range(tr, ts, te, false)
        end
      end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    suppress_latch_next = true  -- items were changed by script due to track change
  end

  -- D) Razor/Track changed → sync items under ACTIVE range (only on changed tracks)
  local a_s, a_e, a_src = active_range(it_info)
  if (a_s and a_e) and ((Razor.sig ~= prev.razor_sig) or (tr_sel_sig ~= prev.tr_sel_sig)) then
    local prev_set = {}; for g in string.gmatch(prev.tr_sel_sig or "", "[^|]+") do prev_set[g] = true end
    local changed = {}
    for g,_ in pairs(sel_tracks_set) do if not prev_set[g] then changed[g] = true end end
    for g,_ in pairs(prev_set) do if not sel_tracks_set[g] then changed[g] = true end end

    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local g  = track_guid(tr)
      if changed[g] then
        local sel = sel_tracks_set[g] or false
        if a_src == "razor" then
          local ranges = Razor.t_ranges[g] or {}
          if #ranges > 0 then
            for _, r in ipairs(ranges) do track_select_items_matching_range(tr, r[1], r[2], sel) end
          else
            track_select_items_matching_range(tr, a_s, a_e, false)
          end
        else
          track_select_items_matching_range(tr, a_s, a_e, sel)
        end
      end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    suppress_latch_next = true  -- items were changed by script due to track change
  end

  -- Publish
  do
    publish_once{
      active_src = a_src or "none",
      active_s   = a_s, active_e = a_e,
      item_s     = it_info.span_s, item_e = it_info.span_e,
      virt_s     = latched_vs, virt_e = latched_ve,
      ts_s       = ts, ts_e = te,
      has_razor  = (Razor.cnt_tracks_with > 0)
    }
  end

  -- Save prev
  prev.psc = psc
  prev.cursor = cursor
  prev.ts_s, prev.ts_e = ts, te
  prev.tr_sel_sig = tr_sel_sig
  prev.it_sel_sig = it_sel_sig
  prev.it_tr_sig  = it_tr_sig
  prev.razor_sig  = Razor.sig

  reaper.defer(mainloop)
end

mainloop()
