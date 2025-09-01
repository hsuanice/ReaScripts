--[[
@description hsuanice Metadata Read (reader / normalizer / tokens)
@version 0.1.0
@author hsuanice
@noindex
@about
  Read-only metadata utilities:
  - Unwrap SECTION to real parent source
  - Read iXML TRACK_LIST (Wave Agent style)
  - Fallback parse sTRK#=Name from BWF/Description (EdiLoad split)
  - Interleave index ↔ recorder channel mapping
  - Token expansion for rename/export
]]

local M = {}
M.VERSION = "0.1.0"

-- ====== Source / file helpers ======
local function stype(src) local ok,t=pcall(reaper.GetMediaSourceType,src,""); return ok and t or "" end

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

-- ====== cache for GetMediaFileMetadata ======
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

-- ====== readers (iXML first, then BWF/Description fallback) ======
function M.read_ixml_tracklist(src)
  local tracks, trk_map = {}, {}
  local cnt = tonumber(meta(src, "IXML:TRACK_LIST:TRACK_COUNT") or 0) or 0
  for i=1,cnt do
    local suf = (i>1) and (":"..i) or ""
    local ch  = tonumber(meta(src, "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX"..suf) or "")
    local nm  = meta(src, "IXML:TRACK_LIST:TRACK:NAME"..suf)
    if ch and ch>=1 then
      tracks[#tracks+1] = { channel_index=i, channel=ch, name=nm or "" }
      trk_map[ch] = nm or ""
    end
  end
  return tracks, trk_map
end

function M.read_bwf_trk_pairs(src)
  local t = {}
  local d1 = meta(src, "BWF:Description")
  local d2 = meta(src, "Description")
  local blob = ((d1 or "").."\n"..(d2 or ""))
  for ch, name in blob:gmatch("sTRK(%d+)%s*=%s*([^\r\n]+)") do
    t[tonumber(ch)] = name
  end
  return t
end

-- ====== interleave / mapping ======
function M.guess_interleave_index(item)
  local tk = item and reaper.GetActiveTake(item)
  local cm = tk and reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0
  if cm >= 3 and cm <= 66 then return math.floor(cm - 2) end
  return nil
end

local function build_by_interleave(fields)
  if fields.__trk_by_interleave then return fields.__trk_by_interleave end
  local list, have_ixml = {}, false
  if fields.__ixml_tracks then
    for _, trk in ipairs(fields.__ixml_tracks) do
      local idx = tonumber(trk.channel_index)
      if idx and idx>=1 then list[idx] = trk.name or ""; have_ixml = true end
    end
  end
  if not have_ixml and fields.__trk_map then
    local a = {}
    for ch,name in pairs(fields.__trk_map) do a[#a+1] = {ch=ch, name=name} end
    table.sort(a, function(x,y) return x.ch < y.ch end)
    for i,e in ipairs(a) do list[i] = e.name end
  end
  fields.__trk_by_interleave = list
  return list
end

function M.resolve_trk_by_interleave(fields, idx)
  local list = build_by_interleave(fields)
  if idx and list[idx] and list[idx] ~= "" then
    local ch
    for c,n in pairs(fields.__trk_map or {}) do if n == list[idx] then ch = c break end end
    return list[idx], ch
  end
  for i=1,#list do
    if list[i] and list[i] ~= "" then
      local ch
      for c,n in pairs(fields.__trk_map or {}) do if n == list[i] then ch = c break end end
      return list[i], ch
    end
  end
  return "", nil
end

-- ====== collect normalized fields for an item ======
function M.collect_fields(item)
  local t = {}
  local tk  = item and reaper.GetActiveTake(item)
  local src = tk and M.unwrap_source(tk)
  if not src then return t end

  local tracks, trk_map = M.read_ixml_tracklist(src)
  local pairs_desc      = M.read_bwf_trk_pairs(src)

  t.__ixml_tracks = (#tracks>0) and tracks or nil
  t.__trk_map     = (next(trk_map) and trk_map) or ((next(pairs_desc) and pairs_desc) or nil)
  t.srcfile       = (M.source_file_path(src):match("([^/\\]+)$")) or ""
  t.take_name     = select(2, reaper.GetSetMediaItemTakeInfo_String(tk,"P_NAME","",false)) or ""
  t.note          = select(2, reaper.GetSetMediaItemInfo_String(item,"P_NOTES","",false)) or ""
  return t
end

-- ====== (optional) token expansion placeholder ======
function M.expand(template, fields)
  -- TODO: 搬你的 Rename token 引擎進來
  return (template or "")
end

return M
