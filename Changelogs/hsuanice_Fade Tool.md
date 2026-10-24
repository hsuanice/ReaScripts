# hsuanice_Fade Tool.lua — Changelog

## 26.1024.1910

- Add: Scene Cut to Razor without a razor - select items and the scene they cover completely on the Scene Cut track is used.
- Release: tested in REAPER 7.82.

## 26.1024.1906pre1

- Add: Scene Cut to Razor without a razor - select items and the scene they cover completely on the Scene Cut track is used.

## 26.1024.1009

- Add: crossfade across a gap between two items - a razor inside the gap, or over both gap edges, extends both items into a crossfade over the razor (it made two separate fades before).
- Release: tested in REAPER 7.82.

## 26.1024.1004pre1

- Add: crossfade across a gap between two items - a razor inside the gap, or over both gap edges, extends both items into a crossfade over the razor (it made two separate fades before).

## 26.1023.2124

- Fix: Smart Fade drag keeps a Cmd fine-tuned position when the keys are released.
- Release: tested in REAPER 7.82.

## 26.1023.2122pre1

- Fix: Smart Fade drag keeps a Cmd fine-tuned position when the keys are released.

## 26.1023.2047

- Add: Smart Fade at Mouse or Edit Cursor - one shortcut that replaces a mouse / razor fade tool: razor, time selection + selected tracks, mouse (Hover Mode) or edit cursor; hold to drag crossfade edges or the whole crossfade, Cmd (Ctrl) inverts Snap.
- Change: Crossfade in Razor and Smart Fade never change anything outside the arrange view (Scene Cut excepted).
- Credits written out in full: heavily based on AZ's Fade tool; hold detection after Sexan's VT_SWIPE to Comp HOLD.
- Release: tested in REAPER 7.82.

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

