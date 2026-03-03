--[[
@description PM Timer - Scene-aware Work Timer
@version 260303.1505
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

  Two work modes (auto-detected from selection):
    Scene Mode   : a scene item on "Scene Cut" is selected
                   P_EXT:SCENE_GUID written; name = "scene (tc) | work_type"
    Project Mode : no scene item selected
                   P_EXT:SCENE_GUID not written; name = work_type only

  Work item metadata: P_EXT:SCENE_GUID (Scene Mode only), P_EXT:WORK_TYPE,
                      P_EXT:END_REASON
  Duration-only items also carry P_EXT:IS_DURATION_ONLY = "1"
  All work items are locked (C_LOCK=1) after creation.

@changelog
  v260303.1505
    - Fix color mapping for aap/conform work types

  v260302.1830
    - Scene vs Project mode auto-detection (no more forced scene selection):
        Scene Mode  : scene item selected on Scene Cut → SCENE_GUID written,
                      name = "scene (tc) | work_type"
        Project Mode: no scene selected → SCENE_GUID omitted, name = work_type
    - Applies to action_start(), action_add_record() (timed + duration-only)
    - create_work_item() signature: scene_name replaced by pre-computed item_name;
      SCENE_GUID only written when scene_guid ~= ""
    - sync_work_item_names() unchanged; naturally skips Project Mode items
      (no SCENE_GUID → sync condition `sg ~= ""` is false)

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

  v260302.1750
    - Add Record: Duration split into two fields — Dur Hours and Dur Mins

  v260302.1745
    - Add Record: Date field changed from YYYY-MM-DD to 6-digit YYMMDD

  v260302.1740
    - Add Record: Work Type now uses gfx.showmenu

  v260302.1730
    - Add Record: added Date field; window position memory

  v260302.1700
    - New: Add Record button with Timed and Duration-only modes

  v260302.1620
    - New: sync_work_item_names()

  v260302.1600
    - Full architecture reset: Scene Cut folder with date track children

  v260302.1540
    - Removed BREAK state; UI high-contrast; Arial 18/22
]]--

---@diagnostic disable: undefined-global
local r = reaper

----------------------------------------------------------------
-- Work Type Color Map (Editable)
----------------------------------------------------------------

local WORK_COLORS = {
  editing  = {255, 255, 0},      -- Yellow
  denoise  = {255, 0, 255},      -- Magenta
  aap      = {0, 0, 255},      -- blue
  conform  = {0, 255, 0}         -- Green
}

-- ── Constants ──────────────────────────────────────────────────────────────
local NS                = "hsuanice_PM"
local SCENE_TRACK_NAME  = "Scene Cut"
local WORK_LOG_NAME     = "Work Log"
local DURATION_LOG_NAME = "DurationOnly_Log"
local WIN_W, WIN_H      = 560, 140
local WORK_TYPES        = { "editing", "denoise", "conform", "aap", "double_check", "custom" }
local SWITCH_TYPES      = { "editing", "denoise", "custom" }
local MODE_TYPES        = { "Dialog", "AAP", "Conform" }
local DATE_PAT          = "^%d%d%d%d%-%d%d%-%d%d$"  -- matches YYYY-MM-DD

