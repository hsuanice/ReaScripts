--[[
@description Hover Mode - Toggle Hover Mode (Syncable)
@version 250927_1532
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
  
  Features:
  - Designed for fast, keyboard-light workflows.
  - Supports Hover Mode via shared ExtState for cursor-aware actions.
  
  References:
  - REAPER ReaScript API (Lua)
  
  Note:
  - This is a 0.1 beta release for internal testing.
  
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v250927_1532 - First-run sync: if saved ExtState != toolbar state, apply saved state without flipping (idempotent on first click after launch). Subsequent clicks toggle normally.
  v250927_1520 - Persist toggle across sessions: read initial state from ExtState (hsuanice_TrimTools / HoverMode) and only then toggle; accept "true/1/on" as ON. No behavior change if ExtState missing.
  v0.1 - Beta release
--]]
-- === MAIN EXTSTATE TOGGLE ===
local section = "hsuanice_TrimTools"
local key = "HoverMode"


-- Get toggle state of this script (initialize from ExtState if present)
local _, _, sectionID, cmdID = reaper.get_action_context()

local function parse_bool(s)
  if not s then return false end
  s = tostring(s):lower()
  return (s == "true" or s == "1" or s == "on" or s == "yes")
end

local ext = reaper.GetExtState(section, key)
local has_ext = (ext ~= nil and ext ~= "")

-- If ExtState exists, honor it as the desired state; otherwise use toolbar state as baseline
local desired -- nil if not defined
if has_ext then desired = parse_bool(ext) and 1 or 0 end

-- === USER CONFIG: Sync with other toggle scripts ===
local synced_toggle_commands = {
  "_RS7c63ddf7171c4cad70a2a5aa14943b5188b93d74", -- ex. TJF Hover Mode Toggle
  "_RS8277b238cd7341ba4a3c9ff870f30876ce76160b", -- ex. LKC HOVER EDIT Toggle
}

-- === Force sync external toggle scripts ===
local function SetCommandState(cmd_id, want)
  if reaper.GetToggleCommandState(cmd_id) ~= want then
    reaper.Main_OnCommand(cmd_id, 0)
  end
end

local current_toolbar = reaper.GetToggleCommandStateEx(sectionID, cmdID)

if desired ~= nil and current_toolbar ~= desired then
  -- First run in a session or toolbar out of sync → just APPLY saved state (no toggle)
  local apply_state = desired
  local apply_ext   = (apply_state == 1) and "true" or "false"
  
  -- Persist (keeps same value) and sync others
  reaper.SetExtState(section, key, apply_ext, true)
  
  -- === USER CONFIG / external toggles ===
  for _, cmd_str in ipairs(synced_toggle_commands or {}) do
    local cmd_id = reaper.NamedCommandLookup(cmd_str)
    if cmd_id ~= 0 then SetCommandState(cmd_id, apply_state) end
  end
  
  -- Update toolbar and exit
  reaper.SetToggleCommandState(sectionID, cmdID, apply_state)
  reaper.RefreshToolbar2(sectionID, cmdID)
  return reaper.defer(function() end)
end

-- Normal toggle path (either no ExtState yet, or already in sync)
local new_state = (current_toolbar == 1) and 0 or 1
local new_ext   = (new_state == 1) and "true" or "false"

-- Persist new state
reaper.SetExtState(section, key, new_ext, true)

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
