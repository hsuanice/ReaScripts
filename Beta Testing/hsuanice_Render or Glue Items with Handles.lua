--[[
@description Render or Glue Items with Handles
@version 0.1.8 No Ripple
@author hsuanice
@about
  NEW (0.1.8) user option: if a single selected item has ONLY ONE take, use GLUE instead of the
  bypass→apply item volume→unbypass path (so the glued file name/TC behave as desired). If the item
  has 2+ takes, keep the original single-item path. Multi-item path unchanged.

  Safety:
    - During handle extension only, temporarily DISABLE "Trim content behind items when editing" (41117),
      then restore user's original state afterward.
    - Optional DEBUG logs to REAPER console.

@changelog
  v0.1.8
    - Add SINGLE_TAKE_USES_GLUE option for single-item with exactly 1 take.
  v0.1.7
    - Safety: ensure 41117 OFF during handle extension; restore afterward. Added DEBUG logs.
--]]

local R = reaper

-------------------------------------------------
-- User options
-------------------------------------------------
local HANDLE_SEC = 5.0
local SINGLE_TAKE_USES_GLUE = true  -- NEW: single item with exactly 1 take → use GLUE path
local DEBUG = true

local function log(fmt, ...)
  if not DEBUG then return end
  local s = (select('#', ...) > 0) and string.format(fmt, ...) or tostring(fmt)
  R.ShowConsoleMsg("[Handles] "..s.."\n")
end

-------------------------------------------------
-- Command IDs (same as 0.1.7)
-------------------------------------------------
local CMD_BYPASS_ALL     = 40342 -- Track: Bypass FX on all tracks
local CMD_UNBYPASS_ALL   = 40343 -- Track: Unbypass FX on all tracks
local CMD_GLUE_TS        = 42432 -- Item: Glue items within time selection
local CMD_TRIM_TS        = 40508 -- Item: Trim items to time selection
local CMD_XEN_MONO_RESET = R.NamedCommandLookup("_XENAKIOS_APPLYTRACKFXMONORESETVOL")
local CMD_TRIM_BEHIND    = 41117 -- Options: Trim content behind items when editing (toggle)

-------------------------------------------------
-- Guards
-------------------------------------------------
local function require_sws()
  if not R.APIExists or not R.APIExists("BR_SetItemEdges") then
    R.MB("SWS is required (missing BR_SetItemEdges).","Missing SWS",0); return false
  end
  return true
end

local function require_xen()
  if not CMD_XEN_MONO_RESET or CMD_XEN_MONO_RESET <= 0 then
    R.MB("Missing _XENAKIOS_APPLYTRACKFXMONORESETVOL (please install/enable SWS/Xenakios).","Missing Xenakios",0)
    return false
  end
  return true
end

-------------------------------------------------
-- Helpers
-------------------------------------------------
local function save_ts() local a,b = R.GetSet_LoopTimeRange(false,false,0,0,false); return a,b end
local function set_ts(a,b) R.GetSet_LoopTimeRange(true,false,a,b,false) end
local function restore_ts(a,b) R.GetSet_LoopTimeRange(true,false,a or 0,b or 0,false) end

local function get_bounds(it)
  local s = R.GetMediaItemInfo_Value(it, "D_POSITION")
  local l = R.GetMediaItemInfo_Value(it, "D_LENGTH")
  return s, s+l, l
end

local function get_active_take(it)
  if not it or not R.ValidatePtr(it,"MediaItem*") then return nil end
  local tk = R.GetActiveTake(it)
  if not tk or R.TakeIsMIDI(tk) then return nil end
  return tk
end

-- source headroom (seconds)
local function headroom_left_sec(take)
  local off = R.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local pr  = R.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  return math.max(0, off / math.max(1e-12, pr))
end
local function headroom_right_sec(it, take)
  local pr  = R.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local off = R.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local src = R.GetMediaItemTake_Source(take)
  local slen, isQN = R.GetMediaSourceLength(src)
  if isQN then return 0 end
  local len = R.GetMediaItemInfo_Value(it, "D_LENGTH")
  local max_total = slen / math.max(1e-12, pr)
  return math.max(0, max_total - (off / pr + len))
end

-------------------------------------------------
-- Trim-behind safety (41117)
-------------------------------------------------
local function get_trim_behind() return (R.GetToggleCommandStateEx(0, CMD_TRIM_BEHIND) == 1) end
local function set_trim_behind(desired_on)
  local now_on = get_trim_behind()
  if desired_on ~= now_on then R.Main_OnCommand(CMD_TRIM_BEHIND, 0) end
end
local function with_trim_behind_guard(fn, tag)
  local was_on = get_trim_behind()
  log("Guard(%s): trim-behind was %s → OFF for handle extension", tag or "?", was_on and "ON" or "OFF")
  set_trim_behind(false)
  local ok, err = pcall(fn)
  set_trim_behind(was_on)
  log("Guard(%s): trim-behind restored to %s", tag or "?", was_on and "ON" or "OFF")
  if not ok then error(err) end
