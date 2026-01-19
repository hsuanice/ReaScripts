--[[
@description ReaImGui - Import audio: one folder per track; channel-split files go to child tracks. Sequence only.
@version 260119.2125 add comprehensive debug mode
@author hsuanice
@about
  - Pre-confirm dialog: shows total folders/files, lets you choose a channel naming pattern or a custom mask, then offers [Import] / [Cancel].
    - Sequence only (append at the end of the target track).
    - Every directory that contains audio becomes a folder parent track (including the selected root).
    - Non–channel-split files (no ".A<number>" or "_<number>" match) go onto the PARENT folder track (one track per folder, including root).
    - Channel-split files → child tracks named "Ch XX" (XX is the parsed channel number).
    - Recursively scans all subfolders but does NOT nest folder tracks beyond two levels: each directory with files is its own parent+children block.
    - Streaming import with a small ReaImGui "Stop" window (ESC also works on some systems). On completion/abort: auto-close progress, then show a finish summary.
    - No ImGui Destroy/Detach calls (avoids crashes on some builds).

  Features:
  - Built with ReaImGui for a compact, responsive UI.
  - Designed for fast, keyboard-light workflows.
  - Optionally leverages js_ReaScriptAPI for advanced interactions.
  - DEBUG_MODE: Set to true to enable detailed console logging for troubleshooting.

  References:
  - REAPER ReaScript API (Lua)
  - js_ReaScriptAPI
  - ReaImGui (ReaScript ImGui binding)

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v260119.2125
  - Add: Comprehensive DEBUG_MODE with detailed logging:
    * Channel parsing results for each file
    * Track assignment decisions
    * File insertion success/failure status
    * Folder grouping information
  - Add: File output for debug logs to avoid console truncation
    * Set OUTPUT_TO_FILE = true to write to file (default: enabled)
    * Output file: Scripts/hsuanice Scripts/Tools/Import_Debug_Output.txt
    * File is cleared at each script run
  - Set DEBUG_MODE = true at line 70 to enable debug output
  v0.4.1.1 fix channel naming rule window size
  v0.4.1
  - Add: Support for filenames ending with "-<number>" (e.g. File-3.wav). 
         Auto mode now tries .A%, _%, and -% (chan_from_dash + Auto path).
  - Fix: Custom Rule mask parsing for "%". Corrected gsub replacement rules so 
         "%" is properly converted to (%d+), with support for literal "%%". 
         Also trims leading/trailing spaces automatically.
  - UI: Channel naming dialog always shows Custom input and P1–P3 preset buttons. 
        In Auto mode, the help text now indicates it will attempt .A%, _%, and Presets. 
        Clicking a preset button auto-focuses the input field.
  - Add: Lowercase ".a<number>" is now recognized the same as ".A<number>" 
         (improved chan_from_A).
  - Add: Pre-scans each folder’s filenames to create the required "Ch XX" child tracks 
         in advance, ensuring stable child track order.
  - Misc: Minor stability and wording improvements for the import progress window 
          and final summary dialog.

  v0.4.0 - Add: "Auto" channel naming (tries .A, then _, then Presets P1–P3; future-proof via MAX_MASK_PRESETS).
  v0.3.1 - Fix: ESC closes dialogs; remembers the last setting.
  v0.3.0 - Add Custom Mask Presets: 3 slots with clickable tokens; Save/Clear controls; focus returns to the custom input; presets persist via ExtState.
  v0.2.1 - Fix error when using ".A" option; translate Chinese comments to English.
  v0.2   - Add custom channel pattern input as the third option.
  v0.1.1 - Update description.
  v0.1   - Beta release.
--]]



---------------------------------------
-- Tunables
---------------------------------------
local JOB_SIZE = 8          -- files per frame; raise for speed
local DEBUG_MODE = true     -- Enable detailed debug logging
local OUTPUT_TO_FILE = true -- Write debug output to file instead of console
local OUTPUT_FILE = reaper.GetResourcePath() .. "/Scripts/hsuanice Scripts/Tools/Import_Debug_Output.txt"
---------------------------------------

-- Channel parsing mode switches (for split-channel naming)
-- 1 = ".A<number>"  (e.g., W-001.A7.wav)
-- 2 = "_<number>"   (e.g., W-001_7.wav)
-- 3 = custom mask (user enters a mask with % as the channel digits)

