--[[
@description hsuanice Metadata Rename Core
@version 0.1.0
@author hsuanice
@about
  Shared helpers for metadata-based rename grouping and baseindex logic.
  This is intentionally small and focused: base-name detection, grouping keys,
  and sequential index assignment for selected items.
]]

local M = {}
M.VERSION = "0.1.0"

local function trim(s)
  s = tostring(s or "")
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

function M.normalize_tokens(s, extra_known)
  s = tostring(s or "")

  s = s:gsub("%$trk(%d+)", "${trk%1}")
  s = s:gsub("%$(counter:%d+)", "${%1}")
  s = s:gsub("%$(srcbaseprefix:%d+)", "${%1}")
  s = s:gsub("%$(srcbasesuffix:%d+)", "${%1}")

  local known = {
    "curtake","curnote","clearnote","track","filename","srcfile","srcbase","srcext","srcpath","srcdir",
    "samplerate","channels","length","project","scene","take","tape","trk","trkall",
    "ubits","framerate","speed","date","time","year","originationdate","originationtime","startoffset",
    "filepath","originator","originatorreference","timereference","description","interleave","interum","baseindex","baseidx","chnum","channelnum",
  }
  if extra_known then
    for _, k in ipairs(extra_known) do
      known[#known + 1] = k
    end
  end
  table.sort(known, function(a,b) return #a > #b end)
  for _,k in ipairs(known) do
    s = s:gsub("%$"..k, "${"..k.."}")
  end
  return s
end

function M.template_token_list(tpl)
  local list, seen = {}, {}
  local s = M.normalize_tokens(tpl or "")
  for name in s:gmatch("%${([%w_:]+)}") do
    if not seen[name] then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  table.sort(list)
  return list
end

function M.empty_tokens_in_template(tpl, fields, counter, expand_fn)
  local empties = {}
  local tokens = M.template_token_list(tpl)
  for _, tk in ipairs(tokens) do
    if tk ~= "clearnote" then
      local probe = "${" .. tk .. "}"
      local out = expand_fn(probe, fields, counter, false) or ""
      out = tostring(out):gsub("^%s+", ""):gsub("%s+$", "")
      if out == "" then empties[#empties + 1] = tk end
    end
  end
  return empties
end

function M.expand_template(tpl, fields, counter, sanitize, custom_repl)
  if sanitize == nil then sanitize = true end

  local function maybe_sanitize(s)
    s = tostring(s or "")
    if sanitize then return (s:gsub('[\\/:*?\"<>|%c]', '_')) end
    return s
  end

  local function default_repl(name)
    local tkl = string.lower(name or "")
    if tkl == "clearnote" then return "" end
    local v = fields[tkl] or fields[name] or ""
    local s = tostring(v or "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
  end

  local out = M.normalize_tokens(tpl or "")
  out = out:gsub("%${(.-)}", function(s)
    if custom_repl then
      local r = custom_repl(s, fields, counter, sanitize, maybe_sanitize)
      if r ~= nil then return r end
    end
    return default_repl(s)
  end)
  out = out:gsub("%$([%a%d:]+)", function(s)
    if custom_repl then
      local r = custom_repl(s, fields, counter, sanitize, maybe_sanitize)
      if r ~= nil then return r end
    end
    return default_repl(s)
  end)
  out = out:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return out
end

function M.detect_base_and_index(name)
  local s = tostring(name or "")
  s = s:gsub("%.[^./\\]+$", "")
  s = s:gsub("%s+$", "")

  local base1, num1 = s:match("^(.-)%s+[%w%-]+%s*(%d+)$")
  if base1 and num1 then
    return (base1:gsub("[%._%- ]+$", "") or base1), tonumber(num1) or 0
  end

  local base2, suffix2, num2 = s:match("^(.-)[%._%- ]?([A-Za-z]+)?(%d+)$")
  if base2 and num2 then
    local cleaned = base2:gsub("[%._%- ]+$", "")
    if cleaned ~= "" then return cleaned, tonumber(num2) or 0 end
  end

  return s, 0
end

function M.strip_channel_suffix(stem)
  local base, _ = M.detect_base_and_index(stem)
  return base ~= "" and base or tostring(stem or "")
end

function M.parse_channel_suffix_number(stem)
  local _, n = M.detect_base_and_index(stem)
  return n or 0
end

function M.item_group_key(it, metadata_getter)
  local metadata_getter_fn = metadata_getter or function(x)
    return x and x.fields or {}
  end

  local f = metadata_getter_fn(it) or {}
  local tape = tostring(f.tape or f.TAPE or "")
  local scene = tostring(f.scene or f.SCENE or "")
  local take = tostring(f.take or f.TAKE or "")

  if tape ~= "" or scene ~= "" or take ~= "" then
    return "META|" .. table.concat({tape, scene, take}, "|")
  end

  local take_it = reaper.GetActiveTake(it)
  local src = take_it and reaper.GetMediaItemTake_Source(take_it)
  local path = src and reaper.GetMediaSourceFileName(src, "") or ""
  local file_name = path:match("([^/\\]+)$") or path or ""
  local base = M.strip_channel_suffix(file_name)
  if base ~= "" and base ~= file_name then
    return "BASE|" .. base
  end

  local start = reaper.GetMediaItemInfo_Value(it, "D_POSITION") or 0
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH") or 0
  return string.format("TIME|%.6f|%.6f", start, len)
end

function M.current_base_index(item, selected_items, metadata_getter, debug_cb)
  if not item then
    if debug_cb then debug_cb("[baseindex] missing item -> return 1") end
    return 1
  end

  local groups = {}
  for _, it in ipairs(selected_items or {}) do
    if it then
      local key = M.item_group_key(it, metadata_getter)
      local take_item = reaper.GetActiveTake(it)
      local src = take_item and reaper.GetMediaItemTake_Source(take_item)
      local path = src and reaper.GetMediaSourceFileName(src, "") or ""
      local file_name = path:match("([^/\\]+)$") or path or ""
      local _, n = M.detect_base_and_index(file_name)
      local start = reaper.GetMediaItemInfo_Value(it, "D_POSITION") or 0
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH") or 0

      groups[key] = groups[key] or {}
      groups[key][#groups[key] + 1] = {
        item = it,
        num = n or 0,
        start = start,
        len = len,
        name = file_name,
      }

      if debug_cb then
        debug_cb(string.format("[baseindex] candidate %s => key=%s num=%s", tostring(file_name), tostring(key), tostring(n or 0)))
      end
    end
  end

  for key, group in pairs(groups) do
    table.sort(group, function(a, b)
      if (a.num or 0) ~= (b.num or 0) then return (a.num or 0) < (b.num or 0) end
      if math.abs((a.start or 0) - (b.start or 0)) > 0.000001 then return (a.start or 0) < (b.start or 0) end
      if math.abs((a.len or 0) - (b.len or 0)) > 0.000001 then return (a.len or 0) < (b.len or 0) end
      return tostring(a.name or "") < tostring(b.name or "")
    end)

    for idx, entry in ipairs(group) do
      if entry.item == item then
        if debug_cb then
          debug_cb(string.format("[baseindex] resolved key=%s item=%s => index=%d", tostring(key), tostring(entry.name), idx))
        end
        return idx
      end
    end
  end

  if debug_cb then debug_cb("[baseindex] no match in selected group -> fallback 1") end
  return 1
end

return M
