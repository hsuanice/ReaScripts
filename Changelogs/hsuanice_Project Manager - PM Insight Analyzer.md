# hsuanice_Project Manager - PM Insight Analyzer.lua — Changelog

(formerly `hsuanice_PM_InsightAnalyzer.lua`)

PM Insight Analyzer


**Removed from ReaPack** (2026-10-15) while it is a work in progress; the script stays in the repository (`@noindex`) as a backup.

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
