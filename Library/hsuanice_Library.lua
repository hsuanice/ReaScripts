--[[
@description hsuanice Library - shared code used by hsuanice scripts (required)
@version 26.1027.1553pre1
@author hsuanice
@metapackage
@provides
  [nomain] hsuanice_RGWH Core.lua
  [nomain] hsuanice_AudioSweet Core.lua
  [nomain] hsuanice_AS Preview Core.lua
  [nomain] hsuanice_Metadata Embed.lua
  [nomain] hsuanice_Metadata Read.lua
  [nomain] hsuanice_Hover.lua
  [nomain] hsuanice_Mouse.lua
  [nomain] hsuanice_Metadata Cache.lua
  [nomain] hsuanice_Metadata Rename Core.lua
  [nomain] hsuanice_List Table.lua
  [nomain] hsuanice_Time Format.lua
  [nomain] hsuanice_Metadata Generator.lua
  [nomain] hsuanice_CLB Compare Engine.lua
  [nomain] hsuanice_EDL Parser.lua
  [nomain] hsuanice_Session Fix Core.lua
  [nomain] hsuanice_OTIO Bridge.lua
  [nomain] hsuanice_Subtitle Bridge.lua
  [nomain] hsuanice_Process Exec.lua
  [nomain] hsuanice_Fade Tool Core.lua
  [nomain] json.lua
@changelog
  - Fade Tool Core: Fix: a razor over several tracks no longer pulls cuts into tracks where it only covers empty space or the middle of an item (e.g. extending both items of a gap) when other tracks have cuts or item edges in the razor.
@about
  # hsuanice Library

  Shared code used by hsuanice scripts (RGWH, AudioSweet, Hover Mode, Reorder, Rename / Item List / Embed tools, Conform List Browser, ...).
  Install this package together with any hsuanice script.
  It adds nothing to the Action List.
--]]
-- This file only describes the package for ReaPack; it is not installed.
