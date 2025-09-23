--[[
@description Embed BWF TimeReference to Active take from Take 1 or Current Position TC
@version 250924_0257 ok
@author hsuanice

@about
  Write BWF TimeReference (sample-accurate) to the ACTIVE take using BWF MetaEdit CLI.
  - Option 1: "Embed Take 1 TC" — copy TimeReference from Take 1 (original file) to the active take.
  - Option 2: "Embed TC to Item Start" — compute TimeReference from the selected item's start position and write it to the active take.
  After writing, the script can optionally refresh the items in REAPER:
  Set selected media offline (40440) → online (40439) → rebuild peaks (40441).

  Requirements:
  - BWF MetaEdit CLI (`bwfmetaedit`) installed and available in PATH, or you will be prompted to locate it.
    macOS (Homebrew):
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      brew install bwfmetaedit
  - ReaImGui extension for the minimal UI.

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@links
  BWF MetaEdit (MediaArea): https://mediaarea.net/BWFMetaEdit
  Homebrew formula: https://formulae.brew.sh/formula/bwfmetaedit
  ReaImGui: https://github.com/cfillion/reaper-imgui

@changelog
  v250924_0257
    - Fix: Align calculation now robust against item position moves.
    - Always compute TimeReference as: TR(src) + StartOffset(src) = edgeTC,
      then convert to dst using (edgeTC - StartOffset(dst)) * dstSR.
    - Correctly handles handles and non-zero offsets.
    - Console output shows raw vs calc offsets, project pivot, and final dstTR.
    - Ensures embedded TR stays sync between original take and rendered/glued take.
  v0.7.4
    - Option 2: refine the "Yes to All" flow — after the first "Yes", ask once whether to apply to all remaining items.
      If "No", do not ask again for the rest of this run; if "Yes", overwrite all remaining without further prompts.
    - Batch flags are reset per run; no duplicate "apply to all" prompts.
    - Minor copy and doc cleanups.

  v0.7.3
    - Option 2: add "Yes to All" choice to overwrite remaining items without per-item prompts.

  v0.7.2
    - Option 2: overwrite warning now shows Track name and Item start position in the project's time display.
    - Add safety prompt before overwriting a non-zero TimeReference.

  v0.7.1
    - UI: ESC to close; add "Cancel" button.
    - Remove ImGui_DestroyContext usage; clean UI shutdown.
]]

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

-- Write TimeReference via --Timereference=
local function write_TR(cli, wav_path, tr)
  local cmd = ('"%s" --Timereference=%d "%s"'):format(cli, tr, wav_path)
  local code, out = exec_shell(cmd, 20000)
  return code, out
end

-- Track label: "Track <index>: <name>"
local function item_track_label(it)
  local tr = it and reaper.GetMediaItem_Track(it)
  if not tr then return "(no track)" end
  local _, name = reaper.GetTrackName(tr)
  local idx = reaper.CSurf_TrackToID(tr, false) or 0
  if not name or name == "" then
    return ("Track %d"):format(idx)
  end
  return ("Track %d: %s"):format(idx, name)
end

-- Project time formatter (uses project display: timecode / bars:beats / etc.)
local function format_project_time(pos)
  return reaper.format_timestr_pos(pos or 0, "", -1)
end

-- Overwrite warning with track/file/path/project-time context (Option 2)
local function confirm_overwrite_TR_with_context(it, dst_path, existing_tr, new_tr, item_start_pos)
  local track_lbl = item_track_label(it)
  local proj_pos  = format_project_time(item_start_pos or 0)
  local fname     = base(dst_path)
  local fpath     = dst_path or "(nil)"

  local prompt = table.concat({
    "The active take already has a non-zero TimeReference.",
    "",
    "Track: "..track_lbl,
    "File:  "..fname,
    "Path:  "..fpath,
    "Item start (project time): "..proj_pos,
    "",
    ("Existing TR: %d samples"):format(existing_tr or 0),
    ("New TR (Item Start): %d samples"):format(new_tr or 0),
    "",
    "Overwrite with the new value?",
    "",
    "Yes = Overwrite",
    "No  = Skip this item",
    "Cancel = Abort batch"
  }, "\n")

  local btn = reaper.MB(prompt, "BWF MetaEdit Tool", 3) -- 3 = Yes/No/Cancel
  if btn == 6 then return "yes"
  elseif btn == 7 then return "no"
  else return "cancel" end
