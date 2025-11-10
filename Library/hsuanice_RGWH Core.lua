--[[]
@description RGWH Core - Render or Glue with Handles
@version 0.1.0-beta (251110.2250)
@author hsuanice
@about
  Core library for handle-aware Render/Glue workflows with clear, single-entry API.
  Features:
    • Handle-aware windows with clamp-to-source.
    • Glue by Item Units (same-track grouping), with optional Glue Cues.
    • Render single items with apply policies and BWF TimeReference embed.
    • One-run overrides via ExtState snapshot/restore (non-destructive defaults).
    • Edge Cues (#in/#out) and Glue Cues (#Glue: <TakeName>) for media cue workflows.

@api
  -- Primary:
  RGWH.core(args) -> (ok:boolean, err?:string)
    args = {
      op = "render" | "glue" | "auto",     -- render = single item only; glue supports scope (see below)
      selection_scope = "auto" | "units" | "ts" | "item",  -- glue/auto only; render ignores it
      item  = MediaItem*,                  -- optional single-item provider (render or glue/item)
      items = { MediaItem*, ... },         -- optional items provider for glue/units

      -- Channel mode (maps to GLUE/RENDER_APPLY_MODE):
      channel_mode = "auto" | "mono" | "multi",

      -- Render-specific toggles:
      take_fx  = true|false,               -- bake take FX (nil = keep ExtState)
      track_fx = true|false,               -- bake track FX (nil = keep ExtState)
      tc_mode  = "previous" | "current" | "off", -- TimeReference embed policy (render only)
      merge_volumes = true|false,          -- merge item volume into take volume before render (default: true)
      print_volumes = true|false,          -- bake volumes into rendered audio; false = restore original (default: true)

      -- One-run overrides (fallback: ExtState -> DEFAULTS):
      handle  = { mode="seconds", seconds=5.0 } | "ext" | nil,
      epsilon = { mode="frames", value=0.5 }     | "ext" | nil,
      cues    = { write_edge=true/false, write_glue=true/false },
      policies = {
        glue_single_items = true/false,
        glue_no_trackfx_output_policy   = "preserve"|"force_multi",
        render_no_trackfx_output_policy = "preserve"|"force_multi",
        rename_mode = "auto"|"glue"|"render",
      },
      debug = { level=1..N, no_clear=true/false },
    }

  -- Legacy (kept for compatibility):
  RGWH.glue_selection()
  RGWH.render_selection(take_fx?, track_fx?, mode?, tc_mode?, merge_volumes?, print_volumes?)
  RGWH.apply(args)  -- AudioSweet bridge (unchanged)
  
@notes
  • "render" always processes a single item (selected or provided); selection_scope is ignored.
  • "glue" supports Item Units / TS-Window / single item.
  • "auto": NEW (v251107.0100) - analyzes each unit individually:
      - Single-item units → render
      - Multi-item units (TOUCH/CROSSFADE) → glue
      - Works with mixed unit types in single execution
  • All overrides are one-run only: ExtState is snapshotted and restored after operation.

@changelog
  0.1.0-beta (251110.2250) - STABLE: Handle logic and scope detection finalized
    - Verified: Item Selection (IS) only → Units glue with handles ✓
    - Verified: Time Selection (TS) exists → TS-Window glue (handles only if TS=unit) ✓
    - Core logic summary:
      • TS exists → TS-Window mode (per-track glue within TS bounds)
      • No TS → Units mode (per-unit glue with handle extension)
      • Handles: Only when TS exactly equals unit (both edges aligned within epsilon)
      • Multi-track: Supported in both modes
    - Ready for comprehensive testing across all scenarios

  0.1.0-beta (251110.2130) - Fixed: Units glue works without TS (Item Selection only)
    - Fixed: Multiple units without TS now process individually with handles (was: merged into GAP unit)
    - Removed: Multi-track TS-Window enforcement (was incorrect)
    - Behavior: Item Selection (IS) only → Units glue with handles, supports multi-track ✓
    - Behavior: Time Selection (TS) exists → TS-Window glue, no handles (unless TS=unit) ✓
    - Modified lines 1703-1746: GAP unit merge only when TS exists
    - Modified lines 1649-1658: Removed multi-track scope override
    - Example: 2 SINGLE units, no TS → each glued individually with 5s handles ✓

  0.1.0-beta (251110.2100) - Handle logic: Strict TS=Unit requirement + multi-track TS-Window enforcement
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

  0.1.0-beta (251110.2000) - Handle logic: Apply handles when TS is at unit edge OR outside (inclusive)
    - Changed: Handle calculation now uses inclusive conditions for left/right independently
    - Left: If TS_left <= unit_left + eps → apply default HANDLE (was: strict < for outside only)
    - Right: If TS_right >= unit_right - eps → apply default HANDLE (was: strict > for outside only)
    - Logic: "只要TS edge有在units的edge or inside 就要有handle 而且左右分開處理"
    - Impact: Handles now apply when TS is at edge OR outside, not just strictly outside
    - Modified lines 1122-1152: Updated conditions and debug messages
    - Example: TS=0..2s, unit=0..2s → uses 5s default handles (edge-aligned case)
    - Example: TS=0..2s, unit=1..2s → left gets 5s handle (TS at/outside left edge)

  0.1.0-beta (251110.1920) - CRITICAL FIX: Correct D_STARTOFFS adjustment for glue with handles
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

  0.1.0-beta (251110.1800) - Handle calculation refinement: TS edge equality handling
    - Fixed: When TS edges exactly equal unit edges, now uses default handles (not 0-length handles)
    - Root cause: Condition `tsL <= unitL + eps` matched when TS=unit, calculating H_left=0
    - Solution: Changed to strict inequality `tsL < unitL - eps` (lines 1115, 1122)
      • TS strictly outside unit → use TS-based handle
      • TS equal to or inside unit → use default HANDLE value
    - Example: TS=0..2s, unit=0..2s → now uses 5s handles (was 0s)
    - Impact: Proper handle extension when TS matches selection exactly

  0.1.0-beta (251110.1730) - CRITICAL FIX: TS-based handle calculation prevents content shift
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

  0.1.0-beta (251110.1630) - CRITICAL FIX: GAP unit glue now respects full TS range
    - Fixed: Multiple items with gaps + TS extending beyond items now glues to full TS range
    - Example: Items at 0-1s and 2-4s with TS=0-6s now glues to 0-6s (was 0-4s)
    - Root cause: GAP unit span calculation used item boundaries only, ignoring TS boundaries
    - Solution: Per-edge TS boundary detection for GAP units (lines 1547-1570)
      • Left edge: use TS_left if TS_left ≤ items_left
      • Right edge: use TS_right if TS_right ≥ items_right
    - Impact: GAP units fill leading/trailing space as silence when TS extends beyond items
    - Tested: Track #170 case (items 0-1s, 2-4s, TS 0-6s) now correctly glues to 0-6s

  0.1.0-beta (251110.1430) - CRITICAL FIX: TS glue scope detection + Units glue handle offset
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

  0.1.0-beta (251107.0240) - MAJOR: GLUE MODE NOW PRIORITIZES TS-WINDOW (NO HANDLES)
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

  0.1.0-beta (251107.0100) - FIXED AUTO MODE LOGIC
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

  0.1.0-beta (251030.1600) - Initial Public Beta Release
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

]]--
local r = reaper
local M = {}

