--[[
@description Fade Tool - razor-based crossfades and scene cut fades on the frame grid (Crossfade in Razor, Scene Cut to Razor, Settings)
@version 26.1023.1850pre1
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Fade Tool - Crossfade in Razor.lua
  [main] hsuanice_Fade Tool - Scene Cut to Razor.lua
  [main] hsuanice_Fade Tool - Settings.lua
@changelog
  - Change: Settings is now a gfx window with radio buttons, steppers, a shape menu and a checkbox.
@about
  # Fade Tool

  Frame-accurate fades for frame-grid editing. Everything works on razor edit areas and never
  opens a window unless something had to be skipped.

  - Crossfade in Razor: one cut in the razor area -> the crossfade fills the area exactly;
    no cut -> the nearest visible cut is moved into the area; several cuts -> each gets the
    default crossfade (e.g. 1 frame before the cut). Default shape: Equal Power.
  - Scene Cut to Razor: the razor area is the scene; only the first and last item are trimmed
    or extended, with a fade-in before the scene start and a fade-out on its last frame
    (1 frame Linear by default). Items in between stay untouched.
  - Settings: lengths in frames, positions (before / center / after) and shapes.

  Requires the hsuanice Library package.

  Design inspired by AZ's "Fade tool (work on context of mouse, razor or time selection)"
  (ReaTeam Scripts, https://forum.cockos.com/showthread.php?t=293335). No code was copied.
--]]
-- This file only describes the package for ReaPack; it is not installed.
