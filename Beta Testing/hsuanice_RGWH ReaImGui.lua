--[[
@description RGWH GUI - ImGui Interface for RGWH Core
@author hsuanice
@version 0.2.0
@provides
  [main] .

@about
  ImGui-based GUI for configuring and running RGWH Core operations.
  Provides visual controls for all RGWH Wrapper Template parameters.

@usage
  Run this script in REAPER to open the RGWH GUI window.
  Adjust parameters using the visual controls and click operation buttons to execute.

@changelog
  0.2.0 [v260204.2352] - Multi mode hover info + Manual: mono 2ch floor documentation
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

  0.2.0 [v260104.2344] - Multi-Channel Policy Support
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

  0.1.4 [v251225.1835] - Epsilon Removal (Internal Constant)
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
]]--

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------
local r = reaper
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local OS_NAME = r.GetOS()
local IS_WINDOWS = OS_NAME:match("Win") ~= nil
local PATH_SEPARATOR = IS_WINDOWS and ';' or ':'
local DIR_SEPARATOR = package.config:sub(1,1) or '/'

-- Load RGWH Core
local RES_PATH = r.GetResourcePath()
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua'

local ok_load, RGWH = pcall(dofile, CORE_PATH)
if not ok_load or type(RGWH) ~= "table" or type(RGWH.core) ~= "function" then
  r.ShowConsoleMsg(("[RGWH GUI] Failed to load Core at:\n  %s\nError: %s\n")
    :format(CORE_PATH, tostring(RGWH)))
  return
end

------------------------------------------------------------
-- Version Info (auto-extracted from @version tag in header)
------------------------------------------------------------
local VERSION = "unknown"
do
  local info = debug.getinfo(1, "S")
  local script_path = info.source:match("^@(.+)$")
  if script_path then
    local f = io.open(script_path, "r")
    if f then
      for line in f:lines() do
        local ver = line:match("^@version%s+(.+)$")
        if ver then
          VERSION = ver
          break
        end
        -- Stop searching after changelog section starts
        if line:match("^@changelog") then break end
      end
      f:close()
    end
  end
end

------------------------------------------------------------
-- ImGui Context
------------------------------------------------------------
local ctx = ImGui.CreateContext('RGWH GUI')
local font = nil

------------------------------------------------------------
-- GUI State
------------------------------------------------------------
local gui = {
  -- Window state
  open = true,
  show_settings = false,
  show_manual = false,

  -- Operation settings
  op = 0,                    -- 0=auto, 1=render, 2=glue
  selection_scope = 0,       -- 0=auto, 1=units, 2=ts, 3=item
  channel_mode = 0,          -- 0=auto, 1=mono, 2=multi
  multi_channel_policy = 0,  -- 0=source_playback, 1=source_track (for AUTO/MULTI modes)

  -- Render toggles
  take_fx = true,
  track_fx = false,
  tc_mode = 1,              -- 0=previous, 1=current, 2=off

  -- Volume handling
  merge_to_item = false,
  merge_to_take = true,
  print_volumes = false,

  -- Handle settings
  handle_mode = 0,          -- 0=ext, 1=seconds, 2=frames
  handle_length = 5.0,

  -- Cues (v0.1.4: epsilon removed - now internal constant in RGWH Core)
  cue_write_edge = true,
  cue_write_glue = true,

  -- Policies
  glue_single_items = false,  -- AUTO mode: false=single→render, true=single→glue
  glue_no_trackfx_policy = 0,    -- 0=preserve, 1=force_multi
  render_no_trackfx_policy = 0,  -- 0=preserve, 1=force_multi

  -- Debug
  debug_level = 2,           -- 0=silent, 1=normal, 2=verbose
  debug_no_clear = true,

  -- Selection policy (wrapper-only)
  selection_policy = 1,      -- 0=progress, 1=restore, 2=none

  -- UI settings
  enable_docking = false,    -- Allow window docking

  -- Dependencies
  bwfmetaedit_custom_path = "",
  open_bwf_install_popup = false,

  -- Status
  is_running = false,
  last_result = "",
}

-- Persistence namespace and helpers (save/load GUI state)
local P_NS = "hsuanice_RGWH_GUI_state_v1"

local persist_keys = {
  'op','selection_scope','channel_mode','multi_channel_policy',
  'take_fx','track_fx','tc_mode',
  'merge_to_item','merge_to_take','print_volumes',
  'handle_mode','handle_length',
  'epsilon_mode','epsilon_value',
  'cue_write_edge','cue_write_glue',
  'glue_single_items','glue_no_trackfx_policy','render_no_trackfx_policy',
  'debug_level','debug_no_clear','selection_policy',
  'enable_docking','bwfmetaedit_custom_path'
}

