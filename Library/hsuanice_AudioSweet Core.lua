--[[
@description AudioSweet — Focused Track FX render via RGWH Core, append FX name, rebuild peaks (selected items)
@version 0.1.0-beta (251030.1630)
@author Tim Chimes (original), adapted by hsuanice
@notes
  Reference:
  AudioSuite-like Script. Renders the selected plugin to the selected media item.
  Written for REAPER 5.1 with Lua
  v1.1 12/22/2015 — Added PreventUIRefresh
  Written by Tim Chimes
  http://chimesaudio.com

@changelog
  0.1.0-beta (2025-10-30) - Initial Public Beta Release
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
]]--

-- Debug toggle: set ExtState "hsuanice_AS"/"DEBUG" to "1" to enable, "0" (or empty) to disable
-- reaper.SetExtState("hsuanice_AS","DEBUG","1", false)  -- (disabled: don't force-on DEBUG by default)

-- === User options ===
-- How many FX names to keep in the "-ASn-..." suffix.
-- 0 or nil = unlimited; N>0 = keep last N tokens (FIFO).
-- Now reads from ExtState: hsuanice_AS/AS_MAX_FX_TOKENS
local function get_max_fx_tokens()
  local val = reaper.GetExtState("hsuanice_AS", "AS_MAX_FX_TOKENS")
  local n = tonumber(val)
  return (n and n > 0) and n or 3  -- default: 3
end

-- Chain token source (for chain mode):
--   "aliases" -> use enabled Track FX aliases in order (joined by AS_CHAIN_ALIAS_JOINER)
--   "fxchain" -> literal token "FXChain"
--   "track"   -> use the FX track's name (sanitized)
-- Now reads from ExtState: hsuanice_AS/AS_CHAIN_TOKEN_SOURCE
local function get_chain_token_source()
  local val = reaper.GetExtState("hsuanice_AS", "AS_CHAIN_TOKEN_SOURCE")
  return (val ~= "") and val or "track"  -- default: "track"
end

-- When AS_CHAIN_TOKEN_SOURCE="aliases", use this joiner to connect alias tokens
-- Now reads from ExtState: hsuanice_AS/AS_CHAIN_ALIAS_JOINER
local function get_chain_alias_joiner()
  return reaper.GetExtState("hsuanice_AS", "AS_CHAIN_ALIAS_JOINER")  -- default: "" (empty)
end

-- If true, strip unsafe filename characters from chain tokens (for "track" mode & others)
-- Now reads from ExtState: hsuanice_AS/SANITIZE_TOKEN_FOR_FILENAME
local function get_sanitize_token_for_filename()
  return reaper.GetExtState("hsuanice_AS", "SANITIZE_TOKEN_FOR_FILENAME") == "1"  -- default: false
end

-- Track name token style: when true, strip ALL non-alphanumeric (FX-like short name).
-- When false, fall back to sanitize_token (underscores etc.).
-- Now reads from ExtState: hsuanice_AS/TRACKNAME_STRIP_SYMBOLS
local function get_trackname_strip_symbols()
  local val = reaper.GetExtState("hsuanice_AS", "TRACKNAME_STRIP_SYMBOLS")
  return (val == "") and true or (val == "1")  -- default: true
end

-- Naming-only debug (console print before/after renaming).
-- Now controlled by ExtState: hsuanice_AS/DEBUG
local function debug_naming_enabled()
  return reaper.GetExtState("hsuanice_AS", "DEBUG") == "1"
end

local function debug_enabled()
  return reaper.GetExtState("hsuanice_AS", "DEBUG") == "1"
end

function debug(message)
  if not debug_enabled() then return end
  if message == nil then return end
  reaper.ShowConsoleMsg(tostring(message) .. "\n")
end

-- Step logger: always prints when DEBUG=1; use for deterministic tracing
local function log_step(tag, fmt, ...)
  if not debug_enabled() then return end
  local msg = fmt and string.format(fmt, ...) or ""
  reaper.ShowConsoleMsg(string.format("[AS][STEP] %s %s\n", tostring(tag or ""), msg))
end



-- ==== debug helpers ====
local function dbg_item_brief(it, tag)
  if not debug_enabled() or not it then return end
  local p   = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local tr  = reaper.GetMediaItem_Track(it)
  local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
  local trname = ""
  if tr then
    local _, tn = reaper.GetTrackName(tr)
    trname = tn or ""
  end
  reaper.ShowConsoleMsg(string.format("[AS][STEP] %s item pos=%.3f len=%.3f track='%s' guid=%s\n",
    tag or "ITEM", p or -1, len or -1, trname, g))
end

local function dbg_dump_selection(tag)
  if not debug_enabled() then return end
  local n = reaper.CountSelectedMediaItems(0)
  reaper.ShowConsoleMsg(string.format("[AS][STEP] %s selected_items=%d\n", tag or "SEL", n))
  for i=0,n-1 do
    dbg_item_brief(reaper.GetSelectedMediaItem(0, i), "  •")
  end
end

local function dbg_dump_unit(u, idx)
  if not debug_enabled() or not u then return end
  reaper.ShowConsoleMsg(string.format("[AS][STEP] UNIT#%d UL=%.3f UR=%.3f members=%d\n",
    idx or -1, u.UL, u.UR, #u.items))
  for _,it in ipairs(u.items) do dbg_item_brief(it, "    -") end
end

local function dbg_track_items_in_range(tr, L, R)
  if not debug_enabled() then return end
  reaper.ShowConsoleMsg(string.format("[AS][STEP] TRACK SCAN in [%.3f..%.3f]\n", L, R))
  if not tr then
    reaper.ShowConsoleMsg("[AS][STEP]   (no track)\n")
    return
  end
  local n = reaper.CountTrackMediaItems(tr)
  for i=0,n-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if it then
      local p   = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local q   = (p or 0) + (len or 0)
      if p and len and not (q < L or p > R) then
        dbg_item_brief(it, "  tr-hit")
      end
    end
  end
end

-- === COPY HELPERS (non-destructive, no rename) ===
local function AS_merge_args_with_extstate(args)
  args = args or {}
  local function get_ns(ns, key, def)
    local v = reaper.GetExtState(ns, key)
    if v == "" then return def else return v end
  end
  args.mode       = args.mode       or get_ns("hsuanice_AS","AS_MODE","focused")     -- focused | chain
  args.action     = args.action     or get_ns("hsuanice_AS","AS_ACTION","apply")      -- apply   | copy
  args.scope      = args.scope      or get_ns("hsuanice_AS","AS_COPY_SCOPE","active") -- active  | all_takes
  args.append_pos = args.append_pos or get_ns("hsuanice_AS","AS_COPY_POS","tail")     -- tail    | head
  args.warn_takefx = (args.warn_takefx ~= false)
  return args
end

local function AS_copy_focused_fx_to_items(src_track, fx_index, args)
  local selN = reaper.CountSelectedMediaItems(0)
  local copied = 0
  for i = 0, selN - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local take_count = reaper.CountTakes(it) or 0
      local function each_take(fn)
        if args.scope == "all_takes" then
          for t = 0, take_count - 1 do
            local tk = reaper.GetMediaItemTake(it, t)
            if tk then fn(tk) end
          end
        else
          local tk = reaper.GetActiveTake(it)
          if tk then fn(tk) end
        end
      end
      each_take(function(tk)
        local dest = (args.append_pos == "head") and 0 or (reaper.TakeFX_GetCount(tk) or 0)
        reaper.TrackFX_CopyToTake(src_track, fx_index, tk, dest, false)
        copied = copied + 1
      end)
    end
  end
  return copied
end

local function AS_copy_chain_to_items(src_track, args)
  local chainN = reaper.TrackFX_GetCount(src_track) or 0
  local selN   = reaper.CountSelectedMediaItems(0)
  local total  = 0
  for i = 0, selN - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local take_count = reaper.CountTakes(it) or 0
      local function each_take(fn)
        if args.scope == "all_takes" then
          for t = 0, take_count - 1 do
            local tk = reaper.GetMediaItemTake(it, t)
            if tk then fn(tk) end
          end
        else
          local tk = reaper.GetActiveTake(it)
          if tk then fn(tk) end
        end
      end
      each_take(function(tk)
        if args.append_pos == "head" then
          for fx = chainN - 1, 0, -1 do
            reaper.TrackFX_CopyToTake(src_track, fx, tk, 0, false)
            total = total + 1
          end
        else
          for fx = 0, chainN - 1 do
            local dest = reaper.TakeFX_GetCount(tk) or 0
            reaper.TrackFX_CopyToTake(src_track, fx, tk, dest, false)
            total = total + 1
          end
        end
      end)
    end
  end
  return total
end
-- ================================================
-- ==== Chain token helpers (for chain mode naming) ====
local function sanitize_token(s)
  s = tostring(s or "")
  if get_sanitize_token_for_filename() then
    s = s:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  end
  return s
end

local function track_name_token(FXtrack)
  if not FXtrack then return "" end
  local _, tn = reaper.GetTrackName(FXtrack)
  tn = tn or ""
  if get_trackname_strip_symbols() then
    tn = tn:gsub("%b()", "")
           :gsub("[^%w]+","")
  else
    tn = sanitize_token(tn)
  end
  return tn
end

-- build_chain_token moved after format_fx_label and fx_alias_for_raw_label definitions (see line ~900)
-- =======================
-- ==== FX enable snapshot/restore (preserve original bypass states) ====
local function snapshot_fx_enables(tr)
  if not tr then return nil end
  local snap = {}
  local cnt = reaper.TrackFX_GetCount(tr) or 0
  for i = 0, cnt-1 do
    snap[i] = reaper.TrackFX_GetEnabled(tr, i) and true or false
  end
  return snap
end

local function restore_fx_enables(tr, snap)
  if not tr or not snap then return end
  local cnt = reaper.TrackFX_GetCount(tr) or 0
  for i = 0, cnt-1 do
    local en = snap[i]
    if en ~= nil then reaper.TrackFX_SetEnabled(tr, i, en) end
  end
end
-- =====================================================================
-- ==== FX name formatting options & helper ====
-- ExtState flags (if not set, reads defaults)
local FXNAME_DEFAULT_SHOW_TYPE    = false  -- include type prefix (e.g., "VST3:" / "CLAP:")
local FXNAME_DEFAULT_SHOW_VENDOR  = false  -- include vendor name (in parentheses)
local FXNAME_DEFAULT_STRIP_SYMBOL = true  -- strip spaces and symbols (keep alphanumeric only)

local function fxname_opts()
  local function flag(key, default)
    local v = reaper.GetExtState("hsuanice_AS", key)
    if v == "1" then return true end
    if v == "0" then return false end
    return default
  end
  return {
    show_type    = flag("FXNAME_SHOW_TYPE",   FXNAME_DEFAULT_SHOW_TYPE),
    show_vendor  = flag("FXNAME_SHOW_VENDOR", FXNAME_DEFAULT_SHOW_VENDOR),
    strip_symbol = flag("FXNAME_STRIP_SYMBOL",FXNAME_DEFAULT_STRIP_SYMBOL),
  }
end

local function trim(s) return (s and s:gsub("^%s+",""):gsub("%s+$","")) or "" end

-- Parse REAPER FX display name:
--  Example: "CLAP: Pro-Q 4 (FabFilter)" → type="CLAP", core="Pro-Q 4", vendor="FabFilter"
local function parse_fx_label(raw)
  raw = tostring(raw or "")
  local typ, rest = raw:match("^([%w%+%._-]+):%s*(.+)$")
  rest = rest or raw
  local core, vendor = rest, nil
  local core_only, v = rest:match("^(.-)%s*%(([^%(%)]+)%)%s*$")
  if core_only then
    core, vendor = core_only, v
  end
  return trim(typ), trim(core), trim(vendor)
end

-- forward declare for alias lookup used by format_fx_label
local fx_alias_for_raw_label

local function format_fx_label(raw)
  -- Get formatting options from ExtState
  local opt = fxname_opts()

  -- Check if alias exists
  local alias = fx_alias_for_raw_label(raw)
  local use_alias = (type(alias) == "string" and alias ~= "")

  -- Parse the raw FX label to get type and vendor
  local typ, core, vendor = parse_fx_label(raw)

  -- If alias exists, use it as the core name; otherwise use parsed core
  local base_name = use_alias and alias or core

  -- Apply formatting options (even if using alias)
  local base
  if opt.show_type and typ ~= "" then
    base = typ .. ": " .. base_name
  else
    base = base_name
  end
  if opt.show_vendor and vendor ~= "" then
    base = base .. " (" .. vendor .. ")"
  end

  if opt.strip_symbol then
    base = base:gsub("[^%w]+","")
  end
  return base
end

-- ==== FX alias lookup (from Settings/fx_alias.json / .tsv) ====
-- User options
local AS_ALIAS_JSON_PATH = reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Settings/fx_alias.json"
local AS_ALIAS_TSV_PATH = reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Settings/fx_alias.tsv"
local AS_USE_ALIAS   = (reaper.GetExtState("hsuanice_AS","USE_ALIAS") == "1")
local AS_DEBUG_ALIAS = (reaper.GetExtState("hsuanice_AS","AS_DEBUG_ALIAS") == "1")

-- Simple normalization: lowercase, remove non-alphanumeric
local function _norm(s) return (tostring(s or ""):lower():gsub("[^%w]+","")) end

-- Lazy-load JSON (requires dkjson or equivalent json.decode in system)
-- Forward declare TSV helper so _alias_map() can call it before definition.
local _alias_map_from_tsv

local _FX_ALIAS_CACHE = nil
local function _alias_map()
  if _FX_ALIAS_CACHE ~= nil then return _FX_ALIAS_CACHE end
  _FX_ALIAS_CACHE = {}
  if not AS_USE_ALIAS then return _FX_ALIAS_CACHE end

  local f = io.open(AS_ALIAS_JSON_PATH, "rb")
  if not f then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg(("[ALIAS][LOAD] JSON not found: %s\n"):format(AS_ALIAS_JSON_PATH))
    end
    -- JSON file not found → try TSV fallback
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end
  local blob = f:read("*a"); f:close()

  -- Detect/load JSON decoder
  local JSON = _G.json or _G.dkjson
  if not JSON or not (JSON.decode or JSON.Decode or JSON.parse) then
    pcall(function()
      local lib = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/dkjson.lua"
      local ok, mod = pcall(dofile, lib)
      if ok and mod then JSON = mod end
    end)
  end
  local decode = (JSON and (JSON.decode or JSON.Decode or JSON.parse)) or nil
  if not decode then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] No JSON decoder found\n")
    end
    -- No decoder → try TSV fallback
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end

  local ok, data = pcall(decode, blob)
  if not ok or type(data) ~= "table" then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] JSON decode failed or not a table\n")
    end
    -- JSON parse failed → try TSV fallback
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end

  -- Support two formats:
  -- (A) object: { ["vst3|core|vendor"] = { alias="FOO", ... }, ... }
  -- (B) array:  [ { fingerprint="vst3|core|vendor", alias="FOO", ... }, ... ]
  local count = 0

  local is_array = (data[1] ~= nil) and true or false
  if is_array then
    for i = 1, #data do
      local rec = data[i]
      if type(rec) == "table" then
        local fp = rec.fingerprint
        local al = rec.alias
        if type(fp) == "string" and fp ~= "" and type(al) == "string" and al ~= "" then
          _FX_ALIAS_CACHE[fp] = al
          count = count + 1
        end
      end
    end
  else
    for k, v in pairs(data) do
      if type(k) == "string" and k ~= "" then
        if type(v) == "table" then
          local al = v.alias
          if type(al) == "string" and al ~= "" then
            _FX_ALIAS_CACHE[k] = al
            count = count + 1
          end
        elseif type(v) == "string" then
          _FX_ALIAS_CACHE[k] = v
          count = count + 1
        end
      end
    end
  end

  if AS_DEBUG_ALIAS then
    reaper.ShowConsoleMsg(("[ALIAS][LOAD] entries=%d  from=%s\n")
      :format(count, AS_ALIAS_JSON_PATH))
  end

  return _FX_ALIAS_CACHE
end
-- TSV small helper: build alias map from a TSV with headers:
--   fingerprint <TAB> alias  (other columns optional)
function _alias_map_from_tsv(tsv_path)
  local map = {}
  local f = io.open(tsv_path, "rb")
  if not f then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg(("[ALIAS][LOAD] TSV not found: %s\n"):format(tsv_path))
    end
    return map
  end

  local header = f:read("*l")
  if not header then
    f:close()
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] TSV empty header\n")
    end
    return map
  end

  -- Find column indices
  local cols = {}
  local idx = 1
  for h in tostring(header):gmatch("([^\t]+)") do
    cols[h] = idx
    idx = idx + 1
  end
  local fp_i  = cols["fingerprint"]
  local al_i  = cols["alias"]

  if not fp_i or not al_i then
    f:close()
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] TSV missing 'fingerprint' or 'alias' header\n")
    end
    return map
  end

  local added = 0
  while true do
    local line = f:read("*l")
    if not line then break end
    if line ~= "" then
      local fields = {}
      local i = 1
      for seg in line:gmatch("([^\t]*)\t?") do
        fields[i] = seg
        i = i + 1
        if (#fields >= idx-1) then break end
      end
      local fp = fields[fp_i]
      local al = fields[al_i]
      if type(fp) == "string" and fp ~= "" and type(al) == "string" and al ~= "" then
        map[fp] = al
        added = added + 1
      end
    end
  end
  f:close()

  if AS_DEBUG_ALIAS then
    reaper.ShowConsoleMsg(("[ALIAS][LOAD] TSV entries=%d  from=%s\n"):format(added, tsv_path))
  end
  return map
end
-- Stronger raw parsing: extract host/type, core without parens, outermost paren as vendor
-- Example: "VST3: UADx Manley VOXBOX Channel Strip (Universal Audio (UADx))"
--  => host="vst3", core="uadxmanleyvoxboxchannelstrip", vendor="universalaudiouadx"
local function _parse_raw_label_host_core_vendor(raw)
  raw = tostring(raw or "")

  -- host/type
  local host = raw:match("^%s*([%w_]+)%s*:") or ""
  host = host:lower()

  -- core: take everything after colon, remove all parens and non-alphanumeric
  local core = raw:match(":%s*(.+)$") or ""
  core = core:gsub("%b()", "")            -- remove all paren segments
               :gsub("%s+%-[%s%-].*$", "")-- remove " - Something" tail (just in case)
               :gsub("%W", "")            -- remove non-alphanumeric
               :lower()

  -- vendor: extract each balanced paren segment, take the last one
  local last = nil
  for seg in raw:gmatch("%b()") do
    last = seg
  end
  local vendor = ""
  if last and #last >= 2 then
    vendor = last:sub(2, -2)              -- remove leading/trailing parens
    vendor = vendor:gsub("%W", ""):lower()
  end

  return host, core, vendor
end
-- Return alias or nil (enhanced: support vendor+core keys, scan fallback, debug output)
function fx_alias_for_raw_label(raw_label)
  if not AS_USE_ALIAS then return nil end
  local m = _alias_map()
  if not m then return nil end

  -- Main parsing
  local host, core, vendor = _parse_raw_label_host_core_vendor(raw_label)

  -- Legacy parsing once (compatible with old keys)
  local typ2, core2, vendor2 = parse_fx_label(raw_label)
  local t2 = _norm(typ2)
  local c2 = _norm(core2)
  local v2 = _norm(vendor2)

  local t = host
  local c = core
  local v = vendor

  -- Build various candidate keys
  local key1  = string.format("%s|%s|%s", t,  c,  v)
  local key2  = string.format("%s|%s|",    t,  c)
  local key2b = (v ~= "" and string.format("%s|%s%s|", t, c, v)) or nil
  local key3  = string.format("|%s|",      c)

  local key1b = string.format("%s|%s|%s", t2, c2, v2)
  local key2c = string.format("%s|%s|",    t2, c2)
  local key2d = (v2 ~= "" and string.format("%s|%s%s|", t2, c2, v2)) or nil
  local key3b = string.format("|%s|",      c2)

  local hit, from

  -- Direct match
  if type(m[key1]) == "string" and m[key1] ~= "" then hit, from = m[key1], "exact" end
  if not hit and type(m[key2]) == "string" and m[key2] ~= "" then hit, from = m[key2], "empty-vendor" end
  if not hit and key2b and type(m[key2b]) == "string" and m[key2b] ~= "" then hit, from = m[key2b], "core+vendor-as-core" end
  if not hit and type(m[key3]) == "string" and m[key3] ~= "" then hit, from = m[key3], "cross-type" end

  -- Legacy key compatibility
  if not hit and type(m[key1b]) == "string" and m[key1b] ~= "" then hit, from = m[key1b], "exact(legacy)" end
  if not hit and type(m[key2c]) == "string" and m[key2c] ~= "" then hit, from = m[key2c], "empty-vendor(legacy)" end
  if not hit and key2d and type(m[key2d]) == "string" and m[key2d] ~= "" then hit, from = m[key2d], "core+vendor-as-core(legacy)" end
  if not hit and type(m[key3b]) == "string" and m[key3b] ~= "" then hit, from = m[key3b], "cross-type(legacy)" end

  -- Fallback scan
  if not hit then
    local core_pat1 = "|" .. c  .. "|"
    local core_pat2 = (v ~= "" and ("|" .. c .. v .. "|")) or nil
    for k, rec in pairs(m) do
      if type(rec) == "string" and rec ~= "" then
        if k:find(core_pat1, 1, true) or (core_pat2 and k:find(core_pat2, 1, true)) then
          hit, from = rec, "scan"
          break
        end
      end
    end
  end

  if AS_DEBUG_ALIAS then
    local size = 0
    for _ in pairs(m) do size = size + 1 end
    reaper.ShowConsoleMsg(("[ALIAS][LOOKUP]\n  raw   = %s\n  host  = %s\n  core  = %s\n  vendor= %s\n  try   = %s | %s | %s | %s\n  legacy= %s | %s | %s | %s\n  alias = %s (from=%s)\n  map   = %d entries\n\n")
      :format(
        tostring(raw_label or ""),
        t, c, v,
        key1, key2, tostring(key2b or "(nil)"), key3,
        key1b, key2c, tostring(key2d or "(nil)"), key3b,
        tostring(hit or ""), tostring(from or "miss"),
        size
      ))
  end

  return hit
end

-- =============================================
-- ==== Chain token builder (moved here after format_fx_label is defined) ====
local function build_chain_token(FXtrack)
  local source = get_chain_token_source()
  if source == "fxchain" then
    return "FXChain"
  elseif source == "track" then
    return track_name_token(FXtrack)
  end

  -- default: "aliases"
  local list = {}
  if not FXtrack then return "" end
  local cnt = reaper.TrackFX_GetCount(FXtrack) or 0
  for i = 0, cnt-1 do
    local enabled = reaper.TrackFX_GetEnabled(FXtrack, i)
    if enabled then
      local _, raw = reaper.TrackFX_GetFXName(FXtrack, i, "")
      local name  = format_fx_label(raw)
      if name and name ~= "" then list[#list+1] = name end
    end
  end
  return table.concat(list, get_chain_alias_joiner())
end

-- =============================================
-- ==== selection snapshot helpers ====
local function snapshot_selection()
  local list = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local tr = reaper.GetMediaItem_Track(it)
      local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      table.insert(list, { tr = tr, L = p, R = p + l })
    end
  end
  return list
end

local function restore_selection(snap)
  if not snap then return end
  reaper.Main_OnCommand(40289, 0) -- clear selection
  local eps = project_epsilon()
  for _, rec in ipairs(snap) do
    local tr = rec.tr
    if tr then
      local n = reaper.CountTrackMediaItems(tr)
      for j = 0, n - 1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if it then
          local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          local q  = p + l
          -- If this item covers the original selection range, consider it a match (TS-Window generates aligned glued clips)
          if p <= rec.L + eps and q >= rec.R - eps then
            reaper.SetMediaItemSelected(it, true)
            break
          end
        end
      end
    end
  end
end
-- ==== channel helpers ====
-- Get source channel count (ignores item channel mode)
local function get_source_channels(it)
  if not it then return 2 end
  local tk = reaper.GetActiveTake(it)
  if not tk then return 2 end
  local src = reaper.GetMediaItemTake_Source(tk)
  if not src then return 2 end
  local ch = reaper.GetMediaSourceNumChannels(src) or 2
  return ch
end

-- Get item's actual playback channel count (respects take channel mode setting)
-- This considers whether the take is set to mono, stereo, or multichannel
local function get_item_channels(it)
  if not it then return 2 end

  local tk = reaper.GetActiveTake(it)
  if not tk then return 2 end

  -- Get take's channel mode setting (IMPORTANT: use GetMediaItemTakeInfo_Value, not GetMediaItemInfo_Value!)
  -- I_CHANMODE: 0=normal, 1=reverse stereo, 2=downmix to mono, 3=left only, 4=right only, 5+=multichannel
  local chanmode = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE")

  -- If set to mono (modes 2, 3, or 4), return 1
  if chanmode == 2 or chanmode == 3 or chanmode == 4 then
    return 1
  end

  -- Otherwise, use source channels
  return get_source_channels(it)
end

local function unit_max_channels(u)
  if not u or not u.items or #u.items == 0 then return 2 end
  local maxch = 1
  for _,it in ipairs(u.items) do
    local ch = get_item_channels(it)
    if ch > maxch then maxch = ch end
  end
  return maxch
end
-- =========================
function getSelectedMedia() --Get value of Media Item that is selected
  local selitem = 0
  local mediaItem = reaper.GetSelectedMediaItem(0, selitem)
  debug(mediaItem)
  return mediaItem
end

local function countSelected() --Makes sure there is only 1 MediaItem selected
  if reaper.CountSelectedMediaItems(0) == 1 then
    debug("Media Item is Selected! \n")
    return true
    else 
      debug("Must Have only ONE Media Item Selected")
      return false
  end
end

function checkSelectedFX() --Determines if a TrackFX is selected, and which FX is selected
  local retval = 0
  local tracknumberOut = 0
  local itemnumberOut = 0
  local fxnumberOut = 0
  local window = false

  -- Check for OVERRIDE ExtState first (set by GUI for SAVED CHAIN/HISTORY execution)
  local override_track_idx = reaper.GetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX")
  local override_fx_idx = reaper.GetExtState("hsuanice_AS", "OVERRIDE_FX_IDX")

  if override_track_idx ~= "" and override_fx_idx ~= "" then
    -- Use override values from GUI
    tracknumberOut = tonumber(override_track_idx) + 1  -- Convert 0-based to 1-based
    fxnumberOut = tonumber(override_fx_idx)
    retval = 1  -- Success

    debug(string.format("\n[OVERRIDE] Using track=%d, fx=%d", tracknumberOut, fxnumberOut))

    -- Clear override for next run
    reaper.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", "", false)
    reaper.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", "", false)
  else
    -- Fall back to GetFocusedFX
    retval, tracknumberOut, itemnumberOut, fxnumberOut = reaper.GetFocusedFX()
    debug ("\n"..retval..tracknumberOut..itemnumberOut..fxnumberOut)
  end

  -- Normalize FX index: strip container (0x2000000) and input/floating (0x1000000) flags
  local raw_fx = fxnumberOut or 0
  if raw_fx >= 0x2000000 then raw_fx = raw_fx - 0x2000000 end
  if raw_fx >= 0x1000000 then raw_fx = raw_fx - 0x1000000 end
  fxnumberOut = raw_fx

  local track = tracknumberOut - 1
  
  if track == -1 then
    track = 0
  else
  end
  
  local mtrack = reaper.GetTrack(0, track)
  
  window = reaper.TrackFX_GetOpen(mtrack, fxnumberOut)
  
  return retval, tracknumberOut, itemnumberOut, fxnumberOut, window
end

function getFXname(trackNumber, fxNumber) --Get FX name
  local track = trackNumber - 1
  local FX = fxNumber
  local FXname = ""

  local mTrack = reaper.GetTrack (0, track)
    
  local retvalfx, FXname = reaper.TrackFX_GetFXName(mTrack, FX, FXname)
    
  return FXname, mTrack
end

function bypassUnfocusedFX(FXmediaTrack, fxnumber_Out, render)--bypass and unbypass FX on FXtrack
  FXtrack = FXmediaTrack
  FXnumber = fxnumber_Out

  FXtotal = reaper.TrackFX_GetCount(FXtrack)
  FXtotal = FXtotal - 1
  
  if render == false then
    for i = 0, FXtotal do
      if i == FXnumber then
        reaper.TrackFX_SetEnabled(FXtrack, i, true)
      else
        reaper.TrackFX_SetEnabled(FXtrack, i, false)
      end
    end
  else
    for i = 0, FXtotal do
      reaper.TrackFX_SetEnabled(FXtrack, i, true)
      i = i + 1
    
    end
  end
  
  return
end

function getLoopSelection()--Checks to see if there is a loop selection
  local startOut, endOut = 0, 0
  local isSet, isLoop, allowautoseek = false, false, false

  startOut, endOut = reaper.GetSet_LoopTimeRange(isSet, isLoop, startOut, endOut, allowautoseek)
  local hasLoop = not (startOut == 0 and endOut == 0)
  return hasLoop, startOut, endOut
end

-- Build processing units from current selection:
-- same track, position-sorted, merge items that touch/overlap into one unit.
-- ===== epsilon helpers (early shim for forward calls) =====
if not project_epsilon then
  function project_epsilon()
    local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    return (sr and sr > 0) and (1.0 / sr) or 1e-6
  end
end

if not approx_eq then
  function approx_eq(a, b, eps)
    eps = eps or project_epsilon()
    return math.abs(a - b) <= eps
  end
end

if not ranges_touch_or_overlap then
  function ranges_touch_or_overlap(a0, a1, b0, b1, eps)
    eps = eps or project_epsilon()
    return not (a1 < b0 - eps or b1 < a0 - eps)
  end
end
-- ==========================================================
local function build_units_from_selection()
  local n = reaper.CountSelectedMediaItems(0)
  local by_track = {}
  for i = 0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local tr  = reaper.GetMediaItem_Track(it)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local fin = pos + len
      by_track[tr] = by_track[tr] or {}
      table.insert(by_track[tr], { item=it, pos=pos, fin=fin })
    end
  end

  local units = {}
  local eps = project_epsilon()
  for tr, arr in pairs(by_track) do
    table.sort(arr, function(a,b) return a.pos < b.pos end)
    local cur = nil
    for _, e in ipairs(arr) do
      if not cur then
        cur = { track=tr, items={ e.item }, UL=e.pos, UR=e.fin }
      else
        if ranges_touch_or_overlap(cur.UL, cur.UR, e.pos, e.fin, eps) then
          table.insert(cur.items, e.item)
          if e.pos < cur.UL then cur.UL = e.pos end
          if e.fin > cur.UR then cur.UR = e.fin end
        else
          table.insert(units, cur)
          cur = { track=tr, items={ e.item }, UL=e.pos, UR=e.fin }
        end
      end
    end
    if cur then table.insert(units, cur) end
  end

  -- debug dump
  log_step("UNITS", "count=%d", #units)
  if debug_enabled() then
    for i,u in ipairs(units) do
      reaper.ShowConsoleMsg(string.format("  unit#%d  track=%s  members=%d  span=%.3f..%.3f\n",
        i, tostring(u.track), #u.items, u.UL, u.UR))
    end
  end
  return units
end

-- Collect units intersecting a time selection
local function collect_units_intersecting_ts(units, tsL, tsR)
  local out = {}
  -- Guard: only process one item via Core when not in TS-Window mode
  local processed_core_once = false
  for _,u in ipairs(units) do
    if ranges_touch_or_overlap(u.UL, u.UR, tsL, tsR, project_epsilon()) then
      table.insert(out, u)
    end
  end
  log_step("TS-INTERSECT", "TS=[%.3f..%.3f]  hit_units=%d", tsL, tsR, #out)
  return out
end

-- Strict: TS equals unit when both edges match within epsilon
local function ts_equals_unit(u, tsL, tsR)
  local eps = project_epsilon()
  return approx_eq(u.UL, tsL, eps) and approx_eq(u.UR, tsR, eps)
end

local function select_only_items(items)
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  for _,it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
end

local function move_items_to_track(items, destTrack)
  for _, it in ipairs(items) do
    -- Enhanced safety check: only move MediaItem*
    if it and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, it, "MediaItem*")) then
      reaper.MoveMediaItemToTrack(it, destTrack)
    else
      log_step("WARN", "move_items_to_track: skipped non-item entry=%s", tostring(it))
    end
  end
end

-- Are all items on a certain track?
local function items_all_on_track(items, tr)
  for _,it in ipairs(items) do
    if not it then return false end
    local cur = reaper.GetMediaItem_Track(it)
    if cur ~= tr then return false end
  end
  return true
end

-- Select only specified items (ensure selection matches unit)
local function select_only_items_checked(items)
  reaper.Main_OnCommand(40289, 0)
  for _,it in ipairs(items) do
    if it and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, it, "MediaItem*")) then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end

local function isolate_focused_fx(FXtrack, focusedIndex)
  -- enable only focusedIndex; others bypass
  local cnt = reaper.TrackFX_GetCount(FXtrack)
  for i = 0, cnt-1 do
    reaper.TrackFX_SetEnabled(FXtrack, i, i == focusedIndex)
  end
end

-- Forward declare helpers used below
local append_fx_to_take_name

-- Max FX tokens cap (via user option AS_MAX_FX_TOKENS)
local function max_fx_tokens()
  local n = get_max_fx_tokens()
  if not n or n < 1 then
    return math.huge -- unlimited
  end
  return math.floor(n)
end

-- === Take name normalization helpers (for AS naming) ===
local function strip_extension(name)
  return (name or ""):gsub("%.[A-Za-z0-9]+$", "")
end

-- remove "glued-XX", "render XXX/edX" and any trailing " - Something"
local function strip_glue_render_and_trailing_label(name)
  local s = name or ""
  s = s:gsub("[_%-%s]*glue[dD]?[%s_%-%d]*", "")
  s = s:gsub("[_%-%s]*render[eE]?[dD]?[%s_%-%d]*", "")
  s = s:gsub("%s+%-[%s%-].*$", "") -- remove trailing " - Something"
  s = s:gsub("%s+$","")
  s = s:gsub("[_%-%s]+$","")
  return s
end

-- tokens like "glued", "render", or "ed123"/"dup3" should be ignored
-- NOTE: do NOT drop pure-numeric tokens (e.g., "1073", "1176"), since some FX aliases are numeric.
local function is_noise_token(tok)
  local t = tostring(tok or ""):lower()
  if t == "" then return true end
  if t == "glue" or t == "glued" or t == "render" or t == "rendered" then return true end
  if t:match("^ed%d*$")  then return true end  -- e.g. "ed1", "ed23"
  if t:match("^dup%d*$") then return true end  -- e.g. "dup1"
  return false
end
-- Try parse "Base-AS{n}-FX1_FX2" and tolerate extra tails like "-ASx-YYY"
-- Return: base (string), n (number), fx_tokens (table)
local function parse_as_tag(full)
  local s = tostring(full or "")
  local base, n, tail = s:match("^(.-)[-_]AS(%d+)[-_](.+)$")
  if not base or not n then
    return nil, nil, nil
  end
  base = base:gsub("%s+$", "")

  -- If tail contains another "-ASx-" (e.g., "Saturn2-AS1-ProQ4"), only keep the part **before** the next AS tag.
  local first_tail = tail:match("^(.-)[-_]AS%d+[-_].*$") or tail

  -- PRE-CLEAN: strip legacy artifacts BEFORE tokenizing
  -- Remove whole "glued-XX", "render 001"/"rendered-03", and "ed###"/"dup###" sequences.
  local cleaned = first_tail
  cleaned = cleaned
              :gsub("[_%-%s]*glue[dD]?[%s_%-%d]*", "")     -- remove "glued" plus any digits/underscores/hyphens/spaces after it
              :gsub("[_%-%s]*render[eE]?[dD]?[%s_%-%d]*", "") -- remove "render"/"rendered" plus trailing digits etc.
              :gsub("ed%d+", "")                            -- remove "ed###"
              :gsub("dup%d+", "")                           -- remove "dup###"
              :gsub("%s+%-[%s%-].*$", "")                   -- trailing " - Something"
              :gsub("^[_%-%s]+", "")                        -- leading separators
              :gsub("[_%-%s]+$", "")                        -- trailing separators

  -- Tokenize FX names (alnum only), keep order.
  -- NOTE: pure numeric tokens are allowed (e.g., "1073"), since some aliases are numeric by design.
  local fx_tokens = {}
  for tok in cleaned:gmatch("([%w]+)") do
    if tok ~= "" and not tok:match("^AS%d+$") and not is_noise_token(tok) then
      fx_tokens[#fx_tokens+1] = tok
    end
  end

  return base, tonumber(n), fx_tokens
end
-- Shared: move single item to FX track and apply "focused FX only"
local function apply_focused_fx_to_item(item, FXmediaTrack, fxIndex, FXName)
  if not item then return false, -1 end
  local origTR = reaper.GetMediaItem_Track(item)

  -- ★ Snapshot take's channel info BEFORE moving (MoveMediaItemToTrack might affect it!)
  local tk = reaper.GetActiveTake(item)
  local orig_chanmode = tk and reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0
  local orig_src_ch = get_source_channels(item)

  -- ★ NEW: snapshot FX enable state (preserve original bypass/enable)
  local fx_enable_snap = snapshot_fx_enables(FXmediaTrack)

  -- Move to FX track and isolate
  reaper.MoveMediaItemToTrack(item, FXmediaTrack)
  dbg_item_brief(item, "TS-APPLY moved→FX")
  local __AS = AS_merge_args_with_extstate({})
  if __AS.mode == "focused" then
    isolate_focused_fx(FXmediaTrack, fxIndex)
  else
    -- chain mode: do NOT isolate; apply entire track FX chain
  end

  -- Choose 40361/41993 based on ExtState channel mode (or auto-detect from item channels)
  local apply_fx_mode = reaper.GetExtState("hsuanice_AS","AS_APPLY_FX_MODE")
  -- Calculate item_ch from ORIGINAL chanmode (current chanmode was reset to 0 by move)
  local ch
  if orig_chanmode == 2 or orig_chanmode == 3 or orig_chanmode == 4 then
    ch = 1  -- mono modes
  else
    ch = orig_src_ch  -- use source channels
  end
  local prev_nchan = tonumber(reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN")) or 2
  local cmd_apply  = 41993
  local did_set    = false

  -- Resolve channel mode: explicit setting from GUI or auto-detect
  local use_mono = false
  if apply_fx_mode == "mono" then
    use_mono = true
    if debug_enabled() then
      log_step("TS-APPLY", "AS_APPLY_FX_MODE='mono' (explicit) → use 40361")
    end
  elseif apply_fx_mode == "multi" then
    use_mono = false
    if debug_enabled() then
      log_step("TS-APPLY", "AS_APPLY_FX_MODE='multi' (explicit) → use 41993")
    end
  else
    -- auto or empty: detect from item playback channels (respects item channel mode)
    use_mono = (ch <= 1)
    if debug_enabled() then
      log_step("TS-APPLY", "AS_APPLY_FX_MODE='%s' → auto: source_ch=%d, item_ch=%d (orig_chanmode=%d) → use %d",
        apply_fx_mode, orig_src_ch, ch, orig_chanmode, use_mono and 40361 or 41993)
    end
  end

  if use_mono then
    cmd_apply = 40361
  else
    local desired = (ch % 2 == 0) and ch or (ch + 1)
    if prev_nchan ~= desired then
      log_step("TS-APPLY", "I_NCHAN %d → %d (pre-apply)", prev_nchan, desired)
      reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired)
      did_set = true
    end
  end

  -- Select only that item then execute apply
  reaper.Main_OnCommand(40289, 0)
  reaper.SetMediaItemSelected(item, true)
  reaper.Main_OnCommand(cmd_apply, 0)
  log_step("TS-APPLY", "applied %d", cmd_apply)
  dbg_dump_selection("TS-APPLY post-apply")

  -- Restore I_NCHAN (if changed)
  if did_set then
    log_step("TS-APPLY", "I_NCHAN restore %d → %d", reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN"), prev_nchan)
    reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
  end

  -- Retrieve the applied item (still the single selected item), rename, move back
  local out = reaper.GetSelectedMediaItem(0, 0) or item
  append_fx_to_take_name(out, FXName)
  reaper.MoveMediaItemToTrack(out, origTR)

  -- ★ NEW: restore FX enable state (back to original bypass/enable)
  restore_fx_enables(FXmediaTrack, fx_enable_snap)

  return true, cmd_apply
end

-- Single item: use RGWH Core Render (new take; keep old take; render both Take FX and Track FX)
local function apply_focused_via_rgwh_render_new_take(item, FXmediaTrack, fxIndex, FXName)
  if not item then return false end
  local origTR = reaper.GetMediaItem_Track(item)

  -- ★ Snapshot take's channel mode BEFORE moving (MoveMediaItemToTrack might affect it!)
  local tk = reaper.GetActiveTake(item)
  local orig_chanmode = tk and reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0
  local orig_src_ch = get_source_channels(item)

  -- ★ NEW: snapshot FX enable state (preserve original bypass/enable)
  local fx_enable_snap = snapshot_fx_enables(FXmediaTrack)

  -- Move to FX track + isolate focused FX only (Track FX original enable/bypass state preserved; here just bypass non-focused)
  reaper.MoveMediaItemToTrack(item, FXmediaTrack)
  dbg_item_brief(item, "RGWH-RENDER moved→FX")
  local __AS = AS_merge_args_with_extstate({})
  if __AS.mode == "focused" then
    isolate_focused_fx(FXmediaTrack, fxIndex)
  else
    -- chain mode: do NOT isolate; render full chain
  end

  -- Select only this item as the render selection
  reaper.Main_OnCommand(40289, 0)
  reaper.SetMediaItemSelected(item, true)

  -- Load RGWH Core
  local CORE_PATH = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"
  local ok_mod, M = pcall(dofile, CORE_PATH)
  if not ok_mod or not M or type(M.render_selection) ~= "function" then
    -- ★ Restore FX enable state before returning
    restore_fx_enables(FXmediaTrack, fx_enable_snap)
    log_step("ERROR", "render_selection not available in RGWH Core")
    return false
  end

  -- ★ Important fix: use RGWH Core's "positional parameter" call version, ensure TAKE/TRACK flags = true
  --   M.render_selection(take_fx, track_fx, apply_mode, tc_embed)
  --   Read apply_mode from ExtState (set by GUI), fallback to "auto"
  local apply_fx_mode = reaper.GetExtState("hsuanice_AS","AS_APPLY_FX_MODE")
  if apply_fx_mode == "" then apply_fx_mode = "auto" end

  -- Resolve "auto" mode to "mono" or "multi" based on item's ORIGINAL playback channels
  -- (use orig_chanmode because MoveMediaItemToTrack resets chanmode to 0!)
  if apply_fx_mode == "auto" then
    -- Calculate item_ch from original chanmode
    local item_ch
    if orig_chanmode == 2 or orig_chanmode == 3 or orig_chanmode == 4 then
      item_ch = 1  -- mono modes
    else
      item_ch = orig_src_ch  -- use source channels
    end
    apply_fx_mode = (item_ch >= 2) and "multi" or "mono"

    if debug_enabled() then
      log_step("RGWH-RENDER", "auto mode: source_ch=%d, item_ch=%d (orig_chanmode=%d) → resolved to '%s'",
        orig_src_ch, item_ch, orig_chanmode, apply_fx_mode)
    end
  else
    if debug_enabled() then
      log_step("RGWH-RENDER", "AS_APPLY_FX_MODE from ExtState: '%s' (explicit)", apply_fx_mode)
    end
  end

  local ok_call, ret_or_err = pcall(M.render_selection, 1, 1, apply_fx_mode, "current")
  if not ok_call then
    log_step("ERROR", "render_selection() runtime error: %s", tostring(ret_or_err))
    -- Still attempt to retrieve new output below, in case Core errored but actually produced a new take
  end

  -- Retrieve item with new take (still selected), rename and move back to original track
  local out = reaper.GetSelectedMediaItem(0, 0) or item
  append_fx_to_take_name(out, FXName)
  reaper.MoveMediaItemToTrack(out, origTR)

  -- ★ NEW: restore FX enable state (back to original bypass/enable)
  restore_fx_enables(FXmediaTrack, fx_enable_snap)

  return true
end

function append_fx_to_take_name(item, fxName)
  if not item or not fxName or fxName == "" then return end
  local takeIndex = reaper.GetMediaItemInfo_Value(item, "I_CURTAKE")
  local take      = reaper.GetMediaItemTake(item, takeIndex)
  if not take then return end

  local _, tn0 = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local tn_noext = strip_extension(tn0 or "")

  -- naming debug: before
  if debug_naming_enabled() then
    reaper.ShowConsoleMsg(("[AS][NAME] before='%s'\n"):format(tn0 or ""))
  end

  local baseAS, nAS, fx_tokens = parse_as_tag(tn_noext)

  local base, n, tokens
  if baseAS and nAS then
    base   = strip_glue_render_and_trailing_label(baseAS)
    n      = nAS + 1
    tokens = fx_tokens or {}
  else
    base   = strip_glue_render_and_trailing_label(tn_noext)
    n      = 1
    tokens = {}
  end

  -- always append new FX (allow duplicates; preserve chronological order)
  table.insert(tokens, fxName)

  -- Apply user cap (FIFO): keep only the last N tokens
  do
    local cap = max_fx_tokens()
    if cap ~= math.huge and #tokens > cap then
      local start = #tokens - cap + 1
      local trimmed = {}
      for i = start, #tokens do
        trimmed[#trimmed+1] = tokens[i]
      end
      tokens = trimmed
    end
  end

  local fx_concat = table.concat(tokens, "_")
  local new_name = string.format("%s-AS%d-%s", base, n, fx_concat)

  -- naming debug: after
  if debug_naming_enabled() then
    reaper.ShowConsoleMsg(("[AS][NAME] after ='%s'\n"):format(new_name))
  end

  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
end

function mediaItemInLoop(mediaItem, startLoop, endLoop)
  local mpos = reaper.GetMediaItemInfo_Value(mediaItem, "D_POSITION")
  local mlen = reaper.GetMediaItemInfo_Value(mediaItem, "D_LENGTH")
  local mend = mpos + mlen
  -- use 1 sample as epsilon
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  local eps = (sr and sr > 0) and (1.0 / sr) or 1e-6

  local function approx_eq(a, b) return math.abs(a - b) <= eps end

  -- TS equals unit ONLY when both edges match (within epsilon)
  return approx_eq(mpos, startLoop) and approx_eq(mend, endLoop)
end


function cropNewTake(mediaItem, tracknumber_Out, FXname)--Crop to new take and change name to add FXname

  track = tracknumber_Out - 1
  
  fxName = FXname
    
  --reaper.Main_OnCommand(40131, 0) --This is what crops to the Rendered take. With this removed, you will have a take for each FX you apply
  
  currentTake = reaper.GetMediaItemInfo_Value(mediaItem, "I_CURTAKE")
  
  take = reaper.GetMediaItemTake(mediaItem, currentTake)
  
  local _, takeName = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local newName = takeName
  if fxName ~= "" then
    newName = takeName .. " - " .. fxName
  end
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", newName, true)
  return true
end

function setNudge()
  reaper.ApplyNudge(0, 0, 0, 0, 1, false, 0)
  reaper.ApplyNudge(0, 0, 0, 0, -1, false, 0)
end

function main() -- main part of the script
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  if debug_enabled() then
    reaper.ShowConsoleMsg("\n=== AudioSweet (hsuanice) run ===\n")
  end
  log_step("BEGIN", "selected_items=%d", reaper.CountSelectedMediaItems(0))
  -- snapshot original selection so we can restore it at the very end
  local sel_snapshot = snapshot_selection()

  -- Focused FX check
  local AS_args = AS_merge_args_with_extstate({})
  local ret_val, tracknumber_Out, itemnumber_Out, fxnumber_Out, window = checkSelectedFX()

  -- In chain mode, if no focused FX, use first selected track as fallback
  if ret_val ~= 1 and AS_args.mode == "chain" then
    local first_track = reaper.GetSelectedTrack(0, 0)
    if first_track then
      tracknumber_Out = reaper.CSurf_TrackToID(first_track, false)
      fxnumber_Out = 0
      ret_val = 1  -- Pretend focus check passed
      log_step("CHAIN-FALLBACK", "No focused FX, using first selected track (tr#=%d)", tracknumber_Out)
    end
  end

  if ret_val ~= 1 then
    reaper.MB("Please focus a Track FX (not a Take FX).", "AudioSweet", 0)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet (no focused Track FX)", -1)
    return
  end
  log_step("FOCUSED-FX", "trackOut=%d  itemOut=%d  fxOut=%d  window=%s", tracknumber_Out, itemnumber_Out, fxnumber_Out, tostring(window))

  -- Normalize focused FX index & resolve name/track
  local fxIndex = fxnumber_Out
  if fxIndex >= 0x1000000 then fxIndex = fxIndex - 0x1000000 end
  local FXNameRaw, FXmediaTrack = getFXname(tracknumber_Out, fxIndex)
  local FXName = format_fx_label(FXNameRaw)
  log_step("FOCUSED-FX", "index(norm)=%d  name='%s' (raw='%s')  FXtrack=%s",
           fxIndex, tostring(FXName or ""), tostring(FXNameRaw or ""), tostring(FXmediaTrack))

  -- Determine naming token based on mode (focused vs chain)
  local naming_token = FXName
  if AS_args.mode == "chain" then
    naming_token = build_chain_token(FXmediaTrack)
    if naming_token == "" then naming_token = FXName end
    log_step("CHAIN-TOKEN", "mode=chain  token='%s' (source=%s)",
             tostring(naming_token), tostring(get_chain_token_source()))
  end

  -- === Early branch: COPY mode (non-destructive; no rename) ===
  do
    local AS = AS_merge_args_with_extstate({})
    if AS.action == "copy" then
      local ops = 0
      if AS.mode == "focused" then
        ops = AS_copy_focused_fx_to_items(FXmediaTrack, fxIndex, AS)
        log_step("COPY", "focused FX → items  scope=%s pos=%s  ops=%d", tostring(AS.scope), tostring(AS.append_pos), ops)
        reaper.Undo_EndBlock(string.format("AudioSweet: Copy focused FX to items (%d op)", ops), 0)
      else
        ops = AS_copy_chain_to_items(FXmediaTrack, AS)
        log_step("COPY", "FX CHAIN → items  scope=%s pos=%s  ops=%d", tostring(AS.scope), tostring(AS.append_pos), ops)
        reaper.Undo_EndBlock(string.format("AudioSweet: Copy FX chain to items (%d op)", ops), 0)
      end
      reaper.UpdateArrange()
      restore_selection(sel_snapshot)
      reaper.PreventUIRefresh(-1)
      return
    end
  end
  -- === End COPY branch; continue into APPLY flow ===


  -- Build units from current selection
  local units = build_units_from_selection()
  if #units == 0 then
    reaper.MB("No media items selected.", "AudioSweet", 0)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet (no items)", -1)
    return
  end

  if debug_enabled() then
    for i,u in ipairs(units) do dbg_dump_unit(u, i) end
  end  

  -- Time selection state
  local hasTS, tsL, tsR = getLoopSelection()
  if debug_enabled() then
    log_step("PATH", "hasTS=%s TS=[%.3f..%.3f]", tostring(hasTS), tsL or -1, tsR or -1)
  end

  -- Helper: Core flags setup/restore
  local function proj_get(ns, key, def)
    local _, val = reaper.GetProjExtState(0, ns, key)
    if val == "" then return def else return val end
  end
  local function proj_set(ns, key, val)
    reaper.SetProjExtState(0, ns, key, tostring(val or ""))
  end

  -- Process (two paths)
  local outputs = {}

  if hasTS then
    -- Figure out how many units intersect the TS
    local hit = collect_units_intersecting_ts(units, tsL, tsR)
    if debug_enabled() then
      log_step("PATH", "TS hit_units=%d → %s", #hit, (#hit>=2 and "TS-WINDOW[GLOBAL]" or "per-unit"))
    end    
    if #hit >= 2 then
      ------------------------------------------------------------------
      -- TS-Window (GLOBAL): Pro Tools behavior (no handles)
      ------------------------------------------------------------------
      log_step("TS-WINDOW[GLOBAL]", "begin TS=[%.3f..%.3f] units_hit=%d", tsL, tsR, #hit)
      log_step("PATH", "ENTER TS-WINDOW[GLOBAL]")

      -- Select all items in intersecting units (on their original tracks)
      reaper.Main_OnCommand(40289, 0)
      for _,u in ipairs(hit) do
        for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      end
      log_step("TS-WINDOW[GLOBAL]", "pre-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[GLOBAL] pre-42432")      -- ★ NEW
      reaper.Main_OnCommand(42432, 0) -- Glue items within time selection (no handles)
      log_step("TS-WINDOW[GLOBAL]", "post-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[GLOBAL] post-42432")     -- ★ NEW

      -- Each glued result: first copy current selection to stable list, then apply one by one
      local glued_items = {}
      do
        local n = reaper.CountSelectedMediaItems(0)
        for i = 0, n - 1 do
          local it = reaper.GetSelectedMediaItem(0, i)
          if it then glued_items[#glued_items + 1] = it end
        end
      end

      for idx, it in ipairs(glued_items) do
        local ok, used_cmd = apply_focused_fx_to_item(it, FXmediaTrack, fxIndex, naming_token)
        if ok then
          log_step("TS-WINDOW[GLOBAL]", "applied %d to glued #%d", used_cmd or -1, idx)
          -- Get the actually applied item (function sets selection to this item)
          local out_item = reaper.GetSelectedMediaItem(0, 0)
          if out_item then table.insert(outputs, out_item) end
        else
          log_step("TS-WINDOW[GLOBAL]", "apply failed on glued #%d", idx)
        end
      end

      log_step("TS-WINDOW[GLOBAL]", "done, outputs=%d", #outputs)

      -- Restore pre-execution selection (picks new glued/printed clips on same track and range)
      restore_selection(sel_snapshot)
      if debug_enabled() then dbg_dump_selection("RESTORE selection") end

      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("AudioSweet TS-Window (global) glue+print", 0)
      return
    end
    -- else: TS hits 0 or 1 unit → fall through to per-unit branch below
  end

  ----------------------------------------------------------------------
  -- Per-unit path:
  --   - No TS: Core/GLUE (with handles)
  --   - Has TS and TS==unit: Core/GLUE (with handles)
  --   - Has TS and TS≠unit: TS-Window (UNIT; no handles) → 42432 → 40361
  ----------------------------------------------------------------------
  for _,u in ipairs(units) do
    log_step("UNIT", "enter UL=%.3f UR=%.3f members=%d", u.UL, u.UR, #u.items)
    dbg_dump_unit(u, -1) -- dump the current unit (−1 = “in-process” marker)
    if hasTS and not ts_equals_unit(u, tsL, tsR) then
      log_step("PATH", "TS-WINDOW[UNIT] UL=%.3f UR=%.3f", u.UL, u.UR)
      --------------------------------------------------------------
      -- TS-Window (UNIT) no handles: 42432 → 40361
      --------------------------------------------------------------
      -- select only this unit's items and glue within TS
      reaper.Main_OnCommand(40289, 0)
      for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      log_step("TS-WINDOW[UNIT]", "pre-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[UNIT] pre-42432")        -- ★ NEW
      reaper.Main_OnCommand(42432, 0)
      log_step("TS-WINDOW[UNIT]", "post-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[UNIT] post-42432")       -- ★ NEW

      local glued = reaper.GetSelectedMediaItem(0, 0)
      if not glued then
        reaper.MB("TS-Window glue failed: no item after 42432 (unit).", "AudioSweet", 0)
        goto continue_unit
      end

      local ok, used_cmd = apply_focused_fx_to_item(glued, FXmediaTrack, fxIndex, naming_token)
      if ok then
        log_step("TS-WINDOW[UNIT]", "applied %d", used_cmd or -1)
        table.insert(outputs, glued)  -- out item already moved back to original track
      else
        log_step("TS-WINDOW[UNIT]", "apply failed")
      end
    else
      --------------------------------------------------------------
      -- Core/GLUE or RGWH Render:
      --   No TS or TS==unit:
      --     • When unit has only 1 item → use RGWH Render (new take; keep old take)
      --     • When unit has ≥2 items   → use Core/GLUE (with handles)
      --------------------------------------------------------------
      if #u.items == 1 then
        -- === Single item: use RGWH Render (render both Take FX and Track FX; keep old take) ===
        local the_item = u.items[1]
        -- Debug: check take chanmode BEFORE calling render function
        if debug_enabled() then
          local tk = reaper.GetActiveTake(the_item)
          local pre_chanmode = tk and reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0
          local pre_src_ch = get_source_channels(the_item)
          log_step("UNIT", "pre-render: take chanmode=%d, source_ch=%d", pre_chanmode, pre_src_ch)
        end
        local ok = apply_focused_via_rgwh_render_new_take(the_item, FXmediaTrack, fxIndex, naming_token)
        if ok then
          table.insert(outputs, the_item) -- already moved back to original track and renamed
        else
          log_step("ERROR", "single-item RGWH render failed")
        end
      else
        -- === Multiple items: use Core/GLUE (with handles) ===

        -- Move all unit items to FX track (keep as-is), but select only the anchor for Core.
        move_items_to_track(u.items, FXmediaTrack)

        -- ★ NEW: snapshot FX enable state (preserve original bypass/enable)
        local fx_enable_snap_core = snapshot_fx_enables(FXmediaTrack)

        -- Enable only focused FX, temporarily bypass others
        local __AS = AS_merge_args_with_extstate({})
        if __AS.mode == "focused" then
          isolate_focused_fx(FXmediaTrack, fxIndex)
        else
          -- chain mode: leave all FX enabled as-is (full chain)
        end

        -- Select the entire unit (non-TS path should preserve full unit selection)
        local anchor = u.items[1]  -- still used for channel auto and safety
        select_only_items_checked(u.items)

        -- [DBG] after move
        do
          local moved = 0
          for _,it in ipairs(u.items) do
            if it and reaper.GetMediaItem_Track(it) == FXmediaTrack then
              moved = moved + 1
            end
          end
          log_step("CORE", "post-move: on-FX=%d / unit=%d", moved, #u.items)

          if debug_enabled() then
            local L = u.UL - project_epsilon()
            local R = u.UR + project_epsilon()
            dbg_track_items_in_range(FXmediaTrack, L, R)
          end
        end

        -- [DBG] selection should equal the full unit at this point
        do
          local selN = reaper.CountSelectedMediaItems(0)
          log_step("CORE", "pre-apply selection count=%d (expect=%d)", selN, #u.items)
          dbg_dump_selection("CORE pre-apply selection")
        end

        -- Load Core
        local failed = false
        local CORE_PATH = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"
        local ok_mod, mod = pcall(dofile, CORE_PATH)
        if not ok_mod or not mod then
          log_step("ERROR", "Core load failed: %s", CORE_PATH)
          reaper.MB("RGWH Core not found or failed to load:\n" .. CORE_PATH, "AudioSweet — Core load failed", 0)
          failed = true
        end

        local core_api = nil
        if not failed then
          core_api = (type(mod)=="table" and type(mod.core)=="function") and mod.core
                     or (type(mod)=="table" and type(mod.glue_selection)=="function") and mod.glue_selection
          if not core_api then
            log_step("ERROR", "RGWH.core or RGWH.glue_selection not found in module")
            reaper.MB("RGWH Core loaded, but M.core() or M.glue_selection() not found.", "AudioSweet — Core API missing", 0)
            failed = true
          end
        end

        -- Resolve auto apply_fx_mode by MAX channels across the entire unit
        -- Use item's actual playback channels (respects item channel mode), not source channels
        local apply_fx_mode = nil
        if not failed then
          apply_fx_mode = reaper.GetExtState("hsuanice_AS","AS_APPLY_FX_MODE")
          if apply_fx_mode == "" or apply_fx_mode == "auto" then
            local ch = unit_max_channels(u)
            apply_fx_mode = (ch <= 1) and "mono" or "multi"
            if debug_enabled() then
              log_step("CORE", "AS_APPLY_FX_MODE='%s' → auto-detect: unit_max_ch=%d → resolved to '%s'",
                (apply_fx_mode == "" and "empty" or "auto"), ch, apply_fx_mode)
            end
          else
            if debug_enabled() then
              log_step("CORE", "AS_APPLY_FX_MODE from ExtState: '%s' (explicit)", apply_fx_mode)
            end
          end
        end

        if debug_enabled() then
          local c = reaper.CountSelectedMediaItems(0)
          log_step("CORE", "pre-apply selected_items=%d (expect = unit members=%d)", c, #u.items)
        end

        -- Snapshot & set project flags
        local snap = {}
        local function proj_get(ns, key, def)
          local _, val = reaper.GetProjExtState(0, ns, key); return (val == "" and def) or val
        end
        local function proj_set(ns, key, val)
          reaper.SetProjExtState(0, ns, key, tostring(val or ""))
        end

        -- Check: are all unit items already on FX track
        if not items_all_on_track(u.items, FXmediaTrack) then
          log_step("ERROR", "unit members not on FX track; fixing...")
          move_items_to_track(u.items, FXmediaTrack)
        end
        -- Check: does selection equal the entire unit
        select_only_items_checked(u.items)
        if debug_enabled() then
          log_step("CORE", "pre-apply selected_items=%d (expect=%d)", reaper.CountSelectedMediaItems(0), #u.items)
        end

        -- Snapshot
        snap.GLUE_TAKE_FX      = proj_get("RGWH","GLUE_TAKE_FX","")
        snap.GLUE_TRACK_FX     = proj_get("RGWH","GLUE_TRACK_FX","")
        snap.GLUE_APPLY_MODE   = proj_get("RGWH","GLUE_APPLY_MODE","")
        snap.GLUE_SINGLE_ITEMS = proj_get("RGWH","GLUE_SINGLE_ITEMS","")

        -- Set desired flags
        proj_set("RGWH","GLUE_TAKE_FX","1")
        proj_set("RGWH","GLUE_TRACK_FX","1")
        proj_set("RGWH","GLUE_APPLY_MODE",apply_fx_mode)
        proj_set("RGWH","GLUE_SINGLE_ITEMS","1")

        if debug_enabled() then
          local _, gsi = reaper.GetProjExtState(0, "RGWH", "GLUE_SINGLE_ITEMS")
          log_step("CORE", "flag GLUE_SINGLE_ITEMS=%s (expected=1 for unit-glue)", (gsi == "" and "(empty)") or gsi)
        end

        -- Prepare arguments and call Core
        if not (anchor and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, anchor, "MediaItem*"))) then
          log_step("ERROR", "anchor item invalid (u.items[1]=%s)", tostring(anchor))
          reaper.MB("Internal error: unit anchor item is invalid.", "AudioSweet", 0)
          failed = true
        else
          -- Use new M.core() API
          local is_chain_mode = (AS_merge_args_with_extstate({}).mode == "chain")
          local args = {
            op = "glue",
            channel_mode = apply_fx_mode,
            take_fx = true,
            track_fx = true,
          }
          if debug_enabled() then
            local c = reaper.CountSelectedMediaItems(0)
            log_step("CORE", "call M.core: op=%s channel_mode=%s take_fx=true track_fx=true unit_members=%d",
              tostring(args.op), tostring(args.channel_mode), #u.items)
            log_step("CORE", "pre-apply FINAL selected_items=%d", c)
            dbg_dump_selection("CORE pre-apply FINAL")
          end

          local ok_call, ok_apply, err = pcall(core_api, args)
          if not ok_call then
            log_step("ERROR", "M.core() runtime error: %s", tostring(ok_apply))
            reaper.MB("RGWH Core M.core() runtime error:\n" .. tostring(ok_apply), "AudioSweet — Core error", 0)
            failed = true
          else
            if not ok_apply then
              if debug_enabled() then
                log_step("ERROR", "M.core() returned false; err=%s", tostring(err))
              end
              reaper.MB("RGWH Core M.core() error:\n" .. tostring(err or "(nil)"), "AudioSweet — Core error", 0)
              failed = true
            end
          end
        end

        -- Restore flags
        proj_set("RGWH","GLUE_TAKE_FX",      snap.GLUE_TAKE_FX)
        proj_set("RGWH","GLUE_TRACK_FX",     snap.GLUE_TRACK_FX)
        proj_set("RGWH","GLUE_APPLY_MODE",   snap.GLUE_APPLY_MODE)
        proj_set("RGWH","GLUE_SINGLE_ITEMS", snap.GLUE_SINGLE_ITEMS)

        -- Pick output, rename, move back
        if not failed then
          local postItem = reaper.GetSelectedMediaItem(0, 0)
          if not postItem then
            reaper.MB("Core finished, but no item is selected.", "AudioSweet", 0)
            failed = true
          else
            append_fx_to_take_name(postItem, naming_token)
            local origTR = u.track
            reaper.MoveMediaItemToTrack(postItem, origTR)
            table.insert(outputs, postItem)
          end

          if debug_enabled() then
            dbg_dump_selection("CORE post-apply selection")
            if postItem then
              dbg_item_brief(postItem, "CORE picked postItem")
            end
          end
        end

        -- Move remaining items (if any) in unit back to original track; restore FX enable state
        move_items_to_track(u.items, u.track)

        -- ★ NEW: restore FX enable state (back to original bypass/enable)
        restore_fx_enables(FXmediaTrack, fx_enable_snap_core)
      end
    end
    ::continue_unit::
  end

  log_step("END", "outputs=%d", #outputs)

  -- Restore pre-execution selection
  restore_selection(sel_snapshot)
  if debug_enabled() then dbg_dump_selection("RESTORE selection") end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("AudioSweet multi-item glue", 0)
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
