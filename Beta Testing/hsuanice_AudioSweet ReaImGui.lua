--[[
@description AudioSweet ReaImGui - ImGui Interface for AudioSweet
@author hsuanice
@version 0.1.0
@provides
  [main] .
@about
  Complete AudioSweet control center with:
  - Focused/Chain modes with FX chain display
  - Apply/Copy actions
  - AudioSweet Preview integration with configurable target track
  - Compact, intuitive UI with radio buttons
  - Persistent settings (remembers all settings between sessions)
  - Improved auto-focus FX with CLAP plugin support
  - Debug mode with detailed console logging
  - Built-in keyboard shortcuts (Space = Play/Stop, S = Solo toggle)
  - Comprehensive file naming settings with FX Alias support
  - Saved Chains and History features with CLAP plugin support
  - Auto-resizing window that prevents accidental resize/close


@changelog
  0.1.0 [Internal Build 251213.0026] - IMPROVED CHAIN PREVIEW TARGET SELECTION AND SOLO TARGETING
    - Improved: Chain preview now intelligently selects target track.
      - If FX chain is focused: Uses the focused FX chain track for preview
      - If no FX chain is focused: Falls back to settings target track name
      - Rationale: Allows quick preview of currently focused chain without changing settings
      - Lines: 1003-1017 (toggle_preview target selection logic), 1019-1027 (args setup)
    - Improved: Solo toggle button now correctly targets preview track in chain mode.
      - In Focused mode: Targets gui.focused_track (existing behavior)
      - In Chain mode: Prioritizes gui.focused_track if exists, otherwise finds track by gui.preview_target_track name
      - Previously: Solo button didn't work correctly in chain mode
      - Lines: 1014-1073 (toggle_solo enhanced targeting logic)
    - Fixed: Chain preview target resolution now works correctly with Preview Core.
      - Issue 1: Previously used target="TARGET_TRACK_NAME" which triggered fallback to "AudioSweet"
      - Issue 2: gui.focused_track_name format included track number prefix (e.g., "#3 - TrackName")
      - Solution: Get pure track name directly from gui.focused_track using P_NAME (without track number)
      - Result: Chain preview now correctly targets focused FX chain track or settings target track
      - Lines: 1008-1024 (target track name extraction), 1026-1034 (args without explicit target)
    - Added: Comprehensive debug logging for both preview and solo operations in chain mode.

  Internal Build 251213.0018 - IMPROVED DOCKING SETTING DISCOVERABILITY
    - Improved: Moved window docking toggle from History Settings to main Settings menu.
      - New location: Menu Bar → Settings → "Enable Window Docking" (checkbox)
      - Previous location: History Settings popup (removed)
      - Rationale: Docking is a UI-level setting unrelated to history; placing it in Settings menu is more intuitive and discoverable
      - Lines: 1689-1693 (Settings menu checkbox), removed lines 1802-1813 (old History Settings UI section)

  Internal Build 251213.0008 - ADDED DOCKING TOGGLE OPTION
    - Added: Window docking toggle option.
      - New setting: "Enable Window Docking" checkbox (default: OFF)
      - When disabled: window cannot be docked into REAPER's dock system (WindowFlags_NoDocking)
      - When enabled: window can be docked like any other ImGui window
      - Setting persists between sessions via ExtState
      - Lines: 579 (setting definition), 610-611 (save), 657-658 (load), 1645-1647 (window flags)
    - Purpose: Prevents accidental docking for users who prefer floating windows, while allowing flexibility for those who want docking.

  Internal Build 251212.1230 - IMPROVED UNDO BEHAVIOR FOR SINGLE-STEP UNDO
    - Improved: Main AUDIOSWEET button execution now uses single undo block.
      - Issue: Executing AudioSweet required multiple undo steps to fully revert (render, glue, print FX, etc.)
      - Solution: Wrapped run_audiosweet() execution with Undo_BeginBlock/EndBlock (lines 1039-1040, 1110-1113)
      - Added PreventUIRefresh to improve performance during execution
      - Result: One Undo operation reverts entire AudioSweet execution back to pre-execution state
      - Undo label format: "AudioSweet GUI: Focused/Chain Apply/Copy"
      - Behavior now consistent with History and Saved Chains (which already had undo blocks)
    - Technical: Nested undo blocks are supported by REAPER and merge correctly.
      - GUI undo block wraps AudioSweet Core's internal undo blocks
      - Core already has undo blocks (AudioSweet Core line 1754)
      - Outer block takes precedence, creating single undo point for user

  Internal Build 251211.2150 - FIXED HISTORY COPY MODE AND ADDED DEBUG LOGGING
    - FIXED: History focused FX in Copy mode now correctly copies single FX instead of entire chain.
      - Issue: Clicking history item for focused FX in copy mode would copy entire track FX chain
      - Root cause: run_history_item() called run_saved_chain_copy_mode() for both focused and chain modes
      - Solution: Created new run_focused_fx_copy_mode() function (lines 1095-1149)
      - Result: Focused FX history copies only the specific FX, chain history copies entire chain
      - Modified: run_history_item() now uses run_focused_fx_copy_mode() for focused mode copy (line 1487)
    - Added: Debug console logging for all Copy mode operations.
      - run_focused_fx_copy_mode(): Shows FX name, index, items, scope, position, and operation count
      - run_saved_chain_copy_mode(): Shows chain name, FX count, scope, position, and operation count
      - Helps diagnose copy operations and verify correct behavior
      - Lines: 1096-1098, 1112-1114, 1143-1145, 1152-1154, 1163-1165, 1172-1174, 1214-1216

  Internal Build 251211.2130 - FIXED IMGUI CHILD WINDOW ASSERTIONS AND DYNAMIC FX LIST HEIGHT
    - FIXED: ImGui_EndChild assertion errors when switching options or launching in clean REAPER.
      - Issue: BeginChild was called when gui.enable_saved_chains/enable_history was true but arrays were empty
      - Root cause: Inner conditions only checked enable flag, not array length
      - Solution: Added #gui.saved_chains > 0 and #gui.history > 0 checks to inner conditions (lines 2100, 2131)
      - Result: BeginChild/EndChild now only called when there's actual content to display
      - Fixes crashes in default REAPER installations without saved ExtState data
    - Improved: FX Chain List now uses dynamic height with scroll support.
      - Calculates height based on FX count: fx_count × 20px, max 150px (~7 FX visible)
      - When FX count ≤ 7: Compact display, saves space for History/Saved Chains below
      - When FX count > 7: Fixed at 150px with automatic scrollbar
      - Result: Better space utilization and improved readability of History/Saved Chains sections

  Internal Build 251106.1600 - ADDED ESC TO CLOSE WINDOW
    - Added: ESC key now closes the AudioSweet GUI window
    - Keyboard shortcut: ESC = Close window
    - Works when not typing in text inputs (same condition as Space/S shortcuts)

  Internal Build 251106.1530 - FIXED SOLO TOGGLE TO TARGET FOCUSED TRACK
    - FIXED: Solo toggle now operates on gui.focused_track (FX chain track) instead of selected tracks.
      - Issue: toggle_solo() used command 40281 which operates on selected tracks
      - Problem: During Preview, the target track (gui.focused_track) may not be selected
      - Solution: Directly toggle solo state on gui.focused_track using r.SetMediaTrackInfo_Value()
      - Result: Solo toggle now correctly targets the track with focused FX chain
    - Technical: toggle_solo() now checks if gui.focused_track exists and directly sets its solo state.

  Internal Build 251030.2350 - FIXED PREVIEW STOP BUTTON
    - FIXED: STOP button now correctly stops preview started by Tools scripts.
      - Issue: toggle_preview() only checked gui.is_previewing (false when started by Tools scripts)
      - Result: Clicking STOP would trigger another preview instead of stopping
      - Solution: Check actual transport play state in addition to gui.is_previewing
      - Now detects and stops previews regardless of how they were started
    - Technical: toggle_preview() now uses GetPlayState() to detect actual playback state.

  Internal Build 251030.2345 - FINALIZED KEYBOARD SHORTCUTS SYSTEM
    - Added back: Space = Stop, S = Solo (simple shortcuts without modifiers work reliably).
    - Fixed: PREVIEW button now detects transport play state (shows STOP when playing).
      - Detects previews started by Tools scripts via transport play state
      - Button turns orange and shows "STOP" when transport is playing
      - Works regardless of whether preview started from GUI or keyboard shortcut
    - Updated: Shortcut info shows "Space = Stop, S = Solo" and Tips for binding Tools scripts.
    - Result: Complete keyboard shortcut system
      - In-GUI: Space (Stop), S (Solo)
      - Tools scripts: User-defined shortcuts for Chain/Focused Preview with modifier keys
      - All preview settings read from GUI ExtState (single source of truth)

  Internal Build 251030.2335 - PREVIEW SHORTCUTS VIA TOOLS SCRIPTS
    - Changed: Removed in-GUI keyboard shortcuts for Preview (modifier key detection unreliable).
    - NEW: Preview shortcuts now use Tools folder scripts that read GUI settings.
      - Bind "hsuanice_AudioSweet Chain Preview Solo Exclusive" for Chain Preview
      - Bind "hsuanice_AudioSweet Preview Solo Exclusive" for Focused Preview
      - Scripts automatically read preview_target_track, solo_scope, restore_mode from GUI ExtState
      - Single source of truth: change settings in GUI, all scripts use same settings
    - Updated: Shortcut info now guides users to bind Tools scripts in Action List.
    - Benefit: Reliable keyboard shortcuts with full modifier key support (Ctrl, Shift, etc.)
    - Compatible: Tools scripts v251030.2335 or newer required

  Internal Build 251030.2300 - ENHANCED KEYBOARD SHORTCUTS (deprecated)
    - Note: This approach had modifier key detection issues and was replaced by Tools scripts approach

  Internal Build 251030.2130 - KEYBOARD SHORTCUTS FIX
    - FIXED: Keyboard shortcuts no longer trigger while typing in text inputs.
      - Uses ImGui.IsAnyItemActive() to detect if user is typing
      - Shortcuts only work when NOT in text input fields
      - Fixes issue where typing "S" or Space in popups would trigger shortcuts
      - Applies to all text inputs: Preview Target, Save Chain name, etc.
    - Changed: Keyboard shortcut "S" restored (no longer requires Shift).
      - Space = Play/Stop transport
      - S = Solo toggle (Track Solo / Item Solo based on settings)
      - Safe to use now that text input detection is fixed
    - Added: Keyboard shortcuts info displayed on main GUI.
      - Gray text below action buttons: "Shortcuts: Space = Play/Stop, S = Solo"
      - Helps users discover keyboard shortcuts
      - Always visible for quick reference

  Internal Build 251030.2115 - UI/UX IMPROVEMENTS
    - Improved: Preview Target now shows on main GUI as clickable button.
      - Displays current target track name in Chain mode
      - Click to open simple popup input dialog
      - Handles empty string case (shows "(not set)")
      - Setting persists between sessions
      - More intuitive: can see current value at a glance
    - Note: Preview Target also remains accessible in Settings → Preview Settings...

  Internal Build 251030.2100 - UI/UX IMPROVEMENTS
    - FIXED: Show FX window on recall now opens correct track's FX chain.
      - Issue: Command 40291 opens "last touched track" FX chain, which was wrong after removing SetOnlyTrackSelected()
      - Root cause: After removing SetOnlyTrackSelected(), last touched track became item selection track instead of target track
      - Solution: Use TrackFX_Show(tr, 0, 1) to directly open target track's FX chain
      - Now correctly opens saved chain's track FX window, not item's track
    - Changed: Keyboard shortcut "S" changed to "Shift+S" for Solo toggle.
      - Prevents accidental solo toggle when typing "S" in text inputs
      - Space = Play/Stop (unchanged)
      - Shift+S = Solo toggle (Track Solo / Item Solo based on settings)
    - Changed: Preview Target input moved to Preview Settings popup.
      - Removed from main GUI to prevent keyboard shortcut conflicts
      - Avoids triggering Shift+S when typing uppercase "S" in track name
      - Access via Settings → Preview Settings...
      - Setting still persists between sessions

  Internal Build 251030.1645 - CODE CLEANUP
    - FIXED: Selection now properly maintained when using AUDIOSWEET button in chain mode.
      - Root cause: Line 948 had SetOnlyTrackSelected() that changed selection before Core execution
      - Solution: Removed SetOnlyTrackSelected(), only use SetMixerScroll()
      - Now all execution paths (AUDIOSWEET button, SAVED CHAIN, HISTORY) preserve selection consistently
    - Removed: Unused variables show_summary and warn_takefx.
      - These variables were saved/loaded but had no actual functionality
      - Cleaned up from gui state, save/load functions, and debug output
      - Reduces code complexity and memory usage
    - Updated: AS Preview Core version to 251030.1630 for consistency.
      - All AudioSweet components now use matching version numbers
      - Ensures compatibility across all modules

  Internal Build 251030.1630 - CRITICAL FIXES
    - FIXED: "Please focus a Track FX" warning no longer appears when using SAVED CHAINS/HISTORY.
      - Root cause: AudioSweet Core's checkSelectedFX() only checked GetFocusedFX()
      - Solution: Core now checks OVERRIDE ExtState before calling GetFocusedFX()
      - OVERRIDE_TRACK_IDX and OVERRIDE_FX_IDX bypass focus detection entirely
      - Works reliably with all plugin formats (CLAP, VST3, VST, AU)
      - History focused mode now works even with "Show FX window on recall" disabled
    - FIXED: Item selection now properly maintained when using SAVED CHAINS/HISTORY.
      - Root cause: GUI called SetOnlyTrackSelected() before Core's selection snapshot
      - Solution: Removed SetOnlyTrackSelected() calls, only use SetMixerScroll()
      - Core now snapshots original item selection and restores it at the end
      - Selection behavior now identical between direct execution and SAVED CHAINS/HISTORY
    - Added: "Show FX window on recall" toggle in settings.
      - Controls whether FX windows open when executing SAVED CHAIN/HISTORY
      - Checkbox appears above SAVED CHAINS and HISTORY sections
      - When enabled: Opens FX chain (chain mode) or floating FX (focused mode)
      - When disabled: Silent execution without opening FX windows
      - Persists between sessions via ExtState
    - Changed: AudioSweet Core checkSelectedFX() now supports OVERRIDE mechanism.
      - Checks OVERRIDE_TRACK_IDX and OVERRIDE_FX_IDX ExtState first
      - Falls back to GetFocusedFX() if OVERRIDE not set
      - Clears OVERRIDE values after use (single-use mechanism)
      - Enables reliable execution without requiring actual FX window focus
    - Technical: Execution flow now preserves item selection correctly.
      - GUI sets OVERRIDE ExtState → Core snapshots selection → Core processes → Core restores selection
      - Previous flow: GUI changes selection → Core snapshots wrong selection → Selection lost
      - Core's internal selection restoration now works as intended
    - Integration: Requires AudioSweet Core v251030.1630+ (OVERRIDE ExtState support).

  Internal Build 251030.1600
    - Changed: Replaced AudioSweet Template usage (removed intermediate Template layer).
      - Previous: ReaImGui → Template → AudioSweet Core → RGWH Core
      - Now: ReaImGui → AudioSweet Core → RGWH Core (streamlined execution path)
      - Removed TEMPLATE_PATH dependency, now directly uses CORE_PATH
      - All ExtState parameters work identically
      - Simplified maintenance and debugging
    - Improved: SAVED CHAINS and HISTORY UI with better scrolling support.
      - Increased height from 150px to 200px for more visible items
      - Added border to child windows for better visual separation
      - SAVED CHAINS: Button width now uses available space dynamically
      - HISTORY: Already uses full available width (-1)
      - Both sections now properly scroll when content exceeds visible area
    - Added: "Open" button for SAVED CHAINS and HISTORY with intelligent toggle behavior.
      - SAVED CHAINS: Toggles FX chain window to view/edit entire chain
      - HISTORY (Focused mode): Toggles floating FX window for specific plugin
      - HISTORY (Chain mode): Toggles FX chain window to view/edit entire chain
      - Smart toggle implementation:
        * FX chain: Uses TrackFX_GetChainVisible() + TrackFX_Show() with flag 0/1
        * Floating FX: Uses TrackFX_GetOpen() + TrackFX_Show() with flag 2/3
      - UI layout: [Open] [Chain/History Name Button] [X (for saved chains only)]
      - Provides quick access for viewing/editing FX without executing AudioSweet
      - Improves workflow: adjust settings → save chain → process items
    - Changed: GUI window now auto-resizes based on content.
      - Added: ImGui.WindowFlags_AlwaysAutoResize flag
      - Added: ImGui.WindowFlags_NoResize flag (prevents manual resizing)
      - Window automatically adjusts size when content changes
      - Users cannot accidentally resize window (prevents UI errors)
      - Window can still be moved and closed normally

  251030.1515
    - Fixed: SAVED CHAINS and HISTORY now work correctly with CLAP plugins.
      - Issue: AudioSweet Core required focused FX even in chain mode
      - Solution: Core now uses first selected track as fallback when no focus detected in chain mode
      - OVERRIDE ExtState mechanism bypasses GetFocusedFX check in Core
      - Removed unnecessary Action 40271 (Show FX chain) that caused FX browser popup
      - All execution is silent and clean - no unexpected dialogs or windows
    - Changed: Enabled SAVED CHAINS and HISTORY features (previously disabled).
      - Both features now fully functional with simplified focus detection
      - SAVED CHAINS: Click saved chain name to execute on selected items
      - HISTORY: Recent operations automatically tracked (configurable size 1-50)
      - Execution logic simplified: Select track → Set OVERRIDE → Execute Core
    - Added: "Open" button for each saved chain.
      - UI layout: [Open] [Chain Name Button] [X]
      - "Open" button: Opens FX chain window without processing (for viewing/editing FX)
      - Chain Name button: Executes AudioSweet processing on selected items
      - "X" button: Deletes saved chain
      - Allows quick access to FX chain for adjustments before processing
    - Technical: Chain mode execution no longer requires GetFocusedFX() to succeed.
      - Core uses OVERRIDE_TRACK_IDX and OVERRIDE_FX_IDX from ExtState
      - Core falls back to first selected track when focus detection fails
      - Works reliably with CLAP, VST3, VST, and AU plugins
    - Integration: Requires AudioSweet Core v251030.1515+ (chain mode fallback support).

  251030.0910
    - Changed: Redesigned File Naming Settings UI for better logic and intuitiveness.
      - Removed: "Use FX Alias for file naming" checkbox from global settings
      - Changed: FX Alias usage now controlled by "Chain Token Source" selection
      - New structure:
        1. Global FX Name Settings (applies to Focused & Chain modes)
           - Show Plugin Type, Show Vendor Name, Strip Spaces & Symbols, Max FX Tokens
        2. Chain Mode Specific Settings
           - Chain Token Source: Track Name / FX Aliases / FXChain
           - When "FX Aliases" is selected, alias database is automatically used
           - Alias Joiner (only shown when FX Aliases is selected)
           - Strip Symbols from Track Names
        3. File Name Safety
           - Sanitize tokens for safe filenames
      - Improved: Clear cyan help text appears when "FX Aliases" is selected
      - Logic: Chain Token Source = "FX Aliases" forces USE_ALIAS=1 regardless of other settings
      - More intuitive: No need to toggle multiple switches to enable alias mode
    - Updated: Debug output now shows Chain Token Source instead of Use FX Alias
      - Shows "Chain Token Source: Track Name/FX Aliases/FXChain"
      - Shows "Chain Alias Joiner" value when FX Aliases mode is active
      - Clearer indication of current naming mode

  251030.0845
    - Changed: File naming settings consolidated into single Settings menu.
      - Removed: "FX Name Formatting..." menu (replaced with comprehensive settings)
      - Added: "File Naming Settings..." menu consolidating all naming options
      - FX Name Formatting: Show Type/Vendor, Strip Symbols, Use FX Alias
      - Chain Mode Naming: Token Source (Track Name/FX Aliases/FXChain), Alias Joiner, Max FX Tokens, Track Name Strip Symbols
      - File Name Safety: Sanitize tokens for safe filenames
      - All settings persist between sessions and pass to AudioSweet Core via ExtState
    - Removed: Apply Method (Auto/Render/Glue) option from GUI.
      - AudioSweet Core now uses default behavior: Single item → Render, Multiple items → Glue
      - Simplified UI by removing unnecessary option (Auto mode works well for most cases)
    - Fixed: USE_ALIAS setting now correctly toggles FX Alias usage.
      - AudioSweet Core now reads USE_ALIAS from ExtState instead of hardcoded value
      - GUI setting "Use FX Alias for file naming" now properly controls alias behavior
    - Added: Comprehensive debug logging for all user interactions.
      - Script startup: Outputs all current settings when debug mode is enabled
      - Script close: Outputs final settings when closing
      - SOLO button: Shows scope (Track/Item Solo) and command ID
      - Keyboard shortcuts: Shows Space (Play/Stop) and S (Solo) key presses
    - Added: FX Alias Tools submenu in Settings menu.
      - Build FX Alias Database: Scans all plugins and creates/updates alias database
      - Export JSON to TSV: Converts JSON database to TSV for manual editing
      - Update TSV to JSON: Imports edited TSV back to JSON database
      - All tools accessible from GUI without needing to run separate scripts
    - Integration: AudioSweet Core v251030.0845+ required for new naming settings.
      - Core now reads all naming options from ExtState (chain token source, alias joiner, max tokens, etc.)
      - Ensures GUI and Core are always in sync for file naming behavior

  251029.2110
    - Improved: Preview Target Track Name moved to main GUI
      - Appears automatically when Chain mode is selected (lines 1395-1407)
      - Input field shows directly in main interface (more intuitive)
      - Setting persists when script is closed (auto-saved to ExtState)
      - Helper text: "(for preview without focused FX)"
      - No need to open Settings menu to change target track

  251029.2055
    - Improved: PREVIEW button auto-resets when transport stops
      - Detects when REAPER stops playing and automatically resets button state (lines 1095-1104)
      - Works when stopping via Space key, toolbar, or any other method
      - Button automatically changes from "STOP" back to "PREVIEW"
    - Improved: Chain mode can now preview without focused FX
      - Focused mode: requires valid focused FX to preview (as before)
      - Chain mode: only requires items, uses target track from settings (lines 1465-1478)
      - If FX is focused in chain mode, preview will use that FX chain (priority)
      - Allows previewing target track (e.g., "TEST") without opening any FX window

  251029.2050
    - Fixed: ImGui_PopStyleColor error when clicking PREVIEW button
      - Snapshot gui.is_previewing state before rendering to avoid push/pop mismatch
      - Ensures PushStyleColor and PopStyleColor are always paired correctly (line 1447)

  251029.2045
    - Added: Built-in keyboard shortcuts that work regardless of focus
      - Space key = Play/Stop (REAPER command 40044)
      - S key = Solo toggle (40281 for Track Solo, 41561 for Item Solo based on solo_scope setting)
      - Shortcuts work even when GUI is not focused (lines 1071-1082)
    - Improved: PREVIEW button is now a toggle (PREVIEW/STOP)
      - Click once to start preview, click again to stop
      - Button turns orange when previewing
      - Button label changes to "STOP" during preview (lines 1436-1453)
    - Added: Warning message for Item Solo lag in Preview Settings
      - Orange text appears when Item Solo is selected
      - Warns that Item Solo may have slight lag compared to Track Solo (lines 1250-1255)
    - Changed: Renamed run_preview() to toggle_preview() for clarity (line 575)

  251029.2030
    - Attempted: ConfigVar_NavCaptureKeyboard (not working in ImGui v0.10)
      - Built-in keyboard shortcuts implemented instead as workaround

  251029.2020
    - Added: AudioSweet Preview integration with full control via GUI
      - New three-button layout: [PREVIEW] [SOLO] [AUDIOSWEET]
      - Preview Settings menu (Settings → Preview Settings...)
      - Configurable target track name (default "AudioSweet")
      - Solo scope selection (Track Solo / Item Solo)
      - Restore mode selection (Time Selection / GUID)
      - Debug and chain_mode settings shared with main AudioSweet
      - SOLO button toggles based on solo_scope: Track (40281) or Item (41561)
    - Changed: Disabled Saved Chains and History features (feature flags: enable_saved_chains, enable_history)
      - GUI shows "under development" message when both features disabled
      - "Save This Chain" button hidden when enable_saved_chains = false
      - "History Settings..." menu disabled when enable_history = false
      - Features can be re-enabled by setting flags to true (lines 253-254)
    - Technical: run_preview() loads AS Preview Core and passes GUI settings as args
    - Technical: toggle_solo() uses REAPER commands 40281 (track) or 41561 (item)

  251029.1934
    - Verified: Channel Mode (Auto/Mono/Multi) now working correctly with AudioSweet Core v251029.1400.
      - Auto mode now correctly detects mono items (e.g., chanmode=2/3/4) and renders as mono
      - Fixed root cause: AudioSweet Core was using wrong API for chanmode detection
      - Integration confirmed: GUI → ExtState → AudioSweet Core → RGWH Core all working
    - Note: This version is compatible with:
      - AudioSweet Core v251029.1400+ (REQUIRED - contains critical chanmode API fix)
      - AudioSweet Core v251028_2315+
      - RGWH Core v251029.1400+ (contains matching chanmode fix)

  251029_1230
    - Added: Channel Mode control (Auto/Mono/Multi) in Apply settings.
      - New UI: Radio buttons below Apply method (lines 1182-1198)
      - Auto: Automatically decides based on item's channel mode setting (not just source)
      - Mono: Force mono render (single channel output)
      - Multi: Force multi-channel render (stereo/multi output)
      - Setting persists between sessions (saved in ExtState)
      - Passes to AudioSweet Core via AS_APPLY_FX_MODE ExtState (line 484)
    - Fixed: AS_APPLY_FX_MODE now properly set (was missing, causing auto-detect issues)

  251029_1218
    - Fixed: History recall now reliably focuses correct FX using REAPER native actions.
      - Previous: Used TrackFX_Show which failed for CLAP/VST3 plugins (focus detection issues)
      - Now: Uses REAPER actions 41749-41756 (Open/close UI for FX #1-8 on last touched track)
      - History now stores FX index (0-based) along with track GUID and name
      - For FX #1-8: Uses native action 41749+idx for reliable focus
      - For FX #9+: Falls back to TrackFX_Show (limitation of REAPER actions)
      - Validates FX still exists at stored index before execution
      - Lines: 349-401 (history storage), 788-862 (focused apply with action)
    - Technical: History storage format changed from "name|guid|trackname|mode" to "name|guid|trackname|mode|fxidx"
    - Integration: Works with AudioSweet Core v251028_2315 (ExtState override support)

  251028_2245
    - Added: FX Name Formatting UI in Settings menu.
      - New menu item: Settings → FX Name Formatting... (line 961-963)
      - Popup modal with three checkboxes and examples (lines 1010-1045)
      - Show Plugin Type: Adds format prefix (CLAP:, VST3:, AU:, VST:) to file names
      - Show Vendor Name: Includes vendor in parentheses (FabFilter)
      - Strip Spaces & Symbols: Removes spaces/symbols for cleaner names (ProQ4 vs Pro-Q 4)
      - Changes auto-save to ExtState and propagate to AudioSweet Core
      - Solves issue where code default changes didn't apply due to ExtState caching
      - Example display shows different combinations: 'AS1-CLAP: Pro-Q 4 (FabFilter)' vs 'AS1-CLAP:ProQ4'

  251028_2240
    - Added: FX name formatting control via ExtState.
      - New GUI state variables: fxname_show_type (true), fxname_show_vendor (false), fxname_strip_symbol (true)
      - GUI sets ExtState keys: FXNAME_SHOW_TYPE, FXNAME_SHOW_VENDOR, FXNAME_STRIP_SYMBOL
      - AudioSweet Core reads these ExtState values to format FX names in rendered file names
      - Show Type = true → includes plugin format prefix (CLAP:, VST3:, AU:, VST:)
      - Show Vendor = true → includes vendor name in parentheses (FabFilter)
      - Strip Symbol = true → removes spaces and symbols from names
      - Lines: 161-163, 193-195, 225-227, 444-446

  251028_2235
    - Fixed: History button now calls run_history_item() instead of run_saved_chain_apply_mode().
      - Previous: History buttons were hardcoded to always use chain mode
      - Now: History buttons respect the original mode (focused/chain)
      - Line 1155: Changed from run_saved_chain_apply_mode() to run_history_item()

  251028_2230
    - Fixed: History items from Focused mode now correctly execute in focused mode.
      - Previous: All history items executed as chain mode (processed entire FX chain)
      - Now: Focused history items find and focus the specific FX by name
      - New function: run_history_focused_apply() searches FX by name, focuses it, runs Core in focused mode
      - Chain mode history items continue to use chain mode (correct behavior)
      - Lines: 733-824, 851-857
    - Improved: FX name matching for history replay (supports partial matching)

  251028_2215
    - Added: Debug console logging with [AS GUI] prefix.
      - Shows saved chain execution details (name, items, FX count)
      - Reports FX focus attempts and timing
      - Displays execution parameters (mode, action, handle)
      - Logs success/error results
      - Lines: 587-589, 599-601, 620-621, 627-629, 637-647, 663-680

  251028_2210
    - Added: Clear History button in History panel.
      - Small button positioned at top-right of History section
      - Clears all history items from memory and ProjExtState
      - Lines 991-1000

  251028_2200
    - Improved: Enhanced FX focus mechanism for better CLAP plugin compatibility.
      - Extended timeout from 500ms to 1 second
      - Multiple focus attempts with different methods:
        1. Show FX chain window (TrackFX_Show flag 3)
        2. Show floating FX window (TrackFX_Show flag 1)
        3. Retry FX chain window
      - Better error message: "CLAP plugins may need manual focus"
      - Chain mode: Lines 452-483
      - Saved chain apply: Lines 561-592
    - Fixed: History items now properly execute with their original mode (focused/chain).
      - run_history_item() rewritten to respect stored mode
      - Lines 644-690

  251028_2145
    - Fixed: Saved Chains and History now auto-focus FX before execution.
      - Previous: Failed when all FX windows were closed (GetFocusedFX returned 0)
      - Now: Automatically shows and focuses track FX, waits up to 500ms for focus
      - Displays clear error if FX cannot be focused
      - Chain mode: Lines 442-460
      - Saved chain apply: Lines 534-552
    - Fixed: load_history() error - changed MAX_HISTORY to gui.max_history (line 266)

  251028_2130
    - Added: Settings menu with configurable History size (1-50 items, default 10).
      - Menu: Settings → History Settings...
      - Setting saved persistently in ExtState
      - History auto-trims when size is reduced
      - Functions: Lines 91, 120, 149, 638-685
    - Fixed: Saved Chains and History now properly use AudioSweet/RGWH pipeline.
      - Previous: Used native REAPER command 40361 (direct render, no naming/handle)
      - Now: Focus track FX and execute via AudioSweet Core
      - Properly applies AudioSweet naming conventions and RGWH handle settings
      - Chain mode execution: Lines 420-451
      - Saved chain apply: Lines 520-556

  251028_2045
    - Added: GUI settings persistence - all settings now saved and restored between sessions.
      - Settings saved: mode, action, copy_scope, copy_pos, apply_method, handle_seconds, debug
      - Uses ExtState (hsuanice_AS_GUI namespace) for persistent storage
      - Auto-saves whenever any setting is changed
      - Auto-loads on startup (line 819)
      - Functions: save_gui_settings() / load_gui_settings() (lines 99-137)

  251028_2030
    - Fixed: Handle seconds setting now works correctly in Focused mode.
      - Root cause: AudioSweet Core v251022_1617 was using hardcoded 5.0s default
      - Solution: Updated Core to v251028_2050 (reads from ProjExtState first)
      - GUI already correctly sets ProjExtState before execution (line 302)
      - Requires: AudioSweet Core v251028_2050 or later

  251028_2015
    - Changed: Status display moved to below RUN button (above Saved Chains/History).
      - Previous: Status appeared at bottom of window
      - Now: Immediate feedback right after clicking RUN
    - Changed: RUN AUDIOSWEET button repositioned above Saved Chains/History.
      - More logical flow: configure → run → see status → quick actions
    - Fixed: Handle seconds setting now properly applied to saved chain execution.
      - Handle value forwarded to RGWH Core via ProjExtState before apply
    - Fixed: Debug mode fully functional - no console output when disabled.
      - Chain/Saved execution uses native command (bypass AudioSweet Core)
      - Focused mode respects ExtState debug flag
    - Integration: Full ExtState control for debug output (hsuanice_AS/DEBUG).
      - Works seamlessly with AudioSweet Core v251028_2011
    - UI: Cleaner visual hierarchy and workflow

  v251028_0003
    - Changed: Combo boxes replaced with Radio buttons for better UX
    - Changed: Compact horizontal layout for controls
    - Added: History tracking for recent FX/Chain operations
    - Changed: Debug moved to Menu Bar
    - Improved: Quick Process area (Saved Chains + History)

  v251028_0002
    - Added: Chain mode displays track FX chain
    - Added: FX Chain memory system
    - Added: One-click saved chain execution
]]--

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------
local r = reaper
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local RES_PATH = r.GetResourcePath()
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_AudioSweet Core.lua'
local PREVIEW_CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_AS Preview Core.lua'

------------------------------------------------------------
-- ImGui Context
------------------------------------------------------------
local ctx = ImGui.CreateContext('AudioSweet GUI')

------------------------------------------------------------
-- GUI State
------------------------------------------------------------
local gui = {
  open = true,
  mode = 0,              -- 0=focused, 1=chain
  action = 0,            -- 0=apply, 1=copy
  copy_scope = 0,
  copy_pos = 0,
  channel_mode = 0,      -- 0=auto, 1=mono, 2=multi
  handle_seconds = 5.0,
  debug = false,
  max_history = 10,      -- Maximum number of history items to keep
  show_fx_on_recall = true,    -- Show FX window when executing SAVED CHAIN/HISTORY
  fxname_show_type = true,     -- Show FX type prefix (CLAP:, VST3:, etc.)
  fxname_show_vendor = true,  -- Show vendor name in parentheses
  fxname_strip_symbol = true,  -- Strip spaces and symbols
  use_alias = false,           -- Use FX Alias for file naming
  -- Chain mode naming
  chain_token_source = 0,      -- 0=track, 1=aliases, 2=fxchain
  chain_alias_joiner = "",     -- Joiner for aliases mode
  max_fx_tokens = 3,           -- FIFO limit for FX tokens
  trackname_strip_symbols = true,  -- Strip symbols from track names
  sanitize_token = false,      -- Sanitize tokens for safe filenames
  is_running = false,
  last_result = "",
  focused_fx_name = "",
  focused_track = nil,
  focused_track_name = "",
  focused_track_fx_list = {},
  saved_chains = {},
  history = {},
  new_chain_name = "",
  show_save_popup = false,
  show_settings_popup = false,
  show_fxname_popup = false,
  show_preview_settings = false,
  show_naming_popup = false,
  show_target_track_popup = false,
  -- Preview settings
  preview_target_track = "AudioSweet",
  preview_solo_scope = 0,     -- 0=track, 1=item
  preview_restore_mode = 0,   -- 0=timesel, 1=guid
  is_previewing = false,      -- Track if preview is currently playing
  -- Feature flags
  enable_saved_chains = true,   -- Now working with OVERRIDE ExtState mechanism
  enable_history = true,        -- Now working with OVERRIDE ExtState mechanism
  -- UI settings
  enable_docking = false,       -- Allow window docking
}

------------------------------------------------------------
-- GUI Settings Persistence
------------------------------------------------------------
local SETTINGS_NAMESPACE = "hsuanice_AS_GUI"

local function save_gui_settings()
  r.SetExtState(SETTINGS_NAMESPACE, "mode", tostring(gui.mode), true)
  r.SetExtState(SETTINGS_NAMESPACE, "action", tostring(gui.action), true)
  r.SetExtState(SETTINGS_NAMESPACE, "copy_scope", tostring(gui.copy_scope), true)
  r.SetExtState(SETTINGS_NAMESPACE, "copy_pos", tostring(gui.copy_pos), true)
  r.SetExtState(SETTINGS_NAMESPACE, "channel_mode", tostring(gui.channel_mode), true)
  r.SetExtState(SETTINGS_NAMESPACE, "handle_seconds", tostring(gui.handle_seconds), true)
  r.SetExtState(SETTINGS_NAMESPACE, "debug", gui.debug and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "max_history", tostring(gui.max_history), true)
  r.SetExtState(SETTINGS_NAMESPACE, "show_fx_on_recall", gui.show_fx_on_recall and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_show_type", gui.fxname_show_type and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_show_vendor", gui.fxname_show_vendor and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_strip_symbol", gui.fxname_strip_symbol and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "use_alias", gui.use_alias and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "chain_token_source", tostring(gui.chain_token_source), true)
  r.SetExtState(SETTINGS_NAMESPACE, "chain_alias_joiner", gui.chain_alias_joiner, true)
  r.SetExtState(SETTINGS_NAMESPACE, "max_fx_tokens", tostring(gui.max_fx_tokens), true)
  r.SetExtState(SETTINGS_NAMESPACE, "trackname_strip_symbols", gui.trackname_strip_symbols and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "sanitize_token", gui.sanitize_token and "1" or "0", true)
  -- Preview settings
  r.SetExtState(SETTINGS_NAMESPACE, "preview_target_track", gui.preview_target_track, true)
  r.SetExtState(SETTINGS_NAMESPACE, "preview_solo_scope", tostring(gui.preview_solo_scope), true)
  r.SetExtState(SETTINGS_NAMESPACE, "preview_restore_mode", tostring(gui.preview_restore_mode), true)
  -- UI settings
  r.SetExtState(SETTINGS_NAMESPACE, "enable_docking", gui.enable_docking and "1" or "0", true)
end

local function load_gui_settings()
  local function get_int(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and tonumber(val) or default
  end

  local function get_bool(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    if val == "" then return default end
    return val == "1"
  end

  local function get_float(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and tonumber(val) or default
  end

  gui.mode = get_int("mode", 0)
  gui.action = get_int("action", 0)
  gui.copy_scope = get_int("copy_scope", 0)
  gui.copy_pos = get_int("copy_pos", 0)
  gui.channel_mode = get_int("channel_mode", 0)
  gui.handle_seconds = get_float("handle_seconds", 5.0)
  gui.debug = get_bool("debug", false)
  gui.max_history = get_int("max_history", 10)
  gui.show_fx_on_recall = get_bool("show_fx_on_recall", true)
  gui.fxname_show_type = get_bool("fxname_show_type", true)
  gui.fxname_show_vendor = get_bool("fxname_show_vendor", false)
  gui.fxname_strip_symbol = get_bool("fxname_strip_symbol", true)
  gui.use_alias = get_bool("use_alias", false)
  gui.chain_token_source = get_int("chain_token_source", 0)
  gui.max_fx_tokens = get_int("max_fx_tokens", 3)
  gui.trackname_strip_symbols = get_bool("trackname_strip_symbols", true)
  gui.sanitize_token = get_bool("sanitize_token", false)
  -- Preview settings
  local function get_string(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and val or default
  end
  gui.chain_alias_joiner = get_string("chain_alias_joiner", "")
  gui.preview_target_track = get_string("preview_target_track", "AudioSweet")
  gui.preview_solo_scope = get_int("preview_solo_scope", 0)
  gui.preview_restore_mode = get_int("preview_restore_mode", 0)
  -- UI settings
  gui.enable_docking = get_bool("enable_docking", false)

  -- Debug output on startup
  if gui.debug then
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("[AS GUI] Script startup - Current settings:\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg(string.format("  Mode: %s\n", gui.mode == 0 and "Focused" or "Chain"))
    r.ShowConsoleMsg(string.format("  Action: %s\n", gui.action == 0 and "Apply" or "Copy"))
    r.ShowConsoleMsg(string.format("  Copy Scope: %s\n", gui.copy_scope == 0 and "Active" or "All"))
    r.ShowConsoleMsg(string.format("  Copy Position: %s\n", gui.copy_pos == 0 and "Last" or "Replace"))
    local channel_mode_names = {"Auto", "Mono", "Multi"}
    r.ShowConsoleMsg(string.format("  Channel Mode: %s\n", channel_mode_names[gui.channel_mode + 1]))
    r.ShowConsoleMsg(string.format("  Handle Seconds: %.2f\n", gui.handle_seconds))
    r.ShowConsoleMsg(string.format("  Debug Mode: %s\n", gui.debug and "ON" or "OFF"))
    r.ShowConsoleMsg(string.format("  Max History: %d\n", gui.max_history))
    r.ShowConsoleMsg(string.format("  FX Name - Show Type: %s\n", gui.fxname_show_type and "ON" or "OFF"))
    r.ShowConsoleMsg(string.format("  FX Name - Show Vendor: %s\n", gui.fxname_show_vendor and "ON" or "OFF"))
    r.ShowConsoleMsg(string.format("  FX Name - Strip Symbol: %s\n", gui.fxname_strip_symbol and "ON" or "OFF"))
    r.ShowConsoleMsg(string.format("  FX Name - Use Alias: %s\n", gui.use_alias and "ON" or "OFF"))
    r.ShowConsoleMsg(string.format("  Max FX Tokens: %d\n", gui.max_fx_tokens))
    local chain_token_source_names = {"Track Name", "FX Aliases", "FXChain"}
    r.ShowConsoleMsg(string.format("  Chain Token Source: %s\n", chain_token_source_names[gui.chain_token_source + 1]))
    if gui.chain_token_source == 1 then
      r.ShowConsoleMsg(string.format("  Chain Alias Joiner: '%s'\n", gui.chain_alias_joiner))
    end
    r.ShowConsoleMsg(string.format("  Track Name Strip Symbols: %s\n", gui.trackname_strip_symbols and "ON" or "OFF"))
    r.ShowConsoleMsg(string.format("  Preview Target Track: %s\n", gui.preview_target_track))
    local solo_scope_names = {"Track Solo", "Item Solo"}
    r.ShowConsoleMsg(string.format("  Preview Solo Scope: %s\n", solo_scope_names[gui.preview_solo_scope + 1]))
    local restore_mode_names = {"Keep", "Restore"}
    r.ShowConsoleMsg(string.format("  Preview Restore Mode: %s\n", restore_mode_names[gui.preview_restore_mode + 1]))
    r.ShowConsoleMsg("========================================\n")
  end
end

------------------------------------------------------------
-- Track FX Chain Helpers
------------------------------------------------------------
local function get_track_guid(tr)
  if not tr then return nil end
  return r.GetTrackGUID(tr)
end

local function get_track_name_and_number(tr)
  if not tr then return "", 0 end
  local track_num = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0
  local _, track_name = r.GetTrackName(tr, "")
  return track_name or "", track_num
end

local function get_track_fx_chain(tr)
  local fx_list = {}
  if not tr then return fx_list end
  local fx_count = r.TrackFX_GetCount(tr)
  for i = 0, fx_count - 1 do
    local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
    fx_list[#fx_list + 1] = {
      index = i,
      name = fx_name or "(unknown)",
      enabled = r.TrackFX_GetEnabled(tr, i),
      offline = r.TrackFX_GetOffline(tr, i),
    }
  end
  return fx_list
end

------------------------------------------------------------
-- Saved Chain Management
------------------------------------------------------------
local CHAIN_NAMESPACE = "hsuanice_AS_SavedChains"
local HISTORY_NAMESPACE = "hsuanice_AS_History"

local function load_saved_chains()
  gui.saved_chains = {}
  local idx = 0
  while true do
    local ok, data = r.GetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx)
    if ok == 0 or data == "" then break end
    local name, guid, track_name = data:match("^([^|]*)|([^|]*)|(.*)$")
    if name and guid then
      gui.saved_chains[#gui.saved_chains + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
      }
    end
    idx = idx + 1
  end
end

local function save_chains_to_extstate()
  local idx = 0
  while true do
    local ok = r.GetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx)
    if ok == 0 then break end
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx, "")
    idx = idx + 1
  end
  for i, chain in ipairs(gui.saved_chains) do
    local data = string.format("%s|%s|%s", chain.name, chain.track_guid, chain.track_name)
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. (i - 1), data)
  end
end

local function add_saved_chain(name, track_guid, track_name)
  gui.saved_chains[#gui.saved_chains + 1] = {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
  }
  save_chains_to_extstate()
end

local function delete_saved_chain(idx)
  table.remove(gui.saved_chains, idx)
  save_chains_to_extstate()
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if get_track_guid(tr) == guid then
      return tr
    end
  end
  return nil
end

------------------------------------------------------------
-- History Management
------------------------------------------------------------
local function load_history()
  gui.history = {}
  local idx = 0
  while idx < gui.max_history do
    local ok, data = r.GetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. idx)
    if ok == 0 or data == "" then break end
    local name, guid, track_name, mode, fx_idx_str = data:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if name and guid then
      gui.history[#gui.history + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
        mode = mode or "chain",
        fx_index = tonumber(fx_idx_str) or 0,
      }
    end
    idx = idx + 1
  end
end

local function add_to_history(name, track_guid, track_name, mode, fx_index)
  fx_index = fx_index or 0

  -- Remove if already exists
  for i = #gui.history, 1, -1 do
    if gui.history[i].name == name and gui.history[i].track_guid == track_guid then
      table.remove(gui.history, i)
    end
  end

  -- Add to front
  table.insert(gui.history, 1, {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
    mode = mode,
    fx_index = fx_index,
  })

  -- Trim to max_history
  while #gui.history > gui.max_history do
    table.remove(gui.history)
  end

  -- Save to ExtState
  for i = 0, gui.max_history - 1 do
    r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
  end
  for i, item in ipairs(gui.history) do
    local data = string.format("%s|%s|%s|%s|%d", item.name, item.track_guid, item.track_name, item.mode, item.fx_index)
    r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. (i - 1), data)
  end
end

------------------------------------------------------------
-- Focused FX Detection
------------------------------------------------------------
local function normalize_focused_fx_index(idx)
  if idx >= 0x2000000 then idx = idx - 0x2000000 end
  if idx >= 0x1000000 then idx = idx - 0x1000000 end
  return idx
end

local function get_focused_fx_info()
  local retval, trackOut, itemOut, fxOut = r.GetFocusedFX()
  if retval == 1 then
    local tr = r.GetTrack(0, math.max(0, (trackOut or 1) - 1))
    if tr then
      local fx_index = normalize_focused_fx_index(fxOut or 0)
      local _, name = r.TrackFX_GetFXName(tr, fx_index, "")
      return true, "Track FX", name or "(unknown)", tr
    end
  elseif retval == 2 then
    return true, "Take FX", "(Take FX not supported)", nil
  end
  return false, "None", "No focused FX", nil
end

local function update_focused_fx_display()
  local found, fx_type, fx_name, tr = get_focused_fx_info()
  gui.focused_track = tr
  if found then
    if fx_type == "Track FX" then
      gui.focused_fx_name = fx_name
      if tr then
        local track_name, track_num = get_track_name_and_number(tr)
        gui.focused_track_name = string.format("#%d - %s", track_num, track_name)
        gui.focused_track_fx_list = get_track_fx_chain(tr)
      end
      return true
    else
      gui.focused_fx_name = fx_name .. " (WARNING)"
      gui.focused_track_name = ""
      gui.focused_track_fx_list = {}
      return false
    end
  else
    gui.focused_fx_name = "No focused FX"
    gui.focused_track_name = ""
    gui.focused_track_fx_list = {}
    return false
  end
end

------------------------------------------------------------
-- AudioSweet Execution
------------------------------------------------------------
local function set_extstate_from_gui()
  local mode_names = { "focused", "chain" }
  local action_names = { "apply", "copy" }
  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local channel_names = { "auto", "mono", "multi" }

  r.SetExtState("hsuanice_AS", "AS_MODE", mode_names[gui.mode + 1], false)
  r.SetExtState("hsuanice_AS", "AS_ACTION", action_names[gui.action + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_SCOPE", scope_names[gui.copy_scope + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_POS", pos_names[gui.copy_pos + 1], false)
  r.SetExtState("hsuanice_AS", "AS_APPLY_FX_MODE", channel_names[gui.channel_mode + 1], false)
  r.SetExtState("hsuanice_AS", "DEBUG", gui.debug and "1" or "0", false)

  -- File Naming ExtStates
  r.SetExtState("hsuanice_AS", "USE_ALIAS", gui.use_alias and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_TYPE", gui.fxname_show_type and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_VENDOR", gui.fxname_show_vendor and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_STRIP_SYMBOL", gui.fxname_strip_symbol and "1" or "0", false)
  local chain_token_names = {"track", "aliases", "fxchain"}
  r.SetExtState("hsuanice_AS", "AS_CHAIN_TOKEN_SOURCE", chain_token_names[gui.chain_token_source + 1], false)
  r.SetExtState("hsuanice_AS", "AS_CHAIN_ALIAS_JOINER", gui.chain_alias_joiner, false)
  r.SetExtState("hsuanice_AS", "AS_MAX_FX_TOKENS", tostring(gui.max_fx_tokens), false)
  r.SetExtState("hsuanice_AS", "TRACKNAME_STRIP_SYMBOLS", gui.trackname_strip_symbols and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "SANITIZE_TOKEN_FOR_FILENAME", gui.sanitize_token and "1" or "0", false)

  -- Debug output
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] ExtState: channel_mode=%s (gui.channel_mode=%d)\n",
      channel_names[gui.channel_mode + 1], gui.channel_mode))
  end
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)  -- Always disable summary dialog
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))

  -- Set RGWH Core debug level (0 = silent, no console output)
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", gui.debug and "2" or "0")

  -- Set FX name formatting options
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_TYPE", gui.fxname_show_type and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_VENDOR", gui.fxname_show_vendor and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_STRIP_SYMBOL", gui.fxname_strip_symbol and "1" or "0", false)
end

