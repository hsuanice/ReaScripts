-- @noindex  (local test for Various/hsuanice_Project Manager - PM Insight Analyzer.lua; not a ReaPack package)
-- Mock project: Scene Cut track with 3 scenes, EDL folder, one work-log date track.
-- Runs the analyzer with and without selected scenes and checks the HTML report.
-- usage (repo root): lua .dev/tests/mock_pm_insight.lua
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
local tracks, projext = nil, {}
local function build(selected)
  local sc1 = item({ pos = 0,  len = 60, name = "10", guid = "{S1}", notes = "Src Len : 00:05:00:00\nSel Len : 00:02:00:00" })
  local sc2 = item({ pos = 60, len = 30, name = "11", guid = "{S2}", notes = "Src Len : 00:03:00:00", mute = 1 })
  local sc3 = item({ pos = 90, len = 90, name = "12", guid = "{S3}", notes = "Src Len : 00:06:00:00" })
  for _, g in ipairs(selected) do
    for _, s in ipairs({ sc1, sc2, sc3 }) do if s.guid == g then s.sel = true end end
  end
  local log = {
    item({ pos = 0, len = 3600, ext = { WORK_TYPE = "editing", SCENE_GUID = "{S1}" } }),
    item({ pos = 0, len = 1800, ext = { WORK_TYPE = "mic select", SCENE_GUID = "{S2}" } }),
    item({ pos = 0, len = 7200, ext = { WORK_TYPE = "denoise", SCENE_GUID = "{S3}" } }),
    item({ pos = 0, len = 900,  ext = { WORK_TYPE = "check" } }),   -- project work, no scene
  }
  tracks = {
    { name = "Scene Cut", depth = 1, items = { sc1, sc2, sc3 } },
    { name = "2026-10-20", depth = -1, items = log },
    { name = "EDL", depth = 1, items = { item({ pos = 0, len = 900 }) } },
    -- EDL items of each scene; muted = mic select done
    { name = "EDL A", depth = -1, items = {
      item({ pos = 0, len = 100, ext = { SCENE_ID = "{S1}" }, mute = 1 }),
      item({ pos = 60, len = 100, ext = { SCENE_ID = "{S2}" }, mute = 1 }),
      item({ pos = 90, len = 300, ext = { SCENE_ID = "{S3}" } }) } },
    -- Mic Selected: only scene 10 (done); scene 11 skips it (has Edited items)
    { name = "Mic Selected", depth = 1, items = {} },
    { name = "MS A", depth = -1, items = { item({ pos = 10, len = 20, mute = 1 }) } },
    { name = "Edited", depth = 1, items = {} },
    { name = "ED A", depth = -1, items = { item({ pos = 65, len = 10 }) } },
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

local all = run({})
check("whole project: overview + project-wide figures", has(all, "<h2>Overview</h2>") and has(all, "Per day (typical)") and has(all, "Without a scene"))
check("work time total 3.8h, last 7 days present", has(all, '<div class="big">3.8h</div>') and has(all, "Last 7 days"))
-- efficiency from finished scenes only: scene 11 (muted) = 30s film, 180s source, 0.5h work
check("efficiency: finished film 30s / 0.5h = 1m 0s", has(all, "Film per hour</b><span>1m 0s"))
check("efficiency: finished source 180s / 0.5h = 6m 0s", has(all, "Source (EDL) per hour</b><span>6m 0s"))
check("efficiency note names the finished scenes", has(all, "1 finished scene: film 30s · source 180s · work 0.5h"))
check("no target yet: hint to set it in PM Timer", has(all, "Set the target hours and the delivery date in PM Timer"))
check("whole project: every work type", has(all, '<td class="l">denoise</td>') and has(all, '<td class="l">check</td>'))
check("whole project: all three scenes listed", has(all, ">10<") and has(all, ">11<") and has(all, ">12<"))
check("whole project: EDL total source 1400s", has(all, "1400s"))

local one = run({ "{S1}" })
check("selected: header names the scene", has(one, "Selected scenes: 1 of 3") and has(one, "· 10</div>"))
check("selected: no project-wide figures", not has(one, "Per day (typical)") and not has(one, "Without a scene")
  and not has(one, "<h3>Plan</h3>") and not has(one, "<th>Project Time</th>"))
check("selected: unfinished scene has no efficiency yet", has(one, "Film per hour</b><span>N/A") and has(one, "No finished scene"))
check("selected: only scene 10 in the list", has(one, ">10<") and not has(one, ">11<") and not has(one, ">12<"))
check("selected: its source and Mic Selected", has(one, "300s") and has(one, "120s"))
check("selected: only its work types", has(one, '<td class="l">editing</td>') and not has(one, '<td class="l">denoise</td>') and not has(one, '<td class="l">check</td>'))
check("selected: scene keeps its project number", has(one, 'id="s1"'))

local two = run({ "{S2}", "{S3}" })
check("two selected: 2 of 3, numbers kept", has(two, "Selected scenes: 2 of 3") and has(two, 'id="s3"') and not has(two, ">10<"))
check("two selected: source = 180s + 360s", has(two, "540s"))

-- stages: EDL muted = mic select done; Mic Selected skipped when Edited has items; no items = not done
check("Mic select stage 2 / 3", has(all, "Mic select <small>(EDL)</small></b><span>2 / 3"))
check("Editing stage 2 / 3 (scene 11 skipped Mic Selected)", has(all, "Editing <small>(Mic Selected)</small></b><span>2 / 3"))
check("Denoise stage 1 / 3 (scene 11 marked done = every stage done)", has(all, "Denoise <small>(Edited)</small></b><span>1 / 3"))
check("remaining source + estimate per stage (finished-stage rates)", has(all, "360s · 1.0h") and has(all, "360s · 1.2h") and has(all, "660s · N/A"))
check("estimated work left 2.2h", has(all, "Estimated work left</b><span><span class=\"big\">2.2h"))
check("scene table has stage columns", has(all, "<th>Mic select ✓</th>") and has(all, "<th>Denoise ✓</th>"))
check("Source/hr uses EDL source for every work type", not has(all, "Mic Selected for editing"))

-- plan: target hours + delivery date in 10 days
projext.TARGET_HOURS = "20"
projext.DUE_DATE = os.date("%Y-%m-%d", os.time() + 10 * 86400)
local plan = run({})
check("plan: days left", has(plan, "10 days left"))
check("plan: hours used / target and per day", has(plan, "3.8h / 20h") and has(plan, "Per day</b><span>1.6h"))
check("plan: estimate fits the hours left", has(plan, "✓ fits"))
check("plan: per day as part of a 5h working day", has(plan, "1.6h <small>(33% of a 5h day)</small>"))
check("plan: 2.2h left at 5h a day = 1 day, before delivery", has(plan, "At 5h a day</b><span>1 days · done ~") and has(plan, "Hours available to delivery</b><span>50.0h"))
-- pace needed: 2 scenes left (660s source, 150s film), 10 days x 5h = 50h
check("pace: header with days x hours", has(plan, "Pace needed for the 2 scenes left") and has(plan, "10 days × 5h = 50.0h"))
check("pace: source 1m 6s per day, 0m 13s per hour, now 6m 0s ✓",
  has(plan, '<td class="l">Source</td><td>1m 6s</td><td>0m 13s</td><td>6m 0s <span class="ok">✓</span>'))
check("pace: film 0m 15s per day, 0m 3s per hour, now 1m 0s ✓",
  has(plan, '<td class="l">Film</td><td>0m 15s</td><td>0m 3s</td><td>1m 0s <span class="ok">✓</span>'))
projext.HOURS_PER_DAY = "1"
local p1 = run({})
check("plan: 1h a day -> 3 days, 10h available", has(p1, "At 1h a day</b><span>3 days") and has(p1, "Hours available to delivery</b><span>10.0h"))
projext.HOURS_PER_DAY = "0.01"   -- 36 s of work a day: far too little
check("pace: too slow -> warning with factor", has(run({}), '<span class="warn">⚠ ×'))
projext.HOURS_PER_DAY = nil
check("plan: source per day per stage as 1m 6s", has(plan, "Denoise source / day</b><span>1m 6s"))
projext.TARGET_HOURS = "5"
check("plan: estimate over the hours left", has(run({}), " short</span>"))
projext.DUE_DATE = os.date("%Y-%m-%d", os.time() - 2 * 86400)
check("plan: late delivery date", has(run({}), "2 days late"))
projext = {}

os.execute('rm -rf "' .. OUT_DIR .. '"')
print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
