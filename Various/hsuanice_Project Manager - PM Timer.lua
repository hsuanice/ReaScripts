--[[
@description Project Manager - PM Timer: scene-aware work timer
@version 26.1028.1303pre1
@author hsuanice
@noindex  (kept in the repository as a backup; Project Manager is not offered on ReaPack for now)
@changelog
  - New: right-click > Rename Project... - a new official name for this project; the old name becomes an older spelling, so other projects saved with it follow. A name that is already another project offers to merge the two.
  - New: right-click > Merge Projects... - pick another project in the list; its name and older spellings become spellings of this one. Both update this project's item names; Work Log items keep theirs (PM Insight reads the list).
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
--]]
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
  ["pre-prod"]      = {255, 140, 0},     -- Orange (legacy)
  ["pre-production"] = {255, 140, 0},     -- Orange
  wrap             = {100, 220, 255},   -- Light blue
  ["mic select"]   = {150, 80, 255},    -- Purple
  check            = {0, 150, 130},     -- Teal
  scene            = {255, 170, 80},    -- Light orange
  ME               = {80, 140, 255},    -- Sky blue
  PAN              = {255, 120, 170},   -- Pink
  ["ME+PAN"]       = {140, 200, 80},    -- Olive green
}
-- Work types without an entry above (saved custom types...)
-- get an automatic color derived from their name: same name = same color.

-- ── Constants ──────────────────────────────────────────────────────────────
local NS                = "hsuanice_PM"
local SCENE_TRACK_NAME  = "Scene Cut"
local WORK_LOG_NAME     = "Work Log"
local DURATION_LOG_NAME = "DurationOnly_Log"
local WIN_W, WIN_H           = 560, 92
local BYTES_PER_SECOND       = 144000
local BYTES_PER_GB           = 1000000000
local WORK_TYPES          = { "pre-production", "wrap" }
local MODE_TYPES          = { "Dialog", "AAP", "Conform" }
local AAP_GENERAL_TYPES   = { "pre-production", "wrap", "custom" }   -- used when no folder is selected in AAP mode
local AAP_FOLDER_DEFAULT_TYPE = "aap"
local DATE_PAT            = "^%d%d%d%d%-%d%d%-%d%d$"  -- matches YYYY-MM-DD
local HEARTBEAT_INTERVAL  = 60   -- seconds between silent D_LENGTH updates
-- Original (ISO) source folder: "ISO"; older projects use "EDL" (fallback)
local ISO_FOLDER_NAMES    = { "ISO", "EDL" }
-- Later stages of the dialog source, after Mic Select and after Editing
-- (scene note lines "Sel Len" / "Edit Len"; only when the folder exists)
local MIC_SELECTED_FOLDER = "Mic Selected"
local EDITED_FOLDER       = "Edited"
local PICTURE_TRACK_NAME  = "Picture Cut"
local auto_sync_work_log_if_open

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
local BREAK_STATE = nil  -- set by action_break; includes mode/work type and optional AAP stats

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
    return { "mic select", "editing", "denoise", "scene", "ME", "PAN", "ME+PAN", "check", "custom" }
  end
  if S.work_mode == "Conform" then
    return { "conform", "picture cut", "subtitle", "custom" }
  end
  return WORK_TYPES
end

-- ── Saved custom work types ─────────────────────────────────────────────────
-- Every name typed via "custom" is remembered per work mode (global ExtState,
-- shared by all projects) and offered in the menu next time, so names stay
-- consistent. "remove custom..." deletes a saved name.
local CUSTOM_REMOVE_LABEL = "remove custom..."

local function custom_types_key()
  return "CUSTOM_TYPES_" .. ((S.work_mode ~= "" and S.work_mode) or "Dialog")
end