------------------------------------------------------------
-- Preview & Solo Functions
------------------------------------------------------------
local function toggle_preview()
  -- Check if transport is playing (includes previews started by Tools scripts)
  local play_state = r.GetPlayState()
  local is_playing = (play_state & 1 ~= 0)

  -- If transport is playing (GUI preview or Tools script preview), stop it
  if gui.is_previewing or is_playing then
    r.Main_OnCommand(40044, 0)  -- Transport: Stop
    gui.is_previewing = false
    gui.last_result = "Preview stopped"
    return
  end

  -- Otherwise, start preview
  if gui.is_running then return end

  -- Load AS Preview Core
  local ok, ASP = pcall(dofile, PREVIEW_CORE_PATH)
  if not ok or type(ASP) ~= "table" or type(ASP.preview) ~= "function" then
    gui.last_result = "Error: Preview Core not found"
    return
  end

  gui.is_running = true
  gui.last_result = "Running Preview..."

  -- Prepare arguments
  local solo_scope_names = { "track", "item" }
  local restore_mode_names = { "timesel", "guid" }

  -- Determine target track for chain mode
  local target_track_name = gui.preview_target_track  -- Default to settings
  if gui.mode == 1 then
    -- Chain mode: prioritize focused FX chain track if available
    if gui.focused_track and r.ValidatePtr2(0, gui.focused_track, "MediaTrack*") then
      -- Get pure track name from track object (P_NAME doesn't include track number)
      local _, pure_name = r.GetSetMediaTrackInfo_String(gui.focused_track, "P_NAME", "", false)
      target_track_name = pure_name
      if gui.debug then
        r.ShowConsoleMsg("[AudioSweet] Chain preview using focused FX chain track: " .. (gui.focused_track_name or pure_name) .. "\n")
      end
    else
      if gui.debug then
        r.ShowConsoleMsg("[AudioSweet] Chain preview using settings target track: " .. target_track_name .. "\n")
      end
    end
  end

  local args = {
    debug = gui.debug,
    chain_mode = (gui.mode == 1),  -- 0=focused, 1=chain
    mode = "solo",
    -- Don't set target explicitly; let Preview Core use target_track_name directly
    target_track_name = target_track_name,
    solo_scope = solo_scope_names[gui.preview_solo_scope + 1],
    restore_mode = restore_mode_names[gui.preview_restore_mode + 1],
  }

  -- Run preview
  local preview_ok, preview_err = pcall(ASP.preview, args)

  if preview_ok then
    gui.last_result = "Preview: Success"
    gui.is_previewing = true
  else
    gui.last_result = "Preview Error: " .. tostring(preview_err)
    gui.is_previewing = false
  end

  gui.is_running = false
end

local function toggle_solo()
  -- Debug logging
  if gui.debug then
    local scope_name = (gui.preview_solo_scope == 0) and "Track Solo" or "Item Solo"
    r.ShowConsoleMsg(string.format("[AS GUI] SOLO button clicked (scope=%s, mode=%s)\n",
      scope_name, gui.mode == 0 and "Focused" or "Chain"))
  end

  -- Toggle solo based on solo_scope setting
  if gui.preview_solo_scope == 0 then
    -- Track solo: determine target track based on mode
    local target_track = nil
    local track_name = ""

    if gui.mode == 0 then
      -- Focused mode: use focused track
      target_track = gui.focused_track
      track_name = gui.focused_track_name
    else
      -- Chain mode: use preview target track or focused track
      if gui.focused_track then
        -- If there's a focused FX chain, use that track
        target_track = gui.focused_track
        track_name = gui.focused_track_name
      else
        -- Otherwise find track by preview_target_track name
        local tc = r.CountTracks(0)
        for i = 0, tc - 1 do
          local tr = r.GetTrack(0, i)
          local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
          if tn == gui.preview_target_track then
            target_track = tr
            track_name = gui.preview_target_track
            break
          end
        end
      end
    end

    if target_track then
      local current_solo = r.GetMediaTrackInfo_Value(target_track, "I_SOLO")
      -- Toggle: 0=unsolo, 1=solo, 2=solo in place
      -- Simple toggle: if any solo state, set to 0; if 0, set to 1
      local new_solo = (current_solo == 0) and 1 or 0
      r.SetMediaTrackInfo_Value(target_track, "I_SOLO", new_solo)

      if gui.debug then
        r.ShowConsoleMsg(string.format("[AS GUI] Toggled track solo: %s -> %s (Track: %s)\n",
          current_solo, new_solo, track_name))
      end
    else
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] No target track found for solo\n")
      end
    end
  else
    -- Item solo (41561): operate on selected items
    r.Main_OnCommand(41561, 0)
  end
