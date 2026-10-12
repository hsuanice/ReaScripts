# hsuanice_Metadata Generator.lua — Changelog

hsuanice Metadata Generator (UMID / IDs) — STRICT

## 26.1012.1113

- Released as part of the 26.1012.1113 package update.

History before 26.1012.1113 (moved out of the script header; last header version: `0.2.1`).

```text
v0.2.1 (2025-09-12)
  - Added: G.format_umid_protools_style()
    * Formats a 32-byte Basic UMID into Pro Tools display style
      (lowercase hex + dash grouping 26-6-16-12-4).
    * Useful for log/console/debug output to match Pro Tools SMPTE ID field.
  - No changes to UMID generation logic or Embed/Read compatibility.
  - Backward compatibility: existing functions unchanged.

v0.2.0
  - Strict lengths & segment layout for UMID (Basic 32B / Extended 64B)
  - Configurable UMID Universal Label (UL) constant (16B)
  - Deterministic material/instance packing (material 16B with instance folded into tail 8B)
  - Helper: G.explain_basic_layout()
  - Aliases: G.generate_umid_basic = _strict; G.generate_umid_extended = _strict
```
