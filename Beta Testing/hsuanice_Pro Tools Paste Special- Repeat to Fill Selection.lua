--[[
@description hsuanice_Pro Tools Paste Special: Repeat to Fill Selection
@version 0.2.3
@author hsuanice
@about
  MRX-style "Repeat to Fill", Razor-only, multi-item & multitrack clipboard.
  - Stage whole block at a far "staging area", then move once into Razor.
  - No system Auto-Crossfade; ALL fades are applied manually.
  - JOIN crossfades between repeated tiles (after moving into target we verify/repair).
  - Boundary crossfades ONLY when edge-to-edge, and without moving any item:
      * Left boundary: extend LEFT neighbor's right edge (no move).
      * Right boundary: extend LAST-IN-AREA item's right edge (no move).
  - Items only; envelopes not supported yet (Razor contains envelope -> abort).
  - Restores original item/track selection.

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

  Reference: MRX_PasteItemToFill_Items_and_EnvelopeLanes.lua
--]]

local r = reaper

--------------------------------------------------------------------------------
-- ***** USER OPTIONS *****
--------------------------------------------------------------------------------
-- Cursor return: 0 = initial, 1 = selection start, 2 = selection end
local leaveCursorLocation       = 0

-- Boundary crossfades (seconds) at Razor left/right (edge-to-edge only).
local edgeXFadeLen              = 0.5

-- JOIN crossfades (seconds) between repeated tiles inside the filled area.
--  -1.0 = use edgeXFadeLen (default ON)
--   0.0 = OFF
--  >0.0 = that length in seconds
local joinXFadeLen              = -1.0

-- Only create boundary CF when edge-to-edge?
local edgeToEdgeOnly            = true

-- Prevent tiny last piece if it would be shorter than this proportion of tile_len
local preventTinyLastFactor     = 0.1  -- 10%

-- Restore original Razor edits after finishing?
local restoreRazorEdits         = true

-- Staging safety pad to the right of the last project item (seconds)
local STAGE_PAD                 = 60.0

local EPS                       = 1e-9
--------------------------------------------------------------------------------

local function get_join_len()
  if joinXFadeLen == -1.0 then return edgeXFadeLen end
  return math.max(0, joinXFadeLen or 0)
end

