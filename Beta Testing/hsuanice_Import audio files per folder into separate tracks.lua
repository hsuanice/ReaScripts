--[[
@description ReaImGUI - Import audio files per folder into separate tracks, poly and channel splited files.
@version 0.1
@author hsuanice
@about
  - Pre-confirm dialog: shows total folders/files, lets you choose channel naming pattern [.A<number>] or [_<number>], then buttons [Import] / [Cancel].
    - Sequence only (append at end of target track).
    - Every directory that contains audio becomes a folder parent track (including the selected root).
    - Non-channel-split files (.A/_ not matched) go onto the PARENT folder track (one track per folder, including root).
    - Channel-split files -> child tracks named "Ch XX" (XX is the parsed channel number).
    - Scan all depths but do NOT nest folder tracks beyond 2 levels: each directory with files is its own parent+children block.
    - Streaming import with a small ReaImGui "Stop" window (ESC also works on some systems). On completion/abort: auto-close progress, then show finish summary.
    - No ImGui Destroy/Detach calls (to avoid crashes on some builds).
  
  Features:
  - Built with ReaImGUI for a compact, responsive UI.
  - Designed for fast, keyboard-light workflows.
  - Optionally leverages js_ReaScriptAPI for advanced interactions.
  
  References:
  - REAPER ReaScript API (Lua)
  - js_ReaScriptAPI
  - ReaImGUI (ReaScript ImGui binding)
  
  Note:
  - This is a 0.1 beta release for internal testing.
  
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.1 - Beta release
--]]
--[[
@description Import audio: one folder -> one folder track, with child tracks (Sequence only, streaming, Stop button, pre-confirm & finish summary). Root treated as a folder. Supports channel-split patterns: ".A<number>" or "_<number>"
@version 0.6.5.0
@author hsuanice
@about
  - Pre-confirm dialog: shows total folders/files, lets you choose channel naming pattern [.A<number>] or [_<number>], then buttons [Import] / [Cancel].
  - Sequence only (append at end of target track).
  - Every directory that contains audio becomes a folder parent track (including the selected root).
  - Non-channel-split files (.A/_ not matched) go onto the PARENT folder track (one track per folder, including root).
  - Channel-split files -> child tracks named "Ch XX" (XX is the parsed channel number).
  - Scan all depths but do NOT nest folder tracks beyond 2 levels: each directory with files is its own parent+children block.
  - Streaming import with a small ReaImGui "Stop" window (ESC also works on some systems). On completion/abort: auto-close progress, then show finish summary.
  - No ImGui Destroy/Detach calls (to avoid crashes on some builds).
@changelog
  v0.6.5.0 - Feature: add user-selectable channel naming pattern at import start (".A<number>" or "_<number>"); keeps all previous behaviors intact.
]]

---------------------------------------
-- Tunables
---------------------------------------
local JOB_SIZE = 8          -- files per frame; raise for speed
---------------------------------------

-- ========= helpers =========
local function log(s) reaper.ShowConsoleMsg(tostring(s).."\n") end

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
  return s:match("([^\\/]+)$") or s
end

