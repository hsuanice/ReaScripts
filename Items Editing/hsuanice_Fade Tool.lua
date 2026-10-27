--[[
@description Fade Tool - frame-grid fades and crossfades by razor, time selection, mouse or edit cursor (Smart Fade, Crossfade in Razor, Scene Cut to Razor, Settings)
@version 26.1027.1553pre1
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Fade Tool - Smart Fade at Mouse or Edit Cursor.lua
  [main] hsuanice_Fade Tool - Crossfade in Razor.lua
  [main] hsuanice_Fade Tool - Scene Cut to Razor.lua
  [main] hsuanice_Fade Tool - Settings.lua
@changelog
  - Fix: a razor over several tracks no longer pulls cuts into tracks where it only covers empty space or the middle of an item (e.g. extending both items of a gap) when other tracks have cuts or item edges in the razor.
  - Add: Settings option "Pull nearby cuts into an empty area" (on by default) to turn these pull-ins off.
@about
  # Fade Tool

  Frame-accurate fades for frame-grid editing. Everything works on razor edit areas and never
  opens a window unless something had to be skipped.

  - Smart Fade at Mouse or Edit Cursor: one shortcut for everything. Razor first, then
    time selection + selected tracks, then the mouse (Hover Mode on: top half = fade-in,
    bottom half = fade-out, item name bar = move the nearest crossfade centered on the mouse),
    else the edit cursor. Shares Hover Mode with Hover Editing - Toggle Hover Mode.
  - Crossfade in Razor: one cut in the razor area -> the crossfade fills the area exactly;
    no cut -> the nearest visible cut is moved into the area; several cuts -> each gets the
    default crossfade (e.g. 1 frame before the cut). Default shape: Equal Power. Over several
    tracks, empty parts of the razor are left alone when other tracks have cuts or item edges.
  - Scene Cut to Razor: the razor area is the scene (no razor: the scene on the "Scene Cut"
    track that the selected items cover completely); only the first and last item are trimmed
    or extended, with a fade-in before the scene start and a fade-out on its last frame
    (1 frame Linear by default). Items in between stay untouched.
  - Settings: lengths in frames, positions (before / center / after) and shapes.

  Shapes: a fade or crossfade side that already exists (length > 0) keeps its own shape; the
  Settings shapes are only used for new fades. Scene Cut always uses the Scene fade shape.

  Requires the hsuanice Library package. Hover Mode needs SWS and the Hover Editing package
  (Toggle Hover Mode); without them Smart Fade works at the edit cursor.

  Credits: heavily based on AZ's "Fade tool (work on context of mouse, razor or time
  selection)" (ReaTeam Scripts) by AZ - https://forum.cockos.com/member.php?u=135221 ,
  forum thread https://forum.cockos.com/showthread.php?t=293335 . Fade Tool follows its design
  closely: the context order (razor, time selection, mouse), top half = fade-in / bottom half
  = fade-out, the item name bar moving a crossfade (including AZ's way of detecting the name
  bar), razor crossfades and razor fades. The code is a new implementation by hsuanice with
  AI (Claude Code), with hsuanice's changes: frame-based defaults, no pop-up windows, Hover
  Mode support, hold-and-drag crossfade edges and Scene Cut.

  Hold-the-shortcut detection follows Sexan's "VT_SWIPE to Comp HOLD" (Virtual Track,
  Sexan_Scripts).
--]]
-- This file only describes the package for ReaPack; it is not installed.
