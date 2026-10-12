--[[
@description Show/Hide TCP children of selected folder parents, or of the parent of selected children
@version 26.1012.1024
@author hsuanice
@changelog
  - First release in the hsuanice/ReaScripts repository.
  - Comments translated to English.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
    Toggle TCP folder children efficiently:
    - If a selected track is a folder parent, toggle its TCP children visibility.
    - If a selected track is a child, find its nearest folder parent and toggle that one.
    - Multi-selection supported with de-duplication. No full-project scan. Designed for very large sessions.

  ## Suggested shortcuts
  - Show Hide Tracks of Selected Parent or Childred Folder Tracks in TCP: Shift+F

  Shortcuts are suggestions only — nothing is assigned automatically. macOS names; on Windows Cmd = Ctrl, Option = Alt, Control = Win.
--]]
local r = reaper

local function is_folder(tr)
  -- I_FOLDERDEPTH: 1=track is a folder parent
  return r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") > 0
end

local function get_parent(tr)
  -- P_PARTRACK : MediaTrack* (read-only). Can be NULL/0 when no parent.
  local p = r.GetMediaTrackInfo_Value(tr, "P_PARTRACK")
  -- 0 is truthy in Lua, so check that the value is userdata
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
  local seen = {} -- de-duplicate by pointer string
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
r.TrackList_AdjustWindows(false) -- refresh the TCP immediately
r.UpdateArrange()
r.Undo_EndBlock("Toggle TCP show/hide of selected parent(s) or parents of selected children", -1)
