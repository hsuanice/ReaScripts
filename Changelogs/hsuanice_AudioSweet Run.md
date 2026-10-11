# hsuanice_AudioSweet Run.lua — Changelog

AudioSweet Run

History before 26.1011.2142 (moved out of the script header; last header version: `0.2.5`).

```text
0.2.5 [261011.1053]
  - ADDED: Syncs "Retain Glue Cues" → AS_RENDER_KEEP_GLUE_CUES (AudioSweet Core >= 0.3.8)

0.2.4 [261010.1609]
  - ADDED: Syncs "Single item: Render (keep takes)" → AS_SINGLE_ITEM_RENDER (AudioSweet Core >= 0.3.6)

0.2.3 [261010.1547]
  - ADDED: Syncs GUI glue grouping (Settings → Glue) to AudioSweet Core
    • AS_GLUE_GROUPING / AS_GLUE_SPLIT_AT_CROSSFADES / AS_GLUE_MUTED_SEPARATE
    • Requires AudioSweet Core >= 0.3.5 and RGWH Core >= 0.3.10

0.2.2 [260330.1809]
  - ADDED: Auto track FX chain online/offline restore on run
    • Before executing AudioSweet Core: brings FX chain track online if offline (I_FXEN or per-FX offline bits)
    • After execution: restores original offline state
    • Normal mode: resolves FX track from chain window or focused FX
    • Preview mode: resolves from focused FX (focused mode) or preview target track (chain mode)

0.2.1 (2026-02-09) [internal: v260209.2130]
  - FIXED: Cross-platform path resolution for Windows/Linux compatibility
    • Replaced debug.getinfo() relative path with reaper.GetResourcePath() absolute path
    • Fixes "attempt to concatenate a nil value (local 'SCRIPT_DIR')" on Windows
  - FIXED: Debug log path on Windows (os.getenv("HOME") returns nil)
    • Added os.getenv("USERPROFILE") fallback for Windows

0.2.0 (2025-12-23) [internal: v251223.2256]
  - CHANGED: Version bump to 0.2.0 (public beta)

0.1.2 (2025-12-23) [internal: v251223.1924]
  - CHANGED: Added Copy+Apply action name support for GUI/Core integration

0.1.1 (2025-12-22) [internal: v251222.1706]
  - CHANGED: All executions now produce single undo operation
    • External undo control enabled before calling AudioSweet Core
    • AudioSweet Core v0.1.7: Skips internal undo when EXTERNAL_UNDO_CONTROL="1"
    • Cleaner undo stack (one "AudioSweet Run (Normal/Preview)" entry)
    • Matches GUI v0.1.24 behavior for consistent user experience

0.1.0 (2025-12-21) [internal: v251221.1803]
  - ADDED: Sync GUI settings to AudioSweet Core + RGWH Core before execution
    • Apply/Copy action, copy scope/pos now set in hsuanice_AS ExtState
    • File naming settings now set in hsuanice_AS ExtState
    • Channel mode now set in hsuanice_AS (AS_APPLY_FX_MODE)
    • Handle seconds now set in RGWH project ExtState
  - ADDED: Optional debug file log on Desktop (Console + file)
  - COMPLETE: Unified AudioSweet execution script with automatic mode detection
  - Normal Mode: Intelligent window detection system
    • Chain FX window focused → Chain mode (full FX chain processing)
    • Single FX floating window → Single FX mode (isolated FX processing)
    • No FX window → Chain mode on default preview target track
    • Window state detection via GetFocusedFX + TrackFX_GetChainVisible + TrackFX_GetOpen
    • Window state always takes priority over GUI settings
    • Sets correct ExtState for AudioSweet Core: "hsuanice_AS/AS_MODE" = "focused"|"chain"
    • Sets OVERRIDE ExtState for chain mode without focused FX
  - Preview Mode: Complete workflow for preview execution
    • Detects placeholder items (note format: "PREVIEWING @ Track <n> - <FXName>")
    • Validates item selection on preview target track
    • Stops preview: deletes placeholder, unsolo all
    • Executes RGWH Core on selected items
    • Moves rendered results back to original source track
    • Stays in normal state (no preview restoration)
    • Respects time selection for RGWH scope determination
  - Integration:
    • Reads all settings from AudioSweet GUI ExtState ("hsuanice_AS_GUI" namespace)
    • Supports GUID-based track lookup for duplicate track names
    • Compatible with AudioSweet Core OVERRIDE mechanism
  - Debug Mode: Optional detailed logging (set DEBUG = true)
  - Single script for unified workflow - no manual mode switching needed

[internal: v251221.1556]
  - FIXED: Correct ExtState namespace and key for AudioSweet Core integration
    • Changed from "hsuanice_AS_GUI/mode" to "hsuanice_AS/AS_MODE"
    • Mode values changed from numeric (0/1) to string ("focused"/"chain")
    • Resolves issue where chain mode was executing as focused mode
  - DEBUG: Added MessageBox debug output (later removed - caused execution interference)

[internal: v251221.1158]
  - Initial implementation of unified AudioSweet Run script
  - Placeholder detection for Normal vs Preview mode split
  - Basic window detection logic (later revised for correct priority)
```
