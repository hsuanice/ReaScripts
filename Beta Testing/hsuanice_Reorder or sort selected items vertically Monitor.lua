--[[
@description Reorder/Sort — Monitor & Debug
@version 0.1.5
@author hsuanice
@about
  Shows a live table of the currently selected items and all sort-relevant fields:
    • Track Index / Track Name
    • Take Name
    • File Name
    • Metadata Track Name (resolved by Interleave, Wave Agent–style)
    • Channel Number (recorder channel, TRK#)
    • Interleave (1..N from REAPER take channel mode: Mono-of-N)
    • Item start time

  Also supports:
    • Capture BEFORE / AFTER snapshots
    • Export or Copy (TSV/CSV) for either the live view or snapshots

  Requires: ReaImGui (install via ReaPack)

@Changelog
  v0.1.5
  - UI: moved Snapshot BEFORE/AFTER section to appear directly under the top toolbar,
        before the live table (content unchanged).

  v0.1.4
  - Column rename: “Source File” (formerly “File Name”).
  - Source resolution now mirrors the Rename script’s $srcfile:
      active take → source → unwrap SECTION (handles nested) → real file path (with extension).
  - Metadata read (iXML/TRK) also uses the unwrapped source for better accuracy on poly/SECTION items.
  - Export headers updated to “Source File”; keeps EndTime from 0.1.3.
  - Cleanup/robustness: removed old src_path usage; safer guards for nil/non-PCM sources.

    - File name reliability: now resolves source file names (with extensions) even for SECTION/non-PCM sources via safe pcall wrapper.
    - New column: End (Start + Length). Also added EndTime to TSV/CSV exports.
    - Table: column count updated to 10; minor utils added (item_len), formatting helpers unchanged.

  v0.1.2
    - UI always renders content (removed 'visible' guard after Begin to avoid blank window in some docks/themes).
    - Table sizing: use -FLT_MIN width for stable full-width layout across ReaImGui builds.
    - Compatibility: safe ESC detection, tolerant handling when Begin returns only one value, save dialog fallback if JS_ReaScriptAPI is missing (auto-save to project folder with notice).

  v0.1.1
    - Compatibility hardening:
      • Avoided font Attach/PushFont when APIs are unavailable.
      • Added guards around keyboard APIs and window-‘open’ handling.
      • General nil-safety for selection scanning and sources.

  v0.1.0
    - Initial release:
      • Live monitor of selected items with columns: #, TrackIdx, Track Name, Take Name, File Name, Meta Track Name (interleave-resolved), Chan#, Interleave, Start.
      • Auto-refresh / manual Refresh Now.
      • Capture BEFORE / AFTER snapshots.
      • Export/Copy selection or snapshots as TSV/CSV.


]]

---------------------------------------
-- Dependency check
---------------------------------------
if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui is required (install via ReaPack).", "Missing dependency", 0)
  return
end

---------------------------------------
-- ImGui setup
---------------------------------------
local ctx = reaper.ImGui_CreateContext('Reorder/Sort — Monitor & Debug')
-- 使用預設字型，避免某些版本沒有 Attach/PushFont
-- local FONT = reaper.ImGui_CreateFont('sans-serif', 14)
-- if reaper.ImGui_Attach then reaper.ImGui_Attach(ctx, FONT) end

local FLT_MIN = 1.175494e-38 -- 用於 -FLT_MIN 佔滿寬度
local function TF(name) local f = reaper[name]; return f and f() or 0 end
local function esc_pressed()
  if reaper.ImGui_Key_Escape and reaper.ImGui_IsKeyPressed then
    return reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false)
  end
  return false
end

---------------------------------------
-- Small utils
---------------------------------------
local function item_start(it) return reaper.GetMediaItemInfo_Value(it,"D_POSITION") end
local function item_track(it) return reaper.GetMediaItemTrack(it) end
local function track_index(tr) return math.floor(reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or 0) end
local function track_name(tr) local _, n = reaper.GetTrackName(tr, "") return n end
local function take_of(it) local tk=it and reaper.GetActiveTake(it); if tk and reaper.ValidatePtr2(0,tk,"MediaItem_Take*") then return tk end end
local function src_of_take(tk) return tk and reaper.GetMediaItemTake_Source(tk) or nil end

