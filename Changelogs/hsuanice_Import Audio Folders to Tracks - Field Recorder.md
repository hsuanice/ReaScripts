# hsuanice_Import Audio Folders to Tracks - Field Recorder.lua — Changelog

(formerly `hsuanice_Import audio files per folder into separate tracks Field Recorder.lua`)

ReaImGui - Import audio: one folder per track; channel-split files go to child tracks. Sequence only.

## 26.1012.1641

- Renamed to "Import Audio Folders to Tracks - Field Recorder" (was "Import audio files per folder into separate tracks Field Recorder") as part of the 2026-10-12 naming clean-up.
- Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.

## 26.1012.1024

- First release in the hsuanice/ReaScripts repository.
- Comments translated to English.

History before 26.1012.1024 (moved out of the script header; last header version: `260405.2009 set UI font size to 125%`).

```text
v260405.2009
- Add: UI font size set to 125% (FONT_SIZE = 16) across all four windows.
       Adjust FONT_SIZE in Tunables to change.
v260405.1933
- Add: "Spot to original timecode (BWF)" checkbox in the Confirm Import dialog.
       When enabled, each imported item is spotted to its BWF start offset
       via command 40299 immediately after insertion. State persists between runs.

v260119.2125
- Add: Comprehensive DEBUG_MODE with detailed logging:
  * Channel parsing results for each file
  * Track assignment decisions
  * File insertion success/failure status
  * Folder grouping information
- Add: File output for debug logs to avoid console truncation
  * Set OUTPUT_TO_FILE = true to write to file (default: enabled)
  * Output file: Scripts/hsuanice Scripts/Tools/Import_Debug_Output.txt
  * File is cleared at each script run
- Set DEBUG_MODE = true at line 70 to enable debug output
v0.4.1.1 fix channel naming rule window size
v0.4.1
- Add: Support for filenames ending with "-<number>" (e.g. File-3.wav).
       Auto mode now tries .A%, _%, and -% (chan_from_dash + Auto path).
- Fix: Custom Rule mask parsing for "%". Corrected gsub replacement rules so
       "%" is properly converted to (%d+), with support for literal "%%".
       Also trims leading/trailing spaces automatically.
- UI: Channel naming dialog always shows Custom input and P1–P3 preset buttons.
      In Auto mode, the help text now indicates it will attempt .A%, _%, and Presets.
      Clicking a preset button auto-focuses the input field.
- Add: Lowercase ".a<number>" is now recognized the same as ".A<number>"
       (improved chan_from_A).
- Add: Pre-scans each folder’s filenames to create the required "Ch XX" child tracks
       in advance, ensuring stable child track order.
- Misc: Minor stability and wording improvements for the import progress window
        and final summary dialog.

v0.4.0 - Add: "Auto" channel naming (tries .A, then _, then Presets P1–P3; future-proof via MAX_MASK_PRESETS).
v0.3.1 - Fix: ESC closes dialogs; remembers the last setting.
v0.3.0 - Add Custom Mask Presets: 3 slots with clickable tokens; Save/Clear controls; focus returns to the custom input; presets persist via ExtState.
v0.2.1 - Fix error when using ".A" option; translate Chinese comments to English.
v0.2   - Add custom channel pattern input as the third option.
v0.1.1 - Update description.
v0.1   - Beta release.
```
