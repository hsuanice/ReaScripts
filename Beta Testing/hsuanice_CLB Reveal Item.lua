--[[
@description CLB - Reveal Item in Conform List Browser (wrapper)
@version 261010.0021
@author hsuanice
@about
  Standalone wrapper for hsuanice_Conform List Browser.lua's reverse
  link — select an item in Reaper, run this (e.g. via a shortcut), and
  CLB jumps to that item's event row(s) in its list.

  How it works:
  - Same heartbeat/pending_action pattern as hsuanice_CLB Load From
    Reaper.lua: if CLB is running, sets pending_action = "reveal_item"
    and CLB runs CLB.reveal_reaper_selection() on its next frame.
  - One selected item: if not linked yet, it's matched on the spot (same
    4-TC rules as Link Reaper Items) and linked — save the .clb to keep it.
  - Several selected items: already-linked ones only, all their events
    get selected (unlinked ones are counted — use Link first).
  - Needs an event list already loaded in CLB, so when CLB isn't open
    this only offers to open it (load your list, then run this again).
  - For hands-free use, CLB's own "Follow Reaper" checkbox does the
    same thing automatically on every selection change.

  Requires: hsuanice_Conform List Browser.lua already added to Reaper's
  Action List at least once (so its command ID below resolves).
@changelog
  v261010.0021 - Several selected items: reveals all their linked events (CLB
    v261010.0021+).
  v261009.1823 - Initial release.
]]--

-- CLB's own Action List command ID — same value as in the other CLB
-- wrappers; update all of them if CLB is ever re-added to the Action
-- List under a different entry.
local CLB_COMMAND_ID_STR = "_RScb9896c033237f3e546353355015a27303d4a73b"
local TITLE = "CLB Reveal Item"

if reaper.CountSelectedMediaItems(0) == 0 then
  reaper.ShowMessageBox(
    "No item selected in Reaper.\n\nSelect an item on the timeline first.",
    TITLE, 0)
  return
end

local EXT_NS = "hsuanice_ConformListBrowser"
local is_running = reaper.GetExtState(EXT_NS, "is_running") == "1"

if is_running then
  reaper.SetExtState(EXT_NS, "pending_action", "reveal_item", false)
  return
end

local choice = reaper.ShowMessageBox(
  "Conform List Browser isn't open.\n\n" ..
  "Revealing needs an event list already loaded in CLB.\n" ..
  "Open CLB now? (Then load your .clb and run this again.)",
  TITLE, 4) -- Yes/No
if choice ~= 6 then return end -- 6 = Yes

local cmd_id = reaper.NamedCommandLookup(CLB_COMMAND_ID_STR)
if not cmd_id or cmd_id == 0 then
  reaper.ShowMessageBox(
    "Could not resolve CLB's command ID (" .. CLB_COMMAND_ID_STR .. ").\n\n" ..
    "Make sure hsuanice_Conform List Browser.lua has been added to\n" ..
    "Reaper's Action List at least once.",
    TITLE, 0)
  return
end

reaper.Main_OnCommand(cmd_id, 0)
