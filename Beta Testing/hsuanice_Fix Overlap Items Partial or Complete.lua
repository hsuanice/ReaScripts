--[[
@description hsuanice_Fix Overlap Items Partial or Complete
@version 0.1.1
@author hsuanice
@changelog
  v0.1.1 (2025-09-13)
    - Ignore intended crossfades: if the entire overlap lies within
      the left item's fade-out and the right item's fade-in (manual or auto),
      the pair is skipped (no marker, no report).
  v0.1.0 (2025-09-13)
    - Initial release: scan all (non-hidden) tracks for item overlaps per track.
    - Classifies as Partial or Complete overlap with sample-accurate tolerance.
    - Adds take markers: "Review: Item overlap — partial/complete".
    - Prints a TSV report to Console and saves a copy next to the project (Overlaps.tsv).
@about
  Finds item overlaps on each track (ignores cross-track). For every overlapping pair:
  - Marks BOTH related items with a take marker at the overlap start position.
  - Writes a TSV report with Track | Take | Start/End (TC & samples) | Note.
  - No auto-fix yet. You can manually resolve using the take markers.
  Future: options to trim, heal, or promote one of the items automatically.
--]]

local r = reaper

----------------------------------------------------------------
-- user options
----------------------------------------------------------------
local DRY_RUN           = true    -- this version only reports/marks; no destructive edit
local WRITE_TSV         = true
local TSV_FILENAME      = "Overlaps.tsv"
-- tolerance: treat times within ≤ 1 sample as equal (avoid float jitter)
local function get_sample_tolerance()
  local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)  -- 0 if "project default"
  if sr == 0 or sr < 1 then sr = 48000 end
  return 1.0 / sr
end

----------------------------------------------------------------
-- utils
----------------------------------------------------------------
local function fmt_tc(sec)  return r.format_timestr_pos(sec, "", 5) end   -- h:m:s:f
local function fmt_smp(sec) return r.format_timestr_pos(sec, "", 4) end   -- samples

local function msg(s) r.ShowConsoleMsg(tostring(s) .. "\n") end

local function get_item_bounds(it)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  return pos, pos + len, len
end

local function get_take_name_safe(tk)
  if not tk then return "" end
  local _, name = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return name or ""
end

-- convert a project-time position to the take's source time for SetTakeMarker
local function projtime_to_taketime(take, item, project_pos)
  if not take or not item then return 0 end
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local rate     = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate == 0 then rate = 1 end
  local offs     = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local take_time = (project_pos - item_pos) / rate + offs
  if take_time < 0 then take_time = 0 end
  return take_time
end

local function add_overlap_marker(item, proj_pos, label)
  local take = r.GetActiveTake(item)
  if not take then return end
  local tpos = projtime_to_taketime(take, item, proj_pos)
  -- idx=-1 appends; position is in TAKE (source) time
  r.SetTakeMarker(take, -1, label, tpos)
end

-- 有效淡變長度（手動與自動取最大，AUTO=-1 視為 0）
local function effective_fadesec(it)
  local fi  = r.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0
  local fo  = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0
  local fia = r.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO") or -1
  local foa = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") or -1
  if fia < 0 then fia = 0 end
  if foa < 0 then foa = 0 end
  return math.max(fi, fia), math.max(fo, foa) -- in_len, out_len
end

-- 判斷 A(左) 與 B(右) 的重疊是否屬於「交叉淡變」
local function is_crossfade(A, B, tol)
  -- 先確保 A 在左、B 在右
  if not (A.s <= B.s) then return false end
  local overlap_start = math.max(A.s, B.s)
  local overlap_end   = math.min(A.e, B.e)
  if overlap_end <= overlap_start + tol then return false end

  local in_len_B, out_len_A = nil, nil
  local inA, outA = effective_fadesec(A.it)
  local inB, outB = effective_fadesec(B.it)
  -- A 的有效淡出、B 的有效淡入
  out_len_A = outA
  in_len_B  = inB

  -- A 的淡出開始點、B 的淡入結束點（專案時間）
  local A_fadeout_start = A.e - out_len_A
  local B_fadein_end    = B.s + in_len_B

  -- crossfade 定義：重疊區完全位於 A 的淡出區間與 B 的淡入區間之內
  local within_A = overlap_start >= (A_fadeout_start - tol)
  local within_B = overlap_end   <= (B_fadein_end    + tol)

  return (out_len_A > tol) and (in_len_B > tol) and within_A and within_B
