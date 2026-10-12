# hsuanice_Render or Glue with Handles - RGWH.lua — Changelog

(formerly `hsuanice_RGWH ReaImGui.lua`)

RGWH ReaImGui - ImGui Interface for RGWH Core（Render or Glue with Handles）

## 26.1012.1641

- Renamed to "Render or Glue with Handles - RGWH" (was "RGWH ReaImGui") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1011.2142

- First release in the hsuanice/ReaScripts repository (replaces hsuanice/PublicBeta).
- Remove the PublicBeta repository in ReaPack before installing this one.
- Requires the "hsuanice Library" package.
- Version format is now YY.MMDD.HHMM.
- Fix: Help > About showed version "unknown".

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.9`).

```text
0.2.9 [261011.1053] - ADDED: "Render: Retain Glue Cues" checkbox (Settings → CUES, default OFF)
  - Render carries the Glue cues already embedded in the source file into the new take
  - Saved to RGWH ExtState RENDER_KEEP_GLUE_CUES; requires RGWH Core >= 0.3.12 and SWS

0.2.8 [260710.1556] - FIX: ImGui window stability + Settings collapse lock
  - FIXED: Removed extra End() calls on non-visible Begin() paths (prevents "ImGui_End: Calling End() too many times!")
  - FIXED: BWF install modal now uses NoDocking to avoid docking-related stack issues
  - UI: Disabled Settings window collapse arrow (NoCollapse) to prevent accidental fold/collapse

0.2.7 [260330.1415] - MOVED: "Keep MUTED as separate unit" to main panel alongside "Split at crossfades"
  - Both unit grouping checkboxes now appear on the same row below Handle/Tail in the main panel
  - REMOVED: "GLUE UNIT BEHAVIOUR" section from Settings tab (no longer needed)
  - FIX (Core): muted items now group with other muted items — only muted/non-muted boundary breaks the chain

0.2.6 [260330.1354] - ADDED: Glue unit grouping options (requires RGWH Core ≥ 0.3.8)
  - NEW: "Split at crossfades" checkbox — main panel, below Tail, right side (default OFF)
    • When ON: crossfading items are not grouped into the same unit; each becomes its own unit
  - NEW: "Keep MUTED as separate unit" checkbox — main panel, below Handle/Tail (default ON)
    • Muted items group only with other muted items; breaks at muted/non-muted boundary
  - REMOVED: "HANDLE (Pre/Post Roll)" section header — "Handle (s)" label already self-explanatory
  - Both settings persisted in GUI state, synced to RGWH ExtState on every change
  - Both options are no-ops when a Time Selection is active (TS-Window path bypasses unit detection)

0.2.5 [260328.0408] - ADDED: Tail Seconds — FX decay extension (requires RGWH Core ≥ 0.3.7)
  - NEW: "Tail (s)" input field under Handle settings
    • Extends item into silence after right handle to capture reverb/delay/echo decay
    • 0 = disabled (backward-compatible default)
  - tail_seconds persisted in gui state (persist_keys + serialize/parse)
  - TAIL_SECONDS written to RGWH ExtState on every sync_to_extstate()
  - Debug log includes Tail Seconds value

0.2.4 [260206.2345] - ExtState: Full sync for wrapper scripts
  - ADDED: SELECTION_SCOPE to ExtState (auto, units, ts, item)
  - ADDED: SELECTION_POLICY to ExtState (progress, restore, none)
  - ADDED: RENDER_MERGE_TO_ITEM, GLUE_MERGE_TO_ITEM to ExtState
  - IMPACT: Wrapper scripts can now read ALL GUI settings from ExtState
  - NOTE: Enables keyboard shortcuts to fully mirror GUI configuration

0.2.3 [260205.1129] - RENAMED: Multi-Channel Policy labels simplified
  - CHANGED: "SOURCE-playback" → "playback", "SOURCE-track" → "track"
  - UPDATED: Radio buttons, tooltips, help text, console messages
  - REASON: Consistency with AudioSweet GUI naming convention

