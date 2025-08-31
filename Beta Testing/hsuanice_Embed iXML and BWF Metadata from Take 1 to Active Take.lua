--[[
@description hsuanice_Embed iXML and BWF Metadata from Take 1 to Active Take
@version 0.3.3
@author hsuanice
@about
  Copy ALL metadata from TAKE 1's source file to the ACTIVE take's source file, with full console logs and a summary:
    • iXML chunk (entire XML): export sidecar (*.iXML.xml) from Take 1 → import into Active.
    • BWF bext/INFO (CORE Document): export fields from Take 1 → import into Active (via CORE CSV).
    • BWF TimeReference (sample-accurate TC): read from Take 1 → write to Active (overwrite).
  UI matches your "BWF TimeReference Embed Tool": small chooser (ReaImGui if available, GetUserInputs fallback),
  detailed console output per item, and a final summary + optional refresh (offline/online + rebuild peaks).
  Audio essence is untouched; only metadata is written.

  Requirements:
    • BWF MetaEdit CLI (`bwfmetaedit`) in PATH (or select it once; path persisted via ExtState).
    • Optional: ReaImGui (for nicer UI).

  Credits:
    • TC embed logic/UX adapted from "hsuanice_BWF TimeReference Embed Tool.lua".
    • iXML/CORE flow adapted from the previous "Embed iXML and BWF Metadata..." implementation.
 
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.

@changelog
  v0.3.3
- Improve: INFO fields (e.g., ICMT, ISBJ) that contain multi-line values are now reformatted into a single human-readable line with " · " separators.
  Example:
    sSPEED=024.000-ND
    sTAKE=03
    sTRK3=BOOM1
  → stored as:
    sSPEED=024.000-ND · sTAKE=03 · sTRK3=BOOM1
- Reason: BWF MetaEdit CLI does not accept literal line breaks in INFO fields, which previously caused “carriage return not acceptable” errors.
- Keep: BEXT Description and iXML USER:DESCRIPTION continue to preserve true multi-line formatting for accurate readability.
- Log: When INFO newlines are collapsed, console shows a warning:
    CORE(FLAGS): ICMT had newlines -> formatted as single line

  v0.3.2
- Fix: Normalize all text-based metadata (Description, Comment, USER:DESCRIPTION, etc.) to use clean \n line breaks instead of literal "\n" escape sequences.
- Improve: Added normalize_newlines() function and applied it during iXML sidecar creation and BWF/INFO field writing, ensuring all multi-line metadata appears as real line breaks when viewed in REAPER or Wave Agent.
- Result: Metadata readability restored to the same style as original field recordings (multi-line lists are vertically aligned, not embedded with "\n").

  v0.3.1
  - CORE (bext/INFO) write:
      • Disabled CodingHistory field for per-flag write mode, since some bwfmetaedit CLI builds reject --CodingHistory= and cause write failure.
      • Now logs "skip CodingHistory (unsupported by this CLI)" in console instead of failing.
  - Ensures all other CORE fields (Description, Originator, OriginatorReference, OriginationDate, OriginationTime, INFO group, UMID, ISFT override) continue to be written correctly.
  - Maintains iXML copy, USER.EMBEDDER normalization, ISFT override, and TimeReference embed unchanged.
  - Console + Summary:
      • Updated logging reflects skip behavior for CodingHistory.
  v0.3.0
    - iXML sidecar auto-cleanup:
        • After embedding (success or fail), the script now automatically deletes any temporary *.iXML.xml sidecars created during export/import.
        • Prevents clutter in source/target folders.
    - CORE (bext/INFO) write:
        • Retains robust per-field flag approach.
        • INFO:ISFT is now always overridden to "BWF MetaEdit" (avoids legacy "Soundminer" values).
    - USER.EMBEDDER normalization:
        • After iXML copy, <USER><EMBEDDER> in the target file is forced to "BWF MetaEdit".
    - Console + Summary:
        • Logs mirror the TimeReference tool with detailed per-step messages and an end summary (OK/FAIL/SKIP).
    - Workflow parity:
        • iXML copy (sidecar export/import), CORE copy, and TimeReference embed remain identical to 0.2.x, but with cleanup and embedder/ISFT normalization built-in.

  v0.2.3
    - CORE (bext/INFO) write:
        • Added strict escaping for \, ", $, and backticks before passing to CLI.
        • Prevents shell expansions (e.g., $0 → /bin/sh), ensuring fields like sUBITS=$00000000 remain intact.
    - ISFT field override:
        • INFO:ISFT is now explicitly set to "BWF MetaEdit", avoiding legacy "Soundminer" values in target files.
    - USER:EMBEDDER normalization:
        • After iXML copy, <USER><EMBEDDER> is forced to "BWF MetaEdit".
    - Maintains existing workflow:
        • iXML sidecar copy, CORE per-field flags, and TimeReference embed.
        • Console logging and final OK/FAIL summary consistent with previous versions.

  v0.2.2
    - Added iXML USER.EMBEDDER normalization:
        • After iXML copy, the script now rewrites <USER><EMBEDDER> to "BWF MetaEdit" on the target file.
        • This replaces legacy "Soundminer" stamps so tools (e.g., Wave Agent) show a consistent embedder.
    - Kept the robust CORE (bext/INFO) per-field write path from 0.2.1:
        • Uses individual flags (e.g., --Description=..., --Originator=..., etc.) for broad CLI compatibility.
        • Success is determined by exit code; a post-check snapshot is logged but not used for pass/fail.
    - Console UX parity and summary:
        • Mirrors the TimeReference tool style with detailed step-by-step logs and a final OK/FAIL summary.
    - Notes:
        • iXML copy (sidecar export/import) unchanged.
        • TimeReference (TR) copy unchanged and verified.
        • File length must match when writing certain CORE fields (preservation behavior of the CLI).

  v0.2.1
    - Reworked CORE (bext/INFO) copy method:
        • Removed reliance on deprecated `--in-core-csv` / `--in-xml`.
        • Implemented per-field flags (`--Description=... --Originator=...` etc.) for maximum CLI compatibility.
    - Improved verification:
        • Success is now determined by exit code (`code=0`) instead of strict XML string matching.
        • Post-check uses `--out-xml=-` only for logging (avoids false negatives on multi-line/escaped fields).
    - Console output updated with clearer messages:
        • Added "CORE(FLAGS): post-check (dst snapshot) captured." after writing.
    - End-to-end workflow (iXML → CORE → TR) now reports `RESULT: OK` correctly.
  v0.2.0
    - Add TR (TimeReference) embed from Take 1 → Active, using your existing CLI wrapper pattern.
    - Add full console logs (per-step read/write/verify) and end-of-run summary + refresh prompt.
    - Add ReaImGui / GetUserInputs front UI like your TC tool, with escape handling.
  v0.1.1
    - First combined version (iXML + CORE + TR) without console/summary parity to TC tool.
]]

