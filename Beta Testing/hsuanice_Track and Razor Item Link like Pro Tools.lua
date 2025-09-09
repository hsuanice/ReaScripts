--[[
@description Track and Razor Item Link like Pro Tools (performance edition)
@version 0.12.0 Integrated Click-select Track
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

  Notes:
    • ABCD switches added (USER OPTIONS) to enable/disable each main section:
        A) Razor changed → Track selection follows "tracks with Razor"
        B) Items changed (no Razor) → Track selection follows items' tracks
        C) Track selection changed + REAL TS → build/clear Razor + sync items (Overlap)
        D) Razor/Track changed → sync items under ACTIVE range on changed tracks
    • DEBUG_PRINT will log which section fired (A/B/C/D) for instant diagnosis.

  Credits:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.12.0
  - NEW: Integrated "Click-select Track" watcher (mouse-up/down, item upper-half option, popup guard).
    • Runs at the start of each cycle so ABCD logic sees the fresh track selection.
    • Options: ENABLE_CLICK_SELECT_TRACK, CLICK_SELECT_ON_MOUSE_UP, CLICK_ENABLE_ITEM_UPPER_HALF, etc.
  - No changes to ABCD semantics. Interop with Razor↔Item master toggle preserved.
  v0.11.0
    - NEW: ABCD per-section switches in USER OPTIONS (ENABLE_A..D) for fast isolation & debugging.
    - NEW: DEBUG_PRINT flag + dbg() helper to log which section fires (A/B/C/D) each tick.
    - Behavior unchanged when all ENABLE_* = true (backward-compatible).
    - Tip presets (commented): set ENABLE_A=false & ENABLE_B=false to fully disable Arrange→TCP linking.
  v0.10.2 
    - temp turn off AB block
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

-- === CLICK-SELECT (integrated) OPTIONS ===
local ENABLE_CLICK_SELECT_TRACK       = true    -- 總開關：整合版「點一下選軌」
local CLICK_SELECT_ON_MOUSE_UP        = true    -- true: mouse-up、false: mouse-down（建議用 mouse-up）
local CLICK_ENABLE_ITEM_UPPER_HALF    = false   -- 點 Item 上半部也算選軌
local CLICK_TOLERANCE_PX              = 3       -- mouse-up 模式允許的微小移動像素
local CLICK_SUPPRESS_RBUTTON_MENU     = true    -- 有右鍵選單或剛放開右鍵的冷卻期內，不處理左鍵點擊
local CLICK_RBUTTON_COOLDOWN_SEC      = 0.10    -- 右鍵放開後冷卻時間（秒）
local CLICK_WANT_DEBUG                = false   -- 顯示 Click 模組除錯訊息


-- Range matching for item-range checks inside C/D when needed:
-- 1=overlap, 2=contain (default: contain)
local RANGE_MODE = 2

-- Clear latched virtual range on cursor move
local LATCH_CLEAR_ON_CURSOR_MOVE = true

-- ====== ABCD section switches ======
-- A) Razor changed → Track selection equals "tracks with razor"
local ENABLE_A = true
-- B) Items changed (and NO Razor) → Track selection follows items' tracks (absolute set)
local ENABLE_B = true
-- C) Track selection changed + REAL TS → build/clear Razor + sync items (Overlap)
local ENABLE_C = true
-- D) Razor/Track changed → sync items under ACTIVE range (only on changed tracks)
local ENABLE_D = true

-- (Quick preset to disable Arrange→TCP fully)
-- ENABLE_A = false; ENABLE_B = false

-- Debug console print which section fired (A/B/C/D)
local DEBUG_PRINT = false
---------------------------------------

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
local function dbg(fmt, ...)
  if not DEBUG_PRINT then return end
  reaper.ShowConsoleMsg(("[LinkDBG] "..fmt.."\n"):format(...))
end

-- Honor external master toggle from companion script:
-- Namespace: "hsuanice_RazorItemLink", key: "enabled" (true/false, 1/0, on/off)
local function is_razor_item_link_enabled()
  local _, v = reaper.GetProjExtState(0, "hsuanice_RazorItemLink", "enabled")
  if v == "" then return true end  -- default ON for backward-compat
  v = v:lower()
  return not (v == "0" or v == "false" or v == "off")
end

-- === CLICK-SELECT helpers (popup/menu guard + geometry + hit test) ===
local function Click_Log(msg)
  if CLICK_WANT_DEBUG then reaper.ShowConsoleMsg(("[Click] %s\n"):format(tostring(msg))) end
end

