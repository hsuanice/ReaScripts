--[[
@description Monitor - Reorder or sort selected items vertically
@version 0.4.4.2
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

  Note:
  使用說明（可貼在 README 或腳本註解）

  模式：m:s / TC / Beats / Custom。
  Custom 範本 tokens：
  h, hh：小時（不補零／兩位）
  m, mm：分鐘（0–59）
  s, ss：秒（0–59）
  S...：小數秒，S 數量 = 位數，例如 SSS = 毫秒
  範例：
  hh:mm:ss → 01:23:45
  h:mm → 1:23
  mm:ss.SSS → 83:07.250

  Reference: Script: zaibuyidao_Display Total Length Of Selected Items.lua




@changelog
  v0.4.4.2
    - Fix: ESC on main window not working — removed a duplicate ImGui_CreateContext/ctx block that shadowed the real context; unified to a single context so esc_pressed() and the window share the same ctx.
    - Behavior: Summary ESC closes only the popup; when no popup is open, ESC closes the main window.
  v0.4.4
    - Feature: Handshake-based auto-capture.
      Listens for req_before/req_after and replies with ack_before/ack_after
      after taking snapshots internally. Backward-compatible with legacy capture_* keys.
  V0.4.3.1
    - Fix: Crash on startup (“attempt to call a nil value 'parse_snapshot_tsv'”).
      Forward-declared the parser and bound the later definition so polling can call it safely.
  v0.4.2
    - Fix: Restored per-frame polling of cross-script signals (poll_reorder_signal) in the main loop,
            so auto-capture from the Reorder script works again.
  v0.4.0 (2025-09-03)
    - New: Summary modal (button next to "Save .csv"). Shows item count, total span, total length, and position range.
            Text is selectable, with a one-click Copy, respects current time mode (m:s / TC / Beats / Custom).
    - New: Added Mute and Color columns (swatch + hex).
    - Fix: Removed duplicate table render in main loop (was drawing twice).
    - Fix: Added bootstrap at file end (conditional initial refresh + loop()) so the window launches correctly.
  v0.3.18 (2025-09-03)
    - New: Added "Mute" and "Color" columns (color swatch + hex).
    - New: Summary panel (counts, total duration span, total length sum, and position range),
           fully respecting the current time display mode (m:s / TC / Beats / Custom).
  v0.3.17 (2025-09-03)
    - Fix: When Auto-refresh is OFF, the script no longer performs an initial scan on launch.
           (Guarded the startup refresh; now only runs if AUTO is true.)
    - UX: Refresh Now resets the table view to Live before scanning.
  v0.3.16 (2025-09-03)
    - Fix: Auto-refresh preference now persists correctly. (Added AUTO to forward declarations and removed local shadowing in State (UI).)

  v0.3.15 (2025-09-03)
    - New: Added “Show BEFORE” and “Show AFTER” buttons in the snapshot section (inline with Copy/Save).
    - UX: “Refresh Now” resets the table view back to Live (from Before/After).

  v0.3.14
    - Restore: Added “Capture BEFORE” & “Capture AFTER” buttons to the toolbar.
    - Feature: Auto-refresh state is now persisted across sessions.
  v0.3.13 (2025-09-03)
    - Fix: Persisted time mode & custom pattern now restore correctly.
      (Forward-declared TIME_MODE/CUSTOM_PATTERN/FORMAT and removed local shadowing in State (UI).)

  v0.3.12 (2025-09-03)
    - Fix: Persist selection — time mode and custom pattern now saved on every change (Radio/Input) via ExtState.
    - UX: Window close button (X) now works. Begin() captures (visible, open); loop stops when open == false or ESC is pressed.
  v0.3.11 (2025-09-03)
    - Fix: Forward-declared TFLib and changed library load to assign instead of re-declare (removed 'local' before TFLib).
      This prevents load_prefs() from capturing a nil global TFLib and restores the saved mode on startup.

  v0.3.10 (2025-09-03)
    - Persistence: Remembers the selected time display mode (m:s / TC / Beats / Custom) and the custom pattern across runs via ExtState.
      Re-opening the script restores your last choice; if it was Custom, the previous pattern is applied automatically.
  v0.3.9 (2025-09-03)
    - UI: Moved "Refresh Now" and Copy/Save buttons to the next row by removing an extra ImGui_SameLine().
      No NewLine/Spacing added to maintain minimal vertical gap and a tighter layout.
  v0.3.8 (2025-09-03)
    - UI: Moved Custom pattern input inline to the right of the "Custom" mode selector.
    - UX: Added tooltip (ⓘ) explaining pattern tokens.
  v0.3.7 (2025-09-02)
    - New: Added "Custom" display mode. Users can type patterns like "hh:mm:ss", "h:mm", "mm:ss.SSS".
    - API: Integrated with hsuanice_Time Format v0.3.0 (MODE.CUSTOM + pattern support).
    - UI: Start/End headers now show the selected pattern, e.g. "Start (hh:mm:ss)".
  v0.3.6 (2025-09-02)
    - Feature: Replace "Seconds" with "Minutes:Seconds" (m:s) display and export.
    - Fix: Beats mode now formats correctly (no longer falls back to seconds).
    - UI: Start/End headers switch to "Start (m:s) / End (m:s)" when m:s mode is selected.
  v0.3.5 (2025-09-02)
    - Feature: Display mode expanded to three options — Seconds / Timecode / Beats.
    - Refactor: Adopt hsuanice_Time Format v0.2.0 (MODE + make_formatter + headers).
    - Exports (TSV/CSV) automatically follow the selected mode.
  v0.3.4 (2025-09-02)
    - Refactor: Adopt hsuanice_Time Format v0.2.0 (unified MODE + formatter/headers).
    - Feature: Display mode expanded to three options — Seconds / Timecode / Beats.
    - Exports (TSV/CSV) follow the current mode automatically.
  v0.3.3 (2025-09-02)
    - Fix: Resolve naming collision between TF() (REAPER flag helper) and TimeFormat table.
           Renamed the library alias to TFLib to prevent "attempt to call a table value" error.

  v0.3.2 (2025-09-02)
    - Refactor: Use hsuanice_Time Format library for Seconds/TC formatting (with fallback if library missing).
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
-- ImGui setup (唯一的一組，請勿重複建立)
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



-- Popup title（供 ESC 判斷與 BeginPopupModal 使用）
local POPUP_TITLE = "Summary"



---------------------------------------
-- Small utils
---------------------------------------

-- Forward declarations so load_prefs() updates the same locals (not globals)
local TIME_MODE, CUSTOM_PATTERN, FORMAT, AUTO
local scan_selection_rows
local parse_snapshot_tsv   -- ← 新增：先宣告，讓上面可以呼叫

-- === Preferences (persist across runs) ===
local EXT_NS = "hsuanice_ReorderSort_Monitor"

local function save_prefs()
  reaper.SetExtState(EXT_NS, "time_mode", TIME_MODE or "", true)
  reaper.SetExtState(EXT_NS, "custom_pattern", CUSTOM_PATTERN or "", true)
  reaper.SetExtState(EXT_NS, "auto_refresh", AUTO and "1" or "0", true)
end

local function load_prefs()
  -- restore mode
  local m = reaper.GetExtState(EXT_NS, "time_mode")
  if m and m ~= "" then
    if     m == "ms"     then TIME_MODE = TFLib.MODE.MS
    elseif m == "tc"     then TIME_MODE = TFLib.MODE.TC
    elseif m == "beats"  then TIME_MODE = TFLib.MODE.BEATS
    elseif m == "sec"    then TIME_MODE = TFLib.MODE.SEC
    elseif m == "custom" then TIME_MODE = TFLib.MODE.CUSTOM
    end
  end
  -- restore pattern
  local pat = reaper.GetExtState(EXT_NS, "custom_pattern")
  if pat and pat ~= "" then CUSTOM_PATTERN = pat end

  -- rebuild formatter according to restored state
  if TIME_MODE == TFLib.MODE.MS then
    FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=3})
  elseif TIME_MODE == TFLib.MODE.CUSTOM then
    FORMAT = TFLib.make_formatter(TIME_MODE, {pattern=CUSTOM_PATTERN})
  else
    FORMAT = TFLib.make_formatter(TIME_MODE)
  end

  -- restpre auto-refresh state
  local a = reaper.GetExtState(EXT_NS, "auto_refresh")
  if a ~= "" then AUTO = (a ~= "0") end
