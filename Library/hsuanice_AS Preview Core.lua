--[[
@description AudioSweet Preview Core
@version 0.1.1
@author hsuanice

@provides
  [main] .

@about Minimal, self-contained preview runtime. Later we can extract helpers to "hsuanice_AS Core.lua".

@changelog
  0.1.1 (2025-12-21) [internal: v251221.2141]
    - ADDED: Track channel count restoration after preview
      • Snapshots track I_NCHAN before preview starts
      • Restores original channel count in cleanup_if_any()
      • Prevents REAPER auto-expansion from persisting after preview
      • Works in both focused and chain preview modes
  0.1.0 (2025-12-13) - Initial Public Beta Release
    Minimal preview runtime for AudioSweet with:
    - High-precision timing using reaper.time_precise()
    - Handle-aware edge/glue cue policies
    - Selection restore with verification
    - Integration with AudioSweet ReaImGui and RGWH Core
    - Fixed: Preview item move bug when FX track is below source track (collect-then-move pattern)
    - Enhanced debug logging for item move verification

  Internal Build v251213.0008
    - Fixed: Preview item move bug when FX track is below source track.
      * Previously: moving items during iteration caused selection index shift, resulting in even-indexed items being skipped.
      * Now: collect all items first, then move them in a separate loop to avoid index invalidation.
      * Affected scenario: when preview target track has a higher track number than the source track.
    - Added: Enhanced debug logging for item move verification (shows item count and positions before/after move).
    - Behavior: No change to audio path or preview workflow; only fixes the move operation reliability.

  Internal Build v251017_1337
    - Verified: removed all Chinese inline comments; file is now fully English-only for public release.
    - Checked: indentation, spacing, and comment alignment preserved exactly.
    - No functional or behavioral changes; logic identical to v251016_2305.
    - Purpose: finalize English translation pass for consistency across the AudioSweet Core libraries.

  v251016_2305
    - Changed: Translated all remaining inline comments from Chinese to English for consistency.
      * Areas covered: function headers and inline notes within Core state, switch mode, and placeholder handling.
    - No functional change. Behavior identical to v251016_1851.
    - Purpose: maintain unified English documentation style for public release.

  v251016_1851
    - Added: High-precision timing using reaper.time_precise().
      * Exports: snapshot_ms, core_ms, restore_ms, total_ms.
      * Printed via "[WRAPPER][Perf] snapshot=... core=... restore=... total=...".
    - Added: Compact one-line "Selection Debug/Perf" summary for large-scale sessions.
    - Changed: Wrapper overhead minimized (≈1–5 ms typical); Core remains the only heavy stage.
    - Changed: Edge/Glue cue policy aligned with Core.
      * WRITE_EDGE_CUES=true, WRITE_GLUE_CUES=true.
      * GLUE_CUE_POLICY="adjacent-different-source".
    - Fixed: Selection restore now verified only once after Core cleanup (no redundant selection updates).
    - Fixed: Error guards — Core error messages (e.g. "focus track missing") are passed through as summaries only.
    - Removed: Dependency on SWS extension (BR_GetMediaItemGUID).
      * Before: reaper.BR_GetMediaItemGUID(item)
      * After:  local ok, guid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
      * Validation: Native and SWS GUIDs identical ("Equal? true").
    - Dev: DEBUG flag affects verbosity only; functional behavior unchanged.
    - Dev: Legacy target="track" removed.
      * chain_mode=true  → target="name:<TrackName>" or target_track_name.
      * chain_mode=false → forced target="focused".

  v251012_2008
    - Change: Focused preview (chain_mode=false) now forces target="focused".
      * Any name-based target (including `target="TARGET_TRACK_NAME"` or `target_track_name`) is ignored in focused mode.
      * This makes switching between chain and focused modes trivial from the template: just flip `chain_mode`.
    - Docs: Updated ASP.preview() arg comments to clarify forced-focused behavior when chain_mode=false.

  v251012_1615
    - Change: Removed support for the literal mode `target = "track"`.
      * Core now only exposes two target forms: "focused" and name-based targets
        (via `target_track_name`, `target = "name:<TrackName>"`, or the sentinel `target = "TARGET_TRACK_NAME"`).
      * The normalization path no longer accepts `"track"`; any previous wrapper relying on
        `target="track"` must switch to name-based or focused mode.
    - Docs: Updated comments in `_resolve_target` and `ASP.preview` to reflect supported forms.
    - Behavior: No change to focused/name-based flows; fallbacks and logs unchanged.

  v251012_0030
    - Change: Single-pass target normalization in ASP.preview(); no mutation of args.
      * All accepted forms now normalize to a single target spec before resolution:
        - target = "focused"
        - target = "name:<TrackName>"
        - target = MediaTrack*
        - target = { by="name"|"guid"|"index"|"focused", value=... }
        - target_track_name = "<TrackName>"
        - target = "TARGET_TRACK_NAME"  (reads _G.TARGET_TRACK_NAME)
      * Only one call to _resolve_target() is made after normalization.
    - Added: Convenience support for `target = "TARGET_TRACK_NAME"` (reads `_G.TARGET_TRACK_NAME`).
    - Behavior: Unchanged audio path and fallbacks:
      * Default target when nothing specified → {by="name", value="AudioSweet"}.
      * If resolution fails, fallback to "name:AudioSweet".
      * Chain mode still ignores FX index; focused mode still requires a valid FX index.
    - Dev Notes: Clearer, faster code path; logs and loop behavior unchanged.

  v251012_0010
    - Added: Support for `target = "TARGET_TRACK_NAME"` sugar.
      * When this is used and `_G.TARGET_TRACK_NAME` is defined,
        the Core will resolve it as a track name target automatically.
      * Internally converts it to `args.target_track_name = _G.TARGET_TRACK_NAME`
        and clears `args.target` to reuse existing name-based logic.
    - Purpose: Simplify Template usage — no need for `target_track_name = TARGET_TRACK_NAME`.
      The user now only sets `local TARGET_TRACK_NAME = "YourTrack"`
      and switches mode with `target = "TARGET_TRACK_NAME"`.

  v251010_2152
    - Added: Convenience arg `target_track_name` for ASP.preview(); equivalent to `target={by="name", value="<name>"}`.
    - Added: Default target fallback to `"AudioSweet"` when neither `target` nor `target_track_name` is provided.
    - Improved: Argument docs for ASP.preview() to include `target_track_name`.
    - Behavior: Non-breaking — sugar only applies when `args.target` is nil; existing wrappers continue to work.
    - Notes: Chain vs Focused behavior unchanged; placeholder label logic unchanged (FX name in focused mode, track name in chain mode).

  v2510082330
    - Fix: Forward-declare `undo_begin` / `undo_end_no_undo` and bind locals so early callers never hit nil.
    - Change: Consolidated no-undo guards (start, mode switch, cleanup) to suppress all undo points.
    - Added: `USER_RESTORE_MODE` option ("guid" | "timesel") with overlap preflight and clear warning dialog.
    - Added: Source-track placeholder detection and re-entry bootstrap; time-selection windowing in timesel restore.
    - Improved: Debug logs (counts, chosen restore mode, FX isolation) for easier tracing.
    - Behavior: Audio path unchanged; solo scope still via `USER_SOLO_SCOPE` ("track" | "item"); wrappers unchanged.

  v2510082151
    - Added: USER_RESTORE_MODE user option ("guid" | "timesel") to control move-back behavior on cleanup.
      * "guid": only move back items that were explicitly moved during this preview session.
      * "timesel": move back all FX-track items overlapping the placeholder or time selection.
    - Added: Overlap-check safeguard before moving items back to source track.
      * If overlap is detected, a warning dialog appears:
        "Move-back aborted: one or more items would overlap existing items on the source track."
        The move-back process aborts safely to prevent collisions.
    - Implemented: Helper functions item_bounds() and track_has_overlap() for robust span checks.
    - Improved: Cleanup flow now logs which restore mode was used and how many items were restored.
    - Behavior: Maintains no-undo protection; integrates seamlessly with existing Preview Core state machine.
    - Note: USER_RESTORE_MODE is a Core-only option; wrappers do not need to set this.
  v2510061248 WIP — No-undo hardening (switch/apply paths)
    - _switch_mode(): wrapped entire body in Undo_BeginBlock2/EndBlock2(...,-1) to suppress all undo points when toggling solo/normal.
    - _apply_mode_flags(): added a protective no-undo block around solo clear/apply + Transport:Play.
    - Rationale: many native actions create undo points unless executed inside a -1 end block; this guarantees Preview Core leaves no undo traces.

  v2510060105 WIP — No-undo scaffolding landed (partial)
    - Added undo_begin()/undo_end_no_undo() around preview start, mode switch, and cleanup paths.
    - Core debug/user options kept as-is; wrappers unchanged.

    Still creates undo points (TO-DO)
    - Moving selected items to the FX track (preview enter).
    - Isolating/restoring focused FX enable mask.
    - Moving items back to source track & removing the placeholder (preview exit).

    Notes
    - Console debug stream unchanged (no auto-clear).
    - Behavior/functionality unaffected; only undo suppression is in progress.

  v2510060105 Change to no undo
    - Wrap mutating ops in undo_begin()/undo_end_no_undo() to avoid creating undo points.
    - Cleanup and mode switch now do not create undo points.
  v2510052349 — Core-only user options for SOLO_SCOPE/DEBUG
    - Moved user-configurable options into Core: 
      - USER_SOLO_SCOPE = "track" | "item" (default "track")
      - USER_DEBUG = false (enable Core logs when true)
    - Core no longer reads/writes ExtState for SOLO_SCOPE/DEBUG. Wrappers do not need to set these anymore.
    - PREVIEW_MODE still comes from ExtState so wrappers can choose solo vs normal.
    - Added a startup log line to print the current SOLO_SCOPE and DEBUG states.

  v2510052343 — Clarify item tint constant
    - Documentation: explained that `0x1000000` sets the high bit of the color integer, which tells REAPER the custom color is *active*.
    - The color field `I_CUSTOMCOLOR` is stored as `RGB | 0x1000000` where the high bit (0x1000000) enables the tint.
    - Functionally unchanged: placeholder items still tinted bright red for visibility.

  v2510052318 — Fix ranges_touch_or_overlap() nil on re-entry
    - Moved forward declarations (project_epsilon, ranges_touch_or_overlap) to the top so any caller can resolve them.
    - Removed the later duplicate forward-decl block to prevent late-binding/globals turning nil at runtime.
    - Behavior unchanged otherwise: placeholder on source track, re-entry bootstrap, mode switch, and cleanup all intact.
    - Debug stream unchanged (no auto-clear).

  Known issues
    - Razor selection not implemented yet (current order: Time Selection > items span).
    - Cross-wrapper toggle still relies on wrappers updating ExtState hsuanice_AS:PREVIEW_MODE before calling Core.
    - If the placeholder is manually moved/deleted during playback, next run will rebuild by design.
  v2510052130 WIP — Preview Core: Solo scope via ExtState; item-solo uses 41558
    - Options: Core reads ExtState hsuanice_AS:SOLO_SCOPE = "track" (default) | "item".
    - Solo(track): clears item-solo (41185) & track-solo (40340), then forces FX track solo (I_SOLO=1).
    - Solo(item): selects moved items and uses 41558 “Item: Solo exclusive” (no prior unsolo needed).
    - Normal/cleanup: always clear both item-solo (41185) and track-solo (40340) to avoid leftover states.
    - Logs: switch/apply path now prints which scope was applied (TRACK/ITEM).

  v2510052021 Fix no item selection warning
    - Guard: Core now aborts early (no state changes) when there are no selected items.
    - Guard: If a Time Selection exists but none of the selected items intersect it, show a warning and abort.
    - UX: Clear dialog explains “select at least one item (or an item inside the time selection)”.
    - Logs: Prints `no-targets: abort` reasons in the continuous [AS][PREVIEW] stream when DEBUG=1.

  v2510051609 WIP — Preview Core: source-track placeholder detection, safer re-entry
    - Re-entry guard: run() now searches the placeholder **only on the original (source) track**, not the whole project, preventing duplicate placeholders and avoiding heavy scans.
    - State capture: when creating a preview, Core persists `src_track` so subsequent runs can resolve the placeholder even if selection focus moved to the FX track.
    - Cleanup hygiene: `cleanup_if_any()` now also clears `src_track` in state after restoring items and removing the placeholder.
    - Bootstrap on re-entry: if a placeholder is found on the source track, Core **does not rebuild**; it bootstraps runtime (collects moved items by the placeholder span) and only performs mode switching.
    - Logs: unchanged continuous `[AS][PREVIEW]` stream; no console clearing.

    Known issues / notes
    - Razor selection still pending (current order: Time Selection > items span).
    - Cross-wrapper toggle requires the wrapper to flip `hsuanice_AS:PREVIEW_MODE` before calling Core.
    - If the user manually deletes/moves the placeholder during playback, next run will rebuild (by design).
    - Not yet auto-aborting preview when launching full AudioSweet; planned follow-up.
    
  v2510051520 WIP — Placeholder-guarded reentry; no rebuild; true single-tap toggle
    - Core now treats the "PREVIEWING @ …" placeholder on the focused FX track as the ground-truth running flag.
    - On every run() call:
      - If a placeholder is found, Core bootstraps its runtime state (collects current preview items by the placeholder’s time span) and ONLY switches mode (solo↔normal). No re-glue, no re-move, no new placeholder.
      - If no placeholder is found, Core builds a fresh preview as before.
    - Mode switching in _switch_mode() now safely re-selects the moved items before toggling Item-Solo-Exclusive.
    - (Optional) You can pin the placeholder to the FX track (Hunk C) for simpler detection; or skip Hunk C to keep placeholders on source tracks.
    - Keeps your continuous debug stream intact; no console clearing.

    Known notes
    - Normal wrapper should mirror the same ExtState flip to allow cross-wrapper toggling.
    - If the user deletes/moves the placeholder during playback, Core will rebuild on next run (by design).
    - Razor selection still pending; current logic follows Time Selection > item span.

  v2510051403 WIP — Preview Core: ExtState-driven mode, move-based preview, placeholder lifecycle
    - ExtState mode: Core reads hsuanice_AS:PREVIEW_MODE ("solo"/"normal"); wrappers only flip this ExtState then call Core (fallback to opts.default_mode if empty).
    - Focused-FX isolation: snapshots per-FX enable mask on the focused track, enables only the focused FX during preview, restores the mask on cleanup.
    - Move-based preview: selected items are MOVED to the focused-FX track (no level-doubling); originals are replaced by a single white placeholder item.
    - Placeholder marker: one empty item with note `PREVIEWING @ Track <n> - <FXName>` spanning Time Selection (or selected-items span); also serves as the “preview is alive” flag.
    - Loop & stop: uses Time Selection if present else items span; forces Repeat ON; a stop-watcher detects transport stop and triggers full cleanup.
    - Cleanup: runs Unsolo-all (41185), moves items back to the placeholder’s track, removes the placeholder, restores FX-enable mask, selection, and Repeat state.
    - Live toggle: re-running Core while active flips solo↔normal without rebuilding or re-moving items (mode switch only).
    - Debug stream: continuous `[AS][PREVIEW]` logs when `hsuanice_AS:DEBUG=1` (no console clear).

    Known issues
    - Wrappers must set `hsuanice_AS:PREVIEW_MODE` before calling Core; legacy `opts.mode` still works as a fallback.
    - Razor selection not implemented yet (Time Selection / item selection only).
    - If the user manually deletes/moves the placeholder or preview items during playback, cleanup may be incomplete.
    - Not yet auto-aborting preview when launching full AudioSweet; planned: end preview first, then proceed.

  v2510050105 WIP — Preview Core: one-tap mode toggle, stop-to-cleanup, continuous debug
    - New state machine (ASP._state) with unified flags for running/mode/focused FX/preview items.
    - Single-tap live switching: calling run() with a different mode seamlessly flips solo↔normal during loop playback.
    - Stop watcher: auto-detects transport stop and performs full cleanup (delete preview items, restore repeat/selection).
    - Loop arming: honors Time Selection; otherwise spans selected items; auto-enables Repeat and restores to prior state.
    - Preview copies: selected items are cloned to the focused-FX track; per-mode flags are applied on the clones only.
    - Solo mode: applies “Item Solo Exclusive” to the preview copies (original items untouched).
    - Debug stream: enable with ExtState hsuanice_AS:DEBUG=1; prints continuous [AS][PREVIEW] logs (no console clear).
    - Public API: ASP.run{mode, focus_track, focus_fxindex}, ASP.toggle_mode(start_hint), ASP.is_running(), ASP.cleanup_if_any().

    Known issues
    - Normal (non-solo) mode currently clones without muting originals (will add original-mute snapshot in next pass).
    - Razor edits not yet parsed (TS or selected items only).
    - FX enable snapshot/restore is simplified; per-FX enable mask restore is planned.

  v2510050103 — Preview Core: seamless mode toggle, full state restore
    - Added run/switch/cleanup state machine: ASP._state tracks running/mode/fx target/unit/moved items.
    - One-track guard: preview only runs when all selected items are on a single track (multi-items OK).
    - Loop region: uses Time Selection if present; otherwise unit span; auto-enables Repeat and restores it after.
    - Normal (non-solo) mode: snapshots & mutes original items to avoid level doubling; copies items to FX track and plays.
    - Solo mode: toggles “Item solo exclusive” on the preview copies; original items remain unmuted.
    - Live mode switch: calling Preview again with the other mode flips normal↔solo without stopping playback.
    - Cleanup: on stop/end, turns off solo (if any), moves items back to original track, restores mutes/selection/FX enables/transport.
    - Debug: honors ExtState "hsuanice_AS:DEBUG" == "1" to print [AS][PREVIEW] steps.

    Known issues
    - Razor edits not yet parsed; preview spans Time Selection or unit range only.
    - FX enable restore is simplified to “re-enable all on FX track”; per-FX enable snapshot/restore can be added later.
    - If items are manually moved/deleted during preview, cleanup may not fully restore the original scene.

  2510042327 Initial version.
]]--

