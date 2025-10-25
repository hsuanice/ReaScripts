--[[
hsuanice_Time Format.lua
v0.3.0
Future-proof time format/parse helpers for REAPER scripts.

Changelog
v0.3.0 (2025-09-03)
- New: Custom display mode (MODE.CUSTOM) with user-defined patterns.
  • Supported tokens: h / hh (hours), m / mm (minutes), s / ss (seconds), S… (fractional seconds; count = digits, e.g., SSS = .mmm).
  • API: format(sec, MODE.CUSTOM, {pattern="hh:mm:ss"}), make_formatter(MODE.CUSTOM, {pattern=...}), headers(MODE.CUSTOM, {pattern=...}).
- UX: Clean carry/rounding behavior at boundaries (e.g., 59.9995 → 60.000) for custom patterns.
- Docs: Added usage hints for common patterns (hh:mm:ss, h:mm, mm:ss.SSS).

v0.2.1 (2025-09-02)
- New: Minutes:Seconds mode (MODE.MS) with formatter and parser (accepts M:SS(.fff) with optional leading ‘-’).
- Fix: Beats display reliability (consistently uses REAPER mode=1; no silent fallback to seconds).
- Rounding guard for m:s to avoid 59.9995 → 60.000 artifacts; supports negative times.
- API: make_formatter() supports MS; headers() returns "Start (m:s) / End (m:s)" when MS is selected.
- Housekeeping: File renamed to "hsuanice_Time Format.lua" (update dofile paths).

v0.2.0 (2025-09-02)
- Unified API:
  • MODE constants: SEC, TC, BEATS (later extended with MS, CUSTOM).
  • format(seconds, mode, opts) / parse(str, mode) / convert_text(str, from_mode, to_mode, opts).
  • make_formatter(mode, opts) returns a closure for hot loops (tables/exports).
  • headers(mode) returns Start/End column titles for the chosen mode.
- Back-compat: Kept shims (format_tc/format_seconds/format_beats and parse_* variants) so older scripts keep working.

v0.1.0 (2025-09-02)
- Initial release:
  • Formatting & parsing for Seconds, Timecode (follows project FPS), and Beats (follows tempo map).
  • QN helpers: seconds_to_qn(), qn_to_seconds().
  • convert_text(): cross-mode string conversion via seconds hub.



--]]

local M = {}
M.VERSION = "0.3.0"

-- Canonical modes
M.MODE = { SEC="sec", MS="ms", TC="tc", BEATS="beats", CUSTOM="custom" }

-- REAPER internal modes
local MODE_BEATS    = 1
local MODE_TIMECODE = 5
local MODE_HMS      = 0

-- ---------- core formatters ----------
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
  local dec = tonumber(decimals) or 3
  local s = sec - m*60
  local cap = 60 - (10^-dec) * 0.5
  if s >= cap then m = m + 1; s = 0 end
  local s_fmt = ("%0."..dec.."f"):format(s)
  if tonumber(s_fmt) < 10 then s_fmt = "0"..s_fmt end
  return ("%s%d:%s"):format(sign, m, s_fmt)
end

