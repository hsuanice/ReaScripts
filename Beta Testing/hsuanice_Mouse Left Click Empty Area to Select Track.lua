--[[
@description hsuanice_Mouse Left Click Empty Area to Select Track
@version 0.2.3
@author hsuanice
@about
  Select the track immediately on **mouse-up** when clicking on **EMPTY** space
  in the Arrange view track lanes. Skips items/envelopes/ruler/TCP/MCP.
  Only triggers if mouse-down and mouse-up are at (almost) the same point.
  Toolbar-friendly background watcher: run once to start, run again to stop (true toggle).
  Optional console logging via WANT_DEBUG.

  Note:
  This script was generated using ChatGPT and Copilot based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@requires js_ReaScriptAPI
@changelog
  0.2.3 - Select only if mouse-up is at same position as mouse-down (prevents drag misfires)
  0.2.2 - True toggle: set_action_options(1+4) to auto-terminate running instance, toolbar ON/OFF
  0.2.1 - Add set_action_options for auto-terminate, sync toolbar ON/OFF
  0.2.0 - Change: select on mouse-down, immediate UI refresh
  0.1.0 - Initial release (selected on mouse-up)
]]

if reaper.set_action_options then
  reaper.set_action_options(1 + 4)
end

local WANT_DEBUG = false

local function Log(msg)
  if WANT_DEBUG then
    reaper.ShowConsoleMsg(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
  end
end

local _, _, sectionID, cmdID = reaper.get_action_context()
local function setToggle(on)
  if sectionID and cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(sectionID, cmdID, on and 1 or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

local function TrackIfClickOnArrangeEmpty(x, y)
  local _, info = reaper.GetThingFromPoint(x, y)
  local isArrange = (info == "arrange") or (type(info) == "string" and info:find("arrange", 1, true))
  if not isArrange then
    return nil, ("not arrange (info=%s)"):format(tostring(info))
  end
  local item = reaper.GetItemFromPoint(x, y, true)
  if item then
    return nil, "clicked on item"
  end
  local tr = reaper.GetTrackFromPoint(x, y)
  if not tr then
    return nil, "no track at this point (ruler/gap?)"
  end
  return tr, nil
end

local function SelectOnlyTrack(tr)
  if not (tr and reaper.ValidatePtr(tr, "MediaTrack*")) then return end
  reaper.SetOnlyTrackSelected(tr)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

local lastDown = false
local lastDownPos = {x = nil, y = nil}
local clickTolerance = 3 -- pixels, allow for tiny moves

local function watch()
  if not reaper.APIExists("JS_Mouse_GetState") then
    Log("❌ Missing js_ReaScriptAPI. Install via ReaPack.")
    setToggle(false)
    return
  end

  local state = reaper.JS_Mouse_GetState(1)
  local x, y  = reaper.GetMousePosition()
  local lmb   = (state & 1) == 1

  if lmb then
    if not lastDown then
      lastDown = true
      lastDownPos.x, lastDownPos.y = x, y
      Log(("⬇︎ down  (%d,%d)"):format(x, y))
    end
  else
    if lastDown then
      lastDown = false
      Log(("⬆︎ up    (%d,%d)"):format(x, y))
      local dx = math.abs(x - (lastDownPos.x or x))
      local dy = math.abs(y - (lastDownPos.y or y))
      if dx <= clickTolerance and dy <= clickTolerance then
        local tr, why = TrackIfClickOnArrangeEmpty(x, y)
        if tr then
          reaper.Undo_BeginBlock()
          SelectOnlyTrack(tr)
          reaper.Undo_EndBlock("Click empty arrange selects track (mouse-up)", -1)
          local ok, name = reaper.GetTrackName(tr)
          Log(("✅ selected track: %s"):format(ok and name or "(unnamed)"))
        else
          Log("skip: " .. tostring(why))
        end
      else
        Log(string.format("skip: drag detected (delta %d,%d)", dx, dy))
      end
    end
  end

  reaper.defer(watch)
end

if WANT_DEBUG then reaper.ClearConsole() end
setToggle(true)
Log("=== Click-empty-select-track watcher started (mouse-up, click only) ===")

reaper.atexit(function()
  if reaper.set_action_options then
    reaper.set_action_options(8)
  end
  setToggle(false)
  Log("🧹 exit cleanup")
end)

watch()
