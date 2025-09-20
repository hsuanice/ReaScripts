--[[
@description Render or Glue Items with Handles Core Library
@version 250921_0205 fix glue in track fx 1 mode fade issue
@author hsuanice
@about
  Library for RGWH glue/render flows with handles, FX policies, rename, # markers, and optional take markers inside glued items.
]]--
local r = reaper
local M = {}

------------------------------------------------------------
-- Constants / Commands
------------------------------------------------------------
local NS = "RGWH"  -- ExtState namespace (project-scope)

-- Actions
local ACT_GLUE_TS        = 42432   -- Item: Glue items within time selection
local ACT_TRIM_TO_TS     = 40508   -- Item: Trim items to time selection
local ACT_APPLY_MONO     = 40361   -- Item: Apply track/take FX to items (mono output)
local ACT_APPLY_MULTI    = 41993   -- Item: Apply track/take FX to items (multichannel output)
local ACT_REMOVE_TAKE_FX = 40640   -- Item: Remove FX for item take

------------------------------------------------------------
-- Defaults (used if no ExtState present)
------------------------------------------------------------
local DEFAULTS = {
  GLUE_SINGLE_ITEMS  = true,
  HANDLE_MODE        = "seconds",
  HANDLE_SECONDS     = 5.0,
  EPSILON_MODE       = "frames",
  EPSILON_VALUE      = 0.5,
  DEBUG_LEVEL        = 1,
  -- FX policies:
  RENDER_TAKE_FX     = 1,      -- 1=保留/印入 take FX；0=Glue 前先移除 take FX
  RENDER_TRACK_FX    = 0,      -- 1=Glue 後對成品套用 Track/Take FX（apply）
  APPLY_FX_MODE      = "mono", -- mono | multi（render/apply 模式）
  -- Rename policy:
  RENAME_OP_MODE     = "auto", -- glue | render | auto
  -- Hash markers（#in/#out 以供 Media Cues）
  WRITE_MEDIA_CUES   = 1,
  -- ✅ 新增：Glue 成品 take 內是否加 take markers（非 SINGLE 才加）
  WRITE_TAKE_MARKERS = 1,
}

------------------------------------------------------------
-- ExtState helpers (project-scope)
------------------------------------------------------------
local function get_proj() return 0 end

local function get_ext(key, fallback)
  local _, v = r.GetProjExtState(get_proj(), NS, key)
  if v == nil or v == "" then return fallback end
  return v
end

local function get_ext_bool(key, fallback_bool)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_bool and 1 or 0 end
  v = tostring(v)
  if v == "1" or v:lower()=="true" then return 1 end
  return 0
end

local function get_ext_num(key, fallback_num)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_num end
  local n = tonumber(v)
  return n or fallback_num
end

local function set_ext(key, val)
  r.SetProjExtState(get_proj(), NS, key, tostring(val))
end

function M.read_settings()
  return {
    GLUE_SINGLE_ITEMS  = (get_ext_bool("GLUE_SINGLE_ITEMS",  DEFAULTS.GLUE_SINGLE_ITEMS)==1),
    HANDLE_MODE        = get_ext("HANDLE_MODE",              DEFAULTS.HANDLE_MODE),
    HANDLE_SECONDS     = get_ext_num("HANDLE_SECONDS",       DEFAULTS.HANDLE_SECONDS),
    EPSILON_MODE       = get_ext("EPSILON_MODE",             DEFAULTS.EPSILON_MODE),
    EPSILON_VALUE      = get_ext_num("EPSILON_VALUE",        DEFAULTS.EPSILON_VALUE),
    DEBUG_LEVEL        = get_ext_num("DEBUG_LEVEL",          DEFAULTS.DEBUG_LEVEL),
    RENDER_TAKE_FX     = (get_ext_bool("RENDER_TAKE_FX",     DEFAULTS.RENDER_TAKE_FX)==1),
    RENDER_TRACK_FX    = (get_ext_bool("RENDER_TRACK_FX",    DEFAULTS.RENDER_TRACK_FX)==1),
    APPLY_FX_MODE      = get_ext("APPLY_FX_MODE",            DEFAULTS.APPLY_FX_MODE),
    RENAME_OP_MODE     = get_ext("RENAME_OP_MODE",           DEFAULTS.RENAME_OP_MODE),
    WRITE_MEDIA_CUES   = (get_ext_bool("WRITE_MEDIA_CUES",   DEFAULTS.WRITE_MEDIA_CUES)==1),
    -- 🔧 修正：用 DEFAULTS，不是 dflt
    WRITE_TAKE_MARKERS = (get_ext_bool("WRITE_TAKE_MARKERS", DEFAULTS.WRITE_TAKE_MARKERS)==1),
  }
end

------------------------------------------------------------
-- Utility / Logging
------------------------------------------------------------
local function printf(fmt, ...) r.ShowConsoleMsg(string.format(fmt.."\n", ...)) end
local function dbg(level, want, ...) if level>=want then printf(...) end end

