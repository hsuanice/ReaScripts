--[[
@description Session Fix - check and fix a REAPER session before moving it to Pro Tools, Nuendo or Cubase (Interchanger)
@version 26.1018.1239
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Session Fix - Interchange Prep.lua
@changelog
  - Add: Workflow cues (last check) - removes the #in / #out / #Glue cues that glue / render leave in WAV files, only for files inside the session folder, in place (same file, audio untouched); other cues, take markers and project markers stay. Asks first (cannot be undone with Undo).
  - Add: Scan shows a progress bar with Cancel instead of freezing REAPER, and the time of each check (the slowest are shown).
  - Add: Tiny items check - editing slivers under 2 frames for review; 2-pops (xx:59:58:00 or after the last audio) are recognized and left out.
  - Add: Tiny items - mark tail pops as 2-pop from the list, or write "2-pop" / "tail pop" in the Item Notes, so they are left out.
@about
  # Session Fix

  Find and fix edit details that other DAWs handle differently when a REAPER session is
  converted (for example with Interchanger): one window, "Session Fix - Interchange Prep",
  with a checklist, automatic fixes, a before / after check of every fix and review tracks.

  Requires ReaImGui and the "hsuanice Library" package; js_ReaScriptAPI is optional.
--]]
-- This file only describes the package for ReaPack; it is not installed.
