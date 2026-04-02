--[[
hsuanice_OTIO Bridge.lua
v0.4.0

Calls the OpenTimelineIO Python wrapper (Tools/otio_to_clb.py) and converts
the JSON output into a parsed table compatible with hsuanice_EDL Parser.lua.

Supported input formats:
  .edl   CMX3600 Edit Decision List
  .xml   FCP7 XML and DaVinci Resolve XML export
  .aaf   AAF via LibAAF aaftool (Tools/aaf_to_otio.py)

API:
  M.parse(filepath, opts)  → parsed_table | nil, error_string

  opts (all optional):
    python       string  Python executable path  (default: "python3")
    default_fps  number  Fallback FPS if not in file (default: 25)

  parsed_table fields (compatible with hsuanice_EDL Parser.parse()):
    format, title, fps, is_drop, source_path
    events[]  →  event_num, reel, track, edit_type, dissolve_len,
                 src_tc_in, src_tc_out, rec_tc_in, rec_tc_out,
                 clip_name, source_file, scene, take, comments,
                 duration_seconds, duration_tc, duration_frames

Requires:
  Library/json.lua
  Library/hsuanice_EDL Parser.lua
  Tools/otio_to_clb.py
  Python 3 with opentimelineio installed

Changelog:
  v0.4.0  Add parse_async_progress() for live per-clip progress during AAF/XML load.
          parse_async_poll() and M.parse() now strip non-JSON prefix from stdout before
          JSON decode (prevents crash on pyaaf2 warning lines prefixed before "{").
  v0.3.0  Add async API: parse_async_start / parse_async_poll for non-blocking AAF loading.
  v0.2.0  Add .aaf support via aaf_to_otio.py + otio_to_clb.py pipeline.
  v0.1.0  Initial release: EDL, FCP7 XML, Resolve XML support.
--]]

local M = {}
M.VERSION = "0.4.0"

-- ---------------------------------------------------------------------------
-- Path discovery
-- ---------------------------------------------------------------------------

local _info    = debug.getinfo(1, "S")
local _lib_dir = _info.source:match("@?(.*[/\\])") or ""
-- _lib_dir = ".../hsuanice Scripts/Library/"
-- Root    = ".../hsuanice Scripts/"
local _root_dir = _lib_dir:match("^(.*[/\\])[^/\\]*[/\\]$") or _lib_dir

local _json_path     = _lib_dir  .. "json.lua"
local _edl_path      = _lib_dir  .. "hsuanice_EDL Parser.lua"
local _python_script = _root_dir .. "Tools/otio_to_clb.py"

-- ---------------------------------------------------------------------------
-- Load dependencies
-- ---------------------------------------------------------------------------

local ok_json, JSON = pcall(dofile, _json_path)
if not ok_json then
  error("OTIO Bridge: cannot load json.lua\n  Expected: " .. _json_path
        .. "\n  Error: " .. tostring(JSON))
end

local ok_edl, EDL = pcall(dofile, _edl_path)
if not ok_edl then
  error("OTIO Bridge: cannot load EDL Parser\n  Expected: " .. _edl_path
        .. "\n  Error: " .. tostring(EDL))
end

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

--- Default Python executable.
--- Override globally:  OTIO.python = "/full/path/to/python3"
--- Or per-call via opts.python.
M.python = "python3"

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Shell-quote a single argument (macOS / Linux single-quote style).
local function shell_quote(s)
  -- Single-quote the whole string; escape any embedded single quotes.
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Probe a Python executable: returns true if it can import opentimelineio.
local function _python_has_otio(py)
  local cmd = shell_quote(py) .. " -c 'import opentimelineio' 2>&1"
  local h = io.popen(cmd, "r")
  if not h then return false end
  local out = h:read("*a"); h:close()
  return out == ""  -- no output = no error = import succeeded
end

