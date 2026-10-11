--[[
@description AudioSweet ReaImGui - AudioSuite Workflow (Pro Tools–Style)
@version 26.1011.2225
@author hsuanice
@links
  https://forum.cockos.com/showthread.php?p=2910884#post2910884
@provides
  [main] .
  [main] hsuanice_AudioSweet Run.lua
  [main] hsuanice_AudioSweet Preview Toggle.lua
  [main] hsuanice_AudioSweet Solo Toggle.lua
  [nomain] hsuanice_FX Alias Build.lua
  [nomain] hsuanice_FX Alias Export JSON to TSV.lua
  [nomain] hsuanice_FX Alias Update TSV to JSON.lua
@changelog
  - Fix: AudioSweet Solo Toggle no longer requires the SWS extension.
  - Requirements: ReaImGui (install via ReaPack, ReaTeam Extensions) and the "hsuanice Library" package; BWF MetaEdit (bwfmetaedit) is needed only for timecode embedding.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  # AudioSweet ReaImGui

  Complete AudioSweet control center with ImGui interface for managing FX chains and presets.

  ## Quick Start
  - Help → User Manual: Full documentation with workflows and tips
  - Help → About: Reference and credits

  ## Reference
  Inspired by AudioSuite-like Script by Tim Chimes
  'AudioSweet' is a name originally given by Tim Chimes.
  This project continues to use the name in reference to his original work.

  Original: Renders selected plugin to selected media item
  Written for REAPER 5.1 with Lua
  v1.1 12/22/2015 - Added PreventUIRefresh
  http://timchimes.com/scripting-with-reaper-audiosuite/

  ## Development
  This script was developed with the assistance of AI tools
  including ChatGPT and Claude AI.
--]]

-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_AudioSweet Core.lua', 'hsuanice_AS Preview Core.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

------------------------------------------------------------
-- Dependencies
------------------------------------------------------------
local r = reaper
local OS_NAME = r.GetOS()
local IS_WINDOWS = OS_NAME:match("Win") ~= nil
local PATH_SEPARATOR = IS_WINDOWS and ';' or ':'
local DIR_SEPARATOR = package.config:sub(1,1) or '/'
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local RES_PATH = r.GetResourcePath()
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_AudioSweet Core.lua'
local PREVIEW_CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_AS Preview Core.lua'

-- Version Info (auto-extracted from @version tag in header, same as RGWH ReaImGui)
local VERSION = "unknown"
do
  local script_path = debug.getinfo(1, "S").source:match("^@(.+)$")
  local f = script_path and io.open(script_path, "r")
  if f then
    for line in f:lines() do
      local ver = line:match("^@version%s+(.+)$")
      if ver then VERSION = ver break end
      if line:match("^@changelog") then break end
    end
    f:close()
  end
end

------------------------------------------------------------
-- ImGui Context
------------------------------------------------------------
local ctx = ImGui.CreateContext('AudioSweet GUI')

------------------------------------------------------------
-- GUI State
------------------------------------------------------------
local gui = {
  open = true,
  mode = 0,              -- 0=focused, 1=chain, 2=auto
  action = 0,            -- 0=apply, 1=copy, 2=apply_after_copy
  copy_scope = 0,
  copy_pos = 0,
  channel_mode = 0,      -- 0=auto, 1=mono, 2=multi
  multi_channel_policy = "source_playback",  -- "source_playback" | "source_track" | "target_track"
  handle_seconds = 5.0,
  use_whole_file = false, -- Use whole file length instead of handles
  tail_seconds = 0.0,     -- FX tail capture (reverb/delay/echo decay), appended after right handle
  glue_grouping = 0,               -- 0=glue all (legacy), 1=follow RGWH GUI, 2=AudioSweet custom
  glue_split_at_crossfades = false, -- custom: crossfading items become separate units
  glue_muted_separate = true,       -- custom: muted items never share a unit with unmuted items
  single_item_render = false,       -- single-item units: RGWH Render (keep takes) instead of Glue
  render_keep_glue_cues = false,    -- Render: carry existing Glue cues into the new take
  debug = false,
  max_history = 10,      -- Maximum number of history items to keep
  show_fx_on_recall = true,    -- Show FX window when executing SAVED CHAIN/HISTORY
  fxname_show_type = true,     -- Show FX type prefix (CLAP:, VST3:, etc.)
  fxname_show_vendor = true,  -- Show vendor name in parentheses
  fxname_strip_symbol = true,  -- Strip spaces and symbols
  use_alias = false,           -- Use FX Alias for file naming

  -- FX Display Settings (4 contexts: button, tooltip, status, fxlist)
  -- Button Display (Preset/History buttons)
  button_show_type = true,
  button_show_vendor = false,
  button_use_alias = false,
  -- Tooltip Display (Hover info)
  tooltip_show_type = true,
  tooltip_show_vendor = true,
  tooltip_use_alias = false,
  -- Status Display (Bottom status bar)
  status_show_type = true,
  status_show_vendor = true,
  status_use_alias = false,
  -- FX Chain List Display (Chain mode FX list)
  fxlist_show_type = true,
  fxlist_show_vendor = true,
  fxlist_use_alias = false,

  -- Chain mode naming
  chain_token_source = 0,      -- 0=track, 1=aliases, 2=fxchain
  chain_alias_joiner = "",     -- Joiner for aliases mode
  max_fx_tokens = 3,           -- FIFO limit for FX tokens
  trackname_strip_symbols = true,  -- Strip symbols from track names
  sanitize_token = false,      -- Sanitize tokens for safe filenames
  is_running = false,
  last_result = "",
  focused_fx_name = "",
  focused_fx_index = nil,  -- Store FX index for focused mode
  focused_track = nil,
  focused_track_name = "",
  focused_track_fx_list = {},
  saved_chains = {},
  history = {},
  new_chain_name = "",
  new_chain_name_default = "",  -- Store initial default value to detect if user modified
  fx_move_logged = {},  -- Cache for logged FX movements (key: "track_guid|fx_name|saved_idx|actual_idx")
  new_fx_preset_name = "",
  show_save_popup = false,
  show_save_fx_popup = false,
  show_rename_popup = false,
  rename_chain_idx = nil,
  rename_chain_name = "",
  rename_is_history = false,  -- Track whether renaming a history item or preset
  show_unified_settings = false,  -- Unified settings window with tabs
  show_help_window = false,  -- Help/Manual window
  show_settings_popup = false,
  show_fxname_popup = false,
  show_preview_settings = false,
  show_naming_popup = false,
  show_preset_display_popup = false,
  show_target_track_popup = false,
  show_tc_embed_popup = false,
  -- Preview settings
  preview_target_track = "AudioSweet",
  preview_target_track_guid = "",  -- Track GUID for unique identification
  preview_solo_scope = 0,     -- 0=track, 1=item
  preview_restore_mode = 0,   -- 0=timesel, 1=guid
  is_previewing = false,      -- Track if preview is currently playing
  -- Feature flags
  enable_saved_chains = true,   -- Now working with OVERRIDE ExtState mechanism
  enable_history = true,        -- Now working with OVERRIDE ExtState mechanism
  show_presets = true,   -- Show/Hide Saved Preset block
  show_history = true,   -- Show/Hide History block
  -- UI settings
  enable_docking = false,       -- Allow window docking
  bwfmetaedit_custom_path = "",
  open_bwf_install_popup = false,
}

local function get_action_label(action)
  if action == 0 then
    return "Apply"
  elseif action == 1 then
    return "Copy"
  end
  return "Copy+Apply"
end

local function get_action_key(action)
  if action == 0 then
    return "apply"
  elseif action == 1 then
    return "copy"
  end
  return "apply_after_copy"
end

------------------------------------------------------------
-- GUI Settings Persistence
------------------------------------------------------------
local SETTINGS_NAMESPACE = "hsuanice_AS_GUI"

-- Glue unit grouping → Core namespace (read by AudioSweet Core >= 0.3.5)
local GLUE_GROUPING_KEYS = { "all", "rgwh", "custom" }
local function sync_glue_grouping_to_core()
  r.SetExtState("hsuanice_AS", "AS_GLUE_GROUPING", GLUE_GROUPING_KEYS[gui.glue_grouping + 1] or "all", false)
  r.SetExtState("hsuanice_AS", "AS_GLUE_SPLIT_AT_CROSSFADES", gui.glue_split_at_crossfades and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "AS_GLUE_MUTED_SEPARATE", gui.glue_muted_separate and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "AS_SINGLE_ITEM_RENDER", gui.single_item_render and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "AS_RENDER_KEEP_GLUE_CUES", gui.render_keep_glue_cues and "1" or "0", false)
end