-- Load Metadata Embed Library (single source of truth for TR math)
local RES_PATH = r.GetResourcePath()
local E = dofile(RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Embed.lua')

------------------------------------------------------------
-- Constants / Commands
------------------------------------------------------------
local NS = "RGWH"  -- ExtState namespace (project-scope)

-- Actions
local ACT_GLUE_TS        = 42432   -- Item: Glue items within time selection
local ACT_TRIM_TO_TS     = 40508   -- Item: Trim items to time selection
local ACT_APPLY_MONO     = 40361   -- Item: Apply track/take FX to items (mono output)
local ACT_APPLY_MULTI    = 41993   -- Item: Apply track/take FX to items (multichannel output)
local ACT_REMOVE_TAKE_FX = 40640   -- Item: Remove FX for item take

------------------------------------------------------------
-- Defaults (used if no ExtState present)
------------------------------------------------------------
local DEFAULTS = {
  GLUE_SINGLE_ITEMS  = true,
  HANDLE_MODE        = "seconds",
  HANDLE_SECONDS     = 5.0,
  EPSILON_MODE       = "frames",
  EPSILON_VALUE      = 0.5,
  DEBUG_LEVEL        = 1,
  -- FX policies (separate for GLUE vs RENDER)
  GLUE_TAKE_FX       = 1,             -- 1=Glue 之後的成品要印入 take FX；0=不印入
  GLUE_TRACK_FX      = 0,             -- 1=Glue 成品再套用 Track/Take FX
  GLUE_APPLY_MODE    = "mono",        -- "mono" | "multi"（給 Glue 後的 apply 用）

  RENDER_TAKE_FX     = 0,             -- 1=Render 直接印入 take FX；0=保留（偏向 non-destructive）
  RENDER_TRACK_FX    = 0,             -- 1=Render 同時印入 Track FX
  RENDER_APPLY_MODE  = "mono",        -- "mono" | "multi"（Render 使用的 apply 模式）
  RENDER_TC_EMBED    = "current",    -- TR embed mode for render: "previous" | "current" | "off"
  -- Rename policy:
  RENAME_OP_MODE     = "auto",        -- glue | render | auto
  -- Hash markers（#in/#out 以供 Media Cues）
  WRITE_EDGE_CUES   = 1,
  -- ✅ 新增：Glue 成品 take 內是否加 take markers（非 SINGLE 才加）
  WRITE_GLUE_CUES = 1,

  -- Policies when TRACK FX are NOT being printed:
  GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX   = "preserve",   -- "preserve" | "force_multi"
  RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve",   -- "preserve" | "force_multi"
}

------------------------------------------------------------
-- ExtState helpers (project-scope)
------------------------------------------------------------
local function get_proj() return 0 end

local function get_ext(key, fallback)
  local _, v = r.GetProjExtState(get_proj(), NS, key)
  if v == nil or v == "" then return fallback end
  return v
end

local function get_ext_bool(key, fallback_bool)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_bool and 1 or 0 end
  v = tostring(v)
  if v == "1" or v:lower()=="true" then return 1 end
  return 0
end

local function get_ext_num(key, fallback_num)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_num end
  local n = tonumber(v)
  return n or fallback_num
end

local function set_ext(key, val)
  r.SetProjExtState(get_proj(), NS, key, tostring(val))
end

function M.read_settings()
  return {
    GLUE_SINGLE_ITEMS  = (get_ext_bool("GLUE_SINGLE_ITEMS",  DEFAULTS.GLUE_SINGLE_ITEMS)==1),
    HANDLE_MODE        = get_ext("HANDLE_MODE",              DEFAULTS.HANDLE_MODE),
    HANDLE_SECONDS     = get_ext_num("HANDLE_SECONDS",       DEFAULTS.HANDLE_SECONDS),
    EPSILON_MODE       = get_ext("EPSILON_MODE",             DEFAULTS.EPSILON_MODE),
    EPSILON_VALUE      = get_ext_num("EPSILON_VALUE",        DEFAULTS.EPSILON_VALUE),
    DEBUG_LEVEL        = get_ext_num("DEBUG_LEVEL",          DEFAULTS.DEBUG_LEVEL),
    GLUE_TAKE_FX       = (get_ext_bool("GLUE_TAKE_FX",      DEFAULTS.GLUE_TAKE_FX)==1),
    GLUE_TRACK_FX      = (get_ext_bool("GLUE_TRACK_FX",     DEFAULTS.GLUE_TRACK_FX)==1),
    GLUE_APPLY_MODE    =  get_ext("GLUE_APPLY_MODE",        DEFAULTS.GLUE_APPLY_MODE),

    RENDER_TAKE_FX     = (get_ext_bool("RENDER_TAKE_FX",    DEFAULTS.RENDER_TAKE_FX)==1),
    RENDER_TRACK_FX    = (get_ext_bool("RENDER_TRACK_FX",   DEFAULTS.RENDER_TRACK_FX)==1),
    RENDER_APPLY_MODE  =  get_ext("RENDER_APPLY_MODE",      DEFAULTS.RENDER_APPLY_MODE),
    -- TR embed mode for Render: "previous" | "current" | "off"
    RENDER_TC_EMBED    = get_ext("RENDER_TC_EMBED", "previous"),
    RENAME_OP_MODE     = get_ext("RENAME_OP_MODE",           DEFAULTS.RENAME_OP_MODE),
    WRITE_EDGE_CUES    = (get_ext_bool("WRITE_EDGE_CUES",   DEFAULTS.WRITE_EDGE_CUES)==1),
    -- 🔧 修正：用 DEFAULTS，不是 dflt
    WRITE_GLUE_CUES    = (get_ext_bool("WRITE_GLUE_CUES", DEFAULTS.WRITE_GLUE_CUES)==1),

    GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX   = get_ext("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX",   DEFAULTS.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX),
    RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = get_ext("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", DEFAULTS.RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX),

    DEBUG_NO_CLEAR = (get_ext_bool("DEBUG_NO_CLEAR", false) == 1),
  }

end

------------------------------------------------------------
-- Utility / Logging
------------------------------------------------------------
local function printf(fmt, ...) r.ShowConsoleMsg(string.format(fmt.."\n", ...)) end
local function dbg(level, want, ...) if level>=want then printf(...) end end

local function frames_to_seconds(frames, sr, fps)
  local fr = (r.TimeMap_curFrameRate and r.TimeMap_curFrameRate(0) or 24.0)
  return (frames or 1) / (fr>0 and fr or 24.0)
end

local function get_sr()
  return r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
end

local function add_take_marker_at(item, rel_pos_sec, label)
  local take = r.GetActiveTake(item)
  if not take then return end
  r.SetTakeMarker(take, -1, label or "", rel_pos_sec, 0) -- -1 append
end


-- 取 base/ext（若無副檔名則 ext=""）
local function split_ext(s)
  local base, ext = s:match("^(.*)(%.[^%./\\]+)$")
  if not base then return s or "", "" end
  return base, ext
end

-- 移除尾端標籤：-takefx / -trackfx / -renderedN（僅針對字尾，避免中段誤刪）
local function strip_tail_tags(s)
  s = s or ""
  while true do
    local before = s
    s = s:gsub("%-takefx$", "")
    s = s:gsub("%-trackfx$", "")
    s = s:gsub("%-rendered%d+$", "")
    s = s:gsub("%-$","")  -- 若剛好留下尾端 '-'，順手清掉
    if s == before then break end
  end
  return s
end

-- 取名字中的 renderedN（僅字尾，允許後面跟 -takefx/-trackfx 再抽回去）
local function extract_rendered_n(name)
  local b = split_ext(name)
  -- 先暫時移除尾端 -takefx/-trackfx，抓 renderedN
  local t = b:gsub("%-takefx$",""):gsub("%-trackfx$","")
  t = t:gsub("%-takefx$",""):gsub("%-trackfx$","")
  local n = t:match("%-rendered(%d+)$")
  return tonumber(n or 0) or 0
end

-- 掃「同一個 item 的所有 takes」找出已存在的最大 renderedN
local function max_rendered_n_on_item(it)
  local maxn = 0
  local tc = reaper.CountTakes(it)
  for i = 0, tc-1 do
    local tk = reaper.GetTake(it, i)
    local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
    local n = extract_rendered_n(nm or "")
    if n > maxn then maxn = n end
  end
  return maxn
end

-- 只改「新產生的 rendered take」的名稱；舊 take 不動
-- base 用「render 前的舊 take 名稱（去掉既有 suffix）」；ext 用「新 take 現名的副檔名」
local function rename_new_render_take(it, orig_take_name, want_takefx, want_trackfx, DBG)
  if not it then return end
  local tc = reaper.CountTakes(it)
  if tc == 0 then return end

  -- New take is appended last (usually becomes active)
  local newtk = reaper.GetTake(it, tc-1)
  if not newtk then return end

  -- Current new-take name (only for logging)
  local _, curNewName = reaper.GetSetMediaItemTakeInfo_String(newtk, "P_NAME", "", false)

  -- Base = old take name without any tail tags and without extension
  local baseOld = strip_tail_tags(select(1, split_ext(orig_take_name or "")))

  -- N = max existing rendered index on this item + 1
  local nextN = max_rendered_n_on_item(it) + 1

  -- Final rule: TakeName-renderedN  (no -takefx/-trackfx, no extension)
  local newname = string.format("%s-rendered%d", baseOld, nextN)

  reaper.GetSetMediaItemTakeInfo_String(newtk, "P_NAME", newname, true)
  dbg(DBG, 1, "[NAME] new take rename '%s' → '%s'", tostring(curNewName or ""), tostring(newname))
end


-- 只快照「offline」布林，不記 bypass
local function snapshot_takefx_offline(tk)
  local n = r.TakeFX_GetCount(tk) or 0
  local snap = {}
  for i = 0, n-1 do
    snap[i] = r.TakeFX_GetOffline(tk, i) and true or false
  end
  return snap
end

-- 暫時把「原本不是 offline」的 FX 設為 offline（不動原本就 offline 的）
local function temp_offline_nonoffline_fx(tk)
  local n = r.TakeFX_GetCount(tk) or 0
  local cnt = 0
  for i = 0, n-1 do
    if not r.TakeFX_GetOffline(tk, i) then
      r.TakeFX_SetOffline(tk, i, true)
      cnt = cnt + 1
    end
  end
  return cnt
end

-- 依快照還原 offline 狀態
local function restore_takefx_offline(tk, snap)
  if not (tk and snap) then return 0 end
  local n = r.TakeFX_GetCount(tk) or 0
  local cnt = 0
  for i = 0, n-1 do
    local want = snap[i]
    if want ~= nil then
      r.TakeFX_SetOffline(tk, i, want and true or false)
      cnt = cnt + 1
    end
  end
  return cnt
end

-- -- Fade snapshot helpers -----------------------------------------
local function snapshot_fades(it)
  return {
    inLen   = r.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0.0,
    outLen  = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0.0,
    inAuto  = r.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO") or 0.0,
    outAuto = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") or 0.0,
    inShape = r.GetMediaItemInfo_Value(it, "C_FADEINSHAPE") or 0,
    outShape= r.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") or 0,
    inDir   = r.GetMediaItemInfo_Value(it, "C_FADEINDIR") or 0.0,
    outDir  = r.GetMediaItemInfo_Value(it, "C_FADEOUTDIR") or 0.0,
  }
end

local function zero_fades(it)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", 0.0)
end

local function restore_fades(it, f)
  if not f then return end
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN",        f.inLen)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN",       f.outLen)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO",   f.inAuto)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO",  f.outAuto)
  r.SetMediaItemInfo_Value(it, "C_FADEINSHAPE",      f.inShape)
  r.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE",     f.outShape)
  r.SetMediaItemInfo_Value(it, "C_FADEINDIR",        f.inDir)
  r.SetMediaItemInfo_Value(it, "C_FADEOUTDIR",       f.outDir)
end

