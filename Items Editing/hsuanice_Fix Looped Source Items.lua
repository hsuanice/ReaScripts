--[[
@description hsuanice_Fix Looped Source Items
@version 26.1012.0736
@author hsuanice
@noindex
@changelog
  - Released as part of the 26.1012.0736 package update.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Scan all items in the project. If an item's length exceeds its source length
  (causing the source to loop), add take marker(s) at the loop boundary using
  source-time coordinates and print a concise console report.

  What constitutes a looped source:
  - Item length > available source length from start offset
  - This causes REAPER to loop the source material

  Notes:
  - Source-pos mapping honors take rate (D_PLAYRATE) and start offset (D_STARTOFFS).
  - Duplicate suppression: skip if same-name marker already exists near the same source position.
  - Scope: all items in project (no selection required).
  - Console: summary + per-issue lines; uses ShowConsoleMsg (clears at start).
--]]
local r = reaper

---------------------------------------
-- Console helpers
---------------------------------------
local function log(s) r.ShowConsoleMsg(tostring(s) .. "\n") end
local function clr() r.ShowConsoleMsg("") end

---------------------------------------
-- User options
---------------------------------------
-- ACTION_MODE: 1=Review only (add markers); 2=Fix by trimming item to source length
local ACTION_MODE = 1

-- When fixing, also drop a take marker at the trimmed edge
local ADD_FIXED_MARKER = true

-- Tolerance for detecting loops (in seconds)
local LOOP_TOLERANCE = 0.001  -- 1ms

-- Epsilon for duplicate marker detection
local EPS_SEC = 0.001

-- Marker edge inset (project time) to ensure marker visibility
local MARKER_EDGE_INSET_PROJ_SEC = 0.001  -- 1ms inside the boundary

-- Marker labels (matching your Review style)
local LABEL_LOOP_POINT = "Review: Source loops here"
local FIX_LABEL_TRIM = "Fixed: Trimmed to source length"

---------------------------------------
-- Helpers
---------------------------------------
local function safe_takename(tk)
  local name = tk and r.GetTakeName(tk) or ""
  if not name or name == "" then return "(no-take-name)" end
  return name
end

