-- @description hsuanice_Pro Tools Move Edit Insertion To Previous Edit
-- @version 0.1.0 [260418.1120]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Replicates Pro Tools: **Move Edit Insertion To Previous Edit** (Shift+Tab)
--
--   ## Behaviour
--   Reads the "Tab to Transient" toggle state:
--   - ON  → moves cursor to previous transient (item edges + internal peaks)
--   - OFF → moves cursor to previous item edge
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

local function get_tab_toggle_state()
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
  return false
end

-- Save current item selection
r.Main_OnCommand(41229, 0)  -- Selection set: Save set #01

-- Select all items in track
r.Main_OnCommand(40421, 0)  -- Item: Select all items in track

-- Move cursor
if get_tab_toggle_state() then
  r.Main_OnCommand(40376, 0)  -- Item navigation: Move cursor to previous transient in items
else
  r.Main_OnCommand(40318, 0)  -- Item navigation: Move cursor left to edge of item
end

-- Restore original item selection
r.Main_OnCommand(41239, 0)  -- Selection set: Load set #01

r.defer(function() end)  -- prevent undo
