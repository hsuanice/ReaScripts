--[[
@description Metadata Embed - BWF MetaEdit helpers
@version 26.1011.2142
@author hsuanice
@noindex
@changelog
  - Released as part of the 26.1011.2142 package update.
  - Full history of earlier versions: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Direct-copy metadata embed helpers for Ediload-split / fully-correct source files.
  - Safe BWF MetaEdit calls
  - Normalize iXML sidecar newline
  - Exact copy of metadata from a trusted source to a target WAV
  - No channel-name guessing or per-track metadata remapping in direct mode
  - Read/write TimeReference and post-embed refresh
  - Write a caller-built iXML document from scratch (not copied from a source)
--]]

local E = {}
E.VERSION = "261007.1128"

local function _trim_outer(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ===== Shell wrapper / exec (same as TR tool style) =====
local IS_WIN = reaper.GetOS():match("Win")

local function sh_wrap(cmd)
  if IS_WIN then
    return 'cmd.exe /C "'..cmd..'"'
  else
    return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'" -- escape safely
  end
end

local function exec_shell(cmd, ms)
  local ret = reaper.ExecProcess(sh_wrap(cmd), ms or 20000) or ""
  local code, out = ret:match("^(%d+)\n(.*)$")
  return tonumber(code or -1), (out or "")
end

local function _is_wav(path)
  return path and type(path)=="string" and path:lower():sub(-4)==".wav"
end

local function _log(log_fn, text)
  if type(log_fn) == "function" then log_fn(text) end
end

local function _file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function _read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function _write_file(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data or "")
  f:close()
end

local function _remove_file_silent(path)
  if not path or path == "" then return end
  if _file_exists(path) then os.remove(path) end
end

local function _normalize_newlines(s)
  if not s or s == "" then return s end
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("\\n", "\n")
  s = s:gsub("&#13;", "\n"):gsub("&#10;", "\n")
  return s
end

local function _collapse_blank_lines(s)
  if not s or s == "" then return s end
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("\n%s*\n+", "\n")
  s = s:gsub("^\n+", ""):gsub("\n+$", "")
  return s
end

local function _normalize_ixml_sidecar(path)
  local data = _read_file(path)
  if not data or #data == 0 then return end
  data = data:gsub("\\n", "\n"):gsub("&#13;", "\n"):gsub("&#10;", "\n")
  data = _collapse_blank_lines(data)
  _write_file(path, data)
end

local function _shorten_output(s, maxlen)
  if not s or s == "" then return "" end
  local out = tostring(s):gsub("[\r\n]+", " "):gsub("%s+", " ")
  maxlen = tonumber(maxlen) or 300
  return (#out > maxlen) and out:sub(1, maxlen) .. "..." or out
end

-- Direct-copy mode intentionally avoids per-track metadata guessing.
-- If you need the full, already-correct Ediload split metadata, use the exact-copy APIs below.

local function _patch_track_tokens_text(s, chan_name)
  if not s or s == "" or chan_name == nil then return s end
  local t = tostring(s)
  local esc = chan_name:gsub("%%", "%%%%")
  t = t:gsub("([sS][tT][rR][kK][aA][lL][lL]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  t = t:gsub("([sS][tT][rR][kK]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  t = t:gsub("([tT][rR][kK][aA][lL][lL]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  t = t:gsub("([tT][rR][kK]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  return t
end

local function _join_track_names(tracks)
  local out = {}
  for _, tr in ipairs(tracks or {}) do
    out[#out + 1] = tostring((tr and tr.name) or "")
  end
  return table.concat(out, ",")
end

local function _patch_track_tokens_with_list(s, tracks)
  if not s or s == "" then return s end
  local list = _join_track_names(tracks)
  if list == "" then return s end
  local esc = list:gsub("%%", "%%%%")
  local t = tostring(s)
  t = t:gsub("([sS][tT][rR][kK][aA][lL][lL]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  t = t:gsub("([sS][tT][rR][kK]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  t = t:gsub("([tT][rR][kK][aA][lL][lL]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  t = t:gsub("([tT][rR][kK]%s*=%s*)[^\r\n;|]+", "%1" .. esc)
  return t
end

local function _verify_ixml_chunk(cli, wav_path, log_fn)
  local side = wav_path .. ".iXML.xml"
  _remove_file_silent(side)
  local code, out = exec_shell(('"%s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, wav_path), 20000)
  _log(log_fn, ("    iXML: verify dst -> sidecar export (code=%s)"):format(tostring(code)))
  _log(log_fn, ("    iXML: verify command output -> %s"):format(_shorten_output(out, 600)))
  if code ~= 0 then return false end
  if not _file_exists(side) then return false end
  local xml = _read_file(side) or ""
  _log(log_fn, ("    iXML: verify sidecar size = %d bytes"):format(#xml))
  if #xml == 0 then return false end
  if not xml:find("<[Bb][Ww][Ff][Xx][Mm][Ll]") and not xml:find("<[iI][Xx][Mm][Ll]") then
    return false
  end
  return true
end

local function _xml_escape_text(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;")
       :gsub("<", "&lt;")
       :gsub(">", "&gt;")
       :gsub('"', "&quot;")
       :gsub("'", "&apos;")
  return s
end

local function _parse_core_from_xml_report(xml_text)
  local function tag(name)
    local v = xml_text:match("<"..name.."%s*[^>]*>(.-)</"..name..">")
    if v then
      v = v:gsub("&lt;","<"):gsub("&gt;",">"):gsub("&amp;","&")
      v = v:gsub("\r\n","\n"):gsub("\r","\n"):gsub("\n","\\n")
      return v
    end
    return ""
  end
  return {
    Description = tag("Description"),
    Originator = tag("Originator"),
    OriginatorReference = tag("OriginatorReference"),
    OriginationDate = tag("OriginationDate"),
    OriginationTime = tag("OriginationTime"),
    IARL = tag("IARL"), IART = tag("IART"), ICMT = tag("ICMT"), ICRD = tag("ICRD"),
    INAM = tag("INAM"), ICOP = tag("ICOP"), ICMS = tag("ICMS"), IGNR = tag("IGNR"),
    ISFT = tag("ISFT"), ISBJ = tag("ISBJ"), ITCH = tag("ITCH"),
    CodingHistory = tag("CodingHistory"), UMID = tag("UMID"),
  }
end

local function _sh_quote(s)
  if s == nil then return "''" end
  return "'" .. tostring(s):gsub("'", "'\"'\"'") .. "'"
end

local function _trunc_bext_desc(s, log_fn)
  if not s then return "" end
  local bytes = {string.byte(s, 1, #s)}
  if #bytes <= 256 then return s end
  local out = {}
  for i = 1, 256 do out[i] = string.char(bytes[i]) end
  _log(log_fn, "    CORE(FLAGS): Description >256 bytes, truncated to 256")
  return table.concat(out)
end

function E.Get_Take_Source_Path(take)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end
  local p = reaper.GetMediaSourceFileName(src, "")
  return (p ~= "" and p) or nil
end

local function _get_take_source_channels(take)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end
  local nch = tonumber(reaper.GetMediaSourceNumChannels(src) or 0)
  if nch and nch > 0 then return nch end
  return nil
end

local function _guess_interleave_index_from_take(take, src_channels)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
  local cm = tonumber(reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0) or 0
  if cm >= 3 and cm <= 66 then
    local idx = math.floor(cm - 2)
    if src_channels and src_channels > 0 then
      if idx < 1 then idx = 1 end
      if idx > src_channels then idx = src_channels end
    end
    return idx
  end
  return nil
end

local function _get_track_name_from_take_source(take, target_idx)
  if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
  if not target_idx or target_idx < 1 then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end

  local function meta(key)
    local ok, val = reaper.GetMediaFileMetadata(src, key)
    if ok == 1 and val and val ~= "" then return val end
    return nil
  end

  local count = tonumber(meta("IXML:TRACK_LIST:TRACK_COUNT") or "") or 0
  if count > 0 then
    local ordered_names = {}
    local ordered_channel_index = {}
    local by_channel_index = {}
    for i = 1, count do
      local suf = (i > 1) and (":" .. i) or ""
      local idx_s = meta("IXML:TRACK_LIST:TRACK:CHANNEL_INDEX" .. suf)
      local nm = meta("IXML:TRACK_LIST:TRACK:NAME" .. suf)
      local idx = tonumber(idx_s or "")
      if nm and nm ~= "" then
        ordered_names[i] = nm
        ordered_channel_index[i] = idx
        if idx then by_channel_index[idx] = nm end
      end
    end

    if target_idx <= count then
      return ordered_names[target_idx] or "", ordered_channel_index[target_idx] or target_idx
    end
    if by_channel_index[target_idx] and by_channel_index[target_idx] ~= "" then
      return by_channel_index[target_idx], target_idx
    end
    if by_channel_index[target_idx - 1] and by_channel_index[target_idx - 1] ~= "" then
      return by_channel_index[target_idx - 1], (target_idx - 1)
    end
  end

  local trk = meta("IXML:TRK" .. tostring(target_idx))
    or meta("IXML:trk" .. tostring(target_idx))
    or meta("IXML:sTRK" .. tostring(target_idx))
  if trk and trk ~= "" then return trk, target_idx end
  return nil
end

function E.Build_Channel_Context(item, src_take, active_take)
  if not item or not src_take or not active_take then return nil end

  local src_channels = _get_take_source_channels(src_take)
    or _get_take_source_channels(active_take)
    or 1

  local idx = _guess_interleave_index_from_take(active_take, src_channels)
    or _guess_interleave_index_from_take(src_take, src_channels)
  if not idx then return nil end

  local nm, channel_index = _get_track_name_from_take_source(src_take, idx)
  if nm == nil then
    nm, channel_index = _get_track_name_from_take_source(active_take, idx)
  end

  return {
    index = idx,
    total = src_channels,
    name = nm or "",
    channel_index = idx,
  }
end

function E.Patch_iXML_For_Channel(xml, chan_ctx)
  if not xml or xml == "" or not chan_ctx then
    return xml
  end

  local target_tracks = (type(chan_ctx.target_tracks) == "table") and chan_ctx.target_tracks or nil
  if target_tracks and #target_tracks > 0 then
    local chunks = {}
    for i, tr in ipairs(target_tracks) do
      local name_xml = _xml_escape_text((tr and tr.name) or "")
      local ch_idx = tonumber((tr and tr.channel_index) or 0) or tonumber((tr and tr.interleave_index) or 0) or i
      local il_idx = tonumber((tr and tr.interleave_index) or 0) or i
      chunks[#chunks + 1] = "<TRACK><CHANNEL_INDEX>" .. tostring(ch_idx) .. "</CHANNEL_INDEX><INTERLEAVE_INDEX>" .. tostring(il_idx) .. "</INTERLEAVE_INDEX><NAME>" .. name_xml .. "</NAME><FUNCTION></FUNCTION></TRACK>"
    end
    local replacement = "<TRACK_LIST><TRACK_COUNT>" .. tostring(#target_tracks) .. "</TRACK_COUNT>" .. table.concat(chunks, "") .. "</TRACK_LIST>"
    local patched, n_track_list = xml:gsub("<TRACK_LIST%s*>.-</TRACK_LIST>", replacement, 1)
    if n_track_list == 0 then
      patched = patched:gsub("(</BWFXML>)", replacement .. "%1", 1)
      patched = patched:gsub("(</iXML>)", replacement .. "%1", 1)
    end
    return patched
  end

  local name_xml = _xml_escape_text(chan_ctx.name or "")
  local channel_index = tonumber(chan_ctx.index or 1) or 1
  if channel_index < 1 then channel_index = 1 end
  local replacement = "<TRACK_LIST><TRACK_COUNT>1</TRACK_COUNT><TRACK><CHANNEL_INDEX>" .. tostring(channel_index) .. "</CHANNEL_INDEX><INTERLEAVE_INDEX>1</INTERLEAVE_INDEX><NAME>" .. name_xml .. "</NAME><FUNCTION></FUNCTION></TRACK></TRACK_LIST>"
  local patched, n_track_list = xml:gsub("<TRACK_LIST%s*>.-</TRACK_LIST>", replacement, 1)
  if n_track_list == 0 then
    patched = patched:gsub("(</BWFXML>)", replacement .. "%1", 1)
    patched = patched:gsub("(</iXML>)", replacement .. "%1", 1)
  end

  patched = patched:gsub("(<TRKALL%s*>)(.-)(</TRKALL%s*>)", "%1" .. name_xml .. "%3", 1)
  patched = patched:gsub("(<trkall%s*>)(.-)(</trkall%s*>)", "%1" .. name_xml .. "%3", 1)
  patched = patched:gsub("<TRK[2-9]%d*%s*>.-</TRK[2-9]%d*%s*>", "")
  patched = patched:gsub("<trk[2-9]%d*%s*>.-</trk[2-9]%d*%s*>", "")

  patched = patched:gsub("(<TRK1%s*>)(.-)(</TRK1%s*>)", "%1" .. name_xml .. "%3", 1)
  patched = patched:gsub("(<trk1%s*>)(.-)(</trk1%s*>)", "%1" .. name_xml .. "%3", 1)

  return patched
end

function E.Copy_iXML_Exact(cli, src_wav, dst_wav, opts)
  opts = opts or {}
  if not cli or not _is_wav(src_wav) or not _is_wav(dst_wav) then return false end

  local src_iXML = src_wav .. ".iXML.xml"
  local dst_iXML = dst_wav .. ".iXML.xml"
  local code1, out1 = exec_shell(('"%s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, src_wav), 20000)
  _log(opts.log, ("    iXML exact: export src → sidecar (code=%s)"):format(tostring(code1)))
  _log(opts.log, ("    iXML exact: export output -> %s"):format(_shorten_output(out1, 600)))

  if not _file_exists(src_iXML) then
    _log(opts.log, "    iXML exact: source sidecar missing -> FAIL")
    return false
  end

  local x = _read_file(src_iXML) or ""
  if x == "" then
    _log(opts.log, "    iXML exact: source sidecar empty -> FAIL")
    return false
  end

  _write_file(dst_iXML, x)
  _normalize_ixml_sidecar(dst_iXML)

  local code2, out2 = exec_shell(('"%s" --in-iXML-xml --continue-errors --verbose "%s"'):format(cli, dst_wav), 20000)
  _log(opts.log, ("    iXML exact: import sidecar → dst (code=%s)"):format(tostring(code2)))
  _log(opts.log, ("    iXML exact: import output -> %s"):format(_shorten_output(out2, 600)))
  if code2 ~= 0 then
    _log(opts.log, "    iXML exact: import command failed -> FAIL")
    return false
  end

  local ok_verify = _verify_ixml_chunk(cli, dst_wav, opts.log)
  if not ok_verify then
    _log(opts.log, "    iXML exact: verification FAILED after import")
    return false
  end

  _log(opts.log, "    iXML exact: verification OK")
  return true
end

function E.Copy_iXML(cli, src_wav, dst_wav, opts)
  opts = opts or {}
  if not cli or not _is_wav(src_wav) or not _is_wav(dst_wav) then return false end

  local src_iXML = src_wav .. ".iXML.xml"
  local dst_iXML = dst_wav .. ".iXML.xml"
  local code1, out1 = exec_shell(('"%s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, src_wav), 20000)
  _log(opts.log, ("    iXML: export src → sidecar (code=%s)"):format(tostring(code1)))
  _log(opts.log, ("    iXML: export src output -> %s"):format(_shorten_output(out1, 600)))

  if not _file_exists(src_iXML) then
    _log(opts.log, "    iXML: no sidecar exported from source -> FAIL")
    return false
  end

  local x = _read_file(src_iXML) or ""
  _log(opts.log, ("    iXML: source sidecar size = %d bytes"):format(#x))
  if x == "" then
    _log(opts.log, "    iXML: source sidecar is empty -> FAIL")
    return false
  end

  if opts.chan_ctx then
    x = E.Patch_iXML_For_Channel(x, opts.chan_ctx)
    _log(opts.log, ("    iXML: strict channel patch -> %d/%d '%s'"):format(
      tonumber(opts.chan_ctx.index or 0) or 0,
      tonumber(opts.chan_ctx.total or 0) or 0,
      tostring(opts.chan_ctx.name or "")
    ))
  end
  _write_file(dst_iXML, x)

  _normalize_ixml_sidecar(dst_iXML)
  local code2, out2 = exec_shell(('"%s" --in-iXML-xml --continue-errors --verbose "%s"'):format(cli, dst_wav), 20000)
  _log(opts.log, ("    iXML: import sidecar → dst (code=%s)"):format(tostring(code2)))
  _log(opts.log, ("    iXML: import dst output -> %s"):format(_shorten_output(out2, 600)))
  if code2 ~= 0 then
    _log(opts.log, "    iXML: import command failed -> FAIL")
    if opts.cleanup ~= false then
      _remove_file_silent(src_iXML)
      _remove_file_silent(dst_iXML)
    end
    return false
  end

  local ok_verify = _verify_ixml_chunk(cli, dst_wav, opts.log)
  if not ok_verify then
    _log(opts.log, "    iXML: verification FAILED after import")
    if opts.cleanup ~= false then
      _remove_file_silent(src_iXML)
      _remove_file_silent(dst_iXML)
      _remove_file_silent(dst_wav .. ".iXML.xml")
    end
    return false
  end
  _log(opts.log, "    iXML: verification OK")

  if opts.cleanup ~= false then
    _remove_file_silent(src_iXML)
    _remove_file_silent(dst_iXML)
    _remove_file_silent(dst_wav .. ".iXML.xml")
  end
  return true
end

function E.Set_iXML_Embedder(cli, wav_path, newval)
  if not cli or not _is_wav(wav_path) then return false end
  local side = wav_path .. ".iXML.xml"
  local _export_code = select(1, exec_shell(('"%s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, wav_path), 20000))
  local xml = _read_file(side) or ""
  if xml == "" then return true end

  local patched, n = xml:gsub("(<%s*EMBEDDER%s*>)(.-)(</%s*EMBEDDER%s*>)", "%1"..tostring(newval or "BWF MetaEdit").."%3", 1)
  if n == 0 then
    if xml:find("<USER%s*>") then
      patched = xml:gsub("(<USER%s*>)", "%1<EMBEDDER>"..tostring(newval or "BWF MetaEdit").."</EMBEDDER>", 1)
    else
      patched = xml:gsub("(</BWFXML>)", "<USER><EMBEDDER>"..tostring(newval or "BWF MetaEdit").."</EMBEDDER></USER>%1", 1)
      patched = patched:gsub("(</iXML>)", "<USER><EMBEDDER>"..tostring(newval or "BWF MetaEdit").."</EMBEDDER></USER>%1", 1)
    end
  end

  _write_file(side, patched)
  _normalize_ixml_sidecar(side)
  local codeI = select(1, exec_shell(('"%s" --in-iXML-xml --continue-errors --verbose "%s"'):format(cli, wav_path), 20000))
  _remove_file_silent(side)
  return codeI == 0
end

function E.Copy_CORE(cli, src_wav, dst_wav, opts)
  opts = opts or {}
  if not cli or not _is_wav(src_wav) or not _is_wav(dst_wav) then return false end

  local codeR, outR = exec_shell(('"%s" --out-xml=- --continue-errors --verbose "%s"'):format(cli, src_wav), 30000)
  _log(opts.log, ("    CORE(FLAGS): export src (code=%s)"):format(tostring(codeR)))
  if not outR or #outR == 0 then return false end
  if codeR ~= 0 then
    _log(opts.log, "    CORE(FLAGS): export reported non-fatal warning (--continue-errors), using recovered report")
  end

  local fields = _parse_core_from_xml_report(outR)
  for k, v in pairs(fields) do
    fields[k] = _collapse_blank_lines(_normalize_newlines(v))
  end

  -- Normalize key BWF identity fields to avoid split-tool padding differences.
  fields.Originator = _trim_outer(fields.Originator)
  fields.OriginatorReference = _trim_outer(fields.OriginatorReference)
  fields.OriginationDate = _trim_outer(fields.OriginationDate)
  fields.OriginationTime = _trim_outer(fields.OriginationTime)

  if opts.chan_ctx then
    fields.ITCH = opts.chan_ctx.name or ""
    if type(opts.chan_ctx.target_tracks) == "table" and #opts.chan_ctx.target_tracks > 0 then
      fields.Description = _patch_track_tokens_with_list(fields.Description, opts.chan_ctx.target_tracks)
      fields.ICMT = _patch_track_tokens_with_list(fields.ICMT, opts.chan_ctx.target_tracks)
      fields.ISBJ = _patch_track_tokens_with_list(fields.ISBJ, opts.chan_ctx.target_tracks)
      _log(opts.log, "    CORE: preserved target track slot layout for sTRK/sTRKALL")
    else
      fields.Description = _patch_track_tokens_text(fields.Description, opts.chan_ctx.name or "")
      fields.ICMT = _patch_track_tokens_text(fields.ICMT, opts.chan_ctx.name or "")
      fields.ISBJ = _patch_track_tokens_text(fields.ISBJ, opts.chan_ctx.name or "")
    end
    _log(opts.log, ("    CORE: strict channel ITCH -> %s"):format(tostring(opts.chan_ctx.name or "(empty)")))
    _log(opts.log, "    CORE: normalized sTRK/sTRKALL tokens for mono channel")
  end
  if type(opts.override_fields) == "table" then
    for k, v in pairs(opts.override_fields) do fields[k] = v end
  end

  fields.Description = _trunc_bext_desc(fields.Description, opts.log)

  local field_filter = opts.core_fields
  if type(field_filter) == "table" then
    for key in pairs(fields) do
      if not field_filter[key] then fields[key] = "" end
    end
  end

  local flags = {}
  local function add(k, v)
    if v and v ~= "" then
      if k == "Originator" or k == "OriginatorReference" or k == "OriginationDate" or k == "OriginationTime" then
        v = _trim_outer(v)
      end
      if v ~= "" then flags[#flags+1] = ('--%s=%s'):format(k, _sh_quote(v)) end
    end
  end
  local function add_info(k, v)
    if v and v ~= "" then
      if v:find("\n", 1, true) or v:find("\r", 1, true) then
        v = v:gsub("\r\n", "\n"):gsub("\r", "\n")
        local parts = {}
        for ln in v:gmatch("[^\n]+") do
          local cleaned = ln:gsub("^%s+", ""):gsub("%s+$", "")
          if cleaned ~= "" then parts[#parts+1] = cleaned end
        end
        v = table.concat(parts, " · ")
      end
      v = v:gsub('"', '\\"')
      flags[#flags+1] = ('--%s="%s"'):format(k, v)
    end
  end

  add("Description", fields.Description)
  add_info("IARL", fields.IARL)
  add_info("IART", fields.IART)
  add_info("ICMT", fields.ICMT)
  add_info("ICRD", fields.ICRD)
  add_info("INAM", fields.INAM)
  add_info("ICOP", fields.ICOP)
  add_info("ICMS", fields.ICMS)
  add_info("IGNR", fields.IGNR)
  add_info("ISFT", fields.ISFT)
  add_info("ISBJ", fields.ISBJ)
  add_info("ITCH", fields.ITCH)
  add("Originator", fields.Originator)
  add("OriginatorReference", fields.OriginatorReference)
  add("OriginationDate", fields.OriginationDate)
  add("OriginationTime", fields.OriginationTime)
  add("UMID", fields.UMID)

  if #flags == 0 then
    _log(opts.log, "    CORE(FLAGS): nothing to write -> SKIP")
    return true
  end

  local cmd = ('"%s" %s "%s"'):format(cli, table.concat(flags, " "), dst_wav)
  local codeW = select(1, exec_shell(cmd, 40000))
  _log(opts.log, ("    CORE(FLAGS): write dst (code=%s)"):format(tostring(codeW)))
  return codeW == 0
end

function E.Analyze_Metadata_Fields(cli, src_wav, dst_wav, opts)
  opts = opts or {}
  local function read_core(path)
    local code, output = exec_shell(('"%s" --out-xml=- --continue-errors "%s"'):format(cli, path), 30000)
    if not output or output == "" then return nil, code end
    return _parse_core_from_xml_report(output), code
  end
  local source, source_code = read_core(src_wav)
  local target, target_code = read_core(dst_wav)
  local result = {
    source = source or {}, target = target or {}, missing = {}, different = {}, same = {},
    source_code = source_code, target_code = target_code,
  }
  local function read_ixml(path)
    local sidecar = path .. ".iXML.xml"
    _remove_file_silent(sidecar)
    local code = select(1, exec_shell(('"%s" --out-iXML-xml --continue-errors "%s"'):format(cli, path), 30000))
    local data = _read_file(sidecar) or ""
    _remove_file_silent(sidecar)
    return code, data
  end
  local fields = {
    "Description", "Originator", "OriginatorReference", "OriginationDate", "OriginationTime",
    "IARL", "IART", "ICMT", "ICRD", "INAM", "ICOP", "ICMS", "IGNR", "ISFT", "ISBJ", "ITCH",
    "CodingHistory", "UMID",
  }
  for _, key in ipairs(fields) do
    local source_value = _normalize_newlines(source and source[key] or "") or ""
    local target_value = _normalize_newlines(target and target[key] or "") or ""
    result.source[key], result.target[key] = source_value, target_value
    if source_value ~= "" and target_value == "" then
      result.missing[key] = { source = source_value, target = target_value }
    elseif source_value ~= target_value then
      result.different[key] = { source = source_value, target = target_value }
    else
      result.same[key] = source_value
    end
  end
  result.source_time_reference = select(1, E.TR_Read(cli, src_wav))
  result.target_time_reference = select(1, E.TR_Read(cli, dst_wav))
  if result.source_time_reference and (not result.target_time_reference or result.target_time_reference == 0) then
    result.missing.TimeReference = { source = result.source_time_reference, target = result.target_time_reference }
  elseif result.source_time_reference and result.source_time_reference ~= result.target_time_reference then
    result.different.TimeReference = { source = result.source_time_reference, target = result.target_time_reference }
  end
  local source_ixml_code, source_ixml = read_ixml(src_wav)
  local target_ixml_code, target_ixml = read_ixml(dst_wav)
  result.source_ixml, result.target_ixml = source_ixml, target_ixml
  result.ixml = { source_code = source_ixml_code, target_code = target_ixml_code }
  if source_ixml ~= "" and target_ixml == "" then
    result.missing.iXML = { source = source_ixml, target = target_ixml }
  elseif source_ixml ~= target_ixml then
    result.different.iXML = { source = source_ixml, target = target_ixml }
  else
    result.same.iXML = source_ixml
  end
  return result
end

function E.Copy_Metadata(cli, src_wav, dst_wav, opts)
  opts = opts or {}
  local res = {
    ixml = false,
    core = false,
    tr = false,
    tr_skipped = false,
    embedder = false,
    ok = false,
  }

  if opts.copy_ixml == false then
    res.ixml = true
    res.ixml_skipped = true
  else
    if opts.direct_copy then
      res.ixml = E.Copy_iXML_Exact(cli, src_wav, dst_wav, opts)
    else
      res.ixml = E.Copy_iXML(cli, src_wav, dst_wav, opts)
    end
  end
  if opts.set_embedder ~= false then
    res.embedder = E.Set_iXML_Embedder(cli, dst_wav, opts.embedder_name or "BWF MetaEdit")
  else
    res.embedder = true
  end
  res.core = E.Copy_CORE(cli, src_wav, dst_wav, opts)

  if opts.copy_tr == false then
    res.tr = true
    res.tr_skipped = true
  else
    local tr_src = select(1, E.TR_Read(cli, src_wav))
    _log(opts.log, ("    TAKE1 TR read  : %s"):format(tostring(tr_src)))
    if tr_src then
      local okW, codeW = E.TR_Write(cli, dst_wav, tr_src)
      _log(opts.log, ("    WRITE dst TR   : code=%s"):format(tostring(codeW)))
      local vr = select(1, E.TR_Read(cli, dst_wav))
      _log(opts.log, ("    VERIFY dst TR  : %s"):format(tostring(vr)))
      res.tr = (okW and vr == tr_src)
      _log(opts.log, ("    TR result      : %s"):format(res.tr and "OK" or "FAIL"))
    else
      res.tr = true
      res.tr_skipped = true
      _log(opts.log, "    TR result      : SKIP (cannot read src TR)")
    end
  end

  res.ok = res.ixml and res.core and res.tr and res.embedder
  return res
end

function E.Copy_Metadata_Exact(cli, src_wav, dst_wav, opts)
  opts = opts or {}
  opts.direct_copy = true
  opts.chan_ctx = nil
  opts.channel_aware = false
  return E.Copy_Metadata(cli, src_wav, dst_wav, opts)
end

function E.Copy_Take1_To_Active(item, opts)
  opts = opts or {}
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then
    return false, { reason = "invalid item" }
  end

  local src_take = opts.src_take or reaper.GetMediaItemTake(item, 0)
  local dst_take = opts.dst_take or reaper.GetActiveTake(item)
  if not src_take then return false, { reason = "no Take 1" } end
  if not dst_take then return false, { reason = "no active take" } end
  if src_take == dst_take then return false, { reason = "active == Take 1" } end

  local src_wav = opts.src_wav or E.Get_Take_Source_Path(src_take)
  local dst_wav = opts.dst_wav or E.Get_Take_Source_Path(dst_take)
  if not _is_wav(src_wav) then return false, { reason = "src is not WAV", src = src_wav } end
  if not _is_wav(dst_wav) then return false, { reason = "dst is not WAV", dst = dst_wav } end
  if not _file_exists(src_wav) then return false, { reason = "src file not found", src = src_wav } end
  if not _file_exists(dst_wav) then return false, { reason = "dst file not found", dst = dst_wav } end

  local cli = opts.cli or E.CLI_Resolve()
  if not cli then return false, { reason = "missing bwfmetaedit CLI" } end

  local chan_ctx = opts.chan_ctx
  if chan_ctx == nil and opts.channel_aware ~= false then
    chan_ctx = E.Build_Channel_Context(item, src_take, dst_take)
  end
  if chan_ctx then
    _log(opts.log, ("    CH mode        : %d/%d -> %s"):format(
      tonumber(chan_ctx.index or 0) or 0,
      tonumber(chan_ctx.total or 0) or 0,
      tostring(chan_ctx.name or "")
    ))
    _log(opts.log, ("    CH iXML index  : %s"):format(tostring(chan_ctx.channel_index or "(nil)")))
  else
    _log(opts.log, "    CH mode        : (no mono-of-N context; keep full metadata)")
  end

  local res = E.Copy_Metadata(cli, src_wav, dst_wav, {
    chan_ctx = chan_ctx,
    copy_tr = opts.copy_tr,
    set_embedder = opts.set_embedder,
    embedder_name = opts.embedder_name,
    override_fields = opts.override_fields,
    cleanup = opts.cleanup,
    log = opts.log,
  })
  res.src_take = src_take
  res.dst_take = dst_take
  res.src_wav = src_wav
  res.dst_wav = dst_wav
  res.chan_ctx = chan_ctx
  return res.ok, res
end



-- ===== UMID writer (explicit CLI path) =====
-- Usage: E.write_bext_umid(cli, wav_path, umid_hex)
function E.write_bext_umid(cli, wav_path, umid_hex)
  local G = E._G or rawget(_G, "G")
  local h = tostring(umid_hex or "")

  -- Aggressive clean → keep only 0-9A-F, force uppercase
  h = h:gsub("[^0-9A-Fa-f]", ""):upper()
  if G and G.normalize_umid then h = G.normalize_umid(h) end

  if not h:match("^[0-9A-F]+$") or #h ~= 64 then
    return false, "UMID must be 64 hex chars"
  end
  if not cli or cli == "" then
    return false, "Missing bwfmetaedit CLI path"
  end

  -- Official BWF MetaEdit syntax: --UMID=<hex>
  local cmd = ('"%s" --UMID=%s "%s"'):format(cli, h, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return (code == 0), code, out, cmd
end


-- ===== Optional: refresh media item to force REAPER reload =====
function E.refresh_media_item_take(take)
  if not take then return end
  local item = reaper.GetMediaItemTake_Item(take)
  if item then
    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC",
      reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")) -- poke
    reaper.UpdateItemInProject(item)
  end
end

-- ===== TimeReference helpers & API (non-breaking add for 0.2.4) =====

-- keep it ultra-safe: reuse existing IS_WIN/sh_wrap/exec_shell from this file

-- tiny epsilon to stabilize floor rounding
local _QUANT_EPS = 1e-9

-- seconds -> integer samples (floor + epsilon)
function E.SecToSamples(sr, seconds)
  return math.floor((seconds or 0) * (sr or 48000) + _QUANT_EPS)
end

-- resolve bwfmetaedit path; persist like TC tool does
function E.CLI_Resolve()
  local R = reaper
  local EXT_NS, EXT_KEY = "hsuanice_TCTools", "BWFMetaEditPath"

  local function ok_cli(p)
    if not p or p=="" then return false end
    -- Use the same safe quoting style as TR_Read/TR_Write
    local cmd = ('"%s" --Version'):format(p)
    local code = select(1, exec_shell(cmd, 3000))
    return code == 0
  end


  local saved = R.GetExtState(EXT_NS, EXT_KEY)
  if saved ~= "" and ok_cli(saved) then return saved end

  local cands
  if IS_WIN then
    cands = {
      [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]],
      [[C:\Program Files (x86)\BWF MetaEdit\bwfmetaedit.exe]],
      "bwfmetaedit",
    }
  else
    -- Prefer Apple Silicon Homebrew path first
    cands = {
      "/opt/homebrew/bin/bwfmetaedit",
      "/usr/local/bin/bwfmetaedit",
      "bwfmetaedit"
    }
  end

  for _,p in ipairs(cands) do
    if ok_cli(p) then
      R.SetExtState(EXT_NS, EXT_KEY, p, true)
      return p
    end
  end

  local hint = IS_WIN and [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]] or "/opt/homebrew/bin/bwfmetaedit"
  local ok, picked = R.GetUserFileNameForRead(0, hint, 'Locate "bwfmetaedit" executable (Cancel to abort)')
  if ok and ok_cli(picked) then
    R.SetExtState(EXT_NS, EXT_KEY, picked, true)
    return picked
  end
  return nil
end

-- read BWF TimeReference (samples) using --out-xml=-
function E.TR_Read(cli, wav_path)
  if not cli or not _is_wav(wav_path) then return nil, -1, "" end
  local cmd = ('"%s" --out-xml=- --continue-errors "%s"'):format(cli, wav_path)
  local code, out = exec_shell(cmd, 20000)
  local tr = tonumber(out:match("<TimeReference>(%d+)</TimeReference>") or "")
  return tr, code, out
end

-- write BWF TimeReference (samples) using --TimeReference=
--
-- @param originator (optional) when set, also writes --Originator= in the
--   SAME command. Needed because bwfmetaedit prunes the whole bext chunk
--   right back out whenever every field in it would end up at its default
--   (empty/zero) value — confirmed by direct testing: writing
--   --TimeReference=0 alone to a file with no pre-existing bext chunk is a
--   silent no-op (bext never gets created), and even writing a non-zero
--   value first then writing 0 right after deletes the chunk again, since
--   the resulting record (TR=0, everything else blank) still reads as
--   "all default." Any other non-empty bext field keeps the chunk from
--   being pruned, so a brand-new file (e.g. CLB's generated reference
--   media, which legitimately needs TimeReference=0 since its real
--   position data lives entirely in each item's own D_STARTOFFS) must pass
--   one here to actually persist TR=0.
function E.TR_Write(cli, wav_path, tr_samples, originator)
  if not cli or not _is_wav(wav_path) then return false, -1, "" end
  local tr = tonumber(tr_samples or 0) or 0
  if tr < 0 then tr = 0 end
  local extra = ""
  if originator and originator ~= "" then
    extra = (' --Originator="%s"'):format(originator)
  end
  local cmd = ('"%s" --TimeReference=%d%s "%s"'):format(cli, tr, extra, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return (code == 0), code, out
end

--- Writes a caller-supplied iXML document straight into a WAV's iXML
--- chunk — unlike Copy_iXML/Copy_iXML_Exact (which only ever COPY iXML
--- from an existing source WAV), this takes raw XML text the caller
--- already built itself (e.g. a fresh <BWFXML> document for a brand-new
--- file with no source to copy from — see
--- hsuanice_Conform List Browser - CLB.lua's CLB.generate_reference_media).
--- Writes via the same sidecar import mechanism (--in-iXML=) bwfmetaedit
--- itself uses, verifies the import actually took by reading the chunk
--- back and comparing size, then cleans up the sidecar either way.
--- @param cli string        bwfmetaedit path (see CLI_Resolve)
--- @param wav_path string   destination WAV (must already exist)
--- @param xml_text string   a complete iXML document, e.g. "<BWFXML>...</BWFXML>"
--- @return boolean ok, number code, string out
function E.Write_iXML_Raw(cli, wav_path, xml_text)
  if not cli or not _is_wav(wav_path) then return false, -1, "" end
  if not xml_text or xml_text == "" then return false, -1, "empty xml_text" end

  local side = wav_path .. ".iXML.xml"
  _write_file(side, xml_text)
  _normalize_ixml_sidecar(side)

  local code, out = exec_shell(('"%s" --in-iXML="%s" --continue-errors --verbose "%s"')
    :format(cli, side, wav_path), 20000)
  _remove_file_silent(side)
  if code ~= 0 then return false, code, out end

  local ok_verify = _verify_ixml_chunk(cli, wav_path, nil)
  _remove_file_silent(wav_path .. ".iXML.xml")  -- left behind by the verify export
  if not ok_verify then return false, code, out .. "\n(verification failed)" end

  return true, code, out
end

-- compute TR for active take from previous take (handle-aware, cross-SR safe)
function E.TR_PrevToActive(prev_take, active_take)
  if not (prev_take and active_take) then return 0 end

  local function take_sr(tk)
    local src = reaper.GetMediaItemTake_Source(tk)
    local sr = src and reaper.GetMediaSourceSampleRate(src) or 0
    if not sr or sr <= 0 then
      sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 0
    end
    return (sr and sr > 0) and sr or 48000
  end
  local function srcstart_sec(tk)
    return reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0.0
  end

  local src_sr = take_sr(prev_take)
  local dst_sr = take_sr(active_take)
  local src_off = srcstart_sec(prev_take)
  local dst_off = srcstart_sec(active_take)

  -- read previous file TR
  local prev_src = reaper.GetMediaItemTake_Source(prev_take)
  local prev_path = prev_src and reaper.GetMediaSourceFileName(prev_src, "") or ""
  local cli = E.CLI_Resolve()
  local prev_tr_samples = 0
  if cli and _is_wav(prev_path) then
    local tr, code = E.TR_Read(cli, prev_path)
    if code == 0 and tr then prev_tr_samples = tr end
  end

  -- seconds-domain math (same policy as TC tool), then quantize
  local prev_tr_sec = (prev_tr_samples or 0) / src_sr
  local dst_tr_sec  = (prev_tr_sec + src_off) - dst_off
  if dst_tr_sec < 0 then dst_tr_sec = 0 end
  return E.SecToSamples(dst_sr, dst_tr_sec)
end

-- compute TR from item start position for active take
function E.TR_FromItemStart(active_take, proj_pos)
  if not active_take then return 0 end
  local function take_sr(tk)
    local src = reaper.GetMediaItemTake_Source(tk)
    local sr = src and reaper.GetMediaSourceSampleRate(src) or 0
    if not sr or sr <= 0 then
      sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 0
    end
    return (sr and sr > 0) and sr or 48000
  end
  local dst_sr = take_sr(active_take)
  local dst_off = reaper.GetMediaItemTakeInfo_Value(active_take, "D_STARTOFFS") or 0.0
  local sec = (proj_pos or 0) - dst_off
  if sec < 0 then sec = 0 end
  return E.SecToSamples(dst_sr, sec)
end

-- batch refresh: offline -> online -> rebuild peaks (items or takes)
function E.Refresh_Items(t)
  if type(t) ~= "table" or #t == 0 then return end
  local R = reaper
  local seen, items = {}, {}
  for _,obj in ipairs(t) do
    local it = obj
    if R.ValidatePtr2(0, obj, "MediaItem_Take*") then
      it = R.GetMediaItemTake_Item(obj)
    end
    if R.ValidatePtr2(0, it, "MediaItem*") then
      local key = tostring(it)
      if not seen[key] then seen[key] = true; items[#items+1] = it end
    end
  end
  if #items == 0 then return end
  R.SelectAllMediaItems(0, false)
  for _,it in ipairs(items) do R.SetMediaItemSelected(it, true) end
  R.UpdateArrange()
  R.Main_OnCommand(42356, 0) -- Toggle force media offline (go offline)
  R.Main_OnCommand(42356, 0) -- Toggle force media offline (back online)
  --R.Main_OnCommand(40441, 0) -- Rebuild peaks
end


return E