-- Solo scope for preview isolation: "track" or "item"
local USER_SOLO_SCOPE = "track"
-- Enable Core debug logs (printed via ASP.log / ASP.dlog)
local USER_DEBUG = true
-- Move-back strategy on cleanup:
--   "guid"     → move back only the items this preview moved (by GUID)
--   "timesel"  → move back ALL items on the FX track that overlap the placeholder/time selection
-- If overlap with destination (source track) is detected, a warning dialog is shown and the move-back is aborted.
local USER_RESTORE_MODE = "guid"  -- "guid" | "timesel"
-- =========================================================================

-- === [AS PREVIEW CORE · Debug / State] ======================================
local ASP = _G.ASP or {}
_G.ASP = ASP

-- ===== Forward declarations (must appear before any use) =====
local project_epsilon
local ranges_touch_or_overlap
local ranges_strict_overlap
local undo_begin
local undo_end_no_undo

-- ExtState keys
ASP.ES_NS         = "hsuanice_AS"
ASP.ES_STATE      = "PREVIEW_STATE"     -- json: {running=true/false, mode="solo"/"normal"}
ASP.ES_DEBUG      = "DEBUG"             -- "1" to enable logs
ASP.ES_MODE       = "PREVIEW_MODE"      -- "solo" | "normal" ; written by wrappers, read-only for Core

