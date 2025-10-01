--[[
@description AudioSweet (hsuanice) — Focused Track FX render via RGWH Core, append FX name, rebuild peaks (selected items)
@version 20251001_1351  TS-Window mode with mono/multi auto-detect
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

function debug(message) --logging
  --reaper.ShowConsoleMsg(tostring(message))
end

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

function main() --main part of the script
  
  
  debug ("") --Clears Log
    
  inst = true --used to instatiate a FX later
  moveBool = false
  render = false
  loopPoints = false
  
  checkSel = countSelected()--Makes sure that there is a MediaItem selected
  if checkSel == true then
    reaper.Undo_BeginBlock()
    
    local mediaItem = reaper.GetSelectedMediaItem(0, 0)
    if not (mediaItem and reaper.ValidatePtr2(0, mediaItem, "MediaItem*")) then
      reaper.MB("Please select exactly one media item.", "AudioSweet", 0)
      reaper.Undo_EndBlock("AudioSweet (no item)", -1)
      return
    end
    ret_val, tracknumber_Out, itemnumber_Out, fxnumber_Out, window = checkSelectedFX()--Yea! An FX is selected!
    if ret_val == 1 then
      -- Normalize focused FX index (remove floating-window flag 0x1000000 if present)
      local fxIndex = fxnumber_Out
      if fxIndex >= 0x1000000 then fxIndex = fxIndex - 0x1000000 end 
      FXName, FXmediaTrack = getFXname(tracknumber_Out, fxIndex)--Get FX name, and FX Track
      
      loopPoints, startLoop, endLoop = getLoopSelection()
      if loopPoints then
        test = mediaItemInLoop(mediaItem, startLoop, endLoop)
        if test then
          -- TS equals unit: do nothing here; proceed to Core path (handles by Core)
        else          -- === TS-Window mode (Pro Tools-like): glue within TS, then print focused Track FX; no handles ===

          -- 1) Glue items within time selection (silent padding in gaps)
          reaper.Main_OnCommand(42432, 0) -- Item: Glue items within time selection

          -- 2) Re-acquire the glued (TS-length) item
          local tsItem = reaper.GetSelectedMediaItem(0, 0)
          if not (tsItem and reaper.ValidatePtr2(0, tsItem, "MediaItem*")) then
            reaper.MB("TS-Window glue failed: no item selected after 42432.", "AudioSweet", 0)
            reaper.Undo_EndBlock("Audiosweet (TS glue failed)", -1)
            return
          end

          -- 3) Move to focused FX track and isolate the focused FX
          local tsOrigTrack = reaper.GetMediaItem_Track(tsItem)
          reaper.MoveMediaItemToTrack(tsItem, FXmediaTrack)
          bypassUnfocusedFX(FXmediaTrack, fxIndex, render)

          -- Ensure only the TS item is selected for apply
          reaper.Main_OnCommand(40289, 0) -- Unselect all
          reaper.SetMediaItemSelected(tsItem, true)

          -- Resolve desired track channel count by source channels (auto: 1ch->mono, >=2ch->multi)
          local desired_nchan = 2
          do
            local tk = reaper.GetActiveTake(tsItem)
            local ch = 2
            if tk then
              local src = reaper.GetMediaItemTake_Source(tk)
              if src then ch = reaper.GetMediaSourceNumChannels(src) or 2 end
            end
            -- REAPER track channels are even (2,4,6,...). Map 1ch->2; >=2ch->nearest even >= ch
            if ch <= 1 then
              desired_nchan = 2
            else
              desired_nchan = (ch % 2 == 0) and ch or (ch + 1)
            end
          end

          -- Snapshot and set the FX track channel count for printing
          local prev_nchan = reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN")
          if prev_nchan ~= desired_nchan then
            reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired_nchan)
          end          

          -- 4) Print focused Track FX to the item (as new take)
          reaper.Main_OnCommand(40361, 0) -- Apply track FX to items as new take

          -- Restore FX track channel count if it was changed
          if prev_nchan and prev_nchan ~= desired_nchan then
            reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
          end

          -- 5) Rename in place: append raw FX label
          do
            local tidx = reaper.GetMediaItemInfo_Value(tsItem, "I_CURTAKE")
            local tk   = reaper.GetMediaItemTake(tsItem, tidx)
            local _, takeName = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
            if FXName and FXName ~= "" then
              reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", takeName .. " - " .. FXName, true)
            end
          end

          -- 6) Move back to original track and restore FX enables
          reaper.MoveMediaItemToTrack(tsItem, tsOrigTrack)
          bypassUnfocusedFX(FXmediaTrack, fxIndex, true)

          -- 7) Rebuild peaks for the processed item
          reaper.Main_OnCommand(40289, 0) -- Unselect all
          reaper.SetMediaItemSelected(tsItem, true)
          reaper.Main_OnCommand(40441, 0) -- Peaks: Rebuild peaks for selected items

          -- 8) Finish TS-Window flow (skip Core path)
          reaper.Undo_EndBlock("Audiosweet TS-Window Glue+Print", 0)
          return
        end
      end

      -- === Normal (unit) path: proceed with Core ===
      selTrack = reaper.GetMediaItem_Track(mediaItem)
      moveBool = reaper.MoveMediaItemToTrack(mediaItem, FXmediaTrack) -- move item to FX track
      bypassUnfocusedFX(FXmediaTrack, fxIndex, render) -- Bypass all FX except desired FX

      -- BEGIN: RGWH Core call (Pro Tools-like default: GLUE + TAKE FX=1 + TRACK FX=1; handles by Core)
      do
        local CORE_PATH = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"

        -- 1) 載入 Core
        local ok_mod, mod = pcall(dofile, CORE_PATH)
        if not ok_mod or not mod then
          reaper.MB("RGWH Core not found or failed to load:\n" .. CORE_PATH, "AudioSweet — Core load failed", 0)
          -- 還原並中止（避免繼續跑 204+）
          bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
          reaper.MoveMediaItemToTrack(mediaItem, selTrack)
          reaper.Undo_EndBlock("Audiosweet (Core load failed)", -1)
          return
        end

        -- 2) 取用 apply()（支援 return 模組或 _G.RGWH）
        local apply = (type(mod)=="table" and type(mod.apply)=="function") and mod.apply
                      or (_G.RGWH and type(_G.RGWH.apply)=="function" and _G.RGWH.apply)
        if not apply then
          reaper.MB("RGWH Core loaded, but RGWH.apply(...) not found.\nPlease expose RGWH.apply(args).",
                    "AudioSweet — Core apply missing", 0)
          bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
          reaper.MoveMediaItemToTrack(mediaItem, selTrack)
          reaper.Undo_EndBlock("Audiosweet (Core apply missing)", -1)
          return
        end

        -- 3) 可設定，但預設採「Pro Tools-like」：
        --    • 模式：Glue
        --    • TAKE FX = 1、TRACK FX = 1
        --    • Handles：完全交給 Core
        --    你也可以用 ExtState 覆蓋預設：
        --       NS="hsuanice_AS"
        --         AS_MODE         = glue_item_focused_fx | render_item_focused_fx
        --         AS_TAKE_FX      = "0" | "1"
        --         AS_TRACK_FX     = "0" | "1"
        --         AS_APPLY_FX_MODE= auto | mono | multi
        local NS = "hsuanice_AS"
        local mode = reaper.GetExtState(NS, "AS_MODE");           if mode == "" then mode = "glue_item_focused_fx" end
        local take_fx_s = reaper.GetExtState(NS, "AS_TAKE_FX");   if take_fx_s == "" then take_fx_s = "1" end
        local track_fx_s= reaper.GetExtState(NS, "AS_TRACK_FX");  if track_fx_s== "" then track_fx_s= "1" end
        local apply_fx_mode = reaper.GetExtState(NS, "AS_APPLY_FX_MODE"); if apply_fx_mode == "" then apply_fx_mode = "auto" end
        -- If caller requested "auto", resolve it now by source channels
        if apply_fx_mode == "auto" then
          local tk = reaper.GetActiveTake(mediaItem)
          local ch = 2
          if tk then
            local src = reaper.GetMediaItemTake_Source(tk)
            if src then ch = reaper.GetMediaSourceNumChannels(src) or 2 end
          end
          apply_fx_mode = (ch == 1) and "mono" or "multi"
        end
        -- 4) Snapshot & override Core's **project** ExtState (namespace=RGWH)
        --    GLUE 模式 → 設 GLUE_*；RENDER 模式 → 設 RENDER_*
        local function proj_get(ns, key, def)
          local _, val = reaper.GetProjExtState(0, ns, key)
          if val == nil or val == "" then return def else return val end
        end
        local function proj_set(ns, key, val)
          reaper.SetProjExtState(0, ns, key, tostring(val or ""))
        end

        -- 先快照（兩組都快照，呼叫後會全部還原）
        local snap = {
          GLUE_TAKE_FX      = proj_get("RGWH", "GLUE_TAKE_FX",      ""),
          GLUE_TRACK_FX     = proj_get("RGWH", "GLUE_TRACK_FX",     ""),
          GLUE_APPLY_MODE   = proj_get("RGWH", "GLUE_APPLY_MODE",   ""),
          RENDER_TAKE_FX    = proj_get("RGWH", "RENDER_TAKE_FX",    ""),
          RENDER_TRACK_FX   = proj_get("RGWH", "RENDER_TRACK_FX",   ""),
          RENDER_APPLY_MODE = proj_get("RGWH", "RENDER_APPLY_MODE", "")
        }

        -- Pro Tools-like 預設：TAKE FX=1, TRACK FX=1；APPLY_FX_MODE 走你上面解析的 apply_fx_mode（auto/mono/multi）
        local want_take, want_track = true, true

        if mode == "glue_item_focused_fx" then
          proj_set("RGWH", "GLUE_TAKE_FX",     want_take  and "1" or "0")
          proj_set("RGWH", "GLUE_TRACK_FX",    want_track and "1" or "0")
          proj_set("RGWH", "GLUE_APPLY_MODE",  apply_fx_mode)   -- auto / mono / multi
        else
          proj_set("RGWH", "RENDER_TAKE_FX",    want_take  and "1" or "0")
          proj_set("RGWH", "RENDER_TRACK_FX",   want_track and "1" or "0")
          proj_set("RGWH", "RENDER_APPLY_MODE", apply_fx_mode)  -- auto / mono / multi
        end

        -- 5) 呼叫 Core（AudioSweet 已把 item 移到 FX 軌並只留焦點 FX；這裡仍保險帶參數）
        local ok_apply, err = apply({
          mode                = mode,          -- 預設 glue_item_focused_fx；可用 ExtState 改成 render_item_focused_fx
          item                = mediaItem,
          apply_fx_mode       = apply_fx_mode, -- 預設 auto：交由 Core 依來源聲道決定 mono/multi
          focused_track       = FXmediaTrack,
          focused_fxindex     = fxIndex,
          policy_only_focused = true,          -- 只印焦點 FX（Core 端還會再保險一次）
        })

        -- 6) Restore project ExtState (RGWH)
        proj_set("RGWH", "GLUE_TAKE_FX",      snap.GLUE_TAKE_FX)
        proj_set("RGWH", "GLUE_TRACK_FX",     snap.GLUE_TRACK_FX)
        proj_set("RGWH", "GLUE_APPLY_MODE",   snap.GLUE_APPLY_MODE)
        proj_set("RGWH", "RENDER_TAKE_FX",    snap.RENDER_TAKE_FX)
        proj_set("RGWH", "RENDER_TRACK_FX",   snap.RENDER_TRACK_FX)
        proj_set("RGWH", "RENDER_APPLY_MODE", snap.RENDER_APPLY_MODE)

        -- 7) 失敗就終止（不 fallback）
        if not ok_apply then
          reaper.MB("RGWH Core apply() error:\n" .. tostring(err), "AudioSweet — Core apply error", 0)
          bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
          reaper.MoveMediaItemToTrack(mediaItem, selTrack)
          reaper.Undo_EndBlock("Audiosweet (Core apply error)", -1)
          return
        end
      end
      -- END: RGWH Core call
      
      -- === Post-Core handoff: use the NEW item produced by Core ===
      local postItem = reaper.GetSelectedMediaItem(0, 0)
      if not (postItem and reaper.ValidatePtr2(0, postItem, "MediaItem*")) then
        reaper.MB("Core finished, but no item is selected.\nCannot continue.", "AudioSweet", 0)
        bypassUnfocusedFX(FXmediaTrack, fxIndex, true)
        reaper.MoveMediaItemToTrack(mediaItem, selTrack) -- best effort restore
        reaper.Undo_EndBlock("Audiosweet (no post item)", -1)
        return
      end

      -- Rename in place (append FX raw name if available)
      do
        local tidx = reaper.GetMediaItemInfo_Value(postItem, "I_CURTAKE")
        local tk   = reaper.GetMediaItemTake(postItem, tidx)
        local _, takeName = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
        if FXName and FXName ~= "" then
          reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", takeName .. " - " .. FXName, true)
        end
      end

      -- Move the processed item back to the original track
      reaper.MoveMediaItemToTrack(postItem, selTrack)

      -- Unbypass all FX on the FX track
      bypassUnfocusedFX(FXmediaTrack, fxIndex, true)

      -- Rebuild peaks for the processed item
      reaper.Main_OnCommand(40289, 0) -- Unselect all
      reaper.SetMediaItemSelected(postItem, true)
      reaper.Main_OnCommand(40441, 0) -- Peaks: Rebuild peaks for selected items
           
    else
      debug ("Must be a TRACK FX")
      return
    end
  
  reaper.Undo_EndBlock("Audiosweet Render", 0)
  else
    return
  end
  
  
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
