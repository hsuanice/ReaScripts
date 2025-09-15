--[[
@description Render or Glue Items with Handles
@version 0.1.1
@author hsuanice
@about
  Single item:
    - Temporarily expands item edges to include user handles (pre/post-roll) without visual jumps,
      using offset compensation when the left handle would cross project 0s.
    - Bypasses all track FX, applies item volume to audio (new take), then un-bypasses track FX.
    - Finally restores the visible item edges; the new take now contains the hidden handles.

  Multiple items:
    - Only the leftmost item gets a left handle; only the rightmost item gets a right handle.
    - Sets a global time selection that includes both handles, glues the selection into a single item,
      then trims back to the original group span. (No takes are created in this mode.)

  Notes:
    - Handle length is capped per item by its visible length; the left handle is also capped by item start.
    - Fades are not baked by glue; item volume is baked when processing a single item.
    - Requires SWS (BR_SetItemEdges). Uses the well-known “temporary edge expansion + offset compensation”
      approach (inspired by community scripts), and the common “apply item volume while avoiding track FX”
      trick (temporarily bypassing track FX).

  Reference:
    - Technique inspired by: Script: az_Open item copy in primary external editor with handles.lua
    - The script internally uses SWS/Xenakios actions to apply item volume while keeping track FX out.

@changelog
  v0.1.1
    - Switch to AZ-style handle creation: temporary edge expansion with left-offset compensation.
    - Single-item path: bake item volume into a fresh take while bypassing track FX to avoid printing them.
    - Multi-item path: group glue with handles only on the outermost items; restore visual span.
    - Stability: pointer guards (ValidatePtr), no visible edge jumps during processing.

  v0.1.0
    - Initial “TS + TrimFill + Apply Track FX Mono ResetVol” prototype (no metadata).
--]]

local R = reaper

-------------------------------------------------
-- User option
-------------------------------------------------
local HANDLE_SEC = 2.0   -- 預設 handle 秒數（秒）

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
    R.MB("需要 SWS 才能執行（缺少 BR_SetItemEdges）。","Missing SWS",0)
    return false
  end
  return true
end

local function require_xen()
  if not CMD_XEN_MONO_RESET or CMD_XEN_MONO_RESET <= 0 then
    R.MB("找不到 _XENAKIOS_APPLYTRACKFXMONORESETVOL（請安裝/啟用 SWS/Xenakios）。","Missing Xenakios",0)
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

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end

-- 取得 take、確保有效
local function get_active_take(it)
  if not it or not R.ValidatePtr(it,"MediaItem*") then return nil end
  local tk = R.GetActiveTake(it)
  if not tk or R.TakeIsMIDI(tk) then return nil end
  return tk
end

-- === AZ-style: 暫時擴邊 + 左越界 offset 補償 ===
-- left_sec/right_sec：希望擴出的秒數（已在外面夾過上限）
-- 回傳一個 table 以便事後還原（orig_pos, orig_end, need_fix, left_shift, take_off_backup）
local function az_expand_item_edges(it, left_sec, right_sec)
  local pos, ed, len = get_bounds(it)
  local tk = get_active_take(it); if not tk then return nil end

  local widePos = pos - (left_sec or 0)
  local wideEnd = ed  + (right_sec or 0)
  local need_fix = false
  local off_backup = R.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0

  if widePos < 0 then
    -- 補償：右邊增加同樣的量，並把原 take 的 offset 先往左挪
    wideEnd = wideEnd - widePos         -- widePos 是負數
    R.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", off_backup + widePos)
    need_fix = true
  end

  -- 暫時擴邊（UI 隱藏）
  R.BR_SetItemEdges(it, (widePos < 0) and 0 or widePos, wideEnd)

  return {
    orig_pos = pos, orig_end = ed,
    need_fix = need_fix,
    left_shift = widePos,      -- <0 表示有左補償量
    off_backup = off_backup,
  }
end

