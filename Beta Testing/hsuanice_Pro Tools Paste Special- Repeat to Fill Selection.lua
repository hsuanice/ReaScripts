--[[
@description hsuanice_Pro Tools Paste Special: Repeat to Fill Selection
@version 0.4.7 time/item selection fallback
@author hsuanice
@about
  Pro Tools-style "Paste Special: Repeat to Fill Selection"
  - Stage whole block at a far "staging area", then move once into Razor.
  - No system Auto-Crossfade; ALL fades are applied manually.
  - JOIN crossfades between repeated tiles (after moving into target we verify/repair).
  - Boundary crossfades ONLY when edge-to-edge, and without moving any item:
      * Left boundary: extend LEFT neighbor's right edge (no move).
      * Right boundary: extend LAST-IN-AREA item's right edge (no move).
  - Items only; envelopes not supported yet (Razor contains envelope -> abort).
  - Restores original item/track selection.

  Known issues:
  - CF_UNIT="grid" is still inaccurate/experimental; use seconds/frames for reliable results.
  - When requested JOIN is much larger than the tile length, the script auto-adjusts JOIN
    to a fraction of the tile for stability. In certain source/material combinations this
    may still yield visually irregular overlaps. Workarounds: lower CF_VALUE or copy a
    longer source tile.

  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

  Reference: MRX_PasteItemToFill_Items_and_EnvelopeLanes.lua


@changelog
  v0.4.7 (2026-02-20 TPE) - Feat: Fallback priority when no Razor Edit is present:
           1. Time selection (uses selected tracks).
           2. Item selection (bounding box of selected items + their tracks).

  v0.4.6 - Fix: Right-boundary crossfades in "center" alignment now respect the full
           requested length (CF_VALUE). Previously each side only applied half the length,
           causing too-short overlaps (e.g. 1f+1f when CF_VALUE=2f). Both last-in-area and
           right-neighbor items now receive at least CF_VALUE fade lengths, consistent
           with left-boundary behavior.
  v0.4.5 - Boundary XF: default to centered; always suspend "Trim content behind…" during
           boundary XF to prevent right-edge being eaten; restore preference afterward.
  v0.4.4 - Robust handling when JOIN ≈ tile:
           • Auto-adjust JOIN to a percent of tile (configurable via
             JOIN_CLAMP_TRIGGER_RATIO / JOIN_CLAMP_TO_TILE_RATIO) to keep layout stable.
           • Staging switches to butt-pastes when JOIN is near tile
             (MAX_JOIN_RATIO_FOR_STAGING) to avoid tiny step sizes and UI stalls.
           • Only one warning dialog ("Auto-adjust") is shown; removed the extra
             "Clamped to prevent hang" dialog in staging.
           • Performance: no beachball; repeat-to-fill completes immediately even in
             extreme JOIN requests.
           NOTE: In rare edge cases the visual arrangement may still look irregular after
             auto-adjust; see Known issues.

  v0.4.3 - Boundary crossfade alignment options ("left" / "center" / "right").
           Centering the right edge may extend the outside neighbor's left edge
           (configurable via EDGE_XF_MOVE_OUTSIDE). JOIN tiles unchanged.

  v0.4.2 - Fix: multitrack paste restored (single anchor track + reassert last-touched
           before each paste). Feat: system equal-power stamping via Action 41529 with
           expanded time selection to include boundary neighbors.

  v0.4.1 - Unified crossfade length control — CF_VALUE + CF_UNIT drive both boundary and
           JOIN CFs. Equal-power polarity switch (CF_EQUALPOWER_FLIP). Hang guard when
           CF ≥ tile length (clamp to tile−ε).

  v0.4.0 - Crossfade length units: seconds / frames / grid (initial grid impl).

  v0.3.0 - Crossfade shape presets (linear / equal_power / custom) via
           apply_item_fade_shape().

  v0.2.4 - Stronger Razor clearing (FIPM-safe; 1 ms tolerance; two rounds of split+delete).
           Preserve neighbors that butt the edges.

  v0.2.3 - After moving to target, re-check JOIN and synthesize overlap if needed;
           apply fades manually; pre-clear Razor; multi-area & cross-track.

  v0.2.1 - No Auto-Crossfade; all fades are manual. Boundary CF only when edge-to-edge
           and outside items are never moved.

  v0.2.0 - User options for JOIN and boundary CFs.

  v0.1.x - Initial release: stage once → move into target; restore selection & view.



--]]

