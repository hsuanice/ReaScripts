-- @noindex  (local test for Various/hsuanice_Project Manager - PM Insight Analyzer.lua; not a ReaPack package)
-- Mock project: Scene Cut track with 3 scenes and 3 work-log days, EDL / Mic Selected / Edited
-- folders. Runs the analyzer with and without selected scenes and checks the HTML report.
-- usage (repo root): lua .dev/tests/mock_pm_insight.lua
--
-- Scenes (film / EDL source):
--   10 (60s / 300s)  EDL muted, Mic Selected muted, Edited muted      -> finished
--   11 (30s / 180s)  EDL muted, no Mic Selected (skipped), Edited open; Scene Cut MUTED as a
--                    temporary marker -> NOT finished
--   12 (90s / 360s)  EDL open, nothing later                          -> not started
-- Work: 10-20 mic select 10 (600s) + 11 (1800s); 10-21 editing 10 (3600s);
--       10-22 denoise 10 (1800s) + mic select 12 (900s) + check without a scene (900s)
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/%.dev/tests/") or "."
local SCRIPT = REPO .. "/Various/hsuanice_Project Manager - PM Insight Analyzer.lua"
local OUT = os.tmpname()
os.remove(OUT)
local OUT_DIR = OUT .. "_dir"
os.execute('mkdir -p "' .. OUT_DIR .. '"')

local function item(o)
  return { pos = o.pos, len = o.len, name = o.name or "", notes = o.notes or "", ext = o.ext or {},
    color = o.color or 0, mute = o.mute or 0, sel = o.sel or false, guid = o.guid or tostring(math.random()) }
end
local function work(len, wt, scene) return item({ pos = 0, len = len, ext = { WORK_TYPE = wt, SCENE_GUID = scene } }) end
local tracks, projext = nil, {}
local function build(selected)
  local sc1 = item({ pos = 0,  len = 60, name = "10", guid = "{S1}", notes = "Src Len : 00:05:00:00\nSel Len : 00:02:00:00" })
  local sc2 = item({ pos = 60, len = 30, name = "11", guid = "{S2}", notes = "Src Len : 00:03:00:00", mute = 1 })
  local sc3 = item({ pos = 90, len = 90, name = "12", guid = "{S3}", notes = "Src Len : 00:06:00:00" })
  for _, g in ipairs(selected) do
    for _, s in ipairs({ sc1, sc2, sc3 }) do if s.guid == g then s.sel = true end end
  end
  tracks = {
    { name = "Scene Cut", depth = 1, items = { sc1, sc2, sc3 } },
    { name = "2026-10-20", depth = 0, items = { work(600, "mic select", "{S1}"), work(1800, "mic select", "{S2}") } },
    { name = "2026-10-21", depth = 0, items = { work(3600, "editing", "{S1}") } },
    { name = "2026-10-22", depth = -1, items = { work(1800, "denoise", "{S1}"), work(900, "mic select", "{S3}"),
      item({ pos = 0, len = 900, ext = { WORK_TYPE = "check" } }) } },
    { name = "EDL", depth = 1, items = { item({ pos = 0, len = 900 }) } },
    { name = "EDL A", depth = -1, items = {
      item({ pos = 0, len = 100, ext = { SCENE_ID = "{S1}" }, mute = 1 }),
      item({ pos = 60, len = 100, ext = { SCENE_ID = "{S2}" }, mute = 1 }),
      item({ pos = 90, len = 300, ext = { SCENE_ID = "{S3}" } }) } },
    { name = "Mic Selected", depth = 1, items = {} },
    { name = "MS A", depth = -1, items = { item({ pos = 10, len = 20, mute = 1 }) } },
    { name = "Edited", depth = 1, items = {} },
    { name = "ED A", depth = -1, items = { item({ pos = 10, len = 20, mute = 1 }), item({ pos = 65, len = 10 }),
      -- muted, ends where scene 12 starts (+ a floating-point hair): belongs to scene 11 only
      item({ pos = 85, len = 5 + 1e-9, mute = 1 }) } },
  }
  for i, t in ipairs(tracks) do t.num = i end
end

