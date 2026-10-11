# hsuanice Scripts

REAPER scripts for audio post-production, by hsuanice.

## Install

1. Install [ReaPack](https://reapack.com/).
2. In REAPER: **Extensions > ReaPack > Import repositories...** and paste:

   ```
   https://github.com/hsuanice/ReaScripts/raw/master/index.xml
   ```

3. **Extensions > ReaPack > Browse packages**, search for `hsuanice`, and install:
   - **hsuanice Library** (required by every script below)
   - **RGWH** and/or **AudioSweet**

### Moving from hsuanice/PublicBeta

This repository replaces `hsuanice/PublicBeta`, which is no longer updated.
Both install to the same folder, so remove PublicBeta first:

1. **Extensions > ReaPack > Manage repositories**, right-click **hsuanice Scripts** (PublicBeta) > **Uninstall**.
2. Import this repository and install the packages as above.

## Packages

| Package | Category | What it does |
|---|---|---|
| RGWH | Rendering | Render or glue items with handles (GUI + Glue / Render shortcuts) |
| AudioSweet | Rendering | AudioSuite-style workflow in REAPER, Pro Tools style (GUI + Run / Preview / Solo shortcuts, FX Alias tools) |
| hsuanice Library | Library | Shared code used by the scripts above; adds nothing to the Action List |

Release notes are shown in ReaPack. Older history is in [Changelogs/](Changelogs/).

## Credits

The scripts in this repository are created and maintained by hsuanice, with the assistance of AI tools such as ChatGPT and Claude.

AudioSweet is inspired by the AudioSuite-like script by Tim Chimes.
"AudioSweet" is a name originally given by Tim Chimes; this project continues to use the name in reference to his original work.
Original: "Renders selected plugin to selected media item", written for REAPER 5.1 with Lua (v1.1, 2015-12-22) —
http://timchimes.com/scripting-with-reaper-audiosuite/
