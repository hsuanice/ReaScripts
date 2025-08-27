--[[
@description Track and Razor Item Link like Pro Tools (performance edition)
@version 0.10.1
@author hsuanice
@about
  Pro Tools-style "Link Track and Edit Selection". 
  Edit Selection = Razor Area or Item Selection.

  Perf principles:
    • Gate heavy scans by GetProjectStateChangeCount().
    • Enumerate ONLY selected tracks/items when possible.
    • Cache per-track Razor; recompute on project-state changes only.
    • Apply changes only on delta tracks; publish ExtState only on change.
    • Keep Latched Virtual Range; avoid shrinking on track toggles.

  Priority:
    1) Razor exists → use Razor (highest)
    2) Else Item Selection → use VIRTUAL (latched) span [min..max]
    3) Else no active range

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.



@changelog
  v0.10.1
    - TCP → Razor toggle honors Edit Link (ON) with Overlap selection:
        • When Edit Link is ON, items overlapping the Razor range are selected/unselected
          as you toggle tracks in TCP (C block now calls Overlap explicitly). 
        • When Edit Link is OFF, still builds/clears Razor for visualization but does not touch item selection.
    - Align Razor-sourced sync (D block) to Overlap as well, so it won’t “rewrite” C’s Overlap with Contain.
    - Internal: item/range matcher and per-track selector now accept an explicit match mode parameter;
      no extra enumeration or UI refresh added (perf-neutral).
  v0.10.0
    - Interop: respect external Edit Link master toggle (Project ExtState):
        • Namespace "hsuanice_RazorItemLink", Key "enabled" ("1"/"0")
        • OFF → skip Razor→Items sync (D) AND suppress TS→Items in C
               (still builds/clears Razor ranges for visual feedback)
        • ON / unset → behavior unchanged (backward-compatible)
    - Fix: C-block if/else structure (remove stray "..." placeholder) and
           avoid duplicate local RIL_enabled; eliminates syntax error/crash.
    - Perf: only adds a constant-time flag check; no extra enumerations;
            UpdateArrange usage unchanged.
    - Meta: align namespace names; keep "Note" credits in header.
    v0.9.0
      - NEW: One-side trigger guard — prevents "ping-pong" (items→tracks→items) within the same cycle.
      - Stable across all test cases (Razor, Virtual, Time Selection, Select-All 40182).
      - Confirmed performance-friendly under large sessions (200+ tracks, thousands of items).
    v0.8.5 - perf-bugfix4  - Internal testing build (single-side trigger, pre-official).
    v0.8.5 - perf-bugfix3  - Gate: skip C/D if tracks changed due to items this tick (e.g. Select-All).
    v0.8.4 - perf-bugfix2  - Step B: absolute set for track selection to avoid edge cases after 40182.
    v0.8.3 - perf-bugfix   - Fix "need to click twice" with Razor; canonical Razor signature.
    v0.8.2 - perf          - Suppress relatch shrink after script-driven item changes.
    v0.8.1 - perf-hotfix   - Restore set_track_level_ranges().
    v0.8.0 - perf          - Major perf pass.
]]


-------------------------
-- === USER OPTIONS === --
-------------------------
local RANGE_MODE = 2  -- 1=overlap, 2=contain
local LATCH_CLEAR_ON_CURSOR_MOVE = true

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

-- Honor external master toggle from companion script:
-- Namespace: "hsuanice_RazorItemLink", key: "enabled" (true/false, 1/0, on/off)
local function is_razor_item_link_enabled()
  local _, v = reaper.GetProjExtState(0, "hsuanice_RazorItemLink", "enabled")
  if v == "" then return true end  -- default ON for backward-compat
  v = v:lower()
  return not (v == "0" or v == "false" or v == "off")
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

local function item_matches_range(s,e,rs,re_, mode)
  mode = mode or RANGE_MODE   -- 1=overlap, 2=contain (default=global)
  if mode == 1 then
    return (e > rs + EPS) and (s < re_ - EPS)     -- overlap
  else
    return (s >= rs - EPS) and (e <= re_ + EPS)   -- contain（含EPS，含邊界）
  end
end

local function track_select_items_matching_range(tr, rs, re_, sel, mode)
  local n = reaper.CountTrackMediaItems(tr)
  if n == 0 then return end
  for i=0, n-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local s, e = item_bounds(it)
    if item_matches_range(s, e, rs, re_, mode) then
      reaper.SetMediaItemInfo_Value(it, "B_UISEL", sel and 1 or 0)
    end
  end
end

