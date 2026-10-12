--[[
@description hsuanice_Fix Misaligned Crossfades
@version 26.1012.0736
@author hsuanice
@noindex
@changelog
  - Released as part of the 26.1012.0736 package update.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Scan all items in the project. If crossfade auto-fade lengths don't match the overlap region,
  add take marker(s) at the misaligned crossfade boundaries using source-time coordinates
  and print a concise console report.

  What constitutes a misaligned crossfade:
  - Two items overlap on the same track
  - Both have auto-crossfade (D_FADEINLEN_AUTO / D_FADEOUTLEN_AUTO > 0)
  - Either: fade lengths don't match each other, OR fade length doesn't match overlap length

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
-- ACTION_MODE: 1=Review only (add markers); 2=Fix misaligned crossfades
local ACTION_MODE = 2

-- When fixing, also drop a take marker at the crossfade boundary
local ADD_FIXED_MARKER = true

-- Tolerance for checking if fade points align (in seconds)
local ALIGNMENT_TOLERANCE = 0.001  -- 1ms

-- Epsilon for duplicate marker detection
local EPS_SEC = 0.001

-- Marker labels (matching your Review style)
local LABEL_MISALIGNED_IN  = "Review: Crossfade misaligned (fade-in)"
local LABEL_MISALIGNED_OUT = "Review: Crossfade misaligned (fade-out)"
local FIX_LABEL_IN  = "Fixed: Crossfade aligned (fade-in)"
local FIX_LABEL_OUT = "Fixed: Crossfade aligned (fade-out)"

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
  r.SetTakeMarker(tk, -1, marker_name, src_pos, 0)
  return true
end

---------------------------------------
-- Crossfade detection and fixing
---------------------------------------

-- Find and process misaligned crossfades
local function process_crossfades()
  local n_items = r.CountMediaItems(0)
  local results = {}
  local processed_pairs = {}  -- Track which pairs we've already processed
  local fixes_applied = 0
  local markers_added = 0

  for i = 0, n_items - 1 do
    local item = r.GetMediaItem(0, i)
    if item then
      local tr = r.GetMediaItem_Track(item)
      if tr then
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
        local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
        local item_end = pos + len

        local fadein_auto = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO") or 0
        local fadeout_auto = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO") or 0

        -- Skip if no auto-crossfade
        if fadein_auto > 0 or fadeout_auto > 0 then
          local n_track_items = r.CountTrackMediaItems(tr)

          for j = 0, n_track_items - 1 do
            local other = r.GetTrackMediaItem(tr, j)
            if other and other ~= item then
              local other_pos = r.GetMediaItemInfo_Value(other, "D_POSITION") or 0
              local other_len = r.GetMediaItemInfo_Value(other, "D_LENGTH") or 0
              local other_end = other_pos + other_len
              local other_fadein_auto = r.GetMediaItemInfo_Value(other, "D_FADEINLEN_AUTO") or 0
              local other_fadeout_auto = r.GetMediaItemInfo_Value(other, "D_FADEOUTLEN_AUTO") or 0

              -- Check if items overlap
              if pos < other_end and item_end > other_pos then
                -- Create unique pair ID using item addresses (sorted to avoid duplicates)
                local item_addr = tostring(item)
                local other_addr = tostring(other)

                -- Sort to create consistent pair ID
                local pair_id
                if item_addr < other_addr then
                  pair_id = item_addr .. "_" .. other_addr
                else
                  pair_id = other_addr .. "_" .. item_addr
                end

                -- Skip if we've already processed this pair
                if not processed_pairs[pair_id] then
                  -- Calculate overlap
                  local overlap_start = math.max(pos, other_pos)
                  local overlap_end = math.min(item_end, other_end)
                  local overlap_length = overlap_end - overlap_start

                  -- Determine which item is on the left
                  local left_item, right_item, left_pos, right_pos
                  if pos < other_pos then
                    left_item = item
                    right_item = other
                    left_pos = pos
                    right_pos = other_pos
                  else
                    left_item = other
                    right_item = item
                    left_pos = other_pos
                    right_pos = pos
                  end

                  local left_fadeout = r.GetMediaItemInfo_Value(left_item, "D_FADEOUTLEN_AUTO") or 0
                  local right_fadein = r.GetMediaItemInfo_Value(right_item, "D_FADEINLEN_AUTO") or 0

                  -- Check if crossfade exists and is misaligned
                  if left_fadeout > 0 and right_fadein > 0 then
                    local fade_mismatch = math.abs(left_fadeout - right_fadein)
                    local overlap_mismatch_left = math.abs(overlap_length - left_fadeout)
                    local overlap_mismatch_right = math.abs(overlap_length - right_fadein)

                    if fade_mismatch > ALIGNMENT_TOLERANCE or
                       overlap_mismatch_left > ALIGNMENT_TOLERANCE or
                       overlap_mismatch_right > ALIGNMENT_TOLERANCE then

                      -- Mark this pair as processed
                      processed_pairs[pair_id] = true

                      -- Get item info for logging
                      local left_tr = r.GetMediaItem_Track(left_item)
                      local left_tk = r.GetActiveTake(left_item)
                      local right_tr = r.GetMediaItem_Track(right_item)
                      local right_tk = r.GetActiveTake(right_item)

                      local left_tr_name = safe_trackname(left_tr)
                      local left_tk_name = safe_takename(left_tk)
                      local right_tr_name = safe_trackname(right_tr)
                      local right_tk_name = safe_takename(right_tk)

                      local left_item_len = r.GetMediaItemInfo_Value(left_item, "D_LENGTH") or 0
                      local right_item_len = r.GetMediaItemInfo_Value(right_item, "D_LENGTH") or 0

                      -- Record the result
                      table.insert(results, {
                        left_item = left_item,
                        right_item = right_item,
                        left_tr_name = left_tr_name,
                        left_tk_name = left_tk_name,
                        right_tr_name = right_tr_name,
                        right_tk_name = right_tk_name,
                        left_pos = left_pos,
                        right_pos = right_pos,
                        overlap_length = overlap_length,
                        old_left_fadeout = left_fadeout,
                        old_right_fadein = right_fadein,
                        fade_mismatch = fade_mismatch,
                        overlap_mismatch_left = overlap_mismatch_left,
                        overlap_mismatch_right = overlap_mismatch_right
                      })

                      -- If in fix mode, apply the fix
                      if ACTION_MODE == 2 then
                        -- Set both auto-fades to overlap length
                        r.SetMediaItemInfo_Value(left_item, "D_FADEOUTLEN_AUTO", overlap_length)
                        r.SetMediaItemInfo_Value(right_item, "D_FADEINLEN_AUTO", overlap_length)
                        fixes_applied = fixes_applied + 1

                        -- Add fixed markers if requested
                        if ADD_FIXED_MARKER and left_tk and right_tk then
                          -- Left item: marker at fade-out start
                          local left_item_end = left_pos + left_item_len
                          local fadeout_start_proj = left_item_end - overlap_length
                          local fadeout_start_src = projtime_to_taketime(left_tk, left_item, fadeout_start_proj)
                          if add_take_marker_if_needed(left_tk, FIX_LABEL_OUT, fadeout_start_src, EPS_SEC) then
                            markers_added = markers_added + 1
                          end

                          -- Right item: marker at fade-in end
                          local fadein_end_proj = right_pos + overlap_length
                          local fadein_end_src = projtime_to_taketime(right_tk, right_item, fadein_end_proj)
                          if add_take_marker_if_needed(right_tk, FIX_LABEL_IN, fadein_end_src, EPS_SEC) then
                            markers_added = markers_added + 1
                          end
                        end
                      else
                        -- Review mode: add review markers
                        if left_tk and right_tk then
                          -- Left item: marker at fade-out start
                          local left_item_end = left_pos + left_item_len
                          local fadeout_start_proj = left_item_end - left_fadeout
                          local fadeout_start_src = projtime_to_taketime(left_tk, left_item, fadeout_start_proj)
                          if add_take_marker_if_needed(left_tk, LABEL_MISALIGNED_OUT, fadeout_start_src, EPS_SEC) then
                            markers_added = markers_added + 1
                          end

                          -- Right item: marker at fade-in end
                          local fadein_end_proj = right_pos + right_fadein
                          local fadein_end_src = projtime_to_taketime(right_tk, right_item, fadein_end_proj)
                          if add_take_marker_if_needed(right_tk, LABEL_MISALIGNED_IN, fadein_end_src, EPS_SEC) then
                            markers_added = markers_added + 1
                          end
                        end
                      end
                    end
                  end
                end
              end
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
  log(string.format("=== %s: Misaligned Crossfades ===\n", mode_str))

  local n_items = r.CountMediaItems(0)
  log(string.format("Scanning %d items...\n", n_items))

  -- Start undo block
  r.Undo_BeginBlock()

  -- Process all crossfades
  local results, fixes_applied, markers_added = process_crossfades()

  -- Print results
  if #results > 0 then
    log(string.format("Found %d misaligned crossfade pair(s):\n", #results))

    for idx, result in ipairs(results) do
      log(string.format("%d. Crossfade between:", idx))
      log(string.format("   Left:  %s [%s] @ %.6f",
                        result.left_tr_name, result.left_tk_name, result.left_pos))
      log(string.format("   Right: %s [%s] @ %.6f",
                        result.right_tr_name, result.right_tk_name, result.right_pos))
      log(string.format("   Overlap length: %.6f sec (%.3f ms)",
                        result.overlap_length, result.overlap_length * 1000))

      if ACTION_MODE == 2 then
        log(string.format("   Fixed: Set both auto-fades to %.6f sec", result.overlap_length))
      else
        log(string.format("   Old values: left fadeout=%.6f sec, right fadein=%.6f sec",
                          result.old_left_fadeout, result.old_right_fadein))
        log(string.format("   Fade mismatch: %.6f sec (%.3f ms)",
                          result.fade_mismatch, result.fade_mismatch * 1000))
        if result.overlap_mismatch_left > ALIGNMENT_TOLERANCE then
          log(string.format("   Left overlap mismatch: %.6f sec (%.3f ms)",
                            result.overlap_mismatch_left, result.overlap_mismatch_left * 1000))
        end
        if result.overlap_mismatch_right > ALIGNMENT_TOLERANCE then
          log(string.format("   Right overlap mismatch: %.6f sec (%.3f ms)",
                            result.overlap_mismatch_right, result.overlap_mismatch_right * 1000))
        end
      end
      log("")
    end

    -- Summary
    log(string.format("--- Summary ---"))
    if ACTION_MODE == 2 then
      log(string.format("Fixed: %d crossfade pair(s)", fixes_applied))
      log(string.format("Markers added: %d", markers_added))
    else
      log(string.format("Misaligned crossfades: %d pair(s)", #results))
      log(string.format("Review markers added: %d", markers_added))
    end

    -- End undo block
    local undo_text = string.format("%s: Misaligned crossfades — %d pair(s)", mode_str, #results)
    r.Undo_EndBlock(undo_text, -1)
    r.UpdateArrange()
  else
    log("\n✓ No misaligned crossfades found - all crossfades are properly aligned!")
    r.Undo_EndBlock("No misaligned crossfades found", -1)
  end
end

main()
