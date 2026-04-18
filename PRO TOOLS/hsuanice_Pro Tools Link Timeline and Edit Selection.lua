-- @description hsuanice_Pro Tools Link Timeline and Edit Selection
-- @version 0.1.5 [260415.1629]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   # hsuanice Pro Tools Keybindings for REAPER
--
--   Replicates Pro Tools: **Link Timeline and Edit Selection**
--
--   ## Behaviour
--   - Toggles Reaper's "Loop points linked to time selection" (40621)
--   - When ON: edit cursor follows selection start after any selection move
--     (Nudge, etc. will read this toggle to move the cursor)
--   - Toggle state is readable by other scripts via:
--       reaper.GetToggleCommandStateEx(0, reaper.NamedCommandLookup("_THIS_SCRIPT_RS_HASH"))
--
--   ## Mapping
--   - Reaper action : Options: Toggle loop points linked to time selection
--   - Command ID    : 40621
--   - Mac shortcut (PT) : Shift + /
--   - Tags              : Editing, Options menu
--
-- @changelog
--   0.1.0 [260415.1629]
--     - Initial release

local r = reaper

-- Toggle the native Reaper action
r.Main_OnCommand(40621, 0)

-- Mirror the native toggle state onto this script's own toggle
-- so other scripts can read our state via GetToggleCommandStateEx
local native_state = r.GetToggleCommandStateEx(0, 40621)
local cmd_id = ({r.get_action_context()})[4]
r.SetToggleCommandState(0, cmd_id, native_state)
r.RefreshToolbar2(0, cmd_id)
