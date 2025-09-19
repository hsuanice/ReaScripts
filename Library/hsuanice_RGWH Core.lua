--[[
@description Render or Glue Items with Handles Core Library
@version 0.1.0 (Core extract, battle-tested flow from glue scripts)
@author hsuanice
@about
  Library for RGWH glue/render flows with handles, FX policies, rename, and # markers.

@changelog


]]--
local r = reaper

local M = {}

----------------------------------------------------------------
-- Constants / Commands
----------------------------------------------------------------
local NS = "RGWH"  -- ExtState namespace (project-scope)

-- Actions
local ACT_GLUE_TS          = 42432   -- Item: Glue items within time selection
local ACT_TRIM_TO_TS       = 40508   -- Item: Trim items to time selection
local ACT_APPLY_MONO       = 40361   -- Item: Apply track/take FX to items (mono output)
local ACT_APPLY_MULTI      = 41993   -- Item: Apply track/take FX to items (multichannel output)
local ACT_REMOVE_TAKE_FX   = 40640   -- Item: Remove FX for item take
-- (We do not need SWS _S&M_CLRFXCHAIN2 if we are clearing only active take via 40640)

-- Project marker API (no action needed; use AddProjectMarker2/DeleteProjectMarker)
-- We rely on Project Settings > Media: "Markers starting with #" to embed media cues.

----------------------------------------------------------------
-- Defaults (used if no ExtState present)
----------------------------------------------------------------
local DEFAULTS = {
  GLUE_SINGLE_ITEMS = true,
  HANDLE_MODE       = "seconds",
  HANDLE_SECONDS    = 5.0,
  EPSILON_MODE      = "frames",
  EPSILON_VALUE     = 0.5,
  DEBUG_LEVEL       = 1,
  -- FX policies:
  RENDER_TAKE_FX    = 1,  -- 1=print take FX in result (glue prints by nature; render always prints unless bypassed)
  RENDER_TRACK_FX   = 0,  -- 1=apply track/take FX after glue; render path uses mono/multi command
  -- Render apply mode (for track/take FX apply command)
  APPLY_FX_MODE     = "mono", -- "mono" | "multi"
  -- Rename policy (suffix without plugin names, just result class):
  RENAME_OP_MODE    = "auto", -- "glue" | "render" | "auto"
  -- Hash markers (#in/#out as project markers for media cue embedding)
  WRITE_MEDIA_CUES  = 1,
}

----------------------------------------------------------------
-- ExtState helpers (project-scope)
----------------------------------------------------------------
local function get_proj()
  return 0
end

local function get_ext(key, fallback)
  local _, v = r.GetProjExtState(get_proj(), NS, key)
  if v == nil or v == "" then return fallback end
  return v
end

local function get_ext_bool(key, fallback_bool)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_bool and 1 or 0 end
  v = tostring(v)
  if v == "1" or v:lower() == "true" then return 1 end
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
    GLUE_SINGLE_ITEMS = (get_ext_bool("GLUE_SINGLE_ITEMS", DEFAULTS.GLUE_SINGLE_ITEMS)==1),
    HANDLE_MODE       = get_ext("HANDLE_MODE", DEFAULTS.HANDLE_MODE),
    HANDLE_SECONDS    = get_ext_num("HANDLE_SECONDS", DEFAULTS.HANDLE_SECONDS),
    EPSILON_MODE      = get_ext("EPSILON_MODE", DEFAULTS.EPSILON_MODE),
    EPSILON_VALUE     = get_ext_num("EPSILON_VALUE", DEFAULTS.EPSILON_VALUE),
    DEBUG_LEVEL       = get_ext_num("DEBUG_LEVEL", DEFAULTS.DEBUG_LEVEL),
    RENDER_TAKE_FX    = get_ext_bool("RENDER_TAKE_FX", DEFAULTS.RENDER_TAKE_FX)==1,
    RENDER_TRACK_FX   = get_ext_bool("RENDER_TRACK_FX", DEFAULTS.RENDER_TRACK_FX)==1,
    APPLY_FX_MODE     = get_ext("APPLY_FX_MODE", DEFAULTS.APPLY_FX_MODE),
    RENAME_OP_MODE    = get_ext("RENAME_OP_MODE", DEFAULTS.RENAME_OP_MODE),
    WRITE_MEDIA_CUES  = get_ext_bool("WRITE_MEDIA_CUES", DEFAULTS.WRITE_MEDIA_CUES)==1,
  }
end

