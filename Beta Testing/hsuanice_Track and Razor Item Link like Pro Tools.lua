--[[
@description hsuanice_Track and Razor Item Link like Pro Tools
@version 0.4.6
@author hsuanice
@about
  Pro Tools–style "Link Track and Edit Selection", where Edit = Razor Areas OR Item selection.

  Per-track priority:
    - If a track has any TRACK-LEVEL Razor Area → STRICT Razor ⇄ Track sync for that track (Item link disabled on that track).
    - If a track has NO Razor Area → Item ⇄ Track link with an ephemeral Edit Range:
        • When items are selected, remember [leftmost item start, rightmost item end] as the Edit Range.
        • While that Edit Range is valid, selecting/deselecting tracks will add/remove selection ONLY
          for items that match the range on those tracks (rule configurable via RANGE_MODE).
        • The Edit Range is invalidated by other edit actions: moving the Edit Cursor, or changing the Time Selection.

  Global behavior:
    - If any Razor exists → STRICT Razor→Track mirror and Track→Razor apply/clear (union template).
    - If no Razor exists → item-based linking with the ephemeral Edit Range as above.

  Notes:
    - TRACK-LEVEL Razor only (GUID == ""); envelope-lane razors are preserved but ignored for linking.
    - Coexists with your Razor↔Item watcher; this script never auto-selects all items.
    - Toolbar-friendly background watcher (auto-terminate previous instance, toggle sync).

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.4.6 - Removed all Time Selection related logic. Edit Range now relies only on item selection or Razor Area range.
           Script exclusively links Razor, Item, and Track without any dependency on Time Selection.
  v0.4.5 - Removed debug console; tidied syntax; kept RANGE_MODE (1=overlap, 2=contain/PT) user option.
]]

-------------------------
-- === USER OPTIONS === --
-------------------------
-- RANGE_MODE:
--   1 = overlap : item is selected if it intersects the remembered Edit Range at all
--   2 = contain : item must be fully inside the Edit Range (Pro Tools mode)
local RANGE_MODE = 2