-- 還原邊界，並把左補償 offset 轉給「新 take」
local function az_restore_edges_and_shift_new_take(it, info)
  if not info then return end
  if not it or not R.ValidatePtr(it,"MediaItem*") then return end

  R.BR_SetItemEdges(it, info.orig_pos, info.orig_end)

  if info.need_fix then
    local tk_old = get_active_take(it)  -- 注意：Xenakios 會把「新 take」設為 active；因此還原 offset 要對「上一個 take」進行？
    -- 我們保守做法：把「目前 active take」當成新 take，先把舊 take offset 還原，再把新 take 設負移量
    -- 1) 取得新 take（active）
    local tk_new = tk_old
    -- 2) 尋找舊 take：通常是上一個（index-1），找不到就跳過還原（不致重掛）
    local tk_prev = nil
    local take_cnt = R.CountTakes(it)
    if take_cnt >= 2 then
      tk_prev = R.GetTake(it, take_cnt-2)
    end
    if tk_prev and R.ValidatePtr(tk_prev,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_prev, "D_STARTOFFS", info.off_backup)
    end
    if tk_new and R.ValidatePtr(tk_new,"MediaItem_Take*") then
      R.SetMediaItemTakeInfo_Value(tk_new, "D_STARTOFFS", -math.min(0, info.left_shift or 0))
    end
  end
end

-- 計算此 item 左/右 handle 的上限（以可視長度與起點限制）
local function compute_handle_caps(it)
  local pos, ed, len = get_bounds(it)
  local left_cap  = math.min(HANDLE_SEC, len, pos) -- 左側受 start 限制
  local right_cap = math.min(HANDLE_SEC, len)
  return left_cap, right_cap
end

-------------------------------------------------
-- Single-item path (AZ handles + Xenakios bake item volume)
-------------------------------------------------
local function do_single_item(it)
  if not it or not R.ValidatePtr(it,"MediaItem*") then return end
  local tk = get_active_take(it); if not tk then return end

  local pos, ed, len = get_bounds(it)
  local wantL, wantR = compute_handle_caps(it)

  -- AZ：暫時擴邊（含左側越界 offset 補償）
  local info = az_expand_item_edges(it, wantL, wantR)

  -- Bypass all track FX → Xenakios（產生新 take 並把 item volume 烘進新音檔）→ Unbypass
  R.Main_OnCommand(CMD_BYPASS_ALL, 0)
  R.Main_OnCommand(CMD_XEN_MONO_RESET, 0)
  R.Main_OnCommand(CMD_UNBYPASS_ALL, 0)

  -- 還原邊界＆把左補償 offset 轉給新 take（保持可視位置不變，但新 take 內含 handles）
  az_restore_edges_and_shift_new_take(it, info)

  -- 保持只選該 item（防呆）
  R.SelectAllMediaItems(0,false)
  if R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end
end

-------------------------------------------------
-- Multi-items path (group glue; L only left handle, R only right handle)
-------------------------------------------------
local function do_multi_items(items)
  if #items == 0 then return end

  -- 找最左/最右 item 與群組範圍
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

  -- 左 item 只加左 handle；右 item 只加右 handle
  local L_left, _ = compute_handle_caps(L)
  local _, R_right = compute_handle_caps(Rr)

  -- 暫時擴邊（AZ 方式；UI 隱藏）
  local infoL, infoR = nil, nil
  if L_left > 0 then infoL = az_expand_item_edges(L, L_left, 0) end
  if R_right > 0 then infoR = az_expand_item_edges(Rr, 0, R_right) end

  -- 全域 TS（含 handles，左界若 <0 以 0 取代）
  local ts_a = math.max(0, L_start - L_left)
  local ts_b = R_end + R_right
  local tsa, tsb = save_ts()
  set_ts(ts_a, ts_b)

  -- Glue 所有選取 item → 產生一顆 glued item（單軌假設；跨軌會各自一顆）
  R.SelectAllMediaItems(0,false)
  for _,it in ipairs(items) do if it and R.ValidatePtr(it,"MediaItem*") then R.SetMediaItemSelected(it,true) end end
  R.Main_OnCommand(CMD_GLUE_TS, 0)

  -- Trim 回原群組可視範圍（handles 藏在 glued 檔裡）
  set_ts(L_start, R_end)
  R.Main_OnCommand(CMD_TRIM_TS, 0)
  restore_ts(tsa, tsb)

  -- 注意：Glue 會用新 item 取代原 items；因此不需要再把 L/R 的原邊界還原
  -- （就算要還原也已無對象；這也是為什麼 multi path 不必做 offset 還原）
end

-------------------------------------------------
-- MAIN
-------------------------------------------------
local function main()
  if not require_sws() then return end
  local n = R.CountSelectedMediaItems(0)
  if n == 0 then return end

  -- 收集被選 items
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
  R.Undo_EndBlock("Render or Glue Items with Handles (AZ-style)", -1)
  R.UpdateArrange()
end

main()
