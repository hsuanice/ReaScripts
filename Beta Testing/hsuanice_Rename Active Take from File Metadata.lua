--[[
@description ReaImGui - Rename Active Take from Metadata (caret insert + cached preview + copy/export)
@version 0.3
@author hsuanice
@about
  Rename active takes and/or item notes from BWF/iXML and true source metadata using a fast ReaImGui UI.
    - Two templates: Take Name + Item Note (empty note template = skip).
    - Click tokens to insert at caret; caret snaps outside existing $tokens.
    - Robust around separators: safe with "--" and "__"; underscores no longer swallow preceding tokens.
    - Reads metadata once per selection ("Get Metadata") and caches it; configurable preview limit.
    - Apply uses current selection; reuses cache if unchanged; Undo / Redo supported.
    - Channel-aware tokens: $trk (auto per-take), $trkN, and $trkall (from iXML/BWF track list, with fallbacks).
    - True source tokens: $srcfile, $srcbase, $srcext, $srcpath, $srcdir (actual media filename/paths).
    - Metadata panel + preview table with quick copy; export preview table as Tab or CSV.
    - Works on audio items; items without takes (empty/MIDI) can still update notes.
    - Requires: ReaImGui (install via ReaPack).
  
  Features:
  - Built with ReaImGUI for a compact, responsive UI.
  - Designed for fast, keyboard-light workflows.
  
  References:
  - REAPER ReaScript API (Lua)
  - ReaImGUI (ReaScript ImGui binding)
  
  Note:
  - This is a 0.1 beta release for internal testing.
  
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.3 - Add Selected/Scanned/Cached status view
  v0.2 - Add ESC close function
  v0.1 - Beta release
--]]


-- ===== Guard ReaImGui =====
if not reaper or not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("This script requires ReaImGui (install via ReaPack).", "Missing dependency", 0)
  return
end

-- ===== ImGui basics =====
local ctx = reaper.ImGui_CreateContext('Rename Active Take from Metadata')
local FLT_MIN = reaper.ImGui_NumericLimits_Float()
local WIN_W, WIN_H = 1020, 720
local function TF(name) local fn = reaper[name]; return (type(fn)=="function") and fn() or 0 end

-- ESC key enum (works across ReaImGui versions)
local KEY_ESC = TF('ImGui_Key_Escape')


-- ===== ExtState (defaults) =====
local EXT_NS = "RENAME_TAKE_FROM_METADATA_V1"
local DEFAULT_TAKE_TEMPLATE_INIT = "$scene_$take_$trk"
local DEFAULT_NOTE_TEMPLATE_INIT = ""
local function load_defaults()
  local t = reaper.GetExtState(EXT_NS, "default_take_template")
  local n = reaper.GetExtState(EXT_NS, "default_note_template")
  if not t or t == "" then t = DEFAULT_TAKE_TEMPLATE_INIT end
  if not n then n = DEFAULT_NOTE_TEMPLATE_INIT end
  return t, n
end
local function save_defaults(t, n)
  reaper.SetExtState(EXT_NS, "default_take_template", tostring(t or ""), true)
  reaper.SetExtState(EXT_NS, "default_note_template", tostring(n or ""), true)
end

-- Persist split ratio
local function load_split_ratio()
  local s = tonumber(reaper.GetExtState(EXT_NS, "split_ratio") or "")
  if s and s > 0.1 and s < 0.9 then return s end
  return 0.62
end
local function save_split_ratio(ratio)
  reaper.SetExtState(EXT_NS, "split_ratio", string.format("%.4f", ratio or 0.62), true)
end

-- ===== Safe BeginChild (compat for different ReaImGui signatures) =====
local function BeginChildSafe(id, w, h, border, flags)
  flags = flags or 0
  -- Variant A: (ctx, id, w, h, flags:number)
  local ok, ret = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, flags)
  if ok and ret ~= nil then return ret end
  -- Variant B: (ctx, id, w, h, border:boolean, flags:number)
  ok, ret = pcall(reaper.ImGui_BeginChild, ctx, id, w, h, border and true or false, flags)
  if ok and ret ~= nil then return ret end
  -- Variant C: (ctx, id, w, h)
  ok, ret = pcall(reaper.ImGui_BeginChild, ctx, id, w, h)
  if ok and ret ~= nil then return ret end
  -- Final fallback: numeric flags at arg#5
  return reaper.ImGui_BeginChild(ctx, id, w, h, 0)
end

