--[[
@description Project Manager - PM Insight Analyzer: work-time analysis of PM Timer logs (work in progress)
@version 26.1026.2300pre1
@author hsuanice
@noindex  (kept in the repository as a backup; not offered on ReaPack while it is a work in progress)
@changelog
  - Change: a stage with no items, and no items in any later stage, now counts as done when the scene is muted on Scene Cut - a scene without dialogue no longer stays unfinished.
@about
  Read-only analysis script. Auto-detects project type:

  Dialog Project Mode (Scene Cut track present):
    Combines scene data, EDL source lengths, and work log.
    Outputs per-scene efficiency metrics and project-wide summary as an
    HTML report ("<session folder name> - PM Insight.html" in the project
    folder, replaced on every run), opened in the web browser. Efficiency is computed for every work type.
    Tracks required: "Scene Cut", "EDL" (folder).

  Work Log Mode (no Scene Cut track):
    Parses item names ("Proj | Scene | Module") to compute durations by
    project, task, work type, month and day, as the same kind of HTML report
    (with a year filter). Work type names differing only in case are merged;
    duplicate items (same day, position and length) are counted once.

  Selected scenes: select one or more items on the Scene Cut track before running to
  report only those scenes - their work time, film length and Source / Mic Selected /
  Edited lengths (project-wide figures such as daily averages and work without a scene
  are left out). Nothing selected = the whole project. Scene numbers stay the project
  numbers. The report file is the same one either way (replaced on every run).

  Duration source: D_LENGTH (always). Does not write any data to the project.
--]]
---@diagnostic disable: undefined-global
local r = reaper

local SCENE_TRACK_NAME  = "Scene Cut"
local EDL_FOLDER_NAME   = "EDL"
local MIC_SELECTED_FOLDER = "Mic Selected"   -- same folder names as PM Timer
local EDITED_FOLDER       = "Edited"
local DURATION_LOG_NAME = "DurationOnly_Log"
local DATE_PAT          = "^%d%d%d%d%-%d%d%-%d%d$"

-- ── Helpers ────────────────────────────────────────────────────────────────

local function fmt_dur(secs)
  -- IMPORTANT: format_timestr_len requires 4 args; offset=0 must NOT be omitted
  return r.format_timestr_len(secs, "", 0, 5)
end

local function fmt_tc(pos)
  return r.format_timestr_pos(pos, "", 5)
end

-- Seconds of media per hour of work → "Xm Ys"
local function fmt_rate(secs_per_hr)
  local m = math.floor(secs_per_hr / 60)
  local s = math.floor(secs_per_hr % 60)
  return string.format("%dm %ds", m, s)
end

-- film_or_src_sec / (work_sec / 3600) → "Xm Ys" or "N/A"
local function rate_or_na(film_or_src_sec, work_sec)
  if work_sec <= 0 then return "N/A" end
  return fmt_rate(film_or_src_sec * 3600 / work_sec)
end

-- Trimmed mean of daily_tbl values (YYYY-MM-DD → secs).
-- Drops the bottom and top `trim_pct` fraction (e.g. 0.1 = 10%).
-- Returns: avg_secs, days_used, total_working_days
local function trimmed_daily_avg(daily_tbl, trim_pct)
  local vals = {}
  for _, secs in pairs(daily_tbl) do
    if secs > 0 then table.insert(vals, secs) end
  end
  local n = #vals
  if n == 0 then return 0, 0, 0 end
  table.sort(vals)
  local trim = math.floor(n * trim_pct)
  local lo   = trim + 1
  local hi   = n - trim
  if lo > hi then lo = 1; hi = n end   -- too few points: use all
  local sum = 0
  for i = lo, hi do sum = sum + vals[i] end
  return sum / (hi - lo + 1), hi - lo + 1, n
end

-- Returns all child tracks inside a named folder track.
-- Same implementation as SceneAnalyzer.find_folder_children().
local function find_folder_children(folder_name)
  local count     = r.CountTracks(0)
  local tracks    = {}
  local in_folder = false
  local depth     = 0

  for i = 0, count - 1 do
    local t        = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))

    if not in_folder then
      if tname == folder_name and fd == 1 then
        in_folder = true
        depth = 1
        -- folder header track is not a source track; skip it
      end
    else
      table.insert(tracks, t)
      depth = depth + fd
      if depth <= 0 then break end
    end
  end

  return tracks
end

-- ── Work Log Mode ──────────────────────────────────────────────────────────