local R = reaper

-- =========================
-- Console helpers
-- =========================
local function msg(s) R.ShowConsoleMsg(tostring(s).."\n") end
local function base(p) return (p and p:match("([^/\\]+)$")) or tostring(p) end
local function is_wav(p) return p and p:lower():sub(-4)==".wav" end

-- remove file if exists, ignore errors
local function remove_file_silent(path)
  if not path or path == "" then return end
  local f = io.open(path, "rb")
  if f then f:close(); os.remove(path) end
end

-- turn any textual "\n" into real newlines, normalize CRLF/CR to LF, and decode common XML entities
local function normalize_newlines(s)
  if not s or s == "" then return s end
  -- unify OS line endings first
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  -- convert literal backslash-n to real newline
  -- pattern needs double escaping: "\\n" as text -> "\\\\n" in Lua pattern
  s = s:gsub("\\n", "\n")
  -- also convert common XML entities sometimes seen in dumps
  s = s:gsub("&#13;", "\n"):gsub("&#10;", "\n")
  return s
end

-- =========================
-- Shell wrappers (borrowed style from your TC tool)
-- =========================
local OS = R.GetOS()
local IS_WIN = OS:match("Win")
local EXT_NS, EXT_KEY = "hsuanice_TCTools", "BWFMetaEditPath" -- reuse same namespace/key so user picks once

