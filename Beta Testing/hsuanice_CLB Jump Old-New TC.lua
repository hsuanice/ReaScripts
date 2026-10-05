--[[
@description CLB - Jump Old/New TC (Recut)
@version 261005.1507
@author hsuanice
@about
  Standalone wrapper for hsuanice_Conform List Browser.lua's "CLB Recut"
  track — jumps the REAPER edit cursor between an event's old and new
  position after a DME Recut, the same way Matchbox's own old/new jump
  works, but runnable from REAPER's own Action List with a keyboard
  shortcut (Matchbox's version only works from inside Matchbox itself).

  How it works:
  - CLB.dme_recut_execute (in Conform List Browser.lua) records each
    recut move as a pair of real, empty items on a shared "CLB Recut"
    track: one spanning the OLD (Src TC) range, one spanning the NEW
    (Rec TC) range. Each item's own Notes field ("CLB_JUMP:<seconds>")
    points at its paired position — REAPER project data is the only
    data exchange between the two scripts, no separate file/ExtState
    sync needed.
  - This script finds whichever CLB Recut item the edit cursor currently
    sits inside, reads its paired position, and jumps there — preserving
    exactly where inside the item the cursor was (frame-accurate, not
    just "somewhere in the paired range"), the same way CLB's own
    click-to-jump works (SetEditCurPos + scroll-into-view). Run it again
    from the new position to jump back.
  - If the cursor isn't inside any CLB Recut item, or the track doesn't
    exist yet, shows a short message instead of guessing where to jump.
  - Reads ONLY real REAPER project data (the CLB Recut track's items and
    their Notes) — Conform List Browser.lua itself does NOT need to be
    open for this to work, only the track it already created needs to
    still be in the project.

  Requires: at least one DME Recut run in Conform List Browser.lua (the
  "CLB Recut" track it creates). Phase 1 — single old<->new pair only;
  no multi-version chain, no Compare-mode support yet (Compare's own
  Trimmed/Extended/Moved Apply isn't built, so there's nothing to pair
  there yet either) — see Conform List Browser.lua's own
  CLB.populate_recut_track for the full design note.
@changelog
  v261005.1507 - Jump now preserves the cursor's exact relative position
    within the CLB Recut item (frame-accurate) instead of always landing
    on the paired item's own start.
  v261005.1455 - Initial Phase 1 release.
]]--

local TRACK_NAME = "CLB Recut"

local function find_recut_track()
  local n = reaper.CountTracks(0)
  for i = 0, n - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name == TRACK_NAME then return tr end
  end
  return nil
end

local function find_item_at_cursor(track, cursor_pos)
  local fps = reaper.TimeMap_curFrameRate(0)
  if not fps or fps <= 0 then fps = 24 end
  local tol = 0.5 / fps
  local n = reaper.CountTrackMediaItems(track)
  for i = 0, n - 1 do
    local item = reaper.GetTrackMediaItem(track, i)
    local pos  = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local iend = pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if cursor_pos >= pos - tol and cursor_pos <= iend + tol then
      return item
    end
  end
  return nil
end

local function parse_jump_target(item)
  local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  if not notes then return nil end
  local sec = notes:match("CLB_JUMP:([%-%d%.]+)")
  return sec and tonumber(sec) or nil
end

local function main()
  local track = find_recut_track()
  if not track then
    reaper.ShowMessageBox(
      "No \"CLB Recut\" track found.\n\n"
      .. "Open Conform List Browser and run a DME Recut first — it\n"
      .. "creates this track with the old/new position pairs to jump\n"
      .. "between.",
      "CLB Jump Old/New TC", 0)
    return
  end

  local cursor_pos = reaper.GetCursorPosition()
  local item = find_item_at_cursor(track, cursor_pos)
  if not item then
    reaper.ShowMessageBox(
      "The edit cursor isn't on a \"CLB Recut\" item.\n\n"
      .. "Move it onto one of that track's old/new marker items first,\n"
      .. "then run this again.",
      "CLB Jump Old/New TC", 0)
    return
  end

  local jump_to = parse_jump_target(item)
  if not jump_to then
    reaper.ShowMessageBox(
      "This CLB Recut item has no valid jump target in its Notes.",
      "CLB Jump Old/New TC", 0)
    return
  end

  -- Preserve where inside the item the cursor actually was, rather than
  -- always snapping to the paired item's own start — both sides of a
  -- move always share the same length (see CLB.populate_recut_track's
  -- own doc comment), so offsetting the target by the same amount lands
  -- on the exact corresponding frame, not just "somewhere in that item."
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local offset = cursor_pos - item_pos
  if offset < 0 then offset = 0 end
  if offset > item_len then offset = item_len end

  reaper.SetEditCurPos(jump_to + offset, true, false)
end

main()
