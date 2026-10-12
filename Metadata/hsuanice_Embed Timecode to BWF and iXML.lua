--[[
@description Embed Timecode to Active take (BWF + iXML) from Take 1 or Current Position
@version 26.1012.1641
@author hsuanice
@noindex
@changelog
  - Renamed to "Embed Timecode to BWF and iXML" (was "Timecode Embed Tool") as part of the 2026-10-12 naming clean-up.
@about
  Write Timecode (sample-accurate) to ALL metadata fields using BWF MetaEdit CLI.
  Writes to BOTH:
  - BWF BEXT TimeReference
  - iXML BWF_TIME_REFERENCE_LOW (for REAPER)
  - iXML TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO (for Wave Agent)

  Two modes:
  - Option 1: "Embed Take 1 TC" — copy TimeReference from Take 1 (original file) to the active take.
  - Option 2: "Embed TC to Item Start" — compute TimeReference from the selected item's start position and write it to the active take.

  After writing, the script can optionally refresh the items in REAPER:
  Set selected media offline (40440) → online (40439) → rebuild peaks (40441).

  Requirements:
  - BWF MetaEdit CLI (`bwfmetaedit`) installed and available in PATH, or you will be prompted to locate it.
    macOS (Homebrew):
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      brew install bwfmetaedit

  Important:
  - For best results, keep media files inside the REAPER project folder.
  - Files outside the project folder may be locked by REAPER and cannot be modified while the project is open.
  - The script will warn you when attempting to modify files outside the project folder.

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@links
  BWF MetaEdit (MediaArea): https://mediaarea.net/BWFMetaEdit
  Homebrew formula: https://formulae.brew.sh/formula/bwfmetaedit
--]]
-- =========================
-- Constants
-- =========================
local SCRIPT_NAME = "Timecode Embed Tool"
-- Version shown in the console: read from the @version tag in the header (single source of truth)
local SCRIPT_VERSION = "unknown"
do
  local script_path = debug.getinfo(1, "S").source:match("^@(.+)$")
  local f = script_path and io.open(script_path, "r")
  if f then
    for line in f:lines() do
      local ver = line:match("^@version%s+(.+)$")
      if ver then SCRIPT_VERSION = ver break end
      if line:match("^@changelog") then break end
    end
    f:close()
  end
end

-- =========================
-- REAPER API shortcuts
-- =========================
local R = reaper

-- =========================
-- Helpers
-- =========================

local OS = R.GetOS()
local IS_WIN = OS:match("Win")
local EXT_NS, EXT_KEY = "hsuanice_TCTools", "BWFMetaEditPath"

local function msg(s) R.ShowConsoleMsg(tostring(s).."\n") end
local function base(p) return (p and p:match("([^/\\]+)$")) or tostring(p) end
local function is_wav(p) return p and p:lower():sub(-4)==".wav" end

-- integer rounding helper (for stable sample-domain math)
local function round(x) return math.floor((x or 0) + 0.5) end


-- Shell wrapper for ExecProcess (handles spaces/quotes)
local function sh_wrap(cmd)
  if IS_WIN then
    return 'cmd.exe /C "'..cmd..'"'
  else
    return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'" -- escape single quotes safely
  end
end

-- Execute a shell command, return exit code and stdout
local function exec_shell(cmd, ms)
  local ret = R.ExecProcess(sh_wrap(cmd), ms or 20000) or ""
  local code, out = ret:match("^(%d+)\n(.*)$")
  return tonumber(code or -1), (out or "")
end

-- Check bwfmetaedit executable
local function test_cli(p)
  if not p or p=="" then return false end
  local code = select(1, exec_shell('"'..p..'" --Version', 4000))
  return code == 0
end

-- Resolve bwfmetaedit path (remember via extstate)
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

-- Read TimeReference via --out-xml=-
local function read_TR(cli, wav_path)
  local cmd = ('"%s" --out-xml=- "%s"'):format(cli, wav_path)
  local code, out = exec_shell(cmd, 20000)
  local tr = tonumber(out:match("<TimeReference>(%d+)</TimeReference>") or "")
  return tr, code, out
