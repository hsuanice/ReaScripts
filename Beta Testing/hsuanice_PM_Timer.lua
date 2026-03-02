--[[
@description PM Timer - Scene-aware Work Timer
@version 260302.1820
@author hsuanice
@about
  Scene-aware toggle timer for the hsuanice PM system.
  Uses gfx (no ReaImGui). 1-second display refresh via defer + time_precise.

  State machine: IDLE ↔ WORKING  (no BREAK state)

  Track structure (auto-managed):
    Scene Cut         ← folder track (I_FOLDERDEPTH = 1)
      2026-03-01      ← date track, direct child, depth = 0
      2026-03-02      ← depth = 0
      DurationOnly_Log← last child, depth = -1; holds duration-only records

  Work item name: "scene_name (start_tc) | work_type"
  Work item metadata: P_EXT:SCENE_GUID, P_EXT:WORK_TYPE, P_EXT:END_REASON
  Duration-only items also carry P_EXT:IS_DURATION_ONLY = "1"
  All work items are locked (C_LOCK=1) after creation.

@changelog
  v260302.1820
    - Right-click anywhere in the window shows "Dock window" / "Undock window" menu.
      Uses gfx.dock(1) to dock, gfx.dock(0) to undock; no OS title bar required.

  v260302.1815
    - Fix: dock state now tracked every frame via cur_dock = gfx.dock(-1) into a
      module-level variable. Previously gfx.dock(-1) was only called at char==-1
      (window already detached), so it always returned 0 and the docked state was
      never saved correctly.

  v260302.1810
    - Fix: item locking used wrong key "D_LOCK"; correct REAPER API key is "C_LOCK"
      (char flag, &1=locked). All lock/unlock calls updated.

  v260302.1805
    - Fix: buttons unclickable after Start — BTN was built with index gaps (BTN[1]=nil
      in WORKING mode), causing ipairs to stop immediately. Changed to table.insert
      so BTN is always a dense array regardless of which buttons are active.

  v260302.1800
    - GUI: horizontal control panel (WIN_W=560, WIN_H=140)
      Single info row: Scene | Type | Status | Elapsed, all on one line
      Buttons: [Start] [Finish] [Break] [Add Record] in a single horizontal row
      Inactive buttons rendered as grayed-out (non-clickable)
    - Dock support: DOCK_STATE persisted via GetExtState/SetExtState
    - Auto Lock: C_LOCK=1 set on all work items after creation
      C_LOCK=0 before modifying D_LENGTH in finish_work_session, C_LOCK=1 after
      Scene items and other project items are NOT locked

  v260302.1755
    - Fix: window position now tracked each frame via gfx.clienttoscreen(0,0)
      (previously saved gfx.x/gfx.y which are drawing cursor coords, not window pos)
      win_x/win_y cached in module vars; written to persistent ExtState on close

  v260302.1750
    - Add Record: Duration split into two fields — Dur Hours and Dur Mins
      Both accept any non-negative integer (no 59 limit); total = h*3600 + m*60
      e.g. Dur Mins=120 → 2 hours; Dur Hours=8 → 8 hours

  v260302.1745
    - Add Record: Date field changed from YYYY-MM-DD to 6-digit YYMMDD (e.g. 260302)
      parse_YYMMDD() converts to full YYYY-MM-DD string internally

  v260302.1740
    - Add Record: Work Type now uses gfx.showmenu (same as Start); no free-text
      typos possible. GetUserInputs reduced to 4 fields (Date/Start/End/Duration).

  v260302.1730
    - Add Record: added Date (YYYY-MM-DD) field; defaults to today
      Timed mode uses the provided date for date track lookup/creation
      Validation: must match YYYY-MM-DD pattern or error before any changes
    - Window position memory: gfx.init reads WIN_X/WIN_Y from GetExtState on
      startup and reopen; SetExtState(persistent=true) saves on close

  v260302.1700
    - New: Add Record button — manual backfill without running the timer
      Timed mode       : Start+End as HHMM → item placed on today's date track
      Duration-only    : Duration as HHMM  → item placed on DurationOnly_Log track
    - New: parse_HHMM()  — strict 4-digit HHMM parser with clear error messages
    - New: get_or_create_duration_log_track() — creates DurationOnly_Log as the
      last child of Scene Cut if absent
    - Updated: get_or_create_date_track() — aware of DurationOnly_Log; new date
      tracks use depth=0 when DurationOnly_Log is the current last child
    - Updated: sync_work_item_names() — now also renames items on DurationOnly_Log
    - UI: WIN_W 300→420, WIN_H 225→320; 2-column button layout
    - Scene name display: truncation limit raised from 22 to 34 chars
    - Duration-only items tagged P_EXT:IS_DURATION_ONLY = "1"

  v260302.1620
    - New: sync_work_item_names() — rebuilds take names for all work items under
      Scene Cut date tracks on startup and after each Finish/Break.
      Name format: "scene_name (start_tc) | work_type"
      Missing scene fallback: "[Missing Scene] | work_type"
    - start_tc uses format_timestr_pos(pos, "", 5) (HH:MM:SS:FF project TC)
    - Only writes undo block when at least one name actually changed

  v260302.1600
    - Full architecture reset: Scene Cut becomes the folder; date tracks are
      its direct children; no per-scene tracks, no placeholder tracks
    - Item metadata: SCENE_GUID / WORK_TYPE / END_REASON
    - Date tracks identified by YYYY-MM-DD name pattern (no P_EXT tags)
    - Folder closing handled via last date track depth = -1

  v260302.1540
    - Removed BREAK state; UI high-contrast; Arial 18/22
]]--

