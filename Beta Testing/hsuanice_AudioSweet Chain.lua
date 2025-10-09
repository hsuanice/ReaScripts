--[[
@description AudioSweet Chain (hsuanice) — Print full Track FX chain via RGWH Core-style flow (selected items); alias-ready naming; TS-window aware
@version 251009_1530 Added: User option `TRACKNAME_STRIP_SYMBOLS` for FX-style short track name tokens.
@author Hsuanice
@notes
  What this does
  • Prints the **entire Track FX chain** of a chosen track onto the selected item(s).
  • Keeps the track FX states intact (no bypass flipping per-FX; we render the full chain).
  • Time Selection aware:
      - If TS intersects ≥2 “units” → Pro Tools-like TS-Window glue (42432) per track, then apply track FX.
      - Else (no TS, or TS == unit) → one-shot “Core-style” glue with handles then apply track FX.
  • Naming: reuses the concise “AS” scheme:
      BaseName-AS{n}-{FX1}_{FX2}_...
    For Chain prints, the token appended each pass is `FXChain` (configurable).
    Respects your AS_MAX_FX_TOKENS FIFO cap (drop oldest tokens when exceeding the cap).
  • Target track resolution (user options below):
      1) auto   : Focused FX track if any; otherwise the first track named “AudioSweet”.
      2) sticky : Always use the track GUID saved in ExtState (cross-project). If missing, falls back to auto.
      3) name   : Always use the first track whose name equals CHAIN_TARGET_NAME.
  • Sticky utilities:
      - If SET_STICKY_ON_RUN=true and exactly one track is selected, we store its GUID to ExtState and proceed.

  Dependencies
  • REAPER 6+.
  • No JSON required (we don’t need alias lookup to render full chain).
  • Uses native actions: 42432, 40361, 41993, 40441.

  Limitations
  • Take FX are ignored (we render **Track FX chain** only).
  • Mixed and multichannel edge-cases follow the same auto-channel logic as AudioSweet: mono → 40361; ≥2ch → 41993 with a temporary I_NCHAN.

  Reference:
  Tim Chimes
  AudioSuite-like Script. Renders the selected plugin to the selected media item.
  Written for REAPER 5.1 with Lua
  v1.1 12/22/2015 — Added PreventUIRefresh
  Written by Tim Chimes
  http://chimesaudio.com

  This version:
    • Keep original flow/UX
    • Replace the render step with hsuanice_RGWH Core
    • Append the focused Track FX full name to the take name after render
    • Use Peaks: Rebuild peaks for selected items (40441) instead of the nudge trick
    • Track FX only (Take FX not supported)


@changelog
  v251009_1530
    - Added: User option `TRACKNAME_STRIP_SYMBOLS` for FX-style short track name tokens.
    - Changed: `track_name_token()` now supports two modes:
        * FX-style (remove all symbols/spaces, e.g. "TEST CHAIN" → "TESTCHAIN")
        * Sanitized underscore style (e.g. "TEST CHAIN" → "TEST_CHAIN")
    - Updated: `move_items_to_track()` no longer warns in normal mode;
      warnings now show only when DEBUG is enabled.
    - Improved: All non-MediaItem userdata are silently skipped during move operations.
    - Behavior: When `AS_CHAIN_TOKEN_SOURCE="track"`, token now follows FX short-name format by default.

  v251009_1110
    - Add: Chain naming mode "alias-chain" (use enabled Track FX aliases in order).
    - Add: User options CHAIN_ALIAS_JOINER (default ">") and SANITIZE_TOKEN_FOR_FILENAME.
    - Change: Name appending now uses dynamic token per mode (fixed vs alias-chain).
  v251009_0051
    - New: “AudioSweet Chain” script that renders the full track FX chain onto selected item(s).
    - New: Target track resolution modes:
        • auto   → Focused FX track; else track named “AudioSweet”.
        • sticky → Track GUID stored in ExtState; cross-project persistent.
        • name   → First track matching CHAIN_TARGET_NAME.
    - New: Optional one-click sticky set — if SET_STICKY_ON_RUN=true and one track is selected, store its GUID then run.
    - New: TS-Window behavior:
        • If Time Selection intersects ≥2 units, glue within TS (42432) per-track group, then apply full chain.
        • Else (no TS or TS==unit), run a Core-like one-shot (glue-with-handles style) then apply full chain.
    - New: Naming uses concise AS scheme and appends “FXChain” to record pass order; respects FIFO cap (AS_MAX_FX_TOKENS).
    - Logging: DEBUG toggle via ExtState “hsuanice_AS_CHAIN/DEBUG”; clear step tags for root cause analysis.
]]--