end

------------------------------------------------------------
-- AudioSweet Run Function
------------------------------------------------------------
local function run_audiosweet(override_track)
  if gui.is_running then return end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  local target_track = override_track or gui.focused_track

  if not override_track then
    local has_valid_fx = update_focused_fx_display()
    if not has_valid_fx then
      gui.last_result = "Error: No valid Track FX focused"
      return
    end
  end

  if not target_track then
    gui.last_result = "Error: Target track not found"
    return
  end

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  -- Only use Core for focused FX mode
  -- (Core needs GetFocusedFX to work properly)
  if gui.mode == 0 and not override_track then
    set_extstate_from_gui()

    local ok, err = pcall(dofile, CORE_PATH)
    r.UpdateArrange()

    if ok then
      gui.last_result = string.format("Success! (%d items)", item_count)

      -- Add to history
      if gui.focused_track then
        local track_guid = get_track_guid(gui.focused_track)
        local name = gui.focused_fx_name
        -- Get FX index from GetFocusedFX
        local retval, trackidx, itemidx, fxidx = r.GetFocusedFX()
        local fx_index = (retval == 1) and normalize_focused_fx_index(fxidx or 0) or 0
        add_to_history(name, track_guid, gui.focused_track_name, "focused", fx_index)
      end
    else
      gui.last_result = "Error: " .. tostring(err)
    end
  else
    -- For chain mode, focus first FX and use AudioSweet Core
    local fx_count = r.TrackFX_GetCount(target_track)
    if fx_count == 0 then
      gui.last_result = "Error: No FX on target track"
      r.PreventUIRefresh(-1)
      r.Undo_EndBlock("AudioSweet GUI (error)", -1)
      gui.is_running = false
      return
    end

    -- Set track as last touched (without changing selection)
    -- Note: OVERRIDE ExtState tells Core which track to use
    -- We don't call SetOnlyTrackSelected() to preserve item selection
    r.SetMixerScroll(target_track)

    -- Set ExtState for AudioSweet (chain mode)
    set_extstate_from_gui()
    r.SetExtState("hsuanice_AS", "AS_MODE", "chain", false)

    -- Set OVERRIDE ExtState to specify track and FX for Core
    -- (bypasses GetFocusedFX check which fails for CLAP plugins)
    local track_idx = r.CSurf_TrackToID(target_track, false) - 1  -- Convert to 0-based index
    r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(track_idx), false)
    r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", "0", false)  -- Chain mode uses first FX

    -- Run AudioSweet Core
    local ok, err = pcall(dofile, CORE_PATH)
    r.UpdateArrange()

    if ok then
      gui.last_result = string.format("Success! (%d items)", item_count)

      -- Add to history
      if target_track then
        local track_guid = get_track_guid(target_track)
        local track_name, track_num = get_track_name_and_number(target_track)
        local name = string.format("#%d - %s", track_num, track_name)
        add_to_history(name, track_guid, name, "chain", 0)  -- chain mode uses index 0
      end
    else
      gui.last_result = "Error: " .. tostring(err)
    end
  end

  r.PreventUIRefresh(-1)
  local mode_name = (gui.mode == 0) and "Focused" or "Chain"
  local action_name = (gui.action == 0) and "Apply" or "Copy"
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s %s", mode_name, action_name), -1)

  gui.is_running = false
