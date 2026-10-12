--[[
@description Toggle Console to Work Log - append ReaScript console output to work.log
@version 26.1012.1641
@author hsuanice
@changelog
  - Renamed to "Toggle Console to Work Log" (was "Console to Work Log Daemon") as part of the 2026-10-12 naming clean-up.
  - Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.
@about
  Monitors REAPER's "ReaScript console output" window and appends new lines
  to work.log.

  - No changes required in other scripts.
  - One log file per project folder: <project_folder>/work.log.
  - If project is unsaved, uses: <this script>/../Tools/work.log.
  - Each appended line is prefixed with local timestamp: YYYY-MM-DD HH:MM:SS.

  Requirements:
  	- js_ReaScriptAPI extension (for reading console window text)

  Notes:
  	- This captures whatever is visible in the ReaScript console window text.
  	- If the console is manually cleared, this daemon marks a reset in the log.
--]]
local SCRIPT_NAME = "Console to Work Log Daemon"

if not reaper.APIExists("JS_Window_Find")
or not reaper.APIExists("JS_Window_ListAllChild")
or not reaper.APIExists("JS_Window_GetClassName")
or not reaper.APIExists("JS_Window_GetTitle") then
	reaper.ShowMessageBox(
		"This script requires js_ReaScriptAPI.\nInstall it via ReaPack first.",
		SCRIPT_NAME,
		0
	)
	return
end

-- Toggle behavior in Action List/toolbar.
if reaper.set_action_options then reaper.set_action_options(1 | 4) end

local _, SCRIPT_PATH, SECTION_ID, CMD_ID = reaper.get_action_context()

local POLL_SECONDS = 0.20
local next_poll_at = 0
local last_console_text = nil

local function now_str()
	return os.date("%Y-%m-%d %H:%M:%S")
end

local function script_tools_fallback_log_path()
	local script_dir = SCRIPT_PATH:match("^(.*[/\\])") or "./"
	return script_dir .. "../Tools/work.log"
end

local function current_log_path()
	local _, proj_path = reaper.EnumProjects(-1, "")
	if proj_path and proj_path ~= "" then
		local folder = proj_path:match("^(.*)[/\\][^/\\]+$")
		if folder and folder ~= "" then
			return folder .. "/work.log"
		end
	end
	return script_tools_fallback_log_path()
end

local function ensure_parent_dir(path)
	local dir = path:match("^(.*)[/\\][^/\\]+$")
	if not dir or dir == "" then return end
	-- REAPER API instead of os.execute("mkdir -p"): works on Windows and does not
	-- spawn a shell on every append; collapse "dir/../" first
	reaper.RecursiveCreateDirectory((dir:gsub("[^/\\]+[/\\]%.%.[/\\]", "")), 0)
end

local function append_lines_to_log(lines, reason)
	if not lines or #lines == 0 then return end
	local path = current_log_path()
	ensure_parent_dir(path)
	local f = io.open(path, "a")
	if not f then return end

	for _, line in ipairs(lines) do
		local s = tostring(line or "")
		if s ~= "" then
			f:write(string.format("[%s] %s\n", now_str(), s))
		end
	end

	if reason == "reset" then
		f:write(string.format("[%s] ---- console reset detected ----\n", now_str()))
	end

	f:close()
end

local function split_lines(s)
	local t = {}
	if not s or s == "" then return t end
	s = s:gsub("\r\n", "\n")
	for line in (s .. "\n"):gmatch("(.-)\n") do
		t[#t + 1] = line
	end
	return t
end

local function starts_with(s, prefix)
	return s:sub(1, #prefix) == prefix
end

local function find_console_edit_hwnd()
	local console_hwnd = reaper.JS_Window_Find("ReaScript console output", true)
	if not console_hwnd then return nil end

	-- js_ReaScriptAPI builds differ here:
	-- some return "csv_string", others return count, "csv_string".
	local a, b = reaper.JS_Window_ListAllChild(console_hwnd)
	local list = (type(a) == "string" and a)
		or (type(b) == "string" and b)
		or ""
	if not list or list == "" then return nil end

	for addr in list:gmatch("[^,]+") do
		local child = reaper.JS_Window_HandleFromAddress(addr)
		if child then
			local cls = reaper.JS_Window_GetClassName(child)
			if cls == "Edit" then
				return child
			end
		end
	end

	return nil
end

local function read_console_text()
	local edit_hwnd = find_console_edit_hwnd()
	if not edit_hwnd then return nil end
	local txt = reaper.JS_Window_GetTitle(edit_hwnd)
	return txt
end

local function compute_delta_lines(old_text, new_text)
	if new_text == nil then return nil, nil end
	if old_text == nil then
		return split_lines(new_text), "init"
	end

	if new_text == old_text then
		return {}, "same"
	end

	if starts_with(new_text, old_text) then
		local delta = new_text:sub(#old_text + 1)
		return split_lines(delta), "append"
	end

	-- Console was cleared/rewritten: keep full visible text and mark reset.
	return split_lines(new_text), "reset"
end

local running = true

reaper.atexit(function()
	if reaper.set_action_options then reaper.set_action_options(8) end
	reaper.SetToggleCommandState(SECTION_ID, CMD_ID, 0)
	reaper.RefreshToolbar2(SECTION_ID, CMD_ID)
end)

reaper.SetToggleCommandState(SECTION_ID, CMD_ID, 1)
reaper.RefreshToolbar2(SECTION_ID, CMD_ID)

local function loop()
	if not running then return end

	local now = reaper.time_precise()
	if now >= next_poll_at then
		next_poll_at = now + POLL_SECONDS

		local txt = read_console_text()
		local lines, reason = compute_delta_lines(last_console_text, txt)
		if lines and #lines > 0 then
			append_lines_to_log(lines, reason)
		end
		if txt ~= nil then
			last_console_text = txt
		end
	end

	reaper.defer(loop)
end

loop()

