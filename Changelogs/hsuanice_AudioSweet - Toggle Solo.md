# hsuanice_AudioSweet - Toggle Solo.lua — Changelog

(formerly `hsuanice_AudioSweet Solo Toggle.lua`)

AudioSweet Solo Toggle

## 26.1012.1641

- Renamed to "AudioSweet - Toggle Solo" (was "AudioSweet Solo Toggle") as part of the 2026-10-12 naming clean-up.

## 26.1011.2225

- Fix: no longer requires the SWS extension (uses REAPER's native GetTrackGUID instead of BR_GetMediaTrackGUID).

## 26.1011.2142

- Released as part of the 26.1011.2142 package update.

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.0`).

```text
0.2.0 [Internal Build 251223.2256] - Public Beta Release
  - CHANGED: Version bump to 0.2.0 (public beta)

0.1.0 [Internal Build 251221.1123] - Public Beta Release
  - Intelligent solo toggle for AudioSweet Preview workflow
  - 3-priority target detection:
    • Priority 1: Active preview (placeholder found) → Toggle preview target track
    • Priority 2: Soloed track found → Toggle that track
    • Priority 3: No preview/solo → Toggle default preview target track
  - Stays locked to preview target track during active preview
  - Supports both track solo and item solo modes
  - Placeholder detection: extracts track number from "PREVIEWING @ Track <n>" note
  - Works in both Focused and Chain preview modes
  - Handles user editing/selection changes during preview
  - Built-in debug mode (set DEBUG = true for detailed logging)
  - Reads settings from AudioSweet ReaImGui GUI ExtState
  - Can be assigned to keyboard shortcuts in action list
```