end

local function run_focused_fx_copy_mode(tr, fx_name, fx_idx, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Focused FX copy: '%s' (fx_idx=%d, items=%d)\n", fx_name, fx_idx, item_count))
  end

  local fx_count = r.TrackFX_GetCount(tr)
  if fx_idx >= fx_count then
    gui.last_result = string.format("Error: FX #%d not found", fx_idx + 1)
    gui.is_running = false
    return
  end

  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local scope = scope_names[gui.copy_scope + 1]
  local pos = pos_names[gui.copy_pos + 1]

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Copy settings: scope=%s, position=%s\n", scope, pos))
  end

  local ops = 0
  for i = 0, item_count - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then
      if scope == "all_takes" then
        local take_count = r.CountTakes(it)
        for t = 0, take_count - 1 do
          local tk = r.GetTake(it, t)
          if tk then
            local dest_idx = (pos == "head") and 0 or r.TakeFX_GetCount(tk)
            r.TrackFX_CopyToTake(tr, fx_idx, tk, dest_idx, false)
            ops = ops + 1
          end
        end
      else
        local tk = r.GetActiveTake(it)
        if tk then
          local dest_idx = (pos == "head") and 0 or r.TakeFX_GetCount(tk)
          r.TrackFX_CopyToTake(tr, fx_idx, tk, dest_idx, false)
          ops = ops + 1
        end
      end
    end
  end

  r.UpdateArrange()

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Focused FX copy completed: %d operations\n", ops))
  end

  gui.last_result = string.format("Success! [%s] Copy (%d ops)", fx_name, ops)
  gui.is_running = false
end

local function run_saved_chain_copy_mode(tr, chain_name, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Chain copy: '%s' (items=%d)\n", chain_name, item_count))
  end

  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = "Error: No FX on track"
    gui.is_running = false
    return
  end

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Track has %d FX to copy\n", fx_count))
  end

  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local scope = scope_names[gui.copy_scope + 1]
  local pos = pos_names[gui.copy_pos + 1]

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Copy settings: scope=%s, position=%s\n", scope, pos))
  end

  local ops = 0
  for i = 0, item_count - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then
      if scope == "all_takes" then
        local take_count = r.CountTakes(it)
        for t = 0, take_count - 1 do
          local tk = r.GetTake(it, t)
          if tk then
            for fx = 0, fx_count - 1 do
              local dest_idx = (pos == "head") and 0 or r.TakeFX_GetCount(tk)
              r.TrackFX_CopyToTake(tr, fx, tk, dest_idx, false)
              ops = ops + 1
            end
          end
        end
      else
        local tk = r.GetActiveTake(it)
        if tk then
          if pos == "head" then
            for fx = fx_count - 1, 0, -1 do
              r.TrackFX_CopyToTake(tr, fx, tk, 0, false)
              ops = ops + 1
            end
          else
            for fx = 0, fx_count - 1 do
              local dest_idx = r.TakeFX_GetCount(tk)
              r.TrackFX_CopyToTake(tr, fx, tk, dest_idx, false)
              ops = ops + 1
            end
          end
        end
      end
    end
  end

  r.UpdateArrange()

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Chain copy completed: %d operations\n", ops))
  end

  gui.last_result = string.format("Success! [%s] Copy (%d ops)", chain_name, ops)
  gui.is_running = false
end

local function run_saved_chain_apply_mode(tr, chain_name, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Saved chain apply: '%s' (items=%d)\n", chain_name, item_count))
  end

  -- Check if track has FX
  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = "Error: No FX on track"
    gui.is_running = false
    return
  end

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Track has %d FX\n", fx_count))
  end

  -- Set track as last touched (without changing selection)
  -- Note: We don't call SetOnlyTrackSelected() to preserve item selection
  -- Core will snapshot the current selection and restore it at the end
  r.SetMixerScroll(tr)

  -- Open FX chain window if setting enabled
  if gui.show_fx_on_recall then
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Opening FX chain window for target track\n")
    end
    -- Use TrackFX_Show to open the specific track's FX chain
    -- Flag 1 = show FX chain window
    r.TrackFX_Show(tr, 0, 1)
  else
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Skipping FX chain window (show_fx_on_recall = false)\n")
    end
  end

  if gui.debug then
    r.ShowConsoleMsg("[AS GUI] Track set as last touched\n")
  end

  -- Set ExtState for AudioSweet (chain mode)
  local action_names = { "apply", "copy" }

  r.SetExtState("hsuanice_AS", "AS_MODE", "chain", false)
  r.SetExtState("hsuanice_AS", "AS_ACTION", action_names[gui.action + 1], false)
  r.SetExtState("hsuanice_AS", "DEBUG", gui.debug and "1" or "0", false)

  -- Set OVERRIDE ExtState to specify track and FX for Core
  -- (bypasses GetFocusedFX check which fails for CLAP plugins)
  local track_idx = r.CSurf_TrackToID(tr, false) - 1  -- Convert to 0-based index
  r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(track_idx), false)
  r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", "0", false)  -- Chain mode uses first FX

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] OVERRIDE set: track_idx=%d fx_idx=0\n", track_idx))
  end
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(gui.handle_seconds))
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", gui.debug and "2" or "0")

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Executing AudioSweet Core (mode=chain, action=%s, handle=%.1fs)\n",
      gui.action == 0 and "apply" or "copy", gui.handle_seconds))
  end

  -- Run AudioSweet Core (it will use the focused track's FX chain)
  -- Note: Core handles selection save/restore internally
  local ok, err = pcall(dofile, CORE_PATH)
  r.UpdateArrange()

  if ok then
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] Execution completed successfully\n"))
    end
    gui.last_result = string.format("Success! [%s] Apply (%d items)", chain_name, item_count)
  else
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] ERROR: %s\n", tostring(err)))
    end
    gui.last_result = "Error: " .. tostring(err)
  end

  gui.is_running = false
