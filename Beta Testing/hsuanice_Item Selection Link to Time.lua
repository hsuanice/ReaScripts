--[[
@description hsuanice_Item Selection and link to Time
@version 0.1.2 edit cursor follow time selection
@author hsuanice
@about
  Background watcher that mirrors current ITEM SELECTION to the TIME SELECTION:
    • When item selection changes, set time selection to [min(item.start) .. max(item.end)].
    • Pauses when any Razor Areas exist in the project (respect Razor).
    • Ultra lightweight, no UI, no lag.

  Conventions:
    • Auto-terminate previous instance on relaunch; keep toolbar toggle in sync (same pattern as Razor-Link).
    • Publishes a per-project enabled flag for interoperability if needed.

@changelog
  v0.1.2 - After linking, move edit cursor to the time selection start (still respecting Razor).
  v0.1.1 - Respect Razor Areas: if any Razor exists (track-level or fallback), do not link item → time.
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
  -- NEW in 0.1.2: move edit cursor to time selection start (no view scroll, no seek)
  reaper.SetEditCurPos(min_pos, false, false)
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

  local sig = selection_signature()
  if sig ~= last_sig then
    last_sig = sig
    reaper.PreventUIRefresh(1)
    apply_time_from_selection()
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
  end
  reaper.defer(mainloop)
end

mainloop()
