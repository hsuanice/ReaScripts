--[[
@description Delete Selected Tracks (safe: skip prompt if empty)
@version 0.1.0
@author hsuanice
@about
  Delete selected tracks with safety:
    • If ALL selected tracks are empty (no items, no automation/envelope data), delete immediately with no prompt.
    • If ANY selected track contains items or automation, show a summary and ask for confirmation.
  Notes:
    - Master track is ignored by REAPER's CountSelectedTracks(), so no special handling is required.
    - "Automation present" means: any track envelope has ≥1 point or ≥1 automation item.

@changelog
  v0.1.0 - Initial release.
]]

local r = reaper

local function collect_selected_tracks()
  local t = {}
  local n = r.CountSelectedTracks(0) -- master ignored
  for i = 0, n-1 do
    t[#t+1] = r.GetSelectedTrack(0, i)
  end
  return t
end

local function track_has_automation(tr)
  local env_count = r.CountTrackEnvelopes(tr)
  for i = 0, env_count-1 do
    local env = r.GetTrackEnvelope(tr, i)
    if env then
      -- any automation items?
      if r.CountAutomationItems(env) > 0 then
        return true
      end
      -- any underlying envelope points?
      if r.CountEnvelopePointsEx(env, -1) > 0 then
        return true
      end
    end
  end
  return false
end

local function summarize_selection(tracks)
  local total_items = 0
  local tracks_with_auto = 0

  for _, tr in ipairs(tracks) do
    local item_count = r.CountTrackMediaItems(tr)
    total_items = total_items + item_count
    if track_has_automation(tr) then
      tracks_with_auto = tracks_with_auto + 1
    end
  end

  return total_items, tracks_with_auto
end

local function delete_tracks(tracks)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  -- delete from bottom of list is safe even with pointers; still do reverse to mimic index-safe patterns
  for i = #tracks, 1, -1 do
    r.DeleteTrack(tracks[i])
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Delete selected tracks (safe)", -1)
end

-- === Entry ===
local sel_tracks = collect_selected_tracks()
if #sel_tracks == 0 then
  r.ShowMessageBox("沒有選取任何軌道。", "Delete Selected Tracks", 0)
  return
end

local total_items, tracks_with_auto = summarize_selection(sel_tracks)

if total_items == 0 and tracks_with_auto == 0 then
  -- All empty: delete without warning
  delete_tracks(sel_tracks)
  return
end

-- Need confirmation: build a concise summary
local msg = string.format(
  "選取的軌道中包含內容：\n\n• Items：%d 個\n• 含自動化資料的軌道：%d 軌\n\n仍要刪除所選軌道嗎？",
  total_items, tracks_with_auto
)

-- 4 = MB_YESNO, return 6 if Yes
local ret = r.ShowMessageBox(msg, "Delete Selected Tracks — 確認", 4)
if ret == 6 then
  delete_tracks(sel_tracks)
else
  -- User canceled: do nothing
end

