--[[
@description Track • Razor • Item LINK — MONITOR (driver-aware)
@version 0.9.5-driver
@author hsuanice
@about
  監控 Track / Razor / Item 的連動關係與狀態。

  新增：
    • 顯示 driver（ARR / TCP / none）
    • 顯示 latched track count（latched_track_count）
    • 仍支援舊鍵名（active_start/active_end 等），保留 Shift-Add Guard 與 “由 items 造成選軌改變” 判斷
]]

----------------------------------------------------------------
-- 設定
----------------------------------------------------------------
local MAX_ITEMS_LIST_GLOBAL    = 500

----------------------------------------------------------------
-- 腳本切換狀態（依你的實際命令 ID）
----------------------------------------------------------------
local SCRIPTS = {
  {"hsuanice_Razor and Item Link with Mode Switch to Overlap or Contain like Pro Tools.lua",
    "_RS6f4e0dfffa0b2d8dbfb1d1f52ed8053bfb935b93", "razor_item"},
  {"hsuanice_Track and Razor Item Link like Pro Tools.lua",
    "_RScb810d93e985a5df273b63589ec315d81fa18529", "track_razor_item"},
}

----------------------------------------------------------------
-- 小工具
----------------------------------------------------------------
local function fmt_time_num(n)
  if not n then return "n/a" end
  local h = math.floor(n / 3600)
  local m = math.floor((n % 3600) / 60)
  local s = math.floor(n % 60)
  local ms = math.floor((n - math.floor(n)) * 1000 + 0.5)
  return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end

local function track_name(tr) local _, n = reaper.GetTrackName(tr, "") return n end
local function track_guid(tr) return reaper.GetTrackGUID(tr) end
local function track_selected(tr) return (reaper.GetMediaTrackInfo_Value(tr, "I_SELECTED") or 0) > 0.5 end

local function get_toggle_txt(cmd_str)
  local cmd = reaper.NamedCommandLookup(cmd_str)
  if cmd == 0 then return "UNKNOWN" end
  local st = reaper.GetToggleCommandStateEx(0, cmd)
  return (st == 1 and "ON") or (st == 0 and "OFF") or "UNKNOWN"
end

----------------------------------------------------------------
-- 偏好顯示
----------------------------------------------------------------
local function pref_selects_track_label()
  if reaper.APIExists and reaper.APIExists("SNM_GetIntConfigVar") then
    local v = reaper.SNM_GetIntConfigVar("trackselonmouse", -1)
    if v == 1 then return "ON" elseif v==0 then return "OFF" else return "UNKNOWN" end
  end
  return "UNKNOWN (SWS not installed)"
end

----------------------------------------------------------------
-- 共享狀態讀取（相容）
----------------------------------------------------------------
local EXT_NS = "hsuanice_Link"
local function R(k) local _, v = reaper.GetProjExtState(0, EXT_NS, k); return v ~= "" and v or nil end
local function num(v) return v and tonumber(v) or nil end

local function read_shared_state()
  local active_s = num(R("active_s") or R("active_start"))
  local active_e = num(R("active_e") or R("active_end"))
  local item_s   = num(R("item_s")   or R("item_span_start"))
  local item_e   = num(R("item_e")   or R("item_span_end"))
  local virt_s   = num(R("virt_s")   or R("virt_latched_start"))
  local virt_e   = num(R("virt_e")   or R("virt_latched_end"))
  local ts_s     = num(R("ts_s")     or R("ts_start"))
  local ts_e     = num(R("ts_e")     or R("ts_end"))
  local has_raz  = (R("has_razor") == "1")
  local ts_real  = (R("ts_has_real") == "1")
  local driver   = R("driver") or "none"
  local ltc      = tonumber(R("latched_track_count") or "0") or 0

  return {
    active_src = R("active_src") or "none",
    active_s = active_s, active_e = active_e,
    item_s = item_s, item_e = item_e,
    virt_s = virt_s, virt_e = virt_e,
    ts_s = ts_s, ts_e = ts_e,
    has_razor = has_raz, ts_has_real = ts_real,
    driver = driver, ltc = ltc,
    -- 可能存在（新主腳本才會寫）
    anchor_guid = R("anchor_guid"),
    anchor_idx  = R("anchor_idx"),
    anchor_src  = R("anchor_src"),
    tr_evt      = R("tr_evt"),
  }
end