-- NEW: simple run-flag for cross-script handshake
ASP.ES_RUN        = "PREVIEW_RUN"       -- "1" while preview is running, else "0"

local function _set_run_flag(on)
  reaper.SetExtState(ASP.ES_NS, ASP.ES_RUN, on and "1" or "0", false)
end

-- Mode from ExtState (fallback to opts.default_mode or "solo")
local function read_mode(default_mode)
  local m = reaper.GetExtState(ASP.ES_NS, ASP.ES_MODE)
  if m == "solo" or m == "normal" then return m end
  return default_mode or "solo"
end

-- Solo scope from Core user option only
local function read_solo_scope()
  return (USER_SOLO_SCOPE == "item") and "item" or "track"
end

-- FX enable snapshot/restore on a track
local function snapshot_fx_enabled(track)
  local t = {}
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do
    t[i] = reaper.TrackFX_GetEnabled(track, i)
  end
  return t
end

local function restore_fx_enabled(track, shot)
  if not shot then return end
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do
    local want = shot[i]
    if want ~= nil then reaper.TrackFX_SetEnabled(track, i, want) end
  end
end

-- Isolate focused FX but keep a mask to restore later
local function isolate_only_focused_fx(track, fxindex)
  local mask = snapshot_fx_enabled(track)
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do reaper.TrackFX_SetEnabled(track, i, i == fxindex) end
  return mask
end

-- Compute preview span: Time Selection > items span
local function compute_preview_span()
  local L,R = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if R > L then return L, R end
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return nil,nil end
  local UL, UR
  for i=0, cnt-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    UL = UL and math.min(UL, pos) or pos
    UR = UR and math.max(UR, pos+len) or (pos+len)
  end
  return UL, UR
end

-- Placeholder: one red empty item with note = PREVIEWING @ Track <n> - <FXName>
local function make_placeholder(track, UL, UR, note)
  local it = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", UL or 0)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",  (UR and UL) and (UR-UL) or 1.0)
  local tk = reaper.AddTakeToMediaItem(it) -- just to satisfy note storage
  reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", true) -- keep empty name
  reaper.GetSetMediaItemInfo_String(it, "P_NOTES", note or "", true)
  -- set red tint for clarity (RGB | 0x1000000 enables the tint)
  reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", reaper.ColorToNative(255,0,0)|0x1000000)
  reaper.UpdateItemInProject(it)
  return it
