# hsuanice Scripts

REAPER scripts for audio post-production, by hsuanice.

## Install

1. Install [ReaPack](https://reapack.com/).
2. In REAPER: **Extensions > ReaPack > Import repositories...** and paste:

   ```
   https://github.com/hsuanice/ReaScripts/raw/master/index.xml
   ```

3. **Extensions > ReaPack > Browse packages**, search for `hsuanice`, and install:
   - **hsuanice Library** (required by most scripts below; adds nothing to the Action List)
   - any of the packages listed under [Packages](#packages)

### Requirements

- **ReaImGui** — needed by the GUI scripts; install with ReaPack (*ReaTeam Extensions* repository, included by default).
- **SWS Extension** — optional; a few features use it (e.g. *Retain Glue Cues*, Session Fix's Off grid).
- **js_ReaScriptAPI** — needed by *Toggle Set Time Selection to Items on Right Drag*, recommended for *Toggle Track and Razor Item Link like Pro Tools*; install with ReaPack (*ReaTeam Extensions*).
- **Python 3 + OpenTimelineIO** (`pip install opentimelineio`) — only for *Conform List Browser* AAF / XML / OTIO import; EDL needs nothing extra. AAF also needs **aaftool** from LibAAF.
- **BWF MetaEdit** (`bwfmetaedit` command-line tool) — optional; only needed for timecode (BWF TimeReference) embedding.

### Moving from hsuanice/PublicBeta

This repository replaces `hsuanice/PublicBeta`, which is no longer updated.
Both install to the same folder, so remove PublicBeta first:

1. **Extensions > ReaPack > Manage repositories**, right-click **hsuanice Scripts** (PublicBeta) > **Uninstall**.
2. Import this repository and install the packages as above.

## Packages

Script names follow one pattern so they are easy to find in the Action List: the series or package name comes first
(`Hover Editing - ...`, `Auto Color - ...`), abbreviations are kept next to the full name (`Conform List Browser - CLB ...`),
and background on/off scripts start with `Toggle`.

> **Renamed on 2026-10-12.** Every script got a clearer name. If you installed an earlier version, reinstall the
> packages from ReaPack and re-assign your shortcuts / toolbar buttons. The changelog of each package lists the old name.

### Rendering

| Package | What it does |
|---|---|
| Render or Glue with Handles - RGWH | Render or glue items with handles (GUI + Glue / Render actions) |
| AudioSweet - AudioSuite Workflow | AudioSuite-style offline FX processing, Pro Tools style (GUI + Run / Toggle Preview / Toggle Solo, FX Alias tools) |

### Items Editing

| Package | What it does |
|---|---|
| Hover Editing | Pro Tools-style Split / Trim at the mouse or edit cursor (Toggle Hover Mode, Split, Trim or Extend Left / Right Edge) |
| Reorder - Sort Items Vertically | Vertical reorder and sort of selected items by metadata (GUI + Copy to Sort / Sort in Place / Upfill) |
| Session Fix | Session Fix - Interchange Prep: one window that checks and fixes a session before converting it with Interchanger (Pro Tools / Nuendo / Cubase) — checklist, Fix All, before / after check, review tracks (ReaImGui; replaces the five earlier Session Fix scripts) |
| Copy / Cut Items and Envelope Points Respect Razor | Copy or cut items and envelope points, respecting razor edits |
| Reposition Items | Space selected items by an interval (GUI) |
| Move Selected Items to Track Under Mouse | Move items vertically, keeping their timeline position |
| Toggle Mute Item Under Mouse | Mute / unmute the item under the mouse |
| Explode Takes Across Tracks | Put each take of the selected items on its own track |
| Explode Multichannel Poly Audio to Mono Items | Split poly files into one-channel items, keeping metadata |
| Convert Empty Items to Audio Items | Keeps take names and notes |
| Copy Unmuted Child Items to Parent Folder Track | Copy unmuted child items to the folder track (checks overlaps first) |

### Items Properties

| Package | What it does |
|---|---|
| Auto Color - Items by Take Name | Color items by take-name keywords with a palette (GUI + Toggle Background Coloring, By Palette, Smart Random, Follow Track Color, All Shiny Color) |

### Selection

| Package | What it does |
|---|---|
| Toggle Track and Razor Item Link like Pro Tools | Pro Tools-style "Link Track and Edit Selection": tracks follow razor areas / item selection |
| Toggle Razor and Item Link Overlap or Contain | Razor areas select the items they overlap or fully contain |
| Toggle Set Time Selection to Items on Right Drag | After a right-button drag, the time selection follows the selected items |

### Tracks

| Package | What it does |
|---|---|
| Auto Pan LR tracks | Pan adjacent XXX_L / XXX_R track pairs hard left / right |
| Delete Selected Tracks with Warning | Safe delete: asks first when tracks have items, FX, routing or are folders |
| Show Hide Folder Child Tracks in TCP | Show or hide the children of the selected folder tracks (or of their parent) |
| Import Audio Folders to Tracks - Field Recorder | Import one folder per track; channel-split recorder files are grouped (GUI) |
| Import Audio Folders to Tracks - Music Multitrack | Import one folder per track for music multitrack sessions (GUI) |

### Metadata

| Package | What it does |
|---|---|
| Rename from Metadata | Rename the active take or the source file from BWF / iXML metadata tokens, with live preview (GUI) |
| Item List | Spreadsheet-style item tables with metadata columns: Item List Browser - ILB, Item List Editor - ILE (GUI) |
| BWF / iXML Embed Tools | Embed BWF iXML Metadata from Take 1, Embed Timecode to BWF and iXML, Embed SMPTE UMID (needs BWF MetaEdit) |

### Conform

| Package | What it does |
|---|---|
| Conform List Browser - CLB | Conform tool for EDL / AAF / XML / OTIO / subtitle lists: match source media, generate and link items, compare old / new cuts *(compare: work in progress)* (GUI + Jump Old New TC, Link REAPER Items, Load from REAPER, Reveal Item) |

### Various

| Package | What it does |
|---|---|
| Clock with Date 24H | Resizable, dockable clock window |
| Count Items and Tracks - Selection HUD | Pro Tools-style selection info: item / track counts, start / end / length |

### Library

| Package | What it does |
|---|---|
| hsuanice Library | Shared code used by the scripts above; adds nothing to the Action List |

Suggested shortcuts are listed in each package's About page in ReaPack (never assigned automatically).

*Pre-release* packages are only offered when **Enable pre-releases** is turned on in ReaPack (Extensions > ReaPack > Manage repositories > Options).

Release notes are shown in ReaPack. Older history is in [Changelogs/](Changelogs/).

## Maintaining

Rules, folder layout and the release workflow are documented in [MAINTAINING.md](MAINTAINING.md).

## Built with AI (vibe coding)

These scripts are a product of **vibe coding**: hsuanice is an audio post-production engineer, not a professional programmer.

- **hsuanice** designs every workflow, decides how each tool should behave, and tests it in real post-production work.
- **AI writes most of the code**: [Claude](https://claude.ai) by Anthropic and ChatGPT by OpenAI.
- **Claude Code** (Anthropic's AI coding agent) also helps maintain this repository: the folder structure, ReaPack packaging, version numbers, changelogs and the release workflow.

Please treat the scripts as such: try them on a copy of your project first, and keep backups of media you process.
Bug reports and feedback are very welcome — open an issue on GitHub or reply in the REAPER forum threads linked in each package.

## Credits

The scripts in this repository are designed, tested and maintained by hsuanice, with code written together with AI tools (Claude, ChatGPT).

AudioSweet is inspired by the AudioSuite-like script by Tim Chimes.
"AudioSweet" is a name originally given by Tim Chimes; this project continues to use the name in reference to his original work.
Original: "Renders selected plugin to selected media item", written for REAPER 5.1 with Lua (v1.1, 2015-12-22) —
http://timchimes.com/scripting-with-reaper-audiosuite/

Hover Editing - Toggle Hover Mode is based on / inspired by TJF's *Hover Mode Toggle* script.

Auto Color's palette (hue + per-row saturation / value) is modeled after rodilab's *Color palette* script.
Auto Color's Shiny mode follows the ShinyColor behavior of *Chroma - Coloring Tool* by OLSHALOM — https://forum.cockos.com/showthread.php?t=281516

Conform List Browser uses [OpenTimelineIO](https://github.com/AcademySoftwareFoundation/OpenTimelineIO) (Academy Software Foundation) for timeline files and [LibAAF](https://github.com/agfline/LibAAF) by agfline (aaftool) for AAF.
`Library/json.lua` is based on [rxi/json.lua](https://github.com/rxi/json.lua) (MIT License, Copyright (c) 2020 rxi); the full license notice is kept in the file.
