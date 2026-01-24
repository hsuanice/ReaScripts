--[[
@description Find Items with TC Position Mismatch (TimeReference vs Timeline)
@version 260124.1845
@author hsuanice

@about
  Finds items where the BWF TimeReference doesn't match the actual timeline position.
  Useful for detecting TC embed errors in multi-channel recordings.

  Use case:
  - After splitting poly WAV to mono files
  - After phase alignment with Auto Align Post 2
  - When dual-recorder B-machine has TC offset issues
  - Finding items that should align but are placed at wrong timeline positions

  The script will:
  1. Read BWF TimeReference from each WAV file
  2. Calculate expected timeline position from TR and StartInSource
  3. Compare with actual item position
  4. Report items with mismatches
  5. Group items by TimeReference to find items that should align
  6. Find overlapping items that aren't perfectly aligned (ignores file names)

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v260124.1845
    - CHANGED: Removed scene-based detection (was incorrectly grouping different takes)
    - NEW: Pure TC/position overlap detection (ignores file names completely)
      * Finds items whose timelines overlap
      * Marks items that overlap but aren't perfectly aligned
      * Detects misaligned items regardless of file naming
    - Detection now purely based on TimeReference and actual timeline position

  v260124.1800
    - Scene-based detection (REMOVED in v260124.1845)

  v260124.1730
    - Added automatic take marker creation for all mismatched items
    - Markers color-coded by issue type:
      * Green: TC correct, reference position
      * Yellow: TC likely correct but slight offset
      * Orange: TC/Position mismatch or overlapping misaligned items
      * Red: Position wrong (in duplicate TR group)
    - Distinguishes between two types of issues:
      1. TC correct but item position wrong
      2. TC incorrect and needs correction

  v260124.1730
    - Added automatic take marker creation for all mismatched items
    - Markers color-coded by issue type:
      * Green: TC correct, reference position
      * Yellow: TC likely correct but slight offset
      * Orange: TC/Position mismatch (single item)
      * Red: Position wrong (in duplicate TR group)
    - Distinguishes between two types of issues:
      1. TC correct but item position wrong
      2. TC incorrect and needs correction

  v260124.1700
    - Changed detection logic: now finds items with same TimeReference but different positions
    - Reads BWF metadata to get actual TimeReference values
    - Calculates expected position and compares with actual position

  v260124.1620
    - Initial release (old logic: length mismatch detection)
]]

local R = reaper

-- Constants
local POS_TOLERANCE = 0.5 -- 500ms tolerance for considering positions "same"
local OS = R.GetOS()
local IS_WIN = OS:match("Win")

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

local function is_wav(p) return p and p:lower():sub(-4)==".wav" end

-- Shell wrapper for ExecProcess
local function sh_wrap(cmd)
  if IS_WIN then
    return 'cmd.exe /C "'..cmd..'"'
  else
    return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'"
  end
end

-- Execute shell command
local function exec_shell(cmd, ms)
  local ret = R.ExecProcess(sh_wrap(cmd), ms or 20000) or ""
  local code, out = ret:match("^(%d+)\n(.*)$")
  return tonumber(code or -1), (out or "")
end

-- Read TimeReference from BWF file
local function read_TR(wav_path)
  -- Try to use bwfmetaedit
  local cli_paths = IS_WIN and {
    [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]],
    [[C:\Program Files (x86)\BWF MetaEdit\bwfmetaedit.exe]],
    "bwfmetaedit"
  } or {
    "/opt/homebrew/bin/bwfmetaedit",
    "/usr/local/bin/bwfmetaedit",
    "bwfmetaedit"
  }

  for _, cli in ipairs(cli_paths) do
    local cmd = ('"%s" --out-xml=- "%s"'):format(cli, wav_path)
    local code, out = exec_shell(cmd, 10000)
    if code == 0 then
      local tr = tonumber(out:match("<TimeReference>(%d+)</TimeReference>") or "")
      return tr
    end
  end

  return nil
end