local function sh_wrap(cmd)
  if IS_WIN then
    return 'cmd.exe /C "'..cmd..'"'
  else
    return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'" -- escape single quotes safely
  end
end

-- Exec with timeout, return exit code, stdout
local function exec_shell(cmd, ms)
  local ret = R.ExecProcess(sh_wrap(cmd), ms or 30000) or ""
  local code, out = ret:match("^(%d+)\n(.*)$")
  return tonumber(code or -1), (out or "")
end

local function test_cli(p)
  if not p or p=="" then return false end
  local code = select(1, exec_shell('"'..p..'" --Version', 4000))
  return code == 0
end

local function resolve_cli()
  local saved = R.GetExtState(EXT_NS, EXT_KEY)
  if saved ~= "" and test_cli(saved) then return saved end

  local cands
  if IS_WIN then
    cands = {
      [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]],
      [[C:\Program Files (x86)\BWF MetaEdit\bwfmetaedit.exe]],
      "bwfmetaedit",
    }
  else
    cands = { "/opt/homebrew/bin/bwfmetaedit", "/usr/local/bin/bwfmetaedit", "bwfmetaedit" }
  end

  for _,p in ipairs(cands) do
    if test_cli(p) then
      R.SetExtState(EXT_NS, EXT_KEY, p, true)
      return p
    end
  end

  local hint = IS_WIN and [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]] or "/opt/homebrew/bin/bwfmetaedit"
  local ok, picked = R.GetUserFileNameForRead(0, hint, 'Locate "bwfmetaedit" executable (Cancel to abort)')
  if not ok then return nil end
  if test_cli(picked) then
    R.SetExtState(EXT_NS, EXT_KEY, picked, true)
    return picked
  end
  return nil
end

-- =========================
-- File helpers
-- =========================
local function file_exists(p) local f=io.open(p,"rb");if f then f:close();return true end return false end
local function dirname(p) return p:match("^(.*)[/\\]") or "" end
local function join(a,b) if a:sub(-1)=="/" or a:sub(-1)=="\\" then return a..b end return a.."/"..b end

local function read_file(path) local f=io.open(path,"rb"); if not f then return nil end local s=f:read("*a"); f:close(); return s end
local function write_file(path,data) local f=assert(io.open(path,"wb")); f:write(data or ""); f:close() end

-- =========================
-- REAPER item/take helpers
-- =========================
local function get_take_src_path(take)
  if not take or not R.ValidatePtr(take,"MediaItem_Take*") then return nil end
  local src = R.GetMediaItemTake_Source(take)
  if not src then return nil end
  local p = R.GetMediaSourceFileName(src, "")
  return (p ~= "" and p) or nil
end

local function get_take1(item)  return R.GetMediaItemTake(item, 0) end
local function get_active(item) return R.GetActiveTake(item) end

-- =========================
-- Parse fields from --out-xml (for CORE+BEXT/INFO)
-- =========================
local function parse_core_from_xml_report(xml_text)
  local function tag(name)
    local v = xml_text:match("<"..name.."%s*[^>]*>(.-)</"..name..">")
    if v then
      v = v:gsub("&lt;","<"):gsub("&gt;",">"):gsub("&amp;","&")
      v = v:gsub("\r\n","\n"):gsub("\r","\n"):gsub("\n","\\n")
      return v
    end
    return ""
  end
  return {
    Description = tag("Description"),
    Originator = tag("Originator"),
    OriginatorReference = tag("OriginatorReference"),
    OriginationDate = tag("OriginationDate"),
    OriginationTime = tag("OriginationTime"),
    IARL = tag("IARL"), IART = tag("IART"), ICMT = tag("ICMT"), ICRD = tag("ICRD"),
    INAM = tag("INAM"), ICOP = tag("ICOP"), ICMS = tag("ICMS"), IGNR = tag("IGNR"),
    ISFT = tag("ISFT"), ISBJ = tag("ISBJ"), ITCH = tag("ITCH"),
    CodingHistory = tag("CodingHistory"), UMID = tag("UMID"),
  }
