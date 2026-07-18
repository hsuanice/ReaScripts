--[[
@description Metadata Embed - BWF MetaEdit helpers
@version 260718.1728
@author hsuanice
@noindex
@about
  Helpers to call BWF MetaEdit safely:
  - Shell quoting
  - Normalize iXML sidecar newline
  - Copy iXML/core, 
  read/write TimeReference
  - Post-embed refresh (offline->online, rebuild peaks)

@changelog
  260718.1728 - Synced channel-aware APIs with production fixes from Embed script
    - Build_Channel_Context now prefers TRACK_LIST slot order for interleave mapping and returns channel_index.
    - Copy_iXML now validates post-import iXML by re-exporting destination sidecar.
    - Missing source iXML sidecar is now treated as FAIL (not success).
    - Patch_iXML_For_Channel preserves non-channel iXML blocks and writes channel_index in TRACK_LIST.
    - Copy_CORE now normalizes sTRK/sTRKALL textual tokens for mono channel metadata consistency.
    - Added richer command output logging for export/import/verify operations.

  260711.2215 - Added reusable channel-aware metadata copy APIs
    - Added Build_Channel_Context() for mono-of-N channel resolution from I_CHANMODE and source TRACK_LIST.
    - Added Copy_iXML(), Copy_CORE(), Set_iXML_Embedder(), and Copy_Metadata() APIs.
    - Added Copy_Take1_To_Active() as a workflow-friendly entry point for render/glue pipelines.
    - Purpose: let explode/render scripts reuse the same metadata re-embed logic.

  0.3.0 (2025-10-30) - Initial Public Beta Release
    BWF MetaEdit helpers library featuring:
    - Shell quoting for safe CLI execution
    - iXML sidecar normalization
    - TimeReference read/write operations
    - Post-embed refresh (offline->online, rebuild peaks)
    - Integration with RGWH Core for BWF TimeReference embed

  Internal Build v251010_0037
    - Rationale: Refresh_Items already does offline->online->rebuild peaks.
    - Prevent redundant peak rebuild (40441) after every single item refresh.

  v250926_2018 (2025-09-26)
    - Change: Refresh_Items now uses 42356 (Toggle force media offline) twice (offline→online), then 40441 (Rebuild peaks), to force immediate BWF header (TimeReference) reload.
    - Rationale: 40440/40439 were insufficient in some cases after render with newly embedded TC.

  v0.3.0 (2025-09-25)
    - Added: CLI_Resolve() — resolve & persist BWF MetaEdit path
      (ExtState: hsuanice_TCTools/BWFMetaEditPath; Apple Silicon default
       /opt/homebrew/bin/bwfmetaedit is tried first).
    - Added: TR_Read(), TR_Write() — read/write BWF TimeReference (samples)
      via --out-xml=- / --TimeReference= with safe quoting (exec_shell).
    - Added: SecToSamples() — floor+epsilon sample quantization to prevent +1 jitter.
    - Added: TR_PrevToActive(), TR_FromItemStart() — handle-aware TC math using
      SrcStart (D_STARTOFFS) and cross-SR safety; negative results clamped to 0.
    - Added: Refresh_Items() — batch offline→online→rebuild peaks for items/takes.
    - Kept: write_bext_umid(), refresh_media_item_take(), shell helpers (unchanged).
    - Notes: TC/TimeReference math here is the single source of truth; RGWH and tools
      should call this library. Backward-compatible insertion; UMID workflows unaffected.


  v0.2.4 (2025-09-12)
    - Changed: E.write_bext_umid() now returns the actual command string
      used for execution, in addition to (ok, code, out).
      * Return signature: ok, code, out, cmd
      * cmd is the fully formatted bwfmetaedit command.
    - Purpose: allows calling tools to log the exact command
      instead of reconstructing it, avoiding stale or incorrect flags.
    - No change to write logic (still uses only --UMID=).
    - Maintains compatibility with v0.2.3 behavior if cmd return is ignored.

  v0.2.2 (2025-09-12)
    - Improved: E.write_bext_umid() now aggressively cleans input
      before validation:
        * Strips all non-hex characters.
        * Forces uppercase to ensure consistent 64 hex chars.
    - Safer: Prevents hidden characters or dash-separated UMIDs
      from being rejected incorrectly.
    - No change to CLI execution or return values.
    - Compatible with v0.2.1 calling convention
      (cli_path, wav_path, umid_hex).
  v0.2.1 (2025-09-12)
    - Changed: E.write_bext_umid() now requires an explicit bwfmetaedit CLI path
      and uses ExecProcess (non-blocking) instead of os.execute.
      * Usage: E.write_bext_umid(cli_path, wav_path, umid_hex)
      * CLI path can be resolved via the same logic as BWF TimeReference tool.
    - Improved: sh_wrap() and exec_shell() helpers added (consistent with TR tool).
    - Notes:
      * Only writes to BWF bext:UMID; iXML UMID is left to recorders.
      * Requires BWF MetaEdit installed and accessible (path must be provided).
    - No breaking changes besides function signature update.
]]