---@diagnostic disable: undefined-global
local r = reaper

-- ── Constants ──────────────────────────────────────────────────────────────
local NS                = "hsuanice_PM"
local SCENE_TRACK_NAME  = "Scene Cut"
local DURATION_LOG_NAME = "DurationOnly_Log"
local WIN_W, WIN_H      = 560, 140
local WORK_TYPES        = { "editing", "denoise", "conform", "aap", "double_check", "custom" }
local DATE_PAT          = "^%d%d%d%d%-%d%d%-%d%d$"  -- matches YYYY-MM-DD

-- ── State ──────────────────────────────────────────────────────────────────
local S = {
  mode            = "IDLE",   -- "IDLE" | "WORKING"
  scene_guid      = "",
  scene_name      = "",
  work_type       = "",
  work_item_guid  = "",
  start_clock     = 0,        -- os.time() at session start (for display)
  last_start_time = 0,        -- time_precise() adjusted to session start (elapsed)
}

-- ── Refresh + mouse state ──────────────────────────────────────────────────
local last_draw_time  = 0
local mouse_prev      = 0
local mouse_r_prev    = 0
local BTN             = {}
local running        = true
local win_x          = tonumber(r.GetExtState(NS, "WIN_X"))       or 100
local win_y          = tonumber(r.GetExtState(NS, "WIN_Y"))       or 100
local cur_dock       = tonumber(r.GetExtState(NS, "DOCK_STATE"))  or 0

-- ── Helpers ────────────────────────────────────────────────────────────────
local function elapsed_secs()
  if S.mode == "WORKING" then
    return math.max(0, r.time_precise() - S.last_start_time)
  end
  return 0
end

local function fmt_hms(secs)
  secs = math.max(0, math.floor(secs))
  return string.format("%02d:%02d:%02d",
    math.floor(secs / 3600),
    math.floor((secs % 3600) / 60),
    secs % 60)
end

local function secs_since_midnight()
  local t = os.date("*t")
  return t.hour * 3600 + t.min * 60 + t.sec
end

local function get_extstate(key)
  local ok, val = r.GetProjExtState(0, NS, key)
  if ok == 1 and val ~= "" then return val end
  return nil
end

local function set_extstate(key, val)
  r.SetProjExtState(0, NS, key, tostring(val))
end

local function clear_active_extstate()
  for _, k in ipairs({
    "ACTIVE_WORK_ITEM_GUID", "ACTIVE_WORK_SCENE_GUID", "ACTIVE_WORK_SCENE_NAME",
    "ACTIVE_WORK_TYPE", "ACTIVE_WORK_START_CLOCK", "ACTIVE_WORK_OSTIME_START",
  }) do
    r.SetProjExtState(0, NS, k, "")
  end
end

local function reset_state()
  S.mode = "IDLE"; S.scene_guid = ""; S.scene_name = ""
  S.work_type = ""; S.work_item_guid = ""
  S.start_clock = 0; S.last_start_time = 0
end

local function get_item_by_guid(guid)
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, j)
      local _, ig = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
      if ig == guid then return item end
    end
  end
  return nil
end

local function get_item_guid(item)
  local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid
end

local function set_item_ext(item, key, val)
  r.GetSetMediaItemInfo_String(item, "P_EXT:" .. key, tostring(val), true)
end

-- Parses a 4-digit HHMM string → seconds since midnight.
-- Returns (nil, errmsg) on failure, (nil) if input is empty.
local function parse_HHMM(input)
  if input == "" then return nil end
  if not input:match("^%d%d%d%d$") then
    return nil, "Time must be 4 digits (HHMM)"
  end
  local hh = tonumber(input:sub(1, 2))
  local mm = tonumber(input:sub(3, 4))
  if hh > 23 then return nil, "Hour must be 00-23" end
  if mm > 59 then return nil, "Minute must be 00-59" end
  return hh * 3600 + mm * 60
