--[[
@description hsuanice_Item Selection and link to Time
@version 0.4.1
@author hsuanice
@about
  Background watcher that mirrors current ITEM SELECTION to the TIME SELECTION (configurable):
    • Default: ONLY link when selection changed by marquee selection, actions, or other scripts.
      (Simple mouse single-click selection, including Ctrl/⌘-click toggles, is suppressed by default.)
    • Respects Razor Areas — if any Razor exists, pausing the link.
    • After linking, moves edit cursor to the time selection start **only for marquee selections**.
    • Ultra lightweight, no UI, no lag.

  How simple-click suppression works:
    • Track mouse down/up and motion distance in Arrange.
    • Drag beyond a pixel threshold counts as marquee (allowed + cursor move).
    • Single-click (no drag) within a short window is suppressed from linking.

  Dependencies (optional):
    • JS_ReaScriptAPI & SWS recommended. If missing, the script falls back to permissive behavior like 0.1.2.

@changelog
  v0.4.1 — Menu Guard (No Click-Through)

    - New: Popup/Menu guard to prevent click-through while menus are open or just closed.
      • Detects OS/REAPER menus (#32768 on Windows / NSMenu on macOS) and suspends linking.
      • Adds a short post-close grace window to absorb residual clicks.

    - Options:
      • SUPPRESS_WHEN_MENU = true (default) — enable the guard.
      • MENU_CLOSE_GRACE_MS = 180 — grace after the menu closes.

    - Debug:
      • When DEBUG_ITEMTIME=true, prints “menu_guard: block this cycle” whenever the guard latches.

    - Behavior:
      • Marquee vs. simple-click classification unchanged.
      • No item→time updates while a menu is modal; reduces accidental TS flicker around context-menu use.

    - Interop:
      • Guard semantics aligned with the Track/Razor script’s click FSM to reduce cross-script interference.

    - Performance:
      • Razor scan throttling from 0.4.0 unchanged; no additional CPU overhead in normal operation.

  v0.4.0 — Performance & Diagnostics

    - New: Adaptive Razor scan throttling
      • Options: RAZOR_SCAN_WHEN_ABSENT=0.08s, RAZOR_SCAN_WHEN_PRESENT=0.25s.
      • Caches last Razor presence and scans on interval to reduce CPU when Razor is active.

    - New: Razor logging policy
      • State-change logging by default; toggle per-cycle logs via DEBUG_RAZOR_VERBOSE.

    - Improved: Debug console coverage and accuracy
      • Correct press duration via down_time_ms; explicit mouse_down / marquee_start / mouse_up logs.
      • Selection-change summary line (allow/move_cursor/dragged/context).
      • BEFORE/AFTER Time Selection now wraps the actual apply_time_from_selection call.
      • Snapshot/restore logs show current → snapshot values.

    - Behavior: No changes to marquee vs. simple-click classification or cursor-move policy.
    - Compatibility: Backward-compatible options; defaults favor low overhead with minimal responsiveness impact.

  v0.3.1
    - Debug: Added optional console logging to observe mouse down/up, marquee detection,
            selection-change classification, Razor gating, and time selection snapshot/restore.
    - Options: DEBUG_ITEMTIME (true/false) and DEBUG_PREFIX.

  v0.3.0
    - Fix: Prevent transient "set time on mouse-down then cancel on mouse-up" when simple clicks are suppressed.
          Implemented time-selection snapshot on mouse-down and automatic restore if the change is classified as a simple click.
    - Option: RESTORE_TS_ON_SUPPRESSED_CLICK (default = true).
    - No behavior change for marquee/action/script updates; cursor move policy unchanged.
  v0.2.1
    - Change: Edit cursor now moves to time selection start ONLY when the selection change came from a marquee drag.
      (Action/Script-triggered selection updates keep time selection in sync but do NOT move the edit cursor.)
  v0.2.0
    - Feature: Suppress time-link for simple mouse single-click selection (incl. Ctrl/⌘-click). Default ON (suppressed).
    - Behavior: Marquee allowed; single-click suppressed. Fallback to 0.1.2 if JS/SWS not present.
  v0.1.2
    - After linking, move edit cursor to time selection start (still respecting Razor).
  v0.1.1
    - Respect Razor Areas: if any Razor exists (track-level or fallback), do not link item → time.
  v0.1.0
    - Initial release. Ultra-light item→time selection link with state-change gating and toolbar sync.
]]

-------------------- USER OPTIONS --------------------
-- If true, clear time selection when no items are selected; otherwise keep previous range.
local CLEAR_WHEN_EMPTY = false

-- Suppress simple mouse single-click selection (incl. Ctrl/⌘-click) from triggering the link.
-- Default = true (i.e., simple-click 不觸發；只保留 marquee / Action / Script)
local SUPPRESS_SIMPLE_CLICK = true

-- Pixel distance regarded as "drag" (>= → treated as marquee, allowed)
local DRAG_THRESHOLD_PX = 4

-- Time window (ms) after a simple click within which a selection-change is considered "from a click"
local CLICK_SUPPRESS_MS = 250

-- 當「簡單點擊」被抑制時，是否把在 mouse-down 前的時間選取還原
local RESTORE_TS_ON_SUPPRESSED_CLICK = true

-- Debug console output
local DEBUG_ITEMTIME = true      -- 打開/關閉除錯輸出（true/false）
local DEBUG_PREFIX   = "[ItemTime] "

-- Optional: only log Razor gating on state changes (not every cycle)
local DEBUG_RAZOR_VERBOSE = false

-- Throttle Razor scan frequency (seconds)
-- Razor 不存在：掃快一點；Razor 存在：掃慢一點更省
local RAZOR_SCAN_WHEN_ABSENT  = 0.08
local RAZOR_SCAN_WHEN_PRESENT = 0.25

-- Tiny tolerance in seconds to avoid floating-point edge issues.
local EPS = 1e-12

-- Debug helpers --
local function D(msg)
  if DEBUG_ITEMTIME then reaper.ShowConsoleMsg((DEBUG_PREFIX .. "%s\n"):format(tostring(msg))) end
end

local function fmt_ts(s, e)
  return ("TS=[%.9f .. %.9f]"):format(s or 0, e or 0)
end

-- Menu guard (block updates while popup menu is open or just closed)
local SUPPRESS_WHEN_MENU = true
local MENU_CLOSE_GRACE_MS = 180   -- short grace after menu closes



------------utilities-------------
local function _is_popup_menu_open()
  if not reaper.APIExists("JS_Window_Find") then return false end
  local h1 = reaper.JS_Window_Find("#32768", true) -- Windows
  local h2 = reaper.JS_Window_Find("NSMenu",  true) -- macOS
  return (h1 and h1 ~= 0) or (h2 and h2 ~= 0)
end

local _menu_open, _menu_closed_t = false, -1
local function menu_guard()
  if not SUPPRESS_WHEN_MENU then return false end
  local now = reaper.time_precise()
  if _is_popup_menu_open() then
    _menu_open = true
    return true
  end
  if _menu_open then
    _menu_open = false
    _menu_closed_t = now
    return true
  end
  if _menu_closed_t >= 0 and (now - _menu_closed_t) < (MENU_CLOSE_GRACE_MS/1000.0) then
    return true
  end
  return false
end



-----------------------------------------------------
if DEBUG_ITEMTIME then reaper.ShowConsoleMsg("") end
------------------------------------------------------

-- Auto-terminate previous instance and toggle ON (1=auto-terminate, 4=toggle ON).
if reaper.set_action_options then reaper.set_action_options(1 | 4) end

-- Mark enabled for this project; and ensure toggle OFF on exit.
reaper.atexit(function()
  if reaper.set_action_options then reaper.set_action_options(8) end -- 8=toggle OFF
  reaper.SetProjExtState(0, "hsuanice_ItemTimeLink", "enabled", "0")
end)
reaper.SetProjExtState(0, "hsuanice_ItemTimeLink", "enabled", "1")

-- Optional deps
local HAS_JS  = reaper.APIExists and reaper.APIExists("JS_Mouse_GetState")
local HAS_SWS = reaper.APIExists and reaper.APIExists("BR_GetMouseCursorContext")

-- Razor presence check (track property P_RAZOREDITS / P_RAZOREDITS_EXT)
local function any_razor_exists()
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt-1 do
    local tr = reaper.GetTrack(0, i)
    local _, ext = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
    if ext and ext ~= "" then return true end
    local _, fbk = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if fbk and fbk ~= "" then return true end
  end
  return false
end

-- Build a tiny signature for current item selection to detect changes cheaply.
local function selection_signature()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return "0|" end
  local min_pos, max_end = math.huge, -math.huge
  for i = 0, n-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos < min_pos then min_pos = pos end
    local iend = pos + len
    if iend > max_end then max_end = iend end
  end
  return string.format("%d|%.12f|%.12f", n, min_pos, max_end)
end

-- Apply time selection from current item selection; optionally move edit cursor to start
local function apply_time_from_selection(move_cursor)
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then
    if CLEAR_WHEN_EMPTY then
      reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
    end
    return
  end

  local min_pos, max_end = math.huge, -math.huge
  for i = 0, n-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos < min_pos then min_pos = pos end
    local iend = pos + len
    if iend > max_end then max_end = iend end
  end

  -- Link: set time selection
  reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
  -- Move cursor only when requested (i.e., marquee selection)
  if move_cursor then
    reaper.SetEditCurPos(min_pos, false, false)
  end
end

----------------------------------------------------------------
-- Mouse watcher (to classify "simple click" vs "drag/marquee")
----------------------------------------------------------------
local mouse = {
  down = false,
  down_x = 0, down_y = 0,
  last_up_time_ms = -1,
  down_time_ms = -1, -- ★ 新增：記住按下時刻
  dragged = false,
  down_ctx = "",   -- cursor context at mouse-down
  ts_snap = nil,   -- ★ 新增：時間選取快照（在左鍵按下那一刻存）
}
local prev_razor_exists = nil -- ★ Razor 是否存在的前一輪狀態（用來降噪）

-- Razor scan throttle cache
local _razor_cached = false
local _razor_last_scan_t = 0.0



local function now_ms()
  return reaper.time_precise() * 1000.0
end

local function get_mouse_xy()
  if HAS_JS then
    local x, y = reaper.GetMousePosition()
    return x or 0, y or 0
  end
  return 0, 0
end

local function is_arrange_context()
  if HAS_SWS then
    local _, ctx = reaper.BR_GetMouseCursorContext()
    return (ctx == "arrange")
  end
  return true
end

local function update_mouse_state()
  if not HAS_JS then return end
  local state = reaper.JS_Mouse_GetState(0xFF) -- mask: all buttons/mods
  local left_down = (state & 1) == 1

  local x, y = get_mouse_xy()

  if left_down and not mouse.down then
    mouse.down_time_ms = now_ms()
    mouse.down = true
    mouse.down_x, mouse.down_y = x, y
    mouse.dragged = false
    mouse.down_ctx = (is_arrange_context() and "arrange") or "other"
    local cur_s, cur_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    D(("mouse_down  x=%d y=%d  ctx=%s  %s"):format(x, y, mouse.down_ctx, fmt_ts(cur_s, cur_e)))

    -- ★ 在左鍵剛按下時，若在 Arrange，就拍一張當下的時間選取快照
    if RESTORE_TS_ON_SUPPRESSED_CLICK and (mouse.down_ctx == "arrange") then
      local ts_s, ts_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
      mouse.ts_snap = { s = ts_s, e = ts_e }
      D(("ts_snapshot  %s"):format(fmt_ts(ts_s, ts_e)))
    else
      mouse.ts_snap = nil
    end

  elseif left_down and mouse.down then
    if not mouse.dragged then
      local dx = math.abs(x - mouse.down_x)
      local dy = math.abs(y - mouse.down_y)
      if dx >= DRAG_THRESHOLD_PX or dy >= DRAG_THRESHOLD_PX then
        D(("marquee_start dx=%d dy=%d thr=%d"):format(dx, dy, DRAG_THRESHOLD_PX))
        mouse.dragged = true
      end
    end
  elseif (not left_down) and mouse.down then
    mouse.down = false
    mouse.last_up_time_ms = now_ms()
    local press_ms = (mouse.down_time_ms >= 0) and (now_ms() - mouse.down_time_ms) or 0
    D(("mouse_up    x=%d y=%d  dragged=%s  press=%dms"):format(x, y, tostring(mouse.dragged), math.floor(press_ms)))
    mouse.down_time_ms = -1


    -- keep mouse.dragged as-is for this cycle (so we can detect marquee on release)
  end
end

-- Decide whether to allow linking for this selection change
local function should_allow_link_for_this_change()
  if not SUPPRESS_SIMPLE_CLICK then
    return true
  end
  if not HAS_JS then
    return true
  end
  local tnow = now_ms()
  local recent_click = (mouse.last_up_time_ms >= 0) and ((tnow - mouse.last_up_time_ms) <= CLICK_SUPPRESS_MS)
  if recent_click and (mouse.dragged == false) and (mouse.down_ctx == "arrange") then
    return false -- simple click; suppress
  end
  return true -- marquee/actions/scripts
end

-- Determine whether this change should MOVE the cursor (only for marquee)
local function should_move_cursor_for_this_change()
  if not HAS_JS then
    -- Without JS we can't reliably detect marquee; be conservative: don't move.
    return false
  end
  -- Consider marquee if drag occurred in Arrange during this interaction
  return mouse.dragged and (mouse.down_ctx == "arrange")
end

-- Main watcher loop
local last_sig = ""
local function mainloop()
  if DEBUG_ITEMTIME and not printed_opts then
    printed_opts = true
    D(("opts  SUPPRESS_SIMPLE_CLICK=%s  DRAG_THRESHOLD_PX=%d  CLICK_SUPPRESS_MS=%d  RESTORE_TS_ON_SUPPRESSED_CLICK=%s")
      :format(tostring(SUPPRESS_SIMPLE_CLICK), DRAG_THRESHOLD_PX, CLICK_SUPPRESS_MS, tostring(RESTORE_TS_ON_SUPPRESSED_CLICK)))
  end  
  -- Throttled Razor scan
  local now = reaper.time_precise()
  local want_interval = (_razor_cached and RAZOR_SCAN_WHEN_PRESENT) or RAZOR_SCAN_WHEN_ABSENT
  if (now - _razor_last_scan_t) >= (want_interval or 0.1) then
    _razor_cached = any_razor_exists()
    _razor_last_scan_t = now
  end

  if _razor_cached then
    if DEBUG_ITEMTIME and (DEBUG_RAZOR_VERBOSE or prev_razor_exists ~= true) then
      D("razor_exists: skip linking this cycle")
    end
    prev_razor_exists = true
    last_sig = selection_signature()
    reaper.defer(mainloop)
    return
  else
    if DEBUG_ITEMTIME and (DEBUG_RAZOR_VERBOSE or prev_razor_exists ~= false) then
      D("razor_cleared: resume linking")
    end
    prev_razor_exists = false
  end
  --------------------------
  if menu_guard() then
    -- 可選：開 debug 時印訊息
    if DEBUG_ITEMTIME then D("menu_guard: block this cycle") end
    reaper.defer(mainloop)
    return
  end

  --------------------------
  update_mouse_state()

  local sig = selection_signature()
  if sig ~= last_sig then
    local allow = should_allow_link_for_this_change()
    local move_cursor = should_move_cursor_for_this_change()
    D(("sel_change  allow=%s  move_cursor=%s  dragged=%s ctx=%s")
      :format(tostring(allow), tostring(move_cursor), tostring(mouse.dragged), tostring(mouse.down_ctx)))
    last_sig = sig

    if allow then
      local before_s, before_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
      D(("link_apply  BEFORE %s"):format(fmt_ts(before_s, before_e)))

      reaper.PreventUIRefresh(1)
      apply_time_from_selection(move_cursor)
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()

      local after_s, after_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
      D(("link_apply  AFTER  %s"):format(fmt_ts(after_s, after_e)))

      mouse.ts_snap = nil
    else
      D("sel_change  SUPPRESSED (simple-click)")
      if RESTORE_TS_ON_SUPPRESSED_CLICK and mouse.ts_snap then
        local cur_s, cur_e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
        D(("ts_restore   cur=%s  ->  snap=%s"):format(fmt_ts(cur_s, cur_e), fmt_ts(mouse.ts_snap.s, mouse.ts_snap.e)))
        local function diff(a,b) return math.abs((a or 0) - (b or 0)) end
        if diff(cur_s, mouse.ts_snap.s) > EPS or diff(cur_e, mouse.ts_snap.e) > EPS then
          reaper.GetSet_LoopTimeRange(true, false, mouse.ts_snap.s or 0, mouse.ts_snap.e or 0, false)
        end
        mouse.ts_snap = nil
      end
    end
  end

  reaper.defer(mainloop)
end

mainloop()
