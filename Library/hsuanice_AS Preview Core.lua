--[[
@description AudioSweet Preview Core
@author Hsuanice
@version 2510050105 WIP — One-tap mode toggle, stop-to-cleanup, continuous debug  

@about Minimal, self-contained preview runtime. Later we can extract helpers to "hsuanice_AS Core.lua".
@changelog
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
local ASP = {}

-- === [AS PREVIEW CORE · Debug / State] ======================================
local ASP = _G.ASP or {}
_G.ASP = ASP

-- ExtState keys
ASP.ES_NS         = "hsuanice_AS"
ASP.ES_STATE      = "PREVIEW_STATE"     -- json: {running=true/false, mode="solo"/"normal"}
ASP.ES_DEBUG      = "DEBUG"             -- "1" to enable logs

-- Debug helpers
local function now_ts()
  return os.date("%H:%M:%S")
end

function ASP._dbg_enabled()
  return (reaper.GetExtState(ASP.ES_NS, ASP.ES_DEBUG) == "1")
end

function ASP.log(fmt, ...)
  if not ASP._dbg_enabled() then return end
  local msg = ("[AS][PREVIEW][%s] " .. fmt):format(now_ts(), ...)
  reaper.ShowConsoleMsg(msg .. "\n")
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

-- Internal runtime state
ASP._state = {
  running         = false,
  mode            = nil,    -- "solo" | "normal"
  play_was_on     = nil,
  repeat_was_on   = nil,
  selection_cache = nil,    -- {itemGUID=true,...}
  fx_track        = nil,
  fx_index        = nil,
  preview_items   = {},     -- { MediaItem, ... } on FX track
  orig_items      = {},     -- used by "normal" mode if we snapshot/mute originals
  stop_watcher    = false,
}

function ASP.is_running()
  return ASP._state.running
end

-- 預覽狀態（讓 run/switch_mode/cleanup 協作）
ASP._state = {
  running = false,
  mode = nil,            -- "normal" | "solo"
  fx_track = nil,
  fx_index = nil,

  -- 本次預覽的目標單位（限制：單一軌）
  unit = nil,            -- { track=MediaTrack*, items={...}, UL, UR }

  -- 轉運的項目（其實就是 unit.items 被搬到 fx_track），結束要搬回 unit.track
  moved_items = nil,     -- = unit.items

  -- 非 solo 時避免疊加：原件靜音快照
  mute_shot = nil,       -- { {it=item, m=0/1}, ... }

  -- 交通工具（Loop/Repeat/Play）快照
  transport_shot = nil,  -- { repeat_on=true/false, playing=true/false }

  -- 原本選取快照：結束後還原
  sel_shot = nil,        -- { [GUID]=true, ... }
}

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

  -- tear down current mode flags/items but keep transport/loop
  ASP._clear_preview_items_only()
  ASP._prepare_preview_items_on_fx_track(newmode)
  ASP._apply_mode_flags(newmode)

  ASP._state.mode = newmode
  write_state({running=true, mode=newmode})
  ASP.log("switch done: now=%s", newmode)
end


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

local function item_guid(it)
  return reaper.BR_GetMediaItemGUID(it)
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
-- Begin preview (or switch if already running)
function ASP.run(opts)
  local mode, FXtrack, FXindex = opts.mode, opts.focus_track, opts.focus_fxindex
  if not (mode == "solo" or mode == "normal") then
    reaper.MB("ASP.run: invalid mode", "AudioSweet Preview", 0); return
  end
  if not FXtrack or not FXindex then
    reaper.MB("ASP.run: focus track/fx missing", "AudioSweet Preview", 0); return
  end

  ASP.log("run called, mode=%s", mode)

  if ASP._state.running then
    if ASP._state.mode ~= mode then
      ASP._switch_mode(mode)
    else
      ASP.log("already running with same mode -> cleanup")
      ASP.cleanup_if_any()
    end
    return
  end

  -- start preview
  ASP._state.running       = true
  ASP._state.mode          = mode
  ASP._state.fx_track      = FXtrack
  ASP._state.fx_index      = FXindex
  ASP._state.selection_cache = ASP._snapshot_item_selection()
  ASP._state.play_was_on   = (reaper.GetPlayState() & 1) == 1
  ASP._state.repeat_was_on = reaper.GetToggleCommandState(1068) == 1

  ASP._arm_loop_region_or_unit()
  ASP._ensure_repeat_on()

  ASP._prepare_preview_items_on_fx_track(mode)
  ASP._apply_mode_flags(mode)

  write_state({running=true, mode=mode})
  ASP.log("preview started: mode=%s", mode)

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

  -- 目標是 "solo"
  if want == "solo" then
    -- 先還原原件靜音（避免疊加判斷失真）
    restore_mutes(st.mute_shot); st.mute_shot = nil
    -- 在 FX 軌上選取預覽項目 → 開啟獨奏
    if st.moved_items and #st.moved_items > 0 then
      select_only_items(st.moved_items)
      reaper.Main_OnCommand(41561, 0) -- Toggle solo exclusive（從 non-solo 切入 → 這次一定變 ON）
    end

  -- 目標是 "normal"
  elseif want == "normal" then
    -- 關閉 item 獨奏（再次 toggle）
    if st.moved_items and #st.moved_items > 0 then
      select_only_items(st.moved_items)
      reaper.Main_OnCommand(41561, 0) -- Toggle solo exclusive（從 solo 切出 → 這次一定變 OFF）
    end
    -- 再把原件靜音，避免疊加
    if st.unit and st.unit.items then
      st.mute_shot = snapshot_and_mute(st.unit.items)
    end
  end

  st.mode = want
end

function ASP.cleanup_if_any()
  if not ASP._state.running then return end
  ASP.log("cleanup begin")

  ASP._clear_preview_items_only()
  ASP._restore_repeat()
  ASP._restore_item_selection()

  ASP._state.running       = false
  ASP._state.mode          = nil
  ASP._state.fx_track      = nil
  ASP._state.fx_index      = nil
  ASP._state.preview_items = {}
  ASP._state.orig_items    = {}
  ASP._state.stop_watcher  = false

  write_state({running=false, mode=""})
  ASP.log("cleanup done")
end

function ASP._watch_stop_and_cleanup()
  if not ASP._state.running then return end
  local playing = (reaper.GetPlayState() & 1) == 1
  if not playing then
    ASP.log("detected stop -> cleanup")
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
    local guid = reaper.BR_GetMediaItemGUID(it)
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
    local guid = reaper.BR_GetMediaItemGUID(it)
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
    return -- 已由 REAPER 自己的 TS 控制 loop
  end

  -- 沒有 TS：用目前選取 items 的包絡範圍
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
  -- Guard：僅允許單一軌（你已經有選擇 guard，這邊假設入口已檢查）
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return end

  -- 建立複本到 FX track
  ASP._state.preview_items = {}
  for i=0, cnt-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local cp  = clone_item_to_track(it, ASP._state.fx_track)
    table.insert(ASP._state.preview_items, cp)
  end
  ASP.log("prepared %d preview items on FX track", #ASP._state.preview_items)
end

function ASP._clear_preview_items_only()
  -- 關閉 item solo、刪除預覽 item
  ASP._select_items(ASP._state.preview_items, true)
  if ASP._state.mode == "solo" then
    -- 關掉 item-solo（exclusive 是切換制，再按一次即可關閉）
    reaper.Main_OnCommand(41561, 0) -- Item: Toggle solo exclusive
  end
  ASP._select_items(ASP._state.preview_items, true)
  reaper.Main_OnCommand(40006, 0)   -- Item: Remove items
  ASP._state.preview_items = {}
  ASP.log("cleared preview items")
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
  ASP._select_items(ASP._state.preview_items, true)
  if mode == "solo" then
    reaper.Main_OnCommand(41561, 0) -- Item properties: Toggle solo exclusive
    ASP.log("solo-exclusive ON on preview items")
  else
    -- normal: 不做任何 mute/solo；（若未來要避免疊音，可在 normal 再加暫時 mute 原 item 的機制）
    ASP.log("normal mode (no item-solo)")
  end
  reaper.Main_OnCommand(1007, 0)    -- Transport: Play
end

return ASP
