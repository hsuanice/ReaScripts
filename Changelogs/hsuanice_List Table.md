# hsuanice_List Table.lua — Changelog

hsuanice_List Table.lua

## 26.1012.1113

- Released as part of the 26.1012.1113 package update.

History before 26.1012.1113 (moved out of the script header; last header version: `0.2.7`).

```text
v0.2.7
  - Enhancement: TSV export now preserves multiline content in fields
    • Fields containing tabs or newlines are now quoted (like CSV)
    • Allows Description field (BWF metadata) to export with actual newlines
    • TSV output is now a quoted TSV format (RFC 4180 style)
    • Backwards compatible - fields without special chars remain unquoted
    • Excel, Google Sheets, and other tools handle quoted TSV correctly

v0.2.6
  - Fix: Complete rewrite of clipboard copy/paste logic
    • copy_selection():
      - Single column: pure text format (no tabs) → treated as plain text on paste
      - Multiple columns: TSV format (tab-separated) → parsed as multi-column on paste
    • parse_clipboard_table():
      - Content with tabs: parsed as TSV (multi-column table)
      - Content without tabs: each line becomes single cell (preserves all characters)
      - Removed CSV parsing mode entirely (was incorrectly splitting on commas)
    • Fixes all clipboard issues:
      ✓ External text with commas: preserved as single cell
      ✓ External text with spaces: preserved completely
      ✓ ILE single-column copy: no unwanted empty column on paste
      ✓ ILE multi-column copy: correctly pastes all columns
      ✓ Google Sheets paste: works correctly in all cases

v0.2.5
  - Partial fix: Removed CSV parsing mode
    • When no tabs found, treat each line as single cell
    • Fixed external paste but broke internal single-column copy
    • Internal single-column copies still had trailing tabs → created empty columns

v0.2.4
  - Attempted fix: Single-column copy forces TSV format with trailing tabs
    • Added trailing tabs to force TSV detection
    • Incomplete solution - caused unwanted empty column on paste
    • Only worked for preventing CSV parsing, but created new problems

v0.2.2
  - Paste spill now honors VISUAL column order:
    • LT.build_dst_spill_writable(): expands to the right by on-screen order,
      but only into writable columns (3=Track, 4=Take, 5=Item Note).
    • LT.build_dst_by_anchor_and_shape(): expands by visual positions for
      all-columns mapping (many-to-many), keeping row-major order stable.
  - This fixes cases where Take Name and Item Note were swapped: pasting a
    2-column source into a single Take Name cell now spills into the next
    writable column on screen (which is Item Note after the swap).
v0.2.1
  - Added LT.build_dst_spill_writable(): Excel-style spill expansion limited
    to writable columns (3=Track, 4=Take, 5=Item Note).
    • Used by LT.apply_paste() when handling multi-cell sources into a
      single-cell or smaller destination selection.
  - Ensures Editor paste behavior matches previous local implementation.

v0.2.0
  - Add a dispatcher for paste actions
v0.1.0
  - Initial release of hsuanice_List Table library.
  - Provides pure helper functions for Item List Editor (no UI, no REAPER writes).
  - Features:
    • Column order mapping: rebuild_display_mapping()
    • Row index map (GUID → row index)
    • Selection rectangle handling (Shift + click)
    • Copy selection to TSV (visual order)
    • Clipboard parsing (TSV / simple CSV with quotes)
    • Flatten TSV/CSV into 1D list for paste logic
    • Source shape dimensions (rows × columns)
    • Build destination list from selection (row-major, visual order)
    • Spill by anchor & shape (Excel-style), restricted to writable columns (3=Track, 4=Take, 5=Item Note)
    • Export table as TSV/CSV following on-screen column order
```