end

-- Select only specific items
local function select_only(items)
  R.SelectAllMediaItems(0, false)
  for _,it in ipairs(items) do
    if it and R.ValidatePtr(it, "MediaItem*") then
      R.SetMediaItemSelected(it, true)
    end
  end
  R.UpdateArrange()
end

-- Offline → Online → Rebuild peaks
local function refresh_and_rebuild(modified_items)
  if not modified_items or #modified_items == 0 then return end
  select_only(modified_items)
  R.Main_OnCommand(40440, 0) -- Item: Set selected media temporarily offline
  R.Main_OnCommand(40439, 0) -- Item: Set selected media online
  R.Main_OnCommand(40441, 0) -- Peaks: Rebuild peaks for selected items
end

-- =========================
-- Core worker
-- =========================

-- mode=1 (take1->active) or mode=2 (item start -> active)
local function perform_embed(mode)
  local cli = resolve_cli()
  if not cli then
    local hint = IS_WIN and "請安裝 BWF MetaEdit，或指定 bwfmetaedit.exe 路徑。"
                       or  "macOS 可用 Homebrew：brew install bwfmetaedit"
    R.MB("找不到 BWF MetaEdit（bwfmetaedit）。\n"..hint, "BWF TimeReference", 0)
    return
  end

  local n_sel = R.CountSelectedMediaItems(0)
  if n_sel == 0 then
    R.MB("請先選取至少一個 item。", "BWF TimeReference", 0)
    return
  end

  local items = {}
  for i=0, n_sel-1 do items[#items+1] = R.GetSelectedMediaItem(0, i) end

  R.ClearConsole()
  msg(("=== BWF MetaEdit ===\nCLI : %s\nSel : %d\n"):format(cli, #items))

  local ok_cnt, fail_cnt, skip_cnt = 0, 0, 0
  local modified, aborted = {}, false

  -- When true, overwrite all remaining items without further prompts (Option 2 only).
  local yes_to_all = false

    -- Ask the "apply to all?" question at most once per run.
  local asked_apply_all = false

  R.Undo_BeginBlock()

  -- Prompt wrapper that supports a "Yes to All" flow for Option 2.
  -- Returns "yes" | "no" | "cancel".
  -- Behavior:
  --   * If yes_to_all is true -> always "yes" without prompting.
  --   * If user presses "Yes" and we have NOT asked the "apply to all?" question yet,
  --     ask it once; if user chooses Yes there, set yes_to_all=true.
  --   * If user chooses "No" on the "apply to all?" question, we set asked_apply_all=true
  --     so we won't ask that secondary question again for the rest of the batch.
  local function ask_overwrite_TR_with_all(it, dst_path, existing_tr, new_tr, item_start_pos)
    if yes_to_all then
      return "yes"
    end

    -- Build contextual message (track, file, path, and project-time)
    local track_lbl = item_track_label(it)
    local proj_pos  = format_project_time(item_start_pos or 0)
    local fname     = base(dst_path)
    local fpath     = dst_path or "(nil)"

    local prompt = table.concat({
      "The active take already has a non-zero TimeReference.",
      "",
      "Track: "..track_lbl,
      "File:  "..fname,
      "Path:  "..fpath,
      "Item start (project time): "..proj_pos,
      "",
      ("Existing TR: %d samples"):format(existing_tr or 0),
      ("New TR (Item Start): %d samples"):format(new_tr or 0),
      "",
      "Overwrite with the new value?",
      "",
      "Yes = Overwrite",
      "No  = Skip this item",
      "Cancel = Abort batch"
    }, "\n")

    local btn = reaper.MB(prompt, "BWF MetaEdit Tool", 3) -- 3 = Yes/No/Cancel
    if btn == 6 then
      -- Only the first time we choose "Yes", we offer "apply to all?".
      if not asked_apply_all then
        local all_btn = reaper.MB("Apply this choice to all remaining items?", "BWF MetaEdit Tool", 4) -- 4 = Yes/No
        asked_apply_all = true
        if all_btn == 6 then
          yes_to_all = true
        end
      end
      return "yes"
    elseif btn == 7 then
      return "no"
    else
      return "cancel"
    end
  end



  for i, it in ipairs(items) do
    if not it or not R.ValidatePtr(it, "MediaItem*") then
      skip_cnt = skip_cnt + 1
      msg(("Item %d [SKIP] invalid pointer"):format(i))
    else
      local takeA = R.GetActiveTake(it)
      if not takeA then
        skip_cnt = skip_cnt + 1
        msg(("Item %d [SKIP] no active take"):format(i))
      else
        local dst_path = (function()
          local src = R.GetMediaItemTake_Source(takeA)
          return src and R.GetMediaSourceFileName(src, "") or nil
        end)()

        msg(("Item %d -------------------------"):format(i))
        msg(("  dst : %s"):format(base(dst_path or "(nil)")))
        if not (dst_path and is_wav(dst_path)) then
          skip_cnt = skip_cnt + 1
          msg("  [SKIP] target is not WAV")
        else
          local target_tr

          if mode == 1 then
            local take1 = R.GetMediaItemTake(it, 0)
            local src_path = (function()
              local s = take1 and R.GetMediaItemTake_Source(take1) or nil
              return s and R.GetMediaSourceFileName(s, "") or nil
            end)()
            msg(("  src : %s"):format(base(src_path or "(nil)")))
            if not (take1 and src_path and is_wav(src_path)) then
              skip_cnt = skip_cnt + 1
              msg("  [SKIP] take1 missing or not WAV")
            else
              local tr, rc = read_TR(cli, src_path)
              msg(("    READ take1 TR : %s  (code=%s)"):format(tostring(tr), tostring(rc)))
              if tr then
                -- Convert via project-time to handle different start offsets and/or sample rates:
                -- ProjPos(sec) = srcTR(samples)/srcSR + SrcStart_src(sec)
                -- dstTR(samples) = (ProjPos - SrcStart_dst) * dstSR
                local src_sr = (function()
                  local s = R.GetMediaItemTake_Source(take1)
                  local v = s and select(2, R.GetMediaSourceSampleRate(s)) or 0
                  if not v or v <= 0 then v = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000 end
                  return math.floor(v + 0.5)
                end)()
                local dst_sr = (function()
                  local s = R.GetMediaItemTake_Source(takeA)
                  local v = s and select(2, R.GetMediaSourceSampleRate(s)) or 0
                  if not v or v <= 0 then v = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000 end
                  return math.floor(v + 0.5)
                end)()

                -- read raw offsets
                local pos          = R.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
                local src_offs_raw = R.GetMediaItemTakeInfo_Value(take1, "D_STARTOFFS") or 0.0
                local dst_offs     = R.GetMediaItemTakeInfo_Value(takeA,  "D_STARTOFFS") or 0.0

                -- cross-check: TR/src_sr + src_offs should equal item start (pos)
                local src_offs_calc = pos - (tr / src_sr)
                local use_calc = math.abs(((tr / src_sr) + src_offs_raw) - pos) > 0.001
                local src_offs = use_calc and src_offs_calc or src_offs_raw
                if use_calc then
                  msg(("    NOTE: srcOffs mismatch raw=%.6fs vs calc=%.6fs (from item pos); using calc")
                    :format(src_offs_raw, src_offs_calc))
                end

                -- project-time pivot via source TC + source start-in-source (stable even if item moved)
                -- ProjPos(sec) = srcTR(samples)/srcSR + SrcStart_src(sec)
                -- dstTR(samples) = (ProjPos - SrcStart_dst) * dstSR
                local proj_pos = (tr / src_sr) + src_offs
                target_tr = math.floor((proj_pos - dst_offs) * dst_sr + 0.5)
                if target_tr < 0 then target_tr = 0 end
                msg(("    ALIGN via time: srcTR=%d @%dHz, srcOffs=%.6fs -> ProjPos=%.6fs | dstOffs=%.6fs @%dHz -> dstTR=%d")
                  :format(tr, src_sr, src_offs, proj_pos, dst_offs, dst_sr, target_tr))
              else
                fail_cnt = fail_cnt + 1
                msg("    [FAIL] failed to read take1 TR")
              end
            end
          else
            local dst_sr  = (function()
              local s = R.GetMediaItemTake_Source(takeA)
              local v  = s and select(2, R.GetMediaSourceSampleRate(s)) or 0
              if not v or v <= 0 then v = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000 end
              return math.floor(v + 0.5)
            end)()
            local dst_offs = R.GetMediaItemTakeInfo_Value(takeA, "D_STARTOFFS") or 0.0
            local pos      = R.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
            target_tr = math.floor((pos - dst_offs) * dst_sr + 0.5)
            if target_tr < 0 then target_tr = 0 end
            msg(("    itemStart=%.6fs, dstOffs=%.6fs, dstSR=%d -> TR=%d"):format(pos, dst_offs, dst_sr, target_tr))
          end

          if target_tr then
            local existing_tr = select(1, read_TR(cli, dst_path))
            msg(("    EXIST dst TR : %s"):format(tostring(existing_tr)))

            local do_write = true
            if mode == 2 and (tonumber(existing_tr or 0) ~= 0) then
              -- Provide track label and project-time position in the prompt
              local item_start_pos = R.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
              -- Use the wrapper that supports "Yes to All"
              local ans = ask_overwrite_TR_with_all(it, dst_path, existing_tr, target_tr, item_start_pos)
              if ans == "cancel" then
                aborted = true
                msg("    [ABORT] user canceled the batch")
                break
              elseif ans == "no" then
                do_write = false
                skip_cnt = skip_cnt + 1
                msg("    [SKIP] user chose not to overwrite")
              end
            end

            if do_write then
              local wc = select(1, write_TR(cli, dst_path, target_tr))
              msg(("    WRITE dst TR  : %d  (code=%s)"):format(target_tr, tostring(wc)))

              local vr = select(1, read_TR(cli, dst_path))
              msg(("    VERIFY dst TR : %s"):format(tostring(vr)))

              if wc == 0 and vr == target_tr then
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
    end
  end

  R.Undo_EndBlock("BWF TimeReference embed", -1)

  local summary = ("Summary: OK=%d  FAIL=%d  SKIP=%d"):format(ok_cnt, fail_cnt, skip_cnt)
  if aborted then summary = summary .. "  (ABORTED)" end
  msg(summary); msg("=== End ===")

  if aborted then
    R.MB("Operation was aborted by user.\n\n" .. summary, "BWF TimeReference", 0)
  end

  if #modified > 0 then
    local btn = R.MB(
      summary .. ("\n\nRefresh now?\n(%d item(s) will be refreshed)"):format(#modified),
      "BWF TimeReference", 4 -- Yes/No
    )
    if btn == 6 then
      refresh_and_rebuild(modified)
    end
  else
    R.MB(summary .. "\n\nNo item embedded, no need to refresh", "BWF TimeReference", 0)
  end
end

-- =========================
-- UI (ReaImGui)
-- =========================

local has_imgui = type(reaper.ImGui_CreateContext) == "function"
if not has_imgui then
  local ok, inp = R.GetUserInputs("BWF MetaEdit Tool", 1, "Select: 1=Take1→Active, 2=ItemStart→Active", "")
  if not ok then return end
  local mode = tonumber((inp or ""):match("(%d+)") or "")
  if mode ~= 1 and mode ~= 2 then return end
  perform_embed(mode)
  return
end

local imgui = reaper
local ctx  = imgui.ImGui_CreateContext('BWF MetaEdit Tool', imgui.ImGui_ConfigFlags_NoSavedSettings())
local FONT = imgui.ImGui_CreateFont('sans-serif', 16); imgui.ImGui_Attach(ctx, FONT)

local BTN_W, BTN_H = 350, 28
local chosen_mode, should_close = nil, false

local function loop()
  imgui.ImGui_SetNextWindowSize(ctx, 360, 180, imgui.ImGui_Cond_Once())
  local visible, open = imgui.ImGui_Begin(ctx, 'BWF MetaEdit Tool', true)
  if visible then
    imgui.ImGui_Text(ctx, 'Write BWF TimeReference to ACTIVE take:')
    imgui.ImGui_Dummy(ctx, 1, 6)

    if imgui.ImGui_Button(ctx, 'Embed Take 1 TC', BTN_W, BTN_H) then chosen_mode = 1 end
    imgui.ImGui_Dummy(ctx, 1, 6)
    if imgui.ImGui_Button(ctx, 'Embed TC to Current Position', BTN_W, BTN_H) then chosen_mode = 2 end
    imgui.ImGui_Dummy(ctx, 1, 6)
    if imgui.ImGui_Button(ctx, 'Cancel', BTN_W, BTN_H) then should_close = true end

    -- ESC to close (only when window focused and no active widget)
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
  if chosen_mode then perform_embed(chosen_mode); return end
  R.defer(loop)
end

loop()
