--[[
@description hsuanice_Item Selection and link to Time
@version 0.1.0
@author hsuanice
@about
  Background watcher that mirrors current ITEM SELECTION to the TIME SELECTION:
    • When item selection changes, set time selection to [min(item.start) .. max(item.end)].
    • Does nothing when selection unchanged — ultra lightweight, no UI, no lag.
  Conventions:
    • Auto-terminate previous instance on relaunch; keep toolbar toggle in sync (same pattern as Razor-Link).
    • Publishes a per-project enabled flag for interoperability if needed.

@changelog
  v0.1.0 - Initial release. Ultra-light item→time selection link with state-change gating and toolbar sync.
]]

-------------------- USER OPTIONS --------------------
-- If true, clear time selection when no items are selected; otherwise keep previous range.
local CLEAR_WHEN_EMPTY = false

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

-- Build a tiny signature for current item selection to detect changes cheaply.
local function selection_signature()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return "0|" end
  -- For cheap and stable sig: count + first/last item's pos/end (sorted by position)
  local items = {}
  items[#items+1] = n
  -- sample up to a few items to avoid O(N log N) sort on huge sets
  local min_pos, max_end = math.huge, -math.huge
  for i = 0, n-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos < min_pos then min_pos = pos end
    local iend = pos + len
    if iend > max_end then max_end = iend end
  end
  items[#items+1] = string.format("%.12f", min_pos)
  items[#items+1] = string.format("%.12f", max_end)
  return table.concat(items, "|")
end

-- Apply time selection from current item selection.
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

  if min_pos < (max_end - EPS) then
    reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
  end
end

-- Gated main loop: only run when project state or selection sig changes.
local last_psc = -1
local last_sig = ""

local function mainloop()
  local psc = reaper.GetProjectStateChangeCount(0)  -- cheap global change counter
  local sig = selection_signature()

  if psc ~= last_psc or sig ~= last_sig then
    -- Update only when something relevant changed.
    last_psc = psc
    if sig ~= last_sig then
      last_sig = sig
      apply_time_from_selection()
    end
  end

  reaper.defer(mainloop)
end

mainloop()

