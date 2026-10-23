# hsuanice_Fade Tool Core.lua — Changelog

## 26.1023.1944

- Initial public release (tested in REAPER 7.82).

## 26.1023.1942pre1

- Fix: fade and crossfade shapes now apply on REAPER 7.82 (the shape was reset to Linear by also writing the curvature; FADEINNEW / FADEOUTNEW lines are no longer used).
- Change: REAPER's own shape list (Linear, Equal Power = 7, Slight / Sharp Convex, Concave, S-Curve); saved settings from the first release are converted.

## 26.1023.1853pre1

- Fix: crossfade shape now applies (REAPER 7.71+ keeps it in the FADEINNEW / FADEOUTNEW chunk lines; format from hsuanice_PT_Fades.lua); it stayed Linear before.

## 26.1023.1800pre1

- Initial release.