local E = {}
E.VERSION = "260718.1728"

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

local function _patch_track_tokens_text(s, chan_name)
  if not s or s == "" or not chan_name or chan_name == "" then return s end
  local t = tostring(s)
  local esc = chan_name:gsub("%%", "%%%%")
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

    if ordered_names[target_idx] and ordered_names[target_idx] ~= "" then
      return ordered_names[target_idx], ordered_channel_index[target_idx]
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
  if not nm or nm == "" then
    nm, channel_index = _get_track_name_from_take_source(active_take, idx)
  end
  if not nm or nm == "" then return nil end

  return {
    index = idx,
    total = src_channels,
    name = nm,
    channel_index = tonumber(channel_index or 0) or idx,
  }
end

function E.Patch_iXML_For_Channel(xml, chan_ctx)
  if not xml or xml == "" or not chan_ctx or not chan_ctx.name or chan_ctx.name == "" then
    return xml
  end

  local name_xml = _xml_escape_text(chan_ctx.name)
  local channel_index = tonumber(chan_ctx.channel_index or 0) or tonumber(chan_ctx.index or 1) or 1
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

  if opts.chan_ctx and opts.chan_ctx.name and opts.chan_ctx.name ~= "" then
    x = E.Patch_iXML_For_Channel(x, opts.chan_ctx)
    _log(opts.log, ("    iXML: channel-aware patch -> %d/%d '%s'"):format(
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
  if codeR ~= 0 or not outR or #outR == 0 then return false end

  local fields = _parse_core_from_xml_report(outR)
  for k, v in pairs(fields) do
    fields[k] = _collapse_blank_lines(_normalize_newlines(v))
  end

  if opts.chan_ctx and opts.chan_ctx.name and opts.chan_ctx.name ~= "" then
    fields.ITCH = opts.chan_ctx.name
    fields.Description = _patch_track_tokens_text(fields.Description, opts.chan_ctx.name)
    fields.ICMT = _patch_track_tokens_text(fields.ICMT, opts.chan_ctx.name)
    fields.ISBJ = _patch_track_tokens_text(fields.ISBJ, opts.chan_ctx.name)
    _log(opts.log, ("    CORE: channel-aware ITCH -> %s"):format(tostring(opts.chan_ctx.name)))
    _log(opts.log, "    CORE: normalized sTRK/sTRKALL tokens for mono channel")
  end
  if type(opts.override_fields) == "table" then
    for k, v in pairs(opts.override_fields) do fields[k] = v end
  end

  fields.Description = _trunc_bext_desc(fields.Description, opts.log)

  local flags = {}
  local function add(k, v)
    if v and v ~= "" then flags[#flags+1] = ('--%s=%s'):format(k, _sh_quote(v)) end
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

  res.ixml = E.Copy_iXML(cli, src_wav, dst_wav, opts)
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
  local cmd = ('"%s" --out-xml=- "%s"'):format(cli, wav_path)
  local code, out = exec_shell(cmd, 20000)
  local tr = tonumber(out:match("<TimeReference>(%d+)</TimeReference>") or "")
  return tr, code, out
end

-- write BWF TimeReference (samples) using --TimeReference=
function E.TR_Write(cli, wav_path, tr_samples)
  if not cli or not _is_wav(wav_path) then return false, -1, "" end
  local tr = tonumber(tr_samples or 0) or 0
  if tr < 0 then tr = 0 end
  local cmd = ('"%s" --TimeReference=%d "%s"'):format(cli, tr, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return (code == 0), code, out
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
