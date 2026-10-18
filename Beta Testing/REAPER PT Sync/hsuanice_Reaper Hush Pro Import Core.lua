--[[
@description Hush Pro Import Core - shared code for importing Hush Pro Split files back into REAPER
@version 26.1018.2105
@author hsuanice
@noindex  (kept in the repository as a backup; local REAPER <> Pro Tools tools, not offered on ReaPack)
@about
  Used by "hsuanice_Reaper Import Hush Pro Split.lua" (manual) and
  "hsuanice_Reaper Hush Pro Monitor.lua" (watch window started by Spot to Pro Tools).
  Local tool next to "hsuanice_Reaper Spot to Pro Tools.lua"; returns a table, not an action.

  Written with Claude Code (AI); designed and tested by hsuanice.
--]]

local r = reaper
local M = {}

------------------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------------------
M.HUSH_DIR   = "/Volumes/Elephlow-Cache/_TEMP/Hush Pro/Audio Files"
M.SYNC_DIR   = "_PT_sync"                              -- same as Spot to Pro Tools
M.DUP_TRACKS = { [1] = "Dialog", [2] = "Reverb", [3] = "Noise" }
local DUP_TRACKS = M.DUP_TRACKS
local SYNC_DIR   = M.SYNC_DIR
local SAME_LEVEL = 1e-6                                -- -120 dBFS: "same audio"

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------
local function basename(p) return (p:match("([^/\\]+)$")) or p end
local function stem_of(name) return (name:gsub("%.[Ww][Aa][Vv]$", "")) end
local function join(dir, name) return (dir:gsub("[/\\]+$", "")) .. "/" .. name end
local function shell_quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- fmt (format tag, channels, rate, bits), data position / size, BWF Time Reference
local function wav_info(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local head = f:read(12)
  if not head or #head < 12 or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then f:close(); return nil end
  local size = f:seek("end")
  local info, pos = {}, 12
  while pos + 8 <= size do
    f:seek("set", pos)
    local h = f:read(8)
    if not h or #h < 8 then break end
    local id, sz = h:sub(1, 4), string.unpack("<I4", h, 5)
    if id == "fmt " then
      local b = f:read(16)
      info.tag, info.ch, info.sr = string.unpack("<I2I2I4", b, 1)
      info.bits = string.unpack("<I2", b, 15)
    elseif id == "bext" and sz >= 346 then
      local b = f:read(346)
      info.tr = string.unpack("<I8", b, 339)
    elseif id == "data" then
      info.data_pos, info.data_size = pos + 8, sz
    end
    pos = pos + 8 + sz + (sz % 2)
  end
  f:close()
  if not (info.ch and info.data_pos) then return nil end
  info.frames = info.data_size // (info.ch * info.bits // 8)
  return info
end

-- Same audio? Same layout and timecode; float data: every 8th sample within SAME_LEVEL
-- (Pro Tools' float processing rounds the last bits); integer data: identical bytes.
local function same_audio(a_path, b_path)
  local a, b = wav_info(a_path), wav_info(b_path)
  if not (a and b) then return false, "not readable as WAV" end
  if a.ch ~= b.ch or a.bits ~= b.bits or a.tag ~= b.tag or a.data_size ~= b.data_size then
    return false, "different length / format"
  end
  if a.tr and b.tr and a.tr ~= b.tr then return false, "different timecode" end
  local fa, fb = io.open(a_path, "rb"), io.open(b_path, "rb")
  fa:seek("set", a.data_pos); fb:seek("set", b.data_pos)
  local left, block = a.data_size, 1 << 20
  local float = (a.tag == 3 and a.bits == 32)
  local ok = true
  while left > 0 and ok do
    local n = math.min(block, left)
    local da, db = fa:read(n), fb:read(n)
    if not da or not db or #da ~= #db then ok = false break end
    if float then
      for i = 1, #da - 3, 32 do -- every 8th float
        if math.abs(string.unpack("<f", da, i) - string.unpack("<f", db, i)) > SAME_LEVEL then ok = false break end
      end
    elseif da ~= db then
      ok = false
    end
    left = left - n
  end
  fa:close(); fb:close()
  return ok, ok and nil or "audio differs"
end

-- Move a file across volumes: copy, check the size, delete the original. Never overwrites.
local function free_name(dir, name)
  local path = join(dir, name)
  if not r.file_exists(path) then return path end
  local s, ext = name:match("^(.*)(%.[^.]+)$")
  s, ext = s or name, ext or ""
  for k = 2, 999 do
    local p = join(dir, string.format("%s (%d)%s", s, k, ext))
    if not r.file_exists(p) then return p end
  end
end

local function move_file(src, dst_dir)
  local dst = free_name(dst_dir, basename(src))
  if not dst then return nil, "no free file name" end
  if os.rename(src, dst) then return dst end -- same volume
  local fi, fo = io.open(src, "rb"), io.open(dst, "wb")
  if not fi or not fo then
    if fi then fi:close() end
    if fo then fo:close() end
    return nil, "cannot copy"
  end
  while true do
    local chunk = fi:read(4 << 20)
    if not chunk then break end
    fo:write(chunk)
  end
  local in_size = fi:seek("end")
  local out_size = fo:seek("end")
  fi:close(); fo:close()
  if in_size ~= out_size then os.remove(dst); return nil, "copy size mismatch" end
  os.remove(src)
  return dst
end

local function trash_file(path)
  local cmd = "osascript -e 'on run argv' -e 'tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)'"
    .. " -e 'end run' " .. shell_quote(path) .. " >/dev/null 2>&1"
  os.execute(cmd)
  return not r.file_exists(path)
end

-- REAPER item whose source is <stem> (Spot used it as-is) or <base>__pt<N> (patched copy:
-- source <base>, file origin at sample N on the timeline)
local function find_source_item(stem)
  local base, n = stem:match("^(.*)__pt(%d+)$")
  for i = 0, r.CountMediaItems(0) - 1 do
    local it = r.GetMediaItem(0, i)
    local take = r.GetActiveTake(it)
    local src = take and r.GetMediaItemTake_Source(take)
    if src then
      local parent = r.GetMediaSourceParent(src)
      while parent do src = parent; parent = r.GetMediaSourceParent(src) end
      local s = stem_of(basename(r.GetMediaSourceFileName(src, "") or ""))
      if n and s == base then
        local sr = r.GetMediaSourceSampleRate(src)
        local origin = r.GetMediaItemInfo_Value(it, "D_POSITION") - r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        if sr > 0 and math.abs(origin * sr - tonumber(n)) <= 1 then return it end
      elseif not n and s == stem then
        return it
      end
    end
  end
end

-- Dialog / Reverb / Noise: always three NEW tracks (existing tracks with these names are never
-- used), at the same folder level as the source track:
--   - normal track: right below it
--   - last track of a folder (depth < 0): right below it, and the last new track takes over the
--     folder end, so the new tracks stay inside the folder
--   - folder parent (depth 1): after the whole folder, not as its children
--   - no source track: at the end of the project
local function target_tracks(below)
  local idx = r.CountTracks(0) -- 0-based index for the first new track
  local close_depth = 0        -- folder end to hand over to the last new track
  if below then
    local n = math.floor(r.GetMediaTrackInfo_Value(below, "IP_TRACKNUMBER")) -- 1-based
    local depth = r.GetMediaTrackInfo_Value(below, "I_FOLDERDEPTH")
    if depth > 0 then
      -- skip the folder's children: walk until the running depth is back to the parent's level
      local level, i = depth, n
      while level > 0 and i < r.CountTracks(0) do
        level = level + r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_FOLDERDEPTH")
        i = i + 1
      end
      idx = i
      if level < 0 then -- the folder's last child also closed outer folders: keep them closed after us
        local last = r.GetTrack(0, i - 1)
        r.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", r.GetMediaTrackInfo_Value(last, "I_FOLDERDEPTH") - level)
        close_depth = level
      end
    else
      idx = n
      if depth < 0 then
        r.SetMediaTrackInfo_Value(below, "I_FOLDERDEPTH", 0)
        close_depth = depth
      end
    end
  end
  local out = {}
  for k = 1, 3 do
    r.InsertTrackAtIndex(idx + k - 1, true)
    local tr = r.GetTrack(0, idx + k - 1)
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", DUP_TRACKS[k], true)
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    out[k] = tr
  end
  if close_depth ~= 0 then r.SetMediaTrackInfo_Value(out[3], "I_FOLDERDEPTH", close_depth) end
  return out
end

local function insert_file(track, path)
  local info = wav_info(path)
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then return nil end
  local it = r.AddMediaItemToTrack(track)
  local take = r.AddTakeToMediaItem(it)
  r.SetMediaItemTake_Source(take, src)
  local sr = (info and info.sr) or r.GetMediaSourceSampleRate(src)
  -- same convention as Spot to Pro Tools: Time Reference = timeline position in samples
  local pos = (info and info.tr and sr > 0) and (info.tr / sr) or 0
  r.SetMediaItemInfo_Value(it, "D_POSITION", pos)
  r.SetMediaItemInfo_Value(it, "D_LENGTH", (r.GetMediaSourceLength(src)))
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", stem_of(basename(path)), true)
  r.UpdateItemInProject(it)
  return it, pos
end


M.basename, M.stem_of, M.join = basename, stem_of, join
M.wav_info, M.same_audio, M.move_file, M.trash_file = wav_info, same_audio, move_file, trash_file
M.find_source_item = find_source_item
M.target_tracks = target_tracks

------------------------------------------------------------------------------
-- Folder content
------------------------------------------------------------------------------
-- Visible file names in a folder
function M.list_files(dir)
  local files, i = {}, 0
  while true do
    local name = r.EnumerateFiles(dir, i)
    if not name then break end
    if name:sub(1, 1) ~= "." then files[#files + 1] = name end
    i = i + 1
  end
  return files
end

-- "<stem>.dupN-HshSplt_NN.wav" -> stem, N
function M.split_name(name)
  local stem, n = name:match("^(.-)%.dup(%d+)%-HshSplt_%d+%.[Ww][Aa][Vv]$")
  return stem, n and tonumber(n)
end
-- Hush Pro's copy of the original: "<clip name>-HshSplt_NN.wav" without dupN
function M.is_original_copy(name)
  return not M.split_name(name) and name:match("%-HshSplt_%d+%.[Ww][Aa][Vv]$") ~= nil
end

-- groups[stem] = { [N] = name }, order, originals, others
function M.classify(files)
  local groups, order, originals, others = {}, {}, {}, {}
  for _, name in ipairs(files) do
    local stem, n = M.split_name(name)
    if stem then
      if not groups[stem] then groups[stem] = {}; order[#order + 1] = stem end
      groups[stem][n] = name
    elseif M.is_original_copy(name) then
      originals[#originals + 1] = name
    else
      others[#others + 1] = name
    end
  end
  return groups, order, originals, others
end

-- Is a file written completely? The RIFF size field matches the file size and the data
-- chunk fits inside the file (while Pro Tools still writes, they usually do not).
function M.file_state(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:seek("set", 0)
  local head = f:read(12)
  f:close()
  if not head or #head < 12 then return size, false end
  local riff = string.unpack("<I4", head, 5)
  local complete = head:sub(1, 4) == "RIFF" and riff + 8 == size
  if complete then
    local info = wav_info(path)
    complete = info ~= nil and info.data_pos + info.data_size <= size
  end
  return size, complete
end

-- The file that was sent to Pro Tools for a stem (patched copy in _PT_sync, or the source)
function M.sent_file(stem, dest)
  local sent = join(join(dest, SYNC_DIR), stem .. ".wav")
  if r.file_exists(sent) then return sent end
  local it = find_source_item(stem)
  local take = it and r.GetActiveTake(it)
  local src = take and r.GetMediaItemTake_Source(take)
  local p = src and r.GetMediaSourceFileName(src, "") or ""
  return (p ~= "" and r.file_exists(p)) and p or nil
end

------------------------------------------------------------------------------
-- Import
------------------------------------------------------------------------------
-- Move one split group into `dest` and place it on Dialog / Reverb / Noise (one undo point).
-- Returns report lines, warnings.
function M.import_group(stem, names, dest)
  local report, warnings = {}, {}
  local src_item = find_source_item(stem)
  local src_track = src_item and r.GetMediaItem_Track(src_item)
  if not src_item then warnings[#warnings + 1] = stem .. ": source item not found - tracks go to the end of the project" end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local tracks = target_tracks(src_track)
  for n, name in pairs(names) do
    local new_path, err = move_file(join(M.HUSH_DIR, name), dest)
    if not new_path then
      warnings[#warnings + 1] = name .. ": " .. tostring(err)
    elseif tracks[n] then
      local it, pos = insert_file(tracks[n], new_path)
      if it then
        report[#report + 1] = string.format("%-6s %s  @ %s", DUP_TRACKS[n], basename(new_path), r.format_timestr_pos(pos, "", 5))
      else
        warnings[#warnings + 1] = basename(new_path) .. ": could not be imported"
      end
    else
      report[#report + 1] = string.format("moved  %s (dup%d: no track for it)", basename(new_path), n)
    end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
  r.UpdateArrange()
  r.Undo_EndBlock("Import Hush Pro Split", -1)
  return report, warnings
end

-- Hush Pro's copies of the original: to the Trash when the audio matches one of `stems`' sent
-- files. Unmatched copies are moved to `dest` when move_unmatched is true, else left alone.
-- Returns report lines, warnings, number trashed.
function M.handle_originals(originals, stems, dest, move_unmatched)
  local report, warnings, trashed = {}, {}, 0
  for _, name in ipairs(originals) do
    local path = join(M.HUSH_DIR, name)
    local matched
    for _, stem in ipairs(stems) do
      local sent = M.sent_file(stem, dest)
      if sent and same_audio(sent, path) then matched = sent break end
    end
    if matched and trash_file(path) then
      trashed = trashed + 1
      report[#report + 1] = "trash  " .. name .. "  (same audio as " .. basename(matched) .. ")"
    elseif move_unmatched then
      local new_path, err = move_file(path, dest)
      warnings[#warnings + 1] = name .. (new_path and ": not confirmed as a copy of the original - moved, not deleted" or (": " .. tostring(err)))
    end
  end
  return report, warnings, trashed
end

return M
