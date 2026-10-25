# hsuanice_AudioSweet - AudioSuite Workflow.lua — Changelog

(formerly `hsuanice_AudioSweet ReaImGui.lua`)

AudioSweet ReaImGui - AudioSuite Workflow (Pro Tools–Style)

## 26.1025.2050pre1

- New: Glue grouping (All / RGWH / AS, Mute separate, Split at XF) and Single item Render (Retain Glue Cues) are now on the main window, below the Whole File / Tail row. They are the same settings as Settings > Glue & Render.

## 26.1016.1659

- Fix: AudioSweet no longer overwrites the RGWH Debug Level saved in the project; its Debug switch now applies to its own RGWH call only, so the RGWH Render / Glue shortcuts stop printing console logs after an AudioSweet run with Debug on.

## 26.1012.1641

- Renamed to "AudioSweet - AudioSuite Workflow" (was "AudioSweet ReaImGui") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1011.2225

- Fix: AudioSweet Solo Toggle no longer requires the SWS extension.
- Requirements: ReaImGui (install via ReaPack, ReaTeam Extensions) and the "hsuanice Library" package; BWF MetaEdit (bwfmetaedit) is needed only for timecode embedding.

## 26.1011.2142

- First release in the hsuanice/ReaScripts repository (replaces hsuanice/PublicBeta).
- Remove the PublicBeta repository in ReaPack before installing this one.
- Requires the "hsuanice Library" package.
- Version format is now YY.MMDD.HHMM.
- FX Alias tools are now installed with AudioSweet (run them from Settings > FX Alias Tools); they no longer appear in the Action List.
- Help > About now reads the version from the script header.

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.11 [261011.1059]`).

```text
0.2.11 [261011.1059]
  - ADDED: Settings → Glue & Render tab: "Retain Glue Cues" under Single item Render (default OFF)
  - CHANGED: Settings tab "Glue" renamed to "Glue & Render"; Single Item section title clarified
    • Render keeps the Glue cues already in the source file (requires SWS)
    • Synced as AS_RENDER_KEEP_GLUE_CUES (AudioSweet Core >= 0.3.8, RGWH Core >= 0.3.12)

0.2.10 [261010.1616]
  - ADDED: Settings → Glue tab: "Single item: Render (keep takes)" (default OFF)
    • Single-item units are rendered to a new take instead of glued; older takes kept
    • Item selection only: with any Time Selection, glue as before (no render, no grouping)
    • Synced to Core as AS_SINGLE_ITEM_RENDER (requires AudioSweet Core >= 0.3.6)

0.2.9 [261010.1547]
  - ADDED: Settings → Glue tab: glue unit grouping for item selection (no Time Selection)
    • Glue all (original behavior, default)
    • Follow RGWH GUI settings (Keep MUTED as separate unit / Split at crossfades)
    • AudioSweet settings: own Keep MUTED as separate unit + Split at crossfades checkboxes
    • Synced to Core as AS_GLUE_GROUPING / AS_GLUE_SPLIT_AT_CROSSFADES / AS_GLUE_MUTED_SEPARATE
    • Requires AudioSweet Core >= 0.3.5 and RGWH Core >= 0.3.10
  - FIXED (in AudioSweet Core 0.3.5): glue results sometimes left behind on the FX track

0.2.8 [260708.1252]
  - ADDED: Load Track FX now imports all single-FX presets from the selected REAPER track
  - ADDED: Load Chain now loads presets from all selected tracks in REAPER
  - IMPROVED: Preset panel UI now uses shorter labels and hover hints for clearer loading actions
  - IMPROVED: Preset section title simplified to "SAVED PRESET"
  - FIXED: Track-name parsing no longer misidentifies ordinary names like "8ChTrack" as track-number selectors

