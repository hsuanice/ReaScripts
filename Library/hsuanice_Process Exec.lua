--[[
hsuanice_Process Exec.lua
v0.1.0

Shared helper for running an external command from inside Reaper and
reliably capturing its output.

Background: Reaper's io.popen pipe read is unreliable for substantial
subprocess stdout — confirmed by direct reproduction (a real multi-sheet
.xlsx via openpyxl consistently exited 0 with io.popen(cmd,"r"):read("*a")
returning "" from inside Reaper, every attempt, while the identical
command always succeeded run directly in a shell, and even a standalone
Lua 5.4 interpreter's own io.popen succeeded). The fix is to redirect the
child process's stdout+stderr to a temp file via shell redirection
(os.execute, blocking) and read that back from disk instead of through a
pipe. This was originally written twice — hsuanice_Subtitle Bridge.lua
v0.1.2 and hsuanice_OTIO Bridge.lua v0.4.2's synchronous parse path — and
is consolidated here per the user's request once both were validated
against real files.

API:
  PX.shell_quote(s)
    Single-quote a string for /bin/sh (macOS/Linux), escaping embedded
    single quotes.

  PX.run_capture(cmd, opts)
    Run an already-quoted shell command, capturing merged stdout+stderr.
    opts (optional): { retries = int }  -- extra attempts after the first
                                            on empty output (default 1,
                                            i.e. 2 attempts total)
    Returns: output (string|nil), exec_ok, exec_why, exec_code
      output is nil only if the temp file could never be opened/read;
      an empty string means the process ran but produced no output.

  PX.python_works(py, opts)
    Check whether a python executable runs cleanly, optionally requiring
    an extra probe (e.g. a specific module import) to also succeed.
    opts (optional): { probe = string }  -- extra Python code appended
                      after "import sys" (e.g. "import opentimelineio")
    Returns: boolean

  PX.resolve_python(preferred, opts)
    Resolve a usable python executable: return `preferred` if it already
    works (and passes opts.probe, if given); otherwise scan a candidate
    path list and return the first one that works.
    opts (optional):
      probe      string     -- same as PX.python_works
      candidates {string,.} -- override the default candidate path list
      fallback   string     -- returned if nothing matches (default "python3")
    Returns: string (a python path or command name; never nil)

Changelog:
  v0.2.0  Added PX.python_works/PX.resolve_python, extracted from
          hsuanice_Subtitle Bridge.lua's _python_works/_detect_python/
          _resolve_python and hsuanice_OTIO Bridge.lua's
          _python_supports/detect_python/_resolve_python_for_ext — same
          "does this python run (optionally with an extra import check)"
          skeleton duplicated in both, differing only in which candidate
          paths and which extra probe each one needed. Both bridges now
          pass their own candidate list / probe via opts instead of
          keeping separate copies of the scan loop.
  v0.1.0  Initial release. Extracted from hsuanice_Subtitle Bridge.lua
          v0.1.2's _run_python_once/_run_python and
          hsuanice_OTIO Bridge.lua v0.4.2's M.parse retry loop, which had
          the exact same temp-file-redirect + retry pattern.
--]]

local PX = {}
PX.VERSION = "0.2.0"

--- Single-quote a string for /bin/sh, escaping embedded single quotes.
function PX.shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- Run an already-quoted shell command, capturing merged stdout+stderr via
--- a temp file (see file header for why this is preferred over io.popen).
--- Retries on empty output — cheap insurance against a one-off hiccup.
---
--- @param cmd string      Fully-formed, already-quoted shell command (no
---                        redirection appended).
--- @param opts table|nil  { retries = int }  extra attempts after the
---                        first on empty output (default 1 → 2 attempts
---                        total).
--- @return string|nil output, boolean exec_ok, string exec_why, number exec_code
function PX.run_capture(cmd, opts)
  opts = opts or {}
  local attempts = (opts.retries or 1) + 1

  local output, exec_ok, exec_why, exec_code
  for _attempt = 1, attempts do
    local tmp_base = os.tmpname()
    os.remove(tmp_base)   -- discard the stub; use it as a name prefix only
    local tmp_out = tmp_base .. ".out"

    exec_ok, exec_why, exec_code =
      os.execute(cmd .. " > " .. PX.shell_quote(tmp_out) .. " 2>&1")

    local f = io.open(tmp_out, "r")
    if f then
      output = f:read("*a")
      f:close()
    end
    os.remove(tmp_out)

    if output and output ~= "" then break end
  end

  return output, exec_ok, exec_why, exec_code
end

--- Check whether a python executable runs cleanly, optionally requiring an
--- extra probe (e.g. a module import) to also succeed. A cheap io.popen
--- check is fine here (unlike run_capture's job) — this only ever produces
--- a few bytes of error text, well below the size where Reaper's io.popen
--- pipe read has been observed to fail.
--- @param py string|nil
--- @param opts table|nil  { probe = string }  extra Python code appended
---                        after "import sys", e.g. "import opentimelineio"
--- @return boolean
function PX.python_works(py, opts)
  if not py or py == "" then return false end
  opts = opts or {}
  local code = "import sys"
  if opts.probe and opts.probe ~= "" then
    code = code .. "; " .. opts.probe
  end
  local cmd = PX.shell_quote(py) .. " -c '" .. code .. "' 2>&1"
  local h = io.popen(cmd, "r")
  if not h then return false end
  local out = h:read("*a"); h:close()
  return out == ""  -- no output = no error = it worked
end

--- Resolve a usable python executable: prefer `preferred` if it already
--- works (and passes opts.probe, if given); otherwise scan opts.candidates
--- (or a sensible built-in list) and return the first one that works.
--- @param preferred string|nil
--- @param opts table|nil {
---   probe      = string,       -- see PX.python_works
---   candidates = {string,...}, -- override the default candidate path list
---   fallback   = string,       -- returned if nothing matches (default "python3")
--- }
--- @return string  a python path or command name; never nil
function PX.resolve_python(preferred, opts)
  opts = opts or {}
  if PX.python_works(preferred, opts) then return preferred end

  local home = os.getenv("HOME") or ""
  local candidates = opts.candidates or {
    "/opt/homebrew/bin/python3",
    "/usr/local/bin/python3",
    "/usr/bin/python3",
    home .. "/.pyenv/shims/python3",
    "python3",
    "python",
  }
  for _, p in ipairs(candidates) do
    if p ~= "" and PX.python_works(p, opts) then return p end
  end
  return opts.fallback or "python3"
end

return PX
