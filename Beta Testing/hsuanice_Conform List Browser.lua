--[[
@description PM Timer - Scene-aware Work Timer
@version 260324.1250
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
  v260324.1250
    - Conform mode work type menu: conform, picture cut, subtitle, custom
      (was conform-only). Custom prompts for free-text entry.
    - Added WORK_COLORS entries: picture cut (red), subtitle (cyan).

  v260323.2205
    - Dialog work type menu: editing, denoise, scene, ME, PAN, ME+PAN, custom
      (same list for both scene-selected and project-scope sessions).
    - Conform work type menu: conform only (auto-selected, single item).
    - Removed separate project-scope ME+PAN/PAN/Custom branch; all modes now
      use get_work_types_for_mode() uniformly.

  v260320.2259
    - New: PM_SyncProjectScopeNotes() — rescans all project-scope work items
      (WORK_TYPE set, SCENE_GUID empty) and rewrites their note with current
      project metadata (Scope, Scenes, Reel Len, Shots, Src Cnt, Src Len).
      Preserves user comments (text after first blank line).
      Called on startup, project change, action_finish, and action_break.

  v260320.2254
    - Project-scope note: Scope field now reads the 3rd part of the project
      filename (e.g. "EP04" from "260320----TheFixer----EP04----Dialog").
      Falls back to "Project" if filename doesn't match the expected format.

  v260320.2249
    - Project-scope work items (no scene selected) now get a note with
      full project metadata: Scope, Scenes, Reel Len, Shots, Src Cnt, Src Len.
      Computed from Scene Cut, Picture Cut, and EDL folder at session start.

  v260320.2246
    - Dialog mode, no scene selected → Project scope: shows menu with
      ME+PAN / PAN / Custom instead of auto-setting ME&PAN.

  v260320.2139
    - Dialog mode: no scene selected → Project scope, work type auto-set to
      "ME&PAN" (skips work type menu). Scene selection is no longer required.

  v260318.2215
    - UI: "Finish Day" button renamed to "Finish".

  v260318.1618
    - Break now saves session context (scene, work type) so it can be resumed.
    - New: "Continue" button appears in IDLE when a break is active; restores
      the previous scene + work type and starts a new work item immediately,
      without showing any menus.
    - New: "Start New" replaces "Start" when break state is pending; clicking
      it begins a fresh session and clears the saved break.
    - Status row shows "ON BREAK" (amber) instead of "IDLE" during a break,
      and previews the paused scene name and work type in the info row.
    - Break state persisted via ProjExtState so it survives REAPER restarts.
    - Fix: build_work_item_note() called with spurious 2nd argument in
      action_switch_scene (pre-existing, now corrected).

  v260307.0335
    - Fix: copy_item_to_wl now uses native P_NOTES instead of ULT_GetMediaItemNote /
      ULT_SetMediaItemNote, resolving "argument 1: expected MediaItem*" crash caused
      by SWS ULT functions requiring matching project context.
    - Fix: copy_item_to_wl now updates existing Work Log items (note, length, color)
      instead of silently skipping them. wl_item_exists() replaced with find_wl_item()
      which returns the item handle for in-place update. No-op if nothing changed.

  v260307.0300
    - New: PM_SyncSceneMetadataToLogItem(item) — reads scene note from the linked
      scene item and writes it into the log item note (ULT_SetMediaItemNote),
      preserving any user comment below the first blank line in the existing note.
    - New: PM_SyncAllLogItems() — scans all project items, filters by take name
      containing "|", calls PM_SyncSceneMetadataToLogItem on each.
      Runs at startup and on project change.
    - Log item note reads/writes now use ULT_GetMediaItemNote / ULT_SetMediaItemNote
      (SWS extension) instead of P_NOTES.
    - sync_linked_work_item_notes now preserves user comments in log item notes
      when pushing updated scene metadata.
    - New: mirror_log_item_to_work_log(item) — after each log item is created,
      auto-mirrors it into the open Work Log project (silent no-op if not found).
    - action_finish: captures work item before state reset and runs
      PM_SyncSceneMetadataToLogItem on the finished item.

  v260305.2100
    - Scene Cut item notes now use the same format as Scene Analyzer:
        Range    : <start> - <end>
        Length   : <duration>
        Shots    : <n>
        Src Cnt  : <n>
        Src Len  : <duration>
      Old key=value lines are recognised and stripped on first update.
    - Auto-update scene metadata on: timer start, timer finish, break,
      stop (abort), and scene switch. Keeps notes current without
      requiring manual Scene Analyzer runs.

  v260305.2000
    - Fix: repeated metadata updates caused src_cnt/src_len to accumulate.
      Root cause: Lua's %w pattern excludes underscore, so "src_cnt=" and
      "src_len=" lines were not matched and were kept as "other" content,
      then appended again on each update. Pattern changed to [%w_]+ to
      correctly strip all key=value metadata lines before rewriting.

  v260305.1945
    - Fix: shots was always 0 because PICTURE_TRACK_NAME was "Picture" instead
      of "Picture Cut". Renamed constant to match the actual track name.
    - Fix: shot overlap detection now uses proper range overlap
      (item_end > scene_start and item_start < scene_end) instead of
      start-only check, so items straddling the scene boundary are counted.

  v260305.1930
    - Scene item notes now always start with the scene name on the first line.
      If the note is empty or has no first line, "(no name)" is used as a placeholder.
      Existing scene names are preserved when metadata is refreshed.
    - "Update Scene Metadata" now supports multiple selected Scene Cut items.
      All selected scenes on the Scene Cut track are updated in one action.
      Result message reports the number of scenes updated.

  v260305.0300
    - New: Scene metadata auto-update on session start (Scene Mode only).
      When starting a work session with a scene selected, the matching Scene Cut
      item's note is updated with:
        shots=   (items on "Picture" track within scene range)
        src_cnt= (EDL items attributed to this scene)
        src_len= (total EDL source length, HH:MM:SS:FF)
      Attribution uses P_EXT:SCENE_ID (priority 1) or color+position (priority 2),
      matching the InsightAnalyzer's EDL attribution logic.
    - New: "Update Scene Metadata" right-click menu option (choice 5).
      Manually refreshes the note on the currently selected Scene Cut item.
    - New constants: EDL_FOLDER_NAME = "EDL", PICTURE_TRACK_NAME = "Picture".

  v260305.0130
    - New: get_proj_task() extracts the Task component (4th part) from the project
      filename (YYMMDD----Project----Episode----Task----...).
    - All newly created work items now store P_EXT:TASK (e.g. "Dialog") so that the
      InsightAnalyzer can group them by task without re-parsing the item name.
      Applies to: live sessions (create_work_item), Add Record (timed + duration-only).

  v260305.0110
    - Fix: Sync to Work Log now also removes orphaned WL items — if a log item is
      deleted from the source project, the next sync removes the corresponding item
      from the Work Log. Only items tagged with P_EXT:WL_SRC_PROJ (i.e. created by
      this script) are eligible for removal; manually added WL items are left alone.
      Result message now reports "N added, N removed" separately.

  v260305.0050
    - New: "Sync to Work Log" right-click menu option (choice 4).
      Mirrors Scene Cut date-track items and DurationOnly_Log items from the current
      dialog project into an open Work Log project (filename must contain "Work Log").
      - Date-track items → flat tracks in Work Log (track named YYYY-MM-DD).
      - DurationOnly_Log items → DurationOnly_Log (folder) > ProjectName (child)
        hierarchy; project name extracted from item name prefix before first " | ".
      - Duplicate check: skips items with same position (±0.001 s) and same take name.
      - Created items are EMPTY (no media source).
      - All changes are grouped into a single undo block in the Work Log project.

  v260305.0038
    - Fix: get_proj_prefix() and get_proj_identity() now use EnumProjects(-1)
      (the currently active project) instead of EnumProjects(0) (tab index 0).
      EnumProjects(0) could return an empty filename in some REAPER configurations,
      causing the prefix to silently not be applied to any items.
    - Right-click menu: added "Fix Item Prefixes" option (choice 3) — manually
      runs sync_work_item_names() + sync_all_prefixes() on all items in the project.
      Use this if items are missing the project prefix after the script restarts.

  v260305.0023
    - Fix: sync_work_item_names() now preserves existing prefix on scene-mode items
      when get_proj_prefix() is unavailable (project filename doesn't match expected
      format), preventing prefix stripping on sync.
    - Fix: sync_work_item_names() now unlocks items before renaming (C_LOCK), then
      relocks, matching the pattern used by sync_all_prefixes().
    - Fix: sync_all_prefixes() now also called after action_add_record() so that
      custom work-type items and duration-only items get their prefix applied
      immediately (they have no SCENE_GUID so sync_work_item_names() skips them).

  v260305.0008
    - Dialog mode: Project Mode items (no scene selected) now placed under Scene Cut
      date tracks instead of Work Log. DurationOnly_Log also moves under Scene Cut.
      All Dialog-mode logs are now consolidated in one place. AAP mode is unaffected.

  v260304.2358
    - Fix: sync_all_prefixes() now called at startup and on project change,
      so existing items (Project Mode, AAP) also get the prefix applied.
      sync_work_item_names() only covers Scene Mode items; sync_all_prefixes()
      covers everything with P_EXT:WORK_TYPE regardless of mode.

  v260304.2350
    - Project prefix: work item names are automatically prefixed with
      "Project Episode Task | " parsed from the project filename.
      Format: YYMMDD----Project----Episode----Task----OptionalNote
      Example: 260304----TheFixer----EP04----Dialog → prefix "TheFixer EP04 Dialog | "
      Applied on creation (create_work_item), sync (sync_work_item_names),
      and manual record (action_add_record). Duplicate-safe (prefix not added twice).

  v260304.2252
    - Project change detection: script now monitors EnumProjects(0) filename each
      loop iteration. When the active project changes (close/reopen without
      REAPER restart, or docked-script timing where project loads after the
      script), state is reset and try_recover() runs automatically — no more
      manual toggle required to trigger the resume dialog.

  v260304.2240
    - Crash recovery dialog: on startup, if a session was interrupted (crash /
      unexpected REAPER close), shows: Resume / Finish & save / Discard.
    - Heartbeat: every 60 s the active work item's D_LENGTH is silently updated
      so crash recovery always has approximate timing (no undo entry).

  v260304.2225
    - Right-click menu: added "Fix Duration from item length"
      Select stretched work item(s) in REAPER → right-click PM Timer →
      Fix Duration; overwrites P_EXT:DURATION with current D_LENGTH so
      InsightAnalyzer reads the corrected time after a crash/manual resize.

  v260304.1300
    - UI: "Scene:" label switches to "Day:" as soon as AAP mode is active (IDLE or
      WORKING), not only when a work item is running

  v260304.1200
    - Fix: get_selected_folder_stats() now counts items on the parent folder track
      itself (previously only child tracks were iterated; items placed directly on
      the folder track were silently skipped)

  v260304.1100
    - Fix: gap between work items when using New Job / switching
      finish_aap_item() now returns (end_time, end_pos); callers pass these as
      a "chain" struct so the next item starts exactly where the previous ended
      (D_POSITION = end_pos, last_start_time = end_time, no menu-delay gap)

  v260304.1000
    - "New Day" button renamed to "New Job" in AAP WORKING state
    - New Job: finish current item → submenu [pre-prod | new day | wrap | custom]
        pre-prod/wrap/custom → simple work item (no folder needed)
        new day              → folder-based AAP start (select folder first)
    - Extracted start_simple_aap_work() helper to avoid code duplication

  v260303.2400
    - AAP folder path: confirmation dialog pre-filled with auto-detected stats;
      user can review/edit Items and Total Duration before creating the item
    - Total Len format changed to H:M:S.ms (e.g. 3:42:41.996) in P_NOTES
    - New: fmt_hms_ms() and parse_duration_str() helpers

  v260303.2350
    - AAP Start: two paths based on folder selection
        Folder selected   → AAP with stats (item count / length / size) as before
        No folder selected→ show [pre-prod | wrap] menu; create simple work item
    - Fix: AAP-specific P_EXT metadata (AAP_DAY_NAME etc.) was silently lost because
      create_work_item() locks the item (C_LOCK=1) before returning; fix: unlock →
      write P_EXT → relock in action_start_aap()
    - fix: finish_aap_item() P_NOTES omits Items/Size rows when no folder stats exist
    - Fix: try_recover() now restores AAP state for all AAP work types (was "aap" only)
    - New work types: pre-prod (orange), wrap (light blue)

  v260303.2340
    - Fix: get_selected_folder_stats() now counts items on the last child track
      (break was firing before the item loop — moved to after)
    - AAP WORKING UI simplified: removed 6-row display and dynamic window height;
      uses standard 2-row layout with "Day: <name>" instead of "Scene:"
    - WIN_H fixed at 140px in all states (no more gfx.init resize on state change)

  v260303.2320
    - Work Log track inserted at top of track list when created (AAP mode)
    - AAP WORKING buttons: [New Day] [Break] [Finish] (+ 1 disabled)
    - New Day: saves current session notes, immediately starts next AAP session
      (user selects next folder track in REAPER before clicking)

  v260303.2310
    - AAP Mode: select a folder track → logs item count, total length, est. size
    - AAP Start creates "AAP | <folder_name>" item on Work Log track
    - AAP Finish writes P_NOTES (Items / Total Len / Est. Size / Work Time)
    - Mode button (IDLE) cycles Dialog ↔ AAP ↔ Conform via existing menu
    - Dynamic window height: 180px in AAP WORKING, 140px otherwise
    - Recovery: AAP state persisted across REAPER restarts

  v260303.2253
    - Dialog mode hides aap/conform from work type menu

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
  editing          = {255, 255, 0},     -- Yellow
  denoise          = {255, 0, 255},     -- Magenta
  aap              = {0, 0, 255},       -- Blue
  conform          = {0, 255, 0},       -- Green
  ["picture cut"]  = {255, 100, 100},   -- Red
  subtitle         = {0, 200, 200},     -- Cyan
  ["pre-prod"]     = {255, 140, 0},     -- Orange
  wrap             = {100, 220, 255},   -- Light blue
}

-- ── Constants ──────────────────────────────────────────────────────────────
local NS                = "hsuanice_PM"
local SCENE_TRACK_NAME  = "Scene Cut"
local WORK_LOG_NAME     = "Work Log"
local DURATION_LOG_NAME = "DurationOnly_Log"
local WIN_W, WIN_H           = 560, 140
local BYTES_PER_SECOND       = 144000
local BYTES_PER_GB           = 1000000000
local WORK_TYPES          = { "editing", "denoise", "conform", "aap", "double_check", "custom" }
local SWITCH_TYPES        = { "editing", "denoise", "custom" }
local MODE_TYPES          = { "Dialog", "AAP", "Conform" }
local AAP_GENERAL_TYPES   = { "pre-prod", "wrap" }   -- used when no folder is selected in AAP mode
local DATE_PAT            = "^%d%d%d%d%-%d%d%-%d%d$"  -- matches YYYY-MM-DD
local HEARTBEAT_INTERVAL  = 60   -- seconds between silent D_LENGTH updates
local EDL_FOLDER_NAME     = "EDL"
local PICTURE_TRACK_NAME  = "Picture Cut"

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
  -- AAP mode fields
  aap_day_name      = "",
  aap_item_count    = 0,
  aap_total_seconds = 0,
  aap_est_size      = "",
}

