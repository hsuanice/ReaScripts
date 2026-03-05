--[[
@description PM Insight Analyzer
@version 260305.0110
@author hsuanice
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

@changelog
  v260305.0110
    - Work Log Mode: when no "Scene Cut" track is present, the script switches
      to Work Log mode. Item names are parsed as "Proj | Scene | Module" and
      durations are grouped by scene and module.
      - Project Overview shows grand total + per-module totals.
      - Per Scene block shows each scene with module breakdown + scene total.
      - Items with only two parts ("Proj | Module", no scene) are counted as
        project work in the overview but excluded from per-scene output.

  v260304.2225
    - Duration source changed to D_LENGTH exclusively; P_EXT:DURATION no longer read.
      Manually stretching a work item now immediately reflects in the analysis.

  v260302.2100
    - Removed Efficiency Overview (all-scene efficiency)
    - "Completion-Based Efficiency" renamed to "Efficiency"
    - Efficiency block shows N/A if no completed scenes
    - Output order: Project Overview → Progress → Efficiency → Per Scene

  v260302.2000
    - Completion tracking switched from P_EXT:SCENE_DONE to B_MUTE
    - New "Completion-Based Efficiency" block using only done scenes

  v260302.1900
    - Progress block, output reorder, Film/Source Length per scene, integer ratios

  v260302.1830
    - Initial release
]]--

---@diagnostic disable: undefined-global
local r = reaper

local SCENE_TRACK_NAME  = "Scene Cut"
local EDL_FOLDER_NAME   = "EDL"
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

local function analyze_work_log()
  -- scene_data: scene_name → { total_sec, modules: { mod → sec } }
  local scene_data    = {}
  local scene_order   = {}
  local module_totals = {}
  local project_work  = 0
  local grand_total   = 0

  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(t) - 1 do
      local item   = r.GetTrackMediaItem(t, j)
      local take   = r.GetActiveTake(item)
      local iname  = take and r.GetTakeName(take) or ""
      local parsed = iname ~= "" and parse_wl_item_name(iname) or nil
      if parsed then
        local dur = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if dur > 0 then
          grand_total = grand_total + dur
          local mod = (parsed.module ~= "") and parsed.module or "other"
          module_totals[mod] = (module_totals[mod] or 0) + dur
          if parsed.scene then
            if not scene_data[parsed.scene] then
              scene_data[parsed.scene] = { total_sec = 0, modules = {} }
              table.insert(scene_order, parsed.scene)
            end
            local sd = scene_data[parsed.scene]
            sd.total_sec      = sd.total_sec + dur
            sd.modules[mod]   = (sd.modules[mod] or 0) + dur
          else
            project_work = project_work + dur
          end
        end
      end
    end
  end

  local lines = {}
  local function out(s) table.insert(lines, s) end

  out("=== hsuanice PM — Insight Report (Work Log) ===")
  out("")
  out("Project Overview")
  out("--------------------------------")
  out("Grand Total Work: " .. fmt_dur(grand_total))
  out("")
  -- Module totals sorted by time descending
  local mod_keys = {}
  for k in pairs(module_totals) do table.insert(mod_keys, k) end
  table.sort(mod_keys, function(a, b)
    return (module_totals[a] or 0) > (module_totals[b] or 0)
  end)
  for _, mod in ipairs(mod_keys) do
    out(string.format("  %-16s %s", mod .. ":", fmt_dur(module_totals[mod])))
  end
  if project_work > 0 then
    out("")
    out("  Project Work (no scene): " .. fmt_dur(project_work))
  end

  out("")
  out("----------------------------------------")
  out("Per Scene")
  out("----------------------------------------")

  for _, sname in ipairs(scene_order) do
    local sd = scene_data[sname]
    out("")
    out("Scene: " .. sname)
    local smods = {}
    for k in pairs(sd.modules) do table.insert(smods, k) end
    table.sort(smods, function(a, b)
      return (sd.modules[a] or 0) > (sd.modules[b] or 0)
    end)
    for _, mod in ipairs(smods) do
      out(string.format("  %-16s %s", mod .. ":", fmt_dur(sd.modules[mod])))
    end
    out("  Total:           " .. fmt_dur(sd.total_sec))
  end

  out("")
  r.ShowConsoleMsg("")
  r.ShowConsoleMsg(table.concat(lines, "\n") .. "\n")
end

-- ── Main ───────────────────────────────────────────────────────────────────
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

  -- 4b. Project Source Total — raw sum of ALL EDL items (no attribution) ───────
  local project_source_total_sec = 0
  for _, t in ipairs(edl_tracks) do
    for i = 0, r.CountTrackMediaItems(t) - 1 do
      local item = r.GetTrackMediaItem(t, i)
      project_source_total_sec = project_source_total_sec
        + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    end
  end

  -- 5. Walk Scene Cut child tracks and accumulate work times ─────────────────
  local sc_num       = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local total_tracks = r.CountTracks(0)
  local depth        = 1

  local project_work_total = 0   -- Project Mode work (no SCENE_GUID)

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
  out("Grand Total Work:   " .. fmt_dur(grand_total))

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
      out("Film Length:   " .. fmt_dur(sc.length_sec))
      out("Source Length: " .. fmt_dur(sc.source_length_sec))

      if sc.length_sec > 0 then
        out("Source Ratio:  "
          .. string.format("%d%%", math.floor(sc.source_length_sec / sc.length_sec * 100)))
      else
        out("Source Ratio:  N/A")
      end

      out("")

      if sc.editing_sec > 0 then
        out("Editing Time: " .. fmt_dur(sc.editing_sec))
      else
        out("Editing Time: N/A")
      end

      if sc.denoise_sec > 0 then
        out("Denoise Time: " .. fmt_dur(sc.denoise_sec))
      else
        out("Denoise Time: N/A")
      end

      out("Total Scene Time: " .. fmt_dur(sc.total_sec))
      out("")
      out("Editing Film/hr:   " .. rate_or_na(sc.length_sec, sc.editing_sec))
      out("Total Film/hr:     " .. rate_or_na(sc.length_sec, sc.total_sec))
    end
  end

  out("")

  -- Write to console (clear first, then output)
  r.ShowConsoleMsg("")
  r.ShowConsoleMsg(table.concat(lines, "\n") .. "\n")
end

analyze()
