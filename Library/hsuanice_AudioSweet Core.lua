--[[
@description AudioSweet (hsuanice) — Focused Track FX render via RGWH Core, append FX name, rebuild peaks (selected items)
@version 251009_2249   Fixed: Single-item (non TS-Window) path no longer forces all FX enabled after render.
@author Tim Chimes (original), adapted by hsuanice
@notes
  Reference:
  AudioSuite-like Script. Renders the selected plugin to the selected media item.
  Written for REAPER 5.1 with Lua
  v1.1 12/22/2015 — Added PreventUIRefresh
  Written by Tim Chimes
  http://chimesaudio.com

This version:
  • Keep original flow/UX
  • Replace the render step with hsuanice_RGWH Core
  • Append the focused Track FX full name to the take name after render
  • Use Peaks: Rebuild peaks for selected items (40441) instead of the nudge trick
  • Track FX only (Take FX not supported)

@changelog
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
-- How many FX names to keep in the “-ASn-...” suffix.
-- 0 or nil = unlimited; N>0 = keep last N tokens (FIFO).
local AS_MAX_FX_TOKENS = 3

-- Naming-only debug (console print before/after renaming).
-- Toggle directly in this script (no ExtState).
local AS_DEBUG_NAMING = true
local function debug_naming_enabled() return AS_DEBUG_NAMING == true end

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
-- ExtState 開關（若沒設定則讀 default）
local FXNAME_DEFAULT_SHOW_TYPE    = false  -- 是否包含 type（如 "VST3:" / "CLAP:"）
local FXNAME_DEFAULT_SHOW_VENDOR  = false  -- 是否包含廠牌（括號內）
local FXNAME_DEFAULT_STRIP_SYMBOL = true  -- 是否移除空格與符號（僅保留字母數字）

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

-- 解析 REAPER FX 顯示名稱：
--  例： "CLAP: Pro-Q 4 (FabFilter)" → type="CLAP", core="Pro-Q 4", vendor="FabFilter"
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
  -- NEW: 先查 alias；若有就直接用
  local alias = fx_alias_for_raw_label(raw)
  if type(alias) == "string" and alias ~= "" then
    return alias
  end

  -- 以下保留你原本的行為
  local opt = fxname_opts()
  local typ, core, vendor = parse_fx_label(raw)

  local base
  if opt.show_type and typ ~= "" then
    base = typ .. ": " .. core
  else
    base = core
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
local AS_USE_ALIAS   = true   -- 設為 false 可暫時停用別名
local AS_DEBUG_ALIAS = (reaper.GetExtState("hsuanice_AS","AS_DEBUG_ALIAS") == "1")

-- 簡單正規化：全小寫、移除非英數
local function _norm(s) return (tostring(s or ""):lower():gsub("[^%w]+","")) end

-- 懶載入 JSON（需系統已有 dkjson 或同等 json.decode）
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
    -- JSON 檔不存在 → 試 TSV 後援
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end
  local blob = f:read("*a"); f:close()

  -- 探測/載入 JSON 解碼器
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
    -- 沒有解碼器 → 試 TSV 後援
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end

  local ok, data = pcall(decode, blob)
  if not ok or type(data) ~= "table" then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] JSON decode failed or not a table\n")
    end
    -- JSON 解析失敗 → 試 TSV 後援
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end

  -- 支援兩種形態：
  -- (A) 物件： { ["vst3|core|vendor"] = { alias="FOO", ... }, ... }
  -- (B) 陣列： [ { fingerprint="vst3|core|vendor", alias="FOO", ... }, ... ]
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
--   fingerprint <TAB> alias  (其他欄位可有可無)
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

  -- 找欄位索引
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
-- 更強的 raw 解析：抓 host/type、去除括號後的 core、以及最外層括號當 vendor
-- 例： "VST3: UADx Manley VOXBOX Channel Strip (Universal Audio (UADx))"
--  => host="vst3", core="uadxmanleyvoxboxchannelstrip", vendor="universalaudiouadx"
local function _parse_raw_label_host_core_vendor(raw)
  raw = tostring(raw or "")

  -- host/type
  local host = raw:match("^%s*([%w_]+)%s*:") or ""
  host = host:lower()

  -- core：取冒號後整段，再去除所有括號內容與非英數
  local core = raw:match(":%s*(.+)$") or ""
  core = core:gsub("%b()", "")            -- 去掉所有括號段
               :gsub("%s+%-[%s%-].*$", "")-- 去掉 " - Something" 類尾巴（防萬一）
               :gsub("%W", "")            -- 非英數去掉
               :lower()

  -- vendor：用 %b() 擷取「每一段平衡括號」，取最後一段
  local last = nil
  for seg in raw:gmatch("%b()") do
    last = seg
  end
  local vendor = ""
  if last and #last >= 2 then
    vendor = last:sub(2, -2)              -- 去掉首尾括號
    vendor = vendor:gsub("%W", ""):lower()
  end

  return host, core, vendor
end
-- 回傳別名或 nil（強化：支援 vendor 併入 core 的鍵、加掃描 fallback 與除錯輸出）
function fx_alias_for_raw_label(raw_label)
  if not AS_USE_ALIAS then return nil end
  local m = _alias_map()
  if not m then return nil end

  -- 主解析
  local host, core, vendor = _parse_raw_label_host_core_vendor(raw_label)

  -- 舊解析一次（兼容老鍵）
  local typ2, core2, vendor2 = parse_fx_label(raw_label)
  local t2 = _norm(typ2)
  local c2 = _norm(core2)
  local v2 = _norm(vendor2)

  local t = host
  local c = core
  local v = vendor

  -- 組各種候選鍵
  local key1  = string.format("%s|%s|%s", t,  c,  v)
  local key2  = string.format("%s|%s|",    t,  c)
  local key2b = (v ~= "" and string.format("%s|%s%s|", t, c, v)) or nil
  local key3  = string.format("|%s|",      c)

  local key1b = string.format("%s|%s|%s", t2, c2, v2)
  local key2c = string.format("%s|%s|",    t2, c2)
  local key2d = (v2 ~= "" and string.format("%s|%s%s|", t2, c2, v2)) or nil
  local key3b = string.format("|%s|",      c2)

  local hit, from

  -- 直接命中
  if type(m[key1]) == "string" and m[key1] ~= "" then hit, from = m[key1], "exact" end
  if not hit and type(m[key2]) == "string" and m[key2] ~= "" then hit, from = m[key2], "empty-vendor" end
  if not hit and key2b and type(m[key2b]) == "string" and m[key2b] ~= "" then hit, from = m[key2b], "core+vendor-as-core" end
  if not hit and type(m[key3]) == "string" and m[key3] ~= "" then hit, from = m[key3], "cross-type" end

  -- 兼容舊鍵
  if not hit and type(m[key1b]) == "string" and m[key1b] ~= "" then hit, from = m[key1b], "exact(legacy)" end
  if not hit and type(m[key2c]) == "string" and m[key2c] ~= "" then hit, from = m[key2c], "empty-vendor(legacy)" end
  if not hit and key2d and type(m[key2d]) == "string" and m[key2d] ~= "" then hit, from = m[key2d], "core+vendor-as-core(legacy)" end
  if not hit and type(m[key3b]) == "string" and m[key3b] ~= "" then hit, from = m[key3b], "cross-type(legacy)" end

  -- 兜底掃描
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
  reaper.Main_OnCommand(40289, 0) -- 清空
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
          -- 只要這顆 item 覆蓋原來的選取範圍就認定是對應項（TS-Window 會生成貼齊的 glued 片段）
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
local function get_item_channels(it)
  if not it then return 2 end
  local tk = reaper.GetActiveTake(it)
  if not tk then return 2 end
  local src = reaper.GetMediaItemTake_Source(tk)
  if not src then return 2 end
  local ch = reaper.GetMediaSourceNumChannels(src) or 2
  return ch
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
  
  retval, tracknumberOut, itemnumberOut, fxnumberOut = reaper.GetFocusedFX()
  debug ("\n"..retval..tracknumberOut..itemnumberOut..fxnumberOut)

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
    -- 強化防呆：只搬 MediaItem*
    if it and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, it, "MediaItem*")) then
      reaper.MoveMediaItemToTrack(it, destTrack)
    else
      log_step("WARN", "move_items_to_track: skipped non-item entry=%s", tostring(it))
    end
  end
