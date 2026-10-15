# Maintaining hsuanice Scripts

How this repository is organized, the rules every change follows, and the release workflow.
Written for whoever maintains it next — a person or an AI coding agent. `CLAUDE.md` is the short
version that Claude Code reads automatically; this file is the full reference.

The owner is **hsuanice**, an audio post-production engineer who designs and tests every tool. Most
code is written with AI ("vibe coding"). Talk to hsuanice in **Taiwanese Mandarin (臺灣華語)** with
little English; **everything written into the repository is English**.

---

## 1. Principles

These came from real decisions; follow them unless hsuanice says otherwise.

1. **Credit everyone.** Keep every "based on / inspired by / reference" line in headers and code
   comments. Credit third-party ideas and code in `README.md` (Credits) *and* in the package
   About. Current credits: Tim Chimes (AudioSweet), TJF (Hover Mode Toggle), rodilab (Color
   palette), OLSHALOM (Chroma ShinyColor), OpenTimelineIO (ASWF), LibAAF / aaftool (agfline),
   rxi/json.lua (MIT — the full license notice must stay in `Library/json.lua`). Before each
   release, grep the headers **and** the code comments ("mirror X's ...") for references; ask
   hsuanice for the author if unknown.
2. **Disclose AI authorship.** README section "Built with AI (vibe coding)" — hsuanice designs and
   tests, AI (Claude, ChatGPT) writes most code, Claude Code maintains the repository.
3. **English only inside scripts** — comments, UI text, messages, headers, changelogs. Older
   files still contain Chinese comments; translate user-visible text before publishing, and
   comments when a file is touched (open TODO).
4. **Small tools use REAPER's native `gfx`**, not ReaImGui. ReaImGui is for the big GUIs only
   (RGWH, AudioSweet, Rename, Item List, Reorder, Conform List Browser, Session Fix - Interchange Prep).
5. **Warn, don't guess.** When a heuristic could pick the wrong item (re-linking, matching, cleanup),
   only act on unambiguous matches and show the rest to the user.
6. **Reuse before writing.** Look for an existing function or Library module first.
7. **Discuss before implementing** behavior changes; after implementing, test, bump the version and
   write the changelog every time.
8. **Never change the user's data silently.** Background/automatic passes write only when
   something actually changed (no undo point, no dirty project otherwise) and never recolor
   items (it conflicts with Auto Color).

## 2. Repository layout

The local working folder *is* the git repository and *is* REAPER's script folder:
`~/Library/Application Support/REAPER/Scripts/hsuanice Scripts/` → `github.com/hsuanice/ReaScripts`.
The ReaPack index name is **"hsuanice Scripts"**, so ReaPack installs packages into exactly this
folder name on users' machines — hardcoded paths like
`reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/"` are therefore valid everywhere.

| Path | Published | What it is |
|---|---|---|
| `Rendering/`, `Items Editing/`, `Items Properties/`, `Selection/`, `Tracks/`, `Metadata/`, `Conform/`, `Various/` | yes | Categories (one folder = one ReaPack category) |
| `Library/` | selected files | Shared code, installed by the "hsuanice Library" metapackage |
| `Tools/*.py` | 3 files | Python helpers installed with Conform List Browser (`[nomain] ../Tools/...`) |
| `Changelogs/` | yes | Full history per script (newest first); headers only hold the current release |
| `Reaper Forum/` | yes | Images linked from forum posts — keep so old links work |
| `.dev/` | yes | Maintenance tools (see §7) and `history/` (batch / rename configs used so far) |
| `README.md`, `MAINTAINING.md`, `CLAUDE.md`, `.github/`, `.reapack-index.conf`, `index.xml` | yes | Docs, CI, generated index |
| `Beta Testing/` | **no** | Local work in progress / not-yet-published scripts |
| `Archive/` | **no** | Retired scripts and `_backup/` snapshots (moved, never deleted) |
| `PRO TOOLS/`, `PT2Reaper Project/`, `Tools/Apps/`, `Settings/`, `docs/` | **no** | Local projects, apps, user data, private notes |

`.gitignore` is a **whitelist**: everything is ignored except the paths listed in it. When a new
category or Library file is published, add it there.

Never publish: user data (`Settings/fx_alias.json`, `Tools/hsuanice_AutoColorItems_state.dat`),
anything containing third-party SDKs (the Pro Tools sync bundles Avid's PTSL SDK), scripts that
need someone else's modified code (the BirdBird Global Sampler helpers need a patched JSFX —
offer the patch upstream first), or debug tools tied to one machine (monitors that hardcode
command IDs).

## 3. Packages

- **Categories never get renamed.** Renaming a category creates new packages for every user and
  breaks their shortcuts. Current set: Rendering, Items Editing, Items Properties, Selection,
  Tracks, Metadata, Conform, Various, Library.
