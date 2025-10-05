--[[
@description AudioSweet Preview Core
@author Hsuanice
@version 2510052349 Core-only user options for SOLO_SCOPE/DEBUG

@about Minimal, self-contained preview runtime. Later we can extract helpers to "hsuanice_AS Core.lua".
@changelog
  v2510052349 — Core-only user options for SOLO_SCOPE/DEBUG
    - Moved user-configurable options into Core: 
      - USER_SOLO_SCOPE = "track" | "item" (default "track")
      - USER_DEBUG = false (enable Core logs when true)
    - Core no longer reads/writes ExtState for SOLO_SCOPE/DEBUG. Wrappers do not need to set these anymore.
    - PREVIEW_MODE still comes from ExtState so wrappers can choose solo vs normal.
    - Added a startup log line to print the current SOLO_SCOPE and DEBUG states.

  v2510052343 — Clarify item tint constant
    - Documentation: explained that `0x1000000` sets the high bit of the color integer, which tells REAPER the custom color is *active*.
    - The color field `I_CUSTOMCOLOR` is stored as `RGB | 0x1000000` where the high bit (0x1000000) enables the tint.
    - Functionally unchanged: placeholder items still tinted bright red for visibility.

  v2510052318 — Fix ranges_touch_or_overlap() nil on re-entry
    - Moved forward declarations (project_epsilon, ranges_touch_or_overlap) to the top so any caller can resolve them.
    - Removed the later duplicate forward-decl block to prevent late-binding/globals turning nil at runtime.
    - Behavior unchanged otherwise: placeholder on source track, re-entry bootstrap, mode switch, and cleanup all intact.
    - Debug stream unchanged (no auto-clear).

  Known issues
    - Razor selection not implemented yet (current order: Time Selection > items span).
    - Cross-wrapper toggle still relies on wrappers updating ExtState hsuanice_AS:PREVIEW_MODE before calling Core.
    - If the placeholder is manually moved/deleted during playback, next run will rebuild by design.
  v2510052130 WIP — Preview Core: Solo scope via ExtState; item-solo uses 41558
    - Options: Core reads ExtState hsuanice_AS:SOLO_SCOPE = "track" (default) | "item".
    - Solo(track): clears item-solo (41185) & track-solo (40340), then forces FX track solo (I_SOLO=1).
    - Solo(item): selects moved items and uses 41558 “Item: Solo exclusive” (no prior unsolo needed).
    - Normal/cleanup: always clear both item-solo (41185) and track-solo (40340) to avoid leftover states.
    - Logs: switch/apply path now prints which scope was applied (TRACK/ITEM).

  v2510052021 Fix no item selection warning
    - Guard: Core now aborts early (no state changes) when there are no selected items.
    - Guard: If a Time Selection exists but none of the selected items intersect it, show a warning and abort.
    - UX: Clear dialog explains “select at least one item (or an item inside the time selection)”.
    - Logs: Prints `no-targets: abort` reasons in the continuous [AS][PREVIEW] stream when DEBUG=1.

  v2510051609 WIP — Preview Core: source-track placeholder detection, safer re-entry
    - Re-entry guard: run() now searches the placeholder **only on the original (source) track**, not the whole project, preventing duplicate placeholders and avoiding heavy scans.
    - State capture: when creating a preview, Core persists `src_track` so subsequent runs can resolve the placeholder even if selection focus moved to the FX track.
    - Cleanup hygiene: `cleanup_if_any()` now also clears `src_track` in state after restoring items and removing the placeholder.
    - Bootstrap on re-entry: if a placeholder is found on the source track, Core **does not rebuild**; it bootstraps runtime (collects moved items by the placeholder span) and only performs mode switching.
    - Logs: unchanged continuous `[AS][PREVIEW]` stream; no console clearing.

    Known issues / notes
    - Razor selection still pending (current order: Time Selection > items span).
    - Cross-wrapper toggle requires the wrapper to flip `hsuanice_AS:PREVIEW_MODE` before calling Core.
    - If the user manually deletes/moves the placeholder during playback, next run will rebuild (by design).
    - Not yet auto-aborting preview when launching full AudioSweet; planned follow-up.
    
  v2510051520 WIP — Placeholder-guarded reentry; no rebuild; true single-tap toggle
    - Core now treats the "PREVIEWING @ …" placeholder on the focused FX track as the ground-truth running flag.
    - On every run() call:
      - If a placeholder is found, Core bootstraps its runtime state (collects current preview items by the placeholder’s time span) and ONLY switches mode (solo↔normal). No re-glue, no re-move, no new placeholder.
      - If no placeholder is found, Core builds a fresh preview as before.
    - Mode switching in _switch_mode() now safely re-selects the moved items before toggling Item-Solo-Exclusive.
    - (Optional) You can pin the placeholder to the FX track (Hunk C) for simpler detection; or skip Hunk C to keep placeholders on source tracks.
    - Keeps your continuous debug stream intact; no console clearing.

    Known notes
    - Normal wrapper should mirror the same ExtState flip to allow cross-wrapper toggling.
    - If the user deletes/moves the placeholder during playback, Core will rebuild on next run (by design).
    - Razor selection still pending; current logic follows Time Selection > item span.

  v2510051403 WIP — Preview Core: ExtState-driven mode, move-based preview, placeholder lifecycle
    - ExtState mode: Core reads hsuanice_AS:PREVIEW_MODE ("solo"/"normal"); wrappers only flip this ExtState then call Core (fallback to opts.default_mode if empty).
    - Focused-FX isolation: snapshots per-FX enable mask on the focused track, enables only the focused FX during preview, restores the mask on cleanup.
    - Move-based preview: selected items are MOVED to the focused-FX track (no level-doubling); originals are replaced by a single white placeholder item.
    - Placeholder marker: one empty item with note `PREVIEWING @ Track <n> - <FXName>` spanning Time Selection (or selected-items span); also serves as the “preview is alive” flag.
    - Loop & stop: uses Time Selection if present else items span; forces Repeat ON; a stop-watcher detects transport stop and triggers full cleanup.
    - Cleanup: runs Unsolo-all (41185), moves items back to the placeholder’s track, removes the placeholder, restores FX-enable mask, selection, and Repeat state.
    - Live toggle: re-running Core while active flips solo↔normal without rebuilding or re-moving items (mode switch only).
    - Debug stream: continuous `[AS][PREVIEW]` logs when `hsuanice_AS:DEBUG=1` (no console clear).

    Known issues
    - Wrappers must set `hsuanice_AS:PREVIEW_MODE` before calling Core; legacy `opts.mode` still works as a fallback.
    - Razor selection not implemented yet (Time Selection / item selection only).
    - If the user manually deletes/moves the placeholder or preview items during playback, cleanup may be incomplete.
    - Not yet auto-aborting preview when launching full AudioSweet; planned: end preview first, then proceed.

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

-- ===== User Options (edit here) ==========================================
-- Solo scope for preview isolation: "track" or "item"
local USER_SOLO_SCOPE = "track"
-- Enable Core debug logs (printed via ASP.log / ASP.dlog)
local USER_DEBUG = false
-- =========================================================================

local ASP = {}

-- === [AS PREVIEW CORE · Debug / State] ======================================
local ASP = _G.ASP or {}
_G.ASP = ASP

-- ===== Forward declarations (must appear before any use) =====
local project_epsilon
local ranges_touch_or_overlap

-- ExtState keys
ASP.ES_NS         = "hsuanice_AS"
ASP.ES_STATE      = "PREVIEW_STATE"     -- json: {running=true/false, mode="solo"/"normal"}
ASP.ES_DEBUG      = "DEBUG"             -- "1" to enable logs
ASP.ES_MODE       = "PREVIEW_MODE"      -- "solo" | "normal" ; wrappers 會寫入，Core 只讀取

-- Mode from ExtState (fallback to opts.default_mode or "solo")
local function read_mode(default_mode)
  local m = reaper.GetExtState(ASP.ES_NS, ASP.ES_MODE)
  if m == "solo" or m == "normal" then return m end
  return default_mode or "solo"
end

-- Solo scope from Core user option only
local function read_solo_scope()
  return (USER_SOLO_SCOPE == "item") and "item" or "track"
end

-- FX enable snapshot/restore on a track
local function snapshot_fx_enabled(track)
  local t = {}
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do
    t[i] = reaper.TrackFX_GetEnabled(track, i)
  end
  return t
end

local function restore_fx_enabled(track, shot)
  if not shot then return end
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do
    local want = shot[i]
    if want ~= nil then reaper.TrackFX_SetEnabled(track, i, want) end
  end
end

-- Isolate focused FX but keep a mask to restore later
local function isolate_only_focused_fx(track, fxindex)
  local mask = snapshot_fx_enabled(track)
  local n = reaper.TrackFX_GetCount(track)
  for i=0, n-1 do reaper.TrackFX_SetEnabled(track, i, i == fxindex) end
  return mask
end

-- Compute preview span: Time Selection > items span
local function compute_preview_span()
  local L,R = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if R > L then return L, R end
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return nil,nil end
  local UL, UR
  for i=0, cnt-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    UL = UL and math.min(UL, pos) or pos
    UR = UR and math.max(UR, pos+len) or (pos+len)
  end
  return UL, UR
end

-- Placeholder: one red empty item with note = PREVIEWING @ Track <n> - <FXName>
local function make_placeholder(track, UL, UR, note)
  local it = reaper.AddMediaItemToTrack(track)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", UL or 0)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",  (UR and UL) and (UR-UL) or 1.0)
  local tk = reaper.AddTakeToMediaItem(it) -- just to satisfy note storage
  reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", true) -- keep empty name
  reaper.ULT_SetMediaItemNote(it, note or "")
  -- set red tint for clarity (RGB | 0x1000000 enables the tint)
  reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", reaper.ColorToNative(255,0,0)|0x1000000)
  reaper.UpdateItemInProject(it)
  return it
end

local function remove_placeholder(it)
  if not it then return end
  reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(it), it)
