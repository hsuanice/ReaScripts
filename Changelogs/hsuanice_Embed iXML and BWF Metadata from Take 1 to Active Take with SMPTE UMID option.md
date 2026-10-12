# hsuanice_Embed iXML and BWF Metadata from Take 1 to Active Take with SMPTE UMID option.lua — Changelog

hsuanice_Embed iXML and BWF Metadata from Take 1 to Active Take with SMPTE UMID option

## 26.1012.1113

- Released as part of the 26.1012.1113 package update.

History before 26.1012.1113 (moved out of the script header; last header version: `260718.1910`).

```text
260718.1910 - Switched embed pipeline to shared Metadata Embed API
           - iXML/CORE/TR copy now calls hsuanice_Metadata Embed.lua (single source of truth).
           - Keeps set_embedder disabled in this script to preserve richer original iXML metadata.
           - Reduces logic drift between this script and explode/render workflows.

260718.1703 - Improved iXML copy reliability with post-import verification
           - Added strict verify step: export iXML from destination and validate sidecar existence/content.
           - Missing source sidecar now returns FAIL (no longer treated as success).
           - Fixed nil-call runtime errors from function declaration order.
           - Corrected channel mapping to prioritize TRACK_LIST order (interleave-safe).
           - Preserved rich non-channel metadata while patching only channel-related iXML fields.
           - Added detailed diagnostics for source/destination paths and iXML verification output.

260711.2204 - Added channel-aware metadata embed for mono-of-N items
           - Detects active take I_CHANMODE interleave index and resolves the matching track name.
           - iXML TRACK_LIST/TRKALL/TRK1 are patched to the selected channel name before embed.
           - CORE channel field ITCH now follows the selected channel name instead of full TRKALL text.

260126.1737 - Added "Start" and "Start & Close" buttons
           - "Start" runs the process and keeps window open for multiple runs
           - "Start & Close" runs and closes the window (previous behavior)
           - Renamed "Cancel" to "Close" for clarity

260126.1545 - Improved error messages with detailed skip reasons
           - Now shows exact cause: src/dst path nil, not WAV, or file not found
           - Displays full path in error message for easier debugging

260126.1533 - Initial release
           - Merged from "Embed iXML and BWF Metadata from Take 1 to Active Take" v0.3.5
           - Added SMPTE UMID generation option with 3 strategies:
             1) Copy if present, Generate if missing
             2) Always generate new
             3) Patch missing only
           - Changed GUI from ReaImGui to native gfx library
           - Dark theme UI with checkbox for UMID option
```