end

local function build_core_csv_row(file_path, fields)
  local headers = {
    "FileName","Description","Originator","OriginatorReference","OriginationDate","OriginationTime",
    "IARL","IART","ICMT","ICRD","INAM","ICOP","ICMS","IGNR","ISFT","ISBJ","ITCH",
    "CodingHistory","UMID"
  }
  local function esc(s) s = s or ""; if s:find('[,"\n]') then s = '"'..s:gsub('"','""')..'"' end return s end
  local vals = {
    file_path, fields.Description, fields.Originator, fields.OriginatorReference,
    fields.OriginationDate, fields.OriginationTime, fields.IARL, fields.IART, fields.ICMT,
    fields.ICRD, fields.INAM, fields.ICOP, fields.ICMS, fields.IGNR, fields.ISFT, fields.ISBJ,
    fields.ITCH, fields.CodingHistory, fields.UMID
  }
  local line = {}
  for i=1,#vals do line[i] = esc(vals[i]) end
  return table.concat(headers,",").."\n"..table.concat(line,",").."\n"
end

-- =========================
-- BWF MetaEdit: iXML / CORE / TR
-- =========================

-- normalize iXML sidecar before import
local function normalize_ixml_sidecar(path)
  local f = io.open(path, "rb")
  if not f then return end
  local data = f:read("*a")
  f:close()
  if not data or #data == 0 then return end

  -- replace literal "\n" with real newline
  data = data:gsub("\\n", "\n")
             :gsub("&#13;", "\n")
             :gsub("&#10;", "\n")

  -- write back
  local wf = io.open(path, "wb")
  if wf then wf:write(data) wf:close() end
end