0.2.7 [260517.1748]
  - FIXED: Open button on Saved Presets / History no longer clobbers item/time/razor selection
    • Previously: with REAPER's "item+time selection link to track" enabled,
      clicking Open re-selected the FX-host track and the link wiped your
      pre-open item / time / razor selection
    • Now: open_saved_chain_fx() and open_history_fx() snapshot selection
      state (items, time selection, razor edits, track selection) before
      SetOnlyTrackSelected(), then restore it after TrackFX_Show — including
      on every early-return error path
    • Workflow: select items → click Open to adjust FX → press Execute,
      all without re-selecting items

0.2.6 [260330.1458]
  - ADDED: Auto track FX chain online/offline restore on preview/run
    • Saves and restores both I_FXEN (chain bypass) and per-FX offline bits
      so all forms of "FX chain offline" in REAPER are covered
    • Before preview or run: chain is brought online if offline; nothing changes if already online
    • After preview/run (or transport auto-stops): original state is restored
    • Applies to both Single FX (focused) mode and Chain mode
    • Preview FX track resolution now has full fallback (focused → GUID → name),
      matching the same logic used by Run

0.2.5 [260328.0408]
  - ADDED: Tail Seconds input field (requires RGWH Core ≥ 0.3.7)
    • New "Tail" input next to the handle seconds field
    • Extends the processed item into silence after the right handle
    • Captures reverb/delay/echo decay; 0 = off (backward-compatible default)
    • Written to RGWH ExtState (TAIL_SECONDS) on every Run/Apply

0.2.4 [260327.2345]
  - ADDED: Independent Show/Hide checkboxes for Presets and History panels
    • Split "Show Presets/History" into separate "Show Presets" and "Show History" checkboxes
    • Layout: [Show Presets] ... [Show FX window on recall] ... [Show History]
    • When only one panel is visible, it expands to use the full available width
    • When both panels are visible, they share the width 50/50 as before
  - ADDED: Drag-to-reorder for Saved FX Presets
    • Drag handle (=) added to the left of each preset row
    • Drop onto any row to insert the dragged item above it
    • New order is persisted immediately via save_chains_to_extstate()

0.2.3 [260205.1040]
  - ADJUSTED: Main page layout alignment and spacing tweaks

0.2.2 [260205.1027]
  - MOVED: Multi-Channel Policy from Settings tab to main page (two-row layout)
    • Row 1: Channel mode (left) + Preview Target (right)
    • Row 2: Policy radios — playback / track / target (left) + Whole File (right)
    • Policy always visible (shows current selection even in Auto/Mono mode)
    • Hover tooltips on each policy option
  - REMOVED: Settings → Channel Mode tab (redundant, now on main page)
  - UPDATED: Multi radio button tooltip simplified

0.2.1 [251223.2328] - Version Sync
  - CHANGED: Version bump to 0.2.0.0.1

v0.2.0 [Internal Build 251223.2256] - Public Beta Release
  - ADDED: Copy+Apply mode (GUI + Core) with consistent undo + stable multichannel IO
  - ADDED: AudioSweet Run/Solo/Preview Toggle tools (Action List workflow)
  - ADDED: Multi-Channel Policy system + Channel Mode settings
  - ADDED: Whole File handle option + BWF MetaEdit detection/install guide
  - ADDED: Unified Settings window + in-app User Manual
  - FIXED: Unified Core/GLUE path for all processing (removes RGWH Render path)
  - FIXED: Single undo behavior across GUI/Run/Saved/History
  - FIXED: FX index tracking + name fallback after reorder
  - FIXED: Preview target GUID handling + duplicate track name targeting
  - REMOVED: Legacy Preview Solo Exclusive tools (replaced by Preview Toggle)

v0.1.27 [Internal Build 251223.2236] - Version Sync
  - CHANGED: Version bump to align with Core changes (no UI behavior change)