local function split_rel(rel)
  local t={}
  for token in rel:gmatch("[^/]+") do t[#t+1]=token end
  return t
end

local function stem(fn)
  local name = fn:match("([^/\\]+)$") or fn
  return (name:gsub("%.%w+$",""))
end

-- natural-ish sort
local function nat_less(a,b)
  a,b=a:lower(),b:lower()
  if a==b then return false end
  local function parts(s)
    local t={}
    for c in s:gmatch("%d+%f[%D]|%D+%f[%d]|%D+$") do
      if c:sub(-1)=="|" then c=c:sub(1,-2) end
      t[#t+1]=c
    end
    return t
  end
  local aa,bb=parts(a),parts(b)
  local n=math.max(#aa,#bb)
  for i=1,n do
    local x,y=aa[i],bb[i]
    if not x then return true end
    if not y then return false end
    local nx,ny=tonumber(x),tonumber(y)
    if nx and ny then
      if nx~=ny then return nx<ny end
    else
      if x~=y then return x<y end
    end
  end
  return a<b
end

-- ======= (we no longer use TC for placement; kept here only if needed later) =======
local function meta(file,key)
  local ok,v=pcall(reaper.GetMediaFileMetadata,file,key)
  if ok and v and v~="" then return v end
end

-- ========= scan (all depths). Each file node: abs, rel (full relative dir) =========
local function scan_all(base)
  local list = {}
  local function walk(dir, rel)
    -- files
    local i=0; local names={}
    while true do
      local fn=reaper.EnumerateFiles(dir,i); if not fn then break end
      if is_audio(fn) then names[#names+1]=fn end
      i=i+1
    end
    table.sort(names, nat_less)
    for _,fn in ipairs(names) do
      list[#list+1] = { abs = join(dir,fn), rel = rel or "" }
    end
    -- subdirs
    i=0; local subs={}
    while true do
      local sd=reaper.EnumerateSubdirectories(dir,i); if not sd then break end
      subs[#subs+1]=sd; i=i+1
    end
    table.sort(subs, nat_less)
    for _,sd in ipairs(subs) do
      local new_rel = (rel and rel~="" and (rel.."/"..sd) or sd)
      walk(join(dir,sd), new_rel)
    end
  end
  walk(base,"")
  -- stable order: by rel, then by abs
  table.sort(list, function(a,b)
    if a.rel==b.rel then return nat_less(a.abs,b.abs) else return nat_less(a.rel,b.rel) end
  end)
  return list
end

-- ========= choose base =========
local function choose_base()
  if reaper.APIExists("JS_Dialog_BrowseForFolder") then
    local ok,folder=reaper.JS_Dialog_BrowseForFolder("Select base folder","")
    if not ok or not folder or folder=="" then return nil end
    if reaper.GetOS():find("Win") then folder=folder:gsub("/", "\\") else folder=folder:gsub("\\","/") end
    return folder
  end
  local rv,ret=reaper.GetUserInputs("Base Folder",1,"Path:", ""); if not rv or ret=="" then return nil end; return ret
end

-- ========= track utils =========
local function set_depth(tr,val) reaper.SetMediaTrackInfo_Value(tr,"I_FOLDERDEPTH",val) end
local function track_index(tr) return math.max(0,(reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or 1)-1) end

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

local function track_end_time(tr)
  local c = reaper.CountTrackMediaItems(tr)
  local t = 0.0
  for i=0,c-1 do
    local it=reaper.GetTrackMediaItem(tr,i)
    local p=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
    local l=reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
    if p+l>t then t=p+l end
  end
  return t
end

local function insert_sequence(tr, file_abs)
  select_only_track(tr)
  local pos = track_end_time(tr)
  local prev = reaper.GetCursorPosition()
  reaper.SetEditCurPos(pos, false, false)
  local before = reaper.CountTrackMediaItems(tr)
  reaper.InsertMedia(file_abs, 0) -- on selected track
  local after  = reaper.CountTrackMediaItems(tr)
  reaper.SetEditCurPos(prev, false, false)
  return after>before
end

-- ========= folder helpers (2 levels: Parent -> Children) =========
local parents = {}        -- key = rel(full) or "" -> {tr, children, lastChild}
local current_parent_key  = nil

local function finish_parent(key)
  local P = key and parents[key] or nil
  if not P then return end
  if P.lastChild then
    set_depth(P.lastChild, -1)
  else
    set_depth(P.tr, 0)
  end
end

local function begin_parent(key, display_name)
  if current_parent_key and parents[current_parent_key] then
    finish_parent(current_parent_key)
  end
  local tr = append_track(display_name, 1)   -- open folder
  parents[key] = { tr=tr, children=0, lastChild=nil }
  current_parent_key = key
  return parents[key]
end

local function ensure_parent(key, display_name)
  local P = parents[key]
  if not P then P = begin_parent(key, display_name) else current_parent_key = key end
  return P
end

-- cache of child tracks per parent
local children_by_parent = {}    -- key -> map name->track
local function ensure_child_under(key, child_name)
  children_by_parent[key] = children_by_parent[key] or {}
  local map = children_by_parent[key]
  if map[child_name] and reaper.ValidatePtr2(0, map[child_name], "MediaTrack*") then
    return map[child_name]
  end
  local P = parents[key]; if not P then return nil end
  local pidx = track_index(P.tr)
  local insert_idx = pidx + P.children + 1
  local tr = create_track_at(insert_idx, child_name, 0)
  P.children = P.children + 1
  P.lastChild = tr
  map[child_name] = tr
  return tr
end

local function finish_all_parents()
  if current_parent_key then finish_parent(current_parent_key) end
end

-- ========= Channel pattern choice =========
-- Default keeps backward compatibility: ".A<number>"
local channel_pattern_choice = ".A"  -- allowed values: ".A" or "_"

local function chan_from_filename(fn)
  -- Return channel number according to user's chosen pattern; nil if not matched
  if channel_pattern_choice == ".A" then
    local a = fn:match("%.[Aa](%d+)%.[^%.]+$")   -- ...A12.WAV
    if a then return tonumber(a) end
  elseif channel_pattern_choice == "_" then
    -- match trailing "_<num>.ext" (right before file extension)
    local u = fn:match("._(%d+)%.[^%.]+$")       -- ..._12.WAV
    if u then return tonumber(u) end
  end
  return nil
end

-- ========= UIs (no Destroy/Detach) =========
local UI_PRE = { ctx=nil, choice=nil }       -- "import" or "cancel"
local UI_PROGRESS = { ctx=nil, stop=false, total=0, done=0 }
local UI_POST = { ctx=nil, show=false, msg="" }

local function ui_pre_open(base_name, folders, files, on_decide)
  UI_PRE.choice = nil
  UI_PRE.ctx = reaper.ImGui_CreateContext('Confirm Import')
  local function loop()
    if not UI_PRE.ctx then return end
    reaper.ImGui_SetNextWindowSize(UI_PRE.ctx, 480, 210, reaper.ImGui_Cond_Once())
    local vis, open = reaper.ImGui_Begin(UI_PRE.ctx, 'Confirm Import', true)
    if vis then
      reaper.ImGui_Text(UI_PRE.ctx, ('Base: %s'):format(base_name))
      reaper.ImGui_Text(UI_PRE.ctx, ('Folders: %d    Files: %d'):format(folders, files))
      reaper.ImGui_Separator(UI_PRE.ctx)

      reaper.ImGui_Text(UI_PRE.ctx, 'Channel split pattern (choose one):')
      -- radio: ".A<number>"
      local a_selected = (channel_pattern_choice == ".A")
      local u_selected = (channel_pattern_choice == "_")
      if reaper.ImGui_RadioButton(UI_PRE.ctx, '.A<number>   e.g. "File.A3.wav"', a_selected) then
        channel_pattern_choice = ".A"
      end
      if reaper.ImGui_RadioButton(UI_PRE.ctx, ' _<number>   e.g. "File_3.wav"', u_selected) then
        channel_pattern_choice = "_"
      end

      reaper.ImGui_Separator(UI_PRE.ctx)
      local avail = reaper.ImGui_GetContentRegionAvail(UI_PRE.ctx)
      local half = (avail - 12) / 2
      if reaper.ImGui_Button(UI_PRE.ctx, 'Import', half, 34) then UI_PRE.choice='import' end
      reaper.ImGui_SameLine(UI_PRE.ctx, nil, 12)
      if reaper.ImGui_Button(UI_PRE.ctx, 'Cancel', half, 34) then UI_PRE.choice='cancel' end
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

local function ui_progress_open(total_files, total_groups)
  UI_PROGRESS.total = total_files; UI_PROGRESS.done = 0; UI_PROGRESS.stop = false
  UI_PROGRESS.ctx = reaper.ImGui_CreateContext('Importing...')
  local function loop()
    if not UI_PROGRESS.ctx then return end
    reaper.ImGui_SetNextWindowSize(UI_PROGRESS.ctx, 360, 110, reaper.ImGui_Cond_Once())
    local visible, open = reaper.ImGui_Begin(UI_PROGRESS.ctx, 'Importing...', true)
    if visible then
      reaper.ImGui_Text(UI_PROGRESS.ctx, ('Folders (groups): %d'):format(total_groups or 0))
      reaper.ImGui_Text(UI_PROGRESS.ctx, ('Files: %d / %d'):format(UI_PROGRESS.done, UI_PROGRESS.total))
      reaper.ImGui_Separator(UI_PROGRESS.ctx)
      if reaper.ImGui_Button(UI_PROGRESS.ctx, 'Stop', 320, 28) then UI_PROGRESS.stop = true end
      reaper.ImGui_Text(UI_PROGRESS.ctx, '(ESC also works)')
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

local function esc_pressed()
  if not reaper.APIExists("JS_VKeys_GetState") then return false end
  local state = reaper.JS_VKeys_GetState(0)
  return state and #state>=256 and (state:byte(27)~=0) or false
end

-- ========= runner =========
local function run_after_confirm(base, list)
  local t0 = reaper.time_precise()

  -- group files by folder-key and prepare display names
  local groups = {}               -- key -> { name=display, files={...}, ch_precreated=false }
  for _,n in ipairs(list) do
    local key = n.rel or ""
    local disp
    if key=="" then
      disp = basename(base)
    else
      local toks = split_rel(key); disp = toks[#toks] or key
    end
    if not groups[key] then groups[key] = { name=disp, files={}, ch_precreated=false } end
    table.insert(groups[key].files, n.abs)
  end

  local order = {}
  for k,_ in pairs(groups) do order[#order+1]=k end
  table.sort(order, nat_less)

  ui_progress_open(#list, #order)

  local parent_idx = 1
  local file_idx_in_parent = 1
  local current_key = nil

  local function precreate_channel_children_for(key)
    local G = groups[key]; if not G or G.ch_precreated then return end
    local set = {}
    for _,f in ipairs(G.files) do
      local fn = f:match("([^/\\]+)$") or f
      local ch = chan_from_filename(fn)
      if ch and ch > 0 then set[ch] = true end
    end
    if next(set) then
      local listn = {}
      for n,_ in pairs(set) do listn[#listn+1]=n end
      table.sort(listn, function(a,b) return a<b end)
      for _,n in ipairs(listn) do
        local child_name = string.format("Ch %02d", n)
        ensure_child_under(key, child_name)
      end
    end
    G.ch_precreated = true
  end

  local imported = 0
  local aborted  = false

  local function finish()
    finish_all_parents()
    ui_progress_close()
    local dt = reaper.time_precise() - t0
    local msg = string.format("Imported folders: %d\nImported files: %d\nStatus: %s\nElapsed: %.2fs",
                              #order, imported, (aborted and "Aborted" or "Completed"), dt)
    ui_post_open(msg)
  end

  local function step()
    if esc_pressed() or UI_PROGRESS.stop then
      aborted = true
      finish()
      return
    end

    if parent_idx > #order then
      finish()
      return
    end

    local key = order[parent_idx]
    local G   = groups[key]
    if current_key ~= key then
      local disp = G.name
      ensure_parent(key, disp)
      precreate_channel_children_for(key)
      current_key = key
      file_idx_in_parent = 1
    end

    local files = G.files
    if file_idx_in_parent > #files then
      parent_idx = parent_idx + 1
      reaper.defer(step)
      return
    end

    reaper.Undo_BeginBlock()

    local to_do = math.min(JOB_SIZE, #files - (file_idx_in_parent-1))
    for _=1,to_do do
      if esc_pressed() or UI_PROGRESS.stop then break end
      local f = files[file_idx_in_parent]; file_idx_in_parent = file_idx_in_parent + 1
      local fn = f:match("([^/\\]+)$") or f
      local ch = chan_from_filename(fn)

      local target_tr
      if ch and ch > 0 then
        -- channel-split -> child "Ch XX"
        local child_name = string.format("Ch %02d", ch)
        target_tr = ensure_child_under(key, child_name)
      else
        -- non-channel-split -> place on the PARENT folder track itself
        local P = parents[key]
        if not P then P = ensure_parent(key, G.name) end
        target_tr = P.tr
      end

      if target_tr and insert_sequence(target_tr, f) then
        imported = imported + 1
        UI_PROGRESS.done = UI_PROGRESS.done + 1
      end
    end

    reaper.Undo_EndBlock("Folder->children sequence import", -1)
    reaper.UpdateArrange()
    reaper.defer(step)
  end

  reaper.defer(step)
end

-- ========= entry =========
reaper.ShowConsoleMsg("")
local function main()
  local base = choose_base(); if not base then return end
  local list = scan_all(base); if #list==0 then reaper.MB("No audio files found.","Import",0); return end

  -- Pre-confirm counts
  local folders_set = {}
  for _,n in ipairs(list) do folders_set[n.rel or ""] = true end
  local folder_count = 0; for _ in pairs(folders_set) do folder_count=folder_count+1 end

  -- Show pre-confirm dialog (with channel pattern choice); on Import -> run; on Cancel -> do nothing
  ui_pre_open(basename(base), folder_count, #list, function(choice)
    if choice == 'import' then
      run_after_confirm(base, list)
    else
      -- cancelled
    end
  end)
end

main()
