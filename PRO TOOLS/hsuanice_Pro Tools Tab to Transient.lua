-- @description hsuanice_Pro Tools Tab to Transient
-- @version 0.1.0 [260418.1120]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Replicates Pro Tools: **Tab to Transient** toggle
--
--   When ON:  Tab moves to next transient (item edges + internal peaks)
--   When OFF: Tab moves to next item edge only
--
--   Other scripts read this toggle state via:
--     reaper.NamedCommandLookup("_RS<this_script_hash>")
--     reaper.GetToggleCommandStateEx(0, cmd_id)
--
--   - Mac shortcut (PT) : Command + Option + Tab
--   - Tags              : Editing, Options menu
--
-- @changelog
--   0.1.0 [260418.1120]
--     - Initial release

local r = reaper
local cmd_id = ({r.get_action_context()})[4]
local state = r.GetToggleCommandStateEx(0, cmd_id)

if state ~= 1 then state = 1 else state = 0 end

r.SetToggleCommandState(0, cmd_id, state)
r.RefreshToolbar2(0, cmd_id)
r.defer(function() end)  -- keep script alive to maintain toggle state