local function save_gui_settings()
  -- Debug: Log ExtState update when debug mode is enabled
  if gui.debug then
    local timestamp = os.date("%H:%M:%S")
    r.ShowConsoleMsg(string.format("\n[%s] [AS GUI] ExtState Update (save_gui_settings called)\n", timestamp))
    r.ShowConsoleMsg("---------------------------------------------------------\n")
  end

  r.SetExtState(SETTINGS_NAMESPACE, "mode", tostring(gui.mode), true)
  r.SetExtState(SETTINGS_NAMESPACE, "action", tostring(gui.action), true)
  r.SetExtState(SETTINGS_NAMESPACE, "copy_scope", tostring(gui.copy_scope), true)
  r.SetExtState(SETTINGS_NAMESPACE, "copy_pos", tostring(gui.copy_pos), true)
  r.SetExtState(SETTINGS_NAMESPACE, "channel_mode", tostring(gui.channel_mode), true)
  r.SetExtState(SETTINGS_NAMESPACE, "multi_channel_policy", gui.multi_channel_policy, true)

  -- Sync multi_channel_policy to Core namespace (for direct GUI execution without Run script)
  r.SetExtState("hsuanice_AS", "AS_MULTI_CHANNEL_POLICY", gui.multi_channel_policy, false)

  r.SetExtState(SETTINGS_NAMESPACE, "handle_seconds", tostring(gui.handle_seconds), true)
  r.SetExtState(SETTINGS_NAMESPACE, "use_whole_file", gui.use_whole_file and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "tail_seconds", tostring(gui.tail_seconds), true)
  r.SetExtState(SETTINGS_NAMESPACE, "glue_grouping", tostring(gui.glue_grouping), true)
  r.SetExtState(SETTINGS_NAMESPACE, "glue_split_at_crossfades", gui.glue_split_at_crossfades and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "glue_muted_separate", gui.glue_muted_separate and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "single_item_render", gui.single_item_render and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "render_keep_glue_cues", gui.render_keep_glue_cues and "1" or "0", true)
  sync_glue_grouping_to_core()
  r.SetExtState(SETTINGS_NAMESPACE, "debug", gui.debug and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "max_history", tostring(gui.max_history), true)
  r.SetExtState(SETTINGS_NAMESPACE, "show_fx_on_recall", gui.show_fx_on_recall and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_show_type", gui.fxname_show_type and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_show_vendor", gui.fxname_show_vendor and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxname_strip_symbol", gui.fxname_strip_symbol and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "use_alias", gui.use_alias and "1" or "0", true)

  -- FX Display Settings (4 contexts)
  r.SetExtState(SETTINGS_NAMESPACE, "button_show_type", gui.button_show_type and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "button_show_vendor", gui.button_show_vendor and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "button_use_alias", gui.button_use_alias and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "tooltip_show_type", gui.tooltip_show_type and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "tooltip_show_vendor", gui.tooltip_show_vendor and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "tooltip_use_alias", gui.tooltip_use_alias and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "status_show_type", gui.status_show_type and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "status_show_vendor", gui.status_show_vendor and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "status_use_alias", gui.status_use_alias and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxlist_show_type", gui.fxlist_show_type and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxlist_show_vendor", gui.fxlist_show_vendor and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "fxlist_use_alias", gui.fxlist_use_alias and "1" or "0", true)

  r.SetExtState(SETTINGS_NAMESPACE, "chain_token_source", tostring(gui.chain_token_source), true)
  r.SetExtState(SETTINGS_NAMESPACE, "chain_alias_joiner", gui.chain_alias_joiner, true)
  r.SetExtState(SETTINGS_NAMESPACE, "max_fx_tokens", tostring(gui.max_fx_tokens), true)
  r.SetExtState(SETTINGS_NAMESPACE, "trackname_strip_symbols", gui.trackname_strip_symbols and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "sanitize_token", gui.sanitize_token and "1" or "0", true)
  -- Preview settings
  r.SetExtState(SETTINGS_NAMESPACE, "preview_target_track", gui.preview_target_track, true)
  r.SetExtState(SETTINGS_NAMESPACE, "preview_target_track_guid", gui.preview_target_track_guid, true)
  r.SetExtState(SETTINGS_NAMESPACE, "preview_solo_scope", tostring(gui.preview_solo_scope), true)
  r.SetExtState(SETTINGS_NAMESPACE, "preview_restore_mode", tostring(gui.preview_restore_mode), true)
  -- UI settings
  r.SetExtState(SETTINGS_NAMESPACE, "enable_docking", gui.enable_docking and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "show_presets", gui.show_presets and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "show_history", gui.show_history and "1" or "0", true)
  r.SetExtState(SETTINGS_NAMESPACE, "bwfmetaedit_custom_path", gui.bwfmetaedit_custom_path or "", true)

  -- Debug: Log key settings that were updated
  if gui.debug then
    local channel_names = {"Auto", "Mono", "Multi"}
    local solo_scope_names = {"Track Solo", "Item Solo"}
    local restore_mode_names = {"Time Selection", "GUID"}

    r.ShowConsoleMsg("Key Settings Updated:\n")
    r.ShowConsoleMsg(string.format("  * channel_mode: %s (%d)\n", channel_names[gui.channel_mode + 1], gui.channel_mode))
    if gui.channel_mode == 2 then
      r.ShowConsoleMsg(string.format("  * multi_channel_policy: %s\n", gui.multi_channel_policy))
    end
    r.ShowConsoleMsg(string.format("  * handle_seconds: %.1f\n", gui.handle_seconds))
    r.ShowConsoleMsg(string.format("  * use_whole_file: %s\n", gui.use_whole_file and "Yes" or "No"))
    r.ShowConsoleMsg(string.format("  * preview_target_track: %s\n", gui.preview_target_track))
    if gui.preview_target_track_guid ~= "" then
      r.ShowConsoleMsg(string.format("  * preview_target_track_guid: %s\n", gui.preview_target_track_guid))
    end
    r.ShowConsoleMsg(string.format("  * preview_solo_scope: %s (%d)\n", solo_scope_names[gui.preview_solo_scope + 1], gui.preview_solo_scope))
    r.ShowConsoleMsg(string.format("  * preview_restore_mode: %s (%d)\n", restore_mode_names[gui.preview_restore_mode + 1], gui.preview_restore_mode))
    r.ShowConsoleMsg("---------------------------------------------------------\n")
  end
end

local function load_gui_settings()
  local function get_int(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and tonumber(val) or default
  end

  local function get_bool(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    if val == "" then return default end
    return val == "1"
  end

  local function get_float(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and tonumber(val) or default
  end

  local function get_string(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and val or default
  end

  gui.mode = get_int("mode", 0)
  gui.action = get_int("action", 0)
  gui.copy_scope = get_int("copy_scope", 0)
  gui.copy_pos = get_int("copy_pos", 0)
  gui.channel_mode = get_int("channel_mode", 0)
  gui.multi_channel_policy = get_string("multi_channel_policy", "source_playback")
  gui.handle_seconds = get_float("handle_seconds", 5.0)
  gui.use_whole_file = get_bool("use_whole_file", false)
  gui.tail_seconds   = get_float("tail_seconds", 0.0)
  gui.glue_grouping  = math.max(0, math.min(2, get_int("glue_grouping", 0)))
  gui.glue_split_at_crossfades = get_bool("glue_split_at_crossfades", false)
  gui.glue_muted_separate      = get_bool("glue_muted_separate", true)
  gui.single_item_render       = get_bool("single_item_render", false)
  gui.render_keep_glue_cues    = get_bool("render_keep_glue_cues", false)
  gui.debug = get_bool("debug", false)
  gui.max_history = get_int("max_history", 10)
  gui.show_fx_on_recall = get_bool("show_fx_on_recall", true)
  gui.fxname_show_type = get_bool("fxname_show_type", true)
  gui.fxname_show_vendor = get_bool("fxname_show_vendor", false)
  gui.fxname_strip_symbol = get_bool("fxname_strip_symbol", true)
  gui.use_alias = get_bool("use_alias", false)

  -- FX Display Settings (4 contexts) - reset to defaults
  gui.button_show_type = get_bool("button_show_type", true)
  gui.button_show_vendor = get_bool("button_show_vendor", false)
  gui.button_use_alias = get_bool("button_use_alias", false)
  gui.tooltip_show_type = get_bool("tooltip_show_type", true)
  gui.tooltip_show_vendor = get_bool("tooltip_show_vendor", true)
  gui.tooltip_use_alias = get_bool("tooltip_use_alias", false)
  gui.status_show_type = get_bool("status_show_type", true)
  gui.status_show_vendor = get_bool("status_show_vendor", true)
  gui.status_use_alias = get_bool("status_use_alias", false)
  gui.fxlist_show_type = get_bool("fxlist_show_type", true)
  gui.fxlist_show_vendor = get_bool("fxlist_show_vendor", true)
  gui.fxlist_use_alias = get_bool("fxlist_use_alias", false)

  gui.chain_token_source = get_int("chain_token_source", 0)
  gui.max_fx_tokens = get_int("max_fx_tokens", 3)
  gui.trackname_strip_symbols = get_bool("trackname_strip_symbols", true)
  gui.sanitize_token = get_bool("sanitize_token", false)
  -- Preview settings
  local function get_string(key, default)
    local val = r.GetExtState(SETTINGS_NAMESPACE, key)
    return (val ~= "") and val or default
  end
  gui.chain_alias_joiner = get_string("chain_alias_joiner", "")
  gui.preview_target_track = get_string("preview_target_track", "AudioSweet")
  gui.preview_target_track_guid = get_string("preview_target_track_guid", "")
  gui.preview_solo_scope = get_int("preview_solo_scope", 0)
  gui.preview_restore_mode = get_int("preview_restore_mode", 0)
  gui.bwfmetaedit_custom_path = get_string("bwfmetaedit_custom_path", "")
  -- UI settings
  gui.enable_docking = get_bool("enable_docking", false)
  gui.show_presets = get_bool("show_presets", true)
  gui.show_history = get_bool("show_history", true)

  -- Debug output on startup now handled by log_gui_settings() at entry point.
end

------------------------------------------------------------
-- BWF MetaEdit CLI Detection
------------------------------------------------------------
local bwf_cli = {
  checked = false,
  available = false,
  resolved_path = "",
  message = "",
  last_source = "",
  attempts = {},
  warning_dismissed = false,
}

local function trim(s)
  if not s then return "" end
  return s:match("^%s*(.-)%s*$") or ""
end

local function sanitize_bwf_custom_path(path)
  local v = trim(path or "")
  v = v:gsub('^"(.*)"$', '%1')
  v = v:gsub("^'(.*)'$", "%1")
  return v
end

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function join_path(base, fragment)
  if base == "" then return fragment end
  local last = base:sub(-1)
  if last == '/' or last == '\\' then
    return base .. fragment
  end
  local sep = DIR_SEPARATOR == "\\" and "\\" or "/"
  return base .. sep .. fragment
end

------------------------------------------------------------
-- Preset/History Display Helpers
------------------------------------------------------------
local json = (function()
  local j = {}
  local function skip_ws(s, i)
    local _, j = s:find("^[ \n\r\t]*", i)
    return (j or i - 1) + 1
  end
  local function parse_value(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "{" then
      local obj = {}
      i = i + 1
      i = skip_ws(s, i)
      if s:sub(i, i) == "}" then return obj, i + 1 end
      while true do
        local k
        k, i = parse_value(s, i)
        if type(k) ~= "string" then error("JSON key error") end
        i = skip_ws(s, i)
        if s:sub(i, i) ~= ":" then error("JSON :") end
        i = i + 1
        local v
        v, i = parse_value(s, i)
        obj[k] = v
        i = skip_ws(s, i)
        local ch = s:sub(i, i)
        if ch == "}" then return obj, i + 1 end
        if ch ~= "," then error("JSON ,}") end
        i = i + 1
      end
    elseif c == "[" then
      local arr = {}
      i = i + 1
      i = skip_ws(s, i)
      if s:sub(i, i) == "]" then return arr, i + 1 end
      while true do
        local v
        v, i = parse_value(s, i)
        arr[#arr + 1] = v
        i = skip_ws(s, i)
        local ch = s:sub(i, i)
        if ch == "]" then return arr, i + 1 end
        if ch ~= "," then error("JSON ,]") end
        i = i + 1
      end
    elseif c == '"' then
      local j1 = i + 1
      local out = {}
      while true do
        local ch = s:sub(j1, j1)
        if ch == "" then error("JSON string") end
        if ch == '"' then return table.concat(out), j1 + 1 end
        if ch == "\\" then
          local e = s:sub(j1 + 1, j1 + 1)
          if e == "u" then
            local hex = s:sub(j1 + 2, j1 + 5)
            out[#out + 1] = utf8.char(tonumber(hex, 16))
            j1 = j1 + 6
          else
            local m = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ['\\'] = "\\", ['/'] = "/" }
            out[#out + 1] = m[e] or e
            j1 = j1 + 2
          end
        else
          out[#out + 1] = ch
          j1 = j1 + 1
        end
      end
    else
      local lit = s:match("^true", i)
      if lit then return true, i + 4 end
      lit = s:match("^false", i)
      if lit then return false, i + 5 end
      lit = s:match("^null", i)
      if lit then return nil, i + 4 end
      local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", i)
      if num and #num > 0 then return tonumber(num), i + #num end
      error("JSON unexpected")
    end
  end
  function j.decode(s)
    local ok, res = pcall(function()
      local v = select(1, parse_value(s, 1))
      return v
    end)
    return ok and res or nil
  end
  return j
end)()

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local fx_alias_cache = {
  loaded = false,
  data = {},
  path = "",
}

local function parse_fx_label(raw)
  raw = tostring(raw or "")
  local typ, rest = raw:match("^([%w%+%._-]+):%s*(.+)$")
  rest = rest or raw
  local core, vendor = rest, ""
  local core_only, v = rest:match("^(.-)%s*%(([^%(%)]+)%)%s*$")
  if core_only then
    core = core_only
    vendor = v or ""
  end
  return trim(typ), trim(core), trim(vendor)
end

local function normalize_token(s)
  return (tostring(s or ""):gsub("[^%w]+", "")):lower()
end

local function make_fingerprint(raw_label)
  local typ, core, vendor = parse_fx_label(raw_label)
  local t = normalize_token(typ)
  local c = normalize_token(core)
  local v = normalize_token(vendor)
  return table.concat({ t, c, v }, "|")
end

local function get_fx_alias_db()
  if fx_alias_cache.loaded then return fx_alias_cache.data end
  fx_alias_cache.path = RES_PATH .. "/Scripts/hsuanice Scripts/Settings/fx_alias.json"
  local raw = read_file(fx_alias_cache.path)
  local decoded = raw and raw ~= "" and json.decode(raw) or nil
  if type(decoded) == "table" then
    fx_alias_cache.data = decoded
  else
    fx_alias_cache.data = {}
  end
  fx_alias_cache.loaded = true
  return fx_alias_cache.data
end

local function get_fx_alias_record(raw_label, use_alias)
  if not use_alias then return nil end
  local db = get_fx_alias_db()
  local fp = make_fingerprint(raw_label)
  local rec = db and db[fp]
  return rec
end

local function pick_alias_type(parsed_type, seen_types)
  if type(seen_types) == "table" then
    if parsed_type and parsed_type ~= "" then
      for _, t in ipairs(seen_types) do
        if t == parsed_type then
          return parsed_type
        end
      end
    end
    return seen_types[1] or ""
  end
  return parsed_type or ""
end

-- Unified FX label formatting function
-- context: "button", "tooltip", "status", "fxlist"
local function format_fx_label(raw_label, context)
  local typ, core, vendor = parse_fx_label(raw_label)
  if core == "" then return raw_label end

  -- Get settings based on context
  local show_type, show_vendor, use_alias
  if context == "button" then
    show_type = gui.button_show_type
    show_vendor = gui.button_show_vendor
    use_alias = gui.button_use_alias
  elseif context == "tooltip" then
    show_type = gui.tooltip_show_type
    show_vendor = gui.tooltip_show_vendor
    use_alias = gui.tooltip_use_alias
  elseif context == "status" then
    show_type = gui.status_show_type
    show_vendor = gui.status_show_vendor
    use_alias = gui.status_use_alias
  elseif context == "fxlist" then
    show_type = gui.fxlist_show_type
    show_vendor = gui.fxlist_show_vendor
    use_alias = gui.fxlist_use_alias
  else
    -- Fallback to button settings
    show_type = gui.button_show_type
    show_vendor = gui.button_show_vendor
    use_alias = gui.button_use_alias
  end

  local display_type = typ
  local display_vendor = vendor
  local display_core = core

  -- Apply alias if enabled
  local rec = get_fx_alias_record(raw_label, use_alias)
  if rec then
    display_type = pick_alias_type(typ, rec.seen_types)
    display_vendor = rec.normalized_vendor or ""
    display_core = (rec.alias and rec.alias ~= "") and rec.alias or (rec.normalized_core or display_core)
  end

  -- Build display name
  local name = display_core
  if show_vendor and display_vendor ~= "" then
    name = string.format("%s (%s)", display_core, display_vendor)
  end
  if show_type and display_type ~= "" then
    name = string.format("%s: %s", display_type, name)
  end
  return name
end

-- Legacy functions for backward compatibility
local function format_fx_label_for_preset(raw_label)
  return format_fx_label(raw_label, "button")
end

local function format_fx_label_for_status(raw_label)
  return format_fx_label(raw_label, "status")
end

-- Extract core FX name only (no type, no vendor) for rename dialog
-- If button uses alias, return alias; otherwise return core name
local function get_fx_core_name(raw_label)
  -- Check if button display uses alias
  if gui.button_use_alias then
    local rec = get_fx_alias_record(raw_label, true)
    if rec and rec.alias and rec.alias ~= "" then
      return rec.alias  -- Return alias if available
    end
    -- Fallback to normalized_core if alias is empty
    if rec and rec.normalized_core and rec.normalized_core ~= "" then
      return rec.normalized_core
    end
  end

  -- Default: return parsed core name
  local _, core, _ = parse_fx_label(raw_label)
  return core
end

-- Format FX label using custom name but preserving type/vendor from original
-- Used for displaying custom-named presets with type/vendor toggle support
local function format_fx_label_with_custom_name(original_fx_name, custom_name, context)
  -- Parse original FX name to extract type and vendor
  local typ, _, vendor = parse_fx_label(original_fx_name)

  -- Get display settings based on context
  local show_type, show_vendor, use_alias
  if context == "button" then
    show_type = gui.button_show_type
    show_vendor = gui.button_show_vendor
    use_alias = gui.button_use_alias
  elseif context == "tooltip" then
    show_type = gui.tooltip_show_type
    show_vendor = gui.tooltip_show_vendor
    use_alias = gui.tooltip_use_alias
  elseif context == "status" then
    show_type = gui.status_show_type
    show_vendor = gui.status_show_vendor
    use_alias = gui.status_use_alias
  elseif context == "fxlist" then
    show_type = gui.fxlist_show_type
    show_vendor = gui.fxlist_show_vendor
    use_alias = gui.fxlist_use_alias
  else
    -- Fallback to button settings
    show_type = gui.button_show_type
    show_vendor = gui.button_show_vendor
    use_alias = gui.button_use_alias
  end

  -- Build display name with custom core but original type/vendor
  local display_name = custom_name
  if show_vendor and vendor ~= "" then
    display_name = string.format("%s (%s)", custom_name, vendor)
  end
  if show_type and typ ~= "" then
    display_name = string.format("%s: %s", typ, display_name)
  end

  return display_name
end

local function check_bwfmetaedit(force)
  if bwf_cli.checked and not force then return end
  bwf_cli.checked = true
  if force then bwf_cli.warning_dismissed = false end

  local custom = sanitize_bwf_custom_path(gui.bwfmetaedit_custom_path or "")
  gui.bwfmetaedit_custom_path = custom

  local attempted = {}
  local found_path, source_label
  local binary_names = IS_WINDOWS and { "bwfmetaedit.exe", "bwfmetaedit" } or { "bwfmetaedit" }

  local function register_attempt(path)
    if path and path ~= "" then
      attempted[#attempted+1] = path
    end
  end

  local function try_candidate(path, label)
    if found_path or not path or path == "" then return false end
    register_attempt(path)
    if file_exists(path) then
      found_path = path
      source_label = label or path
      return true
    end
    return false
  end

  if custom ~= "" then
    try_candidate(custom, "custom path")
    if IS_WINDOWS and not found_path and not custom:lower():match("%.exe$") then
      try_candidate(custom .. ".exe", "custom path (.exe)")
    end
  end

  local path_env = os.getenv(IS_WINDOWS and "Path" or "PATH") or ""
  if not found_path and path_env ~= "" then
    local pattern = string.format("([^%s]+)", PATH_SEPARATOR)
    for path_dir in path_env:gmatch(pattern) do
      local cleaned_dir = trim(path_dir:gsub('"', ''))
      if cleaned_dir ~= "" then
        for _, name in ipairs(binary_names) do
          try_candidate(join_path(cleaned_dir, name), "PATH: " .. cleaned_dir)
          if found_path then break end
        end
      end
      if found_path then break end
    end
  end

  local fallback_dirs = {}
  if IS_WINDOWS then
    local pf = os.getenv("ProgramFiles")
    local pf86 = os.getenv("ProgramFiles(x86)")
    if pf then fallback_dirs[#fallback_dirs+1] = join_path(pf, "BWF MetaEdit") end
    if pf86 then fallback_dirs[#fallback_dirs+1] = join_path(pf86, "BWF MetaEdit") end
  else
    fallback_dirs = { "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/local/bin" }
  end
  if not found_path then
    for _, dir in ipairs(fallback_dirs) do
      for _, name in ipairs(binary_names) do
        try_candidate(join_path(dir, name), dir)
        if found_path then break end
      end
      if found_path then break end
    end
  end

  bwf_cli.attempts = attempted
  if found_path then
    bwf_cli.available = true
    bwf_cli.resolved_path = found_path
    bwf_cli.last_source = source_label or ""
    bwf_cli.message = string.format("BWF MetaEdit CLI ready (%s)", source_label or found_path)
  else
    bwf_cli.available = false
    bwf_cli.resolved_path = ""
    if custom ~= "" then
      bwf_cli.message = "Custom BWF MetaEdit CLI path not found. Please verify the file exists."
    else
      bwf_cli.message = "No 'bwfmetaedit' binary detected. Timecode embedding is currently disabled."
    end
  end
end

local BWF_INSTALL_POPUP_ID = 'BWF MetaEdit CLI Install Guide'
local BREW_INSTALL_CMD = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
local BREW_BWF_CMD = 'brew install bwfmetaedit'
local BWF_VERIFY_CMD = 'bwfmetaedit --version'

local function draw_bwfmetaedit_warning_banner()
  if bwf_cli.available or bwf_cli.warning_dismissed then return end

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF6666FF)
  ImGui.Text(ctx, "BWF MetaEdit CLI missing – Timecode embedding is disabled.")
  ImGui.PopStyleColor(ctx)

  ImGui.TextWrapped(ctx,
    "AudioSweet relies on the bwfmetaedit CLI to embed BWF TimeReference (timecode).\n" ..
    "You can continue using other features, but TC embedding stays off until the CLI is installed.")
  if bwf_cli.message ~= "" then
    ImGui.TextDisabled(ctx, bwf_cli.message)
  end

  if ImGui.Button(ctx, "Install Guide##as_warn") then
    gui.open_bwf_install_popup = true
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Re-check##as_warn") then
    check_bwfmetaedit(true)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remind Me Later##as_warn") then
    bwf_cli.warning_dismissed = true
  end
  ImGui.Spacing(ctx)
end

local function draw_bwfmetaedit_install_modal()
  if gui.open_bwf_install_popup then
    ImGui.SetNextWindowSize(ctx, 520, 0, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, BWF_INSTALL_POPUP_ID)
    gui.open_bwf_install_popup = false
  end

  if ImGui.BeginPopupModal(ctx, BWF_INSTALL_POPUP_ID, true, ImGui.WindowFlags_AlwaysAutoResize) then
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.TextColored(ctx, 0x00AAFFFF, "Why is this required?")
    ImGui.TextWrapped(ctx,
      "AudioSweet calls the BWF MetaEdit CLI to write BWF TimeReference (timecode) back into rendered files.\n" ..
      "Without the CLI, the embed step is skipped. The steps below describe a Homebrew-based install on macOS:")
    ImGui.Spacing(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 1: Install Homebrew (if missing)")
    ImGui.TextWrapped(ctx, "Open Terminal, run the following command, and follow the prompts to install Homebrew:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##as_brew_install_cmd", BREW_INSTALL_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##as_copy_brew_install") then
      r.ImGui_SetClipboardText(ctx, BREW_INSTALL_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Reference: https://brew.sh")
    ImGui.Separator(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 2: Install BWF MetaEdit CLI")
    ImGui.TextWrapped(ctx, "Once Homebrew is installed, run this command to install bwfmetaedit:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##as_brew_bwf_cmd", BREW_BWF_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##as_copy_bwf") then
      r.ImGui_SetClipboardText(ctx, BREW_BWF_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Binary is typically placed in /opt/homebrew/bin")
    ImGui.Separator(ctx)

    ImGui.TextColored(ctx, 0xFFFFAAFF, "Step 3: Verify the CLI")
    ImGui.TextWrapped(ctx, "Confirm the binary responds by running:")
    ImGui.SetNextItemWidth(ctx, 460)
    ImGui.InputText(ctx, "##as_brew_verify_cmd", BWF_VERIFY_CMD, ImGui.InputTextFlags_ReadOnly)
    if ImGui.Button(ctx, "Copy Command##as_copy_verify") then
      r.ImGui_SetClipboardText(ctx, BWF_VERIFY_CMD)
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "Version output = install success")
    ImGui.Spacing(ctx)

    ImGui.TextWrapped(ctx,
      "After installing, reopen AudioSweet (or press \"Re-check CLI\") to enable embedding again.\n" ..
      "Windows users (or anyone skipping Homebrew) can download installers from MediaArea: https://mediaarea.net/BWFMetaEdit")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Close", 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

local function draw_tc_embed_settings_popup()
  if gui.show_tc_embed_popup then
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'Timecode Embed Settings')
    gui.show_tc_embed_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'Timecode Embed Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    if bwf_cli.available then
      ImGui.TextColored(ctx, 0x55FF55FF, ("CLI detected: %s"):format(bwf_cli.resolved_path))
      if bwf_cli.last_source ~= "" then
        ImGui.TextDisabled(ctx, ("Source: %s"):format(bwf_cli.last_source))
      end
    else
      ImGui.TextColored(ctx, 0xFF6666FF, "bwfmetaedit CLI not detected – Timecode embedding stays disabled.")
      if bwf_cli.message ~= "" then
        ImGui.TextWrapped(ctx, bwf_cli.message)
      end
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Custom CLI Path (optional):")
    ImGui.SetNextItemWidth(ctx, 360)
    local rv_path, new_path = ImGui.InputText(ctx, "##as_bwf_path", gui.bwfmetaedit_custom_path or "")
    if rv_path then
      gui.bwfmetaedit_custom_path = new_path
      save_gui_settings()
    end
    ImGui.TextDisabled(ctx, "Leave blank to search PATH. Provide full path incl. .exe on Windows.")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Re-check CLI##as_settings") then
      check_bwfmetaedit(true)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Install Guide##as_settings") then
      gui.open_bwf_install_popup = true
    end

    ImGui.Spacing(ctx)
    ImGui.TextWrapped(ctx,
      "AudioSweet uses bwfmetaedit after renders to embed BWF TimeReference so downstream apps read the correct TC.\n" ..
      "If you skip installation, rendering still works but the embed step is skipped.")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Close##as_tc_settings", 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
end

------------------------------------------------------------
-- Track FX Chain Helpers
------------------------------------------------------------
local CHAIN_NAMESPACE = "hsuanice_AS_SavedChains"
local add_saved_chain
local find_track_by_guid

local function save_chains_to_extstate()
  local idx = 0
  while true do
    local ok = r.GetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx)
    if ok == 0 then break end
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx, "")
    idx = idx + 1
  end
  for i, chain in ipairs(gui.saved_chains) do
    local data = string.format("%s|%s|%s|%s|%s|%s",
      chain.name,
      chain.track_guid,
      chain.track_name,
      chain.custom_name or "",
      chain.mode or "chain",
      tostring(chain.fx_index or ""))
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. (i - 1), data)
  end
end

local function add_saved_chain(name, track_guid, track_name, custom_name, mode, fx_index)
  gui.saved_chains = gui.saved_chains or {}
  gui.saved_chains[#gui.saved_chains + 1] = {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
    custom_name = custom_name,
    mode = mode or "chain",
    fx_index = fx_index,
  }
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AudioSweet] Save preset: name='%s', mode='%s', fx_index=%s\n",
      name or "nil", mode or "chain", tostring(fx_index or "nil")))
  end
  save_chains_to_extstate()
end

local function get_track_guid(tr)
  if not tr then return nil end
  return r.GetTrackGUID(tr)
end

local function get_track_name_and_number(tr)
  if not tr then return "", 0 end
  local track_num = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0
  local _, track_name = r.GetTrackName(tr, "")
  return track_name or "", track_num
end

local function get_track_fx_chain(tr)
  local fx_list = {}
  if not tr then return fx_list end
  local fx_count = r.TrackFX_GetCount(tr)
  for i = 0, fx_count - 1 do
    local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
    fx_list[#fx_list + 1] = {
      index = i,
      name = fx_name or "(unknown)",
      enabled = r.TrackFX_GetEnabled(tr, i),
      offline = r.TrackFX_GetOffline(tr, i),
    }
  end
  return fx_list
end

local function get_track_number(tr)
  if not tr then return nil end
  local track_num = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
  if not track_num then return nil end
  return math.floor(track_num + 0.5)
end

local function parse_track_selector(selector)
  local raw = trim(selector or "")
  if raw == "" then return nil, nil end

  if raw:sub(1, 1) == "#" then
    local num = raw:match("^#(%d+)")
    if num then
      return tonumber(num), nil
    end

    local num2, name = raw:match("^#(%d+)%s*[-:%s]+%s*(.+)$")
    if num2 and name and trim(name) ~= "" then
      return tonumber(num2), trim(name)
    end
  end

  return nil, raw
end

local function find_track_by_name(track_name)
  local target = trim(track_name or "")
  if target == "" then return nil end
  local lowered = target:lower()
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local _, name = r.GetTrackName(tr, "")
    if name and name:lower() == lowered then
      return tr
    end
  end
  return nil
end

local function find_track_by_selector(selector)
  local track_num, track_name = parse_track_selector(selector)
  if track_num then
    local tr = r.GetTrack(0, track_num - 1)
    if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
      return tr
    end
  end

  if track_name then
    local tr = find_track_by_name(track_name)
    if tr then return tr end
  end

  return nil
end

local function find_auto_load_track()
  local target_name = trim(gui.auto_load_track_name or "")
  if target_name ~= "" then
    local tr = find_track_by_selector(target_name)
    if tr then return tr end
  end
  return nil
end

local function find_track_by_guid(guid)
  if not guid then return nil end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr and r.GetTrackGUID(tr) == guid then
      return tr
    end
  end
  return nil
end

local function preset_chain_already_exists(track_guid, fx_list)
  if not track_guid or not fx_list then return false end
  for _, chain in ipairs(gui.saved_chains) do
    if chain.track_guid == track_guid and chain.mode == "chain" then
      local saved_track = find_track_by_guid(chain.track_guid)
      if saved_track then
        local saved_fx_list = get_track_fx_chain(saved_track)
        if #saved_fx_list == #fx_list then
          local matches = true
          for i = 1, #saved_fx_list do
            if saved_fx_list[i].name ~= fx_list[i].name then
              matches = false
              break
            end
          end
          if matches then
            return true
          end
        end
      end
    end
  end
  return false
end

local function preset_focused_already_exists(track_guid, fx_index)
  if not track_guid or fx_index == nil then return false end
  for _, chain in ipairs(gui.saved_chains) do
    if chain.track_guid == track_guid and chain.mode == "focused" and chain.fx_index == fx_index then
      return true
    end
  end
  return false
end

local function load_preset_from_track(tr)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then
    gui.last_result = "Error: No valid track selected"
    return false
  end

  local track_name, track_num = get_track_name_and_number(tr)
  if track_name == "" then
    gui.last_result = "Error: Selected track has no name"
    return false
  end

  local fx_list = get_track_fx_chain(tr)
  if #fx_list == 0 then
    gui.last_result = "Error: Selected track has no FX to load"
    return false
  end

  local track_guid = get_track_guid(tr)
  local added = 0
  for _, fx in ipairs(fx_list) do
    if not preset_focused_already_exists(track_guid, fx.index) then
      add_saved_chain(fx.name, track_guid, track_name, nil, "focused", fx.index)
      added = added + 1
    end
  end

  if added > 0 then
    gui.last_result = string.format("Success: Loaded %d single-FX presets from track '%s'", added, track_name)
    return true
  end

  gui.last_result = "Info: All single-FX presets already exist for this track"
  return false
end

local function load_preset_from_selected_or_named_track()
  local selected_track = r.GetSelectedTrack(0, 0)
  if selected_track and r.ValidatePtr2(0, selected_track, "MediaTrack*") then
    return load_preset_from_track(selected_track)
  end

  gui.last_result = "Error: Select a track in REAPER first"
  return false
end

local function get_selected_track_list()
  local tracks = {}
  local count = r.CountSelectedTracks(0)
  for i = 0, count - 1 do
    local tr = r.GetSelectedTrack(0, i)
    if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
      tracks[#tracks + 1] = tr
    end
  end
  return tracks
end

local function load_chain_preset_from_track(tr)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then
    gui.last_result = "Error: No valid track selected"
    return false
  end

  local track_name, _ = get_track_name_and_number(tr)
  if track_name == "" then
    gui.last_result = "Error: Selected track has no name"
    return false
  end

  local fx_list = get_track_fx_chain(tr)
  if #fx_list == 0 then
    gui.last_result = "Error: Selected track has no FX to load"
    return false
  end

  local track_guid = get_track_guid(tr)
  if preset_chain_already_exists(track_guid, fx_list) then
    gui.last_result = "Info: This chain preset already exists"
    return false
  end

  add_saved_chain(track_name, track_guid, track_name, nil, "chain", nil)
  gui.last_result = string.format("Success: Chain preset loaded from track '%s'", track_name)
  return true
end

local function load_chain_presets_from_selected_tracks()
  local tracks = get_selected_track_list()
  if #tracks == 0 then
    gui.last_result = "Error: Select one or more tracks in REAPER first"
    return false
  end

  local loaded = 0
  local skipped = 0
  for _, tr in ipairs(tracks) do
    local ok = load_chain_preset_from_track(tr)
    if ok then
      loaded = loaded + 1
    else
      skipped = skipped + 1
    end
  end

  if loaded > 0 then
    gui.last_result = string.format("Success: Loaded chain presets from %d selected track(s)", loaded)
    return true
  end

  if skipped > 0 then
    gui.last_result = "Info: Selected tracks already had chain presets"
  end
  return false
end

------------------------------------------------------------
-- Saved Chain Management
------------------------------------------------------------
local CHAIN_NAMESPACE = "hsuanice_AS_SavedChains"
local HISTORY_NAMESPACE = "hsuanice_AS_History"

local function load_saved_chains()
  gui.saved_chains = {}
  local idx = 0
  while true do
    local ok, data = r.GetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx)
    if ok == 0 or data == "" then break end
    -- Format: name|guid|track_name|custom_name|mode|fx_index
    -- For backward compatibility: if no custom_name, mode, or fx_index, they will be nil/"chain"/nil
    local parts = {}
    for part in (data .. "|"):gmatch("([^|]*)|") do
      table.insert(parts, part)
    end
    local name, guid, track_name, custom_name, mode, fx_index_str = parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
    if name and guid then
      local fx_index = nil
      if fx_index_str and fx_index_str ~= "" then
        fx_index = tonumber(fx_index_str)
      end
      gui.saved_chains[#gui.saved_chains + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
        custom_name = (custom_name and custom_name ~= "") and custom_name or nil,
        mode = (mode and mode ~= "") and mode or "chain",  -- Default to "chain" for backward compatibility
        fx_index = fx_index,  -- Load fx_index
      }
    end
    idx = idx + 1
  end
end

local function save_chains_to_extstate()
  local idx = 0
  while true do
    local ok = r.GetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx)
    if ok == 0 then break end
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. idx, "")
    idx = idx + 1
  end
  for i, chain in ipairs(gui.saved_chains) do
    local data = string.format("%s|%s|%s|%s|%s|%s",
      chain.name,
      chain.track_guid,
      chain.track_name,
      chain.custom_name or "",
      chain.mode or "chain",
      tostring(chain.fx_index or ""))  -- Add fx_index field
    r.SetProjExtState(0, CHAIN_NAMESPACE, "chain_" .. (i - 1), data)
  end
end

local function add_saved_chain(name, track_guid, track_name, custom_name, mode, fx_index)
  gui.saved_chains[#gui.saved_chains + 1] = {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
    custom_name = custom_name,
    mode = mode or "chain",
    fx_index = fx_index,  -- Store FX index for focused mode
  }
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AudioSweet] Save preset: name='%s', mode='%s', fx_index=%s\n",
      name or "nil", mode or "chain", tostring(fx_index or "nil")))
  end
  save_chains_to_extstate()
end

local function delete_saved_chain(idx)
  table.remove(gui.saved_chains, idx)
  save_chains_to_extstate()
end

local function rename_saved_chain(idx, new_custom_name)
  if gui.saved_chains[idx] then
    local chain = gui.saved_chains[idx]
    chain.custom_name = (new_custom_name and new_custom_name ~= "") and new_custom_name or nil
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Rename preset #%d: custom_name='%s', mode='%s'\n",
        idx, tostring(chain.custom_name or "nil"), chain.mode or "chain"))
    end
    save_chains_to_extstate()

    -- Sync rename to history items that match this preset
    -- Match by: track_guid + mode + (fx_index for focused, name for chain)
    for _, hist_item in ipairs(gui.history) do
      if hist_item.track_guid == chain.track_guid and hist_item.mode == chain.mode then
        if chain.mode == "focused" then
          -- For focused mode: match by fx_index
          if hist_item.fx_index == chain.fx_index then
            hist_item.custom_name = chain.custom_name
          end
        else
          -- For chain mode: match by name (original internal name)
          if hist_item.name == chain.name then
            hist_item.custom_name = chain.custom_name
          end
        end
      end
    end

    -- Save updated history to ExtState
    for i = 0, gui.max_history - 1 do
      r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
    end
    for i, item in ipairs(gui.history) do
      local data = string.format("%s|%s|%s|%s|%d|%s", item.name, item.track_guid, item.track_name, item.mode, item.fx_index, item.custom_name or "")
      r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. (i - 1), data)
    end
  end
end

local function rename_history_item(idx, new_custom_name)
  if gui.history[idx] then
    local item = gui.history[idx]
    item.custom_name = (new_custom_name and new_custom_name ~= "") and new_custom_name or nil
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Rename history #%d: custom_name='%s', mode='%s'\n",
        idx, tostring(item.custom_name or "nil"), item.mode or "chain"))
    end

    -- Sync rename to saved presets that match this history item
    -- Match by: track_guid + mode + (fx_index for focused, name for chain)
    for _, chain in ipairs(gui.saved_chains) do
      if chain.track_guid == item.track_guid and chain.mode == item.mode then
        if item.mode == "focused" then
          -- For focused mode: match by fx_index
          if chain.fx_index == item.fx_index then
            chain.custom_name = item.custom_name
          end
        else
          -- For chain mode: match by name (original internal name)
          if chain.name == item.name then
            chain.custom_name = item.custom_name
          end
        end
      end
    end

    -- Save updated history to ExtState
    for i = 0, gui.max_history - 1 do
      r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
    end
    for i, hist in ipairs(gui.history) do
      local data = string.format("%s|%s|%s|%s|%d|%s", hist.name, hist.track_guid, hist.track_name, hist.mode, hist.fx_index, hist.custom_name or "")
      r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. (i - 1), data)
    end

    -- Save updated presets
    save_chains_to_extstate()
  end
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if get_track_guid(tr) == guid then
      return tr
    end
  end
  return nil
