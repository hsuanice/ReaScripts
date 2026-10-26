# hsuanice_Fade Tool - Crossfade in Razor.lua — Changelog

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

- Add: a free item start / end inside the razor area gets a plain fade over the area.
- Change: only the part of the razor area inside the arrange view, on visible tracks, is used.
- Release: tested in REAPER 7.82.

## 26.1023.2032pre1

- Change: only the part of the razor area inside the arrange view, on visible tracks, is used.

## 26.1023.2008pre1

- Credits: written out in full - Fade Tool is heavily based on AZ's Fade tool (ReaTeam Scripts).

## 26.1023.1958pre1

- Add: an item start or end inside the razor area without a neighbour gets a plain fade over the area.

## 26.1023.1944

- Initial public release (tested in REAPER 7.82).

## 26.1023.1800pre1

- Initial release.