end

-- Parses a 6-digit YYMMDD string → "YYYY-MM-DD" date string.
-- Returns (nil, errmsg) on failure.
local function parse_YYMMDD(input)
  if not input:match("^%d%d%d%d%d%d$") then
    return nil, "Date must be 6 digits (YYMMDD)"
  end
  local mm = tonumber(input:sub(3, 4))
  local dd = tonumber(input:sub(5, 6))
  if mm < 1 or mm > 12 then return nil, "Month must be 01-12" end
  if dd < 1 or dd > 31 then return nil, "Day must be 01-31"   end
  return "20" .. input:sub(1, 2) .. "-" .. input:sub(3, 4) .. "-" .. input:sub(5, 6)
end

-- ── Track management ───────────────────────────────────────────────────────

-- Ensures Scene Cut is a folder track (I_FOLDERDEPTH = 1).
local function ensure_scene_cut_folder(scene_track)
  local fd = math.floor(r.GetMediaTrackInfo_Value(scene_track, "I_FOLDERDEPTH"))
  if fd ~= 1 then
    r.SetMediaTrackInfo_Value(scene_track, "I_FOLDERDEPTH", 1)
  end
end

-- Find or create a YYYY-MM-DD date track as a direct child of Scene Cut.
--
-- Maintained folder invariant:
--   YYYY-MM-DD  depth=0  (all date tracks)
--   ...
--   DurationOnly_Log  depth=-1  (last child, closes folder)
--   — if DurationOnly_Log absent, last date track carries depth=-1 instead
--
-- Adding a new date track:
--   DurationOnly_Log present → insert before it with depth=0
--   DurationOnly_Log absent  → promote current last date to 0, append with -1
local function get_or_create_date_track(scene_track, date_str)
  local sc_num  = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local sc_0idx = sc_num - 1
  local total   = r.CountTracks(0)
  local depth   = 1
  local last_date_idx    = -1
  local duration_log_idx = -1

  for i = sc_num, total - 1 do
    local t       = r.GetTrack(0, i)
    local fd      = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)

    if tname:match(DATE_PAT) then
      if tname == date_str then return t end  -- found; done
      last_date_idx = i
    elseif tname == DURATION_LOG_NAME then
      duration_log_idx = i
    end

    depth = depth + fd
    if depth <= 0 then break end
  end

  if duration_log_idx >= 0 then
    -- DurationOnly_Log is the last child (depth=-1).
    -- Insert new date track just before it with depth=0; DurationOnly_Log
    -- shifts one position but retains depth=-1, keeping the folder closed.
    r.InsertTrackAtIndex(duration_log_idx, true)
    local dt = r.GetTrack(0, duration_log_idx)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", date_str, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", 0)
    return dt

  elseif last_date_idx < 0 then
    -- No children at all: insert as sole child with depth=-1.
    r.InsertTrackAtIndex(sc_0idx + 1, true)
    local dt = r.GetTrack(0, sc_0idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", date_str, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt

  else
    -- Date tracks exist, no DurationOnly_Log.
    -- Promote current last date track from -1 to 0, append new with depth=-1.
    r.SetMediaTrackInfo_Value(r.GetTrack(0, last_date_idx), "I_FOLDERDEPTH", 0)
    r.InsertTrackAtIndex(last_date_idx + 1, true)
    local dt = r.GetTrack(0, last_date_idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", date_str, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt
  end
end

-- Find or create DurationOnly_Log as the last child of Scene Cut.
local function get_or_create_duration_log_track(scene_track)
  local sc_num  = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local sc_0idx = sc_num - 1
  local total   = r.CountTracks(0)
  local depth   = 1
  local last_child_idx = -1

  for i = sc_num, total - 1 do
    local t       = r.GetTrack(0, i)
    local fd      = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)

    if tname == DURATION_LOG_NAME then return t end  -- found; done

    last_child_idx = i
    depth = depth + fd
    if depth <= 0 then break end
  end

  -- Not found: append as last child with depth=-1.
  if last_child_idx < 0 then
    -- Folder is empty.
    r.InsertTrackAtIndex(sc_0idx + 1, true)
    local dt = r.GetTrack(0, sc_0idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", DURATION_LOG_NAME, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt
  else
    -- Promote current last child to depth=0, append DurationOnly_Log with depth=-1.
    r.SetMediaTrackInfo_Value(r.GetTrack(0, last_child_idx), "I_FOLDERDEPTH", 0)
    r.InsertTrackAtIndex(last_child_idx + 1, true)
    local dt = r.GetTrack(0, last_child_idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", DURATION_LOG_NAME, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt
  end
end

-- ── Work item ──────────────────────────────────────────────────────────────
local function create_work_item(date_track, scene_guid, scene_name, work_type, pos_secs)
  -- Place after the last existing item on this date track.
  local pos = pos_secs
  local n   = r.CountTrackMediaItems(date_track)
  if n > 0 then
    local last = r.GetTrackMediaItem(date_track, n - 1)
    local last_end = r.GetMediaItemInfo_Value(last, "D_POSITION")
                   + math.max(r.GetMediaItemInfo_Value(last, "D_LENGTH"), 1)
    if last_end > pos then pos = last_end end
  end

  local item = r.AddMediaItemToTrack(date_track)
  r.SetMediaItemInfo_Value(item, "D_POSITION", pos)
  r.SetMediaItemInfo_Value(item, "D_LENGTH",   1)  -- updated on Finish/Break

  -- Temporary name; sync_work_item_names() rewrites to full "scene (tc) | type" format.
  local take = r.AddTakeToMediaItem(item)
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", scene_name .. " | " .. work_type, true)

  set_item_ext(item, "SCENE_GUID",  scene_guid)
  set_item_ext(item, "WORK_TYPE",   work_type)
  set_item_ext(item, "START_CLOCK", tostring(os.time()))

  r.UpdateItemInProject(item)
  r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
  return item
end

-- ── Actions ────────────────────────────────────────────────────────────────
local function action_start()
  -- 1. Find Scene Cut track
  local scene_track = nil
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname == SCENE_TRACK_NAME then scene_track = t; break end
  end
  if not scene_track then
    r.ShowMessageBox("Track '" .. SCENE_TRACK_NAME .. "' not found.", "PM Timer", 0)
    return
  end

  -- 2. Require a selected item on Scene Cut
  local sel_scene = nil
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if r.GetMediaItemTrack(item) == scene_track then sel_scene = item; break end
  end
  if not sel_scene then
    r.ShowMessageBox(
      "Please select a scene item on '" .. SCENE_TRACK_NAME .. "' first.",
      "PM Timer", 0)
    return
  end

  local scene_guid = r.BR_GetMediaItemGUID(sel_scene)
  local scene_name = ""
  local take = r.GetActiveTake(sel_scene)
  if take then scene_name = r.GetTakeName(take) end
  if scene_name == "" then
    local _, notes = r.GetSetMediaItemInfo_String(sel_scene, "P_NOTES", "", false)
    scene_name = (notes and notes ~= "") and notes or "(unnamed)"
  end

  -- 3. Choose work type
  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(WORK_TYPES, "|"))
  if choice == 0 then return end

  local work_type = WORK_TYPES[choice]
  if work_type == "custom" then
    local ok, val = r.GetUserInputs("Custom Work Type", 1, "Work type:", "")
    if not ok or val == "" then return end
    work_type = val
  end

  -- 4. Build track structure and create item
  local pos_secs    = secs_since_midnight()
  local now_clock   = os.time()
  local now_precise = r.time_precise()

  r.Undo_BeginBlock()
  ensure_scene_cut_folder(scene_track)
  local date_track = get_or_create_date_track(scene_track, os.date("%Y-%m-%d"))
  local item       = create_work_item(date_track, scene_guid, scene_name, work_type, pos_secs)
  local item_guid  = get_item_guid(item)
  r.Undo_EndBlock("PM: Start work session", -1)
  r.UpdateArrange()

  -- 5. Update state + ExtState
  S.mode            = "WORKING"
  S.scene_guid      = scene_guid
  S.scene_name      = scene_name
  S.work_type       = work_type
  S.work_item_guid  = item_guid
  S.start_clock     = now_clock
  S.last_start_time = now_precise

  set_extstate("ACTIVE_WORK_ITEM_GUID",    item_guid)
  set_extstate("ACTIVE_WORK_SCENE_GUID",   scene_guid)
  set_extstate("ACTIVE_WORK_SCENE_NAME",   scene_name)
  set_extstate("ACTIVE_WORK_TYPE",         work_type)
  set_extstate("ACTIVE_WORK_START_CLOCK",  tostring(now_clock))
  set_extstate("ACTIVE_WORK_OSTIME_START", tostring(now_clock))
end

local function finish_work_session(end_reason)
  local duration = r.time_precise() - S.last_start_time

  local item = get_item_by_guid(S.work_item_guid)
  if item then
    r.Undo_BeginBlock()
    r.SetMediaItemInfo_Value(item, "C_LOCK",   0)  -- unlock before modifying length
    r.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(duration, 1))
    set_item_ext(item, "END_REASON", end_reason)
    set_item_ext(item, "END_CLOCK",  tostring(os.time()))
    set_item_ext(item, "DURATION",   tostring(duration))
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- relock after modifying
    r.Undo_EndBlock("PM: " .. end_reason .. " work session", -1)
    r.UpdateArrange()
  end

  clear_active_extstate()
  reset_state()
end

-- ── Sync work item names ────────────────────────────────────────────────────
-- Rebuilds take names for all work items on YYYY-MM-DD and DurationOnly_Log
-- tracks inside the Scene Cut folder.
-- Name format: "scene_name (start_tc) | work_type"
-- Missing-scene fallback: "[Missing Scene] | work_type"
local function sync_work_item_names()
  -- Step A: build scene_map {guid → {name, start_tc}} from Scene Cut items
  local scene_track = nil
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname == SCENE_TRACK_NAME then scene_track = t; break end
  end
  if not scene_track then return end

  local scene_map = {}
  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local item     = r.GetTrackMediaItem(scene_track, i)
    local guid     = r.BR_GetMediaItemGUID(item)
    local spos     = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local start_tc = r.format_timestr_pos(spos, "", 5)
    local name     = ""
    local take     = r.GetActiveTake(item)
    if take then name = r.GetTakeName(take) end
    if name == "" then
      local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      name = (notes and notes ~= "") and notes or "(unnamed)"
    end
    scene_map[guid] = { name = name, start_tc = start_tc }
  end

  -- Step B+C: walk date tracks AND DurationOnly_Log inside Scene Cut folder
  local sc_num  = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local total   = r.CountTracks(0)
  local depth   = 1
  local changed = 0

  for i = sc_num, total - 1 do
    local t       = r.GetTrack(0, i)
    local fd      = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)

    if tname:match(DATE_PAT) or tname == DURATION_LOG_NAME then
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        local item = r.GetTrackMediaItem(t, j)
        local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
        local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE",  "", false)
        if sg ~= "" then
          local work_type = (wt ~= "") and wt or ""
          local new_name
          local sc = scene_map[sg]
          if sc then
            new_name = sc.name .. " (" .. sc.start_tc .. ") | " .. work_type
          else
            new_name = "[Missing Scene] | " .. work_type
          end
          local item_take = r.GetActiveTake(item)
          if not item_take then item_take = r.AddTakeToMediaItem(item) end
          if r.GetTakeName(item_take) ~= new_name then
            if changed == 0 then r.Undo_BeginBlock() end
            r.GetSetMediaItemTakeInfo_String(item_take, "P_NAME", new_name, true)
            r.UpdateItemInProject(item)
            changed = changed + 1
          end
        end
      end
    end

    depth = depth + fd
    if depth <= 0 then break end
  end

  if changed > 0 then
    r.Undo_EndBlock("PM: Sync work item names", -1)
    r.UpdateArrange()
  end
