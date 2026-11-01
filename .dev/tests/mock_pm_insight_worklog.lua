-- @noindex  (local test for Various/hsuanice_Project Manager - PM Insight Analyzer.lua; not a ReaPack package)
-- Work Log mode (no Scene Cut track): By Project reel columns and the per-project By Reel table.
-- usage (repo root): lua .dev/tests/mock_pm_insight_worklog.lua
--
-- Proj R1 Dialog: scene A (60s film / 600s source) mic select 1h + editing 1h (A again: once);
--                 scene B (120s / 900s) editing 1h - logged a frame later with a smaller Src Len
--                 (same scene: max source kept); notes in REAPER use CRLF
-- Proj R3 Dialog: scene "80" twice at different places (2 scenes) + "80" again a frame off (same)
-- Proj R2 Dialog: whole-reel ME+PAN 1h (Reel Len 300s, source 1800s, 5 scenes)
-- Proj All Conform: conform 1h (not a reel) · "Proj | aap": no reel · "261020 Proj R2 | check": date ignored
-- Proj R1 Dialog | export: 5 s of work -> no rate
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/%.dev/tests/") or "."
local SCRIPT = REPO .. "/Various/hsuanice_Project Manager - PM Insight Analyzer.lua"
local OUT_DIR = os.tmpname() .. "_dir"
os.execute('mkdir -p "' .. OUT_DIR .. '"')

local function it(pos, len, name, notes) return { pos = pos, len = len, name = name, notes = notes or "" } end
local A = "10\r\nRange    : 01:00:00:00 - 01:01:00:00\nLength   : 00:01:00:00\nSrc Len  : 00:10:00:00"
local B1 = "20\nRange    : 01:01:00:00 - 01:03:00:00\nLength   : 00:02:00:00\nSrc Len  : 00:15:00:00"
local B2 = "20\nRange    : 01:01:00:01 - 01:03:00:01\nLength   : 00:02:00:00\nSrc Len  : 00:05:00:00"
local REEL = "Scope    : R2\nScenes   : 5\nReel Len : 00:05:00:00\nSrc Len  : 00:30:00:00"
local function s80(a, b) return "80\nRange    : " .. a .. " - " .. b .. "\nLength   : 00:00:30:00" end
local tracks = {
  { name = "2026-09-30", items = { it(0, 1800, "Proj R3 Dialog | editing", s80("03:00:00:00", "03:00:30:00")),
    it(2000, 1800, "Proj R3 Dialog | editing", s80("03:05:00:00", "03:05:30:00")),
    it(4000, 1800, "Proj R3 Dialog | denoise", s80("03:00:00:01", "03:00:30:01")) } },
  { name = "2026-10-01", items = { it(0, 3600, "Proj R1 Dialog | mic select", A),
    it(4000, 3600, "Proj R1 Dialog | editing", B1), it(8000, 5, "Proj R1 Dialog | export") } },
  { name = "2026-10-02", items = { it(0, 3600, "Proj R1 dialog | editing", A),
    it(4000, 3600, "Proj R1 Dialog | denoise", B2), it(8000, 3600, "Proj R2 Dialog | ME+PAN", REEL) } },
  { name = "2026-10-03", items = { it(0, 3600, "Proj All Conform | conform"), it(4000, 1800, "Proj | aap"),
    it(6000, 600, "261020 Proj R2 | check") } },
}
reaper = {
  CountTracks = function() return #tracks end, GetTrack = function(_, i) return tracks[i + 1] end,
  GetTrackName = function(t) return true, t.name end, GetMediaTrackInfo_Value = function() return 0 end,
  CountTrackMediaItems = function(t) return #t.items end, GetTrackMediaItem = function(t, i) return t.items[i + 1] end,
  GetMediaItemInfo_Value = function(x, k) if k == "D_POSITION" then return x.pos elseif k == "D_LENGTH" then return x.len end return 0 end,
  GetActiveTake = function(x) return x end, GetTakeName = function(x) return x.name end,
  GetSetMediaItemInfo_String = function(x, k) if k == "P_NOTES" then return true, x.notes end return true, "" end,
  format_timestr_len = function(s) return string.format("%.0fs", s) end,
  format_timestr_pos = function(s) return string.format("@%.0f", s) end,
  ColorFromNative = function() return 0, 0, 0 end,
  EnumProjects = function() return nil, OUT_DIR .. "/Work Log.rpp" end, GetProjectPath = function() return OUT_DIR end,
  GetOS = function() return "macOS-arm64" end, EnumerateFiles = function() return nil end,
  CF_ShellExecute = function() end, ShowConsoleMsg = function() end, ShowMessageBox = function(m) print("MB: " .. m) end,
  GetProjExtState = function() return 0, "" end, TimeMap_curFrameRate = function() return 24 end,
  BR_GetMediaItemGUID = function() return "" end, IsMediaItemSelected = function() return false end,
}
dofile(SCRIPT)
local f = assert(io.open(OUT_DIR .. "/" .. OUT_DIR:match("([^/]+)$") .. " - PM Insight.html"))
local html = f:read("a"); f:close()
local all = html:match('data%-y="all">(.-)<div class="yr"')

