--[[
@description AudioSweet (hsuanice) — Focused Track FX render via RGWH Core, append FX name, rebuild peaks (selected items)
@version 251001_1512  (Global TS-Window when TS intersects multiple units)
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
  v251001_1512  (Global TS-Window when TS intersects multiple units)
    - New global TS-Window branch: if Time Selection intersects ≥2 RGWH units, glue the whole TS once across those units,
      then print the focused Track FX per glued result (no handles), append FX name, and move items back.
    - Keeps existing behaviors for other cases:
      • TS == unit  → hand off to RGWH Core (GLUE with handles by Core).
      • TS ≠ unit   → per-unit TS-Window (single unit selection → 42432 → 40361).
    - Preserves auto mono/multi for TS-Window (set FX track I_NCHAN by source channels; restore afterward).
    - No peak rebuilds (40441) to avoid project-wide rebuild slowness; REAPER will build peaks lazily for new files.
  v251001_1418  (Unit-based processing for all modes)
    - Switched batch logic from per-item to per-unit (RGWH-like): items on the same track that touch or overlap
      are merged into a single unit (epsilon = 1 sample).
    - TS-Window mode now selects the entire unit first, then runs 42432 once to produce a single TS-length item,
      prints only the focused Track FX via 40361, appends the FX name, moves back, and rebuilds peaks.
    - When TS == unit: the whole unit is moved to the focused-FX track and processed once via RGWH Core (GLUE; handles by Core).
    - Kept focused-FX isolation and index normalization; auto mono/multi preserved (TS-Window via track channels, Core via ExtState).
    - Stability: per-unit early abort on failure with clear message; outer Undo block and UI refresh bracketing maintained.
  v251001_1351  (TS-Window mode with mono/multi auto-detect)
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
  v251001_1336  (TS-Window mode with mono/multi auto-detect)
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
  v251001_1312  (glue fx with time selection)
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
  v251001_0330
    - Auto channel mode: resolve "auto" by source channels before calling Core (1ch→mono, ≥2ch→multi); prevents unintended mono downmix in GLUE.
    - Core integration: write RGWH *project* ExtState for GLUE/RENDER (…_TAKE_FX, …_TRACK_FX, …_APPLY_MODE), with snapshot/restore around apply.
    - Focused FX targeting: normalize index (strip 0x1000000 floating-window flag); Track FX only.
    - Post-Core handoff: reacquire processed item, rename in place with " - <FX raw name>", then move back to original track.
    - Refresh: replace nudge with `Peaks: Rebuild peaks for selected items` (40441) on the processed item.
    - Error handling: modal alerts for Core load/apply failures; abort without fallback.
    - Cleanup: removed crop-to-new-take path; reduced global variable leakage; loop hygiene & minor logging polish.

  v250930_1754
    - Switched render engine to RGWH Core: call `RGWH.apply()` instead of native 40361.
    - Pro Tools–like default: GLUE mode with TAKE FX=1 and TRACK FX=1; handles fully managed by Core.
    - Focused FX targeting hardened: mask floating-window flag (0x1000000); Track FX only.
    - Post-Core handoff: re-acquire processed item from current selection; rename in place; move back to original track.
    - Naming: append raw focused FX label to take name (" - <FX raw name>"); avoids trailing dash when FX name is empty.
    - Refresh: replaced nudge trick with `Peaks: Rebuild peaks for selected items` (40441).
    - Error handling: message boxes for Core load/apply failures; no fallback path (explicit abort).
    - Cleanups: removed crop-to-new-take step; reduced global variable leakage; minor loop hygiene.
    - Config via ExtState (hsuanice_AS): `AS_MODE` (glue|render), `AS_TAKE_FX`, `AS_TRACK_FX`, `AS_APPLY_FX_MODE` (auto|mono|multi).

  v250929
    - Initial integration with RGWH Core
    - FX focus: robust (mask floating flag), Track FX only
    - Refresh: Peaks → Rebuild peaks for selected items (40441)
    - Naming: append " - <FX raw name>" after Core’s render naming
]]--

function debug(message) --logging
  --reaper.ShowConsoleMsg(tostring(message))
end

function getSelectedMedia() --Get value of Media Item that is selected
  selitem = 0
  MediaItem = reaper.GetSelectedMediaItem(0, selitem)
  debug (MediaItem)
  return MediaItem
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

