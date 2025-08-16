--[[
@description Hover Mode Trim Tool Monitor — Live HUD + A/S Snapshot & Diff
@version 0.1.0
@author hsuanice
@about
  Live monitor for Hover Mode trim tools. Shows mouse/track context and triplet (Prev/Under/Next),
  captures A=Left Trim / S=Right Trim, takes TRUE BEFORE & AFTER snapshots (ring buffer / WM key),
  and prints GUID-mapped global diffs. Edge-aware "Under" uses zoom-adaptive epsilon and
  pixel-accurate hit tests (SWS/js_ReaScriptAPI when available). Undo-assisted trigger/ready;
  ESC/Cancel to quit.

  Note:
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
    hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.1.0
    - Baseline release (equivalent to internal v1.8):
      ring-buffer TRUE BEFORE for undo-triggered events; edge-aware Under;
      pixel-accurate item hit; GUID-mapped global diff; A/S capture; ESC/Cancel.
--]]

-------------------------------------------------
-- Config
-------------------------------------------------
local NAMED_LEFT   = "_RS76cff27631188d111aa189a67dbd32da03cf36c9" -- A
local NAMED_IMPORT = "_RSb02d73a9185efd0eaa9b73e4c9482c052b3beefd" -- S
local NAMED_TOGGLE = "_RS8626f4a9475133c13270c52e1deca4035fb8313c" -- HUD only

-- Undo assist (you prefer ON)
local USE_UNDO_FOR_TRIGGER = true
local USE_UNDO_FOR_READY   = true

-- Edge preference at exact boundary
-- "left" | "right" | "neutral"
local EDGE_PREF_FOR_LIVE = "right"  -- good for LEFT trim

-- WM key intercept (if js_ReaScriptAPI available)
local USE_WM_INTERCEPT = true

-- Timings
local LIVE_INTERVAL          = 0.08   -- HUD refresh (s)
local MIN_AFTER_DELAY        = 0.05   -- minimal wait before AFTER (s)
local MAX_AFTER_WAIT         = 1.60   -- timeout (s)
local SNAPSHOT_ITEM_INTERVAL = 0.20   -- ring buffer refresh for items/tracks (s)  <-- NEW

-- Limits / keys
local MAX_LOG_LINES   = 2400
local EPS             = 1e-9
local VK_A, VK_S      = 0x41, 0x53

-------------------------------------------------
-- Capability checks / utils
-------------------------------------------------
local function has_js()  return reaper.JS_VKeys_GetState ~= nil end
local function has_wm()  return reaper.JS_WindowMessage_Intercept ~= nil end
local function has_sws() return reaper.BR_GetMouseCursorContext ~= nil end
local function has_item_at_mouse() return reaper.BR_ItemAtMouseCursor ~= nil end
local function msg(s) reaper.ShowConsoleMsg(tostring(s).."\n") end
local function now() return reaper.time_precise() end
local function fmtsec(s) return s and reaper.format_timestr_pos(s, "", 0) or "N/A" end
local function approx(a,b,eps) eps=eps or EPS return math.abs((a or 0)-(b or 0))<=eps end

-------------------------------------------------
-- Names/ids/snap/hover/view
-------------------------------------------------
local function get_track_name(tr) if not tr then return "(no track)" end local _,n=reaper.GetTrackName(tr,"") return (n~="" and n) or "(unnamed track)" end
local function item_guid(it) local _,g=reaper.GetSetMediaItemInfo_String(it,"GUID","",false) return g end
local function track_guid(tr) local _,g=reaper.GetSetMediaTrackInfo_String(tr,"GUID","",false) return g end
local function snap_enabled() return reaper.GetToggleCommandState(1157)==1 end
local function hover_ext_state() local v=reaper.GetExtState("hsuanice_TrimTools","HoverMode") return (v=="true" or v=="1"), (v or "") end
local function mouse_class_is_ruler(x,y)
  if not reaper.JS_Window_FromPoint then return false,"(js not installed)" end
  local hwnd = reaper.JS_Window_FromPoint(x,y)
  local cls  = hwnd and reaper.JS_Window_GetClassName(hwnd) or ""
  return (cls=="REAPERTimeDisplay"), cls