v0.1.26 [Internal Build 251223.1924] - Copy+Apply UI + Settings Logs
  - CHANGED: Copy+Apply label + hover note about IO mapping limitations
  - CHANGED: Copy settings now show only for Copy (not Copy+Apply)
  - FIXED: GUI startup logging duplication; include Channel Policy in settings log

v0.1.25 [Internal Build 251222.2009] - Keyboard Shortcut Input Detection
  - ADDED: Shortcut handling before ImGui.Begin()
    • Space = Stop transport (command 40044)
    • S = Solo toggle (respects Preview Solo Scope)
  - SAFETY: Ignores shortcuts while typing in inputs (IsAnyItemActive)

v0.1.24 [Internal Build 251222.1706] - Single Undo for All Executions
  - CHANGED: All GUI Run executions now produce single undo operation
    • Main Run button: External undo control enabled
    • Saved Chains execution: External undo control enabled
    • History execution: External undo control enabled
    • AudioSweet Core v0.1.7: Skips internal undo when EXTERNAL_UNDO_CONTROL="1"
    • Cleaner undo stack (one entry instead of nested blocks)
  - BENEFIT: Simplified undo experience
    • GUI Run → Single "AudioSweet GUI: Focused/Chain Apply/Copy" undo
    • Saved Chain → Single "AudioSweet GUI: Apply/Copy [Chain Name]" undo
    • History → Single "AudioSweet GUI: Apply/Copy [History Name]" undo
  - CHANGED: Unified all processing to use Core/GLUE path (RGWH Render path eliminated)
    • AudioSweet Core v0.1.7: Single-item units now use Core/GLUE instead of RGWH Render
    • GLUE mode produces single take (no old take preserved)
    • Fixes position issues that occurred with RGWH Render path
    • Multi-Channel Policy already implemented in Core/GLUE path (works immediately)
    • Consistent behavior across all unit sizes (single/multi-item)

v0.1.23 [Internal Build 251222.1651] - Unified GLUE Path for All Processing
  - CHANGED: All units now use Core/GLUE path (RGWH Render path eliminated)
    • AudioSweet Core v0.1.6: Single-item units now use Core/GLUE instead of RGWH Render
    • GLUE mode produces single take (no old take preserved)
    • Fixes position issues that occurred with RGWH Render path
    • Multi-Channel Policy already implemented in Core/GLUE path (works immediately)
    • Consistent behavior across all unit sizes (single/multi-item)
  - BENEFIT: All processing paths now behave identically
    • Single-item: Core/GLUE
    • Multi-item: Core/GLUE
    • TS-WINDOW: Core/GLUE (already working)
    • Simpler codebase, more predictable results

v0.1.22 [Internal Build 251222.1622] - RGWH & AudioSweet Multi-Channel Policy Integration
  - ADDED: Complete Multi-Channel Policy support across ALL execution paths
    • RGWH Core v0.1.1: Added preserve_track_ch parameter + ExtState control (RGWH_PRESERVE_TRACK_CH)
    • AudioSweet Core v0.1.5: All paths now correctly implement Multi-Channel Policy
    • Single-item units (RGWH Render): Policy now works correctly (was overridden by RGWH Core)
    • Multi-item units (Core/GLUE): Policy now fully implemented (was missing)
    • TS-WINDOW paths: Continue to work correctly (no changes needed)
  - FIXED: Single-item and multi-item units now produce consistent results
    • SOURCE-PLAYBACK: Matches item/unit playback channels
    • SOURCE-TRACK: Matches source track channel count
    • TARGET-TRACK: Respects FX track channel count (passive mode)
  - TECHNICAL: ExtState-based communication between AudioSweet and RGWH Core
    • AudioSweet sets RGWH_PRESERVE_TRACK_CH before calling RGWH Core
    • RGWH Core respects this setting (backward compatible, defaults to preserve=true)
    • Enables both tools to work independently with their own policies