-- ===== UTF-8 helpers =====
local function trim(s) return (tostring(s or "")):gsub("^%s+",""):gsub("%s+$","") end
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
local function utf8_width_first_k(ctx, s, k)
  s = tostring(s or ""); local spans = utf8_spans(s)
  if k <= 0 then return 0 end
  k = math.min(k, #spans)
  local prefix = s:sub(1, spans[k][2])
  local w = select(1, reaper.ImGui_CalcTextSize(ctx, prefix))
  return w or 0
end
local function utf8_index_from_x(ctx, s, relx)
  local n = utf8_len(s); if n == 0 or relx <= 0 then return 0 end
  local best_i, best_d = 0, 1e9
  for i = 0, n do
    local w = utf8_width_first_k(ctx, s, i)
    local d = math.abs(w - relx)
    if d < best_d then best_d, best_i = d, i end
  end
  return best_i
end
local function insert_at_char_index(s, token, ci)
  s = tostring(s or ""); token = tostring(token or ""); local n = utf8_len(s)
  ci = math.max(0, math.min(n, tonumber(ci or n) or n))
  if ci == 0 then return token..s, ci + utf8_len(token) end
  if ci == n then return s..token, ci + utf8_len(token) end
  local left = utf8_sub(s, 1, ci); local right = utf8_sub(s, ci+1, n)
  return left..token..right, ci + utf8_len(token)
end
local function utf8_char_at(s, ci)
  if not s or s=="" then return "" end
  local n = utf8_len(s); if ci < 1 or ci > n then return "" end
  return utf8_sub(s, ci, ci)
end
local function byte_to_char_index(s, bpos)
  local spans = utf8_spans(s)
  for i, sp in ipairs(spans) do if bpos <= sp[2] then return i end end
  return #spans
end

-- ===== Token spans (for snapping) =====
local function token_spans_chars(s)
  s = tostring(s or "")
  local tokens = {}
  -- ${...}
  local i = 1
  while true do
    local bs, be = s:find("%$%b{}", i); if not bs then break end
    tokens[#tokens+1] = { byte_to_char_index(s, bs), byte_to_char_index(s, be) }
    i = be + 1
  end
  -- $word
  i = 1
  while true do
    local bs, be = s:find("%$[%a%d]+", i); if not bs then break end
    if s:sub(bs+1, bs+1) ~= "{" then
      tokens[#tokens+1] = { byte_to_char_index(s, bs), byte_to_char_index(s, be) }
    end
    i = be + 1
  end
  table.sort(tokens, function(a,b) return a[1] < b[1] end)
  return tokens
end
local function snap_caret_out_of_token(text, ci)
  local tks = token_spans_chars(text); if #tks==0 then return ci end
  for _, t in ipairs(tks) do
    local cs, ce = t[1], t[2]
    if ci > (cs-1) and ci < ce then return ce end
  end
  return ci
end

-- Avoid splitting words when inserting tokens
local function is_word_char(ch)
  return ch ~= "" and (ch:match("[%w_]") ~= nil)
end
local function snap_caret_out_of_word(text, ci, prefer_side)
  prefer_side = prefer_side or "right"
  local left  = utf8_char_at(text, ci)
  local right = utf8_char_at(text, ci + 1)
  if is_word_char(left) and is_word_char(right) then
    if prefer_side == "left" then
      local j = ci
      while j > 0 and is_word_char(utf8_char_at(text, j)) do j = j - 1 end
      return j
    else
      local n = utf8_len(text)
      local j = ci
      while j < n and is_word_char(utf8_char_at(text, j + 1)) do j = j + 1 end
      return j
    end
  end
  return ci
end

-- ===== Safe insert (caret-only; token+word snapping) =====
local function safe_insert_token(str, caret_ci, token)
  caret_ci = tonumber(caret_ci or utf8_len(str)) or utf8_len(str)
  caret_ci = snap_caret_out_of_token(str, caret_ci)
  caret_ci = snap_caret_out_of_word(str, caret_ci, "right")
  local s, new_idx = insert_at_char_index(str, token, caret_ci)
  return s, new_idx
end

-- ===== REAPER helpers =====
local function get_active_take(item) local tk=reaper.GetActiveTake(item); if tk and reaper.ValidatePtr2(0,tk,'MediaItem_Take*') then return tk end end
local function take_source(take) if not take then return nil end local s=reaper.GetMediaItemTake_Source(take); if s and reaper.ValidatePtr2(0,s,'PCM_source*') then return s end end
local function source_filename(src) if not src then return nil end local p=reaper.GetMediaSourceFileName(src,''); return (p~='' and p) or nil end
local function basename(p) return p and (p:match("([^/\\]+)$") or p) or "" end
local function basename_no_ext(p) local n=basename(p); return (n:gsub("%.%w+$","")) end
local function get_ext(p) local n=basename(p); return (n:match("%.([^.]+)$") or "") end
local function dirname(p) return p and (p:match("^(.*)[/\\][^/\\]+$") or "") or "" end
local function get_item_track_name(item) local tr=reaper.GetMediaItem_Track(item); if not tr then return "" end local _,name=reaper.GetTrackName(tr,""); return name or "" end
local function get_item_length_sec(item) return reaper.GetMediaItemInfo_Value(item,"D_LENGTH") or 0.0 end
local function seconds_to_m_ss_mmm(sec) local s=math.max(0,tonumber(sec) or 0) local m=math.floor(s/60) local r=s-m*60 return string.format("%d:%06.3f", m, r) end

-- channel guess
local function guess_channel_index(item, fields)
  local take = get_active_take(item)
  if take then
    local cm = reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0
    if cm >= 3 and cm <= 66 then return math.floor(cm - 2) end
  end
  local fname = fields and (fields.srcfile or fields.filepath or fields.filename) or (take and source_filename(take_source(take))) or ""
  local name = basename(tostring(fname)):lower()
  local idx =
      tonumber(name:match("[_%-%.]pn[_%-]?([0-9]+)%.%w+$")) or
      tonumber(name:match("[_%-%.]pm[_%-]?([0-9]+)%.%w+$")) or
      tonumber(name:match("[_%-%.]n[_%-]?([0-9]+)%.%w+$"))  or
      tonumber(name:match("[_%-%.]a([0-9]+)%.%w+$"))        or
      tonumber(name:match("[_%-%.]ch([0-9]+)%.%w+$"))       or
      tonumber(name:match("[_%-%.]iso[_%-]?([0-9]+)%.%w+$"))or
      tonumber(name:match("[_%-%s]([0-9]+)%.%w+$"))
  if idx and idx>=1 and idx<=64 then return idx end
  return nil
end

-- metadata keys
local BWF_KEYS = {
  "BWF:Description","BWF:OriginationDate","BWF:OriginationTime",
  "BWF:Originator","BWF:OriginatorReference","BWF:TimeReference",
}
local IXML_KEYS = {
  "IXML:PROJECT","IXML:SCENE","IXML:TAKE","IXML:TAPE","IXML:TRK1",
  "IXML:UBITS","IXML:FRAMERATE","IXML:SPEED",
}
local GENERIC_KEYS = { "Metadata:Date","Metadata:Description","Generic:StartOffset" }
local function get_meta(src, key)
  if not src or not reaper.GetMediaFileMetadata then return nil end
  local ok, val = reaper.GetMediaFileMetadata(src, key)
  if ok == 1 and val ~= "" then return val end
  return nil
end
local function parse_description_pairs(desc_text, out_tbl)
  for line in (tostring(desc_text or "") .. "\n"):gmatch("(.-)\n") do
    local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if k and v and k ~= "" then
      out_tbl[k] = v; out_tbl[string.lower(k)] = v
      if k:sub(1,1) == 's' and #k > 1 then
        local base = k:sub(2); out_tbl[base] = v; out_tbl[string.lower(base)] = v
      end
    end
  end
end
local function fill_ixml_tracklist(src, t)
  local ok, count = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK_COUNT")
  if ok == 1 then
    local n = tonumber(count) or 0
    for i=1,n do
      local suffix = (i>1) and (":"..i) or ""
      local _, ch_idx = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX"..suffix)
      local _, name   = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:NAME"..suffix)
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
local function detect_samplerate_channels(src)
  if not src then return nil,nil end
  local srate = reaper.GetMediaSourceSampleRate(src) or 0
  local ch = reaper.GetMediaSourceNumChannels(src) or 0
  return srate, ch
end

local function collect_metadata_for_item(item)
  local t = {}
  local take = get_active_take(item)
  local src  = take and take_source(take)
  local fn   = src and source_filename(src)
  -- true source tokens
  if fn and fn ~= "" then
    t.srcpath = fn
    t.srcfile = basename(fn)
    t.srcbase = basename_no_ext(fn)
    t.srcext  = get_ext(fn)
    t.srcdir  = dirname(fn)
  end
  -- back-compat-ish
  t.filename   = fn and basename_no_ext(fn) or ""
  t.filepath   = fn or ""
  -- common fields
  local sr, ch = detect_samplerate_channels(src)
  if sr and sr>0 then t.samplerate = tostring(math.floor(sr+0.5)) end
  if ch and ch>0 then t.channels   = tostring(ch) end
  t.track      = get_item_track_name(item)
  t.length     = seconds_to_m_ss_mmm(get_item_length_sec(item))
  -- can read bwf/ixml?
  local srctype = src and reaper.GetMediaSourceType(src, "") or ""
  local upper = srctype:upper()
  local can_meta = (upper:find("WAVE") or upper:find("AIFF") or upper:find("WAVE64")) and true or false
  if can_meta then
    for _, key in ipairs(GENERIC_KEYS) do
      local v = get_meta(src, key)
      if v ~= nil then t[string.lower(key:gsub("Metadata:",""):gsub("Generic:",""))] = v end
    end
    for _, key in ipairs(BWF_KEYS) do
      local v = get_meta(src, key)
      if v ~= nil then
        local short = key:gsub("BWF:","")
        t[short] = v; t[string.lower(short)] = v
        if short == "Description" then parse_description_pairs(v, t) end
      end
    end
    fill_ixml_tracklist(src, t)
    for _, key in ipairs(IXML_KEYS) do
      local v = get_meta(src, key)
      if v ~= nil then
        local short = key:gsub("IXML:","")
        t[short] = v; t[string.lower(short)] = v
      end
    end
  end
  local date_val = t.OriginationDate or t.originationdate or t.date
  local time_val = t.OriginationTime or t.originationtime or t.time
  local date_str = date_val and tostring(date_val) or ""
  if date_str ~= "" then
    t.year = date_str:match("(%d%d%d%d)") or ""; t.date = date_str
    t.originationdate = t.originationdate or t.OriginationDate or date_str
  end
  local time_str = time_val and tostring(time_val) or ""
  if time_str ~= "" then
    t.time = time_str; t.originationtime = t.originationtime or t.OriginationTime or time_str
  end
  if t.startoffset == nil and t.startoffsset ~= nil then t.startoffset = t.startoffsset end
  local alias = {
    "Description","OriginationDate","OriginationTime","Originator","OriginatorReference","TimeReference",
    "PROJECT","SCENE","TAKE","TAPE","TRK1","UBITS","FRAMERATE","SPEED",
    "filename","filepath","samplerate","channels","track","length","year","date","time",
    "originationdate","originationtime","startoffset",
    "srcpath","srcfile","srcbase","srcext","srcdir",
  }
  for _,k in ipairs(alias) do local v=t[k]; if v and not t[string.lower(k)] then t[string.lower(k)]=v end end
  for i=2,64 do if t["TRK"..i] and not t["trk"..i] then t["trk"..i]=t["TRK"..i] end end
  t.__trk_table = {}
  for i=1,64 do local v=t["trk"..i]; if v and v~="" then t.__trk_table[i]=v end end
  t.__chan_index = guess_channel_index(item, t)
  if not t.__chan_index then for i=1,64 do if t.__trk_table[i] then t.__chan_index=i break end end end
  if t.__chan_index and t.__trk_table[t.__chan_index] then t.__trk_name = t.__trk_table[t.__chan_index] end
  return t
end

-- ===== Template expansion =====
local function expand_template(tpl, fields, counter)
  local function repl(tok)
    local tkl = string.lower(tok)
    local digits = tkl:match("^counter:(%d+)$")
    if digits then
      local n = tonumber(digits) or 0
      local val = tostring(counter or 1)
      if n>0 then val = string.rep("0", math.max(0, n-#val))..val end
      return val
    end
    if tkl == "trk" then
      local idx = fields.__chan_index
      local name = idx and fields.__trk_table and fields.__trk_table[idx]
      if not name and fields.__trk_table then
        for i=1,64 do if fields.__trk_table[i] then name = fields.__trk_table[i] break end end
      end
      return trim(tostring(name or ""):gsub('[\\/:*?"<>|%c]','_'))
    end
    if tkl == "trkall" then
      local list = {}
      if fields.__trk_table then for i=1,20 do local v=fields.__trk_table[i]; if v and v~="" then list[#list+1]=v end end end
      return table.concat(list, "_")
    end
    local nidx = tkl:match("^trk(%d+)$")
    if nidx then
      local idx = tonumber(nidx)
      local v = (fields.__trk_table and fields.__trk_table[idx]) or fields["trk"..nidx] or fields["TRK"..nidx]
      return trim(tostring(v or ""):gsub('[\\/:*?"<>|%c]','_'))
    end
    local v = fields[tkl] or fields[tok] or ""
    return trim(tostring(v or ""):gsub('[\\/:*?"<>|%c]','_'))
  end
  local out = tpl or ""
  out = out:gsub("%${(.-)}", function(s) return repl(s) end)
  out = out:gsub("%$([%a%d]+)", function(s) return repl(s) end)
  out = out:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
  return out
end

-- ===== Selection & cache =====
local function get_item_guid(item) local _,guid=reaper.GetSetMediaItemInfo_String(item,"GUID","",false); return guid or "" end
local function get_selected_items_and_sig()
  local items, parts = {}, {}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do local it=reaper.GetSelectedMediaItem(0,i); items[#items+1]=it; parts[#parts+1]=get_item_guid(it) end
  return items, table.concat(parts,";")
end

-- ===== UI / State =====
local TAKE_TEMPLATE, NOTE_TEMPLATE = load_defaults()
local caret_take_char, caret_note_char = nil, nil
local preview_limit = 50
local preview_rows, status_msg = {}, ""
local close_after_apply = false
local active_box = "take"
local SCAN_CACHE = nil
local left_copy_text, right_copy_text = "", ""
local right_copy_fmt = "tab"
local RIGHT_SELECTABLE_VIEW = false
local SPLIT_RATIO = load_split_ratio()
local _drag_active = false
local _last_my = 0

-- ===== Token list =====
local TOKEN_LIST = {
  "$track","$filename","$srcfile","$srcbase","$srcext","$srcpath","$srcdir",
  "$samplerate","$channels","$length",
  "$project","$scene","$take","$tape",
  "$trk","$trkall","$trk1","$trk2","$trk3","$trk4","$trk5","$trk6","$trk7","$trk8",
  "$ubits","$framerate","$speed",
  "$date","$time","$year","$originationdate","$originationtime","$startoffset",
  "${counter:2}","${counter:3}"
}

-- ===== Token insertion (caret only) =====
local function append_token(tk)
  if active_box == "note" then
    local s, new_idx = safe_insert_token(NOTE_TEMPLATE, caret_note_char, tk)
    NOTE_TEMPLATE = s; caret_note_char = new_idx
  else
    local s, new_idx = safe_insert_token(TAKE_TEMPLATE, caret_take_char, tk)
    TAKE_TEMPLATE = s; caret_take_char = new_idx
  end
  if SCAN_CACHE then
    preview_rows = {}
    local shown = 0
    for i, e in ipairs(SCAN_CACHE.list) do
      if not preview_limit or shown < preview_limit then
        local newname = expand_template(TAKE_TEMPLATE, e.fields, i)
        local newnote = (NOTE_TEMPLATE ~= "" and expand_template(NOTE_TEMPLATE, e.fields, i)) or ""
        preview_rows[#preview_rows+1] = { current=e.current, newname=newname, newnote=newnote }
        shown = shown + 1
      end
    end
    right_copy_text = ""
  end
end

local function field_row_token(key, value)
  local tk = "$"..key
  if reaper.ImGui_SmallButton(ctx, tk .. "##field_" .. key) then append_token(tk) end
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_Text(ctx, tk..": "); reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextWrapped(ctx, tostring(value))
end

-- ===== CSV helpers =====
local function csv_escape(s) s=tostring(s or ""); if s:find('[,\r\n"]') then s='"'..s:gsub('"','""')..'"' end; return s end

-- ===== Build left/right copy texts =====
local function build_left_copy_text_from_fields(f)
  local lines = {}
  local function add(k, v) if v and v~="" then lines[#lines+1] = tostring(k).."\t"..tostring(v) end end
  local trk_auto = (f.__trk_name and (f.__trk_name.." (ch "..tostring(f.__chan_index or 0)..")")) or ""
  add("$trk", trk_auto)
  local list = {}; if f.__trk_table then for i=1,20 do local v=f.__trk_table[i]; if v and v~="" then list[#list+1]=v end end end
  if #list>0 then add("$trkall", table.concat(list, "_")) end
  local ordered = {
    "project","scene","take","tape","track",
    "filename","srcfile","srcbase","srcext","srcpath","srcdir","filepath",
    "samplerate","channels","length",
    "date","time","year","originationdate","originationtime","startoffset",
    "framerate","speed","ubits","originator","originatorreference","timereference",
    "trk1","trk2","trk3","trk4","trk5","trk6","trk7","trk8","trk9","trk10","trk11","trk12","trk13","trk14","trk15","trk16",
    "description"
  }
  for _,k in ipairs(ordered) do if f[k] ~= nil then add("$"..k, f[k]) end end
  return table.concat(lines, "\n")
end

local function build_right_copy_text_from_rows(fmt)
  local sep = (fmt == "csv") and "," or "\t"
  local out = {}
  local function add(...) local a={...}; if fmt=="csv" then for i=1,#a do a[i]=csv_escape(a[i]) end end; out[#out+1]=table.concat(a,sep) end
  add("#","Current Take Name","New Name","New Note")
  if preview_rows and #preview_rows>0 then
    for i,r in ipairs(preview_rows) do add(tostring(i), r.current or "", r.newname or "", r.newnote or "") end
  end
  return table.concat(out, "\n")
end

-- ===== Build preview (from selection) =====
local function scan_metadata()
  local items, sig = get_selected_items_and_sig()
  SCAN_CACHE = { sig=sig, list={}, map={} }
  local counter = 1
  for _, item in ipairs(items) do
    local take = get_active_take(item)
    local f = collect_metadata_for_item(item)
    local cur = "(no take)"
    if take then
      local _, cur_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
      cur = (cur_name and cur_name ~= "") and cur_name or "(unnamed)"
    end
    local guid = get_item_guid(item)
    local entry = { item=item, guid=guid, fields=f, current=cur, order=counter }
    SCAN_CACHE.list[#SCAN_CACHE.list+1] = entry
    SCAN_CACHE.map[guid] = entry
    counter = counter + 1
  end
  preview_rows = {}
  local shown = 0
  for i, e in ipairs(SCAN_CACHE.list) do
    if not preview_limit or shown < preview_limit then
      local newname = expand_template(TAKE_TEMPLATE, e.fields, i)
      local newnote = (NOTE_TEMPLATE ~= "" and expand_template(NOTE_TEMPLATE, e.fields, i)) or ""
      preview_rows[#preview_rows+1] = { current=e.current, newname=newname, newnote=newnote }
      shown = shown + 1
    end
  end
  right_copy_text = build_right_copy_text_from_rows(right_copy_fmt)
  local total = #items
  status_msg = (total==0) and "No items selected."
            or string.format("Scanned %d item(s). Preview shows first %d. (cached)", total, math.min(total, preview_limit))
end

local function recompute_preview_from_cache()
  if not SCAN_CACHE then preview_rows = {}; right_copy_text=""; status_msg="No cached metadata. Click 'Get Metadata (Preview)'."; return end
  preview_rows = {}
  local shown = 0
  for i, e in ipairs(SCAN_CACHE.list) do
    if not preview_limit or shown < preview_limit then
      local newname = expand_template(TAKE_TEMPLATE, e.fields, i)
      local newnote = (NOTE_TEMPLATE ~= "" and expand_template(NOTE_TEMPLATE, e.fields, i)) or ""
      preview_rows[#preview_rows+1] = { current=e.current, newname=newname, newnote=newnote }
      shown = shown + 1
    end
  end
  right_copy_text = build_right_copy_text_from_rows(right_copy_fmt)
  status_msg = string.format("Using cached metadata. Showing first %d.", shown)
end

-- ===== Apply =====
local function apply_renaming()
  local items, sig = get_selected_items_and_sig()
  if #items == 0 then status_msg="No items selected."; return end
  local can_use_cache = (SCAN_CACHE and SCAN_CACHE.sig == sig)
  reaper.Undo_BeginBlock()
  local renamed, noted, skipped, counter = 0, 0, 0, 1
  for _, item in ipairs(items) do
    local take = get_active_take(item)
    local fields
    if can_use_cache then local e=SCAN_CACHE.map[get_item_guid(item)]; fields = e and e.fields end
    if not fields then fields = collect_metadata_for_item(item) end
    if take then
      local name = expand_template(TAKE_TEMPLATE, fields, counter)
      if name ~= "" then reaper.GetSetMediaItemTakeInfo_String(take,"P_NAME",name,true); renamed=renamed+1 end
      if NOTE_TEMPLATE ~= "" then
        local note = expand_template(NOTE_TEMPLATE, fields, counter)
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", note, true); noted=noted+1
      end
    else
      if NOTE_TEMPLATE ~= "" then
        local note = expand_template(NOTE_TEMPLATE, fields, counter)
        reaper.GetSetMediaItemInfo_String(item, "P_NOTES", note, true); noted=noted+1
      else
        skipped=skipped+1
      end
    end
    counter = counter + 1
  end
  reaper.UpdateArrange()
  reaper.Undo_EndBlock(string.format("Rename %d take(s), update %d note(s), skipped %d (no take)", renamed, noted, skipped), -1)
  status_msg = string.format("Done: %d renamed, %d notes updated, %d skipped (no take). You can Undo/Redo.", renamed, noted, skipped)
  recompute_preview_from_cache()
end

-- ===== UI: token row =====
local function draw_token_row()
  local avail_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
  local x_used, pad, safety = 0, 14, 28
  for i, tk in ipairs(TOKEN_LIST) do
    local tw = select(1, reaper.ImGui_CalcTextSize(ctx, tk)) + pad
    if i > 1 and (x_used + tw) <= (avail_w - safety) then
      reaper.ImGui_SameLine(ctx); x_used = x_used + tw
    else
      x_used = tw
    end
    if reaper.ImGui_SmallButton(ctx, tk) then append_token(tk) end
  end
end

-- ===== UI: inputs =====
local function take_note_inputs()
  -- Take name
  reaper.ImGui_Text(ctx, "Take Name"); reaper.ImGui_SameLine(ctx); reaper.ImGui_TextDisabled(ctx, "(click to set caret; snaps out of tokens)")
  reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
  local changed_take, new_take = reaper.ImGui_InputText(ctx, "##take_name_tpl", TAKE_TEMPLATE)
  if reaper.ImGui_IsItemActive(ctx) then active_box = "take" end
  if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0) then
    local mx, _ = reaper.ImGui_GetMousePos(ctx); local rx, _ = reaper.ImGui_GetItemRectMin(ctx)
    local relx = mx - rx - 6; local raw = utf8_index_from_x(ctx, TAKE_TEMPLATE, relx)
    caret_take_char = snap_caret_out_of_token(TAKE_TEMPLATE, raw)
    caret_take_char = snap_caret_out_of_word(TAKE_TEMPLATE, caret_take_char, "right")
  end
  if changed_take then TAKE_TEMPLATE = new_take; if SCAN_CACHE then recompute_preview_from_cache() end end

  -- Item note
  reaper.ImGui_Text(ctx, "Item Note"); reaper.ImGui_SameLine(ctx); reaper.ImGui_TextDisabled(ctx, "(empty = skip)")
  reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
  local changed_note, new_note = reaper.ImGui_InputTextMultiline(ctx, "##item_note_tpl", NOTE_TEMPLATE, -FLT_MIN, 92)
  if reaper.ImGui_IsItemActive(ctx) then active_box = "note" end
  if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0) then
    local mx, my = reaper.ImGui_GetMousePos(ctx); local rx, ry = reaper.ImGui_GetItemRectMin(ctx)
    local line_h = reaper.ImGui_GetTextLineHeight(ctx); local relx = mx - rx - 6; local rely = my - ry - 6
    local lines = {}; for line in (tostring(NOTE_TEMPLATE or "").."\n"):gmatch("(.-)\n") do lines[#lines+1]=line end; if #lines==0 then lines[1]="" end
    local li = math.floor(rely / line_h) + 1; if li<1 then li=1 end; if li>#lines then li=#lines end
    local col = utf8_index_from_x(ctx, lines[li], relx)
    local idx = 0; for i=1,li-1 do idx = idx + utf8_len(lines[i]) + 1 end; idx = idx + col
    caret_note_char = snap_caret_out_of_token(NOTE_TEMPLATE, idx)
    caret_note_char = snap_caret_out_of_word(NOTE_TEMPLATE, caret_note_char, "right")
  end
  if changed_note then NOTE_TEMPLATE = new_note; if SCAN_CACHE then recompute_preview_from_cache() end end
end

-- ===== Top bar (Undo/Redo only) =====
local function draw_top_bar()
  if reaper.ImGui_Button(ctx, "Undo", 80, 0) then reaper.Undo_DoUndo2(0) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Redo", 80, 0) then reaper.Undo_DoRedo2(0) end
end


-- ===== View/Copy split panes =====
local function draw_view_pane(available_h)
  local split_thickness = 6.0
  local view_h = math.max(150, math.floor(available_h * SPLIT_RATIO) - math.floor(split_thickness/2))
  local copy_h = math.max(120, available_h - view_h - split_thickness)

  -- Top view child
  BeginChildSafe("ViewPane", -1, view_h, true)
    local splitFlags = TF('ImGui_TableFlags_Resizable') | TF('ImGui_TableFlags_BordersInnerV')
    if reaper.ImGui_BeginTable(ctx, "MainSplit", 2, splitFlags) then
      reaper.ImGui_TableSetupColumn(ctx, "Fields", TF('ImGui_TableColumnFlags_WidthStretch'), 0.5)
      reaper.ImGui_TableSetupColumn(ctx, "Preview", TF('ImGui_TableColumnFlags_WidthStretch'), 0.5)
      reaper.ImGui_TableNextRow(ctx)

      -- Left panel
      reaper.ImGui_TableSetColumnIndex(ctx, 0)
      reaper.ImGui_Text(ctx, "Detected fields (from FIRST currently-selected item):")
      reaper.ImGui_Separator(ctx)
      local first = reaper.GetSelectedMediaItem(0, 0)
      if not first then
        reaper.ImGui_TextDisabled(ctx, "No items selected. Click Preview or just Apply.")
        left_copy_text = ""
      else
        local f = collect_metadata_for_item(first)
        left_copy_text = build_left_copy_text_from_fields(f)

        do
          local label = "$trk"
          if reaper.ImGui_SmallButton(ctx, label .. "##field") then append_token(label) end
          reaper.ImGui_SameLine(ctx); reaper.ImGui_Text(ctx, label..": "); reaper.ImGui_SameLine(ctx)
          local auto = (f.__trk_name and (f.__trk_name.." (ch "..tostring(f.__chan_index or 0)..")")) or "(auto)"
          reaper.ImGui_TextWrapped(ctx, auto)
        end
        do
          local label = "$trkall"
          local preview_all = {}; if f.__trk_table then for i=1,20 do local v=f.__trk_table[i]; if v and v~="" then preview_all[#preview_all+1]=v end end end
          if reaper.ImGui_SmallButton(ctx, label .. "##field") then append_token(label) end
          reaper.ImGui_SameLine(ctx); reaper.ImGui_Text(ctx, label..": "); reaper.ImGui_SameLine(ctx)
          reaper.ImGui_TextWrapped(ctx, table.concat(preview_all, "_"))
        end
        reaper.ImGui_Separator(ctx)
        local ordered = {
          "project","scene","take","tape","track",
          "filename","srcfile","srcbase","srcext","srcpath","srcdir","filepath",
          "samplerate","channels","length",
          "date","time","year","originationdate","originationtime","startoffset",
          "framerate","speed","ubits","originator","originatorreference","timereference",
          "trk1","trk2","trk3","trk4","trk5","trk6","trk7","trk8","trk9","trk10","trk11","trk12","trk13","trk14","trk15","trk16",
          "description"
        }
        for _,k in ipairs(ordered) do if f[k] ~= nil then field_row_token(k, f[k]) end end
      end

      -- Right panel
      reaper.ImGui_TableSetColumnIndex(ctx, 1)
      reaper.ImGui_Text(ctx, "Preview (cached; click 'Get Metadata' to refresh selection):")
      reaper.ImGui_Separator(ctx)

      if RIGHT_SELECTABLE_VIEW then
        right_copy_text = build_right_copy_text_from_rows(right_copy_fmt)
        if reaper.ImGui_Button(ctx, "Copy preview table (right)", 230, 0) then reaper.ImGui_SetClipboardText(ctx, right_copy_text or "") end
        reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
        reaper.ImGui_InputTextMultiline(ctx, "##right_sel_view", right_copy_text or "", -FLT_MIN, 240, reaper.ImGui_InputTextFlags_ReadOnly())
      else
        local prevFlags = TF('ImGui_TableFlags_Borders') | TF('ImGui_TableFlags_RowBg')
        if reaper.ImGui_BeginTable(ctx, "PreviewTable", 4, prevFlags) then
          reaper.ImGui_TableSetupColumn(ctx, "#", TF('ImGui_TableColumnFlags_WidthFixed'), 36)
          reaper.ImGui_TableSetupColumn(ctx, "Current Take Name")
          reaper.ImGui_TableSetupColumn(ctx, "New Name")
          reaper.ImGui_TableSetupColumn(ctx, "New Note")
          reaper.ImGui_TableHeadersRow(ctx)
          if not SCAN_CACHE or #preview_rows == 0 then
            reaper.ImGui_TableNextRow(ctx)
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "-")
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "No cache. Click 'Get Metadata (Preview)'.")
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "")
            reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextDisabled(ctx, "")
          else
            for i, row in ipairs(preview_rows) do
              reaper.ImGui_TableNextRow(ctx)
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(i))
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, row.current ~= "" and row.current or "(unnamed)")
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, row.newname ~= "" and row.newname or "(empty)")
              reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, row.newnote ~= "" and row.newnote or "")
            end
          end
          reaper.ImGui_EndTable(ctx)
        end
      end

      reaper.ImGui_EndTable(ctx)
    end
  reaper.ImGui_EndChild(ctx)

  -- Splitter (drag to resize)
  reaper.ImGui_InvisibleButton(ctx, "VSplit", -1, split_thickness)
  if reaper.ImGui_IsItemActive(ctx) then
    local _, my = reaper.ImGui_GetMousePos(ctx)
    if not _drag_active then _drag_active = true; _last_my = my
    else
      local dy = (my - _last_my)
      local total = view_h + copy_h + split_thickness
      if total > 0 then
        SPLIT_RATIO = math.min(0.9, math.max(0.1, SPLIT_RATIO + (dy / total)))
        save_split_ratio(SPLIT_RATIO)
      end
      _last_my = my
    end
  else
    _drag_active = false
  end

  -- Bottom copy child
  BeginChildSafe("CopyPane", -1, copy_h, true)
    local copyFlags = TF('ImGui_TableFlags_Resizable') | TF('ImGui_TableFlags_BordersInnerV')
    if reaper.ImGui_BeginTable(ctx, "CopySplit", 2, copyFlags) then
      reaper.ImGui_TableSetupColumn(ctx, "CopyLeft", TF('ImGui_TableColumnFlags_WidthStretch'), 0.5)
      reaper.ImGui_TableSetupColumn(ctx, "CopyRight", TF('ImGui_TableColumnFlags_WidthStretch'), 0.5)
      reaper.ImGui_TableNextRow(ctx)

      -- Copy left (metadata)
      reaper.ImGui_TableSetColumnIndex(ctx, 0)
      reaper.ImGui_Text(ctx, "Copy metadata")
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "Copy##meta") then
        reaper.ImGui_SetClipboardText(ctx, left_copy_text or "")
      end
      reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
      reaper.ImGui_InputTextMultiline(ctx, "##left_copy_box", left_copy_text or "", -FLT_MIN, copy_h - 48, reaper.ImGui_InputTextFlags_ReadOnly())

      -- Copy right (preview table)
      reaper.ImGui_TableSetColumnIndex(ctx, 1)
      reaper.ImGui_Text(ctx, "Copy preview table:")
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "Tab##copytable") then
        local text = build_right_copy_text_from_rows("tab")
        reaper.ImGui_SetClipboardText(ctx, text or "")
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_SmallButton(ctx, "CSV##copytable") then
        local text = build_right_copy_text_from_rows("csv")
        reaper.ImGui_SetClipboardText(ctx, text or "")
      end
      reaper.ImGui_SetNextItemWidth(ctx, -FLT_MIN)
      right_copy_text = (SCAN_CACHE and #preview_rows>0) and build_right_copy_text_from_rows(right_copy_fmt) or ""
      reaper.ImGui_InputTextMultiline(ctx, "##right_copy_box", right_copy_text or "", -FLT_MIN, copy_h - 48, reaper.ImGui_InputTextFlags_ReadOnly())

      reaper.ImGui_EndTable(ctx)
    end
  reaper.ImGui_EndChild(ctx)
end

-- ===== Main loop =====
local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, WIN_W, WIN_H, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, 'Rename Active Take from Metadata', true, TF('ImGui_WindowFlags_NoScrollbar'))
  if visible then

    -- ESC to Cancel/Close (press Esc anywhere to close the window)
    if reaper.ImGui_IsWindowFocused(ctx, TF('ImGui_FocusedFlags_RootAndChildWindows')) 
      and reaper.ImGui_IsKeyPressed(ctx, KEY_ESC, false) then
      close_after_apply = true
    end



    -- Top row: Undo / Redo / Preview first
    draw_top_bar()
    reaper.ImGui_Separator(ctx)

    -- Tokens & inputs
    reaper.ImGui_Text(ctx, "Template tokens (click to insert at caret):")
    draw_token_row()
    reaper.ImGui_Separator(ctx)
    take_note_inputs()

    -- Template tools
    if reaper.ImGui_Button(ctx, "Clear", 80, 0) then
      if active_box == "note" then NOTE_TEMPLATE = "" else TAKE_TEMPLATE = "" end
      if SCAN_CACHE then recompute_preview_from_cache() end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Default", 90, 0) then
      local t, n2 = load_defaults(); TAKE_TEMPLATE, NOTE_TEMPLATE = t, n2; if SCAN_CACHE then recompute_preview_from_cache() end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Save", 80, 0) then save_defaults(TAKE_TEMPLATE, NOTE_TEMPLATE) end

    -- Action row: left = Get Metadata, right = Apply buttons (no status text)
    do
      local full_w = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
      local left_btn_w = 210
      local btn_w = 150*3 + 16*2

      -- Left button
      if reaper.ImGui_Button(ctx, "Get Metadata (Preview)", left_btn_w, 28) then scan_metadata() end

      -- Right-aligned Apply buttons
      local right_x = full_w - btn_w
      if right_x > (left_btn_w + 12) then
        reaper.ImGui_SameLine(ctx, right_x)
      else
        reaper.ImGui_NewLine(ctx)
        local fw2 = select(1, reaper.ImGui_GetContentRegionAvail(ctx))
        reaper.ImGui_SameLine(ctx, math.max(0, fw2 - btn_w))
      end
      if reaper.ImGui_Button(ctx, "Apply", 150, 28) then apply_renaming() end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Apply & Close", 150, 28) then apply_renaming(); close_after_apply = true end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel", 150, 28) then close_after_apply = true end
    end


    -- Status row: Selected / Scanned / Cached / Preview first (with input)
do
  -- live selection and cache state
  local nsel = reaper.CountSelectedMediaItems(0)
  local scanned = (SCAN_CACHE and #SCAN_CACHE.list) or 0
  local _, sig = get_selected_items_and_sig()
  local cached_ok = (SCAN_CACHE and SCAN_CACHE.sig == sig)

  local flags = TF('ImGui_TableFlags_SizingFixedFit')
  if reaper.ImGui_BeginTable(ctx, "StatusRow", 4, flags) then
    reaper.ImGui_TableSetupColumn(ctx, "Sel")
    reaper.ImGui_TableSetupColumn(ctx, "Scan")
    reaper.ImGui_TableSetupColumn(ctx, "Cache")
    reaper.ImGui_TableSetupColumn(ctx, "Prev")

    reaper.ImGui_TableNextRow(ctx)

    -- Selected
    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, ("Selected: %d"):format(nsel))

    -- Scanned
    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, ("Scanned: %d"):format(scanned))

    -- Cached state
    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, cached_ok and "Cached: Yes" or "Cached: No")
    -- 想顯示 "Catched" 就把上行字串改成 "Catched: Yes/No"

    -- Preview first input (moved here)
    reaper.ImGui_TableNextColumn(ctx)
    reaper.ImGui_Text(ctx, "Preview first"); reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, 90)
    local chg, n = reaper.ImGui_InputInt(ctx, "##preview_limit", preview_limit)
    if chg then
      preview_limit = math.max(1, math.min(10000, n or preview_limit))
      if SCAN_CACHE then recompute_preview_from_cache() end
    end

    reaper.ImGui_EndTable(ctx)
  end
end



    -- View/Copy split panes
    reaper.ImGui_Separator(ctx)
    local _, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    draw_view_pane(avail_h)

    reaper.ImGui_End(ctx)
  end

  if (not open) or close_after_apply then
    if reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
    return
  else
    reaper.defer(loop)
  end
end

reaper.defer(loop)