----------------------------------------------------------------
-- Razor 讀取
----------------------------------------------------------------
local function parse_track_level_razor(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
  if not ok then return {} end
  local out = {}
  for a,b,g in string.gmatch(s, "([%d%.%-]+) ([%d%.%-]+) (%b\"\")") do
    if g == '""' then out[#out+1] = {tonumber(a), tonumber(b)} end
  end
  table.sort(out, function(x,y) return x[1] < y[1] end)
  return out
end

local function razor_union_all_tracks()
  local keys, out = {}, {}
  local tcnt = reaper.CountTracks(0)
  for i=0, tcnt-1 do
    local tr = reaper.GetTrack(0,i)
    for _, r in ipairs(parse_track_level_razor(tr)) do
      local k = string.format("%.9f|%.9f", r[1], r[2])
      if not keys[k] then keys[k]=true; out[#out+1] = {r[1], r[2]} end
    end
  end
  table.sort(out, function(a,b) return a[1] < b[1] end)
  return out
end

----------------------------------------------------------------
-- 狀態快照（事件分類用）
----------------------------------------------------------------
local function selected_tracks_set_and_sig()
  local set, list = {}, {}
  local tcnt = reaper.CountTracks(0)
  for i=0, tcnt-1 do
    local tr = reaper.GetTrack(0,i)
    if track_selected(tr) then
      local g = track_guid(tr)
      set[g] = true
      list[#list+1] = g
    end
  end
  table.sort(list)
  return set, table.concat(list, "|")
end

local function selected_items_sig_and_count()
  local parts, cnt = {}, 0
  local icnt = reaper.CountMediaItems(0)
  for i=0, icnt-1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      cnt = cnt + 1
      local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
      parts[#parts+1] = g or tostring(it)
    end
  end
  table.sort(parts)
  return table.concat(parts, "|"), cnt
end

local function razor_sig_all_tracks()
  local parts = {}
  local tcnt = reaper.CountTracks(0)
  for i=0, tcnt-1 do
    local tr = reaper.GetTrack(0,i)
    local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    parts[#parts+1] = (ok and s) and s or ""
  end
  return table.concat(parts, "|")
end

----------------------------------------------------------------
-- 輸出
----------------------------------------------------------------
local function print_header()
  reaper.ShowConsoleMsg("=== Track • Razor • Item LINK — MONITOR ===\n")
  for _, rec in ipairs(SCRIPTS) do
    reaper.ShowConsoleMsg(string.format("  %s: %s\n", rec[1], get_toggle_txt(rec[2])))
  end
  reaper.ShowConsoleMsg(("REAPER Preference — Arrange click selects track: %s\n\n"):format(pref_selects_track_label()))
end

local function print_selected_tracks()
  local names = {}
  local tcnt = reaper.CountTracks(0)
  for i=0, tcnt-1 do local tr = reaper.GetTrack(0,i); if track_selected(tr) then names[#names+1]=track_name(tr) end end
  reaper.ShowConsoleMsg(("# Selected Tracks: %d\n"):format(#names))
  if #names>0 then reaper.ShowConsoleMsg("  "..table.concat(names, ", ").."\n") end
  reaper.ShowConsoleMsg("\n")
end

local function active_take_name(it)
  local tk = reaper.GetActiveTake(it)
  if not tk then return "<no take>" end
  local ok, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  if ok and nm ~= "" then return nm end
  local src = reaper.GetMediaItemTake_Source(tk)
  if src then
    local buf = reaper.GetMediaSourceFileName(src, "")
    if buf and buf ~= "" then return buf:match("[^/\\]+$") or buf end
  end
  return "<unnamed>"
end

local function print_items_global()
  local icnt = reaper.CountMediaItems(0)
  local rows, total = {}, 0
  local min_s, max_e = math.huge, -math.huge
  for i=0, icnt-1 do
    local it = reaper.GetMediaItem(0, i)
    if reaper.GetMediaItemInfo_Value(it, "B_UISEL") == 1 then
      total = total + 1
      local s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local e = s + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if s < min_s then min_s = s end
      if e > max_e then max_e = e end
      if #rows < MAX_ITEMS_LIST_GLOBAL then
        rows[#rows+1] = string.format("%s  [%s..%s]", active_take_name(it), fmt_time_num(s), fmt_time_num(e))
      end
    end
  end
  reaper.ShowConsoleMsg(("# Selected Items: %d\n"):format(total))
  for _,line in ipairs(rows) do reaper.ShowConsoleMsg("  • "..line.."\n") end
  if total > #rows then reaper.ShowConsoleMsg(("  (+%d more)\n"):format(total-#rows)) end
  if total>0 then
    reaper.ShowConsoleMsg(("  Computed item range: [%s .. %s]  (%.6f .. %.6f)\n\n"):format(fmt_time_num(min_s), fmt_time_num(max_e), min_s, max_e))
  else
    reaper.ShowConsoleMsg("  Computed item range: (none)\n\n")
  end
end

local function print_razors()
  reaper.ShowConsoleMsg("Razor Areas (TRACK-LEVEL only):\n")
  local any = false
  local tcnt = reaper.CountTracks(0)
  for i=0, tcnt-1 do
    local tr = reaper.GetTrack(0,i)
    local ranges = parse_track_level_razor(tr)
    if #ranges>0 then
      any = true
      reaper.ShowConsoleMsg(("  - %s:\n"):format(track_name(tr)))
      for _,r in ipairs(ranges) do
        reaper.ShowConsoleMsg(("      [%s .. %s]  (%.6f .. %.6f)\n"):format(fmt_time_num(r[1]), fmt_time_num(r[2]), r[1], r[2]))
      end
    end
  end
  if not any then reaper.ShowConsoleMsg("  (none)\n") end
  local uni = razor_union_all_tracks()
  reaper.ShowConsoleMsg(("\nRazor UNION ranges: %d\n"):format(#uni))
  for _,r in ipairs(uni) do reaper.ShowConsoleMsg(("  [%s .. %s]  (%.6f .. %.6f)\n"):format(fmt_time_num(r[1]), fmt_time_num(r[2]), r[1], r[2])) end
  reaper.ShowConsoleMsg("\n")
end

local function print_shared_state_extras(st, flags)
  reaper.ShowConsoleMsg("Shared Link State (ProjExtState: hsuanice_Link):\n")
  reaper.ShowConsoleMsg(("  active_src   : %s\n"):format(st.active_src))
  reaper.ShowConsoleMsg(("  active_range : [%s .. %s]\n"):format(fmt_time_num(st.active_s), fmt_time_num(st.active_e)))
  reaper.ShowConsoleMsg(("  item_span    : [%s .. %s]\n"):format(fmt_time_num(st.item_s), fmt_time_num(st.item_e)))
  reaper.ShowConsoleMsg(("  virt_latched : [%s .. %s]\n"):format(fmt_time_num(st.virt_s), fmt_time_num(st.virt_e)))
  reaper.ShowConsoleMsg(("  real TS      : [%s .. %s]  (%s)\n"):format(fmt_time_num(st.ts_s), fmt_time_num(st.ts_e), st.ts_has_real and "present" or "none"))
  reaper.ShowConsoleMsg(("  has_razor    : %s\n"):format(st.has_razor and "YES" or "NO"))
  reaper.ShowConsoleMsg(("  driver       : %s\n"):format(st.driver))
  reaper.ShowConsoleMsg(("  latched_track_count : %d\n"):format(st.ltc or 0))

  if flags then
    reaper.ShowConsoleMsg(("  tracks_changed_by_items : %s\n"):format(flags.tracks_changed_by_items and "YES" or "NO"))
    reaper.ShowConsoleMsg(("  shift_add_guard         : %s\n"):format(flags.shift_add_guard and "ON" or "OFF"))
    if st.tr_evt and st.tr_evt ~= "" then
      reaper.ShowConsoleMsg(("  tr_evt (from script)    : %s\n"):format(st.tr_evt))
    end
  end
  reaper.ShowConsoleMsg("\n")
end

local function print_link_summary()
  local on_raz_it, on_trk = false, false
  for _, rec in ipairs(SCRIPTS) do
    local on = (get_toggle_txt(rec[2]) == "ON")
    if rec[3] == "razor_item" then on_raz_it = on end
    if rec[3] == "track_razor_item" then on_trk = on end
  end
  reaper.ShowConsoleMsg("Link summary:\n")
  reaper.ShowConsoleMsg(string.format("  Razor >> Item link: %s\n", on_raz_it and "ACTIVE" or "OFF"))
  reaper.ShowConsoleMsg(string.format("  Track <> Razor+Item link: %s\n\n", on_trk and "ACTIVE" or "OFF"))
end

----------------------------------------------------------------
-- 事件分類（本地推斷）
----------------------------------------------------------------
local prev = {
  tr_sig = "",          -- tracks
  it_sig = "", it_cnt = 0,  -- items
  rz_sig = "",          -- razor raw sig
}

local function classify_and_print_snapshot()
  reaper.ClearConsole()
  print_header()
  print_selected_tracks()
  print_razors()
  print_items_global()

  local st = read_shared_state()
  local tr_set, tr_sig = selected_tracks_set_and_sig()
  local it_sig, it_cnt = selected_items_sig_and_count()
  local rz_sig = razor_sig_all_tracks()

  local tracks_changed   = (tr_sig ~= prev.tr_sig)
  local items_changed    = (it_sig ~= prev.it_sig)
  local razors_changed   = (rz_sig ~= prev.rz_sig)

  local shift_add_guard = false
  if items_changed == false and tracks_changed == true and it_cnt > 0 then
    local is_superset = true
    for g in string.gmatch(prev.tr_sig or "", "[^|]+") do
      if g ~= "" then
        local still = tr_set[g] or false
        if not still then is_superset = false; break end
      end
    end
    if is_superset then shift_add_guard = true end
  end

  local flags = {
    tracks_changed_by_items = (items_changed and tracks_changed) or false,
    shift_add_guard = shift_add_guard,
  }

  print_shared_state_extras(st, flags)
  print_link_summary()

  prev.tr_sig = tr_sig
  prev.it_sig = it_sig
  prev.it_cnt = it_cnt
  prev.rz_sig = rz_sig
end

----------------------------------------------------------------
-- GFX（ESC/Cancel）
----------------------------------------------------------------
local GFX_W, GFX_H = 560, 64
local BTN_W, BTN_H = 96, 26
local BTN_X, BTN_Y = GFX_W - BTN_W - 12, 12
local prev_cap = 0
local function btn_clicked(x,y,w,h)
  local mx,my = gfx.mouse_x, gfx.mouse_y
  local over  = (mx>=x and mx<=x+w and my>=y and my<=y+h)
  local cap   = gfx.mouse_cap
  local clicked = over and (prev_cap&1==0) and (cap&1==1)
  prev_cap = cap
  return clicked
end
local function draw_cancel_ui()
  gfx.set(0.12,0.12,0.12,1); gfx.rect(0,0,GFX_W,GFX_H,1)
  gfx.set(0.9,0.9,0.9,1); gfx.x=12; gfx.y=12
  gfx.drawstr("Monitor running... ESC or click Cancel to quit")
  gfx.set(0.15,0.15,0.15,1); gfx.rect(BTN_X,BTN_Y,BTN_W,BTN_H,1)
  gfx.set(0.55,0.55,0.55,1); gfx.rect(BTN_X,BTN_Y,BTN_W,BTN_H,0)
  gfx.x = BTN_X+20; gfx.y = BTN_Y+6; gfx.set(0.9,0.9,0.9,1); gfx.drawstr("Cancel")
  gfx.update()
  if btn_clicked(BTN_X,BTN_Y,BTN_W,BTN_H) then return true end
  local ch = gfx.getchar()
  if ch == 27 or ch == -1 then return true end
  return false
end

----------------------------------------------------------------
-- 主迴圈
----------------------------------------------------------------
local function build_sig_for_redraw()
  local st = read_shared_state()
  local _, tr_sig = selected_tracks_set_and_sig()
  local it_sig = selected_items_sig_and_count()
  return table.concat({
    tr_sig, it_sig, razor_sig_all_tracks(),
    st.active_src, st.driver or "",
    tostring(st.active_s or ""), tostring(st.active_e or ""),
    tostring(st.item_s or ""), tostring(st.item_e or ""),
    tostring(st.virt_s or ""), tostring(st.virt_e or ""),
    tostring(st.ts_s or ""), tostring(st.ts_e or ""),
    st.has_razor and "1" or "0",
    tostring(st.ltc or 0),
  }, "||")
end

local last_sig = ""
local function loop()
  if draw_cancel_ui() then gfx.quit(); return end
  local cur = build_sig_for_redraw()
  if cur ~= last_sig then
    classify_and_print_snapshot()
    last_sig = cur
  end
  reaper.defer(loop)
end

gfx.init("Track • Razor • Item LINK — MONITOR (ESC/Cancel)", GFX_W, GFX_H, 0, 100, 100)
reaper.ShowConsoleMsg("")
classify_and_print_snapshot()
last_sig = build_sig_for_redraw()
loop()