0.2.2 [260205.0418] - REMOVE: force_multi / No-TrackFX Policy settings (redundant with MULTI_CHANNEL_POLICY)
  - REMOVED: "Glue No-TrackFX Policy" and "Render No-TrackFX Policy" combo controls from Settings tab
  - REMOVED: GUI state fields glue_no_trackfx_policy / render_no_trackfx_policy
  - REMOVED: persist keys, ExtState sync, labels, debug output, args pass-through for the two policies
  - REASON: MULTI_CHANNEL_POLICY now fully controls channel behavior
    • source_track = old force_multi (Apply after Glue to force track ch)
    • source_playback = old preserve (Glue natively preserves playback ch → skip Apply → faster)
  - PERFORMANCE: Glue with SOURCE-playback is significantly faster (skips unnecessary Apply step)
  - REQUIRES: RGWH Core v0.3.0 [v260205.0409]+

0.2.1 [260204.2352] - Multi mode hover info + Manual: mono 2ch floor documentation
  - UPDATED: Multi channel mode tooltip
    • Now explains Multi-Channel Policy (SOURCE-playback / SOURCE-track)
    • Clarifies vs AUTO mode: MULTI does not detect mono items → 2ch minimum
  - UPDATED: SOURCE-playback policy tooltip
    • Separated mono handling by mode: AUTO → 1ch, MULTI → 2ch (40209 floor)
    • Added note: "Use AUTO mode if mono should stay mono"
  - UPDATED: Manual > Overview > Channel Mode table
    • Multi row: now shows policy-based (40209/41993) instead of hardcoded 41993
    • Auto row: clarified mono → 40361, multi → policy-based
    • Apply Actions row: added 40209 (preserve)
  - ADDED: Manual > Multi-Channel Policy section
    • SOURCE-playback vs SOURCE-track explanation
    • Mono items in MULTI mode: 40209 has 2ch floor
    • Guidance: use AUTO mode for true 1ch mono preservation

0.2.0 [260104.2344] - Multi-Channel Policy Support
  - ADDED: Multi-Channel Policy control for AUTO and MULTI channel modes
    • Two policies: SOURCE-playback (preserve item channels) and SOURCE-track (match track channels)
    • UI: Appears as indented radio buttons below Channel Mode when AUTO or MULTI is selected
    • Tooltips explain each policy's behavior and use cases
  - ADDED: ExtState synchronization for MULTI_CHANNEL_POLICY
    • Writes "source_playback" or "source_track" to RGWH ExtState
    • Integrated into sync_rgwh_extstate_from_gui() function
  - ADDED: Debug logging for Multi-Channel Policy setting
    • Shows in console output when debug mode is enabled
    • Format: "Multi-Channel Policy: SOURCE-playback" or "SOURCE-track"
  - CHANGED: GUI state now includes multi_channel_policy field (0=source_playback, 1=source_track)
  - REQUIRES: RGWH Core v0.3.0+ for Multi-Channel Policy support
  - IMPACT: Users can now control multi-channel behavior for AUTO/MULTI modes
  - NOTE: Policy only applies to multi-channel items; mono items always output mono

0.1.4 [251225.1835] - Epsilon Removal (Internal Constant)
  - REMOVED: Epsilon Mode and Epsilon Value GUI controls (lines 1467-1479)
  - REMOVED: epsilon_mode and epsilon_value from gui state (lines 525-526)
  - REMOVED: epsilon ExtState synchronization (lines 651-657, 1211-1216)
  - REMOVED: epsilon debug logging entry (line 760)
  - REASON: Epsilon now internal constant (0.5 frames) in RGWH Core v0.2.2
  - IMPACT: Simplified GUI, epsilon no longer user-configurable

0.1.3 [v251224.1135] - Live ExtState Sync + Debug Setting Logs
  - ADDED: Any setting change now updates RGWH ExtState immediately
  - ADDED: Debug mode prints setting changes on every toggle/update

0.1.2 [v251218.2240] - Disabled collapse arrow
  - Added: Main GUI window now uses WindowFlags_NoCollapse so users cannot collapse it accidentally

0.1.1 [v251218.1800] - BWF MetaEdit reminder + install guide
  - Added: CLI detection flow that checks PATH/custom paths on startup, shows alert + guide when missing
  - Added: Settings > Timecode section shows CLI status, allows custom path input and re-check action
  - Added: Homebrew install modal with copy buttons for each step to simplify CLI installation

0.1.0 [v251215.1730] - DISABLED SETTINGS WINDOW DOCKING
  - FIXED: Settings window now always has docking disabled (WindowFlags_NoDocking).
    • Prevents Settings window from being docked into REAPER's dock system
    • Settings window should remain floating for better usability
    • Line: 985 (settings window flags)
  - PURPOSE: Match Manual window behavior - both popup windows now always float
  - IMPACT: Improved stability and consistent UX for popup windows

