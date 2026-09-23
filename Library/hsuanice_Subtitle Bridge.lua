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
  Library/hsuanice_Process Exec.lua  (shell exec + reliable output capture)
  Tools/subtitle_to_clb.py
  Python 3, plus openpyxl for .xlsx files (pip3 install openpyxl)

Changelog:
  v0.1.4  Refactor: _python_works/_detect_python/_resolve_python's "run
          python, else scan a candidate path list" logic moved into the
          new shared hsuanice_Process Exec.lua (PX.python_works/
          PX.resolve_python), since hsuanice_OTIO Bridge.lua had the same
          skeleton (plus its own opentimelineio import probe, passed via
          opts there). No behavior change — same default candidate list,
          no extra probe needed here.
  v0.1.3  Refactor: _run_python_once/_run_python's temp-file-redirect +
          retry logic (added in v0.1.2) moved into the new shared
          hsuanice_Process Exec.lua (PX.run_capture), since
          hsuanice_OTIO Bridge.lua v0.4.2 had an identical copy for the
          same io.popen problem. No behavior change.
  v0.1.2  Fix: "No output from Python script" persisted even after v0.1.1's
          retry — confirmed the real cause is io.popen's pipe read being
          unreliable specifically when called from inside Reaper (exit 0,
          zero bytes read, every attempt) against a real multi-sheet
          .xlsx, even though the identical command always succeeds run
          directly in a shell, and even a standalone Lua 5.4 interpreter's
          io.popen succeeds too. Switched to the same technique
          hsuanice_OTIO Bridge.lua already relies on for exactly this
          class of problem: redirect the Python process's stdout+stderr to
          a temp file via shell redirection (os.execute, blocking — this
          module is intentionally synchronous), then read that file back
          from disk instead of through a pipe.
  v0.1.1  Fix: "No output from Python script" could fire even though the
          exact same command always succeeded run directly in a shell —
          seen once against a large .xlsx via openpyxl. _run_python now
          retries once automatically on empty output before reporting an
          error, and the error (if it still happens) now also reports the
          child process's exit status for better diagnosis.
  v0.1.0  Initial release: SRT / CSV / TSV / XLSX support; inspect + parse modes.
--]]

local M = {}
M.VERSION = "0.1.4"

-- ---------------------------------------------------------------------------
-- Path discovery
-- ---------------------------------------------------------------------------

local _info    = debug.getinfo(1, "S")
local _lib_dir = _info.source:match("@?(.*[/\\])") or ""
local _root_dir = _lib_dir:match("^(.*[/\\])[^/\\]*[/\\]$") or _lib_dir

local _json_path     = _lib_dir  .. "json.lua"
local _edl_path      = _lib_dir  .. "hsuanice_EDL Parser.lua"
local _px_path       = _lib_dir  .. "hsuanice_Process Exec.lua"
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

local ok_px, PX = pcall(dofile, _px_path)
if not ok_px then
  error("Subtitle Bridge: cannot load Process Exec\n  Expected: " .. _px_path
        .. "\n  Error: " .. tostring(PX))
end

-- Default Python executable; override with M.python = "/full/path/to/python3"
M.python = "python3"

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local shell_quote = PX.shell_quote

-- ---------------------------------------------------------------------------
-- Python runtime detection (independent of OTIO Bridge — subtitle parsing
-- needs no special libraries beyond stdlib + optional openpyxl for .xlsx,
-- so it must not fail just because an otio-env virtualenv was removed).
-- Delegates to hsuanice_Process Exec.lua's PX.resolve_python with no extra
-- probe and the default candidate list (a plain "does python run" check is
-- all this module needs — no special import requirement like OTIO Bridge).
-- ---------------------------------------------------------------------------

--- Resolve a usable python executable: prefer the given path if it actually
--- runs; otherwise fall back to auto-detection. Handles a stale saved path
--- (e.g. an OTIO.python virtualenv that was later removed) transparently.
local function _resolve_python(py)
  return PX.resolve_python(py)
end

--- Run subtitle_to_clb.py with the given args; return (raw_output, err).
--- Captures both stdout and stderr (merged) so Python tracebacks are
--- visible. Delegates to hsuanice_Process Exec.lua's PX.run_capture, which
--- redirects output to a temp file and retries once on empty output — see
--- that file's header for why (Reaper's io.popen is unreliable for
--- substantial subprocess stdout).
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

  local out, exec_ok, exec_why, exec_code = PX.run_capture(cmd)

  if not out or out == "" then
    local status = ""
    if exec_why then
      status = string.format("\n  Process %s: %s", tostring(exec_why), tostring(exec_code))
    end
    return nil,
      "No output from Python script (after 2 attempts).\n"
      .. "  Is '" .. python .. "' in your PATH?\n"
      .. "  Is openpyxl installed (for .xlsx)? Run: pip3 install openpyxl\n"
      .. "  Command: " .. cmd .. status
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
  local python = _resolve_python(opts.python or M.python)
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
  local python = _resolve_python(opts.python or M.python)
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
