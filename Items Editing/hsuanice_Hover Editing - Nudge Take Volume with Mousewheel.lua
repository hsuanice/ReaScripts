--[[
@description Hover Editing - Nudge Take Volume with Mousewheel (Pro Tools-style clip gain)
@version 26.1031.1833pre1
@author hsuanice
@noindex
@changelog
  - New: nudge the active take volume (clip gain) of the item under the mouse or the selected items with the mousewheel; shows the new value next to the mouse.
  - Fix: wheel down after wheel up no longer keeps going up (each step is a fresh launch; undo merge and value display moved to a background timer)
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

  This script ends right after each step, so every wheel step is a fresh launch that carries
  its own direction (a script relaunched while still running gets no wheel value). The undo
  point and the value display are timed by "Hover Editing - Nudge Take Volume Timer", which
  runs in the background only while needed.

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
local STEP_DB       = 1.0   -- ← dB per wheel step (e.g. 0.5 or 0.1 for finer steps)
local MIN_DB        = -150  -- ← the volume does not go below this
local MAX_DB        = 24    -- ← the volume does not go above this
local SHOW_VALUE    = true  -- ← show the new value next to the mouse
local SHOW_SECONDS  = 1.2   -- ← how long the value stays on screen
local MERGE_SECONDS = 1.0   -- ← wheel steps closer together than this share one undo point
local DEBUG         = false -- ← print the mousewheel values to the ReaScript console

----------------------------------------
-- Load shared Hover library
----------------------------------------
local LIB_PATH = reaper.GetResourcePath().."/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua"
local ok, hover = pcall(dofile, LIB_PATH)
if not ok or type(hover) ~= "table" then
  reaper.ShowMessageBox("Missing or invalid library:\n"..LIB_PATH, "hsuanice Hover Library", 0)
  return
end

-- Shared with the Timer script
local NS = "hsuanice_HoverWheelVol"
local function ext_num(k) return tonumber(reaper.GetExtState(NS, k)) end
local function ext_set(k, v) reaper.SetExtState(NS, k, tostring(v), false) end

local TIMER_PATH = reaper.GetResourcePath()
  .. "/Scripts/hsuanice Scripts/Items Editing/hsuanice_Hover Editing - Nudge Take Volume Timer.lua"
local CAN_MERGE = reaper.set_action_options ~= nil and reaper.file_exists(TIMER_PATH)
-- Two steps less than one defer cycle apart would ask "already running": restart instead
if CAN_MERGE then reaper.set_action_options(1 | 2) end

----------------------------------------
-- Direction
----------------------------------------
local now = reaper.time_precise()
local is_new, _, _, _, mode, res, val, ctx = reaper.get_action_context()
if DEBUG then
  reaper.ShowConsoleMsg(string.format("[Wheel] t=%.3f is_new=%s mode=%s res=%s val=%s ctx=%s\n",
    now, tostring(is_new), tostring(mode), tostring(res), tostring(val), tostring(ctx)))
end
local dir
if is_new and mode ~= -1 and val and val ~= 0 then
  dir = (val > 0) and 1 or -1
else
  -- No wheel value: a restart during a fast burst keeps the burst's direction;
  -- run from the Action List = one step up
  local last_t = ext_num("last_time")
  dir = (last_t and now - last_t < MERGE_SECONDS) and (ext_num("last_dir") or 1) or 1
end
local step = dir * STEP_DB

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

local function apply(targets)
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

-- Start the Timer unless it is already running (it refreshes "alive" every defer cycle)
local function ensure_timer()
  local alive = ext_num("alive")
  if alive and now - alive < 0.5 then return end
  local cmd = ext_num("timer_cmd")
  if not cmd or cmd == 0 then
    cmd = reaper.AddRemoveReaScript(true, 0, TIMER_PATH, true)
    ext_set("timer_cmd", cmd)
  end
  if cmd and cmd ~= 0 then reaper.Main_OnCommand(cmd, 0) end
end

----------------------------------------
-- Main
----------------------------------------
local targets = collect_targets()
if #targets == 0 then return end

local count, last_db, burst
if CAN_MERGE then
  -- No undo block: a script that ends with defer gets no automatic undo point; the Timer
  -- writes one merged point once the wheel stops
  count, last_db = apply(targets)
  if count == 0 then return end
  burst = (ext_num("burst_db") or 0) + step
  ext_set("burst_db", burst)
  ext_set("last_time", now)
  ext_set("last_dir", dir)
  ext_set("merge_s", MERGE_SECONDS)
else
  reaper.Undo_BeginBlock()
  count, last_db = apply(targets)
  reaper.Undo_EndBlock(string.format("Nudge take volume %+.1f dB", step), 4)
  if count == 0 then return end
end

if SHOW_VALUE then
  local text = (count == 1) and ("Take vol: " .. fmt_db(last_db))
    or string.format("Take vol: %+.1f dB (%d items)", burst or step, count)
  local mx, my = reaper.GetMousePosition()
  reaper.TrackCtl_SetToolTip(text, mx + 18, my + 18, true)
  if CAN_MERGE then ext_set("tip_until", now + SHOW_SECONDS) end
end

if CAN_MERGE then
  ensure_timer()
  reaper.defer(function() end)
end