-- ── State ──────────────────────────────────────────────────────────────────
local S = {
  mode            = "IDLE",   -- "IDLE" | "WORKING"
  scene_guid      = "",
  scene_name      = "",
  scene_start_tc  = "",
  work_mode       = "Dialog",
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
local running         = true
local win_x           = tonumber(r.GetExtState(NS, "WIN_X"))       or 100
local win_y           = tonumber(r.GetExtState(NS, "WIN_Y"))       or 100
local cur_dock        = tonumber(r.GetExtState(NS, "DOCK_STATE"))  or 0
local last_dock       = cur_dock

-- ── Helpers ────────────────────────────────────────────────────────────────
local function elapsed_secs()
  if S.mode == "WORKING" then
    return math.max(0, r.time_precise() - S.last_start_time)
  end
  return 0
end

local function fmt_clock(ts)
  if not ts or ts == 0 then return "-" end
  return os.date("%H:%M:%S", ts)
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

local function get_work_mode()
  local m = get_extstate("WORK_MODE")
  if m and m ~= "" then return m end
  return "Dialog"
end

local function set_work_mode(mode)
  S.work_mode = mode
  set_extstate("WORK_MODE", mode)
end

local function reset_state()
  S.mode = "IDLE"; S.scene_guid = ""; S.scene_name = ""
  S.scene_start_tc = ""
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

local function get_track_by_name(name)
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname == name then return t end
  end
  return nil
end

local function get_or_create_folder_track(name, allow_create)
  local t = get_track_by_name(name)
  if t then return t end
  if not allow_create then return nil end

  local insert_idx = r.CountTracks(0)
  r.InsertTrackAtIndex(insert_idx, true)
  t = r.GetTrack(0, insert_idx)
  r.GetSetMediaTrackInfo_String(t, "P_NAME", name, true)
  r.SetMediaTrackInfo_Value(t, "I_FOLDERDEPTH", 1)
  return t
end

local function get_item_guid(item)
  local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid
end

local function set_item_ext(item, key, val)
  r.GetSetMediaItemInfo_String(item, "P_EXT:" .. key, tostring(val), true)
end

----------------------------------------------------------------
-- Apply color from WORK_TYPE
----------------------------------------------------------------

local function apply_color_from_type(item)
  if not item then return end

  local ok, work_type = reaper.GetSetMediaItemInfo_String(
    item,
    "P_EXT:WORK_TYPE",
    "",
    false
  )

  if not ok or work_type == "" then return end

  local c = WORK_COLORS[work_type]
  if not c then return end

  local color = reaper.ColorToNative(c[1], c[2], c[3]) | 0x1000000
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
end

local function get_scene_info_from_item(scene_item)
  if not scene_item then return nil end
  local scene_guid = r.BR_GetMediaItemGUID(scene_item)
  local take = r.GetActiveTake(scene_item)
  local scene_name = take and r.GetTakeName(take) or ""
  if scene_name == "" then
    local _, notes = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
    scene_name = (notes and notes ~= "") and notes or "(unnamed)"
  end
  local scene_start_tc = r.format_timestr_pos(
    r.GetMediaItemInfo_Value(scene_item, "D_POSITION"), "", 5)
  return { guid = scene_guid, name = scene_name, start_tc = scene_start_tc }
end

local function get_selected_scene_info(scene_track)
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if r.GetMediaItemTrack(item) == scene_track then
      return get_scene_info_from_item(item)
    end
  end
  return nil
end

local function get_scene_info_by_guid(scene_guid)
  if scene_guid == "" then return nil end
  local item = get_item_by_guid(scene_guid)
  return get_scene_info_from_item(item)
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

local function ensure_folder_track(track)
  if not track then return end
  local fd = math.floor(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH"))
  if fd ~= 1 then
    r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 1)
  end
end

-- Find or create a YYYY-MM-DD date track as a direct child of a folder track.
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
      if tname == date_str then return t end
      last_date_idx = i
    elseif tname == DURATION_LOG_NAME then
      duration_log_idx = i
    end

    depth = depth + fd
    if depth <= 0 then break end
  end

  if duration_log_idx >= 0 then
    r.InsertTrackAtIndex(duration_log_idx, true)
    local dt = r.GetTrack(0, duration_log_idx)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", date_str, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", 0)
    return dt

  elseif last_date_idx < 0 then
    r.InsertTrackAtIndex(sc_0idx + 1, true)
    local dt = r.GetTrack(0, sc_0idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", date_str, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt

  else
    r.SetMediaTrackInfo_Value(r.GetTrack(0, last_date_idx), "I_FOLDERDEPTH", 0)
    r.InsertTrackAtIndex(last_date_idx + 1, true)
    local dt = r.GetTrack(0, last_date_idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", date_str, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt
  end
end

-- Find or create DurationOnly_Log as the last child of a folder track.
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

    if tname == DURATION_LOG_NAME then return t end

    last_child_idx = i
    depth = depth + fd
    if depth <= 0 then break end
  end

  if last_child_idx < 0 then
    r.InsertTrackAtIndex(sc_0idx + 1, true)
    local dt = r.GetTrack(0, sc_0idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", DURATION_LOG_NAME, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt
  else
    r.SetMediaTrackInfo_Value(r.GetTrack(0, last_child_idx), "I_FOLDERDEPTH", 0)
    r.InsertTrackAtIndex(last_child_idx + 1, true)
    local dt = r.GetTrack(0, last_child_idx + 1)
    r.GetSetMediaTrackInfo_String(dt, "P_NAME", DURATION_LOG_NAME, true)
    r.SetMediaTrackInfo_Value(dt, "I_FOLDERDEPTH", -1)
    return dt
  end
end

-- ── Work item ──────────────────────────────────────────────────────────────
-- scene_guid : "" in Project Mode (SCENE_GUID ext-state not written)
-- item_name  : pre-computed final name
--   Scene Mode   → "scene_name (tc) | work_type"  (sync will keep it updated)
--   Project Mode → "work_type"                     (sync skips; name is permanent)
local function create_work_item(date_track, scene_guid, item_name, work_type, pos_secs, start_clock)
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

  local take = r.AddTakeToMediaItem(item)
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", item_name, true)

  if scene_guid ~= "" then
    set_item_ext(item, "SCENE_GUID", scene_guid)
  end
  set_item_ext(item, "WORK_TYPE",   work_type)
  set_item_ext(item, "START_CLOCK", tostring(start_clock or os.time()))

  r.UpdateItemInProject(item)
  apply_color_from_type(item)
  r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
  return item
end

-- ── Actions ────────────────────────────────────────────────────────────────
local function action_start()
  -- 1. Find Scene Cut track (if it exists)
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)

  -- 2. Detect mode: Scene (scene item selected on Scene Cut) vs Project (no selection)
  local sel_scene = nil
  if S.work_mode == "Dialog" and scene_track then
    sel_scene = get_selected_scene_info(scene_track)
  end

  local scene_guid, scene_name, scene_start_tc = "", "", ""
  if sel_scene then
    scene_guid = sel_scene.guid
    scene_name = sel_scene.name
    scene_start_tc = sel_scene.start_tc
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

  -- 4. Build item name
  --    Scene Mode   : "scene_name (tc) | work_type"  (sync will keep it current)
  --    Project Mode : "work_type"                     (permanent; sync skips it)
  local item_name
  if scene_guid ~= "" then
    item_name = scene_name .. " (" .. scene_start_tc .. ") | " .. work_type
  else
    item_name = work_type
  end

  -- 5. Build track structure and create item
  local parent_track
  if scene_guid ~= "" then
    parent_track = scene_track
  else
    parent_track = get_or_create_folder_track(WORK_LOG_NAME, true)
  end
  if not parent_track then
    r.ShowMessageBox("Work log track not found.", "PM Timer", 0)
    return
  end

  local pos_secs    = secs_since_midnight()
  local now_clock   = os.time()
  local now_precise = r.time_precise()

  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)
  local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
  local item       = create_work_item(date_track, scene_guid, item_name, work_type, pos_secs, now_clock)
  local item_guid  = get_item_guid(item)
  r.Undo_EndBlock("PM: Start work session", -1)
  r.UpdateArrange()

  -- 6. Update state + ExtState
  S.mode            = "WORKING"
  S.scene_guid      = scene_guid
  S.scene_name      = scene_name
  S.scene_start_tc  = scene_start_tc
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

local function finish_current_item(end_reason, keep_active)
  local end_time = r.time_precise()
  local duration = end_time - S.last_start_time
  local end_pos = nil

  local item = get_item_by_guid(S.work_item_guid)
  if item then
    local start_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    end_pos = start_pos + math.max(duration, 0)
    r.Undo_BeginBlock()
    r.SetMediaItemInfo_Value(item, "C_LOCK",   0)  -- unlock before modifying length
    r.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(duration, 0))
    set_item_ext(item, "END_REASON", end_reason)
    set_item_ext(item, "END_CLOCK",  tostring(os.time()))
    set_item_ext(item, "DURATION",   tostring(duration))
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- relock after modifying
    r.Undo_EndBlock("PM: " .. end_reason .. " work session", -1)
    r.UpdateArrange()
  end

  if not keep_active then
    clear_active_extstate()
    reset_state()
  end

  return end_time, end_pos
