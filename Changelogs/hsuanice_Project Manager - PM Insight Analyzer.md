# hsuanice_Project Manager - PM Insight Analyzer.lua — Changelog

(formerly `hsuanice_PM_InsightAnalyzer.lua`)

PM Insight Analyzer


**Removed from ReaPack** (2026-10-15) while it is a work in progress; the script stays in the repository (`@noindex`) as a backup.

## 26.1026.2327pre1

- Change: Progress lists the latest step on top - Scenes finished, Denoise (Edited), Editing (Mic Selected), then Mic select (EDL) at the bottom.

## 26.1026.2314pre1

- Change: Progress Source / Film switch now also switches the lengths - each stage shows 'source done' or 'film done' (done / total) and 'source left' or 'film left' with the estimated work - so the switch is visible even when both percentages happen to round the same.

## 26.1026.2310pre1

- New: Progress card has a Source / Film switch - each stage and Scenes finished as % of the EDL source or of the film of the scenes where it is done, with the scene count in brackets. Default Source; the choice is remembered in the browser.

## 26.1026.2304pre1

- Fix: an ungrouped Mic Selected / Edited item that only touches a scene edge (ends where the next scene starts) was also counted for the next scene, because of a tiny floating-point difference - its muted items made e.g. Denoise done there before Editing. An item must now overlap a scene by more than half a frame (same fix as PM Timer's Shots count).

## 26.1026.2300pre1

- Change: a stage with no items, and no items in any later stage, now counts as done when the scene is muted on Scene Cut - a scene without dialogue no longer stays unfinished.

## 26.1026.2251pre1

- Change: Completion shows two percentages - Film (film of the scenes muted on Scene Cut / all film) and Source (EDL source of the finished scenes, every stage done / all source) - each with done / total and a bar, plus Scenes marked done and Scenes finished.

## 26.1026.2153pre1

- Change: Completion and Work time are one card again. '% done' is now the film of the finished scenes / all film (no time estimate), with Film done, Source done and Scenes done of the total, then the work time and daily figures. Work time no longer shows estimated hours left / total.

## 26.1026.2118pre1

- Change: Overview starts with a Completion card - '% done' with a bar, then Film left, Source left (EDL) and Scenes left, each of the total. The hours (done, Left (est.), Total (est.), daily figures) are in the Work time card next to it. The overview cards are narrower so the five fit in one row (page up to 1400 px wide).

## 26.1026.2053pre1

- Change: the Work time card leads with the overall completion - '% done' with a bar, then Done, Left (est.) and Total (est.) hours and Scenes finished. % done = work done / (work done + estimated work left, the same estimate as in Progress); by finished scenes when there is no estimate yet.

## 26.1025.2139pre1

- New: Work Log mode (no Scene Cut track) is now the same kind of HTML report instead of the gfx window: overview (Total Work - was 'Year total work' -, items, days, daily average, projects), a year filter, By Month, By Project (click a project for its tasks, work types and sessions), By Work Type / Task / Day.
- Change: work type and task names that differ only in upper / lower case are merged (Scene / scene, Export / EXPORT); the older Chinese name for mic select counts as mic select; a task's save-copy suffix (Conform_001) is ignored.
- Fix: duplicate work log items (same day, position and length - a copy of a project synced to the Work Log too) are counted once; the report says how many were skipped.
- Fix: the work type is read from the last part of the item name - items with a stacked project prefix showed a project name as their work type.

## 26.1025.1501pre1

- Change: a scene is finished when every stage is done (its items muted in EDL / Mic Selected / Edited; skipped stages count). The Scene Cut mute no longer means finished (it is used as a temporary marker); only a project without stage folders still uses it. Efficiency, remaining work and pace follow this.
- Add: Daily progress (open, below the overview) - per day the scenes finished, their film and source, the stages finished (with scenes) and the work hours. A stage counts on the last day its work type was logged on the scene; a scene on the latest of its stage days.
- Change: Plan's source per day per stage reads like the pace table (12m 25s instead of 00:12:24:21).

## 26.1025.1403pre1

- Change: Plan's source per day per stage reads like the pace table (12m 25s instead of 00:12:24:21).

## 26.1025.1402

- Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
- Change: efficiency counts finished content only - film / EDL source of the scenes marked done on Scene Cut (muted, with logged work) per hour of all the work on them.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted, when a later stage already has items (skipped), or when the scene is marked done. Remaining EDL source and estimated work per stage, from the rates of finished stages.
- Add: plan from PM Timer's target hours, delivery date and work hours per day (default 5) - days left, hours used / left, hours per day, whether the estimated work fits, working days needed and finish date, source per day per stage.
- Add: pace needed - source and film left per day and per hour, for the days left at the work hours per day, next to the pace of the finished scenes (✓, or ⚠ ×N).
- Change: Source/hr always uses the EDL source.
- Release: tested in REAPER 7.82.

## 26.1025.1401pre1

- Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
- Change: efficiency counts finished content only - film / EDL source of the scenes marked done on Scene Cut (muted, with logged work) per hour of all the work on them.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted, when a later stage already has items (skipped), or when the scene is marked done. Remaining EDL source and estimated work per stage, from the rates of finished stages.
- Add: plan from PM Timer's target hours, delivery date and work hours per day (default 5) - days left, hours used / left, hours per day, whether the estimated work fits, working days needed and finish date, source per day per stage.
- Add: pace needed - source and film left per day and per hour, for the days left at the work hours per day, next to the pace of the finished scenes (✓, or ⚠ ×N).
- Fix: the pace table (and its header) fits inside the Plan card.
- Change: Source/hr always uses the EDL source.

## 26.1025.1352pre1

- Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
- Change: efficiency counts finished content only - film / EDL source of the scenes marked done on Scene Cut (muted, with logged work) per hour of all the work on them.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted, when a later stage already has items (skipped), or when the scene is marked done. Remaining EDL source and estimated work per stage, from the rates of finished stages.
- Add: plan from PM Timer's target hours, delivery date and work hours per day (default 5) - days left, hours used / left, hours per day, whether the estimated work fits, working days needed and finish date, source per day per stage.
- Add: pace needed - source and film left per day and per hour, for the days left at the work hours per day, next to the pace of the finished scenes (✓, or ⚠ ×N).
- Fix: the pace table fits inside the Plan card.
- Change: Source/hr always uses the EDL source.

## 26.1025.1347pre1

- Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
- Change: efficiency counts finished content only - film / EDL source of the scenes marked done on Scene Cut (muted, with logged work) per hour of all the work on them.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted, when a later stage already has items (skipped), or when the scene is marked done. Remaining EDL source and estimated work per stage, from the rates of finished stages.
- Add: plan from PM Timer's target hours, delivery date and work hours per day (default 5) - days left, hours used / left, hours per day, whether the estimated work fits, working days needed and finish date, source per day per stage.
- Add: pace needed - source and film left (scenes not marked done) per day and per hour, for the days left at the work hours per day, next to the pace of the finished scenes (✓, or ⚠ ×N when N times faster is needed).
- Change: Source/hr always uses the EDL source.

## 26.1025.1333pre1

- Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
- Change: efficiency counts finished content only - film / EDL source of the scenes marked done on Scene Cut (muted, with logged work) per hour of all the work on them.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted, when a later stage already has items (skipped), or when the scene is marked done. Remaining EDL source and estimated work per stage, from the rates of finished stages.
- Add: plan from PM Timer's target hours, delivery date and work hours per day (default 5) - days left, hours used / left, hours per day (as part of a working day), whether the estimated work fits, how many working days it takes and when it would be done, hours available to the delivery, source per day per stage.
- Change: Source/hr always uses the EDL source.

## 26.1025.1322pre1

- Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
- Change: efficiency counts finished content only - film / EDL source of the scenes marked done on Scene Cut (muted, with logged work) per hour of all the work on them; unfinished scenes no longer make it look better.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted, when a later stage already has items (skipped), or when the scene is marked done. Remaining EDL source and estimated work per stage, from the rates of finished stages.
- Add: plan from PM Timer's target hours and delivery date - days left, hours used / left, hours per day, whether the estimated work fits, source per day per stage.
- Change: Source/hr always uses the EDL source.

## 26.1025.1313pre1

- Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
- Change: efficiency = the whole film / the whole EDL source per hour of ALL work (every work type and work without a scene); the per work type rates stay for the estimates.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted; a stage with no items is done when a later stage already has items (skipped). Remaining EDL source and estimated work hours per stage.
- Add: plan from PM Timer's target hours and delivery date - days left, hours used / left, hours per day, whether the estimated work fits, source per day per stage.
- Change: Source/hr always uses the EDL source.

## 26.1025.1249pre1

- Change: the report opens with an overview of the four questions - work time (total, working days, typical day, last 7 days), efficiency (film / EDL source per hour), progress by stage and plan; the detailed tables are collapsed below.
- Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): a stage is done for a scene when all its items there are muted; a stage with no items is done when a later stage already has items (skipped), else not done. Remaining EDL source and estimated work hours per stage.
- Add: plan from PM Timer's target hours and delivery date - days left, hours used / left, hours per day, whether the estimated work fits, source per day per stage.
- Change: Source/hr always uses the EDL source (not Mic Selected / Edited lengths).

