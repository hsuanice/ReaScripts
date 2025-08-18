--[[
@description ReaImGui - Import audio: one folder per folder track; each file in folder as child track.
@version 0.1.3
@author hsuanice
@about
  - Pre-confirm dialog: shows total folders/files, then offers [Import] / [Cancel].
    - Each folder (including subfolders) that contains audio becomes a parent folder track.
    - Each file in a folder becomes a child track (track name = filename without extension).
    - Subfolders are treated as independent parent folder tracks (no nested folder tracks beyond two levels).
    - Streaming import with progress window (ESC and Cancel supported). Files and tracks are imported into REAPER one by one.
    - On completion/abort: auto-close progress, then show summary dialog.
    - No ImGui Destroy/Detach calls (avoids crashes on some builds).

  Features:
  - Built with ReaImGui for a compact, responsive UI.
  - Designed for fast, keyboard-light workflows.
  - Optionally leverages js_ReaScriptAPI for advanced interactions.

  References:
  - REAPER ReaScript API (Lua)
  - js_ReaScriptAPI
  - ReaImGui (ReaScript ImGui binding)

  This script was generated using ChatGPT and Copilot based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.1.3 - Streaming import: insert tracks one by one with progress.
        - English comments and metadata format update.
  v0.1.2 - File tracks are now named without extension; bug fixes for folder grouping.
--]]

local AUDIO_EXTS = { wav=true, aif=true, aiff=true, flac=true, ogg=true, mp3=true, caf=true, m4a=true, bwf=true, ogm=true, opus=true }
local function is_audio(fn)
  local e=fn:match("%.([%w]+)$")
  if not e then return false end
  e = e:lower()
  if e=="ds_store" or e=="pdf" or e=="txt" then return false end
  return AUDIO_EXTS[e] == true
end