end

-- 尋找「原始軌」上的佔位 item（以註記開頭 "PREVIEWING @" 判定）
local function find_placeholder_on_track(track)
  if not track then return nil end
  local ic = reaper.CountTrackMediaItems(track)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local _, note = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
    if note and note:find("^PREVIEWING @") then
      local UL  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local LEN = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      return it, UL, UL + LEN
    end
  end
  return nil
end



-- 依據佔位範圍，抓取 FX 軌上屬於「被搬來預覽」的 items（排除佔位本身）
local function collect_preview_items_on_fx_track(track, ph_item, UL, UR)
  local items = {}
  if not track then return items end
  local ic = reaper.CountTrackMediaItems(track)
  for i=0, ic-1 do
    local it = reaper.GetTrackMediaItem(track, i)
    if it ~= ph_item then
      local L = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local R = L + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if ranges_touch_or_overlap(L, R, UL, UR) then
        table.insert(items, it)
      end
    end
  end
  return items
end

-- Debug helpers
local function now_ts()
  return os.date("%H:%M:%S")
end

function ASP._dbg_enabled()
  return USER_DEBUG
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

-- Internal runtime state (persist across re-loads)
ASP._state = ASP._state or {
  running         = false,
  mode            = nil,
  play_was_on     = nil,
  repeat_was_on   = nil,
  selection_cache = nil,
  fx_track        = nil,
  fx_index        = nil,
  moved_items     = {},
  placeholder     = nil,
  fx_enable_shot  = nil,
  stop_watcher    = false,
}

