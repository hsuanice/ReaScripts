-- RGWH Render — wrapper that calls core.render_selection()

local LIB_PATH = reaper.GetResourcePath()
  .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"

local ok, core_or_err = pcall(dofile, LIB_PATH)
if not ok or type(core_or_err) ~= "table" then
  reaper.ShowMessageBox(
    "Cannot load 'hsuanice_RGWH Core.lua'.\n\nPath:\n" .. LIB_PATH ..
    "\n\nError:\n" .. tostring(core_or_err),
    "RGWH Render", 0)
  return
end

local core = core_or_err
if type(core.render_selection) ~= "function" then
  reaper.ShowMessageBox(
    "RGWH Core loaded but function 'render_selection' is missing.",
    "RGWH Render", 0)
  return
end

local ok_run, err = pcall(core.render_selection)
if not ok_run then
  reaper.ShowMessageBox("RGWH Render failed:\n\n" .. tostring(err), "RGWH Render", 0)
end