end

local function open_saved_chain_fx(chain_idx)
  local chain = gui.saved_chains[chain_idx]
  if not chain then return end

  local tr = find_track_by_guid(chain.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", chain.track_name)
    return
  end

  -- Select track and toggle FX chain window (chain mode uses entire FX chain)
  r.SetOnlyTrackSelected(tr)
  r.SetMixerScroll(tr)

  -- Check if FX chain window is visible and toggle it
  local chain_visible = r.TrackFX_GetChainVisible(tr)
  if chain_visible == -1 then
    -- Chain window is closed, open it
    r.TrackFX_Show(tr, 0, 1)  -- Show chain window
  else
    -- Chain window is open, close it
    r.TrackFX_Show(tr, 0, 0)  -- Hide chain window
  end

  gui.last_result = string.format("Toggled FX chain: %s", chain.name)
end

local function open_history_fx(hist_idx)
  local hist_item = gui.history[hist_idx]
  if not hist_item then return end

  local tr = find_track_by_guid(hist_item.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", hist_item.track_name)
    return
  end

  -- Select track and set as last touched
  r.SetOnlyTrackSelected(tr)
  r.SetMixerScroll(tr)

  -- Toggle FX window based on history mode
  if hist_item.mode == "focused" then
    -- For focused mode, toggle the specific FX floating window
    local fx_idx = hist_item.fx_index or 0
    local fx_count = r.TrackFX_GetCount(tr)

    if fx_idx >= fx_count then
      gui.last_result = string.format("Error: FX #%d not found (track has %d FX)", fx_idx + 1, fx_count)
      return
    end

    -- Toggle specific FX floating window
    -- Check if FX is open using TrackFX_GetOpen
    local is_open = r.TrackFX_GetOpen(tr, fx_idx)
    if is_open then
      r.TrackFX_Show(tr, fx_idx, 2)  -- Hide floating window
    else
      r.TrackFX_Show(tr, fx_idx, 3)  -- Show floating window
    end
    gui.last_result = string.format("Toggled FX: %s (FX #%d)", hist_item.name, fx_idx + 1)
  else
    -- For chain mode, toggle FX chain window (chain mode uses entire FX chain)
    local chain_visible = r.TrackFX_GetChainVisible(tr)
    if chain_visible == -1 then
      -- Chain window is closed, open it
      r.TrackFX_Show(tr, 0, 1)  -- Show chain window
    else
      -- Chain window is open, close it
      r.TrackFX_Show(tr, 0, 0)  -- Hide chain window
    end
    gui.last_result = string.format("Toggled FX chain: %s", hist_item.name)
  end
end

local function run_saved_chain(chain_idx)
  local chain = gui.saved_chains[chain_idx]
  if not chain then return end

  local tr = find_track_by_guid(chain.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", chain.track_name)
    return
  end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  if gui.is_running then return end

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  if gui.action == 1 then
    run_saved_chain_copy_mode(tr, chain.name, item_count)
  else
    run_saved_chain_apply_mode(tr, chain.name, item_count)
  end

  -- Add to history
  add_to_history(chain.name, chain.track_guid, chain.track_name, "chain", 0)

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", gui.action == 1 and "Copy" or "Apply", chain.name), -1)
end

local function run_history_focused_apply(tr, fx_name, fx_idx, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] History focused apply: '%s' (fx_idx=%d, items=%d)\n", fx_name, fx_idx, item_count))
  end

  -- Validate FX still exists at this index
  local fx_count = r.TrackFX_GetCount(tr)
  if fx_idx >= fx_count then
    gui.last_result = string.format("Error: FX #%d not found (track only has %d FX)", fx_idx + 1, fx_count)
    gui.is_running = false
    return
  end

  -- Set track as last touched (without changing selection)
  -- Note: We don't call SetOnlyTrackSelected() to preserve item selection
  -- Core will snapshot the current selection and restore it at the end
  r.SetMixerScroll(tr)

  -- Open specific FX as floating window if setting enabled
  -- Note: Focus detection is not required - Core will work regardless
  if gui.show_fx_on_recall then
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] Opening FX #%d floating window\n", fx_idx + 1))
    end
    r.TrackFX_Show(tr, fx_idx, 3)  -- Show floating window (flag 3)

    -- Small delay to ensure FX window is fully opened before Core checks it
    -- This prevents "Please focus a Track FX" warning
    r.defer(function() end)  -- Process one defer cycle
  else
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Skipping FX window (show_fx_on_recall = false)\n")
    end
  end

  -- Set ExtState for AudioSweet (focused mode)
  set_extstate_from_gui()
  r.SetExtState("hsuanice_AS", "AS_MODE", "focused", false)

  -- Set OVERRIDE ExtState to specify exact FX (bypasses GetFocusedFX check)
  -- This ensures Core processes the correct FX even if focus detection fails
  local track_idx = r.CSurf_TrackToID(tr, false) - 1  -- Convert to 0-based index
  r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(track_idx), false)
  r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", tostring(fx_idx), false)

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Executing AudioSweet Core (mode=focused, action=%s, handle=%.1fs)\n",
      gui.action == 0 and "apply" or "copy", gui.handle_seconds))
  end

  -- Run AudioSweet Core
  -- Note: Core handles selection save/restore internally
  local ok, err = pcall(dofile, CORE_PATH)
  r.UpdateArrange()

  if ok then
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Execution completed successfully\n")
    end
    gui.last_result = string.format("Success! [%s] Apply (%d items)", fx_name, item_count)
  else
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] ERROR: %s\n", tostring(err)))
    end
    gui.last_result = "Error: " .. tostring(err)
  end

  gui.is_running = false
