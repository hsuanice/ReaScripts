# hsuanice_Fade Tool.lua — Changelog

## 26.1023.2042pre1

- Add: Smart Fade drag - hold Cmd (Ctrl on Windows) to invert Snap for fine-tuning.

## 26.1023.2032pre1

- Add: Smart Fade hold-and-drag for crossfade edges or the whole crossfade.
- Change: Smart Fade and Crossfade in Razor never change anything outside the arrange view (Scene Cut excepted).
- Change: a short Smart Fade press no longer adjusts one side of a crossfade.

## 26.1023.2012pre1

- Fix: Smart Fade adjusts only the crossfade nearer to the mouse / edit cursor on an item with crossfades on both sides.

## 26.1023.2008pre1

- Add: Smart Fade adjusts one side of a crossfade (Hover: top half = end, bottom half = start; Hover off: mouse left / right of the edit cursor).
- Add: Smart Fade over empty arrange space (Hover Mode on) opens Settings.
- Credits: written out in full - Fade Tool is heavily based on AZ's Fade tool (ReaTeam Scripts).

## 26.1023.1958pre1

- Add: Smart Fade at Mouse or Edit Cursor - razor, then time selection + selected tracks, then mouse (top half fade-in, bottom half fade-out, name bar moves the nearest crossfade) or edit cursor; shares Hover Mode with Hover Editing.
- Add: Crossfade in Razor fades a free item edge inside the razor area.

## 26.1023.1944

- Initial release: Crossfade in Razor (fit one cut to the razor area or crossfade every cut in it, Equal Power), Scene Cut to Razor (edge items trimmed or extended with 1-frame transition fades), Settings (gfx window).

## 26.1023.1942pre1

- Fix: fade and crossfade shapes now apply (they always stayed Linear on REAPER 7.82).
- Change: shape menu lists all eight REAPER fade shapes.

## 26.1023.1853pre1

- Fix: Crossfade in Razor now applies the crossfade shape (Equal Power by default); it stayed Linear before.

## 26.1023.1850pre1

- Change: Settings is now a gfx window with radio buttons, steppers, a shape menu and a checkbox.

## 26.1023.1818pre1

- Fix: Settings shows the scene fade position choices (before, center, after).

## 26.1023.1800pre1

- Initial release.

