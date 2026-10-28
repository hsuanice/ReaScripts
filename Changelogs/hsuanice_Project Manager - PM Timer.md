# hsuanice_Project Manager - PM Timer.lua — Changelog

(formerly `hsuanice_PM_Timer.lua`)

PM Timer - Scene-aware Work Timer


**Removed from ReaPack** (2026-10-15) together with PM Insight Analyzer; the script stays in the repository (`@noindex`) as a backup.

## 26.1028.1257pre1

- New: project master list 'PM Projects.txt' next to the Work Log project (created and updated by PM Timer): one line per project, official name = older spellings. The project name in the .rpp file name is looked up there (any case) and replaced by the official name in all work item names; the choice is saved in the project, so daily save-as copies keep it.
- New: a project name that is not in the list asks once which project this is - add it as a new project (as written or typed) or pick an existing one; the file-name spelling then becomes an alias. Right-click > Project Name... changes it later. The first time, PM Timer asks where Work Log.RPP is (or remembers it from an open Work Log tab / Sync).
- Change: the window shows the official project name before the mode (e.g. 'POINT · Dialog'), and the task in item names is always Conform / AAP / Dialog (e.g. 'dialog' becomes 'Dialog').

## 26.1026.2333pre1

- Change: the original source folder is now called ISO; a project whose folder is still called EDL keeps working (Src Len, Src Cnt and the project-scope note read 'ISO', else 'EDL').

## 26.1025.1402

- Add: target box at the top right - click to set the target work hours, the delivery date and the work hours per day (default 5; saved in the project; PM Insight Analyzer plans with them). Shows the days to delivery and the hours left of the target (live while the timer runs), e.g. 'Due 11-02 · 8d · 45.6h left'.
- Change: compact buttons (26 px instead of 40 px high, smaller font) and a lower window, so the whole timer fits in a short dock.
- Release: tested in REAPER 7.82.

## 26.1025.1333pre1

- Add: target box at the top right - click to set the target work hours, the delivery date and the work hours per day (default 5; saved in the project; PM Insight Analyzer plans with them). Shows the days to delivery and the hours left of the target (live while the timer runs), e.g. 'Due 11-02 · 8d · 45.6h left'.
- Change: compact buttons (26 px instead of 40 px high, smaller font) and a lower window, so the whole timer fits in a short dock.

## 26.1025.1313pre1

- Add: target box at the top right - click to set the target work hours and the delivery date (saved in the project; PM Insight Analyzer plans with them). Shows the days to delivery and the hours LEFT of the target (target minus the work logged so far, live while the timer runs), e.g. 'Due 11-02 · 8d · 45.6h left'.
- Change: compact buttons (26 px instead of 40 px high, smaller font) and a lower window, so the whole timer fits in a short dock.

## 26.1025.1249pre1

- Add: target box at the top right - click to set the target work hours and the delivery date (saved in the project; PM Insight Analyzer plans with them). Shows e.g. 'Due 11-15 · 21d · 120h'.
- Change: compact buttons (26 px instead of 40 px high, smaller font) and a lower window, so the whole timer fits in a short dock.

## 26.1023.1606pre1

- New: scene notes get 'Sel Len' and 'Edit Len' - the source left in the 'Mic Selected' and 'Edited' folders (only when the folder exists). An item in the scene's item group counts in full; any other item counts with the part inside the scene range, so no linking is needed. The EDL 'Src Len' is unchanged.

## 26.1023.1405pre1

- New: right-click > Link Split Scenes - for a scene split on Scene Cut after work was logged: select all its pieces and run it; PM Insight then shares that work time between the pieces by source length. Run it with ONE scene selected to undo.

## 26.1020.1529

- Fix: work item names stacked an outdated project prefix after the project was renamed (e.g. 'POINT R5 dialog | POINT R5 dialog_001 | POINT R5 dialog | scene'); names are now rebuilt as current prefix + work type, which also repairs existing items.
- Fix: a work item renamed by hand was renamed back on the next start; the new name now becomes the item's work type (and its color follows).