end

local function remove_placeholder(it)
  if not it then return end
  reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it)
end

-- get item bounds [L, R]
local function item_bounds(it)
  local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  return L, R
end

-- check if moving an interval [UL,UR] into target track would overlap any existing item (excluding a given set and excluding a placeholder)
local function track_has_overlap(tr, UL, UR, exclude_set, placeholder_it, allow_guid_map)
  if not tr then return false end
  local ic = reaper.CountTrackMediaItems(tr)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if it ~= placeholder_it then
      local skip = false
      if exclude_set and it and exclude_set[it] then skip = true end
      if not skip then
        local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        if ranges_strict_overlap(L, R, UL, UR) then
          if allow_guid_map then
            local g = guid_of(it)
            if g and allow_guid_map[g] then
              -- allowed to overlap (original neighbor / crossfade partner)
              goto continue
            end
          end
          return true
        end
      end
    end
    ::continue::
  end
  return false
end
-- Find the placeholder item on the source track (identified by note prefix "PREVIEWING @")
local function find_placeholder_on_track(track)
  if not track then return nil end
  local ic = reaper.CountTrackMediaItems(track)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local _, note = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
    if note and note:find("^PREVIEWING @") then
      local UL  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local LEN = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      return it, UL, UL + LEN
    end
  end
  return nil
end



-- Collect items on the FX track that belong to the "previewed" set within the placeholder span (excluding the placeholder itself)
local function collect_preview_items_on_fx_track(track, ph_item, UL, UR)
  local items = {}
  if not track then return items end
  local ic = reaper.CountTrackMediaItems(track)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    if it ~= ph_item then
      local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if ranges_touch_or_overlap(L, R, UL, UR) then
        table.insert(items, it)
      end
    end
  end
  return items
end

-- Debug helpers
local function now_ts()
  return os.date("%H:%M:%S")
end

function ASP._dbg_enabled()
  return USER_DEBUG
end

function ASP.log(fmt, ...)
  if not ASP._dbg_enabled() then return end
  local msg = ("[AS][PREVIEW][%s] " .. fmt):format(now_ts(), ...)
  reaper.ShowConsoleMsg(msg .. "\n")
end

-- Resolve different "target" specs into (track, fxindex, kind)
-- target supports:
--   "focused" | "name:<TrackName>" | { by="name", value="<TrackName>" }
-- Return values:
--   FXtrack :: MediaTrack*
--   FXindex :: integer or nil  (nil for Chain mode; 0-based index for Focused mode)
--   kind    :: "trackfx" | "takefx" | "none"
function ASP._resolve_target(target)
  -- 1) Directly given a MediaTrack* object
  if type(target) == "userdata" then
    return target, nil, "trackfx"
  end

  -- 2) focused
  local function read_focused()
    local rv, trNum, itNum, fxNum = reaper.GetFocusedFX()
    -- rv: 0 none, 1 trackfx, 2 takefx
    if rv == 1 then
      local tr = reaper.GetTrack(0, trNum-1)
      return tr, fxNum, "trackfx"
    elseif rv == 2 then
      -- Take FX also maps back to the item's track; Chain preview uses the entire track FX chain
      local it = reaper.GetMediaItem(0, itNum)
      if it then
        local tr = reaper.GetMediaItem_Track(it)
        return tr, fxNum, "takefx"
      end
    end
    return nil, nil, "none"
  end

  if target == "focused" or (type(target)=="table" and target.by=="focused") then
    return read_focused()
  end

  -- 3) "name:XXX"
  if type(target) == "string" then
    local name = target:match("^name:(.+)$")
    if name then
      local tc = reaper.CountTracks(0)
      for i=0, tc-1 do
        local tr = reaper.GetTrack(0, i)
        local _, tn = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if (tn or "") == name then return tr, nil, "trackfx" end
      end
      return nil, nil, "none"
    end
  end

  -- 4) { by="name"/"guid"/"index", value=... }
  if type(target) == "table" then
    if target.by == "name" then
      local want = tostring(target.value or "")
      local tc = reaper.CountTracks(0)
      for i=0, tc-1 do
        local tr = reaper.GetTrack(0, i)
        local _, tn = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if (tn or "") == want then return tr, nil, "trackfx" end
      end
      return nil,nil,"none"
    elseif target.by == "guid" then
      -- Searching GUIDs track-by-track and item-by-item is too heavy; not recommended.
      -- You may inject your own GUID→Track mapping externally. Returns "none" here.
      return nil,nil,"none"
    elseif target.by == "index" then
      local idx = tonumber(target.value or 1)
      local tr = reaper.GetTrack(0, (idx or 1)-1)
      return tr, nil, tr and "trackfx" or "none"
    end
  end

  return nil, nil, "none"
end

-- Minimal JSON encode for small tables (no nested tables needed here)
local function tbl2json(t)
  local parts = {"{"}
  local first = true
  for k,v in pairs(t) do
    if not first then table.insert(parts, ",") end
    first = false
    local vv = (type(v)=="string") and ('"'..v..'"') or tostring(v)
    table.insert(parts, ('"%s":%s'):format(k, vv))
  end
  table.insert(parts, "}")
  return table.concat(parts)
end

local function write_state(t)
  reaper.SetExtState(ASP.ES_NS, ASP.ES_STATE, tbl2json(t), false)
end

-- args = {
--   mode        = "solo"|"normal",         -- default "solo"
--   target      = "focused"|"name:<TrackName>"|{by="name", value="<TrackName>"},
--   target_track_name = "MyChain",         -- convenience: same as target={by="name", value="MyChain"}
--   chain_mode  = true|false,              -- true = Track FX Chain preview (no isolate)
--                                          -- false = Focused preview; Core will FORCE target to "focused"
--                                          --          (ignores any name-based target or TARGET_TRACK_NAME)
--   isolate_focused = true|false,          -- only meaningful when chain_mode=false; default true
--   solo_scope  = "track"|"item",          -- override USER_SOLO_SCOPE (optional)
--   restore_mode= "guid"|"timesel",        -- override USER_RESTORE_MODE (optional)
--   debug       = true|false,              -- override USER_DEBUG (optional)
-- }
function ASP.preview(args)
  args = args or {}

  -- Read-only normalization: produce a single target_spec without mutating args
  -- inside ASP.preview(args)
  local function normalize_target(a)
    -- A) explicit mode: focused / pass-through
    if a.target == "focused" then
      return "focused"                       -- ignore target_track_name
    end
    if a.target ~= nil and a.target ~= "TARGET_TRACK_NAME" then
      return a.target                        -- pass-through ("name:<X>" or table spec)
    end

    -- B) sentinel: target = "TARGET_TRACK_NAME"
    if a.target == "TARGET_TRACK_NAME" then
      local name = a.target_track_name
      if type(name) ~= "string" or name == "" then
        name = _G.TARGET_TRACK_NAME
      end
      if type(name) == "string" and name ~= "" then
        return { by = "name", value = name } -- use provided name
      end
      return { by = "name", value = "AudioSweet" } -- last-resort fallback
    end

    -- C) no explicit target: allow direct name when target is nil
    if a.target == nil and type(a.target_track_name) == "string" and a.target_track_name ~= "" then
      return { by = "name", value = a.target_track_name }
    end

    -- D) default when nothing specified
    return "focused"
  end

  local mode       = (args.mode == "normal") and "normal" or "solo"
  local chain_mode = args.chain_mode == true

  -- Override Core user options (optional)
  if args.debug ~= nil then USER_DEBUG = args.debug and true or false end
  USER_SOLO_SCOPE = (args.solo_scope == "item") and "item" or "track"
  USER_RESTORE_MODE = (args.restore_mode == "timesel") and "timesel" or "guid"

  -- Resolve target once
  -- Focused preview (chain_mode=false) always uses "focused", ignoring any name-based targets.
  local target_spec = chain_mode and normalize_target(args) or "focused"
  local FXtrack, FXindex, kind = ASP._resolve_target(target_spec)

  -- Fallback: if resolution failed, try name:AudioSweet
  if not FXtrack then
    FXtrack, FXindex, kind = ASP._resolve_target("name:AudioSweet")
  end

  -- Chain mode does not need an FX index
  local focus_index = chain_mode and nil or FXindex

  -- Mirror the chosen mode into ExtState (for cross-wrapper toggle)
  reaper.SetExtState(ASP.ES_NS, ASP.ES_MODE, mode, false)

  return ASP.run{
    mode          = mode,
    focus_track   = FXtrack,
    focus_fxindex = focus_index,
    no_isolate    = chain_mode,
  }
