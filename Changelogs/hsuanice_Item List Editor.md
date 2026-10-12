# hsuanice_Item List Editor.lua — Changelog

Item List Editor

## 26.1012.1113

- Released as part of the 26.1012.1113 package update.

History before 26.1012.1113 (moved out of the script header; last header version: `260904.0819`).

```text
v260904.0819
- Fix: Prevented a nil-function error when selecting a large number of items.
  • Forward-declared item_selection_signature before progressive loading uses
    it, so all selection-change checks resolve to the local helper correctly.

v260824.1538
- Fix: ReaImGui compatibility on stale-instance cleanup.
  • Guarded `ImGui_DestroyContext` call to avoid nil-value crash on builds
    where this API is unavailable.

v260711.1941
- UX: Disambiguated metadata TAKE vs REAPER item take slot naming.
  • Metadata column keeps original label "TAKE".
  • Active REAPER take column renamed to "Takes".
  • "Takes" shows values like "1/2" and "2/2".

v260711.1937
- Feature: Added current take slot column.
  • New read-only column: "Takes" (e.g. "1/2", "2/2").
  • Updates immediately when switching active take on the same item.
  • Included in table sorting, copy/export, and column preset visibility/order.
- Performance note:
  • Active-take detection adds lightweight take index reads only.
  • Metadata parsing/caching flow is unchanged; practical overhead is minimal.

v260711.1924
- Fix: Auto-refresh now detects active-take switches on the same item.
  • Selection hash now uses item GUID + I_CURTAKE (active take index), not GUID alone.
  • Metadata rows refresh correctly when toggling take 1/2, 2/2 without requiring
    extra operations (e.g. duplicate item) to force redraw.
  • Progressive loading selection-change detection now also tracks active take.
- Performance: Minimal impact.
  • Added one lightweight I_CURTAKE read per sampled selected item during hash checks.
  • Existing throttling/sampling behavior is unchanged.

v260129.1920
- Fix: Bit Depth column not displaying for some items
  • Fixed inconsistent Bit Depth reading from WAV file headers
  • All valid WAV files now correctly show Bit Depth value

v260129.1600
- Feature: Added file info columns
  • Sample Rate: from REAPER API (fast, no external tools)
  • Bit Depth: read from WAV file header (bytes 34-35)
  • File Type: from REAPER API (e.g. WAV, AIFF, MP3)
  • Columns 32-34, positioned after Source File in default order
  • Total column count: 31 → 34

v251210.2210 (2024-12-10)
- Feature: Persistent Debug Mode with UI toggle
  • Debug Mode setting now persists across sessions via ExtState
  • Toggle via Options menu → Debug Mode (shows ✓ when enabled)
  • Controls both ILE console output and Cache Library debug logging
  • When enabled, shows: ILE initialization messages, cache behavior (HIT/MISS/STORE)
  • Setting automatically restored when reopening script
- UX: Cleaner console output by default
  • Initialization messages ("[ILE] Loaded Metadata Cache library", "[ILE] Cache initialized")
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
```