end
local function get_arrange_view()
  local s,e = reaper.GetSet_ArrangeView2(0,false,0,0)
  return s or 0, e or 0
end

-------------------------------------------------
-- Item/source state builders
-------------------------------------------------
local function item_label(item)
  local ok, iname = reaper.GetSetMediaItemInfo_String(item,"P_NAME","",false)
  if ok and iname~="" then return iname.." [Item Label]" end
  local take = reaper.GetActiveTake(item)
  if take then
    local tn = reaper.GetTakeName(take) or ""
    if tn~="" then return tn.." [Take Name]" end
    local src = reaper.GetMediaItemTake_Source(take)
    if src then
      local p = reaper.GetMediaSourceFileName(src,"") or ""
      if p~="" then return p.." [Source]" end
    end
    return "[Unnamed Take]"
  end
  return "[EMPTY Item]"
end

local function take_source_len_sec(take)
  if not take then return 0 end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return 0 end
  local len,isQN = reaper.GetMediaSourceLength(src)
  if isQN then return reaper.TimeMap_QNToTime(len) or 0 end
  return len or 0
end

local function item_state_full(item)
  local pos   = reaper.GetMediaItemInfo_Value(item,"D_POSITION")
  local len   = reaper.GetMediaItemInfo_Value(item,"D_LENGTH")
  local fi    = reaper.GetMediaItemInfo_Value(item,"D_FADEINLEN")
  local fo    = reaper.GetMediaItemInfo_Value(item,"D_FADEOUTLEN")
  local tr    = reaper.GetMediaItem_Track(item)
  local loops = reaper.GetMediaItemInfo_Value(item,"B_LOOPSRC")==1
  local take  = reaper.GetActiveTake(item)
  local is_midi = (take and reaper.TakeIsMIDI(take)) or false
  local offs  = (take and not is_midi) and reaper.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS") or 0.0
  local rate  = (take and reaper.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")) or 1.0
  local src_s = take_source_len_sec(take)

  local win_start_src = offs
  local win_len_src   = (len or 0) * (rate>0 and rate or 1.0)
  local win_end_src   = win_start_src + win_len_src
  local trim_left_src = win_start_src
  local trim_right_src= loops and math.huge or math.max(0, src_s - win_end_src)

  local hr_left_proj  = (rate>0) and (offs / rate) or 0
  local hr_right_proj = loops and math.huge or ((src_s - (offs + win_len_src)) / (rate>0 and rate or 1.0))
  if hr_right_proj < 0 then hr_right_proj = 0 end

  return {
    guid=item_guid(item), name=item_label(item), track=get_track_name(tr),
    pos=pos, len=len, endp=(pos or 0)+(len or 0),
    fadein=fi, fadeout=fo,
    loops=loops, rate=rate, startoffs=offs, src_len=src_s,
    win_start_src=win_start_src, win_end_src=win_end_src, win_len_src=win_len_src,
    trim_left_src=trim_left_src, trim_right_src=trim_right_src,
    headroom_left=hr_left_proj, headroom_right=hr_right_proj,
  }
end

-------------------------------------------------
-- Track / items listing
-------------------------------------------------
local last_mouse_track=nil
local function mouse_track()
  if has_sws() then
    reaper.BR_GetMouseCursorContext()
    local tr = reaper.BR_GetMouseCursorContext_Track()
    if tr then last_mouse_track=tr; return tr end
  end
  local x,y = reaper.GetMousePosition()
  local tr  = reaper.GetTrackFromPoint(x,y)
  if tr then last_mouse_track=tr; return tr end
  if last_mouse_track then return last_mouse_track end
  if reaper.CountSelectedTracks(0)==1 then return reaper.GetSelectedTrack(0,0) end
  return nil
end

local function collect_track_items_sorted(tr)
  local list={}
  local n=reaper.CountTrackMediaItems(tr)
  for i=0,n-1 do
    local it=reaper.GetTrackMediaItem(tr,i)
    local st=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
    local ln=reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
    list[#list+1]={item=it,pos=st,endp=st+ln,idx=i}
  end
  table.sort(list,function(a,b) if a.pos==b.pos then return a.idx<b.idx end return a.pos<b.pos end)
  return list
end

local function intersects_view(a_start,a_end,v_start,v_end) return (a_end>v_start) and (a_start<v_end) end

-------------------------------------------------
-- Zoom-adaptive epsilon
-------------------------------------------------
local function sec_epsilon_half_pixel()
  local pps = reaper.GetHZoomLevel() or 100.0
  if pps <= 0 then pps = 100.0 end
  return 0.5 / pps
end

-------------------------------------------------
-- Edge-aware UNDER resolver
-------------------------------------------------
local function resolve_under_index(items, tr, t, vstart, vend, edge_pref)
  if not t then return nil end
  local eps = sec_epsilon_half_pixel()

  -- 1) Pixel hit via SWS
  if has_item_at_mouse() then
    local it = reaper.BR_ItemAtMouseCursor()
    if it and reaper.GetMediaItem_Track(it) == tr then
      local st = reaper.GetMediaItemInfo_Value(it,"D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
      if intersects_view(st,en,vstart,vend) then
        local gid = item_guid(it)
        for i,rec in ipairs(items) do if item_guid(rec.item)==gid then return i end end
      end
    end
  end

  -- 2) Time-based + boundary rule
  local start_hits, end_hits = {}, {}
  local inside_candidate = nil
  for i,it in ipairs(items) do
    if intersects_view(it.pos,it.endp,vstart,vend) then
      local at_start = math.abs(t - it.pos) <= eps
      local at_end   = math.abs(t - it.endp) <= eps
      local inside   = (t > it.pos + eps) and (t < it.endp - eps)
      if inside and not inside_candidate then inside_candidate=i end
      if at_start then start_hits[#start_hits+1] = i end
      if at_end   then end_hits[#end_hits+1]   = i end
    end
  end

  if inside_candidate then return inside_candidate end

  local function pick_from(list, cmp)
    table.sort(list, cmp); return (#list>0) and list[1] or nil
  end

  if #start_hits>0 and #end_hits==0 then
    if edge_pref=="right" then
      return pick_from(start_hits, function(a,b) return items[a].pos < items[b].pos end)
    elseif edge_pref=="left" then
      return pick_from(start_hits, function(a,b) return items[a].pos > items[b].pos end)
    else
      return pick_from(start_hits, function(a,b) return items[a].pos < items[b].pos end)
    end
  elseif #end_hits>0 and #start_hits==0 then
    if edge_pref=="left" then
      return pick_from(end_hits, function(a,b) return items[a].endp > items[b].endp end)
    elseif edge_pref=="right" then
      return pick_from(end_hits, function(a,b) return items[a].endp > items[b].endp end)
    else
      return pick_from(end_hits, function(a,b) return items[a].endp > items[b].endp end)
    end
  elseif #start_hits>0 and #end_hits>0 then
    if edge_pref=="right" then
      return pick_from(start_hits, function(a,b) return items[a].pos < items[b].pos end)
    elseif edge_pref=="left" then
      return pick_from(end_hits, function(a,b) return items[a].endp > items[b].endp end)
    else
      return pick_from(start_hits, function(a,b) return items[a].pos < items[b].pos end)
    end
  end

  return nil
end

-------------------------------------------------
-- Crossfade grouping + state
-------------------------------------------------
local function group_from_index(items,i)
  local A=items[i]; if not A then return nil end
  local L=(i-1>=1) and items[i-1] or nil
  local R=(i+1<=#items) and items[i+1] or nil
  local members={A.item}
  if L and L.endp > A.pos then members={L.item,A.item}
  elseif R and A.endp > R.pos then members={A.item,R.item} end
  local g={members={}, startp=math.huge, endp=-math.huge}
  local seen={}
  for _,it in ipairs(members) do
    if not seen[it] then
      local st=reaper.GetMediaItemInfo_Value(it,"D_POSITION")
      local ln=reaper.GetMediaItemInfo_Value(it,"D_LENGTH")
      g.startp=math.min(g.startp,st); g.endp=math.max(g.endp,st+ln)
      g.members[#g.members+1]=it; seen[it]=true
    end
  end
  return g
end

local function group_to_state(group)
  if not group then return nil end
  local out={startp=group.startp,endp=group.endp,members={}}
  for _,it in ipairs(group.members) do out.members[#out.members+1]=item_state_full(it) end
  return out
end

-------------------------------------------------
-- Triplet finder (ensures Next != Under)
-------------------------------------------------
local function find_triplet_on_mouse_track(mouse_time,vstart,vend, edge_pref)
  local tr = mouse_track()
  if not tr then return tr,nil,nil,nil end
  local items = collect_track_items_sorted(tr)

  local under_i = resolve_under_index(items, tr, mouse_time, vstart, vend, edge_pref)
  local prev_i, next_i = nil, nil

  if under_i then
    for i=under_i-1,1,-1 do
      local it = items[i]
      if intersects_view(it.pos,it.endp,vstart,vend) and it.endp <= (mouse_time or -math.huge) then prev_i = i; break end
    end
    for i=under_i+1,#items do
      local it = items[i]
      if intersects_view(it.pos,it.endp,vstart,vend) and it.pos >= (mouse_time or math.huge) then next_i = i; break end
    end
  else
    for i,it in ipairs(items) do
      if intersects_view(it.pos,it.endp,vstart,vend) then
        if it.endp <= (mouse_time or -math.huge) then
          if (not prev_i) or items[i].endp > items[prev_i].endp then prev_i=i end
        end
        if it.pos >= (mouse_time or math.huge) then
          if (not next_i) or items[i].pos < items[next_i].pos then next_i=i end
        end
      end
    end
  end

  local prevG  = prev_i  and group_from_index(items,prev_i)  or nil
  local underG = under_i and group_from_index(items,under_i) or nil
  local nextG  = next_i  and group_from_index(items,next_i)  or nil
  return tr, group_to_state(prevG), group_to_state(underG), group_to_state(nextG)
end

-------------------------------------------------
-- History / printing helpers
-------------------------------------------------
local history={}
local function push(line)
  history[#history+1]=line
  if #history>MAX_LOG_LINES then
    local cut=#history-MAX_LOG_LINES
    for i=1,cut do history[i]=nil end
  end
end

local function fmt_src_state(s)
  local rR=(s.trim_right_src==math.huge) and "∞ (loop)" or string.format("%.6f", s.trim_right_src or 0)
  local hR=(s.headroom_right==math.huge) and "∞ (loop)" or string.format("%.6f", s.headroom_right or 0)
  return string.format(
    "Source: total %0.6fs | window [%0.6f → %0.6f] (%0.6f) | trim L %0.6f R %s | loop %s | HR L/R %0.6f / %s",
    s.src_len or 0, s.win_start_src or 0, s.win_end_src or 0, s.win_len_src or 0,
    s.trim_left_src or 0, rR, tostring(s.loops), s.headroom_left or 0, hR)
end

local function print_triplet_block(label,G)
  if not G then msg("  "..label..": none"); return end
  local head=(#G.members==2) and "XFADE group" or "item"
  msg(string.format("  %s: %s [%s – %s]", label, head, fmtsec(G.startp), fmtsec(G.endp)))
  for _,s in ipairs(G.members) do
    msg("    - "..s.name)
    msg(string.format("      Timeline: Start %s | End %s | Len %s", fmtsec(s.pos), fmtsec(s.endp), fmtsec(s.len)))
    msg("      "..fmt_src_state(s))
  end
end

-------------------------------------------------
-- Live HUD + ring buffers (env + items/tracks)
-------------------------------------------------
local last_env, prev_env = nil, nil
local last_live = 0

-- NEW: ring buffer for items/tracks
local last_items, prev_items = nil, nil
local last_tracks, prev_tracks = nil, nil
local last_items_time = 0

local function current_mouse_tl()
  if has_sws() and reaper.BR_GetMouseCursorContext_Position then
    reaper.BR_GetMouseCursorContext()
    return reaper.BR_GetMouseCursorContext_Position()
  end
  if reaper.BR_PositionAtMouseCursor then
    return reaper.BR_PositionAtMouseCursor(true)
  end
  return nil
end

local function env_snapshot(edge_pref_for_live)
  local x,y = reaper.GetMousePosition()
  local mt  = current_mouse_tl()
  local vstart, vend = get_arrange_view()
  local tr, prevG, underG, nextG = find_triplet_on_mouse_track(mt, vstart, vend, edge_pref_for_live or EDGE_PREF_FOR_LIVE)
  local over_ruler=false
  if has_js() then local isr,_=mouse_class_is_ruler(x,y); over_ruler=isr end
  local snap_on = snap_enabled()
  local hover_on, hover_raw = hover_ext_state()
  local edit_pos = reaper.GetCursorPosition()
  return {
    x=x,y=y, mouse_tl=mt, track=tr, track_name=get_track_name(tr),
    over_ruler=over_ruler, snap=snap_on, hover=hover_on, hover_raw=hover_raw,
    edit=edit_pos, vstart=vstart, vend=vend,
    prev=prevG, under=underG, next=nextG
  }
end

local function all_items_map()
  local map={}
  local n=reaper.CountMediaItems(0)
  for i=0,n-1 do local it=reaper.GetMediaItem(0,i); map[item_guid(it)]=item_state_full(it) end
  return map
end
local function all_tracks_set()
  local t={}
  local n=reaper.CountTracks(0)
  for i=0,n-1 do local tr=reaper.GetTrack(0,i); t[track_guid(tr)]={index=i+1,name=get_track_name(tr)} end
  return t
end

local function maybe_refresh_item_ringbuf()
  local t = now()
  if (t - last_items_time) >= SNAPSHOT_ITEM_INTERVAL or (not last_items) then
    prev_items  = last_items
    prev_tracks = last_tracks
    last_items  = all_items_map()
    last_tracks = all_tracks_set()
    last_items_time = t
  end
end

local function redraw_live()
  local t=now(); if t-last_live<LIVE_INTERVAL then return end; last_live=t

  -- refresh ring buffers
  prev_env = last_env
  last_env = env_snapshot(EDGE_PREF_FOR_LIVE)

  maybe_refresh_item_ringbuf()

  reaper.ClearConsole()
  local e = last_env
  msg(string.format("LIVE  Mouse(%d,%d) | Timeline: %s | Ruler: %s | Edit: %s | Snap: %s | Hover: %s (raw '%s') | ToggleID:%s",
    e.x,e.y, fmtsec(e.mouse_tl), tostring(e.over_ruler), fmtsec(e.edit),
    tostring(e.snap), tostring(e.hover), e.hover_raw, NAMED_TOGGLE))
  msg(string.format("      On Track: %s | View: [%s – %s] | Target: %s",
    get_track_name(e.track), fmtsec(e.vstart), fmtsec(e.vend),
    (e.hover and not e.over_ruler and e.mouse_tl and (e.snap and fmtsec(reaper.SnapToGrid(0,e.mouse_tl)).." (Mouse snapped)" or fmtsec(e.mouse_tl).." (Mouse)")) or "Edit Cursor"))
  msg("Triplet")
  print_triplet_block("Prev ", e.prev)
  print_triplet_block("Under", e.under)
  print_triplet_block("Next ", e.next)
  msg("------------------------------------")
  for i=1,#history do msg(history[i]) end
end

-------------------------------------------------
-- Global diff + helpers
-------------------------------------------------
local function global_item_diff(before,after)
  local changed={}
  for g,b in pairs(before or {}) do
    local a=after and after[g]
    if a then
      local posc=not approx(a.pos,b.pos)
      local endc=not approx(a.endp,b.endp)
      local lenc=not approx(a.len,b.len)
      local fic =not approx(a.fadein,b.fadein)
      local foc =not approx(a.fadeout,b.fadeout)
      if posc or endc or lenc or fic or foc then
        local mode
        if posc and not endc then mode=(a.pos>b.pos) and "TRIM-LEFT" or "EXTEND-LEFT"
        elseif endc and not posc then mode=(a.endp>b.endp) and "EXTEND-RIGHT" or "TRIM-RIGHT"
        elseif posc and endc then mode="BOTH-EDGES"
        else mode="FADES-ONLY" end
        changed[#changed+1]={guid=g, name=a.name, track=a.track, mode=mode,
          start_b=b.pos,start_a=a.pos, end_b=b.endp,end_a=a.endp, len_b=b.len,len_a=a.len}
      end
    end
  end
  return changed
end

local function guid_in_group(gid, G)
  if not G or not G.members then return false end
  for _,s in ipairs(G.members) do if s.guid==gid then return true end end
  return false
end

-------------------------------------------------
-- Keyboard (WM/VKeys) + Undo
-------------------------------------------------
local prev_keys=""
local function key_edge_vkeys(vk)
  if not has_js() then return false end
  local st=reaper.JS_VKeys_GetState(0); if not st then return false end
  local was=(prev_keys:len()==256) and prev_keys:byte(vk+1) or 0
  local nowb=(st:len()==256) and st:byte(vk+1) or 0
  prev_keys=st
  return (was==0 and nowb~=0)
end

local mainHwnd = reaper.GetMainHwnd and reaper.GetMainHwnd() or nil
local wm_active=false
local function wm_start()
  if not (has_wm() and USE_WM_INTERCEPT and mainHwnd) then return false end
  reaper.JS_WindowMessage_Intercept(mainHwnd, "WM_KEYDOWN", true)
  reaper.JS_WindowMessage_Intercept(mainHwnd, "WM_KEYUP",   true)
  wm_active=true
  return true
end
local function wm_stop()
  if wm_active and has_wm() and mainHwnd then
    reaper.JS_WindowMessage_Release(mainHwnd, "WM_KEYDOWN")
    reaper.JS_WindowMessage_Release(mainHwnd, "WM_KEYUP")
  end
  wm_active=false
end

local function wm_poll_keydown()
  if not wm_active then return nil end
  while true do
    local rv, msg, wparam = reaper.JS_WindowMessage_Peek(mainHwnd, "WM_KEYDOWN")
    if rv ~= 1 then return nil end
    reaper.JS_WindowMessage_Peek(mainHwnd, "", 0) -- consume
    local vk = tonumber(wparam or 0) or 0
    if vk==VK_A or vk==VK_S then return vk end
  end
end

local last_undo = reaper.Undo_CanUndo2(0) or ""
local function undo_changed()
  local u=reaper.Undo_CanUndo2(0) or ""
  local ch=(u~=last_undo)
  last_undo=u
  return ch,u
end

-------------------------------------------------
-- Event controller
-------------------------------------------------
local pending=nil

local function push_triplet_snapshot(title, snap)
  push(title)
  push(string.format("  MouseTL:%s | Track:%s | Snap:%s | Hover:%s (raw '%s') | Ruler:%s | Edit:%s | View:[%s – %s]",
    fmtsec(snap.mouse_tl), snap.track_name, tostring(snap.snap), tostring(snap.hover), snap.hover_raw,
    tostring(snap.over_ruler), fmtsec(snap.edit), fmtsec(snap.vstart), fmtsec(snap.vend)))
  local function pg(tag,G)
    if not G then push("  "..tag..": none"); return end
    local head=(#G.members==2) and "XFADE group" or "item"
    push(string.format("  %s: %s [%s – %s]", tag, head, fmtsec(G.startp), fmtsec(G.endp)))
    for _,s in ipairs(G.members) do
      push("    - "..s.name)
      push(string.format("      Timeline: Start %s | End %s | Len %s", fmtsec(s.pos), fmtsec(s.endp), fmtsec(s.len)))
      push("      "..fmt_src_state(s))
    end
  end
  pg("Prev ", snap.prev); pg("Under", snap.under); pg("Next ", snap.next)
end

local function begin_event(evtype, source) -- 'key' | 'vkeys' | 'undo'
  -- TRUE BEFORE (env)
  local before_env =
      ((source=="key" or source=="vkeys") and last_env) or
      (source=="undo" and (prev_env or last_env)) or
      last_env
  if not before_env then before_env = env_snapshot(EDGE_PREF_FOR_LIVE) end

  -- TRUE BEFORE (items/tracks) via ring buffer  <-- NEW
  maybe_refresh_item_ringbuf() -- ensure ring has something
  local before_items = ((source=="undo") and (prev_items or last_items)) or (last_items)
  local before_tracks= ((source=="undo") and (prev_tracks or last_tracks)) or (last_tracks)
  if not before_items then before_items = all_items_map() end
  if not before_tracks then before_tracks = all_tracks_set() end

  pending = {
    type=evtype, t0=now(), source=source,
    before_env   = before_env,
    before_items = before_items,
    before_tracks= before_tracks,
  }
  push(string.format("[Event %s] (%s) | MouseTL:%s | Track:%s | Snap:%s | Hover:%s",
    evtype:upper(), source, fmtsec(before_env.mouse_tl), before_env.track_name,
    tostring(before_env.snap), tostring(before_env.hover)))
end

local function complete_event_if_ready()
  if not pending then return end
  local elapsed = now()-pending.t0
  if elapsed < MIN_AFTER_DELAY then return end

  local after_env   = env_snapshot(EDGE_PREF_FOR_LIVE)
  local after_items = all_items_map()
  local after_tracks= all_tracks_set()

  local ready=false
  if USE_UNDO_FOR_READY then local chg,_=undo_changed(); if chg then ready=true end end

  local changes = global_item_diff(pending.before_items, after_items)
  if #changes>0 then ready=true end

  if pending.type=="import" and not ready then
    for g,_ in pairs(after_items)  do if not pending.before_items[g]  then ready=true break end end
    for g,_ in pairs(after_tracks) do if not pending.before_tracks[g] then ready=true break end end
  end

  if (not ready) and elapsed < MAX_AFTER_WAIT then return end

  push_triplet_snapshot("BEFORE snapshot:", pending.before_env)
  push_triplet_snapshot("AFTER snapshot:",  after_env)

  local B = pending.before_env
  local mapped = { ["Prev "]= {}, ["Under"]= {}, ["Next "]= {}, ["Other"]= {} }
  for _,ch in ipairs(changes) do
    local slot="Other"
    if guid_in_group(ch.guid, B.prev)  then slot="Prev " end
    if guid_in_group(ch.guid, B.under) then slot="Under" end
    if guid_in_group(ch.guid, B.next)  then slot="Next " end
    table.insert(mapped[slot], ch)
  end

  push("Summary (changes grouped by BEFORE slots):")
  local function dump(slot)
    local list = mapped[slot]
    if #list==0 then push("  "..slot..": no change"); return end
    for _,ch in ipairs(list) do
      push(string.format("  %s: %s | %s | Start %s→%s (Δ %+0.6fs) | End %s→%s (Δ %+0.6fs) | Len %s→%s (Δ %+0.6fs)",
        slot, ch.mode, ch.name,
        fmtsec(ch.start_b), fmtsec(ch.start_a), (ch.start_a-ch.start_b),
        fmtsec(ch.end_b),   fmtsec(ch.end_a),   (ch.end_a-ch.end_b),
        fmtsec(ch.len_b),   fmtsec(ch.len_a),   (ch.len_a-ch.len_b)))
    end
  end
  dump("Prev "); dump("Under"); dump("Next "); dump("Other")
  push("--- DONE ---")

  pending=nil
end

-------------------------------------------------
-- gfx mini window (ESC/Cancel)
-------------------------------------------------
local W,H=560,80; local BW,BH=100,26; local BX,BY=W-BW-12,12
gfx.init("Hover Monitor (ESC / Cancel to quit)", W,H,0,80,80)
local prev_cap=0
local function btn_clicked(x,y,w,h)
  local mx,my=gfx.mouse_x,gfx.mouse_y
  local over=(mx>=x and mx<=x+w and my>=y and my<=y+h)
  local cap=gfx.mouse_cap
  local clicked=over and (prev_cap&1==0) and (cap&1==1)
  prev_cap=cap
  return clicked
end
local function draw_btn(x,y,w,h,txt)
  gfx.set(0.15,0.15,0.15,1) gfx.rect(x,y,w,h,1)
  gfx.set(0.55,0.55,0.55,1) gfx.rect(x,y,w,h,0)
  gfx.x=x+12; gfx.y=y+6; gfx.set(0.9,0.9,0.9,1) gfx.drawstr(txt)
end

-------------------------------------------------
-- WM/VKeys/Undo loop + HUD
-------------------------------------------------
local function loop()
  local ch=gfx.getchar()
  if ch==27 or ch==-1 then
    reaper.ClearConsole(); for i=1,#history do msg(history[i]) end
    gfx.quit(); wm_stop(); return
  end

  if btn_clicked(BX,BY,BW,BH) then
    push("[Monitor] Cancel clicked. Exiting.")
    reaper.ClearConsole(); for i=1,#history do msg(history[i]) end
    gfx.quit(); wm_stop(); return
  end

  gfx.set(0.12,0.12,0.12,1) gfx.rect(0,0,W,H,1)
  draw_btn(BX,BY,BW,BH,"Cancel"); gfx.update()

  redraw_live()

  -- WM intercept → precise BEFORE
  if has_wm() and USE_WM_INTERCEPT then
    local vk = wm_poll_keydown()
    if vk and not pending then
      if vk==VK_A then begin_event("left","key") end
      if vk==VK_S then begin_event("import","key") end
    end
  end

  -- VKeys fallback
  if has_js() and not pending then
    if key_edge_vkeys(VK_A) then begin_event("left","vkeys") end
    if key_edge_vkeys(VK_S) then begin_event("import","vkeys") end
  end

  -- Undo fallback (as requested ON)
  if USE_UNDO_FOR_TRIGGER and not pending then
    local changed,label=undo_changed()
    if changed then
      local l=(label or ""):lower()
      if l:find("trim") or l:find("extend") then begin_event("left","undo"); push("  (by Undo label: "..label..")")
      elseif l:find("import") then begin_event("import","undo"); push("  (by Undo label: "..label..")") end
    end
  end

  complete_event_if_ready()
  reaper.defer(loop)
end

-- Start
reaper.ClearConsole()
push("[Monitor] Started. A=Left Trim, S=Right Trim. ESC/Cancel to quit.")
if not has_js()  then push("[Warning] js_ReaScriptAPI not detected; key capture falls back to Undo.]") end
if not has_sws() then push("[Warning] SWS not detected; using time-based hit-tests only (still edge-aware).]") end
if USE_WM_INTERCEPT and has_wm() then
  reaper.JS_WindowMessage_Intercept(reaper.GetMainHwnd(), "WM_KEYDOWN", true)
  reaper.JS_WindowMessage_Intercept(reaper.GetMainHwnd(), "WM_KEYUP",   true)
end
loop()