end


local function item_start(it) return reaper.GetMediaItemInfo_Value(it,"D_POSITION") end
local function item_track(it) return reaper.GetMediaItemTrack(it) end
local function track_index(tr) return math.floor(reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or 0) end
local function track_name(tr) local _, n = reaper.GetTrackName(tr, "") return n end

local function fmt_seconds(s) if not s then return "" end return string.format("%.6f", s) end
local function fmt_tc(s)      if not s then return "" end return reaper.format_timestr_pos(s, "", 5) end

-- Time Format Library (with fallback)
local ok
ok, TFLib = pcall(dofile, reaper.GetResourcePath().."/Scripts/hsuanice Scripts/Library/hsuanice_Time Format.lua")

if not ok or not TFLib or not TFLib.make_formatter then
  -- fallback: 支援 m:s / TC / Beats（三種）
  local function _fmt_ms(sec, decimals)
    if sec == nil then return "" end
    local sign = ""
    if sec < 0 then sign = "-"; sec = -sec end
    local m = math.floor(sec / 60)
    local dec = tonumber(decimals) or 3
    local s = sec - m*60
    local cap = 60 - (10^-dec) * 0.5
    if s >= cap then m = m + 1; s = 0 end
    local s_fmt = ("%0."..dec.."f"):format(s)
    if tonumber(s_fmt) < 10 then s_fmt = "0"..s_fmt end
    return ("%s%d:%s"):format(sign, m, s_fmt)
  end
  TFLib = {
    VERSION="fallback",
    MODE={ SEC="sec", MS="ms", TC="tc", BEATS="beats" },
    make_formatter=function(mode, opts)
      local m = mode
      if m=="tc" then return function(sec) return reaper.format_timestr_pos(sec or 0, "", 5) end end
      if m=="beats" then return function(sec) return reaper.format_timestr_pos(sec or 0, "", 1) end end
      if m=="sec" then
        local dec=(opts and opts.decimals) or 6
        return function(sec) return string.format("%."..dec.."f", sec or 0) end
      end
      local dec=(opts and opts.decimals) or 3
      return function(sec) return _fmt_ms(sec or 0, dec) end
    end,
    headers=function(mode)
      if mode=="tc" then return "Start (TC)","End (TC)" end
      if mode=="beats" then return "Start (Beats)","End (Beats)" end
      if mode=="sec" then return "Start (s)","End (s)" end
      return "Start (m:s)","End (m:s)"
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

local function compute_summary(rows)
  local n = #rows
  if n == 0 then return {count=0} end
  local min_start = math.huge
  local max_end   = -math.huge
  local sum_len   = 0.0
  for _, r in ipairs(rows) do
    local s = tonumber(r.start_time) or 0
    local e = tonumber(r.end_time)   or s
    if s < min_start then min_start = s end
    if e > max_end   then max_end   = e end
    sum_len = sum_len + (e - s)
  end
  local span = max_end - min_start
  return {
    count = n,
    min_start = min_start,
    max_end   = max_end,
    span      = span,
    sum_len   = sum_len
  }
end






-- forward locals (避免之後被重新 local 化)
ROWS = {}
SNAP_BEFORE, SNAP_AFTER = {}, {}


-- === Cross-script signal (auto-capture from Reorder) ===
local SIG_NS = "hsuanice_ReorderSort_Signal"
local LAST_REQ_BEFORE, LAST_REQ_AFTER = "", ""

local function poll_reorder_signal()
  -- New handshake: BEFORE
  local rb = reaper.GetExtState(SIG_NS, "req_before")
  if rb ~= "" and rb ~= LAST_REQ_BEFORE then
    LAST_REQ_BEFORE = rb
    SNAP_BEFORE = scan_selection_rows()                     -- 由 Monitor 自己掃
    reaper.SetExtState(SIG_NS, "ack_before", rb, false)      -- 回 ACK
    reaper.DeleteExtState(SIG_NS, "req_before", true)
  end

  -- New handshake: AFTER
  local ra = reaper.GetExtState(SIG_NS, "req_after")
  if ra ~= "" and ra ~= LAST_REQ_AFTER then
    LAST_REQ_AFTER = ra
    SNAP_AFTER = scan_selection_rows()
    reaper.SetExtState(SIG_NS, "ack_after", ra, false)
    reaper.DeleteExtState(SIG_NS, "req_after", true)
  end

  -- （選擇性）支援舊的 capture_* / snapshot_*，你可保留原本 parse_snapshot_tsv 的分支；不再贅述。
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

  -- Mute state
  row.muted = (reaper.GetMediaItemInfo_Value(item, "B_MUTE") or 0) > 0.5

  -- Item color
  local native = reaper.GetDisplayedMediaItemColor(item) or 0
  if native ~= 0 then
    local r, g, b = reaper.ColorFromNative(native)
    row.color_rgb = { r, g, b }
    row.color_hex = string.format("#%02X%02X%02X", r, g, b)
  else
    row.color_rgb, row.color_hex = nil, ""
  end



  row.__fields = f
  return row
end

function scan_selection_rows()
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
AUTO = (AUTO == nil) and true or AUTO

TABLE_SOURCE = "live"   -- "live" | "before" | "after"

-- Display mode state (persisted)
TIME_MODE = TFLib.MODE.MS        -- 預設 m:s；load_prefs() 會覆寫為上次選擇
CUSTOM_PATTERN = "hh:mm:ss"

-- Data
ROWS = {}
SNAP_BEFORE, SNAP_AFTER = {}, {}

-- Current formatter（會在切換模式/修改 pattern 時重建）
FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=3})

