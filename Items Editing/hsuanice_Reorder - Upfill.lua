--[[
@description hsuanice_Reorder - Upfill
@version 26.1012.0736
@author hsuanice
@noindex
@changelog
  - Released as part of the 26.1012.0736 package update.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Runs the Upfill action using preferences saved in
  "hsuanice_Reorder or sort selected items vertically.lua".
--]]
local r = reaper
local source = debug.getinfo(1, "S").source
local script_path = source:sub(2)
local script_dir = script_path:match("^(.*[/\\])") or ""
local main_script = script_dir .. "hsuanice_Reorder or sort selected items vertically.lua"
local namespace = "hsuanice_ReorderSort_Prefs"

r.SetExtState(namespace, "run_action", "upfill", false)
local ok, err = pcall(dofile, main_script)
if not ok then
  r.SetExtState(namespace, "run_action", "", false)
  r.ShowMessageBox(tostring(err), "Upfill wrapper error", 0)
end