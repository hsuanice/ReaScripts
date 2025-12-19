--[[
@description AudioSweet ReaImGui - ImGui Interface for AudioSweet
@author hsuanice
@version 0.1.6
@provides
  [main] .
@about
  # AudioSweet ReaImGui - User Manual

  ## Overview
  Complete AudioSweet control center with ImGui interface for managing FX chains and presets.

  ## Core Features
  - Two operation modes: Focused FX and Full Chain
  - Apply/Copy FX chains to AudioSweet Preview track
  - Save and manage FX presets with custom naming
  - Automatic operation history tracking
  - Real-time FX chain visualization
  - Built-in keyboard shortcuts
  - Persistent settings across sessions

  ---

  ## Operation Modes

  ### Focused Mode (Single FX)
  - Works with the currently focused FX window
  - Click on any FX window to focus it
  - Saves/applies only the selected FX
  - Display shows: FX name only (e.g., "VST3: Pro-Q 4")
  - Supports CLAP and VST3 plugins

  ### Chain Mode (Full FX Chain)
  - Works with the entire FX chain of selected track
  - Saves/applies all FX on the track
  - Display shows: "#N Track Name" format
  - Shows complete FX list in tooltips

  ---

  ## Main Actions

  ### Apply
  - Copies FX to Preview track AND enables it
  - Removes all existing FX on Preview track first
  - Use when you want to audition the FX immediately

  ### Copy
  - Copies FX to Preview track but keeps it bypassed
  - Removes all existing FX on Preview track first
  - Use when you want to prepare FX without hearing it yet

  ### Open
  - Opens the saved FX window(s)
  - Focused mode: Opens the specific FX window
  - Chain mode: Opens all FX windows in the chain

  ---

  ## Preset System

  ### Saving Presets
  1. Click the "Save" button (in main controls or history section)
  2. Enter a custom name, or leave empty to use default:
     - Focused mode default: FX name
     - Chain mode default: Track name
  3. Preset is saved and appears in the "Saved" section

  ### Managing Presets
  - **Open**: Opens the FX window(s) without applying
  - **Name**: Rename the preset (custom name or revert to default)
  - **Save**: Save current FX as a new preset
  - **Delete** (X button): Remove the preset permanently

  ### Preset Display Names
  - Custom name: Shows your custom name
  - Default name (Focused): Shows current FX name from track
  - Default name (Chain): Shows "#N Current Track Name"
  - Hover tooltip: Shows full FX chain with track info

  ---

  ## History System

  ### Automatic Tracking
  - Every Apply/Copy operation is automatically logged
  - History stores up to 50 recent operations
  - Newest operations appear at the top
  - Duplicates are automatically removed

  ### History Actions
  - **Open**: Opens the FX window(s) from this history entry
  - **Name**: Rename this history entry (becomes a custom name)
  - **Save**: Convert this history entry into a saved preset

  ### History Display Names
  - Inherits custom name from preset (if executed from a saved preset)
  - Shows default name if executed directly
  - Updates automatically when you rename the matching preset

  ---

  ## Keyboard Shortcuts
  - **Space**: Play/Stop transport
  - **S**: Toggle solo on Preview track
  - **Esc**: Close dialogs

  ---

  ## Settings Panel

  ### Target Track
  - Select which track to use as AudioSweet Preview target
  - Default: First track matching "AudioSweet Preview" in name
  - Can manually override with any track

  ### Auto-Actions
  - **Auto Open FX**: Automatically opens FX window after Apply/Copy
  - **Auto Solo**: Automatically solos Preview track after Apply/Copy

  ### File Naming
  Configure how bounced audio files are named:
  - **Include Elements**: Track#, Track Name, FX Name, Timestamp, Item Name
  - **Show Type**: Display plugin type prefix (VST3:, CLAP:, JS:)
  - **Separators**: Customize separators between name elements
  - **FX Alias**: Replace long FX names with short aliases

  ### Chain Visibility
  - **Show Chain in Focused Mode**: Display full FX chain even in Focused mode
  - Useful for context when working with multiple FX

  ### Debug Mode
  - Enable console logging for troubleshooting
  - Shows: Save/Rename/Open/Run operations with indices and modes

  ---

  ## Tips & Tricks

  ### Workflow Example 1: Quick FX Auditioning
  1. Select track with FX chain
  2. Switch to Chain mode
  3. Click "Apply" to audition the full chain
  4. Click "Save" if you like it

  ### Workflow Example 2: Building FX Library
  1. Focus on individual FX window
  2. Switch to Focused mode
  3. Click "Save" and name it (e.g., "Vocal EQ Bright")
  4. Repeat for different FX
  5. Access your library from "Saved" section anytime

  ### Workflow Example 3: Using History
  1. Experiment with different FX chains using Apply
  2. All attempts are logged in History
  3. Go back to History and click "Open" on any entry to review
  4. Click "Save" on the one you like to make it permanent

  ### Name Management
  - Leave name empty when saving = dynamic name (updates with track/FX renames)
  - Enter custom name = static name (never changes)
  - You can always rename later using the "Name" button
  - Renaming a preset automatically updates all matching history entries

  ### FX Chain Tooltips
  - Hover over any preset/history item to see full FX chain
  - Focused mode: Saved FX is highlighted in GREEN
  - Shows track number and current track name

  ---

  ## Troubleshooting

  ### "No focused FX" in Focused Mode
  - Click on any FX window to focus it
  - Make sure the FX window is open (not just in FX chain list)

  ### Preset Opens Wrong FX
  - This can happen if you reordered FX after saving
  - The script tries to match by name as fallback
  - Enable Debug mode to see index matching details

  ### History Not Showing Custom Names
  - Make sure you're using version 251215.0025 or later
  - Old history entries won't have custom names (only new ones)

  ### Window Too Wide/Narrow
  - Edit line 2482: ImGui.SetNextWindowSizeConstraints(ctx, 450, ...)
  - Change the first number (450) to your preferred width

  ---

  ## Technical Notes
  - All presets saved in REAPER project ExtState (persistent per project)
  - History limited to 50 entries (configurable in gui.max_history)
  - Supports CLAP, VST3, VST2, AU, and JS plugins
  - FX matching uses both index and name for reliability
  - Track identification uses GUID (survives track reordering)


@changelog
  0.1.6 [Internal Build 251219.1800] - Apply layout compact
    - Changed: Moved Handle control to the Channel row for a two-line top layout

  0.1.5 [Internal Build 251219.1754] - Preset/History show toggle
    - Added: Toggle to show/hide Presets/History block with persistent setting

  0.1.4 [Internal Build 251219.1745] - Removed Presets menu tab
    - Removed: Presets menu from the top menu bar (use main controls instead)

  0.1.3 [Internal Build 251219.1730] - Dynamic list height refinement
    - Improved: Saved presets and History lists now auto-fit content height with no extra blank row

  0.1.2 [Internal Build 251218.2240] - Disabled collapse arrow
    - Added: Main GUI window now has collapse controls disabled (WindowFlags_NoCollapse) to prevent accidental collapse errors reported by users

  0.1.1 [Internal Build 251218.2150] - BWF MetaEdit reminder + install guide
    - Added: CLI detection at startup with warning banner so users know TC embedding requires bwfmetaedit
    - Added: Settings > Timecode Embed modal showing status, custom path input, and re-check/install buttons
    - Added: Homebrew install guide popup with copy-friendly commands for quick setup

  0.1.0 [Internal Build 251215.1330] - ESC KEY FIX & WINDOW POSITION IMPROVEMENTS
    - FIXED: ESC key now correctly closes main window and popups.
      • Problem 1: ESC in Settings popups closed main window instead of popup
      • Problem 2: ESC couldn't close main window when controls were active
      • Root cause: ESC handler was in wrong location and missing IsWindowFocused() check
      • Solution: Moved main window ESC handler to immediately after ImGui.Begin() (line 2774)
      • Solution: Use IsWindowFocused() for all ESC handlers (main: 2774, popups: 2914, 2953, 3118)
      • Impact: ESC closes focused window correctly, matching RGWH GUI behavior
      • Reference: RGWH GUI ESC handler at line 1726 (immediately after Begin)
    - FIXED: Main window position now remembered across sessions.
      • Problem: Window always opened at default position, ignoring previous placement
      • Root cause: SetNextWindowPos() overrode ImGui's automatic position memory
      • Solution: Removed SetNextWindowPos() for main window, let ImGui handle position persistence
      • Impact: Main window reopens where user last placed it
    - ATTEMPTED: Settings popups open near mouse cursor (partial implementation).
      • Implementation: Use GetMousePosition() + SetNextWindowPos() with Cond_Appearing
      • Note: Popup modals may have limitations with position override in ReaImGui
      • Affected popups: History Settings (2906-2907), File Naming (2945-2946), Preview (3110-3111)
    - PURPOSE: Better UX - consistent window management matching RGWH GUI behavior

  [Internal Build 251215.1250] - KEYBOARD SHORTCUTS HELP TEXT IMPROVEMENT
    - IMPROVED: Keyboard shortcuts help text now shows mode-specific instructions.
      • Previous: Both Chain and Focused mode hints shown simultaneously (text too long)
      • Now: Dynamic help text that changes based on current mode
      • Chain Mode shows: "Script: hsuanice_AudioSweet Chain Preview..." (Ctrl+Space)
      • Focused Mode shows: "Script: hsuanice_AudioSweet Preview..." (Ctrl+Shift+Space)
      • Lines: 3305-3311 (mode-specific keyboard shortcuts help)
    - PURPOSE: Cleaner UI with relevant hint for current mode only

  [Internal Build 251215.1225] - UI TEXT IMPROVEMENT
    - IMPROVED: Copy settings label clarity.
      • Changed "Copy:" to "Copy to:" for better readability
      • More accurately describes the action (copying FX TO items)
      • Line: 3169 (Copy settings label)
    - PURPOSE: Clearer UI labeling for better user understanding

  [Internal Build 251215.0050] - VERSION NUMBER CLEANUP
    - CHANGED: Simplified version number format.
      • @version: 0.1.0 (for ReaPack compatibility)
      • Help > About: Version 0.1.0 (251215)
      • Removed "-beta" suffix for cleaner version display
      • Internal build number preserved in Help > About for tracking
      • Line: 4 (@version), 2825 (About dialog version)
    - PURPOSE: Cleaner version display while maintaining build tracking

  [Internal Build 251215.0045] - COMPREHENSIVE USER MANUAL
    - ADDED: Complete user manual in @about section.
      • Comprehensive guide covering all features and workflows
      • Sections: Overview, Operation Modes, Main Actions, Preset System, History System
      • Keyboard shortcuts, Settings panel, Tips & Tricks, Troubleshooting
      • Three workflow examples for common use cases
      • Technical notes for advanced users
      • Lines: 8-198 (user manual in @about section)
    - PURPOSE: Improve user onboarding and feature discoverability
    - IMPACT: Users can now understand all features without external documentation

  [Internal Build 251215.0030] - PRESET RENAME SYNC TO HISTORY
    - FIXED: Renaming a preset now immediately syncs to matching history items.
      • Problem: When renaming a saved preset, history items didn't update to show the new custom name
      • Root cause: rename_saved_chain() only updated saved_chains array, not history array
      • Solution: Modified rename_saved_chain() to iterate through history and update matching items
      • Matching criteria: track_guid + mode + (fx_index for focused, name for chain)
      • Impact: History list now reflects renamed preset names in real-time
      • Lines: 1203-1240 (rename_saved_chain with history sync)

  [Internal Build 251215.0025] - HISTORY CUSTOM NAMES & UI WIDTH IMPROVEMENTS
    - FIXED: History items now display renamed custom names.
      • Problem: History list only showed default names, ignoring renamed custom names
      • Root cause: History data structure didn't store custom_name field
      • Solution: Added custom_name field to history storage and display logic
      • Impact: Renamed presets now show their custom names in history list
      • Lines: 1403-1427 (load_history with custom_name), 1429-1462 (add_to_history with custom_name)
      • Lines: 1330-1366 (get_history_display_name with custom_name support)
    - IMPROVED: Increased minimum window width to improve button text readability.
      • Problem: Six buttons per row (Open/Name/Save for preset+history) caused text truncation
      • Solution: Set minimum window width to 700px using SetNextWindowSizeConstraints
      • Impact: Button text now more readable, less truncation
      • Line: 2482 (window size constraints)
    - IMPROVED: History now preserves custom_name when adding from saved presets.
      • When executing a renamed saved preset, the custom name is now preserved in history
      • Line: 2368 (pass custom_name to add_to_history)

  [Internal Build 251215.0020] - FUNCTION ORDERING FIX
    - FIXED: Saved focused FX presets now execute without errors.
      • Problem: Clicking saved focused FX preset crashed with "attempt to call a nil value (global 'run_history_focused_apply')"
      • Root cause: run_saved_chain() called run_history_focused_apply() which was defined AFTER it (forward reference error in Lua)
      • Solution: Moved run_history_focused_apply() definition before run_saved_chain()
      • Impact: All saved focused FX presets now work correctly
      • Lines: 2214-2282 (run_history_focused_apply), 2284-2335 (run_saved_chain)
    - EXPLANATION: Why history worked but saved presets didn't.
      • History calls run_history_item() → run_history_focused_apply() (both in correct order)
      • Saved presets call run_saved_chain() → run_history_focused_apply() (was in wrong order)
      • Fixed by reordering function definitions to eliminate forward reference

  [Internal Build 251215.0005] - CODE REFACTORING & UI CONSISTENCY
    - REFACTORED: Unified tooltip display for saved presets and history.
      • Created shared show_preset_tooltip() function
      • Eliminated duplicate code (~50 lines reduced to 3 lines per usage)
      • Both saved presets and history now use identical tooltip logic
      • Easier to maintain and update tooltip behavior
      • Lines: 1329-1377 (shared tooltip function), 3050, 3121 (usage)
    - PURPOSE: Code consolidation and consistency between saved presets and history features

  [Internal Build 251214.2355] - SAVED/HISTORY EXECUTION FIX & TOOLTIP ENHANCEMENTS
    - FIXED: Saved focused FX presets now execute correctly in focused mode.
      • Problem: Saved focused FX would execute as chain mode (entire FX chain)
      • Root cause: run_saved_chain() always used chain execution regardless of saved mode
      • Solution: Check chain.mode and route to appropriate execution function
      • Impact: Focused FX presets now correctly process only the specific FX
      • Lines: 2160-2181 (mode-based execution routing in run_saved_chain)
    - ENHANCED: History items now show hover tooltips with track and FX info.
      • Previously: History had no tooltips
      • Now: Shows track #, name, and complete FX chain with saved FX highlighted in GREEN
      • Focused mode: Highlights the specific FX in green within the chain
      • Chain mode: Shows entire FX chain list
      • Lines: 3092-3143 (history hover tooltip with FX chain display)
    - NEW: History items now have "Save" button to save as preset.
      • UI layout: [Open] [Name Button] [Save] (matching saved presets layout)
      • Click "Save" to add history item to Saved FX Preset list
      • Duplicate check: Shows info message if preset already exists
      • Preserves original mode (focused/chain) and fx_index
      • Lines: 3145-3175 (Save button with duplicate check)
    - IMPROVED: History now records correct mode and fx_index from saved chains.
      • Previously: Always added to history as "chain" mode with fx_index=0
      • Now: Preserves original mode (focused/chain) and fx_index from saved preset
      • Line: 2178 (correct mode and fx_index in add_to_history)

  [Internal Build 251214.2340] - CHAIN DUPLICATE PREVENTION & UI IMPROVEMENTS
    - NEW: Chain mode duplicate prevention.
      • Previously: Only focused FX had duplicate prevention
      • Now: Chain mode blocks saving identical FX chains with different names
      • Check method: Compare full FX chain content (all FX names in order)
      • Impact: Prevents accidental duplicate chain saves
      • Lines: 3149-3186 (chain duplicate check by FX content comparison)
    - ENHANCED: Debug messages for chain open toggle operations.
      • Previously: Only focused FX open had debug output
      • Now: Chain mode open also shows debug info (name, mode, chain_visible status)
      • Both saved chains and history chains show debug output
      • Lines: 2037-2040 (saved chain debug), 2091-2094 (history chain debug)
    - IMPROVED: Rename dialog now shows current default name in hint text.
      • Chain mode: Shows "(default: #N - track_name)" with actual track# and name
      • Focused mode: Shows "(default: FX_name)" with full FX name (VST3:/CLAP: prefix)
      • Previously: Generic "(leave empty to use track name)" text
      • Helps users understand what the default name will be before confirming
      • Lines: 3253-3277 (dynamic hint text based on mode and current track info)
    - FIXED: Removed non-existent process_fx_name() function call.
      • Problem: Rename dialog crashed when renaming focused FX presets
      • Error: "attempt to call a nil value (global 'process_fx_name')"
      • Solution: Use chain.name directly (already contains full FX name)
      • Line: 3271

  [Internal Build 251214.2200] - FX INDEX TRACKING & ENHANCED TOOLTIPS
    - NEW: Store FX index for focused presets to prevent wrong FX loading.
      • Problem: When saving same FX with different names, both presets would load the same FX
      • Solution: Save and track fx_index alongside FX name
      • Impact: Open button now always opens the correct FX window
      • Lines: 1052-1065 (add_saved_chain), 1007-1036 (load/save extstate)
    - NEW: Duplicate prevention for focused FX presets.
      • Now blocks saving the same FX twice, even with different names
      • Check by track_guid + fx_index for focused mode
      • Check by track_guid + name for chain mode
      • Line: 3040-3054 (duplicate check logic)
    - ENHANCED: Focused FX preset tooltips now show full FX chain.
      • Previously: Only showed the saved FX name
      • Now: Shows entire FX chain with saved FX highlighted in GREEN
      • Helps identify which preset is which when saving multiple instances of same FX
      • Lines: 1124-1168 (build full chain for focused mode), 2869-2897 (colored tooltip)
    - Improved: Better FX matching with fallback logic.
      • Method 1: Use saved fx_index (fast, accurate)
      • Method 2: Exact name match (fallback if index invalid)
      • Removed fuzzy matching to prevent wrong FX selection
      • Lines: 1129-1154 (FX matching logic)
    - Added: Debug messages for save/rename/open/run operations.
      • Console output when debug mode is ON
      • Shows fx_index, mode, and operation details
      • Open operation now shows: saved_index vs actual_index (detects order changes)
      • Removed noisy per-frame debug messages
      • Lines: 1094-1097, 1077-1080, 2010-2013, 2027-2030
    - FIXED: Store original FX name (with VST3:/CLAP: prefix) instead of processed name.
      • Problem: FX Name settings (Show Type: OFF) would strip prefixes before saving
      • Result: Name matching failed after FX order changes
      • Solution: Read raw FX name directly from track when saving
      • Line: 3109-3113, 3136 (get original_fx_name and use for storage)
    - IMPROVED: Open button now adapts to FX order changes.
      • Method 1: Try saved fx_index with name verification
      • Method 2: Search by name if index position changed
      • Debug output shows both saved and actual positions
      • Lines: 1982-2021 (smart FX matching in open_saved_chain_fx)

  [Internal Build 251214.2030] - PRESET SAVE AND DISPLAY FIXES
    - Fixed: Save dialog input field now pre-filled with default value.
      • Chain mode: Pre-filled with track name (e.g., "test" not "#1 - test")
      • Focused mode: Pre-filled with FX name
      • Previous: Input field was empty, confusing what the default would be
      • New: Shows the actual default value user can edit or clear
      • Line: 2671-2673 (extract track name using get_track_name_and_number)
    - Improved: Save dialog now shows hint text "(leave empty to use default)".
      • Consistent with Rename dialog behavior
      • Clarifies that empty input will use default naming
      • Line: 2864 (hint text)
    - Fixed: Save dialog now properly handles empty input (uses default name).
      • Chain mode empty → uses track name as preset name
      • Focused mode empty → uses FX name as preset name
      • Lines: 2875-2884 (default name handling)
    - Fixed: Focused FX presets no longer show "#N" prefix when using default name.
      • Previous: Focused FX with empty/default name showed "#1 track_name"
      • New: Only chain mode shows "#N" prefix, focused mode shows clean name
      • Lines: 1092-1097 (mode-based track# prefix logic)
    - Fixed: ImGui.BeginChild() assertion errors by checking return value.
      • Previous: BeginChild could fail but EndChild still executed → assertion error
      • New: Only call EndChild if BeginChild returns true (successful)
      • Prevents "child_window->Flags & ImGuiWindowFlags_ChildWindow" assertion failures
      • Lines: 2712, 2769, 2844 (BeginChild return value checks)
    - Fixed: Focused FX preset hover tooltip now shows FX name instead of chain info.
      • Previous: Hovering over focused FX preset showed entire track FX chain
      • New: Shows only the saved FX name (e.g., "VST3: Pro-Q 4 (FabFilter)")
      • Lines: 1075-1077 (focused mode FX info)
    - Fixed: Focused FX preset rename now uses FX name as default, not track name.
      • Previous: Empty rename input defaulted to track name (chain behavior)
      • New: Focused FX uses saved FX name, Chain uses track name
      • Lines: 1100-1106 (focused mode display name logic)
    - Fixed: Rename dialog now pre-fills with current preset name.
      • Previous: Rename input field was empty, requiring full re-type
      • New: Pre-filled with current name (custom name or default name)
      • Allows quick edits like adding numbers or removing words
      • Lines: 2797-2809 (rename dialog pre-fill logic)
    - Fixed: Save dialog now correctly saves user input as custom name.
      • Previous: Chain mode always ignored user input, saved as dynamic track name
      • Previous: Focused mode saved input field value even if unmodified (wrong default)
      • New: Compares user input with initial default value
      • If unchanged or empty → saves as nil (uses dynamic name)
      • If modified → saves as custom name
      • Lines: 2718-2726 (store default), 2926-2969 (custom name logic)
    - Fixed: Hover tooltip now shows real-time track info for both chain and focused FX.
      • First line: #track_number: track_name (updates dynamically)
      • Chain mode: Shows numbered FX list (1. Plugin Name, 2. Plugin Name...)
      • Focused FX mode: Shows only the current full FX name from track (not saved name)
      • Lines: 1079-1157 (get_chain_display_info updates)
    - Purpose: Better UX - users can see and modify the default value directly.

  [Internal Build 251214.1530] - UI POLISH AND SAVE IMPROVEMENTS
    - Fixed: Status message moved above FX info area to prevent Saved/History buttons from jumping.
      • Previous: Yellow status text appeared between Save button and Saved/History section
      • New: Status appears above FX info at bottom of window
      • Result: Saved/History buttons stay in fixed position regardless of status messages
      • Line: 2761-2772 (status above FX info)
    - Improved: Save/Rename dialogs now show track# prefix outside input field for chains.
      • Chain presets: "Track #3 - Preset Name: [input field]"
      • Focused presets: "Preset Name: [input field]"
      • Track number is fixed, only preset name can be edited
      • Lines: 2820-2826 (Save dialog), 2879-2896 (Rename dialog)
    - Added: Duplicate preset name detection when saving.
      • Checks for existing preset with same name and track GUID
      • Shows error message if duplicate found
      • Prevents accidental overwrites
      • Lines: 2836-2843 (duplicate check)
    - Purpose: Cleaner UI with better feedback and duplicate prevention.

  [Internal Build 251214.1500] - MAJOR UI RESTRUCTURE FOR BETTER WORKFLOW
    - Restructured: Complete UI layout reorganization for stability and better UX.
      • FX info area moved to bottom (after Saved/History) with dynamic height
      • Save button merged and positioned above Saved/History section
      • Stable layout: Main controls stay in fixed positions
      • Lines: 2611-2628 (unified Save button), 2735-2769 (FX info at bottom)
    - Improved: Unified "Save" button that changes label based on mode.
      • Chain mode: "Save This Chain" | Focused mode: "Save This FX"
      • Single button eliminates layout jumping when switching modes
      • Always visible above Saved/History for quick access
      • Lines: 2611-2628 (unified Save button logic)
    - Improved: Simplified save dialog with single input field.
      • Previous: Two separate popups with multiple fields
      • New: One unified popup with preset name input
      • Pre-filled with FX name or track name based on mode
      • Support Enter to save, Escape to cancel
      • Lines: 2773-2810 (unified Save FX Preset popup)
    - Improved: Saved FX Preset and History display real-time track info.
      • Chain presets show "#track_number track_name" format
      • Track number/name updates automatically when track changes
      • Focused FX presets show FX name only (no track# prefix)
      • Lines: 979-1032 (get_chain_display_info with track#), 1034-1052 (get_history_display_name)
    - Improved: History column now auto-resizes based on content.
      • Dynamic height calculation: items * 25px + header (max 200px)
      • Reduces wasted space when few history items
      • Scrollbar appears when needed
      • Lines: 2696-2727 (History with auto-resize)
    - Changed: Section title "SAVED CHAINS" → "SAVED FX PRESET".
      • More accurate description of functionality
      • Line: 2645
    - Fixed: Popup dialogs now appear near main GUI window.
      • Positioned at center-top of main window
      • No more popups appearing off-screen
      • Lines: 2775-2778 (Save popup position), 2814-2817 (Rename popup position)
    - Purpose: Stable UI with controls in predictable positions - FX info changes don't affect button locations.

  [Internal Build 251214.1420] - UI/UX IMPROVEMENTS
    - Fixed: FX chain preview area now uses fixed height to prevent button layout jumping.
      • Previous: Dynamic height based on FX count caused buttons below to move up/down
      • New: Fixed 150px height with scrollbar when needed (allows ~7 FX visible)
      • Result: Stable button positions - easier to quickly toggle Open/Save buttons
      • Lines: 2387-2397 (fixed height for FXChainList BeginChild)
    - Added: Right-click to rename saved FX/chains.
      • Right-click any saved preset → "Rename" menu item
      • Opens rename dialog with current custom name (or empty if using track name)
      • Leave empty to use dynamic track name, or enter custom name
      • Lines: 2655-2663 (context menu), 2796-2825 (rename popup), 942-947 (rename function)
      • GUI state: show_rename_popup, rename_chain_idx, rename_chain_name (lines 709-711)
    - Fixed: Save FX Preset dialog now correctly uses default FX name when unchanged.
      • Previous issue: Pressing OK without editing resulted in empty preset name
      • New: Simplified dialog - just one input field with FX name as default
      • User can modify or press OK/Enter to save with default name
      • Lines: 2761-2786 (simplified Save FX Preset popup)
    - Purpose: Better workflow for managing saved presets with stable UI layout.

  [Internal Build 251214.1400] - MODE-BASED FX WINDOW TOGGLE + UI FIX
    - Fixed: Chain mode status bar text "No track focused" → "No Track FX" (line 2373)
    - Improved: Saved presets now remember whether they were saved as chain or focused FX.
      • Added mode field to saved_chains data structure ("chain" or "focused")
      • Data format: "name|guid|track_name|custom_name|mode" (backward compatible)
      • Chain presets: always open FX chain window (even if only 1 FX)
      • Focused presets: always open floating FX window (for single FX)
      • Lines: 874-898 (load with mode), 909-916 (save with mode), 919-928 (add_saved_chain)
    - Improved: Window toggle behavior determined by how preset was saved, not FX count.
      • Previous issue: Chain with 1 FX would open floating window (incorrect)
      • User feedback: "chain有可能雖然有時候只有一個 但可能會需要新增修改之類的"
      • Solution: Track mode when saving, use mode to determine window type
      • Lines: 1693-1715 (open_saved_chain_fx using mode field)
      • Lines: 2718 (Save This Chain → mode="chain"), 2761 (Save This FX → mode="focused")
    - Purpose: Correct window type for saved presets - chains can be modified, focused FX are standalone.

  0.1.0 [Internal Build 251214.1100] - IMPROVED CHAIN/PRESET WORKFLOW
    - Improved: Chain mode now shows FX chain preview without requiring focused FX window.
      • If no FX window is focused: automatically uses first selected track with FX
      • If FX window is focused: prioritizes focused FX track (existing behavior)
      • Allows quick preview of track FX chains without opening FX window
      • Lines: 1036-1047 (auto-detect selected track logic in update_focused_fx_display)
    - Improved: "Save This Chain" button now available whenever FX chain is visible.
      • Previous: Required focused FX window (has_valid_fx check)
      • New: Available in Chain mode as long as track has FX (focused or selected)
      • More convenient workflow: select track → see FX chain → save directly
      • Lines: 2341-2348 (removed has_valid_fx requirement)
    - Added: "Save This FX" button in Focused mode for saving single FX presets.
      • New button appears below FX chain display when valid FX is focused
      • Opens preset save dialog with FX name as default
      • Saves single FX as a chain preset with custom name
      • Hover tooltip shows current FX name for confirmation
      • Lines: 2350-2359 (Save This FX button), 2679-2718 (Save FX Preset popup)
    - Technical: New GUI state variables for FX preset saving.
      • Added: show_save_fx_popup, new_fx_preset_name (line 668, 670)
      • Reuses existing saved_chains system (single FX saved as chain)
    - Purpose: Streamlined workflow for saving both chains and individual FX presets without requiring FX windows to be open.

  [Internal Build 251213.1330] - FIXED DUPLICATE TRACK NAME ISSUE BY PASSING TRACK OBJECT
    - Fixed: Preview now correctly targets the right track when multiple tracks have identical names.
      - Critical fix: Pass MediaTrack* object directly to Preview Core instead of just track name
      - Previous issue: When GUID found the correct track, only track name was passed to Preview Core
      - Preview Core behavior: Searches all tracks by name and uses FIRST match (wrong for duplicates)
      - Solution: When GUID resolves to a track, pass the track object directly (lines 1161, 1195-1196)
      - Result: Preview Core uses the exact track object, bypassing name search entirely
    - Enhanced: Comprehensive debug logging for preview target selection.
      - Shows decision tree: focused FX → GUID lookup → name fallback
      - Displays GUID, track name, and whether MediaTrack* object is passed
      - Helps diagnose duplicate name scenarios
      - Lines: 1129-1186 (debug logging throughout selection process)
    - Technical: Smart args construction for Preview Core.
      - If track object available: `target = MediaTrack*`, `target_track_name = nil`
      - If only name available: `target = nil`, `target_track_name = "name"`
      - Ensures Preview Core uses most reliable target method available

  Internal Build 251213.0352 - IMPROVED PREVIEW TARGET WITH GUID-BASED TRACK IDENTIFICATION
    - Enhanced: Preview target now uses GUID for unique track identification.
      - Added: preview_target_track_guid field to store track GUID
      - Stores both track name AND GUID for reliable identification
      - Fallback: If GUID not found (track deleted/project changed), falls back to track name search
      - Lines: 658 (field definition), 695/743 (save/load), 1155-1179 (GUID resolution)
    - Added: "Set First Selected Track" button in Preview Target edit popup.
      - Quick-select: Click button to instantly set first selected track as preview target
      - Stores both track name AND GUID simultaneously
      - Auto-saves settings immediately
      - Works when multiple tracks selected (uses first track only)
      - Lines: 2119-2136 (Set First Selected Track button with GUID)
    - Purpose: Robust preview targeting that survives track renaming and handles duplicate names.

  Internal Build 251213.0342 - SYNCED CHAIN PREVIEW LOGIC WITH TOOLS SCRIPT
    - Updated: Chain preview logic now synchronized between GUI and Tools script.
      - Tools script (hsuanice_AudioSweet Chain Preview Solo Exclusive.lua) updated to v251213.0336
      - Both GUI and Tools script now use identical smart target selection logic:
        * If focused FX chain exists → preview that track (using pure P_NAME)
        * If no focused FX chain → use preview_target_track from GUI settings
      - Ensures consistent behavior whether previewing from GUI or keyboard shortcut
      - Tools script reads all settings from GUI ExtState (single source of truth)
    - Purpose: Unified preview experience across all AudioSweet interfaces.

  Internal Build 251213.0253 - IMPROVED SAVED CHAINS WITH DYNAMIC TRACK NAME AND FX INFO
    - Improved: Saved Chains now support custom names and dynamic track name updates.
      - Added: Optional custom name field when saving a chain
      - If custom name is provided: Display remains fixed (custom name)
      - If no custom name: Display auto-updates with current track name when track is renamed
      - Hover tooltip: Shows current track name + current FX chain (always up-to-date)
      - Lines: 766-789 (load with custom_name), 791-807 (save with custom_name), 809-817 (add_saved_chain)
    - Added: Smart display logic for Saved Chains presets.
      - New helper function: get_chain_display_info() (lines 835-886)
      - Resolves track by GUID to get current track name and FX list
      - Display priority: custom_name > current_track_name > saved_track_name
      - Hover tooltip format: "Track: [name]\n1. [Type]: FX\n2. [Type]: FX..."
      - FX list shows full plugin info including type (VST3, CLAP, JS, AU, etc.)
      - Lines: 2382-2424 (display logic with tooltip)
    - Improved: Save Chain dialog now has two input fields.
      - Custom Name (optional): User-defined name that won't change
      - Internal ID (auto-generated): Technical identifier
      - Clear instructions: "Leave empty to use track name (will auto-update when track is renamed)"
      - Lines: 2405-2436 (Save Chain popup)
    - Improved: Hover tooltip FX list format.
      - Changed from horizontal (FX1 → FX2 → FX3) to vertical list (like FX insert)
      - Shows plugin type prefix (VST3:, CLAP:, JS:, AU:, VST:)
      - Format: "1. VST3: Pro-Q 4 (FabFilter)" (full plugin info with vendor)
      - More readable and consistent with REAPER's FX chain display
      - Lines: 869-883 (FX list building)
    - Technical: Backward compatible with existing saved chains (custom_name field is optional).
    - Purpose: Solves the problem of identifying saved chains when track names change.

  Internal Build 251213.0026 - IMPROVED CHAIN PREVIEW TARGET SELECTION AND SOLO TARGETING
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
local OS_NAME = r.GetOS()
local IS_WINDOWS = OS_NAME:match("Win") ~= nil
local PATH_SEPARATOR = IS_WINDOWS and ';' or ':'
local DIR_SEPARATOR = package.config:sub(1,1) or '/'
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
  focused_fx_index = nil,  -- Store FX index for focused mode
  focused_track = nil,
  focused_track_name = "",
  focused_track_fx_list = {},
  saved_chains = {},
  history = {},
  new_chain_name = "",
  new_chain_name_default = "",  -- Store initial default value to detect if user modified
  new_fx_preset_name = "",
  show_save_popup = false,
  show_save_fx_popup = false,
  show_rename_popup = false,
  rename_chain_idx = nil,
  rename_chain_name = "",
  show_settings_popup = false,
  show_fxname_popup = false,
  show_preview_settings = false,
  show_naming_popup = false,
  show_target_track_popup = false,
  show_tc_embed_popup = false,
  -- Preview settings
  preview_target_track = "AudioSweet",
  preview_target_track_guid = "",  -- Track GUID for unique identification
  preview_solo_scope = 0,     -- 0=track, 1=item
  preview_restore_mode = 0,   -- 0=timesel, 1=guid
  is_previewing = false,      -- Track if preview is currently playing
  -- Feature flags
  enable_saved_chains = true,   -- Now working with OVERRIDE ExtState mechanism
  enable_history = true,        -- Now working with OVERRIDE ExtState mechanism
  show_presets_history = true,  -- Show/Hide Saved Preset + History block
  -- UI settings
  enable_docking = false,       -- Allow window docking
  bwfmetaedit_custom_path = "",
  open_bwf_install_popup = false,
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
  r.SetExtState(SETTINGS_NAMESPACE, "preview_target_track_guid", gui.preview_target_track_guid, true)
  r.SetExtState(SETTINGS_NAMESPACE, "preview_solo_scope", tostring(gui.preview_solo_scope), true)
  r.SetExtState(SETTINGS_NAMESPACE, "preview_restore_mode", tostring(gui.preview_restore_mode), true)
  -- UI settings
  r.SetExtState(SETTINGS_NAMESPACE, "enable_docking", gui.enable_docking and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "show_presets_history", gui.show_presets_history and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "bwfmetaedit_custom_path", gui.bwfmetaedit_custom_path or "", true)
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
  gui.preview_target_track_guid = get_string("preview_target_track_guid", "")
  gui.preview_solo_scope = get_int("preview_solo_scope", 0)
  gui.preview_restore_mode = get_int("preview_restore_mode", 0)
  gui.bwfmetaedit_custom_path = get_string("bwfmetaedit_custom_path", "")
  -- UI settings
  gui.enable_docking = get_bool("enable_docking", false)
  gui.show_presets_history = get_bool("show_presets_history", true)

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
    try_candidate(custom, "custom path")
    if IS_WINDOWS and not found_path and not custom:lower():match("%.exe$") then
      try_candidate(custom .. ".exe", "custom path (.exe)")
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
      bwf_cli.message = "No 'bwfmetaedit' binary detected. Timecode embedding is currently disabled."
    end
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
    "AudioSweet relies on the bwfmetaedit CLI to embed BWF TimeReference (timecode).\n" ..
    "You can continue using other features, but TC embedding stays off until the CLI is installed.")
  if bwf_cli.message ~= "" then
    ImGui.TextDisabled(ctx, bwf_cli.message)
  end

  if ImGui.Button(ctx, "Install Guide##as_warn") then
    gui.open_bwf_install_popup = true
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Re-check##as_warn") then
    check_bwfmetaedit(true)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remind Me Later##as_warn") then
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
      "AudioSweet calls the BWF MetaEdit CLI to write BWF TimeReference (timecode) back into rendered files.\n" ..
      "Without the CLI, the embed step is skipped. The steps below describe a Homebrew-based install on macOS:")
    ImGui.Spacing(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 1: Install Homebrew (if missing)")
    ImGui.TextWrapped(ctx, "Open Terminal, run the following command, and follow the prompts to install Homebrew:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##as_brew_install_cmd", BREW_INSTALL_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##as_copy_brew_install") then
      r.ImGui_SetClipboardText(ctx, BREW_INSTALL_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Reference: https://brew.sh")
    ImGui.Separator(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 2: Install BWF MetaEdit CLI")
    ImGui.TextWrapped(ctx, "Once Homebrew is installed, run this command to install bwfmetaedit:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##as_brew_bwf_cmd", BREW_BWF_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##as_copy_bwf") then
      r.ImGui_SetClipboardText(ctx, BREW_BWF_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Binary is typically placed in /opt/homebrew/bin")
    ImGui.Separator(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 3: Verify the CLI")
    ImGui.TextWrapped(ctx, "Confirm the binary responds by running:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##as_brew_verify_cmd", BWF_VERIFY_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##as_copy_verify") then
      r.ImGui_SetClipboardText(ctx, BWF_VERIFY_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Version output = install success")
    ImGui.Spacing(ctx)

    ImGui.TextWrapped(ctx,
      "After installing, reopen AudioSweet (or press \"Re-check CLI\") to enable embedding again.\n" ..
      "Windows users (or anyone skipping Homebrew) can download installers from MediaArea: https://mediaarea.net/BWFMetaEdit")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Close", 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

local function draw_tc_embed_settings_popup()
  if gui.show_tc_embed_popup then
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'Timecode Embed Settings')
    gui.show_tc_embed_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'Timecode Embed Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    if bwf_cli.available then
      ImGui.TextColored(ctx, 0x55FF55FF, ("CLI detected: %s"):format(bwf_cli.resolved_path))
      if bwf_cli.last_source ~= "" then
        ImGui.TextDisabled(ctx, ("Source: %s"):format(bwf_cli.last_source))
      end
    else
      ImGui.TextColored(ctx, 0xFF6666FF, "bwfmetaedit CLI not detected – Timecode embedding stays disabled.")
      if bwf_cli.message ~= "" then
        ImGui.TextWrapped(ctx, bwf_cli.message)
      end
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Custom CLI Path (optional):")
    ImGui.SetNextItemWidth(ctx, 360)
    local rv_path, new_path = ImGui.InputText(ctx, "##as_bwf_path", gui.bwfmetaedit_custom_path or "")
    if rv_path then
      gui.bwfmetaedit_custom_path = new_path
      save_gui_settings()
    end
    ImGui.TextDisabled(ctx, "Leave blank to search PATH. Provide full path incl. .exe on Windows.")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Re-check CLI##as_settings") then
      check_bwfmetaedit(true)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Install Guide##as_settings") then
      gui.open_bwf_install_popup = true
    end

    ImGui.Spacing(ctx)
    ImGui.TextWrapped(ctx,
      "AudioSweet uses bwfmetaedit after renders to embed BWF TimeReference so downstream apps read the correct TC.\n" ..
      "If you skip installation, rendering still works but the embed step is skipped.")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Close##as_tc_settings", 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
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
    -- Format: name|guid|track_name|custom_name|mode|fx_index
    -- For backward compatibility: if no custom_name, mode, or fx_index, they will be nil/"chain"/nil
    local parts = {}
    for part in (data .. "|"):gmatch("([^|]*)|") do
      table.insert(parts, part)
    end
    local name, guid, track_name, custom_name, mode, fx_index_str = parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
    if name and guid then
      local fx_index = nil
      if fx_index_str and fx_index_str ~= "" then
        fx_index = tonumber(fx_index_str)
      end
      gui.saved_chains[#gui.saved_chains + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
        custom_name = (custom_name and custom_name ~= "") and custom_name or nil,
        mode = (mode and mode ~= "") and mode or "chain",  -- Default to "chain" for backward compatibility
        fx_index = fx_index,  -- Load fx_index
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
    local data = string.format("%s|%s|%s|%s|%s|%s",
      chain.name,
      chain.track_guid,
      chain.track_name,
      chain.custom_name or "",
      chain.mode or "chain",
      tostring(chain.fx_index or ""))  -- Add fx_index field
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. (i - 1), data)
  end
end

local function add_saved_chain(name, track_guid, track_name, custom_name, mode, fx_index)
  gui.saved_chains[#gui.saved_chains + 1] = {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
    custom_name = custom_name,
    mode = mode or "chain",
    fx_index = fx_index,  -- Store FX index for focused mode
  }
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AudioSweet] Save preset: name='%s', mode='%s', fx_index=%s\n",
      name or "nil", mode or "chain", tostring(fx_index or "nil")))
  end
  save_chains_to_extstate()
end

local function delete_saved_chain(idx)
  table.remove(gui.saved_chains, idx)
  save_chains_to_extstate()
end

local function rename_saved_chain(idx, new_custom_name)
  if gui.saved_chains[idx] then
    local chain = gui.saved_chains[idx]
    chain.custom_name = (new_custom_name and new_custom_name ~= "") and new_custom_name or nil
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Rename preset #%d: custom_name='%s', mode='%s'\n",
        idx, tostring(chain.custom_name or "nil"), chain.mode or "chain"))
    end
    save_chains_to_extstate()

    -- Sync rename to history items that match this preset
    -- Match by: track_guid + mode + (fx_index for focused, name for chain)
    for _, hist_item in ipairs(gui.history) do
      if hist_item.track_guid == chain.track_guid and hist_item.mode == chain.mode then
        if chain.mode == "focused" then
          -- For focused mode: match by fx_index
          if hist_item.fx_index == chain.fx_index then
            hist_item.custom_name = chain.custom_name
          end
        else
          -- For chain mode: match by name (original internal name)
          if hist_item.name == chain.name then
            hist_item.custom_name = chain.custom_name
          end
        end
      end
    end

    -- Save updated history to ExtState
    for i = 0, gui.max_history - 1 do
      r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
    end
    for i, item in ipairs(gui.history) do
      local data = string.format("%s|%s|%s|%s|%d|%s", item.name, item.track_guid, item.track_name, item.mode, item.fx_index, item.custom_name or "")
      r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. (i - 1), data)
    end
  end
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

-- Get display name and current info for a saved chain
-- Returns: display_name, track_info_line, fx_info, saved_fx_index
local function get_chain_display_info(chain)
  local display_name = chain.name  -- fallback
  local current_track_name = nil
  local fx_info = ""
  local track_number = nil
  local track_info_line = ""  -- First line for tooltip: #track_number: track_name
  local saved_fx_index = nil  -- For focused mode: which FX is the saved one
  local found_fx_name = nil  -- For focused mode: current FX name from track

  -- Try to find the track by GUID
  local tr = find_track_by_guid(chain.track_guid)
  if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
    -- Get current track name and number
    local _, track_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    current_track_name = track_name
    track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")  -- 1-based

    -- Build track info line for tooltip (always show #number: name)
    track_info_line = string.format("#%d: %s", track_number, track_name)

    -- Build FX info based on mode
    if chain.mode == "focused" then
      -- For focused FX: show entire FX chain, mark the saved FX
      local found_fx_idx = nil

      -- Method 1: Try to use saved fx_index if available
      if chain.fx_index then
        local fx_count = r.TrackFX_GetCount(tr)
        if chain.fx_index < fx_count then
          local _, fx_name = r.TrackFX_GetFXName(tr, chain.fx_index, "")
          -- Verify this is still the same FX (name should match or contain saved name)
          if fx_name and (fx_name == chain.name or fx_name:find(chain.name, 1, true)) then
            found_fx_name = fx_name
            found_fx_idx = chain.fx_index
          end
        end
      end

      -- Method 2: If index didn't work, search by exact name match
      if not found_fx_name then
        local fx_count = r.TrackFX_GetCount(tr)
        for i = 0, fx_count - 1 do
          local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
          -- Only exact match to avoid matching wrong FX
          if fx_name == chain.name then
            found_fx_name = fx_name
            found_fx_idx = i
            break
          end
        end
      end

      -- Build full FX chain list, same as chain mode
      saved_fx_index = found_fx_idx  -- Store for tooltip coloring
      local fx_count = r.TrackFX_GetCount(tr)
      if fx_count > 0 then
        local fx_lines = {}
        for i = 0, fx_count - 1 do
          local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
          table.insert(fx_lines, string.format("%d. %s", i + 1, fx_name))
        end
        fx_info = table.concat(fx_lines, "\n")
      else
        fx_info = "No FX"
      end
    else
      -- For chain mode: show entire FX chain list
      local fx_count = r.TrackFX_GetCount(tr)
      if fx_count > 0 then
        local fx_lines = {}
        for i = 0, fx_count - 1 do
          local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
          -- fx_name format: "VST3: Pro-Q 4 (FabFilter)" or "JS: ReaEQ"
          -- Keep the full name including plugin type
          -- Format: "1. [Plugin Type]: FX Name"
          table.insert(fx_lines, string.format("%d. %s", i + 1, fx_name))
        end
        fx_info = table.concat(fx_lines, "\n")
      else
        fx_info = "No FX"
      end
    end
  else
    track_info_line = "Track not found"
    fx_info = ""
  end

  -- Determine display name based on mode
  if chain.mode == "focused" then
    -- Focused FX mode: use custom name OR current FX name from track (real-time)
    if chain.custom_name and chain.custom_name ~= "" then
      display_name = chain.custom_name
    else
      -- Use current FX name from track, fallback to saved name
      display_name = found_fx_name or chain.name
    end
  else
    -- Chain mode: use custom name OR current track name OR saved track name
    if chain.custom_name and chain.custom_name ~= "" then
      display_name = chain.custom_name
      -- Add track# prefix for custom names
      if track_number then
        display_name = string.format("#%d %s", track_number, display_name)
      end
    elseif current_track_name then
      -- Add track# prefix for dynamic track names
      if track_number then
        display_name = string.format("#%d %s", track_number, current_track_name)
      else
        display_name = current_track_name
      end
    else
      display_name = chain.track_name  -- fallback to saved name
    end
  end

  return display_name, track_info_line, fx_info, saved_fx_index
end

-- Get display name for a history item with current track info
local function get_history_display_name(hist_item)
  local display_name = hist_item.name  -- fallback

  -- Try to find the track by GUID to get current track number
  local tr = find_track_by_guid(hist_item.track_guid)
  if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
    local track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")  -- 1-based
    local _, track_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)

    if hist_item.mode == "focused" then
      -- Focused mode: use custom name OR FX name (no track# prefix)
      if hist_item.custom_name and hist_item.custom_name ~= "" then
        display_name = hist_item.custom_name
      else
        -- Use the saved FX name (hist_item.name already contains full FX name)
        display_name = hist_item.name
      end
    else
      -- Chain mode: use custom name OR current track name
      if hist_item.custom_name and hist_item.custom_name ~= "" then
        display_name = hist_item.custom_name
        -- Add track# prefix for custom names
        if track_number then
          display_name = string.format("#%d %s", track_number, display_name)
        end
      elseif track_number then
        -- Use current track name with track# prefix
        display_name = string.format("#%d %s", track_number, track_name)
      else
        display_name = track_name
      end
    end
  end

  return display_name
end

-- Show hover tooltip for preset/history item (shared function)
-- item: saved chain or history item
local function show_preset_tooltip(item)
  local tr = find_track_by_guid(item.track_guid)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then
    ImGui.SetTooltip(ctx, "Track not found")
    return
  end

  local track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
  local _, track_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  local track_info_line = string.format("#%d: %s", track_number, track_name)

  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    ImGui.SetTooltip(ctx, track_info_line .. "\nNo FX")
    return
  end

  if item.mode == "focused" then
    -- For focused mode: show entire FX chain, mark the saved FX in GREEN
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, track_info_line)
    for fx_idx = 0, fx_count - 1 do
      local _, fx_name = r.TrackFX_GetFXName(tr, fx_idx, "")
      if fx_idx == (item.fx_index or 0) then
        -- This is the saved FX - color it green
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
        ImGui.Text(ctx, string.format("%d. %s", fx_idx + 1, fx_name))
        ImGui.PopStyleColor(ctx)
      else
        ImGui.Text(ctx, string.format("%d. %s", fx_idx + 1, fx_name))
      end
    end
    ImGui.EndTooltip(ctx)
  else
    -- For chain mode: show entire FX chain
    local fx_lines = {}
    for fx_idx = 0, fx_count - 1 do
      local _, fx_name = r.TrackFX_GetFXName(tr, fx_idx, "")
      table.insert(fx_lines, string.format("%d. %s", fx_idx + 1, fx_name))
    end
    local fx_info = table.concat(fx_lines, "\n")
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, track_info_line)
    ImGui.Text(ctx, fx_info)
    ImGui.EndTooltip(ctx)
  end
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
    -- Format: name|guid|track_name|mode|fx_index|custom_name
    local parts = {}
    for part in (data .. "|"):gmatch("([^|]*)|") do
      table.insert(parts, part)
    end
    local name, guid, track_name, mode, fx_idx_str, custom_name = parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
    if name and guid then
      gui.history[#gui.history + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
        mode = mode or "chain",
        fx_index = tonumber(fx_idx_str) or 0,
        custom_name = (custom_name and custom_name ~= "") and custom_name or nil,
      }
    end
    idx = idx + 1
  end
end

local function add_to_history(name, track_guid, track_name, mode, fx_index, custom_name)
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
    custom_name = custom_name,
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
    local data = string.format("%s|%s|%s|%s|%d|%s", item.name, item.track_guid, item.track_name, item.mode, item.fx_index, item.custom_name or "")
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
      return true, "Track FX", name or "(unknown)", tr, fx_index
    end
  elseif retval == 2 then
    return true, "Take FX", "(Take FX not supported)", nil, nil
  end
  return false, "None", "No focused FX", nil, nil
end

local function update_focused_fx_display()
  local found, fx_type, fx_name, tr, fx_index = get_focused_fx_info()

  -- In Chain mode: if no focused FX, try to use first selected track with FX
  if gui.mode == 1 and not found then
    local sel_track = r.GetSelectedTrack(0, 0)  -- Get first selected track
    if sel_track and r.TrackFX_GetCount(sel_track) > 0 then
      tr = sel_track
      local track_name, track_num = get_track_name_and_number(tr)
      gui.focused_track = tr
      gui.focused_track_name = string.format("#%d - %s", track_num, track_name)
      gui.focused_track_fx_list = get_track_fx_chain(tr)
      gui.focused_fx_name = "Track: " .. track_name
      return false  -- Not a "valid focused FX" but we have a track with FX chain
    end
  end

  gui.focused_track = tr
  if found then
    if fx_type == "Track FX" then
      gui.focused_fx_name = fx_name
      gui.focused_fx_index = fx_index  -- Store FX index
      if tr then
        local track_name, track_num = get_track_name_and_number(tr)
        gui.focused_track_name = string.format("#%d - %s", track_num, track_name)
        gui.focused_track_fx_list = get_track_fx_chain(tr)
      end
      return true
    else
      gui.focused_fx_name = fx_name .. " (WARNING)"
      gui.focused_fx_index = nil
      gui.focused_track_name = ""
      gui.focused_track_fx_list = {}
      return false
    end
  else
    gui.focused_fx_name = "No focused FX"
    gui.focused_fx_index = nil
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
  local target_track_obj = nil  -- Store the actual track object to pass directly

  if gui.debug then
    r.ShowConsoleMsg(string.format("\n[AudioSweet] === PREVIEW TARGET SELECTION DEBUG ===\n"))
    r.ShowConsoleMsg(string.format("  Mode: %s\n", gui.mode == 1 and "Chain" or "Focused"))
    r.ShowConsoleMsg(string.format("  Settings preview_target_track: %s\n", gui.preview_target_track))
    r.ShowConsoleMsg(string.format("  Settings preview_target_track_guid: %s\n", gui.preview_target_track_guid or "(empty)"))
    r.ShowConsoleMsg(string.format("  Has focused_track: %s\n", gui.focused_track and "YES" or "NO"))
  end

  if gui.mode == 1 then
    -- Chain mode: prioritize focused FX chain track if available
    if gui.focused_track and r.ValidatePtr2(0, gui.focused_track, "MediaTrack*") then
      -- Get pure track name from track object (P_NAME doesn't include track number)
      local _, pure_name = r.GetSetMediaTrackInfo_String(gui.focused_track, "P_NAME", "", false)
      local focused_guid = get_track_guid(gui.focused_track)
      target_track_name = pure_name
      target_track_obj = gui.focused_track
      if gui.debug then
        r.ShowConsoleMsg(string.format("  DECISION: Using focused FX chain track\n"))
        r.ShowConsoleMsg(string.format("  → Track: %s (GUID: %s)\n", pure_name, focused_guid))
      end
    else
      -- No focused FX: use settings target track
      if gui.debug then
        r.ShowConsoleMsg(string.format("  DECISION: No focused FX, using settings\n"))
      end
      -- Try to find track by GUID first (more reliable for duplicate names)
      if gui.preview_target_track_guid and gui.preview_target_track_guid ~= "" then
        local target_track = find_track_by_guid(gui.preview_target_track_guid)
        if target_track and r.ValidatePtr2(0, target_track, "MediaTrack*") then
          -- Found by GUID: get current track name and store track object
          local _, current_name = r.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
          target_track_name = current_name
          target_track_obj = target_track  -- IMPORTANT: Pass track object directly to avoid duplicate name issues
          if gui.debug then
            r.ShowConsoleMsg(string.format("  → Found by GUID: %s\n", gui.preview_target_track_guid))
            r.ShowConsoleMsg(string.format("  → Track name: %s\n", current_name))
            r.ShowConsoleMsg(string.format("  → Will pass MediaTrack* directly to Preview Core\n"))
          end
        else
          -- GUID not found: fallback to name
          if gui.debug then
            r.ShowConsoleMsg(string.format("  → GUID not found: %s\n", gui.preview_target_track_guid))
            r.ShowConsoleMsg(string.format("  → Fallback to track name search: %s\n", target_track_name))
          end
        end
      else
        -- No GUID: use track name directly
        if gui.debug then
          r.ShowConsoleMsg(string.format("  → No GUID stored, using track name: %s\n", target_track_name))
        end
      end
    end
  end

  if gui.debug then
    r.ShowConsoleMsg(string.format("  FINAL target_track_name: %s\n", target_track_name))
    r.ShowConsoleMsg(string.format("  FINAL target_track_obj: %s\n", target_track_obj and "MediaTrack*" or "nil (will use name search)"))
    r.ShowConsoleMsg("[AudioSweet] =====================================\n\n")
  end

  local args = {
    debug = gui.debug,
    chain_mode = (gui.mode == 1),  -- 0=focused, 1=chain
    mode = "solo",
    -- Pass track object directly if available (avoids duplicate name issues)
    -- Otherwise fall back to track name search
    target = target_track_obj or nil,
    target_track_name = target_track_obj and nil or target_track_name,
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
        -- No focused FX: find track by GUID first, then by name
        if gui.preview_target_track_guid and gui.preview_target_track_guid ~= "" then
          target_track = find_track_by_guid(gui.preview_target_track_guid)
          if target_track and r.ValidatePtr2(0, target_track, "MediaTrack*") then
            local _, tn = r.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
            track_name = tn
          end
        end
        -- Fallback to name search if GUID not found
        if not target_track then
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
        add_to_history(name, track_guid, gui.focused_track_name, "focused", fx_index, nil)  -- No custom name from direct execution
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
        add_to_history(name, track_guid, name, "chain", 0, nil)  -- chain mode uses index 0, no custom name from direct execution
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

  -- Select track and set as last touched
  r.SetOnlyTrackSelected(tr)
  r.SetMixerScroll(tr)

  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = string.format("Error: No FX on track '%s'", chain.track_name)
    return
  end

  -- Determine window type based on how it was saved
  if chain.mode == "focused" then
    -- Focused FX preset: toggle floating window for the specific FX
    local fx_idx = nil
    local found_fx_name = nil

    -- Method 1: Try saved fx_index first
    if chain.fx_index and chain.fx_index < fx_count then
      local _, fx_name = r.TrackFX_GetFXName(tr, chain.fx_index, "")
      -- Verify this is still the same FX
      if fx_name == chain.name then
        fx_idx = chain.fx_index
        found_fx_name = fx_name
      end
    end

    -- Method 2: If index didn't match, search by name
    if not fx_idx then
      for i = 0, fx_count - 1 do
        local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
        if fx_name == chain.name then
          fx_idx = i
          found_fx_name = fx_name
          break
        end
      end
    end

    -- Check if FX was found
    if not fx_idx then
      gui.last_result = string.format("Error: FX '%s' not found on track", chain.name)
      return
    end

    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Open preset: saved_name='%s', saved_index=%s, actual_index=%d, actual_name='%s'\n",
        chain.name, tostring(chain.fx_index or "nil"), fx_idx, found_fx_name))
    end

    local is_open = r.TrackFX_GetOpen(tr, fx_idx)
    if is_open then
      r.TrackFX_Show(tr, fx_idx, 2)  -- Hide floating window
    else
      r.TrackFX_Show(tr, fx_idx, 3)  -- Show floating window
    end
    gui.last_result = string.format("Toggled FX #%d: %s", fx_idx + 1, found_fx_name)
  else
    -- Chain preset: toggle FX chain window
    local chain_visible = r.TrackFX_GetChainVisible(tr)

    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Open chain: name='%s', mode='%s', chain_visible=%d\n",
        chain.name or "nil", chain.mode or "chain", chain_visible))
    end

    if chain_visible == -1 then
      -- Chain window is closed, open it
      r.TrackFX_Show(tr, 0, 1)  -- Show chain window
    else
      -- Chain window is open, close it
      r.TrackFX_Show(tr, 0, 0)  -- Hide chain window
    end
    gui.last_result = string.format("Toggled FX chain: %s", chain.name)
  end
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

    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Open history chain: name='%s', mode='%s', chain_visible=%d\n",
        hist_item.name or "nil", hist_item.mode or "chain", chain_visible))
    end

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

