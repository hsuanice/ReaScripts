--[[
@description hsuanice Metadata Embed (BWF MetaEdit helpers)
@version 0.1.0
@author hsuanice
@noindex
@about
  Helpers to call BWF MetaEdit safely:
  - Shell quoting
  - Normalize iXML sidecar newline
  - Copy iXML/core, read/write TimeReference
  - Post-embed refresh (offline->online, rebuild peaks)
]]
local E = {}
E.VERSION = "0.1.0"

-- TODO: sh_quote, normalize_ixml_text, bwfme_exec, read_TR, write_TR, refresh_project_peaks ...

return E
