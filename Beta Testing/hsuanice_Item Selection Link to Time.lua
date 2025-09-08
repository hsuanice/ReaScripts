--[[
@description hsuanice_Item Selection and link to Time
@version 0.2.2 marquee-only link + marquee-only cursor move; suppress simple-click (default)
@author hsuanice
@about
  Background watcher that mirrors ITEM SELECTION to TIME SELECTION (highly conservative):
    • NOW: Only marquee selection (drag in Arrange) will link & move cursor.
    • Simple single-click (incl. Ctrl/⌘-click) is suppressed by default.
    • Selection changes from actions or other scripts are IGNORED by default.
    • Respects Razor Areas — if any Razor exists, pause linking.
    • Ultra lightweight, no UI, no lag.

  Notes:
    • Requires JS_ReaScriptAPI & SWS to robustly classify marquee vs. click/action/script.
      If not present, falls back to permissive behavior (same as 0.1.2) so it never blocks your workflow.

@changelog
  v0.2.2
    - Change: Time link now triggers ONLY on marquee selection (mouse drag beyond threshold in Arrange).
    - Change: Action-/Script-driven selection changes are suppressed (no link) by default.
    - Keep: Edit cursor moves to range start only for marquee selections.
    - Keep: Simple-click suppression (incl. Ctrl/⌘-click) remains ON by default.
  v0.2.1
    - Cursor moves only for marquee; actions/scripts still linked (now disabled in 0.2.2).
  v0.2.0
    - Added simple-click suppression switches; marquee allowed; fallback to 0.1.2 if JS/SWS missing.
  v0.1.2
    - Move edit cursor to time selection start after linking.
  v0.1.1
    - Respect Razor Areas: pause linking when any Razor exists.
  v0.1.0
    - Initial release.
]]

-------------------- USER OPTIONS --------------------
-- If true, clear time selection when no items are selected; otherwise keep previous range.
local CLEAR_WHEN_EMPTY = false

-- Suppress simple mouse single-click selection (incl. Ctrl/⌘-click) from triggering the link.
-- Default = true (i.e., simple-click 不觸發)
local SUPPRESS_SIMPLE_CLICK = true

-- Only marquee may link (actions/scripts ignored). Default true per 0.2.2.
local ONLY_MARQUEE_LINKS = true

-- Pixel distance regarded as "drag" (>= → treated as marquee)
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

  reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
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
  dragged = false,
  down_ctx = "",   -- cursor context at mouse-down
}

local function now_ms() return reaper.time_precise() * 1000.0 end

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
    mouse.down = true
    mouse.down_x, mouse.down_y = x, y
    mouse.dragged = false
    mouse.down_ctx = (is_arrange_context() and "arrange") or "other"
  elseif left_down and mouse.down then
    if not mouse.dragged then
      local dx = math.abs(x - mouse.down_x)
      local dy = math.abs(y - mouse.down_y)
      if dx >= DRAG_THRESHOLD_PX or dy >= DRAG_THRESHOLD_PX then
        mouse.dragged = true
      end
    end
  elseif (not left_down) and mouse.down then
    mouse.down = false
    mouse.last_up_time_ms = now_ms()
  end
end

-- Decide whether this selection change should trigger LINK at all
local function should_allow_link_for_this_change()
  -- If we can't classify (no JS), be permissive like 0.1.2 to avoid breaking workflows.
  if not HAS_JS then
    return true
  end

  -- If only marquee may link, require: dragged in Arrange.
  if ONLY_MARQUEE_LINKS then
    return mouse.dragged and (mouse.down_ctx == "arrange")
  end

  -- Otherwise (not only-marquee):
  if SUPPRESS_SIMPLE_CLICK then
    local tnow = now_ms()
    local recent_click = (mouse.last_up_time_ms >= 0) and ((tnow - mouse.last_up_time_ms) <= CLICK_SUPPRESS_MS)
    if recent_click and (mouse.dragged == false) and (mouse.down_ctx == "arrange") then
      return false -- simple click; suppress
    end
  end
  return true -- allow actions/scripts
end

-- Determine whether this change should MOVE the cursor (only for marquee)
local function should_move_cursor_for_this_change()
  if not HAS_JS then return false end
  return mouse.dragged and (mouse.down_ctx == "arrange")
end

-- Main watcher loop
local last_sig = ""
local function mainloop()
  if any_razor_exists() then
    last_sig = selection_signature()
    reaper.defer(mainloop)
    return
  end

  update_mouse_state()

  local sig = selection_signature()
  if sig ~= last_sig then
    local allow = should_allow_link_for_this_change()
    local move_cursor = should_move_cursor_for_this_change() -- only marquee → true
    last_sig = sig
    if allow then
      reaper.PreventUIRefresh(1)
      apply_time_from_selection(move_cursor)
      reaper.PreventUIRefresh(-1)
      reaper.UpdateArrange()
    end
  end

  reaper.defer(mainloop)
end

mainloop()
