--[[
@description FX Alias Update - Update FX Alias JSON from TSV
@version 0.1.0
@author hsuanice
@provides
  [main] Tools/hsuanice_FX Alias Update TSV to JSON.lua
@about
  Read Settings/fx_alias.tsv and update Settings/fx_alias.json.
  Only rows that exist in TSV will be updated/added. Others are kept.

  Part of AudioSweet ReaImGui Tools suite.

@changelog
  0.1.0 (2025-12-12) [internal: v251030.1600]
    - Initial Public Beta Release
    - FX Alias TSV to JSON updater tool featuring:
      • Reads edited fx_alias.tsv and updates fx_alias.json
      • Preserves existing entries not in TSV
      • Accessible from AudioSweet ReaImGui: Settings → FX Alias Tools → Update TSV to JSON
      • Completes FX Alias workflow: Build → Export → Edit → Update
    - Fix JSON decode, stable object-key ordering in encoder [internal: v251007.1]
    - Initial release [internal: v251007]
]]--

-- ========== Minimal JSON (dkjson subset) ==========
local json = (function()
  -- same trimmed dkjson as exporter
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
        local keys = {}
        for k,_ in pairs(v) do keys[#keys+1] = tostring(k) end
        table.sort(keys)  -- deterministic key order
        local out = {}
        for _,k in ipairs(keys) do
          out[#out+1] = encode(k) .. ":" .. encode(v[k])
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
        local val; val, i = parse_value(str, i+1)
        obj[key] = val
        i = skip_whitespace(str, i)
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
      error("JSON decode error near "..i)
    end
  end

  function json.decode(str)
    local ok, res = pcall(function()
      local v, i = parse_value(str, 1)
      return v
    end)
    if ok then return res else return nil, res end
  end

  json.encode = encode
  return json
end)()
-- ========== /JSON ==========

local function resource_path() return reaper.GetResourcePath() end
local function settings_dir()  return resource_path().."/Scripts/hsuanice Scripts/Settings" end

local function read_file(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local function write_file(path, text)
  local f = io.open(path, "wb"); if not f then return false, "open failed" end
  f:write(text or ""); f:close(); return true
end

local function backup_file(path)
  local bak = path..".bak"
  local data = read_file(path)
  if not data then return false end
  return write_file(bak, data)
end

local function split_tabs(line)
  local out = {}
  local last = 1
  while true do
    local a,b = line:find("\t", last, true)
    if not a then
      out[#out+1] = line:sub(last)
      break
    end
    out[#out+1] = line:sub(last, a-1)
    last = b + 1
  end
  return out
end

local function unescape_tsv(s)
  if not s or s=="" then return "" end
  s = s:gsub("\\n", "\n")
       :gsub("\\t", "\t")
       :gsub("\\r", "\r")
  return s
end

local function parse_seen_types(cell)
  if not cell or cell=="" then return {} end
  local out = {}
  for part in cell:gmatch("([^,]+)") do
    local t = part:gsub("^%s+",""):gsub("%s+$","")
    if t ~= "" then out[#out+1] = t end
  end
  return out
end

local function parse_examples(cell)
  if not cell or cell=="" then return {} end
  local out = {}
  for part in cell:gmatch("([^|]+)") do
    local t = part:gsub("^%s+",""):gsub("%s+$","")
    if t ~= "" then out[#out+1] = t end
  end
  return out
end

local function main()
  local dir = settings_dir()
  local json_path = dir.."/fx_alias.json"
  local tsv_path  = dir.."/fx_alias.tsv"

  local raw_json = read_file(json_path)
  if not raw_json then
    raw_json = "{}"
  end
  local obj, err = json.decode(raw_json)
  if not obj then
    reaper.MB("JSON decode error:\n"..tostring(err), "FX Alias Update", 0)
    return
  end

  local raw_tsv = read_file(tsv_path)
  if not raw_tsv then
    reaper.MB("TSV not found:\n"..tsv_path, "FX Alias Update", 0)
    return
  end

  local updated, added, unchanged = 0, 0, 0
  local line_no = 0
  local fp_seen = {}

  for line in raw_tsv:gmatch("([^\n]*)\n?") do
    line_no = line_no + 1
    if line_no == 1 then
      -- header，略過
    else
      if line ~= "" then
        local cols = split_tabs(line)
        -- 欄位順序：
        -- fingerprint, raw_examples, alias, normalized_core, normalized_vendor, seen_types, last_seen
        local fingerprint       = unescape_tsv(cols[1] or "")
        local raw_examples_cell = unescape_tsv(cols[2] or "")
        local alias             = unescape_tsv(cols[3] or "")
        local norm_core         = unescape_tsv(cols[4] or "")
        local norm_vendor       = unescape_tsv(cols[5] or "")
        local seen_types_cell   = unescape_tsv(cols[6] or "")
        local last_seen         = unescape_tsv(cols[7] or "")

        if fingerprint ~= "" then
          fp_seen[fingerprint] = true
          local rec = obj[fingerprint]
          local is_new = false
          if not rec then
            rec = {}
            obj[fingerprint] = rec
            is_new = true
          end

          local before = json.encode(rec)

          rec.alias            = alias
          rec.normalized_core  = norm_core
          rec.normalized_vendor= norm_vendor
          rec.last_seen        = last_seen
          -- 陣列欄位
          rec.seen_types       = parse_seen_types(seen_types_cell)
          rec.raw_examples     = parse_examples(raw_examples_cell)

          local after = json.encode(rec)
          if is_new then
            added = added + 1
          elseif before == after then
            unchanged = unchanged + 1
          else
            updated = updated + 1
          end
        end
      end
    end
  end

  -- 安全：備份並原子更新
  backup_file(json_path)
  local tmp_path = json_path..".tmp"
  local ok = write_file(tmp_path, json.encode(obj))
  if not ok then
    reaper.MB("Failed to write JSON tmp file.", "FX Alias Update", 0)
    return
  end

  -- 覆蓋
  local final_ok = write_file(json_path, read_file(tmp_path))
  if not final_ok then
    reaper.MB("Failed to finalize JSON write.", "FX Alias Update", 0)
    return
  end

  reaper.ShowConsoleMsg(("[FX ALIAS][UPDATE]\n  TSV : %s\n  JSON: %s\n  added: %d  updated: %d  unchanged: %d\n  backup: %s.bak\n")
    :format(tsv_path, json_path, added, updated, unchanged, json_path))
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Update FX Alias JSON from TSV", -1)