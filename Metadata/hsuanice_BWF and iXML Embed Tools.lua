--[[
@description BWF / iXML Embed Tools - write timecode, iXML / BWF metadata and SMPTE UMID into files (BWF MetaEdit)
@version 26.1012.1641
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Embed BWF iXML Metadata from Take 1.lua
  [main] hsuanice_Embed Timecode to BWF and iXML.lua
  [main] hsuanice_Embed SMPTE UMID.lua
@changelog
  - Scripts renamed as part of the 2026-10-12 naming clean-up (see the file list in @provides).
  - Reinstall the package from ReaPack and re-assign your shortcuts / toolbar buttons.
@about
  # BWF / iXML Embed Tools

  Write metadata into WAV files with the BWF MetaEdit command-line tool (bwfmetaedit):

  - Embed iXML and BWF Metadata from Take 1 to Active Take (with SMPTE UMID option)
  - Timecode Embed Tool: TimeReference to BWF + iXML, from Take 1 or the item position
  - SMPTE UMID Generate and Embed Tool (bext:UMID)

  Requires BWF MetaEdit: https://mediaarea.net/BWFMetaEdit (macOS: brew install bwfmetaedit).
--]]
-- This file only describes the package for ReaPack; it is not installed.