-- Per-unit processing; returns (true, producedItem) or (false, "error message")
-- unit = { track=<MediaTrack*>, items={<MediaItem*>...}, UL=<number>, UR=<number> }
function process_one_unit(unit, FXmediaTrack, fxIndex, FXName)
  local render = false

  -- Time Selection probe
  local loopPoints, startLoop, endLoop = getLoopSelection()

  -- Helper: strict TS == unit bounds (1-sample epsilon)
  local function ts_equals_unit()
    if not loopPoints then return false end
    local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    local eps = (sr and sr > 0) and (1.0 / sr) or 1e-6
    return (math.abs(unit.UL - startLoop) <= eps) and (math.abs(unit.UR - endLoop) <= eps)
  end

  if loopPoints and not ts_equals_unit() then
    ----------------------------------------------------------------------
    -- TS-Window path: select the whole UNIT, 42432 once -> single TS item,
    -- move to FX track -> isolate focused FX -> 40361 print -> rename -> back -> 40441
    ----------------------------------------------------------------------
    -- Selection should already contain unit.items (set in main), but enforce:
    reaper.Main_OnCommand(40289, 0)
    for _, it in ipairs(unit.items) do reaper.SetMediaItemSelected(it, true) end

    -- DEBUG: TS 與實際選取
    do
      local loopPoints, startLoop, endLoop = getLoopSelection()
      reaper.ShowConsoleMsg(string.format("[AS][TS-Window] TS = [%.3f .. %.3f]\n", startLoop or -1, endLoop or -1))
      local cnt = reaper.CountSelectedMediaItems(0)
      reaper.ShowConsoleMsg(string.format("[AS][TS-Window] pre-42432 selected items: %d\n", cnt))
      for i = 0, cnt-1 do
        local it = reaper.GetSelectedMediaItem(0, i)
        local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
        local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
        local tk = reaper.GetActiveTake(it)
        local nm = ""
        if tk then local _, tnm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false); nm = tnm or "" end
        reaper.ShowConsoleMsg(string.format("  sel#%d  [%.3f..%.3f]  name='%s'\n", i+1, p, p+l, nm))
      end
    end

    -- Glue within TS (operates on selection = the whole unit), yields one TS-length item on that track
    reaper.Main_OnCommand(42432, 0) -- Item: Glue items within time selection

    local tsItem = reaper.GetSelectedMediaItem(0, 0)
    if not (tsItem and reaper.ValidatePtr2(0, tsItem, "MediaItem*")) then
      return false, "TS-Window glue failed: no item selected after 42432."
    end

    local tsOrigTrack = reaper.GetMediaItem_Track(tsItem)
    reaper.MoveMediaItemToTrack(tsItem, FXmediaTrack)
    bypassUnfocusedFX(FXmediaTrack, fxIndex, render)

    -- Ensure only the TS item is selected for apply
    reaper.Main_OnCommand(40289, 0)
    reaper.SetMediaItemSelected(tsItem, true)

    -- Auto channel: set FX track channels based on source take channels
    local desired_nchan = 2
    do
      local tk = reaper.GetActiveTake(tsItem)
      local ch = 2
      if tk then
        local src = reaper.GetMediaItemTake_Source(tk)
        if src then ch = reaper.GetMediaSourceNumChannels(src) or 2 end
      end
      if ch <= 1 then desired_nchan = 2 else desired_nchan = (ch % 2 == 0) and ch or (ch + 1) end
    end
    local prev_nchan = reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN")
    if prev_nchan ~= desired_nchan then
      reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired_nchan)
    end

    -- Print focused FX
    reaper.Main_OnCommand(40361, 0) -- Apply track FX to items as new take

    -- Restore FX track channels if needed
    if prev_nchan and prev_nchan ~= desired_nchan then
      reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
    end

    -- Rename with FX label
    do
      local tidx = reaper.GetMediaItemInfo_Value(tsItem, "I_CURTAKE")
      local tk   = reaper.GetMediaItemTake(tsItem, tidx)
      local _, takeName = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
      if FXName and FXName ~= "" then
        reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", takeName .. " - " .. FXName, true)
      end
    end

    -- Move back and restore FX enables
    reaper.MoveMediaItemToTrack(tsItem, tsOrigTrack)
    bypassUnfocusedFX(FXmediaTrack, fxIndex, true)


    --[[ Peaks
    reaper.Main_OnCommand(40289, 0)
    reaper.SetMediaItemSelected(tsItem, true)
    reaper.Main_OnCommand(40441, 0)--]]

    return true, tsItem
  end

  ----------------------------------------------------------------------
  -- Core (unit) path: move the whole UNIT to FX track, isolate focused FX,
  -- call Core once, then rename/move back/peaks. (Handles by Core)
  ----------------------------------------------------------------------
  -- Remember original track (unit is per-track by construction)
  local origTrack = unit.track

  -- Move all unit members to the FX track
  for _, it in ipairs(unit.items) do
    reaper.MoveMediaItemToTrack(it, FXmediaTrack)
  end
  bypassUnfocusedFX(FXmediaTrack, fxIndex, render)

  -- Keep the whole unit selected for Core
  reaper.Main_OnCommand(40289, 0)
  for _, it in ipairs(unit.items) do reaper.SetMediaItemSelected(it, true) end

  -- Core call (same logic as before, but on the unit selection)
  local CORE_PATH = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"
  local ok_mod, mod = pcall(dofile, CORE_PATH)
  if not ok_mod or not mod then
    bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
    -- Move back best-effort
    for _, it in ipairs(unit.items) do reaper.MoveMediaItemToTrack(it, origTrack) end
    return false, "RGWH Core not found or failed to load: " .. CORE_PATH
  end

  local apply = (type(mod)=="table" and type(mod.apply)=="function") and mod.apply
                or (_G.RGWH and type(_G.RGWH.apply)=="function" and _G.RGWH.apply)
  if not apply then
    bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
    for _, it in ipairs(unit.items) do reaper.MoveMediaItemToTrack(it, origTrack) end
    return false, "RGWH.apply(...) not found"
  end

  -- Read AS_* and resolve auto mono/multi by source channels (use first item of unit)
  local NS = "hsuanice_AS"
  local mode = reaper.GetExtState(NS, "AS_MODE");           if mode == "" then mode = "glue_item_focused_fx" end
  local take_fx_s = reaper.GetExtState(NS, "AS_TAKE_FX");   if take_fx_s == "" then take_fx_s = "1" end
  local track_fx_s= reaper.GetExtState(NS, "AS_TRACK_FX");  if track_fx_s== "" then track_fx_s= "1" end
  local apply_fx_mode = reaper.GetExtState(NS, "AS_APPLY_FX_MODE"); if apply_fx_mode == "" then apply_fx_mode = "auto" end
  if apply_fx_mode == "auto" then
    local first = unit.items[1]
    local tk = first and reaper.GetActiveTake(first)
    local ch = 2
    if tk then
      local src = reaper.GetMediaItemTake_Source(tk)
      if src then ch = reaper.GetMediaSourceNumChannels(src) or 2 end
    end
    apply_fx_mode = (ch == 1) and "mono" or "multi"
  end

  -- Project ExtState snapshot/override for Core
  local function proj_get(ns, key, def)
    local _, val = reaper.GetProjExtState(0, ns, key)
    if val == nil or val == "" then return def else return val end
  end
  local function proj_set(ns, key, val)
    reaper.SetProjExtState(0, ns, key, tostring(val or ""))
  end
  local snap = {
    GLUE_TAKE_FX      = proj_get("RGWH", "GLUE_TAKE_FX",      ""),
    GLUE_TRACK_FX     = proj_get("RGWH", "GLUE_TRACK_FX",     ""),
    GLUE_APPLY_MODE   = proj_get("RGWH", "GLUE_APPLY_MODE",   ""),
    RENDER_TAKE_FX    = proj_get("RGWH", "RENDER_TAKE_FX",    ""),
    RENDER_TRACK_FX   = proj_get("RGWH", "RENDER_TRACK_FX",   ""),
    RENDER_APPLY_MODE = proj_get("RGWH", "RENDER_APPLY_MODE", "")
  }
  local want_take, want_track = true, true
  if mode == "glue_item_focused_fx" then
    proj_set("RGWH", "GLUE_TAKE_FX",     want_take  and "1" or "0")
    proj_set("RGWH", "GLUE_TRACK_FX",    want_track and "1" or "0")
    proj_set("RGWH", "GLUE_APPLY_MODE",  apply_fx_mode)
  else
    proj_set("RGWH", "RENDER_TAKE_FX",    want_take  and "1" or "0")
    proj_set("RGWH", "RENDER_TRACK_FX",   want_track and "1" or "0")
    proj_set("RGWH", "RENDER_APPLY_MODE", apply_fx_mode)
  end

  local ok_apply, err = apply({
    mode                = mode,
    -- Core relies on current selection (the whole unit). We pass the first item for API compatibility.
    item                = unit.items[1],
    apply_fx_mode       = apply_fx_mode,
    focused_track       = FXmediaTrack,
    focused_fxindex     = fxIndex,
    policy_only_focused = true,
  })

  -- Restore project ExtState
  proj_set("RGWH", "GLUE_TAKE_FX",      snap.GLUE_TAKE_FX)
  proj_set("RGWH", "GLUE_TRACK_FX",     snap.GLUE_TRACK_FX)
  proj_set("RGWH", "GLUE_APPLY_MODE",   snap.GLUE_APPLY_MODE)
  proj_set("RGWH", "RENDER_TAKE_FX",    snap.RENDER_TAKE_FX)
  proj_set("RGWH", "RENDER_TRACK_FX",   snap.RENDER_TRACK_FX)
  proj_set("RGWH", "RENDER_APPLY_MODE", snap.RENDER_APPLY_MODE)

  if not ok_apply then
    bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
    for _, it in ipairs(unit.items) do reaper.MoveMediaItemToTrack(it, origTrack) end
    return false, ("RGWH Core apply() error: " .. tostring(err))
  end

  -- Pick Core output (selected), rename, move back, peaks
  local postItem = reaper.GetSelectedMediaItem(0, 0)
  if not (postItem and reaper.ValidatePtr2(0, postItem, "MediaItem*")) then
    bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
    for _, it in ipairs(unit.items) do reaper.MoveMediaItemToTrack(it, origTrack) end
    return false, "Core finished, but no item is selected."
  end

  do
    local tidx = reaper.GetMediaItemInfo_Value(postItem, "I_CURTAKE")
    local tk   = reaper.GetMediaItemTake(postItem, tidx)
    local _, takeName = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
    if FXName and FXName ~= "" then
      reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", takeName .. " - " .. FXName, true)
    end
  end

  -- Move Core output back to the unit's original track
  reaper.MoveMediaItemToTrack(postItem, origTrack)

  -- Restore FX enables
  bypassUnfocusedFX(FXmediaTrack, fxIndex, true)

  --[[ Peaks
  reaper.Main_OnCommand(40289, 0)
  reaper.SetMediaItemSelected(postItem, true)
  reaper.Main_OnCommand(40441, 0)--]]

  return true, postItem
