--[[
@description Render or Glue Items with Handles and FX (No Ripple)
@version 0.1.6 No Ripple
@author hsuanice
@about
  Render-or-glue WITH handles, and ALWAYS print TRACK FX to a new take.
  Fix: Multi-item path now preserves handles by printing FX BEFORE trimming
       back to the original visual span.
  - Single item: AZ-style temporary expansion (handles) → apply track FX →
                 restore visible edges (handles preserved in new take source).
  - Multi items: extend outer edges from SOURCE headroom → glue within the
                 extended time selection → apply track FX to the glued result
                 (still extended) → trim back to original span → restore outer fades.
  - NEVER touches Ripple editing.
  - Requires SWS (BR_SetItemEdges). Track-FX print uses SWS/Xenakios.

@changelog
  v0.1.6
    - Change (multi-item): Order = Extend → Glue (extended) → APPLY TRACK FX →
      Trim back → Restore fades. Handles are now preserved on the printed take.
    - Keep: Single-item prints FX with handles; No Ripple safety unchanged.
--]]

local R = reaper

-------------------------------------------------
-- User option
-------------------------------------------------
local HANDLE_SEC = 5.0   -- default handle length in seconds

-------------------------------------------------
-- Command IDs
-------------------------------------------------
local CMD_GLUE_TS        = 42432 -- Item: Glue items within time selection
local CMD_TRIM_TS        = 40508 -- Item: Trim items to time selection
local CMD_XEN_MONO_RESET = R.NamedCommandLookup("_XENAKIOS_APPLYTRACKFXMONORESETVOL")

-------------------------------------------------
-- Guards
-------------------------------------------------
local function require_sws()
  if not R.APIExists or not R.APIExists("BR_SetItemEdges") then
    R.MB("SWS is required (missing BR_SetItemEdges).","Missing SWS",0)
    return false
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
local function save_ts()
  local a,b = R.GetSet_LoopTimeRange(false,false,0,0,false); return a,b
end
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

-- Capture/apply fades
local function capture_fades(it)
  return {
    fin_len   = R.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0,
    fin_shape = R.GetMediaItemInfo_Value(it, "C_FADEINSHAPE") or 0,
    fin_dir   = R.GetMediaItemInfo_Value(it, "D_FADEINDIR") or 0,
    fin_auto  = R.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO") or 0,
    fout_len   = R.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0,
    fout_shape = R.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") or 0,
    fout_dir   = R.GetMediaItemInfo_Value(it, "D_FADEOUTDIR") or 0,
    fout_auto  = R.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") or 0,
  }
end

local function apply_fades(it, cap)
  if not cap or not it or not R.ValidatePtr(it,"MediaItem*") then return end
  local _, _, ilen = get_bounds(it)
  local in_len  = math.max(0, math.min(cap.fin_len  or 0, ilen))
  local out_len = math.max(0, math.min(cap.fout_len or 0, ilen))

  if in_len > 0 then
    R.SetMediaItemInfo_Value(it, "D_FADEINLEN", in_len)
    R.SetMediaItemInfo_Value(it, "C_FADEINSHAPE", cap.fin_shape or 0)
    R.SetMediaItemInfo_Value(it, "D_FADEINDIR",  cap.fin_dir   or 0)
    R.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", cap.fin_auto or 0)
  else
    R.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0)
  end

  if out_len > 0 then
    R.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", out_len)
    R.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE", cap.fout_shape or 0)
    R.SetMediaItemInfo_Value(it, "D_FADEOUTDIR",  cap.fout_dir   or 0)
    R.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", cap.fout_auto or 0)
  else
    R.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0)
  end
end

-- AZ-style: temporary edge expansion + left-offset compensation
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

  return {
    orig_pos = pos, orig_end = ed,
    need_fix = need_fix,
    left_shift = widePos,
    off_backup = off_backup,
  }
end

local function az_restore_edges_and_shift_new_take(it, info)
  if not info or not it or not R.ValidatePtr(it,"MediaItem*") then return end
  R.BR_SetItemEdges(it, info.orig_pos, info.orig_end)

  if info.need_fix then
    local tk_new  = get_active_take(it)
    local tk_prev = (R.CountTakes(it) >= 2) and R.GetTake(it, R.CountTakes(it)-2) or nil
    if tk_prev and R.ValidatePtr(tk_prev,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_prev, "D_STARTOFFS", info.off_backup)
    end
    if tk_new and R.ValidatePtr(tk_new,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_new, "D_STARTOFFS", -math.min(0, info.left_shift or 0))
    end
  end