-- Get item info including TimeReference
local function get_item_info(item)
  local take = R.GetActiveTake(item)
  if not take then return nil end

  local src = R.GetMediaItemTake_Source(take)
  if not src then return nil end

  local file_path = R.GetMediaSourceFileName(src, "")
  if not is_wav(file_path) then return nil end

  -- Get item timeline position and take info
  local item_pos = R.GetMediaItemInfo_Value(item, "D_POSITION")
  local start_in_source = R.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")

  -- Get sample rate
  local sr = select(2, R.GetMediaSourceSampleRate(src)) or 48000
  if sr <= 0 then sr = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000 end
  sr = math.floor(sr + 0.5)

  -- Get project time offset
  local proj_offset = R.GetProjectTimeOffset(0, false) or 0.0

  -- Read TimeReference from file
  local tr_samples = read_TR(file_path)
  if not tr_samples then return nil end

  -- Calculate expected position based on TR and StartInSource
  -- TR represents the timecode of the file's first sample
  -- Expected item position = (TR / SR) - ProjectOffset + StartInSource
  local tr_seconds = tr_samples / sr
  local expected_pos = tr_seconds - proj_offset + start_in_source

  return {
    item = item,
    file_path = file_path,
    track = get_track_label(item),
    take = get_take_name(item),
    actual_pos = item_pos,
    expected_pos = expected_pos,
    tr_samples = tr_samples,
    tr_seconds = tr_seconds,
    start_in_source = start_in_source,
    sample_rate = sr,
    proj_offset = proj_offset,
    mismatch = math.abs(expected_pos - item_pos)
  }
end

-- Group items by TimeReference
local function group_items_by_TR(item_infos)
  local groups = {}

  for _, info in ipairs(item_infos) do
    local found = false
    for _, group in ipairs(groups) do
      if group.tr_samples == info.tr_samples then
        table.insert(group.items, info)
        found = true
        break
      end
    end

    if not found then
      table.insert(groups, {
        tr_samples = info.tr_samples,
        tr_seconds = info.tr_seconds,
        items = {info}
      })
    end
  end

  return groups
end

-- Add take marker
local function add_take_marker(item, message, color)
  local take = R.GetActiveTake(item)
  if not take then return false end

  -- Add marker at the beginning of the take (position 0 in source time)
  local marker_color = color or 0xFF0000FF -- Default: red with full alpha
  R.SetTakeMarker(take, -1, message, 0.0, marker_color)
  return true
end

-- Check if two items overlap on timeline
local function items_overlap(info1, info2)
  local item1_start = info1.actual_pos
  local item1_end = item1_start + R.GetMediaItemInfo_Value(info1.item, "D_LENGTH")
  local item2_start = info2.actual_pos
  local item2_end = item2_start + R.GetMediaItemInfo_Value(info2.item, "D_LENGTH")

  -- Check for overlap
  return not (item1_end <= item2_start or item2_end <= item1_start)
end

-- Find overlapping items that aren't perfectly aligned
local function find_overlapping_misaligned(item_infos)
  local results = {}

  for i = 1, #item_infos do
    for j = i + 1, #item_infos do
      local info1 = item_infos[i]
      local info2 = item_infos[j]

      -- Check if they overlap
      if items_overlap(info1, info2) then
        -- Check if they're NOT perfectly aligned
        local pos_diff = math.abs(info1.actual_pos - info2.actual_pos)
        if pos_diff > POS_TOLERANCE then
          -- They overlap but aren't aligned - mark both
          table.insert(results, {info1, info2})
        end
      end
    end
  end

  return results
end

