--[[
@description hsuanice Metadata Embed (BWF MetaEdit helpers)
@version 0.2.1
@author hsuanice
@noindex
@about
  Helpers to call BWF MetaEdit safely:
  - Shell quoting
  - Normalize iXML sidecar newline
  - Copy iXML/core, read/write TimeReference
  - Post-embed refresh (offline->online, rebuild peaks)

@changelog
  v0.2.1 (2025-09-12)
    - Changed: E.write_bext_umid() now requires an explicit bwfmetaedit CLI path
      and uses ExecProcess (non-blocking) instead of os.execute.
      * Usage: E.write_bext_umid(cli_path, wav_path, umid_hex)
      * CLI path can be resolved via the same logic as BWF TimeReference tool.
    - Improved: sh_wrap() and exec_shell() helpers added (consistent with TR tool).
    - Notes:
      * Only writes to BWF bext:UMID; iXML UMID is left to recorders.
      * Requires BWF MetaEdit installed and accessible (path must be provided).
    - No breaking changes besides function signature update.
]]

local E = {}
E.VERSION = "0.2.1"

-- ===== Shell wrapper / exec (same as TR tool style) =====
local IS_WIN = reaper.GetOS():match("Win")

local function sh_wrap(cmd)
  if IS_WIN then
    return 'cmd.exe /C "'..cmd..'"'
  else
    return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'" -- escape safely
  end
end

local function exec_shell(cmd, ms)
  local ret = reaper.ExecProcess(sh_wrap(cmd), ms or 20000) or ""
  local code, out = ret:match("^(%d+)\n(.*)$")
  return tonumber(code or -1), (out or "")
end

-- ===== UMID writer (explicit CLI path) =====
-- Usage: E.write_bext_umid(cli_path, wav_path, umid_hex)
function E.write_bext_umid(cli, wav_path, umid_hex)
  local G = E._G or G
  local h = tostring(umid_hex or "")
  if G and G.normalize_umid then h = G.normalize_umid(h) end
  if not h:match("^[0-9A-Fa-f]+$") or #h ~= 64 then
    return false, "UMID must be 64 hex chars"
  end
  if not cli or cli == "" then
    return false, "Missing bwfmetaedit CLI path"
  end

  local cmd = ('"%s" --UMID=%s --in-place "%s"'):format(cli, h, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return (code == 0), code, out
end

-- ===== Optional: refresh media item to force REAPER reload =====
function E.refresh_media_item_take(take)
  if not take then return end
  local item = reaper.GetMediaItemTake_Item(take)
  if item then
    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC",
      reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")) -- poke
    reaper.UpdateItemInProject(item)
  end
end

return E