local function get_custom_types()
  local list = {}
  for name in (r.GetExtState(NS, custom_types_key()) or ""):gmatch("[^|]+") do
    list[#list + 1] = name
  end
  return list
end

local function set_custom_types(list)
  r.SetExtState(NS, custom_types_key(), table.concat(list, "|"), true)
end

-- gfx.showmenu treats "|" as a separator and a leading ! # > < as flags.
local function clean_custom_name(name)
  name = (name or ""):gsub("|", " "):gsub("^[%s!#<>]+", ""):gsub("%s+$", "")
  return name
end

-- Shows the work type menu for `builtins` (a list ending with "custom"), with
-- the saved custom types inserted before "custom". Returns the chosen type,
-- or nil when cancelled.
local function choose_work_type(builtins)
  local saved = get_custom_types()
  local items, parts = {}, {}
  for _, t in ipairs(builtins) do
    if t == "custom" then
      if #saved > 0 then
        parts[#parts] = parts[#parts] .. "|"   -- separator before saved types
        for _, c in ipairs(saved) do
          items[#items + 1] = c; parts[#parts + 1] = c
        end
        parts[#parts] = parts[#parts] .. "|"   -- separator after saved types
      end
    end
    items[#items + 1] = t; parts[#parts + 1] = t
  end
  if #saved > 0 then
    items[#items + 1] = CUSTOM_REMOVE_LABEL; parts[#parts + 1] = CUSTOM_REMOVE_LABEL
  end

  gfx.x, gfx.y = 10, 60
  local choice = gfx.showmenu(table.concat(parts, "|"))
  local picked = items[choice]
  if not picked then return nil end

  if picked == CUSTOM_REMOVE_LABEL then
    gfx.x, gfx.y = 10, 60
    local rm = gfx.showmenu("#Remove saved custom type:||" .. table.concat(saved, "|"))
    if rm >= 2 and saved[rm - 1] then
      table.remove(saved, rm - 1)
      set_custom_types(saved)
    end
    return nil
  end

  if picked == "custom" then
    local ok, val = r.GetUserInputs("Custom Work Type", 1, "Work type:,extrawidth=100", "")
    if not ok then return nil end
    val = clean_custom_name(val)
    if val == "" then return nil end
    local known = false
    for _, t in ipairs(builtins) do if t == val then known = true end end
    for _, c in ipairs(saved) do if c == val then known = true end end
    if not known then
      saved[#saved + 1] = val
      set_custom_types(saved)
    end
    return val
  end

  return picked
end

local function reset_state()
  S.mode = "IDLE"; S.scene_guid = ""; S.scene_name = ""
  S.scene_start_tc = ""
  S.work_type = ""; S.work_item_guid = ""
  S.start_clock = 0; S.last_start_time = 0
  S.aap_day_name = ""; S.aap_item_count = 0
  S.aap_total_seconds = 0; S.aap_est_size = ""
end

local function is_aap_work_type(work_type)
  return work_type == "pre-production"
      or work_type == "wrap"
    or work_type == "custom"
      or work_type == "aap" -- legacy data compatibility
end

-- ── Break state persistence ────────────────────────────────────────────────
local function save_break_state()
  BREAK_STATE = {
    work_mode    = S.work_mode,
    scene_guid    = S.scene_guid,
    scene_name    = S.scene_name,
    scene_start_tc = S.scene_start_tc,
    work_type     = S.work_type,
    aap_day_name      = S.aap_day_name,
    aap_item_count    = S.aap_item_count,
    aap_total_seconds = S.aap_total_seconds,
    aap_est_size      = S.aap_est_size,
  }
  set_extstate("BREAK_WORK_MODE", S.work_mode)
  set_extstate("BREAK_SCENE_GUID", S.scene_guid)
  set_extstate("BREAK_SCENE_NAME", S.scene_name)
  set_extstate("BREAK_SCENE_TC",   S.scene_start_tc)
  set_extstate("BREAK_WORK_TYPE",  S.work_type)
  set_extstate("BREAK_AAP_DAY_NAME",      S.aap_day_name)
  set_extstate("BREAK_AAP_ITEM_COUNT",    tostring(S.aap_item_count or 0))
  set_extstate("BREAK_AAP_TOTAL_SECONDS", tostring(S.aap_total_seconds or 0))
  set_extstate("BREAK_AAP_EST_SIZE",      S.aap_est_size)
end

local function load_break_state()
  local wtype = get_extstate("BREAK_WORK_TYPE")
  if not wtype then return end
  BREAK_STATE = {
    work_mode      = get_extstate("BREAK_WORK_MODE") or "Dialog",
    scene_guid     = get_extstate("BREAK_SCENE_GUID") or "",
    scene_name     = get_extstate("BREAK_SCENE_NAME") or "",
    scene_start_tc = get_extstate("BREAK_SCENE_TC")   or "",
    work_type      = wtype,
    aap_day_name      = get_extstate("BREAK_AAP_DAY_NAME") or "",
    aap_item_count    = tonumber(get_extstate("BREAK_AAP_ITEM_COUNT")) or 0,
    aap_total_seconds = tonumber(get_extstate("BREAK_AAP_TOTAL_SECONDS")) or 0,
    aap_est_size      = get_extstate("BREAK_AAP_EST_SIZE") or "",
  }
end

local function clear_break_state()
  BREAK_STATE = nil
  set_extstate("BREAK_WORK_MODE", "")
  set_extstate("BREAK_SCENE_GUID", "")
  set_extstate("BREAK_SCENE_NAME", "")
  set_extstate("BREAK_SCENE_TC",   "")
  set_extstate("BREAK_WORK_TYPE",  "")
  set_extstate("BREAK_AAP_DAY_NAME",      "")
  set_extstate("BREAK_AAP_ITEM_COUNT",    "")
  set_extstate("BREAK_AAP_TOTAL_SECONDS", "")
  set_extstate("BREAK_AAP_EST_SIZE",      "")
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

-- Name of the ISO source folder in this project: "ISO", else the older "EDL".
local function iso_folder_name()
  for _, name in ipairs(ISO_FOLDER_NAMES) do
    if get_track_by_name(name) then return name end
  end
  return ISO_FOLDER_NAMES[1]
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

-- ── Project master list ─────────────────────────────────────────────────────
-- One place for project names: "PM Projects.txt" next to the Work Log project,
-- created and updated by PM Timer (plain text, one project per line):
--   POINT = Point, PointUp_AAP        official name = older spellings (aliases)
-- The project name in a .rpp file name is looked up there (case-insensitive) and
-- replaced by the official name; the choice is saved in the project (PROJECT_NAME),
-- so daily save-as copies keep it. Aliases are project names only, never modules.
local PROJECTS_FILE = "PM Projects.txt"
local TASK_NAMES    = { conform = "Conform", aap = "AAP", dialog = "Dialog" }
local MASTER        = nil   -- { path = file or nil, list = { { name =, aliases = {} } } }

-- Folder of the Work Log project: remembered (global ExtState), else an open Work Log tab
local function work_log_dir()
  local d = r.GetExtState(NS, "WORK_LOG_DIR")
  if d ~= "" then return d end
  local i = 0
  while true do
    local proj, fn = r.EnumProjects(i)
    if not proj then break end
    if (fn:match("([^/\\]+)$") or fn):find("Work Log", 1, true) then
      d = fn:match("^(.*)[/\\]") or ""
      if d ~= "" then r.SetExtState(NS, "WORK_LOG_DIR", d, true); return d end
    end
    i = i + 1
  end
  return nil
end

local function load_master()
  local dir  = work_log_dir()
  local path = dir and (dir .. "/" .. PROJECTS_FILE) or nil
  local list = {}
  local fh = path and io.open(path, "r")
  if fh then
    for raw_line in fh:lines() do
      local line = raw_line:gsub("\r$", "")
      if line:match("%S") and not line:match("^%s*#") then
        local name, rest = line:match("^%s*(.-)%s*=%s*(.-)%s*$")
        if not name then name, rest = line:match("^%s*(.-)%s*$"), "" end
        local e = { name = name, aliases = {} }
        for a_raw in rest:gmatch("[^,]+") do
          local a = a_raw:match("^%s*(.-)%s*$")
          if a ~= "" then e.aliases[#e.aliases + 1] = a end
        end
        if name ~= "" then list[#list + 1] = e end
      end
    end
    fh:close()
  end
  MASTER = { path = path, list = list }
  return MASTER
end

local function save_master()
  if not (MASTER and MASTER.path) then return false end
  local fh = io.open(MASTER.path, "w")
  if not fh then return false end
  fh:write("# PM Projects - official project names for PM Timer / PM Insight (managed by PM Timer)\n")
  fh:write("# One project per line:  OfficialName = older spelling, another spelling\n")
  for _, e in ipairs(MASTER.list) do
    fh:write(e.name .. (#e.aliases > 0 and (" = " .. table.concat(e.aliases, ", ")) or "") .. "\n")
  end
  fh:close()
  return true
end

-- Official name for a project name or alias (case-insensitive), or nil
local function master_lookup(name)
  if not MASTER then load_master() end
  local l = (name or ""):lower()
  if l == "" then return nil end
  for _, e in ipairs(MASTER.list) do
    if e.name:lower() == l then return e.name end
    for _, a in ipairs(e.aliases) do if a:lower() == l then return e.name end end
  end
  return nil
end

local function master_entry(name)
  if not MASTER then load_master() end
  local l = (name or ""):lower()
  for i, e in ipairs(MASTER.list) do if e.name:lower() == l then return e, i end end
end

local function add_alias(entry, alias)
  if alias == "" or alias:lower() == entry.name:lower() then return end
  for _, a in ipairs(entry.aliases) do if a:lower() == alias:lower() then return end end
  entry.aliases[#entry.aliases + 1] = alias
end

-- Merges project `from` into `into`: its name and aliases become aliases of `into`
local function master_merge(from_name, into_name)
  local from, fi = master_entry(from_name)
  local into = master_entry(into_name)
  if not (from and into) or from == into then return false end
  add_alias(into, from.name)
  for _, a in ipairs(from.aliases) do add_alias(into, a) end
  table.remove(MASTER.list, fi)
  return true
end

-- Renames a project; the old name becomes an alias (not for a change of case only).
-- Returns "renamed", "exists" (new_name is another project: merge instead) or nil.
local function master_rename(old_name, new_name)
  local e = master_entry(old_name)
  new_name = (new_name or ""):gsub("[|,=]", " "):match("^%s*(.-)%s*$")
  if not e or new_name == "" or new_name == e.name then return nil end
  local other = master_entry(new_name)
  if other and other ~= e then return "exists" end
  local old = e.name
  e.name = new_name
  add_alias(e, old)
  for i = #e.aliases, 1, -1 do
    if e.aliases[i]:lower() == new_name:lower() then table.remove(e.aliases, i) end
  end
  return "renamed"
end

-- Parts of the project file name "YYMMDD----Project----Scope----Task----Note"
local function proj_file_parts()
  local _, proj_path = r.EnumProjects(-1)
  if not proj_path or proj_path == "" then return {} end
  local name = (proj_path:match("([^/\\]+)$") or proj_path):gsub("%.%a+$", "")
  local parts = {}
  for p in (name .. "----"):gmatch("(.-)%-%-%-%-") do parts[#parts + 1] = p end
  return parts
end

-- Official name of this project: the saved choice, else the file-name part,
-- each run through the master list
local function official_project_name(raw)
  local n = get_extstate("PROJECT_NAME") or raw or ""
  if n == "" then return "" end
  return master_lookup(n) or n
end

-- Conform / AAP / Dialog in one spelling
local function norm_task(t)
  if not t or t == "" then return t end
  return TASK_NAMES[t:lower()] or t
end

-- Asks which project this is when its file-name project name is not in the
-- master list (once per project per run; force = always, from the menu).
local asked_project = {}
local function check_project_name(force)
  local raw = proj_file_parts()[2]
  if not raw or raw == "" then return end           -- not a "YYMMDD----Project----..." file
  local id = get_proj_identity()
  if not force then
    if asked_project[id] then return end
    asked_project[id] = true
  end
  if not work_log_dir() then
    local ok, fn = r.GetUserFileNameForRead("", "PM Timer: locate Work Log.RPP (the project list is kept next to it)", ".RPP")
    if not ok or fn == "" then return end
    r.SetExtState(NS, "WORK_LOG_DIR", fn:match("^(.*)[/\\]") or "", true)
  end
  load_master()
  if not MASTER.path then return end
  local saved = get_extstate("PROJECT_NAME")
  if not force then
    local official = master_lookup(saved or raw)
    if official then
      if official ~= saved then set_extstate("PROJECT_NAME", official) end
      return
    end
  end

  -- Menu: add the file-name name as a new project, type one, or pick an existing one
  local cur = official_project_name(raw)
  local entries = { "#Project of this file (file name: " .. raw .. ")", "Add as a new project: " .. raw,
    "Add a new project (type the name)...", "#Or it is the same project as:" }
  local first = #entries + 1
  for _, e in ipairs(MASTER.list) do entries[#entries + 1] = (e.name == cur and "!" or "") .. e.name end
  local menu = table.concat(entries, "|", 1, 3) .. "||" .. table.concat(entries, "|", 4)
  gfx.x, gfx.y = 10, 30
  local choice = gfx.showmenu((menu:gsub("|$", "")))
  local name
  if choice == 2 then
    name = raw
  elseif choice == 3 then
    local ok, val = r.GetUserInputs("New project", 1, "Official project name:,extrawidth=120", raw)
    if not ok then return end
    name = val:gsub("[|,=]", " "):match("^%s*(.-)%s*$")
    if name == "" then return end
  elseif choice >= first then
    name = MASTER.list[choice - first + 1].name
  else
    return
  end
  local entry
  for _, e in ipairs(MASTER.list) do if e.name:lower() == name:lower() then entry = e end end
  if not entry then entry = { name = name, aliases = {} }; MASTER.list[#MASTER.list + 1] = entry end
  -- the file-name spelling becomes an alias, so the next file with it needs no question
  if raw:lower() ~= entry.name:lower() and not master_lookup(raw) then entry.aliases[#entry.aliases + 1] = raw end
  save_master()
  set_extstate("PROJECT_NAME", entry.name)
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
  local project = parts[2] and official_project_name(parts[2])
  local scope   = parts[3]
  local task    = norm_task(parts[4])
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
  return norm_task(parts[4]) or ""
end

-- Prepend the project prefix to name. No-ops if prefix is empty or already present.
local function apply_proj_prefix(name)
  local prefix = get_proj_prefix()
  if prefix == "" then return name end
  if name:sub(1, #prefix) == prefix then return name end
  return prefix .. name
end

-- Build "project workflow | process" fallback when strict prefix is unavailable.
-- Example: 260729----FishTown----AAP  ->  "FishTown AAP | pre-production"
local function get_project_workflow_prefix_fallback()
  local _, proj_path = r.EnumProjects(-1)
  if not proj_path or proj_path == "" then return "" end
  local name = proj_path:match("([^/\\]+)$") or proj_path
  name = name:gsub("%.%a+$", "")

  local parts = {}
  for p in (name .. "----"):gmatch("(.-)%-%-%-%-") do
    parts[#parts + 1] = p
  end
  local project  = official_project_name(parts[2])
  local workflow = norm_task(parts[3]) or ""
  if project ~= "" and workflow ~= "" then
    return project .. " " .. workflow .. " | "
  end
  return ""
end

local function get_project_label_fallback()
  local _, proj_path = r.EnumProjects(-1)
  if not proj_path or proj_path == "" then return "Project" end
  local name = proj_path:match("([^/\\]+)$") or proj_path
  name = name:gsub("%.%a+$", "")

  local parts = {}
  for p in (name .. "----"):gmatch("(.-)%-%-%-%-") do
    parts[#parts + 1] = p
  end
  if parts[2] and parts[2] ~= "" then return official_project_name(parts[2]) end
  return name
end

local function build_project_process_name(process_name)
  local prefix = get_proj_prefix()
  if prefix ~= "" then
    return apply_proj_prefix(process_name)
  end
  local wf_prefix = get_project_workflow_prefix_fallback()
  if wf_prefix ~= "" then
    return wf_prefix .. process_name
  end
  return get_project_label_fallback() .. " | " .. process_name
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
  if not c then
    -- Automatic color: hue from a hash of the name (stable across sessions)
    local h = 0
    for i = 1, #work_type do h = (h * 31 + work_type:byte(i)) % 360 end
    local f = (h % 60) / 60
    local v, lo = 235, 70
    local up, dn = math.floor(lo + (v - lo) * f), math.floor(v - (v - lo) * f)
    local seg = math.floor(h / 60)
    c = ({ {v, up, lo}, {dn, v, lo}, {lo, v, up}, {lo, dn, v}, {up, lo, v}, {v, lo, dn} })[seg + 1]
  end

  local color = reaper.ColorToNative(c[1], c[2], c[3]) | 0x1000000
  if reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR") == color then return end
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

  -- Safety: for AAP-style sessions, ensure item names always include
  -- "project workflow | process" even if caller passed only work_type.
  local is_aap_style = (S.work_mode == "AAP")
                    or (work_type == "pre-production")
                    or (work_type == "wrap")
  if is_aap_style and item_name and not item_name:find(" | ", 1, true) then
    item_name = build_project_process_name(work_type)
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
  return string.format("%.1f GB", gb)
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
  local item_name  = build_project_process_name(work_type)
  local item       = create_work_item(date_track, "", item_name, work_type, pos_secs, now_clock)
  local item_guid  = get_item_guid(item)
  r.Undo_EndBlock("PM: Start AAP session", -1)
  r.UpdateArrange()
  auto_sync_work_log_if_open()

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
    local selected_type = choose_work_type(AAP_GENERAL_TYPES)
    if not selected_type then return end
    start_simple_aap_work(selected_type, chain)
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
  local work_type      = AAP_FOLDER_DEFAULT_TYPE
  local item_name      = build_project_process_name(work_type)
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
  auto_sync_work_log_if_open()

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
-- src_cnt : ISO (or older EDL) folder items attributed to the scene (P_EXT:SCENE_ID, else same item group)
-- src_len : total D_LENGTH of the attributed ISO items (seconds)
-- sel_len / edit_len : source left in the "Mic Selected" / "Edited" folders
--           (nil when the folder does not exist). An item in the scene's item
--           group counts in full; an item not grouped with any scene counts
--           with the part that lies inside the scene range (pre-laps etc. are
--           counted where they sit on the timeline).

local function compute_scene_metadata(scene_item)
  local scene_start = r.GetMediaItemInfo_Value(scene_item, "D_POSITION")
  local scene_len   = r.GetMediaItemInfo_Value(scene_item, "D_LENGTH")
  local scene_end   = scene_start + scene_len
  local scene_group = math.floor(r.GetMediaItemInfo_Value(scene_item, "I_GROUPID"))
  local scene_guid  = r.BR_GetMediaItemGUID(scene_item)

  -- shots: Picture Cut items that overlap the scene range by more than half a frame; a shot that
  -- only touches the scene edge (starts where the scene ends) must not count, but a tiny
  -- floating-point difference made it "overlap" and the count was often 1 too high
  local shots = 0
  local pic_track = get_track_by_name(PICTURE_TRACK_NAME)
  if pic_track then
    local fps = r.TimeMap_curFrameRate(0)
    local tol = 0.5 / ((fps and fps > 0) and fps or 24)
    for i = 0, r.CountTrackMediaItems(pic_track) - 1 do
      local pitem      = r.GetTrackMediaItem(pic_track, i)
      local item_start = r.GetMediaItemInfo_Value(pitem, "D_POSITION")
      local item_end   = item_start + r.GetMediaItemInfo_Value(pitem, "D_LENGTH")
      if item_end > scene_start + tol and item_start < scene_end - tol then shots = shots + 1 end
    end
  end

  -- src_cnt / src_len: ISO items attributed to this scene
  local src_cnt = 0
  local src_len = 0
  for _, t in ipairs(get_folder_children(iso_folder_name())) do
    for i = 0, r.CountTrackMediaItems(t) - 1 do
      local item  = r.GetTrackMediaItem(t, i)
      local ilen  = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local _, sid = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_ID", "", false)
      local match = (sid == scene_guid)
      if not match and scene_group ~= 0 then  -- same item group as the scene (merged from PM Scene Analyzer)
        match = math.floor(r.GetMediaItemInfo_Value(item, "I_GROUPID")) == scene_group
      end
      if match then src_cnt = src_cnt + 1; src_len = src_len + ilen end
    end
  end

  -- sel_len / edit_len: later stage folders, by item group, else by time range
  local scene_groups = {}
  local scene_track  = get_track_by_name(SCENE_TRACK_NAME)
  if scene_track then
    for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
      local g = math.floor(r.GetMediaItemInfo_Value(r.GetTrackMediaItem(scene_track, i), "I_GROUPID"))
      if g ~= 0 then scene_groups[g] = true end
    end
  end
  local function stage_len(folder_name)
    if not get_track_by_name(folder_name) then return nil end
    local total = 0
    for _, t in ipairs(get_folder_children(folder_name)) do
      for i = 0, r.CountTrackMediaItems(t) - 1 do
        local item = r.GetTrackMediaItem(t, i)
        local s0   = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local s1   = s0 + r.GetMediaItemInfo_Value(item, "D_LENGTH")
        local g    = math.floor(r.GetMediaItemInfo_Value(item, "I_GROUPID"))
        if g ~= 0 and scene_groups[g] then
          if g == scene_group then total = total + (s1 - s0) end
        else
          local ov = math.min(s1, scene_end) - math.max(s0, scene_start)
          if ov > 0 then total = total + ov end
        end
      end
    end
    return total
  end

  return { shots = shots, src_cnt = src_cnt, src_len = src_len,
           sel_len = stage_len(MIC_SELECTED_FOLDER), edit_len = stage_len(EDITED_FOLDER) }
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

local function build_aap_recording_note(day_name, item_count, total_seconds)
  local day = (day_name and day_name ~= "") and day_name or "(unknown)"
  local cnt = math.max(0, math.floor(tonumber(item_count) or 0))
  local secs = math.max(0, tonumber(total_seconds) or 0)

  return table.concat({
    "Recording Date : " .. day,
    "Items          : " .. tostring(cnt),
    "Source Len     : " .. fmt_hms_ms(secs),
    "Source Size    : " .. seconds_to_size_string(secs),
  }, "\n")
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

-- Returns true when the note or take name changed (or would change, with dry = true).
local function update_scene_note(scene_item, dry)
  if not scene_item then return false end

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

  -- Scene name: take name first (CLB-created scenes keep the name there with an
  -- empty note), then the first note line, else "(no name)".
  local scene_name
  local take = r.GetActiveTake(scene_item)
  if take then
    local tname = r.GetTakeName(take)
    if tname and tname ~= "" then scene_name = tname end
  end
  if not scene_name then
    scene_name = (lines[1] and lines[1] ~= "") and lines[1] or "(no name)"
  end

  -- Strip all known metadata lines (new pretty format + old key=value format)
  local function is_meta(line)
    return line:match("^Range%s*:")
        or line:match("^Length%s*:")
        or line:match("^Shots%s*:")
        or line:match("^Src Cnt%s*:")
        or line:match("^Src Len%s*:")
        or line:match("^Sel Len%s*:")
        or line:match("^Edit Len%s*:")
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
  if meta.sel_len then
    table.insert(parts, "Sel Len  : " .. r.format_timestr_len(meta.sel_len, "", 0, 5))
  end
  if meta.edit_len then
    table.insert(parts, "Edit Len : " .. r.format_timestr_len(meta.edit_len, "", 0, 5))
  end
  for _, l in ipairs(other) do table.insert(parts, l) end

  local new_note = table.concat(parts, "\n")
  local note_changed = new_note ~= (note or "")
  local name_changed = not take or r.GetTakeName(take) ~= scene_name
  if dry then return note_changed or name_changed end

  if note_changed then
    r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", new_note, true)
  end
  if name_changed then
    -- Show the scene name on the timeline (add an empty take to hold it if needed)
    if not take then take = r.AddTakeToMediaItem(scene_item) end
    if take then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", scene_name, true) end
  end
  if note_changed or name_changed then r.UpdateItemInProject(scene_item) end

  -- Push updated note to all work log items linked to this scene
  local scene_guid = r.BR_GetMediaItemGUID(scene_item)
  sync_linked_work_item_notes(scene_guid, new_note)
  return note_changed or name_changed
end

-- Public entry point: update metadata for a scene item found by GUID.
local function update_scene_metadata_by_guid(guid)
  if not guid or guid == "" then return end
  local scene_item = get_item_by_guid(guid)
  if scene_item then update_scene_note(scene_item) end
end

-- Update the metadata of every Scene Cut item (selected_only = only the selected
-- ones). One undo step, and only when something actually changes, so opening /
-- closing PM Timer does not dirty the project. Returns (scenes checked, updated).
local function update_scene_notes(selected_only)
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  if not scene_track then return 0, 0 end
  local targets, pending = {}, false
  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local item = r.GetTrackMediaItem(scene_track, i)
    if not selected_only or r.IsMediaItemSelected(item) then
      targets[#targets + 1] = item
      if update_scene_note(item, true) then pending = true end
    end
  end
  if not pending then return #targets, 0 end
  local updated = 0
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  for _, item in ipairs(targets) do
    if update_scene_note(item) then updated = updated + 1 end
  end
  r.Undo_EndBlock("PM: Update scene metadata", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  return #targets, updated
end

-- Work log items (take name contains "|") whose P_EXT:SCENE_GUID points to a
-- scene that no longer exists on Scene Cut — e.g. after the Scene Cut was
-- regenerated. Project Mode items have no SCENE_GUID by design and are fine.
-- (Merged from the former PM Check Scene Links script.)
local function find_broken_scene_links()
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  if not scene_track then return {} end
  local valid = {}
  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    valid[r.BR_GetMediaItemGUID(r.GetTrackMediaItem(scene_track, i))] = true
  end
  local broken = {}
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    if tr ~= scene_track then
      for j = 0, r.CountTrackMediaItems(tr) - 1 do
        local item = r.GetTrackMediaItem(tr, j)
        local take = r.GetActiveTake(item)
        if take and r.GetTakeName(take):find("|", 1, true) then
          local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
          if sg ~= "" and not valid[sg] then broken[#broken + 1] = item end
        end
      end
    end
  end
  return broken
end

-- ── Re-linking work log items to scenes ────────────────────────────────────
-- Scene name + Range start read from a note in the scene-metadata format
-- (line 1 = scene name, "Range    : <start> - <end>"). Log items keep a copy of
-- their scene's note, so this identifies which scene a broken item belonged to.
local function scene_key_from_note(note)
  if not note or note == "" then return nil end
  local name = note:match("^([^\n]*)")
  local range_start = note:match("\nRange%s*:%s*(.-)%s+%-%s+")
  if not name or name == "" or not range_start then return nil end
  return name .. "\0" .. range_start
end

-- Current scene name, same priority as update_scene_note (take name, then note).
local function scene_key_of_scene_item(scene_item)
  local _, note = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
  local range_start = (note or ""):match("\nRange%s*:%s*(.-)%s+%-%s+")
  local take = r.GetActiveTake(scene_item)
  local name = take and r.GetTakeName(take) or ""
  if name == "" then name = (note or ""):match("^([^\n]*)") or "" end
  if name == "" or not range_start then return nil end
  return name .. "\0" .. range_start
end

-- For each broken item, the one scene with the same name AND Range start.
-- Items with no match or several matches are left alone (never guessed).
-- Returns { {item=, scene=, name=}, ... } and the list of items left unmatched.
local function match_broken_links(broken)
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  local by_key = {}
  if scene_track then
    for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
      local sc = r.GetTrackMediaItem(scene_track, i)
      local key = scene_key_of_scene_item(sc)
      if key then
        by_key[key] = by_key[key] or {}
        table.insert(by_key[key], sc)
      end
    end
  end
  local matched, unmatched = {}, {}
  for _, item in ipairs(broken) do
    local note = r.ULT_GetMediaItemNote(item) or ""
    local key = scene_key_from_note(note)
    local hits = key and by_key[key]
    if hits and #hits == 1 then
      matched[#matched + 1] = { item = item, scene = hits[1], name = note:match("^([^\n]*)") }
    else
      unmatched[#unmatched + 1] = item
    end
  end
  return matched, unmatched
end

-- Point work log items at a scene and refresh their scene metadata. One undo step.
local function relink_items_to_scene(pairs_list)
  if #pairs_list == 0 then return 0 end
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  for _, p in ipairs(pairs_list) do
    local locked = r.GetMediaItemInfo_Value(p.item, "C_LOCK")
    r.SetMediaItemInfo_Value(p.item, "C_LOCK", 0)
    set_item_ext(p.item, "SCENE_GUID", r.BR_GetMediaItemGUID(p.scene))
    r.SetMediaItemInfo_Value(p.item, "C_LOCK", locked)
    PM_SyncSceneMetadataToLogItem(p.item)
    r.UpdateItemInProject(p.item)
  end
  r.Undo_EndBlock("PM: Relink work log items to scenes", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  return #pairs_list
end

-- Runs when PM Timer opens, closes, or the project changes (like the work log sync).
local function auto_update_scenes()
  update_scene_notes(false)
  S.broken_links = #find_broken_scene_links()
end

-- Returns the P_NOTES of a Scene Cut item to sync into the linked work log item.
-- The work item note mirrors the scene item note verbatim — no recomputation.
local function build_work_item_note(scene_item)
  if not scene_item then return "" end
  local _, note = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)
  return note or ""
end

-- Computes project-scope metadata (all scenes, all ISO source, all shots) for the
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

  -- ISO source: all items across all ISO folder children
  local src_cnt = 0
  local src_len = 0
  for _, t in ipairs(get_folder_children(iso_folder_name())) do
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
      if wt ~= "" and sg == "" and not is_aap_work_type(wt) then
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
  local work_type = choose_work_type(get_work_types_for_mode())
  if not work_type then return end

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

  -- Read scene metadata from Scene Cut item note (owned by Scene Analyzer).
  local item_note = ""
  if sel_scene and sel_scene.handle then
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
  auto_sync_work_log_if_open()

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

  auto_sync_work_log_if_open()

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

    local aap_day_name = S.aap_day_name
    if aap_day_name == "" then
      local _, v = r.GetSetMediaItemInfo_String(item, "P_EXT:AAP_DAY_NAME", "", false)
      aap_day_name = v or ""
    end
    local aap_item_count = S.aap_item_count
    if (aap_item_count or 0) <= 0 then
      local _, v = r.GetSetMediaItemInfo_String(item, "P_EXT:AAP_ITEM_COUNT", "", false)
      aap_item_count = tonumber(v) or 0
    end
    local aap_total_seconds = S.aap_total_seconds
    if (aap_total_seconds or 0) <= 0 then
      local _, v = r.GetSetMediaItemInfo_String(item, "P_EXT:AAP_TOTAL_SECONDS", "", false)
      aap_total_seconds = tonumber(v) or 0
    end

    local cur_note = r.ULT_GetMediaItemNote(item) or ""
    local user_comment = extract_log_comment(cur_note)
    if user_comment == "" and cur_note ~= "" and not cur_note:find("Recording Date :", 1, true) then
      user_comment = cur_note
    end

    r.Undo_BeginBlock()
    r.SetMediaItemInfo_Value(item, "C_LOCK",   0)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", duration)
    set_item_ext(item, "END_REASON",       end_reason)
    set_item_ext(item, "END_CLOCK",        tostring(os.time()))
    set_item_ext(item, "DURATION",         tostring(duration))
    set_item_ext(item, "AAP_WORK_SECONDS", tostring(work_secs))
    if S.work_type == "aap" then
      local meta = build_aap_recording_note(aap_day_name, aap_item_count, aap_total_seconds)
      local new_note = merge_log_note(meta, user_comment)
      r.ULT_SetMediaItemNote(item, new_note)
    end
    r.UpdateItemInProject(item)
    r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
    r.Undo_EndBlock("PM: " .. end_reason .. " AAP session", -1)
    r.UpdateArrange()
  end

  auto_sync_work_log_if_open()
  clear_active_extstate()
  reset_state()
  return end_time, end_pos
end

-- Finish current AAP item and immediately start the next one.
-- Menu: [pre-production | new day | wrap | custom]
--   new day        → folder-based AAP start (select folder in REAPER first)
--   pre-production / wrap / custom → simple work item, no folder stats needed
local AAP_NEW_JOB_MENU = { "pre-production", "new day", "wrap", "custom" }
local function action_aap_new_job()
  local end_time, end_pos = finish_aap_item("new_job")
  local chain = end_time and { end_time = end_time, end_pos = end_pos } or nil
  local sel = choose_work_type(AAP_NEW_JOB_MENU)
  if not sel then return end
  if sel == "new day" then
    action_start_aap(chain)
  else
    start_simple_aap_work(sel, chain)
  end
end

-- ── Sync work item names ────────────────────────────────────────────────────
-- Rebuilds take names for all Scene Mode work items (those with P_EXT:SCENE_GUID).
-- Project Mode items (no SCENE_GUID) are naturally skipped by the sg ~= "" check.
-- Name format: "work_type" only (scene metadata lives in P_NOTES, not the name)
-- A work item renamed by hand keeps its new name: the text after the last
-- " | " (or the whole name) differing from P_EXT:WORK_TYPE becomes the new
-- work type, and the item color follows. Returns the (possibly new) type.
local function adopt_renamed_work_type(item, take, wt)
  local cur  = r.GetTakeName(take)
  local base = cur:match(".* | (.-)$") or cur
  base = base:gsub("^%s+", ""):gsub("%s+$", "")
  if base == "" or base == wt then return wt end
  set_item_ext(item, "WORK_TYPE", base)
  r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
  apply_color_from_type(item)
  r.SetMediaItemInfo_Value(item, "C_LOCK", 1)
  if get_item_guid(item) == S.work_item_guid then
    S.work_type = base
    set_extstate("ACTIVE_WORK_TYPE", base)
  end
  return base
end

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
          if work_type ~= "" then
            work_type = adopt_renamed_work_type(item, item_take, work_type)
          end
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
-- A name ending in its WORK_TYPE is rebuilt as "<current prefix><work type>",
-- so an outdated prefix (project renamed) is replaced instead of stacked.
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
          wt = adopt_renamed_work_type(item, take, wt)
          local cur  = r.GetTakeName(take)
          local new
          if cur == wt or cur:sub(-(#wt + 3)) == " | " .. wt then
            new = prefix .. wt
          else
            new = apply_proj_prefix(cur)
          end
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
    local finishing_guid = S.work_item_guid
    finish_current_item("finish"); sync_work_item_names()
    local log_item = get_item_by_guid(finishing_guid)
    if log_item then PM_SyncSceneMetadataToLogItem(log_item) end
    if was_project_scope then PM_SyncProjectScopeNotes() end
  end
end
local function action_break()
  if S.work_mode == "AAP" then
    save_break_state()
    finish_aap_item("break")
  else
    local was_project_scope = (S.scene_guid == "")
    save_break_state()
    finish_current_item("break"); sync_work_item_names()
    if was_project_scope then PM_SyncProjectScopeNotes() end
  end
end

local function action_continue()
  if not BREAK_STATE then return end
  local bs = BREAK_STATE

  if bs.work_mode == "AAP" then
    -- Continue should always restore AAP mode even if user changed mode while on break.
    set_work_mode("AAP")

    local parent_track = get_or_create_folder_track(WORK_LOG_NAME, true, true)
    if not parent_track then
      r.ShowMessageBox("Cannot create Work Log track.", "PM Timer", 0)
      return
    end

    local pos_secs    = secs_since_midnight()
    local now_clock   = os.time()
    local now_precise = r.time_precise()
    local item_name   = build_project_process_name(bs.work_type)

    r.Undo_BeginBlock()
    ensure_folder_track(parent_track)
    local date_track = get_or_create_date_track(parent_track, os.date("%Y-%m-%d"))
    local item       = create_work_item(date_track, "", item_name, bs.work_type, pos_secs, now_clock)
    local item_guid  = get_item_guid(item)
    r.Undo_EndBlock("PM: Continue AAP session", -1)
    r.UpdateArrange()
    auto_sync_work_log_if_open()

    S.mode              = "WORKING"
    S.scene_guid        = ""
    S.scene_name        = ""
    S.scene_start_tc    = ""
    S.work_type         = bs.work_type
    S.work_item_guid    = item_guid
    S.start_clock       = now_clock
    S.last_start_time   = now_precise
    S.aap_day_name      = bs.aap_day_name or ""
    S.aap_item_count    = bs.aap_item_count or 0
    S.aap_total_seconds = bs.aap_total_seconds or 0
    S.aap_est_size      = bs.aap_est_size or ""

    set_extstate("ACTIVE_WORK_ITEM_GUID",    item_guid)
    set_extstate("ACTIVE_WORK_SCENE_GUID",   "")
    set_extstate("ACTIVE_WORK_SCENE_NAME",   "")
    set_extstate("ACTIVE_WORK_TYPE",         bs.work_type)
    set_extstate("ACTIVE_WORK_START_CLOCK",  tostring(now_clock))
    set_extstate("ACTIVE_WORK_OSTIME_START", tostring(now_clock))
    set_extstate("ACTIVE_AAP_DAY_NAME",      S.aap_day_name)
    set_extstate("ACTIVE_AAP_ITEM_COUNT",    tostring(S.aap_item_count))
    set_extstate("ACTIVE_AAP_TOTAL_SECONDS", tostring(S.aap_total_seconds))
    set_extstate("ACTIVE_AAP_EST_SIZE",      S.aap_est_size)

    clear_break_state()
    return
  end

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
  auto_sync_work_log_if_open()

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

  local new_type = choose_work_type(get_work_types_for_mode()) or S.work_type

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
  auto_sync_work_log_if_open()

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

  local new_type = choose_work_type(get_work_types_for_mode()) or S.work_type

  -- Read new scene's metadata from Scene Cut note (owned by Scene Analyzer).
  local item_note = ""
  if sel_scene.handle then
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
  auto_sync_work_log_if_open()

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
  auto_sync_work_log_if_open()
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
    if base:find("Work Log", 1, true) then
      local d = fn:match("^(.*)[/\\]")
      if d and d ~= "" and r.GetExtState(NS, "WORK_LOG_DIR") ~= d then r.SetExtState(NS, "WORK_LOG_DIR", d, true) end
      return proj
    end
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
    r.SetMediaItemInfo_Value(existing, "C_LOCK", 0)
    r.SetMediaItemInfo_Value(existing, "D_LENGTH",      len)
    r.SetMediaItemInfo_Value(existing, "I_CUSTOMCOLOR", color)
    if src_note and src_note ~= "" then
      r.GetSetMediaItemInfo_String(existing, "P_NOTES", src_note, true)
    end
    r.UpdateItemInProject(existing)
    r.SetMediaItemInfo_Value(existing, "C_LOCK", 1)
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
  r.SetMediaItemInfo_Value(new_item, "C_LOCK", 1)
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
-- Returns nil for scene-mode names ("4-14 Bakery (04:04:28:12) | editing")
-- or names without a recognizable prefix.
local function extract_proj_from_name(name)
  local prefix_part = name:match("^(.-)%s*|")
  if not prefix_part or prefix_part == "" then return nil end
  -- Scene-mode names contain a timecode "(HH:MM:SS:FF)" → skip
  if prefix_part:find("%(%d+:%d+:%d+:%d+%)") then return nil end
  return prefix_part:match("^(%S+)")
end

-- Find or create a YYYY-MM-DD date track in the Work Log project.
-- Missing tracks are inserted after the previous date track when possible,
-- or before DurationOnly_Log so the date range stays contiguous.
local function get_or_create_wl_date_track(wl_proj, date_str, after_idx, src_proj)
  local existing, existing_idx = find_track_in_proj(wl_proj, date_str)
  if existing then
    if r.GetMediaTrackInfo_Value(existing, "I_FOLDERDEPTH") ~= 0 then
      r.SetMediaTrackInfo_Value(existing, "I_FOLDERDEPTH", 0)
    end
    return existing, existing_idx
  end

  local insert_at
  if after_idx and after_idx >= 0 then
    insert_at = after_idx + 1
  else
    local dur_log = find_track_in_proj(wl_proj, DURATION_LOG_NAME)
    if dur_log then
      insert_at = math.floor(r.GetMediaTrackInfo_Value(dur_log, "IP_TRACKNUMBER")) - 1
    else
      insert_at = r.CountTracks(wl_proj)
    end
  end

  r.SelectProjectInstance(wl_proj)
  r.InsertTrackAtIndex(insert_at, true)
  local new_t = r.GetTrack(wl_proj, insert_at)
  r.GetSetMediaTrackInfo_String(new_t, "P_NAME", date_str, true)
  r.SetMediaTrackInfo_Value(new_t, "I_FOLDERDEPTH", 0)
  r.SelectProjectInstance(src_proj)
  return new_t, insert_at
end

local function date_str_to_ts(date_str)
  local year, month, day = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not year then return nil end
  return os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
end

local function expand_date_range(start_date, end_date)
  local dates = {}
  local start_ts = date_str_to_ts(start_date)
  local end_ts   = date_str_to_ts(end_date)
  if not start_ts or not end_ts then return dates end

  local ts = start_ts
  while ts <= end_ts do
    dates[#dates + 1] = os.date("%Y-%m-%d", ts)
    ts = ts + 86400
  end
  return dates
end

-- Ensure the Work Log project has one date track for every day in `year`.
-- Existing tracks are preserved; missing tracks are inserted in date order.
local function ensure_wl_year_calendar(wl_proj, year)
  if not wl_proj then return 0 end
  year = tonumber(year)
  if not year then return 0 end

  local start_ts = os.time({ year = year, month = 1, day = 1, hour = 12 })
  local next_year_ts = os.time({ year = year + 1, month = 1, day = 1, hour = 12 })
  if not start_ts or not next_year_ts then return 0 end

  local filled = 0
  local last_idx = -1
  for ts = start_ts, next_year_ts - 86400, 86400 do
    local date_str = os.date("%Y-%m-%d", ts)
    local _, cur_idx = find_track_in_proj(wl_proj, date_str)
    if cur_idx >= 0 then
      last_idx = cur_idx
    else
      local _, new_idx = get_or_create_wl_date_track(wl_proj, date_str, last_idx, wl_proj)
      last_idx = new_idx
      filled = filled + 1
    end
  end
  return filled
end

local function sync_work_log_internal(opts)
  opts = opts or {}
  local show_messages = not not opts.show_messages

  local src_proj = r.EnumProjects(-1)
  local wl_proj  = find_work_log_project()
  if not wl_proj then
    if show_messages then
      r.ShowMessageBox(
        "Work Log project not found.\n\n"
        .. "Open a project whose filename contains 'Work Log' in REAPER, then try again.",
        "Sync to Work Log", 0)
    end
    return false
  end

  local current_year = tonumber(os.date("%Y"))
  local calendar_filled = ensure_wl_year_calendar(wl_proj, current_year)

  if src_proj == wl_proj then
    if show_messages then
      local msg = "Work Log calendar ensured for " .. tostring(current_year) .. "."
      if calendar_filled > 0 then
        msg = msg .. "\nCreated " .. tostring(calendar_filled) .. " missing date tracks."
      end
      r.ShowMessageBox(msg, "Sync to Work Log", 0)
    end
    return true
  end

  local source_track, source_name = find_track_in_proj(src_proj, SCENE_TRACK_NAME)
  if not source_track then
    source_track, source_name = find_track_in_proj(src_proj, WORK_LOG_NAME)
  end
  if not source_track then
    if show_messages then
      local msg = "Work Log calendar ensured for " .. tostring(current_year) .. "."
      if calendar_filled > 0 then
        msg = msg .. "\nCreated " .. tostring(calendar_filled) .. " missing date tracks."
      end
      msg = msg .. "\nNo source folder found ('" .. SCENE_TRACK_NAME .. "' or '" .. WORK_LOG_NAME .. "')."
      r.ShowMessageBox(msg, "Sync to Work Log", 0)
    end
    return true
  end

  local sc_num      = math.floor(r.GetMediaTrackInfo_Value(source_track, "IP_TRACKNUMBER"))
  local total       = r.CountTracks(src_proj)
  local _, src_fn   = r.EnumProjects(-1)
  local src_proj_id = (src_fn or ""):match("([^/\\]+)$") or (src_fn or "")

  local src_set = {}
  local src_dates = {}
  local src_date_seen = {}
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
      if tname:match(DATE_PAT) and not src_date_seen[tname] then
        src_date_seen[tname] = true
        src_dates[#src_dates + 1] = tname
      end
      d = d + fd
      if d <= 0 then break end
    end
  end
  table.sort(src_dates)

  local filled = 0
  r.Undo_BeginBlock2(wl_proj)
  if #src_dates > 0 then
    local expected_dates = expand_date_range(src_dates[1], src_dates[#src_dates])
    local last_idx = -1
    for _, date_str in ipairs(expected_dates) do
      local _, cur_idx = find_track_in_proj(wl_proj, date_str)
      if cur_idx >= 0 then
        last_idx = cur_idx
      else
        local _, new_idx = get_or_create_wl_date_track(wl_proj, date_str, last_idx, src_proj)
        last_idx = new_idx
        filled = filled + 1
      end
    end
  end

  local depth = 1
  local added = 0

  for i = sc_num, total - 1 do
    local t        = r.GetTrack(src_proj, i)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)

    if tname:match(DATE_PAT) then
      local dst = get_or_create_wl_date_track(wl_proj, tname, nil, src_proj)
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        if copy_item_to_wl(r.GetTrackMediaItem(t, j), dst, src_proj_id) then
          added = added + 1
        end
      end

    elseif tname == DURATION_LOG_NAME then
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

  if show_messages then
    local parts = {}
    if added   > 0 then table.insert(parts, string.format("%d added",   added))   end
    if filled  > 0 then table.insert(parts, string.format("%d date tracks filled", filled)) end
    if removed > 0 then table.insert(parts, string.format("%d removed", removed)) end
    local msg = #parts > 0
      and string.format("Work Log synced: %s.", table.concat(parts, ", "))
      or  "Work Log already up to date."
    r.ShowMessageBox(msg, "Sync to Work Log", 0)
  end

  return true
end

local function action_sync_work_log()
  sync_work_log_internal({ show_messages = true })
end

auto_sync_work_log_if_open = function()
  sync_work_log_internal({ show_messages = false })
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
    dst_track = get_or_create_wl_date_track(wl_proj, tname, nil, src_proj)
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

-- ── Rename / merge projects (master list) ───────────────────────────────────
-- Changes only the list (and this project's item names); other projects follow
-- through their saved name, which is now an alias. Work Log items keep their names
-- (PM Insight reads the list).
local function current_master_entry()
  load_master()
  if not MASTER.path then
    r.ShowMessageBox("The project list is kept next to Work Log.RPP - use Project Name... first.", "PM Timer", 0)
    return nil
  end
  local e = master_entry(official_project_name(proj_file_parts()[2]))
  if not e then
    r.ShowMessageBox("This project is not in the project list yet - use Project Name... first.", "PM Timer", 0)
  end
  return e
end

local function after_master_change(name)
  save_master()
  set_extstate("PROJECT_NAME", name)
  sync_work_item_names()
  sync_all_prefixes()
end

local function action_rename_project()
  local e = current_master_entry()
  if not e then return end
  local ok, val = r.GetUserInputs("Rename Project", 1, "New official name:,extrawidth=120", e.name)
  if not ok then return end
  local old = e.name
  local res = master_rename(old, val)
  if res == "exists" then
    local into = master_entry(val).name
    if r.ShowMessageBox(string.format("'%s' is already in the project list.\n\nMerge '%s' into '%s'?"
      .. "\n('%s' and its older spellings become spellings of '%s'.)", into, old, into, old, into),
      "Rename Project", 1) ~= 1 then return end
    master_merge(old, into)
    after_master_change(into)
  elseif res == "renamed" then
    after_master_change(e.name)
  end
end

local function action_merge_projects()
  local e = current_master_entry()
  if not e then return end
  local others = {}
  for _, x in ipairs(MASTER.list) do if x ~= e then others[#others + 1] = x.name end end
  if #others == 0 then
    r.ShowMessageBox("There is no other project in the list.", "Merge Projects", 0)
    return
  end
  gfx.x, gfx.y = 10, 30
  local choice = gfx.showmenu("#Merge into " .. e.name .. ":||" .. table.concat(others, "|"))
  local from = others[choice - 1]
  if not from then return end
  if r.ShowMessageBox(string.format("Merge '%s' into '%s'?\n\n'%s' and its older spellings become spellings of '%s'.",
    from, e.name, from, e.name), "Merge Projects", 1) ~= 1 then return end
  master_merge(from, e.name)
  after_master_change(e.name)
end

-- ── Link Split Scenes ───────────────────────────────────────────────────────
-- A scene found to be wrongly cut (split in REAPER after work was logged) keeps
-- all logged time on the piece that kept the original GUID. Select all pieces
-- on Scene Cut and run this: every work item linked to any piece gets
-- P_EXT:SCENE_SPLIT = "guid|guid|...", and PM Insight shares its time between
-- the pieces by source length. Selecting ONE scene removes the sharing again.
local function action_link_split_scenes()
  local scene_track = get_track_by_name(SCENE_TRACK_NAME)
  local pieces, in_set = {}, {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if scene_track and r.GetMediaItemTrack(item) == scene_track then
      local g = r.BR_GetMediaItemGUID(item)
      pieces[#pieces + 1] = g; in_set[g] = true
    end
  end
  if #pieces == 0 then
    r.ShowMessageBox("Select the pieces of the split scene on the Scene Cut track"
      .. " (or ONE scene to undo the sharing), then run Link Split Scenes again.", "PM Timer", 0)
    return
  end

  -- Work items linked to any selected piece (by SCENE_GUID or an earlier SCENE_SPLIT)
  local items = {}
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, j)
      local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
      local _, sp = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_SPLIT", "", false)
      local hit = in_set[sg]
      for g in sp:gmatch("[^|]+") do if in_set[g] then hit = true end end
      if hit then items[#items + 1] = item end
    end
  end
  if #items == 0 then
    r.ShowMessageBox("No work items are linked to the selected scene(s).", "PM Timer", 0)
    return
  end

  local value = (#pieces > 1) and table.concat(pieces, "|") or ""
  local msg = (#pieces > 1)
    and string.format("Share the time of %d work item%s between the %d selected scene pieces"
      .. " (by source length) in PM Insight?", #items, #items == 1 and "" or "s", #pieces)
    or string.format("Remove time sharing from %d work item%s?", #items, #items == 1 and "" or "s")
  if r.ShowMessageBox(msg, "Link Split Scenes", 1) ~= 1 then return end

  r.Undo_BeginBlock()
  for _, item in ipairs(items) do set_item_ext(item, "SCENE_SPLIT", value) end
  r.Undo_EndBlock("PM: Link split scenes", -1)
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
  local work_type = choose_work_type(get_work_types_for_mode())
  if not work_type then return end

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

-- ── Target (work hours + delivery date) ─────────────────────────────────────
-- Saved in the project (TARGET_HOURS, DUE_DATE, HOURS_PER_DAY = a working day, default 5);
-- PM Insight Analyzer plans with them.
-- Work logged so far (seconds): every work item under the Scene Cut folder (date tracks and
-- the duration-only log), as PM Insight Analyzer counts it. Cached until the project changes;
-- the running session counts with its live elapsed time (its item is only updated every 60 s).
local used_cache = { psc = -1, secs = 0, active_len = 0 }
local function used_work_secs()
  local psc = r.GetProjectStateChangeCount(0)
  if psc ~= used_cache.psc then
    local total, active_len = 0, 0
    for _, t in ipairs(get_folder_children(SCENE_TRACK_NAME)) do
      local _, tname = r.GetTrackName(t)
      if tname:match(DATE_PAT) or tname == DURATION_LOG_NAME then
        for i = 0, r.CountTrackMediaItems(t) - 1 do
          local item = r.GetTrackMediaItem(t, i)
          local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE", "", false)
          if wt ~= "" then
            local len = math.max(0, r.GetMediaItemInfo_Value(item, "D_LENGTH"))
            total = total + len
            if S.work_item_guid and r.BR_GetMediaItemGUID(item) == S.work_item_guid then active_len = len end
          end
        end
      end
    end
    used_cache.psc, used_cache.secs, used_cache.active_len = psc, total, active_len
  end
  if S.mode == "WORKING" then
    return used_cache.secs - used_cache.active_len + elapsed_secs()
  end
  return used_cache.secs
end

local function target_label()
  local hours, due = get_extstate("TARGET_HOURS"), get_extstate("DUE_DATE")
  if not hours and not due then return "Set target" end
  local parts = {}
  local y, m, d = (due or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if y then
    local now = os.date("*t")
    local days = math.floor((os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
      - os.time({ year = now.year, month = now.month, day = now.day, hour = 12 })) / 86400 + 0.5)
    parts[#parts + 1] = "Due " .. m .. "-" .. d
    parts[#parts + 1] = (days >= 0) and (days .. "d") or (-days .. "d late")
  end
  if tonumber(hours) then
    local left = tonumber(hours) - used_work_secs() / 3600
    parts[#parts + 1] = (left >= 0) and string.format("%.1fh left", left) or string.format("%.1fh over", -left)
  end
  return table.concat(parts, " · ")
end

local function action_set_target()
  local hours, due = get_extstate("TARGET_HOURS") or "", get_extstate("DUE_DATE") or ""
  local per_day = get_extstate("HOURS_PER_DAY") or "5"
  local ok, csv = r.GetUserInputs("PM Timer - Target", 3,
    "Target work hours (empty = none),Delivery date YYYY-MM-DD,Work hours per day,extrawidth=60",
    hours .. "," .. due .. "," .. per_day)
  if not ok then return end
  local h, d, pd = csv:match("^%s*(.-)%s*,%s*(.-)%s*,%s*(.-)%s*$")
  h, d, pd = h or "", d or "", pd or ""
  if not (tonumber(pd) and tonumber(pd) > 0 and tonumber(pd) <= 24) then
    r.ShowMessageBox("Work hours per day must be a number between 0 and 24.", "PM Timer", 0); return
  end
  if h ~= "" and not (tonumber(h) and tonumber(h) > 0) then
    r.ShowMessageBox("Target work hours must be a number above 0 (or empty).", "PM Timer", 0); return
  end
  local y, m, dd = d:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if d ~= "" and not (y and tonumber(m) >= 1 and tonumber(m) <= 12 and tonumber(dd) >= 1 and tonumber(dd) <= 31) then
    r.ShowMessageBox("Delivery date must look like 2026-11-15 (or empty).", "PM Timer", 0); return
  end
  set_extstate("TARGET_HOURS", h)
  set_extstate("DUE_DATE", d)
  set_extstate("HOURS_PER_DAY", pd)
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

    -- Official project name (master list) as a reminder, then the work mode
    local proj_disp = official_project_name(proj_file_parts()[2])
    if proj_disp ~= "" then
      if #proj_disp > 16 then proj_disp = proj_disp:sub(1, 15) .. "..." end
      gfx.set(0.45, 0.75, 1.0, 1); gfx.drawstr(proj_disp)
      gfx.set(0.7, 0.7, 0.7, 1);  gfx.drawstr(" · ")
    else
      gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("Mode: ")
    end
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

    local row1_end = gfx.x
    gfx.x, gfx.y = 10, 28
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("Start: ")
    gfx.set(1,   1,   1,   1); gfx.drawstr(start_disp)
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  Elapsed: ")
    gfx.set(0.2, 0.8, 1.0, 1); gfx.drawstr(fmt_hms(elapsed_secs()))
    -- Project frame rate (merged from the former "Show Frame Rate" script); DF = drop-frame
    local fps, drop = r.TimeMap_curFrameRate(0)
    local fps_str = string.format("%.3f", fps or 0):gsub("0+$", ""):gsub("%.$", "")
    gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  FPS: ")
    gfx.set(1,   1,   1,   1); gfx.drawstr(fps_str .. (drop and " DF" or ""))
    if (S.broken_links or 0) > 0 then
      gfx.set(0.7, 0.7, 0.7, 1); gfx.drawstr("  |  ")
      gfx.set(1.0, 0.6, 0.2, 1)
      gfx.drawstr(string.format("! %d broken scene link%s", S.broken_links, S.broken_links > 1 and "s" or ""))
    end

    -- Target box at the right of the info rows (click to set)
    local label = target_label()
    local tw, th = gfx.measurestr(label)
    local bw, bh = tw + 14, 30
    local bx = math.max(math.max(gfx.x, row1_end) + 12, gfx.w - bw - 10)
    local by = 8
    gfx.set(0.22, 0.22, 0.25, 1); gfx.rect(bx, by, bw, bh, 1)
    gfx.set(0.45, 0.45, 0.50, 1); gfx.rect(bx, by, bw, bh, 0)
    gfx.set(label == "Set target" and 0.6 or 1, label == "Set target" and 0.6 or 0.85, label == "Set target" and 0.6 or 0.4, 1)
    gfx.x, gfx.y = bx + 7, by + math.floor((bh - th) / 2)
    gfx.drawstr(label)
    table.insert(BTN, { rect = { x = bx, y = by, w = bw, h = bh }, action = action_set_target })

    sep(44)
  end

  -- ── Horizontal buttons ──────────────────────────────────────────────────
  -- compact buttons (were 40 px high): the whole window fits in a short dock
  local btn_w   = 129
  local btn_h   = 26
  local btn_y   = 54
  local btn_gap = 8
  local btn_x0  = 10

  local dlg_working = (S.mode == "WORKING" and not aap_working)

  gfx.setfont(3)
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
    local choice = gfx.showmenu(dock_label .. "|Fix Duration from item length|Fix Item Prefixes|Sync to Work Log|Update Scene Metadata|Relink to Selected Scene|Link Split Scenes|Project Name...|Rename Project...|Merge Projects...")
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
        -- Selected Scene Cut items only; if none is selected, all scenes
        local any_selected = false
        for i = 0, r.CountSelectedMediaItems(0) - 1 do
          if r.GetMediaItemTrack(r.GetSelectedMediaItem(0, i)) == scene_track then any_selected = true break end
        end
        local checked, updated = update_scene_notes(any_selected)
        local broken = find_broken_scene_links()
        local relinked = 0
        if #broken > 0 then
          local matched = match_broken_links(broken)
          if #matched > 0 then
            local names = {}
            for i, m in ipairs(matched) do
              if i > 10 then names[#names + 1] = "  ..." break end
              names[#names + 1] = "  " .. m.name
            end
            local ok = r.ShowMessageBox(string.format(
              "%d of %d broken scene link%s can be re-linked automatically\n"
              .. "(a scene with the same name and start position was found):\n\n%s\n\nRe-link now?",
              #matched, #broken, #broken == 1 and "" or "s", table.concat(names, "\n")),
              "PM Timer", 4)
            if ok == 6 then
              relinked = relink_items_to_scene(matched)
              broken = find_broken_scene_links()
            end
          end
        end
        S.broken_links = #broken
        local msg = string.format("%d %sscene%s checked, %d updated.",
          checked, any_selected and "selected " or "", checked == 1 and "" or "s", updated)
        if relinked > 0 then
          msg = msg .. string.format("\n%d work log item%s re-linked.", relinked, relinked == 1 and "" or "s")
        end
        if #broken > 0 then
          r.SelectAllMediaItems(0, false)
          for _, item in ipairs(broken) do r.SetMediaItemSelected(item, true) end
          r.UpdateArrange()
          msg = msg .. string.format("\n\n%d work log item%s link to a scene that no longer exists"
            .. " (e.g. after the Scene Cut was regenerated).\nThey are now selected so you can find them."
            .. "\n\nTo fix one: select it together with the right scene on Scene Cut,"
            .. "\nthen right-click PM Timer > Relink to Selected Scene.",
            #broken, #broken == 1 and "" or "s")
        end
        r.ShowMessageBox(msg, "PM Timer", 0)
      end
    elseif choice == 6 then
      -- Relink the selected work log item(s) to the one selected Scene Cut item
      local scene_track = get_track_by_name(SCENE_TRACK_NAME)
      local scenes, logs = {}, {}
      for i = 0, r.CountSelectedMediaItems(0) - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if scene_track and r.GetMediaItemTrack(item) == scene_track then
          scenes[#scenes + 1] = item
        else
          local take = r.GetActiveTake(item)
          if take and r.GetTakeName(take):find("|", 1, true) then logs[#logs + 1] = item end
        end
      end
      if #scenes ~= 1 or #logs == 0 then
        r.ShowMessageBox("Select exactly ONE scene on the Scene Cut track and the work log item(s)"
          .. " to link to it, then run Relink to Selected Scene again.", "PM Timer", 0)
      else
        local info = get_scene_info_from_item(scenes[1])
        local ok = r.ShowMessageBox(string.format("Link %d work log item%s to scene:\n\n  %s\n\nContinue?",
          #logs, #logs == 1 and "" or "s", info and info.name or "?"), "PM Timer", 1)
        if ok == 1 then
          local list = {}
          for _, item in ipairs(logs) do list[#list + 1] = { item = item, scene = scenes[1] } end
          relink_items_to_scene(list)
          S.broken_links = #find_broken_scene_links()
        end
      end
    elseif choice == 7 then
      action_link_split_scenes()
    elseif choice == 8 then
      check_project_name(true)
      sync_work_item_names()
      sync_all_prefixes()
    elseif choice == 9 then
      action_rename_project()
    elseif choice == 10 then
      action_merge_projects()
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
      auto_update_scenes()
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
    check_project_name()
    sync_work_item_names()
    sync_all_prefixes()
    sync_work_item_colors()
    auto_update_scenes()
    PM_SyncAllLogItems()
    PM_SyncProjectScopeNotes()
    auto_sync_work_log_if_open()
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
check_project_name()
sync_work_item_names()
sync_all_prefixes()
sync_work_item_colors()
auto_update_scenes()
PM_SyncAllLogItems()
PM_SyncProjectScopeNotes()
auto_sync_work_log_if_open()
last_draw_time = r.time_precise()
r.defer(loop)