## 26.1020.1454pre1

- New: Dialog work types 'mic select' (pick the needed mic channels, rough levels, spot possible ADR) and 'check' (final overall check).
- New: names typed via 'custom' are remembered per work mode (shared by all projects) and listed in the menu next time; 'remove custom...' deletes one.
- New: every work type gets a color - fixed colors for mic select, check, scene, ME, PAN, ME+PAN; saved custom types get an automatic color from their name.
- Change: Switch Type now offers the same list as Start (was only editing / denoise / custom).
- Change: item colors are only written when they differ.

## 26.1016.1013

- Fix: a scene's Shots count was often 1 too high - a Picture Cut shot that only touches the scene edge (starts where the scene ends) was counted; a shot must now overlap the scene by more than half a frame.

## 26.1012.1641

- Renamed to "Project Manager - PM Timer" (was "PM_Timer") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1358

- First release in the hsuanice/ReaScripts repository.
- Requires the SWS extension.
- New: FPS (and DF for drop-frame) shown on the status line.
- Update Scene Metadata rewritten: scene name taken from the take name first (CLB-created scenes no longer become "(no name)"), take name set from the scene name, source items attributed by item group, selected scenes or all; runs automatically when PM Timer opens, closes or the project changes, and only writes when something changed.
- New: broken scene links (work log items pointing to a scene that no longer exists) are shown on the status line; Update Scene Metadata offers to re-link them automatically when a scene with the same name and start is found, and the new "Relink to Selected Scene" menu item re-links them by hand.

History before 26.1012.1358 (moved out of the script header; last header version: `260823.1332`).

