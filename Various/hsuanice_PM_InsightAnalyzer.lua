--[[
@description PM Insight Analyzer
@version 26.1012.1358pre1
@author hsuanice
@changelog
  - First release in the hsuanice/ReaScripts repository.
  - Pre-release: work in progress (basic info and time totals so far) — only installed when "Enable pre-releases" is on in ReaPack.
  - Requires the SWS extension.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Read-only analysis script. Auto-detects project type:

  Dialog Project Mode (Scene Cut track present):
    Combines scene data, EDL source lengths, and work log.
    Outputs per-scene efficiency metrics and project-wide summary.
    Tracks required: "Scene Cut", "EDL" (folder).

  Work Log Mode (no Scene Cut track):
    Parses item names ("Proj | Scene | Module") to compute durations
    grouped by scene and module. No EDL data required.

  Duration source: D_LENGTH (always). Does not write any data to the project.
--]]
---@diagnostic disable: undefined-global
local r = reaper

local SCENE_TRACK_NAME  = "Scene Cut"
local EDL_FOLDER_NAME   = "EDL"
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
      editing_sec       = 0,   -- work_type == "editing"
      denoise_sec       = 0,   -- work_type == "denoise"
      total_sec         = 0,   -- all scene work types combined
    }

    scene_map[guid] = sc
    table.insert(scene_order, guid)
    table.insert(scenes, sc)
  end

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
      if scene_id ~= "" and scene_map[scene_id] then
        scene_map[scene_id].source_length_sec =
          scene_map[scene_id].source_length_sec + item_len

      -- Priority 2: colour match AND position within lookup range
      else
        for idx, sc in ipairs(scenes) do
          if sc.color ~= 0 and item_color == sc.color then
            local rng = scene_ranges[idx]
            if item_start >= rng.range_start and item_end <= rng.range_end then
              sc.source_length_sec = sc.source_length_sec + item_len
              break
            end
          end
        end
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

  -- 5. Walk Scene Cut child tracks and accumulate work times ─────────────────
  local sc_num       = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local total_tracks = r.CountTracks(0)
  local depth        = 1

  local project_work_total = 0   -- Project Mode work (no SCENE_GUID)
  local daily_totals       = {}  -- "YYYY-MM-DD" → total work secs that day
  local wt_totals          = {}  -- work_type → total secs across all items

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

          local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
          if sg ~= "" and scene_map[sg] then
            -- Scene Mode: attribute to scene
            local sc = scene_map[sg]
            if     wt == "editing" then sc.editing_sec = sc.editing_sec + dur_secs
            elseif wt == "denoise" then sc.denoise_sec = sc.denoise_sec + dur_secs
            end
            sc.total_sec = sc.total_sec + dur_secs
          else
            -- Project Mode: no scene attribution
            project_work_total = project_work_total + dur_secs
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

  -- Progress aggregates (by B_MUTE)
  local completed_film_sec = 0
  local remaining_film_sec = 0

  -- Efficiency accumulators (done scenes only)
  local done_editing_sec = 0
  local done_denoise_sec = 0
  local done_total_sec   = 0
  local done_source_sec  = 0

  for _, guid in ipairs(scene_order) do
    local sc = scene_map[guid]
    project_film_total_sec  = project_film_total_sec  + sc.length_sec
    project_scene_total_sec = project_scene_total_sec + sc.total_sec

    if sc.is_done then
      completed_film_sec = completed_film_sec + sc.length_sec
      done_editing_sec   = done_editing_sec   + sc.editing_sec
      done_denoise_sec   = done_denoise_sec   + sc.denoise_sec
      done_total_sec     = done_total_sec     + sc.total_sec
      done_source_sec    = done_source_sec    + sc.source_length_sec
    else
      remaining_film_sec = remaining_film_sec + sc.length_sec
    end
  end

  local grand_total = project_scene_total_sec + project_work_total

  -- 7. Build console output ──────────────────────────────────────────────────
  local lines = {}
  local function out(s) table.insert(lines, s) end

  -- ── Project Overview ─────────────────────────────────────────────────────
  out("=== hsuanice PM — Insight Report ===")
  out("")
  out("Project Overview")
  out("--------------------------------")
  out("Total Film Length:   " .. fmt_dur(project_film_total_sec))
  out("Total Source Length: " .. fmt_dur(project_source_total_sec))
  if project_film_total_sec > 0 then
    out("Overall Source Ratio: "
      .. string.format("%d%%", math.floor(project_source_total_sec / project_film_total_sec * 100)))
  else
    out("Overall Source Ratio: N/A")
  end
  out("")
  out("Total Scene Work:   " .. fmt_dur(project_scene_total_sec))
  out("Total Project Work: " .. fmt_dur(project_work_total))
  local dl_avg, dl_used, dl_all = trimmed_daily_avg(daily_totals, 0.1)
  out("Grand Total Work:   " .. fmt_dur(grand_total))
  do
    local wt_keys = {}
    for k in pairs(wt_totals) do table.insert(wt_keys, k) end
    table.sort(wt_keys, function(a, b) return (wt_totals[a] or 0) > (wt_totals[b] or 0) end)
    for _, k in ipairs(wt_keys) do
      out(string.format("  %-14s %s", k .. ":", fmt_dur(wt_totals[k])))
    end
  end
  out("Working Days:       " .. dl_all)
  out("Avg Daily Work:     " .. (dl_all > 0
    and (fmt_dur(dl_avg) .. string.format("  (mid %d days, 10-90%%)", dl_used))
    or "N/A"))

  -- ── Progress ─────────────────────────────────────────────────────────────
  out("")
  out("Progress")
  out("--------------------------------")
  out("Completed Film:  " .. fmt_dur(completed_film_sec))
  out("Remaining Film:  " .. fmt_dur(remaining_film_sec))
  if project_film_total_sec > 0 then
    out("Completion:      "
      .. string.format("%d%%", math.floor(completed_film_sec / project_film_total_sec * 100)))
  else
    out("Completion:      N/A")
  end

  -- ── Efficiency ────────────────────────────────────────────────────────────
  out("")
  out("Efficiency")
  out("--------------------------------")
  if completed_film_sec <= 0 then
    out("N/A (No completed scenes)")
  else
    out("Editing Film/hr:   " .. rate_or_na(completed_film_sec, done_editing_sec))
    out("Editing Source/hr: " .. rate_or_na(done_source_sec,    done_editing_sec))
    out("")
    out("Denoise Film/hr:   " .. rate_or_na(completed_film_sec, done_denoise_sec))
    out("Denoise Source/hr: " .. rate_or_na(done_source_sec,    done_denoise_sec))
    out("")
    out("Total Film/hr:     " .. rate_or_na(completed_film_sec, done_total_sec))
    out("Total Source/hr:   " .. rate_or_na(done_source_sec,    done_total_sec))
  end

  -- ── Per Scene ─────────────────────────────────────────────────────────────
  out("")
  out("----------------------------------------")
  out("Per Scene")
  out("----------------------------------------")

  for _, guid in ipairs(scene_order) do
    local sc = scene_map[guid]

    -- Skip scenes with no work at all
    if sc.total_sec > 0 then
      out("")
      out("Scene: " .. (sc.name ~= "" and sc.name or "(unnamed)"))
      out("Range: " .. sc.start_tc .. " - " .. sc.end_tc)
      out("")
      out("Film Length:   " .. fmt_dur(sc.length_sec))
      out("Source Length: " .. fmt_dur(sc.source_length_sec))
      if sc.length_sec > 0 then
        out("Source Ratio:  "
          .. string.format("%d%%", math.floor(sc.source_length_sec / sc.length_sec * 100)))
      else
        out("Source Ratio:  N/A")
      end
      out("")
      out("Editing Time:     " .. (sc.editing_sec > 0 and fmt_dur(sc.editing_sec) or "N/A"))
      out("Denoise Time:     " .. (sc.denoise_sec > 0 and fmt_dur(sc.denoise_sec) or "N/A"))
      out("Total Scene Time: " .. fmt_dur(sc.total_sec))
      out("")
      out("Source Throughput")
      out("Editing Source/hr: " .. rate_or_na(sc.source_length_sec, sc.editing_sec))
      out("Denoise Source/hr: " .. rate_or_na(sc.source_length_sec, sc.denoise_sec))
      out("Total Source/hr:   " .. rate_or_na(sc.source_length_sec, sc.total_sec))
      out("")
      out("Film Throughput")
      out("Editing Film/hr: " .. rate_or_na(sc.length_sec, sc.editing_sec))
      out("Denoise Film/hr: " .. rate_or_na(sc.length_sec, sc.denoise_sec))
      out("Total Film/hr:   " .. rate_or_na(sc.length_sec, sc.total_sec))
    end
  end

  out("")

  -- Write to console (clear first, then output)
  r.ShowConsoleMsg("")
  r.ShowConsoleMsg(table.concat(lines, "\n") .. "\n")
end

analyze()