-- Main function
local function find_mismatched_items()
  R.ClearConsole()
  msg("=== Find Items with TC Position Mismatch ===")
  msg(("Position tolerance: %.3fs (%.1fms)"):format(POS_TOLERANCE, POS_TOLERANCE * 1000))
  msg("")

  -- Get all items in project
  local item_count = R.CountMediaItems(0)
  if item_count == 0 then
    R.MB("No items in project.", "Find TC Mismatch", 0)
    return
  end

  msg(("Total items in project: %d"):format(item_count))
  msg("Reading TimeReference from WAV files...")
  msg("")

  -- Get info for all WAV items
  local item_infos = {}
  local skipped = 0
  for i = 0, item_count - 1 do
    local item = R.GetMediaItem(0, i)
    local info = get_item_info(item)
    if info then
      table.insert(item_infos, info)
    else
      skipped = skipped + 1
    end
  end

  msg(("Processed: %d WAV items, %d skipped (non-WAV or no TR)"):format(#item_infos, skipped))
  msg("")

  if #item_infos == 0 then
    R.MB("No WAV items with TimeReference found in project.", "Find TC Mismatch", 0)
    return
  end

  -- Find items with position mismatches
  local mismatched = {}
  for _, info in ipairs(item_infos) do
    if info.mismatch > POS_TOLERANCE then
      table.insert(mismatched, info)
    end
  end

  -- Group items by TimeReference to find duplicates at different positions
  local tr_groups = group_items_by_TR(item_infos)
  local duplicate_tr_groups = {}
  for _, group in ipairs(tr_groups) do
    if #group.items > 1 then
      -- Check if they're at different positions
      local first_pos = group.items[1].actual_pos
      local has_diff_pos = false
      for i = 2, #group.items do
        if math.abs(group.items[i].actual_pos - first_pos) > POS_TOLERANCE then
          has_diff_pos = true
          break
        end
      end
      if has_diff_pos then
        table.insert(duplicate_tr_groups, group)
      end
    end
  end

  -- Find overlapping items that aren't perfectly aligned
  local overlapping_misaligned = find_overlapping_misaligned(item_infos)

  -- Report findings
  if #mismatched == 0 and #duplicate_tr_groups == 0 and #overlapping_misaligned == 0 then
    msg("No TC position mismatches found!")
    msg("All items are correctly positioned according to their TimeReference.")
    msg("=== End ===")
    R.MB("No TC mismatches found.\n\nAll items are correctly positioned.", "Find TC Mismatch", 0)
    return
  end

  msg("=== RESULTS ===")
  msg("")

  -- Track which items are in duplicate TR groups
  local items_in_dup_groups = {}
  for _, group in ipairs(duplicate_tr_groups) do
    for _, info in ipairs(group.items) do
      items_in_dup_groups[info.item] = true
    end
  end

  -- Report items with wrong positions
  if #mismatched > 0 then
    msg(("Found %d items with position mismatch (Expected vs Actual):"):format(#mismatched))
    msg("")
    for i, info in ipairs(mismatched) do
      msg(("Item %d: %s - take='%s'"):format(i, info.track, info.take))
      msg(("  TR: %d samples (%.6fs)"):format(info.tr_samples, info.tr_seconds))
      msg(("  Expected position: %s (%.6fs)"):format(format_time(info.expected_pos), info.expected_pos))
      msg(("  Actual position:   %s (%.6fs)"):format(format_time(info.actual_pos), info.actual_pos))
      msg(("  Mismatch: %.6fs (%.1fms)"):format(info.mismatch, info.mismatch * 1000))

      -- Add take marker if not in a duplicate group (will be handled separately)
      if not items_in_dup_groups[info.item] then
        local marker_msg = string.format("Review: TC/Position mismatch (%.1fs diff)", info.mismatch)
        add_take_marker(info.item, marker_msg, 0xFF6600FF) -- Orange
        msg(("  Added marker: '%s'"):format(marker_msg))
      end
      msg("")
    end
  end

  -- Report duplicate TR groups and add markers
  if #duplicate_tr_groups > 0 then
    msg(("Found %d TimeReference groups with items at different positions:"):format(#duplicate_tr_groups))
    msg("")
    for group_idx, group in ipairs(duplicate_tr_groups) do
      msg(("Group %d - TR: %d samples (%.6fs) - %s"):format(
        group_idx, group.tr_samples, group.tr_seconds, format_time(group.tr_seconds)))
      msg(("  %d items with this TR:"):format(#group.items))

      -- Sort by position for clarity
      table.sort(group.items, function(a, b) return a.actual_pos < b.actual_pos end)

      -- Find the item closest to expected position (TC is likely correct for this one)
      local closest_item = nil
      local min_mismatch = math.huge
      for _, info in ipairs(group.items) do
        if info.mismatch < min_mismatch then
          min_mismatch = info.mismatch
          closest_item = info
        end
      end

      for i, info in ipairs(group.items) do
        msg(("    Item %d: pos=%s (%.6fs)  %s  take='%s'  mismatch=%.3fs"):format(
          i, format_time(info.actual_pos), info.actual_pos, info.track, info.take, info.mismatch))

        -- Add appropriate marker
        if info == closest_item and info.mismatch <= POS_TOLERANCE then
          -- This item is correctly positioned according to TC
          local marker_msg = "Review: TC correct, reference position"
          add_take_marker(info.item, marker_msg, 0x00FF00FF) -- Green
          msg(("      Marker: '%s'"):format(marker_msg))
        elseif info == closest_item then
          -- Closest but still has some mismatch
          local marker_msg = string.format("Review: TC likely correct (%.1fs off)", info.mismatch)
          add_take_marker(info.item, marker_msg, 0xFFFF00FF) -- Yellow
          msg(("      Marker: '%s'"):format(marker_msg))
        else
          -- This item is misaligned - either wrong position or wrong TC
          if closest_item and closest_item.actual_pos then
            local expected_tc = format_time(closest_item.actual_pos)
            local marker_msg = string.format("Review: Position wrong, should be %s", expected_tc)
            add_take_marker(info.item, marker_msg, 0xFF0000FF) -- Red
            msg(("      Marker: '%s'"):format(marker_msg))
          else
            local marker_msg = "Review: Position wrong"
            add_take_marker(info.item, marker_msg, 0xFF0000FF) -- Red
            msg(("      Marker: '%s'"):format(marker_msg))
          end
        end
      end
      msg("")
    end
  end

  -- Report overlapping items that aren't aligned
  if #overlapping_misaligned > 0 then
    msg(("Found %d pairs of overlapping but misaligned items:"):format(#overlapping_misaligned))
    msg("")

    -- Track which items we've already marked to avoid duplicates
    local marked_items = {}

    for pair_idx, pair in ipairs(overlapping_misaligned) do
      local info1, info2 = pair[1], pair[2]
      local pos_diff = math.abs(info1.actual_pos - info2.actual_pos)

      msg(("Pair %d - Overlapping items with %.3fs position difference:"):format(pair_idx, pos_diff))
      msg(("  Item A: pos=%s (%.6fs)  TR=%d  %s  take='%s'"):format(
        format_time(info1.actual_pos), info1.actual_pos, info1.tr_samples, info1.track, info1.take))
      msg(("  Item B: pos=%s (%.6fs)  TR=%d  %s  take='%s'"):format(
        format_time(info2.actual_pos), info2.actual_pos, info2.tr_samples, info2.track, info2.take))

      -- Add markers to both items if not already marked
      if not marked_items[info1.item] then
        local marker_msg = string.format("Review: Overlaps but misaligned (%.1fs off from another item)", pos_diff)
        add_take_marker(info1.item, marker_msg, 0xFFAA00FF) -- Orange
        msg(("    Marker added to Item A: '%s'"):format(marker_msg))
        marked_items[info1.item] = true
      end

      if not marked_items[info2.item] then
        local marker_msg = string.format("Review: Overlaps but misaligned (%.1fs off from another item)", pos_diff)
        add_take_marker(info2.item, marker_msg, 0xFFAA00FF) -- Orange
        msg(("    Marker added to Item B: '%s'"):format(marker_msg))
        marked_items[info2.item] = true
      end

      msg("")
    end
  end

  msg("=== End ===")

  -- Select all problematic items
  local items_to_select = {}

  -- Helper to add item if not already added
  local function add_item(item)
    for _, existing in ipairs(items_to_select) do
      if existing == item then return end
    end
    table.insert(items_to_select, item)
  end

  for _, info in ipairs(mismatched) do
    add_item(info.item)
  end

  for _, group in ipairs(duplicate_tr_groups) do
    for _, info in ipairs(group.items) do
      add_item(info.item)
    end
  end

  for _, pair in ipairs(overlapping_misaligned) do
    add_item(pair[1].item)
    add_item(pair[2].item)
  end

  R.Undo_BeginBlock()
  R.SelectAllMediaItems(0, false)
  for _, item in ipairs(items_to_select) do
    R.SetMediaItemSelected(item, true)
  end
  R.UpdateArrange()
  R.Undo_EndBlock("Select items with TC mismatches", -1)

  -- Show summary
  local summary_parts = {}
  if #mismatched > 0 then
    table.insert(summary_parts, string.format("%d items with TC/position mismatch", #mismatched))
  end
  if #duplicate_tr_groups > 0 then
    table.insert(summary_parts, string.format("%d TR groups with different positions", #duplicate_tr_groups))
  end
  if #overlapping_misaligned > 0 then
    table.insert(summary_parts, string.format("%d pairs of overlapping but misaligned items", #overlapping_misaligned))
  end

  local summary = string.format(
    "Found TC position issues:\n\n%s\n\n" ..
    "Total items selected: %d\n\n" ..
    "Take markers have been added.\n" ..
    "Check the console for detailed information.",
    table.concat(summary_parts, "\n"), #items_to_select
  )

  R.MB(summary, "Find TC Mismatch", 0)
end

-- Run
find_mismatched_items()
