--[[
@description hsuanice_Track and Razor Item Link like Pro Tools
@version 0.3.4
@author hsuanice
@about
  Pro Tools–style Link Track and Edit Selection, where "Edit" = Razor Areas OR Item selection.

  Priority per track:
    - If a track has any track-level Razor Area → STRICT Razor ⇄ Track sync for that track (Item link disabled on that track).
    - If a track has NO Razor Area → Item ⇄ Track link is enabled, with Track→Item = removal only.

  Global behavior:
    - Razor exists → STRICT Razor→Track mirror and Track→Razor apply/clear (union template).
    - No Razor → item-based linking only.
    - Track-level Razor only; envelope-lane razors preserved but ignored.
    - Coexists with your Razor↔Item watcher; this script never auto-selects items.

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

  Reference:
    Script: X_Raym_Ugurcan Orcun_Toggle Mouse Click for track selection in preference.lua

@changelog
  v0.3.4 - On toggle ON: run an immediate initial sync with Razor priority:
           • If any track-level Razor exists → mirror Razor→Track right away.
           • Else if items are selected → mirror Item→Track right away.
           (Turning OFF does not clear Razor or item selection.)
  v0.3.3 - Metadata + preference toggle scaffold.
  v0.3.2 - Refine item⇄track linking: only active when items are selected; Track→Item is removal-only.
]]


-- Toolbar toggle
if reaper.set_action_options then reaper.set_action_options(1 | 4) end
reaper.atexit(function() if reaper.set_action_options then reaper.set_action_options(8) end end)

-- === Preference: Arrange click selects track (enable while running; restore on exit) ===
-- Uses SWS: SNM_GetIntConfigVar / SNM_SetIntConfigVar with key 'trackselonmouse' (1=ON, 0=OFF).
-- We force it ON while the script runs, and restore the original value on exit.
do
  local HAS_SWS = reaper.APIExists and reaper.APIExists("SNM_GetIntConfigVar")
  if HAS_SWS then
    local orig = reaper.SNM_GetIntConfigVar("trackselonmouse", -1) -- current value
    if orig ~= 1 then reaper.SNM_SetIntConfigVar("trackselonmouse", 1) end
    reaper.atexit(function()
      if orig ~= -1 then reaper.SNM_SetIntConfigVar("trackselonmouse", orig) end
    end)
  else
    -- SWS not installed: cannot toggle the preference programmatically.
    -- The script still runs; consider installing SWS for full integration.
  end
end


-- === Initial sync on activation (Razor priority) ===
-- When the script turns ON, immediately mirror the current state:
--   • If any track-level Razor exists: mirror Razor → Track right away.
--   • Else if items are selected: mirror Item → Track right away.
-- Turning the script OFF does NOT clear Razor or item selections.
do
  local function track_has_tracklevel_razor(tr)
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if not ok or s == "" then return false end
    for a,b,g in s:gmatch("(%S+)%s+(%S+)%s+(%S+)") do
      if g == "\"\"" then return true end -- GUID=="" means track-level Razor
    end
    return false
  end

  local function any_track_has_razor()
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      if track_has_tracklevel_razor(reaper.GetTrack(0,i)) then return true end
    end
    return false
  end

  local function any_item_selected()
    local icnt = reaper.CountMediaItems(0)
    for i = 0, icnt-1 do
      local it = reaper.GetMediaItem(0,i)
      if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then return true end
    end
    return false
  end

  reaper.PreventUIRefresh(1)

  if any_track_has_razor() then
    -- Razor → Track mirror now (select tracks that have a track-level Razor)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      reaper.SetTrackSelected(tr, track_has_tracklevel_razor(tr))
    end

  elseif any_item_selected() then
    -- Item → Track mirror now (select tracks that contain any selected item)
    -- This does not modify items; your regular logic will handle Track→Item later as needed.
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local has_sel = false
      local ic = reaper.CountTrackMediaItems(tr)
      for j = 0, ic-1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then has_sel = true break end
      end
      reaper.SetTrackSelected(tr, has_sel)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end


-- === Initial sync on activation (Razor priority) ===
-- When the script turns ON, immediately mirror the current state:
--   • If any track-level Razor exists: mirror Razor → Track right away.
--   • Else if items are selected: mirror Item → Track right away.
-- Turning the script OFF does NOT clear Razor or item selections.
do
  local function track_has_tracklevel_razor(tr)
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if not ok or s == "" then return false end
    for a,b,g in s:gmatch("(%S+)%s+(%S+)%s+(%S+)") do
      if g == "\"\"" then return true end -- GUID=="" means track-level Razor
    end
    return false
  end

  local function any_track_has_razor()
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      if track_has_tracklevel_razor(reaper.GetTrack(0,i)) then return true end
    end
    return false
  end

  local function any_item_selected()
    local icnt = reaper.CountMediaItems(0)
    for i = 0, icnt-1 do
      local it = reaper.GetMediaItem(0,i)
      if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then return true end
    end
    return false
  end

  reaper.PreventUIRefresh(1)

  if any_track_has_razor() then
    -- Razor → Track mirror now (select tracks that have a track-level Razor)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      reaper.SetTrackSelected(tr, track_has_tracklevel_razor(tr))
    end

  elseif any_item_selected() then
    -- Item → Track mirror now (select tracks that contain any selected item)
    -- This does not modify items; your regular logic will handle Track→Item later as needed.
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt-1 do
      local tr = reaper.GetTrack(0,i)
      local has_sel = false
      local ic = reaper.CountTrackMediaItems(tr)
      for j = 0, ic-1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then has_sel = true break end
      end
      reaper.SetTrackSelected(tr, has_sel)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end