v0.1.21 [Internal Build 251222.1122] - Core/GLUE Source Track Protection
  - FIXED: Multi-item unit processing source track protection
    • AudioSweet Core v0.1.4: Core/GLUE path now protects source track channel count
    • Previously: processing 3-member unit changed source track from 4ch to 6ch (incorrect)
    • Now: source track channel count preserved at original value (correct)
    • Affects per-unit path when unit has ≥2 items without Time Selection
    • Completes source track protection coverage for all execution paths

v0.1.20 [Internal Build 251222.1103] - Multi-Unit Multi-Channel Policy Fix
  - FIXED: Multi-unit processing across tracks with SOURCE-TRACK policy
    • When processing multiple units across different tracks simultaneously, second unit now reads correct source track channel count
    • AudioSweet Core v0.1.3: TS-WINDOW[GLOBAL] path now snapshots ALL source track channel counts BEFORE glue operation
    • Previously: glue operation modified track channel counts before second unit snapshot (incorrect)
    • Now: all units use pre-glue snapshot values (correct)
    • Ensures consistent behavior when processing single vs multiple units

v0.1.19 [Internal Build 251222.1035] - Multi-Channel Policy System
  - ADDED: Complete Multi-Channel Policy system with 3 options (Settings → Channel Mode)
    • SOURCE playback: Match item's actual playback channels (default, current behavior)
    • SOURCE track: Match source track channel count (RGWH/Pro Tools style)
    • TARGET track: Respect FX track's current channel count (passive mode)
    • Policy only applies when Channel Mode is explicitly set to "Multi"
    • Auto/Mono modes use default behavior (not affected by policy)
  - ADDED: Settings → Channel Mode tab with 3 RadioButton options
    • Each option has description and example usage
    • Orange warning when Channel Mode is not "Multi"
    • Settings saved to ExtState: multi_channel_policy (source_playback/source_track/target_track)
  - ADDED: Multi RadioButton tooltip update
    • Shows current policy name
    • Hints user to configure in Settings → Channel Mode
    • Removed Shift+Click toggle (moved to Settings)
  - ADDED: ExtState synchronization to Core namespace
    • save_gui_settings() now syncs AS_MULTI_CHANNEL_POLICY to hsuanice_AS
    • set_extstate_from_gui() syncs policy when running from GUI button
    • Ensures policy works for both GUI button and Run.lua execution
  - ADDED: Multi-Channel Policy display in startup debug log
    • Shows policy when Channel Mode is Multi
    • Format: "Multi-Channel Policy: SOURCE playback/track or TARGET track"
  - CHANGED: Tab numbering updated (Channel Mode is Tab 4, Timecode is Tab 6)

v0.1.18.1 [Internal Build 251221.2133] - Multi-Channel Policy UI (deprecated)
  - NOTE: This version was experimental; v0.1.19 is the complete implementation
v0.1.18 [Internal Build 251221.1937] - Auto Mode + Single Rename
  - ADDED: Auto mode for window-based focused/chain detection
  - CHANGED: "Focused" label renamed to "Single"
  - UI: Auto moved to first position with hover tooltips
v0.1.17 [Internal Build 251221.1822] - Chain Run Without Focus + Button Enable
  - FIXED: Chain mode run now works without focused FX window
    • Falls back to preview target track when no focused FX is available
  - FIXED: AUDIOSWEET button now enabled in chain mode without focused FX
v0.1.16 [Internal Build 251221.1722] - Debug ExtState Logging
  - ADDED: Console logging when GUI debug is enabled
    • save_gui_settings() now prints a timestamped ExtState update header
    • Logs key settings after each change (channel mode, handles, preview target, etc.)
