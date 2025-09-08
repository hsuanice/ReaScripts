--[[
@description hsuanice_Item Selection and link to Time
@version 0.2.0 edit cursor follow time selection + suppress simple-click triggers (default)
@author hsuanice
@about
  Background watcher that mirrors current ITEM SELECTION to the TIME SELECTION (configurable):
    • Default: ONLY link when selection changed by marquee selection, actions, or other scripts.
      (Simple mouse single-click selection, including Ctrl/⌘-click toggles, is suppressed by default.)
    • Respects Razor Areas — if any Razor exists, pausing the link.
    • After linking, moves edit cursor to the time selection start.
    • Ultra lightweight, no UI, no lag.

  How simple-click suppression works (no perfect source-of-change signal in REAPER):
    • We track mouse down/up and motion distance on Arrange. 
    • If a selection change happens within a short window after a non-drag left click (a "simple click"),
      we suppress linking. Dragging beyond a pixel threshold counts as marquee (allowed).

  Dependencies (optional but recommended):
    • JS_ReaScriptAPI (for precise mouse pos/state) and SWS (for BR_GetMouseCursorContext).
      If missing, the script gracefully falls back to "always allow" (i.e., behaves like 0.1.2).

@changelog
  v0.2.0
    - Feature: Added switches to suppress time-link for simple mouse single-click selection
      (including Ctrl/⌘-click). Default OFF (suppressed). Marquee, actions, and scripts still trigger.
    - Behavior: Marquee (drag beyond threshold) is allowed; single-click (no drag) suppressed.
    - Robustness: If JS/SWS not installed, falls back to 0.1.2 behavior so it never breaks your workflow.
    - Kept: Razor-aware pause; edit cursor jumps to range start; auto-terminate + toolbar sync.
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

-- Tiny tolerance in seconds to avoid floating-point edge issues.
local EPS = 1e-12
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

-- Apply time selection from current item selection, and move edit cursor to start
local function apply_time_from_selection()
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
  -- Keep: move edit cursor to time selection start (no view scroll, no seek)
  reaper.SetEditCurPos(min_pos, false, false)
end

----------------------------------------------------------------
-- Mouse watcher (to classify "simple click" vs "drag/marquee")
----------------------------------------------------------------
local mouse = {
  down = false,
  down_x = 0, down_y = 0,
  last_up_time_ms = -1,
  dragged = false,
  down_ctx = "",   -- cursor context at mouse-down
}

local function now_ms()
  return reaper.time_precise() * 1000.0
end

local function get_mouse_xy()
  if HAS_JS then
    local x, y = reaper.GetMousePosition()
    return x or 0, y or 0
  end
  -- Fallback: no JS — we won't be able to detect drag reliably
  return 0, 0
end

local function is_arrange_context()
  if HAS_SWS then
    local _, ctx = reaper.BR_GetMouseCursorContext()
    return (ctx == "arrange")
  end
  -- Without SWS, we can't tell; treat as unknown/true to avoid false blocks
  return true
end

local function update_mouse_state()
  if not HAS_JS then return end
  local state = reaper.JS_Mouse_GetState(0xFF) -- mask: all buttons/mods
  local left_down = (state & 1) == 1

  local x, y = get_mouse_xy()

  if left_down and not mouse.down then
    -- mouse pressed
    mouse.down = true
    mouse.down_x, mouse.down_y = x, y
    mouse.dragged = false
    mouse.down_ctx = (is_arrange_context() and "arrange") or "other"
  elseif left_down and mouse.down then
    -- mouse held: check drag distance
    if not mouse.dragged then
      local dx = math.abs(x - mouse.down_x)
      local dy = math.abs(y - mouse.down_y)
      if dx >= DRAG_THRESHOLD_PX or dy >= DRAG_THRESHOLD_PX then
        mouse.dragged = true
      end
    end
  elseif (not left_down) and mouse.down then
    -- mouse released
    mouse.down = false
    mouse.last_up_time_ms = now_ms()
  end
end

-- Decide whether to allow linking for this selection change
local function should_allow_link_for_this_change()
  if not SUPPRESS_SIMPLE_CLICK then
    return true
  end

  -- If we don't have JS/SWS, we cannot classify — don't block.
  if not HAS_JS then
    return true
  end

  -- If mouse was recently released and it wasn't a drag, and down was on Arrange => simple click
  local tnow = now_ms()
  local recent_click = (mouse.last_up_time_ms >= 0) and ((tnow - mouse.last_up_time_ms) <= CLICK_SUPPRESS_MS)
  if recent_click and (mouse.dragged == false) and (mouse.down_ctx == "arrange") then
    -- Suppress: likely a single click (incl. Ctrl/⌘-click toggle)
    return false
  end

  -- Otherwise allow (covers marquee drag, actions, scripts, non-arrange sources)
  return true
end

-- Main watcher loop
local last_sig = ""
local function mainloop()
  if any_razor_exists() then
    -- respect Razor: do nothing this cycle
    last_sig = selection_signature() -- keep sig in sync to avoid false triggers later
    reaper.defer(mainloop)
    return
  end

  -- Update mouse tracker each frame
  update_mouse_state()

  local sig = selection_signature()
  if sig ~= last_sig then
    -- selection just changed (could be marquee / action / script / click)
    local allow = should_allow_link_for_this_change()
    last_sig = sig
    if allow then
      reaper.PreventUIRefresh(1)
      apply_time_from_selection()
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()
    end
  end

  reaper.defer(mainloop)
end

mainloop()
