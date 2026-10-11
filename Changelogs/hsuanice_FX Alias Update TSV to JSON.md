# hsuanice_FX Alias Update TSV to JSON.lua — Changelog

FX Alias Update - Update FX Alias JSON from TSV

History before 26.1011.2142 (moved out of the script header; last header version: `0.1.0`).
Newer entries are kept in each release's `@changelog` and shown in ReaPack.

```text
0.1.0 (2025-12-12) [internal: v251030.1600]
  - Initial Public Beta Release
  - FX Alias TSV to JSON updater tool featuring:
    • Reads edited fx_alias.tsv and updates fx_alias.json
    • Preserves existing entries not in TSV
    • Accessible from AudioSweet ReaImGui: Settings → FX Alias Tools → Update TSV to JSON
    • Completes FX Alias workflow: Build → Export → Edit → Update
  - Fix JSON decode, stable object-key ordering in encoder [internal: v251007.1]
  - Initial release [internal: v251007]
```
