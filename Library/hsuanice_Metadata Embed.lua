--[[
@description hsuanice Metadata Embed (BWF MetaEdit helpers)
@version 251010_0037 Remove R.Main_OnCommand(40441, 0) -- Rebuild peaks
@author hsuanice
@noindex
@about
  Helpers to call BWF MetaEdit safely:
  - Shell quoting
  - Normalize iXML sidecar newline
  - Copy iXML/core, 
  read/write TimeReference
  - Post-embed refresh (offline->online, rebuild peaks)

@changelog
  v251010_0037 Remove R.Main_OnCommand(40441, 0) -- Rebuild peaks
    - Rationale: Refresh_Items already does offline->online->rebuild peaks.
    - Prevent redundant peak rebuild (40441) after every single item refresh.

  v250926_2018 (2025-09-26)
    - Change: Refresh_Items now uses 42356 (Toggle force media offline) twice (offline→online), then 40441 (Rebuild peaks), to force immediate BWF header (TimeReference) reload.
    - Rationale: 40440/40439 were insufficient in some cases after render with newly embedded TC.

  v0.3.0 (2025-09-25)
    - Added: CLI_Resolve() — resolve & persist BWF MetaEdit path
      (ExtState: hsuanice_TCTools/BWFMetaEditPath; Apple Silicon default
       /opt/homebrew/bin/bwfmetaedit is tried first).
    - Added: TR_Read(), TR_Write() — read/write BWF TimeReference (samples)
      via --out-xml=- / --TimeReference= with safe quoting (exec_shell).
    - Added: SecToSamples() — floor+epsilon sample quantization to prevent +1 jitter.
    - Added: TR_PrevToActive(), TR_FromItemStart() — handle-aware TC math using
      SrcStart (D_STARTOFFS) and cross-SR safety; negative results clamped to 0.
    - Added: Refresh_Items() — batch offline→online→rebuild peaks for items/takes.
    - Kept: write_bext_umid(), refresh_media_item_take(), shell helpers (unchanged).
    - Notes: TC/TimeReference math here is the single source of truth; RGWH and tools
      should call this library. Backward-compatible insertion; UMID workflows unaffected.


  v0.2.4 (2025-09-12)
    - Changed: E.write_bext_umid() now returns the actual command string
      used for execution, in addition to (ok, code, out).
      * Return signature: ok, code, out, cmd
      * cmd is the fully formatted bwfmetaedit command.
    - Purpose: allows calling tools to log the exact command
      instead of reconstructing it, avoiding stale or incorrect flags.
    - No change to write logic (still uses only --UMID=).
    - Maintains compatibility with v0.2.3 behavior if cmd return is ignored.

  v0.2.2 (2025-09-12)
    - Improved: E.write_bext_umid() now aggressively cleans input
      before validation:
        * Strips all non-hex characters.
        * Forces uppercase to ensure consistent 64 hex chars.
    - Safer: Prevents hidden characters or dash-separated UMIDs
      from being rejected incorrectly.
    - No change to CLI execution or return values.
    - Compatible with v0.2.1 calling convention
      (cli_path, wav_path, umid_hex).
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
E.VERSION = "0.3.0"

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
-- Usage: E.write_bext_umid(cli, wav_path, umid_hex)
function E.write_bext_umid(cli, wav_path, umid_hex)
  local G = E._G or G
  local h = tostring(umid_hex or "")

  -- Aggressive clean → keep only 0-9A-F, force uppercase
  h = h:gsub("[^0-9A-Fa-f]", ""):upper()
  if G and G.normalize_umid then h = G.normalize_umid(h) end

  if not h:match("^[0-9A-F]+$") or #h ~= 64 then
    return false, "UMID must be 64 hex chars"
  end
  if not cli or cli == "" then
    return false, "Missing bwfmetaedit CLI path"
  end

  -- Official BWF MetaEdit syntax: --UMID=<hex>
  local cmd = ('"%s" --UMID=%s "%s"'):format(cli, h, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return (code == 0), code, out, cmd
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

-- ===== TimeReference helpers & API (non-breaking add for 0.2.4) =====

-- keep it ultra-safe: reuse existing IS_WIN/sh_wrap/exec_shell from this file

-- tiny epsilon to stabilize floor rounding
local _QUANT_EPS = 1e-9

-- quick WAV check
local function _is_wav(path)
  return path and type(path)=="string" and path:lower():sub(-4)==".wav"
end

-- seconds -> integer samples (floor + epsilon)
function E.SecToSamples(sr, seconds)
  return math.floor((seconds or 0) * (sr or 48000) + _QUANT_EPS)
end

-- resolve bwfmetaedit path; persist like TC tool does
function E.CLI_Resolve()
  local R = reaper
  local EXT_NS, EXT_KEY = "hsuanice_TCTools", "BWFMetaEditPath"

  local function ok_cli(p)
    if not p or p=="" then return false end
    -- Use the same safe quoting style as TR_Read/TR_Write
    local cmd = ('"%s" --Version'):format(p)
    local code = select(1, exec_shell(cmd, 3000))
    return code == 0
  end


  local saved = R.GetExtState(EXT_NS, EXT_KEY)
  if saved ~= "" and ok_cli(saved) then return saved end

  local cands
  if IS_WIN then
    cands = {
      [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]],
      [[C:\Program Files (x86)\BWF MetaEdit\bwfmetaedit.exe]],
      "bwfmetaedit",
    }
  else
    -- Prefer Apple Silicon Homebrew path first
    cands = {
      "/opt/homebrew/bin/bwfmetaedit",
      "/usr/local/bin/bwfmetaedit",
      "bwfmetaedit"
    }
  end

  for _,p in ipairs(cands) do
    if ok_cli(p) then
      R.SetExtState(EXT_NS, EXT_KEY, p, true)
      return p
    end
  end

  local hint = IS_WIN and [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]] or "/opt/homebrew/bin/bwfmetaedit"
  local ok, picked = R.GetUserFileNameForRead(0, hint, 'Locate "bwfmetaedit" executable (Cancel to abort)')
  if ok and ok_cli(picked) then
    R.SetExtState(EXT_NS, EXT_KEY, picked, true)
    return picked
  end
  return nil
end

-- read BWF TimeReference (samples) using --out-xml=-
function E.TR_Read(cli, wav_path)
  if not cli or not _is_wav(wav_path) then return nil, -1, "" end
  local cmd = ('"%s" --out-xml=- "%s"'):format(cli, wav_path)
  local code, out = exec_shell(cmd, 20000)
  local tr = tonumber(out:match("<TimeReference>(%d+)</TimeReference>") or "")
  return tr, code, out
end

-- write BWF TimeReference (samples) using --TimeReference=
function E.TR_Write(cli, wav_path, tr_samples)
  if not cli or not _is_wav(wav_path) then return false, -1, "" end
  local tr = tonumber(tr_samples or 0) or 0
  if tr < 0 then tr = 0 end
  local cmd = ('"%s" --TimeReference=%d "%s"'):format(cli, tr, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return (code == 0), code, out
end

-- compute TR for active take from previous take (handle-aware, cross-SR safe)
function E.TR_PrevToActive(prev_take, active_take)
  if not (prev_take and active_take) then return 0 end

  local function take_sr(tk)
    local src = reaper.GetMediaItemTake_Source(tk)
    local sr = src and reaper.GetMediaSourceSampleRate(src) or 0
    if not sr or sr <= 0 then
      sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 0
    end
    return (sr and sr > 0) and sr or 48000
  end
  local function srcstart_sec(tk)
    return reaper.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0.0
  end

  local src_sr = take_sr(prev_take)
  local dst_sr = take_sr(active_take)
  local src_off = srcstart_sec(prev_take)
  local dst_off = srcstart_sec(active_take)

  -- read previous file TR
  local prev_src = reaper.GetMediaItemTake_Source(prev_take)
  local prev_path = prev_src and reaper.GetMediaSourceFileName(prev_src, "") or ""
  local cli = E.CLI_Resolve()
  local prev_tr_samples = 0
  if cli and _is_wav(prev_path) then
    local tr, code = E.TR_Read(cli, prev_path)
    if code == 0 and tr then prev_tr_samples = tr end
  end

  -- seconds-domain math (same policy as TC tool), then quantize
  local prev_tr_sec = (prev_tr_samples or 0) / src_sr
  local dst_tr_sec  = (prev_tr_sec + src_off) - dst_off
  if dst_tr_sec < 0 then dst_tr_sec = 0 end
  return E.SecToSamples(dst_sr, dst_tr_sec)
end

-- compute TR from item start position for active take
function E.TR_FromItemStart(active_take, proj_pos)
  if not active_take then return 0 end
  local function take_sr(tk)
    local src = reaper.GetMediaItemTake_Source(tk)
    local sr = src and reaper.GetMediaSourceSampleRate(src) or 0
    if not sr or sr <= 0 then
      sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 0
    end
    return (sr and sr > 0) and sr or 48000
  end
  local dst_sr = take_sr(active_take)
  local dst_off = reaper.GetMediaItemTakeInfo_Value(active_take, "D_STARTOFFS") or 0.0
  local sec = (proj_pos or 0) - dst_off
  if sec < 0 then sec = 0 end
  return E.SecToSamples(dst_sr, sec)
end

-- batch refresh: offline -> online -> rebuild peaks (items or takes)
function E.Refresh_Items(t)
  if type(t) ~= "table" or #t == 0 then return end
  local R = reaper
  local seen, items = {}, {}
  for _,obj in ipairs(t) do
    local it = obj
    if R.ValidatePtr2(0, obj, "MediaItem_Take*") then
      it = R.GetMediaItemTake_Item(obj)
    end
    if R.ValidatePtr2(0, it, "MediaItem*") then
      local key = tostring(it)
      if not seen[key] then seen[key] = true; items[#items+1] = it end
    end
  end
  if #items == 0 then return end
  R.SelectAllMediaItems(0, false)
  for _,it in ipairs(items) do R.SetMediaItemSelected(it, true) end
  R.UpdateArrange()
  R.Main_OnCommand(42356, 0) -- Toggle force media offline (go offline)
  R.Main_OnCommand(42356, 0) -- Toggle force media offline (back online)
  --R.Main_OnCommand(40441, 0) -- Rebuild peaks
end


return E
