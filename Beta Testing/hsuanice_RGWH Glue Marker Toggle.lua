-- @description hsuanice_RGWH Glue Marker Toggle
-- @version 250922_0106 can hide but can't show
-- @author hsuanice
-- @about Toggle visibility of take markers whose names start with "Glue:".
--         Uses project ExtState (NS="RGWH"):
--           GLUE_MARKERS_VIS  : "1" (visible) | "0" (hidden)
--           GLUE_MARKERS_CACHE: JSON { "<takeGUID>": [ {pos,name,color,flags}, ... ] }
-- @changelog
--   1.0.0 - Initial release: hide/show with built-in sweep-new on show.

local r = reaper

----------------------------------------------------------------
-- tiny JSON (encode/decode) - sufficient for our cache schema
----------------------------------------------------------------
local function is_array(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for k,_ in pairs(t) do
    if type(k) ~= "number" then return false end
    if k > n then n = k end
  end
  for i=1,n do
    if t[i] == nil then return false end
  end
  return true
end

local function json_escape_str(s)
  s = s:gsub('\\','\\\\'):gsub('"','\\"')
  s = s:gsub('\b','\\b'):gsub('\f','\\f'):gsub('\n','\\n'):gsub('\r','\\r'):gsub('\t','\\t')
  return '"'..s..'"'
end

local function json_encode(v)
  local tv = type(v)
  if tv == "nil" then return "null"
  elseif tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return tostring(v)
  elseif tv == "boolean" then return v and "true" or "false"
  elseif tv == "string" then return json_escape_str(v)
  elseif tv == "table" then
    if is_array(v) then
      local parts = {}
      for i=1,#v do parts[#parts+1] = json_encode(v[i]) end
      return "["..table.concat(parts,",").."]"
    else
      local parts = {}
      for k,val in pairs(v) do
        parts[#parts+1] = json_escape_str(tostring(k))..":"..json_encode(val)
      end
      return "{"..table.concat(parts,",").."}"
    end
  else
    return "null"
  end
end

local function json_decode(str)
  local pos = 1
  local function skip_ws()
    local _,e = str:find("^[ \n\r\t]*", pos)
    pos = (e or pos-1) + 1
  end
  local function parse_value()
    skip_ws()
    local c = str:sub(pos,pos)
    if c == "{" then
      pos = pos + 1; skip_ws()
      local obj = {}
      if str:sub(pos,pos) == "}" then pos = pos + 1; return obj end
      while true do
        skip_ws()
        if str:sub(pos,pos) ~= '"' then error("JSON: expected string key at "..pos) end
        local key = parse_string()
        skip_ws()
        if str:sub(pos,pos) ~= ":" then error("JSON: expected ':' at "..pos) end
        pos = pos + 1
        local val = parse_value()
        obj[key] = val
        skip_ws()
        local ch = str:sub(pos,pos)
        if ch == "}" then pos = pos + 1; break
        elseif ch == "," then pos = pos + 1
        else error("JSON: expected ',' or '}' at "..pos) end
      end
      return obj
    elseif c == "[" then
      pos = pos + 1; skip_ws()
      local arr = {}
      if str:sub(pos,pos) == "]" then pos = pos + 1; return arr end
      local i = 1
      while true do
        arr[i] = parse_value(); i = i + 1
        skip_ws()
        local ch = str:sub(pos,pos)
        if ch == "]" then pos = pos + 1; break
        elseif ch == "," then pos = pos + 1
        else error("JSON: expected ',' or ']' at "..pos) end
      end
      return arr
    elseif c == '"' then
      return parse_string()
    elseif c:match("[%d%-]") then
      return parse_number()
    else
      local lit = str:sub(pos, pos+4)
      if str:sub(pos,pos+3) == "true" then pos = pos + 4; return true end
      if str:sub(pos,pos+4) == "false" then pos = pos + 5; return false end
      if str:sub(pos,pos+3) == "null" then pos = pos + 4; return nil end
      error("JSON: unexpected token at "..pos)
    end
  end
  function parse_string()
    local i = pos + 1
    local out = {}
    while i <= #str do
      local ch = str:sub(i,i)
      if ch == '"' then
        local s = table.concat(out)
        pos = i + 1
        return s
      elseif ch == "\\" then
        local nxt = str:sub(i+1,i+1)
        if nxt == '"' then out[#out+1] = '"' ; i = i + 2
        elseif nxt == "\\" then out[#out+1] = "\\"; i = i + 2
        elseif nxt == "/" then out[#out+1] = "/"; i = i + 2
        elseif nxt == "b" then out[#out+1] = "\b"; i = i + 2
        elseif nxt == "f" then out[#out+1] = "\f"; i = i + 2
        elseif nxt == "n" then out[#out+1] = "\n"; i = i + 2
        elseif nxt == "r" then out[#out+1] = "\r"; i = i + 2
        elseif nxt == "t" then out[#out+1] = "\t"; i = i + 2
        elseif nxt == "u" then
          local hex = str:sub(i+2,i+5)
          local cp = tonumber(hex,16)
          if not cp then error("JSON: invalid \\u escape at "..i) end
          if cp <= 0x7F then out[#out+1]=string.char(cp)
          elseif cp <= 0x7FF then
            out[#out+1]=string.char(0xC0+math.floor(cp/0x40))
            out[#out+1]=string.char(0x80+(cp%0x40))
          elseif cp <= 0xFFFF then
            out[#out+1]=string.char(0xE0+math.floor(cp/0x1000))
            out[#out+1]=string.char(0x80+math.floor((cp%0x1000)/0x40))
            out[#out+1]=string.char(0x80+(cp%0x40))
          else
            -- outside BMP (rare in marker names) – simplify to '?'
            out[#out+1] = "?"
          end
          i = i + 6
        else
          error("JSON: invalid escape at "..i)
        end
      else
        out[#out+1] = ch
        i = i + 1
      end
    end
    error("JSON: unterminated string starting at "..pos)
  end
  function parse_number()
    local s, e = str:find("^%-?%d+%.?%d*[eE]?[+%-]?%d*", pos)
    if not s then error("JSON: bad number at "..pos) end
    local num = tonumber(str:sub(s,e))
    pos = e + 1
    return num
  end
  local ok, res = pcall(parse_value)
  if ok then return res end
  return nil -- on error, return nil (we'll fallback to {})
end

----------------------------------------------------------------
-- ExtState helpers
----------------------------------------------------------------
local NS = "RGWH"
local KEY_VIS   = "GLUE_MARKERS_VIS"
local KEY_CACHE = "GLUE_MARKERS_CACHE"

local function proj_get()
  return 0 -- current project
end

local function get_vis()
  local rv, val = r.GetProjExtState(proj_get(), NS, KEY_VIS)
  if rv == 0 or val == "" then return "1" end -- default visible
  return val
end

local function set_vis(v)
  r.SetProjExtState(proj_get(), NS, KEY_VIS, v)
end

local function load_cache()
  local rv, blob = r.GetProjExtState(proj_get(), NS, KEY_CACHE)
  if rv == 0 or blob == "" then return {} end
  local t = json_decode(blob)
  if type(t) ~= "table" then return {} end
  return t
end

local function save_cache(t)
  r.SetProjExtState(proj_get(), NS, KEY_CACHE, json_encode(t or {}))
end

----------------------------------------------------------------
-- Utilities: project enumeration, take GUID, marker ops
----------------------------------------------------------------
local function for_each_take(fn)
  local trN = r.CountTracks(0)
  for ti=0,trN-1 do
    local tr = r.GetTrack(0, ti)
    local itN = r.CountTrackMediaItems(tr)
    for ii=0,itN-1 do
      local it = r.GetTrackMediaItem(tr, ii)
      local tkN = r.GetMediaItemNumTakes(it)
      for ki=0,tkN-1 do
        local tk = r.GetMediaItemTake(it, ki)
        if tk then fn(tk, it, tr) end
      end
    end
  end
end

local function take_guid(tk)
  local _,guid = r.GetSetMediaItemTakeInfo_String(tk, "GUID", "", false)
  return guid
end

local function count_glue_markers_on_take(tk)
  local n = r.GetNumTakeMarkers(tk) or 0
  local c = 0
  for i=0,n-1 do
    local _, name = r.GetTakeMarker(tk, i)
    if name and name:sub(1,5) == "Glue:" then c = c + 1 end
  end
  return c
end

local function clamp_to_item_len(tk, pos)
  local it = r.GetMediaItemTake_Item(tk)
  local len = (it and r.GetMediaItemInfo_Value(it, "D_LENGTH")) or 0
  if pos < 0 then pos = 0 end
  if len > 0 and pos > len then pos = len end
  return pos
end

local function find_take_by_guid(want)
  local hit = nil
  for_each_take(function(tk)
    if take_guid(tk) == want then hit = tk end
  end)
  return hit
end

local function marker_exists_in_cache(cache, guid, pos, name)
  local list = cache[guid]
  if not list then return false end
  for _,m in ipairs(list) do
    if m.name == name and math.abs((m.pos or 0) - (pos or 0)) < 1e-6 then
      return true
    end
  end
  return false
end

----------------------------------------------------------------
-- Core ops: hide, sweep_new, show
----------------------------------------------------------------
local function hide_all_into_cache()
  local cache = {}
  local del_count = 0
  for_each_take(function(tk)
    local nmark = r.GetNumTakeMarkers(tk) or 0
    if nmark > 0 then
      local gid = take_guid(tk)
      for i = nmark-1, 0, -1 do
        local _, name, pos, color, _, flags = r.GetTakeMarker(tk, i)
        if name and name:sub(1,5) == "Glue:" then
          cache[gid] = cache[gid] or {}
          table.insert(cache[gid], {
            pos   = pos or 0,
            name  = name or "Glue:",
            color = color or 0,
            flags = flags or 0,
          })
          r.DeleteTakeMarker(tk, i)
          del_count = del_count + 1
        end
      end
    end
  end)
  save_cache(cache)
  set_vis("0")
  return del_count, cache
end

local function sweep_new_into_cache()
  local cache = load_cache()
  local added, deleted = 0, 0
  for_each_take(function(tk)
    local gid = take_guid(tk)
    local n = r.GetNumTakeMarkers(tk) or 0
    if n > 0 then
      for i = n-1, 0, -1 do
        local _, name, pos, color, _, flags = r.GetTakeMarker(tk, i)
        if name and name:sub(1,5) == "Glue:" then
          if not marker_exists_in_cache(cache, gid, pos, name) then
            cache[gid] = cache[gid] or {}
            table.insert(cache[gid], {
              pos   = pos or 0,
              name  = name or "Glue:",
              color = color or 0,
              flags = flags or 0,
            })
            added = added + 1
          end
          r.DeleteTakeMarker(tk, i)
          deleted = deleted + 1
        end
      end
    end
  end)
  save_cache(cache)
  return added, deleted, cache
end

local function show_from_cache()
  local cache = load_cache()
  local restored = 0
  for gid, list in pairs(cache) do
    local tk = find_take_by_guid(gid)
    if tk and type(list) == "table" then
      for _,m in ipairs(list) do
        local p = clamp_to_item_len(tk, tonumber(m.pos) or 0)
        -- Basic 4-arg SetTakeMarker (name/pos/color)。若你的 REAPER 版支持 flags，可改成：
        -- r.SetTakeMarker(tk, -1, m.name or "Glue:", p, tonumber(m.color) or 0, tonumber(m.flags) or 0)
        r.SetTakeMarker(tk, -1, m.name or "Glue:", p, tonumber(m.color) or 0)
        restored = restored + 1
      end
    else
      -- take 不在了，清掉這組垃圾
      cache[gid] = nil
    end
  end
  -- 顯示之後，把快取清空（亦可選擇保留一份）
  save_cache({})
  set_vis("1")
  return restored
end

----------------------------------------------------------------
-- Main (toggle)
----------------------------------------------------------------
r.Undo_BeginBlock()
local vis = get_vis()
if vis == "1" then
  local del, _ = hide_all_into_cache()
  r.UpdateArrange()
  r.Undo_EndBlock(("RGWH - Glue Marker Toggle: Hide (%d deleted)"):format(del), -1)
else
  local added, deleted, _ = sweep_new_into_cache()
  local restored = show_from_cache()
  r.UpdateArrange()
  r.Undo_EndBlock(("RGWH - Glue Marker Toggle: Show (sweep+%d add, %d del, %d restored)"):format(added, deleted, restored), -1)
end