end

local function action_finish() finish_work_session("finish"); sync_work_item_names() end
local function action_break()  finish_work_session("break");  sync_work_item_names() end

local function action_stop()
  local item = get_item_by_guid(S.work_item_guid)
  if item then
    r.Undo_BeginBlock()
    set_item_ext(item, "END_REASON", "aborted")
    r.UpdateItemInProject(item)
    r.Undo_EndBlock("PM: Abort work session", -1)
    r.UpdateArrange()
  end
  clear_active_extstate()
  reset_state()
end

-- ── Add Record ─────────────────────────────────────────────────────────────
-- Timed mode        : Start + End as HHMM → item on today's date track
-- Duration-only mode: Duration as HHMM    → item on DurationOnly_Log track
local function action_add_record()
  -- Guard: cannot backfill while a session is running
  if S.mode == "WORKING" then
    r.ShowMessageBox("Finish current session first.", "Add Record", 0)
    return
  end

  -- Find Scene Cut
  local scene_track = nil
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname == SCENE_TRACK_NAME then scene_track = t; break end
  end
  if not scene_track then
    r.ShowMessageBox("Track '" .. SCENE_TRACK_NAME .. "' not found.", "Add Record", 0)
    return
  end

  -- Require a selected scene item on Scene Cut
  local sel_scene = nil
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if r.GetMediaItemTrack(item) == scene_track then sel_scene = item; break end
  end
  if not sel_scene then
    r.ShowMessageBox(
      "Please select a scene item on '" .. SCENE_TRACK_NAME .. "' first.",
      "Add Record", 0)
    return
  end

  local scene_guid     = r.BR_GetMediaItemGUID(sel_scene)
  local scene_name     = ""
  local s_take         = r.GetActiveTake(sel_scene)
  if s_take then scene_name = r.GetTakeName(s_take) end
  if scene_name == "" then
    local _, notes = r.GetSetMediaItemInfo_String(sel_scene, "P_NOTES", "", false)
    scene_name = (notes and notes ~= "") and notes or "(unnamed)"
  end
  local scene_start_tc = r.format_timestr_pos(
    r.GetMediaItemInfo_Value(sel_scene, "D_POSITION"), "", 5)

  -- Work type via menu (same as Start)
  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(WORK_TYPES, "|"))
  if choice == 0 then return end
  local work_type = WORK_TYPES[choice]
  if work_type == "custom" then
    local ok2, val = r.GetUserInputs("Custom Work Type", 1, "Work type:", "")
    if not ok2 or val == "" then return end
    work_type = val
  end

  -- Input dialog (5 fields: date + times + duration)
  local ok, raw = r.GetUserInputs("Add Record", 5,
    "Date (YYMMDD):,Start (HHMM):,End   (HHMM):,Dur Hours:,Dur Mins:",
    os.date("%y%m%d") .. ",,,,")
  if not ok then return end

  -- Parse comma-separated fields
  local fields = {}
  local n = 0
  for f in (raw .. ","):gmatch("([^,]*),") do
    n = n + 1; fields[n] = f:match("^%s*(.-)%s*$")
  end
  local date_input = fields[1] or ""
  local start_str  = fields[2] or ""
  local end_str    = fields[3] or ""
  local hours_str  = fields[4] or ""
  local mins_str   = fields[5] or ""

  local date_str, date_err = parse_YYMMDD(date_input)
  if not date_str then
    r.ShowMessageBox("Date: " .. (date_err or "invalid"), "Add Record", 0); return
  end

  local has_time = start_str ~= "" or end_str ~= ""
  local has_dur  = hours_str ~= "" or mins_str ~= ""

  local is_timed    = start_str ~= "" and end_str ~= "" and not has_dur
  local is_duration = has_dur and not has_time

  if not is_timed and not is_duration then
    r.ShowMessageBox(
      "Invalid input.\n\n"
      .. "Timed mode       : fill Start + End, leave Dur Hours/Mins empty.\n"
      .. "Duration-only mode: fill Dur Hours and/or Mins, leave Start + End empty.",
      "Add Record", 0)
    return
  end

  -- Validate times before touching the project
  local s_secs, e_secs, d_secs
  if is_timed then
    local s_err, e_err
    s_secs, s_err = parse_HHMM(start_str)
    if not s_secs then
      r.ShowMessageBox("Start: " .. (s_err or "invalid"), "Add Record", 0); return
    end
    e_secs, e_err = parse_HHMM(end_str)
    if not e_secs then
      r.ShowMessageBox("End: "   .. (e_err or "invalid"), "Add Record", 0); return
    end
    if e_secs - s_secs <= 0 then
      r.ShowMessageBox("End time must be after Start time.", "Add Record", 0); return
    end
  else
    local h = math.floor(tonumber(hours_str) or 0)
    local m = math.floor(tonumber(mins_str)  or 0)
    if h < 0 or m < 0 then
      r.ShowMessageBox("Hours and Minutes must be non-negative.", "Add Record", 0); return
    end
    d_secs = h * 3600 + m * 60
    if d_secs <= 0 then
      r.ShowMessageBox("Duration must be greater than 0.", "Add Record", 0); return
    end
  end

  -- All valid — create item
  local item_name = scene_name .. " (" .. scene_start_tc .. ") | " .. work_type

  r.Undo_BeginBlock()
  ensure_scene_cut_folder(scene_track)

  if is_timed then
    local length     = e_secs - s_secs
    local date_track = get_or_create_date_track(scene_track, date_str)
    local item       = r.AddMediaItemToTrack(date_track)
    r.SetMediaItemInfo_Value(item, "D_POSITION", s_secs)
    r.SetMediaItemInfo_Value(item, "D_LENGTH",   length)
    local it = r.AddTakeToMediaItem(item)
    r.GetSetMediaItemTakeInfo_String(it, "P_NAME", item_name, true)
    set_item_ext(item, "SCENE_GUID",  scene_guid)
    set_item_ext(item, "WORK_TYPE",   work_type)
    set_item_ext(item, "DURATION",    tostring(length))
    set_item_ext(item, "END_REASON",  "manual")
    set_item_ext(item, "START_CLOCK", start_str)
    set_item_ext(item, "END_CLOCK",   end_str)
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
    r.Undo_EndBlock("PM: Add Record (timed)", -1)

  else  -- duration-only
    local dur_track = get_or_create_duration_log_track(scene_track)
    local item      = r.AddMediaItemToTrack(dur_track)
    r.SetMediaItemInfo_Value(item, "D_POSITION", 0)
    r.SetMediaItemInfo_Value(item, "D_LENGTH",   d_secs)
    local it = r.AddTakeToMediaItem(item)
    r.GetSetMediaItemTakeInfo_String(it, "P_NAME", item_name, true)
    set_item_ext(item, "SCENE_GUID",       scene_guid)
    set_item_ext(item, "WORK_TYPE",        work_type)
    set_item_ext(item, "DURATION",         tostring(d_secs))
    set_item_ext(item, "END_REASON",       "manual")
    set_item_ext(item, "IS_DURATION_ONLY", "1")
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
    r.Undo_EndBlock("PM: Add Record (duration-only)", -1)
  end

  r.UpdateArrange()
  sync_work_item_names()