-- 超薄轉接（保留相容性；也可以讓 table/export 都直接叫 FORMAT(r.start_time)）
local function format_time(val) return FORMAT(val) end

local function refresh_now()
  ROWS = scan_selection_rows()
end

-- 啟動時讀回上次的模式與 pattern，並重建 FORMAT
if load_prefs then load_prefs() end



local function build_summary_text(rows)
  local S = compute_summary(rows or {})
  if not S or (S.count or 0) == 0 then return "No items." end
  local from = format_time(S.min_start)
  local to   = format_time(S.max_end)
  local span = format_time(S.span)
  local sum  = format_time(S.sum_len)
  return table.concat({
    ("Number of items:\n%d"):format(S.count),
    "",
    ("Total duration:\n%s"):format(span),
    "",
    ("Total length:\n%s"):format(sum),
    "",
    ("Position:\n%s - %s"):format(from, to),
  }, "\n")
end

local function draw_summary_popup()
  if reaper.ImGui_BeginPopupModal(ctx, POPUP_TITLE, true, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
    -- 依目前顯示來源挑 rows（你現在有 live/before/after 的切換）
    local rows = ROWS
    if     TABLE_SOURCE == "before" then rows = SNAP_BEFORE
    elseif TABLE_SOURCE == "after"  then rows = SNAP_AFTER end

    local txt = build_summary_text(rows)

    -- 可選可複製：用唯讀的多行輸入框
    reaper.ImGui_SetNextItemWidth(ctx, 560)
    reaper.ImGui_InputTextMultiline(ctx, "##summary_text", txt, 560, 200,
      reaper.ImGui_InputTextFlags_ReadOnly())

    -- Copy / OK
    if reaper.ImGui_Button(ctx, "Copy", 80, 24) then
      reaper.ImGui_SetClipboardText(ctx, txt)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "OK", 80, 24) 
       or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    reaper.ImGui_EndPopup(ctx)
  end
