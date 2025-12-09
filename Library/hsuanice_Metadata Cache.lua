--[[
@description hsuanice Metadata Cache - Shared metadata caching system
@version 251209.1954
@author hsuanice
@about
  Shared metadata caching library for REAPER scripts.
  Provides persistent disk-based cache for item metadata (BWF/iXML fields).

  Features:
  - Persistent cache stored in project directory as "Metadata.cache"
  - Cache validation using item modification hash
  - Automatic cache invalidation when items change
  - Cache statistics tracking (hits/misses)
  - Compatible with Item List Editor, Rename Active Take, and other scripts

  Usage:
    local CACHE = dofile(reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Cache.lua")
    CACHE.init()

    -- Lookup metadata
    local metadata = CACHE.lookup(item_guid, item)
    if not metadata then
      -- Cache miss - read metadata from file
      metadata = read_metadata_from_file(item)
      CACHE.store(item_guid, item, metadata)
    end

    -- Save cache before exit
    CACHE.flush()

@changelog
  v251209.1954 (2024-12-09)
    - Finalized version for production use
    - Changed cache filename from "ItemListEditor.cache" to "Metadata.cache" (more generic)
    - Cache now shared across all scripts that use this library
    - Improved documentation and usage examples
    - Ready for use by Item List Editor, Rename Active Take, and future scripts
    - Comprehensive API with 9 public methods (init, lookup, store, flush, invalidate_items, clear, get_stats, set_debug, get_cache_path)
    - Caches 21 metadata fields including all BWF/iXML data
    - Automatic hash-based invalidation when items are modified

  v0.1.0 (2024-12-05)
    - Initial release
    - Extracted from Item List Editor v251101.2230
    - Shared cache for Item List Editor and Rename Active Take
    - Compatible with Metadata Read >= 0.2.0
]]

local M = {}
M.VERSION = "251209.1954"

-- Cache version (increment to invalidate all caches)
local CACHE_VERSION = "2.0"

-- Global cache state
local CACHE = {
  loaded = false,
  data = nil,           -- { project_modified, item_count, items = {guid -> metadata} }
  dirty = false,        -- Cache needs saving
  hits = 0,            -- Cache hit count (for stats)
  misses = 0,          -- Cache miss count (for stats)
  debug = false,       -- Enable debug logging
  invalidated = {},    -- Track which items were invalidated (for debugging)
}

---------------------------------------
-- Helper functions
---------------------------------------

-- Get cache directory (REAPER resource path)
local function get_cache_dir()
  local resource_path = reaper.GetResourcePath()
  local cache_dir = resource_path .. "/Metadata_cache"
  -- Ensure directory exists
  reaper.RecursiveCreateDirectory(cache_dir .. "/", 0)
  return cache_dir
end

-- Get current project identifier
local function get_project_cache_key()
  local proj, projfn = reaper.EnumProjects(-1, "")
  if not projfn or projfn == "" then
    return "unsaved_" .. tostring(proj)
  end

  local basename = projfn:match("([^/\\]+)$") or "unknown"
  basename = basename:gsub("[^%w%._%-]", "_")  -- Remove unsafe chars
  return basename
end

-- Get cache file path for current project
local function get_cache_path()
  local proj, projfn = reaper.EnumProjects(-1, "")

  if not projfn or projfn == "" then
    -- Unsaved project: fallback to REAPER resource path
    local cache_dir = get_cache_dir()
    local key = get_project_cache_key()
    return cache_dir .. "/" .. key .. ".cache"
  end

  -- Get project directory (folder containing the .RPP file)
  local proj_dir = projfn:match("^(.*[/\\])[^/\\]+$") or ""
  if proj_dir == "" then
    -- Fallback if can't extract directory
    local cache_dir = get_cache_dir()
    local key = get_project_cache_key()
    return cache_dir .. "/" .. key .. ".cache"
  end

  -- Use fixed cache filename in project directory
  return proj_dir .. "Metadata.cache"
end

-- Get project modification time (for cache invalidation)
local function get_project_mod_time()
  local proj, projfn = reaper.EnumProjects(-1, "")
  if not projfn or projfn == "" then return 0 end

  local file = io.open(projfn, "r")
  if not file then return 0 end
  file:close()

  return reaper.GetProjectTimeSignature2(proj) or 0
end

-- Get item modification hash (based on item properties)
local function get_item_mod_hash(item)
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then return 0 end

  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local take_count = reaper.CountTakes(item)

  local tk = reaper.GetActiveTake(item)
  local src_hash = 0
  local src_fn = ""
  if tk then
    local src = reaper.GetMediaItemTake_Source(tk)
    if src then
      local _, fn = reaper.GetMediaSourceFileName(src, "")
      src_fn = fn or ""
      for i = 1, #src_fn do
        src_hash = src_hash + string.byte(src_fn, i) * i
      end
    end
  end

  return math.floor((pos * 1000000 + len * 10000 + take_count * 100 + src_hash) * 1000)
end

-- Get item details for logging
local function get_item_debug_info(item)
  if not item or not reaper.ValidatePtr(item, "MediaItem*") then return "invalid item" end

  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local tk = reaper.GetActiveTake(item)
  local take_name = tk and (select(2, reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)) or "") or ""
  local src_fn = ""
  if tk then
    local src = reaper.GetMediaItemTake_Source(tk)
    if src then
      local _, fn = reaper.GetMediaSourceFileName(src, "")
      src_fn = (fn or ""):match("([^/\\]+)$") or ""
    end
  end

  return string.format("pos=%.2f, take='%s', src='%s'", pos, take_name, src_fn)