end

-- Find FX on track by index (with verification) or name (fallback)
-- Returns: fx_index (number or nil), fx_name (string or nil), status (string)
-- Status: "found_by_index", "found_by_name", "invalid_track", "no_fx", "not_found"
local function find_fx_on_track(track, saved_fx_index, saved_fx_name)
  if not track or not r.ValidatePtr2(0, track, "MediaTrack*") then
    return nil, nil, "invalid_track"
  end

  local fx_count = r.TrackFX_GetCount(track)
  if fx_count == 0 then
    return nil, nil, "no_fx"
  end

  -- Method 1: Try saved index first (with name verification)
  if saved_fx_index and saved_fx_index < fx_count then
    local _, fx_name = r.TrackFX_GetFXName(track, saved_fx_index, "")
    if fx_name == saved_fx_name then
      return saved_fx_index, fx_name, "found_by_index"
    end
  end

  -- Method 2: Search by exact name
  for i = 0, fx_count - 1 do
    local _, fx_name = r.TrackFX_GetFXName(track, i, "")
    if fx_name == saved_fx_name then
      return i, fx_name, "found_by_name"
    end
  end

  return nil, nil, "not_found"
end

-- Get display name and current info for a saved chain
-- Returns: display_name, track_info_line, fx_info, saved_fx_index
local function get_chain_display_info(chain)
  local display_name = chain.name  -- fallback
  local current_track_name = nil
  local fx_info = ""
  local track_number = nil
  local track_info_line = ""  -- First line for tooltip: #track_number: track_name
  local saved_fx_index = nil  -- For focused mode: which FX is the saved one
  local found_fx_name = nil  -- For focused mode: current FX name from track

  -- Try to find the track by GUID
  local tr = find_track_by_guid(chain.track_guid)
  if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
    -- Get current track name and number
    local _, track_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    current_track_name = track_name
    track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")  -- 1-based

    -- Build track info line for tooltip (always show #number: name)
    track_info_line = string.format("#%d: %s", track_number, track_name)

    -- Build FX info based on mode
    if chain.mode == "focused" then
      -- For focused FX: show entire FX chain, mark the saved FX
      local found_fx_idx, found_fx_name, status = find_fx_on_track(tr, chain.fx_index, chain.name)

      -- Build full FX chain list, same as chain mode
      saved_fx_index = found_fx_idx  -- Store for tooltip coloring
      local fx_count = r.TrackFX_GetCount(tr)
      if fx_count > 0 then
        local fx_lines = {}
        for i = 0, fx_count - 1 do
          local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
          table.insert(fx_lines, string.format("%d. %s", i + 1, format_fx_label_for_preset(fx_name)))
        end
        fx_info = table.concat(fx_lines, "\n")
      else
        fx_info = "No FX"
      end
    else
      -- For chain mode: show entire FX chain list
      local fx_count = r.TrackFX_GetCount(tr)
      if fx_count > 0 then
        local fx_lines = {}
        for i = 0, fx_count - 1 do
          local _, fx_name = r.TrackFX_GetFXName(tr, i, "")
          -- fx_name format: "VST3: Pro-Q 4 (FabFilter)" or "JS: ReaEQ"
          -- Keep the full name including plugin type
          -- Format: "1. [Plugin Type]: FX Name"
          table.insert(fx_lines, string.format("%d. %s", i + 1, format_fx_label_for_preset(fx_name)))
        end
        fx_info = table.concat(fx_lines, "\n")
      else
        fx_info = "No FX"
      end
    end
  else
    track_info_line = "Track not found"
    fx_info = ""
  end

  -- Determine display name based on mode
  if chain.mode == "focused" then
    -- Focused FX mode: use custom name OR current FX name from track (real-time)
    if chain.custom_name and chain.custom_name ~= "" then
      -- Use custom name but preserve type/vendor from original FX
      display_name = format_fx_label_with_custom_name(chain.name, chain.custom_name, "button")
    else
      -- Use current FX name from track, fallback to saved name
      display_name = format_fx_label_for_preset(found_fx_name or chain.name)
    end
  else
    -- Chain mode: use custom name OR current track name OR saved track name
    if chain.custom_name and chain.custom_name ~= "" then
      display_name = chain.custom_name
      -- Add track# prefix for custom names
      if track_number then
        display_name = string.format("#%d %s", track_number, display_name)
      end
    elseif current_track_name then
      -- Add track# prefix for dynamic track names
      if track_number then
        display_name = string.format("#%d %s", track_number, current_track_name)
      else
        display_name = current_track_name
      end
    else
      display_name = chain.track_name  -- fallback to saved name
    end
  end

  return display_name, track_info_line, fx_info, saved_fx_index
end

-- Get display name for a history item with current track info
local function get_history_display_name(hist_item)
  local display_name = hist_item.name  -- fallback

  -- Try to find the track by GUID to get current track number
  local tr = find_track_by_guid(hist_item.track_guid)
  if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
    local track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")  -- 1-based
    local _, track_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)

    if hist_item.mode == "focused" then
      -- Focused mode: use custom name OR current FX name from track (real-time)
      if hist_item.custom_name and hist_item.custom_name ~= "" then
        -- Use custom name but preserve type/vendor from original FX
        display_name = format_fx_label_with_custom_name(hist_item.name, hist_item.custom_name, "button")
      else
        -- Find FX on track to get CURRENT name (handles FX reordering)
        local found_fx_idx, found_fx_name, status = find_fx_on_track(tr, hist_item.fx_index, hist_item.name)

        -- Use current FX name from track, fallback to saved name
        display_name = format_fx_label_for_preset(found_fx_name or hist_item.name)
      end
    else
      -- Chain mode: use custom name OR current track name
      if hist_item.custom_name and hist_item.custom_name ~= "" then
        display_name = hist_item.custom_name
        -- Add track# prefix for custom names
        if track_number then
          display_name = string.format("#%d %s", track_number, display_name)
        end
      elseif track_number then
        -- Use current track name with track# prefix
        display_name = string.format("#%d %s", track_number, track_name)
      else
        display_name = track_name
      end
    end
  end

  return display_name
end

-- Show hover tooltip for preset/history item (shared function)
-- item: saved chain or history item
local function show_preset_tooltip(item)
  local tr = find_track_by_guid(item.track_guid)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then
    ImGui.SetTooltip(ctx, "Track not found")
    return
  end

  local track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
  local _, track_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  local track_info_line = string.format("#%d: %s", track_number, track_name)

  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    ImGui.SetTooltip(ctx, track_info_line .. "\nNo FX")
    return
  end

  if item.mode == "focused" then
    -- For focused mode: show entire FX chain, mark the saved FX in GREEN
    -- Find actual FX position (handles FX reordering)
    local actual_fx_idx, actual_fx_name, status = find_fx_on_track(tr, item.fx_index, item.name)

    -- Log FX movement only once (cache key: track_guid|fx_name|saved_idx|actual_idx)
    if gui.debug and actual_fx_idx and status == "found_by_name" then
      local log_key = string.format("%s|%s|%d|%d", item.track_guid, item.name, item.fx_index or -1, actual_fx_idx)
      if not gui.fx_move_logged[log_key] then
        r.ShowConsoleMsg(string.format(
          "[AudioSweet] Tooltip: FX '%s' moved from saved_index=%d to actual_index=%d\n",
          item.name, item.fx_index or -1, actual_fx_idx
        ))
        gui.fx_move_logged[log_key] = true
      end
    end

    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, track_info_line)
    for fx_idx = 0, fx_count - 1 do
      local _, fx_name = r.TrackFX_GetFXName(tr, fx_idx, "")
      local display_name = format_fx_label(fx_name, "tooltip")
      if fx_idx == actual_fx_idx then
        -- This is the actual FX - color it green
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
        ImGui.Text(ctx, string.format("%d. %s", fx_idx + 1, display_name))
        ImGui.PopStyleColor(ctx)
      else
        ImGui.Text(ctx, string.format("%d. %s", fx_idx + 1, display_name))
      end
    end
    ImGui.EndTooltip(ctx)
  else
    -- For chain mode: show entire FX chain
    local fx_lines = {}
    for fx_idx = 0, fx_count - 1 do
      local _, fx_name = r.TrackFX_GetFXName(tr, fx_idx, "")
      table.insert(fx_lines, string.format("%d. %s", fx_idx + 1, format_fx_label(fx_name, "tooltip")))
    end
    local fx_info = table.concat(fx_lines, "\n")
    ImGui.BeginTooltip(ctx)
    ImGui.Text(ctx, track_info_line)
    ImGui.Text(ctx, fx_info)
    ImGui.EndTooltip(ctx)
  end
end

------------------------------------------------------------
-- History Management
------------------------------------------------------------
local function load_history()
  gui.history = {}
  local idx = 0
  while idx < gui.max_history do
    local ok, data = r.GetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. idx)
    if ok == 0 or data == "" then break end
    -- Format: name|guid|track_name|mode|fx_index|custom_name
    local parts = {}
    for part in (data .. "|"):gmatch("([^|]*)|") do
      table.insert(parts, part)
    end
    local name, guid, track_name, mode, fx_idx_str, custom_name = parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
    if name and guid then
      gui.history[#gui.history + 1] = {
        name = name,
        track_guid = guid,
        track_name = track_name or "",
        mode = mode or "chain",
        fx_index = tonumber(fx_idx_str) or 0,
        custom_name = (custom_name and custom_name ~= "") and custom_name or nil,
      }
    end
    idx = idx + 1
  end
end

local function add_to_history(name, track_guid, track_name, mode, fx_index, custom_name)
  fx_index = fx_index or 0

  -- Remove if already exists
  for i = #gui.history, 1, -1 do
    if gui.history[i].name == name and gui.history[i].track_guid == track_guid then
      table.remove(gui.history, i)
    end
  end

  -- Add to front
  table.insert(gui.history, 1, {
    name = name,
    track_guid = track_guid,
    track_name = track_name,
    mode = mode,
    fx_index = fx_index,
    custom_name = custom_name,
  })

  -- Trim to max_history
  while #gui.history > gui.max_history do
    table.remove(gui.history)
  end

  -- Save to ExtState
  for i = 0, gui.max_history - 1 do
    r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
  end
  for i, item in ipairs(gui.history) do
    local data = string.format("%s|%s|%s|%s|%d|%s", item.name, item.track_guid, item.track_name, item.mode, item.fx_index, item.custom_name or "")
    r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. (i - 1), data)
  end
end

------------------------------------------------------------
-- Focused FX Detection
------------------------------------------------------------
local function normalize_focused_fx_index(idx)
  if idx >= 0x2000000 then idx = idx - 0x2000000 end
  if idx >= 0x1000000 then idx = idx - 0x1000000 end
  return idx
end

local function get_focused_fx_info()
  local retval, trackOut, itemOut, fxOut = r.GetFocusedFX()
  if retval == 1 then
    local tr = r.GetTrack(0, math.max(0, (trackOut or 1) - 1))
    if tr then
      local fx_index = normalize_focused_fx_index(fxOut or 0)
      local _, name = r.TrackFX_GetFXName(tr, fx_index, "")
      return true, "Track FX", name or "(unknown)", tr, fx_index
    end
  elseif retval == 2 then
    return true, "Take FX", "(Take FX not supported)", nil, nil
  end
  return false, "None", "No focused FX", nil, nil
end

local function detect_window_mode()
  local retval, trackOut, _, fxOut = r.GetFocusedFX()
  if retval == 1 and trackOut then
    local tr = r.GetTrack(0, math.max(0, (trackOut or 1) - 1))
    if tr then
      local chain_visible = r.TrackFX_GetChainVisible(tr)
      local fx_open = r.TrackFX_GetOpen(tr, fxOut or 0)
      if chain_visible ~= -1 then
        return "chain", tr, fxOut or 0
      end
      if fx_open and chain_visible == -1 then
        return "focused", tr, fxOut or 0
      end
    end
  end
  return "chain", nil, nil
end

local function get_effective_mode()
  if gui.mode == 0 then
    return "focused"
  elseif gui.mode == 1 then
    return "chain"
  end
  local mode_str = detect_window_mode()
  return mode_str or "chain"
end

local function update_focused_fx_display()
  local effective_mode = get_effective_mode()
  local found, fx_type, fx_name, tr, fx_index = get_focused_fx_info()

  -- In Chain mode: if no focused FX, try to use first selected track with FX
  if effective_mode == "chain" and not found then
    local sel_track = r.GetSelectedTrack(0, 0)  -- Get first selected track
    if sel_track and r.TrackFX_GetCount(sel_track) > 0 then
      tr = sel_track
      local track_name, track_num = get_track_name_and_number(tr)
      gui.focused_track = tr
      gui.focused_track_name = string.format("#%d - %s", track_num, track_name)
      gui.focused_track_fx_list = get_track_fx_chain(tr)
      gui.focused_fx_name = "Track: " .. track_name
      return false  -- Not a "valid focused FX" but we have a track with FX chain
    end
  end

  gui.focused_track = tr
  if found then
    if fx_type == "Track FX" then
      gui.focused_fx_name = fx_name
      gui.focused_fx_index = fx_index  -- Store FX index
      if tr then
        local track_name, track_num = get_track_name_and_number(tr)
        gui.focused_track_name = string.format("#%d - %s", track_num, track_name)
        gui.focused_track_fx_list = get_track_fx_chain(tr)
      end
      return true
    else
      gui.focused_fx_name = fx_name .. " (WARNING)"
      gui.focused_fx_index = nil
      gui.focused_track_name = ""
      gui.focused_track_fx_list = {}
      return false
    end
  else
    gui.focused_fx_name = "No focused FX"
    gui.focused_fx_index = nil
    gui.focused_track_name = ""
    gui.focused_track_fx_list = {}
    return false
  end
end

------------------------------------------------------------
-- AudioSweet Execution
------------------------------------------------------------
local function set_extstate_from_gui(mode_override)
  local mode_names = { "focused", "chain", "auto" }
  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local channel_names = { "auto", "mono", "multi" }

  local mode_str = mode_override or mode_names[gui.mode + 1] or "focused"
  if mode_str == "auto" then
    mode_str = "chain"
  end
  r.SetExtState("hsuanice_AS", "AS_MODE", mode_str, false)
  r.SetExtState("hsuanice_AS", "AS_ACTION", get_action_key(gui.action), false)
  r.SetExtState("hsuanice_AS", "AS_COPY_SCOPE", scope_names[gui.copy_scope + 1], false)
  r.SetExtState("hsuanice_AS", "AS_COPY_POS", pos_names[gui.copy_pos + 1], false)
  r.SetExtState("hsuanice_AS", "AS_APPLY_FX_MODE", channel_names[gui.channel_mode + 1], false)
  r.SetExtState("hsuanice_AS", "AS_MULTI_CHANNEL_POLICY", gui.multi_channel_policy, false)
  sync_glue_grouping_to_core()
  r.SetExtState("hsuanice_AS", "DEBUG", gui.debug and "1" or "0", false)

  -- File Naming ExtStates
  r.SetExtState("hsuanice_AS", "USE_ALIAS", gui.use_alias and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_TYPE", gui.fxname_show_type and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_VENDOR", gui.fxname_show_vendor and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_STRIP_SYMBOL", gui.fxname_strip_symbol and "1" or "0", false)
  local chain_token_names = {"track", "aliases", "fxchain"}
  r.SetExtState("hsuanice_AS", "AS_CHAIN_TOKEN_SOURCE", chain_token_names[gui.chain_token_source + 1], false)
  r.SetExtState("hsuanice_AS", "AS_CHAIN_ALIAS_JOINER", gui.chain_alias_joiner, false)
  r.SetExtState("hsuanice_AS", "AS_MAX_FX_TOKENS", tostring(gui.max_fx_tokens), false)
  r.SetExtState("hsuanice_AS", "TRACKNAME_STRIP_SYMBOLS", gui.trackname_strip_symbols and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "SANITIZE_TOKEN_FOR_FILENAME", gui.sanitize_token and "1" or "0", false)

  -- Debug output
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] ExtState: channel_mode=%s (gui.channel_mode=%d)\n",
      channel_names[gui.channel_mode + 1], gui.channel_mode))
  end
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)  -- Always disable summary dialog
  -- Use whole file length if enabled, otherwise use configured handle seconds
  local handle_value = gui.use_whole_file and 999999 or gui.handle_seconds
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(handle_value))
  r.SetProjExtState(0, "RGWH", "TAIL_SECONDS", tostring(gui.tail_seconds or 0.0))

  -- Set RGWH Core debug level (0 = silent, no console output)
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", gui.debug and "2" or "0")

  -- Set FX name formatting options
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_TYPE", gui.fxname_show_type and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_SHOW_VENDOR", gui.fxname_show_vendor and "1" or "0", false)
  r.SetExtState("hsuanice_AS", "FXNAME_STRIP_SYMBOL", gui.fxname_strip_symbol and "1" or "0", false)
end

------------------------------------------------------------
-- Track FX Chain Online/Offline Helpers (for preview/run)
------------------------------------------------------------
-- REAPER represents "FX chain offline" via two mechanisms:
--   1. I_FXEN = 0  (chain-level bypass / offline flag)
--   2. TrackFX_SetOffline per-FX  (unloads individual plugins)
-- Both are saved and restored here so all scenarios are covered.
-- Only offline/chain-bypass state is touched; individual FX enabled (bypass)
-- state is intentionally left alone so AudioSweet Core's behaviour is unaffected.
--
-- Returns a saved-state table, or nil if the chain was already fully online.
local function save_and_enable_track_fx_chain(tr)
  if not tr or not r.ValidatePtr2(0, tr, "MediaTrack*") then return nil end

  local saved = {}
  local any_change = false

  -- (1) Chain-level: I_FXEN
  local fxen = math.floor(r.GetMediaTrackInfo_Value(tr, "I_FXEN") + 0.5)
  saved.fxen = fxen
  if fxen == 0 then
    r.SetMediaTrackInfo_Value(tr, "I_FXEN", 1)
    any_change = true
  end

  -- (2) Per-FX offline bits
  local fx_count = r.TrackFX_GetCount(tr)
  saved.offline = {}
  for i = 0, fx_count - 1 do
    local is_offline = r.TrackFX_GetOffline(tr, i)
    saved.offline[i] = is_offline
    if is_offline then
      r.TrackFX_SetOffline(tr, i, false)
      any_change = true
    end
  end

  return any_change and saved or nil
end