-- ── Refresh + mouse state ──────────────────────────────────────────────────
local last_draw_time      = 0
local last_heartbeat_time = 0
local mouse_prev          = 0
local mouse_r_prev    = 0
local BTN             = {}
local running         = true
local win_x           = tonumber(r.GetExtState(NS, "WIN_X"))       or 100
local win_y           = tonumber(r.GetExtState(NS, "WIN_Y"))       or 100
local cur_dock        = tonumber(r.GetExtState(NS, "DOCK_STATE"))  or 0
local last_dock       = cur_dock
local last_proj_identity = nil  -- tracks active project for change detection
local BREAK_STATE = nil  -- {scene_guid, scene_name, scene_start_tc, work_type} set by action_break

-- ── Helpers ────────────────────────────────────────────────────────────────

-- Returns a string that uniquely identifies the current project (its file path).
-- Falls back to "" for unsaved/new projects. Used to detect project changes.
-- Uses EnumProjects(-1) = the currently active project (not tab index 0).
local function get_proj_identity()
  local _, fn = r.EnumProjects(-1)
  return fn or ""
end
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

-- Format seconds to H:MM:SS.mmm (includes milliseconds; no leading zero on hours)
local function fmt_hms_ms(secs)
  secs = math.max(0, secs)
  local ms  = math.floor((secs % 1) * 1000 + 0.5)
  if ms >= 1000 then ms = 999 end
  secs = math.floor(secs)
  return string.format("%d:%02d:%02d.%03d",
    math.floor(secs / 3600),
    math.floor((secs % 3600) / 60),
    secs % 60, ms)
end

-- Parse "H:M:S.ms" or "H:M:S" string → seconds (float). Returns nil on failure.
local function parse_duration_str(s)
  if not s or s == "" then return nil end
  s = s:match("^%s*(.-)%s*$")
  local h, m, sec, ms = s:match("^(%d+):(%d+):(%d+)%.(%d+)$")
  if h then
    while #ms < 3 do ms = ms .. "0" end
    ms = ms:sub(1, 3)
    return tonumber(h)*3600 + tonumber(m)*60 + tonumber(sec) + tonumber(ms)/1000
  end
  h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
  if h then return tonumber(h)*3600 + tonumber(m)*60 + tonumber(sec) end
  return nil
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
    "ACTIVE_AAP_DAY_NAME", "ACTIVE_AAP_ITEM_COUNT",
    "ACTIVE_AAP_TOTAL_SECONDS", "ACTIVE_AAP_EST_SIZE",
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

local function get_work_types_for_mode()
  if S.work_mode == "Dialog" then
    return { "editing", "denoise", "scene", "ME", "PAN", "ME+PAN", "custom" }
  end
  if S.work_mode == "Conform" then
    return { "conform", "picture cut", "subtitle", "custom" }
  end
  return WORK_TYPES
end

local function reset_state()
  S.mode = "IDLE"; S.scene_guid = ""; S.scene_name = ""
  S.scene_start_tc = ""
  S.work_type = ""; S.work_item_guid = ""
  S.start_clock = 0; S.last_start_time = 0
  S.aap_day_name = ""; S.aap_item_count = 0
  S.aap_total_seconds = 0; S.aap_est_size = ""
end

-- ── Break state persistence ────────────────────────────────────────────────
local function save_break_state()
  BREAK_STATE = {
    scene_guid    = S.scene_guid,
    scene_name    = S.scene_name,
    scene_start_tc = S.scene_start_tc,
    work_type     = S.work_type,
  }
  set_extstate("BREAK_SCENE_GUID", S.scene_guid)
  set_extstate("BREAK_SCENE_NAME", S.scene_name)
  set_extstate("BREAK_SCENE_TC",   S.scene_start_tc)
  set_extstate("BREAK_WORK_TYPE",  S.work_type)
end

local function load_break_state()
  local wtype = get_extstate("BREAK_WORK_TYPE")
  if not wtype then return end
  BREAK_STATE = {
    scene_guid     = get_extstate("BREAK_SCENE_GUID") or "",
    scene_name     = get_extstate("BREAK_SCENE_NAME") or "",
    scene_start_tc = get_extstate("BREAK_SCENE_TC")   or "",
    work_type      = wtype,
  }
end

local function clear_break_state()
  BREAK_STATE = nil
  set_extstate("BREAK_SCENE_GUID", "")
  set_extstate("BREAK_SCENE_NAME", "")
  set_extstate("BREAK_SCENE_TC",   "")
  set_extstate("BREAK_WORK_TYPE",  "")
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

-- Returns an array of all direct child tracks inside a named folder track.
local function get_folder_children(folder_name)
  local count     = r.CountTracks(0)
  local tracks    = {}
  local in_folder = false
  local depth     = 0
  for i = 0, count - 1 do
    local t        = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    if not in_folder then
      if tname == folder_name and fd == 1 then
        in_folder = true; depth = 1
      end
    else
      table.insert(tracks, t)
      depth = depth + fd
      if depth <= 0 then break end
    end
  end
  return tracks
end

-- Find a track by name in a specific project (uses explicit proj ptr, not current-project "0").
local function find_track_in_proj(proj, name)
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    local _, tname = r.GetTrackName(t)
    if tname == name then return t, i end
  end
  return nil, -1
end

local function get_or_create_folder_track(name, allow_create, at_top)
  local t = get_track_by_name(name)
  if t then return t end
  if not allow_create then return nil end

  local insert_idx = (at_top) and 0 or r.CountTracks(0)
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