local function frames_to_seconds(frames, sr, fps)
  local fr = (r.TimeMap_curFrameRate and r.TimeMap_curFrameRate(0) or 24.0)
  return (frames or 1) / (fr>0 and fr or 24.0)
end

local function get_sr()
  return r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
end

local function add_take_marker_at(item, rel_pos_sec, label)
  local take = r.GetActiveTake(item)
  if not take then return end
  r.SetTakeMarker(take, -1, label or "", rel_pos_sec, 0) -- -1 append
end


-- 取 base/ext（若無副檔名則 ext=""）
local function split_ext(s)
  local base, ext = s:match("^(.*)(%.[^%./\\]+)$")
  if not base then return s or "", "" end
  return base, ext
end

-- 移除尾端標籤：-takefx / -trackfx / -renderedN（僅針對字尾，避免中段誤刪）
local function strip_tail_tags(s)
  s = s or ""
  while true do
    local before = s
    s = s:gsub("%-takefx$", "")
    s = s:gsub("%-trackfx$", "")
    s = s:gsub("%-rendered%d+$", "")
    s = s:gsub("%-$","")  -- 若剛好留下尾端 '-'，順手清掉
    if s == before then break end
  end
  return s
end

-- 取名字中的 renderedN（僅字尾，允許後面跟 -takefx/-trackfx 再抽回去）
local function extract_rendered_n(name)
  local b = split_ext(name)
  -- 先暫時移除尾端 -takefx/-trackfx，抓 renderedN
  local t = b:gsub("%-takefx$",""):gsub("%-trackfx$","")
  t = t:gsub("%-takefx$",""):gsub("%-trackfx$","")
  local n = t:match("%-rendered(%d+)$")
  return tonumber(n or 0) or 0
end

-- 掃「同一個 item 的所有 takes」找出已存在的最大 renderedN
local function max_rendered_n_on_item(it)
  local maxn = 0
  local tc = reaper.CountTakes(it)
  for i = 0, tc-1 do
    local tk = reaper.GetTake(it, i)
    local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
    local n = extract_rendered_n(nm or "")
    if n > maxn then maxn = n end
  end
  return maxn
end

-- 只改「新產生的 rendered take」的名稱；舊 take 不動
-- base 用「render 前的舊 take 名稱（去掉既有 suffix）」；ext 用「新 take 現名的副檔名」
local function rename_new_render_take(it, orig_take_name, want_takefx, want_trackfx, DBG)
  if not it then return end
  local tc = reaper.CountTakes(it)
  if tc == 0 then return end

  -- Reaper 會把新 take 加在最後一軌（也通常設為 Active），抓最後一個即可
  local newtk = reaper.GetTake(it, tc-1)
  if not newtk then return end

  -- ext 用新 take 現名的副檔名，以符合「插在副檔名前」的規則
  local _, curNewName = reaper.GetSetMediaItemTakeInfo_String(newtk, "P_NAME", "", false)
  local _, extNew = split_ext(curNewName or "")

  -- base 用舊 take 名（render 前抓到的那個），並去除尾端既有 suffix
  local baseOld = strip_tail_tags(select(1, split_ext(orig_take_name or "")))

  -- N = 目前 item 內最大值 + 1（僅掃本 item，成本極低）
  local nextN = max_rendered_n_on_item(it) + 1

  local newname = string.format("%s-rendered%d", baseOld, nextN)
  if want_takefx  then newname = newname .. "-takefx"  end
  if want_trackfx then newname = newname .. "-trackfx" end
  newname = newname .. extNew

  reaper.GetSetMediaItemTakeInfo_String(newtk, "P_NAME", newname, true)
  dbg(DBG, 1, "[NAME] new take rename '%s' → '%s'", tostring(curNewName or ""), tostring(newname))
end

-- 只快照「offline」布林，不記 bypass
local function snapshot_takefx_offline(tk)
  local n = r.TakeFX_GetCount(tk) or 0
  local snap = {}
  for i = 0, n-1 do
    snap[i] = r.TakeFX_GetOffline(tk, i) and true or false
  end
  return snap
end

-- 暫時把「原本不是 offline」的 FX 設為 offline（不動原本就 offline 的）
local function temp_offline_nonoffline_fx(tk)
  local n = r.TakeFX_GetCount(tk) or 0
  local cnt = 0
  for i = 0, n-1 do
    if not r.TakeFX_GetOffline(tk, i) then
      r.TakeFX_SetOffline(tk, i, true)
      cnt = cnt + 1
    end
  end
  return cnt
end

-- 依快照還原 offline 狀態
local function restore_takefx_offline(tk, snap)
  if not (tk and snap) then return 0 end
  local n = r.TakeFX_GetCount(tk) or 0
  local cnt = 0
  for i = 0, n-1 do
    local want = snap[i]
    if want ~= nil then
      r.TakeFX_SetOffline(tk, i, want and true or false)
      cnt = cnt + 1
    end
  end
  return cnt