-- Restore the state saved by save_and_enable_track_fx_chain.
local function restore_track_fx_chain_state(tr, saved)
  if not tr or not saved then return end
  if not r.ValidatePtr2(0, tr, "MediaTrack*") then return end

  -- (1) Restore I_FXEN
  if saved.fxen ~= nil then
    r.SetMediaTrackInfo_Value(tr, "I_FXEN", saved.fxen)
  end

  -- (2) Restore per-FX offline bits
  if saved.offline then
    for i, was_offline in pairs(saved.offline) do
      if was_offline then r.TrackFX_SetOffline(tr, i, true) end
    end
  end
end

------------------------------------------------------------
-- Preview & Solo Functions
------------------------------------------------------------
local function toggle_preview()
  -- Check if transport is playing (includes previews started by Tools scripts)
  local play_state = r.GetPlayState()
  local is_playing = (play_state & 1 ~= 0)

  -- If transport is playing (GUI preview or Tools script preview), stop it
  if gui.is_previewing or is_playing then
    r.Main_OnCommand(40044, 0)  -- Transport: Stop
    restore_track_fx_chain_state(gui.preview_fxchain_track, gui.preview_fxchain_saved)
    gui.preview_fxchain_track = nil
    gui.preview_fxchain_saved = nil
    gui.is_previewing = false
    gui.last_result = "Preview stopped"
    return
  end

  -- Otherwise, start preview
  if gui.is_running then return end

  -- Load AS Preview Core
  local ok, ASP = pcall(dofile, PREVIEW_CORE_PATH)
  if not ok or type(ASP) ~= "table" or type(ASP.preview) ~= "function" then
    gui.last_result = "Error: Preview Core not found"
    return
  end

  gui.is_running = true
  gui.last_result = "Running Preview..."

  -- Prepare arguments
  local solo_scope_names = { "track", "item" }
  local restore_mode_names = { "timesel", "guid" }

  -- Determine target track for chain mode
  local target_track_name = gui.preview_target_track  -- Default to settings
  local target_track_obj = nil  -- Store the actual track object to pass directly

  if gui.debug then
    r.ShowConsoleMsg(string.format("\n[AudioSweet] === PREVIEW TARGET SELECTION DEBUG ===\n"))
    r.ShowConsoleMsg(string.format("  Mode: %s\n", effective_mode == "chain" and "Chain" or "Focused"))
    r.ShowConsoleMsg(string.format("  Settings preview_target_track: %s\n", gui.preview_target_track))
    r.ShowConsoleMsg(string.format("  Settings preview_target_track_guid: %s\n", gui.preview_target_track_guid or "(empty)"))
    r.ShowConsoleMsg(string.format("  Has focused_track: %s\n", gui.focused_track and "YES" or "NO"))
  end

  local effective_mode = get_effective_mode()

  if effective_mode == "chain" then
    -- Chain mode: prioritize focused FX chain track if available
    if gui.focused_track and r.ValidatePtr2(0, gui.focused_track, "MediaTrack*") then
      -- Get pure track name from track object (P_NAME doesn't include track number)
      local _, pure_name = r.GetSetMediaTrackInfo_String(gui.focused_track, "P_NAME", "", false)
      local focused_guid = get_track_guid(gui.focused_track)
      target_track_name = pure_name
      target_track_obj = gui.focused_track
      if gui.debug then
        r.ShowConsoleMsg(string.format("  DECISION: Using focused FX chain track\n"))
        r.ShowConsoleMsg(string.format("  → Track: %s (GUID: %s)\n", pure_name, focused_guid))
      end
    else
      -- No focused FX: use settings target track
      if gui.debug then
        r.ShowConsoleMsg(string.format("  DECISION: No focused FX, using settings\n"))
      end
      -- Try to find track by GUID first (more reliable for duplicate names)
      if gui.preview_target_track_guid and gui.preview_target_track_guid ~= "" then
        local target_track = find_track_by_guid(gui.preview_target_track_guid)
        if target_track and r.ValidatePtr2(0, target_track, "MediaTrack*") then
          -- Found by GUID: get current track name and store track object
          local _, current_name = r.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
          target_track_name = current_name
          target_track_obj = target_track  -- IMPORTANT: Pass track object directly to avoid duplicate name issues
          if gui.debug then
            r.ShowConsoleMsg(string.format("  → Found by GUID: %s\n", gui.preview_target_track_guid))
            r.ShowConsoleMsg(string.format("  → Track name: %s\n", current_name))
            r.ShowConsoleMsg(string.format("  → Will pass MediaTrack* directly to Preview Core\n"))
          end
        else
          -- GUID not found: fallback to name
          if gui.debug then
            r.ShowConsoleMsg(string.format("  → GUID not found: %s\n", gui.preview_target_track_guid))
            r.ShowConsoleMsg(string.format("  → Fallback to track name search: %s\n", target_track_name))
          end
        end
      else
        -- No GUID: use track name directly
        if gui.debug then
          r.ShowConsoleMsg(string.format("  → No GUID stored, using track name: %s\n", target_track_name))
        end
      end
    end
  end

  if gui.debug then
    r.ShowConsoleMsg(string.format("  FINAL target_track_name: %s\n", target_track_name))
    r.ShowConsoleMsg(string.format("  FINAL target_track_obj: %s\n", target_track_obj and "MediaTrack*" or "nil (will use name search)"))
    r.ShowConsoleMsg("[AudioSweet] =====================================\n\n")
  end

  local args = {
    debug = gui.debug,
    chain_mode = (effective_mode == "chain"),
    mode = "solo",
    -- Pass track object directly if available (avoids duplicate name issues)
    -- Otherwise fall back to track name search
    target = target_track_obj or nil,
    target_track_name = target_track_obj and nil or target_track_name,
    solo_scope = solo_scope_names[gui.preview_solo_scope + 1],
    restore_mode = restore_mode_names[gui.preview_restore_mode + 1],
  }

  -- Bring FX chain track online so AudioSweet can process correctly.
  -- Resolve the FX track with the same fallback chain used by run_audiosweet:
  --   1. target_track_obj (set for chain mode if focused or found by GUID)
  --   2. gui.focused_track (focused mode, or chain mode with focused FX window)
  --   3. GUID lookup from preview target settings
  --   4. Name lookup from preview target settings
  local fx_track_for_preview = target_track_obj or gui.focused_track
  if not fx_track_for_preview then
    if gui.preview_target_track_guid and gui.preview_target_track_guid ~= "" then
      fx_track_for_preview = find_track_by_guid(gui.preview_target_track_guid)
    end
    if not fx_track_for_preview and target_track_name and target_track_name ~= "" then
      for i = 0, r.CountTracks(0) - 1 do
        local tr = r.GetTrack(0, i)
        local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tn == target_track_name then fx_track_for_preview = tr; break end
      end
    end
  end
  gui.preview_fxchain_track = fx_track_for_preview
  gui.preview_fxchain_saved = save_and_enable_track_fx_chain(fx_track_for_preview)

  -- Run preview
  local preview_ok, preview_err = pcall(ASP.preview, args)

  if preview_ok then
    gui.last_result = "Preview: Success"
    gui.is_previewing = true
  else
    -- Preview failed: restore offline state immediately
    restore_track_fx_chain_state(gui.preview_fxchain_track, gui.preview_fxchain_saved)
    gui.preview_fxchain_track = nil
    gui.preview_fxchain_saved = nil
    gui.last_result = "Preview Error: " .. tostring(preview_err)
    gui.is_previewing = false
  end

  gui.is_running = false
end

local function toggle_solo()
  -- Debug logging
  if gui.debug then
    local scope_name = (gui.preview_solo_scope == 0) and "Track Solo" or "Item Solo"
    r.ShowConsoleMsg(string.format("[AS GUI] SOLO button clicked (scope=%s, mode=%s)\n",
      scope_name, get_effective_mode() == "focused" and "Focused" or "Chain"))
  end

  -- Toggle solo based on solo_scope setting
  if gui.preview_solo_scope == 0 then
    -- Track solo: determine target track based on mode
    local target_track = nil
    local track_name = ""
    local effective_mode = get_effective_mode()
    if effective_mode == "focused" then
      -- Focused mode: use focused track
      target_track = gui.focused_track
      track_name = gui.focused_track_name
    else
      -- Chain mode: use preview target track or focused track
      if gui.focused_track then
        -- If there's a focused FX chain, use that track
        target_track = gui.focused_track
        track_name = gui.focused_track_name
      else
        -- No focused FX: find track by GUID first, then by name
        if gui.preview_target_track_guid and gui.preview_target_track_guid ~= "" then
          target_track = find_track_by_guid(gui.preview_target_track_guid)
          if target_track and r.ValidatePtr2(0, target_track, "MediaTrack*") then
            local _, tn = r.GetSetMediaTrackInfo_String(target_track, "P_NAME", "", false)
            track_name = tn
          end
        end
        -- Fallback to name search if GUID not found
        if not target_track then
          local tc = r.CountTracks(0)
          for i = 0, tc - 1 do
            local tr = r.GetTrack(0, i)
            local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
            if tn == gui.preview_target_track then
              target_track = tr
              track_name = gui.preview_target_track
              break
            end
          end
        end
      end
    end

    if target_track then
      local current_solo = r.GetMediaTrackInfo_Value(target_track, "I_SOLO")
      -- Toggle: 0=unsolo, 1=solo, 2=solo in place
      -- Simple toggle: if any solo state, set to 0; if 0, set to 1
      local new_solo = (current_solo == 0) and 1 or 0
      r.SetMediaTrackInfo_Value(target_track, "I_SOLO", new_solo)

      if gui.debug then
        r.ShowConsoleMsg(string.format("[AS GUI] Toggled track solo: %s -> %s (Track: %s)\n",
          current_solo, new_solo, track_name))
      end
    else
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] No target track found for solo\n")
      end
    end
  else
    -- Item solo (41561): operate on selected items
    r.Main_OnCommand(41561, 0)
  end
end

------------------------------------------------------------
-- AudioSweet Run Function
------------------------------------------------------------
local function run_audiosweet(override_track)
  if gui.is_running then return end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  local effective_mode = get_effective_mode()
  local target_track = override_track or gui.focused_track

  if not override_track then
    local has_valid_fx = update_focused_fx_display()

    if effective_mode == "focused" and not has_valid_fx then
      gui.last_result = "Error: No valid Track FX focused"
      return
    end

    if effective_mode == "chain" then
      -- Chain mode: allow default target track when no focused FX
      if not (gui.focused_track and r.ValidatePtr2(0, gui.focused_track, "MediaTrack*")) then
          local fallback_track = nil
          if gui.preview_target_track_guid and gui.preview_target_track_guid ~= "" then
            fallback_track = find_track_by_guid(gui.preview_target_track_guid)
          end
          if not fallback_track then
            for i = 0, r.CountTracks(0) - 1 do
              local tr = r.GetTrack(0, i)
              local _, tn = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
              if tn == gui.preview_target_track then
                fallback_track = tr
                break
              end
            end
          end
          if fallback_track then
            target_track = fallback_track
          end
        else
          target_track = gui.focused_track
        end
      end
  else
    -- Explicit override implies chain execution on target track
    effective_mode = "chain"
  end

  if not target_track then
    gui.last_result = "Error: Target track not found"
    return
  end

  -- Bring FX chain track online so AudioSweet can process correctly
  local saved_fxchain = save_and_enable_track_fx_chain(target_track)

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  -- Tell AudioSweet Core to NOT create its own undo block (we're managing it here for single undo)
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "1", false)

  -- Only use Core for focused FX mode
  -- (Core needs GetFocusedFX to work properly)
  if effective_mode == "focused" and not override_track then
    set_extstate_from_gui("focused")

    local ok, err = pcall(dofile, CORE_PATH)
    r.UpdateArrange()

    if ok then
      gui.last_result = string.format("Success! (%d items)", item_count)

      -- Add to history
      if gui.focused_track then
        local track_guid = get_track_guid(gui.focused_track)
        local name = gui.focused_fx_name
        -- Get FX index from GetFocusedFX
        local retval, trackidx, itemidx, fxidx = r.GetFocusedFX()
        local fx_index = (retval == 1) and normalize_focused_fx_index(fxidx or 0) or 0
        add_to_history(name, track_guid, gui.focused_track_name, "focused", fx_index, nil)  -- No custom name from direct execution
      end
    else
      gui.last_result = "Error: " .. tostring(err)
    end
  else
    -- For chain mode, focus first FX and use AudioSweet Core
    local fx_count = r.TrackFX_GetCount(target_track)
    if fx_count == 0 then
      gui.last_result = "Error: No FX on target track"
      r.PreventUIRefresh(-1)
      r.Undo_EndBlock("AudioSweet GUI (error)", -1)
      gui.is_running = false
      return
    end

    -- Set track as last touched (without changing selection)
    -- Note: OVERRIDE ExtState tells Core which track to use
    -- We don't call SetOnlyTrackSelected() to preserve item selection
    r.SetMixerScroll(target_track)

    -- Set ExtState for AudioSweet (chain mode)
    set_extstate_from_gui("chain")
    r.SetExtState("hsuanice_AS", "AS_MODE", "chain", false)

    -- Set OVERRIDE ExtState to specify track and FX for Core
    -- (bypasses GetFocusedFX check which fails for CLAP plugins)
    local track_idx = r.CSurf_TrackToID(target_track, false) - 1  -- Convert to 0-based index
    r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(track_idx), false)
    r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", "0", false)  -- Chain mode uses first FX

    -- Run AudioSweet Core
    local ok, err = pcall(dofile, CORE_PATH)
    r.UpdateArrange()

    if ok then
      gui.last_result = string.format("Success! (%d items)", item_count)

      -- Add to history
      if target_track then
        local track_guid = get_track_guid(target_track)
        local track_name, track_num = get_track_name_and_number(target_track)
        local name = string.format("#%d - %s", track_num, track_name)
        add_to_history(name, track_guid, name, "chain", 0, nil)  -- chain mode uses index 0, no custom name from direct execution
      end
    else
      gui.last_result = "Error: " .. tostring(err)
    end
  end

  r.PreventUIRefresh(-1)
  local mode_name = (effective_mode == "focused") and "Focused" or "Chain"
  local action_name = get_action_label(gui.action)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s %s", mode_name, action_name), -1)

  -- Clear external undo control flag after execution
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "", false)

  gui.is_running = false
  restore_track_fx_chain_state(target_track, saved_fxchain)
end

local function run_focused_fx_copy_mode(tr, fx_name, fx_idx, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Focused FX copy: '%s' (saved_fx_idx=%d, items=%d)\n", fx_name, fx_idx, item_count))
  end

  -- Find FX on track (handles FX reordering)
  local actual_fx_idx, actual_fx_name, status = find_fx_on_track(tr, fx_idx, fx_name)

  if not actual_fx_idx then
    gui.last_result = string.format("Error: FX '%s' not found on track", fx_name)
    gui.is_running = false
    return
  end

  if gui.debug and status == "found_by_name" then
    r.ShowConsoleMsg(string.format(
      "[AS GUI] Focused FX copy: FX moved from index %d to %d\n",
      fx_idx, actual_fx_idx
    ))
  end

  -- Use actual index and name for all subsequent operations
  fx_idx = actual_fx_idx
  fx_name = actual_fx_name

  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local scope = scope_names[gui.copy_scope + 1]
  local pos = pos_names[gui.copy_pos + 1]

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Copy settings: scope=%s, position=%s\n", scope, pos))
  end

  local ops = 0
  for i = 0, item_count - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then
      if scope == "all_takes" then
        local take_count = r.CountTakes(it)
        for t = 0, take_count - 1 do
          local tk = r.GetTake(it, t)
          if tk then
            local dest_idx = (pos == "head") and 0 or r.TakeFX_GetCount(tk)
            r.TrackFX_CopyToTake(tr, fx_idx, tk, dest_idx, false)
            ops = ops + 1
          end
        end
      else
        local tk = r.GetActiveTake(it)
        if tk then
          local dest_idx = (pos == "head") and 0 or r.TakeFX_GetCount(tk)
          r.TrackFX_CopyToTake(tr, fx_idx, tk, dest_idx, false)
          ops = ops + 1
        end
      end
    end
  end

  r.UpdateArrange()

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Focused FX copy completed: %d operations\n", ops))
  end

  gui.last_result = string.format("Success! [%s] Copy (%d ops)", format_fx_label_for_status(fx_name), ops)
  gui.is_running = false
end

local function run_saved_chain_copy_mode(tr, chain_name, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Chain copy: '%s' (items=%d)\n", chain_name, item_count))
  end

  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = "Error: No FX on track"
    gui.is_running = false
    return
  end

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Track has %d FX to copy\n", fx_count))
  end

  local scope_names = { "active", "all_takes" }
  local pos_names = { "tail", "head" }
  local scope = scope_names[gui.copy_scope + 1]
  local pos = pos_names[gui.copy_pos + 1]

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Copy settings: scope=%s, position=%s\n", scope, pos))
  end

  local ops = 0
  for i = 0, item_count - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then
      if scope == "all_takes" then
        local take_count = r.CountTakes(it)
        for t = 0, take_count - 1 do
          local tk = r.GetTake(it, t)
          if tk then
            for fx = 0, fx_count - 1 do
              local dest_idx = (pos == "head") and 0 or r.TakeFX_GetCount(tk)
              r.TrackFX_CopyToTake(tr, fx, tk, dest_idx, false)
              ops = ops + 1
            end
          end
        end
      else
        local tk = r.GetActiveTake(it)
        if tk then
          if pos == "head" then
            for fx = fx_count - 1, 0, -1 do
              r.TrackFX_CopyToTake(tr, fx, tk, 0, false)
              ops = ops + 1
            end
          else
            for fx = 0, fx_count - 1 do
              local dest_idx = r.TakeFX_GetCount(tk)
              r.TrackFX_CopyToTake(tr, fx, tk, dest_idx, false)
              ops = ops + 1
            end
          end
        end
      end
    end
  end

  r.UpdateArrange()

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Chain copy completed: %d operations\n", ops))
  end

  gui.last_result = string.format("Success! [%s] Copy (%d ops)", chain_name, ops)
  gui.is_running = false
end

local function run_saved_chain_apply_mode(tr, chain_name, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Saved chain apply: '%s' (items=%d)\n", chain_name, item_count))
  end

  -- Check if track has FX
  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = "Error: No FX on track"
    gui.is_running = false
    return
  end

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] Track has %d FX\n", fx_count))
  end

  -- Set track as last touched (without changing selection)
  -- Note: We don't call SetOnlyTrackSelected() to preserve item selection
  -- Core will snapshot the current selection and restore it at the end
  r.SetMixerScroll(tr)

  -- Open FX chain window if setting enabled
  if gui.show_fx_on_recall then
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Opening FX chain window for target track\n")
    end
    -- Use TrackFX_Show to open the specific track's FX chain
    -- Flag 1 = show FX chain window
    r.TrackFX_Show(tr, 0, 1)
  else
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Skipping FX chain window (show_fx_on_recall = false)\n")
    end
  end

  if gui.debug then
    r.ShowConsoleMsg("[AS GUI] Track set as last touched\n")
  end

  -- Set ExtState for AudioSweet (chain mode)
  r.SetExtState("hsuanice_AS", "AS_MODE", "chain", false)
  r.SetExtState("hsuanice_AS", "AS_ACTION", get_action_key(gui.action), false)
  sync_glue_grouping_to_core()
  r.SetExtState("hsuanice_AS", "DEBUG", gui.debug and "1" or "0", false)

  -- Set OVERRIDE ExtState to specify track and FX for Core
  -- (bypasses GetFocusedFX check which fails for CLAP plugins)
  local track_idx = r.CSurf_TrackToID(tr, false) - 1  -- Convert to 0-based index
  r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(track_idx), false)
  r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", "0", false)  -- Chain mode uses first FX

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] OVERRIDE set: track_idx=%d fx_idx=0\n", track_idx))
  end
  r.SetExtState("hsuanice_AS", "AS_SHOW_SUMMARY", "0", false)
  -- Use whole file length if enabled, otherwise use configured handle seconds
  local handle_value = gui.use_whole_file and 999999 or gui.handle_seconds
  r.SetProjExtState(0, "RGWH", "HANDLE_SECONDS", tostring(handle_value))
  r.SetProjExtState(0, "RGWH", "TAIL_SECONDS", tostring(gui.tail_seconds or 0.0))
  r.SetProjExtState(0, "RGWH", "DEBUG_LEVEL", gui.debug and "2" or "0")

  if gui.debug then
    local handle_display = gui.use_whole_file and "whole file" or string.format("%.1fs", gui.handle_seconds)
    r.ShowConsoleMsg(string.format("[AS GUI] Executing AudioSweet Core (mode=chain, action=%s, handle=%s)\n",
      get_action_key(gui.action), handle_display))
  end

  -- Run AudioSweet Core (it will use the focused track's FX chain)
  -- Note: Core handles selection save/restore internally
  local ok, err = pcall(dofile, CORE_PATH)
  r.UpdateArrange()

  if ok then
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] Execution completed successfully\n"))
    end
    gui.last_result = string.format("Success! [%s] %s (%d items)", chain_name, get_action_label(gui.action), item_count)
  else
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] ERROR: %s\n", tostring(err)))
    end
    gui.last_result = "Error: " .. tostring(err)
  end

  gui.is_running = false
end