reaper = {
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetTrackName = function(t) return true, t.name end,
  GetMediaTrackInfo_Value = function(t, k)
    if k == "I_FOLDERDEPTH" then return t.depth end
    if k == "IP_TRACKNUMBER" then return t.num end
    return 0
  end,
  CountTrackMediaItems = function(t) return #t.items end,
  GetTrackMediaItem = function(t, i) return t.items[i + 1] end,
  GetMediaItemInfo_Value = function(it, k)
    if k == "D_POSITION" then return it.pos elseif k == "D_LENGTH" then return it.len
    elseif k == "I_CUSTOMCOLOR" then return it.color elseif k == "B_MUTE" then return it.mute end
    return 0
  end,
  IsMediaItemSelected = function(it) return it.sel end,
  BR_GetMediaItemGUID = function(it) return it.guid end,
  TimeMap_curFrameRate = function() return 24 end,
  GetActiveTake = function(it) return it end,
  GetTakeName = function(it) return it.name end,
  GetSetMediaItemInfo_String = function(it, k)
    if k == "P_NOTES" then return true, it.notes end
    local e = k:match("^P_EXT:(.+)$")
    return true, (e and it.ext[e]) or ""
  end,
  format_timestr_len = function(s) return string.format("%.0fs", s) end,
  format_timestr_pos = function(s) return string.format("@%.0f", s) end,
  ColorFromNative = function() return 0, 0, 0 end,
  EnumProjects = function() return nil, OUT_DIR .. "/Session.rpp" end,
  GetProjectPath = function() return OUT_DIR end,
  GetOS = function() return "macOS-arm64" end,
  EnumerateFiles = function() return nil end,
  CF_ShellExecute = function() end,
  ShowConsoleMsg = function() end,
  ShowMessageBox = function(m) print("MB: " .. m) end,
  GetProjExtState = function(_, _, k) local v = projext[k]; return v and 1 or 0, v or "" end,
}

local function run(selected)
  build(selected)
  dofile(SCRIPT)
  local f = assert(io.open(OUT_DIR .. "/" .. (OUT_DIR:match("([^/]+)$")) .. " - PM Insight.html"))
  local html = f:read("a"); f:close()
  return html
end

local fails, passes = 0, 0
local function check(name, cond)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL " .. name) end
end
local function has(h, s) return h:find(s, 1, true) ~= nil end

-- Whole project ------------------------------------------------------------------
local all = run({})
check("overview + project-wide figures", has(all, "<h2>Overview</h2>") and has(all, "Per day (typical)") and has(all, "Without a scene"))
check("an Edited item that only touches scene 12 does not make its denoise done (1 / 3)",
  has(all, 'Denoised</span></b><span>36% <small>(1 / 3)</small></span>'))
check("work time total 2.7h, no time estimate", has(all, '<b>Work time</b><span><span class="big" style="font-size:18px">2.7h</span>')
  and has(all, "Last 7 days") and not has(all, "Left (est.)") and not has(all, "Total (est.)"))
-- film: scene 11 is muted on Scene Cut (not finished); source: scene 10 is finished (not muted)
check("completion film % from Scene Cut mute (scene 11: 30s of 180s = 17%)",
  has(all, '<div><div class="big" style="color:#2e9b55">17%</div><small>film</small></div>')
  and has(all, "<b>Film done</b><span>30s <small>/ 180s</small>") and has(all, "<b>Scenes marked done</b><span>1 / 3</span>"))
check("completion source % from finished scenes (scene 10: 300s of 840s = 36%)",
  has(all, '<div><div class="big" style="color:#2e9b55">36%</div><small>source</small></div>')
  and has(all, "<b>Source done</b><span>300s <small>/ 840s</small>") and has(all, "<b>Scenes finished</b><span>1 / 3</span>"))
check("every work type in the table", has(all, '<td class="l">denoise</td>') and has(all, '<td class="l">check</td>'))
check("all three scenes listed", has(all, ">10<") and has(all, ">11<") and has(all, ">12<"))
check("EDL total source 1400s", has(all, "1400s"))
check("no target yet: hint to set it in PM Timer", has(all, "Set the target hours and the delivery date in PM Timer"))

-- finished = every stage done; the Scene Cut mute of scene 11 does not count
check("scenes finished 1 / 3 (Scene Cut mute ignored)", has(all, "Scenes finished</b><span>1 / 3")
  and has(all, 'Denoised</span></b><span>36% <small>(1 / 3)</small>'))
