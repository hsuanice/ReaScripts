--[[
@description Item List Editor
@version 251024_2105
@author hsuanice
@about
  Shows a live, spreadsheet-style table of the currently selected items and all
  sort-relevant fields:
    • Track Index / Track Name
    • Take Name
    • Item Note
    • Source File
    • Metadata Track Name (resolved by Interleave, Wave Agent–style)
    • Channel Number (recorder channel, TRK#)
    • Interleave (1..N from REAPER take channel mode: Mono-of-N)
    • Item Start / End (toggle display format)

  Features:
    • Inline editing of Track Name, Take Name, and Item Note
    • Excel-like selection model (click, Shift rectangle, Cmd/Ctrl multi-select)
    • Copy and Paste with spill/fill rules, one undo per operation
    • Drag-reorderable columns; Copy/Export follows on-screen order
    • Export or Copy as TSV/CSV
    • Summary popup: item count, total span, total length, position range
    • Option to hide muted items (rows are filtered, not removed)
    • Progressive loading for large selections (1000+ items)

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

local CACHE_VERSION = "1.0"  -- Bump this to invalidate all caches when metadata logic changes

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
  local cache_dir = get_cache_dir()
  local key = get_project_cache_key()
  return cache_dir .. "/" .. key .. ".cache"
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
    -- Format: GUID|mod_time|file_name|interleave|meta_trk_name|channel_num
    local parts = {
      guid,
      tostring(meta.mod_time or 0),
      meta.file_name or "",
      tostring(meta.interleave or 0),
      meta.meta_trk_name or "",
      tostring(meta.channel_num or 0)
    }
    -- Escape pipes in data
    for i = 3, #parts do
      parts[i] = parts[i]:gsub("|", "\\|")
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
      -- Parse data line: GUID|mod_time|file_name|interleave|meta_trk_name|channel_num
      local parts = {}
      for part in line:gmatch("([^|]+)") do
        parts[#parts + 1] = part:gsub("\\|", "|")  -- Unescape pipes
      end

      if #parts >= 6 then
        local guid = parts[1]
        cache_data.items[guid] = {
          mod_time = tonumber(parts[2]) or 0,
          file_name = parts[3],
          interleave = tonumber(parts[4]) or 0,
          meta_trk_name = parts[5],
          channel_num = tonumber(parts[6]) or 0
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
    reaper.ShowConsoleMsg(string.format("[ILE Cache] Loaded cache: %d items\n",
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
    reaper.ShowConsoleMsg("[ILE Cache] Warning: Failed to write cache file\n")
    return false
  end

  file:write(content)
  file:close()

  reaper.ShowConsoleMsg(string.format("[ILE Cache] Saved cache: %d items\n",
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
  debug = false,       -- Enable debug logging (set via UI or console)
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
      reaper.ShowConsoleMsg("[ILE Cache] Project modified, cache may be stale\n")
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
    channel_num = metadata.channel_num or 0
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
    reaper.ShowConsoleMsg(string.format("[ILE Cache] Stats: %d hits, %d misses (%d%% hit rate)\n",
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
    reaper.ShowConsoleMsg(string.format("[ILE Cache] Invalidated %d items\n", count))
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
  reaper.ShowConsoleMsg("[ILE Cache] Cache cleared\n")
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
-- Dependency check for ImGui
---------------------------------------
if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui is required (install via ReaPack).", "Missing dependency", 0)
  return
end

---------------------------------------
-- ImGui setup
---------------------------------------
-- ImGui setup (唯一的一組，請勿重複建立)
local ctx = reaper.ImGui_CreateContext('Item List Editor')

-- Debug: Check context creation
if ctx then
  reaper.ShowConsoleMsg(string.format("[ILE] ImGui context created: %s (type: %s)\n",
    tostring(ctx), type(ctx)))
else
  reaper.ShowConsoleMsg("[ILE] ERROR: Failed to create ImGui context!\n")
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



-- Popup title（供 ESC 判斷與 BeginPopupModal 使用）
local POPUP_TITLE = "Summary"



---------------------------------------
-- Small utils
---------------------------------------

-- Forward declarations so load_prefs() updates the same locals (not globals)
local TIME_MODE, CUSTOM_PATTERN, FORMAT, AUTO
local SHOW_MUTED_ITEMS      -- ← 新增：是否顯示「被靜音的列」
local scan_selection_rows
local refresh_now          -- ← 新增：先宣告 refresh_now，讓上面函式抓到 local
local _trim               -- ← 新增：先宣告 _trim，供前面函式當作同一個 local 來引用

-- defaults
if SHOW_MUTED_ITEMS == nil then SHOW_MUTED_ITEMS = true end


-- log
local function log(fmt, ...)
  reaper.ShowConsoleMsg((fmt.."\n"):format(...))
end



-- Column order mapping (single source of truth)
local COL_ORDER, COL_POS = {}, {}   -- visual→logical / logical→visual





-- === Preferences (persist across runs) ===
local EXT_NS = "hsuanice_ItemListEditor"

local function save_prefs()
  reaper.SetExtState(EXT_NS, "time_mode", TIME_MODE or "", true)
  reaper.SetExtState(EXT_NS, "custom_pattern", CUSTOM_PATTERN or "", true)
  reaper.SetExtState(EXT_NS, "auto_refresh", AUTO and "1" or "0", true)
end

-- ===== BEGIN Column Presets (named) =====
-- Persist multiple named presets. No auto-save. Recall explicitly by user.
-- Keys:
--   col_presets             = "name1|name2|..."
--   col_preset_active       = last selected name (optional)
--   col_preset.<sanitized>  = "1,2,3,...,13" (logical column IDs)

local PRESETS, PRESET_SET = {}, {}     -- list + set of names
local ACTIVE_PRESET = nil              -- string or nil
local PRESET_STATUS = "No preset"
local PRESET_NAME_BUF = ""             -- popup input buffer

local function _csv_from_order(order)
  local t = {}
  for i=1,#(order or {}) do t[i] = tostring(order[i]) end
  return table.concat(t, ",")
end

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
  for id=1,13 do if not seen[id] then out[#out+1]=id end end
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

local function preset_save_as(name, order)
  name = _sanitize_name(name)
  if name == "" then PRESET_STATUS = "Name required"; return false end
  order = _normalize_full_order(order or COL_ORDER)
  reaper.SetExtState(EXT_NS, _key_for(name), _csv_from_order(order), true)
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
  local ord = _order_from_csv(payload)
  if ord and #ord>0 then
    ord = _normalize_full_order(ord)
    COL_ORDER = ord
    COL_POS = {}
    for vis,id in ipairs(ord) do if id then COL_POS[id]=vis end end
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

-- 讓 UI 右上角的下拉選單可以拿到所有名稱
local function preset_list()
  return PRESETS
end

-- 讓 Summary 右側的小字狀態能顯示目前狀態
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

  -- restpre auto-refresh state
  local a = reaper.GetExtState(EXT_NS, "auto_refresh")
  if a ~= "" then AUTO = (a ~= "0") end

  -- Column presets (named) — initialize index and optionally recall last active
  presets_init()
end



-- Runtime cache
local PRESET = nil          -- {logical_id,...} read from ExtState
local LAST_SAVED_STR = nil  -- csv cache for quick compare
local PRESET_STATUS = ""    -- "Preset ✓" / "Column not saved" 等小字提示

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
  -- 確保包含 1..13 全部欄位，缺的補上（避免舊版本或不完整資料）
  local seen, out = {}, {}
  for i=1,#(order or {}) do
    local v = tonumber(order[i]); if v and not seen[v] then seen[v]=true; out[#out+1]=v end
  end
  for id=1,13 do if not seen[id] then out[#out+1]=id end end
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
  -- fallback: 支援 m:s / TC / Beats（三種）
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
    headers=function(mode)
      if mode=="tc" then return "Start (TC)","End (TC)" end
      if mode=="beats" then return "Start (Beats)","End (Beats)" end
      if mode=="sec" then return "Start (s)","End (s)" end
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

  -- 如果你已有 format_time()，直接用。沒有的話，改用下面 fallback：
  local function _fmt(sec)
    if format_time then return format_time(sec) end
    -- fallback: 直接用 TFLib 依目前 TIME_MODE 格式化
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



-- forward locals (避免之後被重新 local 化)
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

-- 可附帶標籤與 COL_POS 的即時輸出
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

  -- Keep object references for editing
  row.__item  = item
  row.__track = tr

  -- Placeholder for metadata (to be loaded later)
  row.file_name = ""
  row.interleave = 0
  row.meta_trk_name = ""
  row.channel_num = 0
  row.__metadata_loaded = false  -- Flag for lazy loading

  return row
end

-- Slow: load full metadata for a row (called on demand or in background)
-- Now with cache support!
local function load_metadata_for_row(row)
  if row.__metadata_loaded then return end

  local item = row.__item
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then return end

  local item_guid = row.__item_guid

  -- Try cache first
  local cached = cache_lookup(item_guid, item)
  if cached then
    -- Cache hit! Use cached metadata
    row.file_name = cached.file_name
    row.interleave = cached.interleave
    row.meta_trk_name = cached.meta_trk_name
    row.channel_num = cached.channel_num
    row.__metadata_loaded = true
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
  row.__fields      = f
  row.__metadata_loaded = true

  -- Store in cache for next time
  cache_store(item_guid, item, {
    file_name = row.file_name,
    interleave = row.interleave,
    meta_trk_name = row.meta_trk_name,
    channel_num = row.channel_num
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
  PROGRESSIVE.items = get_selected_items_sorted()
  PROGRESSIVE.loaded_count = 0
  PROGRESSIVE.metadata_index = 0
  PROGRESSIVE.phase = 1
  PROGRESSIVE.active = (#PROGRESSIVE.items > 0)
  PROGRESSIVE.start_time = reaper.time_precise()

  -- Generate hash to detect selection changes
  local hash_parts = {}
  for i = 1, math.min(#PROGRESSIVE.items, 20) do
    local _, guid = reaper.GetSetMediaItemInfo_String(PROGRESSIVE.items[i], "GUID", "", false)
    hash_parts[#hash_parts + 1] = guid
  end
  PROGRESSIVE.selection_hash = table.concat(hash_parts, "|")

  -- Clear current rows, show loading state
  ROWS = {}
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
      reaper.ShowConsoleMsg(string.format("[ILE] Phase 1 complete: %d items in %.2fs (basic fields loaded)\n",
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
      reaper.ShowConsoleMsg(string.format("[ILE] Phase 1: %d/%d (%d%%) - batch size: %d\n",
        PROGRESSIVE.loaded_count, total, percent, PROGRESSIVE.batch_size))
    end
  elseif PROGRESSIVE.phase == 2 then
    -- Phase 2: log every 20 batches (less frequent)
    if PROGRESSIVE.metadata_index % (PROGRESSIVE.batch_size * 20) < PROGRESSIVE.batch_size then
      local percent = math.floor((PROGRESSIVE.metadata_index / total) * 100)
      reaper.ShowConsoleMsg(string.format("[ILE] Phase 2 (metadata): %d/%d (%d%%)\n",
        PROGRESSIVE.metadata_index, total, percent))
    end
  end

  -- Check if fully complete (phase 2 done)
  if PROGRESSIVE.phase == 2 and PROGRESSIVE.metadata_index >= total then
    PROGRESSIVE.active = false
    local elapsed = reaper.time_precise() - PROGRESSIVE.start_time
    -- Log completion time
    reaper.ShowConsoleMsg(string.format("[ILE] Fully completed: %d items in %.2fs (metadata loaded)\n",
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

-- Data
ROWS = {}

-- Current formatter（會在切換模式/修改 pattern 時重建）
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

-- 取得目前是否按住 CmdOrCtrl / Shift
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












-- 計算矩形選取（anchor 與目前 guid,col 之間）
local function sel_rect_apply(rows, row_index_map, cur_guid, cur_col)
  if not (SEL.anchor and SEL.anchor.guid and SEL.anchor.col) then
    SEL.anchor = { guid = cur_guid, col = cur_col }
    -- 只清已選的 cells，不要清掉 anchor
    SEL.cells = {}; sel_add(cur_guid, cur_col)
    return
  end
  SEL.cells = {}
  local a_idx = row_index_map[SEL.anchor.guid] or 1
  local b_idx = row_index_map[cur_guid] or a_idx
  local r1, r2 = math.min(a_idx, b_idx), math.max(a_idx, b_idx)

  -- 依畫面順序的欄位位置算矩形，再轉回邏輯欄位 id
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
end  -- ★★★ 補這個 end，結束 sel_rect_apply() 函式

-- 取得某格「顯示用文字」（複製用；與 UI 呈現一致）
local function get_cell_text(i, r, col, fmt)
  if     col == 1  then return tostring(i)
  elseif col == 2  then return tostring(r.track_idx or "")
  elseif col == 3  then return tostring(r.track_name or "")
  elseif col == 4  then return tostring(r.take_name or "")
  elseif col == 5  then return tostring(r.item_note or "")
  elseif col == 6  then return tostring(r.file_name or "")
  elseif col == 7  then return tostring(r.meta_trk_name or "")
  elseif col == 8  then return tostring(r.channel_num or "")
  elseif col == 9  then return tostring(r.interleave or "")
  elseif col == 10 then return r.muted and "M" or ""
  elseif col == 11 then return tostring(r.color_hex or "")
  elseif col == 12 then return FORMAT(r.start_time)
  elseif col == 13 then return FORMAT(r.end_time)
  end
  return ""
end



-- Delegate to Library: return visible rows (honors Show muted items toggle)
local function get_view_rows()
  return LT.filter_rows(ROWS, { show_muted = SHOW_MUTED_ITEMS })
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
  if col_id == 9  then return "Interleave" end
  if col_id == 10 then return "Mute" end
  if col_id == 11 then return "Color" end
  if col_id == 12 or col_id == 13 then
    local sh, eh = TFLib.headers(TIME_MODE, {pattern=CUSTOM_PATTERN})
    return (col_id == 12) and sh or eh
  end
  return tostring(col_id)
end

-- === Header label helpers (for mapping display order) ===
-- 依你目前的邏輯欄位 ID 來填；4/5/12/13 的 Start/End 會用 FORMAT 抬頭
local HEADER_BY_ID = {
  [1]  = "#",
  [2]  = "TrkID",
  [3]  = "Track Name",
  [4]  = "Take Name",
  [5]  = "Item Note",
  [6]  = "Source File",
  [7]  = "Meta Trk Name",
  [8]  = "Chan#",
  [9]  = "Interleave",
  [10] = "Mute",
  [11] = "Color",
  [12] = nil,  -- Start (動態)
  [13] = nil,  -- End   (動態)
}

local function current_start_label()
  -- 這裡沿用你畫抬頭用的同一套邏輯 / TFLib
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
  -- 時間欄位標題是動態的，要先取出目前的 Start/End 名稱來比對
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

-- 讀取「顯示欄位順序」→ COL_ORDER / COL_POS
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

local function rebuild_display_mapping()
  -- 先給個穩定長度
  local cnt = reaper.ImGui_TableGetColumnCount(ctx) or 0
  local old = {}
  for i=1,#(COL_ORDER or {}) do old[i] = COL_ORDER[i] end

  COL_ORDER, COL_POS = {}, {}
  for display_pos = 0, cnt - 1 do
    -- 直接用帶 index 的 API，避免切換 current column 造成讀值落在舊狀態
    local label = reaper.ImGui_TableGetColumnName(ctx, display_pos) or ""
    local id    = _colid_from_label(label)
    if id then
      COL_ORDER[display_pos + 1] = id
      COL_POS[id] = display_pos + 1
    end
  end

  -- 讀不到就回退固定順序（保險）
  if #COL_ORDER == 0 then
    COL_ORDER = {1,2,3,12,13,4,5,6,7,8,9,10,11}  -- 你的預設（與畫表頭一致）
    COL_POS = {}; for i,id in ipairs(COL_ORDER) do COL_POS[id] = i end
  end

  if orders_differ(COL_ORDER, old) then
    dump_order_if_changed("ORDER")
  end
end




-- 依「來源形狀」與「單一錨點（選到的一格）」產生展開後的目標格清單（行優先、左到右）
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
  -- 依畫面欄位順序排序（與 COL_ORDER/COL_POS 一致）
  table.sort(dst, function(a,b)
    if a.row_index ~= b.row_index then return a.row_index < b.row_index end
    local pa = (COL_POS and COL_POS[a.col]) or a.col
    local pb = (COL_POS and COL_POS[b.col]) or b.col
    return pa < pb
  end)
  return dst
end

-- 依來源形狀與單一錨點，產生「只落在可寫欄位 3/4/5」的展開目標
local function build_dst_spill_writable(rows, anchor_desc, src_rows, src_cols)
  local dst = {}
  local writable = {3,4,5}
  -- 找到 >= 錨點欄 的第一個可寫欄位；若沒有（例如錨在 6），就用最後一個（5）
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
        if wi > #writable then break end  -- 超出可寫欄位就截斷
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




-- === Undo/Redo 選取保護（以 GUID 快照） ===
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
  -- 先清空目前選取
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  -- 建索引表以加速比對
  local want = {}
  for _, g in ipairs(guids) do if g and g ~= "" then want[g] = true end end
  -- 逐一掃描專案 item，比對 GUID 後重選
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

-- Bulk-commit（一次 Undo、最後再 UpdateArrange/Refresh）
local BULK = false
local function bulk_begin() BULK = true end
local function bulk_end(refresh_cb)
  BULK = false
  reaper.UpdateArrange()
  if type(refresh_cb) == "function" then refresh_cb() end
end


-- 清除目前選取到的「格子文字」（只在 Live 視圖；僅 3/4/5 欄可寫）
local function delete_selected_cells()
  -- 0) 沒選取就離開
  if not SEL or not SEL.cells or next(SEL.cells) == nil then return end

  -- 1) 可見列 + 以畫面欄位順序展開選取
  local rows = get_view_rows()                              -- ← 替代 ROWS
  local dst = LT.build_dst_list_from_selection(rows, sel_has, COL_ORDER, COL_POS)
  if #dst == 0 then return end

  reaper.Undo_BeginBlock2(0)
  local affected_guids = {}
  for i = 1, #dst do
    local d = dst[i]
    local r = rows[d.row_index]             -- ★ 用 row_index 取 row
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
  reaper.Undo_EndBlock2(0, "[ILE] Clear selected cells", 4|1)  -- UNDO_STATE_ITEMS | UNDO_STATE_TRACKCFG

  -- Invalidate cache and immediately refresh affected rows
  cache_invalidate_items(affected_guids)
  refresh_rows_by_guids(affected_guids)  -- Immediate visual feedback

  reaper.UpdateArrange()
  -- No need for mark_dirty() - rows already refreshed
end






local COL = { TRACK_NAME = 3, TAKE_NAME = 4, ITEM_NOTE = 5 } -- 以表頭順序為準（#、TrackIdx、Track Name、Take Name、Item Note、Source File...）

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
    reaper.Undo_EndBlock2(0, "[ILE] "..label, 4|1)  -- UNDO_STATE_ITEMS | UNDO_STATE_TRACKCFG
    reaper.UpdateArrange()
  end
  mark_dirty()  -- Mark refresh needed after edit
  return true
end


-- 寫回：Track / Take / Item Note
local function apply_track_name(tr, newname, rows)
  _commit_if_changed("Rename Track", select(2, reaper.GetTrackName(tr, "")), newname, function(v)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", v, true)
    -- 同一個 track 之所有列同步更新（依物件，而非名字）
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
    cache_invalidate_items({row.__item_guid})
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
    cache_invalidate_items({row.__item_guid})
    refresh_rows_by_guids({row.__item_guid})  -- Immediate visual feedback
  end
end




-- 超薄轉接（保留相容性；也可以讓 table/export 都直接叫 FORMAT(r.start_time)）
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
  ROWS = scan_selection_rows()
  update_selection_cache()
  PROGRESSIVE.active = false  -- Cancel any progressive load
end

-- Start progressive refresh for large selections
local function refresh_progressive()
  local count = reaper.CountSelectedMediaItems(0)

  -- For small selections (<100 items), use immediate refresh
  if count < 100 then
    refresh_now()
    return
  end

  -- For large selections (100+), use progressive loading
  start_progressive_load()
  update_selection_cache()
end

-- Smart refresh: only execute when truly needed
local function smart_refresh()
  -- If progressive loading is active, continue processing batches
  if PROGRESSIVE.active then
    -- Check if selection changed during loading - restart if needed
    if has_selection_changed_during_load() then
      start_progressive_load()  -- Restart with new selection
      return
    end

    -- Process next batch every frame while loading
    process_progressive_batch()
    return
  end

  -- Normal refresh logic (when not progressive loading)
  if not AUTO then return end
  if EDIT and EDIT.col then return end  -- No refresh while editing

  local now = reaper.time_precise()

  -- Check if refresh needed
  local should_refresh = false
  local reason = ""

  -- 1. Dirty flag (marked after manual operations)
  if NEEDS_REFRESH then
    should_refresh = true
    reason = "dirty flag"
  end

  -- 2. Throttle: only check if enough time passed since last refresh
  if (now - LAST_REFRESH_TIME) >= REFRESH_THROTTLE then
    -- 3. Selection change detection
    if has_selection_changed() then
      should_refresh = true
      reason = "selection changed"
    end
  end

  if should_refresh then
    refresh_progressive()  -- Use progressive refresh instead of immediate
  end
end

-- 啟動時讀回上次的模式與 pattern，並重建 FORMAT
if load_prefs then load_prefs() end



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
    -- 依目前顯示來源挑 rows
    local rows = ROWS

    local txt = build_summary_text(rows)

    -- 可選可複製：用唯讀的多行輸入框
    reaper.ImGui_SetNextItemWidth(ctx, 560)
    reaper.ImGui_InputTextMultiline(ctx, "##summary_text", txt, 560, 200,
      reaper.ImGui_InputTextFlags_ReadOnly())

    -- Copy / OK
    if reaper.ImGui_Button(ctx, "Copy", 80, 24) then
      reaper.ImGui_SetClipboardText(ctx, txt)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "OK", 80, 24) 
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
    status_text = string.format("Selected items: %d", #ROWS)
  end
  reaper.ImGui_Text(ctx, status_text)
  reaper.ImGui_SameLine(ctx)
  local chg, v = reaper.ImGui_Checkbox(ctx, "Auto-refresh", AUTO)
  if chg then
    AUTO = v
    reaper.SetExtState(EXT_NS, "auto_refresh", v and "1" or "0", true)
  end
  reaper.ImGui_SameLine(ctx)

-- Show muted items（隱藏被靜音的列；影響當前表格與輸出）
local changed, nv = reaper.ImGui_Checkbox(ctx, "Show muted items", SHOW_MUTED_ITEMS)
reaper.ImGui_SameLine(ctx)
if changed then
  SHOW_MUTED_ITEMS = nv
  EDIT = nil
  sel_clear()
  -- No need for mark_dirty() - get_view_rows() filters instantly
end

  
-- 四種：m:s / TC / Beats / Custom（Input 直接在 Custom 右邊）
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
-- ← 直接接在 Custom 後面放輸入框
reaper.ImGui_SameLine(ctx)
reaper.ImGui_Text(ctx, "Pattern:")
reaper.ImGui_SameLine(ctx)
reaper.ImGui_SetNextItemWidth(ctx, 180)
local changed, newpat = reaper.ImGui_InputText(ctx, "##custom_pattern", CUSTOM_PATTERN)
if changed then
  CUSTOM_PATTERN = newpat
  if TIME_MODE==TFLib.MODE.CUSTOM then
    FORMAT = TFLib.make_formatter(TIME_MODE, {pattern=CUSTOM_PATTERN})
  end
  save_prefs()
end
-- 小提示（hover 顯示）
reaper.ImGui_SameLine(ctx)
reaper.ImGui_TextDisabled(ctx, "ⓘ")
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  reaper.ImGui_Text(ctx, "Tokens: h | hh | m | mm | s | ss | S… (e.g. SSS = .mmm)")
  reaper.ImGui_EndTooltip(ctx)
end



if reaper.ImGui_Button(ctx, "Refresh Now", 110, 24) then
  TABLE_SOURCE = "live"
  refresh_now()  -- Force immediate full refresh (bypasses progressive loading)
end
-- Show hint if progressive loading is active
if PROGRESSIVE.active then
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextDisabled(ctx, "(loading in background...)")
end


reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Copy (TSV)", 110, 24) then
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
      header_label_from_id,                              -- ★ 改這裡：傳入欄頭函式
      function(i, r, col) return get_cell_text(i, r, col, "tsv") end
    )
    if text and text ~= "" then
      reaper.ImGui_SetClipboardText(ctx, text)
    end

  end
end


reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Save .tsv", 100, 24) then
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
if reaper.ImGui_Button(ctx, "Save .csv", 100, 24) then
  local p = choose_save_path("Item List_"..timestamp()..".csv","CSV (*.csv)\0*.csv\0All (*.*)\0*.*\0")
  if p then
    local rows = get_view_rows()
    local text = LT.build_table_text(
      "csv",
      rows,
      COL_ORDER,
      header_label_from_id,                            -- ★
      function(i, r, col) return get_cell_text(i, r, col, "csv") end
    )
    write_text_file(p, text)
  end
end

reaper.ImGui_SameLine(ctx)
-- [ANCHOR] Summary button cluster (REPLACED)
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, POPUP_TITLE, 100, 24) then
  reaper.ImGui_OpenPopup(ctx, POPUP_TITLE)
end

-- Cache management button
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Clear Cache", 100, 24) then
  cache_clear()
  mark_dirty()  -- Trigger refresh to rebuild cache
end
-- Show cache stats on hover
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  local total = CACHE.hits + CACHE.misses
  local hit_rate = (total > 0) and math.floor((CACHE.hits / total) * 100) or 0
  local cached_count = 0
  local invalidated_count = 0
  if CACHE.data and CACHE.data.items then
    for _ in pairs(CACHE.data.items) do cached_count = cached_count + 1 end
  end
  for _ in pairs(CACHE.invalidated or {}) do invalidated_count = invalidated_count + 1 end
  reaper.ImGui_Text(ctx, string.format("Cached: %d items", cached_count))
  reaper.ImGui_Text(ctx, string.format("Hit rate: %d%% (%d/%d)", hit_rate, CACHE.hits, total))
  if invalidated_count > 0 then
    reaper.ImGui_TextColored(ctx, 0xFF6666FF, string.format("Invalidated: %d items", invalidated_count))
  end
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_TextDisabled(ctx, "Right-click for debug mode")
  reaper.ImGui_EndTooltip(ctx)
end
-- Right-click to toggle debug mode
if reaper.ImGui_IsItemClicked(ctx, reaper.ImGui_MouseButton_Right()) then
  CACHE.debug = not CACHE.debug
  if CACHE.debug then
    reaper.ShowConsoleMsg("\n[ILE Cache] Debug mode ENABLED - watch console for detailed cache behavior\n")
    reaper.ShowConsoleMsg("[ILE Cache] Will show: HIT (first 5), MISS (new), MISS (changed), STORE (updated)\n\n")
  else
    reaper.ShowConsoleMsg("[ILE Cache] Debug mode DISABLED\n")
  end
end

-- === Column Presets UI (right of Summary) ===
reaper.ImGui_SameLine(ctx)
reaper.ImGui_Text(ctx, "Preset:")
reaper.ImGui_SameLine(ctx)
do
  local current = ACTIVE_PRESET or "(none)"
  -- 固定預覽欄位寬度，避免太長
  reaper.ImGui_SetNextItemWidth(ctx, 160)
  -- 控制彈出高度不要過長（可捲動）
  if reaper.ImGui_BeginCombo(ctx, "##colpreset_combo", current, reaper.ImGui_ComboFlags_HeightRegular()) then
    -- "(none)"：清空預設，不套用任何儲存的順序
    local sel = (ACTIVE_PRESET == nil)
    if reaper.ImGui_Selectable(ctx, "(none)", sel) then
      ACTIVE_PRESET = nil
      PRESET_STATUS = "No preset"
    end
    reaper.ImGui_Separator(ctx)

    -- 列出使用者命名的所有 preset；選到就「立即套用」
    for i, name in ipairs(PRESETS) do
      local selected = (name == ACTIVE_PRESET)
      if reaper.ImGui_Selectable(ctx, name, selected) then
        ACTIVE_PRESET = name
        preset_recall(name)       -- ← 直接套用，不需要再按 Recall
      end
    end
    reaper.ImGui_EndCombo(ctx)
  end
end

-- 「Save as…」：用使用者自訂名稱另存
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_Button(ctx, "Save as…", 88, 24) then
  PRESET_NAME_BUF = ACTIVE_PRESET or PRESET_NAME_BUF or ""
  reaper.ImGui_OpenPopup(ctx, "Save preset as")
end

-- 「Delete」：刪除目前選到的 preset
reaper.ImGui_SameLine(ctx)
local can_delete = (ACTIVE_PRESET and ACTIVE_PRESET~="")
if reaper.ImGui_BeginDisabled(ctx, not can_delete) then end
if reaper.ImGui_Button(ctx, "Delete", 68, 24) and can_delete then
  preset_delete(ACTIVE_PRESET)
end
if reaper.ImGui_EndDisabled then reaper.ImGui_EndDisabled(ctx) end

-- 小字狀態
reaper.ImGui_SameLine(ctx)
reaper.ImGui_TextDisabled(ctx, PRESET_STATUS or "")

-- Save-as modal
if reaper.ImGui_BeginPopupModal(ctx, "Save preset as", true, TF('ImGui_WindowFlags_AlwaysAutoResize')) then
  reaper.ImGui_Text(ctx, "Preset name:")
  reaper.ImGui_SetNextItemWidth(ctx, 220)
  PRESET_NAME_BUF = PRESET_NAME_BUF or ""
  local changed, txt = reaper.ImGui_InputText(ctx, "##presetname", PRESET_NAME_BUF)
  if changed then PRESET_NAME_BUF = txt end

  if reaper.ImGui_Button(ctx, "Save", 82, 24) then
    if preset_save_as(PRESET_NAME_BUF, COL_ORDER) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Cancel", 82, 24) then
    reaper.ImGui_CloseCurrentPopup(ctx)
  end
  reaper.ImGui_EndPopup(ctx)
end
-----------------------

reaper.ImGui_SameLine(ctx)
reaper.ImGui_TextDisabled(ctx, col_preset_status_text())




end

local function draw_table(rows, height)
  local flags = TF('ImGui_TableFlags_Borders')
            | TF('ImGui_TableFlags_RowBg')
            | TF('ImGui_TableFlags_SizingFixedFit')
            | TF('ImGui_TableFlags_ScrollX')
            | TF('ImGui_TableFlags_Resizable')  
            | TF('ImGui_TableFlags_Reorderable')   -- 允許拖曳重排欄位            
  -- 依目前 ACTIVE_PRESET 生成唯一表格 ID，避免 ImGui 重用舊排序
  -- 原本：local table_id = "items_" . ((ACTIVE_PRESET and ACTIVE_PRESET ~= "" and ACTIVE_PRESET) or "default")
  local table_id = "items_" .. ((ACTIVE_PRESET and ACTIVE_PRESET ~= "" and ACTIVE_PRESET) or "default")
  if reaper.ImGui_BeginTable(ctx, table_id, 13, flags, -FLT_MIN, height or 360) then
    -- 先定義一個 helper（若檔案裡還沒有）
    local function _setup_column_by_id(id)
      local label = header_label_from_id(id) or tostring(id)
      -- 如需寬度/旗標可在這裡加第三參數
      reaper.ImGui_TableSetupColumn(ctx, label, reaper.ImGui_TableColumnFlags_None())
    end

    -- 依現有 COL_ORDER 來畫表頭；若還沒任何順序則用預設
    local DEFAULT_COL_ORDER = { 1, 2, 3, 12, 13, 4, 5, 6, 7, 8, 9, 10, 11 }
    local initial_order = (COL_ORDER and #COL_ORDER > 0) and COL_ORDER or DEFAULT_COL_ORDER
    for i = 1, #initial_order do
      _setup_column_by_id(initial_order[i])
    end


    -- 表頭
    reaper.ImGui_TableHeadersRow(ctx)

    -- IMPORTANT: Rebuild display mapping EVERY FRAME to detect column reordering
    -- ImGui doesn't notify us when user drags columns, so we must check each frame
    rebuild_display_mapping()


    -- 建 row_index_map（給 Shift-矩形選取等）
    local row_index_map = LT.build_row_index_map(rows)



    
    -- 點擊單一格的統一處理：單擊＝選取；Shift＝矩形；Cmd/Ctrl＝增減
    local function handle_cell_click(guid, col)
      local m = _mods()
      if m.shift and SEL.anchor then
        -- 用 Library 內建：視覺欄序（COL_ORDER/COL_POS）版本的矩形選取
        LT.sel_rect_apply(
          rows,
          row_index_map,
          SEL.anchor.guid,  -- anchor guid
          guid,             -- current guid
          SEL.anchor.col,   -- anchor col (邏輯欄位 ID)
          col,              -- current col (邏輯欄位 ID)
          COL_ORDER,        -- 視覺→邏輯欄序
          COL_POS,          -- 邏輯→視覺欄序
          sel_add           -- 把每個被選的 cell 加入 SEL 的 callback
        )


        
      elseif m.shortcut then
        -- 切換單格
        if not SEL.anchor then SEL.anchor = { guid = guid, col = col } end
        sel_toggle(guid, col)
      else
        -- 清空已選 → 設新錨點 → 選單格（避免把剛設的 anchor 清掉）
        sel_clear()
        SEL.anchor = { guid = guid, col = col }
        sel_add(guid, col)
      end
    end

    -- 視覺順序版：依畫面欄位順序（COL_POS/COL_ORDER）做 Shift 矩形
    local function sel_rect_apply_visual(rows, row_index_map, guid, col, COL_ORDER, COL_POS)
      local a = SEL and SEL.anchor
      if not (a and a.guid and a.col) then return end

      -- 轉成「視覺位置」再求區間
      local p1 = (COL_POS and COL_POS[a.col]) or a.col
      local p2 = (COL_POS and COL_POS[col])   or col
      if not (p1 and p2) then return end
      if p1 > p2 then p1, p2 = p2, p1 end        -- 視覺欄位區間（左→右）

      local r1 = row_index_map[a.guid]
      local r2 = row_index_map[guid]
      if not (r1 and r2) then return end
      if r1 > r2 then r1, r2 = r2, r1 end        -- 列區間（上→下）

      -- 以視覺位置回推邏輯欄位，再逐格加入
      -- 保留 anchor，不清空 anchor 本身
      SEL.cells = {}                             -- 只清「選取的格」，錨點照舊
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



    -- === 取代原本每欄固定順序的整段：改成依 COL_ORDER 繪製 ===
    for i, r in ipairs(rows or {}) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_PushID(ctx, (r.__item_guid ~= "" and r.__item_guid) or tostring(i))

      for disp = 1, reaper.ImGui_TableGetColumnCount(ctx) do
        reaper.ImGui_TableSetColumnIndex(ctx, disp-1)
        local col = COL_ORDER[disp]

        if col == 1 then
          local sel = sel_has(r.__item_guid, 1)
          reaper.ImGui_Selectable(ctx, tostring(i).."##c1", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 1) end

        elseif col == 2 then
          local sel = sel_has(r.__item_guid, 2)
          reaper.ImGui_Selectable(ctx, tostring(r.track_idx or "").."##c2", sel)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 2) end

        elseif col == 3 then
          -- Track Name（維持你原本的可編輯行為）
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
            local flags = reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_EnterReturnsTrue()
            local changed, newv = reaper.ImGui_InputText(ctx, "##trk", EDIT.buf, flags)
            if changed then EDIT.buf = newv end
            local submit = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or reaper.ImGui_IsItemDeactivated(ctx)
            local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
            if submit then if r.__track then apply_track_name(r.__track, EDIT.buf, rows) end; EDIT=nil
            elseif cancel then EDIT=nil end
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
          -- Take Name（維持原本可編輯）
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
            local flags = reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_EnterReturnsTrue()
            local changed, newv = reaper.ImGui_InputText(ctx, "##take", EDIT.buf, flags)
            if changed then EDIT.buf = newv end
            local submit = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or reaper.ImGui_IsItemDeactivated(ctx)
            local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
            if submit then apply_take_name(r.__take, EDIT.buf, r); EDIT=nil
            elseif cancel then EDIT=nil end
          end

        elseif col == 5 then
          -- Item Note（維持原本可編輯）
          local note_txt = tostring(r.item_note or "")
          local editing = (EDIT and EDIT.row == r and EDIT.col == 5)
          local sel = sel_has(r.__item_guid, 5)
          if not editing then
            reaper.ImGui_Selectable(ctx, (note_txt ~= "" and note_txt or " ").."##note", sel)
            if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 5) end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and TABLE_SOURCE=="live" then
              EDIT = { row = r, col = 5, buf = note_txt, want_focus = true }
            end
          else
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            if EDIT.want_focus then reaper.ImGui_SetKeyboardFocusHere(ctx); EDIT.want_focus=false end
            local flags = reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_EnterReturnsTrue()
            local changed, newv = reaper.ImGui_InputText(ctx, "##note", EDIT.buf, flags)
            if changed then EDIT.buf = newv end
            local submit = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) or reaper.ImGui_IsItemDeactivated(ctx)
            local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())
            if submit then apply_item_note(r.__item, EDIT.buf, r); EDIT=nil
            elseif cancel then EDIT=nil end
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
        end
      end

      reaper.ImGui_PopID(ctx)
    end

    reaper.ImGui_EndTable(ctx)


  end
end





---------------------------------------
-- Main loop
---------------------------------------
local function loop()
  -- Ensure ctx exists
  if not ctx then
    reaper.ShowConsoleMsg("[ILE] ERROR: ImGui context is nil!\n")
    return
  end

  -- Increment frame counter
  FRAME_COUNT = FRAME_COUNT + 1

  reaper.ImGui_SetNextWindowSize(ctx, 1000, 640, reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoCollapse()
  local visible, open = reaper.ImGui_Begin(ctx, "Item List Editor"..LIBVER, true, flags)

  if visible then
    -- Skip all content on first frame to avoid ImGui context initialization issues
    if FRAME_COUNT > 1 then
      -- Smart refresh (after ImGui window is created)
      smart_refresh()


      -- ESC 關閉整個視窗（若 Summary modal 開著，先只關 modal）
      if esc_pressed() and not reaper.ImGui_IsPopupOpen(ctx, POPUP_TITLE) then
        open = false
      end




      -- Top bar + Summary popup
      draw_toolbar()
      draw_summary_popup()   -- ← 要保留這行

      -- Use get_view_rows() to respect "Show muted items" toggle
      local rows_to_show = get_view_rows()
      draw_table(rows_to_show, 360)

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

        -- Paste（Live only，Excel 風規則）
        if shortcut_pressed(reaper.ImGui_Key_V()) then
      -- 檢查是否有選取      
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

      -- 目標格（行優先、左到右），包含所有被選欄；實際寫回僅 3/4/5
      local rows = get_view_rows()
      local dst  = LT.build_dst_list_from_selection(rows, sel_has, COL_ORDER, COL_POS)
      if #dst == 0 then goto PASTE_END end

      -- 寫入工具：只在 3/4/5 欄動作
      local tracks_renamed, takes_named, notes_set, takes_created, skipped = 0,0,0,0,0
      -- 只示範關鍵幾行，其他維持你現有邏輯（Track/Take/Item Note 寫入與 ValidatePtr）
      local function apply_cell(d, val)
        local col = d.col
        local r   = rows[d.row_index]              -- ★ 改這裡：用 row_index 取 row
        if not r then return end

        if col == 3 then
          local tr = r.track or r.__track          -- 兩種欄位名都相容
          if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
            local cur = r.track_name or ""
            if val ~= cur then
              reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", val, true)
              r.track_name = val                  -- 同步 rows
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
          -- 若你想恢復「沒有 take 時自動建立」的舊行為，可在這裡加偏好開關再 AddTake（可另給我就地 patch）

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

      -- 一次 Undo：單值填滿；多值截斷；若只選 1 格則依來源形狀展開；單列來源可往下填滿
      reaper.Undo_BeginBlock2(0)

      -- 解析剪貼簿 → 2D
      local clip = reaper.ImGui_GetClipboardText(ctx) or ""
      local tbl  = LT.parse_clipboard_table(clip)
      if not tbl or #tbl == 0 then goto PASTE_END end

      -- 寫入工具（只處理 3/4/5；其餘欄 apply_cell_cb 直接忽略）
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

      -- 一次 Undo：交給 Library 做分流
      reaper.Undo_BeginBlock2(0)
      LT.apply_paste(rows, dst, tbl, COL_ORDER, COL_POS, apply_cell)
      reaper.Undo_EndBlock2(0, "[ILE] Paste", 4|1)  -- UNDO_STATE_ITEMS | UNDO_STATE_TRACKCFG

      -- Invalidate cache and immediately refresh affected rows
      local affected_guids = {}
      for _, d in ipairs(dst) do
        local r = rows[d.row_index]
        if r and r.__item_guid then
          affected_guids[#affected_guids+1] = r.__item_guid
        end
      end
      cache_invalidate_items(affected_guids)
      refresh_rows_by_guids(affected_guids)  -- Immediate visual feedback

      reaper.UpdateArrange()
      -- No need for mark_dirty() - rows already refreshed

      --（可選）你若有狀態列，可顯示摘要；沒有就略過
      -- status(string.format("Paste: trk=%d, take=%d (+%d), note=%d, skipped=%d",
      --   tracks_renamed, takes_named, takes_created, notes_set, skipped))

          ::PASTE_END::
        end

        -- Delete（Live only）：Delete 或 Backspace 皆可
        if TABLE_SOURCE == "live" then
          local del_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete(), false)
                           or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace(), false)
          if del_pressed then
            delete_selected_cells()
          end
        end
      end  -- End of: if not (EDIT and EDIT.col)

      -- Undo / Redo（專案層級；保護 item 選取）- MOVED OUTSIDE editing check
      -- Only process when ILE window is focused or hovered (to capture keyboard input)
      if reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_RootAndChildWindows())
         or reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_RootAndChildWindows()) then
        local m = _mods()
        if m.shortcut then
          -- 先快照目前選取（以 GUID）
          local sel_snapshot = _snapshot_selected_item_guids()

          -- 先判斷 Redo：Cmd/Ctrl+Shift+Z 或 Cmd/Ctrl+Y
          local redo_combo = (m.shift and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z(), false))
                          or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Y(), false)
          if redo_combo then
            reaper.ShowConsoleMsg("[ILE] Redo triggered\n")
            reaper.Undo_DoRedo2(0)
            _restore_item_selection_by_guids(sel_snapshot)

            -- Immediately refresh all rows after redo
            ROWS = scan_selection_rows()
            reaper.ShowConsoleMsg("[ILE] Refreshed after redo\n")
          elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z(), false) then
            -- Undo: Cmd/Ctrl+Z
            reaper.ShowConsoleMsg("[ILE] Undo triggered\n")
            reaper.Undo_DoUndo2(0)
            _restore_item_selection_by_guids(sel_snapshot)

            -- Immediately refresh all rows after undo
            ROWS = scan_selection_rows()
            reaper.ShowConsoleMsg("[ILE] Refreshed after undo\n")
          end
        end
      end  -- End of: if window focused/hovered

    end  -- End of: if FRAME_COUNT > 1
  end  -- End of: if visible then

  reaper.ImGui_End(ctx)

  -- GOOD：要不要續跑只看 `open`；按 ESC 的判斷已在上面完成
  if open then
    reaper.defer(loop)
  else
    -- Save cache before exiting
    cache_flush()
    save_prefs()
  end
end

-- Boot
if not ctx then
  reaper.ShowConsoleMsg("[ILE] FATAL: Failed to create ImGui context!\n")
  return
end

-- Initialize cache system
init_cache()

-- Mark that we need initial load (will happen in first frame via smart_refresh)
if AUTO and reaper.CountSelectedMediaItems(0) > 0 then
  NEEDS_REFRESH = true
end

loop()  -- Start UI main loop
