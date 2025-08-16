--[[
@description hsuanice_Track and Razor Link like Pro Tools
@version 0.2
@author hsuanice
@about
  Pro Tools–style STRICT two-way link between Razor Areas and Track Selection.
  - Track -> Razor: Selecting tracks applies the current global Razor template to selected tracks; deselecting tracks removes their Razor.
  - Razor -> Track: Tracks that have at least one track-level Razor become selected; tracks without any track-level Razor get deselected.
  - Template = union of all existing track-level Razor ranges across tracks.
  - Operates on track-level Razor only (GUID == ""), envelope-lane razors are ignored/preserved.
  - Does NOT touch item selection. Designed to coexist with your item-link scripts.

  Toolbar-friendly background watcher:
  - Auto-terminates previous instance on restart and syncs toolbar toggle.
  - No blocking task dialog.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.2 - Switch to STRICT sync (add & remove): deselecting a track now removes its Razor; removing a track's Razor now deselects that track.
  v0.1 - Beta release (add-only prototype)
]]

---------------------------------------
-- Toolbar auto-terminate + toggle sync
---------------------------------------
if reaper.set_action_options then
  -- 1: auto-terminate prev instance; 4: set toggle ON
  reaper.set_action_options(1 | 4)
end

reaper.atexit(function()
  if reaper.set_action_options then
    -- 8: set toggle OFF on exit
    reaper.set_action_options(8)
  end
end)

----------------
-- Small helpers
----------------
local function track_guid(tr) return reaper.GetTrackGUID(tr) end
local function track_selected(tr)
  return (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5
end

-- Parse P_RAZOREDITS into triplets {start, end, guid_str}
local function parse_triplets(s)
  local out = {}
  if not s or s == "" then return out end
  local toks = {}
  for w in s:gmatch("%S+") do toks[#toks+1] = w end
  for i = 1, #toks, 3 do
    local a = tonumber(toks[i])
    local b = tonumber(toks[i+1])
    local g = toks[i+2] or "\"\""
    if a and b and b > a then
      out[#out+1] = {a, b, g}
    end
  end
  return out
end

-- Get ONLY track-level ranges on a track (GUID == "")
local function get_track_level_ranges(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok then return {} end
  local out = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] == "\"\"" then
      out[#out+1] = {t[1], t[2]}
    end
  end
  return out
end

-- Does track have at least one track-level Razor?
local function has_track_level_razor(tr)
  return #get_track_level_ranges(tr) > 0
end

-- Set track-level ranges EXACTLY to newRanges; preserve any non-track-level triplets (envelopes)
local function set_track_level_ranges(tr, newRanges)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  s = (ok and s) and s or ""
  local keep = {}
  -- keep all non-track-level triplets as-is
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] ~= "\"\"" then
      keep[#keep+1] = string.format("%.17f %.17f %s", t[1], t[2], t[3])
    end
  end
  -- append track-level new ranges
  for _, r in ipairs(newRanges) do
    keep[#keep+1] = string.format("%.17f %.17f \"\"", r[1], r[2])
  end
  local newstr = table.concat(keep, " ")
  reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", newstr, true)
end

-- Collect the UNION (dedup exact pairs) of all track-level ranges across project
local function collect_union_ranges()
  local tcnt = reaper.CountTracks(0)
  local set, out = {}, {}
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    for _, r in ipairs(get_track_level_ranges(tr)) do
      local key = string.format("%.17f|%.17f", r[1], r[2])
      if not set[key] then set[key] = true; out[#out+1] = {r[1], r[2]} end
    end
  end
  return out
end

-- Signatures to detect changes
local function build_razor_sig()
  local t = {}
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    t[#t+1] = s or ""
  end
  return table.concat(t, "|")
end

local function build_sel_sig()
  local t = {}
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    if track_selected(tr) then t[#t+1] = track_guid(tr) end
  end
  return table.concat(t, "|")
end

---------------
-- Main watcher
---------------
local last_razor_sig = build_razor_sig()
local last_sel_sig   = build_sel_sig()

local function mainloop()
  local need_update = false

  -- Read current signatures
  local cur_razor_sig = build_razor_sig()
  local cur_sel_sig   = build_sel_sig()

  ------------------------------------------
  -- RAZOR -> TRACK (strict): sync selection
  ------------------------------------------
  if cur_razor_sig ~= last_razor_sig then
    last_razor_sig = cur_razor_sig
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      local should_select = has_track_level_razor(tr)
      if should_select and not track_selected(tr) then
        reaper.SetTrackSelected(tr, true)
        need_update = true
      elseif (not should_select) and track_selected(tr) then
        reaper.SetTrackSelected(tr, false)
        need_update = true
      end
    end
    reaper.PreventUIRefresh(-1)
    if need_update then
      reaper.UpdateArrange()
      cur_sel_sig = build_sel_sig()
      last_sel_sig = cur_sel_sig
    end
  end

  ---------------------------------------------------
  -- TRACK -> RAZOR (strict): apply/remove exact set
  ---------------------------------------------------
  if cur_sel_sig ~= last_sel_sig then
    -- Identify selected set and apply template; clear on deselected
    local template = collect_union_ranges() -- may be empty; that's fine
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if track_selected(tr) then
        -- Selected: set to template exactly (strict)
        set_track_level_ranges(tr, template)
      else
        -- Deselected: remove all track-level Razor
        set_track_level_ranges(tr, {})
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    last_sel_sig   = build_sel_sig()
    last_razor_sig = build_razor_sig()
  end

  reaper.defer(mainloop)
end

mainloop()