end

-- ── Sync work item names ────────────────────────────────────────────────────
-- Rebuilds take names for all Scene Mode work items (those with P_EXT:SCENE_GUID).
-- Project Mode items (no SCENE_GUID) are naturally skipped by the sg ~= "" check.
-- Name format: "scene_name (start_tc) | work_type"
-- Missing-scene fallback: "[Missing Scene] | work_type"
local function sync_work_item_names()
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
        if sg ~= "" then  -- Scene Mode items only; Project Mode items untouched
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

local function action_finish() finish_current_item("finish"); sync_work_item_names() end
local function action_break()  finish_current_item("break");  sync_work_item_names() end

local function action_switch_type()
  if S.mode ~= "WORKING" then return end
  local parent_track
  if S.scene_guid ~= "" then
    parent_track = get_or_create_folder_track(SCENE_TRACK_NAME, false)
    if not parent_track then
      r.ShowMessageBox("Track '" .. SCENE_TRACK_NAME .. "' not found.", "PM Timer", 0)
      return
    end
  else
    parent_track = get_or_create_folder_track(WORK_LOG_NAME, true)
    if not parent_track then
      r.ShowMessageBox("Work log track not found.", "PM Timer", 0)
      return
    end
  end

  local end_time, end_pos = finish_current_item("switch", true)
  local now_clock = os.time()

  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(SWITCH_TYPES, "|"))
  local new_type = SWITCH_TYPES[choice] or S.work_type
  if new_type == "custom" then
    local ok, val = r.GetUserInputs("Custom Work Type", 1, "Work type:", "")
    if ok and val ~= "" then
      new_type = val
    else
      new_type = S.work_type
    end
  end

  local scene_name = S.scene_name
  local scene_start_tc = S.scene_start_tc
  if S.scene_guid ~= "" and scene_start_tc == "" then
    local sc = get_scene_info_by_guid(S.scene_guid)
    if sc then
      scene_name = sc.name
      scene_start_tc = sc.start_tc
    end
  end

  local item_name
  if S.scene_guid ~= "" then
    if scene_start_tc ~= "" then
      item_name = scene_name .. " (" .. scene_start_tc .. ") | " .. new_type
    else
      item_name = "[Missing Scene] | " .. new_type
    end
  else
    item_name = new_type
  end

  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)
  local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
  local item = create_work_item(date_track, S.scene_guid, item_name, new_type,
    end_pos or secs_since_midnight(), now_clock)
  local item_guid = get_item_guid(item)
  r.Undo_EndBlock("PM: Switch work type", -1)
  r.UpdateArrange()

  S.mode            = "WORKING"
  S.work_type       = new_type
  S.work_item_guid  = item_guid
  S.start_clock     = now_clock
  S.last_start_time = end_time
  S.scene_name      = scene_name
  S.scene_start_tc  = scene_start_tc

  set_extstate("ACTIVE_WORK_ITEM_GUID",    item_guid)
  set_extstate("ACTIVE_WORK_SCENE_GUID",   S.scene_guid)
  set_extstate("ACTIVE_WORK_SCENE_NAME",   scene_name)
  set_extstate("ACTIVE_WORK_TYPE",         new_type)
  set_extstate("ACTIVE_WORK_START_CLOCK",  tostring(now_clock))
  set_extstate("ACTIVE_WORK_OSTIME_START", tostring(now_clock))
