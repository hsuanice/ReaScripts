--[[
@description hsuanice_Embed iXML and BWF Metadata from Take 1 to Active Take with SMPTE UMID option
@version 260126.1545
@author hsuanice
@about
  Copy ALL metadata from TAKE 1's source file to the ACTIVE take's source file:
    • iXML chunk (entire XML): export sidecar from Take 1 → import into Active.
    • BWF bext/INFO (CORE Document): export fields from Take 1 → import into Active.
    • BWF TimeReference (sample-accurate TC): read from Take 1 → write to Active.
    • [Optional] SMPTE UMID: Generate and embed UMID (bext:UMID) if checkbox enabled.

  GUI uses native gfx library (no ReaImGui required).

  Requirements:
    • BWF MetaEdit CLI (`bwfmetaedit`) in PATH or specify path.
    • For UMID: hsuanice_Metadata Generator.lua and hsuanice_Metadata Embed.lua libraries.

@changelog
  260126.1545 - Improved error messages with detailed skip reasons
             - Now shows exact cause: src/dst path nil, not WAV, or file not found
             - Displays full path in error message for easier debugging

  260126.1533 - Initial release
             - Merged from "Embed iXML and BWF Metadata from Take 1 to Active Take" v0.3.5
             - Added SMPTE UMID generation option with 3 strategies:
               1) Copy if present, Generate if missing
               2) Always generate new
               3) Patch missing only
             - Changed GUI from ReaImGui to native gfx library
             - Dark theme UI with checkbox for UMID option
]]

local R = reaper

-- =========================
-- Console helpers
-- =========================
local function msg(s) R.ShowConsoleMsg(tostring(s).."\n") end
local function base(p) return (p and p:match("([^/\\]+)$")) or tostring(p) end
local function is_wav(p) return p and p:lower():sub(-4)==".wav" end

local function remove_file_silent(path)
  if not path or path == "" then return end
  local f = io.open(path, "rb")
  if f then f:close(); os.remove(path) end
end

local function normalize_newlines(s)
  if not s or s == "" then return s end
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("\\n", "\n")
  s = s:gsub("&#13;", "\n"):gsub("&#10;", "\n")
  return s
end

local function collapse_blank_lines(s)
  if not s or s == "" then return s end
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("\n%s*\n+", "\n")
  s = s:gsub("^\n+", ""):gsub("\n+$","")
  return s
end

-- =========================
-- Shell wrappers
-- =========================
local OS = R.GetOS()
local IS_WIN = OS:match("Win")
local EXT_NS, EXT_KEY = "hsuanice_TCTools", "BWFMetaEditPath"

local function sh_wrap(cmd)
  if IS_WIN then
    return 'cmd.exe /C "'..cmd..'"'
  else
    return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'"
  end
end

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
-- UMID Library Loading
-- =========================
local function exists(path) local f=io.open(path,"rb"); if f then f:close(); return true end end
local RES = R.GetResourcePath()

local LIB_GEN_CANDS = {
  RES .. "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Generator.lua",
  RES .. "/Scripts/hsuanice_Scripts/Library/hsuanice_Metadata Generator.lua",
  RES .. "/Scripts/hsuanice/Library/hsuanice_Metadata Generator.lua",
  RES .. "/Scripts/Library/hsuanice_Metadata Generator.lua",
}
local LIB_EMB_CANDS = {
  RES .. "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Embed.lua",
  RES .. "/Scripts/hsuanice_Scripts/Library/hsuanice_Metadata Embed.lua",
  RES .. "/Scripts/hsuanice/Library/hsuanice_Metadata Embed.lua",
  RES .. "/Scripts/Library/hsuanice_Metadata Embed.lua",
}

local function load_first(cands)
  for _,p in ipairs(cands) do if exists(p) then
    local ok, mod = pcall(dofile, p)
    if ok and type(mod)=="table" then return mod, p end
  end end
  return nil, nil
end

local G, GPATH = load_first(LIB_GEN_CANDS)
local E, EPATH = load_first(LIB_EMB_CANDS)
local UMID_AVAILABLE = (G ~= nil and E ~= nil)

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
-- Parse fields from --out-xml
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

