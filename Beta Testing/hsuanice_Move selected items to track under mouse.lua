--[[
@description Move selected items to track under mouse (vertical only, keep timeline position)
@version 260502.1833
@author hsuanice
@about
  Moves the currently selected items (one or many, possibly spanning multiple
  tracks) to the track that the mouse cursor is hovering over. Timeline
  position is preserved — only the vertical (track) position changes.

  Acts as a one-step "vertical cut & paste":
    - No need to cut, scroll, click target track, then paste.
    - Just select items, hover over the target track, run the action.

  Behavior:
    • Scope: operates on the current item selection.
    • The topmost selected track is aligned to the track under the mouse.
      All other selected items keep their relative track offsets, so multi-
      track selections move together as a block.
    • If the destination span exceeds the last track, new empty tracks are
      auto-appended at the bottom of the project so all items have a home.
    • If any moved item would overlap an existing item on its destination
      track, a warning dialog is shown with three options:
        Yes (Insert)    — Insert N empty tracks at the destination so the
                          selection lands on fresh, empty tracks.
        No  (Overwrite) — Trim/split existing items in the overlap range,
                          then place the moved items on top.
        Cancel          — Abort.
    • If the mouse is not over any track (e.g. over TCP empty area, ruler,
      or master), the script does nothing.
    • If the target offset is zero (mouse already on the topmost selected
      track), the script does nothing.

  Notes:
    - Designed for keyboard/mouse-modifier workflow (assign to a shortcut
      and trigger while hovering the destination track).
    - Based on design concepts and iterative testing by hsuanice.
    - Script generated and refined with Claude.

@changelog
  v260502.1833
  - Auto-append tracks at the bottom when the destination span exceeds
    the last existing track.
  - Detect overlap with existing items on destination tracks; prompt user
    with Insert / Overwrite / Cancel.
  - Insert mode: insert N empty tracks at the destination.
  - Overwrite mode: trim, split, or delete existing items inside each
    moved item's time range before placing the moved item.

  v260502.1823
  - Initial release.
--]]

local r = reaper

local item_count = r.CountSelectedMediaItems(0)
if item_count == 0 then return end

local mx, my = r.GetMousePosition()
local target_track = r.GetTrackFromPoint(mx, my)
if not target_track then return end