## 26.1025.1235

- Add: select one or more items on the Scene Cut track to report only those scenes - their work time, film length and Source / Mic Selected / Edited; project-wide figures (daily average, work without a scene, Total Time) are left out. Nothing selected = whole project, same report file.
- Release: tested in REAPER 7.82.

## 26.1024.1127pre1

- Add: select one or more items on the Scene Cut track to report only those scenes - their work time, film length and Source / Mic Selected / Edited; project-wide figures (daily average, work without a scene, Total Time) are left out. Nothing selected = whole project, same report file.

## 26.1023.1619pre1

- Change: Project Overview shows the source stages side by side - Source (EDL), Selected (Mic Selected), Edited - each with Total Length, Ratio vs film (of the scenes that have that stage), Kept from previous stage, and Scenes.

## 26.1023.1606pre1

- New: Source/hr per work type uses the source that work starts from - EDL for mic select, Mic Selected ('Sel Len') for editing, Edited ('Edit Len') for denoise; EDL when that stage is missing.
- New: Selected / Edited columns in the scene list and in each scene's detail.

## 26.1023.1405pre1

- New: work items marked by PM Timer > Link Split Scenes have their time shared between the scene pieces by source length (film length if there is no source length).

## 26.1023.1341pre1

- Change: one report per session folder ('<folder name> - PM Insight.html') instead of one per .rpp, so daily .rpp backups in the same folder update the same page; older per-.rpp reports in the folder are removed.