end

-------------------------------------------------
-- AZ-style expansion + left-offset compensation
-------------------------------------------------
local function az_expand_item_edges(it, left_sec, right_sec)
  local pos, ed = get_bounds(it)
  local tk = get_active_take(it); if not tk then return nil end

  local widePos = pos - (left_sec or 0)
  local wideEnd = ed  + (right_sec or 0)
  local need_fix = false
  local off_backup = R.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0

  if widePos < 0 then
    wideEnd = wideEnd - widePos
    R.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", off_backup + widePos) -- negative
    need_fix = true
  end

  R.BR_SetItemEdges(it, (widePos < 0) and 0 or widePos, wideEnd)
  log("Expand: pos=%.6f → [%.6f, %.6f] (L+=%.3fs, R+=%.3fs)%s",
      pos, (widePos<0) and 0 or widePos, wideEnd, left_sec or 0, right_sec or 0, need_fix and " (left shift fix)" or "")

  return { orig_pos=pos, orig_end=ed, need_fix=need_fix, left_shift=widePos, off_backup=off_backup }
end
local function az_restore_edges_and_shift_new_take(it, info)
  if not info or not it or not R.ValidatePtr(it,"MediaItem*") then return end
  R.BR_SetItemEdges(it, info.orig_pos, info.orig_end)
  log("Restore edges to [%.6f, %.6f]", info.orig_pos, info.orig_end)

  if info.need_fix then
    local tk_new  = get_active_take(it)
    local take_cnt = R.CountTakes(it)
    local tk_prev = (take_cnt >= 2) and R.GetTake(it, take_cnt-2) or nil
    if tk_prev and R.ValidatePtr(tk_prev,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_prev, "D_STARTOFFS", info.off_backup)
    end
    if tk_new and R.ValidatePtr(tk_new,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_new, "D_STARTOFFS", -math.min(0, info.left_shift or 0))
    end
    log("Left-shift compensation applied to takes")
  end
end

-------------------------------------------------
-- Single-item helpers (GLUE variant)
-------------------------------------------------
local function single_item_glue_path(it, left_cap, right_cap)
  local pos, _ = get_bounds(it)
  local info
  with_trim_behind_guard(function()
    info = az_expand_item_edges(it, left_cap, right_cap)
  end, "single-GLUE")

  local tsa, tsb = save_ts()
  local ext_start = math.max(0, info.orig_pos - left_cap)
  local ext_end   = info.orig_end + right_cap
  set_ts(ext_start, ext_end)
  R.SelectAllMediaItems(0,false); if R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end
  R.Main_OnCommand(CMD_GLUE_TS, 0)
  log("Single(GLUE): glued in extended TS [%.6f, %.6f]", ext_start, ext_end)

  set_ts(info.orig_pos, info.orig_end)
  R.Main_OnCommand(CMD_TRIM_TS, 0)
  restore_ts(tsa, tsb)
  log("Single(GLUE): trimmed back to [%.6f, %.6f]", info.orig_pos, info.orig_end)
end

-------------------------------------------------
-- Single item (bypass→apply item vol→unbypass) OR GLUE (when SINGLE_TAKE_USES_GLUE and 1 take)
-------------------------------------------------
local function do_single_item(it)
  if not it or not R.ValidatePtr(it,"MediaItem*") then return end
  local tk_before = get_active_take(it); if not tk_before then return end

  local pos, _ = get_bounds(it)
  local left_cap  = math.min(HANDLE_SEC, pos)
  local right_cap = math.min(HANDLE_SEC, headroom_right_sec(it, tk_before))

  local take_cnt = R.CountTakes(it)
  log("Single: take-count=%d", take_cnt)

  if SINGLE_TAKE_USES_GLUE and take_cnt == 1 then
    single_item_glue_path(it, left_cap, right_cap)
  else
    local info
    with_trim_behind_guard(function()
      info = az_expand_item_edges(it, left_cap, right_cap)
    end, "single-APPLY")

    if not require_xen() then return end
    R.Main_OnCommand(CMD_BYPASS_ALL, 0)
    R.Main_OnCommand(CMD_XEN_MONO_RESET, 0)
    R.Main_OnCommand(CMD_UNBYPASS_ALL, 0)
    log("Single(APPLY): bypass→apply item vol→unbypass")

    az_restore_edges_and_shift_new_take(it, info)
  end

  R.SelectAllMediaItems(0,false)
  if R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end
end