```text
v260823.1332
  - AAP mode: added custom option to Start (no-folder flow) and New Job menu.
  - AAP mode: custom selection now prompts for a free-text work type and starts
    a simple AAP work item with that type.
  - Break/Continue: when continuing an AAP break session, mode is now forced
    back to AAP before creating the resumed item.

v260729.1217
  - Taipei-time version stamp aligned for this changelog entry.

v260510.1632
  - Fix: Start / Finish / Break / Continue / Switch Scene / Stop no longer
    recompute and overwrite the Scene Cut item's metadata note. The local
    compute_scene_metadata() only knows P_EXT:SCENE_ID and color+position
    attribution — it has no I_GROUPID fallback, so workflows that link EDL
    items to scenes via REAPER item grouping caused Src Cnt / Src Len to be
    reset to 0 on every action, requiring a Scene Analyzer rerun.
    Scene metadata is now owned by Scene Analyzer; PM Timer reads the
    existing note via build_work_item_note() and only writes when the user
    explicitly invokes "Update Scene Metadata" from the right-click menu.

v260324.1250
  - Conform mode work type menu: conform, picture cut, subtitle, custom
    (was conform-only). Custom prompts for free-text entry.
  - Added WORK_COLORS entries: picture cut (red), subtitle (cyan).

v260323.2205
  - Dialog work type menu: editing, denoise, scene, ME, PAN, ME+PAN, custom
    (same list for both scene-selected and project-scope sessions).
  - Conform work type menu: conform only (auto-selected, single item).
  - Removed separate project-scope ME+PAN/PAN/Custom branch; all modes now
    use get_work_types_for_mode() uniformly.

v260320.2259
  - New: PM_SyncProjectScopeNotes() — rescans all project-scope work items
    (WORK_TYPE set, SCENE_GUID empty) and rewrites their note with current
    project metadata (Scope, Scenes, Reel Len, Shots, Src Cnt, Src Len).
    Preserves user comments (text after first blank line).
    Called on startup, project change, action_finish, and action_break.

v260320.2254
  - Project-scope note: Scope field now reads the 3rd part of the project
    filename (e.g. "EP04" from "260320----TheFixer----EP04----Dialog").
    Falls back to "Project" if filename doesn't match the expected format.

v260320.2249
  - Project-scope work items (no scene selected) now get a note with
    full project metadata: Scope, Scenes, Reel Len, Shots, Src Cnt, Src Len.
    Computed from Scene Cut, Picture Cut, and EDL folder at session start.

v260320.2246
  - Dialog mode, no scene selected → Project scope: shows menu with
    ME+PAN / PAN / Custom instead of auto-setting ME&PAN.

v260320.2139
  - Dialog mode: no scene selected → Project scope, work type auto-set to
    "ME&PAN" (skips work type menu). Scene selection is no longer required.

v260318.2215
  - UI: "Finish Day" button renamed to "Finish".

v260318.1618
  - Break now saves session context (scene, work type) so it can be resumed.
  - New: "Continue" button appears in IDLE when a break is active; restores
    the previous scene + work type and starts a new work item immediately,
    without showing any menus.
  - New: "Start New" replaces "Start" when break state is pending; clicking
    it begins a fresh session and clears the saved break.
  - Status row shows "ON BREAK" (amber) instead of "IDLE" during a break,
    and previews the paused scene name and work type in the info row.
  - Break state persisted via ProjExtState so it survives REAPER restarts.
  - Fix: build_work_item_note() called with spurious 2nd argument in
    action_switch_scene (pre-existing, now corrected).

v260307.0335
  - Fix: copy_item_to_wl now uses native P_NOTES instead of ULT_GetMediaItemNote /
    ULT_SetMediaItemNote, resolving "argument 1: expected MediaItem*" crash caused
    by SWS ULT functions requiring matching project context.
  - Fix: copy_item_to_wl now updates existing Work Log items (note, length, color)
    instead of silently skipping them. wl_item_exists() replaced with find_wl_item()
    which returns the item handle for in-place update. No-op if nothing changed.

v260307.0300
  - New: PM_SyncSceneMetadataToLogItem(item) — reads scene note from the linked
    scene item and writes it into the log item note (ULT_SetMediaItemNote),
    preserving any user comment below the first blank line in the existing note.
  - New: PM_SyncAllLogItems() — scans all project items, filters by take name
    containing "|", calls PM_SyncSceneMetadataToLogItem on each.
    Runs at startup and on project change.
  - Log item note reads/writes now use ULT_GetMediaItemNote / ULT_SetMediaItemNote
    (SWS extension) instead of P_NOTES.
  - sync_linked_work_item_notes now preserves user comments in log item notes
    when pushing updated scene metadata.
  - New: mirror_log_item_to_work_log(item) — after each log item is created,
    auto-mirrors it into the open Work Log project (silent no-op if not found).
  - action_finish: captures work item before state reset and runs
    PM_SyncSceneMetadataToLogItem on the finished item.

v260305.2100
  - Scene Cut item notes now use the same format as Scene Analyzer:
      Range    : <start> - <end>
      Length   : <duration>
      Shots    : <n>
      Src Cnt  : <n>
      Src Len  : <duration>
    Old key=value lines are recognised and stripped on first update.
  - Auto-update scene metadata on: timer start, timer finish, break,
    stop (abort), and scene switch. Keeps notes current without
    requiring manual Scene Analyzer runs.

v260305.2000
  - Fix: repeated metadata updates caused src_cnt/src_len to accumulate.
    Root cause: Lua's %w pattern excludes underscore, so "src_cnt=" and
    "src_len=" lines were not matched and were kept as "other" content,
    then appended again on each update. Pattern changed to [%w_]+ to
    correctly strip all key=value metadata lines before rewriting.

v260305.1945
  - Fix: shots was always 0 because PICTURE_TRACK_NAME was "Picture" instead
    of "Picture Cut". Renamed constant to match the actual track name.
  - Fix: shot overlap detection now uses proper range overlap
    (item_end > scene_start and item_start < scene_end) instead of
    start-only check, so items straddling the scene boundary are counted.

v260305.1930
  - Scene item notes now always start with the scene name on the first line.
    If the note is empty or has no first line, "(no name)" is used as a placeholder.
    Existing scene names are preserved when metadata is refreshed.
  - "Update Scene Metadata" now supports multiple selected Scene Cut items.
    All selected scenes on the Scene Cut track are updated in one action.
    Result message reports the number of scenes updated.

v260305.0300
  - New: Scene metadata auto-update on session start (Scene Mode only).
    When starting a work session with a scene selected, the matching Scene Cut
    item's note is updated with:
      shots=   (items on "Picture" track within scene range)
      src_cnt= (EDL items attributed to this scene)
      src_len= (total EDL source length, HH:MM:SS:FF)
    Attribution uses P_EXT:SCENE_ID (priority 1) or color+position (priority 2),
    matching the InsightAnalyzer's EDL attribution logic.
  - New: "Update Scene Metadata" right-click menu option (choice 5).
    Manually refreshes the note on the currently selected Scene Cut item.
  - New constants: EDL_FOLDER_NAME = "EDL", PICTURE_TRACK_NAME = "Picture".

v260305.0130
  - New: get_proj_task() extracts the Task component (4th part) from the project
    filename (YYMMDD----Project----Episode----Task----...).
  - All newly created work items now store P_EXT:TASK (e.g. "Dialog") so that the
    InsightAnalyzer can group them by task without re-parsing the item name.
    Applies to: live sessions (create_work_item), Add Record (timed + duration-only).

v260305.0110
  - Fix: Sync to Work Log now also removes orphaned WL items — if a log item is
    deleted from the source project, the next sync removes the corresponding item
    from the Work Log. Only items tagged with P_EXT:WL_SRC_PROJ (i.e. created by
    this script) are eligible for removal; manually added WL items are left alone.
    Result message now reports "N added, N removed" separately.

v260305.0050
  - New: "Sync to Work Log" right-click menu option (choice 4).
    Mirrors Scene Cut date-track items and DurationOnly_Log items from the current
    dialog project into an open Work Log project (filename must contain "Work Log").
    - Date-track items → flat tracks in Work Log (track named YYYY-MM-DD).
    - DurationOnly_Log items → DurationOnly_Log (folder) > ProjectName (child)
      hierarchy; project name extracted from item name prefix before first " | ".
    - Duplicate check: skips items with same position (±0.001 s) and same take name.
    - Created items are EMPTY (no media source).
    - All changes are grouped into a single undo block in the Work Log project.

v260305.0038
  - Fix: get_proj_prefix() and get_proj_identity() now use EnumProjects(-1)
    (the currently active project) instead of EnumProjects(0) (tab index 0).
    EnumProjects(0) could return an empty filename in some REAPER configurations,
    causing the prefix to silently not be applied to any items.
  - Right-click menu: added "Fix Item Prefixes" option (choice 3) — manually
    runs sync_work_item_names() + sync_all_prefixes() on all items in the project.
    Use this if items are missing the project prefix after the script restarts.

v260305.0023
  - Fix: sync_work_item_names() now preserves existing prefix on scene-mode items
    when get_proj_prefix() is unavailable (project filename doesn't match expected
    format), preventing prefix stripping on sync.
  - Fix: sync_work_item_names() now unlocks items before renaming (C_LOCK), then
    relocks, matching the pattern used by sync_all_prefixes().
  - Fix: sync_all_prefixes() now also called after action_add_record() so that
    custom work-type items and duration-only items get their prefix applied
    immediately (they have no SCENE_GUID so sync_work_item_names() skips them).

v260305.0008
  - Dialog mode: Project Mode items (no scene selected) now placed under Scene Cut
    date tracks instead of Work Log. DurationOnly_Log also moves under Scene Cut.
    All Dialog-mode logs are now consolidated in one place. AAP mode is unaffected.

v260304.2358
  - Fix: sync_all_prefixes() now called at startup and on project change,
    so existing items (Project Mode, AAP) also get the prefix applied.
    sync_work_item_names() only covers Scene Mode items; sync_all_prefixes()
    covers everything with P_EXT:WORK_TYPE regardless of mode.

v260304.2350
  - Project prefix: work item names are automatically prefixed with
    "Project Episode Task | " parsed from the project filename.
    Format: YYMMDD----Project----Episode----Task----OptionalNote
    Example: 260304----TheFixer----EP04----Dialog → prefix "TheFixer EP04 Dialog | "
    Applied on creation (create_work_item), sync (sync_work_item_names),
    and manual record (action_add_record). Duplicate-safe (prefix not added twice).

v260304.2252
  - Project change detection: script now monitors EnumProjects(0) filename each
    loop iteration. When the active project changes (close/reopen without
    REAPER restart, or docked-script timing where project loads after the
    script), state is reset and try_recover() runs automatically — no more
    manual toggle required to trigger the resume dialog.

v260304.2240
  - Crash recovery dialog: on startup, if a session was interrupted (crash /
    unexpected REAPER close), shows: Resume / Finish & save / Discard.
  - Heartbeat: every 60 s the active work item's D_LENGTH is silently updated
    so crash recovery always has approximate timing (no undo entry).

v260304.2225
  - Right-click menu: added "Fix Duration from item length"
    Select stretched work item(s) in REAPER → right-click PM Timer →
    Fix Duration; overwrites P_EXT:DURATION with current D_LENGTH so
    InsightAnalyzer reads the corrected time after a crash/manual resize.

v260304.1300
  - UI: "Scene:" label switches to "Day:" as soon as AAP mode is active (IDLE or
    WORKING), not only when a work item is running

v260304.1200
  - Fix: get_selected_folder_stats() now counts items on the parent folder track
    itself (previously only child tracks were iterated; items placed directly on
    the folder track were silently skipped)

v260304.1100
  - Fix: gap between work items when using New Job / switching
    finish_aap_item() now returns (end_time, end_pos); callers pass these as
    a "chain" struct so the next item starts exactly where the previous ended
    (D_POSITION = end_pos, last_start_time = end_time, no menu-delay gap)

v260304.1000
  - "New Day" button renamed to "New Job" in AAP WORKING state
  - New Job: finish current item → submenu [pre-prod | new day | wrap | custom]
      pre-prod/wrap/custom → simple work item (no folder needed)
      new day              → folder-based AAP start (select folder first)
  - Extracted start_simple_aap_work() helper to avoid code duplication

v260303.2400
  - AAP folder path: confirmation dialog pre-filled with auto-detected stats;
    user can review/edit Items and Total Duration before creating the item
  - Total Len format changed to H:M:S.ms (e.g. 3:42:41.996) in P_NOTES
  - New: fmt_hms_ms() and parse_duration_str() helpers

v260303.2350
  - AAP Start: two paths based on folder selection
      Folder selected   → AAP with stats (item count / length / size) as before
      No folder selected→ show [pre-prod | wrap] menu; create simple work item
  - Fix: AAP-specific P_EXT metadata (AAP_DAY_NAME etc.) was silently lost because
    create_work_item() locks the item (C_LOCK=1) before returning; fix: unlock →
    write P_EXT → relock in action_start_aap()
  - fix: finish_aap_item() P_NOTES omits Items/Size rows when no folder stats exist
  - Fix: try_recover() now restores AAP state for all AAP work types (was "aap" only)
  - New work types: pre-prod (orange), wrap (light blue)

v260303.2340
  - Fix: get_selected_folder_stats() now counts items on the last child track
    (break was firing before the item loop — moved to after)
  - AAP WORKING UI simplified: removed 6-row display and dynamic window height;
    uses standard 2-row layout with "Day: <name>" instead of "Scene:"
  - WIN_H fixed at 140px in all states (no more gfx.init resize on state change)

v260303.2320
  - Work Log track inserted at top of track list when created (AAP mode)
  - AAP WORKING buttons: [New Day] [Break] [Finish] (+ 1 disabled)
  - New Day: saves current session notes, immediately starts next AAP session
    (user selects next folder track in REAPER before clicking)

v260303.2310
  - AAP Mode: select a folder track → logs item count, total length, est. size
  - AAP Start creates "AAP | <folder_name>" item on Work Log track
  - AAP Finish writes P_NOTES (Items / Total Len / Est. Size / Work Time)
  - Mode button (IDLE) cycles Dialog ↔ AAP ↔ Conform via existing menu
  - Dynamic window height: 180px in AAP WORKING, 140px otherwise
  - Recovery: AAP state persisted across REAPER restarts

v260303.2253
  - Dialog mode hides aap/conform from work type menu

v260302.1830
  - Scene vs Project mode auto-detection (no more forced scene selection):
      Scene Mode  : scene item selected on Scene Cut → SCENE_GUID written,
                    name = "scene (tc) | work_type"
      Project Mode: no scene selected → SCENE_GUID omitted, name = work_type
  - Applies to action_start(), action_add_record() (timed + duration-only)
  - create_work_item() signature: scene_name replaced by pre-computed item_name;
    SCENE_GUID only written when scene_guid ~= ""
  - sync_work_item_names() unchanged; naturally skips Project Mode items
    (no SCENE_GUID → sync condition `sg ~= ""` is false)

v260302.1820
  - Right-click anywhere in the window shows "Dock window" / "Undock window" menu.
    Uses gfx.dock(1) to dock, gfx.dock(0) to undock; no OS title bar required.

v260302.1815
  - Fix: dock state now tracked every frame via cur_dock = gfx.dock(-1) into a
    module-level variable. Previously gfx.dock(-1) was only called at char==-1
    (window already detached), so it always returned 0 and the docked state was
    never saved correctly.

v260302.1810
  - Fix: item locking used wrong key "D_LOCK"; correct REAPER API key is "C_LOCK"
    (char flag, &1=locked). All lock/unlock calls updated.

v260302.1805
  - Fix: buttons unclickable after Start — BTN was built with index gaps (BTN[1]=nil
    in WORKING mode), causing ipairs to stop immediately. Changed to table.insert
    so BTN is always a dense array regardless of which buttons are active.

v260302.1800
  - GUI: horizontal control panel (WIN_W=560, WIN_H=140)
    Single info row: Scene | Type | Status | Elapsed, all on one line
    Buttons: [Start] [Finish] [Break] [Add Record] in a single horizontal row
    Inactive buttons rendered as grayed-out (non-clickable)
  - Dock support: DOCK_STATE persisted via GetExtState/SetExtState
  - Auto Lock: C_LOCK=1 set on all work items after creation
    C_LOCK=0 before modifying D_LENGTH in finish_work_session, C_LOCK=1 after
    Scene items and other project items are NOT locked

v260302.1755
  - Fix: window position now tracked each frame via gfx.clienttoscreen(0,0)

v260302.1750
  - Add Record: Duration split into two fields — Dur Hours and Dur Mins

v260302.1745
  - Add Record: Date field changed from YYYY-MM-DD to 6-digit YYMMDD

v260302.1740
  - Add Record: Work Type now uses gfx.showmenu

v260302.1730
  - Add Record: added Date field; window position memory

v260302.1700
  - New: Add Record button with Timed and Duration-only modes

v260302.1620
  - New: sync_work_item_names()

v260302.1600
  - Full architecture reset: Scene Cut folder with date track children

v260302.1540
  - Removed BREAK state; UI high-contrast; Arial 18/22
```
