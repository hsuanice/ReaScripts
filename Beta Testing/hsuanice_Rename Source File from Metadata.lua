--[[
@description ReaImGui - Rename Source File from Metadata (cached preview + source rename)
@version 260714.1438
@author hsuanice
@about
  Rename the actual source file on disk from BWF/iXML and true source metadata using a fast ReaImGui UI.
    - Two templates: Take Name + Item Note (empty note template = skip).
    - Click tokens to insert at caret; caret snaps outside existing $tokens.
    - Robust around separators: safe with "--" and "__"; underscores no longer swallow preceding tokens.
    - Reads metadata once per selection ("Get Metadata") and caches it; configurable preview limit.
    - Apply uses current selection; reuses cache if unchanged; Undo / Redo supported.
    - Channel-aware tokens: $trk (auto per-take), $trkN, and $trkall (from iXML/BWF track list, with fallbacks).
    - True source tokens: $srcfile, $srcbase, $srcext, $srcpath, $srcdir (actual media filename/paths).
    - Metadata panel + preview table with quick copy; export preview table as TSV or CSV.
    - Works on audio items; items without takes (empty/MIDI) can still update notes.
    - Requires: ReaImGui (install via ReaPack).
    - Shared metadata cache with Item List Editor for fast performance.


  Features:
  - Built with ReaImGUI for a compact, responsive UI.
  - Designed for fast, keyboard-light workflows.
  - Take Name renamer (multi-rule, user-configurable):
    • Enable/Disable checkbox; stored via ExtState, persistent across sessions.
    • Add unlimited rename rules (From → To); manage with [+] / [-] buttons.
    • Applies after token expansion; affects Take Name only (Note unaffected).
    • Real-time preview update and applied in final Apply/Summary (TSV/CSV export now matches preview).

  References:
  - REAPER ReaScript API (Lua)
  - ReaImGUI (ReaScript ImGui binding)

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v260714.1438 (2026-07-14)
    - Replace Rules: Added a global RegEx checkbox for pattern matching mode.
    - Replace Rules: Preserved leading spaces in Find when RegEx mode is enabled.
    - Workflow: Source renaming now consistently applies Source File Name template first, then Replace Rules.
    - Defaults: Source File Name default template changed to $srcfile.
    - UI: Removed Replace Rules Base override option to avoid bypassing Source File Name input.
    - UX: Clear button for Source File Name now resets to $srcfile.
    - Apply: Removed premature file existence pre-check before os.rename to prevent false skips.
    - Result: Skipped details now include real skip reasons in Apply Result.

  v260710.1425 (2026-07-10)
    - UI: History is now a standalone fold section (separate from Presets) with a Clear All action.
    - UI: Token row simplified by removing $trk1~$trk8 and keeping only one counter token (${counter:2}).
    - Behavior: Apply no longer auto-refreshes preview; preview updates only when user clicks Update Preview.
    - Fix: Rename History preview now reflects persisted note history only (no projected extra row).

  v260710.1356 (2026-07-10)
    - UI: Removed $curnote from the token list and Detected fields to keep the workflow focused on source renaming.
    - UI: Preview now shows rename history instead of Current/New Note columns, with $origsrcfile prioritized in token ordering.
    - Fixed: Recent template History initialization no longer errors on startup when trimming entries.

  v260710.1349 (2026-07-10)
    - UI: Added an Original button under Source File Name to load $origsrcfile directly.
    - UI: Renamed Source File Renamer to Replace Rules and Source Presets to Presets.
    - UI: Added a recent template History dropdown under Presets (keeps the latest 10 entries).

  v260710.1340 (2026-07-10)
    - Changed: Rename history now stores only resulting filenames to reduce Item Note size.
    - Changed: Renaming back to $origsrcfile now clears this script's internal note metadata while preserving visible note text.
    - Compatibility: Legacy history entries in old -> new format are read and normalized automatically.

  v260710.1321 (2026-07-10)
    - New: Added $origsrcfile token for restoring the first saved source filename.
    - New: Rename history is appended to Item Note in a structured internal block.
    - Changed: Visible Item Note text is preserved while internal rename metadata is parsed separately.

  v260709.2218 (2026-07-09)
    - New: Rename the actual source file on disk from metadata-driven templates, not just the take name.
    - New: After a successful rename, update the take name to match the new source filename.
    - New: Save the original source filename in the item note as a rollback reference.
    - UI: Keep the current neutral button palette and darken popup/dropdown menu colors for a softer appearance.
    - Stability: Preserve cached preview, deferred Apply batching, and Undo/Redo support for batch renaming.

  v260319.1448 (2026-03-19)
    - UI: Take Name and Item Note input boxes now have warm amber background (0x332B08)
      • Both fields visually stand out from the rest of the UI

  v260225.2030 (2026-02-25)
    - UI: Preview panel — "Get Metadata (Preview)" button moved from top bar into preview panel header
      • Button label shows "Get Preview" when no cache exists, "Update Preview" when cache is present
      • "Clear" button added next to it (clears cache and preview)
      • "Copy TSV" and "Copy CSV" are right-aligned on the same header row
    - Perf: Removed all live/real-time preview auto-updates triggered by template or setting changes
      • Preview only refreshes when "Get Metadata" / "Update Metadata" is clicked explicitly
    - UI: Item Note input field now matches Take Name visual prominence
      • Label text in warm gold color; InputText box is taller (increased FramePadding)

  v260225.1930 (2026-02-25)
    - UI: Take Name input field is now visually prominent
      • Label text rendered in warm gold color to stand out from other labels
      • InputText box is taller (increased FramePadding) for clear visual hierarchy
    - UI: Font scale — Options ▾ menu in status bar → Font Size submenu (75%–200%)
      • Font size persists via ExtState across sessions
    - UI: Dock toggle — Options ▾ menu → Allow Docking (on/off, persists via ExtState)

  v260225.1800 (2026-02-25)
    - UI: Three-pane layout (upper-left editor, upper-right Detected Fields, lower Preview)
      • CollapsingHeader states (Tokens, Renamer, Take Presets, Note Presets) now persist
        across sessions via ExtState
      • Detected Fields values now use InputText(ReadOnly) — click and Cmd+A / Cmd+C to copy
      • "Copy Metadata" section removed (fields are directly selectable/copyable)
      • Horizontal splitter between upper and lower sections is draggable; ratio persists

  v260225.1700 (2026-02-25)
    - UI: Redesigned layout — left/right two-column split
      • Left panel (380px, scrollable): Take Name, Item Note, and all collapsible sections
      • Right panel (stretch): Detected Fields (top, resizable) + Preview table (bottom)
      • Top bar: Undo / Redo / Get Metadata / Apply / Cancel + status on a single fixed row
      • Template Tokens, Take Name Renamer, Take Presets, Note Presets are now collapsible
        (CollapsingHeader — hidden by default to reduce visual noise)
      • Copy Metadata moved to a collapsible section inside the Preview pane
      • Removed standalone Copy-text panes; copy buttons now compact inline

  v260225.1630 (2026-02-25)
    - UX: Apply now processes items in deferred batches (50 items per frame via reaper.defer())
      • No more spinning beach ball / UI freeze during large batch renames
      • REAPER Console window opens automatically on Apply to show live progress
      • Each batch prints [processed / total]; final summary printed on completion
      • Guard against double-trigger: re-pressing Apply while a batch is in progress is ignored

  v251210.0145 (2024-12-10)
    - Fixed: BWF Description parsing now handles newline-separated key=value pairs
      • Previously only supported semicolon separators (key=val; key=val)
      • Now supports both newline and semicolon separators (common in Sound Devices recorders)
      • Fixes $trk token expansion when using cached metadata
      • Pattern: desc:gmatch("([^\r\n;]+)") instead of desc:gmatch("[^;]+")
    - Fixed: Cache-to-fields reconstruction now properly handles all TRK# variants
      • Correctly parses sTRK#, dTRK#, and TRK# from description
      • Properly builds __trk_table with sparse indices (e.g., [3]="BOOM", [9]="LAVA")
      • Sets __trk_name from __trk_table[__chan_index] for preview display
    - Improved: Description field parsing now handles sPROJECT, sSCENE, sTAKE, sTAPE variants
      • Maps both uppercase variants (sPROJECT → PROJECT) and lowercase (sproject → project)
    - Debug: Added comprehensive debug logging (disabled by default, set DEBUG=true to enable)
      • Shows cache lookup details, TRK parsing results, interleave resolution
      • Helps troubleshoot metadata issues without modifying cache library
    - Technical: All changes in cache_to_fields() function - no cache format changes required

  v251209.1954 (2024-12-09)
    - Performance: Integrated shared metadata cache system (hsuanice_Metadata Cache.lua v251209.1954)
      • Dramatically faster metadata loading on repeated operations (cache hit ~100x faster)
      • Cache shared across all scripts using the Metadata Cache library
      • Cache stored as "Metadata.cache" in project directory (generic naming for multi-script use)
      • Automatic cache invalidation when items are modified (hash-based detection)
      • Caches 21 metadata fields: all BWF/iXML data (15 fields) + file info (6 fields)
      • Fast TRK# reconstruction from cached description field (no file I/O)
      • Cache flushed automatically on script exit (atexit handler)
    - Implementation details:
      • cache_to_fields() reconstructs full metadata from cache (TRK table, interleave, source info)
      • fields_to_cache() extracts cacheable fields from full metadata
      • First "Get Metadata" is normal speed (cache miss), subsequent calls are instant (cache hit)
    - No UI changes - all improvements are under the hood
    - Backward compatible with existing workflows

  v0.12.5 (2025-09-13)
    - Fixed: UMID rows were shown twice in Detected fields. Removed the
      manual UMID block and now render via the ordered field list only.
    - Order tweak: $umid and $umid_pt now appear directly under
      $originatorreference (before $timereference).
    - Copy panel: Keeps $umid / $umid_pt in the same order for easier
      cross-checking with Pro Tools.
    - Dependency note: Requires Metadata Read v0.3.0 (provides umid and
      umid_pt fields, with bwfmetaedit fallback when needed).
  v0.12.4 (2025-09-13)
    - Added: $umid (64-hex uppercase) and $umid_pt (PT style 26-6-16-12-4)
      tokens to the Template toolbar for caret insert.
    - Added: Detected fields panel now shows UMID and UMID (PT) directly
      under $originatorreference.
    - Added: "Copy metadata" output includes $umid and $umid_pt in the
      same order, for quick paste into notes or sheets.
    - Tokenization: normalize_tokens() recognizes $umid and $umid_pt so
      bare tokens are auto-wrapped as ${umid} / ${umid_pt}.
    - Dependency: expects Metadata Read v0.3.0 (provides fields.umid /
      fields.umid_pt; optional CLI fallback via bwfmetaedit when needed).

  v0.12.3 (2025-09-12)
    - Added: Display of UMID (BWF:UMID 64-hex uppercase) and UMID (PT style)
      in the Detected fields panel.
      * Each has its own row with a copyable token button ($umid, $umid_pt).
      * Values are taken from hsuanice_Metadata Read (v0.3.0).
    - Improved: Users can now directly insert $umid and $umid_pt tokens
      into rename templates for batch renaming or copy/export.
    - UI/Flow: UMID fields are shown immediately below the separator
      in the left pane, before the ordered generic field list.
    - Note: Tokens are empty if REAPER does not expose BWF:UMID on the
      current build; planned CLI fallback will fill them in later.
  v0.12.2 (2025-09-01)
    - UI: Show "Metadata Read vX.Y.Z" in the window title.
    - Init: Compute LIBVER before ImGui_Begin to avoid nil-concat errors; falls back to empty when library is missing.
    - Cleanup: Removed inline version text and leftover debug prints.
    - Behavior: Rename / Preview / Export unchanged from 0.12.1.
  v0.12.1 (2025-09-01)
    - More robust library loading:
      * Switch to dofile() with an absolute path to load 'hsuanice Metadata Read'
        (works reliably with spaces in paths).
      * Added version gate (requires >= 0.2.0) with clearer error messaging.
    - UI: Optionally shows the Metadata Read version at the top of the window for quick verification.
    - Cleanup: Removed temporary console prints / debug code.
    - Behavior: Rename/Preview/Export logic unchanged from 0.12.0.
  v0.12.0 (2025-09-01)
    - Integrate with "hsuanice Metadata Read" library (>= 0.2.0).
      * Removed internal iXML/TRK parsing & interleave name resolution in favor of Library.
      * $trk / $trkall / ${chnum} now use Library's resolve/guess logic.
      * Left-panel interleave diagnostics now come from Library (index/total/name/all).
      * Kept general field collection (track/length) here; all metadata read is via Library.
    - Updated export: "Replaced" column preserved. No UI changes otherwise.

  v0.11.24
  - New numeric tokens:
    • ${interleave} (alias ${interum}) → current interleave index (1..N) from I_CHANMODE.
    • ${chnum} (alias ${channelnum})  → recorder channel number:
        - Uses TRK# / iXML track list to map interleave position → channel number.
        - Falls back to ${interleave} when TRK info is absent.
  - No behavior changes to $trk / $trkN / $trkall.
  v0.11.23
    - Fix: Extended BWF/iXML Description parser to normalize `sXXXX=` keys 
      (introduced by Vordio AAF conversion) in addition to `dXXXX=`.
      • Examples: 
        `sSCENE=80-2`   → parsed as `scene`
        `sTAKE=04`      → parsed as `take`
        `sTAPE=25Y04M23`→ parsed as `tape`
        `sUBITS=00000000` → parsed as `ubits`
        `sFRAMERATE=24.000ND` → parsed as `framerate`
        `sSPEED=024.000-ND`  → parsed as `speed`
        `sTRK10=WANG1`  → parsed as `trk10` / `TRK10`
    - `$trk`, `$trkN`, `$trkall` now resolve correctly when Vordio’s 
      `sTRK#` fields are present.
    - Backward compatibility preserved: `dXXXX`, `TRK#`, and standard 
      iXML/BWF keys remain supported.

  v0.11.22
    - Skipped details: column order changed to
      “#, Current Take Name, Srcfile, Reason”.
    - Export/Copy (TSV/CSV): updated to use the same column order.
    - Fix: added missing `end` in the Result modal’s Skipped section (syntax error resolved).
    - No other changes: Skip-if-empty behavior, TRK/Interleave resolution, preview/apply flow remain unchanged.
  v0.11.21
    - Apply Result: Skipped details table now correctly populated (empty-token skips only).
      • Columns: #, Reason, Current Take Name, Srcfile.
      • Actions: Save skipped as .tsv / .csv, Copy skipped (TSV).
    - Fix: Moved skipped-row collection into the apply loop and removed the stray post-loop block,
      which previously caused “0” rows to appear despite nonzero Skipped count.
    - No changes to rename logic, interleave/TRK resolution, or the main result export.

  v0.11.20
    - Apply Result: added “Skipped details (empty-token skips)” section.
      • Columns: #, Reason, Current Take Name, Srcfile.
      • Actions: Save skipped as .tsv / .csv, Copy skipped (TSV).
      • Only lists items skipped by the “empty token” rule (i.e., when Skip option is ON).
    - Data plumbing: Apply now collects per-row skip info (reason + $srcfile) into the modal.
    - UI: keeps existing summary (Selected / Renamed / Notes / Skipped) and the original full-result export.
    - Stability: preserves 0.11.12 interleave/TRK resolution and caret/hover order for token insertion.
    - Note: non–empty-token causes (e.g., no-take) are counted in “Skipped” but not listed in this table by design.
  v0.11.19
    - Take-only option: “Skip rename if any token empty”.
      • When enabled, if any token in the Take Name template expands to empty, the item’s Take rename is skipped.
      • Notes are unaffected and still apply.
      • Setting persists via ExtState (key: skip_empty_tokens). Default OFF.
    - UI: Added the checkbox under the Take Name input. Reordered caret/hover capture
      so token buttons insert into the Take field correctly.
    - Apply: Updated logic to honor skip (new_name ~= "" AND not skip_reason).
      Skipped items are counted in the Apply Result (no list yet).
    - Parser fix: Corrected token extraction pattern to `%${...}` so empty-token detection works.
    - Stability fix: Made `expand_template` forward-declared/assigned to avoid upvalue nil errors.
    - TRK/Interleave behavior: unchanged from 0.11.12 (poly track name resolution preserved).
    - Result modal/export: unchanged in this build (counts only; no skipped list UI).
  v0.11.12
    - Fix: validate MediaItem before calling GetActiveTake to prevent intermittent
      “bad argument #1 to 'GetActiveTake' (MediaItem expected)” errors when clicking
      Item Note “Clear” or applying Take presets on poly files.
    - Stabilized preview/preset flows: recompute Interleave diagnostics safely even
      when an item handle is missing; no crashes, consistent $trk/$trkall.
    - No changes to naming behavior: still metadata-only, Wave Agent–style Interleave mapping.
  v0.11.11
    - Fix: crash in “Get Metadata (Preview)” caused by referencing a non-existent variable `f`.
    - Preview rows now recompute Interleave diagnostics per row using `e.fields` / `e.item` before expansion, preventing stale caches.

  v0.11.10
    - Left panel “Detected fields” now shows $trk / $trkall in Interleave order (1..N), strictly from metadata.
    - “Copy metadata” updated to use the same Interleave logic as the left panel/preview.
    - Before expanding any template (Take/Note), Interleave mapping/diagnostics are recomputed to avoid stale values.
    - Uses Wave Agent–style Interleave mapping; no filename-based inference for track names.

  v0.11.9
    - $trk resolves strictly from metadata by Interleave index:
      • Primary: iXML TRACK_LIST (CHANNEL_INDEX → NAME).
      • Fallback: TRK# (incl. normalized dTRK#) sorted numerically → mapped to Interleave 1..N.
    - $trkall concatenates names in Interleave order.
    - Interleave index for $trk derives from I_CHANMODE (Mono of N), clamped to the actual number of channels.
    - Removed all filename-based inference (.A#, chN, isoN, etc.).


  v0.11.8 - $trk/$trkall metadata-only:
    • $trk now resolves strictly from metadata track lists:
      - Primary: iXML TRACK_LIST (CHANNEL_INDEX → NAME).
      - Fallback: BWF:Description dTRK# pairs.
    • Removed filename-based patterns (.A#, chN, isoN, etc.) from $trk resolution.
    • Channel selection uses item I_CHANMODE (Mono of N). If not set, falls back to the first TRK in metadata.
    • BWF:Description normalization: dSCENE/dTAKE/dUBITS/... → SCENE/TAKE/UBITS; dTRK# → TRK#.

  v0.11.6 - Note clearing + preview clarity:
          • Added $clearnote token to explicitly clear Item Note (template expands to empty string).
          • Preview table: when Note template is applied and results in an empty string (e.g., $clearnote),
            "New Note" now shows (empty). If Note template is blank (skipped), it still shows (unchanged).
          • Token appears in the Template tokens row; no impact on Take Name or renamer behavior.
  v0.11.5 - Export Info row re-mapped:
          • New Take Name column shows the Take template (rename tokens).
          • New Take Note column shows the Note template (rename tokens).
          • Replace column keeps the consolidated rename rules (e.g., 2.0→2; 1.0→1).
          • No change to data rows or preview.
  v0.11.4 - UI cleanup: removed "Apply & Close" button.
          • Kept two-button layout: Apply / Cancel (right-aligned, consistent spacing).
          • Eliminates a non-functional action; no changes to apply/preview/export logic.
  v0.11.3 - Export: add per-row "Replaced" column showing hit rename rules (e.g., 2.0→2; 1.0→1).
             • Keeps top Info row (templates + all rules).
             • Preview table unchanged.
  v0.11.2 - Export format update:
          • Removed "Status" column from final TSV/CSV.
          • Added top "Info" row summarizing the run:
            Take=<template> | Note=<template> | Replace=<from→to; ...>.
  v0.11.1 - Export parity with preview:
          • Final TSV/CSV export now includes "Current Note" (order: #, Status, Current Take Name, New Name, Current Note, New Note).
          • Fix: corrected result export builder to write header and rows consistently (no more nil 'r' error).
  v0.11.0 - Preview table & export include Current Note:
          • Preview table adds a "Current Note" column and reorders columns to:
            #, Current Take Name, New Name, Current Note, New Note.
          • Copy/Export (TSV/CSV) now includes "Current Note" in the same order as the preview.
          • Internals: preview row builder now attaches current_note for each item; no changes to templates or renamer behavior.
  v0.10.3 - UI polish for Take Name renamer:
          • Use a custom header row so "Clear All" sits on the same line as "From" / "To".
          • "From" / "To" now left-aligned for clearer scanning; button remains in the right header cell.
          • Replaced auto TableHeadersRow and version-dependent calls with a safer approach (GetContentRegionAvail);
            no behavior changes to preview/apply/export.
  v0.10.2 - UI: Add "Clear All" button to Take Name renamer rules table header (top-right).
             • Clears all rename rules at once (does not affect Take Name/Item Note templates).
  v0.10.1 - UI: Move “+ Add rename rule” next to the Enable checkbox (same line) for quicker access.
  v0.10.0 - Replace Take Name filter with Take Name renamer:
          • Multi-rule, user-configurable rename system (From → To).
          • Enable/Disable checkbox; rules managed via [+] / [-] buttons; persisted via ExtState.
          • Applies after token expansion; affects Take Name only (Note unaffected).
          • Real-time preview update; applied in Apply and Summary (TSV/CSV export).
  v0.9.0 - (removed) Take Name filter (single disallow/replacement) → superseded by v0.10.0 renamer.
  v0.8.3 - Preset persistence: store P1–P5 in a single-line, escaped ExtState value.
          - Fixes issue where only P1 survived after REAPER restart (INI newline cutoff).
          - Supports multi-line Note presets; no data loss across sessions.
  v0.8.2 - Consistency: unified all internal "tab" format identifiers to "tsv"; default right_copy_fmt = "tsv".
           - UI: "Copy preview table" uses TSV/CSV buttons (clipboard copy via ImGui_SetClipboardText).
           - Preview: right pane preview text reflects current cached rows and respects preview_limit.
           - Save dialog: silent write for .tsv/.csv; cancel returns nil from choose_save_path() (no write, no popup).
           - Stability: verified matching Begin/End for Child and Table scopes in view/copy panes.
  v0.8.1 - UI: Unified “Copy preview table” buttons to TSV + CSV (renamed Tab → TSV); logic unchanged, TSV uses tab delimiter.
           - Result dialog: Save as .tsv / .csv now writes silently without REAPER popup.
             • If user cancels the file dialog → no file is written, no message shown.
             • If save succeeds/fails → no blocking popup; optional status_msg can be used instead.
  v0.7.5
    - Fix: Token normalization now processes longer tokens first, avoiding prefix collisions
          (e.g., $trkall, $timereference, $originatorreference).
    - QA: Verified adjacent-letter cases such as "$sceneT$take" expand as expected.
    - Docs: Clarify that Note template expansion preserves whitespace/newlines;
            Take Name continues to collapse consecutive whitespace.
  v0.7.4 – Fix: disable filename-style sanitization when expanding Note templates; Take Name expansion unchanged.
  v0.7.3 - Token normalization & adjacency fix
    - Automatically wraps bare $tokens as ${token} during expansion.
    - Adjacent letters/digits are now safe (e.g., "$sceneT$take" works as "${scene}T${take}").
    - Supports $trkN, ${counter:N}, ${srcbaseprefix:N}, ${srcbasesuffix:N}.
    - Backward compatible with existing templates.
  v0.7.2 - Fix: Show "(unchanged)" in Note preview when template is blank; fix Default (Note) to restore $curnote when ExtState is empty.
  v0.7.1 - Increase preset button label preview from 24 to 64 characters (Take & Note).
  v0.7.0 - Add $curnote token
  v0.6.2 - Change Clear/Default/Save to Clear/Save/Default, each input section has its own buttons
  v0.6.1 - Preset now can be seen directly, no need to hover
  v0.6.0 - Add 5 presets for Take/Note templates (save & click to load). Fix $curtake parsing bug. Show $curtake in Detected fields.
  v0.5.0 - Add $curtake token
  v0.4.0 - Add $srcbaseprefix:N and $srcbasesuffix:N tokens to extract the first/last N characters of the filename (without extension).
  v0.3.0 - Add Selected/Scanned/Cached status view
  v0.2.0 - Add ESC close function
  v0.1.0 - Beta release
--]]

-- ===== Integrate with hsuanice Metadata Read (>= 0.2.0) =====
local META = dofile(
  reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua"
)
assert(META and (META.VERSION or "0") >= "0.2.0",
       "Please update 'hsuanice Metadata Read' to >= 0.2.0")

-- ===== Integrate with hsuanice Metadata Cache (shared with Item List Editor) =====
local CACHE = dofile(
  reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Cache.lua"
)
assert(CACHE and CACHE.VERSION, "Failed to load 'hsuanice Metadata Cache'")

-- Debug flag for troubleshooting
local DEBUG = false  -- Set to true to enable debug output for troubleshooting

-- Initialize cache on startup
CACHE.init()
-- Enable debug logging to see cache hits/misses (set to false in production)
CACHE.set_debug(false)



-- ===== Guard ReaImGui =====
if not reaper or not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("This script requires ReaImGui (install via ReaPack).", "Missing dependency", 0)
  return
end

-- ===== ImGui basics =====
local ctx = reaper.ImGui_CreateContext('Rename Active Take from Metadata')
local LIBVER = (META and META.VERSION) and (' | Metadata Read v'..tostring(META.VERSION)) or ''
local FLT_MIN = reaper.ImGui_NumericLimits_Float()
local WIN_W, WIN_H = 1020, 720
local LEFT_PANEL_W    = 380   -- fixed width of the left editor panel
local function TF(name) local fn = reaper[name]; return (type(fn)=="function") and fn() or 0 end

-- ESC key enum (works across ReaImGui versions)
local KEY_ESC = TF('ImGui_Key_Escape')

-- ===== ExtState (defaults) =====
local EXT_NS = "RENAME_TAKE_FROM_METADATA_V1"
local DEFAULT_TAKE_TEMPLATE_INIT = "$srcfile"
local DEFAULT_NOTE_TEMPLATE_INIT = "$curnote"
local function load_defaults()
  local t = reaper.GetExtState(EXT_NS, "default_take_template")
  local n = reaper.GetExtState(EXT_NS, "default_note_template")
  if not t or t == "" then t = DEFAULT_TAKE_TEMPLATE_INIT end
  if not n or n == "" then n = DEFAULT_NOTE_TEMPLATE_INIT end
  return t, n
end
local function save_defaults(t, n)
  reaper.SetExtState(EXT_NS, "default_take_template", tostring(t or ""), true)
  reaper.SetExtState(EXT_NS, "default_note_template", tostring(n or ""), true)
end

-- ===== Font scale and docking =====
local current_font_size      = 13
local font_pushed_this_frame = false
local FONT_SCALE   = math.max(0.5, math.min(3.0, tonumber(reaper.GetExtState(EXT_NS, "font_scale")) or 1.0))
local ALLOW_DOCKING = (reaper.GetExtState(EXT_NS, "allow_docking") == "1")
local function set_font_size(size)
  current_font_size = math.max(8, math.min(48, math.floor(size or 13)))
end
set_font_size(math.floor(13 * FONT_SCALE))

-- ===== Safe string pack for ExtState (single-line storage) =====
local SEP = string.char(31) -- ASCII Unit Separator; 不會出現在一般文字中

local function esc(s)
  s = tostring(s or "")
  -- 歸一化換行 → \n
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  -- 轉義：反斜線、分隔符、以及換行
  s = s:gsub("\\", "\\\\")
       :gsub(SEP, "\\x1F")
       :gsub("\n", "\\n")
  return s
end

local function unesc(s)
  s = tostring(s or "")
  s = s:gsub("\\n", "\n")
       :gsub("\\x1F", SEP)
       :gsub("\\\\", "\\")
  return s
end

local function split_by_sep(s)
  local t = {}
  local from = 1
  while true do
    local i, j = s:find(SEP, from, true)
    if not i then
      t[#t+1] = s:sub(from)
      break
    end
    t[#t+1] = s:sub(from, i-1)
    from = j + 1
  end
  return t
end

local function join_by_sep(list)
  return table.concat(list, SEP)
end


-- ===== Template Presets (5 slots each for Take/Note) =====
local TAKE_PRESETS_KEY = "take_template_presets_v1"  -- newline-separated 5 lines
local NOTE_PRESETS_KEY = "note_template_presets_v1"  -- newline-separated 5 lines
local PRESET_SLOTS = 5
local TAKE_HISTORY_KEY = "take_template_history_v1"
local TAKE_HISTORY_LIMIT = 10

local function load_presets(key)
  local s = reaper.GetExtState(EXT_NS, key)
  local t = {}
  if s and s ~= "" then
    local parts = split_by_sep(s)
    for i = 1, math.min(#parts, PRESET_SLOTS) do
      t[i] = unesc(parts[i])
    end
  end
  for i = #t + 1, PRESET_SLOTS do t[i] = "" end
  return t
end

local function save_presets(key, list)
  local packed = {}
  for i = 1, PRESET_SLOTS do
    packed[i] = esc(list[i] or "")
  end
  reaper.SetExtState(EXT_NS, key, join_by_sep(packed), true)
end

local function load_recent_list(key, limit)
  local s = reaper.GetExtState(EXT_NS, key)
  local t = {}
  if s and s ~= "" then
    local parts = split_by_sep(s)
    for i = 1, math.min(#parts, limit) do
      local v = unesc(parts[i])
      if v ~= "" then t[#t + 1] = v end
    end
  end
  return t
end

local function save_recent_list(key, limit, list)
  local packed = {}
  for i = 1, math.min(#list, limit) do
    packed[i] = esc(list[i] or "")
  end
  reaper.SetExtState(EXT_NS, key, join_by_sep(packed), true)
end

local function push_recent_list(list, key, limit, value)
  local trimmed = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if trimmed == "" then return list end
  local next_list = { trimmed }
  for _, existing in ipairs(list or {}) do
    if existing ~= trimmed and #next_list < limit then
      next_list[#next_list + 1] = existing
    end
  end
  save_recent_list(key, limit, next_list)
  return next_list
end

-- ===== Skip-If-Empty (Take-only) =====
local function load_skip_empty_tokens()
  return reaper.GetExtState(EXT_NS, "skip_empty_tokens") == "1"
end
local function save_skip_empty_tokens(v)
  reaper.SetExtState(EXT_NS, "skip_empty_tokens", v and "1" or "0", true)
end
local SKIP_EMPTY_TOKENS = load_skip_empty_tokens()


-- ===== Take Name post-filter (user-configurable) =====
local function load_take_filter()
  local en   = (reaper.GetExtState(EXT_NS, "take_filter_enable") == "1")
  local ch   = reaper.GetExtState(EXT_NS, "take_filter_chars"); if ch == "" then ch = nil end
  local repl = reaper.GetExtState(EXT_NS, "take_filter_repl");  if repl == "" then repl = nil end
  local col  = (reaper.GetExtState(EXT_NS, "take_filter_collapse") == "1")
  return {
    enable   = en,
    chars    = ch or ".",   -- 預設把 '.' 視為不允許
    repl     = repl or "_", -- 預設用底線取代
    collapse = col,
  }
end
local function save_take_filter(F)
  reaper.SetExtState(EXT_NS, "take_filter_enable",   F.enable and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "take_filter_chars",    tostring(F.chars or ""), true)
  reaper.SetExtState(EXT_NS, "take_filter_repl",     tostring(F.repl  or "_"), true)
  reaper.SetExtState(EXT_NS, "take_filter_collapse", F.collapse and "1" or "0", true)
end
local TAKE_FILTER = load_take_filter()

-- 把使用者輸入的「字元清單」組成 Lua 字元類別，處理必要跳脫
local function _build_charclass(literals)
  literals = tostring(literals or "")
  -- 在 [] 內要跳脫的字元：^ - ]
  literals = literals:gsub("([%^%-%]])", "%%%1")
  return "[" .. literals .. "]"
end

-- 把 literal 字串轉成 Lua pattern-safe（用於 collapse 重複）
local function _escape_lua_pat(s) return tostring(s or ""):gsub("(%W)", "%%%1") end

local function apply_take_filter(name)
  local out = tostring(name or "")
  if TAKE_FILTER.enable and TAKE_FILTER.chars and TAKE_FILTER.chars ~= "" then
    local cls = _build_charclass(TAKE_FILTER.chars)
    local repl = TAKE_FILTER.repl or "_"
    -- 1) 不允許的字元 → 取代字元（留空代表刪除）
    out = out:gsub(cls, repl)
    -- 2) 折疊連續取代字元
    if TAKE_FILTER.collapse and repl ~= "" then
      local rp = _escape_lua_pat(repl)
      out = out:gsub(rp.."+", repl)
    end
  end
  return out
end

-- ===== Take Name renamer (user-configurable, after filter) =====
local R_ITEM_SEP  = string.char(31)
local R_FIELD_SEP = string.char(30)

local function _escape_lua_pat_safe(s) return tostring(s or ""):gsub("(%W)","%%%1") end

local function _repeat_pat_atom(atom, n)
  local count = tonumber(n) or 0
  if count <= 0 then return "" end
  local t = {}
  for i = 1, count do t[i] = atom end
  return table.concat(t)
end

local function _regex_like_to_lua_pat(s)
  local out = tostring(s or "")
  -- Convenience translation for common regex-style shortcuts.
  out = out:gsub("\\d", "%%d")
           :gsub("\\s", "%%s")
           :gsub("\\w", "%%w")

  -- Support simple fixed quantifiers like %d{3} or [0-9]{3}.
  out = out:gsub("(%b[]){(%d+)}", function(atom, n)
    return _repeat_pat_atom(atom, n)
  end)
  out = out:gsub("(%%[%a]){(%d+)}", function(atom, n)
    return _repeat_pat_atom(atom, n)
  end)

  return out
end

local function _resolve_rule_pat(from, use_regex)
  local raw = tostring(from or "")
  if use_regex then
    local body = raw
    if body:sub(1, 3) == "re:" then
      body = body:sub(4)
    end
    if body == "" then return "", true end
    return _regex_like_to_lua_pat(body), true
  end
  local lead_trim = raw:gsub("^%s+", "")
  if lead_trim:sub(1, 3) == "re:" then
    local body = lead_trim:sub(4):gsub("^%s+", "")
    if body == "" then return "", true end
    return _regex_like_to_lua_pat(body), true
  end
  return _escape_lua_pat_safe(raw), false
end

local function pack_rules(rules)
  -- rules: { {from="2.0", to="2"}, {from="1.0", to="1"}, ... }
  local packed = {}
  for i=1, #(rules or {}) do
    local p = rules[i]
    local from = esc(p.from or "")
    local to   = esc(p.to   or "")
    packed[#packed+1] = from .. R_FIELD_SEP .. to
  end
  return table.concat(packed, R_ITEM_SEP)
end

local function unpack_rules(s)
  local out = {}
  if s and s ~= "" then
    local items = split_by_sep(s:gsub(R_FIELD_SEP, R_FIELD_SEP)) -- reuse splitter
    -- 手動 split item → fields（from/to）
    local start = 1
    local function split_once(str, sep)
      local i = str:find(sep, 1, true)
      if not i then return str, "" end
      return str:sub(1, i-1), str:sub(i+1)
    end
    local idx = 1
    for chunk in s:gmatch("([^" .. R_ITEM_SEP .. "]*)"..R_ITEM_SEP.."*") do
      if chunk == "" then
        if s:sub(#s) == R_ITEM_SEP then break end
      end
      local a, b = split_once(chunk, R_FIELD_SEP)
      out[#out+1] = { from = unesc(a or ""), to = unesc(b or "") }
      idx = idx + 1
      if idx > 999 then break end
    end
  end
  return out
end

local function load_take_renamer()
  local en = (reaper.GetExtState(EXT_NS, "take_ren_enable") == "1")
  local rex = (reaper.GetExtState(EXT_NS, "take_ren_regex") == "1")
  local raw = reaper.GetExtState(EXT_NS, "take_ren_rules")
  local rules = unpack_rules(raw)
  return { enable = en, regex = rex, rules = rules }
end

local function save_take_renamer(R)
  reaper.SetExtState(EXT_NS, "take_ren_enable", R.enable and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "take_ren_regex",  R.regex and "1" or "0", true)
  reaper.SetExtState(EXT_NS, "take_ren_rules",  pack_rules(R.rules or {}), true)
end

local TAKE_RENAMER = load_take_renamer()

local function apply_take_renamer(name)
  local out = tostring(name or "")
  local hits = {}
  if TAKE_RENAMER.enable and TAKE_RENAMER.rules then
    for _, pair in ipairs(TAKE_RENAMER.rules) do
      local from = pair.from or ""
      local to   = pair.to   or ""
      if from ~= "" then
        local pat = _resolve_rule_pat(from, TAKE_RENAMER.regex)
        local replaced = 0
        local ok, new_out, rep_count = pcall(string.gsub, out, pat, to)
        if ok then
          out, replaced = new_out, (rep_count or 0)
        else
          -- Fallback to literal mode if an invalid pattern was entered.
          local lit = _escape_lua_pat_safe(from)
          out, replaced = out:gsub(lit, to)
        end
        if replaced and replaced > 0 then
          hits[#hits+1] = from .. "→" .. to
        end
      end
    end
  end
  return out, hits
end






-- Persist split ratio
local function load_split_ratio()
  local s = tonumber(reaper.GetExtState(EXT_NS, "split_ratio") or "")
  if s and s > 0.1 and s < 0.9 then return s end
  return 0.62
end
local function save_split_ratio(ratio)
  reaper.SetExtState(EXT_NS, "split_ratio", string.format("%.4f", ratio or 0.62), true)
end

-- ===== Safe BeginChild (cross-version) =====
-- 回傳兩個值：begun:boolean, visible:boolean
local function BeginChildSafe(id, w, h, border, flags)
  border = not not border
  flags  = flags or 0

  -- 最常見簽名：(ctx, id, w, h, border:boolean, flags:number)
  local ok, ret = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, border, flags)
  if ok then return true, ret end

  -- 舊綁定簽名 A：(ctx, id, w, h, flags:number)
  ok, ret = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, flags)
  if ok then return true, ret end

  -- 舊綁定簽名 B：(ctx, id, w, h)
  ok, ret = pcall(reaper.ImGui_BeginChild, ctx, id, w, h)
  if ok then return true, ret end

  -- 全部失敗 → 沒有開始 child（千萬別 EndChild）
  return false, false
end



-- ===== UTF-8 helpers =====
local function trim(s) return (tostring(s or "")):gsub("^%s+",""):gsub("%s+$","") end
local NOTE_META_BEGIN = "[hsuanice_source_rename_meta]"
local NOTE_META_END = "[/hsuanice_source_rename_meta]"

local function split_note_and_meta(note)
  note = tostring(note or "")
  local start_pos = note:find(NOTE_META_BEGIN, 1, true)
  if not start_pos then return note, nil end

  local end_pos = note:find(NOTE_META_END, start_pos + #NOTE_META_BEGIN, true)
  if not end_pos then
    local visible = note:sub(1, start_pos - 1):gsub("[%s\r\n]+$", "")
    local meta_block = note:sub(start_pos + #NOTE_META_BEGIN)
    return visible, meta_block
  end

  local visible = note:sub(1, start_pos - 1):gsub("[%s\r\n]+$", "")
  local meta_block = note:sub(start_pos + #NOTE_META_BEGIN, end_pos - 1)
  return visible, meta_block
end

local function parse_note_meta(note)
  local visible, meta_block = split_note_and_meta(note)
  local meta = { origsrcfile = "", history = {} }
  if not meta_block or meta_block == "" then
    return visible, meta
  end

  local normalized = tostring(meta_block):gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (normalized .. "\n"):gmatch("(.-)\n") do
    if line:match("^origsrcfile=") then
      meta.origsrcfile = line:sub(#"origsrcfile=" + 1)
    elseif line:match("^history=") then
      local entry = line:sub(#"history=" + 1)
      local new_name = entry:match("^.- | .- %-%> (.-)$")
      meta.history[#meta.history + 1] = new_name or entry
    end
  end
  return visible, meta
end

local function build_note_with_meta(visible, meta)
  visible = tostring(visible or "")
  meta = meta or {}
  local lines = {}
  if meta.origsrcfile and meta.origsrcfile ~= "" then
    lines[#lines + 1] = "origsrcfile=" .. tostring(meta.origsrcfile)
  end
  for _, entry in ipairs(meta.history or {}) do
    if tostring(entry or "") ~= "" then
      lines[#lines + 1] = "history=" .. tostring(entry)
    end
  end
  if #lines == 0 then
    return visible
  end

  local out = visible
  if out ~= "" then out = out:gsub("[%s\r\n]+$", "") end
  if out ~= "" then out = out .. "\n" end
  return out .. NOTE_META_BEGIN .. "\n" .. table.concat(lines, "\n") .. "\n" .. NOTE_META_END
end

local function append_rename_note_history(note, old_name, new_name)
  local visible, meta = parse_note_meta(note)
  local old_trimmed = trim(old_name)
  local new_trimmed = trim(new_name)

  if new_trimmed == "" or old_trimmed == "" or new_trimmed == old_trimmed then
    return build_note_with_meta(visible, meta)
  end
  if old_trimmed ~= "" and (not meta.origsrcfile or meta.origsrcfile == "") then
    meta.origsrcfile = old_trimmed
  end

  if meta.origsrcfile ~= "" and new_trimmed == meta.origsrcfile then
    meta.origsrcfile = ""
    meta.history = {}
    return build_note_with_meta(visible, meta)
  end

  if new_trimmed ~= "" then
    meta.history[#meta.history + 1] = new_trimmed
  end
  return build_note_with_meta(visible, meta)
end

local function format_history_preview(note)
  local _, meta = parse_note_meta(note)
  local lines = {}
  if meta.origsrcfile and meta.origsrcfile ~= "" then
    lines[#lines + 1] = "1. Original: " .. tostring(meta.origsrcfile)
  end
  for i, entry in ipairs(meta.history or {}) do
    if tostring(entry or "") ~= "" then
      lines[#lines + 1] = string.format("%d. Rename %d: %s", #lines + 1, i, tostring(entry))
    end
  end
  if #lines == 0 then
    return "(no history)"
  end
  return table.concat(lines, "\n")
end

local function utf8_spans(s)
  s = tostring(s or ""); local spans, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i); if not c then break end
    local len = (c<0x80) and 1 or ((c<=0xDF) and 2 or ((c<=0xEF) and 3 or 4))
    local j = math.min(i+len-1, n); spans[#spans+1] = {i,j}; i = j+1
  end
  return spans
end
local function utf8_len(s) return #utf8_spans(s) end
local function utf8_sub(s, ci1, ci2)
  s = tostring(s or ""); local spans = utf8_spans(s); local n = #spans
  if n == 0 then return "" end
  ci1 = math.max(1, math.min(n, ci1 or 1))
  ci2 = math.max(1, math.min(n, ci2 or n))
  if ci2 < ci1 then return "" end
  local b = spans[ci1][1]; local e = spans[ci2][2]
  return s:sub(b, e)
end

-- ===== helpers: UTF-8 ellipsis for preset preview =====
local function ellipsize_utf8(s, max_chars)
  s = tostring(s or "")
  local n = utf8_len(s)
  if n <= max_chars then return s end
  return utf8_sub(s, 1, math.max(1, max_chars - 1)) .. "…"
end

local function utf8_width_first_k(ctx, s, k)
  s = tostring(s or ""); local spans = utf8_spans(s)
  if k <= 0 then return 0 end
  k = math.min(k, #spans)
  local prefix = s:sub(1, spans[k][2])
  local w = select(1, reaper.ImGui_CalcTextSize(ctx, prefix))
  return w or 0
end
local function utf8_index_from_x(ctx, s, relx)
  local n = utf8_len(s); if n == 0 or relx <= 0 then return 0 end
  local best_i, best_d = 0, 1e9
  for i = 0, n do
    local w = utf8_width_first_k(ctx, s, i)
    local d = math.abs(w - relx)
    if d < best_d then best_d, best_i = d, i end
  end
  return best_i
end
local function insert_at_char_index(s, token, ci)
  s = tostring(s or ""); token = tostring(token or ""); local n = utf8_len(s)
  ci = math.max(0, math.min(n, tonumber(ci or n) or n))
  if ci == 0 then return token..s, ci + utf8_len(token) end
  if ci == n then return s..token, ci + utf8_len(token) end
  local left = utf8_sub(s, 1, ci); local right = utf8_sub(s, ci+1, n)
  return left..token..right, ci + utf8_len(token)
end
local function utf8_char_at(s, ci)
  if not s or s=="" then return "" end
  local n = utf8_len(s); if ci < 1 or ci > n then return "" end
  return utf8_sub(s, 1, 1)
end
local function byte_to_char_index(s, bpos)
  local spans = utf8_spans(s)
  for i, sp in ipairs(spans) do if bpos <= sp[2] then return i end end
  return #spans
end

-- 根據可用寬度（像素）截斷並加省略號
local function ellipsize_to_width(ctx, s, max_w)
  s = tostring(s or "")
  if max_w <= 0 then return "…" end
  local w = select(1, reaper.ImGui_CalcTextSize(ctx, s)) or 0
  if w <= max_w then return s end
  -- 二分搜尋最長可顯示的字元數
  local spans = utf8_spans(s)
  local lo, hi, best = 0, #spans, 0
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    local pw = utf8_width_first_k(ctx, s, mid)
    if pw <= (max_w - 8) then  -- 留一點邊距
      best = mid; lo = mid + 1
    else
      hi = mid - 1
    end
  end
  if best <= 0 then return "…" end
  return utf8_sub(s, 1, best) .. "…"
end




-- ===== Token spans (for snapping) =====
local function token_spans_chars(s)
  s = tostring(s or "")
  local tokens = {}
  -- ${...}
  local i = 1
  while true do
    local bs, be = s:find("%$%b{}", i); if not bs then break end
    tokens[#tokens+1] = { byte_to_char_index(s, bs), byte_to_char_index(s, be) }
    i = be + 1
  end
  -- $word
  i = 1
  while true do
    local bs, be = s:find("%$[%a%d:]+", i); if not bs then break end
    if s:sub(bs+1, bs+1) ~= "{" then
      tokens[#tokens+1] = { byte_to_char_index(s, bs), byte_to_char_index(s, be) }
    end
    i = be + 1
  end
  table.sort(tokens, function(a,b) return a[1] < b[1] end)
  return tokens
end
local function snap_caret_out_of_token(text, ci)
  local tks = token_spans_chars(text); if #tks==0 then return ci end
  for _, t in ipairs(tks) do
    local cs, ce = t[1], t[2]
    if ci > (cs-1) and ci < ce then return ce end
  end
  return ci
end

-- Avoid splitting words when inserting tokens
local function is_word_char(ch)
  return ch ~= "" and (ch:match("[%w_]") ~= nil)
end
local function snap_caret_out_of_word(text, ci, prefer_side)
  prefer_side = prefer_side or "right"
  local left  = utf8_char_at(text, ci)
  local right = utf8_char_at(text, ci + 1)
  if is_word_char(left) and is_word_char(right) then
    if prefer_side == "left" then
      local j = ci
      while j > 0 and is_word_char(utf8_char_at(text, j)) do j = j - 1 end
      return j
    else
      local n = utf8_len(text)
      local j = ci
      while j < n and is_word_char(utf8_char_at(text, j + 1)) do j = j + 1 end
      return j
    end
  end
  return ci
end

-- ===== Safe insert (caret-only; token+word snapping) =====
local function safe_insert_token(str, caret_ci, token)
  caret_ci = tonumber(caret_ci or utf8_len(str)) or utf8_len(str)
  caret_ci = snap_caret_out_of_token(str, caret_ci)
  caret_ci = snap_caret_out_of_word(str, caret_ci, "right")
  local s, new_idx = insert_at_char_index(str, token, caret_ci)
  return s, new_idx
end

-- ===== REAPER helpers =====
local function get_active_take(item)
  if not (item and reaper.ValidatePtr2 and reaper.ValidatePtr2(0, item, 'MediaItem*')) then
    return nil
  end
  local tk = reaper.GetActiveTake(item)
  if tk and reaper.ValidatePtr2(0, tk, 'MediaItem_Take*') then
    return tk
  end
  return nil
end

local function take_source(take) if not take then return nil end local s=reaper.GetMediaItemTake_Source(take); if s and reaper.ValidatePtr2(0,s,'PCM_source*') then return s end end
local function source_filename(src) if not src then return nil end local p=reaper.GetMediaSourceFileName(src,''); return (p~='' and p) or nil end
local function get_take_source_path(take)
  local src = take and reaper.GetMediaItemTake_Source(take)
  if not src then return nil end
  local p = reaper.GetMediaSourceFileName(src, '')
  return (p and p ~= '') and p or nil
end
local function replace_take_source_from_file(take, path)
  if not take or not path or path == '' then return false, 'no take/path' end
  if reaper.PCM_Source_CreateFromFile then
    local new_src = reaper.PCM_Source_CreateFromFile(path)
    if new_src then
      if reaper.SetMediaItemTake_Source then
        reaper.SetMediaItemTake_Source(take, new_src)
      elseif reaper.BR_SetTakeSourceFromFile then
        reaper.BR_SetTakeSourceFromFile(take, path, false)
      else
        return false, 'no source replacement API'
      end
      if reaper.PCM_Source_BuildPeaks then
        reaper.PCM_Source_BuildPeaks(new_src, 0)
      end
      return true
    end
  end
  if reaper.BR_SetTakeSourceFromFile then
    reaper.BR_SetTakeSourceFromFile(take, path, false)
    return true
  end
  return false, 'source replacement unavailable'
end
local function basename(p) return p and (p:match("([^/\\]+)$") or p) or "" end
local function basename_no_ext(p) local n=basename(p); return (n:gsub("%.%w+$","")) end
local function get_ext(p) local n=basename(p); return (n:match("%.([^.]+)$") or "") end
local function dirname(p) return p and (p:match("^(.*)[/\\][^/\\]+$") or "") or "" end
local function get_item_track_name(item) local tr=reaper.GetMediaItem_Track(item); if not tr then return "" end local _,name=reaper.GetTrackName(tr,""); return name or "" end
local function get_item_length_sec(item) return reaper.GetMediaItemInfo_Value(item,"D_LENGTH") or 0.0 end
local function seconds_to_m_ss_mmm(sec) local s=math.max(0,tonumber(sec) or 0) local m=math.floor(s/60) local r=s-m*60 return string.format("%d:%06.3f", m, r) end

-- Return the number of channels in the true source (poly N).
local function get_source_num_channels(item, fields)
  -- 1) Prefer the media source (most reliable)
  local take = reaper.GetActiveTake(item)
  if take then
    local src = reaper.GetMediaItemTake_Source(take)
    if src then
      local nch = reaper.GetMediaSourceNumChannels(src)
      if type(nch) == "number" and nch > 0 then
        return nch
      end
    end
  end
  -- 2) Fallback: metadata $channels
  local n = tonumber(fields and fields.channels)
  if n and n > 0 then
    return n
  end
  return 1
end

-- Interleave-only: derive Interleave index N from I_CHANMODE (Mono of N),
-- then clamp to 1..num_channels. This returns Interleave index (1..N),
-- not the recorder's channel label (3/4/5/...).
local function guess_channel_index(item, fields)
  local take = reaper.GetActiveTake(item)
  if not take then
    return nil
  end

  local cm = reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0
  -- Mono of N: cm = 2 + N  →  N = cm - 2
  if cm >= 3 and cm <= 66 then
    local n = math.floor(cm - 2)
    local nch = get_source_num_channels(item, fields)
    if n < 1 then n = 1 end
    if n > nch then n = nch end
    return n
  end

  return nil -- No Mono-of-N set; $trk branch will decide fallback behavior.
end


-- metadata keys
local BWF_KEYS = {
  "BWF:Description","BWF:OriginationDate","BWF:OriginationTime",
  "BWF:Originator","BWF:OriginatorReference","BWF:TimeReference",
}
local IXML_KEYS = {
  "IXML:PROJECT","IXML:SCENE","IXML:TAKE","IXML:TAPE","IXML:TRK1",
  "IXML:UBITS","IXML:FRAMERATE","IXML:SPEED",
}
local GENERIC_KEYS = { "Metadata:Date","Metadata:Description","Generic:StartOffset" }
local function get_meta(src, key)
  if not src or not reaper.GetMediaFileMetadata then return nil end
  local ok, val = reaper.GetMediaFileMetadata(src, key)
  if ok == 1 and val ~= "" then return val end
  return nil
end
-- Parse "key=value" pairs from BWF:Description and normalize:
--   dSCENE/dTAKE/... → SCENE/TAKE/...
--   dTRK#/TRK#       → TRK#/trk#
local function parse_description_pairs(desc_text, out_tbl)
  for line in (tostring(desc_text or "") .. "\n"):gmatch("(.-)\n") do
    local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if k and v and k ~= "" then
      out_tbl[k] = v
      out_tbl[string.lower(k)] = v

      -- Map dXXXX → XXXX (upper & lower)
      local up = k:upper()
      local base = up:match("^[SD]([A-Z0-9_]+)$")
      if base and base ~= "" then
        out_tbl[base] = v
        out_tbl[string.lower(base)] = v
      end

      -- Map dTRK#/TRK#/sTRK# → TRK#/trk#
      local n = up:match("^[SD]?TRK(%d+)$")
      if n then
        out_tbl["TRK"..n] = v
        out_tbl["trk"..n] = v
      end
    end
  end
end

local function fill_ixml_tracklist(src, t)
  local ok, count = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK_COUNT")
  if ok == 1 then
    local n = tonumber(count) or 0
    for i=1,n do
      local suffix = (i>1) and (":"..i) or ""
      local _, ch_idx = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX"..suffix)
      local _, name   = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:NAME"..suffix)
      local idx = tonumber(ch_idx or "")
      if idx and idx >= 1 then
        if name and name ~= "" then
          t["trk"..idx] = name; t["TRK"..idx] = name
        elseif not t["trk"..idx] and t["TRK"..idx] then
          t["trk"..idx] = t["TRK"..idx]
        end
      end
    end
  end
end
local function detect_samplerate_channels(src)
  if not src then return nil,nil end
  local srate = reaper.GetMediaSourceSampleRate(src) or 0
  local ch = reaper.GetMediaSourceNumChannels(src) or 0
  return srate, ch
end

local function collect_metadata_for_item(item)
  local t = {}
  local take = get_active_take(item)
  local src  = take and take_source(take)
  local fn   = src and source_filename(src)
  -- true source tokens
  if fn and fn ~= "" then
    t.srcpath = fn
    t.srcfile = basename(fn)
    t.srcbase = basename_no_ext(fn)
    t.srcext  = get_ext(fn)
    t.srcdir  = dirname(fn)
  end
  -- back-compat-ish
  t.filename   = fn and basename_no_ext(fn) or ""
  t.filepath   = fn or ""
  -- common fields
  local sr, ch = detect_samplerate_channels(src)
  if sr and sr>0 then t.samplerate = tostring(math.floor(sr+0.5)) end
  if ch and ch>0 then t.channels   = tostring(ch) end
  t.track      = get_item_track_name(item)
  t.length     = seconds_to_m_ss_mmm(get_item_length_sec(item))
  -- can read bwf/ixml?
  local srctype = src and reaper.GetMediaSourceType(src, "") or ""
  local upper = srctype:upper()
  local can_meta = (upper:find("WAVE") or upper:find("AIFF") or upper:find("WAVE64")) and true or false
  if can_meta then
    for _, key in ipairs(GENERIC_KEYS) do
      local v = get_meta(src, key)
      if v ~= nil then t[string.lower(key:gsub("Metadata:",""):gsub("Generic:",""))] = v end
    end
    for _, key in ipairs(BWF_KEYS) do
      local v = get_meta(src, key)
      if v ~= nil then
        local short = key:gsub("BWF:","")
        t[short] = v; t[string.lower(short)] = v
        if short == "Description" then parse_description_pairs(v, t) end
      end
    end
    fill_ixml_tracklist(src, t)
    for _, key in ipairs(IXML_KEYS) do
      local v = get_meta(src, key)
      if v ~= nil then
        local short = key:gsub("IXML:","")
        t[short] = v; t[string.lower(short)] = v
      end
    end
  end
  local date_val = t.OriginationDate or t.originationdate or t.date
  local time_val = t.OriginationTime or t.originationtime or t.time
  local date_str = date_val and tostring(date_val) or ""
  if date_str ~= "" then
    t.year = date_str:match("(%d%d%d%d)") or ""; t.date = date_str
    t.originationdate = t.originationdate or t.OriginationDate or date_str
  end
  local time_str = time_val and tostring(time_val) or ""
  if time_str ~= "" then
    t.time = time_str; t.originationtime = t.originationtime or t.OriginationTime or time_str
  end
  if t.startoffset == nil and t.startoffsset ~= nil then t.startoffset = t.startoffsset end
  local alias = {
    "Description","OriginationDate","OriginationTime","Originator","OriginatorReference","TimeReference",
    "PROJECT","SCENE","TAKE","TAPE","TRK1","UBITS","FRAMERATE","SPEED",
    "filename","filepath","samplerate","channels","track","length","year","date","time",
    "originationdate","originationtime","startoffset","origsrcfile",
    "srcpath","srcfile","srcbase","srcext","srcdir",
  }
  for _,k in ipairs(alias) do local v=t[k]; if v and not t[string.lower(k)] then t[string.lower(k)]=v end end
  for i=2,64 do if t["TRK"..i] and not t["trk"..i] then t["trk"..i]=t["TRK"..i] end end
  t.__trk_table = {}
  for i=1,64 do local v=t["trk"..i]; if v and v~="" then t.__trk_table[i]=v end end
  t.__chan_index = guess_channel_index(item, t)
  if not t.__chan_index then for i=1,64 do if t.__trk_table[i] then t.__chan_index=i break end end end
  if t.__chan_index and t.__trk_table[t.__chan_index] then t.__trk_name = t.__trk_table[t.__chan_index] end

  -- 讓左欄診斷可直接取得 item（供 I_CHANMODE 讀取）
  t.__item = item

  -- current take name
  if take then
    local _, cur_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if cur_name and cur_name ~= "" then
      t.curtake = cur_name
    else
      t.curtake = "(unnamed)"
    end
  else
    t.curtake = "(no take)"
  end

  -- current item note
  do
    local _, note = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
    local visible_note, note_meta = parse_note_meta(note)
    t.curnote = visible_note or ""
    t.origsrcfile = note_meta.origsrcfile or ""
  end
  return t
end

-- Build a map: Interleave index (1..N) → Track Name.
-- Priority: iXML TRACK_LIST (CHANNEL_INDEX → NAME).
-- Fallback: TRK# keys (incl. normalized dTRK#) sorted numerically → mapped to 1..N.
local function build_interleave_name_list(fields)
  if fields.__trk_by_interleave then return fields.__trk_by_interleave end

  local by_interleave = {}
  local have_ixml = false

  -- 1) iXML source (if your parser filled this):
  --    fields.__ixml_tracks = { {channel_index=1, channel=3, name="BOOM1"}, ... }
  if fields.__ixml_tracks and type(fields.__ixml_tracks) == "table" then
    for _, t in ipairs(fields.__ixml_tracks) do
      local idx = tonumber(t.channel_index)
      local nm  = t.name
      if idx and idx >= 1 and nm and nm ~= "" then
        by_interleave[idx] = nm
        have_ixml = true
      end
    end
  end

  -- 2) Fallback: derive Interleave order from TRK# keys (dedup by channel number)
  if not have_ixml then
    local pairs_chan = {}  -- { {chan=3,name="BOOM1"}, ... }
    local seen = {}        -- deduplicate by channel number

    for k, v in pairs(fields or {}) do
      -- Accept both "TRK#" and "trk#" but keep only the first occurrence per channel
      local n = k:match("^TRK(%d+)$") or k:match("^trk(%d+)$")
      if n then
        local ch = tonumber(n)
        if ch and v and v ~= "" and not seen[ch] then
          pairs_chan[#pairs_chan+1] = { chan = ch, name = v }
          seen[ch] = true
          if DEBUG then
            reaper.ShowConsoleMsg(string.format("[build_interleave_name_list] Found %s = %s\n", k, v))
          end
        end
      end
    end

    table.sort(pairs_chan, function(a,b) return a.chan < b.chan end)
    for i, e in ipairs(pairs_chan) do
      by_interleave[i] = e.name
      if DEBUG then
        reaper.ShowConsoleMsg(string.format("[build_interleave_name_list] by_interleave[%d] = %s\n", i, e.name))
      end
    end
  end

  fields.__trk_by_interleave = by_interleave
  return by_interleave
end

-- Compute interleave diagnostics for UI and copy/preview paths.
-- Fills:
--   fields.__diag_interleave = {
--     index  = <N>,             -- Interleave index (1..num_channels) from I_CHANMODE
--     total  = <num_channels>,  -- Actual poly channel count (from source or $channels)
--     name   = <string>,        -- Interleave-resolved track name
--     all    = <string>         -- $trkall concatenated in interleave order
--   }
local function compute_interleave_diag(fields, item)
  -- (Re)build interleave table: [1..N] -> track name (iXML CHANNEL_INDEX or TRK# fallback)
  local list = build_interleave_name_list(fields)

  -- Interleave index from I_CHANMODE (clamped to 1..num_channels)
  local nch = get_source_num_channels(item, fields)
  local idx = guess_channel_index(item, fields)

  if DEBUG then
    local list_count = 0
    if list then
      for i = 1, 256 do
        if list[i] then list_count = list_count + 1 end
      end
    end
    reaper.ShowConsoleMsg(string.format("[compute_interleave_diag] nch=%s, idx=%s, list entries=%d\n",
      tostring(nch), tostring(idx), list_count))
  end

  local name = ""
  if idx and list and list[idx] then
    name = list[idx]
    if DEBUG then
      reaper.ShowConsoleMsg(string.format("[compute_interleave_diag] Using list[%d] = %s\n", idx, name))
    end
  else
    -- Fallback: first available name to avoid empty UI
    if list then
      for i = 1, 256 do
        if list[i] and list[i] ~= "" then
          name = list[i]
          if DEBUG then
            reaper.ShowConsoleMsg(string.format("[compute_interleave_diag] Fallback to list[%d] = %s\n", i, name))
          end
          break
        end
      end
    end
  end

  local all = {}
  if list then
    for i = 1, 256 do
      local v = list[i]
      if v and v ~= "" then all[#all+1] = v end
    end
  end

  fields.__diag_interleave = {
    index = idx,
    total = nch,
    name  = name,
    all   = table.concat(all, "_"),
  }
end

-- === Interleave / ChannelNumber helpers (NEW) ===
local function get_current_interleave_index(fields)
  local idx = tonumber(fields and fields.__chan_index) or 1
  if idx < 1 then idx = 1 end
  return idx
end

local function get_recorder_channel_number(fields)
  -- 先蒐集 TRK 表（錄音機 channel → 名稱）
  local pairs_chan, seen = {}, {}
  for k, v in pairs(fields or {}) do
    local n = k:match("^TRK(%d+)$") or k:match("^trk(%d+)$")
    if n and not seen[n] then
      seen[n] = true
      pairs_chan[#pairs_chan+1] = { chan = tonumber(n), name = v }
    end
  end
  table.sort(pairs_chan, function(a,b) return (a.chan or 0) < (b.chan or 0) end)

  local il = get_current_interleave_index(fields)
  if #pairs_chan > 0 then
    local e = pairs_chan[il]
    if e and e.chan then return e.chan end
  end
  -- 找不到 TRK# → 回退用 interleave
  return il
end


-- Wrap known $tokens to ${token} so $sceneT$take -> ${scene}T${take}
local function normalize_tokens(s)
  s = tostring(s or "")

  -- forms with numbers/colon
  s = s:gsub("%$trk(%d+)", "${trk%1}")
  s = s:gsub("%$(counter:%d+)", "${%1}")
  s = s:gsub("%$(srcbaseprefix:%d+)", "${%1}")
  s = s:gsub("%$(srcbasesuffix:%d+)", "${%1}")

  -- plain known tokens
  local known = {
    "curtake","curnote","clearnote","track","filename","origsrcfile","srcfile","srcbase","srcext","srcpath","srcdir",
    "samplerate","channels","length","project","scene","take","tape","trk","trkall",
    "ubits","framerate","speed","date","time","year","originationdate","originationtime","startoffset",
    "filepath","originator","originatorreference","timereference","description", "interleave","interum","chnum","channelnum",
  }
  table.sort(known, function(a,b) return #a > #b end)  -- NEW
  for _,k in ipairs(known) do
    s = s:gsub("%$"..k, "${"..k.."}")
  end

  return s
end

-- Forward declare so helpers below can call it before its definition
local expand_template




-- 列出樣板中實際使用到的 token（以 normalize 後的 ${...} 為準）
local function template_token_list(tpl)
  local list, seen = {}, {}
  local s = normalize_tokens(tpl or "")
  for name in s:gmatch("%${([%w_:]+)}") do
    if not seen[name] then
      seen[name] = true
      list[#list+1] = name
    end
  end
  table.sort(list)
  return list
end

-- 回傳「在 Take 樣板裡會展開為空字串」的 token 名稱陣列
-- 不改變/污染任何 fields；僅用 expand_template 試算
local function empty_tokens_in_take_template(tpl, fields, counter)
  local empties = {}
  local tokens = template_token_list(tpl)
  for _, tk in ipairs(tokens) do
    if tk ~= "clearnote" then
      local probe = "${" .. tk .. "}"
      local out = expand_template(probe, fields, counter, false) or ""
      out = tostring(out):gsub("^%s+", ""):gsub("%s+$", "")
      if out == "" then empties[#empties+1] = tk end
    end
  end
  return empties
end

-- ===== Template expansion =====
function expand_template(tpl, fields, counter, sanitize)
  if sanitize == nil then sanitize = true end

  local function maybe_sanitize(s)
    s = tostring(s or "")
    if sanitize then return (s:gsub('[\\/:*?"<>|%c]', '_')) end
    return s
  end

  local function repl(name)
    local tkl = string.lower(name or "")
    if tkl == "clearnote" then return "" end

    -- $srcbaseprefix:N - first N chars of srcbase
    local prefix = tkl:match("^srcbaseprefix:(%d+)$")
    if prefix then
      local n = tonumber(prefix) or 0
      local srcbase = fields.srcbase or fields.filename or ""
      if n > 0 then
        local spans = utf8_spans(srcbase)
        local len = math.min(n, #spans)
        if len > 0 then
          local cut = srcbase:sub(1, spans[len][2])
          return cut
        end
      end
      return ""
    end

    -- $srcbasesuffix:N - last N chars of srcbase
    local suffix = tkl:match("^srcbasesuffix:(%d+)$")
    if suffix then
      local n = tonumber(suffix) or 0
      local srcbase = fields.srcbase or fields.filename or ""
      local spans = utf8_spans(srcbase)
      local len = #spans
      if n > 0 and len > 0 then
        local start_i = math.max(1, len - n + 1)
        local cut = srcbase:sub(spans[start_i][1], spans[len][2])
        return cut
      end
      return ""
    end

    -- ${counter:N}
    local digits = tkl:match("^counter:(%d+)$")
    if digits then
      local n = tonumber(digits) or 0
      local val = tostring(counter or 1)
      if n > 0 then val = string.rep("0", math.max(0, n - #val)) .. val end
      return val
    end

    -- $trk → Interleave-resolved name (metadata-only, Wave Agent–style)
    if tkl == "trk" then
      local interleave = fields.__chan_index
      local list = build_interleave_name_list(fields)
      local s = ""
      if interleave and list and list[interleave] then
        s = list[interleave]
      else
        -- Fallback: first available name
        if list then
          for i = 1, 128 do
            if list[i] and list[i] ~= "" then s = list[i]; break end
          end
        end
      end
      return trim(maybe_sanitize(s or ""))
    end

    -- $trkall → names concatenated in Interleave order (metadata-only)
    if tkl == "trkall" then
      local list = build_interleave_name_list(fields)
      local out = {}
      if list then
        for i = 1, 256 do
          local v = list[i]
          if v and v ~= "" then out[#out+1] = v end
        end
      end
      return table.concat(out, "_")
    end

    -- $trkN (explicit by recorder channel number indexing table)
    local nidx = tkl:match("^trk(%d+)$")
    if nidx then
      local idx = tonumber(nidx)
      local v = (fields.__trk_table and fields.__trk_table[idx]) or fields["trk"..nidx] or fields["TRK"..nidx]
      local s = tostring(v or "")
      return trim(maybe_sanitize(s))
    end

    -- ${interleave} / ${interum} → 目前 Interleave 序號（1..N）
    if tkl == "interleave" or tkl == "interum" then
      local idx = get_current_interleave_index(fields)
      return tostring(idx or "")
    end

    -- ${chnum} / ${channelnum} → 錄音機的 Channel 編號（優先 TRK#，否則退回 interleave）
    if tkl == "chnum" or tkl == "channelnum" then
      local chn = get_recorder_channel_number(fields)
      return tostring(chn or "")
    end


    -- default: plain field
    local v = fields[tkl] or fields[name] or ""
    local s = tostring(v or "")
    return trim(maybe_sanitize(s))
  end

  local out = normalize_tokens(tpl or "")
  out = out:gsub("%${(.-)}", function(s) return repl(s) end)
  out = out:gsub("%$([%a%d:]+)", function(s) return repl(s) end)
  out = out:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end


-- ===== Integrate with hsuanice Metadata Read (>= 0.2.0) =====
do
  local SCRIPTS = reaper.GetResourcePath() .. "/Scripts"
  package.path  = SCRIPTS .. "/?.lua;" .. package.path
end
local META = require("hsuanice Scripts/Library/hsuanice_Metadata Read")
assert(META and (META.VERSION or "0") >= "0.2.0", "Please update 'hsuanice Metadata Read' to >= 0.2.0")

-- Override former internal metadata readers / expanders with Library calls
local _collect_metadata_for_item_impl = collect_metadata_for_item

-- Helper function to convert between cache format and full fields format
local function cache_to_fields(cached, item)
  -- Cache only stores BWF/iXML metadata
  -- Need to supplement with source file info, UI-specific fields, and track info

  -- Debug: Show what's in the cache
  if DEBUG then
    reaper.ShowConsoleMsg(string.format("[cache_to_fields] Cache contains description='%s'\n", tostring(cached.description or "")))
    reaper.ShowConsoleMsg(string.format("[cache_to_fields] Cache contains file_name='%s'\n", tostring(cached.file_name or "")))
  end

  local fields = {
    -- From cache (BWF/iXML metadata)
    umid = cached.umid or "",
    umid_pt = cached.umid_pt or "",
    origination_date = cached.origination_date or "",
    originationdate = cached.origination_date or "",
    origination_time = cached.origination_time or "",
    originationtime = cached.origination_time or "",
    originator = cached.originator or "",
    originator_ref = cached.originator_ref or "",
    originatorreference = cached.originator_ref or "",
    time_reference = cached.time_reference or "",
    timereference = cached.time_reference or "",
    description = cached.description or "",
    project = cached.project or "",
    scene = cached.scene or "",
    take_meta = cached.take_meta or "",
    take = cached.take_meta or "",
    tape = cached.tape or "",
    ubits = cached.ubits or "",
    framerate = cached.framerate or "",
    speed = cached.speed or "",
    -- From cache (file and track info)
    file_name = cached.file_name or "",
    interleave = cached.interleave or 0,
    meta_trk_name = cached.meta_trk_name or "",
    channel_num = cached.channel_num or 0
  }

  -- Parse description for TRK# fields (this is quick, no file I/O)
  -- Description contains key=value pairs separated by newlines or semicolons
  -- Example: "sPROJECT=WEDDING\nsTRK9=BOOM 1\n" or "sTRK1=BOOM; sTRK2=LAVA"
  local desc = fields.description or ""
  if desc ~= "" then
    -- Parse key=value pairs from description (split by newline OR semicolon)
    for kv in desc:gmatch("([^\r\n;]+)") do
      local k, v = kv:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
      if k and v and v ~= "" then
        local up = k:upper()
        -- Map dTRK#/TRK#/sTRK# → TRK#/trk#
        local n = up:match("^[SD]?TRK(%d+)$")
        if n then
          fields["TRK"..n] = v
          fields["trk"..n] = v
          if DEBUG then
            reaper.ShowConsoleMsg(string.format("[cache_to_fields] Parsed TRK%s = %s from description\n", n, v))
          end
        end
        -- Also map other description fields (handle both sPROJECT and PROJECT)
        if up == "SPROJECT" or up == "PROJECT" then
          fields["PROJECT"] = v
          fields["project"] = v
        elseif up == "SSCENE" or up == "SCENE" then
          fields["SCENE"] = v
          fields["scene"] = v
        elseif up == "STAKE" or up == "TAKE" then
          fields["TAKE"] = v
          fields["take"] = v
        elseif up == "STAPE" or up == "TAPE" then
          fields["TAPE"] = v
          fields["tape"] = v
        end
      end
    end
  end

  -- Build __trk_table from TRK# fields
  fields.__trk_table = {}
  for i = 1, 64 do
    local v = fields["trk"..i]
    if v and v ~= "" then
      fields.__trk_table[i] = v
    end
  end

  -- Guess channel index (interleave index) from I_CHANMODE
  fields.__chan_index = guess_channel_index(item, fields)
  if not fields.__chan_index then
    -- Fallback: use first available TRK
    for i = 1, 64 do
      if fields.__trk_table[i] then
        fields.__chan_index = i
        break
      end
    end
  end

  -- Set __trk_name
  if fields.__chan_index and fields.__trk_table[fields.__chan_index] then
    fields.__trk_name = fields.__trk_table[fields.__chan_index]
  end

  -- Get source file info (quick access, no file I/O needed)
  local take = get_active_take(item)
  if take then
    local src = take_source(take)
    local fn = src and source_filename(src)
    if fn and fn ~= "" then
      fields.srcpath = fn
      fields.srcfile = basename(fn)
      fields.srcbase = basename_no_ext(fn)
      fields.srcext = get_ext(fn)
      fields.srcdir = dirname(fn)
      fields.filename = fields.srcbase
      fields.filepath = fn
    end

    -- Get samplerate and channels
    if src then
      local sr = reaper.GetMediaSourceSampleRate(src) or 0
      local ch = reaper.GetMediaSourceNumChannels(src) or 0
      if sr > 0 then fields.samplerate = tostring(math.floor(sr + 0.5)) end
      if ch > 0 then fields.channels = tostring(ch) end
    end

    -- Get current take name
    local _, cur_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    fields.curtake = (cur_name and cur_name ~= "") and cur_name or "(unnamed)"
  else
    fields.curtake = "(no take)"
  end

  -- Get current item note
  local _, note = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  local visible_note, note_meta = parse_note_meta(note)
  fields.curnote = (visible_note and visible_note ~= "") and visible_note or ""
  fields.origsrcfile = note_meta.origsrcfile or ""

  -- UI-specific fields (not cached, computed on the fly)
  fields.track = get_item_track_name(item)
  fields.length = seconds_to_m_ss_mmm(get_item_length_sec(item))

  -- Build __trk_table and __chan_index (needed by interleave resolution)
  -- These will be populated from the cached metadata later by META functions
  fields.__item = item

  -- Add lowercase aliases for all uppercase fields (META library may expect these)
  local alias_keys = {
    "DESCRIPTION", "ORIGINATION_DATE", "ORIGINATION_TIME", "ORIGINATOR",
    "ORIGINATOR_REF", "TIME_REFERENCE", "PROJECT", "SCENE", "TAKE", "TAPE",
    "UBITS", "FRAMERATE", "SPEED", "UMID", "UMID_PT"
  }
  for _, k in ipairs(alias_keys) do
    local v = fields[k]
    if v and not fields[k:lower()] then
      fields[k:lower()] = v
    end
  end

  if DEBUG then
    local trk_count = 0
    if fields.__trk_table then
      for k, v in pairs(fields.__trk_table) do
        if v and v ~= "" then trk_count = trk_count + 1 end
      end
    end
    reaper.ShowConsoleMsg(string.format("[cache_to_fields] Final fields: __chan_index=%s, __trk_table entries=%d, __trk_name=%s\n",
      tostring(fields.__chan_index), trk_count, tostring(fields.__trk_name or "")))
  end

  return fields
end

local function fields_to_cache(fields)
  -- Extract only the metadata fields that should be cached
  return {
    file_name = fields.srcfile or fields.filename or "",
    interleave = fields.interleave or 0,
    meta_trk_name = fields.meta_trk_name or "",
    channel_num = fields.channel_num or 0,
    umid = fields.umid or "",
    umid_pt = fields.umid_pt or "",
    origination_date = fields.origination_date or fields.originationdate or "",
    origination_time = fields.origination_time or fields.originationtime or "",
    originator = fields.originator or "",
    originator_ref = fields.originator_ref or fields.originatorreference or "",
    time_reference = fields.time_reference or fields.timereference or "",
    description = fields.description or "",
    project = fields.project or "",
    scene = fields.scene or "",
    take_meta = fields.take_meta or fields.take or "",
    tape = fields.tape or "",
    ubits = fields.ubits or "",
    framerate = fields.framerate or "",
    speed = fields.speed or ""
  }
end

collect_metadata_for_item = function(item)
  local t = META.collect_item_fields(item) or {}
  -- Supplement fields that are UI-specific in this script
  t.track  = get_item_track_name(item)
  t.length = seconds_to_m_ss_mmm(get_item_length_sec(item))
  return t
end

compute_interleave_diag = function(fields, item)
  return META.compute_interleave_diag(fields, item)
end

empty_tokens_in_take_template = function(tpl, fields, counter)
  return META.empty_tokens_in_template(tpl, fields, counter)
end

expand_template = function(tpl, fields, counter, sanitize)
  return META.expand(tpl, fields, counter, sanitize)
end

guess_channel_index = function(item, fields)
  return META.guess_interleave_index(item, fields)
end

-- ===== Selection & cache =====
local function get_item_guid(item) local _,guid=reaper.GetSetMediaItemInfo_String(item,"GUID","",false); return guid or "" end
local function get_selected_items_and_sig()
  local items, parts = {}, {}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do local it=reaper.GetSelectedMediaItem(0,i); items[#items+1]=it; parts[#parts+1]=get_item_guid(it) end
  return items, table.concat(parts,";")
end

-- ===== UI / State =====
local TAKE_TEMPLATE, NOTE_TEMPLATE = load_defaults()
-- Presets (in-memory) + focus flags
local TAKE_PRESETS = load_presets(TAKE_PRESETS_KEY)
local TAKE_TEMPLATE_HISTORY = load_recent_list(TAKE_HISTORY_KEY, TAKE_HISTORY_LIMIT)
local NOTE_PRESETS = load_presets(NOTE_PRESETS_KEY)
local focus_take_input, focus_note_input = false, false

local caret_take_char, caret_note_char = nil, nil
local preview_limit = 50
local preview_rows, status_msg = {}, ""
local close_after_apply = false
local active_box = "take"
local SCAN_CACHE = nil
local left_copy_text, right_copy_text = "", ""
local right_copy_fmt = "tsv"
local RIGHT_SELECTABLE_VIEW = false
local SPLIT_RATIO = load_split_ratio()
local _drag_active = false
local _last_my = 0

-- ===== Post-Apply result state =====
local SHOW_RESULT_MODAL  = false
local PENDING_RESULT_OPEN = false   -- set by deferred apply; ImGui_OpenPopup called on next frame
local LAST_RESULT = nil  -- { total_sel, renamed, noted, skipped, rows = { {idx, old, newname, newnote, status}... } }



-- ===== Token list =====
local TOKEN_LIST = {
  "$origsrcfile","$curtake","$clearnote","$track","$filename","$srcfile","$srcbase",'$srcbaseprefix:N','$srcbasesuffix:N',"$srcext","$srcpath","$srcdir",
  "$samplerate","$channels","$length",
  "$project","$scene","$take","$tape",
  "$trk","$trkall",
  "$ubits","$framerate","$speed",
  "$date","$time","$year","$originationdate","$umid", "$umid_pt","$originationtime","$startoffset",
  "${counter:2}","$interleave","$interum","$chnum",
}

-- ===== Token insertion (caret only) =====
local function append_token(tk)
  if active_box == "note" then
    local s, new_idx = safe_insert_token(NOTE_TEMPLATE, caret_note_char, tk)
    NOTE_TEMPLATE = s; caret_note_char = new_idx
  else
    local s, new_idx = safe_insert_token(TAKE_TEMPLATE, caret_take_char, tk)
    TAKE_TEMPLATE = s; caret_take_char = new_idx
  end
end

local function field_row_token(key, value)
  local tk = "$"..key
  if reaper.ImGui_SmallButton(ctx, tk .. "##field_" .. key) then append_token(tk) end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
  reaper.ImGui_InputText(ctx, "##fv_"..key, tostring(value or ""), reaper.ImGui_InputTextFlags_ReadOnly())
end

-- ===== CSV helpers =====
local function csv_escape(s) s=tostring(s or ""); if s:find('[,\r\n"]') then s='"'..s:gsub('"','""')..'"' end; return s end

-- ===== File save helpers =====
local function default_save_dir()
  local ok, proj_path = reaper.EnumProjects(-1, "")
  if proj_path and proj_path ~= "" then
    local dir = proj_path:match("^(.*)[/\\]") or proj_path
    if dir and dir ~= "" then return dir end
  end
  return reaper.GetResourcePath() or "."
end

local function timestamp()
  local t = os.date("*t")
  return string.format("%04d%02d%02d_%02d%02d%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function split_name_ext(path)
  local filename = tostring(path or ""):match("[^/\\]+$") or tostring(path or "")
  local base, ext = filename:match("^(.-)(%.[^%.]+)$")
  if base then
    return base, ext or ""
  end
  return filename, ""
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function make_unique_target_path(old_path, new_name)
  local dir = tostring(old_path or ""):match("^(.*[\\/])") or ""
  local candidate = dir .. tostring(new_name or "")
  if candidate == old_path or not file_exists(candidate) then
    return candidate
  end
  local base, ext = split_name_ext(new_name)
  local i = 1
  while file_exists(candidate) and candidate ~= old_path do
    candidate = dir .. base .. string.format("-%03d", i) .. ext
    i = i + 1
  end
  return candidate
end

local function build_source_name(template, fields, index, old_path)
  local tpl = tostring(template or "")
  local tpl_trim = tpl:gsub("^%s+", ""):gsub("%s+$", "")
  local has_rules = TAKE_RENAMER and TAKE_RENAMER.enable and TAKE_RENAMER.rules and (#TAKE_RENAMER.rules > 0)
  if tpl_trim == "" and has_rules then
    tpl = "$srcfile"
  end

  local new_name = expand_template(tpl, fields, index)

  new_name = apply_take_filter(new_name)
  new_name = apply_take_renamer(new_name)
  if not new_name or new_name == "" then
    new_name = fields and (fields.srcbase or fields.filename or "") or ""
  end
  if new_name:match("%.[^%.]+$") then
    return new_name
  end
  local _, ext = split_name_ext(old_path or "")
  return new_name .. ext
end

local function write_text_file(path, text)
  local f, err = io.open(path, "w")
  if not f then return false, tostring(err or "open failed") end
  f:write(text or "")
  f:close()
  return true
end

-- 優先用 js_ReaScriptAPI 的另存對話框；若沒有，直接自動存到專案資料夾
local function choose_save_path(default_name, filter)
  local js = reaper.JS_Dialog_BrowseForSaveFile
  if type(js) == "function" then
    local ret, fn = js("Save list", default_save_dir(), default_name, filter or "All (*.*)\0*.*\0")
    if ret and ret ~= 0 and fn and fn ~= "" then
      return fn
    else
      return nil -- user canceled
    end
  end
  -- Fallback when JS API is unavailable: autosave to default folder
  return (default_save_dir() .. "/" .. default_name)
end

local function build_result_text(fmt, rows)
  local sep = (fmt == "csv") and "," or "\t"
  local out = {}
  local function esc(s)
    s = tostring(s or "")
    if fmt == "csv" and s:find('[,\r\n"]') then s = '"'..s:gsub('"','""')..'"' end
    return s
  end
  local rule_str = ""
  if TAKE_RENAMER and TAKE_RENAMER.enable and TAKE_RENAMER.rules and #TAKE_RENAMER.rules > 0 then
    for i, p in ipairs(TAKE_RENAMER.rules) do
      if p and (p.from or "") ~= "" then
        rule_str = rule_str .. (i>1 and "; " or "") .. tostring(p.from or "") .. "→" .. tostring(p.to or "")
      end
    end
  else
    rule_str = "(none)"
  end
  out[#out+1] = table.concat({
    "Info",
    "",
    tostring(TAKE_TEMPLATE or ""),
    rule_str
  }, sep)
  out[#out+1] = table.concat({ "#","Current Source File","New Source File","Replaced" }, sep)
  for _, r in ipairs(rows or {}) do
    out[#out+1] = table.concat({ esc(r.idx), esc(r.old), esc(r.newname), esc(r.replaced or "") }, sep)
  end
  return table.concat(out, "\n")
end

-- Build text (TSV/CSV) for skipped list
local function build_skipped_text(fmt, srows)
  local sep = (fmt == "csv") and "," or "\t"
  local out = {}
  local function esc(s)
    s = tostring(s or "")
    if fmt == "csv" and s:find('[,\r\n"]') then s = '"'..s:gsub('"','""')..'"' end
    return s
  end
  -- Header：#, Current Take Name, Srcfile, Reason
  out[#out+1] = table.concat({ "#", "Current Take Name", "Srcfile", "Reason" }, sep)
  for _, r in ipairs(srows or {}) do
    out[#out+1] = table.concat({
      esc(r.idx),
      esc(r.current or ""),
      esc(r.srcfile or ""),
      esc(r.reason or "")
    }, sep)
  end
  return table.concat(out, "\n")
end



-- ===== Result modal =====
local function open_result_modal(res)
  LAST_RESULT = res
  SHOW_RESULT_MODAL = true
  PENDING_RESULT_OPEN = true   -- ImGui_OpenPopup will be called on the next loop frame
end

local function draw_result_modal()
  if not SHOW_RESULT_MODAL then return end
  -- Must call ImGui_OpenPopup inside the ImGui frame; deferred apply sets the pending flag
  if PENDING_RESULT_OPEN then
    reaper.ImGui_OpenPopup(ctx, "Apply Result")
    PENDING_RESULT_OPEN = false
  end
  local opened = reaper.ImGui_BeginPopupModal(ctx, "Apply Result", true)
  if opened then
    local r = LAST_RESULT or { total_sel=0, renamed=0, noted=0, skipped=0, rows={} }
    reaper.ImGui_Text(ctx, ("Selected: %d"):format(r.total_sel or 0))
    reaper.ImGui_Text(ctx, ("Renamed:  %d"):format(r.renamed or 0))
    reaper.ImGui_Text(ctx, ("Notes:    %d"):format(r.noted or 0))
    reaper.ImGui_Text(ctx, ("Skipped:  %d"):format(r.skipped or 0))
    reaper.ImGui_Separator(ctx)

    -- Save buttons (no popups; silent on success/cancel/failure)
    if reaper.ImGui_Button(ctx, "Save as .tsv", 150, 26) then
      local name = ("RenameResult_%s.tsv"):format(timestamp())
      local path = choose_save_path(name, "Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
      -- If canceled, path is nil → do nothing
      if path then
        local _ = write_text_file(path, build_result_text("tsv", r.rows))
        -- optional: update status line in the main UI (no modal)
        -- status_msg = _ and ("Saved: " .. path) or "Save failed."
      end
    end

    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Save as .csv", 150, 26) then
      local name = ("RenameResult_%s.csv"):format(timestamp())
      local path = choose_save_path(name, "CSV (*.csv)\0*.csv\0All (*.*)\0*.*\0")
      if path then
        local _ = write_text_file(path, build_result_text("csv", r.rows))
        -- optional: status_msg = _ and ("Saved: " .. path) or "Save failed."
      end
    end

    -- ----- Skipped details -----
    reaper.ImGui_Separator(ctx)
    local srows = r.skipped_rows or {}
    reaper.ImGui_Text(ctx, ("Skipped details: %d"):format(#srows))

    do
      local begun, _ = BeginChildSafe("##skip_list_child", -1, 220, true)
      if begun then
        local flags = TF('ImGui_TableFlags_Borders') | TF('ImGui_TableFlags_RowBg')
        if reaper.ImGui_BeginTable(ctx, "SkippedTable", 4, flags) then
          -- 新順序：#, Current Take Name, Srcfile, Reason
          reaper.ImGui_TableSetupColumn(ctx, "#", TF('ImGui_TableColumnFlags_WidthFixed'), 36)
          reaper.ImGui_TableSetupColumn(ctx, "Current Take Name")
          reaper.ImGui_TableSetupColumn(ctx, "Srcfile")
          reaper.ImGui_TableSetupColumn(ctx, "Reason")
          reaper.ImGui_TableHeadersRow(ctx)

          if #srows == 0 then
            reaper.ImGui_TableNextRow(ctx)
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "-")
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "(none)")
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "")
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "")
          else
            for _, sr in ipairs(srows) do
              reaper.ImGui_TableNextRow(ctx)
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(sr.idx or ""))
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, tostring(sr.current or ""))
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, tostring(sr.srcfile or ""))
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, tostring(sr.reason or ""))
            end
          end

          reaper.ImGui_EndTable(ctx)
        end
        reaper.ImGui_EndChild(ctx)
      end
    end  
    -- Save/Copy skipped list
    if srows and #srows > 0 then
      if reaper.ImGui_Button(ctx, "Save skipped as .tsv", 180, 24) then
        local name = ("Skipped_%s.tsv"):format(timestamp())
        local path = choose_save_path(name, "Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
        if path then write_text_file(path, build_skipped_text("tsv", srows)) end
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Save skipped as .csv", 180, 24) then
        local name = ("Skipped_%s.csv"):format(timestamp())
        local path = choose_save_path(name, "CSV (*.csv)\0*.csv\0All (*.*)\0*.*\0")
        if path then write_text_file(path, build_skipped_text("csv", srows)) end
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Copy skipped (TSV)", 180, 24) then
        reaper.ImGui_SetClipboardText(ctx, build_skipped_text("tsv", srows))
      end
    end


    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, "Close", 100, 26) then
      SHOW_RESULT_MODAL = false
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  else
    -- 關閉/ESC 後清旗標
    SHOW_RESULT_MODAL = false
  end
end


-- ===== Build left/right copy texts =====
local function build_left_copy_text_from_fields(f)
  -- Ensure interleave diagnostics are ready
  if not f.__diag_interleave then compute_interleave_diag(f, f.__item or nil) end
  local diag = f.__diag_interleave or {}

  local lines = {}
  local function add(k, v) if v and v~="" then lines[#lines+1] = tostring(k).."\t"..tostring(v) end end

  -- $trk (interleave-resolved)
  local trk_line = (diag.name and diag.name ~= "" and diag.name) or ""
  if diag.index and diag.total then
    trk_line = string.format("%s (interleave %d/%d)", trk_line, diag.index or 0, diag.total or 0)
  end
  add("$trk", trk_line)

  -- $trkall (interleave order)
  add("$trkall", diag.all or "")

  -- rest in stable order (unchanged)
  local ordered = {
    "origsrcfile",
    "project","scene","take","tape","track",
    "filename","srcfile","srcbase","srcext","srcpath","srcdir","filepath",
    "samplerate","channels","length",
    "date","time","year","originationdate","originationtime","startoffset",
    "framerate","speed","ubits","originator","originatorreference",
    "umid","umid_pt",
    "timereference",
    "trk1","trk2","trk3","trk4","trk5","trk6","trk7","trk8","trk9","trk10",
    "trk11","trk12","trk13","trk14","trk15","trk16",
    "description"
  }
  for _,k in ipairs(ordered) do if f[k] ~= nil then add("$"..k, f[k]) end end
  return table.concat(lines, "\n")
end

local function build_right_copy_text_from_rows(fmt)
  local sep = (fmt == "csv") and "," or "\t"
  local out = {}
  local function add(...)
    local a = { ... }
    if fmt == "csv" then
      for i = 1, #a do a[i] = csv_escape(a[i]) end
    end
    out[#out + 1] = table.concat(a, sep)
  end

  -- 表頭（順序：#, Current Source File, New Source File, Rename History）
  add("#","Current Source File","New Source File","Rename History")

  -- 內容
  if preview_rows and #preview_rows > 0 then
    for i, r in ipairs(preview_rows) do
      add(
        tostring(i),
        r.current or "",
        r.newname or "",
        r.history_preview or ""
      )
    end
  end
  return table.concat(out, "\n")
end

-- ===== Build preview (from selection) =====
local function scan_metadata()
  TAKE_TEMPLATE_HISTORY = push_recent_list(TAKE_TEMPLATE_HISTORY, TAKE_HISTORY_KEY, TAKE_HISTORY_LIMIT, TAKE_TEMPLATE)
  local items, sig = get_selected_items_and_sig()
  SCAN_CACHE = { sig=sig, list={}, map={} }
  local counter = 1
  for _, item in ipairs(items) do
    local guid = get_item_guid(item)
    local f

    -- Try to lookup from cache first
    local cached = CACHE.lookup(guid, item)
    if cached then
      -- Cache hit - use cached metadata and supplement with UI fields
      f = cache_to_fields(cached, item)
    else
      -- Cache miss - read metadata from file
      f = collect_metadata_for_item(item)
      -- Store in cache for next time
      CACHE.store(guid, item, fields_to_cache(f))
    end

    local take = get_active_take(item)
    local cur = "(no take)"
    if take then
      local _, cur_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
      cur = (cur_name and cur_name ~= "") and cur_name or "(unnamed)"
    end

    local entry = { item=item, guid=guid, fields=f, current=cur, order=counter }
    SCAN_CACHE.list[#SCAN_CACHE.list+1] = entry
    SCAN_CACHE.map[guid] = entry
    counter = counter + 1
  end
  preview_rows = {}
  local shown = 0
  if DEBUG then
    reaper.ShowConsoleMsg(string.format("[scan_metadata] Building preview for %d items, preview_limit=%s\n",
      #SCAN_CACHE.list, tostring(preview_limit)))
  end
  for i, e in ipairs(SCAN_CACHE.list) do
    if not preview_limit or shown < preview_limit then
      if DEBUG and i <= 3 then
        reaper.ShowConsoleMsg(string.format("[scan_metadata] Processing item %d/%d for preview\n", i, #SCAN_CACHE.list))
      end
      e.fields.__trk_by_interleave = nil
      compute_interleave_diag(e.fields, e.item)
      local take = get_active_take(e.item)
      local actual_src_path = (take and get_take_source_path(take)) or (e.fields and e.fields.srcpath) or ""
      local current_src = basename(actual_src_path)
      if current_src == "" then current_src = tostring(e.fields and e.fields.srcfile or e.current or "") end
      local newname = build_source_name(TAKE_TEMPLATE, e.fields, i, actual_src_path)
      local _, raw_note = reaper.GetSetMediaItemInfo_String(e.item, "P_NOTES", "", false)
      local will_skip = false
      if SKIP_EMPTY_TOKENS then
        local empties = empty_tokens_in_take_template(TAKE_TEMPLATE, e.fields, i)
        will_skip = (#empties > 0)
      end

      preview_rows[#preview_rows+1] = {
        current = current_src,
        newname = newname,
        history_preview = format_history_preview(raw_note),
        note_applied = false,
        will_skip = will_skip
      }


      shown = shown + 1
    end
  end
  right_copy_text = build_right_copy_text_from_rows(right_copy_fmt)
  local total = #items
  status_msg = (total==0) and "No items selected."
            or string.format("Scanned %d item(s). Preview shows first %d. (cached)", total, math.min(total, preview_limit))
end

local function recompute_preview_from_cache()
  if not SCAN_CACHE then preview_rows = {}; right_copy_text=""; status_msg="No cached metadata. Click 'Get Metadata'.";  return end
  preview_rows = {}
  local shown = 0
  for i, e in ipairs(SCAN_CACHE.list) do
    if not preview_limit or shown < preview_limit then
      e.fields.__trk_by_interleave = nil
      compute_interleave_diag(e.fields, e.item)
      local take = get_active_take(e.item)
      local actual_src_path = (take and get_take_source_path(take)) or (e.fields and e.fields.srcpath) or ""
      local current_src = basename(actual_src_path)
      if current_src == "" then current_src = tostring(e.fields and e.fields.srcfile or e.current or "") end
      local newname = build_source_name(TAKE_TEMPLATE, e.fields, i, actual_src_path)
      local _, raw_note = reaper.GetSetMediaItemInfo_String(e.item, "P_NOTES", "", false)
      local will_skip = false
      if SKIP_EMPTY_TOKENS then
        local empties = empty_tokens_in_take_template(TAKE_TEMPLATE, e.fields, i)
        will_skip = (#empties > 0)
      end

      preview_rows[#preview_rows+1] = {
        current = current_src,
        newname = newname,
        history_preview = format_history_preview(raw_note),
        note_applied = false,
        will_skip = will_skip
      }
      
      shown = shown + 1
    end
  end
  right_copy_text = build_right_copy_text_from_rows(right_copy_fmt)
  status_msg = string.format("Using cached metadata. Showing first %d.", shown)
end

-- ===== Apply (deferred with progress console) =====
local APPLY_STATE = nil
local APPLY_BATCH = 50   -- items processed per defer frame

local function apply_renaming_step()
  if not APPLY_STATE then return end
  local p = APPLY_STATE

  local i_end = math.min(p.i + APPLY_BATCH - 1, p.total)

  for i = p.i, i_end do
    local item = p.items[i]
    local take = get_active_take(item)
    local current_take_name = "(no take)"
    if take then
      local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
      current_take_name = (tn and tn ~= "") and tn or "(unnamed)"
    end
    local fields
    if p.can_use_cache then
      local e = SCAN_CACHE and SCAN_CACHE.map and SCAN_CACHE.map[get_item_guid(item)]
      fields = e and e.fields
    end
    if not fields then
      fields = collect_metadata_for_item(item)
    end

    local actual_source = take and get_take_source_path(take)
    local old_source = tostring(actual_source or (fields and fields.srcpath or ""))
    local old_name = tostring(fields and fields.srcfile or "")
    local original_source_name = basename(old_source)
    local new_name = ""
    local skip_reason = nil

    if old_source ~= "" then
      new_name = build_source_name(TAKE_TEMPLATE, fields, p.counter, old_source)
      if new_name ~= "" then
        local dir = old_source:match("^(.*[\\/])") or ""
        local target_path = make_unique_target_path(old_source, new_name)
        local target_full = dir .. new_name
        if target_path ~= old_source then
          local ok_rename, err = os.rename(old_source, target_path)
          if not ok_rename then
            ok_rename, err = os.rename(old_source:gsub("\\", "/"), target_path:gsub("\\", "/"))
          end
          if ok_rename then
            local peak_old = old_source .. ".reapeaks"
            local peak_new = target_path .. ".reapeaks"
            if file_exists(peak_old) then
              local ok_peak = os.rename(peak_old, peak_new)
              if not ok_peak and not file_exists(peak_new) then
                reaper.ShowConsoleMsg(string.format("  [warn] peak rename failed for %s\n", old_source))
              end
            end
            if take then
              local ok_replace, replace_err = replace_take_source_from_file(take, target_path)
              if not ok_replace then
                skip_reason = string.format("source update failed: %s", replace_err or "unknown")
              else
                local take_name = basename(target_path)
                local _, current_note = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
                local updated_note = append_rename_note_history(current_note, original_source_name, take_name)
                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
                reaper.GetSetMediaItemInfo_String(item, "P_NOTES", updated_note, true)
                p.renamed = p.renamed + 1
              end
            else
              p.renamed = p.renamed + 1
            end
          else
            skip_reason = string.format("rename failed: %s", err or "unknown")
          end
        elseif target_full == old_source then
          skip_reason = "unchanged"
        end
      else
        skip_reason = "empty template"
      end
    else
      skip_reason = "no source path"
    end

    if skip_reason then
      p.skipped = p.skipped + 1
      p.skipped_rows[#p.skipped_rows+1] = {
        idx = i,
        current = current_take_name,
        srcfile = old_name,
        reason = skip_reason,
      }
    end

    p.rows[#p.rows+1] = {
      idx = i,
      old = old_name,
      newname = new_name,
      replaced = "",
      current_note = "",
      newnote = ""
    }
    p.counter = p.counter + 1
  end

  p.i = i_end + 1

  reaper.ShowConsoleMsg(string.format("  [%d / %d] processed\n", math.min(i_end, p.total), p.total))

  if p.i > p.total then
    reaper.UpdateArrange()
    reaper.Undo_EndBlock(string.format("Rename %d source file(s)", p.renamed), -1)
    status_msg = string.format("Done: %d renamed, %d skipped.", p.renamed, p.skipped)
    reaper.ShowConsoleMsg(string.format("Done: %d renamed, %d skipped.\n", p.renamed, p.skipped))
    APPLY_STATE = nil
    open_result_modal({
      total_sel = p.total,
      renamed = p.renamed,
      noted = 0,
      skipped = p.skipped,
      rows = p.rows,
      skipped_rows = p.skipped_rows or {}
    })
  else
    reaper.defer(apply_renaming_step)
  end
end

local function apply_renaming()
  local items, sig = get_selected_items_and_sig()
  local total = #items
  if total == 0 then status_msg="No items selected."; return end

  TAKE_TEMPLATE_HISTORY = push_recent_list(TAKE_TEMPLATE_HISTORY, TAKE_HISTORY_KEY, TAKE_HISTORY_LIMIT, TAKE_TEMPLATE)

  -- 防止重複觸發
  if APPLY_STATE then return end

  local can_use_cache = (SCAN_CACHE and SCAN_CACHE.sig == sig)

  reaper.Undo_BeginBlock()

  -- Open Console and print header
  reaper.ShowConsoleMsg(string.format("=== Renaming %d item(s) ===\n", total))

  APPLY_STATE = {
    items         = items,
    total         = total,
    can_use_cache = can_use_cache,
    i             = 1,
    counter       = 1,
    renamed       = 0,
    noted         = 0,
    skipped       = 0,
    rows          = {},
    skipped_rows  = {},
  }

  reaper.defer(apply_renaming_step)
end


-- ===== UI: token row =====
local function draw_token_row()
  local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
  local x_used, pad, safety = 0, 14, 28
  for i, tk in ipairs(TOKEN_LIST) do
    local tw = select(1, reaper.ImGui_CalcTextSize(ctx, tk)) + pad
    if i > 1 and (x_used + tw) <= (avail_w - safety) then
      reaper.ImGui_SameLine(ctx); x_used = x_used + tw
    else
      x_used = tw
    end
    if reaper.ImGui_SmallButton(ctx, tk) then append_token(tk) end
  end
end


-- CollapsingHeader state persistence (saved via ExtState across sessions)
local _SECT_EXT   = "hsuanice_RenameMetadata_v1"
local _sect_state = {}
local _sect_init  = {}
for _, k in ipairs({"tokens","renamer","take_presets","history","note_presets"}) do
  local v = reaper.GetExtState(_SECT_EXT, k)
  _sect_state[k] = (v == "1")
end

local function section_header(label, key)
  if not _sect_init[key] then
    reaper.ImGui_SetNextItemOpen(ctx, _sect_state[key] or false)
    _sect_init[key] = true
  end
  local open = reaper.ImGui_CollapsingHeader(ctx, label)
  if open ~= (_sect_state[key] or false) then
    _sect_state[key] = open
    reaper.SetExtState(_SECT_EXT, key, open and "1" or "0", true)
  end
  return open
end


-- ===== Left panel =====
local function push_orange_theme()
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFF0D8FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextDisabled(), 0xFFB98BFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x1F120EFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x2A1610FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x4A2318FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x5D2B1AFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0x6F311DFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF5B6F8C)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF4F6580)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF445972)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0xFF4F3B5C)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0xFF5E4A6D)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), 0xFF3F314B)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Separator(), 0xFF4C3654)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFF3C2945)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x170D12FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), 0x2A1510FF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(), 0xFF8A4DFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), 0xFFA05EFF)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(), 0xFF7A3DFF)
end

local function pop_orange_theme()
  for _ = 1, 20 do
    reaper.ImGui_PopStyleColor(ctx)
  end
end

local function draw_left_panel()
  -- Source file template (prominent: colored label + taller input box + warm amber bg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFCC55FF)
  reaper.ImGui_Text(ctx, "Source File Name")
  reaper.ImGui_PopStyleColor(ctx)
  reaper.ImGui_SameLine(ctx); reaper.ImGui_TextDisabled(ctx, "(template for the actual source file name)")
  reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
  if focus_take_input then reaper.ImGui_SetKeyboardFocusHere(ctx); focus_take_input = false end
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 6, 8)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x332B08FF)
  local changed_take, new_take = reaper.ImGui_InputText(ctx, "##take_name_tpl", TAKE_TEMPLATE)
  reaper.ImGui_PopStyleColor(ctx)
  reaper.ImGui_PopStyleVar(ctx)
  if reaper.ImGui_IsItemActive(ctx) then active_box = "take" end
  if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0) then
    local mx, _ = reaper.ImGui_GetMousePos(ctx); local rx, _ = reaper.ImGui_GetItemRectMin(ctx)
    local relx = mx - rx - 6; local raw = utf8_index_from_x(ctx, TAKE_TEMPLATE, relx)
    caret_take_char = snap_caret_out_of_token(TAKE_TEMPLATE, raw)
    caret_take_char = snap_caret_out_of_word(TAKE_TEMPLATE, caret_take_char, "right")
  end
  if changed_take then TAKE_TEMPLATE = new_take end

  -- Skip-if-empty toggle (Take-only)
  local chg_skip_empty, val_skip_empty = reaper.ImGui_Checkbox(ctx, "Skip rename if any token empty", SKIP_EMPTY_TOKENS)
  if chg_skip_empty then
    SKIP_EMPTY_TOKENS = val_skip_empty
    save_skip_empty_tokens(val_skip_empty)
  end

  -- Source template tools (Clear / Save / Default / Original)
  if reaper.ImGui_SmallButton(ctx, "Clear##take") then
    TAKE_TEMPLATE = "$srcfile"
    focus_take_input = true
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Save##take") then
    save_defaults(TAKE_TEMPLATE, NOTE_TEMPLATE)
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Default##take") then
    local tdef, ndef = load_defaults()
    TAKE_TEMPLATE = tdef
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Original##take") then
    TAKE_TEMPLATE = "$origsrcfile"
    focus_take_input = true
  end

  -- Template Tokens (collapsible, state persisted)
  if section_header("Template Tokens", "tokens") then
    draw_token_row()
  end

  -- Replace Rules (collapsible, state persisted)
  if section_header("Replace Rules", "renamer") then
    reaper.ImGui_TextDisabled(ctx, "(applies after tokens & filter; Note unaffected)")
    reaper.ImGui_TextDisabled(ctx, "Tip: Turn on RegEx for pattern mode (e.g. render \\d+). When off, Find is literal text.")
    local chgEn, en = reaper.ImGui_Checkbox(ctx, "Enable##takeren", TAKE_RENAMER.enable or false)
    if chgEn then
      TAKE_RENAMER.enable = en
      save_take_renamer(TAKE_RENAMER)
    end
    reaper.ImGui_SameLine(ctx)
    local chgRe, reMode = reaper.ImGui_Checkbox(ctx, "RegEx##takeren_regex", TAKE_RENAMER.regex or false)
    if chgRe then
      TAKE_RENAMER.regex = reMode
      save_take_renamer(TAKE_RENAMER)
    end
    local take_tpl_trim = tostring(TAKE_TEMPLATE or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if take_tpl_trim == "" and TAKE_RENAMER.enable and TAKE_RENAMER.rules and #TAKE_RENAMER.rules > 0 then
      reaper.ImGui_TextDisabled(ctx, "Template is empty, auto-using $srcfile for rule processing.")
    end

    if reaper.ImGui_SmallButton(ctx, "+ Add replace rule##takeren_add_top") then
      local rules = TAKE_RENAMER.rules or {}
      rules[#rules+1] = { from = "", to = "" }
      TAKE_RENAMER.rules = rules
      save_take_renamer(TAKE_RENAMER)
    end
    local rules = TAKE_RENAMER.rules or {}
    local tblFlags = TF('ImGui_TableFlags_Borders') | TF('ImGui_TableFlags_RowBg')
    if reaper.ImGui_BeginTable(ctx, "TakeRenRules", 3, tblFlags) then
      reaper.ImGui_TableSetupColumn(ctx, "Find", TF('ImGui_TableFlags_None')|TF('ImGui_TableColumnFlags_WidthStretch'), 0.48)
      reaper.ImGui_TableSetupColumn(ctx, "Replace",   TF('ImGui_TableFlags_None')|TF('ImGui_TableColumnFlags_WidthStretch'), 0.48)
      reaper.ImGui_TableSetupColumn(ctx, "",     TF('ImGui_TableFlags_None')|TF('ImGui_TableColumnFlags_WidthFixed'),   60)
      reaper.ImGui_TableNextRow(ctx, TF('ImGuiTableRowFlags_Headers'))
      reaper.ImGui_TableSetColumnIndex(ctx, 0)
      reaper.ImGui_Text(ctx, "Find")
      reaper.ImGui_TableSetColumnIndex(ctx, 1)
      reaper.ImGui_Text(ctx, "Replace")
      reaper.ImGui_TableSetColumnIndex(ctx, 2)
      do
        local label = "Clear All"
        local w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
        local t = reaper.ImGui_CalcTextSize(ctx, label)
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + math.max(0, (w - t) * 0.5))
        if reaper.ImGui_SmallButton(ctx, label.."##takeren_clear") then
          TAKE_RENAMER.rules = {}
          save_take_renamer(TAKE_RENAMER)
        end
      end
      for i=#rules,1,-1 do
        local row = rules[i]
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableSetColumnIndex(ctx, 0)
        reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
        local chgF, vF = reaper.ImGui_InputText(ctx, ("##ren_from_%d"):format(i), row.from or "")
        if chgF then
          row.from = vF; save_take_renamer(TAKE_RENAMER)
        end
        reaper.ImGui_TableSetColumnIndex(ctx, 1)
        reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
        local chgT, vT = reaper.ImGui_InputText(ctx, ("##ren_to_%d"):format(i), row.to or "")
        if chgT then
          row.to = vT; save_take_renamer(TAKE_RENAMER)
        end
        reaper.ImGui_TableSetColumnIndex(ctx, 2)
        if reaper.ImGui_SmallButton(ctx, ("-##delren_%d"):format(i)) then
          table.remove(rules, i); save_take_renamer(TAKE_RENAMER)
        end
      end
      reaper.ImGui_EndTable(ctx)
    end
  end

  -- Presets (collapsible, state persisted)
  if section_header("Presets", "take_presets") then
    draw_preset_row("Presets", TAKE_PRESETS,
      function(i)
        local v = TAKE_PRESETS[i] or ""
        if v ~= "" then
          TAKE_TEMPLATE = v
          focus_take_input = true
        end
      end,
      function(i)
        TAKE_PRESETS[i] = TAKE_TEMPLATE or ""
        save_presets(TAKE_PRESETS_KEY, TAKE_PRESETS)
      end,
      true
    )
  end

  if section_header("History", "history") then
    reaper.ImGui_TextDisabled(ctx, "(stores up to 10 recent Source File Name templates after Preview or Apply)")
    if reaper.ImGui_SmallButton(ctx, "Clear All##take_history_clear") then
      TAKE_TEMPLATE_HISTORY = {}
      save_recent_list(TAKE_HISTORY_KEY, TAKE_HISTORY_LIMIT, TAKE_TEMPLATE_HISTORY)
    end
    local tbl_flags = TF('ImGui_TableFlags_SizingFixedFit') | TF('ImGui_TableFlags_BordersInnerV')
    if reaper.ImGui_BeginTable(ctx, "TakeTemplateHistoryTable", 2, tbl_flags) then
      reaper.ImGui_TableSetupColumn(ctx, "", TF('ImGui_TableColumnFlags_WidthFixed'), 32)
      reaper.ImGui_TableSetupColumn(ctx, "", TF('ImGui_TableColumnFlags_WidthStretch'))
      if #TAKE_TEMPLATE_HISTORY == 0 then
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_TextDisabled(ctx, "-")
        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_TextDisabled(ctx, "No history yet.")
      else
        for i, v in ipairs(TAKE_TEMPLATE_HISTORY) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableNextColumn(ctx)
          reaper.ImGui_TextDisabled(ctx, ("H%d"):format(i))
          reaper.ImGui_TableNextColumn(ctx)
          local avail = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
          local preview = ellipsize_to_width(ctx, v, avail - 6)
          if reaper.ImGui_SmallButton(ctx, preview .. "##take_hist_" .. i) then
            TAKE_TEMPLATE = v
            focus_take_input = true
          end
          if reaper.ImGui_IsItemHovered(ctx) and preview ~= v then
            reaper.ImGui_BeginTooltip(ctx)
            reaper.ImGui_Text(ctx, v)
            reaper.ImGui_EndTooltip(ctx)
          end
        end
      end
      reaper.ImGui_EndTable(ctx)
    end
  end

end


-- ===== Top bar =====
local function draw_top_bar()
  local full_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))

  -- Undo / Redo
  if reaper.ImGui_Button(ctx, "Undo", 70, 0) then reaper.Undo_DoUndo2(0) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Redo", 70, 0) then reaper.Undo_DoRedo2(0) end

  -- Apply / Cancel (right-aligned)
  local btn_total = 150 + 150 + 8
  local right_off = full_w - btn_total
  if right_off > (70 + 70 + 16) then
    reaper.ImGui_SameLine(ctx, right_off)
  else
    reaper.ImGui_NewLine(ctx)
  end
  if reaper.ImGui_Button(ctx, "Apply", 150, 0) then apply_renaming() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Cancel", 150, 0) then close_after_apply = true end

  -- Status + Preview first (second row)
  local nsel = reaper.CountSelectedMediaItems(0)
  local scanned = (SCAN_CACHE and #SCAN_CACHE.list) or 0
  local _, sig = get_selected_items_and_sig()
  local cached_ok = (SCAN_CACHE and SCAN_CACHE.sig == sig)
  reaper.ImGui_TextDisabled(ctx, string.format("Selected: %d   Scanned: %d   %s",
    nsel, scanned, cached_ok and "Cached: Yes" or "Cached: No"))
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, "  Preview first")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_SetNextItemWidth(ctx, 80)
  local chg, n = reaper.ImGui_InputInt(ctx, "##preview_limit", preview_limit)
  if chg then
    preview_limit = math.max(1, math.min(10000, n or preview_limit))
  end

  -- Options button (font size + docking)
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Options \xe2\x96\xbe##opts_btn") then
    reaper.ImGui_OpenPopup(ctx, "##opts_popup")
  end
  if reaper.ImGui_BeginPopup(ctx, "##opts_popup") then
    -- Docking toggle
    local dock_l = ALLOW_DOCKING and ">> Allow Docking" or "   Allow Docking"
    if reaper.ImGui_Selectable(ctx, dock_l, false) then
      ALLOW_DOCKING = not ALLOW_DOCKING
      reaper.SetExtState(EXT_NS, "allow_docking", ALLOW_DOCKING and "1" or "0", true)
    end
    reaper.ImGui_Separator(ctx)
    -- Font Size submenu
    if reaper.ImGui_BeginMenu(ctx, "Font Size") then
      local sizes = {
        { label = "75%",            s = 0.75 },
        { label = "100% (Default)", s = 1.0  },
        { label = "125%",           s = 1.25 },
        { label = "150%",           s = 1.5  },
        { label = "175%",           s = 1.75 },
        { label = "200%",           s = 2.0  },
      }
      for _, sz in ipairs(sizes) do
        local is_cur = math.abs((FONT_SCALE or 1.0) - sz.s) < 0.01
        local lbl = (is_cur and ">> " or "   ") .. sz.label
        if reaper.ImGui_Selectable(ctx, lbl, false) then
          FONT_SCALE = sz.s
          set_font_size(math.floor(13 * FONT_SCALE))
          reaper.SetExtState(EXT_NS, "font_scale", tostring(FONT_SCALE), true)
        end
      end
      reaper.ImGui_EndMenu(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

function draw_preset_row(label, presets, on_load_click, on_save_click, hide_label)
  if not hide_label then
    reaper.ImGui_TextDisabled(ctx, "(click row to load; Save to store current)")
  end
  -- Vertical layout: one row per preset slot (P# label | content button | Save button)
  local tbl_flags = TF('ImGui_TableFlags_SizingFixedFit') | TF('ImGui_TableFlags_BordersInnerV')
  if reaper.ImGui_BeginTable(ctx, label.."##preset_table", 3, tbl_flags) then
    reaper.ImGui_TableSetupColumn(ctx, "",  TF('ImGui_TableColumnFlags_WidthFixed'), 28)  -- "Pn"
    reaper.ImGui_TableSetupColumn(ctx, "",  TF('ImGui_TableColumnFlags_WidthStretch'))     -- content
    reaper.ImGui_TableSetupColumn(ctx, "",  TF('ImGui_TableColumnFlags_WidthFixed'), 46)  -- "Save"
    for i = 1, PRESET_SLOTS do
      reaper.ImGui_TableNextRow(ctx)
      -- Col 0: slot label
      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_TextDisabled(ctx, ("P%d"):format(i))
      -- Col 1: load button showing content preview
      reaper.ImGui_TableNextColumn(ctx)
      local raw = (presets[i] or ""):gsub("[%c\r\n]", " ")
      local show = (raw ~= "" and raw or "(empty)")
      reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
      local avail = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
      local preview = ellipsize_to_width(ctx, show, avail - 6)
      local load_btn = ("%s##%s_load_%d"):format(preview, label, i)
      if reaper.ImGui_SmallButton(ctx, load_btn) then on_load_click(i) end
      if raw ~= "" and reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx); reaper.ImGui_Text(ctx, raw); reaper.ImGui_EndTooltip(ctx)
      end
      -- Col 2: save button
      reaper.ImGui_TableNextColumn(ctx)
      local save_btn = ("Save##%s_save_%d"):format(label, i)
      if reaper.ImGui_SmallButton(ctx, save_btn) then on_save_click(i) end
    end
    reaper.ImGui_EndTable(ctx)
  end
end


-- ===== Detected fields panel =====
local function draw_fields_panel()
  reaper.ImGui_Text(ctx, "Detected fields (from FIRST currently-selected item):")
  reaper.ImGui_Separator(ctx)
  local first = reaper.GetSelectedMediaItem(0, 0)
  if not first then
    reaper.ImGui_TextDisabled(ctx, "No items selected. Click 'Get Metadata' above or just Apply.")
    left_copy_text = ""
  else
    local f = collect_metadata_for_item(first)
    left_copy_text = build_left_copy_text_from_fields(f)

    do
      local label = "$trk"
      if reaper.ImGui_SmallButton(ctx, label .. "##field") then append_token(label) end
      reaper.ImGui_SameLine(ctx)
      if not f.__diag_interleave then compute_interleave_diag(f, f.__item or first) end
      local diag = f.__diag_interleave or {}
      local out = (diag.name and diag.name ~= "" and diag.name) or "(auto)"
      if diag.index and diag.total then
        out = string.format("%s (interleave %d/%d)", out, diag.index, diag.total)
      end
      reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
      reaper.ImGui_InputText(ctx, "##fv_trk", out, reaper.ImGui_InputTextFlags_ReadOnly())
    end

    do
      local label = "$trkall"
      if reaper.ImGui_SmallButton(ctx, label .. "##field") then append_token(label) end
      reaper.ImGui_SameLine(ctx)
      if not f.__diag_interleave then compute_interleave_diag(f, f.__item or first) end
      local all = (f.__diag_interleave and f.__diag_interleave.all) or ""
      reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
      reaper.ImGui_InputText(ctx, "##fv_trkall", all, reaper.ImGui_InputTextFlags_ReadOnly())
    end

    do
      local label = "$curtake"
      if reaper.ImGui_SmallButton(ctx, label .. "##field") then append_token(label) end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
      reaper.ImGui_InputText(ctx, "##fv_curtake", tostring(f.curtake or ""), reaper.ImGui_InputTextFlags_ReadOnly())
    end

    reaper.ImGui_Separator(ctx)

    local ordered = {
      "origsrcfile",
      "project","scene","take","tape","track",
      "filename","srcfile","srcbase","srcext","srcpath","srcdir","filepath",
      "samplerate","channels","length",
      "date","time","year","originationdate","originationtime","startoffset",
      "framerate","speed","ubits","originator","originatorreference",
      "umid","umid_pt",
      "timereference",
      "trk1","trk2","trk3","trk4","trk5","trk6","trk7","trk8","trk9","trk10",
      "trk11","trk12","trk13","trk14","trk15","trk16",
      "description"
    }
    for _,k in ipairs(ordered) do if f[k] ~= nil then field_row_token(k, f[k]) end end
  end
end


-- ===== Preview panel =====
local function draw_preview_panel()
  -- Action row: left = Get/Update Metadata + Clear; right = Copy TSV + Copy CSV
  local panel_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
  local tsv_w = select(1, reaper.ImGui_CalcTextSize(ctx, "Copy TSV")) + 14
  local csv_w = select(1, reaper.ImGui_CalcTextSize(ctx, "Copy CSV")) + 14
  local copy_total_w = tsv_w + csv_w + 8

  local meta_label = SCAN_CACHE and "Update Preview##getmeta_prev" or "Get Preview##getmeta_prev"
  if reaper.ImGui_SmallButton(ctx, meta_label) then scan_metadata() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Clear##clearprev") then
    SCAN_CACHE = nil
    preview_rows = {}
    right_copy_text = ""
    status_msg = ""
  end

  local right_x = panel_w - copy_total_w
  local cur_x = select(1, reaper.ImGui_GetCursorPosX(ctx))
  if right_x > cur_x + 8 then
    reaper.ImGui_SameLine(ctx, right_x)
  else
    reaper.ImGui_SameLine(ctx)
  end
  if reaper.ImGui_SmallButton(ctx, "Copy TSV##copytable") then
    reaper.ImGui_SetClipboardText(ctx, build_right_copy_text_from_rows("tsv") or "")
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Copy CSV##copytable") then
    reaper.ImGui_SetClipboardText(ctx, build_right_copy_text_from_rows("csv") or "")
  end
  reaper.ImGui_Separator(ctx)

  if RIGHT_SELECTABLE_VIEW then
    right_copy_text = build_right_copy_text_from_rows(right_copy_fmt)
    if reaper.ImGui_Button(ctx, "Copy preview table", 200, 0) then reaper.ImGui_SetClipboardText(ctx, right_copy_text or "") end
    reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
    reaper.ImGui_InputTextMultiline(ctx, "##right_sel_view", right_copy_text or "", -FLT_MIN, -FLT_MIN, reaper.ImGui_InputTextFlags_ReadOnly())
  else
    local prevFlags = TF('ImGui_TableFlags_Borders') | TF('ImGui_TableFlags_RowBg')
    if reaper.ImGui_BeginTable(ctx, "PreviewTable", 4, prevFlags) then
      reaper.ImGui_TableSetupColumn(ctx, "#", TF('ImGui_TableColumnFlags_WidthFixed'), 36)
      reaper.ImGui_TableSetupColumn(ctx, "Current Source File")
      reaper.ImGui_TableSetupColumn(ctx, "New Source File")
      reaper.ImGui_TableSetupColumn(ctx, "Rename History")
      reaper.ImGui_TableHeadersRow(ctx)
      if not SCAN_CACHE or #preview_rows == 0 then
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "-")
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "No cache. Click 'Get Metadata'.")
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "")
        reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "")
      else
        for i, row in ipairs(preview_rows) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(i))
          reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, row.current ~= "" and row.current or "(unnamed)")
          reaper.ImGui_TableNextColumn(ctx)
          if row.will_skip then
            reaper.ImGui_TextWrapped(ctx, "(will skip)")
          else
            reaper.ImGui_TextWrapped(ctx, row.newname ~= "" and row.newname or "(unchanged)")
          end
          reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, row.history_preview or "(no history)")
        end
      end
      reaper.ImGui_EndTable(ctx)
    end
  end
end


-- ===== Main loop =====
local function loop()
  -- Push font if scaled (must happen before ImGui_Begin)
  font_pushed_this_frame = false
  if current_font_size ~= 13 and reaper.ImGui_PushFont then
    local ok_font = pcall(reaper.ImGui_PushFont, ctx, nil, current_font_size)
    if ok_font then font_pushed_this_frame = true end
  end

  reaper.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H, reaper.ImGui_Cond_FirstUseEver())
  local wnd_flags = TF('ImGui_WindowFlags_NoScrollbar')
  if not ALLOW_DOCKING then
    local no_dock = TF('ImGui_WindowFlags_NoDocking')
    if no_dock ~= 0 then wnd_flags = wnd_flags | no_dock end
  end
  local visible, open = reaper.ImGui_Begin(ctx, 'Rename Source File from Metadata'..LIBVER, true, wnd_flags)
  if visible then
    push_orange_theme()

    -- ESC to Cancel/Close (press Esc anywhere to close the window)
    if reaper.ImGui_IsWindowFocused(ctx, TF('ImGui_FocusedFlags_RootAndChildWindows'))
      and reaper.ImGui_IsKeyPressed(ctx, KEY_ESC, false) then
      close_after_apply = true
    end

    -- Top bar: Undo / Redo / Get Metadata / Apply / Cancel + status
    draw_top_bar()
    reaper.ImGui_Separator(ctx)

    -- 3-pane layout: upper-left (editor) + upper-right (detected fields) + lower (preview)
    local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local split_thickness = 6.0
    local upper_h = math.max(200, math.floor(avail_h * SPLIT_RATIO) - math.floor(split_thickness / 2))
    local lower_h = math.max(100, avail_h - upper_h - split_thickness)

    -- Upper section: left editor + detected fields side by side
    local begun_up = BeginChildSafe("UpperSection", -1, upper_h, false)
    if begun_up then
      local begun_l = BeginChildSafe("LeftPanel", LEFT_PANEL_W, -1, true)
      if begun_l then
        draw_left_panel()
        reaper.ImGui_EndChild(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      local begun_f = BeginChildSafe("FieldsPanel", -1, -1, true)
      if begun_f then
        draw_fields_panel()
        reaper.ImGui_EndChild(ctx)
      end
      reaper.ImGui_EndChild(ctx)
    end

    -- Horizontal splitter (drag to resize upper/lower ratio)
    reaper.ImGui_InvisibleButton(ctx, "HSplit", -1, split_thickness)
    if reaper.ImGui_IsItemActive(ctx) then
      local _, my = reaper.ImGui_GetMousePos(ctx)
      if not _drag_active then
        _drag_active = true
        _last_my = my
      else
        local dy = my - _last_my
        local total = upper_h + lower_h + split_thickness
        if total > 0 then
          SPLIT_RATIO = math.min(0.9, math.max(0.1, SPLIT_RATIO + dy / total))
          save_split_ratio(SPLIT_RATIO)
        end
        _last_my = my
      end
    else
      _drag_active = false
    end

    -- Lower section: preview (full width)
    local begun_prev = BeginChildSafe("PreviewPanel", -1, lower_h, true)
    if begun_prev then
      draw_preview_panel()
      reaper.ImGui_EndChild(ctx)
    end

    -- Draw result modal if needed
    draw_result_modal()

    pop_orange_theme()
    reaper.ImGui_End(ctx)
  end

  -- Pop font (must happen after ImGui_End, always if pushed)
  if font_pushed_this_frame then
    reaper.ImGui_PopFont(ctx)
  end

  if (not open) or close_after_apply then
    -- Flush cache before exit
    CACHE.flush()
    if reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
    return
  else
    reaper.defer(loop)
  end
end

-- Register cache flush on script exit (in case of abnormal termination)
reaper.atexit(function()
  CACHE.flush()
end)

reaper.defer(loop)