-- Debug toggle: set ExtState "hsuanice_AS"/"DEBUG" to "1" to enable, "0" (or empty) to disable
-- reaper.SetExtState("hsuanice_AS","DEBUG","1", false)  -- (disabled: don't force-on DEBUG by default)

-- === User options ===
-- How many FX names to keep in the “-ASn-...” suffix.
-- 0 or nil = unlimited; N>0 = keep last N tokens (FIFO).
local AS_MAX_FX_TOKENS = 3

-- Chain token source:
--   "aliases" → use enabled Track FX aliases in order (joined by AS_CHAIN_ALIAS_JOINER)
--   "fxchain" → literal token "FXChain"
--   "track"   → use the FX track's name (sanitized)
local AS_CHAIN_TOKEN_SOURCE = "track"

-- When AS_CHAIN_TOKEN_SOURCE="aliases", use this joiner to connect alias tokens
local AS_CHAIN_ALIAS_JOINER = "+"

-- If true, strip unsafe filename characters from chain tokens (for "track" mode & others)
local SANITIZE_TOKEN_FOR_FILENAME = false
-- Track name token style: when true, strip ALL non-alphanumeric (FX-like short name).
-- When false, fall back to sanitize_token (underscores etc.).
local TRACKNAME_STRIP_SYMBOLS = true

-- Naming-only debug (console print before/after renaming).
-- Toggle directly in this script (no ExtState).
local AS_DEBUG_NAMING = true
local function debug_naming_enabled() return AS_DEBUG_NAMING == true end

local function debug_enabled()
  return reaper.GetExtState("hsuanice_AS", "DEBUG") == "1"
end

function debug(message)
  if not debug_enabled() then return end
  if message == nil then return end
  reaper.ShowConsoleMsg(tostring(message) .. "\n")
end

-- Step logger: always prints when DEBUG=1; use for deterministic tracing
local function log_step(tag, fmt, ...)
  if not debug_enabled() then return end
  local msg = fmt and string.format(fmt, ...) or ""
  reaper.ShowConsoleMsg(string.format("[AS][STEP] %s %s\n", tostring(tag or ""), msg))
end



-- ==== debug helpers ====
local function dbg_item_brief(it, tag)
  if not debug_enabled() or not it then return end
  local p   = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local tr  = reaper.GetMediaItem_Track(it)
  local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
  local trname = ""
  if tr then
    local _, tn = reaper.GetTrackName(tr)
    trname = tn or ""
  end
  reaper.ShowConsoleMsg(string.format("[AS][STEP] %s item pos=%.3f len=%.3f track='%s' guid=%s\n",
    tag or "ITEM", p or -1, len or -1, trname, g))
end

local function dbg_dump_selection(tag)
  if not debug_enabled() then return end
  local n = reaper.CountSelectedMediaItems(0)
  reaper.ShowConsoleMsg(string.format("[AS][STEP] %s selected_items=%d\n", tag or "SEL", n))
  for i=0,n-1 do
    dbg_item_brief(reaper.GetSelectedMediaItem(0, i), "  •")
  end
end

local function dbg_dump_unit(u, idx)
  if not debug_enabled() or not u then return end
  reaper.ShowConsoleMsg(string.format("[AS][STEP] UNIT#%d UL=%.3f UR=%.3f members=%d\n",
    idx or -1, u.UL, u.UR, #u.items))
  for _,it in ipairs(u.items) do dbg_item_brief(it, "    -") end
end

local function dbg_track_items_in_range(tr, L, R)
  if not debug_enabled() then return end
  reaper.ShowConsoleMsg(string.format("[AS][STEP] TRACK SCAN in [%.3f..%.3f]\n", L, R))
  if not tr then
    reaper.ShowConsoleMsg("[AS][STEP]   (no track)\n")
    return
  end
  local n = reaper.CountTrackMediaItems(tr)
  for i=0,n-1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    if it then
      local p   = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local q   = (p or 0) + (len or 0)
      if p and len and not (q < L or p > R) then
        dbg_item_brief(it, "  tr-hit")
      end
    end
  end
end
-- =======================
-- ==== FX name formatting options & helper ====
-- ExtState 開關（若沒設定則讀 default）
local FXNAME_DEFAULT_SHOW_TYPE    = false  -- 是否包含 type（如 "VST3:" / "CLAP:"）
local FXNAME_DEFAULT_SHOW_VENDOR  = false  -- 是否包含廠牌（括號內）
local FXNAME_DEFAULT_STRIP_SYMBOL = true  -- 是否移除空格與符號（僅保留字母數字）

local function fxname_opts()
  local function flag(key, default)
    local v = reaper.GetExtState("hsuanice_AS", key)
    if v == "1" then return true end
    if v == "0" then return false end
    return default
  end
  return {
    show_type    = flag("FXNAME_SHOW_TYPE",   FXNAME_DEFAULT_SHOW_TYPE),
    show_vendor  = flag("FXNAME_SHOW_VENDOR", FXNAME_DEFAULT_SHOW_VENDOR),
    strip_symbol = flag("FXNAME_STRIP_SYMBOL",FXNAME_DEFAULT_STRIP_SYMBOL),
  }
end

local function trim(s) return (s and s:gsub("^%s+",""):gsub("%s+$","")) or "" end

-- 解析 REAPER FX 顯示名稱：
--  例： "CLAP: Pro-Q 4 (FabFilter)" → type="CLAP", core="Pro-Q 4", vendor="FabFilter"
local function parse_fx_label(raw)
  raw = tostring(raw or "")
  local typ, rest = raw:match("^([%w%+%._-]+):%s*(.+)$")
  rest = rest or raw
  local core, vendor = rest, nil
  local core_only, v = rest:match("^(.-)%s*%(([^%(%)]+)%)%s*$")
  if core_only then
    core, vendor = core_only, v
  end
  return trim(typ), trim(core), trim(vendor)
end

-- forward declare for alias lookup used by format_fx_label
local fx_alias_for_raw_label

local function format_fx_label(raw)
  -- NEW: 先查 alias；若有就直接用
  local alias = fx_alias_for_raw_label(raw)
  if type(alias) == "string" and alias ~= "" then
    return alias
  end

  -- 以下保留你原本的行為
  local opt = fxname_opts()
  local typ, core, vendor = parse_fx_label(raw)

  local base
  if opt.show_type and typ ~= "" then
    base = typ .. ": " .. core
  else
    base = core
  end
  if opt.show_vendor and vendor ~= "" then
    base = base .. " (" .. vendor .. ")"
  end

  if opt.strip_symbol then
    base = base:gsub("[^%w]+","")
  end
  return base
end

-- ==== FX alias lookup (from Settings/fx_alias.json / .tsv) ====
-- User options
local AS_ALIAS_JSON_PATH = reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Settings/fx_alias.json"
local AS_ALIAS_TSV_PATH = reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Settings/fx_alias.tsv"
local AS_USE_ALIAS   = true   -- 設為 false 可暫時停用別名
local AS_DEBUG_ALIAS = true   -- 印出 alias 查找細節（Console）

-- 簡單正規化：全小寫、移除非英數
local function _norm(s) return (tostring(s or ""):lower():gsub("[^%w]+","")) end

-- 懶載入 JSON（需系統已有 dkjson 或同等 json.decode）
-- Forward declare TSV helper so _alias_map() can call it before definition.
local _alias_map_from_tsv

local _FX_ALIAS_CACHE = nil
local function _alias_map()
  if _FX_ALIAS_CACHE ~= nil then return _FX_ALIAS_CACHE end
  _FX_ALIAS_CACHE = {}
  if not AS_USE_ALIAS then return _FX_ALIAS_CACHE end

  local f = io.open(AS_ALIAS_JSON_PATH, "rb")
  if not f then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg(("[ALIAS][LOAD] JSON not found: %s\n"):format(AS_ALIAS_JSON_PATH))
    end
    -- JSON 檔不存在 → 試 TSV 後援
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end
  local blob = f:read("*a"); f:close()

  -- 探測/載入 JSON 解碼器
  local JSON = _G.json or _G.dkjson
  if not JSON or not (JSON.decode or JSON.Decode or JSON.parse) then
    pcall(function()
      local lib = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/dkjson.lua"
      local ok, mod = pcall(dofile, lib)
      if ok and mod then JSON = mod end
    end)
  end
  local decode = (JSON and (JSON.decode or JSON.Decode or JSON.parse)) or nil
  if not decode then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] No JSON decoder found\n")
    end
    -- 沒有解碼器 → 試 TSV 後援
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end

  local ok, data = pcall(decode, blob)
  if not ok or type(data) ~= "table" then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] JSON decode failed or not a table\n")
    end
    -- JSON 解析失敗 → 試 TSV 後援
    _FX_ALIAS_CACHE = _alias_map_from_tsv(AS_ALIAS_TSV_PATH)
    return _FX_ALIAS_CACHE
  end

  -- 支援兩種形態：
  -- (A) 物件： { ["vst3|core|vendor"] = { alias="FOO", ... }, ... }
  -- (B) 陣列： [ { fingerprint="vst3|core|vendor", alias="FOO", ... }, ... ]
  local count = 0

  local is_array = (data[1] ~= nil) and true or false
  if is_array then
    for i = 1, #data do
      local rec = data[i]
      if type(rec) == "table" then
        local fp = rec.fingerprint
        local al = rec.alias
        if type(fp) == "string" and fp ~= "" and type(al) == "string" and al ~= "" then
          _FX_ALIAS_CACHE[fp] = al
          count = count + 1
        end
      end
    end
  else
    for k, v in pairs(data) do
      if type(k) == "string" and k ~= "" then
        if type(v) == "table" then
          local al = v.alias
          if type(al) == "string" and al ~= "" then
            _FX_ALIAS_CACHE[k] = al
            count = count + 1
          end
        elseif type(v) == "string" then
          _FX_ALIAS_CACHE[k] = v
          count = count + 1
        end
      end
    end
  end

  if AS_DEBUG_ALIAS then
    reaper.ShowConsoleMsg(("[ALIAS][LOAD] entries=%d  from=%s\n")
      :format(count, AS_ALIAS_JSON_PATH))
  end

  return _FX_ALIAS_CACHE
end

-- Sanitize a string for safe filename tokens
local function sanitize_token(s)
  s = tostring(s or "")
  if SANITIZE_TOKEN_FOR_FILENAME then
    -- keep letters, numbers, underscore; collapse repeats
    s = s:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  end
  return s
end

-- Get the FX track's name and turn it into a short token
local function track_name_token(FXtrack)
  if not FXtrack then return "" end
  local _, tn = reaper.GetTrackName(FXtrack)
  tn = tn or ""
  if TRACKNAME_STRIP_SYMBOLS then
    -- 移除括號內容與所有非英數，風格與 alias 一致（e.g., "TEST CHAIN" -> "TESTCHAIN")
    tn = tn:gsub("%b()", "")      -- drop any (...) groups
           :gsub("[^%w]+","")     -- keep only [A-Za-z0-9_], but _ 也去掉
  else
    -- 舊行為：用 sanitize_token（可能把空白轉底線）
    tn = sanitize_token(tn)
  end
  return tn
