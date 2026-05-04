--[[
hsuanice_Subtitle Bridge.lua
v0.1.0

Calls Tools/subtitle_to_clb.py to read subtitle / dialogue-list files
(.srt / .csv / .tsv / .xlsx / .xlsm) and convert them into CLB-compatible
parsed tables.

Two-phase API:
  M.inspect(filepath, opts)
    Returns inspection metadata (sheets, columns, sample rows, auto-detected
    IN/OUT columns, text-column candidates) so the caller can prompt the user
    for sheet / text-column / FPS selections.
    For SRT (which has no choices) returns ready=true.

  M.parse(filepath, opts)
    Returns a CLB-parsed table (same shape as hsuanice_OTIO Bridge.M.parse
    output: format, title, fps, is_drop, source_path, events[]).

opts (all optional):
  python       string    Python executable (default: M.python or "python3")
  default_fps  number    FPS for TC conversion (default 25)
  is_drop      bool      Drop-frame flag (default false)
  sheet        string|int  Sheet name or 1-based index (xlsx only)
  in_col       int       1-based IN column (csv/tsv/xlsx)
  out_col      int       1-based OUT column (csv/tsv/xlsx)
  text_col     int       1-based text column (csv/tsv/xlsx)

Both inspect and parse are SYNCHRONOUS — subtitle files are small and
parse fast; the async pattern used by OTIO Bridge would just add latency
to the user-facing dialog flow.

Requires:
  Library/json.lua
  Library/hsuanice_EDL Parser.lua  (for tc_to_seconds / seconds_to_tc)
  Tools/subtitle_to_clb.py
  Python 3, plus openpyxl for .xlsx files (pip3 install openpyxl)

Changelog:
  v0.1.0  Initial release: SRT / CSV / TSV / XLSX support; inspect + parse modes.
--]]

local M = {}
M.VERSION = "0.1.0"

-- ---------------------------------------------------------------------------
-- Path discovery
-- ---------------------------------------------------------------------------

local _info    = debug.getinfo(1, "S")
local _lib_dir = _info.source:match("@?(.*[/\\])") or ""
local _root_dir = _lib_dir:match("^(.*[/\\])[^/\\]*[/\\]$") or _lib_dir

local _json_path     = _lib_dir  .. "json.lua"
local _edl_path      = _lib_dir  .. "hsuanice_EDL Parser.lua"
local _python_script = _root_dir .. "Tools/subtitle_to_clb.py"

-- ---------------------------------------------------------------------------
-- Load dependencies
-- ---------------------------------------------------------------------------

local ok_json, JSON = pcall(dofile, _json_path)
if not ok_json then
  error("Subtitle Bridge: cannot load json.lua\n  Expected: " .. _json_path
        .. "\n  Error: " .. tostring(JSON))
end

local ok_edl, EDL = pcall(dofile, _edl_path)
if not ok_edl then
  error("Subtitle Bridge: cannot load EDL Parser\n  Expected: " .. _edl_path
        .. "\n  Error: " .. tostring(EDL))
end

-- Default Python executable; override with M.python = "/full/path/to/python3"
M.python = "python3"

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Run subtitle_to_clb.py with the given args; return (raw_output, err).
--- Captures both stdout and stderr (merged) so Python tracebacks are visible.
local function _run_python(python, args)
  local f = io.open(_python_script, "r")
  if not f then
    return nil,
      "Subtitle Python script not found.\n  Expected: " .. _python_script
  end
  f:close()

  local cmd = shell_quote(python) .. " " .. shell_quote(_python_script)
  for _, a in ipairs(args) do
    cmd = cmd .. " " .. shell_quote(a)
  end
  cmd = cmd .. " 2>&1"

  local h, popen_err = io.popen(cmd, "r")
  if not h then
    return nil, "io.popen failed: " .. tostring(popen_err)
                 .. "\n  Command was: " .. cmd
  end
  local out = h:read("*a")
  h:close()

  if not out or out == "" then
    return nil,
      "No output from Python script.\n"
      .. "  Is '" .. python .. "' in your PATH?\n"
      .. "  Is openpyxl installed (for .xlsx)? Run: pip3 install openpyxl\n"
      .. "  Command: " .. cmd
  end
  return out, nil
end

--- Strip non-JSON prefix lines (e.g. Python warnings on stderr merged into
--- stdout via 2>&1) and decode the remainder.
local function _decode_json(raw)
  local s = raw
  local i = s:find("{")
  if i and i > 1 then s = s:sub(i) end
  local ok, data = pcall(JSON.decode, s)
  if not ok then
    return nil,
      "JSON decode error: " .. tostring(data)
      .. "\n  Raw output (first 400 chars):\n" .. raw:sub(1, 400)
  end
  if type(data) == "table" and data.error then
    local msg = tostring(data.error)
    if data.traceback then msg = msg .. "\n\n" .. tostring(data.traceback) end
    return nil, msg
  end
  return data, nil