end

local function run_history_item(hist_idx)
  local hist_item = gui.history[hist_idx]
  if not hist_item then return end

  local tr = find_track_by_guid(hist_item.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", hist_item.track_name)
    return
  end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  if gui.is_running then return end

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  -- Check if this was originally a focused FX or chain
  if hist_item.mode == "focused" then
    -- For focused mode, use stored FX index
    if gui.action == 1 then
      run_focused_fx_copy_mode(tr, hist_item.name, hist_item.fx_index or 0, item_count)
    else
      run_history_focused_apply(tr, hist_item.name, hist_item.fx_index or 0, item_count)
    end
  else
    -- Chain mode - use saved chain execution
    if gui.action == 1 then
      run_saved_chain_copy_mode(tr, hist_item.name, item_count)
    else
      run_saved_chain_apply_mode(tr, hist_item.name, item_count)
    end
  end

  -- Note: History doesn't re-add to history to avoid duplication

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", gui.action == 1 and "Copy" or "Apply", hist_item.name), -1)
end

------------------------------------------------------------
-- GUI Rendering
------------------------------------------------------------
local function draw_gui()
  -- Auto-reset is_previewing when transport stops
  if gui.is_previewing then
    local play_state = r.GetPlayState()
    if play_state == 0 then  -- 0 = stopped
      gui.is_previewing = false
      if gui.last_result == "Preview: Success" or gui.last_result == "Preview stopped" then
        gui.last_result = "Preview stopped (auto-detected)"
      end
    end
  end

  -- Keyboard shortcuts (only work when NOT typing in text inputs)
  local is_typing = ImGui.IsAnyItemActive(ctx)

  if not is_typing then
    -- ESC = Close window
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] Keyboard shortcut: ESC pressed (Close window)\n")
      end
      return false  -- Close the window
    end

    -- Space = Stop transport (simple, no modifiers needed)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] Keyboard shortcut: Space (Stop transport, command=40044)\n")
      end
      r.Main_OnCommand(40044, 0)  -- Transport: Stop
    end

    -- S = Solo toggle (depends on solo_scope setting)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_S, false) then
      if gui.debug then
        local scope_name = (gui.preview_solo_scope == 0) and "Track Solo" or "Item Solo"
        r.ShowConsoleMsg(string.format("[AS GUI] Keyboard shortcut: S pressed (scope=%s)\n", scope_name))
      end
      toggle_solo()
    end
  end

  -- Note: Preview shortcuts with modifiers (Ctrl+Space, etc.) should use Tools scripts
  -- Users should bind keyboard shortcuts to:
  --   - "hsuanice_AudioSweet Chain Preview Solo Exclusive" (for Chain mode)
  --   - "hsuanice_AudioSweet Preview Solo Exclusive" (for Focused mode)
  -- These scripts read settings from GUI ExtState automatically

  local window_flags = ImGui.WindowFlags_MenuBar |
                       ImGui.WindowFlags_AlwaysAutoResize |
                       ImGui.WindowFlags_NoResize

  -- Add NoDocking flag if docking is disabled
  if not gui.enable_docking then
    window_flags = window_flags | ImGui.WindowFlags_NoDocking
  end

  local visible, open = ImGui.Begin(ctx, 'AudioSweet Control Panel', true, window_flags)
  if not visible then
    ImGui.End(ctx)
    return open
  end

  -- Menu Bar
  if ImGui.BeginMenuBar(ctx) then
    if ImGui.BeginMenu(ctx, 'Presets') then
      if ImGui.MenuItem(ctx, 'Focused Apply', nil, false, true) then
        gui.mode = 0; gui.action = 0
        save_gui_settings()
      end
      if ImGui.MenuItem(ctx, 'Focused Copy', nil, false, true) then
        gui.mode = 0; gui.action = 1; gui.copy_scope = 0; gui.copy_pos = 0
        save_gui_settings()
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'Chain Apply', nil, false, true) then
        gui.mode = 1; gui.action = 0
        save_gui_settings()
      end
      if ImGui.MenuItem(ctx, 'Chain Copy', nil, false, true) then
        gui.mode = 1; gui.action = 1; gui.copy_scope = 0; gui.copy_pos = 0
        save_gui_settings()
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Debug') then
      local rv, new_val = ImGui.MenuItem(ctx, 'Enable Debug Mode', nil, gui.debug, true)
      if rv then
        gui.debug = new_val
        save_gui_settings()
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Settings') then
      -- UI Settings
      local rv_dock, new_dock = ImGui.MenuItem(ctx, 'Enable Window Docking', nil, gui.enable_docking, true)
      if rv_dock then
        gui.enable_docking = new_dock
        save_gui_settings()
      end
      ImGui.Separator(ctx)

      if ImGui.MenuItem(ctx, 'Preview Settings...', nil, false, true) then
        gui.show_preview_settings = true
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'History Settings...', nil, false, gui.enable_history) then
        gui.show_settings_popup = true
      end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx, 'File Naming Settings...', nil, false, true) then
        gui.show_naming_popup = true
      end
      ImGui.Separator(ctx)
      if ImGui.BeginMenu(ctx, 'FX Alias Tools') then
        if ImGui.MenuItem(ctx, 'Build FX Alias Database', nil, false, true) then
          local script_path = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Tools/hsuanice_FX Alias Build.lua"
          local success, err = pcall(dofile, script_path)
          if success then
            r.ShowConsoleMsg("[AS GUI] FX Alias Build completed\n")
          else
            r.ShowConsoleMsg("[AS GUI] Error running FX Alias Build: " .. tostring(err) .. "\n")
          end
        end
        if ImGui.MenuItem(ctx, 'Export JSON to TSV', nil, false, true) then
          local script_path = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Tools/hsuanice_FX Alias Export JSON to TSV.lua"
          local success, err = pcall(dofile, script_path)
          if success then
            r.ShowConsoleMsg("[AS GUI] FX Alias Export completed\n")
          else
            r.ShowConsoleMsg("[AS GUI] Error running FX Alias Export: " .. tostring(err) .. "\n")
          end
        end
        if ImGui.MenuItem(ctx, 'Update TSV to JSON', nil, false, true) then
          local script_path = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Tools/hsuanice_FX Alias Update TSV to JSON.lua"
          local success, err = pcall(dofile, script_path)
          if success then
            r.ShowConsoleMsg("[AS GUI] FX Alias Update completed\n")
          else
            r.ShowConsoleMsg("[AS GUI] Error running FX Alias Update: " .. tostring(err) .. "\n")
          end
        end
        ImGui.EndMenu(ctx)
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg(
          "=================================================\n" ..
          "AudioSweet ReaImGui - ImGui Interface for AudioSweet\n" ..
          "=================================================\n" ..
          "Version: 0.1.0-beta (251030.1600)\n" ..
          "Author: hsuanice\n\n" ..

          "Description:\n" ..
          "  Complete AudioSweet control center with:\n" ..
          "  - Focused/Chain modes with FX chain display\n" ..
          "  - Apply/Copy actions for flexible workflow\n" ..
          "  - AudioSweet Preview integration with configurable target track\n" ..
          "  - Saved Chains and History features with CLAP plugin support\n" ..
          "  - Comprehensive file naming settings with FX Alias support\n" ..
          "  - Debug mode with detailed console logging\n" ..
          "  - Built-in keyboard shortcuts (Space = Play/Stop, S = Solo toggle)\n" ..
          "  - Auto-resizing window that prevents accidental resize\n\n" ..

          "Reference:\n" ..
          "  Based on AudioSuite-like Script by Tim Chimes\n" ..
          "  Original: Renders selected plugin to selected media item\n" ..
          "  Written for REAPER 5.1 with Lua\n" ..
          "  v1.1 12/22/2015 - Added PreventUIRefresh\n" ..
          "  http://chimesaudio.com\n\n" ..

          "Development:\n" ..
          "  This script was developed with the assistance of AI tools\n" ..
          "  including ChatGPT and Claude AI.\n" ..
          "=================================================\n"
        )
      end
      ImGui.EndMenu(ctx)
    end

    ImGui.EndMenuBar(ctx)
  end

  -- Settings Popup
  if gui.show_settings_popup then
    ImGui.OpenPopup(ctx, 'History Settings')
    gui.show_settings_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'History Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Maximum History Items:")
    ImGui.SetNextItemWidth(ctx, 120)
    local rv, new_val = ImGui.InputInt(ctx, "##max_history", gui.max_history)
    if rv then
      gui.max_history = math.max(1, math.min(50, new_val))  -- Limit 1-50
      save_gui_settings()
      -- Trim history if needed
      while #gui.history > gui.max_history do
        table.remove(gui.history)
      end
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Range: 1-50 items")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- FX Name Formatting Popup
  -- File Naming Settings Popup
  if gui.show_naming_popup then
    ImGui.OpenPopup(ctx, 'File Naming Settings')
    gui.show_naming_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'File Naming Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    local changed = false
    local rv

    -- === Global FX Name Settings (applies to Focused & Chain modes) ===
    ImGui.Text(ctx, "Global FX Name Settings:")
    ImGui.TextDisabled(ctx, "(applies to both Focused and Chain modes)")
    ImGui.Separator(ctx)

    rv, gui.fxname_show_type = ImGui.Checkbox(ctx, "Show Plugin Type (CLAP:, VST3:, AU:, VST:)", gui.fxname_show_type)
    if rv then changed = true end

    rv, gui.fxname_show_vendor = ImGui.Checkbox(ctx, "Show Vendor Name (FabFilter)", gui.fxname_show_vendor)
    if rv then changed = true end

    rv, gui.fxname_strip_symbol = ImGui.Checkbox(ctx, "Strip Spaces & Symbols (ProQ4 vs Pro-Q 4)", gui.fxname_strip_symbol)
    if rv then changed = true end

    rv, gui.use_alias = ImGui.Checkbox(ctx, "Use FX Alias for file naming", gui.use_alias)
    if rv then changed = true end

    ImGui.Text(ctx, "Max FX Tokens:")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 80)
    rv, gui.max_fx_tokens = ImGui.InputInt(ctx, "##max_tokens", gui.max_fx_tokens)
    if rv then
      gui.max_fx_tokens = math.max(1, math.min(10, gui.max_fx_tokens))
      changed = true
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(FIFO limit, 1-10)")

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- === Chain Mode Specific Settings ===
    ImGui.Text(ctx, "Chain Mode Specific Settings:")
    ImGui.Separator(ctx)

    ImGui.Text(ctx, "Chain Token Source:")
    if ImGui.RadioButton(ctx, "Track Name", gui.chain_token_source == 0) then
      gui.chain_token_source = 0
      changed = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "FX Aliases", gui.chain_token_source == 1) then
      gui.chain_token_source = 1
      changed = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "FXChain", gui.chain_token_source == 2) then
      gui.chain_token_source = 2
      changed = true
    end

    -- Chain Alias Joiner (only when using aliases)
    if gui.chain_token_source == 1 then
      ImGui.Text(ctx, "Alias Joiner:")
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 100)
      rv, gui.chain_alias_joiner = ImGui.InputText(ctx, "##chain_joiner", gui.chain_alias_joiner)
      if rv then changed = true end
      ImGui.SameLine(ctx)
      ImGui.TextDisabled(ctx, "(separator between aliases)")
    end

    rv, gui.trackname_strip_symbols = ImGui.Checkbox(ctx, "Strip Symbols from Track Names", gui.trackname_strip_symbols)
    if rv then changed = true end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- === File Safety Section ===
    ImGui.Text(ctx, "File Name Safety:")
    ImGui.Separator(ctx)

    rv, gui.sanitize_token = ImGui.Checkbox(ctx, "Sanitize tokens for safe filenames", gui.sanitize_token)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(?)")
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Replace unsafe characters with underscores")
    end

    if changed then
      save_gui_settings()
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- Target Track Name Popup (simple input)
  if gui.show_target_track_popup then
    ImGui.OpenPopup(ctx, 'Edit Preview Target Track')
    gui.show_target_track_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'Edit Preview Target Track', true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Enter target track name for preview:")
    ImGui.SetNextItemWidth(ctx, 250)
    local rv, new_target = ImGui.InputText(ctx, "##target_track_input", gui.preview_target_track)
    if rv then
      gui.preview_target_track = new_target
      save_gui_settings()
    end

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'OK', 100, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Cancel', 100, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- Preview Settings Popup
  if gui.show_preview_settings then
    ImGui.OpenPopup(ctx, 'Preview Settings')
    gui.show_preview_settings = false
  end

  if ImGui.BeginPopupModal(ctx, 'Preview Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Target Track Name:")
    ImGui.SetNextItemWidth(ctx, 200)
    local rv, new_name = ImGui.InputText(ctx, "##preview_target", gui.preview_target_track)
    if rv then
      gui.preview_target_track = new_name
      save_gui_settings()
    end
    ImGui.TextWrapped(ctx, "The track where preview will be applied")

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Solo Scope:")
    local changed_scope = false
    if ImGui.RadioButton(ctx, "Track Solo (40281)", gui.preview_solo_scope == 0) then
      gui.preview_solo_scope = 0
      changed_scope = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Item Solo (41561)", gui.preview_solo_scope == 1) then
      gui.preview_solo_scope = 1
      changed_scope = true
    end
    if changed_scope then
      save_gui_settings()
    end

    -- Warning for Item Solo lag
    if gui.preview_solo_scope == 1 then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFAA00FF)  -- Orange color
      ImGui.TextWrapped(ctx, "Note: Item Solo may have a slight lag when toggling, not as responsive as Track Solo.")
      ImGui.PopStyleColor(ctx)
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Restore Mode:")
    local changed_restore = false
    if ImGui.RadioButton(ctx, "Time Selection", gui.preview_restore_mode == 0) then
      gui.preview_restore_mode = 0
      changed_restore = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "GUID", gui.preview_restore_mode == 1) then
      gui.preview_restore_mode = 1
      changed_restore = true
    end
    if changed_restore then
      save_gui_settings()
    end

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- Main content with compact layout
  local has_valid_fx = update_focused_fx_display()
  local item_count = r.CountSelectedMediaItems(0)

  -- === STATUS BAR ===
  if has_valid_fx then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
  end

  if gui.mode == 0 then
    ImGui.Text(ctx, gui.focused_fx_name)
  else
    ImGui.Text(ctx, gui.focused_track_name ~= "" and ("Track: " .. gui.focused_track_name) or "No track focused")
  end
  ImGui.PopStyleColor(ctx)

  ImGui.SameLine(ctx)
  ImGui.Text(ctx, string.format(" | Items: %d", item_count))

  -- Show FX chain in Chain mode
  if gui.mode == 1 and #gui.focused_track_fx_list > 0 then
    -- Dynamic height: each FX line is ~20px, max 150px (allows ~7 FX visible)
    local line_height = 20
    local max_height = 150
    local fx_count = #gui.focused_track_fx_list
    local calculated_height = math.min(fx_count * line_height, max_height)

    ImGui.BeginChild(ctx, "FXChainList", 0, calculated_height, ImGui.WindowFlags_None)
    for _, fx in ipairs(gui.focused_track_fx_list) do
      local status = fx.offline and "[offline]" or (fx.enabled and "[on]" or "[byp]")
      ImGui.Text(ctx, string.format("%02d) %s %s", fx.index + 1, fx.name, status))
    end
    ImGui.EndChild(ctx)

    if gui.enable_saved_chains then
      if has_valid_fx and ImGui.Button(ctx, "Save This Chain", -1, 0) then
        gui.show_save_popup = true
        gui.new_chain_name = gui.focused_track_name
      end
    end
  end

  ImGui.Separator(ctx)

  -- === MODE & ACTION (Radio buttons, horizontal) ===
  ImGui.Text(ctx, "Mode:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Focused", gui.mode == 0) then
    gui.mode = 0
    save_gui_settings()
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Chain", gui.mode == 1) then
    gui.mode = 1
    save_gui_settings()
  end

  ImGui.SameLine(ctx, 0, 30)
  ImGui.Text(ctx, "Action:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Apply", gui.action == 0) then
    gui.action = 0
    save_gui_settings()
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Copy", gui.action == 1) then
    gui.action = 1
    save_gui_settings()
  end

  -- === TARGET TRACK NAME (Chain mode only) ===
  if gui.mode == 1 then
    ImGui.Text(ctx, "Preview Target:")
    ImGui.SameLine(ctx)
    -- Display current target track name as a button
    -- Use ## ID to handle empty string case
    local display_name = (gui.preview_target_track ~= "") and gui.preview_target_track or "(not set)"
    if ImGui.Button(ctx, display_name .. "##target_track_btn", 150, 0) then
      gui.show_target_track_popup = true
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(click to edit)")
  end

  -- === COPY/APPLY SETTINGS (Compact horizontal) ===
  if gui.action == 1 then
    ImGui.Text(ctx, "Copy:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Active##scope", gui.copy_scope == 0) then
      gui.copy_scope = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "All Takes##scope", gui.copy_scope == 1) then
      gui.copy_scope = 1
      save_gui_settings()
    end
    ImGui.SameLine(ctx, 0, 20)
    if ImGui.RadioButton(ctx, "Tail##pos", gui.copy_pos == 0) then
      gui.copy_pos = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Head##pos", gui.copy_pos == 1) then
      gui.copy_pos = 1
      save_gui_settings()
    end
  else
    -- Handle seconds
    ImGui.Text(ctx, "Handle:")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 80)
    local rv, new_val = ImGui.InputDouble(ctx, "##handle_seconds", gui.handle_seconds, 0, 0, "%.1f")
    if rv then
      gui.handle_seconds = math.max(0, new_val)
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, "seconds")

    -- Channel Mode
    ImGui.Text(ctx, "Channel:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Auto##channel", gui.channel_mode == 0) then
      gui.channel_mode = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Mono##channel", gui.channel_mode == 1) then
      gui.channel_mode = 1
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Multi##channel", gui.channel_mode == 2) then
      gui.channel_mode = 2
      save_gui_settings()
    end
  end

  ImGui.Separator(ctx)

  -- === RUN BUTTONS: PREVIEW / SOLO / AUDIOSWEET ===
  local can_run = has_valid_fx and item_count > 0 and not gui.is_running

  -- Calculate button widths (3 buttons with spacing)
  local avail_width = ImGui.GetContentRegionAvail(ctx)
  local spacing = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local button_width = (avail_width - spacing * 2) / 3

  -- PREVIEW button (toggle: preview/stop)
  -- Check if transport is playing (includes previews started by Tools scripts)
  local play_state = r.GetPlayState()
  local is_playing = (play_state & 1 ~= 0)  -- bit 1 = playing
  local is_previewing_now = gui.is_previewing or is_playing

  -- Preview can run if:
  -- - Focused mode: has valid focused FX + has items + not running
  -- - Chain mode: has items + not running (no focused FX required, uses target track)
  -- - Already previewing/playing: always enabled to allow stopping
  local preview_can_run
  if is_previewing_now then
    preview_can_run = true  -- Always allow stopping
  elseif gui.mode == 0 then
    -- Focused mode: requires valid FX
    preview_can_run = has_valid_fx and item_count > 0 and not gui.is_running
  else
    -- Chain mode: only requires items (uses target track)
    preview_can_run = item_count > 0 and not gui.is_running
  end

  if not preview_can_run then ImGui.BeginDisabled(ctx) end

  -- Change button color if previewing
  if is_previewing_now then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xFF6600FF)  -- Orange when previewing
  end

  local button_label = is_previewing_now and "STOP" or "PREVIEW"
  if ImGui.Button(ctx, button_label, button_width, 35) then
    toggle_preview()
  end

  if is_previewing_now then
    ImGui.PopStyleColor(ctx)
  end
  if not preview_can_run then ImGui.EndDisabled(ctx) end

  ImGui.SameLine(ctx)

  -- SOLO button (always enabled)
  if ImGui.Button(ctx, "SOLO", button_width, 35) then
    toggle_solo()
  end

  ImGui.SameLine(ctx)

  -- AUDIOSWEET button
  if not can_run then ImGui.BeginDisabled(ctx) end
  if ImGui.Button(ctx, "AUDIOSWEET", button_width, 35) then
    run_audiosweet(nil)
  end
  if not can_run then ImGui.EndDisabled(ctx) end

  -- === KEYBOARD SHORTCUTS INFO ===
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x808080FF)  -- Gray color
  ImGui.Text(ctx, "Shortcuts: ESC = Close, Space = Stop, S = Solo")
  ImGui.Text(ctx, "Tip: Bind 'AudioSweet Chain/Focused Preview' actions to shortcuts")
  ImGui.Text(ctx, "     in REAPER Action List for Ctrl+Space preview")
  ImGui.PopStyleColor(ctx)

  -- === STATUS (below RUN button) ===
  if gui.last_result ~= "" then
    if gui.last_result:match("^Success") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
    elseif gui.last_result:match("^Error") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFF00FF)
    end
    ImGui.Text(ctx, gui.last_result)
    ImGui.PopStyleColor(ctx)
  end

  ImGui.Separator(ctx)

  -- === QUICK PROCESS (Saved + History, side by side) ===
  if gui.enable_saved_chains or gui.enable_history then
    -- Show FX on recall checkbox
    local changed
    changed, gui.show_fx_on_recall = ImGui.Checkbox(ctx, "Show FX window on recall", gui.show_fx_on_recall)
    if changed then save_gui_settings() end

    -- Only show if at least one feature is enabled and has content
    if (gui.enable_saved_chains and #gui.saved_chains > 0) or (gui.enable_history and #gui.history > 0) then
      local avail_w = ImGui.GetContentRegionAvail(ctx)
      local col1_w = avail_w * 0.5 - 5

      -- Left: Saved Chains
      if gui.enable_saved_chains and #gui.saved_chains > 0 then
        ImGui.BeginChild(ctx, "SavedCol", col1_w, 200, ImGui.WindowFlags_None)
        ImGui.Text(ctx, "SAVED CHAINS")
        ImGui.Separator(ctx)
        local to_delete = nil
        for i, chain in ipairs(gui.saved_chains) do
          ImGui.PushID(ctx, i)
          -- "Open" button (small, on the left)
          if ImGui.SmallButton(ctx, "Open") then
            open_saved_chain_fx(i)
          end
          ImGui.SameLine(ctx)
          -- Chain name button (executes AudioSweet) - use available width minus Delete button
          local avail_width = ImGui.GetContentRegionAvail(ctx) - 25  -- Space for "X" button
          if ImGui.Button(ctx, chain.name, avail_width, 0) then
            run_saved_chain(i)
          end
          ImGui.SameLine(ctx)
          -- Delete button
          if ImGui.Button(ctx, "X", 20, 0) then
            to_delete = i
          end
          ImGui.PopID(ctx)
        end
        if to_delete then delete_saved_chain(to_delete) end
        ImGui.EndChild(ctx)

        ImGui.SameLine(ctx)
      end

      -- Right: History
      if gui.enable_history and #gui.history > 0 then
        ImGui.BeginChild(ctx, "HistoryCol", 0, 0, ImGui.WindowFlags_None)
        ImGui.Text(ctx, "HISTORY")
        ImGui.SameLine(ctx)
        ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + ImGui.GetContentRegionAvail(ctx) - 45)
        if ImGui.SmallButton(ctx, "Clear") then
          gui.history = {}
          -- Clear from ProjExtState
          for i = 0, gui.max_history - 1 do
            r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
          end
        end
        ImGui.Separator(ctx)
        for i, item in ipairs(gui.history) do
          ImGui.PushID(ctx, 1000 + i)
          -- "Open" button (small, on the left)
          if ImGui.SmallButton(ctx, "Open") then
            open_history_fx(i)
          end
          ImGui.SameLine(ctx)
          -- History item name button (executes AudioSweet)
          if ImGui.Button(ctx, item.name, -1, 0) then
            run_history_item(i)
          end
          ImGui.PopID(ctx)
        end
        ImGui.EndChild(ctx)
      end
    end
  else
    -- Show "Developing" message when both features are disabled
    ImGui.TextWrapped(ctx, "SAVED CHAINS and HISTORY features are currently under development.")
    ImGui.TextWrapped(ctx, "These features are not functioning properly and will be available in a future update.")
  end

  ImGui.End(ctx)

  -- === SAVE CHAIN POPUP ===
  if gui.show_save_popup then
    ImGui.OpenPopup(ctx, "Save Chain")
    gui.show_save_popup = false
  end

  if ImGui.BeginPopupModal(ctx, "Save Chain", true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Enter a name for this FX chain:")
    local rv, new_name = ImGui.InputText(ctx, "##chainname", gui.new_chain_name, 256)
    if rv then gui.new_chain_name = new_name end

    if ImGui.Button(ctx, "Save", 100, 0) then
      if gui.new_chain_name ~= "" and gui.focused_track then
        local track_guid = get_track_guid(gui.focused_track)
        add_saved_chain(gui.new_chain_name, track_guid, gui.focused_track_name)
        gui.new_chain_name = ""
        ImGui.CloseCurrentPopup(ctx)
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 100, 0) then
      gui.new_chain_name = ""
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  return open
end

