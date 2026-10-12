# hsuanice_Rename from Metadata - Source File.lua — Changelog

(formerly `hsuanice_Rename Source File from Metadata.lua`)

ReaImGui - Rename Source File from Metadata (cached preview + source rename)

## 26.1012.1641

- Renamed to "Rename from Metadata - Source File" (was "Rename Source File from Metadata") as part of the 2026-10-12 naming clean-up.

## 26.1012.1113

- Released as part of the 26.1012.1113 package update.

History before 26.1012.1113 (moved out of the script header; last header version: `260911.1302`).

```text
v260911.1302 (Taipei Time)
  - Cleanup: removed a pre-existing dead-code trap — local guess_channel_index()
    (and the get_source_num_channels() it alone called) had a full I_CHANMODE-based
    implementation defined early, but every call site actually ran later at
    runtime, by which point a bare "guess_channel_index = function(...) return
    META.guess_interleave_index(...) end" reassignment (no 'local') had already
    silently overwritten it — so the local body never executed. Removed the dead
    body; guess_channel_index is now forward-declared (matching expand_template's
    existing pattern) and defined once, delegating to the library. No behavior
    change (the delegating version was already the only one actually running).

v260911.1056 (Taipei Time)
  - Refactored: $trk, $trkN, $trkall, $interleave/$interum, $chnum/$channelnum,
    $counter:N, $srcbaseprefix:N/$srcbasesuffix:N no longer duplicate their
    own local implementation — they now delegate to the shared "hsuanice
    Metadata Read" library (Metadata Read >= 0.3.10, adds M.resolve_trk_name),
    the same library "Rename Active Take from File Metadata.lua" uses. Removed the
    now-unused local build_interleave_name_list()/get_current_interleave_index()/
    get_recorder_channel_number() and the dead pre-library copy of
    compute_interleave_diag() that only these fed. $baseindex/$baseidx and
    $overlapindex/$rangeindex stay local (they depend on this UI's current
    selection/grouping state, which the metadata library has no concept of).
    No output change intended beyond the meta_trk_name-first fix below.

v260910.2332 (Taipei Time)
  - Fixed: $trk resolved to empty (causing false "will skip" / blank output) for items whose
    metadata came from the shared Metadata.cache after a cache hit, when the recorder's iXML
    description does not embed per-channel "TRK#=" pairs (e.g. Cantar/Aaton poly files).
    • $trk now trusts the already-resolved fields.meta_trk_name first (same value the shared
      cache and Item List Editor already carry for that channel), instead of only ever
      reconstructing the name by re-parsing TRK# tokens out of the description text.
    • Falls back to the previous interleave-list reconstruction when meta_trk_name is empty
      (e.g. very first scan before any cache exists), so behavior for other recorders is unchanged.

v260823.1355 (Taipei Time)
  - Apply progress: processing now runs one-by-one (1 item per defer step), so Console progress updates per item instead of per 50-item batch.
  - Persistence scope: moved this script to its own ExtState namespace so input fields, presets, and section states are isolated from other rename scripts.

v2026.08.21 (Taipei Time)
  - New: Added $marker token — nearest project marker at/before the item start (same semantics as REAPER's own render wildcard), for non-metadata channel/scene naming workflows.
  - UI: Template Tokens row is now split into two color-coded groups: "REAPER / Session" (e.g. $track, $marker, $srcfile, counters) vs "File Metadata (BWF/iXML)" (e.g. $scene, $trk, $umid), so file-embedded metadata tokens are visually distinct from REAPER/session-derived ones.

v2026.08.17 (Taipei Time)
  - New: Added $overlapindex (with $rangeindex alias) for a pure time-overlap-based numbering mode.
  - Perf: Preview/index generation now groups selected items by overlap range and track order for fast sequential numbering.
  - UX: Keeps $baseindex behavior intact while adding a much faster metadata-free option for large batches.

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
```