local fails, passes = 0, 0
local function check(name, cond)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL " .. name) end
end
local function has(s) return all:find(s, 1, true) ~= nil end

-- By Project: 2 reels; reel work 5h + 600s check (R2) = 18605s incl. the 5 s export
-- film 60+120 (R1) + 300 (R2) = 480s; source 600+900 (max) + 1800 = 3300s
-- R3: 1.5h, film 60s -> totals 3 reels, 24005s, film 540s, source 3300s
check("By Project reel columns, no Share", not has('<th>Total</th><th>Share</th><th>Reels</th>') and has('<td>3</td><td>6h 40m</td><td>2h 13m</td><td>540s</td><td>3300s</td>'))
check("By Project film/hr 540s / 24005s = 1m 20s", has('<td>1m 20s</td><td>8m 14s</td>'))
check("R3: same name at two places = 2 scenes, a frame off = same scene",
  has('<td class="l">R3</td><td>1h 30m</td>') and has('<td>60s</td><td>–</td><td>2</td>'))
-- By Reel: R1 = 4h + 5s, scenes A + B once each, film 180s, source 1500s (max of B)
check("R1 row", has('<tr class="total reel"><td class="l">R1</td><td>4h 00m</td>') and has('<td>180s</td><td>1500s</td><td>2</td>'))
check("R1 editing: scenes A + B in 2h", has('editing</td><td>2h 00m</td>') and has('<td>180s</td><td>1500s</td><td>2</td><td>1m 30s</td><td>12m 30s</td>'))
check("export of 5 s: no rate", has('export</td><td>0h 00m</td><td>0%</td><td>1</td><td class="l"></td><td>–</td><td>–</td><td>–</td><td>–</td><td>–</td>'))
check("R2 whole-reel item: Reel Len, source, scenes – / 5",
  has('<td class="l">R2</td><td>1h 10m</td>') and has('<td>300s</td><td>1800s</td><td>– / 5</td>'))
check("dated name ignored: check counted on R2", has('check</td><td>0h 10m</td>') and not has('>261020<'))
check("All and no reel rows, not counted as reels", has('<td class="l">All</td>') and has('<td class="l">(no reel)</td>')
  and has('3 reels</div>'))
check("zebra rows + reel rows", html:find("tr:nth-child(even) td{background:var(--stripe)}", 1, true) ~= nil)
check("reel order R1, R2, All, (no reel)", all:find(">R1<", 1, true) < all:find(">R2<", 1, true)
  and all:find(">R2<", 1, true) < all:find(">All<", 1, true) and all:find(">All<", 1, true) < all:find(">(no reel)<", 1, true))
check("work time as Xh XXm (rounded), lengths stay timecode", has('<b>Total Work</b><span>8h 10m</span>')
  and has('<td>300s</td><td>1800s</td>'))
check("task still the last word (dialog / Dialog merged)", has('<td class="l">Dialog</td>') and not has('<td class="l">dialog</td>'))

os.execute('rm -rf "' .. OUT_DIR .. '"')
print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then os.exit(1) end
