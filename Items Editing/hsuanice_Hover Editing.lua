--[[
@description Hover Editing - Pro Tools-style Split / Trim / clip gain at the mouse or edit cursor (Toggle Hover Mode, Split, Trim Left / Right, Nudge Take Volume)
@version 26.1031.1833pre1
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Hover Editing - Toggle Hover Mode.lua
  [main] hsuanice_Hover Editing - Split Items at Mouse or Edit Cursor.lua
  [main] hsuanice_Hover Editing - Trim or Extend Left Edge.lua
  [main] hsuanice_Hover Editing - Trim or Extend Right Edge.lua
  [main] hsuanice_Hover Editing - Nudge Take Volume with Mousewheel.lua
  [nomain] hsuanice_Hover Editing - Nudge Take Volume Timer.lua
@changelog
  - New: Nudge Take Volume with Mousewheel (Pro Tools-style clip gain, Hover aware, merged undo)
@about
  # Hover Editing

  Pro Tools-style editing that follows the mouse (Hover Mode on) or the edit cursor (Hover Mode off).

  - Toggle Hover Mode: switch Hover Mode on/off (toolbar-friendly)
  - Split: split items at the selection, edit cursor or mouse
  - Trim Left / Right: trim or extend the item edge to the cursor, keeping fades
  - Nudge Take Volume with Mousewheel: clip gain on the item under the mouse or the selection

  Toggle Hover Mode is based on / inspired by TJF's "Hover Mode Toggle" script.

  ## Suggested shortcuts
  - Hover Mode Split Item by Selection or Edit or Mouse Cursor: B
  - Hover Mode Trim or Extend Left Edge of Item: A
  - Hover Mode Trim or Extend Right Edge of Item: S
  - Hover Editing - Nudge Take Volume with Mousewheel: Shift+Cmd+Mousewheel

  Shortcuts are suggestions only — nothing is assigned automatically. macOS names; on Windows Cmd = Ctrl, Option = Alt, Control = Win.
--]]
-- This file only describes the package for ReaPack; it is not installed.