-- Capture current selection state (items, time, razor, tracks).
-- Used to preserve the user's selection before opening FX windows, because
-- SetOnlyTrackSelected() combined with REAPER's "item/time link to track"
-- preference would otherwise clobber it.
local function capture_selection_state()
  local state = { items = {}, tracks = {}, razors = {} }

  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    state.items[#state.items + 1] = r.GetSelectedMediaItem(0, i)
  end

  local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  state.ts_start, state.ts_end = ts_start, ts_end

  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.IsTrackSelected(tr) then
      state.tracks[#state.tracks + 1] = tr
    end
    local _, razor = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if razor and razor ~= "" then
      state.razors[#state.razors + 1] = { track = tr, data = razor }
    end
  end

  return state
end

local function restore_selection_state(state)
  if not state then return end

  -- Restore track selection first so that REAPER's link behavior settles
  -- before we override items/time/razor below.
  for i = 0, r.CountTracks(0) - 1 do
    r.SetTrackSelected(r.GetTrack(0, i), false)
  end
  for _, tr in ipairs(state.tracks) do
    if r.ValidatePtr2(0, tr, "MediaTrack*") then
      r.SetTrackSelected(tr, true)
    end
  end

  r.SelectAllMediaItems(0, false)
  for _, it in ipairs(state.items) do
    if r.ValidatePtr2(0, it, "MediaItem*") then
      r.SetMediaItemSelected(it, true)
    end
  end

  r.GetSet_LoopTimeRange(true, false, state.ts_start or 0, state.ts_end or 0, false)

  -- Clear razor on every track, then re-apply saved areas
  for i = 0, r.CountTracks(0) - 1 do
    r.GetSetMediaTrackInfo_String(r.GetTrack(0, i), "P_RAZOREDITS", "", true)
  end
  for _, rz in ipairs(state.razors) do
    if r.ValidatePtr2(0, rz.track, "MediaTrack*") then
      r.GetSetMediaTrackInfo_String(rz.track, "P_RAZOREDITS", rz.data, true)
    end
  end

  r.UpdateArrange()
end

local function open_saved_chain_fx(chain_idx)
  local chain = gui.saved_chains[chain_idx]
  if not chain then return end

  local tr = find_track_by_guid(chain.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", chain.track_name)
    return
  end

  -- Preserve user's pre-open selection (item/time/razor link-to-track resets it).
  local saved_sel = capture_selection_state()

  -- Select track and set as last touched
  r.SetOnlyTrackSelected(tr)
  r.SetMixerScroll(tr)

  local fx_count = r.TrackFX_GetCount(tr)
  if fx_count == 0 then
    gui.last_result = string.format("Error: No FX on track '%s'", chain.track_name)
    restore_selection_state(saved_sel)
    return
  end

  -- Determine window type based on how it was saved
  if chain.mode == "focused" then
    -- Focused FX preset: toggle floating window for the specific FX
    local fx_idx, found_fx_name, status = find_fx_on_track(tr, chain.fx_index, chain.name)

    if not fx_idx then
      gui.last_result = string.format("Error: FX '%s' not found on track", chain.name)
      restore_selection_state(saved_sel)
      return
    end

    if gui.debug then
      r.ShowConsoleMsg(string.format(
        "[AudioSweet] Open preset: saved_name='%s', saved_index=%s, actual_index=%d, status=%s\n",
        chain.name, tostring(chain.fx_index or "nil"), fx_idx, status
      ))
    end

    local is_open = r.TrackFX_GetOpen(tr, fx_idx)
    if is_open then
      r.TrackFX_Show(tr, fx_idx, 2)  -- Hide floating window
    else
      r.TrackFX_Show(tr, fx_idx, 3)  -- Show floating window
    end
    gui.last_result = string.format("Toggled FX #%d: %s", fx_idx + 1, format_fx_label_for_status(found_fx_name))
  else
    -- Chain preset: toggle FX chain window
    local chain_visible = r.TrackFX_GetChainVisible(tr)

    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Open chain: name='%s', mode='%s', chain_visible=%d\n",
        chain.name or "nil", chain.mode or "chain", chain_visible))
    end

    if chain_visible == -1 then
      -- Chain window is closed, open it
      r.TrackFX_Show(tr, 0, 1)  -- Show chain window
    else
      -- Chain window is open, close it
      r.TrackFX_Show(tr, 0, 0)  -- Hide chain window
    end
    gui.last_result = string.format("Toggled FX chain: %s", chain.name)
  end

  restore_selection_state(saved_sel)
end

local function open_history_fx(hist_idx)
  local hist_item = gui.history[hist_idx]
  if not hist_item then return end

  local tr = find_track_by_guid(hist_item.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", hist_item.track_name)
    return
  end

  -- Preserve user's pre-open selection (item/time/razor link-to-track resets it).
  local saved_sel = capture_selection_state()

  -- Select track and set as last touched
  r.SetOnlyTrackSelected(tr)
  r.SetMixerScroll(tr)

  -- Toggle FX window based on history mode
  if hist_item.mode == "focused" then
    -- For focused mode, toggle the specific FX floating window
    local fx_idx = hist_item.fx_index or 0
    local fx_count = r.TrackFX_GetCount(tr)

    if fx_idx >= fx_count then
      gui.last_result = string.format("Error: FX #%d not found (track has %d FX)", fx_idx + 1, fx_count)
      restore_selection_state(saved_sel)
      return
    end

    -- Toggle specific FX floating window
    -- Check if FX is open using TrackFX_GetOpen
    local is_open = r.TrackFX_GetOpen(tr, fx_idx)
    if is_open then
      r.TrackFX_Show(tr, fx_idx, 2)  -- Hide floating window
    else
      r.TrackFX_Show(tr, fx_idx, 3)  -- Show floating window
    end
    gui.last_result = string.format("Toggled FX: %s (FX #%d)", format_fx_label_for_status(hist_item.name), fx_idx + 1)
  else
    -- For chain mode, toggle FX chain window (chain mode uses entire FX chain)
    local chain_visible = r.TrackFX_GetChainVisible(tr)

    if gui.debug then
      r.ShowConsoleMsg(string.format("[AudioSweet] Open history chain: name='%s', mode='%s', chain_visible=%d\n",
        hist_item.name or "nil", hist_item.mode or "chain", chain_visible))
    end

    if chain_visible == -1 then
      -- Chain window is closed, open it
      r.TrackFX_Show(tr, 0, 1)  -- Show chain window
    else
      -- Chain window is open, close it
      r.TrackFX_Show(tr, 0, 0)  -- Hide chain window
    end
    gui.last_result = string.format("Toggled FX chain: %s", hist_item.name)
  end

  restore_selection_state(saved_sel)
end

local function run_history_focused_apply(tr, fx_name, fx_idx, item_count)
  if gui.debug then
    r.ShowConsoleMsg(string.format("[AS GUI] History focused apply: '%s' (saved_fx_idx=%d, items=%d)\n", fx_name, fx_idx, item_count))
  end

  -- Find FX on track (handles FX reordering)
  local actual_fx_idx, actual_fx_name, status = find_fx_on_track(tr, fx_idx, fx_name)

  if not actual_fx_idx then
    gui.last_result = string.format("Error: FX '%s' not found on track", fx_name)
    gui.is_running = false
    return
  end

  if gui.debug and status == "found_by_name" then
    r.ShowConsoleMsg(string.format(
      "[AS GUI] History focused apply: FX moved from index %d to %d\n",
      fx_idx, actual_fx_idx
    ))
  end

  -- Use actual index and name for all subsequent operations
  fx_idx = actual_fx_idx
  fx_name = actual_fx_name

  -- Set track as last touched (without changing selection)
  -- Note: We don't call SetOnlyTrackSelected() to preserve item selection
  -- Core will snapshot the current selection and restore it at the end
  r.SetMixerScroll(tr)

  -- Open specific FX as floating window if setting enabled
  -- Note: Focus detection is not required - Core will work regardless
  if gui.show_fx_on_recall then
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] Opening FX #%d floating window\n", fx_idx + 1))
    end
    r.TrackFX_Show(tr, fx_idx, 3)  -- Show floating window (flag 3)

    -- Small delay to ensure FX window is fully opened before Core checks it
    -- This prevents "Please focus a Track FX" warning
    r.defer(function() end)  -- Process one defer cycle
  else
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Skipping FX window (show_fx_on_recall = false)\n")
    end
  end

  -- Set ExtState for AudioSweet (focused mode)
  set_extstate_from_gui()
  r.SetExtState("hsuanice_AS", "AS_MODE", "focused", false)

  -- Set OVERRIDE ExtState to specify exact FX (bypasses GetFocusedFX check)
  -- This ensures Core processes the correct FX even if focus detection fails
  local track_idx = r.CSurf_TrackToID(tr, false) - 1  -- Convert to 0-based index
  r.SetExtState("hsuanice_AS", "OVERRIDE_TRACK_IDX", tostring(track_idx), false)
  r.SetExtState("hsuanice_AS", "OVERRIDE_FX_IDX", tostring(fx_idx), false)

  if gui.debug then
    local handle_display = gui.use_whole_file and "whole file" or string.format("%.1fs", gui.handle_seconds)
    r.ShowConsoleMsg(string.format("[AS GUI] Executing AudioSweet Core (mode=focused, action=%s, handle=%s)\n",
      get_action_key(gui.action), handle_display))
  end

  -- Run AudioSweet Core
  -- Note: Core handles selection save/restore internally
  local ok, err = pcall(dofile, CORE_PATH)
  r.UpdateArrange()

  if ok then
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Execution completed successfully\n")
    end
    gui.last_result = string.format("Success! [%s] %s (%d items)", format_fx_label_for_status(fx_name), get_action_label(gui.action), item_count)
  else
    if gui.debug then
      r.ShowConsoleMsg(string.format("[AS GUI] ERROR: %s\n", tostring(err)))
    end
    gui.last_result = "Error: " .. tostring(err)
  end

  gui.is_running = false
end

local function run_saved_chain(chain_idx)
  local chain = gui.saved_chains[chain_idx]
  if not chain then return end

  if gui.debug then
    r.ShowConsoleMsg(string.format("[AudioSweet] Run preset #%d: name='%s', mode='%s', fx_index=%s\n",
      chain_idx, chain.name, chain.mode or "chain", tostring(chain.fx_index or "nil")))
  end

  local tr = find_track_by_guid(chain.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", chain.track_name)
    return
  end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  if gui.is_running then return end

  -- Bring FX chain track online so AudioSweet can process correctly
  local saved_fxchain = save_and_enable_track_fx_chain(tr)

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  -- Tell AudioSweet Core to NOT create its own undo block (we're managing it here for single undo)
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "1", false)

  -- Execute based on saved mode (chain or focused)
  if chain.mode == "focused" then
    -- For focused mode, use stored FX index
    if gui.action == 1 then
      run_focused_fx_copy_mode(tr, chain.name, chain.fx_index or 0, item_count)
    else
      run_history_focused_apply(tr, chain.name, chain.fx_index or 0, item_count)
    end
  else
    -- Chain mode - use chain execution
    if gui.action == 1 then
      run_saved_chain_copy_mode(tr, chain.name, item_count)
    else
      run_saved_chain_apply_mode(tr, chain.name, item_count)
    end
  end

  -- Add to history with correct mode, fx_index, and custom_name
  add_to_history(chain.name, chain.track_guid, chain.track_name, chain.mode or "chain", chain.fx_index or 0, chain.custom_name)

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", get_action_label(gui.action), chain.name), -1)

  -- Clear external undo control flag after execution
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "", false)
  restore_track_fx_chain_state(tr, saved_fxchain)
end

local function run_history_item(hist_idx)
  local hist_item = gui.history[hist_idx]
  if not hist_item then return end

  local tr = find_track_by_guid(hist_item.track_guid)
  if not tr then
    gui.last_result = string.format("Error: Track '%s' not found", hist_item.track_name)
    return
  end

  local item_count = r.CountSelectedMediaItems(0)
  if item_count == 0 then
    gui.last_result = "Error: No items selected"
    return
  end

  if gui.is_running then return end

  -- Bring FX chain track online so AudioSweet can process correctly
  local saved_fxchain = save_and_enable_track_fx_chain(tr)

  gui.is_running = true
  gui.last_result = "Running..."

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  -- Tell AudioSweet Core to NOT create its own undo block (we're managing it here for single undo)
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "1", false)

  -- Check if this was originally a focused FX or chain
  if hist_item.mode == "focused" then
    -- For focused mode, use stored FX index
    if gui.action == 1 then
      run_focused_fx_copy_mode(tr, hist_item.name, hist_item.fx_index or 0, item_count)
    else
      run_history_focused_apply(tr, hist_item.name, hist_item.fx_index or 0, item_count)
    end
  else
    -- Chain mode - use saved chain execution
    if gui.action == 1 then
      run_saved_chain_copy_mode(tr, hist_item.name, item_count)
    else
      run_saved_chain_apply_mode(tr, hist_item.name, item_count)
    end
  end

  -- Note: History doesn't re-add to history to avoid duplication

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format("AudioSweet GUI: %s [%s]", get_action_label(gui.action), hist_item.name), -1)

  -- Clear external undo control flag after execution
  r.SetExtState("hsuanice_AS", "EXTERNAL_UNDO_CONTROL", "", false)
  restore_track_fx_chain_state(tr, saved_fxchain)
end

------------------------------------------------------------
-- GUI Rendering
------------------------------------------------------------
local function draw_gui()
  -- Auto-reset is_previewing when transport stops
  if gui.is_previewing then
    local play_state = r.GetPlayState()
    if play_state == 0 then  -- 0 = stopped
      restore_track_fx_chain_state(gui.preview_fxchain_track, gui.preview_fxchain_saved)
      gui.preview_fxchain_track = nil
      gui.preview_fxchain_saved = nil
      gui.is_previewing = false
      if gui.last_result == "Preview: Success" or gui.last_result == "Preview stopped" then
        gui.last_result = "Preview stopped (auto-detected)"
      end
    end
  end

  -- Keyboard shortcuts (only work when NOT typing in text inputs)
  local is_typing = ImGui.IsAnyItemActive(ctx)

  if not is_typing then
    -- Space = Stop transport (simple, no modifiers needed)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] Keyboard shortcut: Space (Stop transport, command=40044)\n")
      end
      r.Main_OnCommand(40044, 0)  -- Transport: Stop
    end

    -- S = Solo toggle (depends on solo_scope setting)
    if ImGui.IsKeyPressed(ctx, ImGui.Key_S, false) then
      if gui.debug then
        local scope_name = (gui.preview_solo_scope == 0) and "Track Solo" or "Item Solo"
        r.ShowConsoleMsg(string.format("[AS GUI] Keyboard shortcut: S pressed (scope=%s)\n", scope_name))
      end
      toggle_solo()
    end
  end

  local window_flags = ImGui.WindowFlags_MenuBar |
                       ImGui.WindowFlags_AlwaysAutoResize |
                       ImGui.WindowFlags_NoResize |
                       ImGui.WindowFlags_NoCollapse

  -- Add NoDocking flag if docking is disabled
  if not gui.enable_docking then
    window_flags = window_flags | ImGui.WindowFlags_NoDocking
  end

  -- Set minimum window size to make buttons more readable (min width: 700px)
  ImGui.SetNextWindowSizeConstraints(ctx, 450, 0, 99999, 99999)

  local visible, open = ImGui.Begin(ctx, 'AudioSweet Control Panel', true, window_flags)
  if not visible then
    ImGui.End(ctx)
    return open
  end

  -- Close the window when ESC is pressed and the window is focused
  if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
    open = false
    if gui.debug then
      r.ShowConsoleMsg("[AS GUI] Keyboard shortcut: ESC pressed (Close window)\n")
    end
  end

  -- Menu Bar
  if ImGui.BeginMenuBar(ctx) then
    if ImGui.BeginMenu(ctx, 'Debug') then
      local rv, new_val = ImGui.MenuItem(ctx, 'Enable Debug Mode', nil, gui.debug, true)
      if rv then
        gui.debug = new_val
        save_gui_settings()
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Settings') then
      -- UI Settings
      local rv_dock, new_dock = ImGui.MenuItem(ctx, 'Enable Window Docking', nil, gui.enable_docking, true)
      if rv_dock then
        gui.enable_docking = new_dock
        save_gui_settings()
      end
      ImGui.Separator(ctx)

      -- Unified Settings Window
      if ImGui.MenuItem(ctx, 'Settings...', nil, false, true) then
        gui.show_unified_settings = true
      end
      ImGui.Separator(ctx)

      if ImGui.BeginMenu(ctx, 'FX Alias Tools') then
        if ImGui.MenuItem(ctx, 'Build FX Alias Database', nil, false, true) then
          local script_path = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Rendering/hsuanice_FX Alias Build.lua"
          local success, err = pcall(dofile, script_path)
          if success then
            r.ShowConsoleMsg("[AS GUI] FX Alias Build completed\n")
          else
            r.ShowConsoleMsg("[AS GUI] Error running FX Alias Build: " .. tostring(err) .. "\n")
          end
        end
        if ImGui.MenuItem(ctx, 'Export JSON to TSV', nil, false, true) then
          local script_path = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Rendering/hsuanice_FX Alias Export JSON to TSV.lua"
          local success, err = pcall(dofile, script_path)
          if success then
            r.ShowConsoleMsg("[AS GUI] FX Alias Export completed\n")
          else
            r.ShowConsoleMsg("[AS GUI] Error running FX Alias Export: " .. tostring(err) .. "\n")
          end
        end
        if ImGui.MenuItem(ctx, 'Update TSV to JSON', nil, false, true) then
          local script_path = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Rendering/hsuanice_FX Alias Update TSV to JSON.lua"
          local success, err = pcall(dofile, script_path)
          if success then
            r.ShowConsoleMsg("[AS GUI] FX Alias Update completed\n")
          else
            r.ShowConsoleMsg("[AS GUI] Error running FX Alias Update: " .. tostring(err) .. "\n")
          end
        end
        ImGui.EndMenu(ctx)
      end
      ImGui.EndMenu(ctx)
    end

    if ImGui.BeginMenu(ctx, 'Help') then
      if ImGui.MenuItem(ctx, 'User Manual', nil, false, true) then
        gui.show_help_window = true
      end
      if ImGui.MenuItem(ctx, 'About', nil, false, true) then
        r.ShowConsoleMsg(
          "=================================================\n" ..
          "AudioSweet ReaImGui - ImGui Interface for AudioSweet\n" ..
          "=================================================\n" ..
          "Version: " .. VERSION .. "\n" ..
          "Author: hsuanice\n\n" ..

          "Reference:\n" ..
          "  Inspired by AudioSuite-like Script by Tim Chimes\n" ..
          "  'AudioSweet' is a name originally given by Tim Chimes.\n" ..
          "  This project continues to use the name in reference to his original work.\n\n" ..
          "  Original: Renders selected plugin to selected media item\n" ..
          "  Written for REAPER 5.1 with Lua\n" ..
          "  v1.1 12/22/2015 - Added PreventUIRefresh\n" ..
          "  http://timchimes.com/scripting-with-reaper-audiosuite/\n\n" ..

          "Development:\n" ..
          "  This script was developed with the assistance of AI tools\n" ..
          "  including ChatGPT and Claude AI.\n" ..
          "=================================================\n"
        )
      end
    ImGui.EndMenu(ctx)
  end

  ImGui.EndMenuBar(ctx)