## 26.1020.1601pre1

- New: the Dialog project report is now an HTML page next to the project file ('<project name> - PM Insight.html', replaced on every run) and opened in the web browser; the console only shows the file path.
- New: efficiency (Film/hr, Source/hr) for every work type, e.g. mic select, check, custom types - not only editing and denoise. A work type's rate uses every scene that has that work type.
- New: scene list with one row per scene (time per work type, done mark); click a scene to jump to its detail block.
- Change: each scene's detail is a separate block with a table of only the work types done on it.

## 26.1020.1550pre1

- New: the Dialog project report is now an HTML page saved next to the project file (insight_YYMMDD_HHMMSS.html) and opened in the web browser; the console only shows the file path.
- New: efficiency (Film/hr, Source/hr) for every work type, e.g. mic select, check, custom types - not only editing and denoise. A work type's rate uses every scene that has that work type.
- New: scene list with one row per scene (time per work type, done mark); click a scene to jump to its detail block.
- Change: each scene's detail is a separate block with a table of only the work types done on it.

## 26.1012.1641pre1

- Renamed to "Project Manager - PM Insight Analyzer" (was "PM_InsightAnalyzer") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1358pre1

- First release in the hsuanice/ReaScripts repository.
- Pre-release: work in progress (basic info and time totals so far) — only installed when "Enable pre-releases" is on in ReaPack.
- Requires the SWS extension.

History before 26.1012.1358pre1 (moved out of the script header; last header version: `260729.1217`).

```text
v260729.1217
  - Taipei-time version stamp aligned for this changelog entry.

v260309.2010
  - Both modes: added Working Days count and Avg Daily Work (on working days)
    computed from date-named tracks (YYYY-MM-DD pattern).
  - Avg Daily Work uses trimmed mean (10-90 percentile): excludes the lowest
    and highest 10% of working days to filter out extreme outliers.

v260307.1600
  - Source Length now read from scene item P_NOTES ("Src Len : HH:MM:SS")
    pre-computed by SceneAnalyzer, overriding EDL-attributed values.
    Project source total recomputed as sum of per-scene note-based values.

v260305.0230
  - Unified throughput output format across both modes:
  - Scene Insight — Per Scene: reorganized into three blocks:
      Film Length / Source Length / Source Ratio / Time Summary
      Source Throughput (Editing/Denoise/Total Source/hr)
      Film Throughput  (Editing/Denoise/Total Film/hr)
      Added Denoise Source/hr and Denoise Film/hr per scene.
  - Work Log — "Efficiency" section renamed to "Throughput":
      Shows same three-block structure per Project → Task.
      Film and Source fields show N/A (not available in Work Log).
      Time summary (Editing/Denoise/Total) retained.

v260305.0200
  - Work Log Mode: added "Efficiency" section (Ratio metrics) after Per Project.

v260305.0150
  - Work Log Mode rewrite: removed "Per Scene" and "By Task" blocks; replaced with:
    - "Year Overview": grand total + per-task totals across all projects.
    - "Per Project": Project → Task → Module breakdown.
      Project = first word of item name prefix (e.g. "TheFixer").
      Task    = P_EXT:TASK (preferred) or last word of prefix (e.g. "Dialog").
      Module  = text after the last " | " in the item name.
    Both sections sorted by duration descending.

v260305.0130
  - Work Log Mode: added "By Task" grouping.
  - Work Log Mode: task extracted from P_EXT:TASK or item name fallback.

v260305.0110
  - Work Log Mode: when no "Scene Cut" track is present, the script switches
    to Work Log mode. Item names are parsed as "Proj | Scene | Module" and
    durations are grouped by scene and module.
    - Project Overview shows grand total + per-module totals.
    - Per Scene block shows each scene with module breakdown + scene total.
    - Items with only two parts ("Proj | Module", no scene) are counted as
      project work in the overview but excluded from per-scene output.

v260304.2225
  - Duration source changed to D_LENGTH exclusively; P_EXT:DURATION no longer read.
    Manually stretching a work item now immediately reflects in the analysis.

v260302.2100
  - Removed Efficiency Overview (all-scene efficiency)
  - "Completion-Based Efficiency" renamed to "Efficiency"
  - Efficiency block shows N/A if no completed scenes
  - Output order: Project Overview → Progress → Efficiency → Per Scene

v260302.2000
  - Completion tracking switched from P_EXT:SCENE_DONE to B_MUTE
  - New "Completion-Based Efficiency" block using only done scenes

v260302.1900
  - Progress block, output reorder, Film/Source Length per scene, integer ratios

v260302.1830
  - Initial release
```
