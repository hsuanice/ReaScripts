--[[
@description Hover Editing - Nudge Take Volume with Mousewheel (Pro Tools-style clip gain)
@version 26.1031.1544pre1
@author hsuanice
@noindex
@changelog
  - New: nudge the active take volume (clip gain) of the item under the mouse or the selected items with the mousewheel; shows the new value next to the mouse.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Mousewheel clip gain like Pro Tools. Assign this script to a mousewheel shortcut in the
  Action List (for example Shift+Cmd+Wheel). Wheel up = louder, wheel down = quieter.

  Targets:
    • Hover Mode ON, mouse over an item:
        - the item is selected     → all selected items
        - the item is not selected → only that item
    • Hover Mode ON, mouse not over an item → the selected items
    • Hover Mode OFF → the selected items

  Only items in the visible time range of the arrange view are changed. Locked items and
  empty takes are skipped. The polarity (a negative take volume) is kept.
  Continuous wheel steps are merged into one undo point, written when the wheel has been
  still for MERGE_SECONDS (REAPER 7.03+; older versions write one undo point per step).

  Hover Mode is set by "Hover Editing - Toggle Hover Mode".

  Library path:
    REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Hover.lua' }) do
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
-- USER OPTIONS
----------------------------------------
local STEP_DB      = 1.0    -- ← dB per wheel step (e.g. 0.5 or 0.1 for finer steps)
local MIN_DB       = -150   -- ← the volume does not go below this
local MAX_DB       = 24     -- ← the volume does not go above this
local SHOW_VALUE   = true   -- ← show the new value next to the mouse
local SHOW_SECONDS = 1.2    -- ← how long the value stays on screen
local MERGE_SECONDS = 1.0   -- ← wheel steps closer together than this share one undo point

----------------------------------------
-- Load shared Hover library
----------------------------------------
local LIB_PATH = reaper.GetResourcePath().."/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua"
local ok, hover = pcall(dofile, LIB_PATH)
if not ok or type(hover) ~= "table" then
  reaper.ShowMessageBox("Missing or invalid library:\n"..LIB_PATH, "hsuanice Hover Library", 0)
  return
end

-- A new wheel step restarts the script (ends the previous timer) instead of asking
local CAN_MERGE = reaper.set_action_options ~= nil
if CAN_MERGE then reaper.set_action_options(1 | 2) end

-- Running total of the current wheel burst (for the merged undo point's name)
local EXT_NS, EXT_KEY = "hsuanice_HoverWheelVol", "burst_db"

local _, _, _, _, _, _, val = reaper.get_action_context()
if not val or val == 0 then val = 1 end  -- run from the Action List: one step up
local step = (val > 0) and STEP_DB or -STEP_DB

----------------------------------------
-- Targets
----------------------------------------
local function selected_items()
  local list = {}
  for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
    list[#list + 1] = reaper.GetSelectedMediaItem(0, i)
  end
  return list
end

local function collect_targets()
  if hover.is_hover_enabled() then
    local it = hover.get_hover_item()
    if it and not reaper.IsMediaItemSelected(it) then return { it } end
  end
  return selected_items()
end

----------------------------------------
-- Volume
----------------------------------------
local function vol_to_db(v)
  if v <= 0 then return MIN_DB end
  return 20 * math.log(v, 10)
end

-- Returns the new dB value, or nil when the item was skipped
local function nudge(it)
  if reaper.GetMediaItemInfo_Value(it, "C_LOCK") & 1 == 1 then return nil end
  if not hover.is_item_visible(it) then return nil end
  local take = reaper.GetActiveTake(it)
  if not take then return nil end
  local vol  = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  local sign = (vol < 0) and -1 or 1
  local db   = math.max(MIN_DB, math.min(MAX_DB, vol_to_db(math.abs(vol)) + step))
  reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", sign * 10 ^ (db / 20))
  return db
end

local function fmt_db(db)
  if db <= MIN_DB then return "-inf dB" end
  return string.format("%+.1f dB", db)
end

----------------------------------------
-- Main
----------------------------------------
local targets = collect_targets()
if #targets == 0 then return end

local function apply()
  reaper.PreventUIRefresh(1)
  local count, last_db = 0, nil
  for _, it in ipairs(targets) do
    local db = nudge(it)
    if db then count, last_db = count + 1, db end
  end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  return count, last_db
end

local count, last_db, burst
if CAN_MERGE then
  -- No undo block here: a script that ends with defer gets no automatic undo point, so the
  -- merged point is written by the timer below once the wheel stops
  count, last_db = apply()
  if count == 0 then return end
  burst = (tonumber(reaper.GetExtState(EXT_NS, EXT_KEY)) or 0) + step
  reaper.SetExtState(EXT_NS, EXT_KEY, tostring(burst), false)
else
  reaper.Undo_BeginBlock()
  count, last_db = apply()
  reaper.Undo_EndBlock(string.format("Nudge take volume %+.1f dB", step), 4)
  if count == 0 then return end
end

local mx, my = reaper.GetMousePosition()
if SHOW_VALUE then
  local text = (count == 1) and ("Take vol: " .. fmt_db(last_db))
    or string.format("Take vol: %+.1f dB (%d items)", burst or step, count)
  reaper.TrackCtl_SetToolTip(text, mx + 18, my + 18, true)
end

if not CAN_MERGE then return end

-- A new wheel step restarts the script and both timers; the last step of a burst writes the
-- undo point (state before the burst -> state now) and clears the tooltip
local t0 = reaper.time_precise()
local undo_done, tip_done = false, not SHOW_VALUE
local function wait()
  local t = reaper.time_precise() - t0
  if not undo_done and t >= MERGE_SECONDS then
    undo_done = true
    reaper.SetExtState(EXT_NS, EXT_KEY, "0", false)
    reaper.Undo_OnStateChange2(0, string.format("Nudge take volume %+.1f dB", burst))
  end
  if not tip_done and t >= SHOW_SECONDS then
    tip_done = true
    reaper.TrackCtl_SetToolTip("", 0, 0, true)
  end
  if not (undo_done and tip_done) then reaper.defer(wait) end
end
reaper.defer(wait)
