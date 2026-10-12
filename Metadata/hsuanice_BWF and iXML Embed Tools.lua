--[[
@description BWF / iXML Embed Tools - write timecode, iXML / BWF metadata and SMPTE UMID into files (BWF MetaEdit)
@version 26.1012.1113
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Embed iXML and BWF Metadata from Take 1 to Active Take with SMPTE UMID option.lua
  [main] hsuanice_Timecode Embed Tool.lua
  [main] hsuanice_SMPTE UMID Generate and Embed Tool.lua
@changelog
  - First release in the hsuanice/ReaScripts repository.
  - Requires the "hsuanice Library" package.
  - Requires BWF MetaEdit (bwfmetaedit).
  - Messages translated to English.
  - Timecode Embed Tool: files without iXML TimeReference fields (e.g. REAPER renders) were reported as FAIL although the BWF TimeReference was written and verified; they now report OK.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  # BWF / iXML Embed Tools

  Write metadata into WAV files with the BWF MetaEdit command-line tool (bwfmetaedit):

  - Embed iXML and BWF Metadata from Take 1 to Active Take (with SMPTE UMID option)
  - Timecode Embed Tool: TimeReference to BWF + iXML, from Take 1 or the item position
  - SMPTE UMID Generate and Embed Tool (bext:UMID)

  Requires BWF MetaEdit: https://mediaarea.net/BWFMetaEdit (macOS: brew install bwfmetaedit).
--]]
-- This file only describes the package for ReaPack; it is not installed.
