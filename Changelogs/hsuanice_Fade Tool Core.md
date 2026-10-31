# hsuanice_Fade Tool Core.lua — Changelog

## 26.1031.1225pre1

- Fix: resizing an existing fade or crossfade (Smart Fade and the other Fade Tool scripts) no longer resets its shape and curve to Linear

## 26.1027.1608

- Fix: a razor over several tracks no longer pulls cuts into tracks where it only covers empty space or the middle of an item (e.g. extending both items of a gap) when other tracks have cuts or item edges in the razor.
- Add: Settings option "Pull nearby cuts into an empty area" (on by default) to turn these pull-ins off.
- Release: tested in REAPER 7.82.

## 26.1027.1553pre1

- Fix: a razor over several tracks no longer pulls cuts into tracks where it only covers empty space or the middle of an item (e.g. extending both items of a gap) when other tracks have cuts or item edges in the razor.
- Add: Settings option "Pull nearby cuts into an empty area" (on by default) to turn these pull-ins off.

## 26.1026.1232

- Add: a razor area inside an item with no neighbour on either side fades in from the item start to the area start and fades out from the area end to the item end (as AZ's Fade tool). An item with a neighbour still gets its nearest cut pulled into the area.
- Release: tested in REAPER 7.82.

## 26.1026.1230pre1

- Add: a razor area inside an item with no neighbour on either side fades in from the item start to the area start and fades out from the area end to the item end (as AZ's Fade tool). An item with a neighbour still gets its nearest cut pulled into the area.

## 26.1025.1231

- Change: an existing fade or crossfade side (length > 0) keeps its own shape; the default shape from Settings is only used for a new fade.
- Release: tested in REAPER 7.82.

## 26.1025.1227pre1

- Change: an existing fade or crossfade side (length > 0) keeps its own shape; the default shape from Settings is only used for a new fade.

## 26.1024.1009

- Add: crossfade across a gap between two items - a razor inside the gap, or over both gap edges, extends both items into a crossfade over the razor (it made two separate fades before).
- Release: tested in REAPER 7.82.

## 26.1024.1004pre1

- Add: crossfade across a gap between two items - a razor inside the gap, or over both gap edges, extends both items into a crossfade over the razor (it made two separate fades before).

## 26.1023.2047

- Smart Fade support: mouse / edit cursor fades, name bar crossfade move, visible-area rule (razor / time selection clipped to the arrange view), plain fades never touch a crossfade.
- Release: tested in REAPER 7.82.

## 26.1023.2032pre1

- Add: visible-area helpers (in_view, track_visible); razor / time selection areas are clipped to the arrange view.
- Change: plain fades never touch a crossfade.

## 26.1023.2012pre1

- Fix: an item with crossfades on both sides only moves the crossfade nearer to the mouse / edit cursor (a far crossfade was stretched across the item).

## 26.1023.2008pre1

- Add: side_fade() - one-sided fade or crossfade end / start adjustment.
- Credits: written out in full - Fade Tool is heavily based on AZ's Fade tool (ReaTeam Scripts).

## 26.1023.1958pre1

- Add: Smart Fade helpers (fade to mouse / cursor, crossfade neighbours, move crossfade, item name bar detection, time selection areas).
- Add: a free item start / end inside a razor area gets a plain fade over the area.
- Add: Fade shape and Use time selection settings.

## 26.1023.1944

- Initial public release (tested in REAPER 7.82).

## 26.1023.1942pre1

- Fix: fade and crossfade shapes now apply on REAPER 7.82 (the shape was reset to Linear by also writing the curvature; FADEINNEW / FADEOUTNEW lines are no longer used).
- Change: REAPER's own shape list (Linear, Equal Power = 7, Slight / Sharp Convex, Concave, S-Curve); saved settings from the first release are converted.

## 26.1023.1853pre1

- Fix: crossfade shape now applies (REAPER 7.71+ keeps it in the FADEINNEW / FADEOUTNEW chunk lines; format from hsuanice_PT_Fades.lua); it stayed Linear before.

## 26.1023.1800pre1

- Initial release.