--- Auto-detect a Python that has opentimelineio installed.
--- Checks common locations; returns the first working path, or "python3" as fallback.
function M.detect_python()
  local home = os.getenv("HOME") or ""
  local candidates = {
    "python3",
    home .. "/.pyenv/versions/otio-env/bin/python",
    home .. "/.pyenv/shims/python3",
    "/opt/homebrew/bin/python3",
    "/usr/local/bin/python3",
    "python",
  }
  for _, p in ipairs(candidates) do
    if p ~= "" and _python_has_otio(p) then
      return p
    end
  end
  return "python3"
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Parse a timeline file via the appropriate parser.
---
--- Routing:
---   .edl  → native Lua EDL parser (hsuanice_EDL Parser.lua)
---           OTIO's CMX3600 adapter loses record TC offsets and has bugs with
---           dual-track (V+A same event#) EDLs — not suitable for conform workflows.
---   .xml  → OpenTimelineIO Python bridge (FCP7 XML, Resolve XML)
---   .aaf  → aaf_to_otio.py (LibAAF) + otio_to_clb.py, via otio_to_clb.py dispatcher
---
--- @param filepath string    Absolute path to .edl, .xml, or .aaf file.
--- @param opts table|nil     Options: { python=string, default_fps=number }
--- @return table|nil         Parsed data table (EDL.parse()-compatible), or nil.
--- @return string|nil        Error message if nil was returned.
function M.parse(filepath, opts)
  opts = opts or {}

  -- Route .edl → native Lua parser
  local ext = (filepath:match("%.([^./\\]+)$") or ""):lower()
  if ext == "edl" then
    return EDL.parse(filepath, { default_fps = opts.default_fps })
  end

  -- .xml and others → OTIO Python bridge
  local python = opts.python or M.python

  -- Verify the Python script exists
  local f = io.open(_python_script, "r")
  if not f then
    return nil,
      "OTIO Python script not found.\n  Expected: " .. _python_script
  end
  f:close()

  -- Build and run command
  local cmd = python .. " " .. shell_quote(_python_script)
                      .. " " .. shell_quote(filepath)

  local handle, popen_err = io.popen(cmd, "r")
  if not handle then
    return nil, "io.popen failed: " .. tostring(popen_err)
               .. "\n  Command was: " .. cmd
  end

  local output = handle:read("*a")
  handle:close()

  if not output or output == "" then
    return nil,
      "No output from Python script.\n"
      .. "  Is '" .. python .. "' in your PATH?\n"
      .. "  Is opentimelineio installed? Run: pip3 install opentimelineio\n"
      .. "  Command: " .. cmd
  end

  -- Strip any non-JSON prefix lines (e.g. Python logging warnings on stdout)
  local json_start = output:find("{")
  if json_start and json_start > 1 then output = output:sub(json_start) end

  -- Decode JSON output
  local ok_dec, data = pcall(JSON.decode, output)
  if not ok_dec then
    return nil,
      "JSON decode error: " .. tostring(data)
      .. "\n  Raw output (first 400 chars):\n" .. output:sub(1, 400)
  end

  -- Python script returned an error dict
  if type(data) == "table" and data.error then
    local msg = tostring(data.error)
    if data.traceback then
      msg = msg .. "\n\n" .. tostring(data.traceback)
    end
    return nil, msg
  end

  -- Convert to CLB parsed format
  local parsed = M._to_parsed(data, filepath, opts.default_fps)

  -- Attach optional warning from lenient-mode parsing
  if data.warning then
    parsed._warning = data.warning
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Internal: JSON dict → parsed table
-- ---------------------------------------------------------------------------

--- Convert the otio_to_clb.py JSON output into an EDL-parser-compatible table.
---
--- @param data table         Decoded JSON (from otio_to_clb.py)
--- @param source_path string Original file path
--- @param default_fps number|nil  Fallback FPS
--- @return table             Parsed table
function M._to_parsed(data, source_path, default_fps)
  local fps     = tonumber(data.fps) or default_fps or 25
  local is_drop = (data.is_drop == true)

  local parsed = {
    format      = data.format or "UNKNOWN",
    title       = data.title  or "",
    fps         = fps,
    is_drop     = is_drop,
    source_path = source_path,
    events      = {},
  }

  for _, ev in ipairs(data.events or {}) do
    local rec_in  = ev.rec_tc_in  or "00:00:00:00"
    local rec_out = ev.rec_tc_out or "00:00:00:00"

    -- Compute duration fields (same as EDL.parse() does)
    local dur_sec = EDL.tc_to_seconds(rec_out, fps, is_drop)
                  - EDL.tc_to_seconds(rec_in,  fps, is_drop)
    dur_sec = math.max(0, dur_sec)

    local round_fps = math.floor(fps + 0.5)

    parsed.events[#parsed.events + 1] = {
      event_num        = ev.event_num   or "",
      reel             = ev.reel        or "",
      track            = ev.track       or "",
      edit_type        = ev.edit_type   or "C",
      dissolve_len     = ev.dissolve_len,         -- number or nil (JSON null → Lua nil)
      src_tc_in        = ev.src_tc_in   or "00:00:00:00",
      src_tc_out       = ev.src_tc_out  or "00:00:00:00",
      rec_tc_in        = rec_in,
      rec_tc_out       = rec_out,
      clip_name        = ev.clip_name   or "",
      source_file      = ev.source_file or "",
      scene            = ev.scene       or "",
      take             = ev.take        or "",
      comments         = {},
      -- Pre-computed (same fields that EDL.parse() produces)
      duration_seconds = dur_sec,
      duration_tc      = EDL.seconds_to_tc(dur_sec, fps, is_drop),
      duration_frames  = math.floor(dur_sec * round_fps + 0.5),
    }
  end

  return parsed
end

-- ---------------------------------------------------------------------------
-- Async API  (non-blocking: launch Python in background, poll each frame)
-- ---------------------------------------------------------------------------

--- Start parsing a timeline file in the background.
---
--- .edl files are parsed synchronously right now (they're fast) and the
--- result is wrapped in a pre-resolved handle.
--- .xml / .aaf files launch Python as a background shell process whose
--- stdout is redirected to a temp file; a second sentinel file is written
--- when the process exits.
---
--- @param filepath string   Absolute path to the file.
--- @param opts table|nil    Options: { python=string, default_fps=number }
--- @return table|nil        Async handle (pass to parse_async_poll), or nil on launch failure.
--- @return string|nil       Error message if nil was returned.
function M.parse_async_start(filepath, opts)
  opts = opts or {}
  local ext = (filepath:match("%.([^./\\]+)$") or ""):lower()

  -- .edl → run synchronously; wrap in a pre-resolved handle
  if ext == "edl" then
    local result, err = EDL.parse(filepath, { default_fps = opts.default_fps })
    return {
      _resolved    = true,
      _result      = result,
      _err         = err,
      _filepath    = filepath,
      _default_fps = opts.default_fps,
    }, nil
  end

  -- Python bridge: verify script exists
  local python = opts.python or M.python
  local f = io.open(_python_script, "r")
  if not f then
    return nil,
      "OTIO Python script not found.\n  Expected: " .. _python_script
  end
  f:close()

  -- Temp file base  (macOS/Linux → /tmp/luaXXXXXX)
  local tmp_base = os.tmpname()
  os.remove(tmp_base)            -- discard the stub; use it as a name prefix only
  local tmp_json = tmp_base .. ".json"
  local tmp_done = tmp_base .. ".done"
  local tmp_sh   = tmp_base .. ".sh"

  local tmp_progress = tmp_base .. ".progress"

  -- Write a tiny shell script so we can launch it with a single path argument.
  -- Using a script avoids quoting issues and lets us add the sentinel write
  -- without relying on the launcher to interpret shell metacharacters.
  --
  -- The sentinel (tmp_done) is written by the script itself after Python exits,
  -- regardless of success or failure.  Python's stderr is discarded (warnings
  -- already suppressed inside otio_to_clb.py; JSON errors go to stdout).
  local shf = io.open(tmp_sh, "w")
  if not shf then
    return nil, "Cannot create temp file: " .. tmp_sh
  end
  shf:write("#!/bin/sh\n")
  shf:write(shell_quote(python)
    .. " " .. shell_quote(_python_script)
    .. " " .. shell_quote(filepath)
    .. " --progress-file " .. shell_quote(tmp_progress)
    .. " > " .. shell_quote(tmp_json)
    .. " 2>/dev/null\n")
  shf:write("echo done > " .. shell_quote(tmp_done) .. "\n")
  shf:close()
  os.execute("chmod +x " .. shell_quote(tmp_sh))

  -- Launch via reaper.ExecProcess with timeout = -1 (REAPER native async launch).
  -- ExecProcess(-1) spawns the process and returns immediately without waiting —
  -- unlike os.execute() which blocks until the shell child exits, causing a
  -- beach-ball freeze for slow AAF/XML loads.
  -- Fallback: os.execute with & (works if REAPER's Lua os.execute truly detaches).
  if reaper and reaper.ExecProcess then
    reaper.ExecProcess("/bin/sh " .. shell_quote(tmp_sh), -1)
  else
    os.execute("/bin/sh " .. shell_quote(tmp_sh) .. " &")
  end

  return {
    _resolved      = false,
    _python        = python,
    _tmp_json      = tmp_json,
    _tmp_done      = tmp_done,
    _tmp_sh        = tmp_sh,
    _tmp_progress  = tmp_progress,
    _filepath      = filepath,
    _default_fps   = opts.default_fps,
  }, nil
end


--- Read the latest progress written by Python.
---
--- @param handle table   Handle from parse_async_start.
--- @return table|nil     { phase, current, total, name } or nil if not available.
function M.parse_async_progress(handle)
  if not handle or handle._resolved or not handle._tmp_progress then return nil end
  local f = io.open(handle._tmp_progress, "r")
  if not f then return nil end
  local line = f:read("*l")
  f:close()
  if not line then return nil end
  local phase, cur, tot, name = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)")
  if not phase then return nil end
  return {
    phase   = phase,
    current = tonumber(cur) or 0,
    total   = tonumber(tot) or 0,
    name    = name or "",
  }
end


--- Poll an async handle returned by parse_async_start.
---
--- Call this every frame (from your defer loop) until the status is not "loading".
--- Temp files are deleted automatically on first non-loading return.
---
--- @param handle table   Handle from parse_async_start.
--- @return string        "loading" | "done" | "error"
--- @return table|string  Parsed table on "done"; error string on "error"; nil on "loading".
function M.parse_async_poll(handle)
  if not handle then return "error", "nil handle" end

  -- Pre-resolved (EDL sync path)
  if handle._resolved then
    if handle._err then return "error", tostring(handle._err) end
    return "done", handle._result
  end

  -- Check sentinel file written when background process exits
  local sf = io.open(handle._tmp_done, "r")
  if not sf then return "loading", "" end
  sf:close()

  -- Read JSON output
  local jf = io.open(handle._tmp_json, "r")
  local output = jf and jf:read("*a") or ""
  if jf then jf:close() end

  -- Clean up temp files
  os.remove(handle._tmp_json)
  os.remove(handle._tmp_done)
  if handle._tmp_sh       then os.remove(handle._tmp_sh)       end
  if handle._tmp_progress then os.remove(handle._tmp_progress) end

  if not output or output == "" then
    return "error",
      "No output from Python script.\n"
      .. "  Is '" .. (handle._python or "python3") .. "' in your PATH?\n"
      .. "  Is opentimelineio installed? Run: pip3 install opentimelineio"
  end

  -- Strip any non-JSON prefix lines (e.g. "WARNING:root:..." from Python logging
  -- that leaked onto stdout via 2>&1 redirection).
  local json_start = output:find("{")
  if json_start and json_start > 1 then
    output = output:sub(json_start)
  end

  local ok_dec, data = pcall(JSON.decode, output)
  if not ok_dec then
    return "error",
      "JSON decode error: " .. tostring(data)
      .. "\n  Raw output (first 400 chars):\n" .. output:sub(1, 400)
  end

  if type(data) == "table" and data.error then
    local msg = tostring(data.error)
    if data.traceback then msg = msg .. "\n\n" .. tostring(data.traceback) end
    return "error", msg
  end

  local parsed = M._to_parsed(data, handle._filepath, handle._default_fps)
  if data.warning then parsed._warning = data.warning end
  return "done", parsed
end

return M
