# hsuanice_Auto Color Items by Take Name.lua — Changelog

Auto Color Items by Take Name

## 26.1012.0930

- First release in the hsuanice/ReaScripts repository.
- Includes: GUI, Background Daemon, by Palette, Smart Random, Follow Track Color, All ShinyColor (all share the GUI's settings).
- Fix: the settings folder is now created with REAPER's API, so saving also works on Windows.
- Fix: All Shiny (GUI button and All ShinyColor script) no longer re-colors items in the black / gray / white row that are already Shiny.

History before 26.1012.0930 (moved out of the script header; last header version: `261002.1042`).

```text
v261002.1042
- Fix: "All Shiny" was re-pastelizing items that were already Shiny (background recomputed from
  the already-pale background instead of the true peak color), so running it repeatedly faded
  every colored item out more each time. Now detects "already shiny" by checking whether the
  background's hue matches the peak's hue and its saturation is meaningfully lower (the shiny
  formula's signature) and leaves those items alone instead of reprocessing them.
- Change: "All Shiny" now converts just the selected items when any are selected (consistent with
  Palette/Random/Follow); only falls back to the whole project — with an OK/Cancel confirmation
  prompt — when nothing is selected.

v261002.1021
- Add: "All Shiny" function button (Functions row, right of Follow) — forces every colored item
  in the whole project to Shiny color, regardless of current selection or the global Normal/Shiny
  mode setting. Items with no custom color are left alone. One-shot convert-once action: an item
  already in Shiny mode has no stored flag saying so, so re-running it on already-shiny items will
  re-derive the pastel background from the existing pastel background rather than skip it.
- Add: standalone "Auto Color All ShinyColor" wrapper script for Action-List/toolbar use, matching
  the existing Palette / Smart Random / Follow Track Color wrappers.

v260918.1411
- Fix: adding the Follow Track Color function pushed the script over Lua's 200-local-per-function
  limit ("too many local variables ... in main function near 'in'" on load). Grouped
  do_palette_flow_color / do_smart_random_color / do_follow_track_color and their Smart-Random-only
  helper functions (weighted_rgb_distance, hue_gap_degrees, smart_color_distance, shuffled_indices,
  is_grayscale_color, non_grayscale_palette_indices, shuffled_values) into one shared `do...end`
  block with forward-declared locals for the three functions, so the helpers' local slots are
  freed when the block ends instead of staying live for the rest of the file.

v260918.1405
- Add: Follow Track Color function — colors selected items (or all items if none selected) to
  match their own track's current custom color; tracks without a custom color are left
  unchanged. Only applies to items (Target: Tracks shows a reminder and does nothing), since a
  track following its own color has no meaning.
- Add: standalone "Auto Color Follow Track Color" wrapper script for Action-List/toolbar use,
  matching the existing Auto Color by Palette / Smart Random wrappers.
- Change: moved the Palette / Random / Follow function buttons out of the crowded Take
  Name/Track Name toggle row and into the Types: sub-bar (right of the MIDI checkbox), under a
  new "Functions:" label, with shorter button labels (Palette / Random / Follow)

v260908.1427
- Change: BG Bright / BG Sat now only take effect in Shiny mode (Normal mode's background is
  left exactly as before — raw palette color, or Match/Black/White/Theme secondary). Only
  Shiny mode's pastel background formula was ever the thing getting washed out by REAPER's
  razor-edit selection highlight, so that's the only case this setting should touch.

v260908.1424
- Fix: BG Bright / BG Sat sliders were marked `dirty`, which made the Settings panel call
  gen_palette()+save_palette() on every drag — silently regenerating and overwriting the whole
  color palette (losing custom/imported swatch colors) instead of only affecting how background
  color is rendered. Now persists via save_pconf() directly, like Normal target/Other color/mode.

v260908.1404
- Add: BG Bright / BG Sat sliders in Settings panel — scale item background Value/Saturation
  (0-200%, default 100% = no change) independent of Normal/Shiny mode, to give headroom against
  REAPER's razor-edit selection highlight blowing out very pale (e.g. Shiny mode) backgrounds
- Change: settings persisted to ExtState as bg_brightness_scale / bg_saturation_scale so
  Auto Color Daemon, Auto Color by Palette, and Auto Color Smart Random follow automatically

v260806.2303
- Add: keyword export/import now explicitly supports separate Take Name and Track Name targets with dedicated file defaults
- Change: Smart Random now excludes grayscale/low-saturation swatches to avoid overly similar color assignments
- Fix: Take/Track keyword tab switching now correctly updates palette keyword display and editing target

v260806.1959
- Change: hover info now shows HEX, RGB, and CMYK for palette swatches in that order
- Change: Edit Color now provides separate HEX, RGB, and CMYK input fields, with the last non-empty field taking priority

v260806.1949
- Change: adjust built-in default 3x8 palette colors to the latest provided values
- Change: update Recording Auto Color fixed 10-color set to the latest provided sequence

v260806.1940
- Change: built-in default color palette is now a fixed 3x8 RGB set matching the updated custom default palette
- Change: Reset Default and first-run palette initialization now use the same fixed palette

v260806.1921
- Add: right-click swatch Edit Color action with HEX, RGB, and CMYK input support
- Change: color parsing is now shared between swatch editing and color-list import

v260806.1841
- Change: Import Colors now accepts RGB values (R,G,B and rgb(R,G,B)) in addition to hex
- Fix: tabular import parser no longer splits RGB triplets by comma

v260806.1828
- Change: Recording Auto Color fixed set now uses white instead of gray for the final slot

v260806.1819
- Change: Import Colors now reads tabular hex rows and regenerates palette rows/cols from file content
- Change: importing colors disables the extra grey row so imported dimensions match exactly (e.g. 2x8)

v260806.1812
- Add: Import Colors button for loading a text list of hex colors into the current palette grid order
- Change: imported palette colors are persisted in palette_v3 and preset files
- Change: preset panel footer now exposes Import Colors / Import Keywords buttons

v260806.1728
- Change: Recording Auto Color now groups by recording base name (e.g. vocal, guitar) and assigns sequences per group
- Add: Reset Seq button to clear recording color sequence state manually
- Change: recording sequence no longer resets when item is moved to another track; it stays tied to recording name

v260806.1650
- Change: rollback to pre-custom-palette behavior (palette remains generator-driven)
- Change: remove per-swatch manual color edit/reset and custom-color preset binding
- Change: restore preset UI wording to "Presets" / "Save Preset"

v260806.1644
- Fix: Recording Auto Color no longer re-colors already-colored takes at recording stop when take GUIDs finalize
- Change: Preset UI labels clarified for palette workflow (toolbar "Palette", button "Save Palette")
- Add: Preset panel hint text "Click preset name to load"

v260806.1633
- Add: per-swatch color editing via right-click (Edit Color, accepts HEX #RRGGBB or RGB R,G,B)
- Add: per-swatch reset to generated default color (Reset Color)
- Change: presets now bind full palette state (color + keyword + custom flag), not keyword only
- Change: palette_v3 save/load now persists per-cell custom-color flags and remains backward-compatible with older data

v260806.1624
- Change: Recording Auto Color now uses 10-color loop: bright red/yellow/green/blue/purple, then dark red/yellow/green/blue/purple
- Change: Orange/indigo and grayscale are excluded from recording auto-color sequence for clearer visual separation

v260806.1615
- Change: Recording Auto Color now loops a high-contrast six-color set (red/orange/yellow/green/blue/purple)
- Change: Exclude grayscale/low-saturation colors from recording auto-color pool
- Change: Indigo-adjacent ambiguity reduced by target-hue mapping for better visual separation

v260806.1605
- Change: Recording Auto Color now uses session lineage order (new take #1, #2, #3...) across tracks
- Fix: Loop recording on the same track/range now colors new takes individually (take GUID based)
- Fix: Moving recorded items to other edit tracks no longer causes Recording Auto Color re-calculation
- Change: Recording Auto Color applies take color directly and updates active item background by mode

v260806.1546
- Change: Recording Auto Color is now a checkbox on the main Colors/List action row
- Fix: Recording Auto Color now scans only rec-armed tracks (no full-project scan)
- Fix: Recording scan is throttled (~100ms interval) to reduce CPU load
- Fix: On recording stop, run one finalize pass so the just-finished last item is colored immediately

v260806.1500
- Add: Safety Mode option in Settings (enabled by default)
- Add: Auto safety trigger when any track is record-armed or project is recording
- Safety action: auto-save current preset (or create "Safety Backup" when unsaved), then switch to Default preset
- Add: safety_mode to persisted state file and ExtState preferences

v260806.1422
- Add: Auto Color by Palette button in the Colors/List row
- Add: Palette pattern setting with Row Repeat (default) and Full modes
- Change: Rename Palette Flow to Auto Color by Palette
- Add: Smart Random coloring mode that avoids similar adjacent colors for better readability
- Add: Selected-color swatch highlight (supports both Normal and Shiny mode matching)

v260804.1623
- Add: ShinyColor mode (Pro Tools-like) toggle in toolbar — writes take peak color and applies a lighter item background color for readability
- Change: all apply paths now follow mode behavior (Auto Color, swatch click, List View click, Paste Color)
- Change: Remove Color now clears item color and all take colors

v260425.1857
- Fix: Export Keywords failed with "Could not write to: 1" — JS_Dialog_BrowseForSaveFile returns (retval, fileName); only the retval (1) was being captured as the path. Now captures both return values correctly.

v260325.1752
- Add: file-based state persistence — all presets, keywords, and prefs saved to hsuanice Scripts/Tools/hsuanice_AutoColorItems_state.dat on script exit and on every explicit "Save Preset"
- On startup: file is loaded first so ExtState is repopulated even if reaper-extstate.ini was lost across REAPER restarts

v260325.1647
- Fix: startup no longer overwrites palette_v3 keywords with (possibly older) saved preset — load_preset() now only fires as fallback when palette_v3 has no keywords at all
- Add: Export / Import buttons in List View footer — tab-separated text file (hex_color TAB keyword, one line per palette entry)
- Export uses native macOS/Windows save dialog via js_ReaScriptAPI (JS_Dialog_BrowseForSaveFile); falls back to text-input if extension not installed
- Import/Export default location is the REAPER session (.rpp) folder, not the media recording folder

v260325.1620
- Fix: add atexit handler to flush palette + pconf to ExtState when script exits (guards against data lost on normal close without prior save_pconf trigger)
- Fix: save_pconf() called immediately on startup (so last_preset is always current after init)
- Fix: clicking Default preset now immediately persists last_preset = "Default" to prevent stale restore on next open

v260325.1605
- Fix: saved preset now reliably restored on script reopen — startup now calls load_preset() directly instead of relying on palette_v3 (which could become stale)
- Fix: saving a preset (Save Preset button) now also persists last_preset so it survives reopen even without any other settings change

v260324.1912
- Fix: Daemon no longer slows REAPER on track selection — debounce added (15-frame stable window before recolor); GUI settings polled every 10 frames instead of every frame
- Add: Audio / Empty / MIDI item-type filter checkboxes always visible below toolbar (not gated on Auto Color)
- Fix: Auto Color checkbox restored to toolbar
- Fix: Empty items (audio take with no source file) correctly skipped when Empty is unchecked

v260324.1800
- Add: Collapse button (▾/▴) in toolbar — shrinks window to a single bar for unobtrusive background use; state persisted
- Add: Background Daemon script (hsuanice_Auto Color Daemon.lua) — headless, no window, reads GUI settings in real time; toggle state (on/off checkmark) shown in Action List and toolbar buttons via SetToggleCommandState

v260324.1434
- Fix: last active preset now correctly restored on script reopen (was a Lua scoping bug — current_preset declared after save/load_pconf, so they accessed separate globals)
- Fix: CJK characters in color swatches now vertically centered (was offset low due to ASCII-only line height measurement)
- Add: "Preview chars" setting in Settings panel to control how many characters show per keyword segment in Color View (range 1–9, persisted)
- Change: Auto Update now defaults to ON at startup
- Change: Auto Color always starts OFF at startup (prevents accidental coloring before user is ready)

v260324.1407
- Fix: Chinese/CJK characters in color swatches now render correctly (was garbled due to byte-level sub)
- Change: color swatch now shows first 3 characters of each keyword segment (was 1)

v260324.1349
- Fix: mouse wheel scrolling now works in List View (was consumed by color grid before reaching list)
- Add: font size control in Settings panel (Font − / +, range 8–24pt, persisted)

v260324.1340
- Fix: Paste Color button now correctly previews the copied color (was dividing by 255 twice)
- Add: Paste Color button — applies copied color to all selected items; button background shows the copied color
- Add: List View — toggle between ⊞ Colors (palette grid) and ≡ List (scrollable keyword editor)
- List View: each row shows color swatch, hex code, and keyword; left-click applies, right-click edits
- Fix: default window width widened to 620px to prevent toolbar button overlap

v260324.1225
- Fix: Preset panel open/closed state now saved across sessions (was always resetting to closed on restart)
- Add: Right-click preset → Rename option (in addition to existing Delete)

v260324.0451
- Add: Preset panel — save/load/delete named presets; all presets stored in ExtState
- Add: Built-in "Default" preset that clears all keywords
- Add: Preset name + save status (● clean / * dirty) displayed in toolbar
- Add: Auto Update checkbox — auto-saves to current preset on any change
- Add: Confirm dialog before deleting a preset (right-click)
- Add: Grey row toggle (white → black grayscale) in Settings panel
- Add: Settings and Presets panels auto-resize window; palette area never compressed
- Fix: Window size and position now remembered across sessions
- Fix: Active buttons (Settings, Presets) show dark background + green underline, white text
- Fix: Keyword matching uses longest-match-wins — "NAN" beats "NA"
- Fix: Cells always show at full brightness regardless of keyword assignment
- Remove: "Apply to Selected" button
- Change: "Clear Selected" renamed to "Remove Color" (removes custom color from selected items)
v260324.0403
- Redesign: config-driven palette generator (Hue offset, Span, Sat/Val per row)
- Add: interactive sliders for all palette parameters, live preview
- Add: Settings panel (toggle with ⚙ button)
- Remove: manual Add Color / Generate Gradient — palette fully driven by config
- Remove: color labels — cells show keyword only
- Simplify: right-click popup → Edit Keyword / Clear Keyword
v260324.1700
- Add: dynamic palette — add/remove/edit individual swatches
- Add: Generate Gradient, Columns +/−, right-click context popup
v260324.1600
- Redesign: palette-first UX
v260324.1500
- Rewrite: GFX library replaces ReaImGui
```
