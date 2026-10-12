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
- **SWS Extension** — optional; a few features use it (e.g. *Retain Glue Cues*).
- **js_ReaScriptAPI** — needed by *Set Time to Item on Right-Drag Release*, recommended for *Track and Razor Item Link*; install with ReaPack (*ReaTeam Extensions*).
- **BWF MetaEdit** (`bwfmetaedit` command-line tool) — optional; only needed for timecode (BWF TimeReference) embedding.

### Moving from hsuanice/PublicBeta

This repository replaces `hsuanice/PublicBeta`, which is no longer updated.
Both install to the same folder, so remove PublicBeta first:

1. **Extensions > ReaPack > Manage repositories**, right-click **hsuanice Scripts** (PublicBeta) > **Uninstall**.
2. Import this repository and install the packages as above.

## Packages

### Rendering

| Package | What it does |
|---|---|
| RGWH | Render or glue items with handles (GUI + Glue / Render shortcuts) |
| AudioSweet | AudioSuite-style workflow in REAPER, Pro Tools style (GUI + Run / Preview / Solo shortcuts, FX Alias tools) |

### Items Editing

| Package | What it does |
|---|---|
| Hover Mode | Pro Tools-style Split / Trim at the mouse or edit cursor (Toggle, Split, Trim Left / Right) |
| Reorder | Vertical reorder and sort of selected items (GUI + Copy to Sort / Sort in Place / Upfill) |
| Fix Tools | Clean up edits before moving a session to Pro Tools or Nuendo (edges off grid, looped sources, crossfades, overlaps, fades) |
| Copy / Cut with Razor | Copy or cut items and envelope points, respecting razor edits |
| Item Reposition | Reposition selected items by interval (GUI) |
| Move selected items to track under mouse | Move items vertically, keeping their timeline position |
| Toggle Mute Item under Mouse Cursor | Mute / unmute the item under the mouse |
| Explode takes of items across tracks | Put each take of the selected items on its own track |
| Explode Multichannel Poly Audio | Split poly files into one-channel items, keeping metadata |
| Convert empty items to audio items | Keep names and notes |
| Copy Unmuted Child Items to Parent Folder Track | Copy unmuted child items to the folder track (checks overlaps first) |

### Items Properties

| Package | What it does |
|---|---|
| Auto Color | Color items by take-name keywords with a configurable palette (GUI + Background Daemon, by Palette, Smart Random, Follow Track Color, All ShinyColor) |

### Selection

| Package | What it does |
|---|---|
| Track and Razor Item Link like Pro Tools | Pro Tools-style "Link Track and Edit Selection": tracks follow razor areas / item selection (toggle) |
| Razor and Item Link with Mode Switch | Razor areas select the items they overlap or fully contain (toggle) |
| Set Time to Item on Right-Drag Release | After a right-button drag, the time selection follows the selected items (toggle) |

### Library

| Package | What it does |
|---|---|
| hsuanice Library | Shared code used by the scripts above; adds nothing to the Action List |

Suggested shortcuts are listed in each package's About page in ReaPack (never assigned automatically).

Release notes are shown in ReaPack. Older history is in [Changelogs/](Changelogs/).

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

Hover Mode Toggle is based on / inspired by TJF's *Hover Mode Toggle* script.

Auto Color's palette (hue + per-row saturation / value) is modeled after rodilab's *Color palette* script.
Auto Color's Shiny mode follows the ShinyColor behavior of *Chroma - Coloring Tool* by OLSHALOM — https://forum.cockos.com/showthread.php?t=281516
