--[[
@description CLB - Load From Reaper (wrapper)
@version 261007.1708
@author hsuanice
@about
  Standalone wrapper for hsuanice_Conform List Browser.lua's "Load From
  Reaper" feature — runnable from REAPER's own Action List with a
  keyboard shortcut.

  How it works:
  - Select item(s) on the Reaper timeline, then run this (e.g. via a
    shortcut).
  - Checks whether CLB is already running via a heartbeat ExtState flag
    CLB itself sets on startup and clears on exit
    (hsuanice_ConformListBrowser / is_running) — NOT Reaper's own
    GetToggleCommandStateEx, which doesn't work here: confirmed by real
    testing that this script never registers Reaper toggle state at
    all, so that check never reliably reported "running", and the
    wrapper's own Main_OnCommand call kept TOGGLING CLB OFF instead of
    just signaling it (Reaper's standard behavior for re-running an
    already-active deferred script's own command).
      - Already running → sets a one-shot ExtState flag
        (pending_action = "load_from_reaper") and stops. CLB's own main
        loop polls that flag every frame and runs
        CLB.load_from_reaper_selection() itself on its very next frame.
        This script never touches CLB's command in this case, so it can
        never toggle it off.
      - Not running → asks first (CLB isn't just a background daemon;
        opening its window is a visible, undoable-by-closing-it but
        still real action, worth a yes/no rather than silently popping
        it open). If confirmed, sets the same flag, then launches CLB
        via its own known command ID (resolved with NamedCommandLookup
        — hardcoded below; update it if CLB's script is ever re-saved
        under a different Action List entry).

  Requires: hsuanice_Conform List Browser.lua already added to Reaper's
  Action List at least once (so its command ID below resolves) — see
  CLB_COMMAND_ID below.
@changelog
  v261007.1708 - Fix: GetToggleCommandStateEx-based "is it running"
    check (v261007.1640) still toggled CLB off every time, confirmed by
    real testing — CLB never registers Reaper toggle state at all, so
    the check was always false. Replaced with a heartbeat ExtState flag
    CLB itself now sets on startup / clears on exit — the only robust
    "is it running" signal available for a plain reaper.defer() script
    with no toggle-state support. Also changed to ask before launching
    CLB when it isn't already open (user's own request), using CLB's
    own known command ID instead of re-resolving its script path via
    AddRemoveReaScript every time.
  v261007.1640 - Fix: was closing CLB every time it was already open
    (GetToggleCommandStateEx-based check didn't work — see above).
  v261007.1632 - Initial release.
]]--

-- CLB's own Action List command ID — update this if hsuanice_Conform
-- List Browser.lua is ever re-added to the Action List under a
-- different entry (NamedCommandLookup resolves it to a runnable ID).
local CLB_COMMAND_ID_STR = "_RScb9896c033237f3e546353355015a27303d4a73b"

local n_sel = reaper.CountSelectedMediaItems(0)
if n_sel == 0 then
  reaper.ShowMessageBox(
    "No items selected in Reaper.\n\nSelect item(s) on the timeline first.",
    "CLB Load From Reaper", 0)
  return
end

local EXT_NS = "hsuanice_ConformListBrowser"
local is_running = reaper.GetExtState(EXT_NS, "is_running") == "1"

if is_running then
  reaper.SetExtState(EXT_NS, "pending_action", "load_from_reaper", false)
  return
end

local choice = reaper.ShowMessageBox(
  "Conform List Browser isn't open.\n\nOpen it now and load the current selection?",
  "CLB Load From Reaper", 4) -- Yes/No
if choice ~= 6 then return end -- 6 = Yes

local cmd_id = reaper.NamedCommandLookup(CLB_COMMAND_ID_STR)
if not cmd_id or cmd_id == 0 then
  reaper.ShowMessageBox(
    "Could not resolve CLB's command ID (" .. CLB_COMMAND_ID_STR .. ").\n\n" ..
    "Make sure hsuanice_Conform List Browser.lua has been added to\n" ..
    "Reaper's Action List at least once.",
    "CLB Load From Reaper", 0)
  return
end

reaper.SetExtState(EXT_NS, "pending_action", "load_from_reaper", false)
reaper.Main_OnCommand(cmd_id, 0)