[v251215.1507] - REMOVED REDUNDANT CHANNEL MODE HELP MARKER
  - REMOVED: Help marker (?) after Channel Mode radio buttons (line 1793-1794).
    • Reason: Each radio button now has detailed hover tooltip
    • Auto/Mono/Multi modes all provide comprehensive explanations on hover
    • Redundant summary help marker no longer needed
  - IMPACT: Cleaner UI, less visual clutter

[v251215.1500] - REMOVED PRESET MENU
  - REMOVED: Preset menu and preset system completely removed from GUI.
    • Removed preset data definitions (previously lines 622-653)
    • Removed apply_preset() function (previously lines 834-844)
    • Removed Presets menu from menu bar (previously lines 1752-1760)
  - REASON: Preset system not needed - users prefer direct control
  - IMPACT: Cleaner, simpler GUI interface

[v251215.1450] - IMPROVED CHANNEL MODE TOOLTIPS CLARITY
  - IMPROVED: Channel Mode tooltips clarified to prevent item vs track channel count confusion (lines 1797-1837).
    • Problem: Users might confuse item's own channel count with track channel count
    • Solution: Added explicit warnings and reminders in tooltips
  - Auto mode tooltip (lines 1797-1809):
    • Added Note section warning about item vs track channel count distinction
    • "Item channel count may differ from track channel count"
    • "Use Multi mode to force output to match track channels"
  - Mono mode tooltip (lines 1812-1821):
    • REMOVED: Operation mode (AUTO/RENDER/GLUE) explanations - irrelevant to channel mode
    • Simplified to focus only on mono channel behavior
    • "All items converted to mono output"
  - Multi mode tooltip (lines 1825-1837):
    • Added Important section emphasizing output follows TRACK channel count
    • "Output always follows TRACK channel count"
    • "Item's own channel count is ignored"
  - PURPOSE: Prevent user confusion between item channels vs track channels
  - NOTE: All tooltips exclude command IDs (kept in manual only)

[v251214.0920] - CLARIFIED OPERATION MODE SCOPE
  - Fixed: AUTO mode hover info no longer mentions TS scope logic (line 1933)
    • Previous: "Scope: No TS→Units, TS=span→Units, TS≠span→TS" (incorrect)
    • Corrected: "Always uses Units scope" (accurate)
    • Rationale: AUTO mode always uses Units detection, TS logic only applies to GLUE mode
  - Clarified: GLUE mode hover info clearly shows TS scope behavior (line 1935)
    • "Scope: Has TS→TS, No TS→Units (like REAPER native)"
    • TS scope logic is GLUE-specific feature, not AUTO feature
0.1.0 [v251214.0100] - SIMPLIFIED VOLUME MERGE INTERACTION
  - Simplified: Clean mutual exclusion + binding logic, removed all warning text (lines 1816-1856)
    • Merge to Item ◄──mutually exclusive──► Merge to Take ◄──bound to──► Print Volumes
    • 4 valid states: ❌❌❌ (native) | ✓❌❌ (Item) | ❌✓❌ (Take) | ❌✓✓ (Take+Print)
  - Behavior: Merge to Item
    • When checked: auto-disables Merge to Take + Print Volumes
    • Mutually exclusive with opposite, no Print support (REAPER only prints take volume)
  - Behavior: Merge to Take
    • When checked: auto-disables Merge to Item
    • When unchecked: auto-disables Print Volumes (binding relationship)
  - Behavior: Print Volumes
    • When checked: auto-enables Merge to Take + disables Merge to Item
    • Fully bound to Merge to Take
  - Removed: Orange warning text and auto_switched state variable
    • Mutual exclusion + binding behavior is intuitive enough, no extra prompts needed
    • Avoids window resize issues
  - Updated: Help markers clarify mutual exclusion and binding relationships
