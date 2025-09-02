--[[
hsuanice_Time Format.lua
v0.2.1
Future-proof time format/parse helpers for REAPER scripts.



v0.2.1 (2025-09-02)
- New: Minutes:Seconds mode (MODE.MS) with formatter and parser. Accepts M:SS(.fff) with optional leading '-'.
- Fix: Beat display reliability (uses REAPER mode=1 consistently; no silent fallback to seconds).
- Rounding guard: Prevent 59.9995 → 60.000 carry; clamps to next minute cleanly.
- API: make_formatter() now supports MS; headers() returns "Start (m:s) / End (m:s)" for MS.
- Housekeeping: File name unified to "hsuanice_Time Format.lua" (no API changes).

v0.2.0 (2025-09-02)
- Unified API: Introduced MODE constants (SEC, TC, BEATS), plus format(), parse(), convert_text(), make_formatter(), and headers().
- Performance: make_formatter(mode, opts) returns a closure for hot loops (tables/exports).
- Back-compat: Shims (format_tc, format_seconds, format_beats, etc.) retained so older scripts keep working.

v0.1.0 (2025-09-02)
- Initial release: Formatting & parsing for Seconds, Timecode (follows project FPS), and Beats (follows tempo map).
- Utilities: convert_text(from, to) for cross-mode string conversion; QN helpers (seconds_to_qn, qn_to_seconds).


--]]
local M = {}
M.VERSION = "0.2.1"

-- Canonical modes
M.MODE = { SEC="sec", MS="ms", TC="tc", BEATS="beats" }

-- REAPER modes
local MODE_BEATS    = 1
local MODE_TIMECODE = 5
local MODE_HMS      = 0

-- ---------- formatters ----------
local function _fmt_seconds(sec, decimals)
  if sec == nil then return "" end
  return string.format("%."..tostring(decimals or 6).."f", sec)
end

local function _fmt_tc(sec)
  if sec == nil then return "" end
  return reaper.format_timestr_pos(sec, "", MODE_TIMECODE)
end

local function _fmt_beats(sec)
  if sec == nil then return "" end
  return reaper.format_timestr_pos(sec, "", MODE_BEATS)
end

local function _fmt_ms(sec, decimals)
  if sec == nil then return "" end
  local sign = ""
  if sec < 0 then sign = "-"; sec = -sec end
  local m = math.floor(sec / 60)
  local s = sec - m*60
  local dec = tonumber(decimals) or 3
  -- 保障 0..59.999 範圍避免 59.9995 → 60.000 邊界
  local cap = 60 - (10^-dec) * 0.5
  if s >= cap then
    m = m + 1
    s = 0
  end
  local s_fmt = ("%0."..dec.."f"):format(s)
  if tonumber(s_fmt) < 10 then s_fmt = "0"..s_fmt end
  return ("%s%d:%s"):format(sign, m, s_fmt)
end

-- ---------- parsers ----------
local function _parse_tc(str)
  if not str or str=="" then return nil end
  local v = reaper.parse_timestr_pos(str, MODE_TIMECODE)
  return type(v)=="number" and v or nil
end

local function _parse_beats(str)
  if not str or str=="" then return nil end
  local v = reaper.parse_timestr_pos(str, MODE_BEATS)
  return type(v)=="number" and v or nil
end

local function _parse_sec(str)
  if not str or str=="" then return nil end
  local n = tonumber(str); if n then return n end
  local v = reaper.parse_timestr_pos(str, MODE_HMS)
  return type(v)=="number" and v or nil
end

local function _parse_ms(str)
  if not str or str=="" then return nil end
  -- Accept: M:SS(.fff), MM:SS(.fff), with optional leading '-' sign
  local sign, m, s = str:match("^%s*([%-]?)(%d+):([%d%.]+)%s*$")
  if not m or not s then return nil end
  m = tonumber(m); s = tonumber(s)
  if not m or not s or s>=60 then return nil end
  local sec = m*60 + s
  if sign == "-" then sec = -sec end
  return sec
end

-- ---------- public API ----------
function M.format(seconds, mode, opts)
  local m = mode or M.MODE.MS
  if m == M.MODE.TC    then return _fmt_tc(seconds)
  elseif m == M.MODE.BEATS then return _fmt_beats(seconds)
  elseif m == M.MODE.SEC   then return _fmt_seconds(seconds, (opts and opts.decimals) or 6)
  else                         return _fmt_ms(seconds, (opts and opts.decimals) or 3)
  end
end

function M.parse(str, mode)
  local m = mode or M.MODE.MS
  if m == M.MODE.TC    then return _parse_tc(str)
  elseif m == M.MODE.BEATS then return _parse_beats(str)
  elseif m == M.MODE.SEC   then return _parse_sec(str)
  else                         return _parse_ms(str)
  end
end

function M.convert_text(str, from_mode, to_mode, opts)
  local s = M.parse(str, from_mode); if not s then return nil end
  return M.format(s, to_mode, opts)
end

function M.seconds_to_qn(seconds) return seconds and reaper.TimeMap_timeToQN(seconds) or nil end
function M.qn_to_seconds(qn)      return qn and reaper.TimeMap_QNToTime(qn) or nil end

function M.make_formatter(mode, opts)
  local m = mode or M.MODE.MS
  if m == M.MODE.TC    then return _fmt_tc
  elseif m == M.MODE.BEATS then return _fmt_beats
  elseif m == M.MODE.SEC   then
    local dec = (opts and opts.decimals) or 6
    return function(sec) return _fmt_seconds(sec, dec) end
  else
    local dec = (opts and opts.decimals) or 3
    return function(sec) return _fmt_ms(sec, dec) end
  end
end

function M.headers(mode)
  local m = mode or M.MODE.MS
  if m == M.MODE.TC       then return "Start (TC)",   "End (TC)"
  elseif m == M.MODE.BEATS then return "Start (Beats)","End (Beats)"
  elseif m == M.MODE.SEC   then return "Start (s)",    "End (s)"
  else                          return "Start (m:s)",  "End (m:s)"
  end
end

-- back-compat shim
function M.format_seconds(s,d) return _fmt_seconds(s,d) end
function M.format_tc(s)        return _fmt_tc(s) end
function M.format_beats(s)     return _fmt_beats(s) end
function M.parse_seconds(s)    return _parse_sec(s) end
function M.parse_tc(s)         return _parse_tc(s) end
function M.parse_beats(s)      return _parse_beats(s) end

return M
