-- @description hsuanice_Pro Tools Move Edit Insertion To Next Edit
-- @version 0.1.0 [260418.1120]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Replicates Pro Tools: **Move Edit Insertion To Next Edit** (Tab key)
--
--   ## Behaviour
--   Reads the "Tab to Transient" toggle state:
--   - ON  → moves cursor to next transient (item edges + internal peaks)
--   - OFF → moves cursor to next item edge
--
--   Saves and restores item selection so the user sees no change.
--   Selects all items on current track temporarily to enable navigation.
--
--   - Tags : Editing, Navigation
--
-- @changelog
--   0.1.0 [260418.1120]
--     - Initial release

local r = reaper

-- Get Tab to Transient toggle state
-- RS hash of hsuanice_Pro Tools Tab to Transient.lua
local TAB_TOGGLE_SCRIPT = "_RS<TAB_TOGGLE_HASH>"  -- replaced after first load
local function get_tab_toggle_state()
  -- Search by script name at runtime (hash assigned after first load)
  local section = r.SectionFromUniqueID(0)
  local idx = 0
  while true do
    local cid, cname = r.kbd_enumerateActions(section, idx)
    if cid == 0 and idx > 0 then break end
    if cname and cname:lower():find("pro tools tab to transient", 1, true) then
      return r.GetToggleCommandStateEx(0, cid) == 1
    end
    idx = idx + 1
    if idx > 200000 then break end
  end
  return false  -- default: off
end

-- Save current item selection
r.Main_OnCommand(41229, 0)  -- Selection set: Save set #01

-- Select all items in track (so navigation works regardless of selection)
r.Main_OnCommand(40421, 0)  -- Item: Select all items in track

-- Move cursor
if get_tab_toggle_state() then
  r.Main_OnCommand(40375, 0)  -- Item navigation: Move cursor to next transient in items
else
  r.Main_OnCommand(40319, 0)  -- Item navigation: Move cursor right to edge of item
end

-- Restore original item selection
r.Main_OnCommand(41239, 0)  -- Selection set: Load set #01

r.defer(function() end)  -- prevent undo