v0.1.15 [Internal Build 251220.2350] - Whole File Handle Option
  - ADDED: "Whole File" toggle option for rendering/gluing entire file length
    • New GUI element: Checkbox next to handle seconds input
    • When enabled, processes entire media item source length instead of handles
    • Implementation: Sets HANDLE_SECONDS to 999999, RGWH Core auto-clamps to available length
    • Handle seconds input becomes disabled (grayed out) when Whole File is checked
    • Setting persisted in GUI state (saved/loaded between sessions)
    • Lines: gui init (1210), save (1299), load (1361), GUI layout (4714-4735)
  - CHANGED: GUI layout for handles section
    • Removed "Handle:" and "seconds" text labels for cleaner layout
    • Layout: Channel options → [65px spacing] → Whole File checkbox → handle input
    • Handle input width: 80px (unchanged)
  - FIXED: Whole file logic implementation
    • Focused mode: Sets handle value before execution (lines 2631-2633)
    • Chain mode: Sets handle value before execution (lines 3144-3146)
    • Debug messages: Display "whole file" instead of seconds when enabled (lines 1425, 3151, 3351, 5348)
    • Settings display: Shows "Whole File" in status output when enabled
v0.1.14
  + FIXED: Custom names now fully support type/vendor display toggles
  + CHANGED: Rename dialog shows core name only, respects alias settings
  + ADDED: Smart helper functions for custom name handling
  + UPDATED: Display logic preserves original FX metadata while using custom names
0.1.13 [Internal Build 251220.0750] - Help System Refactoring
  - ADDED: In-app User Manual window (Help → User Manual)
    • New tabbed GUI window with 4 sections
    • Tab 1: Getting Started (Overview, Core Features, Operation Modes)
    • Tab 2: Actions & Presets (Main Actions, Preset System)
    • Tab 3: History & Workflows (History System, Workflow Examples)
    • Tab 4: Tips & Troubleshooting (Tips, Keyboard Shortcuts, Troubleshooting)
    • Window size: 700x600, scrollable content
    • Lines: 4186-4441 (help window implementation)
  - SIMPLIFIED: @about section (lines 7-28)
    • Removed all manual content (moved to GUI)
    • Now only contains: Quick Start, Reference, Development credits
    • Much cleaner ReaPack package description
    • Users directed to Help → User Manual for full docs
  - IMPROVED: Help menu structure
    • Help → User Manual (opens GUI window)
    • Help → About (prints reference to console)
    • Clear separation between documentation and credits
    • Lines: 3657-3685 (updated Help menu)
  - ADDED: GUI state variable
    • gui.show_help_window flag (line 1399)
    • Controls help window visibility
  - UX: Better documentation access
    • No need to read @about in ReaPack or text editor
    • Interactive, searchable (via tabs) manual
    • Always available in Help menu
    • Consistent with Settings window design

0.1.12 [Internal Build 251220.0744] - FX Index Tracking Fix
  - FIXED: Critical bug where presets/history execute wrong FX after reordering
    • Problem: Stored fx_index becomes invalid when FX order changes on track
    • Impact: Open and Execute buttons would process incorrect FX
    • Root cause: Only index validation without name verification
    • Lines affected: run_history_focused_apply (3277+), run_focused_fx_copy_mode (2947+)
  - ADDED: Unified FX resolution function for consistent lookup
    • New function: find_fx_on_track(track, saved_fx_index, saved_fx_name)
    • Method 1: Try saved index with name verification (fast path)
    • Method 2: Search by exact name if index invalid (fallback)
    • Returns: actual_fx_idx, actual_fx_name, status
    • Status values: "found_by_index", "found_by_name", "invalid_track", "no_fx", "not_found"
    • Lines: 2244-2274 (unified FX resolution function)
  - REFACTORED: All FX lookup operations now use unified function
    • get_chain_display_info(): Lines 2359+ (display name generation)
    • get_history_display_name(): Lines 2444+ (history display names)
    • show_preset_tooltip(): Lines 2507+ (tooltip hover highlighting)
    • open_saved_chain_fx(): Lines 3265+ (Open button)
    • run_history_focused_apply(): Lines 3283+ (Execute/Apply)
    • run_focused_fx_copy_mode(): Lines 2953+ (Copy mode)
    • Eliminated ~70 lines of duplicate FX lookup code
  - ADDED: Smart debug logging with anti-spam cache
    • Tooltip hover: Shows when FX moved (line 2477-2487)
    • Open button: Shows saved vs actual index (line 3272-3277)
    • Execute operations: Already had debug logs
    • Cache mechanism: Only logs each FX movement ONCE per session
    • Cache key: "track_guid|fx_name|saved_idx|actual_idx"
    • Cache storage: gui.fx_move_logged table (line 1388)
    • Result: Clean, readable debug output without repetition
  - TECHNICAL: DRY principle applied to FX resolution
    • Single source of truth for FX lookup logic
    • Easier to maintain and extend (e.g., fuzzy matching)
    • Consistent behavior across all operations
  - BEHAVIOR: Graceful fallback when FX order changes
    • Index mismatch: Falls back to name search automatically
    • FX not found: Clear error message with FX name
    • Backward compatible: Existing presets work without migration
  - EDGE CASES: Handled edge cases
    • Invalid track pointer: Returns "invalid_track" status
    • Empty FX chain: Returns "no_fx" status
    • FX deleted: Returns "not_found" with clear error message
    • Duplicate FX names: Matches first occurrence (same as before)

