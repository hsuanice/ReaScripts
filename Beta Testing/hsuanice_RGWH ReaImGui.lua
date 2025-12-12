--[[
@description RGWH GUI - ImGui Interface for RGWH Core
@author hsuanice
@version 0.1.0
@provides
  [main] .

@about
  ImGui-based GUI for configuring and running RGWH Core operations.
  Provides visual controls for all RGWH Wrapper Template parameters.

@usage
  Run this script in REAPER to open the RGWH GUI window.
  Adjust parameters using the visual controls and click operation buttons to execute.

@changelog
  0.1.0 [v251213.0023] - ADDED DOCKING TOGGLE OPTION
    - Added: Window docking toggle option in Settings menu.
      - New location: Menu Bar → Settings → "Enable Window Docking" (checkbox)
      - When disabled: window cannot be docked into REAPER's dock system (WindowFlags_NoDocking)
      - When enabled: window can be docked like any other ImGui window
      - Setting persists between sessions via ExtState
      - Lines: 396 (setting definition), 415 (persist_keys), 1604-1606 (window flags), 1634-1638 (Settings menu)
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

  -- Render toggles
  take_fx = true,
  track_fx = false,
  tc_mode = 1,              -- 0=previous, 1=current, 2=off

  -- Volume handling
  merge_volumes = true,
  print_volumes = false,

  -- Handle settings
  handle_mode = 0,          -- 0=ext, 1=seconds, 2=frames
  handle_length = 5.0,

  -- Epsilon settings
  epsilon_mode = 0,         -- 0=ext, 1=frames, 2=seconds
  epsilon_value = 0.5,

  -- Cues
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

  -- Status
  is_running = false,
  last_result = "",
}

-- Persistence namespace and helpers (save/load GUI state)
local P_NS = "hsuanice_RGWH_GUI_state_v1"

local persist_keys = {
  'op','selection_scope','channel_mode',
  'take_fx','track_fx','tc_mode',
  'merge_volumes','print_volumes',
  'handle_mode','handle_length',
  'epsilon_mode','epsilon_value',
  'cue_write_edge','cue_write_glue',
  'glue_single_items','glue_no_trackfx_policy','render_no_trackfx_policy',
  'debug_level','debug_no_clear','selection_policy',
  'enable_docking'
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
  local epsilon_names = {"Use ExtState", "Frames", "Seconds"}
  local policy_names = {"Preserve", "Force Multi"}
  local debug_names = {"Silent", "Normal", "Verbose"}
  local selection_policy_names = {"Progress", "Restore", "None"}

  r.ShowConsoleMsg("========================================\n")
  r.ShowConsoleMsg(string.format("%s settings:\n", prefix))
  r.ShowConsoleMsg("========================================\n")

  r.ShowConsoleMsg(string.format("  Operation: %s\n", op_names[gui.op + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Selection Scope: %s\n", scope_names[gui.selection_scope + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Channel Mode: %s\n", channel_names[gui.channel_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Take FX: %s\n", bool_str(gui.take_fx)))
  r.ShowConsoleMsg(string.format("  Track FX: %s\n", bool_str(gui.track_fx)))
  r.ShowConsoleMsg(string.format("  TC Mode: %s\n", tc_names[gui.tc_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Merge Volumes: %s\n", bool_str(gui.merge_volumes)))
  r.ShowConsoleMsg(string.format("  Print Volumes: %s\n", bool_str(gui.print_volumes)))
  r.ShowConsoleMsg(string.format("  Handle Mode: %s\n", handle_names[gui.handle_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Handle Length: %.2f\n", gui.handle_length))
  r.ShowConsoleMsg(string.format("  Epsilon Mode: %s\n", epsilon_names[gui.epsilon_mode + 1] or "Unknown"))
  r.ShowConsoleMsg(string.format("  Epsilon Value: %.5f\n", gui.epsilon_value))
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

-- If debug level >= 1, print settings on startup
if gui.debug_level >= 1 then
  print_all_settings("[RGWH GUI - STARTUP]")
end

------------------------------------------------------------
-- Preset System
------------------------------------------------------------
local presets = {
  {
    name = "Auto (ExtState defaults)",
    op = 0,
    selection_scope = 0,
    channel_mode = 0,
  },
  {
    name = "Force Units Glue",
    op = 2,
    selection_scope = 1,
    channel_mode = 0,
  },
  {
    name = "Force TS-Window Glue",
    op = 2,
    selection_scope = 2,
    channel_mode = 0,
  },
  {
    name = "Single-Item Render",
    op = 1,
    channel_mode = 0,
    take_fx = true,
    track_fx = false,
    tc_mode = 0,
  },
}

local selected_preset = -1

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

local function apply_preset(idx)
  if idx < 0 or idx >= #presets then return end
  local p = presets[idx + 1]

  if p.op then gui.op = p.op end
  if p.selection_scope then gui.selection_scope = p.selection_scope end
  if p.channel_mode then gui.channel_mode = p.channel_mode end
  if p.take_fx ~= nil then gui.take_fx = p.take_fx end
  if p.track_fx ~= nil then gui.track_fx = p.track_fx end
  if p.tc_mode then gui.tc_mode = p.tc_mode end
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

    merge_volumes = gui.merge_volumes,
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

  -- Epsilon
  if gui.epsilon_mode == 0 then
    args.epsilon = "ext"
  elseif gui.epsilon_mode == 1 then
    args.epsilon = { mode = "frames", value = gui.epsilon_value }
  else -- seconds
    args.epsilon = { mode = "seconds", value = gui.epsilon_value }
  end

  -- Debug
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

local function draw_settings_popup()
  if not gui.show_settings then return end

  local before_state = serialize_gui_state(gui)

  ImGui.SetNextWindowSize(ctx, 500, 600, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Settings', true)
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

  -- === EPSILON ===
  draw_section_header("EPSILON (Tolerance)")
  rv, new_val = ImGui.Combo(ctx, "Epsilon Mode", gui.epsilon_mode, "Use ExtState\0Frames\0Seconds\0")
  if rv then gui.epsilon_mode = new_val end

  if gui.epsilon_mode > 0 then
    rv, new_val = ImGui.InputDouble(ctx, "Epsilon Value", gui.epsilon_value, 0.01, 0.1, "%.3f")
    if rv then gui.epsilon_value = math.max(0, new_val) end

    local unit = gui.epsilon_mode == 1 and "frames" or "seconds"
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, unit)
  end

  -- === CUES ===
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
  if after_state ~= before_state then save_persist() end

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
  local visible, open = ImGui.Begin(ctx, 'RGWH Manual - Operation Modes', true)
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
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Mono source → mono, Multi → multi')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Mono')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Action 40361')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Item: Apply track/take FX to items (mono output)')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Multi')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Action 41993')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Item: Apply track/take FX (multichannel output)')

        ImGui.EndTable(ctx)
      end
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
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, '40361 (mono) / 41993 (multi)')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Bakes FX into audio file')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)
      ImGui.Separator(ctx)
      ImGui.Spacing(ctx)

      -- === VOLUME RENDERING ===
      ImGui.TextColored(ctx, 0x00AAFFFF, "3. VOLUME RENDERING")
      ImGui.Spacing(ctx)
      if ImGui.BeginTable(ctx, 'VolumeTable', 3, ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, 'Feature')
        ImGui.TableSetupColumn(ctx, 'Implementation')
        ImGui.TableSetupColumn(ctx, 'Behavior')
        ImGui.TableHeadersRow(ctx)

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Merge Volumes')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'D_VOL + D_TAKEVOL')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Merge item vol into take vol before render')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Print Volumes')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Keep/restore volume values')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'ON: bake into audio | OFF: restore original')

        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, 0xFFFF00FF, 'Volume Snapshot')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'GetMediaItemInfo_Value()')
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, 'Snapshot before, restore after if needed')

        ImGui.EndTable(ctx)
      end
      ImGui.Spacing(ctx)
      ImGui.TextColored(ctx, 0xFF0000FF, "Important Note:")
      ImGui.BulletText(ctx, "GLUE mode always forces merge and print volumes (technical requirement)")
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
  local window_flags = ImGui.WindowFlags_MenuBar | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoResize

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
    if ImGui.BeginMenu(ctx, 'Presets') then
      for i, preset in ipairs(presets) do
        if ImGui.MenuItem(ctx, preset.name, nil, false, true) then
          apply_preset(i - 1)
          selected_preset = i - 1
        end
      end
      ImGui.EndMenu(ctx)
    end

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

  -- === COMMON SETTINGS ===

  -- === CHANNEL MODE ===
  ImGui.Text(ctx, "Channel Mode:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Auto##channel", gui.channel_mode == 0) then gui.channel_mode = 0 end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Mono##channel", gui.channel_mode == 1) then gui.channel_mode = 1 end
  -- Mono mode tooltip (show current glue_after_mono_apply setting)
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx,
      "Mono mode: Apply mono (40361) to each item\n\n" ..
      "Behavior by operation mode:\n" ..
      "  • RENDER mode: Never glues (processes items individually)\n" ..
      "  • AUTO mode: Multi-item units are glued after mono apply\n" ..
      "  • GLUE mode: Always glues after mono apply"
    )
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Multi##channel", gui.channel_mode == 2) then gui.channel_mode = 2 end
  ImGui.SameLine(ctx)
  draw_help_marker("Auto: decide based on source material | Mono: force mono | Multi: force multi-channel")

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
  rv, new_val = ImGui.Checkbox(ctx, "Merge Volumes", gui.merge_volumes)
  if rv then gui.merge_volumes = new_val end
  draw_help_marker("Merge item volume into take volume before render\n\nNote: GLUE mode always forces merge and print (technical requirement)")

  rv, new_val = ImGui.Checkbox(ctx, "Print Volumes", gui.print_volumes)
  if rv then gui.print_volumes = new_val end
  draw_help_marker("Print volumes into rendered audio\n(false = restore original volumes)\n\nNote: GLUE mode always forces merge and print (technical requirement)")
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
    ImGui.TextWrapped(ctx, "AUTO: Single-item units→RENDER, Multi-item units(TOUCH/CROSSFADE)→GLUE • Scope: No TS→Units, TS=span→Units, TS≠span→TS")
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
  if after_state ~= before_state then save_persist() end

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