local function Click_IsPopupMenuOpen()
  if not reaper.APIExists("JS_Window_Find") then return false end
  local h1 = reaper.JS_Window_Find("#32768", true) -- Windows context menu
  if h1 and h1 ~= 0 then return true end
  local h2 = reaper.JS_Window_Find("NSMenu", true) -- macOS menu
  if h2 and h2 ~= 0 then return true end
  return false
end

-- Parse "P_UI_RECT:tcp.size" to x,y,w,h
local function Click_GetTrackTCPRect(tr)
  local ok, rect = reaper.GetSetMediaTrackInfo_String(tr, "P_UI_RECT:tcp.size", "", false)
  if not ok or not rect or rect == "" then return end
  local a,b,c,d = rect:match("(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)")
  if not a then return end
  a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  if not (a and b and c and d) then return end
  if c > a and d > b then return a,b,(c-a),(d-b) else return a,b,c,d end
end

-- 命中測試：回傳「要被選取的 track」或 nil
local function Click_TrackIfSelectTarget(x, y)
  local _, info = reaper.GetThingFromPoint(x, y)
  local isArrange = (info == "arrange") or (type(info)=="string" and info:find("arrange",1,true))
  if not isArrange then return nil, ("not arrange (info=%s)"):format(tostring(info)) end

  local item = reaper.GetItemFromPoint(x, y, true)
  if item then
    if not CLICK_ENABLE_ITEM_UPPER_HALF then
      return nil, "clicked on item (upper-half select disabled)"
    end
    local tr = reaper.GetMediaItem_Track(item); if not tr then return nil, "no track for item" end
    local item_rel_y = reaper.GetMediaItemInfo_Value(item, "I_LASTY") or 0
    local item_h     = reaper.GetMediaItemInfo_Value(item, "I_LASTH") or 0
    local tx, ty, tw, th = Click_GetTrackTCPRect(tr)
    if not (ty and th and item_h and item_h>0) then return nil, "couldn't resolve track/item rect" end
    local item_top = ty + item_rel_y
    local item_mid = item_top + (item_h * 0.5)
    if y <= item_mid then return tr, "clicked item upper half" else return nil, "clicked item lower half" end
  end

  local tr = reaper.GetTrackFromPoint(x, y)
  if not tr then return nil, "no track at this point (ruler/gap?)" end
  return tr, "clicked arrange empty"
end

local function Click_SelectOnlyTrack(tr)
  if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
    reaper.SetOnlyTrackSelected(tr)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
  end
end



-- === CLICK-SELECT state ===
local CLICK_lastDown = false
local CLICK_lastDownPos = {x=nil, y=nil}
local CLICK_rbtn_down_time = -1
local CLICK_rbtn_up_time   = -1

