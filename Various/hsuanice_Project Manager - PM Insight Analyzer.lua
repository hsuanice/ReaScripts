--[[
@description Project Manager - PM Insight Analyzer: work-time analysis of PM Timer logs (work in progress)
@version 26.1025.1313pre1
@author hsuanice
@noindex  (kept in the repository as a backup; not offered on ReaPack while it is a work in progress)
@changelog
  - Change: the report opens with an overview - work time, efficiency, progress by stage and plan; the detailed tables are collapsed below.
  - Change: efficiency = the whole film / the whole EDL source per hour of ALL work (every work type and work without a scene); the per work type rates stay for the estimates.
  - Add: progress by stage - Mic select (EDL), Editing (Mic Selected), Denoise (Edited): done when all the scene's items there are muted; a stage with no items is done when a later stage already has items (skipped). Remaining EDL source and estimated work hours per stage.
  - Add: plan from PM Timer's target hours and delivery date - days left, hours used / left, hours per day, whether the estimated work fits, source per day per stage.
  - Change: Source/hr always uses the EDL source.
@about
  Read-only analysis script. Auto-detects project type:

  Dialog Project Mode (Scene Cut track present):
    Combines scene data, EDL source lengths, and work log.
    Outputs per-scene efficiency metrics and project-wide summary as an
    HTML report ("<session folder name> - PM Insight.html" in the project
    folder, replaced on every run), opened in the web browser. Efficiency is computed for every work type.
    Tracks required: "Scene Cut", "EDL" (folder).

  Work Log Mode (no Scene Cut track):
    Parses item names ("Proj | Scene | Module") to compute durations
    grouped by scene and module. No EDL data required.

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
local WIN_W, WIN_H      = 1100, 760
local LINE_H            = 18
local SECTION_GAP       = 8

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
  if #parts >= 3 then
    return { scene = parts[2], module = parts[3] }
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

local function new_project_bucket(name)
  return {
    name = name,
    total_sec = 0,
    task_totals = {},
    module_totals = {},
    day_totals = {},
    items = {},
  }
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

local function collect_work_log_data()
  local data = {
    grand_total = 0,
    daily_totals = {},
    task_totals = {},
    module_totals = {},
    project_data = {},
    project_order = {},
    item_count = 0,
  }

  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    local _, track_name = r.GetTrackName(track)
    local is_date_track = track_name:match(DATE_PAT)

    for j = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, j)
      local take = r.GetActiveTake(item)
      local take_name = take and r.GetTakeName(take) or ""
      local parsed = take_name ~= "" and parse_wl_item_name(take_name) or nil
      local dur = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if parsed and dur > 0 then
        local _, note = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
        local note_info = parse_note_fields(note)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local start_tc = fmt_tc(pos)
        local end_tc = fmt_tc(pos + dur)
        local prefix, project, task = split_prefix(take_name)
        if project == "" then project = "(unknown)" end
        if task == "" then task = "(unknown)" end
        local module = (parsed.module ~= "") and parsed.module or "other"
        local date_name = is_date_track and track_name or "(no date track)"

        data.grand_total = data.grand_total + dur
        data.item_count = data.item_count + 1
        data.daily_totals[date_name] = (data.daily_totals[date_name] or 0) + dur
        data.task_totals[task] = (data.task_totals[task] or 0) + dur
        data.module_totals[module] = (data.module_totals[module] or 0) + dur

        if not data.project_data[project] then
          data.project_data[project] = new_project_bucket(project)
          table.insert(data.project_order, project)
        end

        local pd = data.project_data[project]
        pd.total_sec = pd.total_sec + dur
        pd.task_totals[task] = (pd.task_totals[task] or 0) + dur
        pd.module_totals[module] = (pd.module_totals[module] or 0) + dur
        pd.day_totals[date_name] = (pd.day_totals[date_name] or 0) + dur
        table.insert(pd.items, {
          date = date_name,
          start_tc = start_tc,
          end_tc = end_tc,
          length_sec = dur,
          take_name = take_name,
          note = note or "",
          task = task,
          module = module,
          prefix = prefix,
          project = project,
          shots = note_info.shots,
          src_cnt = note_info.src_cnt,
          src_len = note_info.src_len,
          scope = note_info.scope,
          scenes = note_info.scenes,
          reel_len = note_info.reel_len,
          note_range = note_info.range,
          note_length = note_info.length,
        })
      end
    end
  end

  for _, project in ipairs(data.project_order) do
    table.sort(data.project_data[project].items, function(a, b)
      if a.date == b.date then return a.start_tc < b.start_tc end
      return a.date < b.date
    end)
  end

  table.sort(data.project_order, function(a, b)
    local av = data.project_data[a].total_sec or 0
    local bv = data.project_data[b].total_sec or 0
    if av == bv then return a < b end
    return av > bv
  end)

  return data
end

local function build_work_log_lines(data)
  local lines = {}
  local function out(s) table.insert(lines, s) end

  local wl_avg, wl_used, wl_all = trimmed_daily_avg(data.daily_totals, 0.1)
  local daily_keys = sort_keys_by_value(data.daily_totals)
  local project_keys = data.project_order

  out("PM Insight Analyzer")
  out("Work Log Report")
  out(string.rep("=", 64))
  out(string.format("Year total work: %s", fmt_dur(data.grand_total)))
  out(string.format("Work items: %d", data.item_count))
  out(string.format("Working days: %d", wl_all))
  out(string.format("Avg daily work: %s", wl_all > 0 and (fmt_dur(wl_avg) .. string.format("  (mid %d days)", wl_used)) or "N/A"))
  out("")

  out("By Project")
  out(string.rep("-", 64))
  if #project_keys == 0 then
    out("(no work log items found)")
  else
    for _, pname in ipairs(project_keys) do
      local pd = data.project_data[pname]
      out(string.format("%s  [%s]", pname, fmt_dur(pd.total_sec)))
      out(string.format("  Tasks: %d  Modules: %d  Days: %d  Items: %d", #sort_keys_by_value(pd.task_totals), #sort_keys_by_value(pd.module_totals), #sort_keys_by_value(pd.day_totals), #pd.items))
      local task_keys = sort_keys_by_value(pd.task_totals)
      if #task_keys > 0 then
        out("  Task totals:")
        for _, task in ipairs(task_keys) do
          out(string.format("    %-18s %s", task .. ":", fmt_dur(pd.task_totals[task])))
        end
      end
      local module_keys = sort_keys_by_value(pd.module_totals)
      if #module_keys > 0 then
        out("  Module totals:")
        for _, mod in ipairs(module_keys) do
          out(string.format("    %-18s %s", mod .. ":", fmt_dur(pd.module_totals[mod])))
        end
      end
      out("  Sessions:")
      for _, item in ipairs(pd.items) do
        local note_bits = {}
        if item.scope ~= "" then table.insert(note_bits, "Scope " .. item.scope) end
        if item.scenes ~= "" then table.insert(note_bits, "Scenes " .. item.scenes) end
        if item.shots ~= "" then table.insert(note_bits, "Shots " .. item.shots) end
        if item.src_cnt ~= "" then table.insert(note_bits, "Src Cnt " .. item.src_cnt) end
        if item.src_len ~= "" then table.insert(note_bits, "Src Len " .. item.src_len) end
        local note_summary = (#note_bits > 0) and (" | " .. table.concat(note_bits, ", ")) or ""
        out(string.format("    %s  %s-%s  %s  %s / %s%s",
          item.date, item.start_tc, item.end_tc, fmt_dur(item.length_sec), item.task, item.module, note_summary))
      end
      out("")
    end
  end

  out("By Day")
  out(string.rep("-", 64))
  for _, day in ipairs(daily_keys) do
    out(string.format("%s  %s", day, fmt_dur(data.daily_totals[day])))
  end

  out("")
  out("By Task")
  out(string.rep("-", 64))
  for _, task in ipairs(sort_keys_by_value(data.task_totals)) do
    out(string.format("%s  %s", task, fmt_dur(data.task_totals[task])))
  end

  out("")
  out("By Module")
  out(string.rep("-", 64))
  for _, mod in ipairs(sort_keys_by_value(data.module_totals)) do
    out(string.format("%s  %s", mod, fmt_dur(data.module_totals[mod])))
  end

  return lines
end

local function show_console_report(lines)
  r.ShowConsoleMsg("")
  r.ShowConsoleMsg(table.concat(lines, "\n") .. "\n")
end

local function draw_wrapped_line(x, y, w, text)
  gfx.x = x
  gfx.y = y
  gfx.drawstr(text, 0)
end

local WORK_LOG_GUI = nil

local function render_work_log_gui(lines)
  WORK_LOG_GUI = {
    lines = lines,
    scroll = 0,
    line_count = #lines,
  }

  local function draw_work_log_gui()
    if not WORK_LOG_GUI then return end
    local line_count = WORK_LOG_GUI.line_count
    local visible_lines = math.max(1, math.floor((WIN_H - 34) / LINE_H))
    local max_scroll = math.max(0, line_count - visible_lines)
    local scroll = WORK_LOG_GUI.scroll

    gfx.set(0.10, 0.10, 0.11, 1)
    gfx.rect(0, 0, WIN_W, WIN_H, 1)
    gfx.set(0.22, 0.22, 0.25, 1)
    gfx.rect(0, 0, WIN_W, 28, 1)
    gfx.set(1, 1, 1, 1)
    gfx.x, gfx.y = 12, 8
    gfx.drawstr("Work Log Report")
    gfx.x, gfx.y = WIN_W - 180, 8
    gfx.drawstr(string.format("%d lines", line_count))

    local y = 38
    for i = scroll + 1, math.min(line_count, scroll + visible_lines) do
      local line = WORK_LOG_GUI.lines[i]
      if line == "" then
        y = y + LINE_H - 4
      else
        if line:match("^By ") or line:match("^%-%-+") or line:match("^=+") then
          gfx.set(0.85, 0.85, 0.92, 1)
        elseif line:match("^%s%s%S") then
          gfx.set(0.78, 0.78, 0.82, 1)
        else
          gfx.set(0.95, 0.95, 0.95, 1)
        end
        gfx.x, gfx.y = 12, y
        gfx.drawstr(line)
        y = y + LINE_H
      end
    end

    gfx.set(0.45, 0.45, 0.50, 1)
    gfx.rect(WIN_W - 12, 28, 6, WIN_H - 40, 1)
    if max_scroll > 0 then
      local thumb_h = math.max(28, (WIN_H - 44) * visible_lines / line_count)
      local thumb_y = 30 + (WIN_H - 44 - thumb_h) * (scroll / max_scroll)
      gfx.set(0.85, 0.85, 0.95, 0.85)
      gfx.rect(WIN_W - 12, thumb_y, 6, thumb_h, 1)
    end

    gfx.update()
  end

  local function loop_work_log_gui()
    if not WORK_LOG_GUI then return end
    if gfx.getchar() < 0 then
      WORK_LOG_GUI = nil
      return
    end

    local wheel = gfx.mouse_wheel or 0
    if wheel ~= 0 then
      local visible_lines = math.max(1, math.floor((WIN_H - 34) / LINE_H))
      local max_scroll = math.max(0, WORK_LOG_GUI.line_count - visible_lines)
      WORK_LOG_GUI.scroll = math.max(0, math.min(max_scroll, WORK_LOG_GUI.scroll - math.floor(wheel / 120)))
      gfx.mouse_wheel = 0
    end

    draw_work_log_gui()
    r.defer(loop_work_log_gui)
  end

  gfx.init("PM Insight Analyzer - Work Log", WIN_W, WIN_H, 0, 120, 120)
  gfx.setfont(1, "Arial", 16)
  draw_work_log_gui()
  r.defer(loop_work_log_gui)
end

local function analyze_work_log()
  local data = collect_work_log_data()
  local lines = build_work_log_lines(data)
  show_console_report(lines)
  render_work_log_gui(lines)
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
  -- (e.g. EDL -> Edited directly, Mic Selected left empty); otherwise it is not done yet.
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
    return false
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

  out([[<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PM Insight Report</title>
<style>
:root{--bg:#fafafa;--fg:#1d1d1f;--mut:#6e6e73;--line:#d2d2d7;--card:#fff;--head:#f0f0f3;--acc:#3b6fd8}
@media (prefers-color-scheme:dark){:root{--bg:#1b1b1d;--fg:#e8e8ea;--mut:#9a9aa0;--line:#3a3a3f;--card:#242427;--head:#2d2d31;--acc:#7da2ff}}
body{margin:0;padding:24px 16px 80px;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,"Segoe UI",Helvetica,Arial,sans-serif}
main{max-width:1200px;margin:0 auto}
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
details{margin-top:18px}summary{cursor:pointer;font-size:16px;font-weight:600;padding:6px 0}
.top{position:fixed;right:16px;bottom:16px;background:var(--card);border:1px solid var(--line);border-radius:20px;padding:6px 12px}
</style></head><body><main>]])
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
  -- source per second of work for a work type (EDL source), nil without work
  local function src_rate(wt)
    local e = eff[wt]
    if e and e.work > 0 and e.source > 0 then return e.source / e.work end
  end

  out('<h2>' .. (sel_mode and 'Selected Scenes' or 'Overview') .. '</h2><div class="cards">')

  -- 1. Time
  card("Work time")
  local work_total = sel_mode and project_scene_total_sec or grand_total
  out('<div class="big">' .. fmt_h(work_total) .. '</div>')
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

  -- 2. Efficiency: whole film / whole EDL source per hour of ALL work (every work type,
  --    and work without a scene); selected scenes: their film / source per hour of their work
  local shown_film, shown_src = 0, 0
  for _, sc in ipairs(scenes) do
    if shown(sc) then shown_film, shown_src = shown_film + sc.length_sec, shown_src + sc.source_length_sec end
  end
  local all_src = sel_mode and shown_src or project_source_total_sec
  card("Efficiency (per hour of all work)")
  row("Film", rate_or_na(shown_film, work_total))
  row("Source (EDL)", rate_or_na(all_src, work_total))
  out('<div class="note">Film ' .. fmt_dur(shown_film) .. ' · Source ' .. fmt_dur(all_src) .. ' · Work '
    .. fmt_h(work_total) .. '</div>')
  -- per work type: EDL source of the scenes with that work, per hour of it (used for the estimates)
  local first = true
  for _, wt in ipairs({ "mic select", "editing", "denoise" }) do
    local e = eff[wt]
    if e and e.work > 0 then
      if first then out('<div class="note" style="margin-top:8px">By work type (source per hour of that work):</div>'); first = false end
      row("&nbsp;&nbsp;" .. esc(wt), rate_or_na(e.source, e.work))
    end
  end
  out('</div>')

  -- 3. Progress by stage: a stage is done for a scene when all its items there are muted
  --    (skipped stages count as done); remaining = EDL source of the scenes not done yet
  local n_scenes = 0
  for _, sc in ipairs(scenes) do if shown(sc) then n_scenes = n_scenes + 1 end end
  local remaining_work, any_estimate = 0, false   -- seconds of work still needed (estimate)
  local per_stage = {}
  card("Progress")
  for _, stg in ipairs(STAGES) do
    if stage_exists[stg.key] then
      local done, rem_src = 0, 0
      for _, sc in ipairs(scenes) do
        if shown(sc) then
          if stage_done(sc, stg.key) then done = done + 1 else rem_src = rem_src + sc.source_length_sec end
        end
      end
      local rate = src_rate(stg.wt)
      local est = rate and rem_src / rate
      if est then remaining_work = remaining_work + est; any_estimate = true end
      per_stage[#per_stage + 1] = { stg = stg, rem_src = rem_src }
      row(stg.label .. " <small>(" .. stg.src .. ")</small>", string.format("%d / %d", done, n_scenes))
      bar(n_scenes > 0 and done / n_scenes or 0)
      row("&nbsp;&nbsp;source left · est. work", fmt_dur(rem_src) .. " · " .. (est and fmt_h(est) or "N/A"))
    end
  end
  row("Scenes marked done", string.format("%d / %d", (function()
    local n = 0; for _, sc in ipairs(scenes) do if shown(sc) and sc.is_done then n = n + 1 end end; return n end)(), n_scenes))
  bar(project_film_total_sec > 0 and completed_film_sec / project_film_total_sec or 0)
  if any_estimate then row("Estimated work left", '<span class="big">' .. fmt_h(remaining_work) .. '</span>') end
  out('</div>')

  -- 4. Plan: target hours and delivery date (set in PM Timer, saved in the project)
  if not sel_mode then
    local _, t_hours = r.GetProjExtState(0, "hsuanice_PM", "TARGET_HOURS")
    local _, due = r.GetProjExtState(0, "hsuanice_PM", "DUE_DATE")
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
        if days then row("Per day", fmt_h(math.max(left, 0) / per_day_div)) end
        if any_estimate then
          local fits = remaining_work <= left   -- both in seconds of work
          row("Estimated work left", fmt_h(remaining_work) .. " " .. (fits and '<span class="ok">✓ fits</span>'
            or ('<span class="warn">' .. fmt_h(remaining_work - left) .. " short</span>")))
        end
      end
      if days then
        for _, x in ipairs(per_stage) do
          if x.rem_src > 0 then row(x.stg.label .. " source / day", fmt_dur(x.rem_src / per_day_div)) end
        end
      end
    end
    out('</div>')
  end
  out('</div>')

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

  -- 8. Save next to the project file and open it in the browser ─────────────
  --    One report per session folder (daily .rpp backups in the same folder
  --    continue the same work), overwritten on every run.
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

analyze()