end

-- Internal runtime state (persist across re-loads)
ASP._state = ASP._state or {
  running           = false,
  mode              = nil,
  play_was_on       = nil,
  repeat_was_on     = nil,
  selection_cache   = nil,
  fx_track          = nil,
  fx_index          = nil,
  moved_items       = {},
  placeholder       = nil,
  fx_enable_shot    = nil,
  track_nchan       = nil,  -- Snapshot of track channel count
  stop_watcher      = false,
  allow_overlap_guids = nil,
}

function ASP.is_running()
  return ASP._state.running
end



function ASP.toggle_mode(start_hint)
  -- if not running -> start with start_hint
  if not ASP._state.running then
    return ASP.run{ mode = start_hint, focus_track = ASP._state.fx_track, focus_fxindex = ASP._state.fx_index }
  end
  local target = (ASP._state.mode == "solo") and "normal" or "solo"
  ASP._switch_mode(target)
end

function ASP._switch_mode(newmode)
  ASP.log("switch mode: %s -> %s", tostring(ASP._state.mode), newmode)
  if newmode == ASP._state.mode then return end

  -- ==== NO-UNDO GUARD (entire mode switch) ====
  undo_begin()  -- Ensure the following Main_OnCommand / I_SOLO operations create no Undo points

  local scope = read_solo_scope()
  local FXtr  = ASP._state.fx_track

  -- Before switching, clear both solo states to ensure a clean state
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  if ASP._state.moved_items and #ASP._state.moved_items > 0 then
    ASP._select_items(ASP._state.moved_items, true)

    if newmode == "solo" then
      if scope == "track" then
        if FXtr then reaper.SetMediaTrackInfo_Value(FXtr, "I_SOLO", 1) end
        ASP.log("switch→solo TRACK: FX track solo ON")
      else
        reaper.Main_OnCommand(41558, 0) -- Item: Solo exclusive
        ASP.log("switch→solo ITEM: item-solo-exclusive ON")
      end
    else
      -- normal: keep non-solo (already cleared above)
      ASP.log("switch→normal: solo cleared (items & tracks)")
    end
  end

  ASP._state.mode = newmode
  write_state({running=true, mode=newmode})
  ASP.log("switch done: now=%s (scope=%s)", newmode, scope)

  undo_end_no_undo("AS Preview: switch mode (no undo)")  
  -- ==== END NO-UNDO GUARD ====
end


----------------------------------------------------------------
-- (A) Debug / log (built-in for now; may be moved to AS Core later)
----------------------------------------------------------------
local function debug_enabled()
  return USER_DEBUG
end
local function log_step(tag, fmt, ...)
  if not debug_enabled() then return end
  local msg = fmt and string.format(fmt, ...) or ""
  reaper.ShowConsoleMsg(string.format("[AS][PREVIEW] %s %s\n", tostring(tag or ""), msg))
end

-- === Undo helpers: wrap mutating ops but do NOT create undo points ===
undo_begin = function()
  reaper.Undo_BeginBlock2(0)
end

undo_end_no_undo = function(desc)
  -- desc is for debug readability only; -1 means **no** undo point will be created
  reaper.Undo_EndBlock2(0, desc or "AS Preview (no undo)", -1)
end

----------------------------------------------------------------
-- (B) Basic utilities (epsilon / selection / units / items / fx)
--   Currently includes minimal subset; will later be extracted to AS Core
----------------------------------------------------------------
project_epsilon = function()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end
local function approx_eq(a,b,eps) eps = eps or project_epsilon(); return math.abs(a-b) <= eps end
ranges_touch_or_overlap = function(a0,a1,b0,b1,eps)
  eps = eps or project_epsilon()
  return not (a1 < b0 - eps or b1 < a0 - eps)
end
-- NEW: strict overlap (edges touching are NOT overlap)
ranges_strict_overlap = function(a0,a1,b0,b1,eps)
  eps = eps or project_epsilon()
  -- true only if interiors intersect strictly
  return (a0 < b1 - eps) and (a1 > b0 + eps)
end

local function build_units_from_selection()
  local n = reaper.CountSelectedMediaItems(0)
  local by_track, units, eps = {}, {}, project_epsilon()
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0,i)
    if it then
      local tr  = reaper.GetMediaItem_Track(it)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local fin = pos + len
      by_track[tr] = by_track[tr] or {}
      table.insert(by_track[tr], {item=it,pos=pos,fin=fin})
    end
  end
  for tr, arr in pairs(by_track) do
    table.sort(arr, function(a,b) return a.pos < b.pos end)
    local cur
    for _,e in ipairs(arr) do
      if not cur then cur = {track=tr, items={e.item}, UL=e.pos, UR=e.fin}
      else
        if ranges_touch_or_overlap(cur.UL, cur.UR, e.pos, e.fin, eps) then
          table.insert(cur.items, e.item); if e.pos<cur.UL then cur.UL=e.pos end; if e.fin>cur.UR then cur.UR=e.fin end
        else
          table.insert(units, cur); cur = {track=tr, items={e.item}, UL=e.pos, UR=e.fin}
        end
      end
    end
    if cur then table.insert(units, cur) end
  end
  return units
end

local function getLoopSelection()
  local isSet, isLoop = false, false
  local allowautoseek = false
  local L,R = reaper.GetSet_LoopTimeRange(isSet, isLoop, 0,0, allowautoseek)
  local has = not (L==0 and R==0)
  return has, L, R
end



local function items_all_on_track(items, tr)
  for _,it in ipairs(items) do if reaper.GetMediaItem_Track(it) ~= tr then return false end end
  return true
end

local function select_only_items(items)
  reaper.Main_OnCommand(40289, 0)
  for _,it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
end

local function item_guid(it)
  return select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false))
end



local function snapshot_selection()
  local map = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then map[item_guid(it)] = true end
  end
  return map
end