end

-- -- Fade snapshot helpers -----------------------------------------
local function snapshot_fades(it)
  return {
    inLen   = r.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0.0,
    outLen  = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0.0,
    inAuto  = r.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO") or 0.0,
    outAuto = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") or 0.0,
    inShape = r.GetMediaItemInfo_Value(it, "C_FADEINSHAPE") or 0,
    outShape= r.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") or 0,
    inDir   = r.GetMediaItemInfo_Value(it, "C_FADEINDIR") or 0.0,
    outDir  = r.GetMediaItemInfo_Value(it, "C_FADEOUTDIR") or 0.0,
  }
end

local function zero_fades(it)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", 0.0)
end

local function restore_fades(it, f)
  if not f then return end
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN",        f.inLen)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN",       f.outLen)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO",   f.inAuto)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO",  f.outAuto)
  r.SetMediaItemInfo_Value(it, "C_FADEINSHAPE",      f.inShape)
  r.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE",     f.outShape)
  r.SetMediaItemInfo_Value(it, "C_FADEINDIR",        f.inDir)
  r.SetMediaItemInfo_Value(it, "C_FADEOUTDIR",       f.outDir)
end

------------------------------------------------------------
-- Selection / grouping helpers
------------------------------------------------------------
local function count_selected_items() return r.CountSelectedMediaItems(0) end
local function get_sel_items()
  local t, n = {}, r.CountSelectedMediaItems(0)
  for i=0,n-1 do t[#t+1] = r.GetSelectedMediaItem(0,i) end
  return t
end

local function item_span(it)
  local pos = r.GetMediaItemInfo_Value(it,"D_POSITION")
  local len = r.GetMediaItemInfo_Value(it,"D_LENGTH")
  return pos, pos+len, len
end

local function get_take_name(it)
  local tk = r.GetActiveTake(it)
  if not tk then return nil end
  local _, nm = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return nm
end

local function set_take_name(it, newn)
  local tk = r.GetActiveTake(it)
  if tk and newn and newn~="" then
    r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", newn, true)
  end
end

local function select_only_items(items)
  r.SelectAllMediaItems(0,false)
  for _,it in ipairs(items) do
    if r.ValidatePtr2(0,it,"MediaItem*") then r.SetMediaItemSelected(it, true) end
  end
  r.UpdateArrange()
end

local function find_item_by_span_on_track(tr, L, R, tol)
  tol = tol or 0.002
  local n = r.CountTrackMediaItems(tr)
  for i=0,n-1 do
    local it = r.GetTrackMediaItem(tr,i)
    local p0,p1 = item_span(it)
    if math.abs(p0-L)<=tol and math.abs(p1-R)<=tol then return it end
  end
  return nil
end

------------------------------------------------------------
-- Unit detection (same track)
------------------------------------------------------------
local function sort_items_by_pos(items)
  table.sort(items, function(a,b)
    local aL = r.GetMediaItemInfo_Value(a,"D_POSITION")
    local bL = r.GetMediaItemInfo_Value(b,"D_POSITION")
    if aL~=bL then return aL<bL end
    local aR = aL + r.GetMediaItemInfo_Value(a,"D_LENGTH")
    local bR = bL + r.GetMediaItemInfo_Value(b,"D_LENGTH")
    return aR<bR
  end)
end

local function detect_units_same_track(items, eps_s)
  local units = {}
  if #items==0 then return units end
  sort_items_by_pos(items)

  local i=1
  while i<=#items do
    local a = items[i]
    local aL,aR = item_span(a)
    if i==#items then
      units[#units+1] = {kind="SINGLE", members={{it=a,L=aL,R=aR}}, start=aL, finish=aR}
      break
    end

    local members = { {it=a,L=aL,R=aR} }
    local anyTouch, anyOverlap = false, false
    local cur_start, cur_end = aL, aR

    local j=i+1
    while j<=#items do
      local itj = items[j]
      local L,R = item_span(itj)
      if L - cur_end > eps_s then break end
      if L >= cur_end - eps_s and L <= cur_end + eps_s then anyTouch=true end
      if L <  cur_end - eps_s then anyOverlap=true end
      members[#members+1] = {it=itj,L=L,R=R}
      if R>cur_end then cur_end=R end
      j=j+1
    end

    local kind
    if #members==1 then kind="SINGLE"
    elseif anyOverlap and anyTouch then kind="MIXED"
    elseif anyOverlap then kind="CROSSFADE"
    else kind="TOUCH" end

    units[#units+1] = {kind=kind, members=members, start=cur_start, finish=cur_end}
    i=j
  end
  return units
end

local function collect_by_track_from_selection()
  local by_tr, tracks = {}, {}
  local sel = get_sel_items()
  for _,it in ipairs(sel) do
    local tr = r.GetMediaItem_Track(it)
    if not by_tr[tr] then by_tr[tr]={}; tracks[#tracks+1]=tr end
    by_tr[tr][#by_tr[tr]+1] = it
  end
  table.sort(tracks, function(a,b)
    return (r.GetMediaTrackInfo_Value(a,"IP_TRACKNUMBER") or 0) < (r.GetMediaTrackInfo_Value(b,"IP_TRACKNUMBER") or 0)
  end)
  return by_tr, tracks
end

------------------------------------------------------------
-- Handle window / clamp
------------------------------------------------------------
local function per_member_window_lr(it, L, R, H_left, H_right)
  local tk   = r.GetActiveTake(it)
  local rate = tk and (r.GetMediaItemTakeInfo_Value(tk,"D_PLAYRATE") or 1.0) or 1.0
  local offs = tk and (r.GetMediaItemTakeInfo_Value(tk,"D_STARTOFFS") or 0.0) or 0.0
  local src  = tk and r.GetMediaItemTake_Source(tk) or nil
  local src_len = src and ({r.GetMediaSourceLength(src)})[1] or math.huge

  local cur_len = R - L

  local max_left_ext  = offs / rate
  local wantL         = L - (H_left or 0.0)
  local gotL          = (wantL < (L - max_left_ext)) and (L - max_left_ext) or wantL

  local max_right_ext = ((src_len - offs) / rate) - cur_len
  if max_right_ext < 0 then max_right_ext = 0 end
  local wantR = R + (H_right or 0.0)
  local gotR  = (wantR > (R + max_right_ext)) and (R + max_right_ext) or wantR

  local clampL = (gotL > wantL + 1e-9)
  local clampR = (gotR < wantR - 1e-9)

  return {
    tk=tk, rate=rate, offs=offs,
    L=L, R=R, wantL=wantL, wantR=wantR, gotL=gotL, gotR=gotR,
    clampL=clampL, clampR=clampR,
    leftH=H_left or 0.0, rightH=H_right or 0.0,
    name=get_take_name(it)
  }
end

------------------------------------------------------------
-- #in/#out project markers
------------------------------------------------------------
local function add_hash_markers(UL, UR, color)
  local proj = 0
  color = color or 0
  local in_id  = r.AddProjectMarker2(proj, false, UL, 0, "#in",  -1, color)
  local out_id = r.AddProjectMarker2(proj, false, UR, 0, "#out", -1, color)
  return {in_id, out_id}
end

local function remove_markers_by_ids(ids)
  if not ids then return end
  local proj = 0
  for _,id in ipairs(ids) do r.DeleteProjectMarker(proj, id, false) end
end

------------------------------------------------------------
-- Rename helpers
------------------------------------------------------------
local function strip_suffixes(base)
  if not base then return base, 0, false, false end
  local n=0
  base = base:gsub("[-_]TakeFX_TrackFX$", function() return "" end)
  base = base:gsub("[-_]TrackFX$",        function() return "" end)
  base = base:gsub("[-_]TakeFX$",         function() return "" end)
  base = base:gsub("[-_]rendered(%d+)$",  function(d) n=tonumber(d) or n; return "" end)
  base = base:gsub("[-_]glued(%d+)$",     function(d) n=tonumber(d) or n; return "" end)
  return base, n, false, false
end

-- 把 -takefx / -trackfx 插在真正的音訊副檔名（.wav/.aif/.aiff/...）之前
-- 若找不到副檔名，就附加在字串尾端。已存在就不重複加（冪等）。
local _KNOWN_EXTS = { ".wav", ".aif", ".aiff", ".flac", ".mp3", ".ogg", ".wv", ".caf", ".m4a" }

local function _split_name_by_audio_ext(nm)
  if not nm or nm == "" then return "", "", "" end
  local lower = string.lower(nm)
  local s_best, e_best = nil, nil
  for _, ext in ipairs(_KNOWN_EXTS) do
    local s, e = 1, 0
    while true do
      s, e = lower:find(ext, e + 1, true)
      if not s then break end
      s_best, e_best = s, e
    end
  end
  if s_best then
    -- stem | .ext | tail（例如 "foo" | ".wav" | "-rendered1-TrackFX"）
    return nm:sub(1, s_best - 1), nm:sub(s_best, e_best), nm:sub(e_best + 1)
  else
    return nm, "", ""
  end
end

local function _has_tag_in_stem(stem, tag)
  if not stem or stem == "" then return false end
  return stem:lower():find("-" .. tag:lower(), 1, true) ~= nil
end

local function _add_tag_once_in_stem(stem, tag)
  if _has_tag_in_stem(stem, tag) then return stem end
  return (stem or "") .. "-" .. tag
end

-- op 參數保留相容性；實際不再分 glue/render 模式
function compute_new_name(op, oldn, flags)
  local stem, ext, tail = _split_name_by_audio_ext(oldn or "")

  local want_take  = flags and flags.takePrinted  == true
  local want_track = flags and flags.trackPrinted == true

  -- 固定順序：takefx → trackfx
  if want_take  then stem = _add_tag_once_in_stem(stem, "takefx")  end
  if want_track then stem = _add_tag_once_in_stem(stem, "trackfx") end

  return stem .. ext .. tail
end


------------------------------------------------------------
-- FX utilities
------------------------------------------------------------
local function get_apply_cmd(mode) return (mode=="multi") and ACT_APPLY_MULTI or ACT_APPLY_MONO end

local function clear_take_fx_for_items(items)
  if #items==0 then return end
  select_only_items(items)
  r.Main_OnCommand(ACT_REMOVE_TAKE_FX, 0)
end

local function apply_track_take_fx_to_item(it, apply_mode, dbg_level)
  r.SelectAllMediaItems(0,false)
  r.SetMediaItemSelected(it,true)
  r.UpdateArrange()
  local cmd = get_apply_cmd(apply_mode)
  dbg(dbg_level,1,"[RUN] Apply Track/Take FX (%s) to 1 item.", apply_mode)
  r.Main_OnCommand(cmd, 0)
end

------------------------------------------------------------
-- GLUE FLOW (per unit)
------------------------------------------------------------
local function glue_unit(tr, u, cfg)
  local DBG    = cfg.DEBUG_LEVEL or 1
  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0
  local eps_s  = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  -- 📝 先蒐集 take-marker（存「絕對位置」），之後 Glue 完再換算成相對 UL
  local marks_abs = nil
  if cfg.WRITE_TAKE_MARKERS and u.kind ~= "SINGLE" then
    marks_abs = {}
    for _, m in ipairs(u.members or {}) do
      local tname = get_take_name(m.it) or ""
      marks_abs[#marks_abs+1] = { abs = m.L, label = ("Glue: %s"):format(tname) }
    end
  end

  -- 保存左右邊界淡入淡出（之後還原）
  local members = {}
  for i,m in ipairs(u.members) do members[i]=m end
  local first_it = members[1] and members[1].it or nil
  local last_it  = members[#members] and members[#members].it or nil

  local fin_len, fin_dir, fin_shape, fin_auto = 0,0,0,0
  local fout_len, fout_dir, fout_shape, fout_auto = 0,0,0,0
  if first_it then
    fin_len   = r.GetMediaItemInfo_Value(first_it,"D_FADEINLEN") or 0
    fin_dir   = r.GetMediaItemInfo_Value(first_it,"D_FADEINDIR") or 0
    fin_shape = r.GetMediaItemInfo_Value(first_it,"C_FADEINSHAPE") or 0
    fin_auto  = r.GetMediaItemInfo_Value(first_it,"D_FADEINLEN_AUTO") or 0
  end
  if last_it then
    fout_len   = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTLEN") or 0
    fout_dir   = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTDIR") or 0
    fout_shape = r.GetMediaItemInfo_Value(last_it,"C_FADEOUTSHAPE") or 0
    fout_auto  = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTLEN_AUTO") or 0
  end

  -- 計算 UL/UR（handles + clamp）
  local UL, UR = math.huge, -math.huge
  local details = {}
  for idx, m in ipairs(members) do
    local H_left  = (idx==1) and HANDLE or 0.0
    local H_right = (idx==#members) and HANDLE or 0.0
    local d = per_member_window_lr(m.it, m.L, m.R, H_left, H_right)
    UL = math.min(UL, d.gotL)
    UR = math.max(UR, d.gotR)
    details[idx] = d
  end

  dbg(DBG,1,"[RUN] unit kind=%s members=%d UL=%.3f UR=%.3f dur=%.3f", u.kind,#members,UL,UR,UR-UL)
  if DBG>=2 then
    for i,d in ipairs(details) do
      dbg(DBG,2,"       member#%d want=%.3f..%.3f -> got=%.3f..%.3f  clampL=%s clampR=%s  name=%s",
        i, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), d.name or "(none)")
    end
  end

  -- RENDER_TAKE_FX=0 → 先清空成員的 take FX（避免被 Glue 印入）
  if not cfg.RENDER_TAKE_FX then
    local items = {}
    for i,m in ipairs(members) do items[i]=m.it end
    clear_take_fx_for_items(items)
    dbg(DBG,1,"[TAKE-FX] cleared (policy=OFF) for this unit.")
  end

  -- 寫 #in/#out（以 unit 實際 span）
  local hash_ids = nil
  if cfg.WRITE_MEDIA_CUES then
    hash_ids = add_hash_markers(u.start, u.finish, 0)
    dbg(DBG,1,"[HASH] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", u.start, u.finish, tostring(hash_ids[1]), tostring(hash_ids[2]))
  end

  -- 選取並暫時把左右最外側 item 撐到 UL/UR 以吃到 handles
  local items_sel = {}
  for i,m in ipairs(members) do items_sel[i]=m.it end
  select_only_items(items_sel)

  for idx, m in ipairs(members) do
    local it = m.it
    local d  = details[idx]
    local newL = (idx==1) and d.gotL or m.L
    local newR = (idx==#members) and d.gotR or m.R
    r.SetMediaItemInfo_Value(it,"D_POSITION", newL)
    r.SetMediaItemInfo_Value(it,"D_LENGTH",   newR - newL)
    if d.tk then
      local deltaL  = (m.L - newL)
      local new_off = d.offs - (deltaL * d.rate)
      r.SetMediaItemTakeInfo_Value(d.tk,"D_STARTOFFS", new_off)
    end
    r.UpdateItemInProject(it)
  end

  -- 時選=UL..UR → Glue → (必要時)對成品 Apply → Trim 回 UL..UR
  r.GetSet_LoopTimeRange(true, false, UL, UR, false)
  r.Main_OnCommand(ACT_GLUE_TS, 0)

  local glued_pre = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if cfg.RENDER_TRACK_FX and glued_pre then
    -- NOTE: 40361/41993 will print fades into audio; clear them on the
    -- intermediate glued item, then rebuild edge fades later on final 'glued'.
    -- 40361 Item: Apply track/take FX to items (mono output)
    -- 41993 Item: Apply track/take FX to items (multichannel output)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN",       0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN_AUTO",  0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN",      0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN_AUTO", 0)
    r.UpdateItemInProject(glued_pre)

    apply_track_take_fx_to_item(glued_pre, cfg.APPLY_FX_MODE, DBG)
  end
  r.Main_OnCommand(ACT_TRIM_TO_TS, 0)

  -- 找到最後成品（UL..UR），移回 u.start..u.finish 並寫入 offset
  local glued = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if glued then
    local left_total  = u.start - UL
    local right_total = UR - u.finish
    if left_total  < 0 then left_total  = 0 end
    if right_total < 0 then right_total = 0 end

    r.SetMediaItemInfo_Value(glued,"D_POSITION", u.start)
    r.SetMediaItemInfo_Value(glued,"D_LENGTH",   u.finish - u.start)
    local gtk = r.GetActiveTake(glued)
    if gtk then r.SetMediaItemTakeInfo_Value(gtk,"D_STARTOFFS", left_total) end
    r.UpdateItemInProject(glued)

    -- 還原邊界淡入淡出
    r.SetMediaItemInfo_Value(glued,"D_FADEINLEN",      fin_len)
    r.SetMediaItemInfo_Value(glued,"D_FADEINDIR",      fin_dir)
    r.SetMediaItemInfo_Value(glued,"C_FADEINSHAPE",    fin_shape)
    r.SetMediaItemInfo_Value(glued,"D_FADEINLEN_AUTO", fin_auto)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTLEN",      fout_len)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTDIR",      fout_dir)
    r.SetMediaItemInfo_Value(glued,"C_FADEOUTSHAPE",    fout_shape)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTLEN_AUTO", fout_auto)
    r.UpdateItemInProject(glued)

    -- ✅ 在「插入位置 B」：Glue 後、已拿到 UL 與 glued
    if cfg.WRITE_TAKE_MARKERS and u.kind ~= "SINGLE" and marks_abs and #marks_abs>0 then
      for _, mk in ipairs(marks_abs) do
        local rel = (mk.abs or u.start) - UL   -- UL 為 take 的 0 秒
        add_take_marker_at(glued, rel, mk.label)
      end
    end

    -- 重新命名
    local flags = { takePrinted=cfg.RENDER_TAKE_FX, trackPrinted=cfg.RENDER_TRACK_FX }
    local oldn  = get_take_name(glued)
    local op    = (cfg.RENAME_OP_MODE=="auto") and "glue" or cfg.RENAME_OP_MODE
    local newn  = compute_new_name(op, oldn, flags)
    set_take_name(glued, newn)

    dbg(DBG,1,"       post-glue: trimmed to [%.3f..%.3f], offs=%.3f (L=%.3f R=%.3f)  name='%s' → '%s'",
      u.start, u.finish, left_total, left_total, right_total, oldn or "", newn or "")
  else
    dbg(DBG,1,"       WARNING: glued item not found by span (UL=%.3f UR=%.3f)", UL, UR)
  end

  -- 清掉時選與 # 標記
  r.GetSet_LoopTimeRange(true, false, 0, 0, false)
  if hash_ids then
    remove_markers_by_ids(hash_ids)
    dbg(DBG,1,"[HASH] removed ids: %s, %s", tostring(hash_ids[1]), tostring(hash_ids[2]))
  end
end

------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------
function M.glue_selection()
  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.ClearConsole()

  local nsel = count_selected_items()
  if nsel==0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Glue (no selection)", -1); return
  end

  local eps_s = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)
  dbg(DBG,1,"[RUN] Glue start  handles=%.3fs  epsilon=%.5fs  GLUE_SINGLE_ITEMS=%s  RENDER_TAKE_FX=%s  RENDER_TRACK_FX=%s  APPLY_FX_MODE=%s  WRITE_MEDIA_CUES=%s  WRITE_TAKE_MARKERS=%s",
    cfg.HANDLE_SECONDS or 0, eps_s, tostring(cfg.GLUE_SINGLE_ITEMS), tostring(cfg.RENDER_TAKE_FX),
    tostring(cfg.RENDER_TRACK_FX), cfg.APPLY_FX_MODE, tostring(cfg.WRITE_MEDIA_CUES), tostring(cfg.WRITE_TAKE_MARKERS))

  local by_tr, tr_list = collect_by_track_from_selection()
  for _,tr in ipairs(tr_list) do
    local list  = by_tr[tr]
    local units = detect_units_same_track(list, eps_s)
    dbg(DBG,1,"[RUN] Track #%d: units=%d", r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1, #units)
    for ui,u in ipairs(units) do
      if u.kind=="SINGLE" and (not cfg.GLUE_SINGLE_ITEMS) then
        dbg(DBG,2,"[TRACE] unit#%d SINGLE skipped (option off).", ui)
      else
        glue_unit(tr, u, cfg)
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("RGWH Core - Glue selection", -1)
end

function M.render_selection()
  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1
  local items = get_sel_items()
  local nsel  = #items
  local r = reaper

  -- helpers (local to this function) -----------------------------------------
  local function snapshot_takefx_offline(tk)
    local n = r.TakeFX_GetCount(tk) or 0
    local snap = {}
    for i = 0, n-1 do snap[i] = r.TakeFX_GetOffline(tk, i) and true or false end
    return snap
  end

  -- set offline only for FX that were online; leave originally-offline FX intact
  local function temp_offline_nonoffline_fx(tk)
    local n = r.TakeFX_GetCount(tk) or 0
    local cnt = 0
    for i = 0, n-1 do
      if not r.TakeFX_GetOffline(tk, i) then
        r.TakeFX_SetOffline(tk, i, true)
        cnt = cnt + 1
      end
    end
    return cnt
  end

  local function restore_takefx_offline(tk, snap)
    if not (tk and snap) then return 0 end
    local n = r.TakeFX_GetCount(tk) or 0
    local cnt = 0
    for i = 0, n-1 do
      local want = snap[i]
      if want ~= nil then
        r.TakeFX_SetOffline(tk, i, want and true or false)
        cnt = cnt + 1
      end
    end
    return cnt
  end
  -----------------------------------------------------------------------------

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.ClearConsole()

  if nsel == 0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Render (no selection)", -1); return
  end

  local eps_s = (cfg.EPSILON_MODE=="frames")
                  and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil)
                  or (cfg.EPSILON_VALUE or 0.002)
  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0

  dbg(DBG,1,"[RUN] Render start  mode=%s  TAKE=%s TRACK=%s  items=%d  handles=%.3fs  WRITE_MEDIA_CUES=%s",
      cfg.APPLY_FX_MODE, tostring(cfg.RENDER_TAKE_FX), tostring(cfg.RENDER_TRACK_FX),
      nsel, HANDLE, tostring(cfg.WRITE_MEDIA_CUES))

  -- snapshot per-track FX enabled state (TRACK path has been stable)
  local tr_map = {}
  for _, it in ipairs(items) do
    local tr = r.GetMediaItem_Track(it)
    if tr and not tr_map[tr] then
      local fxn = r.TrackFX_GetCount(tr) or 0
      local rec = { track = tr, enabled = {} }
      for i = 0, fxn-1 do rec.enabled[i] = r.TrackFX_GetEnabled(tr, i) end
      tr_map[tr] = rec
    end
  end

  local need_disable_track = (not cfg.RENDER_TRACK_FX)
  if need_disable_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      local fxn = r.TrackFX_GetCount(tr) or 0
      for i = 0, fxn-1 do r.TrackFX_SetEnabled(tr, i, false) end
    end
    dbg(DBG,1,"[RUN] Temporarily disabled TRACK FX (policy TRACK=0).")
  end

  -- 40361/41993 = Item: Apply track/take FX to items (mono/multichannel) 會把 fades 一起烘進音檔
  -- 40601       = Item: Render items to new take (preserve source type) 不會烘入 fades、也不會印 Track FX
  local apply_cmd = get_apply_cmd(cfg)  -- 40361 or 41993（看 cfg.APPLY_FX_MODE）


  for _, it in ipairs(items) do
    -- keep a handle to the original active take (pre-render)
    local tk_orig = r.GetActiveTake(it)
    local orig_name = ""
    if tk_orig then
      _, orig_name = r.GetSetMediaItemTakeInfo_String(tk_orig, "P_NAME", "", false)
    end

    -- per-item: temporarily offline non-offline take FX when TAKE FX are excluded
    local snap_off = nil
    if tk_orig and not cfg.RENDER_TAKE_FX then
      snap_off = snapshot_takefx_offline(tk_orig)
      local n_off = temp_offline_nonoffline_fx(tk_orig)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] temp-offline %d FX on '%s'", n_off, orig_name) end
    end

    local L0, R0 = item_span(it)
    local name0  = get_take_name(it) or ""
    local d      = per_member_window_lr(it, L0, R0, HANDLE, HANDLE)

    if DBG >= 2 then
      dbg(DBG,2,"[REN] item@%.3f..%.3f want=%.3f..%.3f -> got=%.3f..%.3f clampL=%s clampR=%s name=%s",
          L0, R0, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), name0)
    end

    local hash_ids = nil
    if cfg.WRITE_MEDIA_CUES then
      hash_ids = add_hash_markers(L0, R0, 0)
      dbg(DBG,1,"[HASH] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", L0, R0, tostring(hash_ids and hash_ids[1]), tostring(hash_ids and hash_ids[2]))
    end

    -- move to render window and align take offset
    r.SetMediaItemInfo_Value(it, "D_POSITION", d.gotL)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   d.gotR - d.gotL)
    if d.tk then
      local deltaL  = (L0 - d.gotL)
      local new_off = d.offs - (deltaL * d.rate)
      r.SetMediaItemTakeInfo_Value(d.tk, "D_STARTOFFS", new_off)
    end
    r.UpdateItemInProject(it)

    -- render:
    -- 若需要印 TRACK FX -> 用 40361/41993（會把 fades 烘進音檔），所以先 snapshot/清零，再還原
    -- 若不需要印 TRACK FX -> 用 40601（不會烘入 fades，且只印 Take FX），無須處理 fades
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(it, true)
    r.UpdateArrange()

    if cfg.RENDER_TRACK_FX then
      -- 使用 40361/41993：Apply track/take FX to items（mono/multi）→ 會把 fades 一併 render
      local f_snap = snapshot_fades(it)
      zero_fades(it)
      r.Main_OnCommand(apply_cmd, 0)  -- ← 40361 或 41993
      restore_fades(it, f_snap)
    else
      -- 使用 40601：Render items to new take (preserve source type)
      -- 不會烘入 fades、也不會印 Track FX；若 TAKE FX=0，本函式已暫時 offline 掉 take FX
      r.Main_OnCommand(40601, 0)
    end


    if hash_ids then
      remove_markers_by_ids(hash_ids)
      dbg(DBG,1,"[HASH] removed ids: %s, %s", tostring(hash_ids[1]), tostring(hash_ids[2]))
    end

    -- restore item window and offset
    local left_total = L0 - d.gotL
    if left_total < 0 then left_total = 0 end
    r.SetMediaItemInfo_Value(it, "D_POSITION", L0)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   R0 - L0)
    local newtk = r.GetActiveTake(it)  -- now the freshly rendered take
    if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_STARTOFFS", left_total) end
    r.UpdateItemInProject(it)

    -- gain: merge pre-render item vol into all older takes; then normalize item & new take
    local pre_item_vol = r.GetMediaItemInfo_Value(it, "D_VOL") or 1.0
    if pre_item_vol and math.abs(pre_item_vol - 1.0) > 1e-9 then
      local nt = r.GetMediaItemNumTakes(it) or 0
      local merged = 0
      for ti = 0, nt-1 do
        local tk = r.GetTake(it, ti)
        if tk and tk ~= newtk then
          local tkvol = r.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1.0
          r.SetMediaItemTakeInfo_Value(tk, "D_VOL", tkvol * pre_item_vol)
          merged = merged + 1
        end
      end
      if DBG >= 2 then dbg(DBG,2,"[GAIN] merged pre itemVol=%.3f into %d older take(s)", pre_item_vol, merged) end
    end
    r.SetMediaItemInfo_Value(it, "D_VOL", 1.0)
    if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_VOL", 1.0) end

    -- rename only the new rendered take
    rename_new_render_take(
      it,
      orig_name,
      cfg.RENDER_TAKE_FX == true,
      cfg.RENDER_TRACK_FX == true,
      DBG
    )

    -- restore the original take's offline snapshot (do not touch bypass/enabled)
    if tk_orig and snap_off then
      local n_rest = restore_takefx_offline(tk_orig, snap_off)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] restored %d FX on '%s'", n_rest, orig_name) end
    end
  end

  -- restore TRACK FX enabled states if we disabled them
  if need_disable_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      for fx, was_on in pairs(rec.enabled) do
        r.TrackFX_SetEnabled(tr, fx, was_on and true or false)
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("RGWH Core - Render (Apply FX per item w/ handles)", -1)
end


return M
