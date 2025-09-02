--[[
@description hsuanice_Mouse Left Click Empty Area to Select Track
@version 0.4.1
@author hsuanice
@about
  Select the track when clicking either:
    • EMPTY arrange area in a track lane, or
    • The UPPER HALF of a media item in arrange (non-envelope).
  Supports mouse-up or mouse-down trigger (user option).
  Only triggers if mouse-down and mouse-up are at (almost) the same point (for mouse-up mode).
  Toolbar-friendly background watcher: run once to start, run again to stop (true toggle).
  Optional console logging via WANT_DEBUG.

  Notes:
  - Uses item screen metrics (I_LASTY/I_LASTH) and the track TCP screen rect (P_UI_RECT:tcp.size) to test "upper half".
  - Requires js_ReaScriptAPI for mouse state polling.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@requires js_ReaScriptAPI

@changelog
  0.4.1 - Fix: Prevent "ghost" track selection when interacting with context menus.
           • Suppress selection while right mouse button is down.
           • Suppress selection when mouse is over popup menus or non-REAPER windows 
             (detected via JS_Window_FromPoint, class names like #32768 / NSMenu).
           • Clears lastDown state when a popup is active to avoid accidental triggers.
  0.4.0 - New: Also select track when clicking the UPPER HALF of a media item.
          Add ENABLE_ITEM_UPPER_HALF_SELECT option.
          Fix: console log string concatenation.
  0.3.0 - Add option SELECT_ON_MOUSE_UP: true=mouse-up, false=mouse-down
  0.2.3 - Select only if mouse-up is at same position as mouse-down (prevents drag misfires)
  0.2.2 - True toggle: set_action_options(1+4) to auto-terminate running instance, toolbar ON/OFF
  0.2.1 - Add set_action_options for auto-terminate, sync toolbar ON/OFF
  0.2.0 - Change: select on mouse-down, immediate UI refresh
  0.1.0 - Initial release (selected on mouse-up)
]]

-------------------------------------------------------------
-- User options
-------------------------------------------------------------
local SELECT_ON_MOUSE_UP = true   -- true: mouse-up, false: mouse-down
local ENABLE_ITEM_UPPER_HALF_SELECT = false -- click item upper-half also selects track
local WANT_DEBUG = false          -- true: print to console
local clickTolerance = 3          -- pixels for mouse-up (allow tiny moves)
local SUPPRESS_POPUP_MENU = true

-------------------------------------------------------------
-- Logger
-------------------------------------------------------------
local function Log(msg)
  if WANT_DEBUG then
    reaper.ShowConsoleMsg(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
  end
end

-------------------------------------------------------------
-- Toolbar toggle helpers
-------------------------------------------------------------
local _, _, sectionID, cmdID = reaper.get_action_context()
local function setToggle(on)
  if sectionID and cmdID and cmdID ~= 0 then
    reaper.SetToggleCommandState(sectionID, cmdID, on and 1 or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

-------------------------------------------------------------
-- Geometry helpers
-------------------------------------------------------------
-- Parse "P_UI_RECT:tcp.size" -> x, y, w, h (numbers) when possible.
local function GetTrackTCPRect(tr)
  local ok, rect = reaper.GetSetMediaTrackInfo_String(tr, "P_UI_RECT:tcp.size", "", false)
  if not ok or not rect or rect == "" then return nil end
  -- Accept both "x y w h" or "l t r b"
  local a, b, c, d = rect:match("(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)")
  if not a then return nil end
  a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  if not (a and b and c and d) then return nil end
  -- Heuristic: if values look like left,top,right,bottom convert to x,y,w,h
  if c > a and d > b and (c - a) > 0 and (d - b) > 0 and (c > 200 or d > 40) then
    return a, b, (c - a), (d - b)
  else
    return a, b, c, d
  end
end

-- Return track if mouse is over arrange empty area OR over the upper half of an item.
local function TrackIfClickSelectTarget(x, y)
  local _, info = reaper.GetThingFromPoint(x, y)
  local isArrange = (info == "arrange") or (type(info) == "string" and info:find("arrange", 1, true))
  if not isArrange then
    return nil, ("not arrange (info=%s)"):format(tostring(info))
  end

  -- First, check if we're over an item.
  local item = reaper.GetItemFromPoint(x, y, true)
  if item then
    if not ENABLE_ITEM_UPPER_HALF_SELECT then
      return nil, "clicked on item (upper-half select disabled)"
    end
    local tr = reaper.GetMediaItem_Track(item)
    if not tr then return nil, "no track for item" end

    -- Item Y/H are relative to top of track; we need track top in screen coords.
    local item_rel_y = reaper.GetMediaItemInfo_Value(item, "I_LASTY") or 0
    local item_h     = reaper.GetMediaItemInfo_Value(item, "I_LASTH") or 0

    local tx, ty, tw, th = GetTrackTCPRect(tr)
    if not (ty and th and item_h and item_h > 0) then
      return nil, "couldn't resolve track/item screen rect"
    end

    local item_top_screen = ty + item_rel_y
    local item_mid_screen = item_top_screen + (item_h * 0.5)

    if y <= item_mid_screen then
      return tr, "clicked item upper half"
    else
      return nil, "clicked item lower half"
    end
  end

  -- Otherwise, empty arrange area: select that lane's track.
  local tr = reaper.GetTrackFromPoint(x, y)
  if not tr then
    return nil, "no track at this point (ruler/gap?)"
  end
  return tr, "clicked arrange empty"
end

local function SelectOnlyTrack(tr)
  if not (tr and reaper.ValidatePtr(tr, "MediaTrack*")) then return end
  reaper.SetOnlyTrackSelected(tr)
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end

-------------------------------------------------------------
-- Watcher loop (mouse-up or mouse-down selectable)
-------------------------------------------------------------
local lastDown = false
local lastDownPos = {x = nil, y = nil}

local function watch()
  if not reaper.APIExists("JS_Mouse_GetState") then
    Log("❌ Missing js_ReaScriptAPI. Install via ReaPack.")
    setToggle(false)
    return
  end

  -- 舊：local state = reaper.JS_Mouse_GetState(1)
  local state = reaper.JS_Mouse_GetState(1 + 2)  -- 1=Left, 2=Right
  local x, y  = reaper.GetMousePosition()

  -- === Guard: 抑制右鍵／選單互動 ===
  if SUPPRESS_POPUP_MENU then
    -- A) 右鍵按下時，直接跳過
    if (state & 2) == 2 then
      lastDown = false
      reaper.defer(watch); return
    end

    -- B) 滑鼠當前位於 REAPER 之外（例如系統選單、工具提示…）時，跳過
    if reaper.APIExists("JS_Window_FromPoint") then
      local hwnd = reaper.JS_Window_FromPoint(x, y)
      local main = reaper.GetMainHwnd()
      if hwnd then
        local cls = reaper.JS_Window_GetClassName(hwnd) or ""
        local isChild = reaper.JS_Window_IsChild(main, hwnd)
        local overNonMain = (hwnd ~= main and not isChild)

        -- Windows 的右鍵選單類名多為 "#32768"；macOS 常見為 "NSMenu"
        if overNonMain or cls == "#32768" or cls == "NSMenu" then
          -- 重要：把 lastDown 清掉，避免「吃到」選單裡那次左鍵的 mouse-up
          lastDown = false
          reaper.defer(watch); return
        end
      end
    end
  end
  

  if SELECT_ON_MOUSE_UP then
    -- mouse-up mode
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
          local tr, why = TrackIfClickSelectTarget(x, y)
          if tr then
            reaper.Undo_BeginBlock()
            SelectOnlyTrack(tr)
            reaper.Undo_EndBlock("Select track by empty/upper-half click (mouse-up)", -1)
            local ok, name = reaper.GetTrackName(tr)
            Log(("✅ selected track: %s (%s)"):format(ok and name or "(unnamed)", tostring(why)))
          else
            Log("skip: " .. tostring(why))
          end
        else
          Log(string.format("skip: drag detected (delta %d,%d)", dx, dy))
        end
      end
    end
  else
    -- mouse-down mode
    if lmb then
      if not lastDown then
        lastDown = true
        Log(("⬇︎ down  (%d,%d)"):format(x, y))
        local tr, why = TrackIfClickSelectTarget(x, y)
        if tr then
          reaper.Undo_BeginBlock()
          SelectOnlyTrack(tr)
          reaper.Undo_EndBlock("Select track by empty/upper-half click (mouse-down)", -1)
          local ok, name = reaper.GetTrackName(tr)
          Log(("✅ selected track: %s (%s)"):format(ok and name or "(unnamed)", tostring(why)))
        else
          Log("skip: " .. tostring(why))
        end
      end
    else
      if lastDown then
        lastDown = false
        Log(("⬆︎ up    (%d,%d)"):format(x, y))
      end
    end
  end

  reaper.defer(watch)
end

if reaper.set_action_options then
  reaper.set_action_options(1 + 4) -- auto-terminate previous instance, sync toolbar
end
if WANT_DEBUG then reaper.ClearConsole() end
setToggle(true)
Log("=== Click-select-track watcher started (" .. (SELECT_ON_MOUSE_UP and "mouse-up" or "mouse-down") .. ") ===")

reaper.atexit(function()
  if reaper.set_action_options then
    reaper.set_action_options(8)
  end
  setToggle(false)
  Log("🧹 exit cleanup")
end)

watch()