local function run_saved_chain(chain_idx)
  local chain = gui.saved_chains[chain_idx]
  if not chain then return end

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AudioSweet] Run preset #%d: name='%s', mode='%s', fx_index=%s\n",
      chain_idx, chain.name, chain.mode or "chain", tostring(chain.fx_index or "nil")))
  end

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

  -- Execute based on saved mode (chain or focused)
  if chain.mode == "focused" then
    -- For focused mode, use stored FX index
    if gui.action == 1 then
      run_focused_fx_copy_mode(tr, chain.name, chain.fx_index or 0, item_count)
    else
      run_history_focused_apply(tr, chain.name, chain.fx_index or 0, item_count)
    end
  else
    -- Chain mode - use chain execution
    if gui.action == 1 then
      run_saved_chain_copy_mode(tr, chain.name, item_count)
    else
      run_saved_chain_apply_mode(tr, chain.name, item_count)
    end
  end

  -- Add to history with correct mode, fx_index, and custom_name
  add_to_history(chain.name, chain.track_guid, chain.track_name, chain.mode or "chain", chain.fx_index or 0, chain.custom_name)

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", gui.action == 1 and "Copy" or "Apply", chain.name), -1)
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
                       ImGui.WindowFlags_NoResize |
                       ImGui.WindowFlags_NoCollapse

  -- Add NoDocking flag if docking is disabled
  if not gui.enable_docking then
    window_flags = window_flags | ImGui.WindowFlags_NoDocking
  end

  -- Set minimum window size to make buttons more readable (min width: 700px)
  ImGui.SetNextWindowSizeConstraints(ctx, 450, 0, 99999, 99999)

  local visible, open = ImGui.Begin(ctx, 'AudioSweet Control Panel', true, window_flags)
  if not visible then
    ImGui.End(ctx)
    return open
  end

  -- Close the window when ESC is pressed and the window is focused
  if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    open = false
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Keyboard shortcut: ESC pressed (Close window)\n")
    end
  end

  -- Menu Bar
  if ImGui.BeginMenuBar(ctx) then
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
      if ImGui.MenuItem(ctx, 'Timecode Embed Settings...', nil, false, true) then
        gui.show_tc_embed_popup = true
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
          "Version: 0.1.6 (251219.1800)\n" ..
          "Author: hsuanice\n\n" ..

          "Quick Start:\n" ..
          "  1. Select a track with FX or focus an FX window\n" ..
          "  2. Choose mode: Focused (single FX) or Chain (full track)\n" ..
          "  3. Click Apply to audition or Copy to prepare\n" ..
          "  4. Click Save to store presets for later use\n\n" ..

          "Key Features:\n" ..
          "  - Focused/Chain modes with real-time FX display\n" ..
          "  - Preset library with custom naming and rename sync\n" ..
          "  - Auto-tracked history (up to 50 operations)\n" ..
          "  - Keyboard shortcuts (Space=Play/Stop, S=Solo)\n" ..
          "  - Comprehensive file naming settings with FX Alias\n" ..
          "  - Debug mode with detailed console logging\n\n" ..


          "Reference:\n" ..
          "  Inspired by AudioSuite-like Script by Tim Chimes\n" ..
          "  'AudioSweet' is a name originally given by Tim Chimes.  \n" ..
          "  This project continues to use the name in reference to his original work.\n\n" ..
          "  Original: Renders selected plugin to selected media item\n" ..
          "  Written for REAPER 5.1 with Lua\n" ..
          "  v1.1 12/22/2015 - Added PreventUIRefresh\n" ..
          "  http://timchimes.com/scripting-with-reaper-audiosuite/\n\n" ..

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

  draw_bwfmetaedit_warning_banner()

  -- Settings Popup
  if gui.show_settings_popup then
    -- Position popup near mouse cursor
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'History Settings')
    gui.show_settings_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'History Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- ESC key handling for popup (only when popup is focused)
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

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
    -- Position popup near mouse cursor
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'File Naming Settings')
    gui.show_naming_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'File Naming Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- ESC key handling for popup (only when popup is focused)
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

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

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- "Set First Selected Track" button
    if ImGui.Button(ctx, 'Set First Selected Track', 250, 0) then
      local first_track = r.GetSelectedTrack(0, 0)  -- Get first selected track (index 0)
      if first_track then
        local _, track_name = r.GetSetMediaTrackInfo_String(first_track, "P_NAME", "", false)
        local track_guid = get_track_guid(first_track)
        gui.preview_target_track = track_name
        gui.preview_target_track_guid = track_guid
        save_gui_settings()
        if gui.debug then
          r.ShowConsoleMsg(string.format("[AudioSweet] Preview target set to first selected track: %s (GUID: %s)\n",
            track_name, track_guid))
        end
      else
        if gui.debug then
          r.ShowConsoleMsg("[AudioSweet] No track selected\n")
        end
      end
    end

    ImGui.Spacing(ctx)
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
    -- Position popup near mouse cursor
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'Preview Settings')
    gui.show_preview_settings = false
  end

  if ImGui.BeginPopupModal(ctx, 'Preview Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- ESC key handling for popup (only when popup is focused)
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

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
  
  draw_tc_embed_settings_popup()
  draw_bwfmetaedit_install_modal()

  -- Main content with compact layout
  local has_valid_fx = update_focused_fx_display()
  local item_count = r.CountSelectedMediaItems(0)

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
    ImGui.Text(ctx, "Copy to:")
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

    ImGui.SameLine(ctx, 0, 20)
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
  if gui.mode == 1 then
    -- Chain mode
    ImGui.Text(ctx, "Tip: Set shortcut 'Script: hsuanice_AudioSweet Chain Preview...' (Ctrl+Space)")
  else
    -- Focused mode
    ImGui.Text(ctx, "Tip: Set shortcut 'Script: hsuanice_AudioSweet Preview...' (Ctrl+Shift+Space)")
  end
  ImGui.PopStyleColor(ctx)

  ImGui.Separator(ctx)

  -- === SAVE BUTTON (above Saved/History) ===
  if gui.enable_saved_chains then
    -- Unified Save button that changes text based on mode
    local save_button_label = (gui.mode == 1) and "Save This Chain" or "Save This FX"
    local save_button_enabled = (gui.mode == 1 and #gui.focused_track_fx_list > 0) or (gui.mode == 0 and has_valid_fx)

    if not save_button_enabled then ImGui.BeginDisabled(ctx) end
    if ImGui.Button(ctx, save_button_label, -1, 0) then
      -- Unified save popup - we'll use one popup for both
      gui.show_save_popup = true
      if gui.mode == 1 then
        -- Extract only track name without "#N - " prefix
        local track_name, _ = get_track_name_and_number(gui.focused_track)
        gui.new_chain_name = track_name
        gui.new_chain_name_default = track_name  -- Store default
      else
        gui.new_chain_name = gui.focused_fx_name
        gui.new_chain_name_default = gui.focused_fx_name  -- Store default
      end
    end
    if not save_button_enabled then ImGui.EndDisabled(ctx) end
  end

  -- === QUICK PROCESS (Saved + History, side by side) ===
  if gui.enable_saved_chains or gui.enable_history then
    local changed
    changed, gui.show_presets_history = ImGui.Checkbox(ctx, "Show Presets/History", gui.show_presets_history)
    if changed then save_gui_settings() end

    if gui.show_presets_history then
      -- Show FX on recall checkbox
      changed, gui.show_fx_on_recall = ImGui.Checkbox(ctx, "Show FX window on recall", gui.show_fx_on_recall)
      if changed then save_gui_settings() end

      -- Only show if at least one feature is enabled and has content
      if (gui.enable_saved_chains and #gui.saved_chains > 0) or (gui.enable_history and #gui.history > 0) then
        local avail_w = ImGui.GetContentRegionAvail(ctx)
        local col1_w = avail_w * 0.5 - 5

        local function calc_list_height(item_count)
          local _, spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
          local frame_h = ImGui.GetFrameHeight(ctx)
          local text_h = ImGui.GetTextLineHeight(ctx)
          local header_line_h = math.max(frame_h, text_h)
          local separator_h = 1
          local header_height = header_line_h + spacing_y + separator_h + spacing_y
          local items_height = item_count * frame_h + math.max(0, item_count - 1) * spacing_y
          return math.min(header_height + items_height, 200)
        end

        -- Left: Saved FX Preset
        if gui.enable_saved_chains and #gui.saved_chains > 0 then
          local saved_height = calc_list_height(#gui.saved_chains)
          if ImGui.BeginChild(ctx, "SavedCol", col1_w, saved_height) then
            ImGui.Text(ctx, "SAVED FX PRESET")
            ImGui.Separator(ctx)
            local to_delete = nil
            for i, chain in ipairs(gui.saved_chains) do
              ImGui.PushID(ctx, i)

              -- Get display info
              local display_name, track_info_line, fx_info, saved_fx_index = get_chain_display_info(chain)

              -- "Open" button (small, on the left)
              if ImGui.SmallButton(ctx, "Open") then
                open_saved_chain_fx(i)
              end
              ImGui.SameLine(ctx)

              -- Chain name button (executes AudioSweet) - use available width minus Delete button
              local avail_width = ImGui.GetContentRegionAvail(ctx) - 25  -- Space for "X" button
              if ImGui.Button(ctx, display_name, avail_width, 0) then
                run_saved_chain(i)
              end

              -- Hover tooltip showing track and FX info
              if ImGui.IsItemHovered(ctx) then
                show_preset_tooltip(chain)
              end

              -- Right-click context menu for renaming
              if ImGui.BeginPopupContextItem(ctx, "chain_context_" .. i) then
                if ImGui.MenuItem(ctx, "Rename") then
                  gui.show_rename_popup = true
                  gui.rename_chain_idx = i
                  -- Pre-fill with current custom name, or use display name (without track# prefix for chains)
                  if chain.custom_name and chain.custom_name ~= "" then
                    gui.rename_chain_name = chain.custom_name
                  else
                    -- Use the base name without track# prefix
                    if chain.mode == "focused" then
                      gui.rename_chain_name = chain.name  -- FX name for focused mode
                    else
                      -- For chain mode, extract track name from track_info_line (#N: name)
                      local extracted_name = track_info_line:match("^#%d+: (.+)$")
                      gui.rename_chain_name = extracted_name or chain.track_name or ""
                    end
                  end
                end
                ImGui.EndPopup(ctx)
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
          end

          ImGui.SameLine(ctx)
        end

        -- Right: History (auto-resizes based on content)
        if gui.enable_history and #gui.history > 0 then
          -- Calculate height based on number of history items (each item ~25px, header ~40px)
          local history_height = calc_list_height(#gui.history)
          if ImGui.BeginChild(ctx, "HistoryCol", 0, history_height) then
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
              -- History item name button (executes AudioSweet) - use available width minus Save button
              local avail_width = ImGui.GetContentRegionAvail(ctx) - 45  -- Space for "Save" button
              local display_name = get_history_display_name(item)
              if ImGui.Button(ctx, display_name, avail_width, 0) then
                run_history_item(i)
              end

              -- Hover tooltip showing track and FX info
              if ImGui.IsItemHovered(ctx) then
                show_preset_tooltip(item)
              end

              ImGui.SameLine(ctx)
              -- "Save" button to save this history item as a saved preset
              if ImGui.Button(ctx, "Save", 40, 0) then
                -- Check if this exact preset already exists in saved_chains
                local already_saved = false
                for _, chain in ipairs(gui.saved_chains) do
                  if chain.track_guid == item.track_guid and chain.mode == item.mode then
                    if item.mode == "focused" then
                      -- For focused mode: check fx_index
                      if chain.fx_index == item.fx_index then
                        already_saved = true
                        break
                      end
                    else
                      -- For chain mode: check if same chain (by name)
                      if chain.name == item.name then
                        already_saved = true
                        break
                      end
                    end
                  end
                end

                if already_saved then
                  gui.last_result = "Info: This preset is already saved"
                else
                  -- Add to saved_chains
                  add_saved_chain(item.name, item.track_guid, item.track_name, nil, item.mode, item.fx_index)
                  gui.last_result = "Success: History item saved to presets"
                end
              end

              ImGui.PopID(ctx)
            end
            ImGui.EndChild(ctx)
          end
        end
      end
    end
  else
    -- Show "Developing" message when both features are disabled
    ImGui.TextWrapped(ctx, "SAVED FX PRESET and HISTORY features are currently under development.")
    ImGui.TextWrapped(ctx, "These features are not functioning properly and will be available in a future update.")
  end

  -- === FX INFO (at bottom, auto-resizes) ===
  ImGui.Separator(ctx)

  -- === STATUS (above FX info) ===
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

  -- STATUS BAR
  if has_valid_fx then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
  end

  if gui.mode == 0 then
    ImGui.Text(ctx, gui.focused_fx_name)
  else
    ImGui.Text(ctx, gui.focused_track_name ~= "" and ("Track: " .. gui.focused_track_name) or "No Track FX")
  end
  ImGui.PopStyleColor(ctx)

  ImGui.SameLine(ctx)
  ImGui.Text(ctx, string.format(" | Items: %d", item_count))

  -- Show FX chain in Chain mode (dynamic height, auto-resizes based on content)
  if gui.mode == 1 and #gui.focused_track_fx_list > 0 then
    -- Dynamic height based on FX count (each FX line ~20px), max 150px
    local line_height = 20
    local max_height = 150
    local fx_count = #gui.focused_track_fx_list
    local calculated_height = math.min(fx_count * line_height, max_height)

    if ImGui.BeginChild(ctx, "FXChainList", 0, calculated_height) then
      for _, fx in ipairs(gui.focused_track_fx_list) do
        local status = fx.offline and "[offline]" or (fx.enabled and "[on]" or "[byp]")
        ImGui.Text(ctx, string.format("%02d) %s %s", fx.index + 1, fx.name, status))
      end
      ImGui.EndChild(ctx)
    end
  end

  ImGui.End(ctx)

  -- === SAVE PRESET POPUP (Unified for both Chain and Focused modes) ===
  if gui.show_save_popup then
    -- Position popup near main window
    local main_x, main_y = ImGui.GetWindowPos(ctx)
    local main_w, main_h = ImGui.GetWindowSize(ctx)
    ImGui.SetNextWindowPos(ctx, main_x + main_w / 2, main_y + 50, ImGui.Cond_Appearing, 0.5, 0)
    ImGui.OpenPopup(ctx, "Save FX Preset")
    gui.show_save_popup = false
  end

  if ImGui.BeginPopupModal(ctx, "Save FX Preset", true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- Show track# prefix for chain mode (outside input field)
    if gui.mode == 1 and gui.focused_track then
      local track_number = r.GetMediaTrackInfo_Value(gui.focused_track, "IP_TRACKNUMBER")
      ImGui.Text(ctx, string.format("Track #%d - Preset Name:", track_number))
    else
      ImGui.Text(ctx, "Preset Name:")
    end
    ImGui.TextDisabled(ctx, "(leave empty to use default)")
    ImGui.Spacing(ctx)

    local rv, new_name = ImGui.InputText(ctx, "##presetname", gui.new_chain_name, 256)
    if rv then gui.new_chain_name = new_name end

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Save", 100, 0) or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
      if gui.focused_track then
        local user_input = gui.new_chain_name
        local default_value = gui.new_chain_name_default

        -- Determine final_name and custom_name
        local final_name
        local custom_name = nil

        if user_input == "" then
          -- User cleared the field → use default name, no custom name
          final_name = default_value
          custom_name = nil
        elseif user_input == default_value then
          -- User kept default value → use default name, no custom name
          final_name = default_value
          custom_name = nil
        else
          -- User modified the name → use user's input as both final_name and custom_name
          final_name = user_input
          custom_name = user_input
        end

        -- Check for duplicates
        local duplicate_found = false
        local track_guid = get_track_guid(gui.focused_track)
        local mode = (gui.mode == 1) and "chain" or "focused"
        local fx_index = (mode == "focused") and gui.focused_fx_index or nil

        -- For focused mode: get the ORIGINAL FX name from track (not processed by FX name settings)
        local original_fx_name = nil
        if mode == "focused" and fx_index ~= nil then
          local _, raw_fx_name = r.TrackFX_GetFXName(gui.focused_track, fx_index, "")
          original_fx_name = raw_fx_name
        end

        -- For chain mode: get current FX chain content for comparison
        local current_fx_list = nil
        if mode == "chain" then
          current_fx_list = get_track_fx_chain(gui.focused_track)
        end

        for _, chain in ipairs(gui.saved_chains) do
          -- For focused mode: check by track_guid + fx_index (same FX)
          -- For chain mode: check by track_guid + FX chain content (same chain regardless of name)
          if mode == "focused" and chain.mode == "focused" then
            if chain.track_guid == track_guid and chain.fx_index == fx_index then
              duplicate_found = true
              break
            end
          elseif mode == "chain" and chain.mode == "chain" then
            -- Compare FX chain content instead of name
            if chain.track_guid == track_guid then
              local saved_track = find_track_by_guid(chain.track_guid)
              if saved_track then
                local saved_fx_list = get_track_fx_chain(saved_track)
                -- Compare FX counts first
                if #saved_fx_list == #current_fx_list then
                  local chains_match = true
                  for i = 1, #saved_fx_list do
                    if saved_fx_list[i].name ~= current_fx_list[i].name then
                      chains_match = false
                      break
                    end
                  end
                  if chains_match then
                    duplicate_found = true
                    break
                  end
                end
              end
            end
          end
        end

        if duplicate_found then
          gui.last_result = "Error: This FX preset already exists"
        else
          -- For focused mode: use original FX name (with VST3:/CLAP: prefix) for internal storage
          -- For chain mode: use final_name (track name)
          local storage_name = (mode == "focused" and original_fx_name) or final_name
          add_saved_chain(storage_name, track_guid, gui.focused_track_name, custom_name, mode, fx_index)
          gui.last_result = "Success: Preset saved"
          gui.new_chain_name = ""
          gui.new_chain_name_default = ""
          ImGui.CloseCurrentPopup(ctx)
        end
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 100, 0) or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      gui.new_chain_name = ""
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  -- === RENAME CHAIN POPUP ===
  if gui.show_rename_popup then
    -- Position popup near main window
    local main_x, main_y = ImGui.GetWindowPos(ctx)
    local main_w, main_h = ImGui.GetWindowSize(ctx)
    ImGui.SetNextWindowPos(ctx, main_x + main_w / 2, main_y + 50, ImGui.Cond_Appearing, 0.5, 0)
    ImGui.OpenPopup(ctx, "Rename Preset")
    gui.show_rename_popup = false
  end

  if ImGui.BeginPopupModal(ctx, "Rename Preset", true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- Show track# prefix for chain mode (outside input field)
    local hint_text = "(leave empty to use default)"
    if gui.rename_chain_idx and gui.saved_chains[gui.rename_chain_idx] then
      local chain = gui.saved_chains[gui.rename_chain_idx]
      if chain.mode == "chain" then
        local tr = find_track_by_guid(chain.track_guid)
        if tr then
          local track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
          ImGui.Text(ctx, string.format("Track #%d - Preset Name:", track_number))
          -- Show current track name in hint
          local current_track_name, _ = get_track_name_and_number(tr)
          hint_text = string.format("(default: #%.0f - %s)", track_number, current_track_name)
        else
          ImGui.Text(ctx, "Preset Name:")
        end
      else
        -- Focused mode: show FX name in hint
        ImGui.Text(ctx, "Preset Name:")
        if chain.name then
          hint_text = string.format("(default: %s)", chain.name)
        end
      end
    else
      ImGui.Text(ctx, "Preset Name:")
    end
    ImGui.TextDisabled(ctx, hint_text)
    ImGui.Spacing(ctx)

    local rv, new_name = ImGui.InputText(ctx, "##renamefield", gui.rename_chain_name, 256)
    if rv then gui.rename_chain_name = new_name end

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "OK", 100, 0) then
      if gui.rename_chain_idx then
        rename_saved_chain(gui.rename_chain_idx, gui.rename_chain_name)
        gui.rename_chain_idx = nil
        gui.rename_chain_name = ""
        ImGui.CloseCurrentPopup(ctx)
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 100, 0) then
      gui.rename_chain_idx = nil
      gui.rename_chain_name = ""
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
check_bwfmetaedit(true)
load_saved_chains()
load_history()
r.defer(loop)
