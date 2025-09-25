--[[
@description ReaImGui - Vertical Reorder and Sort (items)
@version 250925_1038 change UI namming display
@author hsuanice
@about
  Provides three vertical re-arrangement modes for selected items (stacked UI):

  • Reorder (fill upward)
    - Keeps items at their original timeline position.
    - Packs items upward into available selected tracks, avoiding gaps.

  • Sort Vertically
    - Groups items by near-identical start time.
    - Within each time cluster, re-orders items top-to-bottom by:
        Take Name / File Name / Metadata (Track Name or Channel Number).
    - Ascending / Descending toggle.

  • Metadata modes
    - Copy to Sort: duplicates selected items to NEW tracks grouped by metadata.
    - Sort in Place: reorders items on their existing tracks based on metadata
      (Track Name or Channel Number). No new tracks are created, no names changed.

  Notes:
    - Based on design concepts and iterative testing by hsuanice.
    - Script generated and refined with ChatGPT.





@changelog
  v250925_1038 change UI namming display
  v250921_1819
    - Preferences are now persisted via ExtState:
      • Sort key (Take/File/Metadata) and Asc/Desc.
      • Metadata sort key (Track Name / Channel#).
      • Copy-to-Sort naming (Track Name / Channel#).
      • Copy-to-Sort group order (Track Name / Channel#).
      • Copy-to-Sort “Append Track Name” option.
    - All changes in the UI are saved immediately with save_pref(),
      and reloaded at startup with load_pref().
    - Result: user selections are remembered across script restarts
      and REAPER sessions, no need to reselect every time.

  v250921_1732
    - Copy-to-Sort: decoupled "TCP naming (grouping)" from "Group order".
      • You can name new tracks by Track Name while ordering groups by Channel#, or vice versa.
      • When naming by Channel#, the option is now "Append Track Name to TCP label".
        Enabling it no longer just appends the most-frequent Track Name —
        it **splits each Channel# into separate tracks by Track Name**,
        e.g.:
          Ch 09 — BASS
          Ch 09 — PRODUCER
    - UI: Added separate radio groups for TCP naming and Group order in Metadata section.
    - Removed legacy two-arg signature; all callsites updated to the new 4-arg form.

  v0.5.6.0
    - Copy-to-Sort: decoupled "TCP naming (grouping)" from "Group order".
      • You can name new tracks by Track Name while ordering groups by Channel#, or vice versa.
      • Optional: append the most-frequent Track Name to Channel#-named TCP labels.
    - UI: Added separate radio groups for TCP naming and Group order in Metadata section.
    - Removed legacy two-arg signature; all callsites updated to the new 4-arg form.

  v0.5.5.2
    - UI refined
  v0.5.5.1
    - UX: Press ESC to close the Reorder window (modal summary still closes first).
  v0.5.5
    - Refactor: Decoupled auto-capture from metadata payloads.
      Reorder now issues handshake requests (req_before/req_after) and waits for ack,
      leaving all scanning to the Monitor. No TSV payload in Reorder anymore.
  v0.5.4.4
    - Copy to Sort: Added result summary (tracks created, items copied) and overlap warning.
    - Summary popup now shows detailed counts right after the action completes.
  v0.5.4.3 (2025-09-03)
    - Fix: Restored missing helper copy_item_to_track used by Copy-to-Sort.
      Copies item properties (pos/len/mute/vol/fades/color) and the active take
      (source, start offset, playrate, pitch, name).
  v0.5.4.2 (2025-09-03)
    - Fix: Copy-to-Sort “invalid order function for sorting”.
      Replaced comparator with a stable string-key comparator (guards nil/types and enforces strict weak ordering).

  v0.5.4.1 (2025-09-03)
    - Fix: Copy-to-Sort crash (“attempt to call a nil value 'snapshot_rows_tsv'”).
      Added forward declaration and bound the function definition so callers can invoke it reliably.
    - Fix: Metadata preview stability.
      Introduced PREVIEW_PAIRS / build_preview_pairs() and UI guards (generate via “Scan first 10 items”)
      to prevent nil indexing before data exists.
    - Cleanup: Removed stray duplicate emit_capture() and kept the payload-capable version used by
      run_engine() / run_copy_to_new_tracks().
    - Misc: Small refactors and comments; no functional changes to core reordering/sorting.

  v0.5.4 (2025-09-03)
    - Feature: Opt-in Monitor auto-capture.
      • Added “Monitor auto-capture” checkbox; preference is persisted via ExtState.
    - Reliable Monitor auto-capture with BEFORE/AFTER payloads.
      • Emits separate ExtState keys: capture_before / capture_after.
      • Attaches snapshot_before / snapshot_after TSV payloads so the Monitor
        can restore the exact selection at the moment of action (no race).
    - Preference & UI:
      • Added “Monitor auto-capture” checkbox (persisted via ExtState).
      • Emissions are guarded by CAPTURE_ON; no Monitor dependency.
    - Integration points:
      • Wraps run_engine() and run_copy_to_new_tracks() with BEFORE/AFTER emits.
    - Fixes:
      • Removed duplicate emit_capture() implementation.
      • Sanitized TSV payload for newlines/tabs to avoid parsing issues.
  v0.5.3 (2025-09-03)
    - Feature: Auto-capture hooks for Monitor integration.
      Emits an ExtState signal before/after operations so the Monitor script can snapshot automatically.
        • Namespace: "hsuanice_ReorderSort_Signal"
        • Key:       "capture"
        • Values:    "before:<timestamp>", "after:<timestamp>"
      Covered actions: Reorder, Sort vertically, Sort-in-place (if present), and Copy-to-Sort (new tracks).
    - Implementation: Added helper emit_capture(tag) and invoked it at the start ("before") and end ("after")
      of the execution paths (run_engine / run_copy_to_new_tracks). Signals are non-persistent (SetExtState …, false).
    - Safety: No dependency on the Monitor; if it’s not running the signals are simply ignored.

  v0.5.2 (2025-09-02)
  - Performance: Throttled selection polling to reduce per-frame rescans
    while the window is open. Replaced unconditional calls with a
    conditional helper (maybe_compute_selection).
  - Logic: Recompute the selection snapshot only when
      • the number of selected items or tracks changes, or
      • the throttle timer expires (default 0.12s).
  - UX: No behavior changes to actions. Main UI stays responsive;
    selection counts may update with a tiny (<120 ms) delay under heavy edits.
  - Tunable: Exposed SCAN_INTERVAL constant to balance CPU vs responsiveness.

  v0.5.1 (2025-09-02)
    - UX: Keep the main window open after actions.
    - New: Result Summary popup (ESC to close).
      • After any action (Reorder / Sort / Sort in Place / Copy to Sort),
        a modal popup shows “Items / Moved / Skipped”.
      • Close via the Close button or ESC; the main UI stays active.  
  v0.5.0 (2025-09-02)
    - New: Added "Sort in Place" for Metadata mode.
      • Works directly on existing tracks, no renaming or new tracks.
      • Sort key selectable: Track Name or Channel Number.
      • Ascending/Descending toggle supported.
    - "Copy to Sort" behavior unchanged.
    - UI: Metadata section now has two buttons:
        • Sort in Place
        • Copy to Sort
    - This allows users to sort selected items across existing tracks
      or duplicate them to new metadata-grouped tracks.
  v0.4.0 (2025-09-01)
    - Switch all metadata reading to 'hsuanice Metadata Read' (>= 0.2.0):
      * iXML TRACK_LIST preferred; fallback to BWF Description sTRK#=Name (EdiLoad split).
      * Interleave from take channel mode; name/channel via Library tokens $trk/${chnum}.
    - Removed usage of legacy local parsers; UI/behavior unchanged aside from robustness.

  v0.3.6
    - UI: Moved the main action button directly under
          "Sort by Metadata: Track Name / Channel Number".
          The Preview list now comes after the button so it never pushes
          the button off-screen.
  v0.3.5a
    - Fix: "invalid order function for sorting" when using Copy to Sort.
           Now uses stable string-based order keys for both Track Name
           and Channel Number modes, preventing type/nil comparison errors.
    - Behavior unchanged: 
        • Track Name mode → new track named by metadata Track Name.
        • Channel Number mode → new track named "Ch 01/02/…".
    - Stability: Copy-to-Sort now guaranteed consistent ordering regardless
      of mixed metadata types or missing values.
  v0.3.5
    - UX: Removed duplicated "Copy to New Tracks" section.
    - UX: When Sort key = Metadata, the main action button becomes "Copy to Sort"
          and performs copy → new tracks using the chosen Metadata sub-key
          (Track Name / Channel Number) and Asc/Desc.
    - Copy naming:
        • Track Name mode → new track named by metadata Track Name.
        • Channel Number mode → new track named "Ch 01/02/…".
  v0.3.4 Vertical UI
    - UI: Window renamed to "Vertical Reorder and Sort".
    - UI: Layout changed to vertical stack:
          Reorder → Sort Vertically → Sort by Metadata → Copy to New Tracks.
    - New: Sort Vertically now supports Metadata key (Track Name / Channel Number).
    - Preview: simplified to two-column mapping "Channel Number ↔ Track Name".
    - Minor: cleaned labels for clarity.

  v0.3.3
    - New: Option "Order new tracks alphabetically (ignore channel #)" in Copy-to-New-Tracks.
           Uses natural sort so names with numbers order intuitively (CHEN 2.0 < CHEN 10.0).
    - Tweak: Name sort in Copy-to-New-Tracks now uses natural string key.

  v0.3.2
    - Fix: "invalid order function for sorting" in Sort Vertically (Take/File).
           Comparator replaced with stable key-based ordering.
  v0.3.1
    - Fix: Always call ImGui_End() to prevent "Missing End()" error.
    - Added Copy-to-New-Tracks-by-Metadata and metadata parsing improvements.
]]

-- ===== Integrate with hsuanice Metadata Read (>= 0.2.0) =====
local META = dofile(
  reaper.GetResourcePath() ..
  "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua"
)
assert(META and (META.VERSION or "0") >= "0.2.0",
       "Please update 'hsuanice Metadata Read' to >= 0.2.0")



---------------------------------------
-- 依賴檢查
---------------------------------------
if not reaper or not reaper.ImGui_CreateContext then
  reaper.MB("ReaImGui is required (install via ReaPack).","Missing dependency",0)
  return
end

---------------------------------------
-- ImGui
---------------------------------------
local ctx = reaper.ImGui_CreateContext('Vertical Reorder and Sort')
local LIBVER = (META and META.VERSION) and ('  |  Metadata Read v'..tostring(META.VERSION)) or ''
local FONT = reaper.ImGui_CreateFont('sans-serif', 14); reaper.ImGui_Attach(ctx, FONT)
local function esc_pressed() return reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) end

---------------------------------------
-- 小工具
---------------------------------------
local function item_start(it) return reaper.GetMediaItemInfo_Value(it,"D_POSITION") end
local function item_len(it)   return reaper.GetMediaItemInfo_Value(it,"D_LENGTH")   end
local function item_track(it) return reaper.GetMediaItemTrack(it) end
local function is_item_locked(it) return (reaper.GetMediaItemInfo_Value(it,"C_LOCK") or 0) & 1 == 1 end
local function track_index(tr) return math.floor(reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or 0) end
local function set_track_name(tr, name) reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", tostring(name or ""), true) end

local function take_of(it) local tk=it and reaper.GetActiveTake(it); if tk and reaper.ValidatePtr2(0,tk,"MediaItem_Take*") then return tk end end
local function source_of_take(tk) return tk and reaper.GetMediaItemTake_Source(tk) or nil end
local function src_path(src) local ok,p=reaper.GetMediaSourceFileName(src,""); return ok and (p or "") or (p or "") end
local function path_basename(p) p=tostring(p or ""); return p:match("([^/\\]+)$") or p end




-- === Cross-script signal for Monitor auto-capture ===
local SIG_NS = "hsuanice_ReorderSort_Signal"

local function request_capture(tag, timeout_sec)
  if not CAPTURE_ON then return end
  local req_key = (tag == "before") and "req_before" or "req_after"
  local ack_key = (tag == "before") and "ack_before" or "ack_after"
  local token = string.format("%.6f", reaper.time_precise())

  -- 清掉上一筆 ACK，送出請求
  reaper.DeleteExtState(SIG_NS, ack_key, true)
  reaper.SetExtState(SIG_NS, req_key, token, false)

  -- 等待 Monitor 回 ACK（最長 0.5 秒）
  local deadline = reaper.time_precise() + (timeout_sec or 0.5)
  while reaper.time_precise() < deadline do
    if reaper.GetExtState(SIG_NS, ack_key) == token then
      reaper.DeleteExtState(SIG_NS, ack_key, true)
      return true
    end
  end
  return false  -- 超時也放行，不阻塞工作流
end

-- === Persist user preferences ===
local PREF_NS = "hsuanice_ReorderSort_Prefs"

local function save_pref(key, val)
  reaper.SetExtState(PREF_NS, key, tostring(val or ""), true)
end
local function load_pref(key, default)
  local v = reaper.GetExtState(PREF_NS, key)
  if v == "" then return default end
  if v == "true" then return true
  elseif v == "false" then return false
  else
    local num = tonumber(v)
    return num or v
  end
end

-- === Monitor auto-capture preference ===
local CAPTURE_ON = (reaper.GetExtState(SIG_NS, "enable") == "1")

local function set_capture_enabled(on)
  CAPTURE_ON = not not on
  -- 持久化，重開 REAPER 仍保留
  reaper.SetExtState(SIG_NS, "enable", CAPTURE_ON and "1" or "0", true)
end




-- 記憶使用者偏好（你現有的 CAPTURE_ON / set_capture_enabled 保留）
-- ...


-- 複製單一 item 到指定軌道（保留位置/長度/靜音/顏色/音量/淡入淡出；複製「現用 take」的來源與參數）
local function copy_item_to_track(src_it, dst_tr)
  if not (src_it and dst_tr) then return nil end
  if not reaper.ValidatePtr2(0, src_it, "MediaItem*") then return nil end
  if not reaper.ValidatePtr2(0, dst_tr, "MediaTrack*") then return nil end

  -- Item 屬性
  local pos   = reaper.GetMediaItemInfo_Value(src_it, "D_POSITION") or 0
  local len   = reaper.GetMediaItemInfo_Value(src_it, "D_LENGTH")   or 0
  local mute  = reaper.GetMediaItemInfo_Value(src_it, "B_MUTE")     or 0
  local vol   = reaper.GetMediaItemInfo_Value(src_it, "D_VOL")      or 1
  local so    = reaper.GetMediaItemInfo_Value(src_it, "D_SNAPOFFSET") or 0
  local fi    = reaper.GetMediaItemInfo_Value(src_it, "D_FADEINLEN")  or 0
  local fo    = reaper.GetMediaItemInfo_Value(src_it, "D_FADEOUTLEN") or 0
  local lock  = reaper.GetMediaItemInfo_Value(src_it, "C_LOCK") or 0
  local color = reaper.GetDisplayedMediaItemColor(src_it) or 0

  -- 建立新 item
  local it = reaper.AddMediaItemToTrack(dst_tr)
  reaper.SetMediaItemInfo_Value(it, "D_POSITION", pos)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",   len)
  reaper.SetMediaItemInfo_Value(it, "B_MUTE",     mute)
  reaper.SetMediaItemInfo_Value(it, "D_VOL",      vol)
  reaper.SetMediaItemInfo_Value(it, "D_SNAPOFFSET", so)
  reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN",  fi)
  reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", fo)
  reaper.SetMediaItemInfo_Value(it, "C_LOCK",     lock)
  if color ~= 0 then
    -- I_CUSTOMCOLOR 要帶「啟用」bit；GetDisplayedMediaItemColor 已經是 native 值
    reaper.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", color | 0x1000000)
  end

  -- 複製現用 take
  local src_tk = reaper.GetActiveTake(src_it)
  if src_tk then
    local new_tk = reaper.AddTakeToMediaItem(it)
    local src = reaper.GetMediaItemTake_Source(src_tk)
    if reaper.SetMediaItemTake_Source then
      reaper.SetMediaItemTake_Source(new_tk, src)
    end
    -- take 參數
    local soffs   = reaper.GetMediaItemTakeInfo_Value(src_tk, "D_STARTOFFS") or 0
    local rate    = reaper.GetMediaItemTakeInfo_Value(src_tk, "D_PLAYRATE")  or 1
    local pitch   = reaper.GetMediaItemTakeInfo_Value(src_tk, "D_PITCH")     or 0
    reaper.SetMediaItemTakeInfo_Value(new_tk, "D_STARTOFFS", soffs)
    reaper.SetMediaItemTakeInfo_Value(new_tk, "D_PLAYRATE",  rate)
    reaper.SetMediaItemTakeInfo_Value(new_tk, "D_PITCH",     pitch)
    -- take 名稱
    local _, tkn = reaper.GetSetMediaItemTakeInfo_String(src_tk, "P_NAME", "", false)
    if tkn and tkn ~= "" then
      reaper.GetSetMediaItemTakeInfo_String(new_tk, "P_NAME", tkn, true)
    end
    reaper.SetActiveTake(new_tk)
  end

  reaper.UpdateItemInProject(it)
  return it
end


---------------------------------------
-- 選取集合
---------------------------------------
local function get_selected_items()
  local t, n = {}, reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do t[#t+1] = reaper.GetSelectedMediaItem(0,i) end
  table.sort(t, function(a,b) return item_start(a) < item_start(b) end)
  return t
end

local function get_selected_tracks_set()
  local set, order = {}, {}
  local n = reaper.CountSelectedTracks(0)
  for i=0,n-1 do local tr = reaper.GetSelectedTrack(0,i); set[tr]=true; order[#order+1]=tr end
  table.sort(order, function(a,b) return track_index(a) < track_index(b) end)
  return set, order
end

local function unique_tracks_from_items(items)
  local set, order = {}, {}
  for _,it in ipairs(items) do local tr=item_track(it); if tr and not set[tr] then set[tr]=true; order[#order+1]=tr end end
  table.sort(order, function(a,b) return track_index(a) < track_index(b) end)
  return set, order
end

---------------------------------------
-- 佔用資訊（避免重疊）
---------------------------------------
local function build_initial_occupancy(tracks, selected_set)
  local occ = {}
  for _, tr in ipairs(tracks) do
    local list, cnt = {}, reaper.CountTrackMediaItems(tr)
    for i=0,cnt-1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      if not selected_set[it] then
        local s = item_start(it); list[#list+1] = { s=s, e=s+item_len(it) }
      end
    end
    occ[tr] = list
  end
  return occ
end

local function interval_overlaps(a_s,a_e,b_s,b_e) return (a_e>b_s) and (b_e>a_s) end
local function track_has_overlap(occ_list, s,e)
  for i=1,#occ_list do local seg=occ_list[i]; if interval_overlaps(s,e, seg.s,seg.e) then return true end end
  return false
end
local function add_interval(occ_list, s,e) occ_list[#occ_list+1] = { s=s, e=e } end

---------------------------------------
-- Sort：同列分群
---------------------------------------
local TIME_TOL = 0.005 -- 秒；欄位容差
local function build_time_clusters(items)
  local sorted = { table.unpack(items) }
  table.sort(sorted, function(a,b)
    local sa,sb = item_start(a), item_start(b)
    if math.abs(sa - sb) > TIME_TOL then return sa < sb end
    local ta,tb = track_index(item_track(a)), track_index(item_track(b))
    if ta ~= tb then return ta < tb end
    return tostring(a) < tostring(b)
  end)
  local clusters, cur, last_s = {}, {}, nil
  for _, it in ipairs(sorted) do
    local s = item_start(it)
    if (not last_s) or (math.abs(s - last_s) <= TIME_TOL) then
      cur[#cur+1] = it; last_s = last_s or s
    else
      clusters[#clusters+1] = cur; cur = { it }; last_s = s
    end
  end
  if #cur > 0 then clusters[#clusters+1] = cur end
  return clusters
end

---------------------------------------
-- Sort keys（Take / File / Metadata）
---------------------------------------
local function key_take_name(it)
  local tk = take_of(it); if not tk then return "" end
  local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return nm or ""
end
local function key_file_name(it)
  local tk = take_of(it); local src = source_of_take(tk)
  return path_basename(src_path(src))
end

-- 以穩定鍵值排序：把 (key, trackIndex, startTime, originalIndex) 組成單一字串鍵比較
local function sort_cluster(cluster, keyfn, asc)
  local recs = {}
  for i, it in ipairs(cluster) do
    local k  = tostring(keyfn(it) or ""):lower()
    local tr = item_track(it)
    local ti = tr and track_index(tr) or 2147483647
    local st = item_start(it) or 0
    local ord = table.concat({
      k,
      string.format("%09d", ti),
      string.format("%015.6f", st),
      string.format("%09d", i)
    }, "|")
    recs[#recs+1] = { it = it, ord = ord }
  end
  if asc then table.sort(recs, function(a,b) return a.ord < b.ord end)
  else       table.sort(recs, function(a,b) return a.ord > b.ord end) end
  for i, r in ipairs(recs) do cluster[i] = r.it end
end

---------------------------------------
-- 計畫：Reorder / Sort
---------------------------------------
local function plan_reorder_moves(items, tracks, occ)
  local sorted = { table.unpack(items) }
  table.sort(sorted, function(a,b)
    local sa,sb = item_start(a), item_start(b)
    if math.abs(sa - sb) > TIME_TOL then return sa < sb end
    return track_index(item_track(a)) < track_index(item_track(b))
  end)
  local pos_in = {}; for i,tr in ipairs(tracks) do pos_in[tr]=i end
  local moves = {}
  for _, it in ipairs(sorted) do
    if not is_item_locked(it) then
      local s = item_start(it); local e = s + item_len(it)
      local cur_tr = item_track(it); local cur_pos = pos_in[cur_tr] or #tracks
      local target = cur_tr
      for i=1, cur_pos do
        local tr = tracks[i]
        if not track_has_overlap(occ[tr], s, e) then target = tr; break end
      end
      if target ~= cur_tr then
        moves[#moves+1] = { item=it, to=target, s=s, e=e }
        add_interval(occ[target], s, e)
      else
        add_interval(occ[cur_tr], s, e)
      end
    end
  end
  return moves
end

local function plan_sort_moves(items, tracks, occ, keyfn, asc)
  local moves, clusters = {}, build_time_clusters(items)
  for _, cluster in ipairs(clusters) do
    sort_cluster(cluster, keyfn, asc)
    for _, it in ipairs(cluster) do
      if not is_item_locked(it) then
        local s = item_start(it); local e = s + item_len(it)
        local placed = nil
        for _, tr in ipairs(tracks) do
          if not track_has_overlap(occ[tr], s, e) then placed = tr; break end
        end
        local cur_tr = item_track(it)
        if placed and placed ~= cur_tr then
          moves[#moves+1] = { item=it, to=placed, s=s, e=e }
          add_interval(occ[placed], s, e)
        else
          add_interval(occ[cur_tr], s, e)
        end
      end
    end
  end
  return moves
end

local function apply_moves(moves)
  for _,m in ipairs(moves) do reaper.MoveMediaItemToTrack(m.item, m.to) end
end

---------------------------------------
-- 讀取 Metadata：BWF/iXML + take/name/note
---------------------------------------
local function get_meta(src, key)
  if not src or not reaper.GetMediaFileMetadata then return nil end
  local ok, val = reaper.GetMediaFileMetadata(src, key)
  if ok == 1 and val ~= "" then return val end
  return nil
end

local function normalize_key(s)
  s = tostring(s or ""):gsub("^%s+",""):gsub("%s+$","")
  s = s:gsub("^%$", ""):gsub("^%${(.-)}$", "%1")
  return string.lower(s)
end

local function parse_description_pairs(desc_text, out_tbl)
  for line in (tostring(desc_text or "") .. "\n"):gmatch("(.-)\n") do
    local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if k and v and k ~= "" then
      out_tbl[k] = v; out_tbl[string.lower(k)] = v
      if k:sub(1,1) == 's' and #k > 1 then
        local base = k:sub(2); out_tbl[base] = v; out_tbl[string.lower(base)] = v
      end
    end
  end
end

local function collect_ixml_tracklist(src, t)
  local ok, count = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK_COUNT")
  if ok == 1 then
    local n = tonumber(count) or 0
    for i=1,n do
      local suffix = (i>1) and (":"..i) or ""
      local _, ch = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:CHANNEL_INDEX"..suffix)
      local _, nm = reaper.GetMediaFileMetadata(src, "IXML:TRACK_LIST:TRACK:NAME"..suffix)
      local ci = tonumber(ch or "")
      if ci and ci>=1 then
        if nm and nm~="" then t["trk"..ci] = nm; t["TRK"..ci] = nm end
        t["ch"..ci] = ci
      end
    end
  end
end

local function collect_fields(it)
  local t = {}
  local tk = take_of(it)
  local src = source_of_take(tk)
  if tk then
    local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
    t.curtake = nm or ""
  end
  local _, note = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
  t.curnote = note or ""

  local st = src and (reaper.GetMediaSourceType(src, "") or ""):upper() or ""
  local can = st:find("WAVE") or st:find("AIFF") or st:find("WAVE64")
  if can then
    local d = get_meta(src, "BWF:Description"); if d then t.Description=d; t.description=d; parse_description_pairs(d,t) end
    for _,k in ipairs({"BWF:OriginationDate","BWF:OriginationTime","IXML:PROJECT","IXML:SCENE","IXML:TAKE","IXML:TAPE","IXML:SPEED"}) do
      local v = get_meta(src,k); if v then local s=k:gsub("BWF:",""):gsub("IXML:",""); t[s]=v; t[string.lower(s)]=v end
    end
    collect_ixml_tracklist(src, t)
    local v = get_meta(src, "IXML:TRKALL"); if v then t.TRKALL=v; t.trkall=v end
    local fn = path_basename(src_path(src)); t.filename = fn; t.FILENAME = fn
    t.srcfile = fn; t.sfilename = fn
  end
  return t
end




-- 解析：從檔名推 channel；優先用 TRK{ch} 取 name；最後才用 $trk 的 "Name (ch N)"
local function extract_name_and_chan(fields, name_key)
  local k = normalize_key(name_key)
  local name, ch = "", nil

  local srcfile = fields.srcfile or fields.FILENAME or fields.filename or fields.sfilename
  if srcfile and srcfile ~= "" then
    ch = tonumber(tostring(srcfile):match("_AAP_(%d+)")) or
         tonumber(tostring(srcfile):match("[_%-]t(%d+)[_%-]"))
  end

  if ch and (fields["trk"..ch] or fields["TRK"..ch]) then
    name = fields["trk"..ch] or fields["TRK"..ch]
    return name, ch
  end

  if k == "trkall" then
    name = fields.trkall or fields.TRKALL or ""
    if name ~= "" then
      for i=1,64 do
        local v = fields["trk"..i] or fields["TRK"..i]
        if v and v ~= "" and tostring(v)==tostring(name) then ch = i; break end
      end
      return name, ch
    end
  end

  local raw = fields[k] or fields[k:upper()] or fields.trk or fields.TRK or ""
  if raw ~= "" then
    local n1, c1 = tostring(raw):match("^(.-)%s*%(%s*ch%s*(%d+)%s*%)%s*$")
    if n1 then
      name = n1
      ch   = tonumber(c1) or ch
      if ch and (fields["trk"..ch] or fields["TRK"..ch]) then
        name = fields["trk"..ch] or fields["TRK"..ch]
      end
      return name, ch
    end
    name = raw
  end

  if name == "" then
    for i=1,64 do
      local v = fields["trk"..i] or fields["TRK"..i]
      if v and v ~= "" then name = v; ch = ch or i; break end
    end
  else
    if not ch then
      for i=1,64 do
        local v = fields["trk"..i] or fields["TRK"..i]
        if v and v ~= "" and tostring(v)==tostring(name) then ch = i; break end
      end
    end
  end

  if name == "" then name = nil end
  return name, ch
end


-- forward declarations
local snapshot_rows_tsv


---------------------------------------
-- Copy-to-New-Tracks：核心
---------------------------------------

-- name_mode  : 1=Track Name（以 Track Name 命名新 TCP & 依此分組），2=Channel#
-- order_mode : 1=Track Name（群組排序依名稱），2=Channel#
-- asc        : true=Ascending, false=Descending
-- append_secondary : 若 name_mode=2（Channel#命名），於 TCP 名稱後附加最常見 Track Name
local function run_copy_to_new_tracks(name_mode, order_mode, asc, append_secondary)
  -- 1) 請 Monitor 先抓 BEFORE
  request_capture("before")

  reaper.Undo_BeginBlock()

  -- 2) 取目前選取 items，抽出 metadata（與 Monitor 一致）
  local items = get_selected_items()
  local rows = {}
  for _, it in ipairs(items) do
    local f   = META.collect_item_fields(it)
    local idx = META.guess_interleave_index(it, f) or f.__chan_index or 1
    f.__chan_index = idx
    local name = tostring(META.expand("${trk}",   f, nil, false) or "")
    local ch   = tonumber(META.expand("${chnum}", f, nil, false) or idx) or idx
    local tk   = take_of(it)
    local tkn  = ""
    if tk then
      local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
      tkn = nm or ""
    end
    rows[#rows+1] = { it = it, name = name, ch = ch, take = tkn }
  end


  -- 排序鍵工具
  local function natural_key(s)
    s = tostring(s or ""):lower():gsub("%s+"," ")
    return s:gsub("(%d+)", function(d) return string.format("%09d", tonumber(d) or 0) end)
  end
  local function channel_label(n)
    return (n and n ~= 999) and string.format("Ch %02d", n) or "Ch ??"
  end

  -- 3) 依「命名軸」分組；群組排序鍵由「排序軸」決定
  local groups, order = {}, {}

  local function natural_key(s)
    s = tostring(s or ""):lower():gsub("%s+"," ")
    return s:gsub("(%d+)", function(d) return string.format("%09d", tonumber(d) or 0) end)
  end
  local function channel_label(n)
    return (n and n ~= 999) and string.format("Ch %02d", n) or "Ch ??"
  end

  local function ensure_group(key, label_seed, ord_key)
    local g = groups[key]
    if not g then
      g = { key = key, label = label_seed, items = {}, name_hist = {}, ord = ord_key }
      groups[key] = g
      order[#order+1] = g
    end
    return g
  end

  for _, r in ipairs(rows) do
    -- 命名/分組 key 與初始 label
    local gkey, glabel
    if name_mode == 1 then
      gkey  = (r.name ~= "" and r.name or "(unnamed)")
      glabel = gkey
    else
      gkey  = tonumber(r.ch) or 999
      glabel = channel_label(gkey)
    end

    -- 主軸的排序鍵
    local ord_key
    if order_mode == 1 then
      ord_key = "N|" .. natural_key(r.name ~= "" and r.name or "(unnamed)")
    else
      ord_key = string.format("C|%09d", tonumber(r.ch) or 999)
    end

    -- 副軸（隱式）：當以 Channel# 命名且勾選 Append Track Name → 依 Track Name 拆分
    local skey, slabel = "", ""
    if name_mode == 2 and append_secondary then
      local sub = tostring(r.name or "")
      skey   = "\0" .. sub
      slabel = (sub ~= "" and (" — " .. sub) or " — (name)")
      -- 同群之間的次序：主軸 ord_key 後再接自然鍵，維持嚴格弱序
      ord_key = ord_key .. "|S|" .. natural_key(sub)
    end

    -- 組合群組鍵與標籤
    local comb_key   = tostring(gkey) .. skey
    local comb_label = tostring(glabel) .. slabel

    local g = ensure_group(comb_key, comb_label, ord_key)
    g.items[#g.items+1] = r.it
    if r.name and r.name ~= "" then
      g.name_hist[r.name] = (g.name_hist[r.name] or 0) + 1
    end

  end

  -- 當以 Channel# 命名且勾選 Append Track Name 時，已依 Track Name 拆分到不同新軌，
  -- 不需要再追加「最常見 Track Name」到標籤（避免重複/誤導）
  -- [no-op]


  -- 4) 依 ord 排序群組（嚴格弱序）
  local function ord_lt(a, b)
    local ax, ay = tostring(a and a.ord or ""), tostring(b and b.ord or "")
    if ax == ay then return false end
    return ax < ay
  end
  if asc then
    table.sort(order, ord_lt)
  else
    table.sort(order, function(x, y) return ord_lt(y, x) end)
  end

  -- 5) 建新軌並複製
  local base = reaper.CountTracks(0)
  local existing, created = {}, {}
  local function ensure_track(label)
    local tr = existing[label]
    if tr then return tr end
    reaper.InsertTrackAtIndex(base + #created, true)
    tr = reaper.GetTrack(0, base + #created)
    set_track_name(tr, label)
    existing[label] = tr
    created[#created+1] = tr
    return tr
  end

  local copied, overlaps = 0, 0
  local spans = {} -- label -> { {s,e}, ... }

  for _, g in ipairs(order) do
    local label = g.label
    local tr = ensure_track(label)
    local arr = spans[label] or {}
    spans[label] = arr
    for _, it in ipairs(g.items) do
      local s = item_start(it) or 0
      local e = s + (item_len(it) or 0)
      local hit = false
      for i = 1, #arr do local seg = arr[i]; if e > seg.s and seg.e > s then hit = true; break end end
      if hit then overlaps = overlaps + 1 end
      arr[#arr+1] = { s = s, e = e }
      copy_item_to_track(it, tr)
      copied = copied + 1
    end
  end

  reaper.Undo_EndBlock("Copy selected items to NEW tracks by metadata", -1)
  reaper.UpdateArrange()

  -- 6) 請 Monitor 抓 AFTER
  request_capture("after")

  return { tracks_created = #created, items_copied = copied, overlaps = overlaps }
end



---------------------------------------
-- UI / Engine 狀態
---------------------------------------
local STATE, MODE, EXIT = "confirm", nil, false
local sort_key_idx    = load_pref("sort_key_idx", 1)
local sort_asc        = load_pref("sort_asc", true)
local meta_sort_mode  = load_pref("meta_sort_mode", 1)

local meta_name_mode  = load_pref("meta_name_mode", 1)
local meta_order_mode = load_pref("meta_order_mode", 1)
local meta_append_secondary = load_pref("meta_append_secondary", true)


local SELECTED_ITEMS, SELECTED_SET = {}, {}
local SEL_TR_SET, SEL_TR_ORDER, ACTIVE_TRACKS, OCC, MOVES = {}, {}, {}, nil, {}
local MOVED, SKIPPED, TOTAL = 0, 0, 0
local SUMMARY = ""

-- === Selection polling throttle ===
local LAST_NI, LAST_NT = -1, -1         -- 上次看到的選取數量（items/tracks）
local NEXT_SCAN_AT = 0
local SCAN_INTERVAL = 0.12              -- 每 0.12 秒才允許重掃一次

local function maybe_compute_selection()
  local now = reaper.time_precise()
  local ni = reaper.CountSelectedMediaItems(0)
  local nt = reaper.CountSelectedTracks(0)
  -- 若數量變了，或到了下一個掃描時刻，就重建整份快照
  if ni ~= LAST_NI or nt ~= LAST_NT or now >= NEXT_SCAN_AT then
    compute_selection_and_tracks()
    LAST_NI, LAST_NT = ni, nt
    NEXT_SCAN_AT = now + SCAN_INTERVAL
  end
end


-- === Summary popup state ===
local WANT_POPUP = false
local POPUP_TITLE = "Result Summary"

local function draw_summary_popup()
  -- 如果剛剛要求彈窗，先開啟
  if WANT_POPUP then
    reaper.ImGui_OpenPopup(ctx, POPUP_TITLE)
    WANT_POPUP = false
  end

  local flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
  if reaper.ImGui_BeginPopupModal(ctx, POPUP_TITLE, true, flags) then
    reaper.ImGui_Text(ctx, SUMMARY ~= "" and SUMMARY or "Done.")
    reaper.ImGui_Spacing(ctx)

    -- ESC 關閉（額外保險）
    if esc_pressed() then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end

    if reaper.ImGui_Button(ctx, "Close", 90, 26) then
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_EndPopup(ctx)
  end
end


local function compute_selection_and_tracks()
  SELECTED_ITEMS = get_selected_items()
  SELECTED_SET = {}; for _,it in ipairs(SELECTED_ITEMS) do SELECTED_SET[it]=true end
  SEL_TR_SET, SEL_TR_ORDER = get_selected_tracks_set()
  if next(SEL_TR_SET)==nil then SEL_TR_SET, SEL_TR_ORDER = unique_tracks_from_items(SELECTED_ITEMS) end
  ACTIVE_TRACKS = {}; for _,tr in ipairs(SEL_TR_ORDER) do ACTIVE_TRACKS[#ACTIVE_TRACKS+1]=tr end
  local filtered = {}
  for _, it in ipairs(SELECTED_ITEMS) do if SEL_TR_SET[item_track(it)] then filtered[#filtered+1] = it end end
  SELECTED_ITEMS = filtered
end

---------------------------------------
-- Metadata 取鍵（供 Sort Vertically 用）
---------------------------------------
local function meta_key_track_name(it)
  local f = META.collect_item_fields(it)
  local idx = META.guess_interleave_index(it, f) or f.__chan_index or 1
  f.__chan_index = idx
  local name = META.expand("${trk}", f, nil, false)
  return tostring(name or ""):lower()
end
local function meta_key_channel_num(it)
  local f = META.collect_item_fields(it)
  local idx = META.guess_interleave_index(it, f) or f.__chan_index or 1
  f.__chan_index = idx
  local ch = tonumber(META.expand("${chnum}", f, nil, false)) or idx or 999
  return string.format("%09d", tonumber(ch) or 999)
end

local function prepare_plan()
  OCC = build_initial_occupancy(ACTIVE_TRACKS, SELECTED_SET)
  if MODE == "reorder" then
    MOVES = plan_reorder_moves(SELECTED_ITEMS, ACTIVE_TRACKS, OCC)
  else
    local keyfn
    if     sort_key_idx==1 then keyfn = key_take_name
    elseif sort_key_idx==2 then keyfn = key_file_name
    else
      keyfn = (meta_sort_mode==1) and meta_key_track_name or meta_key_channel_num
    end
    MOVES = plan_sort_moves(SELECTED_ITEMS, ACTIVE_TRACKS, OCC, keyfn, sort_asc)
  end
  TOTAL, MOVED, SKIPPED = #SELECTED_ITEMS, 0, 0
end

-- === Snapshot payload (TSV) from a given item list ===
function snapshot_rows_tsv(items)
  local sep = "\t"
  local out = {}
  local function esc(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n\t]", " ") -- TSV 安全
    return s
  end

  -- header（與 Monitor 匯出一致）
  out[#out+1] = table.concat({
    "#","TrackIdx","TrackName","TakeName","Source File",
    "MetaTrackName","Channel#","Interleave","Mute","ColorHex","StartTime","EndTime"
  }, sep)

  for i, it in ipairs(items or {}) do
    local tr = reaper.GetMediaItem_Track(it)
    local tidx = tr and math.floor(reaper.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or 0) or 0
    local _, tname = tr and reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false) or false, ""
    local take = reaper.GetActiveTake(it)
    local tkn = (take and reaper.GetTakeName(take)) or ""
    local src = take and reaper.GetMediaItemTake_Source(take)
    local file = ""
    if src then
      local fn = reaper.GetMediaSourceFileName(src, "")
      file = fn or ""
    end
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION") or 0
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")   or 0
    local muted = (reaper.GetMediaItemInfo_Value(it, "B_MUTE") or 0) > 0.5
    local native = reaper.GetDisplayedMediaItemColor(it) or 0
    local hex = ""
    if native ~= 0 then
      local r,g,b = reaper.ColorFromNative(native)
      hex = string.format("#%02X%02X%02X", r,g,b)
    end

    -- 這兩個先留空或 1（Monitor 可顯示，但不影響）
    local meta_trk = tname or ""
    local interleave = ""
    local chnum = 1

    out[#out+1] = table.concat({
      esc(i),
      esc(tidx),
      esc(tname or ""),
      esc(tkn),
      esc(file),
      esc(meta_trk),
      esc(chnum),
      esc(interleave),
      esc(muted and "1" or "0"),
      esc(hex),
      esc(pos),
      esc(pos + len),
    }, sep)
  end

  return table.concat(out, "\n")
end




local function run_engine()
  request_capture("before")          -- ★ 先請 Monitor 抓 BEFORE
  reaper.Undo_BeginBlock()
  apply_moves(MOVES)
  MOVED = #MOVES
  reaper.Undo_EndBlock((MODE=="reorder") and
    "Reorder (fill upward) selected items" or
    "Sort selected items vertically", -1)
  reaper.UpdateArrange()
  request_capture("after")           -- ★ 完成後請 Monitor 抓 AFTER
end

---------------------------------------
-- Metadata Preview helpers (for UI)
---------------------------------------
-- 保存在 UI 期間可重用的對照表：{ {ch=1,name="Vocal"}, ... }
local PREVIEW_PAIRS = {}

-- 給名稱排序用的簡單自然排序鍵
local function _preview_natkey(s)
  s = tostring(s or ""):lower():gsub("%s+", " ")
  return s:gsub("(%d+)", function(d) return string.format("%09d", tonumber(d) or 0) end)
end

-- 從目前的 items（最多取頭 10 個樣本）掃出 TRK1..64 的 {ch ↔ name}
local function build_preview_pairs(items)
  PREVIEW_PAIRS = {}
  local seen = {}
  local n = math.min(10, #items)
  for i = 1, n do
    local f = META.collect_item_fields(items[i])
    for ch = 1, 64 do
      local nm = f["trk"..ch] or f["TRK"..ch]
      if nm and nm ~= "" then
        local key = ch .. "\0" .. nm
        if not seen[key] then
          seen[key] = true
          PREVIEW_PAIRS[#PREVIEW_PAIRS+1] = { ch = ch, name = nm }
        end
      end
    end
  end
  table.sort(PREVIEW_PAIRS, function(a, b)
    if a.ch ~= b.ch then return a.ch < b.ch end
    return _preview_natkey(a.name) < _preview_natkey(b.name)
  end)
end


---------------------------------------
-- UI：畫面（直向）
---------------------------------------
-- === REPLACE WHOLE FUNCTION ===
local function draw_confirm()
  compute_selection_and_tracks()
  reaper.ImGui_Text(ctx, string.format("Selected: %d item(s) across %d track(s).", #SELECTED_ITEMS, #ACTIVE_TRACKS))
  reaper.ImGui_Spacing(ctx)
  reaper.ImGui_Spacing(ctx)

  reaper.ImGui_SameLine(ctx)
  local chg, v = reaper.ImGui_Checkbox(ctx, "Monitor auto-capture", CAPTURE_ON)
  if chg then set_capture_enabled(v) end

  -- Draw result popup if needed
  draw_summary_popup()

  -- 1) Reorder
  reaper.ImGui_Text(ctx, "Reorder")
  if reaper.ImGui_Button(ctx, "Reorder (fill upward)", 222, 28) then
    MODE="reorder"; prepare_plan(); run_engine()
    SUMMARY = ("Completed. Items=%d, Moved=%d, Skipped=%d."):format(TOTAL, MOVED, SKIPPED)
    WANT_POPUP = true
  end

  reaper.ImGui_Separator(ctx)

  -- 2) Sort Vertically
  reaper.ImGui_Text(ctx, "Sort Vertically")

  -- Sort key 選項
  local labels = { "Take name", "File name", "Metadata" }
  for i=1,3 do
    if reaper.ImGui_RadioButton(ctx, labels[i], sort_key_idx==i) then
      sort_key_idx=i
      save_pref("sort_key_idx", sort_key_idx)
    end
    if i<3 then reaper.ImGui_SameLine(ctx) end
  end
  local chg_asc, asc_chk = reaper.ImGui_Checkbox(ctx, "Ascending", sort_asc)
  if chg_asc then
    sort_asc = asc_chk
    save_pref("sort_asc", sort_asc)
  end

  if sort_key_idx==3 then
    -- ---- Metadata 子選項（分離命名與排序）----
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Sort by Metadata (engine key):")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Track Name##key", meta_sort_mode==1) then
      meta_sort_mode=1
      save_pref("meta_sort_mode", meta_sort_mode)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Channel##key",   meta_sort_mode==2) then
      meta_sort_mode=2
      save_pref("meta_sort_mode", meta_sort_mode)
    end

    -- ★ 主按鈕放在這裡（Preview 上方）
    reaper.ImGui_Spacing(ctx)

    -- 🆕 Sort in Place（就地排序）
    if reaper.ImGui_Button(ctx, "Sort in Place", 108, 26) then
      -- 使用現有的「Sort Vertically」引擎，但 key 來自 Metadata
      MODE = "sort"
      sort_key_idx = 3
      prepare_plan()
      run_engine()
      SUMMARY = ("Completed. Items=%d, Moved=%d, Skipped=%d."):format(TOTAL, MOVED, SKIPPED)
      WANT_POPUP = true
    end
    reaper.ImGui_SameLine(ctx)

    -- 🆕 Copy-to-Sort 的「TCP命名」與「群組排序」
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Copy-to-Sort — TCP naming:")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Track Name##nm", meta_name_mode==1) then
      meta_name_mode=1
      save_pref("meta_name_mode", meta_name_mode)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Channel##nm",    meta_name_mode==2) then
      meta_name_mode=2
      save_pref("meta_name_mode", meta_name_mode)
    end

    reaper.ImGui_Text(ctx, "Copy-to-Sort — order:")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Track Name##ord", meta_order_mode==1) then
      meta_order_mode=1
      save_pref("meta_order_mode", meta_order_mode)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Channel##ord",    meta_order_mode==2) then
      meta_order_mode=2
      save_pref("meta_order_mode", meta_order_mode)
    end

    -- 🆕 當以 Channel# 命名新 TCP 時，附加最常見 Track Name
    if meta_name_mode == 2 then
      local chg, v = reaper.ImGui_Checkbox(ctx, "Append Track Name label (e.g., 'Ch 03 — BOOM1')", meta_append_secondary)
      if chg then
        meta_append_secondary = v
        save_pref("meta_append_secondary", meta_append_secondary)
      end

    end

    reaper.ImGui_Spacing(ctx)

    -- 🆕 Copy to Sort：帶入命名軸與排序軸
    if reaper.ImGui_Button(ctx, "Copy to Sort", 108, 26) then
      local res = run_copy_to_new_tracks(meta_name_mode, meta_order_mode, sort_asc, meta_append_secondary)
      if res then
        SUMMARY = string.format(
          "Copy to Sort — Done.\nTracks created: %d\nItems copied: %d\nOverlaps detected: %d",
          res.tracks_created or 0, res.items_copied or 0, res.overlaps or 0
        )
      else
        SUMMARY = "Copy to Sort — Done."
      end
      WANT_POPUP = true
    end




    -- Preview（選擇性資訊，放在按鈕之後）
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Preview detected fields")
    if reaper.ImGui_Button(ctx, "Scan first 10 items", 200, 22) then
      build_preview_pairs(SELECTED_ITEMS)   -- ← 先生成 PREVIEW_PAIRS
    end

    -- 只有有資料才畫表格，避免 PREVIEW_PAIRS 為 nil/空表時當掉
    if type(PREVIEW_PAIRS) == "table" and #PREVIEW_PAIRS > 0 then
      reaper.ImGui_Spacing(ctx)
      if reaper.ImGui_BeginTable(ctx, "tbl_preview", 2,
          reaper.ImGui_TableFlags_Borders() | reaper.ImGui_TableFlags_RowBg(), -1, 220) then
        reaper.ImGui_TableSetupColumn(ctx, "Channel #")
        reaper.ImGui_TableSetupColumn(ctx, "Track Name")
        reaper.ImGui_TableHeadersRow(ctx)
        for _, p in ipairs(PREVIEW_PAIRS) do
          reaper.ImGui_TableNextRow(ctx)
          reaper.ImGui_TableSetColumnIndex(ctx, 0); reaper.ImGui_Text(ctx, tostring(p.ch))
          reaper.ImGui_TableSetColumnIndex(ctx, 1); reaper.ImGui_Text(ctx, tostring(p.name))
        end
        reaper.ImGui_EndTable(ctx)
      end
    else
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Text(ctx, "Preview: click \"Scan first 10 items\"")
    end

  else
    -- 非 Metadata：這裡才畫 Sort 的主按鈕
    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, "Run Sort Vertically", 220, 26) then
      MODE="sort"; prepare_plan(); run_engine()
      SUMMARY = ("Completed. Items=%d, Moved=%d, Skipped=%d."):format(TOTAL, MOVED, SKIPPED)
      WANT_POPUP = true
    end
  end

  reaper.ImGui_Separator(ctx)
end



local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 720, 560, reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoCollapse()
  local visible, open = reaper.ImGui_Begin(ctx, "Vertical Reorder and Sort"..LIBVER, true, flags)

  -- ESC 關閉整個視窗（若 Summary modal 開著，先只關 modal）
  if esc_pressed() and not reaper.ImGui_IsPopupOpen(ctx, POPUP_TITLE) then
    open = false
  end

  if visible then
    if STATE=="confirm" then draw_confirm()
    else if draw_summary() then open=false end end
  end
  reaper.ImGui_End(ctx) -- 永遠呼叫（修正 Missing End）

  if open then reaper.defer(loop) end
end

loop()
