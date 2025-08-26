--[[
@description hsuanice_Pro Tools Paste Special: Repeat to Fill Selection
@version 0.4.4
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
  v0.4.4 - Robust handling when JOIN ≈ tile:
           • Auto-adjust JOIN to a percent of tile (configurable via
             JOIN_CLAMP_TRIGGER_RATIO / JOIN_CLAMP_TO_TILE_RATIO) to keep layout stable.
           • Staging switches to butt-pastes when JOIN is near tile
             (MAX_JOIN_RATIO_FOR_STAGING) to avoid tiny step sizes and UI stalls.
           • Only one warning dialog (“Auto-adjust”) is shown; removed the extra
             “Clamped to prevent hang” dialog in staging.
           • Performance: no beachball; repeat-to-fill completes immediately even in
             extreme JOIN requests.
           NOTE: In rare edge cases the visual arrangement may still look irregular after
             auto-adjust; see Known issues.

  v0.4.3 - Boundary crossfade alignment options (“left” / “center” / “right”).
           Centering the right edge may extend the outside neighbor’s left edge
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
CF_VALUE       = 48               -- 若 seconds=秒；frames=影格數；grid=幾個 grid 單位
CF_GRID_REF    = "left"            -- 以哪個時間點換算 grid 長度："left"|"center"|"right"（建議 left）



-- Crossfade shape options (v0.3.0)
CF_SHAPE_PRESET   = "equal_power"  -- "linear" | "equal_power" | "custom"
CF_EQUALPOWER_VIA_ACTION = true   -- true: 用 41529 Item: Set crossfade shape to type 2 (equal power) 蓋系統等功率；false: 用自家曲率近似
CF_SHAPE_IN       = 0              -- only used when PRESET="custom", 0..6 (0=linear)
CF_SHAPE_OUT      = 0              -- only used when PRESET="custom", 0..6
CF_CURVE_IN       = 0            -- -1..1, only used when PRESET="custom"
CF_CURVE_OUT      = 0            -- -1..1, only used when PRESET="custom"
CF_EQUALPOWER_FLIP = true   -- set true if you feel the equal-power curvature is reversed

-- Edge (boundary) crossfade alignment on the Razor borders only:
--   "right"  = 全部在邊界內側（現行行為）
--   "center" = 以邊界為中心，左右各一半
--   "left"   = 全部在邊界外側
-- 內部 JOIN：置中
JOIN_XF_ALIGN = "center"   -- "right" | "center" | "left"

-- 邊界 EDGE：置中，允許向外側延左緣（只動左緣、不動右邊界）
EDGE_XF_ALIGN = "center"   -- "right" | "center" | "left"
EDGE_XF_MOVE_OUTSIDE = true

-- When JOIN >= this ratio of tile_len, stage with BUTT pastes (join_for_staging=0)
-- and create overlaps later in target (prevents long loops & beachball).
MAX_JOIN_RATIO_FOR_STAGING = 0.80

-- If requested JOIN is too large vs tile, auto-scale JOIN to a percent of tile:
JOIN_CLAMP_TRIGGER_RATIO = 0.85   -- 當 (JOIN >= 85% * tile_len) 就觸發縮減
JOIN_CLAMP_TO_TILE_RATIO = 0.35   -- 縮減為 tile_len 的 45%（可改 0.3~0.6 視口味）




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
local STAGE_PAD                 = 60.0

local EPS                       = 1e-9

local warned_join_clamp   = false
local warned_join_fallback = false   -- ⬅︎ 新增：JOIN 太大時只彈一次提示
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

-- 選取整組目標軌，並把第一條設為 last touched（作為貼上的基準）
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
-- 僅清除 [t1,t2] 內的片段；保留貼齊邊界的外側 item
-- 在 FIPM 下也會逐個 lane 精準切割與刪除
local function clear_items_in_range_on_tracks(t1,t2, tracks_sorted)
  -- 用較寬鬆的容差（約 1 ms），避免浮點/取樣邊界漏切
  local EPSX = 0.001

  for _,tr in ipairs(tracks_sorted) do
    -- pass1：把跨越 t1/t2 的 item 先切開（剛好等於邊界的不切）
    for i = r.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if p < t1 - EPSX and e > t1 + EPSX then r.SplitMediaItem(it, t1) end
      if p < t2 - EPSX and e > t2 + EPSX then r.SplitMediaItem(it, t2) end
    end

    -- pass2：刪除完全落在 [t1-ε, t2+ε] 內的片段（含剛好等於邊界）
    for i = r.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if p >= t1 - EPSX and e <= t2 + EPSX then
        r.DeleteTrackMediaItem(tr, it)
      end
    end

    -- pass3（保險）：若仍有殘留與區段相交者，再切再刪一次
    for i = r.CountTrackMediaItems(tr)-1, 0, -1 do
      local it = r.GetTrackMediaItem(tr,i)
      local p  = r.GetMediaItemInfo_Value(it,"D_POSITION")
      local l  = r.GetMediaItemInfo_Value(it,"D_LENGTH")
      local e  = p + l
      if e > t1 + EPSX and p < t2 - EPSX then
        -- 這裡一定是跨界殘留（例如極小浮點誤差），直接在邊界再切一次再判斷
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

-- convert a length value (edgeXFadeLen / joinXFadeLen) from CF_UNIT to seconds
-- return seconds for CF_VALUE in the selected unit, referenced at refTime
local function cf_grid_len_seconds(units, refTime)
  -- anchor：依設定抓參考點附近的格線，統一從「左邊格線」開始量
  local t_ref = refTime or reaper.GetCursorPosition()
  local t_left = reaper.BR_GetClosestGridDivision(t_ref)
  if t_left > t_ref + 1e-12 then
    -- 最靠近但在右邊，就退到前一格
    t_left = reaper.BR_GetPrevGridDivision(t_left)
  end
  if CF_GRID_REF == "right" then
    -- 以右側為基準則先進一格當起點
    t_left = reaper.BR_GetNextGridDivision(t_left)
  elseif CF_GRID_REF == "center" then
    -- 以中心為基準：先找到邊界所在格，再往左半格
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
    local fps = reaper.TimeMap_curFrameRate(0) -- seconds/frame = 1/fps
    return v / (fps > 0 and fps or 1)
  elseif CF_UNIT == "grid" then
    return cf_grid_len_seconds(v, refTime)
  else
    return v -- fallback
  end
end


-- edge/join crossfade length (in SECONDS) at a given reference time
local function edge_len_seconds(refTime)
  return cf_to_seconds(CF_VALUE, refTime)
end

local function join_len_seconds(refTime)
  local units = (joinXFadeLen == -1.0) and CF_VALUE or joinXFadeLen
  return cf_to_seconds(units, refTime)
end

-- 取「有效 JOIN 秒數」；若過大，依比例縮減（僅 JOIN 用；邊界不受影響）
local function effective_join_len_seconds(tile_len, refTime)
  local req = join_len_seconds(refTime)              -- 你原本的換算（秒）
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
  -- 正常情況直接用原請求（含你已有的 clamp）
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
      -- 讓 41529 Item: Set crossfade shape to type 2 (equal power)來蓋「等功率」形狀；這裡只保證長度有設到（上面已寫 D_FADEIN/OUTLEN）
      -- 不再在這裡寫 shape/curve，避免和 41529 打架
    else
      -- 若想用自家近似（不用 41529），就保留下面這段
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

-- 向左延伸 item 的左緣 amt 秒，保持右邊界不動；若素材不夠，回傳實際可延長秒數
local function extend_item_left_no_move_right_clamped(it, amt)
  if not it or not (amt and amt > 0) then return 0 end
  local tk = r.GetActiveTake(it)
  if not tk then return 0 end

  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
  local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")       -- 秒（source domain）
  local loop = r.GetMediaItemTakeInfo_Value(tk, "B_LOOPSRC") > 0.5

  -- 在不 Loop 的情況下，可向左延的「工程秒」= offs / rate
  local max_left = loop and amt or math.min(amt, (offs or 0) / math.max(rate, 1e-9))

  if max_left <= 0 then return 0 end
  r.SetMediaItemInfo_Value(it, "D_POSITION", pos - max_left)
  r.SetMediaItemInfo_Value(it, "D_LENGTH",   len + max_left)
  -- 同步滑移 take offset，確保內容不變
  r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", math.max(0, offs - max_left * rate))
  return max_left
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
        apply_item_fade_shape(L.it, nil,  fade)  -- 左塊：只設出淡
        apply_item_fade_shape(R.it, fade, nil )  -- 右塊：只設入淡
      end

    end
  end
end

-- Build the staged block of length total_len at stage_pos (JOIN overlaps applied in staging too)
local function build_staging_block(stage_pos, total_len, tile_len, base_track, tracks_sorted)
  -- 多軌貼上的正確作法：只選本組的最上面那一軌當「錨點」
  select_only_track(base_track)
  r.Main_OnCommand(40914,0) -- Track: Set first selected track as last touched track（保險重申一次）

  local join_req = join_len_seconds(stage_pos)
  local join_eff = effective_join_len_seconds(tile_len, stage_pos)


  -- staging 若為極端（JOIN 逼近 tile），一律用 butt 貼（join_for_staging=0）
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
  if fadeLen<=EPS then return end
  local align = (EDGE_XF_ALIGN or "right"):lower()
  local half  = fadeLen * 0.5

  -- 在置中時，為避免「Trim content behind」把重疊的一側吃掉，可暫時關掉；做完還原
  local TRIM_CMD = 41117 -- Options: Trim content behind media items when editing
  local trim_was_on = (r.GetToggleCommandState(TRIM_CMD) == 1)
  local need_temp_untrim = (align=="center" or align=="left")  -- 會做左延時才需要
  if need_temp_untrim and trim_was_on then r.Main_OnCommand(TRIM_CMD,0) end

  for _,tr in ipairs(tracks_sorted) do
    -- ===== LEFT boundary =====
    local leftN  = find_left_neighbor(tr, start_t)
    local first  = first_item_in_area_on_track(tr, start_t, end_t)

    if first then
      if leftN then
        if align == "center" then
          -- 左鄰向右延一半；區內第一塊向左延一半（置中）
          local ll = r.GetMediaItemInfo_Value(leftN,"D_LENGTH")
          r.SetMediaItemInfo_Value(leftN,"D_LENGTH", ll + half)
          extend_item_left_no_move_right_clamped(first, half)
        elseif align == "left" then
          -- 全部放在邊界外側：只把區內第一塊向左延整個長度
          extend_item_left_no_move_right_clamped(first, fadeLen)
        else -- "right"
          -- 現行：全在內側，僅左鄰向右延整個長度
          local ll = r.GetMediaItemInfo_Value(leftN,"D_LENGTH")
          r.SetMediaItemInfo_Value(leftN,"D_LENGTH", ll + fadeLen)
        end

        -- 形狀/長度（兩側都至少是 fadeLen）
        local fin  = math.max(fadeLen, r.GetMediaItemInfo_Value(first, "D_FADEINLEN"))
        local fout = math.max(fadeLen, r.GetMediaItemInfo_Value(leftN, "D_FADEOUTLEN"))
        apply_item_fade_shape(first, fin, nil)
        apply_item_fade_shape(leftN, nil,  fout)
      else
        -- 沒有左鄰，但若你不強制 edge-to-edge 才做，可以在此僅對第一塊給淡入
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
          -- 置中：區內最後一塊向右延一半；右鄰向左延一半（若素材不足，會夾緊）
          local half  = fadeLen * 0.5
          local llen  = r.GetMediaItemInfo_Value(last,"D_LENGTH")
          r.SetMediaItemInfo_Value(last,"D_LENGTH", llen + half)

          local gotR  = extend_item_left_no_move_right_clamped(rightN, half)
          if gotR < half - EPS then
            -- 右鄰素材不足：把「置中」改為「可達到的對稱值」
            local want = gotR
            -- 回退內側延伸，保持重疊對稱
            r.SetMediaItemInfo_Value(last,"D_LENGTH", llen + want)
            half = want
          end
          -- 設置兩側淡化（長度至少 half）
          local fout = math.max(half, r.GetMediaItemInfo_Value(last,   "D_FADEOUTLEN"))
          local fin  = math.max(half, r.GetMediaItemInfo_Value(rightN, "D_FADEINLEN"))
          apply_item_fade_shape(last,   nil, fout)
          apply_item_fade_shape(rightN, fin, nil )

        elseif (EDGE_XF_ALIGN or "right"):lower() == "left" and EDGE_XF_MOVE_OUTSIDE then
          -- 全部在外側：只把右鄰向左延整個長度（不足則夾緊）
          local got = extend_item_left_no_move_right_clamped(rightN, fadeLen)
          local fout = math.max(got, r.GetMediaItemInfo_Value(last,"D_FADEOUTLEN"))
          local fin  = math.max(got, r.GetMediaItemInfo_Value(rightN,"D_FADEINLEN"))
          apply_item_fade_shape(last, nil, fout)
          apply_item_fade_shape(rightN, fin, nil)

        else
          -- "right" 或不允許動外側：全在內側，只延長區內最後一塊
          local llen = r.GetMediaItemInfo_Value(last,"D_LENGTH")
          r.SetMediaItemInfo_Value(last,"D_LENGTH", llen + fadeLen)
          local fout = math.max(fadeLen, r.GetMediaItemInfo_Value(last,"D_FADEOUTLEN"))
          local fin  = math.max(fadeLen, r.GetMediaItemInfo_Value(rightN,"D_FADEINLEN"))
          apply_item_fade_shape(last, nil, fout)
          apply_item_fade_shape(rightN, fin, nil)
        end

      else
        -- 沒右鄰；若非 edge-to-edge 限制，可只對 last 給淡出
        if not edgeToEdgeOnly then
          local fout = math.max(fadeLen, r.GetMediaItemInfo_Value(last,"D_FADEOUTLEN"))
          apply_item_fade_shape(last, nil, fout)
        end
      end
    end

  end

  -- 還原 Trim behind
  if need_temp_untrim and trim_was_on then r.Main_OnCommand(TRIM_CMD,0) end
end


-- 用系統等功率形狀（Action 41529）蓋掉選區內、指定軌的交叉形狀
local function stamp_system_equal_power(start_t, end_t, tracks_sorted)
  -- 1) 暫存原本的 time selection & selection
  local ts_st, ts_en = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  local saved_items, saved_tracks = {}, {}
  for i=0, r.CountSelectedMediaItems(0)-1 do
    saved_items[#saved_items+1] = r.GetSelectedMediaItem(0,i)
  end
  for i=0, r.CountTracks(0)-1 do
    local tr = r.GetTrack(0,i)
    if r.GetMediaTrackInfo_Value(tr,"I_SELECTED") > 0.5 then saved_tracks[#saved_tracks+1]=tr end
  end

  -- 2) 選本組軌
  r.Main_OnCommand(40297,0)
  for _,tr in ipairs(tracks_sorted) do r.SetMediaTrackInfo_Value(tr,"I_SELECTED",1) end

  -- 3) 依邊界交叉長度擴張 time selection（確保包含邊界兩側的成對 items）
  local edgeL = edge_len_seconds(start_t)
  local edgeR = edge_len_seconds(end_t)
  local padL  = (edgeL > 0) and edgeL or 0
  local padR  = (edgeR > 0) and edgeR or 0
  local t1    = start_t - padL
  local t2    = end_t   + padR
  r.GetSet_LoopTimeRange2(0, true, false, t1, t2, false)

  -- 4) 選擇這些軌在 time selection 內的所有 items
  r.Main_OnCommand(40718,0) -- Item: Select all items on selected tracks in current time selection

  -- 5) 套等功率形狀（41529）
  r.Main_OnCommand(41529,0) -- Item: Set crossfade shape to type 2 (equal power)

  -- 6) 還原
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

  -- 若選擇用系統等功率形狀，最後蓋一次（JOIN + 邊界一起）
  if (CF_SHAPE_PRESET or "equal_power") == "equal_power" and CF_EQUALPOWER_VIA_ACTION then
    stamp_system_equal_power(start_t, end_t, tracks_sorted)
  end



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
  r.Undo_EndBlock("hsuanice — Paste Special: Repeat to Fill Selection", -1)
  r.UpdateArrange()
end

main()
