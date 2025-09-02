--[[
@description Monitor - Reorder or sort selected items vertically
@version 0.3.5
@author hsuanice
@about
  Shows a live table of the currently selected items and all sort-relevant fields:
    • Track Index / Track Name
    • Take Name
    • Source File
    • Metadata Track Name (resolved by Interleave, Wave Agent–style)
    • Channel Number (recorder channel, TRK#)
    • Interleave (1..N from REAPER take channel mode: Mono-of-N)
    • Item start/end (toggle Seconds vs Timecode, follows project frame rate)

  Also supports:
    • Capture BEFORE / AFTER snapshots
    • Export or Copy (TSV/CSV) for either the live view or snapshots

  Requires: ReaImGui (install via ReaPack)

@changelog
  v0.3.5 (2025-09-02)
    - Feature: Display mode expanded to three options — Seconds / Timecode / Beats.
    - Refactor: Adopt hsuanice_TimeFormat v0.2.0 (MODE + make_formatter + headers).
    - Exports (TSV/CSV) automatically follow the selected mode.
  v0.3.4 (2025-09-02)
    - Refactor: Adopt hsuanice_TimeFormat v0.2.0 (unified MODE + formatter/headers).
    - Feature: Display mode expanded to three options — Seconds / Timecode / Beats.
    - Exports (TSV/CSV) follow the current mode automatically.
  v0.3.3 (2025-09-02)
    - Fix: Resolve naming collision between TF() (REAPER flag helper) and TimeFormat table.
           Renamed the library alias to TFLib to prevent "attempt to call a table value" error.

  v0.3.2 (2025-09-02)
    - Refactor: Use hsuanice_TimeFormat library for Seconds/TC formatting (with fallback if library missing).
  v0.3.1 (2025-09-02)
    - Fix: Restored missing helpers from 0.2.x (selection scan, save dialogs, ImGui context, etc.)
           to resolve "attempt to call a nil value (global 'refresh_now')" and related issues.
    - Feature (from 0.3.0): Toolbar checkbox to toggle Start/End display:
        • Seconds (6 decimals) or
        • Timecode (uses project frame rate via format_timestr_pos mode=5).
    - Exports (TSV/CSV) honor the current display mode.
  v0.2.2 (2025-09-01)
    - UI: Show "Metadata Read vX.Y.Z" in the window title (computed before ImGui_Begin).
    - Cleanup: Optionally remove the toolbar version label to avoid duplication.
    - Behavior: Monitoring, refresh, and exports unchanged from 0.2.1.
  v0.2.1 (2025-09-01)
    - Fully delegate metadata resolution to the Library:
      * Use META.guess_interleave_index() + META.expand("${trk}") / "${chnum}"
        (no local interleave→name/chan logic). Sets __chan_index before expand.
      * Fix: removed a duplicate local 'idx' declaration; more nil-safety.
    - UI: keeps the Library version label; no visual/format changes.
    - Exports/Snapshots: unchanged from 0.2.0 (backward compatible).
  v0.2.0 (2025-09-01)
    - Switched to 'hsuanice Metadata Read' (>= 0.2.0) for all metadata:
      * Uses Library to read/normalize metadata (unwrap SECTION, iXML TRACK_LIST first;
        falls back to BWF Description sTRK#=Name for EdiLoad-split files).
      * Interleave is derived from REAPER take channel mode (Mono-of-N); 
        Meta Track Name and Channel# are resolved from the Library fields.
      * Removed legacy in-file parsers; behavior for Wave Agent is unchanged,
        and EdiLoad-split is now robustly supported.
      * Minor safety/UX hardening (no functional change to table/snapshots/exports).
  v0.1.6
    - Metadata: Added fallback for EdiLoad-split mono files.
      • If IXML TRACK_LIST is missing, parse sTRK#=NAME from BWF/Description.
      • Resolves Meta Track Name and Channel# via existing Interleave pipeline.
  
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

-- ===== Integrate with hsuanice Metadata Read (>= 0.2.0) =====
local META = dofile(
  reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua"
)
assert(META and (META.VERSION or "0") >= "0.2.0",
       "Please update 'hsuanice Metadata Read' to >= 0.2.0")

---------------------------------------
-- Dependency check for ImGui
---------------------------------------
if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui is required (install via ReaPack).", "Missing dependency", 0)
  return
end

---------------------------------------
-- ImGui setup
---------------------------------------
local ctx = reaper.ImGui_CreateContext('Reorder or sort selected items Monitor')
local LIBVER = (META and META.VERSION) and (' | Metadata Read v'..tostring(META.VERSION)) or ''
local FLT_MIN = 1.175494e-38
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

local function fmt_seconds(s) if not s then return "" end return string.format("%.6f", s) end
local function fmt_tc(s)      if not s then return "" end return reaper.format_timestr_pos(s, "", 5) end

-- Time Format Library (with fallback)
local ok, TFLib = pcall(dofile, reaper.GetResourcePath().."/Scripts/hsuanice Scripts/Library/hsuanice_TimeFormat.lua")
if not ok or not TFLib or not TFLib.make_formatter then
  -- minimal fallback (Seconds/TC only); Beats 顯示將退回秒數
  TFLib = {
    VERSION="fallback",
    MODE={ SEC="sec", TC="tc", BEATS="beats" },
    make_formatter=function(mode, opts)
      local dec=(opts and opts.decimals) or 6
      if mode=="tc" then return function(sec) return reaper.format_timestr_pos(sec or 0, "", 5) end end
      return function(sec) return string.format("%."..dec.."f", sec or 0) end
    end,
    headers=function(mode)
      if mode=="tc" then return "Start (TC)","End (TC)" end
      if mode=="beats" then return "Start (s)","End (s)" end
      return "Start (s)","End (s)"
    end,
    format=function(sec, mode, opts)
      return (TFLib.make_formatter(mode, opts))(sec)
    end
  }
end




-- file ops
local function choose_save_path(default_name, filter)
  if reaper.JS_Dialog_BrowseForSaveFile then
    local ok, fn = reaper.JS_Dialog_BrowseForSaveFile("Save", "", default_name, filter)
    if ok and fn and fn ~= "" then return fn end
    return nil
  end
  local proj, projfn = reaper.EnumProjects(-1, "")
  local base = projfn ~= "" and projfn:match("^(.*)[/\\]") or reaper.GetResourcePath()
  return (base or reaper.GetResourcePath()) .. "/" .. default_name
end

local function write_text_file(path, text)
  if not path or path == "" then return false end
  local f = io.open(path, "wb"); if not f then return false end
  f:write(text or ""); f:close(); return true
end

local function timestamp()
  local t=os.date("*t"); return string.format("%04d%02d%02d_%02d%02d%02d",t.year,t.month,t.day,t.hour,t.min,t.sec)
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

---------------------------------------
-- Collect item fields (uses Library)
---------------------------------------
local function collect_fields_for_item(item)
  local f = META.collect_item_fields(item)
  local row = {}

  -- Track index/name
  local tr = reaper.GetMediaItemTrack(item)
  row.track_idx  = tr and math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or 0
  row.track_name = tr and (select(2, reaper.GetTrackName(tr, "")) or "") or ""

  -- File/take from fields
  row.file_name  = f.srcfile or ""
  row.take_name  = f.curtake or ""

  -- Interleave & meta name/chan（Library）
  local idx = META.guess_interleave_index(item, f) or f.__chan_index or 1
  f.__chan_index = idx
  local name = META.expand("${trk}", f, nil, false)
  local ch   = tonumber(META.expand("${chnum}", f, nil, false)) or idx

  row.interleave    = idx
  row.meta_trk_name = name or ""
  row.channel_num   = ch

  -- Item bounds
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  row.start_time = pos
  row.end_time   = pos + len

  row.__fields = f
  return row
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
-- State (UI)
---------------------------------------
local AUTO = true
-- 以三段模式取代 boolean
local TIME_MODE = TFLib.MODE.TC   -- 預設顯示 TC；你也可改成 TFLib.MODE.SEC
local ROWS = {}
local SNAP_BEFORE, SNAP_AFTER = {}, {}
local ROWS = {}
local SNAP_BEFORE, SNAP_AFTER = {}, {}

-- 建立可重用 formatter（在表格列與輸出都共用）
local FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=6})

-- 最薄的轉接：之後如果要改用 FORMAT 直接呼叫，也可移除這個 wrapper
local function format_time(val)
  return FORMAT(val)
end

local function refresh_now()
  ROWS = scan_selection_rows()
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
      esc(format_time(r.start_time)),
      esc(format_time(r.end_time)),
    }, sep)
  end
  return table.concat(out, "\n")
