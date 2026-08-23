--[[
@description hsuanice Batch Metadata Conform
@version 260823.2050
@author hsuanice
@noindex
@about
  File-based batch metadata conform preview tool.
  Phase 1/2: load WAV targets and original poly references, read metadata,
  build conservative matches, and preview the shared Match Result database.

  This version is intentionally read-only. Embed and rename are disabled until
  the source identity and poly stream mapping are validated against real files.

@changelog
  v260823.2050 (Asia/Taipei)
    - Saved stable loading/preview milestone.
    - Load folders using fast filename-only indexing before metadata scanning.
    - Defer Audio Cache loading and scan metadata explicitly from the UI.
    - Use per-folder !CLB_Audio_Cache_R.clbcache for Target and Reference.
    - Defer Build Match and report folder, cache, metadata, and match progress.
    - Keep Target/Reference paired preview rows and large-batch UI responsive.
]]
---@diagnostic disable: undefined-global

local SCRIPT_DIR = (debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "")
local LIB_DIR = SCRIPT_DIR:gsub("[/\\]Beta Testing[/\\]$", "/Library/")
local ok_meta, META = pcall(dofile, LIB_DIR .. "hsuanice_Metadata Read.lua")
if not ok_meta then
  reaper.ShowMessageBox("Cannot load Metadata Read library:\n\n" .. tostring(META), "Batch Metadata Conform", 0)
  return
end
if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("This script requires ReaImGui.", "Batch Metadata Conform", 0)
  return
end

local TARGETS, REFERENCES, RESULTS = {}, {}, {}
local filter, search = "All", ""
local show_log = false
local last_build_status = "Match has not been built yet"
local EXT_NS = "hsuanice_BatchMetadataConform"
local FONT_SCALE = math.max(0.5, math.min(3.0, tonumber(reaper.GetExtState(EXT_NS, "font_scale")) or 1.0))
local ALLOW_DOCKING = reaper.GetExtState(EXT_NS, "allow_docking") ~= "0"
local BASE_FONT_SIZE = 13
local status_order = { MATCHED = 1, AMBIGUOUS = 2, NOT_FOUND = 3, INVALID = 4 }
local MATCH_OPTIONS = {
  { key = "tape", label = "Tape" },
  { key = "scene", label = "Scene" },
  { key = "take", label = "Take" },
  { key = "originatorreference", label = "Originator Ref" },
  { key = "umid", label = "UMID" },
  { key = "filename", label = "Filename" },
  { key = "clip_name", label = "Clip Name" },
  { key = "track_name", label = "Track Name (stream)" },
}
local MATCH_CONFIG = { tape = true, scene = true, take = true }
for _, option in ipairs(MATCH_OPTIONS) do
  local saved = reaper.GetExtState(EXT_NS, "match_" .. option.key)
  if saved == "1" then MATCH_CONFIG[option.key] = true end
  if saved == "0" then MATCH_CONFIG[option.key] = false end
end
local selected_target_index = 1
local loading_state = nil
local scan_jobs = {}
local cache_scan_jobs = {}
local folder_scan_state = nil
local last_cache_status = ""
local metadata_scan_requested = false
local metadata_scan_status = "Metadata scan not started"
local active_task_status = "IDLE"
local active_task_started_at = 0
local match_coroutine = nil
local cache_fields = { "srcfile", "srcbase", "folder", "samplerate", "channels", "duration", "scene", "take", "tape", "reel", "project", "timereference", "src_tc", "description", "framerate", "speed", "orig_filename", "track_names", "ubits", "bit_depth", "file_type", "originationdate", "originationtime", "originator", "originatorreference", "umid", "clip_name" }

local function basename(path)
  return (tostring(path or ""):match("([^/\\]+)$") or tostring(path or ""))
end

local function stem(path)
  return basename(path):gsub("%.[^%.]+$", "")
end

local function source_base(path_or_stem)
  local value = stem(path_or_stem)
  value = value:gsub("%.[Aa]%d+$", "")
  value = value:gsub("%s+[Rr][Ee][Nn][Dd][Ee][Rr]%s*[%d]+$", "")
  value = value:gsub("[_%-]+[Rr][Ee][Nn][Dd][Ee][Rr][_-]*[%d]+$", "")
  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function basic_fields(path, role)
  return {
    srcpath = path,
    srcfile = basename(path),
    clip_name = stem(path),
    srcbase = source_base(path),
    role = role,
    __metadata_loaded = false,
    __ixml_tracks = {},
  }
end

local function dirname(path)
  return tostring(path or ""):match("^(.*)[/\\][^/\\]+$") or ""
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lower(value)
  return trim(value):lower()
end

local parse_description

local function read_meta(src, key)
  local ok, value = reaper.GetMediaFileMetadata(src, key)
  return ok == 1 and trim(value) or ""
end

local function cache_escape(value)
  return tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r\n", "\n"):gsub("\n", "%%0A")
end

