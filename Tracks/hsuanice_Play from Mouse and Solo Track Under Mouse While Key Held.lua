--[[
@description Play from Mouse and Solo Track Under Mouse While Key Held (pinned tracks aware)
@version 26.1028.2147pre1
@author hsuanice
@changelog
  - First release: hold the shortcut to play from the mouse and solo the track under it (pinned tracks aware); release to stop and restore solo.
@about
  # Play from Mouse and Solo Track Under Mouse While Key Held

  Hold the shortcut: playback starts from the mouse position and the track under the mouse
  is soloed. Release the shortcut: playback stops and every track's solo goes back to what
  it was. Works like SWS/BR "Play from mouse cursor position and solo item and track under
  mouse for the duration", but finds the track with REAPER's own hit test, so pinned tracks
  (Pin track to top of arrange view) give the right track.

  - Mouse over an item: its track is soloed. When that item is selected, the tracks of all
    selected items are soloed.
  - Mouse over an empty lane or a track panel: that track is soloed.
  - Solo uses the solo mode of REAPER's preferences (e.g. solo in place). Track grouping
    and selection ganging do not spread the solo.
  - The edit cursor does not move; on stop the play cursor goes back to it, as with SWS.
  - Over a track panel (no timeline position under the mouse) playback starts from the
    edit cursor.
  - Item mute is never changed, and no undo point is added.

  Requires js_ReaScriptAPI (key hold detection) and SWS (mouse position).

  ## Suggested shortcuts
  None: pick any key that is free in your setup. Shortcuts are suggestions only — nothing is
  assigned automatically.

  Inspired by SWS/BR "Play from mouse cursor position and solo item and track under mouse
  for the duration" (_BR_CONT_PLAY_MOUSE_SOLO_ITEM, by Breeder, SWS Extension).
  Hold-the-shortcut detection follows Sexan's "VT_SWIPE to Comp HOLD" (Virtual Track,
  Sexan_Scripts). Designed and tested by hsuanice; written with AI (Claude Code).
--]]
local r = reaper
local TITLE = "Play from Mouse and Solo Track Under Mouse"

if not (r.JS_VKeys_GetState and r.JS_VKeys_Intercept and r.BR_PositionAtMouseCursor) then
  r.MB("This script needs js_ReaScriptAPI and SWS.\n\n"
    .. "Please install them with ReaPack (Extensions > ReaPack > Browse packages).", TITLE, 0)
  return
end

-- Tracks to solo: the item's track (all selected items' tracks when the item is selected),
-- else the track under the mouse. GetItemFromPoint / GetTrackFromPoint follow pinned tracks.
local function target_tracks()
  local x, y = r.GetMousePosition()
  local list, seen = {}, {}
  local function add(tr)
    if tr and not seen[tr] and tr ~= r.GetMasterTrack(0) then
      seen[tr] = true
      list[#list + 1] = tr
    end
  end
  local item = r.GetItemFromPoint(x, y, true)
  if item then
    if r.IsMediaItemSelected(item) then
      for i = 0, r.CountSelectedMediaItems(0) - 1 do
        add(r.GetMediaItem_Track(r.GetSelectedMediaItem(0, i)))
      end
    else
      add(r.GetMediaItem_Track(item))
    end
  else
    add(r.GetTrackFromPoint(x, y))
  end
  return list
end

-- Start playback at t without moving the edit cursor (as SWS does)
local function play_from(t)
  if r.GetPlayState() & 1 == 1 then r.OnStopButton() end
  if t then
    local edit = r.GetCursorPosition()
    r.SetEditCurPos(t, false, false)
    r.OnPlayButton()
    r.SetEditCurPos(edit, false, false)
  else
    r.OnPlayButton()
  end
end

-- Hold: run until every key is released (pattern from Sexan's "VT_SWIPE to Comp HOLD":
-- JS_VKeys state since launch, keys intercepted meanwhile)
local VK_LO, VK_HI = 8, 0xFE
-- Modifier keys do not keep playback alive: Shift, Ctrl, Alt, Win (left / right variants)
local VK_MOD = { [0x10] = true, [0x11] = true, [0x12] = true, [0x5B] = true, [0x5C] = true,
  [0xA0] = true, [0xA1] = true, [0xA2] = true, [0xA3] = true, [0xA4] = true, [0xA5] = true }

local start = r.time_precise()
local t = r.BR_PositionAtMouseCursor(false)
if not t or t < 0 then t = nil end
local targets = target_tracks()

-- remember every track's solo, solo only the targets
local saved = {}
r.PreventUIRefresh(1)
if #targets > 0 then
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local s = r.GetMediaTrackInfo_Value(tr, "I_SOLO")
    saved[tr] = s
    if s ~= 0 then r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0) end
  end
  for _, tr in ipairs(targets) do
    r.SetTrackUISolo(tr, 1, 3)  -- 1: solo mode from preferences; 3: no grouping, no ganging
  end
end
r.PreventUIRefresh(-1)
play_from(t)

local intercepted, done = true, false
local function finish()
  if done then return end
  done = true
  if intercepted then intercepted = false; r.JS_VKeys_Intercept(-1, -1) end
  r.OnStopButton()
  r.PreventUIRefresh(1)
  for tr, s in pairs(saved) do
    if r.ValidatePtr(tr, "MediaTrack*") and r.GetMediaTrackInfo_Value(tr, "I_SOLO") ~= s then
      r.SetMediaTrackInfo_Value(tr, "I_SOLO", s)
    end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
end
r.JS_VKeys_Intercept(-1, 1)
r.atexit(finish)

local function step()
  local st = r.JS_VKeys_GetState(start - 0.5)
  for vk = VK_LO, VK_HI do
    if not VK_MOD[vk] and st:byte(vk) ~= 0 then
      r.defer(step)
      return
    end
  end
  finish()
end
step()
