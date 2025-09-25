--[[
@description Render or Glue Items with Handles Core Library
@version 250925_1546 REBDER_TC_EMBED OK
@author hsuanice
@about
  Library for RGWH glue/render flows with handles, FX policies, rename, # markers, and optional take markers inside glued items.

@changelog
v250925_1546 REBDER_TC_EMBED OK
  - Added: ExtState key `RENDER_TC_EMBED` ("previous" | "current" | "off") to control
    TimeReference embedding policy during render.
      • "previous" (default): embed TimeReference from the original take (handle-aware).
      • "current": embed TimeReference from current project position (item start).
      • "off": disable TimeReference embedding (skip write).
  - Fixed: initialization order — `DEFAULTS.RENDER_TC_EMBED` is now a static value
    ("previous"); actual project-scope ExtState is read inside `read_settings()`.
  - Updated: `render_selection()` now calls Metadata Embed library functions
    (`TR_PrevToActive`, `TR_FromItemStart`, `TR_Write`) according to mode.
  - Behavior: batch refresh of items after TR write remains intact.

v250925_1101 change "force-multi" to "force_multi"
v250922_2257
  - Multi-mode policies finalized:
    • GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve" | "force_multi"
    • RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve" | "force_multi"
  - When APPLY_MODE="multi"-
   and policy="force_multi" with no Track FX printing:
    • Glue: run 41993 in a no-track-FX path; preserves take-FX per setting; fades snapshot/restore
    • Render: choose apply path and run 41993; fades snapshot/restore
  - New helper: apply_multichannel_no_fx_preserve_take(it, keep_take_fx, dbg_level)
    • Temporarily disables track FX (snapshot), optionally offlines take FX, zeroes fades, runs 41993, restores everything
  - Render path: add use_apply decision (need_track OR force_multi) with clear fades only when applying
  - Console messages:
    • "[APPLY] force multi (no track FX path)"
    • "[RUN] Temporarily disabled TRACK FX (policy TRACK=0)."
  - Minor: ensure "[EDGE-CUE]" tag consistent across add/remove logs

v250922_1954
  - Prep multi-channel flow: utilities and structure for using 41993 (Apply track/take FX to items – multichannel output)
  - Separated paths for GLUE vs RENDER to allow later policy injection without changing call sites

v250922_1819
  - Rename WRITE_MEDIA_CUES → WRITE_EDGE_CUES
  - Rename WRITE_TAKE_MARKERS → WRITE_GLUE_CUES
  - Standardize: hash_ids → edge_ids; function add_hash_markers → add_edge_cues
  - Console tag "[HASH]" → "[EDGE-CUE]"
  - Glue Cue labels simplified: "#Glue: <TakeName>" (remove redundant "GlueCue:" prefix)
  - TakeName preserved with original case (no forced lowercase)
  - Final: Edge Cues (#in/#out) and Glue Cues (#Glue: <TakeName>) both embedded as media cues

v250921_1732
  - Implement Glue Cues: add cues at unit head + where adjacent sources differ
  - Glue Cues written as project markers with '#' prefix → embedded into glued media
  - Edge Cues (#in/#out) and Glue Cues temporarily added then cleaned up
  - Console output: [HASH] for edge cues, [GLUE-CUE] for glue cues

v250921_1647
  - First experiment: replace take markers with media cues (#in/#out written as project markers)
  - Console shows [HASH] add/remove; cues absorbed into glued media

v250921_1512
  - Initial stable Core snapshot (handles, epsilon, glue/render pipeline, hash markers)

]]--
local r = reaper
local M = {}

-- Load Metadata Embed Library (single source of truth for TR math)
local RES_PATH = r.GetResourcePath()
local E = dofile(RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Embed.lua')

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
  -- FX policies (separate for GLUE vs RENDER)
  GLUE_TAKE_FX       = 1,             -- 1=Glue 之後的成品要印入 take FX；0=不印入
  GLUE_TRACK_FX      = 0,             -- 1=Glue 成品再套用 Track/Take FX
  GLUE_APPLY_MODE    = "mono",        -- "mono" | "multi"（給 Glue 後的 apply 用）

  RENDER_TAKE_FX     = 0,             -- 1=Render 直接印入 take FX；0=保留（偏向 non-destructive）
  RENDER_TRACK_FX    = 0,             -- 1=Render 同時印入 Track FX
  RENDER_APPLY_MODE  = "mono",        -- "mono" | "multi"（Render 使用的 apply 模式）
  RENDER_TC_EMBED    = "previous",    -- TR embed mode for render: "previous" | "current" | "off"
  -- Rename policy:
  RENAME_OP_MODE     = "auto",        -- glue | render | auto
  -- Hash markers（#in/#out 以供 Media Cues）
  WRITE_EDGE_CUES   = 1,
  -- ✅ 新增：Glue 成品 take 內是否加 take markers（非 SINGLE 才加）
  WRITE_GLUE_CUES = 1,

  -- Policies when TRACK FX are NOT being printed:
  GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX   = "preserve",   -- "preserve" | "force_multi"
  RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve",   -- "preserve" | "force_multi"
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
    GLUE_TAKE_FX       = (get_ext_bool("GLUE_TAKE_FX",      DEFAULTS.GLUE_TAKE_FX)==1),
    GLUE_TRACK_FX      = (get_ext_bool("GLUE_TRACK_FX",     DEFAULTS.GLUE_TRACK_FX)==1),
    GLUE_APPLY_MODE    =  get_ext("GLUE_APPLY_MODE",        DEFAULTS.GLUE_APPLY_MODE),

    RENDER_TAKE_FX     = (get_ext_bool("RENDER_TAKE_FX",    DEFAULTS.RENDER_TAKE_FX)==1),
    RENDER_TRACK_FX    = (get_ext_bool("RENDER_TRACK_FX",   DEFAULTS.RENDER_TRACK_FX)==1),
    RENDER_APPLY_MODE  =  get_ext("RENDER_APPLY_MODE",      DEFAULTS.RENDER_APPLY_MODE),
    -- TR embed mode for Render: "previous" | "current" | "off"
    RENDER_TC_EMBED    = get_ext("RENDER_TC_EMBED", "previous"),
    RENAME_OP_MODE     = get_ext("RENAME_OP_MODE",           DEFAULTS.RENAME_OP_MODE),
    WRITE_EDGE_CUES    = (get_ext_bool("WRITE_EDGE_CUES",   DEFAULTS.WRITE_EDGE_CUES)==1),
    -- 🔧 修正：用 DEFAULTS，不是 dflt
    WRITE_GLUE_CUES    = (get_ext_bool("WRITE_GLUE_CUES", DEFAULTS.WRITE_GLUE_CUES)==1),

    GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX   = get_ext("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX",   DEFAULTS.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX),
    RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = get_ext("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", DEFAULTS.RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX),
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

  -- New take is appended last (usually becomes active)
  local newtk = reaper.GetTake(it, tc-1)
  if not newtk then return end

  -- Current new-take name (only for logging)
  local _, curNewName = reaper.GetSetMediaItemTakeInfo_String(newtk, "P_NAME", "", false)

  -- Base = old take name without any tail tags and without extension
  local baseOld = strip_tail_tags(select(1, split_ext(orig_take_name or "")))

  -- N = max existing rendered index on this item + 1
  local nextN = max_rendered_n_on_item(it) + 1

  -- Final rule: TakeName-renderedN  (no -takefx/-trackfx, no extension)
  local newname = string.format("%s-rendered%d", baseOld, nextN)

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
-- #in/#out edge cues (kept for media-cue workflows)
------------------------------------------------------------
local function add_edge_cues(UL, UR, color)
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

--[[
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
]]--

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
  local cmd = get_apply_cmd(apply_mode)
  dbg(dbg_level,1,"[RUN] Apply Track/Take FX (%s) to 1 item.", apply_mode)
  r.Main_OnCommand(cmd, 0)
end

-- Disable all TRACK FX on a track and return a snapshot of enabled states
local function disable_trackfx_with_snapshot(tr)
  if not tr then return nil end
  local n = r.TrackFX_GetCount(tr) or 0
  local snap = {}
  for i = 0, n-1 do
    local on = r.TrackFX_GetEnabled(tr, i)
    snap[i] = on and true or false
    if on then r.TrackFX_SetEnabled(tr, i, false) end
  end
  return snap
end

local function restore_trackfx_from_snapshot(tr, snap)
  if not (tr and snap) then return end
  for i, on in pairs(snap) do r.TrackFX_SetEnabled(tr, i, on and true or false) end
end

-- Apply multichannel (41993) WITHOUT baking any TRACK FX, and only bake TAKE FX when keep_take_fx=true
local function apply_multichannel_no_fx_preserve_take(it, keep_take_fx, dbg_level)
  if not it then return end
  local tr = r.GetMediaItem_Track(it)
  local tk = r.GetActiveTake(it)

  local tr_snap = disable_trackfx_with_snapshot(tr)
  local tk_snap = snapshot_takefx_offline(tk)
  if tk and (not keep_take_fx) then
    temp_offline_nonoffline_fx(tk)
  end

  local fade_snap = snapshot_fades(it)
  zero_fades(it)

  r.SelectAllMediaItems(0,false)
  r.SetMediaItemSelected(it,true)
  dbg(dbg_level,1,"[APPLY] multi(no-FX) via 41993 (keep_take_fx=%s)", tostring(keep_take_fx))
  r.Main_OnCommand(ACT_APPLY_MULTI, 0)

  -- restore states
  restore_trackfx_from_snapshot(tr, tr_snap)
  restore_takefx_offline(tk, tk_snap)
  restore_fades(it, fade_snap)
end
------------------------------------------------------------
-- GLUE FLOW (per unit)
------------------------------------------------------------
local function glue_unit(tr, u, cfg)
  local DBG    = cfg.DEBUG_LEVEL or 1
  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0
  local eps_s  = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  -- Prepare Glue Cues plan (absolute project times).
  -- Rule: write a cue only when adjacent items switch to a different file source.
  -- If the whole unit uses a single source, write none (including the head).
  local marks_abs = nil
  if u.kind ~= "SINGLE" then
    -- Build ordered source sequence for this unit
    local function src_path_of(it)
      local tk  = reaper.GetActiveTake(it)
      if not tk then return nil end
      local src = reaper.GetMediaItemTake_Source(tk)
      if not src then return nil end
      local p   = reaper.GetMediaSourceFileName(src, "") or ""
      p = p:gsub("\\","/"):gsub("^%s+",""):gsub("%s+$","")
      return (p ~= "") and p or nil
    end

    local function take_name_of(it)
      local tk = reaper.GetActiveTake(it)
      if not tk then return nil end
      local ok, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
      return (ok and nm ~= "" and nm) or reaper.GetTakeName(tk) or nil
    end
    local seq, uniq = {}, {}
    for _, m in ipairs(u.members or {}) do
      local p = src_path_of(m.it) or ("<no-src>")
      seq[#seq+1] = { L = m.L, path = p }
      uniq[p] = true
    end
    local unique_count = 0
    for _ in pairs(uniq) do unique_count = unique_count + 1 end

    if unique_count >= 2 then
      marks_abs = {}
      -- Head cue uses TakeName (preserve original case)
      local head_name = take_name_of(u.members[1].it) or ((seq[1].path or ""):match("([^/]+)$") or "")
      marks_abs[#marks_abs+1] = { abs = u.start, name = head_name }

      -- Boundary cues where source changes
      for i = 1, (#seq - 1) do
        if seq[i].path ~= seq[i+1].path then
          local next_name = take_name_of(u.members[i+1].it) or ((seq[i+1].path or ""):match("([^/]+)$") or "")
          marks_abs[#marks_abs+1] = { abs = seq[i+1].L, name = next_name }
        end
      end
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
  if not cfg.GLUE_TAKE_FX then
    local items = {}
    for i,m in ipairs(members) do items[i]=m.it end
    clear_take_fx_for_items(items)
    dbg(DBG,1,"[TAKE-FX] cleared (policy=OFF) for this unit.")
  end

  -- Write #in/#out (unit span) as media cues when enabled
  local edge_ids = nil
  if cfg.WRITE_EDGE_CUES then
    edge_ids = add_edge_cues(u.start, u.finish, 0)
    dbg(DBG,1,"[EDGE-CUE] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", u.start, u.finish, tostring(edge_ids[1]), tostring(edge_ids[2]))
  end

  -- When enabled, pre-embed Glue Cues as project markers (with '#' prefix).
  -- They will be absorbed into the new media during glue.
  -- Pre-embed Glue cues as project markers (with '#') so glue absorbs them into media
  local glue_ids = nil
  if cfg.WRITE_GLUE_CUES and u.kind ~= "SINGLE" and marks_abs and #marks_abs > 0 then
    glue_ids = {}
    for _, mk in ipairs(marks_abs) do
      local raw = mk.name or mk.stem or mk.label or ""
      raw = raw:gsub("^%s*GlueCue:%s*", "")  -- strip legacy prefix if any
      local label = ("#Glue: %s"):format(raw)
      local id = reaper.AddProjectMarker2(0, false, mk.abs or u.start, 0, label, -1, 0)
      glue_ids[#glue_ids+1] = id
      if DBG >= 2 then dbg(DBG,2,"[GLUE-CUE] add @ %.3f  label=%s  id=%s", mk.abs or u.start, label, tostring(id)) end
    end
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
  end

  -- 時選=UL..UR → Glue → (必要時)對成品 Apply → Trim 回 UL..UR
  r.GetSet_LoopTimeRange(true, false, UL, UR, false)
  r.Main_OnCommand(ACT_GLUE_TS, 0)

  local glued_pre = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if cfg.GLUE_TRACK_FX and glued_pre then
    -- 清掉 fades（40361/41993 會把 fade 烘進音檔）
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN",       0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN_AUTO",  0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN",      0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN_AUTO", 0)

    apply_track_take_fx_to_item(glued_pre, cfg.GLUE_APPLY_MODE, DBG)

  elseif glued_pre
     and (cfg.GLUE_APPLY_MODE == "multi")
     and (cfg.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi") then
    -- TRACK FX 未印，但需要強制 multi：以「無 FX」方式套 41993
    apply_multichannel_no_fx_preserve_take(glued_pre, (cfg.GLUE_TAKE_FX == true), DBG)
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

    -- (Removed legacy take-marker emission. Glue cues are now pre-written as project markers with '#'.)


    -- [GLUE NAME] Do not rename glued items; let REAPER auto-name (e.g. "...-glued-XX").
    -- (Intentionally no-op here to preserve REAPER's default glued naming.)
    -- dbg(DBG,2,"[NAME] Skip renaming glued item; keep REAPER's default.")


    dbg(DBG,1,"       post-glue: trimmed to [%.3f..%.3f], offs=%.3f (L=%.3f R=%.3f)",
      u.start, u.finish, left_total, left_total, right_total)
  else
    dbg(DBG,1,"       WARNING: glued item not found by span (UL=%.3f UR=%.3f)", UL, UR)
  end

  -- Clear time selection and temporary project markers
  r.GetSet_LoopTimeRange(true, false, 0, 0, false)
  if edge_ids then
    remove_markers_by_ids(edge_ids)
    dbg(DBG,1,"[EDGE-CUE] removed ids: %s, %s", tostring(edge_ids[1]), tostring(edge_ids[2]))
  end
  if glue_ids and #glue_ids>0 then
    remove_markers_by_ids(glue_ids)
    dbg(DBG,1,"[GLUE-CUE] removed %d temp markers.", #glue_ids)
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
  dbg(DBG,1,"[RUN] Glue start  handles=%.3fs  epsilon=%.5fs  GLUE_SINGLE_ITEMS=%s  GLUE_TAKE_FX=%s  GLUE_TRACK_FX=%s  GLUE_APPLY_MODE=%s  WRITE_EDGE_CUES=%s  WRITE_GLUE_CUES=%s  GLUE_CUE_POLICY=%s",
    cfg.HANDLE_SECONDS or 0, eps_s, tostring(cfg.GLUE_SINGLE_ITEMS), tostring(cfg.GLUE_TAKE_FX),
    tostring(cfg.GLUE_TRACK_FX), cfg.GLUE_APPLY_MODE, tostring(cfg.WRITE_EDGE_CUES), tostring(cfg.WRITE_GLUE_CUES),
    "adjacent-different-source")


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
    if not tk then return nil end
    local n = r.TakeFX_GetCount(tk) or 0
    local snap = {}
    for i = 0, n-1 do snap[i] = r.TakeFX_GetOffline(tk, i) and true or false end
    return snap
  end

  -- temporarily set offline=true ONLY for FX that were online
  local function temp_offline_nonoffline_fx(tk)
    if not tk then return 0 end
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

  -- clone whole take-FX chain (states included) from src to dst
  local function clone_takefx_chain(src_tk, dst_tk)
    if not (src_tk and dst_tk) or src_tk == dst_tk then return 0 end
    -- clear dst first to avoid duplicates
    for i = (r.TakeFX_GetCount(dst_tk) or 0)-1, 0, -1 do r.TakeFX_Delete(dst_tk, i) end
    local n = r.TakeFX_GetCount(src_tk) or 0
    for i = 0, n-1 do r.TakeFX_CopyToTake(src_tk, i, dst_tk, i, false) end
    return n
  end

  -- fade helpers (shared with GLUE)
  -- snapshot_fades(it) -> table
  -- zero_fades(it)
  -- restore_fades(it, snap)
  -----------------------------------------------------------------------------

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.ClearConsole()

  if nsel == 0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Render (no selection)", -1); return
  end

  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0

  dbg(DBG,1,"[RUN] Render start  mode=%s  TAKE=%s TRACK=%s  items=%d  handles=%.3fs  WRITE_EDGE_CUES=%s  GLUE_CUE_POLICY=%s",
      cfg.RENDER_APPLY_MODE, tostring(cfg.RENDER_TAKE_FX), tostring(cfg.RENDER_TRACK_FX),
      nsel, HANDLE, tostring(cfg.WRITE_EDGE_CUES), "adjacent-different-source")

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

  local need_track = (cfg.RENDER_TRACK_FX == true)
  local need_take  = (cfg.RENDER_TAKE_FX  == true)

  if not need_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      local fxn = r.TrackFX_GetCount(tr) or 0
      for i = 0, fxn-1 do r.TrackFX_SetEnabled(tr, i, false) end
    end
    dbg(DBG,1,"[RUN] Temporarily disabled TRACK FX (policy TRACK=0).")
  end

  -- pick render command
  local ACT_APPLY_MONO  = 40361 -- Apply track/take FX to items (mono)
  local ACT_APPLY_MULTI = 41993 -- Apply track/take FX to items (multichannel)
  local ACT_RENDER_PRES = 40601 -- Render items to new take (preserve source type)
  local cmd_apply = (cfg.RENDER_APPLY_MODE=="multi") and ACT_APPLY_MULTI or ACT_APPLY_MONO

  for _, it in ipairs(items) do
    local tk_orig = r.GetActiveTake(it)
    local orig_name = ""
    if tk_orig then
      _, orig_name = r.GetSetMediaItemTakeInfo_String(tk_orig, "P_NAME", "", false)
    end
    -- snapshot original StartInSource (seconds) before we stretch window
    local orig_startoffs_sec = tk_orig and (r.GetMediaItemTakeInfo_Value(tk_orig, "D_STARTOFFS") or 0.0) or nil

    -- When TAKE FX are excluded, temporarily offline only those that were online.
    local snap_off = nil
    if tk_orig and (not need_take) then
      snap_off = snapshot_takefx_offline(tk_orig)
      local n_off = temp_offline_nonoffline_fx(tk_orig)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] temp-offline %d FX on '%s'", n_off, orig_name) end
    end

    -- >>>> NEW: pre-merge item volume into ALL takes' take volume (one-time) <<<<
    -- so the render bakes the correct gain and both item & new take end up at 0 dB.
    do
      local item_vol = r.GetMediaItemInfo_Value(it, "D_VOL") or 1.0
      if math.abs(item_vol - 1.0) > 1e-9 then
        local nt = r.GetMediaItemNumTakes(it) or 0
        local merged = 0
        for ti = 0, nt-1 do
          local tk = r.GetTake(it, ti)
          if tk then
            local tv = r.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1.0
            r.SetMediaItemTakeInfo_Value(tk, "D_VOL", tv * item_vol)
            merged = merged + 1
          end
        end
        r.SetMediaItemInfo_Value(it, "D_VOL", 1.0)
        if DBG >= 2 then dbg(DBG,2,"[GAIN] pre-merged itemVol=%.3f into %d take(s)", item_vol, merged) end
      end
    end

    local L0, R0 = item_span(it)
    local name0  = get_take_name(it) or ""
    local d      = per_member_window_lr(it, L0, R0, HANDLE, HANDLE)

    if DBG >= 2 then
      dbg(DBG,2,"[REN] item@%.3f..%.3f want=%.3f..%.3f -> got=%.3f..%.3f clampL=%s clampR=%s name=%s",
          L0, R0, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), name0)
    end

    local edge_ids = nil
    if cfg.WRITE_EDGE_CUES then
      -- Keep #in/#out (unit span) for downstream media-cue workflows.
      edge_ids = add_edge_cues(L0, R0, 0)
      dbg(DBG,1,"[EDGE-CUE] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", L0, R0, tostring(edge_ids and edge_ids[1]), tostring(edge_ids and edge_ids[2]))
    end


    -- move to render window and align take offset
    r.SetMediaItemInfo_Value(it, "D_POSITION", d.gotL)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   d.gotR - d.gotL)
    if d.tk then
      local deltaL  = (L0 - d.gotL)
      local new_off = d.offs - (deltaL * d.rate)
      r.SetMediaItemTakeInfo_Value(d.tk, "D_STARTOFFS", new_off)
    end

    -- If we are going to apply TRACK FX (01/11), or we are forcing multi without TRACK FX,
    -- clear fades (40361/41993 will bake them). Otherwise (00/10 => 40601) keep fades.
    local fade_snap = nil
    local force_multi = (not need_track)
                    and (cfg.RENDER_APPLY_MODE == "multi")
                    and (cfg.RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi")

    local use_apply = (need_track == true) or (force_multi == true)
    if use_apply then
      if force_multi then
        dbg(DBG,1,"[APPLY] force multi (no track FX path)")
      end
      fade_snap = snapshot_fades(it)
      zero_fades(it)
    end


    -- render
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(it, true)
    r.Main_OnCommand(use_apply and cmd_apply or ACT_RENDER_PRES, 0)

    -- remove temporary # markers (if any)
    if edge_ids then
      remove_markers_by_ids(edge_ids)
      dbg(DBG,1,"[EDGE-CUE] removed ids: %s, %s", tostring(edge_ids[1]), tostring(edge_ids[2]))
    end

    -- restore fades if we cleared them for 40361/41993
    if use_apply and fade_snap then
      restore_fades(it, fade_snap)
    end


    -- restore item window and offset
    local left_total = L0 - d.gotL
    if left_total < 0 then left_total = 0 end
    r.SetMediaItemInfo_Value(it, "D_POSITION", L0)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   R0 - L0)
    local newtk = r.GetActiveTake(it)  -- the freshly rendered take
    if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_STARTOFFS", left_total) end
    r.UpdateItemInProject(it)

    -- Ensure volumes are neutral after render (we already pre-merged itemVol, so no extra math now).
    r.SetMediaItemInfo_Value(it, "D_VOL", 1.0)
    if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_VOL", 1.0) end

    -- Rename only the new rendered take
    rename_new_render_take(
      it,
      orig_name,
      cfg.RENDER_TAKE_FX == true,
      cfg.RENDER_TRACK_FX == true,
      DBG
    )

    -- Restore original take's offline snapshot first...
    if tk_orig and snap_off then
      restore_takefx_offline(tk_orig, snap_off)
    end
    -- ...then clone the original take FX chain to the NEW take when TAKE FX were excluded
    if newtk and tk_orig and (not need_take) then
      local ncl = clone_takefx_chain(tk_orig, newtk)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] cloned %d FX from old→new on '%s'", ncl, orig_name) end
    end

    -- === TimeReference embed (via Library) =========================
    -- ExtState: RENDER_TC_EMBED = "previous" | "current" | "off"
    do
      local mode = cfg.RENDER_TC_EMBED or "previous"
      if newtk and mode ~= "off" then
        local ok_write = false

        -- 1) 保證 prev_take 的 D_STARTOFFS 回到「渲染前」的值
        if tk_orig and orig_startoffs_sec ~= nil then
          r.SetMediaItemTakeInfo_Value(tk_orig, "D_STARTOFFS", orig_startoffs_sec)
        end

        if mode == "previous" and tk_orig then
          -- Embed TR from previous (original) take, handle-aware and cross-SR safe
          local smp = E.TR_PrevToActive(tk_orig, newtk)
          local src = r.GetMediaItemTake_Source(newtk)
          local path = src and r.GetMediaSourceFileName(src, "") or ""
          if path ~= "" and path:lower():sub(-4) == ".wav" then
            ok_write = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
            if DBG >= 2 then dbg(DBG,2,"[RGWH-TR] mode=previous  write=%s  samples=%d  path=%s", tostring(ok_write), smp, path) end
          end

        elseif mode == "current" then
          -- Embed TR from current project position (item start → active)
          local smp = E.TR_FromItemStart(newtk, L0)
          local src = r.GetMediaItemTake_Source(newtk)
          local path = src and r.GetMediaSourceFileName(src, "") or ""
          if path ~= "" and path:lower():sub(-4) == ".wav" then
            ok_write = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
            if DBG >= 2 then dbg(DBG,2,"[RGWH-TR] mode=current   write=%s  samples=%d  path=%s", tostring(ok_write), smp, path) end
          end
        end

        -- collect for batch refresh if TR was written
        if ok_write then
          collected_new_takes = collected_new_takes or {}
          collected_new_takes[#collected_new_takes+1] = newtk
        end
      end
    end
    -- ==============================================================
  end
  -- restore TRACK FX enabled states if we disabled them
  if not need_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      for fx, was_on in pairs(rec.enabled) do
        r.TrackFX_SetEnabled(tr, fx, was_on and true or false)
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()

  -- refresh items that had TR written (batch)
  if collected_new_takes and #collected_new_takes > 0 then
    E.Refresh_Items(collected_new_takes)
  end

  r.Undo_EndBlock("RGWH Core - Render (Apply FX per item w/ handles)", -1)
end


return M