-- ---------- Helpers ----------
local function track_selected(tr) return (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5 end
local function set_track_selected(tr, sel) reaper.SetTrackSelected(tr, sel and true or false) end
local function track_guid(tr) return reaper.GetTrackGUID(tr) end

local function parse_triplets(s)
  local out = {}
  if not s or s == "" then return out end
  local toks = {}
  for w in s:gmatch("%S+") do toks[#toks+1] = w end
  for i = 1, #toks, 3 do
    local a = tonumber(toks[i]); local b = tonumber(toks[i+1]); local g = toks[i+2] or "\"\""
    if a and b and b > a then out[#out+1] = {a, b, g} end
  end
  return out
end

local function get_track_level_ranges(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok then return {} end
  local out = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] == "\"\"" then out[#out+1] = {t[1], t[2]} end
  end
  return out
end

local function track_has_razor(tr) return #get_track_level_ranges(tr) > 0 end

local function any_razor_exists()
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    if track_has_razor(reaper.GetTrack(0, i)) then return true end
  end
  return false
end

local function set_track_level_ranges(tr, newRanges)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  s = (ok and s) and s or ""
  local keep = {}
  for _, t in ipairs(parse_triplets(s)) do
    if t[3] ~= "\"\"" then
      keep[#keep+1] = string.format("%.17f %.17f %s", t[1], t[2], t[3])
    end
  end
  for _, r in ipairs(newRanges) do
    keep[#keep+1] = string.format("%.17f %.17f \"\"", r[1], r[2])
  end
  reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", table.concat(keep, " "), true)
end

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

local function build_razor_sig()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local _, s = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i), "P_RAZOREDITS", "", false)
    t[#t+1] = s or ""
  end
  return table.concat(t, "|")
end

local function build_track_sel_sig()
  local t, tcnt = {}, reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    local tr = reaper.GetTrack(0, i)
    if track_selected(tr) then t[#t+1] = track_guid(tr) end
  end
  return table.concat(t, "|")
end

local function build_item_sel_sig()
  local parts, icnt = {}, reaper.CountMediaItems(0)
  for i = 0, icnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      parts[#parts+1] = g or tostring(it)
    end
  end
  return table.concat(parts, "|")
end

local function any_item_selected()
  local icnt = reaper.CountMediaItems(0)
  for i = 0, icnt - 1 do
    if reaper.GetMediaItemInfo_Value(reaper.GetMediaItem(0, i), "B_UISEL") == 1 then return true end
  end
  return false
end

local function clear_selected_items_on_track(tr)
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      reaper.SetMediaItemInfo_Value(it, "B_UISEL", 0)
    end
  end
end

local function track_has_any_selected_item(tr)
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    if reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(tr, i), "B_UISEL") == 1 then return true end
  end
  return false
end

-- ---------- Watcher ----------
local last_razor_sig = build_razor_sig()
local last_trk_sig   = build_track_sel_sig()
local last_item_sig  = build_item_sel_sig()

local function mainloop()
  local cur_razor_sig = build_razor_sig()
  local cur_trk_sig   = build_track_sel_sig()
  local cur_item_sig  = build_item_sel_sig()
  local hasRazor      = any_razor_exists()
  local hasItemSel    = (cur_item_sig ~= "")  -- quicker than scanning again

  -- 1) RAZOR -> TRACK (STRICT mirror) when any Razor exists
  if cur_razor_sig ~= last_razor_sig and hasRazor then
    last_razor_sig = cur_razor_sig
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      local want_sel = track_has_razor(tr)
      if want_sel ~= track_selected(tr) then set_track_selected(tr, want_sel) end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
    last_trk_sig = cur_trk_sig
  end

  -- 2) TRACK → RAZOR (STRICT) when any Razor exists
  if cur_trk_sig ~= last_trk_sig and hasRazor then
    local template = collect_union_ranges()
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if track_selected(tr) then
        set_track_level_ranges(tr, template)
      else
        set_track_level_ranges(tr, {})
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    last_trk_sig   = build_track_sel_sig()
    last_razor_sig = build_razor_sig()
  end

  -- 3) ITEM → TRACK (STRICT on NON-razor tracks). Always allowed (mirrors current item selection).
  if cur_item_sig ~= last_item_sig then
    last_item_sig = cur_item_sig
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if not track_has_razor(tr) then
        local want_sel = track_has_any_selected_item(tr)
        if want_sel ~= track_selected(tr) then set_track_selected(tr, want_sel) end
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
    last_trk_sig = cur_trk_sig
  end

  -- 4) TRACK → ITEM (REMOVAL ONLY, NON-razor tracks), and ONLY if there is item selection in the project
  if cur_trk_sig ~= last_trk_sig and not hasRazor and hasItemSel then
    last_trk_sig = cur_trk_sig
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if not track_has_razor(tr) and (not track_selected(tr)) then
        -- Deselect items on deselected tracks (do NOT add items on selected tracks)
        clear_selected_items_on_track(tr)
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    last_item_sig = build_item_sel_sig()
  end

  reaper.defer(mainloop)
end

mainloop()
