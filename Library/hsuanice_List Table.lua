--[[
hsuanice_List Table.lua
Minimal helper library for Item List Editor
(No UI. Pure helpers for columns/selection/clipboard/paste/export.)
Exports a single table: LT = { ... }

@about
  hsuanice_List Table.lua — Minimal helper library for Item List Editor.
  Provides pure, side-effect-free utilities (no UI, no REAPER writes).

  Functions include:
    • Column helpers: rebuild_display_mapping()
    • Row helpers: build_row_index_map(), filter_rows()
    • Selection helpers: sel_rect_apply() (Shift-rectangle)
    • Clipboard helpers: copy_selection(), parse_clipboard_table(),
      flatten_tsv_to_list(), src_shape_dims()
    • Destination builders: build_dst_list_from_selection(),
      build_dst_by_anchor_and_shape()
    • Summary: compute_summary() for item count, span, length totals
    • Export: build_table_text() to TSV/CSV (follows visual column order)

  Intended usage:
    Called from the Item List Editor (or similar scripts) to handle
    table logic, selection mechanics, and text I/O, keeping the Editor
    focused on UI and REAPER state changes only.

@changelog
  v0.1.0
    - Initial release of hsuanice_List Table library.
    - Provides pure helper functions for Item List Editor (no UI, no REAPER writes).
    - Features:
      • Column order mapping: rebuild_display_mapping()  
      • Row index map (GUID → row index)  
      • Selection rectangle handling (Shift + click)  
      • Copy selection to TSV (visual order)  
      • Clipboard parsing (TSV / simple CSV with quotes)  
      • Flatten TSV/CSV into 1D list for paste logic  
      • Source shape dimensions (rows × columns)  
      • Build destination list from selection (row-major, visual order)  
      • Spill by anchor & shape (Excel-style), restricted to writable columns (3=Track, 4=Take, 5=Item Note)  
      • Export table as TSV/CSV following on-screen column order
--]]

local LT = {}

------------------------------------------------------------
-- Columns: visual <-> logical mapping
------------------------------------------------------------
-- resolve_label_to_id: function(label) -> logical_col_id (number)
function LT.rebuild_display_mapping(ctx, resolve_label_to_id)
  local n = reaper.ImGui_TableGetColumnCount(ctx) or 0
  local order = {}
  local pos   = {}  -- pos[logical_id] = visual_pos
  for i = 1, n do
    local name = reaper.ImGui_TableGetColumnName(ctx, i-1) or ""
    local id   = resolve_label_to_id(name)
    order[i] = id
    if id then pos[id] = i end
  end
  return order, pos
end

------------------------------------------------------------
-- Rows: visible rows index map (GUID -> row index for current view)
------------------------------------------------------------
function LT.build_row_index_map(rows)
  local rim = {}
  for i, r in ipairs(rows or {}) do
    rim[r.__item_guid] = i
  end
  return rim
end

