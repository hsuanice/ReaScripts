-- @description hsuanice_PT_SelectionSync — Selection Sync Library
-- @version 0.1.7 [260421.1214]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Shared library for PT2Reaper scripts.
--   Call Sync.notify() after any programmatic selection change.
--
-- @changelog
--   0.1.7 [260421.1214]
--     - Fix: cursor_follow() skips item positions when razor is present —
--       prevents cursor jumping to item start instead of selection start
--   0.1.6 [260416.1355]
--     - Fix: cursor_follow() only scrolls view if cursor target is
--       outside the current arrange view — prevents unwanted view jump
--   0.1.5 [260415.1629]
--     - Fix: link_timeline_active() reads 40621 native state directly
--     - Fix: razor areas included in time selection sync
--   0.1.4 [260415.1620]
--     - Add: cursor_follow(), link_timeline check by script name
--   0.1.3 [260415.1615]
--     - Fix: treat toggle_state -1 as active
--   0.1.2 [260415.1610]
--     - Use NamedCommandLookup + GetToggleCommandStateEx
--   0.1.1 [260415.1605]
--     - Always sync without ExtState check
--   0.1.0 [260415.1600]
--     - Initial release

local M = {}

local HASH_ITEM_TIME   = "_RS2b504b790607fea41863a2e7e5a2de5aca8fa089"
local HASH_RAZOR_ITEM  = "_RS6f4e0dfffa0b2d8dbfb1d1f52ed8053bfb935b93"
local HASH_TRACK_RAZOR = "_RScb810d93e985a5df273b63589ec315d81fa18529"

local function link_timeline_active()
  return reaper.GetToggleCommandStateEx(0, 40621) == 1
end

local function is_active(rs_hash)
  local cmd_id = reaper.NamedCommandLookup(rs_hash)
  if cmd_id == 0 then return false end
  local state = reaper.GetToggleCommandStateEx(0, cmd_id)
  return state == 1 or state == -1
end

local function sync_item_to_time()
  local r = reaper
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then return end
  local min_pos = math.huge
  local max_end = -math.huge
  for i = 0, n - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local pos  = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local len  = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    if pos < min_pos then min_pos = pos end
    if pos + len > max_end then max_end = pos + len end
  end
  r.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
end

local function sync_razor_to_time()
  local r = reaper
  local min_pos = math.huge
  local max_end = -math.huge
  local found = false
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, razor_str = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor_str and razor_str ~= "" then
      local toks = {}
      for t in razor_str:gmatch("%S+") do toks[#toks+1] = t end
      for i = 1, #toks - 2, 3 do
        local s = tonumber(toks[i])
        local e = tonumber(toks[i+1])
        if s and e then
          found = true
          if s < min_pos then min_pos = s end
          if e > max_end then max_end = e end
        end
      end
    end
  end
  if found then
    r.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
  end
end

local function get_selection_start()
  local r = reaper
  local sel_start = math.huge
  local has_razor = false
  for ti = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, ti)
    local _, razor_str = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if razor_str and razor_str ~= "" then
      has_razor = true
      local toks = {}
      for t in razor_str:gmatch("%S+") do toks[#toks+1] = t end
      for i = 1, #toks - 2, 3 do
        local s = tonumber(toks[i])
        if s and s < sel_start then sel_start = s end
      end
    end
  end
  -- Item positions only when no razor — with a razor, items may span far left of the
  -- selection zone and would pull the cursor away from the actual selection start.
  if not has_razor then
    for i = 0, r.CountSelectedMediaItems(0) - 1 do
      local item = r.GetSelectedMediaItem(0, i)
      local pos  = r.GetMediaItemInfo_Value(item, "D_POSITION")
      if pos < sel_start then sel_start = pos end
    end
  end
  local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if te > ts and ts < sel_start then sel_start = ts end
  return sel_start < math.huge and sel_start or nil
end

-- Move edit cursor to selection start, scroll ONLY if outside current view
function M.cursor_follow()
  if not link_timeline_active() then return end
  local pos = get_selection_start()
  if not pos then return end

  -- Check if pos is within current arrange view
  local view_start, view_end = reaper.BR_GetArrangeView(0)
  local in_view = (pos >= view_start) and (pos <= view_end)

  -- scroll=true only if cursor target is outside view
  reaper.SetEditCurPos(pos, not in_view, false)
end

function M.notify()
  local r = reaper
  r.PreventUIRefresh(1)

  if is_active(HASH_ITEM_TIME) then
    sync_item_to_time()
  end

  if is_active(HASH_RAZOR_ITEM) or is_active(HASH_TRACK_RAZOR) then
    if reaper.CountSelectedMediaItems(0) == 0 then
      sync_razor_to_time()
    end
  end

  M.cursor_follow()

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

function M.any_link_active()
  return is_active(HASH_ITEM_TIME)
      or is_active(HASH_RAZOR_ITEM)
      or is_active(HASH_TRACK_RAZOR)
end

function M.item_time_active()     return is_active(HASH_ITEM_TIME)    end
function M.razor_item_active()    return is_active(HASH_RAZOR_ITEM)   end
function M.track_razor_active()   return is_active(HASH_TRACK_RAZOR)  end
function M.link_timeline_active() return link_timeline_active()       end

return M
