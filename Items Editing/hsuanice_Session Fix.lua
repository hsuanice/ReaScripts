--[[
@description Session Fix - check and fix a REAPER session before moving it to Pro Tools, Nuendo or Cubase (Interchanger)
@version 26.1101.1419pre1
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Session Fix - Interchange Prep.lua
@changelog
  - New: Scene cuts check (review only) with Mark as OK
@about
  # Session Fix

  Find and fix edit details that other DAWs handle differently when a REAPER session is
  converted (for example with Interchanger): one window, "Session Fix - Interchange Prep",
  with a checklist, automatic fixes, a before / after check of every fix and review tracks.

  Requires ReaImGui and the "hsuanice Library" package; js_ReaScriptAPI is optional.
--]]
-- This file only describes the package for ReaPack; it is not installed.