-- ---------- custom pattern ----------
-- Supported tokens:
--   h / hh  : hours (no pad / 2-digit)
--   m / mm  : minutes (0-59)
--   s / ss  : seconds (0-59)
--   S..     : fractional seconds, number of 'S' = digits (e.g. SSS = .mmm)
-- Notes: negative sign handled; carries (e.g., 59.9995 -> 60.000) guarded.
local function _make_custom(pattern)
  pattern = tostring(pattern or "hh:mm:ss")
  local has_frac, frac_digits = pattern:find("S+")
  local nd = has_frac and frac_digits - has_frac + 1 or 0

  return function(sec)
    if sec == nil then return "" end
    local sign = ""
    if sec < 0 then sign = "-"; sec = -sec end

    -- rounding at requested fractional precision
    local pow = 10^(nd)
    local rounded = (nd > 0) and (math.floor(sec * pow + 0.5) / pow) or math.floor(sec + 0.5)

    local h = math.floor(rounded / 3600)
    local rem = rounded - h*3600
    local m = math.floor(rem / 60)
    local s = rem - m*60

    -- guard 59.999.. -> 60 carry
    local cap = 60 - ((nd>0) and (10^-nd)*0.5 or 0.5)
    if s >= cap then
      s = 0
      m = m + 1
      if m >= 60 then m=0; h=h+1 end
    end

    local out = pattern
    -- fractional seconds
    if nd > 0 then
      local frac = s - math.floor(s)
      local frac_str = string.format("%0"..nd.."d", math.floor(frac * 10^nd + 0.5))
      out = out:gsub(string.rep("S", nd), frac_str)
    end

    -- seconds (integer part)
    local si = math.floor(s + 1e-9)
    out = out:gsub("ss", string.format("%02d", si))
             :gsub("s",  tostring(si))

    -- minutes
    out = out:gsub("mm", string.format("%02d", m))
             :gsub("m",  tostring(m))

    -- hours
    out = out:gsub("hh", string.format("%02d", h))
             :gsub("h",  tostring(h))

    return sign .. out
  end
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
  if m == M.MODE.TC     then return _fmt_tc(seconds)
  elseif m == M.MODE.BEATS  then return _fmt_beats(seconds)
  elseif m == M.MODE.SEC    then return _fmt_seconds(seconds, (opts and opts.decimals) or 6)
  elseif m == M.MODE.MS     then return _fmt_ms(seconds, (opts and opts.decimals) or 3)
  elseif m == M.MODE.CUSTOM then return _make_custom((opts and opts.pattern) or "hh:mm:ss")(seconds)
  else return _fmt_ms(seconds, 3) end
end

function M.parse(str, mode)
  local m = mode or M.MODE.MS
  if m == M.MODE.TC     then return _parse_tc(str)
  elseif m == M.MODE.BEATS  then return _parse_beats(str)
  elseif m == M.MODE.SEC    then return _parse_sec(str)
  elseif m == M.MODE.MS     then return _parse_ms(str)
  else return _parse_ms(str) end
end

function M.convert_text(str, from_mode, to_mode, opts)
  local s = M.parse(str, from_mode); if not s then return nil end
  return M.format(s, to_mode, opts)
end

function M.seconds_to_qn(seconds) return seconds and reaper.TimeMap_timeToQN(seconds) or nil end
function M.qn_to_seconds(qn)      return qn and reaper.TimeMap_QNToTime(qn) or nil end

function M.make_formatter(mode, opts)
  local m = mode or M.MODE.MS
  if m == M.MODE.TC     then return _fmt_tc
  elseif m == M.MODE.BEATS  then return _fmt_beats
  elseif m == M.MODE.SEC    then
    local dec = (opts and opts.decimals) or 6
    return function(sec) return _fmt_seconds(sec, dec) end
  elseif m == M.MODE.MS     then
    local dec = (opts and opts.decimals) or 3
    return function(sec) return _fmt_ms(sec, dec) end
  else
    local pat = (opts and opts.pattern) or "hh:mm:ss"
    local f = _make_custom(pat)
    return function(sec) return f(sec) end
  end
end

function M.headers(mode, opts)
  local m = mode or M.MODE.MS
  if m == M.MODE.TC        then return "Start (TC)","End (TC)"
  elseif m == M.MODE.BEATS then return "Start (Beats)","End (Beats)"
  elseif m == M.MODE.SEC   then return "Start (s)","End (s)"
  elseif m == M.MODE.MS    then return "Start (m:s)","End (m:s)"
  elseif m == M.MODE.CUSTOM then return "Start (Custom)","End (Custom)"
  else
    return "Start (Custom)","End (Custom)"
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