end

local function action_switch_scene()
  if S.mode ~= "WORKING" then return end

  local scene_track = get_or_create_folder_track(SCENE_TRACK_NAME, false)
  if not scene_track then
    r.ShowMessageBox("Track '" .. SCENE_TRACK_NAME .. "' not found.", "PM Timer", 0)
    return
  end

  local sel_scene = get_selected_scene_info(scene_track)
  if not sel_scene then
    r.ShowMessageBox("Please select a Scene Cut item first.", "PM Timer", 0)
    return
  end

  local end_time, end_pos = finish_current_item("switch_scene", true)
  local now_clock = os.time()

  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(SWITCH_TYPES, "|"))
  local new_type = SWITCH_TYPES[choice] or S.work_type
  if new_type == "custom" then
    local ok, val = r.GetUserInputs("Custom Work Type", 1, "Work type:", "")
    if ok and val ~= "" then
      new_type = val
    else
      new_type = S.work_type
    end
  end

  local item_name = sel_scene.name .. " (" .. sel_scene.start_tc .. ") | " .. new_type
  r.Undo_BeginBlock()
  ensure_folder_track(scene_track)
  local date_track = get_or_create_date_track(scene_track, os.date("%Y-%m-%d"))
  local item = create_work_item(date_track, sel_scene.guid, item_name, new_type,
    end_pos or secs_since_midnight(), now_clock)
  local item_guid = get_item_guid(item)
  r.Undo_EndBlock("PM: Switch scene", -1)
  r.UpdateArrange()

  S.mode            = "WORKING"
  S.scene_guid      = sel_scene.guid
  S.scene_name      = sel_scene.name
  S.scene_start_tc  = sel_scene.start_tc
  S.work_type       = new_type
  S.work_item_guid  = item_guid
  S.start_clock     = now_clock
  S.last_start_time = end_time

  set_extstate("ACTIVE_WORK_ITEM_GUID",    item_guid)
  set_extstate("ACTIVE_WORK_SCENE_GUID",   sel_scene.guid)
  set_extstate("ACTIVE_WORK_SCENE_NAME",   sel_scene.name)
  set_extstate("ACTIVE_WORK_TYPE",         new_type)
  set_extstate("ACTIVE_WORK_START_CLOCK",  tostring(now_clock))
  set_extstate("ACTIVE_WORK_OSTIME_START", tostring(now_clock))
