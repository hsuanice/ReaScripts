# hsuanice_Hover Mode Split Item by Selection or Edit or Mouse Cursor.lua — Changelog

Hover Mode - Split Items (Selection-first in Hover, Mouse/Edit aware) + Simple Debug Switch

## 26.1012.0736

- Released as part of the 26.1012.0736 package update.

History before 26.1012.0736 (moved out of the script header; last header version: `0.2.4`).

```text
v0.2.4
  - Fix: When both a Time Selection and a single selected item existed with no overlap, the first run would clear the selection without splitting.
          Now the Time Selection branch runs only if at least one selected item overlaps the TS range; otherwise it falls through to the Hover/Edit path.
  - Logging: Added debug output showing the Time Selection overlap count.
  - No other changes: Razor priority, IGNORE_TIME_SELECTION, hover behavior, selection-sync threshold (≥2), and “preserve both halves of originally selected items” remain unchanged.
v0.2.3 - Hover selection-sync requires >=2 selected items; single selection behaves like no-selection.
v0.2.2
  - True Hover: When selection exists, also split the item under mouse if it's outside selection but crosses the time.
v0.2.1.1
  - Preserve original selection across split (both halves stay selected for originally-selected items).
v0.2.1
  - USER OPTION `IGNORE_TIME_SELECTION`.
v0.2.0
  - Use Action 40757 for splitting; integrated hover library and forced redraw.
```
