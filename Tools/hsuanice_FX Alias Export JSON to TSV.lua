--[[
@description FX Alias Export - Convert FX Alias JSON to TSV
@version 0.1.0
@author hsuanice
@provides
  [main] Tools/hsuanice_FX Alias Export JSON to TSV.lua
@about
  Export Settings/fx_alias.json to Settings/fx_alias.tsv for easy editing in Excel/Numbers/Sheets.

  Part of AudioSweet ReaImGui Tools suite.

@changelog
  0.1.0 (2025-12-12) [internal: v251030.1600]
    - Initial Public Beta Release
    - FX Alias JSON to TSV exporter tool featuring:
      • Converts fx_alias.json to fx_alias.tsv format
      • Enables easy editing in Excel/Numbers/Google Sheets
      • Accessible from AudioSweet ReaImGui: Settings → FX Alias Tools → Export JSON to TSV
      • Part of FX Alias workflow: Build → Export → Edit → Update
    - Initial release [internal: v251007]
]]--

-- ========== Minimal JSON (dkjson subset) ==========
local json = (function()
  -- dkjson v2.5 (trimmed)
  local json = { version = "dkjson 2.5" }
  local encode

  local function escape_char(c)
    local x = string.byte(c)
    local esc = {
      [8]='\\b',[9]='\\t',[10]='\\n',[12]='\\f',[13]='\\r',
      [34]='\\"',[92]='\\\\'
    }
    local e = esc[x]
    if e then return e end
    if x < 32 then return string.format("\\u%04x", x) end
    return c
  end

  local function is_array(tbl)
    local n = 0
    for k,v in pairs(tbl) do
      if type(k) ~= "number" then return false end
      if k > n then n = k end
    end
    for i = 1, n do
      if tbl[i] == nil then return false end
    end
    return true, n
  end

  function encode(v)
    local t = type(v)
    if t == "nil" then
      return "null"
    elseif t == "number" then
      return string.format("%.14g", v)
    elseif t == "boolean" then
      return v and "true" or "false"
    elseif t == "string" then
      return '"' .. v:gsub('[%z\1-\31\\"]', escape_char) .. '"'
    elseif t == "table" then
      local arr, n = is_array(v)
      if arr then
        local out = {}
        for i=1,n do out[#out+1] = encode(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
      else
        local out = {}
        for k,val in pairs(v) do
          out[#out+1] = encode(tostring(k)) .. ":" .. encode(val)
        end
        return "{" .. table.concat(out, ",") .. "}"
      end
    else
      return 'null'
    end
  end

  local function decode_error(str, i, msg)
    error(string.format("JSON decode error at %d: %s", i, msg))
  end

  local function skip_whitespace(str, i)
    local _, j = str:find("^[ \n\r\t]*", i)
    return (j or i-1) + 1
  end

  local function parse_value(str, i)
    i = skip_whitespace(str, i)
    local c = str:sub(i,i)
    if c == "{" then
      local obj = {}
      i = i + 1
      i = skip_whitespace(str, i)
      if str:sub(i,i) == "}" then return obj, i+1 end
      while true do
        local key; key, i = parse_value(str, i)
        if type(key) ~= "string" then decode_error(str,i,"Expected string for object key") end
        i = skip_whitespace(str, i)
        if str:sub(i,i) ~= ":" then decode_error(str,i,"Expected ':' after key") end
        -- 這裡要直接解析 value，位置索引給下一輪用
        local val; val, i = parse_value(str, i+1)
        obj[key] = val
        i = skip_whitespace(str,i)
        local ch = str:sub(i,i)
        if ch == "}" then return obj, i+1 end
        if ch ~= "," then decode_error(str,i,"Expected ',' or '}' in object") end
        i = i + 1
      end
    elseif c == "[" then
      local arr = {}
      i = i + 1
      i = skip_whitespace(str,i)
      if str:sub(i,i) == "]" then return arr, i+1 end
      while true do
        local val; val, i = parse_value(str, i)
        arr[#arr+1] = val
        i = skip_whitespace(str,i)
        local ch = str:sub(i,i)
        if ch == "]" then return arr, i+1 end
        if ch ~= "," then decode_error(str,i,"Expected ',' or ']' in array") end
        i = i + 1
      end
    elseif c == '"' then
      local j = i+1
      local out = {}
      while true do
        local ch = str:sub(j,j)
        if ch == "" then decode_error(str,j,"Unclosed string") end
        if ch == '"' then
          return table.concat(out), j+1
        elseif ch == "\\" then
          local e = str:sub(j+1,j+1)
          if e == "u" then
            local hex = str:sub(j+2, j+5)
            if not hex:match("%x%x%x%x") then decode_error(str,j,"Invalid \\u escape") end
            local cp = tonumber(hex,16)
            -- Basic BMP only
            out[#out+1] = utf8.char(cp)
            j = j + 6
          else
            local map = { b="\b", f="\f", n="\n", r="\r", t="\t", ['"']='"', ['\\']='\\', ['/']='/' }
            out[#out+1] = map[e] or e
            j = j + 2
          end
        else
          out[#out+1] = ch
          j = j + 1
        end
      end
    else
      local lit = str:sub(i,i+3)
      if lit == "true" then return true, i+4 end
      lit = str:sub(i,i+4)
      if lit == "false" then return false, i+5 end
      lit = str:sub(i,i+3)
      if lit == "null" then return nil, i+4 end
      local num = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
      if num and #num>0 then return tonumber(num), i + #num end
      decode_error(str, i, "Unexpected char '"..c.."'")
    end
  end

  function json.decode(str)
    local ok, res = pcall(function()
      local v, i = parse_value(str, 1)
      i = skip_whitespace(str, i)
      return v
    end)
    if ok then return res else return nil, res end
  end

  json.encode = encode
  return json
end)()
-- ========== /JSON ==========

local function resource_path()
  return reaper.GetResourcePath()
end

local function settings_dir()
  return resource_path().."/Scripts/hsuanice Scripts/Settings"
end

local function ensure_dir(path)
  -- (REAPER/Lua 沒有跨平台 mkdir；這裡假設你已建立 Settings 夾)
  return true
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function write_file(path, text)
  local f = io.open(path, "wb")
  if not f then return false, "open failed" end
  f:write(text or ""); f:close()
  return true
end

local function tsv_escape(s)
  if not s or s=="" then return "" end
  -- 以單行為主：替換換行與 tab
  s = s:gsub("\r\n","\n"):gsub("\r","\n")
  s = s:gsub("\n","\\n")
  s = s:gsub("\t","    ")
  return s
end

local function as_array(v)
  if type(v)=="table" then return v end
  if v==nil then return {} end
  return { tostring(v) }
end

local function main()
  local dir = settings_dir()
  ensure_dir(dir)
  local json_path = dir.."/fx_alias.json"
  local tsv_path  = dir.."/fx_alias.tsv"

  local raw = read_file(json_path)
  if not raw or raw == "" then
    -- 建一個範例空殼
    local empty = json.encode({
      -- key = fingerprint
      -- value = { alias="", normalized_core="", normalized_vendor="", raw_examples=[], seen_types=[], last_seen="" }
    })
    write_file(json_path, empty)
    raw = empty
  end

  local obj, err = json.decode(raw)
  if not obj then
    reaper.MB("JSON decode error:\n"..tostring(err), "FX Alias Export", 0)
    return
  end

  -- 以 key（fingerprint）排序穩定輸出
  local keys = {}
  for k in pairs(obj) do keys[#keys+1]=k end
  table.sort(keys)

  local lines = {}
  lines[#lines+1] = table.concat({
    "fingerprint",
    "raw_examples",
    "alias",
    "normalized_core",
    "normalized_vendor",
    "seen_types",
    "last_seen",
  }, "\t")

  for _,fp in ipairs(keys) do
    local rec = obj[fp] or {}
    local raw_examples = table.concat(as_array(rec.raw_examples), " | ")
    local seen_types   = table.concat(as_array(rec.seen_types),   ",")

    lines[#lines+1] = table.concat({
      tsv_escape(fp),
      tsv_escape(raw_examples),
      tsv_escape(rec.alias or ""),
      tsv_escape(rec.normalized_core or ""),
      tsv_escape(rec.normalized_vendor or ""),
      tsv_escape(seen_types),
      tsv_escape(rec.last_seen or ""),
    }, "\t")
  end

  local ok, werr = write_file(tsv_path, table.concat(lines, "\n"))
  if not ok then
    reaper.MB("Write TSV failed:\n"..tostring(werr), "FX Alias Export", 0)
    return
  end

  reaper.ShowConsoleMsg(("[FX ALIAS][EXPORT]\n  JSON: %s\n  TSV : %s\n  rows: %d\n"):format(json_path, tsv_path, #keys))
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Export FX Alias JSON → TSV", -1)