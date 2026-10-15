# hsuanice_Conform List Browser - CLB Jump Old New TC.lua — Changelog

(formerly `hsuanice_CLB Jump Old-New TC.lua`)

CLB - Jump Old/New TC (Recut)

## 26.1015.1941

- Fix: after a jump the video sometimes showed the previous frame although the timecode looked right (the stored target was rounded to 6 decimals and could sit just before the frame); the jump now lands exactly on the frame.

## 26.1012.1641

- Renamed to "Conform List Browser - CLB Jump Old New TC" (was "CLB Jump Old-New TC") as part of the 2026-10-12 naming clean-up.

## 26.1012.1206

- Released as part of the 26.1012.1206 package update.

History before 26.1012.1206 (moved out of the script header; last header version: `261005.1507`).

```text
v261005.1507 - Jump now preserves the cursor's exact relative position
  within the CLB Recut item (frame-accurate) instead of always landing
  on the paired item's own start.
v261005.1455 - Initial Phase 1 release.
```