------------------------------------------------------------
-- Rows: filters (pure, no UI)
------------------------------------------------------------
-- LT.filter_rows(rows, opts) -> filtered_rows (new table)
--   opts = {
--     show_muted = true/false (default: true)
--     predicate  = function(row) -> boolean   -- 可選，自訂過濾條件（與 show_muted AND 起來）
--   }
function LT.filter_rows(rows, opts)
  local out = {}
  rows = rows or {}
  opts = opts or {}
  local show_muted = (opts.show_muted ~= false)  -- 預設顯示靜音列

  for i = 1, #rows do
    local r = rows[i]
    local ok = true
    if not show_muted and r.muted then ok = false end
    if ok and type(opts.predicate) == "function" then
      ok = not not opts.predicate(r)
    end
    if ok then out[#out+1] = r end
  end
  return out
end




------------------------------------------------------------
-- Selection: Shift rectangle (visual-ordered)
------------------------------------------------------------
-- sel_add(guid, logical_col) is provided by the Editor
function LT.sel_rect_apply(rows, row_index_map, anchor_guid, cur_guid, anchor_col, cur_col,
                           COL_ORDER, COL_POS, sel_add)
  if not (anchor_guid and cur_guid and anchor_col and cur_col) then return end
  local r1 = row_index_map[anchor_guid]; local r2 = row_index_map[cur_guid]
  if not (r1 and r2) then return end
  if r2 < r1 then r1, r2 = r2, r1 end

  -- visual positions -> clamp by available columns
  local p1 = (COL_POS and COL_POS[anchor_col]) or anchor_col
  local p2 = (COL_POS and COL_POS[cur_col])    or cur_col
  if not (p1 and p2) then return end
  if p2 < p1 then p1, p2 = p2, p1 end

  for i = r1, r2 do
    local g = rows[i].__item_guid
    for pos = p1, p2 do
      local logical = COL_ORDER[pos]
      if logical then sel_add(g, logical) end
    end
  end
end

------------------------------------------------------------
-- Copy: build TSV from current selection (visual order)
------------------------------------------------------------
-- sel_has(guid, logical_col) and get_cell_text(i, row, logical_col, "tsv")
function LT.copy_selection(rows, row_index_map, sel_has, COL_ORDER, COL_POS, get_cell_text)
  if not (rows and #rows > 0 and COL_ORDER and #COL_ORDER > 0) then return "" end

  -- find selected rectangle bounds in row-major (visible rows only)
  local rmin, rmax = math.huge, -math.huge
  local pmin, pmax = math.huge, -math.huge
  for i, row in ipairs(rows) do
    local g = row.__item_guid
    for pos, logical in ipairs(COL_ORDER) do
      if logical and sel_has(g, logical) then
        if i < rmin then rmin = i end
        if i > rmax then rmax = i end
        if pos < pmin then pmin = pos end
        if pos > pmax then pmax = pos end
      end
    end
  end
  if rmax < rmin or pmax < pmin then return "" end

  local out = {}
  for i = rmin, rmax do
    local row = rows[i]
    local line = {}
    for pos = pmin, pmax do
      local col = COL_ORDER[pos]
      local val = (col and sel_has(row.__item_guid, col)) and (get_cell_text(i, row, col, "tsv") or "") or ""
      line[#line+1] = val
    end
    out[#out+1] = table.concat(line, "\t")
  end
  return table.concat(out, "\n")
end

------------------------------------------------------------
-- Clipboard parse helpers (TSV / CSV)
------------------------------------------------------------
local function _split_lines(s)
  local t = {}
  s = s:gsub("\r\n", "\n")
  for line in (s.."\n"):gmatch("([^\n]*)\n") do t[#t+1] = line end
  -- drop trailing empty line if clipboard ends with newline
  if #t>0 and t[#t]=="" then table.remove(t, #t) end
  return t
end

function LT.parse_clipboard_table(text)
  text = text or ""
  if text == "" then return {} end
  local lines = _split_lines(text)
  local use_tsv = false
  for _, ln in ipairs(lines) do if ln:find("\t", 1, true) then use_tsv = true break end end

  local tbl = {}
  if use_tsv then
    for i, ln in ipairs(lines) do
      local row = {}
      for cell in (ln.."\t"):gmatch("([^\t]*)\t") do row[#row+1] = cell end
      tbl[#tbl+1] = row
    end
  else
    -- simple CSV parser with quotes
    for _, ln in ipairs(lines) do
      local row = {}
      local i, n = 1, #ln
      while i <= n do
        if ln:sub(i,i) == '"' then
          local j = i+1; local buf = {}
          while j <= n do
            local c = ln:sub(j,j)
            if c == '"' then
              if ln:sub(j+1,j+1) == '"' then buf[#buf+1] = '"' ; j = j + 2
              else j = j + 1; break end
            else buf[#buf+1] = c ; j = j + 1 end
          end
          row[#row+1] = table.concat(buf)
          if ln:sub(j,j) == "," then j = j + 1 end
          i = j
        else
          local j = ln:find(",", i, true) or (n+1)
          row[#row+1] = ln:sub(i, j-1)
          i = j + 1
        end
      end
      tbl[#tbl+1] = row
    end
  end
  return tbl
end

function LT.flatten_tsv_to_list(tbl)
  local out = {}
  for r = 1, #tbl do for c = 1, #(tbl[r] or {}) do out[#out+1] = tbl[r][c] end end
  return out
end

function LT.src_shape_dims(tbl)
  local h, w = #tbl, 0
  for r = 1, #tbl do w = math.max(w, #(tbl[r] or {})) end
  return h, w
end

------------------------------------------------------------
-- Build destination list from current selection (visible rows only)
------------------------------------------------------------
-- Returns: { {guid=..., col=...}, ... } in row-major order
function LT.build_dst_list_from_selection(rows, sel_has, COL_ORDER, COL_POS)
  local dst = {}
  if not (rows and COL_ORDER and #rows>0 and #COL_ORDER>0) then return dst end
  for i, row in ipairs(rows) do
    for pos, col in ipairs(COL_ORDER) do
      if col and sel_has(row.__item_guid, col) then
        dst[#dst+1] = { guid = row.__item_guid, col = col, row_index = i, visual_pos = pos }
      end
    end
  end
  return dst
end

------------------------------------------------------------
-- Spill by anchor & shape (Excel-style), writable cols only (3/4/5)
------------------------------------------------------------
-- anchor: { guid=..., col=..., row_index=..., visual_pos=... }  (caller may pass any subset;
--         if row_index/visual_pos missing we recompute from rows/COL_ORDER)
function LT.build_dst_by_anchor_and_shape(rows, anchor, src_h, src_w)
  if not (rows and anchor and src_h and src_w) then return {} end
  local writable = { [3]=true, [4]=true, [5]=true }
  -- compute anchor row index if missing
  local r0 = anchor.row_index or 1
  if not anchor.row_index and anchor.guid then
    for i, row in ipairs(rows) do if row.__item_guid == anchor.guid then r0 = i break end end
  end
  -- compute first writable logical col at/after anchor.col (fallback to 3)
  local start_col = 3
  if type(anchor.col)=="number" and writable[anchor.col] then start_col = anchor.col
  else
    for _, cid in ipairs({anchor.col, 3,4,5}) do if type(cid)=="number" and writable[cid] then start_col = cid break end end
  end

  local dst = {}
  local rmax = math.min(#rows, r0 + src_h - 1)
  for ri = r0, rmax do
    local g = rows[ri].__item_guid
    local wrote = 0
    for logical = start_col, 5 do
      if writable[logical] then
        dst[#dst+1] = { guid = g, col = logical, row_index = ri }
        wrote = wrote + 1
        if wrote >= src_w then break end
      end
    end
  end
  return dst
end

------------------------------------------------------------
-- Summary helpers (pure aggregation; no UI/formatting)
------------------------------------------------------------
-- Returns:
--   { count, min_start, max_end, span, sum_len }
function LT.compute_summary(rows)
  local n = #(rows or {})
  if n == 0 then
    return { count = 0, min_start = nil, max_end = nil, span = 0, sum_len = 0 }
  end

  local min_start = math.huge
  local max_end   = -math.huge
  local sum_len   = 0.0

  for i = 1, n do
    local r = rows[i]
    local s = tonumber(r and r.start_time) or 0
    local e = tonumber(r and r.end_time)   or s
    if s < min_start then min_start = s end
    if e > max_end   then max_end   = e end
    sum_len = sum_len + (e - s)
  end

  return {
    count     = n,
    min_start = min_start,
    max_end   = max_end,
    span      = max_end - min_start,
    sum_len   = sum_len,
  }
end



------------------------------------------------------------
-- Export (TSV/CSV) following visual column order
------------------------------------------------------------
-- header_label_from_id(col_id) and get_cell_text(i, row, col, fmt) are provided by Editor
function LT.build_table_text(fmt, rows, COL_ORDER, header_label_from_id, get_cell_text)
  local sep = (fmt == "csv") and "," or "\t"
  local out = {}

  local export_cols = (COL_ORDER and #COL_ORDER>0) and COL_ORDER or {1,2,3,4,5,6,7,8,9,10,11,12,13}
  local header = {}
  for _, cid in ipairs(export_cols) do header[#header+1] = header_label_from_id(cid) end
  out[#out+1] = table.concat(header, sep)

  for i, r in ipairs(rows or {}) do
    local line = {}
    for _, cid in ipairs(export_cols) do
      local s = tostring(get_cell_text(i, r, cid, fmt) or "")
      if fmt=="csv" and s:find('[,\r\n"]') then s = '"'..s:gsub('"','""')..'"' end
      line[#line+1] = s
    end
    out[#out+1] = table.concat(line, sep)
  end

  return table.concat(out, "\n")
end

return LT