end

-- ── Draw ───────────────────────────────────────────────────────────────────
local function setup_fonts()
  gfx.setfont(1, "Arial", 18)
  gfx.setfont(2, "Arial", 22)
  gfx.setfont(3, "Arial", 15)  -- compact info row
end

local function sep(y)
  gfx.set(0.35, 0.35, 0.35, 1)
  gfx.line(0, y, WIN_W, y)
end

local function draw_btn(x, y, w, h, label)
  gfx.set(0.28, 0.28, 0.32, 1); gfx.rect(x, y, w, h, 1)
  gfx.set(0.60, 0.60, 0.65, 1); gfx.rect(x, y, w, h, 0)
  gfx.set(1, 1, 1, 1)
  local tw, th = gfx.measurestr(label)
  gfx.x = x + math.floor((w - tw) / 2)
  gfx.y = y + math.floor((h - th) / 2)
  gfx.drawstr(label)
  return { x = x, y = y, w = w, h = h }
end

local function draw_btn_disabled(x, y, w, h, label)
  gfx.set(0.18, 0.18, 0.20, 1); gfx.rect(x, y, w, h, 1)
  gfx.set(0.35, 0.35, 0.38, 1); gfx.rect(x, y, w, h, 0)
  gfx.set(0.45, 0.45, 0.45, 1)
  local tw, th = gfx.measurestr(label)
  gfx.x = x + math.floor((w - tw) / 2)
  gfx.y = y + math.floor((h - th) / 2)
  gfx.drawstr(label)