0.1.0 [v251214.0040] - SIMPLIFIED VOLUME MERGE UI
  - Added: Auto-switch from Merge to Item to Merge to Take when Print ON is enabled
    • Rationale: REAPER can only print take volume, not item volume
    • When user enables Print with Merge to Item selected, auto-switches to Merge to Take
    • Shows orange notification: "(Auto-switched to Merge to Take)"
    • Updated Print Volumes help marker to explain this behavior
    • Valid combinations: OFF | Merge to Item | Merge to Take + Print OFF | Merge to Take + Print ON
  - Improved: Channel Mode help marker now clarifies Multi mode behavior
    • Updated tooltip: "Multi: force item output to match track channel count"
    • Makes it clear that Multi mode forces item to match the track's channel count
  - Improved: Simplified Manual documentation for Volume Rendering
    • Restored 3-column table format (Print OFF / Print ON) for consistency
    • Direct language: "Combine take vol to item vol" instead of technical jargon
    • Shows result, compensation behavior, and print options for each mode
    • OFF mode now clearly explains REAPER native behavior
    • Changed: "Bake" → "Print" for consistent terminology
  - Updated: Manual documentation for bidirectional volume merge
    • New table showing all merge/print combinations and their results
    • Added technical details: REAPER renders with item×take, both must be 1.0 for Print OFF
    • Clearer explanation of volume flow in each mode
  - Tested: All four combinations verified working correctly
    • Merge to Item + Print OFF: item=combined, take=1.0, audio at original level ✓
    • Merge to Item + Print ON: item=1.0, take=1.0, audio with gain ✓
    • Merge to Take + Print OFF: item=1.0, take=combined, audio at original level ✓
    • Merge to Take + Print ON: item=1.0, take=1.0, audio with gain ✓
  - Fixed: Merge to Item + Print OFF - BOTH item AND take set to 1.0 during render
  - Critical: REAPER renders with item×take volume (not just take!)
  - Logic: Preprocess sets item=1.0, take=1.0; Postprocess restores item=combined
  - Added: Bidirectional volume merge support (merge to item OR merge to take).
    - New checkbox: "Merge to Item" - merges take volume into item volume
    - Existing checkbox: "Merge to Take" - merges item volume into take volume (original behavior)
    - Checkboxes are mutually exclusive (radio button behavior)
    - Print checkbox now disabled when neither merge option is selected
    - Merge modes:
      * Merge to Item: Consolidates volume at item level, all takes at 1.0 (0 dB)
      * Merge to Take: Consolidates volume at take level (original behavior)
      * OFF (neither checked): No volume merging, REAPER native behavior
    - Print behavior:
      * Print ON + Merge to Item: Transfers item volume to takes, then prints (all volumes → 0dB)
      * Print ON + Merge to Take: Prints merged take volumes (all volumes → 0dB)
      * Print OFF + Merge to Item: Preserves volume in item
      * Print OFF + Merge to Take: Preserves volume in takes
      * Print disabled when Merge = OFF (no effect in native mode)
    - GUI state: merge_to_item (boolean), merge_to_take (boolean, replaces merge_volumes)
    - Migration: Old merge_volumes boolean auto-converts to merge_to_take on load
    - Lines: 384-385 (state vars), 425 (persist keys), 491-498 (migration), 817-820 (args), 1818-1848 (UI)
  - Purpose: Supports both item-centric and take-centric volume workflows, with flexible print options.

[v251213.1430] - DISABLED MANUAL WINDOW DOCKING
  - Fixed: Manual window now always has docking disabled (WindowFlags_NoDocking).
    - Prevents ImGui_End assertion errors when manual window is docked
    - Manual window should remain floating for better readability
    - Line: 993 (manual window flags)
  - Purpose: Improve stability and prevent docking-related errors for manual window.

[v251213.0023] - ADDED DOCKING TOGGLE OPTION
  - Added: Window docking toggle option in Settings menu.
    - New location: Menu Bar → Settings → "Enable Window Docking" (checkbox)
    - When disabled: window cannot be docked into REAPER's dock system (WindowFlags_NoDocking)
    - When enabled: window can be docked like any other ImGui window
    - Setting persists between sessions via ExtState
    - Lines: 396 (setting definition), 415 (persist_keys), 1610-1614 (window flags), 1643-1647 (Settings menu)
  - Purpose: Prevents accidental docking for users who prefer floating windows, while allowing flexibility for those who want docking.

