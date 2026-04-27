-- @description Spot selected items to Pro Tools (REAPER<>PT, v1)
-- @author Shanice
-- @version 0.1
--
-- v1 scope:
--   * playrate must be 1.0 (no time-stretch) — render first if not
--   * Source must be .wav with a 'bext' chunk (i.e. BWF)
--   * Trimmed items are OK: we spot the FULL source file at the TC of its
--     sample 0 on the timeline (= item_pos - src_offset). The user trims
--     head/tail in Pro Tools. (PT sees the whole file, not just the clip.)
--   * If sample-0 TC == BWF Time Reference     -> use original source as-is
--   * If sample-0 TC != BWF Time Reference     -> COPY to _PT_sync/ and patch
--                                                 the bext Time Reference in the COPY
--                                                 (original file is never modified)
--
-- Track mapping: Reaper track name == PT track name (exact match).
-- Suggested convention: REAPER<>PT_01, REAPER<>PT_02, ...

------------------------------------------------------------------------------
-- USER CONFIG
------------------------------------------------------------------------------

local PYTHON_CMD     = "/Users/shaniceyang/.pyenv/shims/python3"            -- "python" on Windows if no python3 alias
local SYNC_DIR_NAME  = "_PT_sync"           -- relative to project media folder
local BRIDGE_SCRIPT  = "ptsync_oneshot.py"  -- expected next to this .lua file

------------------------------------------------------------------------------
-- Path helpers
------------------------------------------------------------------------------

local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local PATH_SEP   = package.config:sub(1, 1)

local function path_join(...)
  return table.concat({...}, PATH_SEP)
end

local function basename(p) return p:match("([^/\\]+)$") or p end

local function file_exists(p)
  local f = io.open(p, "rb"); if f then f:close(); return true end; return false
end

local function ensure_dir(p)
  if PATH_SEP == "\\" then
    os.execute(string.format('if not exist "%s" mkdir "%s"', p, p))
  else
    os.execute(string.format('mkdir -p "%s"', p))
  end
end

local function is_wav(p) return p:lower():match("%.wav$") ~= nil end

------------------------------------------------------------------------------
-- BWF (RIFF/WAVE 'bext' chunk) reader / writer
------------------------------------------------------------------------------
-- bext layout (after the 8-byte chunk header "bext" + size):
--   Description           256 bytes   (offset   0)
--   Originator             32 bytes   (offset 256)
--   OriginatorReference    32 bytes   (offset 288)
--   OriginationDate        10 bytes   (offset 320)
--   OriginationTime         8 bytes   (offset 330)
--   TimeReferenceLow        4 bytes   (offset 338)  <-- LE uint32
--   TimeReferenceHigh       4 bytes   (offset 342)  <-- LE uint32
--   ...

local TR_OFFSET = 338  -- relative to start of bext data (i.e. after the 8-byte header)

local function read_at(f, offset, len)
  f:seek("set", offset); return f:read(len)
end

local function read_u32_le(f, offset)
  local s = read_at(f, offset, 4)
  if not s or #s < 4 then return nil end
  local b1, b2, b3, b4 = s:byte(1, 4)
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

-- Returns (data_offset, data_size) for the chunk with the given 4-char id, or nil.
-- data_offset points to the first byte AFTER the 8-byte chunk header.
local function find_chunk(f, target_id)
  local riff = read_at(f, 0, 4)
  if riff ~= "RIFF" then return nil, "not a RIFF file" end
  local wave = read_at(f, 8, 4)
  if wave ~= "WAVE" then return nil, "not a WAVE file" end

  local fsize = f:seek("end")
  local pos = 12
  while pos < fsize - 8 do
    local id = read_at(f, pos, 4)
    local sz = read_u32_le(f, pos + 4)
    if not id or not sz then break end
    if id == target_id then return pos + 8, sz end
    pos = pos + 8 + sz
    if sz % 2 == 1 then pos = pos + 1 end -- chunks are word-aligned
  end
  return nil, "chunk not found"
