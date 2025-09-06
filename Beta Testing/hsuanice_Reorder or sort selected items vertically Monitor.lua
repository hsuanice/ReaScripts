--[[
@description Monitor - Reorder or sort selected items vertically
@version 0.6.11 Fill now support mullti-columns
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
  v0.6.11
    - Paste: when the source is a single row spanning multiple columns (e.g., Take Name + Item Note),
      pasting into a multi-row selection now “fills down” row-by-row, Excel-style.
      • Each destination row receives the source row’s values left-to-right.
      • No wrap: if a destination row has more selected columns than the source width, extras are left untouched.
      • Still supports: single value → fill all; multi → single cell spill (0.6.10); multi → multi row-major mapping (0.6.9).
    - Live view only; Track/Take/Item Note remain the only writable columns; others safely ignore writes.
    - One undo per paste; undo/redo keeps your item selection (0.6.8.1).

  v0.6.10
    - Paste: multi-cell sources now “spill” from a single target cell, Excel-style.
      • If the source has multiple values but only one destination cell is selected,
        the paste expands from that cell in row-major order, matching the source’s 2D shape.
      • Single value still fills all selected cells (across columns or non-contiguous ranges).
      • Multi→multi keeps row-major mapping and truncates when destination is smaller (no wrap).
    - Writable columns remain Track Name / Take Name / Item Note; other columns safely ignore writes.
    - One undo per paste; Live view only; selection protection on undo/redo remains in effect.

  v0.6.9
    - Paste behavior now matches spreadsheet intuition:
      • Single source value fills all selected cells.
      • Multiple source values map to selected cells in row-major order, truncating if destination is larger (no wrap).
      • Selection can be non-rectangular; shape does not need to match.
    - Writable columns remain Track Name / Take Name / Item Note; other columns accept paste but are ignored safely.
    - Live view only; Snapshots stay read-only. One undo per paste; table refreshes after paste.
    - If no cell is selected when pasting, a message box prompts you to select cells first.

  v0.6.8.1
    - Undo/Redo selection protection (always on):
      • When using table shortcuts (Cmd/Ctrl+Z, Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y),
        the current item selection is snapshotted by GUID and restored after Undo/Redo.
      • Works even if REAPER Preferences → Undo → “Include selection: item” is OFF.
      • Live view refreshes right after to stay in sync.
  v0.6.8
    - Shortcuts: Undo (Cmd/Ctrl+Z) and Redo (Cmd/Ctrl+Shift+Z or Cmd/Ctrl+Y).
    - All write operations already create undo points:
    - Inline edits (Track / Take / Item Note) — one undo per commit.
    - Paste (block) — one undo per paste.
    - Delete (clear selected cell text) — one undo per delete.
    - The table refreshes immediately after Undo/Redo to stay in sync.
    - Note: For predictable selection behavior during Undo/Redo, enable:
      “Preferences → General → Undo → Include selection: item”.

  v0.6.7
    - New: Delete clears text in the selected cells (Live view only).
      • Writable columns: Track Name, Take Name, Item Note.
      • Non-writable columns are ignored.
      • Works with single cell, Cmd/Ctrl multi-select, and Shift rectangular selection.
      • One Undo block; table refreshes after deletion.

  v0.6.6 — fix click anchor
    - Fix: Shift+click rectangular selection didn’t work after a plain click.
      • Root cause: the code set SEL.anchor and then immediately cleared it via sel_clear(),
        both in handle_cell_click() and in the first-time branch of sel_rect_apply().
      • Change: clear selected cells first, then set the anchor; and on first Shift action,
        keep the anchor (reset only SEL.cells).
    - Result: Single-click sets the anchor; Shift+click extends a rectangle from that anchor;
      Cmd/Ctrl+click toggles cells without touching the anchor.
    - No behavior changes to editing (double-click to edit), copy, or paste rules
      (paste still Live-only and only for Track/Take/Item Note).
  v0.6.5
    - Make First and Second columns selectable
  v0.6.4
    - Excel-like selection & clipboard:
        • Click selects a cell; Shift+click selects a rectangular range; Cmd/Ctrl+click toggles noncontiguous cells.
        • Cmd/Ctrl+C copies the selection as TSV (tab/newline delimited).
        • Cmd/Ctrl+V pastes into the Live view: 1×1 fills the selection; shape-matched blocks paste 1:1.
    - Writable columns (Live only): Track Name, Take Name, Item Note.
        • Track names apply strictly by Track object (GUID) — never by text, so identically named tracks are unaffected.
        • Take names auto-create an empty take if missing; Item Notes write to P_NOTES.
    - Safety & UX: one Undo block per paste; auto-refresh pauses during edit/paste and resumes after; clear, predictable behavior.
    - Snapshots: copy allowed; paste is disabled by design.

  v0.6.3
    - Table layout: switched to fixed-width columns with horizontal scrolling (no more squeezing).
    - Set practical default widths for all columns; key edit fields (Track/Take/Item Note) stay readable.
    - Header tweak: “TrackIdx” → “TrkID”.
    - Wrapping: long text wraps inside its fixed-width cell; overflow is available via horizontal scroll.
    - Columns remain resizable by the user; widths can be fine-tuned interactively.
  v0.6.2
    - Editing UX: Fixed focus so double-click reliably enters inline edit and the input is immediately active with the text preselected.
    - Commit behavior: Leaving the cell (losing focus) now commits just like pressing Enter; Esc cancels. Only writes (and creates one Undo step) when the value actually changes.
    - Stability: While a cell is being edited we render only the InputText (no overlapping Selectable), avoiding focus flicker and ID conflicts.
    - Auto-refresh: Continues to refresh when not editing, pauses during edit, and resumes as soon as the edit ends (on Enter, blur, or Esc).
  v0.6.1
    - Fix: Resolved Dear ImGui ID conflicts in editable cells (Track Name, Take Name, Item Note)
          by using a row-level PushID keyed by item GUID plus per-cell "##trk"/"##take"/"##note" IDs.
    - Change: Entering edit mode no longer immediately collapses (auto-refresh is paused while editing).
    - Known issue: After double-click, the input field shows but sometimes doesn’t accept typing
                  (focus isn’t captured). Will be addressed next by giving the editor explicit focus
                  and rendering it exclusively while active.
    - Known issue: With the guard `if AUTO and (not EDIT or not EDIT.col) then refresh_now() end`,
                  auto-refresh may remain suspended in some setups. Use
                  `if AUTO and not (EDIT and EDIT.col) then refresh_now() end`
                  as a temporary workaround; a proper fix will follow.
    - No changes to exports, snapshots, or metadata handling.
  v0.6.0
    - Inline editing (Excel-like) in the table:
        • Single-click selects a cell so you can copy/paste its text.
        • Double-click enters edit mode (InputText) with the current value preselected.
    - Editable columns: Track Name, Take Name, Item Note.
        • Track Name writes to the exact Track object (by GUID) — only that track is renamed,
          even if other tracks share the same name.
        • Take Name and Item Note write to the specific item/take of that row.
        • Edits are allowed even when the item has no active take; handled safely without touching BWF/iXML.
    - Commit & cancel behavior:
        • Enter / Tab / clicking outside commits the edit.
        • Esc cancels and restores the original value.
    - Safety & consistency:
        • Only writes (and creates one Undo step) when the value actually changes.
        • Trims leading/trailing whitespace (keeps interior spaces); applies a reasonable length limit.
        • After commit, the view refreshes so all rows tied to the same Track object update consistently.
    - No change to embedded metadata (BWF/iXML).
    - Exports (TSV/CSV) and BEFORE/AFTER snapshots reflect the edited values.
  v0.5.2
    - Parser: Updated parse_snapshot_tsv() to accept both "M" and "1" as muted values in TSV input,
              ensuring compatibility with exports from v0.5.1 and later (which use "M"/blank).
    - No other functional changes; UI and exports remain identical to v0.5.1.
  v0.5.1
    - Export: Changed the Mute column in TSV/CSV exports to output "M" when muted and blank when unmuted (was previously 1/0).
  v0.5.0
    - NEW: Inserted "Item Note" column (between Take Name and Source File) across UI and TSV/CSV exports.
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
local parse_snapshot_tsv   -- ← 先宣告
local refresh_now          -- ← 新增：先宣告 refresh_now，讓上面函式抓到 local
local _trim               -- ← 新增：先宣告 _trim，供前面函式當作同一個 local 來引用



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

  -- Stable GUIDs for unique IDs and cross-frame identity
  local _, item_guid  = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
  row.__item_guid     = item_guid or ""
  local _, track_guid = tr and reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  row.__track_guid    = track_guid or ""
  row.__take          = reaper.GetActiveTake(item)




  -- File/take from fields
  row.file_name  = f.srcfile or ""
  row.take_name  = f.curtake or ""
  row.item_note  = f.curnote or ""   -- NEW (0.5.0)

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

  -- Keep object references for editing
  row.__item  = item
  row.__track = tr
  row.__take  = reaper.GetActiveTake(item)

  -- Item note (trim head/tail spaces; keep middle spaces)
  local ok_note, note = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  row.item_note = (ok_note and (note or "")) or ""




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

-- === Inline edit state ===
local EDIT = { row = nil, col = nil, buf = "", want_focus = false }

-- === Selection model (Excel-like) & clipboard ===
local SEL = {
  cells = {},            -- set: ["<item_guid>:<col>"]=true
  anchor = nil,          -- { guid = "...", col = N }
}
local function _cell_key(guid, col) return (guid or "") .. ":" .. tostring(col or "") end
local function sel_clear() SEL.cells = {}; SEL.anchor = nil end
local function sel_has(guid, col) return SEL.cells[_cell_key(guid, col)] == true end
local function sel_add(guid, col) SEL.cells[_cell_key(guid, col)] = true end
local function sel_toggle(guid, col)
  local k = _cell_key(guid, col)
  SEL.cells[k] = not SEL.cells[k] or nil
end

-- 取得目前是否按住 CmdOrCtrl / Shift
local function _mods()
  local mods = reaper.ImGui_GetKeyMods(ctx)
  local has = function(mask) return (mask ~= 0) and ((mods & mask) ~= 0) end
  local M = {
    ctrl  = has(reaper.ImGui_Mod_Ctrl and reaper.ImGui_Mod_Ctrl() or 0),
    super = has(reaper.ImGui_Mod_Super and reaper.ImGui_Mod_Super() or 0),
    shift = has(reaper.ImGui_Mod_Shift and reaper.ImGui_Mod_Shift() or 0),
    alt   = has(reaper.ImGui_Mod_Alt and reaper.ImGui_Mod_Alt() or 0),
  }
  M.shortcut = has(reaper.ImGui_Mod_Shortcut and reaper.ImGui_Mod_Shortcut() or 0) or M.ctrl or M.super
  return M
end
local function shortcut_pressed(key_const)
  local m = _mods()
  return m.shortcut and reaper.ImGui_IsKeyPressed(ctx, key_const, false)
end

-- 由 rows 建立 rowIndex 對照（以 item_guid 為鍵）
local function build_row_index_map(rows)
  local map = {}
  for i, rr in ipairs(rows or {}) do
    map[rr.__item_guid or ("row"..i)] = i
  end
  return map
end

-- 計算矩形選取（anchor 與目前 guid,col 之間）
local function sel_rect_apply(rows, row_index_map, cur_guid, cur_col)
  if not (SEL.anchor and SEL.anchor.guid and SEL.anchor.col) then
    SEL.anchor = { guid = cur_guid, col = cur_col }
    -- 只清已選的 cells，不要清掉 anchor
    SEL.cells = {}; sel_add(cur_guid, cur_col)
    return
  end
  SEL.cells = {}
  local a_idx = row_index_map[SEL.anchor.guid] or 1
  local b_idx = row_index_map[cur_guid] or a_idx
  local r1, r2 = math.min(a_idx, b_idx), math.max(a_idx, b_idx)
  local c1, c2 = math.min(SEL.anchor.col, cur_col), math.max(SEL.anchor.col, cur_col)
  for i = r1, r2 do
    local g = rows[i].__item_guid
    for c = c1, c2 do sel_add(g, c) end
  end
end

-- 取得某格「顯示用文字」（複製用；與 UI 呈現一致）
local function get_cell_text(i, r, col, fmt)
  if     col == 1  then return tostring(i)
  elseif col == 2  then return tostring(r.track_idx or "")
  elseif col == 3  then return tostring(r.track_name or "")
  elseif col == 4  then return tostring(r.take_name or "")
  elseif col == 5  then return tostring(r.item_note or "")
  elseif col == 6  then return tostring(r.file_name or "")
  elseif col == 7  then return tostring(r.meta_trk_name or "")
  elseif col == 8  then return tostring(r.channel_num or "")
  elseif col == 9  then return tostring(r.interleave or "")
  elseif col == 10 then return r.muted and "M" or ""
  elseif col == 11 then return tostring(r.color_hex or "")
  elseif col == 12 then return FORMAT(r.start_time)
  elseif col == 13 then return FORMAT(r.end_time)
  end
  return ""
end

-- 複製目前選取到剪貼簿（TSV）
local function copy_selection(rows, row_index_map)
  -- 找出被選的所有 (row,col)，並計算最小包圍矩形
  local minr, maxr, minc, maxc = math.huge, -math.huge, math.huge, -math.huge
  local selected = {}
  for guid_col, _ in pairs(SEL.cells) do
    local g, c = guid_col:match("^(.-):(%d+)$")
    local rowi = row_index_map[g]
    local col  = tonumber(c)
    if rowi and col then
      selected[#selected+1] = {row=rowi, col=col}
      if rowi < minr then minr = rowi end
      if rowi > maxr then maxr = rowi end
      if col  < minc then minc = col  end
      if col  > maxc then maxc = col  end
    end
  end
  if #selected == 0 then return end
  local out = {}
  for i=minr, maxr do
    local r = rows[i]
    local line = {}
    for c=minc, maxc do
      if sel_has(r.__item_guid, c) then
        line[#line+1] = get_cell_text(i, r, c)
      else
        line[#line+1] = ""
      end
    end
    out[#out+1] = table.concat(line, "\t")
  end
  reaper.ImGui_SetClipboardText(ctx, table.concat(out, "\n"))
end

-- 解析剪貼簿文字成 2D 陣列（TSV / 簡單 CSV）
local function parse_clipboard_table(text)
  text = tostring(text or "")
  if text == "" then return {} end
  local rows = {}
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (text.."\n"):gmatch("([^\n]*)\n") do
    if line == "" then
      rows[#rows+1] = {""}
    else
      local cols = {}
      -- 先試 TSV
      for c in (line.."\t"):gmatch("([^\t]*)\t") do cols[#cols+1] = c end
      -- 若只有 1 欄且含逗號，視為簡單 CSV
      if #cols == 1 and line:find(",") then
        cols = {}
        for c in (line..","):gmatch("([^,]*),") do cols[#cols+1] = (c or ""):gsub('^"(.*)"$','%1'):gsub('""','"') end
      end
      rows[#rows+1] = cols
    end
  end
  return rows
end


-- 來源 2D 形狀：回傳 rows, cols（以各列最大欄數為寬）
local function src_shape_dims(tbl)
  local rows = #tbl
  local cols = 0
  for i = 1, rows do
    if #tbl[i] > cols then cols = #tbl[i] end
  end
  return rows, cols
end

-- 依「來源形狀」與「單一錨點（選到的一格）」產生展開後的目標格清單（行優先、左到右）
local function build_dst_by_anchor_and_shape(rows, anchor_desc, src_rows, src_cols)
  local dst = {}
  for i = 0, src_rows - 1 do
    local ri = (anchor_desc.row_index or 1) + i
    if ri >= 1 and ri <= #rows then
      local r = rows[ri]
      for j = 0, src_cols - 1 do
        local col = (anchor_desc.col or 1) + j
        dst[#dst+1] = { row_index = ri, col = col, row = r }
      end
    end
  end
  table.sort(dst, function(a,b)
    if a.row_index ~= b.row_index then return a.row_index < b.row_index end
    return a.col < b.col
  end)
  return dst
end


-- 扁平化來源：把剪貼簿解析結果 (2D) 依「行優先、左到右」展開成一維
local function flatten_tsv_to_list(tbl)
  local list = {}
  for i = 1, #tbl do
    local row = tbl[i]
    for j = 1, #row do
      list[#list+1] = _trim(row[j] or "")
    end
  end
  return list
end

-- 依「行優先、左到右」取得目前選取的目標格（含所有欄；真正寫回只在 3/4/5 欄）
local function build_dst_list_from_selection(rows)
  local rim = build_row_index_map(rows)
  local dst = {}
  for key,_ in pairs(SEL.cells or {}) do
    local g, cstr = key:match("^(.-):(%d+)$")
    local col = tonumber(cstr)
    local ri = rim[g]
    if ri and col then
      dst[#dst+1] = { row_index = ri, col = col, row = rows[ri] }
    end
  end
  table.sort(dst, function(a,b)
    if a.row_index ~= b.row_index then return a.row_index < b.row_index end
    return a.col < b.col
  end)
  return dst
end



-- === Undo/Redo 選取保護（以 GUID 快照） ===
local function _snapshot_selected_item_guids()
  local list = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    list[#list+1] = g
  end
  return list
end

local function _restore_item_selection_by_guids(guids)
  if not guids or #guids == 0 then return end
  -- 先清空目前選取
  reaper.Main_OnCommand(40289, 0) -- Unselect all items
  -- 建索引表以加速比對
  local want = {}
  for _, g in ipairs(guids) do if g and g ~= "" then want[g] = true end end
  -- 逐一掃描專案 item，比對 GUID 後重選
  local total = reaper.CountMediaItems(0)
  for i = 0, total-1 do
    local it = reaper.GetMediaItem(0, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if want[g] then reaper.SetMediaItemSelected(it, true) end
  end
  reaper.UpdateArrange()
end




-- Bulk-commit（一次 Undo、最後再 UpdateArrange/Refresh）
local BULK = false
local function bulk_begin() BULK = true end
local function bulk_end(refresh_cb)
  BULK = false
  reaper.UpdateArrange()
  if type(refresh_cb) == "function" then refresh_cb() end
end


-- 清除目前選取到的「格子文字」（只在 Live 視圖；僅 3/4/5 欄可寫）
local function delete_selected_cells()
  if TABLE_SOURCE ~= "live" then return end
  if not SEL or not SEL.cells or next(SEL.cells) == nil then return end

  local rows = ROWS
  local rim  = build_row_index_map(rows)

  -- 以物件去重：Track / Take / Item
  local tr_set, tk_set, it_set = {}, {}, {}

  for key,_ in pairs(SEL.cells) do
    local g, cstr = key:match("^(.-):(%d+)$")
    local col = tonumber(cstr)
    local ri  = rim[g]
    if ri and col then
      local r = rows[ri]
      if col == 3 and r and r.__track then
        tr_set[r.__track] = true
      elseif col == 4 and r and r.__take then
        tk_set[r.__take] = true
      elseif col == 5 and r and r.__item then
        it_set[r.__item] = true
      end
    end
  end

  -- 沒有任何可寫欄被選到就不動作
  if next(tr_set) == nil and next(tk_set) == nil and next(it_set) == nil then return end

  reaper.Undo_BeginBlock2(0)

  -- 清 Track Name（空字串 = 還原為預設 Track 名顯示）
  for tr,_ in pairs(tr_set) do
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", true)
    -- 同步更新目前 rows 的顯示值
    for _, rr in ipairs(rows) do
      if rr.__track == tr then rr.track_name = "" end
    end
  end

  -- 清 Take Name（僅當下有 take；不自動建立 take）
  for tk,_ in pairs(tk_set) do
    reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", true)
  end
  -- 同步 rows
  for _, rr in ipairs(rows) do
    if rr.__take and tk_set[rr.__take] then rr.take_name = "" end
  end

  -- 清 Item Note
  for it,_ in pairs(it_set) do
    reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", true)
  end
  -- 同步 rows
  for _, rr in ipairs(rows) do
    if rr.__item and it_set[rr.__item] then rr.item_note = "" end
  end

  reaper.Undo_EndBlock2(0, "[Monitor] Clear selected cell text", -1)
  reaper.UpdateArrange()
  refresh_now()
end




local COL = { TRACK_NAME = 3, TAKE_NAME = 4, ITEM_NOTE = 5 } -- 以表頭順序為準（#、TrackIdx、Track Name、Take Name、Item Note、Source File...）

function _trim(s)
  s = tostring(s or "")
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function _commit_if_changed(label, oldv, newv, fn_apply)
  newv = _trim(newv or "")
  oldv = tostring(oldv or "")
  if newv == oldv then return false end
  if BULK then
    fn_apply(newv)
  else
    reaper.Undo_BeginBlock2(0)
    fn_apply(newv)
    reaper.Undo_EndBlock2(0, "[Monitor] "..label, -1)
    reaper.UpdateArrange()
  end
  return true
end


-- 寫回：Track / Take / Item Note
local function apply_track_name(tr, newname, rows)
  _commit_if_changed("Rename Track", select(2, reaper.GetTrackName(tr, "")), newname, function(v)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", v, true)
    -- 同一個 track 之所有列同步更新（依物件，而非名字）
    for _, rr in ipairs(rows or {}) do
      if rr.__track == tr then rr.track_name = v end
    end
  end)
end

local function apply_take_name(tk, newname, row)
  if not tk then return end
  _commit_if_changed("Rename Take", row.take_name, newname, function(v)
    reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", v, true)
    row.take_name = v
  end)
end

local function apply_item_note(it, newnote, row)
  _commit_if_changed("Edit Item Note", row.item_note, newnote, function(v)
    reaper.GetSetMediaItemInfo_String(it, "P_NOTES", v, true)
    row.item_note = v
  end)
end




-- 超薄轉接（保留相容性；也可以讓 table/export 都直接叫 FORMAT(r.start_time)）
local function format_time(val) return FORMAT(val) end

function refresh_now()
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
        muted = (cols[9] == "1" or cols[9] == "M"),
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
    "#","TrackIdx","TrackName","TakeName","ItemNote","Source File",
    "MetaTrackName","Channel#","Interleave","Mute","ColorHex","StartTime","EndTime"
  }, sep)

  -- rows
  for i, r in ipairs(rows or {}) do
    out[#out+1] = table.concat({
      esc(i),
      esc(r.track_idx),
      esc(r.track_name),
      esc(r.take_name),
      esc(r.item_note or ""), -- NEW (0.5.0)
      esc(r.file_name),
      esc(r.meta_trk_name),
      esc(r.channel_num or ""),
      esc(r.interleave or ""),
      esc(r.muted and "M" or ""),   -- 0.5.1: export M/blank
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
  local flags = TF('ImGui_TableFlags_Borders')
            | TF('ImGui_TableFlags_RowBg')
            | TF('ImGui_TableFlags_SizingFixedFit')
            | TF('ImGui_TableFlags_ScrollX')
            | TF('ImGui_TableFlags_Resizable')  if reaper.ImGui_BeginTable(ctx, "live_table", 13, flags, -FLT_MIN, height or 360) then
    reaper.ImGui_TableSetupColumn(ctx, "#", TF('ImGui_TableColumnFlags_WidthFixed'), 28)
    reaper.ImGui_TableSetupColumn(ctx, "TrkID", TF('ImGui_TableColumnFlags_WidthFixed'), 44)

    -- 可編輯欄：給足閱讀寬度，固定寬內自動換行
    reaper.ImGui_TableSetupColumn(ctx, "Track Name", TF('ImGui_TableColumnFlags_WidthFixed'), 140)
    reaper.ImGui_TableSetupColumn(ctx, "Take Name",  TF('ImGui_TableColumnFlags_WidthFixed'), 200)
    reaper.ImGui_TableSetupColumn(ctx, "Item Note",  TF('ImGui_TableColumnFlags_WidthFixed'), 320)

    -- 其他資訊欄
    reaper.ImGui_TableSetupColumn(ctx, "Source File",      TF('ImGui_TableColumnFlags_WidthFixed'), 220)
    reaper.ImGui_TableSetupColumn(ctx, "Meta Track Name",  TF('ImGui_TableColumnFlags_WidthFixed'), 160)
    reaper.ImGui_TableSetupColumn(ctx, "Chan#",       TF('ImGui_TableColumnFlags_WidthFixed'), 44)
    reaper.ImGui_TableSetupColumn(ctx, "Interleave",  TF('ImGui_TableColumnFlags_WidthFixed'), 60)

    local startHeader, endHeader = TFLib.headers(TIME_MODE, {pattern=CUSTOM_PATTERN})
    reaper.ImGui_TableSetupColumn(ctx, "Mute",   TF('ImGui_TableColumnFlags_WidthFixed'), 46)
    reaper.ImGui_TableSetupColumn(ctx, "Color",  TF('ImGui_TableColumnFlags_WidthFixed'), 96)
    reaper.ImGui_TableSetupColumn(ctx, startHeader, TF('ImGui_TableColumnFlags_WidthFixed'), 120)
    reaper.ImGui_TableSetupColumn(ctx, endHeader,   TF('ImGui_TableColumnFlags_WidthFixed'), 120)

    reaper.ImGui_TableHeadersRow(ctx)

        -- Build row-index map for selection math
    local row_index_map = build_row_index_map(rows)

    -- 點擊單一格的統一處理：單擊＝選取；Shift＝矩形；Cmd/Ctrl＝增減
    local function handle_cell_click(guid, col)
      local m = _mods()
      if m.shift and SEL.anchor then
        sel_rect_apply(rows, row_index_map, guid, col)
      elseif m.shortcut then
        -- 切換單格
        if not SEL.anchor then SEL.anchor = { guid = guid, col = col } end
        sel_toggle(guid, col)
      else
        -- 清空已選 → 設新錨點 → 選單格（避免把剛設的 anchor 清掉）
        sel_clear()
        SEL.anchor = { guid = guid, col = col }
        sel_add(guid, col)
      end
    end


    for i, r in ipairs(rows or {}) do
      reaper.ImGui_TableNextRow(ctx)
      reaper.ImGui_PushID(ctx, (r.__item_guid ~= "" and r.__item_guid) or tostring(i))    -- 0.6.1
      -- # (col 1)
      reaper.ImGui_TableNextColumn(ctx)
      local sel1 = sel_has(r.__item_guid, 1)
      reaper.ImGui_Selectable(ctx, tostring(i) .. "##c1", sel1)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 1) end

      -- TrkID (col 2)
      reaper.ImGui_TableNextColumn(ctx)
      local sel2 = sel_has(r.__item_guid, 2)
      reaper.ImGui_Selectable(ctx, tostring(r.track_idx or "") .. "##c2", sel2)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 2) end


        -- Track Name（click = select, double-click = edit）
        reaper.ImGui_TableNextColumn(ctx)
        local track_txt = tostring(r.track_name or "")
        local editing_trk = (EDIT and EDIT.row == r and EDIT.col == 3)
        local is_sel3 = sel_has(r.__item_guid, 3)

        if not editing_trk then
          reaper.ImGui_Selectable(ctx, (track_txt ~= "" and track_txt or " ") .. "##trk", is_sel3)
          if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 3) end
          if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            if TABLE_SOURCE == "live" then
              EDIT = { row = r, col = 3, buf = track_txt, want_focus = true }
            end
          end
        else

        -- 編輯模式：只畫 InputText，確保鍵盤焦點在這格
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        if EDIT.want_focus then
          reaper.ImGui_SetKeyboardFocusHere(ctx)
          EDIT.want_focus = false
        end
        local flags = reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_EnterReturnsTrue()
        local changed, newv = reaper.ImGui_InputText(ctx, "##trk", EDIT.buf, flags)
        if changed then EDIT.buf = newv end

        local submit = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
                      or reaper.ImGui_IsItemDeactivated(ctx)   -- 失焦也提交（可能沒改值）
        local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())

        if submit then
          if r.__track then apply_track_name(r.__track, EDIT.buf, rows) end
          EDIT = nil
        elseif cancel then
          EDIT = nil
        end
      end

      -- Take Name（允許沒有 active take 也能編輯）
      reaper.ImGui_TableNextColumn(ctx)
      local take_txt = tostring(r.take_name or "")
      local editing_take = (EDIT and EDIT.row == r and EDIT.col == 4)
      local is_sel4 = sel_has(r.__item_guid, 4)

      if not editing_take then
        reaper.ImGui_Selectable(ctx, (take_txt ~= "" and take_txt or " ") .. "##take", is_sel4)
        if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 4) end
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          if TABLE_SOURCE == "live" then
            EDIT = { row = r, col = 4, buf = take_txt, want_focus = true }
          end
        end
      else

        
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        if EDIT.want_focus then
          reaper.ImGui_SetKeyboardFocusHere(ctx)
          EDIT.want_focus = false
        end
        local flags = reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_EnterReturnsTrue()
        local changed, newv = reaper.ImGui_InputText(ctx, "##take", EDIT.buf, flags)
        if changed then EDIT.buf = newv end

        local submit = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
                      or reaper.ImGui_IsItemDeactivated(ctx)
        local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())

        if submit then
          apply_take_name(r.__take, EDIT.buf, r)
          EDIT = nil
        elseif cancel then
          EDIT = nil
        end
      end



      -- Item Note
      reaper.ImGui_TableNextColumn(ctx)
      local note_txt = tostring(r.item_note or "")
      local editing_note = (EDIT and EDIT.row == r and EDIT.col == 5)
      local is_sel5 = sel_has(r.__item_guid, 5)

      if not editing_note then
        reaper.ImGui_Selectable(ctx, (note_txt ~= "" and note_txt or " ") .. "##note", is_sel5)
        if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 5) end
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
          if TABLE_SOURCE == "live" then
            EDIT = { row = r, col = 5, buf = note_txt, want_focus = true }
          end
        end
      else
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        if EDIT.want_focus then
          reaper.ImGui_SetKeyboardFocusHere(ctx)
          EDIT.want_focus = false
        end
        local flags = reaper.ImGui_InputTextFlags_AutoSelectAll() | reaper.ImGui_InputTextFlags_EnterReturnsTrue()
        local changed, newv = reaper.ImGui_InputText(ctx, "##note", EDIT.buf, flags)
        if changed then EDIT.buf = newv end

        local submit = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter())
                      or reaper.ImGui_IsItemDeactivated(ctx)
        local cancel = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape())

        if submit then
          apply_item_note(r.__item, EDIT.buf, r)
          EDIT = nil
        elseif cancel then
          EDIT = nil
        end
      end

      -- 6 Source File
      reaper.ImGui_TableNextColumn(ctx)
      local t6 = tostring(r.file_name or ""); local s6 = sel_has(r.__item_guid, 6)
      reaper.ImGui_Selectable(ctx, (t6 ~= "" and t6 or " ") .. "##c6", s6)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 6) end

      -- 7 Meta Track Name
      reaper.ImGui_TableNextColumn(ctx)
      local t7 = tostring(r.meta_trk_name or ""); local s7 = sel_has(r.__item_guid, 7)
      reaper.ImGui_Selectable(ctx, (t7 ~= "" and t7 or " ") .. "##c7", s7)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 7) end

      -- 8 Chan#
      reaper.ImGui_TableNextColumn(ctx)
      local t8 = tostring(r.channel_num or ""); local s8 = sel_has(r.__item_guid, 8)
      reaper.ImGui_Selectable(ctx, (t8 ~= "" and t8 or " ") .. "##c8", s8)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 8) end

      -- 9 Interleave
      reaper.ImGui_TableNextColumn(ctx)
      local t9 = tostring(r.interleave or ""); local s9 = sel_has(r.__item_guid, 9)
      reaper.ImGui_Selectable(ctx, (t9 ~= "" and t9 or " ") .. "##c9", s9)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 9) end

      -- 10 Mute
      reaper.ImGui_TableNextColumn(ctx)
      local t10 = r.muted and "M" or ""; local s10 = sel_has(r.__item_guid, 10)
      reaper.ImGui_Selectable(ctx, (t10 ~= "" and t10 or " ") .. "##c10", s10)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 10) end

      -- 11 Color（顯示色塊 + 以 hex 為可選文字）
      reaper.ImGui_TableNextColumn(ctx)
      if r.color_rgb and r.color_rgb[1] then
        local rr, gg, bb = r.color_rgb[1]/255, r.color_rgb[2]/255, r.color_rgb[3]/255
        local col = reaper.ImGui_ColorConvertDouble4ToU32(rr, gg, bb, 1.0)
        reaper.ImGui_TextColored(ctx, col, "■")
        reaper.ImGui_SameLine(ctx)
      end
      local t11 = tostring(r.color_hex or ""); local s11 = sel_has(r.__item_guid, 11)
      reaper.ImGui_Selectable(ctx, (t11 ~= "" and t11 or " ") .. "##c11", s11)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 11) end

      -- 12 Start
      reaper.ImGui_TableNextColumn(ctx)
      local t12 = format_time(r.start_time); local s12 = sel_has(r.__item_guid, 12)
      reaper.ImGui_Selectable(ctx, (t12 ~= "" and t12 or " ") .. "##c12", s12)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 12) end

      -- 13 End
      reaper.ImGui_TableNextColumn(ctx)
      local t13 = format_time(r.end_time); local s13 = sel_has(r.__item_guid, 13)
      reaper.ImGui_Selectable(ctx, (t13 ~= "" and t13 or " ") .. "##c13", s13)
      if reaper.ImGui_IsItemClicked(ctx) then handle_cell_click(r.__item_guid, 13) end

      reaper.ImGui_PopID(ctx)   -- 0.6.1

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
  if AUTO and not (EDIT and EDIT.col) then refresh_now() end


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

  -- Clipboard shortcuts (when NOT in InputText editing)
  if not (EDIT and EDIT.col) then
    -- Copy selection (any view)
    if shortcut_pressed(reaper.ImGui_Key_C()) then
      local rows = rows_to_show
      local rim  = build_row_index_map(rows)
      copy_selection(rows, rim)
    end

    -- Paste（Live only，Excel 風規則）
    if TABLE_SOURCE == "live" and shortcut_pressed(reaper.ImGui_Key_V()) then
      -- 檢查是否有選取
      if not SEL or not SEL.cells or next(SEL.cells) == nil then
        reaper.ShowMessageBox("沒有選取任何格子。請先選取要貼上的目標格。", "貼上", 0)
        goto PASTE_END
      end

      -- 解析剪貼簿 → 扁平化來源
      local clip = reaper.ImGui_GetClipboardText(ctx) or ""
      local tbl  = parse_clipboard_table(clip)
      local src  = flatten_tsv_to_list(tbl)
      if #src == 0 then goto PASTE_END end
      local src_h, src_w = src_shape_dims(tbl)

      -- 目標格（行優先、左到右），包含所有被選欄；實際寫回僅 3/4/5
      local rows = ROWS
      local dst  = build_dst_list_from_selection(rows)
      if #dst == 0 then goto PASTE_END end

      -- 寫入工具：只在 3/4/5 欄動作
      local tracks_renamed, takes_named, notes_set, takes_created, skipped = 0,0,0,0,0
      local function apply_cell(d, val)
        local r, col = d.row, d.col
        if not r then skipped = skipped + 1; return end
        if col == 3 then
          if r.__track and val ~= r.track_name then
            reaper.GetSetMediaTrackInfo_String(r.__track, "P_NAME", val, true)
            r.track_name = val; tracks_renamed = tracks_renamed + 1
          end
        elseif col == 4 then
          local tk = r.__take
          if not tk then
            tk = reaper.AddTakeToMediaItem(r.__item); r.__take = tk; takes_created = takes_created + 1
          end
          if tk and val ~= r.take_name then
            reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", val, true)
            r.take_name = val; takes_named = takes_named + 1
          end
        elseif col == 5 then
          if val ~= r.item_note then
            reaper.GetSetMediaItemInfo_String(r.__item, "P_NOTES", val, true)
            r.item_note = val; notes_set = notes_set + 1
          end
        else
          -- 非可寫欄：接受但不寫
          skipped = skipped + 1
        end
      end

      -- 一次 Undo：單值填滿；多值截斷；若只選 1 格則依來源形狀展開；單列來源可往下填滿
      reaper.Undo_BeginBlock2(0)

      if #src == 1 then
        -- 單值填滿（跨欄位、非矩形都可）
        local v = src[1]
        for i=1, #dst do apply_cell(dst[i], v) end

      elseif #dst == 1 then
        -- 來源多值、目標只選一格：依來源 2D 形狀向右、向下展開（0.6.10）
        local anchor = dst[1]  -- 單一目標格描述（含 row_index/col）
        local dst2 = build_dst_by_anchor_and_shape(ROWS, anchor, src_h, src_w)
        local n = math.min(#src, #dst2)
        for k = 1, n do apply_cell(dst2[k], src[k]) end

      elseif src_h == 1 then
        -- 0.6.11：來源是「單一列、跨多欄」，目標選了多格（通常為多列相同欄）→ 往下填滿
        -- 作法：把目標依 row 分組，每一列按欄順序貼上「來源該列的前 src_w 個值」（不循環）
        local by_row = {}
        for _, d in ipairs(dst) do
          local t = by_row[d.row_index]; if not t then t = {}; by_row[d.row_index] = t end
          t[#t+1] = d
        end
        for _, cells in pairs(by_row) do
          table.sort(cells, function(a,b) return a.col < b.col end)
          local m = math.min(#cells, src_w)
          for j = 1, m do
            local v = _trim((tbl[1] and tbl[1][j]) or "")
            apply_cell(cells[j], v)
          end
        end

      else
        -- 多對多：依 row-major 對應到 min(#src, #dst)（0.6.9）
        local n = math.min(#src, #dst)
        for k=1, n do apply_cell(dst[k], src[k]) end
      end

      reaper.Undo_EndBlock2(0, "[Monitor] Paste", -1)

      reaper.UpdateArrange()
      refresh_now()

      --（可選）你若有狀態列，可顯示摘要；沒有就略過
      -- status(string.format("Paste: trk=%d, take=%d (+%d), note=%d, skipped=%d",
      --   tracks_renamed, takes_named, takes_created, notes_set, skipped))

      ::PASTE_END::
    end

    -- Delete（Live only）：Delete 或 Backspace 皆可
    if TABLE_SOURCE == "live" then
      local del_pressed = reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete(), false)
                       or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace(), false)
      if del_pressed then
        delete_selected_cells()
      end
    end

    -- Undo / Redo（專案層級；保護 item 選取）
    do
      local m = _mods()
      if m.shortcut then
        -- 先快照目前選取（以 GUID）
        local sel_snapshot = _snapshot_selected_item_guids()

        -- 先判斷 Redo：Cmd/Ctrl+Shift+Z 或 Cmd/Ctrl+Y
        local redo_combo = (m.shift and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z(), false))
                        or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Y(), false)
        if redo_combo then
          reaper.Undo_DoRedo2(0)
          _restore_item_selection_by_guids(sel_snapshot)
          refresh_now()
        elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Z(), false) then
          -- Undo：Cmd/Ctrl+Z
          reaper.Undo_DoUndo2(0)
          _restore_item_selection_by_guids(sel_snapshot)
          refresh_now()
        end
      end
    end
  end

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