check("efficiency from scene 10 only: film 60s / 6000s = 0m 36s", has(all, "Film per hour</b><span>0m 36s"))
check("efficiency: source 300s / 6000s = 3m 0s", has(all, "Source (ISO) per hour</b><span>3m 0s"))
check("efficiency note", has(all, "1 finished scene: film 60s · source 300s · work 1.7h"))

-- stages: EDL muted = mic select done; Mic Selected skipped when Edited has items
-- Progress: % of the EDL source (840s) and of the film (180s); scenes 10 + 11 = 480s / 90s, scene 10 = 300s / 60s
check("Mic select stage 2 / 3: source 57%, film 50%",
  has(all, "Mic Selected</span></b><span>57% <small>(2 / 3)</small>")
  and has(all, "Mic Selected</span></b><span>50% <small>(2 / 3)</small>"))
check("Editing stage 2 / 3 (scene 11 skipped Mic Selected)",
  has(all, "Edited</span></b><span>57% <small>(2 / 3)</small>"))
check("Denoise stage 1 / 3: source 36%, film 33%",
  has(all, "Denoised</span></b><span>36% <small>(1 / 3)</small>")
  and has(all, "Denoised</span></b><span>33% <small>(1 / 3)</small>"))
check("Progress Editing: done / left lengths switch too (source 480s / 840s, film 90s / 180s)",
  has(all, "source done</b><span>480s <small>/ 840s</small>") and has(all, "source left · est. work</b><span>360s · ")
  and has(all, "film done</b><span>90s <small>/ 180s</small>") and has(all, "film left · est. work</b><span>90s · "))
do -- Progress order: latest step on top, Mic select (EDL) at the bottom
  local a, b = all:find("Denoised</span></b><span>36%", 1, true), all:find("Edited</span></b><span>57%", 1, true)
  local c, d = all:find("Mic Selected</span></b><span>57%", 1, true), all:find("ISO</span></b><span>840s <small>(3 scenes)</small>", 1, true)
  check("Progress order (states): Denoised, Edited, Mic Selected, ISO at the bottom", a and b and c and d and a < b and b < c and c < d)
  check("Progress state colors", has(all, 'color:#e040e0;font-weight:700">Denoised') and has(all, 'color:#e0b400;font-weight:700">Edited')
    and has(all, 'color:#9650ff;font-weight:700">Mic Selected') and has(all, 'background:#7f9cc0'))
  check("ISO fallback: the mock's folder is still called EDL", has(all, "ISO</span></b><span>840s"))
  local den = all:sub(a, b)   -- the Denoised block (up to Edited) has its own left row
  check("Denoised has a source left row (scenes 11 + 12: 540s)", has(den, "source left · est. work</b><span>540s · "))
end
check("Progress Source / Film switch", has(all, '<div class="pmode"><button data-m="source">Source</button><button data-m="film">Film</button></div>')
  and has(all, '<div class="pm" data-m="film">') and has(all, 'localStorage'))
check("remaining source + estimate per stage", has(all, "360s · 0.5h") and has(all, "360s · 1.2h") and has(all, "540s · 0.9h"))
check("estimated work left 2.6h", has(all, 'Estimated work left</b><span><span class="big">2.6h'))
check("scene table has stage columns", has(all, "<th>Mic select ✓</th>") and has(all, "<th>Denoise ✓</th>"))
check("Source/hr uses EDL source for every work type", not has(all, "Mic Selected for editing"))

-- daily progress: a stage on the last day of its work type; the scene on the latest stage day
check("daily progress section, open", has(all, "<details open><summary>Daily progress</summary>"))
check("10-22: scene 10 finished (1m 0s film, 5m 0s source), denoise done, 1.0h work",
  has(all, '<td class="l">2026-10-22</td><td class="l">10</td><td>1m 0s</td><td>5m 0s</td>')
  and has(all, "denoise 1: 10</td><td class=\"l\" style=\"white-space:normal\">12 (mic select)</td><td>1.0h"))
check("10-21: editing of scene 10", has(all, '<td class="l">2026-10-21</td><td class="l">–</td>') and has(all, "editing 1: 10</td><td class=\"l\" style=\"white-space:normal\">10 (editing)</td><td>1.0h"))
check("10-20: mic select of 10 and 11, 0.7h", has(all, "mic select 2: 10, 11</td><td class=\"l\" style=\"white-space:normal\">10 (mic select)<br>11 (mic select)</td><td>0.7h"))
check("In progress column + note", has(all, '<th class="l">In progress</th>') and has(all, "In progress = work logged on a scene"))
check("newest day first", all:find("2026-10-22", 1, true) < all:find("2026-10-20", 1, true))