local function cache_unescape(value)
  return tostring(value or ""):gsub("%%0A", "\n"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function cache_path(folder, role)
  return folder .. "/!CLB_Audio_Cache_R.clbcache"
end

local function cache_encode_fields(path, fields)
  local values = { cache_escape(path) }
  for _, key in ipairs(cache_fields) do values[#values + 1] = cache_escape(fields[key]) end
  local tracks = {}
  for _, track in ipairs(fields.__ixml_tracks or {}) do
    tracks[#tracks + 1] = table.concat({ track.channel_index or "", track.interleave_index or "", cache_escape(track.name) }, "^")
  end
  values[#values + 1] = table.concat(tracks, "~")
  return table.concat(values, "|")
end

local function cache_decode_fields(parts)
  if tonumber(parts[2]) then
    local fields = {
      srcpath = cache_unescape(parts[1]),
      srcfile = cache_unescape(parts[3]),
      clip_name = cache_unescape(parts[3]),
      srcbase = cache_unescape(parts[4]),
      folder = cache_unescape(parts[5]),
      samplerate = cache_unescape(parts[6]),
      channels = cache_unescape(parts[7]),
      duration = cache_unescape(parts[8]),
      scene = cache_unescape(parts[9]),
      take = cache_unescape(parts[10]),
      tape = cache_unescape(parts[11]),
      project = cache_unescape(parts[13]),
      timereference = cache_unescape(parts[14]),
      description = cache_unescape(parts[16]),
      framerate = cache_unescape(parts[17]),
      speed = cache_unescape(parts[18]),
      ubits = cache_unescape(parts[21]),
      file_type = cache_unescape(parts[23]),
      originationdate = cache_unescape(parts[24]),
      originationtime = cache_unescape(parts[25]),
      originator = cache_unescape(parts[26]),
      originatorreference = cache_unescape(parts[27]),
      orig_filename = cache_unescape(parts[29]),
      __ixml_tracks = {},
      __metadata_loaded = true,
    }
    local track_data = cache_unescape(parts[30])
    for track_text in (track_data .. "~"):gmatch("([^~]+)~") do
      local channel, interleave, name = track_text:match("^([^%^]*)%^([^%^]*)%^(.-)%^")
      if name then
        fields.__ixml_tracks[#fields.__ixml_tracks + 1] = {
          channel_index = tonumber(channel), interleave_index = tonumber(interleave), name = name
        }
      end
    end
    parse_description(fields.description, fields)
    fields.__trk_table = {}
    for index = 1, 64 do fields.__trk_table[index] = fields["trk" .. index] end
    fields.__chan_index = 1
    fields.__has_explicit_interleave = false
    return fields
  end
  if #parts == 21 then
    local fields = {
      srcpath = cache_unescape(parts[1]), srcfile = cache_unescape(parts[2]),
      srcbase = cache_unescape(parts[3]), folder = cache_unescape(parts[4]),
      samplerate = cache_unescape(parts[5]), channels = cache_unescape(parts[6]),
      duration = cache_unescape(parts[7]), scene = cache_unescape(parts[8]),
      take = cache_unescape(parts[9]), tape = cache_unescape(parts[10]),
      project = cache_unescape(parts[12]), timereference = cache_unescape(parts[13]),
      description = cache_unescape(parts[15]), framerate = cache_unescape(parts[16]),
      speed = cache_unescape(parts[17]), orig_filename = cache_unescape(parts[18]),
      track_names = cache_unescape(parts[19]), ubits = cache_unescape(parts[20]),
      clip_name = cache_unescape(parts[2]), bit_depth = "", file_type = "WAV",
      __ixml_tracks = {}, __metadata_loaded = true,
    }
    for name in (fields.track_names .. "_"):gmatch("([^_]+)_") do
      fields.__ixml_tracks[#fields.__ixml_tracks + 1] = { interleave_index = #fields.__ixml_tracks + 1, name = name }
    end
    return fields
  end
  local fields = {}
  for index, key in ipairs(cache_fields) do fields[key] = cache_unescape(parts[index + 1] or "") end
  fields.__ixml_tracks = {}
  for track_text in (parts[#parts] or ""):gmatch("([^~]+)") do
    local channel, interleave, name = track_text:match("^([^%^]*)%^([^%^]*)%^(.*)$")
    if name then fields.__ixml_tracks[#fields.__ixml_tracks + 1] = { channel_index = tonumber(channel), interleave_index = tonumber(interleave), name = cache_unescape(name) } end
  end
  fields.__trk_table = {}
  for index = 1, 64 do fields.__trk_table[index] = fields["trk" .. index] end
  fields.__chan_index = 1
  fields.__has_explicit_interleave = false
  fields.__metadata_loaded = true
  return fields
end

local function load_folder_cache(folder, role, paths)
  local started_at = reaper.time_precise()
  reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] START cache read: %s (%d files expected)\n", cache_path(folder, role), #paths))
  local file = io.open(cache_path(folder, role), "r")
  if not file then
    reaper.ShowConsoleMsg("[Batch Metadata Conform] cache not found; all files will be scanned\n")
    return {}
  end
  local cached = {}
  local header = file:read("*l")
  if not header then file:close(); return {} end
  local cached_folder, recursive, _, cached_count = header:match("^([^|]+)|([^|]+)|([^|]+)|(%d+)$")
  if cached_folder ~= folder or recursive ~= "R" or tonumber(cached_count) ~= #paths then
    file:close()
    reaper.ShowConsoleMsg("[Batch Metadata Conform] cache header mismatch; all files will be scanned\n")
    return {}
  end
  local decoded = 0
  for line in file:lines() do
    local parts = {}
    for part in (line .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
    if #parts == 21 or #parts >= #cache_fields + 2 then
      cached[cache_unescape(parts[1])] = cache_decode_fields(parts)
      decoded = decoded + 1
      if decoded % 500 == 0 then
        reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] cache read %s: %d/%d\n", role, decoded, #paths))
      end
    end
  end
  file:close()
  reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] END cache read: %s (%d records, %.2fs)\n", role, decoded, reaper.time_precise() - started_at))
  return cached
end

local function save_folder_cache(folder, role, records)
  local file = io.open(cache_path(folder, role), "w")
  if not file then return end
  file:write(folder, "|R|", os.time(), "|", #records, "\n")
  for _, record in ipairs(records) do if record.fields then file:write(cache_encode_fields(record.path, record.fields), "\n") end end
  file:close()
  reaper.ShowConsoleMsg("[Batch Metadata Conform] Saved Audio cache: " .. cache_path(folder, role) .. "\n")
end

local function read_meta_any(src, keys)
  for _, key in ipairs(keys) do
    local value = read_meta(src, key)
    if value ~= "" then return value end
  end
  return ""
end

local function target_track_name(fields)
  if type(fields and fields.__ixml_tracks) == "table" and #fields.__ixml_tracks == 1 then
    return trim(fields.__ixml_tracks[1].name)
  end
  return ""
end

parse_description = function(value, fields)
  for line in (tostring(value or "") .. "\n"):gmatch("(.-)\n") do
    local key, item = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if key and item then
      fields[key] = item
      fields[key:lower()] = item
      local base = key:upper():match("^[SD]([A-Z0-9_]+)$")
      if base then fields[base] = item; fields[base:lower()] = item end
      local number = key:upper():match("^[SD]?TRK(%d+)$")
      if number then fields["TRK" .. number] = item; fields["trk" .. number] = item end
    end
  end
end

local function read_file(path, role)
  local src = reaper.PCM_Source_CreateFromFile(path)
  if not src then return nil, "REAPER could not open the WAV source" end

  local fields = {
    srcpath = path,
    srcfile = basename(path),
    clip_name = stem(path),
    srcbase = source_base(path),
    role = role,
    channels = tostring(reaper.GetMediaSourceNumChannels(src) or 0),
    samplerate = tostring(math.floor((reaper.GetMediaSourceSampleRate(src) or 0) + 0.5)),
    bit_depth = read_meta_any(src, { "Metadata:BitsPerSample", "BitsPerSample", "SPEED:AUDIO_BIT_DEPTH" }),
    file_type = read_meta_any(src, { "Metadata:FileType", "FileType" }) ~= "" and read_meta_any(src, { "Metadata:FileType", "FileType" }) or "WAV",
    duration = tostring(reaper.GetMediaSourceLength(src) or 0),
    description = read_meta(src, "BWF:Description"),
    originationdate = read_meta(src, "BWF:OriginationDate"),
    originationtime = read_meta(src, "BWF:OriginationTime"),
    originator = read_meta(src, "BWF:Originator"),
    originatorreference = read_meta(src, "BWF:OriginatorReference"),
    timereference = read_meta(src, "BWF:TimeReference"),
    umid = read_meta_any(src, { "BWF:UMID", "UMID" }),
    scene = read_meta_any(src, { "IXML:SCENE", "SCENE" }),
    take = read_meta_any(src, { "IXML:TAKE", "TAKE" }),
    tape = read_meta_any(src, { "IXML:TAPE", "TAPE" }),
    project = read_meta_any(src, { "IXML:PROJECT", "PROJECT", "ASWG:PROJECT", "Metadata:Title" }),
    ubits = read_meta_any(src, { "IXML:UBITS", "UBITS" }),
    framerate = read_meta_any(src, { "IXML:FRAMERATE", "SPEED:TIMECODE_RATE", "FRAMERATE" }),
    speed = read_meta_any(src, { "IXML:SPEED", "SPEED", "SPEED:TIMECODE_FLAG" }),
    __ixml_tracks = {},
    __metadata_loaded = true,
  }
  if fields.description ~= "" then parse_description(fields.description, fields) end

  local count = tonumber(read_meta_any(src, { "IXML:TRACK_LIST:TRACK_COUNT", "TRACK_LIST:TRACK_COUNT" })) or 0
  for index = 1, count do
    local suffix = index > 1 and ":" .. index or ""
    local channel = tonumber(read_meta_any(src, { "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX" .. suffix, "TRACK_LIST:TRACK:CHANNEL_INDEX" .. suffix }))
    local interleave = tonumber(read_meta_any(src, { "IXML:TRACK_LIST:TRACK:INTERLEAVE_INDEX" .. suffix, "TRACK_LIST:TRACK:INTERLEAVE_INDEX" .. suffix }))
    local name = read_meta_any(src, { "IXML:TRACK_LIST:TRACK:NAME" .. suffix, "TRACK_LIST:TRACK:NAME" .. suffix })
    if name ~= "" then
      fields.__ixml_tracks[#fields.__ixml_tracks + 1] = {
        channel_index = channel, interleave_index = interleave or index, name = name
      }
      if channel then fields["trk" .. channel] = name; fields["TRK" .. channel] = name end
    end
  end
  fields.__trk_table = {}
  for index = 1, 64 do fields.__trk_table[index] = fields["trk" .. index] end
  fields.__chan_index = 1
  fields.__has_explicit_interleave = false
  reaper.PCM_Source_Destroy(src)
  return fields
end

local function identity_keys(fields)
  local keys = {}
  local function add(prefix, value)
    value = lower(value)
    if value ~= "" then keys[#keys + 1] = prefix .. value end
  end
  add("umid:", fields.umid)
  add("ref:", fields.originatorreference)
  add("scene:", tostring(fields.scene or "") .. "|" .. tostring(fields.take or "") .. "|" .. tostring(fields.tape or ""))
  add("base:", fields.srcbase)
  return keys
end

local function match_value(fields, key)
  if key == "filename" then return lower(fields.srcbase) end
  if key == "clip_name" then return lower(fields.clip_name) end
  if key == "track_name" then return lower(target_track_name(fields)) end
  return lower(fields[key])
end

local function selected_match_values(fields)
  local values = {}
  for _, option in ipairs(MATCH_OPTIONS) do
    if MATCH_CONFIG[option.key] then
      values[option.key] = match_value(fields, option.key)
    end
  end
  return values
end

local function channel_from_name(path)
  local name = stem(path)
  local number = name:match("%[?%s*[Cc]han(?:nel)?[%s_%-]*(%d+)%s*%]?")
    or name:match("[_%-][Cc][Hh](%d+)")
    or name:match("[_%-][Cc](%d+)$")
  return tonumber(number)
end

local function render_index_from_name(path)
  local name = stem(path)
  return tonumber(name:match("%.[Aa](%d+)$"))
    or tonumber(name:match("%s+[Rr][Ee][Nn][Dd][Ee][Rr]%s*(%d+)$"))
    or tonumber(name:match("[_%-][Rr][Ee][Nn][Dd][Ee][Rr][_-]*(%d+)$"))
end

local function reference_matches(target)
  local candidates, target_values = {}, selected_match_values(target)
  for _, reference in ipairs(REFERENCES) do
    if reference.fields then
      local filename_only = not target.__metadata_loaded or not reference.fields.__metadata_loaded
      if filename_only then
        if lower(target.srcbase) == lower(reference.fields.srcbase) then candidates[#candidates + 1] = reference end
      else
      local matched = false
      local usable = true
      for _, option in ipairs(MATCH_OPTIONS) do
        if MATCH_CONFIG[option.key] and option.key ~= "track_name" then
          local target_value = target_values[option.key]
          local reference_value = match_value(reference.fields, option.key)
          if target_value == "" or reference_value == "" or target_value ~= reference_value then
            usable = false
            break
          end
        end
      end
      matched = usable
      if matched then candidates[#candidates + 1] = reference end
      end
    end
  end
  return candidates
end

local function resolve_stream(target_fields, reference_fields)
  local target_name = target_track_name(target_fields)
  if MATCH_CONFIG.track_name and target_name ~= "" then
    local matches = {}
    for index, track in ipairs(reference_fields.__ixml_tracks or {}) do
      if lower(track.name) == lower(target_name) then matches[#matches + 1] = { index = index, track = track } end
    end
    if #matches == 1 then return matches[1].index, matches[1].track, "Target track name" end
    if #matches > 1 then return nil, nil, "Track name matches multiple streams" end
  end
  local stream = channel_from_name(target_fields.srcfile or "")
  local source = "Target filename channel suffix"
  if not stream and tonumber(target_fields.channels) == 1 then
    stream = render_index_from_name(target_fields.srcfile or "")
    source = "Mono render index"
  end
  if stream then
    for _, track in ipairs(reference_fields.__ixml_tracks or {}) do
      if tonumber(track.interleave_index) == stream then
        return stream, track, source
      end
    end
  end
  return nil, nil, target_name ~= "" and "Target track name was not selected or found in Poly" or "Target stream is not explicit"
end

local function build_results(write_console)
  RESULTS = {}
  local started_at = reaper.time_precise()
  local counts = { MATCHED = 0, AMBIGUOUS = 0, NOT_FOUND = 0, INVALID = 0 }
  if write_console then
    reaper.ShowConsoleMsg("\n=== Batch Metadata Conform: Build Match ===\n")
    reaper.ShowConsoleMsg(string.format("Targets: %d | References: %d\n", #TARGETS, #REFERENCES))
  end
  for _, target in ipairs(TARGETS) do
    local result = {
      target = target, status = "NOT_FOUND", reference = nil, stream = nil,
      recorder_ch = nil, track_name = nil, target_track_name = nil, match_values = {},
      proposed_filename = "", candidate_count = 0,
      reason = "No reliable source match"
    }
    if not target.fields then
      result.status = "INVALID"
      result.reason = target.error or "Metadata read failed"
    else
      local candidates = reference_matches(target.fields)
      result.candidate_count = #candidates
      result.match_values = selected_match_values(target.fields)
      if #candidates == 1 then
      result.reference = candidates[1]
      local stream, track, stream_reason = resolve_stream(target.fields, candidates[1].fields)
      result.target_track_name = target_track_name(target.fields)
      if stream and track then
        result.status = "MATCHED"
        result.stream = stream
        result.recorder_ch = track.channel_index
        result.track_name = track.name
        result.reason = "Unique source and stream match: " .. stream_reason
        result.proposed_filename = target.fields.srcbase .. "_" .. (track.name ~= "" and track.name or ("stream" .. stream)) .. ".wav"
      else
        result.status = "AMBIGUOUS"
        result.reason = "Reference found, but " .. stream_reason
      end
      elseif #candidates > 1 then
        result.status = "AMBIGUOUS"
        result.reason = "Multiple possible source references"
      end
    end
    counts[result.status] = counts[result.status] + 1
    if write_console then
      local keys = target.fields and table.concat(identity_keys(target.fields), ", ") or "<no metadata fields>"
      local reference_name = result.reference and basename(result.reference["path"]) or "-"
      reaper.ShowConsoleMsg(string.format(
        "%s | %s | candidates=%d | reference=%s | keys=%s | reason=%s\n",
        result.status, target.filename, result.candidate_count, reference_name, keys, result.reason))
    end
    RESULTS[#RESULTS + 1] = result
    if match_coroutine and #RESULTS % 100 == 0 then
      reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] match progress: %d/%d\n", #RESULTS, #TARGETS))
      coroutine.yield()
    end
    if write_console and #RESULTS % 500 == 0 then
      reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] match progress: %d/%d (%.2fs)\n", #RESULTS, #TARGETS, reaper.time_precise() - started_at))
    end
  end
  table.sort(RESULTS, function(a, b) return (status_order[a.status] or 9) < (status_order[b.status] or 9) end)
  last_build_status = string.format("Last build: %d matched, %d ambiguous, %d not found, %d invalid", counts.MATCHED, counts.AMBIGUOUS, counts.NOT_FOUND, counts.INVALID)
  if write_console then
    reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] match elapsed: %.2fs\n", reaper.time_precise() - started_at))
    reaper.ShowConsoleMsg(last_build_status .. "\n=== End Build Match ===\n")
  end
end

local function start_match_build(write_console)
  if match_coroutine then return end
  active_task_status = "BUILDING MATCH"
  active_task_started_at = reaper.time_precise()
  reaper.ShowConsoleMsg("[Batch Metadata Conform] START Build Match (deferred)\n")
  match_coroutine = coroutine.create(function() build_results(write_console) end)
end

local function process_match_build()
  if not match_coroutine then return end
  local ok, error_message = coroutine.resume(match_coroutine)
  if not ok then
    reaper.ShowConsoleMsg("[Batch Metadata Conform] MATCH ERROR: " .. tostring(error_message) .. "\n")
    match_coroutine = nil
    active_task_status = "IDLE"
    last_build_status = "Match failed: " .. tostring(error_message)
  elseif coroutine.status(match_coroutine) == "dead" then
    match_coroutine = nil
    active_task_status = "IDLE"
    reaper.ShowConsoleMsg("[Batch Metadata Conform] END Build Match\n")
  end
end

local function build_basic_results()
  RESULTS = {}
  for _, target in ipairs(TARGETS) do
    RESULTS[#RESULTS + 1] = {
      target = target,
      status = "NOT_FOUND",
      reference = nil,
      stream = nil,
      recorder_ch = nil,
      track_name = nil,
      target_track_name = nil,
      match_values = {},
      proposed_filename = "",
      candidate_count = 0,
      reason = "Filename loaded; metadata scan pending",
    }
  end
end

local function add_paths(paths, role, folder)
  local records, pending, cached = {}, {}, {}
  for _, path in ipairs(paths) do
    if path:lower():match("%.wav$") then
      local record = { path = path, filename = basename(path), fields = basic_fields(path, role) }
      pending[#pending + 1] = record
      records[#records + 1] = record
    end
  end
  loading_state = {
    role = role, folder = folder, records = records, pending = pending,
    current = 0, total = #pending, from_cache = #pending == 0,
    started_at = reaper.time_precise(),
    scanning = false, cache_checked = false,
  }
  scan_jobs[role] = loading_state
  last_cache_status = string.format("%s: %d files indexed; cache deferred until Scan Metadata", role, #records)
  reaper.ShowConsoleMsg("[Batch Metadata Conform] Audio cache: " .. cache_path(folder, role) .. "\n")
  reaper.ShowConsoleMsg("[Batch Metadata Conform] " .. last_cache_status .. "\n")
  if role == "target" then TARGETS = records else REFERENCES = records end
  metadata_scan_status = string.format("%s loaded: %d files; press Scan Metadata", role, #records)
  reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] READY %s: %d filename records\n", role, #records))
  build_basic_results()
end

local function start_metadata_scan()
  metadata_scan_requested = true
  if #cache_scan_jobs > 0 then
      if match_coroutine then
        metadata_scan_status = "Build Match is already running"
        return
      end
    metadata_scan_status = "Audio Cache is already loading"
    return
  end
  for _, state in pairs(scan_jobs) do
    if state.scanning then
      metadata_scan_status = "Metadata scan is already running"
      return
    end
  end
  if folder_scan_state then
    metadata_scan_status = "Finish loading file list first"
    return
  end
  cache_scan_jobs = {}
  for _, state in pairs(scan_jobs) do
    if not state.cache_checked then cache_scan_jobs[#cache_scan_jobs + 1] = state end
  end
  if #cache_scan_jobs == 0 then
    metadata_scan_status = "Metadata is already cached or no files loaded"
    active_task_status = "IDLE"
    start_match_build(false)
    return
  end
  active_task_status = "LOADING CACHE"
  active_task_started_at = reaper.time_precise()
  metadata_scan_status = "Loading Audio Cache..."
  reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] START deferred cache loading (%d folders)\n", #cache_scan_jobs))
  for _, state in ipairs(cache_scan_jobs) do
    reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] QUEUE cache: %s (%d records)\n", state.role, #state.records))
  end
end

local function finish_cache_job(state, cached, cache_found)
  local pending, cached_count = {}, 0
  for _, record in ipairs(state.records) do
    local cached_fields = cache_found and cached[record.path] or nil
    if cached_fields then
      cached_fields.role = state.role
      record.fields = cached_fields
      cached_count = cached_count + 1
    else
      record.fields = basic_fields(record.path, state.role)
      pending[#pending + 1] = record
    end
  end
  state.pending, state.current, state.total = pending, 0, #pending
  state.cache_checked = true
  last_cache_status = string.format("%s: %d cached, %d to scan", state.role, cached_count, #pending)
  reaper.ShowConsoleMsg("[Batch Metadata Conform] " .. state.role .. " cache loaded: " .. cached_count .. " cached, " .. #pending .. " to scan\n")
  if #pending > 0 then
    reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] QUEUE metadata scan: %s (%d files)\n", state.role, #pending))
  end
end

local function process_cache_scan_batch()
  local state = cache_scan_jobs[1]
  if not state then return false end
  if not state.cache_file then
    state.cache_file = io.open(cache_path(state.folder, state.role), "r")
    state.cache = {}
    state.cache_lines = 0
    state.cache_expected = #state.records
    state.cache_valid = false
    if state.cache_file then
      local header = state.cache_file:read("*l") or ""
      local cached_folder, recursive, _, count = header:match("^([^|]+)|([^|]+)|([^|]+)|(%d+)$")
      state.cache_valid = cached_folder == state.folder and recursive == "R" and tonumber(count) == state.cache_expected
    end
  end
  if not state.cache_file or not state.cache_valid then
    if state.cache_file then state.cache_file:close() end
    finish_cache_job(state, {}, false)
    table.remove(cache_scan_jobs, 1)
    if #cache_scan_jobs == 0 then
      reaper.ShowConsoleMsg("[Batch Metadata Conform] END deferred cache loading\n")
      local jobs = 0
      for _, metadata_state in pairs(scan_jobs) do
        if metadata_state.total > metadata_state.current then
          metadata_state.scanning = true
          metadata_state.started_at = reaper.time_precise()
          jobs = jobs + 1
        end
      end
      if jobs > 0 then
        metadata_scan_status = "Scanning metadata..."
        active_task_status = "SCANNING METADATA"
        reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] START metadata scan (%d jobs)\n", jobs))
      else
        metadata_scan_status = "Metadata is already cached or no files loaded"
        start_match_build(false)
      end
    end
    return #cache_scan_jobs > 0
  end
  for _ = 1, 500 do
    local line = state.cache_file:read("*l")
    if not line then
      state.cache_file:close()
      finish_cache_job(state, state.cache, true)
      table.remove(cache_scan_jobs, 1)
      if #cache_scan_jobs == 0 then
        reaper.ShowConsoleMsg("[Batch Metadata Conform] END deferred cache loading\n")
        local jobs = 0
        for _, metadata_state in pairs(scan_jobs) do
          if metadata_state.total > metadata_state.current then
            metadata_state.scanning = true
            metadata_state.started_at = reaper.time_precise()
            jobs = jobs + 1
          end
        end
        if jobs > 0 then
          metadata_scan_status = "Scanning metadata..."
          active_task_status = "SCANNING METADATA"
          reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] START metadata scan (%d jobs)\n", jobs))
        else
          metadata_scan_status = "Metadata is already cached or no files loaded"
          start_match_build(false)
        end
      end
      return #cache_scan_jobs > 0
    end
    state.cache_lines = state.cache_lines + 1
    local parts = {}
    for part in (line .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = part end
    if #parts == 21 or #parts >= #cache_fields + 2 then
      state.cache[cache_unescape(parts[1])] = cache_decode_fields(parts)
    end
  end
  reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] cache read %s: %d/%d\n", state.role, state.cache_lines, state.cache_expected))
  return true
end

local function process_loading_batch()
  if match_coroutine then return end
  if #cache_scan_jobs > 0 then return end
  if not loading_state or not loading_state.scanning then
    loading_state = scan_jobs.target and scan_jobs.target.scanning and scan_jobs.target or scan_jobs.reference and scan_jobs.reference.scanning and scan_jobs.reference
  end
  if not loading_state or not loading_state.scanning then return end
  local state = loading_state
  local batch_size = 5
  for _ = 1, batch_size do
    local record = state.pending[state.current + 1]
    if not record then break end
    record.fields, record.error = read_file(record.path, state.role)
    if record.fields then record.fields.__metadata_loaded = true end
    state.current = state.current + 1
    if state.current % 500 == 0 then
      reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] metadata scan %s: %d/%d\n", state.role, state.current, state.total))
    end
  end
  if state.current >= state.total then
    save_folder_cache(state.folder, state.role, state.records)
    state.scanning = false
    reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] END metadata scan: %s (%d files)\n", state.role, state.total))
    if state.role == "reference" or not (scan_jobs.reference and scan_jobs.reference.scanning) then
      metadata_scan_status = "Metadata scan complete"
      start_match_build(false)
    end
    loading_state = scan_jobs.target and scan_jobs.target.scanning and scan_jobs.target or scan_jobs.reference and scan_jobs.reference.scanning and scan_jobs.reference
  end
end

local function loading_progress_text(state)
  if not state then return "" end
  local elapsed = math.max(0, reaper.time_precise() - state.started_at)
  local rate = state.current > 0 and state.current / math.max(elapsed, 0.001) or 0
  local remaining = rate > 0 and math.max(0, state.total - state.current) / rate or 0
  local function clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
  end
  return string.format("Scanning %s: %d/%d | elapsed %s | ETA %s | %.1f files/s",
    state.role, state.current, state.total, clock(elapsed),
    state.current >= state.total and "done" or clock(remaining), rate)
end

local function is_audio_file(path)
  return tostring(path or ""):lower():match("%.wav$") ~= nil
end

local function start_folder_scan(folder, role)
  active_task_status = "LOADING FILE LIST"
  active_task_started_at = reaper.time_precise()
  reaper.ShowConsoleMsg("[Batch Metadata Conform] START file list: " .. folder .. "\n")
  folder_scan_state = {
    folder = folder, role = role, directories = { folder }, paths = {},
    files_seen = 0, displayed_count = 0, started_at = reaper.time_precise()
  }
end

local function update_basic_file_list(state)
  if #state.paths <= state.displayed_count then return end
  local records = state.role == "target" and TARGETS or REFERENCES
  for index = state.displayed_count + 1, #state.paths do
    local path = state.paths[index]
    records[#records + 1] = {
      path = path,
      filename = basename(path),
      fields = basic_fields(path, state.role),
    }
  end
  if state.role == "target" then TARGETS = records else REFERENCES = records end
  state.displayed_count = #state.paths
  if state.role == "target" then
    for index = #RESULTS + 1, #TARGETS do
      local target = TARGETS[index]
      RESULTS[#RESULTS + 1] = {
        target = target, status = "NOT_FOUND", reference = nil,
        stream = nil, recorder_ch = nil, track_name = nil,
        target_track_name = nil, match_values = {}, proposed_filename = "",
        candidate_count = 0, reason = "Filename loaded; metadata scan pending",
      }
    end
  end
end

local function folder_scan_progress_text(state)
  local elapsed = math.max(0, reaper.time_precise() - state.started_at)
  return string.format("Loading file list (%s): %d files | elapsed %02d:%02d",
    state.role, state.files_seen, math.floor(elapsed / 60), math.floor(elapsed % 60))
end

local function process_folder_scan()
  local state = folder_scan_state
  if not state then return end
  local directories_per_frame = 2
  for _ = 1, directories_per_frame do
    local directory = table.remove(state.directories, 1)
    if not directory then break end
    local index = 0
    while true do
      local filename = reaper.EnumerateFiles(directory, index)
      if not filename then break end
      state.files_seen = state.files_seen + 1
      if is_audio_file(filename) then state.paths[#state.paths + 1] = directory .. "/" .. filename end
      index = index + 1
    end
    update_basic_file_list(state)
    index = 0
    while true do
      local subfolder = reaper.EnumerateSubdirectories(directory, index)
      if not subfolder then break end
      state.directories[#state.directories + 1] = directory .. "/" .. subfolder
      index = index + 1
    end
  end
  if #state.directories == 0 then
    local paths, role, folder = state.paths, state.role, state.folder
    folder_scan_state = nil
    table.sort(paths, function(a, b) return lower(basename(a)) < lower(basename(b)) end)
    add_paths(paths, role, folder)
    active_task_status = "IDLE"
    reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] END file list: %s (%d WAV files, %.2fs)\n", role, #paths, reaper.time_precise() - state.started_at))
  end
end

local function scan_audio_folder(folder, paths)
  paths = paths or {}
  local index = 0
  while true do
    local filename = reaper.EnumerateFiles(folder, index)
    if not filename then break end
    local path = folder .. "/" .. filename
    if is_audio_file(filename) then paths[#paths + 1] = path end
    index = index + 1
  end
  index = 0
  while true do
    local subfolder = reaper.EnumerateSubdirectories(folder, index)
    if not subfolder then break end
    scan_audio_folder(folder .. "/" .. subfolder, paths)
    index = index + 1
  end
  return paths
end

local function pick_folder(role)
  local folder
  if reaper.JS_Dialog_BrowseForFolder then
    local accepted, selected = reaper.JS_Dialog_BrowseForFolder(
      role == "target" and "Select Target Folder" or "Select Reference Folder", "")
    if accepted == 1 then folder = selected end
  else
    local accepted, path = reaper.GetUserFileNameForRead("", "Select any audio file in folder", "wav")
    if accepted and path ~= "" then folder = dirname(path) end
  end
  if folder and folder ~= "" then
    loading_state = nil
    folder_scan_state = nil
    if role == "target" then TARGETS = {} else REFERENCES = {} end
    start_folder_scan(folder, role)
  end
end

local function clear_lists(clear_targets, clear_references)
  if clear_targets then TARGETS = {}; scan_jobs.target = nil end
  if clear_references then REFERENCES = {}; scan_jobs.reference = nil end
  folder_scan_state = nil
  loading_state = nil
  reaper.ShowConsoleMsg(string.format("[Batch Metadata Conform] CLEAR lists: targets=%s references=%s\n", tostring(clear_targets), tostring(clear_references)))
  build_basic_results()
end

local function text(value) return tostring(value or "") end
local function single_line(value, max_chars)
  local value_text = text(value):gsub("\r\n", " "):gsub("[\r\n]", " "):gsub("%s+", " ")
  max_chars = max_chars or 160
  if #value_text > max_chars then return value_text:sub(1, max_chars - 3) .. "..." end
  return value_text
end

local function color_u32(red, green, blue, alpha)
  return reaper.ImGui_ColorConvertDouble4ToU32(red, green, blue, alpha or 1)
end

local function cell_color(result, row_role, key)
  if row_role == "REFERENCE" then return color_u32(0.55, 0.75, 1.0, 1) end
  if key == "status" then
    if result.status == "MATCHED" then return color_u32(0.35, 1.0, 0.45, 1) end
    if result.status == "AMBIGUOUS" then return color_u32(1.0, 0.85, 0.2, 1) end
    if result.status == "NOT_FOUND" then return color_u32(1.0, 0.45, 0.35, 1) end
  end
  if key == "diff" then
    return result.status == "MATCHED" and color_u32(0.35, 1.0, 0.45, 1) or color_u32(1.0, 0.85, 0.2, 1)
  end
  local reference_fields = result.reference and result.reference.fields
  local target_fields = result.target and result.target.fields
  local comparable = reference_fields and target_fields and {
    umid = true, originationdate = true, originationtime = true, originator = true,
    originatorreference = true, timereference = true, description = true, project = true,
    scene = true, take = true, tape = true, ubits = true, framerate = true, speed = true,
  }
  if row_role == "TARGET" and comparable and comparable[key] then
    local target_value = lower(target_fields[key])
    local reference_value = lower(reference_fields[key])
    if target_value ~= "" and target_value == reference_value then return color_u32(0.35, 1.0, 0.45, 1) end
    return color_u32(1.0, 0.85, 0.2, 1)
  end
  if row_role == "TARGET" and result.status == "MATCHED" and (key == "stream" or key == "recorder_ch" or key == "track_name") then
    return color_u32(0.35, 1.0, 0.45, 1)
  end
  return nil
end

local function button(label, callback)
  if reaper.ImGui_Button(ctx, label) then callback() end
end

local function draw_options()
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_SmallButton(ctx, "Options##options_button") then
    reaper.ImGui_OpenPopup(ctx, "##options_popup")
  end
  if reaper.ImGui_BeginPopup(ctx, "##options_popup") then
    local docking_label = (ALLOW_DOCKING and "[x] " or "[ ] ") .. "Allow Docking"
    if reaper.ImGui_Selectable(ctx, docking_label, false) then
      ALLOW_DOCKING = not ALLOW_DOCKING
      reaper.SetExtState(EXT_NS, "allow_docking", ALLOW_DOCKING and "1" or "0", true)
    end
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Font Size")
    for _, option in ipairs({
      { label = "75%", scale = 0.75 },
      { label = "100% (Default)", scale = 1.0 },
      { label = "125%", scale = 1.25 },
      { label = "150%", scale = 1.5 },
      { label = "200%", scale = 2.0 },
    }) do
      local marker = math.abs(FONT_SCALE - option.scale) < 0.01 and ">> " or "   "
      if reaper.ImGui_Selectable(ctx, marker .. option.label, false) then
        FONT_SCALE = option.scale
        reaper.SetExtState(EXT_NS, "font_scale", tostring(FONT_SCALE), true)
      end
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function draw_match_settings()
  reaper.ImGui_Text(ctx, "MATCH SETTINGS")
  for index, option in ipairs(MATCH_OPTIONS) do
    if index > 1 then reaper.ImGui_SameLine(ctx) end
    local changed, enabled = reaper.ImGui_Checkbox(ctx, option.label .. "##match_" .. option.key, MATCH_CONFIG[option.key] == true)
    if changed then
      MATCH_CONFIG[option.key] = enabled
      reaper.SetExtState(EXT_NS, "match_" .. option.key, enabled and "1" or "0", true)
    end
  end
  reaper.ImGui_TextWrapped(ctx, "Selected fields must match exactly. Track Name also resolves the target to the corresponding Poly stream.")
end

local function match_values_text(values)
  local output = {}
  for _, option in ipairs(MATCH_OPTIONS) do
    if MATCH_CONFIG[option.key] then
      output[#output + 1] = option.label .. "=" .. (values[option.key] ~= "" and values[option.key] or "<empty>")
    end
  end
  return table.concat(output, " | ")
end

local function draw_target_metadata_preview()
  local target = TARGETS[selected_target_index]
  if not target or not target.fields then return end
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "TARGET METADATA PREVIEW: " .. target.filename)
  local fields = target.fields
  reaper.ImGui_TextWrapped(ctx, string.format(
    "Filename=%s | Clip Name=%s | Tape=%s | Scene=%s | Take=%s | Originator Ref=%s | UMID=%s | Track Name=%s | Channels=%s | Duration=%s",
    fields.srcfile or "", fields.clip_name or "", fields.tape or "", fields.scene or "", fields.take or "",
    fields.originatorreference or "", fields.umid or "", target_track_name(fields),
    fields.channels or "", fields.duration or ""))
end

local TRANSFER_FIELDS = {
  { key = "timereference", label = "TimeReference" },
  { key = "originatorreference", label = "Originator Ref" },
  { key = "umid", label = "UMID" },
  { key = "tape", label = "Tape" },
  { key = "scene", label = "Scene" },
  { key = "take", label = "Take" },
}

local function metadata_transfer_text(target_fields, reference_fields)
  if not reference_fields then return "No reference matched" end
  local changes = {}
  for _, field in ipairs(TRANSFER_FIELDS) do
    local target_value = trim(target_fields[field.key])
    local source_value = trim(reference_fields[field.key])
    if target_value == "" and source_value ~= "" then
      changes[#changes + 1] = "MISSING " .. field.label .. " -> " .. source_value
    elseif lower(target_value) ~= lower(source_value) and source_value ~= "" then
      changes[#changes + 1] = "OVERWRITE " .. field.label .. ": " .. (target_value ~= "" and target_value or "<empty>") .. " -> " .. source_value
    end
  end
  if #changes == 0 then return "No metadata changes detected" end
  return table.concat(changes, " | ")
end

local function poly_streams_text(fields)
  local streams = {}
  for index, track in ipairs(fields and fields.__ixml_tracks or {}) do
    streams[#streams + 1] = string.format("stream %d / Recorder Ch %s / %s", index, track.channel_index or "-", track.name ~= "" and track.name or "<unnamed>")
  end
  return #streams > 0 and table.concat(streams, " | ") or "No TRACK_LIST metadata"
end

local function poly_track_names_text(fields)
  local names = {}
  for _, track in ipairs(fields and fields.__ixml_tracks or {}) do
    if trim(track.name) ~= "" then names[#names + 1] = trim(track.name) end
  end
  return #names > 0 and table.concat(names, " | ") or "-"
end

local DISPLAY_COLUMNS = {
  { key = "role", label = "Role" },
  { key = "status", label = "Status" },
  { key = "filename", label = "Filename" },
  { key = "stream", label = "Interleave Stream" },
  { key = "recorder_ch", label = "Recorder Ch" },
  { key = "track_name", label = "Track Name" },
  { key = "target_track_name", label = "Target Trk Name" },
  { key = "poly_track_names", label = "Poly Trk Names" },
  { key = "poly_streams", label = "Poly Stream Map" },
  { key = "srcbase", label = "Source Base" },
  { key = "samplerate", label = "Sample Rate" },
  { key = "bit_depth", label = "Bit Depth" },
  { key = "file_type", label = "File Type" },
  { key = "channels", label = "Channels" },
  { key = "duration", label = "Duration" },
  { key = "umid", label = "UMID" },
  { key = "originationdate", label = "Origination Date" },
  { key = "originationtime", label = "Origination Time" },
  { key = "originator", label = "Originator" },
  { key = "originatorreference", label = "Originator Ref" },
  { key = "timereference", label = "TimeReference" },
  { key = "description", label = "BWF Description" },
  { key = "project", label = "iXML Project" },
  { key = "scene", label = "iXML Scene" },
  { key = "take", label = "iXML Take" },
  { key = "tape", label = "iXML Tape" },
  { key = "ubits", label = "iXML UBITS" },
  { key = "framerate", label = "iXML Framerate" },
  { key = "speed", label = "iXML Speed" },
  { key = "proposed_filename", label = "Proposed Name" },
  { key = "diff", label = "Metadata Diff" },
  { key = "reason", label = "Reason" },
}

local function display_column_value(result, row_role, key)
  local fields = row_role == "TARGET" and result.target.fields or (result.reference and result.reference.fields)
  if key == "role" then return row_role end
  if key == "status" then return row_role == "TARGET" and result.status or "SOURCE" end
  if key == "filename" then return fields and fields.srcfile or "-" end
  if key == "srcbase" then return fields and fields.srcbase or "-" end
  if key == "stream" then return result.stream or "-" end
  if key == "recorder_ch" then return result.recorder_ch or "-" end
  if key == "track_name" then
    return row_role == "TARGET" and (result.target_track_name or "-") or (result.track_name or "-")
  end
  if key == "target_track_name" then return row_role == "TARGET" and (result.target_track_name or "-") or "-" end
  if key == "poly_track_names" then return row_role == "REFERENCE" and poly_track_names_text(fields) or "-" end
  if key == "poly_streams" then return row_role == "REFERENCE" and poly_streams_text(fields) or "-" end
  if key == "proposed_filename" then return row_role == "TARGET" and (result.proposed_filename ~= "" and result.proposed_filename or "-") or "-" end
  if key == "diff" then return row_role == "TARGET" and metadata_transfer_text(result.target.fields or {}, fields) or "Source metadata used for conform" end
  if key == "reason" then return row_role == "TARGET" and result.reason or "Original Poly metadata" end
  return fields and (fields[key] or "") or "-"
end

ctx = reaper.ImGui_CreateContext("hsuanice Batch Metadata Conform")
reaper.ImGui_SetNextWindowSize(ctx, 1180, 720, reaper.ImGui_Cond_FirstUseEver())

local function loop()
  process_folder_scan()
  process_cache_scan_batch()
  process_loading_batch()
  process_match_build()
  local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
  if not ALLOW_DOCKING then
    window_flags = window_flags | reaper.ImGui_WindowFlags_NoDocking()
  end
  local font_pushed = false
  if reaper.ImGui_PushFont then
    local ok_font = pcall(reaper.ImGui_PushFont, ctx, nil, math.floor(BASE_FONT_SIZE * FONT_SCALE))
    font_pushed = ok_font
  end
  local visible, open = reaper.ImGui_Begin(ctx, "hsuanice Batch Metadata Conform", true, window_flags)
  if visible then
    reaper.ImGui_Text(ctx, "File-based batch conform preview")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, string.format("TARGET FILES %d", #TARGETS))
    reaper.ImGui_SameLine(ctx); button("Load Target Folder...", function() pick_folder("target") end)
    reaper.ImGui_SameLine(ctx); reaper.ImGui_Text(ctx, string.format("REFERENCE POLY FILES %d", #REFERENCES))
    reaper.ImGui_SameLine(ctx); button("Load Reference Folder...", function() pick_folder("reference") end)
    reaper.ImGui_SameLine(ctx); button("Clear Lists", function() clear_lists(true, true) end)
    if folder_scan_state then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, folder_scan_progress_text(folder_scan_state))
    elseif #cache_scan_jobs > 0 then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, "Loading Audio Cache... " .. (cache_scan_jobs[1].role or ""))
    elseif loading_state then
      reaper.ImGui_SameLine(ctx)
      if loading_state.scanning then
        reaper.ImGui_Text(ctx, loading_progress_text(loading_state))
      else
        reaper.ImGui_Text(ctx, "Folder loaded; metadata scan not started")
      end
    end
    if last_cache_status ~= "" then
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, last_cache_status)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Scan Metadata") then start_metadata_scan() end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, metadata_scan_status)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "Task: " .. active_task_status)
    draw_options()
    if reaper.ImGui_Button(ctx, "Build Match") then
      start_match_build(true)
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, last_build_status)
    draw_match_settings()
    reaper.ImGui_Separator(ctx)

    local counts = { MATCHED = 0, AMBIGUOUS = 0, NOT_FOUND = 0, INVALID = 0 }
    for _, result in ipairs(RESULTS) do counts[result.status] = counts[result.status] + 1 end
    reaper.ImGui_Text(ctx, string.format("%d Targets   %d Matched   %d Ambiguous   %d Not Found   %d Invalid", #RESULTS, counts.MATCHED, counts.AMBIGUOUS, counts.NOT_FOUND, counts.INVALID))
    for _, name in ipairs({ "All", "Matched", "Warning", "Not Found", "Invalid" }) do
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, name) then filter = name end
    end
    local changed, value = reaper.ImGui_InputText(ctx, "Search", search)
    if changed then search = value end

    if reaper.ImGui_BeginTable(ctx, "matches", #DISPLAY_COLUMNS, reaper.ImGui_TableFlags_Borders() + reaper.ImGui_TableFlags_RowBg() + reaper.ImGui_TableFlags_ScrollY() + reaper.ImGui_TableFlags_ScrollX() + reaper.ImGui_TableFlags_Resizable() + reaper.ImGui_TableFlags_SizingFixedFit(), 0, 420) then
      for _, column in ipairs(DISPLAY_COLUMNS) do
        local label = column.label
        if MATCH_CONFIG[column.key] and column.key ~= "track_name" then label = label .. " [MATCH]" end
        if MATCH_CONFIG.track_name and column.key == "track_name" then label = label .. " [STREAM]" end
        reaper.ImGui_TableSetupColumn(ctx, label)
      end
      reaper.ImGui_TableHeadersRow(ctx)
      local visible_results = {}
      for _, result in ipairs(RESULTS) do
        local allowed = filter == "All" or (filter == "Matched" and result.status == "MATCHED") or (filter == "Warning" and result.status == "AMBIGUOUS") or (filter == "Not Found" and result.status == "NOT_FOUND") or (filter == "Invalid" and result.status == "INVALID")
        local haystack = lower(result.target.filename .. " " .. (result.reference and result.reference.filename or "") .. " " .. result.reason)
        if allowed and (search == "" or haystack:find(lower(search), 1, true)) then
          visible_results[#visible_results + 1] = result
        end
      end
      local preview_count = math.min(5, #visible_results)
      local row_count = preview_count * 2
      local first_row, last_row = 1, row_count
      for display_row = first_row, last_row do
        local result = visible_results[math.floor((display_row - 1) / 2) + 1]
        local row_index = ((display_row - 1) % 2) + 1
        local row_role = row_index == 1 and "TARGET" or "REFERENCE"
        if result then
            reaper.ImGui_TableNextRow(ctx)
            for column, definition in ipairs(DISPLAY_COLUMNS) do
              local full_cell = display_column_value(result, row_role, definition.key)
              local cell = single_line(full_cell)
              reaper.ImGui_TableNextColumn(ctx)
              local color = cell_color(result, row_role, definition.key)
              if color then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), color) end
              if row_role == "TARGET" then
                reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), color_u32(0.18, 0.14, 0.08, 0.65))
              else
                reaper.ImGui_TableSetBgColor(ctx, reaper.ImGui_TableBgTarget_RowBg0(), color_u32(0.08, 0.14, 0.20, 0.65))
              end
              if row_index == 1 and definition.key == "filename" then
                if reaper.ImGui_Selectable(ctx, text(cell) .. "##target_" .. tostring(result.target.path), result.target == TARGETS[selected_target_index]) then
                  for index, target in ipairs(TARGETS) do
                    if target == result.target then selected_target_index = index; break end
                  end
                end
              else
                reaper.ImGui_Text(ctx, text(cell))
              end
              if #text(full_cell) > #text(cell) and reaper.ImGui_BeginItemTooltip then
                if reaper.ImGui_BeginItemTooltip(ctx) then
                  reaper.ImGui_Text(ctx, text(full_cell))
                  reaper.ImGui_EndTooltip(ctx)
                end
              end
              if color then reaper.ImGui_PopStyleColor(ctx) end
            end
        end
      end
      reaper.ImGui_EndTable(ctx)
    end
    draw_target_metadata_preview()
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Processing is read-only in this phase. Embed + Rename will be enabled after stream mapping validation.")
    if reaper.ImGui_Button(ctx, show_log and "Hide Log" or "Show Log") then show_log = not show_log end
    if show_log then
      reaper.ImGui_TextWrapped(ctx, "Reference files are never modified. Only MATCHED results are eligible for the future processor; AMBIGUOUS, NOT_FOUND, and INVALID results are excluded by design.")
    end
    reaper.ImGui_End(ctx)
  end
  if font_pushed then reaper.ImGui_PopFont(ctx) end
  if open then
    reaper.defer(loop)
  elseif reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(ctx)
  end
end

reaper.defer(loop)
