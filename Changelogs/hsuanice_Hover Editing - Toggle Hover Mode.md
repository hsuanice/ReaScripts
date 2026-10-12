# hsuanice_Hover Editing - Toggle Hover Mode.lua — Changelog

(formerly `hsuanice_Hover Mode Toggle.lua`)

Hover Mode - Toggle Hover Mode (Syncable)

## 26.1012.1641

- Renamed to "Hover Editing - Toggle Hover Mode" (was "Hover Mode Toggle") as part of the 2026-10-12 naming clean-up.

## 26.1012.0736

- Released as part of the 26.1012.0736 package update.

History before 26.1012.0736 (moved out of the script header; last header version: `250927_1532`).

```text
v250927_1532 - First-run sync: if saved ExtState != toolbar state, apply saved state without flipping (idempotent on first click after launch). Subsequent clicks toggle normally.
v250927_1520 - Persist toggle across sessions: read initial state from ExtState (hsuanice_TrimTools / HoverMode) and only then toggle; accept "true/1/on" as ON. No behavior change if ExtState missing.
v0.1 - Beta release
```