end

local function draw()
  gfx.setfont(1)
  gfx.set(0.15, 0.15, 0.15, 1)
  gfx.rect(0, 0, WIN_W, WIN_H, 1)
  BTN = {}

  -- ── Info row ────────────────────────────────────────────────────────────
  local name_disp = S.scene_name
  if #name_disp > 14 then name_disp = name_disp:sub(1, 13) .. "\xe2\x80\xa6" end
  local type_disp = (S.work_type ~= "") and S.work_type or "\xe2\x80\x94"
  if #type_disp > 12 then type_disp = type_disp:sub(1, 11) .. "\xe2\x80\xa6" end

  gfx.setfont(3)
  gfx.x, gfx.y = 10, 12

  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("Scene: ")
  gfx.set(1,   1,   1,   1); gfx.drawstr(name_disp ~= "" and name_disp or "\xe2\x80\x94")
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Type: ")
  gfx.set(1,   1,   1,   1); gfx.drawstr(type_disp)
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Status: ")
  if S.mode == "WORKING" then
    gfx.set(0.2, 1.0, 0.2, 1); gfx.drawstr("WORKING")
  else
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("IDLE")
  end
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Elapsed: ")
  gfx.set(0.2, 0.8, 1.0, 1); gfx.drawstr(fmt_hms(elapsed_secs()))

  sep(44)

  -- ── Horizontal buttons ──────────────────────────────────────────────────
  -- 4 buttons filling WIN_W with small equal margins:
  --   gap=8, left=10, btn_w=129
  --   x positions: 10, 147, 284, 421  (last right edge: 421+129=550, right margin: 10)
  local btn_w  = 129
  local btn_h  = 40
  local btn_y  = 58
  local btn_gap = 8
  local btn_x0  = 10

  local working = (S.mode == "WORKING")
  local idle    = (S.mode == "IDLE")

  gfx.setfont(1)
  local function btn_x(i) return btn_x0 + (i - 1) * (btn_w + btn_gap) end

  -- Use table.insert so BTN is always a dense array (ipairs stops at first nil gap).
  local function add_btn(i, label, action)
    table.insert(BTN, { rect = draw_btn(btn_x(i), btn_y, btn_w, btn_h, label), action = action })
  end

  if idle    then add_btn(1, "Start",      action_start)
  else            draw_btn_disabled(btn_x(1), btn_y, btn_w, btn_h, "Start")      end

  if working then add_btn(2, "Finish",     action_finish)
  else            draw_btn_disabled(btn_x(2), btn_y, btn_w, btn_h, "Finish")     end

  if working then add_btn(3, "Break",      action_break)
  else            draw_btn_disabled(btn_x(3), btn_y, btn_w, btn_h, "Break")      end

  if idle    then add_btn(4, "Add Record", action_add_record)
  else            draw_btn_disabled(btn_x(4), btn_y, btn_w, btn_h, "Add Record") end

  gfx.update()