-- ── Project prefix ──────────────────────────────────────────────────────────
-- Parses the project filename using the format:
--   YYMMDD----Project----Scope----Task----OptionalNote
-- Returns "Project Scope Task | " or "" if the project name doesn't match.
local function get_proj_prefix()
  local _, proj_path = r.EnumProjects(-1)
  if not proj_path or proj_path == "" then return "" end
  local name = proj_path:match("([^/\\]+)$") or proj_path
  name = name:gsub("%.%a+$", "")  -- strip extension (.RPP etc.)
  local parts = {}
  for p in (name .. "----"):gmatch("(.-)%-%-%-%-") do
    parts[#parts + 1] = p
  end
  -- parts[1]=YYMMDD, parts[2]=Project, parts[3]=Scope, parts[4]=Task
  local project = parts[2]
  local scope   = parts[3]
  local task    = parts[4]
  if not project or project == "" then return "" end
  if not scope   or scope   == "" then return "" end
  if not task    or task    == "" then return "" end
  return project .. " " .. scope .. " " .. task .. " | "
end

-- Returns the Scope component (3rd part) of the project name, e.g. "EP04".
local function get_proj_scope()
  local _, proj_path = r.EnumProjects(-1)
  if not proj_path or proj_path == "" then return "" end
  local name = proj_path:match("([^/\\]+)$") or proj_path
  name = name:gsub("%.%a+$", "")
  local parts = {}
  for p in (name .. "----"):gmatch("(.-)%-%-%-%-") do
    parts[#parts + 1] = p
  end
  return parts[3] or ""
end

-- Returns just the Task component (4th part) of the project name, e.g. "Dialog".
local function get_proj_task()
  local _, proj_path = r.EnumProjects(-1)
  if not proj_path or proj_path == "" then return "" end
  local name = proj_path:match("([^/\\]+)$") or proj_path
  name = name:gsub("%.%a+$", "")
  local parts = {}
  for p in (name .. "----"):gmatch("(.-)%-%-%-%-") do
    parts[#parts + 1] = p
  end
  return parts[4] or ""
end

-- Prepend the project prefix to name. No-ops if prefix is empty or already present.
local function apply_proj_prefix(name)
  local prefix = get_proj_prefix()
  if prefix == "" then return name end
  if name:sub(1, #prefix) == prefix then return name end
  return prefix .. name
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
  return { guid = scene_guid, name = scene_name, start_tc = scene_start_tc, handle = scene_item }
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

-- Find a Scene Cut item by GUID using BR_GetMediaItemGUID (safe for scene GUIDs).
local function find_scene_item_by_guid(guid)
  if not guid or guid == "" then return nil end
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  if not scene_track then return nil end
  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local item = r.GetTrackMediaItem(scene_track, i)
    if r.BR_GetMediaItemGUID(item) == guid then return item end
  end
  return nil
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
--   Scene Mode   → "work_type"  (name is just the action; scene metadata goes in P_NOTES)
--   Project Mode → "work_type"  (sync skips; name is permanent)
-- item_note  : optional P_NOTES string (scene metadata block); nil/empty = preserve existing
local function create_work_item(date_track, scene_guid, item_name, work_type, pos_secs, start_clock, item_note)
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

  item_name = apply_proj_prefix(item_name)
  local take = r.AddTakeToMediaItem(item)
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", item_name, true)

  if scene_guid ~= "" then
    set_item_ext(item, "SCENE_GUID", scene_guid)
  end
  set_item_ext(item, "WORK_TYPE",   work_type)
  set_item_ext(item, "START_CLOCK", tostring(start_clock or os.time()))
  local _task = get_proj_task()
  if _task ~= "" then set_item_ext(item, "TASK", _task) end

  if item_note and item_note ~= "" then
    r.ULT_SetMediaItemNote(item, item_note)
  end

  r.UpdateItemInProject(item)
  apply_color_from_type(item)
  r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
  return item
end

-- ── AAP helpers ────────────────────────────────────────────────────────────

local function seconds_to_size_string(seconds)
  local bytes = seconds * BYTES_PER_SECOND
  local gb    = bytes / BYTES_PER_GB
  if gb < 1 then
    return string.format("%.1f MB", bytes / 1000000)
  else
    return string.format("%.2f GB", gb)
  end
end

local function get_selected_folder_stats()
  local track = r.GetSelectedTrack(0, 0)
  if not track then return nil, "No track selected" end

  local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
  if depth ~= 1 then return nil, "Selected track is not a folder" end

  local total_items   = 0
  local total_seconds = 0
  local track_index   = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
  local total_tracks  = r.CountTracks(0)

  -- Count items directly on the parent folder track itself
  for j = 0, r.CountTrackMediaItems(track) - 1 do
    local item = r.GetTrackMediaItem(track, j)
    total_items   = total_items   + 1
    total_seconds = total_seconds + r.GetMediaItemInfo_Value(item, "D_LENGTH")
  end

  for i = track_index + 1, total_tracks - 1 do
    local t = r.GetTrack(0, i)
    local d = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
    local ic = r.CountTrackMediaItems(t)
    for j = 0, ic - 1 do
      local item = r.GetTrackMediaItem(t, j)
      total_items   = total_items   + 1
      total_seconds = total_seconds + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    end
    if d == -1 then break end
  end

  local _, name = r.GetTrackName(track)
  return { name = name, item_count = total_items, total_seconds = total_seconds }
end

-- Create a simple AAP work item (no folder stats) on the Work Log track.
-- Used for pre-prod, wrap, and custom types.
-- chain (optional): { end_time, end_pos } from finish_aap_item() for gap-free chaining.
local function start_simple_aap_work(work_type, chain)
  local parent_track = get_or_create_folder_track(WORK_LOG_NAME, true, true)
  if not parent_track then
    r.ShowMessageBox("Cannot create Work Log track.", "PM Timer", 0); return
  end

  local pos_secs    = (chain and chain.end_pos) or secs_since_midnight()
  local now_clock   = os.time()
  local now_precise = (chain and chain.end_time) or r.time_precise()

  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)
  local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
  local item       = create_work_item(date_track, "", work_type, work_type, pos_secs, now_clock)
  local item_guid  = get_item_guid(item)
  r.Undo_EndBlock("PM: Start AAP session", -1)
  r.UpdateArrange()

  S.mode              = "WORKING"
  S.scene_guid        = ""; S.scene_name = ""
  S.work_type         = work_type
  S.work_item_guid    = item_guid
  S.start_clock       = now_clock
  S.last_start_time   = now_precise
  S.aap_day_name      = ""
  S.aap_item_count    = 0
  S.aap_total_seconds = 0
  S.aap_est_size      = ""

  set_extstate("ACTIVE_WORK_ITEM_GUID",     item_guid)
  set_extstate("ACTIVE_WORK_SCENE_GUID",    "")
  set_extstate("ACTIVE_WORK_SCENE_NAME",    "")
  set_extstate("ACTIVE_WORK_TYPE",          work_type)
  set_extstate("ACTIVE_WORK_START_CLOCK",   tostring(now_clock))
  set_extstate("ACTIVE_WORK_OSTIME_START",  tostring(now_clock))
  set_extstate("ACTIVE_AAP_DAY_NAME",      "")
  set_extstate("ACTIVE_AAP_ITEM_COUNT",    "0")
  set_extstate("ACTIVE_AAP_TOTAL_SECONDS", "0")
  set_extstate("ACTIVE_AAP_EST_SIZE",      "")
end

-- chain (optional): { end_time, end_pos } from finish_aap_item() for gap-free chaining.
local function action_start_aap(chain)
  -- Determine if a folder track is selected → AAP path; else → general work path.
  local stats = get_selected_folder_stats()  -- returns nil if no valid folder selected

  if not stats then
    -- No folder: general pre-production work → show type menu
    gfx.x, gfx.y = 10, 60
    local choice = gfx.showmenu(table.concat(AAP_GENERAL_TYPES, "|"))
    if choice == 0 then return end
    start_simple_aap_work(AAP_GENERAL_TYPES[choice], chain)
    return
  end

  local parent_track = get_or_create_folder_track(WORK_LOG_NAME, true, true)
  if not parent_track then
    r.ShowMessageBox("Cannot create Work Log track.", "PM Timer", 0)
    return
  end

  -- ── Folder selected: show confirmation dialog ─────────────────────────────
  local ok, raw = r.GetUserInputs("AAP Recording Day", 2,
    "Items:,Total Duration (H:M:S.ms):",
    tostring(stats.item_count) .. "," .. fmt_hms_ms(stats.total_seconds))
  if not ok then return end

  local parts = {}
  local n = 0
  for f in (raw .. ","):gmatch("([^,]*),") do
    n = n + 1; parts[n] = f:match("^%s*(.-)%s*$")
  end

  local items_n = tonumber(parts[1])
  if not items_n or items_n < 0 then
    r.ShowMessageBox("Invalid item count.", "PM Timer — AAP", 0); return
  end
  local dur_secs = parse_duration_str(parts[2])
  if not dur_secs then
    r.ShowMessageBox("Invalid duration.\nFormat: H:M:S.ms  (e.g. 3:42:41.996)", "PM Timer — AAP", 0); return
  end

  local aap_item_count = math.floor(items_n)
  local aap_total_secs = dur_secs
  local aap_day_name   = stats.name
  local work_type      = "aap"
  local item_name      = "AAP | " .. stats.name
  local est_size       = seconds_to_size_string(aap_total_secs)

  -- ── Create item ──────────────────────────────────────────────────────────
  local pos_secs    = (chain and chain.end_pos) or secs_since_midnight()
  local now_clock   = os.time()
  local now_precise = (chain and chain.end_time) or r.time_precise()

  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)
  local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
  local item       = create_work_item(date_track, "", item_name, work_type, pos_secs, now_clock)

  -- Fix: create_work_item() locks the item (C_LOCK=1); unlock to write AAP P_EXT, then relock.
  r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
  set_item_ext(item, "AAP_DAY_NAME",      aap_day_name)
  set_item_ext(item, "AAP_ITEM_COUNT",    tostring(aap_item_count))
  set_item_ext(item, "AAP_TOTAL_SECONDS", tostring(aap_total_secs))
  set_item_ext(item, "AAP_EST_SIZE",      est_size)
  r.SetMediaItemInfo_Value(item, "C_LOCK", 1)

  local item_guid = get_item_guid(item)
  r.Undo_EndBlock("PM: Start AAP session", -1)
  r.UpdateArrange()

  -- ── Update state ─────────────────────────────────────────────────────────
  S.mode              = "WORKING"
  S.scene_guid        = ""; S.scene_name = ""
  S.work_type         = work_type
  S.work_item_guid    = item_guid
  S.start_clock       = now_clock
  S.last_start_time   = now_precise
  S.aap_day_name      = aap_day_name
  S.aap_item_count    = aap_item_count
  S.aap_total_seconds = aap_total_secs
  S.aap_est_size      = est_size

  set_extstate("ACTIVE_WORK_ITEM_GUID",     item_guid)
  set_extstate("ACTIVE_WORK_SCENE_GUID",    "")
  set_extstate("ACTIVE_WORK_SCENE_NAME",    "")
  set_extstate("ACTIVE_WORK_TYPE",          work_type)
  set_extstate("ACTIVE_WORK_START_CLOCK",   tostring(now_clock))
  set_extstate("ACTIVE_WORK_OSTIME_START",  tostring(now_clock))
  set_extstate("ACTIVE_AAP_DAY_NAME",      aap_day_name)
  set_extstate("ACTIVE_AAP_ITEM_COUNT",    tostring(aap_item_count))
  set_extstate("ACTIVE_AAP_TOTAL_SECONDS", tostring(aap_total_secs))
  set_extstate("ACTIVE_AAP_EST_SIZE",      est_size)
end

-- ── Scene Metadata ──────────────────────────────────────────────────────────
-- Computes scene stats and writes them into the item's P_NOTES.
-- Note format (first line = scene name, preserved or "(no name)"):
--   Range    : <start> - <end>
--   Length   : <duration>
--   Shots    : <n>
--   Src Cnt  : <n>
--   Src Len  : <duration>
--
-- shots   : Picture Cut items overlapping the scene range
-- src_cnt : EDL folder items attributed to the scene (P_EXT:SCENE_ID or color+pos)
-- src_len : total D_LENGTH of the attributed EDL items (seconds)

local function compute_scene_metadata(scene_item)
  local scene_start = r.GetMediaItemInfo_Value(scene_item, "D_POSITION")
  local scene_len   = r.GetMediaItemInfo_Value(scene_item, "D_LENGTH")
  local scene_end   = scene_start + scene_len
  local scene_color = math.floor(r.GetMediaItemInfo_Value(scene_item, "I_CUSTOMCOLOR"))
  local scene_guid  = r.BR_GetMediaItemGUID(scene_item)

  -- shots: Picture Cut items that overlap the scene range
  local shots = 0
  local pic_track = get_track_by_name(PICTURE_TRACK_NAME)
  if pic_track then
    for i = 0, r.CountTrackMediaItems(pic_track) - 1 do
      local pitem      = r.GetTrackMediaItem(pic_track, i)
      local item_start = r.GetMediaItemInfo_Value(pitem, "D_POSITION")
      local item_end   = item_start + r.GetMediaItemInfo_Value(pitem, "D_LENGTH")
      if item_end > scene_start and item_start < scene_end then shots = shots + 1 end
    end
  end

  -- src_cnt / src_len: EDL items attributed to this scene
  local src_cnt = 0
  local src_len = 0
  for _, t in ipairs(get_folder_children(EDL_FOLDER_NAME)) do
    for i = 0, r.CountTrackMediaItems(t) - 1 do
      local item  = r.GetTrackMediaItem(t, i)
      local ipos  = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local ilen  = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local _, sid = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_ID", "", false)
      local match = (sid == scene_guid)
      if not match and scene_color ~= 0 then
        local icolor = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
        match = (icolor == scene_color) and (ipos >= scene_start) and (ipos < scene_end)
      end
      if match then src_cnt = src_cnt + 1; src_len = src_len + ilen end
    end
  end

  return { shots = shots, src_cnt = src_cnt, src_len = src_len }
end

-- Extract user comment from a log item note: everything after the first blank
-- line (\n\n). Returns "" if no blank line exists.
local function extract_log_comment(note)
  if not note or note == "" then return "" end
  local pos = note:find("\n\n", 1, true)
  if not pos then return "" end
  return note:sub(pos + 2)
end

-- Merge scene metadata block with optional user comment.
local function merge_log_note(metadata, comment)
  if comment and comment ~= "" then
    return metadata .. "\n\n" .. comment
  end
  return metadata
end

-- Pushes scene metadata into all work log items linked to the given scene GUID.
-- Preserves any user comment already in the log item note (text after first blank line).
local function sync_linked_work_item_notes(scene_guid, note)
  if not scene_guid or scene_guid == "" or not note or note == "" then return end
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, j)
      local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
      local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE",  "", false)
      if sg == scene_guid and wt ~= "" then
        local cur_note = r.ULT_GetMediaItemNote(item) or ""
        local comment  = extract_log_comment(cur_note)
        local new_note = merge_log_note(note, comment)
        if cur_note ~= new_note then
          r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
          r.ULT_SetMediaItemNote(item, new_note)
          r.UpdateItemInProject(item)
          r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
        end
      end
    end
  end
end

-- Sync scene metadata into a single log item's note.
-- Reads the scene note from the item's linked scene (P_EXT:SCENE_GUID),
-- preserves any user comment already in the log item note, then writes back
-- using ULT_SetMediaItemNote. No-ops if: not a log item, no GUID, broken link.
local function PM_SyncSceneMetadataToLogItem(item)
  if not item then return end
  local take = r.GetActiveTake(item)
  if not take then return end
  if not r.GetTakeName(take):match("|") then return end  -- not a log item

  local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
  if not sg or sg == "" then return end  -- no scene link; nothing to sync

  local scene_item = find_scene_item_by_guid(sg)
  if not scene_item then return end  -- broken link; skip

  local _, scene_note = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
  if not scene_note or scene_note == "" then return end

  local cur_note = r.ULT_GetMediaItemNote(item) or ""
  local comment  = extract_log_comment(cur_note)
  local new_note = merge_log_note(scene_note, comment)
  if cur_note == new_note then return end

  r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
  r.ULT_SetMediaItemNote(item, new_note)
  r.UpdateItemInProject(item)
  r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
end

-- Sync scene metadata into every log item in the project.
-- Filters by take name containing "|" (PM log item convention).
local function PM_SyncAllLogItems()
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(t) - 1 do
      PM_SyncSceneMetadataToLogItem(r.GetTrackMediaItem(t, j))
    end
  end
end

local function update_scene_note(scene_item)
  if not scene_item then return end

  local scene_start = r.GetMediaItemInfo_Value(scene_item, "D_POSITION")
  local scene_len   = r.GetMediaItemInfo_Value(scene_item, "D_LENGTH")
  local scene_end   = scene_start + scene_len

  local meta       = compute_scene_metadata(scene_item)
  local range_s    = r.format_timestr_pos(scene_start, "", -1)
  local range_e    = r.format_timestr_pos(scene_end,   "", -1)
  local length_tc  = r.format_timestr_len(scene_len,   "", 0, 5)
  local src_len_tc = r.format_timestr_len(meta.src_len, "", 0, 5)

  -- Parse existing note: first line = scene name; rest = other content
  local _, note = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
  local lines = {}
  for line in ((note or "") .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  -- Preserve scene name from first line, or default to "(no name)"
  local scene_name = (lines[1] and lines[1] ~= "") and lines[1] or "(no name)"

  -- Strip all known metadata lines (new pretty format + old key=value format)
  local function is_meta(line)
    return line:match("^Range%s*:")
        or line:match("^Length%s*:")
        or line:match("^Shots%s*:")
        or line:match("^Src Cnt%s*:")
        or line:match("^Src Len%s*:")
        or line:match("^[%w_]+=")
  end

  local other = {}
  for i = 2, #lines do
    if not is_meta(lines[i]) and lines[i] ~= "" then
      table.insert(other, lines[i])
    end
  end

  local parts = {
    scene_name,
    "Range    : " .. range_s .. " - " .. range_e,
    "Length   : " .. length_tc,
    "Shots    : " .. tostring(meta.shots),
    "Src Cnt  : " .. tostring(meta.src_cnt),
    "Src Len  : " .. src_len_tc,
  }
  for _, l in ipairs(other) do table.insert(parts, l) end

  local new_note = table.concat(parts, "\n")
  r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", new_note, true)
  r.UpdateItemInProject(scene_item)

  -- Push updated note to all work log items linked to this scene
  local scene_guid = r.BR_GetMediaItemGUID(scene_item)
  sync_linked_work_item_notes(scene_guid, new_note)
end

-- Public entry point: update metadata for a scene item found by GUID.
local function update_scene_metadata_by_guid(guid)
  if not guid or guid == "" then return end
  local scene_item = get_item_by_guid(guid)
  if scene_item then update_scene_note(scene_item) end
end

-- Returns the P_NOTES of a Scene Cut item to sync into the linked work log item.
-- The work item note mirrors the scene item note verbatim — no recomputation.
local function build_work_item_note(scene_item)
  if not scene_item then return "" end
  local _, note = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
  return note or ""
end

-- Computes project-scope metadata (all scenes, all EDL, all shots) for the
-- note of a Project-scope work item (no scene selected).
local function build_project_scope_note()
  -- Reel length & scene count: sum of all Scene Cut items
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  local scene_cnt = 0
  local reel_len  = 0
  if scene_track then
    for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
      local item = r.GetTrackMediaItem(scene_track, i)
      reel_len  = reel_len + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      scene_cnt = scene_cnt + 1
    end
  end

  -- Shots: total items on Picture Cut track
  local shots = 0
  local pic_track = get_track_by_name(PICTURE_TRACK_NAME)
  if pic_track then
    shots = r.CountTrackMediaItems(pic_track)
  end

  -- EDL source: all items across all EDL folder children
  local src_cnt = 0
  local src_len = 0
  for _, t in ipairs(get_folder_children(EDL_FOLDER_NAME)) do
    for i = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, i)
      src_cnt = src_cnt + 1
      src_len = src_len + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    end
  end

  local reel_tc    = r.format_timestr_len(reel_len, "", 0, 5)
  local src_len_tc = r.format_timestr_len(src_len,  "", 0, 5)

  local scope = get_proj_scope()
  if scope == "" then scope = "Project" end

  return table.concat({
    "Scope    : " .. scope,
    "Scenes   : " .. tostring(scene_cnt),
    "Reel Len : " .. reel_tc,
    "Shots    : " .. tostring(shots),
    "Src Cnt  : " .. tostring(src_cnt),
    "Src Len  : " .. src_len_tc,
  }, "\n")
end

-- Rescans all project-scope work items (WORK_TYPE set, SCENE_GUID empty) and
-- rewrites their note with current project metadata, preserving user comments.
local function PM_SyncProjectScopeNotes()
  local new_meta = build_project_scope_note()
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, j)
      local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE",  "", false)
      local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
      if wt ~= "" and sg == "" then
        local cur_note = r.ULT_GetMediaItemNote(item) or ""
        local comment  = extract_log_comment(cur_note)
        local new_note = merge_log_note(new_meta, comment)
        if cur_note ~= new_note then
          r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
          r.ULT_SetMediaItemNote(item, new_note)
          r.UpdateItemInProject(item)
          r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
        end
      end
    end
  end
