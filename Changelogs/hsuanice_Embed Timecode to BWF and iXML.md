# hsuanice_Embed Timecode to BWF and iXML.lua — Changelog

(formerly `hsuanice_Timecode Embed Tool.lua`)

Embed Timecode to Active take (BWF + iXML) from Take 1 or Current Position

## 26.1012.1641

- Renamed to "Embed Timecode to BWF and iXML" (was "Timecode Embed Tool") as part of the 2026-10-12 naming clean-up.

## 26.1012.1113

- Released as part of the 26.1012.1113 package update.
- Fix: files without iXML TimeReference fields (e.g. REAPER renders) were reported as FAIL although the BWF TimeReference was written and verified; they now report OK.

History before 26.1012.1113 (moved out of the script header; last header version: `260125.0100`).

```text
v260125.0100
  - NEW: Integrated iXML TimeReference writing
  - Now writes to ALL TC-related metadata fields:
    * BWF BEXT TimeReference (for standard BWF compatibility)
    * iXML BEXT/BWF_TIME_REFERENCE_LOW (REAPER reads this)
    * iXML SPEED/TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO (Wave Agent reads this)
  - Ensures perfect TC sync across all metadata fields
  - Based on hsuanice_BWF TimeReference Embed Tool.lua v260124.0020

Previous versions (from BWF TimeReference Embed Tool):
v260124.0020
  - Added file location check: warns when files are outside project folder
v260123.2330
  - CRITICAL FIX: Items set offline BEFORE writing to allow file modification
  - Changed UI from ReaImGui to native GFX library
  - Fixed Option 2 calculation with project time offset
v250924_1930
  - Sample-accurate TimeReference calculation
  - Double-precision math with floor quantization
```