----------------------------------------------------------------
-- Utility / Logging
----------------------------------------------------------------
local function printf(fmt, ...)
  r.ShowConsoleMsg(string.format(fmt.."\n", ...))
end

local function dbg(level, want, ...)
  if level >= want then printf(...) end
end

local function frames_to_seconds(frames, sr, fps)
  -- We track epsilon in frames over fps. If fps not available, default to SR/??; prefer TimeMap_curFrameRate
  local fr = (r.TimeMap_curFrameRate and r.TimeMap_curFrameRate(0) or 24.0)
  return (frames or 1) / (fr > 0 and fr or 24.0)
end

local function get_sr()
  return r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
end

----------------------------------------------------------------
-- Selection / grouping helpers
----------------------------------------------------------------
local function count_selected_items()
  return r.CountSelectedMediaItems(0)
end

local function get_sel_items()
  local t = {}
  local n = r.CountSelectedMediaItems(0)
  for i=0,n-1 do
    t[#t+1] = r.GetSelectedMediaItem(0, i)
  end
  return t
end

local function item_span(it)
  local pos  = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len  = r.GetMediaItemInfo_Value(it, "D_LENGTH")
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
  if tk and newn and newn ~= "" then
    r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", newn, true)
  end
end

local function select_only_items(items)
  r.SelectAllMediaItems(0, false)
  for _,it in ipairs(items) do
    if r.ValidatePtr2(0, it, "MediaItem*") then
      r.SetMediaItemSelected(it, true)
    end
  end
  r.UpdateArrange()
end

local function find_item_by_span_on_track(tr, L, R, tol)
  -- Find the glued item spanning exactly L..R on specific track (within tolerance)
  tol = tol or 0.002
  local n = r.CountTrackMediaItems(tr)
  for i=0,n-1 do
    local it = r.GetTrackMediaItem(tr, i)
    local p0, p1 = item_span(it)
    if math.abs(p0 - L) <= tol and math.abs(p1 - R) <= tol then
      return it
    end
  end
  return nil
end

----------------------------------------------------------------
-- Unit detection (single / touch / crossfade) on a single track
----------------------------------------------------------------
local function sort_items_by_pos(items)
  table.sort(items, function(a,b)
    local aL = r.GetMediaItemInfo_Value(a, "D_POSITION")
    local bL = r.GetMediaItemInfo_Value(b, "D_POSITION")
    if aL ~= bL then return aL < bL end
    local aR = aL + r.GetMediaItemInfo_Value(a, "D_LENGTH")
    local bR = bL + r.GetMediaItemInfo_Value(b, "D_LENGTH")
    return aR < bR
  end)
end

local function detect_units_same_track(items, eps_s)
  -- items: already filtered to same track
  -- returns array of {kind="SINGLE"/"TOUCH"/"CROSSFADE", members={...}, start=, finish=}
  local units = {}
  if #items == 0 then return units end
  sort_items_by_pos(items)

  local i = 1
  while i <= #items do
    local a = items[i]
    local aL, aR = item_span(a)
    if i == #items then
      units[#units+1] = {kind="SINGLE", members={{it=a, L=aL, R=aR}}, start=aL, finish=aR}
      break
    end
    local b = items[i+1]
    local bL, bR = item_span(b)
    if aR > bL + 1e-9 then
      -- overlap
      units[#units+1] = {kind="CROSSFADE", members={{it=a, L=aL, R=aR},{it=b, L=bL, R=bR}}, start=aL, finish=bR}
      i = i + 2
    else
      local gap = bL - aR
      if math.abs(gap) <= eps_s then
        units[#units+1] = {kind="TOUCH", members={{it=a, L=aL, R=aR},{it=b, L=bL, R=bR}}, start=aL, finish=bR}
        i = i + 2
      else
        units[#units+1] = {kind="SINGLE", members={{it=a, L=aL, R=aR}}, start=aL, finish=aR}
        i = i + 1
      end
    end
  end
  return units
end

local function collect_by_track_from_selection()
  -- returns map track -> {items...}, and ordered track list
  local by_tr = {}
  local tracks = {}
  local sel = get_sel_items()
  for _,it in ipairs(sel) do
    local tr = r.GetMediaItem_Track(it)
    if not by_tr[tr] then
      by_tr[tr] = {}
      tracks[#tracks+1] = tr
    end
    by_tr[tr][#by_tr[tr]+1] = it
  end
  -- stable order by IP_TRACKNUMBER
  table.sort(tracks, function(a,b)
    return (r.GetMediaTrackInfo_Value(a,"IP_TRACKNUMBER") or 0) < (r.GetMediaTrackInfo_Value(b,"IP_TRACKNUMBER") or 0)
  end)
  return by_tr, tracks
end

----------------------------------------------------------------
-- Handle window (outer members only) with clamp to source bounds
----------------------------------------------------------------
local function per_member_window_lr(it, L, R, H_left, H_right)
  local tk = r.GetActiveTake(it)
  local rate = tk and (r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1.0) or 1.0
  local offs = tk and (r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0.0) or 0.0
  local src  = tk and r.GetMediaItemTake_Source(tk) or nil
  local src_len = src and ({r.GetMediaSourceLength(src)})[1] or math.huge

  local cur_len = R - L

  -- Clamp left: cannot extend beyond available offset
  local max_left_ext = offs / rate
  local wantL = L - (H_left or 0.0)
  local gotL = (wantL < (L - max_left_ext)) and (L - max_left_ext) or wantL

  -- Clamp right: cannot extend beyond source end
  local max_right_ext = ((src_len - offs) / rate) - cur_len
  if max_right_ext < 0 then max_right_ext = 0 end
  local wantR = R + (H_right or 0.0)
  local gotR = (wantR > (R + max_right_ext)) and (R + max_right_ext) or wantR

  local clampL = (gotL > wantL + 1e-9)
  local clampR = (gotR < wantR - 1e-9)

  return {
    tk=tk, rate=rate, offs=offs,
    L=L, R=R,
    wantL=wantL, wantR=wantR,
    gotL=gotL, gotR=gotR,
    clampL=clampL, clampR=clampR,
    leftH=H_left or 0.0, rightH=H_right or 0.0,
    name=get_take_name(it)
  }
end

----------------------------------------------------------------
-- #in/#out project markers (for embedding media cues)
----------------------------------------------------------------
local function add_hash_markers(UL, UR, color)
  -- Returns {in_id, out_id}
  local proj = 0
  color = color or 0
  local in_id  = r.AddProjectMarker2(proj, false, UL, 0, "#in",  -1, color)
  local out_id = r.AddProjectMarker2(proj, false, UR, 0, "#out", -1, color)
  return {in_id, out_id}
end

local function remove_markers_by_ids(ids)
  if not ids then return end
  local proj = 0
  for _,id in ipairs(ids) do
    r.DeleteProjectMarker(proj, id, false) -- isrgn=false
  end
end

----------------------------------------------------------------
-- Rename helpers: strip old suffix and append new
----------------------------------------------------------------
local function strip_suffixes(base)
  if not base then return base, 0, false, false end
  local n = 0
  local hadTake, hadTrack = false, false

  -- Remove -TakeFX / -TrackFX / -TakeFX_TrackFX (in any order)
  base = base:gsub("[-_]TakeFX_TrackFX$", function() hadTake=true; hadTrack=true; return "" end)
  base = base:gsub("[-_]TrackFX$", function() hadTrack=true; return "" end)
  base = base:gsub("[-_]TakeFX$",  function() hadTake=true;  return "" end)

  -- Remove -renderedN / -gluedN
  base = base:gsub("[-_]rendered(%d+)$", function(_) n = tonumber(_) or n; return "" end)
  base = base:gsub("[-_]glued(%d+)$",    function(_) n = tonumber(_) or n; return "" end)

  return base, n, hadTake, hadTrack
end

local function compute_new_name(op_mode, old_name, flags)
  -- flags: {takePrinted=bool, trackPrinted=bool}
  local base = old_name or "Take"
  local stem, n_prev, _, _ = strip_suffixes(base)

  local suffix_print = nil
  if     flags.takePrinted and flags.trackPrinted then suffix_print = "TakeFX_TrackFX"
  elseif flags.takePrinted and not flags.trackPrinted then suffix_print = "TakeFX"
  elseif (not flags.takePrinted) and flags.trackPrinted then suffix_print = "TrackFX"
  end

  local cnt_tag = (op_mode=="glue") and "glued" or "rendered"
  local nextN = (n_prev or 0) + 1

  local final = stem .. "-" .. cnt_tag .. tostring(nextN)
  if suffix_print then
    final = final .. "-" .. suffix_print
  end
  return final
end

----------------------------------------------------------------
-- FX utilities
----------------------------------------------------------------
local function get_apply_cmd(mode)
  return (mode=="multi") and ACT_APPLY_MULTI or ACT_APPLY_MONO
end

local function clear_take_fx_for_items(items)
  if #items == 0 then return end
  select_only_items(items)
  r.Main_OnCommand(ACT_REMOVE_TAKE_FX, 0)
end

local function apply_track_take_fx_to_item(it, apply_mode, dbg_level)
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(it, true)
  r.UpdateArrange()
  local cmd = get_apply_cmd(apply_mode)
  dbg(dbg_level,1,"[RUN] Apply Track/Take FX (%s) to 1 item.", apply_mode)
  r.Main_OnCommand(cmd, 0)
end

----------------------------------------------------------------
-- GLUE FLOW (per unit)
----------------------------------------------------------------
local function glue_unit(tr, u, cfg)
  local DBG = cfg.DEBUG_LEVEL or 1
  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0
  local eps_s  = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  -- Collect members (ordered) and capture original boundary fades
  local members = {}
  for i,m in ipairs(u.members) do members[i] = m end
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

  -- Determine outer handle windows with clamp
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

  dbg(DBG,1,"[RUN] unit kind=%s members=%d UL=%.3f UR=%.3f dur=%.3f",
    u.kind, #members, UL, UR, UR-UL)
  if DBG>=2 then
    for i,d in ipairs(details) do
      dbg(DBG,2,"       member#%d want=%.3f..%.3f -> got=%.3f..%.3f  clampL=%s clampR=%s  name=%s",
        i, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), d.name or "(none)")
    end
  end

  -- Respect RENDER_TAKE_FX policy:
  -- 0 => remove all take FX for members before glue (glue won’t print take FX then)
  if not cfg.RENDER_TAKE_FX then
    local items = {}
    for i,m in ipairs(members) do items[i] = m.it end
    clear_take_fx_for_items(items)
    dbg(DBG,1,"[TAKE-FX] cleared (policy=OFF) for this unit.")
  end

  -- Insert #in/#out markers if enabled (unit boundaries; not UL/UR)
  local hash_ids = nil
  if cfg.WRITE_MEDIA_CUES then
    hash_ids = add_hash_markers(u.start, u.finish, 0)
    dbg(DBG,1,"[HASH] add #in @ %.3f  #out @ %.3f  ids=(%d,%d)", u.start, u.finish, hash_ids[1] or -1, hash_ids[2] or -1)
  end

  -- Prepare selection for glue: select only this unit members
  local items_sel = {}
  for i,m in ipairs(members) do items_sel[i] = m.it end
  select_only_items(items_sel)

  -- Temporarily extend only outermost items to UL/UR so glue captures handles
  for idx, m in ipairs(members) do
    local it = m.it
    local d  = details[idx]
    local newL = (idx==1) and d.gotL or m.L
    local newR = (idx==#members) and d.gotR or m.R
    r.SetMediaItemInfo_Value(it, "D_POSITION", newL)
    r.SetMediaItemInfo_Value(it, "D_LENGTH", newR - newL)
    if d.tk then
      local deltaL  = (m.L - newL)
      local new_off = d.offs - (deltaL * d.rate)
      r.SetMediaItemTakeInfo_Value(d.tk, "D_STARTOFFS", new_off)
    end
    r.UpdateItemInProject(it)
  end

  -- Time selection = UL..UR, glue, (optionally) apply track/take FX, then trim back to UL..UR
  r.GetSet_LoopTimeRange(true, false, UL, UR, false)
  r.Main_OnCommand(ACT_GLUE_TS, 0)

  local glued_pre = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if cfg.RENDER_TRACK_FX and glued_pre then
    apply_track_take_fx_to_item(glued_pre, cfg.APPLY_FX_MODE, DBG)
  end
  r.Main_OnCommand(ACT_TRIM_TO_TS, 0)

  -- Find final glued item (again) by UL..UR
  local glued = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if glued then
    -- Reposition to unit “real span” and set take offset as handles-left
    local left_total  = u.start - UL
    local right_total = UR - u.finish
    if left_total  < 0 then left_total  = 0 end
    if right_total < 0 then right_total = 0 end

    r.SetMediaItemInfo_Value(glued, "D_POSITION", u.start)
    r.SetMediaItemInfo_Value(glued, "D_LENGTH",  u.finish - u.start)
    local gtk = r.GetActiveTake(glued)
    if gtk then r.SetMediaItemTakeInfo_Value(gtk, "D_STARTOFFS", left_total) end
    r.UpdateItemInProject(glued)

    -- Restore original boundary fades
    r.SetMediaItemInfo_Value(glued, "D_FADEINLEN",      fin_len)
    r.SetMediaItemInfo_Value(glued, "D_FADEINDIR",      fin_dir)
    r.SetMediaItemInfo_Value(glued, "C_FADEINSHAPE",    fin_shape)
    r.SetMediaItemInfo_Value(glued, "D_FADEINLEN_AUTO", fin_auto)
    r.SetMediaItemInfo_Value(glued, "D_FADEOUTLEN",      fout_len)
    r.SetMediaItemInfo_Value(glued, "D_FADEOUTDIR",      fout_dir)
    r.SetMediaItemInfo_Value(glued, "C_FADEOUTSHAPE",    fout_shape)
    r.SetMediaItemInfo_Value(glued, "D_FADEOUTLEN_AUTO", fout_auto)
    r.UpdateItemInProject(glued)

    -- Rename per result flags (actual prints)
    local flags = {
      takePrinted  = cfg.RENDER_TAKE_FX,       -- glue printed take FX iff we didn’t clear them
      trackPrinted = cfg.RENDER_TRACK_FX       -- we applied track/take FX after glue
    }
    local oldn = get_take_name(glued)
    local op   = (cfg.RENAME_OP_MODE=="auto") and "glue" or cfg.RENAME_OP_MODE
    local newn = compute_new_name(op, oldn, flags)
    set_take_name(glued, newn)

    dbg(DBG,1,"       post-glue: trimmed to [%.3f..%.3f], offs=%.3f (L=%.3f R=%.3f)  name='%s' → '%s'",
      u.start, u.finish, left_total, left_total, right_total, oldn or "", newn or "")
  else
    dbg(DBG,1,"       WARNING: glued item not found by span (UL=%.3f UR=%.3f)", UL, UR)
  end

  -- Clear time selection
  r.GetSet_LoopTimeRange(true, false, 0, 0, false)

  -- Remove hash markers
  if hash_ids then
    remove_markers_by_ids(hash_ids)
    dbg(DBG,1,"[HASH] removed ids: %s, %s", tostring(hash_ids[1]), tostring(hash_ids[2]))
  end
end

----------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------
function M.glue_selection()
  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.ClearConsole()

  local nsel = count_selected_items()
  if nsel == 0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Glue (no selection)", -1); return
  end

  -- epsilon seconds
  local eps_s = (cfg.EPSILON_MODE=="frames")
    and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil)
     or (cfg.EPSILON_VALUE or 0.002)

  dbg(DBG,1,"[RUN] Glue start  handles=%.3fs  epsilon=%.5fs  GLUE_SINGLE_ITEMS=%s  RENDER_TAKE_FX=%s  RENDER_TRACK_FX=%s  APPLY_FX_MODE=%s  WRITE_MEDIA_CUES=%s",
    cfg.HANDLE_SECONDS or 0, eps_s, tostring(cfg.GLUE_SINGLE_ITEMS),
    tostring(cfg.RENDER_TAKE_FX), tostring(cfg.RENDER_TRACK_FX), cfg.APPLY_FX_MODE, tostring(cfg.WRITE_MEDIA_CUES))

  -- Group by track and process in track order
  local by_tr, tr_list = collect_by_track_from_selection()
  for _, tr in ipairs(tr_list) do
    local list = by_tr[tr]
    -- Detect units on this track
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
  -- NOTE:
  -- "Render" here means Apply Track/Take FX to items as new take (mono/multi).
  -- Policy matrix (simplified and safe):
  --  - If RENDER_TAKE_FX=1 and RENDER_TRACK_FX=1: direct apply (40361/41993).
  --  - If RENDER_TAKE_FX=0 and RENDER_TRACK_FX=1: temporarily bypass take FX per item, apply, then restore.
  --  - If RENDER_TAKE_FX=1 and RENDER_TRACK_FX=0: temporarily bypass track FX (all on track), apply, then restore track FX.
  --  - If both 0: temporarily bypass both chains, apply (so it prints "dry" item vol/take vol), then restore.
  -- This is intentionally conservative (no cloning/migrating FX chains). Renaming reflects printed reality.

  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1
  local items = get_sel_items()
  local nsel = #items

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.ClearConsole()

  if nsel == 0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Render (no selection)", -1); return
  end

  dbg(DBG,1,"[RUN] Render start  APPLY_FX_MODE=%s  TAKE=%s TRACK=%s  items=%d",
    cfg.APPLY_FX_MODE, tostring(cfg.RENDER_TAKE_FX), tostring(cfg.RENDER_TRACK_FX), nsel)

  -- Snapshot track FX bypass per track (so we can restore)
  local tr_map = {}
  for _,it in ipairs(items) do
    local tr = r.GetMediaItem_Track(it)
    if not tr_map[tr] then
      tr_map[tr] = {track=tr, bypass_orig = {}}
      -- Inspect track FX count and bypass states
      local fx_count = r.TrackFX_GetCount(tr) or 0
      for fx=0,fx_count-1 do
        local bypass = r.TrackFX_GetEnabled(tr, fx)
        tr_map[tr].bypass_orig[fx] = bypass -- true = enabled
      end
    end
  end

  -- Apply policy: temporarily enable/disable chains as needed
  local need_disable_track = (not cfg.RENDER_TRACK_FX)
  local need_disable_take  = (not cfg.RENDER_TAKE_FX)

  -- Track FX: disable if needed
  if need_disable_track then
    for _,rec in pairs(tr_map) do
      local tr = rec.track
      local fx_count = r.TrackFX_GetCount(tr) or 0
      for fx=0,fx_count-1 do
        r.TrackFX_SetEnabled(tr, fx, false) -- disable (bypass)
      end
    end
    dbg(DBG,1,"[RUN] Temporarily disabled TRACK FX for render (policy TRACK=0).")
  end

  -- Take FX: disable per item if needed
  local per_item_takefx_enabled = {}
  if need_disable_take then
    for _,it in ipairs(items) do
      local tk = r.GetActiveTake(it)
      local enabled_now = true
      if tk then
        local fx_count = r.TakeFX_GetCount(tk) or 0
        per_item_takefx_enabled[it] = {}
        for fx=0,fx_count-1 do
          local on = r.TakeFX_GetEnabled(tk, fx) -- true=enabled
          per_item_takefx_enabled[it][fx] = on
          if on then r.TakeFX_SetEnabled(tk, fx, false) end
        end
      end
    end
    dbg(DBG,1,"[RUN] Temporarily disabled TAKE FX for render (policy TAKE=0).")
  end

  -- Insert #in/#out markers if enabled: at item span
  local hash_ids = {}
  if cfg.WRITE_MEDIA_CUES then
    for _,it in ipairs(items) do
      local L,R = item_span(it)
      local ids = add_hash_markers(L, R, 0)
      hash_ids[#hash_ids+1] = ids
    end
    dbg(DBG,1,"[HASH] inserted #in/#out for %d items.", #items)
  end

  -- Do the apply (mono/multi) to all selected
  select_only_items(items)
  local cmd = get_apply_cmd(cfg.APPLY_FX_MODE)
  r.Main_OnCommand(cmd, 0)
  dbg(DBG,1,"[RUN] Apply Track/Take FX (%s) to %d items.", cfg.APPLY_FX_MODE, #items)

  -- Remove hash markers
  if cfg.WRITE_MEDIA_CUES then
    for _,ids in ipairs(hash_ids) do remove_markers_by_ids(ids) end
    dbg(DBG,1,"[HASH] removed all render-time # markers.")
  end

  -- Restore chain enable states
  if need_disable_take then
    for it, map in pairs(per_item_takefx_enabled) do
      local tk = r.GetActiveTake(it)
      if tk then
        for fx, was_on in pairs(map) do
          r.TakeFX_SetEnabled(tk, fx, was_on and true or false)
        end
      end
    end
  end
  if need_disable_track then
    for _,rec in pairs(tr_map) do
      local tr = rec.track
      for fx,was_on in pairs(rec.bypass_orig) do
        r.TrackFX_SetEnabled(tr, fx, was_on and true or false)
      end
    end
  end

  -- Rename new active take(s) per actual printed result
  -- For Apply-to-new-take, REAPER adds a new active take; we rename that.
  local printed_take = cfg.RENDER_TAKE_FX
  local printed_trk  = cfg.RENDER_TRACK_FX
  for _,it in ipairs(items) do
    local tk = r.GetActiveTake(it)
    if tk then
      local _, oldn = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
      local newn     = compute_new_name("render", oldn, {takePrinted=printed_take, trackPrinted=printed_trk})
      r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", newn, true)
      dbg(DBG,1,"[NAME] '%s' → '%s'", oldn or "", newn or "")
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("RGWH Core - Render (Apply FX to new take)", -1)
end

return M