end

-- Forward declaration: defined after WL helper functions below.
local mirror_log_item_to_work_log

-- ── Actions ────────────────────────────────────────────────────────────────
local function action_start()
  if S.work_mode == "AAP" then action_start_aap(); return end

  -- 1. Find Scene Cut track (if it exists)
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)

  -- 2. Detect mode: Scene (scene item selected on Scene Cut) vs Project (no selection)
  local sel_scene = nil
  if S.work_mode == "Dialog" and scene_track then
    sel_scene = get_selected_scene_info(scene_track)
  end

  local scene_guid, scene_name = "", ""
  if sel_scene then
    scene_guid = sel_scene.guid
    scene_name = sel_scene.name
  end

  -- 3. Choose work type
  local work_type
  do
    gfx.x, gfx.y = 10, 60
    local work_types = get_work_types_for_mode()
    local choice = gfx.showmenu(table.concat(work_types, "|"))
    if choice == 0 then return end
    work_type = work_types[choice]
    if work_type == "custom" then
      local ok, val = r.GetUserInputs("Custom Work Type", 1, "Work type:", "")
      if not ok or val == "" then return end
      work_type = val
    end
  end

  -- 4. Item name = just work_type (scene metadata goes into P_NOTES)
  local item_name = work_type

  -- 5. Build track structure and create item
  -- Dialog mode: always place items under Scene Cut (create if needed)
  local parent_track = get_or_create_folder_track(SCENE_TRACK_NAME, true)
  if not parent_track then
    r.ShowMessageBox("Cannot create '" .. SCENE_TRACK_NAME .. "' track.", "PM Timer", 0)
    return
  end

  local pos_secs    = secs_since_midnight()
  local now_clock   = os.time()
  local now_precise = r.time_precise()

  -- Update scene metadata in Scene Cut item note and build work item note
  local item_note = ""
  if sel_scene and sel_scene.handle then
    update_scene_note(sel_scene.handle)
    item_note = build_work_item_note(sel_scene.handle)
  else
    item_note = build_project_scope_note()
  end

  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)
  local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
  local item       = create_work_item(date_track, scene_guid, item_name, work_type, pos_secs, now_clock, item_note)
  local item_guid  = get_item_guid(item)
  r.Undo_EndBlock("PM: Start work session", -1)
  r.UpdateArrange()
  mirror_log_item_to_work_log(item)

  -- 6. Update state + ExtState
  S.mode            = "WORKING"
  S.scene_guid      = scene_guid
  S.scene_name      = scene_name
  S.scene_start_tc  = (sel_scene and sel_scene.start_tc) or ""
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

  clear_break_state()  -- starting fresh clears any saved break
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