local r = reaper

--------------------------------------------------------------------------------
-- ***** USER OPTIONS *****
--------------------------------------------------------------------------------
-- Crossfade length unit (v0.4.0)
CF_UNIT        = "frames"            -- "seconds" | "frames" | "grid"
CF_VALUE       = 1                   -- seconds=seconds, frames=frame count, grid=number of grid units
CF_GRID_REF    = "center"            -- reference point for grid length: "left"|"center"|"right" (recommended: left)



-- Crossfade shape options (v0.3.0)
CF_SHAPE_PRESET   = "equal_power"  -- "linear" | "equal_power" | "custom"
CF_EQUALPOWER_VIA_ACTION = true    -- true: use action 41529 to stamp equal-power shape; false: use internal curve approximation
CF_SHAPE_IN       = 0              -- only used when PRESET="custom", 0..6 (0=linear)
CF_SHAPE_OUT      = 0              -- only used when PRESET="custom", 0..6
CF_CURVE_IN       = 0              -- -1..1, only used when PRESET="custom"
CF_CURVE_OUT      = 0              -- -1..1, only used when PRESET="custom"
CF_EQUALPOWER_FLIP = true          -- set true if you feel the equal-power curvature is reversed

-- Edge (boundary) crossfade alignment on the Razor borders only:
--   "right"  = entirely inside the boundary (original behavior)
--   "center" = centered on the boundary, half on each side
--   "left"   = entirely outside the boundary
-- Internal JOIN: centered
JOIN_XF_ALIGN = "center"   -- "right" | "center" | "left"

-- Boundary EDGE: centered; allows extending the outer item's left edge (left edge only, right boundary untouched)
EDGE_XF_ALIGN = "center"   -- "right" | "center" | "left"
EDGE_XF_MOVE_OUTSIDE = true

-- When JOIN >= this ratio of tile_len, stage with BUTT pastes (join_for_staging=0)
-- and create overlaps later in target (prevents long loops & beachball).
MAX_JOIN_RATIO_FOR_STAGING = 0.80

-- If requested JOIN is too large vs tile, auto-scale JOIN to a percent of tile:
JOIN_CLAMP_TRIGGER_RATIO = 0.85   -- trigger auto-scale when JOIN >= 85% of tile_len
JOIN_CLAMP_TO_TILE_RATIO = 0.35   -- scale down to 35% of tile_len (adjust 0.3-0.6 to taste)




-- Cursor return: 0 = initial, 1 = selection start, 2 = selection end
local leaveCursorLocation       = 1

-- Boundary crossfades (seconds) at Razor left/right (edge-to-edge only).
-- local edgeXFadeLen              = 1

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
local STAGE_PAD                 = 2

local EPS                       = 1e-9

local warned_join_clamp   = false  -- unused; reserved
local warned_join_fallback = false  -- show the auto-adjust dialog at most once per run
--------------------------------------------------------------------------------

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

-- Select the target track group and set the first as last-touched (paste anchor).
local function select_tracks_block(tracks_sorted)
  r.Main_OnCommand(40297,0) -- Unselect all tracks
  for _,tr in ipairs(tracks_sorted) do
    r.SetMediaTrackInfo_Value(tr,"I_SELECTED",1)
  end
  r.Main_OnCommand(40914,0) -- Track: Set first selected track as last touched track
end


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
-- Clear only items inside [t1,t2]; preserve items that butt the boundary from outside.
-- Also works per-lane in Fixed Item Pool mode.
local function clear_items_in_range_on_tracks(t1,t2, tracks_sorted)
  -- Use a loose tolerance (~1 ms) to avoid floating-point/sample-boundary misses.
  local EPSX = 0.001

  for _,tr in ipairs(tracks_sorted) do
    -- pass1: split items that cross t1/t2 (items exactly on the boundary are not split)
    for i = r.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if p < t1 - EPSX and e > t1 + EPSX then r.SplitMediaItem(it, t1) end
      if p < t2 - EPSX and e > t2 + EPSX then r.SplitMediaItem(it, t2) end
    end

    -- pass2: delete items fully inside [t1-eps, t2+eps] (including boundary-exact items)
    for i = r.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if p >= t1 - EPSX and e <= t2 + EPSX then
        r.DeleteTrackMediaItem(tr, it)
      end
    end

    -- pass3 (safety): if any items still intersect the range, split and delete again
    for i = r.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if e > t1 + EPSX and p < t2 - EPSX then
        -- Residual cross-boundary item (tiny float error); re-split at boundary edges.
        if p < t1 - EPSX and e > t1 + EPSX then r.SplitMediaItem(it, t1) end
        if p < t2 - EPSX and e > t2 + EPSX then r.SplitMediaItem(it, t2) end
      end
    end
    for i = r.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if p >= t1 - EPSX and e <= t2 + EPSX then
        r.DeleteTrackMediaItem(tr, it)
      end
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