end

---------------------------------------
-- Serialization
---------------------------------------

-- Serialize cache data to string
local function serialize_cache(cache_data)
  local lines = {
    "CACHE_VERSION=" .. CACHE_VERSION,
    "PROJECT_MODIFIED=" .. tostring(cache_data.project_modified or 0),
    "ITEM_COUNT=" .. tostring(cache_data.item_count or 0),
    "CACHED_AT=" .. tostring(os.time()),
    "---DATA---"
  }

  for guid, meta in pairs(cache_data.items or {}) do
    -- Format: GUID|mod_time|file_name|interleave|meta_trk_name|channel_num|umid|umid_pt|origination_date|origination_time|originator|originator_ref|time_reference|description|project|scene|take_meta|tape|ubits|framerate|speed
    local parts = {
      guid,
      tostring(meta.mod_time or 0),
      meta.file_name or "",
      tostring(meta.interleave or 0),
      meta.meta_trk_name or "",
      tostring(meta.channel_num or 0),
      -- BWF/iXML metadata (15 fields)
      meta.umid or "",
      meta.umid_pt or "",
      meta.origination_date or "",
      meta.origination_time or "",
      meta.originator or "",
      meta.originator_ref or "",
      meta.time_reference or "",
      meta.description or "",
      meta.project or "",
      meta.scene or "",
      meta.take_meta or "",
      meta.tape or "",
      meta.ubits or "",
      meta.framerate or "",
      meta.speed or ""
    }
    -- Escape special characters in data (skip GUID and mod_time)
    for i = 3, #parts do
      parts[i] = parts[i]:gsub("\\", "\\\\")  -- Escape backslashes first
      parts[i] = parts[i]:gsub("|", "\\|")    -- Escape pipes
      parts[i] = parts[i]:gsub("\r\n", "\\n") -- Windows line endings
      parts[i] = parts[i]:gsub("\n", "\\n")   -- Unix line endings
      parts[i] = parts[i]:gsub("\r", "\\n")   -- Old Mac line endings
      parts[i] = parts[i]:gsub("\t", "\\t")   -- Tab characters
    end
    lines[#lines + 1] = table.concat(parts, "|")
  end

  return table.concat(lines, "\n")
end

-- Deserialize cache data from string
local function deserialize_cache(content)
  if not content or content == "" then return nil end

  local cache_data = { items = {} }
  local in_data = false

  for line in content:gmatch("([^\n]*)\n?") do
    if line == "---DATA---" then
      in_data = true
    elseif not in_data then
      local key, val = line:match("^([^=]+)=(.*)$")
      if key == "CACHE_VERSION" then
        if val ~= CACHE_VERSION then
          return nil  -- Version mismatch, invalidate cache
        end
      elseif key == "PROJECT_MODIFIED" then
        cache_data.project_modified = tonumber(val) or 0
      elseif key == "ITEM_COUNT" then
        cache_data.item_count = tonumber(val) or 0
      end
    else
      -- Parse data line
      local parts = {}
      local pos = 1
      while pos <= #line do
        local pipe_pos = line:find("|", pos, true)
        if not pipe_pos then
          parts[#parts + 1] = line:sub(pos)
          break
        end

        -- Check if pipe is escaped
        local before_pipe = pipe_pos - 1
        local num_backslashes = 0
        while before_pipe > 0 and line:sub(before_pipe, before_pipe) == "\\" do
          num_backslashes = num_backslashes + 1
          before_pipe = before_pipe - 1
        end

        if num_backslashes % 2 == 1 then
          -- Escaped pipe, skip it
          pos = pipe_pos + 1
        else
          -- Unescaped pipe - field separator
          parts[#parts + 1] = line:sub(pos, pipe_pos - 1)
          pos = pipe_pos + 1
        end
      end

      -- Unescape all special characters in fields
      for i = 1, #parts do
        parts[i] = parts[i]:gsub("\\t", "\t")
        parts[i] = parts[i]:gsub("\\n", "\n")
        parts[i] = parts[i]:gsub("\\|", "|")
        parts[i] = parts[i]:gsub("\\\\", "\\")
      end

      if #parts >= 6 then
        local guid = parts[1]
        cache_data.items[guid] = {
          mod_time = tonumber(parts[2]) or 0,
          file_name = parts[3] or "",
          interleave = tonumber(parts[4]) or 0,
          meta_trk_name = parts[5] or "",
          channel_num = tonumber(parts[6]) or 0,
          -- BWF/iXML metadata (15 fields)
          umid = parts[7] or "",
          umid_pt = parts[8] or "",
          origination_date = parts[9] or "",
          origination_time = parts[10] or "",
          originator = parts[11] or "",
          originator_ref = parts[12] or "",
          time_reference = parts[13] or "",
          description = parts[14] or "",
          project = parts[15] or "",
          scene = parts[16] or "",
          take_meta = parts[17] or "",
          tape = parts[18] or "",
          ubits = parts[19] or "",
          framerate = parts[20] or "",
          speed = parts[21] or ""
        }
      end
    end
  end

  return cache_data
end

---------------------------------------
-- Cache I/O
---------------------------------------

-- Load cache from disk
local function load_cache()
  local path = get_cache_path()
  local file = io.open(path, "r")
  if not file then return nil end

  local content = file:read("*all")
  file:close()

  local cache_data = deserialize_cache(content)
  if cache_data and CACHE.debug then
    reaper.ShowConsoleMsg(string.format("[Metadata Cache] Loaded: %d items from %s\n",
      cache_data.item_count or 0, path))
  end
  return cache_data
end

-- Save cache to disk
local function save_cache(cache_data)
  local path = get_cache_path()
  local content = serialize_cache(cache_data)

  local file = io.open(path, "w")
  if not file then
    if CACHE.debug then
      reaper.ShowConsoleMsg("[Metadata Cache] Warning: Failed to write cache file\n")
    end
    return false
  end

  file:write(content)
  file:close()

  if CACHE.debug then
    reaper.ShowConsoleMsg(string.format("[Metadata Cache] Saved: %d items to %s\n",
      cache_data.item_count or 0, path))
  end
  return true
end

---------------------------------------
-- Public API
---------------------------------------

-- Initialize cache (call once at startup)
function M.init()
  CACHE.data = load_cache()
  CACHE.loaded = true
  CACHE.dirty = false

  if CACHE.data then
    local current_mod = get_project_mod_time()
    if current_mod ~= CACHE.data.project_modified then
      if CACHE.debug then
        reaper.ShowConsoleMsg("[Metadata Cache] Project modified, cache may be stale\n")
      end
    end
  else
    -- No cache exists, create empty
    CACHE.data = {
      project_modified = get_project_mod_time(),
      item_count = 0,
      items = {}
    }
  end
end

-- Lookup metadata in cache (returns cached metadata or nil)
function M.lookup(item_guid, item)
  if not CACHE.data or not CACHE.data.items then return nil end

  local cached = CACHE.data.items[item_guid]
  if not cached then
    CACHE.misses = CACHE.misses + 1
    if CACHE.debug then
      reaper.ShowConsoleMsg(string.format("[Cache] MISS (new): %s\n", get_item_debug_info(item)))
    end
    return nil
  end

  -- Verify item hasn't changed
  local current_hash = get_item_mod_hash(item)
  if current_hash ~= cached.mod_time then
    CACHE.misses = CACHE.misses + 1
    CACHE.invalidated[item_guid] = true
    if CACHE.debug then
      reaper.ShowConsoleMsg(string.format("[Cache] MISS (changed): %s | hash: %d -> %d\n",
        get_item_debug_info(item), cached.mod_time, current_hash))
    end
    CACHE.data.items[item_guid] = nil
    CACHE.dirty = true
    return nil
  end

  CACHE.hits = CACHE.hits + 1
  if CACHE.debug and CACHE.hits <= 5 then
    reaper.ShowConsoleMsg(string.format("[Cache] HIT: %s\n", get_item_debug_info(item)))
  end
  return cached
end

-- Store metadata in cache
function M.store(item_guid, item, metadata)
  if not CACHE.data then return end

  local hash = get_item_mod_hash(item)
  CACHE.data.items[item_guid] = {
    mod_time = hash,
    file_name = metadata.file_name or "",
    interleave = metadata.interleave or 0,
    meta_trk_name = metadata.meta_trk_name or "",
    channel_num = metadata.channel_num or 0,
    -- BWF/iXML metadata (15 fields)
    umid = metadata.umid or "",
    umid_pt = metadata.umid_pt or "",
    origination_date = metadata.origination_date or "",
    origination_time = metadata.origination_time or "",
    originator = metadata.originator or "",
    originator_ref = metadata.originator_ref or "",
    time_reference = metadata.time_reference or "",
    description = metadata.description or "",
    project = metadata.project or "",
    scene = metadata.scene or "",
    take_meta = metadata.take_meta or "",
    tape = metadata.tape or "",
    ubits = metadata.ubits or "",
    framerate = metadata.framerate or "",
    speed = metadata.speed or ""
  }

  if CACHE.debug and CACHE.invalidated[item_guid] then
    reaper.ShowConsoleMsg(string.format("[Cache] STORE (updated): %s | hash: %d\n",
      get_item_debug_info(item), hash))
  end

  CACHE.dirty = true
end

-- Save cache if dirty (call periodically or on exit)
function M.flush()
  if not CACHE.dirty or not CACHE.data then return end

  -- Update metadata
  CACHE.data.project_modified = get_project_mod_time()
  CACHE.data.item_count = 0
  for _ in pairs(CACHE.data.items) do
    CACHE.data.item_count = CACHE.data.item_count + 1
  end

  save_cache(CACHE.data)
  CACHE.dirty = false

  -- Log stats
  if CACHE.debug then
    local total = CACHE.hits + CACHE.misses
    if total > 0 then
      local hit_rate = math.floor((CACHE.hits / total) * 100)
      reaper.ShowConsoleMsg(string.format("[Metadata Cache] Stats: %d hits, %d misses (%d%% hit rate)\n",
        CACHE.hits, CACHE.misses, hit_rate))
    end
  end
end

-- Invalidate cache for specific items by GUID
function M.invalidate_items(item_guids)
  if not CACHE.data or not CACHE.data.items then return end

  local count = 0
  for _, guid in ipairs(item_guids) do
    if CACHE.data.items[guid] then
      CACHE.data.items[guid] = nil
      CACHE.dirty = true
      count = count + 1
    end
  end

  if count > 0 and CACHE.debug then
    reaper.ShowConsoleMsg(string.format("[Metadata Cache] Invalidated %d items\n", count))
  end
end

-- Clear cache
function M.clear()
  CACHE.data = {
    project_modified = get_project_mod_time(),
    item_count = 0,
    items = {}
  }
  CACHE.dirty = true
  CACHE.hits = 0
  CACHE.misses = 0
  if CACHE.debug then
    reaper.ShowConsoleMsg("[Metadata Cache] Cache cleared\n")
  end
end

-- Get cache statistics
function M.get_stats()
  return {
    hits = CACHE.hits,
    misses = CACHE.misses,
    item_count = CACHE.data and CACHE.data.item_count or 0,
    loaded = CACHE.loaded,
    dirty = CACHE.dirty
  }
end

-- Enable/disable debug logging
function M.set_debug(enabled)
  CACHE.debug = enabled
end

-- Get cache file path (for debugging)
function M.get_cache_path()
  return get_cache_path()
end

return M
