--[[
@description Conform List Browser
@version 260206.1300
@author hsuanice
@about
  A REAPER script for browsing and editing EDL (Edit Decision List) data
  with a spreadsheet-style table UI, based on the Item List Browser framework.

  Reads CMX3600 EDL files, displays events in an editable table, and can
  generate empty items with metadata on REAPER tracks for conform workflows.

  Workflow:
    1. Load EDL file -> events display in table
    2. Browse, filter, sort, and edit metadata fields
    3. Load audio folder -> match files to EDL events by metadata
    4. Generate empty items on REAPER tracks at absolute TC positions
    5. Use a separate reconform script to relink original audio files

  Features:
    - CMX3600 EDL parser (TITLE, FCM, events, comments)
    - 15-column table: Event#, Reel, Track, Edit Type, Dissolve Len,
      Source TC In/Out, Record TC In/Out, Duration, Clip Name, Source File, Notes,
      Match Status, Matched File
    - All fields editable (except Event#, Duration, Match columns)
    - Excel-like selection (click, Shift+rectangle, Cmd/Ctrl multi-select)
    - Copy/Paste with TSV clipboard support
    - Multi-level sorting (click headers, Shift+click for secondary)
    - Text search filter (case-insensitive across all fields)
    - Audio file matching with BWF/iXML metadata support
    - Split-view UI for EDL events and audio files
    - Generate empty items on REAPER tracks with P_EXT metadata
    - Configurable track name format with token expansion
    - Absolute timecode positioning on REAPER timeline
    - Export edited EDL back to CMX3600 format
    - Font size adjustment (50% - 300%)
    - Column presets (save/load visible column configurations)

  Future: XML format support (Premiere, FCPX, FCP7, Resolve, Nuendo)

  Requires: ReaImGui (install via ReaPack)
  Optional: js_ReaScriptAPI (for folder selection)

@changelog
  v260206.1300
  - Feature: Conform Matched functionality
    • "Conform All" button: insert matched audio files as items
    • "Conform Sel" button: conform selected rows only
    • Multiple matches create multiple takes on the same item
    • Source offset calculated from EDL src_tc_in vs audio BWF TimeReference
    • Preserves metadata as P_EXT fields including matched file path
  - Note: Original "Generate Items" kept for empty item creation

  v260206.1230
  - Fix: Improved metadata reading for audio files
    • Check file type before reading metadata (WAV/AIFF/W64 only)
    • Convert BWF TimeReference (samples) to timecode string
    • Parse BWF Description for Scene/Take/Tape/Reel (EdiLoad format)
    • Reorganized audio table columns for conform workflow:
      Filename | Src TC | Scene | Take | Tape/Roll | Folder | Duration | SR | Ch | Project | Description

  v260206.1200
  - Feature: Audio file matching
    • "Load Audio..." button to select folder with audio files
    • Reads BWF/iXML metadata (scene, take, tape, reel, timereference, etc.)
    • Recursive folder scanning (configurable)
    • Auto-matching with multiple strategies:
      1. Clip name ↔ filename exact match
      2. Source file ↔ filename exact match
      3. Reel ↔ tape/reel metadata + partial name match
      4. Fuzzy partial name match
    • "Match All" button to re-run matching
    • "Clear Audio" button to reset audio panel
  - Feature: Split-view UI
    • Draggable splitter between EDL and Audio tables
    • Audio files table shows: filename, folder, duration, SR, channels,
      scene, take, tape, reel, timereference, description, project
    • Search filter for audio files
    • Progress indicator during async loading
  - Feature: New EDL columns
    • Match Status: "Found" / "Multiple" / "Not Found"
    • Matched File: shows matched audio file path

  v260203.2241
  - Feature: Remove Duplicates button in toolbar
    • Detects duplicates by composite key (track + rec TC in/out + clip name + reel)
    • Shows confirmation dialog with duplicate count before removing
    • Updates per-source event counts after removal
    • Supports undo/redo
  - Fix: Sources panel now scrollable when many EDLs are loaded
    • Wraps checkbox list in scrollable child region (max 6 visible rows)

  v260203.2216
  - Feature: Multi-file EDL selection in file dialog
    • Uses JS_Dialog_BrowseForOpenFiles for multi-select (shift/cmd-click)
    • Handles macOS (full paths) and Windows (directory + filenames) return formats
    • Falls back to single-file dialog if JS extension unavailable
  - Feature: EDL Sources panel with visibility filtering
    • "Sources >>" toggle button in toolbar shows/hides panel
    • Each loaded EDL listed with filename, event count, and checkbox
    • Show All / Hide All buttons for quick toggling
    • Unchecked sources are filtered from table display
  - Fix: Multi-file path parsing on macOS (was concatenating full paths as directory + filename)

  v260203.1854
  - Feature: Multiple EDL import support
    • Loading a second EDL when events already exist prompts Replace / Append / Cancel
    • Append adds new events to the existing list with unique GUIDs
  - Feature: Generated items now write Reel and Source TC In/Out to item notes
    • Human-readable format: "Reel: xxx / Src In: xx:xx:xx:xx / Src Out: xx:xx:xx:xx"
    • P_EXT metadata fields retained for programmatic access

  v260203.1845
  - Fix: Single vertical scrollbar (table only, no duplicate window scrollbar)
    • Window now uses NoScrollbar + NoScrollWithMouse flags
    • Table height correctly uses available height from GetContentRegionAvail
  - Fix: Selection highlight uses ImGui_Selectable instead of DrawList
    • Resolves ImGui_GetColumnWidth nil error and Missing EndTable cascade

  v260203.1500
  - Initial release: CMX3600 EDL parser, table UI, item generation, EDL export
--]]

---------------------------------------------------------------------------
-- Library loading
---------------------------------------------------------------------------
local info = debug.getinfo(1, "S")
local script_path = info.source:match("@?(.*[/\\])")
local lib_path = script_path:gsub("[/\\]Beta Testing[/\\]$", "/Library/")

-- EDL Parser
local EDL_PARSER_PATH = lib_path .. "hsuanice_EDL Parser.lua"
local ok_edl, EDL = pcall(dofile, EDL_PARSER_PATH)
if not ok_edl then
  reaper.ShowMessageBox(
    "Cannot load EDL Parser library.\n\nExpected at:\n" .. EDL_PARSER_PATH ..
    "\n\nError: " .. tostring(EDL),
    "Conform List Browser", 0)
  return
end

-- List Table (optional, for clipboard/export helpers)
local LT_PATH = lib_path .. "hsuanice_List Table.lua"
local ok_lt, LT = pcall(dofile, LT_PATH)
if not ok_lt then LT = nil end

-- Time Format (optional, for time display)
local TF_PATH = lib_path .. "hsuanice_Time Format.lua"
local ok_tf, TFLib = pcall(dofile, TF_PATH)
if not ok_tf then TFLib = nil end

-- Metadata Read (optional, for audio file metadata)
local META_PATH = lib_path .. "hsuanice_Metadata Read.lua"
local ok_meta, META = pcall(dofile, META_PATH)
if not ok_meta then META = nil end

---------------------------------------------------------------------------
-- ReaImGui check
---------------------------------------------------------------------------
if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox(
    "This script requires ReaImGui.\nPlease install it via ReaPack.",
    "Conform List Browser", 0)
  return
end

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local SCRIPT_NAME = "Conform List Browser"
local EXT_NS = "hsuanice_ConformListBrowser"
local VERSION = "260206.1300"

-- Column definitions (EDL Events table)
local COL = {
  EVENT        = 1,
  REEL         = 2,
  TRACK        = 3,
  EDIT_TYPE    = 4,
  DISS_LEN     = 5,
  SRC_IN       = 6,
  SRC_OUT      = 7,
  REC_IN       = 8,
  REC_OUT      = 9,
  DURATION     = 10,
  CLIP_NAME    = 11,
  SRC_FILE     = 12,
  NOTES        = 13,
  MATCH_STATUS = 14,
  MATCHED_PATH = 15,
}

local COL_COUNT = 15

-- Audio Files table column definitions (conform-focused order)
local AUDIO_COL = {
  FILENAME      = 1,
  SRC_TC        = 2,   -- Source timecode (from BWF TimeReference)
  SCENE         = 3,
  TAKE          = 4,
  TAPE          = 5,   -- Tape/Roll
  FOLDER        = 6,
  DURATION      = 7,
  SAMPLERATE    = 8,
  CHANNELS      = 9,
  PROJECT       = 10,
  DESCRIPTION   = 11,
}
local AUDIO_COL_COUNT = 11

local AUDIO_HEADER_LABELS = {
  [1]  = "Filename",
  [2]  = "Src TC",
  [3]  = "Scene",
  [4]  = "Take",
  [5]  = "Tape/Roll",
  [6]  = "Folder",
  [7]  = "Duration",
  [8]  = "SR",
  [9]  = "Ch",
  [10] = "Project",
  [11] = "Description",
}

local AUDIO_COL_WIDTH = {
  [1]  = 200,  -- Filename
  [2]  = 100,  -- Src TC
  [3]  = 80,   -- Scene
  [4]  = 50,   -- Take
  [5]  = 80,   -- Tape/Roll
  [6]  = 120,  -- Folder
  [7]  = 70,   -- Duration
  [8]  = 50,   -- SR
  [9]  = 30,   -- Ch
  [10] = 100,  -- Project
  [11] = 200,  -- Description
}

-- Audio file extensions
local AUDIO_EXTS = {
  wav = true, aif = true, aiff = true, flac = true, ogg = true,
  mp3 = true, caf = true, m4a = true, bwf = true, ogm = true, opus = true
}

local HEADER_LABELS = {
  [1]  = "#",
  [2]  = "Reel",
  [3]  = "Track",
  [4]  = "Edit",
  [5]  = "Diss",
  [6]  = "Src TC In",
  [7]  = "Src TC Out",
  [8]  = "Rec TC In",
  [9]  = "Rec TC Out",
  [10] = "Duration",
  [11] = "Clip Name",
  [12] = "Source File",
  [13] = "Notes",
  [14] = "Match",
  [15] = "Matched File",
}

local DEFAULT_COL_WIDTH = {
  [1]  = 40,
  [2]  = 100,
  [3]  = 50,
  [4]  = 45,
  [5]  = 45,
  [6]  = 100,
  [7]  = 100,
  [8]  = 100,
  [9]  = 100,
  [10] = 85,
  [11] = 300,
  [12] = 300,
  [13] = 200,
  [14] = 70,
  [15] = 250,
}

-- Editable columns (all except Event# and Duration)
local EDITABLE_COLS = {
  [COL.REEL] = true,
  [COL.TRACK] = true,
  [COL.EDIT_TYPE] = true,
  [COL.DISS_LEN] = true,
  [COL.SRC_IN] = true,
  [COL.SRC_OUT] = true,
  [COL.REC_IN] = true,
  [COL.REC_OUT] = true,
  [COL.CLIP_NAME] = true,
  [COL.SRC_FILE] = true,
  [COL.NOTES] = true,
}

-- TC columns (need TC validation)
local TC_COLS = {
  [COL.SRC_IN] = true,
  [COL.SRC_OUT] = true,
  [COL.REC_IN] = true,
  [COL.REC_OUT] = true,
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local ctx -- ImGui context
local list_clipper

local CLB = {
  -- File state
  loaded_file = nil,
  loaded_format = nil,
  parsed_data = nil,

  -- EDL source tracking: { { name, path, event_count, visible }, ... }
  edl_sources = {},

  -- Table state
  search_text = "",
  scroll_to_row = nil,
  visible_range = { first = 0, last = 0 },
  cached_rows = nil,
  cached_rows_frame = -1,

  -- Settings
  fps = 25,
  is_drop = false,
  track_name_format = "${format} - ${track}",
  last_dir = "",
  last_audio_dir = "",

  -- UI state
  frame_counter = 0,
  show_sources_panel = false,
  show_track_filter = false,
  track_filters = {},  -- { { name, count, visible }, ... }

  -- Audio file matching state
  audio_files = {},           -- { {path, filename, basename, folder, metadata={}}, ... }
  audio_folder = "",          -- Loaded audio folder path
  audio_recursive = true,     -- Recursive search enabled
  show_audio_panel = false,   -- Show audio panel (auto-enabled when files loaded)
  split_ratio = 0.5,          -- Split ratio for EDL/Audio tables (0.3~0.7)
  audio_search = "",          -- Audio table search filter
  audio_cached = nil,         -- Cached filtered audio files
  audio_cached_frame = -1,    -- Frame number of cached audio files

  -- Loading state (for async loading with progress)
  loading_state = nil,        -- { phase, total, current, files }

  -- Match picker state
  match_picker_row = nil,     -- Row being matched (for multi-match selection)
}

local ROWS = {}    -- Array of row tables
local EDIT = nil   -- { row_idx, col_id, buf, want_focus }

-- Selection model
local SEL = {
  cells = {},             -- set: ["guid:col_id"] = true
  anchor = nil,           -- { guid, col } or nil
}

-- Sort state
local SORT_STATE = {
  columns = {},           -- Array of { col_id, ascending }
}

-- Console
local CONSOLE = { enabled = false }
local DEBUG = false

-- Undo stack (in-memory, for table edits)
local UNDO_STACK = {}
local UNDO_POS = 0
local MAX_UNDO = 100

-- Font
local current_font_size = 13
local font_pushed_this_frame = false
local FONT_SCALE = 1.0
local ALLOW_DOCKING = false

---------------------------------------------------------------------------
-- Font size
---------------------------------------------------------------------------
local function set_font_size(size)
  current_font_size = size or 13
end

local function get_ui_scale()
  return current_font_size / 13.0
end

local function scale(value)
  return math.floor(value * get_ui_scale())
end

---------------------------------------------------------------------------
-- Console helpers
---------------------------------------------------------------------------
local function console_msg(msg)
  if CONSOLE.enabled then
    reaper.ShowConsoleMsg("[CLB] " .. tostring(msg) .. "\n")
  end
end

---------------------------------------------------------------------------
-- Audio file utilities
---------------------------------------------------------------------------

--- Check if a filename has an audio extension
local function is_audio(filename)
  if not filename or filename == "" then return false end
  local ext = filename:match("%.([%w]+)$")
  if not ext then return false end
  ext = ext:lower()
  -- Exclude common non-audio files
  if ext == "ds_store" or ext == "pdf" or ext == "txt" then return false end
  return AUDIO_EXTS[ext] == true
end

--- Get basename (filename without extension)
local function get_basename(filename)
  if not filename or filename == "" then return "" end
  -- Extract filename from path if needed
  local name = filename:match("([^/\\]+)$") or filename
  -- Remove extension
  return name:gsub("%.[^%.]+$", "")
end

--- Get folder name from full path
local function get_folder(filepath)
  if not filepath or filepath == "" then return "" end
  local folder = filepath:match("^(.*)[/\\][^/\\]+$") or ""
  return folder
end

--- Join path components
local function join_path(dir, file)
  if not dir or dir == "" then return file or "" end
  if not file or file == "" then return dir end
  if dir:match("[/\\]$") then
    return dir .. file
  else
    return dir .. "/" .. file
  end
end

--- Scan audio folder and return list of audio files
--- @param base_path string  Base folder path
--- @param recursive boolean  Whether to search recursively
--- @return table  Array of { path, filename, basename, folder }
local function scan_audio_folder(base_path, recursive)
  if not base_path or base_path == "" then return {} end

  local files = {}

  local function scan_dir(dir, rel_folder)
    -- Enumerate files in directory
    local i = 0
    while true do
      local fn = reaper.EnumerateFiles(dir, i)
      if not fn then break end
      if is_audio(fn) then
        files[#files + 1] = {
          path = join_path(dir, fn),
          filename = fn,
          basename = get_basename(fn),
          folder = rel_folder or "",
          metadata = {},  -- Will be filled later
        }
      end
      i = i + 1
    end

    -- Enumerate subdirectories if recursive
    if recursive then
      i = 0
      while true do
        local sd = reaper.EnumerateSubdirectories(dir, i)
        if not sd then break end
        local new_rel = (rel_folder and rel_folder ~= "") and (rel_folder .. "/" .. sd) or sd
        scan_dir(join_path(dir, sd), new_rel)
        i = i + 1
      end
    end
  end

  scan_dir(base_path, "")

  -- Sort by filename
  table.sort(files, function(a, b)
    return (a.filename or ""):lower() < (b.filename or ""):lower()
  end)

  return files
end

--- Convert TimeReference (samples) to timecode string
--- @param samples number|string  Sample count
--- @param samplerate number  Sample rate
--- @param fps number  Frame rate (default 25)
--- @return string  Timecode "HH:MM:SS:FF"
local function samples_to_tc(samples, samplerate, fps)
  samples = tonumber(samples) or 0
  samplerate = samplerate or 48000
  fps = fps or 25
  if samples <= 0 or samplerate <= 0 then return "" end

  local seconds = samples / samplerate
  local total_frames = math.floor(seconds * fps + 0.5)
  local f = total_frames % fps
  local total_secs = math.floor(total_frames / fps)
  local s = total_secs % 60
  local total_mins = math.floor(total_secs / 60)
  local m = total_mins % 60
  local h = math.floor(total_mins / 60)

  return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
end

--- Parse BWF Description key=value pairs
--- @param desc string  BWF Description text
--- @return table  Parsed key-value pairs
local function parse_bwf_description(desc)
  local result = {}
  if not desc or desc == "" then return result end

  for line in (desc .. "\n"):gmatch("(.-)\n") do
    local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if k and v and k ~= "" then
      result[k] = v
      result[k:lower()] = v
      result[k:upper()] = v
      -- Map dXXXX/sXXXX → XXXX (EdiLoad style)
      local base = k:upper():match("^[SD]([A-Z0-9_]+)$")
      if base then
        result[base] = v
        result[base:lower()] = v
      end
    end
  end
  return result
end

--- Read metadata from an external audio file
--- @param filepath string  Full path to audio file
--- @return table  Metadata table
local function read_audio_metadata(filepath)
  local meta = {
    samplerate = 0,
    channels = 0,
    duration = 0,
    scene = "",
    take = "",
    tape = "",
    reel = "",
    project = "",
    timereference = "",      -- raw samples
    src_tc = "",             -- converted timecode
    description = "",
    originator = "",
    bwf_fields = {},         -- parsed BWF Description fields
  }

  if not filepath or filepath == "" then return meta end

  -- Create temporary PCM source from file
  local src = reaper.PCM_Source_CreateFromFile(filepath)
  if not src then return meta end

  -- Check if file type supports metadata (WAV/AIFF/W64)
  local srctype = reaper.GetMediaSourceType(src, "") or ""
  local upper = srctype:upper()
  local can_meta = upper:find("WAVE") or upper:find("AIFF") or upper:find("W64") or upper:find("WAV")

  -- Read basic info
  meta.samplerate = reaper.GetMediaSourceSampleRate(src) or 0
  meta.channels = reaper.GetMediaSourceNumChannels(src) or 0
  local len, _ = reaper.GetMediaSourceLength(src)
  meta.duration = len or 0

  if can_meta then
    -- Helper to read metadata
    local function get_meta(key)
      local ok, val = reaper.GetMediaFileMetadata(src, key)
      return (ok == 1 and val ~= "") and val or nil
    end

    -- Read iXML metadata
    meta.scene = get_meta("IXML:SCENE") or ""
    meta.take = get_meta("IXML:TAKE") or ""
    meta.tape = get_meta("IXML:TAPE") or ""
    meta.project = get_meta("IXML:PROJECT") or ""

    -- Read BWF metadata
    meta.timereference = get_meta("BWF:TimeReference") or ""
    meta.description = get_meta("BWF:Description") or ""
    meta.originator = get_meta("BWF:Originator") or ""

    -- Convert TimeReference to timecode (using file's sample rate and default 25fps)
    if meta.timereference ~= "" and meta.samplerate > 0 then
      meta.src_tc = samples_to_tc(meta.timereference, meta.samplerate, CLB.fps or 25)
    end

    -- Parse BWF Description for key=value pairs
    if meta.description ~= "" then
      meta.bwf_fields = parse_bwf_description(meta.description)

      -- Extract reel from description (sTRK#/dREEL format)
      meta.reel = meta.bwf_fields["REEL"]
               or meta.bwf_fields["sREEL"]
               or meta.bwf_fields["dREEL"]
               or ""

      -- Also try SCENE, TAKE, TAPE from BWF if iXML was empty
      if meta.scene == "" then meta.scene = meta.bwf_fields["SCENE"] or meta.bwf_fields["sSCENE"] or "" end
      if meta.take == ""  then meta.take  = meta.bwf_fields["TAKE"]  or meta.bwf_fields["sTAKE"]  or "" end
      if meta.tape == ""  then meta.tape  = meta.bwf_fields["TAPE"]  or meta.bwf_fields["sTAPE"]  or "" end
    end

    -- If no reel from description, try tape as reel
    if meta.reel == "" and meta.tape ~= "" then
      meta.reel = meta.tape
    end
  end

  -- Destroy temporary source
  reaper.PCM_Source_Destroy(src)

  return meta
end

--- Format duration as HH:MM:SS or MM:SS
local function format_duration(seconds)
  if not seconds or seconds <= 0 then return "00:00" end
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = math.floor(seconds % 60)
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  else
    return string.format("%d:%02d", m, s)
  end
end

--- Format sample rate as "48k" style
local function format_samplerate(sr)
  if not sr or sr <= 0 then return "" end
  if sr >= 1000 then
    return string.format("%.0fk", sr / 1000)
  end
  return tostring(sr)
end

---------------------------------------------------------------------------
-- Audio matching
---------------------------------------------------------------------------

--- Clear all match results from ROWS
local function clear_match_results()
  for _, row in ipairs(ROWS) do
    row.match_status = ""
    row.matched_path = ""
    row.__match_candidates = nil
  end
  CLB.cached_rows = nil
  CLB.cached_rows_frame = -1
end

--- Match audio files to EDL events
local function match_audio_files()
  if #CLB.audio_files == 0 or #ROWS == 0 then return end

  console_msg("Starting audio matching...")

  -- Build audio file indexes
  local by_basename = {}   -- filename (lowercase, no ext) → {audio_file, ...}
  local by_tape = {}       -- tape/reel metadata → {audio_file, ...}

  for _, af in ipairs(CLB.audio_files) do
    -- Index by basename
    local base = (af.basename or ""):lower()
    if base ~= "" then
      by_basename[base] = by_basename[base] or {}
      by_basename[base][#by_basename[base] + 1] = af
    end

    -- Index by tape/reel metadata
    local tape = ""
    if af.metadata then
      tape = (af.metadata.tape or af.metadata.reel or ""):lower()
    end
    if tape ~= "" then
      by_tape[tape] = by_tape[tape] or {}
      by_tape[tape][#by_tape[tape] + 1] = af
    end
  end

  -- Match each EDL row
  local found_count = 0
  local multiple_count = 0
  local not_found_count = 0

  for _, row in ipairs(ROWS) do
    local candidates = {}

    -- Strategy 1: clip_name exact match (ignoring extension)
    local clip_base = get_basename(row.clip_name or ""):lower()
    if clip_base ~= "" and by_basename[clip_base] then
      for _, af in ipairs(by_basename[clip_base]) do
        candidates[#candidates + 1] = af
      end
    end

    -- Strategy 2: source_file exact match (if strategy 1 found nothing)
    if #candidates == 0 then
      local src_base = get_basename(row.source_file or ""):lower()
      if src_base ~= "" and by_basename[src_base] then
        for _, af in ipairs(by_basename[src_base]) do
          candidates[#candidates + 1] = af
        end
      end
    end

    -- Strategy 3: reel ↔ tape match + clip_name partial match
    if #candidates == 0 and row.reel and row.reel ~= "" then
      local reel_lower = row.reel:lower()
      local tape_files = by_tape[reel_lower] or {}
      for _, af in ipairs(tape_files) do
        local af_base = (af.basename or ""):lower()
        -- Check if clip_name is contained in audio filename or vice versa
        if clip_base ~= "" and (af_base:find(clip_base, 1, true) or clip_base:find(af_base, 1, true)) then
          candidates[#candidates + 1] = af
        end
      end
    end

    -- Strategy 4: Fuzzy match - clip_name partial match in all files
    if #candidates == 0 and clip_base ~= "" and #clip_base >= 3 then
      for _, af in ipairs(CLB.audio_files) do
        local af_base = (af.basename or ""):lower()
        if af_base:find(clip_base, 1, true) then
          candidates[#candidates + 1] = af
        end
      end
    end

    -- Set match result
    if #candidates == 1 then
      row.match_status = "Found"
      row.matched_path = candidates[1].path
      row.__match_candidates = nil
      found_count = found_count + 1
    elseif #candidates > 1 then
      row.match_status = "Multiple"
      row.matched_path = string.format("(%d)", #candidates)
      row.__match_candidates = candidates
      multiple_count = multiple_count + 1
    else
      row.match_status = "Not Found"
      row.matched_path = ""
      row.__match_candidates = nil
      not_found_count = not_found_count + 1
    end
  end

  CLB.cached_rows = nil
  CLB.cached_rows_frame = -1

  console_msg(string.format("Matching complete: %d found, %d multiple, %d not found",
    found_count, multiple_count, not_found_count))
end

--- Get filtered audio files for display
local function get_audio_view_rows()
  local frame = CLB.frame_counter
  if CLB.audio_cached and CLB.audio_cached_frame == frame then
    return CLB.audio_cached
  end

  local search = (CLB.audio_search or ""):lower()
  if search == "" then
    CLB.audio_cached = CLB.audio_files
  else
    local filtered = {}
    for _, af in ipairs(CLB.audio_files) do
      -- Search in filename and metadata
      local searchable = (af.filename or "") .. " " ..
        (af.folder or "") .. " " ..
        (af.metadata and af.metadata.scene or "") .. " " ..
        (af.metadata and af.metadata.take or "") .. " " ..
        (af.metadata and af.metadata.tape or "")
      if searchable:lower():find(search, 1, true) then
        filtered[#filtered + 1] = af
      end
    end
    CLB.audio_cached = filtered
  end

  CLB.audio_cached_frame = frame
  return CLB.audio_cached
end

---------------------------------------------------------------------------
-- Column widths
---------------------------------------------------------------------------
local COL_WIDTH = {}
for k, v in pairs(DEFAULT_COL_WIDTH) do
  COL_WIDTH[k] = v
end

---------------------------------------------------------------------------
-- Preferences
---------------------------------------------------------------------------
local function save_prefs()
  reaper.SetExtState(EXT_NS, "font_scale", tostring(FONT_SCALE or 1.0), true)
  reaper.SetExtState(EXT_NS, "fps", tostring(CLB.fps or 25), true)
  reaper.SetExtState(EXT_NS, "track_name_format", CLB.track_name_format or "${format} - ${track}", true)
  reaper.SetExtState(EXT_NS, "last_dir", CLB.last_dir or "", true)
  reaper.SetExtState(EXT_NS, "last_audio_dir", CLB.last_audio_dir or "", true)
  reaper.SetExtState(EXT_NS, "audio_recursive", CLB.audio_recursive and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "split_ratio", tostring(CLB.split_ratio or 0.5), true)
  reaper.SetExtState(EXT_NS, "console_output", CONSOLE.enabled and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "debug_mode", DEBUG and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "allow_docking", ALLOW_DOCKING and "1" or "0", true)
end

local function load_prefs()
  local function get(key, default)
    if reaper.HasExtState(EXT_NS, key) then
      return reaper.GetExtState(EXT_NS, key)
    end
    return default
  end

  FONT_SCALE = tonumber(get("font_scale", "1.0")) or 1.0
  CLB.fps = tonumber(get("fps", "25")) or 25
  CLB.track_name_format = get("track_name_format", "${format} - ${track}")
  CLB.last_dir = get("last_dir", "")
  CLB.last_audio_dir = get("last_audio_dir", "")
  CLB.audio_recursive = get("audio_recursive", "1") == "1"
  CLB.split_ratio = tonumber(get("split_ratio", "0.5")) or 0.5
  CONSOLE.enabled = get("console_output", "0") == "1"
  DEBUG = get("debug_mode", "0") == "1"
  ALLOW_DOCKING = get("allow_docking", "0") == "1"

  -- Apply font
  set_font_size(math.floor(13 * FONT_SCALE))
end

---------------------------------------------------------------------------
-- Selection helpers
---------------------------------------------------------------------------
local function sel_key(guid, col_id)
  return guid .. ":" .. tostring(col_id)
end

local function sel_clear()
  SEL.cells = {}
  SEL.anchor = nil
end

local function sel_add(guid, col_id)
  SEL.cells[sel_key(guid, col_id)] = true
end

local function sel_remove(guid, col_id)
  SEL.cells[sel_key(guid, col_id)] = nil
end

local function sel_has(guid, col_id)
  return SEL.cells[sel_key(guid, col_id)] == true
end

local function sel_toggle(guid, col_id)
  local k = sel_key(guid, col_id)
  if SEL.cells[k] then
    SEL.cells[k] = nil
  else
    SEL.cells[k] = true
  end
end

local function sel_set_single(guid, col_id)
  sel_clear()
  sel_add(guid, col_id)
  SEL.anchor = { guid = guid, col = col_id }
end

-- Rectangle selection (Shift+Click)
local function sel_rect(guid_from, col_from, guid_to, col_to)
  -- Find row indices
  local idx_from, idx_to
  for i, row in ipairs(ROWS) do
    if row.__guid == guid_from then idx_from = i end
    if row.__guid == guid_to then idx_to = i end
  end
  if not idx_from or not idx_to then return end

  local r1, r2 = math.min(idx_from, idx_to), math.max(idx_from, idx_to)
  local c1, c2 = math.min(col_from, col_to), math.max(col_from, col_to)

  sel_clear()
  for i = r1, r2 do
    for c = c1, c2 do
      sel_add(ROWS[i].__guid, c)
    end
  end
end

---------------------------------------------------------------------------
-- Undo stack (in-memory, for table edits)
---------------------------------------------------------------------------
local function undo_snapshot()
  -- Deep copy current ROWS data (only editable fields)
  local snapshot = {}
  for i, row in ipairs(ROWS) do
    snapshot[i] = {
      reel = row.reel,
      track = row.track,
      edit_type = row.edit_type,
      dissolve_len = row.dissolve_len,
      src_tc_in = row.src_tc_in,
      src_tc_out = row.src_tc_out,
      rec_tc_in = row.rec_tc_in,
      rec_tc_out = row.rec_tc_out,
      clip_name = row.clip_name,
      source_file = row.source_file,
      notes = row.notes,
    }
  end

  -- Trim redo history
  while #UNDO_STACK > UNDO_POS do
    table.remove(UNDO_STACK)
  end

  UNDO_STACK[#UNDO_STACK + 1] = snapshot
  if #UNDO_STACK > MAX_UNDO then
    table.remove(UNDO_STACK, 1)
  end
  UNDO_POS = #UNDO_STACK
end

local function undo_restore(snapshot)
  for i, saved in ipairs(snapshot) do
    if ROWS[i] then
      for k, v in pairs(saved) do
        ROWS[i][k] = v
      end
      -- Recompute duration
      local ri_sec = EDL.tc_to_seconds(ROWS[i].rec_tc_in, CLB.fps, CLB.is_drop)
      local ro_sec = EDL.tc_to_seconds(ROWS[i].rec_tc_out, CLB.fps, CLB.is_drop)
      ROWS[i].duration = EDL.seconds_to_tc(ro_sec - ri_sec, CLB.fps, CLB.is_drop)
      -- Rebuild search text
      ROWS[i].__search_text = table.concat({
        ROWS[i].event_num or "", ROWS[i].reel or "", ROWS[i].track or "",
        ROWS[i].clip_name or "", ROWS[i].source_file or "", ROWS[i].notes or "",
      }, " "):lower()
    end
  end
end

local function do_undo()
  if UNDO_POS <= 1 then return end
  UNDO_POS = UNDO_POS - 1
  undo_restore(UNDO_STACK[UNDO_POS])
  CLB.cached_rows = nil; CLB.cached_rows_frame = -1
  console_msg("Undo")
end

local function do_redo()
  if UNDO_POS >= #UNDO_STACK then return end
  UNDO_POS = UNDO_POS + 1
  undo_restore(UNDO_STACK[UNDO_POS])
  CLB.cached_rows = nil; CLB.cached_rows_frame = -1
  console_msg("Redo")
end

---------------------------------------------------------------------------
-- Row data helpers
---------------------------------------------------------------------------

-- Get cell text for display
local function get_cell_text(row, col_id)
  if not row then return "" end
  if col_id == COL.EVENT        then return row.event_num or "" end
  if col_id == COL.REEL         then return row.reel or "" end
  if col_id == COL.TRACK        then return row.track or "" end
  if col_id == COL.EDIT_TYPE    then return row.edit_type or "" end
  if col_id == COL.DISS_LEN     then
    return row.dissolve_len and tostring(row.dissolve_len) or ""
  end
  if col_id == COL.SRC_IN       then return row.src_tc_in or "" end
  if col_id == COL.SRC_OUT      then return row.src_tc_out or "" end
  if col_id == COL.REC_IN       then return row.rec_tc_in or "" end
  if col_id == COL.REC_OUT      then return row.rec_tc_out or "" end
  if col_id == COL.DURATION     then return row.duration or "" end
  if col_id == COL.CLIP_NAME    then return row.clip_name or "" end
  if col_id == COL.SRC_FILE     then return row.source_file or "" end
  if col_id == COL.NOTES        then return row.notes or "" end
  if col_id == COL.MATCH_STATUS then return row.match_status or "" end
  if col_id == COL.MATCHED_PATH then
    -- Show just filename for display, full path in tooltip
    if row.matched_path and row.matched_path ~= "" then
      return row.matched_path:match("([^/\\]+)$") or row.matched_path
    end
    return ""
  end
  return ""
end

-- Set cell value (with undo)
local function set_cell_value(row, col_id, value)
  if not row or not EDITABLE_COLS[col_id] then return false end

  if col_id == COL.REEL      then row.reel = value
  elseif col_id == COL.TRACK     then row.track = value
  elseif col_id == COL.EDIT_TYPE then row.edit_type = value
  elseif col_id == COL.DISS_LEN  then row.dissolve_len = tonumber(value)
  elseif col_id == COL.SRC_IN    then row.src_tc_in = value
  elseif col_id == COL.SRC_OUT   then row.src_tc_out = value
  elseif col_id == COL.REC_IN    then row.rec_tc_in = value
  elseif col_id == COL.REC_OUT   then row.rec_tc_out = value
  elseif col_id == COL.CLIP_NAME then row.clip_name = value
  elseif col_id == COL.SRC_FILE  then row.source_file = value
  elseif col_id == COL.NOTES     then row.notes = value
  else return false end

  -- Recompute duration if TC changed
  if TC_COLS[col_id] then
    local ri_sec = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
    local ro_sec = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
    row.duration = EDL.seconds_to_tc(ro_sec - ri_sec, CLB.fps, CLB.is_drop)
  end

  -- Rebuild search text
  row.__search_text = table.concat({
    row.event_num or "", row.reel or "", row.track or "",
    row.clip_name or "", row.source_file or "", row.notes or "",
  }, " "):lower()

  return true
end

-- Get sort value for sorting
local function get_sort_value(row, col_id)
  if not row then return "" end
  local val = get_cell_text(row, col_id)
  -- TC columns: convert to seconds for numeric sort
  if TC_COLS[col_id] or col_id == COL.DURATION then
    return EDL.tc_to_seconds(val, CLB.fps, CLB.is_drop)
  end
  -- Event#: numeric
  if col_id == COL.EVENT then return tonumber(val) or 0 end
  -- Dissolve len: numeric
  if col_id == COL.DISS_LEN then return tonumber(val) or 0 end
  return val:lower()
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------
local function sort_rows()
  if #SORT_STATE.columns == 0 then return end

  table.sort(ROWS, function(a, b)
    for _, sc in ipairs(SORT_STATE.columns) do
      local va = get_sort_value(a, sc.col_id)
      local vb = get_sort_value(b, sc.col_id)
      if va ~= vb then
        if sc.ascending then
          return va < vb
        else
          return va > vb
        end
      end
    end
    return false
  end)

  CLB.cached_rows = nil; CLB.cached_rows_frame = -1
end

local function toggle_sort(col_id, add_level)
  if add_level then
    -- Shift+Click: add or toggle existing level
    for _, sc in ipairs(SORT_STATE.columns) do
      if sc.col_id == col_id then
        sc.ascending = not sc.ascending
        sort_rows()
        return
      end
    end
    SORT_STATE.columns[#SORT_STATE.columns + 1] = { col_id = col_id, ascending = true }
  else
    -- Click: replace sort
    local was_asc = nil
    if #SORT_STATE.columns == 1 and SORT_STATE.columns[1].col_id == col_id then
      was_asc = SORT_STATE.columns[1].ascending
    end
    SORT_STATE.columns = { { col_id = col_id, ascending = was_asc == nil and true or not was_asc } }
  end
  sort_rows()
end

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------
local function get_view_rows()
  local frame = CLB.frame_counter
  if CLB.cached_rows and CLB.cached_rows_frame == frame then
    return CLB.cached_rows
  end

  -- Build hidden source index set
  local hidden_src_idx = nil
  for i, src in ipairs(CLB.edl_sources) do
    if not src.visible then
      hidden_src_idx = hidden_src_idx or {}
      hidden_src_idx[i] = true
    end
  end

  -- Build hidden track set
  local hidden_tracks = nil
  for _, tf in ipairs(CLB.track_filters) do
    if not tf.visible then
      hidden_tracks = hidden_tracks or {}
      hidden_tracks[tf.name] = true
    end
  end

  local search = CLB.search_text:lower()
  local need_filter = search ~= "" or hidden_src_idx or hidden_tracks

  if not need_filter then
    CLB.cached_rows = ROWS
  else
    local filtered = {}
    for _, row in ipairs(ROWS) do
      -- Source visibility filter
      if hidden_src_idx and hidden_src_idx[row.__source_idx] then
        goto skip
      end
      -- Track visibility filter
      if hidden_tracks and hidden_tracks[row.track or ""] then
        goto skip
      end
      -- Search filter
      if search ~= "" then
        if not (row.__search_text and row.__search_text:find(search, 1, true)) then
          goto skip
        end
      end
      filtered[#filtered + 1] = row
      ::skip::
    end
    CLB.cached_rows = filtered
  end

  CLB.cached_rows_frame = frame
  return CLB.cached_rows
end

---------------------------------------------------------------------------
-- File loading
---------------------------------------------------------------------------
-- GUID counter for unique row IDs across multiple imports
local _guid_counter = 0

local function _make_rows_from_events(events, fps, is_drop, source_idx)
  local new_rows = {}
  for _, evt in ipairs(events) do
    _guid_counter = _guid_counter + 1
    local row = {
      __event_idx = _guid_counter,
      __guid = string.format("clb_%06d", _guid_counter),
      __source_idx = source_idx or 0,

      event_num = evt.event_num or string.format("%03d", _guid_counter),
      reel = evt.reel or "",
      track = evt.track or "",
      edit_type = evt.edit_type or "C",
      dissolve_len = evt.dissolve_len,
      src_tc_in = evt.src_tc_in or "00:00:00:00",
      src_tc_out = evt.src_tc_out or "00:00:00:00",
      rec_tc_in = evt.rec_tc_in or "00:00:00:00",
      rec_tc_out = evt.rec_tc_out or "00:00:00:00",
      clip_name = evt.clip_name or "",
      source_file = evt.source_file or "",
      notes = "",

      duration = evt.duration_tc or EDL.seconds_to_tc(
        EDL.tc_to_seconds(evt.rec_tc_out or "00:00:00:00", fps, is_drop)
        - EDL.tc_to_seconds(evt.rec_tc_in or "00:00:00:00", fps, is_drop),
        fps, is_drop),
    }

    row.__search_text = table.concat({
      row.event_num, row.reel, row.track,
      row.clip_name, row.source_file, row.notes,
    }, " "):lower()

    new_rows[#new_rows + 1] = row
  end
  return new_rows
end

--- Register an EDL source and return its index.
local function _register_source(filepath, event_count)
  local name = filepath:match("([^/\\]+)$") or filepath
  local idx = #CLB.edl_sources + 1
  CLB.edl_sources[idx] = {
    name = name,
    path = filepath,
    event_count = event_count,
    visible = true,
  }
  return idx
end

--- Rebuild track filter list from current ROWS.
local function _rebuild_track_filters()
  local track_counts = {}
  local track_order = {}
  for _, row in ipairs(ROWS) do
    local t = row.track or ""
    if not track_counts[t] then
      track_counts[t] = 0
      track_order[#track_order + 1] = t
    end
    track_counts[t] = track_counts[t] + 1
  end
  table.sort(track_order)

  -- Preserve existing visibility
  local old_vis = {}
  for _, tf in ipairs(CLB.track_filters) do
    old_vis[tf.name] = tf.visible
  end

  CLB.track_filters = {}
  for _, name in ipairs(track_order) do
    CLB.track_filters[#CLB.track_filters + 1] = {
      name = name,
      count = track_counts[name],
      visible = old_vis[name] == nil or old_vis[name],
    }
  end
end

-- Replace all rows (fresh load)
local function build_rows_from_parsed(parsed, source_path)
  ROWS = {}
  _guid_counter = 0
  CLB.edl_sources = {}
  CLB.track_filters = {}
  if not parsed or not parsed.events then return end

  CLB.fps = parsed.fps or 25
  CLB.is_drop = parsed.is_drop or false

  local src_idx = _register_source(
    source_path or parsed.source_path or "?", #parsed.events)
  ROWS = _make_rows_from_events(parsed.events, CLB.fps, CLB.is_drop, src_idx)

  sel_clear()
  EDIT = nil
  SORT_STATE.columns = {}
  UNDO_STACK = {}
  UNDO_POS = 0
  undo_snapshot()
  _rebuild_track_filters()
  CLB.cached_rows = nil; CLB.cached_rows_frame = -1

  console_msg(string.format("Loaded %d events from %s",
    #ROWS, CLB.edl_sources[src_idx].name))
end

-- Append rows from additional EDL (keeps existing rows)
local function append_rows_from_parsed(parsed, source_path)
  if not parsed or not parsed.events then return end

  local src_idx = _register_source(
    source_path or parsed.source_path or "?", #parsed.events)
  local new_rows = _make_rows_from_events(
    parsed.events, CLB.fps, CLB.is_drop, src_idx)
  for _, row in ipairs(new_rows) do
    ROWS[#ROWS + 1] = row
  end

  undo_snapshot()
  _rebuild_track_filters()
  CLB.cached_rows = nil; CLB.cached_rows_frame = -1

  console_msg(string.format("Appended %d events from %s (total: %d)",
    #new_rows, CLB.edl_sources[src_idx].name, #ROWS))
end

local function load_edl_file()
  -- Collect file paths (multi-select via JS extension, fallback to single)
  local filepaths = {}

  if reaper.JS_Dialog_BrowseForOpenFiles then
    -- JS extension available: multi-select file dialog
    local rv, filestr = reaper.JS_Dialog_BrowseForOpenFiles(
      "Open EDL Files", CLB.last_dir or "", "", "EDL files\0*.edl\0All files\0*.*\0", true)
    if rv ~= 1 or not filestr or filestr == "" then return end

    -- Parse null-separated result
    local parts = {}
    for part in (filestr .. "\0"):gmatch("([^\0]*)\0") do
      if part ~= "" then parts[#parts + 1] = part end
    end

    if #parts == 1 then
      -- Single file selected (full path returned directly)
      filepaths[1] = parts[1]
    elseif #parts > 1 then
      -- macOS returns all full paths; Windows returns directory + filenames
      -- Detect: if second part starts with "/" or drive letter, all are full paths
      if parts[2]:match("^/") or parts[2]:match("^%a:\\") then
        -- All full paths (macOS behavior)
        for i = 1, #parts do
          filepaths[#filepaths + 1] = parts[i]
        end
      else
        -- First part is directory, rest are filenames (Windows behavior)
        local dir = parts[1]
        if not dir:match("[/\\]$") then dir = dir .. "/" end
        for i = 2, #parts do
          filepaths[#filepaths + 1] = dir .. parts[i]
        end
      end
    end
  else
    -- Fallback: single file dialog
    local retval, filepath = reaper.GetUserFileNameForRead("", "Open EDL File", "*.edl")
    if not retval or filepath == "" then return end
    filepaths[1] = filepath
  end

  if #filepaths == 0 then return end

  -- Parse all selected EDL files
  local all_parsed = {}  -- { { parsed=..., path=... }, ... }
  local errors = {}
  for _, fp in ipairs(filepaths) do
    local parsed, err = EDL.parse(fp, { default_fps = CLB.fps })
    if parsed then
      all_parsed[#all_parsed + 1] = { parsed = parsed, path = fp }
    else
      errors[#errors + 1] = (fp:match("([^/\\]+)$") or fp) .. ": " .. tostring(err)
    end
  end

  -- Report any parse errors
  if #errors > 0 then
    reaper.ShowMessageBox(
      "Failed to parse " .. #errors .. " file(s):\n\n" .. table.concat(errors, "\n"),
      SCRIPT_NAME, 0)
  end
  if #all_parsed == 0 then return end

  -- Remember directory
  CLB.last_dir = filepaths[1]:match("(.*[/\\])") or ""
  save_prefs()

  -- Count total events
  local total_events = 0
  for _, ap in ipairs(all_parsed) do total_events = total_events + #ap.parsed.events end

  -- If rows already loaded, ask Replace or Append
  if #ROWS > 0 then
    local file_desc = #filepaths == 1
      and (filepaths[1]:match("([^/\\]+)$") or filepaths[1])
      or (#filepaths .. " files")

    local choice = reaper.ShowMessageBox(
      string.format(
        "Current list has %d events.\n\n" ..
        "Loading: %s (%d events)\n\n" ..
        "Yes = Replace (clear current list)\n" ..
        "No = Append (add to current list)",
        #ROWS, file_desc, total_events),
      SCRIPT_NAME, 3)  -- 3 = Yes/No/Cancel

    if choice == 2 then return end  -- Cancel

    if choice == 6 then
      -- Yes = Replace
      CLB.loaded_file = #filepaths == 1 and filepaths[1] or nil
      CLB.loaded_format = "EDL"
      CLB.parsed_data = all_parsed[1].parsed
      build_rows_from_parsed(all_parsed[1].parsed, all_parsed[1].path)
      -- Append remaining files
      for i = 2, #all_parsed do
        append_rows_from_parsed(all_parsed[i].parsed, all_parsed[i].path)
      end
    else
      -- No = Append
      for _, ap in ipairs(all_parsed) do
        append_rows_from_parsed(ap.parsed, ap.path)
      end
    end
  else
    -- First load: build from first, append rest
    CLB.loaded_file = #filepaths == 1 and filepaths[1] or nil
    CLB.loaded_format = "EDL"
    CLB.parsed_data = all_parsed[1].parsed
    build_rows_from_parsed(all_parsed[1].parsed, all_parsed[1].path)
    for i = 2, #all_parsed do
      append_rows_from_parsed(all_parsed[i].parsed, all_parsed[i].path)
    end
  end

  -- Summary message
  if #all_parsed > 1 then
    console_msg(string.format("Loaded %d EDL files (%d total events)", #all_parsed, #ROWS))
  end
end

---------------------------------------------------------------------------
-- Audio Loading
---------------------------------------------------------------------------

--- Start loading audio folder (initiates async loading)
local function load_audio_folder()
  -- Select folder
  local folder
  if reaper.JS_Dialog_BrowseForFolder then
    local rv, path = reaper.JS_Dialog_BrowseForFolder("Select Audio Folder", CLB.last_audio_dir or "")
    if rv ~= 1 or not path or path == "" then return end
    folder = path
  else
    reaper.ShowMessageBox(
      "JS extension required for folder selection.\n\n" ..
      "Please install js_ReaScriptAPI via ReaPack.",
      SCRIPT_NAME, 0)
    return
  end

  -- Remember directory
  CLB.last_audio_dir = folder
  CLB.audio_folder = folder
  save_prefs()

  console_msg("Scanning audio folder: " .. folder)

  -- Phase 1: Scan files (quick)
  local files = scan_audio_folder(folder, CLB.audio_recursive)

  if #files == 0 then
    reaper.ShowMessageBox(
      "No audio files found in:\n" .. folder ..
      (CLB.audio_recursive and "\n(recursive search enabled)" or ""),
      SCRIPT_NAME, 0)
    return
  end

  console_msg(string.format("Found %d audio files, reading metadata...", #files))

  -- Initialize loading state for async metadata reading
  CLB.loading_state = {
    phase = "reading_metadata",
    total = #files,
    current = 0,
    files = files,
  }

  -- Show audio panel
  CLB.show_audio_panel = true
end

--- Process a batch of audio files for metadata reading (called each frame)
local function process_audio_loading_batch()
  if not CLB.loading_state or CLB.loading_state.phase ~= "reading_metadata" then
    return false  -- Not loading
  end

  local BATCH_SIZE = 5  -- Files per frame (balance between speed and responsiveness)
  local state = CLB.loading_state

  for i = 1, BATCH_SIZE do
    local idx = state.current + 1
    if idx > state.total then
      -- Loading complete
      CLB.audio_files = state.files
      CLB.loading_state = nil
      CLB.audio_cached = nil
      CLB.audio_cached_frame = -1

      console_msg(string.format("Loaded %d audio files with metadata", #CLB.audio_files))

      -- Auto-match if EDL is loaded
      if #ROWS > 0 then
        match_audio_files()
      end

      return false  -- Done loading
    end

    -- Read metadata for this file
    local file = state.files[idx]
    file.metadata = read_audio_metadata(file.path)
    state.current = idx
  end

  return true  -- Still loading
end

--- Clear all loaded audio files
local function clear_audio_files()
  CLB.audio_files = {}
  CLB.audio_folder = ""
  CLB.audio_cached = nil
  CLB.audio_cached_frame = -1
  CLB.loading_state = nil
  clear_match_results()
end

---------------------------------------------------------------------------
-- Generate Items
---------------------------------------------------------------------------
local function generate_items()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded. Load an EDL file first.", SCRIPT_NAME, 0)
    return
  end

  -- Collect unique tracks
  local track_names = {}
  local track_order = {}
  for _, row in ipairs(ROWS) do
    local t = row.track or "A1"
    if not track_names[t] then
      track_names[t] = true
      track_order[#track_order + 1] = t
    end
  end

  -- Confirmation
  local msg = string.format(
    "Generate %d empty items on %d track(s)?\n\n" ..
    "Tracks: %s\n" ..
    "FPS: %s%s\n\n" ..
    "Items will be placed at absolute timecode positions.",
    #ROWS, #track_order,
    table.concat(track_order, ", "),
    tostring(CLB.fps),
    CLB.is_drop and " (Drop Frame)" or ""
  )
  if reaper.ShowMessageBox(msg, SCRIPT_NAME, 1) ~= 1 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Create or find tracks by name
  local track_map = {}  -- track_field -> MediaTrack*
  local existing_count = reaper.CountTracks(0)

  for _, t in ipairs(track_order) do
    local tokens = {
      format = CLB.loaded_format or "EDL",
      track = t,
      title = (CLB.parsed_data and CLB.parsed_data.title) or "",
    }
    local name = EDL.expand_template(CLB.track_name_format, tokens)

    -- Search existing tracks first
    local found = nil
    for ti = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, ti)
      local _, tr_name = reaper.GetTrackName(tr)
      if tr_name == name then
        found = tr
        break
      end
    end

    if not found then
      -- Create new track
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      found = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      reaper.GetSetMediaTrackInfo_String(found, "P_NAME", name, true)
    end

    track_map[t] = found
  end

  -- Create items
  local created = 0
  for _, row in ipairs(ROWS) do
    local tr = track_map[row.track or "A1"]
    if not tr then tr = track_map[track_order[1]] end
    if not tr then goto continue end

    local pos = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
    local pos_out = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
    local length = pos_out - pos
    if length <= 0 then length = 0.001 end  -- minimum length

    local item = reaper.AddMediaItemToTrack(tr)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)

    local take = reaper.AddTakeToMediaItem(item)
    if take then
      -- Take name = clip name
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", row.clip_name or "", true)

      -- Item note: Source TC In/Out + Reel (human-readable)
      local note_parts = {}
      note_parts[#note_parts + 1] = "Reel: " .. (row.reel or "")
      note_parts[#note_parts + 1] = "Src In: " .. (row.src_tc_in or "")
      note_parts[#note_parts + 1] = "Src Out: " .. (row.src_tc_out or "")
      if row.notes and row.notes ~= "" then
        note_parts[#note_parts + 1] = ""
        note_parts[#note_parts + 1] = row.notes
      end
      local note_text = table.concat(note_parts, "\n")
      reaper.GetSetMediaItemInfo_String(item, "P_NOTES", note_text, true)

      -- Store all metadata as P_EXT fields
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_EVENT", row.event_num or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_REEL", row.reel or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_TRACK", row.track or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_EDIT_TYPE", row.edit_type or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_IN", row.src_tc_in or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_OUT", row.src_tc_out or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_REC_TC_IN", row.rec_tc_in or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_REC_TC_OUT", row.rec_tc_out or "", true)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SOURCE_FILE", row.source_file or "", true)
      if row.notes and row.notes ~= "" then
        reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_NOTES", row.notes, true)
      end
    end

    created = created + 1
    ::continue::
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("CLB: Generate " .. created .. " conform items", -1)

  reaper.ShowMessageBox(
    string.format("Generated %d empty items on %d track(s).", created, #track_order),
    SCRIPT_NAME, 0)
end

---------------------------------------------------------------------------
-- Get Selected Rows (for conform operations)
---------------------------------------------------------------------------
local function get_selected_rows()
  local selected = {}
  local view_rows = get_view_rows()

  for _, row in ipairs(view_rows) do
    -- Check if any cell in this row is selected
    for c = 1, COL_COUNT do
      if sel_has(row.__guid, c) then
        selected[#selected + 1] = row
        break
      end
    end
  end

  return selected
end

---------------------------------------------------------------------------
-- Conform Matched Items (insert actual audio files)
---------------------------------------------------------------------------
local function conform_matched_items(selected_only)
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded. Load an EDL file first.", SCRIPT_NAME, 0)
    return
  end

  -- Determine which rows to process
  local rows_to_process
  if selected_only then
    rows_to_process = get_selected_rows()
    if #rows_to_process == 0 then
      reaper.ShowMessageBox("No rows selected. Select rows in the table first.", SCRIPT_NAME, 0)
      return
    end
  else
    rows_to_process = ROWS
  end

  -- Filter to matched rows only
  local matched_rows = {}
  local found_count = 0
  local multi_count = 0

  for _, row in ipairs(rows_to_process) do
    if row.match_status == "Found" then
      matched_rows[#matched_rows + 1] = row
      found_count = found_count + 1
    elseif row.match_status == "Multiple" and row.__match_candidates then
      matched_rows[#matched_rows + 1] = row
      multi_count = multi_count + 1
    end
  end

  if #matched_rows == 0 then
    reaper.ShowMessageBox(
      "No matched events to conform.\n\n" ..
      "Load audio files and run matching first.",
      SCRIPT_NAME, 0)
    return
  end

  -- Collect unique tracks
  local track_names = {}
  local track_order = {}
  for _, row in ipairs(matched_rows) do
    local t = row.track or "A1"
    if not track_names[t] then
      track_names[t] = true
      track_order[#track_order + 1] = t
    end
  end

  -- Confirmation
  local msg = string.format(
    "Conform %d matched events?\n\n" ..
    "• %d single matches (1 take each)\n" ..
    "• %d multiple matches (multiple takes)\n\n" ..
    "Tracks: %s\n" ..
    "FPS: %s%s\n\n" ..
    "Audio files will be inserted at timeline positions.",
    #matched_rows, found_count, multi_count,
    table.concat(track_order, ", "),
    tostring(CLB.fps),
    CLB.is_drop and " (Drop Frame)" or ""
  )
  if reaper.ShowMessageBox(msg, SCRIPT_NAME, 1) ~= 1 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Create or find tracks by name
  local track_map = {}

  for _, t in ipairs(track_order) do
    local tokens = {
      format = CLB.loaded_format or "EDL",
      track = t,
      title = (CLB.parsed_data and CLB.parsed_data.title) or "",
    }
    local name = EDL.expand_template(CLB.track_name_format, tokens)

    -- Search existing tracks first
    local found = nil
    for ti = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, ti)
      local _, tr_name = reaper.GetTrackName(tr)
      if tr_name == name then
        found = tr
        break
      end
    end

    if not found then
      reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
      found = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
      reaper.GetSetMediaTrackInfo_String(found, "P_NAME", name, true)
    end

    track_map[t] = found
  end

  -- Helper: Get audio file's TimeReference in seconds
  local function get_audio_start_sec(audio_file)
    if not audio_file or not audio_file.metadata then return 0 end
    local meta = audio_file.metadata
    local tr = tonumber(meta.timereference) or 0
    local sr = meta.samplerate or 48000
    if sr <= 0 then sr = 48000 end
    if tr > 0 and sr > 0 then
      return tr / sr
    end
    return 0
  end

  -- Create items
  local created = 0
  local takes_created = 0

  for _, row in ipairs(matched_rows) do
    local tr = track_map[row.track or "A1"]
    if not tr then tr = track_map[track_order[1]] end
    if not tr then goto continue end

    -- Timeline position from rec_tc_in
    local pos = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
    local pos_out = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
    local length = pos_out - pos
    if length <= 0 then length = 0.001 end

    -- Source offset: src_tc_in - audio's TimeReference
    local src_in_sec = EDL.tc_to_seconds(row.src_tc_in, CLB.fps, CLB.is_drop)

    -- Get audio files to insert
    local audio_files = {}
    if row.match_status == "Found" and row.matched_path then
      -- Find the audio file entry
      for _, af in ipairs(CLB.audio_files) do
        if af.path == row.matched_path then
          audio_files[1] = af
          break
        end
      end
    elseif row.match_status == "Multiple" and row.__match_candidates then
      audio_files = row.__match_candidates
    end

    if #audio_files == 0 then goto continue end

    -- Create item
    local item = reaper.AddMediaItemToTrack(tr)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)

    -- Add takes for each audio file
    local first_take = true
    for ti, af in ipairs(audio_files) do
      -- Calculate source offset for this audio file
      local audio_start = get_audio_start_sec(af)
      local source_offset = src_in_sec - audio_start
      if source_offset < 0 then source_offset = 0 end

      -- Insert media source
      local source = reaper.PCM_Source_CreateFromFile(af.path)
      if source then
        local take
        if first_take then
          take = reaper.AddTakeToMediaItem(item)
          first_take = false
        else
          take = reaper.AddTakeToMediaItem(item)
        end

        if take then
          reaper.SetMediaItemTake_Source(take, source)
          reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", source_offset)

          -- Take name: clip name (or filename for additional takes)
          local take_name = row.clip_name or af.basename or ""
          if ti > 1 then
            take_name = af.filename or af.basename or ("Take " .. ti)
          end
          reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)

          -- Store metadata as P_EXT
          reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_EVENT", row.event_num or "", true)
          reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_REEL", row.reel or "", true)
          reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_IN", row.src_tc_in or "", true)
          reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_OUT", row.src_tc_out or "", true)
          reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_MATCHED_FILE", af.path or "", true)

          takes_created = takes_created + 1
        end
      end
    end

    -- Item note
    local note_parts = {}
    note_parts[#note_parts + 1] = "Reel: " .. (row.reel or "")
    note_parts[#note_parts + 1] = "Src In: " .. (row.src_tc_in or "")
    note_parts[#note_parts + 1] = "Src Out: " .. (row.src_tc_out or "")
    if #audio_files > 1 then
      note_parts[#note_parts + 1] = ""
      note_parts[#note_parts + 1] = string.format("(%d takes from multiple matches)", #audio_files)
    end
    if row.notes and row.notes ~= "" then
      note_parts[#note_parts + 1] = ""
      note_parts[#note_parts + 1] = row.notes
    end
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES", table.concat(note_parts, "\n"), true)

    created = created + 1
    ::continue::
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("CLB: Conform " .. created .. " items (" .. takes_created .. " takes)", -1)

  reaper.ShowMessageBox(
    string.format("Conformed %d items with %d takes on %d track(s).",
      created, takes_created, #track_order),
    SCRIPT_NAME, 0)
end

---------------------------------------------------------------------------
-- Remove Duplicates
---------------------------------------------------------------------------
local function remove_duplicates()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded.", SCRIPT_NAME, 0)
    return
  end

  -- Build duplicate key: track + rec_tc_in + rec_tc_out + clip_name + reel
  local seen = {}
  local keep = {}
  local removed = 0

  for _, row in ipairs(ROWS) do
    local key = table.concat({
      row.track or "",
      row.rec_tc_in or "",
      row.rec_tc_out or "",
      row.clip_name or "",
      row.reel or "",
    }, "|")

    if seen[key] then
      removed = removed + 1
    else
      seen[key] = true
      keep[#keep + 1] = row
    end
  end

  if removed == 0 then
    reaper.ShowMessageBox("No duplicate events found.", SCRIPT_NAME, 0)
    return
  end

  -- Confirm
  local choice = reaper.ShowMessageBox(
    string.format("Found %d duplicate event(s) out of %d total.\n\n" ..
      "Duplicates are identified by matching:\n" ..
      "Track + Rec TC In + Rec TC Out + Clip Name + Reel\n\n" ..
      "Remove them? (keeps first occurrence)",
      removed, #ROWS),
    SCRIPT_NAME, 1)  -- 1 = OK/Cancel

  if choice ~= 1 then return end

  ROWS = keep

  -- Update source event counts
  local src_counts = {}
  for _, row in ipairs(ROWS) do
    local si = row.__source_idx or 0
    src_counts[si] = (src_counts[si] or 0) + 1
  end
  for i, src in ipairs(CLB.edl_sources) do
    src.event_count = src_counts[i] or 0
  end

  sel_clear()
  EDIT = nil
  _rebuild_track_filters()
  undo_snapshot()
  CLB.cached_rows = nil; CLB.cached_rows_frame = -1

  console_msg(string.format("Removed %d duplicates (%d remaining)", removed, #ROWS))
  reaper.ShowMessageBox(
    string.format("Removed %d duplicate event(s).\n%d events remaining.", removed, #ROWS),
    SCRIPT_NAME, 0)
end

---------------------------------------------------------------------------
-- Export EDL
---------------------------------------------------------------------------
local function export_edl()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events to export.", SCRIPT_NAME, 0)
    return
  end

  local retval, filepath
  if reaper.JS_Dialog_BrowseForSaveFile then
    retval, filepath = reaper.JS_Dialog_BrowseForSaveFile(
      "Export EDL", CLB.last_dir or "", "export.edl", "EDL Files\0*.edl\0\0")
    if not retval or retval == 0 or not filepath or filepath == "" then return end
  else
    -- Fallback if JS extension not available
    retval, filepath = reaper.GetUserFileNameForRead("", "Export EDL (choose or type filename)", "*.edl")
    if not retval or not filepath or filepath == "" then return end
  end

  -- Build export data structure
  local export_data = {
    title = (CLB.parsed_data and CLB.parsed_data.title) or "Untitled",
    fcm = (CLB.parsed_data and CLB.parsed_data.fcm) or "NON-DROP FRAME",
    events = {},
  }

  for _, row in ipairs(ROWS) do
    export_data.events[#export_data.events + 1] = {
      event_num = row.event_num,
      reel = row.reel,
      track = row.track,
      edit_type = row.edit_type,
      dissolve_len = row.dissolve_len,
      src_tc_in = row.src_tc_in,
      src_tc_out = row.src_tc_out,
      rec_tc_in = row.rec_tc_in,
      rec_tc_out = row.rec_tc_out,
      clip_name = row.clip_name,
      source_file = row.source_file,
      comments = {},
    }
  end

  local ok, err = EDL.write(filepath, export_data)
  if ok then
    reaper.ShowMessageBox(
      string.format("Exported %d events to:\n%s", #export_data.events, filepath),
      SCRIPT_NAME, 0)
  else
    reaper.ShowMessageBox("Export failed:\n\n" .. tostring(err), SCRIPT_NAME, 0)
  end
end

---------------------------------------------------------------------------
-- Copy / Paste
---------------------------------------------------------------------------
local function copy_selection()
  -- Build TSV from selected cells
  local lines = {}
  local view_rows = get_view_rows()

  for _, row in ipairs(view_rows) do
    local cols = {}
    local has_sel = false
    for c = 1, COL_COUNT do
      if sel_has(row.__guid, c) then
        cols[#cols + 1] = get_cell_text(row, c)
        has_sel = true
      end
    end
    if has_sel then
      lines[#lines + 1] = table.concat(cols, "\t")
    end
  end

  if #lines > 0 then
    reaper.CF_SetClipboard(table.concat(lines, "\n"))
    console_msg("Copied " .. #lines .. " rows")
  end
end

local function paste_selection()
  local clip = reaper.CF_GetClipboard and reaper.CF_GetClipboard("") or ""
  if clip == "" then return end

  -- Parse TSV
  local clip_rows = {}
  for line in (clip .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      local cells = {}
      for cell in (line .. "\t"):gmatch("(.-)\t") do
        cells[#cells + 1] = cell
      end
      clip_rows[#clip_rows + 1] = cells
    end
  end

  if #clip_rows == 0 then return end

  -- Find anchor (top-left of selection)
  local anchor_row_idx, anchor_col
  local view_rows = get_view_rows()
  for i, row in ipairs(view_rows) do
    for c = 1, COL_COUNT do
      if sel_has(row.__guid, c) then
        if not anchor_row_idx or i < anchor_row_idx or (i == anchor_row_idx and c < anchor_col) then
          anchor_row_idx = i
          anchor_col = c
        end
      end
    end
  end

  if not anchor_row_idx then
    anchor_row_idx = 1
    anchor_col = 2  -- First editable column
  end

  -- Apply paste
  for ri, clip_row in ipairs(clip_rows) do
    local target_row_idx = anchor_row_idx + ri - 1
    if target_row_idx > #view_rows then break end
    local target_row = view_rows[target_row_idx]

    for ci, val in ipairs(clip_row) do
      local target_col = anchor_col + ci - 1
      if target_col <= COL_COUNT and EDITABLE_COLS[target_col] then
        set_cell_value(target_row, target_col, val)
      end
    end
  end

  undo_snapshot()
  CLB.cached_rows = nil; CLB.cached_rows_frame = -1
  console_msg("Pasted " .. #clip_rows .. " rows")
end

---------------------------------------------------------------------------
-- Modifier key helpers
---------------------------------------------------------------------------
local function _mods()
  local shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
  local ctrl_cmd
  -- macOS: use Cmd (Super), Windows/Linux: use Ctrl
  if reaper.GetOS():find("OSX") or reaper.GetOS():find("macOS") then
    ctrl_cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
  else
    ctrl_cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
  end
  return shift, ctrl_cmd
end

---------------------------------------------------------------------------
-- Draw: Toolbar
---------------------------------------------------------------------------
local function draw_toolbar()
  -- Load buttons
  if reaper.ImGui_Button(ctx, "Load EDL...", scale(90), scale(24)) then
    load_edl_file()
  end
  reaper.ImGui_SameLine(ctx)

  -- Load XML placeholder
  if reaper.ImGui_Button(ctx, "Load XML...", scale(90), scale(24)) then
    reaper.ShowMessageBox(
      "XML support coming soon.\n\nCurrently supported: EDL (CMX3600).\n\n" ..
      "Planned: Premiere XML, FCPX XML, FCP7 XML, Resolve XML, Steinberg XML",
      SCRIPT_NAME, 0)
  end
  reaper.ImGui_SameLine(ctx)

  -- Load Audio button
  if reaper.ImGui_Button(ctx, "Load Audio...", scale(100), scale(24)) then
    load_audio_folder()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Load audio files from folder to match with EDL events")
    reaper.ImGui_Text(ctx, "Reads BWF/iXML metadata for matching")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Match All button (only show when both EDL and audio are loaded)
  if #ROWS > 0 and #CLB.audio_files > 0 then
    if reaper.ImGui_Button(ctx, "Match All", scale(80), scale(24)) then
      match_audio_files()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Re-run matching algorithm on all EDL events")
      reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_SameLine(ctx)
  end

  -- Clear Audio button (only show when audio is loaded)
  if #CLB.audio_files > 0 then
    if reaper.ImGui_Button(ctx, "Clear Audio", scale(90), scale(24)) then
      clear_audio_files()
    end
    reaper.ImGui_SameLine(ctx)
  end

  -- Separator
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)

  -- Status
  local view_rows = get_view_rows()
  local status
  if #CLB.edl_sources > 0 then
    if #CLB.edl_sources == 1 then
      status = string.format("%s | Events: %d | Showing: %d",
        CLB.edl_sources[1].name, #ROWS, #view_rows)
    else
      status = string.format("%d EDLs | Events: %d | Showing: %d",
        #CLB.edl_sources, #ROWS, #view_rows)
    end
  elseif CLB.loaded_file then
    local filename = CLB.loaded_file:match("([^/\\]+)$") or CLB.loaded_file
    status = string.format("%s | Events: %d | Showing: %d",
      filename, #ROWS, #view_rows)
  else
    status = "No file loaded"
  end
  reaper.ImGui_Text(ctx, status)
  reaper.ImGui_SameLine(ctx)

  -- Sources toggle button (only show when files are loaded)
  if #CLB.edl_sources > 0 then
    local src_label = CLB.show_sources_panel and "Sources <<" or "Sources >>"
    if reaper.ImGui_SmallButton(ctx, src_label .. "##clb_src_toggle") then
      CLB.show_sources_panel = not CLB.show_sources_panel
    end
    reaper.ImGui_SameLine(ctx)
  end

  -- Tracks toggle button
  if #CLB.track_filters > 0 then
    local trk_label = CLB.show_track_filter and "Tracks <<" or "Tracks >>"
    if reaper.ImGui_SmallButton(ctx, trk_label .. "##clb_trk_toggle") then
      CLB.show_track_filter = not CLB.show_track_filter
    end
    reaper.ImGui_SameLine(ctx)
  end

  -- Search
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "Search:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(160))
  local chg_s, new_s = reaper.ImGui_InputText(ctx, "##clb_search", CLB.search_text)
  if chg_s then
    CLB.search_text = new_s
    CLB.cached_rows = nil; CLB.cached_rows_frame = -1
    sel_clear()
  end
  reaper.ImGui_SameLine(ctx)
  if CLB.search_text ~= "" then
    if reaper.ImGui_SmallButton(ctx, "X##clb_clear_search") then
      CLB.search_text = ""
      CLB.cached_rows = nil; CLB.cached_rows_frame = -1
    end
    reaper.ImGui_SameLine(ctx)
  end

  -- Options button
  if reaper.ImGui_Button(ctx, "Options", scale(70), scale(24)) then
    reaper.ImGui_OpenPopup(ctx, "##clb_options")
  end

  -- Options menu
  if reaper.ImGui_BeginPopup(ctx, "##clb_options") then
    -- Console output
    local cl = CONSOLE.enabled and ">> Console Output" or "   Console Output"
    if reaper.ImGui_Selectable(ctx, cl) then
      CONSOLE.enabled = not CONSOLE.enabled
      save_prefs()
    end

    -- Debug mode
    local dl = DEBUG and ">> Debug Mode" or "   Debug Mode"
    if reaper.ImGui_Selectable(ctx, dl) then
      DEBUG = not DEBUG
      save_prefs()
    end

    reaper.ImGui_Separator(ctx)

    -- Docking
    local dock_l = ALLOW_DOCKING and ">> Allow Docking" or "   Allow Docking"
    if reaper.ImGui_Selectable(ctx, dock_l) then
      ALLOW_DOCKING = not ALLOW_DOCKING
      save_prefs()
    end

    reaper.ImGui_Separator(ctx)

    -- Font Size submenu
    if reaper.ImGui_BeginMenu(ctx, "Font Size") then
      local sizes = {
        { label = "50%",  s = 0.5 },
        { label = "75%",  s = 0.75 },
        { label = "100% (Default)", s = 1.0 },
        { label = "125%", s = 1.25 },
        { label = "150%", s = 1.5 },
        { label = "175%", s = 1.75 },
        { label = "200%", s = 2.0 },
        { label = "250%", s = 2.5 },
        { label = "300%", s = 3.0 },
      }
      for _, sz in ipairs(sizes) do
        local is_cur = math.abs((FONT_SCALE or 1.0) - sz.s) < 0.01
        local label = is_cur and (">> " .. sz.label) or ("   " .. sz.label)
        if reaper.ImGui_Selectable(ctx, label) then
          FONT_SCALE = sz.s
          set_font_size(math.floor(13 * FONT_SCALE))
          save_prefs()
        end
      end
      reaper.ImGui_EndMenu(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end

  -- Row 2
  -- FPS selector
  reaper.ImGui_Text(ctx, "FPS:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(70))
  local fps_str = tostring(CLB.fps)
  local chg_fps, new_fps = reaper.ImGui_InputText(ctx, "##clb_fps", fps_str)
  if chg_fps then
    local n = tonumber(new_fps)
    if n and n > 0 and n <= 120 then
      CLB.fps = n
      save_prefs()
      -- Recompute durations
      for _, row in ipairs(ROWS) do
        local ri_sec = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
        local ro_sec = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
        row.duration = EDL.seconds_to_tc(ro_sec - ri_sec, CLB.fps, CLB.is_drop)
      end
    end
  end
  reaper.ImGui_SameLine(ctx)

  -- Track name format
  reaper.ImGui_Text(ctx, "Track Format:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(250))
  local chg_tf, new_tf = reaper.ImGui_InputText(ctx, "##clb_trk_fmt", CLB.track_name_format)
  if chg_tf then
    CLB.track_name_format = new_tf
    save_prefs()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Tokens: ${format} ${track} ${reel} ${event} ${clip} ${title}")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Generate Items button (empty items)
  if reaper.ImGui_Button(ctx, "Generate Items", scale(110), scale(24)) then
    generate_items()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Create empty items on REAPER tracks at absolute TC positions")
    reaper.ImGui_Text(ctx, "Metadata stored as P_EXT fields on each take")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Conform Matched button (with audio)
  local has_matches = false
  for _, row in ipairs(ROWS) do
    if row.match_status == "Found" or row.match_status == "Multiple" then
      has_matches = true
      break
    end
  end

  if has_matches then
    if reaper.ImGui_Button(ctx, "Conform All", scale(90), scale(24)) then
      conform_matched_items(false)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Insert matched audio files as items")
      reaper.ImGui_Text(ctx, "Multiple matches = multiple takes on same item")
      reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_SameLine(ctx)

    -- Conform Selected button
    if reaper.ImGui_Button(ctx, "Conform Sel", scale(90), scale(24)) then
      conform_matched_items(true)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Insert matched audio for selected rows only")
      reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_SameLine(ctx)
  end

  -- Remove Duplicates button
  if reaper.ImGui_Button(ctx, "Remove Dups", scale(100), scale(24)) then
    remove_duplicates()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Remove duplicate events (matching Track + Rec TC + Clip Name + Reel)")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Export EDL button
  if reaper.ImGui_Button(ctx, "Export EDL", scale(90), scale(24)) then
    export_edl()
  end
end

---------------------------------------------------------------------------
-- Draw: Sources Panel
---------------------------------------------------------------------------
local function draw_sources_panel()
  if not CLB.show_sources_panel or #CLB.edl_sources == 0 then return end

  reaper.ImGui_Separator(ctx)

  -- Count visible/hidden
  local visible_count = 0
  for _, src in ipairs(CLB.edl_sources) do
    if src.visible then visible_count = visible_count + 1 end
  end

  reaper.ImGui_Text(ctx, string.format("Loaded EDL Sources (%d):", #CLB.edl_sources))
  reaper.ImGui_SameLine(ctx)

  -- Show All / Hide All buttons (always rendered to keep stable layout)
  if reaper.ImGui_SmallButton(ctx, "Show All##clb_src_all") then
    for _, src in ipairs(CLB.edl_sources) do src.visible = true end
    CLB.cached_rows = nil; CLB.cached_rows_frame = -1
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide All##clb_src_none") then
    for _, src in ipairs(CLB.edl_sources) do src.visible = false end
    CLB.cached_rows = nil; CLB.cached_rows_frame = -1
  end

  -- List each source with checkbox (scrollable region, max ~6 rows visible)
  local line_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
  local max_visible = 6
  local list_h = math.min(#CLB.edl_sources, max_visible) * line_h + 4
  if reaper.ImGui_BeginChild(ctx, "##clb_src_list", 0, list_h, reaper.ImGui_ChildFlags_Borders()) then
    for i, src in ipairs(CLB.edl_sources) do
      local label = string.format("%s (%d events)##clb_src_%d", src.name, src.event_count, i)
      local changed, new_val = reaper.ImGui_Checkbox(ctx, label, src.visible)
      if changed then
        src.visible = new_val
        CLB.cached_rows = nil; CLB.cached_rows_frame = -1
      end
    end
    reaper.ImGui_EndChild(ctx)
  end
end

---------------------------------------------------------------------------
-- Draw: Track Filter Panel
---------------------------------------------------------------------------
local function draw_track_filter_panel()
  if not CLB.show_track_filter or #CLB.track_filters == 0 then return end

  reaper.ImGui_Separator(ctx)

  reaper.ImGui_Text(ctx, string.format("Track Filter (%d):", #CLB.track_filters))
  reaper.ImGui_SameLine(ctx)

  -- Show All / Hide All
  if reaper.ImGui_SmallButton(ctx, "Show All##clb_trk_all") then
    for _, tf in ipairs(CLB.track_filters) do tf.visible = true end
    CLB.cached_rows = nil; CLB.cached_rows_frame = -1
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide All##clb_trk_none") then
    for _, tf in ipairs(CLB.track_filters) do tf.visible = false end
    CLB.cached_rows = nil; CLB.cached_rows_frame = -1
  end

  -- Track checkboxes (inline, since tracks are usually few)
  for i, tf in ipairs(CLB.track_filters) do
    if i > 1 then reaper.ImGui_SameLine(ctx) end
    local label = string.format("%s (%d)##clb_trk_%d", tf.name, tf.count, i)
    local changed, new_val = reaper.ImGui_Checkbox(ctx, label, tf.visible)
    if changed then
      tf.visible = new_val
      CLB.cached_rows = nil; CLB.cached_rows_frame = -1
    end
  end
end

---------------------------------------------------------------------------
-- Draw: Table
---------------------------------------------------------------------------
local function draw_table(table_height)
  local view_rows = get_view_rows()
  local row_count = #view_rows

  if row_count == 0 and not CLB.loaded_file then
    reaper.ImGui_TextDisabled(ctx, "Click 'Load EDL...' to open a CMX3600 EDL file.")
    return
  end

  if row_count == 0 then
    reaper.ImGui_TextDisabled(ctx, "No events match the current filter.")
    return
  end

  -- Table flags
  local flags = reaper.ImGui_TableFlags_Borders()
    | reaper.ImGui_TableFlags_RowBg()
    | reaper.ImGui_TableFlags_SizingFixedFit()
    | reaper.ImGui_TableFlags_ScrollX()
    | reaper.ImGui_TableFlags_ScrollY()
    | reaper.ImGui_TableFlags_Resizable()
    | reaper.ImGui_TableFlags_Reorderable()

  -- Available height for table (use provided height or available space)
  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local height = table_height or avail_h

  if not reaper.ImGui_BeginTable(ctx, "clb_table", COL_COUNT, flags, 0, height) then
    return
  end

  -- Setup columns
  for c = 1, COL_COUNT do
    local w = scale(COL_WIDTH[c] or DEFAULT_COL_WIDTH[c] or 80)
    reaper.ImGui_TableSetupColumn(ctx, HEADER_LABELS[c] or "",
      reaper.ImGui_TableColumnFlags_WidthFixed(), w)
  end

  -- Headers (manual rendering for sort indicators + click handling)
  reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
  reaper.ImGui_TableNextRow(ctx)
  for c = 1, COL_COUNT do
    reaper.ImGui_TableSetColumnIndex(ctx, c - 1)

    -- Sort indicator
    local sort_indicator = ""
    for si, sc in ipairs(SORT_STATE.columns) do
      if sc.col_id == c then
        local arrow = sc.ascending and " ^" or " v"
        if #SORT_STATE.columns > 1 then
          sort_indicator = string.format(" [%d]%s", si, arrow)
        else
          sort_indicator = arrow
        end
        break
      end
    end

    local label = (HEADER_LABELS[c] or "") .. sort_indicator
    reaper.ImGui_Text(ctx, label)

    -- Click to sort
    if reaper.ImGui_IsItemClicked(ctx, 0) then
      local shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
      toggle_sort(c, shift)
    end
  end

  -- ListClipper for virtualization
  if list_clipper and not reaper.ImGui_ValidatePtr(list_clipper, "ImGui_ListClipper*") then
    list_clipper = reaper.ImGui_CreateListClipper(ctx)
  end

  local use_clipper = list_clipper and row_count > 100
  local cs, ce

  if use_clipper then
    reaper.ImGui_ListClipper_Begin(list_clipper, row_count)
  end

  local clp = true
  while clp do
    if use_clipper then
      if not reaper.ImGui_ListClipper_Step(list_clipper) then break end
      local ds, de = reaper.ImGui_ListClipper_GetDisplayRange(list_clipper)
      cs, ce = ds + 1, de
      CLB.visible_range.first = cs
      CLB.visible_range.last = ce
    else
      cs, ce = 1, row_count
      clp = false
    end

    for i = cs, ce do
      local row = view_rows[i]
      if not row then break end

      reaper.ImGui_TableNextRow(ctx)

      for c = 1, COL_COUNT do
        reaper.ImGui_TableSetColumnIndex(ctx, c - 1)

        local is_editing = EDIT and EDIT.row_idx == i and EDIT.col_id == c

        if is_editing then
          -- Editing mode
          reaper.ImGui_SetNextItemWidth(ctx, -1)
          if EDIT.want_focus then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            EDIT.want_focus = false
          end

          local chg, new_val = reaper.ImGui_InputText(ctx,
            "##edit_" .. row.__guid .. "_" .. c,
            EDIT.buf)

          if chg then
            EDIT.buf = new_val
          end

          -- Confirm: Enter or deactivated
          local confirm = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
          -- Cancel: ESC
          local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)

          if confirm then
            local old_val = get_cell_text(row, c)
            if EDIT.buf ~= old_val then
              -- TC validation for TC columns
              if TC_COLS[c] and not EDL.is_valid_tc(EDIT.buf) then
                -- Invalid TC: reject
                reaper.ShowMessageBox(
                  "Invalid timecode format.\nExpected: HH:MM:SS:FF",
                  SCRIPT_NAME, 0)
              else
                set_cell_value(row, c, EDIT.buf)
                undo_snapshot()
                CLB.cached_rows = nil; CLB.cached_rows_frame = -1
              end
            end
            EDIT = nil
          elseif cancel then
            EDIT = nil
          end
        else
          -- Display mode: use Selectable for highlight + click detection
          local text = get_cell_text(row, c)
          local selected = sel_has(row.__guid, c)
          local display = (text ~= "" and text or " ") .. "##" .. row.__guid .. "_" .. c

          reaper.ImGui_Selectable(ctx, display, selected)

          -- Click handling
          if reaper.ImGui_IsItemClicked(ctx, 0) then
            local shift, cmd = _mods()
            if shift and SEL.anchor then
              sel_rect(SEL.anchor.guid, SEL.anchor.col, row.__guid, c)
            elseif cmd then
              sel_toggle(row.__guid, c)
              if not SEL.anchor then
                SEL.anchor = { guid = row.__guid, col = c }
              end
            else
              sel_set_single(row.__guid, c)
            end
          end

          -- Double-click to edit
          if reaper.ImGui_IsItemHovered(ctx) and
             reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and
             EDITABLE_COLS[c] then
            EDIT = {
              row_idx = i,
              col_id = c,
              buf = text,
              want_focus = true,
            }
          end
        end
      end
    end
  end

  reaper.ImGui_EndTable(ctx)
end

---------------------------------------------------------------------------
-- Draw: Audio Panel Header
---------------------------------------------------------------------------
local function draw_audio_panel_header()
  -- Header line: Audio Files count, folder path, options
  local file_count = #CLB.audio_files
  local folder_display = CLB.audio_folder:match("([^/\\]+)$") or CLB.audio_folder

  reaper.ImGui_Text(ctx, string.format("Audio Files (%d)", file_count))
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, folder_display)

  -- Recursive checkbox
  reaper.ImGui_SameLine(ctx)
  local chg_rec, new_rec = reaper.ImGui_Checkbox(ctx, "Recursive##audio_rec", CLB.audio_recursive)
  if chg_rec then
    CLB.audio_recursive = new_rec
    save_prefs()
  end

  -- Audio search
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "Search:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(120))
  local chg_s, new_s = reaper.ImGui_InputText(ctx, "##audio_search", CLB.audio_search)
  if chg_s then
    CLB.audio_search = new_s
    CLB.audio_cached = nil
    CLB.audio_cached_frame = -1
  end
  if CLB.audio_search ~= "" then
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "X##clr_audio_search") then
      CLB.audio_search = ""
      CLB.audio_cached = nil
      CLB.audio_cached_frame = -1
    end
  end

  -- Audio panel toggle
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide##audio_panel") then
    CLB.show_audio_panel = false
  end
end

---------------------------------------------------------------------------
-- Draw: Splitter (draggable divider between EDL and Audio tables)
---------------------------------------------------------------------------
local function draw_splitter()
  local splitter_height = 6
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)

  -- Invisible button for dragging
  reaper.ImGui_InvisibleButton(ctx, "##splitter", avail_w, splitter_height)

  if reaper.ImGui_IsItemActive(ctx) then
    local delta_y = reaper.ImGui_GetMouseDelta(ctx)
    if delta_y then
      local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
      local total_h = avail_h + splitter_height
      local delta_ratio = delta_y / total_h
      CLB.split_ratio = math.max(0.2, math.min(0.8, CLB.split_ratio + delta_ratio))
    end
  end

  -- Draw splitter line
  local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
  local min_x, min_y = reaper.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = reaper.ImGui_GetItemRectMax(ctx)
  local color = reaper.ImGui_IsItemHovered(ctx) and 0xAAAAAAFF or 0x666666FF
  reaper.ImGui_DrawList_AddRectFilled(draw_list, min_x, min_y + 2, max_x, max_y - 2, color)

  -- Change cursor on hover
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
  end
end

---------------------------------------------------------------------------
-- Draw: Audio Table
---------------------------------------------------------------------------
local function draw_audio_table(table_height)
  local audio_rows = get_audio_view_rows()
  local row_count = #audio_rows

  if row_count == 0 then
    if #CLB.audio_files == 0 then
      reaper.ImGui_TextDisabled(ctx, "No audio files loaded.")
    else
      reaper.ImGui_TextDisabled(ctx, "No audio files match the current filter.")
    end
    return
  end

  -- Table flags
  local flags = reaper.ImGui_TableFlags_Borders()
    | reaper.ImGui_TableFlags_RowBg()
    | reaper.ImGui_TableFlags_SizingFixedFit()
    | reaper.ImGui_TableFlags_ScrollX()
    | reaper.ImGui_TableFlags_ScrollY()
    | reaper.ImGui_TableFlags_Resizable()

  if not reaper.ImGui_BeginTable(ctx, "audio_table", AUDIO_COL_COUNT, flags, 0, table_height) then
    return
  end

  -- Setup columns
  for c = 1, AUDIO_COL_COUNT do
    local w = scale(AUDIO_COL_WIDTH[c] or 80)
    reaper.ImGui_TableSetupColumn(ctx, AUDIO_HEADER_LABELS[c] or "",
      reaper.ImGui_TableColumnFlags_WidthFixed(), w)
  end

  -- Headers
  reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
  reaper.ImGui_TableNextRow(ctx)
  for c = 1, AUDIO_COL_COUNT do
    reaper.ImGui_TableSetColumnIndex(ctx, c - 1)
    reaper.ImGui_Text(ctx, AUDIO_HEADER_LABELS[c] or "")
  end

  -- Rows
  for i = 1, row_count do
    local af = audio_rows[i]
    if not af then break end

    reaper.ImGui_TableNextRow(ctx)

    for c = 1, AUDIO_COL_COUNT do
      reaper.ImGui_TableSetColumnIndex(ctx, c - 1)

      local text = ""
      local meta = af.metadata or {}

      if c == AUDIO_COL.FILENAME then
        text = af.filename or ""
      elseif c == AUDIO_COL.SRC_TC then
        -- Source timecode (converted from BWF TimeReference)
        text = meta.src_tc or ""
      elseif c == AUDIO_COL.SCENE then
        text = meta.scene or ""
      elseif c == AUDIO_COL.TAKE then
        text = meta.take or ""
      elseif c == AUDIO_COL.TAPE then
        -- Tape/Roll (prefer tape, fallback to reel)
        text = meta.tape or meta.reel or ""
      elseif c == AUDIO_COL.FOLDER then
        text = af.folder or ""
      elseif c == AUDIO_COL.DURATION then
        text = format_duration(meta.duration)
      elseif c == AUDIO_COL.SAMPLERATE then
        text = format_samplerate(meta.samplerate)
      elseif c == AUDIO_COL.CHANNELS then
        text = meta.channels and tostring(meta.channels) or ""
      elseif c == AUDIO_COL.PROJECT then
        text = meta.project or ""
      elseif c == AUDIO_COL.DESCRIPTION then
        -- Show truncated description
        local desc = meta.description or ""
        if #desc > 50 then desc = desc:sub(1, 47) .. "..." end
        text = desc
      end

      reaper.ImGui_Text(ctx, text)
    end
  end

  reaper.ImGui_EndTable(ctx)
end

---------------------------------------------------------------------------
-- Draw: Loading Progress Indicator
---------------------------------------------------------------------------
local function draw_loading_progress()
  if not CLB.loading_state then return false end

  local state = CLB.loading_state
  local progress = state.total > 0 and (state.current / state.total) or 0

  reaper.ImGui_Text(ctx, string.format("Loading audio files... %d / %d", state.current, state.total))
  reaper.ImGui_ProgressBar(ctx, progress, -1, 0)

  return true
end

---------------------------------------------------------------------------
-- Draw: Main Content Area (split view support)
---------------------------------------------------------------------------
local function draw_main_content()
  -- Check if we're loading audio files
  if draw_loading_progress() then
    -- Show EDL table above progress bar
    draw_table()
    return
  end

  -- Check if audio panel should be shown
  if CLB.show_audio_panel and #CLB.audio_files > 0 then
    -- Split view mode
    local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local splitter_h = 6
    local header_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx) + 4

    -- Calculate heights
    local content_h = avail_h - splitter_h - header_h
    local edl_h = content_h * CLB.split_ratio
    local audio_h = content_h - edl_h

    -- EDL Events table (top)
    draw_table(edl_h)

    -- Splitter (draggable)
    draw_splitter()

    -- Audio panel header
    draw_audio_panel_header()

    -- Audio files table (bottom)
    draw_audio_table(audio_h)
  else
    -- Single table mode
    draw_table()
  end
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function loop()
  CLB.frame_counter = CLB.frame_counter + 1

  -- Process async audio loading (if in progress)
  process_audio_loading_batch()

  -- Push font
  font_pushed_this_frame = false
  if current_font_size ~= 13 and reaper.ImGui_PushFont then
    local ok_font = pcall(reaper.ImGui_PushFont, ctx, nil, current_font_size)
    if ok_font then
      font_pushed_this_frame = true
    end
  end

  -- Window flags
  local wnd_flags = reaper.ImGui_WindowFlags_NoCollapse()
    | reaper.ImGui_WindowFlags_NoScrollbar()
    | reaper.ImGui_WindowFlags_NoScrollWithMouse()
  if not ALLOW_DOCKING then
    wnd_flags = wnd_flags | reaper.ImGui_WindowFlags_NoDocking()
  end

  reaper.ImGui_SetNextWindowSize(ctx, 1200, 600, reaper.ImGui_Cond_FirstUseEver())

  local visible, open = reaper.ImGui_Begin(ctx,
    SCRIPT_NAME .. " v" .. VERSION .. "###clb_main", true, wnd_flags)

  if visible then
    -- Toolbar
    draw_toolbar()

    -- Sources panel (collapsible, between toolbar and table)
    draw_sources_panel()

    -- Track filter panel
    draw_track_filter_panel()

    reaper.ImGui_Separator(ctx)

    -- Main content (EDL table, optionally split with Audio table)
    draw_main_content()

    -- Keyboard shortcuts
    local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
    if focused and not EDIT then
      local shift, cmd = _mods()

      -- Cmd+Z = Undo
      if cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z(), false) then
        if shift then
          do_redo()
        else
          do_undo()
        end
      end

      -- Cmd+Y = Redo
      if cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Y(), false) then
        do_redo()
      end

      -- Cmd+C = Copy
      if cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_C(), false) then
        copy_selection()
      end

      -- Cmd+V = Paste
      if cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_V(), false) then
        paste_selection()
      end

      -- Cmd+A = Select All
      if cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_A(), false) then
        local vr = get_view_rows()
        sel_clear()
        for _, row in ipairs(vr) do
          for c = 1, COL_COUNT do
            sel_add(row.__guid, c)
          end
        end
      end

      -- Delete = Clear selected cells
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete(), false) or
         reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace(), false) then
        local changed = false
        local vr = get_view_rows()
        for _, row in ipairs(vr) do
          for c = 1, COL_COUNT do
            if sel_has(row.__guid, c) and EDITABLE_COLS[c] then
              changed = true
              set_cell_value(row, c, "")
            end
          end
        end
        if changed then
          undo_snapshot()
          CLB.cached_rows = nil; CLB.cached_rows_frame = -1
        end
      end

      -- ESC = Clear selection
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) then
        sel_clear()
      end
    end

    reaper.ImGui_End(ctx)
  end

  -- Pop font
  if font_pushed_this_frame then
    reaper.ImGui_PopFont(ctx)
  end

  if open then
    reaper.defer(loop)
  end
end

---------------------------------------------------------------------------
-- Instance detection
---------------------------------------------------------------------------
local instance_key = EXT_NS .. "_instance"
local prev = reaper.GetExtState(EXT_NS, "instance_id")
local my_id = tostring(math.random(100000, 999999))
reaper.SetExtState(EXT_NS, "instance_id", my_id, false)

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
load_prefs()

ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)
if reaper.ImGui_CreateListClipper then
  list_clipper = reaper.ImGui_CreateListClipper(ctx)
end

console_msg("Conform List Browser v" .. VERSION .. " started")
console_msg("EDL Parser v" .. (EDL.VERSION or "?"))

reaper.defer(loop)
