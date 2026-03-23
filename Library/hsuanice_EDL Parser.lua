--[[
hsuanice_EDL Parser.lua
v260323.2201

CMX3600 Edit Decision List parser and writer for REAPER scripts.

Supports:
  - CMX3600 format parsing (TITLE, FCM, event lines, comment lines)
  - Timecode ↔ seconds conversion (any frame rate, including drop-frame 29.97)
  - Comment metadata: FROM CLIP NAME, SOURCE FILE, and arbitrary * lines
  - EDL writing (round-trip: parse → edit → export)

API:
  M.parse(filepath, opts)           → { format, title, fcm, fps, events }
  M.write(filepath, parsed_data)    → true/nil, error_string
  M.tc_to_seconds(tc_str, fps, drop) → number (seconds)
  M.seconds_to_tc(seconds, fps, drop) → string "HH:MM:SS:FF"
  M.detect_fps(fcm_str, comment_fps, default_fps) → number, boolean(is_drop)

Changelog:
  v260323.2201
  - Fix: detect_fps() now accepts a third parameter default_fps; when the EDL has
    no explicit FPS comment and is non-drop, the caller's preferred FPS is used
    instead of hardcoded 25 (e.g. CLB's saved FPS preference of 24)
  - Fix: M.parse() passes opts.default_fps through to detect_fps(), removing the
    redundant post-parse override block that only handled fcm == "" edge case

  v0.3.0 — Feature: parse AUDIO LEVEL / VIDEO LEVEL comments into structured data.
            event.audio_levels = [{ type, tc, db, reel, src_track }]
            (reel/src_track may be nil if the (REEL ...) suffix is absent)
  v0.2.0 — Fix: support event numbers > 999 (4+ digits).
            Previous regex `^%d%d%d%s` silently dropped events 1000+,
            causing their comments to contaminate the last valid event.
          Fix: support wipe transitions with type code (e.g. W001 028).
            Previous `[CDWK]` pattern only matched 1 char; W001 fell through
            to the no-duration path, misreading duration as Src TC In.
  v0.1.0 — Initial release: CMX3600 parse, write, TC conversion.
--]]

local M = {}
M.VERSION = "0.3.0"

---------------------------------------------------------------------------
-- Timecode utilities
---------------------------------------------------------------------------

--- Convert timecode string "HH:MM:SS:FF" to seconds.
--- Handles both ":" and ";" separators (semicolon = drop-frame indicator).
--- @param tc_str string  Timecode string
--- @param fps number     Frames per second (e.g. 24, 25, 29.97, 30)
--- @param drop boolean   True if drop-frame (only relevant for 29.97)
--- @return number        Seconds
function M.tc_to_seconds(tc_str, fps, drop)
  if not tc_str or tc_str == "" then return 0 end
  fps = fps or 25
  drop = drop or false

  -- Normalize separator: accept ":" or ";" or "."
  local h, m, s, f = tc_str:match("^(-?%d+)[:;.](%d+)[:;.](%d+)[:;.](%d+)$")
  if not h then return 0 end

  h, m, s, f = tonumber(h), tonumber(m), tonumber(s), tonumber(f)

  if drop and math.abs(fps - 29.97) < 0.1 then
    -- Drop-frame 29.97: SMPTE drop-frame counting
    -- Total frames = 108000*h + 1800*m - 2*(m - m/10) + 30*s + f
    -- (drop 2 frames every minute except every 10th minute)
    local total_minutes = 60 * h + m
    local drop_frames = 2 * (total_minutes - math.floor(total_minutes / 10))
    local total_frames = (108000 * h) + (1800 * m) + (30 * s) + f - drop_frames
    return total_frames / 29.97
  else
    -- Non-drop-frame: straightforward
    local round_fps = math.floor(fps + 0.5)
    return h * 3600 + m * 60 + s + f / round_fps
  end
end

--- Convert seconds to timecode string "HH:MM:SS:FF".
--- @param seconds number  Time in seconds
--- @param fps number      Frames per second
--- @param drop boolean    True if drop-frame
--- @return string         Timecode string
function M.seconds_to_tc(seconds, fps, drop)
  if not seconds then return "00:00:00:00" end
  fps = fps or 25
  drop = drop or false

  local sign = ""
  if seconds < 0 then sign = "-"; seconds = -seconds end

  local round_fps = math.floor(fps + 0.5)

  if drop and math.abs(fps - 29.97) < 0.1 then
    -- Drop-frame 29.97
    local total_frames = math.floor(seconds * 29.97 + 0.5)
    -- Drop-frame algorithm (reverse)
    local D = total_frames
    local d = D / 17982      -- 17982 frames per 10-minute block
    local M_val = D % 17982
    -- Adjust for drop frames
    local adj = math.floor(d) * 18000 + 2 * (math.max(0, math.floor((M_val - 2) / 1798)))
    -- But simpler: iterate or use standard formula
    -- Standard reverse formula:
    local frames_per_10min = 17982  -- 29.97 * 60 * 10 rounded
    local num_10min = math.floor(total_frames / frames_per_10min)
    local remainder = total_frames % frames_per_10min

    local adj_frames
    if remainder < 2 then
      adj_frames = total_frames + 18 * num_10min
    else
      adj_frames = total_frames + 18 * num_10min + 2 * math.floor((remainder - 2) / 1798)
    end

    local f = adj_frames % 30
    local s = math.floor(adj_frames / 30) % 60
    local m = math.floor(adj_frames / 1800) % 60
    local h = math.floor(adj_frames / 108000)

    return string.format("%s%02d:%02d:%02d;%02d", sign, h, m, s, f)
  else
    -- Non-drop-frame
    local total_frames = math.floor(seconds * round_fps + 0.5)
    local f = total_frames % round_fps
    local total_seconds = math.floor(total_frames / round_fps)
    local s = total_seconds % 60
    local total_minutes = math.floor(total_seconds / 60)
    local m = total_minutes % 60
    local h = math.floor(total_minutes / 60)

    return string.format("%s%02d:%02d:%02d:%02d", sign, h, m, s, f)
  end
end

--- Detect FPS and drop-frame from FCM string and optional comment.
--- @param fcm_str string    "NON-DROP FRAME" or "DROP FRAME"
--- @param comment_fps string|nil  Optional FPS from comment (e.g., "25")
--- @return number fps, boolean is_drop
function M.detect_fps(fcm_str, comment_fps, default_fps)
  fcm_str = (fcm_str or ""):upper()
  local is_drop = fcm_str:find("DROP") and not fcm_str:find("NON%-DROP")

  -- If comment provides explicit FPS, use it
  if comment_fps then
    local n = tonumber(comment_fps)
    if n and n > 0 then
      return n, is_drop
    end
  end

  -- Infer from FCM
  if is_drop then
    return 29.97, true
  else
    -- Use caller-supplied default if provided, otherwise fall back to 25
    return default_fps or 25, false
  end
end

---------------------------------------------------------------------------
-- EDL Parser
---------------------------------------------------------------------------

--- Parse a CMX3600 EDL file.
--- @param filepath string   Path to .edl file
--- @param opts table|nil    Options: { default_fps = number }
--- @return table|nil        Parsed data structure, or nil on error
--- @return string|nil       Error message if failed
function M.parse(filepath, opts)
  opts = opts or {}

  local file, err = io.open(filepath, "r")
  if not file then
    return nil, "Cannot open file: " .. tostring(err)
  end

  local result = {
    format = "CMX3600",
    title = "",
    fcm = "",
    fps = opts.default_fps or 25,
    is_drop = false,
    events = {},
    source_path = filepath,
  }

  local lines = {}
  for line in file:lines() do
    -- Strip BOM if present
    if #lines == 0 then
      line = line:gsub("^\xEF\xBB\xBF", "")
    end
    -- Strip trailing CR/LF
    line = line:gsub("[\r\n]+$", "")
    lines[#lines + 1] = line
  end
  file:close()

  local current_event = nil
  local comment_fps = nil

  for _, line in ipairs(lines) do
    -- Skip blank lines
    if line:match("^%s*$") then
      -- nothing

    -- TITLE: line
    elseif line:match("^TITLE:") then
      result.title = line:match("^TITLE:%s*(.*)$") or ""

    -- FCM: line
    elseif line:match("^FCM:") then
      result.fcm = line:match("^FCM:%s*(.*)$") or ""

    -- Comment lines (start with *)
    elseif line:match("^%*") or line:match("^%s+%*") then
      local comment_body = line:match("^%s*%*%s*(.*)$") or ""

      -- Check for FPS comment: "* FCM: 25" or "* FRAME RATE: 25"
      local fps_val = comment_body:match("^FCM:%s*(%d+%.?%d*)") or
                      comment_body:match("^FRAME%s*RATE:%s*(%d+%.?%d*)")
      if fps_val then
        comment_fps = fps_val
      end

      -- Attach metadata to current event
      if current_event then
        -- FROM CLIP NAME:
        local clip = comment_body:match("^FROM CLIP NAME:%s*(.+)$")
        if clip then
          current_event.clip_name = clip
        end

        -- SOURCE FILE:
        local src = comment_body:match("^SOURCE FILE:%s*(.+)$")
        if src then
          current_event.source_file = src
        end

        -- TO CLIP NAME: (for transitions)
        local to_clip = comment_body:match("^TO CLIP NAME:%s*(.+)$")
        if to_clip then
          current_event.to_clip_name = to_clip
        end

        -- AUDIO LEVEL / VIDEO LEVEL
        -- Full format: "AUDIO LEVEL AT TC IS VALUE (REEL REEL_NAME TRACK)"
        -- Simple format: "AUDIO LEVEL AT TC IS VALUE"
        local function _parse_level_comment(prefix, body)
          local tc, db, reel, src_track =
            body:match("^" .. prefix .. " AT (%S+) IS (.-)%s+%(REEL (%S+) (%S+)%)%s*$")
          if not tc then
            tc, db = body:match("^" .. prefix .. " AT (%S+) IS (.+)$")
          end
          if tc then
            return { type = prefix == "AUDIO LEVEL" and "AUDIO" or "VIDEO",
                     tc = tc, db = db, reel = reel, src_track = src_track }
          end
        end

        local level_entry = _parse_level_comment("AUDIO LEVEL", comment_body)
                         or _parse_level_comment("VIDEO LEVEL", comment_body)
        if level_entry then
          current_event.audio_levels = current_event.audio_levels or {}
          current_event.audio_levels[#current_event.audio_levels + 1] = level_entry
        end

        -- Store all comments for round-trip fidelity
        current_event.comments = current_event.comments or {}
        current_event.comments[#current_event.comments + 1] = comment_body
      end

    -- Event line: starts with event number (3+ digits) followed by whitespace
    elseif line:match("^%d+%s") then
      local event = M._parse_event_line(line)
      if event then
        current_event = event
        result.events[#result.events + 1] = event
      end
    end
  end

  -- Detect FPS from FCM + comments; pass default_fps so caller's preference wins
  -- when EDL has no explicit FPS (e.g. plain "NON-DROP FRAME" with no comment FPS)
  result.fps, result.is_drop = M.detect_fps(result.fcm, comment_fps, opts.default_fps)

  -- Compute durations for all events
  for _, evt in ipairs(result.events) do
    local rec_in_sec = M.tc_to_seconds(evt.rec_tc_in, result.fps, result.is_drop)
    local rec_out_sec = M.tc_to_seconds(evt.rec_tc_out, result.fps, result.is_drop)
    evt.duration_seconds = rec_out_sec - rec_in_sec
    -- Duration as TC string
    evt.duration_tc = M.seconds_to_tc(evt.duration_seconds, result.fps, result.is_drop)
    -- Duration in frames
    local round_fps = math.floor(result.fps + 0.5)
    evt.duration_frames = math.floor(evt.duration_seconds * round_fps + 0.5)
  end

  return result
end

--- Parse a single event line.
--- Format: NNN  REEL  TRACK  TRANS  [DUR]  SRC_IN  SRC_OUT  REC_IN  REC_OUT
--- @param line string
--- @return table|nil  Event table
function M._parse_event_line(line)
  -- Try with dissolve/wipe duration first:
  -- "001  REEL  V  D  025  01:00:00:00 01:00:05:00 01:00:00:00 01:00:05:00"
  -- "001  REEL  V  W001 028  01:00:00:00 01:00:05:00 01:00:00:00 01:00:05:00"
  local evt, reel, track, trans, dur, si, so, ri, ro =
    line:match("^(%d+)%s+(%S+)%s+(%S+)%s+([CDWK]%d*)%s+(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")

  if not evt then
    -- Try without duration (cut):
    -- "001  REEL  V  C  01:00:00:00 01:00:05:00 01:00:00:00 01:00:05:00"
    evt, reel, track, trans, si, so, ri, ro =
      line:match("^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    dur = nil
  end

  if not evt then return nil end

  -- Normalize track field
  track = track:upper()

  return {
    event_num = evt,
    reel = reel,
    track = track,
    edit_type = trans:sub(1, 1):upper(),  -- C, D, W, K
    dissolve_len = dur and tonumber(dur) or nil,
    src_tc_in = si,
    src_tc_out = so,
    rec_tc_in = ri,
    rec_tc_out = ro,
    clip_name = "",
    source_file = "",
    to_clip_name = nil,
    comments = {},
  }
end

---------------------------------------------------------------------------
-- EDL Writer
---------------------------------------------------------------------------

--- Write parsed EDL data back to a CMX3600 file.
--- @param filepath string       Output file path
--- @param parsed_data table     Data structure from parse()
--- @return boolean|nil          true on success
--- @return string|nil           Error message on failure
function M.write(filepath, parsed_data)
  if not parsed_data or not parsed_data.events then
    return nil, "No data to write"
  end

  local file, err = io.open(filepath, "w")
  if not file then
    return nil, "Cannot open file for writing: " .. tostring(err)
  end

  -- Header
  file:write("TITLE: " .. (parsed_data.title or "Untitled") .. "\n")
  if parsed_data.fcm and parsed_data.fcm ~= "" then
    file:write("FCM: " .. parsed_data.fcm .. "\n")
  else
    file:write("FCM: NON-DROP FRAME\n")
  end
  file:write("\n")

  -- Events
  for _, evt in ipairs(parsed_data.events) do
    -- Build event line
    local trans_field
    if evt.dissolve_len and evt.dissolve_len > 0 then
      trans_field = string.format("%s %03d", evt.edit_type or "C", evt.dissolve_len)
    else
      trans_field = evt.edit_type or "C"
    end

    -- CMX3600 format: fixed-width fields
    -- Event(3) Reel(8+) Track(4+) Trans(varies) SrcIn SrcOut RecIn RecOut
    local line = string.format("%-3s  %-8s %-4s %-6s %s %s %s %s",
      evt.event_num or "001",
      evt.reel or "AX",
      evt.track or "V",
      trans_field,
      evt.src_tc_in or "00:00:00:00",
      evt.src_tc_out or "00:00:00:00",
      evt.rec_tc_in or "00:00:00:00",
      evt.rec_tc_out or "00:00:00:00"
    )
    file:write(line .. "\n")

    -- Comment lines
    if evt.clip_name and evt.clip_name ~= "" then
      file:write("* FROM CLIP NAME: " .. evt.clip_name .. "\n")
    end
    if evt.source_file and evt.source_file ~= "" then
      file:write("* SOURCE FILE: " .. evt.source_file .. "\n")
    end
    if evt.to_clip_name and evt.to_clip_name ~= "" then
      file:write("* TO CLIP NAME: " .. evt.to_clip_name .. "\n")
    end

    -- Write any additional comments that weren't standard metadata
    if evt.comments then
      for _, cmt in ipairs(evt.comments) do
        -- Skip standard comments we already wrote above
        if not cmt:match("^FROM CLIP NAME:")
          and not cmt:match("^SOURCE FILE:")
          and not cmt:match("^TO CLIP NAME:") then
          file:write("* " .. cmt .. "\n")
        end
      end
    end

    file:write("\n")
  end

  file:close()
  return true
end

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------

--- Get unique track list from events.
--- @param events table  Array of event tables
--- @return table        Sorted array of unique track names
function M.get_tracks(events)
  local seen = {}
  local tracks = {}
  for _, evt in ipairs(events or {}) do
    local t = evt.track
    if t and not seen[t] then
      seen[t] = true
      tracks[#tracks + 1] = t
    end
  end
  table.sort(tracks)
  return tracks
end

--- Validate a timecode string format.
--- @param tc_str string
--- @return boolean
function M.is_valid_tc(tc_str)
  if not tc_str or tc_str == "" then return false end
  return tc_str:match("^%d%d:%d%d:%d%d[:;.]%d%d$") ~= nil
end

--- Expand a track name template with event tokens.
--- @param template string   e.g. "${format} - ${track}"
--- @param tokens table      { format, track, reel, event, clip, title }
--- @return string
function M.expand_template(template, tokens)
  if not template then return "" end
  tokens = tokens or {}
  return (template:gsub("%${(%w+)}", function(key)
    return tokens[key] or ""
  end))
end

return M