function ASP.is_running()
  return ASP._state.running
end



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

  local scope = read_solo_scope()
  local FXtr  = ASP._state.fx_track

  -- 切換前，先清兩種 solo，確保狀態乾淨
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  if ASP._state.moved_items and #ASP._state.moved_items > 0 then
    ASP._select_items(ASP._state.moved_items, true)

    if newmode == "solo" then
      if scope == "track" then
        if FXtr then reaper.SetMediaTrackInfo_Value(FXtr, "I_SOLO", 1) end
        ASP.log("switch→solo TRACK: FX track solo ON")
      else
        reaper.Main_OnCommand(41558, 0) -- Item: Solo exclusive（排他）
        ASP.log("switch→solo ITEM: item-solo-exclusive ON")
      end
    else
      -- normal：保持非獨奏（上面已清）
      ASP.log("switch→normal: solo cleared (items & tracks)")
    end
  end

  ASP._state.mode = newmode
  write_state({running=true, mode=newmode})
  ASP.log("switch done: now=%s (scope=%s)", newmode, scope)
end


----------------------------------------------------------------
-- (A) Debug / log (先內建；未來可移到 AS Core)
----------------------------------------------------------------
local function debug_enabled()
  return USER_DEBUG
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
project_epsilon = function()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end
local function approx_eq(a,b,eps) eps = eps or project_epsilon(); return math.abs(a-b) <= eps end
ranges_touch_or_overlap = function(a0,a1,b0,b1,eps)
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
  opts = opts or {}
  local FXtrack, FXindex = opts.focus_track, opts.focus_fxindex
  local mode = read_mode(opts.default_mode or "solo")  -- ← 以 ExtState 為主

  if not (mode == "solo" or mode == "normal") then
    reaper.MB("ASP.run: invalid mode", "AudioSweet Preview", 0); return
  end
  if not FXtrack or not FXindex then
    reaper.MB("ASP.run: focus track/fx missing", "AudioSweet Preview", 0); return
  end

  ASP.log("run called, mode=%s", mode)
  ASP.log("Core options: SOLO_SCOPE=%s DEBUG=%s", read_solo_scope(), tostring(USER_DEBUG))
  -- Guard A: require at least one selected item (and if TS exists, require intersection)
  do
    local sel_cnt = reaper.CountSelectedMediaItems(0)
    if sel_cnt == 0 then
      ASP.log("no-targets: abort (no selected items)")
      reaper.MB("No preview targets found. Please select at least one item (or items within the time selection). Preview was not started.","AudioSweet Preview",0)
      return
    end
    local hasTS, tsL, tsR = getLoopSelection()
    if hasTS and tsR > tsL then
      local eps = project_epsilon()
      local overlap_found = false
      for i=0, sel_cnt-1 do
        local it  = reaper.GetSelectedMediaItem(0, i)
        if it then
          local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local fin = pos + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          if ranges_touch_or_overlap(pos, fin, tsL, tsR, eps) then overlap_found = true; break end
        end
      end
      if not overlap_found then
        ASP.log("no-targets: abort (TS set but no selected items intersect %.3f..%.3f)", tsL, tsR)
        reaper.MB("No preview targets found within the current time selection. Please select at least one item inside the time selection.","AudioSweet Preview",0)
        return
      end
    end
  end

  -- ① 先用「佔位 item」偵測是否已在預覽（只查「原始軌」）
  local src_tr = ASP._state.src_track
  if not src_tr then
    local first_sel = reaper.GetSelectedMediaItem(0, 0)
    if first_sel then src_tr = reaper.GetMediaItem_Track(first_sel) end
  end

  local ph, UL, UR = nil, nil, nil
  if src_tr then
    ph, UL, UR = find_placeholder_on_track(src_tr)
  end

  if ph then
    -- runtime bootstrap（不重建、不再搬移）
    ASP._state.running       = true
    ASP._state.fx_track      = FXtrack
    ASP._state.fx_index      = FXindex
    ASP._state.placeholder   = ph
    ASP._state.src_track     = src_tr
    ASP._state.moved_items   = collect_preview_items_on_fx_track(FXtrack, ph, UL, UR)
    ASP._state.mode          = (mode == "solo") and "normal" or "solo"  -- 讓下一步 _switch_mode(mode) 一定會生效
    ASP.log("detected existing placeholder on source track; bootstrap (items=%d)", #ASP._state.moved_items)

    -- 只做「模式切換」，避免任何 rebuild
    ASP._switch_mode(mode)
    return
  end

  -- ② 舊路徑：若為同一實例且 state.running=true（但沒找到佔位），才允許重建（極少見）
  if ASP._state.running then
    ASP.log("run: state.running=true but placeholder missing; rebuilding preview")
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

  -- 隔離 focused FX（並保留快照，結束時還原）
  ASP._state.fx_enable_shot = isolate_only_focused_fx(FXtrack, FXindex)
  ASP.log("focused FX isolated (index=%d)", FXindex or -1)

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

  -- 保險：清 item-solo + 清 track-solo
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  -- 還原 FX enable 狀態
  if ASP._state.fx_track and ASP._state.fx_enable_shot then
    restore_fx_enabled(ASP._state.fx_track, ASP._state.fx_enable_shot)
    ASP._state.fx_enable_shot = nil
    ASP.log("FX enables restored")
  end

  -- 搬回 items 並刪除 placeholder
  ASP._move_back_and_remove_placeholder()

  -- 還原 Repeat / 選取
  ASP._restore_repeat()
  ASP._restore_item_selection()

  ASP._state.running       = false
  ASP._state.mode          = nil
  ASP._state.fx_track      = nil
  ASP._state.fx_index      = nil
  ASP._state.moved_items   = {}
  ASP._state.placeholder   = nil
  ASP._state.src_track     = nil
  ASP._state.stop_watcher  = false

  write_state({running=false, mode=""})
  ASP.log("cleanup done")
end

function ASP._watch_stop_and_cleanup()
  if not ASP._state.running then return end
  local playing = (reaper.GetPlayState() & 1) == 1
  local ph_ok   = ASP._state.placeholder and reaper.ValidatePtr2(0, ASP._state.placeholder, "MediaItem*")
  if (not playing) and ph_ok then
    ASP.log("detected stop + placeholder alive -> cleanup")
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
  local cnt = reaper.CountSelectedMediaItems(0)
  if cnt == 0 then return end

  -- 計算預覽區間，建立佔位（白色空白 item）
  local UL, UR = compute_preview_span()
  local tridx  = reaper.GetMediaTrackInfo_Value(ASP._state.fx_track, "IP_TRACKNUMBER")
  tridx = (tridx and tridx > 0) and math.floor(tridx) or 0
  local _, fxname = reaper.TrackFX_GetFXName(ASP._state.fx_track, ASP._state.fx_index, "")
  local note = string.format("PREVIEWING @ Track %d - %s", tridx, fxname or "Focused FX")

  -- 放在「原始軌」：以第一個選取 item 的軌為準
  local first_sel = reaper.GetSelectedMediaItem(0, 0)
  local src_tr = first_sel and reaper.GetMediaItem_Track(first_sel) or ASP._state.fx_track
  ASP._state.src_track = src_tr  -- 記住原始軌，供重入時查找 placeholder
  ASP._state.placeholder = make_placeholder(src_tr, UL or 0, UR or (UL and UL+1 or 1), note)

  ASP.log("placeholder created: [%0.3f..%0.3f] %s", UL or -1, UR or -1, note)

  -- 搬移所選 item 到 FX 軌
  ASP._state.moved_items = {}
  for i=0, cnt-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      table.insert(ASP._state.moved_items, it)
      reaper.MoveMediaItemToTrack(it, ASP._state.fx_track)
    end
  end
  reaper.UpdateArrange()
  ASP.log("moved %d items -> FX track", #ASP._state.moved_items)
end

function ASP._clear_preview_items_only()
  -- 這裡在新流程不再「刪除」預覽品，而是搬回；保留名義以免其他呼叫
  if ASP._state.moved_items and #ASP._state.moved_items > 0 then
    ASP.log("clear_preview_items_only(): nothing to delete under move-based preview")
  end
end

local function move_items_to_track(items, tr)
  for _,it in ipairs(items or {}) do
    if reaper.ValidatePtr2(0, it, "MediaItem*") then
      reaper.MoveMediaItemToTrack(it, tr)
    end
  end
end

function ASP._move_back_and_remove_placeholder()
  -- 把 items 搬回「佔位 item 的 track」
  if ASP._state.placeholder then
    local ph_tr = reaper.GetMediaItem_Track(ASP._state.placeholder)
    move_items_to_track(ASP._state.moved_items, ph_tr)
    remove_placeholder(ASP._state.placeholder)
    ASP._state.placeholder = nil
    ASP.log("moved items back & removed placeholder")
  else
    ASP.log("no placeholder; skip move-back")
  end
  ASP._state.moved_items = {}
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
  local scope = read_solo_scope()
  local FXtr  = ASP._state.fx_track

  -- 統一先清：item-solo 與 track-solo 都歸零
  reaper.Main_OnCommand(41185, 0) -- Item: Unsolo all
  reaper.Main_OnCommand(40340, 0) -- Track: Unsolo all tracks

  if mode == "solo" then
    if scope == "track" then
      -- 獨奏「FX 目標軌」
      if FXtr then
        -- 直接設 I_SOLO=1（強制 ON，比 toggle 穩）
        reaper.SetMediaTrackInfo_Value(FXtr, "I_SOLO", 1)
        ASP.log("solo TRACK scope: FX track solo ON")
      end
      -- moved_items 僅用於播放與選取，不做 item-solo
      ASP._select_items(ASP._state.moved_items, true)

    else -- scope == "item"
      -- 只獨奏搬移後 items（獨奏項目＝排他）
      ASP._select_items(ASP._state.moved_items, true)
      reaper.Main_OnCommand(41558, 0) -- Item: Solo exclusive（會自動 unsolo 其他 item）
      ASP.log("solo ITEM scope: item-solo-exclusive ON")
    end

  else
    -- normal：保持非獨奏（已經 41185 + 40340 歸零）
    ASP._select_items(ASP._state.moved_items, true)
    ASP.log("normal mode: solo cleared (items & tracks)")
  end

  reaper.Main_OnCommand(1007, 0) -- Transport: Play
end

return ASP