- **Package types**
  - *Single script*: the file itself is the package.
  - *Main + actions*: the main file is the package and lists the others
    (`@provides` `[main] .` + `[main] other.lua`; helpers as `[nomain]`). The other files carry `@noindex`.
  - *Metapackage*: a small description-only file with `@metapackage` and `@provides`
    (e.g. `hsuanice_Hover Editing.lua`); it is not installed itself.
  - `[nomain]` = installed but not in the Action List. `[main=mediaexplorer]` = Media Explorer section.
  - *Backup only*: a script that stays in the repository (version history on GitHub) but is not
    offered on ReaPack — `@noindex  (kept in the repository as a backup; ...)` in its header. The
    word "backup" tells `validate.py` it is unlisted on purpose (e.g. PM Insight Analyzer while it
    is a work in progress). Remove the line to publish it again.
- **hsuanice Library** (`Library/hsuanice_Library.lua`) is a metapackage that installs every
  shared library as `[nomain]`. When a script starts using a new library file: add it to that
  `@provides`, to `.gitignore`, and bump the Library package.
- **Missing-Library prompt.** Every script that loads a library starts with a check that shows a
  message and opens ReaPack (`ReaPack_BrowsePackages('hsuanice Library')`) when the file is
  missing (`.dev/migrate.py` inserts it).
- **Paths.** Load libraries from `reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/"`.
  Find sibling scripts from the script's own folder (`debug.getinfo(1, "S").source`). **Never**
  derive paths from category folder names (`gsub("Beta Testing", "Library")` broke on every move)
  and **never** hardcode a command ID (`_RS...` differs per machine) — look a script up by path
  with `reaper.AddRemoveReaScript(true, 0, path, true)`.
- **Python helpers** are scanned by reapack-index too: every `.py` in the repo needs a
  `# @noindex` line right after the shebang.

## 4. Naming (agreed 2026-10-12)

Users find scripts by searching the Action List, which shows `Script: <file name>`.

- `hsuanice_<Series or package> - <Action>.lua`. GUI main window: `<Series> - <short what it is>`.
  Standalone tool: verb first — `Move Selected Items to Track Under Mouse`.
- **Series / package name first**, and words shared by a family first, so the family sorts
  together — as long as the phrase still reads naturally.
- **Abbreviations keep the full name:** `<Full Name> - <ABBR> <Action>`
  (`Conform List Browser - CLB Reveal Item`, `Render or Glue with Handles - RGWH Glue`).