end

local function read_bwf_time_reference(path)
  local f, oerr = io.open(path, "rb")
  if not f then return nil, "open failed: " .. tostring(oerr) end
  local bext_off, why = find_chunk(f, "bext")
  if not bext_off then f:close(); return nil, "no bext chunk (" .. (why or "") .. ")" end
  local low  = read_u32_le(f, bext_off + TR_OFFSET)
  local high = read_u32_le(f, bext_off + TR_OFFSET + 4)
  f:close()
  if not low or not high then return nil, "could not read TimeReference" end
  return high * 4294967296 + low
end

local function u32_to_le_bytes(n)
  return string.char(
    n % 256,
    math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256,
    math.floor(n / 16777216) % 256
  )
end

-- Overwrite the bext Description field (256 bytes, ASCII, null-padded).
-- Pro Tools displays this as the imported clip name in the Clip List and on
-- timeline instances, so writing the Reaper take name here means PT picks it
-- up automatically — no post-import rename needed.
local function write_bwf_description(path, text)
  local f, oerr = io.open(path, "r+b")
  if not f then return false, "open failed: " .. tostring(oerr) end
  local bext_off, why = find_chunk(f, "bext")
  if not bext_off then f:close(); return false, "no bext chunk (" .. (why or "") .. ")" end

  local ascii = text:gsub("[^\032-\126]", "?")  -- replace non-printable-ASCII
  if #ascii > 256 then ascii = ascii:sub(1, 256) end
  local padded = ascii .. string.rep("\0", 256 - #ascii)

  f:seek("set", bext_off + 0)  -- Description starts at bext offset 0
  f:write(padded)
  f:close()
  return true
end

-- Overwrite TimeReferenceLow/High in place. Audio data untouched.
local function write_bwf_time_reference(path, samples)
  local f, oerr = io.open(path, "r+b")
  if not f then return false, "open failed: " .. tostring(oerr) end
  local bext_off, why = find_chunk(f, "bext")
  if not bext_off then f:close(); return false, "no bext chunk (" .. (why or "") .. ")" end

  local low  = samples % 4294967296
  local high = math.floor(samples / 4294967296)

  f:seek("set", bext_off + TR_OFFSET)
  f:write(u32_to_le_bytes(low))
  f:write(u32_to_le_bytes(high))
  f:close()
  return true
end

-- Patch iXML's TC fields in place. iXML keeps its own copy of the BWF Time
-- Reference and a "samples since midnight" timestamp; if these disagree with
-- the bext we just patched, Pro Tools reads conflicting metadata and corrupts
-- playback (audio data offsets get computed against the wrong file origin).
--
-- We must not change the iXML chunk's byte size — RIFF chunks are size-prefixed
-- and growing/shrinking would invalidate everything after. So we left-pad the
-- new value with zeros to match the old text length. XML parsers accept
-- "00001381700001" as the same number as "1381700001". If the new value
-- doesn't fit (more digits than the original), we return an error rather than
-- corrupt the chunk.
local IXML_TC_TAGS = {
  "BWF_TIME_REFERENCE_LOW",
  "BWF_TIME_REFERENCE_HIGH",
  "TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO",
  "TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI",
}

-- Replace inner text of <TAG>...</TAG> with new_val. Returns (new_text, ok).
local function replace_xml_tag(text, tag, new_val)
  local pat = "(<" .. tag .. ">)([^<]*)(</" .. tag .. ">)"
  if not text:match(pat) then return text, false end
  -- gsub_escape: % is the only special char in replacement strings
  local safe = new_val:gsub("%%", "%%%%")
  return text:gsub(pat, "%1" .. safe .. "%3", 1), true
end

local function patch_ixml_tc(path, samples)
  local f, oerr = io.open(path, "rb")
  if not f then return false, "open failed: " .. tostring(oerr) end
  local ixml_off, ixml_sz = find_chunk(f, "iXML")
  if not ixml_off then f:close(); return true, "no iXML chunk (skipped)" end

  -- Read whole file so we can splice if iXML changes size.
  f:seek("set", 0)
  local full = f:read("*a")
  f:close()
  if not full then return false, "could not read file" end

  local text = full:sub(ixml_off + 1, ixml_off + ixml_sz)
  if #text ~= ixml_sz then
    return false, string.format("iXML read truncated (%d/%d)", #text, ixml_sz)
  end

  local low  = samples % 4294967296
  local high = math.floor(samples / 4294967296)
  local replacements = {
    BWF_TIME_REFERENCE_LOW              = tostring(low),
    BWF_TIME_REFERENCE_HIGH             = tostring(high),
    TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO = tostring(low),
    TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI = tostring(high),
  }

  local new_text = text
  local patched = {}
  for _, tag in ipairs(IXML_TC_TAGS) do
    local out, ok = replace_xml_tag(new_text, tag, replacements[tag])
    if ok then
      new_text = out
      patched[#patched + 1] = tag
    end
  end

  -- If size unchanged, in-place patch (cheap).
  if #new_text == #text then
    local f2, e2 = io.open(path, "r+b")
    if not f2 then return false, "reopen failed: " .. tostring(e2) end
    f2:seek("set", ixml_off)
    f2:write(new_text)
    f2:close()
    return true, table.concat(patched, ",")
  end

  -- Size changed → splice. Each RIFF chunk must be word-aligned (even-sized);
  -- if data length is odd, a 0x00 pad byte follows the data (NOT counted in
  -- the chunk size header). Recompute padding for both old and new.
  local old_pad = (ixml_sz % 2 == 1) and 1 or 0
  local new_sz  = #new_text
  local new_pad = (new_sz % 2 == 1) and 1 or 0

  local before_header = full:sub(1, ixml_off - 8)     -- everything before the "iXML" id
  local after_chunk   = full:sub(ixml_off + ixml_sz + old_pad + 1)  -- everything after old iXML data + its pad

  local new_header = "iXML" .. u32_to_le_bytes(new_sz)
  local pad_byte   = string.rep("\0", new_pad)
  local rebuilt    = before_header .. new_header .. new_text .. pad_byte .. after_chunk

  -- Update outer RIFF size (file size - 8). Stored as u32 LE at offset 4.
  local riff_payload = #rebuilt - 8
  rebuilt = rebuilt:sub(1, 4) .. u32_to_le_bytes(riff_payload) .. rebuilt:sub(9)

  local fw, ew = io.open(path, "wb")
  if not fw then return false, "open for rewrite failed: " .. tostring(ew) end
  fw:write(rebuilt)
  fw:close()
  return true, table.concat(patched, ",") ..
    string.format(" [iXML resized %d->%d]", ixml_sz, new_sz)
end

------------------------------------------------------------------------------
-- File copy
------------------------------------------------------------------------------

local function copy_file(src, dst)
  local sf, e1 = io.open(src, "rb"); if not sf then return false, "src: " .. tostring(e1) end
  local df, e2 = io.open(dst, "wb"); if not df then sf:close(); return false, "dst: " .. tostring(e2) end
  while true do
    local chunk = sf:read(1024 * 1024)
    if not chunk then break end
    df:write(chunk)
  end
  sf:close(); df:close()
  return true
end

------------------------------------------------------------------------------
-- Minimal JSON encoder (good enough for a flat manifest)
------------------------------------------------------------------------------

local function json_escape(s)
  return (s:gsub('\\', '\\\\'):gsub('"', '\\"')
           :gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'))
end

local function json_encode(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "number" then return tostring(v)
  elseif t == "string" then return '"' .. json_escape(v) .. '"'
  elseif t == "table" then
    if #v > 0 then -- array
      local parts = {}
      for _, x in ipairs(v) do parts[#parts+1] = json_encode(x) end
      return "[" .. table.concat(parts, ",") .. "]"
    else -- object
      local parts = {}
      for k, x in pairs(v) do
        parts[#parts+1] = '"' .. json_escape(k) .. '":' .. json_encode(x)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

------------------------------------------------------------------------------
-- Item analysis
------------------------------------------------------------------------------

local function analyze_item(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil, "no active take" end
  if reaper.TakeIsMIDI(take) then return nil, "MIDI take not supported" end

  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return nil, "no source" end

  local src_path = reaper.GetMediaSourceFileName(source, "")
  local src_len  = reaper.GetMediaSourceLength(source)
  local src_sr   = reaper.GetMediaSourceSampleRate(source)

  local item_pos    = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len    = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local src_offset  = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local playrate    = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")

  local _, take_name  = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local track         = reaper.GetMediaItem_Track(item)
  local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)

  return {
    source_path = src_path,
    item_pos    = item_pos,
    item_len    = item_len,
    src_offset  = src_offset,
    src_len     = src_len,
    src_sr      = src_sr,
    playrate    = playrate,
    take_name   = take_name,
    track_name  = track_name,
  }
end

------------------------------------------------------------------------------
-- Console
------------------------------------------------------------------------------

local function msg(s) reaper.ShowConsoleMsg(tostring(s) .. "\n") end

------------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------------

local function main()
  reaper.ClearConsole()
  msg("=== Spot to Pro Tools (v1) ===")

  local count = reaper.CountSelectedMediaItems(0)
  if count == 0 then
    reaper.MB("No items selected.", "Spot to PT", 0)
    return
  end

  -- Need a saved project so we have a stable sync directory
  local proj_path = reaper.GetProjectPath("")
  if proj_path == "" then
    reaper.MB("Please save the Reaper project first (we need a project folder " ..
              "to stage synced files in).", "Spot to PT", 0)
    return
  end

  local sync_dir = path_join(proj_path, SYNC_DIR_NAME)
  ensure_dir(sync_dir)
  msg("Sync dir: " .. sync_dir)

  local manifest = { items = {} }
  local skipped  = 0

  for i = 0, count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local info, err = analyze_item(item)

    local function skip(reason)
      msg(string.format("  [skip] item %d: %s", i, reason))
      skipped = skipped + 1
    end

    if not info then
      skip(err or "?")
    elseif not is_wav(info.source_path) then
      skip("source is not .wav (" .. basename(info.source_path) .. ")")
    else
      local sr = info.src_sr

      -- Trimmed items are allowed: we spot the full source file at the TC
      -- of its sample 0 on the timeline. The only thing we can't handle is
      -- a non-1.0 playrate (PT can't represent that natively) — render first.
      if math.abs(info.playrate - 1.0) >= 1e-6 then
        skip(string.format(
          "playrate != 1.0 (%s) — render first (rate=%.4f)",
          info.take_name, info.playrate))
      else
        local existing_tc, tc_err = read_bwf_time_reference(info.source_path)
        if not existing_tc then
          skip(string.format("%s: %s — needs a BWF bext chunk; render first",
                             info.take_name, tc_err or ""))
        else
          -- BWF Time Reference encodes the timecode of sample 0 of the file.
          -- Item starts playing at item_pos, but sample 0 of the source
          -- corresponds to (item_pos - src_offset) on the timeline.
          local file_origin_sec = info.item_pos - info.src_offset
          local target_samples  = math.floor(file_origin_sec * sr + 0.5)
          -- file_for_pt stays nil until we either confirm the source's
          -- existing TC is already correct, or we successfully patch a copy.
          -- Any skip() on this item must leave it nil so we don't fall back
          -- to the unpatched source.
          local file_for_pt    = nil

          if math.abs(existing_tc - target_samples) > 1 then
            -- Need to patch: copy to sync dir, patch the copy.
            -- Embed target TC in filename so re-spotting at a different TC
            -- yields a different filename — Pro Tools keys its clip list by
            -- file path, so reusing one path across runs leaves stale clip
            -- entries that confuse rename_target_clip. With TC-stamped names,
            -- same TC = same file (idempotent); different TC = fresh file.
            local stem, ext = basename(info.source_path):match("^(.*)(%.[^.]+)$")
            if not stem then stem = basename(info.source_path); ext = "" end
            local copy_name = string.format("%s__pt%d%s", stem, target_samples, ext)
            local copy_path = path_join(sync_dir, copy_name)
            local cok, cerr = copy_file(info.source_path, copy_path)
            if not cok then
              skip("copy failed: " .. (cerr or "?"))
            else
              local pok, perr = write_bwf_time_reference(copy_path, target_samples)
              if not pok then
                skip("patch failed: " .. (perr or "?"))
              else
                local iok, iinfo = patch_ixml_tc(copy_path, target_samples)
                if not iok then
                  skip("iXML patch failed: " .. (iinfo or "?"))
                else
                  -- Stamp Reaper's take name into bext Description so PT
                  -- displays it as the clip name on import (no rename needed).
                  local dok, derr = write_bwf_description(copy_path, info.take_name)
                  if not dok then
                    msg(string.format("  [warn] description patch failed: %s", derr or "?"))
                  end
                  file_for_pt = copy_path
                  msg(string.format("  [patch] %s -> TC=%d samples (%.6fs, file origin); iXML: %s; desc=%q",
                                    basename(copy_path), target_samples, file_origin_sec,
                                    iinfo == "" and "no TC tags" or iinfo, info.take_name))
                end
              end
            end
          else
            file_for_pt = info.source_path
            msg(string.format("  [ok]   %s -> existing TC matches",
                              basename(info.source_path)))
          end

          if file_for_pt then
            manifest.items[#manifest.items + 1] = {
              source_path  = file_for_pt,
              target_track = info.track_name,
              clip_name    = info.take_name,
              tc_samples   = target_samples,
              sample_rate  = sr,
            }
          end
        end
      end
    end
  end

  if #manifest.items == 0 then
    reaper.MB(string.format(
      "No items eligible to spot (%d skipped). See Console for details.", skipped),
      "Spot to PT", 0)
    return
  end

  -- Write manifest
  local manifest_path = path_join(proj_path, "_ptsync_manifest.json")
  local mf, merr = io.open(manifest_path, "w")
  if not mf then
    reaper.MB("Cannot write manifest: " .. tostring(merr), "Spot to PT", 0)
    return
  end
  mf:write(json_encode(manifest))
  mf:close()
  msg("Manifest: " .. manifest_path)
  msg(string.format("Spotting %d item(s) to Pro Tools...", #manifest.items))

  -- Invoke Python bridge
  local bridge = SCRIPT_DIR .. BRIDGE_SCRIPT
  if not file_exists(bridge) then
    reaper.MB("Bridge script not found:\n" .. bridge ..
              "\n\nPlace ptsync_oneshot.py next to this .lua file.",
              "Spot to PT", 0)
    return
  end

  local cmd
  if PATH_SEP == "\\" then
    -- Windows: wrap whole command in extra quotes for cmd.exe
    cmd = string.format('""%s" "%s" "%s" 2>&1"', PYTHON_CMD, bridge, manifest_path)
  else
    cmd = string.format('"%s" "%s" "%s" 2>&1', PYTHON_CMD, bridge, manifest_path)
  end
  msg("Running: " .. cmd)

  local p = io.popen(cmd, "r")
  if not p then
    reaper.MB("Failed to launch bridge command.", "Spot to PT", 0)
    return
  end
  for line in p:lines() do
    msg("  | " .. line)
  end
  local ok, why, rc = p:close()
  if ok then
    msg("Done.")
  else
    msg(string.format("Bridge exit: %s (%s)", tostring(why), tostring(rc)))
    reaper.MB("Bridge command failed. See Reaper console for details.",
              "Spot to PT", 0)
  end
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Spot to Pro Tools", -1)