-- Convert a CF length value from CF_UNIT to seconds, referenced at refTime.
local function cf_grid_len_seconds(units, refTime)
  -- Anchor: find the grid line to the left of refTime, then measure from there.
  local t_ref = refTime or reaper.GetCursorPosition()
  local t_left = reaper.BR_GetClosestGridDivision(t_ref)
  if t_left > t_ref + 1e-12 then
    -- Closest grid division was to the right; step back one grid.
    t_left = reaper.BR_GetPrevGridDivision(t_left)
  end
  if CF_GRID_REF == "right" then
    -- Right-referenced: advance one grid cell to use as the start point.
    t_left = reaper.BR_GetNextGridDivision(t_left)
  elseif CF_GRID_REF == "center" then
    -- Center-referenced: find the current cell, then shift left by half a cell.
    local t_next = reaper.BR_GetNextGridDivision(t_left)
    local half = (t_next - t_left) * 0.5
    t_left = t_ref - half
  end

  local whole = math.floor(units)
  local frac  = units - whole
  local t0    = t_left
  local sec   = 0.0

  for _=1, whole do
    local t1 = reaper.BR_GetNextGridDivision(t0)
    sec = sec + (t1 - t0)
    t0  = t1
  end
  if frac > 0 then
    local t1 = reaper.BR_GetNextGridDivision(t0)
    sec = sec + (t1 - t0) * frac
  end
  return sec
end

local function cf_to_seconds(v, refTime)
  if v == nil then return 0 end
  if CF_UNIT == "seconds" then
    return v
  elseif CF_UNIT == "frames" then
    local fps = reaper.TimeMap_curFrameRate(0)
    return v / (fps > 0 and fps or 1)
  elseif CF_UNIT == "grid" then
    return cf_grid_len_seconds(v, refTime)
  else
    return v -- fallback
  end
end


-- Edge/join crossfade length (in seconds) at a given reference time.
local function edge_len_seconds(refTime)
  return cf_to_seconds(CF_VALUE, refTime)
end

local function join_len_seconds(refTime)
  local units = (joinXFadeLen == -1.0) and CF_VALUE or joinXFadeLen
  return cf_to_seconds(units, refTime)
end

-- Return effective JOIN length in seconds; auto-scales if too large (boundary CF is unaffected).
local function effective_join_len_seconds(tile_len, refTime)
  local req = join_len_seconds(refTime)              -- requested JOIN in seconds
  local trig = (JOIN_CLAMP_TRIGGER_RATIO or 0.85) * tile_len
  if req >= trig and tile_len > EPS then
    local eff = (JOIN_CLAMP_TO_TILE_RATIO or 0.45) * tile_len
    eff = math.max(EPS, math.min(eff, tile_len - 1e-4))
    if not warned_join_fallback then
      r.ShowMessageBox(
        string.format(
          "Requested JOIN crossfade (%.3fs) is too large vs tile (%.3fs).\nUsing %.3fs (%.0f%% of tile) to keep layout stable.",
          req, tile_len, eff, (eff/tile_len)*100),
        "Repeat to Fill — Auto-adjust", 0)
      warned_join_fallback = true
    end
    return eff
  end
  -- Normal case: use the requested value (clamped to tile_len - epsilon).
  return math.min(req, tile_len - 1e-4)
end




