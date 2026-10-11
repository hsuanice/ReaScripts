# hsuanice_AudioSweet Core.lua — Changelog

AudioSweet Core - Focused Track FX render via RGWH Core

History before 26.1011.2142 (moved out of the script header; last header version: `0.3.8`).

```text
0.3.8 [261011.1053]
  - ADDED: AS_RENDER_KEEP_GLUE_CUES (default 0) — single-item Render retains the source's
    existing Glue cues (passed to RGWH.core as args.cues.render_keep_glue; RGWH Core >= 0.3.12)

0.3.7 [261010.1616]
  - CHANGED: Glue grouping and single-item render now apply to item selection ONLY
    • Any Time Selection → original behaviour: glue all, TS decides the range, no render
    • (RGWH grouping flags are still forced to match during the glue call, so the
      "glue results left on the FX track" fix from 0.3.5 stays in effect)

0.3.6 [261010.1609]
  - ADDED: Single-item render option (AS_SINGLE_ITEM_RENDER, default 0)
    • Single-item units use RGWH Render (new take, older takes kept) instead of Glue
    • Applies with no TS, or TS == item; a partial TS is pre-split first, so it renders too
    • Multi-item units and TS-WINDOW paths still glue
    • Tail Seconds does not apply to Render (RGWH: tail is Glue-only)
    • Apply after Copy: FX is copied only to the take that was active before render,
      appended to its existing take FX (not cleared); other older takes are untouched

0.3.5 [261010.1545]
  - ADDED: Glue unit grouping option (item selection, no Time Selection)
    • AS_GLUE_GROUPING = all (default, legacy) / rgwh (follow RGWH GUI) / custom
    • custom reads AS_GLUE_SPLIT_AT_CROSSFADES (default 0) and AS_GLUE_MUTED_SEPARATE (default 1)
    • Units built via RGWH.utils.detect_units_from_selection(opts) (requires RGWH Core >= 0.3.10)
  - FIXED: Glue results sometimes left behind on the FX track
    • CAUSE: AudioSweet grouped units ignoring mute/crossfade, but RGWH Glue re-grouped them
      using its own GLUE_MUTED_SEPARATE (default ON) / GLUE_SPLIT_AT_CROSSFADES → one unit
      became several glued items, and only the first one was renamed and moved back
    • FIX: the resolved grouping is forced onto RGWH for the glue call (snapshot/restore)
    • FIX: every new item on the FX track after glue is now treated as output and moved back

0.3.4 [260212.1247]
  - FIXED: Items extending beyond time selection now pre-split at TS boundaries before processing
    • PROBLEM: When item selection > time selection, entire item moved to FX track →
      render processed full item → RGWH glue split at TS → only TS portion moved back →
      content outside TS lost on FX track
    • SOLUTION: Pre-split items at tsL and tsR before any processing
      (same approach as RGWH Core glue_by_ts_window_on_track, lines 2612-2649)
    • Split pieces outside TS deselected and remain intact on original track
    • Units rebuilt from selection after split → Core/GLUE receives TS-aligned items
    • Selection snapshot retaken after split for correct end-of-run restoration
    • After split, ts_equals_unit() returns true for trimmed items → Core/GLUE path (with handles)
    • TS-WINDOW[UNIT] path still handles items smaller than TS (silence padding, Pro Tools behavior)

0.3.3 [260209.2130]
  - FIXED: Debug log path on Windows (os.getenv("HOME") returns nil)
    • Added os.getenv("USERPROFILE") fallback for Windows

0.3.2 [260205.0458]
  - BUGFIX: Mono mode completely broken — always passed channel_mode="auto" to RGWH.core()
    • BUG: Both APPLY and CORE paths hardcoded channel_mode="auto" in RGWH.core() args
    • When user selected Mono, RGWH received "auto" → detected multi-ch → used preserve → wrong output
    • FIX: Pass actual channel_mode to RGWH — "mono" when mono, "auto" otherwise (let ExtState policy resolve)
  - BUGFIX: TARGET-track (CORE path) ExtState handshake still broken
    • BUG: CORE path still wrote empty MULTI_CHANNEL_POLICY (only APPLY path was fixed in v0.3.0)
    • FIX: CORE path now also writes "source_track" for TARGET-track policy
  - RENAMED: "SOURCE-target" → "TARGET-track" (clearer naming, no SOURCE/TARGET conflict)
    • Internal ExtState value "target_track" unchanged (already matches new name)
    • Updated all comments, logs, and changelog display names
  - REQUIRES: RGWH Core v0.3.0 [v260205.0409]+

0.3.1 [260205.0433]
  - BUGFIX: TARGET-track ExtState handshake broken after RGWH Core force_multi removal (APPLY path only)
    • BUG: Wrote empty MULTI_CHANNEL_POLICY → RGWH v0.3.0 defaults to preserve → adjusts FX track to item ch
    • Expected: TARGET-track should output FX track ch (not item ch)
    • FIX: TARGET-track now writes "source_track" to RGWH (on FX track, target ch = track ch)
  - IMPROVED: source_playback explicit odd channel handling in FX track pre-adjustment
    • Old: desired_apply_nchan = item_ch (REAPER silently rounds odd to even)
    • New: Odd multi ch (3,5,7...) → explicitly set item_ch+1 (even ceiling, matches RGWH hybrid logic)
  - REQUIRES: RGWH Core v0.3.0 [v260205.0409]+

0.3.0 [260104.2143]
  - CHANGED: Complete redesign of Multi-Channel Policy handling with TARGET-track support
  - ARCHITECTURE: Three policies with clear separation of concerns
    • SOURCE-playback: Adjust FX track to item playback channels, write "source_playback" ExtState to RGWH
    • SOURCE-track: Adjust FX track to source track channels, write "source_track" ExtState to RGWH
    • TARGET-track: Keep FX track channels as-is, write "source_track" ExtState (FX track ch = target ch)
  - IMPLEMENTATION: FX track channel adjustment strategy
    • Before RGWH.core() call: Snapshot FX track original channel count
    • SOURCE-playback: Set FX track to max(2, item_playback_channels)
    • SOURCE-track: Set FX track to source_track_channels
    • TARGET-track: No adjustment (keep FX track channels, e.g., 6ch for Atmos)
    • After RGWH.core() call: Restore FX track to original channel count
  - CHANGED: ExtState protocol updated for RGWH Core v0.3.0 compatibility
    • Write "RGWH"/"MULTI_CHANNEL_POLICY" = "source_playback" | "source_track" (TARGET-track → "source_track")
    • TARGET-track mode: Write "source_track" (on FX track, target ch = track ch)
  - IMPACT: Cleaner architecture, all three policies use unified source_track/source_playback protocol
  - REQUIRES: RGWH Core v0.3.0+ for Multi-Channel Policy ExtState support
  - BACKWARD COMPATIBLE: Existing behavior preserved when no policy set

0.2.3 [251226.0356]
  - CHANGED: Unified Multi-Channel Policy ExtState Protocol
    • BEFORE: Used hsuanice_AS.RGWH_PRESERVE_TRACK_CH = "0"/"1" (boolean handshake)
    • NOW: Uses RGWH.MULTI_CHANNEL_POLICY = "source_playback"/"source_track"/"target_track" (semantic protocol)
    • IMPACT: Shares same ExtState protocol as RGWH GUI (single source of truth)
    • Implementation: Lines 2094-2119, 2783-2796, 2822-2823 (unified SetProjExtState)
    • Backward compatible: RGWH Core v0.2.2c+ reads both protocols with fallback
  - REFACTORED: AudioSweet Core is now a pure RGWH wrapper (Phase 4)
    • apply_focused_fx_to_item() simplified from ~170 to ~50 lines
    • apply_focused_via_rgwh_render_new_take() removed (merged into unified apply)
    • All render/glue logic delegated to RGWH.core()
    • Removed duplicated channel mode detection (~70 lines)
    • Removed duplicated Multi-Channel Policy logic (~50 lines)
    • Removed direct REAPER action calls (40361/41993)
  - CHANGED: Unified apply flow
    • Single apply function handles both focused and chain modes
    • Channel mode detection moved to args preparation
    • Multi-Channel Policy previously via RGWH_PRESERVE_TRACK_CH handshake (now unified protocol)
  - FIXED: Multi-Channel Policy now works correctly in all execution paths
    • ROOT CAUSE: Action 41993 (Apply multichannel) uses TRACK channel count, not item channel count
    • SOLUTION: Temporarily adjust FX track channel count based on Multi-Channel Policy BEFORE apply
    • source_playback: Set FX track to item playback channels → apply → restore FX track
    • source_track: Set FX track to source track channels → apply → restore FX track
    • target_track: Keep FX track as-is (no adjustment needed)
    • TS-WINDOW[UNIT] path now snapshots source track channel count before glue (line 2467-2472)
    • Fixed output item retrieval in TS-WINDOW[UNIT] path (line 2508: use GetSelectedMediaItem)
    • Fixed CountTakes error when copying FX to non-active takes (use out_item instead of glued)
    • ExtState namespace corrected: "hsuanice_AS" (was incorrectly using "RGWH")
    • Implementation: lines 2051-2087 (FX track adjustment), 2128-2134 (FX track restore)
  - IMPACT: ~200 lines removed, cleaner architecture, single source of truth
  - NOTE: All Apply functionality now uses RGWH.core() API

0.2.2 [251225.2158]
  - REFACTORED: Removed duplicated unit detection logic
    • Removed build_units_from_selection() function (~47 lines of duplicated code)
    • Now uses RGWH.utils.detect_units_from_selection() (single source of truth)
    • Added format conversion: RGWH unit → AudioSweet unit (line 2516-2531)
      RGWH: {kind, members=[{it,L,R},...], start, finish, track}
      AS:   {track, items=[item,...], UL, UR}
    • Helper functions (project_epsilon, approx_eq, ranges_touch_or_overlap) retained for AudioSweet-specific use
  - CHANGED: Load RGWH Core early in main() to access utility functions
    • RGWH loaded at script start (line 2401) instead of per-unit (line 2750+)
    • Provides access to RGWH.utils API for unit detection
  - IMPACT: Cleaner codebase, maintains DRY principle, no functionality change
  - NOTE: Helper functions marked for future refactoring in v0.3.0

v0.2.0.0.1 (2025-12-23) [internal: v251223.2328]
  - CHANGED: Version bump to 0.2.0.0.1

v0.2.0 (2025-12-23) [internal: v251223.2256]
  - CHANGED: Version bump to 0.2.0 (public beta)

0v.1.9 (2025-12-23) [internal: v251223.2236]
  - CHANGED: Copy+Apply now reuses Apply flow, then copies target FX to non-active takes
    • Single/multi items share the same glue/apply path for stability
    • Copy+Apply no longer uses a separate glue→copy→render path
  - CHANGED: Copy+Apply FX copy targets the processed take channel count (min 2)
  - FIXED: TC embed offset by handle length in Apply flow
    • Use item-start-based TC (matches RGWH current mode)
  - DEBUG: Added TC embed logging for current/previous sources
  - NOTE: Do not override RGWH TC embed mode in Core/GLUE path

v0.1.8 (2025-12-23) [internal: v251223.1924]
  - ADDED: Copy+Apply flow (copy FX then render) with multi-item glue support
    • Copy step now enforces identity pin mappings for stable multichannel IO
    • Render uses track FX to match Apply results, then clears take FX on output
  - FIXED: Multi-Channel Policy handling for Copy+Apply (source/target policies)
  - CHANGED: RGWH TimeReference embed forced to "current" during runs
  - DEBUG: Added take FX IO tracing and safe handling for invalid item pointers

v0.1.7 (2025-12-22) [internal: v251222.1706]
  - ADDED: External undo control support for single undo operation
    • External callers (GUI/standalone scripts) can set EXTERNAL_UNDO_CONTROL="1" ExtState
    • When enabled, Core skips its internal Undo_BeginBlock/EndBlock
    • Allows GUI and standalone scripts to manage undo as single operation
    • Default: false (Core manages undo internally for backward compatibility)
    • Integration: AudioSweet GUI v0.1.24 and Run v0.1.1 both enable external undo control
  - CHANGED: Unified all processing to use Core/GLUE path (eliminates RGWH Render path)
    • Single-item units now use Core/GLUE instead of RGWH Render
    • GLUE mode produces single take (no old take preserved)
    • Fixes position issues that occurred with RGWH Render path
    • Multi-Channel Policy already implemented in Core/GLUE path (works immediately)
    • Consistent behavior across all unit sizes (single/multi-item)
    • RGWH Core's GLUE_SINGLE_ITEMS flag handles single-item glue correctly

v0.1.5 (2025-12-22) [internal: v251222.1622]
  - ADDED: Multi-Channel Policy support for Core/GLUE path (multi-item units)
    • Core/GLUE path now implements all three Multi-Channel Policy options
    • SOURCE-PLAYBACK: Match unit's max playback channels
    • SOURCE-TRACK: Match source track channel count (uses pre-move snapshot)
    • TARGET-TRACK: Respect FX track's current channel count
    • Policy applied before calling RGWH Core, via ExtState RGWH_PRESERVE_TRACK_CH
  - ADDED: RGWH Core integration via ExtState control
    • Sets RGWH_PRESERVE_TRACK_CH="0" to disable FX track restoration (Multi/Auto mode)
    • Sets RGWH_PRESERVE_TRACK_CH="1" to enable FX track restoration (Mono mode)
    • ExtState cleared after RGWH Core execution
    • Works with RGWH Core v0.1.1+ preserve_track_ch parameter
  - IMPROVED: RGWH Render path now correctly applies Multi-Channel Policy
    • Previously: RGWH Core restored FX track channel count, overriding policy
    • Now: Uses ExtState to tell RGWH Core not to restore when policy is active
    • Fixes single-item units producing incorrect channel counts

v0.1.4 (2025-12-22) [internal: v251222.1122]
  - FIXED: Core/GLUE path (multi-item units) source track protection
    • Added source track channel count snapshot BEFORE move to FX track
    • Added source track restore AFTER move back from FX track
    • Prevents REAPER auto-adjust from changing source track channel count
    • Affects per-unit path when unit has ≥2 items (uses Core/GLUE)
    • Debug log: "snapshot SOURCE track #N I_NCHAN=X (pre-move)"
    • Debug log: "restored SOURCE track #N I_NCHAN=X (post-move)"
    • Completes source track protection coverage for all execution paths

v0.1.3 (2025-12-22) [internal: v251222.1103]
  - FIXED: Multi-unit processing across tracks - SOURCE-TRACK policy now works correctly
    • TS-WINDOW[GLOBAL] path now snapshots ALL source track channel counts BEFORE glue operation
    • Previously: second unit read post-glue channel count (incorrect)
    • Now: all units use pre-glue snapshot (correct)
    • apply_focused_fx_to_item() accepts optional source_track_nchan_snapshot parameter
    • When snapshot provided, uses pre-glue value for SOURCE-TRACK policy calculation
    • Individual track restore skipped when using snapshot (batch restore at end instead)
    • Renamed variable to avoid confusion with FX track snapshot (main function line 1967)
    • Added detailed debug logging: "snapshot SOURCE track" vs "SNAPSHOT track" (FX track)
    • Debug logs now clearly distinguish SOURCE track operations from FX track operations

v0.1.2 (2025-12-22) [internal: v251222.1035]
  - ADDED: Multi-Channel Policy system with 3 options (Settings → Channel Mode)
    • SOURCE-PLAYBACK: Match item's actual playback channels (default, current behavior)
    • SOURCE-TRACK: Match source track channel count (RGWH/Pro Tools style)
    • TARGET-TRACK: Respect FX track's current channel count (passive mode)
    • Policy only applies when Channel Mode is explicitly set to "Multi"
    • Auto/Mono modes use SOURCE-PLAYBACK logic (default behavior)
    • Implemented in both TS-Window and RGWH Render paths
    • Reads policy from ExtState: AS_MULTI_CHANNEL_POLICY
    • Debug logging shows policy selection and resulting channel count
  - ADDED: Source track channel count protection
    • Snapshots source track I_NCHAN before moving items to FX track
    • Restores source track channel count after processing complete
    • Prevents REAPER auto-adjust from changing source track channel count
    • Essential for post-production workflows and project interchange (Pro Tools/Nuendo)
    • Implemented in both TS-Window and RGWH Render paths
  - ADDED: Debug file logging
    • All debug output now writes to ~/Desktop/AudioSweet_Core_Debug.log
    • Prevents console messages from being washed away by RGWH Core output
    • Helps troubleshooting when multiple cores are running

v0.1.1 (2025-12-21) [internal: v251221.2141]
  - ADDED: Track channel count restoration after execution
    • Snapshots track I_NCHAN at execution start (after FXmediaTrack is known)
    • Restores original channel count at all exit points (copy/apply/TS-window paths)
    • Prevents REAPER auto-expansion from persisting after processing
    • Works in both focused and chain modes
    • Helper function restore_track_nchan() for consistent restoration
v0.1.0 (2025-10-30) - Initial Public Beta Release
  AudioSuite-like workflow with RGWH Core integration featuring:
  - Focused/Chain modes for Track FX processing
  - CLAP plugin support with fallback mechanism
  - Integration with AudioSweet ReaImGui v0.1.0-beta
  - File naming with FX Alias support
  - Handle-aware rendering via RGWH Core

Internal Build 251030.1630 - CRITICAL FIX
  • FIXED: checkSelectedFX() now supports OVERRIDE ExtState mechanism.
    - Issue: SAVED CHAINS/HISTORY execution showed "Please focus a Track FX" warning
    - Root cause: checkSelectedFX() only used GetFocusedFX(), which fails for CLAP and unfocused windows
    - Solution: Check OVERRIDE_TRACK_IDX and OVERRIDE_FX_IDX ExtState before GetFocusedFX()
    - Location: lines 1172-1191 (checkSelectedFX function)
    - OVERRIDE values are 0-based, converted to 1-based for internal use
    - OVERRIDE values cleared after use (single-use mechanism)
    - Falls back to GetFocusedFX() when OVERRIDE not set
  • Integration: Required by AudioSweet ReaImGui v251030.1630+ for reliable SAVED CHAINS/HISTORY execution.
    - GUI sets OVERRIDE ExtState → Core checks OVERRIDE → bypasses focus detection
    - Enables execution without requiring actual FX window focus
    - Works with all plugin formats (CLAP, VST3, VST, AU)

Internal Build 251030.1600
  • Fixed: Chain mode now works without focused FX (CLAP plugin support).
    - Issue: Core required GetFocusedFX() to return 1 even in chain mode
    - Solution: Added fallback to first selected track when focus detection fails in chain mode
    - Logic: if ret_val ~= 1 AND mode == "chain" then use GetSelectedTrack(0, 0)
    - Location: lines 1725-1734 (main function)
    - Works with CLAP, VST3, VST, AU plugins
  • Integration: Works with AudioSweet GUI v251030.1515 (OVERRIDE ExtState mechanism).

251030.0845
  • Changed: All file naming options now read from ExtState instead of hardcoded values.
    - AS_USE_ALIAS: Now reads from ExtState "hsuanice_AS/USE_ALIAS" (line 711)
      • Allows GUI to dynamically toggle FX alias usage
      • Default: false (disabled)
    - AS_MAX_FX_TOKENS: Now reads from ExtState "hsuanice_AS/AS_MAX_FX_TOKENS" (lines 415-419)
      • Controls FIFO cap for FX tokens in file names
      • Default: 3 tokens
    - AS_CHAIN_TOKEN_SOURCE: Now reads from ExtState "hsuanice_AS/AS_CHAIN_TOKEN_SOURCE" (lines 426-429)
      • Options: "track" (use track name), "aliases" (use FX aliases), "fxchain" (literal "FXChain")
      • Default: "track"
    - AS_CHAIN_ALIAS_JOINER: Now reads from ExtState "hsuanice_AS/AS_CHAIN_ALIAS_JOINER" (lines 433-435)
      • Separator when using aliases mode
      • Default: "" (empty, no separator)
    - SANITIZE_TOKEN_FOR_FILENAME: Now reads from ExtState "hsuanice_AS/SANITIZE_TOKEN_FOR_FILENAME" (lines 439-441)
      • Strip unsafe filename characters from tokens
      • Default: false
    - TRACKNAME_STRIP_SYMBOLS: Now reads from ExtState "hsuanice_AS/TRACKNAME_STRIP_SYMBOLS" (lines 446-449)
      • Strip all non-alphanumeric chars from track names (FX-like short name)
      • Default: true
  • Updated: All functions now call getter functions instead of using global constants.
    - sanitize_token() uses get_sanitize_token_for_filename() (line 613)
    - track_name_token() uses get_trackname_strip_symbols() (line 623)
    - build_chain_token() uses get_chain_token_source() and get_chain_alias_joiner() (lines 1002, 1021)
    - max_fx_tokens() uses get_max_fx_tokens() (line 1343)
  • Integration: AudioSweet GUI v251030.0845+ required for new naming settings.
    - GUI's "File Naming Settings" menu controls all these options
    - Settings automatically sync between GUI and Core via ExtState
    - Ensures consistent file naming behavior across all workflows

251029_1930
  • CRITICAL FIX: Changed all chanmode reads to use GetMediaItemTakeInfo_Value() instead of GetMediaItemInfo_Value()!
    - Root cause: Channel mode is stored on the TAKE, not the ITEM
    - Wrong API: GetMediaItemInfo_Value(item, "I_CHANMODE") always returns 0
    - Correct API: GetMediaItemTakeInfo_Value(take, "I_CHANMODE") returns actual channel mode
    - This explains why auto mode was always detecting as multi (chanmode was always read as 0=normal)
  • Updated: get_item_channels() now gets take first, then reads chanmode from take
  • Updated: All snapshot/debug code now reads from take instead of item
  • Verified: Now matches RGWH Monitor's channel mode detection logic

251029_1330
  • Fixed: Auto channel mode now correctly preserves item's original chanmode before moving to FX track.
    - Critical fix: MoveMediaItemToTrack() resets I_CHANMODE to 0 (normal)!
    - Solution: Snapshot orig_chanmode BEFORE moving, then use it for auto detection
    - Affects: apply_focused_via_rgwh_render_new_take() and apply_focused_fx_to_item()
  • Changed: Debug output now shows "orig_chanmode" to clarify it's the pre-move value
  • Verified: Now correctly detects chanmode=2/3/4 items as mono even after track move

251029_1300
  • Changed: Auto channel mode now uses item's playback channel count instead of source channel count.
    - Respects item's channel mode setting (mono/stereo/multichannel)
    - Handles cases where source is 8ch but item plays only 1ch or 2ch
    - Example: 8ch source with "left only" item mode → auto detects as mono
  • Added: get_item_channels() now checks I_CHANMODE to determine actual playback channels
    - chanmode 2/3/4 (downmix/left/right) → returns 1 (mono)
    - chanmode 0/1/5+ (normal/reverse/multi) → returns source channels
  • Added: Detailed debug logging showing source_ch, item_ch, and chanmode for troubleshooting
  • All paths (RGWH Render, TS-Window, Core/GLUE) now use consistent item-based channel detection

251029_1245
  • Fixed: Channel Mode (mono/multi/auto) from GUI now works correctly across ALL execution paths.
    - RGWH Render path (single items): Now reads AS_APPLY_FX_MODE ExtState instead of hardcoded "auto"
    - TS-Window path (TS glue): Now reads AS_APPLY_FX_MODE ExtState to override item channel auto-detection
    - Core/GLUE path (multiple items): Already working (verified)
  • Added debug logging to show which channel mode is being used and why
  • Root cause: apply_focused_via_rgwh_render_new_take() and apply_focused_fx_to_item()
    were not reading the GUI's AS_APPLY_FX_MODE ExtState setting

251028_2300
  • Verified: FX name formatting with alias functionality working correctly.
    - Test results confirm proper ExtState integration:
      • All options ON: "AU: Pro-Q 4 (FabFilter)" → "AUProQ4FabFilter"
      • Strip symbol OFF: "AU: Pro-Q 4 (FabFilter)" → "AU: ProQ4"
      • Console output shows correct formatting in both [AS][STEP] FOCUSED-FX name and [AS][NAME] after
    - Real-world validation:
      • First test: name='AUProQ4FabFilter', after='...-AS1-AUProQ4FabFilter' ✓
      • Second test: name='AU: ProQ4', after='...-AS1-AU: ProQ4' ✓
    - Confirms that format_fx_label() correctly applies ExtState options even when fx_alias exists.
  • Status: Ready for production use with AudioSweet GUI v251028_2245.

251028_2250
  • Fixed: FX name formatting options now apply even when fx_alias is used.
    - Previous: If fx_alias.json contained an alias (e.g., "ProQ4" for "Pro-Q 4"),
      format_fx_label() would return the alias immediately, ignoring ExtState settings
      for show_type/show_vendor/strip_symbol.
    - Now: format_fx_label() always respects ExtState formatting options:
      • FXNAME_SHOW_TYPE=1 → adds plugin type prefix (AU:, CLAP:, VST3:, VST:)
      • FXNAME_SHOW_VENDOR=1 → adds vendor name in parentheses
      • FXNAME_STRIP_SYMBOL=1 → removes spaces and symbols
    - Implementation: Lines 606-635
      • Gets formatting options first (line 608)
      • Checks for alias (line 611-612)
      • Uses alias as base_name if exists, otherwise uses parsed core (line 618)
      • Applies formatting options to final result (lines 622-633)
    - Result: With all options enabled, "AU: Pro-Q 4 (FabFilter)" → "AU:ProQ4FabFilter"
      instead of just "ProQ4"
  • Integration: Works with AudioSweet GUI → Settings → FX Name Formatting...

251028_2011
  • Changed: Naming debug output now controlled by ExtState instead of hardcoded constant.
    - Removed hardcoded `AS_DEBUG_NAMING = true` (line 354).
    - `debug_naming_enabled()` now reads from ExtState: `hsuanice_AS/DEBUG`.
    - When DEBUG="0" or empty: No console output, no window popup.
    - When DEBUG="1": Shows [AS][NAME] before/after renaming messages.
  • Integration: Fully compatible with AudioSweet GUI debug toggle.
  • Impact: Users can now control all console output via single debug switch.
    - GUI Menu: Debug → Enable Debug Mode
    - ExtState: `reaper.SetExtState("hsuanice_AS", "DEBUG", "1", false)`
  • Tech: Lines 352-356 modified for ExtState integration.

251022_1716
  • Changed: All Chinese comments replaced with English for public beta release.
    - Replaced ~70 lines of Chinese inline comments after line 320.
    - Covers: alias system, FX parsing, main flow, TS-Window, Core/GLUE, RGWH Render logic.
  • Tech: Ready for public beta distribution with full English documentation.

251022_1638
  • Fixed: Function definition order for build_chain_token().
    - Moved build_chain_token() after format_fx_label() and fx_alias_for_raw_label() definitions.
    - Resolves "attempt to call a nil value (global 'format_fx_label')" error when using AS_CHAIN_TOKEN_SOURCE = "aliases".
    - Now all three chain token modes work correctly: "track", "aliases", "fxchain".
  • Tech: Chain token modes verified with comprehensive testing:
    - "track" mode: uses track name (e.g., "-AS1-AudioSweet")
    - "aliases" mode: uses FX alias list (e.g., "-AS1-ProR2ProQ4")
    - "fxchain" mode: uses literal "FXChain" (e.g., "-AS1-FXChain")

251021_2145
  - Fixed: Multi-item glue path now uses new RGWH Core M.core() API instead of deprecated apply()
  - Changed: Core API detection now looks for M.core() or M.glue_selection() instead of old M.apply()
  - Changed: Multi-item glue args updated to new API format: {op="glue", channel_mode=..., take_fx=true, track_fx=true}
  - Tech: Resolves "RGWH.apply not found" error when processing multi-item units (touching/overlapping items)
  - Note: Single-item path already used M.render_selection() and is unaffected

251021_2130
  - Added: Chain mode naming support - take names now reflect the full FX chain or track name.
  - Added: New user options for chain token generation:
      • AS_CHAIN_TOKEN_SOURCE: "track" (use track name), "aliases" (list FX aliases), or "fxchain" (literal "FXChain")
      • AS_CHAIN_ALIAS_JOINER: separator when using aliases mode (default: empty string)
      • TRACKNAME_STRIP_SYMBOLS: strip non-alphanumeric chars from track names (FX-style short name)
      • SANITIZE_TOKEN_FOR_FILENAME: sanitize tokens for safe filenames
  - Added: Helper functions: sanitize_token(), track_name_token(), build_chain_token()
  - Changed: Main function now determines naming token based on AS_MODE:
      • Focused mode: uses focused FX name (e.g., "-AS1-ProR2")
      • Chain mode: uses chain token (e.g., "-AS1-AudioSweet" or "-AS1-ProR2ProQ4ProR2ProQ4")
  - Changed: All append_fx_to_take_name() calls now use dynamic naming_token instead of static FXName
  - Tech: Integrated chain token logic from AudioSweet Chain script into Core for unified behavior
  - Example: Chain mode with track "AudioSweet" → "TakeName-AS1-AudioSweet"
  - Example: Chain mode with aliases (no joiner) → "TakeName-AS1-ProR2ProQ4ProR2ProQ4"

251009_2249
  - Fixed: Single-item (non TS-Window) path no longer forces all FX enabled after render.
    It now relies solely on snapshot/restore so original bypass/offline states are preserved.
  - Note: TS-Window paths already used helper-level snapshot/restore and needed no changes.

251009_2238
  - Fixed: Restore original Track FX enable/bypass states after both single-item RGWH render and multi-item Core/GLUE paths (snapshot → restore).
  - Changed: Replaced “enable all FX on exit” with precise state restore to preserve user’s original bypass/offline setup.
  - Note: No peaks rebuild calls remain in this script (faster post-render).

251009_2215
  - Changed: Single-item path now calls RGWH Core via positional API:
             M.render_selection(1, 1, "auto", "current") to print both Take FX
             and Track FX into a NEW take (keeps previous takes).
  - Tech: Module variable renamed to `M` (from `RGWH`) to match Core return value.

v251009_2000
  - Changed: In non–TS-Window path, single-item units now use RGWH Render
             to create a NEW take (keeping previous takes), while multi-item
             units still use Core/GLUE with handles.
  - Added: Helper apply_focused_via_rgwh_render_new_take() to move the item
           to the FX track, isolate the focused FX, call RGWH.render_selection
           (TAKE_FX=1, TRACK_FX=1, APPLY_MODE=auto, TC=current),
           rename with AS token, and move back.
  - Unchanged: TS-Window (GLOBAL/UNIT) keeps the 42432→40361/41993 path
               (no handles), preserving the previous UX and behavior.
  - Notes: Naming, alias, and FIFO token cap remain intact; selection is
           restored at the end as before.

v251008_1838 (2025-10-08, GMT+8)
  - Added: Full FX alias integration with TSV fallback when JSON decoder is missing.
  - Fixed: Numeric-only FX aliases (e.g., “1176”, “1073”) are now correctly preserved.
  - Fixed: Sequential same-FX renders now append properly and respect FIFO cap,
           removing old tokens like “glued-xx” or “render-001”.
  - Improved: parse_as_tag() now pre-cleans legacy artifacts before tokenization,
              preventing ghost tokens such as “02” or “001”.
  - Result: Repeated FX passes stack correctly, e.g.
            “...-AS3-1073_1073_1073” and mixed passes as
            “...-AS4-1073_1073_VOXBOX”.
v251008_1837 — FX alias integration (JSON-driven short names)
  - Added: Full FX alias integration via TSV fallback when JSON decoder missing.
  - Fixed: Numeric-only FX aliases (e.g., “1176”, “1073”) are now preserved.
  - Fixed: Repeated same-FX passes now correctly append without residual tokens
           from “glued-xx” or “render-001” suffixes.
  - Improved: parse_as_tag() pre-cleans legacy artifacts before tokenizing,
              preventing ghost tokens like “02” or “001”.
  - Result: Sequential renders correctly stack as “...-AS3-1073_1073_1073” and
            mixed renders as “...-AS4-1073_1073_VOXBOX”.

v2510081815 — FX alias integration (JSON-driven short names)
  - Added: automatic FX short-name alias lookup for take naming.
  - Source: Settings/fx_alias.json (preferred) or fallback to fx_alias.tsv.
  - Supports both JSON object ({ fingerprint=alias }) and array forms.
  - Fallback: if JSON decoder is unavailable or file missing, loads TSV.
  - Detection: normalized keys "type|core|vendor", "type|core|", "|core|", etc.
  - Added: alias log tracing (AS_DEBUG_ALIAS) and TSV loader (_alias_map_from_tsv).
  - Improvement: alias normalization removes non-alphanumeric symbols.
  - Safety: fails gracefully with clear [ALIAS] console messages; never halts render.

v2510072312 — FX alias integration (JSON-driven short names)
  - New: AudioSweet now consults Settings/fx_alias.json for FX short names when composing the “-ASn-...” suffix.
  - Resolution order: "type|core|vendor" → "type|core|" → "|core|".
  - Fallback: if no alias is found (or JSON missing/invalid), revert to the existing formatter/options.
  - Toggle: set AS_USE_ALIAS at the top of the script (true/false).
  - Behavior: keeps FIFO cap (AS_MAX_FX_TOKENS), preserves order, allows duplicates by design.
  - Safety: lazy JSON load; gracefully tolerates absent/invalid file; no modal errors.
  - Logging: keeps [AS][NAME] before/after when AS_DEBUG_NAMING=true; no change to render pipeline.

v2510071447 — AS naming: allow duplicates, keep order (FIFO cap)
  - Stop de-duplicating FX tokens; every run appends the new FX to the end.
  - The AS_MAX_FX_TOKENS cap (user option) still trims from the oldest (FIFO).
  - Examples (cap=3):
      CHOU...-AS5-Volcano3_dxRevivePro_Saturn2
      + Volcano3 → CHOU...-AS6-dxRevivePro_Saturn2_Volcano3
      + Saturn2  → CHOU...-AS7-ProQ4_Volcano3_Saturn2   (if cap=3)

v2510071407 — AS naming: user-capped FX list (FIFO)
  - New user option at top of script: AS_MAX_FX_TOKENS
    * 0 or nil → unlimited (default)
    * N>0     → keep only the last N FX names in the “-ASn-...” suffix
  - Behavior: each run appends the new FX; if over the cap, drop the oldest tokens (FIFO).
  - Examples (cap=3):
      Take-AS4-Saturn2_ProQ4_ProR2
      + ProQ4   → Take-AS5-ProQ4_ProR2_ProQ4
      + Saturn2 → Take-AS6-ProR2_ProQ4_Saturn2

v2510062341 — AudioSweet concise AS naming (iteration-safe)
  - Simplified take-name scheme:
      BaseName-AS{n}-{FX1}_{FX2}_...
    (removed redundant “glued/render” suffixes and file extensions)
  - Automatically increments {n} when re-applying AudioSweet to the same take.
  - Merges previously appended FX names to avoid duplicate “-ASx-FX...” chains.
  - Removes legacy “glued-XX” / “render XXX/edX” fragments before composing.
  - Example:
      1st pass → TakeName-AS1-ProR2
      2nd pass → TakeName-AS2-ProR2_Saturn2
  - Refactored parser to detect and merge nested AS tags (“-ASx-...-ASy-...”)
    ensuring clean sequential numbering and deduplicated FX tokens.
  - Fix: strip glue/render artifacts when re-parsing existing AS tags
      (filters tokens: "glued", "render", pure numbers, "ed###", "dup###").
v2510062315 — AudioSweet take-naming (AS scheme)
  - Replace long “...glued... render...” suffix with concise scheme:
    BaseName-AS{n}-{FX1}_{FX2}_...
  - If the take already has AS-form, increment n and append the new FX.
  - Strip file extensions and any trailing " - Something".
  - Remove legacy “glued-XX” / “render XXX/edX” fragments before composing.
v2510060238 — FX name scheme (type/vendor toggle, strip symbols)
  - Added user options (via ExtState) for FX take-name postfix:
    • FXNAME_SHOW_TYPE=1 → include type prefix (e.g., “CLAP:” / “VST3:”).
    • FXNAME_SHOW_VENDOR=1 → include vendor in parentheses.
    • FXNAME_STRIP_SYMBOL=1 → remove spaces and non-alphanumeric symbols from the final label.
  - Introduced robust parser for REAPER FX labels (“TYPE: Name (Vendor)”), then recomposed per options.
  - Main now formats the focused FX label once (keeps raw in logs), downstream naming unchanged.

v2510042157 — TS-Window cross-track print + selection restore
  - TS-Window (GLOBAL): After 42432, now iterates each glued item **across tracks** and prints the focused FX per-item.
  - Channel-aware apply: per item chooses 40361 (mono, new take) or 41993 (multichannel); temporarily sets FX track I_NCHAN for ≥2ch and restores afterward.
  - Name handling: appends the focused FX name to the printed take (forward-declared helper to avoid nil-call errors).
  - Selection UX: snapshots your original selection at start and restores it at the very end, so you retain what you picked.
  - Logging: clearer TS-APPLY traces (moved→FX / applied cmd / post-apply selection) and extra dumps around 42432.

  Known issues
  - Razor selection: not supported yet (planned precedence Razor > Time Selection).
  - Non–TS-Window path still relies on RGWH Core; plugins with unusual I/O layouts (>2 outs, e.g., 5.0-only) may require manual pin routing.

v2510042113 — TS-Window cross-track print; forward-declare fix
  - TS-Window (GLOBAL): After 42432, iterate each glued item across tracks and print the focused FX per-item
    (handles channel-aware 40361/41993, restores I_NCHAN, renames, and moves back).
  - Fixed a Lua scoping bug: append_fx_to_take_name is now forward-declared, preventing
    “attempt to call a nil value (global 'append_fx_to_take_name')”.
  - Logs: clearer TS-APPLY traces (moved→FX / applied cmd / post-apply selection dump).

  Known issues
  - Razor selection is not yet supported (planned: Razor > Time Selection precedence).
  - Non–TS-Window path still relies on RGWH Core; plugin I/O edge cases (>2-out mappers) may require pin tweaks.

v2510042033 — Harden I_NCHAN read to avoid nil compare
  - TS-Window (GLOBAL/UNIT): Wrap I_NCHAN reads with tonumber(...) to avoid `attempt to compare nil with number`.
  - No behavior change other than crash-proofing; logging unchanged.

v2510041957 — TS-Window channel-aware apply; mono/stereo logic fixed
  - TS-Window (GLOBAL/UNIT): Per-item channel detection now works for both single-track and mixed material on the same track.
  - Mono (1ch) sources use 40361 “Apply track FX to items as new take” so a new take is created; track channel count is not changed.
  - ≥2-channel sources set the FX track I_NCHAN to the nearest even ≥ source channels, then use 41993 (multichannel output).
  - Restores the FX track channel count after apply and appends the focused FX name to the new take.
  - Stability: added guards to avoid nil/number comparisons while resolving channel/track fields; clearer logs around 42432 and post-apply.

  Known issues
  - TS-Window cross-track printing: Printing the focused FX across multiple tracks is not yet supported. Current build can glue across tracks, but the focused-FX print step only runs when the window resolves to a single unit on one track.
  - Non–TS-Window path still processes only the first unit per run (documented limitation).
  - Plugins with restricted I/O layouts (e.g., 5.0-only) may still require manual pin/routing adjustments.

v2510041931 (TS-Window mono path → 40361 as new take)
  - TS-Window (GLOBAL/UNIT): For mono (1ch) sources, use 40361 “Apply track FX to items as new take” so a new take is created; do not touch I_NCHAN.
  - TS-Window (GLOBAL/UNIT): For ≥2ch sources, set FX track I_NCHAN to the nearest even ≥ source channels and use 41993 (multichannel output).
  - Fixes the issue where mono path used 40631 and did not create a new take (name postfix appeared on take #1).

v2510041808 (unit-wide auto channel for Core glue; fix TS-Window unit n-chan set)
  - Core/GLUE: Auto channel detection now scans the entire unit and uses the maximum channel count to decide mono/multi; no longer depends on an anchor item.
  - TS-Window (UNIT): Before 40361, set the FX track I_NCHAN to the desired_nchan derived from the glued source; restore prev_nchan afterwards.
  - All other behavior and debug output remain unchanged.

v2510041421 (drop buffered debug; direct console logging)
  - Removed LOG_BUF/buf_push/buf_dump/buf_step; all debug now prints directly via log_step/dbg_* helpers.
  - Switched post-move range dump to dbg_track_items_in_range(); removed re-dump step (Core no longer clears console).
  - Kept all existing debug granularity; behavior unchanged.

v2510041339 (fix misuse of glue_single_items argument)
  - Corrected the `glue_single_items` argument in the Core call to `false` for multi-item glue scenarios.
  - Ensures that when multiple items are selected and glued, they are treated as a single unit rather than individually.
  - No other changes to functionality or behavior.

v2510041145  (fix item unit selection after move to FX track)
  - Non–TS-Window path: preserve full unit selection after moving items to FX track (no longer anchor-only).
  - Core handoff: keep GLUE_SINGLE_ITEMS=1（unit glue even for single-item）；do not pass glue_single_items in args（avoid ambiguity）.
  - Logging: clearer unit dumps and pre-apply selection counts to verify unit integrity before Core apply.
  - Stability: ensure FX-track bypass restore and item return-to-original-track even on partial failures.

Known limitation
  - Non–TS-Window mode still processes only the **first** unit per run (guarded by processed_core_once).
    To process all units, remove the guard that skips subsequent units and the assignment that sets it to true.

v251002_2223  (stabilize multi-item in TS-Window; single-item in non-TS)
  - TS-Window (GLOBAL/UNIT) path: added detailed console tracing (pre/post 42432, post 40361, item moves).
  - Per-unit (Core) path: when not in TS-Window, now processes only the first item (anchor) as single-item glue.
  - Focused-FX isolation: keep non-focused FX bypassed on the FX track during apply, then restore.
  - Safety: stronger MediaItem validation when moving items between tracks; clearer error messages.
  - Logging: unit dumps, selection snapshots, track range scans for easier root-cause analysis.

Known limitation
  - In non–TS-Window mode, **multi-item selection (multiple item units)** is **not supported** in this build:
    only the first item (anchor) is glued/printed via Core; other selected items are ignored.

v251002_1447  (multi-item glue, TS-window no handles)
  - Multi-item selection via unit-based grouping (same-track touching/overlap/crossfade merged as one unit).
  - Unified glue-first pipeline: Unit → GLUE (handles + take FX by Core when TS==unit or no-TS) → Print focused Track FX.
  - TS-Window mode (TS ≠ unit or TS hits ≥2 units): no handles (Pro Tools behavior) — run 42432 then 40361 per glued item.
  - Core handoff uses unit scope (SELECTION_SCOPE=unit, GLUE_SINGLE_ITEMS=0) and auto apply_fx_mode by source channels.
  - Logging toggle via ExtState hsuanice_AS/DEBUG; add [AS][STEP] markers for each phase; early-abort with clear messages.
  - Peaks rebuild skipped by default to save time (REAPER will background-build as needed).
  - Note: Multichannel routing (>2-out utilities) unchanged in this build; to be handled in a later pass.

v20251001_1351  (TS-Window mode with mono/multi auto-detect)
  - TS-Window behavior refined: strictly treat Time Selection ≠ unit as “window” — no handle content is included.
  - Strict unit match: replaced loose check with sample-accurate (epsilon = 1 sample) start/end equality.
  - When TS == unit: removed 41385 padding step; defer entirely to RGWH Core (handles managed by Core).
  - TS-Window path: keeps 42432 (Glue within TS, silent padding, no handles) → 40361 (print only focused Track FX).
  - Mono/Multi auto in TS-Window: set FX-track channel count by source take channels before 40361, then restore.
  - Post-op flow unchanged: in-place rename with “ - <FX raw name>”, move back to original track, 40441 peaks.
  - Focused FX index handling and isolation maintained (strip 0x1000000; bypass non-focused FX).
  - Stability: clearer failure messages and early aborts; no fallback paths.
  Known notes
  - If the focused plugin does not support all source channels (e.g., 5.0 only), unaffected channels may need routing/pins.

v20251001_1336  (TS-Window mode with mono/multi auto-detect)
  - TS-Window mode: when Time Selection ≠ RGWH “item unit”, run 42432 (Glue within TS, silent padding, no handles),
    then print only the focused Track FX via 40361 as a new take, append FX full name, move back, and rebuild peaks.
  - Auto channel for TS-Window: before 40361, auto-resolve desired track channels by source take channels
    (1ch→set track to 2ch; ≥2ch→set track to nearest even ≥ source ch), restore track channel count afterwards.
  - Unit-matched path unchanged: when TS == unit, keep RGWH Core path (GLUE; handles managed by Core; auto channel via Core).
  - Focused FX handling: normalized focused index (strip 0x1000000 floating-window flag) and isolate only the focused Track FX.
  - Post-op flow: reacquire processed item, in-place rename (“ - <FX raw name>”), return to original track, 40441 peaks.
  - Failure handling: clear modal alerts and early aborts (no fallback) on Core load/apply or TS glue failure.

  Known notes
  - Multichannel routing that relies on >2-out utility FX (mappers/routers) remains bypassed in focused-only mode;
    if a plugin is limited to e.g. 5.0 I/O, extra channels may need routing/pin adjustments (to be addressed separately).
v20251001_1312  (glue fx with time selection)
  - Added TS-Window mode (Pro Tools-like): when Time Selection doesn’t match the RGWH “item unit”, the script now
    1) runs native 42432 “Glue items within time selection” (silent padding, no handles), then
    2) prints only the focused Track FX via 40361 as a new take, appends FX full name, moves back, and rebuilds peaks.
  - Kept unit-matched path unchanged: when TS == unit, continue using RGWH Core (GLUE with handles by Core).
  - Hardened focused FX isolation and consistent index normalization (strip 0x1000000).
  - Robust post-op selection flow: reacquire the processed item, in-place rename, return to original track, 40441 peaks.
  - Clear aborts with message boxes on failure; no fallback.

  Known issue
  - In TS-Window mode, printing with 40361 follows the track’s channel layout and focused FX I/O. This can result in mono/stereo-only output and ignore source channel count (“auto” detection not applied here). Workarounds for now:
    • Ensure the track channel count matches the source channels before 40361, or
    • Keep routing utilities (>2-out channel mappers) enabled, or
    • Use the Core path (TS == unit) where auto channel mode is respected.
v20251001_0330
  - Auto channel mode: resolve "auto" by source channels before calling Core (1ch→mono, ≥2ch→multi); prevents unintended mono downmix in GLUE.
  - Core integration: write RGWH *project* ExtState for GLUE/RENDER (…_TAKE_FX, …_TRACK_FX, …_APPLY_MODE), with snapshot/restore around apply.
  - Focused FX targeting: normalize index (strip 0x1000000 floating-window flag); Track FX only.
  - Post-Core handoff: reacquire processed item, rename in place with " - <FX raw name>", then move back to original track.
  - Refresh: replace nudge with `Peaks: Rebuild peaks for selected items` (40441) on the processed item.
  - Error handling: modal alerts for Core load/apply failures; abort without fallback.
  - Cleanup: removed crop-to-new-take path; reduced global variable leakage; loop hygiene & minor logging polish.

v20250930_1754
  - Switched render engine to RGWH Core: call `RGWH.apply()` instead of native 40361.
  - Pro Tools–like default: GLUE mode with TAKE FX=1 and TRACK FX=1; handles fully managed by Core.
  - Focused FX targeting hardened: mask floating-window flag (0x1000000); Track FX only.
  - Post-Core handoff: re-acquire processed item from current selection; rename in place; move back to original track.
  - Naming: append raw focused FX label to take name (" - <FX raw name>"); avoids trailing dash when FX name is empty.
  - Refresh: replaced nudge trick with `Peaks: Rebuild peaks for selected items` (40441).
  - Error handling: message boxes for Core load/apply failures; no fallback path (explicit abort).
  - Cleanups: removed crop-to-new-take step; reduced global variable leakage; minor loop hygiene.
  - Config via ExtState (hsuanice_AS): `AS_MODE` (glue|render), `AS_TAKE_FX`, `AS_TRACK_FX`, `AS_APPLY_FX_MODE` (auto|mono|multi).

v20250929
  - Initial integration with RGWH Core
  - FX focus: robust (mask floating flag), Track FX only
  - Refresh: Peaks → Rebuild peaks for selected items (40441)
  - Naming: append " - <FX raw name>" after Core’s render naming
```
