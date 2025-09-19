--[[
@description Show/Hide TCP children of selected folder parents, or of the parent of selected children
@version 0.1.2
@author hsuanice
@about
  Toggle TCP folder children efficiently:
  - If a selected track is a folder parent, toggle its TCP children visibility.
  - If a selected track is a child, find its nearest folder parent and toggle that one.
  - Multi-selection supported with de-duplication. No full-project scan. Designed for very large sessions.
@changelog
  v0.1.2
  - Fix: robust parent detection when no parent (avoid invalid MediaTrack errors).
  - Change: use I_FOLDERCOMPACT for TCP folding (0 normal, 1 collapsed, 2 fully collapsed).
  - Add: multi-select de-duplication, UI refresh guard, Undo block.
  v0.1.1
  - Options draft (not released): MODE/TOPMOST_ANCESTOR.
  v0.1.0
  - Initial minimal toggle from selected parent or parent-of-selected-child.
]]

local r = reaper

local function is_folder(tr)
  -- I_FOLDERDEPTH: 1=track is a folder parent
  return r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") > 0
end

local function get_parent(tr)
  -- P_PARTRACK : MediaTrack* (read-only). Can be NULL/0 when no parent.
  local p = r.GetMediaTrackInfo_Value(tr, "P_PARTRACK")
  -- 在 Lua 裡 0 是 truthy，所以必須檢查型別是否為 userdata
  if type(p) == "userdata" then return p end
  return nil
end

local function toggle_folder_compact(tr)
  -- I_FOLDERCOMPACT: 0=normal, 1=collapsed, 2=fully collapsed
  local s = r.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT")
  local new = (s ~= 0) and 0 or 2
  r.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", new)
end

local function collect_target_parents()
  local targets = {}
  local seen = {} -- 用指標字串去重
  local sel_cnt = r.CountSelectedTracks(0)
  for i = 0, sel_cnt-1 do
    local tr = r.GetSelectedTrack(0, i)
    local parent = is_folder(tr) and tr or get_parent(tr)
    if parent then
      local key = tostring(parent)
      if not seen[key] then
        seen[key] = true
        targets[#targets+1] = parent
      end
    end
  end
  return targets
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local targets = collect_target_parents()
for i = 1, #targets do
  toggle_folder_compact(targets[i])
end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false) -- 立即刷新 TCP
r.UpdateArrange()
r.Undo_EndBlock("Toggle TCP show/hide of selected parent(s) or parents of selected children", -1)
