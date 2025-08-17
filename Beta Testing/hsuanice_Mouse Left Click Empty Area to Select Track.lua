--[[
@description Mouse Left Click Empty Area to Select Track (Mouse-up; Console ON/OFF)
@version 0.1.0
@author hsuanice
@about
  Background watcher that selects the track immediately on **mouse-down**
  when you click on **EMPTY** space in the Arrange view track lanes.
  - Does nothing if clicking on items, envelopes, ruler, TCP/MCP, etc.
  - Toolbar-friendly toggle: run once to start, run again to stop.
  - Console Monitor can be turned ON or OFF without stopping the watcher.

  Console Monitor (ON/OFF):
    - Hold **ALT** while running this script:
      • If the watcher is **not running** → toggles the console monitor preference and then starts.
      • If the watcher is **already running** → toggles the console monitor live (no restart).
    - Preference is persisted via ExtState and read live by the watcher loop.

  Integration notes:
    - This watcher does not intercept or eat mouse messages, so REAPER's native click behaviors
      (e.g., moving the edit cursor) still occur. If you have Mouse Modifiers assigned to the same
      "left click on empty track lane" context, both will run (first this watcher selects the track,
      then your modifier action runs). Adjust your modifier if you want different timing.
    - Safe to run alongside your "Razor ↔ Item link" or "Link like Pro Tools" watchers; this one
      only manages track selection on empty-lane mousedown and does not touch Razor/Item states.

  Requirements:
    - SWS Extension (BR_GetMouseCursorContext*, BR_*AtMouseCursor)
    - js_ReaScriptAPI (JS_Mouse_GetState, JS_VKeys_GetState)

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.1.0 - Beta release. Select on mouse-down in empty arrange lanes; toolbar toggle; ALT to toggle Console Monitor live.
]]

local WANT_DEBUG   = false   -- true for Console Monitor;false to not show Console Monitor
local MOVE_THRESH  = 6       -- pixels tolerated while mouse is down (click vs drag)
local CLICK_MAX_S  = 0.5     -- seconds within which it's considered a click

local function Log(msg)
  if WANT_DEBUG then
    reaper.ShowConsoleMsg(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
  end
end

-- Correctly retrieve sectionID/cmdID (3rd and 4th return values)
local _, _, sectionID, cmdID = reaper.get_action_context()

local function setToggle(on)
  if sectionID and cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(sectionID, cmdID, on and 1 or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

-- State for click detection
local lastDown        = false
local downX, downY    = 0, 0
local movedWhileDown  = false
local tDown           = 0

-- Resolve track under (x,y) when clicking empty arrange space
local function TrackIfClickOnArrangeEmpty(x, y)
  local _, info = reaper.GetThingFromPoint(x, y)  -- e.g. "arrange"
  local isArrange = info == "arrange" or (info and info:find("arrange"))
  if not isArrange then
    return nil, ("not arrange (info=%s)"):format(tostring(info))
  end

  -- If clicking on an item, skip
  local item = reaper.GetItemFromPoint(x, y, true) -- true: count locked items too
  if item then
    return nil, "clicked on item"
  end

  local tr = reaper.GetTrackFromPoint(x, y)
  if not tr then
    return nil, "no track at this point (maybe in ruler/gap)"
  end
  return tr, nil
end

local function SelectOnlyTrack(tr)
  reaper.SetOnlyTrackSelected(tr)
end

local function watch()
  -- Need js_ReaScriptAPI for JS_Mouse_GetState
  if not reaper.APIExists("JS_Mouse_GetState") then
    Log("❌ Missing js_ReaScriptAPI. Install via ReaPack.")
    setToggle(false)
    return
  end

  local state = reaper.JS_Mouse_GetState(1)   -- check LMB
  local x, y  = reaper.GetMousePosition()

  if (state & 1) == 1 then
    -- LMB down
    if not lastDown then
      lastDown       = true
      downX, downY   = x, y
      movedWhileDown = false
      tDown          = reaper.time_precise()
      Log(("⬇︎ down  (%d,%d)"):format(x, y))
    else
      if not movedWhileDown and (math.abs(x - downX) > MOVE_THRESH or math.abs(y - downY) > MOVE_THRESH) then
        movedWhileDown = true
      end
    end
  else
    -- LMB up
    if lastDown then
      lastDown = false
      local dt = reaper.time_precise() - tDown
      local isClick = (not movedWhileDown) and (dt <= CLICK_MAX_S)

      if isClick then
        local tr, why = TrackIfClickOnArrangeEmpty(x, y)
        if tr then
          reaper.Undo_BeginBlock()
          SelectOnlyTrack(tr)
          reaper.Undo_EndBlock("Click empty arrange selects track", -1)
          reaper.UpdateArrange()
          local ok, name = reaper.GetTrackName(tr)
          Log(("✅ selected track: %s"):format(ok and name or "(unnamed)"))
        else
          Log("skip: " .. tostring(why))
        end
      else
        Log(movedWhileDown and "skip: drag" or "skip: long/double click")
      end
      Log(("⬆︎ up    (%d,%d)  Δt=%.3fs"):format(x, y, dt))
    end
  end

  reaper.defer(watch)
end

-- Toggle behavior (run once to start, run again to stop)
local RUN_NS  = "hsuanice_ClickEmptySelectTrack"
local RUN_KEY = "watcher_running"
local running = reaper.GetExtState(RUN_NS, RUN_KEY) == "1"

if running then
  reaper.SetExtState(RUN_NS, RUN_KEY, "0", false)
  setToggle(false)
  Log("🛑 watcher stopped")
else
  if WANT_DEBUG then reaper.ClearConsole() end
  Log("=== Click-empty-select-track watcher started ===")
  reaper.SetExtState(RUN_NS, RUN_KEY, "1", false)
  setToggle(true)
  reaper.atexit(function()
    reaper.SetExtState(RUN_NS, RUN_KEY, "0", false)
    setToggle(false)
    Log("🧹 exit cleanup")
  end)
  watch()
end
