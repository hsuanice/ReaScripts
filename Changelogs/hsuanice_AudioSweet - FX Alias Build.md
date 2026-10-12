# hsuanice_AudioSweet - FX Alias Build.lua — Changelog

(formerly `hsuanice_FX Alias Build.lua`)

FX Alias Build - Build FX Alias JSON from Current Project

## 26.1012.1641

- Renamed to "AudioSweet - FX Alias Build" (was "FX Alias Build") as part of the 2026-10-12 naming clean-up.

## 26.1011.2142

- Released as part of the 26.1011.2142 package update.

History before 26.1011.2142 (moved out of the script header; last header version: `0.1.1`).

```text
0.1.1
  + FIXED: False error "Failed to create Settings folder" when folder already exists
  + IMPROVED: Error handling now consistent with Export and Update tools
  + RecursiveCreateDirectory() behavior more robust across platforms
0.1.0 [Internal Build 251216.1820] - Settings Directory Safeguard
  - ADDED: Automatically create the Settings folder before writing fx_alias.json to avoid write errors.
  - ADDED: Clear warning dialog if the folder cannot be created so the user knows why the build stops.
[internal: v251030.1600]
  - Initial Public Beta Release
  - FX Alias database builder tool featuring:
    • Scans all Track FX in current project
    • Creates/updates Settings/fx_alias.json database
    • Accessible from AudioSweet ReaImGui: Settings → FX Alias Tools → Build FX Alias Database
    • Integration with AudioSweet file naming system
  - Initial release [internal: v251007]
```
