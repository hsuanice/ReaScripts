--[[
@description json.lua
@version 26.1012.1206
@author hsuanice
@noindex
@changelog
  - Released as part of the 26.1012.1206 package update.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  v0.1.3 — Lightweight JSON decoder/encoder for Lua 5.3+
  Based on rxi/json.lua (MIT License, https://github.com/rxi/json.lua)
  Copyright (c) 2020 rxi
  Permission is hereby granted, free of charge, to any person obtaining a copy of
  this software and associated documentation files (the "Software"), to deal in
  the Software without restriction, including without limitation the rights to
  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
  of the Software, and to permit persons to whom the Software is furnished to do
  so, subject to the following conditions:
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  Minimal subset: decode only (encoder kept for debug convenience).
  Usage:
    local json = dofile("Library/json.lua")
    local t    = json.decode('{"key": "value", "n": 42}')
    local s    = json.encode(t)   -- optional, for debugging
--]]
local json = {}
json._VERSION = "0.1.3"

-- ---------------------------------------------------------------------------
-- Decode
-- ---------------------------------------------------------------------------

local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count  = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count  = 1
    end
  end
  error(string.format("%s at line %d col %d", msg, line_count, col_count))
end

local function codepoint_to_utf8(n)
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224,
                       f(n % 4096 / 64) + 128,
                       n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240,
                       f(n % 262144 / 4096) + 128,
                       f(n % 4096 / 64) + 128,
                       n % 64 + 128)
  end
  error(string.format("invalid unicode codepoint '%x'", n))
end

local function parse_unicode_escape(s)
  local n1 = tonumber(s:sub(3, 6),  16)
  local n2 = tonumber(s:sub(9, 12), 16)
  -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  end
  return codepoint_to_utf8(n1)
end

local string_escapes = {
  ["\""] = "\"", ["\\"] = "\\", ["/"] = "/",
  ["b"] = "\b",  ["f"] = "\f",  ["n"] = "\n",
  ["r"] = "\r",  ["t"] = "\t",
}

local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end

local whitespace = { [" "] = true, ["\t"] = true, ["\r"] = true, ["\n"] = true }
local delimiters  = { [" "] = true, ["\t"] = true, ["\r"] = true, ["\n"] = true,
                      ["]"] = true, ["}"] = true,  [","] = true,  [":"] = true }

local function decode_string(str, i)
  local has_unicode_escape = false
  local has_surrogate_escape = false
  local has_escape = false
  local last

  for j = i + 1, #str do
    local x = str:byte(j)
    if x < 32 then
      decode_error(str, j, "control character in string")
    end
    if last == 92 then -- backslash
      if x == 117 then -- 'u'
        local hex = str:sub(j + 1, j + 5)
        if not hex:find("%x%x%x%x") then
          decode_error(str, j, "invalid unicode escape in string")
        end
        if hex:find("^[dD][89aAbB]") then
          has_surrogate_escape = true
        else
          has_unicode_escape = true
        end
      else
        local c = string.char(x)
        if not string_escapes[c] then
          decode_error(str, j, "invalid escape char '" .. c .. "' in string")
        end
        has_escape = true
      end
      last = nil
    elseif x == 34 then -- '"'
      local s = str:sub(i + 1, j - 1)
      if has_surrogate_escape then
        s = s:gsub("\\u[dD][89aAbB]..\\u....", parse_unicode_escape)
      end
      if has_unicode_escape then
        s = s:gsub("\\u....", parse_unicode_escape)
      end
      if has_escape then
        s = s:gsub("\\.", string_escapes)
      end
      return s, j + 1
    else
      last = x
    end
  end
  decode_error(str, i, "expected closing quote for string")
end

local function decode_number(str, i)
  local x = next_char(str, i, delimiters)  -- nil negate: stop AT delimiter
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end

-- Use a list (ipairs) so nil values survive table storage.
local literal_list = {
  { "true",  true  },
  { "false", false },
  { "null",  nil   },  -- returns nil correctly via kv[2]
}

