--[[
@description hsuanice_Razor Area and Item Link
@version 0.1
@author hsuanice
@about
  Single-button toggle. When ON, continuously add-select media items that overlap any Razor Area
  on the same track (partial or full overlap). When OFF, the watcher stops.
  - Coexists with Razor Areas (never modifies or hides them).
  - Add-only selection (does not clear existing item selection).
  - No "Task control" dialog: relaunching this action terminates the previous instance automatically
    and keeps the toolbar state in sync.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.1 - Beta release
]]

-------------------- Config --------------------
-- If you prefer hard sync (clear all selection, then select only fully-contained items), set true:
local STRICT_SYNC = false
------------------------------------------------

-- Auto-terminate previous instance on relaunch (no popup) and set toolbar ON
-- flags: 1 = auto-terminate on restart, 4 = set toggle ON
reaper.set_action_options(1 | 4)

-- Ensure toolbar toggles OFF on exit and clear internal enable flag
reaper.atexit(function()
  -- flag 8 = set toggle OFF
  reaper.set_action_options(8)
  reaper.SetExtState("hsuanice_RazorItemLink_ProTools", "enabled", "0", true)
end)

-- Mark as enabled for this run (for other tools if they need to read it)
reaper.SetExtState("hsuanice_RazorItemLink_ProTools", "enabled", "1", true)

-- Read all Razor Area time ranges for a given track.
-- Prefers P_RAZOREDITS_EXT; falls back to P_RAZOREDITS.
local function get_razor_ranges(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
  if not ok or not s or s == "" then
    ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if not ok or not s then s = "" end
  end
  local ranges = {}

  -- Primary parse for EXT: each set begins with "start end ..."
  for a, b in s:gmatch("([%d%.%-]+)%s+([%d%.%-]+)%s+") do
    a, b = tonumber(a), tonumber(b)
    if a and b and b > a then ranges[#ranges+1] = {a, b} end
  end

  -- Fallback: pairwise scan of all numeric tokens (start/end pairs)
  if #ranges == 0 then
    local nums = {}
    for n in s:gmatch("[-%d%.]+") do nums[#nums+1] = tonumber(n) end
    for i = 1, #nums-1, 2 do
      local a, b = nums[i], nums[i+1]
      if a and b and b > a then ranges[#ranges+1] = {a, b} end
    end
  end
  return ranges
end

-- Add-select items that are FULLY contained in any of the given ranges.
-- Full containment rule: itemStart >= rangeStart AND itemEnd <= rangeEnd.
local function select_items_fully_contained(tr, ranges)
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt-1 do
    local it   = reaper.GetTrackMediaItem(tr, i)
    local pos  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local iEnd = pos + len
    for _, r in ipairs(ranges) do
      if pos >= r[1] and iEnd <= r[2] then
        if reaper.GetMediaItemInfo_Value(it, "B_UISEL") ~= 1 then
          reaper.SetMediaItemInfo_Value(it, "B_UISEL", 1) -- add-select
        end
        break
      end
    end
  end
end

-- Build a signature of all tracks' Razor strings.
-- We only update selection when the signature changes to reduce work.
local function build_sig()
  local parts = {}
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt-1 do
    local tr = reaper.GetTrack(0, i)
    local _, s1 = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
    local _, s2 = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    parts[#parts+1] = s1 or ""
    parts[#parts+1] = s2 or ""
  end
  return table.concat(parts, "|")
end

local last_sig = ""

-- Main deferred loop: keeps the toolbar ON and updates selection when Razor Areas change.
local function mainloop()
  -- If the user presses the same toolbar button again, REAPER will auto-terminate
  -- this instance due to set_action_options(1), so we don't need to handle it manually.
  local sig = build_sig()
  if sig ~= last_sig then
    last_sig = sig
    reaper.PreventUIRefresh(1)

    if STRICT_SYNC then
      -- hard sync: start from a clean selection, then select fully-contained items only
      reaper.SelectAllMediaItems(0, false)
    end

    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      local tr = reaper.GetTrack(0, i)
      local ranges = get_razor_ranges(tr)
      if #ranges > 0 then
        select_items_fully_contained(tr, ranges)
      end
      -- Tracks without Razor Areas are left untouched (no deselection beyond optional STRICT_SYNC).
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
  end
  reaper.defer(mainloop)
end

mainloop()
