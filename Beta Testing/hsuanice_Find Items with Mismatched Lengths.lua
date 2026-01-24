--[[
@description Find Items with Mismatched Lengths at Same Timeline Position
@version 260124.1620
@author hsuanice

@about
  Finds items that start at the same timeline position but have different lengths.
  Useful for detecting TC embed errors in multi-channel recordings.

  Use case:
  - After splitting poly WAV to mono files
  - After phase alignment with Auto Align Post 2
  - When dual-recorder B-machine has TC offset issues

  The script will:
  1. Group items by their timeline start position
  2. Check if items in each group have different lengths
  3. Select all items with length mismatches
  4. Report findings in the console

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v260124.1620
    - Initial release
    - Groups items by timeline position (with tolerance)
    - Detects length mismatches within groups
    - Reports detailed information in console
]]

local R = reaper

-- Constants
local POS_TOLERANCE = 0.001 -- 1ms tolerance for grouping items at "same" position
local LEN_TOLERANCE = 0.001 -- 1ms tolerance for considering lengths "different"

-- Helper functions
local function msg(s) R.ShowConsoleMsg(tostring(s).."\n") end

local function format_time(sec)
  return R.format_timestr_pos(sec or 0, "", -1)
end

local function get_track_label(item)
  local tr = R.GetMediaItem_Track(item)
  if not tr then return "(no track)" end
  local _, name = R.GetTrackName(tr)
  local idx = R.CSurf_TrackToID(tr, false) or 0
  if not name or name == "" then
    return ("Track %d"):format(idx)
  end
  return ("Track %d: %s"):format(idx, name)
end

local function get_take_name(item)
  local take = R.GetActiveTake(item)
  if not take then return "(no take)" end
  return R.GetTakeName(take)
end

-- Group items by start position
local function group_items_by_position(items)
  local groups = {}

  for _, item in ipairs(items) do
    local pos = R.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = R.GetMediaItemInfo_Value(item, "D_LENGTH")

    -- Find existing group or create new one
    local found_group = false
    for _, group in ipairs(groups) do
      if math.abs(group.position - pos) <= POS_TOLERANCE then
        table.insert(group.items, {
          item = item,
          position = pos,
          length = len,
          track = get_track_label(item),
          take = get_take_name(item)
        })
        found_group = true
        break
      end
    end

    if not found_group then
      table.insert(groups, {
        position = pos,
        items = {{
          item = item,
          position = pos,
          length = len,
          track = get_track_label(item),
          take = get_take_name(item)
        }}
      })
    end
  end

  return groups
end

-- Check if a group has length mismatches
local function has_length_mismatch(group)
  if #group.items <= 1 then return false end

  local first_len = group.items[1].length
  for i = 2, #group.items do
    if math.abs(group.items[i].length - first_len) > LEN_TOLERANCE then
      return true
    end
  end

  return false
end

-- Main function
local function find_mismatched_items()
  R.ClearConsole()
  msg("=== Find Items with Mismatched Lengths ===")
  msg(("Position tolerance: %.3fs (%.1fms)"):format(POS_TOLERANCE, POS_TOLERANCE * 1000))
  msg(("Length tolerance: %.3fs (%.1fms)"):format(LEN_TOLERANCE, LEN_TOLERANCE * 1000))
  msg("")

  -- Get all items in project
  local item_count = R.CountMediaItems(0)
  if item_count == 0 then
    R.MB("No items in project.", "Find Mismatched Lengths", 0)
    return
  end

  local all_items = {}
  for i = 0, item_count - 1 do
    table.insert(all_items, R.GetMediaItem(0, i))
  end

  msg(("Total items in project: %d"):format(#all_items))
  msg("")

  -- Group items by position
  local groups = group_items_by_position(all_items)
  msg(("Found %d position groups"):format(#groups))
  msg("")

  -- Find groups with mismatches
  local mismatch_groups = {}
  for _, group in ipairs(groups) do
    if has_length_mismatch(group) then
      table.insert(mismatch_groups, group)
    end
  end

  if #mismatch_groups == 0 then
    msg("No length mismatches found!")
    msg("=== End ===")
    R.MB("No length mismatches found.\n\nAll items at the same timeline position have matching lengths.", "Find Mismatched Lengths", 0)
    return
  end

  -- Report mismatches
  msg(("Found %d groups with length mismatches:"):format(#mismatch_groups))
  msg("")

  local mismatched_items = {}

  for group_idx, group in ipairs(mismatch_groups) do
    msg(("Group %d - Position: %s (%.6fs)"):format(group_idx, format_time(group.position), group.position))
    msg(("  Items in group: %d"):format(#group.items))

    -- Sort items by length for easier comparison
    table.sort(group.items, function(a, b) return a.length < b.length end)

    local min_len = group.items[1].length
    local max_len = group.items[#group.items].length
    local diff = max_len - min_len

    msg(("  Length range: %.6fs to %.6fs (diff: %.6fs / %.1fms)"):format(
      min_len, max_len, diff, diff * 1000))

    for i, item_info in ipairs(group.items) do
      msg(("    Item %d: len=%.6fs  %s  take='%s'"):format(
        i, item_info.length, item_info.track, item_info.take))
      table.insert(mismatched_items, item_info.item)
    end

    msg("")
  end

  msg(("Total mismatched items: %d"):format(#mismatched_items))
  msg("=== End ===")

  -- Select all mismatched items
  R.Undo_BeginBlock()
  R.SelectAllMediaItems(0, false)
  for _, item in ipairs(mismatched_items) do
    R.SetMediaItemSelected(item, true)
  end
  R.UpdateArrange()
  R.Undo_EndBlock("Select items with mismatched lengths", -1)

  -- Show summary
  local summary = string.format(
    "Found %d groups with length mismatches.\n\n" ..
    "Total items with mismatches: %d\n\n" ..
    "These items have been selected.\n" ..
    "Check the console for detailed information.",
    #mismatch_groups, #mismatched_items
  )

  R.MB(summary, "Find Mismatched Lengths", 0)
end

-- Run
find_mismatched_items()
