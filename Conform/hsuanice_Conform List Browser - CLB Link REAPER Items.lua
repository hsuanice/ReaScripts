--[[
@description CLB - Link Reaper Items (wrapper)
@version 26.1012.1641
@author hsuanice
@noindex
@changelog
  - Renamed to "Conform List Browser - CLB Link REAPER Items" (was "CLB Link Reaper Items") as part of the 2026-10-12 naming clean-up.
@about
  Standalone wrapper for hsuanice_Conform List Browser - CLB.lua's "Link
  Reaper Items" feature — runnable from REAPER's own Action List with a
  keyboard shortcut.

  How it works:
  - Load the event list (.clb/EDL/XML/AAF) in CLB first, then select
    item(s) on the Reaper timeline and run this.
  - Same heartbeat/pending_action pattern as hsuanice_CLB Load From
    Reaper.lua (see its @about for why Reaper's own toggle state can't
    be used): if CLB is running, sets pending_action =
    "link_reaper_items" and CLB runs CLB.link_reaper_items_selection()
    on its next frame.
  - Unlike Load From Reaper, there's no point launching CLB and linking
    in one go: linking attaches items to an ALREADY LOADED list, and a
    freshly opened CLB has no list loaded yet. So when CLB isn't open,
    this offers to open it, and asks you to load your list and run this
    again.

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
local TITLE = "CLB Link Reaper Items"

local n_sel = reaper.CountSelectedMediaItems(0)
if n_sel == 0 then
  reaper.ShowMessageBox(
    "No items selected in Reaper.\n\nSelect item(s) on the timeline first.",
    TITLE, 0)
  return
end

local EXT_NS = "hsuanice_ConformListBrowser"
local is_running = reaper.GetExtState(EXT_NS, "is_running") == "1"

if is_running then
  reaper.SetExtState(EXT_NS, "pending_action", "link_reaper_items", false)
  return
end

local choice = reaper.ShowMessageBox(
  "Conform List Browser isn't open.\n\n" ..
  "Linking needs an event list already loaded in CLB.\n" ..
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