------------------------------------------------------------
-- Main Loop
------------------------------------------------------------
local function loop()
  gui.open = draw_gui()
  if gui.open then
    r.defer(loop)
  else
    -- Script is closing - output final settings if debug mode is on
    if gui.debug then
      r.ShowConsoleMsg("========================================\n")
      r.ShowConsoleMsg("[AS GUI] Script closing - Final settings:\n")
      r.ShowConsoleMsg("========================================\n")
      r.ShowConsoleMsg(string.format("  Mode: %s\n", gui.mode == 0 and "Focused" or "Chain"))
      r.ShowConsoleMsg(string.format("  Action: %s\n", gui.action == 0 and "Apply" or "Copy"))
      r.ShowConsoleMsg(string.format("  Copy Scope: %s\n", gui.copy_scope == 0 and "Active" or "All"))
      r.ShowConsoleMsg(string.format("  Copy Position: %s\n", gui.copy_pos == 0 and "Last" or "Replace"))
      local channel_mode_names = {"Auto", "Mono", "Multi"}
      r.ShowConsoleMsg(string.format("  Channel Mode: %s\n", channel_mode_names[gui.channel_mode + 1]))
      r.ShowConsoleMsg(string.format("  Handle Seconds: %.2f\n", gui.handle_seconds))
      r.ShowConsoleMsg(string.format("  Debug Mode: %s\n", gui.debug and "ON" or "OFF"))
      r.ShowConsoleMsg(string.format("  Max History: %d\n", gui.max_history))
      r.ShowConsoleMsg(string.format("  FX Name - Show Type: %s\n", gui.fxname_show_type and "ON" or "OFF"))
      r.ShowConsoleMsg(string.format("  FX Name - Show Vendor: %s\n", gui.fxname_show_vendor and "ON" or "OFF"))
      r.ShowConsoleMsg(string.format("  FX Name - Strip Symbol: %s\n", gui.fxname_strip_symbol and "ON" or "OFF"))
      r.ShowConsoleMsg(string.format("  FX Name - Use Alias: %s\n", gui.use_alias and "ON" or "OFF"))
      r.ShowConsoleMsg(string.format("  Max FX Tokens: %d\n", gui.max_fx_tokens))
      local chain_token_source_names = {"Track Name", "FX Aliases", "FXChain"}
      r.ShowConsoleMsg(string.format("  Chain Token Source: %s\n", chain_token_source_names[gui.chain_token_source + 1]))
      if gui.chain_token_source == 1 then
        r.ShowConsoleMsg(string.format("  Chain Alias Joiner: '%s'\n", gui.chain_alias_joiner))
      end
      r.ShowConsoleMsg(string.format("  Track Name Strip Symbols: %s\n", gui.trackname_strip_symbols and "ON" or "OFF"))
      r.ShowConsoleMsg(string.format("  Preview Target Track: %s\n", gui.preview_target_track))
      local solo_scope_names = {"Track Solo", "Item Solo"}
      r.ShowConsoleMsg(string.format("  Preview Solo Scope: %s\n", solo_scope_names[gui.preview_solo_scope + 1]))
      local restore_mode_names = {"Keep", "Restore"}
      r.ShowConsoleMsg(string.format("  Preview Restore Mode: %s\n", restore_mode_names[gui.preview_restore_mode + 1]))
      r.ShowConsoleMsg("========================================\n")
    end
  end
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
load_gui_settings()  -- Load saved GUI settings first
load_saved_chains()
load_history()
r.defer(loop)
