--[[
@description Metadata Read (reader / normalizer / tokens)
@version 0.2.0
@author hsuanice
@noindex
@about
  Read-only metadata utilities for REAPER items:
  - Unwrap SECTION to real parent source
  - Read iXML TRACK_LIST (Wave Agent style)
  - Fallback parse sTRK#=Name from BWF/Description (EdiLoad split)
  - Interleave index ↔ recorder channel mapping
  - Token expansion for rename/export ($trk/$trkN/$trkall, ${interleave}, ${chnum}, ...)

@changelog
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
M.VERSION = "0.2.0"

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

-- ====== cached metadata reads ======
local CACHE = {}
function M.begin_batch() CACHE = {} end
function M.end_batch()   CACHE = {} end
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

-- ====== iXML TRACK_LIST → t.trk# ======
local function fill_ixml_tracklist(src, t)
  local ok, count = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK_COUNT")
  if ok == 1 then
    local n = tonumber(count) or 0
    for i=1,n do
      local suf = (i>1) and (":"..i) or ""
      local _, ch_idx = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX"..suf)
      local _, name   = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:NAME"..suf)
      local idx = tonumber(ch_idx or "")
      if idx and idx >= 1 then
        if name and name ~= "" then
          t["trk"..idx] = name; t["TRK"..idx] = name
        elseif not t["trk"..idx] and t["TRK"..idx] then
          t["trk"..idx] = t["TRK"..idx]
        end
      end
    end
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
    for _, t in ipairs(fields.__ixml_tracks) do
      local idx = tonumber(t.channel_index)
      local nm  = t.name
      if idx and idx >= 1 and nm and nm ~= "" then
        by_interleave[idx] = nm
        have_ixml = true
      end
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
  t.__chan_index = M.guess_interleave_index(item, t)
  if not t.__chan_index then
    for i=1,64 do if t.__trk_table[i] then t.__chan_index=i break end end
  end
  if t.__chan_index and t.__trk_table[t.__chan_index] then t.__trk_name = t.__trk_table[t.__chan_index] end

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
  local pairs_chan, seen = {}, {}
  for k, v in pairs(fields or {}) do
    local n = k:match("^TRK(%d+)$") or k:match("^trk(%d+)$")
    if n and not seen[n] then
      seen[n] = true
      pairs_chan[#pairs_chan+1] = { chan = tonumber(n), name = v }
    end
  end
  table.sort(pairs_chan, function(a,b) return (a.chan or 0) < (b.chan or 0) end)
  local il = get_current_interleave_index(fields)
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
      local interleave = fields.__chan_index
      local list = build_interleave_name_list(fields)
      local s = ""
      if interleave and list and list[interleave] then
        s = list[interleave]
      else
        if list then for i=1,128 do if list[i] and list[i]~="" then s=list[i]; break end end end
      end
      return maybe_sanitize(s)
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

return M
