--[[
@description Item List Browser
@version 250130.1240
@author hsuanice
@about
  A project-wide media browser that shows ALL items in the project with full
  BWF/iXML metadata columns — features that REAPER's built-in Media Bay and
  Media Explorer cannot provide.

  Based on Item List Editor, with these additions:
    • Loads all project items on startup (not just selected)
    • Filter system: Only Selected, Track filter, Text search
    • Bidirectional Selection Link with REAPER arrange view
    • Follow Selection: auto-scroll arrange to clicked item
    • Move to View: double-click to jump to item position

  Shows a spreadsheet-style table of all project items with
  sort-relevant fields:
    • Track Index / Track Name
    • Take Name
    • Item Note
    • Source File
    • Sample Rate / Bit Depth / File Type
    • Metadata Track Name (resolved by Interleave, Wave Agent–style)
    • Channel Number (recorder channel, TRK#)
    • Interleave (1..N from REAPER take channel mode: Mono-of-N)
    • Item Start / End / Length (toggle display format)

  Features:
    • Inline editing of Track Name, Take Name, and Item Note
    • Excel-like selection model (click, Shift rectangle, Cmd/Ctrl multi-select)
    • Copy and Paste with spill/fill rules, one undo per operation
    • Drag-reorderable columns; Copy/Export follows on-screen order
    • Export or Copy as TSV/CSV
    • Summary popup: item count, total span, total length, position range
    • Option to hide muted items (rows are filtered, not removed)
    • Progressive loading for large selections (1000+ items)
    • Excel-like multi-level sorting (click headers or use Advanced Sort dialog)

  Time display modes:
    • m:s (minutes:seconds), Timecode, Beats, or Custom pattern
    • Custom pattern tokens:
        h, hh   – hours (unpadded / two-digit)
        m, mm   – minutes (0–59)
        s, ss   – seconds (0–59)
        S…      – fractional seconds, digits = precision (e.g. SSS = milliseconds)
      Examples:
        hh:mm:ss   → 01:23:45
        h:mm       → 1:23
        mm:ss.SSS  → 83:07.250

  Requires: ReaImGui (install via ReaPack)
  Reference: Script: zaibuyidao_Display Total Length Of Selected Items.lua


@changelog
  v250130.1240
  - Fix: Follow Selection now uses native API only (no SWS dependency)
    • Horizontal scroll via GetSet_ArrangeView2 (centers item in arrange view)
    • Vertical scroll via action 40913 (scrolls track into view)
    • Removed _S&M_SCROLL_ITEM dependency
  - Fix: Clicking rows in list no longer causes unwanted table auto-scroll
    • sync_list_selection_to_reaper() now updates REAPER selection hash immediately
    • Prevents sync_reaper_selection_to_list() from detecting false change after cooldown
  - Fix: Unified GUID API to native GetSetMediaItemInfo_String (removed SWS BR_GetMediaItemGUID)
  - Change: Follow Selection now defaults to ON (ILB.follow = true)

  v260130.1220
  - Fix: Removed auto-refresh polling that caused infinite reload loop
    • smart_refresh() no longer polls has_project_changed() every 100ms
    • Refresh now only triggered by: boot, Refresh Now button, edit/paste/delete, Clear Cache
    • Eliminates continuous "Phase 1 / Phase 2 / Fully completed" cycle
  - Fix: All Chinese comments replaced with English (no CJK characters in script)
  - Fix: Added follow_selection preference restore in load_prefs()

  v260129.1920
  - Initial release: Item List Browser (based on Item List Editor)
    • Shows ALL project items by default (not just selected)
    • Filter system: Only Selected, Track filter, Text search, Show/hide muted
    • Bidirectional Selection Link: click row → select in REAPER, select in REAPER → highlight in list
    • Follow Selection: toggle to auto-scroll REAPER arrange view to clicked item
    • Move to View: double-click any non-editable cell to jump to item position
    • All 34 metadata columns from ILE (including BWF/iXML fields)
    • Full ILE feature set: inline editing, clipboard, sort, presets, export
    • Shared metadata cache with ILE for cross-script acceleration

  v251210.2210 (2024-12-10)
  - Feature: Persistent Debug Mode with UI toggle
    • Debug Mode setting now persists across sessions via ExtState
    • Toggle via Options menu → Debug Mode (shows ✓ when enabled)
    • Controls both ILE console output and Cache Library debug logging
    • When enabled, shows: ILE initialization messages, cache behavior (HIT/MISS/STORE)
    • Setting automatically restored when reopening script
  - UX: Cleaner console output by default
    • Initialization messages ("[ILB] Loaded Metadata Cache library", "[ILB] Cache initialized")
      now only shown in Debug Mode
    • Reduces console clutter during normal usage
    • Enable Debug Mode when troubleshooting performance or cache issues

  v251209.1954 (2024-12-09)
  - Performance: Migrated to shared Metadata Cache library (hsuanice_Metadata Cache.lua v251209.1954)
    • Dramatically faster metadata loading through shared cache system
    • Cache now shared with Rename Active Take and future scripts
    • Cache stored as "Metadata.cache" in project directory (renamed from "ItemListEditor.cache")
    • Automatic cache invalidation when items are modified (hash-based detection)
    • Full cross-script cache acceleration - metadata loaded by Item List Editor can be instantly reused by Rename
    • Removed internal cache system (~450 lines) in favor of shared 9-method library API
    • All cache operations now use CACHE_LIB.* methods (init, lookup, store, flush, invalidate_items, clear)
  - Architecture: Cleaner code with standardized cache interface
  - Backward compatible: Existing workflows unchanged
  - Note: Old "ItemListEditor.cache" files will be ignored; new "Metadata.cache" will be created

  v251128.0110
  - Enhancement: Auto-fit content width on preset change
    • Preset dropdown automatically fits column widths when switching presets
    • Preset Editor "Apply" button automatically fits column widths
    • Preset Editor "Save & Apply" button automatically fits column widths
    • Eliminates need to manually click "Fit Content Widths" after changing presets
    • Ensures optimal column sizing for each preset's column configuration

  v251128.0100
  - Feature: User-configurable docking toggle in Options menu
    • Added "Allow Docking" option in Options menu (default: disabled)
    • Docking disabled by default for stability (prevents crashes)
    • Users can enable docking if needed, with warning about potential instability
    • Setting persists across sessions via ExtState
    • Requires script restart for changes to take effect
    • Warning dialog appears when toggling to inform about stability implications

  v251127.2315
  - Fix: Disable docking to prevent ImGui crashes
    • Added WindowFlags_NoDocking to prevent window from being docked
    • Eliminates all dock/undock related crashes and context invalidation issues
    • Window remains as floating window only (cannot be dragged into docker)
    • Simplifies code by removing need for complex dock state handling
    • Note: Context validation and recreation code kept as safety net

  v251127.2300
  - Fix: ImGui context validation and stale flag cleanup
    • Added context validation before every ImGui call (ValidatePtr check)
    • Automatic context recreation if context becomes invalid during dock/undock
    • Stale "running" flag detection and cleanup on startup
    • Uses test context creation to verify if previous instance really exists
    • Prevents false "already running" warnings after crashes
    • Clear running flag on fatal errors to avoid lockout

  v251127.2245
  - Fix: Prevent duplicate loop calls during dock/undock transitions
    • Added frame-time tracking to prevent multiple loop() calls within same frame
    • Fixes "ImGui_End: Calling End() too many times!" when undocking window
    • Uses time_precise() to detect and skip duplicate frame calls
    • Ensures proper Begin/End pairing even during dock state transitions

  v251127.2230
  - Fix: Prevent multiple instances causing ImGui errors
    • Added instance detection to prevent running multiple copies simultaneously
    • Shows warning dialog if script is already running
    • Prevents "ImGui_End: Calling End() too many times!" error from multiple instances
    • Automatic cleanup of instance flag on exit (via atexit and manual cleanup)
    • Removed incorrect pcall protection (ImGui requires Begin/End pairing regardless)

  v251127.2200
  - Fix: Crash when docking/undocking window (reverted - incorrect approach)

  v251127.2150
  - Feature: Responsive window and table layout
    • GUI window is now freely resizable by user
    • Table automatically adjusts to fill available space
    • Table height dynamically calculated using GetCursorPosY() for precise toolbar height
    • Minimal bottom padding (8px) maximizes usable table space
    • Both width and height scale with window size changes
    • No wasted space at bottom of window
    • Improves usability on different screen sizes and resolutions

  v251127.2100
  - Feature: Font size adjustment with full UI scaling
    • Added Font Size submenu in Options menu
    • Adjustable from 50% to 300% (9 preset sizes)
    • Current size marked with checkmark (✓)
    • Preference persisted via ExtState (survives REAPER restart)
    • Font changes apply immediately within same session
    • Auto-scales ALL UI elements proportionally:
      - Button widths and heights (24 buttons scaled)
      - Table column widths (31 columns scaled)
      - Input field widths and heights (7 fields scaled)
      - Table height and padding/spacing
    • Recommended range: 75% - 200% for optimal experience
    • Makes text easier to read for users with vision difficulties

  v251127.1630
  - Feature: Added Cut shortcut (Cmd/Ctrl+X)
    • Works like Excel/Sheets: copies selection to clipboard, then deletes content
    • Live view only (matches Paste and Delete behavior)
    • Respects writable columns (Track Name, Take Name, Item Note)
    • Creates single undo point for entire cut operation
    • Completes clipboard workflow: Copy (Cmd+C), Cut (Cmd+X), Paste (Cmd+V)

  v251114.2130
  - Feature: Added Length column (total: 30→31 columns)
    • New column 31 displays item length in current time format
    • Positioned after Start/End columns in default order
    • Supports all time display modes (m:s, Timecode, Beats, Custom pattern)
    • Read-only column (calculated from D_LENGTH)
    • Sortable by length (numeric sort)
    • Column width: 80px (customizable via COL_WIDTH[31])
    • Included in Copy/Export operations (TSV/CSV)
  - Technical: Updated all column-related loops and arrays from 30 to 31 columns
    • BeginTable column count: 30 → 31
    • DEFAULT_COL_ORDER includes column 31
    • COL_VISIBILITY supports all 31 columns
    • Preset Editor handles all 31 columns
    • Reset to Default includes Length column
    • Show Widths button displays all 31 columns

  v251101.2230
  - UX: Separated Clear Cache options into dedicated "Options" button
    • New standalone "Options" button added next to "Clear Cache"
    • Moved all debug/diagnostic options from Clear Cache right-click menu to Options button
    • Options menu includes: Console Output toggle, Debug Mode toggle, Cache Test Report
    • Clearer UI organization - users can find diagnostic options more easily
    • Clear Cache button now only shows cache statistics on hover

  v251101.0350
  - UX: Swapped "Fit Content Widths" and "Reset Widths" button behavior
    • Primary button (left-click): "Fit Content Widths" - auto-adjusts columns based on content
    • Right-click menu: "Reset to Default Widths" - restores original default sizes
    • Updated tooltips to reflect new behavior

  v251101.0340
  - Enhancement: Advanced Sort dialog improvements
    • New dropdown + "+" button to add sort columns directly in dialog
    • No longer need to Shift+Click headers first - can manage everything in dialog
    • Dropdown shows all available columns in current column order
    • Prevents duplicate columns (checks if already in sort list)
  - Enhancement: Auto-width adjustment for sort indicators
    • Columns automatically expand when sort indicators are added (immediate effect)
    • Single sort: +20px for " ▲" or " ▼"
    • Multi-level sort: +50px for " [N] ▲" or " [N] ▼"
    • Ensures sort level numbers are always visible
    • Width adjustment happens immediately on sort (no need to click Reset Widths)
  - Feature: Fit Content Width functionality
    • Right-click "Reset Widths" button for width options menu
    • "Reset to Default Widths" - restores original default sizes
    • "Fit Content Width" - auto-adjusts columns based on actual content
    • Skips fixed-content columns (#, TrkID, Chan#, Int#, Mute, Color, Start, End, UMID, UMID PT, Time Reference, Source Start/End)
    • Preserves default width values (won't be modified by Fit Content)
  - Technical: Pre-calculates sort levels before column setup for accurate width calculation
  - Technical: Separated DEFAULT_COL_WIDTH (immutable defaults) from COL_WIDTH (current widths)

  v251031.1700
  - Feature: Excel-like sorting functionality
    • Click column header: single-column sort (toggle ascending/descending)
    • Shift+Click column header: add column to multi-level sort
    • Sort indicators in headers: ▲ (ascending) / ▼ (descending)
    • Multi-level sort shows priority numbers: [1], [2], [3], etc.
    • New "Advanced Sort..." button opens sort configuration dialog
    • Advanced Sort dialog allows:
      - View and manage all sort levels
      - Toggle sort direction for each level
      - Reorder sort levels (move up/down buttons: ▲▼)
      - Remove individual sort levels
      - Clear all sorting
    • Supports sorting on all 30 columns (including metadata fields)
    • Smart type handling: numbers sort numerically, text sorts alphabetically
    • Stable sort preserves original order when values are equal
  - Technical: Replaced TableHeadersRow with manual header rendering to support click detection
  - Technical: Direct UTF-8 characters used instead of \u escape sequences (Lua 5.1 compatibility)

  v251027_2130
  - Feature: Console output can now be toggled from Clear Cache menu (persists via ExtState)
    • Replaces direct console writes with a guarded wrapper; scanning progress still forces output
    • Adds preference storage and restore for console state
  - UX: Scan Project Items tooltip now shows current cached item count (and live scan progress)
    • Tooltip updates while scanning to display batch progress alongside instructions

  v251026_0054
  - Fix: Restored “#” header text in preset editor drag handles
    • Column labels now render correctly even for symbols when drag-reordering
    • Drag source preview maintains readable names after the change

  v251026_0040
  - UX: Column preset editor now supports drag-and-drop reordering
    • Drag any column label to reposition instantly; drop below the list to append
    • Up/Down buttons remain for incremental moves when fine tuning

  v251026_0037
  - Fix: Column presets now preserve both column order and visibility state
    • ExtState payload now uses `ord=...;vis=...`, writing the visible-order list alongside flags
    • Loading restores COL_ORDER and COL_VISIBILITY in saved sequence so drag or editor changes persist
    • Legacy payloads remain readable; when no order is present, the previous fallback order is used

  v251025_2313
  - Fix: Display issue with multiline item notes
    • Problem: Item Note column showed only first line with "..." suffix
    • Root cause: Original design truncated at first newline for table view
    • Fix: Now shows full multiline content with auto-wrap in Selectable
    • Ensures all note content visible without editing
    • Edit mode unchanged - still shows full content in InputTextMultiline
    
  v251025.2245
  - UI: Toolbar reorganization for cleaner layout
    • Removed standalone "Cache Test" button from toolbar
    • Moved "Scan Project Items" and "Clear Cache" buttons to first row (after Custom Pattern input)
    • Second row now contains only: Refresh Now, Reset Widths, Copy (TSV), Save.tsv, Save.csv, Summary
    • Added confirmation dialog to "Clear Cache" (shows cached item count before clearing)
    • Cache Test functionality moved to right-click context menu on "Clear Cache" button
    • Right-click "Clear Cache" now shows menu with two options:
      - Toggle Debug Mode (with checkmark when active)
      - Cache Test Report... (generates diagnostic report to console)
    • Cleaner UI: cache management buttons grouped on first row, export buttons on second row

  - Fix: TSV export trailing newline issue (requires List Table v0.2.7+)
    • Problem: Multiline fields (Description) had closing quote on new line instead of after last character
    • Root cause: BWF Description field includes trailing newline (per BWF spec)
    • Impact: Google Sheets and other tools showed extra blank line in quoted fields
    • Fix: Strip trailing newlines from field content before quoting in build_table_text()
    • Example fixed:
      Before: "...sTRK7=LINE\n"  (quote on new line)
      After:  "...sTRK7=LINE"    (quote immediately after last character)
    • Internal newlines are preserved, only trailing newlines removed
    • Applies to all fields (TSV and CSV), ensures proper RFC 4180 compliance

  v251025.2147
  - Fix: Critical cache serialization bug - multiline Description fields corrupting cache
    • Problem: Description field (BWF metadata) contains newlines, breaking cache file format
    • Root cause: Cache serialization didn't escape newlines/tabs in metadata fields
    • Impact: Cache file became corrupt after first save, metadata lost on reload
    • Fix: Added proper escaping for all special characters in cache serialize/deserialize
      - Newlines (\n, \r\n, \r) → literal "\n"
      - Tabs (\t) → literal "\t"
      - Pipes (|) → literal "\|"
      - Backslashes (\) → literal "\\"
    • Deserializer now correctly handles escaped pipes and restores special characters
    • IMPORTANT: Delete old cache files and rescan to rebuild with correct format

  - Enhancement: TSV export now preserves multiline content (requires List Table v0.2.7)
    • TSV fields containing newlines/tabs are now quoted (RFC 4180 style)
    • Description field exports with actual newlines preserved (not escaped to \n)
    • Compatible with Excel, Google Sheets, and standard TSV parsers
    • Backwards compatible - simple fields remain unquoted
    • CSV export behavior unchanged (already used quotes)

  v251025.1640
  - Feature: Cache diagnostic testing tool
    • New "Cache Test" button generates comprehensive diagnostic report
    • Report includes:
      - Cache file location and existence verification
      - Cache statistics: item count, version, hit/miss rate
      - Current selection information
      - Sample metadata verification for selected item
      - Recommended test procedures (6 tests: A-F)
    • Report output to console with message box notification
    • Useful for troubleshooting cache issues and verifying metadata integrity
    • Tests cover: cold start, single item, cache hit, large selection, startup speed, project scan

  - Verified: Complete cache system working correctly
    • Tested with real production project: 7696 items cached in 68.31 seconds
    • All 21 fields (GUID + mod_time + 19 metadata) correctly stored and retrieved
    • Sample verification confirmed: BWF metadata (UMID, dates, times) and iXML (PROJECT, SCENE, TAKE, TAPE) all present
    • Cache hit rate tracking operational
    • Project-folder-based cache storage stable

  v251025_1540
  - Fix: Critical bug in cache_store() - BWF/iXML metadata not being cached
    • Root cause: cache_store() was only storing 4 basic fields, not all 19 metadata fields
    • This caused metadata to appear empty on second load (after cache hit)
    • Fixed: cache_store() now correctly stores all 19 fields (4 basic + 15 BWF/iXML)
    • IMPORTANT: Delete old cache files to rebuild with complete metadata
    • Old cache format: GUID|mod_time|file|int|name|ch (6 fields)
    • New cache format: GUID|mod_time|file|int|name|ch|umid|umid_pt|... (21 fields total)

  v251025_1530
  - Feature: "Scan Project Items" button replaces "Show Widths"
    • New button scans ALL items in project (not just selected) and builds complete metadata cache
    • Shows confirmation dialog with item count before starting
    • Progress indicator shows percentage during scan
    • Cancellable with ESC key - partial cache is saved
    • Batch processing (20 items/frame) keeps UI responsive
    • Console logs progress every 100 items and final timing
    • Useful for pre-building cache for large projects before editing sessions
    • Cached data persists in project folder as ItemListEditor.cache

  v251025_1500
  - Enhancement: Custom time format headers now display "(Custom)" instead of full pattern
    • Start/End column headers show "Start (Custom)" and "End (Custom)" when custom time format is selected
    • Updated both Item List Editor fallback and Time Format library (hsuanice_Time Format.lua)
    • Improves readability - full pattern still used for actual time formatting

  - Enhancement: Complete metadata caching to eliminate repeated file reads
    • Cache now stores ALL metadata fields (4 basic + 15 BWF/iXML = 19 fields total)
    • Cache version bumped to 2.0 (old caches automatically invalidated)
    • Significantly improves performance when re-opening projects with many items
    • Cache fields: file_name, interleave, meta_trk_name, channel_num, UMID, UMID_PT, origination_date, origination_time, originator, originator_ref, time_reference, description, PROJECT, SCENE, TAKE, TAPE, UBITS, FRAMERATE, SPEED
    • Old cache format (v1.0, 6 fields) automatically upgraded on first load

  - Feature: Added Source Start/Source End columns (total: 28→30 columns)
    • New columns 29-30 display source file position in timecode format
    • Calculated from BWF TimeReference (sample count since midnight) + take offset
    • Shows actual position in original source file, accounting for:
      - TimeReference from BWF metadata
      - Take start offset (D_STARTOFFS)
      - Item length and playback rate
    • Always displayed in Timecode format for consistency
    • Useful for dialogue editing and conforming to match original recordings
    • Read-only columns (calculated, not editable)
    • Column width: 100px (customizable via COL_WIDTH[29] and COL_WIDTH[30])

  - Technical: Updated all column-related loops and arrays from 28 to 30 columns
    • BeginTable column count: 28 → 30
    • DEFAULT_COL_ORDER includes columns 29-30
    • COL_VISIBILITY supports all 30 columns
    • Preset Editor handles all 30 columns
    • Show Widths button displays all 30 columns

  v251025_1420
  - Fix: Incomplete metadata after cache location change
    • Fixed bug where BWF/iXML metadata fields (15 columns) were not loaded when cache hit occurred
    • Root cause: Early return in load_metadata_for_row() skipped metadata parsing when basic fields were cached
    • Solution: Always parse full metadata via META.collect_item_fields() regardless of cache status
    • Cache now only stores 4 basic fields (file_name, interleave, meta_trk_name, channel_num)
    • BWF/iXML fields (UMID, origination_date, PROJECT, SCENE, etc.) are always loaded fresh from files
    • Added diagnostic logging to get_cache_path() for troubleshooting cache location issues

  v251025_1400
  - Enhancement: Improved column width management with user customization
    • Changed to SizingFixedFit mode - all columns manually resizable by dragging dividers
    • Resizing columns now extends table width (columns don't shrink behind)
    • Added TableSetupScrollFreeze(0, 1) - header row now properly frozen during vertical scrolling
    • Added ScrollY flag with proper outer_size for vertical scrolling support
    • New "Reset Widths" button restores all columns to default sizes
    • New "Show Widths" button displays default column widths in console
    • Right-click context menu on table area provides quick access to:
      - Reset Column Widths
      - Show Column Widths (Console)
      - Edit Columns (opens Preset Editor)
      - Toggle Show/Hide Muted Items
    • COL_WIDTH table controls default width for each column (editable in script around line 1200)
    • All default column widths now use explicit pixel values (150-200px for text fields)

  - Fix: Resolved COL_WIDTH nil error
    • Moved COL_WIDTH and RESET_COLUMN_WIDTHS declarations to global scope (before first use)
    • Fixed "attempt to index a nil value (global 'COL_WIDTH')" error

  - Fix: Reset Width now works correctly
    • Added TableFlags_NoSavedSettings to prevent ImGui from persisting column widths
    • Uses incrementing counter to generate truly unique table IDs on each reset
    • Column widths now properly reset to COL_WIDTH defaults when button clicked

  - Enhancement: Cache now stored in project folder
    • Cache file saved as "ItemListEditor.cache" in project directory (same folder as .RPP file)
    • Multiple project versions in same folder now share the same cache (e.g., YYYY-MM-DD--ProjectName-v1.RPP, YYYY-MM-DD--ProjectName-v2.RPP)
    • Unsaved projects still use fallback cache in REAPER resource path
    • Improves workflow for projects with multiple editing versions in same folder

  v251025_0015
  - Feature: Added 15 new metadata columns from BWF/iXML (total: 13→28 columns)
    • BWF metadata columns (14-21):
      - UMID: SMPTE Unique Material Identifier (64-char hex)
      - UMID (PT): Pro Tools format UMID
      - Origination Date: Recording date (YYYY-MM-DD)
      - Origination Time: Recording time (HH:MM:SS)
      - Originator: Person/organization who created the file
      - Originator Ref: Unique identifier reference
      - Time Reference: Sample count since midnight
      - Description: Free text description
    • iXML metadata columns (22-28):
      - PROJECT: Production project name
      - SCENE: Scene identifier
      - TAKE: Take number/identifier
      - TAPE: Tape/card identifier
      - UBITS: User bits data
      - FRAMERATE: Timecode frame rate
      - SPEED: Recording speed
    • All metadata columns are read-only, populated from embedded file metadata
    • Metadata sourced from hsuanice_Metadata Read.lua v0.3.0 library
    • Smart width configuration: fixed widths for structured data (UMID, dates, times), auto-stretch for text fields
    • Preset Editor updated to support all 28 columns
    • Default column order groups: Basic fields (1-13) → UMID (14-15) → BWF (16-21) → iXML (22-28)

  v251025_0010
  - Enhancement: Smart column width management
    • Fixed-width columns for fields with predictable sizes: #(50px), TrkID(60px), Chan#(60px), Interleave(80px), Mute(50px), Color(80px), Start(140px), End(140px)
    • Auto-stretch columns for variable content: Track Name, Take Name, Item Note, Source File, Meta Trk Name
    • Changed table sizing mode to SizingStretchProp to support mixed fixed/stretch columns
    • New "Column Info" button shows current width configuration
    • All columns remain manually resizable by dragging column dividers

  v251024_2350
  - Fix: Column visibility (show/hide) now properly saved and restored in presets
    • Preset storage format updated to include visibility flags (format: "1:1,2:1,3:0,...")
    • When saving/loading presets, hidden columns are now remembered correctly
    • Preset Editor now shows all 13 columns with correct visibility state
    • Backward compatible with old preset format (columns in list are visible, rest hidden)
    • New global COL_VISIBILITY table tracks visibility state for Preset Editor

  v251024_2345
  - Enhancement: Preset Editor improvements
    • Added "Reset to Default" button to restore default column order (all visible)
    • Disabled manual column drag-reorder in table (TableFlags_Reorderable removed)
    • All column management now done through Preset Editor for consistency
  - Next planned features:
    • Table sorting (click column header to sort)
    • Filter functionality (search/filter rows)

  v251024_2120
  - Feature: Column Preset Editor with visual column arrangement
    • New "Edit..." button opens Preset Editor dialog
    • Show/hide columns with checkboxes
    • Reorder columns with ↑/↓ buttons
    • "Apply" button applies changes to current session (unsaved)
    • "Save & Apply" button saves to preset and applies
    • Works with existing preset system (select/save/delete)
    • Column order/visibility now managed through presets, not drag-and-drop
    • Copy/Export always follow the preset-defined order
  - Removed: Broken auto-detection logic for drag-reorder
    • ImGui doesn't expose display order after user drags columns
    • New preset editor provides reliable column management

  v251024_2115
  - Attempted: Auto-detect column display order after drag-reorder
    • Used TableNextColumn() + TableGetColumnIndex() to detect order
    • Failed: Only detected 10/13 columns, detection was unreliable
    • Rolled back this approach in v251024_2120

  v251024_2110
  - Attempted: Column order persistence with auto-detection
    • Tried to save column order to ExtState when changed
    • Failed: Could not reliably detect display order from ImGui

  v251024_2105
  - Fix: Clipboard paste now fully functional for all scenarios
    • Updated Library v0.2.6: Complete rewrite of copy/paste logic
    • COPY behavior:
      - Single column: pure text format (no tabs)
      - Multiple columns: TSV format (tab-separated)
    • PASTE behavior:
      - Content with tabs: parsed as TSV (multi-column)
      - Content without tabs: each line as single cell (preserves all characters)
    • Fixed issues:
      ✓ External text with commas: "Come on, come on" → single cell (not split)
      ✓ External text with spaces: "MEDIA_START:123 MEDIA_DURATION:456" → preserved
      ✓ ILE internal single-column copy: no extra empty column on paste
      ✓ ILE internal multi-column copy: correctly pastes all columns
      ✓ Google Sheets paste: works correctly with/without empty cells
    • Removed problematic CSV parsing mode entirely (was incorrectly splitting on commas)
    • Both internal (ILE→ILE) and external (text→ILE) paste work correctly

  v251024_2100
  - Partial fix: Removed CSV parsing mode (Library v0.2.5)
    • Fixed external paste but broke internal single-column copy

  v251024_2055
  - Attempted fix: Added trailing tabs to single-column copy (Library v0.2.4)
    • Incomplete solution - caused unwanted empty column on paste

  v251024_2050
  - Fix: Complete solution for "Missing End()" and ImGui context errors
    • Skip ALL ImGui content drawing on first frame (not just keyboard checks)
    • Fixed code structure: all content now properly inside FRAME_COUNT > 1 guard
    • Prevents draw_toolbar(), draw_table(), and all ImGui calls before context is stable
    • Resolves "expected a valid ImGui_Context*" errors when opening with items selected

  v251024_2045
  - Revert: Progressive loading threshold back to 100 items (from 500)
    • User feedback: 500 threshold felt slower in practice
    • 100 items provides better balance between immediate response and smooth loading
  - Fix: Removed spurious cache directory warning
    • RecursiveCreateDirectory returns 0 when directory already exists (not an error)
    • Removed confusing warning message - actual save/load errors will still be reported

  v251024_2040
  - Fix: ImGui context validation errors when opening with items selected
    • Added frame counter to skip keyboard checks on first frame
    • Fixed cache directory creation (REAPER API requires trailing slash)
    • Added pcall protection to esc_pressed() function
    • Prevents "expected a valid ImGui_Context*" errors during initialization

  v251024_2030
  - Fix: "Show muted items" toggle now works with instant response
    • Table rendering now correctly uses get_view_rows() instead of raw ROWS
    • Toggle immediately filters/shows muted items without refresh delay
    • No unnecessary data rescanning - pure UI filtering for instant feedback

  v251024_2016
  - Fix: Undo/Redo functionality now works correctly
    • Changed undo flags from -1 (no undo) to 4|1 (UNDO_STATE_ITEMS | UNDO_STATE_TRACKCFG)
    • Paste, Delete, and Inline editing operations now create proper undo points
    • Undo/Redo immediately refreshes display - no need to manually refresh
    • Added window focus check to ensure shortcuts are captured by ILE
  - Fix: Instant visual feedback after edits (combines cache speed with live responsiveness)
    • NEW: refresh_rows_by_guids() - instantly reloads only edited rows
    • Paste/Delete/Edit operations now invalidate cache AND immediately refresh affected rows
    • No more "cached old data" after edits - changes appear instantly
    • Preserves cache performance for unedited rows (best of both worlds)
  - Fix: ImGui context errors when opening with items selected
    • Moved smart_refresh() after ImGui_Begin() to ensure context is initialized
    • Added "if visible then" guard to only execute window content when visible
    • Proper Begin/End pairing maintained (End always called regardless of visibility)
    • Fixed "Missing End()" errors that prevented script from starting
  - Fix: mark_dirty() definition order corrected (again)
    • Moved mark_dirty() to very top of code to prevent any "nil value" errors
    • Now defined before ALL functions that use it (delete, paste, edit, undo, redo)
  - Debug: Added context creation logging
    • Console shows context address and type on creation
    • Helps diagnose any future ImGui initialization issues
  - Performance: Tested with 190 items - loads in 0.16s with full metadata

  v251024_0115
  - Fix: Crash when editing cells (Track Name, Take Name, Item Note)
    • Root cause: mark_dirty() was defined after _commit_if_changed() but called inside it
    • Fixed function definition order - mark_dirty() now defined before first use
    • Prevents "attempt to call a nil value (global 'mark_dirty')" error
    • Prevents "Missing EndTable()" ImGui error that crashed the script

  v251024_0110
  - NEW: Cache debug mode for testing cache invalidation
    • Right-click "Clear Cache" button to toggle debug mode
    • Console shows detailed cache behavior: HIT, MISS (new), MISS (changed), STORE
    • Displays item details (position, take name, source file) for each cache operation
    • "Invalidated" count shown in red when items detected as changed
  - Improvement: More sensitive cache invalidation
    • Enhanced source filename hashing (character-by-character)
    • Detects: render/glue output, new files, source replacement, position/length changes
    • Hash now includes full filename content (not just length)
  - UX: Enhanced cache tooltip
    • Shows "Invalidated: N items" in red when changes detected
    • Displays cache path and debug mode status
    • Right-click hint for debug mode

  v251024_0100
  - NEW: Project-based metadata cache system (like waveform peaks cache)
    • Caches expensive metadata parsing (file_name, interleave, meta_trk_name, channel_num) per project
    • Cache files stored in REAPER/ItemListEditor_cache/ directory
    • First scan builds full cache, subsequent opens only scan new/modified items
    • Automatic cache invalidation when items change (position, length, source file)
    • Cache persists across sessions - dramatically faster reopening of same project
  - Performance: Massive speedup for repeat visits to same project
    • Example: 2428 items - First time: 14-33s → Next time: 2-3s (90% faster!)
    • Cache hit rate displayed on "Clear Cache" button hover
    • Cache version system allows automatic invalidation when script logic updates
  - UX: New "Clear Cache" button in toolbar
    • Hover shows cache statistics (cached items, hit rate)
    • Use when troubleshooting or after major project changes
    • Cache automatically rebuilds on next refresh
  - Technical: Smart cache validation
    • Per-item modification hash (position + length + take count + source)
    • Project-level modification time tracking
    • Unsaved projects use temporary cache (per session)
    • Cache serialization uses pipe-delimited format with escaping

  v251024_0030
  - Fix: Startup crash when opening ILE with items already selected
    • Moved initial load to first frame of main loop (after ImGui context ready)
    • Progressive load now triggers via dirty flag instead of direct call at startup
    • Added context validation checks to prevent invalid context errors
  - Fix: Column order sync now works correctly in real-time
    • rebuild_display_mapping() now called every frame to detect column reordering
    • Copy/Paste/Export immediately reflect user's visual column arrangement
    • No longer uses stale column order after dragging columns
  - Fix: Duplicate refresh triggers eliminated
    • update_selection_cache() now properly updates LAST_SEL_HASH
    • Selection hash generation logic unified across all code paths
    • Prevents redundant scans when selection hasn't actually changed
  - Cleanup: Removed duplicate code and improved comments
    • Removed redundant row_index_map building in copy operation
    • Removed debug dump_cols() calls from production code
    • English comments for new performance-critical code sections

  v251023_2246
  - Performance: Major optimization for large selections (1000+ items)
    • Smart refresh with throttling: only refreshes when truly needed (max 10 fps)
    • Selection change detection: lightweight GUID hashing instead of full scan
    • Progressive loading: streams data in batches to keep UI responsive
    • Two-phase lazy loading:
      Phase 1 - Basic fields (track, take, position) load first (~2-3s for 2000 items)
      Phase 2 - Metadata (source file, interleave, channel) loads in background
    • Adaptive batch sizing: automatically adjusts based on system performance
    • Result: 2000+ items now usable in seconds instead of freezing for 30+ seconds
  - Fix: Progressive loading no longer triggers infinite restart loop
    • Corrected GUID hash generation consistency between phases
    • Added proper cache updates on completion to prevent re-triggers
  - UX: Real-time progress display in toolbar
    • Phase 1: "Loading: 1250/2428 (51%)"
    • Phase 2: "Items: 2428 | Loading metadata: 65%"
    • Console logs show detailed progress and timing
  - Behavior: All editing operations now mark dirty flag for smart refresh
    • Inline edits, paste, delete, undo/redo trigger refresh only when needed
    • "Refresh Now" button forces immediate full refresh (bypasses progressive)

  v0.9.4
  - Presets UX: The dropdown now applies a preset immediately on selection (no “Recall” button).
    • Added a width limit for the preview field and a height-capped, scrollable list.
    • “(none)” cleanly resets to the default column order.
  - Table rebuild: The table ID is now keyed by the active preset, ensuring a fresh
    rebuild so headers/columns reflect the saved order right away after switching.
  - Fix: Removed a rare “double header” render path when switching presets; the header
    is drawn once and the display→logical mapping is rebuilt predictably.
  - Cleanup: Deleted legacy/overlapping preset helpers; unified on named presets
    stored as an index plus `col_preset.<name>` and `col_preset_active`. Includes
    defensive normalization for incomplete orders (fills IDs 1..13).
  - Status: The toolbar status text now reflects the active preset or shows “No preset”.
  v0.9.2
    - New: Named Column Presets with dropdown + explicit Recall / Save as… / Delete.
      • Save with a user-defined name; multiple presets stored in ExtState.
      • Recall applies the saved logical column order to the current session.
      • Delete removes the selected preset from both index and storage.
    - Behavior: Removed auto-save. ExtState only updates on user actions.
    - UI: Preset controls live to the right of "Summary" (compact toolbar group).

  v0.9.1
    - New (UI): Added "Save preset" button and status text to the right of "Summary".
      • One-click saves the current on-screen column order (visual → logical) to ExtState.
      • Status shows "(preset …)" when saved, or "(columns not saved)" otherwise.
    - Fix: Resolved duplicate preset helper definitions (old name-based API vs new order-based API)
      that caused "Save preset" to no-op or steal focus to header.
      • Unified to: save_col_preset(order, note), load_col_preset().
      • Toolbar button now calls the unified API; removed name-based variants.
    - Behavior: Copy / Paste / Save (TSV/CSV) continue to follow the live on-screen order.
      Preset only persists your preferred order across sessions (stored at ExtState: col_preset).
    - Internal: Guarded header→ID mapping and preset normalization (fills missing 1..13 IDs).
      Optional auto-save hook kept out by default; can be enabled after TableHeadersRow().
  v0.9.0
    - add column presets
  v0.8.4
    - Refactor: Moved the paste dispatcher into the List Table library.
      • New LT.apply_paste(rows, dst, tbl, COL_ORDER, COL_POS, apply_cell_cb)
        routes all cases (single fill, single-cell spill, block spill, fill-down,
        many-to-many) and honors visual column order and visible-row filtering.
      • Editor now only provides the visible rows, destination list, column
        mapping, and a small apply_cell() that writes Track/Take/Item Note.
    - Behavior unchanged by design; tests cover single/multi cell, spill/fill,
      Show-muted filtering, and column reordering.
  v0.8.3.1
    - Clean refactor: Editor’s Copy/Save (TSV/CSV) now calls LT.build_table_text()
      directly instead of a local stub.
    - Behavior unchanged: exports follow visual column order, reflect current
      time mode/pattern, and include only visible rows.

  v0.8.3
    - Refactor: Moved TSV/CSV utilities into the List Table library.
      • Removed local implementations of:
          - parse_clipboard_table() (clipboard → 2D table)
          - flatten_tsv_to_list() (2D → flat list)
          - src_shape_dims() (source height/width detection)
          - build_dst_by_anchor_and_shape() / build_dst_spill_writable()
      • Editor now delegates to LT.* equivalents, keeping all copy/paste
        and export logic consistent across scripts.
    - Editor side: only minimal glue remains (get_cell_text, COL_ORDER/COL_POS).
    - Behavior unchanged:
      • Copy/Export still follow on-screen column order.
      • Paste still supports single-value fill, multi-cell spill, fill-down,
        and Excel-style block mapping.
    - Cleanup: consolidated file I/O helpers (choose_save_path, write_text_file, timestamp)
      to prepare for future library migration.

  v0.8.2.1
    - Fix: Inline editing no longer renders two overlapping tables.
      • Removed duplicate draw_table() call in the main loop.
      • Double-click editing now stays stable in a single table (no “jumping” between lists).

  v0.8.2
    - Paste & Delete refactor to use LT destination lists:
      • Switched Editor to consume LT.build_dst_list_from_selection() results
        and access rows via rows[d.row_index] (no more d.row), fixing single-cell
        spill cases and keeping behavior aligned with visible rows and visual
        column order. (Library: hsuanice_List Table v0.1.0)
      • Paste now consistently targets only visible rows (get_view_rows → LT.filter_rows).
      • Message box when pasting with no selection now uses English text.
    - Summary popup:
      • Unified modal (“Summary”) with a single read-only multiline box and Copy button.
      • Summary body is built via LT.compute_summary() and follows the active time mode.
    - UI minor:
      • Removed use of ImGui_ImVec2 constructor; use plain width/height arguments for
        InputTextMultiline to improve compatibility across ReaImGui builds.
    - Cleanup:
      • Deleted remaining local variants of row/dst helpers; Editor delegates to LT for
        row index map, selection rectangle, copy/export, and destination building.
  v0.8.1
    - Summary calculation now calls LT.compute_summary() from the List Table library.
      • Removed the local compute_summary() implementation in Editor.
  v0.8.0
    - Major refactor: split from "Monitor" into a standalone Item List Editor.
      • Removed BEFORE/AFTER snapshot capture, cross-script handshake, and all
        Reorder-related signal code (SIG_NS, poll_reorder_signal, req/ack keys).
      • UI now focuses purely on the live selection list.
    - Header/metadata cleanup:
      • Updated @about and changelog to remove snapshot references.
      • All Export/Copy actions now target only the live table view.
    - Code cleanup:
      • Removed unused TABLE_SOURCE branches ("before"/"after").
      • Deleted cross-script constants and handlers.
      • Standardized get_view_rows() calls (no stray src arg).
    - No change to core Editor features:
      • Live table of selected items with drag-reorderable columns.
      • Excel-like selection, copy/paste, spill/fill rules.
      • Inline editing of Track Name, Take Name, Item Note.
      • Export to TSV/CSV follows on-screen column order.
      • Summary popup remains available.

  v0.7.2
    - New: “Show muted items” toggle in the toolbar.
      • When off, rows with Mute=on are hidden from the table.
      • Copy and Save (TSV/CSV) export only the currently visible rows, in the exact on-screen column order.
      • Toggling clears any active inline edit and selection to avoid acting on hidden rows.
    - Paste/spill/fill now operate strictly on visible rows (no accidental writes to hidden muted items).
    - Mute column remains visible (we hide rows, not the column).

  v0.7.1.1
    - Fix: Copy (Cmd/Ctrl+C) and Shift-rectangle selection could error with
      “attempt to index a nil value (global 'COL_POS')” on first use.
      • Root cause: multiple local re-declarations of COL_ORDER/COL_POS and
        functions defined before their locals existed.
      • Change: single forward declaration of COL_ORDER/COL_POS; removed duplicate
        local re-declarations; added nil-safe fallbacks where COL_POS is read.
    - Result: Copy/Shift-select work reliably; outputs still follow the on-screen
      column order. Paste behavior unchanged.

  v0.7.1
    - Copy & Export (TSV/CSV) now follow the on-screen column order for all views (Live/BEFORE/AFTER).
      • Headers use the current labels (e.g., Start/End reflect the active time display mode).
      • Data rows output in the exact visual order (including after you drag-reorder columns).
      • Safe fallback: if no mapping is available, exports use the classic fixed order.
    - (If not yet applied) Shift-rectangle selection can be switched to use visual column positions too,
      so selections align with your dragged column order.

  v0.7.0
    - Columns: Moved Start/End to appear right after Track Name by default (before Take Name/Item Note).
    - Column Reordering: You can now drag column headers to reorder them (ImGui TableFlags_Reorderable).
    - Selection/Copy/Paste respect the current visual column order:
      • Shift-rectangle selection expands by the visual positions, not fixed IDs.
      • Copy outputs a rectangle according to the on-screen order.
      • Paste destination ordering also follows the current on-screen order.
    - Logic IDs unchanged for safety (3=Track, 4=Take, 5=Item Note, 12=Start, 13=End), so editing/paste rules remain stable.

  v0.6.12.1
    - Paste: when the source contains multiple cells but the selection has fewer cells than the source,
      the paste now spills the entire source block from the top-left selected cell (anchor), Excel-style.
      • Spill targets only writable columns (3/4/5); overflow is truncated (no wrap).
      • Works together with 0.6.12 (single-cell spill), 0.6.11 (single-row fill-down), and 0.6.9 rules.
    - One undo per paste; Live view only; selection protection on undo/redo remains enabled.

  v0.6.12
    - Paste (spill): multi-cell sources now spill across writable columns as well.
      • When only one destination cell is selected, the paste expands from that cell
        in row-major order but only targets writable columns (3=Track, 4=Take, 5=Item Note).
      • The first writable column at or to the right of the anchor is used as the start;
        values beyond column 5 are truncated (no wrap), matching spreadsheet behavior.
      • Works together with v0.6.11 (fill-down for single-row sources) and v0.6.9 rules.
    - Live view only. Non-writable columns remain read-only (safe to select/copy, ignored on write).
    - One undo per paste; undo/redo keeps your item selection (v0.6.8.1).

  v0.6.11
    - Paste: when the source is a single row spanning multiple columns (e.g., Take Name + Item Note),
      pasting into a multi-row selection now “fills down” row-by-row, Excel-style.
      • Each destination row receives the source row’s values left-to-right.
      • No wrap: if a destination row has more selected columns than the source width, extras are left untouched.
      • Still supports: single value → fill all; multi → single cell spill (0.6.10); multi → multi row-major mapping (0.6.9).
    - Live view only; Track/Take/Item Note remain the only writable columns; others safely ignore writes.
    - One undo per paste; undo/redo keeps your item selection (0.6.8.1).

  v0.6.10
    - Paste: multi-cell sources now “spill” from a single target cell, Excel-style.
      • If the source has multiple values but only one destination cell is selected,
        the paste expands from that cell in row-major order, matching the source’s 2D shape.
      • Single value still fills all selected cells (across columns or non-contiguous ranges).
      • Multi→multi keeps row-major mapping and truncates when destination is smaller (no wrap).
    - Writable columns remain Track Name / Take Name / Item Note; other columns safely ignore writes.
    - One undo per paste; Live view only; selection protection on undo/redo remains in effect.

  v0.6.9
    - Paste behavior now matches spreadsheet intuition:
      • Single source value fills all selected cells.
      • Multiple source values map to selected cells in row-major order, truncating if destination is larger (no wrap).
      • Selection can be non-rectangular; shape does not need to match.
    - Writable columns remain Track Name / Take Name / Item Note; other columns accept paste but are ignored safely.
    - Live view only; Snapshots stay read-only. One undo per paste; table refreshes after paste.
    - If no cell is selected when pasting, a message box prompts you to select cells first.

  v0.6.8.1
    - Undo/Redo selection protection (always on):
      • When using table shortcuts (Cmd/Ctrl+Z, Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y),
        the current item selection is snapshotted by GUID and restored after Undo/Redo.
      • Works even if REAPER Preferences → Undo → “Include selection: item” is OFF.
      • Live view refreshes right after to stay in sync.

  v0.6.8
    - Shortcuts: Undo (Cmd/Ctrl+Z) and Redo (Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y).
    - All write operations already create undo points:
      • Inline edits (Track / Take / Item Note) — one undo per commit.
      • Paste (block) — one undo per paste.
      • Delete (clear selected cell text) — one undo per delete.
    - The table refreshes immediately after Undo/Redo to stay in sync.
    - Note: For predictable selection behavior during Undo/Redo, enable:
      “Preferences → General → Undo → Include selection: item”.

  v0.6.7
    - New: Delete clears text in the selected cells (Live view only).
      • Writable columns: Track Name, Take Name, Item Note.
      • Non-writable columns are ignored.
      • Works with single cell, Cmd/Ctrl multi-select, and Shift rectangular selection.
      • One Undo block; table refreshes after deletion.

  v0.6.6 — fix click anchor
    - Fix: Shift+click rectangular selection didn’t work after a plain click.
      • Root cause: the code set SEL.anchor and then immediately cleared it via sel_clear(),
        both in handle_cell_click() and in the first-time branch of sel_rect_apply().
      • Change: clear selected cells first, then set the anchor; and on first Shift action,
        keep the anchor (reset only SEL.cells).
    - Result: Single-click sets the anchor; Shift+click extends a rectangle from that anchor;
      Cmd/Ctrl+click toggles cells without touching the anchor.
    - No behavior changes to editing (double-click to edit), copy, or paste rules
      (paste still Live-only and only for Track/Take/Item Note).

  v0.6.5
    - Make First and Second columns selectable.

  v0.6.4
    - Excel-like selection & clipboard:
      • Click selects a cell; Shift+click selects a rectangular range; Cmd/Ctrl+click toggles noncontiguous cells.
      • Cmd/Ctrl+C copies the selection as TSV (tab/newline delimited).
      • Cmd/Ctrl+V pastes into the Live view: 1×1 fills the selection; shape-matched blocks paste 1:1.
    - Writable columns (Live only): Track Name, Take Name, Item Note.
      • Track names apply strictly by Track object (GUID) — never by text, so identically named tracks are unaffected.
      • Take names auto-create an empty take if missing; Item Notes write to P_NOTES.
    - Safety & UX: one Undo block per paste; auto-refresh pauses during edit/paste and resumes after; clear, predictable behavior.
    - Snapshots: copy allowed; paste is disabled by design.

  v0.6.3
    - Table layout: switched to fixed-width columns with horizontal scrolling (no more squeezing).
    - Set practical default widths for all columns; key edit fields (Track/Take/Item Note) stay readable.
    - Header tweak: “TrackIdx” → “TrkID”.
    - Wrapping: long text wraps inside its fixed-width cell; overflow is available via horizontal scroll.
    - Columns remain resizable by the user; widths can be fine-tuned interactively.

  v0.6.2
    - Editing UX: Fixed focus so double-click reliably enters inline edit and the input is immediately active with the text preselected.
    - Commit behavior: Leaving the cell (losing focus) now commits just like pressing Enter; Esc cancels. Only writes (and creates one Undo step) when the value actually changes.
    - Stability: While a cell is being edited we render only the InputText (no overlapping Selectable), avoiding focus flicker and ID conflicts.
    - Auto-refresh: Continues to refresh when not editing, pauses during edit, and resumes as soon as the edit ends (on Enter, blur, or Esc).

  v0.6.1
    - Fix: Resolved Dear ImGui ID conflicts in editable cells (Track Name, Take Name, Item Note)
      by using a row-level PushID keyed by item GUID plus per-cell "##trk"/"##take"/"##note" IDs.
    - Change: Entering edit mode no longer immediately collapses (auto-refresh is paused while editing).
    - Known issue: After double-click, the input field shows but sometimes doesn’t accept typing (focus isn’t captured). Addressed in 0.6.2 by giving the editor explicit focus and rendering it exclusively while active.
    - Known issue: With the guard `if AUTO and (not EDIT or not EDIT.col) then refresh_now() end`,
      auto-refresh may remain suspended in some setups. Temporary workaround:
      `if AUTO and not (EDIT and EDIT.col) then refresh_now() end`.

  v0.6.0
    - Inline editing (Excel-like) in the table:
      • Single-click selects a cell so you can copy/paste its text.
      • Double-click enters edit mode (InputText) with the current value preselected.
    - Editable columns: Track Name, Take Name, Item Note.
      • Track Name writes to the exact Track object (by GUID) — only that track is renamed,
        even if other tracks share the same name.
      • Take Name and Item Note write to the specific item/take of that row.
      • Edits are allowed even when the item has no active take; handled safely without touching BWF/iXML.
    - Commit & cancel behavior:
      • Enter / Tab / clicking outside commits the edit.
      • Esc cancels and restores the original value.
    - Safety & consistency:
      • Only writes (and creates one Undo step) when the value actually changes.
      • Trims leading/trailing whitespace (keeps interior spaces); applies a reasonable length limit.
      • After commit, the view refreshes so all rows tied to the same Track object update consistently.
    - No change to embedded metadata (BWF/iXML).
    - Exports (TSV/CSV) and BEFORE/AFTER snapshots reflect the edited values.

  v0.5.2
    - Parser: Updated parse_snapshot_tsv() to accept both "M" and "1" as muted values in TSV input,
      ensuring compatibility with exports from v0.5.1 and later (which use "M"/blank).

  v0.5.1
    - Export: Changed the Mute column in TSV/CSV exports to output "M" when muted and blank when unmuted (was previously 1/0).

  v0.5.0
    - NEW: Inserted "Item Note" column (between Take Name and Source File) across UI and TSV/CSV exports.

  v0.4.4.2
    - Fix: ESC on main window not working — removed a duplicate ImGui_CreateContext/ctx block that shadowed the real context; unified to a single context so esc_pressed() and the window share the same ctx.
    - Behavior: Summary ESC closes only the popup; when no popup is open, ESC closes the main window.

  v0.4.4
    - Feature: Handshake-based auto-capture.
      Listens for req_before/req_after and replies with ack_before/ack_after
      after taking snapshots internally. Backward-compatible with legacy capture_* keys.

  v0.4.3.1
    - Fix: Crash on startup (“attempt to call a nil value 'parse_snapshot_tsv'”).
      Forward-declared the parser and bound the later definition so polling can call it safely.

  v0.4.2
    - Fix: Restored per-frame polling of cross-script signals (poll_reorder_signal) in the main loop,
      so auto-capture from the Reorder script works again.

  v0.4.0 (2025-09-03)
    - New: Summary modal (button next to "Save .csv"). Shows item count, total span, total length, and position range.
      Text is selectable, with a one-click Copy, respects current time mode (m:s / TC / Beats / Custom).
    - New: Added Mute and Color columns (swatch + hex).
    - Fix: Removed duplicate table render in main loop (was drawing twice).
    - Fix: Added bootstrap at file end (conditional initial refresh + loop()) so the window launches correctly.

  v0.3.18 (2025-09-03)
    - New: Added "Mute" and "Color" columns (color swatch + hex).
    - New: Summary panel (counts, total duration span, total length sum, and position range),
      fully respecting the current time display mode (m:s / TC / Beats / Custom).

  v0.3.17 (2025-09-03)
    - Fix: When Auto-refresh is OFF, the script no longer performs an initial scan on launch.
      (Guarded the startup refresh; now only runs if AUTO is true.)
    - UX: Refresh Now resets the table view to Live before scanning.

  v0.3.16 (2025-09-03)
    - Fix: Auto-refresh preference now persists correctly. (Added AUTO to forward declarations and removed local shadowing in State (UI).)

  v0.3.15 (2025-09-03)
    - New: Added “Show BEFORE” and “Show AFTER” buttons in the snapshot section (inline with Copy/Save).
    - UX: “Refresh Now” resets the table view back to Live (from Before/After).

  v0.3.14
    - Restore: Added “Capture BEFORE” & “Capture AFTER” buttons to the toolbar.
    - Feature: Auto-refresh state is now persisted across sessions.

  v0.3.13 (2025-09-03)
    - Fix: Persisted time mode & custom pattern now restore correctly.
      (Forward-declared TIME_MODE/CUSTOM_PATTERN/FORMAT and removed local shadowing in State (UI).)

  v0.3.12 (2025-09-03)
    - Fix: Persist selection — time mode and custom pattern now saved on every change (Radio/Input) via ExtState.
    - UX: Window close button (X) now works. Begin() captures (visible, open); loop stops when open == false or ESC is pressed.

  v0.3.11 (2025-09-03)
    - Fix: Forward-declared TFLib and changed library load to assign instead of re-declare (removed 'local' before TFLib).
      This prevents load_prefs() from capturing a nil global TFLib and restores the saved mode on startup.

  v0.3.10 (2025-09-03)
    - Persistence: Remembers the selected time display mode (m:s / TC / Beats / Custom) and the custom pattern across runs via ExtState.
      Re-opening the script restores your last choice; if it was Custom, the previous pattern is applied automatically.

  v0.3.9 (2025-09-03)
    - UI: Moved "Refresh Now" and Copy/Save buttons to the next row by removing an extra ImGui_SameLine().
      No NewLine/Spacing added to maintain minimal vertical gap and a tighter layout.

  v0.3.8 (2025-09-03)
    - UI: Moved Custom pattern input inline to the right of the "Custom" mode selector.
    - UX: Added tooltip (ⓘ) explaining pattern tokens.

  v0.3.7 (2025-09-02)
    - New: Added "Custom" display mode. Users can type patterns like "hh:mm:ss", "h:mm", "mm:ss.SSS".
    - API: Integrated with hsuanice_Time Format v0.3.0 (MODE.CUSTOM + pattern support).
    - UI: Start/End headers now show the selected pattern, e.g. "Start (hh:mm:ss)".

  v0.3.6 (2025-09-02)
    - Feature: Replace "Seconds" with "Minutes:Seconds" (m:s) display and export.
    - Fix: Beats mode now formats correctly (no longer falls back to seconds).
    - UI: Start/End headers switch to "Start (m:s) / End (m:s)" when m:s mode is selected.

  v0.3.5 (2025-09-02)
    - Feature: Display mode expanded to three options — Seconds / Timecode / Beats.
    - Refactor: Adopt hsuanice_Time Format v0.2.0 (MODE + make_formatter + headers).
    - Exports (TSV/CSV) automatically follow the selected mode.

  v0.3.4 (2025-09-02)
    - Refactor: Adopt hsuanice_Time Format v0.2.0 (unified MODE + formatter/headers).
    - Feature: Display mode expanded to three options — Seconds / Timecode / Beats.
    - Exports (TSV/CSV) follow the current mode automatically.

  v0.3.3 (2025-09-02)
    - Fix: Resolve naming collision between TF() (REAPER flag helper) and TimeFormat table.
      Renamed the library alias to TFLib to prevent "attempt to call a table value" error.

  v0.3.2 (2025-09-02)
    - Refactor: Use hsuanice_Time Format library for Seconds/TC formatting (with fallback if library missing).

  v0.3.1 (2025-09-02)
    - Fix: Restored missing helpers from 0.2.x (selection scan, save dialogs, ImGui context, etc.)
      to resolve "attempt to call a nil value (global 'refresh_now')" and related issues.
    - Feature (from 0.3.0): Toolbar checkbox to toggle Start/End display:
      • Seconds (6 decimals) or
      • Timecode (uses project frame rate via format_timestr_pos mode=5).
    - Exports (TSV/CSV) honor the current display mode.

  v0.2.2 (2025-09-01)
    - UI: Show "Metadata Read vX.Y.Z" in the window title (computed before ImGui_Begin).
    - Cleanup: Optionally remove the toolbar version label to avoid duplication.
    - Behavior: Monitoring, refresh, and exports unchanged from 0.2.1.

  v0.2.1 (2025-09-01)
    - Fully delegate metadata resolution to the Library:
      • Use META.guess_interleave_index() + META.expand("${trk}") / "${chnum}"
        (no local interleave→name/chan logic). Sets __chan_index before expand.
      • Fix: removed a duplicate local 'idx' declaration; more nil-safety.
    - UI: keeps the Library version label; no visual/format changes.
    - Exports/Snapshots: unchanged from 0.2.0 (backward compatible).

  v0.2.0 (2025-09-01)
    - Switched to 'hsuanice Metadata Read' (>= 0.2.0) for all metadata:
      • Uses Library to read/normalize metadata (unwrap SECTION, iXML TRACK_LIST first;
        falls back to BWF Description sTRK#=Name for EdiLoad-split files).
      • Interleave is derived from REAPER take channel mode (Mono-of-N);
        Meta Track Name and Channel# are resolved from the Library fields.
      • Removed legacy in-file parsers; behavior for Wave Agent is unchanged,
        and EdiLoad-split is now robustly supported.
      • Minor safety/UX hardening (no functional change to table/snapshots/exports).

  v0.1.6
    - Metadata: Added fallback for EdiLoad-split mono files.
      • If IXML TRACK_LIST is missing, parse sTRK#=NAME from BWF/Description.
      • Resolves Meta Track Name and Channel# via existing Interleave pipeline.

  v0.1.5
    - UI: moved Snapshot BEFORE/AFTER section to appear directly under the top toolbar,
      before the live table (content unchanged).

  v0.1.4
    - Column rename: “Source File” (formerly “File Name”).
    - Source resolution now mirrors the Rename script’s $srcfile:
      active take → source → unwrap SECTION (handles nested) → real file path (with extension).
    - Metadata read (iXML/TRK) also uses the unwrapped source for better accuracy on poly/SECTION items.
    - Export headers updated to “Source File”; keeps EndTime from 0.1.3.
    - Cleanup/robustness: removed old src_path usage; safer guards for nil/non-PCM sources.
    - File name reliability: now resolves source file names (with extensions) even for SECTION/non-PCM sources via safe pcall wrapper.
    - New column: End (Start + Length). Also added EndTime to TSV/CSV exports.
    - Table: column count updated to 10; minor utils added (item_len), formatting helpers unchanged.

  v0.1.2
    - UI always renders content (removed 'visible' guard after Begin to avoid blank window in some docks/themes).
    - Table sizing: use -FLT_MIN width for stable full-width layout across ReaImGui builds.
    - Compatibility: safe ESC detection, tolerant handling when Begin returns only one value, save dialog fallback if JS_ReaScriptAPI is missing (auto-save to project folder with notice).

  v0.1.1
    - Compatibility hardening:
      • Avoided font Attach/PushFont when APIs are unavailable.
      • Added guards around keyboard APIs and window-‘open’ handling.
      • General nil-safety for selection scanning and sources.

  v0.1.0
    - Initial release:
      • Live monitor of selected items with columns: #, TrackIdx, Track Name, Take Name, File Name, Meta Track Name (interleave-resolved), Chan#, Interleave, Start.
      • Auto-refresh / manual Refresh Now.
      • Capture BEFORE / AFTER snapshots.
      • Export/Copy selection or snapshots as TSV/CSV.



]]


-- ===== Project-based Metadata Cache System =====
-- Cache metadata (file_name, interleave, meta_trk_name, channel_num) per project
-- to avoid re-scanning unchanged items on subsequent launches

---------------------------------------
-- Console output control
---------------------------------------
local EXT_NS = "hsuanice_ItemListBrowser"
local original_ShowConsoleMsg = reaper.ShowConsoleMsg
local console_pref = (reaper.GetExtState and reaper.GetExtState(EXT_NS, "console_output")) or ""
local CONSOLE = { enabled = (console_pref ~= "0") }

local function console_write(text, force)
  if text and (force or CONSOLE.enabled) then
    original_ShowConsoleMsg(text)
  end
end

local function console_force(text)
  console_write(text, true)
end

local function console_forcef(fmt, ...)
  console_force(string.format(fmt, ...))
end

reaper.ShowConsoleMsg = function(text)
  console_write(text, false)
end

---------------------------------------
local CACHE_VERSION = "2.0"  -- Bump this to invalidate all caches when metadata logic changes (v2.0: added BWF/iXML fields)

-- Get cache directory path
local function get_cache_dir()
  local resource_path = reaper.GetResourcePath()
  local cache_dir = resource_path .. "/ItemListEditor_cache"
  -- Ensure directory exists (note: need trailing slash for REAPER API)
  -- RecursiveCreateDirectory returns 0 if dir already exists or on error
  -- We'll just call it and not warn - if save/load fails, that will warn instead
  reaper.RecursiveCreateDirectory(cache_dir .. "/", 0)
  return cache_dir
end

-- Get current project identifier (path + filename hash)
local function get_project_cache_key()
  local proj, projfn = reaper.EnumProjects(-1, "")
  if not projfn or projfn == "" then
    -- Unsaved project: use temporary identifier
    return "unsaved_" .. tostring(proj)
  end

  -- Use project filename as key (sanitize for filesystem)
  local basename = projfn:match("([^/\\]+)$") or "unknown"
  basename = basename:gsub("[^%w%._%-]", "_")  -- Remove unsafe chars
  return basename
end

-- Get cache file path for current project
local function get_cache_path()
  local proj, projfn = reaper.EnumProjects(-1, "")

  if not projfn or projfn == "" then
    -- Unsaved project: fallback to REAPER resource path
    local cache_dir = get_cache_dir()
    local key = get_project_cache_key()
    local path = cache_dir .. "/" .. key .. ".cache"
    reaper.ShowConsoleMsg("[ILBCache] Path (unsaved): " .. path .. "\n")
    return path
  end

  -- Get project directory (folder containing the .RPP file)
  local proj_dir = projfn:match("^(.*[/\\])[^/\\]+$") or ""
  if proj_dir == "" then
    -- Fallback if can't extract directory
    local cache_dir = get_cache_dir()
    local key = get_project_cache_key()
    local path = cache_dir .. "/" .. key .. ".cache"
    reaper.ShowConsoleMsg("[ILBCache] Path (fallback): " .. path .. "\n")
    return path
  end

  -- Use fixed cache filename in project directory
  local path = proj_dir .. "ItemListEditor.cache"
  reaper.ShowConsoleMsg("[ILBCache] Path: " .. path .. "\n")
  reaper.ShowConsoleMsg("[ILBCache] Project dir: " .. proj_dir .. "\n")
  reaper.ShowConsoleMsg("[ILBCache] Project file: " .. projfn .. "\n")
  return path
end

-- Serialize cache data to string
local function serialize_cache(cache_data)
  local lines = {
    "CACHE_VERSION=" .. CACHE_VERSION,
    "PROJECT_MODIFIED=" .. tostring(cache_data.project_modified or 0),
    "ITEM_COUNT=" .. tostring(cache_data.item_count or 0),
    "CACHED_AT=" .. tostring(os.time()),
    "---DATA---"
  }

  for guid, meta in pairs(cache_data.items or {}) do
    -- Format: GUID|mod_time|file_name|interleave|meta_trk_name|channel_num|umid|umid_pt|origination_date|origination_time|originator|originator_ref|time_reference|description|project|scene|take_meta|tape|ubits|framerate|speed
    local parts = {
      guid,
      tostring(meta.mod_time or 0),
      meta.file_name or "",
      tostring(meta.interleave or 0),
      meta.meta_trk_name or "",
      tostring(meta.channel_num or 0),
      -- BWF/iXML metadata (15 fields)
      meta.umid or "",
      meta.umid_pt or "",
      meta.origination_date or "",
      meta.origination_time or "",
      meta.originator or "",
      meta.originator_ref or "",
      meta.time_reference or "",
      meta.description or "",
      meta.project or "",
      meta.scene or "",
      meta.take_meta or "",
      meta.tape or "",
      meta.ubits or "",
      meta.framerate or "",
      meta.speed or ""
    }
    -- Escape special characters in data (skip GUID and mod_time)
    for i = 3, #parts do
      parts[i] = parts[i]:gsub("\\", "\\\\")  -- Escape backslashes first
      parts[i] = parts[i]:gsub("|", "\\|")    -- Escape pipes
      parts[i] = parts[i]:gsub("\r\n", "\\n") -- Windows line endings
      parts[i] = parts[i]:gsub("\n", "\\n")   -- Unix line endings
      parts[i] = parts[i]:gsub("\r", "\\n")   -- Old Mac line endings
      parts[i] = parts[i]:gsub("\t", "\\t")   -- Tab characters
    end
    lines[#lines + 1] = table.concat(parts, "|")
  end

  return table.concat(lines, "\n")
end

-- Deserialize cache data from string
local function deserialize_cache(content)
  if not content or content == "" then return nil end

  local cache_data = { items = {} }
  local in_data = false

  for line in content:gmatch("([^\n]*)\n?") do
    if line == "---DATA---" then
      in_data = true
    elseif not in_data then
      local key, val = line:match("^([^=]+)=(.*)$")
      if key == "CACHE_VERSION" then
        if val ~= CACHE_VERSION then
          return nil  -- Version mismatch, invalidate cache
        end
      elseif key == "PROJECT_MODIFIED" then
        cache_data.project_modified = tonumber(val) or 0
      elseif key == "ITEM_COUNT" then
        cache_data.item_count = tonumber(val) or 0
      end
    else
      -- Parse data line: GUID|mod_time|file_name|interleave|meta_trk_name|channel_num|umid|umid_pt|origination_date|origination_time|originator|originator_ref|time_reference|description|project|scene|take_meta|tape|ubits|framerate|speed
      local parts = {}
      -- Split by unescaped pipes (not preceded by backslash)
      local pos = 1
      while pos <= #line do
        local pipe_pos = line:find("|", pos, true)
        if not pipe_pos then
          -- Last field
          local field = line:sub(pos)
          parts[#parts + 1] = field
          break
        end

        -- Check if pipe is escaped
        local before_pipe = pipe_pos - 1
        local num_backslashes = 0
        while before_pipe > 0 and line:sub(before_pipe, before_pipe) == "\\" do
          num_backslashes = num_backslashes + 1
          before_pipe = before_pipe - 1
        end

        -- If odd number of backslashes, the pipe is escaped
        if num_backslashes % 2 == 1 then
          -- Skip this pipe, continue searching
          pos = pipe_pos + 1
        else
          -- Unescaped pipe - this is a field separator
          local field = line:sub(pos, pipe_pos - 1)
          parts[#parts + 1] = field
          pos = pipe_pos + 1
        end
      end

      -- Unescape all special characters in fields
      for i = 1, #parts do
        parts[i] = parts[i]:gsub("\\t", "\t")    -- Unescape tabs
        parts[i] = parts[i]:gsub("\\n", "\n")    -- Unescape newlines
        parts[i] = parts[i]:gsub("\\|", "|")     -- Unescape pipes
        parts[i] = parts[i]:gsub("\\\\", "\\")   -- Unescape backslashes (must be last)
      end

      if #parts >= 6 then
        local guid = parts[1]
        cache_data.items[guid] = {
          mod_time = tonumber(parts[2]) or 0,
          file_name = parts[3] or "",
          interleave = tonumber(parts[4]) or 0,
          meta_trk_name = parts[5] or "",
          channel_num = tonumber(parts[6]) or 0,
          -- BWF/iXML metadata (15 fields) - handle both old and new cache formats
          umid = parts[7] or "",
          umid_pt = parts[8] or "",
          origination_date = parts[9] or "",
          origination_time = parts[10] or "",
          originator = parts[11] or "",
          originator_ref = parts[12] or "",
          time_reference = parts[13] or "",
          description = parts[14] or "",
          project = parts[15] or "",
          scene = parts[16] or "",
          take_meta = parts[17] or "",
          tape = parts[18] or "",
          ubits = parts[19] or "",
          framerate = parts[20] or "",
          speed = parts[21] or ""
        }
      end
    end
  end

  return cache_data
end

-- Load cache from disk
local function load_cache()
  local path = get_cache_path()
  local file = io.open(path, "r")
  if not file then return nil end

  local content = file:read("*all")
  file:close()

  local cache_data = deserialize_cache(content)
  if cache_data then
    reaper.ShowConsoleMsg(string.format("[ILBCache] Loaded cache: %d items\n",
      cache_data.item_count or 0))
  end
  return cache_data
end

-- Save cache to disk
local function save_cache(cache_data)
  local path = get_cache_path()
  local content = serialize_cache(cache_data)

  local file = io.open(path, "w")
  if not file then
    reaper.ShowConsoleMsg("[ILBCache] Warning: Failed to write cache file\n")
    return false
  end

  file:write(content)
  file:close()

  reaper.ShowConsoleMsg(string.format("[ILBCache] Saved cache: %d items\n",
    cache_data.item_count or 0))
  return true
end

-- Get project modification time (for cache invalidation)
local function get_project_mod_time()
  local proj, projfn = reaper.EnumProjects(-1, "")
  if not projfn or projfn == "" then return 0 end

  -- Try to get file modification time
  local file = io.open(projfn, "r")
  if not file then return 0 end
  file:close()

  -- Use file system stat if available, otherwise use current time
  -- Note: Lua doesn't have portable stat, so we use a heuristic
  return reaper.GetProjectTimeSignature2(proj) or 0  -- Use project change marker as proxy
end

-- Get item modification time (REAPER doesn't expose this, so we hash item properties)
local function get_item_mod_hash(item)
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then return 0 end

  -- Hash based on: position, length, take count, source filename
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local take_count = reaper.CountTakes(item)

  local tk = reaper.GetActiveTake(item)
  local src_hash = 0
  local src_fn = ""
  if tk then
    local src = reaper.GetMediaItemTake_Source(tk)
    if src then
      local _, fn = reaper.GetMediaSourceFileName(src, "")
      src_fn = fn or ""
      -- Use full filename hash (more sensitive to changes)
      for i = 1, #src_fn do
        src_hash = src_hash + string.byte(src_fn, i) * i
      end
    end
  end

  -- Simple hash: combine values (more sensitive to source file changes)
  return math.floor((pos * 1000000 + len * 10000 + take_count * 100 + src_hash) * 1000)
end

-- Debug: get item details for logging (when cache validation fails)
local function get_item_debug_info(item)
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then return "invalid item" end

  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local tk = reaper.GetActiveTake(item)
  local take_name = tk and (select(2, reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)) or "") or ""
  local src_fn = ""
  if tk then
    local src = reaper.GetMediaItemTake_Source(tk)
    if src then
      local _, fn = reaper.GetMediaSourceFileName(src, "")
      src_fn = (fn or ""):match("([^/\\]+)$") or ""  -- Just filename, no path
    end
  end

  return string.format("pos=%.2f, take='%s', src='%s'", pos, take_name, src_fn)
end

-- Global cache state
local CACHE = {
  loaded = false,
  data = nil,           -- { project_modified, item_count, items = {guid -> metadata} }
  dirty = false,        -- Cache needs saving
  hits = 0,            -- Cache hit count (for stats)
  misses = 0,          -- Cache miss count (for stats)
  debug = false,       -- Enable debug logging (set via UI or console if needed)
  invalidated = {},    -- Track which items were invalidated (for debugging)
}

-- Initialize cache on startup
local function init_cache()
  CACHE.data = load_cache()
  CACHE.loaded = true
  CACHE.dirty = false

  -- Validate cache against current project
  if CACHE.data then
    local current_mod = get_project_mod_time()
    if current_mod ~= CACHE.data.project_modified then
      reaper.ShowConsoleMsg("[ILBCache] Project modified, cache may be stale\n")
      -- Don't invalidate immediately - we'll check per-item
    end
  else
    -- No cache exists, create empty
    CACHE.data = {
      project_modified = get_project_mod_time(),
      item_count = 0,
      items = {}
    }
  end
end

-- Lookup metadata in cache (returns cached metadata or nil)
local function cache_lookup(item_guid, item)
  if not CACHE.data or not CACHE.data.items then return nil end

  local cached = CACHE.data.items[item_guid]
  if not cached then
    CACHE.misses = CACHE.misses + 1
    if CACHE.debug then
      reaper.ShowConsoleMsg(string.format("[Cache] MISS (new): %s\n", get_item_debug_info(item)))
    end
    return nil
  end

  -- Verify item hasn't changed (compare mod hash)
  local current_hash = get_item_mod_hash(item)
  if current_hash ~= cached.mod_time then
    -- Item changed, cache invalid for this item
    CACHE.misses = CACHE.misses + 1
    CACHE.invalidated[item_guid] = true
    if CACHE.debug then
      reaper.ShowConsoleMsg(string.format("[Cache] MISS (changed): %s | hash: %d -> %d\n",
        get_item_debug_info(item), cached.mod_time, current_hash))
    end
    CACHE.data.items[item_guid] = nil  -- Remove stale entry
    CACHE.dirty = true
    return nil
  end

  CACHE.hits = CACHE.hits + 1
  if CACHE.debug and CACHE.hits <= 5 then  -- Only log first 5 hits to avoid spam
    reaper.ShowConsoleMsg(string.format("[Cache] HIT: %s\n", get_item_debug_info(item)))
  end
  return cached
end

-- Store metadata in cache
local function cache_store(item_guid, item, metadata)
  if not CACHE.data then return end

  local hash = get_item_mod_hash(item)
  CACHE.data.items[item_guid] = {
    mod_time = hash,
    file_name = metadata.file_name or "",
    interleave = metadata.interleave or 0,
    meta_trk_name = metadata.meta_trk_name or "",
    channel_num = metadata.channel_num or 0,
    -- BWF/iXML metadata (15 fields)
    umid = metadata.umid or "",
    umid_pt = metadata.umid_pt or "",
    origination_date = metadata.origination_date or "",
    origination_time = metadata.origination_time or "",
    originator = metadata.originator or "",
    originator_ref = metadata.originator_ref or "",
    time_reference = metadata.time_reference or "",
    description = metadata.description or "",
    project = metadata.project or "",
    scene = metadata.scene or "",
    take_meta = metadata.take_meta or "",
    tape = metadata.tape or "",
    ubits = metadata.ubits or "",
    framerate = metadata.framerate or "",
    speed = metadata.speed or ""
  }

  if CACHE.debug and CACHE.invalidated[item_guid] then
    reaper.ShowConsoleMsg(string.format("[Cache] STORE (updated): %s | hash: %d\n",
      get_item_debug_info(item), hash))
  end

  CACHE.dirty = true
end

-- Save cache if dirty (call periodically or on exit)
local function cache_flush()
  if not CACHE.dirty or not CACHE.data then return end

  -- Update metadata
  CACHE.data.project_modified = get_project_mod_time()
  CACHE.data.item_count = 0
  for _ in pairs(CACHE.data.items) do
    CACHE.data.item_count = CACHE.data.item_count + 1
  end

  save_cache(CACHE.data)
  CACHE.dirty = false

  -- Log stats
  local total = CACHE.hits + CACHE.misses
  if total > 0 then
    local hit_rate = math.floor((CACHE.hits / total) * 100)
    reaper.ShowConsoleMsg(string.format("[ILBCache] Stats: %d hits, %d misses (%d%% hit rate)\n",
      CACHE.hits, CACHE.misses, hit_rate))
  end
end

-- Invalidate cache for specific items by GUID
local function cache_invalidate_items(item_guids)
  if not CACHE.data or not CACHE.data.items then return end

  local count = 0
  for _, guid in ipairs(item_guids) do
    if CACHE.data.items[guid] then
      CACHE.data.items[guid] = nil
      CACHE.dirty = true
      count = count + 1
    end
  end

  if count > 0 and CACHE.debug then
    reaper.ShowConsoleMsg(string.format("[ILBCache] Invalidated %d items\n", count))
  end
end

-- Clear cache (for manual refresh or troubleshooting)
local function cache_clear()
  CACHE.data = {
    project_modified = get_project_mod_time(),
    item_count = 0,
    items = {}
  }
  CACHE.dirty = true
  CACHE.hits = 0
  CACHE.misses = 0
  reaper.ShowConsoleMsg("[ILBCache] Cache cleared\n")
end


-- ===== Integrate with hsuanice Metadata Read (>= 0.2.0) =====
local META = dofile(
  reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua"
)
assert(META and (META.VERSION or "0") >= "0.2.0",
       "Please update 'hsuanice Metadata Read' to >= 0.2.0")


-- ===== Integrate with hsuanice List Table (>= 0.1.0) =====
local LT = dofile(
  reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Library/hsuanice_List Table.lua"
)
assert(LT and (LT.VERSION or "0") >= "0.1.0",
       "Please update 'hsuanice List Table' to >= 0.1.0")

-- TSV/CSV helpers: delegate to Library
local parse_clipboard_table = LT.parse_clipboard_table
local flatten_tsv_to_list   = LT.flatten_tsv_to_list
local src_shape_dims        = LT.src_shape_dims

---------------------------------------
-- Load Metadata Cache library (shared with Rename and other scripts)
---------------------------------------
local CACHE_LIB = dofile(
  reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Cache.lua"
)
assert(CACHE_LIB and CACHE_LIB.VERSION, "Failed to load 'hsuanice Metadata Cache'")

-- Debug flag for troubleshooting (persisted via ExtState, global for access in save_prefs)
DEBUG = (reaper.GetExtState("hsuanice_ItemListBrowser", "debug_mode") == "1")

-- Use original ShowConsoleMsg to bypass console filter
if DEBUG then
  original_ShowConsoleMsg(string.format("[ILB] Loaded Metadata Cache library v%s\n", CACHE_LIB.VERSION))
end

---------------------------------------
-- Dependency check for ImGui
---------------------------------------
if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui is required (install via ReaPack).", "Missing dependency", 0)
  return
end

-- ImGui setup
---------------------------------------
-- ImGui setup (single instance, do not duplicate)
local ctx = reaper.ImGui_CreateContext('Item List Browser')

-- Debug: Check context creation
if ctx then
  reaper.ShowConsoleMsg(string.format("[ILB] ImGui context created: %s (type: %s)\n",
    tostring(ctx), type(ctx)))
else
  reaper.ShowConsoleMsg("[ILB] ERROR: Failed to create ImGui context!\n")
end

-- Font size management (uses PushFont/PopFont in main loop)
local current_font_size = 13  -- Default size
local font_pushed_this_frame = false  -- Track if we pushed font this frame

local function set_font_size(size)
  current_font_size = size or 13
  -- console_force(string.format("[ILBFont] Font size set to: %d\n", current_font_size))
end

-- Docking preference (default: disabled for stability)
local ALLOW_DOCKING = false

-- Get the scale factor for UI elements (buttons, spacing, etc.)
local function get_ui_scale()
  return current_font_size / 13.0
end

-- Helper function to scale UI dimensions (width, height, etc.)
local function scale(value)
  return math.floor(value * get_ui_scale())
end

local LIBVER = (META and META.VERSION) and (' | Metadata Read v'..tostring(META.VERSION)) or ''
local FLT_MIN = 1.175494e-38
local function TF(name) local f = reaper[name]; return f and f() or 0 end
local function esc_pressed()
  if not ctx then return false end
  if reaper.ImGui_Key_Escape and reaper.ImGui_IsKeyPressed then
    local ok, result = pcall(reaper.ImGui_IsKeyPressed, ctx, reaper.ImGui_Key_Escape(), false)
    return ok and result or false
  end
  return false
end



-- Popup title (used by ESC check and BeginPopupModal)
local POPUP_TITLE = "Summary"



---------------------------------------
-- Small utils
---------------------------------------

-- Forward declarations so load_prefs() updates the same locals (not globals)
local TIME_MODE, CUSTOM_PATTERN, FORMAT, AUTO, FONT_SCALE
local SHOW_MUTED_ITEMS      -- whether to show muted rows
local scan_selection_rows
local scan_all_project_rows  -- ILB: forward decl, defined after get_all_project_items
local refresh_now
local _trim

-- defaults
if SHOW_MUTED_ITEMS == nil then SHOW_MUTED_ITEMS = true end

-- ===== ILB: All new state in tables to avoid Lua 200-local limit =====
local ILB = {
  -- Filter system
  only_selected = false,        -- show only REAPER-selected items
  track_index = 0,              -- 0 = all tracks, >0 = specific track index
  search_text = "",             -- text search filter
  track_list = {},              -- dynamically built track list
  -- Selection link
  sel_source = nil,             -- "list" | "reaper" | nil (feedback loop guard)
  sel_cooldown = 0,             -- timestamp of last list-to-REAPER sync
  sel_cooldown_ms = 0.3,        -- 300ms cooldown
  follow = true,                -- auto-scroll arrange view to selected item
  scroll_to_row = nil,          -- row index to auto-scroll to
  last_reaper_sel_hash = "",    -- REAPER selection state hash
  -- Project change detection
  last_project_count = 0,
  last_project_hash = "",
  -- Filter result cache (per-frame)
  cached_rows = nil,
  cached_rows_frame = -1,
}


-- log
local function log(fmt, ...)
  reaper.ShowConsoleMsg((fmt.."\n"):format(...))
end



-- Column order mapping (single source of truth)
local COL_ORDER, COL_POS = {}, {}   -- visual→logical / logical→visual
local COL_VISIBILITY = {}           -- col_id → true/false (for all 34 columns)

-- Column width configuration (customizable)
-- Edit these values to change default column widths
-- Positive number = width in pixels (e.g., 100)
-- Use "Reset Widths" button to restore these defaults after manual resizing
local DEFAULT_COL_WIDTH = {
  [1]  = 30,   -- # (item index)
  [2]  = 30,   -- TrkID (track number)
  [3]  = 100,  -- Track Name
  [4]  = 300,  -- Take Name
  [5]  = 300,  -- Item Note
  [6]  = 300,  -- Source File (longer paths)
  [7]  = 100,  -- Meta Trk Name
  [8]  = 30,   -- Chan# (channel number)
  [9]  = 30,   -- Interleave (mono-of-N)
  [10] = 30,   -- Mute (M/-)
  [11] = 10,   -- Color
  [12] = 80,  -- Start (fits "hh:mm:ss.SSS")
  [13] = 80,  -- End (fits "hh:mm:ss.SSS")
  -- BWF metadata columns
  [14] = 450,  -- UMID (64 hex chars)
  [15] = 450,  -- UMID_PT (Pro Tools format)
  [16] = 60,  -- OriginationDate (YYYY-MM-DD)
  [17] = 60,  -- OriginationTime (HH:MM:SS)
  [18] = 300,  -- Originator
  [19] = 300,  -- OriginatorReference
  [20] = 80,  -- TimeReference (sample count)
  [21] = 300,  -- Description (longer text)
  -- iXML metadata columns
  [22] = 80,  -- PROJECT
  [23] = 50,  -- SCENE
  [24] = 30,  -- TAKE
  [25] = 50,  -- TAPE
  [26] = 80,   -- UBITS
  [27] = 80,  -- FRAMERATE
  [28] = 80,   -- SPEED
  -- Source position columns (calculated from TimeReference)
  [29] = 90,  -- Source Start (TC)
  [30] = 90,  -- Source End (TC)
  -- Length column
  [31] = 80,  -- Length (fits "hh:mm:ss.SSS")
  -- File info columns
  [32] = 60,   -- Sample Rate (e.g. "48000")
  [33] = 40,   -- Bit Depth (e.g. "24")
  [34] = 40,   -- File Type (e.g. "WAV")
}

-- Current column widths (may be modified by user or Fit Content Width)
local COL_WIDTH = {}
for k, v in pairs(DEFAULT_COL_WIDTH) do
  COL_WIDTH[k] = v
end

-- Track if user requested column width reset
local RESET_COLUMN_WIDTHS = false
local RESET_COUNTER = 0  -- Counter to generate unique table IDs for width reset





-- === Preferences (persist across runs) ===
local function save_prefs()
  reaper.SetExtState(EXT_NS, "time_mode", TIME_MODE or "", true)
  reaper.SetExtState(EXT_NS, "custom_pattern", CUSTOM_PATTERN or "", true)
  reaper.SetExtState(EXT_NS, "auto_refresh", AUTO and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "console_output", CONSOLE.enabled and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "font_scale", tostring(FONT_SCALE or 1.0), true)
  reaper.SetExtState(EXT_NS, "allow_docking", ALLOW_DOCKING and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "debug_mode", DEBUG and "1" or "0", true)
  -- ILB prefs
  reaper.SetExtState(EXT_NS, "follow_selection", ILB.follow and "1" or "0", true)
end

-- ===== BEGIN Column Presets (named) =====
-- Persist multiple named presets. No auto-save. Recall explicitly by user.
-- Keys:
--   col_presets             = "name1|name2|..."
--   col_preset_active       = last selected name (optional)
--   col_preset.<sanitized>  = "1,2,3,...,28" (logical column IDs)

local PRESETS, PRESET_SET = {}, {}     -- list + set of names
local ACTIVE_PRESET = nil              -- string or nil
local PRESET_STATUS = "No preset"
local PRESET_NAME_BUF = ""             -- popup input buffer
local PRESET_EDITOR_STATE = nil        -- preset editor state {columns, dirty}
local PENDING_VISIBILITY_MAP = nil     -- temp storage for visibility when saving from editor

-- New format:
--   ord=[display-order joined by "|"];vis=col_id:visible_flag,...
--   Example: ord=5|2|1;vis=1:1,2:1,3:0,...
--   Backward compatible with earlier "id:flag" or legacy "1,2,3" payloads.
local function _csv_from_order_and_visibility(order, visibility_map)
  order = order or {}

  -- Build a normalized visibility table (even when caller did not provide visibility_map)
  local vis_map = {}
  if visibility_map then
    for col_id = 1, 34 do
      local flag = visibility_map[col_id]
      if flag == nil then
        vis_map[col_id] = false
      else
        vis_map[col_id] = not not flag
      end
    end
  else
    local visible_set = {}
    for _, col_id in ipairs(order) do
      visible_set[col_id] = true
    end
    for col_id = 1, 34 do
      vis_map[col_id] = visible_set[col_id] or false
    end
  end

  -- Serialize display order (only record currently visible columns)
  local ord_parts, seen = {}, {}
  for _, col_id in ipairs(order) do
    if not seen[col_id] and vis_map[col_id] then
      ord_parts[#ord_parts+1] = tostring(col_id)
      seen[col_id] = true
    end
  end

  -- If order is empty but visibility_map has visible columns, fill in order by column ID
  if #ord_parts == 0 then
    for col_id = 1, 34 do
      if vis_map[col_id] then
        ord_parts[#ord_parts+1] = tostring(col_id)
      end
    end
  end

  -- Serialize full column visibility
  local vis_parts = {}
  for col_id = 1, 34 do
    local flag = vis_map[col_id] and "1" or "0"
    vis_parts[#vis_parts+1] = string.format("%d:%s", col_id, flag)
  end

  return string.format("ord=%s;vis=%s", table.concat(ord_parts, "|"), table.concat(vis_parts, ","))
end

-- Parse format: "1:1,2:1,3:1,4:0,..." returns order (visible columns) and visibility map
local function _order_and_visibility_from_csv(s)
  s = tostring(s or "")

  -- Try new format first: ord=...;vis=...
  local ord_section, vis_section = s:match("^ord=([^;]*);vis=(.+)$")
  if ord_section then
    local order = {}
    for token in ord_section:gmatch("([^|]+)") do
      local col_id = tonumber(token)
      if col_id then order[#order+1] = col_id end
    end

    local visibility_map = {}
    if vis_section and vis_section ~= "" then
      for pair in vis_section:gmatch("([^,]+)") do
        local col_id, visible_flag = pair:match("(%d+):(%d+)")
        if col_id and visible_flag then
          col_id = tonumber(col_id)
          visibility_map[col_id] = (tonumber(visible_flag) == 1)
        end
      end
    end

    -- Columns not mentioned in the saved vis= section are new (added after preset was saved)
    -- Default new columns to visible so they appear automatically
    for col_id = 1, 34 do
      if visibility_map[col_id] == nil then visibility_map[col_id] = true end
    end

    -- Some legacy data may have visible columns in visibility_map not listed in ord_section; append them.
    if visibility_map then
      local seen = {}
      for _, col_id in ipairs(order) do seen[col_id] = true end
      for col_id = 1, 34 do
        if visibility_map[col_id] and not seen[col_id] then
          order[#order+1] = col_id
        end
      end
    end

    return (#order > 0) and order or nil, visibility_map
  end

  -- Fall back to legacy "id:flag" format
  if s:find(":") then
    -- New format: "1:1,2:1,3:1,4:0,..."
    local order = {}
    local visibility_map = {}

    for pair in s:gmatch("([^,]+)") do
      local col_id, visible_flag = pair:match("(%d+):(%d+)")
      if col_id and visible_flag then
        col_id = tonumber(col_id)
        visible_flag = tonumber(visible_flag)
        visibility_map[col_id] = (visible_flag == 1)
        if visible_flag == 1 then
          order[#order+1] = col_id
        end
      end
    end

    -- New columns not in saved data default to visible
    for col_id = 1, 34 do
      if visibility_map[col_id] == nil then
        visibility_map[col_id] = true
        order[#order+1] = col_id
      end
    end

    return (#order > 0) and order or nil, visibility_map
  else
    -- Old format (backward compatibility): "1,2,3,..." - all listed columns are visible
    local order = {}
    for num in s:gmatch("([^,]+)") do
      local v = tonumber(num)
      if v then order[#order+1] = v end
    end

    -- Build visibility map - all columns in order are visible, rest are hidden
    local visibility_map = {}
    local visible_set = {}
    for _, col_id in ipairs(order) do
      visible_set[col_id] = true
    end
    for col_id = 1, 34 do
      visibility_map[col_id] = visible_set[col_id] or false
    end

    return (#order > 0) and order or nil, visibility_map
  end
end

-- Legacy function for backward compatibility (not used in new code)
local function _csv_from_order(order)
  local t = {}
  for i=1,#(order or {}) do t[i] = tostring(order[i]) end
  return table.concat(t, ",")
end

-- Legacy function for backward compatibility (not used in new code)
local function _order_from_csv(s)
  local out = {}
  for num in tostring(s or ""):gmatch("([^,]+)") do
    local v = tonumber(num); if v then out[#out+1] = v end
  end
  return (#out > 0) and out or nil
end

local function _normalize_full_order(order)
  local seen, out = {}, {}
  for i=1,#(order or {}) do
    local v = tonumber(order[i]); if v and not seen[v] then seen[v]=true; out[#out+1]=v end
  end
  for id=1,34 do if not seen[id] then out[#out+1]=id end end
  return out
end

local function _sanitize_name(name)
  name = (name or ""):gsub("^%s+",""):gsub("%s+$",""):gsub("[%c\r\n]","")
  return name
end

local function _key_for(name)
  local safe = name:gsub("[^%w%._%-]", "_") -- spaces & specials -> "_"
  return "col_preset." .. safe
end

local function _preset_load_index()
  PRESETS, PRESET_SET = {}, {}
  local s = reaper.GetExtState(EXT_NS, "col_presets") or ""
  for name in s:gmatch("([^|]+)") do
    name = _sanitize_name(name)
    if name ~= "" and not PRESET_SET[name] then
      PRESETS[#PRESETS+1] = name
      PRESET_SET[name] = true
    end
  end
  table.sort(PRESETS, function(a,b) return a:lower()<b:lower() end)
end

local function _preset_save_index()
  reaper.SetExtState(EXT_NS, "col_presets", table.concat(PRESETS, "|"), true)
end

-- Updated to accept both order and visibility map
local function preset_save_as(name, order, visibility_map)
  name = _sanitize_name(name)
  if name == "" then PRESET_STATUS = "Name required"; return false end

  -- If visibility_map is provided, use new format; otherwise use legacy format
  local payload
  if visibility_map then
    payload = _csv_from_order_and_visibility(order or COL_ORDER, visibility_map)
  else
    -- Legacy: assume all columns in order are visible, rest hidden
    order = _normalize_full_order(order or COL_ORDER)
    payload = _csv_from_order(order)
  end

  reaper.SetExtState(EXT_NS, _key_for(name), payload, true)
  if not PRESET_SET[name] then
    PRESET_SET[name]=true; PRESETS[#PRESETS+1]=name; table.sort(PRESETS, function(a,b) return a:lower()<b:lower() end)
    _preset_save_index()
  end
  ACTIVE_PRESET = name
  reaper.SetExtState(EXT_NS, "col_preset_active", name, true)
  PRESET_STATUS = "Saved: "..name
  return true
end

local function preset_recall(name)
  name = _sanitize_name(name)
  if name == "" then PRESET_STATUS = "No preset selected"; return false end
  local payload = reaper.GetExtState(EXT_NS, _key_for(name))

  -- Try to parse with new format (returns order and visibility_map)
  local ord, visibility_map = _order_and_visibility_from_csv(payload)

  if ord and #ord > 0 then
    -- Set COL_ORDER to only visible columns in the correct order
    COL_ORDER = ord
    COL_POS = {}
    for vis_pos, col_id in ipairs(ord) do
      COL_POS[col_id] = vis_pos
    end

    -- Store visibility map globally for Preset Editor
    COL_VISIBILITY = visibility_map or {}

    ACTIVE_PRESET = name
    reaper.SetExtState(EXT_NS, "col_preset_active", name, true)
    PRESET_STATUS = "Preset: "..name
    return true
  end

  PRESET_STATUS = "Preset not found"
  return false
end

local function preset_delete(name)
  name = _sanitize_name(name)
  if name == "" then return end
  reaper.DeleteExtState(EXT_NS, _key_for(name), true)
  if PRESET_SET[name] then
    PRESET_SET[name] = nil
    for i,n in ipairs(PRESETS) do if n==name then table.remove(PRESETS, i); break end end
    _preset_save_index()
  end
  if ACTIVE_PRESET == name then
    ACTIVE_PRESET = nil
    reaper.SetExtState(EXT_NS, "col_preset_active", "", true)
  end
  PRESET_STATUS = "Deleted: "..name
end

-- Return all preset names for the dropdown menu
local function preset_list()
  return PRESETS
end

-- Return current preset status text for display
local function col_preset_status_text()
  return PRESET_STATUS or ""
end



local function presets_init()
  _preset_load_index()
  local last = reaper.GetExtState(EXT_NS, "col_preset_active")
  if last and last ~= "" then
    if not preset_recall(last) then PRESET_STATUS = "No preset" end
  else
    PRESET_STATUS = (#PRESETS>0) and ("Preset: "..PRESETS[1]) or "No preset"
  end
end
-- ===== END Column Presets (named) =====



local function load_prefs()
  -- restore mode
  local m = reaper.GetExtState(EXT_NS, "time_mode")
  if m and m ~= "" then
    if     m == "ms"     then TIME_MODE = TFLib.MODE.MS
    elseif m == "tc"     then TIME_MODE = TFLib.MODE.TC
    elseif m == "beats"  then TIME_MODE = TFLib.MODE.BEATS
    elseif m == "sec"    then TIME_MODE = TFLib.MODE.SEC
    elseif m == "custom" then TIME_MODE = TFLib.MODE.CUSTOM
    end
  end




  -- restore pattern
  local pat = reaper.GetExtState(EXT_NS, "custom_pattern")
  if pat and pat ~= "" then CUSTOM_PATTERN = pat end

  -- rebuild formatter according to restored state
  if TIME_MODE == TFLib.MODE.MS then
    FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=3})
  elseif TIME_MODE == TFLib.MODE.CUSTOM then
    FORMAT = TFLib.make_formatter(TIME_MODE, {pattern=CUSTOM_PATTERN})
  else
    FORMAT = TFLib.make_formatter(TIME_MODE)
  end

  -- restore auto-refresh state
  local a = reaper.GetExtState(EXT_NS, "auto_refresh")
  if a ~= "" then AUTO = (a ~= "0") end

  -- restore console output preference
  local c = reaper.GetExtState(EXT_NS, "console_output")
  if c == "0" then
    CONSOLE.enabled = false
  elseif c == "1" then
    CONSOLE.enabled = true
  end

  -- restore font scale preference
  local fs = reaper.GetExtState(EXT_NS, "font_scale")
  if fs and fs ~= "" then
    local scale = tonumber(fs)
    if scale and scale >= 0.5 and scale <= 3.0 then
      FONT_SCALE = scale
    end
  end

  -- restore docking preference
  local d = reaper.GetExtState(EXT_NS, "allow_docking")
  if d == "1" then
    ALLOW_DOCKING = true
  elseif d == "0" then
    ALLOW_DOCKING = false
  end
  -- default is false if not set

  -- restore follow selection preference (ILB)
  local fsel = reaper.GetExtState(EXT_NS, "follow_selection")
  if fsel == "1" then ILB.follow = true elseif fsel == "0" then ILB.follow = false end

  -- Column presets (named) — initialize index and optionally recall last active
  presets_init()

  -- Restore last column order (if no preset is active)
  if not ACTIVE_PRESET or ACTIVE_PRESET == "" then
    local csv = reaper.GetExtState(EXT_NS, "col_order_current")
    if csv and csv ~= "" then
      local ord = _order_from_csv(csv)
      if ord and #ord > 0 then
        ord = _normalize_full_order(ord)
        COL_ORDER = ord
        COL_POS = {}
        for vis, id in ipairs(ord) do if id then COL_POS[id] = vis end end

        -- Initialize COL_VISIBILITY - all columns in ord are visible
        COL_VISIBILITY = {}
        for col_id = 1, 34 do
          COL_VISIBILITY[col_id] = (COL_POS[col_id] ~= nil)
        end
      end
    end
  end

  -- Ensure COL_VISIBILITY is initialized even if no preset/order was loaded
  if not COL_VISIBILITY or not next(COL_VISIBILITY) then
    COL_VISIBILITY = {}
    for col_id = 1, 34 do
      COL_VISIBILITY[col_id] = true  -- default: all visible
    end
  end
end



-- Runtime cache
local PRESET = nil          -- {logical_id,...} read from ExtState
local LAST_SAVED_STR = nil  -- csv cache for quick compare
local PRESET_STATUS = ""    -- status hint e.g. "Preset ✓" / "Column not saved"

local function _csv_from_order(order)
  local t = {}
  for i=1,#order do t[i] = tostring(order[i] or "") end
  return table.concat(t, ",")
end

local function _order_from_csv(s)
  local out = {}
  for num in tostring(s or ""):gmatch("([^,]+)") do
    local v = tonumber(num); if v then out[#out+1] = v end
  end
  return (#out > 0) and out or nil
end

local function _order_equal(a,b)
  if not (a and b) then return false end
  if #a ~= #b then return false end
  for i=1,#a do if a[i] ~= b[i] then return false end end
  return true
end

local function _normalize_full_order(order)
  -- Ensure all 34 columns are included; append any missing ones (handles legacy/incomplete data)
  local seen, out = {}, {}
  for i=1,#(order or {}) do
    local v = tonumber(order[i]); if v and not seen[v] then seen[v]=true; out[#out+1]=v end
  end
  for id=1,34 do if not seen[id] then out[#out+1]=id end end
  return out
end

local function load_col_preset()
  local csv = reaper.GetExtState(EXT_NS, "col_preset")
  local ord = _normalize_full_order(_order_from_csv(csv))
  if ord then
    PRESET = ord
    LAST_SAVED_STR = _csv_from_order(ord)
  else
    PRESET = nil
    LAST_SAVED_STR = nil
  end
end

local function save_col_preset(order, note)
  local ord = _normalize_full_order(order or COL_ORDER or DEFAULT_COL_ORDER)
  local csv = _csv_from_order(ord)
  reaper.SetExtState(EXT_NS, "col_preset", csv, true)
  reaper.SetExtState(EXT_NS, "col_preset_saved_at", tostring(os.time()), true)
  PRESET = ord
  LAST_SAVED_STR = csv
  PRESET_STATUS = note or "Preset ✓"
end






local function item_start(it) return reaper.GetMediaItemInfo_Value(it,"D_POSITION") end
local function item_track(it) return reaper.GetMediaItemTrack(it) end
local function track_index(tr) return math.floor(reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or 0) end
local function track_name(tr) local _, n = reaper.GetTrackName(tr, "") return n end

local function fmt_seconds(s) if not s then return "" end return string.format("%.6f", s) end
local function fmt_tc(s)      if not s then return "" end return reaper.format_timestr_pos(s, "", 5) end

-- Time Format Library (with fallback)
local ok
ok, TFLib = pcall(dofile, reaper.GetResourcePath().."/Scripts/hsuanice Scripts/Library/hsuanice_Time Format.lua")

if not ok or not TFLib or not TFLib.make_formatter then
  -- fallback: supports m:s / TC / Beats (three modes)
  local function _fmt_ms(sec, decimals)
    if sec == nil then return "" end
    local sign = ""
    if sec < 0 then sign = "-"; sec = -sec end
    local m = math.floor(sec / 60)
    local dec = tonumber(decimals) or 3
    local s = sec - m*60
    local cap = 60 - (10^-dec) * 0.5
    if s >= cap then m = m + 1; s = 0 end
    local s_fmt = ("%0."..dec.."f"):format(s)
    if tonumber(s_fmt) < 10 then s_fmt = "0"..s_fmt end
    return ("%s%d:%s"):format(sign, m, s_fmt)
  end
  TFLib = {
    VERSION="fallback",
    MODE={ SEC="sec", MS="ms", TC="tc", BEATS="beats" },
    make_formatter=function(mode, opts)
      local m = mode
      if m=="tc" then return function(sec) return reaper.format_timestr_pos(sec or 0, "", 5) end end
      if m=="beats" then return function(sec) return reaper.format_timestr_pos(sec or 0, "", 1) end end
      if m=="sec" then
        local dec=(opts and opts.decimals) or 6
        return function(sec) return string.format("%."..dec.."f", sec or 0) end
      end
      local dec=(opts and opts.decimals) or 3
      return function(sec) return _fmt_ms(sec or 0, dec) end
    end,
    headers=function(mode, opts)
      if mode=="tc" then return "Start (TC)","End (TC)" end
      if mode=="beats" then return "Start (Beats)","End (Beats)" end
      if mode=="sec" then return "Start (s)","End (s)" end
      if mode=="custom" then return "Start (Custom)","End (Custom)" end
      return "Start (m:s)","End (m:s)"
    end,
    format=function(sec, mode, opts)
      return (TFLib.make_formatter(mode, opts))(sec)
    end
  }
end




-- file ops
local function choose_save_path(default_name, filter)
  if reaper.JS_Dialog_BrowseForSaveFile then
    local ok, fn = reaper.JS_Dialog_BrowseForSaveFile("Save", "", default_name, filter)
    if ok and fn and fn ~= "" then return fn end
    return nil
  end
  local proj, projfn = reaper.EnumProjects(-1, "")
  local base = projfn ~= "" and projfn:match("^(.*)[/\\]") or reaper.GetResourcePath()
  return (base or reaper.GetResourcePath()) .. "/" .. default_name
end

local function write_text_file(path, text)
  if not path or path == "" then return false end
  local f = io.open(path, "wb"); if not f then return false end
  f:write(text or ""); f:close(); return true
end

local function timestamp()
  local t=os.date("*t"); return string.format("%04d%02d%02d_%02d%02d%02d",t.year,t.month,t.day,t.hour,t.min,t.sec)
end


-- Build human-readable summary text (uses current time formatter)
local function build_summary_text(rows)
  local S = LT.compute_summary(rows or {})
  if not S or (S.count or 0) == 0 then return "No items." end

  -- Use format_time() if available, otherwise use TFLib fallback:
  local function _fmt(sec)
    if format_time then return format_time(sec) end
    -- fallback: format via TFLib using current TIME_MODE
    local opts = (TIME_MODE == TFLib.MODE.MS) and {decimals=3}
              or (TIME_MODE == TFLib.MODE.CUSTOM) and {pattern=CUSTOM_PATTERN}
              or nil
    return TFLib.format(sec, TIME_MODE, opts)
  end

  local from = _fmt(S.min_start)
  local to   = _fmt(S.max_end)
  local span = _fmt(S.span)
  local sum  = _fmt(S.sum_len)

  return table.concat({
    ("Number of items:\n%d"):format(S.count),
    "",
    ("Total span (first to last):\n%s"):format(span),
    "",
    ("Sum of lengths:\n%s"):format(sum),
    "",
    ("Range:\n%s  →  %s"):format(from, to),
  }, "\n")
end



-- forward locals (prevent re-declaration later)
ROWS = {}



-- ===== Debug: dump current on-screen column order =====
local __last_order_dump = ""
local function dump_order_once()
  local parts = {}
  for i, id in ipairs(COL_ORDER or {}) do
    parts[#parts+1] = string.format("%d:%d", i, id) -- visual_index:logical_col_id
  end
  local s = "[ORDER] " .. table.concat(parts, ", ")
  if s ~= __last_order_dump then
    reaper.ShowConsoleMsg(s .. "\n")
    __last_order_dump = s
  end
end

-- Debug dump with tag and COL_POS output
local function dump_cols(tag)
  local a = {}
  for i, id in ipairs(COL_ORDER or {}) do a[#a+1] = string.format("%d:%d", i, id) end
  reaper.ShowConsoleMsg(string.format("[%s][ORDER] %s\n", tag or "?", table.concat(a, ", ")))
  local b = {}
  if COL_POS then
    for id, pos in pairs(COL_POS) do b[#b+1] = string.format("%d->%d", id, pos) end
    table.sort(b)
    reaper.ShowConsoleMsg(string.format("[%s][POS]   %s\n", tag or "?", table.concat(b, ", ")))
  end
end



---------------------------------------
-- Selection scan
---------------------------------------
local function get_selected_items_sorted()
  local t, n = {}, reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do t[#t+1] = reaper.GetSelectedMediaItem(0,i) end
  table.sort(t, function(a,b)
    local sa, sb = item_start(a) or 0, item_start(b) or 0
    if math.abs(sa - sb) > 1e-9 then return sa < sb end
    local ta = item_track(a); local tb = item_track(b)
    local ia = ta and track_index(ta) or 0
    local ib = tb and track_index(tb) or 0
    if ia ~= ib then return ia < ib end
    return tostring(a) < tostring(b)
  end)
  return t
end

---------------------------------------
-- Collect item fields (uses Library)
---------------------------------------
-- Fast: collect basic fields only (no metadata parsing)
local function collect_basic_fields(item)
  local row = {}

  -- Track index/name
  local tr = reaper.GetMediaItemTrack(item)
  row.track_idx  = tr and math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or 0
  row.track_name = tr and (select(2, reaper.GetTrackName(tr, "")) or "") or ""

  -- Stable GUIDs for unique IDs and cross-frame identity
  local _, item_guid  = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  row.__item_guid     = item_guid or ""
  local _, track_guid = tr and reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  row.__track_guid    = track_guid or ""

  local tk = reaper.GetActiveTake(item)
  row.__take = tk

  -- Basic take info (fast)
  row.take_name = tk and (select(2, reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)) or "") or ""

  -- Item note (fast)
  local ok_note, note = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  row.item_note = (ok_note and note) or ""

  -- Item bounds (fast)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  row.start_time = pos
  row.end_time   = pos + len
  row.length     = len

  -- Mute state (fast)
  row.muted = (reaper.GetMediaItemInfo_Value(item, "B_MUTE") or 0) > 0.5

  -- Item color (fast)
  local native = reaper.GetDisplayedMediaItemColor(item) or 0
  if native ~= 0 then
    local r, g, b = reaper.ColorFromNative(native)
    row.color_rgb = { r, g, b }
    row.color_hex = string.format("#%02X%02X%02X", r, g, b)
  else
    row.color_rgb, row.color_hex = nil, ""
  end

  -- File info (fast: directly from REAPER API, no external tools needed)
  row.sample_rate = ""
  row.bit_depth = ""
  row.file_type = ""
  if tk then
    local source = reaper.GetMediaItemTake_Source(tk)
    if source then
      -- Sample rate
      local sr = reaper.GetMediaSourceSampleRate(source)
      if sr and sr > 0 then row.sample_rate = tostring(math.floor(sr)) end
      -- File type (returns single string)
      local ftype = reaper.GetMediaSourceType(source, "")
      row.file_type = ftype or ""
      -- Bit depth: parse RIFF chunks to find "fmt " (handles JUNK/ds64 before fmt)
      local src_path = reaper.GetMediaSourceFileName(source, "")
      if src_path and src_path ~= "" then
        local fh = io.open(src_path, "rb")
        if fh then
          local riff = fh:read(4)
          if riff == "RIFF" or riff == "RF64" then
            fh:seek("cur", 4) -- skip file size
            local wave = fh:read(4)
            if wave == "WAVE" then
              for _ = 1, 40 do -- safety limit on chunk iterations
                local chunk_id = fh:read(4)
                if not chunk_id or #chunk_id < 4 then break end
                local sb = fh:read(4)
                if not sb or #sb < 4 then break end
                local chunk_sz = sb:byte(1) + sb:byte(2)*256 + sb:byte(3)*65536 + sb:byte(4)*16777216
                if chunk_id == "fmt " then
                  if chunk_sz >= 16 then
                    local fmt = fh:read(16)
                    if fmt and #fmt >= 16 then
                      local bits = fmt:byte(15) + fmt:byte(16) * 256
                      if bits > 0 and bits <= 64 then
                        row.bit_depth = tostring(bits)
                      end
                    end
                  end
                  break
                else
                  fh:seek("cur", chunk_sz + (chunk_sz % 2)) -- skip chunk (pad to even)
                end
              end
            end
          end
          fh:close()
        end
      end
    end
  end

  -- Keep object references for editing
  row.__item  = item
  row.__track = tr

  -- Placeholder for metadata (to be loaded later)
  row.file_name = ""
  row.interleave = 0
  row.meta_trk_name = ""
  row.channel_num = 0

  -- Placeholder for new metadata columns
  row.umid = ""
  row.umid_pt = ""
  row.origination_date = ""
  row.origination_time = ""
  row.originator = ""
  row.originator_ref = ""
  row.time_reference = ""
  row.description = ""
  row.project = ""
  row.scene = ""
  row.take_meta = ""
  row.tape = ""
  row.ubits = ""
  row.framerate = ""
  row.speed = ""

  -- Source position columns (calculated from TimeReference)
  row.source_start = ""
  row.source_end = ""

  row.__metadata_loaded = false  -- Flag for lazy loading

  -- ILB: pre-build search text from basic fields (updated after metadata loads)
  row.__search_text = table.concat({
    row.track_name or "", row.take_name or "", row.item_note or "",
    row.sample_rate or "", row.file_type or "",
  }, " "):lower()

  return row
end

-- Calculate source position from TimeReference (BWF sample count since midnight)
-- Returns source_start_tc, source_end_tc as formatted timecode strings
local function calculate_source_position(item, time_reference_str, fields)
  if not item or not time_reference_str or time_reference_str == "" then
    return "", ""
  end

  -- Parse TimeReference (sample count since midnight)
  local time_ref_samples = tonumber(time_reference_str)
  if not time_ref_samples then
    return "", ""
  end

  -- Get sample rate from fields or source
  local sample_rate = 48000  -- Default sample rate
  if fields and fields.samplerate then
    sample_rate = tonumber(fields.samplerate) or 48000
  else
    local take = reaper.GetActiveTake(item)
    if take then
      local source = reaper.GetMediaItemTake_Source(take)
      if source then
        sample_rate = reaper.GetMediaSourceSampleRate(source)
        if not sample_rate or sample_rate <= 0 then
          sample_rate = 48000
        end
      end
    end
  end

  -- Convert TimeReference from samples to seconds
  local time_ref_seconds = time_ref_samples / sample_rate

  -- Get take start offset (where in the source file the take starts)
  local take = reaper.GetActiveTake(item)
  if not take then
    return "", ""
  end

  local take_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0

  -- Calculate source positions
  -- source_start = time_reference + take_offset
  local source_start_sec = time_ref_seconds + take_offset

  -- Get item length to calculate source end
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local playrate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
  local source_len = item_len * playrate  -- Account for playback rate

  local source_end_sec = source_start_sec + source_len

  -- Format as timecode (using REAPER's TC formatter)
  local source_start_tc = reaper.format_timestr_pos(source_start_sec, "", 5)  -- 5 = TC format
  local source_end_tc = reaper.format_timestr_pos(source_end_sec, "", 5)

  return source_start_tc, source_end_tc
end

-- Slow: load full metadata for a row (called on demand or in background)
-- Now with cache support!
local function load_metadata_for_row(row)
  if row.__metadata_loaded then return end

  local item = row.__item
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then return end

  local item_guid = row.__item_guid

  -- Try cache first for ALL metadata fields (using shared library)
  local cached = CACHE_LIB.lookup(item_guid, item)
  if cached then
    -- Cache hit! Use all cached metadata
    row.file_name = cached.file_name or ""
    row.interleave = cached.interleave or 0
    row.meta_trk_name = cached.meta_trk_name or ""
    row.channel_num = cached.channel_num or 0
    -- BWF/iXML metadata from cache
    row.umid = cached.umid or ""
    row.umid_pt = cached.umid_pt or ""
    row.origination_date = cached.origination_date or ""
    row.origination_time = cached.origination_time or ""
    row.originator = cached.originator or ""
    row.originator_ref = cached.originator_ref or ""
    row.time_reference = cached.time_reference or ""
    row.description = cached.description or ""
    row.project = cached.project or ""
    row.scene = cached.scene or ""
    row.take_meta = cached.take_meta or ""
    row.tape = cached.tape or ""
    row.ubits = cached.ubits or ""
    row.framerate = cached.framerate or ""
    row.speed = cached.speed or ""

    -- Calculate source position from TimeReference (not cached, always calculated)
    row.source_start, row.source_end = calculate_source_position(item, row.time_reference, nil)

    row.__metadata_loaded = true
    -- ILB: rebuild full search text with metadata
    row.__search_text = table.concat({
      row.track_name or "", row.take_name or "", row.item_note or "",
      row.file_name or "", row.meta_trk_name or "",
      row.originator or "", row.description or "",
      row.project or "", row.scene or "", row.take_meta or "", row.tape or "",
      row.sample_rate or "", row.file_type or "",
    }, " "):lower()
    return
  end

  -- Cache miss: do expensive metadata parsing
  local f = META.collect_item_fields(item)

  -- File/take from fields
  row.file_name = f.srcfile or ""

  -- Interleave & meta name/chan (Library)
  local idx = META.guess_interleave_index(item, f) or f.__chan_index or 1
  f.__chan_index = idx
  local name = META.expand("${trk}", f, nil, false)
  local ch   = tonumber(META.expand("${chnum}", f, nil, false)) or idx

  row.interleave    = idx
  row.meta_trk_name = name or ""
  row.channel_num   = ch

  -- BWF/iXML metadata fields
  row.umid = f.umid or f.UMID or ""
  row.umid_pt = f.umid_pt or ""
  row.origination_date = f.originationdate or f.OriginationDate or ""
  row.origination_time = f.originationtime or f.OriginationTime or ""
  row.originator = f.originator or f.Originator or ""
  row.originator_ref = f.originatorreference or f.OriginatorReference or ""
  row.time_reference = f.timereference or f.TimeReference or ""
  row.description = f.description or f.Description or ""
  row.project = f.project or f.PROJECT or ""
  row.scene = f.scene or f.SCENE or ""
  row.take_meta = f.take or f.TAKE or ""
  row.tape = f.tape or f.TAPE or ""
  row.ubits = f.ubits or f.UBITS or ""
  row.framerate = f.framerate or f.FRAMERATE or ""
  row.speed = f.speed or f.SPEED or ""

  -- Calculate source position from TimeReference (not cached, always calculated)
  row.source_start, row.source_end = calculate_source_position(item, row.time_reference, f)

  row.__fields      = f
  row.__metadata_loaded = true
  -- ILB: rebuild full search text with metadata
  row.__search_text = table.concat({
    row.track_name or "", row.take_name or "", row.item_note or "",
    row.file_name or "", row.meta_trk_name or "",
    row.originator or "", row.description or "",
    row.project or "", row.scene or "", row.take_meta or "", row.tape or "",
    row.sample_rate or "", row.file_type or "",
  }, " "):lower()

  -- Store ALL metadata in cache for next time (using shared library)
  CACHE_LIB.store(item_guid, item, {
    file_name = row.file_name,
    interleave = row.interleave,
    meta_trk_name = row.meta_trk_name,
    channel_num = row.channel_num,
    -- BWF/iXML metadata
    umid = row.umid,
    umid_pt = row.umid_pt,
    origination_date = row.origination_date,
    origination_time = row.origination_time,
    originator = row.originator,
    originator_ref = row.originator_ref,
    time_reference = row.time_reference,
    description = row.description,
    project = row.project,
    scene = row.scene,
    take_meta = row.take_meta,
    tape = row.tape,
    ubits = row.ubits,
    framerate = row.framerate,
    speed = row.speed
  })
end

-- Immediately refresh specific rows by item GUIDs (for instant feedback after edits)
local function refresh_rows_by_guids(item_guids)
  if not ROWS or #ROWS == 0 then return end

  -- Build GUID to row mapping
  local guid_to_row = {}
  for _, row in ipairs(ROWS) do
    if row.__item_guid then
      guid_to_row[row.__item_guid] = row
    end
  end

  -- Reload data for affected rows
  for _, guid in ipairs(item_guids) do
    local row = guid_to_row[guid]
    if row and row.__item then
      local item = row.__item
      if reaper.ValidatePtr(item, "MediaItem*") then
        -- Reload basic fields
        local _, track_name = reaper.GetTrackName(row.__track or item_track(item), "")
        row.track_name = track_name

        local take = reaper.GetActiveTake(item)
        if take then
          local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
          row.take_name = take_name
        end

        local _, note = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        row.item_note = note

        -- Force reload metadata (cache already invalidated)
        row.__metadata_loaded = false
        load_metadata_for_row(row)
      end
    end
  end
end

-- Full load (for compatibility, used when immediate load needed)
local function collect_fields_for_item(item)
  local row = collect_basic_fields(item)
  load_metadata_for_row(row)
  return row
end

function scan_selection_rows()
  local its = get_selected_items_sorted()
  local rows = {}
  for _, it in ipairs(its) do
    rows[#rows+1] = collect_fields_for_item(it)
  end
  return rows
end

---------------------------------------
-- Project-wide Item Scanning System
---------------------------------------
local PROJECT_SCAN = {
  active = false,        -- Is project scan in progress?
  all_items = {},        -- All project items to scan
  scanned_count = 0,     -- How many items scanned
  batch_size = 20,       -- Scan N items per frame
  cancelled = false,     -- User cancelled scan?
  start_time = 0,        -- Scan start time
}

-- Get all items in project (across all tracks)
local function get_all_project_items()
  local items = {}
  local track_count = reaper.CountTracks(0)
  for t = 0, track_count - 1 do
    local track = reaper.GetTrack(0, t)
    local item_count = reaper.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
      local item = reaper.GetTrackMediaItem(track, i)
      items[#items + 1] = item
    end
  end
  return items
end

-- ILB: Scan ALL project items (sorted by position then track)
scan_all_project_rows = function()
  local items = get_all_project_items()
  table.sort(items, function(a, b)
    local sa, sb = item_start(a) or 0, item_start(b) or 0
    if math.abs(sa - sb) > 1e-9 then return sa < sb end
    local ta = item_track(a); local tb = item_track(b)
    local ia = ta and track_index(ta) or 0
    local ib = tb and track_index(tb) or 0
    if ia ~= ib then return ia < ib end
    return tostring(a) < tostring(b)
  end)
  local rows = {}
  for _, it in ipairs(items) do
    rows[#rows+1] = collect_fields_for_item(it)
  end
  return rows
end

-- ILB: Project structure change detection
local function build_project_hash()
  local track_count = reaper.CountTracks(0)
  local total_items = 0
  local hash_parts = { tostring(track_count) }
  for t = 0, track_count - 1 do
    local track = reaper.GetTrack(0, t)
    local ic = reaper.CountTrackMediaItems(track)
    total_items = total_items + ic
    if ic > 0 then
      local item = reaper.GetTrackMediaItem(track, 0)
      if item then
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        hash_parts[#hash_parts + 1] = guid
      end
      if ic > 1 then
        local item2 = reaper.GetTrackMediaItem(track, ic - 1)
        if item2 then
          local _, guid2 = reaper.GetSetMediaItemInfo_String(item2, "GUID", "", false)
          hash_parts[#hash_parts + 1] = guid2
        end
      end
    end
  end
  hash_parts[#hash_parts + 1] = tostring(total_items)
  return table.concat(hash_parts, "|"), total_items
end

local function has_project_changed()
  local hash, count = build_project_hash()
  if count ~= ILB.last_project_count or hash ~= ILB.last_project_hash then
    ILB.last_project_hash = hash
    ILB.last_project_count = count
    return true
  end
  return false
end

local function update_project_cache()
  local hash, count = build_project_hash()
  ILB.last_project_hash = hash
  ILB.last_project_count = count
  LAST_REFRESH_TIME = reaper.time_precise()
  NEEDS_REFRESH = false
end

-- ILB: Build track list for filter dropdown
local function build_track_list()
  local tracks = {}
  local count = reaper.CountTracks(0)
  for t = 0, count - 1 do
    local track = reaper.GetTrack(0, t)
    local idx = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
    local _, name = reaper.GetTrackName(track, "")
    tracks[#tracks + 1] = { index = idx, name = name or "" }
  end
  ILB.track_list = tracks
  return tracks
end

-- Start project-wide scan (build complete cache)
local function start_project_scan()
  PROJECT_SCAN.all_items = get_all_project_items()
  PROJECT_SCAN.scanned_count = 0
  PROJECT_SCAN.cancelled = false
  PROJECT_SCAN.active = true
  PROJECT_SCAN.start_time = reaper.time_precise()

  local total = #PROJECT_SCAN.all_items
  console_forcef("\n[ILB] Starting project scan: %d items total\n", total)
end

-- Process one batch of project scan
local function process_project_scan_batch()
  if not PROJECT_SCAN.active then return false end

  local total = #PROJECT_SCAN.all_items
  local start_idx = PROJECT_SCAN.scanned_count + 1
  local end_idx = math.min(start_idx + PROJECT_SCAN.batch_size - 1, total)

  -- Scan this batch
  for i = start_idx, end_idx do
    local item = PROJECT_SCAN.all_items[i]
    if item and reaper.ValidatePtr(item, "MediaItem*") then
      -- Create a temporary row just to trigger metadata load and cache storage
      local row = collect_basic_fields(item)
      load_metadata_for_row(row)  -- This will populate cache
    end
  end

  PROJECT_SCAN.scanned_count = end_idx

  -- Log progress every 100 items
  if PROJECT_SCAN.scanned_count % 100 < PROJECT_SCAN.batch_size then
    local percent = math.floor((PROJECT_SCAN.scanned_count / total) * 100)
    console_forcef("[ILB] Project scan: %d/%d (%d%%)\n",
      PROJECT_SCAN.scanned_count, total, percent)
  end

  -- Complete?
  if PROJECT_SCAN.scanned_count >= total then
    local elapsed = reaper.time_precise() - PROJECT_SCAN.start_time
    console_forcef("[ILB] Project scan complete: %d items in %.2fs\n",
      total, elapsed)
    CACHE_LIB.flush()  -- Save cache to disk (shared library)
    PROJECT_SCAN.active = false
    return false  -- Done
  end

  return true  -- Continue
end

---------------------------------------
-- Progressive Loading System
---------------------------------------
local PROGRESSIVE = {
  active = false,           -- Is progressive loading in progress?
  items = {},               -- Cached sorted items to load
  loaded_count = 0,         -- How many items already loaded
  batch_size = 50,          -- Load N items per frame (adaptive)
  min_batch = 10,           -- Minimum batch size
  max_batch = 200,          -- Maximum batch size
  target_frame_time = 0.016, -- Target: ~60fps (16ms per frame)
  start_time = 0,           -- Time when loading started
  last_batch_time = 0,      -- Time last batch took
  selection_hash = "",      -- Hash to detect if selection changed during loading

  -- Two-phase loading
  phase = 1,                -- 1 = basic fields, 2 = metadata
  metadata_index = 0,       -- Index for phase 2 loading
}

-- Start progressive loading for current selection
local function start_progressive_load()
  -- ILB: load ALL project items (sorted), not just selected
  local items = get_all_project_items()
  table.sort(items, function(a, b)
    local sa, sb = item_start(a) or 0, item_start(b) or 0
    if math.abs(sa - sb) > 1e-9 then return sa < sb end
    local ta = item_track(a); local tb = item_track(b)
    local ia = ta and track_index(ta) or 0
    local ib = tb and track_index(tb) or 0
    if ia ~= ib then return ia < ib end
    return tostring(a) < tostring(b)
  end)
  PROGRESSIVE.items = items
  PROGRESSIVE.loaded_count = 0
  PROGRESSIVE.metadata_index = 0
  PROGRESSIVE.phase = 1
  PROGRESSIVE.active = (#PROGRESSIVE.items > 0)
  PROGRESSIVE.start_time = reaper.time_precise()

  -- Generate hash to detect project changes during load
  PROGRESSIVE.selection_hash = ILB.last_project_hash

  -- Clear current rows, show loading state
  ROWS = {}
  ILB.cached_rows_frame = -1
end

-- Process one batch of items (called every frame)
-- Returns: true if loading complete, false if still in progress
local function process_progressive_batch()
  if not PROGRESSIVE.active then return true end

  local batch_start = reaper.time_precise()
  local total = #PROGRESSIVE.items

  -- Phase 1: Load basic fields (FAST)
  if PROGRESSIVE.phase == 1 then
    local start_idx = PROGRESSIVE.loaded_count + 1
    local end_idx = math.min(start_idx + PROGRESSIVE.batch_size - 1, total)

    -- Load basic fields only
    for i = start_idx, end_idx do
      local item = PROGRESSIVE.items[i]
      if item and reaper.ValidatePtr(item, "MediaItem*") then
        ROWS[#ROWS + 1] = collect_basic_fields(item)  -- Fast!
      end
    end

    PROGRESSIVE.loaded_count = end_idx

    -- Phase 1 complete?
    if PROGRESSIVE.loaded_count >= total then
      PROGRESSIVE.phase = 2
      PROGRESSIVE.metadata_index = 0
      local elapsed = reaper.time_precise() - PROGRESSIVE.start_time
      reaper.ShowConsoleMsg(string.format("[ILB] Phase 1 complete: %d items in %.2fs (basic fields loaded)\n",
        total, elapsed))
    end
  -- Phase 2: Load metadata in background (SLOW)
  elseif PROGRESSIVE.phase == 2 then
    local start_idx = PROGRESSIVE.metadata_index + 1
    local end_idx = math.min(start_idx + PROGRESSIVE.batch_size - 1, total)

    -- Load metadata for this batch
    for i = start_idx, end_idx do
      if ROWS[i] then
        load_metadata_for_row(ROWS[i])
      end
    end

    PROGRESSIVE.metadata_index = end_idx
  end

  -- Measure and adapt batch size based on performance
  local batch_time = reaper.time_precise() - batch_start
  PROGRESSIVE.last_batch_time = batch_time

  -- Adaptive batch size: aim for target frame time
  if batch_time > PROGRESSIVE.target_frame_time * 1.2 then
    -- Too slow: reduce batch size by 20%
    PROGRESSIVE.batch_size = math.max(
      PROGRESSIVE.min_batch,
      math.floor(PROGRESSIVE.batch_size * 0.8)
    )
  elseif batch_time < PROGRESSIVE.target_frame_time * 0.5 then
    -- Too fast: increase batch size by 20%
    PROGRESSIVE.batch_size = math.min(
      PROGRESSIVE.max_batch,
      math.floor(PROGRESSIVE.batch_size * 1.2)
    )
  end

  -- Log progress
  if PROGRESSIVE.phase == 1 then
    -- Phase 1: log every 10 batches
    if PROGRESSIVE.loaded_count % (PROGRESSIVE.batch_size * 10) < PROGRESSIVE.batch_size then
      local percent = math.floor((PROGRESSIVE.loaded_count / total) * 100)
      reaper.ShowConsoleMsg(string.format("[ILB] Phase 1: %d/%d (%d%%) - batch size: %d\n",
        PROGRESSIVE.loaded_count, total, percent, PROGRESSIVE.batch_size))
    end
  elseif PROGRESSIVE.phase == 2 then
    -- Phase 2: log every 20 batches (less frequent)
    if PROGRESSIVE.metadata_index % (PROGRESSIVE.batch_size * 20) < PROGRESSIVE.batch_size then
      local percent = math.floor((PROGRESSIVE.metadata_index / total) * 100)
      reaper.ShowConsoleMsg(string.format("[ILB] Phase 2 (metadata): %d/%d (%d%%)\n",
        PROGRESSIVE.metadata_index, total, percent))
    end
  end

  -- Check if fully complete (phase 2 done)
  if PROGRESSIVE.phase == 2 and PROGRESSIVE.metadata_index >= total then
    PROGRESSIVE.active = false
    local elapsed = reaper.time_precise() - PROGRESSIVE.start_time
    -- Log completion time
    reaper.ShowConsoleMsg(string.format("[ILB] Fully completed: %d items in %.2fs (metadata loaded)\n",
      total, elapsed))

    -- Update cache to prevent immediate re-trigger
    LAST_SEL_COUNT = reaper.CountSelectedMediaItems(0)
    LAST_REFRESH_TIME = reaper.time_precise()
    NEEDS_REFRESH = false
    return true
  end

  return false
end

-- Check if selection changed during progressive loading
local function has_selection_changed_during_load()
  local count = reaper.CountSelectedMediaItems(0)
  if count ~= #PROGRESSIVE.items then return true end

  -- Use same indexing as start_progressive_load() to ensure hashes match
  local hash_parts = {}
  for i = 1, math.min(#PROGRESSIVE.items, 20) do
    local item = PROGRESSIVE.items[i]
    if item then
      local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      hash_parts[#hash_parts + 1] = guid
    end
  end
  local current_hash = table.concat(hash_parts, "|")

  return current_hash ~= PROGRESSIVE.selection_hash
end

---------------------------------------
-- State (UI)
---------------------------------------
AUTO = (AUTO == nil) and true or AUTO
local FRAME_COUNT = 0  -- Track frame count to skip operations on first frame

TABLE_SOURCE = "live"   -- "live"

-- Display mode state (persisted)
TIME_MODE = TFLib.MODE.MS        -- Default m:s; load_prefs() will override
CUSTOM_PATTERN = "hh:mm:ss"
FONT_SCALE = 1.0                 -- Default 1.0 (100%); load_prefs() will override

-- Data
ROWS = {}

-- === Sorting state (Excel-like) ===
local SORT_STATE = {
  columns = {},  -- Array of {col_id=N, ascending=true/false}, primary sort first
}

-- Get sort value for a row and column (for comparison)
local function get_sort_value(row, col_id)
  if col_id == 1 then return 0  -- # (row index) - will use array index
  elseif col_id == 2 then return row.track_idx or 0
  elseif col_id == 3 then return (row.track_name or ""):lower()
  elseif col_id == 4 then return (row.take_name or ""):lower()
  elseif col_id == 5 then return (row.item_note or ""):lower()
  elseif col_id == 6 then return (row.file_name or ""):lower()
  elseif col_id == 7 then return (row.meta_trk_name or ""):lower()
  elseif col_id == 8 then return tonumber(row.channel_num) or 0
  elseif col_id == 9 then return tonumber(row.interleave) or 0
  elseif col_id == 10 then return row.muted and 1 or 0
  elseif col_id == 11 then return row.color_hex or ""
  elseif col_id == 12 then return row.start_time or 0
  elseif col_id == 13 then return row.end_time or 0
  elseif col_id == 14 then return (row.umid or ""):lower()
  elseif col_id == 15 then return (row.umid_pt or ""):lower()
  elseif col_id == 16 then return (row.origination_date or ""):lower()
  elseif col_id == 17 then return (row.origination_time or ""):lower()
  elseif col_id == 18 then return (row.originator or ""):lower()
  elseif col_id == 19 then return (row.originator_ref or ""):lower()
  elseif col_id == 20 then return tonumber(row.time_reference) or 0
  elseif col_id == 21 then return (row.description or ""):lower()
  elseif col_id == 22 then return (row.project or ""):lower()
  elseif col_id == 23 then return (row.scene or ""):lower()
  elseif col_id == 24 then return (row.take_meta or ""):lower()
  elseif col_id == 25 then return (row.tape or ""):lower()
  elseif col_id == 26 then return (row.ubits or ""):lower()
  elseif col_id == 27 then return (row.framerate or ""):lower()
  elseif col_id == 28 then return (row.speed or ""):lower()
  elseif col_id == 29 then return (row.source_start or ""):lower()
  elseif col_id == 30 then return (row.source_end or ""):lower()
  elseif col_id == 31 then return row.length or 0
  end
  return ""
end

-- Multi-level sort comparator (Excel-like)
local function sort_rows_by_state(rows)
  if #SORT_STATE.columns == 0 then return end

  table.sort(rows, function(a, b)
    for _, sort_col in ipairs(SORT_STATE.columns) do
      local col_id = sort_col.col_id
      local asc = sort_col.ascending

      local val_a = get_sort_value(a, col_id)
      local val_b = get_sort_value(b, col_id)

      -- Handle different types
      local type_a = type(val_a)
      local type_b = type(val_b)

      if type_a ~= type_b then
        -- Different types: numbers first, then strings
        if type_a == "number" then return asc
        elseif type_b == "number" then return not asc
        end
      end

      -- Compare same types
      if val_a ~= val_b then
        if asc then
          return val_a < val_b
        else
          return val_a > val_b
        end
      end
      -- If equal, continue to next sort column
    end
    return false  -- All sort columns equal
  end)
end

-- Current formatter (rebuilt when mode or pattern changes)
FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=3})

-- === Inline edit state ===
local EDIT = { row = nil, col = nil, buf = "", want_focus = false }

-- === Selection model (Excel-like) & clipboard ===
local SEL = {
  cells = {},            -- set: ["<item_guid>:<col>"]=true
  anchor = nil,          -- { guid = "...", col = N }
}
local function _cell_key(guid, col) return (guid or "") .. ":" .. tostring(col or "") end
local function sel_clear() SEL.cells = {}; SEL.anchor = nil end
local function sel_has(guid, col) return SEL.cells[_cell_key(guid, col)] == true end
local function sel_add(guid, col) SEL.cells[_cell_key(guid, col)] = true end
local function sel_toggle(guid, col)
  local k = _cell_key(guid, col)
  SEL.cells[k] = not SEL.cells[k] or nil
end

-- Check if CmdOrCtrl / Shift modifiers are held
local function _mods()
  local mods = reaper.ImGui_GetKeyMods(ctx)
  local has = function(mask) return (mask ~= 0) and ((mods & mask) ~= 0) end
  local M = {
    ctrl  = has(reaper.ImGui_Mod_Ctrl and reaper.ImGui_Mod_Ctrl() or 0),
    super = has(reaper.ImGui_Mod_Super and reaper.ImGui_Mod_Super() or 0),
    shift = has(reaper.ImGui_Mod_Shift and reaper.ImGui_Mod_Shift() or 0),
    alt   = has(reaper.ImGui_Mod_Alt and reaper.ImGui_Mod_Alt() or 0),
  }
  M.shortcut = has(reaper.ImGui_Mod_Shortcut and reaper.ImGui_Mod_Shortcut() or 0) or M.ctrl or M.super
  return M
end
local function shortcut_pressed(key_const)
  local m = _mods()
  return m.shortcut and reaper.ImGui_IsKeyPressed(ctx, key_const, false)
end












-- Compute rectangular selection (between anchor and current guid,col)
local function sel_rect_apply(rows, row_index_map, cur_guid, cur_col)
  if not (SEL.anchor and SEL.anchor.guid and SEL.anchor.col) then
    SEL.anchor = { guid = cur_guid, col = cur_col }
    -- Clear selected cells only, keep anchor
    SEL.cells = {}; sel_add(cur_guid, cur_col)
    return
  end
  SEL.cells = {}
  local a_idx = row_index_map[SEL.anchor.guid] or 1
  local b_idx = row_index_map[cur_guid] or a_idx
  local r1, r2 = math.min(a_idx, b_idx), math.max(a_idx, b_idx)

  -- Compute rectangle by visual column positions, then map back to logical column IDs
  local p1 = (COL_POS and COL_POS[SEL.anchor.col]) or SEL.anchor.col
  local p2 = (COL_POS and COL_POS[cur_col])       or cur_col
  local c1, c2 = math.min(p1, p2), math.max(p1, p2)
  for i = r1, r2 do
    local g = rows[i].__item_guid
    for pos = c1, c2 do
      local logical_col = COL_ORDER[pos]
      if logical_col then sel_add(g, logical_col) end
    end
  end
end  -- end sel_rect_apply()

-- Helper function to escape special characters for TSV format
-- Note: TSV fields with newlines/tabs will be quoted by build_table_text()
-- We don't need to escape newlines - they'll be preserved in quoted fields
local function escape_for_tsv(text)
  if not text or text == "" then return "" end
  text = tostring(text)
  -- No escaping needed - build_table_text() will quote fields with special chars
  -- Just return the original text (newlines, tabs preserved)
  return text
end

-- Get display text for a cell (for copy; matches UI display)
local function get_cell_text(i, r, col, fmt)
  local text = ""

  if     col == 1  then text = tostring(i)
  elseif col == 2  then text = tostring(r.track_idx or "")
  elseif col == 3  then text = tostring(r.track_name or "")
  elseif col == 4  then text = tostring(r.take_name or "")
  elseif col == 5  then text = tostring(r.item_note or "")
  elseif col == 6  then text = tostring(r.file_name or "")
  elseif col == 7  then text = tostring(r.meta_trk_name or "")
  elseif col == 8  then text = tostring(r.channel_num or "")
  elseif col == 9  then text = tostring(r.interleave or "")
  elseif col == 10 then text = r.muted and "M" or ""
  elseif col == 11 then text = tostring(r.color_hex or "")
  elseif col == 12 then text = FORMAT(r.start_time)
  elseif col == 13 then text = FORMAT(r.end_time)
  -- New metadata columns
  elseif col == 14 then text = tostring(r.umid or "")
  elseif col == 15 then text = tostring(r.umid_pt or "")
  elseif col == 16 then text = tostring(r.origination_date or "")
  elseif col == 17 then text = tostring(r.origination_time or "")
  elseif col == 18 then text = tostring(r.originator or "")
  elseif col == 19 then text = tostring(r.originator_ref or "")
  elseif col == 20 then text = tostring(r.time_reference or "")
  elseif col == 21 then text = tostring(r.description or "")
  elseif col == 22 then text = tostring(r.project or "")
  elseif col == 23 then text = tostring(r.scene or "")
  elseif col == 24 then text = tostring(r.take_meta or "")
  elseif col == 25 then text = tostring(r.tape or "")
  elseif col == 26 then text = tostring(r.ubits or "")
  elseif col == 27 then text = tostring(r.framerate or "")
  elseif col == 28 then text = tostring(r.speed or "")
  -- Source position columns (from TimeReference)
  elseif col == 29 then text = tostring(r.source_start or "")
  elseif col == 30 then text = tostring(r.source_end or "")
  -- Length column
  elseif col == 31 then text = FORMAT(r.length)
  -- File info columns
  elseif col == 32 then text = tostring(r.sample_rate or "")
  elseif col == 33 then text = tostring(r.bit_depth or "")
  elseif col == 34 then text = tostring(r.file_type or "")
  end

  -- For TSV format, escape special characters to prevent format corruption
  if fmt == "tsv" then
    return escape_for_tsv(text)
  end

  return text
end



-- Delegate to Library: return visible rows (honors Show muted items toggle)
local function get_view_rows()
  -- ILB: per-frame cache to avoid recalculating filters multiple times
  if ILB.cached_rows_frame == FRAME_COUNT then
    return ILB.cached_rows
  end

  local search_lower = ILB.search_text ~= "" and ILB.search_text:lower() or nil

  local result = LT.filter_rows(ROWS, {
    show_muted = SHOW_MUTED_ITEMS,
    predicate = function(row)
      -- Filter: Only selected items
      if ILB.only_selected then
        local item = row.__item
        if not item or not reaper.ValidatePtr(item, "MediaItem*") then return false end
        if not reaper.IsMediaItemSelected(item) then return false end
      end
      -- Filter: Track
      if ILB.track_index > 0 then
        if (row.track_idx or 0) ~= ILB.track_index then return false end
      end
      -- Filter: Text search
      if search_lower then
        if not (row.__search_text or ""):find(search_lower, 1, true) then return false end
      end
      return true
    end
  })

  ILB.cached_rows = result
  ILB.cached_rows_frame = FRAME_COUNT
  return result
end


-- === ILB: Selection Link ===

-- List → REAPER: sync table selection to REAPER item selection
local function sync_list_selection_to_reaper()
  ILB.sel_source = "list"
  ILB.sel_cooldown = reaper.time_precise()

  -- Unselect all items in REAPER
  reaper.Main_OnCommand(40289, 0)  -- Item: Unselect all items

  -- Collect unique GUIDs from SEL.cells
  local selected_guids = {}
  for key, _ in pairs(SEL.cells) do
    local guid = key:match("^(.+):%d+$")
    if guid and guid ~= "" then selected_guids[guid] = true end
  end

  -- Select matching items in REAPER
  for _, row in ipairs(ROWS) do
    if selected_guids[row.__item_guid] then
      local item = row.__item
      if item and reaper.ValidatePtr(item, "MediaItem*") then
        reaper.SetMediaItemSelected(item, true)
      end
    end
  end

  reaper.UpdateArrange()

  -- Follow Selection: scroll arrange view to selected item (native API, no SWS needed)
  if ILB.follow then
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item and reaper.ValidatePtr(item, "MediaItem*") then
      -- Horizontal scroll: center item position in arrange view
      local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
      local item_mid = item_pos + item_len * 0.5
      local arr_start, arr_end = reaper.GetSet_ArrangeView2(0, false, 0, 0)
      local view_span = arr_end - arr_start
      local new_start = item_mid - view_span * 0.5
      reaper.GetSet_ArrangeView2(0, true, 0, 0, new_start, new_start + view_span)
      -- Vertical scroll: bring selected track into view
      reaper.Main_OnCommand(40913, 0)  -- Track: Vertical scroll selected tracks into view
    end
  end

  -- Update REAPER selection hash so sync_reaper_selection_to_list()
  -- won't detect a false change and trigger unwanted table auto-scroll
  local sel_count = reaper.CountSelectedMediaItems(0)
  local hp = { tostring(sel_count) }
  for s = 0, math.min(sel_count - 1, 9) do
    local item = reaper.GetSelectedMediaItem(0, s)
    if item then
      local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      hp[#hp + 1] = guid
    end
  end
  if sel_count > 10 then
    local item = reaper.GetSelectedMediaItem(0, sel_count - 1)
    if item then
      local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      hp[#hp + 1] = guid
    end
  end
  ILB.last_reaper_sel_hash = table.concat(hp, "|")
end

-- REAPER → List: sync REAPER selection to table highlight
local function sync_reaper_selection_to_list()
  local now = reaper.time_precise()
  -- Guard: don't sync during cooldown after list-initiated selection
  if ILB.sel_source == "list" and (now - ILB.sel_cooldown) < ILB.sel_cooldown_ms then
    return
  end

  -- Build hash of current REAPER selection
  local sel_count = reaper.CountSelectedMediaItems(0)
  local hash_parts = { tostring(sel_count) }
  for s = 0, math.min(sel_count - 1, 9) do  -- sample first 10 for speed
    local item = reaper.GetSelectedMediaItem(0, s)
    if item then
      local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      hash_parts[#hash_parts + 1] = guid
    end
  end
  -- Also add last item GUID for better change detection
  if sel_count > 10 then
    local item = reaper.GetSelectedMediaItem(0, sel_count - 1)
    if item then
      local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      hash_parts[#hash_parts + 1] = guid
    end
  end
  local hash = table.concat(hash_parts, "|")

  if hash == ILB.last_reaper_sel_hash then return end
  ILB.last_reaper_sel_hash = hash
  ILB.sel_source = nil

  -- Build set of selected GUIDs in REAPER
  local reaper_sel = {}
  for s = 0, sel_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, s)
    if item then
      local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      reaper_sel[guid] = true
    end
  end

  -- Clear table selection and highlight full rows for selected items
  sel_clear()
  local view_rows = get_view_rows()
  local first_match = nil
  for idx, row in ipairs(view_rows) do
    if reaper_sel[row.__item_guid] then
      if not first_match then first_match = idx end
      -- Select all visible columns for this row (full-row highlight)
      for disp = 1, #COL_ORDER do
        local col_id = COL_ORDER[disp]
        if col_id then sel_add(row.__item_guid, col_id) end
      end
      -- Set anchor on first match
      if not SEL.anchor then
        SEL.anchor = { guid = row.__item_guid, col = COL_ORDER[1] or 1 }
      end
    end
  end

  -- Auto-scroll to first matched row
  if first_match then
    ILB.scroll_to_row = first_match
  end
end


-- === Column order mapping (visual <-> logical) & header text ===
-- COL_ORDER[display_index] = logical_col_id
-- COL_POS[logical_col_id]  = display_index

local function header_label_from_id(col_id)
  if col_id == 1  then return "#" end
  if col_id == 2  then return "TrkID" end
  if col_id == 3  then return "Track Name" end
  if col_id == 4  then return "Take Name" end
  if col_id == 5  then return "Item Note" end
  if col_id == 6  then return "Source File" end
  if col_id == 7  then return "Meta Trk Name" end
  if col_id == 8  then return "Chan#" end
  if col_id == 9  then return "Int#" end
  if col_id == 10 then return "Mute" end
  if col_id == 11 then return "Color" end
  if col_id == 12 or col_id == 13 then
    local sh, eh = TFLib.headers(TIME_MODE, {pattern=CUSTOM_PATTERN})
    return (col_id == 12) and sh or eh
  end
  -- New metadata columns
  if col_id == 14 then return "UMID" end
  if col_id == 15 then return "UMID (PT)" end
  if col_id == 16 then return "Origination Date" end
  if col_id == 17 then return "Origination Time" end
  if col_id == 18 then return "Originator" end
  if col_id == 19 then return "Originator Ref" end
  if col_id == 20 then return "Time Reference" end
  if col_id == 21 then return "Description" end
  if col_id == 22 then return "PROJECT" end
  if col_id == 23 then return "SCENE" end
  if col_id == 24 then return "TAKE" end
  if col_id == 25 then return "TAPE" end
  if col_id == 26 then return "UBITS" end
  if col_id == 27 then return "FRAMERATE" end
  if col_id == 28 then return "SPEED" end
  -- Source position columns (TC format, from TimeReference)
  if col_id == 29 then return "Source Start (TC)" end
  if col_id == 30 then return "Source End (TC)" end
  -- Length column
  if col_id == 31 then return "Length" end
  -- File info columns
  if col_id == 32 then return "Sample Rate" end
  if col_id == 33 then return "Bit Depth" end
  if col_id == 34 then return "File Type" end
  return tostring(col_id)
end

-- === Header label helpers (for mapping display order) ===
-- Map logical column IDs to header labels; 12/13 Start/End use dynamic FORMAT headers
local HEADER_BY_ID = {
  [1]  = "#",
  [2]  = "TrkID",
  [3]  = "Track Name",
  [4]  = "Take Name",
  [5]  = "Item Note",
  [6]  = "Source File",
  [7]  = "Meta Trk Name",
  [8]  = "Chan#",
  [9]  = "Int#",
  [10] = "Mute",
  [11] = "Color",
  [12] = nil,  -- Start (dynamic)
  [13] = nil,  -- End   (dynamic)
}

local function current_start_label()
  -- Same logic as header rendering / TFLib
  if TIME_MODE == TFLib.MODE.MS      then return "Start (m:s)"
  elseif TIME_MODE == TFLib.MODE.TC  then return "Start (TC)"
  elseif TIME_MODE == TFLib.MODE.BEATS then return "Start (Beats)"
  elseif TIME_MODE == TFLib.MODE.CUSTOM then return ("Start (%s)"):format(CUSTOM_PATTERN or "")
  else return "Start (s)" end
end

local function current_end_label()
  if TIME_MODE == TFLib.MODE.MS      then return "End (m:s)"
  elseif TIME_MODE == TFLib.MODE.TC  then return "End (TC)"
  elseif TIME_MODE == TFLib.MODE.BEATS then return "End (Beats)"
  elseif TIME_MODE == TFLib.MODE.CUSTOM then return ("End (%s)"):format(CUSTOM_PATTERN or "")
  else return "End (s)" end
end


local function label_for_id(id)
  if id == 12 then return current_start_label()
  elseif id == 13 then return current_end_label()
  else return HEADER_BY_ID[id] end
end



local function _colid_from_label(label)
  -- Time column headers are dynamic; get current Start/End labels for matching
  local sh, eh = TFLib.headers(TIME_MODE, {pattern=CUSTOM_PATTERN})
  if label == "#"                then return 1 end
  if label == "TrkID"            then return 2 end
  if label == "Track Name"       then return 3 end
  if label == "Take Name"        then return 4 end
  if label == "Item Note"        then return 5 end
  if label == "Source File"      then return 6 end
  if label == "Meta Trk Name"    then return 7 end
  if label == "Chan#"            then return 8 end
  if label == "Interleave"       then return 9 end
  if label == "Mute"             then return 10 end
  if label == "Color"            then return 11 end
  if label == sh                 then return 12 end
  if label == eh                 then return 13 end
  return nil
end

-- Read display column order -> COL_ORDER / COL_POS
-- COL_ORDER[display_pos] = logical_col_id
-- COL_POS[logical_col_id] = display_pos
local __last_dump = nil
local function orders_differ(a, b)
  if not a or not b or #a ~= #b then return true end
  for i=1,#a do if a[i] ~= b[i] then return true end end
  return false
end

local function dump_order_if_changed(tag)
  local parts = {}
  for i,id in ipairs(COL_ORDER or {}) do parts[#parts+1] = string.format("%d:%s", i, tostring(id)) end
  local s = "["..(tag or "ORDER").."] "..table.concat(parts, ", ")
  if s ~= __last_dump then
    reaper.ShowConsoleMsg(s.."\n")
    __last_dump = s
  end
end

-- Column order is now managed through Preset system
-- Users edit column order/visibility in Preset Editor, not by dragging in table




-- Expand from source shape and single anchor cell to produce destination cell list (row-major, left to right)
local function build_dst_by_anchor_and_shape(rows, anchor_desc, src_rows, src_cols)
  local dst = {}
  for i = 0, src_rows - 1 do
    local ri = (anchor_desc.row_index or 1) + i
    if ri >= 1 and ri <= #rows then
      local r = rows[ri]
      for j = 0, src_cols - 1 do
        local col = (anchor_desc.col or 1) + j
        dst[#dst+1] = { row_index = ri, col = col, row = r }
      end
    end
  end
  -- Sort by visual column order (consistent with COL_ORDER/COL_POS)
  table.sort(dst, function(a,b)
    if a.row_index ~= b.row_index then return a.row_index < b.row_index end
    local pa = (COL_POS and COL_POS[a.col]) or a.col
    local pb = (COL_POS and COL_POS[b.col]) or b.col
    return pa < pb
  end)
  return dst
end

-- Expand from source shape and single anchor, targeting only writable columns 3/4/5
local function build_dst_spill_writable(rows, anchor_desc, src_rows, src_cols)
  local dst = {}
  local writable = {3,4,5}
  -- Find first writable column >= anchor col; if none (e.g. anchor at 6), use last one (5)
  local start_idx
  for idx, c in ipairs(writable) do
    if c >= (anchor_desc.col or 3) then start_idx = idx; break end
  end
  if not start_idx then start_idx = #writable end

  for i = 0, src_rows - 1 do
    local ri = (anchor_desc.row_index or 1) + i
    if ri >= 1 and ri <= #rows then
      local r = rows[ri]
      for j = 0, src_cols - 1 do
        local wi = start_idx + j
        if wi > #writable then break end  -- truncate beyond writable columns
        local col = writable[wi]
        dst[#dst+1] = { row_index = ri, col = col, row = r }
      end
    end
  end

  table.sort(dst, function(a,b)
    if a.row_index ~= b.row_index then return a.row_index < b.row_index end
    return a.col < b.col
  end)
  return dst
end




-- === Undo/Redo selection protection (GUID snapshot) ===
local function _snapshot_selected_item_guids()
  local list = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    list[#list+1] = g
  end
  return list
end

local function _restore_item_selection_by_guids(guids)
  if not guids or #guids == 0 then return end
  -- Clear current selection first
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  -- Build lookup table for fast matching
  local want = {}
  for _, g in ipairs(guids) do if g and g ~= "" then want[g] = true end end
  -- Scan project items and re-select by GUID match
  local total = reaper.CountMediaItems(0)
  for i = 0, total-1 do
    local it = reaper.GetMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if want[g] then reaper.SetMediaItemSelected(it, true) end
  end
  reaper.UpdateArrange()
end




-- Mark as needing refresh (must be defined early - used by multiple functions)
local function mark_dirty()
  NEEDS_REFRESH = true
end

-- Bulk-commit (single Undo, UpdateArrange/Refresh at end)
local BULK = false
local function bulk_begin() BULK = true end
local function bulk_end(refresh_cb)
  BULK = false
  reaper.UpdateArrange()
  if type(refresh_cb) == "function" then refresh_cb() end
end


-- Delete selected cell text (live view only; only columns 3/4/5 are writable)
local function delete_selected_cells()
  -- 0) No selection, bail out
  if not SEL or not SEL.cells or next(SEL.cells) == nil then return end

  -- 1) Visible rows + expand selection by visual column order
  local rows = get_view_rows()                              -- replaces ROWS
  local dst = LT.build_dst_list_from_selection(rows, sel_has, COL_ORDER, COL_POS)
  if #dst == 0 then return end

  reaper.Undo_BeginBlock2(0)
  local affected_guids = {}
  for i = 1, #dst do
    local d = dst[i]
    local r = rows[d.row_index]             -- get row by index
    local col = d.col
    if col == 3 then
      local tr = r.track or r.__track
      if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
        reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", true)
        r.track_name = ""
      end
    elseif col == 4 then
      local tk = r.take or r.__take or (r.item or r.__item)
          and reaper.GetActiveTake(r.item or r.__item)
      if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") then
        reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", true)
        r.take_name = ""
      end
    elseif col == 5 then
      local it = r.item or r.__item
      if it and reaper.ValidatePtr(it, "MediaItem*") then
        reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", true)
        r.item_note = ""
      end
    end
    -- Collect affected item GUIDs
    if r and r.__item_guid then
      affected_guids[#affected_guids+1] = r.__item_guid
    end
  end
  reaper.Undo_EndBlock2(0, "[ILB] Clear selected cells", 4|1)  -- UNDO_STATE_ITEMS | UNDO_STATE_TRACKCFG

  -- Invalidate cache and immediately refresh affected rows
  CACHE_LIB.invalidate_items(affected_guids)
  refresh_rows_by_guids(affected_guids)  -- Immediate visual feedback

  reaper.UpdateArrange()
  -- No need for mark_dirty() - rows already refreshed
end






local COL = { TRACK_NAME = 3, TAKE_NAME = 4, ITEM_NOTE = 5 } -- header column order: #, TrkID, Track Name, Take Name, Item Note, Source File...

function _trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function _commit_if_changed(label, oldv, newv, fn_apply)
  newv = _trim(newv or "")
  oldv = tostring(oldv or "")
  if newv == oldv then return false end
  if BULK then
    fn_apply(newv)
  else
    reaper.Undo_BeginBlock2(0)
    fn_apply(newv)
    reaper.Undo_EndBlock2(0, "[ILB] "..label, 4|1)  -- UNDO_STATE_ITEMS | UNDO_STATE_TRACKCFG
    reaper.UpdateArrange()
  end
  mark_dirty()  -- Mark refresh needed after edit
  return true
end


-- Write back: Track / Take / Item Note
local function apply_track_name(tr, newname, rows)
  _commit_if_changed("Rename Track", select(2, reaper.GetTrackName(tr, "")), newname, function(v)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", v, true)
    -- Sync all rows of the same track (by object, not by name)
    for _, rr in ipairs(rows or {}) do
      if rr.__track == tr then rr.track_name = v end
    end
  end)
end

local function apply_take_name(tk, newname, row)
  if not tk then return end
  local changed = _commit_if_changed("Rename Take", row.take_name, newname, function(v)
    reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", v, true)
    row.take_name = v
  end)
  -- Invalidate cache and immediately refresh if changed
  if changed and row.__item_guid then
    CACHE_LIB.invalidate_items({row.__item_guid})
    refresh_rows_by_guids({row.__item_guid})  -- Immediate visual feedback
  end
end

local function apply_item_note(it, newnote, row)
  local changed = _commit_if_changed("Edit Item Note", row.item_note, newnote, function(v)
    reaper.GetSetMediaItemInfo_String(it, "P_NOTES", v, true)
    row.item_note = v
  end)
  -- Invalidate cache and immediately refresh if changed
  if changed and row.__item_guid then
    CACHE_LIB.invalidate_items({row.__item_guid})
    refresh_rows_by_guids({row.__item_guid})  -- Immediate visual feedback
  end
end




-- Thin wrapper (for compatibility; table/export can also call FORMAT(r.start_time) directly)
local function format_time(val) return FORMAT(val) end

----------------------------------------
-- Auto-refresh optimization
----------------------------------------
-- Cache last selection state to avoid rescanning every frame
local LAST_SEL_COUNT = 0
local LAST_SEL_HASH = ""
local LAST_REFRESH_TIME = -1  -- -1 to trigger first refresh immediately
local REFRESH_THROTTLE = 0.1  -- Max refresh rate: 100ms (10 fps)
local NEEDS_REFRESH = false   -- Dirty flag

-- Fast check if selection changed (only count + GUID hash, no full scan)
local function has_selection_changed()
  local count = reaper.CountSelectedMediaItems(0)
  if count ~= LAST_SEL_COUNT then return true end
  if count == 0 then return false end

  -- Only check GUIDs when count is same (avoid perf hit with large selections)
  -- For large selections (>100 items), only check first 10 and last 10 GUIDs
  local hash_parts = {}

  if count <= 100 then
    -- Small selection: check all GUIDs
    for i = 0, count - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        hash_parts[#hash_parts + 1] = guid
      end
    end
  else
    -- Large selection: only check first 10 and last 10
    for i = 0, 9 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        hash_parts[#hash_parts + 1] = guid
      end
    end
    for i = count - 10, count - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        hash_parts[#hash_parts + 1] = guid
      end
    end
  end

  local hash = table.concat(hash_parts, "|")
  if hash ~= LAST_SEL_HASH then
    LAST_SEL_HASH = hash
    return true
  end

  return false
end

-- Update cache
local function update_selection_cache()
  LAST_SEL_COUNT = reaper.CountSelectedMediaItems(0)
  LAST_REFRESH_TIME = reaper.time_precise()
  NEEDS_REFRESH = false

  -- Also update hash to prevent re-trigger
  local count = LAST_SEL_COUNT
  if count == 0 then
    LAST_SEL_HASH = ""
    return
  end

  local hash_parts = {}
  if count <= 100 then
    for i = 0, count - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        hash_parts[#hash_parts + 1] = guid
      end
    end
  else
    for i = 0, 9 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        hash_parts[#hash_parts + 1] = guid
      end
    end
    for i = count - 10, count - 1 do
      local item = reaper.GetSelectedMediaItem(0, i)
      if item then
        local _, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
        hash_parts[#hash_parts + 1] = guid
      end
    end
  end
  LAST_SEL_HASH = table.concat(hash_parts, "|")
end

-- Immediate full refresh (for manual "Refresh Now" button)
function refresh_now()
  -- ILB: load ALL project items (not just selected)
  ROWS = scan_all_project_rows()
  update_project_cache()
  build_track_list()  -- Rebuild track list for filter dropdown
  ILB.cached_rows_frame = -1  -- Invalidate filter cache
  PROGRESSIVE.active = false
end

-- Start progressive refresh for large projects
local function refresh_progressive()
  -- Count all project items
  local count = 0
  local track_count = reaper.CountTracks(0)
  for t = 0, track_count - 1 do
    count = count + reaper.CountTrackMediaItems(reaper.GetTrack(0, t))
  end

  if count < 100 then
    refresh_now()
    return
  end

  start_progressive_load()
  update_project_cache()
  build_track_list()
end

-- Smart refresh: only execute when truly needed
-- ILB: No periodic polling. Refresh is triggered only by:
--   1. NEEDS_REFRESH flag (boot, Refresh Now, mark_dirty after edit/paste/delete/clear cache)
--   2. Progressive loading continuation (process remaining batches)
local function smart_refresh()
  -- If progressive loading is active, continue processing batches
  if PROGRESSIVE.active then
    process_progressive_batch()
    return
  end

  -- Only refresh when explicitly requested (no periodic polling)
  if NEEDS_REFRESH then
    NEEDS_REFRESH = false
    refresh_progressive()
  end
end

-- Restore last mode and pattern on startup, then rebuild FORMAT
if load_prefs then load_prefs() end

-- Set font size after loading preferences
if set_font_size and FONT_SCALE then
  local size = math.floor(13 * FONT_SCALE)
  set_font_size(size)
end


local function build_summary_text(rows)
  local S = LT.compute_summary(rows or {})
  if not S or (S.count or 0) == 0 then return "No items." end
  local from = format_time(S.min_start)
  local to   = format_time(S.max_end)
  local span = format_time(S.span)
  local sum  = format_time(S.sum_len)
  return table.concat({
    ("Number of items:\n%d"):format(S.count),
    "",
    ("Total span (first to last):\n%s"):format(span),
    "",
    ("Sum of lengths:\n%s"):format(sum),
    "",
    ("Range:\n%s - %s"):format(from, to),
  }, "\n")
end

local function draw_summary_popup()
  if reaper.ImGui_BeginPopupModal(ctx, POPUP_TITLE, true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    -- Pick rows from current display source
    local rows = ROWS

    local txt = build_summary_text(rows)

    -- Selectable and copyable: read-only multiline input
    reaper.ImGui_SetNextItemWidth(ctx, scale(560))
    reaper.ImGui_InputTextMultiline(ctx, "##summary_text", txt, scale(560), scale(200),
      reaper.ImGui_InputTextFlags_ReadOnly())

    -- Copy / OK
    if reaper.ImGui_Button(ctx, "Copy", scale(80), scale(24)) then
      reaper.ImGui_SetClipboardText(ctx, txt)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "OK", scale(80), scale(24))
       or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end

-- Advanced Sort dialog (Excel-like multi-level sort)
-- State for add column combo box
local ADVANCED_SORT_STATE = ADVANCED_SORT_STATE or {
  selected_col_id = 1,  -- Currently selected column in combo
  combo_preview = ""
}

local function draw_advanced_sort_popup()
  if reaper.ImGui_BeginPopupModal(ctx, "Advanced Sort", true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    reaper.ImGui_Text(ctx, "Multi-level sort configuration")
    reaper.ImGui_Separator(ctx)

    -- Add column section
    reaper.ImGui_Text(ctx, "Add sort column:")
    reaper.ImGui_SameLine(ctx)

    -- Build list of available columns (following COL_ORDER)
    local available_cols = COL_ORDER and #COL_ORDER > 0 and COL_ORDER or {
      1, 2, 3, 12, 13, 31, 4, 5, 6, 7, 8, 9, 10, 11,
      14, 15, 16, 17, 18, 19, 20, 21,
      22, 23, 24, 25, 26, 27, 28, 29, 30
    }

    -- Update combo preview
    ADVANCED_SORT_STATE.combo_preview = header_label_from_id(ADVANCED_SORT_STATE.selected_col_id) or "Column " .. ADVANCED_SORT_STATE.selected_col_id

    -- Combo box
    reaper.ImGui_SetNextItemWidth(ctx, scale(200))
    if reaper.ImGui_BeginCombo(ctx, "##add_col_combo", ADVANCED_SORT_STATE.combo_preview) then
      for _, col_id in ipairs(available_cols) do
        local label = header_label_from_id(col_id) or "Column " .. col_id
        local is_selected = (ADVANCED_SORT_STATE.selected_col_id == col_id)
        if reaper.ImGui_Selectable(ctx, label, is_selected) then
          ADVANCED_SORT_STATE.selected_col_id = col_id
        end
        if is_selected then
          reaper.ImGui_SetItemDefaultFocus(ctx)
        end
      end
      reaper.ImGui_EndCombo(ctx)
    end

    -- Add button
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+ Add", scale(60), scale(24)) then
      -- Check if column already exists in sort
      local already_exists = false
      for _, sort_col in ipairs(SORT_STATE.columns) do
        if sort_col.col_id == ADVANCED_SORT_STATE.selected_col_id then
          already_exists = true
          break
        end
      end

      if not already_exists then
        table.insert(SORT_STATE.columns, {
          col_id = ADVANCED_SORT_STATE.selected_col_id,
          ascending = true
        })
        sort_rows_by_state(ROWS)
      end
    end

    reaper.ImGui_Separator(ctx)

    -- Display current sort columns
    if #SORT_STATE.columns > 0 then
      reaper.ImGui_Text(ctx, "Current sort order:")
      reaper.ImGui_Indent(ctx, 20)

      for i, sort_col in ipairs(SORT_STATE.columns) do
        reaper.ImGui_PushID(ctx, i)

        local label = header_label_from_id(sort_col.col_id) or "Column " .. sort_col.col_id
        local dir = sort_col.ascending and "Ascending" or "Descending"
        reaper.ImGui_Text(ctx, string.format("%d. %s (%s)", i, label, dir))

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Toggle", 60, 20) then
          sort_col.ascending = not sort_col.ascending
          sort_rows_by_state(ROWS)
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Remove", 60, 20) then
          table.remove(SORT_STATE.columns, i)
          sort_rows_by_state(ROWS)
        end

        -- Move up/down buttons
        reaper.ImGui_SameLine(ctx)
        if i > 1 and reaper.ImGui_Button(ctx, "▲", 25, 20) then
          SORT_STATE.columns[i], SORT_STATE.columns[i-1] = SORT_STATE.columns[i-1], SORT_STATE.columns[i]
          sort_rows_by_state(ROWS)
        end

        reaper.ImGui_SameLine(ctx)
        if i < #SORT_STATE.columns and reaper.ImGui_Button(ctx, "▼", 25, 20) then
          SORT_STATE.columns[i], SORT_STATE.columns[i+1] = SORT_STATE.columns[i+1], SORT_STATE.columns[i]
          sort_rows_by_state(ROWS)
        end

        reaper.ImGui_PopID(ctx)
      end

      reaper.ImGui_Unindent(ctx, 20)
    else
      reaper.ImGui_TextDisabled(ctx, "No sort applied. Click column headers to sort.")
    end

    reaper.ImGui_Separator(ctx)

    -- Buttons
    if reaper.ImGui_Button(ctx, "Clear All", scale(100), scale(24)) then
      SORT_STATE.columns = {}
      -- Don't sort yet - just clear the state
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Apply", scale(100), scale(24)) then
      sort_rows_by_state(ROWS)
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Close", scale(100), scale(24))
       or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end




---------------------------------------
-- Export helpers
---------------------------------------


---------------------------------------
-- UI
---------------------------------------
local function draw_toolbar()
  -- Show item count with loading progress if applicable
  local status_text
  if PROGRESSIVE.active then
    local total = #PROGRESSIVE.items
    if PROGRESSIVE.phase == 1 then
      local loaded = PROGRESSIVE.loaded_count
      local percent = math.floor((loaded / total) * 100)
      status_text = string.format("Loading: %d/%d (%d%%)", loaded, total, percent)
    elseif PROGRESSIVE.phase == 2 then
      local loaded = PROGRESSIVE.metadata_index
      local percent = math.floor((loaded / total) * 100)
      status_text = string.format("Items: %d | Loading metadata: %d%%", total, percent)
    end
  else
    local view_count = ILB.cached_rows and #ILB.cached_rows or #ROWS
    status_text = string.format("Project items: %d | Showing: %d", #ROWS, view_count)
  end
  reaper.ImGui_Text(ctx, status_text)
  reaper.ImGui_SameLine(ctx)
  local chg, v = reaper.ImGui_Checkbox(ctx, "Auto-refresh", AUTO)
  if chg then
    AUTO = v
    reaper.SetExtState(EXT_NS, "auto_refresh", v and "1" or "0", true)
  end
  reaper.ImGui_SameLine(ctx)

-- Show muted items (hides muted rows; affects current table and export)
local changed, nv = reaper.ImGui_Checkbox(ctx, "Show muted items", SHOW_MUTED_ITEMS)
reaper.ImGui_SameLine(ctx)
if changed then
  SHOW_MUTED_ITEMS = nv
  EDIT = nil
  sel_clear()
  ILB.cached_rows = nil; ILB.cached_rows_frame = -1
end

-- ILB: Only Selected filter
do
  local chg_os, nv_os = reaper.ImGui_Checkbox(ctx, "Only Selected", ILB.only_selected)
  reaper.ImGui_SameLine(ctx)
  if chg_os then
    ILB.only_selected = nv_os
    ILB.cached_rows = nil; ILB.cached_rows_frame = -1
    sel_clear()
  end
end

-- ILB: Follow Selection
do
  local chg_fs, nv_fs = reaper.ImGui_Checkbox(ctx, "Follow Selection", ILB.follow)
  reaper.ImGui_SameLine(ctx)
  if chg_fs then
    ILB.follow = nv_fs
    save_prefs()
  end
end

-- ILB: Track filter dropdown
do
  reaper.ImGui_Text(ctx, "Track:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(160))
  local preview = ILB.track_index == 0 and "All Tracks" or
    (ILB.track_list[ILB.track_index] and ILB.track_list[ILB.track_index].name or "Track " .. ILB.track_index)
  if reaper.ImGui_BeginCombo(ctx, "##ilb_track_filter", preview) then
    if reaper.ImGui_Selectable(ctx, "All Tracks", ILB.track_index == 0) then
      ILB.track_index = 0
      ILB.cached_rows = nil; ILB.cached_rows_frame = -1
      sel_clear()
    end
    for _, trk in ipairs(ILB.track_list) do
      local label = string.format("%d: %s", trk.index, trk.name)
      if reaper.ImGui_Selectable(ctx, label, ILB.track_index == trk.index) then
        ILB.track_index = trk.index
        ILB.cached_rows = nil; ILB.cached_rows_frame = -1
        sel_clear()
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
  reaper.ImGui_SameLine(ctx)
end

-- ILB: Search filter
do
  reaper.ImGui_Text(ctx, "Search:")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, scale(160))
  local chg_s, new_s = reaper.ImGui_InputText(ctx, "##ilb_search", ILB.search_text)
  if chg_s then
    ILB.search_text = new_s
    ILB.cached_rows = nil; ILB.cached_rows_frame = -1
    sel_clear()
  end
  reaper.ImGui_SameLine(ctx)
  if ILB.search_text ~= "" then
    if reaper.ImGui_Button(ctx, "X##ilb_clear_search", scale(20), scale(20)) then
      ILB.search_text = ""
      ILB.cached_rows = nil; ILB.cached_rows_frame = -1
    end
    reaper.ImGui_SameLine(ctx)
  end
end

-- Four modes: m:s / TC / Beats / Custom (input field right after Custom)
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "m:s", TIME_MODE==TFLib.MODE.MS) then
  TIME_MODE = TFLib.MODE.MS
  FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=3})
  save_prefs()
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "TC", TIME_MODE==TFLib.MODE.TC) then
  TIME_MODE = TFLib.MODE.TC
  FORMAT = TFLib.make_formatter(TIME_MODE)
  save_prefs()
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "Beats", TIME_MODE==TFLib.MODE.BEATS) then
  TIME_MODE = TFLib.MODE.BEATS
  FORMAT = TFLib.make_formatter(TIME_MODE)
  save_prefs()
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "Custom", TIME_MODE==TFLib.MODE.CUSTOM) then
  TIME_MODE = TFLib.MODE.CUSTOM
  FORMAT = TFLib.make_formatter(TIME_MODE, {pattern=CUSTOM_PATTERN})
  save_prefs()
end
-- Input field placed right after Custom radio button
reaper.ImGui_SameLine(ctx)
reaper.ImGui_Text(ctx, "Pattern:")
reaper.ImGui_SameLine(ctx)
reaper.ImGui_SetNextItemWidth(ctx, scale(180))
local changed, newpat = reaper.ImGui_InputText(ctx, "##custom_pattern", CUSTOM_PATTERN)
if changed then
  CUSTOM_PATTERN = newpat
  if TIME_MODE==TFLib.MODE.CUSTOM then
    FORMAT = TFLib.make_formatter(TIME_MODE, {pattern=CUSTOM_PATTERN})
  end
  save_prefs()
end
-- Info tooltip (shown on hover)
reaper.ImGui_SameLine(ctx)
reaper.ImGui_TextDisabled(ctx, "ⓘ")
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  reaper.ImGui_Text(ctx, "Tokens: h | hh | m | mm | s | ss | S… (e.g. SSS = .mmm)")
  reaper.ImGui_EndTooltip(ctx)
end

-- Cache management button
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Clear Cache", scale(100), scale(24)) then
  -- Show confirmation dialog
  local cache_stats = CACHE_LIB.get_stats()
  local cached_count = cache_stats.item_count or 0

  local msg = string.format(
    "Clear metadata cache?\n\n" ..
    "Current cache:\n" ..
    "• %d items cached\n\n" ..
    "This will:\n" ..
    "• Delete all cached metadata\n" ..
    "• Metadata will be re-read from files on next selection\n\n" ..
    "Continue?",
    cached_count
  )

  local result = reaper.ShowMessageBox(msg, "Clear Cache", 1)  -- 1 = OK/Cancel
  if result == 1 then  -- OK
    CACHE_LIB.clear()
    mark_dirty()  -- Trigger refresh to rebuild cache
  end
end
-- Show cache stats on hover
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  local total = CACHE.hits + CACHE.misses
  local hit_rate = (total > 0) and math.floor((CACHE.hits / total) * 100) or 0
  local cache_stats = CACHE_LIB.get_stats()
  local cached_count = cache_stats.item_count or 0
  local invalidated_count = 0
  for _ in pairs(CACHE.invalidated or {}) do invalidated_count = invalidated_count + 1 end
  reaper.ImGui_Text(ctx, string.format("Cached: %d items", cached_count))
  reaper.ImGui_Text(ctx, string.format("Hit rate: %d%% (%d/%d)", hit_rate, CACHE.hits, total))
  if invalidated_count > 0 then
    reaper.ImGui_TextColored(ctx, 0xFF6666FF, string.format("Invalidated: %d items", invalidated_count))
  end
  reaper.ImGui_EndTooltip(ctx)
end

-- Options button (moved from Clear Cache right-click menu)
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Options", scale(70), scale(24)) then
  reaper.ImGui_OpenPopup(ctx, "##options_menu")
end
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  reaper.ImGui_Text(ctx, "Debug and diagnostic options")
  reaper.ImGui_EndTooltip(ctx)
end

-- Options menu (previously cache_context_menu)
if reaper.ImGui_BeginPopup(ctx, "##options_menu") then
  -- Toggle console output option
  local console_label = CONSOLE.enabled and "✓ Console Output" or "  Console Output"
  if reaper.ImGui_Selectable(ctx, console_label) then
    CONSOLE.enabled = not CONSOLE.enabled
    save_prefs()
  end

  -- Toggle debug mode option
  local debug_label = DEBUG and "✓ Debug Mode" or "  Debug Mode"
  if reaper.ImGui_Selectable(ctx, debug_label) then
    DEBUG = not DEBUG
    -- Also control Cache Library debug mode
    CACHE_LIB.set_debug(DEBUG)
    -- Save preference
    save_prefs()
    if DEBUG then
      reaper.ShowConsoleMsg("\n[ILB] Debug mode ENABLED\n")
      reaper.ShowConsoleMsg("[ILB] Will show: ILE initialization messages, cache behavior (HIT/MISS/STORE)\n\n")
    else
      reaper.ShowConsoleMsg("[ILB] Debug mode DISABLED\n")
    end
  end

  reaper.ImGui_Separator(ctx)

  -- Toggle docking option
  local docking_label = ALLOW_DOCKING and "✓ Allow Docking" or "  Allow Docking"
  if reaper.ImGui_Selectable(ctx, docking_label) then
    ALLOW_DOCKING = not ALLOW_DOCKING
    save_prefs()
    -- Show warning message
    local msg = ALLOW_DOCKING and
      "Docking enabled!\n\n" ..
      "⚠️ WARNING: Docking/undocking may cause crashes.\n" ..
      "Please restart the script for this change to take effect." or
      "Docking disabled.\n\n" ..
      "Window will remain floating only (more stable).\n" ..
      "Please restart the script for this change to take effect."
    reaper.ShowMessageBox(msg, "Docking Setting Changed", 0)
  end
  if reaper.ImGui_IsItemHovered(ctx) then
    reaper.ImGui_BeginTooltip(ctx)
    reaper.ImGui_Text(ctx, "Enable/disable window docking to REAPER docker")
    reaper.ImGui_Text(ctx, "⚠️  Docking may cause crashes on some systems")
    reaper.ImGui_Text(ctx, "Requires script restart to apply")
    reaper.ImGui_EndTooltip(ctx)
  end

  -- Cache Test Report option
  if reaper.ImGui_Selectable(ctx, "  Cache Test Report...") then
    -- Generate cache test report
    local report = {}
    report[#report + 1] = "=== CACHE SYSTEM TEST REPORT ==="
    report[#report + 1] = ""

    -- 1. Cache file location
    local cache_path = get_cache_path()
    report[#report + 1] = "1. CACHE FILE LOCATION:"
    report[#report + 1] = "   " .. cache_path

    -- Check if file exists
    local file = io.open(cache_path, "r")
    if file then
      file:close()
      report[#report + 1] = "   ✓ Cache file exists"
    else
      report[#report + 1] = "   ✗ Cache file NOT found"
    end
    report[#report + 1] = ""

    -- 2. Cache statistics
    report[#report + 1] = "2. CACHE STATISTICS:"
    if CACHE.data then
      report[#report + 1] = string.format("   Cached items: %d", CACHE.data.item_count or 0)
      report[#report + 1] = string.format("   Cache version: %s", CACHE_VERSION)
      report[#report + 1] = string.format("   Cache hits: %d", CACHE.hits)
      report[#report + 1] = string.format("   Cache misses: %d", CACHE.misses)
      local total = CACHE.hits + CACHE.misses
      if total > 0 then
        local hit_rate = math.floor((CACHE.hits / total) * 100)
        report[#report + 1] = string.format("   Hit rate: %d%%", hit_rate)
      end
    else
      report[#report + 1] = "   ✗ No cache data loaded"
    end
    report[#report + 1] = ""

    -- 3. Current selection
    local sel_count = reaper.CountSelectedMediaItems(0)
    report[#report + 1] = "3. CURRENT SELECTION:"
    report[#report + 1] = string.format("   Selected items: %d", sel_count)
    report[#report + 1] = string.format("   Displayed rows: %d", #ROWS)
    report[#report + 1] = ""

    -- 4. Sample metadata check (first selected item)
    if sel_count > 0 then
      local item = reaper.GetSelectedMediaItem(0, 0)
      local _, item_guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)

      report[#report + 1] = "4. SAMPLE ITEM METADATA CHECK:"
      report[#report + 1] = "   Item GUID: " .. (item_guid or "unknown")

      -- Check if in cache
      if CACHE.data and CACHE.data.items and CACHE.data.items[item_guid] then
        local cached = CACHE.data.items[item_guid]
        report[#report + 1] = "   ✓ Item found in cache"
        report[#report + 1] = "   Cached fields:"
        report[#report + 1] = "     - file_name: " .. (cached.file_name or "(empty)")
        report[#report + 1] = "     - meta_trk_name: " .. (cached.meta_trk_name or "(empty)")
        report[#report + 1] = "     - umid: " .. ((cached.umid and cached.umid ~= "") and "✓ present" or "✗ empty")
        report[#report + 1] = "     - origination_date: " .. ((cached.origination_date and cached.origination_date ~= "") and cached.origination_date or "✗ empty")
        report[#report + 1] = "     - project: " .. ((cached.project and cached.project ~= "") and cached.project or "✗ empty")
        report[#report + 1] = "     - scene: " .. ((cached.scene and cached.scene ~= "") and cached.scene or "✗ empty")
      else
        report[#report + 1] = "   ✗ Item NOT in cache"
      end
    else
      report[#report + 1] = "4. SAMPLE ITEM METADATA CHECK:"
      report[#report + 1] = "   (No items selected - select an item to test)"
    end
    report[#report + 1] = ""

    -- 5. Test recommendations
    report[#report + 1] = "5. RECOMMENDED TESTS:"
    report[#report + 1] = "   A. Delete cache file and restart ILE (cold start test)"
    report[#report + 1] = "   B. Select 1 random item - check load time & metadata"
    report[#report + 1] = "   C. Deselect all, reselect same item - should be instant (cache hit)"
    report[#report + 1] = "   D. Select 100+ items - check progressive loading"
    report[#report + 1] = "   E. Close and reopen ILE - check startup time with cache"
    report[#report + 1] = "   F. Use 'Scan Project Items' to build complete cache"
    report[#report + 1] = ""
    report[#report + 1] = "==================================="

    -- Print to console
    local report_text = table.concat(report, "\n")
    reaper.ShowConsoleMsg("\n" .. report_text .. "\n\n")

    -- Show message box
    reaper.ShowMessageBox("Cache test report printed to console.\n\nCheck the REAPER console for detailed results.", "Cache Test Report", 0)
  end

  -- Separator before font size
  reaper.ImGui_Separator(ctx)

  -- Font Size submenu
  if reaper.ImGui_BeginMenu(ctx, "Font Size") then
    local sizes = {
      {label = "50%",  scale = 0.5},
      {label = "75%",  scale = 0.75},
      {label = "100% (Default)", scale = 1.0},
      {label = "125%", scale = 1.25},
      {label = "150%", scale = 1.5},
      {label = "175%", scale = 1.75},
      {label = "200%", scale = 2.0},
      {label = "250%", scale = 2.5},
      {label = "300%", scale = 3.0},
    }

    for _, size in ipairs(sizes) do
      local is_current = (math.abs((FONT_SCALE or 1.0) - size.scale) < 0.01)
      local label = is_current and ("✓ " .. size.label) or ("  " .. size.label)
      if reaper.ImGui_Selectable(ctx, label) then
        FONT_SCALE = size.scale
        local font_size = math.floor(13 * FONT_SCALE)
        save_prefs()
        set_font_size(font_size)  -- Set new font size
      end
    end

    reaper.ImGui_EndMenu(ctx)
  end

  reaper.ImGui_EndPopup(ctx)
end

-- Second row starts here
if reaper.ImGui_Button(ctx, "Refresh Now", scale(110), scale(24)) then
  TABLE_SOURCE = "live"
  refresh_now()  -- Force immediate full refresh (bypasses progressive loading)
end
-- Show hint if progressive loading is active
if PROGRESSIVE.active then
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "(loading in background...)")
end

-- Fit Content Widths button
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Fit Content Widths", scale(130), scale(24)) then
  FIT_CONTENT_WIDTH = true  -- Flag to fit content widths on next frame
end
-- Right-click for width options menu
if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then
  reaper.ImGui_OpenPopup(ctx, "Width Options")
end
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  reaper.ImGui_Text(ctx, "Left-click: Auto-adjust columns based on content")
  reaper.ImGui_Text(ctx, "Right-click: Reset to default widths")
  reaper.ImGui_EndTooltip(ctx)
end

-- Width Options popup menu
if reaper.ImGui_BeginPopup(ctx, "Width Options") then
  if reaper.ImGui_MenuItem(ctx, "Reset to Default Widths") then
    RESET_COLUMN_WIDTHS = true
  end
  reaper.ImGui_EndPopup(ctx)
end

-- Advanced Sort button
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Advanced Sort...", scale(120), scale(24)) then
  reaper.ImGui_OpenPopup(ctx, "Advanced Sort")
end
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  reaper.ImGui_Text(ctx, "Multi-level sort (Excel-like)")
  reaper.ImGui_Text(ctx, "Click header: single sort")
  reaper.ImGui_Text(ctx, "Shift+Click header: add to sort")
  reaper.ImGui_EndTooltip(ctx)
end

reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Copy (TSV)", scale(110), scale(24)) then
  local rows = get_view_rows()
  local text = LT.build_table_text(
    "tsv",
    rows,
    COL_ORDER,
    header_label_from_id,
    function(i, r, col) return get_cell_text(i, r, col, "tsv") end
  )
  if text and text ~= "" then
    local rows = get_view_rows()
    local text = LT.build_table_text(
      "tsv",
      rows,
      COL_ORDER,
      header_label_from_id,                              -- header label function
      function(i, r, col) return get_cell_text(i, r, col, "tsv") end
    )
    if text and text ~= "" then
      reaper.ImGui_SetClipboardText(ctx, text)
    end

  end
end


reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Save .tsv", scale(100), scale(24)) then
  local p = choose_save_path("Item List_"..timestamp()..".tsv","Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
  if p then
    local rows = get_view_rows()
    local text = LT.build_table_text(
      "tsv",
      rows,
      COL_ORDER,
      header_label_from_id,
      function(i, r, col) return get_cell_text(i, r, col, "tsv") end
    )
    write_text_file(p, text)
  end

end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Save .csv", scale(100), scale(24)) then
  local p = choose_save_path("Item List_"..timestamp()..".csv","CSV (*.csv)\0*.csv\0All (*.*)\0*.*\0")
  if p then
    local rows = get_view_rows()
    local text = LT.build_table_text(
      "csv",
      rows,
      COL_ORDER,
      header_label_from_id,
      function(i, r, col) return get_cell_text(i, r, col, "csv") end
    )
    write_text_file(p, text)
  end
end

-- [ANCHOR] Summary button cluster (REPLACED)
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, POPUP_TITLE, 100, 24) then
  reaper.ImGui_OpenPopup(ctx, POPUP_TITLE)
end

-- === Column Presets UI (right of Summary) ===
reaper.ImGui_SameLine(ctx)
reaper.ImGui_Text(ctx, "Preset:")
reaper.ImGui_SameLine(ctx)
do
  local current = ACTIVE_PRESET or "(none)"
  -- Fixed preview field width to prevent overflow
  reaper.ImGui_SetNextItemWidth(ctx, scale(160))
  -- Limit popup height (scrollable)
  if reaper.ImGui_BeginCombo(ctx, "##colpreset_combo", current, reaper.ImGui_ComboFlags_HeightRegular()) then
    -- "(none)": clear preset, do not apply any saved order
    local sel = (ACTIVE_PRESET == nil)
    if reaper.ImGui_Selectable(ctx, "(none)", sel) then
      ACTIVE_PRESET = nil
      PRESET_STATUS = "No preset"
    end
    reaper.ImGui_Separator(ctx)

    -- List all user-named presets; selecting applies immediately
    for i, name in ipairs(PRESETS) do
      local selected = (name == ACTIVE_PRESET)
      if reaper.ImGui_Selectable(ctx, name, selected) then
        ACTIVE_PRESET = name
        preset_recall(name)       -- apply immediately, no Recall button needed
        FIT_CONTENT_WIDTH = true  -- auto fit content width
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
end

-- "Edit...": open Preset Editor
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Edit...", scale(68), scale(24)) then
  reaper.ImGui_OpenPopup(ctx, "Column Preset Editor")
end

-- "Save as...": save with user-defined name
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Save as…", scale(88), scale(24)) then
  PRESET_NAME_BUF = ACTIVE_PRESET or PRESET_NAME_BUF or ""
  reaper.ImGui_OpenPopup(ctx, "Save preset as")
end

-- "Delete": delete currently selected preset
reaper.ImGui_SameLine(ctx)
local can_delete = (ACTIVE_PRESET and ACTIVE_PRESET~="")
if reaper.ImGui_BeginDisabled(ctx, not can_delete) then end
if reaper.ImGui_Button(ctx, "Delete", scale(68), scale(24)) and can_delete then
  preset_delete(ACTIVE_PRESET)
end
if reaper.ImGui_EndDisabled then reaper.ImGui_EndDisabled(ctx) end

-- Status text
reaper.ImGui_SameLine(ctx)
reaper.ImGui_TextDisabled(ctx, PRESET_STATUS or "")

-- Save-as modal
if reaper.ImGui_BeginPopupModal(ctx, "Save preset as", true, TF('ImGui_WindowFlags_AlwaysAutoResize')) then
  reaper.ImGui_Text(ctx, "Preset name:")
  reaper.ImGui_SetNextItemWidth(ctx, scale(220))
  PRESET_NAME_BUF = PRESET_NAME_BUF or ""
  local changed, txt = reaper.ImGui_InputText(ctx, "##presetname", PRESET_NAME_BUF)
  if changed then PRESET_NAME_BUF = txt end

  if reaper.ImGui_Button(ctx, "Save", scale(82), scale(24)) then
    -- Use pending visibility map if available (from Preset Editor), otherwise nil (legacy mode)
    if preset_save_as(PRESET_NAME_BUF, COL_ORDER, PENDING_VISIBILITY_MAP) then
      PENDING_VISIBILITY_MAP = nil  -- Clear after use
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Cancel", scale(82), scale(24)) then
    PENDING_VISIBILITY_MAP = nil  -- Clear on cancel
    reaper.ImGui_CloseCurrentPopup(ctx)
  end
  reaper.ImGui_EndPopup(ctx)
end

-- Column Preset Editor modal
if reaper.ImGui_BeginPopupModal(ctx, "Column Preset Editor", true, TF('ImGui_WindowFlags_AlwaysAutoResize')) then
  reaper.ImGui_Text(ctx, "Arrange columns for preset: " .. (ACTIVE_PRESET or "(unsaved)"))
  reaper.ImGui_Separator(ctx)

  -- Initialize editor state if needed
  if not PRESET_EDITOR_STATE then
    PRESET_EDITOR_STATE = {
      columns = {},  -- {col_id, visible, label}
      dirty = false
    }

    -- Build complete list of all 28 columns with proper visibility
    -- First add visible columns in their current order
    local added = {}
    for _, col_id in ipairs(COL_ORDER or {}) do
      table.insert(PRESET_EDITOR_STATE.columns, {
        id = col_id,
        visible = true,
        label = header_label_from_id(col_id) or tostring(col_id)
      })
      added[col_id] = true
    end

    -- Then add hidden columns (those not in COL_ORDER) at the end
    for col_id = 1, 34 do
      if not added[col_id] then
        local is_visible = COL_VISIBILITY[col_id] or false
        table.insert(PRESET_EDITOR_STATE.columns, {
          id = col_id,
          visible = is_visible,
          label = header_label_from_id(col_id) or tostring(col_id)
        })
      end
    end
  end

  -- Column list with checkboxes, drag handles, and move buttons
  local drag_src_idx, drag_dst_idx = nil, nil
  for i = 1, #PRESET_EDITOR_STATE.columns do
    local col = PRESET_EDITOR_STATE.columns[i]
    reaper.ImGui_PushID(ctx, i)

    -- Checkbox for visibility
    local changed, checked = reaper.ImGui_Checkbox(ctx, "##vis", col.visible)
    if changed then
      col.visible = checked
      PRESET_EDITOR_STATE.dirty = true
    end

    -- Drag handle (Selectable)
    reaper.ImGui_SameLine(ctx)
    local display_label = col.label
    if not display_label or display_label == "" then
      display_label = string.format("Column %d", col.id)
    end
    reaper.ImGui_Selectable(ctx, display_label, false, 0, 220, 20)
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "Drag to reorder")
    end
    if reaper.ImGui_BeginDragDropSource(ctx, TF('ImGui_DragDropFlags_SourceNoPreviewTooltip')) then
      reaper.ImGui_SetDragDropPayload(ctx, "ILB_COL_REORDER", tostring(i))
      reaper.ImGui_Text(ctx, display_label)
      reaper.ImGui_EndDragDropSource(ctx)
    end
    if reaper.ImGui_BeginDragDropTarget(ctx) then
      local accepted, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "ILB_COL_REORDER")
      if accepted then
        drag_src_idx = tonumber(payload)
        drag_dst_idx = i
      end
      reaper.ImGui_EndDragDropTarget(ctx)
    end

    -- Up button
    reaper.ImGui_SameLine(ctx, 300)
    if reaper.ImGui_BeginDisabled(ctx, i == 1) then end
    if reaper.ImGui_Button(ctx, "↑", 30, 20) and i > 1 then
      PRESET_EDITOR_STATE.columns[i], PRESET_EDITOR_STATE.columns[i-1] =
        PRESET_EDITOR_STATE.columns[i-1], PRESET_EDITOR_STATE.columns[i]
      PRESET_EDITOR_STATE.dirty = true
    end
    if reaper.ImGui_EndDisabled then reaper.ImGui_EndDisabled(ctx) end

    -- Down button
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_BeginDisabled(ctx, i == #PRESET_EDITOR_STATE.columns) then end
    if reaper.ImGui_Button(ctx, "↓", 30, 20) and i < #PRESET_EDITOR_STATE.columns then
      PRESET_EDITOR_STATE.columns[i], PRESET_EDITOR_STATE.columns[i+1] =
        PRESET_EDITOR_STATE.columns[i+1], PRESET_EDITOR_STATE.columns[i]
      PRESET_EDITOR_STATE.dirty = true
    end
    if reaper.ImGui_EndDisabled then reaper.ImGui_EndDisabled(ctx) end

    reaper.ImGui_PopID(ctx)
  end

  -- Drop zone to append to the end of the list
  reaper.ImGui_Dummy(ctx, 1, 4)
  if reaper.ImGui_BeginDragDropTarget(ctx) then
    local accepted, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "ILB_COL_REORDER")
    if accepted then
      drag_src_idx = tonumber(payload)
      drag_dst_idx = (#PRESET_EDITOR_STATE.columns + 1)
    end
    reaper.ImGui_EndDragDropTarget(ctx)
  end

  if drag_src_idx and drag_dst_idx and drag_src_idx ~= drag_dst_idx then
    local entry = table.remove(PRESET_EDITOR_STATE.columns, drag_src_idx)
    if entry then
      if drag_dst_idx > (#PRESET_EDITOR_STATE.columns + 1) then
        drag_dst_idx = #PRESET_EDITOR_STATE.columns + 1
      elseif drag_dst_idx < 1 then
        drag_dst_idx = 1
      end
      if drag_src_idx < drag_dst_idx then
        drag_dst_idx = drag_dst_idx - 1
      end
      table.insert(PRESET_EDITOR_STATE.columns, drag_dst_idx, entry)
      PRESET_EDITOR_STATE.dirty = true
    end
  end

  reaper.ImGui_Separator(ctx)

  -- Reset to default button
  if reaper.ImGui_Button(ctx, "Reset to Default", scale(140), scale(24)) then
    -- Reset to default column order (all 34 columns)
    local reset_order = {
      1, 2, 3, 12, 13, 31, 4, 5, 6, 32, 33, 34, 7, 8, 9, 10, 11,  -- Basic + Time + Length + File Info + Status
      14, 15,  -- UMID
      16, 17, 18, 19, 20, 21,  -- BWF metadata
      22, 23, 24, 25, 26, 27, 28,  -- iXML metadata
      29, 30  -- Source position (from TimeReference)
    }
    PRESET_EDITOR_STATE.columns = {}
    for _, col_id in ipairs(reset_order) do
      table.insert(PRESET_EDITOR_STATE.columns, {
        id = col_id,
        visible = true,
        label = header_label_from_id(col_id) or tostring(col_id)
      })
    end
    PRESET_EDITOR_STATE.dirty = true
  end

  reaper.ImGui_Separator(ctx)

  -- Bottom buttons
  if reaper.ImGui_Button(ctx, "Apply", scale(82), scale(24)) then
    -- Apply to current session (update COL_ORDER and COL_VISIBILITY)
    COL_ORDER = {}
    COL_POS = {}
    COL_VISIBILITY = {}
    for i, col in ipairs(PRESET_EDITOR_STATE.columns) do
      COL_VISIBILITY[col.id] = col.visible
      if col.visible then
        table.insert(COL_ORDER, col.id)
        COL_POS[col.id] = #COL_ORDER
      end
    end
    PRESET_EDITOR_STATE.dirty = false
    PRESET_STATUS = "Applied (unsaved)"
    FIT_CONTENT_WIDTH = true  -- auto fit content width
  end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Save & Apply", scale(120), scale(24)) then
    -- Save to active preset and apply
    COL_ORDER = {}
    COL_POS = {}
    COL_VISIBILITY = {}

    -- Build COL_ORDER (visible columns only) and visibility map (all columns)
    for i, col in ipairs(PRESET_EDITOR_STATE.columns) do
      COL_VISIBILITY[col.id] = col.visible
      if col.visible then
        table.insert(COL_ORDER, col.id)
        COL_POS[col.id] = #COL_ORDER
      end
    end

    FIT_CONTENT_WIDTH = true  -- auto fit content width

    if ACTIVE_PRESET and ACTIVE_PRESET ~= "" then
      -- Update existing preset with visibility data
      preset_save_as(ACTIVE_PRESET, COL_ORDER, COL_VISIBILITY)
      PRESET_EDITOR_STATE = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
    else
      -- Need to create a new preset - store visibility map and open save dialog
      PENDING_VISIBILITY_MAP = COL_VISIBILITY
      PRESET_NAME_BUF = "New Preset"
      PRESET_EDITOR_STATE = nil
      reaper.ImGui_CloseCurrentPopup(ctx)
      reaper.ImGui_OpenPopup(ctx, "Save preset as")
    end
  end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Cancel", scale(82), scale(24)) then
    PRESET_EDITOR_STATE = nil
    reaper.ImGui_CloseCurrentPopup(ctx)
  end

  reaper.ImGui_EndPopup(ctx)
end
-----------------------

reaper.ImGui_SameLine(ctx)
reaper.ImGui_TextDisabled(ctx, col_preset_status_text())




end

local function draw_table(rows, height)
  -- Use SizingFixedFit so all columns are manually resizable and extending (not shrinking)
  local flags = TF('ImGui_TableFlags_Borders')
            | TF('ImGui_TableFlags_RowBg')
            | TF('ImGui_TableFlags_SizingFixedFit')  -- All columns manually resizable with extension
            | TF('ImGui_TableFlags_ScrollX')
            | TF('ImGui_TableFlags_ScrollY')         -- Enable vertical scrolling with frozen header
            | TF('ImGui_TableFlags_Resizable')
            | TF('ImGui_TableFlags_NoSavedSettings') -- Don't persist table settings (prevents width memory)
            -- Removed: TableFlags_Reorderable - column order managed through Preset Editor

  -- Generate table ID - use counter to ensure truly unique IDs when resetting
  local base_id = "items_" .. ((ACTIVE_PRESET and ACTIVE_PRESET ~= "" and ACTIVE_PRESET) or "default")
  local table_id = base_id .. "_" .. tostring(RESET_COUNTER)

  if RESET_COLUMN_WIDTHS then
    -- Restore default widths
    for k, v in pairs(DEFAULT_COL_WIDTH) do
      COL_WIDTH[k] = v
    end
    RESET_COUNTER = RESET_COUNTER + 1
    table_id = base_id .. "_" .. tostring(RESET_COUNTER)
    reaper.ShowConsoleMsg("[ILB] Resetting column widths (counter: " .. RESET_COUNTER .. ")\n")
    RESET_COLUMN_WIDTHS = false  -- Clear immediately before creating table
  end

  -- Fit content width: Calculate actual text widths for all columns
  if FIT_CONTENT_WIDTH then
    local initial_order = (COL_ORDER and #COL_ORDER > 0) and COL_ORDER or {
      1, 2, 3, 12, 13, 31, 4, 5, 6, 32, 33, 34, 7, 8, 9, 10, 11,
      14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30
    }

    -- Columns to skip (fixed content, keep default width)
    local skip_columns = {
      [1] = true,   -- #
      [2] = true,   -- TrkID
      [8] = true,   -- Chan#
      [9] = true,   -- Int#
      [10] = true,  -- Mute
      [11] = true,  -- Color
      [12] = true,  -- Start
      [13] = true,  -- End
      [14] = true,  -- UMID
      [15] = true,  -- UMID (PT)
      [20] = true,  -- Time Reference
      [29] = true,  -- Source Start (TC)
      [30] = true,  -- Source End (TC)
      [31] = true,  -- Length (fits "hh:mm:ss.SSS")
    }

    -- Calculate max width for each column
    for _, col_id in ipairs(initial_order) do
      -- Skip columns with fixed content
      if skip_columns[col_id] then
        goto continue
      end

      local max_width = 0

      -- Measure header text (with sort indicator if present)
      local header_text = header_label_from_id(col_id) or tostring(col_id)
      for i, sort_col in ipairs(SORT_STATE.columns) do
        if sort_col.col_id == col_id then
          local sort_indicator = sort_col.ascending and " ▲" or " ▼"
          if i > 1 then
            header_text = header_text .. " [" .. i .. "]" .. sort_indicator
          else
            header_text = header_text .. sort_indicator
          end
          break
        end
      end
      local header_width = reaper.ImGui_CalcTextSize(ctx, header_text)
      max_width = math.max(max_width, header_width)

      -- Measure content for all visible rows (no sampling limit for accurate measurement)
      for i = 1, #rows do
        local row = rows[i]
        -- Use existing get_cell_text function for consistency
        local cell_text = get_cell_text(i, row, col_id, FORMAT) or ""

        -- CalcTextSize returns width, height - we only need width
        local cell_width = reaper.ImGui_CalcTextSize(ctx, tostring(cell_text))
        max_width = math.max(max_width, cell_width)
      end

      -- Add padding: 16px for internal padding + 16px for border, margins, and safety
      COL_WIDTH[col_id] = math.max(50, math.ceil(max_width + 32))

      ::continue::
    end

    -- Reset table to apply new widths
    RESET_COUNTER = RESET_COUNTER + 1
    table_id = base_id .. "_" .. tostring(RESET_COUNTER)
    FIT_CONTENT_WIDTH = false
    reaper.ShowConsoleMsg("[ILB] Fitted content widths (counter: " .. RESET_COUNTER .. ")\n")
  end

  -- Use dynamic height (fills remaining space) or fallback to 360
  -- If height is provided (not nil), use it; otherwise use -1 (fill available space)
  local outer_height = height or -1
  if reaper.ImGui_BeginTable(ctx, table_id, 34, flags, 0, outer_height) then
    -- Use existing COL_ORDER for header rendering; use default if not set yet
    -- Default order: Basic info, Time, Metadata (BWF), Metadata (iXML), Status
    local DEFAULT_COL_ORDER = {
      1, 2, 3, 12, 13, 31, 4, 5, 6, 32, 33, 34, 7, 8, 9, 10, 11,  -- Basic + Time + Length + File Info + Status
      14, 15,  -- UMID
      16, 17, 18, 19, 20, 21,  -- BWF metadata
      22, 23, 24, 25, 26, 27, 28,  -- iXML metadata
      29, 30  -- Source position (from TimeReference)
    }
    local initial_order = (COL_ORDER and #COL_ORDER > 0) and COL_ORDER or DEFAULT_COL_ORDER

    -- Pre-calculate sort level for each column (for width adjustment)
    local col_sort_level = {}
    for i, sort_col in ipairs(SORT_STATE.columns) do
      col_sort_level[sort_col.col_id] = i
    end

    -- Setup column with default width from COL_WIDTH (adjusted for sort indicators)
    local function _setup_column_by_id(id)
      local label = header_label_from_id(id) or tostring(id)
      local width = COL_WIDTH[id] or DEFAULT_COL_WIDTH[id] or 100  -- Fallback to default or 100px

      -- All columns use WidthFixed for manual resizing with extension behavior
      if width < 0 then width = 150 end  -- Convert auto-stretch (-1) to reasonable default

      -- Add extra width for sort indicators
      local sort_level = col_sort_level[id]
      if sort_level then
        if sort_level > 1 then
          -- Multi-level sort: " [N] ▲" or " [N] ▼" (approx 40-50 pixels)
          width = width + 50
        else
          -- Single sort: " ▲" or " ▼" (approx 20 pixels)
          width = width + 20
        end
      end

      local col_flags = reaper.ImGui_TableColumnFlags_WidthFixed()
      reaper.ImGui_TableSetupColumn(ctx, label, col_flags, scale(width))
    end

    -- Setup columns based on current order
    for i = 1, #initial_order do
      _setup_column_by_id(initial_order[i])
    end

    -- Freeze header row (0 columns, 1 row frozen)
    reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)

    -- Manual header rendering (with sort click detection)
    reaper.ImGui_TableNextRow(ctx, reaper.ImGui_TableRowFlags_Headers())
    for disp = 1, #initial_order do
      reaper.ImGui_TableSetColumnIndex(ctx, disp - 1)
      local col_id = initial_order[disp]
      local label = header_label_from_id(col_id) or tostring(col_id)

      -- Find sort indicator for this column
      local sort_indicator = ""
      local sort_level = 0
      for i, sort_col in ipairs(SORT_STATE.columns) do
        if sort_col.col_id == col_id then
          sort_indicator = sort_col.ascending and " ▲" or " ▼"
          sort_level = i
          break
        end
      end

      -- Display level number for multi-column sort (Excel-like)
      if sort_level > 1 then
        label = label .. " [" .. sort_level .. "]" .. sort_indicator
      elseif sort_level == 1 then
        label = label .. sort_indicator
      end

      reaper.ImGui_TableHeader(ctx, label)

      -- Detect header click for sorting
      if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Left()) then
        local m = _mods()
        if m.shift then
          -- Shift+Click: Add to multi-column sort
          local found = false
          for i, sort_col in ipairs(SORT_STATE.columns) do
            if sort_col.col_id == col_id then
              -- Toggle ascending/descending
              sort_col.ascending = not sort_col.ascending
              found = true
              break
            end
          end
          if not found then
            -- Add new sort column
            table.insert(SORT_STATE.columns, {col_id = col_id, ascending = true})
          end
        else
          -- Click: Single column sort (clear others)
          local was_sorted = false
          for i, sort_col in ipairs(SORT_STATE.columns) do
            if sort_col.col_id == col_id then
              -- Toggle direction
              SORT_STATE.columns = {{col_id = col_id, ascending = not sort_col.ascending}}
              was_sorted = true
              break
            end
          end
          if not was_sorted then
            -- Set new single sort
            SORT_STATE.columns = {{col_id = col_id, ascending = true}}
          end
        end

        -- Apply sort immediately to ROWS (not just the view)
        sort_rows_by_state(ROWS)

        -- Force table width recalculation by resetting table ID
        RESET_COUNTER = RESET_COUNTER + 1
      end
    end


    -- Build row_index_map (for Shift-rectangle selection etc.)
    local row_index_map = LT.build_row_index_map(rows)



    
    -- Unified cell click handling: Click = select; Shift = rectangle; Cmd/Ctrl = toggle
    local function handle_cell_click(guid, col)
      local m = _mods()
      if m.shift and SEL.anchor then
        -- Use Library built-in: visual column order (COL_ORDER/COL_POS) rectangle selection
        LT.sel_rect_apply(
          rows,
          row_index_map,
          SEL.anchor.guid,  -- anchor guid
          guid,             -- current guid
          SEL.anchor.col,   -- anchor col (logical column ID)
          col,              -- current col (logical column ID)
          COL_ORDER,        -- visual-to-logical column order
          COL_POS,          -- logical-to-visual column order
          sel_add           -- callback to add each selected cell to SEL
        )


        
      elseif m.shortcut then
        -- Toggle single cell
        if not SEL.anchor then SEL.anchor = { guid = guid, col = col } end
        sel_toggle(guid, col)
      else
        -- Clear selection -> set new anchor -> select cell (avoid clearing anchor just set)
        sel_clear()
        SEL.anchor = { guid = guid, col = col }
        sel_add(guid, col)
      end
      -- ILB: sync table selection → REAPER item selection
      sync_list_selection_to_reaper()
    end

    -- Visual order version: Shift-rectangle by visual column order (COL_POS/COL_ORDER)
    local function sel_rect_apply_visual(rows, row_index_map, guid, col, COL_ORDER, COL_POS)
      local a = SEL and SEL.anchor
      if not (a and a.guid and a.col) then return end

      -- Convert to visual positions and compute range
      local p1 = (COL_POS and COL_POS[a.col]) or a.col
      local p2 = (COL_POS and COL_POS[col])   or col
      if not (p1 and p2) then return end
      if p1 > p2 then p1, p2 = p2, p1 end        -- visual column range (left to right)

      local r1 = row_index_map[a.guid]
      local r2 = row_index_map[guid]
      if not (r1 and r2) then return end
      if r1 > r2 then r1, r2 = r2, r1 end        -- row range (top to bottom)

      -- Map visual positions back to logical columns, add each cell
      -- Keep anchor intact, only clear selected cells
      SEL.cells = {}                             -- clear cells only, keep anchor
      for ri = r1, r2 do
        local row = rows[ri]
        local row_guid = row and row.__item_guid
        if row_guid then
          for pos = p1, p2 do
            local logical_col = COL_ORDER and COL_ORDER[pos] or pos
            if logical_col then sel_add(row_guid, logical_col) end
          end
        end
      end
    end



    -- === Render rows in visual column order (COL_ORDER) ===
    for i, r in ipairs(rows or {}) do
      reaper.ImGui_TableNextRow(ctx)
      -- ILB: auto-scroll to target row (from REAPER selection sync)
      if ILB.scroll_to_row and ILB.scroll_to_row == i then
        reaper.ImGui_SetScrollHereY(ctx, 0.3)
        ILB.scroll_to_row = nil
      end
      reaper.ImGui_PushID(ctx, (r.__item_guid ~= "" and r.__item_guid) or tostring(i))

      local ilb_dblclick_item = nil  -- ILB: Move to View on double-click
      for disp = 1, reaper.ImGui_TableGetColumnCount(ctx) do
        reaper.ImGui_TableSetColumnIndex(ctx, disp-1)
        local col = COL_ORDER[disp]

        if col == 1 then
          local sel = sel_has(r.__item_guid, 1)
          reaper.ImGui_Selectable(ctx, tostring(i).."##c1", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 1) end
          if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then ilb_dblclick_item = r end

        elseif col == 2 then
          local sel = sel_has(r.__item_guid, 2)
          reaper.ImGui_Selectable(ctx, tostring(r.track_idx or "").."##c2", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 2) end
          if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then ilb_dblclick_item = r end

        elseif col == 3 then
          -- Track Name (editable - click elsewhere or ESC to finish)
          local track_txt = tostring(r.track_name or "")
          local editing = (EDIT and EDIT.row == r and EDIT.col == 3)
          local sel = sel_has(r.__item_guid, 3)
          if not editing then
            reaper.ImGui_Selectable(ctx, (track_txt ~= "" and track_txt or " ").."##trk", sel)
            if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 3) end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and TABLE_SOURCE=="live" then
              EDIT = { row = r, col = 3, buf = track_txt, want_focus = true }
            end
          else
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            if EDIT.want_focus then reaper.ImGui_SetKeyboardFocusHere(ctx); EDIT.want_focus=false end
            local flags = reaper.ImGui_InputTextFlags_AutoSelectAll()
            local changed, newv = reaper.ImGui_InputText(ctx, "##trk", EDIT.buf, flags)
            if changed then EDIT.buf = newv end
            -- Submit on: Enter, click elsewhere (deactivated), or ESC (cancel without saving)
            local deactivated = reaper.ImGui_IsItemDeactivated(ctx)
            local enter_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
            local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
            if enter_pressed or (deactivated and not cancel) then
              if r.__track then apply_track_name(r.__track, EDIT.buf, rows) end
              EDIT=nil
            elseif cancel then
              EDIT=nil  -- Cancel without saving
            end
          end

        elseif col == 12 then
          local t = format_time(r.start_time); local sel = sel_has(r.__item_guid, 12)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c12", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 12) end

        elseif col == 13 then
          local t = format_time(r.end_time); local sel = sel_has(r.__item_guid, 13)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c13", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 13) end

        elseif col == 4 then
          -- Take Name (editable - click elsewhere or ESC to finish)
          local take_txt = tostring(r.take_name or "")
          local editing = (EDIT and EDIT.row == r and EDIT.col == 4)
          local sel = sel_has(r.__item_guid, 4)
          if not editing then
            reaper.ImGui_Selectable(ctx, (take_txt ~= "" and take_txt or " ").."##take", sel)
            if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 4) end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and TABLE_SOURCE=="live" then
              EDIT = { row = r, col = 4, buf = take_txt, want_focus = true }
            end
          else
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            if EDIT.want_focus then reaper.ImGui_SetKeyboardFocusHere(ctx); EDIT.want_focus=false end
            local flags = reaper.ImGui_InputTextFlags_AutoSelectAll()
            local changed, newv = reaper.ImGui_InputText(ctx, "##take", EDIT.buf, flags)
            if changed then EDIT.buf = newv end
            -- Submit on: Enter, click elsewhere (deactivated), or ESC (cancel without saving)
            local deactivated = reaper.ImGui_IsItemDeactivated(ctx)
            local enter_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
            local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
            if enter_pressed or (deactivated and not cancel) then
              apply_take_name(r.__take, EDIT.buf, r)
              EDIT=nil
            elseif cancel then
              EDIT=nil  -- Cancel without saving
            end
          end

        elseif col == 5 then
          -- Item Note (multiline editor - click elsewhere or ESC to finish)
          local note_txt = tostring(r.item_note or "")
          local editing = (EDIT and EDIT.row == r and EDIT.col == 5)
          local sel = sel_has(r.__item_guid, 5)
          if not editing then
            -- Show full multiline content (auto-wrap like Description)
            local display_txt = note_txt
            if display_txt == "" then display_txt = " " end
            reaper.ImGui_Selectable(ctx, display_txt.."##note", sel, reaper.ImGui_SelectableFlags_AllowOverlap())
            if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 5) end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and TABLE_SOURCE=="live" then
              EDIT = { row = r, col = 5, buf = note_txt, want_focus = true }
            end
          else
            -- Multiline editor with proper size (expand vertically)
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            if EDIT.want_focus then reaper.ImGui_SetKeyboardFocusHere(ctx); EDIT.want_focus=false end
            -- Remove AutoSelectAll for multiline, add Multiline flag
            local flags = reaper.ImGui_InputTextFlags_None()
            local changed, newv = reaper.ImGui_InputTextMultiline(ctx, "##note", EDIT.buf, -1, 100, flags)
            if changed then EDIT.buf = newv end
            -- Submit on: click elsewhere (deactivated), or ESC (cancel without saving)
            -- Note: Enter creates new line in multiline mode, so don't submit on Enter
            local deactivated = reaper.ImGui_IsItemDeactivated(ctx)
            local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
            if deactivated and not cancel then
              apply_item_note(r.__item, EDIT.buf, r)
              EDIT=nil
            elseif cancel then
              EDIT=nil  -- Cancel without saving
            end
          end

        elseif col == 6 then
          local t = tostring(r.file_name or ""); local sel = sel_has(r.__item_guid, 6)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c6", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 6) end

        elseif col == 7 then
          local t = tostring(r.meta_trk_name or ""); local sel = sel_has(r.__item_guid, 7)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c7", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 7) end

        elseif col == 8 then
          local t = tostring(r.channel_num or ""); local sel = sel_has(r.__item_guid, 8)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c8", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 8) end

        elseif col == 9 then
          local t = tostring(r.interleave or ""); local sel = sel_has(r.__item_guid, 9)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c9", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 9) end

        elseif col == 10 then
          local t = r.muted and "M" or ""; local sel = sel_has(r.__item_guid, 10)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c10", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 10) end

        elseif col == 11 then
          if r.color_rgb and r.color_rgb[1] then
            local rr, gg, bb = r.color_rgb[1]/255, r.color_rgb[2]/255, r.color_rgb[3]/255
            local colu = reaper.ImGui_ColorConvertDouble4ToU32(rr, gg, bb, 1.0)
            reaper.ImGui_TextColored(ctx, colu, "■")
            reaper.ImGui_SameLine(ctx)
          end
          local t = tostring(r.color_hex or ""); local sel = sel_has(r.__item_guid, 11)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c11", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 11) end

        -- New metadata columns (14-28) - Read-only
        elseif col == 14 then
          local t = tostring(r.umid or ""); local sel = sel_has(r.__item_guid, 14)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c14", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 14) end

        elseif col == 15 then
          local t = tostring(r.umid_pt or ""); local sel = sel_has(r.__item_guid, 15)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c15", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 15) end

        elseif col == 16 then
          local t = tostring(r.origination_date or ""); local sel = sel_has(r.__item_guid, 16)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c16", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 16) end

        elseif col == 17 then
          local t = tostring(r.origination_time or ""); local sel = sel_has(r.__item_guid, 17)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c17", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 17) end

        elseif col == 18 then
          local t = tostring(r.originator or ""); local sel = sel_has(r.__item_guid, 18)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c18", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 18) end

        elseif col == 19 then
          local t = tostring(r.originator_ref or ""); local sel = sel_has(r.__item_guid, 19)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c19", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 19) end

        elseif col == 20 then
          local t = tostring(r.time_reference or ""); local sel = sel_has(r.__item_guid, 20)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c20", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 20) end

        elseif col == 21 then
          local t = tostring(r.description or ""); local sel = sel_has(r.__item_guid, 21)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c21", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 21) end

        elseif col == 22 then
          local t = tostring(r.project or ""); local sel = sel_has(r.__item_guid, 22)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c22", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 22) end

        elseif col == 23 then
          local t = tostring(r.scene or ""); local sel = sel_has(r.__item_guid, 23)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c23", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 23) end

        elseif col == 24 then
          local t = tostring(r.take_meta or ""); local sel = sel_has(r.__item_guid, 24)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c24", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 24) end

        elseif col == 25 then
          local t = tostring(r.tape or ""); local sel = sel_has(r.__item_guid, 25)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c25", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 25) end

        elseif col == 26 then
          local t = tostring(r.ubits or ""); local sel = sel_has(r.__item_guid, 26)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c26", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 26) end

        elseif col == 27 then
          local t = tostring(r.framerate or ""); local sel = sel_has(r.__item_guid, 27)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c27", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 27) end

        elseif col == 28 then
          local t = tostring(r.speed or ""); local sel = sel_has(r.__item_guid, 28)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c28", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 28) end

        -- Source position columns (read-only, from TimeReference)
        elseif col == 29 then
          local t = tostring(r.source_start or ""); local sel = sel_has(r.__item_guid, 29)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c29", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 29) end

        elseif col == 30 then
          local t = tostring(r.source_end or ""); local sel = sel_has(r.__item_guid, 30)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c30", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 30) end

        elseif col == 31 then
          local t = format_time(r.length); local sel = sel_has(r.__item_guid, 31)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c31", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 31) end

        elseif col == 32 then
          local t = tostring(r.sample_rate or ""); local sel = sel_has(r.__item_guid, 32)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c32", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 32) end

        elseif col == 33 then
          local t = tostring(r.bit_depth or ""); local sel = sel_has(r.__item_guid, 33)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c33", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 33) end

        elseif col == 34 then
          local t = tostring(r.file_type or ""); local sel = sel_has(r.__item_guid, 34)
          reaper.ImGui_Selectable(ctx, (t ~= "" and t or " ").."##c34", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 34) end
        end
      end

      -- ILB: Move to View - double-click on non-editable cell scrolls arrange to item
      if ilb_dblclick_item then
        local item = ilb_dblclick_item.__item
        if item and reaper.ValidatePtr(item, "MediaItem*") then
          reaper.Main_OnCommand(40289, 0)  -- Unselect all items
          reaper.SetMediaItemSelected(item, true)
          reaper.Main_OnCommand(40913, 0)  -- Scroll view to selected items
          reaper.UpdateArrange()
        end
      end

      reaper.ImGui_PopID(ctx)
    end

    reaper.ImGui_EndTable(ctx)

    -- Right-click context menu on table area
    if reaper.ImGui_BeginPopupContextItem(ctx, "table_context_menu") then
      if reaper.ImGui_MenuItem(ctx, "Reset Column Widths") then
        RESET_COLUMN_WIDTHS = true
      end

      if reaper.ImGui_MenuItem(ctx, "Show Column Widths (Console)") then
        -- Log current column widths to console
        reaper.ShowConsoleMsg("\n=== Current Column Widths ===\n")
        reaper.ShowConsoleMsg("Showing DEFAULT widths from COL_WIDTH table:\n\n")

        local order = (COL_ORDER and #COL_ORDER > 0) and COL_ORDER or {
          1, 2, 3, 12, 13, 31, 4, 5, 6, 32, 33, 34, 7, 8, 9, 10, 11,
          14, 15, 16, 17, 18, 19, 20, 21,
          22, 23, 24, 25, 26, 27, 28,
          29, 30
        }

        for i, col_id in ipairs(order) do
          local label = header_label_from_id(col_id)
          local width = COL_WIDTH[col_id] or 100
          if width < 0 then width = 150 end
          reaper.ShowConsoleMsg(string.format("[%2d] %-20s = %3dpx\n", col_id, label, width))
        end
        reaper.ShowConsoleMsg("\nEdit COL_WIDTH table (line ~3260) to customize defaults\n")
        reaper.ShowConsoleMsg("=============================\n\n")
      end

      reaper.ImGui_Separator(ctx)

      if reaper.ImGui_MenuItem(ctx, "Edit Columns...") then
        reaper.ImGui_OpenPopup(ctx, "Column Preset Editor")
      end

      reaper.ImGui_Separator(ctx)

      local show_muted_label = SHOW_MUTED and "Hide Muted Items" or "Show Muted Items"
      if reaper.ImGui_MenuItem(ctx, show_muted_label) then
        SHOW_MUTED = not SHOW_MUTED
      end

      reaper.ImGui_EndPopup(ctx)
    end

  end
end





---------------------------------------
-- Main loop
---------------------------------------
local LAST_FRAME_TIME = 0  -- Prevent multiple calls per frame

local function loop()
  -- Prevent multiple loop calls within same frame (during dock/undock transitions)
  local current_time = reaper.time_precise()
  if current_time == LAST_FRAME_TIME then
    reaper.defer(loop)
    return
  end
  LAST_FRAME_TIME = current_time

  -- Ensure ctx exists and is valid
  if not ctx or not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    reaper.ShowConsoleMsg("[ILB] ERROR: ImGui context is invalid! Attempting to recreate...\n")
    -- Try to recreate context
    ctx = reaper.ImGui_CreateContext('Item List Browser')
    if not ctx or not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
      reaper.ShowConsoleMsg("[ILB] FATAL: Failed to recreate ImGui context. Exiting.\n")
      -- Clear running flag before exit
      reaper.SetExtState("hsuanice_ItemListBrowser_Running", "running", "0", false)
      return
    end
    reaper.ShowConsoleMsg("[ILB] Successfully recreated ImGui context.\n")
  end

  -- Increment frame counter
  FRAME_COUNT = FRAME_COUNT + 1

  -- Begin window - MUST be paired with End() regardless of result
  reaper.ImGui_SetNextWindowSize(ctx, 1000, 640, reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoCollapse()
  if not ALLOW_DOCKING then
    flags = flags | reaper.ImGui_WindowFlags_NoDocking()  -- Disable docking to prevent crashes
  end
  local visible, open = reaper.ImGui_Begin(ctx, "Item List Browser"..LIBVER, true, flags)

  if visible then
    -- Get current window size for responsive layout (safe to call inside visible check)
    local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
    -- Push custom font size if not default (track this frame's state)
    font_pushed_this_frame = false
    local style_pushed = false
    if current_font_size ~= 13 and reaper.ImGui_PushFont then
      local scale = get_ui_scale()
      reaper.ImGui_PushFont(ctx, nil, current_font_size)
      font_pushed_this_frame = true

      -- Also scale all UI elements proportionally
      if reaper.ImGui_PushStyleVar and reaper.ImGui_StyleVar_FramePadding then
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 4.0 * scale, 3.0 * scale)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8.0 * scale, 4.0 * scale)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemInnerSpacing(), 4.0 * scale, 4.0 * scale)
        style_pushed = true
      end
    end

    -- Skip all content on first frame to avoid ImGui context initialization issues
    if FRAME_COUNT > 1 then
      -- Smart refresh (after ImGui window is created)
      smart_refresh()

      -- ILB: sync REAPER selection to table highlight (throttled)
      sync_reaper_selection_to_list()

      -- Process project scan batch if active
      if PROJECT_SCAN.active then
        process_project_scan_batch()
      end

      -- ESC closes the window (if Summary modal is open, close modal only first)
      -- Also cancel project scan if active
      if esc_pressed() and not reaper.ImGui_IsPopupOpen(ctx, POPUP_TITLE) then
        if PROJECT_SCAN.active then
          PROJECT_SCAN.active = false
          PROJECT_SCAN.cancelled = true
          console_force("[ILB] Project scan cancelled by user\n")
          CACHE_LIB.flush()  -- Save partial cache (shared library)
        else
          open = false
        end
      end




      -- Top bar + Summary popup
      draw_toolbar()
      draw_summary_popup()   -- keep this line
      draw_advanced_sort_popup()  -- Advanced Sort dialog

      -- Calculate table height: window height minus toolbar and minimal padding
      -- Use GetCursorPosY to get actual toolbar height instead of estimating
      local toolbar_end_y = reaper.ImGui_GetCursorPosY(ctx)
      local bottom_padding = scale(8)  -- Minimal padding at bottom
      local table_height = win_h - toolbar_end_y - bottom_padding

      -- Use get_view_rows() to respect "Show muted items" toggle
      local rows_to_show = get_view_rows()
      draw_table(rows_to_show, table_height)

      -- Clipboard shortcuts (when NOT in InputText editing)
      if not (EDIT and EDIT.col) then
        -- Copy selection (follows visible rows & on-screen column order)
        if shortcut_pressed(reaper.ImGui_Key_C()) then
          local rows = get_view_rows()                     -- Visible rows (matches UI)
          local rim  = LT.build_row_index_map(rows)        -- guid -> row_index
          local tsv  = LT.copy_selection(
            rows, rim, sel_has, COL_ORDER, COL_POS,
            function(i, r, col) return get_cell_text(i, r, col, "tsv") end
          )
          if tsv and tsv ~= "" then
            reaper.ImGui_SetClipboardText(ctx, tsv)
          end
        end

        -- Cut selection (Copy + Delete, Live only)
        if shortcut_pressed(reaper.ImGui_Key_X()) and TABLE_SOURCE == "live" then
          -- First copy to clipboard
          local rows = get_view_rows()
          local rim  = LT.build_row_index_map(rows)
          local tsv  = LT.copy_selection(
            rows, rim, sel_has, COL_ORDER, COL_POS,
            function(i, r, col) return get_cell_text(i, r, col, "tsv") end
          )
          if tsv and tsv ~= "" then
            reaper.ImGui_SetClipboardText(ctx, tsv)
            -- Then delete selected cells
            delete_selected_cells()
          end
        end

        -- Paste (live only, Excel-style rules)
        if shortcut_pressed(reaper.ImGui_Key_V()) then
      -- Check if anything is selected
      if not SEL or not SEL.cells or next(SEL.cells) == nil then
        reaper.ShowMessageBox("No cells selected. Please select target cells before pasting.", "Pasting", 0)
        goto PASTE_END
      end

      -- Parse clipboard -> flatten source
      local clip = reaper.ImGui_GetClipboardText(ctx) or ""
      local tbl  = parse_clipboard_table(clip)
      local src  = flatten_tsv_to_list(tbl)
      if #src == 0 then goto PASTE_END end
      local src_h, src_w = src_shape_dims(tbl)

      -- Destination cells (row-major, left to right); includes all selected cols but only writes 3/4/5
      local rows = get_view_rows()
      local dst  = LT.build_dst_list_from_selection(rows, sel_has, COL_ORDER, COL_POS)
      if #dst == 0 then goto PASTE_END end

      -- Write handler: only operates on columns 3/4/5
      local tracks_renamed, takes_named, notes_set, takes_created, skipped = 0,0,0,0,0
      -- Key lines shown; rest follows existing logic (Track/Take/Item Note write with ValidatePtr)
      local function apply_cell(d, val)
        local col = d.col
        local r   = rows[d.row_index]              -- get row by index
        if not r then return end

        if col == 3 then
          local tr = r.track or r.__track          -- compatible with both field names
          if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
            local cur = r.track_name or ""
            if val ~= cur then
              reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", val, true)
              r.track_name = val                  -- sync rows
            end
          end

        elseif col == 4 then
          local it = r.item or r.__item
          local tk = r.take or r.__take or (it and reaper.GetActiveTake(it))
          if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") then
            local cur = r.take_name or ""
            if val ~= cur then
              reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", val, true)
              r.take_name = val
            end
          end
          -- To restore "auto-create take if missing" behavior, add a preference toggle for AddTake here

        elseif col == 5 then
          local it = r.item or r.__item
          if it and reaper.ValidatePtr(it, "MediaItem*") then
            local cur = r.item_note or ""
            if val ~= cur then
              reaper.GetSetMediaItemInfo_String(it, "P_NOTES", val, true)
              r.item_note = val
            end
          end
        end
      end

      -- Single Undo: fill single value; truncate multi; expand by source shape if 1 cell selected; fill-down for single-row source
      reaper.Undo_BeginBlock2(0)

      -- Parse clipboard to 2D table
      local clip = reaper.ImGui_GetClipboardText(ctx) or ""
      local tbl  = LT.parse_clipboard_table(clip)
      if not tbl or #tbl == 0 then goto PASTE_END end

      -- Write handler (only processes cols 3/4/5; other columns ignored by apply_cell_cb)
      local function apply_cell(d, val)
        local r = rows[d.row_index]
        local col = d.col
        if col == 3 then
          local tr = r.track or r.__track
          if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
            reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", tostring(val or ""), true)
            r.track_name = tostring(val or "")
          end
        elseif col == 4 then
          local tk = r.take or r.__take or ((r.item or r.__item) and reaper.GetActiveTake(r.item or r.__item))
          if not tk and (r.item or r.__item) then
            tk = reaper.AddTakeToMediaItem(r.item or r.__item); r.__take = tk
          end
          if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") then
            reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", tostring(val or ""), true)
            r.take_name = tostring(val or "")
          end
        elseif col == 5 then
          local it = r.item or r.__item
          if it and reaper.ValidatePtr(it, "MediaItem*") then
            reaper.GetSetMediaItemInfo_String(it, "P_NOTES", tostring(val or ""), true)
            r.item_note = tostring(val or "")
          end
        end
      end

      -- Single Undo: delegate to Library for dispatch
      reaper.Undo_BeginBlock2(0)
      LT.apply_paste(rows, dst, tbl, COL_ORDER, COL_POS, apply_cell)
      reaper.Undo_EndBlock2(0, "[ILB] Paste", 4|1)  -- UNDO_STATE_ITEMS | UNDO_STATE_TRACKCFG

      -- Invalidate cache and immediately refresh affected rows
      local affected_guids = {}
      for _, d in ipairs(dst) do
        local r = rows[d.row_index]
        if r and r.__item_guid then
          affected_guids[#affected_guids+1] = r.__item_guid
        end
      end
      CACHE_LIB.invalidate_items(affected_guids)
      refresh_rows_by_guids(affected_guids)  -- Immediate visual feedback

      reaper.UpdateArrange()
      -- No need for mark_dirty() - rows already refreshed

      -- (Optional) status bar summary; skip if not available
      -- status(string.format("Paste: trk=%d, take=%d (+%d), note=%d, skipped=%d",
      --   tracks_renamed, takes_named, takes_created, notes_set, skipped))

          ::PASTE_END::
        end

        -- Delete (live only): Delete or Backspace key
        if TABLE_SOURCE == "live" then
          local del_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete(), false)
                           or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace(), false)
          if del_pressed then
            delete_selected_cells()
          end
        end
      end  -- End of: if not (EDIT and EDIT.col)

      -- Undo / Redo (project level; preserves item selection) - MOVED OUTSIDE editing check
      -- Only process when ILE window is focused or hovered (to capture keyboard input)
      if reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
         or reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_RootAndChildWindows()) then
        local m = _mods()
        if m.shortcut then
          -- Snapshot current selection (by GUID)
          local sel_snapshot = _snapshot_selected_item_guids()

          -- Check Redo first: Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y
          local redo_combo = (m.shift and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z(), false))
                          or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Y(), false)
          if redo_combo then
            reaper.ShowConsoleMsg("[ILB] Redo triggered\n")
            reaper.Undo_DoRedo2(0)
            _restore_item_selection_by_guids(sel_snapshot)

            -- Immediately refresh all rows after redo
            ROWS = scan_selection_rows()
            reaper.ShowConsoleMsg("[ILB] Refreshed after redo\n")
          elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z(), false) then
            -- Undo: Cmd/Ctrl+Z
            reaper.ShowConsoleMsg("[ILB] Undo triggered\n")
            reaper.Undo_DoUndo2(0)
            _restore_item_selection_by_guids(sel_snapshot)

            -- Immediately refresh all rows after undo
            ROWS = scan_selection_rows()
            reaper.ShowConsoleMsg("[ILB] Refreshed after undo\n")
          end
        end
      end  -- End of: if window focused/hovered

    end  -- End of: if FRAME_COUNT > 1

    -- Pop style vars if we pushed them
    if style_pushed and reaper.ImGui_PopStyleVar then
      reaper.ImGui_PopStyleVar(ctx, 3)  -- Pop 3 style vars
    end

    -- Pop font if we pushed one this frame
    if font_pushed_this_frame and reaper.ImGui_PopFont then
      reaper.ImGui_PopFont(ctx)
    end
  end  -- End of: if visible then

  -- MUST call End() to match Begin() - no exceptions!
  reaper.ImGui_End(ctx)

  -- Continue running based on `open`; ESC handling is done above
  if open then
    reaper.defer(loop)
  else
    -- Save cache and prefs before exiting
    CACHE_LIB.flush()
    save_prefs()
    -- Clear running flag
    reaper.SetExtState("hsuanice_ItemListBrowser_Running", "running", "0", false)
  end
end

-- Boot
-- Prevent multiple instances (with stale flag cleanup)
local INSTANCE_KEY = "hsuanice_ItemListBrowser_Running"
local was_running = reaper.GetExtState(INSTANCE_KEY, "running")

-- Check if truly running by verifying ImGui context exists
if was_running == "1" then
  -- Try to detect if it's really running or just a stale flag
  local test_ctx = reaper.ImGui_CreateContext('ILB_Test')
  if test_ctx then
    -- If we can create a test context, the old flag is probably stale
    reaper.ShowConsoleMsg("[ILB] Detected stale running flag, clearing...\n")
    reaper.SetExtState(INSTANCE_KEY, "running", "0", false)
    reaper.ImGui_DestroyContext(test_ctx)
  else
    -- Really running
    reaper.ShowMessageBox(
      "Item List Browser is already running!\n\n" ..
      "Close the existing window before starting a new instance.",
      "Already Running",
      0
    )
    return
  end
end

-- Mark instance as running
reaper.SetExtState(INSTANCE_KEY, "running", "1", false)  -- false = don't persist

if not ctx then
  reaper.ShowConsoleMsg("[ILB] FATAL: Failed to create ImGui context!\n")
  reaper.SetExtState(INSTANCE_KEY, "running", "0", false)  -- Clear flag
  return
end

-- Initialize cache system (using shared Metadata Cache library)
CACHE_LIB.init()
CACHE_LIB.set_debug(DEBUG)  -- Set cache debug mode from saved preference
if DEBUG then
  original_ShowConsoleMsg("[ILB] Cache initialized (shared library)\n")
end

-- ILB: always load all project items on startup
NEEDS_REFRESH = true

-- Cleanup on exit
reaper.atexit(function()
  reaper.SetExtState(INSTANCE_KEY, "running", "0", false)
  CACHE_LIB.flush()
  save_prefs()
end)

loop()  -- Start UI main loop