---------------------------------------
-- Toolbar auto-terminate + toggle sync
---------------------------------------
if reaper.set_action_options then
  -- 1: auto-terminate previous instance on restart
  -- 4: set toggle ON for toolbar button
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
local function track_selected(tr)
  return (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5
end

local function set_track_selected(tr, sel)
  reaper.SetTrackSelected(tr, sel and true or false)
end

local function track_guid(tr) return reaper.GetTrackGUID(tr) end

-- Parse P_RAZOREDITS into triplets {start, end, guid_str}
local function parse_triplets(s)
  local out = {}
  if not s or s == "" then return out end
  local toks = {}
  for w in s:gmatch("%S+") do
    toks[#toks+1] = w
  end
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

local function track_has_razor(tr)
  return #get_track_level_ranges(tr) > 0
end

local function any_razor_exists()
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt - 1 do
    if track_has_razor(reaper.GetTrack(0, i)) then
      return true
    end
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
      if not set[key] then
        set[key] = true
        out[#out+1] = {r[1], r[2]}
      end
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
    if track_selected(tr) then
      t[#t+1] = track_guid(tr)
    end
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

-- Item utils (range-based)
local function item_bounds(it)
  local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  return pos, pos + len
end

-- Range match: RANGE_MODE 1=overlap, 2=contain (PT)
local EPS = 1e-9
local function item_matches_range(s, e, rs, re_)
  if RANGE_MODE == 1 then
    return (e > rs + EPS) and (s < re_ - EPS)        -- overlap
  else
    return (s >= rs - EPS) and (e <= re_ + EPS)      -- contain (PT)
  end
end

local function track_select_items_matching_range(tr, rs, re_, sel)
  local changed = false
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local s, e = item_bounds(it)
    if item_matches_range(s, e, rs, re_) then
      local cur = reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1
      if sel and (not cur) then
        reaper.SetMediaItemInfo_Value(it, "B_UISEL", 1)
        changed = true
      elseif (not sel) and cur then
        reaper.SetMediaItemInfo_Value(it, "B_UISEL", 0)
        changed = true
      end
    end
  end
  return changed
end

local function track_has_any_selected_item(tr)
  local icnt = reaper.CountTrackMediaItems(tr)
  for i = 0, icnt - 1 do
    if reaper.GetMediaItemInfo_Value(reaper.GetTrackMediaItem(tr, i), "B_UISEL") == 1 then
      return true
    end
  end
  return false
end

-------------------------------
-- Ephemeral Edit Range memory
-------------------------------
local edit_range_active = false
local edit_range_start, edit_range_end = 0.0, 0.0
local cursor_at_capture = reaper.GetCursorPosition()

local function capture_edit_range_from_items()
  local icnt = reaper.CountMediaItems(0)
  local have = false
  local min_s, max_e = math.huge, -math.huge
  for i = 0, icnt - 1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      have = true
      local s, e = item_bounds(it)
      if s < min_s then min_s = s end
      if e > max_e then max_e = e end
    end
  end
  if have and max_e > min_s then
    edit_range_active = true
    edit_range_start, edit_range_end = min_s, max_e
    cursor_at_capture = reaper.GetCursorPosition()
  end
end

local function invalidate_edit_range_if_edited()
  if not edit_range_active then return end
  local cur_cur = reaper.GetCursorPosition()
  if cur_cur ~= cursor_at_capture or cur_ts_s ~= ts_s_at_capture or cur_ts_e ~= ts_e_at_capture then
    edit_range_active = false
  end
end

----------------
-- Main watcher
----------------
local last_razor_sig = build_razor_sig()
local last_trk_sig   = build_track_sel_sig()
local last_item_sig  = build_item_sel_sig()

local function mainloop()
  -- Snapshot previous signatures
  local prev_razor_sig = last_razor_sig
  local prev_trk_sig   = last_trk_sig
  local prev_item_sig  = last_item_sig

  -- Read current signatures
  local cur_razor_sig = build_razor_sig()
  local cur_trk_sig   = build_track_sel_sig()
  local cur_item_sig  = build_item_sel_sig()
  local hasRazor      = any_razor_exists()

  -- Maintain/Edit Range memory
  if cur_item_sig ~= prev_item_sig and cur_item_sig ~= "" then
    capture_edit_range_from_items()
  end
  invalidate_edit_range_if_edited()

  -- 1) RAZOR -> TRACK (STRICT) when any Razor exists
  if cur_razor_sig ~= prev_razor_sig and hasRazor then
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      local want_sel = track_has_razor(tr)
      if want_sel ~= track_selected(tr) then
        set_track_selected(tr, want_sel)
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
  end

  -- 2) TRACK -> RAZOR (STRICT) when any Razor exists
  if cur_trk_sig ~= prev_trk_sig and hasRazor then
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
    cur_razor_sig = build_razor_sig()
  end

  -- 3) ITEM -> TRACK (STRICT, non-Razor tracks) — mirror selected items to track selection
  if cur_item_sig ~= prev_item_sig and cur_item_sig ~= "" then
    reaper.PreventUIRefresh(1)
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if not track_has_razor(tr) then
        local want_sel = track_has_any_selected_item(tr)
        if want_sel ~= track_selected(tr) then
          set_track_selected(tr, want_sel)
        end
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_trk_sig = build_track_sel_sig()
  end

  -- 4) TRACK -> ITEM via Edit Range (non-Razor tracks), only while range is active
  if edit_range_active and cur_trk_sig ~= prev_trk_sig and not hasRazor then
    -- Build prev/current selected track sets
    local prev_set, cur_set = {}, {}
    for g in (prev_trk_sig or ""):gmatch("[^|]+") do
      prev_set[g] = true
    end
    local tcnt = reaper.CountTracks(0)
    for i = 0, tcnt - 1 do
      local tr = reaper.GetTrack(0, i)
      if track_selected(tr) then
        cur_set[track_guid(tr)] = tr
      end
    end

    reaper.PreventUIRefresh(1)
    -- Newly selected tracks → select items matching the remembered range
    for g, tr in pairs(cur_set) do
      if not prev_set[g] and not track_has_razor(tr) then
        track_select_items_matching_range(tr, edit_range_start, edit_range_end, true)
      end
    end
    -- Newly deselected tracks → deselect items matching the remembered range
    for g in pairs(prev_set) do
      if not cur_set[g] then
        for i = 0, tcnt - 1 do
          local tr = reaper.GetTrack(0, i)
          if track_guid(tr) == g and not track_has_razor(tr) then
            track_select_items_matching_range(tr, edit_range_start, edit_range_end, false)
            break
          end
        end
      end
    end
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    cur_item_sig = build_item_sel_sig()
  end

  -- Update "last_*" only at end of loop
  last_razor_sig = cur_razor_sig
  last_trk_sig   = cur_trk_sig
  last_item_sig  = cur_item_sig

  reaper.defer(mainloop)
end

mainloop()
