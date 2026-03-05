--[[
@description PM Work Analyzer
@version 260302.1830
@author hsuanice
@about
  Read-only analysis of work log items under Scene Cut.
  Outputs per-scene work breakdown, efficiency, and totals to the console.
  Does not write any data to the project.

  Classification (by P_EXT:SCENE_GUID, not name):
    Scene Mode   : SCENE_GUID ~= "" → attributed to that scene
    Project Mode : SCENE_GUID == "" → attributed to Project Work

  Duration source: P_EXT:DURATION (preferred) → D_LENGTH (fallback)

@changelog
  v260302.1830
    - Initial release
]]--

---@diagnostic disable: undefined-global
local r = reaper

local SCENE_TRACK_NAME  = "Scene Cut"
local DURATION_LOG_NAME = "DurationOnly_Log"
local DATE_PAT          = "^%d%d%d%d%-%d%d%-%d%d$"

-- ── Helpers ────────────────────────────────────────────────────────────────
local function fmt_dur(secs)
  -- IMPORTANT: format_timestr_len requires 4 args; offset=0 must NOT be omitted
  return r.format_timestr_len(secs, "", 0, 5)
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
    r.ShowConsoleMsg("")
    r.ShowConsoleMsg("=== hsuanice PM — Work Analyzer ===\n\nERROR: Track '"
      .. SCENE_TRACK_NAME .. "' not found.\n")
    return
  end

  -- 2. Build scene_map from items on Scene Cut ───────────────────────────────
  local scene_map   = {}  -- [guid] → { name, start_tc, length, work={}, total }
  local scene_order = {}  -- insertion order preserved

  for i = 0, r.CountTrackMediaItems(scene_track) - 1 do
    local item = r.GetTrackMediaItem(scene_track, i)
    local guid = r.BR_GetMediaItemGUID(item)
    local spos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local slen = r.GetMediaItemInfo_Value(item, "D_LENGTH")

    local name = ""
    local take = r.GetActiveTake(item)
    if take then name = r.GetTakeName(take) end
    if name == "" then
      local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
      name = (notes and notes ~= "") and notes or "(unnamed)"
    end

    scene_map[guid] = {
      name     = name,
      start_tc = r.format_timestr_pos(spos, "", 5),
      length   = slen,
      work     = {},   -- [work_type] → seconds
      total    = 0,
    }
    table.insert(scene_order, guid)
  end

  -- 3. Walk child tracks of Scene Cut and accumulate work ────────────────────
  local sc_num       = math.floor(r.GetMediaTrackInfo_Value(scene_track, "IP_TRACKNUMBER"))
  local total_tracks = r.CountTracks(0)
  local depth        = 1

  local scene_work_total   = 0
  local project_work_total = 0
  local project_work       = {}   -- [work_type] → seconds

  for i = sc_num, total_tracks - 1 do
    local t        = r.GetTrack(0, i)
    local fd       = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))
    local _, tname = r.GetTrackName(t)

    if tname:match(DATE_PAT) or tname == DURATION_LOG_NAME then
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        local item = r.GetTrackMediaItem(t, j)

        -- Only process items with a WORK_TYPE
        local _, wt = r.GetSetMediaItemInfo_String(item, "P_EXT:WORK_TYPE", "", false)
        if wt ~= "" then

          -- Duration: prefer P_EXT:DURATION, fallback D_LENGTH
          local dur_secs
          local _, dur_str = r.GetSetMediaItemInfo_String(item, "P_EXT:DURATION", "", false)
          if dur_str ~= "" then
            dur_secs = tonumber(dur_str) or 0
          else
            dur_secs = r.GetMediaItemInfo_Value(item, "D_LENGTH")
          end
          if dur_secs < 0 then dur_secs = 0 end

          -- Classify by SCENE_GUID
          local _, sg = r.GetSetMediaItemInfo_String(item, "P_EXT:SCENE_GUID", "", false)
          if sg ~= "" and scene_map[sg] then
            -- Scene Mode
            local sc = scene_map[sg]
            sc.work[wt] = (sc.work[wt] or 0) + dur_secs
            sc.total    = sc.total + dur_secs
            scene_work_total = scene_work_total + dur_secs
          else
            -- Project Mode (no SCENE_GUID, or GUID references a deleted scene)
            project_work[wt]   = (project_work[wt] or 0) + dur_secs
            project_work_total = project_work_total + dur_secs
          end
        end
      end
    end

    depth = depth + fd
    if depth <= 0 then break end
  end

  local grand_total = scene_work_total + project_work_total

  -- Count scenes that have at least one work item
  local scenes_with_work = 0
  for _, guid in ipairs(scene_order) do
    if scene_map[guid].total > 0 then scenes_with_work = scenes_with_work + 1 end
  end

  -- 4. Build console output ──────────────────────────────────────────────────
  local lines = {}
  local function out(s) table.insert(lines, s) end

  out("=== hsuanice PM — Work Analyzer ===")
  out("")
  out("Scenes: " .. scenes_with_work)
  out("Scene Work Total:   " .. fmt_dur(scene_work_total))
  out("Project Work Total: " .. fmt_dur(project_work_total))
  out("Grand Total:        " .. fmt_dur(grand_total))
  out("")
  out("----------------------------------------")

  -- Per-scene block (only scenes with work)
  for _, guid in ipairs(scene_order) do
    local sc = scene_map[guid]
    if sc.total > 0 then
      out("")
      out("Scene: " .. sc.name .. " (" .. sc.start_tc .. ")")

      -- Sort work types alphabetically for consistent output
      local wt_list = {}
      for wt in pairs(sc.work) do table.insert(wt_list, wt) end
      table.sort(wt_list)

      for _, wt in ipairs(wt_list) do
        out("  " .. wt .. ": " .. fmt_dur(sc.work[wt]))
      end

      out("  Total:        " .. fmt_dur(sc.total))
      out("  Scene Length: " .. fmt_dur(sc.length))

      if sc.length > 0 then
        out("  Efficiency:   " .. string.format("%.2fx", sc.total / sc.length))
      else
        out("  Efficiency:   N/A")
      end
    end
  end

  -- Project Work block (only if there is any)
  if project_work_total > 0 then
    out("")
    out("----------------------------------------")
    out("")
    out("Project Work:")

    local wt_list = {}
    for wt in pairs(project_work) do table.insert(wt_list, wt) end
    table.sort(wt_list)

    for _, wt in ipairs(wt_list) do
      out("  " .. wt .. ": " .. fmt_dur(project_work[wt]))
    end
    out("  Total: " .. fmt_dur(project_work_total))
  end

  out("")

  -- Write to console (clear first, then output)
  r.ShowConsoleMsg("")
  r.ShowConsoleMsg(table.concat(lines, "\n") .. "\n")
end

analyze()
