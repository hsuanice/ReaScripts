# hsuanice_Auto Color - All Shiny Color.lua — Changelog

(formerly `hsuanice_Auto Color All ShinyColor.lua`)

Auto Color All ShinyColor

## 26.1012.1641

- Renamed to "Auto Color - All Shiny Color" (was "Auto Color All ShinyColor") as part of the 2026-10-12 naming clean-up.

## 26.1012.0930

- Released as part of the 26.1012.0930 package update.
- Fix: All Shiny (GUI button and All ShinyColor script) no longer re-colors items in the black / gray / white row that are already Shiny.

History before 26.1012.0930 (moved out of the script header; last header version: `261002.1042`).

```text
v261002.1042
- Fix: items already in Shiny mode were being re-pastelized on every run (background
  recomputed from the already-pale background instead of the true peak color), fading
  everything out more each time. Now detects "already shiny" by checking whether the
  background's hue matches the peak's hue and its saturation is meaningfully lower
  (the shiny formula's signature) and skips those items instead of reprocessing them.
- Change: now converts just the selected items when any are selected; only falls back to
  the whole project (with an OK/Cancel confirmation prompt) when nothing is selected.

v261002.1021
- Initial extraction from hsuanice_Auto Color Items by Take Name.lua
```
