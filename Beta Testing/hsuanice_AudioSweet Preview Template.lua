--[[
@description AudioSweet Preview Template
@author Hsuanice
@changelog
  v251010_2152 (Core: hsuanice_AS Preview Core.lua)
    - Added: Convenience arg `target_track_name` for ASP.preview(); equivalent to `target={by="name", value="<name>"}`.
    - Added: Default target fallback "AudioSweet" when neither `target` nor `target_track_name` is provided.
    - Docs: Updated args comment to include `target_track_name`.
    - Behavior: Non-breaking; sugar only applies when `args.target` is nil.

  v251010_1800 (Template: hsuanice_AudioSweet Preview Template.lua)
    - Clean: Reorganized into clear sections (Load Core / Utility / Target / Params / Run).
    - Option: Console logging now guarded by `args.debug` (no output when false).
    - Note: Current template still uses manual name lookup and `focus_track`; can migrate to `target_track_name` sugar later.
]]--

--========================================
-- AudioSweet Preview Template
--========================================
-- This template calls the AudioSweet Core preview function
-- with a track target specified by name.
-- Organized by logical section for clarity.
--========================================

------------------------------------------------------------
-- 1) Load Core Library
------------------------------------------------------------
local SCRIPT_DIR = debug.getinfo(1, "S").source:match("@(.*/)")
local ASP = dofile(SCRIPT_DIR .. "Library/hsuanice_AS Preview Core.lua")

------------------------------------------------------------
-- 2) Utility: Find Track by Name (exact first, then contains)
------------------------------------------------------------
local function find_track_by_name(name, case_insensitive)
  if not name or name == "" then return nil end
  local target = nil
  local N = reaper.CountTracks(0)
  local needle = case_insensitive and name:lower() or name

  -- 2.1 Exact match
  for i = 0, N - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, trname = reaper.GetTrackName(tr, "")
    local hay = case_insensitive and trname:lower() or trname
    if hay == needle then
      target = tr
      break
    end
  end

  -- 2.2 Fallback: substring contains
  if not target then
    for i = 0, N - 1 do
      local tr = reaper.GetTrack(0, i)
      local _, trname = reaper.GetTrackName(tr, "")
      local hay = case_insensitive and trname:lower() or trname
      if hay:find(needle, 1, true) then
        target = tr
        break
      end
    end
  end

  return target
end

------------------------------------------------------------
-- 3) Define Target Track
------------------------------------------------------------
local TARGET_TRACK_NAME = "TEST"

local target_track = find_track_by_name(TARGET_TRACK_NAME, true) -- case-insensitive
if not target_track then
  reaper.ShowMessageBox(
    ("AudioSweet Preview\nTarget track named \"%s\" not found."):format(TARGET_TRACK_NAME),
    "AudioSweet Preview",
    0
  )
  return
end

------------------------------------------------------------
-- 4) Define Parameters
------------------------------------------------------------
local args = {
  -- 額外控制
  debug       = true,
  ----------------------------------------------------------
  -- Core Behavior
  ----------------------------------------------------------
  mode         = "solo",      -- "solo" or "normal"
  target       = "focused",     -- "track" uses focus_track as target (default)
                              -- "focused" isolates the currently focused FX

  ----------------------------------------------------------
  -- Behavior Options
  ----------------------------------------------------------
  chain_mode   = false,        -- true = Chain preview (no FX isolation)
                              -- false = Focused preview (isolate active FX)
  solo_scope   = "item",     -- "track" or "item"
  loop_source  = "auto",      -- "timesel" | "items" | "auto"
  restore_mode = "guid",      -- "guid" | "timesel"

  ----------------------------------------------------------
  -- Track Target
  ----------------------------------------------------------
  focus_track  = target_track,
  -- focus_fxindex = nil,     -- not required for "track" mode
}

------------------------------------------------------------
-- 5) Log Parameters (only if debug) and Run Preview
------------------------------------------------------------
if args.debug then
  reaper.ShowConsoleMsg(string.format(
    "[AS][PREVIEW TEMPLATE] mode=%s  target=%s  solo_scope=%s  chain=%s  loop_source=%s  restore=%s  trackName=%s\n",
    args.mode, args.target, args.solo_scope, tostring(args.chain_mode),
    args.loop_source, args.restore_mode, TARGET_TRACK_NAME
  ))
end



ASP.preview(args)