end


-- === Parse snapshot TSV coming from Reorder ===
function parse_snapshot_tsv(text)
  local rows = {}
  if not text or text == "" then return rows end
  local first = true
  for line in tostring(text):gmatch("([^\n]*)\n?") do
    if line == "" then break end
    if first then first = false -- skip header
    else
      local cols = {}
      local i = 1
      for c in (line.."\t"):gmatch("([^\t]*)\t") do cols[i]=c; i=i+1 end
      local r = {
        track_idx    = tonumber(cols[2]) or 0,
        track_name   = cols[3] or "",
        take_name    = cols[4] or "",
        file_name    = cols[5] or "",
        meta_trk_name= cols[6] or "",
        channel_num  = tonumber(cols[7]) or nil,
        interleave   = tonumber(cols[8]) or nil,
        muted        = (cols[9] == "1"),
        color_hex    = cols[10] or "",
        start_time   = tonumber(cols[11]) or 0,
        end_time     = tonumber(cols[12]) or 0,
      }
      -- 供色塊用：把 hex 轉成 rgb
      if r.color_hex ~= "" then
        local rr,gg,bb = r.color_hex:match("^#?(%x%x)(%x%x)(%x%x)$")
        if rr then r.color_rgb = { tonumber(rr,16), tonumber(gg,16), tonumber(bb,16) } end
      end
      rows[#rows+1] = r
    end
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

  -- header（加入 Mute / ColorHex）
  out[#out+1] = table.concat({
    "#","TrackIdx","TrackName","TakeName","Source File",
    "MetaTrackName","Channel#","Interleave","Mute","ColorHex","StartTime","EndTime"
  }, sep)

  -- rows
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
      esc(r.muted and "1" or "0"),
      esc(r.color_hex or ""),
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
  local chg, v = reaper.ImGui_Checkbox(ctx, "Auto-refresh", AUTO)
  if chg then
    AUTO = v
    reaper.SetExtState(EXT_NS, "auto_refresh", v and "1" or "0", true)
  end
  reaper.ImGui_SameLine(ctx)
  
