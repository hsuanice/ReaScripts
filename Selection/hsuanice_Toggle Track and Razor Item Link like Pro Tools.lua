--[[
@description Toggle Track and Razor Item Link like Pro Tools - Link Track and Edit Selection
@version 26.1023.1358pre1
@author hsuanice
@changelog
  - Change: part D (sync items when the Razor area or track selection changes) is now off by default (ENABLE_D = false): with D on, linking track selection to items also triggered the item-to-track direction, which cleared the intended selection.
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
--]]
-------------------------
-- === USER OPTIONS === --
-------------------------

-- === CLICK-SELECT (integrated) OPTIONS ===
local ENABLE_CLICK_SELECT_TRACK        = false    -- integrated click-to-select-track (must take over track selection to emulate PT behavior)
local CLICK_SELECT_ON_MOUSE_UP         = true   -- mouse-up recommended
local CLICK_ENABLE_ITEM_UPPER_HALF     = false  -- clicking the upper half of an item does not select the track
local CLICK_TOLERANCE_PX               = 3      -- click movement tolerance (px)

local CLICK_FOCUS_RETURN_GRACE_SEC     = 0.20   -- grace window after focus returns

-- Debug
local CLICK_WANT_DEBUG                 = false  -- enable when needed


-- === CLICK-SELECT hook phase ===
-- "pre":  handle click → select track at the start of mainloop (the 0.12.0 approach)
-- "post": handle it at the end of mainloop (default in this version, so ABCD sees the track change on the next loop)
local CLICK_HOOK_PHASE = "post"
--------------------------------

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

-- ====== Direction-specific sub-switches ======
-- C sub) Whether track-selection change builds/clears Razor (requires ENABLE_C = true)
local ENABLE_TRACKS_TO_RAZOR = true
-- D sub) Whether track-selection change triggers item sync (requires ENABLE_D = true)
--        Set false to keep Razor→Items active while blocking Track→Items.
local ENABLE_TRACKS_TO_ITEMS = true

-- (Quick preset to disable Arrange→TCP fully)
-- ENABLE_A = false; ENABLE_B = false

-- Debug console print which section fired (A/B/C/D)
local DEBUG_PRINT = false
---------------------------------------

-- ================================================
-- WM_LBUTTONDOWN / WM_LBUTTONUP intercept  (Pro Tools guard — no-flicker)
--
-- REAPER selects tracks on mouse-UP.  On mouse-DOWN we check the click
-- target.  If it's a selected item we disable 'trackselonmouse' before
-- REAPER's up-handler fires → wrong-track flash never happens.
-- Pref is restored immediately on mouse-UP.
--
-- passthrough=true on both messages: REAPER still receives all clicks for
-- item selection, dragging, rubber-band, etc.
-- RMB context menus live in a separate HWND → guard never fires for them.
--
-- Fallback (no SNM extension): manual track-selection restoration after the
-- fact (may flash ~1 frame, same as original behaviour).
-- ================================================
local _WM_HWND        = nil
local _WM_DOWN_LAST   = 0
local _WM_UP_LAST     = 0
local _guard_prev_lmb = false   -- fallback polling edge-detector
local _guard_blocking = false   -- true while trackselonmouse is suppressed
local _guard_orig_pref = 1      -- saved pref value

local function wm_setup()
  if not reaper.APIExists("JS_WindowMessage_Intercept") then return false end
  if not reaper.APIExists("JS_WindowMessage_Peek")      then return false end
  local arrange = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
  if not arrange then return false end
  local r = reaper.JS_WindowMessage_Intercept(arrange, "WM_LBUTTONDOWN", true)
  if r ~= 1 then return false end
  reaper.JS_WindowMessage_Intercept(arrange, "WM_LBUTTONUP", true)
  _WM_HWND = arrange
  return true
end

