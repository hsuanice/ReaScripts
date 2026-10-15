--[[
@description Conform List Browser - CLB: conform EDL / AAF / XML / OTIO / subtitle lists (GUI + Jump / Link / Load / Reveal)
@version 26.1015.1941
@author hsuanice
@provides
  [main] .
  [main] hsuanice_Conform List Browser - CLB Jump Old New TC.lua
  [main] hsuanice_Conform List Browser - CLB Link REAPER Items.lua
  [main] hsuanice_Conform List Browser - CLB Load from REAPER.lua
  [main] hsuanice_Conform List Browser - CLB Reveal Item.lua
  [nomain] ../Tools/otio_to_clb.py
  [nomain] ../Tools/aaf_to_otio.py
  [nomain] ../Tools/subtitle_to_clb.py
@changelog
  - Fix: CLB Jump Old New TC could show the previous video frame; jumps land exactly on the frame now, and DME Recut stores jump targets with full precision.
@about
  Note: the Compare view (old vs new cut, reconform) is a work in progress and not finished yet.

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

  Supported formats:
    - CMX3600 EDL (.edl)  — no embedded software/version info in this format
    - XML (.xml)          — FCP7-schema XMEML, read via OpenTimelineIO.
        Confirmed via real project files (Tools/format_tests/, 260923):
          - Adobe Premiere Pro export — 10/10 real samples tested were this.
            Detected via authoringApp="PremierePro" (NOT the <appname>/
            <appversion> tags near the top of the file — Premiere always
            writes "Final Cut Pro"/"7.0" there for schema-compat, regardless
            of the real authoring app; that pair is not a usable signal).
          - Final Cut Pro 7 / DaVinci Resolve XMEML export — same parser
            path, not yet exercised against a real sample from either app.
        UI/track-naming ${format} token shows all of the above simply as
        "XML" (see _friendly_format()); the distinction (CLB.loaded_format:
        "PREMIERE_XML"/"FCP7_XML"/"RESOLVE_XML") is tracked internally only.
    - AAF (.aaf)          — via LibAAF (aaftool) + OpenTimelineIO.
        Confirmed via real project files: Adobe Premiere Pro, versions
        15.0.0 / 25.6.4 / 26.3.0 (read from the AAF's own Identification
        chain via aaf2/pyaaf2 — see Tools/format_tests/aaf_identify.py).
    - Subtitles / dialogue lists — no embedded software/version info:
        .srt                 SubRip absolute time
        .csv / .tsv          Tabular dialogue lists with auto IN/OUT detection
        .xlsx / .xlsm        Excel dialogue lists; multi-sheet picker

    Regression coverage: Tools/format_tests/ holds a golden-snapshot test
    harness (39 real production samples across all formats above, referenced
    by external path — not copied into the repo) that verifies a change to
    one format's parsing doesn't silently break another. Run with:
      lua5.4 Tools/format_tests/run_regression.lua

  Requires: ReaImGui (install via ReaPack)
  Optional: js_ReaScriptAPI (for folder selection)
  Required: Python 3 + opentimelineio (pip3 install opentimelineio)
  Optional: openpyxl  (pip3 install openpyxl) — only for .xlsx subtitle import
  Required for AAF: aaftool in PATH (https://github.com/agfline/LibAAF)
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_EDL Parser.lua', 'hsuanice_OTIO Bridge.lua', 'hsuanice_Subtitle Bridge.lua', 'hsuanice_CLB Compare Engine.lua', 'hsuanice_List Table.lua', 'hsuanice_Time Format.lua', 'hsuanice_Metadata Read.lua', 'hsuanice_Metadata Embed.lua', 'hsuanice_Process Exec.lua', 'json.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

---------------------------------------------------------------------------
-- Library loading
---------------------------------------------------------------------------
local info = debug.getinfo(1, "S")
local script_path = info.source:match("@?(.*[/\\])")
local lib_path = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/"  -- shared hsuanice Library (independent of this script's folder)

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

-- OTIO Bridge (EDL, FCP7 XML, Resolve XML via OpenTimelineIO)
local OTIO_BRIDGE_PATH = lib_path .. "hsuanice_OTIO Bridge.lua"
local ok_otio, OTIO = pcall(dofile, OTIO_BRIDGE_PATH)
if not ok_otio then
  reaper.ShowMessageBox(
    "Cannot load OTIO Bridge library.\n\nExpected at:\n" .. OTIO_BRIDGE_PATH ..
    "\n\nError: " .. tostring(OTIO) ..
    "\n\nOTIO Bridge is required for EDL and XML import.",
    "Conform List Browser", 0)
  return
end

-- Subtitle Bridge (SRT, CSV, TSV, XLSX subtitle / dialogue list import)
local SUBTITLE_BRIDGE_PATH = lib_path .. "hsuanice_Subtitle Bridge.lua"
local ok_sub, SUBTITLE = pcall(dofile, SUBTITLE_BRIDGE_PATH)
if not ok_sub then
  -- Optional: subtitle import is not required for core CLB workflows
  SUBTITLE = nil
end

-- Compare Engine (old-vs-new EDL/XML/AAF reconform comparison)
local COMPARE_ENGINE_PATH = lib_path .. "hsuanice_CLB Compare Engine.lua"
local ok_cmp, COMPARE = pcall(dofile, COMPARE_ENGINE_PATH)
if not ok_cmp then
  -- Optional: compare/reconform is not required for core CLB workflows
  COMPARE = nil
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

-- Metadata Embed and Process Exec: loaded further below, right after the
-- CLB table itself is defined (as CLB.METAEMBED/CLB.PX fields, not new
-- top-level locals like the other optional libs above — this file is
-- already pinned at Lua's 200-local-per-chunk ceiling) — see there.

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
-- Shown in the window title bar — must be kept in sync with @version in
-- the header comment at the top of this file by hand; they are two
-- separate strings with no automatic link between them.
-- Version: read from the @version tag in the header (single source of truth)
local VERSION = "unknown"
do
  local f = io.open(info.source:match("^@(.+)$") or "", "r")
  if f then
    for line in f:lines() do
      local ver = line:match("^@version%s+(.+)$")
      if ver then VERSION = ver break end
      if line:match("^@changelog") then break end
    end
    f:close()
  end
end

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
  GROUP        = 16,
  LEVEL        = 17,
  SCENE        = 18,
  TAKE         = 19,
  SPEED        = 20,
}

local COL_COUNT = 20

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
  FRAMERATE     = 11,  -- sFRAMERATE
  SPEED         = 12,  -- sSPEED
  ORIG_FILENAME = 13,  -- sFiLENAME
  TRACK_NAMES   = 14,  -- sTRK1, sTRK2, etc.
  DESCRIPTION   = 15,
}
local AUDIO_COL_COUNT = 15

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
  [11] = "FPS",
  [12] = "Speed",
  [13] = "Orig File",
  [14] = "Tracks",
  [15] = "Description",
}

local AUDIO_COL_WIDTH = {
  [1]  = 200,  -- Filename
  [2]  = 75,  -- Src TC
  [3]  = 50,   -- Scene
  [4]  = 35,   -- Take
  [5]  = 80,   -- Tape/Roll
  [6]  = 120,  -- Folder
  [7]  = 50,   -- Duration
  [8]  = 35,   -- SR
  [9]  = 35,   -- Ch
  [10] = 100,  -- Project
  [11] = 65,   -- FPS
  [12] = 80,   -- Speed
  [13] = 150,  -- Orig File
  [14] = 120,  -- Tracks
  [15] = 300,  -- Description
}

-- Baseline for Fit Widths (always compute from these, not from current AUDIO_COL_WIDTH)
local AUDIO_DEFAULT_COL_WIDTH = {}
for k, v in pairs(AUDIO_COL_WIDTH) do AUDIO_DEFAULT_COL_WIDTH[k] = v end

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
  [16] = "Group",
  [17] = "Level",
  [18] = "Scene",
  [19] = "Take",
  [20] = "Speed",
}

local DEFAULT_COL_WIDTH = {
  [1]  = 32,
  [2]  = 75,
  [3]  = 50,
  [4]  = 25,
  [5]  = 25,
  [6]  = 75,
  [7]  = 75,
  [8]  = 75,
  [9]  = 75,
  [10] = 75,
  [11] = 300,
  [12] = 300,
  [13] = 300,
  [14] = 70,
  [15] = 25,
  [16] = 65,
  [17] = 65,
  [18] = 55,   -- Scene
  [19] = 40,   -- Take
  [20] = 65,   -- Speed (EDL M2 rate, e.g. "48.0" or "-24.0")
}

-- Columns with short/fixed-length content: kept at DEFAULT_COL_WIDTH during Fit Widths.
-- Remaining visible width is distributed among the "stretchy" content columns.
local FIT_FIXED_COLS = {
  [COL.EVENT]       = true,  -- "#" always 3 digits
  [COL.REEL]        = true,  -- reel ID
  [COL.TRACK]       = true,  -- A/V track (1-2 chars)
  [COL.EDIT_TYPE]   = true,  -- C/W/D
  [COL.DISS_LEN]    = true,  -- dissolve frame count
  [COL.SRC_IN]      = true,  -- HH:MM:SS:FF
  [COL.SRC_OUT]     = true,
  [COL.REC_IN]      = true,
  [COL.REC_OUT]     = true,
  [COL.DURATION]    = true,
  [COL.MATCH_STATUS]= true,  -- short status tag
  [COL.LEVEL]       = true,  -- dB value(s)
  [COL.SPEED]       = true,  -- EDL M2 rate, e.g. "48.0" or "-24.0"
}
-- Stretchy: CLIP_NAME (11), SRC_FILE (12), NOTES (13), MATCHED_PATH (15), GROUP (16)

-- TC columns are fixed-format "HH:MM:SS:FF" text — never user-resizable, in
-- any table/mode that shows them (main event list, Audio list, Recut Group
-- Details). Width still comes from DEFAULT_COL_WIDTH (edit that table to
-- change it).
local TC_COLS = {
  [COL.SRC_IN]  = true,
  [COL.SRC_OUT] = true,
  [COL.REC_IN]  = true,
  [COL.REC_OUT] = true,
}

-- Audio columns with short/fixed-length content: kept at AUDIO_DEFAULT_COL_WIDTH during Fit Widths.
local AUDIO_FIT_FIXED_COLS = {
  [AUDIO_COL.SRC_TC]     = true,  -- timecode HH:MM:SS:FF
  [AUDIO_COL.DURATION]   = true,
  [AUDIO_COL.SAMPLERATE] = true,
  [AUDIO_COL.CHANNELS]   = true,
  [AUDIO_COL.FRAMERATE]  = true,
  [AUDIO_COL.SPEED]      = true,
}
-- Stretchy: FILENAME, SCENE, TAKE, TAPE, FOLDER, PROJECT, ORIG_FILENAME, TRACK_NAMES, DESCRIPTION

-- Audio list's TC column — never user-resizable (see TC_COLS above).
local AUDIO_TC_COLS = {
  [AUDIO_COL.SRC_TC] = true,
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
  [COL.GROUP] = true,
  [COL.LEVEL] = true,
}

-- TC columns (need TC validation)
local TC_COLS = {
  [COL.SRC_IN] = true,
  [COL.SRC_OUT] = true,
  [COL.REC_IN] = true,
  [COL.REC_OUT] = true,
}

-- EDL column display order (default order, can be reordered by user)
local EDL_COL_ORDER = {
  COL.EVENT,        -- 1. #
  COL.REEL,         -- 2. Reel
  COL.TRACK,        -- 3. Track
  COL.EDIT_TYPE,    -- 4. Edit
  COL.LEVEL,        -- 5. Level
  COL.DISS_LEN,     -- 6. Diss
  COL.SRC_IN,       -- 7. Src TC In
  COL.SRC_OUT,      -- 8. Src TC Out
  COL.SPEED,        -- 8b. Speed (EDL M2 rate — retimed/reverse flag)
  COL.REC_IN,       -- 9. Rec TC In
  COL.REC_OUT,      -- 10. Rec TC Out
  COL.DURATION,     -- 11. Duration
  COL.CLIP_NAME,    -- 12. Clip Name
  COL.SRC_FILE,     -- 13. Source File
  COL.NOTES,        -- 14. Notes
  COL.MATCH_STATUS, -- 15. Match
  COL.MATCHED_PATH, -- 16. Matched File
  COL.GROUP,        -- 17. Group
  COL.SCENE,        -- 18. Scene (from OTIO/XML metadata)
  COL.TAKE,         -- 19. Take  (from OTIO/XML metadata)
}

-- EDL column visibility (all visible by default, except Group / Scene / Take)
local EDL_COL_VISIBILITY = {}
for i = 1, COL_COUNT do
  EDL_COL_VISIBILITY[i] = true
end
EDL_COL_VISIBILITY[COL.GROUP] = false
EDL_COL_VISIBILITY[COL.SCENE] = false
EDL_COL_VISIBILITY[COL.TAKE]  = false

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local ctx -- ImGui context
local list_clipper

local CLB = {
  -- File state
  loaded_file = nil,
  loaded_format = nil,  -- ORIGINAL content format (XML/AAF/EDL/...) — for the
                        -- header label and ${format} token; untouched by
                        -- saving/loading a .clb project (see loaded_is_clb).
  loaded_is_clb = false, -- true once loaded_file points at an actual .clb
                          -- project (gates the toolbar's Quick Save button) —
                          -- kept separate from loaded_format so saving as
                          -- .clb doesn't overwrite the remembered original
                          -- source format.
  parsed_data = nil,

  -- EDL source tracking: { { name, path, event_count, visible }, ... }
  edl_sources = {},

  -- Table state
  search_text = "",
  scroll_to_row = nil,
  tl_center_on_guid = nil,  -- list click → center timeline on this row
  visible_range = { first = 0, last = 0 },
  cached_rows = nil,

  -- Settings
  fps = 24,
  is_drop = false,
  track_name_format = "${format} - ${track}",
  last_dir = "",
  last_audio_dir = "",
  -- Generate Ref Media (see CLB.generate_reference_media_prepare): one
  -- real WAV PER EVENT, each with its OWN embedded BWF TimeReference
  -- (that event's real Source TC) + iXML (Scene/Take/Reel) — a
  -- "Simple/shared ONE file" mode existed briefly (fast, few files, but
  -- Source TC lived only in REAPER's own D_STARTOFFS, not embedded in
  -- any file) and was removed entirely at the user's request
  -- (just
  -- keep Full — Basic's need is already covered by the plain "Generate
  -- Items" empty-item placeholder). ref_media_scope ("visible" default |
  -- "selected") picks which rows to use, chosen per run in the popup —
  -- files go in an auto-created subfolder (filenames prefixed "_REF",
  -- user's own request so they stand out once bundled with real
  -- production media) rather than loose in the chosen parent folder.
  -- ref_media_folder is that parent folder (user picks each run, like
  -- Load Audio); ref_media_name_format is the filename template
  -- (${timestamp} token) — used as the subfolder's name.
  ref_media_folder      = "",
  ref_media_name_format = "!CLB_Mute_${timestamp}",
  ref_media_scope       = "visible", -- "visible" | "selected"
  ref_media_pending     = nil,      -- { sox, bwf, usable_rows, folder, sr, retimed_count } between prepare and the scope popup's Next button
  ref_media_want_folder_pick = false, -- set by the scope popup's "Next" button, consumed (folder dialog + reset) right after EndPopup — see its own comment

  -- Load List From Reaper Selection (see CLB.load_from_reaper_selection):
  -- when on, loading from the current Reaper selection also runs Find
  -- Match right after (loading Audio first via the same folder-picker
  -- as "Load Audio" if none is loaded yet) — off by default so the
  -- plain "just read the selection into a list" action never surprises
  -- with an automatic match the user didn't ask for that run.
  ref_load_auto_match = false,

  -- "Follow Reaper" (see CLB.reveal_reaper_item): when on, selecting an
  -- item in Reaper reveals its event row(s). Persisted, off by default.
  follow_reaper_sel = false,
  follow_status = "",        -- last reveal result, shown next to the checkbox
  _follow_sig = nil,         -- Reaper item-selection signature seen last (see CLB._reaper_sel_sig)
  _sel_synced_version = nil, -- SEL.version last pushed to Reaper (see CLB.sync_reaper_from_table_sel)
  sel_cursor = nil,          -- {guid, col}: moving end of keyboard nav (see CLB.table_nav)
  nav_scroll_to_row = nil,   -- row guid: scroll just enough to show it (keyboard nav)
  focus_search = false,      -- Cmd+F → focus the Search box next frame

  -- "ask" (default) shows the usual Replace/Append/Cancel dialog every
  -- run; "replace"/"append" skip it and always do that directly — user's
  -- own request, since re-answering the same dialog on every "Load From
  -- Reaper" run (often repeated many times while iterating) got old.
  -- Set in Options. Only this action honors it — every other loader
  -- (EDL/XML/AAF/Subtitle) always asks, unaffected.
  ref_load_merge_mode = "ask", -- "ask" | "replace" | "append"

  -- UI state
  show_sources_panel = false,
  show_track_filter = true,
  track_filters = {},  -- { { name, count, visible }, ... }
  show_reel_filter = true,
  reel_filters = {},   -- { { name, count, visible }, ... }
  reel_sel = {},       -- { [idx]=true } multi-selected reel indices (visual selection, separate from .visible)
  reel_sel_anchor = nil, -- anchor index for shift-range selection
  show_group_filter = true,
  group_filters = {},  -- { { name, count, visible, tracks={} }, ... }  -- tracks = list of track names in group

  -- Audio file matching state
  audio_files = {},           -- { {path, filename, basename, folder, metadata={}}, ... }
  audio_folder = "",          -- Loaded audio folder path
  audio_recursive = true,     -- Recursive search enabled
  show_audio_panel = false,   -- Show audio panel (auto-enabled when files loaded)
  split_ratio = 0.5,          -- Split ratio for EDL/Audio tables (0.3~0.7)
  audio_search = "",          -- Audio table search filter
  audio_match_filter = nil,   -- When set: {[path]=true,...}; audio table shows only these paths
  clip_name_format = "",      -- Template for clip name rename on match (e.g. "$reel----$sceneT$take")
  audio_cached = nil,         -- Cached filtered audio files
  audio_sort_col = nil,       -- Column to sort by (nil = no sort)
  audio_sort_asc = true,      -- Sort ascending
  audio_fit_content = false,  -- Flag to fit content widths next frame
  edl_fit_content = false,    -- Flag to fit EDL table content widths next frame
  edl_table_gen = 0,          -- Incremented on Fit Widths to reset ImGui column state
  audio_table_gen = 0,        -- Incremented on audio Fit Widths to reset ImGui column state
  edl_fit_mode = false,       -- true = Fit Widths active; button shows "Default"
  audio_fit_mode = false,     -- true = Fit Widths active; button shows "Default"

  -- Timeline panel state
  show_timeline = false,
  tl_zoom = 50.0,   -- pixels per second
  tl_scroll = 0.0,  -- seconds panned from tc_min
  tl_vscroll = 0.0, -- pixels scrolled vertically in track area

  -- Compare (reconform) view state
  compare_old = nil,         -- {name, path, rows, fps, is_drop} loaded via "Load Old..."
  compare_new = nil,         -- {name, path, rows, fps, is_drop} loaded via "Load New..."
  compare_result = nil,      -- set by run_compare(): {old_source,new_source,old_dedup,new_dedup,changes,groups,reordered,fps,is_drop}
  show_compare_view = false, -- true = show dual SRC/DEST timeline instead of the normal table
  viewing_compare_groups = false, -- true = main table (ROWS) is temporarily showing recut-group rows
  show_cmp_details = true,   -- inline Details panel visible while viewing_compare_groups (Hide/Details toggles it)
  cmp_group_details = nil,   -- rebuilt every frame by CMP.refresh_group_details(): {labels, items} — live, follows current row selection
  gd_selected_c = nil,       -- which recut candidate (an item from cmp_group_details.items) is picked in the "Matched Item" column, for Assign/Clear

  -- Apply to Reaper: which resolution strategies are enabled, tried in
  -- fixed priority order Matched Item > Length Match > Range Clear
  -- regardless of toggle order (see CMP.apply_to_reaper). All on by
  -- default.
  apply_mode_matched = true,  -- Matched Item: P_EXT:CLB_REEL + SRC_TC identity, regardless of current position
  apply_mode_length  = true,  -- Length Match: item overlapping the range whose own length matches the target's
  apply_mode_range   = true,  -- Range Clear: clear whatever occupies the range, split at edges, no identity check

  -- Reconform offset: shifts the OLD Reaper session (real items on selected
  -- tracks) out of the way by +/-N hours before Compare-session matching, so
  -- the pristine old cut is preserved as a source pool while the new cut is
  -- rebuilt in the vacated real-timeline space. Hours only for now (no
  -- fractional TC). "New" offset covers the rarer case where the NEW EDL/XML
  -- itself is authored at a non-zero hour and needs the same alignment.
  offset_old_enabled = false,
  offset_old_hours   = 10,
  offset_new_enabled = false,
  offset_new_hours   = 0,
  -- "Calibrate TC (Anchor)" state lives PER SOURCE, not here — see
  -- CLB.edl_sources[i].tc_calib_enabled/tc_calib_delta_sec/tc_calib_note
  -- (set by CLB.calibrate_tc_via_anchor / CLB.calibrate_tc_to_target).
  -- Audio post commonly loads several reels/episodes at once, each
  -- authored by the editor starting at 0 but placed at its own hour slot
  -- on the real session timeline (00595800, 01595800, 02595800...) — a
  -- single global delta can't correct that, so each loaded source gets
  -- its own. tc_calib_target_buf is just the popup's InputText buffer for
  -- CLB.calibrate_tc_to_target, not calibration state itself.
  tc_calib_target_buf = "",

  -- DME Recut settings (remembered between runs — see CLB.dme_recut_prepare/
  -- CLB.dme_recut_execute). "copy" leaves V1's real content untouched and
  -- duplicates from it (the original, safer default); "cut" really moves/
  -- splits the original items, matching Matchbox/Ediload's Cut/Paste mode.
  dme_recut_mode    = "copy",   -- "copy" or "cut"
  dme_recut_markers = true,     -- add Delete/Insert project markers
  dme_recut_pending = nil,      -- { moves, dup_lines, dup_warning, sel_tracks } between prepare and execute

  cmp_zoom = 50.0,
  cmp_scroll = 0.0,
  cmp_vscroll_old = 0.0,
  cmp_vscroll_new = 0.0,
  cmp_split_ratio = 0.5,

  -- Loading state (for async loading with progress)
  -- phase="reading_metadata"  : async audio metadata scanning
  -- phase="otio_loading"      : async OTIO/AAF Python parse in background
  loading_state = nil,        -- { phase, ... }

  -- Generic chunked batch-job state (Generate Items / Conform / Match All):
  -- { label, total, current, batch_size, step=fn(job,i), finish=fn(job) }.
  -- Processed a few items per frame by process_batch_job() (see there) so
  -- the progress bar actually redraws instead of Reaper freezing for the
  -- whole run — same principle as loading_state's audio metadata scan.
  batch_job = nil,

  -- Match picker state
  match_picker_row = nil,     -- Row being matched (for multi-match selection)

  -- Rename/Delete filter state
  rename_filter = nil,        -- { type="track"|"reel", idx, old_name, buf }
  context_filter = nil,       -- { type="track"|"reel", idx, name } for context menu
  delete_filter = nil,        -- { type="track"|"reel", idx, name } for delete confirm
  new_reel_buf = "",          -- Buffer for "Create New Reel" input in row context menu
  batch_rename = nil,         -- { type="track"|"reel", find="", replace="" } for batch rename
  consolidate_tracks = nil,   -- { selected={}, prefix="" } for track consolidation
}

-- Metadata Embed (optional — BWF/iXML write via bwfmetaedit, for
-- CLB.generate_reference_media) and Process Exec (optional — shared
-- shell-exec helper, for the sox call there). CLB.* fields, not new
-- top-level locals like the other optional libs loaded earlier above —
-- this file is already pinned at Lua's 200-local-per-chunk ceiling, so
-- any further top-level local breaks the build; table fields are exempt.
do
  local ok, mod = pcall(dofile, lib_path .. "hsuanice_Metadata Embed.lua")
  CLB.METAEMBED = ok and mod or nil
end
do
  local ok, mod = pcall(dofile, lib_path .. "hsuanice_Process Exec.lua")
  CLB.PX = ok and mod or nil
end

local ROWS = {}    -- Array of row tables
local EDIT = nil   -- { row_idx, col_id, buf, want_focus }

-- Selection model
local SEL = {
  cells = {},             -- set: ["guid:col_id"] = true
  anchor = nil,           -- { guid, col } or nil
  version = 0,            -- bumped on every change — Follow Reaper's CLB→Reaper sync watches it
}

-- Sort state
local SORT_STATE = {
  columns = {},           -- Array of { col_id, ascending }
}

-- Audio column visibility and order
-- User-requested order: Folder, Tape/Roll, Filename, Tracks, Src TC, Scene, Take, Ch, Duration, SR, Project, FPS, Speed, Orig File, Description
local AUDIO_COL_ORDER = {
  AUDIO_COL.FOLDER,        -- 1. Folder
  AUDIO_COL.TAPE,          -- 2. Tape/Roll
  AUDIO_COL.FILENAME,      -- 3. Filename
  AUDIO_COL.TRACK_NAMES,   -- 4. Tracks
  AUDIO_COL.SRC_TC,        -- 5. Src TC
  AUDIO_COL.SCENE,         -- 6. Scene
  AUDIO_COL.TAKE,          -- 7. Take
  AUDIO_COL.CHANNELS,      -- 8. Ch
  AUDIO_COL.DURATION,      -- 9. Duration
  AUDIO_COL.SAMPLERATE,    -- 10. SR
  AUDIO_COL.PROJECT,       -- 11. Project
  AUDIO_COL.FRAMERATE,     -- 12. FPS
  AUDIO_COL.SPEED,         -- 13. Speed
  AUDIO_COL.ORIG_FILENAME, -- 14. Orig File
  AUDIO_COL.DESCRIPTION,   -- 15. Description
}

-- Audio column visibility (all visible by default)
local AUDIO_COL_VISIBILITY = {}
for i = 1, AUDIO_COL_COUNT do
  AUDIO_COL_VISIBILITY[i] = true
end

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

-- CJK-capable font object, populated at startup. nil if no CJK font is found
-- (e.g. on Linux without Noto CJK installed) — in that case ImGui falls back
-- to the default font, which lacks Chinese glyphs.
local cjk_font = nil
local cjk_font_source = ""  -- Human-readable description of which font was loaded

-- Candidate font files to load when the user has not specified a custom path.
-- macOS PingFang.ttc covers Traditional and Simplified Chinese, Japanese, and
-- Hangul, but lacks rare Taiwanese / Hakka characters — users with those
-- needs can point at a custom font in Options → CJK Font…
local CJK_FONT_CANDIDATES = {
  "/System/Library/Fonts/PingFang.ttc",
  "/System/Library/Fonts/STHeiti Medium.ttc",
  "/System/Library/Fonts/Hiragino Sans GB.ttc",
  "C:\\Windows\\Fonts\\msyh.ttc",
  "C:\\Windows\\Fonts\\msjh.ttc",
  "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
  "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
}

--- Try loading a font (file path or family name) and attaching it to the
--- given ImGui context. Returns (font_obj, source_label) on success, or
--- (nil, error_message) on failure.
---
--- @param ctx_         ReaImGui context
--- @param path_or_name string|nil  Path to .ttf/.ttc/.otf, OR a font family name
local function _try_create_font(ctx_, path_or_name)
  if not path_or_name or path_or_name == "" then return nil, "(no path)" end
  if not reaper.ImGui_CreateFont or not reaper.ImGui_Attach then
    return nil, "ReaImGui CreateFont / Attach not available"
  end

  -- File-existence check: only meaningful for absolute paths. Family names
  -- pass through to CoreText / system font resolution.
  local looks_like_path = path_or_name:find("[/\\]") ~= nil
                        or path_or_name:lower():match("%.tt[fc]$")
                        or path_or_name:lower():match("%.otf$")
  if looks_like_path then
    local f = io.open(path_or_name, "rb")
    if not f then
      return nil, "File not found: " .. path_or_name
    end
    f:close()
  end

  local ok, font = pcall(reaper.ImGui_CreateFont, path_or_name, 13)
  if not ok or not font then
    return nil, "CreateFont failed: " .. tostring(font)
  end
  local ok_a, attach_err = pcall(reaper.ImGui_Attach, ctx_, font)
  if not ok_a then
    return nil, "Attach failed: " .. tostring(attach_err)
  end
  return font, path_or_name
end

--- Load a CJK font, preferring the user-supplied path/family, then falling
--- back to the platform candidates list.
---
--- @param ctx_        ReaImGui context
--- @param custom      string|nil  User-supplied font file path or family name
--- @return font_obj|nil
--- @return source_label  When font loaded: path/name that succeeded.
---                       When font is nil: error message describing the failure.
--- @return custom_err string|nil  Non-nil only when the *custom* path was
---                                tried and failed (regardless of whether
---                                a fallback later succeeded).
local function _load_cjk_font(ctx_, custom)
  local custom_err = nil
  if custom and custom ~= "" then
    local font, src = _try_create_font(ctx_, custom)
    if font then return font, src, nil end
    custom_err = tostring(src)
  end
  for _, path in ipairs(CJK_FONT_CANDIDATES) do
    local font, src = _try_create_font(ctx_, path)
    if font then return font, src, custom_err end
  end
  return nil, "(none found)", custom_err
end

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

---------------------------------------------------------------------------
-- Audio Metadata Cache (stored in audio folder)
---------------------------------------------------------------------------

--- Get cache file path for a given folder (stored inside the audio folder itself)
local function get_cache_path(folder, recursive)
  if not folder or folder == "" then return nil end
  local suffix = recursive and "_R" or ""
  return folder .. "/!CLB_Audio_Cache" .. suffix .. ".clbcache"
end

--- Save audio metadata cache to file
local function save_audio_cache(folder, recursive, files)
  local cache_path = get_cache_path(folder, recursive)
  local f = io.open(cache_path, "w")
  if not f then return false end

  -- Header line: folder|recursive|timestamp|file_count
  f:write(string.format("%s|%s|%d|%d\n",
    folder,
    recursive and "R" or "N",
    os.time(),
    #files))

  -- File entries: path|filename|basename|folder|sr|ch|dur|scene|take|tape|reel|project|timeref|src_tc|desc|framerate|speed|orig_filename|track_names|ubits
  for _, file in ipairs(files) do
    local m = file.metadata or {}
    local line = string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n",
      file.path or "",
      file.filename or "",
      file.basename or "",
      file.folder or "",
      tostring(m.samplerate or 0),
      tostring(m.channels or 0),
      tostring(m.duration or 0),
      (m.scene or ""):gsub("|", "_"),
      (m.take or ""):gsub("|", "_"),
      (m.tape or ""):gsub("|", "_"),
      (m.reel or ""):gsub("|", "_"),
      (m.project or ""):gsub("|", "_"),
      (m.timereference or ""):gsub("|", "_"),
      (m.src_tc or ""):gsub("|", "_"),
      (m.description or ""):gsub("|", "_"):gsub("\n", " "),
      (m.framerate or ""):gsub("|", "_"),
      (m.speed or ""):gsub("|", "_"),
      (m.orig_filename or ""):gsub("|", "_"),
      (m.track_names or ""):gsub("|", "_"),
      (m.ubits or ""):gsub("|", "_"))
    f:write(line)
  end

  f:close()
  console_msg("Saved audio cache: " .. cache_path)
  return true
end

-- Forward-declared here so load_audio_cache/scan_audio_folder below can use
-- it for filename sort order (natural sort: A1, A2, A10 instead of A1, A10,
-- A2); actually defined further down, alongside its other users (track/
-- reel/group sorts).
local _natural_sort_cmp

-- Forward-declared here so match_audio_files below can use it (to tell
-- Video rows apart from Audio ones when inferring Scene/Take from
-- overlapping audio); actually defined further down, alongside its other
-- use (initial auto-assign of row.group on load).
local _get_track_group

--- Load audio metadata cache from file
--- Returns files array if cache valid, nil if cache invalid/missing
local function load_audio_cache(folder, recursive)
  local cache_path = get_cache_path(folder, recursive)
  local f = io.open(cache_path, "r")
  if not f then return nil end

  -- Read header
  local header = f:read("*l")
  if not header then f:close(); return nil end

  local h_folder, h_rec, _, h_count = header:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
  if not h_folder or h_folder ~= folder then
    f:close()
    return nil
  end

  local file_count = tonumber(h_count) or 0

  -- Read file entries
  local files = {}
  for line in f:lines() do
    local parts = {}
    for part in (line .. "|"):gmatch("([^|]*)|") do
      parts[#parts + 1] = part
    end

    if #parts >= 15 then
      files[#files + 1] = {
        path = parts[1],
        filename = parts[2],
        basename = parts[3],
        folder = parts[4],
        metadata = {
          samplerate = tonumber(parts[5]) or 0,
          channels = tonumber(parts[6]) or 0,
          duration = tonumber(parts[7]) or 0,
          scene = parts[8],
          take = parts[9],
          tape = parts[10],
          reel = parts[11],
          project = parts[12],
          timereference = parts[13],
          src_tc = parts[14],
          description = parts[15],
          -- New fields (v2 cache format, parts 16-20)
          framerate = parts[16] or "",
          speed = parts[17] or "",
          orig_filename = parts[18] or "",
          track_names = parts[19] or "",
          ubits = parts[20] or "",
          bwf_fields = {},
        }
      }
    end
  end

  f:close()

  -- Verify file count matches
  if #files ~= file_count then
    console_msg("Cache file count mismatch, will rescan")
    return nil
  end

  -- Natural sort (A1, A2, A10 instead of A1, A10, A2) — applied here so a
  -- cache saved before this fix existed still comes back in the right
  -- order, not whatever order it happened to be saved in.
  table.sort(files, function(a, b) return _natural_sort_cmp(a.filename or "", b.filename or "") end)

  console_msg(string.format("Loaded %d files from cache", #files))
  return files
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

  -- Sort by filename (natural sort: A1, A2, A10 instead of A1, A10, A2)
  table.sort(files, function(a, b)
    return _natural_sort_cmp(a.filename or "", b.filename or "")
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

--- Core of read_audio_metadata: reads BWF/iXML fields from an EXISTING
--- PCM_Source object (e.g. a REAPER item take's own source via
--- GetMediaItemTake_Source) — doesn't create or destroy anything, so
--- it's also what CLB.load_from_reaper_selection reuses to read the
--- exact same fields from items already in the project, instead of
--- duplicating this logic against a path it would have to re-derive.
--- @param src userdata|nil  An existing PCM_Source
--- @return table  Metadata table (same shape/defaults either way)
function CLB._read_metadata_from_source(src)
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
    -- Additional fields from BWF Description
    framerate = "",          -- sFRAMERATE
    speed = "",              -- sSPEED
    orig_filename = "",      -- sFiLENAME (original filename)
    track_names = "",        -- sTRK1, sTRK2, etc. (comma-separated)
    ubits = "",              -- sUBITS
  }

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
      local bf = meta.bwf_fields

      -- Extract reel from description (sTRK#/dREEL format)
      meta.reel = bf["REEL"] or bf["sREEL"] or bf["dREEL"] or ""

      -- Also try SCENE, TAKE, TAPE from BWF if iXML was empty
      if meta.scene == "" then meta.scene = bf["SCENE"] or bf["sSCENE"] or "" end
      if meta.take == ""  then meta.take  = bf["TAKE"]  or bf["sTAKE"]  or "" end
      if meta.tape == ""  then meta.tape  = bf["TAPE"]  or bf["sTAPE"]  or "" end

      -- Extract project from BWF if iXML was empty
      if meta.project == "" then meta.project = bf["PROJECT"] or bf["sPROJECT"] or "" end

      -- Extract additional fields
      meta.framerate = bf["FRAMERATE"] or bf["sFRAMERATE"] or ""
      meta.speed = bf["SPEED"] or bf["sSPEED"] or ""
      meta.orig_filename = bf["FILENAME"] or bf["sFiLENAME"] or bf["sFILENAME"] or ""
      meta.ubits = bf["UBITS"] or bf["sUBITS"] or ""

      -- Collect track names (sTRK1, sTRK2, sTRK3, etc.)
      local trk_names = {}
      for i = 1, 32 do  -- Check up to 32 tracks
        local key = "TRK" .. i
        local val = bf[key] or bf["s" .. key] or bf["d" .. key]
        if val and val ~= "" then
          trk_names[#trk_names + 1] = string.format("%d:%s", i, val)
        end
      end
      meta.track_names = table.concat(trk_names, ", ")
    end

    -- If no reel from description, try tape as reel
    if meta.reel == "" and meta.tape ~= "" then
      meta.reel = meta.tape
    end
  end

  return meta
end

--- Read metadata from an external audio file — creates a temporary
--- PCM_Source just for this call (destroyed before returning); see
--- CLB._read_metadata_from_source for the actual field-reading logic,
--- shared with reading an existing item take's own source directly.
--- @param filepath string  Full path to audio file
--- @return table  Metadata table
local function read_audio_metadata(filepath)
  if not filepath or filepath == "" then return CLB._read_metadata_from_source(nil) end
  local src = reaper.PCM_Source_CreateFromFile(filepath)
  if not src then return CLB._read_metadata_from_source(nil) end
  local meta = CLB._read_metadata_from_source(src)
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

--- Generate timestamp string for filenames (YYMMDD_HHMMSS)
local function timestamp()
  return os.date("%y%m%d_%H%M%S")
end

--- Write text to file
local function write_text_file(path, text)
  local f = io.open(path, "w")
  if f then
    f:write(text)
    f:close()
    return true
  end
  return false
end

--- Choose save path using file dialog
local function choose_save_path(default_name, filter)
  local retval, filepath
  if reaper.JS_Dialog_BrowseForSaveFile then
    retval, filepath = reaper.JS_Dialog_BrowseForSaveFile(
      "Save File", CLB.last_dir or "", default_name, filter)
  else
    retval, filepath = reaper.GetUserFileNameForRead("", "Save As", filter)
  end
  if retval == 1 or (retval and filepath and filepath ~= "") then
    return filepath
  end
  return nil
end

--- Get audio cell text for export (similar to get_audio_cell_value but returns string)
local function get_audio_cell_text(af, col)
  local meta = af.metadata or {}
  if col == AUDIO_COL.FILENAME then return af.filename or ""
  elseif col == AUDIO_COL.SRC_TC then return meta.src_tc or ""
  elseif col == AUDIO_COL.SCENE then return meta.scene or ""
  elseif col == AUDIO_COL.TAKE then return meta.take or ""
  elseif col == AUDIO_COL.TAPE then return meta.tape or meta.reel or ""
  elseif col == AUDIO_COL.FOLDER then return af.folder or ""
  elseif col == AUDIO_COL.DURATION then return format_duration(meta.duration)
  elseif col == AUDIO_COL.SAMPLERATE then return format_samplerate(meta.samplerate)
  elseif col == AUDIO_COL.CHANNELS then return meta.channels and tostring(meta.channels) or ""
  elseif col == AUDIO_COL.PROJECT then return meta.project or ""
  elseif col == AUDIO_COL.FRAMERATE then return meta.framerate or ""
  elseif col == AUDIO_COL.SPEED then return meta.speed or ""
  elseif col == AUDIO_COL.ORIG_FILENAME then return meta.orig_filename or ""
  elseif col == AUDIO_COL.TRACK_NAMES then return meta.track_names or ""
  elseif col == AUDIO_COL.DESCRIPTION then return meta.description or ""
  end
  return ""
end

--- Escape field value for TSV/CSV export
local function escape_field_value(val, format_type)
  if not val then return "" end
  val = tostring(val)

  if format_type == "csv" then
    -- CSV: wrap in quotes if contains comma, quote, or newline
    if val:find('[,"\n\r]') then
      val = '"' .. val:gsub('"', '""') .. '"'
    end
  else
    -- TSV: replace newlines with space (no standard quoting in TSV)
    val = val:gsub('[\n\r]+', ' ')
    -- Also replace tabs with spaces
    val = val:gsub('\t', ' ')
  end
  return val
end

--- Build audio table text for export (TSV or CSV)
local function build_audio_table_text(format_type, rows, col_order, col_visibility)
  local sep = format_type == "csv" and "," or "\t"
  local lines = {}

  -- Header row
  local headers = {}
  for _, col in ipairs(col_order) do
    if col_visibility[col] then
      local h = AUDIO_HEADER_LABELS[col] or ""
      table.insert(headers, escape_field_value(h, format_type))
    end
  end
  table.insert(lines, table.concat(headers, sep))

  -- Data rows
  for _, af in ipairs(rows) do
    local cells = {}
    for _, col in ipairs(col_order) do
      if col_visibility[col] then
        local val = get_audio_cell_text(af, col)
        table.insert(cells, escape_field_value(val, format_type))
      end
    end
    table.insert(lines, table.concat(cells, sep))
  end

  return table.concat(lines, "\n")
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
end

--- Match audio files to EDL events
---------------------------------------------------------------------------
-- Scene / Take normalisation helpers
---------------------------------------------------------------------------

--- Strip leading zeros from a single token and uppercase any alpha suffix.
--- "01B" → "1B"   "06" → "6"   "T05" → "T5"   "A" → "A"
local function _norm_scene_token(s)
  -- numeric prefix + optional alpha suffix
  local num, alpha = s:match("^0*(%d*)([A-Za-z]*)$")
  if num then
    local n = (num ~= "" and tostring(tonumber(num)) or "")
    local a = alpha:upper()
    if n == "" and a == "" then return "0" end
    return (n ~= "0" and n or (a ~= "" and "" or "0")) .. a
  end
  return s:upper()
end

--- Normalise a scene string to a canonical dash-separated key for comparison.
--- Splits on any non-alphanumeric separator, strips leading zeros per token.
--- "6-01B-02" → "6-1B-2"   "06_01B_01" → "6-1B-1"   "06-01B-02" → "6-1B-2"
local function normalize_scene_key(s)
  if not s or s == "" then return "" end
  local parts = {}
  for tok in s:gmatch("[%w]+") do
    parts[#parts + 1] = _norm_scene_token(tok)
  end
  return table.concat(parts, "-")
end

--- Normalise a take string: strip leading zeros, return as string.
--- "05" → "5"   "1" → "1"   "T03" → strip T then "3"
local function normalize_take_key(s)
  if not s or s == "" then return "" end
  -- Strip optional leading 'T'/'t'
  local t = s:match("^[Tt](%d+)$") or s:match("^(%d+)$") or s
  local n = tonumber(t)
  return n and tostring(n) or t:upper()
end

--- Common pre-processing: strip known trailing annotations and channel suffix.
--- Returns a trimmed string ready for pattern matching.
local function _clip_name_clean(name)
  if not name or name == "" then return "" end
  -- Strip " - Merged / Synced / MOS / Mix / Stem" and anything after
  name = name:gsub("%s*[-–]%s*[Mm]erged.*$",  "")
             :gsub("%s*[-–]%s*[Ss]ynced.*$",  "")
             :gsub("%s*[-–]%s*[Mm][Oo][Ss].*$", "")
             :gsub("%s*[-–]%s*[Ss]tem.*$",     "")
  -- Strip single-letter channel suffix at the very end: _A _B _a …
  name = name:gsub("_[A-Za-z]$", "")
  return name:match("^(.-)%s*$") or ""   -- trim trailing whitespace
end

--- Pattern A — underscore-T take:  EP_SCENE_SHOT_T## [_Channel] [- Merged…]
---   "06_01B_02_T01 - Merged"   →  ("6-1B-2", "1")
---   "06_01B_01_T05_A - Merged" →  ("6-1B-1", "5")
local function parse_scene_take_from_clip_name(name)
  name = _clip_name_clean(name)
  if name == "" then return "", "" end
  local body, take_raw = name:match("^(.+)_[Tt](%d+)$")
  if not body then return "", "" end
  local take  = tostring(tonumber(take_raw))
  local parts = {}
  for p in body:gmatch("[^_]+") do parts[#parts + 1] = _norm_scene_token(p) end
  return table.concat(parts, "-"), take
end

--- Pattern B — slash-T take:  SCENE /t## [suffix]
--- Handles names like:  "9-1-1    /t2    .new.01"
---   The scene is everything before the first  /T  or  /t  (with optional
---   surrounding whitespace).  The take is the digit run immediately after.
---   Anything after the take (version tags like ".new.01") is ignored.
local function _parse_slasht(name)
  name = _clip_name_clean(name)
  if name == "" then return "", "" end
  -- Primary: explicit "/t##" or "/ t##"
  local scene_raw, take_raw = name:match("^(.-)%s*/%s*[Tt](%d+)")
  if not scene_raw or scene_raw == "" then return "", "" end
  local scene = normalize_scene_key(scene_raw:match("^(.-)%s*$") or scene_raw)
  return scene, tostring(tonumber(take_raw))
end

--- Pattern C — bare-T take at end:  SCENE T## or SCENE-T##
--- Handles:  "9-1-1 T2",  "9-1-1-T03",  "Scene01 T5"
--- The T must be preceded by a non-digit separator so we don't confuse
--- alphanumeric scene codes like "1B" with a take indicator.
local function _parse_bare_t(name)
  name = _clip_name_clean(name)
  if name == "" then return "", "" end
  -- Separator before T must be non-alphanumeric (space, dash, dot, _)
  local scene_raw, take_raw = name:match("^(.-)%s*[%-%._% ]%s*[Tt](%d+)%s*$")
  if not scene_raw or scene_raw == "" then return "", "" end
  local scene = normalize_scene_key(scene_raw:match("^(.-)%s*$") or scene_raw)
  return scene, tostring(tonumber(take_raw))
end

--- All parsers tried by Strategy 6, in priority order.
--- Each entry: { id, label, fn }
local SCENE_TAKE_PARSERS = {
  { id = "meta",  label = "Existing metadata",      fn = nil },   -- handled separately
  { id = "A",     label = "EP_SCENE_SHOT_T##",       fn = parse_scene_take_from_clip_name },
  { id = "B",     label = "SCENE /t##",              fn = _parse_slasht   },
  { id = "C",     label = "SCENE-T## / SCENE T##",   fn = _parse_bare_t   },
}

--- Apply CLB.clip_name_format template to a row.
-- Tokens (case-insensitive): $reel, $scene, $take
local function _apply_clip_name_format(row)
  local fmt = CLB.clip_name_format or ""
  if fmt == "" then return end
  local result = fmt
    :gsub("%$[Rr][Ee][Ee][Ll]",  row.reel  or "")
    :gsub("%$[Ss][Cc][Ee][Nn][Ee]", row.scene or "")
    :gsub("%$[Tt][Aa][Kk][Ee]",  row.take  or "")
  if result ~= "" then
    row.clip_name = result
  end
end

local _rebuild_reel_filters  -- forward declaration (defined later)

local function match_audio_files()
  if CLB.batch_job then
    reaper.ShowMessageBox("Another operation (" .. (CLB.batch_job.label or "batch job") .. ") is still running — wait for it to finish first.", SCRIPT_NAME, 0)
    return
  end
  if #CLB.audio_files == 0 or #ROWS == 0 then return end

  console_msg("Starting audio matching...")

  -- Build audio file indexes
  local by_basename   = {}   -- filename (lowercase, no ext) → {audio_file, ...}
  local by_tape       = {}   -- tape/reel metadata (lowercase) → {audio_file, ...}
  local by_scene_take = {}   -- "norm_scene/norm_take" → {audio_file, ...}

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

    -- Index by normalised scene + take  (Strategy 6)
    if af.metadata then
      local sk = normalize_scene_key(af.metadata.scene or "")
      local tk = normalize_take_key (af.metadata.take  or "")
      if sk ~= "" and tk ~= "" then
        local k = sk .. "/" .. tk
        by_scene_take[k] = by_scene_take[k] or {}
        by_scene_take[k][#by_scene_take[k] + 1] = af
      end
    end
  end

  -- Match each EDL row — a chunk per frame via the shared batch-job runner
  -- (see CLB.process_batch_job), since Strategy 4's fuzzy scan is
  -- O(rows_needing_it × total_audio_files) and can be genuinely slow on a
  -- large list (this tool routinely sees thousands of rows against
  -- thousands of audio files). finish() below runs once, after the last
  -- row: rebuilds search text, prints the console summary, and runs the
  -- audio→video Scene/Take inference pass — all pure in-memory Lua, fast
  -- enough to stay synchronous even at full row count.
  CLB.batch_job = {
    label = "Matching audio",
    total = #ROWS,
    current = 0,
    found_count = 0,
    multiple_count = 0,
    not_found_count = 0,
    s6_stats   = {},                          -- parser_id → match count
    backfill_n = { scene = 0, take = 0, reel = 0 },
    batch_size = 100,
    step = function(job, i)
    local row = ROWS[i]
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

    -- Strategy 5 (fallback): Tape+TC range match — ignores filename entirely.
    -- Used when EDL has wrong clip name but correct reel/TC (e.g. wipe TO=BL or
    -- a typo in the clip name field). Marks result as "Fallback" so the UI can
    -- flag it visually. fallback_kind records WHICH fallback strategy actually
    -- produced the match (Strategy 5 = "tape_tc", Strategy 6 below =
    -- "scene_take") so the UI can show the right reason instead of assuming
    -- Tape+TC for every fallback — a Strategy-6 (Scene+Take-only) match never
    -- checked source TC at all, so it needs its own distinct warning.
    local fallback_kind = nil
    if #candidates == 0 and row.reel and row.reel ~= "" and
       row.src_tc_in and row.src_tc_in ~= "" then
      local reel_lower = row.reel:lower()
      local tape_files = by_tape[reel_lower] or {}
      if #tape_files > 0 then
        local row_tc_sec = EDL.tc_to_seconds(row.src_tc_in, CLB.fps, CLB.is_drop)
        if row_tc_sec then
          for _, af in ipairs(tape_files) do
            local af_tc_str = af.metadata and af.metadata.src_tc or ""
            local af_dur    = af.metadata and (af.metadata.duration or 0) or 0
            if af_tc_str ~= "" and af_dur > 0 then
              local af_tc_sec = EDL.tc_to_seconds(af_tc_str, CLB.fps, CLB.is_drop)
              if af_tc_sec and
                 row_tc_sec >= af_tc_sec - 0.04 and
                 row_tc_sec <  af_tc_sec + af_dur + 0.04 then
                candidates[#candidates + 1] = af
              end
            end
          end
        end
      end
      if #candidates > 0 then fallback_kind = "tape_tc" end
    end

    -- Strategy 6: normalised Scene + Take match — source TC is never
    -- consulted here at all (unlike Strategy 5, which at least confirms the
    -- audio file's own embedded TC range covers the EDL row's src_tc_in).
    -- This exists for productions where the audio recorder wasn't jam-
    -- synced to camera (embedded TC is meaningless) but slate scene/take
    -- numbers are trustworthy — real, but strictly weaker evidence than any
    -- TC-based strategy, so it's flagged as "Fallback" too (fallback_kind
    -- = "scene_take") rather than silently reported as "Found"/"Multiple"
    -- the same as an identity- or TC-verified match.
    -- Tries (in order):
    --   1. Existing scene/take metadata on the row (from AAF UserComments or
    --      otio_to_clb.py clip-name parse)
    --   2. All SCENE_TAKE_PARSERS applied to row.clip_name in priority order
    -- The first parser that produces a hit in by_scene_take wins.
    -- Statistics are collected per parser for the console summary.
    if #candidates == 0 then
      local clip_name = row.clip_name or ""

      -- 1. Try existing row metadata first (fastest, most reliable)
      local r_scene = normalize_scene_key(row.scene or "")
      local r_take  = normalize_take_key (row.take  or "")
      if r_scene ~= "" and r_take ~= "" then
        local hits = by_scene_take[r_scene .. "/" .. r_take] or {}
        if #hits > 0 then
          for _, af in ipairs(hits) do candidates[#candidates + 1] = af end
          job.s6_stats["meta"] = (job.s6_stats["meta"] or 0) + 1
        end
      end

      -- 2. Try each clip-name parser until one produces a hit
      if #candidates == 0 then
        for _, parser in ipairs(SCENE_TAKE_PARSERS) do
          if parser.fn then   -- skip the "meta" sentinel (fn=nil)
            local ps, pt = parser.fn(clip_name)
            if ps ~= "" and pt ~= "" then
              local hits = by_scene_take[ps .. "/" .. pt] or {}
              if #hits > 0 then
                for _, af in ipairs(hits) do candidates[#candidates + 1] = af end
                job.s6_stats[parser.id] = (job.s6_stats[parser.id] or 0) + 1
                -- Promote the parsed scene/take onto the row so backfill
                -- can use the normalised form if the original fields are empty.
                if (row.scene or "") == "" then row.scene = ps end
                if (row.take  or "") == "" then row.take  = pt end
                break
              end
            end
          end
        end
      end
      if #candidates > 0 then fallback_kind = "scene_take" end
    end

    -- Set match result
    row.__fallback_kind = fallback_kind
    if #candidates == 1 then
      row.match_status = fallback_kind and "Fallback" or "Found"
      row.matched_path = candidates[1].path
      row.__match_candidates = nil
      job.found_count = job.found_count + 1

      -- Repair Tape/Clip Name from matched audio; backfill Scene/Take only when empty.
      -- Original values are preserved in notes; repaired rows are flagged.
      local af_meta = candidates[1].metadata
      if af_meta then
        local orig_notes = {}

        -- Scene / Take: fill only when empty
        if (row.scene or "") == "" and (af_meta.scene or "") ~= "" then
          row.scene = af_meta.scene
          job.backfill_n.scene = job.backfill_n.scene + 1
        end
        if (row.take or "") == "" and (af_meta.take or "") ~= "" then
          row.take = af_meta.take
          job.backfill_n.take = job.backfill_n.take + 1
        end

        -- Tape: always repair from matched audio
        local row_repaired = false
        local new_tape = af_meta.tape or af_meta.reel or ""
        if new_tape ~= "" then
          local old_tape = row.reel or ""
          if old_tape ~= new_tape then
            if old_tape ~= "" then
              orig_notes[#orig_notes+1] = "Orig Tape: " .. old_tape
            end
            row.reel = new_tape
            job.backfill_n.reel = job.backfill_n.reel + 1
            row_repaired = true
          end
        end

        -- Mark repaired and save originals to notes
        if row_repaired then
          row.__repaired = true
          if #orig_notes > 0 then
            local existing = row.notes or ""
            local prefix = table.concat(orig_notes, " | ")
            row.notes = existing ~= "" and (prefix .. " | " .. existing) or prefix
          end
        end

      end
    elseif #candidates > 1 then
      row.match_status = fallback_kind and "Fallback" or "Multiple"
      row.matched_path = string.format("(%d)", #candidates)
      row.__match_candidates = candidates
      job.multiple_count = job.multiple_count + 1

      -- Backfill from candidates[1] — all candidates are channels of the same
      -- recording so they share scene/take/tape metadata.
      local af_meta = candidates[1].metadata
      if af_meta then
        local orig_notes = {}

        if (row.scene or "") == "" and (af_meta.scene or "") ~= "" then
          row.scene = af_meta.scene
          job.backfill_n.scene = job.backfill_n.scene + 1
        end
        if (row.take or "") == "" and (af_meta.take or "") ~= "" then
          row.take = af_meta.take
          job.backfill_n.take = job.backfill_n.take + 1
        end

        local row_repaired = false
        local new_tape = af_meta.tape or af_meta.reel or ""
        if new_tape ~= "" then
          local old_tape = row.reel or ""
          if old_tape ~= new_tape then
            if old_tape ~= "" then
              orig_notes[#orig_notes+1] = "Orig Tape: " .. old_tape
            end
            row.reel = new_tape
            job.backfill_n.reel = job.backfill_n.reel + 1
            row_repaired = true
          end
        end

        if row_repaired then
          row.__repaired = true
          if #orig_notes > 0 then
            local existing = row.notes or ""
            local prefix = table.concat(orig_notes, " | ")
            row.notes = existing ~= "" and (prefix .. " | " .. existing) or prefix
          end
        end

      end
    else
      row.match_status = "Not Found"
      row.matched_path = ""
      row.__match_candidates = nil
      job.not_found_count = job.not_found_count + 1
    end
    end,
    finish = function(job)
  CLB.cached_rows = nil

  -- Rebuild search text for all rows (scene/take/reel may have been updated)
  for _, row in ipairs(ROWS) do
    row.__search_text = table.concat({
      row.event_num or "", row.reel or "", row.track or "",
      row.clip_name or "", row.source_file or "", row.notes or "",
      row.group or "", row.level or "",
      row.scene or "", row.take or "",
      row.src_tc_in or "", row.src_tc_out or "",
      row.rec_tc_in or "", row.rec_tc_out or "",
      row.duration or "",
    }, " "):lower()
  end

  local fallback_tc_count, fallback_st_count = 0, 0
  for _, row in ipairs(ROWS) do
    if row.match_status == "Fallback" then
      if row.__fallback_kind == "scene_take" then
        fallback_st_count = fallback_st_count + 1
      else
        fallback_tc_count = fallback_tc_count + 1
      end
    end
  end
  local fallback_parts = {}
  if fallback_tc_count > 0 then fallback_parts[#fallback_parts+1] = string.format("%d fallback (Tape+TC only)", fallback_tc_count) end
  if fallback_st_count > 0 then fallback_parts[#fallback_parts+1] = string.format("%d fallback (Scene+Take only, TC unverified)", fallback_st_count) end
  console_msg(string.format(
    "Matching complete: %d found, %d multiple, %d not found%s",
    job.found_count, job.multiple_count, job.not_found_count,
    #fallback_parts > 0 and (", " .. table.concat(fallback_parts, ", ")) or ""))

  -- Strategy 6 detail: which parsers matched how many clips
  local s6_total = 0
  for _, v in pairs(job.s6_stats) do s6_total = s6_total + v end
  if s6_total > 0 then
    local parser_labels = {
      meta = "Existing metadata",
      A    = "Pattern A  EP_SCENE_SHOT_T##",
      B    = "Pattern B  SCENE /t##",
      C    = "Pattern C  SCENE-T## / SCENE T##",
    }
    console_msg(string.format("  Strategy 6 (Scene+Take): %d clip(s) matched", s6_total))
    -- Print in definition order so output is stable
    for _, p in ipairs(SCENE_TAKE_PARSERS) do
      local n = job.s6_stats[p.id] or 0
      if n > 0 then
        console_msg(string.format("    %-38s %d clip(s)",
          (parser_labels[p.id] or p.id) .. ":", n))
      end
    end
  end

  -- Repair / backfill summary
  local bf_parts = {}
  if job.backfill_n.scene     > 0 then bf_parts[#bf_parts+1] = job.backfill_n.scene     .. " scene"     end
  if job.backfill_n.take      > 0 then bf_parts[#bf_parts+1] = job.backfill_n.take      .. " take"      end
  if job.backfill_n.reel      > 0 then bf_parts[#bf_parts+1] = job.backfill_n.reel      .. " tape"      end

  if #bf_parts > 0 then
    console_msg("  Repaired: " .. table.concat(bf_parts, ", ") .. " value(s) from matched audio  [✦ = repaired row]")
  end

  -- Infer Scene/Take for Video rows whose own metadata is still empty
  -- (clip name gave nothing, and no BWF-metadata backfill applies to
  -- Video rows the way it does for matched Audio rows), from the majority
  -- Scene/Take among Audio rows overlapping the same REC TC range —
  -- copied verbatim, not split. This production's Scene field may itself
  -- be a combined "Scene-Shot" value like "P1-1"; that's preserved as-is
  -- here — Scene Cuts strips it down to just the scene prefix at its own
  -- use site instead of this being split at the source. A handful of
  -- inserts/cutaways voting for a different scene in the same range are
  -- outvoted and ignored.
  do
    local audio_evts = {}
    for _, row in ipairs(ROWS) do
      if _get_track_group(row.track) == "Audio" and ((row.scene or "") ~= "" or (row.take or "") ~= "") then
        audio_evts[#audio_evts + 1] = {
          rec_in  = EDL.tc_to_seconds(row.rec_tc_in,  CLB.fps, CLB.is_drop),
          rec_out = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop),
          scene   = row.scene or "",
          take    = row.take  or "",
        }
      end
    end
    table.sort(audio_evts, function(a, b) return a.rec_in < b.rec_in end)

    local function vote(rec_in, rec_out, field)
      local votes, first_seen = {}, {}
      for _, a in ipairs(audio_evts) do
        if a.rec_in >= rec_out then break end   -- sorted by rec_in: nothing further can overlap
        if a.rec_out > rec_in and a[field] ~= "" then
          local key = a[field]:upper()
          votes[key] = (votes[key] or 0) + 1
          first_seen[key] = first_seen[key] or a[field]
        end
      end
      local best_key, best_n = nil, 0
      for key, n in pairs(votes) do
        if n > best_n then best_key, best_n = key, n end
      end
      return best_key and first_seen[best_key] or nil
    end

    local scene_inferred_n, take_inferred_n = 0, 0
    if #audio_evts > 0 then
      for _, row in ipairs(ROWS) do
        if _get_track_group(row.track) == "Video" then
          local need_scene = (row.scene or "") == ""
          local need_take  = (row.take  or "") == ""
          if need_scene or need_take then
            local rec_in  = EDL.tc_to_seconds(row.rec_tc_in,  CLB.fps, CLB.is_drop)
            local rec_out = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
            local touched = false
            if need_scene then
              local s = vote(rec_in, rec_out, "scene")
              if s then row.scene = s; scene_inferred_n = scene_inferred_n + 1; touched = true end
            end
            if need_take then
              local t = vote(rec_in, rec_out, "take")
              if t then row.take = t; take_inferred_n = take_inferred_n + 1; touched = true end
            end
            if touched then
              row.__scene_inferred = true
              row.notes = ((row.notes or "") ~= "" and (row.notes .. " | ") or "") .. "Scene/Take inferred from overlapping audio"
              row.__search_text = table.concat({
                row.event_num or "", row.reel or "", row.track or "",
                row.clip_name or "", row.source_file or "", row.notes or "",
                row.group or "", row.level or "",
                row.scene or "", row.take or "",
                row.src_tc_in or "", row.src_tc_out or "",
                row.rec_tc_in or "", row.rec_tc_out or "",
                row.duration or "",
              }, " "):lower()
            end
          end
        end
      end
    end
    if scene_inferred_n > 0 or take_inferred_n > 0 then
      console_msg(string.format(
        "  Video Scene/Take inferred from overlapping audio: %d scene, %d take value(s)  [orange Scene/Take = inferred]",
        scene_inferred_n, take_inferred_n))
    end
  end

  -- Reel values may have changed; refresh the Reel Filter sidebar
  _rebuild_reel_filters()
    end,
  }
end

--- Get value for audio file column (for sorting)
local function get_audio_col_value(af, col)
  local meta = af.metadata or {}
  if col == AUDIO_COL.FILENAME then return af.filename or ""
  elseif col == AUDIO_COL.SRC_TC then return meta.src_tc or ""
  elseif col == AUDIO_COL.SCENE then return meta.scene or ""
  elseif col == AUDIO_COL.TAKE then return meta.take or ""
  elseif col == AUDIO_COL.TAPE then return meta.tape or meta.reel or ""
  elseif col == AUDIO_COL.FOLDER then return af.folder or ""
  elseif col == AUDIO_COL.DURATION then return meta.duration or 0
  elseif col == AUDIO_COL.SAMPLERATE then return meta.samplerate or 0
  elseif col == AUDIO_COL.CHANNELS then return meta.channels or 0
  elseif col == AUDIO_COL.PROJECT then return meta.project or ""
  elseif col == AUDIO_COL.FRAMERATE then return meta.framerate or ""
  elseif col == AUDIO_COL.SPEED then return meta.speed or ""
  elseif col == AUDIO_COL.ORIG_FILENAME then return meta.orig_filename or ""
  elseif col == AUDIO_COL.TRACK_NAMES then return meta.track_names or ""
  elseif col == AUDIO_COL.DESCRIPTION then return meta.description or ""
  end
  return ""
end

--- Get filtered and sorted audio files for display
local function get_audio_view_rows()
  if CLB.audio_cached then
    return CLB.audio_cached
  end

  local result
  local search = (CLB.audio_search or ""):lower()
  local match_filter = CLB.audio_match_filter  -- {[path]=true} or nil

  if search == "" and not match_filter then
    -- Copy array for sorting (don't modify original)
    result = {}
    for i, af in ipairs(CLB.audio_files) do
      result[i] = af
    end
  else
    result = {}
    for _, af in ipairs(CLB.audio_files) do
      -- Match filter: show only paths linked to the selected EDL row
      if match_filter and not (af.path and match_filter[af.path]) then
        goto continue_audio
      end
      -- Text search
      if search ~= "" then
        local meta = af.metadata or {}
        local searchable = (af.filename or "") .. " " ..
          (af.folder or "") .. " " ..
          (meta.scene or "") .. " " ..
          (meta.take or "") .. " " ..
          (meta.tape or "") .. " " ..
          (meta.project or "") .. " " ..
          (meta.orig_filename or "")
        if not searchable:lower():find(search, 1, true) then
          goto continue_audio
        end
      end
      result[#result + 1] = af
      ::continue_audio::
    end
  end

  -- Sort if sort column is set
  if CLB.audio_sort_col and CLB.audio_sort_col >= 1 and CLB.audio_sort_col <= AUDIO_COL_COUNT then
    local col = CLB.audio_sort_col
    local asc = CLB.audio_sort_asc
    table.sort(result, function(a, b)
      local va = get_audio_col_value(a, col)
      local vb = get_audio_col_value(b, col)
      -- Handle numbers
      if type(va) == "number" and type(vb) == "number" then
        if asc then return va < vb else return va > vb end
      end
      -- Handle strings (natural sort: A1, A2, A10 instead of A1, A10, A2)
      va = tostring(va)
      vb = tostring(vb)
      if asc then return _natural_sort_cmp(va, vb) else return _natural_sort_cmp(vb, va) end
    end)
  end

  CLB.audio_cached = result
  return CLB.audio_cached
end

---------------------------------------------------------------------------
-- Column widths
---------------------------------------------------------------------------
local COL_WIDTH = {}
for k, v in pairs(DEFAULT_COL_WIDTH) do
  COL_WIDTH[k] = v
end

-- Namespaced under one table (rather than ~9 separate top-level locals) to
-- stay under Lua's 200-local-per-chunk limit for this already-large script.
-- Declared here (ahead of its first use in save_prefs/load_prefs below) so
-- both can read/write CMP.GD_* fields; all CMP.foo() functions are defined
-- further down, under "Old-vs-New Compare (reconform)".
local CMP = {}

---------------------------------------------------------------------------
-- Preferences
---------------------------------------------------------------------------
local function save_prefs()
  reaper.SetExtState(EXT_NS, "font_scale", tostring(FONT_SCALE or 1.0), true)
  reaper.SetExtState(EXT_NS, "fps", tostring(CLB.fps or 25), true)
  reaper.SetExtState(EXT_NS, "is_drop", CLB.is_drop and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "track_name_format", CLB.track_name_format or "${format} - ${track}", true)
  reaper.SetExtState(EXT_NS, "ref_media_folder", CLB.ref_media_folder or "", true)
  reaper.SetExtState(EXT_NS, "ref_media_name_format", CLB.ref_media_name_format or "!CLB_Mute_${timestamp}", true)
  reaper.SetExtState(EXT_NS, "ref_media_scope", CLB.ref_media_scope or "visible", true)
  reaper.SetExtState(EXT_NS, "ref_load_auto_match", CLB.ref_load_auto_match and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "follow_reaper_sel", CLB.follow_reaper_sel and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "ref_load_merge_mode", CLB.ref_load_merge_mode or "ask", true)
  reaper.SetExtState(EXT_NS, "last_dir", CLB.last_dir or "", true)
  reaper.SetExtState(EXT_NS, "last_audio_dir", CLB.last_audio_dir or "", true)
  reaper.SetExtState(EXT_NS, "audio_recursive", CLB.audio_recursive and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "split_ratio", tostring(CLB.split_ratio or 0.5), true)
  reaper.SetExtState(EXT_NS, "console_output", CONSOLE.enabled and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "debug_mode", DEBUG and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "allow_docking", ALLOW_DOCKING and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "otio_python", OTIO.python or "python3", true)

  -- EDL column order (comma-separated)
  local order_str = table.concat(EDL_COL_ORDER, ",")
  reaper.SetExtState(EXT_NS, "edl_col_order", order_str, true)

  -- EDL column visibility (comma-separated 0/1)
  local vis_parts = {}
  for i = 1, COL_COUNT do
    vis_parts[i] = EDL_COL_VISIBILITY[i] and "1" or "0"
  end
  reaper.SetExtState(EXT_NS, "edl_col_visibility", table.concat(vis_parts, ","), true)

  -- Audio column visibility (comma-separated 0/1)
  local audio_vis_parts = {}
  for i = 1, AUDIO_COL_COUNT do
    audio_vis_parts[i] = AUDIO_COL_VISIBILITY[i] and "1" or "0"
  end
  reaper.SetExtState(EXT_NS, "audio_col_visibility", table.concat(audio_vis_parts, ","), true)

  reaper.SetExtState(EXT_NS, "show_timeline", CLB.show_timeline and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "tl_zoom", tostring(CLB.tl_zoom or 50.0), true)
  reaper.SetExtState(EXT_NS, "clip_name_format", CLB.clip_name_format or "", true)
  reaper.SetExtState(EXT_NS, "cjk_font_path", CLB.cjk_font_path or "", true)
  -- ExtState key names kept as the old "apply_mode_a/c/b" letters on
  -- purpose — purely internal plumbing, invisible to the user, and
  -- changing them would silently reset everyone's saved toggle state.
  reaper.SetExtState(EXT_NS, "apply_mode_a", CLB.apply_mode_matched and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "apply_mode_c", CLB.apply_mode_length and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "apply_mode_b", CLB.apply_mode_range and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "offset_old_enabled", CLB.offset_old_enabled and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "offset_old_hours", tostring(CLB.offset_old_hours or 10), true)
  reaper.SetExtState(EXT_NS, "offset_new_enabled", CLB.offset_new_enabled and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "offset_new_hours", tostring(CLB.offset_new_hours or 0), true)
  reaper.SetExtState(EXT_NS, "dme_recut_mode", CLB.dme_recut_mode or "copy", true)
  reaper.SetExtState(EXT_NS, "dme_recut_markers", CLB.dme_recut_markers and "1" or "0", true)
  -- "Calibrate TC (Anchor)" state is per-source (CLB.edl_sources[i].
  -- tc_calib_*), saved/restored as part of each source's own "S|" line in
  -- the .clb project format (see save_clb_project / load_clb_project) —
  -- not a global ExtState pref here, since it's tied to specific loaded
  -- files, not a persistent app-wide setting.

  -- Recut Group Details column visibility (comma-separated 0/1)
  local gd_vis_parts = {}
  for i = 1, CMP.GD_COL_COUNT do
    gd_vis_parts[i] = CMP.GD_COL_VISIBILITY[i] and "1" or "0"
  end
  reaper.SetExtState(EXT_NS, "cmp_gd_col_visibility", table.concat(gd_vis_parts, ","), true)
end

local function load_prefs()
  local function get(key, default)
    if reaper.HasExtState(EXT_NS, key) then
      return reaper.GetExtState(EXT_NS, key)
    end
    return default
  end

  FONT_SCALE = tonumber(get("font_scale", "1.0")) or 1.0
  CLB.fps = tonumber(get("fps", "24")) or 24
  CLB.is_drop = get("is_drop", "0") == "1"
  CLB.track_name_format = get("track_name_format", "${format} - ${track}")
  CLB.ref_media_folder = get("ref_media_folder", "")
  CLB.ref_media_name_format = get("ref_media_name_format", "!CLB_Mute_${timestamp}")
  -- Migrate a stale pre-redesign template: the old one-file-per-(reel,track)
  -- design used ${reel}/${track} tokens, which generate_reference_media's
  -- single-shared-file design no longer provides (only ${timestamp}) — a
  -- leftover old-style value would silently expand to an empty/"_" filename.
  if CLB.ref_media_name_format:find("%${reel}") or CLB.ref_media_name_format:find("%${track}")
     or not CLB.ref_media_name_format:find("%${timestamp}") then
    CLB.ref_media_name_format = "!CLB_Mute_${timestamp}"
  end
  CLB.ref_media_scope = get("ref_media_scope", "visible")
  if CLB.ref_media_scope ~= "visible" and CLB.ref_media_scope ~= "selected" then
    CLB.ref_media_scope = "visible"
  end
  CLB.ref_load_auto_match = get("ref_load_auto_match", "0") == "1"
  CLB.follow_reaper_sel = get("follow_reaper_sel", "0") == "1"
  CLB.ref_load_merge_mode = get("ref_load_merge_mode", "ask")
  if CLB.ref_load_merge_mode ~= "ask" and CLB.ref_load_merge_mode ~= "replace" and CLB.ref_load_merge_mode ~= "append" then
    CLB.ref_load_merge_mode = "ask"
  end
  CLB.last_dir = get("last_dir", "")
  CLB.last_audio_dir = get("last_audio_dir", "")
  CLB.audio_recursive = get("audio_recursive", "1") == "1"
  CLB.split_ratio = tonumber(get("split_ratio", "0.5")) or 0.5
  CONSOLE.enabled = get("console_output", "0") == "1"
  DEBUG = get("debug_mode", "0") == "1"
  ALLOW_DOCKING = get("allow_docking", "0") == "1"
  OTIO.python = get("otio_python", "")  -- set after load_prefs() is called
  CLB.show_timeline = get("show_timeline", "0") == "1"
  CLB.tl_zoom = tonumber(get("tl_zoom", "50.0")) or 50.0
  CLB.clip_name_format = get("clip_name_format", "")
  CLB.cjk_font_path = get("cjk_font_path", "")
  CLB.apply_mode_matched = get("apply_mode_a", "1") == "1"
  CLB.apply_mode_length  = get("apply_mode_c", "1") == "1"
  CLB.apply_mode_range   = get("apply_mode_b", "1") == "1"
  CLB.offset_old_enabled = get("offset_old_enabled", "0") == "1"
  CLB.offset_old_hours   = tonumber(get("offset_old_hours", "10")) or 10
  CLB.offset_new_enabled = get("offset_new_enabled", "0") == "1"
  CLB.offset_new_hours   = tonumber(get("offset_new_hours", "0")) or 0
  CLB.dme_recut_mode     = get("dme_recut_mode", "copy")
  CLB.dme_recut_markers  = get("dme_recut_markers", "1") == "1"

  -- EDL column order
  local order_str = get("edl_col_order", "")
  if order_str ~= "" then
    local new_order = {}
    for num_str in order_str:gmatch("(%d+)") do
      local num = tonumber(num_str)
      if num and num >= 1 and num <= COL_COUNT then
        table.insert(new_order, num)
      end
    end
    -- Append any newly-added columns not present in saved order (migration)
    local in_order = {}
    for _, c in ipairs(new_order) do in_order[c] = true end
    for i = 1, COL_COUNT do
      if not in_order[i] then table.insert(new_order, i) end
    end
    if #new_order == COL_COUNT then
      EDL_COL_ORDER = new_order
    end
  end

  -- EDL column visibility
  local vis_str = get("edl_col_visibility", "")
  if vis_str ~= "" then
    local idx = 0
    for val in vis_str:gmatch("([01])") do
      idx = idx + 1
      if idx <= COL_COUNT then
        EDL_COL_VISIBILITY[idx] = (val == "1")
      end
    end
  end

  -- Audio column visibility
  local audio_vis_str = get("audio_col_visibility", "")
  if audio_vis_str ~= "" then
    local idx = 0
    for val in audio_vis_str:gmatch("([01])") do
      idx = idx + 1
      if idx <= AUDIO_COL_COUNT then
        AUDIO_COL_VISIBILITY[idx] = (val == "1")
      end
    end
  end

  -- Recut Group Details column visibility
  local gd_vis_str = get("cmp_gd_col_visibility", "")
  if gd_vis_str ~= "" then
    local idx = 0
    for val in gd_vis_str:gmatch("([01])") do
      idx = idx + 1
      if idx <= CMP.GD_COL_COUNT then
        CMP.GD_COL_VISIBILITY[idx] = (val == "1")
      end
    end
  end

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
  SEL.version = SEL.version + 1
end

local function sel_add(guid, col_id)
  SEL.cells[sel_key(guid, col_id)] = true
  SEL.version = SEL.version + 1
end

local function sel_remove(guid, col_id)
  SEL.cells[sel_key(guid, col_id)] = nil
  SEL.version = SEL.version + 1
end

local function sel_has(guid, col_id)
  return SEL.cells[sel_key(guid, col_id)] == true
end

-- Returns true if any column of this row is selected
local function sel_has_row(guid)
  local prefix = guid .. ":"
  for k in pairs(SEL.cells) do
    if k:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function sel_toggle(guid, col_id)
  local k = sel_key(guid, col_id)
  if SEL.cells[k] then
    SEL.cells[k] = nil
  else
    SEL.cells[k] = true
  end
  SEL.version = SEL.version + 1
end

local function sel_set_single(guid, col_id)
  sel_clear()
  sel_add(guid, col_id)
  SEL.anchor = { guid = guid, col = col_id }
end

-- Rectangle selection (Shift+Click)
-- Walks the VISIBLE (filtered/searched) rows — via CLB.get_view_rows,
-- assigned once get_view_rows itself is defined further down — not raw
-- ROWS: ROWS is sorted in place but still holds filtered-out rows, which
-- a Shift range used to silently include (then e.g. Delete tagged rows
-- you couldn't see). Keeps SEL.anchor (sel_clear wipes it), so repeated
-- Shift+click / Shift+arrow keep extending from the same anchor.
local function sel_rect(guid_from, col_from, guid_to, col_to)
  local rows = CLB.get_view_rows and CLB.get_view_rows() or ROWS
  -- Find row indices
  local idx_from, idx_to
  for i, row in ipairs(rows) do
    if row.__guid == guid_from then idx_from = i end
    if row.__guid == guid_to then idx_to = i end
  end
  if not idx_from or not idx_to then return end

  local r1, r2 = math.min(idx_from, idx_to), math.max(idx_from, idx_to)
  local c1, c2 = math.min(col_from, col_to), math.max(col_from, col_to)

  local anchor = SEL.anchor
  sel_clear()
  SEL.anchor = anchor
  for i = r1, r2 do
    for c = c1, c2 do
      sel_add(rows[i].__guid, c)
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
      group = row.group,
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
        ROWS[i].group or "", ROWS[i].level or "",
        ROWS[i].scene or "", ROWS[i].take or "",
        ROWS[i].src_tc_in or "", ROWS[i].src_tc_out or "",
        ROWS[i].rec_tc_in or "", ROWS[i].rec_tc_out or "",
        ROWS[i].duration or "",
      }, " "):lower()
    end
  end
end

local function do_undo()
  if UNDO_POS <= 1 then return end
  UNDO_POS = UNDO_POS - 1
  undo_restore(UNDO_STACK[UNDO_POS])
  _rebuild_group_filters()
  CLB.cached_rows = nil
  console_msg("Undo")
end

local function do_redo()
  if UNDO_POS >= #UNDO_STACK then return end
  UNDO_POS = UNDO_POS + 1
  undo_restore(UNDO_STACK[UNDO_POS])
  _rebuild_group_filters()
  CLB.cached_rows = nil
  console_msg("Redo")
end

---------------------------------------------------------------------------
-- Row data helpers
---------------------------------------------------------------------------

--- Accept a timecode typed either as "HH:MM:SS:FF" or as 8 bare digits
--- "HHMMSSFF" (no colons — e.g. "00595800") and return the colon form.
--- Anything else is returned unchanged (untouched, so EDL.is_valid_tc's
--- own error message still applies to a genuinely malformed value). Shared
--- by the main Search box and "Calibrate to Target TC" — both need "type
--- 8 digits, no colons required" the same way.
function CLB.normalize_tc_input(s)
  s = (s or ""):match("^%s*(.-)%s*$")
  if s:match("^%d%d%d%d%d%d%d%d$") then
    return s:sub(1,2) .. ":" .. s:sub(3,4) .. ":" .. s:sub(5,6) .. ":" .. s:sub(7,8)
  end
  return s
end

--- Rec TC (seconds), with the active "Calibrate TC (Anchor)" delta applied
--- if enabled for `row`'s own source. Use this — never a bare
--- EDL.tc_to_seconds(row.rec_tc_in) — everywhere a Rec TC becomes a real
--- Reaper timeline position (Generate Items, Conform Matched Items, Create
--- Scene Cut Track, click-to-jump). Not used for purely relative
--- comparisons between the list's own rows (Consolidate, Scene/Take
--- inference, mini-timeline panel) — a uniform shift cancels out there
--- anyway, so those are left reading raw TC.
---
--- Calibration is per SOURCE, not global: audio post commonly loads
--- several reels/episodes at once, each authored by the editor starting at
--- 0 but placed at its own hour slot on the real session timeline — a
--- single delta can't correct all of them, so each entry in
--- CLB.edl_sources carries its own tc_calib_enabled/tc_calib_delta_sec,
--- looked up here via row.__source_idx.
--- @param tc_str string   A Rec TC string ("HH:MM:SS:FF").
--- @param row table|nil   The row this TC belongs to, for source lookup.
---                        Pass nil only when there's genuinely no row
---                        (falls back to no calibration).
function CLB.rec_tc_seconds(tc_str, row)
  local sec = EDL.tc_to_seconds(tc_str or "00:00:00:00", CLB.fps, CLB.is_drop)
  local src = row and CLB.edl_sources[row.__source_idx or 0]
  if src and src.tc_calib_enabled then
    sec = sec + (src.tc_calib_delta_sec or 0)
  end
  return sec
end

--- Calibrated Rec TC as a display string — what get_cell_text shows for
--- COL.REC_IN/REC_OUT. Returns the raw string unchanged when `row`'s
--- source has no calibration enabled, so it's always safe to call.
function CLB.calibrated_rec_tc_string(tc_str, row)
  local src = row and CLB.edl_sources[row.__source_idx or 0]
  if not (src and src.tc_calib_enabled) then return tc_str or "" end
  return EDL.seconds_to_tc(CLB.rec_tc_seconds(tc_str, row), CLB.fps, CLB.is_drop)
end

--- Src TC (seconds), with the "Old" axis of "Calibrate TC (Anchor)"
--- applied if enabled for `row`'s own source. Only meaningful in DME
--- Recut mode, where Src TC is repurposed as V1's real Reaper timeline
--- position rather than a position inside an audio source file (see
--- CLB.dme_recut) — everywhere else in CLB, Src TC keeps its usual
--- file-relative meaning and this is simply never called for it.
function CLB.src_tc_seconds(tc_str, row)
  local sec = EDL.tc_to_seconds(tc_str or "00:00:00:00", CLB.fps, CLB.is_drop)
  local src = row and CLB.edl_sources[row.__source_idx or 0]
  if src and src.src_calib_enabled then
    sec = sec + (src.src_calib_delta_sec or 0)
  end
  return sec
end

--- Calibrated Src TC as a display string — the "Old" axis counterpart of
--- CLB.calibrated_rec_tc_string, shown for COL.SRC_IN/SRC_OUT only when
--- DME Recut's Src calibration is enabled for `row`'s source (otherwise
--- identical to the raw string, so always safe to call).
function CLB.calibrated_src_tc_string(tc_str, row)
  local src = row and CLB.edl_sources[row.__source_idx or 0]
  if not (src and src.src_calib_enabled) then return tc_str or "" end
  return EDL.seconds_to_tc(CLB.src_tc_seconds(tc_str, row), CLB.fps, CLB.is_drop)
end

-- Get cell text for display
local function get_cell_text(row, col_id)
  if not row then return "" end
  if col_id == COL.EVENT        then return row.event_num or "" end
  if col_id == COL.REEL         then return row.reel or "" end
  if col_id == COL.TRACK        then return row.track or "" end
  if col_id == COL.EDIT_TYPE    then return row.edit_type or "" end
  if col_id == COL.LEVEL        then return row.level or "" end
  if col_id == COL.DISS_LEN     then
    return row.dissolve_len and tostring(row.dissolve_len) or ""
  end
  if col_id == COL.SRC_IN       then return CLB.calibrated_src_tc_string(row.src_tc_in, row) end
  if col_id == COL.SRC_OUT      then return CLB.calibrated_src_tc_string(row.src_tc_out, row) end
  if col_id == COL.REC_IN       then return CLB.calibrated_rec_tc_string(row.rec_tc_in, row) end
  if col_id == COL.REC_OUT      then return CLB.calibrated_rec_tc_string(row.rec_tc_out, row) end
  if col_id == COL.DURATION     then return row.duration or "" end
  if col_id == COL.CLIP_NAME    then return row.clip_name or "" end
  if col_id == COL.SRC_FILE     then return row.source_file or "" end
  if col_id == COL.NOTES        then return row.notes or "" end
  if col_id == COL.MATCH_STATUS then return row.match_status or "" end
  if col_id == COL.MATCHED_PATH then
    -- Show just filename for display, full path in tooltip. The Fallback
    -- "[Scene+Take] "/"[Tape+TC] " prefix lives here (not just at render
    -- time) so it's also part of what get_sort_value below sorts by —
    -- otherwise sorting this column couldn't tell the two fallback kinds
    -- apart (they were only distinguished by a draw-time-only text mutation).
    local text = ""
    if row.matched_path and row.matched_path ~= "" then
      text = row.matched_path:match("([^/\\]+)$") or row.matched_path
    end
    if row.match_status == "Fallback" then
      text = (row.__fallback_kind == "scene_take" and "[Scene+Take] " or "[Tape+TC] ") .. text
    end
    return text
  end
  if col_id == COL.GROUP        then return row.group or "" end
  if col_id == COL.SCENE        then return row.scene or "" end
  if col_id == COL.TAKE         then return row.take  or "" end
  if col_id == COL.SPEED        then
    -- EDL M2 line (aux source timecode) — see hsuanice_EDL Parser.lua's
    -- own parsing comment. Shown exactly as the EDL itself expresses it
    -- (raw fps-style rate), not translated into "2x"/"REV" wording — this
    -- is a from-the-EDL fact for human review, not a derived judgement.
    if not row.aux_rate then return "" end
    return string.format("%.1f", row.aux_rate)
  end
  return ""
end

--- Raw (uncalibrated) cell text — used only for entering/comparing an
--- inline edit. REC_IN/REC_OUT must always be edited against their true
--- stored value, never get_cell_text's "Calibrate TC (Anchor)" display
--- value, or every edit made while calibration is on would silently bake
--- the delta into the raw data (typing what you see, which is already
--- +delta, as the new "raw" value).
function CLB.get_cell_edit_text(row, col_id)
  if col_id == COL.REC_IN  then return row.rec_tc_in  or "" end
  if col_id == COL.REC_OUT then return row.rec_tc_out or "" end
  if col_id == COL.SRC_IN  then return row.src_tc_in  or "" end
  if col_id == COL.SRC_OUT then return row.src_tc_out or "" end
  return get_cell_text(row, col_id)
end

-- Set cell value (with undo)
local function set_cell_value(row, col_id, value)
  if not row or not EDITABLE_COLS[col_id] then return false end

  if col_id == COL.REEL      then row.reel = value
  elseif col_id == COL.TRACK     then row.track = value
  elseif col_id == COL.EDIT_TYPE then row.edit_type = value
  elseif col_id == COL.LEVEL     then row.level = value
  elseif col_id == COL.DISS_LEN  then row.dissolve_len = tonumber(value)
  elseif col_id == COL.SRC_IN    then row.src_tc_in = value
  elseif col_id == COL.SRC_OUT   then row.src_tc_out = value
  elseif col_id == COL.REC_IN    then row.rec_tc_in = value
  elseif col_id == COL.REC_OUT   then row.rec_tc_out = value
  elseif col_id == COL.CLIP_NAME then row.clip_name = value
  elseif col_id == COL.SRC_FILE  then row.source_file = value
  elseif col_id == COL.NOTES     then row.notes = value
  elseif col_id == COL.GROUP     then row.group = value
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
    row.group or "", row.level or "",
    row.scene or "", row.take or "",
    row.src_tc_in or "", row.src_tc_out or "",
    row.rec_tc_in or "", row.rec_tc_out or "",
    row.duration or "",
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

  CLB.cached_rows = nil
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
  if CLB.cached_rows then
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

  -- Build hidden reel set
  local hidden_reels = nil
  for _, rf in ipairs(CLB.reel_filters) do
    if not rf.visible then
      hidden_reels = hidden_reels or {}
      hidden_reels[rf.name] = true
    end
  end

  -- Build hidden group set
  local hidden_groups = nil
  for _, gf in ipairs(CLB.group_filters) do
    if not gf.visible then
      hidden_groups = hidden_groups or {}
      hidden_groups[gf.name] = true
    end
  end

  local search = CLB.search_text:lower()
  -- 8 bare digits ("01102203") are almost certainly a timecode typed
  -- without the colons — also check the "HH:MM:SS:FF" form (via
  -- CLB.normalize_tc_input) so it matches Src/Rec TC In/Out (stored with
  -- colons in __search_text) the same as typing "01:10:22:03" directly would.
  local search_tc = nil
  local normalized_search = CLB.normalize_tc_input(search)
  if normalized_search ~= search then
    search_tc = normalized_search
  end
  local need_filter = search ~= "" or hidden_src_idx or hidden_tracks or hidden_reels or hidden_groups

  if not need_filter then
    CLB.cached_rows = ROWS
  else
    local filtered = {}
    for _, row in ipairs(ROWS) do
      -- Source visibility filter
      if hidden_src_idx and hidden_src_idx[row.__source_idx] then
        goto skip
      end
      -- Group visibility filter (check before track for hierarchy)
      if hidden_groups and hidden_groups[row.group or ""] then
        goto skip
      end
      -- Track visibility filter
      if hidden_tracks and hidden_tracks[row.track or ""] then
        goto skip
      end
      -- Reel visibility filter
      if hidden_reels and hidden_reels[row.reel or ""] then
        goto skip
      end
      -- Search filter
      if search ~= "" then
        local hit = row.__search_text and (
          row.__search_text:find(search, 1, true)
          or (search_tc and row.__search_text:find(search_tc, 1, true))
        )
        if not hit then
          goto skip
        end
      end
      filtered[#filtered + 1] = row
      ::skip::
    end
    CLB.cached_rows = filtered
  end

  return CLB.cached_rows
end
CLB.get_view_rows = get_view_rows -- for code above this point (sel_rect)

---------------------------------------------------------------------------
-- File loading
---------------------------------------------------------------------------
-- GUID counter for unique row IDs across multiple imports
local _guid_counter = 0

--- Rename track with source suffix for multi-EDL import.
--- Examples: A → A1, V → V1, A2 → A1-2, AA → AA1
--- @param track string    Original track name
--- @param suffix number   Source index (1, 2, 3...)
--- @return string         Renamed track
local function _rename_track_with_suffix(track, suffix)
  if not track or track == "" then return track end

  -- Extract base letters and optional existing number
  local base, num = track:match("^([A-Za-z]+)(%d*)$")
  if not base then
    -- Non-standard track name (contains special chars), just append suffix
    return track .. "." .. suffix
  end

  if num and num ~= "" then
    -- Already has a number (e.g., A2, A12, V2)
    -- Rename to: base + suffix + "-" + original_num
    -- e.g., A2 from source 1 → A1-2
    return base:upper() .. suffix .. "-" .. num
  else
    -- Simple track name (e.g., A, V, AA)
    return base:upper() .. suffix
  end
end

--- Apply track suffixes to all rows based on source count.
--- Called after appending rows to rename tracks from all sources.
local function _apply_track_suffixes()
  local source_count = #CLB.edl_sources
  if source_count <= 1 then
    -- Single source: restore original track names (no suffix needed)
    for _, row in ipairs(ROWS) do
      if row.__orig_track and not row.__reaper_item then
        row.track = row.__orig_track
      end
    end
    return
  end

  -- Multiple sources: apply suffix based on source index — EXCEPT rows
  -- from "Load From Reaper" (row.__reaper_item set). This suffixing
  -- exists to disambiguate an EDL's own abstract track label (e.g. "A1"
  -- meaning "audio track 1" in the file) when the SAME label appears in
  -- several separately-loaded EDL files for one reel. A Load-From-Reaper
  -- row's track is already the real, live Reaper track name — not an
  -- abstract label needing disambiguation — so suffixing it is actively
  -- wrong (confirmed by a real user report with a screenshot: real
  -- track names like "A1" were coming out mangled with a confusing "- N"
  -- source-index suffix appended, every time any other source besides
  -- that Reaper load pushed CLB.edl_sources above 1).
  for _, row in ipairs(ROWS) do
    if not row.__reaper_item then
      local orig = row.__orig_track or row.track
      local src_idx = row.__source_idx or 1
      row.track = _rename_track_with_suffix(orig, src_idx)
    end
  end
end

local function _make_rows_from_events(events, fps, is_drop, source_idx)
  local new_rows = {}
  for _, evt in ipairs(events) do
    _guid_counter = _guid_counter + 1
    local orig_track = evt.track or ""
    -- Normalize repeated-letter track names: AA→A, VV→V, etc.
    if orig_track:len() > 1 and orig_track:match("^(%a)%1+$") then
      orig_track = orig_track:sub(1, 1)
    end
    local row = {
      __event_idx = _guid_counter,
      __guid = string.format("clb_%06d", _guid_counter),
      __source_idx = source_idx or 0,
      __orig_track = orig_track,  -- Store original track for multi-EDL suffix

      event_num = evt.event_num or string.format("%03d", _guid_counter),
      reel = evt.reel or "",
      track = orig_track,
      edit_type = evt.edit_type or "C",
      dissolve_len = evt.dissolve_len,
      src_tc_in = evt.src_tc_in or "00:00:00:00",
      src_tc_out = evt.src_tc_out or "00:00:00:00",
      rec_tc_in = evt.rec_tc_in or "00:00:00:00",
      rec_tc_out = evt.rec_tc_out or "00:00:00:00",
      -- Prefer TO CLIP NAME (incoming clip) unless it is "BL" (black/silence),
      -- in which case fall back to FROM CLIP NAME (the real outgoing clip).
      -- This covers: fade-in from BL → show TO; fade-out to BL → show FROM;
      -- real crossfade (neither BL) → show TO (the incoming material).
      clip_name = (function()
        local from_n = evt.clip_name or ""
        local to_n   = evt.to_clip_name or ""
        if to_n ~= "" and to_n ~= "BL" then return to_n end
        if from_n ~= "" and from_n ~= "BL" then return from_n end
        return to_n ~= "" and to_n or from_n  -- both BL or both empty
      end)(),
      source_file = evt.source_file or "",
      notes = "",    -- auto-populated below from extra EDL comments
      level = "",    -- auto-populated below from AUDIO/VIDEO LEVEL comments
      group = "",
      scene = evt.scene or "",
      take  = evt.take  or "",
      audio_levels = evt.audio_levels or {},  -- [{ type, tc, db, reel, src_track }]
      -- EDL M2 line (aux source timecode): signals this clip was shot at
      -- a different native frame rate (speed retime) or reverse playback
      -- — see hsuanice_EDL Parser.lua's own M2-parsing comment. Surfaced
      -- via the "Speed" column and noted on generated ref-media items;
      -- not otherwise acted on (see CLB.generate_reference_media).
      aux_rate = evt.aux_rate,

      -- Only ever set by CLB.load_from_reaper_selection — a direct link
      -- back to the real Reaper item this row was read from, so Clip
      -- Name can jump/select it (see the main table's click handler) and
      -- Conform can add a take there instead of creating a new item.
      -- Lost on .clb save/reload (a raw item pointer can't be
      -- serialized) — same already-accepted limitation as
      -- row.__match_candidates.
      __reaper_item = evt.__reaper_item,

      duration = evt.duration_tc or EDL.seconds_to_tc(
        EDL.tc_to_seconds(evt.rec_tc_out or "00:00:00:00", fps, is_drop)
        - EDL.tc_to_seconds(evt.rec_tc_in or "00:00:00:00", fps, is_drop),
        fps, is_drop),
    }

    -- Auto-populate notes from extra EDL comment lines.
    -- SOURCE FILE has its own column so it is excluded.
    -- FROM CLIP NAME and TO CLIP NAME are included (they clarify transition edits like BL reels).
    local extra = {}
    for _, cmt in ipairs(evt.comments or {}) do
      if not cmt:match("^SOURCE FILE:") then
        extra[#extra + 1] = cmt
      end
    end
    if #extra > 0 then
      row.notes = table.concat(extra, " | ")
    end

    -- evt.notes: a direct, already-formed notes string — only set by
    -- CLB.load_from_reaper_selection (the real item's own P_NOTES text),
    -- which has no "EDL comment lines" concept at all. User's own
    -- report: a Load-From-Reaper row's Notes column was blank even
    -- though the item it came from had real Notes. Appended (not
    -- replacing evt.comments-derived text above) since the two are
    -- mutually exclusive in practice — no loader sets both. Multi-line
    -- item Notes (CLB's own "Reel:\nScene:\n..." convention) collapse to
    -- the same " | "-joined single line as EDL comments above, for
    -- consistent display in the Notes column/cell.
    if evt.notes and evt.notes ~= "" then
      local one_line = evt.notes:gsub("[\r\n]+", " | ")
      row.notes = (row.notes ~= "" and (row.notes .. " | ") or "") .. one_line
    end

    -- Auto-populate level from AUDIO/VIDEO LEVEL comments
    local db_parts = {}
    for _, lv in ipairs(row.audio_levels) do
      if lv.db and lv.db ~= "" then
        db_parts[#db_parts + 1] = lv.db
      end
    end
    if #db_parts > 0 then
      row.level = table.concat(db_parts, " | ")
    end

    row.__search_text = table.concat({
      row.event_num, row.reel, row.track,
      row.clip_name, row.source_file, row.notes,
      row.group, row.level,
      row.scene or "", row.take or "",
      row.src_tc_in, row.src_tc_out,
      row.rec_tc_in, row.rec_tc_out,
      row.duration,
    }, " "):lower()

    new_rows[#new_rows + 1] = row
  end
  return new_rows
end

--- Parent folder of a path, trailing slash included ("" if none).
function CLB.folder_of(filepath)
  return filepath:match("(.*[/\\])") or ""
end

--- Last path segment of a folder path (its own display name).
function CLB.folder_display_name(folder)
  local trimmed = folder:gsub("[/\\]+$", "")
  return trimmed:match("([^/\\]+)$") or trimmed
end

--- Register a source and return its index. .edl files sitting in the same
--- folder are folded into ONE source instead of one-per-file: CMX3600's
--- 4-audio-track-per-file limit means a single reel's full channel set is
--- routinely exported as several .edl files (A1-2/A3-4/.../Video) placed
--- together in one reel folder — see the real case that prompted this,
--- POINT_DIR_v8_R1_*.edl (7 files) sitting in a "R01" folder. Those are
--- one reel, not several, and must share one "Calibrate TC (Anchor)"
--- correction (Set Anchor on any one of them then calibrates the whole
--- reel). XML/AAF exports are always one file per reel already, so they
--- keep the previous one-file-one-source behavior untouched.
local function _register_source(filepath, event_count)
  local ext = (filepath:match("%.([^./\\]+)$") or ""):lower()

  if ext == "edl" then
    local folder = CLB.folder_of(filepath)
    for idx, src in ipairs(CLB.edl_sources) do
      if src.__folder and src.__folder == folder then
        src.event_count  = (src.event_count or 0) + event_count
        src.__file_count = (src.__file_count or 1) + 1
        src.name = string.format("%s (%d files)", CLB.folder_display_name(folder), src.__file_count)
        return idx
      end
    end
  end

  local folder = (ext == "edl") and CLB.folder_of(filepath) or nil
  local idx = #CLB.edl_sources + 1
  CLB.edl_sources[idx] = {
    name = folder and CLB.folder_display_name(folder) or (filepath:match("([^/\\]+)$") or filepath),
    path = filepath,
    event_count = event_count,
    visible = true,
    -- Per-source "Calibrate TC (Anchor)" state — see CLB.calibrate_tc_via_anchor.
    -- Two independent axes: Rec TC ("New" — V2/target position, used by
    -- Generate Items/Conform/Scene Cuts/table display/click-to-jump) and
    -- Src TC ("Old" — only meaningful in DME Recut mode, where Src TC is
    -- repurposed as V1's real Reaper timeline position rather than a
    -- position inside an audio source file; see CLB.dme_recut).
    tc_calib_enabled   = false,
    tc_calib_delta_sec = 0,
    tc_calib_note      = "",
    src_calib_enabled   = false,
    src_calib_delta_sec = 0,
    src_calib_note      = "",
    -- Folder-grouping bookkeeping (.edl only) — not saved to .clb directly;
    -- re-derived from `path` on project load (see load_clb_project).
    __folder     = folder,
    __file_count = folder and 1 or nil,
  }
  return idx
end

--- Natural sort comparison (handles numbers correctly: A1, A2, A10 instead of A1, A10, A2)
function _natural_sort_cmp(a, b)
  -- Split strings into parts of letters and numbers
  local function split_parts(s)
    local parts = {}
    local i = 1
    while i <= #s do
      local num_start, num_end = s:find("^%d+", i)
      if num_start then
        table.insert(parts, { num = true, val = tonumber(s:sub(num_start, num_end)) })
        i = num_end + 1
      else
        local char = s:sub(i, i)
        table.insert(parts, { num = false, val = char:lower() })
        i = i + 1
      end
    end
    return parts
  end

  local pa, pb = split_parts(a or ""), split_parts(b or "")
  local len = math.min(#pa, #pb)

  for i = 1, len do
    local ca, cb = pa[i], pb[i]
    if ca.num ~= cb.num then
      -- Numbers come before letters
      return ca.num
    elseif ca.val ~= cb.val then
      return ca.val < cb.val
    end
  end

  return #pa < #pb
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
  table.sort(track_order, _natural_sort_cmp)

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

--- Rebuild reel filter list from current ROWS.
_rebuild_reel_filters = function()
  local reel_counts = {}
  local reel_order = {}
  for _, row in ipairs(ROWS) do
    local r = row.reel or ""
    if not reel_counts[r] then
      reel_counts[r] = 0
      reel_order[#reel_order + 1] = r
    end
    reel_counts[r] = reel_counts[r] + 1
  end
  table.sort(reel_order, _natural_sort_cmp)

  -- Preserve existing visibility
  local old_vis = {}
  for _, rf in ipairs(CLB.reel_filters) do
    old_vis[rf.name] = rf.visible
  end

  CLB.reel_filters = {}
  CLB.reel_sel = {}          -- indices have shifted; clear selection
  CLB.reel_sel_anchor = nil
  for _, name in ipairs(reel_order) do
    CLB.reel_filters[#CLB.reel_filters + 1] = {
      name = name,
      count = reel_counts[name],
      visible = old_vis[name] == nil or old_vis[name],
    }
  end
end

-- Starting set of selectable groups on a fresh load — lets the user assign
-- rows to any of these right away (right-click a group → Assign Selected
-- Rows Here) without first having to "+" add each one by hand. Users can
-- still add/rename/delete freely; this only seeds the initial list.
local DEFAULT_GROUP_NAMES = { "Video", "Audio", "Dialog", "Music", "Effects", "Location", "ADR", "Delete" }

--- Determine group for a track name based on prefix (used for initial auto-assign only).
--- A* → Audio, V* → Video, NONE → NONE, others → Other
function _get_track_group(track_name)
  if not track_name or track_name == "" then return "Other" end
  local upper = track_name:upper()
  if upper == "NONE" then return "NONE" end
  local first_char = upper:sub(1, 1)
  if first_char == "A" then return "Audio"
  elseif first_char == "V" then return "Video"
  else return "Other"
  end
end

--- Rebuild group filter list from current ROWS (count-only, does NOT reassign row.group).
--- Preserves user-defined groups even if they have zero events.
local function _rebuild_group_filters()
  -- Count events per group and collect tracks
  local group_counts = {}   -- group_name → event_count
  local group_tracks = {}   -- group_name → { track_name = true, ... }

  for _, row in ipairs(ROWS) do
    local g = row.group or ""
    group_counts[g] = (group_counts[g] or 0) + 1
    group_tracks[g] = group_tracks[g] or {}
    group_tracks[g][row.track or ""] = true
  end

  -- Rebuild: preserve existing user-defined groups in order, then add discovered ones
  local new_filters = {}
  local seen = {}

  -- First: keep existing groups in their current order (even if count=0)
  for _, gf in ipairs(CLB.group_filters) do
    if not seen[gf.name] then
      seen[gf.name] = true
      local tracks = {}
      for track_name in pairs(group_tracks[gf.name] or {}) do
        tracks[#tracks + 1] = track_name
      end
      table.sort(tracks, _natural_sort_cmp)
      new_filters[#new_filters + 1] = {
        name = gf.name,
        count = group_counts[gf.name] or 0,
        visible = gf.visible,
        tracks = tracks,
      }
    end
  end

  -- Second: add any groups found in rows but not in user-defined list
  for g_name, count in pairs(group_counts) do
    if not seen[g_name] then
      seen[g_name] = true
      local tracks = {}
      for track_name in pairs(group_tracks[g_name] or {}) do
        tracks[#tracks + 1] = track_name
      end
      table.sort(tracks, _natural_sort_cmp)
      new_filters[#new_filters + 1] = {
        name = g_name,
        count = count,
        visible = (g_name ~= "Delete"),  -- see build_rows_from_parsed's own comment
        tracks = tracks,
      }
    end
  end

  CLB.group_filters = new_filters
end

--- Auto-assign groups to rows that have no group (on initial load only).
local function _auto_assign_groups()
  for _, row in ipairs(ROWS) do
    if not row.group or row.group == "" then
      row.group = _get_track_group(row.track)
    end
  end
  _rebuild_group_filters()
end

-- Replace all rows (fresh load)
local function build_rows_from_parsed(parsed, source_path)
  ROWS = {}
  _guid_counter = 0
  CLB.edl_sources = {}
  CLB.track_filters = {}
  CLB.reel_filters = {}
  CLB.group_filters = {}
  for _, name in ipairs(DEFAULT_GROUP_NAMES) do
    -- Delete defaults to hidden — it's a "things excluded from the cut"
    -- bucket (see the Delete-key handler), not a normal content group,
    -- so a freshly loaded list shouldn't show anything in it yet.
    CLB.group_filters[#CLB.group_filters + 1] =
      { name = name, count = 0, visible = (name ~= "Delete"), tracks = {} }
  end
  if not parsed or not parsed.events then return end

  CLB.fps = parsed.fps or 24
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
  _rebuild_reel_filters()
  _auto_assign_groups()
  CLB.cached_rows = nil

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
  _rebuild_reel_filters()
  _auto_assign_groups()
  CLB.cached_rows = nil

  console_msg(string.format("Appended %d events from %s (total: %d)",
    #new_rows, CLB.edl_sources[src_idx].name, #ROWS))
end

---------------------------------------------------------------------------
-- CLB Project Save / Load
---------------------------------------------------------------------------

--- Escape a value for pipe-delimited CLB format.
local function _clb_escape(s)
  s = tostring(s or "")
  s = s:gsub("\\", "\\\\")
  s = s:gsub("|", "\\|")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "")
  return s
end

--- Split a CLB line by unescaped '|', unescaping as we go.
local function _clb_split(line)
  local parts = {}
  local cur = {}
  local i = 1
  while i <= #line do
    local c = line:sub(i, i)
    if c == "\\" and i < #line then
      local nxt = line:sub(i + 1, i + 1)
      if     nxt == "|"  then cur[#cur+1] = "|";  i = i + 2
      elseif nxt == "n"  then cur[#cur+1] = "\n"; i = i + 2
      elseif nxt == "\\" then cur[#cur+1] = "\\"; i = i + 2
      else                    cur[#cur+1] = c;    i = i + 1
      end
    elseif c == "|" then
      parts[#parts+1] = table.concat(cur); cur = {}; i = i + 1
    else
      cur[#cur+1] = c; i = i + 1
    end
  end
  parts[#parts+1] = table.concat(cur)
  return parts
end

--- Save the current CLB session to a .clb project file.
--- @param silent  boolean  If true, suppress the confirmation MessageBox (for quick Save).
local function save_clb_project(filepath, silent)
  local f = io.open(filepath, "w")
  if not f then
    reaper.ShowMessageBox("Cannot write to:\n" .. filepath, SCRIPT_NAME, 0)
    return false
  end

  f:write("CLB_PROJECT_V1\n")

  -- Settings
  f:write(string.format("SOURCE_FORMAT|%s\n",
    _clb_escape(CLB.loaded_format or "CLB")))
  f:write(string.format("FPS|%s|%s\n",
    tostring(CLB.fps), CLB.is_drop and "1" or "0"))
  f:write(string.format("TRACK_FORMAT|%s\n",
    _clb_escape(CLB.track_name_format or "")))
  f:write(string.format("AUDIO_FOLDER|%s\n",
    _clb_escape(CLB.audio_folder or "")))
  f:write(string.format("AUDIO_RECURSIVE|%s\n",
    CLB.audio_recursive and "1" or "0"))

  -- Column layout
  f:write(string.format("EDL_COL_ORDER|%s\n", table.concat(EDL_COL_ORDER, ",")))
  local vis_parts = {}
  for i = 1, COL_COUNT do
    vis_parts[i] = EDL_COL_VISIBILITY[i] and "1" or "0"
  end
  f:write(string.format("EDL_COL_VISIBILITY|%s\n", table.concat(vis_parts, ",")))

  -- EDL sources (tc_calib_* = per-source "Calibrate TC (Anchor)" state,
  -- Rec/"New" axis; src_calib_* = the Src/"Old" axis, DME Recut only)
  f:write(string.format("SOURCES|%d\n", #CLB.edl_sources))
  for _, src in ipairs(CLB.edl_sources) do
    f:write(string.format("S|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s\n",
      _clb_escape(src.path or ""),
      _clb_escape(src.name or ""),
      src.event_count or 0,
      src.visible and "1" or "0",
      src.tc_calib_enabled and "1" or "0",
      tostring(src.tc_calib_delta_sec or 0),
      _clb_escape(src.tc_calib_note or ""),
      src.src_calib_enabled and "1" or "0",
      tostring(src.src_calib_delta_sec or 0),
      _clb_escape(src.src_calib_note or "")))
  end

  -- EDL rows (including match state and group assignments)
  -- Format: R|event_num|reel|track|edit_type|dissolve_len|
  --           src_tc_in|src_tc_out|rec_tc_in|rec_tc_out|
  --           clip_name|source_file|notes|
  --           match_status|matched_path|group|orig_track|source_idx|level|
  --           scene|take|aux_rate|reaper_item_guid
  f:write(string.format("ROWS|%d\n", #ROWS))
  for _, row in ipairs(ROWS) do
    f:write(string.format("R|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%s|%s\n",
      _clb_escape(row.event_num    or ""),   -- p[2]
      _clb_escape(row.reel         or ""),   -- p[3]
      _clb_escape(row.track        or ""),   -- p[4]
      _clb_escape(row.edit_type    or ""),   -- p[5]
      _clb_escape(tostring(row.dissolve_len or "")), -- p[6]
      _clb_escape(row.src_tc_in    or ""),   -- p[7]
      _clb_escape(row.src_tc_out   or ""),   -- p[8]
      _clb_escape(row.rec_tc_in    or ""),   -- p[9]
      _clb_escape(row.rec_tc_out   or ""),   -- p[10]
      _clb_escape(row.clip_name    or ""),   -- p[11]
      _clb_escape(row.source_file  or ""),   -- p[12]
      _clb_escape(row.notes        or ""),   -- p[13]
      _clb_escape(row.match_status or ""),   -- p[14]
      _clb_escape(row.matched_path or ""),   -- p[15]
      _clb_escape(row.group        or ""),   -- p[16]
      _clb_escape(row.__orig_track or ""),   -- p[17]
      row.__source_idx or 0,                 -- p[18]
      _clb_escape(row.level        or ""),   -- p[19]
      _clb_escape(row.scene        or ""),   -- p[20]
      _clb_escape(row.take         or ""),   -- p[21]
      _clb_escape(row.aux_rate and tostring(row.aux_rate) or ""), -- p[22], EDL M2 rate
      _clb_escape(row.reaper_item_guid or ""))) -- p[23], Link Reaper Items
  end

  -- Filter panel visibility flags
  f:write(string.format("SHOW_TRACK_FILTER|%s\n",   CLB.show_track_filter   and "1" or "0"))
  f:write(string.format("SHOW_REEL_FILTER|%s\n",    CLB.show_reel_filter    and "1" or "0"))
  f:write(string.format("SHOW_GROUP_FILTER|%s\n",   CLB.show_group_filter   and "1" or "0"))
  f:write(string.format("SHOW_SOURCES_PANEL|%s\n",  CLB.show_sources_panel  and "1" or "0"))
  f:write(string.format("SHOW_AUDIO_PANEL|%s\n",    CLB.show_audio_panel    and "1" or "0"))

  -- Hidden filter items (one name per line, only the hidden ones)
  for _, tf in ipairs(CLB.track_filters) do
    if not tf.visible then
      f:write(string.format("HIDDEN_TRACK|%s\n", _clb_escape(tf.name)))
    end
  end
  for _, rf in ipairs(CLB.reel_filters) do
    if not rf.visible then
      f:write(string.format("HIDDEN_REEL|%s\n", _clb_escape(rf.name)))
    end
  end
  for _, gf in ipairs(CLB.group_filters) do
    if not gf.visible then
      f:write(string.format("HIDDEN_GROUP|%s\n", _clb_escape(gf.name)))
    end
  end

  f:close()
  console_msg("Saved CLB project: " .. filepath)
  if not silent then
    reaper.ShowMessageBox(
      string.format("Project saved:\n%s\n\n%d events, %d sources",
        filepath:match("([^/\\]+)$") or filepath, #ROWS, #CLB.edl_sources),
      SCRIPT_NAME, 0)
  end
  return true
end

--- Load a .clb project file and restore the full session state.
--- Pure parser: read a .clb project file into a plain data table without
--- touching any live CLB.*/ROWS state. Used by load_clb_project() (which
--- applies the result to the live session) and by Compare's Load Old/New
--- (which needs the rows/fps in isolation, without disturbing whatever the
--- user currently has open in the main table).
--- @return table|nil  { fps, is_drop, source_format, track_format,
---                       audio_folder, audio_recursive, col_order, col_vis,
---                       sources, rows, max_guid,
---                       show_track, show_reel, show_group, show_sources, show_audio,
---                       hidden_tracks, hidden_reels, hidden_groups }
--- @return string|nil  error message if nil was returned
local function _parse_clb_file(filepath)
  local f = io.open(filepath, "r")
  if not f then
    return nil, "Cannot open:\n" .. filepath
  end

  local header = f:read("*l")
  if header ~= "CLB_PROJECT_V1" then
    f:close()
    return nil, "Not a valid CLB project file."
  end

  local new_fps              = 25
  local new_is_drop          = false
  local new_source_format    = "CLB"
  local new_track_format     = "${format} - ${track}"
  local new_audio_folder     = ""
  local new_audio_recursive  = true
  local new_col_order        = nil
  local new_col_vis          = nil
  local new_sources          = {}
  local new_rows             = {}
  local max_guid             = 0
  -- Filter panel flags (nil = not present in file → keep default)
  local new_show_track       = nil
  local new_show_reel        = nil
  local new_show_group       = nil
  local new_show_sources     = nil
  local new_show_audio       = nil
  -- Hidden filter names (sets, keyed by name)
  local hidden_tracks        = {}
  local hidden_reels         = {}
  local hidden_groups        = {}

  for line in f:lines() do
    if line ~= "" then
      local p = _clb_split(line)
      local key = p[1]

      if key == "SOURCE_FORMAT" then
        new_source_format = p[2] or "CLB"

      elseif key == "FPS" then
        new_fps      = tonumber(p[2]) or 25
        new_is_drop  = (p[3] == "1")

      elseif key == "TRACK_FORMAT" then
        new_track_format = p[2] or "${format} - ${track}"

      elseif key == "AUDIO_FOLDER" then
        new_audio_folder = p[2] or ""

      elseif key == "AUDIO_RECURSIVE" then
        new_audio_recursive = (p[2] == "1")

      elseif key == "EDL_COL_ORDER" then
        local order = {}
        for num_str in (p[2] or ""):gmatch("(%d+)") do
          local num = tonumber(num_str)
          if num and num >= 1 and num <= COL_COUNT then
            order[#order+1] = num
          end
        end
        -- Append newly-added columns not in saved order (migration)
        local in_order = {}
        for _, c in ipairs(order) do in_order[c] = true end
        for i = 1, COL_COUNT do
          if not in_order[i] then order[#order+1] = i end
        end
        if #order == COL_COUNT then new_col_order = order end

      elseif key == "EDL_COL_VISIBILITY" then
        local vis = {}; local idx = 0
        for val in (p[2] or ""):gmatch("([01])") do
          idx = idx + 1
          if idx <= COL_COUNT then vis[idx] = (val == "1") end
        end
        if idx >= COL_COUNT then new_col_vis = vis end

      elseif key == "SHOW_TRACK_FILTER"  then new_show_track   = (p[2] == "1")
      elseif key == "SHOW_REEL_FILTER"   then new_show_reel    = (p[2] == "1")
      elseif key == "SHOW_GROUP_FILTER"  then new_show_group   = (p[2] == "1")
      elseif key == "SHOW_SOURCES_PANEL" then new_show_sources = (p[2] == "1")
      elseif key == "SHOW_AUDIO_PANEL"   then new_show_audio   = (p[2] == "1")
      elseif key == "HIDDEN_TRACK"  then hidden_tracks[p[2] or ""] = true
      elseif key == "HIDDEN_REEL"   then hidden_reels [p[2] or ""] = true
      elseif key == "HIDDEN_GROUP"  then hidden_groups[p[2] or ""] = true

      elseif key == "S" then
        -- p[6]/p[7]/p[8] (tc_calib_*, Rec/"New" axis) and p[9]/p[10]/p[11]
        -- (src_calib_*, Src/"Old" axis) are absent in .clb files saved
        -- before each existed — nil p[6]/p[8]/p[9]/p[11] fall back to
        -- disabled/"" and tonumber(nil) falls back to 0, so old files load
        -- exactly as before (no calibration).
        local s_path = p[2] or ""
        local s_ext  = (s_path:match("%.([^./\\]+)$") or ""):lower()
        -- Re-derive the folder-grouping key (see _register_source) so a
        -- later "Load EDL..." for another file from this same reel folder
        -- still folds into this restored source instead of creating a
        -- duplicate. Not itself saved in the .clb format.
        local s_folder = (s_ext == "edl") and CLB.folder_of(s_path) or nil
        new_sources[#new_sources+1] = {
          path        = s_path,
          name        = p[3] or "",
          event_count = tonumber(p[4]) or 0,
          visible     = (p[5] ~= "0"),
          tc_calib_enabled   = (p[6] == "1"),
          tc_calib_delta_sec = tonumber(p[7]) or 0,
          tc_calib_note      = p[8] or "",
          src_calib_enabled   = (p[9] == "1"),
          src_calib_delta_sec = tonumber(p[10]) or 0,
          src_calib_note      = p[11] or "",
          __folder     = s_folder,
          __file_count = s_folder and 1 or nil,
        }

      elseif key == "R" then
        max_guid = max_guid + 1
        local rec_in  = p[9]  or "00:00:00:00"
        local rec_out = p[10] or "00:00:00:00"
        local dur = EDL.seconds_to_tc(
          EDL.tc_to_seconds(rec_out, new_fps, new_is_drop) -
          EDL.tc_to_seconds(rec_in,  new_fps, new_is_drop),
          new_fps, new_is_drop)
        local row = {
          __event_idx  = max_guid,
          __guid       = string.format("clb_%06d", max_guid),
          __source_idx = tonumber(p[18]) or 0,
          __orig_track = p[17] or "",
          event_num    = p[2]  or "",
          reel         = p[3]  or "",
          track        = p[4]  or "",
          edit_type    = p[5]  or "C",
          dissolve_len = (p[6] and p[6] ~= "") and tonumber(p[6]) or nil,
          src_tc_in    = p[7]  or "00:00:00:00",
          src_tc_out   = p[8]  or "00:00:00:00",
          rec_tc_in    = rec_in,
          rec_tc_out   = rec_out,
          clip_name    = p[11] or "",
          source_file  = p[12] or "",
          notes        = p[13] or "",
          match_status = p[14] or "",
          matched_path = p[15] or "",
          group        = p[16] or "",
          level        = p[19] or "",
          scene        = p[20] or "",
          take         = p[21] or "",
          aux_rate     = (p[22] and p[22] ~= "") and tonumber(p[22]) or nil, -- nil for files saved before this field existed
          reaper_item_guid = (p[23] and p[23] ~= "") and p[23] or nil, -- see CLB.link_reaper_items_selection; nil for older files
          duration     = dur,
        }
        row.__search_text = table.concat({
          row.event_num, row.reel, row.track,
          row.clip_name, row.source_file, row.notes, row.group, row.level,
          row.scene, row.take,
          row.src_tc_in, row.src_tc_out,
          row.rec_tc_in, row.rec_tc_out,
          row.duration,
        }, " "):lower()
        new_rows[#new_rows+1] = row
      end
    end
  end
  f:close()

  return {
    fps = new_fps, is_drop = new_is_drop,
    source_format = new_source_format, track_format = new_track_format,
    audio_folder = new_audio_folder, audio_recursive = new_audio_recursive,
    col_order = new_col_order, col_vis = new_col_vis,
    sources = new_sources, rows = new_rows, max_guid = max_guid,
    show_track = new_show_track, show_reel = new_show_reel,
    show_group = new_show_group, show_sources = new_show_sources,
    show_audio = new_show_audio,
    hidden_tracks = hidden_tracks, hidden_reels = hidden_reels, hidden_groups = hidden_groups,
  }
end

local function load_clb_project(filepath)
  local data, err = _parse_clb_file(filepath)
  if not data then
    reaper.ShowMessageBox(err or "Failed to load CLB project.", SCRIPT_NAME, 0)
    return false
  end

  -- Apply loaded data
  CLB.fps               = data.fps
  CLB.is_drop           = data.is_drop
  CLB.track_name_format = data.track_format
  CLB.audio_folder      = data.audio_folder
  CLB.audio_recursive   = data.audio_recursive
  if data.col_order then EDL_COL_ORDER      = data.col_order end
  if data.col_vis   then EDL_COL_VISIBILITY = data.col_vis   end
  CLB.edl_sources       = data.sources
  ROWS                  = data.rows
  _guid_counter         = data.max_guid

  -- Filter panel visibility flags
  if data.show_track   ~= nil then CLB.show_track_filter   = data.show_track   end
  if data.show_reel    ~= nil then CLB.show_reel_filter    = data.show_reel    end
  if data.show_group   ~= nil then CLB.show_group_filter   = data.show_group   end
  if data.show_sources ~= nil then CLB.show_sources_panel  = data.show_sources end

  -- Reset UI state
  sel_clear()
  EDIT = nil
  SORT_STATE.columns = {}
  UNDO_STACK = {}
  UNDO_POS   = 0
  undo_snapshot()
  CLB.loaded_file   = filepath
  CLB.loaded_format = data.source_format
  CLB.loaded_is_clb = true

  -- Rebuild filter panels, then apply saved hidden states
  _rebuild_track_filters()
  _rebuild_reel_filters()
  _rebuild_group_filters()

  if next(data.hidden_tracks) then
    for _, tf in ipairs(CLB.track_filters) do
      if data.hidden_tracks[tf.name] then tf.visible = false end
    end
  end
  if next(data.hidden_reels) then
    for _, rf in ipairs(CLB.reel_filters) do
      if data.hidden_reels[rf.name] then rf.visible = false end
    end
  end
  if next(data.hidden_groups) then
    for _, gf in ipairs(CLB.group_filters) do
      if data.hidden_groups[gf.name] then gf.visible = false end
    end
  end

  CLB.cached_rows = nil

  -- Try to restore audio files from cache (don't re-run matching — match data is in rows)
  CLB.audio_files      = {}
  CLB.show_audio_panel = false
  if data.audio_folder ~= "" then
    local cached = load_audio_cache(data.audio_folder, data.audio_recursive)
    if cached then
      CLB.audio_files = cached
      -- Restore audio panel visibility from file, or default to true if audio loaded
      CLB.show_audio_panel = (data.show_audio ~= nil) and data.show_audio or true
      console_msg(string.format("Restored %d audio files from cache", #cached))
    else
      console_msg("Audio cache not found — click 'Load Audio...' to re-scan: " .. data.audio_folder)
    end
  end

  console_msg(string.format("Loaded CLB project: %d events, %d sources", #ROWS, #CLB.edl_sources))
  return true
end

--- Open project dialog → load_clb_project.
local function open_clb_project()
  local retval, filepath
  if reaper.JS_Dialog_BrowseForOpenFiles then
    retval, filepath = reaper.JS_Dialog_BrowseForOpenFiles(
      "Open CLB Project", CLB.last_dir or "", "",
      "CLB Project (*.clb)\0*.clb\0All files\0*.*\0", false)
    if retval ~= 1 or not filepath or filepath == "" then return end
  else
    retval, filepath = reaper.GetUserFileNameForRead("", "Open CLB Project", "*.clb")
    if not retval or filepath == "" then return end
  end
  CLB.last_dir = filepath:match("^(.*)[/\\]") or CLB.last_dir
  load_clb_project(filepath)
  save_prefs()
end

--- Reset the main table to empty (does not touch loaded audio files/folder,
--- or Compare's independent Old/New state). Confirms first if there's
--- anything loaded, since it can't be undone once the undo stack is reset.
local function clear_list()
  if #ROWS > 0 then
    local choice = reaper.ShowMessageBox(
      string.format("Clear the current list? (%d events)\n\nThis cannot be undone.", #ROWS),
      SCRIPT_NAME, 4)  -- Yes/No
    if choice ~= 6 then return end
  end

  ROWS            = {}
  CLB.edl_sources = {}
  _guid_counter   = 0
  CLB.loaded_file   = nil
  CLB.loaded_format = nil
  CLB.loaded_is_clb = false
  CLB.viewing_compare_groups = false
  CLB._compare_rows_backup   = nil

  sel_clear()
  EDIT = nil
  SORT_STATE.columns = {}
  UNDO_STACK = {}
  UNDO_POS   = 0
  undo_snapshot()

  _rebuild_track_filters()
  _rebuild_reel_filters()
  _rebuild_group_filters()
  CLB.cached_rows = nil

  console_msg("List cleared")
end

--- Save-as dialog → save_clb_project.
local function save_clb_project_dialog()
  -- "conform_YYMMDD_HHMMSS" — user's own request: unify with Export's
  -- own default naming (export_YYMMDD_HHMMSS.<ext>), same date/time
  -- format (2-digit year + seconds), just a different prefix per action.
  local default = "conform_" .. os.date("%y%m%d_%H%M%S") .. ".clb"
  local filepath = choose_save_path(default,
    "CLB Project (*.clb)\0*.clb\0All files\0*.*\0")
  if not filepath then return end
  if not filepath:match("%.clb$") then filepath = filepath .. ".clb" end
  CLB.last_dir = filepath:match("^(.*)[/\\]") or CLB.last_dir
  if save_clb_project(filepath, false) then
    CLB.loaded_file = filepath
    -- loaded_format is NOT changed here — it's the original content format
    -- (XML/AAF/EDL) and stays whatever it was; only loaded_is_clb reflects
    -- that CLB.loaded_file is now a .clb project (previously this line set
    -- loaded_format = "CLB" directly, which overwrote e.g. "XML" the moment
    -- you saved and flipped the header label from "XML Events" to "EDL
    -- Events" without even reloading anything).
    CLB.loaded_is_clb = true
  end
  save_prefs()
end

--- Show a frame-rate confirmation dialog. Updates CLB.fps / CLB.is_drop.
--- Returns true if user confirmed, false if cancelled.
local function confirm_fps()
  local drop_hint = CLB.is_drop and "Y" or "N"
  local ok, vals = reaper.GetUserInputs(
    "Confirm Frame Rate", 2,
    "Frame rate (e.g. 24, 25, 29.97, 30):,Drop Frame? (Y/N):",
    tostring(CLB.fps) .. "," .. drop_hint)
  if not ok then return false end

  local fps_str, df_str = vals:match("^([^,]+),(.+)$")
  local new_fps = tonumber(fps_str)
  if not new_fps or new_fps <= 0 then
    reaper.ShowMessageBox("Invalid frame rate: " .. tostring(fps_str), SCRIPT_NAME, 0)
    return false
  end
  CLB.fps     = new_fps
  CLB.is_drop = (df_str:match("^%s*[Yy]%s*$") ~= nil)
  save_prefs()
  return true
end

--- Shared timeline loader: opens a file dialog, parses via OTIO Bridge,
--- then replaces or appends rows. Used by load_edl_file() and load_xml_file().
---
--- @param dialog_title  string  Title for the file-open dialog
--- @param file_filter   string  Null-separated filter string for JS_Dialog_BrowseForOpenFiles
--- @param fallback_ext  string  Extension for the fallback single-file dialog (e.g. "*.edl")
local function _load_timeline_via_otio(dialog_title, file_filter, fallback_ext)
  -- Collect file paths (multi-select via JS extension, fallback to single)
  local filepaths = {}

  if reaper.JS_Dialog_BrowseForOpenFiles then
    local rv, filestr = reaper.JS_Dialog_BrowseForOpenFiles(
      dialog_title, CLB.last_dir or "", "", file_filter, true)
    if rv ~= 1 or not filestr or filestr == "" then return end

    local parts = {}
    for part in (filestr .. "\0"):gmatch("([^\0]*)\0") do
      if part ~= "" then parts[#parts + 1] = part end
    end

    if #parts == 1 then
      filepaths[1] = parts[1]
    elseif #parts > 1 then
      -- macOS returns all full paths; Windows returns directory + filenames
      if parts[2]:match("^/") or parts[2]:match("^%a:\\") then
        for i = 1, #parts do filepaths[#filepaths + 1] = parts[i] end
      else
        local dir = parts[1]
        if not dir:match("[/\\]$") then dir = dir .. "/" end
        for i = 2, #parts do filepaths[#filepaths + 1] = dir .. parts[i] end
      end
    end
  else
    -- Fallback: single file dialog
    local retval, filepath = reaper.GetUserFileNameForRead("", dialog_title, fallback_ext)
    if not retval or filepath == "" then return end
    filepaths[1] = filepath
  end

  if #filepaths == 0 then return end

  -- Launch async background parse for all files.
  -- parse_async_start is non-blocking for .aaf/.xml (spawns Python in background).
  -- For .edl it resolves immediately.
  -- The first file's handle is stored in loading_state; process_otio_loading() polls it.

  -- Remember directory immediately
  CLB.last_dir = filepaths[1]:match("(.*[/\\])") or ""
  save_prefs()

  local first_handle, launch_err = OTIO.parse_async_start(
    filepaths[1], { default_fps = CLB.fps, python = OTIO.python })
  if not first_handle then
    reaper.ShowMessageBox(
      "Failed to start loading:\n\n" .. tostring(launch_err),
      SCRIPT_NAME, 0)
    return
  end

  CLB.loading_state = {
    phase        = "otio_loading",
    filepaths    = filepaths,
    current_idx  = 1,
    active_handle= first_handle,
    all_parsed   = {},
    errors       = {},
    default_fps  = CLB.fps,
    start_time   = reaper.time_precise(),
  }

  -- Immediate console feedback (UI progress bar appears next frame)
  local n = #filepaths
  if n == 1 then
    console_msg("Loading: " .. (filepaths[1]:match("([^/\\]+)$") or filepaths[1]))
  else
    console_msg(string.format("Loading %d files...", n))
  end
end

local function load_edl_file()
  _load_timeline_via_otio(
    "Open EDL Files",
    "EDL files\0*.edl\0All files\0*.*\0",
    "*.edl")
end

local function load_xml_file()
  _load_timeline_via_otio(
    "Open XML Files (FCP7 / Resolve / Premiere)",
    "XML files\0*.xml\0All files\0*.*\0",
    "*.xml")
end

local function load_aaf_file()
  _load_timeline_via_otio(
    "Open AAF Files",
    "AAF files\0*.aaf\0All files\0*.*\0",
    "*.aaf")
end

-- Forward-declared; defined after _apply_timeline_results so it can call it.
local load_subtitle_file

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

  -- Check for cached metadata
  local cached_files = load_audio_cache(folder, CLB.audio_recursive)
  if cached_files and #cached_files > 0 then
    -- Verify cached files still exist (spot check first and last)
    local valid = true
    if #cached_files > 0 then
      local first = cached_files[1]
      local last = cached_files[#cached_files]
      local f1 = io.open(first.path, "r")
      local f2 = io.open(last.path, "r")
      if not f1 or not f2 then valid = false end
      if f1 then f1:close() end
      if f2 then f2:close() end
    end

    if valid then
      console_msg(string.format("Using cached metadata for %d files", #cached_files))
      CLB.audio_files = cached_files
      CLB.audio_cached = nil
      CLB.show_audio_panel = true

      -- Auto-match if EDL is loaded
      if #ROWS > 0 then
        match_audio_files()
      end
      return
    else
      console_msg("Cache invalid (files moved/deleted), rescanning...")
    end
  end

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
    folder = folder,           -- Save for cache
    recursive = CLB.audio_recursive,
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

      -- Save to cache for next time
      if state.folder and state.folder ~= "" then
        save_audio_cache(state.folder, state.recursive, state.files)
      end

      CLB.loading_state = nil
      CLB.audio_cached = nil

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

--- Generic per-frame chunked batch-job runner. A job processes
--- job.batch_size items per frame via job.step(job, i) (i = 1-based index
--- into whatever the job is iterating), then calls job.finish(job) once
--- job.current reaches job.total. Keeps Reaper responsive — the progress
--- bar actually redraws between batches — instead of freezing for the
--- whole run inside one giant synchronous loop. Same principle as
--- process_audio_loading_batch() above, generalised for Generate Items /
--- Conform / Match All, each of which sets CLB.batch_job and returns
--- immediately rather than running its own loop to completion inline.
--- Hung off CLB (not a new top-level local) — this script is already at
--- Lua's 200-local-per-chunk ceiling (see CMP for the same workaround).
function CLB.process_batch_job()
  local job = CLB.batch_job
  if not job then return false end

  local batch_size = job.batch_size or 25
  for i = 1, batch_size do
    if job.current >= job.total then
      job.finish(job)
      CLB.batch_job = nil
      return false
    end
    job.current = job.current + 1
    job.step(job, job.current)
  end
  return true
end

--- Apply a list of successfully-parsed timeline results (all_parsed).
--- all_parsed = array of { parsed=table, path=string }
--- filepaths  = original file paths (for Replace/Append dialog)
--- default_fps = fallback fps
--- opts (optional) = {
---   force_choice = "replace"|"append"|nil — skips the Replace/Append
---     dialog entirely and does that directly instead. Only
---     CLB.load_from_reaper_selection uses this (CLB.ref_load_merge_mode
---     setting, user's own request — repeatedly re-answering the same
---     dialog on every "Load From Reaper" run got old). Every other
---     loader (EDL/XML/AAF/Subtitle) always passes nil, unaffected.
---   skip_fps_confirm = true|false — skips the trailing confirm_fps()
---     call. Only CLB.load_from_reaper_selection uses this too (once
---     FPS has been confirmed for this Reaper PROJECT, user's own
---     request to stop re-asking every run).
--- }
--- @return boolean  true if rows were actually loaded/appended, false if
---   there was nothing to apply or the user cancelled the Replace/Append
---   prompt — existing callers ignore this; CLB.load_from_reaper_selection
---   checks it before deciding whether to auto-match (running Find Match
---   after a cancelled load would be wrong).
local function _apply_timeline_results(all_parsed, filepaths, default_fps, opts)
  opts = opts or {}
  if #all_parsed == 0 then return false end

  -- Count total events for the dialog
  local total_events = 0
  for _, ap in ipairs(all_parsed) do total_events = total_events + #ap.parsed.events end

  if #ROWS > 0 then
    local choice
    if opts.force_choice == "replace" then
      choice = 6
    elseif opts.force_choice == "append" then
      choice = 7
    else
      local file_desc = #filepaths == 1
        and (filepaths[1]:match("([^/\\]+)$") or filepaths[1])
        or (#filepaths .. " files")
      choice = reaper.ShowMessageBox(
        string.format(
          "Current list has %d events.\n\n" ..
          "Loading: %s (%d events)\n\n" ..
          "Yes = Replace (clear current list)\n" ..
          "No = Append (add to current list)",
          #ROWS, file_desc, total_events),
        SCRIPT_NAME, 3)
    end

    if choice == 2 then return false end   -- Cancel

    if choice == 6 then
      CLB.loaded_file   = #filepaths == 1 and filepaths[1] or nil
      CLB.loaded_format = all_parsed[1].parsed.format
      CLB.loaded_is_clb = false
      CLB.parsed_data   = all_parsed[1].parsed
      build_rows_from_parsed(all_parsed[1].parsed, all_parsed[1].path)
      for i = 2, #all_parsed do
        append_rows_from_parsed(all_parsed[i].parsed, all_parsed[i].path)
      end
    else
      for _, ap in ipairs(all_parsed) do
        append_rows_from_parsed(ap.parsed, ap.path)
      end
    end
  else
    CLB.loaded_file   = #filepaths == 1 and filepaths[1] or nil
    CLB.loaded_format = all_parsed[1].parsed.format
    CLB.loaded_is_clb = false
    CLB.parsed_data   = all_parsed[1].parsed
    build_rows_from_parsed(all_parsed[1].parsed, all_parsed[1].path)
    for i = 2, #all_parsed do
      append_rows_from_parsed(all_parsed[i].parsed, all_parsed[i].path)
    end
  end

  _apply_track_suffixes()
  _rebuild_track_filters()
  CLB.cached_rows = nil

  if #all_parsed > 1 then
    console_msg(string.format("Loaded %d files (%d total events)", #all_parsed, #ROWS))
  end

  if not opts.skip_fps_confirm then
    confirm_fps()
  end
  return true
end

---------------------------------------------------------------------------
-- Read one Reaper item as an event (shared: Load From Reaper, Link Items)
---------------------------------------------------------------------------
-- Wrapped in do...end: the main chunk is at Lua's 200-local limit, so
-- these helpers stay scoped to CLB._read_item_event instead.
do
--- Reads one line matching "Label: value" out of an item's free-form
--- Notes text (CLB's own convention — see e.g. CLB.generate_items's
--- note_parts) — nil if that label isn't present.
local function _item_notes_field(notes, label)
  if not notes or notes == "" then return nil end
  for line in notes:gmatch("[^\r\n]+") do
    local v = line:match("^" .. label .. ":%s*(.-)%s*$")
    if v and v ~= "" then return v end
  end
  return nil
end

local function _take_pext(take, key)
  local ok, v = reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:" .. key, "", false)
  return (ok and v ~= "") and v or nil
end

--- True only for a real "HH:MM:SS:FF" (or ;/. separated) TC string —
--- EDL.tc_to_seconds silently returns 0 for anything else, which would
--- otherwise read as a valid 00:00:00:00.
local function _is_tc(s)
  return type(s) == "string" and s:match("^%d+[:;.]%d+[:;.]%d+[:;.]%d+$") ~= nil
end

--- Reads one Reaper item into an EDL.parse()-shaped event — the per-item
--- core of CLB.load_from_reaper_selection, also reused by
--- CLB.link_reaper_items_selection (same field derivation, so "what CLB
--- thinks this item is" never differs between the two features).
---
--- Src TC In/Out falls back: P_EXT:CLB_SRC_TC_IN/OUT (exact round-trip
--- for any CLB-generated item) → "Src In:"/"Src Out:" lines in the item's
--- own Notes (survive a glue/render that replaced the take) → this take's
--- own source BWF TimeReference + D_STARTOFFS/D_PLAYRATE ("reverse
--- conform" for real production audio) → none. See
--- CLB.load_from_reaper_selection's doc comment for the other fields.
---
--- event_num is left nil when the take has no P_EXT:CLB_EVENT — the
--- caller decides its own fallback numbering.
--- @return table evt   Event (src_tc_* default "00:00:00:00" when unknown)
--- @return table info  { src_method = "pext"|"notes"|"bwf"|nil,
---                       src_tc_in, src_tc_out (nil when unknown),
---                       pext_rec_tc_in, pext_rec_tc_out, pext_track,
---                       pos, len }
function CLB._read_item_event(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local take = reaper.GetActiveTake(item)
  local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  local track_obj = reaper.GetMediaItem_Track(item)
  local _, reaper_track_name = reaper.GetTrackName(track_obj)

  local clip_name, source_file = "", ""
  local src_tc_in, src_tc_out, src_method = nil, nil, nil
  local reel, scene, take_field = nil, nil, nil
  local event_num, track_val = nil, nil
  local pext_rec_in, pext_rec_out = nil, nil

  if take then
    local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    clip_name = tn or ""

    event_num = _take_pext(take, "CLB_EVENT")
    reel      = _take_pext(take, "CLB_REEL")
    track_val = _take_pext(take, "CLB_TRACK")
    pext_rec_in  = _take_pext(take, "CLB_REC_TC_IN")
    pext_rec_out = _take_pext(take, "CLB_REC_TC_OUT")
    local p_in, p_out = _take_pext(take, "CLB_SRC_TC_IN"), _take_pext(take, "CLB_SRC_TC_OUT")
    if _is_tc(p_in) and _is_tc(p_out) then
      src_tc_in, src_tc_out, src_method = p_in, p_out, "pext"
    end

    local source = reaper.GetMediaItemTake_Source(take)
    if source then
      local srcfile = reaper.GetMediaSourceFileName(source, "")
      if srcfile and srcfile ~= "" then
        source_file = srcfile:match("([^/\\]+)$") or srcfile
      end
    end

    if not src_method then
      local n_in, n_out = _item_notes_field(notes, "Src In"), _item_notes_field(notes, "Src Out")
      local meta = source and CLB._read_metadata_from_source(source) or nil
      if _is_tc(n_in) and _is_tc(n_out) then
        src_tc_in, src_tc_out, src_method = n_in, n_out, "notes"
      elseif meta and meta.timereference ~= "" and meta.samplerate and meta.samplerate > 0 then
        local startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
        local playrate  = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
        if playrate == 0 then playrate = 1.0 end
        local source_start_sec = (tonumber(meta.timereference) / meta.samplerate) + startoffs
        local source_len_sec = len * playrate
        src_tc_in  = EDL.seconds_to_tc(source_start_sec, CLB.fps, CLB.is_drop)
        src_tc_out = EDL.seconds_to_tc(source_start_sec + source_len_sec, CLB.fps, CLB.is_drop)
        src_method = "bwf"
      end
      if not reel and meta then
        reel = (meta.reel ~= "" and meta.reel) or (meta.tape ~= "" and meta.tape) or nil
      end
      if meta then
        scene      = (meta.scene ~= "" and meta.scene) or nil
        take_field = (meta.take  ~= "" and meta.take)  or nil
      end
    end
  end

  -- Notes override/fill scene/take/reel last — these are CLB's own
  -- human-readable record of what a previous CLB step already wrote
  -- (e.g. Generate Ref Media's own note_parts), so prefer them over a
  -- freshly-read file metadata guess when both exist.
  scene      = _item_notes_field(notes, "Scene") or scene
  take_field = _item_notes_field(notes, "Take")  or take_field
  reel       = reel or _item_notes_field(notes, "Reel")

  local evt = {
    event_num  = event_num,
    reel       = reel or "",
    -- Reaper's OWN current track name is authoritative, not the
    -- P_EXT:CLB_TRACK value (frozen at generation time) — user's own
    -- request: this list reflects the session's CURRENT state, and an
    -- item may have been moved to a different track since it was
    -- created, or that track renamed, since then.
    track      = reaper_track_name or track_val or "",
    edit_type  = "C",
    src_tc_in  = src_tc_in  or "00:00:00:00",
    src_tc_out = src_tc_out or "00:00:00:00",
    rec_tc_in  = EDL.seconds_to_tc(pos, CLB.fps, CLB.is_drop),
    rec_tc_out = EDL.seconds_to_tc(pos + len, CLB.fps, CLB.is_drop),
    clip_name  = clip_name,
    source_file = source_file,
    scene = scene or "",
    take  = take_field or "",
    notes = notes or "", -- the item's own P_NOTES, verbatim — see _make_rows_from_events' evt.notes handling
    __reaper_item = item, -- see _make_rows_from_events' own comment on row.__reaper_item
  }
  local info = {
    src_method = src_method,
    src_tc_in = src_tc_in, src_tc_out = src_tc_out,
    pext_rec_tc_in  = _is_tc(pext_rec_in)  and pext_rec_in  or nil,
    pext_rec_tc_out = _is_tc(pext_rec_out) and pext_rec_out or nil,
    pext_track = track_val,
    pos = pos, len = len,
  }
  return evt, info
end
end -- do (CLB._read_item_event helpers)

---------------------------------------------------------------------------
-- Load List From Reaper Selection
---------------------------------------------------------------------------
--- "Another kind of list source" (user's own framing) — reads currently
--- selected REAPER media items back into the event list, the reverse of
--- Generate Items/Generate Ref Media. Real motivating case: verify a
--- just-generated batch of reference items actually Find-Matches
--- correctly, without re-exporting/re-loading any EDL file at all — but
--- deliberately general-purpose (works on any selected item, CLB-
--- generated or real production audio already in the session), per the
--- user's own framing. Builds a synthetic EDL.parse()-shaped event list
--- from the selection and hands it to the SAME _apply_timeline_results
--- pipeline every other loader (EDL/XML/AAF/Subtitle) already uses —
--- gets the existing Replace/Append/Cancel prompt, source registration,
--- filter rebuild, and FPS confirm for free, instead of duplicating any
--- of that.
---
--- Per-item field derivation (each one falls back in this order):
---   Src TC In/Out  — P_EXT:CLB_SRC_TC_IN/OUT (exact round-trip for any
---                    CLB-generated item) → "Src In:"/"Src Out:" lines
---                    in the item's own Notes → else this take's own source
---                    BWF TimeReference + D_STARTOFFS/D_PLAYRATE (same
---                    math as hsuanice_Item List Editor - ILE.lua's own
---                    calculate_source_position, for real production
---                    audio already carrying embedded metadata) → blank
---   Reel           — P_EXT:CLB_REEL → source's own iXML TAPE/BWF REEL
---                    (via CLB._read_metadata_from_source) → "Reel:" line
---                    in the item's own Notes (CLB's own Notes
---                    convention) → ""
---   Scene/Take     — "Scene:"/"Take:" lines in Notes → source's own
---                    iXML SCENE/TAKE → ""
---   Track          — P_EXT:CLB_TRACK (the ORIGINAL EDL track label,
---                    which the Reaper track's own name may have been
---                    expanded away from via track_name_format) → the
---                    Reaper track's own name
---   Event #        — P_EXT:CLB_EVENT → sequential, numbered after
---                    sorting selected items by timeline position (not
---                    Reaper's arbitrary selection/click order)
---   Clip Name      — the take's own P_NAME, always
---   Source File    — the take's underlying source file's own basename,
---                    if any (just for display/reference)
function CLB.load_from_reaper_selection()
  local n_sel = reaper.CountSelectedMediaItems(0)
  if n_sel == 0 then
    reaper.ShowMessageBox(
      "No items selected in Reaper.\n\nSelect item(s) on the timeline first.",
      SCRIPT_NAME, 0)
    return
  end

  local items = {}
  for i = 0, n_sel - 1 do
    items[#items + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  table.sort(items, function(a, b)
    return reaper.GetMediaItemInfo_Value(a, "D_POSITION") < reaper.GetMediaItemInfo_Value(b, "D_POSITION")
  end)

  local events = {}
  for idx, item in ipairs(items) do
    local evt = CLB._read_item_event(item)
    -- Sequential fallback, numbered in timeline order (see sort above)
    evt.event_num = evt.event_num or string.format("%03d", idx)
    events[#events + 1] = evt
  end

  local parsed = {
    format = "REAPER",
    title = "Reaper Selection",
    fps = CLB.fps,
    is_drop = CLB.is_drop,
    events = events,
    source_path = "Reaper Selection",
  }

  -- Per-PROJECT (not global) "already asked" flag — user's own request:
  -- re-confirming FPS on every single "Load From Reaper" run in the same
  -- project got old; still asks once, the first time, per project (via
  -- GetProjExtState/SetProjExtState, which live in the .rpp itself, so a
  -- DIFFERENT project correctly asks again).
  local ok_pes, fps_already_confirmed = reaper.GetProjExtState(0, EXT_NS, "lfr_fps_confirmed")
  fps_already_confirmed = (ok_pes == 1 and fps_already_confirmed == "1")

  -- CLB.ref_load_merge_mode ("ask" default | "replace" | "append", see
  -- Options) — same spirit, same user request: repeatedly re-answering
  -- the Replace/Append dialog on every run got old too.
  local force_choice = (CLB.ref_load_merge_mode == "replace" or CLB.ref_load_merge_mode == "append")
    and CLB.ref_load_merge_mode or nil

  local applied = _apply_timeline_results(
    { { parsed = parsed, path = "Reaper Selection" } }, { "Reaper Selection" }, CLB.fps,
    { force_choice = force_choice, skip_fps_confirm = fps_already_confirmed })

  if applied and not fps_already_confirmed then
    reaper.SetProjExtState(0, EXT_NS, "lfr_fps_confirmed", "1")
  end

  -- Only auto-match if the load actually happened — _apply_timeline_results
  -- returns false if the user cancelled its own Replace/Append prompt
  -- (ROWS is then unchanged, so running Find Match here would be wrong).
  if applied and CLB.ref_load_auto_match then
    if #CLB.audio_files == 0 then
      load_audio_folder() -- auto-matches internally once it finishes, since ROWS is already populated
    else
      match_audio_files()
    end
  end
end

---------------------------------------------------------------------------
-- Link Reaper Items (persistent row → item link, by item GUID)
---------------------------------------------------------------------------
--- GUID → MediaItem* lookup cache for CLB.find_item_by_guid. Rebuilt in
--- full (one pass over every project item) when a lookup misses or finds
--- a stale pointer — but at most once per project state change
--- (GetProjectStateChangeCount), so a batch of stale links (e.g. Conform
--- over many rows whose items were deleted) can't rescan per row.
CLB._guid_item_cache = nil
CLB._guid_cache_state = nil

--- Finds the item with this exact GUID in the current project, or nil.
function CLB.find_item_by_guid(guid)
  if not guid or guid == "" then return nil end
  local cache = CLB._guid_item_cache
  local it = cache and cache[guid]
  if it and reaper.ValidatePtr2(0, it, "MediaItem*") then
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if g == guid then return it end
  end
  local state = reaper.GetProjectStateChangeCount(0)
  if cache and CLB._guid_cache_state == state and not it then return nil end
  cache = {}
  for i = 0, reaper.CountMediaItems(0) - 1 do
    local item = reaper.GetMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
    if g and g ~= "" then cache[g] = item end
  end
  CLB._guid_item_cache = cache
  CLB._guid_cache_state = state
  return cache[guid]
end

--- The Reaper item a row is linked to, or nil: the live pointer from
--- "Load From Reaper" (row.__reaper_item) if still valid, else the
--- persisted GUID link from "Link Reaper Items" (row.reaper_item_guid).
--- Used for jump/select AND Conform (both link kinds get the matched audio
--- added as takes on that item — user's own request, v261009.2349; the
--- GUID link originally deliberately didn't). Track-suffixing still keys
--- off row.__reaper_item alone: only a Load From Reaper row's track is a
--- live Reaper track name rather than an EDL label.
function CLB.row_linked_item(row)
  if row.__reaper_item and reaper.ValidatePtr2(0, row.__reaper_item, "MediaItem*") then
    return row.__reaper_item
  end
  return CLB.find_item_by_guid(row.reaper_item_guid)
end

--- Index of every row in ROWS for 4-TC item matching (see
--- CLB._match_item_rows) — built once per Link run / Reveal, never per
--- frame. Keyed by Src TC In frame; ±1 frame is looked up at match time.
function CLB._build_link_index()
  local fps, drop = CLB.fps, CLB.is_drop
  local function frames(sec) return math.floor(sec * fps + 0.5) end
  local function tc_frames(tc) return frames(EDL.tc_to_seconds(tc, fps, drop)) end
  local by_src_in = {}
  for _, row in ipairs(ROWS) do
    local k = tc_frames(row.src_tc_in)
    by_src_in[k] = by_src_in[k] or {}
    table.insert(by_src_in[k], {
      row = row,
      s_in = k, s_out = tc_frames(row.src_tc_out),
      r_in_raw = tc_frames(row.rec_tc_in), r_out_raw = tc_frames(row.rec_tc_out),
      r_in_pos  = frames(CLB.rec_tc_seconds(row.rec_tc_in, row)),
      r_out_pos = frames(CLB.rec_tc_seconds(row.rec_tc_out, row)),
    })
  end
  return { by_src_in = by_src_in, frames = frames, tc_frames = tc_frames }
end

--- Rows matching one item (its `info` from CLB._read_item_event, which
--- must have a src_method) on all 4 TCs, ±1 frame — see
--- CLB.link_reaper_items_selection's doc comment for the exact rules.
--- @return table  list of rows (empty if none)
function CLB._match_item_rows(link_idx, info)
  local frames, tc_frames = link_idx.frames, link_idx.tc_frames
  local function near(a, b) return math.abs(a - b) <= 1 end
  local s_in, s_out = tc_frames(info.src_tc_in), tc_frames(info.src_tc_out)
  local cands = {}
  for k = s_in - 1, s_in + 1 do
    for _, e in ipairs(link_idx.by_src_in[k] or {}) do
      if near(e.s_out, s_out) then cands[#cands + 1] = e end
    end
  end
  local hits = {}
  if info.pext_rec_tc_in and info.pext_rec_tc_out then
    local ri, ro = tc_frames(info.pext_rec_tc_in), tc_frames(info.pext_rec_tc_out)
    for _, e in ipairs(cands) do
      if near(e.r_in_raw, ri) and near(e.r_out_raw, ro) then hits[#hits + 1] = e.row end
    end
  end
  if #hits == 0 then
    local ri, ro = frames(info.pos), frames(info.pos + info.len)
    for _, e in ipairs(cands) do
      if near(e.r_in_pos, ri) and near(e.r_out_pos, ro) then hits[#hits + 1] = e.row end
    end
  end
  if #hits > 1 and info.pext_track then
    local narrowed = {}
    for _, row in ipairs(hits) do
      if row.track == info.pext_track or row.__orig_track == info.pext_track then
        narrowed[#narrowed + 1] = row
      end
    end
    if #narrowed > 0 then hits = narrowed end
  end
  return hits
end

--- "Link Reaper Items" — user's own request: link the CURRENTLY LOADED
--- event list's rows to real items already in the session (e.g. items
--- generated from this list long ago, since glued/rendered to audio), so
--- clicking Clip Name jumps to that item — and keep the link across .clb
--- save/reload (stored as the item's GUID, which Reaper itself persists
--- in the .rpp, through Save As too). The reverse of Load From Reaper:
--- that one CREATES rows from items, this one attaches items to EXISTING
--- rows without touching anything else on them.
---
--- Per selected item, reads it via the shared CLB._read_item_event, then
--- matches rows on all 4 TCs (±1 frame):
---   Src In/Out — whichever source _read_item_event found (P_EXT → Notes
---                "Src In/Out" → BWF TimeReference "reverse conform").
---   Rec In/Out — the item's own P_EXT:CLB_REC_TC_IN/OUT vs each row's RAW
---                Rec TC first (still matches an item that's since been
---                moved); else the item's real position/length vs each
---                row's CALIBRATED Rec TC (CLB.rec_tc_seconds).
--- If several rows share all 4 TCs (the same cut on several EDL tracks,
--- e.g. V1 + a NONE track), P_EXT:CLB_TRACK narrows them when it can;
--- whatever remains is linked to the same item — identical TCs mean the
--- same edit, so this isn't a guess. Items matching NO row are left
--- unlinked and listed in the report, never position-only guessed (see
--- feedback: warn, don't guess).
function CLB.link_reaper_items_selection()
  local n_sel = reaper.CountSelectedMediaItems(0)
  if n_sel == 0 then
    reaper.ShowMessageBox(
      "No items selected in Reaper.\n\nSelect item(s) on the timeline first.",
      SCRIPT_NAME, 0)
    return
  end
  if #ROWS == 0 then
    reaper.ShowMessageBox(
      "No event list loaded.\n\nLoad the list (.clb/EDL/XML/AAF) first, then link items to it.",
      SCRIPT_NAME, 0)
    return
  end

  local fps, drop = CLB.fps, CLB.is_drop
  local link_idx = CLB._build_link_index()

  local linked_items, linked_rows, relinked_rows = 0, 0, 0
  local by_method = { pext = 0, notes = 0, bwf = 0 }
  local no_tc, unmatched = {}, {}
  for i = 0, n_sel - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local evt, info = CLB._read_item_event(item)
    local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
    local label = string.format("%s @ %s  \"%s\"", evt.track,
      EDL.seconds_to_tc(info.pos, fps, drop), evt.clip_name)
    if not info.src_method then
      no_tc[#no_tc + 1] = label
    else
      local hits = CLB._match_item_rows(link_idx, info)
      if #hits == 0 then
        unmatched[#unmatched + 1] = label .. "  [Src " .. info.src_tc_in .. " via " .. info.src_method .. "]"
      else
        linked_items = linked_items + 1
        by_method[info.src_method] = by_method[info.src_method] + 1
        for _, row in ipairs(hits) do
          if row.reaper_item_guid and row.reaper_item_guid ~= "" and row.reaper_item_guid ~= guid then
            relinked_rows = relinked_rows + 1
          end
          row.reaper_item_guid = guid
          linked_rows = linked_rows + 1
        end
      end
    end
  end
  CLB._guid_item_cache = nil

  local lines = {
    string.format("Selected items: %d", n_sel),
    string.format("Linked: %d item(s) → %d event row(s)", linked_items, linked_rows),
    string.format("   by CLB take data: %d   by Notes Src In/Out: %d   by BWF timecode: %d",
      by_method.pext, by_method.notes, by_method.bwf),
  }
  if relinked_rows > 0 then
    lines[#lines + 1] = string.format("   (%d row(s) were re-linked from a different item)", relinked_rows)
  end
  local function list_some(title, t)
    if #t == 0 then return end
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("%s: %d", title, #t)
    for k = 1, math.min(#t, 10) do lines[#lines + 1] = "   " .. t[k] end
    if #t > 10 then lines[#lines + 1] = string.format("   ... and %d more (see console)", #t - 10) end
  end
  list_some("No 4-TC match in the list (not linked)", unmatched)
  list_some("No Src TC found on item (no CLB data / Notes / BWF — not linked)", no_tc)
  if linked_rows > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Click a linked row's Clip Name to jump to its item."
    lines[#lines + 1] = "Save the .clb to keep these links."
  end

  for _, l in ipairs(unmatched) do console_msg("Link Items — unmatched: " .. l) end
  for _, l in ipairs(no_tc)     do console_msg("Link Items — no Src TC: " .. l) end
  reaper.ShowMessageBox(table.concat(lines, "\n"), SCRIPT_NAME .. " — Link Reaper Items", 0)
end

--- Reverse link — user's own request: a Reaper item → its event row(s)
--- in CLB (selects their Clip Name cells and scrolls the table there).
--- Rows already linked to this item (persisted GUID or Load From Reaper
--- pointer) win; otherwise the item is matched on the spot with the same
--- 4-TC rules as Link Reaper Items, and — user's own choice — the link is
--- stored too (saved with the .clb), but only onto rows with no link yet:
--- a reveal never silently steals a row already linked to another item.
--- Driven by the "Follow Reaper" checkbox (quiet: result goes to the
--- small status text next to it, no dialogs while you edit) and by the
--- hsuanice_Conform List Browser - CLB Reveal Item.lua wrapper (not quiet: dialogs on failure).
--- @return boolean  true if at least one row was revealed
function CLB.reveal_reaper_item(item, quiet)
  local function tell(msg)
    CLB.follow_status = msg
    if not quiet then reaper.ShowMessageBox(msg, SCRIPT_NAME .. " — Reveal Item", 0) end
  end
  if #ROWS == 0 then tell("No event list loaded."); return false end

  local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  local hits = {}
  for _, row in ipairs(ROWS) do
    if row.reaper_item_guid == guid or row.__reaper_item == item then hits[#hits + 1] = row end
  end

  local newly_linked = 0
  if #hits == 0 then
    local _, info = CLB._read_item_event(item)
    if not info.src_method then
      tell("No Src TC on this item (no CLB data / Notes / BWF) — can't find its event.")
      return false
    end
    hits = CLB._match_item_rows(CLB._build_link_index(), info)
    if #hits == 0 then
      tell("No event in the list matches this item's 4 TCs (Src " .. info.src_tc_in .. ").")
      return false
    end
    for _, row in ipairs(hits) do
      if not row.reaper_item_guid or row.reaper_item_guid == "" then
        row.reaper_item_guid = guid
        newly_linked = newly_linked + 1
      end
    end
  end

  sel_set_single(hits[1].__guid, COL.CLIP_NAME)
  for k = 2, #hits do sel_add(hits[k].__guid, COL.CLIP_NAME) end
  CLB.sel_cursor = { guid = hits[1].__guid, col = COL.CLIP_NAME }
  CLB._sel_synced_version = SEL.version -- came FROM Reaper: don't sync it back
  CLB.scroll_to_row = hits[1].__guid
  CLB.tl_center_on_guid = hits[1].__guid

  local visible = false
  for _, vr in ipairs(get_view_rows()) do
    if vr.__guid == hits[1].__guid then visible = true; break end
  end
  local desc = string.format("→ #%s %s%s%s", hits[1].event_num or "", hits[1].track or "",
    #hits > 1 and string.format(" (+%d)", #hits - 1) or "",
    newly_linked > 0 and "  [linked]" or "")
  if not visible then
    tell(desc .. " — hidden by current filters/search; clear them to see it.")
  else
    CLB.follow_status = desc
  end
  return true
end

--- Cheap signature of Reaper's current item selection — count + first +
--- last selected item pointer (3 API calls, regardless of selection
--- size) — compared per frame by Follow Reaper. Changing only a middle
--- item without changing count/first/last isn't caught, but any real
--- click, Cmd+click (count changes) or marquee (first/last change) is.
function CLB._reaper_sel_sig()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return "0" end
  return n .. "|" .. tostring(reaper.GetSelectedMediaItem(0, 0))
    .. "|" .. tostring(reaper.GetSelectedMediaItem(0, n - 1))
end

--- Reveal for the whole Reaper selection. One item → CLB.reveal_reaper_item
--- (matched on the spot + linked if needed). Several items → ALREADY-
--- LINKED ones only (user's own choice: on-the-spot matching reads each
--- item's audio metadata, too slow for e.g. a whole selected track), all
--- their rows selected; unlinked items are just counted ("use Link").
--- Only rows visible under the current filters/search get selected (a
--- hidden selected row could then be hit by e.g. Delete unseen); hidden
--- ones are counted in the status instead.
function CLB.reveal_reaper_selection(quiet)
  local function tell(msg)
    CLB.follow_status = msg
    if not quiet then reaper.ShowMessageBox(msg, SCRIPT_NAME .. " — Reveal Item", 0) end
  end
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then
    tell("No item selected in Reaper — select item(s) on the timeline first.")
    return false
  end
  if n == 1 then return CLB.reveal_reaper_item(reaper.GetSelectedMediaItem(0, 0), quiet) end
  if #ROWS == 0 then tell("No event list loaded."); return false end

  local by_guid, by_ptr = {}, {}
  for _, row in ipairs(ROWS) do
    if row.reaper_item_guid and row.reaper_item_guid ~= "" then
      local t = by_guid[row.reaper_item_guid] or {}
      t[#t + 1] = row
      by_guid[row.reaper_item_guid] = t
    end
    if row.__reaper_item then
      local t = by_ptr[row.__reaper_item] or {}
      t[#t + 1] = row
      by_ptr[row.__reaper_item] = t
    end
  end

  local hit_set, linked_items, unlinked = {}, 0, 0
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    local found = false
    for _, list in ipairs({ by_guid[g] or {}, by_ptr[it] or {} }) do
      for _, row in ipairs(list) do hit_set[row.__guid] = true; found = true end
    end
    if found then linked_items = linked_items + 1 else unlinked = unlinked + 1 end
  end

  local n_hit_rows = 0
  for _ in pairs(hit_set) do n_hit_rows = n_hit_rows + 1 end
  if n_hit_rows == 0 then
    tell(string.format("None of the %d selected items is linked yet — use Link Reaper Items first.", n))
    return false
  end

  sel_clear()
  local first_vis, n_vis = nil, 0
  for _, vr in ipairs(get_view_rows()) do
    if hit_set[vr.__guid] then
      sel_add(vr.__guid, COL.CLIP_NAME)
      first_vis = first_vis or vr
      n_vis = n_vis + 1
    end
  end
  CLB._sel_synced_version = SEL.version -- came FROM Reaper: don't sync it back
  if first_vis then
    SEL.anchor = { guid = first_vis.__guid, col = COL.CLIP_NAME }
    CLB.sel_cursor = { guid = first_vis.__guid, col = COL.CLIP_NAME }
    CLB.scroll_to_row = first_vis.__guid
    CLB.tl_center_on_guid = first_vis.__guid
  end

  local parts = { string.format("→ %d event(s) from %d item(s)", n_vis, linked_items) }
  if unlinked > 0 then parts[#parts + 1] = string.format("%d unlinked skipped (use Link)", unlinked) end
  if n_hit_rows > n_vis then
    parts[#parts + 1] = string.format("%d hidden by filters/search", n_hit_rows - n_vis)
  end
  local msg = table.concat(parts, "; ")
  if n_vis == 0 or (not quiet and unlinked > 0) then tell(msg) else CLB.follow_status = msg end
  return n_vis > 0
end

---------------------------------------------------------------------------
-- Subtitle / Dialogue List Loading
---------------------------------------------------------------------------

--- Apply a single subtitle parse result to ROWS via the shared timeline pipeline.
local function _apply_subtitle_parsed(parsed, filepath)
  _apply_timeline_results({{ parsed = parsed, path = filepath }}, { filepath },
                          CLB.fps)
end

--- Open a subtitle file dialog and start the inspect/import flow.
---
--- Flow:
---   1. Pick file(s) (.srt / .csv / .tsv / .xlsx) — multi-select via JS extension
---   2. Call SUBTITLE.inspect → returns metadata
---   3. SRT  → no questions; call SUBTITLE.parse with CLB.fps and apply.
---      When multiple files are selected, all ready (SRT) files are parsed
---      and applied together as a single batch (Replace/Append prompt shown
---      once, same as multi-file EDL/XML/AAF import). Any non-SRT file in a
---      mixed selection is skipped with a console notice, since CSV/TSV/XLSX
---      need per-file sheet/column choices.
---   4. Single CSV/TSV/XLSX → open subtitle_inspect dialog; user picks sheet,
---      text column, FPS; on OK → SUBTITLE.parse and apply
load_subtitle_file = function()
  if not SUBTITLE then
    reaper.ShowMessageBox(
      "Subtitle Bridge library failed to load.\n\nExpected at:\n"
      .. SUBTITLE_BRIDGE_PATH,
      SCRIPT_NAME, 0)
    return
  end

  local filter =
    "Subtitle / Dialogue files\0*.srt;*.csv;*.tsv;*.xlsx;*.xlsm\0" ..
    "SRT subtitles\0*.srt\0" ..
    "CSV (comma-separated)\0*.csv\0" ..
    "TSV (tab-separated)\0*.tsv\0" ..
    "Excel\0*.xlsx;*.xlsm\0" ..
    "All files\0*.*\0"

  -- Collect file paths (multi-select via JS extension, fallback to single)
  local filepaths = {}
  if reaper.JS_Dialog_BrowseForOpenFiles then
    local rv, filestr = reaper.JS_Dialog_BrowseForOpenFiles(
      "Open Subtitle / Dialogue File(s)", CLB.last_dir or "", "", filter, true)
    if rv ~= 1 or not filestr or filestr == "" then return end

    local parts = {}
    for part in (filestr .. "\0"):gmatch("([^\0]*)\0") do
      if part ~= "" then parts[#parts + 1] = part end
    end

    if #parts == 1 then
      filepaths[1] = parts[1]
    elseif #parts > 1 then
      -- macOS returns all full paths; Windows returns directory + filenames
      if parts[2]:match("^/") or parts[2]:match("^%a:\\") then
        for i = 1, #parts do filepaths[#filepaths + 1] = parts[i] end
      else
        local dir = parts[1]
        if not dir:match("[/\\]$") then dir = dir .. "/" end
        for i = 2, #parts do filepaths[#filepaths + 1] = dir .. parts[i] end
      end
    end
  else
    local retval, fp = reaper.GetUserFileNameForRead(
      "", "Open Subtitle / Dialogue File", "*.srt")
    if not retval or fp == "" then return end
    filepaths[1] = fp
  end

  if #filepaths == 0 then return end

  CLB.last_dir = filepaths[1]:match("(.*[/\\])") or ""
  save_prefs()

  -- Multiple files selected → batch mode: parse every .srt, skip the rest.
  if #filepaths > 1 then
    local all_parsed, skipped = {}, {}
    for _, fp in ipairs(filepaths) do
      local fname = fp:match("([^/\\]+)$") or fp
      if not fp:lower():match("%.srt$") then
        skipped[#skipped + 1] = fname
      else
        local meta, err = SUBTITLE.inspect(fp, { python = OTIO.python })
        if not meta or not meta.ready then
          skipped[#skipped + 1] = fname
          console_msg("Skipped (inspect failed): " .. fname
                      .. (err and (" - " .. tostring(err)) or ""))
        else
          local parsed, perr = SUBTITLE.parse(fp, {
            python      = OTIO.python,
            default_fps = CLB.fps,
            is_drop     = CLB.is_drop,
          })
          if not parsed then
            skipped[#skipped + 1] = fname
            console_msg("Skipped (parse failed): " .. fname
                        .. (perr and (" - " .. tostring(perr)) or ""))
          else
            all_parsed[#all_parsed + 1] = { parsed = parsed, path = fp }
          end
        end
      end
    end

    if #skipped > 0 then
      console_msg(string.format("Skipped %d file(s) (need column selection or failed): %s",
                                #skipped, table.concat(skipped, ", ")))
    end

    if #all_parsed == 0 then
      reaper.ShowMessageBox(
        "No SRT files could be loaded from the selection.\n\n" ..
        "CSV / TSV / XLSX files must be loaded one at a time (they need " ..
        "sheet / column selection).",
        SCRIPT_NAME, 0)
      return
    end

    local batch_paths = {}
    for _, ap in ipairs(all_parsed) do batch_paths[#batch_paths + 1] = ap.path end
    _apply_timeline_results(all_parsed, batch_paths, CLB.fps)
    return
  end

  -- Single file selected
  local filepath = filepaths[1]
  local fname = filepath:match("([^/\\]+)$") or filepath
  console_msg("Inspecting subtitle file: " .. fname)

  local meta, err = SUBTITLE.inspect(filepath, { python = OTIO.python })
  if not meta then
    reaper.ShowMessageBox("Failed to inspect subtitle file:\n\n" .. tostring(err),
                          SCRIPT_NAME, 0)
    return
  end

  -- SRT → no choices; parse immediately at CLB.fps
  if meta.ready then
    local parsed, perr = SUBTITLE.parse(filepath, {
      python      = OTIO.python,
      default_fps = CLB.fps,
      is_drop     = CLB.is_drop,
    })
    if not parsed then
      reaper.ShowMessageBox(
        "Failed to parse subtitle file:\n\n" .. tostring(perr),
        SCRIPT_NAME, 0)
      return
    end
    _apply_subtitle_parsed(parsed, filepath)
    console_msg(string.format("Loaded %d subtitle entries from %s",
                              #parsed.events, fname))
    return
  end

  -- CSV / TSV / XLSX → open inspect dialog for sheet / text-column / FPS choice
  local sheets = meta.sheets
  if not sheets then
    -- CSV / TSV: wrap into a single virtual sheet for uniform UI handling
    sheets = { {
      name             = (meta.format or "FILE"),
      header_present   = meta.header_present,
      columns          = meta.columns or {},
      sample_rows      = meta.sample_rows or {},
      detected_in_col  = meta.detected_in_col,
      detected_out_col = meta.detected_out_col,
      text_candidates  = meta.text_candidates or {},
    } }
  end

  -- Pick first sheet that actually has detected IN/OUT (skip blank cover sheets)
  local default_idx = 1
  for i, s in ipairs(sheets) do
    if s.detected_in_col and s.detected_out_col and #s.text_candidates > 0 then
      default_idx = i
      break
    end
  end
  local active_sheet = sheets[default_idx] or sheets[1]
  local default_text_col = (active_sheet and active_sheet.text_candidates and
                            active_sheet.text_candidates[1]) or nil

  CLB.subtitle_inspect = {
    filepath           = filepath,
    format             = meta.format,
    sheets             = sheets,
    selected_sheet_idx = default_idx,
    selected_text_col  = default_text_col,
    open               = true,
  }
end

---------------------------------------------------------------------------
-- Old-vs-New Compare (reconform)
---------------------------------------------------------------------------

--- Category (row.group — Video/Audio/Dialog/Effects/Music/etc, the user's
--- own classification) inherited by majority vote from a dedup event's
--- original member rows. Shared by CMP.build_group_rows and
--- CMP.rebuild_filters so both agree on what "group" an event
--- belongs to for filtering / table-category purposes.
function CMP.event_category(e)
  local cat_votes = {}
  for _, orig_row in ipairs(e.__rows or {}) do
    local cat = orig_row.group
    if cat and cat ~= "" then cat_votes[cat] = (cat_votes[cat] or 0) + 1 end
  end
  local best, best_n = "", 0
  for cat, n in pairs(cat_votes) do
    if n > best_n then best, best_n = cat, n end
  end
  return best
end

--- Rebuild the Track/Reel/Group filter panels (CLB.track_filters /
--- .reel_filters / .group_filters) from Compare's own old+new dedup events
--- instead of ROWS. These panels are drawn above the Compare view
--- regardless of view mode (see draw_track_filter_panel, called at the top
--- level), so without this they'd keep showing whatever the main table had
--- loaded before Compare opened — stale, and unable to actually hide
--- anything Compare draws. CMP.draw_side and CMP.build_group_rows
--- both check these same lists so filtering stays consistent between the
--- graphical timeline and the "Show as Table" recut-group list.
function CMP.rebuild_filters(cr)
  local track_counts, track_order = {}, {}
  local reel_counts, reel_order = {}, {}
  local group_counts, group_order = {}, {}

  local function visit(events)
    for _, e in ipairs(events) do
      for _, t in ipairs(e.tracks or {}) do
        if not track_counts[t] then track_counts[t] = 0; track_order[#track_order + 1] = t end
        track_counts[t] = track_counts[t] + 1
      end
      local r = e.reel or ""
      if not reel_counts[r] then reel_counts[r] = 0; reel_order[#reel_order + 1] = r end
      reel_counts[r] = reel_counts[r] + 1
      local g = CMP.event_category(e)
      if not group_counts[g] then group_counts[g] = 0; group_order[#group_order + 1] = g end
      group_counts[g] = group_counts[g] + 1
    end
  end
  visit(cr.old_dedup)
  visit(cr.new_dedup)

  table.sort(track_order, _natural_sort_cmp)
  table.sort(reel_order, _natural_sort_cmp)
  table.sort(group_order, _natural_sort_cmp)

  local function rebuild(old_list, order, counts)
    local old_vis = {}
    for _, f in ipairs(old_list) do old_vis[f.name] = f.visible end
    local new_list = {}
    for _, name in ipairs(order) do
      new_list[#new_list + 1] = {
        name = name, count = counts[name],
        visible = old_vis[name] == nil or old_vis[name],
      }
    end
    return new_list
  end

  -- Like rebuild() above, but for groups: also carries over every name
  -- already in old_list even if it currently has zero events (a group the
  -- user just added or renamed via the Groups panel, before any row was
  -- reassigned to it) — otherwise it would silently vanish the next time
  -- Compare's filter panel refreshes, since it only ever existed here, not
  -- in ROWS' own _rebuild_group_filters (which already preserves these).
  local function rebuild_groups(old_list, order, counts)
    local new_list, seen = {}, {}
    for _, f in ipairs(old_list) do
      if not seen[f.name] then
        seen[f.name] = true
        new_list[#new_list + 1] = { name = f.name, count = counts[f.name] or 0, visible = f.visible }
      end
    end
    for _, name in ipairs(order) do
      if not seen[name] then
        seen[name] = true
        new_list[#new_list + 1] = { name = name, count = counts[name], visible = true }
      end
    end
    return new_list
  end

  CLB.track_filters    = rebuild(CLB.track_filters, track_order, track_counts)
  CLB.reel_filters      = rebuild(CLB.reel_filters, reel_order, reel_counts)
  CLB.reel_sel          = {}
  CLB.reel_sel_anchor   = nil
  CLB.group_filters     = rebuild_groups(CLB.group_filters, group_order, group_counts)
end

--- Run the old-vs-new compare engine against CLB.compare_old / .compare_new
--- (loaded independently via CMP.load_side() — see below; entirely
--- separate from the main ROWS table so opening Compare never disturbs
--- whatever the user currently has loaded there). Results are stored in
--- CLB.compare_result for the Compare view; a summary also prints to console.
function CMP.run()
  if not COMPARE then
    reaper.ShowMessageBox(
      "Compare Engine library failed to load.\n\nExpected at:\n"
      .. COMPARE_ENGINE_PATH,
      SCRIPT_NAME, 0)
    return
  end
  if not (CLB.compare_old and CLB.compare_new) then
    reaper.ShowMessageBox("Load both the OLD and NEW versions first.", SCRIPT_NAME, 0)
    return
  end

  -- Both sides are normalized to the NEW side's fps/is_drop for the compare
  -- math (assumes both versions belong to the same project/frame rate).
  local fps     = CLB.compare_new.fps or CLB.fps
  local is_drop = CLB.compare_new.is_drop or false

  local function to_events(rows)
    local evts = {}
    for _, r in ipairs(rows) do
      evts[#evts + 1] = COMPARE.event_from_row(r, fps, is_drop)
    end
    return evts
  end

  local old_dedup = COMPARE.dedup(to_events(CLB.compare_old.rows), fps)
  local new_dedup = COMPARE.dedup(to_events(CLB.compare_new.rows), fps)

  local changes, reordered = COMPARE.compare(old_dedup, new_dedup, fps)
  local groups = COMPARE.group(changes, fps)

  -- Tag each dedup event with its change classification + owning group, so
  -- the compare-view renderer can color-lookup in O(1). Events left
  -- untagged are Unchanged (not part of any reported change).
  for _, g in ipairs(groups) do
    for _, c in ipairs(g.items) do
      if c.old then c.old.change_type = c.type; c.old.change_group = g end
      if c.new then c.new.change_type = c.type; c.new.change_group = g end
    end
  end

  CLB.compare_result = {
    old_source = { name = CLB.compare_old.name }, new_source = { name = CLB.compare_new.name },
    old_dedup = old_dedup, new_dedup = new_dedup,
    changes = changes, groups = groups, reordered = reordered,
    fps = fps, is_drop = is_drop,
  }
  CLB.show_compare_view = true
  CMP.rebuild_filters(CLB.compare_result)

  local counts = {}
  for _, c in ipairs(changes) do
    counts[c.type] = (counts[c.type] or 0) + 1
  end

  local shift_count, moved_count = 0, 0
  for _, g in ipairs(groups) do
    if g.type == "Moved" then
      if g.is_shift then shift_count = shift_count + #g.items
      else moved_count = moved_count + #g.items end
    end
  end

  console_msg(string.format(
    "Compare: %s (old, %d events) vs %s (new, %d events)",
    CLB.compare_old.name, #old_dedup, CLB.compare_new.name, #new_dedup))
  console_msg(string.format(
    "  Deleted=%d  Trimmed=%d  Extended=%d  Shift=%d  Moved=%d  Added=%d  -> %d group(s)",
    counts.Deleted or 0, counts.Trimmed or 0, counts.Extended or 0,
    shift_count, moved_count, counts.Added or 0, #groups))
  if reordered then
    console_msg("  Note: at least one clip's relative order changed vs. its neighbors (see groups).")
  end
  for _, g in ipairs(groups) do
    console_msg(string.format("  [%s] %s  x%d", g.type, g.label, #g.items))
  end
end

--- Load one side ("old" or "new") of Compare from a file dialog. Accepts
--- EDL/XML/AAF (parsed synchronously via OTIO.parse — Compare typically
--- loads one or two specific version files, not a big multi-file batch, so
--- the blocking call is an acceptable trade for not needing the async
--- poll machinery here) or an existing .clb project (via the pure
--- _parse_clb_file parser, so its already-curated row.group values and
--- rows carry straight through). Auto-runs CMP.run() once both sides
--- are loaded. Never touches ROWS / CLB.edl_sources.
function CMP.load_side(side)
  local filter =
    "Timeline / Project files\0*.edl;*.xml;*.aaf;*.clb\0" ..
    "EDL files\0*.edl\0" ..
    "XML files\0*.xml\0" ..
    "AAF files\0*.aaf\0" ..
    "CLB Project\0*.clb\0" ..
    "All files\0*.*\0"
  local title = "Load " .. (side == "old" and "OLD" or "NEW") .. " version"

  local filepath
  if reaper.JS_Dialog_BrowseForOpenFiles then
    local rv, fp = reaper.JS_Dialog_BrowseForOpenFiles(title, CLB.last_dir or "", "", filter, false)
    if rv ~= 1 or not fp or fp == "" then return end
    filepath = fp
  else
    local retval, fp = reaper.GetUserFileNameForRead("", title, "*.edl")
    if not retval or fp == "" then return end
    filepath = fp
  end

  CLB.last_dir = filepath:match("(.*[/\\])") or CLB.last_dir
  local fname = filepath:match("([^/\\]+)$") or filepath
  local ext = (filepath:match("%.([%w]+)$") or ""):lower()

  local rows, fps, is_drop

  if ext == "clb" then
    local data, err = _parse_clb_file(filepath)
    if not data then
      reaper.ShowMessageBox("Failed to load:\n\n" .. tostring(err), SCRIPT_NAME, 0)
      return
    end
    rows, fps, is_drop = data.rows, data.fps, data.is_drop

    -- Bake each row's "Calibrate TC (Anchor)" correction (if its source
    -- has one enabled) into rec_tc_in/rec_tc_out. Compare's old/new
    -- entries are a disconnected snapshot — once loaded here they have no
    -- ongoing link back to CLB.edl_sources, unlike the main list's
    -- virtual/toggleable calibration (CLB.rec_tc_seconds) — so baking it
    -- in at load time is the only way Compare sees the corrected
    -- positions at all. Otherwise a calibrated .clb compared here would
    -- silently use its pre-calibration Rec TC.
    local calib_count = 0
    for _, row in ipairs(rows) do
      local src = data.sources[row.__source_idx or 0]
      if src and src.tc_calib_enabled and (src.tc_calib_delta_sec or 0) ~= 0 then
        local delta = src.tc_calib_delta_sec
        local ri = EDL.tc_to_seconds(row.rec_tc_in,  fps, is_drop) + delta
        local ro = EDL.tc_to_seconds(row.rec_tc_out, fps, is_drop) + delta
        row.rec_tc_in  = EDL.seconds_to_tc(ri, fps, is_drop)
        row.rec_tc_out = EDL.seconds_to_tc(ro, fps, is_drop)
        calib_count = calib_count + 1
      end
    end
    if calib_count > 0 then
      console_msg(string.format(
        "Compare: applied TC calibration to %d event(s) from %s", calib_count, fname))
    end

  elseif ext == "edl" or ext == "xml" or ext == "aaf" then
    console_msg("Compare: loading " .. fname .. " ...")
    local parsed, err = OTIO.parse(filepath, { default_fps = CLB.fps, python = OTIO.python })
    if not parsed then
      reaper.ShowMessageBox("Failed to load:\n\n" .. tostring(err), SCRIPT_NAME, 0)
      return
    end
    fps = parsed.fps or CLB.fps
    is_drop = parsed.is_drop or false
    rows = _make_rows_from_events(parsed.events, fps, is_drop, 0)

  else
    reaper.ShowMessageBox("Unsupported file type: ." .. ext
      .. "\n\nCompare accepts .edl, .xml, .aaf, or .clb.", SCRIPT_NAME, 0)
    return
  end

  local entry = { name = fname, path = filepath, rows = rows, fps = fps, is_drop = is_drop }
  if side == "old" then CLB.compare_old = entry else CLB.compare_new = entry end
  CLB.compare_result = nil  -- stale after (re)loading either side
  console_msg(string.format("Compare: loaded %s (%s, %d events)", side, fname, #rows))

  if CLB.compare_old and CLB.compare_new then
    CMP.run()
  end
end

--- Poll background OTIO loads (called every frame from main loop).
--- Returns true while still loading, false when done or idle.
local function process_otio_loading()
  if not CLB.loading_state or CLB.loading_state.phase ~= "otio_loading" then
    return false
  end

  local state = CLB.loading_state

  -- Poll the currently-active handle
  local status, result = OTIO.parse_async_poll(state.active_handle)

  if status == "loading" then
    return true  -- still waiting
  end

  -- Done or error for this file
  if status == "done" then
    state.all_parsed[#state.all_parsed + 1] = {
      parsed = result,
      path   = state.filepaths[state.current_idx],
    }
    if result._warning then
      local fname = state.filepaths[state.current_idx]:match("([^/\\]+)$") or ""
      console_msg("Warning [" .. fname .. "]: " .. result._warning)
    end
  else
    -- error
    local fname = state.filepaths[state.current_idx]:match("([^/\\]+)$") or ""
    state.errors[#state.errors + 1] = fname .. ": " .. tostring(result)
  end

  state.current_idx = state.current_idx + 1

  -- Start next file if any remain
  if state.current_idx <= #state.filepaths then
    local fp = state.filepaths[state.current_idx]
    local handle = OTIO.parse_async_start(fp, { default_fps = state.default_fps,
                                                python      = OTIO.python })
    state.active_handle = handle
    return true
  end

  -- All files finished
  CLB.loading_state = nil

  if #state.errors > 0 then
    reaper.ShowMessageBox(
      "Failed to parse " .. #state.errors .. " file(s):\n\n" ..
      table.concat(state.errors, "\n"),
      SCRIPT_NAME, 0)
  end

  -- Remember directory
  if state.filepaths[1] then
    CLB.last_dir = state.filepaths[1]:match("(.*[/\\])") or ""
    save_prefs()
  end

  if #state.all_parsed > 0 then
    local elapsed = string.format("%.1fs", reaper.time_precise() - (state.start_time or 0))
    console_msg(string.format("Done — loaded %d file(s) in %s", #state.all_parsed, elapsed))
  end

  _apply_timeline_results(state.all_parsed, state.filepaths, state.default_fps)

  return false
end

--- Clear all loaded audio files
local function clear_audio_files()
  CLB.audio_files = {}
  CLB.audio_folder = ""
  CLB.audio_cached = nil
  CLB.loading_state = nil
  clear_match_results()
end

---------------------------------------------------------------------------
-- Generate Items
---------------------------------------------------------------------------
--- Map internal format identifier to user-friendly label
local function _friendly_format(fmt)
  if not fmt then return "EDL" end
  local u = fmt:upper()
  if u == "CMX3600" or u == "CLB" then return "EDL" end
  if u:find("XML") then return "XML" end
  if u == "AAF" then return "AAF" end
  if u:find("^SUBTITLE") then return "SUBTITLE" end
  return fmt  -- pass through any unknown formats unchanged
end

--- Expand the track-name template for a row, then clean up dangling
--- separators left behind by empty tokens (e.g. "${format} - ${track}"
--- with track="" → "SUBTITLE - " → "SUBTITLE").
local function _expand_track_name(template, tokens)
  local name = EDL.expand_template(template, tokens) or ""
  -- Trim leading/trailing whitespace + dashes/pipes
  name = name:gsub("^[%s%-|]+", ""):gsub("[%s%-|]+$", "")
  -- Collapse repeated internal separator runs: "  -  -  " → " - "
  name = name:gsub("%s*[%-|]%s*[%-|]+%s*", " - ")
  return name
end

--- Build tokens table from a row for track name expansion
local function build_row_tokens(row)
  return {
    format = _friendly_format(CLB.loaded_format),
    track = row.track or "",
    reel = row.reel or "",
    clip = row.clip_name or "",
    event = row.event_num or "",
    title = (CLB.parsed_data and CLB.parsed_data.title) or "",
    edit_type = row.edit_type or "",
    -- Aliases
    clip_name = row.clip_name or "",
    source_file = row.source_file or "",
  }
end

---------------------------------------------------------------------------
-- Generate Ref Media — real BWF/iXML reference WAVs for conform
---------------------------------------------------------------------------
--- A client reported that an exported picture-cut track carries no
--- Source TC at all, so they can't re-conform the original files
--- themselves — "Generate Items" (above) only ever creates REAPER-
--- internal placeholders (P_EXT fields, no real underlying file), which
--- don't survive export to another tool at all. This generates REAL WAV
--- files with embedded BWF TimeReference + iXML (Scene/Tape/Track name)
--- so any professional tool reading the exported/conformed media sees
--- the correct Source TC, Clip Name (the item/take's own name — that's
--- sequence-level metadata, travels with the edit independent of the
--- file), and a real, meaningful filename.
---
--- Deliberately NOT one WAV per event — user's own reference, from
--- EdiLoad V4's behavior: ONE shared reference WAV per (reel, track)
--- group, long enough to span every event in that group, with its own
--- BWF TimeReference set to the GROUP's own earliest Src TC. Each
--- event becomes a REAPER item referencing that SAME file via
--- D_STARTOFFS (same "many items, one shared PCM source" mechanism
--- CLB.dme_recut_execute's Copy mode already uses) — so a list with a
--- few thousand events but a few dozen reels only ever generates a few
--- dozen real files, not thousands. When opened/conformed in another
--- tool, each item's own Source TC is then just (file's own BWF
--- TimeReference + that item's start-offset into the file) — standard
--- broadcast-wave math every professional NLE/DAW already understands,
--- no per-clip metadata needed at all.
---
--- Grouped by (reel, track), not just reel — different tracks on the
--- same reel are genuinely different audio content (e.g. DME stems:
--- DX/ADR/FX/MU share one embedded timecode baseline but are NOT
--- interchangeable — see CLB.dme_recut's own doc comment for the real
--- bug this caused once already) and must never share one file.
---
--- A separate action from Generate Items, not a replacement or a mode
--- toggle on it (confirmed with the user) — this is much heavier (spawns
--- sox + bwfmetaedit per GROUP, real disk I/O) where Generate Items is
--- instant and file-free; most sessions won't need both every time.

--- Filesystem-safe filename piece — strips path separators and other
--- characters that would break on macOS/Windows either way.
function CLB._sanitize_filename(s)
  s = tostring(s or "")
  s = s:gsub('[/\\:%*%?"<>|]', "_")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then s = "untitled" end
  return s
end

--- Resolves the `sox` executable path (used to synthesize the silent
--- reference WAV itself — bwfmetaedit only edits metadata on a file that
--- already exists, it doesn't create audio data), with the same
--- candidate-list + ExtState-cache-then-verify pattern
--- hsuanice_Metadata Embed.lua's E.CLI_Resolve uses for bwfmetaedit.
function CLB._resolve_sox()
  if not CLB.PX then return nil end
  local EXT_NS, EXT_KEY = "hsuanice_CLB", "SoxPath"

  local function ok_cli(p)
    if not p or p == "" then return false end
    local _, exec_ok = CLB.PX.run_capture(CLB.PX.shell_quote(p) .. " --version")
    return exec_ok == true
  end

  local saved = reaper.GetExtState(EXT_NS, EXT_KEY)
  if saved ~= "" and ok_cli(saved) then return saved end

  local is_win = reaper.GetOS():match("Win")
  local cands = is_win
    and { "sox" }
    or  { "/opt/homebrew/bin/sox", "/usr/local/bin/sox", "sox" }
  for _, p in ipairs(cands) do
    if ok_cli(p) then
      reaper.SetExtState(EXT_NS, EXT_KEY, p, true)
      return p
    end
  end
  return nil
end

--- Synthesizes `duration_sec` of pure silence at the given sample rate/
--- channel count/bit depth via sox. Returns ok, output.
function CLB._generate_silent_wav(sox, path, sr, channels, duration_sec)
  local cmd = string.format("%s -n -r %d -c %d -b 24 %s synth %.6f sine 0 vol 0",
    CLB.PX.shell_quote(sox), sr, channels, CLB.PX.shell_quote(path),
    math.max(duration_sec, 0.05))
  local out, exec_ok = CLB.PX.run_capture(cmd)
  return exec_ok == true, out
end

--- Builds a per-event iXML document — carries the real Scene/Take/Reel
--- for ITS OWN event, since this file is self-contained production
--- metadata, not a throwaway placeholder: the whole point of this
--- feature is that the FILE ITSELF (not a REAPER-only D_STARTOFFS
--- trick) carries the truth. User's explicit requirement after briefly
--- trying a version without this:
--- (this mode must have COMPLETE metadata, including TC —
--- strict).
function CLB._build_ref_ixml_independent(opts)
  local tracks = {}
  for ch = 1, opts.channels do
    tracks[#tracks + 1] = table.concat({
      "    <TRACK>",
      "      <CHANNEL_INDEX>" .. ch .. "</CHANNEL_INDEX>",
      "      <INTERLEAVE_INDEX>" .. ch .. "</INTERLEAVE_INDEX>",
      "      <NAME>CLB_Ref</NAME>",
      "    </TRACK>",
    }, "\n")
  end
  local parts = {
    '<?xml version="1.0" encoding="UTF-8"?>',
    "<BWFXML>",
    "  <IXML_VERSION>1.5</IXML_VERSION>",
    "  <NOTE>Generated by hsuanice Conform List Browser — silent reference media for conform (event #" .. (opts.event_num or "") .. "). Content is never actually played; embedded BWF TimeReference carries this event's real Source TC.</NOTE>",
  }
  if opts.tape and opts.tape ~= "" then parts[#parts+1] = "  <TAPE>" .. opts.tape .. "</TAPE>" end
  if opts.scene and opts.scene ~= "" then parts[#parts+1] = "  <SCENE>" .. opts.scene .. "</SCENE>" end
  if opts.take and opts.take ~= "" then parts[#parts+1] = "  <TAKE>" .. opts.take .. "</TAKE>" end
  parts[#parts+1] = "  <SPEED>"
  parts[#parts+1] = "    <FILE_SAMPLE_RATE>" .. tostring(opts.sr) .. "</FILE_SAMPLE_RATE>"
  parts[#parts+1] = "  </SPEED>"
  parts[#parts+1] = "  <TRACK_LIST>"
  parts[#parts+1] = "    <TRACK_COUNT>" .. tostring(opts.channels) .. "</TRACK_COUNT>"
  parts[#parts+1] = table.concat(tracks, "\n")
  parts[#parts+1] = "  </TRACK_LIST>"
  parts[#parts+1] = "</BWFXML>"
  return table.concat(parts, "\n")
end

--- Shared helper: collect-and-create one REAPER track per expanded track
--- name across `rows` (natural-sorted) — used identically by both
--- Generate Ref Media modes below. Returns row_to_trackname, track_map,
--- track_names_order (for diagnostics/messages).
function CLB._build_track_map_for_rows(rows)
  local track_names_set, track_names_order, row_to_trackname = {}, {}, {}
  for _, row in ipairs(rows) do
    local rtokens = build_row_tokens(row)
    local expanded = _expand_track_name(CLB.track_name_format, rtokens)
    row_to_trackname[row.__guid] = expanded
    if not track_names_set[expanded] then
      track_names_set[expanded] = true
      track_names_order[#track_names_order + 1] = expanded
    end
  end
  table.sort(track_names_order, _natural_sort_cmp)
  local track_map = {}
  for _, name in ipairs(track_names_order) do
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
    track_map[name] = tr
  end
  return row_to_trackname, track_map, track_names_order
end

--- Validates prerequisites, THEN opens the "Generate Reference Media"
--- scope-picker popup (Selected rows vs. the currently visible/filtered
--- list — see CLB.ref_media_scope's own doc comment above). The actual
--- row set depends on that choice, so it isn't computed here — see
--- CLB.generate_reference_media_pick_folder_and_run, which reads
--- CLB.ref_media_scope once the popup's "Next" button is clicked. This
--- function itself stays pure synchronous Lua with no blocking dialog
--- before its OpenPopup call (same shape as CLB.dme_recut_prepare's
--- already-proven-working pattern) — the folder dialog happens later,
--- after the popup closes, for the same reason (see
--- CLB.generate_reference_media_pick_folder_and_run's own comment).
function CLB.generate_reference_media_prepare()
  if CLB.batch_job then
    reaper.ShowMessageBox("Another operation (" .. (CLB.batch_job.label or "batch job") .. ") is still running — wait for it to finish first.", SCRIPT_NAME, 0)
    return
  end
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded. Load an EDL file first.", SCRIPT_NAME, 0)
    return
  end
  if not (CLB.PX and CLB.METAEMBED) then
    reaper.ShowMessageBox(
      "Required library failed to load (hsuanice_Process Exec.lua /\n"
      .. "hsuanice_Metadata Embed.lua) — Generate Ref Media is unavailable.",
      SCRIPT_NAME, 0)
    return
  end
  local sox = CLB._resolve_sox()
  if not sox then
    reaper.ShowMessageBox(
      "Could not find \"sox\" (used to synthesize the reference WAV's\n"
      .. "silent audio). Install it, e.g. via Homebrew: brew install sox",
      SCRIPT_NAME, 0)
    return
  end
  local bwf = CLB.METAEMBED.CLI_Resolve()
  if not bwf then
    reaper.ShowMessageBox("Could not find \"bwfmetaedit\" — Generate Ref Media is unavailable.", SCRIPT_NAME, 0)
    return
  end
  if not reaper.JS_Dialog_BrowseForFolder then
    reaper.ShowMessageBox(
      "JS extension required for folder selection.\n\n"
      .. "Please install js_ReaScriptAPI via ReaPack.",
      SCRIPT_NAME, 0)
    return
  end

  CLB.ref_media_pending = { sox = sox, bwf = bwf }
  reaper.ImGui_OpenPopup(ctx, "Generate Reference Media##clb_genref_popup")
end

--- CLB.generate_reference_media_pick_folder_and_run is defined further
--- down, right after get_selected_rows() — it needs to call that
--- function, which (being a `local function`, not a CLB.* field) can
--- only be referenced by code appearing AFTER its own declaration in
--- this file's source order, regardless of call order at runtime.

--- One real WAV PER EVENT, each with its OWN embedded BWF TimeReference
--- (that event's real Source TC — not fixed/shared) + iXML (Scene/Take/
--- Reel). This is the ONLY generation mode — a "Simple/shared ONE file"
--- mode existed briefly but was removed entirely at the user's request:
--- in the user's own words
--- (just keep the Full version — if Basic is wanted, the plain
--- "Generate Items" empty-item placeholder already covers that; this
--- feature's whole reason to exist is the real embedded metadata).
function CLB.generate_reference_media_independent(pending)
  local usable_rows, folder, sox, bwf, sr = pending.usable_rows, pending.folder, pending.sox, pending.bwf, pending.sr
  local CHANNELS = 1
  local sep = reaper.GetOS():match("Win") and "\\" or "/"

  local tokens = { timestamp = os.date("%y%m%d_%H%M%S") }
  local subfolder_name = CLB._sanitize_filename(EDL.expand_template(CLB.ref_media_name_format, tokens))
  local subfolder = folder .. sep .. subfolder_name .. sep
  reaper.RecursiveCreateDirectory(subfolder, 0)

  local retimed_note = ""
  if pending.retimed_count > 0 then
    retimed_note = string.format(
      "\n\n%d event(s) carry an EDL M2 (speed/reverse) flag — see the\n"
      .. "\"Speed\" column. Their own file's Source TC assumes normal\n"
      .. "speed (flagged in each item's own Notes for manual review).",
      pending.retimed_count)
  end

  local msg = string.format(
    "Generate %d independent reference WAV(s), one per event?\n\n"
    .. "Folder: %s\n"
    .. "Sample rate: %d Hz, mono — each file's own embedded BWF\n"
    .. "TimeReference is that event's real Source TC (not shared/fixed\n"
    .. "at 0), so Source TC survives even a render/export to other\n"
    .. "software. Slower than the shared-file mode; creates %d files.%s",
    #usable_rows, subfolder, sr, #usable_rows, retimed_note)
  if reaper.ShowMessageBox(msg, SCRIPT_NAME, 1) ~= 1 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local row_to_trackname, track_map, track_names_order = CLB._build_track_map_for_rows(usable_rows)
  local fail_count = 0

  CLB.batch_job = {
    label = "Generating independent reference files",
    total = #usable_rows,
    current = 0,
    created = 0,
    batch_size = 10, -- heavier per-step work (real sox + bwfmetaedit x2 per event) than the shared mode
    step = function(job, i)
      local row = usable_rows[i]
      local tr = track_map[row_to_trackname[row.__guid]] or track_map[track_names_order[1]]
      if not tr then return end

      local pos     = CLB.rec_tc_seconds(row.rec_tc_in,  row)
      local pos_out = CLB.rec_tc_seconds(row.rec_tc_out, row)
      local length  = math.max(pos_out - pos, 0.001)
      local src_tc_sec = math.max(CLB.src_tc_seconds(row.src_tc_in, row), 0)
      local tr_samples = CLB.METAEMBED.SecToSamples(sr, src_tc_sec)

      -- "_REF" prefix keeps these unmistakable once bundled alongside
      -- real production files — leading "_" is rare in ordinary
      -- filenames, "REF" spells out why.
      local fname = CLB._sanitize_filename(string.format("_REF%s_%s_%s",
        row.event_num or tostring(i), row.reel or "", row.clip_name or "")) .. ".wav"
      local fpath = subfolder .. fname

      local ok_gen = CLB._generate_silent_wav(sox, fpath, sr, CHANNELS, length)
      if not ok_gen then fail_count = fail_count + 1; return end
      local xml = CLB._build_ref_ixml_independent{
        sr = sr, channels = CHANNELS,
        event_num = row.event_num, tape = row.reel, scene = row.scene, take = row.take,
      }
      -- Same Originator-forcing fix as the shared mode's TR_Write call —
      -- required whenever tr_samples could legitimately be 0 (e.g. a "BL"
      -- blank event's Src TC In is literally 00:00:00:00), not just as a
      -- general precaution — see hsuanice_Metadata Embed.lua's TR_Write
      -- doc comment.
      local ok_tr = CLB.METAEMBED.TR_Write(bwf, fpath, tr_samples, "hsuanice CLB")
      local ok_ix = CLB.METAEMBED.Write_iXML_Raw(bwf, fpath, xml)
      if not (ok_tr and ok_ix) then fail_count = fail_count + 1 end

      local source = reaper.PCM_Source_CreateFromFile(fpath)
      if not source then fail_count = fail_count + 1; return end

      local item = reaper.AddMediaItemToTrack(tr)
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
      reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
      reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0) -- defensive; file is already exactly this item's own length
      local take = reaper.AddTakeToMediaItem(item)
      if take then
        reaper.SetMediaItemTake_Source(take, source)
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", row.clip_name or "", true)
        reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_EVENT", row.event_num or "", true)
        reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_REEL", row.reel or "", true)
        reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_TRACK", row.track or "", true)
        reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_IN", row.src_tc_in or "", true)
        reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_OUT", row.src_tc_out or "", true)
      end

      local note_parts = {}
      note_parts[#note_parts + 1] = "Reel: " .. (row.reel or "")
      if row.scene and row.scene ~= "" then note_parts[#note_parts + 1] = "Scene: " .. row.scene end
      if row.take  and row.take  ~= "" then note_parts[#note_parts + 1] = "Take: "  .. row.take  end
      if row.aux_rate then
        note_parts[#note_parts + 1] = string.format(
          "\xE2\x9A\xA0 Speed: %.1f (EDL M2 — retimed or reverse source; this file's Source TC assumes normal speed)",
          row.aux_rate)
      end
      reaper.GetSetMediaItemInfo_String(item, "P_NOTES", table.concat(note_parts, "\n"), true)

      job.created = job.created + 1
    end,
    finish = function(job)
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()
      reaper.Undo_EndBlock(string.format("CLB: Generate Reference Media (%d independent file(s))", job.created), -1)

      local fail_note = fail_count > 0
        and string.format("\n\n%d event(s) failed to generate (sox/bwfmetaedit error) — check the folder directly.", fail_count)
        or ""
      reaper.ShowMessageBox(string.format(
        "Generate Reference Media done.\n\nFolder:\n%s\n\n%d file(s)/item(s) created.%s",
        subfolder, job.created, fail_note),
        SCRIPT_NAME, 0)
    end,
  }
end

local function generate_items()
  if CLB.batch_job then
    reaper.ShowMessageBox("Another operation (" .. (CLB.batch_job.label or "batch job") .. ") is still running — wait for it to finish first.", SCRIPT_NAME, 0)
    return
  end
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded. Load an EDL file first.", SCRIPT_NAME, 0)
    return
  end

  -- Use filtered rows only
  local visible_rows = get_view_rows() or ROWS

  -- Collect unique track names (based on expanded template)
  local track_names_set = {}
  local track_names_order = {}
  local row_to_trackname = {}  -- row.__guid -> expanded track name

  for _, row in ipairs(visible_rows) do
    local tokens = build_row_tokens(row)
    local expanded_name = _expand_track_name(CLB.track_name_format, tokens)
    row_to_trackname[row.__guid] = expanded_name

    if not track_names_set[expanded_name] then
      track_names_set[expanded_name] = true
      track_names_order[#track_names_order + 1] = expanded_name
    end
  end

  -- Sort track names (natural sort: A1, A2, A10 instead of A1, A10, A2)
  table.sort(track_names_order, _natural_sort_cmp)

  -- Confirmation
  local preview_tracks = {}
  for i = 1, math.min(5, #track_names_order) do
    preview_tracks[i] = track_names_order[i]
  end
  local tracks_preview = table.concat(preview_tracks, ", ")
  if #track_names_order > 5 then
    tracks_preview = tracks_preview .. string.format(" ... (+%d more)", #track_names_order - 5)
  end

  local msg = string.format(
    "Generate %d empty items on %d track(s)?\n\n" ..
    "Tracks: %s\n" ..
    "FPS: %s%s\n\n" ..
    "Items will be placed at absolute timecode positions.",
    #visible_rows, #track_names_order,
    tracks_preview,
    tostring(CLB.fps),
    CLB.is_drop and " (Drop Frame)" or ""
  )
  if reaper.ShowMessageBox(msg, SCRIPT_NAME, 1) ~= 1 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Always create a new track (never reuse an existing track with the same
  -- name) — reusing meant a second Generate Items run landed its items on
  -- top of whatever the first run already placed there, since track names
  -- aren't unique keys for "this run's own content". Matches
  -- conform_matched_items()'s existing behavior (see there).
  local track_map = {}  -- expanded_name -> MediaTrack*

  for _, name in ipairs(track_names_order) do
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    local found = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(found, "P_NAME", name, true)
    track_map[name] = found
  end

  -- Create items — a chunk per frame via the shared batch-job runner (see
  -- CLB.process_batch_job) instead of one giant synchronous loop, so the
  -- progress bar actually redraws and Reaper stays responsive on a large
  -- list. finish() below runs once, after the last row.
  CLB.batch_job = {
    label = "Generating items",
    total = #visible_rows,
    current = 0,
    created = 0,
    batch_size = 40,
    step = function(job, i)
      local row = visible_rows[i]
      local track_name = row_to_trackname[row.__guid]
      local tr = track_map[track_name]
      if not tr then tr = track_map[track_names_order[1]] end
      if not tr then return end

      local pos = CLB.rec_tc_seconds(row.rec_tc_in, row)
      local pos_out = CLB.rec_tc_seconds(row.rec_tc_out, row)
      local length = pos_out - pos
      if length <= 0 then length = 0.001 end  -- minimum length

      local item = reaper.AddMediaItemToTrack(tr)
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
      reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)

      local take = reaper.AddTakeToMediaItem(item)
      if take then
        -- Take name = clip name
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", row.clip_name or "", true)

        -- Item note: Source TC In/Out + Reel/Scene/Take (human-readable)
        local note_parts = {}
        note_parts[#note_parts + 1] = "Reel: " .. (row.reel or "")
        if row.scene and row.scene ~= "" then note_parts[#note_parts + 1] = "Scene: " .. row.scene end
        if row.take  and row.take  ~= "" then note_parts[#note_parts + 1] = "Take: "  .. row.take  end
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

      job.created = job.created + 1
    end,
    finish = function(job)
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()
      reaper.Undo_EndBlock("CLB: Generate " .. job.created .. " conform items", -1)
      reaper.ShowMessageBox(
        string.format("Generated %d empty items on %d track(s).", job.created, #track_names_order),
        SCRIPT_NAME, 0)
    end,
  }
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

--- Called from the Generate Reference Media scope popup's "Next"
--- button: resolves which rows to use (Selected vs. visible/filtered,
--- per CLB.ref_media_scope — needs get_selected_rows just above, hence
--- this function living here rather than next to the rest of Generate
--- Ref Media further up), closes the popup, then asks for the output
--- folder (JS_Dialog_BrowseForFolder — BLOCKING) and runs the
--- generator. The folder dialog deliberately happens here, AFTER the
--- popup has already closed, rather than before opening it — a real bug
--- report: opening an ImGui popup right after a blocking native dialog
--- returns doesn't actually work (confirmed no other OpenPopup in this
--- file is ever preceded by one), so the dialog can't come before any
--- ImGui_OpenPopup call in this flow.
function CLB.generate_reference_media_pick_folder_and_run()
  local pending = CLB.ref_media_pending
  CLB.ref_media_pending = nil
  if not pending then return end

  local source_rows = (CLB.ref_media_scope == "selected")
    and get_selected_rows()
    or (get_view_rows() or ROWS)
  if CLB.ref_media_scope == "selected" and #source_rows == 0 then
    reaper.ShowMessageBox("No rows selected. Select rows in the table first.", SCRIPT_NAME, 0)
    return
  end
  local usable_rows = {}
  for _, row in ipairs(source_rows) do
    if row.src_tc_in and row.src_tc_in ~= ""
       and row.rec_tc_in and row.rec_tc_in ~= "" and row.rec_tc_out and row.rec_tc_out ~= "" then
      usable_rows[#usable_rows + 1] = row
    end
  end
  if #usable_rows == 0 then
    reaper.ShowMessageBox("No events have both Src and Rec TC — nothing to generate.", SCRIPT_NAME, 0)
    return
  end

  local sr = math.floor((reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)) or 0)
  if not sr or sr <= 0 then sr = 48000 end
  local retimed_count = 0
  for _, row in ipairs(usable_rows) do
    if row.aux_rate then retimed_count = retimed_count + 1 end
  end

  local rv, folder = reaper.JS_Dialog_BrowseForFolder(
    "Select Output Folder for Reference Media", CLB.ref_media_folder or "")
  if rv ~= 1 or not folder or folder == "" then return end
  CLB.ref_media_folder = folder
  save_prefs()

  pending.usable_rows = usable_rows
  pending.folder = folder
  pending.sr = sr
  pending.retimed_count = retimed_count
  CLB.generate_reference_media_independent(pending)
end

---------------------------------------------------------------------------
-- Calibrate TC (Anchor)
---------------------------------------------------------------------------

--- Field names + display labels for the two independent calibration axes
--- a source can carry. "rec" ("New") is the original axis — Rec TC as
--- V2/target position, used everywhere outside DME Recut (Generate Items,
--- Conform, Scene Cuts, table display, click-to-jump). "src" ("Old") only
--- means something in DME Recut mode, where Src TC is repurposed as V1's
--- real Reaper timeline position rather than a position inside an audio
--- source file (see CLB.dme_recut).
CLB.TC_CALIB_AXES = {
  rec = { field = "rec_tc_in", enabled = "tc_calib_enabled",  delta = "tc_calib_delta_sec",  note = "tc_calib_note",  label = "New (Rec TC)" },
  src = { field = "src_tc_in", enabled = "src_calib_enabled", delta = "src_calib_delta_sec", note = "src_calib_note", label = "Old (Src TC)" },
}

--- Pick one selected event row + one selected Reaper item that the user
--- has confirmed IS that event's real content, and derive a position-
--- correction delta from the difference between where the item actually
--- sits and where the row's TC (on the given axis) says it should be.
--- Verifies the item's length matches the row's duration within a small
--- tolerance first — a mismatch almost certainly means the wrong item was
--- picked, so this refuses rather than silently computing a bogus delta.
--- Always computed from the RAW (uncalibrated) TC, so re-running this
--- replaces any previous calibration on that axis outright rather than
--- compounding on top of it.
---
--- The calibration is stored on the row's own SOURCE (CLB.edl_sources),
--- not globally — loading several reels/episodes at once, each authored
--- by the editor starting at 0 but placed at its own hour slot on the real
--- session timeline, is the normal case in audio post, and each one needs
--- its own correction. Whichever row you anchor from picks the source.
--- @param axis string|nil  "rec" (default) or "src" — see CLB.TC_CALIB_AXES.
function CLB.calibrate_tc_via_anchor(axis)
  local ax = CLB.TC_CALIB_AXES[axis or "rec"]
  local rows = get_selected_rows()
  if #rows ~= 1 then
    reaper.ShowMessageBox(
      "Select exactly one event row in the table first (click one cell).",
      "Calibrate TC (Anchor)", 0)
    return
  end
  local row = rows[1]

  local src = CLB.edl_sources[row.__source_idx or 0]
  if not src then
    reaper.ShowMessageBox(
      "This row isn't tied to a loaded source — can't calibrate it.",
      "Calibrate TC (Anchor)", 0)
    return
  end

  if reaper.CountSelectedMediaItems(0) ~= 1 then
    reaper.ShowMessageBox(
      "Select exactly one item in Reaper first — the item that IS this\n"
      .. "event's real content.",
      "Calibrate TC (Anchor)", 0)
    return
  end
  local item = reaper.GetSelectedMediaItem(0, 0)

  local fps, is_drop = CLB.fps, CLB.is_drop
  local event_in_tc  = row[ax.field]
  local event_out_tc = axis == "src" and row.src_tc_out or row.rec_tc_out
  local event_in  = EDL.tc_to_seconds(event_in_tc  or "00:00:00:00", fps, is_drop)
  local event_out = EDL.tc_to_seconds(event_out_tc or "00:00:00:00", fps, is_drop)
  local event_len = event_out - event_in

  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  local tol = 1.5 / fps
  if math.abs(item_len - event_len) > tol then
    reaper.ShowMessageBox(string.format(
      "Length mismatch — probably not the same content:\n\n"
      .. "  Event %s length:  %s\n"
      .. "  Item length:       %s\n\n"
      .. "Refusing to calibrate.",
      ax.label,
      EDL.seconds_to_tc(event_len, fps, is_drop),
      EDL.seconds_to_tc(item_len,  fps, is_drop)),
      "Calibrate TC (Anchor)", 0)
    return
  end

  local delta = item_pos - event_in
  local sign  = delta >= 0 and "+" or "-"
  local delta_tc = EDL.seconds_to_tc(math.abs(delta), fps, is_drop)

  local take = reaper.GetActiveTake(item)
  local item_name = take and select(2, reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)) or "(no take)"

  local msg = string.format(
    "Source: %s\n"
    .. "Axis: %s\n\n"
    .. "Anchor pair:\n"
    .. "  Event #%s  (%s %s)\n"
    .. "  Item \"%s\"  (at %s)\n\n"
    .. "Computed correction: %s%s\n\n"
    .. "Enable TC Calibration for this source/axis with this offset?\n"
    .. "The underlying list data is not changed — this can be switched\n"
    .. "off at any time. Other loaded sources, and the other axis, are\n"
    .. "unaffected.",
    src.name or "?", ax.label,
    row.event_num or "?", ax.label, event_in_tc or "",
    item_name, EDL.seconds_to_tc(item_pos, fps, is_drop),
    sign, delta_tc)

  if reaper.ShowMessageBox(msg, "Calibrate TC (Anchor)", 1) ~= 1 then return end

  src[ax.enabled] = true
  src[ax.delta]   = delta
  src[ax.note]    = string.format("Event #%s <-> \"%s\"", row.event_num or "?", item_name)
  CLB.cached_rows = nil

  reaper.ShowMessageBox(string.format(
    "TC Calibration enabled for \"%s\" [%s]: %s%s",
    src.name or "?", ax.label, sign, delta_tc), "Calibrate TC (Anchor)", 0)
end

--- Second "Calibrate TC (Anchor)" entry point: no Reaper item needed at
--- all — pick one selected event row and type the TC (on the given axis)
--- it SHOULD be (e.g. a Universal Counting Leader that's always placed 2
--- seconds before each hour mark: 00:59:58:00, 01:59:58:00, ...), and the
--- delta is derived from the difference between that target and the row's
--- current raw TC on that axis. Accepts "HH:MM:SS:FF" or 8 bare digits
--- "HHMMSSFF" (see CLB.normalize_tc_input). Same per-source storage as
--- CLB.calibrate_tc_via_anchor — whichever row you use picks the source,
--- and re-running either method replaces that source/axis's delta
--- outright.
--- @param axis string|nil  "rec" (default) or "src" — see CLB.TC_CALIB_AXES.
function CLB.calibrate_tc_to_target(target_tc_raw, axis)
  local ax = CLB.TC_CALIB_AXES[axis or "rec"]
  local rows = get_selected_rows()
  if #rows ~= 1 then
    reaper.ShowMessageBox(
      "Select exactly one event row in the table first (click one cell).",
      "Calibrate to Target TC", 0)
    return
  end
  local row = rows[1]

  local src = CLB.edl_sources[row.__source_idx or 0]
  if not src then
    reaper.ShowMessageBox(
      "This row isn't tied to a loaded source — can't calibrate it.",
      "Calibrate to Target TC", 0)
    return
  end

  local target_tc = CLB.normalize_tc_input(target_tc_raw)
  if not EDL.is_valid_tc(target_tc) then
    reaper.ShowMessageBox(
      "Invalid timecode.\nExpected HH:MM:SS:FF, or 8 digits with no colons (e.g. 00595800).",
      "Calibrate to Target TC", 0)
    return
  end

  local fps, is_drop = CLB.fps, CLB.is_drop
  local event_in_tc = row[ax.field]
  local event_in   = EDL.tc_to_seconds(event_in_tc or "00:00:00:00", fps, is_drop)
  local target_sec = EDL.tc_to_seconds(target_tc, fps, is_drop)
  local delta = target_sec - event_in
  local sign  = delta >= 0 and "+" or "-"
  local delta_tc = EDL.seconds_to_tc(math.abs(delta), fps, is_drop)

  local msg = string.format(
    "Source: %s\n"
    .. "Axis: %s\n\n"
    .. "Event #%s  %s %s  ->  %s\n\n"
    .. "Computed correction: %s%s\n\n"
    .. "Enable TC Calibration for this source/axis with this offset?\n"
    .. "Other loaded sources, and the other axis, are unaffected.",
    src.name or "?", ax.label, row.event_num or "?", ax.label, event_in_tc or "", target_tc,
    sign, delta_tc)

  if reaper.ShowMessageBox(msg, "Calibrate to Target TC", 1) ~= 1 then return end

  src[ax.enabled] = true
  src[ax.delta]   = delta
  src[ax.note]    = string.format("Event #%s -> %s", row.event_num or "?", target_tc)
  CLB.cached_rows = nil

  reaper.ShowMessageBox(string.format(
    "TC Calibration enabled for \"%s\" [%s]: %s%s",
    src.name or "?", ax.label, sign, delta_tc), "Calibrate to Target TC", 0)
end

---------------------------------------------------------------------------
-- Conform Matched Items (insert actual audio files)
---------------------------------------------------------------------------
local function conform_matched_items(selected_only)
  if CLB.batch_job then
    reaper.ShowMessageBox("Another operation (" .. (CLB.batch_job.label or "batch job") .. ") is still running — wait for it to finish first.", SCRIPT_NAME, 0)
    return
  end
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
    rows_to_process = get_view_rows() or ROWS  -- Only visible/filtered events
  end

  -- Filter to matched rows only
  local matched_rows = {}
  local found_count = 0
  local multi_count = 0

  for _, row in ipairs(rows_to_process) do
    if row.match_status == "Found" or row.match_status == "Fallback" then
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

  -- Collect unique track names (based on expanded template) — skip rows
  -- that will instead reuse their own linked Reaper item (see
  -- CLB.row_linked_item below), so a linked row never causes an unused
  -- empty track to be created for nothing.
  local track_names_set = {}
  local track_names_order = {}
  local row_to_trackname = {}  -- row.__guid -> expanded track name
  local linked_count = 0

  for _, row in ipairs(matched_rows) do
    if CLB.row_linked_item(row) then
      linked_count = linked_count + 1
    else
      local tokens = build_row_tokens(row)
      local expanded_name = _expand_track_name(CLB.track_name_format, tokens)
      row_to_trackname[row.__guid] = expanded_name

      if not track_names_set[expanded_name] then
        track_names_set[expanded_name] = true
        track_names_order[#track_names_order + 1] = expanded_name
      end
    end
  end

  -- Sort track names (natural sort: A1, A2, A10 instead of A1, A10, A2)
  table.sort(track_names_order, _natural_sort_cmp)

  -- Confirmation
  local preview_tracks = {}
  for i = 1, math.min(5, #track_names_order) do
    preview_tracks[i] = track_names_order[i]
  end
  local tracks_preview = table.concat(preview_tracks, ", ")
  if #track_names_order > 5 then
    tracks_preview = tracks_preview .. string.format(" ... (+%d more)", #track_names_order - 5)
  end

  -- Linked rows — "Load From Reaper" (row.__reaper_item) or "Link Reaper
  -- Items"/Reveal (row.reaper_item_guid), see CLB.row_linked_item — carry
  -- a link to a real item already in the session; conforming those adds the
  -- matched audio as a NEW TAKE on that SAME item instead of creating a
  -- separate item on a separate track, per the user's own request
  -- (in the user's words)
  -- (the matched info should become that original item's own takes, no
  -- need for an extra new track).
  local linked_note = linked_count > 0
    and string.format("\n• %d linked to their own Reaper item (new take added there, no new item/track)", linked_count)
    or ""

  local msg = string.format(
    "Conform %d matched events?\n\n" ..
    "• %d single matches (1 take each)\n" ..
    "• %d multiple matches (multiple takes)%s\n\n" ..
    "Tracks: %s\n" ..
    "FPS: %s%s\n\n" ..
    "Audio files will be inserted at timeline positions.",
    #matched_rows, found_count, multi_count, linked_note,
    tracks_preview,
    tostring(CLB.fps),
    CLB.is_drop and " (Drop Frame)" or ""
  )
  if reaper.ShowMessageBox(msg, SCRIPT_NAME, 1) ~= 1 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Create or find tracks by expanded name
  local track_map = {}  -- expanded_name -> MediaTrack*

  for _, name in ipairs(track_names_order) do
    -- Always create a new track (never reuse existing tracks)
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    local found = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(found, "P_NAME", name, true)
    track_map[name] = found
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

  -- Create items — a chunk per frame via the shared batch-job runner (see
  -- CLB.process_batch_job): each item here also opens a source file
  -- (reaper.PCM_Source_CreateFromFile), which is real disk I/O per row on
  -- top of the item/take API calls generate_items() already has, so this
  -- is typically the slowest of the three — most in need of a progress bar.
  CLB.batch_job = {
    label = "Conforming items",
    total = #matched_rows,
    current = 0,
    created = 0,
    takes_created = 0,
    batch_size = 25,
    step = function(job, i)
      local row = matched_rows[i]

      -- Source offset: src_tc_in - audio's TimeReference
      local src_in_sec = EDL.tc_to_seconds(row.src_tc_in, CLB.fps, CLB.is_drop)

      -- Get audio files to insert
      local audio_files = {}
      if (row.match_status == "Found" or row.match_status == "Fallback") and
         row.matched_path and not row.matched_path:match("^%(") then
        -- Single match: find the audio file entry by path
        for _, af in ipairs(CLB.audio_files) do
          if af.path == row.matched_path then
            audio_files[1] = af
            break
          end
        end
      elseif row.__match_candidates then
        -- Multiple candidates (Multiple or Fallback with multiple results)
        audio_files = row.__match_candidates
      end

      if #audio_files == 0 then
        -- Fallback/Multiple rows lose __match_candidates after .clb reload;
        -- re-run matching to restore them.
        console_msg(string.format(
          "  Skipped row %s (Clip: %s) — match candidates lost. Re-run matching to restore.",
          row.event_num or "?", row.clip_name or ""))
        return
      end

      -- A linked row (Load From Reaper, or Link Reaper Items/Reveal — see
      -- CLB.row_linked_item) already has a real item — add the
      -- matched audio as a new take THERE instead of creating a separate
      -- item on a separate track. Its own position/length are left
      -- untouched (it's already positioned correctly; this only adds a
      -- take, never moves/resizes the item). Falls back to the normal
      -- new-item path if the linked item was deleted since loading.
      local item = CLB.row_linked_item(row)
      local is_linked = item ~= nil
      if not is_linked then
        local track_name = row_to_trackname[row.__guid]
        local tr = track_map[track_name] or track_map[track_names_order[1]]
        if not tr then return end

        -- Timeline position from rec_tc_in
        local pos = CLB.rec_tc_seconds(row.rec_tc_in, row)
        local pos_out = CLB.rec_tc_seconds(row.rec_tc_out, row)
        local length = pos_out - pos
        if length <= 0 then length = 0.001 end

        item = reaper.AddMediaItemToTrack(tr)
        reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
      end

      -- On a linked item, skip any audio file it already has a take of —
      -- several rows can share one linked item (same cut on V1 + NONE, or
      -- A1/A2 matching the same file), and a re-Conform would otherwise
      -- stack the same take again each run.
      local existing_src = {}
      if is_linked then
        for t = 0, reaper.CountTakes(item) - 1 do
          local tk = reaper.GetTake(item, t)
          local src = tk and reaper.GetMediaItemTake_Source(tk)
          local fn = src and reaper.GetMediaSourceFileName(src, "")
          if fn and fn ~= "" then existing_src[fn] = true end
        end
      end

      -- Add takes for each audio file
      for ti, af in ipairs(audio_files) do
        if existing_src[af.path or ""] then
          job.takes_skipped = (job.takes_skipped or 0) + 1
        else
          existing_src[af.path or ""] = true
          -- Calculate source offset for this audio file
          local audio_start = get_audio_start_sec(af)
          local source_offset = src_in_sec - audio_start
          if source_offset < 0 then source_offset = 0 end

          -- Insert media source
          local source = reaper.PCM_Source_CreateFromFile(af.path)
          if source then
            local take = reaper.AddTakeToMediaItem(item)

            if take then
              reaper.SetMediaItemTake_Source(take, source)
              reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", source_offset)

              -- Take name: the MATCHED FILE's own name, always — not the
              -- EDL clip name. Real user report with a screenshot: every
              -- conformed take (including the first/primary match, in
              -- both the normal new-item path and the Load-From-Reaper
              -- linked-item path — they share this exact loop) was
              -- showing the clip name instead, which is already visible
              -- elsewhere (item Notes, P_EXT, the event list itself) and
              -- isn't what you need at a glance on the take itself —
              -- which file actually got matched is.
              local take_name = af.filename or af.basename or row.clip_name or ("Take " .. ti)
              reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)

              -- Store metadata as P_EXT
              reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_EVENT", row.event_num or "", true)
              reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_REEL", row.reel or "", true)
              reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_IN", row.src_tc_in or "", true)
              reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_OUT", row.src_tc_out or "", true)
              reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_MATCHED_FILE", af.path or "", true)

              job.takes_created = job.takes_created + 1
            end
          end
        end -- not already on the linked item
      end

      -- Item note
      local note_parts = {}
      note_parts[#note_parts + 1] = "Reel: " .. (row.reel or "")
      if row.scene and row.scene ~= "" then note_parts[#note_parts + 1] = "Scene: " .. row.scene end
      if row.take  and row.take  ~= "" then note_parts[#note_parts + 1] = "Take: "  .. row.take  end
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

      job.created = job.created + 1
    end,
    finish = function(job)
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()
      reaper.Undo_EndBlock("CLB: Conform " .. job.created .. " items (" .. job.takes_created .. " takes)", -1)
      reaper.ShowMessageBox(
        string.format("Conformed %d items with %d takes on %d track(s).%s",
          job.created, job.takes_created, #track_names_order,
          (linked_count > 0 and string.format("\n(%d added as a new take on their own linked Reaper item.)", linked_count) or "")
          .. ((job.takes_skipped or 0) > 0
            and string.format("\n(%d take(s) skipped — that linked item already had a take of the same file.)", job.takes_skipped) or "")),
        SCRIPT_NAME, 0)
    end,
  }
end

---------------------------------------------------------------------------
-- Keyboard navigation in the event table (↑↓ / Home / End, +Shift)
---------------------------------------------------------------------------
--- Moves the table's selection cursor — user's own request for basic
--- spreadsheet-style keyboard nav. `target` = -1 / +1 (one row), "home"
--- or "end"; `extend` (Shift) grows a range from SEL.anchor instead of
--- moving a single selection. Works on the visible (filtered/sorted) rows
--- and keeps the cursor's column. With Follow Reaper on, the linked
--- Reaper item(s) of the selected rows get selected too and the edit
--- cursor moves to the cursor row's item (linked rows only).
function CLB.table_nav(target, extend)
  local vr = get_view_rows()
  if #vr == 0 then return end
  local cur = CLB.sel_cursor or SEL.anchor
  local idx
  if cur then
    for i, r in ipairs(vr) do
      if r.__guid == cur.guid then idx = i; break end
    end
  end
  local col = (cur and cur.col) or COL.CLIP_NAME
  local new
  if target == "home" then new = 1
  elseif target == "end" then new = #vr
  elseif not idx then new = (target < 0) and #vr or 1
  else new = math.max(1, math.min(#vr, idx + target)) end

  local g = vr[new].__guid
  if extend and SEL.anchor then
    sel_rect(SEL.anchor.guid, SEL.anchor.col, g, col)
  else
    sel_set_single(g, col)
  end
  CLB.sel_cursor = { guid = g, col = col }
  CLB.nav_scroll_to_row = g
  CLB.tl_center_on_guid = g

  if CLB.follow_reaper_sel then CLB.sync_reaper_from_table_sel(vr[new]) end
end

--- Follow Reaper, CLB → Reaper direction — user's own request: whatever
--- rows are selected in CLB (click, Cmd/Shift+click, Cmd+A, arrows, the
--- timeline panel's click/box-select) → their linked items become
--- Reaper's item selection. Leaves Reaper's selection alone when none of
--- the selected rows is linked. `focus_row` (optional, keyboard nav):
--- also move the edit cursor to that row's item.
function CLB.sync_reaper_from_table_sel(focus_row)
  CLB._sel_synced_version = SEL.version
  local items, seen = {}, {}
  for _, r in ipairs(get_selected_rows()) do
    local it = CLB.row_linked_item(r)
    if it and not seen[it] then seen[it] = true; items[#items + 1] = it end
  end
  if #items == 0 then return end
  reaper.SelectAllMediaItems(0, false)
  for _, it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
  local focus_item = focus_row and CLB.row_linked_item(focus_row)
  if focus_item then
    reaper.SetEditCurPos(reaper.GetMediaItemInfo_Value(focus_item, "D_POSITION"), true, false)
  end
  reaper.UpdateArrange()
  CLB._follow_sig = CLB._reaper_sel_sig() -- our own selection: Follow mustn't re-reveal it
end

---------------------------------------------------------------------------
-- Remove Duplicates
---------------------------------------------------------------------------
local function remove_duplicates()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded.", SCRIPT_NAME, 0)
    return
  end

  local fps = CLB.fps or 24
  local tolerance_sec = 5 / fps   -- 5-frame tolerance window

  local function tc_sec(tc_str)
    return EDL.tc_to_seconds(tc_str or "00:00:00:00", fps, CLB.is_drop) or 0
  end

  -- Only scan/remove within the currently-filtered (visible) event list —
  -- rows hidden by the Track/Reel/Group/search filters are left untouched,
  -- so e.g. "only remove dups within Audio" works by hiding other groups
  -- first. The final apply step below still rebuilds from the full ROWS,
  -- so hidden rows are always preserved regardless.
  local visible_rows = get_view_rows() or ROWS

  -- Debug log file
  local debug_lines = {}
  local debug_path  = script_path .. "../Tools/clb_dedup_debug.txt"
  local function dlog(s) debug_lines[#debug_lines + 1] = s end
  dlog(string.format("=== CLB Remove Duplicates Debug ==="))
  dlog(string.format("FPS: %s%s  NEAR_SRC_TOL: 5 frames  Events scanned: %d (of %d total)",
    tostring(fps), CLB.is_drop and " DF" or " NDF", #visible_rows, #ROWS))
  dlog("")

  -- Pass 1: exact duplicates (reel + src TC in/out + rec TC in/out + clip_name)
  local seen_exact = {}
  local exact_remove = {}  -- set of __guid
  local seen_exact_row = {}  -- key → first row (for log)
  for _, row in ipairs(visible_rows) do
    local key = table.concat({
      row.reel or "", row.src_tc_in or "", row.src_tc_out or "",
      row.rec_tc_in or "", row.rec_tc_out or "", row.clip_name or "",
    }, "|")
    if seen_exact[key] then
      exact_remove[row.__guid] = true
      local orig = seen_exact_row[key]
      dlog(string.format("[EXACT DUP] REMOVE  Evt#%s  Reel=%s  Clip=%s  SrcIn=%s  RecIn=%s  RecOut=%s",
        row.event_num or "?", row.reel or "?", row.clip_name or "?",
        row.src_tc_in or "?", row.rec_tc_in or "?", row.rec_tc_out or "?"))
      dlog(string.format("            KEPT    Evt#%s  (first occurrence)",
        orig and (orig.event_num or "?") or "?"))
    else
      seen_exact[key] = true
      seen_exact_row[key] = row
    end
  end

  -- Pass 2: overlap-based healing
  --
  -- "Healing" concept: events from the same source placed at overlapping timeline
  -- positions are merged or de-duplicated:
  --   • Containment: one rec range fully contains the other → remove the inner one
  --   • Partial overlap: rec ranges partially overlap → merge into one event spanning
  --     the full range (TC values updated), like a gap-healing operation
  --
  -- Overlap guard: src_in values must also be within 5 frames of each other to confirm
  -- the events share the same sync position (prevents merging sequential clips from the
  -- same source that happen to share a clip_name and touch/overlap slightly in TC).

  local NEAR_SRC_TOL = 5 / fps  -- 5-frame src_in proximity guard

  -- Simple NDF seconds → TC string (used when patching merged TC values)
  local int_fps = math.floor(fps + 0.5)
  local function sec_to_tc(sec)
    local tf = math.max(0, math.floor(sec * fps + 0.5))
    local f  = tf % int_fps
    local ts = math.floor(tf / int_fps)
    return string.format("%02d:%02d:%02d:%02d",
      math.floor(ts / 3600), math.floor(ts / 60) % 60, ts % 60, f)
  end

  local near_remove  = {}
  local contain_count = 0
  local merge_count   = 0

  local groups = {}
  local group_order = {}
  for _, row in ipairs(visible_rows) do
    if exact_remove[row.__guid] then goto next_pass2 end
    local key = (row.reel or "") .. "|" .. (row.clip_name or "")
    if not groups[key] then
      groups[key] = {}
      group_order[#group_order + 1] = key
    end
    local src_in  = tc_sec(row.src_tc_in)
    local src_out = tc_sec(row.src_tc_out)
    local rec_in  = tc_sec(row.rec_tc_in)
    local rec_out = tc_sec(row.rec_tc_out)
    groups[key][#groups[key] + 1] = {
      row     = row,
      src_in  = src_in,
      src_out = src_out,
      rec_in  = rec_in,
      rec_out = rec_out,
    }
    ::next_pass2::
  end

  for _, key in ipairs(group_order) do
    local entries = groups[key]
    if #entries < 2 then goto next_group end

    -- Sort by rec_in ascending; tiebreak: wider rec range first
    table.sort(entries, function(a, b)
      if a.rec_in ~= b.rec_in then return a.rec_in < b.rec_in end
      return a.rec_out > b.rec_out
    end)

    -- Step 1: Containment removal — NO src_in check required
    -- If A.rec_in ≤ B.rec_in AND A.rec_out ≥ B.rec_out → A contains B → remove B.
    -- This correctly handles transition events (wipe/dissolve) whose src_in may differ
    -- more than NEAR_SRC_TOL from the corresponding cut event, but whose rec TC range
    -- fully contains the cut event.
    dlog(string.format("\n[GROUP] Reel+Clip = %s  (%d entries)", key, #entries))
    for _, e in ipairs(entries) do
      dlog(string.format("  Evt#%-4s  SrcIn=%-12s  RecIn=%-12s  RecOut=%-12s  SrcIn_sec=%.3f",
        e.row.event_num or "?", e.row.src_tc_in or "?",
        e.row.rec_tc_in or "?", e.row.rec_tc_out or "?", e.src_in))
    end

    -- Pre-compute sync offsets for containment check
    for _, e in ipairs(entries) do
      e.sync_off = e.rec_in - e.src_in
    end

    local contained = {}
    for i = 1, #entries do
      if not contained[i] then
        for j = i + 1, #entries do
          if not contained[j] then
            -- Sync offsets must match within NEAR_SRC_TOL: confirms same source content
            -- at the same timeline position (rules out same clip_name reused elsewhere)
            local sync_ok = math.abs(entries[i].sync_off - entries[j].sync_off) <= NEAR_SRC_TOL
            if not sync_ok then
              dlog(string.format("  [SKIP]    Evt#%s vs Evt#%s  sync_off diff=%.3fs (%.1f frames) — different source position",
                entries[i].row.event_num or "?", entries[j].row.event_num or "?",
                math.abs(entries[i].sync_off - entries[j].sync_off),
                math.abs(entries[i].sync_off - entries[j].sync_off) * fps))
            elseif entries[i].rec_in  <= entries[j].rec_in and
                   entries[i].rec_out >= entries[j].rec_out then
              contained[j] = true
              contain_count = contain_count + 1
              near_remove[entries[j].row.__guid] = true
              dlog(string.format("  [CONTAIN] REMOVE Evt#%s (RecIn=%s RecOut=%s) contained by Evt#%s (RecIn=%s RecOut=%s)",
                entries[j].row.event_num or "?", entries[j].row.rec_tc_in or "?", entries[j].row.rec_tc_out or "?",
                entries[i].row.event_num or "?", entries[i].row.rec_tc_in or "?", entries[i].row.rec_tc_out or "?"))
            elseif entries[j].rec_in  <= entries[i].rec_in and
                   entries[j].rec_out >= entries[i].rec_out then
              contained[i] = true
              contain_count = contain_count + 1
              near_remove[entries[i].row.__guid] = true
              dlog(string.format("  [CONTAIN] REMOVE Evt#%s (RecIn=%s RecOut=%s) contained by Evt#%s (RecIn=%s RecOut=%s)",
                entries[i].row.event_num or "?", entries[i].row.rec_tc_in or "?", entries[i].row.rec_tc_out or "?",
                entries[j].row.event_num or "?", entries[j].row.rec_tc_in or "?", entries[j].row.rec_tc_out or "?"))
            end
          end
        end
      end
    end

    -- Step 2: Partial overlap merge — src_in proximity check required
    -- Among non-contained entries, find pairs with partial rec TC overlap AND
    -- src_in within NEAR_SRC_TOL → merge into one event (TC values updated).
    local remaining = {}
    for i, e in ipairs(entries) do
      if not contained[i] then remaining[#remaining + 1] = e end
    end
    if #remaining < 2 then goto next_group end

    local merge_groups = {}
    local cur         = { remaining[1] }
    local cur_rec_out = remaining[1].rec_out

    for i = 2, #remaining do
      local e = remaining[i]
      local overlaps  = e.rec_in < cur_rec_out  -- strictly less: partial overlap only
      local src_close = false
      if overlaps then
        for _, ce in ipairs(cur) do
          if math.abs(e.src_in - ce.src_in) <= NEAR_SRC_TOL then
            src_close = true; break
          end
        end
      end
      if overlaps and src_close then
        cur[#cur + 1] = e
        if e.rec_out > cur_rec_out then cur_rec_out = e.rec_out end
      else
        merge_groups[#merge_groups + 1] = cur
        cur         = { e }
        cur_rec_out = e.rec_out
      end
    end
    merge_groups[#merge_groups + 1] = cur

    for _, grp in ipairs(merge_groups) do
      if #grp < 2 then goto next_grp end

      local merged_rec_in  = grp[1].rec_in
      local merged_rec_out = grp[1].rec_out
      for k = 2, #grp do
        if grp[k].rec_out > merged_rec_out then merged_rec_out = grp[k].rec_out end
      end

      local sync_off = grp[1].rec_in - grp[1].src_in
      local new_rec_in_tc  = sec_to_tc(merged_rec_in)
      local new_rec_out_tc = sec_to_tc(merged_rec_out)
      local new_src_in_tc  = sec_to_tc(merged_rec_in  - sync_off)
      local new_src_out_tc = sec_to_tc(merged_rec_out - sync_off)
      dlog(string.format("  [MERGE]   KEEP  Evt#%s  old RecIn=%s RecOut=%s → new RecIn=%s RecOut=%s",
        grp[1].row.event_num or "?",
        grp[1].row.rec_tc_in or "?", grp[1].row.rec_tc_out or "?",
        new_rec_in_tc, new_rec_out_tc))
      grp[1].row.rec_tc_in  = new_rec_in_tc
      grp[1].row.rec_tc_out = new_rec_out_tc
      grp[1].row.src_tc_in  = new_src_in_tc
      grp[1].row.src_tc_out = new_src_out_tc
      merge_count = merge_count + 1

      for k = 2, #grp do
        near_remove[grp[k].row.__guid] = true
        dlog(string.format("  [MERGE]   REMOVE Evt#%s  RecIn=%s RecOut=%s",
          grp[k].row.event_num or "?",
          grp[k].row.rec_tc_in or "?", grp[k].row.rec_tc_out or "?"))
      end

      ::next_grp::
    end
    ::next_group::
  end

  -- Pass 3: Consecutive split healing
  -- If event A's rec_out == event B's rec_in AND src_out_A == src_in_B (within 1 frame),
  -- the two events are a split of the same continuous clip → merge into one.
  -- Handles chains of 3+ consecutive splits as well.
  local SPLIT_TOL = 0.5 / fps  -- must be exactly consecutive (0-frame tolerance; 0.5/fps handles float rounding only)
  local split_remove     = {}
  local split_heal_count = 0  -- number of chains healed (not events removed)

  for _, key in ipairs(group_order) do
    local entries = groups[key]
    if #entries < 2 then goto next_heal_group end

    -- Build list of entries not already flagged for removal
    local live = {}
    for _, e in ipairs(entries) do
      if not near_remove[e.row.__guid] and not exact_remove[e.row.__guid] then
        live[#live + 1] = e
      end
    end
    if #live < 2 then goto next_heal_group end

    -- Sort by rec_in ascending
    table.sort(live, function(a, b) return a.rec_in < b.rec_in end)

    -- Greedy chain merge: walk forward, extend chain while TC boundaries touch
    local function flush_chain(chain)
      if #chain < 2 then return end
      local merged_rec_out = chain[#chain].rec_out
      local merged_src_out = chain[#chain].src_out
      dlog(string.format("  [HEAL]    MERGE chain of %d  starting Evt#%s  RecIn=%s → RecOut=%s  SrcIn=%s → SrcOut=%s",
        #chain, chain[1].row.event_num or "?",
        chain[1].row.rec_tc_in or "?", sec_to_tc(merged_rec_out),
        chain[1].row.src_tc_in or "?", sec_to_tc(merged_src_out)))
      chain[1].row.rec_tc_out = sec_to_tc(merged_rec_out)
      chain[1].row.src_tc_out = sec_to_tc(merged_src_out)
      chain[1].rec_out = merged_rec_out
      chain[1].src_out = merged_src_out
      split_heal_count = split_heal_count + 1
      for k = 2, #chain do
        split_remove[chain[k].row.__guid] = true
        dlog(string.format("  [HEAL]    REMOVE Evt#%s  RecIn=%s RecOut=%s",
          chain[k].row.event_num or "?",
          chain[k].row.rec_tc_in or "?", chain[k].row.rec_tc_out or "?"))
      end
    end

    local chain = { live[1] }
    for i = 2, #live do
      local prev = chain[#chain]
      local curr = live[i]
      local rec_cont = math.abs(prev.rec_out - curr.rec_in) <= SPLIT_TOL
      local src_cont = math.abs(prev.src_out - curr.src_in) <= SPLIT_TOL
      if rec_cont and src_cont then
        chain[#chain + 1] = curr
      else
        flush_chain(chain)
        chain = { curr }
      end
    end
    flush_chain(chain)

    ::next_heal_group::
  end

  local near_count  = 0
  for _ in pairs(near_remove) do near_count = near_count + 1 end
  local split_count = 0
  for _ in pairs(split_remove) do split_count = split_count + 1 end

  local exact_count = 0
  for _ in pairs(exact_remove) do exact_count = exact_count + 1 end
  local total = exact_count + near_count + split_count

  if total == 0 then
    reaper.ShowMessageBox("No duplicate events found.", SCRIPT_NAME, 0)
    return
  end

  -- Confirm
  local choice = reaper.ShowMessageBox(
    string.format(
      "Found %d event(s) to remove/merge out of %d total:\n\n" ..
      "  - %d exact duplicates\n" ..
      "  - %d contained (inner event fully covered by another — removed)\n" ..
      "  - %d merged (partial overlap — TC extended to cover both ranges)\n" ..
      "  - %d healed (%d split clips joined into continuous events)\n\n" ..
      "Remove / merge / heal?",
      total, #visible_rows, exact_count, contain_count, merge_count, split_count, split_heal_count),
    SCRIPT_NAME, 1)

  if choice ~= 1 then return end

  local to_remove = {}
  for g in pairs(exact_remove)  do to_remove[g] = true end
  for g in pairs(near_remove)   do to_remove[g] = true end
  for g in pairs(split_remove)  do to_remove[g] = true end

  local keep = {}
  for _, row in ipairs(ROWS) do
    if not to_remove[row.__guid] then keep[#keep + 1] = row end
  end
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
  _rebuild_reel_filters()
  _rebuild_group_filters()
  undo_snapshot()
  CLB.cached_rows = nil

  local summary = string.format(
    "Removed/merged %d events (%d exact, %d near-dup/overlap, %d split-healed); %d remaining",
    total, exact_count, near_count, split_count, #ROWS)
  console_msg(summary)

  -- Write debug log
  dlog("")
  dlog("=== SUMMARY ===")
  dlog(summary)
  local f = io.open(debug_path, "w")
  if f then
    f:write(table.concat(debug_lines, "\n"))
    f:write("\n")
    f:close()
    console_msg("[CLB] Debug log written: " .. debug_path)
  else
    console_msg("[CLB] Warning: could not write debug log to " .. debug_path)
  end

  reaper.ShowMessageBox(
    string.format("Removed/merged %d event(s) (%d exact, %d overlap, %d split-healed).\n%d events remaining.\n\nDebug log: Tools/clb_dedup_debug.txt",
      total, exact_count, near_count, split_count, #ROWS),
    SCRIPT_NAME, 0)
end

---------------------------------------------------------------------------
-- Consolidate Tracks by Group
---------------------------------------------------------------------------
local function consolidate_by_group()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded.", SCRIPT_NAME, 0)
    return
  end

  -- Only consolidate within the currently-filtered (visible) event list —
  -- rows hidden by the Track/Reel/Group/search filters keep their existing
  -- track assignment untouched (e.g. hide everything but Audio first to
  -- consolidate just that group).
  local visible_rows = get_view_rows() or ROWS

  -- Collect groups with events
  local groups = {}   -- { group_name = { events } }
  local group_order = {}
  for _, row in ipairs(visible_rows) do
    local g = row.group or ""
    if not groups[g] then
      groups[g] = {}
      group_order[#group_order + 1] = g
    end
    local ri_sec = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
    local ro_sec = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
    groups[g][#groups[g] + 1] = { row = row, start = ri_sec, stop = ro_sec }
  end

  -- Preview
  local preview = {}
  for _, g in ipairs(group_order) do
    local display = g ~= "" and g or "(Unassigned)"
    preview[#preview + 1] = string.format("  %s: %d events", display, #groups[g])
  end
  local msg = string.format(
    "Consolidate tracks by group?\n\n" ..
    "%s\n\n" ..
    "Events in each group will be bin-packed into minimal\n" ..
    "non-overlapping tracks. Naming rules:\n" ..
    "  Audio → A1, A2, A3 ...\n" ..
    "  Video → V1, V2, V3 ...\n" ..
    "  Others → GroupName 1, GroupName 2, ...\n" ..
    "Each group's track numbers restart from 1.",
    table.concat(preview, "\n"))
  if reaper.ShowMessageBox(msg, SCRIPT_NAME, 1) ~= 1 then return end

  -- Determine track prefix for a group name:
  --   Audio → "A"  (no space before number)
  --   Video → "V"  (no space before number)
  --   others → "GroupName " (with trailing space before number)
  local function _group_prefix(g)
    if g == "" then return "Unassigned " end
    local up = g:upper()
    if up == "AUDIO" then return "A" end
    if up == "VIDEO" then return "V" end
    return g .. " "
  end

  -- Bin-pack each group; each group gets its OWN track counter starting at 1
  for _, g in ipairs(group_order) do
    local evts = groups[g]
    local prefix = _group_prefix(g)

    -- Sort by start time
    table.sort(evts, function(a, b) return a.start < b.start end)

    -- Bin-packing
    local track_ends = {}
    for _, evt in ipairs(evts) do
      local assigned = nil
      for ti, te in ipairs(track_ends) do
        if evt.start >= te then
          track_ends[ti] = evt.stop
          assigned = ti
          break
        end
      end
      if not assigned then
        track_ends[#track_ends + 1] = evt.stop
        assigned = #track_ends
      end
      evt.row.track = prefix .. tostring(assigned)
    end
  end

  _rebuild_track_filters()
  _rebuild_group_filters()
  CLB.cached_rows = nil
  undo_snapshot()

  console_msg(string.format("Consolidated tracks across %d group(s)", #group_order))
end

---------------------------------------------------------------------------
-- Create Scene Cut Track
---------------------------------------------------------------------------
local function create_scene_cut_track()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded. Load an EDL file first.", SCRIPT_NAME, 0)
    return
  end

  -- Confirm frame rate before generating items
  if not confirm_fps() then return end

  local fps     = CLB.fps     or 24
  local is_drop = CLB.is_drop or false

  -- Scene ID for "Scene Cuts" purposes: prefer row.scene when it's set —
  -- it's the authoritative, already-resolved value (either originally
  -- parsed, or backfilled by Match All's audio-inference — see
  -- match_audio_files), and can't be reliably re-derived by blindly
  -- grabbing clip_name's first token (many clip names, e.g. filler/
  -- "Empty" items, start with alnum text that isn't a scene at all — an
  -- earlier version of this preferred clip_name whenever it was merely
  -- non-empty, which meant an inferred row.scene was never actually used
  -- here even though it existed). Either way, only the FIRST token is
  -- kept — e.g. "06" out of "06_01_T03_A - Merged", or "P1" out of a
  -- row.scene of "P1-1" — this deliberately does NOT reuse
  -- SCENE_TAKE_PARSERS (which keeps the fuller "06_01"/"P1-1" for
  -- Strategy 6's audio Scene+Take matching, where dropping the shot
  -- number would risk matching audio to the wrong shot within a scene):
  -- for episodic naming, the shot/take number after the scene number is
  -- not itself a scene boundary, so shots "06_01"/"06_02"/"06_03" (or
  -- "P1-1"/"P1-WT") all merge into one Scene Cuts segment. _norm_scene_
  -- token also strips leading zeros, so "4" and "04" are recognised as
  -- the same scene. Rows are already filtered to Video tracks only below.
  --
  -- Falls back to clip_name's first token when row.scene is empty ONLY IF
  -- no Video row anywhere in the list has row.scene populated at all
  -- (any_scene_populated below) — i.e. Match All hasn't been run this
  -- session, or the source has no Scene column, so clip-name is the only
  -- signal available. Once Match All HAS run (any_scene_populated true),
  -- an empty row.scene is Match All's own confirmed "no scene here" (it
  -- tried and found none from overlapping audio) — a real bug this
  -- guards against: a "Universal Counting Leader" or raw camera-roll dump
  -- clip like "DVA001_070_260414.MTS" (genuinely not a scene) had its
  -- filename's first token guessed as a fake scene ("Universal",
  -- "DVA001"), which then overlapped real Scene Cuts items on the shared
  -- output track since the fake "scene" occupied the same time range.
  local any_scene_populated = false
  for _, row in ipairs(ROWS) do
    if _get_track_group(row.track) == "Video" and row.scene and row.scene ~= "" then
      any_scene_populated = true
      break
    end
  end

  local function get_scene_id(row)
    local raw
    if row.scene and row.scene ~= "" then
      raw = row.scene:match("^([%w]+)")
    elseif not any_scene_populated and row.clip_name and row.clip_name ~= "" then
      raw = row.clip_name:match("^([%w]+)")
    end
    return raw and _norm_scene_token(raw) or nil
  end

  -- Collect every Video-row occurrence of each scene, from ALL video
  -- tracks — not just walked in row order on one track at a time. Walking
  -- rows sequentially (an earlier approach) only ever detected picture
  -- CUTS (every row-to-row change), not real scene continuity: a second
  -- video track (B-roll/insert coverage) carrying the same scene number
  -- over an overlapping time range produced its own separate, shorter
  -- same-scene item that visually overlapped the main one instead of
  -- being recognised as the same continuous scene.
  --
  -- No duration-based filtering here (a fixed cutoff was tried and
  -- reverted — some real long-take cinema shots legitimately run 10+
  -- minutes, so any hard duration limit risks silently discarding
  -- genuine footage, which is worse than the overlap it would prevent;
  -- see the cross-scene overlap detection after merging below instead).
  local by_scene = {}      -- scene_id -> { {rec_in, rec_out}, ... }
  local scene_order = {}   -- first-seen order, for stable iteration
  for _, row in ipairs(ROWS) do
    if _get_track_group(row.track) == "Video" then
      local scene_id = get_scene_id(row)
      if scene_id then
        -- These become the real item's D_POSITION/D_LENGTH below — apply
        -- "Calibrate TC (Anchor)" here, same as Generate Items/Conform.
        local rec_in  = CLB.rec_tc_seconds(row.rec_tc_in, row)
        local rec_out = CLB.rec_tc_seconds(row.rec_tc_out, row)
        if not by_scene[scene_id] then
          by_scene[scene_id] = {}
          scene_order[#scene_order + 1] = scene_id
        end
        local list = by_scene[scene_id]
        list[#list + 1] = { rec_in = rec_in, rec_out = rec_out }
      end
    end
  end

  -- Merge each scene's own intervals: overlapping or touching (within a
  -- small tolerance, to bridge a 1-2 frame gap at a cut/transition) runs
  -- become one continuous Scene Cuts item; a scene number that recurs much
  -- later with a real gap in between still becomes its own separate item.
  local GAP_TOL = 2 / fps
  local scene_items = {}
  for _, scene_id in ipairs(scene_order) do
    local list = by_scene[scene_id]
    table.sort(list, function(a, b) return a.rec_in < b.rec_in end)
    local run_in, run_out = list[1].rec_in, list[1].rec_out
    for i = 2, #list do
      local iv = list[i]
      if iv.rec_in <= run_out + GAP_TOL then
        if iv.rec_out > run_out then run_out = iv.rec_out end
      else
        scene_items[#scene_items + 1] = { scene_id = scene_id, rec_in = run_in, rec_out = run_out }
        run_in, run_out = iv.rec_in, iv.rec_out
      end
    end
    scene_items[#scene_items + 1] = { scene_id = scene_id, rec_in = run_in, rec_out = run_out }
  end
  table.sort(scene_items, function(a, b) return a.rec_in < b.rec_in end)

  if #scene_items == 0 then
    reaper.ShowMessageBox(
      "No scene events found on Video track(s).\n\n" ..
      "Scene is read as the first token of the clip name, or of row Scene\n" ..
      "(e.g. \"06\" in \"06_01_T03_A - Merged\", or \"P1\" in \"P1-1\").",
      SCRIPT_NAME, 0)
    return
  end

  -- Detect cross-scene overlaps: two DIFFERENT scenes whose merged ranges
  -- overlap in time. This can happen for reasons Scene Cuts can't reliably
  -- tell apart on its own — e.g. a genuine long-take scene vs. an
  -- un-flattened reference/pic-lock clip sharing the same time range on a
  -- separate video track. A fixed duration cutoff to guess which is which
  -- was tried and reverted: real long-take cinema shots can legitimately
  -- run 10+ minutes, so any hard limit risks silently discarding real
  -- footage — worse than the overlap itself. Instead this just surfaces
  -- exactly which scenes overlap (still creating all the items) so the
  -- user can resolve it directly in Reaper with full editorial judgement.
  --
  -- Grouped by the WIDE item causing each cluster of overlaps, not listed
  -- pairwise — the real-world shape of this problem is one long item
  -- (e.g. a whole-reel reference clip) overlapping every real scene in
  -- its range, which would otherwise mean one dialog line per real scene
  -- (confirmed: 154 pairwise lines from just 4 actual culprit clips on a
  -- real 4-reel session). One summary line per culprit stays readable
  -- regardless of how many scenes it happens to span.
  local function tc(sec) return EDL.seconds_to_tc(sec, fps, is_drop) end
  local overlap_lines = {}
  do
    local groups, group_order = {}, {}
    local active_end, active_item = nil, nil
    for _, item in ipairs(scene_items) do
      if active_end and item.rec_in < active_end - GAP_TOL then
        local g = groups[active_item]
        if not g then
          g = { item = active_item, count = 0, sample_ids = {} }
          groups[active_item] = g
          group_order[#group_order + 1] = g
        end
        g.count = g.count + 1
        if #g.sample_ids < 5 then g.sample_ids[#g.sample_ids + 1] = item.scene_id end
        -- Only the wide culprit item is flagged red, not every narrower
        -- item it happens to overlap — in the real case (a whole-reel
        -- reference clip), that's every scene in the reel, and painting
        -- all of them red would bury the one item that actually needs
        -- attention instead of pointing straight at it.
        active_item.__overlap = true
      end
      if not active_end or item.rec_out > active_end then
        active_end = item.rec_out
        active_item = item
      end
    end
    for _, g in ipairs(group_order) do
      local sample = table.concat(g.sample_ids, ", ")
      if g.count > #g.sample_ids then sample = sample .. ", ..." end
      overlap_lines[#overlap_lines + 1] = string.format(
        "  Scene %s (%s–%s) overlaps %d other scene(s): %s",
        g.item.scene_id, tc(g.item.rec_in), tc(g.item.rec_out), g.count, sample)
    end
  end
  local overlap_warning = ""
  if #overlap_lines > 0 then
    overlap_warning = string.format(
      "\n\n⚠ %d overlap cluster(s) detected — Scene Cuts can't automatically\n" ..
      "tell these apart (e.g. a genuine long take vs. an un-flattened\n" ..
      "reference clip). Items will still be created; please review and\n" ..
      "fix manually in Reaper:\n%s",
      #overlap_lines, table.concat(overlap_lines, "\n"))
  end

  -- Confirmation
  local preview = {}
  for i = 1, math.min(6, #scene_items) do preview[i] = scene_items[i].scene_id end
  local msg = string.format(
    "Create Scene Cut Track?\n\n%d scene items will be created.\nOrder: %s%s\n\n" ..
    "A new 'Scene Cuts' track will be added to the project.%s",
    #scene_items,
    table.concat(preview, " → "),
    #scene_items > 6 and string.format(" ... (+%d more)", #scene_items - 6) or "",
    overlap_warning
  )
  if reaper.ShowMessageBox(msg, SCRIPT_NAME, 1) ~= 1 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  -- Create track
  reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
  local tr = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "Scene Cuts", true)

  -- Create one empty item per scene segment. Items flagged by the overlap
  -- sweep above are colored/labeled so the conflict is visible directly on
  -- the timeline, not just in the dialog text — same red used for the
  -- other "needs manual attention" cases in this script (CMP.TYPE_COLOR.Deleted).
  local OVERLAP_COLOR = reaper.ColorToNative(200, 60, 60) | 0x1000000
  for _, si in ipairs(scene_items) do
    local length = si.rec_out - si.rec_in
    if length <= 0 then length = 0.001 end

    local item = reaper.AddMediaItemToTrack(tr)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", si.rec_in)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", length)
    if si.__overlap then
      reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", OVERLAP_COLOR)
    end

    local take = reaper.AddTakeToMediaItem(item)
    if take then
      local take_name = si.__overlap and (si.scene_id .. " ⚠ overlap") or si.scene_id
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("CLB: Create Scene Cut Track (" .. #scene_items .. " scenes)", -1)

  local done_msg = string.format("Created 'Scene Cuts' track with %d scene items.", #scene_items)
  if #overlap_lines > 0 then
    done_msg = done_msg .. string.format(
      "\n\n⚠ %d overlap cluster(s) — the affected items are colored red on\n" ..
      "the track and take-name-suffixed \" ⚠ overlap\" (details were listed\n" ..
      "in the confirmation dialog). Review and fix manually.", #overlap_lines)
  end
  reaper.ShowMessageBox(done_msg, SCRIPT_NAME, 0)
end

---------------------------------------------------------------------------
-- DME Recut
---------------------------------------------------------------------------
--- Recut real items on Reaper-selected track(s) using the currently
--- loaded/filtered list directly — no Compare needed. Built for DME-stem
--- cut lists: when an editor cuts a V2 edit from V1's printed-to-pitch DME
--- stems (DX/ADR/FX/MU) and exports an EDL, each event's Src TC is already
--- V1's real timeline position (not a position inside an audio source
--- file — a different sense of "Src TC" than the rest of CLB uses) and
--- Rec TC is V2's target position. Per CMX3600 format rules a plain cut
--- event always has equal Src and Rec duration (a real trim/extend shows
--- up as separate adjacent events, never as one event with mismatched
--- durations — that only happens when comparing Src TC across TWO
--- different EDLs, which is what CMP.compare's Trimmed/Extended
--- classification is for), so this is a pure range-based reposition: the
--- content occupying an event's Src TC range on the selected track(s)
--- lands at that event's Rec TC range. No identity/content matching —
--- same spirit as Compare's Apply's Range Clear strategy, it only cares
--- what's physically in the range.
---
--- Copy vs Cut is a user choice (CLB.dme_recut_mode, set in the Settings
--- popup this opens — see the draw-side "DME Recut Settings" popup block):
--- "copy" leaves V1's real content at its Src TC position completely
--- untouched (same "keep the old pristine" principle CMP.offset_selected_
--- tracks already follows) — a brand new item is created at the Rec TC
--- position, its take pointing at the SAME underlying source media (safe,
--- standard REAPER practice; many items can reference one source) with
--- D_STARTOFFS adjusted so it plays the exact portion that was sitting in
--- the Src TC range. "cut" really splits/repositions the original items
--- instead (matching Matchbox/Ediload's Cut/Paste mode) — see
--- CLB.dme_recut_execute for both paths.
---
--- Split in two for the Settings popup: CLB.dme_recut_prepare() validates
--- and analyzes (builds the move list + duplicate-overlap warning) and
--- opens the popup; CLB.dme_recut_execute() (called from the popup's "Run
--- It" button) does the actual work, reading CLB.dme_recut_pending for
--- what to run and CLB.dme_recut_mode/dme_recut_markers for how.
function CLB.dme_recut_prepare()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events loaded. Load an EDL file first.", SCRIPT_NAME, 0)
    return
  end

  local n_sel_tracks = reaper.CountSelectedTracks(0)
  if n_sel_tracks == 0 then
    reaper.ShowMessageBox(
      "Select at least one track in Reaper first — the track(s) this\n"
      .. "recut should operate on.",
      SCRIPT_NAME, 0)
    return
  end
  local sel_tracks = {}
  for i = 0, n_sel_tracks - 1 do
    sel_tracks[#sel_tracks + 1] = reaper.GetSelectedTrack(0, i)
  end

  local fps, is_drop = CLB.fps, CLB.is_drop
  local TOL = 0.5 / fps  -- sub-frame float noise tolerance
  local visible_rows = get_view_rows() or ROWS

  -- Build the move list from the currently visible/filtered rows (same
  -- "operate on what's currently filtered" convention as Generate Items/
  -- Remove Dups/Consolidate) — filter to just the relevant stem's rows
  -- first via CLB's own Search/Track/Group filters, same as any other
  -- batch action here.
  local moves = {}
  for _, row in ipairs(visible_rows) do
    if row.src_tc_in and row.src_tc_in ~= "" and row.src_tc_out and row.src_tc_out ~= ""
       and row.rec_tc_in and row.rec_tc_in ~= "" then
      local src_in  = CLB.src_tc_seconds(row.src_tc_in,  row)
      local src_out = CLB.src_tc_seconds(row.src_tc_out, row)
      local rec_in  = CLB.rec_tc_seconds(row.rec_tc_in,  row)
      if src_out > src_in + TOL and math.abs(rec_in - src_in) > TOL then
        moves[#moves + 1] = { src_in = src_in, src_out = src_out, rec_in = rec_in, row = row }
      end
    end
  end

  if #moves == 0 then
    reaper.ShowMessageBox(
      "Nothing to recut — every visible event's Src TC already matches\n"
      .. "its Rec TC position.",
      SCRIPT_NAME, 0)
    return
  end

  -- Pre-flight: detect moves whose Src TC ranges overlap (or are exact
  -- duplicates of) each other — a strong signal the filtered list mixes
  -- more than one "layer" of the same underlying content. Real, confirmed
  -- case: DX/ADR/FX/MU all share ONE embedded timecode baseline (see
  -- CLB.dme_recut's own doc comment), so the same real cut point shows up
  -- as a separate event per stem type when their rows aren't filtered
  -- apart — even Matchbox (Cargo Cult) shows this exact duplication (the
  -- same match listed 4x, once per stem, in its own Matches view) when
  -- fed the same kind of list. Processing overlapping moves together
  -- risks copying the same real content more than once onto the selected
  -- track(s). This only warns — it never guesses which one is "right" and
  -- silently drops/merges the others (see
  -- feedback_warn_dont_guess_ambiguous_heuristics) — the user decides
  -- whether to clean up the filter/track selection first or proceed
  -- anyway.
  local function tc(sec) return EDL.seconds_to_tc(sec, fps, is_drop) end
  table.sort(moves, function(a, b) return a.src_in < b.src_in end)
  local dup_lines = {}
  do
    local groups, group_order = {}, {}
    local active_end, active_mv = nil, nil
    for _, mv in ipairs(moves) do
      if active_end and mv.src_in < active_end - TOL then
        local g = groups[active_mv]
        if not g then
          g = { mv = active_mv, count = 0, sample_clips = {} }
          groups[active_mv] = g
          group_order[#group_order + 1] = g
        end
        g.count = g.count + 1
        local clip = (mv.row and mv.row.clip_name) or "?"
        if #g.sample_clips < 4 then g.sample_clips[#g.sample_clips + 1] = clip end
      end
      if not active_end or mv.src_out > active_end then
        active_end = mv.src_out
        active_mv = mv
      end
    end
    for _, g in ipairs(group_order) do
      local sample = table.concat(g.sample_clips, ", ")
      if g.count > #g.sample_clips then sample = sample .. ", ..." end
      dup_lines[#dup_lines + 1] = string.format(
        "  %s–%s (%s) overlaps %d other event(s): %s",
        tc(g.mv.src_in), tc(g.mv.src_out), (g.mv.row and g.mv.row.clip_name) or "?",
        g.count, sample)
    end
  end
  local dup_warning = ""
  if #dup_lines > 0 then
    dup_warning = string.format(
      "\n\n⚠ %d Src TC range(s) overlap another event in this list — likely\n"
      .. "more than one stem/layer mixed together (e.g. DX+ADR share a\n"
      .. "timecode baseline). Proceeding may copy the same real content\n"
      .. "more than once:\n%s",
      #dup_lines, table.concat(dup_lines, "\n"))
  end

  -- Analysis done — hand off to the Settings popup (Copy/Cut, Marker
  -- on/off; see the draw-side "DME Recut Settings" popup block) instead of
  -- running immediately. CLB.dme_recut_execute (below) reads this back.
  CLB.dme_recut_pending = {
    moves = moves, sel_tracks = sel_tracks,
    dup_lines = dup_lines, dup_warning = dup_warning,
    fps = fps, is_drop = is_drop, tc = tc,
  }
  reaper.ImGui_OpenPopup(ctx, "DME Recut Settings##clb_dme_recut_popup")
end

---------------------------------------------------------------------------
-- CLB Recut track (old<->new jump markers) — Phase 1
---------------------------------------------------------------------------
--- Phase 1 of a planned "Jump Old/New TC" feature (see project memory):
--- a standalone wrapper script, runnable from REAPER's own Action List
--- with a keyboard shortcut (something Matchbox's own old/new jump can't
--- do — it only works from inside Matchbox), finds whichever "CLB Recut"
--- track item the edit cursor currently sits inside and jumps to that
--- item's paired position, read from its own item note. This is how CLB
--- publishes that pairing — real REAPER items are the data store, no
--- separate ExtState/file sync needed between CLB and the wrapper.
---
--- Scoped to DME Recut only for Phase 1 (the only operation that today
--- repositions real content old-position -> new-position) — Compare's
--- own Trimmed/Extended/Moved Apply isn't built yet (only Deleted apply
--- exists), so there is no "move" to pair there yet; it'll get the same
--- treatment once that exists. Deliberately single-pair only here — no
--- multi-version chain (V1->V2->V3), no overlap/folder-track handling —
--- those are planned Phase 2, once this basic mechanism is validated.
CLB.RECUT_TRACK_NAME = "CLB Recut"
CLB.RECUT_OLD_COLOR  = reaper.ColorToNative( 90, 120, 170) | 0x1000000
CLB.RECUT_NEW_COLOR  = reaper.ColorToNative(200, 160,  70) | 0x1000000

--- Finds the shared "CLB Recut" track, or creates one at the TOP of the
--- track list (not hidden — user's own call while this is new/being
--- tried out) if none exists yet.
function CLB._find_or_create_recut_track()
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name == CLB.RECUT_TRACK_NAME then return tr end
  end
  reaper.InsertTrackAtIndex(0, true)
  local tr = reaper.GetTrack(0, 0)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", CLB.RECUT_TRACK_NAME, true)
  return tr
end

--- Records an old<->new position pair per move as TWO empty items on the
--- CLB Recut track: one spanning the OLD (Src TC) range with a note
--- pointing at the NEW position, one spanning the NEW (Rec TC) range
--- with a note pointing at the OLD position — so the wrapper can jump
--- either direction depending which one the cursor is on. Re-running on
--- the same moves replaces (doesn't pile up) any EXISTING item at the
--- EXACT SAME position+length (a prior run of this exact move), so
--- repeat DME Recut runs stay idempotent; markers from other moves are
--- left alone.
---
--- Deliberately an EXACT match (position AND length both within TOL),
--- not a loose overlap test — a loose "do these ranges touch" test was
--- the original implementation and had a real bug: consecutive EDL
--- events routinely share an exact boundary (one event's Src TC Out
--- equals the next one's Src TC In), so a loose overlap check with TOL
--- padding on both edges treated two merely-ADJACENT (not actually
--- overlapping) moves' items as colliding, deleting one neighbor's item
--- while adding the other's — confirmed from a real RGWH Monitor dump
--- where an Old item was silently missing for exactly this reason.
function CLB.populate_recut_track(moves, fps, is_drop)
  local tr = CLB._find_or_create_recut_track()
  local TOL = 0.5 / fps

  local function clear_exact(pos_target, len_target)
    local n = reaper.CountTrackMediaItems(tr)
    for i = n - 1, 0, -1 do
      local item = reaper.GetTrackMediaItem(tr, i)
      local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      if math.abs(pos - pos_target) < TOL and math.abs(len - len_target) < TOL then
        reaper.DeleteTrackMediaItem(tr, item)
      end
    end
  end

  local function add_marker_item(pos, len, label, jump_to_sec, color)
    local item = reaper.AddMediaItemToTrack(tr)
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(len, 0.001))
    reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
    local take = reaper.AddTakeToMediaItem(item)
    if take then
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", label, true)
    end
    -- Machine-readable: "CLB_JUMP:<seconds>" as the first line — the
    -- wrapper only ever parses this line, the rest of the note (if any
    -- gets added later, e.g. in Phase 2) is free-form.
    reaper.GetSetMediaItemInfo_String(item, "P_NOTES",
      string.format("CLB_JUMP:%.10f", jump_to_sec), true)
  end

  for _, mv in ipairs(moves) do
    local len = mv.src_out - mv.src_in
    clear_exact(mv.src_in, len)
    clear_exact(mv.rec_in, len)
    local old_tc = EDL.seconds_to_tc(mv.src_in, fps, is_drop)
    local new_tc = EDL.seconds_to_tc(mv.rec_in, fps, is_drop)
    add_marker_item(mv.src_in, len, "CLB Old → " .. new_tc, mv.rec_in, CLB.RECUT_OLD_COLOR)
    add_marker_item(mv.rec_in, len, "CLB New → " .. old_tc, mv.src_in, CLB.RECUT_NEW_COLOR)
  end
end

--- Runs the analysis CLB.dme_recut_prepare stored in CLB.dme_recut_pending,
--- per the user's CLB.dme_recut_mode ("copy"/"cut") and
--- CLB.dme_recut_markers choice — called from the Settings popup's "Run
--- It" button.
function CLB.dme_recut_execute()
  local pending = CLB.dme_recut_pending
  if not pending then return end
  local moves, sel_tracks = pending.moves, pending.sel_tracks
  local dup_lines, tc = pending.dup_lines, pending.tc
  local TOL = 0.5 / pending.fps
  local mode = CLB.dme_recut_mode or "copy"

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local created = 0
  local unmatched_events = 0

  if mode == "cut" then
    -- Really split/reposition the original items (Matchbox/Ediload's Cut/
    -- Paste mode) — delegates to CLB.cut_shift_range, the same low-level
    -- primitive CMP.shift_range ("Shift Tracks...") uses: isolate
    -- whatever overlaps [a,b] on a track and move it by a constant delta.
    -- Here delta = mv.rec_in - mv.src_in, the same constant for every
    -- overlapping piece within one move, since Src/Rec duration is always
    -- equal per CMX3600 rules (see this function's own doc comment) — a
    -- DME Recut move and a Shift Range move are the exact same mechanical
    -- operation, just computing their delta differently.
    for _, mv in ipairs(moves) do
      local delta = mv.rec_in - mv.src_in
      local any_found = false
      for _, track in ipairs(sel_tracks) do
        local n = CLB.cut_shift_range(track, mv.src_in, mv.src_out, delta, TOL)
        if n > 0 then any_found = true; created = created + n end
      end
      if not any_found then unmatched_events = unmatched_events + 1 end
    end
  else
    -- Copy: V1's real content stays exactly where it is; a brand new item
    -- is created at the Rec TC position sharing the same underlying
    -- source. Snapshot each selected track's ORIGINAL items once, up
    -- front — the new items this creates must never be treated as more
    -- "original V1 content" to read from again on a later event.
    local track_items = {}
    for _, track in ipairs(sel_tracks) do
      local snap = {}
      local n = reaper.CountTrackMediaItems(track)
      for i = 0, n - 1 do snap[#snap + 1] = reaper.GetTrackMediaItem(track, i) end
      track_items[track] = snap
    end

    for _, mv in ipairs(moves) do
      local any_found = false
      for _, track in ipairs(sel_tracks) do
        for _, item in ipairs(track_items[track]) do
          local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local iend = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local overlap_start = math.max(pos, mv.src_in)
          local overlap_end   = math.min(iend, mv.src_out)
          if overlap_end > overlap_start + TOL then
            any_found = true

            local rel_offset = overlap_start - mv.src_in   -- position within the event's own range
            local chunk_len  = overlap_end - overlap_start
            local new_pos    = mv.rec_in + rel_offset

            local new_item = reaper.AddMediaItemToTrack(track)
            reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", new_pos)
            reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", chunk_len)
            reaper.SetMediaItemInfo_Value(new_item, "D_VOL",
              reaper.GetMediaItemInfo_Value(item, "D_VOL"))
            reaper.SetMediaItemInfo_Value(new_item, "B_MUTE",
              reaper.GetMediaItemInfo_Value(item, "B_MUTE"))

            local take = reaper.GetActiveTake(item)
            if take then
              local rate      = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
              local startoffs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
              local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)

              local new_take = reaper.AddTakeToMediaItem(new_item)
              reaper.SetMediaItemTake_Source(new_take, reaper.GetMediaItemTake_Source(take))
              reaper.SetMediaItemTakeInfo_Value(new_take, "D_PLAYRATE", rate)
              -- How far overlap_start sits past this item's own start,
              -- converted to source time via the take's own playback rate,
              -- gives exactly where in the source media to begin.
              reaper.SetMediaItemTakeInfo_Value(new_take, "D_STARTOFFS",
                startoffs + (overlap_start - pos) * rate)
              reaper.SetMediaItemTakeInfo_Value(new_take, "D_VOL",
                reaper.GetMediaItemTakeInfo_Value(take, "D_VOL"))
              reaper.SetMediaItemTakeInfo_Value(new_take, "D_PAN",
                reaper.GetMediaItemTakeInfo_Value(take, "D_PAN"))
              reaper.SetMediaItemTakeInfo_Value(new_take, "I_CHANMODE",
                reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"))
              reaper.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", take_name or "", true)
            end

            created = created + 1
          end
        end
      end
      if not any_found then unmatched_events = unmatched_events + 1 end
    end
  end

  -- Recut markers: DME Recut can tell "how much was trimmed/deleted"
  -- directly from its own Src TC, without a second EDL/Compare — the
  -- whole premise of this function (see CLB.dme_recut_prepare's doc
  -- comment: Src TC already IS V1's real position for printed-to-pitch
  -- stems). Walking moves in their NEW (Rec) order: a gap between
  -- consecutive events' Rec TC with no matching Src TC gap is new content
  -- with no V1 source (INSERT); a gap in Src TC with no matching Rec TC
  -- gap is V1 content that didn't make it into V2 (DELETE). Modeled on
  -- Matchbox's (Cargo Cult) own marker vocabulary, confirmed from a real
  -- Matchbox session and its own Markers list view — deliberately NOT its
  -- bare "x"/">"/"<" edge markers (user's own call: clear to Matchbox's
  -- regular users, opaque to anyone else, and tellingly absent from
  -- Matchbox's own categorized Markers list — only its worded Insert/
  -- Delete/Trim/Extend/Reorder types are) or its Trim/Extend/Reorder
  -- types (those only arise comparing TWO different EDLs' own clip
  -- selections — not meaningful within one EDL's own Src-vs-Rec, where
  -- duration is always identical per CMX3600 rules; that's what
  -- Trimmed/Extended/Moved in hsuanice_CLB Compare Engine.lua are for).
  -- Skippable via CLB.dme_recut_markers (the popup's Marker toggle).
  local n_markers = 0
  if CLB.dme_recut_markers then
    local by_rec = {}
    for _, mv in ipairs(moves) do
      by_rec[#by_rec + 1] = {
        src_in = mv.src_in, src_out = mv.src_out,
        rec_in = mv.rec_in, rec_out = mv.rec_in + (mv.src_out - mv.src_in),
      }
    end
    table.sort(by_rec, function(a, b) return a.rec_in < b.rec_in end)
    local DELETE_COLOR = CMP.TYPE_COLOR.Deleted   -- red  — reused for visual consistency with Analyze & Match
    local INSERT_COLOR = CMP.TYPE_COLOR.Extended  -- green
    for i = 2, #by_rec do
      local prev, cur = by_rec[i - 1], by_rec[i]
      local rec_gap = cur.rec_in - prev.rec_out
      local src_gap = cur.src_in - prev.src_out
      if src_gap > TOL then
        reaper.AddProjectMarker2(0, false, cur.rec_in, 0, "Delete For " .. tc(src_gap), -1, DELETE_COLOR)
        n_markers = n_markers + 1
      end
      if rec_gap > TOL then
        reaper.AddProjectMarker2(0, false, prev.rec_out, 0, "Insert For " .. tc(rec_gap), -1, INSERT_COLOR)
        n_markers = n_markers + 1
      end
    end
  end

  -- Phase 1 of the planned Jump Old/New TC feature (see project memory)
  -- — records each move's old<->new position pair on the shared "CLB
  -- Recut" track for the standalone jump wrapper to read.
  CLB.populate_recut_track(moves, pending.fps, pending.is_drop)

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(string.format("CLB: DME Recut (%d event(s), %d item(s) %s)",
    #moves, created, mode == "cut" and "moved" or "created"), -1)

  CLB.dme_recut_pending = nil

  local done_msg = string.format(
    "DME Recut done.\n\n%d event(s) processed, %d real item(s) %s.",
    #moves, created, mode == "cut" and "moved/split" or "created")
  if n_markers > 0 then
    done_msg = done_msg .. string.format("\n%d Delete/Insert marker(s) added.", n_markers)
  end
  done_msg = done_msg .. (mode == "cut"
    and "\n\nOriginals were split/repositioned directly."
    or "\n\nOriginals were left untouched — this copied from them.")
  if unmatched_events > 0 then
    done_msg = done_msg .. string.format(
      "\n\n%d event(s) had nothing on the selected track(s) at their Src\n"
      .. "TC range — skipped.", unmatched_events)
  end
  if #dup_lines > 0 then
    done_msg = done_msg .. string.format(
      "\n\n⚠ %d overlapping Src TC range(s) were processed anyway (per\n"
      .. "your confirmation) — check the result for unwanted duplicate\n"
      .. "copies.", #dup_lines)
  end
  reaper.ShowMessageBox(done_msg, "DME Recut", 0)
end

---------------------------------------------------------------------------
-- Export EDL / TSV / CSV
---------------------------------------------------------------------------

--- Builds TSV/CSV text from the main event table — mirrors
--- build_audio_table_text (Audio Files panel's own Save .tsv/.csv),
--- just against the main table's own HEADER_LABELS/get_cell_text/
--- COL_COUNT instead of the audio-specific equivalents. Respects the
--- user's CURRENT column order/visibility (EDL_COL_ORDER/VISIBILITY),
--- unlike Export EDL's fixed narrow CMX3600 schema — a TSV/CSV dump
--- isn't constrained by a legacy format spec, so it includes whatever
--- columns are actually shown (Scene/Take/Speed/Notes/Group/... if on).
function CLB._build_edl_table_text(format_type, rows)
  local sep = format_type == "csv" and "," or "\t"
  local lines = {}

  local headers = {}
  for _, col in ipairs(EDL_COL_ORDER) do
    if EDL_COL_VISIBILITY[col] then
      headers[#headers + 1] = escape_field_value(HEADER_LABELS[col] or "", format_type)
    end
  end
  lines[#lines + 1] = table.concat(headers, sep)

  for _, row in ipairs(rows) do
    local cells = {}
    for _, col in ipairs(EDL_COL_ORDER) do
      if EDL_COL_VISIBILITY[col] then
        cells[#cells + 1] = escape_field_value(get_cell_text(row, col), format_type)
      end
    end
    lines[#lines + 1] = table.concat(cells, sep)
  end

  return table.concat(lines, "\n")
end

--- Export the full list (not just the filtered/visible view — same
--- convention Export EDL already uses) as TSV or CSV.
function CLB.export_tsv_csv(format_type)
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events to export.", SCRIPT_NAME, 0)
    return
  end

  local ext = format_type == "csv" and "csv" or "tsv"
  local filter = format_type == "csv"
    and "CSV Files\0*.csv\0\0" or "TSV Files\0*.tsv\0\0"
  -- Default filename: "export_YYMMDD_HHMMSS" — user's own request, same
  -- timestamped-default idea as Save CLB Project's own default name,
  -- same for every export format.
  local default_name = "export_" .. os.date("%y%m%d_%H%M%S") .. "." .. ext
  local retval, filepath
  if reaper.JS_Dialog_BrowseForSaveFile then
    retval, filepath = reaper.JS_Dialog_BrowseForSaveFile(
      "Export " .. ext:upper(), CLB.last_dir or "", default_name, filter)
    if not retval or retval == 0 or not filepath or filepath == "" then return end
  else
    retval, filepath = reaper.GetUserFileNameForRead("", "Export " .. ext:upper() .. " (choose or type filename)", "*." .. ext)
    if not retval or not filepath or filepath == "" then return end
  end

  local text = CLB._build_edl_table_text(format_type, ROWS)
  local f = io.open(filepath, "w")
  if not f then
    reaper.ShowMessageBox("Export failed: could not write to:\n" .. filepath, SCRIPT_NAME, 0)
    return
  end
  f:write(text)
  f:close()
  reaper.ShowMessageBox(
    string.format("Exported %d events to:\n%s", #ROWS, filepath),
    SCRIPT_NAME, 0)
end

local function export_edl()
  if #ROWS == 0 then
    reaper.ShowMessageBox("No events to export.", SCRIPT_NAME, 0)
    return
  end

  -- Default filename: "export_YYMMDD_HHMMSS" — same as Export TSV/CSV's
  -- own default, user's own request (same idea Save CLB Project's own
  -- default name already uses: a timestamped default).
  local default_name = "export_" .. os.date("%y%m%d_%H%M%S") .. ".edl"
  local retval, filepath
  if reaper.JS_Dialog_BrowseForSaveFile then
    retval, filepath = reaper.JS_Dialog_BrowseForSaveFile(
      "Export EDL", CLB.last_dir or "", default_name, "EDL Files\0*.edl\0\0")
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

  -- Renumber events sequentially (001, 002, 003...)
  local event_num = 0
  for _, row in ipairs(ROWS) do
    event_num = event_num + 1
    export_data.events[#export_data.events + 1] = {
      event_num = string.format("%03d", event_num),
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

  _rebuild_group_filters()
  undo_snapshot()
  CLB.cached_rows = nil
  console_msg("Pasted " .. #clip_rows .. " rows")
end

---------------------------------------------------------------------------
-- Modifier key helpers
---------------------------------------------------------------------------
CLB._IS_MAC = (reaper.GetOS():find("OSX") or reaper.GetOS():find("macOS")) ~= nil -- (not a local: main chunk is at the 200-local limit)
local function _mods()
  local shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
  -- Mod_Ctrl IS the Cmd key on macOS: ReaImGui's ConfigVar_MacOSXBehaviors
  -- ("Enabled by default on macOS. Swap Cmd<>Ctrl keys") — so Mod_Super
  -- there is the physical Control key. This used to read Mod_Super on
  -- macOS, which made every "Cmd" shortcut (A/C/V/Z, Cmd+click) actually
  -- need Control — real user report: Cmd+A did nothing. Mod_Super is
  -- still accepted on macOS too, in case MacOSXBehaviors is ever off
  -- (then Super = Cmd) and so Control keeps working as before.
  local ctrl_cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Ctrl())
  if not ctrl_cmd and CLB._IS_MAC then
    ctrl_cmd = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Super())
  end
  return shift, ctrl_cmd
end

---------------------------------------------------------------------------
-- Toolbar button color coding, by function group (user-requested, see
-- project memory) — purely visual grouping, no behavior change. Each
-- entry is {Button, ButtonHovered, ButtonActive} in ImGui's 0xRRGGBBAA
-- format. Seven groups:
--   danger Destructive/reset: Clear List, Clear Audio
--   list   List editing/cleanup: Remove Dups, Consolidate
--   io     Input/Output: Load List, Load Audio, Export EDL
--   align  Position correction: Shift Range, Calibrate TC
--   recut  Recut/reconform: Compare, DME Recut
--   build  Build real content from the list: Generate Items, Conform
--          All/Sel, Scene Cuts, Match All
--   link   Reaper item <-> event links: Link Reaper Items, Reveal Item
-- Anything not wrapped in one of these stays the theme's default color.
--
-- Rainbow order red-orange-yellow-green-blue-indigo-violet (user's own request), following the left
-- sidebar top→bottom: danger red, recut orange, align yellow, build green, io blue (top
-- toolbar), list indigo, link violet — link deliberately muted (lower saturation +
-- alpha): user's own call, its actions aren't consequential enough to
-- need an eye-catching color. Optional 4th entry = text color, for a
-- background too light for the theme's default white text (yellow).
CLB.BTN_GROUP_COLORS = {
  danger = { 0xB33838C0, 0xCC4444D0, 0x992D2DD0 },
  recut  = { 0xCC7A33C0, 0xDD8F44D0, 0xAA6628D0 },
  align  = { 0xD4B23AC8, 0xE3C452D8, 0xB3952CD8, 0x1E1E1EFF },
  build  = { 0x3D8C40C0, 0x4FA352D0, 0x2F6E31D0 },
  io     = { 0x3366CCC0, 0x4477DDD0, 0x2855AAD0 },
  list   = { 0x5B3FB0C0, 0x6E52C6D0, 0x4A3391D0 },
  link   = { 0x8C7096A0, 0x9C80A8B8, 0x76607FB8 },
}

function CLB.push_btn_color(group_key)
  local c = CLB.BTN_GROUP_COLORS[group_key]
  if not c then return end
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), c[1])
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), c[2])
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), c[3])
  if c[4] then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), c[4]) end
end

function CLB.pop_btn_color(group_key)
  local c = CLB.BTN_GROUP_COLORS[group_key]
  if not c then return end
  reaper.ImGui_PopStyleColor(ctx, c[4] and 4 or 3)
end

---------------------------------------------------------------------------
-- Draw: Toolbar
---------------------------------------------------------------------------
local function draw_toolbar()
  -- Row 1 (scrollable if window is narrow)
  -- +14 always reserves horizontal scrollbar space so buttons are never clipped
  local row1_height = scale(28) + 14
  local flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
  if reaper.ImGui_BeginChild(ctx, "##toolbar_row1", 0, row1_height, 0, flags) then
    -- Project Save / Open
    if CLB.loaded_file and CLB.loaded_is_clb then
      -- Quick Save (overwrite current file, no dialog)
      if reaper.ImGui_Button(ctx, "Save", scale(50), scale(24)) then
        if save_clb_project(CLB.loaded_file, true) then
          save_prefs()
        end
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, "Save to: " .. (CLB.loaded_file:match("([^/\\]+)$") or CLB.loaded_file))
        reaper.ImGui_EndTooltip(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      -- Save As (dialog)
      if reaper.ImGui_Button(ctx, "Save As...", scale(80), scale(24)) then
        save_clb_project_dialog()
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, "Save current session as a new .clb project file")
        reaper.ImGui_EndTooltip(ctx)
      end
    else
      if reaper.ImGui_Button(ctx, "Save...", scale(65), scale(24)) then
        save_clb_project_dialog()
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, "Save current session as a .clb project file")
        reaper.ImGui_Text(ctx, "(preserves EDL events, groups, audio matches, settings)")
        reaper.ImGui_EndTooltip(ctx)
      end
    end
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Open...", scale(65), scale(24)) then
      open_clb_project()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Open a previously saved .clb project file")
      reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_SameLine(ctx)

    -- Clear List now lives in the left sidebar (draw_left_sidebar), in
    -- its own red "danger" group with Clear Audio — not here.

    reaper.ImGui_Text(ctx, "|")
    reaper.ImGui_SameLine(ctx)

    -- Load List button: EDL/XML/AAF/Subtitle consolidated into one
    -- popup menu (were 4 separate buttons) — saves toolbar space, same
    -- pattern as the Options popup.
    CLB.push_btn_color("io")
    local load_list_clicked = reaper.ImGui_Button(ctx, "Load List...", scale(90), scale(24))
    CLB.pop_btn_color("io")
    if load_list_clicked then
      reaper.ImGui_OpenPopup(ctx, "##clb_load_list")
    end
    if reaper.ImGui_BeginPopup(ctx, "##clb_load_list") then
      if reaper.ImGui_Selectable(ctx, "Load EDL...") then load_edl_file() end
      if reaper.ImGui_Selectable(ctx, "Load XML...") then load_xml_file() end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "FCP7 XML, DaVinci Resolve XML, Premiere Pro XML")
      end
      if reaper.ImGui_Selectable(ctx, "Load AAF...") then load_aaf_file() end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "AAF — requires: aaftool (LibAAF) in PATH\nhttps://github.com/agfline/LibAAF")
      end
      if reaper.ImGui_Selectable(ctx, "Load Subtitle...") then load_subtitle_file() end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, "Load subtitle / dialogue list file:")
        reaper.ImGui_Text(ctx, "  .srt        SubRip subtitles")
        reaper.ImGui_Text(ctx, "  .csv / .tsv Tabular dialogue lists")
        reaper.ImGui_Text(ctx, "  .xlsx       Excel dialogue lists (multi-sheet)")
        reaper.ImGui_Text(ctx, "")
        reaper.ImGui_Text(ctx, "Generates empty items at subtitle in/out points")
        reaper.ImGui_Text(ctx, "with the text as Clip Name.")
        reaper.ImGui_EndTooltip(ctx)
      end
      reaper.ImGui_EndPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)

  -- Export button — EDL/TSV/CSV consolidated into one popup menu, same
  -- pattern as "Load List..." (user's own request:
  -- make Export work like Import,
  -- show the format choices only after clicking). Lives next to Load
  -- List (both I/O), not down with the action buttons in the sidebar.
  CLB.push_btn_color("io")
  local export_clicked = reaper.ImGui_Button(ctx, "Export...", scale(90), scale(24))
  CLB.pop_btn_color("io")
  if export_clicked then
    reaper.ImGui_OpenPopup(ctx, "##clb_export_list")
  end
  if reaper.ImGui_BeginPopup(ctx, "##clb_export_list") then
    if reaper.ImGui_Selectable(ctx, "Export EDL...") then export_edl() end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "CMX3600 EDL — fixed schema (Event/Reel/Track/TC/Clip Name/Source File)")
    end
    if reaper.ImGui_Selectable(ctx, "Export TSV...") then CLB.export_tsv_csv("tsv") end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Tab-separated — includes every currently visible column, in your current column order")
    end
    if reaper.ImGui_Selectable(ctx, "Export CSV...") then CLB.export_tsv_csv("csv") end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Comma-separated — includes every currently visible column, in your current column order")
    end
    reaper.ImGui_EndPopup(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Load Audio button
  CLB.push_btn_color("io")
  local load_audio_clicked = reaper.ImGui_Button(ctx, "Load Audio...", scale(100), scale(24))
  CLB.pop_btn_color("io")
  if load_audio_clicked then
    load_audio_folder()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Load audio files from folder to match with EDL events")
    reaper.ImGui_Text(ctx, "Reads BWF/iXML metadata for matching")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Load From Reaper button — "another kind of list source" (user's own
  -- framing), independent from the "Load List..." menu's file-based
  -- loaders: reads currently selected Reaper items back into the event
  -- list instead of parsing a file. See CLB.load_from_reaper_selection's
  -- own doc comment. The "Auto Match" checkbox is a persisted setting
  -- (off by default), not a one-off popup choice — matches the existing
  -- "Recursive" checkbox-next-to-its-button convention (Audio Files
  -- panel header) rather than inventing a new settings-popup pattern.
  CLB.push_btn_color("io")
  local load_from_reaper_clicked = reaper.ImGui_Button(ctx, "Load From Reaper", scale(130), scale(24))
  CLB.pop_btn_color("io")
  if load_from_reaper_clicked then
    CLB.load_from_reaper_selection()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Read currently selected Reaper item(s) into the event")
    reaper.ImGui_Text(ctx, "list (replaces/appends like any other Load) — e.g. to")
    reaper.ImGui_Text(ctx, "Find Match-test a batch of items you just generated.")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Match All and Clear Audio now live in the left sidebar
  -- (draw_left_sidebar) — not here. The status text and Sources/Tracks/
  -- Filters/Audio toggle buttons that used to follow them moved to row 2,
  -- right of Search — see there.

  -- Separator
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)

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

    -- CJK Font path (file path or family name)
    if reaper.ImGui_Selectable(ctx, "   CJK Font...") then
      CLB.cjk_font_dialog = {
        open       = true,
        buf        = CLB.cjk_font_path or "",
        status_msg = "",
        status_ok  = nil,
      }
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Formats:")

    reaper.ImGui_Text(ctx, "Track Format")
    reaper.ImGui_SetNextItemWidth(ctx, scale(250))
    local chg_tf, new_tf = reaper.ImGui_InputText(ctx, "##clb_trk_fmt", CLB.track_name_format)
    if chg_tf then
      CLB.track_name_format = new_tf
      save_prefs()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Tokens: ${track} ${reel} ${clip} ${event}")
      reaper.ImGui_Text(ctx, "        ${format} ${title} ${edit_type}")
      reaper.ImGui_Text(ctx, "Items will be grouped by the expanded track name")
      reaper.ImGui_EndTooltip(ctx)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Clip Name Format")
    reaper.ImGui_SetNextItemWidth(ctx, scale(250))
    local cnf_chg, cnf_new = reaper.ImGui_InputText(ctx, "##clip_name_fmt", CLB.clip_name_format or "")
    if cnf_chg then
      CLB.clip_name_format = cnf_new
      save_prefs()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx,
        "Clip name template applied when matching audio (or via\n" ..
        "\"Apply Clip Name Format\" near the Audio table).\n" ..
        "Leave blank to keep original clip names.\n" ..
        "Tokens: $reel  $scene  $take\n" ..
        "Example: $reel----$sceneT$take  →  D043----9-9-12T1")
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Ref Media Filename Format")
    reaper.ImGui_SetNextItemWidth(ctx, scale(250))
    local rmf_chg, rmf_new = reaper.ImGui_InputText(ctx, "##ref_media_fmt", CLB.ref_media_name_format or "")
    if rmf_chg then
      CLB.ref_media_name_format = rmf_new
      save_prefs()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx,
        "Subfolder name for \"Generate Ref Media...\" — one real WAV per\n"
        .. "event goes inside it (filenames prefixed \"_REF\").\n"
        .. "Tokens: ${timestamp}\n"
        .. "Example: !CLB_Mute_${timestamp}  →  !CLB_Mute_261007_120000/")
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Load From Reaper: Replace/Append")
    reaper.ImGui_TextDisabled(ctx, "Re-running \"Load From Reaper\" many times while iterating")
    reaper.ImGui_TextDisabled(ctx, "can mean re-answering this every time — set a fixed default here.")
    if reaper.ImGui_RadioButton(ctx, "Always ask (default)##clb_lfr_merge_ask", CLB.ref_load_merge_mode == "ask") then
      CLB.ref_load_merge_mode = "ask"; save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Always Replace##clb_lfr_merge_replace", CLB.ref_load_merge_mode == "replace") then
      CLB.ref_load_merge_mode = "replace"; save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Always Append##clb_lfr_merge_append", CLB.ref_load_merge_mode == "append") then
      CLB.ref_load_merge_mode = "append"; save_prefs()
    end

    reaper.ImGui_EndPopup(ctx)
  end
  end
  reaper.ImGui_EndChild(ctx)  -- End toolbar_row1

  -- Row 2 (scrollable if window is narrow)
  local row2_height = scale(28) + 14
  if reaper.ImGui_BeginChild(ctx, "##toolbar_row2", 0, row2_height, 0, flags) then
    -- FPS selector (dropdown)
  local FPS_OPTIONS = {
    { label = "24/23.97", value = 24 },
    { label = "25", value = 25 },
    { label = "29.97 DF", value = 29.97, drop = true },
    { label = "30", value = 30 },
    { label = "50", value = 50 },
    { label = "59.94 DF", value = 59.94, drop = true },
    { label = "60", value = 60 },
  }

  -- Find current selection
  local current_label = tostring(CLB.fps)
  for _, opt in ipairs(FPS_OPTIONS) do
    if math.abs(opt.value - CLB.fps) < 0.03 and (opt.drop or false) == CLB.is_drop then
      current_label = opt.label
      break
    end
  end

  reaper.ImGui_Text(ctx, "FPS:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(90))
  if reaper.ImGui_BeginCombo(ctx, "##clb_fps", current_label) then
    for _, opt in ipairs(FPS_OPTIONS) do
      local is_sel = math.abs(opt.value - CLB.fps) < 0.03 and (opt.drop or false) == CLB.is_drop
      if reaper.ImGui_Selectable(ctx, opt.label, is_sel) then
        CLB.fps = opt.value
        CLB.is_drop = opt.drop or false
        save_prefs()
        -- Recompute durations
        for _, row in ipairs(ROWS) do
          local ri_sec = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
          local ro_sec = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
          row.duration = EDL.seconds_to_tc(ro_sec - ri_sec, CLB.fps, CLB.is_drop)
        end
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Search (after FPS)
  reaper.ImGui_Text(ctx, "Search:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(160))
  if CLB.focus_search then -- Cmd+F (see the keyboard shortcuts block)
    reaper.ImGui_SetKeyboardFocusHere(ctx)
    CLB.focus_search = false
  end
  local chg_s, new_s = reaper.ImGui_InputText(ctx, "##clb_search", CLB.search_text)
  if chg_s then
    CLB.search_text = new_s
    CLB.cached_rows = nil
    sel_clear()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "8 digits (e.g. 01102203) also matches\nthe timecode 01:10:22:03")
  end
  if CLB.search_text ~= "" then
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "X##clb_clear_search") then
      CLB.search_text = ""
      CLB.cached_rows = nil
    end
  end
  reaper.ImGui_SameLine(ctx)

  -- Separator
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)

  -- Status (simplified: just counts, no filename)
  local view_rows = get_view_rows()
  local status
  if #ROWS > 0 then
    status = string.format("Events: %d | Showing: %d", #ROWS, #view_rows)
  else
    status = "No events"
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

  -- Filters toggle button (controls Reels + Groups sidebar together)
  local has_filters = #CLB.reel_filters > 0 or #CLB.group_filters > 0
  if has_filters then
    local filters_visible = CLB.show_reel_filter or CLB.show_group_filter
    local filter_label = filters_visible and "Filters <<" or "Filters >>"
    if reaper.ImGui_SmallButton(ctx, filter_label .. "##clb_filter_toggle") then
      local new_state = not filters_visible
      CLB.show_reel_filter = new_state
      CLB.show_group_filter = new_state
    end
    reaper.ImGui_SameLine(ctx)
  end

  -- Audio toggle button (show when audio files are loaded)
  if #CLB.audio_files > 0 then
    local audio_label = CLB.show_audio_panel and "Audio <<" or "Audio >>"
    if reaper.ImGui_SmallButton(ctx, audio_label .. "##clb_audio_toggle") then
      CLB.show_audio_panel = not CLB.show_audio_panel
    end
  end

  -- Track Format and Clip Name Format templates now live in
  -- Options > Formats — not here, to save toolbar space (they're set
  -- once and rarely touched again). The "action" buttons (Compare, DME
  -- Recut, Shift Range, Calibrate TC, Generate Items, Conform, Scene
  -- Cuts, Match All, Remove Dups, Consolidate) now live in
  -- draw_left_sidebar(), not here — see its own doc comment for why.
  end
  reaper.ImGui_EndChild(ctx)  -- End toolbar_row2
end

---------------------------------------------------------------------------
-- Draw: Left Sidebar (action buttons)
---------------------------------------------------------------------------
--- All the "do something now" buttons, stacked vertically along the left
--- edge instead of spread across the top toolbar rows — user's own
--- workflow description: the list itself only gets a glance up front and
--- after cleanup, but the action buttons get used constantly while
--- flipping back and forth checking REAPER's own window, so they need to
--- stay reachable even when the CLB window is narrow and parked off to
--- one side of the screen. Load List/Load Audio/Export EDL (and the
--- non-action tool row: FPS, Search, Sources/Tracks/Filters/Audio
--- toggles, Columns, Fit Widths, Timeline, Apply Clip Name Format,
--- Options) deliberately stay in the top toolbar — confirmed via
--- AskUserQuestion — since those are used once per session or need to
--- stay next to the table they affect, not per-click action triggers.
function CLB.draw_left_sidebar()
  local btn_w = -1  -- fill the sidebar's full width
  local btn_h = scale(26)

  -- Clear List / Clear Audio: destructive resets, deliberately their own
  -- red "danger" group at the very top of the sidebar — separate from
  -- the action groups below so they're never confused for a routine
  -- workflow step.
  CLB.push_btn_color("danger")
  local clear_list_clicked = reaper.ImGui_Button(ctx, "Clear List", btn_w, btn_h)
  CLB.pop_btn_color("danger")
  if clear_list_clicked then
    clear_list()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Reset the table to empty (asks for confirmation first)")
  end

  if #CLB.audio_files > 0 then
    CLB.push_btn_color("danger")
    local clear_audio_clicked = reaper.ImGui_Button(ctx, "Clear Audio", btn_w, btn_h)
    CLB.pop_btn_color("danger")
    if clear_audio_clicked then
      clear_audio_files()
    end
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- Compare button (old-vs-new reconform). Opens its own setup/view screen
  -- with independent Load Old/New buttons — always enabled; it never
  -- depends on (or disturbs) whatever is currently loaded in the main table.
  CLB.push_btn_color("recut")
  local compare_clicked = reaper.ImGui_Button(ctx, "Compare...", btn_w, btn_h)
  CLB.pop_btn_color("recut")
  if compare_clicked then
    CLB.show_compare_view = true
    -- Re-point the Track/Reel/Group filter panels at Compare's data when
    -- reopening a cached result (Close already restored them to ROWS).
    if CLB.compare_result then
      CMP.rebuild_filters(CLB.compare_result)
    end
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Compare an OLD vs NEW version (EDL/XML/AAF/.clb)")
    reaper.ImGui_Text(ctx, "and classify Trimmed / Extended / Moved / Added / Deleted.")
    reaper.ImGui_Text(ctx, "Opens its own Load Old/New screen — independent of")
    reaper.ImGui_Text(ctx, "whatever is currently loaded in the main table.")
    reaper.ImGui_EndTooltip(ctx)
  end

  -- DME Recut: no Compare needed — select Reaper track(s), click, and
  -- every visible/filtered event's Src TC range gets COPIED to its Rec
  -- TC range directly (originals untouched — see CLB.dme_recut's own doc
  -- comment for why this works for printed-to-pitch DME-stem cut lists).
  CLB.push_btn_color("recut")
  local dme_recut_clicked = reaper.ImGui_Button(ctx, "DME Recut...##clb_dme_recut", btn_w, btn_h)
  CLB.pop_btn_color("recut")
  if dme_recut_clicked then
    CLB.dme_recut_prepare()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,
      "Select the Reaper track(s) to recut, then click this. Uses the\n"
      .. "currently visible/filtered list directly (filter down to one\n"
      .. "stem's rows first, e.g. search \"DX\") — no Compare needed.\n"
      .. "Opens a Settings dialog (Copy/Cut, Markers) before running.")
  end
  if reaper.ImGui_BeginPopup(ctx, "DME Recut Settings##clb_dme_recut_popup") then
    local pending = CLB.dme_recut_pending
    reaper.ImGui_Text(ctx, "DME Recut Settings")
    if pending then
      reaper.ImGui_TextDisabled(ctx, string.format(
        "%d event(s) on %d selected track(s).", #pending.moves, #pending.sel_tracks))
    end
    reaper.ImGui_Separator(ctx)

    reaper.ImGui_Text(ctx, "Mode:")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Copy (keep originals)##clb_dme_recut_mode_copy", CLB.dme_recut_mode ~= "cut") then
      CLB.dme_recut_mode = "copy"; save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Cut (move originals)##clb_dme_recut_mode_cut", CLB.dme_recut_mode == "cut") then
      CLB.dme_recut_mode = "cut"; save_prefs()
    end

    local chg_mk, new_mk = reaper.ImGui_Checkbox(ctx, "Add Delete/Insert markers##clb_dme_recut_markers", CLB.dme_recut_markers)
    if chg_mk then CLB.dme_recut_markers = new_mk; save_prefs() end

    if pending and pending.dup_warning and pending.dup_warning ~= "" then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFB000FF)
      reaper.ImGui_TextWrapped(ctx, pending.dup_warning)
      reaper.ImGui_PopStyleColor(ctx)
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Run It##clb_dme_recut_run", scale(90), scale(22)) then
      reaper.ImGui_CloseCurrentPopup(ctx)
      CLB.dme_recut_execute()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel##clb_dme_recut_cancel", scale(70), scale(22)) then
      CLB.dme_recut_pending = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  -- Shift Range: the same real-data-moving action Compare's "Offset Old"
  -- already has (CMP.shift_range), exposed here too — Compare mode isn't
  -- part of the DME Recut workflow at all, so that copy was unreachable
  -- from it. Just the move itself; the Compare-only "Offset Old" checkbox
  -- (a VIRTUAL offset for Analyze & Match's matching math) stays in the
  -- Modes popup, since it has no meaning outside Compare. Requires a
  -- Razor Edit or Time Selection (see CMP.shift_range's doc comment) —
  -- no longer shifts a whole track unconditionally.
  CLB.push_btn_color("align")
  local shift_range_clicked = reaper.ImGui_Button(ctx, "Shift Range...##clb_shift_tracks", btn_w, btn_h)
  CLB.pop_btn_color("align")
  if shift_range_clicked then
    reaper.ImGui_OpenPopup(ctx, "Shift Range##clb_shift_tracks_popup")
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,
      "Move everything inside a Razor Edit area, or a Time Selection on\n"
      .. "the Reaper-selected track(s), by N hours — items (split at the\n"
      .. "range edges) AND any project marker/region fully inside that\n"
      .. "time span. E.g. to stage V1's real content out of the way\n"
      .. "before a DME Recut. Undoable (Edit > Undo).")
  end
  if reaper.ImGui_BeginPopup(ctx, "Shift Range##clb_shift_tracks_popup") then
    reaper.ImGui_Text(ctx, "Shift Range")
    reaper.ImGui_TextDisabled(ctx,
      "Make a Razor Edit selection, or a Time Selection + select the\n"
      .. "track(s) to shift in Reaper, first.")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, scale(90))
    local chg_h, new_h = reaper.ImGui_InputInt(ctx, "hours##clb_shift_tracks_h", CLB.offset_old_hours or 10)
    if chg_h then CLB.offset_old_hours = new_h; save_prefs() end
    if reaper.ImGui_Button(ctx, "Shift Now##clb_shift_tracks_go", scale(100), 0) then
      CMP.shift_range(CLB.offset_old_hours or 0, "old")
    end
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Close##clb_shift_tracks_close", scale(70), scale(22)) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  -- Calibrate TC (Anchor) button
  CLB.push_btn_color("align")
  local calib_tc_clicked = reaper.ImGui_Button(ctx, "Calibrate TC...##clb_tc_calib", btn_w, btn_h)
  CLB.pop_btn_color("align")
  if calib_tc_clicked then
    reaper.ImGui_OpenPopup(ctx, "Calibrate TC (Anchor)##clb_tc_calib_popup")
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,
      "Correct each loaded source's TC to match where its content\n"
      .. "actually sits in this Reaper session — one confirmed event<->item\n"
      .. "pair per source (editors export from 0; audio post commonly\n"
      .. "places each reel/episode at its own hour slot). Two independent\n"
      .. "axes: New/Rec TC (the usual case) and Old/Src TC (DME Recut mode\n"
      .. "only, when V1's real content has been staged somewhere other\n"
      .. "than where the EDL's raw Src TC implies).")
  end
  if reaper.ImGui_BeginPopup(ctx, "Calibrate TC (Anchor)##clb_tc_calib_popup") then
    reaper.ImGui_Text(ctx, "Calibrate TC (Anchor)")
    reaper.ImGui_TextDisabled(ctx,
      "Select one event row + one Reaper item that IS that event's\n"
      .. "real content, then Set Anchor — calibrates that row's source.")
    reaper.ImGui_Separator(ctx)

    -- Which axis Set Anchor / Apply below act on. "New (Rec TC)" is the
    -- usual case (everywhere outside DME Recut). "Old (Src TC)" only
    -- matters in DME Recut mode, where Src TC is repurposed as V1's real
    -- Reaper position rather than a position inside an audio source file
    -- (see CLB.dme_recut) — e.g. when V1's own content has been staged at
    -- a different real hour-slot than the EDL's raw Src TC implies.
    CLB.tc_calib_axis = CLB.tc_calib_axis or "rec"
    reaper.ImGui_Text(ctx, "Axis:")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "New (Rec TC)##clb_tc_calib_axis_rec", CLB.tc_calib_axis == "rec") then
      CLB.tc_calib_axis = "rec"
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Old (Src TC, DME Recut)##clb_tc_calib_axis_src", CLB.tc_calib_axis == "src") then
      CLB.tc_calib_axis = "src"
    end
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_Button(ctx, "Set Anchor...##clb_tc_calib_set", scale(140), 0) then
      CLB.calibrate_tc_via_anchor(CLB.tc_calib_axis)
    end
    reaper.ImGui_Separator(ctx)

    -- Second method: no Reaper item needed — select one event row and
    -- type the TC (on the axis above) it SHOULD be (e.g. a Universal
    -- Counting Leader always placed 2 seconds before each hour mark).
    -- Plain InputText (no EnterReturnsTrue — see the Rename Group popup
    -- for why that flag's buffer sync is unreliable); Enter or the Apply
    -- button both submit.
    reaper.ImGui_TextDisabled(ctx,
      "...or select one event row and type the TC it SHOULD be\n"
      .. "on the axis above (no Reaper item needed):")
    reaper.ImGui_SetNextItemWidth(ctx, scale(120))
    local chg_tgt, new_tgt = reaper.ImGui_InputText(ctx, "##clb_tc_calib_target", CLB.tc_calib_target_buf)
    if chg_tgt then CLB.tc_calib_target_buf = new_tgt end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "HH:MM:SS:FF, or 8 digits with no colons (e.g. 00595800)")
    end
    reaper.ImGui_SameLine(ctx)
    local apply_target = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
      or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
    if reaper.ImGui_Button(ctx, "Apply##clb_tc_calib_target_apply", scale(70), 0) then
      apply_target = true
    end
    if apply_target and CLB.tc_calib_target_buf ~= "" then
      CLB.calibrate_tc_to_target(CLB.tc_calib_target_buf, CLB.tc_calib_axis)
    end
    reaper.ImGui_Separator(ctx)

    -- One block per loaded source, each showing BOTH axes independently —
    -- a single source can need a correction on one axis, the other, or
    -- both (e.g. DME Recut: Old/Src needs +10h because V1 was staged
    -- there, New/Rec needs no correction because it already matches V3's
    -- real position).
    local function axis_row(src, ax, row_label)
      local enabled = src[ax.enabled]
      local chg_en, new_en = reaper.ImGui_Checkbox(ctx, row_label .. "##" .. ax.enabled, enabled)
      if chg_en then
        src[ax.enabled] = new_en
        CLB.cached_rows = nil
      end
      reaper.ImGui_SameLine(ctx, scale(190))
      local sign = (src[ax.delta] or 0) >= 0 and "+" or "-"
      local tc = EDL.seconds_to_tc(math.abs(src[ax.delta] or 0), CLB.fps, CLB.is_drop)
      reaper.ImGui_Text(ctx, string.format("%s%s", sign, tc))
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "Clear##" .. ax.enabled) then
        src[ax.enabled] = false
        src[ax.delta]   = 0
        src[ax.note]    = ""
        CLB.cached_rows = nil
      end
      if src[ax.note] and src[ax.note] ~= "" then
        reaper.ImGui_TextDisabled(ctx, "      from: " .. src[ax.note])
      end
    end

    if #CLB.edl_sources == 0 then
      reaper.ImGui_TextDisabled(ctx, "No sources loaded.")
    else
      for i, src in ipairs(CLB.edl_sources) do
        reaper.ImGui_PushID(ctx, i)
        reaper.ImGui_Text(ctx, src.name or "?")
        reaper.ImGui_Indent(ctx, scale(12))
        axis_row(src, CLB.TC_CALIB_AXES.rec, "New (Rec)")
        axis_row(src, CLB.TC_CALIB_AXES.src, "Old (Src)")
        reaper.ImGui_Unindent(ctx, scale(12))
        reaper.ImGui_PopID(ctx)
      end
    end

    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_Button(ctx, "Close##clb_tc_calib_close", scale(70), scale(22)) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- Generate Items button (empty items)
  CLB.push_btn_color("build")
  local gen_items_clicked = reaper.ImGui_Button(ctx, "Generate Items", btn_w, btn_h)
  CLB.pop_btn_color("build")
  if gen_items_clicked then
    generate_items()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Create empty items on REAPER tracks at absolute TC positions")
    reaper.ImGui_Text(ctx, "Metadata stored as P_EXT fields on each take")
    reaper.ImGui_EndTooltip(ctx)
  end

  -- Generate Ref Media button — opens a scope-picker popup (Selected
  -- rows vs. the visible/filtered list, see CLB.ref_media_scope's doc
  -- comment) instead of generating directly, same prepare/popup/execute
  -- split as DME Recut Settings above. One real WAV per event with real
  -- embedded BWF/iXML metadata — the only mode; a "Simple/shared ONE
  -- file" mode existed briefly but was removed at the user's request
  -- (see CLB.generate_reference_media_independent's own doc comment).
  CLB.push_btn_color("build")
  local gen_ref_clicked = reaper.ImGui_Button(ctx, "Generate Ref Media...", btn_w, btn_h)
  CLB.pop_btn_color("build")
  if gen_ref_clicked then
    CLB.generate_reference_media_prepare()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Generate one real silent WAV per event, with embedded")
    reaper.ImGui_Text(ctx, "BWF TimeReference + iXML, so other software reads")
    reaper.ImGui_Text(ctx, "correct Source TC/Scene/Take/Reel after conform/export.")
    reaper.ImGui_Text(ctx, "Opens a dialog to pick Selected rows or the visible list.")
    reaper.ImGui_EndTooltip(ctx)
  end
  if reaper.ImGui_BeginPopup(ctx, "Generate Reference Media##clb_genref_popup") then
    reaper.ImGui_Text(ctx, "Generate Reference Media")
    local scope_count = (CLB.ref_media_scope == "selected")
      and #get_selected_rows()
      or #(get_view_rows() or ROWS)
    reaper.ImGui_TextDisabled(ctx, string.format("%d row(s) in scope.", scope_count))
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_RadioButton(ctx, "Visible list (currently filtered/shown)##clb_genref_scope_visible", CLB.ref_media_scope ~= "selected") then
      CLB.ref_media_scope = "visible"; save_prefs()
    end
    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_RadioButton(ctx, "Selected rows only##clb_genref_scope_selected", CLB.ref_media_scope == "selected") then
      CLB.ref_media_scope = "selected"; save_prefs()
    end

    reaper.ImGui_Separator(ctx)
    -- "Next" (not "Generate"): picking the output folder — a blocking
    -- native dialog — happens AFTER this popup closes, not before it
    -- opened. See CLB.generate_reference_media_pick_folder_and_run's own
    -- comment for why that order is required, not just reordered for
    -- the user's convenience (though it is also that). The actual call
    -- is deferred one step further still, to AFTER EndPopup below (not
    -- called directly from inside this still-open popup) — same
    -- "don't call a blocking native dialog right across an ImGui
    -- Begin/End boundary" caution as the OpenPopup fix above, just the
    -- other direction (into a popup this time, not out of one).
    if reaper.ImGui_Button(ctx, "Next: Choose Folder...##clb_genref_go", scale(140), scale(22)) then
      reaper.ImGui_CloseCurrentPopup(ctx)
      CLB.ref_media_want_folder_pick = true
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel##clb_genref_cancel", scale(70), scale(22)) then
      CLB.ref_media_pending = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
  if CLB.ref_media_want_folder_pick then
    CLB.ref_media_want_folder_pick = false
    CLB.generate_reference_media_pick_folder_and_run()
  end

  -- Conform Matched buttons (with audio)
  local has_matches = false
  for _, row in ipairs(ROWS) do
    if row.match_status == "Found" or row.match_status == "Fallback" or row.match_status == "Multiple" then
      has_matches = true
      break
    end
  end

  if has_matches then
    CLB.push_btn_color("build")
    local conform_all_clicked = reaper.ImGui_Button(ctx, "Conform All", btn_w, btn_h)
    CLB.pop_btn_color("build")
    if conform_all_clicked then
      conform_matched_items(false)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Insert matched audio files as items")
      reaper.ImGui_Text(ctx, "Multiple matches = multiple takes on same item")
      reaper.ImGui_EndTooltip(ctx)
    end

    CLB.push_btn_color("build")
    local conform_sel_clicked = reaper.ImGui_Button(ctx, "Conform Sel", btn_w, btn_h)
    CLB.pop_btn_color("build")
    if conform_sel_clicked then
      conform_matched_items(true)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Insert matched audio for selected rows only")
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  -- Scene Cut Track button
  if #ROWS > 0 then
    CLB.push_btn_color("build")
    local scene_cuts_clicked = reaper.ImGui_Button(ctx, "Scene Cuts", btn_w, btn_h)
    CLB.pop_btn_color("build")
    if scene_cuts_clicked then
      create_scene_cut_track()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Create a 'Scene Cuts' track with empty items for each scene")
      reaper.ImGui_Text(ctx, "Clip name format: EP_Scene_Shot_Ttake[_Camera]")
      reaper.ImGui_Text(ctx, "Example: 06_01B_01_T05_A")
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  -- Match All button (only show when both EDL and audio are loaded)
  if #ROWS > 0 and #CLB.audio_files > 0 then
    CLB.push_btn_color("build")
    local match_all_clicked = reaper.ImGui_Button(ctx, "Match All", btn_w, btn_h)
    CLB.pop_btn_color("build")
    if match_all_clicked then
      match_audio_files()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Re-run matching algorithm on all EDL events")
      reaper.ImGui_EndTooltip(ctx)
    end
  end

  -- Auto Match (Load From Reaper's persisted "match right after loading"
  -- setting) — lives here with the other match controls (user's own
  -- request), not next to the Load From Reaper button. Always shown,
  -- unlike Match All, since it's a setting, not an action.
  local chg_ram, new_ram = reaper.ImGui_Checkbox(ctx, "Auto Match##clb_ref_load_auto_match", CLB.ref_load_auto_match)
  if chg_ram then CLB.ref_load_auto_match = new_ram; save_prefs() end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,
      "After \"Load From Reaper\", also run Find Match — loads Audio\n"
      .. "first (same folder picker as \"Load Audio...\") if none is\n"
      .. "loaded yet.")
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- Remove Duplicates button
  CLB.push_btn_color("list")
  local remove_dups_clicked = reaper.ImGui_Button(ctx, "Remove Dups", btn_w, btn_h)
  CLB.pop_btn_color("list")
  if remove_dups_clicked then
    remove_duplicates()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Remove duplicate events (matching Reel + Src TC + Rec TC + Clip Name)")
    reaper.ImGui_EndTooltip(ctx)
  end

  -- Consolidate by Group button
  CLB.push_btn_color("list")
  local consolidate_clicked = reaper.ImGui_Button(ctx, "Consolidate", btn_w, btn_h)
  CLB.pop_btn_color("list")
  if consolidate_clicked then
    consolidate_by_group()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Consolidate tracks by group (bin-pack + renumber)")
    reaper.ImGui_EndTooltip(ctx)
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Spacing(ctx)

  -- Reaper item <-> event links, their own magenta "link" group at the
  -- very bottom (user's own placement request). Link attaches selected
  -- items to EXISTING rows (CLB.link_reaper_items_selection); Reveal and
  -- Follow go the other way (CLB.reveal_reaper_item).
  CLB.push_btn_color("link")
  local link_items_clicked = reaper.ImGui_Button(ctx, "Link Reaper Items", btn_w, btn_h)
  CLB.pop_btn_color("link")
  if link_items_clicked then
    CLB.link_reaper_items_selection()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Link selected Reaper item(s) to the events already in this")
    reaper.ImGui_Text(ctx, "list (matched on Src + Rec TC), so clicking an event's Clip")
    reaper.ImGui_Text(ctx, "Name jumps to its item. Saved in the .clb.")
    reaper.ImGui_EndTooltip(ctx)
  end

  CLB.push_btn_color("link")
  local reveal_clicked = reaper.ImGui_Button(ctx, "Reveal Item##clb_reveal_item", btn_w, btn_h)
  CLB.pop_btn_color("link")
  if reveal_clicked then
    CLB._follow_sig = CLB._reaper_sel_sig() -- don't re-reveal it via Follow next frame
    CLB.reveal_reaper_selection(false)
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,
      "Jump this list to the event(s) of the item(s) selected in Reaper.\n"
      .. "One item: matched on the spot and linked if it isn't yet.\n"
      .. "Several items: already-linked ones only (use Link first).")
  end

  local chg_fr, new_fr = reaper.ImGui_Checkbox(ctx, "Follow Reaper##clb_follow_reaper_sel", CLB.follow_reaper_sel)
  if chg_fr then
    CLB.follow_reaper_sel = new_fr
    CLB._follow_sig = nil -- re-reveal whatever is selected right now
    CLB._sel_synced_version = SEL.version -- ...rather than pushing CLB's old selection to Reaper
    CLB.follow_status = ""
    save_prefs()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,
      "Reveal automatically: selecting an item in Reaper jumps this\n"
      .. "list to its event(s). Unlinked items are matched on the spot\n"
      .. "(same rules as Link Reaper Items) and linked — save the .clb\n"
      .. "to keep it.")
  end
  if CLB.follow_status ~= "" then
    -- Wrapped dim text (narrow sidebar) — same PushStyleColor +
    -- TextWrapped pattern as the DME Recut popup's warning text.
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x9A9A9AFF)
    reaper.ImGui_TextWrapped(ctx, CLB.follow_status)
    reaper.ImGui_PopStyleColor(ctx)
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
    CLB.cached_rows = nil
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide All##clb_src_none") then
    for _, src in ipairs(CLB.edl_sources) do src.visible = false end
    CLB.cached_rows = nil
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
        CLB.cached_rows = nil
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
    CLB.cached_rows = nil
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide All##clb_trk_none") then
    for _, tf in ipairs(CLB.track_filters) do tf.visible = false end
    CLB.cached_rows = nil
  end

  -- Track checkboxes in horizontal scrollable region
  local row_height = scale(38)  -- Extra height for scrollbar
  local flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
  local open_track_ctx = false  -- Deferred popup opening (must be outside BeginChild)
  if reaper.ImGui_BeginChild(ctx, "##track_filter_scroll", 0, row_height, 0, flags) then
    -- Right-click to rename or delete
    for i, tf in ipairs(CLB.track_filters) do
      if i > 1 then reaper.ImGui_SameLine(ctx) end
      local label = string.format("%s (%d)##clb_trk_%d", tf.name, tf.count, i)
      local changed, new_val = reaper.ImGui_Checkbox(ctx, label, tf.visible)
      if changed then
        tf.visible = new_val
        CLB.cached_rows = nil
      end
      -- Right-click context menu (deferred)
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Right-click for options")
        if reaper.ImGui_IsMouseClicked(ctx, 1) then
          CLB.context_filter = { type = "track", idx = i, name = tf.name }
          open_track_ctx = true
        end
      end
    end
    reaper.ImGui_EndChild(ctx)
  end

  -- Open popup outside BeginChild scope
  if open_track_ctx then
    reaper.ImGui_OpenPopup(ctx, "Track Filter Context##clb_track_ctx")
  end

  -- Track filter context menu
  local open_track_rename, open_track_delete, open_track_batch, open_track_consolidate = false, false, false, false
  if reaper.ImGui_BeginPopup(ctx, "Track Filter Context##clb_track_ctx") then
    if CLB.context_filter and CLB.context_filter.type == "track" then
      reaper.ImGui_Text(ctx, "Track: " .. CLB.context_filter.name)
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_MenuItem(ctx, "Rename...") then
        CLB.rename_filter = {
          type = "track",
          idx = CLB.context_filter.idx,
          old_name = CLB.context_filter.name,
          buf = CLB.context_filter.name
        }
        open_track_rename = true
      end
      if reaper.ImGui_MenuItem(ctx, "Delete...") then
        CLB.delete_filter = {
          type = "track",
          idx = CLB.context_filter.idx,
          name = CLB.context_filter.name
        }
        open_track_delete = true
      end
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_MenuItem(ctx, "Batch Rename All Tracks...") then
        CLB.batch_rename = {
          type = "track",
          find = "",
          replace = ""
        }
        open_track_batch = true
      end
      if reaper.ImGui_MenuItem(ctx, "Consolidate Tracks...") then
        -- Initialize consolidation state with all tracks unselected
        local selected = {}
        for i = 1, #CLB.track_filters do
          selected[i] = false
        end
        CLB.consolidate_tracks = {
          selected = selected,
          prefix = "A",  -- Default prefix
        }
        open_track_consolidate = true
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end

  -- Deferred OpenPopup (must be at child window scope, not inside context menu popup)
  if open_track_rename then reaper.ImGui_OpenPopup(ctx, "Rename Track##clb_rename_track") end
  if open_track_delete then reaper.ImGui_OpenPopup(ctx, "Confirm Delete Track##clb_del_track") end
  if open_track_batch then reaper.ImGui_OpenPopup(ctx, "Batch Rename Tracks##clb_batch_track") end
  if open_track_consolidate then reaper.ImGui_OpenPopup(ctx, "Consolidate Tracks##clb_consolidate") end

  -- Rename track popup
  if CLB.rename_filter and CLB.rename_filter.type == "track" then
    if reaper.ImGui_BeginPopup(ctx, "Rename Track##clb_rename_track") then
      reaper.ImGui_Text(ctx, "Rename track:")
      reaper.ImGui_SetNextItemWidth(ctx, scale(150))
      -- Plain InputText (no EnterReturnsTrue) — that flag's returned buffer
      -- was only reliable on the exact frame Enter was pressed, so clicking
      -- OK after typing (without pressing Enter) read back the stale
      -- original name and silently no-op'd as "unchanged".
      local chg, new_buf = reaper.ImGui_InputText(ctx, "##rename_input", CLB.rename_filter.buf)
      if chg then CLB.rename_filter.buf = new_buf end

      -- Focus input on first frame
      if not CLB.rename_filter.focused then
        reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
        CLB.rename_filter.focused = true
      end

      -- Apply on Enter or OK button
      local apply = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
        or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
      if reaper.ImGui_Button(ctx, "OK", scale(60), 0) then apply = true end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
        CLB.rename_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      if apply and CLB.rename_filter then
        local old_name = CLB.rename_filter.old_name
        local new_name = CLB.rename_filter.buf
        if new_name ~= old_name and new_name ~= "" then
          -- Update filter name
          CLB.track_filters[CLB.rename_filter.idx].name = new_name
          -- Update all ROWS with old track name
          for _, row in ipairs(ROWS) do
            if row.track == old_name then
              row.track = new_name
            end
          end
          CLB.cached_rows = nil
        end
        CLB.rename_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    else
      -- Popup was closed externally
      CLB.rename_filter = nil
    end
  end

  -- Delete track confirmation popup
  if CLB.delete_filter and CLB.delete_filter.type == "track" then
    if reaper.ImGui_BeginPopup(ctx, "Confirm Delete Track##clb_del_track") then
      reaper.ImGui_Text(ctx, string.format(
        "Delete track '%s' and all %d events?",
        CLB.delete_filter.name,
        CLB.track_filters[CLB.delete_filter.idx] and CLB.track_filters[CLB.delete_filter.idx].count or 0
      ))
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, "Delete", scale(60), 0) then
        -- Remove all rows with this track
        local del_name = CLB.delete_filter.name
        local new_rows = {}
        for _, row in ipairs(ROWS) do
          if row.track ~= del_name then
            new_rows[#new_rows + 1] = row
          end
        end
        ROWS = new_rows
        _rebuild_track_filters()
        CLB.cached_rows = nil
        undo_snapshot()
        CLB.delete_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
        CLB.delete_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_EndPopup(ctx)
    else
      CLB.delete_filter = nil
    end
  end

  -- Batch rename tracks popup
  if CLB.batch_rename and CLB.batch_rename.type == "track" then
    if reaper.ImGui_BeginPopup(ctx, "Batch Rename Tracks##clb_batch_track") then
      reaper.ImGui_Text(ctx, "Find and replace in all track names:")
      reaper.ImGui_Separator(ctx)

      reaper.ImGui_Text(ctx, "Find:")
      reaper.ImGui_SameLine(ctx, scale(80))
      reaper.ImGui_SetNextItemWidth(ctx, scale(150))
      local chg_f, new_f = reaper.ImGui_InputText(ctx, "##batch_find", CLB.batch_rename.find)
      if chg_f then CLB.batch_rename.find = new_f end

      reaper.ImGui_Text(ctx, "Replace:")
      reaper.ImGui_SameLine(ctx, scale(80))
      reaper.ImGui_SetNextItemWidth(ctx, scale(150))
      local chg_r, new_r = reaper.ImGui_InputText(ctx, "##batch_replace", CLB.batch_rename.replace)
      if chg_r then CLB.batch_rename.replace = new_r end

      -- Preview count
      local match_count = 0
      if CLB.batch_rename.find ~= "" then
        for _, row in ipairs(ROWS) do
          if row.track and row.track:find(CLB.batch_rename.find, 1, true) then
            match_count = match_count + 1
          end
        end
      end
      reaper.ImGui_TextDisabled(ctx, string.format("Will affect %d events", match_count))

      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, "Apply", scale(60), 0) then
        if CLB.batch_rename.find ~= "" then
          for _, row in ipairs(ROWS) do
            if row.track then
              row.track = row.track:gsub(CLB.batch_rename.find:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"), CLB.batch_rename.replace)
            end
          end
          _rebuild_track_filters()
          CLB.cached_rows = nil
          undo_snapshot()
        end
        CLB.batch_rename = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
        CLB.batch_rename = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    else
      CLB.batch_rename = nil
    end
  end

  -- Consolidate tracks popup
  if CLB.consolidate_tracks then
    if reaper.ImGui_BeginPopup(ctx, "Consolidate Tracks##clb_consolidate") then
      reaper.ImGui_Text(ctx, "Consolidate selected tracks into minimal non-overlapping tracks:")
      reaper.ImGui_TextDisabled(ctx, "Events on selected tracks will be merged into as few tracks")
      reaper.ImGui_TextDisabled(ctx, "as possible without overlapping in time.")
      reaper.ImGui_Separator(ctx)

      -- Track selection (scrollable list)
      reaper.ImGui_Text(ctx, "Select tracks to consolidate:")
      local list_h = math.min(#CLB.track_filters, 10) * reaper.ImGui_GetTextLineHeightWithSpacing(ctx) + 4
      if reaper.ImGui_BeginChild(ctx, "##consolidate_track_list", scale(300), list_h, reaper.ImGui_ChildFlags_Borders()) then
        for i, tf in ipairs(CLB.track_filters) do
          local label = string.format("%s (%d events)##cons_%d", tf.name, tf.count, i)
          local chg, new_sel = reaper.ImGui_Checkbox(ctx, label, CLB.consolidate_tracks.selected[i] or false)
          if chg then
            CLB.consolidate_tracks.selected[i] = new_sel
          end
        end
        reaper.ImGui_EndChild(ctx)
      end

      -- Select All / None buttons
      if reaper.ImGui_SmallButton(ctx, "Select All##cons") then
        for i = 1, #CLB.track_filters do
          CLB.consolidate_tracks.selected[i] = true
        end
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "Select None##cons") then
        for i = 1, #CLB.track_filters do
          CLB.consolidate_tracks.selected[i] = false
        end
      end

      reaper.ImGui_Separator(ctx)

      -- New track prefix
      reaper.ImGui_Text(ctx, "New track prefix:")
      reaper.ImGui_SameLine(ctx, scale(120))
      reaper.ImGui_SetNextItemWidth(ctx, scale(100))
      local chg_p, new_p = reaper.ImGui_InputText(ctx, "##cons_prefix", CLB.consolidate_tracks.prefix)
      if chg_p then CLB.consolidate_tracks.prefix = new_p end

      -- Preview: count selected tracks and events
      local sel_track_count = 0
      local sel_event_count = 0
      local sel_track_names = {}
      for i, tf in ipairs(CLB.track_filters) do
        if CLB.consolidate_tracks.selected[i] then
          sel_track_count = sel_track_count + 1
          sel_event_count = sel_event_count + tf.count
          sel_track_names[tf.name] = true
        end
      end

      -- Calculate estimated result (bin-packing preview)
      local estimated_tracks = 0
      if sel_track_count > 0 then
        -- Collect events from selected tracks
        local events = {}
        for _, row in ipairs(ROWS) do
          if sel_track_names[row.track] then
            local ri_sec = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
            local ro_sec = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
            table.insert(events, { row = row, start = ri_sec, stop = ro_sec })
          end
        end
        -- Sort by start time
        table.sort(events, function(a, b) return a.start < b.start end)
        -- Bin-packing: count required tracks
        local track_ends = {}  -- track_ends[i] = end time of track i
        for _, evt in ipairs(events) do
          local placed = false
          for ti, te in ipairs(track_ends) do
            if evt.start >= te then
              track_ends[ti] = evt.stop
              placed = true
              break
            end
          end
          if not placed then
            table.insert(track_ends, evt.stop)
          end
        end
        estimated_tracks = #track_ends
      end

      reaper.ImGui_TextDisabled(ctx, string.format(
        "Selected: %d tracks, %d events -> ~%d track(s)",
        sel_track_count, sel_event_count, estimated_tracks))

      reaper.ImGui_Separator(ctx)

      -- Apply / Cancel buttons
      local can_apply = sel_track_count > 0 and CLB.consolidate_tracks.prefix ~= ""
      if not can_apply then
        reaper.ImGui_BeginDisabled(ctx)
      end
      if reaper.ImGui_Button(ctx, "Consolidate", scale(80), 0) then
        -- Perform consolidation
        local prefix = CLB.consolidate_tracks.prefix

        -- Collect events from selected tracks
        local events = {}
        for _, row in ipairs(ROWS) do
          if sel_track_names[row.track] then
            local ri_sec = EDL.tc_to_seconds(row.rec_tc_in, CLB.fps, CLB.is_drop)
            local ro_sec = EDL.tc_to_seconds(row.rec_tc_out, CLB.fps, CLB.is_drop)
            table.insert(events, { row = row, start = ri_sec, stop = ro_sec })
          end
        end

        -- Sort by start time
        table.sort(events, function(a, b) return a.start < b.start end)

        -- Bin-packing: assign track numbers
        local track_ends = {}  -- track_ends[i] = end time of track i
        for _, evt in ipairs(events) do
          local assigned_track = nil
          for ti, te in ipairs(track_ends) do
            if evt.start >= te then
              track_ends[ti] = evt.stop
              assigned_track = ti
              break
            end
          end
          if not assigned_track then
            table.insert(track_ends, evt.stop)
            assigned_track = #track_ends
          end
          -- Assign new track name
          evt.row.track = prefix .. tostring(assigned_track)
        end

        -- Rebuild filters and refresh
        _rebuild_track_filters()
        CLB.cached_rows = nil
        undo_snapshot()

        CLB.consolidate_tracks = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      if not can_apply then
        reaper.ImGui_EndDisabled(ctx)
      end

      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
        CLB.consolidate_tracks = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    else
      CLB.consolidate_tracks = nil
    end
  end
end

---------------------------------------------------------------------------
-- Draw: Reel Filter Panel
---------------------------------------------------------------------------
local function draw_reel_filter_panel()
  if not CLB.show_reel_filter or #CLB.reel_filters == 0 then return end

  reaper.ImGui_Separator(ctx)

  -- Count visible/hidden
  local visible_count = 0
  for _, rf in ipairs(CLB.reel_filters) do
    if rf.visible then visible_count = visible_count + 1 end
  end

  reaper.ImGui_Text(ctx, string.format("Reel Filter (%d):", #CLB.reel_filters))
  reaper.ImGui_SameLine(ctx)

  -- Show All / Hide All
  if reaper.ImGui_SmallButton(ctx, "Show All##clb_reel_all") then
    for _, rf in ipairs(CLB.reel_filters) do rf.visible = true end
    CLB.cached_rows = nil
    CLB.reel_sel = {}; CLB.reel_sel_anchor = nil
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide All##clb_reel_none") then
    for _, rf in ipairs(CLB.reel_filters) do rf.visible = false end
    CLB.cached_rows = nil
    CLB.reel_sel = {}; CLB.reel_sel_anchor = nil
  end

  -- Reel list
  -- [ ] checkbox square   → toggles visible only
  -- Click on text         → selects this reel (clears others); sets anchor
  -- Shift+click on text   → range-select from anchor to here
  -- Ctrl/Cmd+click text   → toggle this reel in/out of selection
  local dl_panel = reaper.ImGui_GetWindowDrawList(ctx)
  for i, rf in ipairs(CLB.reel_filters) do
    local display_name = rf.name ~= "" and rf.name or "(empty)"
    local is_sel = CLB.reel_sel[i] or false

    -- Full-row highlight
    if is_sel then
      local rx, ry = reaper.ImGui_GetCursorScreenPos(ctx)
      local rw, _  = reaper.ImGui_GetContentRegionAvail(ctx)
      local rlh = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
      reaper.ImGui_DrawList_AddRectFilled(dl_panel, rx - 4, ry, rx + rw + 4, ry + rlh, 0x3366CC50)
    end

    -- [ ] Checkbox: visible only
    local cb_changed, new_vis = reaper.ImGui_Checkbox(ctx, "##reel_cb_" .. i, rf.visible)
    if cb_changed then
      rf.visible = new_vis
      CLB.cached_rows = nil
    end
    local cb_hovered = reaper.ImGui_IsItemHovered(ctx)

    reaper.ImGui_SameLine(ctx, 0, 4)

    -- Text: selection only
    local sel_label = string.format("%s (%d)##reel_sel_%d", display_name, rf.count, i)
    if is_sel then
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),        0x3366CC80)
      reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x4477DD90)
    end
    local sel_clicked = reaper.ImGui_Selectable(ctx, sel_label, is_sel, 0, 0, 0)
    if is_sel then reaper.ImGui_PopStyleColor(ctx, 2) end

    if sel_clicked then
      local shift, ctrl = _mods()
      if shift then
        local anchor = CLB.reel_sel_anchor or i
        local lo = math.min(anchor, i)
        local hi = math.max(anchor, i)
        for j = lo, hi do CLB.reel_sel[j] = true end
      elseif ctrl then
        if CLB.reel_sel[i] then CLB.reel_sel[i] = nil
        else CLB.reel_sel[i] = true end
        CLB.reel_sel_anchor = i
      else
        CLB.reel_sel = { [i] = true }
        CLB.reel_sel_anchor = i
      end
    end
    local sel_hovered = reaper.ImGui_IsItemHovered(ctx)

    if cb_hovered or sel_hovered then
      local sel_count = 0
      for _ in pairs(CLB.reel_sel) do sel_count = sel_count + 1 end
      if sel_count > 1 then
        reaper.ImGui_SetTooltip(ctx, sel_count .. " reels selected — right-click to check/uncheck")
      else
        reaper.ImGui_SetTooltip(ctx, "[ ] to check/uncheck  |  Shift+click to select range")
      end
      if reaper.ImGui_IsMouseClicked(ctx, 1) then
        if not CLB.reel_sel[i] then
          CLB.reel_sel = { [i] = true }
          CLB.reel_sel_anchor = i
        end
        CLB.context_filter = { type = "reel", idx = i, name = rf.name }
        reaper.ImGui_OpenPopup(ctx, "Reel Filter Context##clb_reel_ctx")
      end
    end
  end

  -- Reel filter context menu
  if reaper.ImGui_BeginPopup(ctx, "Reel Filter Context##clb_reel_ctx") then
    if CLB.context_filter and CLB.context_filter.type == "reel" then
      local sel_count = 0
      for _ in pairs(CLB.reel_sel) do sel_count = sel_count + 1 end
      if sel_count > 1 then
        reaper.ImGui_TextDisabled(ctx, sel_count .. " reels selected")
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_MenuItem(ctx, "Check selected") then
          for idx in pairs(CLB.reel_sel) do
            if CLB.reel_filters[idx] then CLB.reel_filters[idx].visible = true end
          end
          CLB.cached_rows = nil; CLB.reel_sel = {}
        end
        if reaper.ImGui_MenuItem(ctx, "Uncheck selected") then
          for idx in pairs(CLB.reel_sel) do
            if CLB.reel_filters[idx] then CLB.reel_filters[idx].visible = false end
          end
          CLB.cached_rows = nil; CLB.reel_sel = {}
        end
        reaper.ImGui_Separator(ctx)
      end
      local display_name = CLB.context_filter.name ~= "" and CLB.context_filter.name or "(empty)"
      reaper.ImGui_Text(ctx, "Reel: " .. display_name)
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_MenuItem(ctx, "Rename...") then
        CLB.rename_filter = {
          type = "reel",
          idx = CLB.context_filter.idx,
          old_name = CLB.context_filter.name,
          buf = CLB.context_filter.name
        }
        reaper.ImGui_OpenPopup(ctx, "Rename Reel##clb_rename_reel")
      end
      if reaper.ImGui_MenuItem(ctx, "Delete...") then
        CLB.delete_filter = {
          type = "reel",
          idx = CLB.context_filter.idx,
          name = CLB.context_filter.name
        }
        reaper.ImGui_OpenPopup(ctx, "Confirm Delete Reel##clb_del_reel")
      end
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_MenuItem(ctx, "Batch Rename All Reels...") then
        CLB.batch_rename = {
          type = "reel",
          find = "",
          replace = ""
        }
        reaper.ImGui_OpenPopup(ctx, "Batch Rename Reels##clb_batch_reel")
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end

  -- Rename reel popup
  if CLB.rename_filter and CLB.rename_filter.type == "reel" then
    if reaper.ImGui_BeginPopup(ctx, "Rename Reel##clb_rename_reel") then
      reaper.ImGui_Text(ctx, "Rename reel:")
      reaper.ImGui_SetNextItemWidth(ctx, scale(150))
      local chg, new_buf = reaper.ImGui_InputText(ctx, "##rename_reel_input", CLB.rename_filter.buf,
        reaper.ImGui_InputTextFlags_EnterReturnsTrue())
      if chg then CLB.rename_filter.buf = new_buf end

      -- Focus input on first frame
      if not CLB.rename_filter.focused then
        reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
        CLB.rename_filter.focused = true
      end

      -- Apply on Enter or OK button
      local apply = chg  -- Enter was pressed
      if reaper.ImGui_Button(ctx, "OK", scale(60), 0) then apply = true end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
        CLB.rename_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      if apply and CLB.rename_filter then
        local old_name = CLB.rename_filter.old_name
        local new_name = CLB.rename_filter.buf
        if new_name ~= old_name then
          -- Update filter name
          CLB.reel_filters[CLB.rename_filter.idx].name = new_name
          -- Update all ROWS with old reel name
          for _, row in ipairs(ROWS) do
            if row.reel == old_name then
              row.reel = new_name
            end
          end
          CLB.cached_rows = nil
          undo_snapshot()
        end
        CLB.rename_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    else
      CLB.rename_filter = nil
    end
  end

  -- Delete reel confirmation popup
  if CLB.delete_filter and CLB.delete_filter.type == "reel" then
    if reaper.ImGui_BeginPopup(ctx, "Confirm Delete Reel##clb_del_reel") then
      reaper.ImGui_Text(ctx, string.format(
        "Delete reel '%s' and all %d events?",
        CLB.delete_filter.name ~= "" and CLB.delete_filter.name or "(empty)",
        CLB.reel_filters[CLB.delete_filter.idx] and CLB.reel_filters[CLB.delete_filter.idx].count or 0
      ))
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, "Delete", scale(60), 0) then
        -- Remove all rows with this reel
        local del_name = CLB.delete_filter.name
        local new_rows = {}
        for _, row in ipairs(ROWS) do
          if row.reel ~= del_name then
            new_rows[#new_rows + 1] = row
          end
        end
        ROWS = new_rows
        _rebuild_reel_filters()
        _rebuild_track_filters()
        CLB.cached_rows = nil
        undo_snapshot()
        CLB.delete_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
        CLB.delete_filter = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_EndPopup(ctx)
    else
      CLB.delete_filter = nil
    end
  end

  -- Batch rename reels popup
  if CLB.batch_rename and CLB.batch_rename.type == "reel" then
    if reaper.ImGui_BeginPopup(ctx, "Batch Rename Reels##clb_batch_reel") then
      reaper.ImGui_Text(ctx, "Find and replace in all reel names:")
      reaper.ImGui_Separator(ctx)

      reaper.ImGui_Text(ctx, "Find:")
      reaper.ImGui_SameLine(ctx, scale(80))
      reaper.ImGui_SetNextItemWidth(ctx, scale(150))
      local chg_f, new_f = reaper.ImGui_InputText(ctx, "##batch_reel_find", CLB.batch_rename.find)
      if chg_f then CLB.batch_rename.find = new_f end

      reaper.ImGui_Text(ctx, "Replace:")
      reaper.ImGui_SameLine(ctx, scale(80))
      reaper.ImGui_SetNextItemWidth(ctx, scale(150))
      local chg_r, new_r = reaper.ImGui_InputText(ctx, "##batch_reel_replace", CLB.batch_rename.replace)
      if chg_r then CLB.batch_rename.replace = new_r end

      -- Preview count
      local match_count = 0
      if CLB.batch_rename.find ~= "" then
        for _, row in ipairs(ROWS) do
          if row.reel and row.reel:find(CLB.batch_rename.find, 1, true) then
            match_count = match_count + 1
          end
        end
      end
      reaper.ImGui_TextDisabled(ctx, string.format("Will affect %d events", match_count))

      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, "Apply", scale(60), 0) then
        if CLB.batch_rename.find ~= "" then
          for _, row in ipairs(ROWS) do
            if row.reel then
              row.reel = row.reel:gsub(CLB.batch_rename.find:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"), CLB.batch_rename.replace)
            end
          end
          _rebuild_reel_filters()
          CLB.cached_rows = nil
          undo_snapshot()
        end
        CLB.batch_rename = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
        CLB.batch_rename = nil
        reaper.ImGui_CloseCurrentPopup(ctx)
      end

      reaper.ImGui_EndPopup(ctx)
    else
      CLB.batch_rename = nil
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
    reaper.ImGui_TextDisabled(ctx, "Click 'Load EDL...', 'Load XML...', or 'Load AAF...' to open a timeline file (CMX3600 EDL, FCP7 XML, Resolve XML, AAF).")
    return
  end

  if row_count == 0 then
    reaper.ImGui_TextDisabled(ctx, "No events match the current filter.")
    return
  end

  -- Build visible columns list
  local visible_cols = {}
  for _, col in ipairs(EDL_COL_ORDER) do
    if EDL_COL_VISIBILITY[col] then
      table.insert(visible_cols, col)
    end
  end
  local visible_count = #visible_cols

  if visible_count == 0 then
    reaper.ImGui_TextDisabled(ctx, "No columns visible. Click 'Cols' to show columns.")
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

  -- Available size for table
  local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local height = table_height or avail_h

  -- Fit Widths: fixed columns (Reel/Track/Edit/TC/Level) stay at their default widths;
  -- stretchy columns (Clip Name, Notes, Source File, Matched File, Group) share the
  -- remaining window width proportionally, always computed from DEFAULT_COL_WIDTH so
  -- repeated clicks give the same result (no drift from accumulated rounding errors).
  -- Table ID is bumped each time so ImGui creates fresh column state and respects the
  -- updated COL_WIDTH values (cached tables ignore TableSetupColumn width parameter).
  if CLB.edl_fit_content then
    local scale_ratio = current_font_size / 13.0
    local fixed_base = 0   -- sum of default widths for fixed-width visible columns
    local stretch_base = 0 -- sum of default widths for stretchy visible columns
    for _, col in ipairs(visible_cols) do
      local def_w = DEFAULT_COL_WIDTH[col] or 80
      if FIT_FIXED_COLS[col] then
        fixed_base = fixed_base + def_w
      else
        stretch_base = stretch_base + def_w
      end
    end
    -- remaining base units available for stretchy columns
    local remaining_base = (avail_w / scale_ratio) - fixed_base
    for _, col in ipairs(visible_cols) do
      local def_w = DEFAULT_COL_WIDTH[col] or 80
      if FIT_FIXED_COLS[col] then
        COL_WIDTH[col] = def_w
      elseif stretch_base > 0 then
        COL_WIDTH[col] = math.max(20, math.floor(def_w / stretch_base * remaining_base))
      end
    end
    CLB.edl_table_gen = (CLB.edl_table_gen or 0) + 1
    CLB.edl_fit_content = false
  end

  local table_id = "clb_table_" .. (CLB.edl_table_gen or 0)
  if not reaper.ImGui_BeginTable(ctx, table_id, visible_count, flags, 0, height) then
    return
  end

  -- Setup columns (only visible ones, in display order)
  for _, col in ipairs(visible_cols) do
    local w = scale(COL_WIDTH[col] or DEFAULT_COL_WIDTH[col] or 80)
    local col_flags = reaper.ImGui_TableColumnFlags_WidthFixed()
    if TC_COLS[col] then
      col_flags = col_flags | reaper.ImGui_TableColumnFlags_NoResize()
    end
    reaper.ImGui_TableSetupColumn(ctx, HEADER_LABELS[col] or "", col_flags, w)
  end

  -- Headers (using TableHeader for drag-reorder support + sort indicators)
  reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
  reaper.ImGui_TableNextRow(ctx)
  for disp_idx, col in ipairs(visible_cols) do
    reaper.ImGui_TableSetColumnIndex(ctx, disp_idx - 1)

    -- Sort indicator
    local sort_indicator = ""
    for si, sc in ipairs(SORT_STATE.columns) do
      if sc.col_id == col then
        local arrow = sc.ascending and " ^" or " v"
        if #SORT_STATE.columns > 1 then
          sort_indicator = string.format(" [%d]%s", si, arrow)
        else
          sort_indicator = arrow
        end
        break
      end
    end

    local label = (HEADER_LABELS[col] or "") .. sort_indicator
    reaper.ImGui_TableHeader(ctx, label)

    -- Click to sort
    if reaper.ImGui_IsItemClicked(ctx, 0) then
      local shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Shift())
      toggle_sort(col, shift)
    end
  end

  -- ListClipper for virtualization
  if list_clipper and not reaper.ImGui_ValidatePtr(list_clipper, "ImGui_ListClipper*") then
    list_clipper = reaper.ImGui_CreateListClipper(ctx)
  end

  -- Find scroll target row index (from timeline click → table needs to scroll)
  local scroll_target_idx = nil
  if CLB.scroll_to_row then
    for i, row in ipairs(view_rows) do
      if row.__guid == CLB.scroll_to_row then scroll_target_idx = i; break end
    end
    CLB.scroll_to_row = nil
  end
  -- Keyboard nav target (CLB.table_nav): scroll only as far as needed to
  -- keep it in view, and keep the clipper on (IncludeItemByIndex forces
  -- just that row to be laid out) — holding an arrow key would otherwise
  -- render every row every frame and re-center the list on each step.
  local nav_target_idx = nil
  if CLB.nav_scroll_to_row then
    for i, row in ipairs(view_rows) do
      if row.__guid == CLB.nav_scroll_to_row then nav_target_idx = i; break end
    end
    CLB.nav_scroll_to_row = nil
  end

  -- Disable clipper for this frame if we need to scroll to a row
  local use_clipper = list_clipper and row_count > 100 and not scroll_target_idx
  local cs, ce

  if use_clipper then
    reaper.ImGui_ListClipper_Begin(list_clipper, row_count)
    if nav_target_idx and reaper.ImGui_ListClipper_IncludeItemByIndex then
      reaper.ImGui_ListClipper_IncludeItemByIndex(list_clipper, nav_target_idx - 1)
    end
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
      if i == scroll_target_idx then
        reaper.ImGui_SetScrollHereY(ctx, 0.5)
      elseif i == nav_target_idx then
        -- Only scroll if the row is (about to be) out of view; the frozen
        -- header row takes ~1 row height at the top.
        local y  = reaper.ImGui_GetCursorPosY(ctx)
        local sy = reaper.ImGui_GetScrollY(ctx)
        local wh = reaper.ImGui_GetWindowHeight(ctx)
        local rh = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
        if y < sy + rh * 1.5 then
          reaper.ImGui_SetScrollHereY(ctx, 0.15)
        elseif y + rh * 2 > sy + wh then
          reaper.ImGui_SetScrollHereY(ctx, 0.85)
        end
      end

      for disp_idx, col in ipairs(visible_cols) do
        reaper.ImGui_TableSetColumnIndex(ctx, disp_idx - 1)

        local is_editing = EDIT and EDIT.row_idx == i and EDIT.col_id == col

        if is_editing then
          -- Editing mode
          reaper.ImGui_SetNextItemWidth(ctx, -1)
          if EDIT.want_focus then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            EDIT.want_focus = false
          end

          local chg, new_val = reaper.ImGui_InputText(ctx,
            "##edit_" .. row.__guid .. "_" .. col,
            EDIT.buf)

          if chg then
            EDIT.buf = new_val
          end

          -- Confirm: Enter, or clicking elsewhere (deactivated)
          local edited = reaper.ImGui_IsItemDeactivatedAfterEdit(ctx)
          local deactivated = reaper.ImGui_IsItemDeactivated(ctx)
          -- Cancel: ESC
          local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)

          if edited then
            local old_val = CLB.get_cell_edit_text(row, col)
            if EDIT.buf ~= old_val then
              -- TC validation for TC columns
              if TC_COLS[col] and not EDL.is_valid_tc(EDIT.buf) then
                -- Invalid TC: reject
                reaper.ShowMessageBox(
                  "Invalid timecode format.\nExpected: HH:MM:SS:FF",
                  SCRIPT_NAME, 0)
              else
                set_cell_value(row, col, EDIT.buf)
                if col == COL.GROUP then _rebuild_group_filters() end
                undo_snapshot()
                CLB.cached_rows = nil
              end
            end
            EDIT = nil
          elseif cancel or deactivated then
            EDIT = nil
          end
        else
          -- Display mode: use Selectable for highlight + click detection
          local text = get_cell_text(row, col)
          local selected = sel_has(row.__guid, col)

          -- Match col highlighting: orange=Fallback, cyan=Repaired,
          -- orange=Scene/Take inferred from overlapping audio (Match All)
          local is_fallback_row = row.match_status == "Fallback"
          local is_repaired_row = row.__repaired == true
          local is_scene_inferred_row = row.__scene_inferred == true
          local push_color = 0
          if is_repaired_row and col == COL.MATCH_STATUS then
            text = text .. " ✦"
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x00EEFFFF)
            push_color = 1
          elseif is_fallback_row then
            if col == COL.MATCH_STATUS then
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF8800FF)
              push_color = 1
            elseif col == COL.MATCHED_PATH then
              -- Prefix is already part of `text` — get_cell_text() adds it
              -- (see there for why: it needs to be sortable, not just a
              -- draw-time label).
              reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF4040FF)
              push_color = 1
            end
          end
          if push_color == 0 and is_scene_inferred_row and (col == COL.SCENE or col == COL.TAKE) then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF8800FF)
            push_color = 1
          end

          local display = (text ~= "" and text or " ") .. "##" .. row.__guid .. "_" .. col

          reaper.ImGui_Selectable(ctx, display, selected)
          if push_color > 0 then reaper.ImGui_PopStyleColor(ctx) end

          -- Tooltip for repaired rows
          if is_repaired_row and col == COL.MATCH_STATUS and
             reaper.ImGui_IsItemHovered(ctx) then
            if reaper.ImGui_BeginTooltip(ctx) then
              reaper.ImGui_Text(ctx, "Tape / Clip Name repaired from matched ISO audio.")
              reaper.ImGui_Text(ctx, "Original values saved to Notes column.")
              reaper.ImGui_EndTooltip(ctx)
            end
          end

          -- Tooltip for fallback-matched Matched File cell
          if is_fallback_row and col == COL.MATCHED_PATH and
             reaper.ImGui_IsItemHovered(ctx) then
            if reaper.ImGui_BeginTooltip(ctx) then
              if row.__fallback_kind == "scene_take" then
                reaper.ImGui_Text(ctx, "Scene+Take match only — source TC was NOT checked")
                reaper.ImGui_Text(ctx, "Neither clip name, reel, nor timecode matched any audio file.")
                reaper.ImGui_Text(ctx, "Matched purely by normalised Scene+Take — verify manually")
                reaper.ImGui_Text(ctx, "if the audio recorder wasn't jam-synced to camera.")
              else
                reaper.ImGui_Text(ctx, "Tape+TC match only")
                reaper.ImGui_Text(ctx, "EDL clip name did not match any audio file.")
                reaper.ImGui_Text(ctx, "Matched by reel+timecode range instead.")
              end
              if row.matched_path and row.matched_path ~= "" then
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Text(ctx, row.matched_path)
              end
              reaper.ImGui_EndTooltip(ctx)
            end
          end

          -- Tooltip for Scene/Take inferred from overlapping audio
          if is_scene_inferred_row and (col == COL.SCENE or col == COL.TAKE) and
             reaper.ImGui_IsItemHovered(ctx) then
            if reaper.ImGui_BeginTooltip(ctx) then
              reaper.ImGui_Text(ctx, "Inferred from overlapping audio — this Video row's own")
              reaper.ImGui_Text(ctx, "clip name/metadata had no Scene/Take. Filled in from the")
              reaper.ImGui_Text(ctx, "majority Scene/Take among audio events in the same range")
              reaper.ImGui_Text(ctx, "(a run by Match All) — verify manually if this range mixes")
              reaper.ImGui_Text(ctx, "scenes (inserts/cutaways).")
              reaper.ImGui_EndTooltip(ctx)
            end
          end

          -- Hint that a linked row's Clip Name jumps to its Reaper item
          if col == COL.CLIP_NAME and (row.__reaper_item or row.reaper_item_guid)
             and reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Click to select its linked Reaper item")
          end

          -- Hint that TC columns also jump Reaper's edit cursor on click
          if (col == COL.SRC_IN or col == COL.SRC_OUT or col == COL.REC_IN or col == COL.REC_OUT)
             and reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Click to move edit cursor here")
          end

          -- Click handling
          if reaper.ImGui_IsItemClicked(ctx, 0) then
            local shift, cmd = _mods()
            CLB.sel_cursor = { guid = row.__guid, col = col } -- arrow-key nav continues from here
            if shift and SEL.anchor then
              sel_rect(SEL.anchor.guid, SEL.anchor.col, row.__guid, col)
            elseif cmd then
              sel_toggle(row.__guid, col)
              if not SEL.anchor then
                SEL.anchor = { guid = row.__guid, col = col }
              end
            else
              sel_set_single(row.__guid, col)
              CLB.tl_center_on_guid = row.__guid
            end

            -- Any of the 4 TC columns also moves Reaper's edit cursor to
            -- that column's own literal TC value, treated as an absolute
            -- position on Reaper's timeline (0 to infinity, so a Source TC
            -- is just as valid a position as a Rec TC). This is exactly
            -- what manual conform relies on: raw dailies are commonly
            -- spotted at their own embedded/source timecode, so jumping to
            -- Src TC In/Out finds the correct source content directly,
            -- which is then moved back to the Rec TC position.
            local tc_col_field = {
              [COL.SRC_IN]  = "src_tc_in",  [COL.SRC_OUT] = "src_tc_out",
              [COL.REC_IN]  = "rec_tc_in",  [COL.REC_OUT] = "rec_tc_out",
            }
            local tc_field = tc_col_field[col]
            if tc_field then
              -- Both axes jump to their own "Calibrate TC (Anchor)"-
              -- corrected position when active, matching what the cell
              -- now displays — Rec TC via the usual "New" axis, Src TC
              -- via the "Old" axis (only meaningful in DME Recut mode;
              -- a no-op otherwise, so this is always safe to call).
              local sec
              if col == COL.REC_IN or col == COL.REC_OUT then
                sec = CLB.rec_tc_seconds(row[tc_field], row)
              else
                sec = CLB.src_tc_seconds(row[tc_field], row)
              end
              reaper.SetEditCurPos(sec, true, false)
            end

            -- Clip Name on a linked row ("Load From Reaper" pointer or a
            -- persisted "Link Reaper Items" GUID — see
            -- CLB.row_linked_item) selects and scrolls to that REAL item
            -- — user's own request, parallel to the TC columns' jump-to-
            -- position above but precise to one exact item (a position
            -- alone could land on the wrong one if several share a TC).
            if col == COL.CLIP_NAME and (row.__reaper_item or row.reaper_item_guid) then
              local linked = CLB.row_linked_item(row)
              if linked then
                reaper.SelectAllMediaItems(0, false)
                reaper.SetMediaItemSelected(linked, true)
                CLB._follow_sig = CLB._reaper_sel_sig() -- our own selection: Follow mustn't re-reveal it
                local item_pos = reaper.GetMediaItemInfo_Value(linked, "D_POSITION")
                reaper.SetEditCurPos(item_pos, true, false)
                reaper.UpdateArrange()
              else
                console_msg("Linked item not found in the current Reaper project"
                  .. " (deleted, re-glued, or a different project open) — re-run Link Reaper Items.")
              end
            end

            -- Auto-filter audio panel to matched file(s) for this row
            do
              local new_filter = nil
              local path = row.matched_path or ""
              if (row.match_status == "Found" or row.match_status == "Fallback") and
                 path ~= "" and not path:match("^%(") then
                -- Single real path
                new_filter = { [path] = true }
              elseif row.__match_candidates then
                -- Multiple candidates (Multiple, or Fallback with several files)
                new_filter = {}
                for _, cand in ipairs(row.__match_candidates) do
                  if cand.path then new_filter[cand.path] = true end
                end
                if not next(new_filter) then new_filter = nil end
              end
              if new_filter ~= CLB.audio_match_filter then
                CLB.audio_match_filter = new_filter
                CLB.audio_cached = nil
              end
            end
          end

          -- Double-click to edit
          if reaper.ImGui_IsItemHovered(ctx) and
             reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and
             EDITABLE_COLS[col] then
            EDIT = {
              row_idx = i,
              col_id = col,
              buf = CLB.get_cell_edit_text(row, col),
              want_focus = true,
            }
          end

          -- Right-click for row context menu
          if reaper.ImGui_IsItemClicked(ctx, 1) then
            CLB.row_context = { row = row, row_idx = i, col = col }
            CLB._open_row_ctx = true
          end
        end
      end
    end
  end

  -- Row context menu (Assign Reel / Assign Group)
  if CLB._open_row_ctx then
    reaper.ImGui_OpenPopup(ctx, "Row Context##clb_row_ctx")
    CLB._open_row_ctx = false
    CLB.new_reel_buf = ""
  end

  if reaper.ImGui_BeginPopup(ctx, "Row Context##clb_row_ctx") then
    if CLB.row_context then
      local sel_rows = get_selected_rows()
      if #sel_rows == 0 then sel_rows = { CLB.row_context.row } end

      -- ── Assign Reel ──────────────────────────────────────────
      reaper.ImGui_Text(ctx, string.format("Assign Reel  (%d row(s)):", #sel_rows))
      reaper.ImGui_Separator(ctx)

      -- Existing reels (skip the empty-string entry)
      for _, rf in ipairs(CLB.reel_filters) do
        if rf.name ~= "" then
          local is_current = (CLB.row_context.row.reel == rf.name)
          if reaper.ImGui_MenuItem(ctx, rf.name .. "  (" .. rf.count .. ")", nil, is_current) then
            for _, r in ipairs(sel_rows) do r.reel = rf.name end
            _rebuild_reel_filters()
            CLB.cached_rows = nil
            undo_snapshot()
          end
        end
      end

      -- Create New Reel
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, "New reel name:")
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, scale(120))
      local cnr_chg, cnr_new = reaper.ImGui_InputText(ctx, "##new_reel_ctx", CLB.new_reel_buf)
      if cnr_chg then CLB.new_reel_buf = cnr_new end
      reaper.ImGui_SameLine(ctx)
      local can_create = (CLB.new_reel_buf or "") ~= ""
      if not can_create then
        reaper.ImGui_BeginDisabled(ctx)
      end
      if reaper.ImGui_SmallButton(ctx, "Create##new_reel_btn") and can_create then
        local new_name = CLB.new_reel_buf
        for _, r in ipairs(sel_rows) do r.reel = new_name end
        CLB.new_reel_buf = ""
        _rebuild_reel_filters()
        CLB.cached_rows = nil
        undo_snapshot()
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      if not can_create then
        reaper.ImGui_EndDisabled(ctx)
      end

      -- Unassign
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_MenuItem(ctx, "(Unassign Reel)") then
        for _, r in ipairs(sel_rows) do r.reel = "" end
        _rebuild_reel_filters()
        CLB.cached_rows = nil
        undo_snapshot()
      end

      -- ── Assign Group ─────────────────────────────────────────
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, "Assign Group:")
      reaper.ImGui_Separator(ctx)
      for _, gf in ipairs(CLB.group_filters) do
        if gf.name ~= "" then
          local is_current = (CLB.row_context.row.group == gf.name)
          if reaper.ImGui_MenuItem(ctx, gf.name, nil, is_current) then
            for _, r in ipairs(sel_rows) do r.group = gf.name end
            _rebuild_group_filters()
            CLB.cached_rows = nil
            undo_snapshot()
          end
        end
      end
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_MenuItem(ctx, "(Unassign Group)") then
        for _, r in ipairs(sel_rows) do r.group = "" end
        _rebuild_group_filters()
        CLB.cached_rows = nil
        undo_snapshot()
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end

  reaper.ImGui_EndTable(ctx)
end

---------------------------------------------------------------------------
-- Draw: EDL Panel Header (with column editor)
---------------------------------------------------------------------------
local function draw_edl_panel_header()
  -- Compare group-results banner: the table is temporarily showing one row
  -- per recut group (see "Show as Table" in the Compare view) instead of
  -- the user's own working list. Offer a clear way back.
  if CLB.viewing_compare_groups then
    reaper.ImGui_TextColored(ctx, 0xCCAA33FF, "Showing Compare recut groups (not your working list).")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Analyze & Match...", scale(140), scale(22)) then
      CMP.analyze_and_match_session()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Scan the selected track(s) and match every recut candidate")
      reaper.ImGui_Text(ctx, "(all groups except Added) to a real item there — same Matched")
      reaper.ImGui_Text(ctx, "Item / Length Match strategies as Apply, offset-aware if you")
      reaper.ImGui_Text(ctx, "shifted Old. Matched items get colored by recut type and a")
      reaper.ImGui_Text(ctx, "take marker describing what Apply would do to them — run this")
      reaper.ImGui_Text(ctx, "before Apply to preview/spot-check, non-destructively.")
      reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Apply to Reaper...", scale(140), scale(22)) then
      CMP.apply_to_reaper()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Select recut-group row(s) above, select the track(s) to")
      reaper.ImGui_Text(ctx, "operate on in Reaper, then click this to apply them.")
      reaper.ImGui_Text(ctx, "Only 'Deleted' groups are supported so far.")
      reaper.ImGui_EndTooltip(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "Modes...##cmp_apply_modes") then
      reaper.ImGui_OpenPopup(ctx, "Apply Resolution Modes##cmp_apply_modes_popup")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Choose which strategies Apply may use to find items\n(tried in order: Matched Item > Length Match > Range Clear;\na disabled strategy is skipped).")
    end
    if reaper.ImGui_BeginPopup(ctx, "Apply Resolution Modes##cmp_apply_modes_popup") then
      reaper.ImGui_Text(ctx, "Tried in this order; untoggle to skip a strategy:")
      reaper.ImGui_Separator(ctx)
      local chg_matched, new_matched = reaper.ImGui_Checkbox(ctx, "Matched Item (metadata identity)", CLB.apply_mode_matched)
      if chg_matched then CLB.apply_mode_matched = new_matched; save_prefs() end
      reaper.ImGui_TextDisabled(ctx, "    P_EXT:CLB_REEL + Source TC on the item — exact content\n    identity, wherever it currently sits.")
      local chg_length, new_length = reaper.ImGui_Checkbox(ctx, "Length Match (within range)", CLB.apply_mode_length)
      if chg_length then CLB.apply_mode_length = new_length; save_prefs() end
      reaper.ImGui_TextDisabled(ctx, "    An item overlapping the old range whose own length\n    matches the target's — no metadata needed.")
      local chg_range, new_range = reaper.ImGui_Checkbox(ctx, "Range Clear", CLB.apply_mode_range)
      if chg_range then CLB.apply_mode_range = new_range; save_prefs() end
      reaper.ImGui_TextDisabled(ctx, "    Clear whatever occupies the old range regardless of\n    item boundaries — splits at the range edges.")
      reaper.ImGui_Separator(ctx)

      reaper.ImGui_Text(ctx, "Reconform Offset:")
      reaper.ImGui_TextDisabled(ctx, "    Shift the old Reaper session out of the way so it stays\n    pristine while the new cut is rebuilt in its place.")

      local chg_oe, new_oe = reaper.ImGui_Checkbox(ctx, "Offset Old##cmp_off_old_en", CLB.offset_old_enabled)
      if chg_oe then CLB.offset_old_enabled = new_oe; save_prefs() end
      reaper.ImGui_SameLine(ctx, 0, scale(10))
      reaper.ImGui_SetNextItemWidth(ctx, scale(90))
      local chg_oh, new_oh = reaper.ImGui_InputInt(ctx, "##cmp_off_old_h", CLB.offset_old_hours or 10)
      if chg_oh then CLB.offset_old_hours = new_oh; save_prefs() end
      reaper.ImGui_SameLine(ctx, 0, scale(6))
      reaper.ImGui_Text(ctx, "hours")
      reaper.ImGui_Indent(ctx, scale(16))
      if reaper.ImGui_SmallButton(ctx, "Shift Selected Tracks Now##cmp_off_old_go") then
        CMP.shift_range(CLB.offset_old_hours or 0, "old")
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Moves everything inside a Razor Edit area, or a Time\nSelection on the Reaper-selected track(s), by this many\nhours, right now. Undoable (Edit > Undo).")
      end
      reaper.ImGui_Unindent(ctx, scale(16))

      reaper.ImGui_Spacing(ctx)
      local chg_ne, new_ne = reaper.ImGui_Checkbox(ctx, "Offset New##cmp_off_new_en", CLB.offset_new_enabled)
      if chg_ne then CLB.offset_new_enabled = new_ne; save_prefs() end
      reaper.ImGui_SameLine(ctx, 0, scale(10))
      reaper.ImGui_SetNextItemWidth(ctx, scale(90))
      local chg_nh, new_nh = reaper.ImGui_InputInt(ctx, "##cmp_off_new_h", CLB.offset_new_hours or 0)
      if chg_nh then CLB.offset_new_hours = new_nh; save_prefs() end
      reaper.ImGui_SameLine(ctx, 0, scale(6))
      reaper.ImGui_Text(ctx, "hours")
      reaper.ImGui_TextDisabled(ctx, "    (For matching math only — used when the NEW EDL/XML\n    itself is authored at a non-zero hour.)")

      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_Button(ctx, "Close", scale(70), scale(22)) then
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_EndPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    local details_lbl = CLB.show_cmp_details and "Hide Details" or "Show Details"
    if reaper.ImGui_Button(ctx, details_lbl, scale(100), scale(22)) then
      CLB.show_cmp_details = not CLB.show_cmp_details
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Live inspector, below (same spot the Audio List normally uses):\nselect recut-group row(s) above and their individual items —\nold/new TC, reel, tracks — show here automatically.")
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Exit (restore my list)", scale(160), scale(22)) then
      if CLB._compare_rows_backup then
        ROWS            = CLB._compare_rows_backup.rows
        CLB.edl_sources = CLB._compare_rows_backup.sources
        CLB._compare_rows_backup = nil
      else
        ROWS = {}
      end
      CLB.viewing_compare_groups = false
      sel_clear()
      _rebuild_track_filters()
      _rebuild_reel_filters()
      _rebuild_group_filters()
      CLB.cached_rows = nil
    end
    reaper.ImGui_Separator(ctx)
  end

  -- Header line: Events count, Cols button for column editor
  local view_rows = get_view_rows()
  local event_count = #view_rows
  local total_count = #ROWS

  local fmt_label = _friendly_format(CLB.loaded_format)
  if total_count > 0 then
    if event_count ~= total_count then
      reaper.ImGui_Text(ctx, string.format("%s Events: %d / %d", fmt_label, event_count, total_count))
    else
      reaper.ImGui_Text(ctx, string.format("%s Events: %d", fmt_label, event_count))
    end
  else
    reaper.ImGui_TextDisabled(ctx, "No Event Loaded")
  end

  -- Separator
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "|")

  -- Columns button (column visibility/order editor)
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Columns##edl_cols") then
    reaper.ImGui_OpenPopup(ctx, "EDL Columns##edl_col_popup")
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Show/hide and reorder columns")
  end

  -- Fit widths button (toggle: Fit Widths / Default)
  reaper.ImGui_SameLine(ctx)
  local edl_fit_lbl = CLB.edl_fit_mode and "Default##edl_fit" or "Fit Widths##edl_fit"
  if reaper.ImGui_SmallButton(ctx, edl_fit_lbl) then
    if CLB.edl_fit_mode then
      for k, v in pairs(DEFAULT_COL_WIDTH) do COL_WIDTH[k] = v end
      CLB.edl_table_gen = (CLB.edl_table_gen or 0) + 1
      CLB.edl_fit_mode = false
    else
      CLB.edl_fit_content = true
      CLB.edl_fit_mode = true
    end
  end

  -- Timeline panel toggle
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)
  local tl_lbl = CLB.show_timeline and "Timeline <<##clb_tl" or "Timeline >>##clb_tl"
  if reaper.ImGui_SmallButton(ctx, tl_lbl) then
    CLB.show_timeline = not CLB.show_timeline
    save_prefs()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Show/hide mini-timeline visualization")
  end

  -- Clip Name format: the editable template itself now lives in
  -- Options > Formats (CLB.clip_name_format) — only the action button
  -- stays here, where it's contextually useful (right after matching).
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)
  local can_apply_fmt = (CLB.clip_name_format or "") ~= ""
  if not can_apply_fmt then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_SmallButton(ctx, "Apply Clip Name Format##clip_name_apply") then
    local n = 0
    for _, row in ipairs(ROWS) do
      local ms = row.match_status or ""
      if ms == "Found" or ms == "Fallback" or ms == "Multiple" then
        _apply_clip_name_format(row)
        n = n + 1
      end
    end
    if n > 0 then
      CLB.cached_rows = nil
      undo_snapshot()
    end
  end
  if not can_apply_fmt then reaper.ImGui_EndDisabled(ctx) end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx,
      "Apply the Clip Name template (set in Options > Formats) to all\n"
      .. "matched rows now.")
  end

  -- Columns popup
  if reaper.ImGui_BeginPopup(ctx, "EDL Columns##edl_col_popup") then
    reaper.ImGui_Text(ctx, "Show/Hide Columns:")
    reaper.ImGui_Separator(ctx)

    -- Show All / Hide All
    if reaper.ImGui_SmallButton(ctx, "All##edl_col_all") then
      for i = 1, COL_COUNT do EDL_COL_VISIBILITY[i] = true end
      save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "None##edl_col_none") then
      for i = 1, COL_COUNT do EDL_COL_VISIBILITY[i] = false end
      save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "Reset##edl_col_reset") then
      -- Reset to default order
      EDL_COL_ORDER = {
        COL.EVENT, COL.REEL, COL.TRACK, COL.EDIT_TYPE, COL.LEVEL, COL.DISS_LEN,
        COL.SRC_IN, COL.SRC_OUT, COL.REC_IN, COL.REC_OUT, COL.DURATION,
        COL.CLIP_NAME, COL.SRC_FILE, COL.NOTES, COL.MATCH_STATUS, COL.MATCHED_PATH,
        COL.GROUP, COL.SCENE, COL.TAKE
      }
      for i = 1, COL_COUNT do EDL_COL_VISIBILITY[i] = true end
      EDL_COL_VISIBILITY[COL.GROUP] = false
      EDL_COL_VISIBILITY[COL.SCENE] = false
      EDL_COL_VISIBILITY[COL.TAKE]  = false
      save_prefs()
    end
    reaper.ImGui_Separator(ctx)

    -- Column visibility checkboxes (reorder via table header drag)
    for _, col in ipairs(EDL_COL_ORDER) do
      local label = HEADER_LABELS[col] or ("Col " .. col)
      local chg, new_val = reaper.ImGui_Checkbox(ctx, label .. "##edl_col_vis_" .. col, EDL_COL_VISIBILITY[col])
      if chg then
        EDL_COL_VISIBILITY[col] = new_val
        save_prefs()
      end
    end

    reaper.ImGui_EndPopup(ctx)
  end
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

  -- Match filter indicator
  if CLB.audio_match_filter then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x00EEFFFF)
    reaper.ImGui_Text(ctx, "[ Showing matched ]")
    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "Show All##clr_match_filter") then
      CLB.audio_match_filter = nil
      CLB.audio_cached = nil
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Clear match filter — show all audio files")
    end
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
  end
  if CLB.audio_search ~= "" then
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "X##clr_audio_search") then
      CLB.audio_search = ""
      CLB.audio_cached = nil
    end
  end

  -- Audio panel toggle
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide##audio_panel") then
    CLB.show_audio_panel = false
  end

  -- Separator
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "|")

  -- Fit Widths button (toggle: Fit Widths / Default)
  reaper.ImGui_SameLine(ctx)
  local audio_fit_lbl = CLB.audio_fit_mode and "Default##audio_fit" or "Fit Widths##audio_fit"
  if reaper.ImGui_SmallButton(ctx, audio_fit_lbl) then
    if CLB.audio_fit_mode then
      for k, v in pairs(AUDIO_DEFAULT_COL_WIDTH) do AUDIO_COL_WIDTH[k] = v end
      CLB.audio_table_gen = (CLB.audio_table_gen or 0) + 1
      CLB.audio_fit_mode = false
    else
      CLB.audio_fit_content = true
      CLB.audio_fit_mode = true
    end
  end

  -- Copy (TSV) button
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Copy (TSV)##audio_copy") then
    local rows = get_audio_view_rows()
    local text = build_audio_table_text("tsv", rows, AUDIO_COL_ORDER, AUDIO_COL_VISIBILITY)
    if text and text ~= "" then
      reaper.ImGui_SetClipboardText(ctx, text)
    end
  end

  -- Save .tsv button
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Save .tsv##audio_tsv") then
    local path = choose_save_path("Audio_" .. timestamp() .. ".tsv", "Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
    if path then
      local rows = get_audio_view_rows()
      local text = build_audio_table_text("tsv", rows, AUDIO_COL_ORDER, AUDIO_COL_VISIBILITY)
      write_text_file(path, text)
    end
  end

  -- Save .csv button
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Save .csv##audio_csv") then
    local path = choose_save_path("Audio_" .. timestamp() .. ".csv", "CSV (*.csv)\0*.csv\0All (*.*)\0*.*\0")
    if path then
      local rows = get_audio_view_rows()
      local text = build_audio_table_text("csv", rows, AUDIO_COL_ORDER, AUDIO_COL_VISIBILITY)
      write_text_file(path, text)
    end
  end

  -- Columns button (visibility toggle)
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Columns##audio_cols") then
    reaper.ImGui_OpenPopup(ctx, "Audio Columns##audio_col_popup")
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Show/hide columns")
  end

  -- Columns popup
  if reaper.ImGui_BeginPopup(ctx, "Audio Columns##audio_col_popup") then
    reaper.ImGui_Text(ctx, "Show/Hide Columns:")
    reaper.ImGui_Separator(ctx)

    -- Show All / Hide All
    if reaper.ImGui_SmallButton(ctx, "All##audio_col_all") then
      for i = 1, AUDIO_COL_COUNT do AUDIO_COL_VISIBILITY[i] = true end
      save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "None##audio_col_none") then
      for i = 1, AUDIO_COL_COUNT do AUDIO_COL_VISIBILITY[i] = false end
      save_prefs()
    end
    reaper.ImGui_Separator(ctx)

    -- Checkbox for each column (in display order)
    for _, col in ipairs(AUDIO_COL_ORDER) do
      local label = AUDIO_HEADER_LABELS[col] or ("Col " .. col)
      local chg, new_val = reaper.ImGui_Checkbox(ctx, label .. "##audio_col_" .. col, AUDIO_COL_VISIBILITY[col])
      if chg then
        AUDIO_COL_VISIBILITY[col] = new_val
        save_prefs()
      end
    end

    reaper.ImGui_EndPopup(ctx)
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
    local _, delta_y = reaper.ImGui_GetMouseDelta(ctx)
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
-- Draw: Mini-Timeline Panel
---------------------------------------------------------------------------
local TL_PANEL_H = 136  -- base pixels (scaled at draw time; extra 16px for scrollbar)

local function draw_timeline_panel()
  -- 1. Collect rows, compute TC range and unique track list
  local view_rows = get_view_rows()
  if #view_rows == 0 then return end

  local tc_min, tc_max
  local track_set, track_order = {}, {}
  local row_data = {}

  for _, row in ipairs(view_rows) do
    local t_in  = EDL.tc_to_seconds(row.rec_tc_in  or "00:00:00:00", CLB.fps, CLB.is_drop)
    local t_out = EDL.tc_to_seconds(row.rec_tc_out or "00:00:00:00", CLB.fps, CLB.is_drop)
    if t_out < t_in then t_out = t_in end
    if not tc_min or t_in  < tc_min then tc_min = t_in  end
    if not tc_max or t_out > tc_max then tc_max = t_out end
    local trk = row.track or ""
    if not track_set[trk] then
      track_set[trk] = true
      track_order[#track_order + 1] = trk
    end
    row_data[#row_data + 1] = { row = row, t_in = t_in, t_out = t_out }
  end

  if not tc_min then tc_min = 0 end
  if not tc_max or tc_max <= tc_min then tc_max = tc_min + 1 end

  -- Sort tracks naturally (reuses _natural_sort_cmp)
  table.sort(track_order, _natural_sort_cmp)
  local track_index = {}
  for i, t in ipairs(track_order) do track_index[t] = i end

  -- 2. Geometry
  local LABEL_W   = scale(55)
  local RULER_H   = scale(16)
  local TRACK_H   = scale(18)
  local PAD_V     = scale(2)
  local VSCROLL_W = scale(12)   -- width of vertical scrollbar column
  local HSCROLL_H = scale(16)   -- height of horizontal scrollbar row
  local panel_h   = scale(TL_PANEL_H)
  local avail_w   = reaper.ImGui_GetContentRegionAvail(ctx)

  -- 3. BeginChild: fixed height, no scrollbars
  local wf = reaper.ImGui_WindowFlags_NoScrollbar()
           | reaper.ImGui_WindowFlags_NoScrollWithMouse()
  if not reaper.ImGui_BeginChild(ctx, "##clb_tl", avail_w, panel_h, 0, wf) then
    reaper.ImGui_EndChild(ctx)
    return
  end

  -- 4. InvisibleButton = interaction target (full canvas minus scrollbar rows)
  local cw, ch = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_InvisibleButton(ctx, "##tl_cvs", cw, ch - HSCROLL_H)
  local is_hovered = reaper.ImGui_IsItemHovered(ctx)
  local is_active  = reaper.ImGui_IsItemActive(ctx)

  -- 5. Canvas bounds
  local cx0, cy0 = reaper.ImGui_GetItemRectMin(ctx)
  local cx1, cy1 = reaper.ImGui_GetItemRectMax(ctx)

  -- Vertical scroll: compute before ea_w so VSCROLL_W can be omitted when not needed
  local total_track_h = #track_order * TRACK_H
  local track_area_h  = math.max(1, cy1 - cy0 - RULER_H)
  local max_vscroll   = math.max(0, total_track_h - track_area_h)
  CLB.tl_vscroll = math.max(0, math.min(max_vscroll, CLB.tl_vscroll or 0))
  local vscroll_visible = max_vscroll > 0
  local eff_vscroll_w   = vscroll_visible and VSCROLL_W or 0

  local ea_x0 = cx0 + LABEL_W
  local ea_w  = math.max(1, cx1 - ea_x0 - eff_vscroll_w)

  -- 6. DrawList
  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  -- 7. Zoom / scroll clamping (every frame)
  local span     = tc_max - tc_min
  local min_zoom = ea_w / span
  local max_zoom = 500.0
  CLB.tl_zoom   = math.max(min_zoom, math.min(max_zoom, CLB.tl_zoom))
  local vis_sec  = ea_w / CLB.tl_zoom
  local max_scroll = math.max(0, span - vis_sec)
  CLB.tl_scroll = math.max(0, math.min(max_scroll, CLB.tl_scroll))

  -- Center timeline on row selected from the list (horizontal + vertical)
  if CLB.tl_center_on_guid then
    for _, rd in ipairs(row_data) do
      if rd.row.__guid == CLB.tl_center_on_guid then
        -- Horizontal: center block in view
        local center_t = (rd.t_in + rd.t_out) * 0.5 - tc_min
        CLB.tl_scroll = math.max(0, math.min(max_scroll, center_t - vis_sec * 0.5))
        -- Vertical: bring the track row into view
        local ti = track_index[rd.row.track or ""] or 1
        local block_top_rel = (ti - 1) * TRACK_H   -- relative to track area top
        local block_bot_rel = ti * TRACK_H
        if block_top_rel < CLB.tl_vscroll then
          CLB.tl_vscroll = math.max(0, block_top_rel - TRACK_H)
        elseif block_bot_rel > CLB.tl_vscroll + track_area_h then
          CLB.tl_vscroll = math.min(max_vscroll, block_bot_rel - track_area_h + TRACK_H)
        end
        break
      end
    end
    CLB.tl_center_on_guid = nil
  end

  -- Helper: seconds → screen x
  local function s2px(t)
    return ea_x0 + (t - tc_min - CLB.tl_scroll) * CLB.tl_zoom
  end

  -- 8. Backgrounds
  reaper.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx1 - eff_vscroll_w, cy1, 0x1A1A1AFF)
  reaper.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx0 + LABEL_W, cy1, 0x252525FF)

  -- 9. TC ruler
  local ry0 = cy0
  local ry1 = cy0 + RULER_H
  reaper.ImGui_DrawList_AddRectFilled(dl, ea_x0, ry0, cx1 - eff_vscroll_w, ry1, 0x2A2A2AFF)

  -- Pick tick interval: smallest where ticks are >= 80px apart (TC labels are wider)
  local fps_val = CLB.fps or 24
  local frame_dur = 1.0 / fps_val
  local intervals = {
    frame_dur, frame_dur * 2, frame_dur * 5, frame_dur * 10,
    1, 2, 5, 10, 15, 30, 60, 120, 300, 600,
  }
  local tick_iv = 600
  for _, iv in ipairs(intervals) do
    if iv * CLB.tl_zoom >= scale(80) then tick_iv = iv; break end
  end

  local view_start = tc_min + CLB.tl_scroll
  local view_end   = view_start + vis_sec
  local t = math.floor(view_start / tick_iv) * tick_iv
  while t <= view_end + tick_iv do
    local px = s2px(t)
    if px >= ea_x0 and px <= cx1 then
      reaper.ImGui_DrawList_AddLine(dl, px, ry0, px, ry1, 0x555555FF, 1.0)
      local lbl = EDL.seconds_to_tc(math.max(0, t), CLB.fps or 24, CLB.is_drop or false)
      if px + scale(4) < cx1 then
        reaper.ImGui_DrawList_AddText(dl, px + scale(2), ry0 + scale(2), 0xAAAAAAFF, lbl)
      end
    end
    t = t + tick_iv
  end
  reaper.ImGui_DrawList_AddLine(dl, cx0, ry1, cx1 - eff_vscroll_w, ry1, 0x444444FF, 1.0)

  -- 10. Track row backgrounds + labels
  local track_right = cx1 - eff_vscroll_w   -- right edge of track/label area
  for ti, tname in ipairs(track_order) do
    local ey0_raw = ry1 + (ti - 1) * TRACK_H - CLB.tl_vscroll
    local ey1_raw = ey0_raw + TRACK_H
    if ey1_raw <= ry1 then goto next_track_bg end  -- above ruler
    if ey0_raw >= cy1  then break end               -- below canvas
    local ey0 = math.max(ey0_raw, ry1)
    local ey1 = math.min(ey1_raw, cy1)
    local bg = (ti % 2 == 0) and 0x222222FF or 0x1E1E1EFF
    reaper.ImGui_DrawList_AddRectFilled(dl, cx0, ey0, track_right, ey1, bg)
    if ey0_raw >= ry1 then  -- only draw label when row is fully visible at top
      reaper.ImGui_DrawList_AddText(dl, cx0 + scale(3), ey0 + scale(3), 0xCCCCCCFF,
        tname ~= "" and tname or "?")
    end
    reaper.ImGui_DrawList_AddLine(dl, cx0, ey1, track_right, ey1, 0x333333FF, 1.0)
    ::next_track_bg::
  end

  -- 11. Track color helper (A=blue, V=amber, other=green; shade varies per index)
  local function track_color(tname, ti, alpha)
    local p     = (tname:match("^(%a+)") or ""):upper()
    local shades = { 0xFF, 0xCC, 0xAA }
    local shade = shades[(ti - 1) % 3 + 1]
    local r, g, b
    if p == "A" then
      r = 0x30 + (ti % 3) * 0x10
      g = 0x80 + (ti % 2) * 0x20
      b = shade
    elseif p == "V" then
      r = shade
      g = 0x80 + (ti % 2) * 0x20
      b = 0x10 + (ti % 3) * 0x10
    else
      r = 0x20 + (ti % 2) * 0x20
      g = shade
      b = 0x30 + (ti % 3) * 0x10
    end
    return (r << 24) | (g << 16) | (b << 8) | alpha
  end

  -- 12. Draw event blocks
  local mx, my   = reaper.ImGui_GetMousePos(ctx)
  local hovered_rd = nil
  -- Every on-screen block's own rect, kept for the box-select hit-test in
  -- section 16 below (built here since this is already where each
  -- block's exact screen geometry is computed).
  local block_rects = {}

  for _, rd in ipairs(row_data) do
    local row = rd.row
    local ti  = track_index[row.track or ""] or 1
    local ey0 = ry1 + (ti - 1) * TRACK_H + PAD_V - CLB.tl_vscroll
    local ey1 = ry1 +  ti      * TRACK_H - PAD_V - CLB.tl_vscroll
    if ey1 <= ry1 then goto next_block end     -- above ruler
    if ey0 >= cy1  then goto next_block end    -- below panel bottom

    local px0 = s2px(rd.t_in)
    local px1 = s2px(rd.t_out)
    if px1 < ea_x0 or px0 > cx1 then goto next_block end  -- off canvas

    local dx0 = math.max(px0, ea_x0)
    local dx1 = math.min(px1, cx1)
    if dx1 < dx0 + 1 then dx1 = dx0 + 1 end   -- minimum 1px

    block_rects[#block_rects + 1] = { row = row, dx0 = dx0, ey0 = ey0, dx1 = dx1, ey1 = ey1 }

    local selected = sel_has_row(row.__guid)
    -- Unselected clips use a lighter, legible slate gray (was a near-
    -- black 0x3A3A3A that was hard to read) — still clearly duller than
    -- selected's full-brightness per-track-type color so the two never
    -- get confused.
    local col_fill = selected
      and track_color(row.track or "", ti, 0xFF)   -- selected: full-brightness color
      or  0x5C6670DD                                -- unselected: legible slate gray
    local col_edge = selected and 0xFFFFFFEE or 0x00000066
    reaper.ImGui_DrawList_AddRectFilled(dl, dx0, ey0, dx1, ey1, col_fill)
    reaper.ImGui_DrawList_AddRect(dl,      dx0, ey0, dx1, ey1, col_edge)

    -- Hover highlight
    if is_hovered and mx >= dx0 and mx <= dx1 and my >= ey0 and my <= ey1 then
      reaper.ImGui_DrawList_AddRectFilled(dl, dx0, ey0, dx1, ey1, 0xFFFFFF22)
      hovered_rd = rd
    end

    -- Clip name label (only if block is wide enough)
    local bw = dx1 - dx0
    if bw >= scale(20) then
      local lbl = row.clip_name or ""
      local max_ch = math.max(0, math.floor(bw / scale(7)) - 1)
      if #lbl > max_ch then lbl = lbl:sub(1, math.max(0, max_ch - 1)) .. "~" end
      if #lbl > 0 then
        local txt_col = selected and 0xFFFFFFEE or 0xE8E8E8DD
        reaper.ImGui_DrawList_AddText(dl, dx0 + scale(2), ey0 + scale(2), txt_col, lbl)
      end
    end

    ::next_block::
  end

  -- 13. Tooltip on hover
  if hovered_rd then
    local r = hovered_rd.row
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, r.clip_name ~= "" and r.clip_name or "(no name)")
    reaper.ImGui_Text(ctx, "Track:   " .. (r.track or ""))
    reaper.ImGui_Text(ctx, "Rec In:  " .. (r.rec_tc_in  or ""))
    reaper.ImGui_Text(ctx, "Rec Out: " .. (r.rec_tc_out or ""))
    local d = hovered_rd.t_out - hovered_rd.t_in
    reaper.ImGui_Text(ctx, string.format("Duration: %d:%05.2f", math.floor(d / 60), d % 60))
    if (r.reel or "") ~= "" then
      reaper.ImGui_Text(ctx, "Reel:    " .. r.reel)
    end
    reaper.ImGui_EndTooltip(ctx)
  end

  -- 14. Click → select one clip + scroll-to-row in table. A drag past the
  -- threshold (section 16) supersedes this every frame it's active, so a
  -- click that turns into a drag ends up box-selected instead — no extra
  -- bookkeeping needed to tell click and drag-start apart.
  if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
    if hovered_rd then
      sel_clear()
      for _, c in ipairs(EDL_COL_ORDER) do
        sel_add(hovered_rd.row.__guid, c)
      end
      CLB.scroll_to_row = hovered_rd.row.__guid
    else
      sel_clear()
    end
  end

  -- 14b. Right-click a clip → the SAME row context menu as the event table
  -- (user's own request) — reuses draw_table's deferred popup
  -- (CLB.row_context + CLB._open_row_ctx; draw_table runs after this panel
  -- every frame and opens/draws it in its own scope), so the two menus can
  -- never drift apart. Right-clicking a clip that isn't part of the current
  -- selection selects it alone first, so the menu never silently acts on
  -- some other, unseen selection.
  if is_hovered and hovered_rd and reaper.ImGui_IsMouseClicked(ctx, 1) then
    local g = hovered_rd.row.__guid
    if not sel_has_row(g) then
      sel_clear()
      for _, c in ipairs(EDL_COL_ORDER) do sel_add(g, c) end
      CLB.scroll_to_row = g
    end
    CLB.row_context = { row = hovered_rd.row }
    CLB._open_row_ctx = true
  end

  -- 15. Scroll wheel:
  --   • Scroll (no mod)    → vertical scroll (track rows)
  --   • Shift+scroll       → horizontal pan (macOS converts to horizontal axis)
  --   • Option/Alt+scroll  → horizontal zoom (anchored to cursor)
  if is_hovered then
    local ok_w, scroll_y, scroll_h = pcall(reaper.ImGui_GetMouseWheel, ctx)
    if ok_w then
      local alt_held = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
      -- Option/Alt + vertical scroll → zoom
      if alt_held and scroll_y and scroll_y ~= 0 then
        local mouse_t  = (mx - ea_x0) / CLB.tl_zoom + tc_min + CLB.tl_scroll
        local factor   = scroll_y > 0 and 1.15 or (1 / 1.15)
        local new_zoom = math.max(min_zoom, math.min(max_zoom, CLB.tl_zoom * factor))
        CLB.tl_scroll  = mouse_t - tc_min - (mx - ea_x0) / new_zoom
        CLB.tl_zoom    = new_zoom
        local new_vis  = ea_w / CLB.tl_zoom
        local new_max  = math.max(0, span - new_vis)
        CLB.tl_scroll  = math.max(0, math.min(new_max, CLB.tl_scroll))
      -- Horizontal scroll (Shift+scroll on macOS → horizontal axis) → pan
      elseif scroll_h and scroll_h ~= 0 then
        CLB.tl_scroll = math.max(0, math.min(max_scroll,
          CLB.tl_scroll - scroll_h / CLB.tl_zoom * 60))
      -- Plain scroll → vertical
      elseif not alt_held and scroll_y and scroll_y ~= 0 then
        if vscroll_visible then
          CLB.tl_vscroll = math.max(0, math.min(max_vscroll,
            CLB.tl_vscroll - scroll_y * TRACK_H * 3))
        else
          -- No overflow → fall back to zoom
          local mouse_t  = (mx - ea_x0) / CLB.tl_zoom + tc_min + CLB.tl_scroll
          local factor   = scroll_y > 0 and 1.15 or (1 / 1.15)
          local new_zoom = math.max(min_zoom, math.min(max_zoom, CLB.tl_zoom * factor))
          CLB.tl_scroll  = mouse_t - tc_min - (mx - ea_x0) / new_zoom
          CLB.tl_zoom    = new_zoom
          local new_vis  = ea_w / CLB.tl_zoom
          local new_max  = math.max(0, span - new_vis)
          CLB.tl_scroll  = math.max(0, math.min(new_max, CLB.tl_scroll))
        end
      end
    end
  end

  -- 16. Drag: scrollbar column → vertical scroll thumb; event area → box-
  -- select (replaces the old drag-to-pan — horizontal panning now lives
  -- on Shift+scroll instead, confirmed with the user, so plain left-drag
  -- is free to mean "select multiple clips," same convention REAPER's
  -- own arrange view uses).
  if not is_active then
    CLB._tl_sb_dragging = nil   -- reset drag-origin flag
    -- Box-select just ended → bring the table to the selection, same as a
    -- single click does (user's own report: a drag-select, even of one
    -- clip, never scrolled the event list, so it looked unlinked). Scrolls
    -- to the topmost selected row in the table's own (sorted/filtered)
    -- order and sets it as the Shift/arrow-key anchor.
    if CLB._tl_box_selected then
      CLB._tl_box_selected = nil
      -- One pass over the selected cells → guid set (sel_has_row per row
      -- would rescan every selected cell for every row: rows × cells).
      local sel_guids = {}
      for k in pairs(SEL.cells) do
        local g = k:match("^(.*):[^:]*$")
        if g then sel_guids[g] = true end
      end
      local first, last
      for _, vr in ipairs(get_view_rows()) do
        if sel_guids[vr.__guid] then
          first = first or vr
          last = vr
        end
      end
      if first then
        CLB.scroll_to_row = first.__guid
        SEL.anchor = { guid = first.__guid, col = COL.CLIP_NAME }
        CLB.sel_cursor = { guid = last.__guid, col = COL.CLIP_NAME }
      end
    end
  end
  if is_active then
    local delta_y = select(2, reaper.ImGui_GetMouseDelta(ctx))
    -- Detect drag origin on first active frame
    if CLB._tl_sb_dragging == nil then
      CLB._tl_sb_dragging = vscroll_visible and (mx >= cx1 - eff_vscroll_w)
      if not CLB._tl_sb_dragging then
        CLB.tl_box_x0, CLB.tl_box_y0 = mx, my
      end
    end
    if CLB._tl_sb_dragging then
      -- Drag inside scrollbar column → move thumb
      if delta_y and delta_y ~= 0 then
        local sb_h    = cy1 - ry1
        local thumb_h = math.max(scale(20), sb_h * track_area_h / total_track_h)
        local ratio   = delta_y / math.max(1, sb_h - thumb_h)
        CLB.tl_vscroll = math.max(0, math.min(max_vscroll,
          CLB.tl_vscroll + ratio * max_vscroll))
      end
      reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
    elseif reaper.ImGui_IsMouseDragging(ctx, 0) then
      -- Box-select: live rectangle from drag origin to current mouse pos,
      -- recomputed (and the selection rebuilt from scratch) every frame
      -- so it tracks the rect exactly, including growing/shrinking back.
      local bx0, by0 = CLB.tl_box_x0 or mx, CLB.tl_box_y0 or my
      local rx0, rx1 = math.min(bx0, mx), math.max(bx0, mx)
      local rsy0, rsy1 = math.min(by0, my), math.max(by0, my)
      reaper.ImGui_DrawList_AddRectFilled(dl, rx0, rsy0, rx1, rsy1, 0x4C9BFF33)
      reaper.ImGui_DrawList_AddRect(dl,       rx0, rsy0, rx1, rsy1, 0x7CB8FFDD)
      sel_clear()
      for _, br in ipairs(block_rects) do
        if br.dx1 >= rx0 and br.dx0 <= rx1 and br.ey1 >= rsy0 and br.ey0 <= rsy1 then
          for _, c in ipairs(EDL_COL_ORDER) do sel_add(br.row.__guid, c) end
        end
      end
      CLB._tl_box_selected = true -- scroll the table once the drag ends (see above)
    end
  end

  -- 17. Vertical scrollbar (DrawList, right column)
  if vscroll_visible then
    local sb_x0  = cx1 - eff_vscroll_w + scale(1)
    local sb_x1  = cx1
    local sb_y0  = ry1
    local sb_y1  = cy1
    local sb_h   = sb_y1 - sb_y0
    local thumb_h = math.max(scale(20), sb_h * track_area_h / total_track_h)
    local thumb_y = sb_y0 + (CLB.tl_vscroll / max_vscroll) * (sb_h - thumb_h)

    reaper.ImGui_DrawList_AddRectFilled(dl, sb_x0, sb_y0, sb_x1, sb_y1, 0x1A1A1AFF)
    local thumb_hover = is_hovered and mx >= sb_x0 and mx <= sb_x1
    local thumb_col   = thumb_hover and 0x888888FF or 0x555555FF
    reaper.ImGui_DrawList_AddRectFilled(dl, sb_x0, thumb_y, sb_x1,
      math.min(thumb_y + thumb_h, sb_y1), thumb_col, scale(3))

    -- Click on scrollbar track → jump to position
    if thumb_hover and reaper.ImGui_IsMouseClicked(ctx, 0) then
      local rel = math.max(0, math.min(1, (my - sb_y0) / math.max(1, sb_h - thumb_h)))
      CLB.tl_vscroll = rel * max_vscroll
    end

    -- Hint label inside label column
    reaper.ImGui_DrawList_AddText(dl, cx0 + scale(2), cy1 - scale(13), 0x555555FF,
      "opt+scroll:zoom")
  end

  -- 18. Horizontal scrollbar at bottom of panel
  local hscroll_w = cw - eff_vscroll_w
  if max_scroll > 0 then
    reaper.ImGui_SetNextItemWidth(ctx, hscroll_w)
    local chg_sc, new_sc = reaper.ImGui_SliderDouble(ctx, "##tl_hscroll",
      CLB.tl_scroll, 0, max_scroll, "")
    if chg_sc then CLB.tl_scroll = new_sc end
  end

  reaper.ImGui_EndChild(ctx)
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

  -- Build list of visible columns in display order
  local visible_cols = {}
  for _, col in ipairs(AUDIO_COL_ORDER) do
    if AUDIO_COL_VISIBILITY[col] then
      table.insert(visible_cols, col)
    end
  end
  local visible_count = #visible_cols

  if visible_count == 0 then
    reaper.ImGui_TextDisabled(ctx, "No columns visible. Click 'Cols' to show columns.")
    return
  end

  -- Table flags (with reorder and sortable)
  local flags = reaper.ImGui_TableFlags_Borders()
    | reaper.ImGui_TableFlags_RowBg()
    | reaper.ImGui_TableFlags_SizingFixedFit()
    | reaper.ImGui_TableFlags_ScrollX()
    | reaper.ImGui_TableFlags_ScrollY()
    | reaper.ImGui_TableFlags_Resizable()
    | reaper.ImGui_TableFlags_Reorderable()
    | reaper.ImGui_TableFlags_Sortable()
    | reaper.ImGui_TableFlags_SortMulti()

  -- Fit Widths: fixed columns (Src TC, Duration, SR, Ch, FPS, Speed) stay at default widths;
  -- stretchy columns (Filename, Scene, Folder, Tracks, Description, etc.) share remaining
  -- window width proportionally. Same fixed+stretchy approach as EDL table.
  if CLB.audio_fit_content then
    local scale_ratio = current_font_size / 13.0
    local avail_w_audio, _ = reaper.ImGui_GetContentRegionAvail(ctx)
    local fixed_base = 0
    local stretch_base = 0
    for _, col in ipairs(visible_cols) do
      local def_w = AUDIO_DEFAULT_COL_WIDTH[col] or 80
      if AUDIO_FIT_FIXED_COLS[col] then
        fixed_base = fixed_base + def_w
      else
        stretch_base = stretch_base + def_w
      end
    end
    local remaining_base = (avail_w_audio / scale_ratio) - fixed_base
    for _, col in ipairs(visible_cols) do
      local def_w = AUDIO_DEFAULT_COL_WIDTH[col] or 80
      if AUDIO_FIT_FIXED_COLS[col] then
        AUDIO_COL_WIDTH[col] = def_w
      elseif stretch_base > 0 then
        AUDIO_COL_WIDTH[col] = math.max(20, math.floor(def_w / stretch_base * remaining_base))
      end
    end
    CLB.audio_table_gen = (CLB.audio_table_gen or 0) + 1
    CLB.audio_fit_content = false
  end

  local audio_table_id = "audio_table_v2_" .. (CLB.audio_table_gen or 0)
  if not reaper.ImGui_BeginTable(ctx, audio_table_id, visible_count, flags, 0, table_height) then
    return
  end

  -- Setup columns (only visible ones, in display order)
  for _, col in ipairs(visible_cols) do
    local w = scale(AUDIO_COL_WIDTH[col] or 80)
    local col_flags = reaper.ImGui_TableColumnFlags_WidthFixed()
    if AUDIO_TC_COLS[col] then
      col_flags = col_flags | reaper.ImGui_TableColumnFlags_NoResize()
    end
    reaper.ImGui_TableSetupColumn(ctx, AUDIO_HEADER_LABELS[col] or "", col_flags, w)
  end
  reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)

  -- Check for sort specs changes
  local sort_specs_dirty = reaper.ImGui_TableNeedSort(ctx)
  if sort_specs_dirty then
    if reaper.ImGui_TableGetColumnSortSpecs then
      local has_specs, col_idx, _, sort_dir = reaper.ImGui_TableGetColumnSortSpecs(ctx, 0)
      if has_specs and col_idx then
        -- Map display column index back to actual column ID
        local actual_col = visible_cols[col_idx + 1]
        if actual_col then
          CLB.audio_sort_col = actual_col
          CLB.audio_sort_asc = sort_dir == reaper.ImGui_SortDirection_Ascending()
          CLB.audio_cached = nil
        end
      else
        CLB.audio_sort_col = nil
      end
    end
  end

  -- Headers
  reaper.ImGui_TableHeadersRow(ctx)

  -- Rows (with ListClipper for virtualization)
  if list_clipper and not reaper.ImGui_ValidatePtr(list_clipper, "ImGui_ListClipper*") then
    list_clipper = reaper.ImGui_CreateListClipper(ctx)
  end

  local use_clipper = list_clipper and row_count > 50
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
    else
      cs, ce = 1, row_count
      clp = false
    end

    for i = cs, ce do
      local af = audio_rows[i]
      if not af then break end

      reaper.ImGui_TableNextRow(ctx)

      for idx, col in ipairs(visible_cols) do
        reaper.ImGui_TableSetColumnIndex(ctx, idx - 1)

        local text = ""
        local meta = af.metadata or {}

        if col == AUDIO_COL.FILENAME then
          text = af.filename or ""
        elseif col == AUDIO_COL.SRC_TC then
          text = meta.src_tc or ""
        elseif col == AUDIO_COL.SCENE then
          text = meta.scene or ""
        elseif col == AUDIO_COL.TAKE then
          text = meta.take or ""
        elseif col == AUDIO_COL.TAPE then
          text = meta.tape or meta.reel or ""
        elseif col == AUDIO_COL.FOLDER then
          text = af.folder or ""
        elseif col == AUDIO_COL.DURATION then
          text = format_duration(meta.duration)
        elseif col == AUDIO_COL.SAMPLERATE then
          text = format_samplerate(meta.samplerate)
        elseif col == AUDIO_COL.CHANNELS then
          text = meta.channels and tostring(meta.channels) or ""
        elseif col == AUDIO_COL.PROJECT then
          text = meta.project or ""
        elseif col == AUDIO_COL.FRAMERATE then
          text = meta.framerate or ""
        elseif col == AUDIO_COL.SPEED then
          text = meta.speed or ""
        elseif col == AUDIO_COL.ORIG_FILENAME then
          text = meta.orig_filename or ""
        elseif col == AUDIO_COL.TRACK_NAMES then
          text = meta.track_names or ""
        elseif col == AUDIO_COL.DESCRIPTION then
          local desc = meta.description or ""
          if #desc > 50 then desc = desc:sub(1, 47) .. "..." end
          text = desc
        end

        reaper.ImGui_Text(ctx, text)
      end
    end
  end

  reaper.ImGui_EndTable(ctx)
end

---------------------------------------------------------------------------
-- Draw: Loading Progress Indicator
---------------------------------------------------------------------------
local function draw_loading_progress()
  if CLB.batch_job then
    local job = CLB.batch_job
    local progress = job.total > 0 and (job.current / job.total) or 0
    reaper.ImGui_Text(ctx, string.format("%s... %d / %d", job.label or "Working", job.current, job.total))
    reaper.ImGui_ProgressBar(ctx, progress, -1, 0)
    return true
  end

  if not CLB.loading_state then return false end

  local state = CLB.loading_state

  if state.phase == "reading_metadata" then
    -- Determinate bar for audio metadata scan
    local progress = state.total > 0 and (state.current / state.total) or 0
    reaper.ImGui_Text(ctx, string.format("Loading audio files... %d / %d", state.current, state.total))
    reaper.ImGui_ProgressBar(ctx, progress, -1, 0)

  elseif state.phase == "otio_loading" then
    local n     = #state.filepaths
    local idx   = state.current_idx
    local fname = (state.filepaths[idx] or ""):match("([^/\\]+)$") or ""
    local elapsed = reaper.time_precise() - (state.start_time or 0)
    local dots  = string.rep(".", math.floor(elapsed * 2) % 4)

    -- Try to read granular progress from Python's progress file
    local prog = state.active_handle and OTIO.parse_async_progress(state.active_handle)

    if prog and prog.total > 0 then
      -- Determinate bar: Python has started converting clips
      local fraction = prog.current / prog.total
      local clip_name = prog.name ~= "" and ("  " .. prog.name) or ""
      local file_label = n > 1
        and string.format("(%d/%d) %s", idx, n, fname)
        or  fname
      reaper.ImGui_Text(ctx, string.format(
        "Loading %s — clip %d / %d%s", file_label, prog.current, prog.total, clip_name))
      reaper.ImGui_ProgressBar(ctx, fraction, -1, 0)
    elseif prog and prog.phase == "parsing" then
      -- Indeterminate: AAF/XML file is being parsed (before clip count known)
      local file_label = n > 1
        and string.format("(%d/%d) %s", idx, n, fname)
        or  fname
      reaper.ImGui_Text(ctx, string.format("Parsing %s%s", file_label, dots))
      reaper.ImGui_ProgressBar(ctx, -1, -1, 0)
    else
      -- No progress file yet (process just launched)
      local file_label = n > 1
        and string.format("(%d/%d) %s", idx, n, fname)
        or  fname
      reaper.ImGui_Text(ctx, string.format("Loading %s%s", file_label, dots))
      reaper.ImGui_ProgressBar(ctx, -1, -1, 0)
    end
  end

  return true
end

---------------------------------------------------------------------------
-- Draw: Reel Filter Sidebar (left side)
---------------------------------------------------------------------------
local function draw_reel_filter_sidebar(height)
  local has_reels = CLB.show_reel_filter and #CLB.reel_filters > 0
  local has_groups = CLB.show_group_filter and #ROWS > 0
  if not has_reels and not has_groups then return false end

  -- Calculate sidebar width based on longest reel/group name
  local max_text_w = 160
  if has_reels then
    for _, rf in ipairs(CLB.reel_filters) do
      local display_name = rf.name ~= "" and rf.name or "(empty)"
      local label = string.format("%s (%d)", display_name, rf.count)
      local text_w = reaper.ImGui_CalcTextSize(ctx, label)
      if text_w > max_text_w then max_text_w = text_w end
    end
  end
  if has_groups then
    for _, gf in ipairs(CLB.group_filters) do
      local label = string.format("%s (%d)", gf.name, gf.count)
      local text_w = reaper.ImGui_CalcTextSize(ctx, label)
      if text_w > max_text_w then max_text_w = text_w end
    end
  end
  local sidebar_w = math.min(max_text_w + 40, scale(220))  -- cap at 220 base-px

  -- Left sidebar child
  if reaper.ImGui_BeginChild(ctx, "##clb_sidebar", sidebar_w, height, reaper.ImGui_ChildFlags_Borders()) then
    local _, content_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local header_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx) * 2 + 4  -- header + buttons line

    -- Calculate section heights (Reels 2/3, Groups 1/3)
    local reel_section_h, group_section_h
    if has_reels and has_groups then
      reel_section_h = (content_h - header_h) * 0.65
      group_section_h = content_h - reel_section_h - header_h
    elseif has_reels then
      reel_section_h = content_h
      group_section_h = 0
    else
      reel_section_h = 0
      group_section_h = content_h
    end

    -- ===== REELS SECTION =====
    if has_reels then
      reaper.ImGui_Text(ctx, string.format("Reels (%d)", #CLB.reel_filters))

      -- Show All / Hide All buttons
      if reaper.ImGui_SmallButton(ctx, "All##clb_reel_all") then
        for _, rf in ipairs(CLB.reel_filters) do rf.visible = true end
        CLB.cached_rows = nil
        CLB.reel_sel = {}; CLB.reel_sel_anchor = nil
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "None##clb_reel_none") then
        for _, rf in ipairs(CLB.reel_filters) do rf.visible = false end
        CLB.cached_rows = nil
        CLB.reel_sel = {}; CLB.reel_sel_anchor = nil
      end

      reaper.ImGui_Separator(ctx)

      -- Reel list (vertical, scrollable)
      -- [ ] checkbox square   → toggles visible only (no selection change)
      -- Click on text         → selects this reel (clears others); sets anchor
      -- Shift+click on text   → range-select from anchor to here (no visible change)
      -- Ctrl/Cmd+click text   → toggle this reel in/out of selection
      -- Right-click anywhere  → context menu; auto-selects hovered item if unselected
      local list_h = reel_section_h - header_h - 4
      if list_h < 50 then list_h = 50 end
      if reaper.ImGui_BeginChild(ctx, "##clb_reel_list", 0, list_h) then
      local dl = reaper.ImGui_GetWindowDrawList(ctx)
      for i, rf in ipairs(CLB.reel_filters) do
        local display_name = rf.name ~= "" and rf.name or "(empty)"
        local is_sel = CLB.reel_sel[i] or false

        -- Full-row selection highlight (drawn behind both widgets)
        if is_sel then
          local rx, ry = reaper.ImGui_GetCursorScreenPos(ctx)
          local rw, _  = reaper.ImGui_GetContentRegionAvail(ctx)
          local rlh = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
          reaper.ImGui_DrawList_AddRectFilled(dl, rx - 4, ry, rx + rw + 4, ry + rlh, 0x3366CC50)
        end

        -- [ ] Checkbox: toggles visible only
        local cb_changed, new_vis = reaper.ImGui_Checkbox(ctx, "##reel_cb_" .. i, rf.visible)
        if cb_changed then
          rf.visible = new_vis
          CLB.cached_rows = nil
        end
        local cb_hovered = reaper.ImGui_IsItemHovered(ctx)

        reaper.ImGui_SameLine(ctx, 0, 4)

        -- Text label: Selectable for selection only
        local sel_label = string.format("%s (%d)##reel_sel_%d", display_name, rf.count, i)
        if is_sel then
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),        0x3366CC80)
          reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0x4477DD90)
        end
        local sel_clicked = reaper.ImGui_Selectable(ctx, sel_label, is_sel, 0, 0, 0)
        if is_sel then reaper.ImGui_PopStyleColor(ctx, 2) end

        if sel_clicked then
          local shift, ctrl = _mods()
          if shift then
            local anchor = CLB.reel_sel_anchor or i
            local lo = math.min(anchor, i)
            local hi = math.max(anchor, i)
            for j = lo, hi do CLB.reel_sel[j] = true end
          elseif ctrl then
            if CLB.reel_sel[i] then CLB.reel_sel[i] = nil
            else CLB.reel_sel[i] = true end
            CLB.reel_sel_anchor = i
          else
            CLB.reel_sel = { [i] = true }
            CLB.reel_sel_anchor = i
          end
        end
        local sel_hovered = reaper.ImGui_IsItemHovered(ctx)

        -- Tooltip + right-click (either widget)
        if cb_hovered or sel_hovered then
          local sel_count = 0
          for _ in pairs(CLB.reel_sel) do sel_count = sel_count + 1 end
          if sel_count > 1 then
            reaper.ImGui_SetTooltip(ctx, sel_count .. " reels selected — right-click to check/uncheck")
          else
            reaper.ImGui_SetTooltip(ctx, "[ ] to check/uncheck  |  Shift+click to select range")
          end
          if reaper.ImGui_IsMouseClicked(ctx, 1) then
            if not CLB.reel_sel[i] then
              CLB.reel_sel = { [i] = true }
              CLB.reel_sel_anchor = i
            end
            CLB.context_filter = { type = "reel", idx = i, name = rf.name }
            reaper.ImGui_OpenPopup(ctx, "Reel Filter Context##clb_reel_ctx")
          end
        end
      end

      -- Reel filter context menu
      local open_reel_rename, open_reel_delete, open_reel_batch = false, false, false
      if reaper.ImGui_BeginPopup(ctx, "Reel Filter Context##clb_reel_ctx") then
        if CLB.context_filter and CLB.context_filter.type == "reel" then
          -- Count selected reels
          local sel_count = 0
          for _ in pairs(CLB.reel_sel) do sel_count = sel_count + 1 end

          -- Multi-select actions (shown when 2+ reels are selected)
          if sel_count > 1 then
            reaper.ImGui_TextDisabled(ctx, sel_count .. " reels selected")
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "Check selected") then
              for idx in pairs(CLB.reel_sel) do
                if CLB.reel_filters[idx] then CLB.reel_filters[idx].visible = true end
              end
              CLB.cached_rows = nil; CLB.reel_sel = {}
            end
            if reaper.ImGui_MenuItem(ctx, "Uncheck selected") then
              for idx in pairs(CLB.reel_sel) do
                if CLB.reel_filters[idx] then CLB.reel_filters[idx].visible = false end
              end
              CLB.cached_rows = nil; CLB.reel_sel = {}
            end
            reaper.ImGui_Separator(ctx)
          end

          local display = CLB.context_filter.name ~= "" and CLB.context_filter.name or "(empty)"
          reaper.ImGui_Text(ctx, "Reel: " .. display)
          reaper.ImGui_Separator(ctx)
          if reaper.ImGui_MenuItem(ctx, "Rename...") then
            CLB.rename_filter = {
              type = "reel",
              idx = CLB.context_filter.idx,
              old_name = CLB.context_filter.name,
              buf = CLB.context_filter.name
            }
            open_reel_rename = true
          end
          if reaper.ImGui_MenuItem(ctx, "Delete...") then
            CLB.delete_filter = {
              type = "reel",
              idx = CLB.context_filter.idx,
              name = CLB.context_filter.name
            }
            open_reel_delete = true
          end
          reaper.ImGui_Separator(ctx)
          if reaper.ImGui_MenuItem(ctx, "Batch Rename All Reels...") then
            CLB.batch_rename = {
              type = "reel",
              find = "",
              replace = ""
            }
            open_reel_batch = true
          end
        end
        reaper.ImGui_EndPopup(ctx)
      end

      -- Deferred OpenPopup (must be at child window scope, not inside context menu popup)
      if open_reel_rename then reaper.ImGui_OpenPopup(ctx, "Rename Reel##clb_rename_reel") end
      if open_reel_delete then reaper.ImGui_OpenPopup(ctx, "Confirm Delete Reel##clb_del_reel") end
      if open_reel_batch then reaper.ImGui_OpenPopup(ctx, "Batch Rename Reels##clb_batch_reel") end

      -- Rename reel popup
      if CLB.rename_filter and CLB.rename_filter.type == "reel" then
        if reaper.ImGui_BeginPopup(ctx, "Rename Reel##clb_rename_reel") then
          reaper.ImGui_Text(ctx, "Rename reel:")
          reaper.ImGui_SetNextItemWidth(ctx, scale(150))
          -- Plain InputText (no EnterReturnsTrue) — that flag's returned
          -- buffer was only reliable on the exact frame Enter was pressed,
          -- so clicking OK after typing (without pressing Enter) read back
          -- the stale original name and silently no-op'd as "unchanged".
          local chg, new_buf = reaper.ImGui_InputText(ctx, "##rename_reel_input", CLB.rename_filter.buf)
          if chg then CLB.rename_filter.buf = new_buf end

          -- Focus input on first frame
          if not CLB.rename_filter.focused then
            reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
            CLB.rename_filter.focused = true
          end

          -- Apply on Enter or OK button
          local apply = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
            or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
          if reaper.ImGui_Button(ctx, "OK", scale(60), 0) then apply = true end
          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
            CLB.rename_filter = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end

          if apply and CLB.rename_filter then
            local old_name = CLB.rename_filter.old_name
            local new_name = CLB.rename_filter.buf
            if new_name ~= old_name then
              -- Update filter name
              CLB.reel_filters[CLB.rename_filter.idx].name = new_name
              -- Update all ROWS with old reel name
              for _, row in ipairs(ROWS) do
                if row.reel == old_name then
                  row.reel = new_name
                end
              end
              CLB.cached_rows = nil
            end
            CLB.rename_filter = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end

          reaper.ImGui_EndPopup(ctx)
        else
          -- Popup was closed externally
          CLB.rename_filter = nil
        end
      end

      -- Delete reel confirmation popup
      if CLB.delete_filter and CLB.delete_filter.type == "reel" then
        if reaper.ImGui_BeginPopup(ctx, "Confirm Delete Reel##clb_del_reel") then
          local display = CLB.delete_filter.name ~= "" and CLB.delete_filter.name or "(empty)"
          reaper.ImGui_Text(ctx, string.format(
            "Delete reel '%s' and all %d events?",
            display,
            CLB.reel_filters[CLB.delete_filter.idx] and CLB.reel_filters[CLB.delete_filter.idx].count or 0
          ))
          reaper.ImGui_Separator(ctx)
          if reaper.ImGui_Button(ctx, "Delete", scale(60), 0) then
            -- Remove all rows with this reel
            local del_name = CLB.delete_filter.name
            local new_rows = {}
            for _, row in ipairs(ROWS) do
              if row.reel ~= del_name then
                new_rows[#new_rows + 1] = row
              end
            end
            ROWS = new_rows
            _rebuild_reel_filters()
            CLB.cached_rows = nil
            undo_snapshot()
            CLB.delete_filter = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end
          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
            CLB.delete_filter = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end
          reaper.ImGui_EndPopup(ctx)
        else
          CLB.delete_filter = nil
        end
      end

      -- Batch rename reels popup
      if CLB.batch_rename and CLB.batch_rename.type == "reel" then
        if reaper.ImGui_BeginPopup(ctx, "Batch Rename Reels##clb_batch_reel") then
          reaper.ImGui_Text(ctx, "Find and replace in all reel names:")
          reaper.ImGui_Separator(ctx)

          reaper.ImGui_Text(ctx, "Find:")
          reaper.ImGui_SameLine(ctx, scale(80))
          reaper.ImGui_SetNextItemWidth(ctx, scale(150))
          local chg_f, new_f = reaper.ImGui_InputText(ctx, "##batch_reel_find", CLB.batch_rename.find)
          if chg_f then CLB.batch_rename.find = new_f end

          reaper.ImGui_Text(ctx, "Replace:")
          reaper.ImGui_SameLine(ctx, scale(80))
          reaper.ImGui_SetNextItemWidth(ctx, scale(150))
          local chg_r, new_r = reaper.ImGui_InputText(ctx, "##batch_reel_replace", CLB.batch_rename.replace)
          if chg_r then CLB.batch_rename.replace = new_r end

          -- Preview count
          local match_count = 0
          if CLB.batch_rename.find ~= "" then
            for _, row in ipairs(ROWS) do
              if row.reel and row.reel:find(CLB.batch_rename.find, 1, true) then
                match_count = match_count + 1
              end
            end
          end
          reaper.ImGui_TextDisabled(ctx, string.format("Will affect %d events", match_count))

          reaper.ImGui_Separator(ctx)
          if reaper.ImGui_Button(ctx, "Apply", scale(60), 0) then
            if CLB.batch_rename.find ~= "" then
              for _, row in ipairs(ROWS) do
                if row.reel then
                  row.reel = row.reel:gsub(CLB.batch_rename.find:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"), CLB.batch_rename.replace)
                end
              end
              _rebuild_reel_filters()
              CLB.cached_rows = nil
              undo_snapshot()
            end
            CLB.batch_rename = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end
          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
            CLB.batch_rename = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end

          reaper.ImGui_EndPopup(ctx)
        else
          CLB.batch_rename = nil
        end
      end

      reaper.ImGui_EndChild(ctx)
    end
    end  -- end if has_reels

    -- ===== GROUPS SECTION =====
    if has_groups then
      if has_reels then
        reaper.ImGui_Separator(ctx)
      end

      reaper.ImGui_Text(ctx, string.format("Groups (%d)", #CLB.group_filters))
      reaper.ImGui_SameLine(ctx)

      -- Add group button
      if reaper.ImGui_SmallButton(ctx, "+##clb_group_add") then
        CLB.add_group = { buf = "" }
        reaper.ImGui_OpenPopup(ctx, "Add Group##clb_add_group")
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Add new group")
      end

      -- Show All / Hide All buttons
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "All##clb_group_all") then
        for _, gf in ipairs(CLB.group_filters) do gf.visible = true end
        CLB.cached_rows = nil
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "None##clb_group_none") then
        for _, gf in ipairs(CLB.group_filters) do gf.visible = false end
        CLB.cached_rows = nil
      end

      -- Add Group popup
      if CLB.add_group then
        if reaper.ImGui_BeginPopup(ctx, "Add Group##clb_add_group") then
          reaper.ImGui_Text(ctx, "New group name:")
          reaper.ImGui_SetNextItemWidth(ctx, scale(150))
          if reaper.ImGui_IsWindowAppearing(ctx) then
            reaper.ImGui_SetKeyboardFocusHere(ctx, 0)
          end
          -- Plain InputText (no EnterReturnsTrue): that flag's returned
          -- buffer was only reliable on the exact frame Enter was pressed,
          -- so clicking OK (or Cancel/retyping) after typing without ever
          -- hitting Enter left CLB.add_group.buf stuck at "" — read by OK
          -- as an empty name even though "Delete" was visibly typed. Plain
          -- InputText reports the live buffer on every keystroke instead.
          local chg, new_buf = reaper.ImGui_InputText(ctx, "##add_group_input", CLB.add_group.buf)
          if chg then CLB.add_group.buf = new_buf end

          local apply = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
            or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
          if reaper.ImGui_Button(ctx, "OK", scale(60), 0) then apply = true end
          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
            CLB.add_group = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end

          if apply and CLB.add_group then
            -- Trim leading/trailing whitespace: a stray space typed by
            -- accident (or left over from an IME) previously produced a
            -- new group that LOOKED identical to an existing one (e.g.
            -- "Audio " next to "Audio"), which read as "add did nothing".
            local name = (CLB.add_group.buf or ""):match("^%s*(.-)%s*$")
            if name == "" then
              reaper.ShowMessageBox("Group name can't be empty.", SCRIPT_NAME, 0)
            else
              local exists = false
              for _, gf in ipairs(CLB.group_filters) do
                if gf.name == name then exists = true; break end
              end
              if exists then
                reaper.ShowMessageBox("A group named '" .. name .. "' already exists.", SCRIPT_NAME, 0)
              else
                CLB.group_filters[#CLB.group_filters + 1] = {
                  name = name, count = 0, visible = true, tracks = {}
                }
                CLB.add_group = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
              end
            end
          end

          reaper.ImGui_EndPopup(ctx)
        else
          CLB.add_group = nil
        end
      end

      reaper.ImGui_Separator(ctx)

      -- Group checkboxes (vertical list, scrollable)
      local _, group_list_h = reaper.ImGui_GetContentRegionAvail(ctx)
      if group_list_h < 30 then group_list_h = 30 end
      local open_group_ctx = false
      if reaper.ImGui_BeginChild(ctx, "##clb_group_list", 0, group_list_h) then
        for i, gf in ipairs(CLB.group_filters) do
          local display_name = gf.name ~= "" and gf.name or "(Unassigned)"
          local label = string.format("%s (%d)##clb_group_%d", display_name, gf.count, i)
          local changed, new_val = reaper.ImGui_Checkbox(ctx, label, gf.visible)
          if changed then
            gf.visible = new_val
            CLB.cached_rows = nil
          end
          -- Right-click context menu + tooltip
          if reaper.ImGui_IsItemHovered(ctx) then
            local track_list = table.concat(gf.tracks or {}, ", ")
            local tip = ""
            if track_list ~= "" then tip = "Tracks: " .. track_list .. "\n" end
            tip = tip .. "Right-click for options"
            reaper.ImGui_SetTooltip(ctx, tip)
            if reaper.ImGui_IsMouseClicked(ctx, 1) then
              CLB.context_filter = { type = "group", idx = i, name = gf.name }
              open_group_ctx = true
            end
          end
        end

        -- Group context menu
        if open_group_ctx then
          reaper.ImGui_OpenPopup(ctx, "Group Filter Context##clb_group_ctx")
        end

        local open_grp_rename, open_grp_delete = false, false
        if reaper.ImGui_BeginPopup(ctx, "Group Filter Context##clb_group_ctx") then
          if CLB.context_filter and CLB.context_filter.type == "group" then
            local display = CLB.context_filter.name ~= "" and CLB.context_filter.name or "(Unassigned)"
            reaper.ImGui_Text(ctx, "Group: " .. display)
            reaper.ImGui_Separator(ctx)
            if CLB.context_filter.name ~= "" then
              if reaper.ImGui_MenuItem(ctx, "Rename...") then
                CLB.rename_filter = {
                  type = "group",
                  idx = CLB.context_filter.idx,
                  old_name = CLB.context_filter.name,
                  buf = CLB.context_filter.name,
                  focused = false,
                }
                open_grp_rename = true
              end
              if reaper.ImGui_MenuItem(ctx, "Delete Group...") then
                CLB.delete_filter = {
                  type = "group",
                  idx = CLB.context_filter.idx,
                  name = CLB.context_filter.name,
                }
                open_grp_delete = true
              end
              reaper.ImGui_Separator(ctx)
            end
            if reaper.ImGui_MenuItem(ctx, "Assign Selected Rows Here") then
              local sel_rows = get_selected_rows()
              if #sel_rows > 0 then
                for _, row in ipairs(sel_rows) do
                  row.group = CLB.context_filter.name
                end
                _rebuild_group_filters()
                CLB.cached_rows = nil
                undo_snapshot()
              end
            end
          end
          reaper.ImGui_EndPopup(ctx)
        end

        -- Deferred OpenPopup (must be at child window scope)
        if open_grp_rename then reaper.ImGui_OpenPopup(ctx, "Rename Group##clb_rename_group") end
        if open_grp_delete then reaper.ImGui_OpenPopup(ctx, "Confirm Delete Group##clb_del_group") end

        -- Rename group popup
        if CLB.rename_filter and CLB.rename_filter.type == "group" then
          if reaper.ImGui_BeginPopup(ctx, "Rename Group##clb_rename_group") then
            reaper.ImGui_Text(ctx, "Rename group:")
            reaper.ImGui_SetNextItemWidth(ctx, scale(150))
            -- Plain InputText (no EnterReturnsTrue) — see the Add Group
            -- popup for why: that flag's returned buffer was only reliable
            -- on the exact frame Enter was pressed, so clicking OK after
            -- typing (without pressing Enter) read back the stale original
            -- name and silently no-op'd as "unchanged".
            local chg, new_buf = reaper.ImGui_InputText(ctx, "##rename_group_input", CLB.rename_filter.buf)
            if chg then CLB.rename_filter.buf = new_buf end

            if not CLB.rename_filter.focused then
              reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
              CLB.rename_filter.focused = true
            end

            local apply = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter(), false)
              or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadEnter(), false)
            if reaper.ImGui_Button(ctx, "OK", scale(60), 0) then apply = true end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
              CLB.rename_filter = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
            end

            if apply and CLB.rename_filter then
              local old_name = CLB.rename_filter.old_name
              -- Trim whitespace — see the Add Group popup for why (a
              -- trailing/leading space made the rename look like it "did
              -- nothing" since the result was visually indistinguishable
              -- from an existing name).
              local new_name = (CLB.rename_filter.buf or ""):match("^%s*(.-)%s*$")
              if new_name == "" then
                reaper.ShowMessageBox("Group name can't be empty.", SCRIPT_NAME, 0)
              elseif new_name == old_name then
                CLB.rename_filter = nil
                reaper.ImGui_CloseCurrentPopup(ctx)
              else
                local collides = false
                for _, gf in ipairs(CLB.group_filters) do
                  if gf.name == new_name then collides = true; break end
                end
                if collides then
                  reaper.ShowMessageBox("A group named '" .. new_name .. "' already exists.", SCRIPT_NAME, 0)
                else
                  -- Update filter name
                  for _, gf in ipairs(CLB.group_filters) do
                    if gf.name == old_name then gf.name = new_name; break end
                  end
                  -- Update all rows with old group name
                  for _, row in ipairs(ROWS) do
                    if row.group == old_name then
                      row.group = new_name
                    end
                  end
                  _rebuild_group_filters()
                  CLB.cached_rows = nil
                  undo_snapshot()
                  CLB.rename_filter = nil
                  reaper.ImGui_CloseCurrentPopup(ctx)
                end
              end
            end

            reaper.ImGui_EndPopup(ctx)
          else
            CLB.rename_filter = nil
          end
        end

        -- Delete group confirmation popup
        if CLB.delete_filter and CLB.delete_filter.type == "group" then
          if reaper.ImGui_BeginPopup(ctx, "Confirm Delete Group##clb_del_group") then
            local display = CLB.delete_filter.name ~= "" and CLB.delete_filter.name or "(Unassigned)"
            local del_count = 0
            for _, gf in ipairs(CLB.group_filters) do
              if gf.name == CLB.delete_filter.name then del_count = gf.count; break end
            end
            reaper.ImGui_Text(ctx, string.format(
              "Remove group '%s'?\n%d events will become unassigned.",
              display, del_count
            ))
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_Button(ctx, "Remove", scale(60), 0) then
              local del_name = CLB.delete_filter.name
              -- Unassign rows in this group
              for _, row in ipairs(ROWS) do
                if row.group == del_name then
                  row.group = ""
                end
              end
              -- Remove from group_filters
              for gi = #CLB.group_filters, 1, -1 do
                if CLB.group_filters[gi].name == del_name then
                  table.remove(CLB.group_filters, gi)
                  break
                end
              end
              _rebuild_group_filters()
              CLB.cached_rows = nil
              undo_snapshot()
              CLB.delete_filter = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
              CLB.delete_filter = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
          else
            CLB.delete_filter = nil
          end
        end

        reaper.ImGui_EndChild(ctx)
      end
    end  -- end if has_groups

    reaper.ImGui_EndChild(ctx)
  end

  reaper.ImGui_SameLine(ctx)
  return true
end

---------------------------------------------------------------------------
-- Draw: Compare View (old-vs-new reconform dual timeline)
---------------------------------------------------------------------------
CMP.colors = {
  Deleted  = 0xCC3333FF,
  Trimmed  = 0x33AA55FF,
  Extended = 0xCCAA22FF,
  Moved    = 0x3388CCFF,  -- individual Moved (unique delta, one item)
  Shift    = 0x556688FF,  -- many items sharing the exact same delta (a whole block
                            -- displaced together — global offset, or the downstream
                            -- effect of something inserted/removed earlier)
  Added    = 0xAA55CCFF,
}
CMP.unchanged_color = 0x4A4A4ABB

--- Color key for a dedup event: same as its change_type, except a "Moved"
--- event that belongs to a multi-item (shared-delta) group shows as the
--- dimmer "Shift" color instead of the bright individual-move blue.
function CMP.color_key(e)
  if e.change_type == "Moved" and e.change_group and e.change_group.is_shift then
    return "Shift"
  end
  return e.change_type
end

--- Draw one half (SRC/old or DEST/new) of the Compare view. Both panels
--- show each event at its own raw absolute REC TC — no ripple/base-offset
--- normalization (see hsuanice_CLB Compare Engine.lua's M.compare doc
--- comment for why).
--- events: cr.old_dedup or cr.new_dedup (see CMP.run()); each has
---   reel, tracks[], rec_in/out (seconds), clip_name, change_type (nil =
---   Unchanged), change_group.
function CMP.draw_side(title, events, track_order, track_index, tmin, tmax, panel_h, is_dest, child_id, fps_val, is_drop_val, hidden_tracks, hidden_reels, hidden_groups)
  local LABEL_W = scale(50)
  local RULER_H = scale(16)
  local TRACK_H = scale(16)

  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  local wf = reaper.ImGui_WindowFlags_NoScrollbar() | reaper.ImGui_WindowFlags_NoScrollWithMouse()
  if not reaper.ImGui_BeginChild(ctx, "##" .. child_id, avail_w, panel_h, 0, wf) then
    reaper.ImGui_EndChild(ctx)
    return
  end

  local cw, ch = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_InvisibleButton(ctx, "##" .. child_id .. "_cvs", cw, ch)
  local is_hovered = reaper.ImGui_IsItemHovered(ctx)
  local is_active  = reaper.ImGui_IsItemActive(ctx)

  local cx0, cy0 = reaper.ImGui_GetItemRectMin(ctx)
  local cx1, cy1 = reaper.ImGui_GetItemRectMax(ctx)

  local ea_x0 = cx0 + LABEL_W
  local ea_w  = math.max(1, cx1 - ea_x0)

  local dl = reaper.ImGui_GetWindowDrawList(ctx)

  local span     = tmax - tmin
  local min_zoom = ea_w / span
  local max_zoom = 500.0
  CLB.cmp_zoom   = math.max(min_zoom, math.min(max_zoom, CLB.cmp_zoom))
  local vis_sec  = ea_w / CLB.cmp_zoom
  local max_scroll = math.max(0, span - vis_sec)
  CLB.cmp_scroll = math.max(0, math.min(max_scroll, CLB.cmp_scroll))

  local function s2px(t)
    return ea_x0 + (t - tmin - CLB.cmp_scroll) * CLB.cmp_zoom
  end

  reaper.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx1, cy1, 0x1A1A1AFF)
  reaper.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx0 + LABEL_W, cy1, 0x252525FF)

  local ry0, ry1 = cy0, cy0 + RULER_H
  reaper.ImGui_DrawList_AddRectFilled(dl, ea_x0, ry0, cx1, ry1, 0x2A2A2AFF)
  reaper.ImGui_DrawList_AddText(dl, cx0 + scale(3), ry0 + scale(2), 0xCCCCCCFF, title)

  local fps_val = fps_val or CLB.fps or 24
  local is_drop_val = is_drop_val or false
  local frame_dur = 1.0 / fps_val
  local intervals = {
    frame_dur, frame_dur * 2, frame_dur * 5, frame_dur * 10,
    1, 2, 5, 10, 15, 30, 60, 120, 300, 600,
  }
  local tick_iv = 600
  for _, iv in ipairs(intervals) do
    if iv * CLB.cmp_zoom >= scale(80) then tick_iv = iv; break end
  end
  local view_start = tmin + CLB.cmp_scroll
  local view_end   = view_start + vis_sec
  local t = math.floor(view_start / tick_iv) * tick_iv
  while t <= view_end + tick_iv do
    local px = s2px(t)
    if px >= ea_x0 and px <= cx1 then
      reaper.ImGui_DrawList_AddLine(dl, px, ry0, px, ry1, 0x555555FF, 1.0)
      local lbl = EDL.seconds_to_tc(math.max(0, t), fps_val, is_drop_val)
      if px + scale(4) < cx1 then
        reaper.ImGui_DrawList_AddText(dl, px + scale(2), ry0 + scale(2), 0xAAAAAAFF, lbl)
      end
    end
    t = t + tick_iv
  end
  reaper.ImGui_DrawList_AddLine(dl, cx0, ry1, cx1, ry1, 0x444444FF, 1.0)

  local vscroll = is_dest and CLB.cmp_vscroll_new or CLB.cmp_vscroll_old
  for ti, tname in ipairs(track_order) do
    local ey0 = ry1 + (ti - 1) * TRACK_H - vscroll
    local ey1 = ey0 + TRACK_H
    if ey1 > ry1 and ey0 < cy1 then
      local bg = (ti % 2 == 0) and 0x222222FF or 0x1E1E1EFF
      local dy0, dy1 = math.max(ey0, ry1), math.min(ey1, cy1)
      reaper.ImGui_DrawList_AddRectFilled(dl, cx0, dy0, cx1, dy1, bg)
      if ey0 >= ry1 then
        reaper.ImGui_DrawList_AddText(dl, cx0 + scale(3), ey0 + scale(2), 0xCCCCCCFF, tname)
      end
      reaper.ImGui_DrawList_AddLine(dl, cx0, dy1, cx1, dy1, 0x333333FF, 1.0)
    end
  end

  local mx, my = reaper.ImGui_GetMousePos(ctx)
  local hovered = nil
  for _, e in ipairs(events) do
    local reel_hidden  = hidden_reels  and hidden_reels[e.reel or ""]
    local group_hidden = hidden_groups and hidden_groups[CMP.event_category(e)]
    if not reel_hidden and not group_hidden then
    local px0, px1 = s2px(e.rec_in), s2px(e.rec_out)
    if px1 >= ea_x0 and px0 <= cx1 then
      local dx0 = math.max(px0, ea_x0)
      local dx1 = math.min(px1, cx1)
      if dx1 < dx0 + 1 then dx1 = dx0 + 1 end
      local col = CMP.colors[CMP.color_key(e)] or CMP.unchanged_color
      for _, trk in ipairs(e.tracks) do
        local ti = (not (hidden_tracks and hidden_tracks[trk])) and track_index[trk]
        if ti then
          local ey0 = ry1 + (ti - 1) * TRACK_H - vscroll
          local ey1 = ey0 + TRACK_H
          if ey1 > ry1 and ey0 < cy1 then
            local dy0, dy1 = math.max(ey0, ry1), math.min(ey1, cy1)
            reaper.ImGui_DrawList_AddRectFilled(dl, dx0, dy0, dx1, dy1, col)
            reaper.ImGui_DrawList_AddRect(dl, dx0, dy0, dx1, dy1, 0x00000066)
            if is_hovered and mx >= dx0 and mx <= dx1 and my >= dy0 and my <= dy1 then
              reaper.ImGui_DrawList_AddRectFilled(dl, dx0, dy0, dx1, dy1, 0xFFFFFF22)
              hovered = e
            end
          end
        end
      end
    end
    end
  end

  if hovered then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, hovered.clip_name ~= "" and hovered.clip_name or "(no name)")
    reaper.ImGui_Text(ctx, "Reel:   " .. (hovered.reel or ""))
    reaper.ImGui_Text(ctx, "Tracks: " .. table.concat(hovered.tracks, ", "))
    reaper.ImGui_Text(ctx, "Change: " .. (hovered.change_type or "Unchanged"))
    if hovered.change_group then
      reaper.ImGui_Text(ctx, "Group:  " .. hovered.change_group.label)
    end
    reaper.ImGui_Text(ctx, "Rec In:  " .. EDL.seconds_to_tc(hovered.rec_in, fps_val, is_drop_val))
    reaper.ImGui_Text(ctx, "Rec Out: " .. EDL.seconds_to_tc(hovered.rec_out, fps_val, is_drop_val))
    reaper.ImGui_Text(ctx, "(click to move edit cursor here)")
    reaper.ImGui_EndTooltip(ctx)
  end

  -- Click a block → move Reaper's edit cursor to its Rec TC In and scroll
  -- the arrange view to it (SRC blocks use the old TC, DEST blocks the
  -- new TC — each panel already carries its own side's native position),
  -- so old/new material can be checked directly in the Reaper session
  -- without leaving Compare (mirrors Matchbox's old/new jump behavior).
  if is_hovered and hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
    reaper.SetEditCurPos(hovered.rec_in, true, false)
  end

  -- Scroll wheel: plain = vertical, alt = horizontal zoom (mirrors draw_timeline_panel)
  if is_hovered then
    local ok_w, scroll_y, scroll_h = pcall(reaper.ImGui_GetMouseWheel, ctx)
    if ok_w then
      local alt_held = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Mod_Alt())
      if alt_held and scroll_y and scroll_y ~= 0 then
        local mouse_t  = (mx - ea_x0) / CLB.cmp_zoom + tmin + CLB.cmp_scroll
        local factor   = scroll_y > 0 and 1.15 or (1 / 1.15)
        local new_zoom = math.max(min_zoom, math.min(max_zoom, CLB.cmp_zoom * factor))
        CLB.cmp_scroll = mouse_t - tmin - (mx - ea_x0) / new_zoom
        CLB.cmp_zoom   = new_zoom
        local new_vis  = ea_w / CLB.cmp_zoom
        local new_max  = math.max(0, span - new_vis)
        CLB.cmp_scroll = math.max(0, math.min(new_max, CLB.cmp_scroll))
      elseif scroll_h and scroll_h ~= 0 then
        CLB.cmp_scroll = math.max(0, math.min(max_scroll, CLB.cmp_scroll - scroll_h / CLB.cmp_zoom * 60))
      elseif not alt_held and scroll_y and scroll_y ~= 0 then
        local nv = math.max(0, vscroll - scroll_y * TRACK_H * 3)
        if is_dest then CLB.cmp_vscroll_new = nv else CLB.cmp_vscroll_old = nv end
      end
    end
  end

  -- Drag: horizontal pan
  if is_active then
    local dx = reaper.ImGui_GetMouseDelta(ctx)
    if dx and dx ~= 0 then
      CLB.cmp_scroll = math.max(0, math.min(max_scroll, CLB.cmp_scroll - dx / CLB.cmp_zoom))
    end
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
  end

  reaper.ImGui_EndChild(ctx)
end

--- Top-level Compare view: header/summary/legend + dual SRC/DEST timeline
--- (see draw_cmp_side). Shown instead of the normal table when
--- CLB.show_compare_view is true (see run_compare() and draw_main_content()).
--- Convert a Compare result's recut groups into ROWS-shaped table rows —
--- one row per group instead of one per raw EDL event — so "Show as Table"
--- can reuse the main table's existing sort/filter/search/right-click
--- group-rename machinery for free. The category (Video/Audio/Other, or
--- whatever the user has curated) is inherited by majority vote from the
--- original rows' own .group field, so groups loaded from a .clb session
--- keep their existing classification.
--- Convert Compare's recut groups into ROWS-shaped rows. Change items whose
--- representative event's reel/category is currently hidden via the
--- Track/Reel/Group filter panels (see CMP.rebuild_filters) are excluded
--- from the group's aggregate, and a group left with zero visible items is
--- skipped entirely — so "Show as Table" respects the same filters as the
--- graphical view (CMP.draw_side) rather than always showing everything.
function CMP.build_group_rows(cr)
  local fps, is_drop = cr.fps or CLB.fps, cr.is_drop or false
  local rows = {}

  local hidden_reels, hidden_groups
  for _, rf in ipairs(CLB.reel_filters) do
    if not rf.visible then hidden_reels = hidden_reels or {}; hidden_reels[rf.name] = true end
  end
  for _, gf in ipairs(CLB.group_filters) do
    if not gf.visible then hidden_groups = hidden_groups or {}; hidden_groups[gf.name] = true end
  end

  for idx, g in ipairs(cr.groups) do
    local tracks_set, reels_set, cat_votes = {}, {}, {}
    local rec_min, rec_max, src_min, src_max
    local visible_items = 0

    for _, c in ipairs(g.items) do
      local rep = c.new or c.old
      local reel_hidden  = hidden_reels  and hidden_reels[rep.reel or ""]
      local group_hidden = hidden_groups and hidden_groups[CMP.event_category(rep)]
      if not reel_hidden and not group_hidden then
        visible_items = visible_items + 1
        for _, t in ipairs(rep.tracks or {}) do tracks_set[t] = true end
        if rep.reel and rep.reel ~= "" then reels_set[rep.reel] = true end
        if not rec_min or rep.rec_in < rec_min then rec_min = rep.rec_in end
        if not rec_max or rep.rec_out > rec_max then rec_max = rep.rec_out end
        if not src_min or rep.src_in < src_min then src_min = rep.src_in end
        if not src_max or rep.src_out > src_max then src_max = rep.src_out end
        for _, orig_row in ipairs(rep.__rows or {}) do
          local cat = orig_row.group
          if cat and cat ~= "" then cat_votes[cat] = (cat_votes[cat] or 0) + 1 end
        end
      end
    end

    if visible_items == 0 then goto next_group end
    _guid_counter = _guid_counter + 1

    local tracks, reels = {}, {}
    for t in pairs(tracks_set) do tracks[#tracks + 1] = t end
    for r in pairs(reels_set) do reels[#reels + 1] = r end
    table.sort(tracks); table.sort(reels)

    local best_cat, best_n = "", 0
    for cat, n in pairs(cat_votes) do
      if n > best_n then best_cat, best_n = cat, n end
    end

    rec_min, rec_max = rec_min or 0, rec_max or 0
    src_min, src_max = src_min or 0, src_max or 0
    local row = {
      __event_idx  = _guid_counter,
      __guid       = string.format("clb_%06d", _guid_counter),
      __source_idx = 0,
      __orig_track = "",
      __compare_group = g,
      event_num    = string.format("%03d", idx),
      reel         = table.concat(reels, ", "),
      track        = table.concat(tracks, ","),
      edit_type    = "C",
      src_tc_in    = EDL.seconds_to_tc(src_min, fps, is_drop),
      src_tc_out   = EDL.seconds_to_tc(src_max, fps, is_drop),
      rec_tc_in    = EDL.seconds_to_tc(rec_min, fps, is_drop),
      rec_tc_out   = EDL.seconds_to_tc(rec_max, fps, is_drop),
      clip_name    = g.label,
      source_file  = "",
      notes        = string.format("%s | %d item(s)", g.type, visible_items),
      match_status = "",
      matched_path = "",
      group        = best_cat,
      level        = "",
      scene        = "",
      take         = "",
      audio_levels = {},
      duration     = EDL.seconds_to_tc(rec_max - rec_min, fps, is_drop),
    }
    row.__search_text = table.concat({
      row.event_num, row.reel, row.track, row.clip_name, row.notes, row.group,
    }, " "):lower()
    rows[#rows + 1] = row
    ::next_group::
  end

  return rows
end

--- Save the current Compare result's recut groups directly to a .clb file,
--- without disturbing whatever the user has loaded in the main table (works
--- even if "Show as Table" was never clicked). Temporarily swaps ROWS /
--- sources / loaded_file for the save, then restores them exactly.
--- Write one row in the same pipe-delimited shape save_clb_project() uses
--- for its "R|" lines, but with a caller-supplied prefix — a Compare
--- Session file holds two row-sets (old + new) in one file, and the
--- prefix ("OR"/"NR") is what tells them apart unambiguously on read-back.
local function _write_cmp_row(f, prefix, row)
  f:write(string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%s\n",
    prefix,
    _clb_escape(row.event_num or ""), _clb_escape(row.reel or ""), _clb_escape(row.track or ""),
    _clb_escape(row.edit_type or ""), _clb_escape(tostring(row.dissolve_len or "")),
    _clb_escape(row.src_tc_in or ""), _clb_escape(row.src_tc_out or ""),
    _clb_escape(row.rec_tc_in or ""), _clb_escape(row.rec_tc_out or ""),
    _clb_escape(row.clip_name or ""), _clb_escape(row.source_file or ""), _clb_escape(row.notes or ""),
    _clb_escape(row.match_status or ""), _clb_escape(row.matched_path or ""), _clb_escape(row.group or ""),
    _clb_escape(row.__orig_track or ""), row.__source_idx or 0,
    _clb_escape(row.level or ""), _clb_escape(row.scene or ""), _clb_escape(row.take or ""),
    _clb_escape(row.aux_rate and tostring(row.aux_rate) or "")))
end

local function _read_cmp_row(p)
  return {
    event_num = p[2] or "", reel = p[3] or "", track = p[4] or "",
    edit_type = p[5] or "C", dissolve_len = (p[6] and p[6] ~= "") and tonumber(p[6]) or nil,
    src_tc_in = p[7] or "00:00:00:00", src_tc_out = p[8] or "00:00:00:00",
    rec_tc_in = p[9] or "00:00:00:00", rec_tc_out = p[10] or "00:00:00:00",
    clip_name = p[11] or "", source_file = p[12] or "", notes = p[13] or "",
    match_status = p[14] or "", matched_path = p[15] or "", group = p[16] or "",
    __orig_track = p[17] or "", __source_idx = tonumber(p[18]) or 0,
    level = p[19] or "", scene = p[20] or "", take = p[21] or "",
    aux_rate = (p[22] and p[22] ~= "") and tonumber(p[22]) or nil,
  }
end

--- Save a full Compare Session — CLB.compare_old/.compare_new's raw rows,
--- names and fps/is_drop. That's all that's needed: dedup/compare/group/
--- tagging are pure functions of those two row-sets (see CMP.run), so
--- reloading a session and re-running it reproduces the graphical SRC/DEST
--- view, the live Details panel, and "Show as Table" exactly — unlike the
--- old behavior (removed) of saving only the flattened group-summary table,
--- which lost that context irreversibly on reload.
--- @return boolean ok
function CMP.save_session(filepath)
  if not (CLB.compare_old and CLB.compare_new) then return false end
  local f = io.open(filepath, "w")
  if not f then
    reaper.ShowMessageBox("Cannot write to:\n" .. filepath, SCRIPT_NAME, 0)
    return false
  end

  f:write("CLB_COMPARE_V1\n")
  f:write(string.format("OLD|%s|%s|%s|%s\n",
    _clb_escape(CLB.compare_old.name), _clb_escape(CLB.compare_old.path or ""),
    tostring(CLB.compare_old.fps), CLB.compare_old.is_drop and "1" or "0"))
  f:write(string.format("OLD_ROWS|%d\n", #CLB.compare_old.rows))
  for _, row in ipairs(CLB.compare_old.rows) do _write_cmp_row(f, "OR", row) end

  f:write(string.format("NEW|%s|%s|%s|%s\n",
    _clb_escape(CLB.compare_new.name), _clb_escape(CLB.compare_new.path or ""),
    tostring(CLB.compare_new.fps), CLB.compare_new.is_drop and "1" or "0"))
  f:write(string.format("NEW_ROWS|%d\n", #CLB.compare_new.rows))
  for _, row in ipairs(CLB.compare_new.rows) do _write_cmp_row(f, "NR", row) end

  f:close()
  return true
end

--- Save-as dialog → CMP.save_session. Default extension .clbcmp (distinct
--- from a normal .clb project) so it's clear at the file picker which kind
--- of file it is, and so it fails cleanly (not silently) if opened via the
--- normal "Open..." (CLB_PROJECT_V1 header check).
function CMP.save_session_dialog()
  if not (CLB.compare_old and CLB.compare_new) then
    reaper.ShowMessageBox("Load both the OLD and NEW versions first.", SCRIPT_NAME, 0)
    return
  end
  local function base(name) return (name or ""):gsub("%.%w+$", "") end
  local default = string.format("Compare_%s_vs_%s_%s.clbcmp",
    base(CLB.compare_old.name), base(CLB.compare_new.name), os.date("%Y%m%d_%H%M"))
  local filepath = choose_save_path(default, "CLB Compare Session (*.clbcmp)\0*.clbcmp\0All files\0*.*\0")
  if not filepath then return end
  if not filepath:match("%.clbcmp$") then filepath = filepath .. ".clbcmp" end
  CLB.last_dir = filepath:match("^(.*)[/\\]") or CLB.last_dir
  if CMP.save_session(filepath) then
    console_msg("Compare: saved session to " .. filepath)
  end
  save_prefs()
end

--- Pure parser for a .clbcmp Compare Session file — no live-state side
--- effects, mirroring _parse_clb_file's shape.
--- @return table|nil { old={name,path,fps,is_drop,rows}, new={...} }
--- @return string|nil error message if nil was returned
function CMP._parse_session_file(filepath)
  local f = io.open(filepath, "r")
  if not f then return nil, "Cannot open:\n" .. filepath end
  local header = f:read("*l")
  if header ~= "CLB_COMPARE_V1" then
    f:close()
    return nil, "Not a valid CLB Compare Session file."
  end

  local old_meta, new_meta = { rows = {} }, { rows = {} }
  for line in f:lines() do
    if line ~= "" then
      local p = _clb_split(line)
      local key = p[1]
      if key == "OLD" then
        old_meta.name, old_meta.path = p[2] or "", p[3] or ""
        old_meta.fps, old_meta.is_drop = tonumber(p[4]) or 25, p[5] == "1"
      elseif key == "NEW" then
        new_meta.name, new_meta.path = p[2] or "", p[3] or ""
        new_meta.fps, new_meta.is_drop = tonumber(p[4]) or 25, p[5] == "1"
      elseif key == "OR" then
        old_meta.rows[#old_meta.rows + 1] = _read_cmp_row(p)
      elseif key == "NR" then
        new_meta.rows[#new_meta.rows + 1] = _read_cmp_row(p)
      end
    end
  end
  f:close()

  return { old = old_meta, new = new_meta }
end

--- Load a .clbcmp Compare Session file: restores CLB.compare_old/.new and
--- re-runs CMP.run() — this alone reconstructs the graphical view, the
--- live Details panel, and everything "Show as Table" needs, since they're
--- all pure functions of the two row-sets.
function CMP.load_session(filepath)
  local data, err = CMP._parse_session_file(filepath)
  if not data then
    reaper.ShowMessageBox("Failed to load:\n\n" .. tostring(err), SCRIPT_NAME, 0)
    return
  end
  CLB.compare_old = data.old
  CLB.compare_new = data.new
  CLB.compare_result = nil
  console_msg(string.format("Compare: loaded session — %s (%d rows) vs %s (%d rows)",
    data.old.name, #data.old.rows, data.new.name, #data.new.rows))
  CMP.run()
end

--- File-open dialog → CMP.load_session.
function CMP.load_session_dialog()
  local filepath
  if reaper.JS_Dialog_BrowseForOpenFiles then
    local rv, fp = reaper.JS_Dialog_BrowseForOpenFiles(
      "Load Compare Session", CLB.last_dir or "", "",
      "CLB Compare Session (*.clbcmp)\0*.clbcmp\0All files\0*.*\0", false)
    if rv ~= 1 or not fp or fp == "" then return end
    filepath = fp
  else
    local retval, fp = reaper.GetUserFileNameForRead("", "Load Compare Session", "*.clbcmp")
    if not retval or fp == "" then return end
    filepath = fp
  end
  CLB.last_dir = filepath:match("(.*[/\\])") or CLB.last_dir
  CMP.load_session(filepath)
end

local function _html_escape(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
  return s
end

--- Generate a self-contained HTML report of exactly what an Apply run did
--- (track, item, action, which strategy resolved it) and open it in the
--- default browser — mirrors Reaper's own render-completion result page,
--- so there's a reviewable/archivable record beyond the in-session console
--- log and the timeline markers.
--- @param title string           e.g. "Apply Deleted"
--- @param summary_line string    one-line run summary
--- @param rows table             { { track_name, take_name, action, mode, old_in_tc, old_out_tc, target_label, status } }
---   status: "done" | "partial" | "skipped" | "none" — drives the row's color band
function CMP.write_apply_report(title, summary_line, rows)
  local report_dir = reaper.GetResourcePath() .. "/CLB_Apply_Reports"
  reaper.RecursiveCreateDirectory(report_dir, 0)
  local filepath = string.format("%s/CLB_Apply_%s.html", report_dir, os.date("%Y%m%d_%H%M%S"))

  local f = io.open(filepath, "w")
  if not f then
    console_msg("Apply report: could not write to " .. filepath)
    return nil
  end

  f:write("<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">\n")
  f:write("<title>" .. _html_escape(title) .. "</title>\n<style>\n")
  f:write([[
    body { font-family: -apple-system, Helvetica, Arial, sans-serif; background:#1e1e1e; color:#ddd; margin:24px; }
    h1 { font-size:18px; margin-bottom:4px; }
    .meta { color:#999; font-size:12px; margin-bottom:16px; }
    .summary { background:#2a2a2a; border-left:3px solid #5599cc; padding:8px 12px; margin-bottom:20px; font-size:13px; }
    table { border-collapse:collapse; width:100%; font-size:12px; }
    th, td { text-align:left; padding:6px 10px; border-bottom:1px solid #333; }
    th { background:#2a2a2a; color:#aaa; font-weight:600; position:sticky; top:0; }
    tr:hover { background:#262626; }
    .badge { display:inline-block; padding:1px 8px; border-radius:3px; font-size:11px; font-weight:600; }
    .status-done    { background:#2d5c2d; color:#a6e0a6; }
    .status-partial { background:#6b5a1e; color:#f0d38a; }
    .status-skipped { background:#444; color:#ccc; }
    .status-none    { background:#5c2d2d; color:#e0a6a6; }
    .mono { font-family: ui-monospace, Menlo, monospace; }
  ]])
  f:write("</style></head><body>\n")
  f:write("<h1>" .. _html_escape(title) .. "</h1>\n")
  f:write("<div class=\"meta\">" .. os.date("%Y-%m-%d %H:%M:%S") .. "</div>\n")
  f:write("<div class=\"summary\">" .. _html_escape(summary_line) .. "</div>\n")
  f:write("<table>\n<tr><th>Track</th><th>Take Name</th><th>Status</th><th>Action</th><th>Strategy</th><th>Old Rec TC In</th><th>Old Rec TC Out</th><th>Target</th></tr>\n")
  for _, r in ipairs(rows) do
    f:write(string.format(
      "<tr><td>%s</td><td>%s</td><td><span class=\"badge status-%s\">%s</span></td><td>%s</td><td>%s</td><td class=\"mono\">%s</td><td class=\"mono\">%s</td><td>%s</td></tr>\n",
      _html_escape(r.track_name or ""), _html_escape(r.take_name or ""), r.status or "done",
      _html_escape((r.status or "done"):upper()), _html_escape(r.action or ""), _html_escape(r.mode or ""),
      _html_escape(r.old_in_tc or ""), _html_escape(r.old_out_tc or ""), _html_escape(r.target_label or "")))
  end
  f:write("</table>\n</body></html>\n")
  f:close()

  os.execute(string.format('open %s', ("'" .. filepath:gsub("'", "'\\''") .. "'")))
  console_msg("Apply report saved: " .. filepath)
  return filepath
end

--- Finds whatever's physically on `track` overlapping [range_start,
--- range_end] (TOL-tolerant), splits it at the range edges as needed so
--- content outside the range is left untouched, and shifts the isolated
--- portion by `delta` seconds. A locked item is unlocked before
--- splitting/moving and every resulting piece is re-locked afterward, so
--- a locked item straddling the range edge ends up as a locked remainder
--- plus a locked, moved piece — same lock intent, just split.
---
--- Snapshots the track's item pointers fresh right before scanning (not a
--- live index loop) — REAPER's own per-track item index order isn't
--- guaranteed stable once items are split/repositioned mid-scan, the
--- exact bug class CLB.dme_recut_execute's Cut mode hit and fixed this
--- same way. Shared by CMP.shift_range (below) and DME Recut's Cut mode.
function CLB.cut_shift_range(track, range_start, range_end, delta, TOL)
  local snap = {}
  local n = reaper.CountTrackMediaItems(track)
  for i = 0, n - 1 do snap[#snap + 1] = reaper.GetTrackMediaItem(track, i) end
  local moved = 0
  for _, item in ipairs(snap) do
    local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local iend = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local overlap_start = math.max(pos, range_start)
    local overlap_end   = math.min(iend, range_end)
    if overlap_end > overlap_start + TOL then
      local orig_locked = (reaper.GetMediaItemInfo_Value(item, "C_LOCK") & 1) == 1
      local pieces = { item }
      if orig_locked then reaper.SetMediaItemInfo_Value(item, "C_LOCK", 0) end

      local working = item
      if overlap_start > pos + TOL then
        local right = reaper.SplitMediaItem(working, overlap_start)
        if right then working = right; pieces[#pieces + 1] = right end
      end
      local w_pos = reaper.GetMediaItemInfo_Value(working, "D_POSITION")
      local w_len = reaper.GetMediaItemInfo_Value(working, "D_LENGTH")
      if overlap_end < w_pos + w_len - TOL then
        local right2 = reaper.SplitMediaItem(working, overlap_end)
        if right2 then pieces[#pieces + 1] = right2 end
      end

      reaper.SetMediaItemInfo_Value(working, "D_POSITION", w_pos + delta)

      if orig_locked then
        for _, p in ipairs(pieces) do reaper.SetMediaItemInfo_Value(p, "C_LOCK", 1) end
      end
      moved = moved + 1
    end
  end
  return moved
end

--- Shifts every project marker/region whose position falls within any of
--- `windows` (a list of {start=,stop=}, time-only — track selection has no
--- meaning for markers/regions) by `delta` seconds. A marker counts as
--- in-range if its own position falls in a window; a region counts only
--- if BOTH its start and end fall within the SAME window — one straddling
--- a window edge is left alone rather than guessing how to resolve it.
---
--- Repositions each hit IN PLACE via SetProjectMarker4 (same ID number,
--- same call) rather than deleting and recreating — REAPER's ReaScript
--- API has no getter/setter for a marker/region's ruler "lane" assignment,
--- but since this never deletes the object, whatever REAPER itself tracks
--- that isn't exposed here (lane included) simply isn't touched and stays
--- exactly as it was. Snapshots via EnumProjectMarkers3 first (same
--- "don't mutate what you're iterating" reasoning as CLB.cut_shift_range).
function CLB.shift_markers_regions(windows, delta, TOL)
  local function in_any_window(pos, pos2)
    for _, w in ipairs(windows) do
      if pos2 then
        if pos >= w.start - TOL and pos2 <= w.stop + TOL then return true end
      elseif pos >= w.start - TOL and pos <= w.stop + TOL then
        return true
      end
    end
    return false
  end

  local snap = {}
  local i = 0
  while true do
    local retval, isrgn, pos, rgnend, name, idnum, color = reaper.EnumProjectMarkers3(0, i)
    if retval == 0 then break end
    snap[#snap + 1] = { isrgn = isrgn, pos = pos, rgnend = rgnend, name = name, id = idnum, color = color }
    i = i + 1
  end

  local moved = 0
  for _, m in ipairs(snap) do
    local hit = m.isrgn and in_any_window(m.pos, m.rgnend) or in_any_window(m.pos, nil)
    if hit then
      local new_pos    = m.pos + delta
      local new_rgnend = m.isrgn and (m.rgnend + delta) or new_pos
      reaper.SetProjectMarker4(0, m.id, m.isrgn, new_pos, new_rgnend, m.name, m.color, 0)
      moved = moved + 1
    end
  end
  return moved
end

--- Collects the ranges to shift: Razor Edit areas (if any exist on any
--- track in the project) take priority — each area already carries its
--- own track + time range, so REAPER's track selection (TCP) is ignored
--- entirely in that case. Otherwise falls back to Time Selection x
--- REAPER-selected track(s) (TCP selection required). Envelope-lane razor
--- areas (their 3rd field is a non-empty envelope GUID, not "") are
--- skipped — this is about media items, not automation points. Returns
--- nil if neither a razor edit nor a (time selection + track selection)
--- is present — caller must refuse to run rather than guess a scope.
function CLB._collect_shift_ranges()
  local ranges = {}
  local n_tracks = reaper.CountTracks(0)
  for i = 0, n_tracks - 1 do
    local track = reaper.GetTrack(0, i)
    local ok, raz = reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if ok and raz and raz ~= "" then
      for a, b, env_guid in raz:gmatch('(%S+)%s+(%S+)%s+"(.-)"') do
        if env_guid == "" then
          local s, e = tonumber(a), tonumber(b)
          if s and e and e > s then
            ranges[#ranges + 1] = { track = track, start = s, stop = e }
          end
        end
      end
    end
  end
  if #ranges > 0 then return ranges, "razor edit" end

  local ts_start, ts_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if not (ts_end > ts_start) then return nil, nil end
  local n_sel = reaper.CountSelectedTracks(0)
  if n_sel == 0 then return nil, nil end
  for i = 0, n_sel - 1 do
    ranges[#ranges + 1] = { track = reaper.GetSelectedTrack(0, i), start = ts_start, stop = ts_end }
  end
  return ranges, "time selection"
end

--- Physically shifts whatever's inside the current range selection —
--- Razor Edit areas if any exist (their own track + time range), else
--- Time Selection x REAPER-selected track(s) — by `hours` (may be
--- negative): items (split at the range edges, locked items included —
--- see CLB.cut_shift_range) AND project markers/regions whose own
--- position falls inside that same time span (see
--- CLB.shift_markers_regions). Requires an explicit range; refuses to run
--- on "select some tracks and click" alone (see CLB._collect_shift_ranges).
---
--- Used to move the "old" real session out of the way before Compare-
--- session matching, so the pristine cut is preserved as a source pool
--- while "new" is rebuilt in the vacated real-timeline space (see
--- CLB.offset_old_enabled/offset_old_hours in the "Modes..." popup) — or,
--- outside Compare, to stage DME Recut's V1 content before a recut.
--- `side` ("old" or "new") says which side of the loaded Compare result
--- (if any) this shift corresponds to: once items are actually moved,
--- that side's dedup event positions (cr.old_dedup/new_dedup — read live
--- by the Recut Group Details table, the graphical Compare timeline, and
--- every click-to-jump) are updated by the same delta FOR WHICHEVER
--- entries fall inside the shifted time span (not unconditionally every
--- entry, unlike the old whole-track version of this function — this is
--- now a scoped shift). The matching-only "virtual" offset for that side
--- (Offset Old/New's checkbox in "Modes...") is NOT auto-disabled anymore
--- (the old whole-track version did, since back then the shift always
--- covered every entry) — a scoped shift may only bake in some of them,
--- so leaving that decision to the user is safer than guessing.
function CMP.shift_range(hours, side)
  local delta = (hours or 0) * 3600
  if delta == 0 then
    reaper.ShowMessageBox("Offset is 0 hours — nothing to do.", SCRIPT_NAME, 0)
    return
  end

  local ranges, source = CLB._collect_shift_ranges()
  if not ranges then
    reaper.ShowMessageBox(
      "No range to shift — make a Razor Edit selection, or a Time\n"
      .. "Selection plus select the track(s) to shift in REAPER first.",
      SCRIPT_NAME, 0)
    return
  end

  local fps = CLB.fps or 24
  local TOL = 0.5 / fps

  local tracks_seen, n_tracks = {}, 0
  for _, r in ipairs(ranges) do
    if not tracks_seen[r.track] then tracks_seen[r.track] = true; n_tracks = n_tracks + 1 end
  end

  local sign  = delta >= 0 and "+" or "-"
  local abs_h = math.abs(hours or 0)
  local msg = string.format(
    "Shift everything inside the current %s by %s%g hour(s)?\n\n" ..
    "%d range(s) across %d track(s), plus any project marker/region\n" ..
    "fully inside that time span.\n\n" ..
    "Items are split at the range edges — only the portion inside moves.\n" ..
    "This moves real project data — undoable via Edit > Undo, but is\n" ..
    "separate from the Compare/Apply report.",
    source, sign, abs_h, #ranges, n_tracks)
  if reaper.ShowMessageBox(msg, "Shift Range", 1) ~= 1 then return end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local moved = 0
  local windows = {}
  for _, r in ipairs(ranges) do
    moved = moved + CLB.cut_shift_range(r.track, r.start, r.stop, delta, TOL)
    windows[#windows + 1] = { start = r.start, stop = r.stop }
  end
  local markers_moved = CLB.shift_markers_regions(windows, delta, TOL)

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(string.format("CLB: Shift range by %s%g hour(s)", sign, abs_h), -1)
  reaper.UpdateArrange()

  -- Bake the shift into the matching Compare-result dedup list (if one is
  -- loaded) — but ONLY for entries whose own Rec TC falls inside one of
  -- the shifted windows, since this is now a scoped shift, not always the
  -- whole track (see this function's own doc comment for why the virtual
  -- offset checkbox is deliberately left alone here, unlike before).
  local baked_msg = ""
  local cr = CLB.compare_result
  if cr and (side == "old" or side == "new") then
    local dedup = (side == "old") and cr.old_dedup or cr.new_dedup
    local baked = 0
    for _, e in ipairs(dedup or {}) do
      for _, w in ipairs(windows) do
        if e.rec_in >= w.start - TOL and e.rec_out <= w.stop + TOL then
          e.rec_in  = e.rec_in  + delta
          e.rec_out = e.rec_out + delta
          baked = baked + 1
          break
        end
      end
    end
    if baked > 0 then
      -- "Show as Table" caches old/new TC as formatted strings at build
      -- time — rebuild so those reflect the shift too.
      if CLB.viewing_compare_groups then
        ROWS = CMP.build_group_rows(cr)
        CLB.cached_rows = nil
      end
      baked_msg = string.format(
        "\n\nAlso updated %d %s Rec TC entry/entries in the loaded Compare result to match.",
        baked, side == "old" and "Old" or "New")
    end
  end

  reaper.ShowMessageBox(
    string.format("Shifted %d item piece(s) and %d marker/region(s) by %s%g hour(s), from a %s.%s",
      moved, markers_moved, sign, abs_h, source, baked_msg),
    "Shift Range", 0)
end

-- Reaper does not enforce unique track names (confirmed by real use — two
-- tracks both named e.g. "XML - A3" is entirely possible), so every track
-- reference in previews/reports includes its 1-based track number. Shared
-- by CMP.apply_to_reaper and CMP.analyze_and_match_session.
function CMP.track_label(track)
  local _, name = reaper.GetTrackName(track)
  local num = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  return string.format("#%d %s", num, name)
end

function CMP.item_take_name(item)
  local take = reaper.GetActiveTake(item)
  return take and select(2, reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)) or "(no take)"
end

--- Matched Item: does any item on `sel_tracks` carry P_EXT:CLB_REEL /
--- CLB_SRC_TC_IN/OUT metadata (written by Generate Items /
--- conform_matched_items) identifying it as THIS target's own content,
--- regardless of where it currently sits? Content identity, not position
--- coincidence — so target's src_in/src_out need no offset adjustment even
--- when the session has been shifted (see CMP.shift_range). Single match
--- by design.
function CMP.find_metadata_match(target, sel_tracks, fps, is_drop, tol)
  if not CLB.apply_mode_matched then return nil, nil end
  for _, track in ipairs(sel_tracks) do
    local n_items = reaper.CountTrackMediaItems(track)
    for i = 0, n_items - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      local take = reaper.GetActiveTake(item)
      if take then
        local _, reel = reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_REEL", "", false)
        if reel ~= "" and reel == target.reel then
          local _, src_in_tc  = reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_IN", "", false)
          local _, src_out_tc = reaper.GetSetMediaItemTakeInfo_String(take, "P_EXT:CLB_SRC_TC_OUT", "", false)
          if src_in_tc ~= "" and src_out_tc ~= "" then
            local ok1, src_in_sec  = pcall(EDL.tc_to_seconds, src_in_tc,  fps, is_drop)
            local ok2, src_out_sec = pcall(EDL.tc_to_seconds, src_out_tc, fps, is_drop)
            if ok1 and ok2 and math.abs(src_in_sec - target.src_in) <= tol
               and math.abs(src_out_sec - target.src_out) <= tol then
              return track, item
            end
          end
        end
      end
    end
  end
  return nil, nil
end

--- Length Match: EVERY item overlapping the target's REC TC range (the
--- caller offset-adjusts target.rec_in/rec_out first if the session was
--- shifted) whose own length matches the target's — no metadata needed.
--- Sweeps *all* qualifying items, not just the first (see
--- CMP.apply_to_reaper's Deleted-mode testing notes for why this
--- matters). `exclude_item` is Matched Item's own match for this target,
--- if any, so it isn't listed twice.
function CMP.find_all_length_matches(target, sel_tracks, exclude_item, tol)
  local out = {}
  if not CLB.apply_mode_length then return out end
  local target_len = target.rec_out - target.rec_in
  for _, track in ipairs(sel_tracks) do
    local n_items = reaper.CountTrackMediaItems(track)
    for i = 0, n_items - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      if item ~= exclude_item then
        local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = pos + len
        if item_end > target.rec_in and pos < target.rec_out and math.abs(len - target_len) <= tol then
          out[#out + 1] = { track = track, item = item }
        end
      end
    end
  end
  return out
end

-- Fixed color per recut type, applied to matched items' I_CUSTOMCOLOR.
-- "Shift" (a Moved group with is_shift=true — many items sharing one
-- systemic offset) gets its own neutral gray so it reads as "nothing to
-- worry about" at a glance, distinct from individually Moved items. Kept as
-- CMP fields (not top-level locals) — this script is already at Lua's
-- 200-local-per-chunk ceiling.
CMP.TYPE_COLOR = {
  Deleted  = reaper.ColorToNative(200,  60,  60) | 0x1000000,
  Trimmed  = reaper.ColorToNative( 70, 130, 220) | 0x1000000,
  Extended = reaper.ColorToNative( 80, 170,  90) | 0x1000000,
  Moved    = reaper.ColorToNative(220, 150,  60) | 0x1000000,
  Shift    = reaper.ColorToNative(140, 140, 140) | 0x1000000,
}
CMP.MARKER_PREFIX = "[CLB] "

--- Color-code + take-marker a real item to show what a planned recut
--- action will do to it — shared by CMP.analyze_and_match_session (auto
--- matches) and CMP.assign_group_detail_match (manual corrections via the
--- Recut Group Details table), so both leave identical visual feedback on
--- the arrange view regardless of which one produced the match. Only ever
--- touches a take marker already carrying CMP.MARKER_PREFIX (reused on
--- repeat calls, not piled up), so any of the user's own take markers are
--- left alone.
function CMP.mark_matched_item(item, style_key, label_text)
  local color = CMP.TYPE_COLOR[style_key] or CMP.TYPE_COLOR.Moved
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
  local take = reaper.GetActiveTake(item)
  if not take then return end
  local label = CMP.MARKER_PREFIX .. label_text
  local n = reaper.GetNumTakeMarkers(take)
  local idx = -1
  for i = 0, n - 1 do
    local _, name = reaper.GetTakeMarker(take, i)
    if name and name:sub(1, #CMP.MARKER_PREFIX) == CMP.MARKER_PREFIX then
      idx = i
      break
    end
  end
  reaper.SetTakeMarker(take, idx, label, 0, color)
end

--- Undo CMP.mark_matched_item's visual feedback on an item — used by
--- "Clear Match". Resets the item's custom color to "use track/default"
--- and removes CLB's own take marker (again, only one carrying
--- CMP.MARKER_PREFIX; the user's own markers are untouched).
function CMP.unmark_matched_item(item)
  if not item then return end
  reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)
  local take = reaper.GetActiveTake(item)
  if not take then return end
  local n = reaper.GetNumTakeMarkers(take)
  for i = n - 1, 0, -1 do
    local _, name = reaper.GetTakeMarker(take, i)
    if name and name:sub(1, #CMP.MARKER_PREFIX) == CMP.MARKER_PREFIX then
      reaper.DeleteTakeMarker(take, i)
    end
  end
end

--- Non-destructive preview step, meant to run before Apply: scans the
--- Reaper-selected track(s) and matches every recut candidate (every group
--- except Added, which has no old item) to a real item there, using the
--- same Matched Item (metadata identity) / Length Match strategies as
--- Apply — Range Clear intentionally excluded, since it doesn't identify a
--- specific item the way this preview needs. Matched items are colored by
--- recut type and get a take marker naming the group's own label (e.g.
--- "Trimmed (head +0f/tail+78f)", "Shift +86392f (635 clips)"), so a glance
--- at the arrange view shows what Apply would do to them. Offset-aware: if
--- Offset Old is enabled (see CMP.shift_range), old positions are
--- searched at their shifted location, not their original one.
---
--- Also persists a single definitive match on the candidate itself
--- (c.match = {item, kind}) whenever it's unambiguous — Matched Item's
--- own pick, or exactly one Length Match hit — so the Recut Group
--- Details table's "Matched Item" column can show/correct it afterward
--- (see CMP.assign_group_detail_match / CMP.clear_group_detail_match).
--- Multiple Length Match hits with no Matched Item pick is genuinely
--- ambiguous (which one is really it?), so c.match is left nil for those
--- — needs a manual pick. Doesn't affect Deleted, which intentionally
--- clears every hit regardless and has no manual-correction UI.
function CMP.analyze_and_match_session()
  local cr = CLB.compare_result
  if not cr then
    reaper.ShowMessageBox("Run Compare first.", SCRIPT_NAME, 0)
    return
  end

  local n_sel_tracks = reaper.CountSelectedTracks(0)
  if n_sel_tracks == 0 then
    reaper.ShowMessageBox(
      "Select at least one track in Reaper first.\n\n"
      .. "Analyze & Match only searches the track(s) you have selected there.",
      SCRIPT_NAME, 0)
    return
  end
  local sel_tracks = {}
  for i = 0, n_sel_tracks - 1 do
    sel_tracks[#sel_tracks + 1] = reaper.GetSelectedTrack(0, i)
  end

  if not (CLB.apply_mode_matched or CLB.apply_mode_length) then
    reaper.ShowMessageBox(
      "Matched Item and Length Match are both disabled in 'Modes...' — enable at least one to analyze.",
      SCRIPT_NAME, 0)
    return
  end

  local fps, is_drop = cr.fps or CLB.fps, cr.is_drop or false
  local TOL = 1.5 / fps
  local offset_sec = (CLB.offset_old_enabled and (CLB.offset_old_hours or 0) * 3600) or 0

  local matched_a, matched_c, unmatched = 0, 0, 0
  local touched = {}  -- item → true, so an item hit by more than one target this run isn't recolored twice

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  for _, g in ipairs(cr.groups) do
    if g.type ~= "Added" then
      local style_key = (g.type == "Moved" and g.is_shift) and "Shift" or g.type
      local label_text = g.label or g.type

      for _, c in ipairs(g.items) do
        if c.old then
          local target = {
            reel = c.old.reel, src_in = c.old.src_in, src_out = c.old.src_out,
            rec_in = c.old.rec_in + offset_sec, rec_out = c.old.rec_out + offset_sec,
          }

          local _, a_item = CMP.find_metadata_match(target, sel_tracks, fps, is_drop, TOL)
          local hits = {}
          if a_item then hits[#hits + 1] = a_item end
          for _, hit in ipairs(CMP.find_all_length_matches(target, sel_tracks, a_item, TOL)) do
            hits[#hits + 1] = hit.item
          end

          if #hits == 0 then
            unmatched = unmatched + 1
            c.match = nil
          else
            if a_item then matched_a = matched_a + 1 else matched_c = matched_c + 1 end
            for _, item in ipairs(hits) do
              if not touched[item] then
                touched[item] = true
                CMP.mark_matched_item(item, style_key, label_text)
              end
            end
            if a_item then
              c.match = { item = a_item, kind = "auto_matched" }
            elseif #hits == 1 then
              c.match = { item = hits[1], kind = "auto_length" }
            else
              c.match = nil  -- ambiguous (multiple Length Match hits, no Matched Item pick) — needs a manual pick
            end
          end
        end
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.Undo_EndBlock("CLB: Analyze & Match Session", -1)

  local total = matched_a + matched_c + unmatched
  reaper.ShowMessageBox(string.format(
    "Analyzed %d recut event(s) against %d selected track(s):\n\n" ..
    "  Matched (Matched Item):  %d\n" ..
    "  Matched (Length Match):  %d\n" ..
    "  Unmatched:               %d\n\n" ..
    "Matched items are now colored by recut type, with a take marker\n" ..
    "describing what Apply would do to them. Nothing was moved, trimmed,\n" ..
    "or deleted — this is a preview only.",
    total, #sel_tracks, matched_a, matched_c, unmatched),
    "Analyze & Match Session", 0)
end

--- Manual match correction (pipeline step 4): assign whichever ONE item is
--- currently selected in Reaper as `c`'s match, overriding whatever
--- CMP.analyze_and_match_session did or didn't find. Used by the Recut
--- Group Details table's "Assign" button — for the types that need a
--- single definitive item (Trimmed/Extended/Moved/unmatched candidates of
--- those types). Deleted is intentionally not offered this — see
--- CMP.analyze_and_match_session's doc comment.
---
--- `c.__group` (stamped by hsuanice_CLB Compare Engine.lua's M.group) is
--- how this finds the type/label to color/mark the newly-assigned item
--- with, without the caller having to thread the parent group through.
function CMP.assign_group_detail_match(c)
  if not c or not c.old then
    reaper.ShowMessageBox("This row has no old item to match.", "Assign Match", 0)
    return
  end
  local g = c.__group
  if not g then
    reaper.ShowMessageBox("Internal error: this row has no parent group.", "Assign Match", 0)
    return
  end
  if g.type == "Deleted" then
    reaper.ShowMessageBox(
      "Deleted groups clear every overlapping item automatically —\n"
      .. "manual assignment doesn't apply here.",
      "Assign Match", 0)
    return
  end

  if reaper.CountSelectedMediaItems(0) ~= 1 then
    reaper.ShowMessageBox(
      "Select exactly one item in Reaper first — the item this\n"
      .. "row should be matched to.",
      "Assign Match", 0)
    return
  end
  local item = reaper.GetSelectedMediaItem(0, 0)

  -- If this candidate already had a different matched item, clean up its
  -- old marker/color first so it doesn't keep looking "matched" too.
  if c.match and c.match.item and c.match.item ~= item then
    CMP.unmark_matched_item(c.match.item)
  end

  local style_key = (g.type == "Moved" and g.is_shift) and "Shift" or g.type
  local label_text = g.label or g.type

  reaper.Undo_BeginBlock()
  CMP.mark_matched_item(item, style_key, label_text)
  reaper.Undo_EndBlock("CLB: Assign match (Recut Group Details)", -1)

  c.match = { item = item, kind = "manual" }
end

--- Clear `c`'s current match (manual or automatic) — used by the Recut
--- Group Details table's "Clear" button. Also removes CMP.mark_matched_
--- item's coloring/take-marker from the item itself, so nothing keeps
--- looking matched on the arrange view once cleared here.
function CMP.clear_group_detail_match(c)
  if not c or not c.match then return end
  reaper.Undo_BeginBlock()
  CMP.unmark_matched_item(c.match.item)
  reaper.Undo_EndBlock("CLB: Clear match (Recut Group Details)", -1)
  c.match = nil
end

function CMP.apply_to_reaper()
  -- Pre-flight: refuse to run while Reaper's Ripple Editing is on. A
  -- ripple-mode delete/move would let Reaper itself shift *other* items to
  -- compensate, corrupting the absolute-position math this whole feature
  -- relies on (Compare/Apply intentionally never assumes ripple — see
  -- hsuanice_CLB Compare Engine.lua's M.compare doc comment).
  local ripple_track = reaper.GetToggleCommandStateEx(0, 41990) == 1
  local ripple_all   = reaper.GetToggleCommandStateEx(0, 41991) == 1
  if ripple_track or ripple_all then
    reaper.ShowMessageBox(
      "Reaper's Ripple Editing is currently ON (" ..
      (ripple_all and "all tracks" or "per-track") .. ").\n\n" ..
      "Turn it off first (Options > Ripple Editing > Off). Apply deletes/" ..
      "moves items at absolute positions — ripple mode would let Reaper " ..
      "shift other items to compensate, corrupting the result.",
      SCRIPT_NAME, 0)
    return
  end

  local sel_rows = get_selected_rows()
  if #sel_rows == 0 then
    reaper.ShowMessageBox("Select one or more recut-group rows first.", SCRIPT_NAME, 0)
    return
  end

  local n_sel_tracks = reaper.CountSelectedTracks(0)
  if n_sel_tracks == 0 then
    reaper.ShowMessageBox(
      "Select at least one track in Reaper first.\n\n"
      .. "Apply only searches/modifies the track(s) you have selected there.",
      SCRIPT_NAME, 0)
    return
  end
  local sel_tracks = {}
  for i = 0, n_sel_tracks - 1 do
    sel_tracks[#sel_tracks + 1] = reaper.GetSelectedTrack(0, i)
  end

  local deleted_groups, skipped_types = {}, {}
  for _, row in ipairs(sel_rows) do
    local g = row.__compare_group
    if g then
      if g.type == "Deleted" then
        deleted_groups[#deleted_groups + 1] = g
      else
        skipped_types[g.type] = (skipped_types[g.type] or 0) + 1
      end
    end
  end

  if #deleted_groups == 0 then
    reaper.ShowMessageBox(
      "No 'Deleted' groups among the selected rows.\n\n"
      .. "Only Deleted is supported so far — Trimmed / Extended / Moved / "
      .. "Added are coming in a later update.",
      SCRIPT_NAME, 0)
    return
  end

  local targets = {}  -- { rec_in, rec_out, src_in, src_out (seconds), reel, label }
  for _, g in ipairs(deleted_groups) do
    for _, c in ipairs(g.items) do
      if c.old then
        targets[#targets + 1] = {
          rec_in = c.old.rec_in, rec_out = c.old.rec_out,
          src_in = c.old.src_in, src_out = c.old.src_out,
          reel = c.old.reel or "",
          label = (c.old.clip_name ~= "" and c.old.clip_name) or c.old.reel or "",
        }
      end
    end
  end
  if #targets == 0 then return end
  table.sort(targets, function(a, b) return a.rec_in < b.rec_in end)

  local skip_msg = ""
  do
    local parts = {}
    for t, n in pairs(skipped_types) do parts[#parts + 1] = string.format("%s x%d", t, n) end
    if #parts > 0 then
      skip_msg = "\n\nSkipped (not yet supported): " .. table.concat(parts, ", ")
    end
  end

  local fps     = (CLB.compare_result and CLB.compare_result.fps) or CLB.fps
  local is_drop = (CLB.compare_result and CLB.compare_result.is_drop) or false
  local TOL     = 1.5 / fps  -- ~1.5 frame tolerance

  if not (CLB.apply_mode_matched or CLB.apply_mode_length or CLB.apply_mode_range) then
    reaper.ShowMessageBox("All resolution strategies (Matched Item / Length Match / Range Clear) are disabled — enable at least one in 'Modes...'.", SCRIPT_NAME, 0)
    return
  end

  -- Thin delegations to the shared CMP-level matchers (defined above, right
  -- before this function) — kept as local wrappers so this function's call
  -- sites (track_label(), find_metadata_match(t), find_all_length_matches(t,
  -- a_item), ...) don't need to change.
  local function track_label(track) return CMP.track_label(track) end
  local function item_take_name(item) return CMP.item_take_name(item) end
  local function find_metadata_match(target)
    return CMP.find_metadata_match(target, sel_tracks, fps, is_drop, TOL)
  end
  local function find_all_length_matches(target, exclude_item)
    return CMP.find_all_length_matches(target, sel_tracks, exclude_item, TOL)
  end

  -- Dry-run scan: for each target, Matched Item (single precise match) and
  -- Length Match (sweep of every length-matching item) both contribute
  -- independently when enabled; Range Clear only runs as a fallback when
  -- neither found anything for that target. Preview exactly what was
  -- found before touching anything, so a coincidence or surprise can be
  -- caught here instead of discovered afterward via Undo.
  local plan, locked_list = {}, {}
  for _, t in ipairs(targets) do
    local resolved = false
    local a_item = nil

    local mtrack, mitem = find_metadata_match(t)
    if mtrack then
      resolved = true
      a_item = mitem
      local locked = (reaper.GetMediaItemInfo_Value(mitem, "C_LOCK") & 1) == 1
      local entry = { mode = "matched", track = mtrack, item = mitem, track_name = track_label(mtrack),
                       take_name = item_take_name(mitem), target = t }
      if locked then locked_list[#locked_list + 1] = entry else plan[#plan + 1] = entry end
    end

    for _, hit in ipairs(find_all_length_matches(t, a_item)) do
      resolved = true
      local locked = (reaper.GetMediaItemInfo_Value(hit.item, "C_LOCK") & 1) == 1
      local entry = { mode = "length", track = hit.track, item = hit.item, track_name = track_label(hit.track),
                       take_name = item_take_name(hit.item), target = t }
      if locked then locked_list[#locked_list + 1] = entry else plan[#plan + 1] = entry end
    end

    if not resolved and CLB.apply_mode_range then
      for _, track in ipairs(sel_tracks) do
        local n_items = reaper.CountTrackMediaItems(track)
        for i = 0, n_items - 1 do
          local item = reaper.GetTrackMediaItem(track, i)
          local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
          local len  = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
          local item_end = pos + len
          if item_end > t.rec_in and pos < t.rec_out then
            resolved = true
            local locked = (reaper.GetMediaItemInfo_Value(item, "C_LOCK") & 1) == 1
            local full = pos >= t.rec_in - TOL and item_end <= t.rec_out + TOL
            local entry = { mode = "range", track = track, item = item, pos = pos, item_end = item_end,
                             track_name = track_label(track), take_name = item_take_name(item),
                             target = t, full = full }
            if locked then locked_list[#locked_list + 1] = entry else plan[#plan + 1] = entry end
          end
        end
      end
    end

    if not resolved then
      plan[#plan + 1] = { mode = "none", target = t }
    end
  end

  -- A per-item listing here doesn't scale once there are many recut
  -- events — keep the confirm dialog to a compact summary (range, track
  -- count, item counts per strategy) and leave the full per-item detail
  -- to the HTML report generated after this runs (see CMP.write_apply_report).
  local count_matched, count_length, count_range_full, count_range_partial, count_none = 0, 0, 0, 0, 0
  for _, m in ipairs(plan) do
    if m.mode == "matched" then count_matched = count_matched + 1
    elseif m.mode == "length" then count_length = count_length + 1
    elseif m.mode == "range" then
      if m.full then count_range_full = count_range_full + 1 else count_range_partial = count_range_partial + 1 end
    else count_none = count_none + 1 end
  end

  local range_min, range_max = targets[1].rec_in, targets[1].rec_out
  for _, t in ipairs(targets) do
    if t.rec_in  < range_min then range_min = t.rec_in  end
    if t.rec_out > range_max then range_max = t.rec_out end
  end

  local summary_parts = {}
  if count_matched > 0 then summary_parts[#summary_parts + 1] = count_matched .. " via Matched Item" end
  if count_length > 0 then summary_parts[#summary_parts + 1] = count_length .. " via Length Match" end
  if count_range_full + count_range_partial > 0 then
    summary_parts[#summary_parts + 1] = string.format("%d via Range Clear (%d full, %d partial)",
      count_range_full + count_range_partial, count_range_full, count_range_partial)
  end
  if count_none > 0 then summary_parts[#summary_parts + 1] = count_none .. " not found" end
  if #locked_list > 0 then summary_parts[#summary_parts + 1] = #locked_list .. " locked (skipped)" end

  local confirm = reaper.ShowMessageBox(
    string.format(
      "%d deleted event(s) spanning %s – %s, across %d selected track(s).\n\n" ..
      "%s%s\n\n" ..
      "A red marker is left at each removed position; a detailed HTML " ..
      "report opens after this runs. This will be added to the Undo " ..
      "history. Continue?",
      #targets, EDL.seconds_to_tc(range_min, fps, is_drop), EDL.seconds_to_tc(range_max, fps, is_drop),
      #sel_tracks, table.concat(summary_parts, ", "), skip_msg),
    SCRIPT_NAME, 4)  -- Yes/No
  if confirm ~= 6 then return end

  local RED = reaper.ColorToNative(200, 60, 60) | 0x1000000

  --- Remove the portion of [item: pos..item_end] that overlaps
  --- [range_start..range_end], splitting at the range edges as needed so
  --- content outside the range is left untouched (the Range Clear
  --- strategy's own logic).
  local function clear_item_range(track, item, pos, item_end, range_start, range_end)
    if pos >= range_start - TOL and item_end <= range_end + TOL then
      reaper.DeleteTrackMediaItem(track, item)
    elseif pos < range_start and item_end > range_end then
      reaper.SplitMediaItem(item, range_end)
      local middle = reaper.SplitMediaItem(item, range_start)
      if middle then reaper.DeleteTrackMediaItem(track, middle) end
    elseif pos < range_start then
      local right = reaper.SplitMediaItem(item, range_start)
      if right then reaper.DeleteTrackMediaItem(track, right) end
    else
      -- pos within range, extends past range_end: split there (keeps the
      -- right remainder), then delete the now-truncated original piece.
      reaper.SplitMediaItem(item, range_end)
      reaper.DeleteTrackMediaItem(track, item)
    end
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local matched_count, length_count, range_count = 0, 0, 0
  for _, m in ipairs(plan) do
    if m.mode == "matched" or m.mode == "length" then
      reaper.DeleteTrackMediaItem(m.track, m.item)
      if m.mode == "matched" then matched_count = matched_count + 1 else length_count = length_count + 1 end
    elseif m.mode == "range" then
      clear_item_range(m.track, m.item, m.pos, m.item_end, m.target.rec_in, m.target.rec_out)
      range_count = range_count + 1
    end
  end
  for _, t in ipairs(targets) do
    reaper.AddProjectMarker2(0, false, t.rec_in, 0, "Deleted: " .. t.label, -1, RED)
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("CLB Compare: Apply Deleted recut group(s)", -1)
  reaper.UpdateArrange()

  local summary_line = string.format(
    "Apply: %d Deleted group(s) across %d selected track(s) — %d Matched Item, %d Length Match, %d Range Clear",
    #deleted_groups, #sel_tracks, matched_count, length_count, range_count)
  console_msg(summary_line)
  if #locked_list > 0 then
    console_msg(string.format("  Note: %d item(s) were locked and left untouched.", #locked_list))
  end
  local none_count = 0
  for _, m in ipairs(plan) do if m.mode == "none" then none_count = none_count + 1 end end
  if none_count > 0 then
    console_msg(string.format("  Note: %d target(s) had nothing on the selected track(s) to remove.", none_count))
  end

  -- Build the HTML report from the exact same plan/locked_list used to
  -- execute — track/item/action/strategy for every target, not just a
  -- console summary, so what happened is reviewable/archivable afterward.
  local mode_names = { matched = "Matched Item", length = "Length Match", range = "Range Clear" }
  local report_rows = {}
  for _, m in ipairs(plan) do
    local row = {
      track_name = m.track_name, take_name = m.take_name,
      old_in_tc = EDL.seconds_to_tc(m.target.rec_in, fps, is_drop),
      old_out_tc = EDL.seconds_to_tc(m.target.rec_out, fps, is_drop),
      target_label = m.target.label,
    }
    if m.mode == "matched" or m.mode == "length" then
      row.status, row.action, row.mode = "done", "Deleted", mode_names[m.mode]
    elseif m.mode == "range" then
      row.status = m.full and "done" or "partial"
      row.action = m.full and "Deleted (full overlap)" or "Trimmed (partial overlap)"
      row.mode = mode_names.range
    else
      row.status, row.action, row.mode, row.track_name, row.take_name = "none", "Nothing found", "—", "—", "—"
    end
    report_rows[#report_rows + 1] = row
  end
  for _, m in ipairs(locked_list) do
    report_rows[#report_rows + 1] = {
      track_name = m.track_name, take_name = m.take_name, status = "skipped",
      action = "Skipped (item locked)", mode = mode_names[m.mode] or "—",
      old_in_tc = EDL.seconds_to_tc(m.target.rec_in, fps, is_drop),
      old_out_tc = EDL.seconds_to_tc(m.target.rec_out, fps, is_drop),
      target_label = m.target.label,
    }
  end

  CMP.write_apply_report("CLB Apply — Deleted", summary_line, report_rows)
end

--- Rebuild the inline Group Details panel's content from whichever recut-
--- group row(s) are currently selected. Called every frame while the panel
--- is visible (see draw_main_content) so it behaves like a live "what does
--- this match?" inspector: click an event above, its member items show
--- below immediately — mirroring how the Audio List already follows
--- matched files elsewhere in CLB. No selection = empty panel, not an
--- error (this runs continuously, not on a one-shot button click).
function CMP.refresh_group_details()
  local sel_rows = get_selected_rows()
  local groups_seen, labels, items = {}, {}, {}
  for _, row in ipairs(sel_rows) do
    local g = row.__compare_group
    if g and not groups_seen[g] then
      groups_seen[g] = true
      labels[#labels + 1] = string.format("[%s] %s — %d item(s)", g.type, g.label, #g.items)
      for _, c in ipairs(g.items) do items[#items + 1] = c end
    end
  end
  CLB.cmp_group_details = { labels = labels, items = items }
end

-- Recut Group Details table columns — independently toggleable via the
-- "Columns" button below, separate from the main event-list column set.
CMP.GD_COL = {
  REEL = 1, TRACKS = 2,
  OLD_SRC_IN = 3, OLD_SRC_OUT = 4, NEW_SRC_IN = 5, NEW_SRC_OUT = 6,
  OLD_REC_IN = 7, OLD_REC_OUT = 8, NEW_REC_IN = 9, NEW_REC_OUT = 10,
  CLIP_NAME = 11, MATCH = 12,
}
CMP.GD_COL_COUNT = 12
CMP.GD_HEADER_LABELS = {
  [CMP.GD_COL.REEL] = "Reel", [CMP.GD_COL.TRACKS] = "Tracks",
  [CMP.GD_COL.OLD_SRC_IN] = "Old Src In", [CMP.GD_COL.OLD_SRC_OUT] = "Old Src Out",
  [CMP.GD_COL.NEW_SRC_IN] = "New Src In", [CMP.GD_COL.NEW_SRC_OUT] = "New Src Out",
  [CMP.GD_COL.OLD_REC_IN] = "Old Rec In", [CMP.GD_COL.OLD_REC_OUT] = "Old Rec Out",
  [CMP.GD_COL.NEW_REC_IN] = "New Rec In", [CMP.GD_COL.NEW_REC_OUT] = "New Rec Out",
  [CMP.GD_COL.CLIP_NAME] = "Clip Name", [CMP.GD_COL.MATCH] = "Matched Item",
}
-- Default order: Src TC (old/new) left of Rec TC (old/new), per user
-- request; Matched Item last (click a row there to select it, then use the
-- Assign/Clear buttons below the table — see CMP.draw_group_details_table).
CMP.GD_COL_ORDER = {
  CMP.GD_COL.REEL, CMP.GD_COL.TRACKS,
  CMP.GD_COL.OLD_SRC_IN, CMP.GD_COL.OLD_SRC_OUT, CMP.GD_COL.NEW_SRC_IN, CMP.GD_COL.NEW_SRC_OUT,
  CMP.GD_COL.OLD_REC_IN, CMP.GD_COL.OLD_REC_OUT, CMP.GD_COL.NEW_REC_IN, CMP.GD_COL.NEW_REC_OUT,
  CMP.GD_COL.CLIP_NAME, CMP.GD_COL.MATCH,
}
CMP.GD_COL_IS_TC = {
  [CMP.GD_COL.OLD_SRC_IN] = true, [CMP.GD_COL.OLD_SRC_OUT] = true,
  [CMP.GD_COL.NEW_SRC_IN] = true, [CMP.GD_COL.NEW_SRC_OUT] = true,
  [CMP.GD_COL.OLD_REC_IN] = true, [CMP.GD_COL.OLD_REC_OUT] = true,
  [CMP.GD_COL.NEW_REC_IN] = true, [CMP.GD_COL.NEW_REC_OUT] = true,
}
CMP.GD_COL_STRETCH_WEIGHT = {
  [CMP.GD_COL.REEL] = 1.0, [CMP.GD_COL.TRACKS] = 0.6, [CMP.GD_COL.CLIP_NAME] = 2.0,
  [CMP.GD_COL.MATCH] = 1.6,
}
-- Default visibility: after Compare, Src TC has already become a relative
-- trim/extend number (visible in the main table's Notes column), so it's
-- hidden here by default — only Rec TC matters for most review. Persisted
-- via save_prefs/load_prefs; any column can be toggled back on via "Columns".
CMP.GD_COL_VISIBILITY = {}
for i = 1, CMP.GD_COL_COUNT do CMP.GD_COL_VISIBILITY[i] = true end
CMP.GD_COL_VISIBILITY[CMP.GD_COL.OLD_SRC_IN]  = false
CMP.GD_COL_VISIBILITY[CMP.GD_COL.OLD_SRC_OUT] = false
CMP.GD_COL_VISIBILITY[CMP.GD_COL.NEW_SRC_IN]  = false
CMP.GD_COL_VISIBILITY[CMP.GD_COL.NEW_SRC_OUT] = false

-- Per-TC-column (item, row_id_suffix, value) accessor, shared by the table
-- body loop below — keeps that loop column-order-agnostic.
CMP.GD_TC_GETTERS = {
  [CMP.GD_COL.OLD_SRC_IN]  = { id = "osi", get = function(c) return c.old and c.old.src_in  end },
  [CMP.GD_COL.OLD_SRC_OUT] = { id = "oso", get = function(c) return c.old and c.old.src_out end },
  [CMP.GD_COL.NEW_SRC_IN]  = { id = "nsi", get = function(c) return c.new and c.new.src_in  end },
  [CMP.GD_COL.NEW_SRC_OUT] = { id = "nso", get = function(c) return c.new and c.new.src_out end },
  [CMP.GD_COL.OLD_REC_IN]  = { id = "oi",  get = function(c) return c.old and c.old.rec_in  end },
  [CMP.GD_COL.OLD_REC_OUT] = { id = "oo",  get = function(c) return c.old and c.old.rec_out end },
  [CMP.GD_COL.NEW_REC_IN]  = { id = "ni",  get = function(c) return c.new and c.new.rec_in  end },
  [CMP.GD_COL.NEW_REC_OUT] = { id = "no",  get = function(c) return c.new and c.new.rec_out end },
}

--- Show/hide checkboxes for the Group Details table's columns (see CMP.GD_COL
--- above). Mirrors the main event-list "Columns" popup (EDL Columns).
function CMP.draw_group_details_columns_popup()
  if reaper.ImGui_BeginPopup(ctx, "Group Details Columns##cmp_gd_col_popup") then
    reaper.ImGui_Text(ctx, "Show/Hide Columns:")
    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_SmallButton(ctx, "All##cmp_gd_col_all") then
      for i = 1, CMP.GD_COL_COUNT do CMP.GD_COL_VISIBILITY[i] = true end
      save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "None##cmp_gd_col_none") then
      for i = 1, CMP.GD_COL_COUNT do CMP.GD_COL_VISIBILITY[i] = false end
      save_prefs()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "Reset##cmp_gd_col_reset") then
      for i = 1, CMP.GD_COL_COUNT do CMP.GD_COL_VISIBILITY[i] = true end
      CMP.GD_COL_VISIBILITY[CMP.GD_COL.OLD_SRC_IN]  = false
      CMP.GD_COL_VISIBILITY[CMP.GD_COL.OLD_SRC_OUT] = false
      CMP.GD_COL_VISIBILITY[CMP.GD_COL.NEW_SRC_IN]  = false
      CMP.GD_COL_VISIBILITY[CMP.GD_COL.NEW_SRC_OUT] = false
      save_prefs()
    end
    reaper.ImGui_Separator(ctx)

    for _, col in ipairs(CMP.GD_COL_ORDER) do
      local label = CMP.GD_HEADER_LABELS[col] or ("Col " .. col)
      local chg, new_val = reaper.ImGui_Checkbox(ctx, label .. "##cmp_gd_col_vis_" .. col, CMP.GD_COL_VISIBILITY[col])
      if chg then
        CMP.GD_COL_VISIBILITY[col] = new_val
        save_prefs()
      end
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

--- Header row for the inline Group Details panel — occupies the same
--- split-view slot the Audio List normally uses (see draw_main_content);
--- Compare mode has no use for the audio panel there, so this reuses the
--- space rather than popping up a separate window.
function CMP.draw_group_details_header()
  local d = CLB.cmp_group_details
  if d and #d.items > 0 then
    reaper.ImGui_Text(ctx, string.format("Recut Group Details (%d item(s))", #d.items))
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextDisabled(ctx, table.concat(d.labels, "  |  "))
  else
    reaper.ImGui_TextDisabled(ctx, "Recut Group Details — select a row above to see what it matches.")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Columns##cmp_gd_cols") then
    reaper.ImGui_OpenPopup(ctx, "Group Details Columns##cmp_gd_col_popup")
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Show/hide this table's columns")
  end
  CMP.draw_group_details_columns_popup()
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide##cmp_details_panel") then
    CLB.show_cmp_details = false
  end
end

--- Table body for the inline Group Details panel (see header above).
function CMP.draw_group_details_table(table_height)
  local d = CLB.cmp_group_details
  if not d or #d.items == 0 then
    reaper.ImGui_TextDisabled(ctx, "(nothing selected)")
    return
  end

  -- Drop a stale selection (e.g. the main table's row selection changed,
  -- so this candidate isn't even shown here anymore) rather than letting
  -- Assign/Clear silently act on something no longer visible.
  if CLB.gd_selected_c then
    local still_here = false
    for _, c in ipairs(d.items) do
      if c == CLB.gd_selected_c then still_here = true; break end
    end
    if not still_here then CLB.gd_selected_c = nil end
  end

  local visible_cols = {}
  for _, col in ipairs(CMP.GD_COL_ORDER) do
    if CMP.GD_COL_VISIBILITY[col] then visible_cols[#visible_cols + 1] = col end
  end
  if #visible_cols == 0 then
    reaper.ImGui_TextDisabled(ctx, "No columns visible. Click 'Columns' to show columns.")
    return
  end

  local fps     = (CLB.compare_result and CLB.compare_result.fps) or CLB.fps
  local is_drop = (CLB.compare_result and CLB.compare_result.is_drop) or false
  local function tc(sec) return sec and EDL.seconds_to_tc(sec, fps, is_drop) or "-" end

  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  -- Reserve room below the table for the Assign/Clear toolbar (see the end
  -- of this function) — BeginTable's height param claims that much space
  -- outright, so passing the full table_height left nothing for it: those
  -- widgets were being laid out below the table but past the window's
  -- visible bounds, effectively invisible. line_h covers the "Selected:
  -- ..." text row; button_h the button row; a little spacing between.
  local line_h   = reaper.ImGui_GetTextLineHeightWithSpacing(ctx)
  local button_h = scale(22)
  local toolbar_h = line_h + button_h + scale(8)
  local table_h = math.max(scale(60), table_height - toolbar_h)
  local tflags = reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg()
               | reaper.ImGui_TableFlags_ScrollY() | reaper.ImGui_TableFlags_Resizable()
  if reaper.ImGui_BeginTable(ctx, "##cmp_details_tbl", #visible_cols, tflags, avail_w, table_h) then
    reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
    -- TC columns hold fixed-format "HH:MM:SS:FF" text, so they get a fixed,
    -- non-user-resizable width (edit TC_W below to change it — matches the
    -- main event-list/Audio-list tables' treatment of TC columns, see
    -- TC_COLS/AUDIO_TC_COLS); Reel/Tracks/Clip Name stretch to fill the rest.
    local TC_W = scale(75)
    local TC_FLAGS = reaper.ImGui_TableColumnFlags_WidthFixed() | reaper.ImGui_TableColumnFlags_NoResize()
    for _, col in ipairs(visible_cols) do
      local label = CMP.GD_HEADER_LABELS[col] or ""
      if CMP.GD_COL_IS_TC[col] then
        reaper.ImGui_TableSetupColumn(ctx, label, TC_FLAGS, TC_W)
      else
        reaper.ImGui_TableSetupColumn(ctx, label,
          reaper.ImGui_TableColumnFlags_WidthStretch(), CMP.GD_COL_STRETCH_WEIGHT[col] or 1.0)
      end
    end
    reaper.ImGui_TableHeadersRow(ctx)

    -- All Old/New Rec and Src TC cells are clickable — each jumps Reaper's
    -- edit cursor to that cell's own literal TC value and scrolls it into
    -- view, same as clicking a block in the graphical SRC/DEST timeline
    -- (see CMP.draw_side). Src TC is a real, independent Reaper timeline
    -- position (0 to infinity covers it) distinct from Rec TC — this
    -- supports manual conform, where raw/source dailies are commonly
    -- parked on a track at their own embedded timecode: jump to Src TC to
    -- grab the right source content, then move it to Rec TC (mirrors
    -- Matchbox's old/new jump behavior).
    local function tc_cell(sec, row_id)
      if not sec then
        reaper.ImGui_Text(ctx, "-")
        return
      end
      if reaper.ImGui_Selectable(ctx, tc(sec) .. "##" .. row_id, false) then
        reaper.SetEditCurPos(sec, true, false)
      end
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Click to move edit cursor here")
      end
    end

    -- "Matched Item" cell text: the assigned/auto-found item's take name
    -- plus how it was matched, or "—" if none. A dangling pointer (item
    -- deleted from Reaper since matching ran) shows as "(item deleted)"
    -- rather than erroring.
    local match_kind_label = { auto_matched = "auto: item", auto_length = "auto: length", manual = "manual" }
    local function match_cell_text(c)
      if not c.match or not c.match.item then return "—" end
      if not reaper.ValidatePtr2(0, c.match.item, "MediaItem*") then return "(item deleted)" end
      return string.format("%s (%s)", CMP.item_take_name(c.match.item), match_kind_label[c.match.kind] or "?")
    end

    for idx, c in ipairs(d.items) do
      local rep = c.new or c.old
      reaper.ImGui_TableNextRow(ctx)
      for _, col in ipairs(visible_cols) do
        reaper.ImGui_TableNextColumn(ctx)
        if col == CMP.GD_COL.REEL then
          reaper.ImGui_Text(ctx, rep.reel or "")
        elseif col == CMP.GD_COL.TRACKS then
          reaper.ImGui_Text(ctx, table.concat(rep.tracks or {}, ","))
        elseif col == CMP.GD_COL.CLIP_NAME then
          reaper.ImGui_Text(ctx, rep.clip_name or "")
        elseif col == CMP.GD_COL.MATCH then
          -- Click to select this candidate for the Assign/Clear buttons
          -- below the table (see the rest of this function).
          if reaper.ImGui_Selectable(ctx, match_cell_text(c) .. "##match" .. idx,
                                      CLB.gd_selected_c == c) then
            CLB.gd_selected_c = c
          end
        else
          local g = CMP.GD_TC_GETTERS[col]
          tc_cell(g.get(c), g.id .. idx)
        end
      end
    end
    reaper.ImGui_EndTable(ctx)
  end

  -- Manual match correction (pipeline step 4): click a row's Matched Item
  -- cell above to select it, select the correct item in Reaper, then
  -- Assign. Not offered for Deleted groups (see CMP.assign_group_detail_
  -- match's own doc comment) — the button stays but errors clearly if
  -- clicked on one, rather than silently hiding (the row is still visible
  -- in this table and clicking it to inspect is normal).
  local sel_c = CLB.gd_selected_c
  reaper.ImGui_Spacing(ctx)
  if sel_c then
    local g = sel_c.__group
    local rep = sel_c.new or sel_c.old
    reaper.ImGui_TextDisabled(ctx, string.format("Selected: [%s] %s",
      g and g.type or "?", (rep and rep.clip_name) or ""))
  else
    reaper.ImGui_TextDisabled(ctx, "Click a row's Matched Item cell above to select it.")
  end
  local can_correct = sel_c ~= nil
  if not can_correct then reaper.ImGui_BeginDisabled(ctx) end
  if reaper.ImGui_Button(ctx, "Assign Selected Reaper Item##gd_assign", scale(190), scale(22)) then
    CMP.assign_group_detail_match(sel_c)
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Select exactly one item in Reaper — the item the selected\nrow should be matched to — then click this.")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Clear Match##gd_clear", scale(90), scale(22)) then
    CMP.clear_group_detail_match(sel_c)
  end
  if not can_correct then reaper.ImGui_EndDisabled(ctx) end
end

function CMP.draw_panel()
  local cr = CLB.compare_result

  if not cr then
    reaper.ImGui_Text(ctx, "Compare: load OLD and NEW versions to begin.")
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "Load Old...", scale(100), scale(26)) then
      CMP.load_side("old")
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, CLB.compare_old and
      string.format("%s (%d events)", CLB.compare_old.name, #CLB.compare_old.rows)
      or "(not loaded)")

    if reaper.ImGui_Button(ctx, "Load New...", scale(100), scale(26)) then
      CMP.load_side("new")
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, CLB.compare_new and
      string.format("%s (%d events)", CLB.compare_new.name, #CLB.compare_new.rows)
      or "(not loaded)")

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextDisabled(ctx, "Accepts .edl / .xml / .aaf / .clb. Compare runs automatically once both are loaded.")
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "Load Session...", scale(120), scale(26)) then
      CMP.load_session_dialog()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Resume a previously saved .clbcmp Compare Session —\nloads both sides and re-runs Compare in one step.")
    end
    reaper.ImGui_Spacing(ctx)

    if reaper.ImGui_Button(ctx, "Close", scale(90), scale(24)) then
      -- Restore the Track/Reel/Group filter panels to reflect whatever is
      -- actually in ROWS (CMP.run() repoints them at Compare's own data —
      -- see CMP.rebuild_filters — so they'd otherwise stay stale here).
      _rebuild_track_filters()
      _rebuild_reel_filters()
      _rebuild_group_filters()
      CLB.show_compare_view = false
    end
    return
  end

  if reaper.ImGui_Button(ctx, "<< Show as Table", scale(140), scale(24)) then
    CLB._compare_rows_backup = { rows = ROWS, sources = CLB.edl_sources }
    ROWS = CMP.build_group_rows(cr)
    CLB.edl_sources = {}
    CLB.viewing_compare_groups = true
    CLB.show_compare_view = false
    CLB.show_cmp_details = true  -- auto-open the live Details panel
    sel_clear()
    _rebuild_track_filters()
    _rebuild_reel_filters()
    _rebuild_group_filters()
    CLB.cached_rows = nil
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Show one row per recut group in the main table\n(temporarily replaces your current list — 'Exit' restores it).")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Save Session...", scale(120), scale(24)) then
    CMP.save_session_dialog()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Save the full Compare session (.clbcmp) — both sides' raw\ndata, so 'Load Session' later fully restores this graphical\nview, the live Details panel, and Show as Table. Does not\ntouch your main table's current list.")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Load Session...", scale(120), scale(24)) then
    CMP.load_session_dialog()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Load a different .clbcmp Compare Session, replacing this one.")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Clear Comparison", scale(130), scale(24)) then
    CLB.compare_old    = nil
    CLB.compare_new    = nil
    CLB.compare_result = nil
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetTooltip(ctx, "Discard this comparison and go back to Load Old / New / Session.")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Close", scale(70), scale(24)) then
    -- Same reasoning as the setup-screen Close above: restore the filter
    -- panels to reflect ROWS, not Compare's data.
    _rebuild_track_filters()
    _rebuild_reel_filters()
    _rebuild_group_filters()
    CLB.show_compare_view = false
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, string.format("Compare: %s (old)  vs  %s (new)",
    cr.old_source.name, cr.new_source.name))

  local counts = {}
  for _, c in ipairs(cr.changes) do counts[c.type] = (counts[c.type] or 0) + 1 end
  local total_old, changed_old = #cr.old_dedup, 0
  for _, e in ipairs(cr.old_dedup) do
    if e.change_type then changed_old = changed_old + 1 end
  end
  local matched_pct = total_old > 0 and (100 * (total_old - changed_old) / total_old) or 100

  -- Split "Moved" into Shift (many items sharing the exact same delta — a
  -- whole block displaced together) vs individually-Moved items, so a
  -- systemic offset doesn't read as hundreds of unrelated edits.
  local shift_count, moved_count = 0, 0
  for _, g in ipairs(cr.groups) do
    if g.type == "Moved" then
      if g.is_shift then shift_count = shift_count + #g.items
      else moved_count = moved_count + #g.items end
    end
  end

  reaper.ImGui_Text(ctx, string.format(
    "Deleted %d   Trimmed %d   Extended %d   Shift %d   Moved %d   Added %d   |   Matched %.0f%%",
    counts.Deleted or 0, counts.Trimmed or 0, counts.Extended or 0,
    shift_count, moved_count, counts.Added or 0, matched_pct))

  local function legend_swatch(label, color)
    local dl = reaper.ImGui_GetWindowDrawList(ctx)
    local x, y = reaper.ImGui_GetCursorScreenPos(ctx)
    local sz = scale(12)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y + scale(2), x + sz, y + sz + scale(2), color)
    reaper.ImGui_Dummy(ctx, sz, sz + scale(2))
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, label)
    reaper.ImGui_SameLine(ctx)
  end
  legend_swatch("Deleted", CMP.colors.Deleted)
  legend_swatch("Trimmed", CMP.colors.Trimmed)
  legend_swatch("Extended", CMP.colors.Extended)
  legend_swatch("Shift", CMP.colors.Shift)
  legend_swatch("Moved", CMP.colors.Moved)
  legend_swatch("Added", CMP.colors.Added)
  reaper.ImGui_NewLine(ctx)

  -- Hidden sets from the Track/Reel/Group filter panels (rebuilt from this
  -- compare result by CMP.rebuild_filters — see run()), so toggling them
  -- above the Compare view actually hides what's drawn here.
  local hidden_tracks, hidden_reels, hidden_groups
  for _, tf in ipairs(CLB.track_filters) do
    if not tf.visible then hidden_tracks = hidden_tracks or {}; hidden_tracks[tf.name] = true end
  end
  for _, rf in ipairs(CLB.reel_filters) do
    if not rf.visible then hidden_reels = hidden_reels or {}; hidden_reels[rf.name] = true end
  end
  for _, gf in ipairs(CLB.group_filters) do
    if not gf.visible then hidden_groups = hidden_groups or {}; hidden_groups[gf.name] = true end
  end

  -- Union track order so SRC/DEST lanes line up at the same row.
  local track_set, track_order = {}, {}
  for _, e in ipairs(cr.old_dedup) do
    for _, t in ipairs(e.tracks) do
      if not track_set[t] then track_set[t] = true; track_order[#track_order + 1] = t end
    end
  end
  for _, e in ipairs(cr.new_dedup) do
    for _, t in ipairs(e.tracks) do
      if not track_set[t] then track_set[t] = true; track_order[#track_order + 1] = t end
    end
  end
  -- Drop hidden tracks from the lane list entirely (not just their clips),
  -- so toggling a track off actually collapses its row instead of leaving
  -- an empty lane taking up vertical space.
  if hidden_tracks then
    local visible_order = {}
    for _, t in ipairs(track_order) do
      if not hidden_tracks[t] then visible_order[#visible_order + 1] = t end
    end
    track_order = visible_order
  end
  table.sort(track_order, _natural_sort_cmp)
  local track_index = {}
  for i, t in ipairs(track_order) do track_index[t] = i end

  -- Shared time domain: both panels use raw absolute REC TC (no ripple/
  -- base-offset normalization — see CMP.draw_side's header comment).
  local tmin, tmax
  local function scan(events)
    for _, e in ipairs(events) do
      local a, b = e.rec_in, e.rec_out
      if not tmin or a < tmin then tmin = a end
      if not tmax or b > tmax then tmax = b end
    end
  end
  scan(cr.old_dedup)
  scan(cr.new_dedup)
  if not tmin then tmin = 0 end
  if not tmax or tmax <= tmin then tmax = tmin + 1 end

  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
  local splitter_h = scale(6)
  local half_h  = math.max(scale(40), (avail_h - splitter_h) * CLB.cmp_split_ratio)
  local other_h = math.max(scale(40), avail_h - splitter_h - half_h)

  CMP.draw_side("SRC (old)", cr.old_dedup, track_order, track_index, tmin, tmax, half_h, false, "cmp_old", cr.fps, cr.is_drop, hidden_tracks, hidden_reels, hidden_groups)

  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_InvisibleButton(ctx, "##cmp_splitter", avail_w, splitter_h)
  if reaper.ImGui_IsItemActive(ctx) then
    local _, dy = reaper.ImGui_GetMouseDelta(ctx)
    if dy and dy ~= 0 then
      CLB.cmp_split_ratio = math.max(0.2, math.min(0.8, CLB.cmp_split_ratio + dy / avail_h))
    end
  end
  local dl2 = reaper.ImGui_GetWindowDrawList(ctx)
  local mnx, mny = reaper.ImGui_GetItemRectMin(ctx)
  local mxx, mxy = reaper.ImGui_GetItemRectMax(ctx)
  reaper.ImGui_DrawList_AddRectFilled(dl2, mnx, mny + 2, mxx, mxy - 2,
    reaper.ImGui_IsItemHovered(ctx) and 0xAAAAAAFF or 0x666666FF)
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
  end

  CMP.draw_side("DEST (new)", cr.new_dedup, track_order, track_index, tmin, tmax, other_h, true, "cmp_new", cr.fps, cr.is_drop, hidden_tracks, hidden_reels, hidden_groups)
end

---------------------------------------------------------------------------
-- Draw: Main Content Area (split view support)
---------------------------------------------------------------------------
local function draw_main_content()
  -- Compare view takes over the whole content area when active.
  if CLB.show_compare_view then
    CMP.draw_panel()
    return
  end

  -- Check if we're loading audio files
  if draw_loading_progress() then
    -- Show EDL table above progress bar
    draw_edl_panel_header()
    draw_table()
    return
  end

  local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)

  -- Reserve height for timeline panel
  local tl_h = (CLB.show_timeline and #ROWS > 0) and scale(TL_PANEL_H) or 0

  -- The inline Group Details panel takes over the same split-view slot the
  -- Audio List normally uses — Compare mode has no use for the audio panel
  -- there, and reusing the layout avoids a separate popup window. It's
  -- live: refreshed every frame from the current row selection, so it
  -- behaves like a "what does this match?" inspector, not a one-shot report.
  local show_details_panel = CLB.viewing_compare_groups and CLB.show_cmp_details
  local show_audio_panel   = (not show_details_panel) and CLB.show_audio_panel and #CLB.audio_files > 0

  if show_details_panel or show_audio_panel then
    -- Split view mode
    local splitter_h = 6
    local header_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx) + 4

    -- Calculate heights (subtract timeline panel from available space)
    local content_h = avail_h - splitter_h - header_h - tl_h
    local edl_h = content_h * CLB.split_ratio
    local lower_h = content_h - edl_h

    -- Upper section: EDL panel header + optional timeline + reel sidebar + EDL table
    draw_edl_panel_header()
    if CLB.show_timeline and #ROWS > 0 then draw_timeline_panel() end
    draw_reel_filter_sidebar(edl_h)
    draw_table(edl_h)

    -- Splitter (draggable, full width)
    draw_splitter()

    if show_details_panel then
      CMP.refresh_group_details()
      CMP.draw_group_details_header()
      CMP.draw_group_details_table(lower_h)
    else
      -- Audio panel header (full width)
      draw_audio_panel_header()

      -- Audio files table (full width)
      draw_audio_table(lower_h)
    end
  else
    -- Single table mode with optional reel sidebar (full height)
    draw_edl_panel_header()
    if CLB.show_timeline and #ROWS > 0 then draw_timeline_panel() end
    -- Re-query remaining height after timeline panel consumed its space
    _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    draw_reel_filter_sidebar(avail_h)
    draw_table()
  end
end

---------------------------------------------------------------------------
-- Subtitle Import Dialog
---------------------------------------------------------------------------

--- Render the CJK Font selection dialog.
--- Lets the user pick a font file (.ttf/.ttc/.otf) or type a family name.
--- On Apply: re-attaches the font to the ImGui context immediately and
--- saves the path so it persists across sessions.
local function draw_cjk_font_dialog()
  local d = CLB.cjk_font_dialog
  if not d or not d.open then return end

  local POPUP_ID = "CJK Font##clb_cjk_font"
  if not d._popped then
    reaper.ImGui_OpenPopup(ctx, POPUP_ID)
    d._popped = true
  end

  reaper.ImGui_SetNextWindowSize(ctx, scale(560), scale(260),
                                 reaper.ImGui_Cond_Appearing())

  local visible, open = reaper.ImGui_BeginPopupModal(ctx, POPUP_ID, true,
    reaper.ImGui_WindowFlags_NoCollapse())
  if not visible then
    if not open then CLB.cjk_font_dialog = nil end
    return
  end

  reaper.ImGui_TextWrapped(ctx,
    "Set a custom font for CJK display. Useful for Taiwanese / Hakka and " ..
    "other rare characters not covered by PingFang. Accepts a font file " ..
    "(.ttf / .ttc / .otf) or a font family name.")

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Currently loaded:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, cjk_font_source ~= "" and cjk_font_source
                                                       or "(none / default)")

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Path or family name:")
  reaper.ImGui_SetNextItemWidth(ctx, scale(440))
  local chg, new_buf = reaper.ImGui_InputText(ctx, "##cjk_font_path", d.buf)
  if chg then d.buf = new_buf end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Browse...##cjk_font_browse",
                         scale(80), scale(22)) then
    if reaper.JS_Dialog_BrowseForOpenFiles then
      local rv, fp = reaper.JS_Dialog_BrowseForOpenFiles(
        "Select Font File", "", "",
        "Font files\0*.ttf;*.ttc;*.otf\0All files\0*.*\0", false)
      if rv == 1 and fp and fp ~= "" then
        d.buf = fp
      end
    else
      d.status_msg = "JS extension required for Browse"
      d.status_ok  = false
    end
  end

  reaper.ImGui_TextDisabled(ctx,
    "Examples:\n" ..
    "  /Library/Fonts/MyTaigiFont.ttf\n" ..
    "  /System/Library/Fonts/PingFang.ttc\n" ..
    "  Noto Sans CJK TC      (family name on macOS)")

  if d.status_msg and d.status_msg ~= "" then
    reaper.ImGui_Spacing(ctx)
    if d.status_ok then
      reaper.ImGui_TextColored(ctx, 0x80FF80FF, d.status_msg)
    else
      reaper.ImGui_TextColored(ctx, 0xFF8080FF, d.status_msg)
    end
  end

  reaper.ImGui_Separator(ctx)

  if reaper.ImGui_Button(ctx, "Apply", scale(90), scale(26)) then
    local trimmed = (d.buf or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local font, src, custom_err = _load_cjk_font(ctx, trimmed)
    if trimmed ~= "" and not custom_err then
      -- Custom path supplied AND it succeeded as the primary
      cjk_font = font
      cjk_font_source = src or trimmed
      CLB.cjk_font_path = trimmed
      save_prefs()
      d.status_msg = "Loaded: " .. tostring(cjk_font_source)
      d.status_ok  = true
    elseif trimmed == "" then
      -- Cleared → reset to auto-detect; whatever fallback resolves, use it
      cjk_font = font
      cjk_font_source = src or ""
      CLB.cjk_font_path = ""
      save_prefs()
      d.status_msg = "Reset to default. Loaded: " ..
                     (cjk_font and tostring(cjk_font_source) or "(none)")
      d.status_ok  = cjk_font ~= nil
    else
      -- Custom failed; do not swap
      d.status_msg = "Failed: " .. tostring(custom_err)
      d.status_ok  = false
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Reset to Default", scale(140), scale(26)) then
    d.buf = ""
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Close", scale(80), scale(26)) then
    CLB.cjk_font_dialog = nil
    reaper.ImGui_CloseCurrentPopup(ctx)
  end

  reaper.ImGui_EndPopup(ctx)
end

--- Render the subtitle inspect / column-selection dialog.
--- Called every frame from the main loop; only does work if open.
local function draw_subtitle_inspect_dialog()
  local st = CLB.subtitle_inspect
  if not st or not st.open then return end

  local POPUP_ID = "Subtitle Import##clb_subtitle_inspect"

  -- Open on first frame
  if not st._popped then
    reaper.ImGui_OpenPopup(ctx, POPUP_ID)
    st._popped = true
  end

  -- Center on first appearance
  reaper.ImGui_SetNextWindowSize(ctx, scale(680), scale(480),
                                 reaper.ImGui_Cond_Appearing())

  local visible, open = reaper.ImGui_BeginPopupModal(ctx, POPUP_ID, true,
    reaper.ImGui_WindowFlags_NoCollapse())

  if not visible then
    if not open then CLB.subtitle_inspect = nil end
    return
  end

  -- File header
  local fname = (st.filepath or ""):match("([^/\\]+)$") or st.filepath or ""
  reaper.ImGui_Text(ctx, fname)
  reaper.ImGui_TextDisabled(ctx, "Format: " .. (st.format or "?"))
  reaper.ImGui_Separator(ctx)

  -- Sheet selector (XLSX with multiple sheets)
  if st.sheets and #st.sheets > 1 then
    reaper.ImGui_Text(ctx, "Sheet:")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, scale(220))
    local cur_sheet = st.sheets[st.selected_sheet_idx] or st.sheets[1]
    if reaper.ImGui_BeginCombo(ctx, "##subtitle_sheet", cur_sheet.name) then
      for i, sheet in ipairs(st.sheets) do
        local sel = (i == st.selected_sheet_idx)
        if reaper.ImGui_Selectable(ctx, sheet.name, sel) then
          st.selected_sheet_idx = i
          -- Reset text col when sheet changes
          local tc = sheet.text_candidates and sheet.text_candidates[1] or nil
          st.selected_text_col = tc
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end
  end

  local active_sheet = (st.sheets and st.sheets[st.selected_sheet_idx]) or st.sheets[1]
  if not active_sheet then
    reaper.ImGui_TextColored(ctx, 0xFF6060FF, "No sheet data available.")
    if reaper.ImGui_Button(ctx, "Close", scale(80), scale(24)) then
      CLB.subtitle_inspect = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
    return
  end

  -- Auto-detection summary
  local in_col  = active_sheet.detected_in_col
  local out_col = active_sheet.detected_out_col
  local function _col_name(idx)
    if not idx then return "(none)" end
    local cols = active_sheet.columns or {}
    for _, c in ipairs(cols) do
      if c.index == idx then return c.name end
    end
    return "Column " .. tostring(idx)
  end

  if in_col and out_col then
    reaper.ImGui_Text(ctx, string.format(
      "IN column: %s (#%d)    OUT column: %s (#%d)  -- auto-detected",
      _col_name(in_col), in_col, _col_name(out_col), out_col))
  else
    reaper.ImGui_TextColored(ctx, 0xFFD060FF,
      "Could not auto-detect IN/OUT columns. Pick a different sheet, or "
      .. "ensure the sheet has at least two timecode columns.")
  end

  -- Sample rows preview
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Preview (first rows):")
  local sample_rows = active_sheet.sample_rows or {}
  local cols = active_sheet.columns or {}
  if #sample_rows > 0 and #cols > 0 then
    local table_flags = reaper.ImGui_TableFlags_Borders()
                      | reaper.ImGui_TableFlags_RowBg()
                      | reaper.ImGui_TableFlags_ScrollX()
                      | reaper.ImGui_TableFlags_ScrollY()
                      | reaper.ImGui_TableFlags_SizingFixedFit()
    if reaper.ImGui_BeginTable(ctx, "##subtitle_preview", #cols,
                               table_flags, 0, scale(160)) then
      for _, c in ipairs(cols) do
        local label = c.name .. "##sub_col_" .. tostring(c.index)
        reaper.ImGui_TableSetupColumn(ctx, label,
          reaper.ImGui_TableColumnFlags_WidthFixed(), scale(100))
      end
      reaper.ImGui_TableHeadersRow(ctx)
      for _, row in ipairs(sample_rows) do
        reaper.ImGui_TableNextRow(ctx)
        for ci, c in ipairs(cols) do
          reaper.ImGui_TableSetColumnIndex(ctx, ci - 1)
          local v = row[c.index] or ""
          if c.index == in_col or c.index == out_col then
            reaper.ImGui_TextColored(ctx, 0x80C0FFFF, tostring(v))
          elseif c.index == st.selected_text_col then
            reaper.ImGui_TextColored(ctx, 0xC0FFA0FF, tostring(v))
          else
            reaper.ImGui_Text(ctx, tostring(v))
          end
        end
      end
      reaper.ImGui_EndTable(ctx)
    end
  else
    reaper.ImGui_TextDisabled(ctx, "(no preview data)")
  end

  -- Text-column picker
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, "Text column:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(220))
  local cur_label = (st.selected_text_col and _col_name(st.selected_text_col)
                     .. " (#" .. st.selected_text_col .. ")") or "(select)"
  if reaper.ImGui_BeginCombo(ctx, "##subtitle_text_col", cur_label) then
    -- Always offer all columns except IN/OUT; mark candidates with a star
    local cand_set = {}
    for _, ci in ipairs(active_sheet.text_candidates or {}) do cand_set[ci] = true end
    for _, c in ipairs(cols) do
      if c.index ~= in_col and c.index ~= out_col then
        local marker = cand_set[c.index] and " *" or ""
        local label = string.format("%s (#%d)%s", c.name, c.index, marker)
        local sel = (c.index == st.selected_text_col)
        if reaper.ImGui_Selectable(ctx, label, sel) then
          st.selected_text_col = c.index
        end
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "(* = auto-suggested)")

  -- Frame rate is taken from CLB.fps; the existing post-import "Confirm Frame
  -- Rate" prompt (confirm_fps()) is the canonical place to adjust it.
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_TextDisabled(ctx, string.format(
    "Parsing TC at %.3f fps%s — adjust in the Confirm Frame Rate prompt after Import.",
    CLB.fps or 25, CLB.is_drop and " (drop frame)" or ""))

  -- Buttons
  reaper.ImGui_Separator(ctx)

  local can_import = (in_col ~= nil and out_col ~= nil and
                      st.selected_text_col ~= nil)

  if not can_import then reaper.ImGui_BeginDisabled(ctx, true) end
  if reaper.ImGui_Button(ctx, "Import", scale(100), scale(28)) then
    local fps_num = tonumber(CLB.fps) or 25
    local sheet_arg = nil
    if st.format == "XLSX" and st.sheets and #st.sheets > 0 then
      sheet_arg = active_sheet.name
    end

    local parsed, perr = SUBTITLE.parse(st.filepath, {
      python      = OTIO.python,
      default_fps = fps_num,
      is_drop     = CLB.is_drop and true or false,
      sheet       = sheet_arg,
      in_col      = in_col,
      out_col     = out_col,
      text_col    = st.selected_text_col,
    })

    if not parsed then
      reaper.ShowMessageBox(
        "Failed to parse subtitle file:\n\n" .. tostring(perr),
        SCRIPT_NAME, 0)
    else
      _apply_subtitle_parsed(parsed, st.filepath)
      console_msg(string.format(
        "Loaded %d subtitle entries from %s (%s, fps=%g)",
        #parsed.events,
        (st.filepath:match("([^/\\]+)$") or st.filepath),
        sheet_arg or st.format or "FILE",
        fps_num))
      CLB.subtitle_inspect = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
      reaper.ImGui_EndPopup(ctx)
      return
    end
  end
  if not can_import then reaper.ImGui_EndDisabled(ctx) end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Cancel", scale(80), scale(28)) then
    CLB.subtitle_inspect = nil
    reaper.ImGui_CloseCurrentPopup(ctx)
  end

  reaper.ImGui_EndPopup(ctx)
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function loop()
  -- Process async audio loading (if in progress)
  process_audio_loading_batch()
  -- Process async OTIO/AAF background parse (if in progress)
  process_otio_loading()
  -- Process a chunk of the current batch job (Generate Items / Conform /
  -- Match All), if one is running
  CLB.process_batch_job()

  -- Process a pending action requested by an external wrapper script
  -- (e.g. hsuanice_Conform List Browser - CLB Load from REAPER.lua) via ExtState — lets a
  -- Reaper Action List shortcut drive CLB even when this window wasn't
  -- already open (the wrapper launches/wakes this script, then sets
  -- this flag; picked up on the very next frame either way). Consumed
  -- immediately so it only ever fires once per request.
  do
    local pending = reaper.GetExtState(EXT_NS, "pending_action")
    if pending ~= "" then
      reaper.SetExtState(EXT_NS, "pending_action", "", false)
      if pending == "load_from_reaper" then
        CLB.load_from_reaper_selection()
      elseif pending == "link_reaper_items" then -- hsuanice_Conform List Browser - CLB Link REAPER Items.lua
        CLB.link_reaper_items_selection()
      elseif pending == "reveal_item" then -- hsuanice_Conform List Browser - CLB Reveal Item.lua
        CLB._follow_sig = CLB._reaper_sel_sig() -- don't re-reveal it via Follow next frame
        CLB.reveal_reaper_selection(false)
      end
    end
  end

  -- "Follow Reaper": reveal the selected Reaper item(s)' event(s) whenever
  -- the selection changes. Three cheap API calls per frame (see
  -- CLB._reaper_sel_sig); the actual lookup only runs on a change.
  -- CLB → Reaper first: a table selection change (once the mouse is
  -- released — a box-select drag rebuilds it every frame) pushes the
  -- rows' linked items to Reaper. Then Reaper → CLB below.
  if CLB.follow_reaper_sel and SEL.version ~= CLB._sel_synced_version
     and not reaper.ImGui_IsMouseDown(ctx, 0) then
    CLB.sync_reaper_from_table_sel()
  end
  if CLB.follow_reaper_sel and #ROWS > 0 then
    local sig = CLB._reaper_sel_sig()
    if sig ~= CLB._follow_sig then
      CLB._follow_sig = sig
      if sig ~= "0" then CLB.reveal_reaper_selection(true) end
    end
  end

  -- Push font: prefer the CJK-capable font when available so Chinese / Japanese
  -- text in clip names (e.g. from subtitle import) renders correctly. Falls
  -- back to the ImGui default if the CJK font failed to load.
  font_pushed_this_frame = false
  if reaper.ImGui_PushFont then
    local font_obj = cjk_font  -- nil → default font
    local push_size = current_font_size
    -- Always push when we have a custom CJK font so glyph coverage is present;
    -- otherwise only push when size differs from default to avoid no-op cost.
    if font_obj or current_font_size ~= 13 then
      local ok_font = pcall(reaper.ImGui_PushFont, ctx, font_obj, push_size)
      if ok_font then
        font_pushed_this_frame = true
      elseif font_obj then
        -- Custom-font push failed (older ReaImGui without size override?);
        -- retry without size, then with default font + size.
        local ok2 = pcall(reaper.ImGui_PushFont, ctx, font_obj)
        if ok2 then
          font_pushed_this_frame = true
        else
          local ok3 = pcall(reaper.ImGui_PushFont, ctx, nil, current_font_size)
          if ok3 then font_pushed_this_frame = true end
        end
      end
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
    -- Toolbar (Save/Open/Load List/Load Audio/Export EDL, FPS, Search,
    -- panel toggles, Options — the "action" buttons live in the left
    -- sidebar below, not here; see draw_left_sidebar's own doc comment)
    draw_toolbar()

    -- Left sidebar (action buttons) + everything else, side by side.
    -- User's own workflow: the list itself only needs a glance most of
    -- the time, but the action buttons get clicked constantly while
    -- flipping back and forth checking REAPER's own window — they need
    -- to stay reachable on the left edge even when this window is
    -- narrow and parked off to one side of the screen.
    local sidebar_w = scale(150)
    if reaper.ImGui_BeginChild(ctx, "##clb_left_sidebar", sidebar_w, 0) then
      CLB.draw_left_sidebar()
    end
    reaper.ImGui_EndChild(ctx)
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_BeginChild(ctx, "##clb_right_content", 0, 0) then
      -- Sources panel (collapsible, between toolbar and table)
      draw_sources_panel()

      -- Track filter panel
      draw_track_filter_panel()

      reaper.ImGui_Separator(ctx)

      -- Main content (EDL table, optionally split with Audio table)
      draw_main_content()
    end
    reaper.ImGui_EndChild(ctx)

    -- Subtitle import inspect/column-picker dialog (modal popup)
    draw_subtitle_inspect_dialog()

    -- CJK font path dialog (modal popup, opened from Options menu)
    draw_cjk_font_dialog()

    -- Keyboard shortcuts
    local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
    -- Not while a text field (Search, popups' InputText) is being typed
    -- in — Cmd+A/C/V/Z, arrows, Home/End belong to that field then.
    if focused and not EDIT and not reaper.ImGui_IsAnyItemActive(ctx) then
      local shift, cmd = _mods()

      -- ↑↓ / Home / End (Cmd+↑↓ = Home/End, macOS-style); +Shift extends
      local nav_t
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow(), true) then
        nav_t = cmd and "home" or -1
      elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow(), true) then
        nav_t = cmd and "end" or 1
      elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Home(), false) then
        nav_t = "home"
      elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_End(), false) then
        nav_t = "end"
      end
      if nav_t then CLB.table_nav(nav_t, shift) end

      -- Cmd+F = jump to the Search box
      if cmd and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F(), false) then
        CLB.focus_search = true
      end

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
        if #vr > 0 then
          SEL.anchor = { guid = vr[1].__guid, col = COL.CLIP_NAME }
          CLB.sel_cursor = { guid = vr[#vr].__guid, col = COL.CLIP_NAME }
        end
      end

      -- Delete: same meaning everywhere now, main table and timeline
      -- alike (confirmed with the user — previously the main table
      -- cleared selected CELL VALUES, a destructive spreadsheet-editing
      -- action with no undo-visible record of what was removed). Tags
      -- every selected row's group as "Delete" non-destructively and
      -- hides the Delete group, so excluded events just drop out of view
      -- — the same list-cleanup gesture whether you selected clips in
      -- the timeline or rows/cells in the table. To clear an individual
      -- cell's text now, double-click to edit it and delete the text
      -- directly, rather than selecting + pressing Delete.
      if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete(), false) or
         reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace(), false) then
        local sel_rows = get_selected_rows()
        if #sel_rows > 0 then
          for _, r in ipairs(sel_rows) do r.group = "Delete" end
          _rebuild_group_filters()
          -- Hide the Delete group immediately, same as toggling it off
          -- by hand, so tagged clips drop out of view right away.
          for _, gf in ipairs(CLB.group_filters) do
            if gf.name == "Delete" then gf.visible = false end
          end
          undo_snapshot()
          CLB.cached_rows = nil
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

-- Configure OTIO Python path.
-- load_prefs() may have restored a saved path; if empty or invalid (e.g. a
-- pyenv virtualenv that was since removed), auto-detect a working one.
if not OTIO.python or OTIO.python == "" or not OTIO.python_supports(OTIO.python) then
  OTIO.python = OTIO.detect_python()
  save_prefs()
end

ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)
if reaper.ImGui_CreateListClipper then
  list_clipper = reaper.ImGui_CreateListClipper(ctx)
end

-- Load a CJK-capable font so Chinese / Japanese text (e.g. from subtitle
-- import) renders properly. ImGui's default font is ASCII-only.
-- Custom path (Options → CJK Font…) wins; otherwise platform candidates.
do
  local font, src, custom_err = _load_cjk_font(ctx, CLB.cjk_font_path)
  cjk_font = font
  cjk_font_source = src or ""
  if custom_err then
    console_msg("CJK font (custom): failed to load '" ..
                tostring(CLB.cjk_font_path) .. "' — " .. tostring(custom_err))
  end
  if cjk_font then
    console_msg("CJK font loaded: " .. tostring(cjk_font_source))
  else
    console_msg("CJK font: none found; default font will be used (CJK glyphs missing)")
  end
end

console_msg("Conform List Browser v" .. VERSION .. " started")
console_msg("OTIO Bridge v" .. (OTIO.VERSION or "?") .. " | Python: " .. OTIO.python)
console_msg("EDL Parser v" .. (EDL.VERSION or "?"))

-- "Is CLB running" heartbeat for external wrapper scripts (e.g.
-- hsuanice_Conform List Browser - CLB Load from REAPER.lua) — Reaper's own GetToggleCommandStateEx
-- doesn't reliably report this (confirmed by real user report: a wrapper
-- using it still toggled CLB OFF every time, since this script never
-- registers toggle state at all), so a plain ExtState flag this script
-- sets itself on startup and clears on exit is the only robust signal. A
-- wrapper reads this to decide "signal the already-running instance" vs.
-- "launch it" WITHOUT ever calling this script's own command on a guess.
reaper.SetExtState(EXT_NS, "is_running", "1", false)
reaper.atexit(function()
  reaper.SetExtState(EXT_NS, "is_running", "", false)
end)

reaper.defer(loop)