[v251215.2300] - CLEANUP: Removed unused settings + Documentation improvements
  - Removed: Rename Mode setting (was never implemented, no functional change)
  - Removed: Glue After Mono Apply setting (was never implemented, no functional change)
    • Removed from GUI state variables (line 377-379)
    • Removed from persist_keys array (line 396-404)
    • Removed from build_args_from_gui() policies (line 759-763)
    • Removed checkbox from Settings window (was line 941-943)
    • Updated Mono mode tooltip to reflect fixed behavior (line 1646-1652)
    • Actual behavior unchanged: AUTO/GLUE modes always glue multi-item units after mono apply
  - Removed: Rename Mode setting (complete removal details)
    • Removed from GUI state variables
    • Removed from persist_keys array
    • Removed from build_args_from_gui() function
    • Removed combo box from Settings window
    • Actual naming behavior unchanged: RENDER still uses "TakeName-renderedN", GLUE still uses "TakeName-glued-XX.wav"
  - Improved: TIMECODE MODE section clarity in Settings
    • Title changed: "TIMECODE MODE" → "TIMECODE MODE (RENDER only)" (line 884)
    • Help marker updated to clarify GLUE mode always uses 'Current' (line 887)
    • Prevents user confusion about TC mode applicability
  - Improved: Volume Rendering terminology consistency
    • Changed: "Volume Handling" → "Volume Rendering" throughout GUI (line 1607)
    • Help markers now explain GLUE mode always forces merge and print (lines 1610, 1614)
    • Manual updated with technical explanation of why GLUE requires this (lines 1077-1084, 1407-1414)
  - Added: Comprehensive naming convention documentation in Manual
    • New section 7 "NAMING CONVENTIONS" in Overview tab (lines 1181-1207)
      - Table showing RENDER vs GLUE naming formats with examples
      - Explains N and XX increment logic
    • RENDER Mode tab: Detailed naming explanation (lines 1279-1287)
      - Format: TakeName-renderedN (N = incremental 1,2,3...)
      - Purpose: Distinguish original take from render iterations
      - Fixed behavior, cannot be changed
    • GLUE Mode tab: REAPER native naming explanation (lines 1392-1400)
      - Format: TakeName-glued-XX.wav (XX = REAPER auto-increment 01,02,03...)
      - Take name automatically becomes filename
      - Preserves take names in final output
  - Technical: All changes are documentation/UI cleanup, no Core logic modified
  - Requires: RGWH Core v251215.2300 (Rename Mode setting removed from Core API)

[v251212.1230] - IMPROVED UNDO BEHAVIOR FOR SINGLE-STEP UNDO
  - Improved: All RGWH operations now use single undo block.
    - Issue: Executing RGWH operations required multiple undo steps to fully revert
    - Solution: Wrapped run_rgwh() execution with Undo_BeginBlock/EndBlock (lines 761-762, 807-815)
    - Added PreventUIRefresh to improve performance during execution
    - Result: One Undo operation reverts entire RGWH execution back to pre-execution state
    - Undo label format: "RGWH GUI: Glue/Render/Window/Handle"
    - All operation modes (Glue, Render, Window, Handle) now have consistent undo behavior
  - Technical: Nested undo blocks are supported by REAPER and merge correctly.
    - GUI undo block wraps RGWH Core's internal undo blocks (if any)
    - Outer block takes precedence, creating single undo point for user

v251114.1920 - Manual Window: Process Flow Updates (DOCUMENTATION REFINEMENT)
  - Updated: RENDER Mode process flow table (now 14 steps, was 10)
    • Added: Snapshot Take FX (step 1), Add/Remove Cue Markers (steps 4,8), Clone Take FX (step 13)
    • Complete flow: Take FX snapshot → Volume Pre → Extend → Add Markers → Snapshot/Zero Fades → Apply/Render → Remove Markers → Restore Fades → Trim → Volume Post → Rename → Clone Take FX → Embed TC
    • All steps now accurately reflect actual code execution order in RGWH Core
  - Updated: GLUE Mode process flow table (now 12 steps, was 10)
    • Added: Add Cue Markers (step 1), Snapshot/Restore Track Ch (steps 4,6), Remove Cue Markers (step 12)
    • Complete flow: Add Markers → Extend → Volume Pre → Snapshot Track Ch → Glue → Restore Track Ch → Zero Fades → Apply → Embed TC → Trim → Volume Post → Remove Markers
    • Clarifies that Glue cues are pre-embedded before Glue action (absorbed into media)
  - Fixed: Multi-channel mode execution order description in GLUE technical notes
    • Corrected: "Glue FIRST (42432) → Restore Track Ch → Apply (41993)" (was incorrectly reversed)
    • Reason: Action 42432 auto-expands track channel count, so must snapshot/restore
    • Technical notes now accurately describe the code implementation
  - Fixed: Fade handling explanation for Apply actions (40361/41993)
    • Changed: "print fades causing DUPLICATE fades" (was "bake fades")
    • Clarified: Apply actions print fades into audio while keeping item fade settings
    • Result: Both item fade property AND printed fade exist, doubling the fade effect
    • Accurate description of the actual behavior and why snapshot/zero/restore is needed
  - Improved: Terminology consistency across tabs
    • Unified: "Add/Remove Cue Markers" (was mixed: "Edge Cues"/"Glue Cues"/"Clean Markers")
    • Action descriptions now consistent between RENDER and GLUE tabs
  - Removed: Line number column from process flow tables
    • Reason: Simplifies maintenance, no need to update line numbers when code changes
    • Tables now have 3 columns: Step, Function, Action (was 4 with Line column)
  - Technical: Manual window remains fully functional with ESC key support