local function decode_literal(str, i)
  for _, kv in ipairs(literal_list) do
    local k = kv[1]
    if str:sub(i, i + #k - 1) == k then
      return kv[2], i + #k
    end
  end
  decode_error(str, i, "invalid literal")
end

-- forward declaration
local decode_value

local function decode_array(str, i)
  local res = {}
  local n = 1
  i = i + 1  -- skip '['
  while true do
    i = next_char(str, i, whitespace, true)
    -- Empty array or trailing comma tolerance
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    local v
    v, i = decode_value(str, i)
    res[n] = v
    n = n + 1
    i = next_char(str, i, whitespace, true)
    local c = str:sub(i, i)
    if c == "]" then i = i + 1; break end
    if c ~= "," then decode_error(str, i, "expected ']' or ','") end
    i = i + 1
  end
  return res, i
end

local function decode_object(str, i)
  local res = {}
  i = i + 1  -- skip '{'
  while true do
    i = next_char(str, i, whitespace, true)
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    if str:sub(i, i) ~= "\"" then
      decode_error(str, i, "expected string key")
    end
    local key
    key, i = decode_string(str, i)
    i = next_char(str, i, whitespace, true)
    if str:sub(i, i) ~= ":" then decode_error(str, i, "expected ':'") end
    i = next_char(str, i + 1, whitespace, true)
    local val
    val, i = decode_value(str, i)
    res[key] = val
    i = next_char(str, i, whitespace, true)
    local c = str:sub(i, i)
    if c == "}" then i = i + 1; break end
    if c ~= "," then decode_error(str, i, "expected '}' or ','") end
    i = i + 1
  end
  return res, i
end

local char_to_decoder = {
  ["\""] = decode_string,
  ["0"] = decode_number, ["1"] = decode_number, ["2"] = decode_number,
  ["3"] = decode_number, ["4"] = decode_number, ["5"] = decode_number,
  ["6"] = decode_number, ["7"] = decode_number, ["8"] = decode_number,
  ["9"] = decode_number, ["-"] = decode_number,
  ["t"] = decode_literal,
  ["f"] = decode_literal,
  ["n"] = decode_literal,
  ["["] = decode_array,
  ["{"] = decode_object,
}

decode_value = function(str, i)
  local c = str:sub(i, i)
  local decoder = char_to_decoder[c]
  if decoder then
    return decoder(str, i)
  end
  decode_error(str, i, "unexpected character '" .. c .. "'")
end

function json.decode(str)
  if type(str) ~= "string" then
    error("expected string argument, got " .. type(str))
  end
  local i = next_char(str, 1, whitespace, true)
  local res, idx = decode_value(str, i)
  -- Ensure nothing but whitespace follows
  idx = next_char(str, idx, whitespace, true)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end

-- ---------------------------------------------------------------------------
-- Encode (simple, for debugging)
-- ---------------------------------------------------------------------------

local encode_value  -- forward
local escape_char_map = {
  ["\\"] = "\\\\", ["\""] = "\\\"",
  ["\b"] = "\\b",  ["\f"] = "\\f",  ["\n"] = "\\n",
  ["\r"] = "\\r",  ["\t"] = "\\t",
}

local function escape_string(s)
  return s:gsub('[\\"\b\f\n\r\t]', escape_char_map)
           :gsub("[\0-\31]", function(c)
             return string.format("\\u%04x", string.byte(c))
           end)
end

local function encode_string(v)
  return '"' .. escape_string(v) .. '"'
end

local function is_array(t)
  local max = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
      return false
    end
    if k > max then max = k end
  end
  return max == #t
end

encode_value = function(v)
  local t = type(v)
  if t == "string"  then return encode_string(v) end
  if t == "number"  then
    if v ~= v then return "null" end  -- NaN
    return tostring(v)
  end
  if t == "boolean" then return tostring(v) end
  if t == "nil"     then return "null" end
  if t == "table"   then
    local parts = {}
    if is_array(v) then
      for _, val in ipairs(v) do
        parts[#parts + 1] = encode_value(val)
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      for key, val in pairs(v) do
        if type(key) == "string" then
          parts[#parts + 1] = encode_string(key) .. ":" .. encode_value(val)
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  error("unsupported type: " .. t)
end

function json.encode(v)
  return encode_value(v)
end

return json
