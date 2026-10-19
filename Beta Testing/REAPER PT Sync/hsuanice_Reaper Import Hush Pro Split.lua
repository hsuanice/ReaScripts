--[[
@description Import Hush Pro Split - bring Hush Pro's dialog / reverb / noise files back from Pro Tools
@version 26.1019.1046
@author hsuanice
@noindex  (kept in the repository as a backup; local REAPER <> Pro Tools tools, not offered on ReaPack)
@about
  Companion of "hsuanice_Reaper Spot to Pro Tools.lua" (REAPER <> PT Sync, local tool).
  Normally the Hush Pro Monitor window (opened by Spot to Pro Tools) imports automatically; run
  this by hand when the monitor was cancelled. It empties the Hush Pro output folder:
    - "<stem>.dup1-HshSplt_NN.wav" -> track "Dialog"
    - "<stem>.dup2-HshSplt_NN.wav" -> track "Reverb"
    - "<stem>.dup3-HshSplt_NN.wav" -> track "Noise"
      moved into the project media folder (where Spot to Pro Tools stages its files) and
      placed at the timecode stored in each file (BWF Time Reference), full length, on three
      NEW tracks at the same folder level as the source item's track (found from the file name:
      source name + "__pt<sample position>"); existing tracks with these names are never used.
    - Hush Pro's copy of the original ("<clip name>-HshSplt_NN.wav", no "dupN"): moved to the
      Trash only when its audio matches the file sent to Pro Tools (same length, channels and
      timecode, every sample within -120 dB); otherwise it is moved like the others.
    - Any other file in the folder is moved to the project media folder as well.

  Files are moved (copy, size check, delete), never overwritten: a name that already exists
  gets " (2)", " (3)" ... Track / item changes are one undo point per group; file moves are not
  undoable. macOS (Finder is used for the Trash). Uses "hsuanice_Reaper Hush Pro Import Core.lua".

  Written with Claude Code (AI); designed and tested by hsuanice.
--]]

local r = reaper
local TITLE = "Import Hush Pro Split"
local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
local C = dofile(DIR .. "hsuanice_Reaper Hush Pro Import Core.lua")
local function msg(s) r.ShowConsoleMsg(tostring(s) .. "\n") end

local function main()
  local dest = r.GetProjectPath("")
  local _, proj_file = r.EnumProjects(-1, "")
  if not proj_file or proj_file == "" or dest == "" then
    r.MB("Please save the project first: the files are moved into its media folder.", TITLE, 0)
    return
  end
  r.RecursiveCreateDirectory(dest, 0)
  local files = C.list_files(C.HUSH_DIR)
  if #files == 0 then
    r.MB("The Hush Pro folder is empty:\n" .. C.HUSH_DIR, TITLE, 0)
    return
  end
  local groups, order, originals, others = C.classify(files)
  r.ClearConsole()
  msg("=== " .. TITLE .. " ===")
  msg("From: " .. C.HUSH_DIR)
  msg("To:   " .. dest)
  local report, warnings, moved = {}, {}, 0
  local function add(rep, warn)
    for _, l in ipairs(rep or {}) do report[#report + 1] = l end
    for _, w in ipairs(warn or {}) do warnings[#warnings + 1] = w end
  end
  for _, stem in ipairs(order) do
    local rep, warn = C.import_group(stem, groups[stem], dest)
    add(rep, warn)
    for _ in pairs(groups[stem]) do moved = moved + 1 end
  end
  local rep, warn, trashed = C.handle_originals(originals, order, dest, true)
  add(rep, warn)
  for _, name in ipairs(others) do
    local new_path, err = C.move_file(C.join(C.HUSH_DIR, name), dest)
    if new_path then moved = moved + 1; report[#report + 1] = "moved  " .. name
    else warnings[#warnings + 1] = name .. ": " .. tostring(err) end
  end
  for _, l in ipairs(report) do msg("  " .. l) end
  for _, w in ipairs(warnings) do msg("  ! " .. w) end
  r.MB(string.format("%d split group%s imported (Dialog / Reverb / Noise), %d file%s moved, %d original cop%s moved to the Trash.%s",
    #order, #order == 1 and "" or "s", moved, moved == 1 and "" or "s", trashed, trashed == 1 and "y" or "ies",
    #warnings > 0 and string.format("\n\n%d warning%s - see the console.", #warnings, #warnings == 1 and "" or "s") or ""), TITLE, 0)
end

main()
