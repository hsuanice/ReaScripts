--[[
@description hsuanice Metadata Embed (BWF MetaEdit helpers)
@version 0.2.0
@author hsuanice
@noindex
@about
  Helpers to call BWF MetaEdit safely:
  - Shell quoting
  - Normalize iXML sidecar newline
  - Copy iXML/core, read/write TimeReference
  - Post-embed refresh (offline->online, rebuild peaks)


@changelog
  v0.2.0 (2025-09-12)
    - Added: E.write_bext_umid(wav_path, umid_hex)
      * Embed a 32-byte Basic UMID (64 hex characters) into the BWF bext:UMID field.
      * Uses BWF MetaEdit CLI: --UMID=<hex> --in-place.
      * Only writes to the bext chunk; iXML UMID is left to recorders.
    - Added: sh_quote() and bwfme_exec() helpers
      * POSIX-safe shell quoting for file paths and arguments.
      * Simple wrapper for calling bwfmetaedit (can be replaced with async implementation).
    - Added: E.refresh_media_item_take(take)
      * Forces REAPER to refresh item/take after metadata embedding
        (poke + UpdateItemInProject).
    - Notes:
      * Requires BWF MetaEdit to be installed and accessible from system PATH.
      * Recommended to pair with hsuanice_Metadata Generator.lua >= v0.2.1
        for strict UMID generation and Pro Tools style formatting.
    - No breaking changes:
      * Does not affect existing TimeReference or other metadata helpers;
        only adds UMID writing capability.
  
]]
local E = {}
E.VERSION = "0.2.0"

-- TODO: sh_quote, normalize_ixml_text, bwfme_exec, read_TR, write_TR, refresh_project_peaks ...

-- ===== shell quoting =====
local function sh_quote(s)
  s = tostring(s or "")
  if s == "" then return "''" end
  -- POSIX-safe quoting
  return "'" .. s:gsub("'", [['"'"']]) .. "'"
end

-- ===== BWF MetaEdit wrapper =====
local function bwfme_exec(args_tbl)
  -- 你自己的尋路邏輯：假設系統已可直接呼叫 bwfmetaedit
  local cmd = "bwfmetaedit " .. table.concat(args_tbl, " ")
  -- 注意：在 REAPER 裡用 os.execute 會阻塞；若你已有非阻塞封裝，改成你的
  return os.execute(cmd)
end

-- ===== UMID writer =====
function E.write_bext_umid(wav_path, umid_hex)
  -- 正規化：嵌入建議用「raw 64 hex（大寫或小寫皆可）」；我們統一用大寫
  local G = E._G or G  -- 若外部已載入 Generator，可經由 E._G 傳入；否則用全域 G
  local h = tostring(umid_hex or "")
  if G and G.normalize_umid then h = G.normalize_umid(h) end
  -- 基本長度檢查（64 hex）
  if not h:match("^[0-9A-Fa-f]+$") or #h ~= 64 then
    return false, "UMID must be 64 hex chars"
  end
  -- --UMID=<hex> 寫進 bext；--in-place 直接覆寫
  local ok = bwfme_exec({
    "--UMID=" .. h,
    "--in-place",
    sh_quote(wav_path),
  })
  return ok == true or ok == 0, ok
end

-- （可選）如果你也要同步寫 iXML:<UMID>，可在此加另一個 helper：
-- function E.write_ixml_umid(wav_path, umid_hex) ... end

-- =====（可選）刷新 REAPER 媒體，使變更即時可見 =====
function E.refresh_media_item_take(take)
  if not take then return end
  local item = reaper.GetMediaItemTake_Item(take)
  if item then
    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC")) -- poke
    reaper.UpdateItemInProject(item)
  end
end


return E
