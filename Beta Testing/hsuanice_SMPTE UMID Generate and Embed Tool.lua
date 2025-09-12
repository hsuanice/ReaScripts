--[[
@description SMPTE UMID Generate & Embed Tool (bext:UMID only)
@version 0.1.1
@author hsuanice
@about
  Generate a strict SMPTE ST 330 Basic UMID (32B → 64 hex) and embed it
  into WAV's BWF bext:UMID using BWF MetaEdit CLI. UI and prompts mirror
  the "BWF TimeReference Embed Tool".
  - Strategy:
      1) Copy if present, Generate if missing (default)
      2) Always generate new
      3) Patch missing only (do nothing if already present)
  - Display Pro Tools-style (26-6-16-12-4, lowercase) for human check.
  - iXML UMID is NOT written (leave to recorders).

@changelog
  v0.1.1 (2025-09-12)
    - Fixed: Updated call to E.write_bext_umid() to use the new v0.2.1
      signature (cli_path, wav_path, umid_hex).
    - Added: Normalize and sanitize UMID before writing
      * Remove any non-hex characters, force uppercase.
      * Added DEBUG log: print UMID length and hex check result.
    - Improved: Verification now compares normalized UMID
      against post-write readback from bwfmetaedit.
    - Result: More robust write + verify cycle, avoids
      hidden character issues and function mismatch errors.
  v0.1.0
    - Initial: UI (ReaImGui / fallback prompt), batch over selected items,
      per-item verification, summary & optional refresh.
]]

local R = reaper

-- =========================
-- Config / Paths
-- =========================
local function msg(s) R.ShowConsoleMsg(tostring(s).."\n") end
local function exists(path) local f=io.open(path,"rb"); if f then f:close(); return true end end
local RES = R.GetResourcePath()

-- Try common locations for libraries
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
if not G or not E then
  R.MB("找不到 Metadata Generator/Embed library。\n請確認兩個檔案都在 Scripts/…/Library/ 之下。","SMPTE UMID Tool",0)
  return
end

-- =========================
-- Helpers
-- =========================
local OS = R.GetOS()
local IS_WIN = OS:match("Win")

local function base(p) return (p and p:match("([^/\\]+)$")) or tostring(p) end
local function is_wav(p) return p and p:lower():sub(-4)==".wav" end

-- read bext:UMID via bwfmetaedit --out-xml=-
local function read_umid_hex(cli, wav_path)
  local function sh_wrap(cmd)
    if IS_WIN then return 'cmd.exe /C "'..cmd..'"'
    else return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'" end
  end
  local function exec_shell(cmd, ms)
    local ret = R.ExecProcess(sh_wrap(cmd), ms or 20000) or ""
    local code,out = ret:match("^(%d+)\n(.*)$")
    return tonumber(code or -1), (out or "")
  end
  local cmd = ('"%s" --out-xml=- "%s"'):format(cli, wav_path)
  local code, out = exec_shell(cmd, 20000)
  local umid = out:match("<UMID>([%x]+)</UMID>") or ""
  return umid, code, out
end

-- Resolve bwfmetaedit via your Embed’s bwfme_exec pathing or direct test
local function resolve_cli_from_embed()
  -- Try known paths used by your TimeReference tool’s resolver
  local cands = IS_WIN and {
    [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]],
    [[C:\Program Files (x86)\BWF MetaEdit\bwfmetaedit.exe]],
    "bwfmetaedit",
  } or { "/opt/homebrew/bin/bwfmetaedit", "/usr/local/bin/bwfmetaedit", "bwfmetaedit" }

  local function test_cli(p)
    if not p or p=="" then return false end
    local ret = R.ExecProcess((IS_WIN and ('cmd.exe /C "'..p..' --Version"') or "/bin/sh -lc '\""..p.."\" --Version'"), 4000) or ""
    local code = ret:match("^(%d+)")
    return tonumber(code or -1) == 0
  end

  for _,p in ipairs(cands) do if test_cli(p) then return p end end
  local hint = IS_WIN and [[C:\Program Files\BWF MetaEdit\bwfmetaedit.exe]] or "/opt/homebrew/bin/bwfmetaedit"
  local ok, picked = R.GetUserFileNameForRead(0, hint, 'Locate "bwfmetaedit" executable (Cancel to abort)')
  if ok and test_cli(picked) then return picked end
  return nil
end