end

-------------------------------------------------
-- Single-item path: PRINT track FX (no bypass)
-------------------------------------------------
local function do_single_item(it)
  if not it or not R.ValidatePtr(it,"MediaItem*") then return end
  local tk_before = get_active_take(it); if not tk_before then return end

  local pos, ed = get_bounds(it)
  local left_cap  = math.min(HANDLE_SEC, pos) -- clamp by project start
  local right_cap = math.min(HANDLE_SEC, headroom_right_sec(it, tk_before)) -- by SOURCE headroom

  local info = az_expand_item_edges(it, left_cap, right_cap)

  -- Print Track FX to new take (length = expanded)
  R.Main_OnCommand(CMD_XEN_MONO_RESET, 0)

  -- Restore visible edges; handles remain in the new take's source
  az_restore_edges_and_shift_new_take(it, info)

  R.SelectAllMediaItems(0,false)
  if R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end
end

-------------------------------------------------
-- Multi-items path: GLUE (extended) → APPLY FX → TRIM BACK → RESTORE FADES
-------------------------------------------------
local function do_multi_items(items)
  if #items == 0 then return end

  -- Find outer items and span
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

  -- Save outer fades before glue
  local capL = capture_fades(L)
  local capR = capture_fades(Rr)

  -- Compute handle headroom from SOURCE
  local tkL = get_active_take(L)
  local tkR = get_active_take(Rr)
  if not tkL or not tkR then return end

  -- Avoid loop-source faking headroom
  local loopL = R.GetMediaItemInfo_Value(L, "B_LOOPSRC")
  local loopR = R.GetMediaItemInfo_Value(Rr,"B_LOOPSRC")
  if loopL ~= 0 then R.SetMediaItemInfo_Value(L, "B_LOOPSRC", 0) end
  if loopR ~= 0 then R.SetMediaItemInfo_Value(Rr,"B_LOOPSRC", 0) end

  local left_room  = headroom_left_sec(tkL)
  local right_room = headroom_right_sec(Rr, tkR)
  local L_left  = math.min(HANDLE_SEC, left_room)
  local R_right = math.min(HANDLE_SEC, right_room)

  -- Temporary edge expansion (outermost only)
  if L_left  > 0 then az_expand_item_edges(L,  L_left, 0) end
  if R_right > 0 then az_expand_item_edges(Rr, 0, R_right) end

  -- Extended TS for glue (left clamped at 0)
  local tsa0, tsb0 = save_ts()
  local tsA = math.max(0, L_start - L_left)
  local tsB = R_end + R_right
  set_ts(tsA, tsB)

  -- Glue to consolidate (result = extended-length item)
  R.SelectAllMediaItems(0,false)
  for _,it in ipairs(items) do
    if it and R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end
  end
  R.Main_OnCommand(CMD_GLUE_TS, 0)

  -- IMPORTANT: Now print TRACK FX while item is still extended → new take source keeps handles
  if not require_xen() then restore_ts(tsa0, tsb0); return end
  R.Main_OnCommand(CMD_XEN_MONO_RESET, 0)

  -- Trim back to original visual group span (handles preserved in the printed take)
  set_ts(L_start, R_end)
  R.Main_OnCommand(CMD_TRIM_TS, 0)

  -- Restore TS and re-apply outer fades
  restore_ts(tsa0, tsb0)
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
end

-------------------------------------------------
-- MAIN
-------------------------------------------------
local function main()
  if not require_sws() then return end

  local n = R.CountSelectedMediaItems(0)
  if n == 0 then return end

  local items = {}
  for i=0,n-1 do items[#items+1] = R.GetSelectedMediaItem(0, i) end

  R.Undo_BeginBlock()
  R.PreventUIRefresh(1)

  if #items == 1 then
    if not require_xen() then
      R.PreventUIRefresh(-1); R.Undo_EndBlock("Render/Glue with Handles (abort)", -1); return
    end
    do_single_item(items[1])
  else
    do_multi_items(items)
  end

  R.PreventUIRefresh(-1)
  R.Undo_EndBlock("Render or Glue Items with Handles and FX (No Ripple)", -1)
  R.UpdateArrange()
end

main()
