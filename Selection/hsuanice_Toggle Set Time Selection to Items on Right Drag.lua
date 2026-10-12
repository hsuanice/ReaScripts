--[[
@description Toggle Set Time Selection to Items on Right Drag - time selection follows the selected items after a right-button drag
@version 26.1012.1641
@author hsuanice
@changelog
  - Renamed to "Toggle Set Time Selection to Items on Right Drag" (was "Set Time to Item Selection Mouse Right-Drag Release") as part of the 2026-10-12 naming clean-up.
  - Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.
@about
  Toggle (background watcher). After a right-button DRAG, on the frame the button is released
  (optionally one frame later) the time selection is set to the earliest start / latest end of
  the currently selected items.
  Optimized for large projects: a single pass over the selected items on release (no GUID table,
  no before/after diff), and an optional skip when the time selection would not change.
  Requires hsuanice_Mouse.lua (hsuanice Library) and the js_ReaScriptAPI extension.
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Mouse.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

----------------------------------------
-- User settings
----------------------------------------
local DEBUG                = false  -- true = print simple event logs to the Console
local ARRANGE_ONLY         = false  -- only react inside the Arrange view
local REQUIRE_RMB_DRAG     = true   -- trigger only after a real right-button drag (moved past the threshold); recommended true
local SNAPSHOT_DEFER_ONE_FRAME = false -- set true to wait one frame if a project's selection is not updated yet on the release frame
local DRAG_THRESHOLD_PX    = 4      -- pixel threshold that counts as a drag
local AVOID_REDUNDANT_SET  = true   -- skip setting the time selection if it is (almost) unchanged
local LOOP_EPS             = 1e-6   -- tolerance for the comparison above (seconds)

----------------------------------------
-- Toggle helpers
----------------------------------------
local _, _, sectionID, cmdID = reaper.get_action_context()
local function set_toggle(state)
  reaper.SetToggleCommandState(sectionID, cmdID, state and 1 or 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
end
local function log(s) if DEBUG then reaper.ShowConsoleMsg("[RDragSetTime] "..s.."\n") end end

----------------------------------------
-- Mouse library loader (several candidate paths)
----------------------------------------
local function file_exists(p) local f=io.open(p,"r"); if f then f:close(); return true end end
local function load_mouse_lib()
  local R = reaper.GetResourcePath()
  local cands = {
    R.."/Scripts/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice Scripts/Library/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice scripts/Library/hsuanice_Mouse.lua",
    R.."/Scripts/hsuanice_Scripts/Library/hsuanice_Mouse.lua",
  }
  local info=debug.getinfo(1,"S"); local this_dir=(info and info.source or ""):match("^@(.+[\\/])")
  if this_dir then
    cands[#cands+1]=this_dir.."hsuanice_Mouse.lua"
    cands[#cands+1]=this_dir.."Library/hsuanice_Mouse.lua"
  end
  for _,p in ipairs(cands) do
    if file_exists(p) then local ok,lib=pcall(dofile,p); if ok and type(lib)=="table" and lib.new then return lib end end
  end
  reaper.ShowMessageBox("hsuanice_Mouse.lua was not found.","Missing library",0)
  return nil
end

----------------------------------------
-- Single pass: min start / max end of the selected items (O(#selected))
----------------------------------------
local function compute_bounds_of_selected_items()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return 0, 0.0, 0.0 end
  local min_pos = math.huge
  local max_end = -math.huge
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0,i)
    local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local L  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < min_pos then min_pos = p end
    local e = p + L
    if e > max_end then max_end = e end
  end
  return n, min_pos, max_end
end

-- Current time selection (used to avoid redundant sets)
local function get_time_sel()
  local st, en = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return st, en
end

local function set_time_if_needed(min_pos, max_end)
  if AVOID_REDUNDANT_SET then
    local old_s, old_e = get_time_sel()
    if math.abs(old_s - min_pos) <= LOOP_EPS and math.abs(old_e - max_end) <= LOOP_EPS then
      log(("[skip] unchanged time: %.6f → %.6f"):format(min_pos, max_end))
      return false
    end
  end
  -- set the time selection
  reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
  log(("[set] time %.6f → %.6f"):format(min_pos, max_end))
  return true
end

----------------------------------------
-- State
----------------------------------------
local running = false
local mouse = nil

-- right-button drag tracking
local rmb_down = false
local rmb_down_x, rmb_down_y = 0, 0
local rmb_dragged = false

local arm_post_release = false -- for the one-frame-delay option

----------------------------------------
-- Main
----------------------------------------
local function main()
  if not running then return end

  local ev = mouse:tick()

  -- Arrange view only (optional)
  if ARRANGE_ONLY and not ev.blocked then
    local hit = mouse:hit()
    if not (hit and hit.in_arrange) then
      return reaper.defer(main)
    end
  end

  -- track right-button press / drag
  if mouse.rmb and not rmb_down then
    rmb_down = true
    rmb_dragged = false
    rmb_down_x, rmb_down_y = reaper.GetMousePosition()
  elseif mouse.rmb and rmb_down then
    if REQUIRE_RMB_DRAG and not rmb_dragged then
      local x,y = reaper.GetMousePosition()
      if (math.abs(x - rmb_down_x) >= DRAG_THRESHOLD_PX) or (math.abs(y - rmb_down_y) >= DRAG_THRESHOLD_PX) then
        rmb_dragged = true
      end
    end
  end

  -- right button released on this frame
  local released_now = (rmb_down and not mouse.rmb and not ev.blocked)
  if released_now then
    rmb_down = false
    -- if a drag is required, ignore a plain click
    if REQUIRE_RMB_DRAG and not rmb_dragged then
      log("[ignore] RMB click w/o drag")
    else
      if SNAPSHOT_DEFER_ONE_FRAME then
        arm_post_release = true
      else
        local cnt, s, e = compute_bounds_of_selected_items()
        if cnt > 0 then set_time_if_needed(s, e) end
      end
    end
  elseif arm_post_release then
    -- one-frame-delay variant (rarely needed)
    local cnt, s, e = compute_bounds_of_selected_items()
    if cnt > 0 then set_time_if_needed(s, e) end
    arm_post_release = false
  end

  reaper.defer(main)
end

----------------------------------------
-- Toggle (true two-state)
----------------------------------------
local is_on = (reaper.GetToggleCommandStateEx(sectionID, cmdID) == 1)
if is_on then
  running = false
  set_toggle(false)
  log("[state] disabled")
  return
else
  local MouseLib = load_mouse_lib(); if not MouseLib then set_toggle(false); return end
  mouse = MouseLib.new{
    debug=false,
    -- zero buffering: react on release immediately (skips the mouse lib's menu / focus grace periods)
    menu_grace=0.0,
    rmb_cooldown=0.0,
    focus_grace=0.0,
    require_fresh_lmb=false,
    drag_threshold_px = DRAG_THRESHOLD_PX,
  }
  if DEBUG then reaper.ShowConsoleMsg("") end
  running = true
  set_toggle(true)
  log("[state] enabled")
  main()
  reaper.atexit(function() set_toggle(false) end)
end