-- Persist last choice
local MODE_SECTION = "hsuanice_ImportAudio_Folder"
local MODE_KEY     = "LastMode"
local MASK_KEY     = "LastMask"

local CHAN_MODE = tonumber(reaper.GetExtState(MODE_SECTION, MODE_KEY)) or 1
local CHAN_CUSTOM_MASK = reaper.GetExtState(MODE_SECTION, MASK_KEY) or ""

-- === Custom Mask Presets (ExtState) =========================================
local MASK_PRESET_SECTION = "hsuanice_ImportAudio_Folder"
local MASK_PRESET_KEY     = "CustomMaskPresets_v1"  -- newline-separated list
local MAX_MASK_PRESETS    = 3

local function load_mask_presets()
  local s = reaper.GetExtState(MASK_PRESET_SECTION, MASK_PRESET_KEY)
  local t = {}
  if s and s ~= "" then
    for line in s:gmatch("([^\n]+)") do
      t[#t+1] = line
    end
  end
  for i = #t + 1, MAX_MASK_PRESETS do t[i] = "" end
  return t
end

local function save_mask_presets(presets)
  local lines = {}
  for i = 1, MAX_MASK_PRESETS do
    local v = presets[i] or ""
    v = v:gsub("[\r\n]", " ")  -- sanitize
    lines[#lines+1] = v
  end
  reaper.SetExtState(MASK_PRESET_SECTION, MASK_PRESET_KEY, table.concat(lines, "\n"), true)
end

-- cache in memory for the UI session
local mask_presets = load_mask_presets()
local focus_custom_mask = false  -- when true, focus goes back to the custom input on next frame
-- ============================================================================


-- ========= helpers =========
local function log(s) reaper.ShowConsoleMsg(tostring(s).."\n") end

-- Clear output file at script start
local function init_output_file()
  if OUTPUT_TO_FILE then
    local file = io.open(OUTPUT_FILE, "w")
    if file then
      file:write("")
      file:close()
      reaper.ShowConsoleMsg(string.format("[Import] Debug output redirected to:\n%s\n", OUTPUT_FILE))
    else
      reaper.ShowConsoleMsg("[Import] ERROR: Cannot create output file. Falling back to console.\n")
    end
  end
end

local function debug(s)
  if DEBUG_MODE then
    local msg = "[DEBUG] " .. tostring(s) .. "\n"
    if OUTPUT_TO_FILE then
      local file = io.open(OUTPUT_FILE, "a")
      if file then
        file:write(msg)
        file:close()
      else
        reaper.ShowConsoleMsg("[File write failed] " .. msg)
      end
    else
      reaper.ShowConsoleMsg(msg)
    end
  end
end

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


-- ===== Channel parsers =====
local function chan_from_U(fn)  -- "_<number>.wav"
  local n = fn:match("_(%d+)%.[^%.]+$") or fn:match("_(%d+)$")
  debug("chan_from_U: filename='"..fn.."' -> channel="..(n and tonumber(n) or "nil"))
  if n then return tonumber(n) end
end

-- ".A<number>" pattern (e.g., "Name.A7.wav" or "Name.A7")
local function chan_from_A(fn)
  -- Work on basename only
  local base = fn:match("([^/\\]+)$") or fn

  -- Match ".A<digits>" right before the extension, or at the very end (no extension)
  -- Also accept lowercase ".a<digits>" just in case
  local n = base:match("%.A(%d+)%.[^%.]+$")   -- "Name.A7.wav"
        or base:match("%.a(%d+)%.[^%.]+$")   -- "Name.a7.wav"
        or base:match("%.A(%d+)$")           -- "Name.A7"
        or base:match("%.a(%d+)$")           -- "Name.a7"

  debug("chan_from_A: basename='"..base.."' -> channel="..(n and tonumber(n) or "nil"))
  if n then return tonumber(n) end
end





-- Convert user mask to Lua pattern; "%" means digits.
local function mask_to_pattern(mask)
  if not mask then return nil end
  -- 先去頭尾空白，避免 " -%" / "-% " 之類踩雷
  mask = mask:match("^%s*(.-)%s*$")
  if mask == "" then return nil end

  -- 先把字面上的 "%%" 暫存，避免被誤當數字佔位
  local SENT = "\0PCT\0"
  mask = mask:gsub("%%%%", SENT)

  -- 跳脫 Lua pattern 特殊字元（保留 %）
  local esc = mask:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")

  -- 將單一 % 轉成數字擷取 (%d+)
  esc = esc:gsub("%%", "(%%d+)")

  -- 還原字面上的 %
  esc = esc:gsub(SENT, "%%")
  return esc
end

local function chan_from_custom(fn, mask)
  local pat = mask_to_pattern(mask)
  if not pat then return nil end
  -- Match once before the file extension, then match against the entire filename to increase robustness.
  local base = fn:match("([^/\\]+)$") or fn
  local stemOnly = base:gsub("%.%w+$","")
  local cap = stemOnly:match(pat) or base:match(pat)
  if cap and tonumber(cap) then return tonumber(cap) end
end


-- 新增一個 dash 解析器
local function chan_from_dash(fn)
  local base = fn:match("([^/\\]+)$") or fn
  local n = base:match("%-(%d+)%.[^%.]+$") or base:match("%-(%d+)$")
  debug("chan_from_dash: basename='"..base.."' -> channel="..(n and tonumber(n) or "nil"))
  if n then return tonumber(n) end
end

-- Unified entry point
local function chan_from_filename(fn)
  debug("========================================")
  debug("chan_from_filename: START - file='"..fn.."'")
  debug("  CHAN_MODE="..tostring(CHAN_MODE).." (0=Auto, 1=.A%, 2=_%, 3=Custom, 4=-%)")

  local result
  if CHAN_MODE == 0 then
    -- Auto: .A#, then _#, then -#, then presets
    debug("  Trying Auto mode...")
    local n = chan_from_A(fn) or chan_from_U(fn) or chan_from_dash(fn)
    if n then
      result = n
      debug("  -> Found channel "..n.." from built-in patterns")
    else
      for i = 1, MAX_MASK_PRESETS do
        local m = mask_presets[i]
        if m and m ~= "" then
          debug("  Trying preset #"..i..": '"..m.."'")
          local c = chan_from_custom(fn, m)
          if c then
            result = c
            debug("  -> Found channel "..c.." from preset #"..i)
            break
          end
        end
      end
    end
  elseif CHAN_MODE == 1 then
    debug("  Using .A% mode")
    result = chan_from_A(fn)
  elseif CHAN_MODE == 2 then
    debug("  Using _% mode")
    result = chan_from_U(fn)
  elseif CHAN_MODE == 3 then
    debug("  Using Custom mode: mask='"..tostring(CHAN_CUSTOM_MASK).."'")
    result = chan_from_custom(fn, CHAN_CUSTOM_MASK)
  else
    debug("  Unknown mode, defaulting to .A%")
    result = chan_from_A(fn)
  end

  debug("chan_from_filename: RESULT -> "..(result and ("Ch "..result) or "PARENT (no channel)"))
  debug("========================================")
  return result
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



-- ========= UIs =========
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

      

      reaper.ImGui_Separator(UI_PRE.ctx)
      local avail = reaper.ImGui_GetContentRegionAvail(UI_PRE.ctx)
      local half = (avail - 12) / 2
      if reaper.ImGui_Button(UI_PRE.ctx, 'Import', half, 34) then UI_PRE.choice='import' end
      reaper.ImGui_SameLine(UI_PRE.ctx, nil, 12)
      if reaper.ImGui_Button(UI_PRE.ctx, 'Cancel', half, 34) then UI_PRE.choice='cancel' end
      if (reaper.ImGui_IsKeyPressed and reaper.ImGui_Key_Escape
    and reaper.ImGui_IsKeyPressed(UI_PRE.ctx, reaper.ImGui_Key_Escape()))
   or esc_pressed() then
  UI_PRE.choice = 'cancel'
end

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

function esc_pressed()
  if not reaper.APIExists("JS_VKeys_GetState") then return false end
  local state = reaper.JS_VKeys_GetState(0)
  return state and #state>=256 and (state:byte(27)~=0) or false
end

-- Prefer ImGui key state if available; fall back to JS_VKeys
function esc_any(ctx)
  if reaper.ImGui_IsKeyPressed and reaper.ImGui_Key_Escape then
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      return true
    end
  end
  return esc_pressed()
end

-- ========= choose channel mode (A#, _#, or custom) =========
local function ui_choose_mode(on_done)
  local ctx = reaper.ImGui_CreateContext('Channel Naming')
  local mode = CHAN_MODE
  local custom = CHAN_CUSTOM_MASK or ""

  local decided = false
  local accepted = false

  local function loop()
    if not ctx then return end
    reaper.ImGui_SetNextWindowSize(ctx, 320, 330, reaper.ImGui_Cond_Once())
    local vis, open = reaper.ImGui_Begin(ctx, 'Channel naming rule', true)
    if vis then
      reaper.ImGui_Text(ctx, 'Select split-channel naming:')
      reaper.ImGui_Separator(ctx)

      if reaper.ImGui_RadioButton(ctx, 'Auto Mode', mode == 0) then mode = 0 end
      if reaper.ImGui_RadioButton(ctx, '".A%"  (e.g., File.A3.WAV)', mode == 1) then mode = 1 end
      if reaper.ImGui_RadioButton(ctx, '"_%"   (e.g., File_3.WAV)', mode == 2) then mode = 2 end
      if reaper.ImGui_RadioButton(ctx, '"-%"   (e.g., File-3.WAV)', mode == 4) then mode = 4 end
      if reaper.ImGui_RadioButton(ctx, 'Custom Rule', mode == 3) then mode = 3 end


      -- Custom UI
      -- Always-visible Custom editor + presets
      reaper.ImGui_Spacing(ctx)

      -- Help text (extra explicit when Auto is selected)
      if mode == 0 then
        reaper.ImGui_TextWrapped(ctx, 'Auto Mode tries ".A%", "_%", "-%" and Presets.')
      end
      reaper.ImGui_Text(ctx, 'use "%" for channel number')

      -- Layout: File[ INPUT ].extension
      local left_txt  = 'File'
      local right_txt = '.extension'
      local avail_w   = reaper.ImGui_GetContentRegionAvail(ctx) -- width
      local left_w    = select(1, reaper.ImGui_CalcTextSize(ctx, left_txt))
      local right_w   = select(1, reaper.ImGui_CalcTextSize(ctx, right_txt))
      local pad       = 16
      local input_w   = math.max(80, avail_w - left_w - right_w - pad)

      -- If a preset token was clicked, return keyboard focus to the input on the next frame
      if focus_custom_mask then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        focus_custom_mask = false
      end

      -- Render: File[ INPUT ].extension
      reaper.ImGui_Text(ctx, left_txt)
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_SetNextItemWidth(ctx, input_w)

      -- Allow spaces: last flag = 0 (do not use CharsNoBlank)
      local edited; edited, custom = reaper.ImGui_InputText(ctx, '##custom_mask', custom or "", 0)
      if edited then CHAN_CUSTOM_MASK = custom end
      reaper.ImGui_SameLine(ctx)
      reaper.ImGui_Text(ctx, right_txt)

      -- Preset and Save rows: Preset (top) / Save (bottom), vertically aligned
      reaper.ImGui_Spacing(ctx)
      if reaper.ImGui_BeginTable(ctx, 'mask_preset_table', MAX_MASK_PRESETS, reaper.ImGui_TableFlags_SizingStretchProp()) then
        -- Row 1: Preset tokens (click to insert into the input)
        reaper.ImGui_TableNextRow(ctx)
        for i = 1, MAX_MASK_PRESETS do
          reaper.ImGui_TableNextColumn(ctx)
          local v = mask_presets[i] or ""
          local label = (v ~= "" and ('['..v..']##masktok'..i)) or ('Preset '..i..'##masktok'..i)
          local disabled = (v == "")
          if disabled then reaper.ImGui_BeginDisabled(ctx, true) end
          if reaper.ImGui_Button(ctx, label) and not disabled then
            custom = v
            CHAN_CUSTOM_MASK = custom
            focus_custom_mask = true
          end
          if disabled then reaper.ImGui_EndDisabled(ctx) end
        end

        -- Row 2: Save P1 / P2 / P3 (aligned under each preset)
        reaper.ImGui_TableNextRow(ctx)
        for i = 1, MAX_MASK_PRESETS do
          reaper.ImGui_TableNextColumn(ctx)
          if reaper.ImGui_SmallButton(ctx, ('Save P%d##masksave%d'):format(i, i)) then
            mask_presets[i] = custom or ""
            save_mask_presets(mask_presets)
          end
        end

        reaper.ImGui_EndTable(ctx)
      end


      reaper.ImGui_Separator(ctx)
      local avail = reaper.ImGui_GetContentRegionAvail(ctx)
      local half = (avail - 12) / 2
      if reaper.ImGui_Button(ctx, 'OK', half, 30) then
        CHAN_MODE = mode
        CHAN_CUSTOM_MASK = (mode == 3) and (custom or "") or ""
        reaper.SetExtState(MODE_SECTION, MODE_KEY, tostring(CHAN_MODE), true)
        reaper.SetExtState(MODE_SECTION, MASK_KEY, CHAN_CUSTOM_MASK or "", true)
        decided, accepted = true, true
        

      end
      reaper.ImGui_SameLine(ctx, nil, 12)
      if reaper.ImGui_Button(ctx, 'Cancel', half, 30) then
         decided, accepted = true, false
      end
      if esc_any(ctx) then decided, accepted = true, false end
    end
    reaper.ImGui_End(ctx)

    if decided or not open then
      ctx = nil
      on_done(accepted and true or false)
      return
    end
    reaper.defer(loop)
  end
  reaper.defer(loop)
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

      debug(">>> Processing file: "..fn)
      debug("    Folder key: '"..key.."'")

      local target_tr
      if ch and ch > 0 then
        -- channel-split -> child "Ch XX"
        local child_name = string.format("Ch %02d", ch)
        debug("    -> Placing on CHILD track: '"..child_name.."'")
        target_tr = ensure_child_under(key, child_name)
      else
        -- non-channel-split -> place on the PARENT folder track itself
        debug("    -> Placing on PARENT track (no channel detected)")
        local P = parents[key]
        if not P then P = ensure_parent(key, G.name) end
        target_tr = P.tr
      end

      if target_tr then
        local tr_name = ({reaper.GetSetMediaTrackInfo_String(target_tr, "P_NAME", "", false)})[2] or "?"
        local tr_idx = track_index(target_tr)
        debug("    Target track #"..tr_idx..": '"..tr_name.."'")

        if insert_sequence(target_tr, f) then
          imported = imported + 1
          UI_PROGRESS.done = UI_PROGRESS.done + 1
          debug("    ✓ Successfully inserted")
        else
          debug("    ✗ Failed to insert")
        end
      else
        debug("    ✗ ERROR: target_tr is nil!")
      end
    end

    reaper.Undo_EndBlock("Folder->children sequence import", -1)
    reaper.UpdateArrange()
    reaper.defer(step)
  end

  reaper.defer(step)
end

-- ========= entry =========
local function main()
  init_output_file()  -- Initialize file output if enabled
  reaper.ShowConsoleMsg("")  -- Clear console at start
  debug("======== SCRIPT START ========")
  debug("DEBUG_MODE = "..tostring(DEBUG_MODE))
  debug("OUTPUT_TO_FILE = "..tostring(OUTPUT_TO_FILE))

  local base = choose_base(); if not base then return end
  debug("Selected base folder: "..base)

  local list = scan_all(base)
  debug("Scanned "..#list.." audio files")

  if #list==0 then
    reaper.MB("No audio files found.","Import",0)
    return
  end

  -- Ask for the channel naming convention first
  ui_choose_mode(function(ok)
    if not ok then
      debug("User cancelled channel mode selection")
      return
    end

    debug("Channel mode confirmed: CHAN_MODE="..tostring(CHAN_MODE))
    if CHAN_MODE == 3 then
      debug("  Custom mask: '"..tostring(CHAN_CUSTOM_MASK).."'")
    end

    -- Pre-confirm counts
    local folders_set = {}
    for _,n in ipairs(list) do folders_set[n.rel or ""] = true end
    local folder_count = 0; for _ in pairs(folders_set) do folder_count=folder_count+1 end

    debug("Found "..folder_count.." folders with audio files")

    -- Then show the original "Import / Cancel" dialog
    ui_pre_open(basename(base), folder_count, #list, function(choice)
      if choice == 'import' then
        debug("User confirmed import - starting...")
        run_after_confirm(base, list)
      else
        debug("User cancelled import")
      end
    end)
  end)
end

main()
