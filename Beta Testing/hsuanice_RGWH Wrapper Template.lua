--[[
@description RGWH Wrapper Template (Public Beta)
@author hsuanice
@version 251013_1200
@about
  Thin wrapper for calling RGWH Core via a single entry `RGWH.core(args)`.
  Use this as a starting point to test and ship wrappers that render/glue with handles.

@usage
  1) Adjust the USER CONFIG block below.
  2) Run this script in REAPER. It will call RGWH.core(args) with one-run overrides.
  3) All non-specified options keep the project's ExtState defaults (then DEFAULTS).

@notes
  - op:
      "render" : always single-item (selection_scope is ignored).
      "glue"   : uses selection_scope ("units" | "ts" | "item" | "auto").
      "auto"   : if single item AND GLUE_SINGLE_ITEMS=false => render; else glue(auto scope).
  - selection_scope (for glue/auto):
      "auto"  : TS empty or ≈ selection span => Units; otherwise => TS window.
      "units" : glue by Item Units (same-track grouping).
      "ts"    : glue strictly by the current Time Selection window (never render).
      "item"  : glue per item (SINGLE respects GLUE_SINGLE_ITEMS).
  - channel_mode maps to GLUE/RENDER_APPLY_MODE: "auto" | "mono" | "multi".
  - handle/epsilon/cues/policies/debug: one-run overrides; omit or use "ext" to read ExtState as-is.

@changelog
  v251013_1200  Initial public template wrapper.
]]--

------------------------------------------------------------
-- Resolve RGWH Core
------------------------------------------------------------
local r = reaper
local RES_PATH = r.GetResourcePath()
local CORE_PATH = RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua'

local ok_load, RGWH = pcall(dofile, CORE_PATH)
if not ok_load or type(RGWH) ~= "table" or type(RGWH.core) ~= "function" then
  r.ShowConsoleMsg(("[RGWH WRAPPER] Failed to load Core at:\n  %s\nError: %s\n")
    :format(CORE_PATH, tostring(RGWH)))
  return
end

------------------------------------------------------------
-- QUICK DEBUG SWITCH (one-line toggle)
--   "silent"      → level=0,  no_clear=true
--   "normal"      → level=1,  no_clear=false
--   "verbose"     → level=2,  no_clear=true
--   "use-detailed"→ keep the detailed args.debug settings below
------------------------------------------------------------
local QUICK_DEBUG = "verbose"  -- change to: "silent" | "normal" | "verbose" | "use-detailed"

local function apply_quick_debug(quick, detailed)
  if quick == "silent"  then return { level = 0, no_clear = true  } end
  if quick == "normal"  then return { level = 1, no_clear = false } end
  if quick == "verbose" then return { level = 2, no_clear = true  } end
  return detailed
end


------------------------------------------------------------
-- USER CONFIG (edit here)
------------------------------------------------------------
-- Quick presets (uncomment ONE block or set manually below):
-- [AUTO scope with one-run defaults from ExtState]
-- local _PRESET = { op="auto", selection_scope="auto", channel_mode="auto" }

-- [Force Units glue]
-- local _PRESET = { op="glue", selection_scope="units", channel_mode="auto" }

-- [Force TS-Window glue]
-- local _PRESET = { op="glue", selection_scope="ts", channel_mode="auto" }

-- [Single-item Render]
-- local _PRESET = { op="render", channel_mode="auto", take_fx=true, track_fx=false, tc_mode="previous" }

-- If you didn’t choose a preset, configure manually here:
local args = (_PRESET) or {
  -- Core operation
  op              = "glue",        -- "auto" | "render" | "glue"
  selection_scope = "ts",        -- "auto" | "units" | "ts" | "item"  (ignored when op="render")
  channel_mode    = "auto",        -- "auto" | "mono" | "multi"

  -- Render toggles (only effective when op resolves to render)
  take_fx  = false,                 -- bake take FX on render
  track_fx = true,                 -- bake track FX on render
  tc_mode  = "current",           -- "previous" | "current" | "off" (BWF TimeReference embed)

  -- One-run overrides (simple knobs)
  -- Handle: choose how to interpret length; wrapper will convert to Core format
  handle_mode   = "seconds",     -- "ext" | "seconds" | "frames"
  handle_length = 5.0,       -- value; if "frames", wrapper converts to seconds using project FPS

  -- Epsilon: native support for frames/seconds in Core
  epsilon_mode  = "frames",  -- "ext" | "frames" | "seconds"
  epsilon_value = 0.5,       -- threshold value in selected unit

  cues = {
    write_edge = true,             -- #in/#out edge cues as media cues
    write_glue = true,             -- #Glue: <TakeName> cues inside glued media when sources change
  },

  policies = {
    glue_single_items = true,     -- in op="auto": single item => render (if false)
    glue_no_trackfx_output_policy   = "preserve",   -- "preserve" | "force_multi"
    render_no_trackfx_output_policy = "preserve",   -- "preserve" | "force_multi"
    rename_mode = "auto",          -- "auto" | "glue" | "render" (kept for compatibility)
  },

}

------------------------------------------------------------
-- Build handle/epsilon objects for Core from simple knobs
------------------------------------------------------------
local function resolve_handle_from_knobs(a)
  local mode = (a.handle_mode or "ext")
  if mode == "ext" then return "ext" end
  local len = tonumber(a.handle_length) or 0
  if mode == "seconds" then
    return { mode = "seconds", seconds = len }
  elseif mode == "frames" then
    local fps = reaper.TimeMap_curFrameRate(0) or 30
    -- Core expects seconds for handle; convert frames → seconds
    return { mode = "seconds", seconds = (len / fps) }
  else
    return "ext"
  end
end

local function resolve_epsilon_from_knobs(a)
  local mode = (a.epsilon_mode or "ext")
  if mode == "ext" then return "ext" end
  local val = tonumber(a.epsilon_value) or 0
  if mode == "frames" then
    return { mode = "frames",  value = val }
  elseif mode == "seconds" then
    return { mode = "seconds", value = val }
  else
    return "ext"
  end
end

-- apply conversions
args.handle  = resolve_handle_from_knobs(args)
args.epsilon = resolve_epsilon_from_knobs(args)

------------------------------------------------------------
-- RUN
------------------------------------------------------------
local ok_run, err = RGWH.core(args)
if not ok_run then
  r.ShowConsoleMsg(("[RGWH WRAPPER] error: %s\n"):format(tostring(err)))
end