--[[
@description AudioSweet (hsuanice) — Focused Track FX render via RGWH Core, append FX name, rebuild peaks (selected items)
@version 250930_1754
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
  • Mono/Stereo merged: APPLY_FX_MODE from ExtState (auto/mono/multi); Auto resolves by source channels
@changelog
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
  mposition = reaper.GetMediaItemInfo_Value(mediaItem, "D_POSITION")
  mlength = reaper.GetMediaItemInfo_Value (mediaItem, "D_LENGTH")
  mend = mposition + mlength

  if mposition == startLoop and mend <= endLoop then
    test = true
  else test = false
  end
  return test
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
            reaper.Main_OnCommand(41385, 0)--Fit items to time selection, padding with silence
          else debug ("Loop is not equal to MediaItem Length")
          end        
        else 
        end
      
      selTrack = reaper.GetMediaItem_Track(mediaItem)
     
      moveBool = reaper.MoveMediaItemToTrack(mediaItem, FXmediaTrack)--move item to FX track
     
      bypassUnfocusedFX(FXmediaTrack, fxIndex, render)--Bypass all FX except desired FX
     
      -- BEGIN: RGWH Core call (Pro Tools-like default: GLUE + TAKE FX=1 + TRACK FX=1; handles by Core)
      do
        local CORE_PATH = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"

        -- 1) 載入 Core
        local ok_mod, mod = pcall(dofile, CORE_PATH)
        if not ok_mod or not mod then
          reaper.MB("RGWH Core not found or failed to load:\n" .. CORE_PATH, "AudioSweet — Core load failed", 0)
          -- 還原並中止（避免繼續跑 204+）
          bypassUnfocusedFX(FXmediaTrack, fxnumber_Out, true)
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
          bypassUnfocusedFX(FXmediaTrack, fxnumber_Out, true)
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

        -- 4) 快照 Core 會讀的 ExtState，呼叫前覆寫，呼叫後還原
        local function _get(k, def) local v = reaper.GetExtState(NS, k); return v ~= "" and v or def end
        local prev_track_fx   = _get("RENDER_TRACK_FX",   track_fx_s) -- 以當前預設為 def，避免空值
        local prev_take_fx    = _get("RENDER_TAKE_FX",    take_fx_s)
        local prev_apply_mode = _get("RENDER_APPLY_MODE", apply_fx_mode)

        reaper.SetExtState(NS, "RENDER_TRACK_FX",   track_fx_s,  true)
        reaper.SetExtState(NS, "RENDER_TAKE_FX",    take_fx_s,   true)
        reaper.SetExtState(NS, "RENDER_APPLY_MODE", apply_fx_mode, true)

        -- 5) 呼叫 Core（AudioSweet 已把 item 移到 FX 軌並只留焦點 FX；這裡仍保險帶參數）
        local ok_apply, err = apply({
          mode                = mode,          -- 預設 glue_item_focused_fx；可用 ExtState 改成 render_item_focused_fx
          item                = mediaItem,
          apply_fx_mode       = apply_fx_mode, -- 預設 auto：交由 Core 依來源聲道決定 mono/multi
          focused_track       = FXmediaTrack,
          focused_fxindex     = fxnumber_Out,
          policy_only_focused = true,          -- 只印焦點 FX（Core 端還會再保險一次）
        })

        -- 6) 還原 ExtState
        reaper.SetExtState(NS, "RENDER_TRACK_FX",   prev_track_fx,   true)
        reaper.SetExtState(NS, "RENDER_TAKE_FX",    prev_take_fx,    true)
        reaper.SetExtState(NS, "RENDER_APPLY_MODE", prev_apply_mode, true)

        -- 7) 失敗就終止（不 fallback）
        if not ok_apply then
          reaper.MB("RGWH Core apply() error:\n" .. tostring(err), "AudioSweet — Core apply error", 0)
          bypassUnfocusedFX(FXmediaTrack, fxnumber_Out, true)
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
