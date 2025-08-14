--[[
@description Embed BWF TimeReference to Active take from Take 1 or Current Position TC
@version 0.7.1
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
  v0.7.1
    - Add Esc to cancel, add Cancel button.
  v0.7.x
    - Batch-safe refresh and shell robustness.
  v0.6.x
    - Batch write & verify TimeReference; improved console diagnostics.
  v0.5.x
    - Initial ReaImGui UI with two TC embed options, prompt to refresh items.
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

-- Wrap a shell command so ExecProcess runs it via a shell (handles spaces/quotes)
local function sh_wrap(cmd)
  if IS_WIN then
    return 'cmd.exe /C "'..cmd..'"'
  else
    return "/bin/sh -lc '"..cmd:gsub("'",[['"'"']]).."'" -- safe-escape single quotes
  end
end

-- Execute a shell command and return exit code and stdout
local function exec_shell(cmd, ms)
  local ret = R.ExecProcess(sh_wrap(cmd), ms or 20000) or ""
  local code, out = ret:match("^(%d+)\n(.*)$")
  return tonumber(code or -1), (out or "")
end

-- Check bwfmetaedit executable works
local function test_cli(p)
  if not p or p=="" then return false end
  local code = select(1, exec_shell('"'..p..'" --Version', 4000))
  return code == 0
end

-- Resolve bwfmetaedit path, remember in extstate
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

-- Read TimeReference via bwfmetaedit --out-xml=-
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


-- Ask user before overwriting a non-zero TimeReference on the destination.
-- Returns "yes" | "no" | "cancel".
local function confirm_overwrite_TR(dst_path, existing, target)
  local msg = (
    "The active take already has a non-zero TimeReference.\n\n" ..
    "File: %s\n" ..
    "Existing TR: %d samples\n" ..
    "New TR (Item Start): %d samples\n\n" ..
    "Overwrite with the new value?\n\n" ..
    "Yes = Overwrite\nNo = Skip this item\nCancel = Abort batch"
  ):format(base(dst_path or "(unknown)"), tonumber(existing or 0), tonumber(target or 0))

  -- 3 = MB_YESNOCANCEL; return: 6=Yes, 7=No, 2=Cancel
  local btn = R.MB(msg, "BWF MetaEdit Tool", 3)
  if btn == 6 then return "yes"
  elseif btn == 7 then return "no"
  else return "cancel" end
end







-- Get media source path of a take
local function take_path(take)
  local src = take and R.GetMediaItemTake_Source(take) or nil
  return src and R.GetMediaSourceFileName(src, "") or nil
end

-- Get sample rate of a take (fallback to project SR)
local function take_sr(take)
  local src = take and R.GetMediaItemTake_Source(take) or nil
  local sr = src and select(2, R.GetMediaSourceSampleRate(src)) or 0
  if not sr or sr <= 0 then
    sr = R.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000
  end
  return math.floor(sr + 0.5)
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

-- Offline → Online → Rebuild peaks for given items
local function refresh_and_rebuild(modified_items)
  if not modified_items or #modified_items == 0 then return end
  select_only(modified_items)
  R.Main_OnCommand(40440, 0) -- Item: Set selected media temporarily offline
  R.Main_OnCommand(40439, 0) -- Item: Set selected media online
  R.Main_OnCommand(40441, 0) -- Peaks: Rebuild peaks for selected items
end

-- Core worker. mode=1 (take1->active) or mode=2 (item start -> active)
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

  -- Snapshot selection to avoid side-effects
  local items = {}
  for i=0, n_sel-1 do items[#items+1] = R.GetSelectedMediaItem(0, i) end

  R.ClearConsole()
  msg(("=== BWF MetaEdit ===\nCLI : %s\nSel : %d\n"):format(cli, #items))

  -- Counters and flags for the batch
  local ok_cnt, fail_cnt, skip_cnt = 0, 0, 0
  local modified = {}
  local aborted  = false  -- set to true if user presses Cancel on overwrite prompt

  local ok_cnt, fail_cnt, skip_cnt = 0, 0, 0
  local modified = {}

  R.Undo_BeginBlock()

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
        local dst_path = take_path(takeA)
        msg(("Item %d -------------------------"):format(i))
        msg(("  dst : %s"):format(base(dst_path or "(nil)")))
        if not (dst_path and is_wav(dst_path)) then
          skip_cnt = skip_cnt + 1
          msg("  [SKIP] target is not WAV")
        else
          local target_tr

          if mode == 1 then
            local take1 = R.GetMediaItemTake(it, 0)
            local src_path = take_path(take1)
            msg(("  src : %s"):format(base(src_path or "(nil)")))
            if not (take1 and src_path and is_wav(src_path)) then
              skip_cnt = skip_cnt + 1
              msg("  [SKIP] take1 missing or not WAV")
            else
              local tr, rc = read_TR(cli, src_path)
              msg(("    READ take1 TR : %s  (code=%s)"):format(tostring(tr), tostring(rc)))
              if tr then target_tr = tr else
                fail_cnt = fail_cnt + 1
                msg("    [FAIL] failed to read take1 TR")
              end
            end
          else
            local sr = take_sr(takeA)
            local pos = R.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
            target_tr = math.floor(pos * sr + 0.5)
            msg(("    itemStart=%.6fs, SR=%d -> TR=%d"):format(pos, sr, target_tr))
          end

          if target_tr then
            -- Read existing TR on destination for safety prompt (only for Option 2).
            local existing_tr = select(1, read_TR(cli, dst_path))
            msg(("    EXIST dst TR : %s"):format(tostring(existing_tr)))

            -- If mode=2 and destination already has a non-zero TR, ask user.
            local do_write = true
            if mode == 2 and (tonumber(existing_tr or 0) ~= 0) then
              local ans = confirm_overwrite_TR(dst_path, existing_tr, target_tr)
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


  -- Build and print summary
  local summary = ("Summary: OK=%d  FAIL=%d  SKIP=%d"):format(ok_cnt, fail_cnt, skip_cnt)

  -- Append aborted marker if user canceled during option 2 overwrite prompt
  if aborted then
    summary = summary .. "  (ABORTED)"
  end

  msg(summary)
  msg("=== End ===")

  -- (Optional) extra notice when aborted; delete this block if you don't want an extra popup
  if aborted then
    R.MB("Operation was aborted by user.\n\n" .. summary, "BWF TimeReference", 0)
  end

  -- Ask to refresh (offline→online→rebuild peaks) if there are modified items
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


-- Close the current ImGui window when ESC is pressed.
-- It ignores ESC while typing into a widget (so it won't close while editing a text field).
local function esc_to_close(ctx)
  -- Close only if our window (or its children) has focus,
  -- and no widget is currently active (typing/editing).
  local focused = reaper.ImGui_IsWindowFocused(ctx, reaper.ImGui_FocusedFlags_AnyWindow())
  local typing  = reaper.ImGui_IsAnyItemActive(ctx)
  local esc     = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)
  return focused and esc
end





-- =========================
-- UI (ReaImGui)
-- =========================

local has_imgui = type(reaper.ImGui_CreateContext) == "function"
if not has_imgui then
  -- Fallback UI when ReaImGui is not installed
  local ok, inp = R.GetUserInputs("BWF MetaEdit Tool", 1, "Select: 1=Take1→Active, 2=ItemStart→Active", "")
  if not ok then return end
  local mode = tonumber((inp or ""):match("(%d+)") or "")
  if mode ~= 1 and mode ~= 2 then return end
  perform_embed(mode)
  return
end

local imgui = reaper
-- Window title: BWF MetaEdit Tool
local ctx  = imgui.ImGui_CreateContext('BWF MetaEdit Tool', imgui.ImGui_ConfigFlags_NoSavedSettings())
local FONT = imgui.ImGui_CreateFont('sans-serif', 16)
imgui.ImGui_Attach(ctx, FONT)

-- Unify button sizes; the 3rd button is "Cancel"
local BTN_W, BTN_H = 350, 28

local chosen_mode  = nil     -- 1 or 2 (trigger write on click)
local should_close = false   -- set true by Cancel or ESC

local function loop()
  -- Create the window once with a reasonable size
  imgui.ImGui_SetNextWindowSize(ctx, 360, 180, imgui.ImGui_Cond_Once())

  -- Begin the window; "open" becomes false if user clicks the X button
  local visible, open = imgui.ImGui_Begin(ctx, 'BWF MetaEdit Tool', true)
  if visible then
    imgui.ImGui_Text(ctx, 'Write BWF TimeReference to ACTIVE take:')
    imgui.ImGui_Dummy(ctx, 1, 6)

    -- Button 1: Embed Take 1 TC
    if imgui.ImGui_Button(ctx, 'Embed Take 1 TC', BTN_W, BTN_H) then
      chosen_mode = 1
    end

    imgui.ImGui_Dummy(ctx, 1, 6)

    -- Button 2: Embed TC to Current Position
    if imgui.ImGui_Button(ctx, 'Embed TC to Current Position', BTN_W, BTN_H) then
      chosen_mode = 2
    end

    imgui.ImGui_Dummy(ctx, 1, 6)

    -- Button 3: Cancel (same size, third row)
    if imgui.ImGui_Button(ctx, 'Cancel', BTN_W, BTN_H) then
      should_close = true
    end

    -- ESC to close:
    -- Only close if the window (or its children) is focused
    -- and no item is currently active (avoid closing while editing).
    local esc = imgui.ImGui_IsKeyPressed(ctx, imgui.ImGui_Key_Escape(), false)
    if esc
       and imgui.ImGui_IsWindowFocused(ctx, imgui.ImGui_FocusedFlags_RootAndChildWindows())
       and not imgui.ImGui_IsAnyItemActive(ctx)
    then
      should_close = true
    end

    imgui.ImGui_End(ctx)
  end

  -- Exit conditions: user closed the window, pressed ESC, or clicked Cancel
  if not open or should_close then
    return
  end

  -- If a mode was chosen, run the worker once and exit the UI
  if chosen_mode then
    perform_embed(chosen_mode)
    return
  end

  R.defer(loop)
end

loop()

