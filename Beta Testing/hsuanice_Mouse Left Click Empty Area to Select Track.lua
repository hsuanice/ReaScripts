--[[
@description hsuanice_Mouse Left Click Empty Area to Select Track
@version 0.2.2
@author hsuanice
@about
  Select the track immediately on **mouse-down** when clicking on **EMPTY** space
  in the Arrange view track lanes. Skips items/envelopes/ruler/TCP/MCP.
  Toolbar-friendly background watcher: run once to start, run again to stop (true toggle).
  Optional console logging via WANT_DEBUG.

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@requires js_ReaScriptAPI
@provides [main] .
@changelog
  0.2.2 - True toggle: use set_action_options(1+4) to auto-terminate running instance without Task Control dialog;
          remove ExtState-based toggling; keep toolbar ON at start and OFF on exit.
  0.2.1 - Add set_action_options to auto-terminate previous instance (no Task Control dialog) and sync toolbar ON/OFF.
  0.2.0 - Change: select on mouse-down; add immediate UI refresh; pointer validation.
  0.1.0 - Initial release (selected on mouse-up).
]]

-- Auto-terminate previous instance (no dialog), set toolbar ON
-- 1 = terminate if running, 4 = mark this action as toggled ON
if reaper.set_action_options then
  reaper.set_action_options(1 + 4)
end

----------------------------------------------------------------
-- User option
----------------------------------------------------------------
local WANT_DEBUG = false  -- true = print to console

----------------------------------------------------------------
-- Logger
----------------------------------------------------------------
local function Log(msg)
  if WANT_DEBUG then
    reaper.ShowConsoleMsg(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
  end
end

----------------------------------------------------------------
-- Toolbar toggle helpers
----------------------------------------------------------------
local _, _, sectionID, cmdID = reaper.get_action_context()
local function setToggle(on)
  if sectionID and cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(sectionID, cmdID, on and 1 or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

----------------------------------------------------------------
-- Hit-tests (screen-space)
----------------------------------------------------------------
local function TrackIfClickOnArrangeEmpty(x, y)
  -- Only act inside Arrange
  local _, info = reaper.GetThingFromPoint(x, y)    -- e.g. "arrange", "tcp", "ruler"...
  local isArrange = (info == "arrange") or (type(info) == "string" and info:find("arrange", 1, true))
  if not isArrange then
    return nil, ("not arrange (info=%s)"):format(tostring(info))
  end
  -- Skip if on an item (locked items included)
  local item = reaper.GetItemFromPoint(x, y, true)
  if item then
    return nil, "clicked on item"
  end
  -- Resolve track
  local tr = reaper.GetTrackFromPoint(x, y)
  if not tr then
    return nil, "no track at this point (ruler/gap?)"
  end
  return tr, nil
end

local function SelectOnlyTrack(tr)
  if not (tr and reaper.ValidatePtr(tr, "MediaTrack*")) then return end
  reaper.SetOnlyTrackSelected(tr)
  -- Immediate visual refresh (helps with large track counts)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

----------------------------------------------------------------
-- Watcher loop (select on DOWN edge)
----------------------------------------------------------------
local lastDown = false

local function watch()
  -- Dependency check
  if not reaper.APIExists("JS_Mouse_GetState") then
    Log("❌ Missing js_ReaScriptAPI. Install via ReaPack.")
    setToggle(false)
    return
  end

  local state = reaper.JS_Mouse_GetState(1)   -- 1 = check LMB bit
  local x, y  = reaper.GetMousePosition()
  local lmb   = (state & 1) == 1

  if lmb then
    -- DOWN edge: do the selection immediately
    if not lastDown then
      lastDown = true
      Log(("⬇︎ down  (%d,%d)"):format(x, y))
      local tr, why = TrackIfClickOnArrangeEmpty(x, y)
      if tr then
        reaper.Undo_BeginBlock()
        SelectOnlyTrack(tr)
        reaper.Undo_EndBlock("Click empty arrange selects track (mouse-down)", -1)
        local ok, name = reaper.GetTrackName(tr)
        Log(("✅ selected track: %s"):format(ok and name or "(unnamed)"))
      else
        Log("skip: " .. tostring(why))
      end
    end
  else
    -- UP edge: log only (no selection here)
    if lastDown then
      lastDown = false
      Log(("⬆︎ up    (%d,%d)"):format(x, y))
    end
  end

  reaper.defer(watch)
end

----------------------------------------------------------------
-- Start (no ExtState toggle; true one-button toggle is handled by set_action_options)
----------------------------------------------------------------
if WANT_DEBUG then reaper.ClearConsole() end
setToggle(true)
Log("=== Click-empty-select-track watcher started (mouse-down) ===")

reaper.atexit(function()
  -- Set toolbar OFF on exit (pairs with ON at start)
  if reaper.set_action_options then
    -- 8 = mark this action as toggled OFF
    reaper.set_action_options(8)
  end
  setToggle(false)
  Log("🧹 exit cleanup")
end)

watch()
