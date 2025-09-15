--[[
@description Render or Glue Items with Handles
@version 0.1.2 glue handle fixed
@author hsuanice
@about
  Single item:
    - Temporarily expands item edges to include user handles (pre/post-roll) without visible jumps,
      using offset compensation when the left handle would cross project 0s.
    - Temporarily bypasses all track FX, applies item volume to audio (creates a new take),
      then un-bypasses track FX.
    - Restores the visible edges and transfers the left-compensation offset to the NEW take.

  Multiple items:
    - Only the leftmost item gets a left handle; only the rightmost item gets a right handle.
    - NEW in v0.1.2: handle size is limited by SOURCE HEADROOM (not by the visible item length),
      so you can get the full requested handle length when the source has enough margin.
    - Disables Loop source on the outer items during processing to avoid loop “fake” headroom.
    - Sets a global time selection that includes both handles, glues into a single item,
      then trims back to the original group span. (No takes are created in this mode.)

  Notes:
    - Fades are not baked by glue; item volume is baked when processing a single item.
    - Requires SWS (BR_SetItemEdges).
  Reference:
    - Technique inspired by: Script: az_Open item copy in primary external editor with handles.lua
    - The script internally uses SWS/Xenakios actions to apply item volume while keeping track FX out.  

@changelog
  v0.1.2
    - Multi-item (glue) handles now use SOURCE headroom (left: start offset; right: remaining source)
      instead of capping by each outer item’s visible length.
    - Temporarily disables Loop source on the two outer items to avoid looping being mistaken for headroom.
  v0.1.1
    - AZ-style handle creation (temporary edge expansion + left-offset compensation) for single item.
    - Single-item path bakes item volume while bypassing track FX.
    - Multi-item path: group glue with handles only on outermost items; restore visual span.
--]]

local R = reaper

-------------------------------------------------
-- User option
-------------------------------------------------
local HANDLE_SEC = 5.0   -- default handle length in seconds

-------------------------------------------------
-- Command IDs
-------------------------------------------------
local CMD_BYPASS_ALL     = 40342 -- Track: Bypass FX on all tracks
local CMD_UNBYPASS_ALL   = 40343 -- Track: Unbypass FX on all tracks
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

-- AZ-style: temporary edge expansion + left-offset compensation
local function az_expand_item_edges(it, left_sec, right_sec)
  local pos, ed, _ = get_bounds(it)
  local tk = get_active_take(it); if not tk then return nil end

  local widePos = pos - (left_sec or 0)
  local wideEnd = ed  + (right_sec or 0)
  local need_fix = false
  local off_backup = R.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0

  if widePos < 0 then
    wideEnd = wideEnd - widePos
    R.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", off_backup + widePos) -- widePos negative
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
    local tk_new = get_active_take(it) -- after Xenakios, new take should be active
    local take_cnt = R.CountTakes(it)
    local tk_prev = (take_cnt >= 2) and R.GetTake(it, take_cnt-2) or nil
    if tk_prev and R.ValidatePtr(tk_prev,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_prev, "D_STARTOFFS", info.off_backup)
    end
    if tk_new and R.ValidatePtr(tk_new,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_new, "D_STARTOFFS", -math.min(0, info.left_shift or 0))
    end
  end
end

-------------------------------------------------
-- Single-item path (unchanged from 0.1.1)
-------------------------------------------------
local function do_single_item(it)
  if not it or not R.ValidatePtr(it,"MediaItem*") then return end
  local tk_before = get_active_take(it); if not tk_before then return end

  -- keep 0.1.1 caps (visual length + start) for single item as previously approved
  local pos, ed, len = get_bounds(it)
  local left_cap  = math.min(HANDLE_SEC, pos)
  local right_cap = math.min(HANDLE_SEC, len)

  local info = az_expand_item_edges(it, left_cap, right_cap)

  R.Main_OnCommand(CMD_BYPASS_ALL, 0)
  R.Main_OnCommand(CMD_XEN_MONO_RESET, 0)
  R.Main_OnCommand(CMD_UNBYPASS_ALL, 0)

  az_restore_edges_and_shift_new_take(it, info)

  R.SelectAllMediaItems(0,false)
  if R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end
end

-------------------------------------------------
-- Multi-items path (glue; use SOURCE headroom, no visible-length cap)
-------------------------------------------------
local function do_multi_items(items)
  if #items == 0 then return end

  -- find outer items and group span
  local L, Rr = nil, nil
  local L_start, R_end = math.huge, -math.huge
  for _,it in ipairs(items) do
    if it and R.ValidatePtr(it,"MediaItem*") then
      local s,e,_ = get_bounds(it)
      if s < L_start then L_start = s; L = it end
      if e > R_end   then R_end   = e; Rr = it end
    end
  end
  if not L or not Rr then return end

  -- compute handles from SOURCE headroom (cap only by HANDLE_SEC and project 0s)
  local tkL = get_active_take(L)
  local tkR = get_active_take(Rr)
  if not tkL or not tkR then return end

  -- temporarily disable Loop source on outer items to avoid loop “fake” headroom
  local loopL = R.GetMediaItemInfo_Value(L, "B_LOOPSRC")
  local loopR = R.GetMediaItemInfo_Value(Rr,"B_LOOPSRC")
  if loopL ~= 0 then R.SetMediaItemInfo_Value(L, "B_LOOPSRC", 0) end
  if loopR ~= 0 then R.SetMediaItemInfo_Value(Rr,"B_LOOPSRC", 0) end

  local left_room  = headroom_left_sec(tkL)
  local right_room = headroom_right_sec(Rr, tkR)  -- needs item len internally

  local L_left  = math.min(HANDLE_SEC, left_room)
  local R_right = math.min(HANDLE_SEC, right_room)

  -- temporary edge expansion (AZ style)
  local infoL, infoR = nil, nil
  if L_left  > 0 then infoL = az_expand_item_edges(L,  L_left, 0) end
  if R_right > 0 then infoR = az_expand_item_edges(Rr, 0, R_right) end

  -- global TS with handles (left clamped at project 0)
  local ts_a = math.max(0, L_start - L_left)
  local ts_b = R_end + R_right
  local tsa, tsb = save_ts()
  set_ts(ts_a, ts_b)

  -- glue → single item (per track)
  R.SelectAllMediaItems(0,false)
  for _,it in ipairs(items) do if it and R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end end
  R.Main_OnCommand(CMD_GLUE_TS, 0)

  -- trim back to original group span
  set_ts(L_start, R_end)
  R.Main_OnCommand(CMD_TRIM_TS, 0)
  restore_ts(tsa, tsb)

  -- no need to restore edges/loop flags: originals are replaced by glue
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
    if not require_xen() then R.PreventUIRefresh(-1); R.Undo_EndBlock("Render/Glue with Handles (abort)", -1); return end
    do_single_item(items[1])
  else
    do_multi_items(items)
  end

  R.PreventUIRefresh(-1)
  R.Undo_EndBlock("Render or Glue Items with Handles", -1)
  R.UpdateArrange()
end

main()
