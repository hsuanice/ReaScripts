--[[
@description Convert Empty Items to Audio Items - keeps take names and notes
@version 26.1012.1641
@author hsuanice
@changelog
  - Renamed to "Convert Empty Items to Audio Items" (was "Convert empty items to audio items") as part of the 2026-10-12 naming clean-up.
  - Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.
@about
  Converts empty items (items whose active take has no source) into real audio
  items by attaching a generated silent WAV. Preserves take name and item notes.

  Use case:
    Scene Cut / Picture Cut / Subtitle tracks built with empty items can now be
    transferred to other DAWs together with the rest of the REAPER session,
    because empty items are not portable but audio items are. Mimics the
    EdiLoad picture-cut export style (one shared file per group).

  Behavior:
    • Scope: only operates on selected items.
    • Skips items that already have an audio source.
    • Active take only (multi-take items use the active take).
    • Items are grouped by track. Each group gets ONE shared silent WAV whose
      length equals the longest item in that group; all items in the group
      link to the same file. Per-item take name and notes are preserved.
    • Item D_LENGTH and D_POSITION are preserved (not overwritten by source).

  Output:
    • Folder: <project_path>/Media/
    • Format: 16-bit PCM, mono, project sample rate.

  Filename rules:
    • Single item, take name has no non-ASCII chars → use sanitized take name.
    • Otherwise (or take name is Chinese/empty) → "{TrackName}_{YYMMDDHHMM}.wav".
    • Track name also non-ASCII/empty → "Track{idx}_{YYMMDDHHMM}.wav".
    • Filename collisions auto-append _2, _3, ... to avoid overwriting.

  Notes:
    - Based on design concepts and iterative testing by hsuanice.
    - Script generated and refined with Claude.
--]]
local r = reaper

----------------------------------------------------------------
-- Utilities
----------------------------------------------------------------

local function msg(s)
  r.ShowConsoleMsg(tostring(s) .. "\n")
end

-- Returns true if string contains any byte >= 128 (non-ASCII, e.g. Chinese)
local function has_non_ascii(s)
  if not s or s == "" then return false end
  for i = 1, #s do
    if string.byte(s, i) >= 128 then return true end
  end
  return false
end

-- Filesystem-safe sanitize: replace illegal chars with _, trim, length cap
local function sanitize_filename(s, max_len)
  if not s then return "" end
  s = s:gsub('[/\\:*?"<>|]', "_")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("^%.+", ""):gsub("%.+$", "")
  if max_len and #s > max_len then s = s:sub(1, max_len) end
  return s
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- Returns a non-colliding path by appending _2, _3, ... before extension
local function unique_path(dir, base, ext)
  local sep = package.config:sub(1, 1)
  local function join(name) return dir .. sep .. name .. ext end
  if not file_exists(join(base)) then return join(base) end
  local i = 2
  while true do
    local cand = join(base .. "_" .. i)
    if not file_exists(cand) then return cand end
    i = i + 1
  end
end

----------------------------------------------------------------
-- WAV writer (16-bit PCM mono, all-zero data)
----------------------------------------------------------------

local function u16le(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF)
end

local function u32le(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF)
end

-- Writes a silent 16-bit mono PCM WAV of given length (seconds) at given sample rate.
-- Returns true on success, or false + error message.
local function write_silent_wav(path, length_sec, sample_rate)
  local channels = 1
  local bits_per_sample = 16
  local bytes_per_sample = bits_per_sample // 8
  local num_samples = math.max(1, math.floor(length_sec * sample_rate + 0.5))
  local data_size = num_samples * channels * bytes_per_sample
  local byte_rate = sample_rate * channels * bytes_per_sample
  local block_align = channels * bytes_per_sample

  local f, err = io.open(path, "wb")
  if not f then return false, err end

  -- RIFF header
  f:write("RIFF")
  f:write(u32le(36 + data_size))
  f:write("WAVE")
  -- fmt chunk
  f:write("fmt ")
  f:write(u32le(16))            -- chunk size
  f:write(u16le(1))             -- PCM format
  f:write(u16le(channels))
  f:write(u32le(sample_rate))
  f:write(u32le(byte_rate))
  f:write(u16le(block_align))
  f:write(u16le(bits_per_sample))
  -- data chunk
  f:write("data")
  f:write(u32le(data_size))

  -- Write zeros in chunks (avoid building one huge string)
  local chunk_bytes = 65536
  local zero_chunk = string.rep("\0", chunk_bytes)
  local remaining = data_size
  while remaining >= chunk_bytes do
    f:write(zero_chunk)
    remaining = remaining - chunk_bytes
  end
  if remaining > 0 then
    f:write(string.rep("\0", remaining))
  end

  f:close()
  return true
end

----------------------------------------------------------------
-- Item / take helpers
----------------------------------------------------------------

-- True when active take has no audio source (= empty item case we handle).
-- Also true when item has no take at all.
local function is_empty_item(item)
  local n = r.CountTakes(item)
  if n == 0 then return true end
  local take = r.GetActiveTake(item)
  if not take then return true end
  local src = r.GetMediaItemTake_Source(take)
  if not src then return true end
  -- Some empty takes report a source of length 0 / type "EMPTY"; treat those as empty too.
  local stype = r.GetMediaSourceType(src, "")
  if stype == nil or stype == "" or stype == "EMPTY" then return true end
  return false
end

local function get_track_name(track)
  local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