end

-- Write BWF TimeReference via --Timereference=
local function write_bwf_tr(cli, wav_path, tr)
  local cmd = ('"%s" --Timereference=%d "%s"'):format(cli, tr, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return code, out
end

-- Write iXML TimeReference (both BEXT and SPEED fields)
-- Returns 0 = iXML updated, 2 = nothing to update (no iXML chunk, or no TimeReference
-- fields in it — e.g. files rendered by REAPER), 1 = error.
local function write_ixml_tr(cli, wav_path, tr)
  -- Step 1: Extract iXML to temp file
  local tmp_path = os.tmpname()..".xml"

  -- Get iXML content
  local cmd = ('"%s" --out-iXML=- "%s"'):format(cli, wav_path)
  local code, ixml_content = exec_shell(cmd, 20000)

  if code ~= 0 then
    msg("    [iXML] Failed to extract iXML content")
    return 1
  end
  if not ixml_content or not ixml_content:find("%S") then
    msg("    [iXML] No iXML chunk in this file - nothing to update")
    return 2
  end

  -- Step 2: Modify XML content using string replacement
  local updated_fields = {}
  local modified = ixml_content

  -- Update BWF_TIME_REFERENCE_LOW in BEXT section
  local pattern1 = "(<BWF_TIME_REFERENCE_LOW>)%d+(</BWF_TIME_REFERENCE_LOW>)"
  if modified:match(pattern1) then
    modified = modified:gsub(pattern1, "%1"..tostring(tr).."%2")
    table.insert(updated_fields, "BEXT/BWF_TIME_REFERENCE_LOW")
  end

  -- Update TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO in SPEED section
  local pattern2 = "(<TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO>)%d+(</TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO>)"
  if modified:match(pattern2) then
    modified = modified:gsub(pattern2, "%1"..tostring(tr).."%2")
    table.insert(updated_fields, "SPEED/TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO")
  end

  if #updated_fields == 0 then
    msg("    [iXML] No TimeReference fields in iXML - nothing to update")
    return 2
  end

  msg(("    [iXML] Updated fields: %s"):format(table.concat(updated_fields, ", ")))

  -- Step 3: Write modified XML to temp file
  local f = io.open(tmp_path, "w")
  if not f then
    msg("    [iXML] Failed to create temp file")
    return 1
  end
  f:write(modified)
  f:close()

  -- Step 4: Write modified iXML back to WAV file
  local cmd2 = ('"%s" --in-iXML="%s" "%s"'):format(cli, tmp_path, wav_path)
  local code2, out2 = exec_shell(cmd2, 20000)

  -- Clean up temp file
  os.remove(tmp_path)

  return code2
end

-- Write TimeReference to BOTH BWF and iXML
local function write_TR(cli, wav_path, tr)
  msg(("    [BWF] Writing TimeReference: %d"):format(tr))
  local bwf_code, bwf_out = write_bwf_tr(cli, wav_path, tr)

  msg(("    [iXML] Writing TimeReference to iXML fields..."))
  local ixml_code = write_ixml_tr(cli, wav_path, tr)

  -- Return 0 when BWF succeeded and iXML was updated or had nothing to update
  if bwf_code == 0 and ixml_code == 0 then
    msg("    [SUCCESS] All metadata fields updated")
    return 0
  elseif bwf_code == 0 and ixml_code == 2 then
    msg("    [SUCCESS] BWF updated (iXML has no TimeReference fields to update)")
    return 0
  elseif bwf_code == 0 then
    msg("    [PARTIAL] BWF updated, iXML failed")
    return 1
  elseif ixml_code == 0 then
    msg("    [PARTIAL] iXML updated, BWF failed")
    return 1
  else
    msg("    [FAIL] Both BWF and iXML write failed")
    return 1
  end
end

-- Quantize seconds to integer samples by truncating toward -inf (tiny epsilon to avoid +1)
local QUANT_EPS = 1e-12
local function quantize_samples_floor(sr, sec)
  return math.floor((sec or 0) * (sr or 48000) + QUANT_EPS)
end

-- Helper: 判斷一段秒數在該 SR 下是否「落在整數 sample 邊界」
local function is_on_sample_boundary(sr, sec)
  if not sr then return false end
  local smp = (sec or 0) * sr
  local smp_floor = math.floor(smp + QUANT_EPS)
  return math.abs(smp - smp_floor) < 1e-9
end

-- Get file modification time
local function get_file_mtime(path)
  if not path or path == "" then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  f:close()
  -- Use stat command to get modification time
  local cmd
  if IS_WIN then
    cmd = string.format('forfiles /P "%s" /M "%s" /C "cmd /c echo @fdate @ftime"',
                        path:match("(.+)[\\/][^\\/]+$"), path:match("[^\\/]+$"))
  else
    cmd = string.format('stat -f "%%m" "%s" 2>/dev/null || stat -c "%%Y" "%s" 2>/dev/null', path, path)
  end
  local _, out = exec_shell(cmd, 2000)
  return out and out:match("%d+")
end

-- Test if file is writable
local function is_file_writable(path)
  if not path or path == "" then return false end
  local f = io.open(path, "r+b")
  if not f then return false end
  f:close()
  return true
end

-- Check if file is inside project folder
local function is_in_project_folder(file_path)
  if not file_path or file_path == "" then return false end

  local proj_path, _ = R.GetProjectPath("")
  if not proj_path or proj_path == "" then return false end

  -- Normalize paths (remove trailing slashes, convert to lowercase for comparison)
  local norm_proj = proj_path:gsub("[/\\]+$", ""):lower()
  local norm_file = file_path:lower()

  -- Check if file path starts with project path
  return norm_file:sub(1, #norm_proj) == norm_proj
end


-- Track label: "Track <index>: <name>"
local function item_track_label(it)
  local tr = it and reaper.GetMediaItem_Track(it)
  if not tr then return "(no track)" end
  local _, name = reaper.GetTrackName(tr)
  local idx = reaper.CSurf_TrackToID(tr, false) or 0
  if not name or name == "" then
    return ("Track %d"):format(idx)
  else
    return ("Track %d: %s"):format(idx, name)
  end
end

-- Select only these items
local function select_only(items)
  R.SelectAllMediaItems(0, false)
  for _,it in ipairs(items) do
    if it and R.ValidatePtr(it, "MediaItem*") then
      R.SetMediaItemSelected(it, true)
    end
  end
  R.UpdateArrange()
end

-- Online → Rebuild peaks (items are already offline)
local function refresh_and_rebuild(modified_items)
  if not modified_items or #modified_items == 0 then return end
  select_only(modified_items)
  R.Main_OnCommand(40439, 0) -- Item: Set selected media online
  R.Main_OnCommand(40441, 0) -- Peaks: Rebuild peaks for selected items
end

-- =========================
-- Core worker
-- =========================

local function perform_embed(mode)
  gfx.quit()

  R.ClearConsole()
  msg("=== "..SCRIPT_NAME.." v"..SCRIPT_VERSION.." ===")
  msg("Mode: "..(mode == 1 and "Embed Take 1 TC" or "Embed TC to Item Start"))
  msg("")

  local cli = resolve_cli()
  if not cli then
    R.MB("bwfmetaedit not found. Please install it first:\n\nmacOS: brew install bwfmetaedit", "Error", 0)
    return
  end
  msg("BWF MetaEdit: "..cli)
  msg("")

  local items = {}
  local n = R.CountSelectedMediaItems(0)
  for i = 0, n-1 do
    items[#items+1] = R.GetSelectedMediaItem(0, i)
  end

  if #items == 0 then
    R.MB("No items selected.", SCRIPT_NAME, 0)
    return
  end

  msg(("Processing %d selected items...\n"):format(#items))

  -- Set all items offline FIRST (critical for file modification)
  msg("Setting items offline to release file locks...")
  select_only(items)
  R.Main_OnCommand(40440, 0) -- Item: Set selected media offline
  -- Wait for REAPER to release file locks
  local start_time = R.time_precise()
  while R.time_precise() - start_time < 2.0 do
    -- Wait 2 seconds
  end
  msg("Items offline. Ready to write metadata.\n")

  local ok_cnt, fail_cnt, skip_cnt = 0, 0, 0
  local modified = {}
  local aborted = false

  for idx, it in ipairs(items) do
    if not it or not R.ValidatePtr(it, "MediaItem*") then
      msg(("Item %d: [SKIP] invalid pointer"):format(idx))
      skip_cnt = skip_cnt + 1
    else
      local takeA = R.GetActiveTake(it)
      if not takeA or R.TakeIsMIDI(takeA) then
        msg(("Item %d: [SKIP] no active audio take"):format(idx))
        skip_cnt = skip_cnt + 1
      else
        local src = R.GetMediaItemTake_Source(takeA)
        local dst_path = src and R.GetMediaSourceFileName(src)

        if not dst_path or not is_wav(dst_path) then
          msg(("Item %d: [SKIP] not WAV (take=%s)"):format(idx, R.GetTakeName(takeA)))
          skip_cnt = skip_cnt + 1
        else
          msg(("Item %d: Processing '%s'"):format(idx, base(dst_path)))

          local target_tr = nil

          -- Compute target TimeReference based on mode
          if mode == 1 then
            -- Mode 1: Take 1 -> Active take
            local take1 = R.GetMediaItemTake(it, 0)
            if not take1 or R.TakeIsMIDI(take1) then
              fail_cnt = fail_cnt + 1
              msg("    [FAIL] Take 1 is not audio")
            else
              local src1 = R.GetMediaItemTake_Source(take1)
              local src_path = src1 and R.GetMediaSourceFileName(src1)

              if not src_path or not is_wav(src_path) then
                fail_cnt = fail_cnt + 1
                msg("    [FAIL] Take 1 is not WAV")
              else
                local srcTR_smp = select(1, read_TR(cli, src_path))

                if srcTR_smp then
                  local src1_offs = R.GetMediaItemTakeInfo_Value(take1, "D_STARTOFFS") or 0.0
                  local dstA_offs = R.GetMediaItemTakeInfo_Value(takeA, "D_STARTOFFS") or 0.0
                  local edge_sec = src1_offs - dstA_offs

                  local dst_sr = (function()
                    local v = select(2, R.GetMediaSourceSampleRate(src)) or 0
                    if not v or v <= 0 then v = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000 end
                    return math.floor(v + 0.5)
                  end)()

                  local srcTR_sec = srcTR_smp / 48000.0
                  local dstTR_sec = srcTR_sec + edge_sec
                  local dstTR_smp = quantize_samples_floor(dst_sr, dstTR_sec)
                  if dstTR_smp < 0 then dstTR_smp = 0 end

                  target_tr = dstTR_smp

                  msg(("    Source: TR=%d (%.6fs)  StartInSource=%.6fs"):format(srcTR_smp, srcTR_sec, src1_offs))
                  msg(("    Active: StartInSource=%.6fs  SR=%dHz"):format(dstA_offs, dst_sr))
                  msg(("    Edge preview: %.15fs (quantized=%.15fs)")
                    :format(edge_sec, (quantize_samples_floor(dst_sr, edge_sec) / dst_sr)))
                  msg(("    RESULT dstTR=%d (samples)"):format(target_tr))
                else
                  fail_cnt = fail_cnt + 1
                  msg("    [FAIL] failed to read take1 TR")
                end
              end
            end
          else
            -- Mode 2: Embed TC to Item Start (considering project time offset)
            local dst_sr = (function()
              local s = R.GetMediaItemTake_Source(takeA)
              local v = s and select(2, R.GetMediaSourceSampleRate(s)) or 0
              if not v or v <= 0 then v = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000 end
              return math.floor(v + 0.5)
            end)()

            local proj_offset_sec = R.GetProjectTimeOffset(0, false) or 0.0
            local pos_sec      = R.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
            local dst_offs_sec = R.GetMediaItemTakeInfo_Value(takeA, "D_STARTOFFS") or 0.0

            local item_tc_sec = proj_offset_sec + pos_sec
            local dstTR_sec = item_tc_sec - dst_offs_sec
            local dstTR_smp = quantize_samples_floor(dst_sr, dstTR_sec)
            if dstTR_smp < 0 then dstTR_smp = 0 end
            target_tr = dstTR_smp

            msg(("    ProjectOffset: %.15fs (%d smp)"):format(proj_offset_sec, quantize_samples_floor(dst_sr, proj_offset_sec)))
            msg(("    ItemPos: %.15fs (%d smp)  StartInSource(dst): %.15fs (%d smp)  SR(dst): %dHz")
              :format(
                pos_sec,       quantize_samples_floor(dst_sr, pos_sec),
                dst_offs_sec,  quantize_samples_floor(dst_sr, dst_offs_sec),
                dst_sr
              ))
            msg(("    ItemTC: %.15fs (%d smp)"):format(item_tc_sec, quantize_samples_floor(dst_sr, item_tc_sec)))
            msg(("    RESULT dstTR=%d (samples)"):format(target_tr))
          end

          if target_tr then
            local existing_tr = select(1, read_TR(cli, dst_path))
            msg(("    EXIST dst TR : %s"):format(tostring(existing_tr)))

            local do_write = true

            if do_write then
              -- Check if file is in project folder
              local in_proj = is_in_project_folder(dst_path)
              msg(("    IN PROJECT FOLDER : %s"):format(tostring(in_proj)))

              if not in_proj then
                local track_lbl = item_track_label(it)
                local fname = base(dst_path)
                local warning = table.concat({
                  "WARNING: File is outside the project folder!",
                  "",
                  "Track: " .. track_lbl,
                  "File:  " .. fname,
                  "Path:  " .. dst_path,
                  "",
                  "Files outside the project folder may be locked by REAPER",
                  "and cannot be modified while the project is open.",
                  "",
                  "Recommended: Copy the file to the project folder first.",
                  "",
                  "Continue anyway?"
                }, "\n")

                local btn = R.MB(warning, "Timecode Embed - File Location Warning", 4) -- Yes/No
                if btn ~= 6 then -- Not "Yes"
                  skip_cnt = skip_cnt + 1
                  msg("    [SKIP] user declined - file outside project folder")
                  do_write = false
                end
              end
            end

            if do_write then
              -- Check if file is writable
              local writable = is_file_writable(dst_path)
              msg(("    FILE WRITABLE : %s"):format(tostring(writable)))

              if not writable then
                fail_cnt = fail_cnt + 1
                msg("    RESULT: FAIL - File is locked or not writable")
              else
                -- Get file modification time before writing
                local mtime_before = get_file_mtime(dst_path)

                local wc = select(1, write_TR(cli, dst_path, target_tr))

              -- Check if file was actually modified
              local mtime_after = get_file_mtime(dst_path)
              local file_changed = (mtime_before ~= mtime_after)
              msg(("    FILE MODIFIED : %s (mtime: %s -> %s)"):format(
                tostring(file_changed), tostring(mtime_before), tostring(mtime_after)))

              local vr = select(1, read_TR(cli, dst_path))
              msg(("    VERIFY dst TR : %s"):format(tostring(vr)))

                if wc == 0 and vr == target_tr and file_changed then
                  ok_cnt = ok_cnt + 1
                  modified[#modified+1] = it
                  msg("    RESULT: OK")
                else
                  fail_cnt = fail_cnt + 1
                  if not file_changed then
                    msg("    RESULT: FAIL - File was not modified (still locked?)")
                  else
                    msg("    RESULT: FAIL")
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  local summary = ("Summary: OK=%d  FAIL=%d  SKIP=%d"):format(ok_cnt, fail_cnt, skip_cnt)
  if aborted then summary = summary .. "  (ABORTED)" end
  msg(summary); msg("=== End ===")

  if aborted then
    R.MB("Operation was aborted by user.\n\n" .. summary, "Timecode Embed", 0)
  end

  -- Always bring items back online and rebuild peaks
  if #modified > 0 then
    msg("Bringing items online and rebuilding peaks...")
    refresh_and_rebuild(modified)
    R.MB(summary .. ("\n\n%d item(s) updated and refreshed."):format(#modified), "Timecode Embed", 0)
  else
    -- No items modified, but still need to bring items back online
    msg("Bringing items back online...")
    select_only(items)
    R.Main_OnCommand(40439, 0) -- Item: Set selected media online
    R.MB(summary .. "\n\nNo items were modified.", "Timecode Embed", 0)
  end
end

-- =========================
-- UI (GFX)
-- =========================

-- GFX Button helper
local function gfx_button(x, y, w, h, label)
  local mx, my = gfx.mouse_x, gfx.mouse_y
  local hover = mx >= x and mx <= x+w and my >= y and my <= y+h

  -- Draw button background
  if hover then
    gfx.set(0.4, 0.4, 0.5, 1)
  else
    gfx.set(0.3, 0.3, 0.3, 1)
  end
  gfx.rect(x, y, w, h, 1)

  -- Draw button border
  gfx.set(0.6, 0.6, 0.6, 1)
  gfx.rect(x, y, w, h, 0)

  -- Draw label
  gfx.set(1, 1, 1, 1)
  gfx.x = x + 10
  gfx.y = y + (h - gfx.texth) / 2
  gfx.drawstr(label)

  return hover
end

-- GFX main loop
local WIN_W, WIN_H = 450, 260
local BTN_W, BTN_H = 410, 35
local MARGIN = 20

local chosen_mode = nil
local last_mouse_cap = 0

gfx.init("Timecode Embed Tool", WIN_W, WIN_H)
gfx.setfont(1, "Arial", 16)

local function loop()
  local char = gfx.getchar()

  -- ESC (27) or window close (-1) to exit
  if char == 27 or char == -1 then
    gfx.quit()
    return
  end

  -- Clear background
  gfx.set(0.15, 0.15, 0.15, 1)
  gfx.rect(0, 0, WIN_W, WIN_H, 1)

  -- Draw title
  gfx.set(1, 1, 1, 1)
  gfx.x = MARGIN
  gfx.y = 15
  gfx.drawstr("Write Timecode to ACTIVE take:")

  -- Draw subtitle
  gfx.setfont(2, "Arial", 12)
  gfx.set(0.7, 0.7, 0.7, 1)
  gfx.x = MARGIN
  gfx.y = 40
  gfx.drawstr("(Updates BWF + iXML metadata)")

  gfx.setfont(1, "Arial", 16)

  -- Button positions
  local btn_x = MARGIN
  local btn1_y = 70
  local btn2_y = btn1_y + BTN_H + 10
  local btn3_y = btn2_y + BTN_H + 10

  -- Draw buttons and check for clicks
  local hover1 = gfx_button(btn_x, btn1_y, BTN_W, BTN_H, "Embed Take 1 TC")
  local hover2 = gfx_button(btn_x, btn2_y, BTN_W, BTN_H, "Embed TC to Current Position")
  local hover3 = gfx_button(btn_x, btn3_y, BTN_W, BTN_H, "Cancel")

  -- Detect mouse button release (was pressed, now released)
  local mouse_released = last_mouse_cap == 1 and gfx.mouse_cap == 0

  -- Handle button clicks on mouse release
  if mouse_released then
    if hover1 then
      chosen_mode = 1
    elseif hover2 then
      chosen_mode = 2
    elseif hover3 then
      gfx.quit()
      return
    end
  end

  last_mouse_cap = gfx.mouse_cap

  gfx.update()

  -- Execute chosen mode
  if chosen_mode then
    perform_embed(chosen_mode)
    chosen_mode = nil
  end

  R.defer(loop)
end

loop()