local function wm_cleanup()
  if _guard_blocking and reaper.APIExists("SNM_SetIntConfigVar") then
    reaper.SNM_SetIntConfigVar("trackselonmouse", _guard_orig_pref)
    _guard_blocking = false
  end
  if _WM_HWND and reaper.APIExists("JS_WindowMessage_Release") then
    reaper.JS_WindowMessage_Release(_WM_HWND, "WM_LBUTTONDOWN")
    reaper.JS_WindowMessage_Release(_WM_HWND, "WM_LBUTTONUP")
  end
  _WM_HWND = nil
end

local function wm_new_down()
  if not _WM_HWND then return false end
  local ok, _, _, time = reaper.JS_WindowMessage_Peek(_WM_HWND, "WM_LBUTTONDOWN")
  if not (ok and time and time ~= 0) then return false end
  if time == _WM_DOWN_LAST then return false end
  _WM_DOWN_LAST = time
  return true
end

local function wm_new_up()
  if not _WM_HWND then return false end
  local ok, _, _, time = reaper.JS_WindowMessage_Peek(_WM_HWND, "WM_LBUTTONUP")
  if not (ok and time and time ~= 0) then return false end
  if time == _WM_UP_LAST then return false end
  _WM_UP_LAST = time
  return true
end

---------------------------------------
-- Toolbar auto-terminate + toggle support
---------------------------------------
if reaper.set_action_options then reaper.set_action_options(1|4) end
reaper.atexit(function()
  if reaper.set_action_options then reaper.set_action_options(8) end
  wm_cleanup()
end)

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

-- Hit test: returns the track to select, or nil
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

-- === CLICK-SELECT state (v0.13.0 – Gesture FSM) ===
local CLICK_STATE = "IDLE"   -- "IDLE","LMB_GESTURE","RMB_SESSION","MENU_COOLDOWN","FOCUS_COOLDOWN"

-- edges / gesture tracking
local CLICK_prev_lmb, CLICK_prev_rmb = false, false
local CLICK_down_x, CLICK_down_y, CLICK_down_t = nil, nil, -1

-- focus trackers
local CLICK_focus_was_main     = true
local CLICK_focus_return_time  = -1

