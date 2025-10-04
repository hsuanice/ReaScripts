--[[
@description AudioSweet Preview Core
@author Hsuanice
@version 2510042327

@about Minimal, self-contained preview runtime. Later we can extract helpers to "hsuanice_AS Core.lua".
@changelog
  2510042327 Initial version.
]]--
local ASP = {}

----------------------------------------------------------------
-- (A) Debug / log (先內建；未來可移到 AS Core)
----------------------------------------------------------------
local function debug_enabled()
  return reaper.GetExtState("hsuanice_AS","DEBUG") == "1"
end
local function log_step(tag, fmt, ...)
  if not debug_enabled() then return end
  local msg = fmt and string.format(fmt, ...) or ""
  reaper.ShowConsoleMsg(string.format("[AS][PREVIEW] %s %s\n", tostring(tag or ""), msg))
end

----------------------------------------------------------------
-- (B) 基本工具（epsilon / selection / units / items / fx）
--   先複製最少需要的，之後再抽到 AS Core
----------------------------------------------------------------
local function project_epsilon()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end
local function approx_eq(a,b,eps) eps = eps or project_epsilon(); return math.abs(a-b) <= eps end
local function ranges_touch_or_overlap(a0,a1,b0,b1,eps)
  eps = eps or project_epsilon()
  return not (a1 < b0 - eps or b1 < a0 - eps)
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

local function move_items_to_track(items, tr)
  for _,it in ipairs(items) do if it then reaper.MoveMediaItemToTrack(it, tr) end end
end

local function items_all_on_track(items, tr)
  for _,it in ipairs(items) do if reaper.GetMediaItem_Track(it) ~= tr then return false end end
  return true
end

local function select_only_items(items)
  reaper.Main_OnCommand(40289, 0)
  for _,it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
end

local function isolate_focused_fx(FXtrack, focusedIndex)
  local cnt = reaper.TrackFX_GetCount(FXtrack)
  for i=0,cnt-1 do reaper.TrackFX_SetEnabled(FXtrack, i, i==focusedIndex) end
end

----------------------------------------------------------------
-- (C) Transport / mute 快照與還原
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
  -- 關 repeat（若一開始是關的）
  if not snap.repeat_on and reaper.GetToggleCommandState(1068) == 1 then
    reaper.Main_OnCommand(1068, 0)
  end
  -- 停止播放（若一開始沒播）
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
-- (D) 入口：只允許單一軌（可多 item），TS 優先於 item selection
----------------------------------------------------------------
function ASP.run(opts)
  opts = opts or {}
  local mode = opts.mode or "normal"  -- "normal" or "solo"
  local FXtrack = opts.focus_track
  local fxIndex = opts.focus_fxindex

  if not FXtrack or not fxIndex then
    reaper.MB("Preview: missing focused FX/track.", "AudioSweet Preview", 0)
    return
  end

  -- 收集 selection → 確認單軌
  local units = build_units_from_selection()
  if #units == 0 then
    reaper.MB("No media items selected.", "AudioSweet Preview", 0); return
  end
  if #units > 1 then
    reaper.MB("Preview supports one track at a time.\nPlease select items on a single track.", "AudioSweet Preview", 0)
    return
  end
  local u = units[1]
  -- 解析 loop 範圍：TS 優先，否則用 unit 範圍
  local hasTS, L, R = getLoopSelection()
  if not hasTS then L, R = u.UL, u.UR end

  -- 準備：搬到 FX 軌、隔離 focused FX
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  local moved_back = {}
  local mute_shot  = nil
  local tr_shot    = snapshot_transport()

  -- 非 solo 避免疊音：靜音原件
  if mode == "normal" then
    mute_shot = snapshot_and_mute(u.items)
  end

  -- 搬移 + 隔離
  move_items_to_track(u.items, FXtrack)
  isolate_focused_fx(FXtrack, fxIndex)
  -- 保險：全都在 FX 軌
  if not items_all_on_track(u.items, FXtrack) then
    move_items_to_track(u.items, FXtrack)
  end

  -- 設定 loop & repeat；normal/solo 都 loop
  set_loop_and_repeat(L, R, true)

  -- 開播 + （solo 專用）獨奏 item
  select_only_items(u.items)
  if mode == "solo" then
    reaper.Main_OnCommand(41561, 0) -- Item properties: Toggle solo exclusive
  end
  reaper.Main_OnCommand(1007, 0)   -- Play

  -- 清理函式交還給外層（第二次觸發或 Stop 後呼叫）
  ASP._cleanup = function()
    -- 停播
    reaper.Main_OnCommand(1016, 0)
    -- 移回原軌
    move_items_to_track(u.items, u.track)
    -- 還原 mute
    restore_mutes(mute_shot)
    -- 還原 FX enable 狀態（這裡簡化：全部打開；若要記錄細粒度之後再加）
    local cnt = reaper.TrackFX_GetCount(FXtrack)
    for i=0,cnt-1 do reaper.TrackFX_SetEnabled(FXtrack, i, true) end
    -- 還原 transport
    restore_transport(tr_shot)
  end

  reaper.PreventUIRefresh(-1); reaper.Undo_EndBlock("AudioSweet Preview begin", 0)
end

function ASP.cleanup_if_any()
  if ASP._cleanup then ASP._cleanup(); ASP._cleanup = nil end
end

return ASP