end

---------------------------------------
-- UI
---------------------------------------
local function draw_toolbar()
  reaper.ImGui_Text(ctx, string.format("Selected items: %d", #ROWS))
  reaper.ImGui_SameLine(ctx)
  local chg, v = reaper.ImGui_Checkbox(ctx, "Auto-refresh", AUTO); if chg then AUTO = v end
  reaper.ImGui_SameLine(ctx)
-- 三段模式：Seconds / TC / Beats
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "Seconds", TIME_MODE==TFLib.MODE.SEC) then
  TIME_MODE = TFLib.MODE.SEC
  FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=6})
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "TC", TIME_MODE==TFLib.MODE.TC) then
  TIME_MODE = TFLib.MODE.TC
  FORMAT = TFLib.make_formatter(TIME_MODE)
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "Beats", TIME_MODE==TFLib.MODE.BEATS) then
  TIME_MODE = TFLib.MODE.BEATS
  FORMAT = TFLib.make_formatter(TIME_MODE)
end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Refresh Now", 110, 24) then refresh_now() end

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
    local startHeader, endHeader = TFLib.headers(TIME_MODE)
    reaper.ImGui_TableSetupColumn(ctx, startHeader, TF('ImGui_TableColumnFlags_WidthFixed'), 120)
    reaper.ImGui_TableSetupColumn(ctx, endHeader,   TF('ImGui_TableColumnFlags_WidthFixed'), 120)
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
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, format_time(r.start_time))
      reaper.ImGui_TableNextColumn(ctx); reaper.ImGui_Text(ctx, format_time(r.end_time))
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
  local open = reaper.ImGui_Begin(ctx, "Reorder or Sort — Monitor & Debug"..LIBVER, true, flags)

  draw_toolbar()
  draw_snapshots()
  reaper.ImGui_Spacing(ctx)
  draw_table(ROWS, 360)

  reaper.ImGui_End(ctx)
  if open and not esc_pressed() then reaper.defer(loop) end
end

refresh_now()
loop()