end

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

local function action_switch_mode()
  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(MODE_TYPES, "|"))
  if choice == 0 then return end
  local mode = MODE_TYPES[choice] or "Dialog"
  set_work_mode(mode)
end

----------------------------------------------------------------
-- Sync all existing work item colors
----------------------------------------------------------------

local function sync_work_item_colors()
  local track_count = reaper.CountTracks(0)

  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(0, i)
    local item_count = reaper.CountTrackMediaItems(track)

    for j = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, j)

      local ok, work_type = reaper.GetSetMediaItemInfo_String(
        item,
        "P_EXT:WORK_TYPE",
        "",
        false
      )

      if ok and work_type ~= "" then
        apply_color_from_type(item)
      end
    end
  end
end

-- ── Add Record ─────────────────────────────────────────────────────────────
-- Auto-detects Scene vs Project mode the same way as action_start().
-- Timed mode        : Start + End as HHMM → item on date track
-- Duration-only mode: Dur Hours + Mins    → item on DurationOnly_Log track
local function action_add_record()
  if S.mode == "WORKING" then
    r.ShowMessageBox("Finish current session first.", "Add Record", 0)
    return
  end

  -- Find Scene Cut (if it exists)
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  local parent_track = scene_track

  -- Detect mode: Scene (scene item selected) vs Project (no selection)
  local sel_scene = nil
  if S.work_mode == "Dialog" and scene_track then
    sel_scene = get_selected_scene_info(scene_track)
  end

  local scene_guid, scene_name, scene_start_tc = "", "", ""
  if sel_scene then
    scene_guid = sel_scene.guid
    scene_name = sel_scene.name
    scene_start_tc = sel_scene.start_tc
  else
    parent_track = get_or_create_folder_track(WORK_LOG_NAME, true)
  end
  if not parent_track then
    r.ShowMessageBox("Work log track not found.", "Add Record", 0)
    return
  end

  -- Work type via menu
  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(WORK_TYPES, "|"))
  if choice == 0 then return end
  local work_type = WORK_TYPES[choice]
  if work_type == "custom" then
    local ok2, val = r.GetUserInputs("Custom Work Type", 1, "Work type:", "")
    if not ok2 or val == "" then return end
    work_type = val
  end

  -- Input dialog
  local ok, raw = r.GetUserInputs("Add Record", 5,
    "Date (YYMMDD):,Start (HHMM):,End   (HHMM):,Dur Hours:,Dur Mins:",
    os.date("%y%m%d") .. ",,,,")
  if not ok then return end

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

  -- Build item name
  --   Scene Mode   : "scene_name (tc) | work_type"
  --   Project Mode : "work_type"
  local item_name
  if scene_guid ~= "" then
    item_name = scene_name .. " (" .. scene_start_tc .. ") | " .. work_type
  else
    item_name = work_type
  end

  -- Create item
  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)

  if is_timed then
    local length     = e_secs - s_secs
    local date_track = get_or_create_date_track(parent_track, date_str)
    local item       = r.AddMediaItemToTrack(date_track)
    r.SetMediaItemInfo_Value(item, "D_POSITION", s_secs)
    r.SetMediaItemInfo_Value(item, "D_LENGTH",   length)
    local it = r.AddTakeToMediaItem(item)
    r.GetSetMediaItemTakeInfo_String(it, "P_NAME", item_name, true)
    if scene_guid ~= "" then
      set_item_ext(item, "SCENE_GUID", scene_guid)
    end
    set_item_ext(item, "WORK_TYPE",   work_type)
    set_item_ext(item, "DURATION",    tostring(length))
    set_item_ext(item, "END_REASON",  "manual")
    set_item_ext(item, "START_CLOCK", start_str)
    set_item_ext(item, "END_CLOCK",   end_str)
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
    r.Undo_EndBlock("PM: Add Record (timed)", -1)

  else  -- duration-only
    local dur_track = get_or_create_duration_log_track(parent_track)
    local item      = r.AddMediaItemToTrack(dur_track)
    r.SetMediaItemInfo_Value(item, "D_POSITION", 0)
    r.SetMediaItemInfo_Value(item, "D_LENGTH",   d_secs)
    local it = r.AddTakeToMediaItem(item)
    r.GetSetMediaItemTakeInfo_String(it, "P_NAME", item_name, true)
    if scene_guid ~= "" then
      set_item_ext(item, "SCENE_GUID", scene_guid)
    end
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
  if #name_disp > 18 then name_disp = name_disp:sub(1, 17) .. "..." end
  local type_disp = (S.work_type ~= "") and S.work_type or "---"
  if #type_disp > 10 then type_disp = type_disp:sub(1, 9) .. "..." end
  local mode_disp = (S.work_mode ~= "") and S.work_mode or "Dialog"
  local start_disp = (S.mode == "WORKING") and fmt_clock(S.start_clock) or "--:--:--"

  gfx.setfont(3)
  gfx.x, gfx.y = 10, 12

  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("Mode: ")
  gfx.set(1,   1,   1,   1); gfx.drawstr(mode_disp)
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Scene: ")
  gfx.set(1,   1,   1,   1); gfx.drawstr(name_disp ~= "" and name_disp or "---")
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Type: ")
  gfx.set(1,   1,   1,   1); gfx.drawstr(type_disp)
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Status: ")
  if S.mode == "WORKING" then
    gfx.set(0.2, 1.0, 0.2, 1); gfx.drawstr("WORKING")
  else
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("IDLE")
  end

  gfx.x, gfx.y = 10, 28
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("Start: ")
  gfx.set(1,   1,   1,   1); gfx.drawstr(start_disp)
  gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Elapsed: ")
  gfx.set(0.2, 0.8, 1.0, 1); gfx.drawstr(fmt_hms(elapsed_secs()))

  sep(44)

  -- ── Horizontal buttons ──────────────────────────────────────────────────
  local btn_w   = 129
  local btn_h   = 40
  local btn_y   = 58
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

  if working then
    add_btn(1, "Switch Scene", action_switch_scene)
    add_btn(2, "Switch Type",  action_switch_type)
    add_btn(3, "Break",        action_break)
    add_btn(4, "Finish Day",   action_finish)
  else
    add_btn(1, "Start",      action_start)
    add_btn(2, "Mode",       action_switch_mode)
    add_btn(3, "Add Record", action_add_record)
    draw_btn_disabled(btn_x(4), btn_y, btn_w, btn_h, "")
  end

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
      cur_dock = gfx.dock(-1)
      r.SetExtState(NS, "DOCK_STATE", tostring(cur_dock), true)
      last_dock = cur_dock
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
  S.work_mode = get_work_mode()
  local guid = get_extstate("ACTIVE_WORK_ITEM_GUID")
  if not guid then return end

  if not get_item_by_guid(guid) then
    clear_active_extstate(); return
  end

  S.mode           = "WORKING"
  S.work_item_guid = guid
  S.scene_guid     = get_extstate("ACTIVE_WORK_SCENE_GUID") or ""
  S.scene_name     = get_extstate("ACTIVE_WORK_SCENE_NAME") or ""
  S.scene_start_tc = ""
  S.work_type      = get_extstate("ACTIVE_WORK_TYPE")       or ""
  S.start_clock    = tonumber(get_extstate("ACTIVE_WORK_START_CLOCK"))  or os.time()

  if S.scene_guid ~= "" then
    local sc = get_scene_info_by_guid(S.scene_guid)
    if sc and sc.start_tc then S.scene_start_tc = sc.start_tc end
  end

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
      r.SetExtState(NS, "WIN_X",      tostring(win_x),    true)
      r.SetExtState(NS, "WIN_Y",      tostring(win_y),    true)
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
  if cur_dock ~= last_dock then
    r.SetExtState(NS, "DOCK_STATE", tostring(cur_dock), true)
    last_dock = cur_dock
  end

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
sync_work_item_colors()
last_draw_time = r.time_precise()
r.defer(loop)