-- ============================== selection snapshot ==============================
local function snapshot_selection()
  local items, tracks = {}, {}
  for i=0, r.CountSelectedMediaItems(0)-1 do items[#items+1] = r.GetSelectedMediaItem(0,i) end
  for i=0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0,i)
    if r.GetMediaTrackInfo_Value(tr,"I_SELECTED") > 0.5 then tracks[#tracks+1] = tr end
  end
  return items, tracks
end

local function restore_selection(items, tracks)
  r.Main_OnCommand(40289,0) -- unselect items
  r.Main_OnCommand(40297,0) -- unselect tracks
  for _,tr in ipairs(tracks or {}) do
    if r.ValidatePtr2(0,tr,"MediaTrack*") then r.SetMediaTrackInfo_Value(tr,"I_SELECTED",1) end
  end
  for _,it in ipairs(items or {}) do
    if r.ValidatePtr2(0,it,"MediaItem*") then r.SetMediaItemSelected(it,true) end
  end
end

-- ============================== utils ==============================
local function track_index(tr) return math.floor(r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or 0) end
local function unselect_all() r.Main_OnCommand(40289,0); r.Main_OnCommand(40297,0) end
local function project_last_item_end()
  local last=0.0
  for i=0, r.CountMediaItems(0)-1 do
    local it=r.GetMediaItem(0,i)
    local e=r.GetMediaItemInfo_Value(it,"D_POSITION")+r.GetMediaItemInfo_Value(it,"D_LENGTH")
    if e>last then last=e end
  end
  return last
end
local function select_only_track(tr)
  for i=0,r.CountTracks(0)-1 do
    local t=r.GetTrack(0,i)
    r.SetMediaTrackInfo_Value(t,"I_SELECTED", t==tr and 1 or 0)
  end
  r.Main_OnCommand(40914,0) -- set last touched
end

local function purge_track_envelopes_in_range(t1,t2)
  for i=0, r.CountTracks(0)-1 do
    local tr=r.GetTrack(0,i)
    for e=0, r.CountTrackEnvelopes(tr)-1 do
      local env=r.GetTrackEnvelope(tr,e)
      r.DeleteEnvelopePointRange(env,t1,t2)
      local ai_cnt=r.CountAutomationItems(env)
      for ai=ai_cnt-1,0,-1 do
        local pos=r.GetSetAutomationItemInfo(env,ai,"D_POSITION",0,false)
        local len=r.GetSetAutomationItemInfo(env,ai,"D_LENGTH",0,false)
        if pos+len>t1 and pos<t2 then r.DeleteAutomationItem(env,ai) end
      end
      r.Envelope_SortPoints(env)
    end
  end
end

-- ============================== Razor parsing & grouping ==============================
local function get_razor_areas_items_only()
  local areas={}
  for i=0, r.CountTracks(0)-1 do
    local tr=r.GetTrack(0,i)
    local ok,s=r.GetSetMediaTrackInfo_String(tr,"P_RAZOREDITS","",false)
    if ok and s~="" then
      local t,j={},1
      for w in s:gmatch("%S+") do t[#t+1]=w end
      while j<=#t do
        local a=tonumber(t[j]); local b=tonumber(t[j+1]); local guid=t[j+2]
        if guid~='""' then return nil,"Razor contains envelope lanes (not supported yet)." end
        areas[#areas+1]={start=a, finish=b, track=tr}; j=j+3
      end
    end
  end
  return areas, nil
end

local function group_areas_by_range(areas)
  local groups, order = {}, {}
  for _,ar in ipairs(areas) do
    local key=string.format("%.15f|%.15f", ar.start, ar.finish)
    if not groups[key] then groups[key]={start=ar.start, finish=ar.finish, tracks={}}; order[#order+1]=key end
    groups[key].tracks[#groups[key].tracks+1]=ar.track
  end
  for _,k in ipairs(order) do
    table.sort(groups[k].tracks, function(a,b) return track_index(a)<track_index(b) end)
  end
  return groups, order
end

-- ============================== target pre-clear (Split+Delete) ==============================
local function clear_items_in_range_on_tracks(t1,t2, tracks_sorted)
  for _,tr in ipairs(tracks_sorted) do
    -- split at boundaries where needed
    for i=r.CountTrackMediaItems(tr)-1,0,-1 do
      local it=r.GetTrackMediaItem(tr,i)
      local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e=p+l
      if e>t1+EPS and p<t2-EPS then
        if p<t1-EPS and e>t1+EPS then r.SplitMediaItem(it,t1) end
        if p<t2-EPS and e>t2+EPS then r.SplitMediaItem(it,t2) end
      end
    end
    -- delete items fully inside
    for i=r.CountTrackMediaItems(tr)-1,0,-1 do
      local it=r.GetTrackMediaItem(tr,i)
      local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e=p+l
      if p>=t1-EPS and e<=t2+EPS then r.DeleteTrackMediaItem(tr,it) end
    end
  end
end

-- ============================== staging helpers ==============================
local function remap_selected_items_by_relative_top(tracks_sorted)
  local n=r.CountSelectedMediaItems(0); if n==0 then return end
  local min_idx=math.huge; local tmp={}
  for i=0,n-1 do
    local it=r.GetSelectedMediaItem(0,i)
    local idx=track_index(r.GetMediaItem_Track(it)); tmp[#tmp+1]={it=it, idx=idx}
    if idx<min_idx then min_idx=idx end
  end
  local to_del={}
  for _,rec in ipairs(tmp) do
    local rel=rec.idx-min_idx
    if rel<0 or rel>=#tracks_sorted then to_del[#to_del+1]=rec.it
    else
      local dst=tracks_sorted[rel+1]
      if dst~=r.GetMediaItem_Track(rec.it) then r.MoveMediaItemToTrack(rec.it,dst) end
    end
  end
  for _,it in ipairs(to_del) do r.DeleteTrackMediaItem(r.GetMediaItem_Track(it),it) end
end

local function selected_min_pos()
  local n=r.CountSelectedMediaItems(0); local m=math.huge
  for i=0,n-1 do
    local it=r.GetSelectedMediaItem(0,i)
    local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
    if p<m then m=p end
  end
  return (m<math.huge) and m or nil
end

local function trim_selection_to_right(end_time)
  local n=r.CountSelectedMediaItems(0)
  for i=0,n-1 do
    local it=r.GetSelectedMediaItem(0,i)
    local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
    local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
    if p+l>end_time+EPS then
      local new_len=end_time-p
      if new_len>EPS then r.SetMediaItemInfo_Value(it,"D_LENGTH",new_len)
      else r.DeleteTrackMediaItem(r.GetMediaItem_Track(it),it) end
    end
  end
end

-- Manual JOIN crossfades（確保相鄰 item 之間一定有交叉；必要時延長左邊 item 的右緣）
local function ensure_join_crossfades_in_range(a, b, tracks_sorted, joinLen)
  if not joinLen or joinLen <= EPS then return end
  for _,tr in ipairs(tracks_sorted) do
    local list = {}
    for i=0, r.CountTrackMediaItems(tr)-1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if e > a + EPS and p < b - EPS then list[#list+1] = {it=it,p=p,e=e} end
    end
    table.sort(list, function(u,v) return u.p < v.p end)

    for i=1,#list-1 do
      local L, R = list[i], list[i+1]
      L.p = r.GetMediaItemInfo_Value(L.it,"D_POSITION")
      local Ll = r.GetMediaItemInfo_Value(L.it,"D_LENGTH")
      L.e = L.p + Ll
      R.p = r.GetMediaItemInfo_Value(R.it,"D_POSITION")
      local overlap = L.e - R.p

      if overlap < joinLen - 1e-6 then
        local need = joinLen - math.max(0, overlap)
        r.SetMediaItemInfo_Value(L.it, "D_LENGTH", Ll + need)  -- 只延長左邊 item 的右緣
        L.e = L.e + need
        overlap = L.e - R.p
      end

      if overlap > EPS then
        local fade = math.min(joinLen, overlap)
        r.SetMediaItemInfo_Value(L.it, "D_FADEOUTLEN", fade)
        r.SetMediaItemInfo_Value(R.it, "D_FADEINLEN",  fade)
      end
    end
  end
end

-- Build the staged block of length total_len at stage_pos (JOIN overlaps applied in staging too)
local function build_staging_block(stage_pos, total_len, tile_len, base_track, tracks_sorted)
  select_only_track(base_track)
  local join = get_join_len()
  local step = math.max(EPS, tile_len - join)

  local t = stage_pos
  while t < stage_pos + total_len - EPS do
    r.SetEditCurPos(t, false, false)
    r.Main_OnCommand(42398,0) -- Paste
    remap_selected_items_by_relative_top(tracks_sorted)
    t = t + step
    local left = (stage_pos + total_len) - t
    local tiny_threshold = math.max(2*join + 1e-4, total_len * preventTinyLastFactor)
    if left < tiny_threshold then break end
  end
  if t < stage_pos + total_len - EPS then
    r.SetEditCurPos(t, false, false)
    r.Main_OnCommand(42398,0)
    remap_selected_items_by_relative_top(tracks_sorted)
  end

  -- select all staged items and trim to right boundary
  r.Main_OnCommand(40289,0)
  for _,tr in ipairs(tracks_sorted) do
    for i=0, r.CountTrackMediaItems(tr)-1 do
      local it=r.GetTrackMediaItem(tr,i)
      local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e=p+l
      if e>stage_pos+EPS and p<stage_pos+total_len-EPS then r.SetMediaItemSelected(it,true) end
    end
  end
  trim_selection_to_right(stage_pos + total_len)
end

-- ============================== boundary (edge-to-edge, no move) ==============================
local function find_left_neighbor(tr, time)   -- item whose end == time
  local best=nil; local bestEnd=-math.huge
  for i=0,r.CountTrackMediaItems(tr)-1 do
    local it=r.GetTrackMediaItem(tr,i)
    local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
    local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
    local e=p+l
    if math.abs(e-time) < 0.0005 and e>bestEnd then best=it; bestEnd=e end
  end
  return best
end

local function find_right_neighbor(tr, time)  -- item whose start == time
  for i=0,r.CountTrackMediaItems(tr)-1 do
    local it=r.GetTrackMediaItem(tr,i)
    local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
    if math.abs(p-time) < 0.0005 then return it end
  end
  return nil
end

local function first_item_in_area_on_track(tr, a, b)
  local best=nil; local bestPos=math.huge
  for i=0,r.CountTrackMediaItems(tr)-1 do
    local it=r.GetTrackMediaItem(tr,i)
    local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
    local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
    local e=p+l
    if e>a+EPS and p<b-EPS then if p<bestPos then best=it; bestPos=p end end
  end
  return best
end

local function last_item_in_area_on_track(tr, a, b)
  local best=nil; local bestEnd=-math.huge
  for i=0,r.CountTrackMediaItems(tr)-1 do
    local it=r.GetTrackMediaItem(tr,i)
    local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
    local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
    local e=p+l
    if e>a+EPS and p<b-EPS then if e>bestEnd then best=it; bestEnd=e end end
  end
  return best
end

local function apply_boundary_crossfades(start_t, end_t, tracks_sorted, fadeLen)
  if fadeLen<=EPS then return end
  for _,tr in ipairs(tracks_sorted) do
    -- LEFT boundary
    local leftN  = find_left_neighbor(tr, start_t)
    if leftN or not edgeToEdgeOnly then
      local first = first_item_in_area_on_track(tr, start_t, end_t)
      if first then
        r.SetMediaItemInfo_Value(first, "D_FADEINLEN", math.max(fadeLen, r.GetMediaItemInfo_Value(first,"D_FADEINLEN")))
        if leftN then
          local ll = r.GetMediaItemInfo_Value(leftN,"D_LENGTH")
          r.SetMediaItemInfo_Value(leftN,"D_LENGTH", ll + fadeLen) -- extend right edge only
          r.SetMediaItemInfo_Value(leftN,"D_FADEOUTLEN", math.max(fadeLen, r.GetMediaItemInfo_Value(leftN,"D_FADEOUTLEN")))
        end
      end
    end
    -- RIGHT boundary
    local rightN = find_right_neighbor(tr, end_t)
    if rightN or not edgeToEdgeOnly then
      local last  = last_item_in_area_on_track(tr, start_t, end_t)
      if last then
        local llen = r.GetMediaItemInfo_Value(last,"D_LENGTH")
        r.SetMediaItemInfo_Value(last,"D_LENGTH", llen + fadeLen) -- extend to right (no move)
        r.SetMediaItemInfo_Value(last,"D_FADEOUTLEN", math.max(fadeLen, r.GetMediaItemInfo_Value(last,"D_FADEOUTLEN")))
        if rightN then
          r.SetMediaItemInfo_Value(rightN, "D_FADEINLEN", math.max(fadeLen, r.GetMediaItemInfo_Value(rightN,"D_FADEINLEN")))
        end
      end
    end
  end
end

-- ============================== measurement of clipboard ==============================
local function measure_clipboard_tile_len(stage_track)
  local stage_pos = project_last_item_end() + STAGE_PAD
  select_only_track(stage_track or r.GetTrack(0,0))
  r.SetEditCurPos(stage_pos, false, false)
  r.Main_OnCommand(42398,0) -- Paste
  local n=r.CountSelectedMediaItems(0); if n==0 then return nil,"Clipboard is empty (copy items first)." end
  local minp, maxe = math.huge, -math.huge
  for i=0,n-1 do
    local it=r.GetSelectedMediaItem(0,i)
    local p=r.GetMediaItemInfo_Value(it,"D_POSITION")
    local l=r.GetMediaItemInfo_Value(it,"D_LENGTH")
    if p<minp then minp=p end; if p+l>maxe then maxe=p+l end
  end
  local tile_len=math.max(0.0, maxe-minp)
  r.Main_OnCommand(40006,0) -- Remove staged items (keep clipboard)
  if maxe>minp then purge_track_envelopes_in_range(minp-0.001, maxe+0.001) end
  if tile_len<=EPS then return nil,"Measured clipboard length is zero." end
  return tile_len, nil
end

-- ============================== per-group pipeline ==============================
local function process_group(start_t, end_t, tracks_sorted, tile_len)
  local total = math.max(0, end_t - start_t); if total<=EPS then return end
  local base_track = tracks_sorted[1]

  -- pre-clear target
  clear_items_in_range_on_tracks(start_t, end_t, tracks_sorted)

  -- build in staging
  local stage_pos = project_last_item_end() + STAGE_PAD
  build_staging_block(stage_pos, total, tile_len, base_track, tracks_sorted)

  -- move staged items into area
  local minp = selected_min_pos(); if not minp then return end
  local delta = start_t - minp
  local n = r.CountSelectedMediaItems(0)
  for i=0,n-1 do
    local it=r.GetSelectedMediaItem(0,i)
    local p =r.GetMediaItemInfo_Value(it,"D_POSITION")
    r.SetMediaItemInfo_Value(it,"D_POSITION", p + delta)
  end
  r.Main_OnCommand(40289,0) -- unselect staged

  -- ensure JOIN crossfades inside target (repair butts by extending left edge)
  local join = get_join_len()
  if join > EPS then
    ensure_join_crossfades_in_range(start_t, end_t, tracks_sorted, join)
  end

  -- boundary crossfades (edge-to-edge only if option true), no item movement
  if edgeXFadeLen>EPS then apply_boundary_crossfades(start_t, end_t, tracks_sorted, edgeXFadeLen) end

  -- cleanup staging envelopes (if any were pasted there)
  purge_track_envelopes_in_range(stage_pos-0.001, stage_pos + total + 0.001)
end

-- ============================== main ==============================
local function main()
  local areas, err = get_razor_areas_items_only()
  if not areas then r.ShowMessageBox(err or "Failed to read Razor edits.", "Repeat to Fill", 0); return end
  if #areas==0 then r.ShowMessageBox("No Razor Edit areas.","Repeat to Fill",0); return end

  local arrangeStart, arrangeEnd = r.GetSet_ArrangeView2(0,false,0,0,0,0)
  local curpos = r.GetCursorPosition()
  local sel_items, sel_tracks = snapshot_selection()

  local groups, order = group_areas_by_range(areas)

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  unselect_all()

  -- measure tile once (use first group's top track)
  local first_base = groups[order[1]].tracks[1]
  local tile_len, merr = measure_clipboard_tile_len(first_base)
  if not tile_len then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("hsuanice — Repeat to Fill (FAILED)", -1)
    r.ShowMessageBox(merr or "Measure failed.","Repeat to Fill",0)
    restore_selection(sel_items, sel_tracks)
    r.SetEditCurPos(curpos,false,false)
    r.GetSet_ArrangeView2(0,true,0,0,arrangeStart,arrangeEnd)
    return
  end

  -- process each Razor group
  for _,key in ipairs(order) do
    local g = groups[key]
    process_group(g.start, g.finish, g.tracks, tile_len)
  end

  -- restore Razor or clear
  if restoreRazorEdits then
    local lastTrack=nil; local buf={}
    for _,ar in ipairs(areas) do
      local tr=ar.track
      if tr~=lastTrack and lastTrack~=nil then
        r.GetSetMediaTrackInfo_String(lastTrack,"P_RAZOREDITS", table.concat(buf," "), true); buf={}
      end
      buf[#buf+1] = string.format("%.20f %.20f \"\"", ar.start, ar.finish)
      lastTrack=tr
    end
    if lastTrack then r.GetSetMediaTrackInfo_String(lastTrack,"P_RAZOREDITS", table.concat(buf," "), true) end
  else
    r.Main_OnCommand(42406,0) -- Razor edit: Clear all areas
  end

  -- restore selection & UI
  restore_selection(sel_items, sel_tracks)
  if leaveCursorLocation==1 then r.SetEditCurPos(groups[order[1]].start,false,false)
  elseif leaveCursorLocation==2 then r.SetEditCurPos(groups[order[1]].finish,false,false)
  else r.SetEditCurPos(curpos,false,false) end
  r.GetSet_ArrangeView2(0,true,0,0,arrangeStart,arrangeEnd)

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("hsuanice — Paste Special: Repeat to Fill Selection (v0.2.3)", -1)
  r.UpdateArrange()
end

main()