v251114.0045 - NEW FEATURE: Operation Modes Manual Window (MAJOR UPDATE)
  - Added: Manual window (Help > Manual) with comprehensive operation modes guide
    • Overview tab: Feature reference tables (Channel/FX/Volume/Handle/Cues/Actions)
      - Lists all features with implementation details (API functions, Action IDs)
      - 6 major feature categories with complete technical specifications
    • RENDER Mode tab: Function-based process flow explanation
      - Entry point: M.render_selection()
      - 10-step process table with function names and actions
      - Functions: snapshot_fades, preprocess_item_volumes, per_member_window_lr, etc.
    • GLUE Mode tab: Function-based process flow for multi/auto and mono modes
      - Entry point: M.glue_selection() → glue_auto_scope()
      - 10-step process table for multi/auto mode
      - 3-step simplified flow for mono mode
      - Functions: detect_units_same_track, glue_unit, apply_multichannel_no_fx_preserve_take
    • AUTO Mode tab: Decision logic with function flow
      - Entry point: M.core(args) with op='auto' → auto_selection()
      - 6-step intelligent batching process
      - Shows how units are separated and batched by type
  - Added: Manual window state management (show_manual flag, line 240)
  - Added: ESC key closes Manual window (without closing main GUI)
  - Technical: draw_manual_window() function (lines 861-1129)
  - Technical: Help menu item "Manual (Operation Modes)" opens manual window (lines 891-893)
  - Technical: Main loop calls draw_manual_window() (line 1344)
  - Window size: 900x700 pixels, resizable with tabs for easy navigation
  - Color-coded content: cyan for headings, green for features, red for limitations, yellow for notes
  - Includes important design notes about GLUE multi mode creating 2 takes for efficiency
  - Explains track channel count protection mechanism for force_multi policy
  - Fixed: Comparison table corrections
    • Take Name→Filename: RENDER=No (correct), GLUE=Yes, AUTO=Yes
    • BWF TimeReference: RENDER=Cur/Prev/Off (3 options), GLUE=Current (only), AUTO=RENDER units
    • Mixed unit types: GLUE=Yes(No TS) - supports mixed units without Time Selection
    • Efficiency (multi-item): RENDER=Slow(N×), GLUE=Best(1×) - GLUE significantly faster for multiple items
  - Added: Efficiency Advantage section in GLUE Mode tab
    • Explains why GLUE is faster: merge first (1× operation) vs RENDER each (N× operations)
    • Example: 10 items → GLUE processes 1 time vs RENDER processes 10 times

v251113.1820 - STABLE: Fully tested and verified
  - No GUI changes in this release
  - Requires: RGWH Core v251113.1820
  - Status: Volume handling fully tested and working correctly
  - All features verified working in production testing
  - Recommended stable version for production use

v251113.1810 - Version sync with Core critical volume settings fix
  - No GUI changes in this release
  - Requires: RGWH Core v251113.1810 for proper volume settings support
    • CRITICAL: Fixed volume settings not being read from ExtState
    • GUI "Merge Volumes" and "Print Volumes" checkboxes now work correctly
    • Previous versions ignored these settings (always used false/nil)
  - Note: All GUI features remain unchanged and functional

