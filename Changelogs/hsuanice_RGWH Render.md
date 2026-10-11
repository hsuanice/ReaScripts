# hsuanice_RGWH Render.lua — Changelog

RGWH Render - Render with Handles (ExtState Shortcut)

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.2`).
Newer entries are kept in each release's `@changelog` and shown in ReaPack.

```text
0.2.2 (260207.0230)
  - FIXED: Force selection_scope = "auto" (consistent with Glue wrapper)
  - ADDED: Error message display when Core fails (always shown)

0.2.1 (260206.2345)
  - ADDED: MULTI_CHANNEL_POLICY reading
  - ADDED: SELECTION_SCOPE reading
  - ADDED: SELECTION_POLICY reading (replaces hardcoded value)
  - ADDED: RENDER_MERGE_TO_ITEM reading
  - IMPACT: Now reads ALL GUI settings from ExtState

0.2.0 (260206.2230)
  - BREAKING: Now reads ALL settings from RGWH ExtState
  - Acts as keyboard shortcut for RGWH GUI render operation
  - No more hardcoded settings - mirrors GUI configuration
  - Simplified code: removed manual args table

0.1.0 (251212) [internal: v251022_2200]
  - Initial release with hardcoded settings
```