-- ── AAP finish ─────────────────────────────────────────────────────────────
-- Returns (end_time, end_pos) so callers can chain the next item with no gap.
local function finish_aap_item(end_reason)
  local end_time  = r.time_precise()
  local duration  = math.max(end_time - S.last_start_time, 0)
  local work_secs = math.floor(duration + 0.5)
  local end_pos   = nil

  local item = get_item_by_guid(S.work_item_guid)
  if item then
    local start_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    end_pos = start_pos + duration
    local notes
    if S.aap_item_count > 0 or S.aap_total_seconds > 0 then
      notes = string.format(
        "Items      : %d\nTotal Len  : %s\nEst. Size  : %s\nWork Time  : %s",
        S.aap_item_count, fmt_hms_ms(S.aap_total_seconds),
        S.aap_est_size, fmt_hms(work_secs))
    else
      notes = string.format("Work Time  : %s", fmt_hms(work_secs))
    end
    r.Undo_BeginBlock()
    r.SetMediaItemInfo_Value(item, "C_LOCK",   0)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", duration)
    set_item_ext(item, "END_REASON",       end_reason)
    set_item_ext(item, "END_CLOCK",        tostring(os.time()))
    set_item_ext(item, "DURATION",         tostring(duration))
    set_item_ext(item, "AAP_WORK_SECONDS", tostring(work_secs))
    r.GetSetMediaItemInfo_String(item, "P_NOTES", notes, true)
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
    r.Undo_EndBlock("PM: " .. end_reason .. " AAP session", -1)
    r.UpdateArrange()
  end
  clear_active_extstate()
  reset_state()
  return end_time, end_pos
end

-- Finish current AAP item and immediately start the next one.
-- Menu: [pre-prod | new day | wrap | custom]
--   new day        → folder-based AAP start (select folder in REAPER first)
--   pre-prod / wrap → simple work item, no folder stats needed
--   custom         → ask for name, then simple work item
local AAP_NEW_JOB_MENU = { "pre-prod", "new day", "wrap", "custom" }
local function action_aap_new_job()
  local end_time, end_pos = finish_aap_item("new_job")
  local chain = end_time and { end_time = end_time, end_pos = end_pos } or nil
  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(AAP_NEW_JOB_MENU, "|"))
  if choice == 0 then return end
  local sel = AAP_NEW_JOB_MENU[choice]
  if sel == "new day" then
    action_start_aap(chain)
  elseif sel == "custom" then
    local ok, val = r.GetUserInputs("Custom Work Type", 1, "Work type:", "")
    if not ok or val:match("^%s*$") then return end
    start_simple_aap_work(val:match("^%s*(.-)%s*$"), chain)
  else
    start_simple_aap_work(sel, chain)
  end
end

-- ── Sync work item names ────────────────────────────────────────────────────
-- Rebuilds take names for all Scene Mode work items (those with P_EXT:SCENE_GUID).
-- Project Mode items (no SCENE_GUID) are naturally skipped by the sg ~= "" check.
-- Name format: "work_type" only (scene metadata lives in P_NOTES, not the name)
local function sync_work_item_names()
  local scene_track = nil
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname == SCENE_TRACK_NAME then scene_track = t; break end
  end
  if not scene_track then return end

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
          local item_take = r.GetActiveTake(item)
          if not item_take then item_take = r.AddTakeToMediaItem(item) end
          local cur_name = r.GetTakeName(item_take)

          -- Base name is just the work type (scene metadata is in P_NOTES)
          local base_name = work_type

          -- Apply prefix. If prefix is unavailable (project name not in expected format),
          -- preserve any existing prefix already stored on the item to avoid stripping it.
          local new_name = apply_proj_prefix(base_name)
          if new_name == base_name then  -- prefix unavailable
            if #cur_name > #base_name and cur_name:sub(-#base_name) == base_name then
              new_name = cur_name  -- keep existing prefix
            end
          end

          if cur_name ~= new_name then
            if changed == 0 then r.Undo_BeginBlock() end
            r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
            r.GetSetMediaItemTakeInfo_String(item_take, "P_NAME", new_name, true)
            r.UpdateItemInProject(item)
            r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
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

-- Apply project prefix to ALL work items that are missing it (Project Mode,
-- AAP, and any item sync_work_item_names() doesn't touch).
local function sync_all_prefixes()
  local prefix = get_proj_prefix()
  if prefix == "" then return end
  local changed = 0
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, j)
      local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE", "", false)
      if wt ~= "" then
        local take = r.GetActiveTake(item)
        if take then
          local cur  = r.GetTakeName(take)
          local new  = apply_proj_prefix(cur)
          if new ~= cur then
            if changed == 0 then r.Undo_BeginBlock() end
            r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
            r.GetSetMediaItemTakeInfo_String(take, "P_NAME", new, true)
            r.UpdateItemInProject(item)
            r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
            changed = changed + 1
          end
        end
      end
    end
  end
  if changed > 0 then
    r.Undo_EndBlock("PM: Sync item prefixes", -1)
    r.UpdateArrange()
  end
end

local function action_finish()
  if S.work_mode == "AAP" then finish_aap_item("finish")
  else
    local was_project_scope = (S.scene_guid == "")
    if S.scene_guid ~= "" then update_scene_metadata_by_guid(S.scene_guid) end
    local finishing_guid = S.work_item_guid
    finish_current_item("finish"); sync_work_item_names()
    local log_item = get_item_by_guid(finishing_guid)
    if log_item then PM_SyncSceneMetadataToLogItem(log_item) end
    if was_project_scope then PM_SyncProjectScopeNotes() end
  end
end
local function action_break()
  if S.work_mode == "AAP" then finish_aap_item("break")
  else
    local was_project_scope = (S.scene_guid == "")
    save_break_state()
    if S.scene_guid ~= "" then update_scene_metadata_by_guid(S.scene_guid) end
    finish_current_item("break"); sync_work_item_names()
    if was_project_scope then PM_SyncProjectScopeNotes() end
  end
end

local function action_continue()
  if not BREAK_STATE then return end
  local bs = BREAK_STATE

  local parent_track = get_or_create_folder_track(SCENE_TRACK_NAME, true)
  if not parent_track then
    r.ShowMessageBox("Cannot create '" .. SCENE_TRACK_NAME .. "' track.", "PM Timer", 0)
    return
  end

  local scene_handle = (bs.scene_guid ~= "") and get_item_by_guid(bs.scene_guid) or nil
  local pos_secs    = secs_since_midnight()
  local now_clock   = os.time()
  local now_precise = r.time_precise()

  local item_note = ""
  if scene_handle then
    update_scene_note(scene_handle)
    item_note = build_work_item_note(scene_handle)
  end

  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)
  local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
  local item       = create_work_item(date_track, bs.scene_guid, bs.work_type, bs.work_type, pos_secs, now_clock, item_note)
  local item_guid  = get_item_guid(item)
  r.Undo_EndBlock("PM: Continue work session", -1)
  r.UpdateArrange()
  mirror_log_item_to_work_log(item)

  S.mode            = "WORKING"
  S.scene_guid      = bs.scene_guid
  S.scene_name      = bs.scene_name
  S.scene_start_tc  = bs.scene_start_tc
  S.work_type       = bs.work_type
  S.work_item_guid  = item_guid
  S.start_clock     = now_clock
  S.last_start_time = now_precise

  set_extstate("ACTIVE_WORK_ITEM_GUID",    item_guid)
  set_extstate("ACTIVE_WORK_SCENE_GUID",   bs.scene_guid)
  set_extstate("ACTIVE_WORK_SCENE_NAME",   bs.scene_name)
  set_extstate("ACTIVE_WORK_TYPE",         bs.work_type)
  set_extstate("ACTIVE_WORK_START_CLOCK",  tostring(now_clock))
  set_extstate("ACTIVE_WORK_OSTIME_START", tostring(now_clock))

  clear_break_state()