v251113.1800 - Version sync with Core major refactor
  - No GUI changes in this release
  - Requires: RGWH Core v251113.1800 for unified volume/FX handling
    • Major refactor: All volume and FX handling now uses centralized helper functions
    • Fixed: GLUE multi/auto mode now properly handles volumes (was missing entirely)
    • Improved: Single source of truth for volume logic across all modes
    • More maintainable and less prone to bugs
  - Note: All GUI features remain unchanged and functional

v251113.1700 - Version sync with Core volume handling fix
  - No GUI changes in this release
  - Requires: RGWH Core v251113.1700 for complete mono channel mode functionality
    • Volume handling (merge_volumes/print_volumes) now working correctly in mono apply workflow
    • Fixes volume reset to 1.0 issue when using mono channel mode
    • Volumes now properly snapshot/merge/restore like RENDER mode
  - Note: All GUI features from previous versions remain unchanged and functional

v251113.1650 - Version sync with Core FX control fixes
  - No GUI changes in this release
  - Requires: RGWH Core v251113.1650 for complete mono channel mode functionality
    • FX control (TAKE_FX/TRACK_FX settings) now working correctly
    • RENDER mode mono enforcement now functional
  - Note: All GUI features from v251113.1540 remain unchanged and functional

v251113.1540 - GUI support for mono apply + conditional glue feature
  - Added: "Glue After Mono Apply (AUTO mode)" checkbox in Settings > Policies
    • Tooltip explains: ON=apply mono then glue, OFF=apply mono keep separate
    • Notes that GLUE mode always glues (ignores this setting)
  - Added: Hover tooltip on "Mono" channel mode radio button
    • Displays current GLUE_AFTER_MONO_APPLY setting (ON/OFF)
    • Shows behavior per operation mode (RENDER/AUTO/GLUE)
    • Explains where to change the setting (Menu > Settings > Policies)
  - Technical: Added glue_after_mono_apply to GUI state (line 215)
  - Technical: Added to persist_keys for save/load across sessions (line 242)
  - Technical: Added to build_args_from_gui() policies section (line 603)
  - Technical: Settings checkbox implementation (lines 775-777)
  - Technical: Mono channel mode hover tooltip (lines 856-869)
  - Requires: RGWH Core v251113.1540 for mono apply workflow

v251112.1600 - Auto version extraction from @version tag
  - Improved: VERSION constant now auto-extracts from @version tag in file header
  - Technical: Uses debug.getinfo() and file parsing to read @version tag at runtime
  - Result: Only need to update @version tag once, Help > About automatically syncs
  - No more manual version string updates required

v251112.1500 - Settings window ESC key support + Auto version sync
  - Added: ESC key now closes Settings window (without closing main GUI)
  - Behavior: Press ESC when Settings window is focused to close only the Settings window
  - Main GUI remains open and functional after Settings window is closed with ESC
  - Improved: Help > About now automatically displays current version from VERSION constant
  - Technical: Version string centralized at line 144, Help menu uses string.format() for auto-sync

v251107.1530 - CRITICAL FIX: Units glue handle content shift (CORE FIX)
  - Fixed: Units glue with handles no longer causes content shift
  - Core change: Removed incorrect pre-glue D_STARTOFFS adjustment that was being overwritten
  - Impact: All glue operations now preserve audio alignment correctly
  - Requires: RGWH Core v251107.1530 or later

v251107.0100 - FIXED AUTO MODE LOGIC (CORE MODIFICATION)
  - Fixed: AUTO mode now correctly processes units based on their composition (not total selection count)
    • Single-item units → RENDER (per-item)
    • Multi-item units (TOUCH/CROSSFADE) → GLUE
    • Works correctly even when selecting mixed unit types
  - Added: New auto_selection() function in RGWH Core
    • Analyzes each unit individually
    • Separates single-item units (for render) and multi-item units (for glue)
    • Processes them in appropriate batches
  - Changed: core() function now calls auto_selection() for op="auto"
  - Improved: AUTO mode description updated to reflect unit-based logic
  - Technical: RGWH Core line 1340-1428 (new auto_selection function)
  - Technical: RGWH Core line 1955-1959 (modified core function)

