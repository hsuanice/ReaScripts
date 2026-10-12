--[[
@description CLB - Load From Reaper (wrapper)
@version 26.1012.1641
@author hsuanice
@noindex
@changelog
  - Renamed to "Conform List Browser - CLB Load from REAPER" (was "CLB Load From Reaper") as part of the 2026-10-12 naming clean-up.
@about
  Standalone wrapper for hsuanice_Conform List Browser - CLB.lua's "Load From
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

  Requires: hsuanice_Conform List Browser - CLB.lua already added to Reaper's
  Action List at least once (so its command ID below resolves) — see
  CLB_COMMAND_ID below.
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

local cmd_id = resolve_clb_command_id()
if not cmd_id or cmd_id == 0 then
  reaper.ShowMessageBox(
    "Could not find Conform List Browser:\n" .. CLB_SCRIPT .. "\n\n" ..
    "Make sure hsuanice_Conform List Browser - CLB.lua has been added to\n" ..
    "Reaper's Action List at least once.",
    "CLB Load From Reaper", 0)
  return
end

reaper.SetExtState(EXT_NS, "pending_action", "load_from_reaper", false)
reaper.Main_OnCommand(cmd_id, 0)
