--[[
@description Hover Mode - Toggle Hover Mode (Syncable)
@version 0.1
@author hsuanice

@about
  Toggles Hover Mode (mouse vs. edit cursor) for hsuanice's hover editing tools.  
  Uses ExtState: hsuanice_TrimTools / HoverMode.  
  Maintains toolbar toggle state and can sync with other toggle scripts.

  💡 This script is extensible: you can sync it with other toggle scripts (e.g., TJF, LKC).
    To add them:
      1. Open Action List
      2. Locate the script (e.g., "TJF Hover Mode Toggle")
      3. Right-click → "Copy selected action command ID"
      4. Paste it into the USER CONFIG: Sync with other toggle scripts table below.

  Based on or inspired by:
    • TJF: Hover Mode Toggle — Script: TJF Hover Mode Toggle.lua  
@changelog
  v0.1 - Beta release with ExtState and sync support.
--]]

-- === MAIN EXTSTATE TOGGLE ===
local section = "hsuanice_TrimTools"
local key = "HoverMode"

-- Get toggle state of this script
local _, _, sectionID, cmdID = reaper.get_action_context()
local current = reaper.GetToggleCommandStateEx(sectionID, cmdID)
local new_state = (current == 1) and 0 or 1
local new_ext = (new_state == 1) and "true" or "false"

-- Set new ExtState value (persist = true)
reaper.SetExtState(section, key, new_ext, true)

-- === USER CONFIG: Sync with other toggle scripts ===
local synced_toggle_commands = {
  "_RS7c63ddf7171c4cad70a2a5aa14943b5188b93d74", -- ex. TJF Hover Mode Toggle
  "_RS8277b238cd7341ba4a3c9ff870f30876ce76160b", -- ex. LKC HOVER EDIT Toggle
}

-- === Force sync external toggle scripts ===
local function SetCommandState(cmd_id, desired)
  if reaper.GetToggleCommandState(cmd_id) ~= desired then
    reaper.Main_OnCommand(cmd_id, 0)
  end
end

for _, cmd_str in ipairs(synced_toggle_commands) do
  local cmd_id = reaper.NamedCommandLookup(cmd_str)
  if cmd_id ~= 0 then
    SetCommandState(cmd_id, new_state)
  end
end

-- === Update toolbar toggle button ===
reaper.SetToggleCommandState(sectionID, cmdID, new_state)
reaper.RefreshToolbar2(sectionID, cmdID)

-- === Required for toggle scripts ===
reaper.defer(function() end)
