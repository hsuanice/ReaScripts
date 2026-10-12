--[[
@description Rename from Metadata - rename takes or source files from BWF / iXML metadata with tokens (GUI)
@version 26.1012.1113
@author hsuanice
@metapackage
@provides
  [main] hsuanice_Rename Active Take from File Metadata.lua
  [main] hsuanice_Rename Source File from Metadata.lua
@changelog
  - First release in the hsuanice/ReaScripts repository.
  - Requires the "hsuanice Library" package.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  # Rename from Metadata

  Two GUI tools that build names from BWF / iXML metadata tokens ($trk, ${interleave}, ${chnum}, scene / take, ...)
  with a cached live preview:

  - Rename Active Take from File Metadata: take names and take notes
  - Rename Source File from Metadata: renames the media files on disk and relinks them
--]]
-- This file only describes the package for ReaPack; it is not installed.