-- Apply fade length + shape to one item.
-- Pass nil to keep that side's length unchanged.
local function apply_item_fade_shape(it, fadeInLen, fadeOutLen)
  if fadeInLen and fadeInLen > 0 then
    reaper.SetMediaItemInfo_Value(it, "D_FADEINLEN",  fadeInLen)
  end
  if fadeOutLen and fadeOutLen > 0 then
    reaper.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", fadeOutLen)
  end

  local preset = (CF_SHAPE_PRESET or "equal_power"):lower()
  if preset == "linear" then
    reaper.SetMediaItemInfo_Value(it, "C_FADEINSHAPE",  0)
    reaper.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE", 0)
    reaper.SetMediaItemInfo_Value(it, "D_FADEINDIR",    0.0)
    reaper.SetMediaItemInfo_Value(it, "D_FADEOUTDIR",   0.0)

  elseif preset == "equal_power" then
    if CF_EQUALPOWER_VIA_ACTION then
      -- Action 41529 will stamp the equal-power shape; length is already set above.
      -- Do not write shape/curve here to avoid conflicting with 41529.
    else
      -- Internal curve approximation (used when CF_EQUALPOWER_VIA_ACTION = false).
      local s = (CF_EQUALPOWER_FLIP and -1 or 1)
      reaper.SetMediaItemInfo_Value(it, "C_FADEINSHAPE",  0)
      reaper.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE", 0)
      reaper.SetMediaItemInfo_Value(it, "D_FADEINDIR",   0.45 * s)
      reaper.SetMediaItemInfo_Value(it, "D_FADEOUTDIR", -0.45 * s)
    end


  else -- "custom"
    reaper.SetMediaItemInfo_Value(it, "C_FADEINSHAPE",  math.floor(CF_SHAPE_IN or 0))
    reaper.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE", math.floor(CF_SHAPE_OUT or 0))
    reaper.SetMediaItemInfo_Value(it, "D_FADEINDIR",    CF_CURVE_IN  or 0.0)
    reaper.SetMediaItemInfo_Value(it, "D_FADEOUTDIR",   CF_CURVE_OUT or 0.0)
  end
end

-- Extend item's left edge leftward by amt seconds, keeping the right boundary fixed.
-- Returns the actual amount extended (clamped by available source material).
local function extend_item_left_no_move_right_clamped(it, amt)
  if not it or not (amt and amt > 0) then return 0 end
  local tk = r.GetActiveTake(it)
  if not tk then return 0 end

  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
  local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")  -- seconds in source domain
  local loop = r.GetMediaItemTakeInfo_Value(tk, "B_LOOPSRC") > 0.5

  -- Without looping, max leftward extension in project time = offs / rate.
  local max_left = loop and amt or math.min(amt, (offs or 0) / math.max(rate, 1e-9))

  if max_left <= 0 then return 0 end
  r.SetMediaItemInfo_Value(it, "D_POSITION", pos - max_left)
  r.SetMediaItemInfo_Value(it, "D_LENGTH",   len + max_left)
  -- Shift take offset to keep content in place.
  r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", math.max(0, offs - max_left * rate))
  return max_left
end




-- Manual JOIN crossfades: ensure adjacent items overlap; extend the left item's right edge if needed.
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
        r.SetMediaItemInfo_Value(L.it, "D_LENGTH", Ll + need)  -- extend only the left item's right edge
        L.e = L.e + need
        overlap = L.e - R.p
      end

      if overlap > EPS then
        local fade = math.min(joinLen, overlap)
        apply_item_fade_shape(L.it, nil,  fade)  -- left item: fade-out only
        apply_item_fade_shape(R.it, fade, nil )  -- right item: fade-in only
      end

    end
  end
end