-- =========================
-- BWF MetaEdit functions
-- =========================
local function normalize_ixml_sidecar(path)
  local f = io.open(path, "rb")
  if not f then return end
  local data = f:read("*a")
  f:close()
  if not data or #data == 0 then return end
  data = data:gsub("\\n", "\n"):gsub("&#13;", "\n"):gsub("&#10;", "\n")
  data = collapse_blank_lines(data)
  local wf = io.open(path, "wb")
  if wf then wf:write(data) wf:close() end
end

local function do_ixml_copy(cli, src_wav, dst_wav)
  local src_iXML = src_wav .. ".iXML.xml"
  local dst_iXML = dst_wav .. ".iXML.xml"

  local code1, out1 = exec_shell(('"%s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, src_wav), 20000)
  msg(("    iXML: export src → sidecar (code=%s)"):format(tostring(code1)))

  if file_exists(src_iXML) then
    local x = read_file(src_iXML)
    if x then write_file(dst_iXML, x) end
    normalize_ixml_sidecar(dst_iXML)
    local code2, out2 = exec_shell(('"%s" --in-iXML-xml --continue-errors --verbose "%s"'):format(cli, dst_wav), 20000)
    msg(("    iXML: import sidecar → dst (code=%s)"):format(tostring(code2)))
    return code2 == 0
  else
    msg("    iXML: no sidecar exported (source has no iXML?) -> SKIP")
    return true
  end
end

local function do_core_copy(cli, src_wav, dst_wav)
  local codeR, outR = exec_shell(('"%s" --out-xml=- --continue-errors --verbose "%s"'):format(cli, src_wav), 30000)
  msg(("    CORE(FLAGS): export src (code=%s)"):format(tostring(codeR)))
  if codeR ~= 0 or not outR or #outR == 0 then
    return false
  end

  local fields = parse_core_from_xml_report(outR)

  -- Normalize fields
  for k, v in pairs(fields) do
    fields[k] = collapse_blank_lines(normalize_newlines(v))
  end

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

  local function sh_quote(s)
    if s == nil then return "''" end
    return "'" .. tostring(s):gsub("'", "'\"'\"'") .. "'"
  end

  local flags = {}
  local function add(k, v)
    if v and v ~= "" then
      flags[#flags+1] = ('--%s=%s'):format(k, sh_quote(v))
    end
  end

  local function add_info(k, v)
    if v and v ~= "" then
      if v:find("\n", 1, true) or v:find("\r", 1, true) then
        v = v:gsub("\r\n", "\n"):gsub("\r", "\n")
        local parts = {}
        for line in v:gmatch("[^\n]+") do
          line = line:gsub("^%s+", ""):gsub("%s+$", "")
          if line ~= "" then parts[#parts+1] = line end
        end
        v = table.concat(parts, " · ")
      end
      v = v:gsub('"','\\"')
      flags[#flags+1] = ('--%s="%s"'):format(k, v)
    end
  end

  add("Description", fields.Description)
  add_info("IARL", fields.IARL)
  add_info("IART", fields.IART)
  add_info("ICMT", fields.ICMT)
  add_info("ICRD", fields.ICRD)
  add_info("INAM", fields.INAM)
  add_info("ICOP", fields.ICOP)
  add_info("ICMS", fields.ICMS)
  add_info("IGNR", fields.IGNR)
  add_info("ISFT", fields.ISFT)
  add_info("ISBJ", fields.ISBJ)
  add_info("ITCH", fields.ITCH)
  add("Originator", fields.Originator)
  add("OriginatorReference", fields.OriginatorReference)
  add("OriginationDate", fields.OriginationDate)
  add("OriginationTime", fields.OriginationTime)
  add("UMID", fields.UMID)

  if #flags == 0 then
    msg("    CORE(FLAGS): nothing to write -> SKIP")
    return true
  end

  local cmd = ('"%s" %s "%s"'):format(cli, table.concat(flags, " "), dst_wav)
  local codeW, outW = exec_shell(cmd, 40000)
  msg(("    CORE(FLAGS): write dst (code=%s)"):format(tostring(codeW)))

  return codeW == 0
end

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

local function set_ixml_embedder(cli, wav_path, newval)
  local codeE = select(1, exec_shell(('"%s" --out-iXML-xml --continue-errors --verbose "%s"'):format(cli, wav_path), 20000))
  local side = wav_path .. ".iXML.xml"
  local xml = read_file(side) or ""
  if xml == "" then return true end

  local patched, n = xml:gsub("(<%s*EMBEDDER%s*>)(.-)(</%s*EMBEDDER%s*>)", "%1"..newval.."%3", 1)
  if n == 0 then
    if xml:find("<USER%s*>") then
      patched = xml:gsub("(<USER%s*>)", "%1<EMBEDDER>"..newval.."</EMBEDDER>", 1)
    else
      patched = xml:gsub("(</BWFXML>)", "<USER><EMBEDDER>"..newval.."</EMBEDDER></USER>%1", 1)
      patched = patched:gsub("(</iXML>)", "<USER><EMBEDDER>"..newval.."</EMBEDDER></USER>%1", 1)
    end
  end

  write_file(side, patched)
  normalize_ixml_sidecar(side)
  local codeI = select(1, exec_shell(('"%s" --in-iXML-xml --continue-errors --verbose "%s"'):format(cli, wav_path), 20000))
  remove_file_silent(side)
  return codeI == 0
end

-- =========================
-- UMID functions
-- =========================
local function read_umid_hex(cli, wav_path)
  local cmd = ('"%s" --out-xml=- "%s"'):format(cli, wav_path)
  local code, out = exec_shell(cmd, 20000)
  local umid = out:match("<UMID>([%x]+)</UMID>") or ""
  return umid, code, out
end

local function do_umid_embed(cli, wav_path, umid_strategy)
  if not UMID_AVAILABLE then
    msg("    UMID: Library not available -> SKIP")
    return true
  end

  local current_raw = select(1, read_umid_hex(cli, wav_path)) or ""
  local current_norm = G.normalize_umid(current_raw)
  local has_umid = (current_norm ~= "" and #current_norm == 64)

  msg(("    UMID: existing = %s"):format(has_umid and current_norm or "(none)"))

  local final_umid = nil

  if umid_strategy == 1 then
    -- Copy if present, Generate if missing
    if has_umid then
      final_umid = current_norm
      msg("    UMID: keeping existing")
    else
      final_umid = G.generate_umid_basic({ material = base(wav_path), instance = 0 })
      msg("    UMID: generating new")
    end
  elseif umid_strategy == 2 then
    -- Always generate new
    final_umid = G.generate_umid_basic({ material = base(wav_path), instance = os.time() % 1e6 })
    msg("    UMID: generating new (forced)")
  elseif umid_strategy == 3 then
    -- Patch missing only
    if has_umid then
      msg("    UMID: already has UMID -> SKIP")
      return true
    else
      final_umid = G.generate_umid_basic({ material = base(wav_path), instance = 0 })
      msg("    UMID: generating new (was missing)")
    end
  end

  if final_umid then
    local raw_umid = G.normalize_umid(final_umid):gsub("[^0-9A-Fa-f]", ""):upper()
    local ok, code, out, cmd = E.write_bext_umid(cli, wav_path, raw_umid)

    local after = select(1, read_umid_hex(cli, wav_path)) or ""
    local after_norm = G.normalize_umid(after)

    if ok and after_norm:upper() == raw_umid:upper() then
      msg(("    UMID: write OK (%s)"):format(raw_umid))
      return true
    else
      msg("    UMID: write FAILED")
      return false
    end
  end

  return true
end

-- =========================
-- Refresh helper
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
local function run_worker(enable_umid, umid_strategy)
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
  msg("=== Embed iXML + CORE + TR from Take1 → Active ===")
  msg(("CLI : %s"):format(cli))
  msg(("Sel : %d"):format(#items))
  msg(("UMID: %s (strategy=%s)"):format(enable_umid and "ON" or "OFF", tostring(umid_strategy)))
  if UMID_AVAILABLE then
    msg(("UMID Lib: G=%s  E=%s"):format(base(GPATH), base(EPATH)))
  end
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

        -- Detailed check for debugging
        local skip_reason = nil
        if not src then
          skip_reason = "src path is nil"
        elseif not dst then
          skip_reason = "dst path is nil"
        elseif not is_wav(src) then
          skip_reason = "src is not WAV: " .. tostring(src)
        elseif not is_wav(dst) then
          skip_reason = "dst is not WAV: " .. tostring(dst)
        elseif not file_exists(src) then
          skip_reason = "src file not found: " .. tostring(src)
        elseif not file_exists(dst) then
          skip_reason = "dst file not found: " .. tostring(dst)
        end

        if skip_reason then
          skip_cnt = skip_cnt + 1
          msg("  [SKIP] " .. skip_reason)
        else
          -- iXML
          local ok_ixml = do_ixml_copy(cli, src, dst)
          msg(("  iXML result    : %s"):format(ok_ixml and "OK" or "FAIL"))

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

          -- UMID (optional)
          local ok_umid = true
          if enable_umid then
            ok_umid = do_umid_embed(cli, dst, umid_strategy)
            msg(("  UMID result    : %s"):format(ok_umid and "OK" or "FAIL"))
          end

          if (ok_ixml and ok_core and (tr_written or tr_src==nil) and ok_umid) then
            ok_cnt = ok_cnt + 1
            modified[#modified+1] = it
            msg("  RESULT: OK")
          else
            fail_cnt = fail_cnt + 1
            msg("  RESULT: FAIL")
          end

          remove_file_silent(src .. ".iXML.xml")
          remove_file_silent(dst .. ".iXML.xml")
        end
      end
    end
  end

  R.Undo_EndBlock("Embed iXML + CORE + TR" .. (enable_umid and " + UMID" or ""), -1)

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
-- GFX GUI
-- =========================
local GUI = {
  title = "Embed iXML+BWF from Take1 (with UMID option)",
  width = 420,
  height = 220,

  -- Colors (dark theme)
  bg_color = {0.17, 0.17, 0.17},
  text_color = {0.9, 0.9, 0.9},
  btn_color = {0.3, 0.3, 0.35},
  btn_hover = {0.4, 0.4, 0.45},
  btn_press = {0.25, 0.25, 0.3},
  checkbox_color = {0.3, 0.6, 0.9},

  -- State
  enable_umid = false,
  umid_strategy = 1,  -- 1=Copy/Gen, 2=Always Gen, 3=Patch Missing
  mouse_down = false,
  should_close = false,
}

local function set_color(r, g, b)
  gfx.set(r, g, b, 1)
end

local function draw_rect(x, y, w, h, fill)
  if fill then
    gfx.rect(x, y, w, h, 1)
  else
    gfx.rect(x, y, w, h, 0)
  end
end

local function draw_text(x, y, text)
  gfx.x, gfx.y = x, y
  gfx.drawstr(text)
end

local function is_mouse_in(x, y, w, h)
  return gfx.mouse_x >= x and gfx.mouse_x <= x + w and
         gfx.mouse_y >= y and gfx.mouse_y <= y + h
end

local function draw_button(x, y, w, h, text)
  local hover = is_mouse_in(x, y, w, h)
  local pressed = hover and (gfx.mouse_cap & 1 == 1)

  if pressed then
    set_color(GUI.btn_press[1], GUI.btn_press[2], GUI.btn_press[3])
  elseif hover then
    set_color(GUI.btn_hover[1], GUI.btn_hover[2], GUI.btn_hover[3])
  else
    set_color(GUI.btn_color[1], GUI.btn_color[2], GUI.btn_color[3])
  end
  draw_rect(x, y, w, h, true)

  -- Border
  set_color(0.5, 0.5, 0.5)
  draw_rect(x, y, w, h, false)

  -- Text centered
  set_color(GUI.text_color[1], GUI.text_color[2], GUI.text_color[3])
  local tw, th = gfx.measurestr(text)
  draw_text(x + (w - tw) / 2, y + (h - th) / 2, text)

  -- Return click detection
  local clicked = hover and GUI.mouse_down and (gfx.mouse_cap & 1 == 0)
  return clicked
end

local function draw_checkbox(x, y, checked, text)
  local box_size = 16
  local hover = is_mouse_in(x, y, box_size + gfx.measurestr(text) + 8, box_size)

  -- Box background
  set_color(0.2, 0.2, 0.2)
  draw_rect(x, y, box_size, box_size, true)

  -- Box border
  set_color(0.5, 0.5, 0.5)
  draw_rect(x, y, box_size, box_size, false)

  -- Checkmark
  if checked then
    set_color(GUI.checkbox_color[1], GUI.checkbox_color[2], GUI.checkbox_color[3])
    gfx.rect(x + 3, y + 3, box_size - 6, box_size - 6, 1)
  end

  -- Label
  set_color(GUI.text_color[1], GUI.text_color[2], GUI.text_color[3])
  draw_text(x + box_size + 8, y + 1, text)

  -- Return click detection
  local clicked = hover and GUI.mouse_down and (gfx.mouse_cap & 1 == 0)
  return clicked
end

local function draw_radio(x, y, selected, index, text)
  local radio_size = 14
  local hover = is_mouse_in(x, y, radio_size + gfx.measurestr(text) + 8, radio_size)

  -- Circle background
  set_color(0.2, 0.2, 0.2)
  gfx.circle(x + radio_size/2, y + radio_size/2, radio_size/2, 1, 1)

  -- Circle border
  set_color(0.5, 0.5, 0.5)
  gfx.circle(x + radio_size/2, y + radio_size/2, radio_size/2, 0, 1)

  -- Selected dot
  if selected == index then
    set_color(GUI.checkbox_color[1], GUI.checkbox_color[2], GUI.checkbox_color[3])
    gfx.circle(x + radio_size/2, y + radio_size/2, radio_size/2 - 4, 1, 1)
  end

  -- Label
  set_color(GUI.text_color[1], GUI.text_color[2], GUI.text_color[3])
  draw_text(x + radio_size + 8, y, text)

  local clicked = hover and GUI.mouse_down and (gfx.mouse_cap & 1 == 0)
  return clicked
end

local function gui_loop()
  -- Check for close
  local char = gfx.getchar()
  if char == -1 or char == 27 or GUI.should_close then  -- -1=closed, 27=ESC
    gfx.quit()
    return
  end

  -- Track mouse state
  local mouse_now = (gfx.mouse_cap & 1 == 1)
  GUI.mouse_down = (not mouse_now) and GUI.mouse_was_down
  GUI.mouse_was_down = mouse_now

  -- Clear background
  set_color(GUI.bg_color[1], GUI.bg_color[2], GUI.bg_color[3])
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  -- Title
  gfx.setfont(1, "Arial", 16, 98)  -- Bold
  set_color(GUI.text_color[1], GUI.text_color[2], GUI.text_color[3])
  draw_text(20, 15, "Embed iXML + BWF Metadata")

  gfx.setfont(1, "Arial", 13)
  set_color(0.7, 0.7, 0.7)
  draw_text(20, 38, "Copy from TAKE 1 → ACTIVE take")

  -- UMID Checkbox
  local y_offset = 70
  if draw_checkbox(20, y_offset, GUI.enable_umid, "Generate SMPTE UMID (bext:UMID)") then
    GUI.enable_umid = not GUI.enable_umid
  end

  -- UMID Strategy (only show if enabled)
  if GUI.enable_umid then
    if not UMID_AVAILABLE then
      set_color(1, 0.5, 0.3)
      draw_text(40, y_offset + 25, "Warning: UMID library not found!")
    else
      set_color(0.6, 0.6, 0.6)
      draw_text(40, y_offset + 25, "Strategy:")

      if draw_radio(50, y_offset + 45, GUI.umid_strategy, 1, "Copy if present, Generate if missing") then
        GUI.umid_strategy = 1
      end
      if draw_radio(50, y_offset + 65, GUI.umid_strategy, 2, "Always generate new") then
        GUI.umid_strategy = 2
      end
      if draw_radio(50, y_offset + 85, GUI.umid_strategy, 3, "Patch missing only") then
        GUI.umid_strategy = 3
      end
    end
  end

  -- Buttons
  local btn_y = GUI.enable_umid and 180 or 120
  local btn_w = 180
  local btn_h = 28

  if draw_button(20, btn_y, btn_w, btn_h, "Start") then
    gfx.quit()
    run_worker(GUI.enable_umid, GUI.umid_strategy)
    return
  end

  if draw_button(220, btn_y, btn_w, btn_h, "Cancel") then
    GUI.should_close = true
  end

  gfx.update()
  R.defer(gui_loop)
end

-- =========================
-- Main
-- =========================
local function main()
  gfx.init(GUI.title, GUI.width, GUI.height)
  gfx.setfont(1, "Arial", 13)
  GUI.mouse_was_down = false
  gui_loop()
end

main()