-- Called every loop; returns true if a click → track selection was actually handled in this loop
local function Click_TickMaybeSelectTrack()
  if not ENABLE_CLICK_SELECT_TRACK then return false end
  if not reaper.APIExists("JS_Mouse_GetState") then return false end

  local now = reaper.time_precise()

  -- === Focus guard (matches the native app's click-to-activate suppression) ===
  if reaper.APIExists("JS_Window_GetFocus") and reaper.APIExists("JS_Window_IsChild") then
    local main = reaper.GetMainHwnd()
    local fh   = reaper.JS_Window_GetFocus()
    local focus_back = false
    if fh and main then
      local is_child = (reaper.JS_Window_IsChild(main, fh) == 1)
      focus_back = (fh == main) or is_child
    end
    if focus_back and not CLICK_focus_was_main then
      CLICK_focus_return_time = now
      CLICK_STATE = "FOCUS_COOLDOWN"
      Click_Log("guard: focus_return_latch")
    end
    CLICK_focus_was_main = focus_back
  end

  if CLICK_STATE == "FOCUS_COOLDOWN" then
    local dt = now - (CLICK_focus_return_time >= 0 and CLICK_focus_return_time or now)
    if dt < (CLICK_FOCUS_RETURN_GRACE_SEC or 0) then
      Click_Log(("guard: focus_return_grace dt=%.3f"):format(dt))
      return false
    else
      CLICK_STATE = "IDLE"
    end
  end

  -- Read the mouse state + edges
  local mstate = reaper.JS_Mouse_GetState(1 + 2)   -- LMB|RMB
  local x, y   = reaper.GetMousePosition()
  local lmb    = (mstate & 1) == 1
  local rmb    = (mstate & 2) == 2
  local l_down = ( lmb and not CLICK_prev_lmb)
  local l_up   = ((not lmb) and CLICK_prev_lmb)
  local r_down = ( rmb and not CLICK_prev_rmb)
  local r_up   = ((not rmb) and CLICK_prev_rmb)

  -- === Left-button gesture (one click = a complete down→up gesture) ===
  local did = false

  if CLICK_STATE == "IDLE" then
    if l_down then
      CLICK_down_x, CLICK_down_y, CLICK_down_t = x, y, now
      if not CLICK_SELECT_ON_MOUSE_UP then
        -- mouse-down mode: select the track immediately on a hit
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
      end
      CLICK_STATE = "LMB_GESTURE"
      CLICK_prev_lmb, CLICK_prev_rmb = lmb, rmb
      return did
    end

  elseif CLICK_STATE == "LMB_GESTURE" then
    -- any interference (right button) cancels the gesture
    if r_down then
      CLICK_STATE = "IDLE"
      CLICK_prev_lmb, CLICK_prev_rmb = lmb, rmb
      return false
    end

    if CLICK_SELECT_ON_MOUSE_UP and l_up then
      local dx = math.abs(x - (CLICK_down_x or x))
      local dy = math.abs(y - (CLICK_down_y or y))
      if dx <= (CLICK_TOLERANCE_PX or 0) and dy <= (CLICK_TOLERANCE_PX or 0) then
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
      CLICK_STATE = "IDLE"
      CLICK_prev_lmb, CLICK_prev_rmb = lmb, rmb
      return did
    end
  end

  CLICK_prev_lmb, CLICK_prev_rmb = lmb, rmb
  return did
end
----------------------------------------------




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
    return (s >= rs - EPS) and (e <= re_ + EPS)   -- contain (with EPS, edges included)
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

  -- Remember the last non-empty razor area (range + track GUIDs) for other scripts:
  -- REAPER clears razor areas on mouse-down over an item, before a click action runs
  -- (used by "Extend Razor Edit to Mouse Cursor like Pro Tools"). Not saved with the project.
  if Razor.cnt_tracks_with > 0 then
    local guids = {}
    for i=0, tcnt-1 do
      local g = track_guid(reaper.GetTrack(0,i))
      if Razor.t_has[g] then guids[#guids+1] = g end
    end
    local v = string.format("%.17f %.17f %s", Razor.union_s, Razor.union_e, table.concat(guids, ","))
    if v ~= Razor.last_remembered then
      Razor.last_remembered = v
      reaper.SetExtState("hsuanice_Link", "last_razor", v, false)
    end
  end
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

  if CLICK_HOOK_PHASE == "pre" then
    Click_TickMaybeSelectTrack()
  end

  -- Pro Tools guard — three-layer defence against wrong track-select.
  --
  -- Layer 1 (primary, normal-speed click): on mouse-DOWN disable 'trackselonmouse';
  --   restore on mouse-UP → REAPER's up-handler skips track select → zero flash.
  -- Layer 2 (fast-click fallback): if down+up both arrive before this defer frame
  --   (< ~33 ms click), pref-toggle missed its window → restore tracks manually
  --   and suppress D so items are not deselected this frame.
  -- Layer 3 (polling backup): every frame while LMB held on a selected item,
  --   restore tracks if wrong → catches HWND-staleness failures during drag.
  local _suppress_D = false
  if Razor.cnt_tracks_with == 0 then
    -- Re-validate WM intercept: arrange HWND can change on float/dock.
    if _WM_HWND then
      local _ok = reaper.JS_WindowMessage_Peek(_WM_HWND, "WM_LBUTTONDOWN")
      if not _ok then _WM_HWND = nil; _guard_blocking = false end
    end
    if not _WM_HWND then wm_setup() end

    local _is_down = wm_new_down()
    local _is_up   = wm_new_up()

    -- Fallback polling edges (WM intercept unavailable)
    if not _WM_HWND and reaper.APIExists("JS_Mouse_GetState") then
      local _lmb = (reaper.JS_Mouse_GetState(1) & 1) == 1
      if     _lmb and not _guard_prev_lmb then _is_down = true end
      if not _lmb and     _guard_prev_lmb then _is_up   = true end
      _guard_prev_lmb = _lmb
    end

    -- Safety: missed-up recovery
    if _guard_blocking and reaper.APIExists("JS_Mouse_GetState") then
      if (reaper.JS_Mouse_GetState(1) & 1) == 0 then _is_up = true end
    end

    -- Shared helper: restore track selection to match current item selection
    local function _restore_tracks()
      local _want = {}
      for _i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local _it = reaper.GetSelectedMediaItem(0, _i)
        local _tr = reaper.GetMediaItem_Track(_it)
        if _tr then _want[track_guid(_tr)] = true end
      end
      reaper.PreventUIRefresh(1)
      for _i = 0, reaper.CountTracks(0) - 1 do
        local _tr = reaper.GetTrack(0, _i)
        set_track_selected(_tr, _want[track_guid(_tr)] or false)
      end
      reaper.PreventUIRefresh(-1)
      reaper.TrackList_AdjustWindows(false)
    end

    -- Layer 2: fast-click (down+up in same frame) → manual restore + suppress D
    if _is_down and _is_up then
      local _mx, _my = reaper.GetMousePosition()
      local _hit = reaper.GetItemFromPoint(_mx, _my, true)
      if _hit and (reaper.GetMediaItemInfo_Value(_hit, "B_UISEL") or 0) > 0.5 then
        _restore_tracks()
        _suppress_D = true
      end
    else
      -- Layer 1: normal-speed click — disable pref on down, restore on up
      if _is_down then
        local _mx, _my = reaper.GetMousePosition()
        local _hit = reaper.GetItemFromPoint(_mx, _my, true)
        if _hit and (reaper.GetMediaItemInfo_Value(_hit, "B_UISEL") or 0) > 0.5 then
          if reaper.APIExists("SNM_SetIntConfigVar") then
            _guard_orig_pref = reaper.SNM_GetIntConfigVar("trackselonmouse", 1)
            reaper.SNM_SetIntConfigVar("trackselonmouse", 0)
            _guard_blocking = true
          else
            _restore_tracks()   -- no SNM: manual fallback (may flash)
          end
        end
      end
      if _is_up and _guard_blocking then
        reaper.SNM_SetIntConfigVar("trackselonmouse", _guard_orig_pref)
        _guard_blocking = false
      end
    end

    -- Layer 3: polling backup — every frame while LMB held on selected item
    -- (catches HWND-stale failures; harmless when layer 1 is working)
    if not _guard_blocking
       and reaper.APIExists("JS_Mouse_GetState")
       and (reaper.JS_Mouse_GetState(1) & 1) == 1 then
      local _mx, _my = reaper.GetMousePosition()
      local _hit = reaper.GetItemFromPoint(_mx, _my, true)
      if _hit and (reaper.GetMediaItemInfo_Value(_hit, "B_UISEL") or 0) > 0.5 then
        _restore_tracks()
      end
    end
  end

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
  -- Guard: only fire when items ARE selected (it_info.count > 0).
  -- This prevents clicking empty arrange space (which clears items) from also clearing track selection.
  if ENABLE_B
     and (Razor.cnt_tracks_with == 0)
     and items_changed_this_tick
     and it_info.count > 0
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
     and ENABLE_TRACKS_TO_RAZOR
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
     and ((Razor.sig ~= prev.razor_sig) or (ENABLE_TRACKS_TO_ITEMS and tr_sel_sig ~= prev.tr_sel_sig))
     and (not tracks_changed_by_items)
     and triggered_side ~= "ITEMS"
     and not _suppress_D
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

  if CLICK_HOOK_PHASE == "post" then
    Click_TickMaybeSelectTrack()
  end

  reaper.defer(mainloop)
end

wm_setup()
mainloop()