-- Build the staged block of length total_len at stage_pos (JOIN overlaps applied in staging too)
local function build_staging_block(stage_pos, total_len, tile_len, base_track, tracks_sorted)
  -- For multi-track paste: use only the top track of this group as the anchor.
  select_only_track(base_track)
  r.Main_OnCommand(40914,0) -- Track: Set first selected track as last touched track (reassert for safety)

  local join_req = join_len_seconds(stage_pos)
  local join_eff = effective_join_len_seconds(tile_len, stage_pos)

  -- If JOIN is near tile length, stage with butt pastes (join_for_staging=0) to avoid long loops.
  local join_for_staging = (join_req >= tile_len * (MAX_JOIN_RATIO_FOR_STAGING or 0.80)) and 0 or join_eff
  local step = math.max(EPS, tile_len - join_for_staging)


  local max_iters = math.ceil((total_len / math.max(step, 1e-3)) + 2)
  if max_iters > 4000 then step = math.max(step, 0.01) end

  local t = stage_pos
  while t < stage_pos + total_len - EPS do
    r.SetEditCurPos(t, false, false)
    r.Main_OnCommand(40914,0) -- reassert last touched to the top track
    r.Main_OnCommand(42398,0) -- Paste
    remap_selected_items_by_relative_top(tracks_sorted)
    t = t + step
    local left = (stage_pos + total_len) - t
    local tiny_threshold = math.max(2*join_for_staging + 1e-4, total_len * preventTinyLastFactor)
    if left < tiny_threshold then break end
  end
  if t < stage_pos + total_len - EPS then
    r.SetEditCurPos(t, false, false)
    r.Main_OnCommand(40914,0) -- reassert last touched
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
  -- Suspend "Trim content behind media items" to prevent right-edge being eaten during boundary extension.
  local TRIM_CMD = 41117
  local trim_was_on = (r.GetToggleCommandState(TRIM_CMD) == 1)
  if trim_was_on then r.Main_OnCommand(TRIM_CMD,0) end

  if fadeLen<=EPS then return end
  local align = (EDGE_XF_ALIGN or "right"):lower()
  local half  = fadeLen * 0.5


  for _,tr in ipairs(tracks_sorted) do
    -- ===== LEFT boundary =====
    local leftN  = find_left_neighbor(tr, start_t)
    local first  = first_item_in_area_on_track(tr, start_t, end_t)

    if first then
      if leftN then
        if align == "center" then
          -- Centered: extend left neighbor right by half; extend first item left by half.
          local ll = r.GetMediaItemInfo_Value(leftN,"D_LENGTH")
          r.SetMediaItemInfo_Value(leftN,"D_LENGTH", ll + half)
          extend_item_left_no_move_right_clamped(first, half)
        elseif align == "left" then
          -- Outside: extend first item leftward by full fade length.
          extend_item_left_no_move_right_clamped(first, fadeLen)
        else -- "right"
          -- Inside: extend left neighbor rightward by full fade length.
          local ll = r.GetMediaItemInfo_Value(leftN,"D_LENGTH")
          r.SetMediaItemInfo_Value(leftN,"D_LENGTH", ll + fadeLen)
        end

        -- Apply shape/length (both sides at least fadeLen).
        local fin  = math.max(fadeLen, r.GetMediaItemInfo_Value(first, "D_FADEINLEN"))
        local fout = math.max(fadeLen, r.GetMediaItemInfo_Value(leftN, "D_FADEOUTLEN"))
        apply_item_fade_shape(first, fin, nil)
        apply_item_fade_shape(leftN, nil,  fout)
      else
        -- No left neighbor; apply fade-in to first item only if not restricted to edge-to-edge.
        if not edgeToEdgeOnly then
          local fin = math.max(fadeLen, r.GetMediaItemInfo_Value(first,"D_FADEINLEN"))
          apply_item_fade_shape(first, fin, nil)
        end
      end
    end

    -- ===== RIGHT boundary =====
    local rightN = find_right_neighbor(tr, end_t)
    local last   = last_item_in_area_on_track(tr, start_t, end_t)

    if last then
      if rightN then
        if (EDGE_XF_ALIGN or "right"):lower() == "center" and EDGE_XF_MOVE_OUTSIDE then
          -- Centered: extend last item right by half; extend right neighbor left by half (clamped if source is short).
          local half2 = fadeLen * 0.5
          local llen  = r.GetMediaItemInfo_Value(last,"D_LENGTH")
          r.SetMediaItemInfo_Value(last,"D_LENGTH", llen + half2)

          local gotR  = extend_item_left_no_move_right_clamped(rightN, half2)
          if gotR < half2 - EPS then
            -- Right neighbor source too short: fall back to the achievable symmetric value.
            local want = gotR
            -- Roll back inner extension to maintain symmetric overlap.
            r.SetMediaItemInfo_Value(last,"D_LENGTH", llen + want)
            half2 = want
          end
          -- Apply fades on both sides (length at least fadeLen).
          local fout = math.max(fadeLen, r.GetMediaItemInfo_Value(last,   "D_FADEOUTLEN"))
          local fin  = math.max(fadeLen, r.GetMediaItemInfo_Value(rightN, "D_FADEINLEN"))
          apply_item_fade_shape(last,   nil, fout)
          apply_item_fade_shape(rightN, fin, nil )

        elseif (EDGE_XF_ALIGN or "right"):lower() == "left" and EDGE_XF_MOVE_OUTSIDE then
          -- Outside: extend right neighbor leftward by full length (clamped if source is short).
          local got = extend_item_left_no_move_right_clamped(rightN, fadeLen)
          local fout = math.max(got, r.GetMediaItemInfo_Value(last,"D_FADEOUTLEN"))
          local fin  = math.max(got, r.GetMediaItemInfo_Value(rightN,"D_FADEINLEN"))
          apply_item_fade_shape(last, nil, fout)
          apply_item_fade_shape(rightN, fin, nil)

        else
          -- "right" or EDGE_XF_MOVE_OUTSIDE=false: entirely inside, extend last item only.
          local llen = r.GetMediaItemInfo_Value(last,"D_LENGTH")
          r.SetMediaItemInfo_Value(last,"D_LENGTH", llen + fadeLen)
          local fout = math.max(fadeLen, r.GetMediaItemInfo_Value(last,"D_FADEOUTLEN"))
          local fin  = math.max(fadeLen, r.GetMediaItemInfo_Value(rightN,"D_FADEINLEN"))
          apply_item_fade_shape(last, nil, fout)
          apply_item_fade_shape(rightN, fin, nil)
        end

      else
        -- No right neighbor; apply fade-out to last item only if not restricted to edge-to-edge.
        if not edgeToEdgeOnly then
          local fout = math.max(fadeLen, r.GetMediaItemInfo_Value(last,"D_FADEOUTLEN"))
          apply_item_fade_shape(last, nil, fout)
        end
      end
    end

  end

  -- Restore "Trim content behind" preference.
  if trim_was_on then r.Main_OnCommand(TRIM_CMD,0) end