local function safe_trackname(tr)
  local ok, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if ok and name ~= "" then return name end
  return string.format("Track %d", tr and (r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or -1)
end

-- Get source length in seconds
local function get_source_len_sec(tk)
  if not tk then return 0 end
  local src = r.GetMediaItemTake_Source(tk)
  if not src then return 0 end
  local len, isqn = r.GetMediaSourceLength(src)
  if isqn then
    -- MIDI source: convert quarter notes to seconds
    local qn_tempo = r.Master_GetTempo()
    return (len / qn_tempo) * 60.0
  end
  return len
end

-- Convert project time to take source time
local function projtime_to_taketime(tk, item, proj_time)
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1.0
  local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
  if rate == 0 then rate = 1.0 end
  local item_offset = proj_time - pos
  return offs + (item_offset * rate)
end

-- Check if a take marker with the same name exists near the source position
local function marker_exists_near(tk, marker_name, src_pos, epsilon)
  local n_markers = r.GetNumTakeMarkers(tk)
  for i = 0, n_markers - 1 do
    local retval, name, color = r.GetTakeMarker(tk, i)
    if name == marker_name and math.abs(retval - src_pos) < epsilon then
      return true
    end
  end
  return false
end

-- Add take marker if not already present
local function add_take_marker_if_needed(tk, marker_name, src_pos, epsilon)
  if marker_exists_near(tk, marker_name, src_pos, epsilon) then
    return false
  end

  -- Clamp source position to valid range
  local src_len = get_source_len_sec(tk)
  if src_pos < 0 then src_pos = 0 end
  if src_len > 0 and src_pos > src_len then src_pos = src_len end

  r.SetTakeMarker(tk, -1, marker_name, src_pos, 0)
  return true
end

---------------------------------------
-- Loop detection and fixing
---------------------------------------

-- Check if item has looped source
local function check_item_loop(item)
  local tk = r.GetActiveTake(item)
  if not tk then return nil end

  local src_len = get_source_len_sec(tk)
  if src_len <= 0 then return nil end

  local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1.0
  if rate == 0 then rate = 1.0 end
  local start_offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0

  -- Calculate available source length from start offset
  local available_src_len = src_len - start_offs
  if available_src_len < 0 then available_src_len = 0 end

  -- Calculate required source length for this item
  local required_src_len = item_len * rate

  -- Check if item would loop
  if required_src_len > available_src_len + LOOP_TOLERANCE then
    -- Calculate where the loop would occur in project time
    local loop_occurs_at_item_time = available_src_len / rate
    local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
    local loop_point_proj = item_pos + loop_occurs_at_item_time

    -- Calculate loop point in source time (should be at or near source end)
    local loop_point_src = start_offs + available_src_len

    -- Calculate excess length
    local excess_len = required_src_len - available_src_len
    local excess_proj_len = excess_len / rate

    return {
      item = item,
      take = tk,
      src_len = src_len,
      available_src_len = available_src_len,
      required_src_len = required_src_len,
      item_len = item_len,
      excess_len = excess_len,
      excess_proj_len = excess_proj_len,
      loop_point_proj = loop_point_proj,
      loop_point_src = loop_point_src,
      loop_occurs_at_item_time = loop_occurs_at_item_time,
      rate = rate,
      start_offs = start_offs
    }
  end

  return nil
end

-- Process all items
local function process_items()
  local n_items = r.CountMediaItems(0)
  local results = {}
  local fixes_applied = 0
  local markers_added = 0

  for i = 0, n_items - 1 do
    local item = r.GetMediaItem(0, i)
    if item then
      local loop_info = check_item_loop(item)

      if loop_info then
        -- Get item info for logging
        local tr = r.GetMediaItem_Track(item)
        local tk = loop_info.take
        local tr_name = safe_trackname(tr)
        local tk_name = safe_takename(tk)
        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0

        -- Record the result
        table.insert(results, {
          item = item,
          take = tk,
          tr_name = tr_name,
          tk_name = tk_name,
          item_pos = item_pos,
          loop_info = loop_info
        })

        -- If in fix mode, trim the item
        if ACTION_MODE == 2 then
          -- Trim item to available source length
          local new_len = loop_info.loop_occurs_at_item_time
          r.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
          fixes_applied = fixes_applied + 1

          -- Add fixed marker if requested
          if ADD_FIXED_MARKER and tk then
            -- Add marker near the new right edge
            local pos_now = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
            local len_now = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
            local right_proj = math.max(pos_now, pos_now + len_now - MARKER_EDGE_INSET_PROJ_SEC)
            local src_pos = projtime_to_taketime(tk, item, right_proj)

            if add_take_marker_if_needed(tk, FIX_LABEL_TRIM, src_pos, EPS_SEC) then
              markers_added = markers_added + 1
            end
          end
        else
          -- Review mode: add marker at loop point
          if tk then
            -- Add marker at the loop point (where source would restart)
            -- Use the source end position
            local src_pos = loop_info.loop_point_src

            if add_take_marker_if_needed(tk, LABEL_LOOP_POINT, src_pos, EPS_SEC) then
              markers_added = markers_added + 1
            end
          end
        end
      end
    end
  end

  return results, fixes_applied, markers_added
end

---------------------------------------
-- Main
---------------------------------------
local function main()
  -- Force open console then clear
  r.ShowConsoleMsg("")
  clr()

  local mode_str = (ACTION_MODE == 2) and "Fix" or "Review"
  log(string.format("=== %s: Looped Source Items ===\n", mode_str))

  local n_items = r.CountMediaItems(0)
  log(string.format("Scanning %d items...\n", n_items))

  -- Start undo block
  r.Undo_BeginBlock()

  -- Process all items
  local results, fixes_applied, markers_added = process_items()

  -- Print results
  if #results > 0 then
    log(string.format("Found %d item(s) with looped source:\n", #results))

    for idx, result in ipairs(results) do
      local info = result.loop_info

      log(string.format("%d. %s [%s] @ %.6f", idx, result.tr_name, result.tk_name, result.item_pos))
      log(string.format("   Item length: %.6f sec (%.3f ms)", info.item_len, info.item_len * 1000))
      log(string.format("   Source length: %.6f sec", info.src_len))
      log(string.format("   Start offset: %.6f sec", info.start_offs))
      log(string.format("   Available source: %.6f sec", info.available_src_len))
      log(string.format("   Required source: %.6f sec (at rate %.3fx)", info.required_src_len, info.rate))
      log(string.format("   Excess length: %.6f sec (%.3f ms) - would loop",
                        info.excess_proj_len, info.excess_proj_len * 1000))

      if ACTION_MODE == 2 then
        log(string.format("   Fixed: Trimmed to %.6f sec", info.loop_occurs_at_item_time))
      else
        log(string.format("   Loop point: @ %.6f (project time)", info.loop_point_proj))
      end
      log("")
    end

    -- Summary
    log(string.format("--- Summary ---"))
    if ACTION_MODE == 2 then
      log(string.format("Fixed: %d item(s) trimmed to source length", fixes_applied))
      log(string.format("Markers added: %d", markers_added))
    else
      log(string.format("Looped source items: %d", #results))
      log(string.format("Review markers added: %d", markers_added))
    end

    -- End undo block
    local undo_text = string.format("%s: Looped source items — %d item(s)", mode_str, #results)
    r.Undo_EndBlock(undo_text, -1)
    r.UpdateArrange()
  else
    log("\n✓ No looped source items found - all items fit within their source material!")
    r.Undo_EndBlock("No looped source items found", -1)
  end
end

main()
