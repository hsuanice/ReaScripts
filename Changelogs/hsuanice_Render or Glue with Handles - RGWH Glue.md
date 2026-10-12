# hsuanice_Render or Glue with Handles - RGWH Glue.lua — Changelog

(formerly `hsuanice_RGWH Glue.lua`)

RGWH Glue - Glue with Handles (ExtState Shortcut)

## 26.1012.1641

- Renamed to "Render or Glue with Handles - RGWH Glue" (was "RGWH Glue") as part of the 2026-10-12 naming clean-up.

## 26.1011.2142

- Released as part of the 26.1011.2142 package update.

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.2`).

```text
0.2.2 (260207.0230)
  - FIXED: Force selection_scope = "auto" (ignore GUI SELECTION_SCOPE)
    • Prevents "no_time_selection" error when GUI is set to TS mode
    • Wrapper now works with both item selection and time selection
  - ADDED: Error message display when Core fails (always shown)

0.2.1 (260206.2345)
  - ADDED: MULTI_CHANNEL_POLICY reading
  - ADDED: SELECTION_SCOPE reading
  - ADDED: SELECTION_POLICY reading (replaces hardcoded value)
  - ADDED: GLUE_MERGE_TO_ITEM reading
  - IMPACT: Now reads ALL GUI settings from ExtState

0.2.0 (260206.2230)
  - BREAKING: Now reads ALL settings from RGWH ExtState
  - Acts as keyboard shortcut for RGWH GUI glue operation
  - No more hardcoded settings - mirrors GUI configuration
  - Simplified code: removed manual args table
  - TS-aware selection restore for split items

0.1.0 (2025-12-12) [internal: v251022_2200]
  - Initial release with hardcoded settings
```
