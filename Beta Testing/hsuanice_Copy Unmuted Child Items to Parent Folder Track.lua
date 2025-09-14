--[[
@description Copy UNMUTED child items to the parent folder track (pre-check overlaps → mark & abort)
@version 0.1.1
@author hsuanice
@changelog
  v0.1.1
    - Fix: Use GetTrackMediaItem(track, i) instead of GetMediaItem(proj, i) when iterating items on a track.
  v0.1.0
    - Initial release:
      * Select a FOLDER (parent) track and run
      * Scan all children; if ANY unmuted child item would overlap existing parent items:
          - add a TAKE MARKER "OVERLAP" on that child item's active take (at source start)
          - abort without copying anything
      * If no overlaps detected, copy all unmuted items in-place to the parent (state-chunk)
      * Show a simple summary dialog
@about
  Non-destructive helper for vocal comping. This script never moves or edits child items.
]]

local r = reaper

local function msg(s) r.ShowMessageBox(s, "Copy Unmuted → Parent (Check Overlaps)", 0) end

local function is_folder(track)
  if not track then return false end
  return (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0) == 1
end

-- Collect all child tracks of a selected folder track
local function collect_children_of_folder(parent_tr)
  local children = {}
  local proj = 0
  local parent_idx = r.GetMediaTrackInfo_Value(parent_tr, "IP_TRACKNUMBER") -- 1-based
  local total = r.CountTracks(proj)
  if parent_idx >= total then return children end

  local depth_acc = 1 -- start "inside" the folder after parent
  for i = parent_idx + 1, total do
    local tr = r.GetTrack(proj, i - 1)
    if not tr then break end
    local d  = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0
    children[#children+1] = tr
    depth_acc = depth_acc + d
    if depth_acc <= 0 then break end -- folder tree closed
  end
  return children
end

-- Build intervals from existing items on parent: { {s=.., e=..}, ... } sorted by s
local function build_parent_intervals(parent_tr)
  local N = r.CountTrackMediaItems(parent_tr)
  local intervals = {}
  for i = 0, N - 1 do
    local it = r.GetTrackMediaItem(parent_tr, i)
    if it then
      local s  = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local e  = s + r.GetMediaItemInfo_Value(it, "D_LENGTH")
      intervals[#intervals+1] = { s = s, e = e }
    end
  end
  table.sort(intervals, function(a,b) return a.s < b.s end)
  return intervals
end

-- Binary search: first index with start >= x
local function lower_bound(intervals, x)
  local lo, hi, ans = 1, #intervals, #intervals + 1
  while lo <= hi do
    local mid = (lo + hi) // 2
    if intervals[mid].s >= x then
      ans = mid; hi = mid - 1
    else
      lo = mid + 1
    end
  end
  return ans
end

local function has_overlap(intervals, s, e)
  if e <= s or #intervals == 0 then return false end
  local idx = lower_bound(intervals, s)
  local j = idx - 1
  if j >= 1 and intervals[j].e > s then return true end
  for k = idx, math.min(idx + 2, #intervals) do
    local iv = intervals[k]; if not iv then break end
    if iv.s < e and iv.e > s then return true end
    if iv.s >= e then break end
  end
  return false
end

-- Add a Take Marker "OVERLAP" at the source position corresponding to item start
local function mark_overlap_take(child_item, label)
  local take = r.GetActiveTake(child_item); if not take then return false end
  local startoffs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
  if r.AddTakeMarker then
    r.AddTakeMarker(take, -1, label or "OVERLAP", startoffs)
    return true
  else
    -- Fallback: append note to take name
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", (name or "") .. " [OVERLAP]", true)
    return false
  end
end

-- High-fidelity copy via state chunk
local function copy_item_by_chunk(src_item, dest_track)
  local ok, chunk = r.GetItemStateChunk(src_item, "", false)
  if not ok then return nil end
  local new_item = r.AddMediaItemToTrack(dest_track); if not new_item then return nil end
  r.SetItemStateChunk(new_item, chunk, true)
  -- Re-assert position defensively
  local pos = r.GetMediaItemInfo_Value(src_item, "D_POSITION")
  r.SetMediaItemInfo_Value(new_item, "D_POSITION", pos)
  return new_item
end

local function main()
  local parent = r.GetSelectedTrack(0, 0)
  if not parent or not is_folder(parent) then
    msg("Please select a FOLDER (parent) track and run again.")
    return
  end

  local children = collect_children_of_folder(parent)
  if #children == 0 then
    msg("No child tracks under the selected folder.")
    return
  end

  local _, parent_name = r.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
  local parent_iv = build_parent_intervals(parent)

  -- Pass 1: detect any overlaps and mark them; if any found → abort (no copy)
  local scanned, overlap_cnt, examples = 0, 0, {}
  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)

  for _, tr in ipairs(children) do
    if tr then
      local n = r.CountTrackMediaItems(tr)
      for i = 0, n - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        if it then
          scanned = scanned + 1
          -- skip muted item
          if r.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then
            -- also skip if active take muted
            local tk = r.GetActiveTake(it)
            if not (tk and r.GetMediaItemTakeInfo_Value(tk, "B_MUTE") == 1) then
              local s  = r.GetMediaItemInfo_Value(it, "D_POSITION")
              local e  = s + r.GetMediaItemInfo_Value(it, "D_LENGTH")
              if has_overlap(parent_iv, s, e) then
                overlap_cnt = overlap_cnt + 1
                local added = mark_overlap_take(it, "OVERLAP")
                if #examples < 6 then
                  examples[#examples+1] = string.format("  - %.3f ~ %.3f  (%s)", s, e, added and "marked" or "name-tag")
                end
              end
            end
          end
        end
      end
    end
  end

  if overlap_cnt > 0 then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock2(0, "Detect overlaps (marked) — aborted copy", -1)
    local lines = {}
    lines[#lines+1] = string.format("Parent: %s", parent_name ~= "" and parent_name or "(unnamed)")
    lines[#lines+1] = string.format("Children: %d track(s)", #children)
    lines[#lines+1] = string.format("Scanned items: %d", scanned)
    lines[#lines+1] = ""
    lines[#lines+1] = string.format("⚠️ Overlap detected: %d item(s).", overlap_cnt)
    lines[#lines+1] = "All overlaps have been marked on the CHILD items (take marker: \"OVERLAP\")."
    if #examples > 0 then
      lines[#lines+1] = ""
      lines[#lines+1] = "Examples:"
      for _, L in ipairs(examples) do lines[#lines+1] = L end
      if overlap_cnt > #examples then
        lines[#lines+1] = string.format("  ...and %d more.", overlap_cnt - #examples)
      end
    end
    msg(table.concat(lines, "\n"))
    return
  end

  -- Pass 2: no overlaps → perform copy
  local copied = 0
  for _, tr in ipairs(children) do
    if tr then
      local n = r.CountTrackMediaItems(tr)
      for i = 0, n - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        if it then
          if r.GetMediaItemInfo_Value(it, "B_MUTE") == 0 then
            local tk = r.GetActiveTake(it)
            if not (tk and r.GetMediaItemTakeInfo_Value(tk, "B_MUTE") == 1) then
              local new_item = copy_item_by_chunk(it, parent)
              if new_item then copied = copied + 1 end
            end
          end
        end
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock2(0, "Copy unmuted child items to parent (no overlaps)", -1)

  local lines = {}
  lines[#lines+1] = string.format("Parent: %s", parent_name ~= "" and parent_name or "(unnamed)")
  lines[#lines+1] = string.format("Children: %d track(s)", #children)
  lines[#lines+1] = string.format("Scanned items: %d", scanned)
  lines[#lines+1] = string.format("Copied: %d", copied)
  msg(table.concat(lines, "\n"))
end

main()
