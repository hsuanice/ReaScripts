--[[
@description hsuanice_Fix Overlap Items Partial or Complete
@version 0.1.3
@author hsuanice
@changelog
  v0.1.3 (2025-09-13)
    - 移除 TSV 相關功能與檔案輸出
    - 一開始先強制打開 Console，再清空，避免某些環境下視窗不彈出
    - Summary 改為掃描結束後再印（避免顯示 0 計數）
  v0.1.2 (2025-09-13)
    - 掃描結束印出 summary（partial / complete / total）
  v0.1.1 (2025-09-13)
    - 忽略「純交叉淡變」造成的重疊（手動/自動淡入淡出都納入）
  v0.1.0 (2025-09-13)
    - 掃描所有軌（不依選取），每軌找 item 重疊，分類 partial/complete
    - 在相關 items 上加 take marker：Review: Item overlap — partial/complete
--]]

local r = reaper

-- ========= User options =========
local DRY_RUN = true -- 目前只標記與列出，不做自動修復

-- ========= Utils =========
local function msg(s) r.ShowConsoleMsg(tostring(s).."\n") end
local function fmt_tc(sec)  return r.format_timestr_pos(sec, "", 5) end  -- h:m:s:f
local function fmt_smp(sec) return r.format_timestr_pos(sec, "", 4) end  -- samples

local function get_sample_tolerance()
  local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if sr == 0 or sr < 1 then sr = 48000 end
  return 1.0 / sr
end

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

-- 把「專案時間」換成 take/source 時間，供 SetTakeMarker 使用
local function projtime_to_taketime(take, item, project_pos)
  if not take or not item then return 0 end
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local rate     = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate == 0 then rate = 1 end
  local offs     = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local tpos = (project_pos - item_pos) / rate + offs
  if tpos < 0 then tpos = 0 end
  return tpos
end

local function add_overlap_marker(item, proj_pos, label)
  local take = r.GetActiveTake(item)
  if not take then return end
  local tpos = projtime_to_taketime(take, item, proj_pos)
  r.SetTakeMarker(take, -1, label, tpos) -- -1=append
end

-- 取有效淡入/淡出秒數（手動與自動取最大，AUTO=-1 視為 0）
local function effective_fadesec(it)
  local fi  = r.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0
  local fo  = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0
  local fia = r.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO") or -1
  local foa = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") or -1
  if fia < 0 then fia = 0 end
  if foa < 0 then foa = 0 end
  return math.max(fi, fia), math.max(fo, foa) -- in_len, out_len
end

-- 判斷 A(左) 與 B(右) 的重疊是否屬於「交叉淡變」→ 若是就忽略
local function is_crossfade(A, B, tol)
  if not (A.s <= B.s) then return false end
  local overlap_start = math.max(A.s, B.s)
  local overlap_end   = math.min(A.e, B.e)
  if overlap_end <= overlap_start + tol then return false end

  local inA, outA = effective_fadesec(A.it)
  local inB, outB = effective_fadesec(B.it)
  local out_len_A = outA
  local in_len_B  = inB

  local A_fadeout_start = A.e - out_len_A
  local B_fadein_end    = B.s + in_len_B

  local within_A = overlap_start >= (A_fadeout_start - tol)
  local within_B = overlap_end   <= (B_fadein_end    + tol)

  return (out_len_A > tol) and (in_len_B > tol) and within_A and within_B
end

-- ========= Main =========
local COUNT_PARTIAL  = 0
local COUNT_COMPLETE = 0

local function scan_overlaps()
  local tol = get_sample_tolerance()
  local lines = {}
  lines[#lines+1] = "Track\tTake name\tStart (TC)\tEnd (TC)\tStart (samples)\tEnd (samples)\tNote"

  local tcount = r.CountTracks(0)
  for ti = 0, tcount-1 do
    local tr = r.GetTrack(0, ti)
    if tr then
      local _, tr_name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)

      local n_it = r.CountTrackMediaItems(tr)
      if n_it > 1 then
        local items = {}
        for i = 0, n_it-1 do
          local it = r.GetTrackMediaItem(tr, i)
          local s, e = get_item_bounds(it)
          items[#items+1] = { it=it, s=s, e=e }
        end
        table.sort(items, function(a,b) return a.s < b.s end)

        -- 逐一檢查相鄰的 A(左) 與 B(右)
        for i = 1, #items-1 do
          local A = items[i]
          local B = items[i+1]

          if B.s < (A.e - tol) then
            -- 純交叉淡變 → 忽略
            if is_crossfade(A, B, tol) then goto continue_pair end

            local overlap_start = math.max(A.s, B.s)
            local overlap_end   = math.min(A.e, B.e)
            local is_complete   = (math.abs(A.s - B.s) <= tol) and (math.abs(A.e - B.e) <= tol)

            if is_complete then COUNT_COMPLETE = COUNT_COMPLETE + 1
            else COUNT_PARTIAL = COUNT_PARTIAL + 1 end

            local note = is_complete and "Item overlap — complete" or "Item overlap — partial"

            -- 兩個 item 都加 marker（用相同 label）
            add_overlap_marker(A.it, overlap_start, "Review: " .. note)
            add_overlap_marker(B.it, overlap_start, "Review: " .. note)

            -- 各自列一行（之後比較好逐一定位/處理）
            for _, node in ipairs({A,B}) do
              local tk  = r.GetActiveTake(node.it)
              local tnm = get_take_name_safe(tk)
              lines[#lines+1] = table.concat({
                tr_name or "",
                tnm or "",
                fmt_tc(node.s), fmt_tc(node.e),
                fmt_smp(node.s), fmt_smp(node.e),
                note
              }, "\t")
            end
            ::continue_pair::
          end
        end
      end
    end
  end

  -- 強制打開 Console，再清空，然後輸出
  r.ShowConsoleMsg(" \n")  -- 這行會「開啟」Console（不是 !SHOW: 前綴）
  r.ClearConsole()
  msg("=== Overlap report (per track) ===")
  for _, line in ipairs(lines) do msg(line) end

  local total = COUNT_PARTIAL + COUNT_COMPLETE
  msg("\n=== Summary ===")
  if total == 0 then
    msg("No overlaps found.")
  else
    msg(string.format("Partial overlaps : %d", COUNT_PARTIAL))
    msg(string.format("Complete overlaps: %d", COUNT_COMPLETE))
    msg(string.format("Total            : %d", total))
  end
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
scan_overlaps()
r.PreventUIRefresh(-1)
r.Undo_EndBlock("Scan overlaps and add take markers (partial/complete, skip crossfades)", -1)