0.1.11 [Internal Build 251219.2245] - Unified Settings Window
  - REDESIGNED: Unified Settings window with tabbed interface
    • New: Settings → Settings... opens unified window
    • Previous: 5 separate settings popups (History, File Naming, Preset/History Display, Preview, Timecode)
    • Now: Single window with 5 tabs (FX Display, File Naming, Preview, History, Timecode)
    • Lines: 3608-3945 (unified settings window implementation)
  - IMPROVED: Settings menu reorganization
    • Kept: Settings → Enable Window Docking (independent checkbox in menu)
    • Removed: Individual setting menu items
    • Added: Settings → Settings... (opens unified tabbed window)
    • Lines: 3512-3526 (simplified settings menu)
  - RENAMED: "Preset/History Display" → "FX Display"
    • More accurate name covering all contexts: Button, Tooltip, Status, FX List
    • Now appears as first tab in unified Settings window
  - TECHNICAL: New GUI state variable
    • Added: gui.show_unified_settings flag (line 1329)
    • Controls unified settings window visibility
  - IMPROVED: Better user experience with organized settings
    • All settings in one place with clear categorization
    • Easy navigation between different setting categories
    • Consistent UI with tabbed interface
  - LEGACY: Old popup code kept for backward compatibility
    • Lines: 3947+ (legacy individual popups)
    • Can be safely removed in future versions