local function get_track_index(track)
  return math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
end

local function get_take_name(item)
  if r.CountTakes(item) == 0 then return "" end
  local take = r.GetActiveTake(item)
  if not take then return "" end
  local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  return name or ""
end

local function get_item_notes(item)
  local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  return notes or ""
end

----------------------------------------------------------------
-- Filename decision
----------------------------------------------------------------

local FNAME_MAX = 60

local function timestamp_yymmddhhmm()
  return os.date("%y%m%d%H%M")
end

-- Build the base filename (no extension, no collision handling) for a group.
--   group_items: array of items belonging to this track group
--   track:       MediaTrack
--   total_selected_count: total selected items across all groups
local function decide_basename(group_items, track, total_selected_count)
  local ts = timestamp_yymmddhhmm()
  local track_name = get_track_name(track)
  local track_idx  = get_track_index(track)

  -- Rule 1: only one item selected total AND its take name is ASCII-only & non-empty
  if total_selected_count == 1 and #group_items == 1 then
    local tn = get_take_name(group_items[1])
    if tn ~= "" and not has_non_ascii(tn) then
      local clean = sanitize_filename(tn, FNAME_MAX)
      if clean ~= "" then return clean end
    end
  end

  -- Rule 2/3: track-based naming
  if track_name ~= "" and not has_non_ascii(track_name) then
    local clean = sanitize_filename(track_name, FNAME_MAX)
    if clean ~= "" then return clean .. "_" .. ts end
  end

  -- Fallback: use track index
  return "Track" .. track_idx .. "_" .. ts
end

----------------------------------------------------------------
-- Main
----------------------------------------------------------------

local function main()
  local sel_count = r.CountSelectedMediaItems(0)
  if sel_count == 0 then
    r.ShowMessageBox("No items selected.", "Convert empty items to audio items", 0)
    return
  end

  -- Collect empty items, grouped by track (preserve track order via list of tracks)
  local groups = {}        -- track_ptr -> { items = {...}, track = track }
  local track_order = {}   -- list of track ptrs in insertion order
  local empty_total = 0

  for i = 0, sel_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if is_empty_item(item) then
      local track = r.GetMediaItem_Track(item)
      if not groups[track] then
        groups[track] = { items = {}, track = track }
        table.insert(track_order, track)
      end
      table.insert(groups[track].items, item)
      empty_total = empty_total + 1
    end
  end

  if empty_total == 0 then
    r.ShowMessageBox(
      ("No empty items in selection. (%d item(s) selected, all already have a source.)"):format(sel_count),
      "Convert empty items to audio items", 0)
    return
  end

  -- Project paths and sample rate
  local proj_path = r.GetProjectPath("")
  if proj_path == "" then
    r.ShowMessageBox("Please save the project first (Media folder is required).",
      "Convert empty items to audio items", 0)
    return
  end

  local sep = package.config:sub(1, 1)
  local media_dir = proj_path
  -- GetProjectPath returns the recording folder; ensure trailing separator handling
  -- and create a sibling "Media" if recording folder isn't already named Media.
  -- To keep it simple and predictable, use the recording folder as-is (it's typically
  -- already "<project>/Media" or the project root configured by the user).
  if not media_dir:match("[/\\]$") then media_dir = media_dir .. sep end
  r.RecursiveCreateDirectory(media_dir, 0)

  local sample_rate = math.floor(r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false))
  if sample_rate <= 0 then sample_rate = 48000 end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local converted = 0
  local files_written = 0

  for _, track in ipairs(track_order) do
    local g = groups[track]
    -- Find longest item length in this group
    local max_len = 0
    for _, item in ipairs(g.items) do
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if len > max_len then max_len = len end
    end
    if max_len <= 0 then max_len = 0.1 end

    -- Decide filename and resolve collisions
    local base = decide_basename(g.items, track, sel_count)
    local out_path = unique_path(media_dir:sub(1, -2), base, ".wav")

    local ok, err = write_silent_wav(out_path, max_len, sample_rate)
    if not ok then
      r.PreventUIRefresh(-1)
      r.Undo_EndBlock("Convert empty items to audio (failed)", -1)
      r.ShowMessageBox("Failed to write WAV: " .. tostring(err), "Error", 0)
      return
    end
    files_written = files_written + 1

    -- Build a source per item (sharing the same file). PCM_Source_CreateFromFile
    -- returns a new source object each call; safer to give each take its own object.
    for _, item in ipairs(g.items) do
      local original_len   = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local original_name  = get_take_name(item)
      local original_notes = get_item_notes(item)

      local take = r.GetActiveTake(item)
      if not take then
        take = r.AddTakeToMediaItem(item)
      end

      local src = r.PCM_Source_CreateFromFile(out_path)
      if src then
        r.SetMediaItemTake_Source(take, src)
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
        r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.0)
      end

      -- Restore properties (set source can reset length)
      r.SetMediaItemInfo_Value(item, "D_LENGTH", original_len)
      r.GetSetMediaItemTakeInfo_String(take, "P_NAME", original_name, true)
      r.GetSetMediaItemInfo_String(item, "P_NOTES", original_notes, true)

      r.UpdateItemInProject(item)
      converted = converted + 1
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Convert empty items to audio", -1)

  r.ShowMessageBox(
    ("Converted %d empty item(s) using %d shared file(s)."):format(converted, files_written),
    "Convert empty items to audio items", 0)
end

main()
