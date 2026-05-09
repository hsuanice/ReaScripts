--[[
@description hsuanice_Razor and Item Link with Mode switch to Overlap or Contain like Pro Tools
@version 0.3.0 [260509.1108]
@author hsuanice
@about
  Single-button toggle watcher that add-selects media items on each track according to that track's
  TRACK-LEVEL Razor Areas (GUID == ""). Envelope-lane razors are preserved but ignored for matching.

  MODE (user option inside the script):
    • RANGE_MODE = 1 → Overlap : item is selected if it INTERSECTS any Razor range
    • RANGE_MODE = 2 → Contain : item is selected only if it is FULLY inside a Razor range
                                 (INCLUSIVE with tiny EPS tolerance, so equal-length is selected; Pro Tools-like)

  Behavior:
    • Add-only selection (does not clear existing item selection unless STRICT_SYNC = true).
    • Does not modify Razor Areas; only reads them.
    • Relaunching terminates the previous instance and keeps a toolbar toggle in sync.

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  0.3.0 [260509.1108]
    - Track items previously selected by this script across iterations.
      When razor shrinks (Halve / Shrink Edit Selection / etc.) and an
      item that was razor-selected last tick no longer matches any
      razor on its track, it is now deselected. Manually-selected items
      (those we never touched) remain untouched — selection sync is
      "remembered scope only", not strict global sync.
    - Existing STRICT_SYNC option is unchanged (still nukes everything
      for a hard sync if user prefers).
  v0.2.2 - Rename Project ExtState namespace for master toggle:
           • Namespace: "hsuanice_RazorItemLink", Key: "enabled" ("1"/"0")
           • Align with Track-Link script; no behavior change.
           Master toggle storage switched to Project ExtState (per-project, interoperable):
           • Namespace: "hsuanice_RazorItemLink", Key: "enabled" ("1"/"0")
           • Writes ON at launch, OFF on exit
           • Deprecates old global ExtState "hsuanice_RazorItemLink_ProTools"
           • No change to range logic; still add-only unless STRICT_SYNC = true
  v0.2.1 - Updated header/name, added explicit inclusive contain note and credits. No functional change.
]]


-------------------- USER OPTIONS --------------------
-- Range matching rule for selecting items against Razor Areas:
--   1 = overlap (select if item intersects any range)
--   2 = contain (select if item is fully inside a range; inclusive; Pro Tools mode)
local RANGE_MODE = 1

-- If you prefer hard sync (clear selection first, then select matches only), set true:
local STRICT_SYNC = false

-- Tolerance for floating-point comparisons (seconds)
local EPS = 1e-7
------------------------------------------------------

-- Auto-terminate previous instance on relaunch and set toolbar ON (flags: 1=auto-terminate, 4=toggle ON)
if reaper.set_action_options then reaper.set_action_options(1 | 4) end

-- Ensure toolbar toggles OFF on exit; also publish enabled=0 for compatibility
reaper.atexit(function()
  if reaper.set_action_options then reaper.set_action_options(8) end -- 8=toggle OFF
  reaper.SetProjExtState(0, "hsuanice_RazorItemLink", "enabled", "0")
end)

-- Mark as enabled for this run (legacy/compat)
reaper.SetProjExtState(0, "hsuanice_RazorItemLink", "enabled", "1")

-- Read all TRACK-LEVEL Razor ranges for a given track.
-- Prefer P_RAZOREDITS_EXT; fall back to P_RAZOREDITS.
local function get_tracklevel_razor_ranges(tr)
  -- Try EXT first
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
  if not ok or not s or s == "" then
    ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if not ok or not s then s = "" end
  end

  local ranges = {}

  -- Parse EXT triplets: start end "GUID"
  -- We only keep track-level segments where GUID == "" (i.e., quoted empty string).
  -- EXT format example: <start> <end> "" <start> <end> "ENVGUID" ...
  -- Grab triplets robustly:
  local toks = {}
  for token in s:gmatch("%S+") do toks[#toks+1] = token end
  for i = 1, #toks-2, 3 do
    local a = tonumber(toks[i])
    local b = tonumber(toks[i+1])
    local g = toks[i+2]
    if a and b and b > a and g then
      -- treat "" (exact two quotes) as track-level
      if g == '""' then
        ranges[#ranges+1] = {a, b}
      end
    end
  end

  -- Fallback parse: if nothing recognized as triplets, pairwise scan numbers
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

-- Decide whether `it` should be selected based on its track's `ranges`.
local function item_matches_ranges(it, ranges)
  if #ranges == 0 then return false end
  local pos  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local iEnd = pos + len
  for _, r in ipairs(ranges) do
    local rs, re_ = r[1], r[2]
    if RANGE_MODE == 1 then
      if (iEnd > rs + EPS) and (pos < re_ - EPS) then return true end
    else
      if (pos >= rs - EPS) and (iEnd <= re_ + EPS) then return true end
    end
  end
  return false
end

-- Add-select items on a track that match `ranges`. Mark them in `out_set`
-- so callers can later track which items belong to "razor-driven" selection.
local function select_items_by_ranges(tr, ranges, out_set)
  if #ranges == 0 then return end
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if item_matches_ranges(it, ranges) then
      if reaper.GetMediaItemInfo_Value(it, "B_UISEL") ~= 1 then
        reaper.SetMediaItemInfo_Value(it, "B_UISEL", 1)
      end
      if out_set then out_set[it] = true end
    end
  end
end

-- Build a signature of all tracks' Razor strings (EXT+fallback) to know when to update
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
-- Items we add-selected on the previous tick. Next tick, any item still
-- in this set but no longer matching its track's razor will be deselected.
-- Manually-selected items (never in this set) are never touched.
local prev_owned = {}

-- Main loop: update item selection when Razor Areas change
local function mainloop()
  local sig = build_sig()
  if sig ~= last_sig then
    last_sig = sig
    reaper.PreventUIRefresh(1)

    if STRICT_SYNC then
      reaper.SelectAllMediaItems(0, false)
    end

    local now_owned = {}

    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      local tr = reaper.GetTrack(0, i)
      local ranges = get_tracklevel_razor_ranges(tr)
      if #ranges > 0 then
        select_items_by_ranges(tr, ranges, now_owned)
      end
    end

    -- Deselect items we previously add-selected that no longer match
    -- their track's current razor (handles Halve / Shrink / razor cleared).
    for it in pairs(prev_owned) do
      if not now_owned[it] then
        if reaper.ValidatePtr(it, "MediaItem*") then
          reaper.SetMediaItemInfo_Value(it, "B_UISEL", 0)
        end
      end
    end

    prev_owned = now_owned

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
  end

  reaper.defer(mainloop)
end

mainloop()
