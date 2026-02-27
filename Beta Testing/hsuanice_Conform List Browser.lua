--[[
@description Conform List Browser
@version 260228.0122
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

  Supported formats (via OpenTimelineIO):
    - CMX3600 EDL (.edl)
    - FCP7 XML (.xml) — Final Cut Pro 7 and DaVinci Resolve XML export

  Future: AAF, FCPX, Premiere XML

  Requires: ReaImGui (install via ReaPack)
  Optional: js_ReaScriptAPI (for folder selection)
  Required: Python 3 + opentimelineio (pip3 install opentimelineio)

@changelog
  v260228.0122
  - Fix: Splitter between Event List and Audio List now responds to vertical drag (up/down)
    • Was reading delta_x instead of delta_y from ImGui_GetMouseDelta
  - Feature: "Reels >>" button replaced with "Filters >>" — toggles Reels and Groups together

  v260228.0052
  - Feature: Fit Widths button is now a toggle (Fit Widths ↔ Default) for both EDL and Audio tables
    • "Fit Widths" only stretches content-heavy columns (Clip Name, Notes, Filename, etc.);
      fixed-content columns (TC, Duration, Level, SR, Ch, FPS, Speed) keep their default widths
    • Clicking "Default" restores all columns to their default pixel widths
    • Audio table now uses the same fixed+stretchy strategy as the EDL table
  - Fix: Audio File List column visibility is now persisted across sessions
    • Show/hide state saved via ExtState "audio_col_visibility"
    • Restored on script load; any change in the Columns popup is saved immediately

  v260227.1717
  - Fix: Search box now correctly matches TC columns (Src TC In/Out, Rec TC In/Out, Duration)
    • __search_text is rebuilt in 4 places; all now include TC fields
    • Previously only the initial EDL load rebuilt search text with TC — after any cell edit,
      paste, undo/redo, or .clb project load, TC was dropped from search index

  v260227.1714
  - Fix: Fit Widths now works correctly and is idempotent (same result every click, no drift)
    • EDL table: fixed-width columns (Reel, Track, Edit, Level, all TC/Duration) stay at
      their default widths; stretchy columns (Clip Name, Source File, Notes, Matched File,
      Group) share the remaining window width proportionally
    • Both EDL and audio tables: always compute from DEFAULT widths, never from already-
      fitted widths (which caused slow shrinkage each click due to rounding/scrollbar drift)
    • Table ID bumped on each Fit Widths click so ImGui creates fresh column state
  - Fix: Transition events (e.g. BL reel wipes) now show correct clip name
    • When TO CLIP NAME is present, it is used as clip_name instead of FROM CLIP NAME
    • FROM CLIP NAME and TO CLIP NAME lines now also appear in the Notes column
    • Example: BL → W001 wipe event now shows "4-1-4T1.WAV" not blank

  v260227.1330
  - Fix: FPS option now shows "24/23.97" so users can find 23.976 FPS files
  - Fix: Fit Widths now works reliably every click (calculates proportional widths directly,
    no longer uses WidthStretch toggle which caused revert on second click)
  - Feature: Timeline block color scheme reworked for clearer selection feedback
    • Unselected clips: neutral dark gray (0x3A3A3A) — reduces visual noise
    • Selected clips: full-brightness track color (blue/amber/green)
    • Edge and text label also dim/brighten with selection state

  v260227.1300
  - Fix: Toolbar row height increased by 14px to prevent scrollbar from clipping buttons
  - Fix: FPS 23.976 and 24 merged into single "24" option (match tolerance widened to 0.03)
  - Fix: EDL "Fit Widths" button now correctly stretches columns to fill table width
  - Feature: Timeline TC ruler now shows HH:MM:SS:FF timecode (uses EDL.seconds_to_tc)
    • Tick spacing increased to 80px minimum to accommodate wider TC labels
    • Sub-second (frame-level) tick intervals added at high zoom
  - Feature: Timeline horizontal scrollbar (SliderDouble at bottom of panel)
    • TL_PANEL_H increased from 120 to 136px to accommodate scrollbar
  - Feature: Timeline ↔ List bidirectional selection sync
    • Clicking a block in timeline selects all columns of that row in the list
    • List now scrolls to the selected row (SetScrollHereY, clipper disabled for that frame)
    • Clicking a row in list centers timeline view on that row's block
    • Timeline block highlight now reflects any-column selection (sel_has_row)
  - Fix: $format token now returns user-friendly names (CMX3600→"EDL", *XML*→"XML", AAF→"AAF")

  v260227.1230
  - Feature: Level column (COL.LEVEL = 17) for audio/video level dB values
    • New "Level" column positioned between Edit and Dissolve (Edit → Level → Dissolve)
    • Auto-populated from EDL AUDIO/VIDEO LEVEL comments on file load
    • Multiple level values joined with " | " separator
    • Editable by user; included in full-text search
    • Persisted in .clb project file (backward-compatible: p[19])
    • Visible by default; can be toggled in Columns popup

  v260227.1400
  - Feature: Extra EDL comments preserved in Notes column
    • All * comment lines that are not FROM CLIP NAME / SOURCE FILE / TO CLIP NAME
      are now auto-populated into the Notes column on EDL load
    • Includes: AUDIO LEVEL, VIDEO LEVEL, EFFECTS NAME IS, and any other * lines
    • Multiple extra comments joined with " | " separator
    • Notes remain editable (user can clear/modify freely)
  - Feature: audio_levels field on each row (parsed from EDL AUDIO/VIDEO LEVEL comments)
    • row.audio_levels = [{ type, tc, db, reel, src_track }]
    • reel/src_track populated from "(REEL REEL_NAME TRACK)" suffix when present
    • Available for programmatic use (e.g., future auto-level or source-track matching)
  - Requires hsuanice_EDL Parser.lua ≥ v0.3.0

  v260227.0140
  - Feature: Mini-timeline visualization panel
    • Collapsible horizontal panel (toggle "Timeline >>" in EDL header)
    • Events displayed as colored blocks on a horizontal track layout
    • A-tracks: blue, V-tracks: amber, others: green
    • TC ruler with adaptive tick intervals
    • Drag to pan, scroll wheel to zoom (zoom anchored to cursor)
    • Click block → selects + scrolls to corresponding table row
    • Hover → tooltip with clip name, Rec TC In/Out, duration
    • Respects current Track/Reel/Group filters and search box

  v260227.0120
  - Feature: OpenTimelineIO integration for XML import (FCP7, Resolve)
    • New files: Tools/otio_to_clb.py, Library/hsuanice_OTIO Bridge.lua, Library/json.lua
    • "Load XML..." button now functional: FCP7 XML and DaVinci Resolve XML — NEW
    • load_edl_file() and load_xml_file() share a common _load_timeline_via_otio() helper
    • CLB.loaded_format reflects actual format name (e.g. "FCP7_XML")
    • OTIO Bridge auto-routes .edl → native Lua parser (OTIO CMX3600 adapter loses
      record TC offsets and has dual-track bugs — not suitable for conform workflows)
  - Requires for XML: python3 in PATH, opentimelineio installed

  v260221.1500
  - Perf: Switch get_view_rows() and get_audio_view_rows() from frame-based to dirty-flag cache
    • Previously both functions rebuilt the filtered list every single frame (O(n) per frame)
    • Now the cached result is reused until explicitly invalidated (CLB.cached_rows = nil)
    • Eliminates redundant O(n) filtering on 6,000–10,000+ audio file lists every 60+ Hz frame
    • Removed frame_counter, cached_rows_frame, audio_cached_frame fields entirely

  v260221.1400
  - Fix: REAPER lag when audio files are loaded
    • Audio table was rendering ALL rows every frame (no virtualization)
    • Added ListClipper to draw_audio_table() — same as EDL table
    • Now only visible rows are rendered per frame (50+ row threshold)

  v260221.1128
  - Revert: removed all loop rate-cap experiments
    • Rate cap (early return) → context invalidity crash on macOS
    • do_draw content skip → window flickering + buttons unclickable
    • ImGui immediate mode requires full redraw every frame; partial draw
      or skipped frames are not viable in ReaImGui
    • Loop restored to original structure (render everything every defer call)
    • REAPER lag issue deferred — needs a different investigation approach

  v260221.1041
  - Fix: REAPER lag when CLB is open
    • Added frame rate cap to the defer loop: 30fps when window active, 10fps when idle
    • Previously the loop ran at full REAPER main-thread rate (60+ Hz), consuming
      continuous main-thread time even when nothing was changing
    • Audio metadata loading batch still runs at full defer rate (unaffected)
  - Fix: Filter state (Track/Reel/Group checked/unchecked) now saved in .clb project
    • Unchecked tracks, reels, and groups are restored exactly on Open
    • Filter panel visibility (show/hide sidebar panels) also saved and restored
    • Audio panel show/hide state saved and restored

  v260221.1019
  - Feature: Save / Open project (.clb format)
    • "Save..." button in toolbar: saves full session to a .clb file
      - FPS, drop-frame, track format, audio folder path
      - EDL column order and visibility
      - All EDL sources (path, name, visibility)
      - All event rows (including edits, groups, match status, matched paths)
    • "Open..." button in toolbar: restores session from .clb file
      - All row data restored (edits, groups, match state preserved — no re-matching needed)
      - If audio folder has a cache (.clbcache), audio files auto-restored
      - If no cache, click "Load Audio..." to re-scan
    • File format: CLB_PROJECT_V1 (pipe-delimited, with escape for special chars)

  v260220.1535
  - Fix: Consolidate track naming rules
    • Audio group → A1, A2, A3 ... (no space)
    • Video group → V1, V2, V3 ... (no space)
    • Other groups → GroupName 1, GroupName 2, ... (space before number)
    • Each group's track numbers restart from 1 independently
  - Fix: Conform / Generate Items track order now sorted (natural sort: A1, A2, A10)
    • Tracks appear in correct order in REAPER project after conform

  v260209.1846
  - Feature: Group as table column (COL.GROUP = 16, hidden by default, enable via Columns popup)
    • Double-click cell to inline edit group name
    • Group column included in search text and undo/redo
  - Feature: User-managed Group list in sidebar
    • + button to add new group
    • Right-click group checkbox: Rename / Delete / Assign Selected Rows
    • Delete group: events become unassigned (group = "")
    • Unassigned events shown as "(Unassigned)" in sidebar
  - Feature: Consolidate button in toolbar (next to Remove Dups)
    • Consolidates tracks by group via bin-packing (no time overlap)
    • Tracks renumbered as GroupName1, GroupName2, ... globally across all groups
  - Feature: Table right-click → Assign Group
    • Applies to all selected rows (multi-select via Shift/Cmd+click)
    • Falls back to clicked row if nothing selected
    • (Unassign) option to clear group
  - Fix: All right-click context menu popups now work (rename/delete/batch rename)
    • Root cause: OpenPopup was called inside context menu popup (wrong scope)
    • Fixed with deferred flags for track, reel, and group context menus
  - Fix: Cell edit confirmed when clicking elsewhere (not just Enter)
    • Added IsItemDeactivated check so clicking away closes edit mode
  - Fix: Column reorder now works via table header drag (EDL + Audio tables)
    • Column editor popup simplified to show/hide only (no drag list)
    • EDL table headers switched from Text() to TableHeader() to enable drag reorder
  - Fix: Track name normalization on EDL load (AA→A, VV→V, etc.)
  - Fix: Sidebar Reel/Group panel minimum width increased (~5 chars wider)
    • To adjust: draw_reel_filter_sidebar() → max_text_w (line ~4694) and sidebar_w padding (line ~4710)

  v260209.1625
  - Fix: Remove Duplicates now compares by Reel + Src TC + Rec TC + Clip Name (excludes Track)
    • More robust duplicate detection that ignores track changes
    • Prevents false duplicates when same event appears on multiple tracks

  v260207.1600
  - Feature: Group Filter in sidebar
    • Auto-groups tracks by prefix: A* → Audio, V* → Video, NONE → NONE
    • Groups panel below Reels panel (Reels 2/3, Groups 1/3 height)
    • Toggle group visibility to filter events by category
    • Hover to see which tracks belong to each group
  - Fix: Track Filter right-click menu now works
    • Popup was opening in wrong ImGui scope
  - Fix: Reel Filter right-click menu now works
    • Added Rename, Delete, and Batch Rename options

  v260207.1500
  - Feature: Track Consolidation (like EdiLoad)
    • Right-click Track Filter → "Consolidate Tracks..."
    • Select which tracks to consolidate (e.g., A1~A17 for Dialog)
    • Merges events into minimum tracks without time overlap
    • Uses greedy bin-packing algorithm for optimal track count
    • Specify new track name prefix (e.g., "DX" → DX1, DX2...)
    • Preview shows estimated result before applying

  v260207.1400
  - Feature: Natural sorting for Track/Reel filters
    • Now sorts correctly: A1, A2, A3... A10 (instead of A1, A10, A2)
  - Feature: Batch Rename for Tracks and Reels
    • Right-click any Track/Reel → "Batch Rename All..."
    • Find and replace text across all track/reel names
    • Shows preview count of affected events
  - Fix: Track Filter panel height increased
    • Checkboxes no longer cut off by horizontal scrollbar

  v260207.1300
  - Feature: EDL column editor with drag reorder
    • New "Columns" button in EDL panel header
    • Show/hide individual columns with checkboxes
    • Drag to reorder columns (like Audio panel)
    • "All" / "None" / "Reset" buttons for quick configuration
    • Column settings saved and restored across sessions
  - Feature: Scrollable toolbar and filter panels
    • Toolbar rows now scroll horizontally when window is narrow
    • Track Filter panel now scrolls horizontally for many tracks (A1~A30+)
    • Prevents UI clipping on small windows or large track counts
  - UI: Toolbar layout improvements
    • Search field moved after FPS selector (more accessible)
    • Track Format field moved to end (rarely modified)

  v260207.0900
  - Feature: Track naming for multiple EDL imports
    • Tracks renamed with source suffix when multiple EDLs loaded
    • Example: EDL1 tracks A,V → A1,V1; EDL2 tracks A,V → A2,V2
    • Already-numbered tracks preserve number: A2 from EDL1 → A1-2
    • Single EDL keeps original track names
  - Feature: Event Number renumbering on EDL export
    • Events are automatically renumbered sequentially (001, 002, 003...)
    • Ensures clean, consecutive numbering regardless of original event numbers
  - Feature: Improved Track/Reel filter context menu
    • Right-click only (removed double-click which conflicted with checkbox)
    • Context menu with "Rename..." and "Delete..." options
    • Delete shows confirmation dialog with event count before removing

  v260206.2226
  - Feature: Simplified toolbar status
    • Removed EDL filename display, shows only "Events: X | Showing: Y"
    • Search box moved to right side of row 2 (after Export EDL)
  - Feature: Rename Track/Reel filters
    • Right-click on Track/Reel checkbox for context menu
    • Updates all matching EDL events automatically
    • Tooltip shows right-click hint on hover
  - Feature: Audio panel toolbar buttons
    • Fit Widths: auto-adjust column widths based on content
    • Copy (TSV): copy visible rows to clipboard
    • Save .tsv / Save .csv: export to file
    • Cols: show/hide columns popup (no presets needed)
  - Feature: Audio table column order
    • New order: Folder, Tape/Roll, Filename, Tracks, Src TC, Scene, Take,
      Ch, Duration, SR, Project, FPS, Speed, Orig File, Description
    • Reset table ID to clear previous column order memory
  - Fix: TSV/CSV export handles newlines in Description field
    • TSV: replaces newlines and tabs with spaces
    • CSV: properly quotes fields containing special characters

  v260206.2152
  - Feature: Reel filter sidebar
    • Moved from horizontal bar to left sidebar panel
    • Displays alongside EDL table for better space utilization
    • Auto-width based on longest reel name
    • Scrollable when many reels present
  - Feature: Additional BWF Description parsing
    • sPROJECT, sFRAMERATE, sSPEED, sTRKx (track names), sFiLENAME
    • New audio table columns: Framerate, Speed, Orig Filename, Track Names
  - Feature: Audio table sortable and reorderable
    • Click headers to sort by column
    • Drag headers to reorder columns
  - Feature: FPS setting now remembered
    • Saves both FPS value and drop-frame flag
    • Persists across script restarts
  - Fix: Generate Items / Conform All now respects filters
    • Only processes visible events (filtered by Source/Track/Reel)
    • Hidden events are skipped
  - Fix: Track and Reel filters visible by default
  - Fix: Cache format updated to support new metadata fields

  v260206.1500
  - Feature: Reel filter (similar to Sources/Tracks filter)
    • "Reels >>" toggle button in toolbar shows/hides panel
    • Each unique reel listed with event count and checkbox
    • Show All / Hide All buttons for quick toggling
    • Scrollable list for EDLs with many reels
  - Feature: Audio metadata cache
    • Caches metadata to disk after first scan
    • Subsequent loads of same folder use cache (instant load)
    • Cache invalidated if files no longer exist
    • Cache file stored in audio folder as !CLB_Audio_Cache.clbcache
  - Feature: FPS dropdown selector
    • Common frame rates: 23.976, 24, 25, 29.97 DF, 30, 50, 59.94 DF, 60
    • Automatically sets drop-frame mode for 29.97/59.94
  - Feature: Enhanced Track Format tokens
    • Supports: ${track} ${reel} ${clip} ${event} ${format} ${title} ${edit_type}
    • Items grouped by expanded track name (e.g., "${reel} - ${track}")
  - Fix: Audio panel toggle
    • "Audio >>" toggle button in toolbar to show/hide audio panel
    • Previously hidden panel could not be shown again

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
    • Detects duplicates by composite key (reel + src TC in/out + rec TC in/out + clip name)
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
local VERSION = "260228.0122"

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
}

local COL_COUNT = 17

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
  [2]  = 65,  -- Src TC
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
}
-- Stretchy: CLIP_NAME (11), SRC_FILE (12), NOTES (13), MATCHED_PATH (15), GROUP (16)

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
  COL.REC_IN,       -- 9. Rec TC In
  COL.REC_OUT,      -- 10. Rec TC Out
  COL.DURATION,     -- 11. Duration
  COL.CLIP_NAME,    -- 12. Clip Name
  COL.SRC_FILE,     -- 13. Source File
  COL.NOTES,        -- 14. Notes
  COL.MATCH_STATUS, -- 15. Match
  COL.MATCHED_PATH, -- 16. Matched File
  COL.GROUP,        -- 17. Group
}