end

local function action_switch_type()
  if S.mode ~= "WORKING" then return end
  -- Dialog mode: always place items under Scene Cut (create if needed)
  local parent_track = get_or_create_folder_track(SCENE_TRACK_NAME, true)
  if not parent_track then
    r.ShowMessageBox("Cannot create '" .. SCENE_TRACK_NAME .. "' track.", "PM Timer", 0)
    return
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

  -- Item name = just new_type; scene metadata goes into P_NOTES
  local item_name = new_type

  -- Build note from the linked scene item (if any)
  local item_note = ""
  if S.scene_guid ~= "" then
    local scene_item = find_scene_item_by_guid(S.scene_guid)
    if scene_item then
      item_note = build_work_item_note(scene_item)
    else
      r.ShowConsoleMsg("PM Timer: scene item not found for GUID " .. S.scene_guid .. "\n")
    end
  end

  r.Undo_BeginBlock()
  ensure_folder_track(parent_track)
  local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
  local item = create_work_item(date_track, S.scene_guid, item_name, new_type,
    end_pos or secs_since_midnight(), now_clock, item_note)
  local item_guid = get_item_guid(item)
  r.Undo_EndBlock("PM: Switch work type", -1)
  r.UpdateArrange()
  mirror_log_item_to_work_log(item)

  S.mode            = "WORKING"
  S.work_type       = new_type
  S.work_item_guid  = item_guid
  S.start_clock     = now_clock
  S.last_start_time = end_time

  set_extstate("ACTIVE_WORK_ITEM_GUID",    item_guid)
  set_extstate("ACTIVE_WORK_SCENE_GUID",   S.scene_guid)
  set_extstate("ACTIVE_WORK_SCENE_NAME",   S.scene_name)
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

  -- Update new scene's metadata in Scene Cut note and build work item note
  local item_note = ""
  if sel_scene.handle then
    update_scene_note(sel_scene.handle)
    item_note = build_work_item_note(sel_scene.handle)
  end

  -- Item name = just new_type; scene metadata goes into P_NOTES
  local item_name = new_type
  r.Undo_BeginBlock()
  ensure_folder_track(scene_track)
  local date_track = get_or_create_date_track(scene_track, os.date("%Y-%m-%d"))
  local item = create_work_item(date_track, sel_scene.guid, item_name, new_type,
    end_pos or secs_since_midnight(), now_clock, item_note)
  local item_guid = get_item_guid(item)
  r.Undo_EndBlock("PM: Switch scene", -1)
  r.UpdateArrange()
  mirror_log_item_to_work_log(item)

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
  if S.scene_guid ~= "" then update_scene_metadata_by_guid(S.scene_guid) end
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

-- ── Sync to Work Log ────────────────────────────────────────────────────────
-- Mirrors log items from the current dialog project into a global Work Log
-- project (any open project whose filename contains "Work Log").
--
-- Date tracks (YYYY-MM-DD)  → flat tracks of the same name in Work Log project.
-- DurationOnly_Log items     → DurationOnly_Log (folder) > ProjectName (child)
--                              in Work Log project; project name extracted from
--                              the item's prefix ("TheFixer EP04 Dialog | …"
--                              → "TheFixer").
-- Duplicate check: skip if an item with the same position + name already exists.
-- All items in the Work Log project are EMPTY (no media source).

local function find_work_log_project()
  local i = 0
  while true do
    local proj, fn = r.EnumProjects(i)
    if not proj then break end
    local base = (fn:match("([^/\\]+)$") or fn):gsub("%.%a+$", "")
    if base:find("Work Log", 1, true) then return proj end
    i = i + 1
  end
  return nil
end

-- Returns the existing WL item at the given position+name, or nil if not found.
local function find_wl_item(track, pos, name)
  for j = 0, r.CountTrackMediaItems(track) - 1 do
    local item = r.GetTrackMediaItem(track, j)
    if math.abs(r.GetMediaItemInfo_Value(item, "D_POSITION") - pos) < 0.001 then
      local take = r.GetActiveTake(item)
      if take and r.GetTakeName(take) == name then return item end
    end
  end
  return nil
end

-- Mirror src_item onto dst_track in the Work Log project.
-- If an item with the same position + take name already exists, update its
-- note, length, and color instead of creating a duplicate.
-- Uses native P_NOTES (not ULT) so reads/writes work regardless of active project.
-- Returns true if an item was created or updated, false if nothing changed.
local function copy_item_to_wl(src_item, dst_track, src_proj_id)
  local _, src_note = r.GetSetMediaItemInfo_String(src_item, "P_NOTES", "", false)
  local pos         = r.GetMediaItemInfo_Value(src_item, "D_POSITION")
  local len         = r.GetMediaItemInfo_Value(src_item, "D_LENGTH")
  local color       = r.GetMediaItemInfo_Value(src_item, "I_CUSTOMCOLOR")
  local src_take    = r.GetActiveTake(src_item)
  local name        = src_take and r.GetTakeName(src_take) or ""

  local existing = find_wl_item(dst_track, pos, name)
  if existing then
    -- Update mutable fields on the existing WL item.
    local _, cur_note = r.GetSetMediaItemInfo_String(existing, "P_NOTES", "", false)
    local cur_len     = r.GetMediaItemInfo_Value(existing, "D_LENGTH")
    local cur_color   = r.GetMediaItemInfo_Value(existing, "I_CUSTOMCOLOR")
    if cur_note == src_note and cur_len == len and cur_color == color then
      return false  -- nothing changed
    end
    r.SetMediaItemInfo_Value(existing, "D_LENGTH",      len)
    r.SetMediaItemInfo_Value(existing, "I_CUSTOMCOLOR", color)
    if src_note and src_note ~= "" then
      r.GetSetMediaItemInfo_String(existing, "P_NOTES", src_note, true)
    end
    r.UpdateItemInProject(existing)
    return true
  end

  -- No existing item — create a new one.
  local new_item = r.AddMediaItemToTrack(dst_track)
  if not new_item then return false end

  r.SetMediaItemInfo_Value(new_item, "D_POSITION",    pos)
  r.SetMediaItemInfo_Value(new_item, "D_LENGTH",      len)
  r.SetMediaItemInfo_Value(new_item, "I_CUSTOMCOLOR", color)

  local new_take = r.AddTakeToMediaItem(new_item)
  if new_take then
    r.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", name, true)
  end

  if src_note and src_note ~= "" then
    r.GetSetMediaItemInfo_String(new_item, "P_NOTES", src_note, true)
  end

  if src_proj_id and src_proj_id ~= "" then
    r.GetSetMediaItemInfo_String(new_item, "P_EXT:WL_SRC_PROJ", src_proj_id, true)
  end
  r.UpdateItemInProject(new_item)
  return true
end

-- Remove WL items that were tagged with src_proj_id but no longer exist in source.
-- src_set is { ["%.3f_pos|name"] = true } built from all current source items.
-- Returns the number of items removed.
local function cleanup_wl_orphans(wl_proj, src_proj_id, src_set)
  local to_delete = {}
  for i = 0, r.CountTracks(wl_proj) - 1 do
    local t = r.GetTrack(wl_proj, i)
    for j = r.CountTrackMediaItems(t) - 1, 0, -1 do
      local item = r.GetTrackMediaItem(t, j)
      local _, tagged = r.GetSetMediaItemInfo_String(item, "P_EXT:WL_SRC_PROJ", "", false)
      if tagged == src_proj_id then
        local pos   = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local itake = r.GetActiveTake(item)
        local iname = itake and r.GetTakeName(itake) or ""
        local key   = string.format("%.3f|%s", pos, iname)
        if not src_set[key] then
          table.insert(to_delete, item)
        end
      end
    end
  end
  for _, item in ipairs(to_delete) do
    r.DeleteTrackMediaItem(r.GetMediaItemTrack(item), item)
  end
  return #to_delete
end

-- Find or create a flat (non-folder) track named `name` at the end of wl_proj.
local function get_or_create_wl_flat_track(wl_proj, name, src_proj)
  local t = find_track_in_proj(wl_proj, name)
  if t then return t end
  r.SelectProjectInstance(wl_proj)
  local n = r.CountTracks(wl_proj)
  r.InsertTrackAtIndex(n, true)
  t = r.GetTrack(wl_proj, n)
  r.GetSetMediaTrackInfo_String(t, "P_NAME", name, true)
  r.SelectProjectInstance(src_proj)
  return t
end

-- Find or create the structure: DurationOnly_Log (folder) → proj_name (child)
-- in wl_proj. Returns the child track.
local function get_or_create_wl_dur_proj_track(wl_proj, proj_name, src_proj)
  -- 1. Find or create DurationOnly_Log folder track
  local dur_log = find_track_in_proj(wl_proj, DURATION_LOG_NAME)
  if not dur_log then
    r.SelectProjectInstance(wl_proj)
    local n = r.CountTracks(wl_proj)
    r.InsertTrackAtIndex(n, true)
    dur_log = r.GetTrack(wl_proj, n)
    r.GetSetMediaTrackInfo_String(dur_log, "P_NAME", DURATION_LOG_NAME, true)
    r.SetMediaTrackInfo_Value(dur_log, "I_FOLDERDEPTH", 1)
    r.SelectProjectInstance(src_proj)
  elseif r.GetMediaTrackInfo_Value(dur_log, "I_FOLDERDEPTH") ~= 1 then
    r.SetMediaTrackInfo_Value(dur_log, "I_FOLDERDEPTH", 1)
  end

  -- 2. Scan DurationOnly_Log's children for proj_name
  local dur_log_num    = math.floor(r.GetMediaTrackInfo_Value(dur_log, "IP_TRACKNUMBER"))
  local wl_total       = r.CountTracks(wl_proj)
  local depth          = 1
  local last_child_idx = -1

  for i = dur_log_num, wl_total - 1 do
    local t        = r.GetTrack(wl_proj, i)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)
    if tname == proj_name then return t end
    last_child_idx = i
    depth = depth + fd
    if depth <= 0 then break end
  end

  -- 3. Insert new child track for proj_name
  r.SelectProjectInstance(wl_proj)
  local insert_at
  if last_child_idx < 0 then
    insert_at = dur_log_num          -- first child: right after DurationOnly_Log
  else
    r.SetMediaTrackInfo_Value(r.GetTrack(wl_proj, last_child_idx), "I_FOLDERDEPTH", 0)
    insert_at = last_child_idx + 1
  end
  r.InsertTrackAtIndex(insert_at, true)
  local new_t = r.GetTrack(wl_proj, insert_at)
  r.GetSetMediaTrackInfo_String(new_t, "P_NAME", proj_name, true)
  r.SetMediaTrackInfo_Value(new_t, "I_FOLDERDEPTH", -1)
  r.SelectProjectInstance(src_proj)
  return new_t
