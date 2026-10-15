--[[
@description Session Fix - check and fix a REAPER session before moving it to Pro Tools, Nuendo or Cubase (Interchanger)
@version 26.1015.1425
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Session Fix - Interchange Prep.lua
@changelog
  - Fix: list columns were squeezed and jumped back when resized; columns now keep their width and the list scrolls sideways when it is wider than the window.
  - Add: lists can be sorted - click a column header (up / down / original order); Shift+click selects a range in the order shown.
  - Fix: Fix on Fade shapes missed fades on hidden tracks / inside collapsed folders (only Fix All reached them); they are fixed now.
  - Change: Folders comes right after Hidden tracks; the title bar and its close button use the chosen font size.
  - Fix: a broken crossfade (fades not matching the overlap) could not get its shape and was set to an invalid value; it is now marked "fix Crossfades first" and left alone until Crossfades has fixed it.
  - Add: issues that need another check first (hidden tracks / collapsed folders, broken crossfades) show it in colour in front; fixing such a check alone asks to fix that first (Yes = first that, then this check).
@about
  # Session Fix

  Find and fix edit details that other DAWs handle differently when a REAPER session is
  converted (for example with Interchanger): one window, "Session Fix - Interchange Prep",
  with a checklist, automatic fixes, a before / after check of every fix and review tracks.

  Requires ReaImGui and the "hsuanice Library" package; js_ReaScriptAPI is optional.
--]]
-- This file only describes the package for ReaPack; it is not installed.
