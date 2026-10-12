--[[
@description CLB - Reveal Item in Conform List Browser (wrapper)
@version 26.1012.1641
@author hsuanice
@noindex
@changelog
  - Renamed to "Conform List Browser - CLB Reveal Item" (was "CLB Reveal Item") as part of the 2026-10-12 naming clean-up.
@about
  Standalone wrapper for hsuanice_Conform List Browser - CLB.lua's reverse
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

  Requires: hsuanice_Conform List Browser - CLB.lua already added to Reaper's
  Action List at least once (so its command ID below resolves).
--]]
-- Find CLB's Action List command ID from its file path (CLB is installed next
-- to this wrapper), so it works on any machine and install folder.
-- AddRemoveReaScript returns the existing ID when CLB is already registered
-- (and registers it otherwise).
local CLB_SCRIPT = (debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "") .. "hsuanice_Conform List Browser - CLB.lua"
local function resolve_clb_command_id()
  if not reaper.file_exists(CLB_SCRIPT) then return 0 end
  return reaper.AddRemoveReaScript(true, 0, CLB_SCRIPT, true)
end
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

local cmd_id = resolve_clb_command_id()
if not cmd_id or cmd_id == 0 then
  reaper.ShowMessageBox(
    "Could not find Conform List Browser:\n" .. CLB_SCRIPT .. "\n\n" ..
    "Make sure hsuanice_Conform List Browser - CLB.lua has been added to\n" ..
    "Reaper's Action List at least once.",
    TITLE, 0)
  return
end

reaper.Main_OnCommand(cmd_id, 0)