0.1.10 [Internal Build 251219.2230] - FX Display Settings Refactoring
  - REFACTORED: Unified FX label formatting with context-based settings
    • New: format_fx_label(raw_label, context) function supports 4 contexts
    • Contexts: "button", "tooltip", "status", "fxlist"
    • Lines: 1669-1721 (unified formatting function)
    • Legacy functions preserved for backward compatibility (1723-1730)
  - ADDED: Individual display settings for 4 different contexts
    • Button Display: Controls Preset/History button names
    • Tooltip Display: Controls hover info formatting
    • Status Display: Controls bottom status bar FX name
    • FX List Display: Controls Chain mode FX list formatting
    • Each context has 3 settings: show_type, show_vendor, use_alias
    • Total: 12 new settings variables (lines 1243-1259)
  - IMPROVED: Settings UI redesigned with 4 sections
    • Menu: Settings → Preset/History Display...
    • Section 1: Button Display (Preset/History Buttons)
    • Section 2: Tooltip Display (Hover Info)
    • Section 3: Status Display (Bottom Bar)
    • Section 4: FX Chain List Display (Chain Mode)
    • Lines: 3737-3837 (new settings popup)
  - FIXED: Status bar now supports show_type and show_vendor settings
    • Previous: Only formatted when use_alias = true
    • Now: Respects all 3 settings independently
    • Line: 1729 (uses unified format_fx_label function)
  - FIXED: FX Chain List now applies formatting
    • Previous: Displayed raw fx.name without formatting
    • Now: Uses format_fx_label(fx.name, "fxlist")
    • Line: 4382 (format FX names in chain list)
  - IMPROVED: Tooltip formatting now uses dedicated settings
    • Previous: Shared settings with buttons
    • Now: Independent tooltip_show_type, tooltip_show_vendor, tooltip_use_alias
    • Lines: 2358, 2374 (tooltip uses "tooltip" context)
  - REMOVED: Old preset_display_* settings (backward incompatible)
    • Replaced with new 4-context system
    • Settings reset to defaults on first run with new version
  - TECHNICAL: Updated save/load settings functions
    • Save: Lines 1328-1341 (12 new ExtState keys)
    • Load: Lines 1389-1402 (12 new settings with defaults)
  - EXAMPLE: Flexible display configuration
    • Button: Type=ON, Vendor=OFF, Alias=ON → "VST3: ProQ4"
    • Tooltip: Type=ON, Vendor=ON, Alias=ON → "VST3: ProQ4 (FabFilter)"
    • Status: Type=ON, Vendor=ON, Alias=OFF → "VST3: Pro-Q 4 (FabFilter)"
    • FX List: Type=OFF, Vendor=OFF, Alias=OFF → "Pro-Q 4"

0.1.9 [Internal Build 251219.2216] - Rename preset/history improvements
  - IMPROVED: Preset rename now pre-fills with formatted FX name (matches button display)
    • Previous: Focused mode showed raw FX name (e.g., "VST3: Pro-Q 4 (FabFilter)")
    • Now: Shows formatted name respecting Display Settings (e.g., "ProQ4" if using alias)
    • Lines: 4065-4080 (get current FX and apply format_fx_label_for_preset)
  - IMPROVED: Rename popup hint text now shows formatted FX name (consistent with button)
    • Previous: Hint showed raw FX name regardless of display settings
    • Now: Hint uses format_fx_label_for_preset() to match current display format
    • Line: 4464 (use formatted_name for hint text)
  - ADDED: History items now support right-click rename (same as presets)
    • New: Right-click context menu on history items with "Rename" option
    • Lines: 4140-4166 (history context menu implementation)
    • Pre-fills with formatted name for focused mode, track name for chain mode
  - ADDED: New rename_history_item() function for renaming history entries
    • Function: rename_history_item(idx, new_custom_name)
    • Lines: 2041-2080 (bidirectional sync between history and presets)
    • Syncs custom_name to matching saved presets automatically
  - ADDED: Bidirectional rename sync between presets and history
    • Rename preset → updates matching history items
    • Rename history → updates matching saved presets
    • Match criteria: track_guid + mode + (fx_index for focused, name for chain)
  - IMPROVED: Rename popup now dynamically shows "Preset Name" or "History Name"
    • Lines: 4441-4499 (unified popup for both preset and history)
    • Uses gui.rename_is_history flag to determine source and target
  - TECHNICAL: Added gui.rename_is_history flag to track rename source
    • Line: 1239 (initialization)
    • Set to false for preset rename (line 4101)
    • Set to true for history rename (line 4187)

0.1.8 [Internal Build 251219.1935] - Preset/History display alignment fix
  - Fixed: Preset/History header toggles align without stretching window width

0.1.7 [Internal Build 251219.1915] - Preset/History display alias mapping
  - Added: Preset/History display formatting now reads type/vendor/name from fx_alias.json when alias mode is enabled

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
    - Tools script (hsuanice_AudioSweet Preview Toggle.lua) updated to v251213.0336
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
    - Bind "hsuanice_AudioSweet Preview Toggle" for Preview (auto-detects Chain/Focused)
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
```