-- 四種：m:s / TC / Beats / Custom（Input 直接在 Custom 右邊）
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "m:s", TIME_MODE==TFLib.MODE.MS) then
  TIME_MODE = TFLib.MODE.MS
  FORMAT = TFLib.make_formatter(TIME_MODE, {decimals=3})
  save_prefs()
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "TC", TIME_MODE==TFLib.MODE.TC) then
  TIME_MODE = TFLib.MODE.TC
  FORMAT = TFLib.make_formatter(TIME_MODE)
  save_prefs()
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "Beats", TIME_MODE==TFLib.MODE.BEATS) then
  TIME_MODE = TFLib.MODE.BEATS
  FORMAT = TFLib.make_formatter(TIME_MODE)
  save_prefs()
end
reaper.ImGui_SameLine(ctx)
if reaper.ImGui_RadioButton(ctx, "Custom", TIME_MODE==TFLib.MODE.CUSTOM) then
  TIME_MODE = TFLib.MODE.CUSTOM
  FORMAT = TFLib.make_formatter(TIME_MODE, {pattern=CUSTOM_PATTERN})
  save_prefs()
end
-- ← 直接接在 Custom 後面放輸入框
reaper.ImGui_SameLine(ctx)
reaper.ImGui_Text(ctx, "Pattern:")
reaper.ImGui_SameLine(ctx)
reaper.ImGui_SetNextItemWidth(ctx, 180)
local changed, newpat = reaper.ImGui_InputText(ctx, "##custom_pattern", CUSTOM_PATTERN)
if changed then
  CUSTOM_PATTERN = newpat
  if TIME_MODE==TFLib.MODE.CUSTOM then
    FORMAT = TFLib.make_formatter(TIME_MODE, {pattern=CUSTOM_PATTERN})
  end
  save_prefs()
end
-- 小提示（hover 顯示）
reaper.ImGui_SameLine(ctx)
reaper.ImGui_TextDisabled(ctx, "ⓘ")
if reaper.ImGui_IsItemHovered(ctx) then
  reaper.ImGui_BeginTooltip(ctx)
  reaper.ImGui_Text(ctx, "Tokens: h | hh | m | mm | s | ss | S… (e.g. SSS = .mmm)")
  reaper.ImGui_EndTooltip(ctx)
end



  if reaper.ImGui_Button(ctx, "Refresh Now", 110, 24) then
    TABLE_SOURCE = "live"
    refresh_now()
  end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Capture BEFORE", 130, 24) then
    SNAP_BEFORE = scan_selection_rows()
  end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Capture AFTER", 120, 24) then
    SNAP_AFTER = scan_selection_rows()
    refresh_now()
  end

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

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, POPUP_TITLE, 100, 24) then
    reaper.ImGui_OpenPopup(ctx, POPUP_TITLE)
  end



end