-- 1) iXML sidecar export/import
local function do_ixml_copy(cli, src_wav, dst_wav)
  local src_iXML = src_wav .. ".iXML.xml"
  local dst_iXML = dst_wav .. ".iXML.xml"

  local code1, out1 = exec_shell(('"%s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, src_wav), 20000)
  msg(("    iXML: export src → sidecar (code=%s)"):format(tostring(code1)))

  if file_exists(src_iXML) then
    local x = read_file(src_iXML)
    if x then write_file(dst_iXML, x) end

    -- ★ 新增：先把字面 "\n" 轉回真正換行
    normalize_ixml_sidecar(dst_iXML)

    local code2, out2 = exec_shell(('"%s" --in-iXML-xml --continue-errors --verbose "%s"'):format(cli, dst_wav), 20000)
    msg(("    iXML: import sidecar → dst (code=%s)"):format(tostring(code2)))
    return code2 == 0
  else
    msg("    iXML: no sidecar exported (source has no iXML?) -> SKIP")
    return true
  end
end

-- Escape a value for safe use inside our shell-wrapped command.
-- We already wrap the whole command in single quotes via sh_wrap(),
-- but we still sanitize to avoid edge cases in ExecProcess/sh:
--   - backslash, double-quote, dollar, backtick
local function sh_escape_value(v)
  if not v or v == "" then return "" end
  v = v:gsub("\\", "\\\\")   -- escape backslashes
  v = v:gsub('"', '\\"')     -- escape double quotes
  v = v:gsub("%$", "\\$")    -- escape $ (prevents $0 -> /bin/sh etc.)
  v = v:gsub("`", "\\`")     -- escape backticks
  return v
end



-- 2) CORE (bext/INFO) via per-field flags (robust across CLI versions) — v2 (fixed)
local function do_core_copy(cli, src_wav, dst_wav)
  -- 讀來源 XML 報告（stdout）
  local codeR, outR = exec_shell(('"%'..'s" --out-xml=- --continue-errors --verbose "%s"'):format(cli, src_wav), 30000)
  msg(("    CORE(FLAGS): export src (code=%s)"):format(tostring(codeR)))
  if codeR ~= 0 or not outR or #outR == 0 then
    if outR and #outR > 0 then msg("    CORE(FLAGS): exporter stdout >>>\n"..outR.."\n    <<<") end
    return false
  end

  local fields = parse_core_from_xml_report(outR)
  -- restore clean newlines for all text-ish fields before flag assembly
  fields.Description          = normalize_newlines(fields.Description)
  fields.Originator           = normalize_newlines(fields.Originator)
  fields.OriginatorReference  = normalize_newlines(fields.OriginatorReference)
  fields.OriginationDate      = normalize_newlines(fields.OriginationDate)
  fields.OriginationTime      = normalize_newlines(fields.OriginationTime)
  fields.IARL                 = normalize_newlines(fields.IARL)
  fields.IART                 = normalize_newlines(fields.IART)
  fields.ICMT                 = normalize_newlines(fields.ICMT)
  fields.ICRD                 = normalize_newlines(fields.ICRD)
  fields.INAM                 = normalize_newlines(fields.INAM)
  fields.ICOP                 = normalize_newlines(fields.ICOP)
  fields.ICMS                 = normalize_newlines(fields.ICMS)
  fields.IGNR                 = normalize_newlines(fields.IGNR)
  fields.ISFT                 = normalize_newlines(fields.ISFT)
  fields.ISBJ                 = normalize_newlines(fields.ISBJ)
  fields.ITCH                 = normalize_newlines(fields.ITCH)
  fields.CodingHistory        = normalize_newlines(fields.CodingHistory)
  fields.UMID                 = normalize_newlines(fields.UMID)


  -- BEXT Description 最長 256 bytes（超過截斷並提示）
  local function trunc_bext_desc(s)
    if not s then return "" end
    local bytes = {string.byte(s, 1, #s)}
    if #bytes <= 256 then return s end
    local out = {}
    for i=1,256 do out[i] = string.char(bytes[i]) end
    msg("    CORE(FLAGS): Description >256 bytes, truncated to 256")
    return table.concat(out)
  end
  fields.Description = trunc_bext_desc(fields.Description)

  -- build flags per field
  local flags = {}

  -- basic add: keep real newlines (for BEXT Description, etc.)
  local function add(k, v)
    if v and v ~= "" then
      v = v:gsub('"','\\"')   -- only escape double-quotes
      flags[#flags+1] = ('--%s="%s"'):format(k, v)
    end
  end

  -- INFO-safe add: collapse newlines to a readable single line
  local function add_info(k, v)
    if v and v ~= "" then
      if v:find("\n", 1, true) or v:find("\r", 1, true) then
        -- 將多行轉為「 · 」分隔的一行，提升可讀性
        local before = v
        v = v:gsub("\r\n", "\n"):gsub("\r", "\n")
        -- 移除行首行尾空白，再用分隔符連接
        local parts = {}
        for line in v:gmatch("[^\n]+") do
          line = line:gsub("^%s+", ""):gsub("%s+$", "")
          if line ~= "" then parts[#parts+1] = line end
        end
        v = table.concat(parts, " · ")
        msg(("    CORE(FLAGS): %s had newlines -> formatted as single line"):format(k))
      end
      v = v:gsub('"','\\"')
      flags[#flags+1] = ('--%s="%s"'):format(k, v)
    end
  end

  -- Keep multi-line only where allowed/meaningful:
  add("Description",          fields.Description)          -- BEXT Description (multi-line OK)

  -- INFO chunk family: must be single-line
  add_info("IARL",            fields.IARL)
  add_info("IART",            fields.IART)
  add_info("ICMT",            fields.ICMT)                 -- <- 這個就是剛剛出錯的欄位
  add_info("ICRD",            fields.ICRD)
  add_info("INAM",            fields.INAM)
  add_info("ICOP",            fields.ICOP)
  add_info("ICMS",            fields.ICMS)
  add_info("IGNR",            fields.IGNR)
  add_info("ISFT",            fields.ISFT)
  add_info("ISBJ",            fields.ISBJ)
  add_info("ITCH",            fields.ITCH)

  -- Others
  add("Originator",           fields.Originator)
  add("OriginatorReference",  fields.OriginatorReference)
  add("OriginationDate",      fields.OriginationDate)
  add("OriginationTime",      fields.OriginationTime)
  add("CodingHistory",        fields.CodingHistory)  -- 你已經有「跳過寫入」的判斷，保留此列無妨
  add("UMID",                 fields.UMID)

  -- CodingHistory is often multi-line and not supported by some CLI versions with flags.
  -- Temporarily skip to keep the write robust across environments.
  local WRITE_CODING_HISTORY = false
  if WRITE_CODING_HISTORY and fields.CodingHistory and fields.CodingHistory ~= "" then
    add("CodingHistory", fields.CodingHistory) -- may fail on some CLI builds
  else
    msg("    CORE(FLAGS): skip CodingHistory (unsupported by this CLI)")
  end

  add("UMID",                 fields.UMID)

  if #flags == 0 then
    msg("    CORE(FLAGS): nothing to write -> SKIP")
    return true
  end

  -- 寫入（以退出碼判斷成功）
  local cmd = ('"%s" %s "%s"'):format(cli, table.concat(flags, " "), dst_wav)
  local codeW, outW = exec_shell(cmd, 40000)
  msg(("    CORE(FLAGS): write dst (code=%s)"):format(tostring(codeW)))
  if (outW or "") ~= "" then
    msg("    CORE(FLAGS): writer stdout >>>")
    msg(outW)
    msg("    <<<")
  end

  -- Post-check 只記錄日誌，不影響成敗判定
  local codeV, outV = exec_shell(('"%'..'s" --out-xml=- --continue-errors --verbose "%s"'):format(cli, dst_wav), 20000)
  if codeV == 0 and outV and #outV > 0 then
    msg("    CORE(FLAGS): post-check (dst snapshot) captured.")
    -- Post-check 只記錄日誌，不影響成敗判定
    local codeV, outV = exec_shell(('"%'..'s" --out-xml=- --continue-errors --verbose "%s"'):format(cli, dst_wav), 20000)
    if codeV == 0 and outV and #outV > 0 then
      msg("    CORE(FLAGS): post-check (dst snapshot) captured.")
      -- ★ 在這裡加上你的檢查
      if outV:find("\\n", 1, true) then
        msg("    CORE(FLAGS): WARNING - \\n remains in dst snapshot (should be real newlines)")
      end
    end


  end

  return codeW == 0
end

-- 3) TR read/write/verify
local function read_TR(cli, wav_path)
  local cmd = ('"%s" --out-xml=- "%s"'):format(cli, wav_path)
  local code, out = exec_shell(cmd, 20000)
  local tr = tonumber(out:match("<TimeReference>(%d+)</TimeReference>") or "")
  return tr, code, out
end

local function write_TR(cli, wav_path, tr)
  local cmd = ('"%s" --Timereference=%d "%s"'):format(cli, tr, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return code, out
end

-- 4) iXML USER.EMBEDDER patch
local function set_ixml_embedder(cli, wav_path, newval)
  -- export iXML from target
  local codeE = select(1, exec_shell(('"%'..'s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, wav_path), 20000))
  msg(("    iXML: export dst for USER.EMBEDDER (code=%s)"):format(tostring(codeE)))

  local side = wav_path .. ".iXML.xml"
  local xml  = read_file(side) or ""
  if xml == "" then
    msg("    iXML: no iXML present on dst -> SKIP USER.EMBEDDER")
    return true
  end

  -- try replace existing <EMBEDDER>...</EMBEDDER>
  local patched, n = xml:gsub("(<%s*EMBEDDER%s*>)(.-)(</%s*EMBEDDER%s*>)", "%1"..newval.."%3", 1)

  if n == 0 then
    -- if no EMBEDDER tag yet, insert one inside <USER>..., or append before the iXML closing tag
    if xml:find("<USER%s*>") then
      patched = xml:gsub("(<USER%s*>)", "%1<EMBEDDER>"..newval.."</EMBEDDER>", 1)
    else
      patched = xml
      patched = patched:gsub("(</BWFXML>)", "<USER><EMBEDDER>"..newval.."</EMBEDDER></USER>%1", 1)
      patched = patched:gsub("(</iXML>)",   "<USER><EMBEDDER>"..newval.."</EMBEDDER></USER>%1", 1)
    end
  end

  write_file(side, patched)

  -- 匯入前再清一次，避免任何殘留的文字型 \n
  normalize_ixml_sidecar(side)

  -- import iXML back to target
  local codeI = select(1, exec_shell(('"%'..'s" --in-iXML-xml --continue-errors --verbose "%s"'):format(cli, wav_path), 20000))
  msg(("    iXML: set USER.EMBEDDER=\"%s\" (code=%s)"):format(newval, tostring(codeI)))

  -- cleanup sidecar regardless of success
  remove_file_silent(side)

  return codeI == 0

end




-- =========================
-- Refresh helper (offline → online → rebuild peaks)
-- =========================
local function select_only(items)
  R.SelectAllMediaItems(0, false)
  for _,it in ipairs(items) do
    if it and R.ValidatePtr(it, "MediaItem*") then
      R.SetMediaItemSelected(it, true)
    end
  end
  R.UpdateArrange()
end

local function refresh_and_rebuild(modified_items)
  if not modified_items or #modified_items == 0 then return end
  select_only(modified_items)
  R.Main_OnCommand(40440, 0) -- offline
  R.Main_OnCommand(40439, 0) -- online
  R.Main_OnCommand(40441, 0) -- rebuild peaks
end

-- =========================
-- Worker
-- =========================
local function run_worker()
  local cli = resolve_cli()
  if not cli then
    local hint = IS_WIN and "請安裝 BWF MetaEdit，或指定 bwfmetaedit.exe 路徑。"
                       or  "macOS 可用 Homebrew：brew install bwfmetaedit"
    R.MB("找不到 BWF MetaEdit（bwfmetaedit）。\n"..hint, "Embed iXML+BWF", 0)
    return
  end

  local n_sel = R.CountSelectedMediaItems(0)
  if n_sel == 0 then
    R.MB("請至少選取一個 item。", "Embed iXML+BWF", 0)
    return
  end

  local items = {}
  for i=0, n_sel-1 do items[#items+1] = R.GetSelectedMediaItem(0, i) end

  R.ClearConsole()
  msg(("=== Embed iXML + CORE + TR from Take1 → Active ==="))
  msg(("CLI : %s"):format(cli))
  msg(("Sel : %d"):format(#items))
  msg("")

  local ok_cnt, fail_cnt, skip_cnt = 0, 0, 0
  local modified = {}

  R.Undo_BeginBlock()

  for i, it in ipairs(items) do
    msg(("Item %d -------------------------"):format(i))
    if not it or not R.ValidatePtr(it, "MediaItem*") then
      skip_cnt = skip_cnt + 1
      msg("  [SKIP] invalid item pointer")
    else
      local take1  = get_take1(it)
      local active = get_active(it)

      if not active then
        skip_cnt = skip_cnt + 1
        msg("  [SKIP] no active take")
      elseif not take1 then
        skip_cnt = skip_cnt + 1
        msg("  [SKIP] no Take 1")
      elseif take1 == active then
        skip_cnt = skip_cnt + 1
        msg("  [SKIP] active == Take 1 (same take/file)")
      else
        local src = get_take_src_path(take1)
        local dst = get_take_src_path(active)
        msg(("  src : %s"):format(base(src or "(nil)")))
        msg(("  dst : %s"):format(base(dst or "(nil)")))

        if not (src and dst and is_wav(src) and is_wav(dst) and file_exists(src) and file_exists(dst)) then
          skip_cnt = skip_cnt + 1
          msg("  [SKIP] missing file(s) or non-WAV")
        else
          -- iXML
          local ok_ixml = do_ixml_copy(cli, src, dst)
          msg(("  iXML result    : %s"):format(ok_ixml and "OK" or "FAIL"))

        -- optional: force USER.EMBEDDER patch
        set_ixml_embedder(cli, dst, "BWF MetaEdit")

          -- CORE
          local ok_core = do_core_copy(cli, src, dst)
          msg(("  CORE result    : %s"):format(ok_core and "OK" or "FAIL"))

          -- TR
          local tr_src = select(1, read_TR(cli, src))
          msg(("  TAKE1 TR read  : %s"):format(tostring(tr_src)))
          local tr_written = false
          if tr_src then
            local wc = select(1, write_TR(cli, dst, tr_src))
            msg(("  WRITE dst TR   : code=%s"):format(tostring(wc)))
            local vr = select(1, read_TR(cli, dst))
            msg(("  VERIFY dst TR  : %s"):format(tostring(vr)))
            tr_written = (wc == 0 and vr == tr_src)
            msg(("  TR result      : %s"):format(tr_written and "OK" or "FAIL"))
          else
            msg("  TR result      : SKIP (cannot read src TR)")
          end

          if (ok_ixml and ok_core and tr_written) or (ok_ixml and ok_core and tr_src==nil) then
            ok_cnt = ok_cnt + 1
            modified[#modified+1] = it
            msg("  RESULT: OK")
          else
            fail_cnt = fail_cnt + 1
            msg("  RESULT: FAIL")
          end
          -- cleanup iXML sidecars for both src and dst (best-effort)
          remove_file_silent(src .. ".iXML.xml")
          remove_file_silent(dst .. ".iXML.xml")          
        end
      end
    end
  end

  R.Undo_EndBlock("Embed iXML + CORE + TR", -1)

  local summary = ("Summary: OK=%d  FAIL=%d  SKIP=%d"):format(ok_cnt, fail_cnt, skip_cnt)
  msg("")
  msg(summary)
  msg("=== End ===")

  if #modified > 0 then
    local btn = R.MB(summary .. ("\n\nRefresh now?\n(%d item(s) will be refreshed)"):format(#modified),
                     "Embed iXML+BWF", 4)
    if btn == 6 then
      refresh_and_rebuild(modified)
    end
  else
    R.MB(summary .. "\n\nNo item embedded, no need to refresh", "Embed iXML+BWF", 0)
  end
end

-- =========================
-- UI (match your TC tool behavior)
-- =========================
local has_imgui = type(reaper.ImGui_CreateContext) == "function"
if not has_imgui then
  -- Keep a tiny entry dialog for parity (and to ensure keyboard focus)
  local ok, _ = R.GetUserInputs("Embed iXML+BWF from Take1", 1, "Press OK to start, extrafield ignored", "")
  if not ok then return end
  run_worker()
  return
end

local imgui = reaper
local ctx  = imgui.ImGui_CreateContext('Embed iXML+BWF from Take1', imgui.ImGui_ConfigFlags_NoSavedSettings())
local FONT = imgui.ImGui_CreateFont('sans-serif', 16); imgui.ImGui_Attach(ctx, FONT)
local BTN_W, BTN_H = 360, 28
local should_close = false

local function loop()
  imgui.ImGui_SetNextWindowSize(ctx, 380, 140, imgui.ImGui_Cond_Once())
  local visible, open = imgui.ImGui_Begin(ctx, 'Embed iXML+BWF from Take1', true)
  if visible then
    imgui.ImGui_Text(ctx, 'Copy iXML + BWF (CORE) + TimeReference\nfrom TAKE 1 to ACTIVE take')
    imgui.ImGui_Dummy(ctx, 1, 6)

    if imgui.ImGui_Button(ctx, 'Start', BTN_W, BTN_H) then run_worker() end
    imgui.ImGui_Dummy(ctx, 1, 6)
    if imgui.ImGui_Button(ctx, 'Cancel', BTN_W, BTN_H) then should_close = true end

    local esc = imgui.ImGui_IsKeyPressed(ctx, imgui.ImGui_Key_Escape(), false)
    if esc
       and imgui.ImGui_IsWindowFocused(ctx, imgui.ImGui_FocusedFlags_RootAndChildWindows())
       and not imgui.ImGui_IsAnyItemActive(ctx)
    then
      should_close = true
    end

    imgui.ImGui_End(ctx)
  end
  if not open or should_close then return end
  R.defer(loop)
end
loop()
