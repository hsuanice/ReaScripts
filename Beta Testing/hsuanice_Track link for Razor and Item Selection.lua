--[[
@description hsuanice_Track link for Razor and Item Selection (Toggle, Lightweight)
@version 1.1.0
@author hsuanice
@about
  Synchronizes track selection with Razor Area selection and Item selection (Razor priority).
  If any track has a Razor Area, only Razor Areas link track selection.
  If no Razor Areas, item selection links track selection (tracks with selected items are selected).
  Track selection never affects Razor or item selection (one-way link).
  Extremely lightweight and optimized for large projects.
  Supports Toggle, suitable for Toolbar.

  Note:
    This script was generated using ChatGPT and Copilot based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v1.1.0 - Support item selection link track (when no Razor), Razor priority, removed ExtState, English comments.
]]

----------------------
-- Toolbar Toggle Support
if reaper.set_action_options then
  -- 1: Auto-terminate previous instance
  -- 4: Toolbar button ON
  reaper.set_action_options(1 | 4)
end
reaper.atexit(function()
  if reaper.set_action_options then
    -- 8: Toolbar button OFF
    reaper.set_action_options(8)
  end
end)

----------------------
-- Utility: Check if track has Razor Area
local function track_has_razor(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok or not s or s == "" then return false end
  for a, b, g in s:gmatch("(%S+) (%S+) (%S+)") do
    if g == "\"\"" then return true end -- Only track-level Razor
  end
  return false
end

----------------------
-- Utility: Check if track has selected item
local function track_has_selected_item(tr)
  local icnt = reaper.CountMediaItems(0)
  for i = 0, icnt - 1 do
    local item = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(item, "B_UISEL") == 1 then
      local item_tr = reaper.GetMediaItem_Track(item)
      if item_tr == tr then return true end
    end
  end
  return false
end

----------------------
-- Razor signature (all tracks Razor content concatenated)
local function build_razor_sig()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local ok, s = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_RAZOREDITS", "", false)
    t[#t+1] = s or ""
  end
  return table.concat(t, "|")
end

----------------------
-- Item signature (all tracks item selection info concatenated)
local function build_item_sig()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    t[#t+1] = track_has_selected_item(tr) and "1" or "0"
  end
  return table.concat(t, "")
end

----------------------
-- Main Loop: Razor priority, fallback to item selection
local last_razor_sig = build_razor_sig()
local last_item_sig  = build_item_sig()

local function has_any_razor()
  for i = 0, reaper.CountTracks(0) - 1 do
    if track_has_razor(reaper.GetTrack(0, i)) then return true end
  end
  return false
end

local function mainloop()
  local cur_razor_sig = build_razor_sig()
  local cur_item_sig  = build_item_sig()
  local tcnt = reaper.CountTracks(0)
  local razor_exists = has_any_razor()

  -- Only update track selection when Razor or item selection signature changes
  if cur_razor_sig ~= last_razor_sig or cur_item_sig ~= last_item_sig then
    reaper.PreventUIRefresh(1)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      local want = false
      if razor_exists then
        want = track_has_razor(tr)
      else
        want = track_has_selected_item(tr)
      end
      if (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5 ~= want then
        reaper.SetTrackSelected(tr, want)
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
  end

  last_razor_sig = cur_razor_sig
  last_item_sig  = cur_item_sig
  reaper.defer(mainloop)
end

mainloop()