end

-- ---------------------------------------------------------------------------
-- Public API: inspect
-- ---------------------------------------------------------------------------

--- Probe a subtitle file and return inspection metadata.
---
--- Return shape varies by format:
---   SRT:
---     { format="SRT", ready=true, title=..., events_seconds={...} }
---   CSV / TSV:
---     { format="CSV"|"TSV", ready=false, title=..., encoding=..., header_present=...,
---       columns=[{index,name},...], sample_rows=[{...}], detected_in_col, detected_out_col,
---       text_candidates=[col1, col2, ...] }
---   XLSX:
---     { format="XLSX", ready=false, title=...,
---       sheets=[{name, columns, sample_rows, detected_in_col, detected_out_col,
---                text_candidates, header_present}, ...] }
---
--- @param filepath string
--- @param opts table|nil    { python=string }
--- @return table|nil
--- @return string|nil       Error message if nil was returned
function M.inspect(filepath, opts)
  opts = opts or {}
  local python = opts.python or M.python
  local args = { "--inspect", filepath }
  local raw, err = _run_python(python, args)
  if not raw then return nil, err end
  return _decode_json(raw)
end

-- ---------------------------------------------------------------------------
-- Public API: parse
-- ---------------------------------------------------------------------------

--- Parse a subtitle file into a CLB-compatible parsed table.
---
--- @param filepath string
--- @param opts table|nil    {
---     python=string, default_fps=number, is_drop=bool,
---     sheet=string|int, in_col=int, out_col=int, text_col=int }
--- @return table|nil    Parsed table (compatible with EDL.parse() shape).
--- @return string|nil   Error message if nil was returned.
function M.parse(filepath, opts)
  opts = opts or {}
  local python = opts.python or M.python
  local fps = tonumber(opts.default_fps) or 25
  local args = { "--parse", filepath, "--fps=" .. tostring(fps) }
  if opts.is_drop then args[#args + 1] = "--drop-frame" end
  if opts.sheet ~= nil and opts.sheet ~= "" then
    args[#args + 1] = "--sheet=" .. tostring(opts.sheet)
  end
  if opts.in_col   then args[#args + 1] = "--in-col="   .. tostring(opts.in_col)   end
  if opts.out_col  then args[#args + 1] = "--out-col="  .. tostring(opts.out_col)  end
  if opts.text_col then args[#args + 1] = "--text-col=" .. tostring(opts.text_col) end

  local raw, err = _run_python(python, args)
  if not raw then return nil, err end

  local data, derr = _decode_json(raw)
  if not data then return nil, derr end

  return M._to_parsed(data, filepath, fps)
end

-- ---------------------------------------------------------------------------
-- Internal: JSON dict → parsed table  (mirrors OTIO Bridge._to_parsed)
-- ---------------------------------------------------------------------------

function M._to_parsed(data, source_path, default_fps)
  local fps     = tonumber(data.fps) or default_fps or 25
  local is_drop = (data.is_drop == true)

  local parsed = {
    format      = data.format or "SUBTITLE",
    title       = data.title  or "",
    fps         = fps,
    is_drop     = is_drop,
    source_path = source_path,
    events      = {},
  }

  for _, ev in ipairs(data.events or {}) do
    local rec_in  = ev.rec_tc_in  or "00:00:00:00"
    local rec_out = ev.rec_tc_out or "00:00:00:00"

    local dur_sec = EDL.tc_to_seconds(rec_out, fps, is_drop)
                  - EDL.tc_to_seconds(rec_in,  fps, is_drop)
    if dur_sec < 0 then dur_sec = 0 end

    local round_fps = math.floor(fps + 0.5)

    parsed.events[#parsed.events + 1] = {
      event_num        = ev.event_num   or "",
      reel             = ev.reel        or "",
      track            = ev.track       or "",
      edit_type        = ev.edit_type   or "C",
      dissolve_len     = ev.dissolve_len,
      src_tc_in        = ev.src_tc_in   or "00:00:00:00",
      src_tc_out       = ev.src_tc_out  or "00:00:00:00",
      rec_tc_in        = rec_in,
      rec_tc_out       = rec_out,
      clip_name        = ev.clip_name   or "",
      source_file      = ev.source_file or "",
      scene            = ev.scene       or "",
      take             = ev.take        or "",
      comments         = {},
      duration_seconds = dur_sec,
      duration_tc      = EDL.seconds_to_tc(dur_sec, fps, is_drop),
      duration_frames  = math.floor(dur_sec * round_fps + 0.5),
    }
  end

  return parsed
end

return M