-- Parse "Proj | Scene | Module" or "Proj | Module" item names.
-- Returns { scene = "...", module = "..." } or nil if unparseable.
local function parse_wl_item_name(name)
  local parts = {}
  local s = name
  while true do
    local a, b = s:find(" | ", 1, true)
    if not a then table.insert(parts, s); break end
    table.insert(parts, s:sub(1, a - 1))
    s = s:sub(b + 1)
  end
  -- The work type is always the last part (older items can carry a stacked
  -- prefix: "Proj A | Proj B | ... | module")
  if #parts >= 3 then
    return { scene = parts[2], module = parts[#parts] }
  elseif #parts == 2 then
    return { scene = nil, module = parts[2] }
  end
  return nil
end

local function split_prefix(name)
  local prefix = name:match("^(.-) | ") or name
  local project = prefix:match("^(%S+)") or ""
  local task = prefix:match("(%S+)%s*$") or ""
  return prefix, project, task
end

local function parse_note_fields(note)
  local info = {
    range = "",
    length = "",
    shots = "",
    src_cnt = "",
    src_len = "",
    scope = "",
    scenes = "",
    reel_len = "",
  }
  if not note or note == "" then return info end
  info.range   = note:match("Range%s*:%s*([^\n]+)")   or ""
  info.length  = note:match("Length%s*:%s*([^\n]+)")  or ""
  info.shots   = note:match("Shots%s*:%s*([^\n]+)")   or ""
  info.src_cnt = note:match("Src Cnt%s*:%s*([^\n]+)") or ""
  info.src_len = note:match("Src Len%s*:%s*([^\n]+)") or ""
  info.scope   = note:match("Scope%s*:%s*([^\n]+)")   or ""
  info.scenes  = note:match("Scenes%s*:%s*([^\n]+)")  or ""
  info.reel_len = note:match("Reel Len%s*:%s*([^\n]+)") or ""
  return info
end

local function sort_keys_by_value(tbl)
  local keys = {}
  for k in pairs(tbl) do table.insert(keys, k) end
  table.sort(keys, function(a, b)
    local av = tbl[a] or 0
    local bv = tbl[b] or 0
    if av == bv then return tostring(a) < tostring(b) end
    return av > bv
  end)
  return keys
end

local REPORT_HEAD = [[<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PM Insight Report</title>
<style>
:root{--bg:#fafafa;--fg:#1d1d1f;--mut:#6e6e73;--line:#d2d2d7;--card:#fff;--head:#f0f0f3;--acc:#3b6fd8}
@media (prefers-color-scheme:dark){:root{--bg:#1b1b1d;--fg:#e8e8ea;--mut:#9a9aa0;--line:#3a3a3f;--card:#242427;--head:#2d2d31;--acc:#7da2ff}}
body{margin:0;padding:24px 16px 80px;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,"Segoe UI",Helvetica,Arial,sans-serif}
main{max-width:1400px;margin:0 auto}
h1{font-size:22px;margin:0 0 2px}h2{font-size:17px;margin:32px 0 10px;padding-bottom:6px;border-bottom:2px solid var(--line)}
.sub{color:var(--mut);margin-bottom:20px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:10px}
.kv{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px}
.stages{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px;margin-top:10px}
.stage{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px}
.stage h4{margin:0 0 6px;font-size:13px}.stage div{display:flex;justify-content:space-between;gap:8px;padding:2px 0}
.stage div b{font-size:12px;color:var(--mut);font-weight:500}.stage div span{font:600 15px ui-monospace,Menlo,monospace}
.kv b{display:block;font-size:12px;color:var(--mut);font-weight:500}.kv span{font:600 16px ui-monospace,Menlo,monospace}
.wrap{overflow-x:auto}
table{border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:8px;min-width:100%}
th,td{padding:6px 10px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}
th{background:var(--head);font-size:12px;color:var(--mut);font-weight:600;position:sticky;top:0}
td.l,th.l{text-align:left}td{font-family:ui-monospace,Menlo,monospace;font-size:13px}
tr.total td{font-weight:700}tr.idle td{color:var(--mut)}
a{color:var(--acc);text-decoration:none}a:hover{text-decoration:underline}
.dot{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px;vertical-align:baseline}
.scene{background:var(--card);border:1px solid var(--line);border-left:5px solid var(--acc);border-radius:8px;padding:12px 16px;margin:18px 0;scroll-margin-top:12px}
.scene h3{margin:0 0 4px;font-size:16px}.scene .meta{color:var(--mut);font-family:ui-monospace,Menlo,monospace;font-size:13px;margin-bottom:10px}
.scene table{border:none}.done{color:#2e9b55;font-weight:700}
.note{color:var(--mut);font-size:12px;margin-top:6px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.card h3{margin:0 0 8px;font-size:14px;color:var(--mut);font-weight:600}
.row{display:flex;justify-content:space-between;gap:10px;padding:3px 0}
.row b{font-weight:500;color:var(--mut)}.row span{font:600 15px ui-monospace,Menlo,monospace;text-align:right}
.big{font:700 22px ui-monospace,Menlo,monospace}
.bar{height:8px;border-radius:4px;background:var(--line);overflow:hidden;margin:4px 0 8px}
.bar i{display:block;height:100%;background:var(--acc)}
.ok{color:#2e9b55;font-weight:700}.warn{color:#d0731b;font-weight:700}
.card table{width:100%;min-width:0;table-layout:fixed;border:none;background:none;margin-top:4px}
.card th,.card td{padding:3px 4px;font-size:12px}.card td:last-child,.card th{white-space:normal}
.card th:first-child,.card td:first-child{width:22%}
details{margin-top:18px}summary{cursor:pointer;font-size:16px;font-weight:600;padding:6px 0}
.top{position:fixed;right:16px;bottom:16px;background:var(--card);border:1px solid var(--line);border-radius:20px;padding:6px 12px}
</style></head><body><main>]]

-- ── Report page (shared by both modes) ──────────────────────────────────────
local function html_esc(v)
  return (tostring(v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- Saves the page in the project folder as "<folder name> - PM Insight.html"
-- (one report per folder, replaced on every run) and opens it in the browser.
local function write_and_open_report(h)
  local _, proj_path = r.EnumProjects(-1)
  local dir = (proj_path or ""):match("^(.*)[/\\]")
  if not dir or dir == "" then dir = r.GetProjectPath("") end
  local sep  = r.GetOS():match("^Win") and "\\" or "/"
  local base = dir:match("([^/\\]+)$") or "Session"
  local name = base .. " - PM Insight.html"
  local file = dir .. sep .. name

  -- Remove reports from earlier versions: one per .rpp ("<project> - PM Insight.html")
  -- and timestamped ones (insight_YYMMDD_HHMMSS.html)
  local old_reports, k = {}, 0
  while true do
    local fn = r.EnumerateFiles(dir, k)
    if not fn then break end
    if fn ~= name and (fn:match(" %- PM Insight%.html$")
        or fn:match("^insight_%d%d%d%d%d%d_%d%d%d%d%d%d%.html$")) then
      old_reports[#old_reports + 1] = fn
    end
    k = k + 1
  end
  for _, fn in ipairs(old_reports) do os.remove(dir .. sep .. fn) end
  local fh = io.open(file, "w")
  if not fh then
    r.ShowMessageBox("Cannot write the report:\n" .. file, "PM Insight Analyzer", 0)
    return
  end
  fh:write(table.concat(h, "\n"))
  fh:close()

  if r.CF_ShellExecute then
    r.CF_ShellExecute(file)
  elseif sep == "\\" then
    os.execute('start "" "' .. file .. '"')
  else
    os.execute('open "' .. file .. '"')
  end
  r.ShowConsoleMsg("PM Insight report saved:\n" .. file .. "\n")
end

-- ── Work Log Mode ───────────────────────────────────────────────────────────
-- Work type names that mean the same thing (lowercase → name in the report).
-- "\u{6311}mic" is the older Chinese name for mic select ("pick mic").
local MODULE_ALIASES = { ["\u{6311}mic"] = "mic select" }
-- Spelling used when names differ only in upper / lower case
local KNOWN_TYPES = { "mic select", "editing", "denoise", "scene", "ME", "PAN", "ME+PAN", "check",
  "conform", "picture cut", "subtitle", "aap", "pre-production", "wrap" }

-- Picks one spelling per lowercase name: a known work type (use_known), else the
-- most used one (lowercase wins a tie).
local function canonical_names(values, use_known)
  local known = {}
  if use_known then for _, t in ipairs(KNOWN_TYPES) do known[t:lower()] = t end end
  local counts = {}
  for _, v in ipairs(values) do
    local lk = v:lower()
    counts[lk] = counts[lk] or {}
    counts[lk][v] = (counts[lk][v] or 0) + 1
  end
  local pick = {}
  for lk, spellings in pairs(counts) do
    if known[lk] then pick[lk] = known[lk]
    else
      local best, bn = nil, -1
      for s, n in pairs(spellings) do
        if n > bn or (n == bn and (s == lk or (best ~= lk and s < best))) then best, bn = s, n end
      end
      pick[lk] = best
    end
  end
  return pick
end

-- All work log items as records, names normalized, duplicates removed.
-- A duplicate = same date track, position and length (e.g. a copy of a project
-- also synced to the Work Log); the copy whose project has more items is kept.
local function collect_work_log_records()
  local raw = {}
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    local _, track_name = r.GetTrackName(track)
    local is_date_track = track_name:match(DATE_PAT) ~= nil
    for j = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, j)
      local take = r.GetActiveTake(item)
      local take_name = take and r.GetTakeName(take) or ""
      local parsed = take_name ~= "" and parse_wl_item_name(take_name) or nil
      local dur = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if parsed and dur > 0 then
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        local ni  = parse_note_fields(note)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local _, project, task = split_prefix(take_name)
        local module = (parsed.module ~= "") and parsed.module or "other"
        module = MODULE_ALIASES[module:lower()] or module
        task = task:gsub("_%d+$", "")   -- "Conform_001": save-as copy of the project
        local color = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
        raw[#raw + 1] = {
          track = i, pos = pos, len = dur,
          date = is_date_track and track_name or "(no date)",
          start_tc = fmt_tc(pos), end_tc = fmt_tc(pos + dur),
          project = project ~= "" and project or "(unknown)",
          task = task ~= "" and task or "(unknown)",
          module = module, color = (color & 0x1000000 ~= 0) and color or nil,
          shots = ni.shots, src_cnt = ni.src_cnt, src_len = ni.src_len,
          scope = ni.scope, scenes = ni.scenes,
        }
      end
    end
  end

  for _, field in ipairs({ "project", "task", "module" }) do
    local vals = {}
    for _, x in ipairs(raw) do vals[#vals + 1] = x[field] end
    local pick = canonical_names(vals, field == "module")
    for _, x in ipairs(raw) do x[field] = pick[x[field]:lower()] end
  end

  local proj_count = {}
  for _, x in ipairs(raw) do proj_count[x.project] = (proj_count[x.project] or 0) + 1 end
  local by_key, order = {}, {}
  for _, x in ipairs(raw) do
    local key = string.format("%d:%.1f:%.1f", x.track, x.pos, x.len)
    local cur = by_key[key]
    if not cur then by_key[key] = x; order[#order + 1] = key
    elseif proj_count[x.project] > proj_count[cur.project] then by_key[key] = x end
  end
  local recs = {}
  for _, key in ipairs(order) do recs[#recs + 1] = by_key[key] end
  table.sort(recs, function(a, b)
    if a.date ~= b.date then return a.date < b.date end
    return a.pos < b.pos
  end)
  return recs, #raw - #recs
end

-- Writes one report section (all years or one year) for the given records.
local function work_log_section(out, recs, sid)
  local total, daily, months, projects, proj_order = 0, {}, {}, {}, {}
  local tasks, modules, mod_color = {}, {}, {}
  for _, x in ipairs(recs) do
    total = total + x.len
    daily[x.date] = (daily[x.date] or 0) + x.len
    local ym = x.date:match("^(%d%d%d%d%-%d%d)") or "(no date)"
    local m = months[ym]
    if not m then m = { total = 0, days = {}, items = 0 }; months[ym] = m end
    m.total, m.items, m.days[x.date] = m.total + x.len, m.items + 1, true
    local p = projects[x.project]
    if not p then
      p = { total = 0, days = {}, items = {}, tasks = {}, modules = {}, first = x.date, last = x.date }
      projects[x.project] = p; proj_order[#proj_order + 1] = x.project
    end
    p.total = p.total + x.len
    p.days[x.date] = (p.days[x.date] or 0) + x.len
    p.items[#p.items + 1] = x
    p.tasks[x.task]     = (p.tasks[x.task] or 0) + x.len
    p.modules[x.module] = (p.modules[x.module] or 0) + x.len
    if x.date < p.first then p.first = x.date end
    if x.date > p.last  then p.last  = x.date end
    tasks[x.task]     = (tasks[x.task] or 0) + x.len
    modules[x.module] = (modules[x.module] or 0) + x.len
    if x.color and not mod_color[x.module] then mod_color[x.module] = x.color end
  end
  table.sort(proj_order, function(a, b) return projects[a].total > projects[b].total end)

  local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
  local function pct(a, b) return b > 0 and string.format("%d%%", math.floor(a / b * 100 + 0.5)) or "–" end
  local function mod_label(m)
    local c = mod_color[m]
    if not c then return html_esc(m) end
    local cr, cg, cb = r.ColorFromNative(c & 0xFFFFFF)
    return string.format('<span class="dot" style="background:rgb(%d,%d,%d)"></span>%s', cr, cg, cb, html_esc(m))
  end
  local function totals_table(title, tbl, label_fn, open)
    out('<details' .. (open and ' open' or '') .. '><summary>' .. title .. '</summary><div class="wrap"><table>')
    out('<tr><th class="l">Name</th><th>Time</th><th>Share</th></tr>')
    for _, k in ipairs(sort_keys_by_value(tbl)) do
      out(string.format('<tr><td class="l">%s</td><td>%s</td><td>%s</td></tr>',
        (label_fn or html_esc)(k), fmt_dur(tbl[k]), pct(tbl[k], total)))
    end
    out('</table></div></details>')
  end

  local avg, used, ndays = trimmed_daily_avg(daily, 0.1)
  out('<div class="grid">')
  local function kv(k, v) out('<div class="kv"><b>' .. k .. '</b><span>' .. v .. '</span></div>') end
  kv("Total Work", fmt_dur(total))
  kv("Work Items", tostring(#recs))
  kv("Working Days", tostring(ndays))
  kv("Avg Daily Work", ndays > 0 and (fmt_dur(avg) .. string.format(" <small>(mid %d)</small>", used)) or "N/A")
  kv("Projects", tostring(#proj_order))
  out('</div>')

  -- By Month
  local mkeys = {}
  for k in pairs(months) do mkeys[#mkeys + 1] = k end
  table.sort(mkeys)
  out('<details open><summary>By Month</summary><div class="wrap"><table>')
  out('<tr><th class="l">Month</th><th>Total</th><th>Days</th><th>Avg / Day</th><th>Items</th></tr>')
  for _, k in ipairs(mkeys) do
    local m, nd = months[k], count(months[k].days)
    out(string.format('<tr><td class="l">%s</td><td>%s</td><td>%d</td><td>%s</td><td>%d</td></tr>',
      k, fmt_dur(m.total), nd, fmt_dur(nd > 0 and m.total / nd or 0), m.items))
  end
  out('</table></div></details>')

  -- By Project
  out('<details open><summary>By Project</summary><div class="wrap"><table>')
  out('<tr><th class="l">Project</th><th>Total</th><th>Share</th><th>Days</th><th>Items</th>'
    .. '<th class="l">First</th><th class="l">Last</th></tr>')
  for n, pname in ipairs(proj_order) do
    local p = projects[pname]
    out(string.format('<tr><td class="l"><a href="#%s-p%d">%s</a></td><td>%s</td><td>%s</td><td>%d</td><td>%d</td>'
      .. '<td class="l">%s</td><td class="l">%s</td></tr>', sid, n, html_esc(pname), fmt_dur(p.total),
      pct(p.total, total), count(p.days), #p.items, p.first, p.last))
  end
  out('</table></div></details>')

  -- Per project
  out('<details><summary>Per Project</summary>')
  for n, pname in ipairs(proj_order) do
    local p = projects[pname]
    out('<section class="scene" id="' .. sid .. '-p' .. n .. '">')
    out('<h3>' .. html_esc(pname) .. '</h3>')
    out('<div class="meta">' .. fmt_dur(p.total) .. ' · ' .. count(p.days) .. ' days · '
      .. #p.items .. ' items · ' .. p.first .. ' – ' .. p.last .. '</div>')
    out('<div class="wrap"><table><tr><th class="l">Task</th><th>Time</th><th>Share</th></tr>')
    for _, k in ipairs(sort_keys_by_value(p.tasks)) do
      out(string.format('<tr><td class="l">%s</td><td>%s</td><td>%s</td></tr>',
        html_esc(k), fmt_dur(p.tasks[k]), pct(p.tasks[k], p.total)))
    end
    out('</table></div><div class="wrap" style="margin-top:8px"><table>'
      .. '<tr><th class="l">Work Type</th><th>Time</th><th>Share</th></tr>')
    for _, k in ipairs(sort_keys_by_value(p.modules)) do
      out(string.format('<tr><td class="l">%s</td><td>%s</td><td>%s</td></tr>',
        mod_label(k), fmt_dur(p.modules[k]), pct(p.modules[k], p.total)))
    end
    out('</table></div>')
    out('<details><summary>Sessions (' .. #p.items .. ')</summary><div class="wrap"><table>')
    out('<tr><th class="l">Date</th><th class="l">Time</th><th>Length</th><th class="l">Task</th>'
      .. '<th class="l">Work Type</th><th>Shots</th><th>Src Cnt</th><th>Src Len</th><th class="l">Scope</th></tr>')
    for _, x in ipairs(p.items) do
      local scope = x.scope
      if x.scenes ~= "" then scope = scope .. (scope ~= "" and " · " or "") .. x.scenes .. " scenes" end
      out(string.format('<tr><td class="l">%s</td><td class="l">%s – %s</td><td>%s</td><td class="l">%s</td>'
        .. '<td class="l">%s</td><td>%s</td><td>%s</td><td>%s</td><td class="l">%s</td></tr>',
        x.date, x.start_tc, x.end_tc, fmt_dur(x.len), html_esc(x.task), mod_label(x.module),
        html_esc(x.shots), html_esc(x.src_cnt), html_esc(x.src_len), html_esc(scope)))
    end
    out('</table></div></details></section>')
  end
  out('</details>')

  totals_table("By Work Type", modules, mod_label, false)
  totals_table("By Task", tasks, nil, false)

  -- By Day (newest first)
  local dkeys = {}
  for k in pairs(daily) do dkeys[#dkeys + 1] = k end
  table.sort(dkeys, function(a, b) return a > b end)
  out('<details><summary>By Day</summary><div class="wrap"><table><tr><th class="l">Date</th><th>Total</th></tr>')
  for _, k in ipairs(dkeys) do
    out(string.format('<tr><td class="l">%s</td><td>%s</td></tr>', k, fmt_dur(daily[k])))
  end
  out('</table></div></details>')
end

local function analyze_work_log()
  local recs, dups = collect_work_log_records()
  local years, yset = {}, {}
  for _, x in ipairs(recs) do
    local y = x.date:match("^(%d%d%d%d)")
    if y and not yset[y] then yset[y] = true; years[#years + 1] = y end
  end
  table.sort(years, function(a, b) return a > b end)

  local h = {}
  local function out(s) h[#h + 1] = s end
  out(REPORT_HEAD)
  out('<h1 id="top">PM Insight · Work Log</h1>')
  local _, proj_path = r.EnumProjects(-1)
  local pname = ((proj_path or ""):match("([^/\\]+)$") or ""):gsub("%.[Rr][Pp][Pp]$", "")
  out('<div class="sub">' .. html_esc(pname) .. ' · ' .. os.date("%Y-%m-%d %H:%M") .. '</div>')
  out('<div class="sub">Year: <select id="year"><option value="all">All</option>')
  for _, y in ipairs(years) do out('<option value="' .. y .. '">' .. y .. '</option>') end
  out('</select></div>')
  if dups > 0 then
    out(string.format('<div class="note">%d duplicate item%s skipped (same day, position and length - '
      .. 'e.g. a copy of a project also synced to the Work Log).</div>', dups, dups == 1 and "" or "s"))
  end
  if #recs == 0 then out('<p>(no work log items found)</p>') end

  out('<div class="yr" data-y="all">')
  work_log_section(out, recs, "all")
  out('</div>')
  for _, y in ipairs(years) do
    local sub = {}
    for _, x in ipairs(recs) do if x.date:sub(1, 4) == y then sub[#sub + 1] = x end end
    out('<div class="yr" data-y="' .. y .. '" style="display:none">')
    work_log_section(out, sub, "y" .. y)
    out('</div>')
  end
  out('<a class="top" href="#top">↑ Top</a></main>')
  out([[<script>
document.getElementById("year").addEventListener("change",function(e){
  document.querySelectorAll(".yr").forEach(function(d){d.style.display=d.dataset.y===e.target.value?"":"none";});});
document.querySelectorAll('a[href*="-p"]').forEach(function(a){a.addEventListener("click",function(){
  var t=document.querySelector(a.getAttribute("href"));var d=t&&t.parentElement.closest("details");if(d)d.open=true;});});
</script></body></html>]])
  write_and_open_report(h)
end
local function analyze()

  -- 1. Find Scene Cut track ──────────────────────────────────────────────────
  local scene_track = nil
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname == SCENE_TRACK_NAME then scene_track = t; break end
  end
  if not scene_track then
    analyze_work_log()
    return
  end

  -- 2. Build scene_map from Scene Cut items ─────────────────────────────────
  local scene_map   = {}   -- [guid] → scene data table
  local scene_order = {}   -- GUIDs in project order
  local scenes      = {}   -- array for indexed access (needed for range calc)

  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local item  = r.GetTrackMediaItem(scene_track, i)
    local pos   = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local len   = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local guid  = r.BR_GetMediaItemGUID(item)
    local color = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))

    local name = ""
    local take = r.GetActiveTake(item)
    if take then name = r.GetTakeName(take) end
    if name == "" then
      local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      name = (notes and notes ~= "") and notes or "(unnamed)"
    end

    local is_done = r.GetMediaItemInfo_Value(item, "B_MUTE") == 1

    local sc = {
      guid              = guid,
      name              = name,
      color             = color,
      is_done           = is_done,
      start_pos         = pos,
      end_pos           = pos + len,
      start_tc          = fmt_tc(pos),
      end_tc            = fmt_tc(pos + len),
      length_sec        = len,
      source_length_sec = 0,   -- from EDL attribution
      wt_sec            = {},  -- work_type → secs on this scene
      total_sec         = 0,   -- all scene work types combined
      group             = math.floor(r.GetMediaItemInfo_Value(item, "I_GROUPID")),
      stage             = {},  -- key → { n = items, open = items not muted yet }
    }

    scene_map[guid] = sc
    table.insert(scene_order, guid)
    table.insert(scenes, sc)
  end

  -- 2b. Selected Scene Cut items limit the report to those scenes (none = whole project).
  --     Everything is still computed for every scene (split-scene shares need them
  --     all); the selection only decides what is reported.
  local picked, n_picked = {}, 0
  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local item = r.GetTrackMediaItem(scene_track, i)
    if r.IsMediaItemSelected(item) then
      picked[r.BR_GetMediaItemGUID(item)] = true
      n_picked = n_picked + 1
    end
  end
  local sel_mode = n_picked > 0
  local function shown(sc) return not sel_mode or picked[sc.guid] == true end

  -- 3. Pre-compute colour-fallback lookup ranges (same as SceneAnalyzer) ─────
  --    range_start = prev scene start (or this scene start if first)
  --    range_end   = next scene end   (or this scene end  if last)
  local scene_ranges = {}
  for idx, sc in ipairs(scenes) do
    local prev = scenes[idx - 1]
    local nxt  = scenes[idx + 1]
    scene_ranges[idx] = {
      range_start = prev and prev.start_pos or sc.start_pos,
      range_end   = nxt  and nxt.end_pos   or sc.end_pos,
    }
  end

  -- 4. Attribute EDL source items to scenes ──────────────────────────────────
  --    Priority 1: P_EXT:SCENE_ID exact GUID match
  --    Priority 2: colour match AND item inside scene's lookup range
  local edl_tracks = find_folder_children(EDL_FOLDER_NAME)

  for _, t in ipairs(edl_tracks) do
    for i = 0, r.CountTrackMediaItems(t) - 1 do
      local item       = r.GetTrackMediaItem(t, i)
      local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local item_len   = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local item_end   = item_start + item_len
      local item_color = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))

      -- Priority 1: P_EXT:SCENE_ID exact GUID match
      local _, scene_id = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_ID", "", false)
      local att
      if scene_id ~= "" and scene_map[scene_id] then
        att = scene_map[scene_id]
        scene_map[scene_id].source_length_sec =
          scene_map[scene_id].source_length_sec + item_len

      -- Priority 2: colour match AND position within lookup range
      else
        for idx, sc in ipairs(scenes) do
          if sc.color ~= 0 and item_color == sc.color then
            local rng = scene_ranges[idx]
            if item_start >= rng.range_start and item_end <= rng.range_end then
              sc.source_length_sec = sc.source_length_sec + item_len
              att = sc
              break
            end
          end
        end
      end
      -- stage progress: an EDL item is done (mic select) once it is muted
      if att then
        local st = att.stage.edl or { n = 0, open = 0 }
        att.stage.edl = st
        st.n = st.n + 1
        if r.GetMediaItemInfo_Value(item, "B_MUTE") ~= 1 then st.open = st.open + 1 end
      end
    end
  end

  -- 4b. Project Source Total — sum of ALL items in EDL folder (parent + child tracks)
  local project_source_total_sec = 0
  -- Include parent EDL folder track items
  for i = 0, r.CountTracks(0) - 1 do
    local t        = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    if tname == EDL_FOLDER_NAME and fd == 1 then
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        local item = r.GetTrackMediaItem(t, j)
        project_source_total_sec = project_source_total_sec
          + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      end
      break
    end
  end
  -- Include child track items
  for _, t in ipairs(edl_tracks) do
    for i = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, i)
      project_source_total_sec = project_source_total_sec
        + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    end
  end

  -- 4c. Override source_length_sec from scene item P_NOTES (pre-computed by SceneAnalyzer)
  --     Format: "Src Len : HH:MM:SS:FF" — parse manually; frames ignored (sub-second)
  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local item = r.GetTrackMediaItem(scene_track, i)
    local guid = r.BR_GetMediaItemGUID(item)
    if guid and scene_map[guid] then
      local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      if notes and notes ~= "" then
        -- Later source stages (PM Timer, only when the folders exist)
        for key, field in pairs({ Sel = "sel_len_sec", Edit = "edit_len_sec" }) do
          local h, m, sec = notes:match(key .. "%sLen%s*:%s*(%d+):(%d+):(%d+)")
          if h then scene_map[guid][field] = tonumber(h)*3600 + tonumber(m)*60 + tonumber(sec) end
        end
        local src_len_str = notes:match("Src%sLen%s*:%s*([%d:]+)")
        if src_len_str then
          -- parse_timestr mis-handles HH:MM:SS:FF; extract H/M/S explicitly
          local h, m, s = src_len_str:match("^(%d+):(%d+):(%d+)")
          if h then
            local sec = tonumber(h)*3600 + tonumber(m)*60 + tonumber(s)
            if sec > 0 then
              scene_map[guid].source_length_sec = sec
            end
          end
        end
      end
    end
  end

  -- 4d. Later stage folders (same attribution as PM Timer's Sel Len / Edit Len): an item in a
  --     scene's item group belongs to that scene; an item not grouped with any scene belongs to
  --     the scenes it overlaps. Muted = that stage is done for the item.
  local STAGES = {
    { key = "edl",  folder = EDL_FOLDER_NAME,       wt = "mic select", label = "Mic select",  src = "EDL" },
    { key = "sel",  folder = MIC_SELECTED_FOLDER,   wt = "editing",    label = "Editing",     src = "Mic Selected" },
    { key = "edit", folder = EDITED_FOLDER,         wt = "denoise",    label = "Denoise",     src = "Edited" },
  }
  local scene_by_group = {}
  for _, sc in ipairs(scenes) do if sc.group ~= 0 then scene_by_group[sc.group] = sc end end
  local stage_exists = { edl = #edl_tracks > 0 }
  for _, stg in ipairs(STAGES) do
    if stg.key ~= "edl" then
      local kids = find_folder_children(stg.folder)
      stage_exists[stg.key] = #kids > 0
      for _, t in ipairs(kids) do
        for i = 0, r.CountTrackMediaItems(t) - 1 do
          local item = r.GetTrackMediaItem(t, i)
          local s0 = r.GetMediaItemInfo_Value(item, "D_POSITION")
          local s1 = s0 + r.GetMediaItemInfo_Value(item, "D_LENGTH")
          local open = r.GetMediaItemInfo_Value(item, "B_MUTE") ~= 1
          local g = math.floor(r.GetMediaItemInfo_Value(item, "I_GROUPID"))
          local targets = {}
          if g ~= 0 and scene_by_group[g] then
            targets[1] = scene_by_group[g]
          else
            for _, sc in ipairs(scenes) do
              if math.min(s1, sc.end_pos) - math.max(s0, sc.start_pos) > 0 then targets[#targets + 1] = sc end
            end
          end
          for _, sc in ipairs(targets) do
            local st = sc.stage[stg.key] or { n = 0, open = 0 }
            sc.stage[stg.key] = st
            st.n = st.n + 1
            if open then st.open = st.open + 1 end
          end
        end
      end
    end
  end
  -- "done" = the scene has items in that stage folder and all of them are muted. A stage with
  -- no items is skipped (done) when a later stage already has items for the scene
  -- (e.g. EDL -> Edited directly, Mic Selected left empty), or when nothing later has items
  -- and the scene is muted on Scene Cut (a scene without dialogue - user 26.1026);
  -- otherwise it is not done yet.
  local function stage_done(sc, key)
    local st = sc.stage[key]
    if st and st.n > 0 then return st.open == 0 end
    local later = false
    for _, stg in ipairs(STAGES) do
      if later then
        local s2 = sc.stage[stg.key]
        if s2 and s2.n > 0 then return true end
      end
      if stg.key == key then later = true end
    end
    return sc.muted == true
  end

  -- A scene is finished when every stage is done (user rule 26.1025: the Scene Cut mute is
  -- sometimes used as a temporary marker, e.g. "mic select done", so it does not mean finished).
  -- Only a project without any stage folder still uses the Scene Cut mute.
  local any_stage = stage_exists.edl or stage_exists.sel or stage_exists.edit
  for _, sc in ipairs(scenes) do
    sc.muted = sc.is_done
    if any_stage then
      local all = true
      for _, stg in ipairs(STAGES) do
        if stage_exists[stg.key] and not stage_done(sc, stg.key) then all = false; break end
      end
      sc.is_done = all
    end
  end

  -- 5. Walk Scene Cut child tracks and accumulate work times ─────────────────
  local sc_num       = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local total_tracks = r.CountTracks(0)
  local depth        = 1

  local project_work_total = 0   -- Project Mode work (no SCENE_GUID)
  local daily_totals       = {}  -- "YYYY-MM-DD" → total work secs that day
  local wt_totals          = {}  -- work_type → total secs across all items
  local wt_project         = {}  -- work_type → secs of Project Mode work (no scene)
  local wt_color           = {}  -- work_type → native item color (first seen)

  for i = sc_num, total_tracks - 1 do
    local t        = r.GetTrack(0, i)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)

    if tname:match(DATE_PAT) or tname == DURATION_LOG_NAME then
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        local item = r.GetTrackMediaItem(t, j)

        local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE", "", false)
        if wt ~= "" then
          -- Duration: prefer P_EXT:DURATION, fallback D_LENGTH
          local dur_secs = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          if dur_secs < 0 then dur_secs = 0 end
          if dur_secs > 0 and tname:match(DATE_PAT) then
            daily_totals[tname] = (daily_totals[tname] or 0) + dur_secs
          end
          if dur_secs > 0 then
            wt_totals[wt] = (wt_totals[wt] or 0) + dur_secs
          end
          if not wt_color[wt] then
            local c = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
            if c & 0x1000000 ~= 0 then wt_color[wt] = c end
          end

          local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
          -- Scene split after the work was logged (PM Timer > Link Split Scenes):
          -- share the time between the pieces by source length (film length if
          -- the pieces have no source length).
          local _, sp = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_SPLIT", "", false)
          local shares = {}
          for g in sp:gmatch("[^|]+") do
            if scene_map[g] then shares[#shares + 1] = { sc = scene_map[g] } end
          end
          if #shares == 0 and sg ~= "" and scene_map[sg] then
            shares[1] = { sc = scene_map[sg], w = 1 }
          elseif #shares > 0 then
            local src, film = 0, 0
            for _, x in ipairs(shares) do
              src = src + x.sc.source_length_sec; film = film + x.sc.length_sec
            end
            for _, x in ipairs(shares) do
              if src > 0 then x.w = x.sc.source_length_sec / src
              elseif film > 0 then x.w = x.sc.length_sec / film
              else x.w = 1 / #shares end
            end
          end
          if #shares > 0 then
            -- Scene Mode: attribute to scene(s)
            for _, x in ipairs(shares) do
              local sc, secs = x.sc, dur_secs * x.w
              sc.wt_sec[wt] = (sc.wt_sec[wt] or 0) + secs
              sc.total_sec  = sc.total_sec + secs
              -- dates: last day of each work type (stage finish dates) and work per day
              if tname:match(DATE_PAT) and dur_secs > 0 then
                sc.last_date = sc.last_date or {}
                if not sc.last_date[wt] or tname > sc.last_date[wt] then sc.last_date[wt] = tname end
                sc.day_work = sc.day_work or {}
                sc.day_work[tname] = (sc.day_work[tname] or 0) + secs
              end
            end
          else
            -- Project Mode: no scene attribution
            project_work_total = project_work_total + dur_secs
            wt_project[wt] = (wt_project[wt] or 0) + dur_secs
          end
        end
      end
    end

    depth = depth + fd
    if depth <= 0 then break end
  end

  -- 6. Project-level aggregates ──────────────────────────────────────────────
  local project_film_total_sec  = 0
  local project_scene_total_sec = 0   -- sum of all scene work (not project work)
  local completed_film_sec      = 0   -- progress by B_MUTE (scene marked done)
  local remaining_film_sec      = 0

  -- Source/hr always uses the EDL source, whatever the work type (user choice 26.1025)
  local function input_source(sc)
    return sc.source_length_sec
  end
  local has_sel, has_edit = false, false
  for _, sc in ipairs(scenes) do
    if not shown(sc) then goto next_scene end
    if sc.sel_len_sec  then has_sel  = true end
    if sc.edit_len_sec then has_edit = true end
    ::next_scene::
  end

  -- Efficiency per work type: every scene that has work of that type counts
  -- (its film and input source length), whether or not the scene is marked done.
  local eff = {}          -- work_type → { scenes, film, source, work }
  local eff_total = { scenes = 0, film = 0, source = 0, work = 0 }

  for _, guid in ipairs(scene_order) do
    local sc = scene_map[guid]
    if not shown(sc) then goto next_guid end
    project_film_total_sec  = project_film_total_sec  + sc.length_sec
    project_scene_total_sec = project_scene_total_sec + sc.total_sec
    if sc.is_done then
      completed_film_sec = completed_film_sec + sc.length_sec
    else
      remaining_film_sec = remaining_film_sec + sc.length_sec
    end
    for wt, secs in pairs(sc.wt_sec) do
      local e = eff[wt]
      if not e then e = { scenes = 0, film = 0, source = 0, work = 0 }; eff[wt] = e end
      e.scenes = e.scenes + 1
      e.film   = e.film   + sc.length_sec
      e.source = e.source + input_source(sc, wt)
      e.work   = e.work   + secs
    end
    if sc.total_sec > 0 then
      eff_total.scenes = eff_total.scenes + 1
      eff_total.film   = eff_total.film   + sc.length_sec
      eff_total.source = eff_total.source + sc.source_length_sec
      eff_total.work   = eff_total.work   + sc.total_sec
    end
    ::next_guid::
  end

  local grand_total = project_scene_total_sec + project_work_total
  local dl_avg, dl_used, dl_all = trimmed_daily_avg(daily_totals, 0.1)

  -- Work types in workflow order, then any other (custom) types A-Z
  local TYPE_ORDER = { "mic select", "editing", "denoise", "scene", "ME", "PAN", "ME+PAN", "check" }
  local types, seen = {}, {}
  local type_src = sel_mode and eff or wt_totals   -- selected scenes: only their work types
  for _, t in ipairs(TYPE_ORDER) do
    if type_src[t] then types[#types + 1] = t; seen[t] = true end
  end
  local others = {}
  for t in pairs(type_src) do if not seen[t] then others[#others + 1] = t end end
  table.sort(others, function(a, b) return a:lower() < b:lower() end)
  for _, t in ipairs(others) do types[#types + 1] = t end
  local scene_types = {}   -- types with scene work (columns of the scene list)
  for _, t in ipairs(types) do if eff[t] then scene_types[#scene_types + 1] = t end end

  -- 7. Build the HTML report ─────────────────────────────────────────────────
  local function esc(v)
    return (tostring(v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
  end
  local function pct(a, b)
    if b <= 0 then return "N/A" end
    return string.format("%d%%", math.floor(a / b * 100))
  end
  local function dur_or_dash(secs)
    return (secs and secs > 0) and fmt_dur(secs) or "–"
  end
  local function type_label(t)
    local c = wt_color[t]
    if not c then return esc(t) end
    local cr, cg, cb = r.ColorFromNative(c & 0xFFFFFF)
    return string.format('<span class="dot" style="background:rgb(%d,%d,%d)"></span>%s', cr, cg, cb, esc(t))
  end

  local _, proj_path = r.EnumProjects(-1)
  local proj_name = (proj_path or ""):match("([^/\\]+)$") or ""
  proj_name = proj_name:gsub("%.[Rr][Pp][Pp]$", "")
  if proj_name == "" then proj_name = "(unsaved project)" end

  local h = {}
  local function out(s) h[#h + 1] = s end

  out(REPORT_HEAD)
  out('<h1 id="top">PM Insight Report</h1>')
  out('<div class="sub">' .. esc(proj_name) .. ' · ' .. os.date("%Y-%m-%d %H:%M") .. '</div>')
  if sel_mode then
    local names = {}
    for _, guid in ipairs(scene_order) do
      local sc = scene_map[guid]
      if shown(sc) then names[#names + 1] = esc(sc.name ~= "" and sc.name or "(unnamed)") end
    end
    out(string.format('<div class="sub"><b>Selected scenes: %d of %d</b> · %s</div>',
      n_picked, #scene_order, table.concat(names, ", ")))
  end

  -- Overview: the four questions first (time, efficiency, progress, plan); details below
  local function fmt_h(secs) return string.format("%.1fh", (secs or 0) / 3600) end
  local function card(title) out('<div class="card"><h3>' .. title .. '</h3>') end
  local function row(k, v) out('<div class="row"><b>' .. k .. '</b><span>' .. v .. '</span></div>') end
  local function bar(frac)
    frac = math.max(0, math.min(1, frac or 0))
    out(string.format('<div class="bar"><i style="width:%.1f%%"></i></div>', frac * 100))
  end
  -- Efficiency only counts finished content: work on a scene that is still in progress would
  -- make the rate look better than it is (user rule 26.1025).
  -- Stage rate = EDL source of the scenes whose stage is done, per second of that stage's work
  -- on them (used for the estimates); nil when no finished scene has that work.
  local function stage_rate(stg)
    local src, work = 0, 0
    for _, sc in ipairs(scenes) do
      local w = sc.wt_sec[stg.wt]
      if shown(sc) and w and w > 0 and stage_done(sc, stg.key) then
        src, work = src + sc.source_length_sec, work + w
      end
    end
    if work > 0 and src > 0 then return src / work, work end
  end

  -- Progress by stage, computed first so Work time can show the overall completion:
  -- a stage is done for a scene when all its items there are muted (skipped stages
  -- count as done); remaining = EDL source of the scenes not done yet, estimated with
  -- the stage rate of the finished scenes
  local n_scenes, n_finished = 0, 0
  for _, sc in ipairs(scenes) do
    if shown(sc) then
      n_scenes = n_scenes + 1
      if sc.is_done then n_finished = n_finished + 1 end
    end
  end
  local remaining_work, any_estimate = 0, false   -- seconds of work still needed (estimate)
  local stage_info = {}
  for _, stg in ipairs(STAGES) do
    if stage_exists[stg.key] then
      local done, rem_src = 0, 0
      for _, sc in ipairs(scenes) do
        if shown(sc) then
          if stage_done(sc, stg.key) then done = done + 1 else rem_src = rem_src + sc.source_length_sec end
        end
      end
      local rate = stage_rate(stg)
      local est = rate and rem_src / rate
      if est then remaining_work = remaining_work + est; any_estimate = true end
      stage_info[#stage_info + 1] = { stg = stg, done = done, rem_src = rem_src, est = est }
    end
  end

  out('<h2>' .. (sel_mode and 'Selected Scenes' or 'Overview') .. '</h2><div class="cards">')

  -- 1. Completion and work time in one card, no time estimate (user 26.1026):
  --    Film   = film of the scenes marked done on Scene Cut (item muted) / all film
  --    Source = EDL source of the finished scenes (every stage done) / all source
  local work_total = sel_mode and project_scene_total_sec or grand_total
  local film_all, film_done, src_all, src_done, n_marked = 0, 0, 0, 0, 0
  for _, sc in ipairs(scenes) do
    if shown(sc) then
      film_all, src_all = film_all + sc.length_sec, src_all + sc.source_length_sec
      if sc.muted then film_done, n_marked = film_done + sc.length_sec, n_marked + 1 end
      if sc.is_done then src_done = src_done + sc.source_length_sec end
    end
  end
  local function pct_of(a, b) return b > 0 and math.floor(a / b * 100 + 0.5) or 0 end
  card("Completion")
  out('<div style="display:flex;gap:18px">'
    .. '<div><div class="big">' .. pct_of(film_done, film_all) .. '%</div><small>film</small></div>'
    .. '<div><div class="big">' .. pct_of(src_done, src_all) .. '%</div><small>source</small></div></div>')
  row("Film done", fmt_dur(film_done) .. ' <small>/ ' .. fmt_dur(film_all) .. '</small>')
  bar(film_all > 0 and film_done / film_all or 0)
  row("Source done", fmt_dur(src_done) .. ' <small>/ ' .. fmt_dur(src_all) .. '</small>')
  bar(src_all > 0 and src_done / src_all or 0)
  row("Scenes marked done", string.format("%d / %d", n_marked, n_scenes))
  row("Scenes finished", string.format("%d / %d", n_finished, n_scenes))
  out('<div class="note">Film: scenes muted on Scene Cut. Source: EDL source of the finished scenes '
    .. '(every stage done - items muted in EDL / Mic Selected / Edited).</div>')
  out('<div style="border-top:1px solid var(--line);margin:8px 0 4px"></div>')
  row("Work time", '<span class="big" style="font-size:18px">' .. fmt_h(work_total) .. '</span>')
  if not sel_mode then
    local cutoff = os.date("%Y-%m-%d", os.time() - 6 * 86400)
    local last7 = 0
    for day, secs in pairs(daily_totals) do if day >= cutoff then last7 = last7 + secs end end
    row("Working days", tostring(dl_all))
    row("Per day (typical)", dl_all > 0 and fmt_h(dl_avg) or "N/A")
    row("Last 7 days", fmt_h(last7))
    row("Without a scene", fmt_h(project_work_total))
  end
  out('</div>')

  -- 2. Efficiency from finished scenes only (Scene Cut item muted): their film / EDL source
  --    per hour of all the work logged on them (every work type). Scenes without logged work
  --    are left out (nothing to divide by).
  local done_n, done_film, done_src, done_work = 0, 0, 0, 0
  for _, sc in ipairs(scenes) do
    if shown(sc) and sc.is_done and sc.total_sec > 0 then
      done_n = done_n + 1
      done_film, done_src, done_work = done_film + sc.length_sec, done_src + sc.source_length_sec, done_work + sc.total_sec
    end
  end
  card("Efficiency (finished scenes)")
  row("Film per hour", rate_or_na(done_film, done_work))
  row("Source (EDL) per hour", rate_or_na(done_src, done_work))
  if done_n > 0 then
    out('<div class="note">' .. done_n .. ' finished scene' .. (done_n > 1 and 's' or '') .. ': film ' .. fmt_dur(done_film)
      .. ' · source ' .. fmt_dur(done_src) .. ' · work ' .. fmt_h(done_work) .. '</div>')
  else
    out('<div class="note">No finished scene with logged work yet (a scene is finished when its items are muted in every stage folder).</div>')
  end
  local first = true
  for _, stg in ipairs(STAGES) do
    if stage_exists[stg.key] then
      local rate = stage_rate(stg)
      if rate then
        if first then out('<div class="note" style="margin-top:8px">By stage (source per hour of that work, finished stages only):</div>'); first = false end
        row("&nbsp;&nbsp;" .. esc(stg.wt), fmt_rate(rate * 3600))
      end
    end
  end
  out('</div>')

  -- 3. Progress by stage (computed above)
  local per_stage = {}
  card("Progress")
  for _, si in ipairs(stage_info) do
    local stg = si.stg
    per_stage[#per_stage + 1] = { stg = stg, rem_src = si.rem_src }
    row(stg.label .. " <small>(" .. stg.src .. ")</small>", string.format("%d / %d", si.done, n_scenes))
    bar(n_scenes > 0 and si.done / n_scenes or 0)
    row("&nbsp;&nbsp;source left · est. work", fmt_dur(si.rem_src) .. " · " .. (si.est and fmt_h(si.est) or "N/A"))
  end
  row("Scenes finished", string.format("%d / %d", n_finished, n_scenes))
  out('<div class="note">Finished = every stage done (items muted in EDL / Mic Selected / Edited).</div>')
  bar(project_film_total_sec > 0 and completed_film_sec / project_film_total_sec or 0)
  if any_estimate then row("Estimated work left", '<span class="big">' .. fmt_h(remaining_work) .. '</span>') end
  out('</div>')

  -- 4. Plan: target hours and delivery date (set in PM Timer, saved in the project)
  if not sel_mode then
    local _, t_hours = r.GetProjExtState(0, "hsuanice_PM", "TARGET_HOURS")
    local _, due = r.GetProjExtState(0, "hsuanice_PM", "DUE_DATE")
    local _, per_day_h = r.GetProjExtState(0, "hsuanice_PM", "HOURS_PER_DAY")
    per_day_h = tonumber(per_day_h) or 5          -- one working day (PM Timer target, default 5h)
    local day_secs = per_day_h * 3600
    t_hours = tonumber(t_hours)
    local y, m, d = (due or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    card("Plan")
    if not t_hours and not y then
      out('<div class="note">Set the target hours and the delivery date in PM Timer (top right).</div>')
    else
      local days
      if y then
        local due_t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
        local now = os.date("*t")
        local today_t = os.time({ year = now.year, month = now.month, day = now.day, hour = 12 })
        days = math.floor((due_t - today_t) / 86400 + 0.5)
        row("Delivery", esc(due) .. " · " .. (days > 0 and (days .. " days left") or days == 0 and "today"
          or ('<span class="warn">' .. -days .. " days late</span>")))
      end
      local per_day_div = (days and days > 0) and days or 1
      if t_hours then
        local left = t_hours * 3600 - grand_total
        row("Work hours", fmt_h(grand_total) .. " / " .. string.format("%gh", t_hours))
        bar(grand_total / (t_hours * 3600))
        row("Hours left", left >= 0 and fmt_h(left) or ('<span class="warn">' .. fmt_h(-left) .. " over</span>"))
        if days then
          local need = math.max(left, 0) / per_day_div
          row("Per day", fmt_h(need) .. string.format(" <small>(%d%% of a %gh day)</small>", math.floor(need / day_secs * 100 + 0.5), per_day_h))
        end
        if any_estimate then
          local fits = remaining_work <= left   -- both in seconds of work
          row("Estimated work left", fmt_h(remaining_work) .. " " .. (fits and '<span class="ok">✓ fits</span>'
            or ('<span class="warn">' .. fmt_h(remaining_work - left) .. " short</span>")))
        end
      end
      -- working days of per_day_h hours: what fits before the delivery, when the work is done
      if any_estimate then
        local days_needed = math.ceil(remaining_work / day_secs)
        local finish = os.date("%Y-%m-%d", os.time() + days_needed * 86400)
        local late = days and days_needed > math.max(days, 0)
        row(string.format("At %gh a day", per_day_h), days_needed .. " days · done ~" .. finish
          .. (days and (late and ' <span class="warn">after delivery</span>' or ' <span class="ok">✓</span>') or ""))
        if days and days > 0 then row("Hours available to delivery", fmt_h(days * day_secs)) end
      end
      -- Pace needed: what is left (scenes not marked done) over the days left, working at least
      -- per_day_h hours each day; compared with the pace of the finished scenes
      if days and days > 0 then
        local left_n, left_src, left_film = 0, 0, 0
        for _, sc in ipairs(scenes) do
          if not sc.is_done then
            left_n, left_src, left_film = left_n + 1, left_src + sc.source_length_sec, left_film + sc.length_sec
          end
        end
        if left_n > 0 then
          local hours_avail = days * day_secs
          out('<div class="note" style="margin-top:10px">Pace needed for the ' .. left_n .. ' scenes left (source '
            .. fmt_dur(left_src) .. ' · film ' .. fmt_dur(left_film) .. '), ' .. days .. ' days × '
            .. string.format("%gh", per_day_h) .. ' = ' .. fmt_h(hours_avail) .. ':</div>')
          out('<table><tr><th class="l"></th><th>Per day</th>'
            .. '<th>Per hour</th><th>Now</th></tr>')
          local function pace_row(label, left, done_len)
            local need_hr = left / hours_avail * 3600          -- length per hour needed
            local now = (done_work > 0 and done_len > 0) and (done_len / done_work * 3600) or nil
            local verdict = "–"
            if now then
              verdict = fmt_rate(now) .. (now >= need_hr and ' <span class="ok">✓</span>'
                or string.format(' <span class="warn">⚠ ×%.1f</span>', need_hr / now))
            end
            out('<tr><td class="l">' .. label .. '</td><td>' .. fmt_rate(left / days) .. '</td><td>'
              .. fmt_rate(need_hr) .. '</td><td>' .. verdict .. '</td></tr>')
          end
          pace_row("Source", left_src, done_src)
          pace_row("Film", left_film, done_film)
          out('</table><div class="note">Now = the pace of the finished scenes. ⚠ ×N = the pace needed is N times it.</div>')
        end
      end
      if days then
        for _, x in ipairs(per_stage) do
          if x.rem_src > 0 then row(x.stg.label .. " source / day", fmt_rate(x.rem_src / per_day_div)) end
        end
      end
    end
    out('</div>')
  end
  out('</div>')

  -- Daily progress: a stage finished on the last day that work of its type was logged on the
  -- scene (user: correct - no more work of that type after it is done); a scene finished on
  -- the latest of its stage days. Skipped stages have no day.
  do
    local days = {}
    local function day(d)
      local x = days[d]
      if not x then x = { stages = {}, scenes = {}, film = 0, src = 0 }; days[d] = x end
      return x
    end
    local undated = 0
    for _, sc in ipairs(scenes) do
      if shown(sc) then
        local name = esc(sc.name ~= "" and sc.name or "(unnamed)")
        local latest
        for _, stg in ipairs(STAGES) do
          if stage_exists[stg.key] and stage_done(sc, stg.key) then
            local st = sc.stage[stg.key]
            local d = st and st.n > 0 and sc.last_date and sc.last_date[stg.wt]
            if d then
              local x = day(d)
              x.stages[stg.key] = x.stages[stg.key] or {}
              table.insert(x.stages[stg.key], name)
              if not latest or d > latest then latest = d end
            end
          end
        end
        if sc.is_done then
          if latest then
            local x = day(latest)
            x.scenes[#x.scenes + 1] = name
            x.film, x.src = x.film + sc.length_sec, x.src + sc.source_length_sec
          else
            undated = undated + 1
          end
        end
      end
    end
    -- work per day: the whole project, or only the selected scenes
    local work = {}
    if sel_mode then
      for _, sc in ipairs(scenes) do
        if shown(sc) and sc.day_work then
          for d, secs in pairs(sc.day_work) do work[d] = (work[d] or 0) + secs end
        end
      end
    else
      for d, secs in pairs(daily_totals) do work[d] = secs end
    end
    local dates = {}
    for d in pairs(days) do dates[#dates + 1] = d end
    for d in pairs(work) do if not days[d] then dates[#dates + 1] = d end end
    table.sort(dates, function(a, b) return a > b end)

    out('<details open><summary>Daily progress</summary><div class="wrap"><table>')
    out('<tr><th class="l">Date</th><th class="l">Finished scenes</th><th>Film</th><th>Source</th>'
      .. '<th class="l">Stages finished</th><th>Work</th></tr>')
    for _, d in ipairs(dates) do
      local x = days[d] or { stages = {}, scenes = {}, film = 0, src = 0 }
      local parts = {}
      for _, stg in ipairs(STAGES) do
        local list = x.stages[stg.key]
        if list then parts[#parts + 1] = string.format("%s %d: %s", esc(stg.wt), #list, table.concat(list, ", ")) end
      end
      out(string.format('<tr><td class="l">%s</td><td class="l">%s</td><td>%s</td><td>%s</td>'
        .. '<td class="l" style="white-space:normal">%s</td><td>%s</td></tr>',
        d, #x.scenes > 0 and table.concat(x.scenes, ", ") or "–",
        x.film > 0 and fmt_rate(x.film) or "–", x.src > 0 and fmt_rate(x.src) or "–",
        #parts > 0 and table.concat(parts, "<br>") or "–", work[d] and fmt_h(work[d]) or "–"))
    end
    out('</table></div>')
    out('<div class="note">A stage counts on the last day its work type was logged on the scene; a scene is finished '
      .. 'on the latest of those days. Skipped stages have no day.'
      .. (undated > 0 and (' ' .. undated .. ' finished scene' .. (undated > 1 and 's have' or ' has') .. ' no logged work to date it.') or '')
      .. '</div></details>')
  end

  -- Details (collapsed)
  out('<details><summary>Source lengths (EDL / Mic Selected / Edited)</summary>')
  -- Source stages side by side: EDL source → Mic Selected → Edited.
  -- Ratio = stage length / film length of the scenes that have that stage;
  -- Kept = stage length / previous stage length of the same scenes.
  do
    local src_scenes, src_len = 0, 0
    local sel = { len = 0, film = 0, prev = 0, n = 0 }
    local edt = { len = 0, film = 0, prev = 0, n = 0 }
    for _, sc in ipairs(scenes) do
      if not shown(sc) then goto next_stage end
      if sc.source_length_sec > 0 then src_scenes = src_scenes + 1 end
      src_len = src_len + sc.source_length_sec
      if sc.sel_len_sec and sc.sel_len_sec > 0 then
        sel.len, sel.film = sel.len + sc.sel_len_sec, sel.film + sc.length_sec
        sel.prev, sel.n   = sel.prev + sc.source_length_sec, sel.n + 1
      end
      if sc.edit_len_sec and sc.edit_len_sec > 0 then
        edt.len, edt.film = edt.len + sc.edit_len_sec, edt.film + sc.length_sec
        edt.prev, edt.n   = edt.prev + ((sc.sel_len_sec and sc.sel_len_sec > 0) and sc.sel_len_sec or sc.source_length_sec), edt.n + 1
      end
      ::next_stage::
    end
    -- whole project: every EDL item; selected scenes: their attributed source only
    local source_total = sel_mode and src_len or project_source_total_sec
    local function stage(title, len, ratio, kept, n)
      out('<div class="stage"><h4>' .. title .. '</h4>')
      out('<div><b>Total Length</b><span>' .. len .. '</span></div>')
      out('<div><b>Ratio (vs film)</b><span>' .. ratio .. '</span></div>')
      out('<div><b>Kept from previous</b><span>' .. kept .. '</span></div>')
      out('<div><b>Scenes</b><span>' .. n .. '</span></div></div>')
    end
    out('<div class="stages">')
    stage("Source (EDL)", fmt_dur(source_total),
      pct(source_total, project_film_total_sec), "–", src_scenes)
    if has_sel then
      stage("Selected (Mic Selected)", fmt_dur(sel.len), pct(sel.len, sel.film), pct(sel.len, sel.prev), sel.n)
    end
    if has_edit then
      stage("Edited", fmt_dur(edt.len), pct(edt.len, edt.film), pct(edt.len, edt.prev), edt.n)
    end
    out('</div>')
  end

  out('</details>')

  -- Efficiency per work type
  out('<details><summary>Efficiency by Work Type</summary><div class="wrap"><table>')
  -- (selected scenes: no Project Time / Total Time, they are not per scene)
  out('<tr><th class="l">Work</th><th>Scenes</th><th>Film</th><th>Source</th><th>Scene Time</th>'
    .. '<th>Film/hr</th><th>Source/hr</th>'
    .. (sel_mode and '' or '<th>Project Time</th><th>Total Time</th>') .. '</tr>')
  for _, t in ipairs(types) do
    local e = eff[t] or { scenes = 0, film = 0, source = 0, work = 0 }
    out(string.format('<tr><td class="l">%s</td><td>%d</td><td>%s</td><td>%s</td><td>%s</td>'
      .. '<td>%s</td><td>%s</td>',
      type_label(t), e.scenes, dur_or_dash(e.film), dur_or_dash(e.source), dur_or_dash(e.work),
      e.work > 0 and rate_or_na(e.film, e.work) or "–", e.work > 0 and rate_or_na(e.source, e.work) or "–")
      .. (sel_mode and '' or string.format('<td>%s</td><td>%s</td>', dur_or_dash(wt_project[t]), fmt_dur(wt_totals[t])))
      .. '</tr>')
  end
  out(string.format('<tr class="total"><td class="l">Total</td><td>%d</td><td>%s</td><td>%s</td><td>%s</td>'
    .. '<td>%s</td><td>%s</td>',
    eff_total.scenes, dur_or_dash(eff_total.film), dur_or_dash(eff_total.source), dur_or_dash(eff_total.work),
    rate_or_na(eff_total.film, eff_total.work), rate_or_na(eff_total.source, eff_total.work))
    .. (sel_mode and '' or string.format('<td>%s</td><td>%s</td>', dur_or_dash(project_work_total), fmt_dur(grand_total)))
    .. '</tr>')
  out('</table></div>')
  out('<div class="note">Film/hr and Source/hr: film / source length of every scene that has this work type, '
    .. 'per hour of that work. Source is always the EDL source. '
    .. (sel_mode and 'Only the selected scenes are counted.'
      or 'Project Time (work without a selected scene) is not included in the rates.') .. '</div>')

  out('</details>')

  -- Scene list (one row per scene)
  out('<details><summary>Scenes</summary><div class="wrap"><table>')
  local hdr = '<tr><th>#</th><th class="l">Scene</th><th class="l">Range</th><th>Film</th><th>Source</th><th>Ratio</th>'
    .. (has_sel and '<th>Selected</th>' or '') .. (has_edit and '<th>Edited</th>' or '')
  for _, t in ipairs(scene_types) do hdr = hdr .. '<th>' .. type_label(t) .. '</th>' end
  for _, stg in ipairs(STAGES) do
    if stage_exists[stg.key] then hdr = hdr .. '<th>' .. stg.label .. ' ✓</th>' end
  end
  out(hdr .. '<th>Total</th><th>Film/hr</th><th>Source/hr</th><th>Done</th></tr>')
  for idx, guid in ipairs(scene_order) do
    local sc = scene_map[guid]
    if not shown(sc) then goto next_row end
    local name = esc(sc.name ~= "" and sc.name or "(unnamed)")
    if sc.total_sec > 0 then name = '<a href="#s' .. idx .. '">' .. name .. '</a>' end
    local row = string.format('<tr%s><td>%d</td><td class="l">%s</td><td class="l">%s – %s</td><td>%s</td><td>%s</td><td>%s</td>',
      sc.total_sec > 0 and "" or ' class="idle"', idx, name, sc.start_tc, sc.end_tc,
      fmt_dur(sc.length_sec), fmt_dur(sc.source_length_sec), pct(sc.source_length_sec, sc.length_sec))
    if has_sel  then row = row .. '<td>' .. dur_or_dash(sc.sel_len_sec)  .. '</td>' end
    if has_edit then row = row .. '<td>' .. dur_or_dash(sc.edit_len_sec) .. '</td>' end
    for _, t in ipairs(scene_types) do row = row .. '<td>' .. dur_or_dash(sc.wt_sec[t]) .. '</td>' end
    for _, stg in ipairs(STAGES) do
      if stage_exists[stg.key] then
        row = row .. '<td>' .. (stage_done(sc, stg.key) and '<span class="done">✓</span>' or '·') .. '</td>'
      end
    end
    row = row .. string.format('<td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
      dur_or_dash(sc.total_sec),
      sc.total_sec > 0 and rate_or_na(sc.length_sec, sc.total_sec) or "–",
      sc.total_sec > 0 and rate_or_na(sc.source_length_sec, sc.total_sec) or "–",
      sc.is_done and '<span class="done">✓</span>' or "")
    out(row)
    ::next_row::
  end
  out('</table></div>')

  out('</details>')

  -- Per scene detail
  out('<details><summary>Per Scene</summary>')
  for idx, guid in ipairs(scene_order) do
    local sc = scene_map[guid]
    if sc.total_sec > 0 and shown(sc) then
      out('<section class="scene" id="s' .. idx .. '">')
      out('<h3>#' .. idx .. ' · Scene ' .. esc(sc.name ~= "" and sc.name or "(unnamed)")
        .. (sc.is_done and ' <span class="done">✓ done</span>' or '') .. '</h3>')
      out('<div class="meta">' .. sc.start_tc .. ' – ' .. sc.end_tc
        .. ' · Film ' .. fmt_dur(sc.length_sec) .. ' · Source ' .. fmt_dur(sc.source_length_sec)
        .. ' · Ratio ' .. pct(sc.source_length_sec, sc.length_sec)
        .. (sc.sel_len_sec  and (' · Selected ' .. fmt_dur(sc.sel_len_sec))  or '')
        .. (sc.edit_len_sec and (' · Edited '   .. fmt_dur(sc.edit_len_sec)) or '') .. '</div>')
      out('<div class="wrap"><table><tr><th class="l">Work</th><th>Time</th><th>Film/hr</th><th>Source/hr</th></tr>')
      for _, t in ipairs(scene_types) do
        local secs = sc.wt_sec[t]
        if secs and secs > 0 then
          out(string.format('<tr><td class="l">%s</td><td>%s</td><td>%s</td><td>%s</td></tr>', type_label(t),
            fmt_dur(secs), rate_or_na(sc.length_sec, secs), rate_or_na(input_source(sc, t), secs)))
        end
      end
      out(string.format('<tr class="total"><td class="l">Total</td><td>%s</td><td>%s</td><td>%s</td></tr>',
        fmt_dur(sc.total_sec), rate_or_na(sc.length_sec, sc.total_sec), rate_or_na(sc.source_length_sec, sc.total_sec)))
      out('</table></div></section>')
    end
  end
  out('</details>')
  out('<a class="top" href="#top">↑ Top</a></main>')
  -- a scene link opens the collapsed section it points into
  out('<script>document.querySelectorAll(\'a[href^="#s"]\').forEach(function(a){a.addEventListener("click",'
    .. 'function(){var t=document.querySelector(a.getAttribute("href"));var d=t&&t.closest("details");if(d)d.open=true;});});</script>')
  out('</body></html>')

  write_and_open_report(h)
end

analyze()