local function serialize_gui_state(tbl)
  local parts = {}
  for _,k in ipairs(persist_keys) do
    local v = tbl[k]
    if v == nil then v = '' end
    parts[#parts+1] = k .. '=' .. tostring(v)
  end
  return table.concat(parts, ';')
end

local function deserialize_into_gui(s, tbl)
  if not s or s == '' then return end
  for kv in s:gmatch('[^;]+') do
    local k, v = kv:match('([^=]+)=(.*)')
    if k and v and tbl[k] ~= nil then
      -- try to coerce numeric
      local n = tonumber(v)
      if n then tbl[k] = n
      elseif v == 'true' then tbl[k] = true
      elseif v == 'false' then tbl[k] = false
      else tbl[k] = v end
    end
  end
end

local function save_persist()
  local s = serialize_gui_state(gui)
  reaper.SetExtState(P_NS, 'state', s, true)
end

local function load_persist()
  local s = reaper.GetExtState(P_NS, 'state') or ''
  deserialize_into_gui(s, gui)

  -- Migration: Convert old merge_volumes to merge_to_take
  if gui.merge_volumes ~= nil then
    gui.merge_to_take = gui.merge_volumes
    gui.merge_to_item = false
    gui.merge_volumes = nil
  end
end

local function sync_rgwh_extstate_from_gui()
  local channel_names = { "auto", "mono", "multi" }
  local tc_names = { "previous", "current", "off" }
  local policy_names = { "preserve", "force_multi" }
  local multi_channel_policy_names = { "source_playback", "source_track" }

  local function set_rgwh(key, val)
    r.SetProjExtState(0, "RGWH", key, tostring(val))
  end

  -- Channel/apply mode
  set_rgwh("GLUE_APPLY_MODE", channel_names[gui.channel_mode + 1])
  set_rgwh("RENDER_APPLY_MODE", channel_names[gui.channel_mode + 1])

  -- Multi-Channel Policy (v0.3.0+)
  set_rgwh("MULTI_CHANNEL_POLICY", multi_channel_policy_names[gui.multi_channel_policy + 1])

  -- FX print toggles
  set_rgwh("GLUE_TAKE_FX", gui.take_fx and "1" or "0")
  set_rgwh("GLUE_TRACK_FX", gui.track_fx and "1" or "0")
  set_rgwh("RENDER_TAKE_FX", gui.take_fx and "1" or "0")
  set_rgwh("RENDER_TRACK_FX", gui.track_fx and "1" or "0")

  -- Timecode embed mode (render)
  set_rgwh("RENDER_TC_EMBED", tc_names[gui.tc_mode + 1])

  -- Volume policies (ExtState only supports merge-to-take)
  local merge_to_take = gui.merge_to_take and not gui.merge_to_item
  set_rgwh("RENDER_MERGE_VOLUMES", merge_to_take and "1" or "0")
  set_rgwh("GLUE_MERGE_VOLUMES", merge_to_take and "1" or "0")
  set_rgwh("RENDER_PRINT_VOLUMES", gui.print_volumes and "1" or "0")
  set_rgwh("GLUE_PRINT_VOLUMES", gui.print_volumes and "1" or "0")

  -- Handle/epsilon
  if gui.handle_mode == 1 then
    set_rgwh("HANDLE_MODE", "seconds")
    set_rgwh("HANDLE_SECONDS", gui.handle_length)
  elseif gui.handle_mode == 2 then
    set_rgwh("HANDLE_MODE", "frames")
    set_rgwh("HANDLE_SECONDS", gui.handle_length)
  end

  -- Cues (v0.1.4: epsilon sync removed)
  set_rgwh("WRITE_EDGE_CUES", gui.cue_write_edge and "1" or "0")
  set_rgwh("WRITE_GLUE_CUES", gui.cue_write_glue and "1" or "0")

  -- Policies
  set_rgwh("GLUE_SINGLE_ITEMS", gui.glue_single_items and "1" or "0")
  set_rgwh("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX", policy_names[gui.glue_no_trackfx_policy + 1])
  set_rgwh("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", policy_names[gui.render_no_trackfx_policy + 1])

  -- Debug
  set_rgwh("DEBUG_LEVEL", gui.debug_level)
  set_rgwh("DEBUG_NO_CLEAR", gui.debug_no_clear and "1" or "0")
end

local function parse_state_to_table(s)
  local t = {}
  if not s or s == "" then return t end
  for kv in s:gmatch("[^;]+") do
    local k, v = kv:match("([^=]+)=(.*)")
    if k then
      local n = tonumber(v)
      if n then
        t[k] = n
      elseif v == "true" then
        t[k] = true
      elseif v == "false" then
        t[k] = false
      else
        t[k] = v
      end
    end
  end
  return t
end

local function format_setting_value(key, val)
  if val == nil then return "nil" end

  local bool_keys = {
    take_fx = true, track_fx = true,
    merge_to_item = true, merge_to_take = true, print_volumes = true,
    cue_write_edge = true, cue_write_glue = true, glue_single_items = true,
    debug_no_clear = true, enable_docking = true,
  }

  local op_names = {"Auto", "Render", "Glue"}
  local scope_names = {"Auto", "Units", "Time Selection", "Per Item"}
  local channel_names = {"Auto", "Mono", "Multi"}
  local tc_names = {"Previous", "Current", "Off"}
  local handle_names = {"Use ExtState", "Seconds", "Frames"}
  -- v0.1.4: epsilon_names removed (epsilon is now internal constant)
  local policy_names = {"Preserve", "Force Multi"}
  local multi_channel_policy_names = {"SOURCE-playback", "SOURCE-track"}  -- v0.3.0
  local debug_names = {"Silent", "Normal", "Verbose"}
  local selection_policy_names = {"Progress", "Restore", "None"}

  if bool_keys[key] then
    return val and "ON" or "OFF"
  elseif key == "op" then
    return op_names[val + 1] or tostring(val)
  elseif key == "selection_scope" then
    return scope_names[val + 1] or tostring(val)
  elseif key == "channel_mode" then
    return channel_names[val + 1] or tostring(val)
  elseif key == "multi_channel_policy" then  -- v0.3.0
    return multi_channel_policy_names[val + 1] or tostring(val)
  elseif key == "tc_mode" then
    return tc_names[val + 1] or tostring(val)
  elseif key == "handle_mode" then
    return handle_names[val + 1] or tostring(val)
  elseif key == "glue_no_trackfx_policy" or key == "render_no_trackfx_policy" then  -- v0.1.4: epsilon_mode case removed
    return policy_names[val + 1] or tostring(val)
  elseif key == "debug_level" then
    return debug_names[val + 1] or tostring(val)
  elseif key == "selection_policy" then
    return selection_policy_names[val + 1] or tostring(val)
  elseif key == "handle_length" or key == "epsilon_value" then
    return string.format("%.3f", tonumber(val) or 0)
  end

  return tostring(val)
end

local function log_setting_changes(before_state, after_state)
  if gui.debug_level < 1 then return end

  local before = parse_state_to_table(before_state)
  local after = parse_state_to_table(after_state)

  local labels = {
    op = "Operation",
    selection_scope = "Selection Scope",
    channel_mode = "Channel Mode",
    take_fx = "Print Take FX",
    track_fx = "Print Track FX",
    tc_mode = "Timecode Mode",
    merge_to_item = "Merge to Item",
    merge_to_take = "Merge to Take",
    print_volumes = "Print Volumes",
    handle_mode = "Handle Mode",
    handle_length = "Handle Length",
    cue_write_edge = "Write Edge Cues",
    cue_write_glue = "Write Glue Cues",
    glue_single_items = "Glue Single Items",
    glue_no_trackfx_policy = "Glue No-TrackFX Policy",
    render_no_trackfx_policy = "Render No-TrackFX Policy",
    debug_level = "Debug Level",
    debug_no_clear = "No Clear Console",
    selection_policy = "Selection Policy",
    enable_docking = "Enable Window Docking",
    bwfmetaedit_custom_path = "BWF MetaEdit Custom Path",
  }

  for _, key in ipairs(persist_keys) do
    if before[key] ~= after[key] then
      local label = labels[key] or key
      local before_val = format_setting_value(key, before[key])
      local after_val = format_setting_value(key, after[key])
      r.ShowConsoleMsg(string.format("[RGWH GUI] %s: %s -> %s\n", label, before_val, after_val))
    end
  end
end

local function handle_state_change(before_state, after_state)
  if after_state == before_state then return end
  save_persist()
  sync_rgwh_extstate_from_gui()
  log_setting_changes(before_state, after_state)
end

------------------------------------------------------------
-- BWF MetaEdit CLI Detection
------------------------------------------------------------
local bwf_cli = {
  checked = false,
  available = false,
  resolved_path = "",
  message = "",
  last_source = "",
  attempts = {},
  warning_dismissed = false,
}

local function trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$") or ""
end

local function sanitize_bwf_custom_path(path)
  local v = trim(path or "")
  v = v:gsub('^"(.*)"$', '%1')
  v = v:gsub("^'(.*)'$", "%1")
  return v
end

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function join_path(base, fragment)
  if base == "" then return fragment end
  local last = base:sub(-1)
  if last == '/' or last == '\\' then
    return base .. fragment
  end
  local sep = DIR_SEPARATOR == "\\" and "\\" or "/"
  return base .. sep .. fragment
end

local function check_bwfmetaedit(force)
  if bwf_cli.checked and not force then return end
  bwf_cli.checked = true
  if force then bwf_cli.warning_dismissed = false end

  local custom = sanitize_bwf_custom_path(gui.bwfmetaedit_custom_path or "")
  gui.bwfmetaedit_custom_path = custom

  local attempted = {}
  local found_path, source_label
  local binary_names = IS_WINDOWS and { "bwfmetaedit.exe", "bwfmetaedit" } or { "bwfmetaedit" }

  local function register_attempt(path)
    if path and path ~= "" then
      attempted[#attempted+1] = path
    end
  end

  local function try_candidate(path, label)
    if found_path or not path or path == "" then return false end
    register_attempt(path)
    if file_exists(path) then
      found_path = path
      source_label = label or path
      return true
    end
    return false
  end

  if custom ~= "" then
    try_candidate(custom, "自訂路徑")
    if IS_WINDOWS and not found_path and not custom:lower():match("%.exe$") then
      try_candidate(custom .. ".exe", "自訂路徑 (.exe)")
    end
  end

  local path_env = os.getenv(IS_WINDOWS and "Path" or "PATH") or ""
  if not found_path and path_env ~= "" then
    local pattern = string.format("([^%s]+)", PATH_SEPARATOR)
    for dir in path_env:gmatch(pattern) do
      dir = trim(dir:gsub('"', ''))
      if dir ~= "" then
        for _, name in ipairs(binary_names) do
          try_candidate(join_path(dir, name), "PATH: " .. dir)
          if found_path then break end
        end
      end
      if found_path then break end
    end
  end

  local fallback_dirs = {}
  if IS_WINDOWS then
    local pf = os.getenv("ProgramFiles")
    local pf86 = os.getenv("ProgramFiles(x86)")
    if pf then fallback_dirs[#fallback_dirs+1] = join_path(pf, "BWF MetaEdit") end
    if pf86 then fallback_dirs[#fallback_dirs+1] = join_path(pf86, "BWF MetaEdit") end
  else
    fallback_dirs = { "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/local/bin" }
  end
  if not found_path then
    for _, dir in ipairs(fallback_dirs) do
      for _, name in ipairs(binary_names) do
        try_candidate(join_path(dir, name), dir)
        if found_path then break end
      end
      if found_path then break end
    end
  end

  bwf_cli.attempts = attempted
  if found_path then
    bwf_cli.available = true
    bwf_cli.resolved_path = found_path
    bwf_cli.last_source = source_label or ""
    bwf_cli.message = string.format("BWF MetaEdit CLI ready (%s)", source_label or found_path)
  else
    bwf_cli.available = false
    bwf_cli.resolved_path = ""
    if custom ~= "" then
      bwf_cli.message = "Custom BWF MetaEdit CLI path not found. Please verify the file exists."
    else
      bwf_cli.message = "No 'bwfmetaedit' binary detected. BWF TimeReference embedding is currently disabled."
    end
  end
end

-- Helper function to print all current settings to console
local function print_all_settings(prefix)
  prefix = prefix or "[RGWH GUI]"

  local function bool_str(v) return v and "ON" or "OFF" end

  local op_names = {"Auto", "Render", "Glue"}
  local scope_names = {"Auto", "Units", "Time Selection", "Per Item"}
  local channel_names = {"Auto", "Mono", "Multi"}
  local tc_names = {"Previous", "Current", "Off"}
  local handle_names = {"Use ExtState", "Seconds", "Frames"}
  -- v0.1.4: epsilon_names removed (epsilon is now internal constant)
  local policy_names = {"Preserve", "Force Multi"}
  local multi_channel_policy_names = {"SOURCE-playback", "SOURCE-track"}  -- v0.3.0
  local debug_names = {"Silent", "Normal", "Verbose"}
  local selection_policy_names = {"Progress", "Restore", "None"}

  r.ShowConsoleMsg("========================================\n")
  r.ShowConsoleMsg(string.format("%s settings:\n", prefix))
  r.ShowConsoleMsg("========================================\n")

  r.ShowConsoleMsg(string.format("  Operation: %s\n", op_names[gui.op + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Selection Scope: %s\n", scope_names[gui.selection_scope + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Channel Mode: %s\n", channel_names[gui.channel_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Multi-Channel Policy: %s\n", multi_channel_policy_names[gui.multi_channel_policy + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Take FX: %s\n", bool_str(gui.take_fx)))
  r.ShowConsoleMsg(string.format("  Track FX: %s\n", bool_str(gui.track_fx)))
  r.ShowConsoleMsg(string.format("  TC Mode: %s\n", tc_names[gui.tc_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Merge Volumes: %s\n", bool_str(gui.merge_volumes)))
  r.ShowConsoleMsg(string.format("  Print Volumes: %s\n", bool_str(gui.print_volumes)))
  r.ShowConsoleMsg(string.format("  Handle Mode: %s\n", handle_names[gui.handle_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Handle Length: %.2f\n", gui.handle_length))
  -- v0.1.4: Epsilon debug output removed (now internal constant: 0.1 frames)
  r.ShowConsoleMsg(string.format("  Write Edge Cues: %s\n", bool_str(gui.cue_write_edge)))
  r.ShowConsoleMsg(string.format("  Write Glue Cues: %s\n", bool_str(gui.cue_write_glue)))
  r.ShowConsoleMsg(string.format("  Glue Single Items: %s\n", bool_str(gui.glue_single_items)))
  r.ShowConsoleMsg(string.format("  Glue No-TrackFX Policy: %s\n", policy_names[gui.glue_no_trackfx_policy + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Render No-TrackFX Policy: %s\n", policy_names[gui.render_no_trackfx_policy + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Debug Level: %s\n", debug_names[gui.debug_level + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Debug No Clear: %s\n", bool_str(gui.debug_no_clear)))
  r.ShowConsoleMsg(string.format("  Selection Policy: %s\n", selection_policy_names[gui.selection_policy + 1] or "Unknown"))

  r.ShowConsoleMsg("========================================\n")
end

-- call load immediately so gui gets initial persisted values
load_persist()
sync_rgwh_extstate_from_gui()
check_bwfmetaedit(true)

-- If debug level >= 1, print settings on startup
if gui.debug_level >= 1 then
  print_all_settings("[RGWH GUI - STARTUP]")
end

------------------------------------------------------------
-- Helper Functions
------------------------------------------------------------

-- Selection Snapshot/Restore (from Wrapper Template)
local function track_guid(tr)
  local ok, guid = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  return ok and guid or nil
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for t = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, t)
    local ok, g = r.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
    if ok and g == guid then return tr end
  end
  return nil
end

local function seconds_epsilon_from_args(args)
  if type(args.epsilon) == "table" then
    if args.epsilon.mode == "seconds" then
      return tonumber(args.epsilon.value) or 0.02
    elseif args.epsilon.mode == "frames" then
      local fps = r.TimeMap_curFrameRate(0) or 30
      return (tonumber(args.epsilon.value) or 0) / fps
    end
  end
  return 0.02
end

local function snapshot_selection()
  local s = {}

  -- items
  s.items = {}
  for i = 0, r.CountSelectedMediaItems(0)-1 do
    local it  = r.GetSelectedMediaItem(0, i)
    local tr  = it and r.GetMediaItem_Track(it) or nil
    local tgd = tr and track_guid(tr) or nil
    local pos = it and r.GetMediaItemInfo_Value(it, "D_POSITION") or nil
    local len = it and r.GetMediaItemInfo_Value(it, "D_LENGTH")   or nil
    s.items[#s.items+1] = {
      ptr      = it,
      tr       = tr,
      tr_guid  = tgd,
      start    = pos,
      finish   = (pos and len) and (pos + len) or nil,
    }
  end

  -- tracks
  s.tracks = {}
  for t = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, t)
    if r.IsTrackSelected(tr) then
      s.tracks[#s.tracks+1] = tr
    end
  end

  -- time selection
  s.ts_start, s.ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

  -- edit cursor
  s.edit_pos = r.GetCursorPosition()

  return s
end

local function restore_selection(s, args)
  if not s then return end

  -- items (smart restore)
  r.SelectAllMediaItems(0, false)
  if s.items then
    local eps = seconds_epsilon_from_args(args)
    -- Check if TS exists for smart TS-aware restore (use snapshot TS, not current TS)
    local tsL, tsR = s.ts_start, s.ts_end
    local has_ts = (tsL and tsR and tsR > tsL)

    for _, desc in ipairs(s.items) do
      local selected = false

      -- When TS exists and may have caused splits, verify pointer still matches original position
      if has_ts and desc.ptr and r.ValidatePtr2(0, desc.ptr, "MediaItem*") then
        local p = r.GetMediaItemInfo_Value(desc.ptr, "D_POSITION")
        local l = r.GetMediaItemInfo_Value(desc.ptr, "D_LENGTH")
        -- Check if position/length still matches original (within epsilon)
        if math.abs(p - desc.start) < eps and math.abs((p + l) - desc.finish) < eps then
          r.SetMediaItemSelected(desc.ptr, true)
          selected = true
        end
        -- If position changed (due to split), fall through to TS-aware restore
      elseif desc.ptr and r.ValidatePtr2(0, desc.ptr, "MediaItem*") then
        -- No TS: simple pointer restore
        r.SetMediaItemSelected(desc.ptr, true)
        selected = true
      end

      if not selected then
        -- fallback: match by same-track + time overlap
        local tr = desc.tr
        if (not tr or not r.ValidatePtr2(0, tr, "MediaTrack*")) and desc.tr_guid then
          tr = find_track_by_guid(desc.tr_guid)
        end
        if tr and desc.start and desc.finish then
          local N = r.CountTrackMediaItems(tr)
          local best_item = nil
          local best_overlap = 0

          -- When TS exists, prefer items that overlap with TS (smart TS-aware restore)
          if has_ts then
            for i = 0, N - 1 do
              local it2 = r.GetTrackMediaItem(tr, i)
              local p   = r.GetMediaItemInfo_Value(it2, "D_POSITION")
              local l   = r.GetMediaItemInfo_Value(it2, "D_LENGTH")
              local q1, q2 = p, p + l
              local a1, a2 = desc.start - eps, desc.finish + eps

              -- Check overlap with original item
              if (q1 < a2) and (q2 > a1) then
                -- Calculate overlap with TS
                local ts_overlap_start = math.max(q1, tsL)
                local ts_overlap_end = math.min(q2, tsR)
                local ts_overlap = math.max(0, ts_overlap_end - ts_overlap_start)

                -- Prefer items with maximum TS overlap
                if ts_overlap > best_overlap then
                  best_item = it2
                  best_overlap = ts_overlap
                end
              end
            end
            if best_item then
              r.SetMediaItemSelected(best_item, true)
            end
          else
            -- No TS: use original logic (first overlap)
            for i = 0, N - 1 do
              local it2 = r.GetTrackMediaItem(tr, i)
              local p   = r.GetMediaItemInfo_Value(it2, "D_POSITION")
              local l   = r.GetMediaItemInfo_Value(it2, "D_LENGTH")
              local q1, q2 = p, p + l
              local a1, a2 = desc.start - eps, desc.finish + eps
              if (q1 < a2) and (q2 > a1) then
                r.SetMediaItemSelected(it2, true)
                break
              end
            end
          end
        end
      end
    end
  end

  -- tracks
  for t = 0, r.CountTracks(0)-1 do
    r.SetTrackSelected(r.GetTrack(0, t), false)
  end
  if s.tracks then
    for _, tr in ipairs(s.tracks) do
      if r.ValidatePtr2(0, tr, "MediaTrack*") then
        r.SetTrackSelected(tr, true)
      end
    end
  end

  -- time selection
  if s.ts_start and s.ts_end then
    r.GetSet_LoopTimeRange2(0, true, false, s.ts_start, s.ts_end, false)
  end

  -- edit cursor
  if s.edit_pos then
    r.SetEditCurPos(s.edit_pos, false, false)
  end
end

local function build_args_from_gui(operation)
  -- Map GUI state to RGWH Core args format
  -- operation: "render", "auto", or "glue"
  local channel_names = { "auto", "mono", "multi" }
  local tc_names = { "previous", "current", "off" }
  local policy_names = { "preserve", "force_multi" }

  -- Determine op and selection_scope based on button clicked
  local op, selection_scope, glue_single_items
  if operation == "render" then
    op = "render"
    selection_scope = "item"  -- Always per-item
    glue_single_items = false  -- Not applicable for render
  elseif operation == "auto" then
    op = "auto"
    selection_scope = "auto"  -- Let Core auto-detect units vs ts (single→render, multi→glue)
    glue_single_items = false  -- AUTO mode: single item → render
  elseif operation == "glue" then
    op = "glue"
    selection_scope = "auto"  -- Let Core auto-detect units vs ts (always glue, including single)
    glue_single_items = true   -- GLUE mode: always glue (including single items)
  end

  local args = {
    op = op,
    selection_scope = selection_scope,
    channel_mode = channel_names[gui.channel_mode + 1],

    take_fx = gui.take_fx,
    track_fx = gui.track_fx,
    tc_mode = tc_names[gui.tc_mode + 1],

    merge_volumes = gui.merge_to_take,  -- Core still uses merge_volumes for merge to take
    merge_to_item = gui.merge_to_item,
    print_volumes = gui.print_volumes,

    cues = {
      write_edge = gui.cue_write_edge,
      write_glue = gui.cue_write_glue,
    },

    policies = {
      glue_single_items = glue_single_items,  -- Use the mode-specific value
      glue_no_trackfx_output_policy = policy_names[gui.glue_no_trackfx_policy + 1],
      render_no_trackfx_output_policy = policy_names[gui.render_no_trackfx_policy + 1],
    },
  }

  -- Handle
  if gui.handle_mode == 0 then
    args.handle = "ext"
  elseif gui.handle_mode == 1 then
    args.handle = { mode = "seconds", seconds = gui.handle_length }
  else -- frames
    local fps = r.TimeMap_curFrameRate(0) or 30
    args.handle = { mode = "seconds", seconds = gui.handle_length / fps }
  end

  -- Debug (v0.1.4: epsilon removed - now internal constant)
  args.debug = {
    level = gui.debug_level,
    no_clear = gui.debug_no_clear,
  }

  return args
end

local function run_rgwh(operation)
  if gui.is_running then return end

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  -- Build args based on which button was clicked
  local args = build_args_from_gui(operation)

  -- Selection policy handling (wrapper logic)
  local policy_names = { "progress", "restore", "none" }
  local policy = policy_names[gui.selection_policy + 1]

  -- Snapshot BEFORE (if restore policy)
  local sel_before = nil
  if policy == "restore" then
    sel_before = snapshot_selection()
  end

  -- Clear console if needed
  if args.debug and args.debug.no_clear == false then
    r.ClearConsole()
  end

  -- Run Core
  local ok, err = RGWH.core(args)

  -- Post-run handling
  if policy == "restore" and sel_before then
    restore_selection(sel_before, args)
  elseif policy == "none" then
    r.SelectAllMediaItems(0, false)
  end
  -- "progress": do nothing, keep Core's selections

  r.UpdateArrange()

  if ok then
    gui.last_result = "Success!"
  else
    local err_msg = "Error: " .. tostring(err)
    gui.last_result = err_msg
    -- Also print error to console so user can copy it
    r.ShowConsoleMsg("\n" .. string.rep("=", 60) .. "\n")
    r.ShowConsoleMsg("[RGWH GUI] ERROR:\n")
    r.ShowConsoleMsg(err_msg .. "\n")
    r.ShowConsoleMsg(string.rep("=", 60) .. "\n")
  end

  r.PreventUIRefresh(-1)
  local operation_names = {
    glue = "Glue",
    render = "Render",
    window = "Window",
    handle = "Handle"
  }
  local op_label = operation_names[operation] or operation
  r.Undo_EndBlock(string.format("RGWH GUI: %s", op_label), -1)

  gui.is_running = false
end

------------------------------------------------------------
-- GUI Rendering
------------------------------------------------------------
local function draw_section_header(label)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, label)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)
end

local function draw_help_marker(desc)
  ImGui.SameLine(ctx)
  ImGui.TextDisabled(ctx, '(?)')
  if ImGui.BeginItemTooltip(ctx) then
    ImGui.PushTextWrapPos(ctx, ImGui.GetFontSize(ctx) * 35.0)
    ImGui.Text(ctx, desc)
    ImGui.PopTextWrapPos(ctx)
    ImGui.EndTooltip(ctx)
  end
end

local BWF_INSTALL_POPUP_ID = 'BWF MetaEdit CLI Install Guide'
local BREW_INSTALL_CMD = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
local BREW_BWF_CMD = 'brew install bwfmetaedit'
local BWF_VERIFY_CMD = 'bwfmetaedit --version'

local function draw_bwfmetaedit_warning_banner()
  if bwf_cli.available or bwf_cli.warning_dismissed then return end

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF6666FF)
  ImGui.Text(ctx, "BWF MetaEdit CLI missing – Timecode embedding is disabled.")
  ImGui.PopStyleColor(ctx)

  ImGui.TextWrapped(ctx,
    "RGWH relies on the bwfmetaedit CLI to embed BWF TimeReference (timecode).\n" ..
    "All other features stay available, but TC embedding remains off until the CLI is installed.")
  if bwf_cli.message ~= "" then
    ImGui.TextDisabled(ctx, bwf_cli.message)
  end

  if ImGui.Button(ctx, "Install Guide##warn") then
    gui.open_bwf_install_popup = true
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Re-check##warn") then
    check_bwfmetaedit(true)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remind Me Later##warn") then
    bwf_cli.warning_dismissed = true
  end
  ImGui.Spacing(ctx)
end

local function draw_bwfmetaedit_install_modal()
  if gui.open_bwf_install_popup then
    ImGui.SetNextWindowSize(ctx, 520, 0, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, BWF_INSTALL_POPUP_ID)
    gui.open_bwf_install_popup = false
  end

  if ImGui.BeginPopupModal(ctx, BWF_INSTALL_POPUP_ID, true, ImGui.WindowFlags_AlwaysAutoResize) then
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.TextColored(ctx, 0x00AAFFFF, "Why is this required?")
    ImGui.TextWrapped(ctx,
      "AudioSweet / RGWH calls the BWF MetaEdit CLI to write BWF TimeReference (timecode) back into media files.\n" ..
      "Without the CLI, timecode embedding stays disabled. The steps below cover a Homebrew-based installation on macOS:")
    ImGui.Spacing(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 1: Install Homebrew (if missing)")
    ImGui.TextWrapped(ctx, "Open Terminal, run the command below, and follow the on-screen instructions to complete the Homebrew install:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##brew_install_cmd", BREW_INSTALL_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##copy_brew_install") then
      r.ImGui_SetClipboardText(ctx, BREW_INSTALL_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Reference: https://brew.sh")
    ImGui.Separator(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 2: Install BWF MetaEdit CLI")
    ImGui.TextWrapped(ctx, "After Homebrew completes, install the CLI by running:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##brew_bwf_cmd", BREW_BWF_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##copy_bwf") then
      r.ImGui_SetClipboardText(ctx, BREW_BWF_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Binary will normally be placed in /opt/homebrew/bin")
    ImGui.Separator(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 3: Verify the CLI")
    ImGui.TextWrapped(ctx, "Run the following to confirm it responds with a version string:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##brew_verify_cmd", BWF_VERIFY_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##copy_verify") then
      r.ImGui_SetClipboardText(ctx, BWF_VERIFY_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Version output confirms success")
    ImGui.Spacing(ctx)

    ImGui.TextWrapped(ctx,
      "Once installed, return to the RGWH / AudioSweet settings panel and click \"Re-check CLI\" to re-enable TC embedding.\n" ..
      "Windows users (or anyone not using Homebrew) can download installers from MediaArea: https://mediaarea.net/BWFMetaEdit")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Close", 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

local function draw_settings_popup()
  if not gui.show_settings then return end

  local before_state = serialize_gui_state(gui)

  ImGui.SetNextWindowSize(ctx, 500, 600, ImGui.Cond_FirstUseEver)
  -- Disable docking for settings window
  local settings_flags = ImGui.WindowFlags_NoDocking
  local visible, open = ImGui.Begin(ctx, 'Settings', true, settings_flags)
  if not visible then
    ImGui.End(ctx)
    gui.show_settings = open
    return
  end

  -- Close settings window with ESC (only if focused, don't close main GUI)
  if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    open = false
  end

  ImGui.PushItemWidth(ctx, 200)
  local rv, new_val

  -- === TIMECODE MODE (RENDER ONLY) ===
  draw_section_header("TIMECODE MODE (RENDER only)")
  rv, new_val = ImGui.Combo(ctx, "Timecode Mode", gui.tc_mode, "Previous\0Current\0Off\0")
  if rv then gui.tc_mode = new_val end
  draw_help_marker("BWF TimeReference embed mode for RENDER operations\n\nNote: GLUE mode always uses 'Current' (technical requirement)")

  -- === BWF METAEDIT CLI ===
  draw_section_header("BWF METAEDIT CLI (Timecode Embed)")
  if bwf_cli.available then
    ImGui.TextColored(ctx, 0x55FF55FF, ("CLI detected: %s"):format(bwf_cli.resolved_path))
    if bwf_cli.last_source ~= "" then
      ImGui.TextDisabled(ctx, ("Source: %s"):format(bwf_cli.last_source))
    end
  else
    ImGui.TextColored(ctx, 0xFF6666FF, "bwfmetaedit CLI not detected – embedding stays disabled.")
    if bwf_cli.message ~= "" then
      ImGui.TextWrapped(ctx, bwf_cli.message)
    end
  end

  local rv_path, new_path = ImGui.InputText(ctx, "Custom CLI Path (optional)", gui.bwfmetaedit_custom_path)
  if rv_path then gui.bwfmetaedit_custom_path = new_path end
  draw_help_marker("Leave blank to use PATH. Otherwise provide the full bwfmetaedit binary path (include .exe on Windows).")

  if ImGui.Button(ctx, "Re-check CLI##settings") then
    check_bwfmetaedit(true)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Install Guide##settings") then
    gui.open_bwf_install_popup = true
  end

  -- === CUES === (v0.1.4: epsilon section removed - now internal constant 0.5 frames)
  draw_section_header("CUES")
  rv, new_val = ImGui.Checkbox(ctx, "Write Edge Cues", gui.cue_write_edge)
  if rv then gui.cue_write_edge = new_val end
  draw_help_marker("#in/#out edge cues as media cues")

  rv, new_val = ImGui.Checkbox(ctx, "Write Glue Cues", gui.cue_write_glue)
  if rv then gui.cue_write_glue = new_val end
  draw_help_marker("#Glue: <TakeName> cues when sources change")

  -- === POLICIES ===
  draw_section_header("POLICIES")

  rv, new_val = ImGui.Combo(ctx, "Glue No-TrackFX Policy", gui.glue_no_trackfx_policy, "Preserve\0Force Multi\0")
  if rv then gui.glue_no_trackfx_policy = new_val end

  rv, new_val = ImGui.Combo(ctx, "Render No-TrackFX Policy", gui.render_no_trackfx_policy, "Preserve\0Force Multi\0")
  if rv then gui.render_no_trackfx_policy = new_val end

  -- === DEBUG ===
  draw_section_header("DEBUG")
  rv, new_val = ImGui.SliderInt(ctx, "Debug Level", gui.debug_level, 0, 2,
    gui.debug_level == 0 and "Silent" or (gui.debug_level == 1 and "Normal" or "Verbose"))
  if rv then gui.debug_level = new_val end

  rv, new_val = ImGui.Checkbox(ctx, "No Clear Console", gui.debug_no_clear)
  if rv then gui.debug_no_clear = new_val end

  -- === SELECTION POLICY ===
  draw_section_header("SELECTION POLICY")
  rv, new_val = ImGui.Combo(ctx, "Selection Policy", gui.selection_policy, "Progress\0Restore\0None\0")
  if rv then gui.selection_policy = new_val end
  draw_help_marker("progress: keep in-run selections\nrestore: restore original selection\nnone: clear all")

  -- persist if changed
  local after_state = serialize_gui_state(gui)
  handle_state_change(before_state, after_state)

  ImGui.PopItemWidth(ctx)
  ImGui.End(ctx)
  gui.show_settings = open
end

------------------------------------------------------------
-- Manual Window (Operation Modes Guide)
------------------------------------------------------------
local function draw_manual_window()
  if not gui.show_manual then return end

  ImGui.SetNextWindowSize(ctx, 900, 700, ImGui.Cond_FirstUseEver)
  -- Disable docking for manual window
  local manual_flags = ImGui.WindowFlags_NoDocking
  local visible, open = ImGui.Begin(ctx, 'RGWH Manual - Operation Modes', true, manual_flags)
  if not visible then
    ImGui.End(ctx)
    gui.show_manual = open
    return
  end

  -- Close manual window with ESC (only if focused, don't close main GUI)
  if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    open = false
  end

  -- Title
  ImGui.TextColored(ctx, 0x00AAFFFF, "RGWH Core - Operation Modes Guide")
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  -- Tab bar for different sections
  if ImGui.BeginTabBar(ctx, 'ManualTabs') then

    -- === OVERVIEW TAB ===
    if ImGui.BeginTabItem(ctx, 'Overview') then
      ImGui.TextWrapped(ctx,
        "RGWH Core provides comprehensive audio processing with handle-aware workflows.\n" ..
        "This overview covers all features and their implementations."
      )
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === CHANNEL MODE ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "1. CHANNEL MODE")
      ImGui.Spacing(ctx)
      if ImGui.BeginTable(ctx, 'ChannelTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Mode')
        ImGui.TableSetupColumn(ctx, 'Implementation')
        ImGui.TableSetupColumn(ctx, 'Behavior')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Auto')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Per-item/unit detection')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Mono source → mono (40361)\nMulti source → policy-based (40209/41993)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Mono')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Action 40361')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Force mono output for all items')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Multi')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Policy-based')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'SOURCE-playback: 40209 (preserve ch, 2ch floor)\nSOURCE-track: 41993 (match track ch)')

        ImGui.EndTable(ctx)
      end

      ImGui.Spacing(ctx)
      ImGui.TextColored(ctx, 0xFF8800FF, "Multi-Channel Policy (AUTO / MULTI):")
      ImGui.Indent(ctx)
      ImGui.BulletText(ctx, "SOURCE-playback (40209): Preserves item playback channels (4ch→4ch, 6ch→6ch)")
      ImGui.BulletText(ctx, "SOURCE-track (41993): Forces output to match track I_NCHAN")
      ImGui.Spacing(ctx)
      ImGui.TextColored(ctx, 0xFF0000FF, "Mono items in MULTI mode:")
      ImGui.BulletText(ctx, "Action 40209 has a 2ch floor — mono items output stereo (2ch)")
      ImGui.BulletText(ctx, "AUTO mode detects mono items and uses 40361 → true 1ch output")
      ImGui.BulletText(ctx, "If you need mono items to stay mono, use AUTO mode instead")
      ImGui.Unindent(ctx)

      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === FX PROCESSING ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "2. FX PROCESSING")
      ImGui.Spacing(ctx)
      if ImGui.BeginTable(ctx, 'FXTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'FX Type')
        ImGui.TableSetupColumn(ctx, 'Control')
        ImGui.TableSetupColumn(ctx, 'Notes')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Track FX')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'TrackFX_SetEnabled()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Enable/disable before apply, restore after')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Take FX')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'TakeFX_SetEnabled()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Enable/disable before apply, restore after')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Apply Actions')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '40361 / 40209 / 41993')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Mono (40361) / Preserve (40209) / Track ch (41993)')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === VOLUME RENDERING ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "3. VOLUME RENDERING (Bidirectional)")
      ImGui.Spacing(ctx)

      if ImGui.BeginTable(ctx, 'VolumeTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Merge Mode')
        ImGui.TableSetupColumn(ctx, 'Print OFF')
        ImGui.TableSetupColumn(ctx, 'Print ON')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Merge to Item')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Combine take vol to item vol\n• Result: Same final volume\n• Compensates other takes\n• Volume stays at item level')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Combine take vol to item vol\n• Result: Same final volume\n• Compensates other takes\n• Prints into audio (all → 0dB)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Merge to Take')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Combine item vol to take vol\n• Result: Same final volume\n• Merges ALL takes\n• Volume stays at take level')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Combine item vol to take vol\n• Result: Same final volume\n• Merges ALL takes\n• Prints into audio (all → 0dB)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'OFF (neither)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'REAPER native behavior\n• Item/take vols unchanged\n• Take vol printed to audio\n• Item vol preserved')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'N/A\nPrint disabled')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0x00FF00FF, "Technical Details:")
      ImGui.Indent(ctx)
      ImGui.BulletText(ctx, "REAPER renders with item × take volume (not just take)")
      ImGui.BulletText(ctx, "Print OFF: Both set to 1.0 during render to preserve original audio level")
      ImGui.BulletText(ctx, "After render: Volume restored to target (item or take) based on merge mode")
      ImGui.BulletText(ctx, "Merge modes are mutually exclusive (radio button behavior)")
      ImGui.Unindent(ctx)
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFF0000FF, "Important Note:")
      ImGui.BulletText(ctx, "GLUE mode always forces merge to take + print (technical requirement)")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "• Reason: When merging multiple items into one, volume relationships must be preserved\n" ..
        "• RENDER mode respects your Merge/Print settings\n" ..
        "• GLUE mode ignores these settings and always merges item volume into take volume")
      ImGui.Unindent(ctx)
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === HANDLE PROCESSING ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "4. HANDLE PROCESSING")
      ImGui.Spacing(ctx)
      if ImGui.BeginTable(ctx, 'HandleTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Feature')
        ImGui.TableSetupColumn(ctx, 'Implementation')
        ImGui.TableSetupColumn(ctx, 'Behavior')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Handle Extension')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'D_POSITION, D_LENGTH')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Extend item/unit by handle amount (seconds/frames)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Clamp-to-Source')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'GetMediaSourceLength()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Prevent extending beyond source boundaries')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Handle as Offset')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'D_STARTOFFS')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Store handle in take offset after processing')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === MEDIA CUES ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "5. MEDIA CUES")
      ImGui.Spacing(ctx)
      if ImGui.BeginTable(ctx, 'CueTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Cue Type')
        ImGui.TableSetupColumn(ctx, 'Implementation')
        ImGui.TableSetupColumn(ctx, 'Format')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Edge Cues')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'AddProjectMarker2()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '#in / #out at item boundaries')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Glue Cues')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'AddProjectMarker2()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '#Glue: <TakeName> when sources change')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'BWF TimeReference')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'SetMediaItemTakeInfo()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'P_TRACK:BWF_TIMEREF (embed TC in file)')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === KEY ACTIONS ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "6. KEY REAPER ACTIONS")
      ImGui.Spacing(ctx)
      if ImGui.BeginTable(ctx, 'ActionTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Action ID')
        ImGui.TableSetupColumn(ctx, 'Name')
        ImGui.TableSetupColumn(ctx, 'Usage')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, '40361')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Apply track/take FX (mono)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Channel mode: Mono')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, '41993')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Apply track/take FX (multi)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Channel mode: Multi')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, '42432')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Glue items within time selection')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'GLUE mode: merge items')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, '40640')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Remove FX for item take')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Clean up after apply (preserve)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, '41121')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Trim items to time selection')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Trim back to original boundaries')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === NAMING CONVENTIONS ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "7. NAMING CONVENTIONS")
      ImGui.Spacing(ctx)
      if ImGui.BeginTable(ctx, 'NamingTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Mode')
        ImGui.TableSetupColumn(ctx, 'Format')
        ImGui.TableSetupColumn(ctx, 'Example')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'RENDER')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'TakeName-renderedN')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Dialogue-rendered1')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'GLUE')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'TakeName-glued-XX.wav')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Dialogue-glued-01.wav')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)
      ImGui.TextColored(ctx, 0xFF0000FF, "Important:")
      ImGui.BulletText(ctx, "RENDER: N = incremental based on existing rendered takes (1,2,3...)")
      ImGui.BulletText(ctx, "GLUE: XX = REAPER native auto-increment (01,02,03...)")
      ImGui.BulletText(ctx, "Both modes preserve original take names in the final output")
      ImGui.Spacing(ctx)

      ImGui.EndTabItem(ctx)
    end

    -- === RENDER TAB ===
    if ImGui.BeginTabItem(ctx, 'RENDER Mode') then
      ImGui.TextColored(ctx, 0x00AAFFFF, "Entry Point:")
      ImGui.BulletText(ctx, "M.render_selection(take_fx, track_fx, mode, tc_mode, merge_volumes, print_volumes)")
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0x00AAFFFF, "Process Flow (Function Calls):")
      ImGui.Spacing(ctx)

      if ImGui.BeginTable(ctx, 'RenderFlowTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Step')
        ImGui.TableSetupColumn(ctx, 'Function')
        ImGui.TableSetupColumn(ctx, 'Action')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '1. Snapshot Take FX')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'snapshot_takefx_offline()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Save take FX offline states')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '2. Volume Pre')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'preprocess_item_volumes()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Merge/snapshot volumes')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '3. Extend Window')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'per_member_window_lr()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Extend by handle, clamp to source')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '4. Add Cue Markers')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'add_edge_cues()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Add #in/#out markers')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '5. Snapshot Fades')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'snapshot_fades()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Save fade settings (if Apply)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '6. Zero Fades')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'zero_fades()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Clear fades (if Apply)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '7. Apply/Render')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Main_OnCommand()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Action 40361/41993/40601')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '8. Remove Cue Markers')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'remove_markers_by_ids()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Remove temporary markers')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '9. Restore Fades')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'restore_fades()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Restore fade settings')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '10. Trim Back')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'SetMediaItemInfo_Value()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Restore position + D_STARTOFFS')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '11. Volume Post')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'postprocess_item_volumes()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Restore volumes if print=false')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '12. Rename')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'rename_new_render_take()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Apply naming convention')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '13. Clone Take FX')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'clone_takefx_chain()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Clone FX to new take (if excluded)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '14. Embed TC')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'embed_current_tc_for_item()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Embed BWF TimeReference')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFFFF00FF, "Use Cases:")
      ImGui.BulletText(ctx, "Keep takes: Process single items, preserve original takes")
      ImGui.BulletText(ctx, "Handle-aware: Extend items with handles for safety margin")
      ImGui.BulletText(ctx, "BWF TimeReference: Embed timecode in rendered files")
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFF0000FF, "Important Technical Notes:")
      ImGui.BulletText(ctx, "Does NOT merge multiple items (use GLUE for that)")
      ImGui.BulletText(ctx, "Take naming convention:")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "• RENDER always renames new takes to 'TakeName-renderedN' format\n" ..
        "• N = incremental number (1, 2, 3...) based on existing rendered takes on the item\n" ..
        "• Purpose: Distinguish between original take and multiple render iterations\n" ..
        "• Example: 'Dialogue-rendered1', 'Dialogue-rendered2'\n" ..
        "• This is a fixed behavior and cannot be changed")
      ImGui.Unindent(ctx)
      ImGui.BulletText(ctx, "Fade handling issue with Actions 40361/41993:")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "• Problem: Apply actions (40361/41993) print fades into audio while keeping item fade settings, causing DUPLICATE fades\n" ..
        "• Result: Both the item fade property AND the printed fade exist, doubling the fade effect\n" ..
        "• Solution: snapshot_fades() before → zero_fades() → apply → restore_fades()\n" ..
        "• Process: Save fade settings, remove fades from item, apply FX, restore fade settings\n" ..
        "• This prevents duplicate fades in rendered audio")
      ImGui.Unindent(ctx)

      ImGui.EndTabItem(ctx)
    end

    -- === GLUE TAB ===
    if ImGui.BeginTabItem(ctx, 'GLUE Mode') then
      ImGui.TextColored(ctx, 0x00AAFFFF, "Entry Point:")
      ImGui.BulletText(ctx, "M.glue_selection(force_units) → glue_auto_scope()")
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0x00AAFFFF, "Process Flow - Multi/Auto Mode (Function Calls):")
      ImGui.Spacing(ctx)

      if ImGui.BeginTable(ctx, 'GlueFlowTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Step')
        ImGui.TableSetupColumn(ctx, 'Function')
        ImGui.TableSetupColumn(ctx, 'Action')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '1. Add Cue Markers')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'AddProjectMarker2()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Add #Glue: markers (pre-embed)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '2. Extend Window')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'per_member_window_lr()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Extend items by handle')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '3. Volume Pre')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'preprocess_item_volumes()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Merge/snapshot first item volumes')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '4. Snapshot Track Ch')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'GetMediaTrackInfo_Value(I_NCHAN)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Save track channel count')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '5. Glue')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Main_OnCommand(42432)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Execute Glue (absorbs # markers)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '6. Restore Track Ch')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'SetMediaTrackInfo_Value(I_NCHAN)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Restore track channel count')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '7. Zero Fades')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'SetMediaItemInfo_Value()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Clear fades (if Apply next)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '8. Apply (optional)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'apply_track_take_fx_to_item()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Action 40361/41993 (if Track FX)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '9. Embed TC')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'embed_current_tc_for_item()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Embed BWF TimeReference')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '10. Trim Back')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Main_OnCommand(41121)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Trim to boundaries + restore fades')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '11. Volume Post')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'postprocess_item_volumes()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Restore volumes if print=false')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '12. Remove Cue Markers')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'remove_markers_by_ids()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Remove temporary markers')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0x00AAFFFF, "Process Flow - Mono Mode:")
      ImGui.BulletText(ctx, "1. detect_units_same_track() - Group items")
      ImGui.BulletText(ctx, "2. apply_track_take_fx_to_item() - Apply mono (40361) to EACH item")
      ImGui.BulletText(ctx, "3. Main_OnCommand(42432) - Glue all mono items if multiple")
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFFFF00FF, "Use Cases:")
      ImGui.BulletText(ctx, "Merge multiple items: Consolidate dialogue, SFX, or music stems into single items")
      ImGui.BulletText(ctx, "Handle-aware: Both Units and TS modes extend with handles for safety margin")
      ImGui.BulletText(ctx, "Take name → filename: REAPER native Glue converts take names to filenames")
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFFFF00FF, "Naming Convention:")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "• GLUE uses REAPER's native naming: 'TakeName-glued-XX.wav'\n" ..
        "• XX = auto-incremented number by REAPER (01, 02, 03...)\n" ..
        "• The original take name becomes the filename automatically\n" ..
        "• Example: Take 'Dialogue' → File 'Dialogue-glued-01.wav'\n" ..
        "• This preserves your take names in the final filenames")
      ImGui.Unindent(ctx)
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFFFF00FF, "Efficiency Advantage:")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "For multiple items, GLUE is significantly faster than RENDER:\n" ..
        "• GLUE: Merge N items → Process once (1× operation)\n" ..
        "• RENDER: Process each item separately (N× operations)\n" ..
        "Example: 10 items → GLUE processes 1 time vs RENDER processes 10 times")
      ImGui.Unindent(ctx)
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFFFF00FF, "Selection Scope Modes:")
      ImGui.BulletText(ctx, "Units (default): Auto-detect touching/overlapping items, extend with handles")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx, "• Uses detect_units_same_track() to group items")
      ImGui.TextWrapped(ctx, "• Handle extension via per_member_window_lr()")
      ImGui.Unindent(ctx)
      ImGui.BulletText(ctx, "Time Selection (TS): Use existing TS boundaries, NO handle extension")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx, "• glue_by_ts_window_on_track() uses TS as-is")
      ImGui.TextWrapped(ctx, "• Useful when you manually set TS to exact boundaries")
      ImGui.TextWrapped(ctx, "• Most TS operations do NOT use handles")
      ImGui.Unindent(ctx)
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFF0000FF, "Important Technical Notes:")
      ImGui.BulletText(ctx, "Volume Rendering in GLUE mode:")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "• GLUE mode ALWAYS forces merge and print volumes (ignores GUI settings)\n" ..
        "• Reason: When merging multiple items into one, volume relationships must be preserved\n" ..
        "• Step 3 (Volume Pre): Merges item volume into ALL takes before Glue\n" ..
        "• Step 11 (Volume Post): Always keeps merged volumes (print=true behavior)\n" ..
        "• This is a technical requirement, not a bug")
      ImGui.Unindent(ctx)
      ImGui.BulletText(ctx, "Multi channel mode execution order (with Track FX enabled):")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "• Process: Glue FIRST (42432) → then Apply multi (41993)\n" ..
        "• Reason: Action 42432 auto-expands track channel count to match source channels\n" ..
        "• Solution: Snapshot I_NCHAN before Glue → restore after Glue → then Apply\n" ..
        "• Code: Lines 2130-2142 in glue_unit() function\n" ..
        "• Result: First take = glued audio, Second take = applied (active)\n" ..
        "• Fades: Cleared before Apply to prevent duplicate fades (same issue as RENDER)")
      ImGui.Unindent(ctx)
      ImGui.BulletText(ctx, "Fade handling differences between RENDER and GLUE:")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "• GLUE mode (42432 only): Preserves fade settings, NO duplicate fade issue\n" ..
        "• GLUE+Apply mode (42432→41993): Fades cleared before Apply to prevent duplicates\n" ..
        "• RENDER mode (40361/41993): Always requires fade snapshot/zero/restore workflow\n" ..
        "• Key difference: Glue (42432) keeps fades as properties; Apply (40361/41993) prints them into audio")
      ImGui.Unindent(ctx)

      ImGui.EndTabItem(ctx)
    end

    -- === AUTO TAB ===
    if ImGui.BeginTabItem(ctx, 'AUTO Mode') then
      ImGui.TextColored(ctx, 0x00AAFFFF, "Entry Point:")
      ImGui.BulletText(ctx, "M.core(args) with op='auto' → auto_selection()")
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0x00AAFFFF, "Decision Logic (Function Flow):")
      ImGui.Spacing(ctx)

      if ImGui.BeginTable(ctx, 'AutoFlowTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Step')
        ImGui.TableSetupColumn(ctx, 'Function')
        ImGui.TableSetupColumn(ctx, 'Action')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '1. Analyze')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'auto_selection(cfg)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Determine mode per unit')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '2. Detect Units')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'detect_units_same_track()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Group items into units')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '3. Separate')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'if #unit.members == 1')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Single → render_items[]')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '4. Separate')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'if #unit.members > 1')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Multi → glue_units[]')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '5. Render Batch')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'M.render_selection()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Process all single-item units')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '6. Glue Batch')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'glue_auto_scope()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Process all multi-item units')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFFFF00FF, "Key Advantage:")
      ImGui.Indent(ctx)
      ImGui.TextWrapped(ctx,
        "AUTO intelligently batches units by type:\n" ..
        "• All single-item units → processed together with RENDER workflow\n" ..
        "• All multi-item units → processed together with GLUE workflow\n" ..
        "• Optimal efficiency: right tool for each job, batched execution")
      ImGui.Unindent(ctx)
      ImGui.Spacing(ctx)

      ImGui.TextColored(ctx, 0xFFFF00FF, "Example Scenario:")
      ImGui.TextWrapped(ctx, "Track has 5 units:")
      ImGui.BulletText(ctx, "Unit 1: Single item (1ch) → RENDER batch")
      ImGui.BulletText(ctx, "Unit 2: 3 touching items (5ch) → GLUE batch")
      ImGui.BulletText(ctx, "Unit 3: Single item (6ch) → RENDER batch")
      ImGui.BulletText(ctx, "Unit 4: 2 overlapping items (2ch) → GLUE batch")
      ImGui.BulletText(ctx, "Unit 5: Single item (1ch) → RENDER batch")
      ImGui.Spacing(ctx)
      ImGui.TextWrapped(ctx, "Result: 3 units processed with RENDER, 2 units with GLUE, all in one execution!")

      ImGui.EndTabItem(ctx)
    end

    ImGui.EndTabBar(ctx)
  end

  ImGui.End(ctx)
  gui.show_manual = open
