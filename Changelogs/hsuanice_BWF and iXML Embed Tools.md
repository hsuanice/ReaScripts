# hsuanice_BWF and iXML Embed Tools.lua — Changelog

BWF / iXML Embed Tools - write timecode, iXML / BWF metadata and SMPTE UMID into files (BWF MetaEdit)

## 26.1012.1113

- First release in the hsuanice/ReaScripts repository.
- Requires the "hsuanice Library" package.
- Requires BWF MetaEdit (bwfmetaedit).
- Messages translated to English.
- Timecode Embed Tool: files without iXML TimeReference fields (e.g. REAPER renders) were reported as FAIL although the BWF TimeReference was written and verified; they now report OK.

