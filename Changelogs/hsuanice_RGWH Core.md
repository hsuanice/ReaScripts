# hsuanice_RGWH Core.lua — Changelog

RGWH Core - Core Library of Render or Glue with Handles

History before 26.1011.2142 (moved out of the script header; last header version: `0.3.13`).

```text
0.3.13 [261011.1106] - FIX: Glue with Time Selection lost its handles when grouping options were on
  - CAUSE: with a TS (≈ selection → Units glue), GLUE_SPLIT_AT_CROSSFADES / GLUE_MUTED_SEPARATE
    still split a crossfading/touching run into several units; "multiple units + TS" then
    merged them into one GAP unit glued to the TS span with NO handles
  - FIX: with a TS, Units glue ignores both grouping options (legacy grouping), as the GUI
    tooltip already stated → the run stays one unit and gets its handles
  - Real gaps between units + TS still use the GAP path as before

0.3.12 [261011.1052] - ADDED: RENDER_KEEP_GLUE_CUES (default 0) — Render retains existing Glue cues
  - Before rendering, the "Glue:" cues already in the take's source file are read
    (SWS CF_EnumMediaSourceCues), mapped to project time (position / offset / playrate)
    and re-written as temporary "#Glue: <name>" markers inside the render window
    (incl. handles) → embedded into the new take, then removed
  - Only Glue cues are carried; #in/#out are written fresh as before
  - M.core(): args.cues.render_keep_glue overrides it for one run
  - Requires SWS; without it the option is skipped (logged)

0.3.11 [261011.1038] - FIX: muted unit lost its content when glued (item selection)
  - CAUSE: REAPER Glue / Apply (40361/41993/40209) can render muted items as silence
    (seen with a single muted item, and whenever Track FX are printed)
  - FIX: with GLUE_MUTED_SEPARATE on and NO Time Selection, the members of an all-muted
    unit are unmuted before Glue, and the final glued item is muted again afterwards
    → content + FX printed, item stays muted
  - cfg.ITEM_SELECTION_RUN set by glue_selection (Units, no TS) and auto_selection (no TS)
  - Render: with NO Time Selection, a muted item is unmuted for the render and muted
    again afterwards (independent of GLUE_MUTED_SEPARATE — a single item is its own unit)
  - Time Selection paths unchanged

0.3.10 [261010.1545] - ADDED: M.utils.detect_units_from_selection(opts)
  - Accepts optional opts {split_at_crossfades, muted_separate}, forwarded to detect_units_same_track()
  - No opts → unchanged legacy grouping (backward compatible)
  - PURPOSE: lets AudioSweet Core group units with the same rules RGWH Glue will use

0.3.9 [260330.1415] - FIX: GLUE_MUTED_SEPARATE — muted items now group with other muted items
  - BUG: muted items were always forced to SINGLE units, even when adjacent to other muted items
  - FIX: detect_units_same_track() now breaks only at muted/non-muted boundaries, not at every muted item
    • Muted items can now form TOUCH/CROSSFADE/MIXED units with other muted items
    • The unit chain only breaks when mute state changes between adjacent items

0.3.8 [260330.1354] - ADDED: Glue unit grouping options — muted_separate and split_at_crossfades
  - NEW: GLUE_MUTED_SEPARATE (default: true) — muted items always form their own SINGLE unit;
    a muted item breaks the chain on both sides (items before/after are separate units).
  - NEW: GLUE_SPLIT_AT_CROSSFADES (default: false) — crossfading items are not grouped into the
    same unit; only touching items share a unit.
  - detect_units_same_track() now accepts optional opts table: {split_at_crossfades, muted_separate}
  - Both flags are read from ExtState and exposed via GUI (RGWH ReaImGui >= 0.2.6).
  - Both flags affect Glue and Auto paths only; Render path is unaffected.
  - When a Time Selection is active, the TS-Window path is used instead and opts have no effect.

0.3.7 [260328.0408] - ADDED: Tail Seconds — FX decay extension independent of handles
  - NEW: TAIL_SECONDS setting (default 0.0): extends the processed item beyond the right handle,
    into silence, to capture reverb/delay/echo decay naturally.
  - Tail is NOT clamped to source length — item extends into silence (REAPER pads with zeros).
  - Tail is always additive: finalR = gotR + TAIL (stacks on top of Right handle, not replacing it).
  - Glue path only: UR window and final item length extended by TAIL on last member.
    • Render intentionally ignores TAIL (tail is Glue-only by design).
  - per_member_window_lr() now accepts tail param; returns finalR and tailH in result table.
  - M.core() API: handle = { ..., tail=N } sets TAIL_SECONDS for a one-run override.
  - DEFAULTS.TAIL_SECONDS = 0.0 (fully backward-compatible; no behaviour change when not set).

0.3.6 [260207.1717] - FIX: Multi-track Glue with TS now processes all tracks correctly
  - BUG: When gluing multiple tracks with Time Selection, only Track #1 was processed as GAP unit
    • Track #2+ were incorrectly treated as "no TS" mode (individual units with handles)
  - ROOT CAUSE: get_current_ts() was called INSIDE the per-track loop
    • After Track #1's GAP unit was processed, TS was cleared (line 2252)
    • Subsequent tracks saw hasTS=false
  - FIX: Capture TS state BEFORE the track loop starts
    • capturedTsL, capturedTsR, capturedHasTS = get_current_ts()
    • All tracks now use the captured values instead of re-querying

0.3.5 [260205.0409] - REMOVE: force_multi / no_trackfx_output_policy settings (redundant with MULTI_CHANNEL_POLICY)
  - REMOVED: GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX and RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX settings
    • These settings ("preserve" | "force_multi") are now fully replaced by MULTI_CHANNEL_POLICY
    • source_track = old force_multi (Apply after Glue to force track ch)
    • source_playback = old preserve (Glue natively preserves playback ch, skip Apply)
  - SIMPLIFIED: Glue path condition — 3 locations (GAP unit, main unit, TS-Window)
    • Old: (multi or preserve) AND force_multi policy → Apply
    • New: unit_apply_mode == "multi" → Apply (source_track needs it; source_playback skips)
  - SIMPLIFIED: Render path — merged force_multi + need_apply_for_multichannel into need_multichannel
    • Multi/preserve modes always use Apply for correct channel control (40601 can't preserve multi-ch)
  - REMOVED: DEFAULTS, read_settings(), snapshot/restore, one-run overrides for the two policies
  - REMOVED: API args.policies.glue_no_trackfx_output_policy / render_no_trackfx_output_policy
  - GUI: Removed Glue/Render No-TrackFX Policy combos, persist keys, sync, labels, debug output
  - REASON: Reduces UI complexity — one setting (MULTI_CHANNEL_POLICY) controls all channel behavior

0.3.4 [260205.0144] - REFACTOR: preserve mode hybrid command — 41993 default + 40209 for odd ch
  - CHANGE: SOURCE-playback (preserve) no longer uses 40209 exclusively
    • Even ch (2,4,6...) and mono: 41993 + set track ch = target (deterministic, no FX Pin interference)
    • Odd multi ch (3,5,7...): 40209 + set track ch = item_ch+1 as ceiling (preserves exact odd ch)
  - REASON: 40209 is affected by Take FX Pin Connector (can expand output unpredictably)
    • 41993 output = track ch (100% deterministic, ignores FX Pin)
    • 40209 only needed for odd ch since REAPER track ch is always even
  - UPDATED: apply_track_take_fx_to_item_with_policy() — hybrid preserve_cmd logic
  - UPDATED: apply_multichannel_no_fx_preserve_take() — same hybrid logic
  - UPDATED: get_apply_cmd() comments to note hybrid approach
  - LOGGING: Now logs actual command ID in run_command for easier debugging
  - IMPACT: All 4 FX quadrants × Render/Glue paths benefit from deterministic channel control

0.3.3 [260205.0023] - BUGFIX: preserve mode track ch adjustment was expand-only (not bidirectional)
  - BUG: apply_track_take_fx_to_item_with_policy() only expanded track ch when item_ch > track_ch
    • 40209 uses track I_NCHAN as ceiling → items on wider tracks output at track ch, not item ch
    • e.g., 2ch item on 4ch track → output 4ch (wrong), should be 2ch
    • e.g., 4ch item on 6ch track → output 6ch (wrong), should be 4ch
  - FIXED: Bidirectional track ch adjustment for preserve mode
    • Now adjusts track ch to match item ch in BOTH directions (expand AND shrink)
    • Enforces 2ch floor (40209 REAPER limit) and even channel count
  - FIXED: Same bug in apply_multichannel_no_fx_preserve_take() (Glue no-FX path)
    • Applied identical bidirectional adjustment logic
  - IMPACT: SOURCE-playback now correctly preserves item ch on tracks wider than source

0.3.2 [260204.2032] - BUGFIX: Glue path ignoring SOURCE-playback (preserve) policy
  - FIXED: apply_multichannel_no_fx_preserve_take() always used ACT_APPLY_MULTI (41993)
    • Added apply_mode parameter (5th arg, default "multi" for backward compatibility)
    • Now uses get_apply_cmd(apply_mode) to select correct action per policy
    • preserve mode: uses 40209, expands track ch to match item ch (40209 has 2ch floor)
    • multi mode: uses 41993 (existing behavior, unchanged)
  - FIXED: TS-Window glue path condition only checked unit_apply_mode == "multi"
    • Added "preserve" to condition so preserve mode enters the no-Track-FX apply branch
  - UPDATED: All 3 callers now pass unit_apply_mode as 5th argument
    • GAP unit path (line ~2174)
    • Main glue_unit path (line ~2412)
    • TS-Window path (line ~2707)
  - FIXED: get_multi_channel_policy() captured retval instead of string value
    • Bug: local policy = r.GetProjExtState(...) → policy was always integer 1
    • Fix: local _, policy = r.GetProjExtState(...)
  - IMPACT: SOURCE-playback policy now works correctly for both Render and Glue paths

0.3.1 [260109.1430] - MULTI-CHANNEL POLICY: Track Channel Adjustment Implementation
  - IMPLEMENTED: Track channel adjustment for SOURCE-playback policy
    • New function: apply_track_take_fx_to_item_with_policy() - handles track ch snapshot/adjust/restore
    • SOURCE-playback (preserve mode): Temporarily expands track ch to match item ch before 40209
    • SOURCE-track (multi mode): Uses existing track ch with 41993 (no adjustment needed)
    • Prevents 40209's stereo floor (2ch minimum) by pre-adjusting track channels for >2ch items
    • ODD CHANNEL HANDLING: Rounds up to even (5ch→6ch) since REAPER enforces even track channel counts
  - UPDATED: All apply paths now use policy-aware track channel adjustment
    • apply_track_take_fx_to_item() - wraps new policy-aware function (glue flow uses this)
    • Render flow - updated to use apply_track_take_fx_to_item_with_policy() directly
    • Glue flow - automatically inherits via apply_track_take_fx_to_item()
  - BEHAVIOR: Based on command testing results (40209 vs 41993)
    • 40209 with Take FX: Respects Pin Connector, but has 2ch floor without track expansion
    • 40209 without Take FX: Has 2ch floor (output = max(2ch, min(FX_output, track_ch)))
    • 41993: Completely ignores FX Pin Connector, forces output = track_ch
  - LOGGING: New debug messages for policy-based track channel adjustments
    • "[POLICY] Track ch adjusted X→Y for SOURCE-playback (item has Ych)"
    • "[POLICY] Track ch X→Y during apply, restored to X"
  - IMPACT: SOURCE-playback policy now correctly preserves multi-channel items (4ch→4ch, 6ch→6ch, etc.)
  - VERIFIED: Track channel snapshot/restore mechanism tested and working correctly
  - READY: For user testing with actual multi-channel items and policies

0.3.0 [260105.0045] - CHANNEL MODE REDESIGN: Multi-Channel Policy Integration
  - CHANGED: Complete redesign of channel mode handling to utilize native REAPER commands optimally
  - ADDED: Multi-Channel Policy support for AUTO and MULTI channel modes
    • AUTO mode: Reads MULTI_CHANNEL_POLICY ExtState to decide between 40209 (preserve) and 41993 (match track)
    • MULTI mode: Two policies - "source_playback" (preserve multi-channel) and "source_track" (match track ch)
    • Policy ExtState: "RGWH"/"MULTI_CHANNEL_POLICY" = "source_playback" | "source_track" | ""
  - ADDED: New action constants for expanded channel mode support
    • ACT_APPLY_PRESERVE (40209): Apply track/take FX to items - preserves multi-channel (2ch→2ch, 4ch→4ch)
    • ACT_SET_MONO (40178): Set take channel mode to mono downmix - sets I_CHANMODE to downmix
  - OPTIMIZED: MONO mode 40178 usage (quadrant-based optimization)
    • quadrant 1,2 (no Track FX): Use 40178 → 40601/42432 (set I_CHANMODE for glue/render)
    • quadrant 3,4 (has Track FX): Skip 40178, use 40361 directly (already forces mono output)
    • REASON: 40361 inherently forces mono, no need to pre-set I_CHANMODE
  - CHANGED: apply_track_take_fx_to_item() now supports three modes
    • "mono": Uses 40361 (force mono)
    • "multi": Uses 41993 (match track channel count) - existing behavior
    • "preserve": NEW - Uses 40209 (preserve item multi-channel)
  - IMPLEMENTATION: New command selection logic based on FX quadrants
    • Quadrant 1 (Take❌ Track❌): 40601 (preserve source) or 40178→40601 (mono)
    • Quadrant 2 (Take✅ Track❌): 40601 (preserve source) or 40178→40601 (mono)
    • Quadrant 3 (Take❌ Track✅): 40361 (mono) / 40209 (preserve) / 41993 (match track) based on mode+policy
    • Quadrant 4 (Take✅ Track✅): 40361 (mono) / 40209 (preserve) / 41993 (match track) based on mode+policy
  - ARCHITECTURE: Clear separation of concerns
    • RGWH Core: Handles AUTO/MONO/MULTI modes with policy support via ExtState
    • AudioSweet Core: Manages three policies including SOURCE-target (FX track adjustment)
    • ExtState protocol: Single source of truth for Multi-Channel Policy communication
  - IMPACT: More accurate channel handling, better native command utilization, optimized performance
  - BREAKING: None - backward compatible, defaults to original behavior when no policy set
  - REQUIRES: AudioSweet Core v0.3.0+ for SOURCE-target policy support
  - DEBUG: Added comprehensive command logging system
    • New helper functions: get_command_name(), run_command()
    • All REAPER Main_OnCommand calls now logged with: command ID, command name, context
    • Logging format: "[CMD] <context> → <ID>: <command name>"
    • STATUS: MONO mode verified working correctly (All quadrant OK)

0.2.3 [251225.1845] - EPSILON VALUE REFINEMENT + CRITICAL BUG FIX
  - CHANGED: Epsilon refined from 0.5 frames to 0.1 frames for better precision
  - FIXED: frames_to_seconds() was using video FPS instead of audio sample rate (line 941-950)
    • Bug: Used TimeMap_curFrameRate (24fps) instead of sr parameter → epsilon was 2000x too large!
    • Fix: Now correctly uses sr (sample rate) when provided, falls back to video fps otherwise
    • Impact: Epsilon now correctly 0.002ms @ 48kHz (was incorrectly 4.17ms)
  - REASON: 0.1 frames (48kHz: 0.002ms) balances float precision handling with user intent
  - IMPACT: More accurate touch/overlap detection, respects intentional micro-gaps

0.2.2 [251225.1830] - EPSILON INTERNALIZED
  - CHANGED: Epsilon is now internal constant (0.5 frames), no longer user-configurable
  - REMOVED: EPSILON_MODE and EPSILON_VALUE from ExtState settings
  - REMOVED: epsilon parameter from args (no longer accepts overrides)
  - SIMPLIFIED: M.utils.project_epsilon() now returns hardcoded value
  - REASON: Epsilon rarely needs adjustment, simplifies user experience
  - IMPACT: GUI epsilon settings removed, epsilon always consistent

0.2.1 [251225.1820] - PUBLIC UTILITY API
  - ADDED: M.utils.detect_units_from_selection() - shared unit detection
  - ADDED: M.utils.project_epsilon() - epsilon calculation
  - ADDED: M.utils.ranges_touch_or_overlap() - range overlap detection
  - ADDED: M.utils.select_only_items() - item selection utility
  - PURPOSE: Enable code reuse across AudioSweet Core and AS Preview Core
  - IMPACT: Single source of truth for unit detection logic

0.2.0 [v251223.2256] - PUBLIC BETA ALIGNMENT
  - CHANGED: Version bump to 0.2.0 (public beta)
  - ADDED: Multi-Channel Policy support hook for AudioSweet integration

0.1.1 [v251222.1145] - AUDIOSWEET MULTI-CHANNEL POLICY SUPPORT
  - ADDED: preserve_track_ch parameter to apply_multichannel_no_fx_preserve_take()
    • preserve_track_ch=true: restore track channel count after apply (default, RGWH standalone behavior)
    • preserve_track_ch=false: allow track channel count to change (for AudioSweet Multi-Channel Policy)
    • Default true for backward compatibility - existing RGWH Core calls unchanged
    • AudioSweet can now control whether FX track channel count should be preserved
    • Enables AudioSweet's SOURCE-TRACK and SOURCE-PLAYBACK policies to work correctly
  - Debug log updated: shows preserve_track_ch value in apply log

0.1.0 [v251214.0040] - SIMPLIFIED VOLUME MERGE LOGIC
  - Simplified: Removed "Merge to Item + Print ON" support (GUI auto-switches to Merge to Take)
    • Rationale: REAPER can only print take volume, not item volume
    • GUI now auto-switches to Merge to Take when Print ON is enabled with Merge to Item
    • This simplifies Core logic and prevents confusing/impossible combinations
    • Valid combinations: OFF | Merge to Item | Merge to Take + Print OFF | Merge to Take + Print ON
  - Removed: "merge to item + print ON" branch from preprocess/postprocess (lines 1121-1144, 1208-1213)
  - Simplified: Merge to Item now only handles Print OFF case
  - Note: This change has no functional impact - GUI prevents the removed combination from being used

0.1.0 [v251213.2347] - BIDIRECTIONAL VOLUME MERGE SUPPORT
  - Tested: All four merge/print combinations verified working correctly
  - Fixed: Merge to Item + Print OFF - BOTH item AND take must be 1.0 during render
  - Critical: REAPER renders with item×take volume (not just take!)
  - Added: merge_to_item parameter for bidirectional volume merge support

 (251212.2300) - CLEANUP: Removed unused settings
  - Removed: RENAME_OP_MODE setting (was never implemented, no functional change)
  - Removed: GLUE_AFTER_MONO_APPLY setting (was never implemented, no functional change)
    • Removed from DEFAULTS (was line 781)
    • Removed from read_settings() (was line 846)
    • Defined in v251113.1540 but never checked in actual code
    • Actual behavior unchanged: Mono mode in AUTO/GLUE always glues multi-item units after mono apply
  - Removed: RENAME_OP_MODE setting (complete removal details)
    • Removed from API documentation args.policies.rename_mode (line 38-42)
    • Removed from DEFAULTS (was line 787)
    • Removed from read_settings() (was line 851)
    • Removed from args.policies processing (was lines 2970-2972)
    • Actual naming behavior unchanged: RENDER still uses rename_new_render_take() to create "TakeName-renderedN"
    • GLUE still uses REAPER native "TakeName-glued-XX.wav" naming
  - Technical: This setting was defined in v251115.2045 but never actually used in the code
    • rename_new_render_take() function (lines 935-958) always executed regardless of setting
    • GLUE mode (line 2088-2090) intentionally does not rename (preserves REAPER native behavior)
    • Removing the unused setting has no impact on actual operation
  - Requires: RGWH GUI v251215.2300 (Rename Mode setting removed from GUI)

 (251121.1700) - REFACTOR: Unified glue cue logic with shared add_glue_cues() function
  - Created: Shared add_glue_cues() function (lines 1471-1542) for all glue cue operations
  - Replaced: Three separate implementations with single shared function
    • GAP unit glue cues (was lines 1761-1814, now 1762-1765)
    • Regular unit glue cues (was lines 1798-1843, now 1910-1914)
    • TS-Window glue cues (was lines 2236-2271, now 2236-2246)
  - Benefits:
    • Single source of truth for glue cue logic
    • Consistent behavior across all glue modes (GAP, TOUCH, TS-Window)
    • Easier maintenance (one place to update)
    • Reduced code duplication (~150 lines removed)
  - Technical: TS-Window remaps members to use clamped positions (iL) for correct marker placement

 (251121.1645) - FIX: GAP unit glue cue marker cleanup
  - Issue: Temporary project markers sometimes not removed after GAP unit glue
  - Root cause: Used incorrect DeleteProjectMarkerByIndex API instead of remove_markers_by_ids()
  - Solution: Use existing remove_markers_by_ids() function for consistent cleanup

 (251121.1635) - FIX: GAP unit (TS Glue) now writes glue media cues
  - Issue: When using TS Glue with gaps between items, #Glue: cues were not written
  - Root cause: GAP unit block returned early before glue cue logic could execute
  - Solution: Added glue cue logic inside GAP unit handling (lines 1667-1735)
  - Now creates #Glue: <TakeName> markers when source files change within GAP units

 (251115.2045) - MAJOR: Unified glue flow - Glue first, then conditionally Apply
  - Fixed: Mono mode glue now preserves take name → filename behavior
    • Previous issue: Apply (40361) first → creates "render 001.wav" → Glue → filename lost
    • Root cause: Apply generates generic "render XXX" filenames, losing original take names
    • Impact: Users had to manually rename files after glue operations
  - Changed: Unified glue flow for ALL modes (mono/multi/auto): Glue → (conditional) Apply
    • Removed: 233 lines of old mono-specific Apply-first logic (line 1879-2113)
    • New approach: All modes use same flow - Glue (42432) first, then conditionally Apply
    • Rationale: Native Glue already converts take name → filename, no renaming needed
  - Performance: Massive speed improvement for mono mode without track FX
    • Skip Apply when: GLUE_TRACK_FX=false AND (mode=mono OR not force_multi)
    • Example: 4-item crossfade unit - OLD: 4× Apply + 1× Glue → NEW: 1× Glue only
    • Debug log shows: "[SKIP APPLY] No need to Apply - Glue already preserves take name → filename"
  - Implementation details:
    • Line 1879-1942: Unified Glue → Apply logic for all modes
    • Line 1909-1923: Conditional Apply logic - only when needed:
      - If GLUE_TRACK_FX=true → Apply to print track FX
      - If mode=multi AND force_multi policy → Apply to force multichannel
      - Otherwise → Skip Apply entirely
    • Line 1893-1905: Track channel count snapshot/restore (preserves from previous fix)
  - Benefits:
    • ✅ Take name → filename preserved automatically by Glue
    • ✅ No post-render file renaming needed
    • ✅ Faster execution (skip unnecessary Apply operations)
    • ✅ Cleaner, more maintainable code (one unified path)
    • ✅ Track channel count correctly restored after Glue
  - Testing: Verified with 4-item crossfade unit in mono mode, GLUE_TRACK_FX=false
    • Result: Direct glue without Apply, take names preserved in filenames
    • Performance: Significantly faster (1 operation vs 5 operations)

 (251114.0045) - DOCUMENTATION: Removed detailed manual from Core, moved to GUI
  - Removed: Detailed @manual section with operation modes guide (was lines 60-370)
    • Detailed documentation now available in RGWH GUI: Help > Manual (Operation Modes)
    • Core file reduced by ~310 lines for better maintainability
  - Updated: @notes section now references GUI manual for detailed guide
    • Added note: "For detailed operation modes guide, see RGWH GUI: Help > Manual"
  - Reasoning: Keep Core library focused on API documentation, detailed user guides in GUI
  - Related: RGWH GUI v251114.0100 includes comprehensive operation modes manual window

 (251113.2350) - CRITICAL FIX: Track channel auto-expansion by Action 42432 (Glue)
  - Fixed: Track channel count auto-expands during Glue operations
    • Root cause: Action 42432 (Glue items) auto-expands track channels when source > track
    • Example: 5ch source on 2ch track → Glue expands track to 6ch → subsequent apply outputs 6ch
    • Impact: force_multi policy didn't prevent track expansion by Glue
  - Verified through testing:
    • Action 41993 (Apply multichannel) does NOT change track channels (test script confirms)
    • Action 42432 (Glue items) DOES change track channels to accommodate widest source
    • This is REAPER's native Glue behavior, not a bug
  - Solution: Lock and restore track channel count around both Glue and Apply
    • For Glue (42432): Snapshot before, restore after (line 2115-2127)
    • For Apply (41993): Snapshot before, restore after (line 1495-1519)
  - Implementation:
    • Modified: glue_unit() multi/auto path (line 2115-2127)
      - Added track channel snapshot before 42432
      - Added track channel restore after 42432
      - Debug log: "[GLUE] Track channel auto-expanded 2→6 by 42432, restored to 2"
    • Modified: apply_multichannel_no_fx_preserve_take() (line 1495-1519)
      - Added track channel snapshot/restore for 41993
      - Debug log: "[APPLY] Track channel auto-expanded 2→6, restored to 2"
  - Test scenario that triggered the issue:
    • Track #170: 2 units, track_channels=2
    • Unit #1: 1ch source → Glue → track stays 2ch → Apply → output 2ch ✓
    • Unit #2: 5ch source → Glue → track expands to 6ch → Apply → output 6ch ✗
    • After fix: Both units keep track at 2ch, outputs correctly match track channel
  - Impact: force_multi now truly enforces original track channel limit for both Glue and Apply
  - Test tool: Created Test_42432_Track_Channel_Behavior.lua to verify Glue behavior

 (251113.2230) - VERIFIED: Multi channel mode tested and working correctly
  - Tested: channel_mode="multi" working correctly across all operation modes
  - Test environment: 5-channel source on 6-channel track
  - RENDER mode (Track FX=OFF, Force Multi policy):
    • Correctly uses Action 41993 (Apply multichannel)
    • Output channels follow track channel count (5ch source → 6ch output)
    • Track FX properly disabled during apply (not baked)
    • Handles, volumes, TimeReference all working correctly
  - GLUE mode (Track FX=OFF, Force Multi policy):
    • Correctly uses native Glue (42432) → then Apply multichannel (41993)
    • Output channels follow track channel count (5ch source → 6ch output)
    • Handles extended correctly, volumes handled properly
    • TimeReference embedded correctly at unit start
  - Channel behavior confirmed:
    • RENDER/APPLY modes: Output = track channel count (by REAPER design)
    • Matches "What You Hear Is What You Get" principle
    • Consistent with actual monitoring/playback routing
  - Impact: Multi mode now fully functional and matches mono mode behavior
  - Previous tests: Mono mode already verified working (v251113.1820)
  - Ready for: AUTO mode testing (per-item/per-unit channel detection)

 (251113.1820) - STABLE: Volume handling fully tested and working
  - Verified: All volume handling working correctly with proper settings
  - Tested: Merge volumes + Print volumes in mono apply + glue workflow
  - Confirmed: Settings now properly read from GUI and applied
  - Result: itemVol=1.0, takeVol=1.0 after merge+print (volumes baked into audio)
  - This version is stable and ready for production use

 (251113.1810) - CRITICAL FIX: Volume settings not being read from ExtState
  - Fixed: MERGE_VOLUMES and PRINT_VOLUMES settings were not being read from ExtState
    • Previous behavior: Settings always defaulted to false (nil), ignoring GUI settings
    • Root cause: read_settings() function was missing these 4 keys
    • Impact: Volume handling code was correct but settings were never passed in
  - Added: Volume settings to DEFAULTS (line 645-649)
    • RENDER_MERGE_VOLUMES = 1 (default ON)
    • RENDER_PRINT_VOLUMES = 1 (default ON)
    • GLUE_MERGE_VOLUMES = 1 (default ON)
    • GLUE_PRINT_VOLUMES = 1 (default ON)
  - Added: Volume settings to read_settings() function (line 712-716)
    • Now properly reads from ExtState with fallback to DEFAULTS
    • Uses get_ext_bool() to convert to boolean
  - This fixes the reported volume issues - settings are now properly applied

 (251113.1800) - MAJOR REFACTOR: Unified volume/FX handling with helper functions
  - Added: Centralized helper functions for volume and FX handling (line 848-1080)
    • snapshot_item_volumes() - Snapshot item and all takes' volumes
    • preprocess_item_volumes() - Handle merge_volumes and print_volumes before render/apply
    • postprocess_item_volumes() - Restore/set volumes after render/apply based on settings
    • snapshot_track_fx() / restore_track_fx() / disable_all_track_fx() - Track FX handling
    • snapshot_take_fx_offline() / restore_take_fx_offline() / offline_all_online_take_fx() - Take FX handling
  - Refactored: RENDER mode to use new helper functions
    • Removed ~70 lines of duplicated volume handling code
    • Now uses preprocess_item_volumes() and postprocess_item_volumes()
    • Behavior unchanged, just cleaner and more maintainable
  - Refactored: GLUE mono apply mode to use new helper functions
    • Removed ~60 lines of duplicated volume handling code
    • Now uses same helpers as RENDER mode
    • Ensures consistent volume behavior across all modes
  - Fixed: GLUE multi/auto mode now has volume handling
    • Previous behavior: Volumes were baked by Glue (42432) but never restored
    • New behavior: Snapshots first item's volumes, preprocesses them, then restores after glue
    • Now respects GLUE_MERGE_VOLUMES and GLUE_PRINT_VOLUMES settings
    • Uses same helper functions as RENDER and mono apply modes
  - Benefits:
    • Single source of truth for volume/FX logic (no more copy-paste bugs)
    • Easier to maintain and test
    • Consistent behavior across RENDER, GLUE mono, and GLUE multi modes
    • Future changes only need to be made in one place
  - Technical: All volume handling now follows the same pattern:
    1. Snapshot volumes (item + all takes)
    2. If merge=ON: multiply item vol into all take vols, set item=1.0
    3. If print=OFF: reset active take to 1.0 (non-destructive)
    4. Execute REAPER action (bakes current volumes)
    5. Restore volumes based on merge×print combination (4 cases)
  - Impact: Volume handling now works consistently across all workflows
  - This refactor should fix the reported volume issues in mono apply mode

 (251113.1700) - CRITICAL FIX: Volume handling in mono apply workflow
  - Fixed: Mono apply workflow now properly handles volume merge/print settings
    • Previous behavior: Volumes reset to 1.0 after mono apply + glue (volumes lost)
    • New behavior: Full volume snapshot/merge/restore logic matching RENDER mode
    • Affects: channel_mode="mono" or "auto" (when unit is detected as mono)
    • Only affected mono source items; multi-channel items were not affected
  - Implementation: Volume handling in mono apply path (glue_unit function, line 1542-1782)
    • Before Apply: Snapshot all volumes (item + all takes)
      - If merge_volumes=ON: merge item volume into ALL takes, set item=1.0
      - If print_volumes=OFF: reset active take to 1.0 (non-destructive mode)
    • After Apply (each item): Restore volumes based on merge/print settings
      - print+merge: item=1.0, new take=1.0, old takes keep merged volume
      - print only: item=original, new take=1.0, old take=original
      - non-print+merge: item=1.0, all takes=merged volume
      - non-print only: item=original, all takes=original take volume
    • After Glue (if gluing): Set glued item volumes from first item's snapshot
      - Glue action (42432) bakes all volumes → restore based on merge/print
      - Uses first item's volume_snap for consistent behavior
  - Technical: Follows RENDER mode volume handling pattern (line 2414-2607)
    • Same merge logic: multiply item volume into ALL takes (not just active)
    • Same restore logic: different handling for 4 combinations of merge×print
    • Saves volume_snap in applied_items table for glue restoration
  - Settings: Uses cfg.GLUE_MERGE_VOLUMES and cfg.GLUE_PRINT_VOLUMES
  - Impact: Volume control now works correctly in mono channel mode for both apply-only and apply+glue paths
  - Test case: itemVol=4.169 × takeVol=0.631 → correctly preserved/restored instead of reset to 1.0

 (251113.1650) - CRITICAL FIX: Mono channel mode FX control + RENDER mode support
  - Fixed: Mono apply workflow now respects TAKE_FX and TRACK_FX settings
    • Previous behavior: 40361 (Apply mono) always printed all FX regardless of settings
    • New behavior: Snapshot/disable Track FX and offline Take FX before apply when FX=OFF
    • Restore FX states after apply (Track FX enabled states, Take FX offline states)
  - Fixed: RENDER mode now enforces mono output when channel_mode="mono"
    • Previous behavior: Used 40601 (Render preserve) → kept original channel count
    • New behavior: Uses 40361 (Apply mono) to force mono output regardless of TRACK_FX setting
    • Mono enforcement now works consistently across RENDER, AUTO, and GLUE modes
  - Fixed: D_STARTOFFS calculation after Apply mono in non-gluing path
    • Correct offset = m.L - d.gotL (original position - extended position)
    • Ensures rendered audio plays from correct source position after trim
  - Implementation: Mono apply workflow (glue_unit function, line 1455-1665)
    • Step 0: Snapshot and disable Track FX if GLUE_TRACK_FX=false
    • Step 1: For each item - snapshot/offline Take FX, apply mono (40361), restore Take FX
    • Step 2: Determine should glue (GLUE mode=always, AUTO mode=depends on setting)
    • Step 3: Optional glue + trim, or individual trim with correct D_STARTOFFS
    • Step 4: Restore Track FX enabled states
  - Implementation: RENDER mode force_mono flag (line 2503-2510)
    • Added force_mono condition to use_apply logic
    • Ensures 40361 is used when channel_mode="mono" regardless of FX settings
  - Technical: FX control follows same pattern as RENDER mode
    • Track FX: TrackFX_SetEnabled(false) → apply → restore enabled states
    • Take FX: TakeFX_SetOffline(true) → apply → restore offline states to new take
  - Impact: Mono channel mode now fully functional with correct FX control in all modes
  - Requires: GUI v251113.1540 for GLUE_AFTER_MONO_APPLY setting

 (251113.1540) - MAJOR: Explicit mono/multi channel mode enforcement with conditional glue
  - Added: GLUE_AFTER_MONO_APPLY setting for AUTO mode behavior control
    • ON (default): Apply mono (40361) to each item, then glue the unit
    • OFF: Apply mono (40361) to each item, keep as separate items
    • GLUE mode always glues after mono apply (ignores this setting)
  - Changed: Explicit channel_mode="mono" now uses action 40361 (Apply mono) workflow
    • Previous behavior: Used native glue (42432) which auto-detects channels → stereo sources stayed stereo
    • New behavior: Applies mono (40361) to each item first → forces mono output regardless of source
  - Changed: Explicit channel_mode="multi" continues using native glue/render (unchanged)
  - Implementation details (glue_unit function):
    • Step 1: Apply mono (40361) to each extended item individually
    • Step 2: Clear fades before apply (40361 bakes them), save for later restoration
    • Step 3: Determine if should glue: GLUE mode=always, AUTO mode=depends on GLUE_AFTER_MONO_APPLY
    • Step 4a: If gluing → select all mono items, create TS, glue (42432), trim to original span
    • Step 4b: If not gluing → trim each mono item back to original span individually
    • Step 5: Restore boundary fades, calculate handles and offsets correctly
  - Technical: Fade preservation required because 40361 bakes fades into audio
  - Technical: Handle calculations (left_total/right_total) based on UL/UR to u.start/u.finish
  - Technical: Offset calculations ensure D_STARTOFFS points to correct audio after trim
  - Impact: Explicit mono mode now properly enforces mono output in all apply modes (RENDER/AUTO/GLUE)
  - Impact: channel_mode="auto" unchanged (per-item/per-unit detection still works as before)
  - Note: RENDER mode not affected (continues using 41993 for multi, or native render for mono detection)

 (251112.2220) - VERIFIED: Per-item/per-unit channel detection working correctly
  - Verified: All test cases pass with new per-item/per-unit channel detection
  - Test results with channel_mode="auto":
    • 3 mono items (src=1) → rendered as mono (src=1) ✓
    • 1 MIXED unit with mono sources (src=1) → glued as mono (src=1) ✓
    • 1 multichannel item (src=5) → rendered as multi (src=6) ✓
  - Previous behavior would have rendered all items as multichannel (src=6)
  - New behavior correctly matches each item/unit's actual channel requirements
  - Production ready for mixed mono/multi workflows

 (251112.2030) - CRITICAL: Channel mode "auto" now per-item/per-unit detection
  - Changed: channel_mode="auto" behavior is now per-item for RENDER and per-unit for GLUE/AUTO
  - Previous behavior: Scanned ALL selected items, used max channel count for entire operation
  - New behavior (per-item/per-unit):
    • RENDER mode: Each item independently determines mono/multi based on its source channels
    • GLUE mode: Each unit independently determines mono/multi based on max channels across its members
    • AUTO mode: RENDER phase uses per-item, GLUE phase uses per-unit detection
  - Example: If you have 3 mono items and 1 multichannel (5ch) item:
    • Old: All 4 items rendered as multichannel (src=6)
    • New: 3 mono items render as mono (src=1), 1 multichannel renders as multi (src=6)
  - Technical: Removed global auto detection in render_selection() and glue_selection()
  - Technical: Added per-item detection in render loop, per-unit detection in glue_unit()
  - Impact: More accurate channel handling, matches user intent for mixed mono/multi workflows

 (251112.1430) - STABLE: Core P0 testing complete, all scenarios pass
  - Comprehensive P0 test suite completed (RENDER, GLUE, AUTO modes with various TS/unit combinations)
  - All test results: ✓
    • P0-1: RENDER single item, no TS → handles, volume merge+print, take FX clone ✓
    • P0-2: GLUE multiple SINGLE units, no TS → independent glue with handles per unit ✓
    • P0-3: GLUE with TS (4 scenarios) → correct TS-Window / Units mode switching:
      - TS L+R > unit: TS-Window glue, no handles ✓
      - TS L=unit, R>unit: TS-Window glue, no handles ✓
      - TS R=unit, L>unit: TS-Window glue, no handles ✓
      - TS inside item: Split → auto-detect TS=unit → Units glue WITH handles ✓
    • P0-4: GLUE MIXED unit (overlapping), no TS → glue with handles ✓
    • P0-5: AUTO mode (SINGLE+MIXED units) → RENDER singles with handles, GLUE mixed with handles ✓
  - Core stability verified across:
    • Volume handling (merge/print combinations)
    • Handle extension (Units mode vs TS-Window mode)
    • Selection restore (TS-aware smart restore)
    • Auto-detect TS=unit after split
    • AUTO mode TS independence
  - Ready for production use

 (251111.1615) - CRITICAL FIX: AUTO mode now ignores TS for glue operations (always uses handles)
  - Fixed: AUTO mode glue phase now clears TS before processing multi-item units
  - Issue: AUTO mode was detecting existing TS (from render phase or previous ops) and incorrectly applying TS-Window logic (no handles)
  - Solution: Clear TS at line 1896 before gluing multi-item units in AUTO mode
  - Result: AUTO mode now consistently applies handles to all glue operations (SINGLE and MIXED units) ✓
  - Rationale: AUTO mode operates on units basis, each unit should have handles regardless of TS state
  - Test: P0-5 (AUTO with mixed SINGLE+MIXED units) now shows handles on all glued items ✓

 (251111.1550) - CRITICAL FIX: TS-Window glue selection restore + auto-detect TS=unit after split
  - Fixed: Selection restore after TS-Window glue now correctly selects glued item (not leftover split)
  - Fixed: When TS causes item split and result equals unit edges → auto-switch to Units glue with handles
  - Core changes (line 1525-1545):
    • After split, check if TS=unit edges (single member, edges match within 2ms epsilon)
    • If true: delegate to glue_unit() for handle-aware processing instead of TS-Window glue
    • Result: Split-then-glue scenarios now get handles when TS perfectly matches unit ✓
  - Core changes (line 1605-1607):
    • Re-select glued item after TS glue to ensure correct selection state
  - Wrapper/GUI selection restore logic (Glue.lua line 272-343, ReaImGui.lua line 415-483):
    • Smart TS-aware restore: When TS exists, verify item position/length still matches before using cached pointer
    • If position changed (due to split): fall through to TS-overlap-based restore
    • Select item with maximum TS overlap (not first overlap) when multiple candidates exist
    • Use snapshot TS (not current TS) to avoid issues when Core clears TS after glue
  - Test results:
    • P0-1 (RENDER single item, no TS): ✓ Volume handling correct, handles working
    • P0-2 (GLUE multiple units, no TS): ✓ Independent glue with handles per unit
    • P0-3 (GLUE with TS, various scenarios): ✓ All 4 scenarios pass:
      - TS L+R > unit: TS-Window glue, no handles ✓
      - TS L=unit, R>unit: TS-Window glue, no handles ✓
      - TS R=unit, L>unit: TS-Window glue, no handles ✓
      - TS inside item: Split → auto-detect TS=unit → Units glue WITH handles ✓
  - Ready for continued comprehensive testing

 (251110.2315) - Verified: Volume handling working correctly across all modes
  - Confirmed merge+print fix (v2300) resolves volume preservation issues
  - All volume modes tested and verified:
    • merge=off, print=off → preserves original item/take volumes ✓
    • merge=on,  print=off → merged volumes preserved non-destructively ✓
    • merge=off, print=on  → original structure, new take baked ✓
    • merge=on,  print=on  → merged volumes, new take baked ✓
  - Ready for comprehensive testing

 (251110.2300) - CRITICAL FIX: Render volume handling for merge+print mode
  - Fixed: Old takes now keep merged volume in merge+print mode (was: incorrectly reset)
  - Fixed: Undefined variable tk_orig_idx causing potential errors
  - Root cause: Line 2177 was overwriting merged volume that was already set at line 2064
  - Solution: In merge+print mode, don't touch old take volumes (already merged at line 2073)
  - Test case verified:
    • Original: item=-6.3dB, take=+21.0dB
    • After merge+print render: item=0dB, old take=+14.7dB, new take=0dB ✓
  - Modified lines 2056-2085: Added tk_orig_idx lookup, fixed merge logic
  - Modified lines 2173-2182: Removed incorrect volume restore for old take

 (251110.2250) - STABLE: Handle logic and scope detection finalized
  - Verified: Item Selection (IS) only → Units glue with handles ✓
  - Verified: Time Selection (TS) exists → TS-Window glue (handles only if TS=unit) ✓
  - Core logic summary:
    • TS exists → TS-Window mode (per-track glue within TS bounds)
    • No TS → Units mode (per-unit glue with handle extension)
    • Handles: Only when TS exactly equals unit (both edges aligned within epsilon)
    • Multi-track: Supported in both modes
  - Ready for comprehensive testing across all scenarios

 (251110.2130) - Fixed: Units glue works without TS (Item Selection only)
  - Fixed: Multiple units without TS now process individually with handles (was: merged into GAP unit)
  - Removed: Multi-track TS-Window enforcement (was incorrect)
  - Behavior: Item Selection (IS) only → Units glue with handles, supports multi-track ✓
  - Behavior: Time Selection (TS) exists → TS-Window glue, no handles (unless TS=unit) ✓
  - Modified lines 1703-1746: GAP unit merge only when TS exists
  - Modified lines 1649-1658: Removed multi-track scope override
  - Example: 2 SINGLE units, no TS → each glued individually with 5s handles ✓

 (251110.2100) - Handle logic: Strict TS=Unit requirement + multi-track TS-Window enforcement
  - Changed: Handles ONLY applied when TS exactly equals unit edges (both left AND right aligned)
  - Logic: If TS ≠ Unit → no handles (0.0), regardless of partial overlap
  - Multi-track: If selection spans >1 track → force TS-Window mode (no handles)
    • Each track glued independently within TS bounds
    • Respects FX/cue settings per track
    • No handle extension even if TS=unit on some tracks
  - Modified lines 1145-1170: Simplified handle logic to TS=Unit check only
  - Modified lines 1634-1669: Multi-track detection and TS-Window enforcement
  - Example cases:
    • TS=0..2s, unit=0..2s → handles (5s default) ✓
    • TS=0..3s, unit=0..2s → no handles (partial overlap) ✗
    • TS=0..2s, unit=1..2s → no handles (left misaligned) ✗
    • Multi-track selection → always TS-Window mode, no handles ✓

 (251110.2000) - Handle logic: Apply handles when TS is at unit edge OR outside (inclusive)
  - Changed: Handle calculation now uses inclusive conditions for left/right independently
  - Left: If TS_left <= unit_left + eps → apply default HANDLE (was: strict < for outside only)
  - Right: If TS_right >= unit_right - eps → apply default HANDLE (was: strict > for outside only)
  - Logic: "只要TS edge有在units的edge or inside 就要有handle 而且左右分開處理"
  - Impact: Handles now apply when TS is at edge OR outside, not just strictly outside
  - Modified lines 1122-1152: Updated conditions and debug messages
  - Example: TS=0..2s, unit=0..2s → uses 5s default handles (edge-aligned case)
  - Example: TS=0..2s, unit=1..2s → left gets 5s handle (TS at/outside left edge)

 (251110.1920) - CRITICAL FIX: Correct D_STARTOFFS adjustment for glue with handles
  - Fixed: Content alignment now correct when gluing with left-side handles
  - Root cause: D_STARTOFFS was not adjusted before glue, causing REAPER to read from wrong source position
  - Solution: When extending item left, adjust D_STARTOFFS before glue (lines 1198-1225)
    • Formula: new_offset = old_offset - (left_extension * playrate)
    • Example: Item at 16.458s with offset 6.208s, extend left by 5s → offset becomes 1.208s
    • This ensures glue reads from correct source position (1.208s instead of 6.208s)
  - Key insight: Unlike render, glue REQUIRES pre-glue offset adjustment for left extensions
    • Render: Keeps original offset, handles it via TimeReference
    • Glue: Needs adjusted offset so extended portion reads from earlier in source
  - Post-glue trim operation sets final offset based on trimmed amount (line 1254)
  - Debug output: Added [PRE-GLUE] logs showing extension amounts and offset adjustments
  - Impact: All glue operations with left handles now preserve content alignment perfectly
  - Tested: Item at 16.458s, SIS 6.208s → glue with 5s left handle → content identical

 (251110.1800) - Handle calculation refinement: TS edge equality handling
  - Fixed: When TS edges exactly equal unit edges, now uses default handles (not 0-length handles)
  - Root cause: Condition `tsL <= unitL + eps` matched when TS=unit, calculating H_left=0
  - Solution: Changed to strict inequality `tsL < unitL - eps` (lines 1115, 1122)
    • TS strictly outside unit → use TS-based handle
    • TS equal to or inside unit → use default HANDLE value
  - Example: TS=0..2s, unit=0..2s → now uses 5s handles (was 0s)
  - Impact: Proper handle extension when TS matches selection exactly

 (251110.1730) - CRITICAL FIX: TS-based handle calculation prevents content shift
  - Fixed: All unit types (SINGLE/TOUCH/GAP) now use TS boundaries for handle calculation when TS exists
  - Fixed: Content no longer shifts when gluing with TS-extended handles
  - Root cause: Handle calculation used fixed HANDLE value, ignoring TS boundaries
  - Solution: Dynamic handle calculation based on TS vs unit edge relationship (lines 1071-1117)
    • If TS_left ≤ unit_left: H_left = unit_left - TS_left (extend to TS boundary)
    • If TS_right ≥ unit_right: H_right = TS_right - unit_right (extend to TS boundary)
    • Otherwise: use default HANDLE value
  - Example: Item at 2-4s with TS 0-6s → H_left=2s, H_right=2s (not fixed 5s)
  - Debug output: Added [TS-UNIT] and [HANDLE] logs showing relationship and calculations
  - Impact: "完全尊重TS的範圍" - all edges respect TS range, content stays aligned
  - Tested: Single item with TS extending both sides - no content shift

 (251110.1630) - CRITICAL FIX: GAP unit glue now respects full TS range
  - Fixed: Multiple items with gaps + TS extending beyond items now glues to full TS range
  - Example: Items at 0-1s and 2-4s with TS=0-6s now glues to 0-6s (was 0-4s)
  - Root cause: GAP unit span calculation used item boundaries only, ignoring TS boundaries
  - Solution: Per-edge TS boundary detection for GAP units (lines 1547-1570)
    • Left edge: use TS_left if TS_left ≤ items_left
    • Right edge: use TS_right if TS_right ≥ items_right
  - Impact: GAP units fill leading/trailing space as silence when TS extends beyond items
  - Tested: Track #170 case (items 0-1s, 2-4s, TS 0-6s) now correctly glues to 0-6s

 (251110.1430) - CRITICAL FIX: TS glue scope detection + Units glue handle offset
  - Fixed: TS = Item selection now correctly uses Units glue with handles (not TS glue)
  - Fixed: Units glue with handles no longer causes content shift
  - Root cause #1: glue_auto_scope() in "glue" mode always returned TS path, ignoring TS≈selection check
  - Root cause #2: Pre-glue D_STARTOFFS adjustment was incorrectly removed in v251107.1530
  - Solution #1: Unified glue_auto_scope() logic - both GLUE and AUTO modes now check TS≈selection
    • TS ≈ selection → Units glue (with handles)
    • TS ≠ selection → TS glue (no handles, non-destructive split)
  - Solution #2: Restored pre-glue D_STARTOFFS adjustment (line 1079-1083)
    • Formula: new_offset = old_offset - (deltaL * playrate)
    • Required when extending item left to prevent REAPER glue from reading wrong source position
  - Technical: When item position moves from m.L to newL (extending left by deltaL), we must adjust
               D_STARTOFFS by -deltaL to keep the same audio content at the same timeline position.
               Without this, REAPER glue would read from wrong source position.
  - Impact: All glue operations (Units with/without TS, TS-Window) now work correctly
  - Tested: TS=selection uses Units glue with handles; content alignment preserved

 (251107.0240) - MAJOR: GLUE MODE NOW PRIORITIZES TS-WINDOW (NO HANDLES)
  - Changed: glue_selection() now auto-detects TS and uses TS-Window glue when TS exists
    • When TS exists: Uses TS-Window glue (NO handles, splits at boundaries, non-destructive)
    • When NO TS: Uses Units glue (with handles as configured)
    • Take/Track FX and other settings are respected in both paths
  - Changed: glue_auto_scope() now accepts mode parameter ("glue" vs "auto")
    • "glue" mode: Always use TS-Window when TS exists (for glue_selection)
    • "auto" mode: Use original logic (TS≈selection → units glue with handles)
  - Changed: AUTO mode (auto_selection, core API op="auto") maintains original behavior
    • Still uses units glue with handles when TS≈selection span
    • This is intentional: AUTO mode is for intelligent unit processing
  - Added: glue_selection() accepts force_units parameter
    • core() API with scope="units" can force units glue even when TS exists
    • Ensures explicit scope specification is honored
  - Added: Pre-glue boundary splitting in TS-Window path (line 1182-1255)
    • Splits items at tsL/tsR boundaries before gluing
    • Preserves portions outside TS as separate items (non-destructive)
    • Example: Item 0-2s with TS 1-1.5s → [0-1s], [1-1.5s glued], [1.5-2s]
  - Removed: Handle extension logic from TS-Window glue path
    • TS-Window glue never uses handles (matches native REAPER behavior)
    • Handles only apply in Units glue path
  - Rationale: Users expect GLUE button to use TS range when TS is set, without handles

 (251107.0100) - FIXED AUTO MODE LOGIC
  - Fixed: AUTO mode now correctly processes units based on their composition (not total selection count)
    • Single-item units → RENDER (per-item)
    • Multi-item units (TOUCH/CROSSFADE) → GLUE
    • Works correctly even when selecting mixed unit types
  - Added: New auto_selection() function (line 1340-1445)
    • Analyzes each unit individually based on its composition
    • Separates single-item units (for render) and multi-item units (for glue)
    • Processes render phase first, then glue phase
    • Handles undo blocks correctly between phases
  - Changed: core() function now calls auto_selection() for op="auto" (line 1955-1959)
    • Removed old logic that only checked total selection count
    • New logic respects unit composition regardless of how many items are selected
  - Technical: Unit members structure is {it=item, L=pos, R=pos}, not direct item array
  - Rationale: Users expect AUTO to intelligently handle mixed selections where some units
               need render (single items) and others need glue (multi-item groups)

 (251030.1600) - Initial Public Beta Release
  Core library for handle-aware Render/Glue workflows featuring:
  - Handle-aware windows with clamp-to-source
  - Glue by Item Units (same-track grouping) with optional Glue Cues
  - Render single items with BWF TimeReference embed
  - One-run overrides via ExtState snapshot/restore
  - Edge Cues (#in/#out) and Glue Cues for media cue workflows
  - Integration with AudioSweet Core and Preview Core

Internal Build 251029_1930
  - CRITICAL FIX: Changed all chanmode reads to use GetMediaItemTakeInfo_Value() instead of GetMediaItemInfo_Value()!
    • Root cause: Channel mode is stored on the TAKE, not the ITEM
    • Wrong API: GetMediaItemInfo_Value(item, "I_CHANMODE") always returns 0
    • Correct API: GetMediaItemTakeInfo_Value(take, "I_CHANMODE") returns actual channel mode
    • Affects: render_selection() and glue_selection() auto mode detection
  - Updated: get_item_playback_channels() helper in both paths now reads from take

251029_1315
  - Changed: Auto channel mode now respects item's channel mode setting for both Render and Glue.
    • Checks I_CHANMODE: modes 2/3/4 (downmix/left/right) are treated as mono
    • Examples:
      - 8ch source + "Left only" item → auto = mono
      - 2ch source + "Mono (mix L+R)" item → auto = mono
      - 8ch source + "Normal" item → auto = multi
    • Applies to: render_selection(), glue_selection(), and core() API
  - Technical: Added get_item_playback_channels() helper function in both render and glue paths
  - Rationale: Users often work with multichannel sources but set items to mono playback mode;
               auto detection should respect the item's actual playback configuration, not just source channels

251022_2200
  - Changed: merge_volumes now affects ALL takes (not just active take) to ensure consistent output
  - Rationale: When merge_volumes=true, item volume is reset to 0dB; if only active take was merged,
               switching to other takes would cause unexpected volume jumps. By merging all takes,
               the actual audio output remains consistent regardless of which take is active.
  - Added: English comments explaining the merge-all-takes behavior and design rationale

251022_1745
  - Added: Volume control for Render operations via two new toggles:
      • merge_volumes (default: true) - merge item volume into take volume before render
      • print_volumes (default: true) - bake volumes into rendered audio; false = restore original volumes after render
  - Changed: M.render_selection() now accepts merge_volumes and print_volumes parameters (5th and 6th args)
  - Changed: M.core(args) now accepts args.merge_volumes and args.print_volumes for render operations
  - Behavior: When print_volumes=false, original item and take volumes are restored after render (non-destructive)
  - Tech: Volume snapshot/restore logic added to render path; conditional merge based on merge_volumes flag
  - Note: These options only affect render operations; glue operations unchanged

251014_2246
  - Fix: TS-Window multi-track pass now uses a snapshot of the original selection.
         Per-track processing no longer depends on the live selection, so subsequent
         tracks won't show "TS glue: no members on this track" after the first pass.
  - Change: glue_by_ts_window_on_track(tr, tsL, tsR, cfg) →
            glue_by_ts_window_on_track(tr, tsL, tsR, cfg, members_snapshot).
            Call sites pass the pre-collected members list for each track.
  - Note: Behavior unchanged for single-track; this only affects multi-track TS glue.

251014_0021
  - Change: embed_current_tc_for_item() now calls E.Refresh_Items({take}) after
            a successful TR write, forcing REAPER to reload updated metadata.
  - Effect: Glue+Apply paths (Units and TS-Window) now immediately reflect
            embedded TimeReference without manual refresh.

251014_0011
  - Change: Centralized CURRENT TimeReference embed after GLUE+APPLY via
            `embed_current_tc_for_item(item, ref_pos, DBG)`.
            • Used in Units-Glue (ref_pos = u.start) and TS-Window (ref_pos = tsL).
            • Triggers whenever GLUE_TRACK_FX=1 or the force-multi no-track-FX path runs.
  - Benefit: One canonical place for Glue+Apply TC behavior; removed duplicated
             inline TR writing from individual code paths.
251013_2350
  - Fixed: TS-Window path now respects take_fx=false by clearing all take FX
            before glue, ensuring non-baked output when policy disabled.
  - Added: Debug print in TS-Window now includes GLUE_TAKE_FX state and
            reports when FX are cleared (e.g. “[TS-GLUE] cleared TAKE FX …”).
  - Behavior: Core automatically keeps WRITE_GLUE_CUES active but disables
              WRITE_EDGE_CUES for all TS-Window operations (no handle mode).
  - Internal: glue_by_ts_window_on_track() updated to handle selective
              pre-glue cleanup via clear_take_fx_for_items().

251013_2324
  - Fix: Replace C-style comment in TS-Window force-multi apply path with Lua comment to prevent syntax error.
  - Note: Decision splitter in RGWH.core(args) is already present in this build; no additional merge needed.

251013_2009
  - TS-Window glue now ignores handles (AudioSweet parity)
  - In TS-Window path, removed handle extension and boundary stretching.
  - Glue strictly within the current TS, then apply FX per policy.

v251013_1930
  - Change: Always restore previous take's StartInSource (D_STARTOFFS) after render,
            regardless of RENDER_TC_EMBED mode ("previous" | "current" | "off").
            This ensures all legacy takes stay aligned even when tc_mode="off".
  - Removed: redundant SIS restoration inside TimeReference embed block
            (logic now executed unconditionally before TR writing).

251013_1200 (Public Beta)
  - Added: TS-Window glue path and auto-scope detection (TS vs Item Units).
  - Added: Single-entry `RGWH.core(args)` (render/glue/auto).
  - Clean: English-only comments, consistent section headers, stable API doc in header.
  - Kept: Backward compat for `glue_selection()`, `render_selection()`, and `apply()`.

251009_1839
  - New: `M.render_selection(take_fx, track_fx, mode, tc_mode)` now accepts call-site overrides (integers/booleans for TAKE/ TRACK FX, `"mono"|"multi"|"auto"` for apply mode, `"previous"|"current"|"off"` for TC embed).
  - New: Apply-mode `"auto"` — infers mono/multi by scanning the max source channel count across the current selection.
  - Change: Overrides are applied in-memory for this run only; project ExtState defaults are left untouched (backward compatible if you keep calling with no args).
  - Change: Selection handling & UI/Undo wrappers tightened around render path to match glue path robustness.
  - Keep: When TRACK FX are not printed and mode resolves to `multi` with policy `RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX="force_multi"`, continue using the 41993 “no-FX” apply path (unchanged behavior).
  - Fix: Minor logging consistency and safer nil guards in the render pipeline.
  - Note: Zero-arg `M.render_selection()` behaves exactly as previous builds; only the optional parameters are new.

2510041655 Add AudioSweet bridge multi item selection support
  - In AudioSweet.lua, changed selection_scope from "unit" to "selection" when calling RGWH Core for focused FX render.
  - This allows processing all selected items together, rather than per detected unit.
  - No changes to RGWH Core itself; only the argument passed from AudioSweet script was modified.

2510041327 Add option to not clear console on run
  - New ExtState key `DEBUG_NO_CLEAR` (boolean, default false) to control whether console is cleared at start of Glue/Render operations.
  - When true, console retains previous logs for easier debugging across multiple runs.
  - When false (default), console is cleared as before.
  - No changes to other functionalities or settings.
  - Note: This setting is independent of DEBUG_LEVEL and only affects console clearing behavior.

v250930_1813 — Fix “Glue with Track FX” StartInSource
  - Fixed: After GLUE_TS + Track/Take FX apply, all takes on the glued item now have synchronized StartInSource (D_STARTOFFS) to the computed left handle (left_total). Prevents phase mismatches and take-switch offsets when a new take is created by applying FX post-glue.
  - Improved: Render path preserves the original take’s StartInSource snapshot while expanding the window, then restores it before TimeReference calculations (“previous” mode), ensuring handle-aware math remains exact.
  - Behaviour unchanged: Render naming rule (TakeName-renderedN), item/take volume pre-merge, edge/glue cue handling, and multichannel “force_multi” policy continue to work as before.
  - Compatibility: No changes to ExtState schema. Keys used by this build:
    • RENDER_TC_EMBED = "previous" | "current" | "off"  (read at runtime)
    • GLUE/RENDER_* switches (apply modes, policies) unchanged.
  - Notes: Default TimeReference mode remains “current” (per v250926_2010). “previous” and “off” remain available via ExtState.
250930_1700 Add AudioSweet bridge
v250926_2010
  - Default: RENDER_TC_EMBED = "current" (embed BWF TimeReference from item start).
  - Rationale: take switching no longer relies on previous-take TR; Hover trim/extend keeps SrcStart in sync.
  - Note: "previous" and "off" are still available via ExtState if needed.
v250925_1546 REBDER_TC_EMBED OK
  - Added: ExtState key `RENDER_TC_EMBED` ("previous" | "current" | "off") to control
    TimeReference embedding policy during render.
      • "previous" (default): embed TimeReference from the original take (handle-aware).
      • "current": embed TimeReference from current project position (item start).
      • "off": disable TimeReference embedding (skip write).
  - Fixed: initialization order — `DEFAULTS.RENDER_TC_EMBED` is now a static value
    ("previous"); actual project-scope ExtState is read inside `read_settings()`.
  - Updated: `render_selection()` now calls Metadata Embed library functions
    (`TR_PrevToActive`, `TR_FromItemStart`, `TR_Write`) according to mode.
  - Behavior: batch refresh of items after TR write remains intact.

v250925_1101 change "force-multi" to "force_multi"
v250922_2257
  - Multi-mode policies finalized:
    • GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve" | "force_multi"
    • RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve" | "force_multi"
  - When APPLY_MODE="multi"-
  and policy="force_multi" with no Track FX printing:
    • Glue: run 41993 in a no-track-FX path; preserves take-FX per setting; fades snapshot/restore
    • Render: choose apply path and run 41993; fades snapshot/restore
  - New helper: apply_multichannel_no_fx_preserve_take(it, keep_take_fx, dbg_level)
    • Temporarily disables track FX (snapshot), optionally offlines take FX, zeroes fades, runs 41993, restores everything
  - Render path: add use_apply decision (need_track OR force_multi) with clear fades only when applying
  - Console messages:
    • "[APPLY] force multi (no track FX path)"
    • "[RUN] Temporarily disabled TRACK FX (policy TRACK=0)."
  - Minor: ensure "[EDGE-CUE]" tag consistent across add/remove logs

v250922_1954
  - Prep multi-channel flow: utilities and structure for using 41993 (Apply track/take FX to items – multichannel output)
  - Separated paths for GLUE vs RENDER to allow later policy injection without changing call sites

v250922_1819
  - Rename WRITE_MEDIA_CUES → WRITE_EDGE_CUES
  - Rename WRITE_TAKE_MARKERS → WRITE_GLUE_CUES
  - Standardize: hash_ids → edge_ids; function add_hash_markers → add_edge_cues
  - Console tag "[HASH]" → "[EDGE-CUE]"
  - Glue Cue labels simplified: "#Glue: <TakeName>" (remove redundant "GlueCue:" prefix)
  - TakeName preserved with original case (no forced lowercase)
  - Final: Edge Cues (#in/#out) and Glue Cues (#Glue: <TakeName>) both embedded as media cues

v250921_1732
  - Implement Glue Cues: add cues at unit head + where adjacent sources differ
  - Glue Cues written as project markers with '#' prefix → embedded into glued media
  - Edge Cues (#in/#out) and Glue Cues temporarily added then cleaned up
  - Console output: [HASH] for edge cues, [GLUE-CUE] for glue cues

v250921_1647
  - First experiment: replace take markers with media cues (#in/#out written as project markers)
  - Console shows [HASH] add/remove; cues absorbed into glued media

v250921_1512
  - Initial stable Core snapshot (handles, epsilon, glue/render pipeline, hash markers)
```
