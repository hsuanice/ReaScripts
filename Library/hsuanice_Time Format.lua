-- hsuanice_TimeFormat.lua
-- v0.2.0
-- Unified, future-proof time format/parse helpers for REAPER scripts.

local M = {}
M.VERSION = "0.2.0"

-- Modes as canonical symbols (avoid magic strings elsewhere)
M.MODE = { SEC = "sec", TC = "tc", BEATS = "beats" }

local MODE_BEATS    = 1  -- reaper.format_timestr_pos / parse_timestr_pos
local MODE_TIMECODE = 5
local MODE_HMS      = 0  -- parse H:M:S.xxx

-- ===== core formatters =====
local function _fmt_seconds(sec, decimals) return (sec and string.format("%."..tostring(decimals or 6).."f", sec)) or "" end
local function _fmt_tc(sec)    return (sec and reaper.format_timestr_pos(sec, "", MODE_TIMECODE)) or "" end
local function _fmt_beats(sec) return (sec and reaper.format_timestr_pos(sec, "", MODE_BEATS)) or "" end

-- ===== core parsers =====
local function _parse_tc(s)    if not s or s=="" then return nil end; local v=reaper.parse_timestr_pos(s, MODE_TIMECODE); return type(v)=="number" and v or nil end
local function _parse_beats(s) if not s or s=="" then return nil end; local v=reaper.parse_timestr_pos(s, MODE_BEATS);    return type(v)=="number" and v or nil end
local function _parse_sec(s)
  if not s or s=="" then return nil end
  local n = tonumber(s); if n then return n end
  local v = reaper.parse_timestr_pos(s, MODE_HMS); return type(v)=="number" and v or nil
end

-- ===== public: format / parse / convert =====
function M.format(seconds, mode, opts)
  local m = mode or M.MODE.SEC
  if m == M.MODE.TC    then return _fmt_tc(seconds)
  elseif m == M.MODE.BEATS then return _fmt_beats(seconds)
  else                      return _fmt_seconds(seconds, (opts and opts.decimals) or 6) end
end

function M.parse(str, mode)
  local m = mode or M.MODE.SEC
  if m == M.MODE.TC    then return _parse_tc(str)
  elseif m == M.MODE.BEATS then return _parse_beats(str)
  else                      return _parse_sec(str) end
end

-- Convert textual representations via seconds hub
-- from_mode/to_mode: M.MODE.*
-- returns string; decimals applies when to_mode == SEC
function M.convert_text(str, from_mode, to_mode, opts)
  local s = M.parse(str, from_mode); if not s then return nil end
  return M.format(s, to_mode, opts)
end

-- Convenience: seconds <-> quarter notes (QN)
function M.seconds_to_qn(seconds) return seconds and reaper.TimeMap_timeToQN(seconds) or nil end
function M.qn_to_seconds(qn)      return qn and reaper.TimeMap_QNToTime(qn) or nil end

-- ===== UI helpers =====
-- Build a reusable formatter closure for hot loops (tables, exports)
function M.make_formatter(mode, opts)
  local m = mode or M.MODE.SEC
  if m == M.MODE.TC    then return _fmt_tc
  elseif m == M.MODE.BEATS then return _fmt_beats
  else
    local dec = (opts and opts.decimals) or 6
    return function(sec) return _fmt_seconds(sec, dec) end
  end
end

-- Column titles for Start/End given a mode
function M.headers(mode)
  local m = mode or M.MODE.SEC
  if m == M.MODE.TC       then return "Start (TC)", "End (TC)"
  elseif m == M.MODE.BEATS then return "Start (Beats)", "End (Beats)"
  else                        return "Start (s)", "End (s)" end
end

-- ===== Back-compat shims (safe to remove later if nothing depends on them) =====
function M.format_seconds(s, decimals) return _fmt_seconds(s, decimals) end
function M.format_tc(s)                return _fmt_tc(s) end
function M.format_beats(s)             return _fmt_beats(s) end
function M.parse_seconds(s)            return _parse_sec(s) end
function M.parse_tc(s)                 return _parse_tc(s) end
function M.parse_beats(s)              return _parse_beats(s) end

return M
