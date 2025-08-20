--[[
@description hsuanice_Track link for Razor Selection only (Toggle, Lightweight)
@version 1.0.0
@author hsuanice
@about
  Focuses only on arrangement Razor Areas to synchronize track selection state.
  Does not process item selection or any item-related logic.
  No reverse operation (track selection does not affect Razor).
  Extremely lightweight and optimized for large projects.
  Supports Toggle, suitable for Toolbar.
]]

reaper.SetExtState("hsuanice_tracklink", "enabled", "1", true)

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
  -- Set ExtState OFF at script exit (tracklink disabled)
  reaper.SetExtState("hsuanice_tracklink", "enabled", "0", true)
end)

----------------------
-- Utility: Check if track has Razor Area
local function track_has_razor(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok or not s or s == "" then return false end
  for a, b, g in s:gmatch("(%S+) (%S+) (%S+)") do
    if g == "\"\"" then return true end -- Only check track-level Razor
  end
  return false
end

----------------------
-- Razor signature (concatenate all tracks' Razor contents)
local function build_razor_sig()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local ok, s = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_RAZOREDITS", "", false)
    t[#t+1] = s or ""
  end
  return table.concat(t, "|")
end

----------------------
-- Main Loop
local last_razor_sig = build_razor_sig()

local function mainloop()
  local cur_razor_sig = build_razor_sig()
  local tcnt = reaper.CountTracks(0)

  -- Only update track selection when Razor signature changes
  if cur_razor_sig ~= last_razor_sig then
    reaper.PreventUIRefresh(1)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      local want = track_has_razor(tr)
      if (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5 ~= want then
        reaper.SetTrackSelected(tr, want)
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
  end

  last_razor_sig = cur_razor_sig
  reaper.defer(mainloop)
end

mainloop()