----------------
-- Razor cache & helpers
----------------
local Razor = {
  sig = "",             -- canonical signature
  t_has = {},           -- [track_guid]=bool
  t_ranges = {},        -- [track_guid] = { {s,e}, ... } (track-level only)
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

local function canonical_track_ranges_str(ranges)
  if not ranges or #ranges==0 then return "" end
  table.sort(ranges, function(a,b) return (a[1]<b[1]) or (a[1]==b[1] and a[2]<b[2]) end)
  local parts = {}
  for i=1,#ranges do
    parts[#parts+1] = string.format("%.9f:%.9f", ranges[i][1], ranges[i][2])
  end
  return table.concat(parts, ";")
end

local function scan_razors_if_needed(psc)
  if Razor.last_scan_psc == psc then return end
  Razor.last_scan_psc = psc

  Razor.t_has, Razor.t_ranges = {}, {}
  Razor.union_s, Razor.union_e = nil, nil
  Razor.cnt_tracks_with = 0

  local tcnt = reaper.CountTracks(0)
  local sig_parts = {}

  for i=0, tcnt-1 do
    local tr = reaper.GetTrack(0,i)
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr,"P_RAZOREDITS","",false)
    s = (ok and s) and s or ""
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
      Razor.t_ranges[g] = {}
    end
    sig_parts[#sig_parts+1] = canonical_track_ranges_str(Razor.t_ranges[g])
  end

  Razor.sig = table.concat(sig_parts, "|")
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
local suppress_latch_next = false
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
  local triggered_side = nil -- "ITEMS" or "TRACKS"  
  local psc = reaper.GetProjectStateChangeCount(0)
  local cursor = reaper.GetCursorPosition()
  local ts, te = get_time_selection()
  local RIL_enabled = is_razor_item_link_enabled()

  local sel_tracks_set, tr_sel_sig = get_selected_tracks_set_and_sig()
  local it_info = get_selected_items_info()
  local it_sel_sig = it_info.sig
  local it_tr_sig  = it_info.tr_sig

  if psc ~= prev.psc then scan_razors_if_needed(psc) end

  -- Did items change this tick?
  local items_changed_this_tick = (it_sel_sig ~= prev.it_sel_sig) or (it_tr_sig ~= prev.it_tr_sig)
  local tracks_changed_by_items = false

  -- LATCH management (with suppression)
  if Razor.cnt_tracks_with > 0 or (ts and te) then
    latched_vs, latched_ve = nil, nil
    suppress_latch_next = false
  else
    if (not latched_vs) and it_info.span_s and it_info.span_e and (not suppress_latch_next) then
      latched_vs, latched_ve = it_info.span_s, it_info.span_e
    end
    if items_changed_this_tick and (tr_sel_sig == prev.tr_sel_sig) and (not ts) then
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
  suppress_latch_next = false -- consume after decision

  -- === Sync logic ===

  -- A) Razor changed → Track selection equals "tracks with razor"
  --    Only if track selection did NOT change this tick (so we don't override a user click).
  if (Razor.sig ~= prev.razor_sig) and (Razor.cnt_tracks_with > 0) and (tr_sel_sig == prev.tr_sel_sig) then
    reaper.PreventUIRefresh(1)
    local want = Razor.t_has
    local tcnt = reaper.CountTracks(0)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local g  = track_guid(tr)
      set_track_selected(tr, want[g] or false)
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    sel_tracks_set, tr_sel_sig = get_selected_tracks_set_and_sig()
    triggered_side = "TRACKS"  -- ★ 新增：標記同輪已由 Tracks 端觸發
  end

  -- B) Items changed (or their track set) and NO Razor → Track selection follows items' tracks (absolute set)
  if (Razor.cnt_tracks_with == 0) and items_changed_this_tick and triggered_side ~= "TRACKS" then
    reaper.PreventUIRefresh(1)
    local want = it_info.tr_set
    local tcnt = reaper.CountTracks(0)
    for i=0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local g  = track_guid(tr)
      set_track_selected(tr, want[g] or false)
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    sel_tracks_set, tr_sel_sig = get_selected_tracks_set_and_sig()
    tracks_changed_by_items = true
    triggered_side = "ITEMS"    
  end

  -- C) Track selection changed + REAL TS present → build/remove Razor + sync items
  --    BUT skip if tracks_changed_by_items (e.g. came from 40182 Select-All)
  if (tr_sel_sig ~= prev.tr_sel_sig) and ts and te and (not tracks_changed_by_items) then
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
          if RIL_enabled then track_select_items_matching_range(tr, ts, te, true,  1) end  -- Overlap
        else
          set_track_level_ranges(tr, {})
          if RIL_enabled then track_select_items_matching_range(tr, ts, te, false, 1) end  -- Overlap

        end
      end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    suppress_latch_next = true
  end

  -- D) Razor/Track changed → sync items under ACTIVE range (only on changed tracks)
  --    BUT skip if tracks_changed_by_items to avoid re-touching selection right after Select-All
  local a_s, a_e, a_src = active_range(it_info)
  if (a_s and a_e)
    and ((Razor.sig ~= prev.razor_sig) or (tr_sel_sig ~= prev.tr_sel_sig))
    and (not tracks_changed_by_items)
    and triggered_side ~= "ITEMS"
    and (RIL_enabled or (a_src ~= "razor"))
  then
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
          local ranges = (Razor.t_ranges[g] or {})
          if #ranges > 0 then
            for _, r in ipairs(ranges) do track_select_items_matching_range(tr, r[1], r[2], sel,   1) end  -- Overlap
          else
            track_select_items_matching_range(tr, a_s, a_e, false, 1)                                    -- Overlap
          end
        else
          track_select_items_matching_range(tr, a_s, a_e, sel)
        end
      end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    suppress_latch_next = true
    triggered_side = "TRACKS"
  end

  -- Publish (monitor)
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