end

-- ── Mouse ──────────────────────────────────────────────────────────────────
local function handle_mouse()
  -- Left click: button actions
  local mb = gfx.mouse_cap & 1
  if mb == 1 and mouse_prev == 0 then
    local mx, my = gfx.mouse_x, gfx.mouse_y
    for _, b in ipairs(BTN) do
      local rc = b.rect
      if mx >= rc.x and mx <= rc.x + rc.w
      and my >= rc.y and my <= rc.y + rc.h then
        b.action()
        draw()
        break
      end
    end
  end
  mouse_prev = mb

  -- Right click: Dock / Undock
  local rb = (gfx.mouse_cap & 2) ~= 0 and 1 or 0
  if rb == 1 and mouse_r_prev == 0 then
    local is_docked = cur_dock ~= 0
    local choice = gfx.showmenu(is_docked and "Undock window" or "Dock window")
    if choice == 1 then
      gfx.dock(is_docked and 0 or 1)
    end
  end
  mouse_r_prev = rb
end

-- ── Close ──────────────────────────────────────────────────────────────────
local function handle_close()
  if S.mode == "IDLE" then return false end

  local ret = r.ShowMessageBox(
    "Timer is still running.\n\n"
    .. "Yes    = Finish  (save work log)\n"
    .. "No     = Stop    (mark aborted, keep item)\n"
    .. "Cancel = Return  (reopen timer)",
    "Close PM Timer", 3)

  if ret == 6 then
    action_finish(); return false
  elseif ret == 7 then
    action_stop(); return false
  else
    return true
  end
