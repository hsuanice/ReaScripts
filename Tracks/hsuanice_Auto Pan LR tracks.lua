--[[
@description Auto Pan LR Tracks (pan adjacent XXX_L / XXX_R track pairs hard left / hard right)
@version 26.1012.2303
@author hsuanice
@changelog
  - Change: works on the selected tracks — every L/R pair inside the selection is panned 100% left / 100% right on its own (both tracks of a pair must be selected). With no selection, the whole project is processed as before.
@about
    After an AAF import, split-stereo tracks (e.g. "Audio 9_L" / "Audio 9_R") arrive panned center.
    This script pans each adjacent L/R pair — within the selected tracks, or in the whole
    project when no track is selected:
      • L track -> 100% Left, R track -> 100% Right
      • A pair = track N ends with an L suffix AND track N+1 has the same base name with an R suffix
        (with a selection, both tracks of the pair must be selected); every pair is set on its own
      • Recognized suffixes (case-insensitive): _L/_R, -L/-R, .L/.R, " L"/" R"
    Unpaired L/R-looking tracks are left untouched and listed in a message for review.
    Notes:
      - Works with every pan mode; in Dual Pan mode both knobs are set to the same side.
      - Single undo point.

  ## Suggested shortcuts
  - Auto Pan LR tracks: Control+Option+Cmd+Shift+L

  Shortcuts are suggestions only — nothing is assigned automatically. macOS names; on Windows Cmd = Ctrl, Option = Alt, Control = Win.
--]]
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

-- Scope: the selected tracks, or every track when nothing is selected
local use_selection = r.CountSelectedTracks(0) > 0

local n = r.CountTracks(0)
local tracks = {}
for i = 0, n - 1 do
  local tr = r.GetTrack(0, i)
  local _, name = r.GetTrackName(tr)
  local base, side = parse_lr(name)
  local in_scope = (not use_selection) or r.IsTrackSelected(tr)
  tracks[#tracks + 1] = { tr = tr, name = name, base = base, side = side, in_scope = in_scope }
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

local paired, orphans = 0, {}
local i = 1
while i <= #tracks do
  local t, nxt = tracks[i], tracks[i + 1]
  if t.in_scope and t.side == "L" and nxt and nxt.in_scope and nxt.side == "R" and nxt.base == t.base then
    set_pan(t.tr, -1)
    set_pan(nxt.tr, 1)
    paired = paired + 1
    i = i + 2
  else
    if t.in_scope and t.side then orphans[#orphans + 1] = string.format("  #%d  %s", i, t.name) end
    i = i + 1
  end
end

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.Undo_EndBlock(string.format("Auto Pan LR tracks (%d pairs)", paired), 1)

if #orphans > 0 then
  r.ShowMessageBox(
    string.format("Panned %d L/R track pair(s)%s.\n\nThese tracks look like L/R by name but have no matching neighbor above or below%s, so they were left unchanged:\n\n%s",
      paired, use_selection and " in the selection" or "",
      use_selection and " (both tracks of a pair must be selected)" or "", table.concat(orphans, "\n")),
    "Auto Pan LR Tracks", 0)
end
