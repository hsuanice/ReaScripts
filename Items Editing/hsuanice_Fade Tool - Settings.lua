--[[
@description Fade Tool - Settings (crossfade and scene cut fade lengths, positions and shapes)
@version 26.1023.1800pre1
@author hsuanice
@noindex
@changelog
  - Initial release.
@about
  The only Fade Tool script that opens a window. The other Fade Tool scripts just read these
  values and run.

  - Lengths are in frames (project frame rate), decimals allowed.
  - Position: before / center / after the cut or the scene edge.
  - Shape: 0 Linear, 1 Equal Power, 2 Slight Concave, 3 Sharp Convex, 4 Sharp Concave, 5 S-Curve.
--]]
-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Fade Tool Core.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

local r = reaper
local FT = dofile(r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Fade Tool Core.lua")
local TITLE = "Fade Tool - Settings"

-- { key, caption, kind }
local FIELDS = {
  { "xfade_frames",     "Crossfade length (frames)",            "len"   },
  { "xfade_align",      "Crossfade position before-center-after", "align" },
  { "xfade_shape",      "Crossfade shape 0-5",                  "shape" },
  { "scene_in_frames",  "Scene fade-in length (frames)",        "len"   },
  { "scene_in_align",   "Scene fade-in position",               "align" },
  { "scene_out_frames", "Scene fade-out length (frames)",       "len"   },
  { "scene_out_align",  "Scene fade-out position",              "align" },
  { "scene_shape",      "Scene fade shape 0-5",                 "shape" },
  { "clear_razor",      "Clear razor after run (y-n)",          "bool"  },
}

local S = FT.load_settings()
local captions, values = {}, {}
for i, f in ipairs(FIELDS) do
  captions[i] = f[2]
  local v = S[f[1]]
  if f[3] == "bool" then v = (v == 1) and "y" or "n" end
  values[i] = tostring(v)
end
captions[#captions + 1] = "extrawidth=80"

local shape_help = {}
for i = 0, 5 do shape_help[#shape_help + 1] = i .. " " .. FT.SHAPE_NAMES[i] end

local errors
repeat
  local title = TITLE
  if errors then title = TITLE .. " - " .. errors end
  local ok, csv = r.GetUserInputs(title, #FIELDS, table.concat(captions, ","), table.concat(values, ","))
  if not ok then return end

  local got = {}
  for v in (csv .. ","):gmatch("([^,]*),") do got[#got + 1] = v:match("^%s*(.-)%s*$") end
  errors = nil
  local new = {}
  for i, f in ipairs(FIELDS) do
    local v, kind = got[i] or "", f[3]
    if kind == "len" then
      local n = tonumber(v)
      if n and n > 0 then new[f[1]] = n else errors = errors or (f[2] .. " must be above 0") end
    elseif kind == "align" then
      v = v:lower()
      if FT.valid_align(v) then new[f[1]] = v else errors = errors or (f[2] .. ": before, center or after") end
    elseif kind == "shape" then
      local n = tonumber(v)
      if n and FT.SHAPE_NAMES[n] then new[f[1]] = n
      else errors = errors or (table.concat(shape_help, ", ")) end
    elseif kind == "bool" then
      v = v:lower():sub(1, 1)
      if v == "y" or v == "n" then new[f[1]] = (v == "y") and 1 or 0 else errors = errors or (f[2]) end
    end
    values[i] = got[i] or values[i]
  end
  if not errors then FT.save_settings(new) end
until not errors