end

  draw_bwfmetaedit_warning_banner()

  -- ====================================================================
  -- Unified Settings Window with Tabs
  -- ====================================================================
  if gui.show_unified_settings then
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.SetNextWindowSize(ctx, 600, 500, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'AudioSweet Settings')
    gui.show_unified_settings = false
  end

  if ImGui.BeginPopupModal(ctx, 'AudioSweet Settings', true, ImGui.WindowFlags_None) then
    -- ESC key handling
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    -- Tab Bar
    if ImGui.BeginTabBar(ctx, 'SettingsTabs', ImGui.TabBarFlags_None) then

      -- ============================================================
      -- Tab 1: FX Display Settings
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'FX Display') then
        local changed = false
        local rv

        ImGui.Text(ctx, "FX Display Settings")
        ImGui.TextDisabled(ctx, "Configure how FX names appear in different contexts")
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        -- Button Display Section
        ImGui.Text(ctx, "1. Button Display (Preset/History Buttons)")
        ImGui.Indent(ctx)
        rv, gui.button_show_type = ImGui.Checkbox(ctx, "Show Type##button", gui.button_show_type)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.button_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##button", gui.button_show_vendor)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.button_use_alias = ImGui.Checkbox(ctx, "Use Alias##button", gui.button_use_alias)
        if rv then
          fx_alias_cache.loaded = false
          changed = true
        end
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        -- Tooltip Display Section
        ImGui.Text(ctx, "2. Tooltip Display (Hover Info)")
        ImGui.Indent(ctx)
        rv, gui.tooltip_show_type = ImGui.Checkbox(ctx, "Show Type##tooltip", gui.tooltip_show_type)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.tooltip_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##tooltip", gui.tooltip_show_vendor)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.tooltip_use_alias = ImGui.Checkbox(ctx, "Use Alias##tooltip", gui.tooltip_use_alias)
        if rv then
          fx_alias_cache.loaded = false
          changed = true
        end
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        -- Status Display Section
        ImGui.Text(ctx, "3. Status Display (Bottom Bar)")
        ImGui.Indent(ctx)
        rv, gui.status_show_type = ImGui.Checkbox(ctx, "Show Type##status", gui.status_show_type)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.status_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##status", gui.status_show_vendor)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.status_use_alias = ImGui.Checkbox(ctx, "Use Alias##status", gui.status_use_alias)
        if rv then
          fx_alias_cache.loaded = false
          changed = true
        end
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        -- FX List Display Section
        ImGui.Text(ctx, "4. FX Chain List Display (Chain Mode)")
        ImGui.Indent(ctx)
        rv, gui.fxlist_show_type = ImGui.Checkbox(ctx, "Show Type##fxlist", gui.fxlist_show_type)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.fxlist_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##fxlist", gui.fxlist_show_vendor)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        rv, gui.fxlist_use_alias = ImGui.Checkbox(ctx, "Use Alias##fxlist", gui.fxlist_use_alias)
        if rv then
          fx_alias_cache.loaded = false
          changed = true
        end
        ImGui.Unindent(ctx)

        if changed then
          save_gui_settings()
        end

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab 2: File Naming Settings
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'File Naming') then
        local changed = false
        local rv

        -- === Global FX Name Settings (applies to Focused & Chain modes) ===
        ImGui.Text(ctx, "Global FX Name Settings:")
        ImGui.TextDisabled(ctx, "(applies to both Focused and Chain modes)")
        ImGui.Separator(ctx)

        rv, gui.fxname_show_type = ImGui.Checkbox(ctx, "Show Plugin Type (CLAP:, VST3:, AU:, VST:)", gui.fxname_show_type)
        if rv then changed = true end

        rv, gui.fxname_show_vendor = ImGui.Checkbox(ctx, "Show Vendor Name (FabFilter)", gui.fxname_show_vendor)
        if rv then changed = true end

        rv, gui.fxname_strip_symbol = ImGui.Checkbox(ctx, "Strip Spaces & Symbols (ProQ4 vs Pro-Q 4)", gui.fxname_strip_symbol)
        if rv then changed = true end

        rv, gui.use_alias = ImGui.Checkbox(ctx, "Use FX Alias for file naming", gui.use_alias)
        if rv then changed = true end

        ImGui.Text(ctx, "Max FX Tokens:")
        ImGui.SameLine(ctx)
        ImGui.SetNextItemWidth(ctx, 80)
        rv, gui.max_fx_tokens = ImGui.InputInt(ctx, "##max_tokens", gui.max_fx_tokens)
        if rv then
          gui.max_fx_tokens = math.max(1, math.min(10, gui.max_fx_tokens))
          changed = true
        end
        ImGui.SameLine(ctx)
        ImGui.TextDisabled(ctx, "(FIFO limit, 1-10)")

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        -- === Chain Mode Specific Settings ===
        ImGui.Text(ctx, "Chain Mode Specific Settings:")
        ImGui.Separator(ctx)

        ImGui.Text(ctx, "Chain Token Source:")
        if ImGui.RadioButton(ctx, "Track Name", gui.chain_token_source == 0) then
          gui.chain_token_source = 0
          changed = true
        end
        ImGui.SameLine(ctx)
        if ImGui.RadioButton(ctx, "FX Aliases", gui.chain_token_source == 1) then
          gui.chain_token_source = 1
          changed = true
        end
        ImGui.SameLine(ctx)
        if ImGui.RadioButton(ctx, "FXChain", gui.chain_token_source == 2) then
          gui.chain_token_source = 2
          changed = true
        end

        -- Chain Alias Joiner (only when using aliases)
        if gui.chain_token_source == 1 then
          ImGui.Text(ctx, "Alias Joiner:")
          ImGui.SameLine(ctx)
          ImGui.SetNextItemWidth(ctx, 100)
          rv, gui.chain_alias_joiner = ImGui.InputText(ctx, "##chain_joiner", gui.chain_alias_joiner)
          if rv then changed = true end
          ImGui.SameLine(ctx)
          ImGui.TextDisabled(ctx, "(separator between aliases)")
        end

        rv, gui.trackname_strip_symbols = ImGui.Checkbox(ctx, "Strip Symbols from Track Names", gui.trackname_strip_symbols)
        if rv then changed = true end

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        -- === File Safety Section ===
        ImGui.Text(ctx, "File Name Safety:")
        ImGui.Separator(ctx)

        rv, gui.sanitize_token = ImGui.Checkbox(ctx, "Sanitize tokens for safe filenames", gui.sanitize_token)
        if rv then changed = true end
        ImGui.SameLine(ctx)
        ImGui.TextDisabled(ctx, "(?)")
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Replace unsafe characters with underscores")
        end

        if changed then
          save_gui_settings()
        end

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab 3: Preview Settings
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'Preview') then
        ImGui.Text(ctx, "Target Track Name:")
        ImGui.SetNextItemWidth(ctx, 200)
        local rv, new_name = ImGui.InputText(ctx, "##preview_target", gui.preview_target_track)
        if rv then
          gui.preview_target_track = new_name
          save_gui_settings()
        end
        ImGui.TextWrapped(ctx, "The track where preview will be applied")

        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Solo Scope:")
        local changed_scope = false
        if ImGui.RadioButton(ctx, "Track Solo (40281)", gui.preview_solo_scope == 0) then
          gui.preview_solo_scope = 0
          changed_scope = true
        end
        ImGui.SameLine(ctx)
        if ImGui.RadioButton(ctx, "Item Solo (41561)", gui.preview_solo_scope == 1) then
          gui.preview_solo_scope = 1
          changed_scope = true
        end
        if changed_scope then
          save_gui_settings()
        end

        -- Warning for Item Solo lag
        if gui.preview_solo_scope == 1 then
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFAA00FF)  -- Orange color
          ImGui.TextWrapped(ctx, "Note: Item Solo may have a slight lag when toggling, not as responsive as Track Solo.")
          ImGui.PopStyleColor(ctx)
        end

        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Restore Mode:")
        local changed_restore = false
        if ImGui.RadioButton(ctx, "Time Selection", gui.preview_restore_mode == 0) then
          gui.preview_restore_mode = 0
          changed_restore = true
        end
        ImGui.SameLine(ctx)
        if ImGui.RadioButton(ctx, "GUID", gui.preview_restore_mode == 1) then
          gui.preview_restore_mode = 1
          changed_restore = true
        end
        if changed_restore then
          save_gui_settings()
        end

        ImGui.Separator(ctx)
        ImGui.TextWrapped(ctx,
          "Time Selection: Restores original FX state when leaving time selection.\n" ..
          "GUID: Restores FX state when the preview track GUID changes (switching projects).")

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab: Glue unit grouping (item selection, no Time Selection)
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'Glue & Render') then
        ImGui.Text(ctx, "Glue Grouping (item selection, no Time Selection)")
        ImGui.TextDisabled(ctx, "Which touching / crossfading items are glued into one unit")
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        if ImGui.RadioButton(ctx, "Glue all (original behavior)##glue_grouping", gui.glue_grouping == 0) then
          gui.glue_grouping = 0
          save_gui_settings()
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "All touching and crossfading items on a track become one unit\nMute state is ignored")
        end

        if ImGui.RadioButton(ctx, "Follow RGWH GUI settings##glue_grouping", gui.glue_grouping == 1) then
          gui.glue_grouping = 1
          save_gui_settings()
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Use RGWH GUI's \"Keep MUTED as separate unit\" and \"Split at crossfades\"\n(read from this project's RGWH settings at run time)")
        end

        if ImGui.RadioButton(ctx, "AudioSweet settings##glue_grouping", gui.glue_grouping == 2) then
          gui.glue_grouping = 2
          save_gui_settings()
        end

        ImGui.Indent(ctx)
        if gui.glue_grouping ~= 2 then ImGui.BeginDisabled(ctx) end
        local rv_mute, new_mute = ImGui.Checkbox(ctx, "Keep MUTED as separate unit##as_glue", gui.glue_muted_separate)
        if rv_mute then
          gui.glue_muted_separate = new_mute
          save_gui_settings()
        end
        if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
          ImGui.SetTooltip(ctx, "Muted and unmuted items never share a unit\n(adjacent muted items still group together)")
        end
        local rv_xf, new_xf = ImGui.Checkbox(ctx, "Split at crossfades##as_glue", gui.glue_split_at_crossfades)
        if rv_xf then
          gui.glue_split_at_crossfades = new_xf
          save_gui_settings()
        end
        if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
          ImGui.SetTooltip(ctx, "Crossfading items are not grouped into the same unit\nOnly touching items share a unit")
        end
        if gui.glue_grouping ~= 2 then ImGui.EndDisabled(ctx) end
        ImGui.Unindent(ctx)

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.TextWrapped(ctx, "Glue grouping and Single item Render only apply to item selection. With a Time Selection, AudioSweet glues as before (the Time Selection decides the range).")

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Single Item Render (item selection, no Time Selection)")
        ImGui.Spacing(ctx)
        local rv_render, new_render = ImGui.Checkbox(ctx, "Single item: Render (keep takes)##as_single_render", gui.single_item_render)
        if rv_render then
          gui.single_item_render = new_render
          save_gui_settings()
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "A unit with only one item is rendered to a new take instead of glued\n" ..
            "Older takes are kept\n" ..
            "Item selection only — with a Time Selection, items are glued as before\n" ..
            "Tail Seconds does not apply to Render")
        end

        ImGui.Indent(ctx)
        if not gui.single_item_render then ImGui.BeginDisabled(ctx) end
        local rv_keep, new_keep = ImGui.Checkbox(ctx, "Retain Glue Cues##as_render_keep_glue", gui.render_keep_glue_cues)
        if rv_keep then
          gui.render_keep_glue_cues = new_keep
          save_gui_settings()
        end
        if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
          ImGui.SetTooltip(ctx, "Render keeps the Glue cues already in the source file\n(e.g. from an earlier glue of the edit). Requires SWS")
        end
        if not gui.single_item_render then ImGui.EndDisabled(ctx) end
        ImGui.Unindent(ctx)

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab 4: History Settings
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'History') then
        ImGui.Text(ctx, "Maximum History Items:")
        ImGui.SetNextItemWidth(ctx, 120)
        local rv, new_val = ImGui.InputInt(ctx, "##max_history", gui.max_history)
        if rv then
          gui.max_history = math.max(1, math.min(50, new_val))  -- Limit 1-50
          save_gui_settings()
          -- Trim history if needed
          while #gui.history > gui.max_history do
            table.remove(gui.history)
          end
        end

        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Range: 1-50 items")

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab 6: Timecode Embed Settings
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'Timecode') then
        if bwf_cli.available then
          ImGui.TextColored(ctx, 0x55FF55FF, ("CLI detected: %s"):format(bwf_cli.resolved_path))
          if bwf_cli.last_source ~= "" then
            ImGui.TextDisabled(ctx, ("Source: %s"):format(bwf_cli.last_source))
          end
        else
          ImGui.TextColored(ctx, 0xFF6666FF, "bwfmetaedit CLI not detected – Timecode embedding stays disabled.")
          if bwf_cli.message ~= "" then
            ImGui.TextWrapped(ctx, bwf_cli.message)
          end
        end

        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Custom CLI Path (optional):")
        ImGui.SetNextItemWidth(ctx, 360)
        local rv_path, new_path = ImGui.InputText(ctx, "##as_bwf_path", gui.bwfmetaedit_custom_path or "")
        if rv_path then
          gui.bwfmetaedit_custom_path = new_path
          save_gui_settings()
        end
        ImGui.TextDisabled(ctx, "Leave blank to search PATH. Provide full path incl. .exe on Windows.")

        ImGui.Separator(ctx)
        if ImGui.Button(ctx, "Re-check CLI##as_settings") then
          check_bwfmetaedit(true)
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Install Guide##as_settings") then
          gui.open_bwf_install_popup = true
        end

        ImGui.Spacing(ctx)
        ImGui.TextWrapped(ctx,
          "AudioSweet uses bwfmetaedit after renders to embed BWF TimeReference so downstream apps read the correct TC.\n" ..
          "If you skip installation, rendering still works but the embed step is skipped.")

        ImGui.EndTabItem(ctx)
      end

      -- Keyboard Shortcuts Tab
      if ImGui.BeginTabItem(ctx, 'Keyboard Shortcuts') then
        ImGui.Spacing(ctx)
        ImGui.TextWrapped(ctx, "AudioSweet keyboard shortcuts require setting up Tools scripts in REAPER's Action List.")
        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        -- Action List Scripts Section
        ImGui.TextColored(ctx, 0x4DA6FFFF, "Required Action List Scripts:")
        ImGui.Spacing(ctx)
        ImGui.TextWrapped(ctx,
          "To use keyboard shortcuts, assign these AudioSweet Tools scripts in REAPER's Action List:")

        ImGui.Spacing(ctx)
        ImGui.Indent(ctx)

        -- Script 1: Run
        local script_run = "hsuanice_AudioSweet Run"
        ImGui.BulletText(ctx, "Script: " .. script_run)
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Copy##run") then
          r.ImGui_SetClipboardText(ctx, script_run)
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Copy script name to clipboard for searching in Action List")
        end
        ImGui.Indent(ctx)
        ImGui.TextColored(ctx, 0xAAAAAAFF, "Recommended shortcut: Ctrl+Enter")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        -- Script 2: Solo Toggle
        local script_solo = "hsuanice_AudioSweet Solo Toggle"
        ImGui.BulletText(ctx, "Script: " .. script_solo)
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Copy##solo") then
          r.ImGui_SetClipboardText(ctx, script_solo)
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Copy script name to clipboard for searching in Action List")
        end
        ImGui.Indent(ctx)
        ImGui.TextColored(ctx, 0xAAAAAAFF, "Recommended shortcut: Ctrl+S")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        -- Script 3: Preview Toggle
        local script_preview = "hsuanice_AudioSweet Preview Toggle"
        ImGui.BulletText(ctx, "Script: " .. script_preview)
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Copy##preview") then
          r.ImGui_SetClipboardText(ctx, script_preview)
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Copy script name to clipboard for searching in Action List")
        end
        ImGui.Indent(ctx)
        ImGui.TextColored(ctx, 0xAAAAAAFF, "Recommended shortcut: Ctrl+Space")
        ImGui.Unindent(ctx)

        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        -- How to Set Shortcuts Tutorial
        ImGui.TextColored(ctx, 0x4DA6FFFF, "How to set up keyboard shortcuts:")
        ImGui.Spacing(ctx)
        ImGui.TextWrapped(ctx, "1. Open REAPER's Actions window (? → Actions → Show action list)")
        ImGui.TextWrapped(ctx, "2. Search for the script name using the 'Copy' buttons above")
        ImGui.TextWrapped(ctx, "3. Select the script in the list")
        ImGui.TextWrapped(ctx, "4. Click 'Add' button at the bottom to open the shortcut assignment window")
        ImGui.TextWrapped(ctx, "5. In the Add window: Set 'Scope' dropdown to 'Global' (IMPORTANT!)")
        ImGui.TextWrapped(ctx, "6. Press your desired key combination (e.g., Ctrl+Enter)")
        ImGui.TextWrapped(ctx, "7. Click 'OK' to save")
        ImGui.Spacing(ctx)
        ImGui.TextWrapped(ctx, "Repeat for each script. Global scope ensures shortcuts work everywhere in REAPER, including when GUI is focused.")

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        -- Important Notes
        ImGui.TextColored(ctx, 0x4DA6FFFF, "Important:")
        ImGui.Spacing(ctx)
        ImGui.BulletText(ctx, "Shortcuts must be set to 'Global' scope to work when GUI window is focused")
        ImGui.BulletText(ctx, "All REAPER keyboard shortcuts work normally when GUI is open")
        ImGui.BulletText(ctx, "ESC key closes the GUI window")
        ImGui.BulletText(ctx, "Text input fields capture keyboard input normally for editing")

        ImGui.Spacing(ctx)
        ImGui.Separator(ctx)
        ImGui.Spacing(ctx)

        -- Benefits Section
        ImGui.TextColored(ctx, 0x4DA6FFFF, "Why use Action List shortcuts?")
        ImGui.Spacing(ctx)
        ImGui.BulletText(ctx, "Work globally throughout REAPER (not just in GUI)")
        ImGui.BulletText(ctx, "Single configuration applies everywhere")
        ImGui.BulletText(ctx, "Can be used in custom actions and macros")
        ImGui.BulletText(ctx, "Faster execution with direct script calls")

        ImGui.EndTabItem(ctx)
      end

      ImGui.EndTabBar(ctx)
    end

    -- Close Button
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- ====================================================================
  -- Legacy Individual Settings Popups (kept for backward compatibility)
  -- ====================================================================
  -- Settings Popup
  if gui.show_settings_popup then
    -- Position popup near mouse cursor
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'History Settings')
    gui.show_settings_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'History Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- ESC key handling for popup (only when popup is focused)
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.Text(ctx, "Maximum History Items:")
    ImGui.SetNextItemWidth(ctx, 120)
    local rv, new_val = ImGui.InputInt(ctx, "##max_history", gui.max_history)
    if rv then
      gui.max_history = math.max(1, math.min(50, new_val))  -- Limit 1-50
      save_gui_settings()
      -- Trim history if needed
      while #gui.history > gui.max_history do
        table.remove(gui.history)
      end
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Range: 1-50 items")

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- FX Name Formatting Popup
  -- File Naming Settings Popup
  if gui.show_naming_popup then
    -- Position popup near mouse cursor
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'File Naming Settings')
    gui.show_naming_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'File Naming Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- ESC key handling for popup (only when popup is focused)
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    local changed = false
    local rv

    -- === Global FX Name Settings (applies to Focused & Chain modes) ===
    ImGui.Text(ctx, "Global FX Name Settings:")
    ImGui.TextDisabled(ctx, "(applies to both Focused and Chain modes)")
    ImGui.Separator(ctx)

    rv, gui.fxname_show_type = ImGui.Checkbox(ctx, "Show Plugin Type (CLAP:, VST3:, AU:, VST:)", gui.fxname_show_type)
    if rv then changed = true end

    rv, gui.fxname_show_vendor = ImGui.Checkbox(ctx, "Show Vendor Name (FabFilter)", gui.fxname_show_vendor)
    if rv then changed = true end

    rv, gui.fxname_strip_symbol = ImGui.Checkbox(ctx, "Strip Spaces & Symbols (ProQ4 vs Pro-Q 4)", gui.fxname_strip_symbol)
    if rv then changed = true end

    rv, gui.use_alias = ImGui.Checkbox(ctx, "Use FX Alias for file naming", gui.use_alias)
    if rv then changed = true end

    ImGui.Text(ctx, "Max FX Tokens:")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 80)
    rv, gui.max_fx_tokens = ImGui.InputInt(ctx, "##max_tokens", gui.max_fx_tokens)
    if rv then
      gui.max_fx_tokens = math.max(1, math.min(10, gui.max_fx_tokens))
      changed = true
    end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(FIFO limit, 1-10)")

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- === Chain Mode Specific Settings ===
    ImGui.Text(ctx, "Chain Mode Specific Settings:")
    ImGui.Separator(ctx)

    ImGui.Text(ctx, "Chain Token Source:")
    if ImGui.RadioButton(ctx, "Track Name", gui.chain_token_source == 0) then
      gui.chain_token_source = 0
      changed = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "FX Aliases", gui.chain_token_source == 1) then
      gui.chain_token_source = 1
      changed = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "FXChain", gui.chain_token_source == 2) then
      gui.chain_token_source = 2
      changed = true
    end

    -- Chain Alias Joiner (only when using aliases)
    if gui.chain_token_source == 1 then
      ImGui.Text(ctx, "Alias Joiner:")
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 100)
      rv, gui.chain_alias_joiner = ImGui.InputText(ctx, "##chain_joiner", gui.chain_alias_joiner)
      if rv then changed = true end
      ImGui.SameLine(ctx)
      ImGui.TextDisabled(ctx, "(separator between aliases)")
    end

    rv, gui.trackname_strip_symbols = ImGui.Checkbox(ctx, "Strip Symbols from Track Names", gui.trackname_strip_symbols)
    if rv then changed = true end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- === File Safety Section ===
    ImGui.Text(ctx, "File Name Safety:")
    ImGui.Separator(ctx)

    rv, gui.sanitize_token = ImGui.Checkbox(ctx, "Sanitize tokens for safe filenames", gui.sanitize_token)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    ImGui.TextDisabled(ctx, "(?)")
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Replace unsafe characters with underscores")
    end

    if changed then
      save_gui_settings()
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- ====================================================================
  -- Help / User Manual Window
  -- ====================================================================
  if gui.show_help_window then
    ImGui.SetNextWindowSize(ctx, 700, 600, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'AudioSweet User Manual')
    gui.show_help_window = false
  end

  if ImGui.BeginPopupModal(ctx, 'AudioSweet User Manual', true, ImGui.WindowFlags_None) then
    -- ESC key handling
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    -- Tab Bar for different manual sections
    if ImGui.BeginTabBar(ctx, 'HelpTabs', ImGui.TabBarFlags_None) then

      -- ============================================================
      -- Tab 1: Getting Started
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'Getting Started') then
        ImGui.TextColored(ctx, 0xFFAA55FF, "Overview")
        ImGui.Separator(ctx)
        ImGui.TextWrapped(ctx, "Complete AudioSweet control center with ImGui interface for managing FX chains and presets.")
        ImGui.Spacing(ctx)

        ImGui.TextColored(ctx, 0xFFAA55FF, "Core Features")
        ImGui.Separator(ctx)
        ImGui.BulletText(ctx, "Two operation modes: Focused FX and Full Chain")
        ImGui.BulletText(ctx, "Apply/Copy FX chains to AudioSweet Preview track")
        ImGui.BulletText(ctx, "Save and manage FX presets with custom naming")
        ImGui.BulletText(ctx, "Automatic operation history tracking")
        ImGui.BulletText(ctx, "Real-time FX chain visualization")
        ImGui.BulletText(ctx, "Built-in keyboard shortcuts")
        ImGui.BulletText(ctx, "Persistent settings across sessions")
        ImGui.Spacing(ctx)

        ImGui.TextColored(ctx, 0xFFAA55FF, "Operation Modes")
        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Focused Mode (Single FX)")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Works with the currently focused FX window")
        ImGui.BulletText(ctx, "Click on any FX window to focus it")
        ImGui.BulletText(ctx, "Saves/applies only the selected FX")
        ImGui.BulletText(ctx, "Display shows: FX name only (e.g., 'VST3: Pro-Q 4')")
        ImGui.BulletText(ctx, "Supports CLAP and VST3 plugins")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Chain Mode (Full FX Chain)")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Works with the entire FX chain of selected track")
        ImGui.BulletText(ctx, "Saves/applies all FX on the track")
        ImGui.BulletText(ctx, "Display shows: '#N Track Name' format")
        ImGui.BulletText(ctx, "Shows complete FX list in tooltips")
        ImGui.Unindent(ctx)

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab 2: Actions & Presets
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'Actions & Presets') then
        ImGui.TextColored(ctx, 0xFFAA55FF, "Main Actions")
        ImGui.Separator(ctx)

        ImGui.Text(ctx, "Apply")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Copies FX to Preview track AND enables it")
        ImGui.BulletText(ctx, "Removes all existing FX on Preview track first")
        ImGui.BulletText(ctx, "Use when you want to audition the FX immediately")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Copy")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Copies FX to Preview track but keeps it bypassed")
        ImGui.BulletText(ctx, "Removes all existing FX on Preview track first")
        ImGui.BulletText(ctx, "Use when you want to prepare FX without hearing it yet")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Open")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Opens the saved FX window(s)")
        ImGui.BulletText(ctx, "Focused mode: Opens the specific FX window")
        ImGui.BulletText(ctx, "Chain mode: Opens all FX windows in the chain")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.TextColored(ctx, 0xFFAA55FF, "Preset System")
        ImGui.Separator(ctx)

        ImGui.Text(ctx, "Saving Presets")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "1. Click the 'Save' button (in main controls or history section)")
        ImGui.BulletText(ctx, "2. Enter a custom name, or leave empty to use default:")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Focused mode default: FX name")
        ImGui.BulletText(ctx, "Chain mode default: Track name")
        ImGui.Unindent(ctx)
        ImGui.BulletText(ctx, "3. Preset is saved and appears in the 'Saved' section")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Managing Presets")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Open: Opens the FX window(s) without applying")
        ImGui.BulletText(ctx, "Name: Rename the preset (custom name or revert to default)")
        ImGui.BulletText(ctx, "Save: Save current FX as a new preset")
        ImGui.BulletText(ctx, "Delete (X button): Remove the preset permanently")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Preset Display Names")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Custom name: Shows your custom name")
        ImGui.BulletText(ctx, "Default name (Focused): Shows current FX name from track")
        ImGui.BulletText(ctx, "Default name (Chain): Shows '#N Current Track Name'")
        ImGui.BulletText(ctx, "Hover tooltip: Shows full FX chain with track info")
        ImGui.Unindent(ctx)

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab 3: History & Workflows
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'History & Workflows') then
        ImGui.TextColored(ctx, 0xFFAA55FF, "History System")
        ImGui.Separator(ctx)

        ImGui.Text(ctx, "Automatic Tracking")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Every Apply/Copy operation is automatically logged")
        ImGui.BulletText(ctx, "History stores up to 50 recent operations")
        ImGui.BulletText(ctx, "Newest operations appear at the top")
        ImGui.BulletText(ctx, "Duplicates are automatically removed")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "History Actions")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Open: Opens the FX window(s) from this history entry")
        ImGui.BulletText(ctx, "Name: Rename this history entry (becomes a custom name)")
        ImGui.BulletText(ctx, "Save: Convert this history entry into a saved preset")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.TextColored(ctx, 0xFFAA55FF, "Workflow Examples")
        ImGui.Separator(ctx)

        ImGui.Text(ctx, "Workflow 1: Quick FX Auditioning")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "1. Select track with FX chain")
        ImGui.BulletText(ctx, "2. Switch to Chain mode")
        ImGui.BulletText(ctx, "3. Click 'Apply' to audition the full chain")
        ImGui.BulletText(ctx, "4. Click 'Save' if you like it")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Workflow 2: Building FX Library")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "1. Focus on individual FX window")
        ImGui.BulletText(ctx, "2. Switch to Focused mode")
        ImGui.BulletText(ctx, "3. Click 'Save' and name it (e.g., 'Vocal EQ Bright')")
        ImGui.BulletText(ctx, "4. Repeat for different FX")
        ImGui.BulletText(ctx, "5. Access your library from 'Saved' section anytime")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Workflow 3: Using History")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "1. Experiment with different FX chains using Apply")
        ImGui.BulletText(ctx, "2. All attempts are logged in History")
        ImGui.BulletText(ctx, "3. Go back to History and click 'Open' on any entry to review")
        ImGui.BulletText(ctx, "4. Click 'Save' on the one you like to make it permanent")
        ImGui.Unindent(ctx)

        ImGui.EndTabItem(ctx)
      end

      -- ============================================================
      -- Tab 4: Tips & Troubleshooting
      -- ============================================================
      if ImGui.BeginTabItem(ctx, 'Tips & Troubleshooting') then
        ImGui.TextColored(ctx, 0xFFAA55FF, "Tips & Tricks")
        ImGui.Separator(ctx)

        ImGui.Text(ctx, "Name Management")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Leave name empty when saving = dynamic name (updates with track/FX renames)")
        ImGui.BulletText(ctx, "Enter custom name = static name (never changes)")
        ImGui.BulletText(ctx, "You can always rename later using the 'Name' button")
        ImGui.BulletText(ctx, "Renaming a preset automatically updates all matching history entries")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "FX Chain Tooltips")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Hover over any preset/history item to see full FX chain")
        ImGui.BulletText(ctx, "Focused mode: Saved FX is highlighted in GREEN")
        ImGui.BulletText(ctx, "Shows track number and current track name")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Keyboard Shortcuts")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Space: Play/Stop transport")
        ImGui.BulletText(ctx, "S: Toggle solo on Preview track")
        ImGui.BulletText(ctx, "Esc: Close dialogs")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.TextColored(ctx, 0xFFAA55FF, "Troubleshooting")
        ImGui.Separator(ctx)

        ImGui.Text(ctx, "'No focused FX' in Focused Mode")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "Click on any FX window to focus it")
        ImGui.BulletText(ctx, "Make sure the FX window is open (not just in FX chain list)")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.Text(ctx, "Preset Opens Wrong FX")
        ImGui.Indent(ctx)
        ImGui.BulletText(ctx, "This can happen if you reordered FX after saving")
        ImGui.BulletText(ctx, "The script tries to match by name as fallback")
        ImGui.BulletText(ctx, "Enable Debug mode to see index matching details")
        ImGui.Unindent(ctx)
        ImGui.Spacing(ctx)

        ImGui.TextColored(ctx, 0xFFAA55FF, "Technical Notes")
        ImGui.Separator(ctx)
        ImGui.BulletText(ctx, "All presets saved in REAPER project ExtState (persistent per project)")
        ImGui.BulletText(ctx, "History limited to 50 entries (configurable in Settings)")
        ImGui.BulletText(ctx, "Supports CLAP, VST3, VST2, AU, and JS plugins")
        ImGui.BulletText(ctx, "FX matching uses both index and name for reliability")
        ImGui.BulletText(ctx, "Track identification uses GUID (survives track reordering)")

        ImGui.EndTabItem(ctx)
      end

      ImGui.EndTabBar(ctx)
    end

    -- Close Button
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- Preset/History Display Settings Popup
  if gui.show_preset_display_popup then
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'Preset/History Display')
    gui.show_preset_display_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'Preset/History Display', true, ImGui.WindowFlags_AlwaysAutoResize) then
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    local changed = false
    local rv

    ImGui.Text(ctx, "FX Display Settings")
    ImGui.TextDisabled(ctx, "Configure how FX names appear in different contexts")
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- Button Display Section
    ImGui.Text(ctx, "1. Button Display (Preset/History Buttons)")
    ImGui.Indent(ctx)
    rv, gui.button_show_type = ImGui.Checkbox(ctx, "Show Type##button", gui.button_show_type)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.button_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##button", gui.button_show_vendor)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.button_use_alias = ImGui.Checkbox(ctx, "Use Alias##button", gui.button_use_alias)
    if rv then
      fx_alias_cache.loaded = false
      changed = true
    end
    ImGui.Unindent(ctx)
    ImGui.Spacing(ctx)

    -- Tooltip Display Section
    ImGui.Text(ctx, "2. Tooltip Display (Hover Info)")
    ImGui.Indent(ctx)
    rv, gui.tooltip_show_type = ImGui.Checkbox(ctx, "Show Type##tooltip", gui.tooltip_show_type)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.tooltip_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##tooltip", gui.tooltip_show_vendor)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.tooltip_use_alias = ImGui.Checkbox(ctx, "Use Alias##tooltip", gui.tooltip_use_alias)
    if rv then
      fx_alias_cache.loaded = false
      changed = true
    end
    ImGui.Unindent(ctx)
    ImGui.Spacing(ctx)

    -- Status Display Section
    ImGui.Text(ctx, "3. Status Display (Bottom Bar)")
    ImGui.Indent(ctx)
    rv, gui.status_show_type = ImGui.Checkbox(ctx, "Show Type##status", gui.status_show_type)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.status_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##status", gui.status_show_vendor)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.status_use_alias = ImGui.Checkbox(ctx, "Use Alias##status", gui.status_use_alias)
    if rv then
      fx_alias_cache.loaded = false
      changed = true
    end
    ImGui.Unindent(ctx)
    ImGui.Spacing(ctx)

    -- FX List Display Section
    ImGui.Text(ctx, "4. FX Chain List Display (Chain Mode)")
    ImGui.Indent(ctx)
    rv, gui.fxlist_show_type = ImGui.Checkbox(ctx, "Show Type##fxlist", gui.fxlist_show_type)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.fxlist_show_vendor = ImGui.Checkbox(ctx, "Show Vendor##fxlist", gui.fxlist_show_vendor)
    if rv then changed = true end
    ImGui.SameLine(ctx)
    rv, gui.fxlist_use_alias = ImGui.Checkbox(ctx, "Use Alias##fxlist", gui.fxlist_use_alias)
    if rv then
      fx_alias_cache.loaded = false
      changed = true
    end
    ImGui.Unindent(ctx)

    -- Alias warning
    local alias_path = RES_PATH .. "/Scripts/hsuanice Scripts/Settings/fx_alias.json"
    if (gui.button_use_alias or gui.tooltip_use_alias or gui.status_use_alias or gui.fxlist_use_alias) and not file_exists(alias_path) then
      ImGui.Spacing(ctx)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFAA00FF)
      ImGui.TextWrapped(ctx, "FX Alias database not found. Build it via Settings -> FX Alias Tools.")
      ImGui.PopStyleColor(ctx)
    end

    if changed then
      save_gui_settings()
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- Target Track Name Popup (simple input)
  if gui.show_target_track_popup then
    ImGui.OpenPopup(ctx, 'Edit Preview Target Track')
    gui.show_target_track_popup = false
  end

  if ImGui.BeginPopupModal(ctx, 'Edit Preview Target Track', true, ImGui.WindowFlags_AlwaysAutoResize) then
    ImGui.Text(ctx, "Enter target track name for preview:")
    ImGui.SetNextItemWidth(ctx, 250)
    local rv, new_target = ImGui.InputText(ctx, "##target_track_input", gui.preview_target_track)
    if rv then
      gui.preview_target_track = new_target
      save_gui_settings()
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    ImGui.Spacing(ctx)

    -- "Set First Selected Track" button
    if ImGui.Button(ctx, 'Set First Selected Track', 250, 0) then
      local first_track = r.GetSelectedTrack(0, 0)  -- Get first selected track (index 0)
      if first_track then
        local _, track_name = r.GetSetMediaTrackInfo_String(first_track, "P_NAME", "", false)
        local track_guid = get_track_guid(first_track)
        gui.preview_target_track = track_name
        gui.preview_target_track_guid = track_guid
        save_gui_settings()
        if gui.debug then
          r.ShowConsoleMsg(string.format("[AudioSweet] Preview target set to first selected track: %s (GUID: %s)\n",
            track_name, track_guid))
        end
      else
        if gui.debug then
          r.ShowConsoleMsg("[AudioSweet] No track selected\n")
        end
      end
    end

    ImGui.Spacing(ctx)
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'OK', 100, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Cancel', 100, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end

  -- Preview Settings Popup
  if gui.show_preview_settings then
    -- Position popup near mouse cursor
    local mouse_x, mouse_y = r.GetMousePosition()
    ImGui.SetNextWindowPos(ctx, mouse_x, mouse_y, ImGui.Cond_Appearing)
    ImGui.OpenPopup(ctx, 'Preview Settings')
    gui.show_preview_settings = false
  end

  if ImGui.BeginPopupModal(ctx, 'Preview Settings', true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- ESC key handling for popup (only when popup is focused)
    if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.Text(ctx, "Target Track Name:")
    ImGui.SetNextItemWidth(ctx, 200)
    local rv, new_name = ImGui.InputText(ctx, "##preview_target", gui.preview_target_track)
    if rv then
      gui.preview_target_track = new_name
      save_gui_settings()
    end
    ImGui.TextWrapped(ctx, "The track where preview will be applied")

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Solo Scope:")
    local changed_scope = false
    if ImGui.RadioButton(ctx, "Track Solo (40281)", gui.preview_solo_scope == 0) then
      gui.preview_solo_scope = 0
      changed_scope = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Item Solo (41561)", gui.preview_solo_scope == 1) then
      gui.preview_solo_scope = 1
      changed_scope = true
    end
    if changed_scope then
      save_gui_settings()
    end

    -- Warning for Item Solo lag
    if gui.preview_solo_scope == 1 then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFAA00FF)  -- Orange color
      ImGui.TextWrapped(ctx, "Note: Item Solo may have a slight lag when toggling, not as responsive as Track Solo.")
      ImGui.PopStyleColor(ctx)
    end

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Restore Mode:")
    local changed_restore = false
    if ImGui.RadioButton(ctx, "Time Selection", gui.preview_restore_mode == 0) then
      gui.preview_restore_mode = 0
      changed_restore = true
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "GUID", gui.preview_restore_mode == 1) then
      gui.preview_restore_mode = 1
      changed_restore = true
    end
    if changed_restore then
      save_gui_settings()
    end

    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Close', 120, 0) then
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.EndPopup(ctx)
  end
  
  draw_tc_embed_settings_popup()
  draw_bwfmetaedit_install_modal()

  -- Main content with compact layout
  local has_valid_fx = update_focused_fx_display()
  local effective_mode = get_effective_mode()
  local item_count = r.CountSelectedMediaItems(0)

  -- === MODE & ACTION (Radio buttons, horizontal) ===
  ImGui.Text(ctx, "Mode:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Auto", gui.mode == 2) then
    gui.mode = 2
    save_gui_settings()
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Auto: Detect chain vs single FX by window state")
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Single", gui.mode == 0) then
    gui.mode = 0
    save_gui_settings()
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Single: Process the focused FX only (floating window)")
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Chain", gui.mode == 1) then
    gui.mode = 1
    save_gui_settings()
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Chain: Process the entire FX chain")
  end

  ImGui.SameLine(ctx, 0, 50)
  ImGui.Text(ctx, "Action:")
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Apply", gui.action == 0) then
    gui.action = 0
    save_gui_settings()
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Copy", gui.action == 1) then
    gui.action = 1
    save_gui_settings()
  end
  ImGui.SameLine(ctx)
  if ImGui.RadioButton(ctx, "Copy+Apply", gui.action == 2) then
    gui.action = 2
    save_gui_settings()
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Copy FX to active take, then render (keeps old take FX)\nNote: copied FX IO mapping may be incorrect; use FX parameters for sound. TODO: improve IO mapping.")
  end

  -- === COPY SETTINGS (Compact horizontal) ===
  if gui.action == 1 then
    ImGui.Text(ctx, "Copy to:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Active##scope", gui.copy_scope == 0) then
      gui.copy_scope = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "All Takes##scope", gui.copy_scope == 1) then
      gui.copy_scope = 1
      save_gui_settings()
    end
    ImGui.SameLine(ctx, 0, 20)
    if ImGui.RadioButton(ctx, "Tail##pos", gui.copy_pos == 0) then
      gui.copy_pos = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Head##pos", gui.copy_pos == 1) then
      gui.copy_pos = 1
      save_gui_settings()
    end
  end
  if gui.action == 0 or gui.action == 2 then
    -- === ROW 1: Channel Mode (left) + Preview Target (right) ===
    ImGui.Text(ctx, "Channel:")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Auto##channel", gui.channel_mode == 0) then
      gui.channel_mode = 0
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Mono##channel", gui.channel_mode == 1) then
      gui.channel_mode = 1
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "Multi##channel", gui.channel_mode == 2) then
      gui.channel_mode = 2
      save_gui_settings()
    end
    if ImGui.IsItemHovered(ctx) then
      local policy_names = {source_playback = "playback", source_track = "track", target_track = "target"}
      local policy_name = policy_names[gui.multi_channel_policy] or gui.multi_channel_policy
      ImGui.SetTooltip(ctx, "Multi-channel mode (policy: " .. policy_name .. ")")
    end

    -- Preview Target (right side of row 1)
    if gui.mode ~= 0 then
      ImGui.SameLine(ctx, 0, 120)
      ImGui.Text(ctx, "Preview:")
      ImGui.SameLine(ctx)
      local display_name = (gui.preview_target_track ~= "") and gui.preview_target_track or "(not set)"
      if ImGui.Button(ctx, display_name .. "##target_track_btn", 120, 0) then
        gui.show_target_track_popup = true
      end
    end

    -- === ROW 2: Policy (left) + Whole File (right) ===
    ImGui.Text(ctx, "  ")
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "playback##policy", gui.multi_channel_policy == "source_playback") then
      gui.multi_channel_policy = "source_playback"
      save_gui_settings()
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Match item playback channels\nExample: 8ch file playing as 4ch \xe2\x86\x92 uses 4ch")
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "track##policy", gui.multi_channel_policy == "source_track") then
      gui.multi_channel_policy = "source_track"
      save_gui_settings()
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Match source track channels\nExample: Item on 8ch track \xe2\x86\x92 uses 8ch")
    end
    ImGui.SameLine(ctx)
    if ImGui.RadioButton(ctx, "target##policy", gui.multi_channel_policy == "target_track") then
      gui.multi_channel_policy = "target_track"
      save_gui_settings()
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Keep FX track channels as-is\nExample: FX track is 16ch \xe2\x86\x92 keeps 16ch")
    end

    -- Whole File + handle input (right side of row 2)
    ImGui.SameLine(ctx, 0, 20)
    local rv_whole = ImGui.Checkbox(ctx, "Whole File", gui.use_whole_file)
    if rv_whole then
      gui.use_whole_file = not gui.use_whole_file
      save_gui_settings()
    end
    ImGui.SameLine(ctx)
    if gui.use_whole_file then
      ImGui.BeginDisabled(ctx)
    end
    ImGui.SetNextItemWidth(ctx, 85)
    local rv, new_val = ImGui.InputDouble(ctx, "##handle_seconds", gui.handle_seconds, 0.5, 1.0, "%.1f")
    if rv then
      gui.handle_seconds = math.max(0, new_val)
      save_gui_settings()
    end
    if gui.use_whole_file then
      ImGui.EndDisabled(ctx)
    end
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, "Tail")
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "FX tail capture: extends item into silence after the right handle\nCaptures reverb/delay/echo decay\n0 = off")
    end
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 85)
    local rv_tail, new_tail = ImGui.InputDouble(ctx, "##tail_seconds", gui.tail_seconds, 0.5, 1.0, "%.1f")
    if rv_tail then
      gui.tail_seconds = math.max(0, new_tail)
      save_gui_settings()
    end
  end

  ImGui.Separator(ctx)

  -- === RUN BUTTONS: PREVIEW / SOLO / AUDIOSWEET ===
  local can_run
  if effective_mode == "focused" then
    can_run = has_valid_fx and item_count > 0 and not gui.is_running
  else
    can_run = item_count > 0 and not gui.is_running
  end

  -- Calculate button widths (3 buttons with spacing)
  local avail_width = ImGui.GetContentRegionAvail(ctx)
  local spacing = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
  local button_width = (avail_width - spacing * 2) / 3

  -- PREVIEW button (toggle: preview/stop)
  -- Check if transport is playing (includes previews started by Tools scripts)
  local play_state = r.GetPlayState()
  local is_playing = (play_state & 1 ~= 0)  -- bit 1 = playing
  local is_previewing_now = gui.is_previewing or is_playing

  -- Preview can run if:
  -- - Focused mode: has valid focused FX + has items + not running
  -- - Chain mode: has items + not running (no focused FX required, uses target track)
  -- - Already previewing/playing: always enabled to allow stopping
  local preview_can_run
  if is_previewing_now then
    preview_can_run = true  -- Always allow stopping
  elseif effective_mode == "focused" then
    -- Focused mode: requires valid FX
    preview_can_run = has_valid_fx and item_count > 0 and not gui.is_running
  else
    -- Chain mode: only requires items (uses target track)
    preview_can_run = item_count > 0 and not gui.is_running
  end

  if not preview_can_run then ImGui.BeginDisabled(ctx) end

  -- Change button color if previewing
  if is_previewing_now then
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xFF6600FF)  -- Orange when previewing
  end

  local button_label = is_previewing_now and "STOP" or "PREVIEW"
  if ImGui.Button(ctx, button_label, button_width, 35) then
    if is_previewing_now then
      -- Use OnStopButton instead of Main_OnCommand for better compatibility
      r.OnStopButton()
      gui.is_previewing = false
      if gui.debug then
        r.ShowConsoleMsg("[AS GUI] STOP button pressed (OnStopButton)\n")
      end
    else
      toggle_preview()
    end
  end

  if is_previewing_now then
    ImGui.PopStyleColor(ctx)
  end
  if not preview_can_run then ImGui.EndDisabled(ctx) end

  ImGui.SameLine(ctx)

  -- SOLO button (always enabled)
  if ImGui.Button(ctx, "SOLO", button_width, 35) then
    toggle_solo()
  end

  ImGui.SameLine(ctx)

  -- AUDIOSWEET button
  if not can_run then ImGui.BeginDisabled(ctx) end
  if ImGui.Button(ctx, "AUDIOSWEET", button_width, 35) then
    run_audiosweet(nil)
  end
  if not can_run then ImGui.EndDisabled(ctx) end

  ImGui.Separator(ctx)

  -- === SAVE BUTTON (above Saved/History) ===
  if gui.enable_saved_chains then
    -- Unified Save button that changes text based on mode
    local save_button_label = (effective_mode == "chain") and "Save This Chain" or "Save This FX"
    local save_button_enabled = (effective_mode == "chain" and #gui.focused_track_fx_list > 0) or (effective_mode == "focused" and has_valid_fx)

    if not save_button_enabled then ImGui.BeginDisabled(ctx) end
    if ImGui.Button(ctx, save_button_label, -1, 0) then
      -- Unified save popup - we'll use one popup for both
      gui.show_save_popup = true
      if effective_mode == "chain" then
        -- Extract only track name without "#N - " prefix
        local track_name, _ = get_track_name_and_number(gui.focused_track)
        gui.new_chain_name = track_name
        gui.new_chain_name_default = track_name  -- Store default
      else
        gui.new_chain_name = gui.focused_fx_name
        gui.new_chain_name_default = gui.focused_fx_name  -- Store default
      end
    end
    if not save_button_enabled then ImGui.EndDisabled(ctx) end
  end

  -- === QUICK PROCESS (Saved + History, side by side) ===
  if gui.enable_saved_chains or gui.enable_history then
    local changed
    local line_y = ImGui.GetCursorPosY(ctx)
    local left_x = ImGui.GetCursorPosX(ctx)
    local avail = ImGui.GetContentRegionAvail(ctx)
    local right_edge = left_x + avail
    local cb_frame_h = ImGui.GetFrameHeight(ctx)
    local inner_x = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemInnerSpacing)
    local inner_spacing_x = type(inner_x) == "table" and (inner_x[1] or 0) or inner_x
    local function cb_width(label)
      return cb_frame_h + inner_spacing_x + ImGui.CalcTextSize(ctx, label)
    end
    local recall_label = "Show FX window on recall"
    local history_label = "Show History"
    local recall_w = cb_width(recall_label)
    local history_w = cb_width(history_label)

    -- Show Presets (left)
    changed, gui.show_presets = ImGui.Checkbox(ctx, "Show Presets", gui.show_presets)
    if changed then save_gui_settings() end

    -- Show FX window on recall (center)
    ImGui.SetCursorPosY(ctx, line_y)
    ImGui.SetCursorPosX(ctx, left_x + (avail - recall_w) * 0.5)
    changed, gui.show_fx_on_recall = ImGui.Checkbox(ctx, recall_label, gui.show_fx_on_recall)
    if changed then save_gui_settings() end

    -- Show History (right)
    ImGui.SetCursorPosY(ctx, line_y)
    ImGui.SetCursorPosX(ctx, right_edge - history_w)
    changed, gui.show_history = ImGui.Checkbox(ctx, history_label, gui.show_history)
    if changed then save_gui_settings() end

    if gui.show_presets or gui.show_history then

      -- Only show if at least one feature is enabled, has content, and is set to show
      if (gui.enable_saved_chains and gui.show_presets) or (gui.enable_history and gui.show_history) then
        local avail_w = ImGui.GetContentRegionAvail(ctx)
        local presets_visible = gui.enable_saved_chains and gui.show_presets
        local history_visible = gui.enable_history and gui.show_history
        local col1_w = (presets_visible and history_visible) and (avail_w * 0.5 - 5) or 0

        local function calc_list_height(item_count)
          local _, spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
          local frame_h = ImGui.GetFrameHeight(ctx)
          local text_h = ImGui.GetTextLineHeight(ctx)
          local header_line_h = math.max(frame_h, text_h)
          local separator_h = 1
          local header_height = header_line_h + spacing_y + separator_h + spacing_y
          local items_height = item_count * frame_h + math.max(0, item_count - 1) * spacing_y
          return math.min(header_height + items_height, 200)
        end

        -- Left: Saved FX Preset
        if presets_visible then
          local saved_height = calc_list_height(math.max(#gui.saved_chains, 1))
          if ImGui.BeginChild(ctx, "SavedCol", col1_w, saved_height) then
            ImGui.Text(ctx, "SAVED PRESET")
            ImGui.SameLine(ctx)
            if ImGui.SmallButton(ctx, "Load Track FX") then
              load_preset_from_selected_or_named_track()
            end
            if ImGui.IsItemHovered(ctx) then
              ImGui.BeginTooltip(ctx)
              ImGui.Text(ctx, "Load selected track FX as single-FX presets")
              ImGui.EndTooltip(ctx)
            end
            ImGui.SameLine(ctx)
            if ImGui.SmallButton(ctx, "Load Chain") then
              load_chain_presets_from_selected_tracks()
            end
            if ImGui.IsItemHovered(ctx) then
              ImGui.BeginTooltip(ctx)
              ImGui.Text(ctx, "Load selected FX chain tracks")
              ImGui.EndTooltip(ctx)
            end
            ImGui.Separator(ctx)
            if #gui.saved_chains == 0 then
              ImGui.TextDisabled(ctx, "No presets yet")
            else
              local to_delete = nil
              local drag_src_idx, drag_dst_idx
              for i, chain in ipairs(gui.saved_chains) do
              ImGui.PushID(ctx, i)

              -- Get display info
              local display_name, track_info_line, fx_info, saved_fx_index = get_chain_display_info(chain)

              -- Drag handle
              ImGui.SmallButton(ctx, "=")
              if ImGui.BeginDragDropSource(ctx) then
                ImGui.SetDragDropPayload(ctx, "AS_PRESET_REORDER", tostring(i))
                ImGui.Text(ctx, display_name)
                ImGui.EndDragDropSource(ctx)
              end
              if ImGui.BeginDragDropTarget(ctx) then
                local accepted, payload = ImGui.AcceptDragDropPayload(ctx, "AS_PRESET_REORDER")
                if accepted then
                  drag_src_idx = tonumber(payload)
                  drag_dst_idx = i
                end
                ImGui.EndDragDropTarget(ctx)
              end
              ImGui.SameLine(ctx)

              -- "Open" button (small, on the left)
              if ImGui.SmallButton(ctx, "Open") then
                open_saved_chain_fx(i)
              end
              ImGui.SameLine(ctx)

              -- Chain name button (executes AudioSweet) - use available width minus Delete button
              local avail_width = ImGui.GetContentRegionAvail(ctx) - 25  -- Space for "X" button
              if ImGui.Button(ctx, display_name, avail_width, 0) then
                run_saved_chain(i)
              end

              -- Hover tooltip showing track and FX info
              if ImGui.IsItemHovered(ctx) then
                show_preset_tooltip(chain)
              end

              -- Right-click context menu for renaming
              if ImGui.BeginPopupContextItem(ctx, "chain_context_" .. i) then
                if ImGui.MenuItem(ctx, "Rename") then
                  gui.show_rename_popup = true
                  gui.rename_chain_idx = i
                  gui.rename_is_history = false  -- Mark as preset rename
                  -- Pre-fill with current custom name, or use core name only (for focused mode)
                  if chain.custom_name and chain.custom_name ~= "" then
                    gui.rename_chain_name = chain.custom_name
                  else
                    -- Use the base name without track# prefix
                    if chain.mode == "focused" then
                      -- For focused mode: use CORE name only (no type/vendor)
                      -- This preserves type and vendor info in the original chain.name
                      local tr = find_track_by_guid(chain.track_guid)
                      local found_fx_name = nil
                      if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
                        if chain.fx_index then
                          local fx_count = r.TrackFX_GetCount(tr)
                          if chain.fx_index < fx_count then
                            local _, fx_name = r.TrackFX_GetFXName(tr, chain.fx_index, "")
                            if fx_name and (fx_name == chain.name or fx_name:find(chain.name, 1, true)) then
                              found_fx_name = fx_name
                            end
                          end
                        end
                      end
                      -- Extract only core name (no type, no vendor)
                      gui.rename_chain_name = get_fx_core_name(found_fx_name or chain.name)
                    else
                      -- For chain mode, extract track name from track_info_line (#N: name)
                      local extracted_name = track_info_line:match("^#%d+: (.+)$")
                      gui.rename_chain_name = extracted_name or chain.track_name or ""
                    end
                  end
                end
                ImGui.EndPopup(ctx)
              end

              ImGui.SameLine(ctx)
              -- Delete button
              if ImGui.Button(ctx, "X", 20, 0) then
                to_delete = i
              end
              ImGui.PopID(ctx)
            end
              if to_delete then
                delete_saved_chain(to_delete)
              elseif drag_src_idx and drag_dst_idx and drag_src_idx ~= drag_dst_idx then
                local entry = table.remove(gui.saved_chains, drag_src_idx)
                table.insert(gui.saved_chains, drag_dst_idx, entry)
                save_chains_to_extstate()
              end
            end
            ImGui.EndChild(ctx)
          end

          if history_visible then ImGui.SameLine(ctx) end
        end

        -- Right: History (auto-resizes based on content)
        if history_visible then
          -- Calculate height based on number of history items (each item ~25px, header ~40px)
          local history_height = calc_list_height(#gui.history)
          if ImGui.BeginChild(ctx, "HistoryCol", 0, history_height) then
            ImGui.Text(ctx, "HISTORY")
            ImGui.SameLine(ctx)
            ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + ImGui.GetContentRegionAvail(ctx) - 45)
            if ImGui.SmallButton(ctx, "Clear") then
              gui.history = {}
              -- Clear from ProjExtState
              for i = 0, gui.max_history - 1 do
                r.SetProjExtState(0, HISTORY_NAMESPACE, "hist_" .. i, "")
              end
            end
            ImGui.Separator(ctx)
            for i, item in ipairs(gui.history) do
              ImGui.PushID(ctx, 1000 + i)
              -- "Open" button (small, on the left)
              if ImGui.SmallButton(ctx, "Open") then
                open_history_fx(i)
              end
              ImGui.SameLine(ctx)
              -- History item name button (executes AudioSweet) - use available width minus Save button
              local avail_width = ImGui.GetContentRegionAvail(ctx) - 45  -- Space for "Save" button
              local display_name = get_history_display_name(item)
              if ImGui.Button(ctx, display_name, avail_width, 0) then
                run_history_item(i)
              end

              -- Hover tooltip showing track and FX info
              if ImGui.IsItemHovered(ctx) then
                show_preset_tooltip(item)
              end

              -- Right-click context menu for renaming
              if ImGui.BeginPopupContextItem(ctx, "history_context_" .. i) then
                if ImGui.MenuItem(ctx, "Rename") then
                  gui.show_rename_popup = true
                  gui.rename_chain_idx = i
                  gui.rename_is_history = true  -- Mark as history rename
                  -- Pre-fill with current custom name, or use core name only (for focused mode)
                  if item.custom_name and item.custom_name ~= "" then
                    gui.rename_chain_name = item.custom_name
                  else
                    -- Use core name only (for focused mode, without track# prefix)
                    if item.mode == "focused" then
                      -- Extract only core name (no type, no vendor)
                      gui.rename_chain_name = get_fx_core_name(item.name)
                    else
                      -- For chain mode, extract track name
                      local tr = find_track_by_guid(item.track_guid)
                      if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
                        local _, track_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
                        gui.rename_chain_name = track_name
                      else
                        gui.rename_chain_name = item.track_name or ""
                      end
                    end
                  end
                end
                ImGui.EndPopup(ctx)
              end

              ImGui.SameLine(ctx)
              -- "Save" button to save this history item as a saved preset
              if ImGui.Button(ctx, "Save", 40, 0) then
                -- Check if this exact preset already exists in saved_chains
                local already_saved = false
                for _, chain in ipairs(gui.saved_chains) do
                  if chain.track_guid == item.track_guid and chain.mode == item.mode then
                    if item.mode == "focused" then
                      -- For focused mode: check fx_index
                      if chain.fx_index == item.fx_index then
                        already_saved = true
                        break
                      end
                    else
                      -- For chain mode: check if same chain (by name)
                      if chain.name == item.name then
                        already_saved = true
                        break
                      end
                    end
                  end
                end

                if already_saved then
                  gui.last_result = "Info: This preset is already saved"
                else
                  -- Add to saved_chains
                  add_saved_chain(item.name, item.track_guid, item.track_name, nil, item.mode, item.fx_index)
                  gui.last_result = "Success: History item saved to presets"
                end
              end

              ImGui.PopID(ctx)
            end
            ImGui.EndChild(ctx)
          end
        end
      end
    end
  else
    -- Show "Developing" message when both features are disabled
    ImGui.TextWrapped(ctx, "SAVED FX PRESET and HISTORY features are currently under development.")
    ImGui.TextWrapped(ctx, "These features are not functioning properly and will be available in a future update.")
  end

  -- === FX INFO (at bottom, auto-resizes) ===
  ImGui.Separator(ctx)

  -- === STATUS (above FX info) ===
  if gui.last_result ~= "" then
    if gui.last_result:match("^Success") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
    elseif gui.last_result:match("^Error") then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
    else
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFFFF00FF)
    end
    ImGui.TextWrapped(ctx, gui.last_result)
    ImGui.PopStyleColor(ctx)
  end

  -- STATUS BAR
  if has_valid_fx then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x00FF00FF)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
  end

  if effective_mode == "focused" then
    if has_valid_fx then
      ImGui.Text(ctx, format_fx_label_for_status(gui.focused_fx_name))
    else
      ImGui.Text(ctx, gui.focused_fx_name)
    end
  else
    ImGui.Text(ctx, gui.focused_track_name ~= "" and ("Track: " .. gui.focused_track_name) or "No Track FX")
  end
  ImGui.PopStyleColor(ctx)
  ImGui.Text(ctx, string.format("Items: %d", item_count))

  -- Show FX chain in Chain mode (dynamic height, auto-resizes based on content)
  if effective_mode == "chain" and #gui.focused_track_fx_list > 0 then
    -- Dynamic height based on FX count (each FX line ~20px), max 150px
    local line_height = 20
    local max_height = 150
    local fx_count = #gui.focused_track_fx_list
    local calculated_height = math.min(fx_count * line_height, max_height)

    if ImGui.BeginChild(ctx, "FXChainList", 0, calculated_height) then
      for _, fx in ipairs(gui.focused_track_fx_list) do
        local status = fx.offline and "[offline]" or (fx.enabled and "[on]" or "[byp]")
        local formatted_name = format_fx_label(fx.name, "fxlist")
        ImGui.Text(ctx, string.format("%02d) %s %s", fx.index + 1, formatted_name, status))
      end
      ImGui.EndChild(ctx)
    end
  end

  ImGui.End(ctx)

  -- === SAVE PRESET POPUP (Unified for both Chain and Focused modes) ===
  if gui.show_save_popup then
    -- Position popup near main window
    local main_x, main_y = ImGui.GetWindowPos(ctx)
    local main_w, main_h = ImGui.GetWindowSize(ctx)
    ImGui.SetNextWindowPos(ctx, main_x + main_w / 2, main_y + 50, ImGui.Cond_Appearing, 0.5, 0)
    ImGui.OpenPopup(ctx, "Save FX Preset")
    gui.show_save_popup = false
  end

  if ImGui.BeginPopupModal(ctx, "Save FX Preset", true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- Show track# prefix for chain mode (outside input field)
    if effective_mode == "chain" and gui.focused_track then
      local track_number = r.GetMediaTrackInfo_Value(gui.focused_track, "IP_TRACKNUMBER")
      ImGui.Text(ctx, string.format("Track #%d - Preset Name:", track_number))
    else
      ImGui.Text(ctx, "Preset Name:")
    end
    ImGui.TextDisabled(ctx, "(leave empty to use default)")
    ImGui.Spacing(ctx)

    local rv, new_name = ImGui.InputText(ctx, "##presetname", gui.new_chain_name, 256)
    if rv then gui.new_chain_name = new_name end

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Save", 100, 0) or ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) then
      if gui.focused_track then
        local user_input = gui.new_chain_name
        local default_value = gui.new_chain_name_default

        -- Determine final_name and custom_name
        local final_name
        local custom_name = nil

        if user_input == "" then
          -- User cleared the field → use default name, no custom name
          final_name = default_value
          custom_name = nil
        elseif user_input == default_value then
          -- User kept default value → use default name, no custom name
          final_name = default_value
          custom_name = nil
        else
          -- User modified the name → use user's input as both final_name and custom_name
          final_name = user_input
          custom_name = user_input
        end

        -- Check for duplicates
        local duplicate_found = false
        local track_guid = get_track_guid(gui.focused_track)
        local mode = (effective_mode == "chain") and "chain" or "focused"
        local fx_index = (mode == "focused") and gui.focused_fx_index or nil

        -- For focused mode: get the ORIGINAL FX name from track (not processed by FX name settings)
        local original_fx_name = nil
        if mode == "focused" and fx_index ~= nil then
          local _, raw_fx_name = r.TrackFX_GetFXName(gui.focused_track, fx_index, "")
          original_fx_name = raw_fx_name
        end

        -- For chain mode: get current FX chain content for comparison
        local current_fx_list = nil
        if mode == "chain" then
          current_fx_list = get_track_fx_chain(gui.focused_track)
        end

        for _, chain in ipairs(gui.saved_chains) do
          -- For focused mode: check by track_guid + fx_index (same FX)
          -- For chain mode: check by track_guid + FX chain content (same chain regardless of name)
          if mode == "focused" and chain.mode == "focused" then
            if chain.track_guid == track_guid and chain.fx_index == fx_index then
              duplicate_found = true
              break
            end
          elseif mode == "chain" and chain.mode == "chain" then
            -- Compare FX chain content instead of name
            if chain.track_guid == track_guid then
              local saved_track = find_track_by_guid(chain.track_guid)
              if saved_track then
                local saved_fx_list = get_track_fx_chain(saved_track)
                -- Compare FX counts first
                if #saved_fx_list == #current_fx_list then
                  local chains_match = true
                  for i = 1, #saved_fx_list do
                    if saved_fx_list[i].name ~= current_fx_list[i].name then
                      chains_match = false
                      break
                    end
                  end
                  if chains_match then
                    duplicate_found = true
                    break
                  end
                end
              end
            end
          end
        end

        if duplicate_found then
          gui.last_result = "Error: This FX preset already exists"
        else
          -- For focused mode: use original FX name (with VST3:/CLAP: prefix) for internal storage
          -- For chain mode: use final_name (track name)
          local storage_name = (mode == "focused" and original_fx_name) or final_name
          add_saved_chain(storage_name, track_guid, gui.focused_track_name, custom_name, mode, fx_index)
          gui.last_result = "Success: Preset saved"
          gui.new_chain_name = ""
          gui.new_chain_name_default = ""
          ImGui.CloseCurrentPopup(ctx)
        end
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 100, 0) or ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      gui.new_chain_name = ""
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  -- === RENAME CHAIN POPUP ===
  if gui.show_rename_popup then
    -- Position popup near main window
    local main_x, main_y = ImGui.GetWindowPos(ctx)
    local main_w, main_h = ImGui.GetWindowSize(ctx)
    ImGui.SetNextWindowPos(ctx, main_x + main_w / 2, main_y + 50, ImGui.Cond_Appearing, 0.5, 0)
    ImGui.OpenPopup(ctx, "Rename Preset")
    gui.show_rename_popup = false
  end

  if ImGui.BeginPopupModal(ctx, "Rename Preset", true, ImGui.WindowFlags_AlwaysAutoResize) then
    -- Show track# prefix for chain mode (outside input field)
    local hint_text = "(leave empty to use default)"
    local item_source = gui.rename_is_history and gui.history or gui.saved_chains

    if gui.rename_chain_idx and item_source[gui.rename_chain_idx] then
      local item = item_source[gui.rename_chain_idx]
      if item.mode == "chain" then
        local tr = find_track_by_guid(item.track_guid)
        if tr then
          local track_number = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")
          ImGui.Text(ctx, string.format("Track #%d - %s Name:", track_number, gui.rename_is_history and "History" or "Preset"))
          -- Show current track name in hint
          local current_track_name, _ = get_track_name_and_number(tr)
          hint_text = string.format("(default: #%.0f - %s)", track_number, current_track_name)
        else
          ImGui.Text(ctx, string.format("%s Name:", gui.rename_is_history and "History" or "Preset"))
        end
      else
        -- Focused mode: show formatted FX name in hint
        ImGui.Text(ctx, string.format("%s Name:", gui.rename_is_history and "History" or "Preset"))
        if item.name then
          -- Use formatted name for hint (consistent with button display)
          local formatted_name = format_fx_label_for_preset(item.name)
          hint_text = string.format("(default: %s)", formatted_name)
        end
      end
    else
      ImGui.Text(ctx, string.format("%s Name:", gui.rename_is_history and "History" or "Preset"))
    end
    ImGui.TextDisabled(ctx, hint_text)
    ImGui.Spacing(ctx)

    local rv, new_name = ImGui.InputText(ctx, "##renamefield", gui.rename_chain_name, 256)
    if rv then gui.rename_chain_name = new_name end

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "OK", 100, 0) then
      if gui.rename_chain_idx then
        if gui.rename_is_history then
          rename_history_item(gui.rename_chain_idx, gui.rename_chain_name)
        else
          rename_saved_chain(gui.rename_chain_idx, gui.rename_chain_name)
        end
        gui.rename_chain_idx = nil
        gui.rename_chain_name = ""
        gui.rename_is_history = false
        ImGui.CloseCurrentPopup(ctx)
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancel", 100, 0) then
      gui.rename_chain_idx = nil
      gui.rename_chain_name = ""
      gui.rename_is_history = false
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end

  return open
end

------------------------------------------------------------
-- Main Loop
------------------------------------------------------------
local function log_gui_settings(context)
  r.ShowConsoleMsg("========================================\n")
  r.ShowConsoleMsg(string.format("[AS GUI] %s - Current settings:\n", context))
  r.ShowConsoleMsg("========================================\n")
  local mode_names = {"Single", "Chain", "Auto"}
  r.ShowConsoleMsg(string.format("  Mode: %s\n", mode_names[gui.mode + 1] or "Focused"))
  r.ShowConsoleMsg(string.format("  Action: %s\n", get_action_label(gui.action)))
  r.ShowConsoleMsg(string.format("  Copy Scope: %s\n", gui.copy_scope == 0 and "Active" or "All"))
  r.ShowConsoleMsg(string.format("  Copy Position: %s\n", gui.copy_pos == 0 and "Last" or "Replace"))
  local channel_mode_names = {"Auto", "Mono", "Multi"}
  r.ShowConsoleMsg(string.format("  Channel Mode: %s\n", channel_mode_names[gui.channel_mode + 1]))
  r.ShowConsoleMsg(string.format("  Channel Policy: %s\n", gui.multi_channel_policy))
  local handle_display = gui.use_whole_file and "Whole File" or string.format("%.2f", gui.handle_seconds)
  r.ShowConsoleMsg(string.format("  Handle Seconds: %s\n", handle_display))
  r.ShowConsoleMsg(string.format("  Debug Mode: %s\n", gui.debug and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  Max History: %d\n", gui.max_history))
  r.ShowConsoleMsg(string.format("  FX Name - Show Type: %s\n", gui.fxname_show_type and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  FX Name - Show Vendor: %s\n", gui.fxname_show_vendor and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  FX Name - Strip Symbol: %s\n", gui.fxname_strip_symbol and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  FX Name - Use Alias: %s\n", gui.use_alias and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  Preset Display - Show Type: %s\n", gui.preset_display_show_type and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  Preset Display - Show Vendor: %s\n", gui.preset_display_show_vendor and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  Preset Display - Use Alias: %s\n", gui.preset_display_use_alias and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  Max FX Tokens: %d\n", gui.max_fx_tokens))
  local chain_token_source_names = {"Track Name", "FX Aliases", "FXChain"}
  r.ShowConsoleMsg(string.format("  Chain Token Source: %s\n", chain_token_source_names[gui.chain_token_source + 1]))
  if gui.chain_token_source == 1 then
    r.ShowConsoleMsg(string.format("  Chain Alias Joiner: '%s'\n", gui.chain_alias_joiner))
  end
  r.ShowConsoleMsg(string.format("  Track Name Strip Symbols: %s\n", gui.trackname_strip_symbols and "ON" or "OFF"))
  r.ShowConsoleMsg(string.format("  Preview Target Track: %s\n", gui.preview_target_track))
  local solo_scope_names = {"Track Solo", "Item Solo"}
  r.ShowConsoleMsg(string.format("  Preview Solo Scope: %s\n", solo_scope_names[gui.preview_solo_scope + 1]))
  local restore_mode_names = {"Keep", "Restore"}
  r.ShowConsoleMsg(string.format("  Preview Restore Mode: %s\n", restore_mode_names[gui.preview_restore_mode + 1]))
  r.ShowConsoleMsg("========================================\n")
end

local function loop()
  gui.open = draw_gui()
  if gui.open then
    r.defer(loop)
  else
    -- Script is closing - output final settings if debug mode is on
    if gui.debug then
      log_gui_settings("Script closing")
    end
  end
end

------------------------------------------------------------
-- Entry Point
------------------------------------------------------------
load_gui_settings()  -- Load saved GUI settings first
if gui.debug then
  log_gui_settings("Script opening")
end
check_bwfmetaedit(true)
load_saved_chains()
load_history()
r.defer(loop)