end

-- Build chain token from the FX track according to AS_CHAIN_TOKEN_SOURCE
-- "aliases": join enabled FX aliases using AS_CHAIN_ALIAS_JOINER
-- "fxchain": literal "FXChain"
-- "track"  : sanitized track name
local function build_chain_token(FXtrack)
  if AS_CHAIN_TOKEN_SOURCE == "fxchain" then
    return "FXChain"
  elseif AS_CHAIN_TOKEN_SOURCE == "track" then
    return track_name_token(FXtrack)
  end

  -- default: "aliases"
  local list = {}
  if not FXtrack then return "" end
  local cnt = reaper.TrackFX_GetCount(FXtrack) or 0
  for i = 0, cnt-1 do
    local enabled = reaper.TrackFX_GetEnabled(FXtrack, i)
    if enabled then
      local _, raw = reaper.TrackFX_GetFXName(FXtrack, i, "")
      local name  = format_fx_label(raw)
      if name and name ~= "" then list[#list+1] = name end
    end
  end
  return table.concat(list, AS_CHAIN_ALIAS_JOINER)
end

-- TSV small helper: build alias map from a TSV with headers:
--   fingerprint <TAB> alias  (其他欄位可有可無)
function _alias_map_from_tsv(tsv_path)
  local map = {}
  local f = io.open(tsv_path, "rb")
  if not f then
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg(("[ALIAS][LOAD] TSV not found: %s\n"):format(tsv_path))
    end
    return map
  end

  local header = f:read("*l")
  if not header then
    f:close()
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] TSV empty header\n")
    end
    return map
  end

  -- 找欄位索引
  local cols = {}
  local idx = 1
  for h in tostring(header):gmatch("([^\t]+)") do
    cols[h] = idx
    idx = idx + 1
  end
  local fp_i  = cols["fingerprint"]
  local al_i  = cols["alias"]

  if not fp_i or not al_i then
    f:close()
    if AS_DEBUG_ALIAS then
      reaper.ShowConsoleMsg("[ALIAS][LOAD] TSV missing 'fingerprint' or 'alias' header\n")
    end
    return map
  end

  local added = 0
  while true do
    local line = f:read("*l")
    if not line then break end
    if line ~= "" then
      local fields = {}
      local i = 1
      for seg in line:gmatch("([^\t]*)\t?") do
        fields[i] = seg
        i = i + 1
        if (#fields >= idx-1) then break end
      end
      local fp = fields[fp_i]
      local al = fields[al_i]
      if type(fp) == "string" and fp ~= "" and type(al) == "string" and al ~= "" then
        map[fp] = al
        added = added + 1
      end
    end
  end
  f:close()

  if AS_DEBUG_ALIAS then
    reaper.ShowConsoleMsg(("[ALIAS][LOAD] TSV entries=%d  from=%s\n"):format(added, tsv_path))
  end
  return map
end
-- 更強的 raw 解析：抓 host/type、去除括號後的 core、以及最外層括號當 vendor
-- 例： "VST3: UADx Manley VOXBOX Channel Strip (Universal Audio (UADx))"
--  => host="vst3", core="uadxmanleyvoxboxchannelstrip", vendor="universalaudiouadx"
local function _parse_raw_label_host_core_vendor(raw)
  raw = tostring(raw or "")

  -- host/type
  local host = raw:match("^%s*([%w_]+)%s*:") or ""
  host = host:lower()

  -- core：取冒號後整段，再去除所有括號內容與非英數
  local core = raw:match(":%s*(.+)$") or ""
  core = core:gsub("%b()", "")            -- 去掉所有括號段
               :gsub("%s+%-[%s%-].*$", "")-- 去掉 " - Something" 類尾巴（防萬一）
               :gsub("%W", "")            -- 非英數去掉
               :lower()

  -- vendor：用 %b() 擷取「每一段平衡括號」，取最後一段
  local last = nil
  for seg in raw:gmatch("%b()") do
    last = seg
  end
  local vendor = ""
  if last and #last >= 2 then
    vendor = last:sub(2, -2)              -- 去掉首尾括號
    vendor = vendor:gsub("%W", ""):lower()
  end

  return host, core, vendor
end
-- 回傳別名或 nil（強化：支援 vendor 併入 core 的鍵、加掃描 fallback 與除錯輸出）
function fx_alias_for_raw_label(raw_label)
  if not AS_USE_ALIAS then return nil end
  local m = _alias_map()
  if not m then return nil end

  -- 主解析
  local host, core, vendor = _parse_raw_label_host_core_vendor(raw_label)

  -- 舊解析一次（兼容老鍵）
  local typ2, core2, vendor2 = parse_fx_label(raw_label)
  local t2 = _norm(typ2)
  local c2 = _norm(core2)
  local v2 = _norm(vendor2)

  local t = host
  local c = core
  local v = vendor

  -- 組各種候選鍵
  local key1  = string.format("%s|%s|%s", t,  c,  v)
  local key2  = string.format("%s|%s|",    t,  c)
  local key2b = (v ~= "" and string.format("%s|%s%s|", t, c, v)) or nil
  local key3  = string.format("|%s|",      c)

  local key1b = string.format("%s|%s|%s", t2, c2, v2)
  local key2c = string.format("%s|%s|",    t2, c2)
  local key2d = (v2 ~= "" and string.format("%s|%s%s|", t2, c2, v2)) or nil
  local key3b = string.format("|%s|",      c2)

  local hit, from

  -- 直接命中
  if type(m[key1]) == "string" and m[key1] ~= "" then hit, from = m[key1], "exact" end
  if not hit and type(m[key2]) == "string" and m[key2] ~= "" then hit, from = m[key2], "empty-vendor" end
  if not hit and key2b and type(m[key2b]) == "string" and m[key2b] ~= "" then hit, from = m[key2b], "core+vendor-as-core" end
  if not hit and type(m[key3]) == "string" and m[key3] ~= "" then hit, from = m[key3], "cross-type" end

  -- 兼容舊鍵
  if not hit and type(m[key1b]) == "string" and m[key1b] ~= "" then hit, from = m[key1b], "exact(legacy)" end
  if not hit and type(m[key2c]) == "string" and m[key2c] ~= "" then hit, from = m[key2c], "empty-vendor(legacy)" end
  if not hit and key2d and type(m[key2d]) == "string" and m[key2d] ~= "" then hit, from = m[key2d], "core+vendor-as-core(legacy)" end
  if not hit and type(m[key3b]) == "string" and m[key3b] ~= "" then hit, from = m[key3b], "cross-type(legacy)" end

  -- 兜底掃描
  if not hit then
    local core_pat1 = "|" .. c  .. "|"
    local core_pat2 = (v ~= "" and ("|" .. c .. v .. "|")) or nil
    for k, rec in pairs(m) do
      if type(rec) == "string" and rec ~= "" then
        if k:find(core_pat1, 1, true) or (core_pat2 and k:find(core_pat2, 1, true)) then
          hit, from = rec, "scan"
          break
        end
      end
    end
  end

  if AS_DEBUG_ALIAS then
    local size = 0
    for _ in pairs(m) do size = size + 1 end
    reaper.ShowConsoleMsg(("[ALIAS][LOOKUP]\n  raw   = %s\n  host  = %s\n  core  = %s\n  vendor= %s\n  try   = %s | %s | %s | %s\n  legacy= %s | %s | %s | %s\n  alias = %s (from=%s)\n  map   = %d entries\n\n")
      :format(
        tostring(raw_label or ""),
        t, c, v,
        key1, key2, tostring(key2b or "(nil)"), key3,
        key1b, key2c, tostring(key2d or "(nil)"), key3b,
        tostring(hit or ""), tostring(from or "miss"),
        size
      ))
  end

  return hit
end
-- =============================================
-- ==== selection snapshot helpers ====
local function snapshot_selection()
  local list = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n - 1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local tr = reaper.GetMediaItem_Track(it)
      local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      table.insert(list, { tr = tr, L = p, R = p + l })
    end
  end
  return list
end

local function restore_selection(snap)
  if not snap then return end
  reaper.Main_OnCommand(40289, 0) -- 清空
  local eps = project_epsilon()
  for _, rec in ipairs(snap) do
    local tr = rec.tr
    if tr then
      local n = reaper.CountTrackMediaItems(tr)
      for j = 0, n - 1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if it then
          local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          local q  = p + l
          -- 只要這顆 item 覆蓋原來的選取範圍就認定是對應項（TS-Window 會生成貼齊的 glued 片段）
          if p <= rec.L + eps and q >= rec.R - eps then
            reaper.SetMediaItemSelected(it, true)
            break
          end
        end
      end
    end
  end
end
-- ==== channel helpers ====
local function get_item_channels(it)
  if not it then return 2 end
  local tk = reaper.GetActiveTake(it)
  if not tk then return 2 end
  local src = reaper.GetMediaItemTake_Source(tk)
  if not src then return 2 end
  local ch = reaper.GetMediaSourceNumChannels(src) or 2
  return ch
end

local function unit_max_channels(u)
  if not u or not u.items or #u.items == 0 then return 2 end
  local maxch = 1
  for _,it in ipairs(u.items) do
    local ch = get_item_channels(it)
    if ch > maxch then maxch = ch end
  end
  return maxch
end
-- =========================
function getSelectedMedia() --Get value of Media Item that is selected
  selitem = 0
  MediaItem = reaper.GetSelectedMediaItem(0, selitem)
  debug (MediaItem)
  return MediaItem
end

function countSelected() --Makes sure there is only 1 MediaItem selected
  if reaper.CountSelectedMediaItems(0) == 1 then
    debug("Media Item is Selected! \n")
    return true
    else 
      debug("Must Have only ONE Media Item Selected")
      return false
  end
end

function checkSelectedFX() --Determines if a TrackFX is selected, and which FX is selected
  retval = 0
  tracknumberOut = 0
  itemnumberOut = 0
  fxnumberOut = 0
  window = false
  
  retval, tracknumberOut, itemnumberOut, fxnumberOut = reaper.GetFocusedFX()
  debug ("\n"..retval..tracknumberOut..itemnumberOut..fxnumberOut)
  
  track = tracknumberOut - 1
  
  if track == -1 then
    track = 0
  else
  end
  
  mtrack = reaper.GetTrack(0, track)
  
  window = reaper.TrackFX_GetOpen(mtrack, fxnumberOut)
  
  return retval, tracknumberOut, itemnumberOut, fxnumberOut, window
end

function getFXname(trackNumber, fxNumber) --Get FX name
  track = trackNumber - 1
  FX = fxNumber
  FXname = ""
  
  mTrack = reaper.GetTrack (0, track)
    
  retvalfx, FXname = reaper.TrackFX_GetFXName(mTrack, FX, FXname)
    
  return FXname, mTrack
end

function bypassUnfocusedFX(FXmediaTrack, fxnumber_Out, render)--bypass and unbypass FX on FXtrack
  FXtrack = FXmediaTrack
  FXnumber = fxnumber_Out

  FXtotal = reaper.TrackFX_GetCount(FXtrack)
  FXtotal = FXtotal - 1
  
  if render == false then
    for i = 0, FXtotal do
      if i == FXnumber then
        reaper.TrackFX_SetEnabled(FXtrack, i, true)
      else reaper.TrackFX_SetEnabled(FXtrack, i, false)
      i = i + 1
      end
    end
  else
    for i = 0, FXtotal do
      reaper.TrackFX_SetEnabled(FXtrack, i, true)
      i = i + 1
    
    end
  end
  
  return
end

function getLoopSelection()--Checks to see if there is a loop selection
  startOut = 0
  endOut = 0
  isSet = false
  isLoop = false
  allowautoseek = false
  loop = false
  
  startOut, endOut = reaper.GetSet_LoopTimeRange(isSet, isLoop, startOut, endOut, allowautoseek)
  if startOut == 0 and endOut == 0 then
    loop = false
  else
    loop = true
  end
  
  return loop, startOut, endOut  
end

-- Build processing units from current selection:
-- same track, position-sorted, merge items that touch/overlap into one unit.
-- ===== epsilon helpers (early shim for forward calls) =====
if not project_epsilon then
  function project_epsilon()
    local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    return (sr and sr > 0) and (1.0 / sr) or 1e-6
  end
end

if not approx_eq then
  function approx_eq(a, b, eps)
    eps = eps or project_epsilon()
    return math.abs(a - b) <= eps
  end
end

if not ranges_touch_or_overlap then
  function ranges_touch_or_overlap(a0, a1, b0, b1, eps)
    eps = eps or project_epsilon()
    return not (a1 < b0 - eps or b1 < a0 - eps)
  end
end
-- ==========================================================
local function build_units_from_selection()
  local n = reaper.CountSelectedMediaItems(0)
  local by_track = {}
  for i = 0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local tr  = reaper.GetMediaItem_Track(it)
      local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local fin = pos + len
      by_track[tr] = by_track[tr] or {}
      table.insert(by_track[tr], { item=it, pos=pos, fin=fin })
    end
  end

  local units = {}
  local eps = project_epsilon()
  for tr, arr in pairs(by_track) do
    table.sort(arr, function(a,b) return a.pos < b.pos end)
    local cur = nil
    for _, e in ipairs(arr) do
      if not cur then
        cur = { track=tr, items={ e.item }, UL=e.pos, UR=e.fin }
      else
        if ranges_touch_or_overlap(cur.UL, cur.UR, e.pos, e.fin, eps) then
          table.insert(cur.items, e.item)
          if e.pos < cur.UL then cur.UL = e.pos end
          if e.fin > cur.UR then cur.UR = e.fin end
        else
          table.insert(units, cur)
          cur = { track=tr, items={ e.item }, UL=e.pos, UR=e.fin }
        end
      end
    end
    if cur then table.insert(units, cur) end
  end

  -- debug dump
  log_step("UNITS", "count=%d", #units)
  if debug_enabled() then
    for i,u in ipairs(units) do
      reaper.ShowConsoleMsg(string.format("  unit#%d  track=%s  members=%d  span=%.3f..%.3f\n",
        i, tostring(u.track), #u.items, u.UL, u.UR))
    end
  end
  return units
end

-- Collect units intersecting a time selection
local function collect_units_intersecting_ts(units, tsL, tsR)
  local out = {}
  -- Guard: only process one item via Core when not in TS-Window mode
  local processed_core_once = false
  for _,u in ipairs(units) do
    if ranges_touch_or_overlap(u.UL, u.UR, tsL, tsR, project_epsilon()) then
      table.insert(out, u)
    end
  end
  log_step("TS-INTERSECT", "TS=[%.3f..%.3f]  hit_units=%d", tsL, tsR, #out)
  return out
end

-- Strict: TS equals unit when both edges match within epsilon
local function ts_equals_unit(u, tsL, tsR)
  local eps = project_epsilon()
  return approx_eq(u.UL, tsL, eps) and approx_eq(u.UR, tsR, eps)
end

local function select_only_items(items)
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  for _,it in ipairs(items) do reaper.SetMediaItemSelected(it, true) end
end

local function move_items_to_track(items, destTrack)
  for _, it in ipairs(items) do
    -- 僅搬 MediaItem*；非 item 直接安靜跳過（除非 DEBUG）
    local is_item = it and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, it, "MediaItem*"))
    if is_item then
      reaper.MoveMediaItemToTrack(it, destTrack)
    else
      if debug_enabled() then
        reaper.ShowConsoleMsg(string.format("[AS-CHAIN][WARN] move_items_to_track: skipped non-item entry=%s\n", tostring(it)))
      end
    end
  end
end

-- 所有 items 都在某 track 上？
local function items_all_on_track(items, tr)
  for _,it in ipairs(items) do
    if not it then return false end
    local cur = reaper.GetMediaItem_Track(it)
    if cur ~= tr then return false end
  end
  return true
end

-- 只選取指定 items（保證 selection 與 unit 一致）
local function select_only_items_checked(items)
  reaper.Main_OnCommand(40289, 0)
  for _,it in ipairs(items) do
    if it and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, it, "MediaItem*")) then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end

local function isolate_focused_fx(FXtrack, focusedIndex)
  -- enable only focusedIndex; others bypass
  local cnt = reaper.TrackFX_GetCount(FXtrack)
  for i = 0, cnt-1 do
    reaper.TrackFX_SetEnabled(FXtrack, i, i == focusedIndex)
  end
end

-- Forward declare helpers used below
local append_fx_to_take_name

-- Max FX tokens cap (via user option AS_MAX_FX_TOKENS)
local function max_fx_tokens()
  local n = tonumber(AS_MAX_FX_TOKENS)
  if not n or n < 1 then
    return math.huge -- unlimited
  end
  return math.floor(n)
end

-- === Take name normalization helpers (for AS naming) ===
local function strip_extension(name)
  return (name or ""):gsub("%.[A-Za-z0-9]+$", "")
end

-- remove "glued-XX", "render XXX/edX" and any trailing " - Something"
local function strip_glue_render_and_trailing_label(name)
  local s = name or ""
  s = s:gsub("[_%-%s]*glue[dD]?[%s_%-%d]*", "")
  s = s:gsub("[_%-%s]*render[eE]?[dD]?[%s_%-%d]*", "")
  s = s:gsub("%s+%-[%s%-].*$", "") -- remove trailing " - Something"
  s = s:gsub("%s+$","")
  s = s:gsub("[_%-%s]+$","")
  return s
end

-- tokens like "glued", "render", or "ed123"/"dup3" should be ignored
-- NOTE: do NOT drop pure-numeric tokens (e.g., "1073", "1176"), since some FX aliases are numeric.
local function is_noise_token(tok)
  local t = tostring(tok or ""):lower()
  if t == "" then return true end
  if t == "glue" or t == "glued" or t == "render" or t == "rendered" then return true end
  if t:match("^ed%d*$")  then return true end  -- e.g. "ed1", "ed23"
  if t:match("^dup%d*$") then return true end  -- e.g. "dup1"
  return false
end
-- Try parse "Base-AS{n}-FX1_FX2" and tolerate extra tails like "-ASx-YYY"
-- Return: base (string), n (number), fx_tokens (table)
local function parse_as_tag(full)
  local s = tostring(full or "")
  local base, n, tail = s:match("^(.-)[-_]AS(%d+)[-_](.+)$")
  if not base or not n then
    return nil, nil, nil
  end
  base = base:gsub("%s+$", "")

  -- If tail contains another "-ASx-" (e.g., "Saturn2-AS1-ProQ4"), only keep the part **before** the next AS tag.
  local first_tail = tail:match("^(.-)[-_]AS%d+[-_].*$") or tail

  -- PRE-CLEAN: strip legacy artifacts BEFORE tokenizing
  -- Remove whole "glued-XX", "render 001"/"rendered-03", and "ed###"/"dup###" sequences.
  local cleaned = first_tail
  cleaned = cleaned
              :gsub("[_%-%s]*glue[dD]?[%s_%-%d]*", "")     -- remove "glued" plus any digits/underscores/hyphens/spaces after it
              :gsub("[_%-%s]*render[eE]?[dD]?[%s_%-%d]*", "") -- remove "render"/"rendered" plus trailing digits etc.
              :gsub("ed%d+", "")                            -- remove "ed###"
              :gsub("dup%d+", "")                           -- remove "dup###"
              :gsub("%s+%-[%s%-].*$", "")                   -- trailing " - Something"
              :gsub("^[_%-%s]+", "")                        -- leading separators
              :gsub("[_%-%s]+$", "")                        -- trailing separators

  -- Tokenize FX names (alnum only), keep order.
  -- NOTE: pure numeric tokens are allowed (e.g., "1073"), since some aliases are numeric by design.
  local fx_tokens = {}
  for tok in cleaned:gmatch("([%w]+)") do
    if tok ~= "" and not tok:match("^AS%d+$") and not is_noise_token(tok) then
      fx_tokens[#fx_tokens+1] = tok
    end
  end

  return base, tonumber(n), fx_tokens
end
-- 共用：把單一 item 搬到 FX 軌並列印「只有聚焦 FX」
local function apply_focused_fx_to_item(item, FXmediaTrack, fxIndex, FXName)
  if not item then return false, -1 end
  local origTR = reaper.GetMediaItem_Track(item)

  -- 移到 FX 軌並 isolate
  reaper.MoveMediaItemToTrack(item, FXmediaTrack)
  dbg_item_brief(item, "TS-APPLY moved→FX")
  isolate_focused_fx(FXmediaTrack, fxIndex)

  -- 依素材聲道決定 40361 / 41993；並視需要暫調 I_NCHAN
  local ch         = get_item_channels(item)
  local prev_nchan = tonumber(reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN")) or 2
  local cmd_apply  = 41993
  local did_set    = false

  if ch <= 1 then
    cmd_apply = 40361
  else
    local desired = (ch % 2 == 0) and ch or (ch + 1)
    if prev_nchan ~= desired then
      log_step("TS-APPLY", "I_NCHAN %d → %d (pre-apply)", prev_nchan, desired)
      reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", desired)
      did_set = true
    end
  end

  -- 只選該 item 後執行 apply
  reaper.Main_OnCommand(40289, 0)
  reaper.SetMediaItemSelected(item, true)
  reaper.Main_OnCommand(cmd_apply, 0)
  log_step("TS-APPLY", "applied %d", cmd_apply)
  dbg_dump_selection("TS-APPLY post-apply")

  -- 還原 I_NCHAN（若有改）
  if did_set then
    log_step("TS-APPLY", "I_NCHAN restore %d → %d", reaper.GetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN"), prev_nchan)
    reaper.SetMediaTrackInfo_Value(FXmediaTrack, "I_NCHAN", prev_nchan)
  end

  -- 取回列印出的那顆（仍是選取中的單一 item），改名、搬回
  local out = reaper.GetSelectedMediaItem(0, 0) or item
  append_fx_to_take_name(out, FXName)
  reaper.MoveMediaItemToTrack(out, origTR)
  return true, cmd_apply
end

function append_fx_to_take_name(item, fxName)
  if not item or not fxName or fxName == "" then return end
  local takeIndex = reaper.GetMediaItemInfo_Value(item, "I_CURTAKE")
  local take      = reaper.GetMediaItemTake(item, takeIndex)
  if not take then return end

  local _, tn0 = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local tn_noext = strip_extension(tn0 or "")

  -- naming debug: before
  if debug_naming_enabled() then
    reaper.ShowConsoleMsg(("[AS-CHAIN][NAME] before='%s'\n"):format(tn0 or ""))
  end

  local baseAS, nAS, fx_tokens = parse_as_tag(tn_noext)

  local base, n, tokens
  if baseAS and nAS then
    base   = strip_glue_render_and_trailing_label(baseAS)
    n      = nAS + 1
    tokens = fx_tokens or {}
  else
    base   = strip_glue_render_and_trailing_label(tn_noext)
    n      = 1
    tokens = {}
  end

  -- always append new FX (allow duplicates; preserve chronological order)
  table.insert(tokens, fxName)

  -- Apply user cap (FIFO): keep only the last N tokens
  do
    local cap = max_fx_tokens()
    if cap ~= math.huge and #tokens > cap then
      local start = #tokens - cap + 1
      local trimmed = {}
      for i = start, #tokens do
        trimmed[#trimmed+1] = tokens[i]
      end
      tokens = trimmed
    end
  end

  local fx_concat = table.concat(tokens, "_")
  local new_name = string.format("%s-AS%d-%s", base, n, fx_concat)

  -- naming debug: after
  if debug_naming_enabled() then
    reaper.ShowConsoleMsg(("[AS-CHAIN][NAME] after ='%s'\n"):format(new_name))
  end

  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
end

function mediaItemInLoop(mediaItem, startLoop, endLoop)
  local mpos = reaper.GetMediaItemInfo_Value(mediaItem, "D_POSITION")
  local mlen = reaper.GetMediaItemInfo_Value(mediaItem, "D_LENGTH")
  local mend = mpos + mlen
  -- use 1 sample as epsilon
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  local eps = (sr and sr > 0) and (1.0 / sr) or 1e-6

  local function approx_eq(a, b) return math.abs(a - b) <= eps end

  -- TS equals unit ONLY when both edges match (within epsilon)
  return approx_eq(mpos, startLoop) and approx_eq(mend, endLoop)
end

-- 1-sample epsilon comparators
local function project_epsilon()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end

local function approx_eq(a, b, eps)
  eps = eps or project_epsilon()
  return math.abs(a - b) <= eps
end

local function ranges_touch_or_overlap(a0, a1, b0, b1, eps)
  eps = eps or project_epsilon()
  return not (a1 < b0 - eps or b1 < a0 - eps)
end

function cropNewTake(mediaItem, tracknumber_Out, FXname)--Crop to new take and change name to add FXname

  track = tracknumber_Out - 1
  
  fxName = FXname
    
  --reaper.Main_OnCommand(40131, 0) --This is what crops to the Rendered take. With this removed, you will have a take for each FX you apply
  
  currentTake = reaper.GetMediaItemInfo_Value(mediaItem, "I_CURTAKE")
  
  take = reaper.GetMediaItemTake(mediaItem, currentTake)
  
  local _, takeName = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local newName = takeName
  if fxName ~= "" then
    newName = takeName .. " - " .. fxName
  end
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", newName, true)
  return true
end

function setNudge()
  reaper.ApplyNudge(0, 0, 0, 0, 1, false, 0)
  reaper.ApplyNudge(0, 0, 0, 0, -1, false, 0)
end

function main() -- main part of the script
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  if debug_enabled() then
    reaper.ShowConsoleMsg("\n=== AudioSweet (hsuanice) run ===\n")
  end
  log_step("BEGIN", "selected_items=%d", reaper.CountSelectedMediaItems(0))
  -- snapshot original selection so we can restore it at the very end
  local sel_snapshot = snapshot_selection()

  -- Focused FX check
  local ret_val, tracknumber_Out, itemnumber_Out, fxnumber_Out, window = checkSelectedFX()
  if ret_val ~= 1 then
    reaper.MB("Please focus a Track FX (not a Take FX).", "AudioSweet", 0)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet (no focused Track FX)", -1)
    return
  end
  log_step("FOCUSED-FX", "trackOut=%d  itemOut=%d  fxOut=%d  window=%s", tracknumber_Out, itemnumber_Out, fxnumber_Out, tostring(window))

  -- Normalize focused FX index & resolve name/track
  local fxIndex = fxnumber_Out
  if fxIndex >= 0x1000000 then fxIndex = fxIndex - 0x1000000 end
  local FXNameRaw, FXmediaTrack = getFXname(tracknumber_Out, fxIndex)
  -- Build token from the entire enabled Track FX chain (per user option)
  local CHAIN_TOKEN = build_chain_token(FXmediaTrack)
  local FXName = format_fx_label(FXNameRaw) -- kept for logs/debug only
  if CHAIN_TOKEN == "" then CHAIN_TOKEN = FXName end -- fallback safety
  log_step("FOCUSED-FX", "index(norm)=%d  name='%s' (raw='%s')  FXtrack=%s",
           fxIndex, tostring(FXName or ""), tostring(FXNameRaw or ""), tostring(FXmediaTrack))

  -- Build units from current selection
  local units = build_units_from_selection()
  if #units == 0 then
    reaper.MB("No media items selected.", "AudioSweet", 0)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet (no items)", -1)
    return
  end

  if debug_enabled() then
    for i,u in ipairs(units) do dbg_dump_unit(u, i) end
  end  

  -- Time selection state
  local hasTS, tsL, tsR = getLoopSelection()
  if debug_enabled() then
    log_step("PATH", "hasTS=%s TS=[%.3f..%.3f]", tostring(hasTS), tsL or -1, tsR or -1)
  end

  -- Helper: Core flags setup/restore
  local function proj_get(ns, key, def)
    local _, val = reaper.GetProjExtState(0, ns, key)
    if val == "" then return def else return val end
  end
  local function proj_set(ns, key, val)
    reaper.SetProjExtState(0, ns, key, tostring(val or ""))
  end

  -- Process (two paths)
  local outputs = {}

  if hasTS then
    -- Figure out how many units intersect the TS
    local hit = collect_units_intersecting_ts(units, tsL, tsR)
    if debug_enabled() then
      log_step("PATH", "TS hit_units=%d → %s", #hit, (#hit>=2 and "TS-WINDOW[GLOBAL]" or "per-unit"))
    end    
    if #hit >= 2 then
      ------------------------------------------------------------------
      -- TS-Window (GLOBAL): Pro Tools 行為（無 handles）
      ------------------------------------------------------------------
      log_step("TS-WINDOW[GLOBAL]", "begin TS=[%.3f..%.3f] units_hit=%d", tsL, tsR, #hit)
      log_step("PATH", "ENTER TS-WINDOW[GLOBAL]")

      -- Select all items in intersecting units (on their original tracks)
      reaper.Main_OnCommand(40289, 0)
      for _,u in ipairs(hit) do
        for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      end
      log_step("TS-WINDOW[GLOBAL]", "pre-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[GLOBAL] pre-42432")      -- ★ 新增
      reaper.Main_OnCommand(42432, 0) -- Glue items within time selection (no handles)
      log_step("TS-WINDOW[GLOBAL]", "post-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[GLOBAL] post-42432")     -- ★ 新增

      -- Each glued result: 先把當前選取複製成穩定清單，再逐一列印
      local glued_items = {}
      do
        local n = reaper.CountSelectedMediaItems(0)
        for i = 0, n - 1 do
          local it = reaper.GetSelectedMediaItem(0, i)
          if it then glued_items[#glued_items + 1] = it end
        end
      end

      for idx, it in ipairs(glued_items) do
        local ok, used_cmd = apply_focused_fx_to_item(it, FXmediaTrack, fxIndex, CHAIN_TOKEN)
        if ok then
          log_step("TS-WINDOW[GLOBAL]", "applied %d to glued #%d", used_cmd or -1, idx)
          -- 取真正列印完的那顆（函式內會把選取變成這顆）
          local out_item = reaper.GetSelectedMediaItem(0, 0)
          if out_item then table.insert(outputs, out_item) end
        else
          log_step("TS-WINDOW[GLOBAL]", "apply failed on glued #%d", idx)
        end
      end

      log_step("TS-WINDOW[GLOBAL]", "done, outputs=%d", #outputs)

      -- 還原執行前的選取（會挑回同軌同範圍的新 glued/printed 片段）
      restore_selection(sel_snapshot)
      if debug_enabled() then dbg_dump_selection("RESTORE selection") end

      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("AudioSweet TS-Window (global) glue+print", 0)
      return
    end
    -- else: TS 命中 0 或 1 個 unit → 落到下面 per-unit 分支
  end

  ----------------------------------------------------------------------
  -- Per-unit path:
  --   - 無 TS：Core/GLUE（含 handles）
  --   - 有 TS 且 TS==unit：Core/GLUE（含 handles）
  --   - 有 TS 且 TS≠unit：TS-Window（UNIT；無 handles）→ 42432 → 40361
  ----------------------------------------------------------------------
  for _,u in ipairs(units) do
    log_step("UNIT", "enter UL=%.3f UR=%.3f members=%d", u.UL, u.UR, #u.items)
    dbg_dump_unit(u, -1) -- dump the current unit (−1 = “in-process” marker)
    if hasTS and not ts_equals_unit(u, tsL, tsR) then
      log_step("PATH", "TS-WINDOW[UNIT] UL=%.3f UR=%.3f", u.UL, u.UR)
      --------------------------------------------------------------
      -- TS-Window (UNIT) 無 handles：42432 → 40361
      --------------------------------------------------------------
      -- select only this unit's items and glue within TS
      reaper.Main_OnCommand(40289, 0)
      for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      log_step("TS-WINDOW[UNIT]", "pre-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[UNIT] pre-42432")        -- ★ 新增
      reaper.Main_OnCommand(42432, 0)
      log_step("TS-WINDOW[UNIT]", "post-42432 selected_items=%d", reaper.CountSelectedMediaItems(0))
      dbg_dump_selection("TSW[UNIT] post-42432")       -- ★ 新增

      local glued = reaper.GetSelectedMediaItem(0, 0)
      if not glued then
        reaper.MB("TS-Window glue failed: no item after 42432 (unit).", "AudioSweet", 0)
        goto continue_unit
      end

      local ok, used_cmd = apply_focused_fx_to_item(glued, FXmediaTrack, fxIndex, CHAIN_TOKEN)
      if ok then
        log_step("TS-WINDOW[UNIT]", "applied %d", used_cmd or -1)
        table.insert(outputs, glued)  -- out item已被移回原軌
      else
        log_step("TS-WINDOW[UNIT]", "apply failed")
      end
    else
      --------------------------------------------------------------
      -- Core/GLUE（含 handles）：無 TS 或 TS==unit
      --------------------------------------------------------------

      -- Move all unit items to FX track (keep as-is), but select only the anchor for Core.
      move_items_to_track(u.items, FXmediaTrack)
      isolate_focused_fx(FXmediaTrack, fxIndex)
      -- Select the entire unit (non-TS path should preserve full unit selection)
      local anchor = u.items[1]  -- still used for channel auto and safety
      select_only_items_checked(u.items)

      -- [DBG] after move: how many unit items are actually on the FX track?
      do
        local moved = 0
        for _,it in ipairs(u.items) do
          if it and reaper.GetMediaItem_Track(it) == FXmediaTrack then
            moved = moved + 1
          end
        end
        log_step("CORE", "post-move: on-FX=%d / unit=%d", moved, #u.items)

        if debug_enabled() then
          local L = u.UL - project_epsilon()
          local R = u.UR + project_epsilon()
          dbg_track_items_in_range(FXmediaTrack, L, R)
        end
      end


      -- [DBG] selection should equal the full unit at this point
      do
        local selN = reaper.CountSelectedMediaItems(0)
        log_step("CORE", "pre-apply selection count=%d (expect=%d)", selN, #u.items)
        dbg_dump_selection("CORE pre-apply selection")
      end  

      -- Load Core (no goto; use failed flag to reach cleanup safely)
      local failed = false
      local CORE_PATH = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua"
      local ok_mod, mod = pcall(dofile, CORE_PATH)
      if not ok_mod or not mod then
        log_step("ERROR", "Core load failed: %s", CORE_PATH)
        reaper.MB("RGWH Core not found or failed to load:\n" .. CORE_PATH, "AudioSweet — Core load failed", 0)
        failed = true
      end

      local apply = nil
      if not failed then
        apply = (type(mod)=="table" and type(mod.apply)=="function") and mod.apply
                 or (_G.RGWH and type(_G.RGWH.apply)=="function" and _G.RGWH.apply)
        if not apply then
          log_step("ERROR", "RGWH.apply not found in module")
          reaper.MB("RGWH Core loaded, but RGWH.apply(...) not found.", "AudioSweet — Core apply missing", 0)
          failed = true
        end
      end

      -- Resolve auto apply_fx_mode by MAX channels across the entire unit
      local apply_fx_mode = nil
      if not failed then
        apply_fx_mode = reaper.GetExtState("hsuanice_AS","AS_APPLY_FX_MODE")
        if apply_fx_mode == "" or apply_fx_mode == "auto" then
          local ch = unit_max_channels(u)
          apply_fx_mode = (ch <= 1) and "mono" or "multi"
        end
      end

      if debug_enabled() then
        local c = reaper.CountSelectedMediaItems(0)
        log_step("CORE", "pre-apply selected_items=%d (expect = unit members=%d)", c, #u.items)
      end

      -- Snapshot & set project flags
      local snap = {}

      local function proj_get(ns, key, def)
        local _, val = reaper.GetProjExtState(0, ns, key)
        return (val == "" and def) or val
      end
      local function proj_set(ns, key, val)
        reaper.SetProjExtState(0, ns, key, tostring(val or ""))
      end

      -- (A) 檢查：unit 的所有 items 是否已經搬到 FX 軌
      if not items_all_on_track(u.items, FXmediaTrack) then
        log_step("ERROR", "unit members not on FX track; fixing...")
        move_items_to_track(u.items, FXmediaTrack)
      end
      -- (B) 檢查：selection 是否等於整個 unit
      select_only_items_checked(u.items)
      if debug_enabled() then
        log_step("CORE", "pre-apply selected_items=%d (expect=%d)", reaper.CountSelectedMediaItems(0), #u.items)
      end

      -- (C) Snapshot
      snap.GLUE_TAKE_FX      = proj_get("RGWH","GLUE_TAKE_FX","")
      snap.GLUE_TRACK_FX     = proj_get("RGWH","GLUE_TRACK_FX","")
      snap.GLUE_APPLY_MODE   = proj_get("RGWH","GLUE_APPLY_MODE","")
      snap.GLUE_SINGLE_ITEMS = proj_get("RGWH","GLUE_SINGLE_ITEMS","")

      -- (D) Set desired flags
      proj_set("RGWH","GLUE_TAKE_FX","1")
      proj_set("RGWH","GLUE_TRACK_FX","1")
      proj_set("RGWH","GLUE_APPLY_MODE",apply_fx_mode)
      proj_set("RGWH","GLUE_SINGLE_ITEMS","1")  -- 正確語意：就算 unit 只有 1 顆 item 也走 glue

      if debug_enabled() then
        local _, gsi = reaper.GetProjExtState(0, "RGWH", "GLUE_SINGLE_ITEMS")
        log_step("CORE", "flag GLUE_SINGLE_ITEMS=%s (expected=1 for unit-glue)", (gsi == "" and "(empty)") or gsi)
      end

      -- (E) 準備參數，並完整印出（單一 item）
      if not (anchor and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, anchor, "MediaItem*"))) then
        log_step("ERROR", "anchor item invalid (u.items[1]=%s)", tostring(anchor))
        reaper.MB("Internal error: unit anchor item is invalid.", "AudioSweet", 0)
        failed = true
      else
        -- （保持你現有的 args 組裝…）
        local args = {
          mode                = "glue_item_focused_fx",  -- ★ 改這行：讓 Core 以「整個 selection」為主體
          item                = anchor,
          apply_fx_mode       = apply_fx_mode,
          focused_track       = FXmediaTrack,
          focused_fxindex     = fxIndex,
          policy_only_focused = true,
          selection_scope     = "selection",
          -- glue_single_items  不再由前端傳入，統一交由 RGWH 專案旗標（GLUE_SINGLE_ITEMS）決定
        }
        if debug_enabled() then
          local c = reaper.CountSelectedMediaItems(0)
          log_step("CORE", "apply args: mode=%s apply_fx_mode=%s focus_idx=%d sel_scope=%s unit_members=%d",
            tostring(args.mode), tostring(args.apply_fx_mode), fxIndex, tostring(args.selection_scope), #u.items)
          log_step("CORE", "pre-apply FINAL selected_items=%d", c)
          dbg_dump_selection("CORE pre-apply FINAL")
        end

        if debug_enabled() then
          log_step("CORE", "apply args: scope=%s members=%d", tostring(args.selection_scope), #u.items)
        end

        -- (F) 呼叫 Core（pcall 包起來，抓 runtime error）
        local ok_call, ok_apply, err = pcall(apply, args)
        if not ok_call then
          log_step("ERROR", "apply() runtime error: %s", tostring(ok_apply))
          reaper.MB("RGWH Core apply() runtime error:\n" .. tostring(ok_apply), "AudioSweet — Core apply error", 0)
          failed = true
        else
          if not ok_apply then
            if debug_enabled() then
              log_step("ERROR", "apply() returned false; err=%s", tostring(err))
            end
            reaper.MB("RGWH Core apply() error:\n" .. tostring(err or "(nil)"), "AudioSweet — Core apply error", 0)
            failed = true
          end
        end

      end
      -- (G) Restore flags immediately
      proj_set("RGWH","GLUE_TAKE_FX",      snap.GLUE_TAKE_FX)
      proj_set("RGWH","GLUE_TRACK_FX",     snap.GLUE_TRACK_FX)
      proj_set("RGWH","GLUE_APPLY_MODE",   snap.GLUE_APPLY_MODE)
      proj_set("RGWH","GLUE_SINGLE_ITEMS", snap.GLUE_SINGLE_ITEMS)

      -- Pick output, rename, move back
      if not failed then
        local postItem = reaper.GetSelectedMediaItem(0, 0)
        if not postItem then
          reaper.MB("Core finished, but no item is selected.", "AudioSweet", 0)
          failed = true
        else
          append_fx_to_take_name(postItem, CHAIN_TOKEN)
          local origTR = u.track
          reaper.MoveMediaItemToTrack(postItem, origTR)
          table.insert(outputs, postItem)
          -- Mark Core done once to keep non–TS-Window behavior single-item

        end

        -- [DBG] after Core: what is selected and which item will be picked?
        if debug_enabled() then
          dbg_dump_selection("CORE post-apply selection")
          if postItem then
            dbg_item_brief(postItem, "CORE picked postItem")
          end
        end        

      end
      -- Ensure any remaining original items (if any) go back
      move_items_to_track(u.items, u.track)
      -- Un-bypass everything on FX track
      local cnt = reaper.TrackFX_GetCount(FXmediaTrack)
      for i=0, cnt-1 do reaper.TrackFX_SetEnabled(FXmediaTrack, i, true) end
    end
    ::continue_unit::
  end

  log_step("END", "outputs=%d", #outputs)

  -- 還原執行前的選取
  restore_selection(sel_snapshot)
  if debug_enabled() then dbg_dump_selection("RESTORE selection") end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("AudioSweet multi-item glue", 0)
end

reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)