-- EDL column visibility (all visible by default, except Group)
local EDL_COL_VISIBILITY = {}
for i = 1, COL_COUNT do
  EDL_COL_VISIBILITY[i] = true
end
EDL_COL_VISIBILITY[COL.GROUP] = false

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
  tl_center_on_guid = nil,  -- list click → center timeline on this row
  visible_range = { first = 0, last = 0 },
  cached_rows = nil,

  -- Settings
  fps = 25,
  is_drop = false,
  track_name_format = "${format} - ${track}",
  last_dir = "",
  last_audio_dir = "",

  -- UI state
  show_sources_panel = false,
  show_track_filter = true,
  track_filters = {},  -- { { name, count, visible }, ... }
  show_reel_filter = true,
  reel_filters = {},   -- { { name, count, visible }, ... }
  show_group_filter = true,
  group_filters = {},  -- { { name, count, visible, tracks={} }, ... }  -- tracks = list of track names in group

  -- Audio file matching state
  audio_files = {},           -- { {path, filename, basename, folder, metadata={}}, ... }
  audio_folder = "",          -- Loaded audio folder path
  audio_recursive = true,     -- Recursive search enabled
  show_audio_panel = false,   -- Show audio panel (auto-enabled when files loaded)
  split_ratio = 0.5,          -- Split ratio for EDL/Audio tables (0.3~0.7)
  audio_search = "",          -- Audio table search filter
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

  -- Loading state (for async loading with progress)
  loading_state = nil,        -- { phase, total, current, files }

  -- Match picker state
  match_picker_row = nil,     -- Row being matched (for multi-match selection)

  -- Rename/Delete filter state
  rename_filter = nil,        -- { type="track"|"reel", idx, old_name, buf }
  context_filter = nil,       -- { type="track"|"reel", idx, name } for context menu
  delete_filter = nil,        -- { type="track"|"reel", idx, name } for delete confirm
  batch_rename = nil,         -- { type="track"|"reel", find="", replace="" } for batch rename
  consolidate_tracks = nil,   -- { selected={}, prefix="" } for track consolidation
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
    -- Additional fields from BWF Description
    framerate = "",          -- sFRAMERATE
    speed = "",              -- sSPEED
    orig_filename = "",      -- sFiLENAME (original filename)
    track_names = "",        -- sTRK1, sTRK2, etc. (comma-separated)
    ubits = "",              -- sUBITS
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

  console_msg(string.format("Matching complete: %d found, %d multiple, %d not found",
    found_count, multiple_count, not_found_count))
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
  if search == "" then
    -- Copy array for sorting (don't modify original)
    result = {}
    for i, af in ipairs(CLB.audio_files) do
      result[i] = af
    end
  else
    result = {}
    for _, af in ipairs(CLB.audio_files) do
      -- Search in filename and metadata
      local meta = af.metadata or {}
      local searchable = (af.filename or "") .. " " ..
        (af.folder or "") .. " " ..
        (meta.scene or "") .. " " ..
        (meta.take or "") .. " " ..
        (meta.tape or "") .. " " ..
        (meta.project or "") .. " " ..
        (meta.orig_filename or "")
      if searchable:lower():find(search, 1, true) then
        result[#result + 1] = af
      end
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
      -- Handle strings (case-insensitive)
      va = tostring(va):lower()
      vb = tostring(vb):lower()
      if asc then return va < vb else return va > vb end
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

---------------------------------------------------------------------------
-- Preferences
---------------------------------------------------------------------------
local function save_prefs()
  reaper.SetExtState(EXT_NS, "font_scale", tostring(FONT_SCALE or 1.0), true)
  reaper.SetExtState(EXT_NS, "fps", tostring(CLB.fps or 25), true)
  reaper.SetExtState(EXT_NS, "is_drop", CLB.is_drop and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "track_name_format", CLB.track_name_format or "${format} - ${track}", true)
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
  CLB.is_drop = get("is_drop", "0") == "1"
  CLB.track_name_format = get("track_name_format", "${format} - ${track}")
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
    -- Only use if we got all columns
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
  if col_id == COL.GROUP        then return row.group or "" end
  return ""
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
        if not (row.__search_text and row.__search_text:find(search, 1, true)) then
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
      if row.__orig_track then
        row.track = row.__orig_track
      end
    end
    return
  end

  -- Multiple sources: apply suffix based on source index
  for _, row in ipairs(ROWS) do
    local orig = row.__orig_track or row.track
    local src_idx = row.__source_idx or 1
    row.track = _rename_track_with_suffix(orig, src_idx)
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
      clip_name = (evt.to_clip_name and evt.to_clip_name ~= "" and evt.to_clip_name)
                  or evt.clip_name or "",
      source_file = evt.source_file or "",
      notes = "",    -- auto-populated below from extra EDL comments
      level = "",    -- auto-populated below from AUDIO/VIDEO LEVEL comments
      group = "",
      audio_levels = evt.audio_levels or {},  -- [{ type, tc, db, reel, src_track }]

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
      row.src_tc_in, row.src_tc_out,
      row.rec_tc_in, row.rec_tc_out,
      row.duration,
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

--- Natural sort comparison (handles numbers correctly: A1, A2, A10 instead of A1, A10, A2)
local function _natural_sort_cmp(a, b)
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
local function _rebuild_reel_filters()
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
  for _, name in ipairs(reel_order) do
    CLB.reel_filters[#CLB.reel_filters + 1] = {
      name = name,
      count = reel_counts[name],
      visible = old_vis[name] == nil or old_vis[name],
    }
  end
end

--- Determine group for a track name based on prefix (used for initial auto-assign only).
--- A* → Audio, V* → Video, NONE → NONE, others → Other
local function _get_track_group(track_name)
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
        visible = true,
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
local function save_clb_project(filepath)
  local f = io.open(filepath, "w")
  if not f then
    reaper.ShowMessageBox("Cannot write to:\n" .. filepath, SCRIPT_NAME, 0)
    return false
  end

  f:write("CLB_PROJECT_V1\n")

  -- Settings
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

  -- EDL sources
  f:write(string.format("SOURCES|%d\n", #CLB.edl_sources))
  for _, src in ipairs(CLB.edl_sources) do
    f:write(string.format("S|%s|%s|%d|%s\n",
      _clb_escape(src.path or ""),
      _clb_escape(src.name or ""),
      src.event_count or 0,
      src.visible and "1" or "0"))
  end

  -- EDL rows (including match state and group assignments)
  -- Format: R|event_num|reel|track|edit_type|dissolve_len|
  --           src_tc_in|src_tc_out|rec_tc_in|rec_tc_out|
  --           clip_name|source_file|notes|
  --           match_status|matched_path|group|orig_track|source_idx|level
  f:write(string.format("ROWS|%d\n", #ROWS))
  for _, row in ipairs(ROWS) do
    f:write(string.format("R|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%s\n",
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
      _clb_escape(row.level        or "")))  -- p[19]
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
  reaper.ShowMessageBox(
    string.format("Project saved:\n%s\n\n%d events, %d sources",
      filepath:match("([^/\\]+)$") or filepath, #ROWS, #CLB.edl_sources),
    SCRIPT_NAME, 0)
  return true
end

--- Load a .clb project file and restore the full session state.
local function load_clb_project(filepath)
  local f = io.open(filepath, "r")
  if not f then
    reaper.ShowMessageBox("Cannot open:\n" .. filepath, SCRIPT_NAME, 0)
    return false
  end

  local header = f:read("*l")
  if header ~= "CLB_PROJECT_V1" then
    f:close()
    reaper.ShowMessageBox("Not a valid CLB project file.", SCRIPT_NAME, 0)
    return false
  end

  local new_fps              = 25
  local new_is_drop          = false
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

      if key == "FPS" then
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
        new_sources[#new_sources+1] = {
          path        = p[2] or "",
          name        = p[3] or "",
          event_count = tonumber(p[4]) or 0,
          visible     = (p[5] ~= "0"),
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
          duration     = dur,
        }
        row.__search_text = table.concat({
          row.event_num, row.reel, row.track,
          row.clip_name, row.source_file, row.notes, row.group, row.level,
          row.src_tc_in, row.src_tc_out,
          row.rec_tc_in, row.rec_tc_out,
          row.duration,
        }, " "):lower()
        new_rows[#new_rows+1] = row
      end
    end
  end
  f:close()

  -- Apply loaded data
  CLB.fps               = new_fps
  CLB.is_drop           = new_is_drop
  CLB.track_name_format = new_track_format
  CLB.audio_folder      = new_audio_folder
  CLB.audio_recursive   = new_audio_recursive
  if new_col_order then EDL_COL_ORDER      = new_col_order end
  if new_col_vis   then EDL_COL_VISIBILITY = new_col_vis   end
  CLB.edl_sources       = new_sources
  ROWS                  = new_rows
  _guid_counter         = max_guid

  -- Filter panel visibility flags
  if new_show_track   ~= nil then CLB.show_track_filter   = new_show_track   end
  if new_show_reel    ~= nil then CLB.show_reel_filter    = new_show_reel    end
  if new_show_group   ~= nil then CLB.show_group_filter   = new_show_group   end
  if new_show_sources ~= nil then CLB.show_sources_panel  = new_show_sources end

  -- Reset UI state
  sel_clear()
  EDIT = nil
  SORT_STATE.columns = {}
  UNDO_STACK = {}
  UNDO_POS   = 0
  undo_snapshot()
  CLB.loaded_file   = filepath
  CLB.loaded_format = "CLB"

  -- Rebuild filter panels, then apply saved hidden states
  _rebuild_track_filters()
  _rebuild_reel_filters()
  _rebuild_group_filters()

  if next(hidden_tracks) then
    for _, tf in ipairs(CLB.track_filters) do
      if hidden_tracks[tf.name] then tf.visible = false end
    end
  end
  if next(hidden_reels) then
    for _, rf in ipairs(CLB.reel_filters) do
      if hidden_reels[rf.name] then rf.visible = false end
    end
  end
  if next(hidden_groups) then
    for _, gf in ipairs(CLB.group_filters) do
      if hidden_groups[gf.name] then gf.visible = false end
    end
  end

  CLB.cached_rows = nil

  -- Try to restore audio files from cache (don't re-run matching — match data is in rows)
  CLB.audio_files      = {}
  CLB.show_audio_panel = false
  if new_audio_folder ~= "" then
    local cached = load_audio_cache(new_audio_folder, new_audio_recursive)
    if cached then
      CLB.audio_files = cached
      -- Restore audio panel visibility from file, or default to true if audio loaded
      CLB.show_audio_panel = (new_show_audio ~= nil) and new_show_audio or true
      console_msg(string.format("Restored %d audio files from cache", #cached))
    else
      console_msg("Audio cache not found — click 'Load Audio...' to re-scan: " .. new_audio_folder)
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

--- Save-as dialog → save_clb_project.
local function save_clb_project_dialog()
  local default = "conform_" .. os.date("%Y%m%d_%H%M") .. ".clb"
  local filepath = choose_save_path(default,
    "CLB Project (*.clb)\0*.clb\0All files\0*.*\0")
  if not filepath then return end
  if not filepath:match("%.clb$") then filepath = filepath .. ".clb" end
  CLB.last_dir = filepath:match("^(.*)[/\\]") or CLB.last_dir
  save_clb_project(filepath)
  save_prefs()
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

  -- Parse all selected files via OTIO Bridge
  local all_parsed = {}
  local errors = {}
  for _, fp in ipairs(filepaths) do
    local parsed, err = OTIO.parse(fp, { default_fps = CLB.fps })
    if parsed then
      all_parsed[#all_parsed + 1] = { parsed = parsed, path = fp }
      if parsed._warning then
        console_msg("Warning [" .. (fp:match("([^/\\]+)$") or fp) .. "]: " .. parsed._warning)
      end
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
      CLB.loaded_file   = #filepaths == 1 and filepaths[1] or nil
      CLB.loaded_format = all_parsed[1].parsed.format
      CLB.parsed_data   = all_parsed[1].parsed
      build_rows_from_parsed(all_parsed[1].parsed, all_parsed[1].path)
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
    -- First load
    CLB.loaded_file   = #filepaths == 1 and filepaths[1] or nil
    CLB.loaded_format = all_parsed[1].parsed.format
    CLB.parsed_data   = all_parsed[1].parsed
    build_rows_from_parsed(all_parsed[1].parsed, all_parsed[1].path)
    for i = 2, #all_parsed do
      append_rows_from_parsed(all_parsed[i].parsed, all_parsed[i].path)
    end
  end

  -- Apply track suffixes if multiple sources loaded
  _apply_track_suffixes()
  _rebuild_track_filters()
  CLB.cached_rows = nil

  if #all_parsed > 1 then
    console_msg(string.format("Loaded %d files (%d total events)", #all_parsed, #ROWS))
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
    "Open XML Files (FCP7 / Resolve)",
    "XML files\0*.xml\0All files\0*.*\0",
    "*.xml")
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
  return fmt  -- pass through any unknown formats unchanged
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

local function generate_items()
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
    local expanded_name = EDL.expand_template(CLB.track_name_format, tokens)
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

  -- Create or find tracks by expanded name
  local track_map = {}  -- expanded_name -> MediaTrack*

  for _, name in ipairs(track_names_order) do
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

    track_map[name] = found
  end

  -- Create items
  local created = 0
  for _, row in ipairs(visible_rows) do
    local track_name = row_to_trackname[row.__guid]
    local tr = track_map[track_name]
    if not tr then tr = track_map[track_names_order[1]] end
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
    string.format("Generated %d empty items on %d track(s).", created, #track_names_order),
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
    rows_to_process = get_view_rows() or ROWS  -- Only visible/filtered events
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

  -- Collect unique track names (based on expanded template)
  local track_names_set = {}
  local track_names_order = {}
  local row_to_trackname = {}  -- row.__guid -> expanded track name

  for _, row in ipairs(matched_rows) do
    local tokens = build_row_tokens(row)
    local expanded_name = EDL.expand_template(CLB.track_name_format, tokens)
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
    "Conform %d matched events?\n\n" ..
    "• %d single matches (1 take each)\n" ..
    "• %d multiple matches (multiple takes)\n\n" ..
    "Tracks: %s\n" ..
    "FPS: %s%s\n\n" ..
    "Audio files will be inserted at timeline positions.",
    #matched_rows, found_count, multi_count,
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

  -- Create items
  local created = 0
  local takes_created = 0

  for _, row in ipairs(matched_rows) do
    local track_name = row_to_trackname[row.__guid]
    local tr = track_map[track_name]
    if not tr then tr = track_map[track_names_order[1]] end
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
      created, takes_created, #track_names_order),
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

  -- Build duplicate key: reel + src TC + rec TC + clip_name (track excluded)
  local seen = {}
  local keep = {}
  local removed = 0

  for _, row in ipairs(ROWS) do
    local key = table.concat({
      row.reel or "",
      row.src_tc_in or "",
      row.src_tc_out or "",
      row.rec_tc_in or "",
      row.rec_tc_out or "",
      row.clip_name or "",
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
      "Reel + Src TC In/Out + Rec TC In/Out + Clip Name\n\n" ..
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
  _rebuild_reel_filters()
  _rebuild_group_filters()
  undo_snapshot()
  CLB.cached_rows = nil

  console_msg(string.format("Removed %d duplicates (%d remaining)", removed, #ROWS))
  reaper.ShowMessageBox(
    string.format("Removed %d duplicate event(s).\n%d events remaining.", removed, #ROWS),
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

  -- Collect groups with events
  local groups = {}   -- { group_name = { events } }
  local group_order = {}
  for _, row in ipairs(ROWS) do
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
  -- Row 1 (scrollable if window is narrow)
  -- +14 always reserves horizontal scrollbar space so buttons are never clipped
  local row1_height = scale(28) + 14
  local flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
  if reaper.ImGui_BeginChild(ctx, "##toolbar_row1", 0, row1_height, 0, flags) then
    -- Project Save / Open
    if reaper.ImGui_Button(ctx, "Save...", scale(65), scale(24)) then
      save_clb_project_dialog()
    end
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_BeginTooltip(ctx)
      reaper.ImGui_Text(ctx, "Save current session as a .clb project file")
      reaper.ImGui_Text(ctx, "(preserves EDL events, groups, audio matches, settings)")
      reaper.ImGui_EndTooltip(ctx)
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

    reaper.ImGui_Text(ctx, "|")
    reaper.ImGui_SameLine(ctx)

    -- Load buttons
    if reaper.ImGui_Button(ctx, "Load EDL...", scale(90), scale(24)) then
    load_edl_file()
  end
  reaper.ImGui_SameLine(ctx)

  if reaper.ImGui_Button(ctx, "Load XML...", scale(90), scale(24)) then
    load_xml_file()
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
  local chg_s, new_s = reaper.ImGui_InputText(ctx, "##clb_search", CLB.search_text)
  if chg_s then
    CLB.search_text = new_s
    CLB.cached_rows = nil
    sel_clear()
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
    reaper.ImGui_Text(ctx, "Remove duplicate events (matching Reel + Src TC + Rec TC + Clip Name)")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Consolidate by Group button
  if reaper.ImGui_Button(ctx, "Consolidate", scale(90), scale(24)) then
    consolidate_by_group()
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Consolidate tracks by group (bin-pack + renumber)")
    reaper.ImGui_EndTooltip(ctx)
  end
  reaper.ImGui_SameLine(ctx)

  -- Export EDL button
  if reaper.ImGui_Button(ctx, "Export EDL", scale(90), scale(24)) then
    export_edl()
  end
  reaper.ImGui_SameLine(ctx)

  -- Separator
  reaper.ImGui_Text(ctx, "|")
  reaper.ImGui_SameLine(ctx)

  -- Track name format (at end, rarely modified)
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
    reaper.ImGui_Text(ctx, "Tokens: ${track} ${reel} ${clip} ${event}")
    reaper.ImGui_Text(ctx, "        ${format} ${title} ${edit_type}")
    reaper.ImGui_Text(ctx, "Items will be grouped by the expanded track name")
    reaper.ImGui_EndTooltip(ctx)
  end
  end
  reaper.ImGui_EndChild(ctx)  -- End toolbar_row2
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
      local chg, new_buf = reaper.ImGui_InputText(ctx, "##rename_input", CLB.rename_filter.buf,
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
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Hide All##clb_reel_none") then
    for _, rf in ipairs(CLB.reel_filters) do rf.visible = false end
    CLB.cached_rows = nil
  end

  -- Reel checkboxes (vertical list)
  for i, rf in ipairs(CLB.reel_filters) do
    local display_name = rf.name ~= "" and rf.name or "(empty)"
    local label = string.format("%s (%d)##clb_reel_%d", display_name, rf.count, i)
    local changed, new_val = reaper.ImGui_Checkbox(ctx, label, rf.visible)
    if changed then
      rf.visible = new_val
      CLB.cached_rows = nil
    end
    -- Right-click context menu
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Right-click for options")
      if reaper.ImGui_IsMouseClicked(ctx, 1) then
        CLB.context_filter = { type = "reel", idx = i, name = rf.name }
        reaper.ImGui_OpenPopup(ctx, "Reel Filter Context##clb_reel_ctx")
      end
    end
  end

  -- Reel filter context menu
  if reaper.ImGui_BeginPopup(ctx, "Reel Filter Context##clb_reel_ctx") then
    if CLB.context_filter and CLB.context_filter.type == "reel" then
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
    reaper.ImGui_TextDisabled(ctx, "Click 'Load EDL...' or 'Load XML...' to open a timeline file (CMX3600 EDL, FCP7 XML, Resolve XML).")
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
    reaper.ImGui_TableSetupColumn(ctx, HEADER_LABELS[col] or "",
      reaper.ImGui_TableColumnFlags_WidthFixed(), w)
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

  -- Disable clipper for this frame if we need to scroll to a row
  local use_clipper = list_clipper and row_count > 100 and not scroll_target_idx
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
      if i == scroll_target_idx then
        reaper.ImGui_SetScrollHereY(ctx, 0.5)
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
            local old_val = get_cell_text(row, col)
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
          local display = (text ~= "" and text or " ") .. "##" .. row.__guid .. "_" .. col

          reaper.ImGui_Selectable(ctx, display, selected)

          -- Click handling
          if reaper.ImGui_IsItemClicked(ctx, 0) then
            local shift, cmd = _mods()
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
          end

          -- Double-click to edit
          if reaper.ImGui_IsItemHovered(ctx) and
             reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and
             EDITABLE_COLS[col] then
            EDIT = {
              row_idx = i,
              col_id = col,
              buf = text,
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

  -- Row context menu (Assign Group)
  if CLB._open_row_ctx then
    reaper.ImGui_OpenPopup(ctx, "Row Context##clb_row_ctx")
    CLB._open_row_ctx = false
  end

  if reaper.ImGui_BeginPopup(ctx, "Row Context##clb_row_ctx") then
    if CLB.row_context then
      reaper.ImGui_Text(ctx, "Assign Group:")
      reaper.ImGui_Separator(ctx)
      for _, gf in ipairs(CLB.group_filters) do
        if gf.name ~= "" then
          local is_current = (CLB.row_context.row.group == gf.name)
          if reaper.ImGui_MenuItem(ctx, gf.name, nil, is_current) then
            local sel_rows = get_selected_rows()
            if #sel_rows == 0 then sel_rows = { CLB.row_context.row } end
            for _, r in ipairs(sel_rows) do
              r.group = gf.name
            end
            _rebuild_group_filters()
            CLB.cached_rows = nil
            undo_snapshot()
          end
        end
      end
      reaper.ImGui_Separator(ctx)
      if reaper.ImGui_MenuItem(ctx, "(Unassign)") then
        local sel_rows = get_selected_rows()
        if #sel_rows == 0 then sel_rows = { CLB.row_context.row } end
        for _, r in ipairs(sel_rows) do
          r.group = ""
        end
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
  -- Header line: Events count, Cols button for column editor
  local view_rows = get_view_rows()
  local event_count = #view_rows
  local total_count = #ROWS

  if total_count > 0 then
    if event_count ~= total_count then
      reaper.ImGui_Text(ctx, string.format("EDL Events: %d / %d", event_count, total_count))
    else
      reaper.ImGui_Text(ctx, string.format("EDL Events: %d", event_count))
    end
  else
    reaper.ImGui_TextDisabled(ctx, "No EDL loaded")
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
        COL.GROUP
      }
      for i = 1, COL_COUNT do EDL_COL_VISIBILITY[i] = true end
      EDL_COL_VISIBILITY[COL.GROUP] = false
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
  local LABEL_W = scale(55)
  local RULER_H = scale(16)
  local TRACK_H = scale(18)
  local PAD_V   = scale(2)
  local panel_h = scale(TL_PANEL_H)
  local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)

  -- 3. BeginChild: fixed height, no scrollbars
  local wf = reaper.ImGui_WindowFlags_NoScrollbar()
           | reaper.ImGui_WindowFlags_NoScrollWithMouse()
  if not reaper.ImGui_BeginChild(ctx, "##clb_tl", avail_w, panel_h, 0, wf) then
    reaper.ImGui_EndChild(ctx)
    return
  end

  -- 4. InvisibleButton = interaction target for the canvas (reserve bottom 16px for scrollbar)
  local cw, ch = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_InvisibleButton(ctx, "##tl_cvs", cw, ch - scale(16))
  local is_hovered = reaper.ImGui_IsItemHovered(ctx)
  local is_active  = reaper.ImGui_IsItemActive(ctx)

  -- 5. Canvas bounds from InvisibleButton
  local cx0, cy0 = reaper.ImGui_GetItemRectMin(ctx)
  local cx1, cy1 = reaper.ImGui_GetItemRectMax(ctx)
  local ea_x0 = cx0 + LABEL_W           -- event area left edge
  local ea_w  = math.max(1, cx1 - ea_x0)

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

  -- Center timeline on row selected from the list
  if CLB.tl_center_on_guid then
    for _, rd in ipairs(row_data) do
      if rd.row.__guid == CLB.tl_center_on_guid then
        local center_t = (rd.t_in + rd.t_out) * 0.5 - tc_min
        CLB.tl_scroll = math.max(0, math.min(max_scroll, center_t - vis_sec * 0.5))
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
  reaper.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx1, cy1, 0x1A1A1AFF)
  reaper.ImGui_DrawList_AddRectFilled(dl, cx0, cy0, cx0 + LABEL_W, cy1, 0x252525FF)

  -- 9. TC ruler
  local ry0 = cy0
  local ry1 = cy0 + RULER_H
  reaper.ImGui_DrawList_AddRectFilled(dl, ea_x0, ry0, cx1, ry1, 0x2A2A2AFF)

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
  reaper.ImGui_DrawList_AddLine(dl, cx0, ry1, cx1, ry1, 0x444444FF, 1.0)

  -- 10. Track row backgrounds + labels
  for ti, tname in ipairs(track_order) do
    local ey0 = ry1 + (ti - 1) * TRACK_H
    local ey1 = ey0 + TRACK_H
    if ey1 > cy1 then break end
    local bg = (ti % 2 == 0) and 0x222222FF or 0x1E1E1EFF
    reaper.ImGui_DrawList_AddRectFilled(dl, ea_x0, ey0, cx1, ey1, bg)
    reaper.ImGui_DrawList_AddText(dl, cx0 + scale(3), ey0 + scale(3), 0xCCCCCCFF,
      tname ~= "" and tname or "?")
    reaper.ImGui_DrawList_AddLine(dl, cx0, ey1, cx1, ey1, 0x333333FF, 1.0)
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

  for _, rd in ipairs(row_data) do
    local row = rd.row
    local ti  = track_index[row.track or ""] or 1
    local ey0 = ry1 + (ti - 1) * TRACK_H + PAD_V
    local ey1 = ry1 +  ti      * TRACK_H - PAD_V
    if ey1 > cy1 then goto next_block end      -- below panel bottom

    local px0 = s2px(rd.t_in)
    local px1 = s2px(rd.t_out)
    if px1 < ea_x0 or px0 > cx1 then goto next_block end  -- off canvas

    local dx0 = math.max(px0, ea_x0)
    local dx1 = math.min(px1, cx1)
    if dx1 < dx0 + 1 then dx1 = dx0 + 1 end   -- minimum 1px

    local selected = sel_has_row(row.__guid)
    local col_fill = selected
      and track_color(row.track or "", ti, 0xFF)   -- selected: full-brightness color
      or  0x3A3A3ABB                                -- unselected: neutral dark gray
    local col_edge = selected and 0xFFFFFFEE or 0x00000044
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
        local txt_col = selected and 0xFFFFFFEE or 0xCCCCCC99
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

  -- 14. Click → select + scroll-to-row in table
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

  -- 15. Scroll wheel → zoom (anchored to cursor position)
  if is_hovered then
    local ok_w, scroll_y = pcall(reaper.ImGui_GetMouseWheel, ctx)
    if ok_w and scroll_y and scroll_y ~= 0 then
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

  -- 16. Drag → pan  (IsItemActive + GetMouseDelta, same pattern as draw_splitter)
  if is_active then
    local delta_x = reaper.ImGui_GetMouseDelta(ctx)
    if delta_x and delta_x ~= 0 then
      CLB.tl_scroll = math.max(0, math.min(max_scroll,
        CLB.tl_scroll - delta_x / CLB.tl_zoom))
    end
    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
  end

  -- 17. Horizontal scrollbar at bottom of panel
  if max_scroll > 0 then
    reaper.ImGui_SetNextItemWidth(ctx, -1)
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
    reaper.ImGui_TableSetupColumn(ctx, AUDIO_HEADER_LABELS[col] or "",
      reaper.ImGui_TableColumnFlags_WidthFixed(), w)
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
  if not CLB.loading_state then return false end

  local state = CLB.loading_state
  local progress = state.total > 0 and (state.current / state.total) or 0

  reaper.ImGui_Text(ctx, string.format("Loading audio files... %d / %d", state.current, state.total))
  reaper.ImGui_ProgressBar(ctx, progress, -1, 0)

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
  local sidebar_w = max_text_w + 40  -- checkbox + padding

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
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "None##clb_reel_none") then
        for _, rf in ipairs(CLB.reel_filters) do rf.visible = false end
        CLB.cached_rows = nil
      end

      reaper.ImGui_Separator(ctx)

      -- Reel checkboxes (vertical list, scrollable)
      local list_h = reel_section_h - header_h - 4
      if list_h < 50 then list_h = 50 end
      if reaper.ImGui_BeginChild(ctx, "##clb_reel_list", 0, list_h) then
      for i, rf in ipairs(CLB.reel_filters) do
        local display_name = rf.name ~= "" and rf.name or "(empty)"
        local label = string.format("%s (%d)##clb_reel_%d", display_name, rf.count, i)
        local changed, new_val = reaper.ImGui_Checkbox(ctx, label, rf.visible)
        if changed then
          rf.visible = new_val
          CLB.cached_rows = nil
        end
        -- Right-click context menu
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, "Right-click for options")
          if reaper.ImGui_IsMouseClicked(ctx, 1) then
            CLB.context_filter = { type = "reel", idx = i, name = rf.name }
            reaper.ImGui_OpenPopup(ctx, "Reel Filter Context##clb_reel_ctx")
          end
        end
      end

      -- Reel filter context menu
      local open_reel_rename, open_reel_delete, open_reel_batch = false, false, false
      if reaper.ImGui_BeginPopup(ctx, "Reel Filter Context##clb_reel_ctx") then
        if CLB.context_filter and CLB.context_filter.type == "reel" then
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
        CLB.add_group = { buf = "", focused = false }
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
          local chg, new_buf = reaper.ImGui_InputText(ctx, "##add_group_input", CLB.add_group.buf,
            reaper.ImGui_InputTextFlags_EnterReturnsTrue())
          if chg then CLB.add_group.buf = new_buf end

          if not CLB.add_group.focused then
            reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
            CLB.add_group.focused = true
          end

          local apply = chg
          if reaper.ImGui_Button(ctx, "OK", scale(60), 0) then apply = true end
          reaper.ImGui_SameLine(ctx)
          if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
            CLB.add_group = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
          end

          if apply and CLB.add_group then
            local name = CLB.add_group.buf
            if name ~= "" then
              local exists = false
              for _, gf in ipairs(CLB.group_filters) do
                if gf.name == name then exists = true; break end
              end
              if not exists then
                CLB.group_filters[#CLB.group_filters + 1] = {
                  name = name, count = 0, visible = true, tracks = {}
                }
              end
            end
            CLB.add_group = nil
            reaper.ImGui_CloseCurrentPopup(ctx)
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
            local chg, new_buf = reaper.ImGui_InputText(ctx, "##rename_group_input", CLB.rename_filter.buf,
              reaper.ImGui_InputTextFlags_EnterReturnsTrue())
            if chg then CLB.rename_filter.buf = new_buf end

            if not CLB.rename_filter.focused then
              reaper.ImGui_SetKeyboardFocusHere(ctx, -1)
              CLB.rename_filter.focused = true
            end

            local apply = chg
            if reaper.ImGui_Button(ctx, "OK", scale(60), 0) then apply = true end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Cancel", scale(60), 0) then
              CLB.rename_filter = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
            end

            if apply and CLB.rename_filter then
              local old_name = CLB.rename_filter.old_name
              local new_name = CLB.rename_filter.buf
              if new_name ~= "" and new_name ~= old_name then
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
              end
              CLB.rename_filter = nil
              reaper.ImGui_CloseCurrentPopup(ctx)
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
-- Draw: Main Content Area (split view support)
---------------------------------------------------------------------------
local function draw_main_content()
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

  -- Check if audio panel should be shown
  if CLB.show_audio_panel and #CLB.audio_files > 0 then
    -- Split view mode
    local splitter_h = 6
    local header_h = reaper.ImGui_GetTextLineHeightWithSpacing(ctx) + 4

    -- Calculate heights (subtract timeline panel from available space)
    local content_h = avail_h - splitter_h - header_h - tl_h
    local edl_h = content_h * CLB.split_ratio
    local audio_h = content_h - edl_h

    -- Upper section: EDL panel header + optional timeline + reel sidebar + EDL table
    draw_edl_panel_header()
    if CLB.show_timeline and #ROWS > 0 then draw_timeline_panel() end
    draw_reel_filter_sidebar(edl_h)
    draw_table(edl_h)

    -- Splitter (draggable, full width)
    draw_splitter()

    -- Audio panel header (full width)
    draw_audio_panel_header()

    -- Audio files table (full width)
    draw_audio_table(audio_h)
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
-- Main loop
---------------------------------------------------------------------------
local function loop()
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
-- load_prefs() may have restored a saved path; if empty or invalid, auto-detect.
if not OTIO.python or OTIO.python == "" then
  OTIO.python = OTIO.detect_python()
  save_prefs()
end

ctx = reaper.ImGui_CreateContext(SCRIPT_NAME)
if reaper.ImGui_CreateListClipper then
  list_clipper = reaper.ImGui_CreateListClipper(ctx)
end

console_msg("Conform List Browser v" .. VERSION .. " started")
console_msg("OTIO Bridge v" .. (OTIO.VERSION or "?") .. " | Python: " .. OTIO.python)
console_msg("EDL Parser v" .. (EDL.VERSION or "?"))

reaper.defer(loop)