end

-- 所有 items 都在某 track 上？
local function items_all_on_track(items, tr)
  for _,it in ipairs(items) do
    if not it then return false end
    local cur = reaper.GetMediaItem_Track(it)
    if cur ~= tr then return false end
  end
  return true
end

-- 只選取指定 items（保證 selection 與 unit 一致）
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
  local n = tonumber(AS_MAX_FX_TOKENS)
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
-- 共用：把單一 item 搬到 FX 軌並列印「只有聚焦 FX」
local function apply_focused_fx_to_item(item, FXmediaTrack, fxIndex, FXName)
  if not item then return false, -1 end
  local origTR = reaper.GetMediaItem_Track(item)

  -- ★ 新增：快照 FX 啟用狀態（保留原本 bypass/enable）
  local fx_enable_snap = snapshot_fx_enables(FXmediaTrack)

  -- 移到 FX 軌並 isolate
  reaper.MoveMediaItemToTrack(item, FXmediaTrack)
  dbg_item_brief(item, "TS-APPLY moved→FX")
  local __AS = AS_merge_args_with_extstate({})
  if __AS.mode == "focused" then
    isolate_focused_fx(FXmediaTrack, fxIndex)
  else
    -- chain mode: do NOT isolate; apply entire track FX chain
  end

  -- 依素材聲道決定 40361 / 41993；並視需要暫調 I_NCHAN
  local ch         = get_item_channels(item)
  local prev_nchan = tonumber(reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN")) or 2
  local cmd_apply  = 41993
  local did_set    = false

  if ch <= 1 then
    cmd_apply = 40361
  else
    local desired = (ch % 2 == 0) and ch or (ch + 1)
    if prev_nchan ~= desired then
      log_step("TS-APPLY", "I_NCHAN %d → %d (pre-apply)", prev_nchan, desired)
      reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired)
      did_set = true
    end
  end

  -- 只選該 item 後執行 apply
  reaper.Main_OnCommand(40289, 0)
  reaper.SetMediaItemSelected(item, true)
  reaper.Main_OnCommand(cmd_apply, 0)
  log_step("TS-APPLY", "applied %d", cmd_apply)
  dbg_dump_selection("TS-APPLY post-apply")

  -- 還原 I_NCHAN（若有改）
  if did_set then
    log_step("TS-APPLY", "I_NCHAN restore %d → %d", reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN"), prev_nchan)
    reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
  end

  -- 取回列印出的那顆（仍是選取中的單一 item），改名、搬回
  local out = reaper.GetSelectedMediaItem(0, 0) or item
  append_fx_to_take_name(out, FXName)
  reaper.MoveMediaItemToTrack(out, origTR)

  -- ★ 新增：還原 FX 啟用狀態（回到原本 bypass/enable）
  restore_fx_enables(FXmediaTrack, fx_enable_snap)

  return true, cmd_apply
end

-- 單一 item：改用 RGWH Core 的 Render（新 take；保留舊 take；同時印 Take FX 與 Track FX）
local function apply_focused_via_rgwh_render_new_take(item, FXmediaTrack, fxIndex, FXName)
  if not item then return false end
  local origTR = reaper.GetMediaItem_Track(item)

  -- ★ 新增：快照 FX 啟用狀態（保留原本 bypass/enable）
  local fx_enable_snap = snapshot_fx_enables(FXmediaTrack)

  -- 移到 FX 軌 + isolate 只留聚焦 FX（Track FX 原始啟用/停用狀態保持；此處僅確保非聚焦者被 bypass）
  reaper.MoveMediaItemToTrack(item, FXmediaTrack)
  dbg_item_brief(item, "RGWH-RENDER moved→FX")
  local __AS = AS_merge_args_with_extstate({})
  if __AS.mode == "focused" then
    isolate_focused_fx(FXmediaTrack, fxIndex)
  else
    -- chain mode: do NOT isolate; render full chain
  end

  -- 單選這顆 item 作為 render 的 selection
  reaper.Main_OnCommand(40289, 0)
  reaper.SetMediaItemSelected(item, true)

  -- 載入 RGWH Core
  local CORE_PATH = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"
  local ok_mod, M = pcall(dofile, CORE_PATH)
  if not ok_mod or not M or type(M.render_selection) ~= "function" then
    -- ★ 還原 FX 啟用狀態後再返回
    restore_fx_enables(FXmediaTrack, fx_enable_snap)
    log_step("ERROR", "render_selection not available in RGWH Core")
    return false
  end

  -- ★ 重要修正：改用 RGWH Core 的「位置參數」呼叫版本，確保 TAKE/TRACK 旗標 = true
  --   M.render_selection(take_fx, track_fx, apply_mode, tc_embed)
  --   其中 apply_mode="auto" 會由 Core 依素材聲道決定 mono/multi
  local ok_call, ret_or_err = pcall(M.render_selection, 1, 1, "auto", "current")
  if not ok_call then
    log_step("ERROR", "render_selection() runtime error: %s", tostring(ret_or_err))
    -- 照樣往下嘗試拾取新輸出，避免 Core 雖報錯但其實已產生新 take 的情況漏處理
  end

  -- 取回新 take 所在 item（仍在選取中），改名後搬回原軌
  local out = reaper.GetSelectedMediaItem(0, 0) or item
  append_fx_to_take_name(out, FXName)
  reaper.MoveMediaItemToTrack(out, origTR)

  -- ★ 新增：還原 FX 啟用狀態（回到原本 bypass/enable）
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
  local ret_val, tracknumber_Out, itemnumber_Out, fxnumber_Out, window = checkSelectedFX()
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
      -- TS-Window (GLOBAL): Pro Tools 行為（無 handles）
      ------------------------------------------------------------------
      log_step("TS-WINDOW[GLOBAL]", "begin TS=[%.3f..%.3f] units_hit=%d", tsL, tsR, #hit)
      log_step("PATH", "ENTER TS-WINDOW[GLOBAL]")

      -- Select all items in intersecting units (on their original tracks)
      reaper.Main_OnCommand(40289, 0)
      for _,u in ipairs(hit) do
        for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      end
      log_step("TS-WINDOW[GLOBAL]", "pre-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[GLOBAL] pre-42432")      -- ★ 新增
      reaper.Main_OnCommand(42432, 0) -- Glue items within time selection (no handles)
      log_step("TS-WINDOW[GLOBAL]", "post-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[GLOBAL] post-42432")     -- ★ 新增

      -- Each glued result: 先把當前選取複製成穩定清單，再逐一列印
      local glued_items = {}
      do
        local n = reaper.CountSelectedMediaItems(0)
        for i = 0, n - 1 do
          local it = reaper.GetSelectedMediaItem(0, i)
          if it then glued_items[#glued_items + 1] = it end
        end
      end

      for idx, it in ipairs(glued_items) do
        local ok, used_cmd = apply_focused_fx_to_item(it, FXmediaTrack, fxIndex, FXName)
        if ok then
          log_step("TS-WINDOW[GLOBAL]", "applied %d to glued #%d", used_cmd or -1, idx)
          -- 取真正列印完的那顆（函式內會把選取變成這顆）
          local out_item = reaper.GetSelectedMediaItem(0, 0)
          if out_item then table.insert(outputs, out_item) end
        else
          log_step("TS-WINDOW[GLOBAL]", "apply failed on glued #%d", idx)
        end
      end

      log_step("TS-WINDOW[GLOBAL]", "done, outputs=%d", #outputs)

      -- 還原執行前的選取（會挑回同軌同範圍的新 glued/printed 片段）
      restore_selection(sel_snapshot)
      if debug_enabled() then dbg_dump_selection("RESTORE selection") end

      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("AudioSweet TS-Window (global) glue+print", 0)
      return
    end
    -- else: TS 命中 0 或 1 個 unit → 落到下面 per-unit 分支
  end

  ----------------------------------------------------------------------
  -- Per-unit path:
  --   - 無 TS：Core/GLUE（含 handles）
  --   - 有 TS 且 TS==unit：Core/GLUE（含 handles）
  --   - 有 TS 且 TS≠unit：TS-Window（UNIT；無 handles）→ 42432 → 40361
  ----------------------------------------------------------------------
  for _,u in ipairs(units) do
    log_step("UNIT", "enter UL=%.3f UR=%.3f members=%d", u.UL, u.UR, #u.items)
    dbg_dump_unit(u, -1) -- dump the current unit (−1 = “in-process” marker)
    if hasTS and not ts_equals_unit(u, tsL, tsR) then
      log_step("PATH", "TS-WINDOW[UNIT] UL=%.3f UR=%.3f", u.UL, u.UR)
      --------------------------------------------------------------
      -- TS-Window (UNIT) 無 handles：42432 → 40361
      --------------------------------------------------------------
      -- select only this unit's items and glue within TS
      reaper.Main_OnCommand(40289, 0)
      for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      log_step("TS-WINDOW[UNIT]", "pre-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[UNIT] pre-42432")        -- ★ 新增
      reaper.Main_OnCommand(42432, 0)
      log_step("TS-WINDOW[UNIT]", "post-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[UNIT] post-42432")       -- ★ 新增

      local glued = reaper.GetSelectedMediaItem(0, 0)
      if not glued then
        reaper.MB("TS-Window glue failed: no item after 42432 (unit).", "AudioSweet", 0)
        goto continue_unit
      end

      local ok, used_cmd = apply_focused_fx_to_item(glued, FXmediaTrack, fxIndex, FXName)
      if ok then
        log_step("TS-WINDOW[UNIT]", "applied %d", used_cmd or -1)
        table.insert(outputs, glued)  -- out item已被移回原軌
      else
        log_step("TS-WINDOW[UNIT]", "apply failed")
      end
    else
      --------------------------------------------------------------
      -- Core/GLUE 或 RGWH Render：
      --   無 TS 或 TS==unit：
      --     • 當 unit 只有 1 顆 item → 走 RGWH Render（新 take；保留舊 take）
      --     • 當 unit ≥2 顆 item   → 維持 Core/GLUE（含 handles）
      --------------------------------------------------------------
      if #u.items == 1 then
        -- === 單一 item：使用 RGWH Render（同時印 Take FX 與 Track FX；保留舊 take） ===
        local the_item = u.items[1]
        local ok = apply_focused_via_rgwh_render_new_take(the_item, FXmediaTrack, fxIndex, FXName)
        if ok then
          table.insert(outputs, the_item) -- 已搬回原軌且命名完成
        else
          log_step("ERROR", "single-item RGWH render failed")
        end
      else
        -- === 多 item：維持 Core/GLUE（含 handles） ===

        -- Move all unit items to FX track (keep as-is), but select only the anchor for Core.
        move_items_to_track(u.items, FXmediaTrack)

        -- ★ 新增：快照 FX 啟用狀態（保留原本 bypass/enable）
        local fx_enable_snap_core = snapshot_fx_enables(FXmediaTrack)

        -- 只啟用聚焦 FX，其他暫時 bypass
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

        local apply = nil
        if not failed then
          apply = (type(mod)=="table" and type(mod.apply)=="function") and mod.apply
                   or (_G.RGWH and type(_G.RGWH.apply)=="function" and _G.RGWH.apply)
          if not apply then
            log_step("ERROR", "RGWH.apply not found in module")
            reaper.MB("RGWH Core loaded, but RGWH.apply(...) not found.", "AudioSweet — Core apply missing", 0)
            failed = true
          end
        end

        -- Resolve auto apply_fx_mode by MAX channels across the entire unit
        local apply_fx_mode = nil
        if not failed then
          apply_fx_mode = reaper.GetExtState("hsuanice_AS","AS_APPLY_FX_MODE")
          if apply_fx_mode == "" or apply_fx_mode == "auto" then
            local ch = unit_max_channels(u)
            apply_fx_mode = (ch <= 1) and "mono" or "multi"
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

        -- 檢查：unit 的所有 items 是否已在 FX 軌
        if not items_all_on_track(u.items, FXmediaTrack) then
          log_step("ERROR", "unit members not on FX track; fixing...")
          move_items_to_track(u.items, FXmediaTrack)
        end
        -- 檢查：selection 是否等於整個 unit
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

        -- 準備參數並呼叫 Core
        if not (anchor and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, anchor, "MediaItem*"))) then
          log_step("ERROR", "anchor item invalid (u.items[1]=%s)", tostring(anchor))
          reaper.MB("Internal error: unit anchor item is invalid.", "AudioSweet", 0)
          failed = true
        else
          local args = {
            mode                = "glue_item_focused_fx",
            item                = anchor,
            apply_fx_mode       = apply_fx_mode,
            focused_track       = FXmediaTrack,
            focused_fxindex     = fxIndex,
            policy_only_focused = (AS_merge_args_with_extstate({}).mode == "focused"),
            selection_scope     = "selection",
          }
          if debug_enabled() then
            local c = reaper.CountSelectedMediaItems(0)
            log_step("CORE", "apply args: mode=%s apply_fx_mode=%s focus_idx=%d sel_scope=%s unit_members=%d",
              tostring(args.mode), tostring(args.apply_fx_mode), fxIndex, tostring(args.selection_scope), #u.items)
            log_step("CORE", "pre-apply FINAL selected_items=%d", c)
            dbg_dump_selection("CORE pre-apply FINAL")
          end

          local ok_call, ok_apply, err = pcall(apply, args)
          if not ok_call then
            log_step("ERROR", "apply() runtime error: %s", tostring(ok_apply))
            reaper.MB("RGWH Core apply() runtime error:\n" .. tostring(ok_apply), "AudioSweet — Core apply error", 0)
            failed = true
          else
            if not ok_apply then
              if debug_enabled() then
                log_step("ERROR", "apply() returned false; err=%s", tostring(err))
              end
              reaper.MB("RGWH Core apply() error:\n" .. tostring(err or "(nil)"), "AudioSweet — Core apply error", 0)
              failed = true
            end
          end
        end

        -- 還原旗標
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
            append_fx_to_take_name(postItem, FXName)
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

        -- 將 unit 內其餘（若有）搬回原軌；還原 FX 啟用狀態
        move_items_to_track(u.items, u.track)

        -- ★ 新增：還原 FX 啟用狀態（回到原本 bypass/enable）
        restore_fx_enables(FXmediaTrack, fx_enable_snap_core)
      end
    end
    ::continue_unit::
  end

  log_step("END", "outputs=%d", #outputs)

  -- 還原執行前的選取
  restore_selection(sel_snapshot)
  if debug_enabled() then dbg_dump_selection("RESTORE selection") end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("AudioSweet multi-item glue", 0)
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)