end


-- Stamp equal-power crossfade shape (Action 41529) over all crossfades in the target range.
local function stamp_system_equal_power(start_t, end_t, tracks_sorted)
  -- 1) Save current time selection and item/track selection.
  local ts_st, ts_en = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local saved_items, saved_tracks = {}, {}
  for i=0, r.CountSelectedMediaItems(0)-1 do
    saved_items[#saved_items+1] = r.GetSelectedMediaItem(0,i)
  end
  for i=0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0,i)
    if r.GetMediaTrackInfo_Value(tr,"I_SELECTED") > 0.5 then saved_tracks[#saved_tracks+1]=tr end
  end

  -- 2) Select target tracks.
  r.Main_OnCommand(40297,0)
  for _,tr in ipairs(tracks_sorted) do r.SetMediaTrackInfo_Value(tr,"I_SELECTED",1) end

  -- 3) Expand time selection to include boundary neighbors on both sides.
  local edgeL = edge_len_seconds(start_t)
  local edgeR = edge_len_seconds(end_t)
  local padL  = (edgeL > 0) and edgeL or 0
  local padR  = (edgeR > 0) and edgeR or 0
  local t1    = start_t - padL
  local t2    = end_t   + padR
  r.GetSet_LoopTimeRange2(0, true, false, t1, t2, false)

  -- 4) Select all items on target tracks within the expanded time selection.
  r.Main_OnCommand(40718,0) -- Item: Select all items on selected tracks in current time selection

  -- 5) Apply equal-power shape (action 41529).
  r.Main_OnCommand(41529,0) -- Item: Set crossfade shape to type 2 (equal power)

  -- 6) Restore saved state.
  r.GetSet_LoopTimeRange2(0, true, false, ts_st, ts_en, false)
  r.Main_OnCommand(40289,0) -- Unselect items
  for _,it in ipairs(saved_items) do if r.ValidatePtr2(0,it,"MediaItem*") then r.SetMediaItemSelected(it, true) end end
  r.Main_OnCommand(40297,0)
  for _,tr in ipairs(saved_tracks) do if r.ValidatePtr2(0,tr,"MediaTrack*") then r.SetMediaTrackInfo_Value(tr,"I_SELECTED",1) end end
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
  local join = effective_join_len_seconds(tile_len, start_t)
  if join > EPS then
    ensure_join_crossfades_in_range(start_t, end_t, tracks_sorted, join)
  end


  -- boundary crossfades (edge-to-edge only if option true), no item movement
  local edgeSec = edge_len_seconds(start_t)
  if edgeSec > EPS then
    apply_boundary_crossfades(start_t, end_t, tracks_sorted, edgeSec)
  end

  -- If equal-power via action, stamp all crossfades (JOIN + boundary) at the end.
  if (CF_SHAPE_PRESET or "equal_power") == "equal_power" and CF_EQUALPOWER_VIA_ACTION then
    stamp_system_equal_power(start_t, end_t, tracks_sorted)
  end



  -- cleanup staging envelopes (if any were pasted there)
  purge_track_envelopes_in_range(stage_pos-0.001, stage_pos + total + 0.001)