local function join(a,b)
  local win = reaper.GetOS():find("Win")
  local sep = win and "\\" or "/"
  if a:sub(-1)=="/" or a:sub(-1)=="\\" then a=a:sub(1,#a-1) end
  if b:sub(1,1)=="/" or b:sub(1,1)=="\\" then b=b:sub(2) end
  return a..sep..b
end

local function basename(p)
  local s = p:gsub("[\\/]+$", "")
  local name = s:match("([^\\/]+)$") or s
  return name
end

local function stem(fn)
  -- Remove file extension
  local name = fn:match("([^/\\]+)$") or fn
  return (name:gsub("%.[%w]+$",""))
end

-- ========= Scan all folders (flat, two-level only) =========
-- Returns { {folder="name", files={...}}, ... }
local function scan_flat_groups(base)
  local result = {}
  local function walk(dir)
    local group = { folder = basename(dir), files = {} }
    -- Files in this folder
    local i=0
    while true do
      local fn=reaper.EnumerateFiles(dir,i); if not fn then break end
      if is_audio(fn) then group.files[#group.files+1]=join(dir,fn) end
      i=i+1
    end
    -- Add group only if there are files (including root)
    if #group.files > 0 then
      result[#result+1] = group
    end
    -- Subfolders (each becomes a new group, no nesting)
    i=0
    while true do
      local sd=reaper.EnumerateSubdirectories(dir,i); if not sd then break end
      walk(join(dir,sd))
      i=i+1
    end
  end
  walk(base)
  return result
end

-- ========= UI =========
local UI_PRE = { ctx=nil, choice=nil }
local UI_PROGRESS = { ctx=nil, stop=false, total=0, done=0 }
local UI_POST = { ctx=nil, show=false, msg="" }

local function esc_pressed()
  if not reaper.APIExists("JS_VKeys_GetState") then return false end
  local state = reaper.JS_VKeys_GetState(0)
  return state and #state>=256 and (state:byte(27)~=0) or false
end

local function esc_any(ctx)
  if reaper.ImGui_IsKeyPressed and reaper.ImGui_Key_Escape then
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      return true
    end
  end
  return esc_pressed()
end

local function ui_pre_open(base_name, folder_n, file_n, on_decide)
  UI_PRE.choice = nil
  UI_PRE.ctx = reaper.ImGui_CreateContext('Confirm Import')
  local function loop()
    if not UI_PRE.ctx then return end
    reaper.ImGui_SetNextWindowSize(UI_PRE.ctx, 480, 170, reaper.ImGui_Cond_Once())
    local vis, open = reaper.ImGui_Begin(UI_PRE.ctx, 'Confirm Import', true)
    if vis then
      reaper.ImGui_Text(UI_PRE.ctx, ('Base: %s'):format(base_name))
      reaper.ImGui_Text(UI_PRE.ctx, ('Folders: %d    Files: %d'):format(folder_n, file_n))
      reaper.ImGui_Separator(UI_PRE.ctx)
      local avail = reaper.ImGui_GetContentRegionAvail(UI_PRE.ctx)
      local half = (avail - 12) / 2
      if reaper.ImGui_Button(UI_PRE.ctx, 'Import', half, 34) then UI_PRE.choice='import' end
      reaper.ImGui_SameLine(UI_PRE.ctx, nil, 12)
      if reaper.ImGui_Button(UI_PRE.ctx, 'Cancel', half, 34) then UI_PRE.choice='cancel' end
      if esc_any(UI_PRE.ctx) then UI_PRE.choice = 'cancel' end
    end
    reaper.ImGui_End(UI_PRE.ctx)
    if not open then UI_PRE.ctx=nil; on_decide('cancel'); return end
    if UI_PRE.choice then
      local c = UI_PRE.choice
      UI_PRE.ctx=nil
      on_decide(c)
      return
    end
    reaper.defer(loop)
  end
  reaper.defer(loop)
end

local function ui_progress_open(total_files, total_folders)
  UI_PROGRESS.total = total_files; UI_PROGRESS.done = 0; UI_PROGRESS.stop = false
  UI_PROGRESS.ctx = reaper.ImGui_CreateContext('Importing...')
  local function loop()
    if not UI_PROGRESS.ctx then return end
    reaper.ImGui_SetNextWindowSize(UI_PROGRESS.ctx, 360, 110, reaper.ImGui_Cond_Once())
    local visible, open = reaper.ImGui_Begin(UI_PROGRESS.ctx, 'Importing...', true)
    if visible then
      reaper.ImGui_Text(UI_PROGRESS.ctx, ('Folders: %d'):format(total_folders or 0))
      reaper.ImGui_Text(UI_PROGRESS.ctx, ('Files: %d / %d'):format(UI_PROGRESS.done, UI_PROGRESS.total))
      reaper.ImGui_Separator(UI_PROGRESS.ctx)
      if reaper.ImGui_Button(UI_PROGRESS.ctx, 'Cancel', 320, 28) then UI_PROGRESS.stop = true end
      reaper.ImGui_Text(UI_PROGRESS.ctx, '(ESC also works)')
      if esc_any(UI_PROGRESS.ctx) then UI_PROGRESS.stop = true end
    end
    reaper.ImGui_End(UI_PROGRESS.ctx)
    if UI_PROGRESS.stop or not open then
      UI_PROGRESS.ctx = nil
      return
    end
    reaper.defer(loop)
  end
  reaper.defer(loop)
end

local function ui_progress_close()
  UI_PROGRESS.ctx = nil
end

local function ui_post_open(message)
  UI_POST.msg = message or ""
  UI_POST.show = true
  UI_POST.ctx = reaper.ImGui_CreateContext('Import Summary')
  local function loop()
    if not UI_POST.ctx then return end
    reaper.ImGui_SetNextWindowSize(UI_POST.ctx, 420, 160, reaper.ImGui_Cond_Once())
    local vis, open = reaper.ImGui_Begin(UI_POST.ctx, 'Import Summary', true)
    local clicked_ok = false
    if vis then
      for line in UI_POST.msg:gmatch("[^\n]+") do
        reaper.ImGui_Text(UI_POST.ctx, line)
      end
      reaper.ImGui_Separator(UI_POST.ctx)
      if reaper.ImGui_Button(UI_POST.ctx, 'OK', 360, 30) then
        clicked_ok = true
      end
    end
    reaper.ImGui_End(UI_POST.ctx)
    if clicked_ok or not open then
      UI_POST.ctx = nil
      UI_POST.show = false
      return
    end
    reaper.defer(loop)
  end
  reaper.defer(loop)
end

local function set_depth(tr,val) reaper.SetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH",val) end
local function create_track_at(idx, name, depth)
  reaper.InsertTrackAtIndex(idx,true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr,"P_NAME",name or "",true)
  set_depth(tr, depth or 0)
  return tr
end
local function append_track(name, depth)
  return create_track_at(reaper.CountTracks(0), name, depth or 0)
end
local function select_only_track(tr)
  reaper.Main_OnCommand(40297,0)
  if reaper.SetOnlyTrackSelected then reaper.SetOnlyTrackSelected(tr)
  else reaper.SetTrackSelected(tr,true) end
end
local function insert_file_to_track(tr, file_abs)
  select_only_track(tr)
  reaper.SetEditCurPos(0, false, false)
  local before = reaper.CountTrackMediaItems(tr)
  reaper.InsertMedia(file_abs, 0)
  local after  = reaper.CountTrackMediaItems(tr)
  return after>before
end

-- ========= STREAMING IMPORT RUNNER =========
local function main()
  local base = nil
  if reaper.APIExists("JS_Dialog_BrowseForFolder") then
    local ok,folder=reaper.JS_Dialog_BrowseForFolder("Select base folder","")
    if not ok or not folder or folder=="" then return end
    if reaper.GetOS():find("Win") then folder=folder:gsub("/", "\\") else folder=folder:gsub("\\","/") end
    base = folder
  else
    local rv,ret=reaper.GetUserInputs("Base Folder",1,"Path:", ""); if not rv or ret=="" then return nil end; base = ret
  end

  local groups = scan_flat_groups(base)
  local folder_count = #groups
  local file_count = 0
  for _,g in ipairs(groups) do file_count = file_count + #g.files end

  ui_pre_open(basename(base), folder_count, file_count, function(choice)
    if choice ~= 'import' then return end
    ui_progress_open(file_count, folder_count)
    local t0 = reaper.time_precise()
    local imported = 0
    local group_idx, file_idx = 1, 1
    local folder_tr = nil
    local function step()
      if UI_PROGRESS.stop or esc_pressed() then
        ui_progress_close()
        local dt = reaper.time_precise() - t0
        local msg = string.format("Imported folders: %d\nImported files: %d\nStatus: Aborted\nElapsed: %.2fs",
                                  folder_count, imported, dt)
        ui_post_open(msg)
        return
      end
      if group_idx > #groups then
        ui_progress_close()
        local dt = reaper.time_precise() - t0
        local msg = string.format("Imported folders: %d\nImported files: %d\nStatus: Completed\nElapsed: %.2fs",
                                  folder_count, imported, dt)
        ui_post_open(msg)
        return
      end
      local group = groups[group_idx]
      if file_idx == 1 then
        folder_tr = append_track(group.folder, 1) -- Create parent folder track
      end
      if file_idx <= #group.files then
        local file = group.files[file_idx]
        local tr = append_track(stem(file), 0) -- Create child track for file
        insert_file_to_track(tr, file)
        imported = imported + 1
        UI_PROGRESS.done = imported
        file_idx = file_idx + 1
        reaper.defer(step)
        return
      else
        set_depth(reaper.GetTrack(0, reaper.CountTracks(0)-1), -1) -- Set last child track of this folder
        group_idx = group_idx + 1
        file_idx = 1
        reaper.defer(step)
        return
      end
    end
    reaper.defer(step)
  end)
end

main()