-------------------------------------------------
-- Multi items (glue; preserve outer fades)
-------------------------------------------------
local function capture_fades(it)
  return {
    fin_len = R.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0,
    fin_shape = R.GetMediaItemInfo_Value(it, "C_FADEINSHAPE") or 0,
    fin_dir = R.GetMediaItemInfo_Value(it, "D_FADEINDIR") or 0,
    fin_auto = R.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO") or 0,
    fout_len = R.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0,
    fout_shape = R.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") or 0,
    fout_dir = R.GetMediaItemInfo_Value(it, "D_FADEOUTDIR") or 0,
    fout_auto = R.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") or 0,
  }
end
local function apply_fades(it, cap)
  if not cap or not it or not R.ValidatePtr(it,"MediaItem*") then return end
  local _, _, ilen = get_bounds(it)
  local in_len  = math.max(0, math.min(cap.fin_len  or 0, ilen))
  local out_len = math.max(0, math.min(cap.fout_len or 0, ilen))
  R.SetMediaItemInfo_Value(it, "D_FADEINLEN", in_len)
  R.SetMediaItemInfo_Value(it, "C_FADEINSHAPE", cap.fin_shape or 0)
  R.SetMediaItemInfo_Value(it, "D_FADEINDIR",  cap.fin_dir   or 0)
  R.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", cap.fin_auto or 0)
  R.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", out_len)
  R.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE", cap.fout_shape or 0)
  R.SetMediaItemInfo_Value(it, "D_FADEOUTDIR",  cap.fout_dir   or 0)
  R.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", cap.fout_auto or 0)
end

local function do_multi_items(items)
  if #items == 0 then return end

  local L, Rr = nil, nil
  local L_start, R_end = math.huge, -math.huge
  for _,it in ipairs(items) do
    if it and R.ValidatePtr(it,"MediaItem*") then
      local s,e = get_bounds(it)
      if s < L_start then L_start = s; L = it end
      if e > R_end   then R_end   = e; Rr = it end
    end
  end
  if not L or not Rr then return end
  log("Multi: group span [%.6f, %.6f]", L_start, R_end)

  local capL = capture_fades(L)
  local capR = capture_fades(Rr)

  local tkL = get_active_take(L)
  local tkR = get_active_take(Rr)
  if not tkL or not tkR then return end

  local loopL = R.GetMediaItemInfo_Value(L, "B_LOOPSRC")
  local loopR = R.GetMediaItemInfo_Value(Rr,"B_LOOPSRC")
  if loopL ~= 0 then R.SetMediaItemInfo_Value(L, "B_LOOPSRC", 0) end
  if loopR ~= 0 then R.SetMediaItemInfo_Value(Rr,"B_LOOPSRC", 0) end

  local L_left  = math.min(HANDLE_SEC, headroom_left_sec(tkL))
  local R_right = math.min(HANDLE_SEC, headroom_right_sec(Rr, tkR))

  with_trim_behind_guard(function()
    if L_left  > 0 then az_expand_item_edges(L,  L_left, 0) end
    if R_right > 0 then az_expand_item_edges(Rr, 0, R_right) end
  end, "multi")

  local tsa, tsb = save_ts()
  set_ts(math.max(0, L_start - L_left), R_end + R_right)
  log("Set TS for GLUE (extended)")

  R.SelectAllMediaItems(0,false)
  for _,it in ipairs(items) do if it and R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end end
  R.Main_OnCommand(CMD_GLUE_TS, 0)
  log("Glue within extended TS")

  set_ts(L_start, R_end)
  R.Main_OnCommand(CMD_TRIM_TS, 0)
  restore_ts(tsa, tsb)
  log("Trim back to original span")

  local sel = R.CountSelectedMediaItems(0)
  for i=0, sel-1 do
    local g = R.GetSelectedMediaItem(0, i)
    if g and R.ValidatePtr(g,"MediaItem*") then
      apply_fades(g, {
        fin_len=capL.fin_len, fin_shape=capL.fin_shape, fin_dir=capL.fin_dir, fin_auto=capL.fin_auto,
        fout_len=capR.fout_len, fout_shape=capR.fout_shape, fout_dir=capR.fout_dir, fout_auto=capR.fout_auto
      })
    end
  end
  log("Re-applied outer fades")
end

-------------------------------------------------
-- MAIN
-------------------------------------------------
local function main()
  if not require_sws() then return end

  if DEBUG then R.ShowConsoleMsg("") end
  log("=== Start v0.1.8 (no-FX glue) ===")

  local n = R.CountSelectedMediaItems(0)
  if n == 0 then log("No selected items. Abort."); return end

  local items = {}
  for i=0,n-1 do items[#items+1] = R.GetSelectedMediaItem(0, i) end
  log("Selected items: %d", #items)

  R.Undo_BeginBlock()
  R.PreventUIRefresh(1)

  if #items == 1 then
    do_single_item(items[1])
  else
    do_multi_items(items)
  end

  R.PreventUIRefresh(-1)
  R.Undo_EndBlock("Render or Glue Items with Handles", -1)
  R.UpdateArrange()
  log("=== Done v0.1.8 (no-FX glue) ===")
end

main()