end

local function draw_gui()
  local before_state = serialize_gui_state(gui)
  local window_flags = ImGui.WindowFlags_MenuBar | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoResize | ImGui.WindowFlags_NoCollapse

  -- Add NoDocking flag if docking is disabled
  if not gui.enable_docking then
    window_flags = window_flags | ImGui.WindowFlags_NoDocking
  end

  local visible, open = ImGui.Begin(ctx, 'RGWH Control Panel', true, window_flags)
  if not visible then
    ImGui.End(ctx)
    return open
  end

  -- Close the window when ESC is pressed and the window is focused
  if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    open = false
    gui.open = false
  end

  -- Menu Bar
  if ImGui.BeginMenuBar(ctx) then
    if ImGui.BeginMenu(ctx, 'Settings') then
      -- UI Settings
      local rv_dock, new_dock = ImGui.MenuItem(ctx, 'Enable Window Docking', nil, gui.enable_docking, true)
      if rv_dock then
        gui.enable_docking = new_dock
        save_persist()
      end
      ImGui.Separator(ctx)

      if ImGui.MenuItem(ctx, 'All Settings...', nil, false, true) then
        gui.show_settings = true
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'Manual (Operation Modes)', nil, false, true) then
        gui.show_manual = true
      end
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg(("[RGWH GUI] Version %s\nImGui interface for RGWH Core\n"):format(VERSION))
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  -- Main content
  ImGui.PushItemWidth(ctx, 200)

  draw_bwfmetaedit_warning_banner()

  -- === COMMON SETTINGS ===

  -- === CHANNEL MODE ===
  ImGui.Text(ctx, "Channel Mode:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Auto##channel", gui.channel_mode == 0) then gui.channel_mode = 0 end
  -- Auto mode tooltip
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Auto mode: Decide channel output based on source material\n\n" ..
      "Behavior:\n" ..
      "  • Mono source → Mono output\n" ..
      "  • Multi-channel source → Multi-channel output\n" ..
      "  • Automatically detects source channel count\n" ..
      "  • Most flexible option for mixed projects\n\n" ..
      "Note:\n" ..
      "  • Item channel count may differ from track channel count\n" ..
      "  • Use Multi mode to force output to match track channels"
    )
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Mono##channel", gui.channel_mode == 1) then gui.channel_mode = 1 end
  -- Mono mode tooltip
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Mono mode: Force mono output for all items\n\n" ..
      "Behavior:\n" ..
      "  • All items converted to mono output\n" ..
      "  • Multi-channel sources summed to mono\n" ..
      "  • Consistent mono workflow"
    )
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Multi##channel", gui.channel_mode == 2) then gui.channel_mode = 2 end
  -- Multi mode tooltip
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Multi mode: Multi-channel output via Multi-Channel Policy\n\n" ..
      "Output depends on Multi-Channel Policy:\n\n" ..
      "  SOURCE-playback (Action 40209):\n" ..
      "    • Preserves item playback channel count\n" ..
      "    • 4ch → 4ch, 6ch → 6ch\n" ..
      "    • Mono → Stereo (2ch floor, REAPER limit)\n\n" ..
      "  SOURCE-track (Action 41993):\n" ..
      "    • Output = Track channel count (I_NCHAN)\n" ..
      "    • All items forced to match track ch\n\n" ..
      "vs AUTO mode:\n" ..
      "  • AUTO detects mono items → mono output (1ch)\n" ..
      "  • MULTI does not detect mono → always 2ch minimum\n" ..
      "  • For mono preservation, use AUTO mode"
    )
  end

  -- Multi-Channel Policy (only shown for Auto and Multi modes)
  if gui.channel_mode == 0 or gui.channel_mode == 2 then
    ImGui.Text(ctx, "Multi-Channel Policy:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "SOURCE-playback##policy", gui.multi_channel_policy == 0) then
      gui.multi_channel_policy = 0
      sync_rgwh_extstate_from_gui()  -- Sync immediately when changed
      if gui.debug_level >= 1 then
        r.ShowConsoleMsg(string.format("[RGWH GUI] Multi-Channel Policy changed to: SOURCE-playback\n"))
      end
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "SOURCE-playback: Preserve item playback channel count\n\n" ..
        "Behavior:\n" ..
        "  • Stereo item → Stereo output (2ch → 2ch)\n" ..
        "  • 4-channel item → 4-channel output (4ch → 4ch)\n" ..
        "  • Preserves original multi-channel layout\n\n" ..
        "Mono item handling:\n" ..
        "  • AUTO mode: Mono → Mono (1ch, uses 40361)\n" ..
        "  • MULTI mode: Mono → Stereo (2ch floor)\n" ..
        "    Action 40209 minimum output is 2ch (REAPER limit)\n" ..
        "    Use AUTO mode if mono should stay mono\n\n" ..
        "Use when:\n" ..
        "  • Working with multi-channel audio (surround, Atmos)\n" ..
        "  • Want to preserve original channel layout\n" ..
        "  • Default behavior (recommended)"
      )
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "SOURCE-track##policy", gui.multi_channel_policy == 1) then
      gui.multi_channel_policy = 1
      sync_rgwh_extstate_from_gui()  -- Sync immediately when changed
      if gui.debug_level >= 1 then
        r.ShowConsoleMsg(string.format("[RGWH GUI] Multi-Channel Policy changed to: SOURCE-track\n"))
      end
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "SOURCE-track: Force output to match source track channels\n\n" ..
        "Behavior:\n" ..
        "  • Output always matches SOURCE track channel count\n" ..
        "  • All items normalized to same channel count\n" ..
        "  • Mono on stereo track → Stereo output\n" ..
        "  • 4ch on stereo track → Stereo output (downmix)\n\n" ..
        "Use when:\n" ..
        "  • Need consistent channel count across all items\n" ..
        "  • Want all outputs to match track routing\n" ..
        "  • Working with standard stereo workflow"
      )
    end
  end

  ImGui.Spacing(ctx)

  -- === PRINTING ===
  draw_section_header("PRINTING")

  -- Two-column layout
  local col_width = ImGui.GetContentRegionAvail(ctx) / 2 - 10

  -- Left column: FX Processing
  ImGui.BeginGroup(ctx)
  ImGui.Text(ctx, "FX Processing:")
  rv, new_val = ImGui.Checkbox(ctx, "Print Take FX", gui.take_fx)
  if rv then gui.take_fx = new_val end
  draw_help_marker("Print take FX into rendered audio")

  rv, new_val = ImGui.Checkbox(ctx, "Print Track FX", gui.track_fx)
  if rv then gui.track_fx = new_val end
  draw_help_marker("Print track FX into rendered audio")
  ImGui.EndGroup(ctx)

  ImGui.SameLine(ctx, col_width + 20)

  -- Right column: Volume Rendering
  ImGui.BeginGroup(ctx)
  ImGui.Text(ctx, "Volume Rendering:")

  -- Item checkbox (Merge to Item)
  rv, new_val = ImGui.Checkbox(ctx, "Merge to Item##merge_item", gui.merge_to_item)
  if rv then
    gui.merge_to_item = new_val
    if new_val then
      -- Mutually exclusive: disable Merge to Take + Print
      gui.merge_to_take = false
      gui.print_volumes = false
    end
  end
  ImGui.SameLine(ctx)
  draw_help_marker("Merge take volume INTO item volume\n• Consolidates volume at item level\n• Preserves relative take volumes across multiple takes\n• Print OFF only (REAPER can only print take volume)\n• Mutually exclusive with Merge to Take + Print Volumes")

  -- Take checkbox (Merge to Take)
  rv, new_val = ImGui.Checkbox(ctx, "Merge to Take##merge_take", gui.merge_to_take)
  if rv then
    gui.merge_to_take = new_val
    if new_val then
      -- Mutually exclusive: disable Merge to Item
      gui.merge_to_item = false
    else
      -- Unchecking Merge to Take: auto-disable Print (binding)
      gui.print_volumes = false
    end
  end
  ImGui.SameLine(ctx)
  draw_help_marker("Merge item volume INTO take volume (original behavior)\n• Consolidates volume at take level\n• Merges into ALL takes (preserves relative volumes)\n• Supports Print ON/OFF\n• Mutually exclusive with Merge to Item\n\nNote: GLUE mode always forces merge to take + print")

  -- Print checkbox (always enabled)
  rv, new_val = ImGui.Checkbox(ctx, "Print Volumes##print_vol", gui.print_volumes)
  if rv then
    gui.print_volumes = new_val
    if new_val then
      -- Print ON: auto-enable Merge to Take (binding)
      gui.merge_to_item = false
      gui.merge_to_take = true
    end
  end
  ImGui.SameLine(ctx)
  draw_help_marker("Print volumes into rendered audio (all volumes → 0dB)\n• Requires Merge to Take (REAPER only prints take volume)\n• Checking this auto-enables Merge to Take\n• Unchecking Merge to Take auto-disables Print\n• Mutually exclusive with Merge to Item\n\nNote: GLUE mode always forces print ON")

  ImGui.EndGroup(ctx)

  -- === HANDLE SETTINGS ===
  draw_section_header("HANDLE (Pre/Post Roll)")

  rv, new_val = ImGui.Combo(ctx, "Handle Mode", gui.handle_mode, "Use ExtState\0Seconds\0Frames\0")
  if rv then gui.handle_mode = new_val end

  if gui.handle_mode > 0 then
    rv, new_val = ImGui.InputDouble(ctx, "Handle Length", gui.handle_length, 0.1, 1.0, "%.3f")
    if rv then gui.handle_length = math.max(0, new_val) end

    local unit = gui.handle_mode == 1 and "seconds" or "frames"
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, unit)
  end

  -- === OPERATION BUTTONS & INFO ===
  ImGui.Spacing(ctx)
  ImGui.Spacing(ctx)
  ImGui.Separator(ctx)
  ImGui.Spacing(ctx)

  if gui.is_running then
    ImGui.BeginDisabled(ctx)
  end

  -- Track which button is hovered for info display
  local hovered_mode = nil

  -- Calculate button width (3 buttons with spacing)
  local avail_width = ImGui.GetContentRegionAvail(ctx)
  local button_width = (avail_width - 2 * ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)) / 3

  -- RENDER button (base blue, hover -> green)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button,        0xFF) -- base blue (same as GUI default)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF3399FF) -- hover becomes green
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  0xFF1A75FF) -- active deep green
  if ImGui.Button(ctx, "RENDER", button_width, 40) then
    run_rgwh("render")
  end
  if ImGui.IsItemHovered(ctx) then hovered_mode = "render" end
  ImGui.PopStyleColor(ctx, 3)

  ImGui.SameLine(ctx)

  -- AUTO button (base blue, hover -> brighter blue)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button,        0xFF) -- base blue
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF3399FF) -- hover brighter blue
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  0xFF1A75FF) -- active slightly darker
  if ImGui.Button(ctx, "AUTO", button_width, 40) then
    run_rgwh("auto")
  end
  if ImGui.IsItemHovered(ctx) then hovered_mode = "auto" end
  ImGui.PopStyleColor(ctx, 3)

  ImGui.SameLine(ctx)

  -- GLUE button (base blue, hover -> yellow)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button,        0xFF) -- base blue
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF3399FF) -- hover becomes yellow
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  0xFF1A75FF) -- active deeper yellow/orange
  if ImGui.Button(ctx, "GLUE", button_width, 40) then
    run_rgwh("glue")
  end
  if ImGui.IsItemHovered(ctx) then hovered_mode = "glue" end
  ImGui.PopStyleColor(ctx, 3)

  if gui.is_running then
    ImGui.EndDisabled(ctx)
  end

  -- Mode info display (compact)
  ImGui.Spacing(ctx)
  if hovered_mode == "render" then
    ImGui.TextWrapped(ctx, "RENDER: Process each item independently (per-item render, no grouping)")
  elseif hovered_mode == "auto" then
    ImGui.TextWrapped(ctx, "AUTO: Single-item units→RENDER, Multi-item units(TOUCH/CROSSFADE)→GLUE • Always uses Units scope")
  elseif hovered_mode == "glue" then
    ImGui.TextWrapped(ctx, "GLUE: Always glue all items (including single items) • Scope: Has TS→TS, No TS→Units (like REAPER native)")
  else
    ImGui.TextDisabled(ctx, "Hover over a button to see its description")
  end

  -- Status display
  if gui.last_result ~= "" then
    ImGui.Spacing(ctx)
    ImGui.Text(ctx, "Status: " .. gui.last_result)
  end

  -- persist if changed
  local after_state = serialize_gui_state(gui)
  handle_state_change(before_state, after_state)

  ImGui.PopItemWidth(ctx)
  ImGui.End(ctx)

  return open
end

------------------------------------------------------------
-- Main Loop
------------------------------------------------------------
local function loop()
  gui.open = draw_gui()
  draw_settings_popup()
  draw_manual_window()
  draw_bwfmetaedit_install_modal()

  if gui.open then
    r.defer(loop)
  else
    -- Window is closing - print settings if debug level >= 1
    if gui.debug_level >= 1 then
      print_all_settings("[RGWH GUI - CLOSING]")
    end
  end
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
r.defer(loop)
