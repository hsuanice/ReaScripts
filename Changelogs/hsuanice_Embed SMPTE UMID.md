# hsuanice_Embed SMPTE UMID.lua — Changelog

(formerly `hsuanice_SMPTE UMID Generate and Embed Tool.lua`)

SMPTE UMID Generate & Embed Tool (bext:UMID only)

## 26.1012.1641

- Renamed to "Embed SMPTE UMID" (was "SMPTE UMID Generate and Embed Tool") as part of the 2026-10-12 naming clean-up.

## 26.1012.1113

- Released as part of the 26.1012.1113 package update.

History before 26.1012.1113 (moved out of the script header; last header version: `250924_2319 fix library path`).

```text
v0.1.4.1 (2025-09-13)
  - Fix: Always call ImGui_End() after ImGui_Begin(), regardless of
    the 'visible' flag. Prevents "ImGui_SameLine: expected a valid
    ImGui_Context*" on ReaImGui 0.9.3.2 and ensures proper stack
    balance when the window is collapsed/hidden.
  - No change to UMID generation/embedding; purely UI stability.
  - Fix reaper.ImGui_End(ctx)
v0.1.4 (2025-09-12)
  - Updated: Debug output now displays the actual command string
    returned from E.write_bext_umid(), instead of reconstructing it.
  - Removed: hard-coded "--in-place" text in DEBUG CMD log.
    Output now always reflects the exact CLI command executed.
  - Improved: avoids confusion when library behavior changes,
    ensures tool log is faithful to real CLI usage.
  - No changes to generation, verification, or strategy logic.

v0.1.3 (2025-09-12)
  - Console behavior now mirrors the iXML+BWF tool:
    * Console opens and is cleared at the start of the Run (do_embed),
      not at script launch. Keeps run logs clean and consistent.
  - Includes detailed write-step debug (CMD/CODE/OUT).
  - No changes to UMID generation or CLI resolution logic.
v0.1.2 (2025-09-12)
  - Added: detailed debug logging for write step (DEBUG CMD/CODE/OUT).
  - No change to generation logic or verification.
v0.1.1 (2025-09-12)
  - Fixed: Updated call to E.write_bext_umid() to use new signature
    (cli_path, wav_path, umid_hex).
  - Added: Normalize and sanitize UMID before writing, plus DEBUG length/hex check.
v0.1.0
  - Initial: UI (ReaImGui / fallback prompt), batch over selected items,
    per-item verification, summary & optional refresh.
```