-- =========================
-- Core Worker
-- =========================
-- strategy: 1=Copy if present, Generate if missing (default)
--           2=Always generate new
--           3=Patch missing only
local function do_embed(strategy)
  local cli = resolve_cli_from_embed()
  if not cli then
    local hint = IS_WIN and "請安裝 BWF MetaEdit，或指定 bwfmetaedit.exe 路徑。"
                       or  "macOS 可用 Homebrew：brew install bwfmetaedit"
    R.MB("找不到 BWF MetaEdit（bwfmetaedit）。\n"..hint, "SMPTE UMID", 0)
    return
  end

  local sel = R.CountSelectedMediaItems(0)
  if sel == 0 then
    R.MB("請先選取至少一個 item。", "SMPTE UMID", 0)
    return
  end

  R.ClearConsole()
  msg(("=== SMPTE UMID Tool ===\nCLI : %s\nLib :\n  G=%s (v%s)\n  E=%s (v%s)\nSel : %d\n")
      :format(cli, base(GPATH), tostring(G.VERSION), base(EPATH), tostring(E.VERSION), sel))

  local ok_cnt, fail_cnt, skip_cnt = 0, 0, 0
  local modified = {}

  R.Undo_BeginBlock()

  for i=0, sel-1 do
    local it = R.GetSelectedMediaItem(0, i)
    local take = it and R.GetActiveTake(it)
    if not (it and take) then
      skip_cnt = skip_cnt + 1
      msg(("Item %d [SKIP] no active take"):format(i+1))
    else
      local src = R.GetMediaItemTake_Source(take)
      local path = src and R.GetMediaSourceFileName(src, "") or nil
      msg(("Item %d -------------------------"):format(i+1))
      msg(("  dst : %s"):format(base(path or "(nil)")))
      if not (path and is_wav(path)) then
        skip_cnt = skip_cnt + 1
        msg("  [SKIP] target is not WAV")
      else
        -- read current bext:UMID (raw)
        local current_raw = select(1, read_umid_hex(cli, path)) or ""
        local current_norm = G.normalize_umid(current_raw)
        local has_umid = (current_norm ~= "" and #current_norm == 64)

        msg(("    EXIST UMID : %s"):format(has_umid and current_norm or "(none)"))

        local final_umid = nil
        if strategy == 1 then
          -- Copy if present, Generate if missing
          if has_umid then
            final_umid = current_norm
          else
            -- material: 以檔名基底當作語意來源；instance 0
            final_umid = G.generate_umid_basic({ material = base(path), instance = 0 })
          end
        elseif strategy == 2 then
          -- Always generate new
          final_umid = G.generate_umid_basic({ material = base(path), instance = os.time() % 1e6 })
        else
          -- Patch missing only
          if has_umid then
            msg("    [SKIP] already has UMID (patch-missing only)")
            skip_cnt = skip_cnt + 1
          else
            final_umid = G.generate_umid_basic({ material = base(path), instance = 0 })
          end
        end

        if final_umid then
          -- 先正規化，避免混入不可見字元或 dash
          local raw_umid = G.normalize_umid(final_umid):gsub("[^0-9A-Fa-f]", ""):upper()
          msg(("    DEBUG UMID len=%d isHEX=%s")
              :format(#raw_umid, tostring(raw_umid:match("^[0-9A-F]+$") ~= nil)))

          -- 新版簽名：要把 CLI 路徑一起傳進去
          local ok, code = E.write_bext_umid(cli, path, raw_umid)

          -- 驗證：用 CLI 讀回，再正規化比對
          local after = select(1, read_umid_hex(cli, path)) or ""
          local after_norm = G.normalize_umid(after)
          local pt_view = G.format_umid_protools_style(raw_umid)

          msg(("    WRITE UMID : %s  (code=%s)"):format(raw_umid, tostring(code)))
          msg(("    VERIFY     : %s"):format(after_norm))
          msg(("    PT-STYLE   : %s"):format(pt_view))

          if ok and after_norm:upper() == raw_umid:upper() then
            ok_cnt = ok_cnt + 1
            modified[#modified+1] = it
            msg("    RESULT: OK")
          else
            fail_cnt = fail_cnt + 1
            msg("    RESULT: FAIL")
          end
        end

        

      end
    end
  end

  R.Undo_EndBlock("SMPTE UMID embed (bext)", -1)

  local summary = ("Summary: OK=%d  FAIL=%d  SKIP=%d"):format(ok_cnt, fail_cnt, skip_cnt)
  msg(summary); msg("=== End ===")

  if #modified > 0 then
    local btn = R.MB(
      summary .. ("\n\nRefresh now?\n(%d item(s) will be refreshed)"):format(#modified),
      "SMPTE UMID", 4 -- Yes/No
    )
    if btn == 6 and E.refresh_media_item_take then
      -- refresh each modified item once
      for _,it in ipairs(modified) do
        local take = R.GetActiveTake(it)
        if take then E.refresh_media_item_take(take) end
      end
    end
  else
    R.MB(summary .. "\n\nNo item embedded, no need to refresh", "SMPTE UMID", 0)
  end
end

-- =========================
-- UI (ReaImGui; mirror TR tool style)
-- =========================
local has_imgui = type(R.ImGui_CreateContext) == "function"
if not has_imgui then
  local ok, inp = R.GetUserInputs("SMPTE UMID", 1,
    "Select Strategy: 1=Copy/Gen, 2=Always Gen, 3=Patch Missing", "1")
  if not ok then return end
  local s = tonumber((inp or ""):match("(%d+)") or "1") or 1
  if s < 1 or s > 3 then s = 1 end
  do_embed(s)
  return
end

local imgui = R
local ctx  = imgui.ImGui_CreateContext('SMPTE UMID Tool', imgui.ImGui_ConfigFlags_NoSavedSettings())
local FONT = imgui.ImGui_CreateFont('sans-serif', 16); imgui.ImGui_Attach(ctx, FONT)

local BTN_W, BTN_H = 360, 28
local chosen, should_close = 1, false

local function loop()
  imgui.ImGui_SetNextWindowSize(ctx, 420, 210, imgui.ImGui_Cond_Once())
  local visible, open = imgui.ImGui_Begin(ctx, 'SMPTE UMID Tool', true)
  if visible then
    imgui.ImGui_Text(ctx, 'Generate & embed SMPTE UMID (bext:UMID only):')
    imgui.ImGui_Dummy(ctx, 1, 6)
    imgui.ImGui_Text(ctx, 'Strategy:')
    local labels = { '1) Copy if present, Generate if missing (default)',
                     '2) Always generate new',
                     '3) Patch missing only' }
    for i=1,3 do
      local sel = (chosen == i)
      if imgui.ImGui_RadioButton(ctx, labels[i], sel) then chosen = i end
    end
    imgui.ImGui_Dummy(ctx, 1, 8)
    if imgui.ImGui_Button(ctx, 'Run', BTN_W, BTN_H) then do_embed(chosen); should_close=true end
    imgui.ImGui_SameLine(ctx)
    if imgui.ImGui_Button(ctx, 'Cancel', 100, BTN_H) then should_close = true end

    -- ESC to close
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