end

-- Extract the project name from a work-item take name that has the PM prefix.
-- "TheFixer EP04 Dialog | double_check" → "TheFixer"
-- Returns nil for scene-mode names ("4-14 麵包店 (04:04:28:12) | editing")
-- or names without a recognizable prefix.
local function extract_proj_from_name(name)
  local prefix_part = name:match("^(.-)%s*|")
  if not prefix_part or prefix_part == "" then return nil end
  -- Scene-mode names contain a timecode "(HH:MM:SS:FF)" → skip
  if prefix_part:find("%(%d+:%d+:%d+:%d+%)") then return nil end
  return prefix_part:match("^(%S+)")
end

local function action_sync_work_log()
  local src_proj = r.EnumProjects(-1)
  local wl_proj  = find_work_log_project()
  if not wl_proj then
    r.ShowMessageBox(
      "Work Log project not found.\n\n"
      .. "Open a project whose filename contains 'Work Log' in REAPER, then try again.",
      "Sync to Work Log", 0)
    return
  end
  if src_proj == wl_proj then
    r.ShowMessageBox(
      "Current project is the Work Log project.\nSwitch to your dialog project first.",
      "Sync to Work Log", 0)
    return
  end

  local scene_track = find_track_in_proj(src_proj, SCENE_TRACK_NAME)
  if not scene_track then
    r.ShowMessageBox(
      "No '" .. SCENE_TRACK_NAME .. "' track found in current project.\nNothing to sync.",
      "Sync to Work Log", 0)
    return
  end

  local sc_num     = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local total      = r.CountTracks(src_proj)
  local _, src_fn  = r.EnumProjects(-1)
  local src_proj_id = (src_fn or ""):match("([^/\\]+)$") or (src_fn or "")

  -- Build set of all current source items (pos + name) for orphan cleanup.
  local src_set = {}
  do
    local d = 1
    for i = sc_num, total - 1 do
      local t        = r.GetTrack(src_proj, i)
      local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
      local _, tname = r.GetTrackName(t)
      if tname:match(DATE_PAT) or tname == DURATION_LOG_NAME then
        for j = 0, r.CountTrackMediaItems(t) - 1 do
          local item  = r.GetTrackMediaItem(t, j)
          local pos   = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local itake = r.GetActiveTake(item)
          local iname = itake and r.GetTakeName(itake) or ""
          src_set[string.format("%.3f|%s", pos, iname)] = true
        end
      end
      d = d + fd
      if d <= 0 then break end
    end
  end

  local depth = 1
  local added = 0

  r.Undo_BeginBlock2(wl_proj)

  for i = sc_num, total - 1 do
    local t        = r.GetTrack(src_proj, i)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)

    if tname:match(DATE_PAT) then
      -- ── Date track → flat track in Work Log ───────────────────────────────
      local dst = get_or_create_wl_flat_track(wl_proj, tname, src_proj)
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        if copy_item_to_wl(r.GetTrackMediaItem(t, j), dst, src_proj_id) then
          added = added + 1
        end
      end

    elseif tname == DURATION_LOG_NAME then
      -- ── DurationOnly_Log → DurationOnly_Log > ProjectName in Work Log ────
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        local item      = r.GetTrackMediaItem(t, j)
        local item_take = r.GetActiveTake(item)
        local iname     = item_take and r.GetTakeName(item_take) or ""
        local proj_name = extract_proj_from_name(iname)
        if proj_name then
          local dst = get_or_create_wl_dur_proj_track(wl_proj, proj_name, src_proj)
          if copy_item_to_wl(item, dst, src_proj_id) then
            added = added + 1
          end
        end
      end
    end

    depth = depth + fd
    if depth <= 0 then break end
  end

  local removed = cleanup_wl_orphans(wl_proj, src_proj_id, src_set)

  r.Undo_EndBlock2(wl_proj, "PM: Sync to Work Log", -1)

  local parts = {}
  if added   > 0 then table.insert(parts, string.format("%d added",   added))   end
  if removed > 0 then table.insert(parts, string.format("%d removed", removed)) end
  local msg = #parts > 0
    and string.format("Work Log synced: %s.", table.concat(parts, ", "))
    or  "Work Log already up to date."
  r.ShowMessageBox(msg, "Sync to Work Log", 0)
end

-- ── Auto-mirror to Work Log ─────────────────────────────────────────────────
-- After creating a new log item, silently copy it to the open Work Log project.
-- Skips if: Work Log project not open, current project IS the Work Log,
-- item is not a log item (take name lacks "|"), or no suitable destination track.
mirror_log_item_to_work_log = function(src_item)
  if not src_item then return end
  local take = r.GetActiveTake(src_item)
  if not take then return end
  if not r.GetTakeName(take):match("|") then return end

  local src_proj = r.EnumProjects(-1)
  local wl_proj  = find_work_log_project()
  if not wl_proj or wl_proj == src_proj then return end

  local _, src_fn   = r.EnumProjects(-1)
  local src_proj_id = (src_fn or ""):match("([^/\\]+)$") or (src_fn or "")

  local item_track = r.GetMediaItemTrack(src_item)
  local _, tname   = r.GetTrackName(item_track)
  local dst_track

  if tname:match(DATE_PAT) then
    dst_track = get_or_create_wl_flat_track(wl_proj, tname, src_proj)
  elseif tname == DURATION_LOG_NAME then
    local iname     = r.GetTakeName(take)
    local proj_name = extract_proj_from_name(iname)
    if proj_name then
      dst_track = get_or_create_wl_dur_proj_track(wl_proj, proj_name, src_proj)
    end
  end

  if not dst_track then return end

  -- Switch to the WL project so AddMediaItemToTrack and ULT note calls succeed,
  -- then restore the source project.
  r.SelectProjectInstance(wl_proj)
  local did_create = copy_item_to_wl(src_item, dst_track, src_proj_id)
  r.SelectProjectInstance(src_proj)

  if did_create then
    r.UpdateArrange()
  end
end

