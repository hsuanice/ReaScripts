# hsuanice_Explode Multichannel Poly Audio to New One-channel Items Preserve Metadata.lua — Changelog

Explode Multichannel Poly Audio to New One-channel Items Preserve Metadata

## 26.1012.0736

- First release in the hsuanice/ReaScripts repository.
- Requires the "hsuanice Library" package.

History before 26.1012.0736 (moved out of the script header; last header version: `260824.1900`).

```text
260824.1900 - Preserve empty poly channels as empty mono metadata slots.
           - Each rendered mono item retains its source interleave number.
           - Prevents blank channels from inheriting Channel 1 metadata.

260712.1135 - Fixed channel 1 mapping and reduced final refresh overhead
           - Corrected mono-of-N chanmode mapping so channel 1 is no longer skipped during explode.
           - Removed an extra final arrange refresh when batch media refresh already ran.

260711.2323 - Initial version
           - Added explode -> render to new take -> metadata re-embed workflow.
           - Uses non-destructive mono-of-N explode before rendering.
           - Uses shared Metadata Embed library APIs for channel-aware metadata preservation.
```