end

-- ── Recovery ───────────────────────────────────────────────────────────────
local function try_recover()
  local guid = get_extstate("ACTIVE_WORK_ITEM_GUID")
  if not guid then return end

  if not get_item_by_guid(guid) then
    clear_active_extstate(); return
  end

  S.mode           = "WORKING"
  S.work_item_guid = guid
  S.scene_guid     = get_extstate("ACTIVE_WORK_SCENE_GUID") or ""
  S.scene_name     = get_extstate("ACTIVE_WORK_SCENE_NAME") or ""
  S.work_type      = get_extstate("ACTIVE_WORK_TYPE")       or ""
  S.start_clock    = tonumber(get_extstate("ACTIVE_WORK_START_CLOCK"))  or os.time()

  local ostime_start = tonumber(get_extstate("ACTIVE_WORK_OSTIME_START"))
  if ostime_start then
    S.last_start_time = r.time_precise() - (os.time() - ostime_start)
  else
    S.last_start_time = r.time_precise()
  end
end

-- ── Main loop ──────────────────────────────────────────────────────────────
local function loop()
  if not running then return end

  local char = gfx.getchar()

  if char == -1 then
    local stay = handle_close()
    if stay then
      gfx.init("hsuanice PM Timer", WIN_W, WIN_H, cur_dock, win_x, win_y)
      setup_fonts()
      draw()
      last_draw_time = r.time_precise()
    else
      r.SetExtState(NS, "WIN_X",      tostring(win_x),   true)
      r.SetExtState(NS, "WIN_Y",      tostring(win_y),   true)
      r.SetExtState(NS, "DOCK_STATE", tostring(cur_dock), true)
      running = false
      return
    end
  end

  handle_mouse()

  -- Track window position and dock state each frame so they survive close/reopen.
  local cx, cy = gfx.clienttoscreen(0, 0)
  if cx ~= 0 or cy ~= 0 then win_x, win_y = cx, cy end
  cur_dock = gfx.dock(-1)

  local now = r.time_precise()
  if now - last_draw_time >= 1.0 then
    draw()
    last_draw_time = now
  end

  r.defer(loop)
end

-- ── Entry ──────────────────────────────────────────────────────────────────
try_recover()
gfx.init("hsuanice PM Timer", WIN_W, WIN_H, cur_dock, win_x, win_y)
setup_fonts()
draw()
sync_work_item_names()
last_draw_time = r.time_precise()
r.defer(loop)