-- ── Fix Duration ────────────────────────────────────────────────────────────
-- For each selected REAPER item that has P_EXT:WORK_TYPE set,
-- overwrite P_EXT:DURATION with the item's current D_LENGTH.
-- Use this after manually stretching a work item (e.g. after a crash recovery).
local function action_fix_duration()
  local count = r.CountSelectedMediaItems(0)
  if count == 0 then
    r.ShowMessageBox(
      "No items selected.\nSelect the work item(s) you stretched, then run Fix Duration.",
      "Fix Duration", 0)
    return
  end

  local fixed   = 0
  local skipped = 0

  r.Undo_BeginBlock()
  for i = 0, count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE", "", false)
    if wt ~= "" then
      local d_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
      set_item_ext(item, "DURATION", tostring(d_len))
      r.UpdateItemInProject(item)
      r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
      fixed = fixed + 1
    else
      skipped = skipped + 1
    end
  end
  r.Undo_EndBlock("PM: Fix Duration from item length", -1)
  r.UpdateArrange()

  local msg = string.format("Fixed %d item(s).", fixed)
  if skipped > 0 then
    msg = msg .. string.format("\nSkipped %d item(s) — no WORK_TYPE metadata.", skipped)
  end
  r.ShowMessageBox(msg, "Fix Duration", 0)
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

  -- Find Scene Cut (if it exists); detect Scene vs Project mode
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  local sel_scene = nil
  if S.work_mode == "Dialog" and scene_track then
    sel_scene = get_selected_scene_info(scene_track)
  end

  -- Dialog mode requires a scene selection
  if S.work_mode == "Dialog" and not sel_scene then
    r.ShowMessageBox("Please select a Scene Cut item first.", "Add Record", 0)
    return
  end

  local scene_guid = ""
  if sel_scene then
    scene_guid = sel_scene.guid
  end

  -- Dialog mode: always place items under Scene Cut (create if needed)
  local parent_track = get_or_create_folder_track(SCENE_TRACK_NAME, true)
  if not parent_track then
    r.ShowMessageBox("Cannot create '" .. SCENE_TRACK_NAME .. "' track.", "Add Record", 0)
    return
  end

  -- Work type via menu
  gfx.x, gfx.y = 10, 60
  local work_types = get_work_types_for_mode()
  local choice = gfx.showmenu(table.concat(work_types, "|"))
  if choice == 0 then return end
  local work_type = work_types[choice]
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

  -- Item name = just work_type (scene metadata goes into P_NOTES)
  local item_name = apply_proj_prefix(work_type)

  -- Build scene metadata note (if scene is linked)
  local item_note = ""
  if sel_scene and sel_scene.handle then
    item_note = build_work_item_note(sel_scene.handle)
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
    local _task = get_proj_task()
    if _task ~= "" then set_item_ext(item, "TASK", _task) end
    set_item_ext(item, "START_CLOCK", start_str)
    set_item_ext(item, "END_CLOCK",   end_str)
    if item_note ~= "" then
      r.ULT_SetMediaItemNote(item, item_note)
    end
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
    r.Undo_EndBlock("PM: Add Record (timed)", -1)
    mirror_log_item_to_work_log(item)

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
    local _task = get_proj_task()
    if _task ~= "" then set_item_ext(item, "TASK", _task) end
    if item_note ~= "" then
      r.ULT_SetMediaItemNote(item, item_note)
    end
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)  -- lock after creation
    r.Undo_EndBlock("PM: Add Record (duration-only)", -1)
    mirror_log_item_to_work_log(item)
  end

  r.UpdateArrange()
  sync_work_item_names()
  sync_all_prefixes()
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
  local aap_working = (S.work_mode == "AAP" and S.mode == "WORKING")

  gfx.setfont(1)
  gfx.set(0.15, 0.15, 0.15, 1)
  gfx.rect(0, 0, WIN_W, WIN_H, 1)
  BTN = {}

  -- ── Info rows ───────────────────────────────────────────────────────────
  do
    -- 2-row display: in AAP mode show "Day:" instead of "Scene:"
    -- When IDLE with a saved break state, show the paused session's context.
    local scene_label
    local name_disp
    local type_src  = S.work_type
    local bs_idle   = (S.mode == "IDLE") and BREAK_STATE or nil
    if S.work_mode == "AAP" then
      scene_label = "  |  Day: "
      name_disp   = S.aap_day_name ~= "" and S.aap_day_name or "---"
    else
      scene_label = "  |  Scene: "
      if bs_idle then
        name_disp = bs_idle.scene_name
        type_src  = bs_idle.work_type
      else
        name_disp = S.scene_name
      end
    end
    local on_break = bs_idle ~= nil
    if #name_disp > 18 then name_disp = name_disp:sub(1, 17) .. "..." end
    local type_disp  = (type_src ~= "") and type_src or "---"
    if #type_disp > 10 then type_disp = type_disp:sub(1, 9) .. "..." end
    local mode_disp  = (S.work_mode ~= "") and S.work_mode or "Dialog"
    local start_disp = (S.mode == "WORKING") and fmt_clock(S.start_clock) or "--:--:--"

    gfx.setfont(3)
    gfx.x, gfx.y = 10, 12

    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("Mode: ")
    gfx.set(1,   1,   1,   1); gfx.drawstr(mode_disp)
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr(scene_label)
    gfx.set(1,   1,   1,   1); gfx.drawstr(name_disp)
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Type: ")
    gfx.set(1,   1,   1,   1); gfx.drawstr(type_disp)
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Status: ")
    if S.mode == "WORKING" then
      gfx.set(0.2, 1.0, 0.2, 1); gfx.drawstr("WORKING")
    elseif on_break then
      gfx.set(1.0, 0.7, 0.2, 1); gfx.drawstr("ON BREAK")
    else
      gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("IDLE")
    end

    gfx.x, gfx.y = 10, 28
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("Start: ")
    gfx.set(1,   1,   1,   1); gfx.drawstr(start_disp)
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Elapsed: ")
    gfx.set(0.2, 0.8, 1.0, 1); gfx.drawstr(fmt_hms(elapsed_secs()))

    sep(44)
  end

  -- ── Horizontal buttons ──────────────────────────────────────────────────
  local btn_w   = 129
  local btn_h   = 40
  local btn_y   = 58
  local btn_gap = 8
  local btn_x0  = 10

  local dlg_working = (S.mode == "WORKING" and not aap_working)

  gfx.setfont(1)
  local function btn_x(i) return btn_x0 + (i - 1) * (btn_w + btn_gap) end

  -- Use table.insert so BTN is always a dense array (ipairs stops at first nil gap).
  local function add_btn(i, label, action)
    table.insert(BTN, { rect = draw_btn(btn_x(i), btn_y, btn_w, btn_h, label), action = action })
  end

  if aap_working then
    add_btn(1, "New Job",  action_aap_new_job)
    add_btn(2, "Break",    action_break)
    add_btn(3, "Finish",   action_finish)
    draw_btn_disabled(btn_x(4), btn_y, btn_w, btn_h, "")
  elseif dlg_working then
    add_btn(1, "Switch Scene", action_switch_scene)
    add_btn(2, "Switch Type",  action_switch_type)
    add_btn(3, "Break",        action_break)
    add_btn(4, "Finish",       action_finish)
  elseif BREAK_STATE then
    add_btn(1, "Continue",   action_continue)
    add_btn(2, "Start New",  action_start)
    add_btn(3, "Mode",       action_switch_mode)
    add_btn(4, "Add Record", action_add_record)
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

  -- Right click: Dock / Undock + Fix Duration
  local rb = (gfx.mouse_cap & 2) ~= 0 and 1 or 0
  if rb == 1 and mouse_r_prev == 0 then
    local is_docked = cur_dock ~= 0
    local dock_label = is_docked and "Undock window" or "Dock window"
    local choice = gfx.showmenu(dock_label .. "|Fix Duration from item length|Fix Item Prefixes|Sync to Work Log|Update Scene Metadata")
    if choice == 1 then
      gfx.dock(is_docked and 0 or 1)
      cur_dock = gfx.dock(-1)
      r.SetExtState(NS, "DOCK_STATE", tostring(cur_dock), true)
      last_dock = cur_dock
    elseif choice == 2 then
      action_fix_duration()
    elseif choice == 3 then
      sync_work_item_names()
      sync_all_prefixes()
      r.ShowMessageBox("Item prefixes synced.", "PM Timer", 0)
    elseif choice == 4 then
      action_sync_work_log()
    elseif choice == 5 then
      local scene_track = get_track_by_name(SCENE_TRACK_NAME)
      if not scene_track then
        r.ShowMessageBox("No Scene Cut track found.", "PM Timer", 0)
      else
        local updated = 0
        for i = 0, r.CountSelectedMediaItems(0) - 1 do
          local item = r.GetSelectedMediaItem(0, i)
          if r.GetMediaItemTrack(item) == scene_track then
            update_scene_note(item)
            updated = updated + 1
          end
        end
        if updated > 0 then
          r.ShowMessageBox(updated .. " scene" .. (updated > 1 and "s" or "") .. " updated.", "PM Timer", 0)
        else
          r.ShowMessageBox("No Scene Cut item selected.\nSelect a scene in the Scene Cut track first.", "PM Timer", 0)
        end
      end
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
-- Called at startup. If an ACTIVE_WORK_ITEM_GUID exists, a session was
-- interrupted (crash / unexpected REAPER close). Shows a dialog:
--   Yes    = Resume  — continue timing from original start
--   No     = Finish  — save item with D_LENGTH from last heartbeat
--   Cancel = Discard — mark item as aborted, clear state
local function try_recover()
  S.work_mode = get_work_mode()
  local guid = get_extstate("ACTIVE_WORK_ITEM_GUID")
  if not guid then return end

  local item = get_item_by_guid(guid)
  if not item then
    clear_active_extstate(); return
  end

  -- Restore state so the dialog can show scene/type info
  S.work_item_guid = guid
  S.scene_guid     = get_extstate("ACTIVE_WORK_SCENE_GUID") or ""
  S.scene_name     = get_extstate("ACTIVE_WORK_SCENE_NAME") or ""
  S.scene_start_tc = ""
  S.work_type      = get_extstate("ACTIVE_WORK_TYPE")       or ""
  S.start_clock    = tonumber(get_extstate("ACTIVE_WORK_START_CLOCK")) or os.time()

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

  if S.work_mode == "AAP" then
    S.aap_day_name      = get_extstate("ACTIVE_AAP_DAY_NAME")           or ""
    S.aap_item_count    = tonumber(get_extstate("ACTIVE_AAP_ITEM_COUNT")) or 0
    S.aap_total_seconds = tonumber(get_extstate("ACTIVE_AAP_TOTAL_SECONDS")) or 0
    S.aap_est_size      = get_extstate("ACTIVE_AAP_EST_SIZE")           or ""
  end

  -- D_LENGTH was kept current by heartbeat — use it as the recorded duration
  local recorded_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local scene_info   = (S.scene_name ~= "") and (S.scene_name .. " | ") or ""
  local msg = string.format(
    "Session was interrupted (crash / unexpected close):\n%s%s\n\n"
    .. "Recorded so far: ~%s\n\n"
    .. "Yes    = Resume timer\n"
    .. "No     = Finish & save (keep recorded time)\n"
    .. "Cancel = Discard (mark as aborted)",
    scene_info, S.work_type, fmt_hms(recorded_len))

  local ret = r.ShowMessageBox(msg, "PM Timer — Recover Interrupted Session", 3)

  if ret == 6 then
    -- ── Resume: restore WORKING state and continue ─────────────────────────
    S.mode = "WORKING"

  elseif ret == 7 then
    -- ── Finish: keep D_LENGTH from heartbeat, add end metadata ────────────
    r.Undo_BeginBlock()
    r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
    -- D_LENGTH already correct from heartbeat; just tag it
    set_item_ext(item, "END_REASON", "interrupted_finish")
    set_item_ext(item, "END_CLOCK",  tostring(os.time()))
    set_item_ext(item, "DURATION",   tostring(recorded_len))
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
    r.Undo_EndBlock("PM: Finish interrupted session", -1)
    clear_active_extstate()
    reset_state()

  else
    -- ── Discard: mark aborted, clear state ────────────────────────────────
    r.Undo_BeginBlock()
    r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
    set_item_ext(item, "END_REASON", "aborted")
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
    r.Undo_EndBlock("PM: Abort interrupted session", -1)
    clear_active_extstate()
    reset_state()
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

  -- Detect project change: close/reopen without REAPER restart, or late project
  -- load (script docked → runs before project finishes loading).
  local cur_proj_id = get_proj_identity()
  if cur_proj_id ~= last_proj_identity then
    last_proj_identity = cur_proj_id
    reset_state()
    try_recover()
    sync_work_item_names()
    sync_all_prefixes()
    sync_work_item_colors()
    PM_SyncAllLogItems()
    PM_SyncProjectScopeNotes()
    draw()
    last_draw_time = r.time_precise()
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

  -- Heartbeat: silently keep D_LENGTH current every 60 s so that if REAPER
  -- crashes the item retains approximate timing for crash recovery.
  if S.mode == "WORKING" and (now - last_heartbeat_time) >= HEARTBEAT_INTERVAL then
    local hb_item = get_item_by_guid(S.work_item_guid)
    if hb_item then
      local elapsed = math.max(0, r.time_precise() - S.last_start_time)
      r.SetMediaItemInfo_Value(hb_item, "C_LOCK",   0)
      r.SetMediaItemInfo_Value(hb_item, "D_LENGTH", elapsed)
      r.UpdateItemInProject(hb_item)
      r.SetMediaItemInfo_Value(hb_item, "C_LOCK",   1)
    end
    last_heartbeat_time = now
  end

  r.defer(loop)
end

-- ── Entry ──────────────────────────────────────────────────────────────────
load_break_state()
try_recover()
last_proj_identity = get_proj_identity()  -- lock in current project after recovery
gfx.init("hsuanice PM Timer", WIN_W, WIN_H, cur_dock, win_x, win_y)
setup_fonts()
draw()
sync_work_item_names()
sync_all_prefixes()
sync_work_item_colors()
PM_SyncAllLogItems()
PM_SyncProjectScopeNotes()
last_draw_time = r.time_precise()
r.defer(loop)