-- Selected scenes ------------------------------------------------------------------
local one = run({ "{S1}" })
check("selected: header names the scene", has(one, "Selected scenes: 1 of 3") and has(one, "· 10</div>"))
check("selected: no project-wide figures", not has(one, "Per day (typical)") and not has(one, "Without a scene")
  and not has(one, "<h3>Plan</h3>") and not has(one, "<th>Project Time</th>"))
check("selected: only scene 10 in the list", has(one, ">10<") and not has(one, ">11<") and not has(one, ">12<"))
check("selected: its source and Mic Selected", has(one, "300s") and has(one, "120s"))
check("selected: only its work types", has(one, '<td class="l">editing</td>') and not has(one, '<td class="l">check</td>'))
check("selected: scene keeps its project number", has(one, 'id="s1"'))
check("selected: finished scene has its efficiency", has(one, "Film per hour</b><span>0m 36s"))
check("selected: daily work is only the scene's (10-22 = 0.5h)", has(one, "denoise 1: 10</td><td class=\"l\" style=\"white-space:normal\">–</td><td>0.5h"))

local unfinished = run({ "{S3}" })
check("selected: unfinished scene has no efficiency yet", has(unfinished, "Film per hour</b><span>N/A") and has(unfinished, "No finished scene"))

local two = run({ "{S2}", "{S3}" })
check("two selected: 2 of 3, numbers kept", has(two, "Selected scenes: 2 of 3") and has(two, 'id="s3"') and not has(two, ">10<"))
check("two selected: source = 180s + 360s", has(two, "540s"))

-- Plan: target hours + delivery date in 10 days ----------------------------------------
projext.TARGET_HOURS = "20"
projext.DUE_DATE = os.date("%Y-%m-%d", os.time() + 10 * 86400)
local plan = run({})
check("plan: days left", has(plan, "10 days left"))
check("plan: hours used / target and per day", has(plan, "2.7h / 20h") and has(plan, "Per day</b><span>1.7h"))
check("plan: per day as part of a 5h working day", has(plan, "1.7h <small>(35% of a 5h day)</small>"))
check("plan: estimate fits the hours left", has(plan, "✓ fits"))
check("plan: 2.6h at 5h a day = 1 day", has(plan, "At 5h a day</b><span>1 days · done ~") and has(plan, "Hours available to delivery</b><span>50.0h"))
check("plan: source per day per stage", has(plan, "Denoise source / day</b><span>0m 54s") and has(plan, "Mic select source / day</b><span>0m 36s"))
-- pace needed: 2 scenes left (540s source, 120s film), 10 days x 5h = 50h
check("pace: header", has(plan, "Pace needed for the 2 scenes left") and has(plan, "10 days × 5h = 50.0h"))
check("pace: source 0m 54s per day, 0m 10s per hour, now 3m 0s ✓",
  has(plan, '<td class="l">Source</td><td>0m 54s</td><td>0m 10s</td><td>3m 0s <span class="ok">✓</span>'))
check("pace: film 0m 12s per day, 0m 2s per hour, now 0m 36s ✓",
  has(plan, '<td class="l">Film</td><td>0m 12s</td><td>0m 2s</td><td>0m 36s <span class="ok">✓</span>'))
projext.HOURS_PER_DAY = "1"
local p1 = run({})
check("plan: 1h a day -> 3 days, 10h available", has(p1, "At 1h a day</b><span>3 days") and has(p1, "Hours available to delivery</b><span>10.0h"))
projext.HOURS_PER_DAY = "0.01"
check("pace: too slow -> warning with factor", has(run({}), '<span class="warn">⚠ ×'))
projext.HOURS_PER_DAY = nil
projext.TARGET_HOURS = "2"
check("plan: estimate over the hours left", has(run({}), " over</span>"))
projext.DUE_DATE = os.date("%Y-%m-%d", os.time() - 2 * 86400)
check("plan: late delivery date", has(run({}), "2 days late"))
projext = {}

os.execute('rm -rf "' .. OUT_DIR .. '"')
print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
