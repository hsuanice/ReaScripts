--[[
@description Auto Pan LR Tracks (pan adjacent XXX_L / XXX_R track pairs hard left / hard right)
@version 261010.1246
@author hsuanice
@about
  After an AAF import, split-stereo tracks (e.g. "Audio 9_L" / "Audio 9_R") arrive panned center.
  This script scans ALL tracks and pans each adjacent L/R pair:
    • L track -> 100% Left, R track -> 100% Right
    • A pair = track N ends with an L suffix AND track N+1 has the same base name with an R suffix
    • Recognized suffixes (case-insensitive): _L/_R, -L/-R, .L/.R, " L"/" R"
  Unpaired L/R-looking tracks are left untouched and listed in a message for review.
  Notes:
    - Works with every pan mode; in Dual Pan mode both knobs are set to the same side.
    - Single undo point.

@changelog
  v261010.1246
    + Initial release.
]]

local r = reaper

-- Returns base, side ("L"/"R") if the name ends with a recognized L/R suffix, else nil.
local function parse_lr(name)
  name = name:gsub("%s+$", "")
  local base, side = name:match("^(.-)[_%-%. ]([LlRr])$")
  if not base then return nil end
  base = base:gsub("%s+$", "")
  if base == "" then return nil end
  return base:lower(), side:upper()
end

local function set_pan(tr, pan)
  r.SetMediaTrackInfo_Value(tr, "D_PAN", pan)
  if r.GetMediaTrackInfo_Value(tr, "I_PANMODE") == 6 then -- dual pan
    r.SetMediaTrackInfo_Value(tr, "D_DUALPANL", pan)
    r.SetMediaTrackInfo_Value(tr, "D_DUALPANR", pan)
  end
end

local n = r.CountTracks(0)
local tracks = {}
for i = 0, n - 1 do
  local tr = r.GetTrack(0, i)
  local _, name = r.GetTrackName(tr)
  local base, side = parse_lr(name)
  tracks[#tracks + 1] = { tr = tr, name = name, base = base, side = side }
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local paired, orphans = 0, {}
local i = 1
while i <= #tracks do
  local t, nxt = tracks[i], tracks[i + 1]
  if t.side == "L" and nxt and nxt.side == "R" and nxt.base == t.base then
    set_pan(t.tr, -1)
    set_pan(nxt.tr, 1)
    paired = paired + 1
    i = i + 2
  else
    if t.side then orphans[#orphans + 1] = string.format("  #%d  %s", i, t.name) end
    i = i + 1
  end
end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.Undo_EndBlock(string.format("Auto Pan LR tracks (%d pairs)", paired), 1)

if #orphans > 0 then
  r.ShowMessageBox(
    string.format("已 pan 好 %d 對 L/R 軌。\n\n以下軌道名稱像 L/R，但上下找不到配對，沒有更動：\n\n%s",
      paired, table.concat(orphans, "\n")),
    "Auto Pan LR Tracks", 0)
end