- **Toggle first:** `Toggle <feature>` / `<Series> - Toggle <feature>` (REAPER's own wording).
- **Keep search keywords** (Razor, Envelope Points, Poly, Take Name, Pro Tools, AudioSuite ...).
  Implementation details (ReaImGui, GFX, daemon, wrapper) go into the description.
- Letters, digits, spaces and `-` only — **no `/`, no brackets**. Title Case. ~50 characters,
  but keywords win. Library files are not renamed.
- Renaming something already published = a new package for users: changelog says
  "reinstall and re-assign shortcuts"; use `.dev/rename.py` (§7).

## 5. Headers, versions, changelogs

```lua
--[[
@description Hover Editing - Split Items at Mouse or Edit Cursor
@version 26.1012.1641
@author hsuanice
@noindex                      -- only for files provided by another package
@changelog
  - What changed in THIS release only (a few lines)
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  What it does, requirements, suggested shortcuts, credits
--]]
```

- **Version = `YY.MMDD.HHMM` in Taipei time** (`TZ=Asia/Taipei date +%y.%m%d.%H%M`). ReaPack rejects
  any number segment above 65535, so `YYMMDD.HHMM` never indexed. Never guess the time.
- **Pre-release:** append `pre1`, `pre2`, ... (`26.1012.1641pre1`); only users with
  "Enable pre-releases" get it. A later version without `pre` makes it public.
- **ReaPack only sees the package file's version.** When a provided file changes, bump the package
  file too. Commits without a version change publish nothing (safe for backups / WIP).
- **Changelog in the header = this release only.** Older entries live in `Changelogs/<file>.md`
  (`.dev/bump.py` moves the previous entry there automatically).
- **One version source.** GUIs read their version from their own `@version` line at runtime; never
  keep a second copy in code.
- **Suggested shortcuts** go in the About ("suggestions only — nothing is assigned automatically",
  macOS names + Windows equivalents). ReaPack never assigns shortcuts.

## 6. Release workflow

**Daily change to a published script**
1. Edit the file in its category folder; test in the main REAPER (it runs the files directly).
2. `python3 .dev/bump.py "Category/hsuanice_X.lua" "Fix: ..." "Add: ..."`
   (bump the package file as well if X is provided by another package).
3. `python3 .dev/validate.py` → must print `NO ERRORS`. Run `luac -p` on edited files (see §8).
4. Update `README.md` when packages, names or requirements change.
5. Commit (end the message with the co-author line). hsuanice pushes with **VS Code → Source
   Control → Sync Changes** (the terminal has no GitHub credentials).
6. GitHub Actions: `check` validates, `deploy` regenerates `index.xml` and pushes a bot commit
   ("index: ...") → Sync again to pull it. ReaPack may show the old list for ~5 minutes
   (raw.githubusercontent.com cache).

**Publishing scripts from `Beta Testing/` (a batch)**
1. Review with hsuanice: what to publish, retire (→ `Archive/<version>----retired/`) or keep local.
2. Write `.dev/<batch>.json` (see `.dev/history/` for examples), dry-run
   `python3 .dev/migrate.py .dev/<batch>.json /tmp/out`, then apply with `.` as OUT.
   It rewrites headers, moves old changelogs, adds Library checks and suggested shortcuts, and
   verifies the code body is byte-identical.
3. Add the category / libraries to `.gitignore`, the Library metapackage and `README.md`.
4. `python3 .dev/validate.py`.
5. Ask hsuanice to **quit the main REAPER**, then `python3 .dev/switch.py .dev/<batch>.json`
   (repoints `reaper-kb.ini` so shortcuts / toolbars keep working; old copies → `Archive/_backup/`).
6. hsuanice tests in REAPER → commit → Sync.

**Renaming published scripts:** `.dev/rename.py RENAME.json DESCRIPTIONS.json` (git mv + references +
descriptions + bump), then with REAPER closed `.dev/switch_rename.py RENAME.json`.

## 7. Tools in `.dev/`

| Tool | Purpose |
|---|---|
| `bump.py` | New release of one file: version, header changelog, `Changelogs/*.md` |
| `validate.py` | ReaPack rules: header present, version format, `@provides` targets exist, no file owned twice, every published file installed by a package |
| `migrate.py` | Move a batch from `Beta Testing/` into a category (headers, changelogs, Library checks, shortcuts) |
| `switch.py` | After `migrate.py`: repoint `reaper-kb.ini`, archive the old copies |
| `rename.py` / `switch_rename.py` | Rename published scripts / repoint `reaper-kb.ini` |

`reapack-index` itself cannot be installed on hsuanice's Mac (system Ruby 2.6; the rugged gem does
not build), so `validate.py` mirrors its rules and the `check` workflow is the final authority.
For risky changes, push to a branch first — `check` runs on every branch, `deploy` only on `master`.

## 8. REAPER and testing notes

- **Main REAPER** runs the scripts from this folder. Its ReaPack remote for this repository is
  **disabled** on purpose — enabling it would overwrite the working files.
- **Test REAPER** (portable, `/Applications/REAPER TEST/`, own config and `reaper-kb.ini`) has the
  repository enabled in ReaPack: use it to check what users get.
- **`reaper-kb.ini`** (action registrations, shortcuts) and **`reaper-menu.ini`** (toolbars):
  edit only while the main REAPER is closed, back up first to
  `~/Documents/hsuanice Scripts Backups/<YYMMDD.HHMM>----<reason>/`, read/write **as bytes**
  (kb.ini uses CRLF), keep action IDs. Toolbar items must stay numbered `item_0..n` with their
  `icon_N` lines shifted together; never touch `MenuSets/` (user backups).
- `luac` on this Mac is Lua 5.5 and reports "attempt to assign to const variable" for loop
  variables reassigned inside the loop. REAPER's Lua runs them fine — confirm the same error exists
  in the original file; to check the rest of the file, test a copy with that line patched.
- A `local function` must be defined above every line that calls it (luac does not catch it).
- `---@diagnostic` or any line above `--[[` breaks the ReaPack header — headers start on line 1.
- `os.execute("mkdir -p ...")` fails on Windows and spawns a shell — use
  `reaper.RecursiveCreateDirectory(path, 0)` (collapse `dir/../` first).
- ReaImGui on macOS: Cmd is `Mod_Ctrl`. `ImGui.OpenPopup` right after a blocking file dialog fails
  silently — open it on the next frame.

## 9. Open work

Kept in hsuanice's notes; the main items: translate remaining Chinese comments; convert small
ReaImGui tools to gfx; new
`Session Fix - Remove Workflow Cues`; merge PM Scene Analyzer's report into PM Insight Analyzer;
RGWH / AudioSweet efficiency clean-ups; a new product name for Conform List Browser (if renamed:
new `.clm` files, still open `.clb`, keep internal names); offer the BirdBird gmem patch upstream.