-- Master track has IP_TRACKNUMBER = -1; ignore it.
local target_idx = math.floor(r.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER")) - 1
if target_idx < 0 then return end

local items = {}
local selected_set = {}
local min_src_idx = math.huge
local max_src_idx = -math.huge
for i = 0, item_count - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  local track = r.GetMediaItem_Track(item)
  local idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  items[#items + 1] = { item = item, src_idx = idx, pos = pos, len = len }
  selected_set[item] = true
  if idx < min_src_idx then min_src_idx = idx end
  if idx > max_src_idx then max_src_idx = idx end
end

local offset = target_idx - min_src_idx
if offset == 0 then return end

for _, e in ipairs(items) do
  e.dest_idx = e.src_idx + offset
end
local max_dest_idx = max_src_idx + offset

local function ranges_overlap(a_pos, a_end, b_pos, b_end)
  return a_pos < b_end and b_pos < a_end
end

-- Group moving items by destination track index
local by_dest = {}
for _, e in ipairs(items) do
  local list = by_dest[e.dest_idx]
  if not list then list = {}; by_dest[e.dest_idx] = list end
  list[#list + 1] = e
end

-- Detect overlap with existing items on destination tracks (existing tracks only)
local total_tracks = r.CountTracks(0)
local has_overlap = false
for didx, list in pairs(by_dest) do
  if didx < total_tracks then
    local tr = r.GetTrack(0, didx)
    local n = r.CountTrackMediaItems(tr)
    for i = 0, n - 1 do
      local ex = r.GetTrackMediaItem(tr, i)
      if not selected_set[ex] then
        local exp = r.GetMediaItemInfo_Value(ex, "D_POSITION")
        local exl = r.GetMediaItemInfo_Value(ex, "D_LENGTH")
        local exe = exp + exl
        for _, m in ipairs(list) do
          if ranges_overlap(m.pos, m.pos + m.len, exp, exe) then
            has_overlap = true
            break
          end
        end
        if has_overlap then break end
      end
    end
    if has_overlap then break end
  end
end

local mode = "move"
if has_overlap then
  local ret = r.ShowMessageBox(
    "Selected items would overlap existing items on the destination track(s).\n\n" ..
    "[Yes]    Insert new empty tracks at the destination\n" ..
    "[No]     Overwrite existing items in the overlap range\n" ..
    "[Cancel] Abort",
    "Move items to track under mouse",
    3
  )
  if ret == 2 then return end
  if ret == 6 then mode = "insert" end
  if ret == 7 then mode = "overwrite" end
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

if mode == "insert" then
  -- Insert N empty tracks at target_idx so the selection lands on fresh tracks.
  -- Existing tracks at original index >= target_idx shift down by N, but item
  -- references are stable, so MoveMediaItemToTrack still works on the right items.
  local n_insert = max_src_idx - min_src_idx + 1
  for i = 0, n_insert - 1 do
    r.InsertTrackAtIndex(target_idx + i, true)
  end
  for _, e in ipairs(items) do
    local new_tr = r.GetTrack(0, e.dest_idx)
    if new_tr then r.MoveMediaItemToTrack(e.item, new_tr) end
  end
else
  -- Append tracks at the bottom if destination exceeds current track count
  while r.CountTracks(0) <= max_dest_idx do
    r.InsertTrackAtIndex(r.CountTracks(0), true)
  end

  if mode == "overwrite" then
    -- Snapshot existing items per destination track (excluding our selection)
    local snapshots = {}
    for didx in pairs(by_dest) do
      local tr = r.GetTrack(0, didx)
      if tr then
        local n = r.CountTrackMediaItems(tr)
        local list = {}
        for i = 0, n - 1 do
          local it = r.GetTrackMediaItem(tr, i)
          if not selected_set[it] then list[#list + 1] = it end
        end
        snapshots[didx] = { track = tr, items = list }
      end
    end
    -- For each moving item, trim/split/delete overlapping existing items
    for _, e in ipairs(items) do
      local snap = snapshots[e.dest_idx]
      if snap then
        local mv_pos = e.pos
        local mv_end = e.pos + e.len
        for _, ex in ipairs(snap.items) do
          if r.ValidatePtr2(0, ex, "MediaItem*") then
            local exp = r.GetMediaItemInfo_Value(ex, "D_POSITION")
            local exl = r.GetMediaItemInfo_Value(ex, "D_LENGTH")
            local exe = exp + exl
            if ranges_overlap(mv_pos, mv_end, exp, exe) then
              if exp >= mv_pos and exe <= mv_end then
                r.DeleteTrackMediaItem(snap.track, ex)
              elseif exp < mv_pos and exe > mv_end then
                local middle = r.SplitMediaItem(ex, mv_pos)
                if middle then
                  r.SplitMediaItem(middle, mv_end)
                  r.DeleteTrackMediaItem(snap.track, middle)
                end
              elseif exp < mv_pos then
                r.SetMediaItemInfo_Value(ex, "D_LENGTH", mv_pos - exp)
              else
                r.SetMediaItemInfo_Value(ex, "D_POSITION", mv_end)
                r.SetMediaItemInfo_Value(ex, "D_LENGTH", exe - mv_end)
              end
            end
          end
        end
      end
    end
  end

  for _, e in ipairs(items) do
    local new_tr = r.GetTrack(0, e.dest_idx)
    if new_tr then r.MoveMediaItemToTrack(e.item, new_tr) end
  end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock("Move selected items to track under mouse", -1)