v251106.2250 - CLARIFIED AUTO VS GLUE BEHAVIOR
  - Changed: Removed "Glue Single Items" checkbox from GUI for clarity
  - Changed: AUTO mode behavior clarified (awaiting Core fix)
  - Changed: GLUE mode now has clear, fixed behavior (always glue including single items)
  - Changed: RENDER mode (unchanged - always per-item render)
  - Improved: Mode descriptions now clearly explain the difference between AUTO and GLUE
  - Technical: glue_single_items default changed to false (AUTO mode behavior)
  - Technical: GLUE mode now uses selection_scope="auto" instead of "ts" for proper scope detection

v251106.2230 - COMPLETE UI REDESIGN & COMPACT LAYOUT
  - Changed: Completely reorganized GUI layout for better clarity and compactness
    • Common settings (Channel Mode, Printing, Handle) moved to top
    • Channel Mode now displays in single horizontal row with label
    • Auto Mode settings in single horizontal row (label + checkbox + help)
  - Changed: AUTO mode simplified
    • Single checkbox: "Glue Single Items" (single item → glue or render)
    • Auto scope detection is always on (Units vs TS detection is automatic)
  - Changed: GLUE mode uses Time Selection (always glue, no settings)
  - Changed: RENDER mode has no settings (always per-item render)
  - Added: Dynamic mode info display
    • Hover over RENDER/AUTO/GLUE buttons to see detailed description
    • Unified info area below buttons (much more compact than separate sections)
    • Shows relevant scope detection logic and behavior for each mode
  - Improved: Much shorter GUI window (removed redundant section headers and text blocks)
  - Technical: Removed selected_mode and use_units state variables (no longer needed)

v251106.1800
  - Add: Complete settings persistence - all GUI settings are now automatically saved and restored between sessions
  - Add: Debug mode console output - when debug level >= 1:
    • Print all settings on startup with prefix "[RGWH GUI - STARTUP]"
    • Print all settings on close with prefix "[RGWH GUI - CLOSING]"
  - Improve: Settings are automatically saved whenever any parameter is changed
  - Technical: Added print_all_settings() function to display all current settings in organized format
v251102.1500
  - Fix: Correct GLUE button hover/active colors to yellow shades.
v251102.0735
  - Add: Press ESC to close the GUI window when the window is focused.
v251102.0730
  - Change: Move Channel Mode to the right of Selection Scope and use a two-column layout so Channel Mode takes the right column.
  - Change: Replace the 'View' menu in the menu bar with a direct 'Settings...' menu item for quicker access.
  - Change: Reorder the bottom operation buttons to [RENDER] [AUTO] [GLUE]. Buttons use the default colors but their hover color becomes red (0xFFCC3333).
  - Improve: Persist GUI settings across runs (save/load via ExtState so user choices are remembered between sessions).

v251102.0030
  - Changed: Renamed "RENDER SETTINGS" to "PRINTING" for consistency
  - Changed: Reorganized printing options into two-column layout:
      • Left column: FX Processing (Print Take FX, Print Track FX)
      • Right column: Volume Handling (Merge Volumes, Print Volumes)
  - Changed: Updated terminology from "Bake" to "Print" for REAPER standard compliance
  - Improved: More compact layout with parallel columns

v251102.0015
  - Changed: Converted Selection Scope to radio button format for direct visibility
      • Auto / Units / Time Selection / Per Item
  - Changed: Converted Channel Mode to radio button format for direct visibility
      • Auto / Mono / Multi
  - Improved: All options now visible at once without dropdown menus

v251102.0000
  - Changed: Removed Operation mode radio button selection
  - Changed: Replaced single RUN RGWH button with three operation buttons:
      • AUTO (blue) - Smart auto-detection based on selection
      • RENDER (green) - Force single-item render
      • GLUE (orange) - Force multi-item glue
  - Added: Settings window (View > Settings) containing:
      • Timecode Mode
      • Epsilon settings
      • Cue write options
      • Policies (glue single items, no-trackfx policies, rename mode)
      • Debug level and console options
      • Selection Policy
  - Changed: Main GUI now shows only frequently-used parameters:
      • Selection Scope, Channel Mode, Handle
      • Render settings (FX processing, volume handling)
  - Improved: One-click workflow - directly execute operation without mode switching
  - Improved: Color-coded buttons for quick visual identification

v251028_1900
  - Initial GUI implementation
  - All core parameters exposed as visual controls
  - Real-time parameter validation
  - Preset system for common workflows
```