end


local function get_track_visibility(tr)
  -- TCP visibility bitfield: &1 = visible in TCP, &2 = NOT visible in Mixer
  -- 我們只需要 TCP 可見；若你確定專案「沒有隱藏」，也可以略過這個檢查。
  local vis = r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP")
  return vis == 1
end

----------------------------------------------------------------
-- main scan
----------------------------------------------------------------
local function scan_overlaps()
  local tol = get_sample_tolerance()
  local rows = {}  -- TSV rows
  local header = table.concat({
    "Track", "Take name",
    "Start (TC)", "End (TC)",
    "Start (samples)", "End (samples)",
    "Note"
  }, "\t")
  table.insert(rows, header)

  local proj_path = r.GetProjectPath("")  -- path only
  local proj, proj_fn = r.EnumProjects(-1, "")
  local tcount = r.CountTracks(0)

  for ti = 0, tcount-1 do
    local tr = r.GetTrack(0, ti)
    if tr and get_track_visibility(tr) then
      local _, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)

      -- collect items on this track
      local n_it = r.CountTrackMediaItems(tr)
      if n_it > 1 then
        local items = {}
        for i = 0, n_it-1 do
          local it = r.GetTrackMediaItem(tr, i)
          local s, e = get_item_bounds(it)
          items[#items+1] = { it=it, s=s, e=e }
        end
        table.sort(items, function(a,b) return a.s < b.s end)

        -- sweep line: compare current with next
        for i = 1, #items-1 do
          local A = items[i]
          local B = items[i+1]

          -- if next starts before current ends -> overlap
          if B.s < (A.e - tol) then
            -- 交叉淡變的重疊：忽略
            if is_crossfade(A, B, tol) then
              goto continue_pair
            end

            local overlap_start = math.max(A.s, B.s)
            local overlap_end   = math.min(A.e, B.e)
            local is_complete = (math.abs(A.s - B.s) <= tol) and (math.abs(A.e - B.e) <= tol)


            local note = is_complete and "Item overlap — complete" or "Item overlap — partial"

            -- add take markers on BOTH related items at overlap start
            add_overlap_marker(A.it, overlap_start, "Review: " .. note)
            add_overlap_marker(B.it, overlap_start, "Review: " .. note)

            -- report both items as separate rows (方便之後各別定位)
            for _, node in ipairs({A,B}) do
              local take = r.GetActiveTake(node.it)
              local take_name = get_take_name_safe(take)
              table.insert(rows, table.concat({
                tr_name or "",
                take_name,
                fmt_tc(node.s), fmt_tc(node.e),
                fmt_smp(node.s), fmt_smp(node.e),
                note
              }, "\t"))
            end
            ::continue_pair::
          end
        end
      end
    end
  end

  -- write console + file
  r.ClearConsole()
  msg("=== Overlap report (per track) ===")
  for _, line in ipairs(rows) do msg(line) end

  if WRITE_TSV then
    local sep = package.config:sub(1,1)
    local out = (proj_path or "") .. sep .. TSV_FILENAME
    local f = io.open(out, "w")
    if f then
      f:write(table.concat(rows, "\n"))
      f:close()
      msg("\nSaved TSV: " .. out)
    else
      msg("\n[WARN] Cannot write TSV file: " .. tostring(out))
    end
  end
end

----------------------------------------------------------------
-- run
----------------------------------------------------------------
r.Undo_BeginBlock()
r.PreventUIRefresh(1)
scan_overlaps()
r.PreventUIRefresh(-1)
r.Undo_EndBlock("Scan overlaps and add take markers (partial/complete)", -1)