local function restore_selection(selmap)
  if not selmap then return end
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  local tr_cnt = reaper.CountTracks(0)
  for ti=0, tr_cnt-1 do
    local tr = reaper.GetTrack(0, ti)
    local ic = reaper.CountTrackMediaItems(tr)
    for ii=0, ic-1 do
      local it = reaper.GetTrackMediaItem(tr, ii)
      if it and selmap[item_guid(it)] then
        reaper.SetMediaItemSelected(it, true)
      end
    end
  end
end

-- helper: get item GUID
local function guid_of(it)
  return select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false))
end

-- snapshot neighbors on source track that touch/overlap the preview span
local function snapshot_allow_overlap_neighbors(src_tr, UL, UR, exclude_set)
  local map = {}
  if not src_tr then return map end
  local ic = reaper.CountTrackMediaItems(src_tr)
  local eps = project_epsilon()
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(src_tr, i)
    if not (exclude_set and exclude_set[it]) then
      local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if ranges_touch_or_overlap(L, R, UL, UR, eps) then
        local g = guid_of(it)
        if g and g ~= "" then map[g] = true end
      end
    end
  end
  return map
end

----------------------------------------------------------------
-- (C) Transport / mute snapshot and restore
----------------------------------------------------------------
local function snapshot_transport()
  return {
    repeat_on = (reaper.GetToggleCommandState(1068) == 1),
    playing   = (reaper.GetPlayState() & 1) == 1
  }
end

local function set_loop_and_repeat(L,R, want_repeat)
  reaper.GetSet_LoopTimeRange(true, true, L, R, false)
  if want_repeat and reaper.GetToggleCommandState(1068) ~= 1 then
    reaper.Main_OnCommand(1068, 0) -- Toggle repeat
  end
end

local function restore_transport(snap)
  if not snap then return end
  -- Turn off Repeat (if it was originally off)
  if not snap.repeat_on and reaper.GetToggleCommandState(1068) == 1 then
    reaper.Main_OnCommand(1068, 0)
  end
  -- Stop playback (if it was not playing initially)
  if not snap.playing and (reaper.GetPlayState() & 1) == 1 then
    reaper.Main_OnCommand(1016, 0) -- Stop
  end
end

local function snapshot_and_mute(items)
  local shot = {}
  for _,it in ipairs(items) do
    local m = reaper.GetMediaItemInfo_Value(it, "B_MUTE")
    table.insert(shot, {it=it, m=m})
    reaper.SetMediaItemInfo_Value(it, "B_MUTE", 1)
  end
  return shot
end

local function restore_mutes(shot)
  if not shot then return end
  for _,e in ipairs(shot) do
    if e.it then reaper.SetMediaItemInfo_Value(e.it, "B_MUTE", e.m or 0) end
  end
end