-- 每圈呼叫；若這一圈內「真的有處理一個點擊→選軌」，回傳 true
local function Click_TickMaybeSelectTrack()
  if not ENABLE_CLICK_SELECT_TRACK then return false end
  if Click_IsPopupMenuOpen() then
    CLICK_lastDown = false
    return false
  end
  if not reaper.APIExists("JS_Mouse_GetState") then
    -- 沒有 js_ReaScriptAPI 就不做點擊整合
    return false
  end

  local state = reaper.JS_Mouse_GetState(1 + 2) -- 左鍵+右鍵
  local x, y  = reaper.GetMousePosition()
  local lmb   = (state & 1) == 1

  -- 右鍵守門與冷卻
  if CLICK_SUPPRESS_RBUTTON_MENU then
    local now = reaper.time_precise()
    if (state & 2) == 2 then
      if CLICK_rbtn_down_time < 0 then CLICK_rbtn_down_time = now end
      CLICK_lastDown = false
      return false
    else
      if CLICK_rbtn_down_time >= 0 and CLICK_rbtn_up_time < CLICK_rbtn_down_time then
        CLICK_rbtn_up_time = now; CLICK_rbtn_down_time = -1; CLICK_lastDown = false
      end
      if CLICK_rbtn_up_time >= 0 and (now - CLICK_rbtn_up_time) < CLICK_RBUTTON_COOLDOWN_SEC then
        return false
      end
    end
  end

  local did = false
  if CLICK_SELECT_ON_MOUSE_UP then
    if lmb then
      if not CLICK_lastDown then
        CLICK_lastDown = true
        CLICK_lastDownPos.x, CLICK_lastDownPos.y = x, y
      end
    else
      if CLICK_lastDown then
        CLICK_lastDown = false
        local dx = math.abs(x - (CLICK_lastDownPos.x or x))
        local dy = math.abs(y - (CLICK_lastDownPos.y or y))
        if dx <= CLICK_TOLERANCE_PX and dy <= CLICK_TOLERANCE_PX then
          local tr, why = Click_TrackIfSelectTarget(x, y)
          if tr then
            reaper.Undo_BeginBlock()
            Click_SelectOnlyTrack(tr)
            reaper.Undo_EndBlock("Click-select track (integrated, mouse-up)", -1)
            Click_Log(("selected track (%s)"):format(tostring(why)))
            did = true
          else
            Click_Log(("skip: %s"):format(tostring(why)))
          end
        end
      end
    end
  else
    -- mouse-down 模式
    if lmb and not CLICK_lastDown then
      CLICK_lastDown = true
      local tr, why = Click_TrackIfSelectTarget(x, y)
      if tr then
        reaper.Undo_BeginBlock()
        Click_SelectOnlyTrack(tr)
        reaper.Undo_EndBlock("Click-select track (integrated, mouse-down)", -1)
        Click_Log(("selected track (%s)"):format(tostring(why)))
        did = true
      else
        Click_Log(("skip: %s"):format(tostring(why)))
      end
    elseif (not lmb) and CLICK_lastDown then
      CLICK_lastDown = false
    end
  end

  return did
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
  mode = mode or RANGE_MODE   -- 1=overlap, 2=contain
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
  -- 先處理 Click-select（讓後續 A/B/C/D 看見本次點擊帶來的「選軌」變化）
  local CLICK_did_select = Click_TickMaybeSelectTrack()
  -----------------------------------------------------
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
  if ENABLE_A
     and (Razor.sig ~= prev.razor_sig)
     and (Razor.cnt_tracks_with > 0)
     and (tr_sel_sig == prev.tr_sel_sig)
  then
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
    triggered_side = "TRACKS"
    dbg("A fired: Razor→Tracks")
  end

  -- B) Items changed (or their track set) and NO Razor → Track selection follows items' tracks (absolute set)
  if ENABLE_B
     and (Razor.cnt_tracks_with == 0)
     and items_changed_this_tick
     and triggered_side ~= "TRACKS"
  then
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
    dbg("B fired: Items→Tracks (no Razor)")
  end

  -- C) Track selection changed + REAL TS present → build/remove Razor + sync items
  --    BUT skip if tracks_changed_by_items (e.g. came from 40182 Select-All)
  if ENABLE_C
     and (tr_sel_sig ~= prev.tr_sel_sig)
     and ts and te
     and (not tracks_changed_by_items)
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
        if sel_tracks_set[g] then
          set_track_level_ranges(tr, { {ts, te} })
          if is_razor_item_link_enabled() then
            track_select_items_matching_range(tr, ts, te, true,  1) -- Overlap
          end
        else
          set_track_level_ranges(tr, {})
          if is_razor_item_link_enabled() then
            track_select_items_matching_range(tr, ts, te, false, 1) -- Overlap
          end
        end
      end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    suppress_latch_next = true
    dbg("C fired: Tracks+TS→Razor/Items (Overlap)")
  end

  -- D) Razor/Track changed → sync items under ACTIVE range (only on changed tracks)
  --    BUT skip if tracks_changed_by_items to avoid re-touching selection right after Select-All
  local a_s, a_e, a_src = active_range(it_info)
  if ENABLE_D
     and (a_s and a_e)
     and ((Razor.sig ~= prev.razor_sig) or (tr_sel_sig ~= prev.tr_sel_sig))
     and (not tracks_changed_by_items)
     and triggered_side ~= "ITEMS"
     and (is_razor_item_link_enabled() or (a_src ~= "razor"))
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
            for _, r in ipairs(ranges) do track_select_items_matching_range(tr, r[1], r[2], sel, 1) end -- Overlap
          else
            track_select_items_matching_range(tr, a_s, a_e, false, 1)                                   -- Overlap
          end
        else
          track_select_items_matching_range(tr, a_s, a_e, sel)
        end
      end
    end
    reaper.PreventUIRefresh(-1); reaper.UpdateArrange()
    suppress_latch_next = true
    triggered_side = "TRACKS"
    dbg("D fired: Razor/Tracks→Items (Active=%s)", a_src or "none")
  end

  -- Publish (monitor)
  do
    publish_once{
      active_src = a_src or "none",
      active_s   = a_s, active_e = a_e,
      item_s     = it_info.span_s, item_e = it_info.span_e,
      virt_s     = latched_vs,     virt_e = latched_ve,
      ts_s       = ts,             ts_e   = te,
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