------------------------------------------------------------
-- Selection / grouping helpers
------------------------------------------------------------
local function count_selected_items() return r.CountSelectedMediaItems(0) end
local function get_sel_items()
  local t, n = {}, r.CountSelectedMediaItems(0)
  for i=0,n-1 do t[#t+1] = r.GetSelectedMediaItem(0,i) end
  return t
end

local function item_span(it)
  local pos = r.GetMediaItemInfo_Value(it,"D_POSITION")
  local len = r.GetMediaItemInfo_Value(it,"D_LENGTH")
  return pos, pos+len, len
end

local function get_take_name(it)
  local tk = r.GetActiveTake(it)
  if not tk then return nil end
  local _, nm = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return nm
end

local function set_take_name(it, newn)
  local tk = r.GetActiveTake(it)
  if tk and newn and newn~="" then
    r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", newn, true)
  end
end

local function select_only_items(items)
  r.SelectAllMediaItems(0,false)
  for _,it in ipairs(items) do
    if r.ValidatePtr2(0,it,"MediaItem*") then r.SetMediaItemSelected(it, true) end
  end
  r.UpdateArrange()
end

local function find_item_by_span_on_track(tr, L, R, tol)
  tol = tol or 0.002
  local n = r.CountTrackMediaItems(tr)
  for i=0,n-1 do
    local it = r.GetTrackMediaItem(tr,i)
    local p0,p1 = item_span(it)
    if math.abs(p0-L)<=tol and math.abs(p1-R)<=tol then return it end
  end
  return nil
end

------------------------------------------------------------
-- Unit detection (same track)
------------------------------------------------------------
local function sort_items_by_pos(items)
  table.sort(items, function(a,b)
    local aL = r.GetMediaItemInfo_Value(a,"D_POSITION")
    local bL = r.GetMediaItemInfo_Value(b,"D_POSITION")
    if aL~=bL then return aL<bL end
    local aR = aL + r.GetMediaItemInfo_Value(a,"D_LENGTH")
    local bR = bL + r.GetMediaItemInfo_Value(b,"D_LENGTH")
    return aR<bR
  end)
end

local function detect_units_same_track(items, eps_s)
  local units = {}
  if #items==0 then return units end
  sort_items_by_pos(items)

  local i=1
  while i<=#items do
    local a = items[i]
    local aL,aR = item_span(a)
    if i==#items then
      units[#units+1] = {kind="SINGLE", members={{it=a,L=aL,R=aR}}, start=aL, finish=aR}
      break
    end

    local members = { {it=a,L=aL,R=aR} }
    local anyTouch, anyOverlap = false, false
    local cur_start, cur_end = aL, aR

    local j=i+1
    while j<=#items do
      local itj = items[j]
      local L,R = item_span(itj)
      if L - cur_end > eps_s then break end
      if L >= cur_end - eps_s and L <= cur_end + eps_s then anyTouch=true end
      if L <  cur_end - eps_s then anyOverlap=true end
      members[#members+1] = {it=itj,L=L,R=R}
      if R>cur_end then cur_end=R end
      j=j+1
    end

    local kind
    if #members==1 then kind="SINGLE"
    elseif anyOverlap and anyTouch then kind="MIXED"
    elseif anyOverlap then kind="CROSSFADE"
    else kind="TOUCH" end

    units[#units+1] = {kind=kind, members=members, start=cur_start, finish=cur_end}
    i=j
  end
  return units
end

local function collect_by_track_from_selection()
  local by_tr, tracks = {}, {}
  local sel = get_sel_items()
  for _,it in ipairs(sel) do
    local tr = r.GetMediaItem_Track(it)
    if not by_tr[tr] then by_tr[tr]={}; tracks[#tracks+1]=tr end
    by_tr[tr][#by_tr[tr]+1] = it
  end
  table.sort(tracks, function(a,b)
    return (r.GetMediaTrackInfo_Value(a,"IP_TRACKNUMBER") or 0) < (r.GetMediaTrackInfo_Value(b,"IP_TRACKNUMBER") or 0)
  end)
  return by_tr, tracks
end

-- Time Selection helpers --------------------------------------------
local function get_current_ts()
  local L, R = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has = (R - L) > 1e-9
  return L, R, has
end

local function span_of_selected_items()
  local items = get_sel_items()
  if #items == 0 then return nil, nil, 0 end
  local L, R = math.huge, -math.huge
  for _, it in ipairs(items) do
    local iL, iR = item_span(it)
    if iL < L then L = iL end
    if iR > R then R = iR end
  end
  if L == math.huge then return nil, nil, 0 end
  return L, R, #items
end

local function approximately_equal_span(aL, aR, bL, bR, tol)
  tol = tol or 0.002
  return (math.abs((aL or 0) - (bL or 0)) <= tol)
     and (math.abs((aR or 0) - (bR or 0)) <= tol)
end

local function item_intersects_ts(it, L, R)
  local iL, iR = item_span(it)
  return (iR > L) and (iL < R)
end

local function collect_items_intersect_ts_by_track(tsL, tsR)
  local by_tr, tracks = {}, {}
  local sel = get_sel_items()
  for _, it in ipairs(sel) do
    if item_intersects_ts(it, tsL, tsR) then
      local tr = r.GetMediaItem_Track(it)
      if not by_tr[tr] then by_tr[tr] = {}; tracks[#tracks+1] = tr end
      by_tr[tr][#by_tr[tr]+1] = it
    end
  end
  table.sort(tracks, function(a,b)
    return (r.GetMediaTrackInfo_Value(a,"IP_TRACKNUMBER") or 0) < (r.GetMediaTrackInfo_Value(b,"IP_TRACKNUMBER") or 0)
  end)
  return by_tr, tracks
end
------------------------------------------------------------
-- Handle window / clamp
------------------------------------------------------------
local function per_member_window_lr(it, L, R, H_left, H_right)
  local tk   = r.GetActiveTake(it)
  local rate = tk and (r.GetMediaItemTakeInfo_Value(tk,"D_PLAYRATE") or 1.0) or 1.0
  local offs = tk and (r.GetMediaItemTakeInfo_Value(tk,"D_STARTOFFS") or 0.0) or 0.0
  local src  = tk and r.GetMediaItemTake_Source(tk) or nil
  local src_len = src and ({r.GetMediaSourceLength(src)})[1] or math.huge

  local cur_len = R - L

  local max_left_ext  = offs / rate
  local wantL         = L - (H_left or 0.0)
  local gotL          = (wantL < (L - max_left_ext)) and (L - max_left_ext) or wantL

  local max_right_ext = ((src_len - offs) / rate) - cur_len
  if max_right_ext < 0 then max_right_ext = 0 end
  local wantR = R + (H_right or 0.0)
  local gotR  = (wantR > (R + max_right_ext)) and (R + max_right_ext) or wantR

  local clampL = (gotL > wantL + 1e-9)
  local clampR = (gotR < wantR - 1e-9)

  return {
    tk=tk, rate=rate, offs=offs,
    L=L, R=R, wantL=wantL, wantR=wantR, gotL=gotL, gotR=gotR,
    clampL=clampL, clampR=clampR,
    leftH=H_left or 0.0, rightH=H_right or 0.0,
    name=get_take_name(it)
  }
end

------------------------------------------------------------
-- #in/#out edge cues (kept for media-cue workflows)
------------------------------------------------------------
local function add_edge_cues(UL, UR, color)
  local proj = 0
  color = color or 0
  local in_id  = r.AddProjectMarker2(proj, false, UL, 0, "#in",  -1, color)
  local out_id = r.AddProjectMarker2(proj, false, UR, 0, "#out", -1, color)
  return {in_id, out_id}
end

local function remove_markers_by_ids(ids)
  if not ids then return end
  local proj = 0
  for _,id in ipairs(ids) do r.DeleteProjectMarker(proj, id, false) end
end

--[[
------------------------------------------------------------
-- Rename helpers
------------------------------------------------------------
local function strip_suffixes(base)
  if not base then return base, 0, false, false end
  local n=0
  base = base:gsub("[-_]TakeFX_TrackFX$", function() return "" end)
  base = base:gsub("[-_]TrackFX$",        function() return "" end)
  base = base:gsub("[-_]TakeFX$",         function() return "" end)
  base = base:gsub("[-_]rendered(%d+)$",  function(d) n=tonumber(d) or n; return "" end)
  base = base:gsub("[-_]glued(%d+)$",     function(d) n=tonumber(d) or n; return "" end)
  return base, n, false, false
end

-- 把 -takefx / -trackfx 插在真正的音訊副檔名（.wav/.aif/.aiff/...）之前
-- 若找不到副檔名，就附加在字串尾端。已存在就不重複加（冪等）。
local _KNOWN_EXTS = { ".wav", ".aif", ".aiff", ".flac", ".mp3", ".ogg", ".wv", ".caf", ".m4a" }

local function _split_name_by_audio_ext(nm)
  if not nm or nm == "" then return "", "", "" end
  local lower = string.lower(nm)
  local s_best, e_best = nil, nil
  for _, ext in ipairs(_KNOWN_EXTS) do
    local s, e = 1, 0
    while true do
      s, e = lower:find(ext, e + 1, true)
      if not s then break end
      s_best, e_best = s, e
    end
  end
  if s_best then
    -- stem | .ext | tail（例如 "foo" | ".wav" | "-rendered1-TrackFX"）
    return nm:sub(1, s_best - 1), nm:sub(s_best, e_best), nm:sub(e_best + 1)
  else
    return nm, "", ""
  end
end

local function _has_tag_in_stem(stem, tag)
  if not stem or stem == "" then return false end
  return stem:lower():find("-" .. tag:lower(), 1, true) ~= nil
end

local function _add_tag_once_in_stem(stem, tag)
  if _has_tag_in_stem(stem, tag) then return stem end
  return (stem or "") .. "-" .. tag
end

-- op 參數保留相容性；實際不再分 glue/render 模式
function compute_new_name(op, oldn, flags)
  local stem, ext, tail = _split_name_by_audio_ext(oldn or "")

  local want_take  = flags and flags.takePrinted  == true
  local want_track = flags and flags.trackPrinted == true

  -- 固定順序：takefx → trackfx
  if want_take  then stem = _add_tag_once_in_stem(stem, "takefx")  end
  if want_track then stem = _add_tag_once_in_stem(stem, "trackfx") end

  return stem .. ext .. tail
end
]]--

------------------------------------------------------------
-- FX utilities
------------------------------------------------------------
local function get_apply_cmd(mode) return (mode=="multi") and ACT_APPLY_MULTI or ACT_APPLY_MONO end

local function clear_take_fx_for_items(items)
  if #items==0 then return end
  select_only_items(items)
  r.Main_OnCommand(ACT_REMOVE_TAKE_FX, 0)
end

local function apply_track_take_fx_to_item(it, apply_mode, dbg_level)
  r.SelectAllMediaItems(0,false)
  r.SetMediaItemSelected(it,true)
  local cmd = get_apply_cmd(apply_mode)
  dbg(dbg_level,1,"[RUN] Apply Track/Take FX (%s) to 1 item.", apply_mode)
  r.Main_OnCommand(cmd, 0)
end

-- Disable all TRACK FX on a track and return a snapshot of enabled states
local function disable_trackfx_with_snapshot(tr)
  if not tr then return nil end
  local n = r.TrackFX_GetCount(tr) or 0
  local snap = {}
  for i = 0, n-1 do
    local on = r.TrackFX_GetEnabled(tr, i)
    snap[i] = on and true or false
    if on then r.TrackFX_SetEnabled(tr, i, false) end
  end
  return snap
end

local function restore_trackfx_from_snapshot(tr, snap)
  if not (tr and snap) then return end
  for i, on in pairs(snap) do r.TrackFX_SetEnabled(tr, i, on and true or false) end
end

-- Apply multichannel (41993) WITHOUT baking any TRACK FX, and only bake TAKE FX when keep_take_fx=true
local function apply_multichannel_no_fx_preserve_take(it, keep_take_fx, dbg_level)
  if not it then return end
  local tr = r.GetMediaItem_Track(it)
  local tk = r.GetActiveTake(it)

  local tr_snap = disable_trackfx_with_snapshot(tr)
  local tk_snap = snapshot_takefx_offline(tk)
  if tk and (not keep_take_fx) then
    temp_offline_nonoffline_fx(tk)
  end

  local fade_snap = snapshot_fades(it)
  zero_fades(it)

  r.SelectAllMediaItems(0,false)
  r.SetMediaItemSelected(it,true)
  dbg(dbg_level,1,"[APPLY] multi(no-FX) via 41993 (keep_take_fx=%s)", tostring(keep_take_fx))
  r.Main_OnCommand(ACT_APPLY_MULTI, 0)

  -- restore states
  restore_trackfx_from_snapshot(tr, tr_snap)
  restore_takefx_offline(tk, tk_snap)
  restore_fades(it, fade_snap)
end

-- Central helper: embed CURRENT BWF TimeReference for a given item/take
-- Used after GLUE + Apply (40361/41993) to emulate native Glue behavior.
local function embed_current_tc_for_item(item, ref_pos, DBG)
  if not (item and ref_pos) then return end
  local tk = r.GetActiveTake(item)
  if not tk then return end
  local smp = E.TR_FromItemStart(tk, ref_pos)
  local src = r.GetMediaItemTake_Source(tk)
  local path = src and r.GetMediaSourceFileName(src, "") or ""
  if path ~= "" and path:lower():sub(-4) == ".wav" then
    local ok = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
    if DBG and DBG >= 2 then dbg(DBG, 2, "[TR][EMBED] current write=%s  samples=%d  path=%s", tostring(ok), smp, path) end
    -- Force REAPER to reload newly embedded metadata (offline -> online)
    if ok then
      E.Refresh_Items({ tk })
      if DBG and DBG >= 2 then dbg(DBG, 2, "[TR][REFRESH] toggled offline/online for 1 take") end
    end
  end
end
------------------------------------------------------------
-- GLUE FLOW (per unit)
------------------------------------------------------------
local function glue_unit(tr, u, cfg)
  local DBG    = cfg.DEBUG_LEVEL or 1
  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0
  local eps_s  = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  -- Special handling for GAP units (multiple items with gaps)
  -- Use simplified glue without handle extension (like native 42432)
  if u.kind == "GAP" then
    dbg(DBG,1,"[RUN] GAP unit: %d items, span=%.3f..%.3f (using native glue behavior)", #u.members, u.start, u.finish)

    -- Select all items (without modification)
    local items_sel = {}
    for i,m in ipairs(u.members) do items_sel[i]=m.it end
    select_only_items(items_sel)

    -- Clear take FX if policy says so
    if not cfg.GLUE_TAKE_FX then
      clear_take_fx_for_items(items_sel)
      dbg(DBG,1,"[TAKE-FX] cleared (policy=OFF) for GAP unit.")
    end

    -- Set TS to overall span and glue
    r.GetSet_LoopTimeRange(true, false, u.start, u.finish, false)
    r.Main_OnCommand(ACT_GLUE_TS, 0)

    -- Find glued item
    local glued = find_item_by_span_on_track(tr, u.start, u.finish, 0.002)
    if glued and cfg.GLUE_TRACK_FX then
      r.SetMediaItemInfo_Value(glued, "D_FADEINLEN", 0)
      r.SetMediaItemInfo_Value(glued, "D_FADEINLEN_AUTO", 0)
      r.SetMediaItemInfo_Value(glued, "D_FADEOUTLEN", 0)
      r.SetMediaItemInfo_Value(glued, "D_FADEOUTLEN_AUTO", 0)
      apply_track_take_fx_to_item(glued, cfg.GLUE_APPLY_MODE, DBG)
      embed_current_tc_for_item(glued, u.start, DBG)
    elseif glued
       and (cfg.GLUE_APPLY_MODE == "multi")
       and (cfg.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi") then
      apply_multichannel_no_fx_preserve_take(glued, (cfg.GLUE_TAKE_FX == true), DBG)
      embed_current_tc_for_item(glued, u.start, DBG)
    end

    r.GetSet_LoopTimeRange(true, false, 0, 0, false)
    dbg(DBG,1,"[RUN] GAP unit glued: %.3f..%.3f", u.start, u.finish)
    return
  end

  -- Prepare Glue Cues plan (absolute project times).
  -- Rule: write a cue only when adjacent items switch to a different file source.
  -- If the whole unit uses a single source, write none (including the head).
  local marks_abs = nil
  if u.kind ~= "SINGLE" then
    -- Build ordered source sequence for this unit
    local function src_path_of(it)
      local tk  = reaper.GetActiveTake(it)
      if not tk then return nil end
      local src = reaper.GetMediaItemTake_Source(tk)
      if not src then return nil end
      local p   = reaper.GetMediaSourceFileName(src, "") or ""
      p = p:gsub("\\","/"):gsub("^%s+",""):gsub("%s+$","")
      return (p ~= "") and p or nil
    end

    local function take_name_of(it)
      local tk = reaper.GetActiveTake(it)
      if not tk then return nil end
      local ok, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
      return (ok and nm ~= "" and nm) or reaper.GetTakeName(tk) or nil
    end
    local seq, uniq = {}, {}
    for _, m in ipairs(u.members or {}) do
      local p = src_path_of(m.it) or ("<no-src>")
      seq[#seq+1] = { L = m.L, path = p }
      uniq[p] = true
    end
    local unique_count = 0
    for _ in pairs(uniq) do unique_count = unique_count + 1 end

    if unique_count >= 2 then
      marks_abs = {}
      -- Head cue uses TakeName (preserve original case)
      local head_name = take_name_of(u.members[1].it) or ((seq[1].path or ""):match("([^/]+)$") or "")
      marks_abs[#marks_abs+1] = { abs = u.start, name = head_name }

      -- Boundary cues where source changes
      for i = 1, (#seq - 1) do
        if seq[i].path ~= seq[i+1].path then
          local next_name = take_name_of(u.members[i+1].it) or ((seq[i+1].path or ""):match("([^/]+)$") or "")
          marks_abs[#marks_abs+1] = { abs = seq[i+1].L, name = next_name }
        end
      end
    end
  end

  -- 保存左右邊界淡入淡出（之後還原）
  local members = {}
  for i,m in ipairs(u.members) do members[i]=m end
  local first_it = members[1] and members[1].it or nil
  local last_it  = members[#members] and members[#members].it or nil

  local fin_len, fin_dir, fin_shape, fin_auto = 0,0,0,0
  local fout_len, fout_dir, fout_shape, fout_auto = 0,0,0,0
  if first_it then
    fin_len   = r.GetMediaItemInfo_Value(first_it,"D_FADEINLEN") or 0
    fin_dir   = r.GetMediaItemInfo_Value(first_it,"D_FADEINDIR") or 0
    fin_shape = r.GetMediaItemInfo_Value(first_it,"C_FADEINSHAPE") or 0
    fin_auto  = r.GetMediaItemInfo_Value(first_it,"D_FADEINLEN_AUTO") or 0
  end
  if last_it then
    fout_len   = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTLEN") or 0
    fout_dir   = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTDIR") or 0
    fout_shape = r.GetMediaItemInfo_Value(last_it,"C_FADEOUTSHAPE") or 0
    fout_auto  = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTLEN_AUTO") or 0
  end

  -- 計算 UL/UR（handles + clamp）
  -- If TS exists and its edge is outside unit edge, extend handle to TS edge
  local tsL, tsR, hasTS = get_current_ts()

  -- Calculate unit's natural span (before handles)
  local unitL, unitR = math.huge, -math.huge
  for _, m in ipairs(members) do
    if m.L < unitL then unitL = m.L end
    if m.R > unitR then unitR = m.R end
  end

  -- Debug: show TS vs unit relationship
  if hasTS then
    dbg(DBG,1,"[TS-UNIT] TS=%.3f..%.3f, unit=%.3f..%.3f, eps=%.5f", tsL, tsR, unitL, unitR, eps_s)
    local ts_left_at_or_outside = (tsL <= unitL + eps_s)  -- At edge or outside
    local ts_right_at_or_outside = (tsR >= unitR - eps_s)  -- At edge or outside
    dbg(DBG,1,"[TS-UNIT] TS_left %s unit_left (%.3f %s %.3f), TS_right %s unit_right (%.3f %s %.3f)",
        ts_left_at_or_outside and "AT/OUTSIDE" or "INSIDE",
        tsL, ts_left_at_or_outside and "<=" or ">", unitL + eps_s,
        ts_right_at_or_outside and "AT/OUTSIDE" or "INSIDE",
        tsR, ts_right_at_or_outside and ">=" or "<", unitR - eps_s)
  else
    dbg(DBG,1,"[TS-UNIT] No TS, unit=%.3f..%.3f", unitL, unitR)
  end

  -- Determine handle size for each edge
  -- NEW LOGIC: Only apply handles when TS exactly equals unit edges (both sides aligned)
  local H_left_final = 0.0
  local H_right_final = 0.0

  if hasTS then
    -- Check if TS equals unit on both sides (within epsilon)
    local ts_equals_unit_left  = math.abs(tsL - unitL) <= eps_s
    local ts_equals_unit_right = math.abs(tsR - unitR) <= eps_s
    local ts_equals_unit = ts_equals_unit_left and ts_equals_unit_right

    if ts_equals_unit then
      -- TS exactly matches unit → apply default handles
      H_left_final = HANDLE
      H_right_final = HANDLE
      dbg(DBG,1,"[HANDLE] TS=Unit (%.3f..%.3f ≈ %.3f..%.3f) → Left: %.3f, Right: %.3f",
          tsL, tsR, unitL, unitR, H_left_final, H_right_final)
    else
      -- TS doesn't match unit → no handles
      dbg(DBG,1,"[HANDLE] TS≠Unit (TS=%.3f..%.3f, unit=%.3f..%.3f) → No handles (0.0)",
          tsL, tsR, unitL, unitR)
    end
  else
    -- No TS → use default handles
    H_left_final = HANDLE
    H_right_final = HANDLE
    dbg(DBG,1,"[HANDLE] No TS → Left: %.3f, Right: %.3f (config default)", H_left_final, H_right_final)
  end

  local UL, UR = math.huge, -math.huge
  local details = {}
  for idx, m in ipairs(members) do
    local H_left  = (idx==1) and H_left_final or 0.0
    local H_right = (idx==#members) and H_right_final or 0.0
    local d = per_member_window_lr(m.it, m.L, m.R, H_left, H_right)
    UL = math.min(UL, d.gotL)
    UR = math.max(UR, d.gotR)
    details[idx] = d
  end

  dbg(DBG,1,"[RUN] unit kind=%s members=%d UL=%.3f UR=%.3f dur=%.3f", u.kind,#members,UL,UR,UR-UL)
  if DBG>=2 then
    for i,d in ipairs(details) do
      dbg(DBG,2,"       member#%d want=%.3f..%.3f -> got=%.3f..%.3f  clampL=%s clampR=%s  name=%s",
        i, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), d.name or "(none)")
    end
  end

  -- RENDER_TAKE_FX=0 → 先清空成員的 take FX（避免被 Glue 印入）
  if not cfg.GLUE_TAKE_FX then
    local items = {}
    for i,m in ipairs(members) do items[i]=m.it end
    clear_take_fx_for_items(items)
    dbg(DBG,1,"[TAKE-FX] cleared (policy=OFF) for this unit.")
  end

  -- Write #in/#out (unit span) as media cues when enabled
  local edge_ids = nil
  if cfg.WRITE_EDGE_CUES then
    edge_ids = add_edge_cues(u.start, u.finish, 0)
    dbg(DBG,1,"[EDGE-CUE] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", u.start, u.finish, tostring(edge_ids[1]), tostring(edge_ids[2]))
  end

  -- When enabled, pre-embed Glue Cues as project markers (with '#' prefix).
  -- They will be absorbed into the new media during glue.
  -- Pre-embed Glue cues as project markers (with '#') so glue absorbs them into media
  local glue_ids = nil
  if cfg.WRITE_GLUE_CUES and u.kind ~= "SINGLE" and marks_abs and #marks_abs > 0 then
    glue_ids = {}
    for _, mk in ipairs(marks_abs) do
      local raw = mk.name or mk.stem or mk.label or ""
      raw = raw:gsub("^%s*GlueCue:%s*", "")  -- strip legacy prefix if any
      local label = ("#Glue: %s"):format(raw)
      local id = reaper.AddProjectMarker2(0, false, mk.abs or u.start, 0, label, -1, 0)
      glue_ids[#glue_ids+1] = id
      if DBG >= 2 then dbg(DBG,2,"[GLUE-CUE] add @ %.3f  label=%s  id=%s", mk.abs or u.start, label, tostring(id)) end
    end
  end




  -- 選取並暫時把左右最外側 item 撐到 UL/UR 以吃到 handles
  local items_sel = {}
  for i,m in ipairs(members) do items_sel[i]=m.it end
  select_only_items(items_sel)

  for idx, m in ipairs(members) do
    local it = m.it
    local d  = details[idx]
    local newL = (idx==1) and d.gotL or m.L
    local newR = (idx==#members) and d.gotR or m.R
    r.SetMediaItemInfo_Value(it,"D_POSITION", newL)
    r.SetMediaItemInfo_Value(it,"D_LENGTH",   newR - newL)

    -- CRITICAL: Adjust D_STARTOFFS when extending LEFT
    -- When item extends left (e.g., from 16.458 to 11.458), we need to adjust offset
    -- so that the extended portion reads from earlier in the source.
    -- Formula: new_offset = old_offset - (left_extension * playrate)
    if d.tk and idx == 1 then
      local deltaL = (m.L - newL)
      if deltaL > eps_s then
        -- Left side extended, adjust offset
        local new_off = d.offs - (deltaL * d.rate)
        r.SetMediaItemTakeInfo_Value(d.tk,"D_STARTOFFS", new_off)
        dbg(DBG,1,"[PRE-GLUE] member#%d: extended LEFT by %.3f (%.3f → %.3f)",
            idx, deltaL, m.L, newL)
        dbg(DBG,1,"[PRE-GLUE] Adjusted D_STARTOFFS: %.6f → %.6f (delta=%.6f, rate=%.3f)",
            d.offs, new_off, -deltaL * d.rate, d.rate)
      else
        dbg(DBG,2,"[PRE-GLUE] member#%d: No left extension, keeping original offs=%.6f",
            idx, d.offs)
      end
    end

    if DBG >= 2 and idx == #members then
      local deltaR = (newR - m.R)
      if deltaR > eps_s then
        dbg(DBG,2,"[PRE-GLUE] member#%d: extended RIGHT by %.3f (%.3f → %.3f)",
            idx, deltaR, m.R, newR)
      end
    end
  end

  -- 時選=UL..UR → Glue → (必要時)對成品 Apply → Trim 回 UL..UR
  r.GetSet_LoopTimeRange(true, false, UL, UR, false)
  r.Main_OnCommand(ACT_GLUE_TS, 0)

  local glued_pre = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if cfg.GLUE_TRACK_FX and glued_pre then
    -- 清掉 fades（40361/41993 會把 fade 烘進音檔）
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN",       0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN_AUTO",  0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN",      0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN_AUTO", 0)

    apply_track_take_fx_to_item(glued_pre, cfg.GLUE_APPLY_MODE, DBG)
    -- Emulate Glue’s TC when GLUE+APPLY: embed CURRENT TC at unit start
    embed_current_tc_for_item(glued_pre, u.start, DBG)

  elseif glued_pre
     and (cfg.GLUE_APPLY_MODE == "multi")
     and (cfg.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi") then
    -- TRACK FX 未印，但需要強制 multi：以「無 FX」方式套 41993
    apply_multichannel_no_fx_preserve_take(glued_pre, (cfg.GLUE_TAKE_FX == true), DBG)
    -- Emulate Glue’s TC in force-multi no-track-FX path as well
    embed_current_tc_for_item(glued_pre, u.start, DBG)
  end

  r.Main_OnCommand(ACT_TRIM_TO_TS, 0)

  -- 找到最後成品（UL..UR），移回 u.start..u.finish 並寫入 offset
  local glued = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if glued then
    local left_total  = u.start - UL
    local right_total = UR - u.finish
    if left_total  < 0 then left_total  = 0 end
    if right_total < 0 then right_total = 0 end

    r.SetMediaItemInfo_Value(glued,"D_POSITION", u.start)
    r.SetMediaItemInfo_Value(glued,"D_LENGTH",   u.finish - u.start)
    local gtk = r.GetActiveTake(glued)
    if gtk then r.SetMediaItemTakeInfo_Value(gtk,"D_STARTOFFS", left_total) end
    r.UpdateItemInProject(glued)

    -- NEW: keep StartInSource consistent across ALL takes on the glued item
    do
      local tc = reaper.CountTakes(glued) or 0
      for ti = 0, tc-1 do
        local tk = reaper.GetTake(glued, ti)
        if tk then
          reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", left_total)
        end
      end
    end

    -- 還原邊界淡入淡出
    r.SetMediaItemInfo_Value(glued,"D_FADEINLEN",      fin_len)
    r.SetMediaItemInfo_Value(glued,"D_FADEINDIR",      fin_dir)
    r.SetMediaItemInfo_Value(glued,"C_FADEINSHAPE",    fin_shape)
    r.SetMediaItemInfo_Value(glued,"D_FADEINLEN_AUTO", fin_auto)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTLEN",      fout_len)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTDIR",      fout_dir)
    r.SetMediaItemInfo_Value(glued,"C_FADEOUTSHAPE",    fout_shape)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTLEN_AUTO", fout_auto)
    r.UpdateItemInProject(glued)

    -- (Removed legacy take-marker emission. Glue cues are now pre-written as project markers with '#'.)


    -- [GLUE NAME] Do not rename glued items; let REAPER auto-name (e.g. "...-glued-XX").
    -- (Intentionally no-op here to preserve REAPER's default glued naming.)
    -- dbg(DBG,2,"[NAME] Skip renaming glued item; keep REAPER's default.")


    dbg(DBG,1,"       post-glue: trimmed to [%.3f..%.3f], offs=%.3f (L=%.3f R=%.3f)",
      u.start, u.finish, left_total, left_total, right_total)
  else
    dbg(DBG,1,"       WARNING: glued item not found by span (UL=%.3f UR=%.3f)", UL, UR)
  end

  -- Clear time selection and temporary project markers
  r.GetSet_LoopTimeRange(true, false, 0, 0, false)
  if edge_ids then
    remove_markers_by_ids(edge_ids)
    dbg(DBG,1,"[EDGE-CUE] removed ids: %s, %s", tostring(edge_ids[1]), tostring(edge_ids[2]))
  end
  if glue_ids and #glue_ids>0 then
    remove_markers_by_ids(glue_ids)
    dbg(DBG,1,"[GLUE-CUE] removed %d temp markers.", #glue_ids)
  end




end

-- GLUE by explicit Time Selection window for a single track (NO handles; TS-Window parity with AudioSweet). Uses members_snapshot (original selection) to avoid selection churn.
local function glue_by_ts_window_on_track(tr, tsL, tsR, cfg, members_snapshot)
  local DBG = cfg.DEBUG_LEVEL or 1
  -- TS-Window rules:
  --   • No handles
  --   • Never write EDGE_CUES
  --   • WRITE_GLUE_CUES allowed (adjacent-different-source within TS)
  --   • If GLUE_TAKE_FX==false → clear take FX before glue (do not bake take-FX)
  --   • If GLUE_TRACK_FX==1    → Apply after glue (mono/multi/auto); else skip

  dbg(DBG,1,"[TS-GLUE] track#%d  GLUE_TAKE_FX=%s  GLUE_TRACK_FX=%s  apply_mode=%s  write_glue_cues=%s",
      r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1,
      tostring(cfg.GLUE_TAKE_FX), tostring(cfg.GLUE_TRACK_FX),
      tostring(cfg.GLUE_APPLY_MODE), tostring(cfg.WRITE_GLUE_CUES))

  -- use the original selection snapshot for this track (do NOT depend on live selection)
  local members = {}
  if type(members_snapshot) == "table" then
    for _, it in ipairs(members_snapshot) do
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        -- intersect with TS; keep original item span (L/R) and clamped span (iL/iR)
        local L, R = item_span(it)
        if item_intersects_ts(it, tsL, tsR) then
          local iL = (L < tsL) and tsL or L
          local iR = (R > tsR) and tsR or R
          members[#members+1] = { it = it, L = L, R = R, iL = iL, iR = iR }
        end
      end
    end
  end
  if #members == 0 then
    dbg(DBG,1,"[RUN] TS glue: no members on this track.")
    return
  end
  table.sort(members, function(a,b) return a.iL < b.iL end)

  -- SPLIT items at TS boundaries if edges cut through item interior (non-destructive behavior like native glue)
  -- This ensures items outside TS remain intact after glue operation
  local split_threshold = 0.002 -- tolerance for edge detection (2ms)
  for _, m in ipairs(members) do
    local it = m.it
    local L, R = m.L, m.R  -- original item span

    -- Check if tsL cuts through item interior (not at edge)
    if tsL > (L + split_threshold) and tsL < (R - split_threshold) then
      local new_item = r.SplitMediaItem(it, tsL)
      if new_item and DBG >= 2 then
        dbg(DBG, 2, "[TS-SPLIT] Split item at tsL=%.3f (track #%d)", tsL, r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1)
      end
    end

    -- Check if tsR cuts through item interior (not at edge)
    -- Note: After splitting at tsL, we need to find the correct item piece that contains tsR
    if tsR > (L + split_threshold) and tsR < (R - split_threshold) then
      -- Find the item at tsR position (might be the original or the right piece after tsL split)
      local item_at_tsR = nil
      local track_item_count = r.CountTrackMediaItems(tr)
      for i = 0, track_item_count - 1 do
        local candidate = r.GetTrackMediaItem(tr, i)
        local cL, cR = item_span(candidate)
        if cL <= tsR and cR >= tsR then
          item_at_tsR = candidate
          break
        end
      end

      if item_at_tsR then
        local new_item = r.SplitMediaItem(item_at_tsR, tsR)
        if new_item and DBG >= 2 then
          dbg(DBG, 2, "[TS-SPLIT] Split item at tsR=%.3f (track #%d)", tsR, r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1)
        end
      end
    end
  end

  -- After splitting, rebuild members list to include new split items within TS
  members = {}
  if type(members_snapshot) == "table" then
    for _, orig_it in ipairs(members_snapshot) do
      -- Check all items on track (original + splits) that intersect with TS
      local track_item_count = r.CountTrackMediaItems(tr)
      for i = 0, track_item_count - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        if reaper.ValidatePtr2(0, it, "MediaItem*") then
          local L, R = item_span(it)
          if item_intersects_ts(it, tsL, tsR) then
            -- Check if this item is within TS range (fully or partially)
            local iL = (L < tsL) and tsL or L
            local iR = (R > tsR) and tsR or R
            -- Only add if not already in members list
            local already_added = false
            for _, existing in ipairs(members) do
              if existing.it == it then
                already_added = true
                break
              end
            end
            if not already_added then
              members[#members+1] = { it = it, L = L, R = R, iL = iL, iR = iR }
            end
          end
        end
      end
    end
  end
  table.sort(members, function(a,b) return a.iL < b.iL end)

  if DBG >= 1 then
    dbg(DBG, 1, "[TS-GLUE] After boundary splits: %d items to glue within TS [%.3f, %.3f]", #members, tsL, tsR)
  end

  -- Optional: WRITE_GLUE_CUES inside TS when sources switch
  local glue_ids = nil
  if cfg.WRITE_GLUE_CUES and #members >= 2 then
    -- build per-member source id and label
    local function src_key_and_name(it)
      local tk  = r.GetActiveTake(it)
      if not tk then return "<no-src>", (r.GetTakeName and r.GetTakeName(tk)) or "" end
      local src = r.GetMediaItemTake_Source(tk)
      local p   = src and r.GetMediaSourceFileName(src, "") or ""
      p = p:gsub("\\","/"):gsub("^%s+",""):gsub("%s+$","")
      local key = (p ~= "" and p) or "<no-src>"
      local ok, nm = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
      local lbl = (ok and nm ~= "" and nm) or (p:match("([^/]+)$") or "")
      return key, lbl
    end

    local seq = {}
    for _,m in ipairs(members) do
      local key, lbl = src_key_and_name(m.it)
      seq[#seq+1] = { L = m.iL, key = key, label = lbl }
    end

    -- write head + boundaries where source changes
    glue_ids = {}
    if seq[1] then
      local id = r.AddProjectMarker2(0, false, tsL, 0, ("#Glue: %s"):format(seq[1].label or ""), -1, 0)
      glue_ids[#glue_ids+1] = id
    end
    for i=1,(#seq-1) do
      if seq[i].key ~= seq[i+1].key then
        local id = r.AddProjectMarker2(0, false, seq[i+1].L, 0, ("#Glue: %s"):format(seq[i+1].label or ""), -1, 0)
        glue_ids[#glue_ids+1] = id
      end
    end
    if DBG>=2 then dbg(DBG,2,"[GLUE-CUE][TS] wrote %d markers (track #%d)", #glue_ids, r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1) end
  end

  -- select only intersecting members for this track
  local items_sel = {}
  for i, m in ipairs(members) do items_sel[i] = m.it end
  select_only_items(items_sel)

  -- If policy says "do NOT bake take FX", clear take FX before glue
  if not cfg.GLUE_TAKE_FX then
    clear_take_fx_for_items(items_sel)
    dbg(DBG,1,"[TS-GLUE] cleared TAKE FX on %d item(s) (policy off)", #items_sel)
  end

  -- Glue strictly within TS (no handle extension)
  r.GetSet_LoopTimeRange(true, false, tsL, tsR, false)
  r.Main_OnCommand(ACT_GLUE_TS, 0)

  -- Apply (Track/Take) per policy: TS-Window treats GLUE_TAKE_FX as ON by design.
  local glued_pre = find_item_by_span_on_track(tr, tsL, tsR, 0.002)
  if cfg.GLUE_TRACK_FX and glued_pre then
    -- clear fades to avoid baking during apply
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN",       0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN_AUTO",  0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN",      0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN_AUTO", 0)
    apply_track_take_fx_to_item(glued_pre, cfg.GLUE_APPLY_MODE, DBG)
    -- Emulate Glue’s TC when GLUE+APPLY (TS-Window): embed CURRENT TC at tsL
    embed_current_tc_for_item(glued_pre, tsL, DBG)
  elseif glued_pre
     and (cfg.GLUE_APPLY_MODE == "multi")
     and (cfg.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi") then
    apply_multichannel_no_fx_preserve_take(glued_pre, true, DBG)  -- keep take FX
    -- Emulate Glue’s TC in force-multi no-track-FX path as well (TS-Window)
    embed_current_tc_for_item(glued_pre, tsL, DBG)
  end

  -- Ensure exact TS window
  r.GetSet_LoopTimeRange(true, false, tsL, tsR, false)
  r.Main_OnCommand(ACT_TRIM_TO_TS, 0)

  local glued = find_item_by_span_on_track(tr, tsL, tsR, 0.002)
  if glued then
    r.SetMediaItemInfo_Value(glued, "D_POSITION", tsL)
    r.SetMediaItemInfo_Value(glued, "D_LENGTH",   tsR - tsL)
    r.UpdateItemInProject(glued)
  else
    dbg(DBG,1,"[WARN] TS glue: glued item not found by span.")
  end

  -- clear TS and temporary markers
  r.GetSet_LoopTimeRange(true, false, 0, 0, false)
  if glue_ids and #glue_ids>0 then remove_markers_by_ids(glue_ids) end
end
------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------
-- Auto-scope glue: Units vs TS-Window
-- mode: "glue" = always use TS when present (no handles); "auto" = use original logic (units with handles)
local function glue_auto_scope(cfg, mode)
  local DBG = cfg.DEBUG_LEVEL or 1
  local tsL, tsR, hasTS = get_current_ts()
  local selL, selR, nsel = span_of_selected_items()

  if not hasTS then
    dbg(DBG,1,"[SCOPE] TS empty → Units glue.")
    return "units"
  end
  if nsel == 0 then
    dbg(DBG,1,"[SCOPE] No selection but TS present → TS glue.")
    return "ts", tsL, tsR
  end

  -- Both GLUE and AUTO modes: check if TS ≈ selection
  -- If TS ≈ selection → Units glue (with handles)
  -- If TS ≠ selection → TS glue (no handles)
  if approximately_equal_span(tsL, tsR, selL, selR, 0.002) then
    dbg(DBG,1,"[SCOPE] TS ≈ selection span → Units glue (with handles).")
    return "units"
  else
    dbg(DBG,1,"[SCOPE] TS differs from selection → TS glue (no handles).")
    return "ts", tsL, tsR
  end
end

function M.glue_selection(force_units)
  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end

  local nsel = count_selected_items()
  if nsel==0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Glue (no selection)", -1); return
  end

  local eps_s = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  -- Auto mode for glue: infer mono/multi from max item playback channels over current selection
  if cfg.GLUE_APPLY_MODE == "auto" then
    local function get_item_playback_channels(it)
      if not it then return 2 end
      local tk = reaper.GetActiveTake(it)
      if not tk then return 2 end

      -- Check take's channel mode setting (IMPORTANT: use GetMediaItemTakeInfo_Value!)
      local chanmode = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE")
      if chanmode == 2 or chanmode == 3 or chanmode == 4 then return 1 end

      local src = reaper.GetMediaItemTake_Source(tk)
      return src and (reaper.GetMediaSourceNumChannels(src) or 2) or 2
    end
    local maxch = 1
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local it = reaper.GetSelectedMediaItem(0, i)
      local ch = get_item_playback_channels(it)
      if ch > maxch then maxch = ch end
    end
    cfg.GLUE_APPLY_MODE = (maxch >= 2) and "multi" or "mono"
  end

  dbg(DBG,1,"[RUN] Glue start  handles=%.3fs  epsilon=%.5fs  GLUE_SINGLE_ITEMS=%s  GLUE_TAKE_FX=%s  GLUE_TRACK_FX=%s  GLUE_APPLY_MODE=%s  WRITE_EDGE_CUES=%s  WRITE_GLUE_CUES=%s  GLUE_CUE_POLICY=%s",
    cfg.HANDLE_SECONDS or 0, eps_s, tostring(cfg.GLUE_SINGLE_ITEMS), tostring(cfg.GLUE_TAKE_FX),
    tostring(cfg.GLUE_TRACK_FX), cfg.GLUE_APPLY_MODE, tostring(cfg.WRITE_EDGE_CUES), tostring(cfg.WRITE_GLUE_CUES),
    "adjacent-different-source")

  -- Auto-detect scope: TS-Window vs Units glue
  -- If force_units=true, always use units glue (for core() API scope="units")
  -- Otherwise use auto-scope logic (TS exists → TS-Window, no TS → Units)
  local scope, tsL, tsR
  if force_units then
    scope = "units"
    dbg(DBG,1,"[SCOPE] Forced Units glue (via parameter)")
  else
    scope, tsL, tsR = glue_auto_scope(cfg, "glue")
  end

  if scope == "ts" then
    -- TS-Window glue path
    dbg(DBG,1,"[RUN] Using TS-Window glue: [%.3f, %.3f]", tsL, tsR)
    local by_tr, tracks = collect_items_intersect_ts_by_track(tsL, tsR)
    for _, tr in ipairs(tracks) do
      local snapshot = by_tr[tr]
      glue_by_ts_window_on_track(tr, tsL, tsR, cfg, snapshot)
    end
  else
    -- Units glue path
    dbg(DBG,1,"[RUN] Using Units glue")
    local by_tr, tr_list = collect_by_track_from_selection()
    for _,tr in ipairs(tr_list) do
      local list  = by_tr[tr]
      local units = detect_units_same_track(list, eps_s)
      dbg(DBG,1,"[RUN] Track #%d: units=%d", r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1, #units)

      -- When multiple units with gaps AND TS exists, treat them as one GAP unit
      -- Without TS: keep units separate for individual handle-aware processing
      local currentTsL, currentTsR, hasTS = get_current_ts()

      if #units > 1 and hasTS then
        -- Sort items by position
        table.sort(list, function(a,b)
          return r.GetMediaItemInfo_Value(a,"D_POSITION") < r.GetMediaItemInfo_Value(b,"D_POSITION")
        end)

        -- Calculate this track's items span
        local trackItemsL, trackItemsR = math.huge, -math.huge
        for _, it in ipairs(list) do
          local L, R = item_span(it)
          if L < trackItemsL then trackItemsL = L end
          if R > trackItemsR then trackItemsR = R end
        end

        -- Use TS edge if it's outside (or equal to) items edge
        local overallL = (currentTsL <= trackItemsL + eps_s) and currentTsL or trackItemsL
        local overallR = (currentTsR >= trackItemsR - eps_s) and currentTsR or trackItemsR
        dbg(DBG,1,"[RUN] GAP unit span: %.3f..%.3f (TS=%.3f..%.3f, items=%.3f..%.3f)",
            overallL, overallR, currentTsL, currentTsR, trackItemsL, trackItemsR)

        -- Create one synthetic unit containing all items (without modifying item lengths)
        local members = {}
        for _, it in ipairs(list) do
          local L, R = item_span(it)
          members[#members+1] = {it=it, L=L, R=R}
        end

        local synthetic_unit = {
          kind = "GAP",  -- Mark as having gaps
          members = members,
          start = overallL,
          finish = overallR
        }

        units = {synthetic_unit}
        dbg(DBG,1,"[RUN] Multiple units merged into GAP unit (span=%.3f..%.3f, %d items with gaps, TS exists)", overallL, overallR, #members)
      elseif #units > 1 then
        -- Multiple units but no TS: process each unit individually with handles
        dbg(DBG,1,"[RUN] Multiple units (%d) without TS → processing individually with handles", #units)
      end

      for ui,u in ipairs(units) do
        if u.kind=="SINGLE" and (not cfg.GLUE_SINGLE_ITEMS) then
          dbg(DBG,2,"[TRACE] unit#%d SINGLE skipped (option off).", ui)
        else
          glue_unit(tr, u, cfg)
        end
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("RGWH Core - Glue selection", -1)
end

function M.auto_selection(merge_volumes, print_volumes)
  -- AUTO mode: Render single-item units, Glue multi-item units
  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end

  local nsel = count_selected_items()
  if nsel==0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Auto (no selection)", -1); return
  end

  local eps_s = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  dbg(DBG,1,"[RUN] Auto start  handles=%.3fs  epsilon=%.5fs", cfg.HANDLE_SECONDS or 0, eps_s)

  -- Collect all items by track and detect units
  local by_tr, tr_list = collect_by_track_from_selection()
  local multi_units = {}   -- Multi-item units (to glue)
  local has_single = false -- Flag to check if there are single-item units

  for _,tr in ipairs(tr_list) do
    local list  = by_tr[tr]
    local units = detect_units_same_track(list, eps_s)
    dbg(DBG,1,"[RUN] Track #%d: units=%d", r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1, #units)

    for ui,u in ipairs(units) do
      if u.kind == "SINGLE" then
        dbg(DBG,2,"[TRACE] unit#%d SINGLE → keep selected for render", ui)
        has_single = true
        -- Keep single items selected (don't deselect them)
      else
        dbg(DBG,2,"[TRACE] unit#%d %s → will glue", ui, u.kind)
        table.insert(multi_units, {track=tr, unit=u})
        -- Deselect items in multi-item units (will be glued)
        for _, member in ipairs(u.members) do
          r.SetMediaItemSelected(member.it, false)
        end
      end
    end
  end

  -- First: Render single-item units (they are still selected)
  if has_single then
    local single_count = r.CountSelectedMediaItems(0)
    dbg(DBG,1,"[RUN] Rendering %d single items...", single_count)

    -- Call render_selection for currently selected items (single units)
    local merge_vols = (merge_volumes == nil) and true or (merge_volumes == true)
    local print_vols = (print_volumes == nil) and true or (print_volumes == true)

    -- render_selection has its own undo block, so we need to end ours first
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("RGWH Core - Auto (render phase)", -1)

    M.render_selection(nil, nil, nil, nil, merge_vols, print_vols)

    -- Start new undo block for glue phase
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
  end

  -- Second: Glue all multi-item units
  if #multi_units > 0 then
    dbg(DBG,1,"[RUN] Gluing %d multi-item units...", #multi_units)

    -- Reselect multi-item units for gluing
    r.SelectAllMediaItems(0, false)
    for _, mu in ipairs(multi_units) do
      for _, member in ipairs(mu.unit.members) do
        r.SetMediaItemSelected(member.it, true)
      end
    end

    -- Auto mode for glue: infer mono/multi from max item playback channels
    if cfg.GLUE_APPLY_MODE == "auto" then
      local function get_item_playback_channels(it)
        if not it then return 2 end
        local tk = reaper.GetActiveTake(it)
        if not tk then return 2 end
        local chanmode = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE")
        if chanmode == 2 or chanmode == 3 or chanmode == 4 then return 1 end
        local src = reaper.GetMediaItemTake_Source(tk)
        return src and (reaper.GetMediaSourceNumChannels(src) or 2) or 2
      end
      local maxch = 1
      for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local it = reaper.GetSelectedMediaItem(0, i)
        local ch = get_item_playback_channels(it)
        if ch > maxch then maxch = ch end
      end
      cfg.GLUE_APPLY_MODE = (maxch >= 2) and "multi" or "mono"
    end

    for _, mu in ipairs(multi_units) do
      glue_unit(mu.track, mu.unit, cfg)
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("RGWH Core - Auto selection", -1)
end

function M.render_selection(take_fx, track_fx, mode, tc_mode, merge_volumes, print_volumes)
  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1
  local items = get_sel_items()
  local nsel  = #items
  local r = reaper

  -- Optional parameter overrides (enable call-site control)
  if take_fx ~= nil then
    cfg.RENDER_TAKE_FX = (take_fx == 1 or take_fx == true)
  end
  if track_fx ~= nil then
    cfg.RENDER_TRACK_FX = (track_fx == 1 or track_fx == true)
  end
  if mode ~= nil then
    cfg.RENDER_APPLY_MODE = tostring(mode)
  end
  if tc_mode ~= nil then
    cfg.RENDER_TC_EMBED = tostring(tc_mode)
  end
  -- NEW: Volume control overrides (default: merge=true, print=true)
  if merge_volumes == nil then merge_volumes = true end
  if print_volumes == nil then print_volumes = true end
  cfg.RENDER_MERGE_VOLUMES = (merge_volumes == true)
  cfg.RENDER_PRINT_VOLUMES = (print_volumes == true)

  -- Auto mode: infer mono/multi from max item playback channels over current selection
  -- Respects item channel mode (mono downmix/left/right should be treated as mono)
  if cfg.RENDER_APPLY_MODE == "auto" then
    local function get_item_playback_channels(it)
      if not it then return 2 end
      local tk = reaper.GetActiveTake(it)
      if not tk then return 2 end

      -- Check take's channel mode setting (IMPORTANT: use GetMediaItemTakeInfo_Value, not GetMediaItemInfo_Value!)
      local chanmode = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE")
      -- chanmode 2=downmix, 3=left only, 4=right only → mono
      if chanmode == 2 or chanmode == 3 or chanmode == 4 then
        return 1
      end
      -- Otherwise use source channels
      local src = reaper.GetMediaItemTake_Source(tk)
      return src and (reaper.GetMediaSourceNumChannels(src) or 2) or 2
    end

    local function max_channels_over(items_)
      local maxch = 1
      for _, it in ipairs(items_) do
        local ch = get_item_playback_channels(it)
        if ch > maxch then maxch = ch end
      end
      return maxch
    end
    local maxch = max_channels_over(items)
    cfg.RENDER_APPLY_MODE = (maxch >= 2) and "multi" or "mono"
  end

  -- helpers (local to this function) -----------------------------------------
  local function snapshot_takefx_offline(tk)
    if not tk then return nil end
    local n = r.TakeFX_GetCount(tk) or 0
    local snap = {}
    for i = 0, n-1 do snap[i] = r.TakeFX_GetOffline(tk, i) and true or false end
    return snap
  end

  -- temporarily set offline=true ONLY for FX that were online
  local function temp_offline_nonoffline_fx(tk)
    if not tk then return 0 end
    local n = r.TakeFX_GetCount(tk) or 0
    local cnt = 0
    for i = 0, n-1 do
      if not r.TakeFX_GetOffline(tk, i) then
        r.TakeFX_SetOffline(tk, i, true)
        cnt = cnt + 1
      end
    end
    return cnt
  end

  local function restore_takefx_offline(tk, snap)
    if not (tk and snap) then return 0 end
    local n = r.TakeFX_GetCount(tk) or 0
    local cnt = 0
    for i = 0, n-1 do
      local want = snap[i]
      if want ~= nil then
        r.TakeFX_SetOffline(tk, i, want and true or false)
        cnt = cnt + 1
      end
    end
    return cnt
  end

  -- clone whole take-FX chain (states included) from src to dst
  local function clone_takefx_chain(src_tk, dst_tk)
    if not (src_tk and dst_tk) or src_tk == dst_tk then return 0 end
    -- clear dst first to avoid duplicates
    for i = (r.TakeFX_GetCount(dst_tk) or 0)-1, 0, -1 do r.TakeFX_Delete(dst_tk, i) end
    local n = r.TakeFX_GetCount(src_tk) or 0
    for i = 0, n-1 do r.TakeFX_CopyToTake(src_tk, i, dst_tk, i, false) end
    return n
  end

  -- fade helpers (shared with GLUE)
  -- snapshot_fades(it) -> table
  -- zero_fades(it)
  -- restore_fades(it, snap)
  -----------------------------------------------------------------------------

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end

  if nsel == 0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Render (no selection)", -1); return
  end

  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0

  dbg(DBG,1,"[RUN] Render start  mode=%s  TAKE=%s TRACK=%s  items=%d  handles=%.3fs  WRITE_EDGE_CUES=%s  GLUE_CUE_POLICY=%s",
      cfg.RENDER_APPLY_MODE, tostring(cfg.RENDER_TAKE_FX), tostring(cfg.RENDER_TRACK_FX),
      nsel, HANDLE, tostring(cfg.WRITE_EDGE_CUES), "adjacent-different-source")

  -- snapshot per-track FX enabled state (TRACK path has been stable)
  local tr_map = {}
  for _, it in ipairs(items) do
    local tr = r.GetMediaItem_Track(it)
    if tr and not tr_map[tr] then
      local fxn = r.TrackFX_GetCount(tr) or 0
      local rec = { track = tr, enabled = {} }
      for i = 0, fxn-1 do rec.enabled[i] = r.TrackFX_GetEnabled(tr, i) end
      tr_map[tr] = rec
    end
  end

  local need_track = (cfg.RENDER_TRACK_FX == true)
  local need_take  = (cfg.RENDER_TAKE_FX  == true)

  if not need_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      local fxn = r.TrackFX_GetCount(tr) or 0
      for i = 0, fxn-1 do r.TrackFX_SetEnabled(tr, i, false) end
    end
    dbg(DBG,1,"[RUN] Temporarily disabled TRACK FX (policy TRACK=0).")
  end

  -- pick render command
  local ACT_APPLY_MONO  = 40361 -- Apply track/take FX to items (mono)
  local ACT_APPLY_MULTI = 41993 -- Apply track/take FX to items (multichannel)
  local ACT_RENDER_PRES = 40601 -- Render items to new take (preserve source type)
  local cmd_apply = (cfg.RENDER_APPLY_MODE=="multi") and ACT_APPLY_MULTI or ACT_APPLY_MONO

  for _, it in ipairs(items) do
    local tk_orig = r.GetActiveTake(it)
    local orig_name = ""
    if tk_orig then
      _, orig_name = r.GetSetMediaItemTakeInfo_String(tk_orig, "P_NAME", "", false)
    end
    -- snapshot original StartInSource (seconds) before we stretch window
    local orig_startoffs_sec = tk_orig and (r.GetMediaItemTakeInfo_Value(tk_orig, "D_STARTOFFS") or 0.0) or nil

    -- When TAKE FX are excluded, temporarily offline only those that were online.
    local snap_off = nil
    if tk_orig and (not need_take) then
      snap_off = snapshot_takefx_offline(tk_orig)
      local n_off = temp_offline_nonoffline_fx(tk_orig)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] temp-offline %d FX on '%s'", n_off, orig_name) end
    end

    -- >>>> Volume handling: snapshot, optional merge, optional reset <<<<
    local volume_snap = { item_vol = 0.0, take_vols = {}, merged_vol = 1.0 }
    do
      -- Always snapshot current volumes
      local item_vol = r.GetMediaItemInfo_Value(it, "D_VOL") or 1.0
      volume_snap.item_vol = item_vol
      local nt = r.GetMediaItemNumTakes(it) or 0
      for ti = 0, nt-1 do
        local tk = r.GetTake(it, ti)
        if tk then
          local tv = r.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1.0
          volume_snap.take_vols[ti] = tv
        end
      end

      -- Conditional merge: pre-merge item volume into ALL takes (not just active)
      -- Rationale: When merge_volumes=true, the goal is to move all volume control from
      -- item level to take level. If we only merge the active take, switching to other
      -- takes will cause unexpected volume jumps (because item volume is reset to 0dB).
      -- By merging ALL takes, we ensure consistent output regardless of which take is active.
      if cfg.RENDER_MERGE_VOLUMES and tk_orig then
        if math.abs(item_vol - 1.0) > 1e-9 then
          -- Multiply item volume into EVERY take's volume
          local nt = r.GetMediaItemNumTakes(it) or 0
          for ti = 0, nt-1 do
            local tk = r.GetTake(it, ti)
            if tk then
              local tv = r.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1.0
              local merged_tv = tv * item_vol
              r.SetMediaItemTakeInfo_Value(tk, "D_VOL", merged_tv)
            end
          end
          -- Remember the merged value for the active take specifically (for restoration)
          local tv_orig = volume_snap.take_vols[tk_orig_idx] or 1.0
          volume_snap.merged_vol = tv_orig * item_vol
          r.SetMediaItemInfo_Value(it, "D_VOL", 1.0)
          if DBG >= 2 then dbg(DBG,2,"[GAIN] pre-merged itemVol=%.3f into ALL takes; active take (%.3f → %.3f)", item_vol, tv_orig, volume_snap.merged_vol) end
        else
          -- Item already at 1.0, just store active take volume as merged_vol
          local tv_orig = r.GetMediaItemTakeInfo_Value(tk_orig, "D_VOL") or 1.0
          volume_snap.merged_vol = tv_orig
        end

        -- If print_volumes=false, reset active take volume to 0dB before render
        -- (so rendered audio doesn't bake in the volume)
        if not cfg.RENDER_PRINT_VOLUMES and tk_orig then
          local current_tv = r.GetMediaItemTakeInfo_Value(tk_orig, "D_VOL") or 1.0
          volume_snap.merged_vol = current_tv
          r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", 1.0)
          if DBG >= 2 then dbg(DBG,2,"[GAIN] print_volumes=false; reset active take %.3f→1.0 before render", current_tv) end
        end
      else
        -- merge_volumes=false: don't merge, remember original values
        -- Keep item volume and take volumes separate (no modification to inactive takes)
        local tv_orig = tk_orig and (r.GetMediaItemTakeInfo_Value(tk_orig, "D_VOL") or 1.0) or 1.0
        volume_snap.merged_vol = tv_orig
        if DBG >= 2 then dbg(DBG,2,"[GAIN] merge_volumes=false; keeping item=%.3f, take=%.3f separate", item_vol, tv_orig) end

        -- If print_volumes=false, reset active take to 0dB before render
        if not cfg.RENDER_PRINT_VOLUMES and tk_orig then
          r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", 1.0)
          if DBG >= 2 then dbg(DBG,2,"[GAIN] print_volumes=false; reset active take %.3f→1.0 before render", tv_orig) end
        end
      end
    end

    local L0, R0 = item_span(it)
    local name0  = get_take_name(it) or ""
    local d      = per_member_window_lr(it, L0, R0, HANDLE, HANDLE)

    if DBG >= 2 then
      dbg(DBG,2,"[REN] item@%.3f..%.3f want=%.3f..%.3f -> got=%.3f..%.3f clampL=%s clampR=%s name=%s",
          L0, R0, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), name0)
    end

    local edge_ids = nil
    if cfg.WRITE_EDGE_CUES then
      -- Keep #in/#out (unit span) for downstream media-cue workflows.
      edge_ids = add_edge_cues(L0, R0, 0)
      dbg(DBG,1,"[EDGE-CUE] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", L0, R0, tostring(edge_ids and edge_ids[1]), tostring(edge_ids and edge_ids[2]))
    end


    -- move to render window and align take offset
    r.SetMediaItemInfo_Value(it, "D_POSITION", d.gotL)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   d.gotR - d.gotL)
    if d.tk then
      local deltaL  = (L0 - d.gotL)
      local new_off = d.offs - (deltaL * d.rate)
      r.SetMediaItemTakeInfo_Value(d.tk, "D_STARTOFFS", new_off)
    end

    -- If we are going to apply TRACK FX (01/11), or we are forcing multi without TRACK FX,
    -- clear fades (40361/41993 will bake them). Otherwise (00/10 => 40601) keep fades.
    local fade_snap = nil
    local force_multi = (not need_track)
                    and (cfg.RENDER_APPLY_MODE == "multi")
                    and (cfg.RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi")

    local use_apply = (need_track == true) or (force_multi == true)
    if use_apply then
      if force_multi then
        dbg(DBG,1,"[APPLY] force multi (no track FX path)")
      end
      fade_snap = snapshot_fades(it)
      zero_fades(it)
    end


    -- render
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(it, true)
    r.Main_OnCommand(use_apply and cmd_apply or ACT_RENDER_PRES, 0)

    -- remove temporary # markers (if any)
    if edge_ids then
      remove_markers_by_ids(edge_ids)
      dbg(DBG,1,"[EDGE-CUE] removed ids: %s, %s", tostring(edge_ids[1]), tostring(edge_ids[2]))
    end

    -- restore fades if we cleared them for 40361/41993
    if use_apply and fade_snap then
      restore_fades(it, fade_snap)
    end


    -- restore item window and offset
    local left_total = L0 - d.gotL
    if left_total < 0 then left_total = 0 end
    r.SetMediaItemInfo_Value(it, "D_POSITION", L0)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   R0 - L0)
    local newtk = r.GetActiveTake(it)  -- the freshly rendered take
    if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_STARTOFFS", left_total) end
    r.UpdateItemInProject(it)

    -- Volume handling after render: print or restore
    if cfg.RENDER_PRINT_VOLUMES then
      -- Print mode: volumes are baked into audio
      if cfg.RENDER_MERGE_VOLUMES then
        -- Merged: item=0dB, new take=0dB, old take=merged_vol
        r.SetMediaItemInfo_Value(it, "D_VOL", 1.0)
        if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_VOL", 1.0) end
        if tk_orig then r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", volume_snap.merged_vol) end
        if DBG >= 2 then dbg(DBG,2,"[GAIN] print_volumes=true; item=1.0, new take=1.0, old active take=%.3f", volume_snap.merged_vol) end
      else
        -- Not merged: restore original item & take volumes
        r.SetMediaItemInfo_Value(it, "D_VOL", volume_snap.item_vol)
        if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_VOL", 1.0) end
        if tk_orig then r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", volume_snap.merged_vol) end
        if DBG >= 2 then dbg(DBG,2,"[GAIN] print_volumes=true; item=%.3f, new take=1.0, old active take=%.3f", volume_snap.item_vol, volume_snap.merged_vol) end
      end
    else
      -- Non-print mode: restore volumes (non-destructive)
      if cfg.RENDER_MERGE_VOLUMES then
        -- Merged: item=0dB, all takes=merged_vol
        r.SetMediaItemInfo_Value(it, "D_VOL", 1.0)
        if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_VOL", volume_snap.merged_vol) end
        if tk_orig then r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", volume_snap.merged_vol) end
        if DBG >= 2 then dbg(DBG,2,"[GAIN] print_volumes=false; item=1.0, new & old active takes=%.3f", volume_snap.merged_vol) end
      else
        -- Not merged: restore original item & take volumes
        r.SetMediaItemInfo_Value(it, "D_VOL", volume_snap.item_vol)
        if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_VOL", volume_snap.merged_vol) end
        if tk_orig then r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", volume_snap.merged_vol) end
        if DBG >= 2 then dbg(DBG,2,"[GAIN] print_volumes=false; item=%.3f, new & old active takes=%.3f", volume_snap.item_vol, volume_snap.merged_vol) end
      end
    end

    -- Rename only the new rendered take
    rename_new_render_take(
      it,
      orig_name,
      cfg.RENDER_TAKE_FX == true,
      cfg.RENDER_TRACK_FX == true,
      DBG
    )

    -- Restore original take's offline snapshot first...
    if tk_orig and snap_off then
      restore_takefx_offline(tk_orig, snap_off)
    end
    -- ...then clone the original take FX chain to the NEW take when TAKE FX were excluded
    if newtk and tk_orig and (not need_take) then
      local ncl = clone_takefx_chain(tk_orig, newtk)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] cloned %d FX from old→new on '%s'", ncl, orig_name) end
    end

    ----------------------------------------------------------------
    -- Always restore previous take's StartInSource (SIS),
    -- regardless of tc_mode ("previous" | "current" | "off").
    ----------------------------------------------------------------
    if tk_orig and orig_startoffs_sec ~= nil then
      r.SetMediaItemTakeInfo_Value(tk_orig, "D_STARTOFFS", orig_startoffs_sec)
    end

    -- === TimeReference embed (via Library) =========================
    -- ExtState: RENDER_TC_EMBED = "previous" | "current" | "off"
    do
      local mode = cfg.RENDER_TC_EMBED or "previous"
      if newtk and mode ~= "off" then
        local ok_write = false

        if mode == "previous" and tk_orig then
          -- Embed TR from previous (original) take, handle-aware and cross-SR safe
          local smp = E.TR_PrevToActive(tk_orig, newtk)
          local src = r.GetMediaItemTake_Source(newtk)
          local path = src and r.GetMediaSourceFileName(src, "") or ""
          if path ~= "" and path:lower():sub(-4) == ".wav" then
            ok_write = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
            if DBG >= 2 then dbg(DBG,2,"[RGWH-TR] mode=previous  write=%s  samples=%d  path=%s", tostring(ok_write), smp, path) end
          end

        elseif mode == "current" then
          -- Embed TR from current project position (item start → active)
          local smp = E.TR_FromItemStart(newtk, L0)
          local src = r.GetMediaItemTake_Source(newtk)
          local path = src and r.GetMediaSourceFileName(src, "") or ""
          if path ~= "" and path:lower():sub(-4) == ".wav" then
            ok_write = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
            if DBG >= 2 then dbg(DBG,2,"[RGWH-TR] mode=current   write=%s  samples=%d  path=%s", tostring(ok_write), smp, path) end
          end
        end

        -- collect for batch refresh if TR was written
        if ok_write then
          collected_new_takes = collected_new_takes or {}
          collected_new_takes[#collected_new_takes+1] = newtk
        end
      end
    end
    -- ==============================================================
  end
  -- restore TRACK FX enabled states if we disabled them
  if not need_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      for fx, was_on in pairs(rec.enabled) do
        r.TrackFX_SetEnabled(tr, fx, was_on and true or false)
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()

  -- refresh items that had TR written (batch)
  if collected_new_takes and #collected_new_takes > 0 then
    E.Refresh_Items(collected_new_takes)
  end

  r.Undo_EndBlock("RGWH Core - Render (Apply FX per item w/ handles)", -1)
end

------------------------------------------------------------
-- PUBLIC ENTRY (single callsite)
------------------------------------------------------------
function M.core(args)
  if type(args) ~= "table" then return false, "bad_args" end
  local op = tostring(args.op or "auto")  -- "render" | "glue" | "auto"

  -- Snapshot keys we may override (one-run)
  local prev = {
    HANDLE_MODE     = get_ext("HANDLE_MODE",     ""),
    HANDLE_SECONDS  = get_ext("HANDLE_SECONDS",  ""),
    EPSILON_MODE    = get_ext("EPSILON_MODE",    ""),
    EPSILON_VALUE   = get_ext("EPSILON_VALUE",   ""),
    WRITE_EDGE_CUES = get_ext("WRITE_EDGE_CUES", ""),
    WRITE_GLUE_CUES = get_ext("WRITE_GLUE_CUES", ""),
    DEBUG_LEVEL     = get_ext("DEBUG_LEVEL",     ""),
    DEBUG_NO_CLEAR  = get_ext("DEBUG_NO_CLEAR",  ""),

    GLUE_SINGLE_ITEMS  = get_ext("GLUE_SINGLE_ITEMS",  ""),
    GLUE_TAKE_FX       = get_ext("GLUE_TAKE_FX",       ""),
    GLUE_TRACK_FX      = get_ext("GLUE_TRACK_FX",      ""),
    GLUE_APPLY_MODE    = get_ext("GLUE_APPLY_MODE",    ""),
    GLUE_OUT_NO_TRFX   = get_ext("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX", ""),

    RENDER_TAKE_FX     = get_ext("RENDER_TAKE_FX",     ""),
    RENDER_TRACK_FX    = get_ext("RENDER_TRACK_FX",    ""),
    RENDER_APPLY_MODE  = get_ext("RENDER_APPLY_MODE",  ""),
    RENDER_OUT_NO_TRFX = get_ext("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", ""),
    RENDER_TC_EMBED    = get_ext("RENDER_TC_EMBED",    ""),
  }
  local function set_opt(k, v) if v ~= nil then set_ext(k, v) end end

  -- One-run overrides ------------------------------------------------
  -- handle / epsilon
  if args.handle and args.handle ~= "ext" then
    set_opt("HANDLE_MODE",    args.handle.mode or DEFAULTS.HANDLE_MODE)
    set_opt("HANDLE_SECONDS", tostring(args.handle.seconds or DEFAULTS.HANDLE_SECONDS))
  end
  if args.epsilon and args.epsilon ~= "ext" then
    set_opt("EPSILON_MODE",   args.epsilon.mode or DEFAULTS.EPSILON_MODE)
    set_opt("EPSILON_VALUE",  tostring(args.epsilon.value or DEFAULTS.EPSILON_VALUE))
  end

  -- cues
  if args.cues then
    if args.cues.write_edge ~= nil then set_opt("WRITE_EDGE_CUES", args.cues.write_edge and "1" or "0") end
    if args.cues.write_glue ~= nil then set_opt("WRITE_GLUE_CUES", args.cues.write_glue and "1" or "0") end
  end

  -- debug
  if args.debug then
    if args.debug.level ~= nil then set_opt("DEBUG_LEVEL", tostring(args.debug.level)) end
    if args.debug.no_clear ~= nil then set_opt("DEBUG_NO_CLEAR", args.debug.no_clear and "1" or "0") end
  end

  -- channel mode (maps to GLUE/RENDER_APPLY_MODE)
  local ch = args.channel_mode
  if ch == "auto" or ch == "mono" or ch == "multi" then
    set_opt("GLUE_APPLY_MODE",   ch)
    set_opt("RENDER_APPLY_MODE", ch)
  end

  -- toggles (apply to BOTH render & glue; TS-Window needs GLUE_* too)
  if args.take_fx  ~= nil then
    set_opt("RENDER_TAKE_FX", args.take_fx and "1" or "0")
    set_opt("GLUE_TAKE_FX",   args.take_fx and "1" or "0")
  end
  if args.track_fx ~= nil then
    set_opt("RENDER_TRACK_FX", args.track_fx and "1" or "0")
    set_opt("GLUE_TRACK_FX",   args.track_fx and "1" or "0")
  end
  if args.tc_mode  ~= nil then
    set_opt("RENDER_TC_EMBED", tostring(args.tc_mode))
  end

  -- policies
  if args.policies then
    if args.policies.glue_single_items ~= nil then
      set_opt("GLUE_SINGLE_ITEMS", args.policies.glue_single_items and "1" or "0")
    end
    if args.policies.glue_no_trackfx_output_policy then
      set_opt("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX", args.policies.glue_no_trackfx_output_policy)
    end
    if args.policies.render_no_trackfx_output_policy then
      set_opt("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", args.policies.render_no_trackfx_output_policy)
    end
    if args.policies.rename_mode then
      set_opt("RENAME_OP_MODE", args.policies.rename_mode)
    end
  end

  -- Run --------------------------------------------------------------
  local ok, err
  if op == "render" then
    -- Extract volume control params from args (defaults: merge=true, print=true)
    local merge_vols = (args.merge_volumes == nil) and true or (args.merge_volumes == true)
    local print_vols = (args.print_volumes == nil) and true or (args.print_volumes == true)
    -- Pass volume params as positional args: (take_fx, track_fx, mode, tc_mode, merge_volumes, print_volumes)
    ok, err = pcall(M.render_selection, nil, nil, nil, nil, merge_vols, print_vols)

  elseif op == "auto" then
    -- NEW AUTO MODE: Render single-item units, Glue multi-item units
    local merge_vols = (args.merge_volumes == nil) and true or (args.merge_volumes == true)
    local print_vols = (args.print_volumes == nil) and true or (args.print_volumes == true)
    ok, err = pcall(M.auto_selection, merge_vols, print_vols)

  elseif op == "glue" then
    local cfg = M.read_settings()

    if op == "glue" then
      local scope = tostring(args.selection_scope or "auto")  -- "auto"|"units"|"ts"|"item"
      if scope == "units" then
        ok, err = pcall(M.glue_selection, true)  -- force_units=true

      elseif scope == "ts" then
        local tsL, tsR, hasTS = get_current_ts()
        if not hasTS then ok, err = false, "no_time_selection" else
          local by_tr, tracks = collect_items_intersect_ts_by_track(tsL, tsR)
          r.Undo_BeginBlock(); r.PreventUIRefresh(1)
          if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end
          for _, tr in ipairs(tracks) do
            glue_by_ts_window_on_track(tr, tsL, tsR, cfg, by_tr[tr])
          end
          r.PreventUIRefresh(-1); r.UpdateArrange(); r.Undo_EndBlock("RGWH Core - Glue TS", -1)
          ok, err = true, nil
        end

      elseif scope == "item" then
        ok, err = pcall(M.glue_selection)

      else -- "auto"
        local which, tsL, tsR = glue_auto_scope(cfg, "auto")
        if which == "units" then
          ok, err = pcall(M.glue_selection)
        else
          local by_tr, tracks = collect_items_intersect_ts_by_track(tsL, tsR)
          r.Undo_BeginBlock(); r.PreventUIRefresh(1)
          if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end
          for _, tr in ipairs(tracks) do
            glue_by_ts_window_on_track(tr, tsL, tsR, cfg, by_tr[tr])
          end
          r.PreventUIRefresh(-1); r.UpdateArrange(); r.Undo_EndBlock("RGWH Core - Glue TS(auto)", -1)
          ok, err = true, nil
        end
      end
    end
  else
    ok, err = false, "unsupported_op"
  end

  -- restore snapshot
  for k, v in pairs(prev) do set_opt(k, v) end
  if not ok then return false, tostring(err) end
  return true
end

return M