local function draw_table(rows, height)
  local flags = TF('ImGui_TableFlags_Borders') | TF('ImGui_TableFlags_RowBg') | TF('ImGui_TableFlags_SizingStretchProp')
  if reaper.ImGui_BeginTable(ctx, "live_table", 12, flags, -FLT_MIN, height or 360) then
    reaper.ImGui_TableSetupColumn(ctx, "#", TF('ImGui_TableColumnFlags_WidthFixed'), 36)
    reaper.ImGui_TableSetupColumn(ctx, "TrackIdx", TF('ImGui_TableColumnFlags_WidthFixed'), 45)
    reaper.ImGui_TableSetupColumn(ctx, "Track Name")
    reaper.ImGui_TableSetupColumn(ctx, "Take Name")
    reaper.ImGui_TableSetupColumn(ctx, "Source File")
    reaper.ImGui_TableSetupColumn(ctx, "Meta Track Name")
    reaper.ImGui_TableSetupColumn(ctx, "Chan#", TF('ImGui_TableColumnFlags_WidthFixed'), 36)
    reaper.ImGui_TableSetupColumn(ctx, "Interleave", TF('ImGui_TableColumnFlags_WidthFixed'), 50)
    local startHeader, endHeader = TFLib.headers(TIME_MODE, {pattern=CUSTOM_PATTERN})
    reaper.ImGui_TableSetupColumn(ctx, "Mute", TF('ImGui_TableColumnFlags_WidthFixed'), 52)
    reaper.ImGui_TableSetupColumn(ctx, "Color", TF('ImGui_TableColumnFlags_WidthFixed'), 120)
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

      -- Mute
      reaper.ImGui_TableNextColumn(ctx)
      reaper.ImGui_Text(ctx, r.muted and "M" or "")

      -- Color
      reaper.ImGui_TableNextColumn(ctx)
      if r.color_rgb and r.color_rgb[1] then
        local rr, gg, bb = r.color_rgb[1]/255, r.color_rgb[2]/255, r.color_rgb[3]/255
        local col = reaper.ImGui_ColorConvertDouble4ToU32(rr, gg, bb, 1.0)
        reaper.ImGui_TextColored(ctx, col, "■")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, r.color_hex or "")
      else
        reaper.ImGui_Text(ctx, "")
      end

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

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Show BEFORE", 130, 22) then
    TABLE_SOURCE = "before"
  end

  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Text(ctx, string.format("Snapshot AFTER : %d rows  ", #SNAP_AFTER)); reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Copy AFTER (TSV)", 150, 22) then reaper.ImGui_SetClipboardText(ctx, build_table_text("tsv", SNAP_AFTER)) end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Save AFTER .tsv", 150, 22) then
    local p = choose_save_path("ReorderSort_After_"..timestamp()..".tsv","Tab-separated (*.tsv)\0*.tsv\0All (*.*)\0*.*\0")
    if p then write_text_file(p, build_table_text("tsv", SNAP_AFTER)) end
  end

  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Show AFTER", 120, 22) then
    TABLE_SOURCE = "after"
  end


end

---------------------------------------
-- Main loop
---------------------------------------
local function loop()
  if AUTO then refresh_now() end

  reaper.ImGui_SetNextWindowSize(ctx, 1000, 640, reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoCollapse()
  local visible, open = reaper.ImGui_Begin(ctx, "Reorder or Sort — Monitor & Debug"..LIBVER, true, flags)


  -- ESC 關閉整個視窗（若 Summary modal 開著，先只關 modal）
  if esc_pressed() and not reaper.ImGui_IsPopupOpen(ctx, POPUP_TITLE) then
    open = false
  end


  -- 🔧 補回這行：每幀輪詢 Reorder 的訊號
  poll_reorder_signal()

  -- Top bar + Summary popup
  draw_toolbar()
  draw_summary_popup()

  -- Snapshots
  draw_snapshots()
  reaper.ImGui_Spacing(ctx)

  -- 決定要顯示的 rows（Live / BEFORE / AFTER）
  local rows_to_show = ROWS
  if     TABLE_SOURCE == "before" then rows_to_show = SNAP_BEFORE
  elseif TABLE_SOURCE == "after"  then rows_to_show = SNAP_AFTER
  end

  draw_table(rows_to_show, 360)

  reaper.ImGui_End(ctx)

  -- GOOD：要不要續跑只看 `open`；按 ESC 的判斷已在上面完成
  if open then
    reaper.defer(loop)
  else
    save_prefs()
  end
end

-- Boot
if AUTO then refresh_now() end  -- Auto-refresh 開啟才在啟動時掃一次
loop()                           -- 啟動 UI 主迴圈