end




-- ============================== fallback target builders ==============================
-- Build a single group from time selection and currently selected tracks.
local function get_target_from_time_selection()
  local ts_start, ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if ts_end <= ts_start + EPS then return nil, nil, "No valid time selection." end

  local tracks = {}
  for i = 0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0, i)
    if r.GetMediaTrackInfo_Value(tr, "I_SELECTED") > 0.5 then
      tracks[#tracks+1] = tr
    end
  end
  if #tracks == 0 then
    return nil, nil, "Time selection found, but no tracks selected.\nPlease select at least one track."
  end
  table.sort(tracks, function(a, b) return track_index(a) < track_index(b) end)

  local key    = string.format("%.15f|%.15f", ts_start, ts_end)
  local groups = { [key] = { start=ts_start, finish=ts_end, tracks=tracks } }
  local order  = { key }
  return groups, order, nil
end

-- Build a single group from item selection's bounding box and their tracks.
local function get_target_from_item_selection()
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then
    return nil, nil, "No Razor Edit, no time selection, and no items selected."
  end

  local min_start  = math.huge
  local max_end    = -math.huge
  local tracks_set = {}
  local tracks     = {}
  for i = 0, n-1 do
    local it = r.GetSelectedMediaItem(0, i)
    local p  = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local l  = r.GetMediaItemInfo_Value(it, "D_LENGTH")
    local tr = r.GetMediaItem_Track(it)
    if p < min_start then min_start = p end
    if p+l > max_end then max_end = p+l end
    local tkey = tostring(tr)
    if not tracks_set[tkey] then
      tracks_set[tkey] = true
      tracks[#tracks+1] = tr
    end
  end
  if max_end <= min_start + EPS then
    return nil, nil, "Selected items have zero total length."
  end
  table.sort(tracks, function(a, b) return track_index(a) < track_index(b) end)

  local key    = string.format("%.15f|%.15f", min_start, max_end)
  local groups = { [key] = { start=min_start, finish=max_end, tracks=tracks } }
  local order  = { key }
  return groups, order, nil
end

-- ============================== main ==============================
local function main()
  local areas, err = get_razor_areas_items_only()
  if err then r.ShowMessageBox(err, "Repeat to Fill", 0); return end

  local groups = {}
  local order  = {}
  local used_razor = (#areas > 0)

  if used_razor then
    -- Razor Edit found: original pipeline.
    groups, order = group_areas_by_range(areas)
  else
    -- No Razor Edit: try time selection first.
    local ts_start, ts_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if ts_end > ts_start + EPS then
      local g, o, e2 = get_target_from_time_selection()
      if not g then r.ShowMessageBox(e2, "Repeat to Fill", 0); return end
      groups, order = assert(g), assert(o)
    else
      -- No time selection: fall back to item selection.
      local g, o, e2 = get_target_from_item_selection()
      if not g then r.ShowMessageBox(e2, "Repeat to Fill", 0); return end
      groups, order = assert(g), assert(o)
    end
  end

  local arrangeStart, arrangeEnd = r.GetSet_ArrangeView2(0,false,0,0,0,0)
  local curpos = r.GetCursorPosition()
  local sel_items, sel_tracks = snapshot_selection()

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  unselect_all()

  -- measure tile once (use first group's top track)
  local first_base
  for _, k in ipairs(order) do
    local fg = groups[k]
    if fg ~= nil then first_base = fg.tracks[1] end
    break
  end
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

  -- process each group
  for _,key in ipairs(order) do
    local g = groups[key]
    process_group(g.start, g.finish, g.tracks, tile_len)
  end

  -- Restore or clear Razor edits (only when Razor mode was used).
  if used_razor then
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
  end

  -- restore selection & UI
  restore_selection(sel_items, sel_tracks)
  local g0 = groups[order[1]]
  if leaveCursorLocation==1 then r.SetEditCurPos(g0.start,false,false)
  elseif leaveCursorLocation==2 then r.SetEditCurPos(g0.finish,false,false)
  else r.SetEditCurPos(curpos,false,false) end
  r.GetSet_ArrangeView2(0,true,0,0,arrangeStart,arrangeEnd)

  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("hsuanice — Paste Special: Repeat to Fill Selection", -1)
  r.UpdateArrange()
end

main()
