--[[
@description AudioSweet (hsuanice) — Focused Track FX render via RGWH Core, append FX name, rebuild peaks (selected items)
@version 2510041957 TS-Window channel-aware apply; mono/stereo logic fixed
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
  v2510041957 — TS-Window channel-aware apply; mono/stereo logic fixed
    •	TS-Window (GLOBAL/UNIT): Per-item channel detection now works for both single-track and mixed material on the same track.
    •	Mono (1ch) sources use 40361 “Apply track FX to items as new take” to ensure a new take is created; no track channel change.
    •	≥2-channel sources set the FX track I_NCHAN to the nearest even ≥ source channels, then use 41993 (multichannel output).
    •	Restores the FX track channel count after apply and appends the focused FX name to the new take.
    •	Stability: guards to avoid nil/number comparison when resolving channel or track fields; clearer step logs after 42432/print.

  Known issues
    •	TS-Window cross-track printing: Printing the focused FX across multiple tracks is not yet supported. Current build can glue across tracks, but the focused-FX print step only runs when the window resolves to a single unit on one track.
    •	Non–TS-Window path still processes only the first unit per run (documented limitation).
    
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

reaper.SetExtState("hsuanice_AS","DEBUG","1", false)

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
-- =======================
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
  selitem = 0
  MediaItem = reaper.GetSelectedMediaItem(0, selitem)
  debug (MediaItem)
  return MediaItem
end

function countSelected() --Makes sure there is only 1 MediaItem selected
  if reaper.CountSelectedMediaItems(0) == 1 then
    debug("Media Item is Selected! \n")
    return true
    else 
      debug("Must Have only ONE Media Item Selected")
      return false
  end
end

function checkSelectedFX() --Determines if a TrackFX is selected, and which FX is selected
  retval = 0
  tracknumberOut = 0
  itemnumberOut = 0
  fxnumberOut = 0
  window = false
  
  retval, tracknumberOut, itemnumberOut, fxnumberOut = reaper.GetFocusedFX()
  debug ("\n"..retval..tracknumberOut..itemnumberOut..fxnumberOut)
  
  track = tracknumberOut - 1
  
  if track == -1 then
    track = 0
  else
  end
  
  mtrack = reaper.GetTrack(0, track)
  
  window = reaper.TrackFX_GetOpen(mtrack, fxnumberOut)
  
  return retval, tracknumberOut, itemnumberOut, fxnumberOut, window
end

function getFXname(trackNumber, fxNumber) --Get FX name
  track = trackNumber - 1
  FX = fxNumber
  FXname = ""
  
  mTrack = reaper.GetTrack (0, track)
    
  retvalfx, FXname = reaper.TrackFX_GetFXName(mTrack, FX, FXname)
    
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
      else reaper.TrackFX_SetEnabled(FXtrack, i, false)
      i = i + 1
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
  startOut = 0
  endOut = 0
  isSet = false
  isLoop = false
  allowautoseek = false
  loop = false
  
  startOut, endOut = reaper.GetSet_LoopTimeRange(isSet, isLoop, startOut, endOut, allowautoseek)
  if startOut == 0 and endOut == 0 then
    loop = false
  else
    loop = true
  end
  
  return loop, startOut, endOut  
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

local function append_fx_to_take_name(item, fxName)
  if not item then return end
  local takeIndex = reaper.GetMediaItemInfo_Value(item, "I_CURTAKE")
  local take      = reaper.GetMediaItemTake(item, takeIndex)
  if not take then return end
  local _, tn = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if fxName and fxName ~= "" then
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", tn .. " - " .. fxName, true)
  end
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

-- 1-sample epsilon comparators
local function project_epsilon()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end

local function approx_eq(a, b, eps)
  eps = eps or project_epsilon()
  return math.abs(a - b) <= eps
end

local function ranges_touch_or_overlap(a0, a1, b0, b1, eps)
  eps = eps or project_epsilon()
  return not (a1 < b0 - eps or b1 < a0 - eps)
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
  local FXName, FXmediaTrack = getFXname(tracknumber_Out, fxIndex)
  log_step("FOCUSED-FX", "index(norm)=%d  name='%s'  FXtrack=%s", fxIndex, tostring(FXName or ""), tostring(FXmediaTrack))

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

      -- Each glued result: move to FX track → isolate → 40361 → rename → move back
      local glued_cnt = reaper.CountSelectedMediaItems(0)
      for i=0, glued_cnt-1 do
        local it = reaper.GetSelectedMediaItem(0, i)
        if it then
          local origTR = reaper.GetMediaItem_Track(it)
          reaper.MoveMediaItemToTrack(it, FXmediaTrack)
          dbg_item_brief(it, "TSW[GLOBAL] moved→FX")
          isolate_focused_fx(FXmediaTrack, fxIndex)

          -- ★ NEW: resolve source channels & current track channels
          local ch         = get_item_channels(it)                                  -- 由當前 glued item 取聲道數
          local prev_nchan = reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN") or 2

          -- Auto channel policy (TS-Window GLOBAL):
          --   mono(1ch)  → keep track nchan as-is; use 40361 (as NEW TAKE)
          --   stereo+(≥2)→ set FX track I_NCHAN to nearest even ≥ src; use 41993 (multichannel)
          local cmd_apply = 41993
          local did_set_nchan = false

          if ch <= 1 then
            cmd_apply = 40361
          else
            local desired_nchan = (ch % 2 == 0) and ch or (ch + 1)
            if prev_nchan ~= desired_nchan then
              log_step("TS-WINDOW[GLOBAL]", "I_NCHAN %d → %d (pre-apply)", prev_nchan, desired_nchan)
              reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired_nchan)
              did_set_nchan = true
            end
          end

          reaper.Main_OnCommand(40289, 0)
          reaper.SetMediaItemSelected(it, true)
          reaper.Main_OnCommand(cmd_apply, 0)
          log_step("TS-WINDOW[GLOBAL]", "apply %d to glued #%d", cmd_apply, i+1)
          dbg_dump_selection("TSW[GLOBAL] post-apply")

          if did_set_nchan then
            log_step("TS-WINDOW[GLOBAL]", "I_NCHAN restore %d → %d", reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN"), prev_nchan)
            reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
          end

          append_fx_to_take_name(it, FXName)
          reaper.MoveMediaItemToTrack(it, origTR)
          table.insert(outputs, it)
        end
      end

      log_step("TS-WINDOW[GLOBAL]", "done, outputs=%d", #outputs)
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

      local origTR = reaper.GetMediaItem_Track(glued)
      reaper.MoveMediaItemToTrack(glued, FXmediaTrack)
      dbg_item_brief(glued, "TSW[UNIT] moved→FX")
      isolate_focused_fx(FXmediaTrack, fxIndex)

      -- ★ NEW: resolve source channels & current track channels
      local ch         = get_item_channels(glued)                                -- 由當前 glued item 取聲道數
      local prev_nchan = reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN") or 2

      -- Auto channel policy (TS-Window UNIT):
      --   mono(1ch)  → keep track nchan as-is; use 40361 (as NEW TAKE)
      --   stereo+(≥2)→ set FX track I_NCHAN to nearest even ≥ src; use 41993 (multichannel)
      local cmd_apply = 41993
      local did_set_nchan = false

      if ch <= 1 then
        cmd_apply = 40361
      else
        local desired_nchan = (ch % 2 == 0) and ch or (ch + 1)
        if prev_nchan ~= desired_nchan then
          log_step("TS-WINDOW[UNIT]", "I_NCHAN %d → %d (pre-apply)", prev_nchan, desired_nchan)
          reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired_nchan)
          did_set_nchan = true
        end
      end

      reaper.Main_OnCommand(40289, 0)
      reaper.SetMediaItemSelected(glued, true)
      reaper.Main_OnCommand(cmd_apply, 0)
      log_step("TS-WINDOW[UNIT]", "applied %d", cmd_apply)
      dbg_dump_selection("TSW[UNIT] post-apply")

      if did_set_nchan then
        log_step("TS-WINDOW[UNIT]", "I_NCHAN restore %d → %d", reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN"), prev_nchan)
        reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
      end

      append_fx_to_take_name(glued, FXName)
      reaper.MoveMediaItemToTrack(glued, origTR)
      table.insert(outputs, glued)
    else
      --------------------------------------------------------------
      -- Core/GLUE（含 handles）：無 TS 或 TS==unit
      --------------------------------------------------------------

      -- Move all unit items to FX track (keep as-is), but select only the anchor for Core.
      move_items_to_track(u.items, FXmediaTrack)
      isolate_focused_fx(FXmediaTrack, fxIndex)
      -- Select the entire unit (non-TS path should preserve full unit selection)
      local anchor = u.items[1]  -- still used for channel auto and safety
      select_only_items_checked(u.items)

      -- [DBG] after move: how many unit items are actually on the FX track?
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

      -- Load Core (no goto; use failed flag to reach cleanup safely)
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
        local _, val = reaper.GetProjExtState(0, ns, key)
        return (val == "" and def) or val
      end
      local function proj_set(ns, key, val)
        reaper.SetProjExtState(0, ns, key, tostring(val or ""))
      end

      -- (A) 檢查：unit 的所有 items 是否已經搬到 FX 軌
      if not items_all_on_track(u.items, FXmediaTrack) then
        log_step("ERROR", "unit members not on FX track; fixing...")
        move_items_to_track(u.items, FXmediaTrack)
      end
      -- (B) 檢查：selection 是否等於整個 unit
      select_only_items_checked(u.items)
      if debug_enabled() then
        log_step("CORE", "pre-apply selected_items=%d (expect=%d)", reaper.CountSelectedMediaItems(0), #u.items)
      end

      -- (C) Snapshot
      snap.GLUE_TAKE_FX      = proj_get("RGWH","GLUE_TAKE_FX","")
      snap.GLUE_TRACK_FX     = proj_get("RGWH","GLUE_TRACK_FX","")
      snap.GLUE_APPLY_MODE   = proj_get("RGWH","GLUE_APPLY_MODE","")
      snap.GLUE_SINGLE_ITEMS = proj_get("RGWH","GLUE_SINGLE_ITEMS","")

      -- (D) Set desired flags
      proj_set("RGWH","GLUE_TAKE_FX","1")
      proj_set("RGWH","GLUE_TRACK_FX","1")
      proj_set("RGWH","GLUE_APPLY_MODE",apply_fx_mode)
      proj_set("RGWH","GLUE_SINGLE_ITEMS","1")  -- 正確語意：就算 unit 只有 1 顆 item 也走 glue

      if debug_enabled() then
        local _, gsi = reaper.GetProjExtState(0, "RGWH", "GLUE_SINGLE_ITEMS")
        log_step("CORE", "flag GLUE_SINGLE_ITEMS=%s (expected=1 for unit-glue)", (gsi == "" and "(empty)") or gsi)
      end

      -- (E) 準備參數，並完整印出（單一 item）
      if not (anchor and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, anchor, "MediaItem*"))) then
        log_step("ERROR", "anchor item invalid (u.items[1]=%s)", tostring(anchor))
        reaper.MB("Internal error: unit anchor item is invalid.", "AudioSweet", 0)
        failed = true
      else
        -- （保持你現有的 args 組裝…）
        local args = {
          mode                = "glue_item_focused_fx",  -- ★ 改這行：讓 Core 以「整個 selection」為主體
          item                = anchor,
          apply_fx_mode       = apply_fx_mode,
          focused_track       = FXmediaTrack,
          focused_fxindex     = fxIndex,
          policy_only_focused = true,
          selection_scope     = "selection",
          -- glue_single_items  不再由前端傳入，統一交由 RGWH 專案旗標（GLUE_SINGLE_ITEMS）決定
        }
        if debug_enabled() then
          local c = reaper.CountSelectedMediaItems(0)
          log_step("CORE", "apply args: mode=%s apply_fx_mode=%s focus_idx=%d sel_scope=%s unit_members=%d",
            tostring(args.mode), tostring(args.apply_fx_mode), fxIndex, tostring(args.selection_scope), #u.items)
          log_step("CORE", "pre-apply FINAL selected_items=%d", c)
          dbg_dump_selection("CORE pre-apply FINAL")
        end

        if debug_enabled() then
          log_step("CORE", "apply args: scope=%s members=%d", tostring(args.selection_scope), #u.items)
        end

        -- (F) 呼叫 Core（pcall 包起來，抓 runtime error）
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
      -- (G) Restore flags immediately
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
          -- Mark Core done once to keep non–TS-Window behavior single-item

        end

        -- [DBG] after Core: what is selected and which item will be picked?
        if debug_enabled() then
          dbg_dump_selection("CORE post-apply selection")
          if postItem then
            dbg_item_brief(postItem, "CORE picked postItem")
          end
        end        

      end
      -- Ensure any remaining original items (if any) go back
      move_items_to_track(u.items, u.track)
      -- Un-bypass everything on FX track
      local cnt = reaper.TrackFX_GetCount(FXmediaTrack)
      for i=0, cnt-1 do reaper.TrackFX_SetEnabled(FXmediaTrack, i, true) end
    end
    ::continue_unit::
  end

  log_step("END", "outputs=%d", #outputs)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("AudioSweet multi-item glue", 0)
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)