----------------------------------------------------------------
-- (D) Entry: allow only a single track (multiple items allowed); Time Selection takes priority over item selection
----------------------------------------------------------------
-- Begin preview (or switch if already running)
function ASP.run(opts)
  opts = opts or {}
  local FXtrack, FXindex = opts.focus_track, opts.focus_fxindex
  local mode = read_mode(opts.default_mode or "solo")  -- ExtState takes precedence
  local no_isolate = opts.no_isolate and true or false

  if not (mode == "solo" or mode == "normal") then
    reaper.MB("ASP.run: invalid mode", "AudioSweet Preview", 0); return
  end
  if not FXtrack then
    reaper.MB("ASP.run: focus track missing", "AudioSweet Preview", 0); return
  end
  if (not no_isolate) and (FXindex == nil) then
    reaper.MB("ASP.run: focus FX index missing (focused-FX preview requires a valid FX index)", "AudioSweet Preview", 0); return
  end

  ASP.log("run called, mode=%s", mode)
  ASP.log("Core options: SOLO_SCOPE=%s DEBUG=%s", read_solo_scope(), tostring(USER_DEBUG))
  -- Guard A: require at least one selected item (and if TS exists, require intersection)
  do
    local sel_cnt = reaper.CountSelectedMediaItems(0)
    if sel_cnt == 0 then
      ASP.log("no-targets: abort (no selected items)")
      reaper.MB("No preview targets found. Please select at least one item (or items within the time selection). Preview was not started.","AudioSweet Preview",0)
      return
    end
    local hasTS, tsL, tsR = getLoopSelection()
    if hasTS and tsR > tsL then
      local eps = project_epsilon()
      local overlap_found = false
      for i=0, sel_cnt-1 do
        local it  = reaper.GetSelectedMediaItem(0, i)
        if it then
          local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local fin = pos + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          if ranges_touch_or_overlap(pos, fin, tsL, tsR, eps) then overlap_found = true; break end
        end
      end
      if not overlap_found then
        ASP.log("no-targets: abort (TS set but no selected items intersect %.3f..%.3f)", tsL, tsR)
        reaper.MB("No preview targets found within the current time selection. Please select at least one item inside the time selection.","AudioSweet Preview",0)
        return
      end
    end
  end

  -- (1) Detect preview via a placeholder item (search only on the source track)
  local src_tr = ASP._state.src_track
  if not src_tr then
    local first_sel = reaper.GetSelectedMediaItem(0, 0)
    if first_sel then src_tr = reaper.GetMediaItem_Track(first_sel) end
  end

  local ph, UL, UR = nil, nil, nil
  if src_tr then
    ph, UL, UR = find_placeholder_on_track(src_tr)
  end

  if ph then
    ASP._state.running       = true
    ASP._state.fx_track      = FXtrack
    ASP._state.fx_index      = FXindex   -- allow nil (Chain mode)
    ASP._state.placeholder   = ph
    ASP._state.src_track     = src_tr
    ASP._state.moved_items   = collect_preview_items_on_fx_track(FXtrack, ph, UL, UR)
    ASP._state.mode          = (mode == "solo") and "normal" or "solo"
    ASP.log("detected existing placeholder on source track; bootstrap (items=%d)", #ASP._state.moved_items)

    _set_run_flag(true)  -- NEW: handshake ON

    undo_begin()
    ASP._switch_mode(mode)
    undo_end_no_undo("AS Preview: switch mode (no undo)")
    return
  end

  -- (2) Legacy path: if same instance with state.running=true (placeholder missing), allow rebuild (rare)
  if ASP._state.running then
    ASP.log("run: state.running=true but placeholder missing; rebuilding preview")
  end

  -- start preview (no-undo wrapper)
  undo_begin()
  _set_run_flag(true)  -- NEW: handshake ON
  ASP._state.running       = true
  ASP._state.mode          = mode
  ASP._state.fx_track      = FXtrack
  ASP._state.fx_index      = FXindex     -- 允許 nil（Chain）
  ASP._state.selection_cache = ASP._snapshot_item_selection()
  ASP._state.play_was_on   = (reaper.GetPlayState() & 1) == 1
  ASP._state.repeat_was_on = reaper.GetToggleCommandState(1068) == 1

  -- Snapshot track channel count before preview
  ASP._state.track_nchan = reaper.GetMediaTrackInfo_Value(FXtrack, "I_NCHAN")
  ASP.log("snapshot: track channel count = %d", ASP._state.track_nchan or -1)

  ASP._arm_loop_region_or_unit()
  ASP._ensure_repeat_on()

  -- Isolate focused FX (Chain mode: no isolate)
  if (not no_isolate) and (FXindex ~= nil) then
    ASP._state.fx_enable_shot = isolate_only_focused_fx(FXtrack, FXindex)
    ASP.log("focused FX isolated (index=%d)", FXindex or -1)
  else
    ASP._state.fx_enable_shot = nil
    ASP.log("chain-mode: no isolate; keep track FX enables as-is")
  end

  ASP._prepare_preview_items_on_fx_track(mode)
  ASP._apply_mode_flags(mode)

  write_state({running=true, mode=mode})
  ASP.log("preview started: mode=%s", mode)
  undo_end_no_undo("AS Preview: start (no undo)")

  if not ASP._state.stop_watcher then
    ASP._state.stop_watcher = true
    reaper.defer(ASP._watch_stop_and_cleanup)
  end
end

function ASP.switch_mode(opts)
  opts = opts or {}
  local want = opts.mode
  local st   = ASP._state
  if not st.running or not want or want == st.mode then return end

  -- target is "solo"
  if want == "solo" then
    -- restore original mutes first (avoid additive artifacts)
    restore_mutes(st.mute_shot); st.mute_shot = nil
    -- select preview items on the FX track → enable solo
    if st.moved_items and #st.moved_items > 0 then
      select_only_items(st.moved_items)
      reaper.Main_OnCommand(41561, 0) -- Toggle solo exclusive (entering from non-solo → becomes ON)
    end

  -- target is "normal"
  elseif want == "normal" then
    -- turn off item solo (toggle again)
    if st.moved_items and #st.moved_items > 0 then
      select_only_items(st.moved_items)
      reaper.Main_OnCommand(41561, 0) -- Toggle solo exclusive (leaving solo → becomes OFF)
    end
    -- then mute originals to avoid doubling
    if st.unit and st.unit.items then
      st.mute_shot = snapshot_and_mute(st.unit.items)
    end
  end

  st.mode = want
end

function ASP.cleanup_if_any()
  if not ASP._state.running then return end
  undo_begin()  -- ← 補上：與結尾的 undo_end_no_undo 成對
  ASP.log("cleanup begin")

  -- Safety: clear item-solo and track-solo
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  -- Restore FX enable state (only if focused mode isolated earlier)
  if ASP._state.fx_track and ASP._state.fx_enable_shot ~= nil then
    restore_fx_enabled(ASP._state.fx_track, ASP._state.fx_enable_shot)
    ASP._state.fx_enable_shot = nil
    ASP.log("FX enables restored")
  end

  -- Restore track channel count
  if ASP._state.fx_track and ASP._state.track_nchan then
    reaper.SetMediaTrackInfo_Value(ASP._state.fx_track, "I_NCHAN", ASP._state.track_nchan)
    ASP.log("restore: track channel count = %d", ASP._state.track_nchan)
    ASP._state.track_nchan = nil
  end

  -- 搬回 items 並刪除 placeholder
  ASP._move_back_and_remove_placeholder()

  -- 還原 Repeat / 選取
  ASP._restore_repeat()
  ASP._restore_item_selection()

  ASP._state.running       = false
  ASP._state.mode          = nil
  ASP._state.fx_track      = nil
  ASP._state.fx_index      = nil
  ASP._state.moved_items   = {}
  ASP._state.placeholder   = nil
  ASP._state.src_track     = nil
  ASP._state.stop_watcher  = false

  write_state({running=false, mode=""})
  _set_run_flag(false)  -- NEW: handshake OFF
  ASP.log("cleanup done")
  undo_end_no_undo("AS Preview: cleanup (no undo)")
end

function ASP._watch_stop_and_cleanup()
  if not ASP._state.running then return end
  local playing = (reaper.GetPlayState() & 1) == 1
  local ph_ok   = ASP._state.placeholder and reaper.ValidatePtr2(0, ASP._state.placeholder, "MediaItem*")
  if (not playing) and ph_ok then
    ASP.log("detected stop + placeholder alive -> cleanup")
    ASP.cleanup_if_any()
    return
  end
  reaper.defer(ASP._watch_stop_and_cleanup)
end

function ASP._snapshot_item_selection()
  local t = {}
  local cnt = reaper.CountSelectedMediaItems(0)
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, guid = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    t[guid] = true
  end
  ASP.log("snapshot selection: %d items", cnt)
  return t
end

function ASP._restore_item_selection()
  if not ASP._state.selection_cache then return end
  -- clear current
  reaper.Main_OnCommand(40289,0) -- unselect all
  -- reselect previous
  local tot = reaper.CountMediaItems(0)
  for i=0, tot-1 do
    local it = reaper.GetMediaItem(0, i)
    local guid = select(2, reaper.GetSetMediaItemInfo_String(it, "GUID", "", false))
    if ASP._state.selection_cache[guid] then
      reaper.SetMediaItemSelected(it, true)
    end
  end
  reaper.UpdateArrange()
  ASP.log("restore selection done")
end

function ASP._ensure_repeat_on()
  if reaper.GetToggleCommandState(1068) ~= 1 then
    reaper.Main_OnCommand(1068, 0) -- Toggle repeat
    ASP.log("repeat ON")
  else
    ASP.log("repeat already ON")
  end
end

function ASP._restore_repeat()
  local want_on = ASP._state.repeat_was_on
  local now_on = (reaper.GetToggleCommandState(1068) == 1)
  if want_on ~= now_on then
    reaper.Main_OnCommand(1068, 0) -- Toggle repeat
    ASP.log("repeat restored to %s", want_on and "ON" or "OFF")
  end
end

function ASP._arm_loop_region_or_unit()
  local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if ts_end > ts_start then
    ASP.log("loop by Time Selection: %.3f..%.3f", ts_start, ts_end)
    return -- Loop is controlled by REAPER's time selection
  end

  -- No Time Selection: use the envelope span of currently selected items
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return end
  local UL, UR
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local L, R = pos, pos+len
    UL = UL and math.min(UL, L) or L
    UR = UR and math.max(UR, R) or R
  end
  reaper.GetSet_LoopTimeRange(true, false, UL, UR, false)
  ASP.log("loop armed by items span: %.3f..%.3f", UL, UR)
end

local function clone_item_to_track(src_it, dst_tr)
  local pos   = reaper.GetMediaItemInfo_Value(src_it, "D_POSITION")
  local len   = reaper.GetMediaItemInfo_Value(src_it, "D_LENGTH")
  local newit = reaper.AddMediaItemToTrack(dst_tr)
  reaper.SetMediaItemInfo_Value(newit, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(newit, "D_LENGTH",   len)

  local take  = reaper.GetActiveTake(src_it)
  if take then
    local src   = reaper.GetMediaItemTake_Source(take)
    local newtk = reaper.AddTakeToMediaItem(newit)
    reaper.SetMediaItemTake_Source(newtk, src)
    -- 常用屬性
    reaper.SetMediaItemTakeInfo_Value(newtk, "D_STARTOFFS", reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"))
    reaper.SetMediaItemTakeInfo_Value(newtk, "D_PLAYRATE",  reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"))
    reaper.SetMediaItemTakeInfo_Value(newtk, "I_CHANMODE",  reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"))
  end
  return newit
end

function ASP._prepare_preview_items_on_fx_track(mode)
  local cnt = reaper.CountSelectedMediaItems(0)
  ASP.log("_prepare_preview: counted %d selected items in REAPER", cnt)

  -- Debug: print each selected item
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local tr = reaper.GetMediaItem_Track(it)
      local tr_num = reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
      ASP.log("  [%d] item pos=%.3f track=#%d", i, pos, tr_num or -1)
    end
  end

  if cnt == 0 then return end
  -- remember how many items were moved out in this preview session (for timesel count sanity check)
  ASP._state.moved_count = cnt or 0

  -- Compute preview span and create a placeholder (white empty item)
  local UL, UR = compute_preview_span()
  local tridx  = reaper.GetMediaTrackInfo_Value(ASP._state.fx_track, "IP_TRACKNUMBER")
  tridx = (tridx and tridx > 0) and math.floor(tridx) or 0

  local label
  if ASP._state.fx_index ~= nil then
    local _, fxname = reaper.TrackFX_GetFXName(ASP._state.fx_track, ASP._state.fx_index, "")
    label = fxname or "Focused FX"
  else
    local _, tn = reaper.GetSetMediaTrackInfo_String(ASP._state.fx_track, "P_NAME", "", false)
    label = tn and (#tn>0 and tn or "FX Track") or "FX Track"
  end
  local note = string.format("PREVIEWING @ Track %d - %s", tridx, label)

  -- Place on the source track: use the track of the first selected item
  local first_sel = reaper.GetSelectedMediaItem(0, 0)
  local src_tr = first_sel and reaper.GetMediaItem_Track(first_sel) or ASP._state.fx_track
  ASP._state.src_track = src_tr  -- Remember the source track for placeholder lookup on re-entry
  ASP._state.placeholder = make_placeholder(src_tr, UL or 0, UR or (UL and UL+1 or 1), note)

  ASP.log("placeholder created: [%0.3f..%0.3f] %s", UL or -1, UR or -1, note)

  -- 搬移所選 item 到 FX 軌
  -- IMPORTANT: Collect all items FIRST, then move them.
  -- If we move items during iteration, the selection indices shift when FX track is below the source track.
  ASP._state.moved_items = {}
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      table.insert(ASP._state.moved_items, it)
    end
  end

  -- Now move all collected items
  for _, it in ipairs(ASP._state.moved_items) do
    reaper.MoveMediaItemToTrack(it, ASP._state.fx_track)
  end
  reaper.UpdateArrange()
  ASP.log("moved %d items -> FX track", #ASP._state.moved_items)

  -- Debug: verify items are on FX track after move
  local fx_track_num = reaper.GetMediaTrackInfo_Value(ASP._state.fx_track, "IP_TRACKNUMBER")
  ASP.log("Verification: FX track #%d now has %d items total",
    fx_track_num or -1,
    reaper.CountTrackMediaItems(ASP._state.fx_track))
  for i, it in ipairs(ASP._state.moved_items) do
    local now_tr = reaper.GetMediaItem_Track(it)
    local now_tr_num = reaper.GetMediaTrackInfo_Value(now_tr, "IP_TRACKNUMBER")
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    ASP.log("  moved_items[%d]: now on track #%d, pos=%.3f", i, now_tr_num or -1, pos)
  end
end

function ASP._clear_preview_items_only()
  -- In the new flow we no longer delete preview items; we move them back.
  -- Keep this function name for compatibility.
  if ASP._state.moved_items and #ASP._state.moved_items > 0 then
    ASP.log("clear_preview_items_only(): nothing to delete under move-based preview")
  end
end

local function move_items_to_track(items, tr)
  for _,it in ipairs(items or {}) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      reaper.MoveMediaItemToTrack(it, tr)
    end
  end
end

function ASP._move_back_and_remove_placeholder()
  -- Decide which items to move back based on USER_RESTORE_MODE.
  local move_list = {}

  if not ASP._state.placeholder then
    ASP.log("no placeholder; skip move-back")
    ASP._state.moved_items = {}
    return
  end

  local ph_it = ASP._state.placeholder
  local ph_tr = reaper.GetMediaItem_Track(ph_it)
  local UL    = reaper.GetMediaItemInfo_Value(ph_it, "D_POSITION")
  local UR    = UL + reaper.GetMediaItemInfo_Value(ph_it, "D_LENGTH")

  if USER_RESTORE_MODE == "timesel" then
    -- Collect all items on FX track that overlap the placeholder span
    move_list = collect_preview_items_on_fx_track(ASP._state.fx_track, ph_it, UL, UR)
    ASP.log("restore-mode=timesel: collected %d item(s) on FX track by placeholder span", #move_list)
    -- sanity check: if returning more items than originally moved out for this preview, abort
    local moved_out = tonumber(ASP._state.moved_count or 0) or 0
    ASP.log("preflight: timesel count check; moved_out=%d  to_move_back=%d", moved_out, #move_list)
    if #move_list > moved_out then
      reaper.MB(
        "Move-back aborted: returning items exceed the original count for this time selection.\n\n" ..
        "Tip: adjust the time selection, or use GUID restore mode (restore_mode=\"guid\") to return only the previewed items, then try again.",
        "AudioSweet Preview — Count mismatch",
        0
      )
      ASP.log("move-back aborted due to count mismatch in timesel restore (to_move_back > moved_out)")
      return
    end
  else
    -- Default: only the ones we moved during this preview session
    for i=1, #(ASP._state.moved_items or {}) do
      local it = ASP._state.moved_items[i]
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        table.insert(move_list, it)
      end
    end
    ASP.log("restore-mode=guid: prepared %d item(s) to move back", #move_list)
  end

  -- Perform the move-back (no overlap policing)
  for _, it in ipairs(move_list) do
    reaper.MoveMediaItemToTrack(it, ph_tr)
  end
  remove_placeholder(ph_it)
  ASP._state.placeholder = nil
  ASP._state.moved_items = {}
  ASP.log("moved %d item(s) back & removed placeholder", #move_list)
end

function ASP._select_items(list, exclusive)
  if exclusive then reaper.Main_OnCommand(40289, 0) end -- Unselect all
  for _,it in ipairs(list or {}) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      reaper.SetMediaItemSelected(it, true)
    end
  end
  reaper.UpdateArrange()
end

function ASP._apply_mode_flags(mode)
  -- Wrap the entire section to avoid fragmented Undo operations
  undo_begin()

  local scope = read_solo_scope()
  local FXtr  = ASP._state.fx_track

  -- Always clear first: reset item-solo and track-solo
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  if mode == "solo" then
    if scope == "track" then
      if FXtr then
        reaper.SetMediaTrackInfo_Value(FXtr, "I_SOLO", 1)
        ASP.log("solo TRACK scope: FX track solo ON")
      end
      ASP._select_items(ASP._state.moved_items, true)
    else
      ASP._select_items(ASP._state.moved_items, true)
      reaper.Main_OnCommand(41558, 0) -- Item: Solo exclusive
      ASP.log("solo ITEM scope: item-solo-exclusive ON")
    end
  else
    ASP._select_items(ASP._state.moved_items, true)
    ASP.log("normal mode: solo cleared (items & tracks)")
  end

  reaper.Main_OnCommand(1007, 0) -- Transport: Play

  undo_end_no_undo("AS Preview: apply mode flags (no undo)")
end


return ASP