end

-- Build RGWH-like units from current selection:
-- group by track, sort by position, merge touching/overlapping items (epsilon = 1 sample)
function build_units_from_selection()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  local eps = (sr and sr > 0) and (1.0 / sr) or 1e-6

  local n = reaper.CountSelectedMediaItems(0)
  local buckets = {}  -- track_ptr -> { items={...} }
  local order = {}    -- preserve track iteration order

  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it and reaper.ValidatePtr2(0, it, "MediaItem*") then
      local tr = reaper.GetMediaItem_Track(it)
      if tr then
        if not buckets[tr] then buckets[tr] = { items = {} }; order[#order+1] = tr end
        buckets[tr].items[#buckets[tr].items+1] = it
      end
    end
  end

  local units = {}

  for _, tr in ipairs(order) do
    local arr = buckets[tr].items
    table.sort(arr, function(a,b)
      local pa = reaper.GetMediaItemInfo_Value(a, "D_POSITION")
      local pb = reaper.GetMediaItemInfo_Value(b, "D_POSITION")
      if math.abs(pa - pb) <= eps then
        local ea = pa + reaper.GetMediaItemInfo_Value(a, "D_LENGTH")
        local eb = pb + reaper.GetMediaItemInfo_Value(b, "D_LENGTH")
        return ea < eb
      end
      return pa < pb
    end)

    local cur_unit = nil
    local function start_unit(itm)
      local p = reaper.GetMediaItemInfo_Value(itm, "D_POSITION")
      local e = p + reaper.GetMediaItemInfo_Value(itm, "D_LENGTH")
      cur_unit = { track = tr, items = { itm }, UL = p, UR = e }
    end
    local function push_unit()
      if cur_unit then units[#units+1] = cur_unit; cur_unit = nil end
    end

    for _, it in ipairs(arr) do
      local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")

      if not cur_unit then
        start_unit(it)
      else
        local prev_end = cur_unit.UR
        local touching = math.abs(p - prev_end) <= eps
        local overlapping = p < (prev_end - eps)
        if touching or overlapping then
          cur_unit.items[#cur_unit.items+1] = it
          if e > cur_unit.UR then cur_unit.UR = e end
        else
          push_unit()
          start_unit(it)
        end
      end
    end
    push_unit()
  end

  -- DEBUG: dump units
  reaper.ShowConsoleMsg("\n[AS][Units]\n")
  for ui, u in ipairs(units) do
    reaper.ShowConsoleMsg(string.format("  unit#%d  track=%s  UL=%.3f  UR=%.3f  members=%d\n",
      ui, tostring(u.track), u.UL, u.UR, #u.items))
    for mi, it in ipairs(u.items) do
      local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local en = p + l
      local tk = reaper.GetActiveTake(it)
      local nm = ""
      if tk then local _, tnm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false); nm = tnm or "" end
      reaper.ShowConsoleMsg(string.format("    member#%d  [%0.3f..%0.3f]  name='%s'\n", mi, p, en, nm))
    end
  end

  return units
end

-- Return {list, count} of units that intersect given TS window [startLoop..endLoop]
-- Intersect rule: unit.UR > startLoop+eps AND unit.UL < endLoop-eps (with 1-sample epsilon)
function collect_units_intersecting_ts(units, startLoop, endLoop)
  local sr  = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  local eps = (sr and sr > 0) and (1.0 / sr) or 1e-6
  local list = {}
  for _, u in ipairs(units) do
    if (u.UR > (startLoop + eps)) and (u.UL < (endLoop - eps)) then
      list[#list+1] = u
    end
  end
  return list, #list
end

function setNudge()
  reaper.ApplyNudge(0, 0, 0, 0, 1, false, 0)
  reaper.ApplyNudge(0, 0, 0, 0, -1, false, 0)
end

function main()
  debug("") -- clear log

  local nsel = reaper.CountSelectedMediaItems(0)
  if nsel < 1 then
    reaper.MB("Please select one or more media items.", "AudioSweet", 0)
    return
  end

  -- Require a focused Track FX once (shared for the batch)
  local ret_val, tracknumber_Out, itemnumber_Out, fxnumber_Out, window = checkSelectedFX()
  if ret_val ~= 1 then
    debug("Must be a TRACK FX")
    reaper.MB("Please focus a Track FX (not a Take FX).", "AudioSweet", 0)
    return
  end

  -- Normalize focused index and resolve FX label/track once
  local fxIndex = fxnumber_Out
  if fxIndex >= 0x1000000 then fxIndex = fxIndex - 0x1000000 end
  local FXName, FXmediaTrack = getFXname(tracknumber_Out, fxIndex)

  -- Build RGWH-like units from current selection (per track, merge touching/overlapping by 1-sample epsilon)
  local units = build_units_from_selection()
  if #units == 0 then
    reaper.MB("No valid units could be built from selection.", "AudioSweet", 0)
    return
  end

  -- === Global TS-Window: if TS intersects >= 2 units, glue TS once across those units, then print FX per glued result ===
  local loopPoints, startLoop, endLoop = getLoopSelection()
  if loopPoints then
    local intersecting, n = collect_units_intersecting_ts(units, startLoop, endLoop)
    if n >= 2 then
      reaper.Undo_BeginBlock()
      reaper.PreventUIRefresh(1)

      -- 1) Select all members of all intersecting units
      reaper.Main_OnCommand(40289, 0) -- Unselect all
      for _, u in ipairs(intersecting) do
        for _, it in ipairs(u.items) do
          if reaper.ValidatePtr2(0, it, "MediaItem*") then
            reaper.SetMediaItemSelected(it, true)
          end
        end
      end

      -- 2) Glue within time selection (per track, window length; no handles)
      reaper.Main_OnCommand(42432, 0) -- Item: Glue items within time selection

      -- 3) For each glued result (selection now points to them), print focused Track FX then move back
      local glued_count = reaper.CountSelectedMediaItems(0)
      if glued_count == 0 then
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Audiosweet TS-Window (no glued result)", -1)
        reaper.MB("TS-Window glue produced no item. Check your Time Selection.", "AudioSweet", 0)
        return
      end

      -- Normalize focused index & resolve FX label/track (we already did above, just reuse)
      -- local fxIndex = fxIndex (from earlier)
      -- local FXName, FXmediaTrack = FXName, FXmediaTrack (from earlier)

      -- For stability, process glued results one-by-one (apply 40361 needs selection on that item)
      local results = {}
      for i = 0, glued_count - 1 do
        local tsItem = reaper.GetSelectedMediaItem(0, i)
        if tsItem and reaper.ValidatePtr2(0, tsItem, "MediaItem*") then
          local tsOrigTrack = reaper.GetMediaItem_Track(tsItem)

          -- Move to focused-FX track and isolate the focused FX
          reaper.MoveMediaItemToTrack(tsItem, FXmediaTrack)
          bypassUnfocusedFX(FXmediaTrack, fxIndex, false)

          -- Ensure only this tsItem is selected for apply
          reaper.Main_OnCommand(40289, 0)
          reaper.SetMediaItemSelected(tsItem, true)

          -- Auto channel: set FX track channels by source take channels
          local desired_nchan = 2
          do
            local tk = reaper.GetActiveTake(tsItem)
            local ch = 2
            if tk then
              local src = reaper.GetMediaItemTake_Source(tk)
              if src then ch = reaper.GetMediaSourceNumChannels(src) or 2 end
            end
            if ch <= 1 then desired_nchan = 2 else desired_nchan = (ch % 2 == 0) and ch or (ch + 1) end
          end
          local prev_nchan = reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN")
          if prev_nchan ~= desired_nchan then
            reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired_nchan)
          end

          -- Print focused FX to new take
          reaper.Main_OnCommand(40361, 0) -- Apply track FX to items as new take

          -- Restore track channel count if changed
          if prev_nchan and prev_nchan ~= desired_nchan then
            reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
          end

          -- Rename new take: append raw FX label
          do
            local tidx = reaper.GetMediaItemInfo_Value(tsItem, "I_CURTAKE")
            local tk   = reaper.GetMediaItemTake(tsItem, tidx)
            local _, takeName = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
            if FXName and FXName ~= "" then
              reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", takeName .. " - " .. FXName, true)
            end
          end

          -- Move back & restore FX enables
          reaper.MoveMediaItemToTrack(tsItem, tsOrigTrack)
          bypassUnfocusedFX(FXmediaTrack, fxIndex, true)

          results[#results+1] = tsItem
        end
      end

      -- Select all printed results for convenience
      if #results > 0 then
        reaper.Main_OnCommand(40289, 0)
        for _, it in ipairs(results) do
          if reaper.ValidatePtr2(0, it, "MediaItem*") then
            reaper.SetMediaItemSelected(it, true)
          end
        end
      end

      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("Audiosweet TS-Window (multi-units)", 0)
      return
    end
  end

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local outputs = {}

  for _, unit in ipairs(units) do
    -- Ensure only this unit's members are selected (42432/Core depend on selection)
    reaper.Main_OnCommand(40289, 0) -- Unselect all
    for _, it in ipairs(unit.items) do
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        reaper.SetMediaItemSelected(it, true)
      end
    end

    local ok, outItemOrMsg = process_one_unit(unit, FXmediaTrack, fxIndex, FXName)
    if ok and outItemOrMsg and reaper.ValidatePtr2(0, outItemOrMsg, "MediaItem*") then
      outputs[#outputs+1] = outItemOrMsg
    else
      local msg = tostring(outItemOrMsg or "Unknown error")
      reaper.MB("AudioSweet failed on one unit:\n" .. msg, "AudioSweet", 0)
      break
    end
  end

  -- Select produced outputs (if any)
  if #outputs > 0 then
    reaper.Main_OnCommand(40289, 0)
    for _, it in ipairs(outputs) do
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        reaper.SetMediaItemSelected(it, true)
      end
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("Audiosweet Render (units)", 0)
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
