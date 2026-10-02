--[[
@description Metadata Read (reader / normalizer / tokens)
@version 0.3.11
@author hsuanice
@noindex
@about
  Read-only metadata utilities for REAPER items:
  - Unwrap SECTION to real parent source
  - Read iXML TRACK_LIST (Wave Agent style)
  - Fallback parse sTRK#=Name from BWF/Description (EdiLoad split)
  - Interleave index ↔ recorder channel mapping
  - Token expansion for rename/export ($trk/$trkN/$trkall, ${interleave}, ${chnum}, ...)

  Shared with the Rename scripts (2026-09-11):
  - "Rename Active Take from File Metadata.lua" and "Rename Source File from
    Metadata.lua" (Beta Testing folder) used to keep their own local copies of
    the $trk/$trkN/$trkall/${interleave}/${chnum}/${counter:N}/
    ${srcbaseprefix:N}/${srcbasesuffix:N} token logic instead of calling into
    this library. Both scripts now delegate those tokens to M.expand()
    directly, and $trk specifically calls M.resolve_trk_name() — so this file
    is the single place to fix or extend that logic. Two tokens stay local to
    the Rename scripts on purpose ($baseindex/$baseidx, $overlapindex/
    $rangeindex): they depend on the current multi-item selection/grouping
    state in that UI, which this read-only metadata library has no concept of.
  - M.resolve_trk_name() prefers fields.meta_trk_name (the already-resolved
    single-channel name that survives the shared Metadata.cache round-trip)
    before falling back to reconstructing the name from TRK#= pairs in the
    description text — needed because some recorders (e.g. Cantar/Aaton)
    don't embed per-channel TRK#= in the description, so the old
    reconstruction alone came back empty on a cache hit. $trk inside
    M.expand() now calls the same helper for its single-name case (its
    Pro-Tools-style "no explicit interleave → full track list" poly branch
    is unchanged).

@changelog
  v0.3.11 (2026-10-02)
    - Fixed: a channel whose TRACK_LIST entry exists but has an empty name now
      resolves to an empty track name again, instead of borrowing the first
      non-empty name in the list. M.resolve_trk_name() (added in v0.3.10)
      ended with an unconditional "first non-empty name" fallback, which
      undid the v0.3.9 fix: on Cantar polys that record every channel even
      when unused (2026-01 "FISHTOWN" cards), channels 3-10 — empty in
      TRACK_LIST — all read as "CMIT 5U" ($trk, Meta Trk Name in Item List
      Browser/Editor, Reorder Monitor). The first-non-empty fallback now only
      applies when the file has no TRACK_LIST at all; a file with one describes
      all of its channels, so an empty or missing entry (also in the
      compressed AATON lists REAPER can expose) means "no name".
    - Cached names written by the old behaviour are discarded by Metadata
      Cache 261002 (CACHE_VERSION 2.3).

  v0.3.10 (2026-09-11)
    - Added: M.resolve_trk_name(fields, sanitize) — single-channel track name
      resolver (meta_trk_name-first, falls back to interleave-list
      reconstruction), factored out of $trk's single-name path.
    - Fixed: $trk (single-name path) now prefers fields.meta_trk_name before
      reconstructing from TRK#= pairs in the description, fixing empty $trk
      after a Metadata.cache hit for recorders that don't embed per-channel
      TRK#= in the description (e.g. Cantar/Aaton). The poly "no explicit
      interleave → full track list" branch is unchanged.
    - Consolidated: "Rename Active Take from File Metadata.lua" and "Rename
      Source File from Metadata.lua" no longer keep local copies of
      $trk/$trkN/$trkall/$interleave/$chnum/$counter:N/$srcbaseprefix:N/
      $srcbasesuffix:N — both now delegate to this library.

  v0.3.9 (2026-08-24)
    - Fixed: explicit interleave slots with empty TRACK_LIST names no longer
      fall back to the first non-empty name.
    - Fixed: recorder channel number no longer remaps via compacted AATON
      ACTIVE order (uses TRACK_LIST interleave->channel mapping first).

  v0.3.8 (2026-08-24)
    - Added canonical TRACK_LIST reader via BWF MetaEdit XML output.
    - Multichannel files now prefer CLI TRACK_LIST for stable cross-recorder parsing.
    - REAPER metadata keys remain as fallback when CLI is unavailable.

  v0.3.7 (2026-08-24)
    - Added recorder-family aware mapping policy (AATON / Sound Devices / Sonosax / generic).
    - AATON ACTIVE-slot remap now applies only to AATON-family files.
    - Sound Devices and Sonosax stay on strict TRACK_LIST index mapping.

  v0.3.6 (2026-08-24)
    - Enforced deterministic interleave mapping priority:
      TRACK_LIST.INTERLEAVE_INDEX first, no compressed-slot fallback.
    - Only falls back to sequential names when interleave indexes are absent.

  v0.3.5 (2026-08-24)
    - Fixed: interleave track-name map now uses AATON ACTIVE slot mapping
      when available and unambiguous.
    - Prevents compressed TRACK_LIST names from shifting MIX L/R to wrong slots.

  v0.3.4 (2026-08-24)
    - Fixed: recorder-channel detection for exploded poly items can use
      AATON ACTIVE slot mapping instead of assuming interleave == channel.
    - Preserves previous behavior when ACTIVE metadata is unavailable.

  v0.3.3 (2026-08-24)
    - Fixed: TRACK_LIST parsing now prefers full IXML XML chunk before per-key reads.
    - Fixed: preserves empty TRACK_LIST slots so interleave/channel mapping does not shift.
    - Improved: channel mapping remains stable for AATON-style poly metadata with sparse names.

  v0.3.2 (2026-07-18)
    - Changed: $trk now follows Pro Tools-like display logic.
      * Poly context (no explicit mono-of-N interleave): return full track list (same as $trkall).
      * Mono/specific-channel context: return single resolved track name.
    - Added __has_explicit_interleave flag from I_CHANMODE for safer display decisions.

  v0.3.1 (2026-07-18)
    - Fixed: mono rendered files now resolve $trk from iXML TRACK_LIST first.
    - Improved: TRACK_LIST parsing now stores channel_index + interleave_index.
    - Improved: interleave name list prefers iXML INTERLEAVE_INDEX mapping.
    - Fixed: trk_name_and_channel() no longer returns empty due placeholder list.
    - Behavior: poly keeps multi-track visibility; mono/specific-channel resolves to single track name.

  v0.3.0 (2025-09-12)
    - Added: UMID (SMPTE ID) ingestion from BWF metadata.
      * Reads BWF:UMID (or UMID) via REAPER GetMediaFileMetadata.
      * Normalizes to strict 64-hex uppercase.
    - Added tokens: ${umid} (64-hex uppercase) and ${umid_pt}
      (Pro Tools style 26-6-16-12-4, lowercase with dashes).
    - UI/Fields: UMID values are included in the normalized field map
      returned by collect_item_fields(), so they are available to all
      rename/monitor/sort consumers without additional wiring.
    - Notes: No CLI dependency; if REAPER does not expose BWF:UMID on a
      given build, tokens will be empty (future optional CLI fallback planned).
  v0.2.1 (2025-09-01)
    - Quality & robustness (no breaking changes from 0.2.0):
      * Token engine polish: consistent handling for ${trk}/${trkN}/${trkall},
        ${interleave}/${chnum} (with aliases ${interum}/${channelnum});
        safer UTF-8 slice helpers for prefix/suffix tokens.
      * BWF Description normalization: more tolerant key mirroring
        (dXXXX/sXXXX → XXXX; accepts upper/lower mixed cases).
      * Diagnostics: M.compute_interleave_diag() more defensive when iXML/TRK
        data is sparse.
      * Module hygiene: ensured clean header and explicit `return M`.
  v0.2.0 (2025-09-01)
    - Integrated token engine and diagnostics:
      * Added M.expand() and M.empty_tokens_in_template():
        - Supports $trk / $trkN / $trkall
        - Supports ${interleave} / ${chnum} (from I_CHANMODE and TRK# mapping)
        - Supports ${counter:N}, ${srcbaseprefix:N}, ${srcbasesuffix:N}
      * Added UTF-8-safe substring helpers (used by prefix/suffix tokens).
      * Added M.compute_interleave_diag(fields, item) to expose index/total/name/all.
    - Field normalization:
      * M.collect_item_fields() now returns srcpath/srcfile/srcbase/srcext/srcdir,
        samplerate/channels, __trk_table, __chan_index, __trk_name, etc.
      * BWF/Description mirrors (dXXXX/sXXXX) are normalized to XXXX (both upper/lower keys).
      * Automatically populates TRK# table (trk1..trk64) for tokens/mapping.
    - Interleave mapping is more robust:
      * M.guess_interleave_index() clamps to 1..N (N derived from source channel count).
      * M.resolve_trk_by_interleave() prefers iXML TRACK_LIST; falls back to sTRK# order;
        if neither is present, returns the first non-empty name.
    - Performance:
      * Retains run-level metadata cache (M.begin_batch/M.end_batch) to avoid redundant I/O.
    - Compatibility:
      * Metadata reading is limited to PCM containers (WAV/W64/AIFF); other sources are skipped safely.

  v0.1.0 (2025-09-01)
    - Initial release (read-only parsing & normalization):
      * Unwrap SECTION to get the real parent source.
      * Cached GetMediaFileMetadata lookups.
      * Read iXML TRACK_LIST (CHANNEL_INDEX/NAME).
      * When TRACK_LIST is missing, fall back to BWF/Description sTRK#=Name (EdiLoad split compatible).
      * Basic Interleave ↔ TRK# mapping to power $trk/$trkall.
]]


local M = {}
M.VERSION = "0.3.11"

-- ====== Source / file helpers ======
local function stype(src) local ok,t=pcall(reaper.GetMediaSourceType,src,""); return ok and (t or "") or "" end

function M.unwrap_source(take)
  if not take then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  while src and stype(src) == "SECTION" do
    local ok, parent = pcall(reaper.GetMediaSourceParent, src)
    if not ok or not parent then break end
    src = parent
  end
  return src
end

function M.source_file_path(src)
  if not src then return "" end
  local ok, p = pcall(reaper.GetMediaSourceFileName, src, "")
  return (ok and p) or ""
end

-- PT 風格（26-6-16-12-4，小寫＋破折號）
local function umid_to_pt(hex64)
  local h = (hex64 or ""):gsub("%s+", ""):lower()
  if #h ~= 64 then return nil end
  return table.concat({
    h:sub(1,26), h:sub(27,32), h:sub(33,48), h:sub(49,60), h:sub(61,64)
  }, "-")
end

local parse_ixml_tracklist_from_chunk

-- 讀不到 BWF:UMID 時的 CLI fallback（bwfmetaedit --out-xml）
local function read_umid_via_cli_abs(path_to_cli, wav_path)
  local cli = path_to_cli or "/opt/homebrew/bin/bwfmetaedit"
  local cmd = string.format('"%s" --out-xml=- "%s"', cli, wav_path)
  local ok, out = reaper.ExecProcess and reaper.ExecProcess(cmd, 10000) or nil, nil
  if type(ok) == "number" then out = select(2, reaper.ExecProcess(cmd, 10000)) end
  if not out or out == "" then
    local fh = io.popen(cmd); out = fh and fh:read("*a") or ""; if fh then fh:close() end
  end
  if not out or out == "" then return nil end
  -- 找 <UMID>…</UMID>（bext 區段）
  local hex = out:match("<UMID>([%x%s]+)</UMID>")
  if not hex then return nil end
  hex = hex:gsub("%s+", ""):upper()
  if #hex ~= 64 then return nil end
  return hex
end

local TRACKLIST_CLI_CACHE = {}

local function read_tracklist_via_cli_abs(path_to_cli, wav_path)
  local path = tostring(wav_path or "")
  if path == "" then return nil end
  if TRACKLIST_CLI_CACHE[path] ~= nil then return TRACKLIST_CLI_CACHE[path] end

  local cli = path_to_cli or "/opt/homebrew/bin/bwfmetaedit"
  local cmd = string.format('"%s" --out-xml=- "%s"', cli, path)
  local xml = ""
  local fh = io.popen(cmd)
  if fh then
    xml = fh:read("*a") or ""
    fh:close()
  end

  local tracks = nil
  if xml ~= "" then tracks = parse_ixml_tracklist_from_chunk(xml) end
  TRACKLIST_CLI_CACHE[path] = tracks or false
  return tracks
end




-- ====== cached metadata reads ======
local CACHE = {}
function M.begin_batch() CACHE = {} end
function M.end_batch()   CACHE = {}; TRACKLIST_CLI_CACHE = {} end
local function meta(src, key)
  local k = tostring(src) .. "\0" .. key
  if CACHE[k] ~= nil then return CACHE[k] end
  local ok, v = reaper.GetMediaFileMetadata(src, key)
  v = (ok == 1 and v ~= "") and v or nil
  CACHE[k] = v
  return v
end

-- ====== UTF-8 helpers（給 token: srcbaseprefix/suffix） ======
local function utf8_spans(s)
  s = tostring(s or ""); local spans, i, n = {}, 1, #s
  while i <= n do
    local c = s:byte(i); if not c then break end
    local len = (c<0x80) and 1 or ((c<=0xDF) and 2 or ((c<=0xEF) and 3 or 4))
    local j = math.min(i+len-1, n); spans[#spans+1] = {i,j}; i = j+1
  end
  return spans
end
local function utf8_len(s) return #utf8_spans(s) end
local function utf8_sub(s, ci1, ci2)
  s = tostring(s or ""); local spans = utf8_spans(s); local n = #spans
  if n == 0 then return "" end
  ci1 = math.max(1, math.min(n, ci1 or 1))
  ci2 = math.max(1, math.min(n, ci2 or n))
  if ci2 < ci1 then return "" end
  local b = spans[ci1][1]; local e = spans[ci2][2]
  return s:sub(b, e)
end

-- ====== BWF/Description 解析（含 dXXXX/sXXXX 正規化） ======
local function parse_description_pairs(desc_text, out_tbl)
  for line in (tostring(desc_text or "") .. "\n"):gmatch("(.-)\n") do
    local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if k and v and k ~= "" then
      out_tbl[k] = v
      out_tbl[string.lower(k)] = v

      -- Map dXXXX/sXXXX → XXXX（upper & lower）
      local up = k:upper()
      local base = up:match("^[SD]([A-Z0-9_]+)$")
      if base and base ~= "" then
        out_tbl[base] = v
        out_tbl[string.lower(base)] = v
      end

      -- Map dTRK#/TRK#/sTRK# → TRK#/trk#
      local n = up:match("^[SD]?TRK(%d+)$")
      if n then
        out_tbl["TRK"..n] = v
        out_tbl["trk"..n] = v
      end
    end
  end
end

local function decode_xml_text(s)
  local v = tostring(s or "")
  v = v:gsub("<!%[CDATA%[(.-)%]%]>", "%1")
  v = v:gsub("&lt;", "<")
  v = v:gsub("&gt;", ">")
  v = v:gsub("&quot;", '"')
  v = v:gsub("&apos;", "'")
  v = v:gsub("&amp;", "&")
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  return v
end

parse_ixml_tracklist_from_chunk = function(ixml_chunk)
  local xml = tostring(ixml_chunk or "")
  if xml == "" then return nil end
  local block = xml:match("<TRACK_LIST>(.-)</TRACK_LIST>")
  if not block or block == "" then return nil end

  local tracks = {}
  for track_xml in block:gmatch("<TRACK>(.-)</TRACK>") do
    local ch = tonumber(track_xml:match("<CHANNEL_INDEX>%s*(%d+)%s*</CHANNEL_INDEX>") or "")
    local il = tonumber(track_xml:match("<INTERLEAVE_INDEX>%s*(%d+)%s*</INTERLEAVE_INDEX>") or "")
    local nm = decode_xml_text(track_xml:match("<NAME>(.-)</NAME>") or "")
    if ch or il or nm ~= "" then
      tracks[#tracks+1] = { channel_index = ch, interleave_index = il, name = nm }
    end
  end
  return (#tracks > 0) and tracks or nil
end

local function detect_recorder_family(src)
  local originator = tostring(meta(src, "BWF:Originator") or "")
  local originator_upper = originator:upper()
  local ixml_blob = tostring(meta(src, "IXML") or ""):upper()

  if originator_upper:find("AATON", 1, true) or originator_upper:find("CANTAR", 1, true)
    or ixml_blob:find("AATON_CANTAR", 1, true) then
    return "aaton"
  end
  if originator_upper:find("SOUND DEVICES", 1, true)
    or originator_upper:find("MIXPRE", 1, true)
    or ixml_blob:find("SOUND_DEVICES", 1, true) then
    return "sounddevices"
  end
  if originator_upper:find("SONOSAX", 1, true)
    or ixml_blob:find("SONOSAX", 1, true) then
    return "sonosax"
  end
  return "generic"
end

-- ====== iXML TRACK_LIST → t.trk# ======
local function fill_ixml_tracklist(src, t)
  t.__recorder_family = detect_recorder_family(src)
  local tracks = nil
  local src_channels = tonumber(t.channels) or 0

  -- Canonical source for multichannel track maps across recorder brands.
  if src_channels > 1 and t.srcpath and t.srcpath ~= "" then
    tracks = read_tracklist_via_cli_abs(nil, t.srcpath)
  end
  if not tracks then
    tracks = parse_ixml_tracklist_from_chunk(meta(src, "IXML"))
  end

  if not tracks then
    tracks = {}
    local ok, count = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK_COUNT")
    if ok == 1 then
      local n = tonumber(count) or 0
      for i=1,n do
        local suf = (i>1) and (":"..i) or ""
        local _, ch_idx = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX"..suf)
        local _, il_idx = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:INTERLEAVE_INDEX"..suf)
        local _, name   = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:NAME"..suf)
        local idx = tonumber(ch_idx or "")
        local il  = tonumber(il_idx or "") or i
        local nm  = decode_xml_text(name)
        tracks[#tracks+1] = { channel_index = idx, interleave_index = il, name = nm }
      end
    end
  end

  if #tracks > 0 then
    for i, tr in ipairs(tracks) do
      tr.interleave_index = tonumber(tr.interleave_index) or i
      local ch = tonumber(tr.channel_index) or tonumber(tr.interleave_index)
      local nm = tostring(tr.name or "")
      if ch and ch >= 1 and nm ~= "" then
        t["trk"..ch] = nm
        t["TRK"..ch] = nm
      end
    end
    t.__ixml_tracks = tracks
  end

  local active_slots = {}
  local saw_active = false
  local max_slots = math.max(#tracks, tonumber(t.channels) or 0, 1)
  for i = 1, max_slots do
    local suf = (i > 1) and (":" .. i) or ""
    local raw = meta(src, "IXML:AATON_CANTAR:ALL_TRK_NAME:DATA:ACTIVE" .. suf)
             or meta(src, "AATON_CANTAR:ALL_TRK_NAME:DATA:ACTIVE" .. suf)
    if raw and raw ~= "" then
      saw_active = true
      local v = tostring(raw):upper():gsub("^%s+", ""):gsub("%s+$", "")
      if v == "YES" or v == "TRUE" or v == "1" or v == "ARMED" then
        active_slots[#active_slots + 1] = i
      end
    end
  end
  if t.__recorder_family == "aaton" and saw_active and #active_slots > 0 then
    t.__aaton_active_slots = active_slots
  end
end

-- ====== 補充：來源取樣率/聲道數 ======
local function detect_samplerate_channels(src)
  if not src then return nil,nil end
  local srate = reaper.GetMediaSourceSampleRate(src) or 0
  local ch = reaper.GetMediaSourceNumChannels(src) or 0
  return srate, ch
end

-- ====== Interleave index（來自 I_CHANMODE 的 Mono-of-N） ======
local function get_source_num_channels(item, fields)
  local tk = item and reaper.GetActiveTake(item)
  if tk then
    local src = reaper.GetMediaItemTake_Source(tk)
    if src then
      local nch = reaper.GetMediaSourceNumChannels(src)
      if type(nch) == "number" and nch > 0 then return nch end
    end
  end
  local n = tonumber(fields and fields.channels)
  if n and n > 0 then return n end
  return 1
end

function M.guess_interleave_index(item, fields)
  local tk = item and reaper.GetActiveTake(item)
  if not tk then return nil end
  local cm = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0
  if cm >= 3 and cm <= 66 then
    local n = math.floor(cm - 2)
    local nch = get_source_num_channels(item, fields)
    if n < 1 then n = 1 end
    if n > nch then n = nch end
    return n
  end
  return nil
end

-- ====== 建立 Interleave → Name 表 ======
local function build_interleave_name_list(fields)
  if fields.__trk_by_interleave then return fields.__trk_by_interleave end
  local by_interleave, have_ixml = {}, false

  if fields.__ixml_tracks and type(fields.__ixml_tracks) == "table" then
    local by_slot = {}
    local have_any_interleave_index = false
    for _, t in ipairs(fields.__ixml_tracks) do
      local idx = tonumber(t.interleave_index)
      local nm  = t.name
      if nm and nm ~= "" then
        by_slot[#by_slot+1] = nm
      end
      if idx and idx >= 1 then
        have_any_interleave_index = true
        if nm and nm ~= "" and not by_interleave[idx] then
          by_interleave[idx] = nm
          have_ixml = true
        end
      end
    end

    local active_slots = fields.__aaton_active_slots
    if fields.__recorder_family == "aaton"
      and type(active_slots) == "table"
      and #active_slots > 0
      and #by_slot > 0
      and #active_slots == #by_slot then
      -- AATON files can expose compressed TRACK_LIST names in REAPER metadata.
      -- Re-map the non-empty sequence onto active recorder slots to preserve layout.
      by_interleave = {}
      for i, slot in ipairs(active_slots) do
        local slot_idx = tonumber(slot)
        local nm = by_slot[i]
        if slot_idx and slot_idx >= 1 and nm and nm ~= "" and not by_interleave[slot_idx] then
          by_interleave[slot_idx] = nm
        end
      end
      have_ixml = true
    end

    -- Only use sequential fallback when interleave indexes are absent.
    if not have_ixml and (not have_any_interleave_index) and #by_slot > 0 then
      for i, nm in ipairs(by_slot) do by_interleave[i] = nm end
      have_ixml = true
    end
  end
  if not have_ixml then
    local pairs_chan, seen = {}, {}
    for k, v in pairs(fields or {}) do
      local n = k:match("^TRK(%d+)$") or k:match("^trk(%d+)$")
      if n then
        local ch = tonumber(n)
        if ch and v and v ~= "" and not seen[ch] then
          pairs_chan[#pairs_chan+1] = { chan = ch, name = v }
          seen[ch] = true
        end
      end
    end
    table.sort(pairs_chan, function(a,b) return a.chan < b.chan end)
    for i, e in ipairs(pairs_chan) do by_interleave[i] = e.name end
  end

  fields.__trk_by_interleave = by_interleave
  return by_interleave
end

-- ====== 將 item 讀成規範化欄位表（Rename/Monitor/Sort 共用） ======
function M.collect_item_fields(item)
  local t = {}
  local take = item and reaper.GetActiveTake(item)
  local src  = take and M.unwrap_source(take)
  local fn   = src and M.source_file_path(src)

  -- true source tokens
  if fn and fn ~= "" then
    t.srcpath = fn
    t.srcfile = (fn:match("([^/\\]+)$") or fn)
    t.srcbase = t.srcfile:gsub("%.%w+$","")
    t.srcext  = (t.srcfile:match("%.([^.]+)$") or "")
    t.srcdir  = (fn:match("^(.*)[/\\][^/\\]+$") or "")
  end
  t.filename = t.srcbase or ""
  t.filepath = fn or ""

  local sr, ch = detect_samplerate_channels(src)
  if sr and sr>0 then t.samplerate = tostring(math.floor(sr+0.5)) end
  if ch and ch>0 then t.channels   = tostring(ch) end

  -- 可讀 metadata？
  local srctype = src and reaper.GetMediaSourceType(src, "") or ""
  local upper = (srctype or ""):upper()
  local can_meta = (upper:find("WAVE") or upper:find("AIFF") or upper:find("WAVE64")) and true or false

  if can_meta then
    -- Generic
    local g_date = meta(src, "Metadata:Date");        if g_date then t.date = g_date; t["metadata:date"]=g_date end
    local g_desc = meta(src, "Metadata:Description");  if g_desc then t.description = g_desc end
    local g_offs = meta(src, "Generic:StartOffset");   if g_offs then t.startoffset = g_offs end

    -- BWF core
    local desc = meta(src, "BWF:Description"); if desc then t.Description=desc; t.description = t.description or desc end
    local od   = meta(src, "BWF:OriginationDate"); if od then t.OriginationDate=od; t.originationdate=od end
    local ot   = meta(src, "BWF:OriginationTime"); if ot then t.OriginationTime=ot; t.originationtime=ot end
    local org  = meta(src, "BWF:Originator"); if org then t.Originator=org; t.originator=org end
    local orgr = meta(src, "BWF:OriginatorReference"); if orgr then t.OriginatorReference=orgr; t.originatorreference=orgr end
    local tr   = meta(src, "BWF:TimeReference"); if tr then t.TimeReference=tr; t.timereference=tr end
    
    if desc then parse_description_pairs(desc, t) end

    -- ====== BWF:UMID（SMPTE ID）======
    local function set_umid_fields(hex)
      t.UMID = hex
      t.umid = hex
      local pt = umid_to_pt(hex)
      if pt then t.umid_pt = pt end
    end

    -- 1) 先嘗試 REAPER API（有些版本讀不到）
    do
      local um = meta(src, "BWF:UMID") or meta(src, "UMID")
      if um and um ~= "" then
        local hex = um:gsub("[^0-9A-Fa-f]", ""):upper()
        if #hex == 64 then set_umid_fields(hex) end
      end
    end

    -- 2) 讀不到就走 CLI fallback（bwfmetaedit --out-xml）
    if not t.umid and t.srcpath and t.srcpath ~= "" then
      local hex = read_umid_via_cli_abs(nil, t.srcpath)  -- nil=預設 /opt/homebrew/bin/bwfmetaedit
      if hex then set_umid_fields(hex) end
    end


    -- iXML common
    local proj = meta(src, "IXML:PROJECT"); if proj then t.PROJECT=proj; t.project=proj end
    local sc   = meta(src, "IXML:SCENE");   if sc   then t.SCENE=sc;     t.scene=sc   end
    local tk   = meta(src, "IXML:TAKE");    if tk   then t.TAKE=tk;      t.take=tk    end
    local tp   = meta(src, "IXML:TAPE");    if tp   then t.TAPE=tp;      t.tape=tp    end
    local ub   = meta(src, "IXML:UBITS");   if ub   then t.UBITS=ub;     t.ubits=ub   end
    local fr   = meta(src, "IXML:FRAMERATE"); if fr then t.FRAMERATE=fr; t.framerate=fr end
    local sp   = meta(src, "IXML:SPEED");   if sp   then t.SPEED=sp;     t.speed=sp   end

    -- iXML TRACK_LIST → trk#
    fill_ixml_tracklist(src, t)
  end

  -- 推出 __trk_table
  t.__trk_table = {}
  for i=1,64 do local v=t["trk"..i]; if v and v~="" then t.__trk_table[i]=v end end

  -- Interleave index（I_CHANMODE）→ __chan_index
  local guessed_idx = M.guess_interleave_index(item, t)
  t.__has_explicit_interleave = (guessed_idx ~= nil)
  t.__chan_index = guessed_idx
  if not t.__chan_index and type(t.__ixml_tracks) == "table" and #t.__ixml_tracks == 1 then
    t.__chan_index = tonumber(t.__ixml_tracks[1].interleave_index or "") or 1
  end
  if not t.__chan_index then t.__chan_index = 1 end

  local il_list = build_interleave_name_list(t)
  if il_list and il_list[t.__chan_index] and il_list[t.__chan_index] ~= "" then
    t.__trk_name = il_list[t.__chan_index]
  elseif t.__trk_table[t.__chan_index] then
    t.__trk_name = t.__trk_table[t.__chan_index]
  end

  -- current take / note
  if take then
    local _, cur_name = reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME","",false)
    t.curtake = (cur_name and cur_name~="") and cur_name or "(unnamed)"
  else
    t.curtake = "(no take)"
  end
  local _, note = reaper.GetSetMediaItemInfo_String(item,"P_NOTES","",false)
  t.curnote = note or ""

  -- 給診斷用
  t.__item = item
  return t
end

-- ====== Interleave 診斷（供 UI/複製區） ======
function M.compute_interleave_diag(fields, item)
  local list = build_interleave_name_list(fields)
  local nch  = get_source_num_channels(item, fields)
  local idx  = M.guess_interleave_index(item, fields)

  local name = ""
  if idx and list and list[idx] then
    name = list[idx]
  else
    if list then
      for i = 1, 256 do if list[i] and list[i]~="" then name = list[i]; break end end
    end
  end

  local all = {}
  if list then for i=1,256 do local v=list[i]; if v and v~="" then all[#all+1]=v end end end

  fields.__diag_interleave = { index = idx, total = nch, name = name, all = table.concat(all, "_") }
end

local function get_current_interleave_index(fields)
  local idx = tonumber(fields and fields.__chan_index) or 1
  if idx < 1 then idx = 1 end
  return idx
end

local function get_recorder_channel_number(fields)
  local il = get_current_interleave_index(fields)

  if type(fields and fields.__ixml_tracks) == "table" and #fields.__ixml_tracks > 0 then
    for i, tr in ipairs(fields.__ixml_tracks) do
      local tr_il = tonumber(tr.interleave_index or "") or i
      if tr_il == il then
        local ch = tonumber(tr.channel_index or "")
        if ch and ch > 0 then return ch end
      end
    end
    if #fields.__ixml_tracks == 1 then
      local ch = tonumber(fields.__ixml_tracks[1].channel_index or "")
      if ch and ch > 0 then return ch end
    end
  end

  local pairs_chan, seen = {}, {}
  for k, v in pairs(fields or {}) do
    local n = k:match("^TRK(%d+)$") or k:match("^trk(%d+)$")
    if n and not seen[n] then
      seen[n] = true
      pairs_chan[#pairs_chan+1] = { chan = tonumber(n), name = v }
    end
  end
  table.sort(pairs_chan, function(a,b) return (a.chan or 0) < (b.chan or 0) end)
  if #pairs_chan > 0 then
    local e = pairs_chan[il]
    if e and e.chan then return e.chan end
  end
  return il
end

-- ====== Token 處理 ======
local function normalize_tokens(s)
  s = tostring(s or "")
  s = s:gsub("%$trk(%d+)", "${trk%1}")
       :gsub("%$(counter:%d+)", "${%1}")
       :gsub("%$(srcbaseprefix:%d+)", "${%1}")
       :gsub("%$(srcbasesuffix:%d+)", "${%1}")
  local known = {
    "curtake","curnote","clearnote","track","filename","srcfile","srcbase","srcext","srcpath","srcdir",
    "samplerate","channels","length","project","scene","take","tape","trk","trkall",
    "ubits","framerate","speed","date","time","year","originationdate","originationtime","startoffset",
    "filepath","originator","originatorreference","timereference","description","interleave","interum","chnum","channelnum",
    -- 新增 UMID tokens
    "umid","umid_pt",
  }
  table.sort(known, function(a,b) return #a > #b end)
  for _,k in ipairs(known) do s = s:gsub("%$"..k, "${"..k.."}") end
  return s
end

local function template_token_list(tpl)
  local list, seen = {}, {}
  local s = normalize_tokens(tpl or "")
  for name in s:gmatch("%${([%w_:]+)}") do
    if not seen[name] then seen[name] = true; list[#list+1] = name end
  end
  table.sort(list); return list
end

function M.empty_tokens_in_template(tpl, fields, counter)
  local empties, tokens = {}, template_token_list(tpl)
  for _, tk in ipairs(tokens) do
    if tk ~= "clearnote" then
      local probe = "${" .. tk .. "}"
      local out = M.expand(probe, fields, counter, false) or ""
      out = tostring(out):gsub("^%s+",""):gsub("%s+$","")
      if out == "" then empties[#empties+1] = tk end
    end
  end
  return empties
end

function M.expand(tpl, fields, counter, sanitize)
  if sanitize == nil then sanitize = true end
  local function maybe_sanitize(s)
    s = tostring(s or "")
    if sanitize then return (s:gsub('[\\/:*?"<>|%c]', '_')) end
    return s
  end

  local function repl(name)
    local tkl = string.lower(name or "")
    if tkl == "clearnote" then return "" end

    local prefix = tkl:match("^srcbaseprefix:(%d+)$")
    if prefix then
      local n = tonumber(prefix) or 0
      local srcbase = fields.srcbase or fields.filename or ""
      if n > 0 then
        local spans = utf8_spans(srcbase)
        local len = math.min(n, #spans)
        if len > 0 then return srcbase:sub(1, spans[len][2]) end
      end
      return ""
    end

    local suffix = tkl:match("^srcbasesuffix:(%d+)$")
    if suffix then
      local n = tonumber(suffix) or 0
      local srcbase = fields.srcbase or fields.filename or ""
      local spans = utf8_spans(srcbase)
      local len = #spans
      if n > 0 and len > 0 then
        local start_i = math.max(1, len - n + 1)
        return srcbase:sub(spans[start_i][1], spans[len][2])
      end
      return ""
    end

    local digits = tkl:match("^counter:(%d+)$")
    if digits then
      local n = tonumber(digits) or 0
      local val = tostring(counter or 1)
      if n > 0 then val = string.rep("0", math.max(0, n - #val)) .. val end
      return val
    end

    if tkl == "trk" then
      -- Pro Tools-like display: for poly files without explicit mono-of-N
      -- selection, show the full interleaved track-name list.
      local has_explicit = (fields.__has_explicit_interleave == true)
      local chn = tonumber(fields.channels) or 1
      if (not has_explicit) and chn > 1 then
        local list = build_interleave_name_list(fields)
        local out = {}
        if list then for i=1,256 do local v=list[i]; if v and v~="" then out[#out+1]=v end end end
        return maybe_sanitize(table.concat(out, "_"))
      end

      return M.resolve_trk_name(fields, sanitize)
    end

    if tkl == "trkall" then
      local list = build_interleave_name_list(fields)
      local out = {}
      if list then for i=1,256 do local v=list[i]; if v and v~="" then out[#out+1]=v end end end
      return table.concat(out, "_")
    end

    local nidx = tkl:match("^trk(%d+)$")
    if nidx then
      local idx = tonumber(nidx)
      local v = (fields.__trk_table and fields.__trk_table[idx]) or fields["trk"..nidx] or fields["TRK"..nidx]
      return maybe_sanitize(v or "")
    end

    if tkl == "interleave" or tkl == "interum" then
      return tostring(get_current_interleave_index(fields) or "")
    end

    if tkl == "chnum" or tkl == "channelnum" then
      return tostring(get_recorder_channel_number(fields) or "")
    end

    local v = fields[tkl] or fields[name] or ""
    return maybe_sanitize(v)
  end

  local out = normalize_tokens(tpl or "")
  out = out:gsub("%${(.-)}", function(s) return repl(s) end)
           :gsub("%$([%a%d:]+)", function(s) return repl(s) end)
           :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

-- Whether the file's iXML TRACK_LIST covers this channel. A file with a
-- TRACK_LIST describes every one of its channels: a channel with an empty
-- name — or with no entry at all, as in the compressed AATON lists REAPER can
-- expose (only the named tracks) — has no name. It must never borrow another
-- channel's; only a file with no TRACK_LIST at all falls back.
local function track_list_describes_slot(fields, interleave)
  local tracks = fields and fields.__ixml_tracks
  if type(tracks) ~= "table" or #tracks == 0 or not interleave then return false end
  local channels = math.max(tonumber(fields.channels) or 0, #tracks)
  return interleave >= 1 and interleave <= channels
end

-- Public helper: single resolved track name for the item's current channel.
-- Prefers fields.meta_trk_name (the already-resolved single-channel name,
-- which survives a Metadata.cache round-trip even when the recorder doesn't
-- embed per-channel TRK#= pairs in the description text), falling back to
-- the interleave-name-list reconstruction and then — only when the track list
-- doesn't describe this channel at all — to the first non-empty
-- name in that list. Always resolves to one name (no Pro-Tools-style "full
-- poly list" behavior) — this is the single-name path $trk uses above, and
-- what the Rename-from-Metadata scripts call directly for their $trk token.
function M.resolve_trk_name(fields, sanitize)
  if sanitize == nil then sanitize = true end
  local function maybe_sanitize(s)
    s = tostring(s or "")
    if sanitize then return (s:gsub('[\\/:*?"<>|%c]', '_')) end
    return s
  end

  local f = fields or {}
  local s = f.meta_trk_name
  if not s or s == "" then
    local interleave = f.__chan_index
    local list = build_interleave_name_list(f)
    s = ""
    if interleave and list and list[interleave] then
      s = list[interleave]
    elseif track_list_describes_slot(f, interleave) then
      s = ""  -- explicit, empty slot: stays empty (v0.3.9 rule, restored in v0.3.11)
    else
      if list then
        for i = 1, 128 do
          if list[i] and list[i] ~= "" then s = list[i]; break end
        end
      end
    end
  end
  return maybe_sanitize(s or "")
end

-- Public helper: resolve track name & channel by interleave index
function M.trk_name_and_channel(fields, idx)
  local f = fields or {}
  local il = tonumber(idx) or tonumber(f.__chan_index) or 1
  if il < 1 then il = 1 end

  local list = build_interleave_name_list(f)

  local name = ""
  if list and list[il] and list[il] ~= "" then
    name = list[il]
  end

  local prev = f.__chan_index
  f.__chan_index = il
  local chan = get_recorder_channel_number(f)
  f.__chan_index = prev

  return name or "", (chan or il)
end


return M