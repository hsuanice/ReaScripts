--[[
@description RGWH Core ExtState Set (project-scope)
@version 2510041439 Add CFG.DEBUG_NO_CLEAR (default false) to control console clearing
@author hsuanice
@about
  Quick setup for RGWH Core ExtStates (written into current project).
  Includes defaults for handles, epsilon, FX print policies, cue writing,
  rename options, multi-mode output policy switches, and TC embed mode.

@changelog
  v2510041439 Add CFG.DEBUG_NO_CLEAR (default false) to control console clearing
    - New ExtState key `DEBUG_NO_CLEAR` (boolean, default false) to control whether console is cleared at start of Glue/Render operations.
    - When true, console retains previous logs for easier debugging across multiple runs.
    - When false (default), console is cleared as before.
    - No changes to other functionalities or settings.
    - Note: This setting is independent of DEBUG_LEVEL and only affects console clearing behavior.

  v250925_1130
    - Added: RENDER_TC_EMBED ("previous" | "current" | "off"), default "previous".
             Controls TimeReference embedding behavior in Core after Render/Apply FX.
    - Renamed: output policy token "force-multi" -> "force_multi" for consistency.
    - Console: now prints RENDER_TC_EMBED along with other settings.
v250925_1101 change "force_multi" to "force_multi"
v250925_1042
  - Added: RENDER_TC_EMBED = "previous" | "current"
    • "previous" (default): embed TimeReference from the previous/original take
    • "current"           : embed TimeReference derived from current item position
  - Printed in console summary alongside other render/glue options.

v250922_2257
  - Added: GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX and RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX
    • Options: "preserve" (keep source mono/stereo) or "force_multi" (always run 41993 multichannel path)
  - Updated: Console display shows both policies explicitly when ExtState is written
  - Synced with Core v250922_2257 (multi-mode OK)

v250922_1750
  - Previous stable ExtState writer
  - Sets HANDLE, EPSILON, DEBUG_LEVEL, FX modes, cue writing options
]]--

local r = reaper
local NS = "RGWH" -- namespace

-- Edit what you want here
local CFG = {
  GLUE_SINGLE_ITEMS = 1,

  HANDLE_MODE       = "seconds",
  HANDLE_SECONDS    = 5,

  EPSILON_MODE      = "frames",
  EPSILON_VALUE     = 0.5,

  DEBUG_LEVEL       = 2,

  -- Console: do not ClearConsole() inside Core when set to 1
  DEBUG_NO_CLEAR    = 1,

  -- GLUE
  GLUE_TAKE_FX      = 1,
  GLUE_TRACK_FX     = 0,
  GLUE_APPLY_MODE   = "mono",   -- "mono" | "multi"

  -- RENDER
  RENDER_TAKE_FX    = 0,
  RENDER_TRACK_FX   = 0,
  RENDER_APPLY_MODE = "mono",   -- "mono" | "multi" | "off"

  -- New: Render TC embed mode (2-choice)
  --   "previous" (default): embed TimeReference from previous/original take
  --   "current"           : embed TimeReference from current item start position
  RENDER_TC_EMBED = "current", -- "previous" | "current" | "off"

  RENAME_OP_MODE    = "auto",

  -- CUE switches
  WRITE_EDGE_CUES   = 1,
  WRITE_GLUE_CUES   = 1,

  -- Output policy when NOT printing Track FX
  GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX   = "preserve",   -- "preserve" | "force_multi"
  RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve",   -- "preserve" | "force_multi"
}

local function set(k, v) r.SetProjExtState(0, NS, k, tostring(v)) end

r.Undo_BeginBlock()
for k, v in pairs(CFG) do set(k, v) end
r.Undo_EndBlock("RGWH Core - Set ExtState", -1)

-- Show current settings
r.ShowConsoleMsg(string.format(
  "[RGWH] ExtState updated (project) — namespace=%s\n"..
  "GLUE_SINGLE_ITEMS=%s\nHANDLE_MODE=%s\nHANDLE_SECONDS=%s\n"..
  "EPSILON_MODE=%s\nEPSILON_VALUE=%s\nDEBUG_LEVEL=%s\n"..
  "DEBUG_NO_CLEAR=%s\n"..
  "GLUE_TAKE_FX=%s\nGLUE_TRACK_FX=%s\nGLUE_APPLY_MODE=%s\n"..
  "RENDER_TAKE_FX=%s\nRENDER_TRACK_FX=%s\nRENDER_APPLY_MODE=%s\n"..
  "RENDER_TC_EMBED=%s\n"..
  "RENAME_OP_MODE=%s\nWRITE_EDGE_CUES=%s\nWRITE_GLUE_CUES=%s\n"..
  "GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX=%s\nRENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX=%s\n",
  NS,
  CFG.GLUE_SINGLE_ITEMS, CFG.HANDLE_MODE, CFG.HANDLE_SECONDS,
  CFG.EPSILON_MODE, CFG.EPSILON_VALUE, CFG.DEBUG_LEVEL,
  CFG.DEBUG_NO_CLEAR,
  CFG.GLUE_TAKE_FX, CFG.GLUE_TRACK_FX, CFG.GLUE_APPLY_MODE,
  CFG.RENDER_TAKE_FX, CFG.RENDER_TRACK_FX, CFG.RENDER_APPLY_MODE,
  CFG.RENDER_TC_EMBED,
  CFG.RENAME_OP_MODE, CFG.WRITE_EDGE_CUES, CFG.WRITE_GLUE_CUES,
  CFG.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX, CFG.RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX
))
