# CLAUDE.md

REAPER scripts by hsuanice, published with ReaPack from `github.com/hsuanice/ReaScripts`.
This folder is both the git repository and REAPER's live script folder.
**Read `MAINTAINING.md` before changing anything** — it is the full rulebook.

## Talking with hsuanice
- Reply in **Taiwanese Mandarin (臺灣華語)**, little English; explain technical terms in Chinese.
  hsuanice uses VS Code in English — quote English button names (Source Control, Sync Changes).
- **Discuss first, then implement.** After implementing: test, bump the version, write the changelog.
- hsuanice tests in REAPER and pushes with VS Code **Sync Changes** (no GitHub credentials in the terminal).

## Must-follow rules
- **English only** inside scripts (comments, UI, messages, headers, changelogs).
- **Credit** every source / inspiration (README Credits + package About); never drop such lines.
  Disclose AI authorship (README "Built with AI").
- **Version = `YY.MMDD.HHMM` Taipei time** from `TZ=Asia/Taipei date +%y.%m%d.%H%M` (never guess;
  ReaPack rejects segments > 65535). Pre-release = `...pre1`.
- Header `@changelog` = this release only; history goes to `Changelogs/` → use `.dev/bump.py`.
  Bump the **package** file when a file it provides changes.
- **Naming:** series name first, `Full Name - ABBR Action`, `Toggle ...` first, keep Action List
  search keywords, no `/` or brackets in file names (MAINTAINING.md §4).
- Categories are fixed and never renamed. New library files → `Library/hsuanice_Library.lua`
  `@provides` + `.gitignore` whitelist.
- Library path: `reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/"`. Never derive
  paths from folder names, never hardcode `_RS...` command IDs (use `AddRemoveReaScript` by path).
- Small tools: native `gfx`, not ReaImGui. Automatic passes write only on change; never recolor items.
- Don't publish user data, third-party SDKs, or scripts that need someone else's modified code.

## Commands
```sh
python3 .dev/bump.py "Category/hsuanice_X.lua" "Fix: ..."   # new release of one file
python3 .dev/validate.py                                      # must print NO ERRORS
python3 .dev/migrate.py .dev/<batch>.json <out|.>             # publish a batch from Beta Testing/
python3 .dev/switch.py .dev/<batch>.json                      # REAPER CLOSED: repoint reaper-kb.ini
```
`reaper-kb.ini` / `reaper-menu.ini`: only with the main REAPER closed, back up to
`~/Documents/hsuanice Scripts Backups/`, edit as bytes (CRLF), keep action IDs.
`luac` here is Lua 5.5: "assign to const variable" on loop variables is a known false positive.