-- Unwrap SECTION → return the real parent source (or original if not SECTION)
local function resolved_source_of_take(take)
  if not take then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end

  local function stype(s)
    local ok, t = pcall(reaper.GetMediaSourceType, s, "")
    return ok and t or ""
  end

  local t = stype(src)
  while t == "SECTION" do
    local ok, parent = pcall(reaper.GetMediaSourceParent, src)
    if not ok or not parent then break end
    src = parent
    t = stype(src)
  end
  return src
end

-- Safe filename for any source (after unwrapped): returns full path; "" if none
local function source_file_path(src)
  if not src then return "" end
  local ok, path = pcall(reaper.GetMediaSourceFileName, src, "")
  if ok and type(path) == "string" then return path end
  return ""
end

local function item_len(it)   return reaper.GetMediaItemInfo_Value(it,"D_LENGTH") end








local function basename(p) p=tostring(p or ""); return p:match("([^/\\]+)$") or p end
local function fmt_time(s) if not s then return "" end return string.format("%.6f", s) end

---------------------------------------
-- Metadata helpers (BWF/iXML)
---------------------------------------
-- IXML TRACK_LIST → build both:
--   trk_table[ch] = name
--   interleave_list = { {name=..., chan=...}, ... }  -- order = interleave (1..N)
local function collect_ixml_tracklist(src)
  local trk_table, interleave_list = {}, {}
  if not src or not reaper.GetMediaFileMetadata then return trk_table, interleave_list end
  local ok, count = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK_COUNT")
  if ok == 1 then
    local n = tonumber(count) or 0
    for i=1,n do
      local suffix = (i>1) and (":"..i) or ""
      local _, ch  = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX"..suffix)
      local _, nm  = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:NAME"..suffix)
      local ci = tonumber(ch or "")
      if ci and ci >= 1 then
        if nm and nm ~= "" then trk_table[ci] = nm end
        interleave_list[#interleave_list+1] = { name = nm or "", chan = ci }
      end
    end
  end
  return trk_table, interleave_list
end

-- Guess Interleave index 1..N using REAPER take channel mode: Mono-of-N (3..66 → i = cm-2)
local function guess_interleave_index(it)
  local tk = take_of(it); if not tk then return nil end
  local cm = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0
  if cm >= 3 and cm <= 66 then return math.floor(cm - 2) end
  return nil
end

-- Resolve "$trk" by Interleave (Wave Agent style).
-- Prefer interleave_list if present; fallback: build from TRK# sorted by channel number.
local function resolve_trk_name_by_interleave(fields, interleave_idx)
  local list = fields.interleave_list
  if (not list or #list == 0) and fields.trk_table then
    list = {}
    local pairs_chan = {}
    for ch, name in pairs(fields.trk_table) do pairs_chan[#pairs_chan+1] = { chan=ch, name=name } end
    table.sort(pairs_chan, function(a,b) return a.chan < b.chan end)
    for _, e in ipairs(pairs_chan) do list[#list+1] = { name=e.name or "", chan=e.chan } end
  end
  if list and interleave_idx and list[interleave_idx] then
    local rec = list[interleave_idx]
    return rec.name or "", rec.chan
  end
  -- fallback: first non-empty
  if list then
    for i=1,#list do if list[i].name and list[i].name ~= "" then return list[i].name, list[i].chan end end
  end
  return "", nil
end

-- Collect all fields for a single item
local function collect_fields_for_item(it)
  local row = {
    track_idx = 0,
    track_name = "",
    take_name = "",
    file_name = "",
    meta_trk_name = "",
    channel_num = nil,
    interleave = nil,
    start_time = item_start(it) or 0,
    end_time   = 0,                    -- ← 新增
  }

  local tr = item_track(it)
  row.track_idx  = tr and track_index(tr) or 0
  row.track_name = tr and track_name(tr) or "<no track>"

  local tk = take_of(it)
  if tk then
    local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
    row.take_name = nm or ""
  else
    row.take_name = "<no take>"
  end

  -- Use the same pipeline as Rename's $srcfile:
  --   active take -> source -> unwrap SECTION -> filename (with extension)
  local src_unwrapped = resolved_source_of_take(tk)
  local fpath = source_file_path(src_unwrapped)
  row.file_name = basename(fpath)  -- == $srcfile

  -- iXML/BWF should read from the real parent source too
  local trk_table, interleave_list = collect_ixml_tracklist(src_unwrapped)
  local fields = { trk_table = trk_table, interleave_list = interleave_list }

  row.interleave = guess_interleave_index(it)
  local nm, ch = resolve_trk_name_by_interleave(fields, row.interleave or 1)
  row.meta_trk_name = nm or ""
  row.channel_num   = ch
  row.end_time = (row.start_time or 0) + (item_len(it) or 0)

  return row
end

---------------------------------------
-- Selection scan
---------------------------------------
local function get_selected_items_sorted()
  local t, n = {}, reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do t[#t+1] = reaper.GetSelectedMediaItem(0,i) end
  table.sort(t, function(a,b)
    local sa, sb = item_start(a) or 0, item_start(b) or 0
    if math.abs(sa - sb) > 1e-9 then return sa < sb end
    local ta = item_track(a); local tb = item_track(b)
    local ia = ta and track_index(ta) or 0
    local ib = tb and track_index(tb) or 0
    if ia ~= ib then return ia < ib end
    return tostring(a) < tostring(b)
  end)
  return t
end

local function scan_selection_rows()
  local its = get_selected_items_sorted()
  local rows = {}
  for _, it in ipairs(its) do
    rows[#rows+1] = collect_fields_for_item(it)
  end
  return rows
end

---------------------------------------
-- Export helpers
---------------------------------------
local function build_table_text(fmt, rows)
  local sep = (fmt == "csv") and "," or "\t"
  local out = {}
  local function esc(s)
    s = tostring(s or "")
    if fmt == "csv" and s:find('[,\r\n"]') then s = '"'..s:gsub('"','""')..'"' end
    return s
  end
  out[#out+1] = table.concat({
    "#", "TrackIdx", "TrackName", "TakeName", "Source File",
    "MetaTrackName", "Channel#", "Interleave", "StartTime", "EndTime"
  }, sep)

  for i, r in ipairs(rows or {}) do
    out[#out+1] = table.concat({
      esc(i),
      esc(r.track_idx),
      esc(r.track_name),
      esc(r.take_name),
      esc(r.file_name),
      esc(r.meta_trk_name),
      esc(r.channel_num or ""),
      esc(r.interleave or ""),
      esc(fmt_time(r.start_time)),
      esc(fmt_time(r.end_time)), 
    }, sep)
  end
  return table.concat(out, "\n")
end

local function choose_save_path(default_name, filter)
  if reaper.JS_Dialog_BrowseForSaveFile then
    local ok, fn = reaper.JS_Dialog_BrowseForSaveFile("Save", "", default_name, filter)
    if ok and fn and fn ~= "" then return fn end
  end
  -- 沒有 JS_ReaScriptAPI：直接放到專案資料夾
  local proj, projfn = reaper.EnumProjects(-1, "")
  local base = projfn ~= "" and projfn:match("^(.*)[/\\]") or reaper.GetResourcePath()
  local p = (base or reaper.GetResourcePath()) .. "/" .. default_name
  reaper.ShowMessageBox("JS_ReaScriptAPI not installed.\nSaved to:\n"..p, "Info", 0)
  return p
end

local function write_text_file(path, text)
  local f = io.open(path, "wb"); if not f then return false end
  f:write(text or ""); f:close(); return true
end

local function timestamp()
  local t=os.date("*t"); return string.format("%04d%02d%02d_%02d%02d%02d",t.year,t.month,t.day,t.hour,t.min,t.sec)
end

---------------------------------------
-- State (UI)
---------------------------------------
local AUTO = true
local ROWS = {}
local SNAP_BEFORE, SNAP_AFTER = {}, {}

local function refresh_now()
  ROWS = scan_selection_rows()
end

---------------------------------------
-- UI
---------------------------------------
local function draw_toolbar()
  reaper.ImGui_Text(ctx, string.format("Selected items: %d", #ROWS))
  reaper.ImGui_SameLine(ctx)
  local chg, v = reaper.ImGui_Checkbox(ctx, "Auto-refresh", AUTO); if chg then AUTO = v end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Refresh Now", 110, 24) then refresh_now() end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Capture BEFORE", 130, 24) then SNAP_BEFORE = scan_selection_rows() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Capture AFTER", 120, 24) then SNAP_AFTER = scan_selection_rows() end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Copy (TSV)", 110, 24) then
    reaper.ImGui_SetClipboardText(ctx, build_table_text("tsv", ROWS))
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Save .tsv", 100, 24) then
    local p = choose_save_path("ReorderSort_Monitor_"..timestamp()..".tsv","Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
    if p then write_text_file(p, build_table_text("tsv", ROWS)) end
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Save .csv", 100, 24) then
    local p = choose_save_path("ReorderSort_Monitor_"..timestamp()..".csv","CSV (*.csv)\0*.csv\0All (*.*)\0*.*\0")
    if p then write_text_file(p, build_table_text("csv", ROWS)) end
  end
end

local function draw_table(rows, height)
  local flags = TF('ImGui_TableFlags_Borders') | TF('ImGui_TableFlags_RowBg') | TF('ImGui_TableFlags_SizingStretchProp')
  if reaper.ImGui_BeginTable(ctx, "live_table", 10, flags, -FLT_MIN, height or 360) then
    reaper.ImGui_TableSetupColumn(ctx, "#", TF('ImGui_TableColumnFlags_WidthFixed'), 36)
    reaper.ImGui_TableSetupColumn(ctx, "TrackIdx", TF('ImGui_TableColumnFlags_WidthFixed'), 72)
    reaper.ImGui_TableSetupColumn(ctx, "Track Name")
    reaper.ImGui_TableSetupColumn(ctx, "Take Name")
    reaper.ImGui_TableSetupColumn(ctx, "Source File")
    reaper.ImGui_TableSetupColumn(ctx, "Meta Track Name")
    reaper.ImGui_TableSetupColumn(ctx, "Chan#", TF('ImGui_TableColumnFlags_WidthFixed'), 64)
    reaper.ImGui_TableSetupColumn(ctx, "Interleave", TF('ImGui_TableColumnFlags_WidthFixed'), 88)
    reaper.ImGui_TableSetupColumn(ctx, "Start", TF('ImGui_TableColumnFlags_WidthFixed'), 96)
    reaper.ImGui_TableSetupColumn(ctx, "End",   TF('ImGui_TableColumnFlags_WidthFixed'), 96)
    reaper.ImGui_TableHeadersRow(ctx)

    for i, r in ipairs(rows or {}) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(i))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(r.track_idx or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, tostring(r.track_name or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, tostring(r.take_name or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, tostring(r.file_name or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_TextWrapped(ctx, tostring(r.meta_trk_name or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(r.channel_num or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, tostring(r.interleave or ""))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, fmt_time(r.start_time))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, fmt_time(r.end_time))
    end

    reaper.ImGui_EndTable(ctx)
  end
end

local function draw_snapshots()
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, string.format("Snapshot BEFORE: %d rows  ", #SNAP_BEFORE)); reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Copy BEFORE (TSV)", 150, 22) then reaper.ImGui_SetClipboardText(ctx, build_table_text("tsv", SNAP_BEFORE)) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Save BEFORE .tsv", 150, 22) then
    local p = choose_save_path("ReorderSort_Before_"..timestamp()..".tsv","Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
    if p then write_text_file(p, build_table_text("tsv", SNAP_BEFORE)) end
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, string.format("Snapshot AFTER : %d rows  ", #SNAP_AFTER)); reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Copy AFTER (TSV)", 150, 22) then reaper.ImGui_SetClipboardText(ctx, build_table_text("tsv", SNAP_AFTER)) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Save AFTER .tsv", 150, 22) then
    local p = choose_save_path("ReorderSort_After_"..timestamp()..".tsv","Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
    if p then write_text_file(p, build_table_text("tsv", SNAP_AFTER)) end
  end
end

---------------------------------------
-- Main loop
---------------------------------------
local function loop()
  if AUTO then refresh_now() end

  reaper.ImGui_SetNextWindowSize(ctx, 1000, 640, reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoCollapse()
  local visible, open = reaper.ImGui_Begin(ctx, "Reorder or Sort — Monitor & Debug", true, flags)
  if open == nil then open = true end

  -- 無 guard：一律繪製內容，避免某些版本/停駐情境 visible=false 導致空白
  draw_toolbar()
  draw_snapshots()            -- ← 先顯示 BEFORE/AFTER 兩行
  reaper.ImGui_Spacing(ctx)
  draw_table(ROWS, 360)

  reaper.ImGui_End(ctx)
  if open and not esc_pressed() then reaper.defer(loop) end
end

refresh_now()
loop()
