--[[
@description ReaImGui - Reorder or sort selected items vertically
@version 0.3.3
@author hsuanice
@about
  Provides two vertical re-arrangement modes for selected items:

  • Reorder (fill upward)  
    - Keeps items at their original timeline position.  
    - Packs items upward into available selected tracks, avoiding gaps.  
    - Useful to condense scattered clips without changing their order.  

  • Sort Vertically  
    - Groups items by near-identical start time.  
    - Within each time cluster, re-orders items top-to-bottom by:  
        Take Name / File Name / Metadata field.  
    - Optional Ascending / Descending toggle.  

  • Copy to New Tracks by Metadata  
    - NEW: Duplicates selected items onto newly created tracks,  
      named from metadata (e.g. $trk, $trkall, TRK1…TRK64).  
    - Tracks are ordered by Channel Number, then by Name.  
    - Original tracks/items remain untouched.  

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.3.3
    - New: Option "Order new tracks alphabetically (ignore channel #)" for Copy-to-New-Tracks.
           Uses natural sort so names with numbers order intuitively (e.g., CHEN 2.0 < CHEN 10.0).
    - Tweak: Name sort now uses a natural string key for consistent A→Z ordering.
  v0.3.2
    - Fix: "invalid order function for sorting" in Sort Vertically by Take/File; use single-key total ordering.
  v0.3.1
    - Fix: Always call ImGui_End() to prevent "Missing End()" error.
    - Added Copy-to-New-Tracks-by-Metadata and metadata parsing improvements.

  v0.3.2
         - Fix: Sort Vertically sometimes raised "invalid order function for sorting".
          Replaced comparator with single-key total ordering (string-composed key).

  v0.3.1 - Fix: Always call ImGui_End() to prevent "Missing End()" error.
         - Improved metadata parsing: support $trk, $trkall, TRK{n}, and filename patterns (_AAP_N, tN__PN).
         - New "Copy to New Tracks by Metadata" mode: auto-create destination tracks named from metadata, copy items there.
         - Track order based on Channel number (unknown=999, then by name).
         - Preview detected fields to check available metadata before sorting.
]]

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
local ctx = reaper.ImGui_CreateContext('Vertical Reorder / Sort')
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
-- Sort keys（Take / File）
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
    -- 組合單一鍵：字串可比性強、全序；time 固定小數位避免浮點誤差
    local ord = table.concat({
      k,
      string.format("%09d", ti),
      string.format("%015.6f", st),
      string.format("%09d", i)
    }, "|")
    recs[#recs+1] = { it = it, ord = ord }
  end

  if asc then
    table.sort(recs, function(a,b) return a.ord < b.ord end)
  else
    table.sort(recs, function(a,b) return a.ord > b.ord end)
  end

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
  for _,m in ipairs(moves) do
    reaper.MoveMediaItemToTrack(m.item, m.to)
  end
end

---------------------------------------
-- 讀取 Metadata：BWF/iXML + take/name/note
---------------------------------------
local function get_meta(src, key)
  if not src or not reaper.GetMediaFileMetadata then return nil end
  local ok, val = reaper.GetMediaFileMetadata(src, key) -- REAPER API：GetMediaFileMetadata
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
        if nm and nm~="" then
          t["trk"..ci] = nm; t["TRK"..ci] = nm
        end
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

  -- 檔名推 ch：W-054_AAP_3.WAV / UM5613...t1__PN.WAV
  local srcfile = fields.srcfile or fields.FILENAME or fields.filename or fields.sfilename
  if srcfile and srcfile ~= "" then
    ch = tonumber(tostring(srcfile):match("_AAP_(%d+)")) or
         tonumber(tostring(srcfile):match("[_%-]t(%d+)[_%-]"))
  end

  -- 若 iXML 有 TRACK_LIST，TRK{ch} 直接給名
  if ch and (fields["trk"..ch] or fields["TRK"..ch]) then
    name = fields["trk"..ch] or fields["TRK"..ch]
    return name, ch
  end

  -- 若指定 trkall，先取 trkall，再從 TRK1..64 找 ch
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

  -- 一般情形（含 k=="trk"）：讀 "Name (ch N)"
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

  -- 沒有 name：從 TRK1..64 找第一個
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

---------------------------------------
-- Copy-to-New-Tracks：核心
---------------------------------------
-- 排序選項：true = 只按名稱 A→Z；false = 先 Channel# 再名稱
local ORDER_BY_NAME_ONLY = false

-- 自然排序鍵：把數字補零，避免 "10" 小於 "2" 的問題（CHEN 2.0 < CHEN 10.0）
local function natural_key(s)
  s = tostring(s or ""):lower()
  s = s:gsub("%s+", " ")
  s = s:gsub("(%d+)", function(d) return string.format("%09d", tonumber(d)) end)
  return s
end

local META_NAME_KEY = "trk" -- 預設讀 $trk（建議）
local SHOW_PREVIEW  = false
local PREVIEW_TEXT  = ""

local function build_preview_text(items)
  local counts = {}
  local sample = math.min(80, #items)
  for i=1,sample do
    local f = collect_fields(items[i])
    for _,k in ipairs({"trkall","TRKALL","trk","TRK3","TRK4","TRK5","TRK6","TRK7","TRK8","TRK9","TRK10","curtake","curnote"}) do
      local v = f[k]
      if v and v~="" then counts[k]=counts[k] or {}; counts[k][v]=(counts[k][v] or 0)+1 end
    end
    for i2=1,16 do local v=f["trk"..i2]; if v and v~="" then counts["trk"..i2]=counts["trk"..i2] or {}; counts["trk"..i2][v]=(counts["trk"..i2][v] or 0)+1 end end
  end
  local lines={"Detected fields (first "..sample.." items):"}
  local keys={}
  for k,_ in pairs(counts) do keys[#keys+1]=k end
  table.sort(keys)
  for _,k in ipairs(keys) do
    lines[#lines+1] = "  $"..k..":"
    local xs={}
    for v,c in pairs(counts[k]) do xs[#xs+1]={v=v,c=c} end
    table.sort(xs,function(a,b) return a.v<b.v end)
    for i=1,math.min(6,#xs) do lines[#lines+1] = "    - "..xs[i].v.."  ("..xs[i].c..")" end
    if #xs>6 then lines[#lines+1] = "    … +"..(#xs-6).." more" end
  end
  PREVIEW_TEXT = table.concat(lines,"\n")
end

local function ensure_target_track(name, ch, base_index, existing, order)
  if existing[name] then return existing[name] end
  local insert_at = base_index + #order
  reaper.InsertTrackAtIndex(insert_at, true)
  local tr = reaper.GetTrack(0, insert_at)
  set_track_name(tr, name)
  existing[name] = tr
  order[#order+1] = {name=name, ch=ch or 999, tr=tr}
  return tr
end

local function copy_item_to_track(it, tr)
  local s  = item_start(it)
  local len= item_len(it)
  local new = reaper.AddMediaItemToTrack(tr)
  reaper.SetMediaItemInfo_Value(new, "D_POSITION", s)
  reaper.SetMediaItemInfo_Value(new, "D_LENGTH",   len)
  local ok, chunk = reaper.GetItemStateChunk(it, "", false)
  if ok then
    chunk = chunk:gsub("\n%s*SEL%s+1", "\n  SEL 0")
    reaper.SetItemStateChunk(new, chunk, false)
  end
  return new
end

local function run_copy_to_new_tracks()
  local items = get_selected_items()
  if #items==0 then return end
  reaper.Undo_BeginBlock()

  local groups = {}  -- name => { ch=min_ch, items={ {it, ch}... } }
  for _,it in ipairs(items) do
    if not is_item_locked(it) then
      local f = collect_fields(it)
      local name, ch = extract_name_and_chan(f, META_NAME_KEY)
      name = tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
      if name=="" or not name then name = "(Unknown)" end
      local g = groups[name] or { ch=ch or 999, items={} }
      if ch and (not g.ch or ch < g.ch) then g.ch = ch end
      table.insert(g.items, {it=it, ch=ch or 999})
      groups[name] = g
    end
  end

  local names = {}
  for n,_ in pairs(groups) do names[#names+1]=n end
  table.sort(names, function(a,b)
    if ORDER_BY_NAME_ONLY then
      return natural_key(a) < natural_key(b)
    else
      local ca,cb = groups[a].ch or 999, groups[b].ch or 999
      if ca ~= cb then return ca < cb end
      return natural_key(a) < natural_key(b)
    end
  end)

  local last_idx = reaper.CountTracks(0)
  local created, order, copied = {}, {}, 0

  for _,name in ipairs(names) do
    local tr = ensure_target_track(name, groups[name].ch, last_idx, created, order)
    for _,row in ipairs(groups[name].items) do
      copy_item_to_track(row.it, tr); copied = copied + 1
    end
  end

  reaper.Undo_EndBlock("Copy selected items to NEW tracks by metadata ($"..META_NAME_KEY..")", -1)
  reaper.UpdateArrange()
  reaper.MB(("Completed.\nNew tracks: %d\nItems copied: %d\nKey: $%s\n\nNote:\n- Track order = by Channel # (unknown = 999, then by name).\n- Original tracks/items untouched."):format(#order, copied, META_NAME_KEY), "Copy to New Tracks", 0)
end

---------------------------------------
-- UI / Engine 狀態
---------------------------------------
local STATE, MODE, EXIT = "confirm", nil, false
local sort_key_idx, sort_asc = 2, true
local SELECTED_ITEMS, SELECTED_SET = {}, {}
local SEL_TR_SET, SEL_TR_ORDER, ACTIVE_TRACKS, OCC, MOVES = {}, {}, {}, nil, {}
local MOVED, SKIPPED, TOTAL, CUR_IDX = 0, 0, 0, 0
local SUMMARY = ""

local function compute_selection_and_tracks()
  SELECTED_ITEMS = get_selected_items()
  SELECTED_SET = {}; for _,it in ipairs(SELECTED_ITEMS) do SELECTED_SET[it]=true end
  SEL_TR_SET, SEL_TR_ORDER = get_selected_tracks_set()
  if next(SEL_TR_SET)==nil then SEL_TR_SET, SEL_TR_ORDER = unique_tracks_from_items(SELECTED_ITEMS) end
  ACTIVE_TRACKS = {}; for _,tr in ipairs(SEL_TR_ORDER) do ACTIVE_TRACKS[#ACTIVE_TRACKS+1]=tr end
  -- 僅保留屬於所選軌的 items
  local filtered = {}
  for _, it in ipairs(SELECTED_ITEMS) do if SEL_TR_SET[item_track(it)] then filtered[#filtered+1] = it end end
  SELECTED_ITEMS = filtered
end

local function prepare_plan()
  OCC = build_initial_occupancy(ACTIVE_TRACKS, SELECTED_SET)
  if MODE == "reorder" then
    MOVES = plan_reorder_moves(SELECTED_ITEMS, ACTIVE_TRACKS, OCC)
  else
    local keyfn = (sort_key_idx==1) and key_take_name or key_file_name
    MOVES = plan_sort_moves(SELECTED_ITEMS, ACTIVE_TRACKS, OCC, keyfn, sort_asc)
  end
  TOTAL, CUR_IDX, MOVED, SKIPPED = #SELECTED_ITEMS, 0, 0, 0
end

local function run_engine()
  reaper.Undo_BeginBlock()
  apply_moves(MOVES)
  MOVED = #MOVES
  reaper.Undo_EndBlock((MODE=="reorder") and "Reorder (fill upward) selected items" or "Sort selected items vertically", -1)
  reaper.UpdateArrange()
end

---------------------------------------
-- UI：畫面
---------------------------------------
local SHOW_PRE = false
local function draw_confirm()
  compute_selection_and_tracks()
  reaper.ImGui_Text(ctx, string.format("Selected: %d item(s) across %d track(s).", #SELECTED_ITEMS, #ACTIVE_TRACKS))
  reaper.ImGui_Spacing(ctx)

  if reaper.ImGui_Button(ctx, "Reorder (fill upward)", 220, 28) then MODE="reorder"; prepare_plan(); run_engine(); SUMMARY=("Completed. Items=%d, Moved=%d, Skipped=%d."):format(TOTAL,MOVED,SKIPPED); STATE="summary" end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Sort Vertically", 150, 28) then MODE="sort"; prepare_plan(); run_engine(); SUMMARY=("Completed. Items=%d, Moved=%d, Skipped=%d."):format(TOTAL,MOVED,SKIPPED); STATE="summary" end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Copy to New Tracks by Metadata", 300, 28) then run_copy_to_new_tracks() end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Cancel", 100, 28) or esc_pressed() then EXIT=true return end

  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Sort options (only for Sort Vertically):")
  local labels = { "Take name", "File name", "Metadata field" }
  for i=1,2 do
    if reaper.ImGui_RadioButton(ctx, labels[i], sort_key_idx==i) then sort_key_idx=i end
    reaper.ImGui_SameLine(ctx)
  end
  -- Metadata field（僅供 Copy 模式/預覽使用）
  reaper.ImGui_Text(ctx, "Metadata field for Copy:  "); reaper.ImGui_SameLine(ctx)
  local changed, buf = reaper.ImGui_InputText(ctx, "##metakey", META_NAME_KEY or "", 140)
  if changed then META_NAME_KEY = buf end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Preview detected fields", 200, 24) then SHOW_PRE=true; build_preview_text(SELECTED_ITEMS) end
  reaper.ImGui_SameLine(ctx)
  local _, name_only = reaper.ImGui_Checkbox(ctx, "Order new tracks alphabetically (ignore channel #)", ORDER_BY_NAME_ONLY)
  ORDER_BY_NAME_ONLY = name_only  
  local _, asc_chk = reaper.ImGui_Checkbox(ctx, "Ascending (for Sort Vertically)", sort_asc); sort_asc = asc_chk

  if SHOW_PRE then
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Detected fields (read-only):")
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    reaper.ImGui_InputTextMultiline(ctx, "##preview", PREVIEW_TEXT or "", -1, 220, reaper.ImGui_InputTextFlags_ReadOnly())
  end
end

local function draw_summary()
  reaper.ImGui_Text(ctx, SUMMARY); reaper.ImGui_Spacing(ctx)
  if reaper.ImGui_Button(ctx, "Close", 90, 26) or esc_pressed() then EXIT=true return end
end

local function loop()
  -- ★ 修正 Missing End()：Begin/End 一定成對
  reaper.ImGui_SetNextWindowSize(ctx, 760, 420, reaper.ImGui_Cond_FirstUseEver())
  local flags = reaper.ImGui_WindowFlags_NoCollapse()|reaper.ImGui_WindowFlags_AlwaysAutoResize()
  local visible, open = reaper.ImGui_Begin(ctx, "Vertical Reorder / Sort", true, flags)

  if visible then
    if STATE=="confirm" then draw_confirm()
    else draw_summary() end
  end
  reaper.ImGui_End(ctx) -- 永遠呼叫

  if open and not EXIT then reaper.defer(loop) end
end

loop()
