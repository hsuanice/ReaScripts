-- @description hsuanice_Pro Tools Create Fades
-- @version 0.3.8 [260418.1035]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools: **Create Fades**
--
--   Auto-detects fade type from time selection + items:
--   - ts before item start, te inside item  → Fade In
--   - ts inside item, te after item end     → Fade Out
--   - items overlap, ts inside overlap area → Crossfade
--   - ts≈first item start AND te≈last item end → Batch (all three)
--
--   Mac shortcut (PT): Command + F
--
-- @changelog
--   0.3.8 [260418.1035]
--     - Fix: xfade detection only pairs items on the same track
--   0.3.7 [260418.1027]
--     - Fix: set xfade length before AND after action to prevent shape reset
--   0.3.6 [260418.1013]
--     - Fix: existing overlap resize — adjust item boundaries when xfade length changes
--     - Fix: touching uses extend by half each side; overlap uses same approach
--   0.3.5 [260417.2041]
--     - Fix: shape-only mode reads existing fadeout length instead of using 10ms fallback
--     - Fix: xfade length logic: batch=ms, real overlap=overlap, touching=existing or default
--   0.3.4 [260417.2028]
--     - Fix: call UpdateArrange after extending touching items before applying xfade shape
--     - Fix: re-apply xfade length after action call
--   0.3.3 [260417.2018]
--     - Fix: xfade boundaries excluded from fadein/fadeout lists (no duplicate settings)
--     - Fix: same exclusion applied to no-selection case
--   0.3.2 [260417.2013]
--     - Fix: XFADE_GAP=5ms for touch detection (was EPS=0.1ms, too small for sample-level gaps)
--     - Fix: touching flag based on gap>=0 not overlap<EPS
--   0.3.1 [260417.2006]
--     - Fix: clicking new input field commits previous field first
--     - Fix: clicking input field clears to empty (type to replace)
--     - Fix: commit_field keeps old value when nothing typed
--     - Fix: batch mode checks each item individually for fade in/out
--   0.3.0 [260417.1946]
--     - Rewrite detect: Razor > Time Sel > Item Sel priority
--     - Single boundary: use selection length, shape-only UI (no ms field)
--     - Multiple items or xfade: batch UI with ms fields
--     - No selection: batch UI, ms from settings
--     - Fix: xfade length uses selection/overlap in shape-only mode
--     - Fix: apply respects use_ms flag per fade item
--   0.2.6 [260417.1848]
--     - Fix: batch detection uses covers_start+covers_end (not exact match)
--     - Fix: no-time-sel always adds all items to list (creates new fades if none exist)
--     - Fix: multiple items with razor/time > item span now detected correctly
--     - Fix: touch+multiple items now shows full batch UI
--     - Fix: xfade length in apply correctly uses S.xfade_ms in batch mode
--   0.2.5 [260417.1836]
--     - Fix: commit_field moved to frame scope (was inside batch block, invisible to OK button)
--   0.2.4 [260417.1831]
--     - Fix: click-outside uses mouse-up edge (just_released) not held state
--     - Fix: commit keeps current value if input is invalid/empty
--     - Add: ExtState remembers last ms values across sessions
--   0.2.3 [260417.1828]
--     - Fix: Type 5 = t^4 (steeper concave, more arched than Type 3)
--   0.2.2 [260417.1708]
--     - Fix: Type 2 = 1-(1-t)^2 (fast start); Type 4 = very fast start; Type 5 = asymmetric S
--   0.2.1 [260417.1703]
--     - Fix: Type 6 = gentle S-curve (smooth step); Type 7 = steeper S
--   0.2.0 [260417.1702]
--     - Fix: curve_y rewritten to match actual Reaper visual shapes from screenshot
--     - Fix: shape names updated (Type 1=Linear, Type 2=Equal Power, rest=Type N)
--   0.1.9 [260417.1656]
--     - Fix: remove D_FADEINDIR override — just call action, let Reaper set shape correctly
--     - Fix: remove SHAPE_DIR table (unnecessary)
--     - Fix: shape names simplified to Type 1-7 to match Reaper action names
--   0.1.8 [260417.1648]
--     - Confirmed: Fade Out (41521-41526,41837) and Crossfade (41528-41533,41838)
--       share same shape order as Fade In — no command changes needed
--     - Fade Out preview correctly mirrors Fade In (1-t transform)
--     - Crossfade preview shows both curves crossing
--   0.1.7 [260417.1640]
--     - Fix: correct shape order from visual testing (S-Curve=type7, Fast Start=type3, etc.)
--     - Fix: SHAPE_DIR updated to match actual Reaper storage values
--     - Fix: curve_y preview corrected for all 7 shapes
--   0.1.6 [260417.1624]
--     - Fix: SHAPE_DIR corrected from visual testing (Fast Start/End swapped, S-Curve dir=0)
--     - Fix: curve_y preview matches actual Reaper visual output
--   0.1.5 [260417.1609]
--     - Fix: set D_FADEINDIR/D_FADEOUTDIR per shape after action call
--     - Fix: fade in length detection (allow te at item end)
--     - Fix: set length after action (not before)
--     - Fix: curve_y matches actual Reaper shape behaviour
--     - Fix: better shape names
--   0.1.4 [260417.1511]
--     - Fix: use detected time sel length for fade, not batch_ms
--     - Fix: batch mode has 3 separate editable length fields
--     - Fix: ESC/Enter won't close window while editing a field
--   0.1.3 [260417.1302]
--     - Fix: gfx.moveto does not exist; use gfx.line for curve drawing
--   0.1.2 [260417.1255]
--     - Fix: rewrite detection logic based on actual PT usage patterns
--     - Fix: fade in = ts before/at item start; fade out = te after/at item end
--   0.1.1 [260417.1232]
--     - Fix: proper defer-based GFX loop
--   0.1.0 [260417.1229]
--     - Initial release

local r = reaper

local FADE_IN  = "fade_in"
local FADE_OUT = "fade_out"
local XFADE    = "crossfade"
local EPS       = 1e-4   -- general floating point tolerance
local XFADE_GAP = 0.005  -- items within 5ms are treated as touching (handles sample-level gaps)

local SHAPE_NAMES    = {"Type 1 (Linear)","Type 2 (Equal Power)","Type 3","Type 4","Type 5","Type 6","Type 7"}
local FADEIN_CMDS    = {41514,41515,41516,41517,41518,41519,41836}
local FADEOUT_CMDS   = {41521,41522,41523,41524,41525,41526,41837}
local XFADE_CMDS     = {41528,41529,41530,41531,41532,41533,41838}

-- ============================================================
-- DETECTION
-- ============================================================
local function get_sel_items()
  local items = {}
  for i = 0, r.CountSelectedMediaItems(0)-1 do
    local it  = r.GetSelectedMediaItem(0,i)
    local pos = r.GetMediaItemInfo_Value(it,"D_POSITION")
    local len = r.GetMediaItemInfo_Value(it,"D_LENGTH")
    items[#items+1] = {item=it, pos=pos, len=len, fin=pos+len}
  end
  table.sort(items, function(a,b) return a.pos < b.pos end)
  return items
end

local function clamp_shape(s)
  return math.max(1, math.min(7, s))
end

local function existing_fadein_shape(item)
  return clamp_shape(math.floor(r.GetMediaItemInfo_Value(item,"C_FADEINSHAPE"))+1)
end
local function existing_fadeout_shape(item)
  return clamp_shape(math.floor(r.GetMediaItemInfo_Value(item,"C_FADEOUTSHAPE"))+1)
end

local function get_razor_range()
  -- Get the union of all track-level razor areas (guid="")
  local min_pos, max_end = math.huge, -math.huge
  local found = false
  for ti = 0, r.CountTracks(0)-1 do
    local track = r.GetTrack(0, ti)
    local _, s = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if s and s ~= "" then
      local toks = {}
      for t in s:gmatch("%S+") do toks[#toks+1] = t end
      for i = 1, #toks-2, 3 do
        local rs = tonumber(toks[i])
        local re = tonumber(toks[i+1])
        local guid = toks[i+2]
        if rs and re and guid == '""' then
          found = true
          if rs < min_pos then min_pos = rs end
          if re > max_end then max_end = re end
        end
      end
    end
  end
  if found then return min_pos, max_end end
  return nil, nil
end

local function detect()
  local items = get_sel_items()

  local det = {
    types={}, items=items,
    fadein_items={}, fadeout_items={}, xfade_pairs={},
    def_fadein_shape=1, def_fadeout_shape=1, def_xfade_shape=2,
    def_batch_ms=10,
    -- show_length: true = show ms fields in UI; false = shape only
    show_length=true,
  }

  if #items == 0 then return det end

  -- Load remembered batch ms
  local EXT_SEC = "hsuanice_PT2Reaper_CreateFades"
  local function remembered_ms(key)
    local v = tonumber(r.GetExtState(EXT_SEC, key))
    return (v and v > 0) and math.floor(v) or det.def_batch_ms
  end
  det.def_batch_ms = remembered_ms("fadein_ms")

  -- Priority: Razor > Time Selection > Item Selection
  local sel_start, sel_end
  local rz_s, rz_e = get_razor_range()
  local ts, te = r.GetSet_LoopTimeRange(false,false,0,0,false)
  local has_ts = te > ts + EPS

  if rz_s then
    sel_start, sel_end = rz_s, rz_e
  elseif has_ts then
    sel_start, sel_end = ts, te
  end

  -- Check xfade pairs (overlapping/touching adjacent items ON THE SAME TRACK)
  for i = 1, #items-1 do
    local a,b = items[i], items[i+1]
    -- Only pair items on the same track
    local track_a = r.GetMediaItemTrack(a.item)
    local track_b = r.GetMediaItemTrack(b.item)
    if track_a ~= track_b then goto continue_xfade end

    local gap = b.pos - a.fin
    if gap <= XFADE_GAP then
      local overlap = math.max(0, a.fin - b.pos)
      det.xfade_pairs[#det.xfade_pairs+1] = {
        left=a, right=b, overlap=overlap,
        touching=(gap >= -EPS)
      }
    end
    ::continue_xfade::
  end

  local has_xfade = #det.xfade_pairs > 0
  local is_multi  = #items > 1

  if sel_start then
    -- We have a selection range (razor or time sel)
    local first = items[1]
    local last  = items[#items]

    -- Determine if this is a "boundary" selection (single edge only)
    -- or a "full coverage" selection (batch)
    local covers_first_start = sel_start <= first.pos + EPS
    local covers_last_end    = sel_end   >= last.fin  - EPS

    if is_multi or has_xfade then
      -- Multiple items: batch UI
      det.show_length = true

      -- Build sets of items that are xfade left/right edges
      -- so we don't add fadein/fadeout on xfade boundaries
      local is_xfade_right = {}  -- item.item pointer → true if it's the right side of an xfade
      local is_xfade_left  = {}  -- item.item pointer → true if it's the left side of an xfade
      for _, pair in ipairs(det.xfade_pairs) do
        is_xfade_left[pair.left.item]   = true  -- left item's right edge = xfade
        is_xfade_right[pair.right.item] = true  -- right item's left edge = xfade
      end

      -- Check each item individually for fade in/out
      -- Skip edges that are part of a crossfade
      for _, it in ipairs(items) do
        local ts_at_start = sel_start <= it.pos + EPS
        local te_at_end   = sel_end   >= it.fin  - EPS
        local te_inside   = sel_end   >  it.pos + EPS and sel_end < it.fin - EPS
        local ts_inside   = sel_start >  it.pos + EPS and sel_start < it.fin - EPS

        -- Fade In: selection covers this item's start
        -- But skip if this item's left edge is part of a crossfade
        if ts_at_start and (te_inside or te_at_end) then
          if not is_xfade_right[it.item] then
            det.fadein_items[#det.fadein_items+1] = {item=it, len=nil, use_ms=true}
          end
        end
        -- Fade Out: selection covers this item's end
        -- But skip if this item's right edge is part of a crossfade
        if te_at_end and (ts_inside or ts_at_start) then
          if not is_xfade_left[it.item] then
            det.fadeout_items[#det.fadeout_items+1] = {item=it, len=nil, use_ms=true}
          end
        end
      end

    else
      -- Single item
      local it = items[1]
      local ts_at_start = sel_start <= it.pos + EPS
      local te_at_end   = sel_end   >= it.fin  - EPS
      local te_inside   = sel_end   >  it.pos + EPS and sel_end < it.fin - EPS
      local ts_inside   = sel_start >  it.pos + EPS and sel_start < it.fin - EPS

      if ts_at_start and te_inside then
        -- Selection covers item start → fade in, length = sel_end - item.pos
        det.fadein_items[#det.fadein_items+1] = {item=it, len=sel_end - it.pos, use_ms=false}
        det.show_length = false  -- shape only

      elseif ts_inside and te_at_end then
        -- Selection covers item end → fade out, length = item.fin - sel_start
        det.fadeout_items[#det.fadeout_items+1] = {item=it, len=it.fin - sel_start, use_ms=false}
        det.show_length = false  -- shape only

      elseif ts_at_start and te_at_end then
        -- Full item coverage → fade in + fade out with ms
        det.fadein_items[#det.fadein_items+1]   = {item=it, len=nil, use_ms=true}
        det.fadeout_items[#det.fadeout_items+1] = {item=it, len=nil, use_ms=true}
        det.show_length = true

      else
        -- Selection inside item (no boundary) → shape only, use existing fade lengths
        local fi_len = r.GetMediaItemInfo_Value(it.item,"D_FADEINLEN")
        local fo_len = r.GetMediaItemInfo_Value(it.item,"D_FADEOUTLEN")
        if fi_len > EPS then
          det.fadein_items[#det.fadein_items+1]   = {item=it, len=fi_len, use_ms=false}
        end
        if fo_len > EPS then
          det.fadeout_items[#det.fadeout_items+1] = {item=it, len=fo_len, use_ms=false}
        end
        det.show_length = false  -- shape only
      end
    end

  else
    -- No selection: item selection only → batch UI with ms
    det.show_length = true

    local is_xfade_right = {}
    local is_xfade_left  = {}
    for _, pair in ipairs(det.xfade_pairs) do
      is_xfade_left[pair.left.item]   = true
      is_xfade_right[pair.right.item] = true
    end

    for _, it in ipairs(items) do
      local fi_len = r.GetMediaItemInfo_Value(it.item,"D_FADEINLEN")
      local fo_len = r.GetMediaItemInfo_Value(it.item,"D_FADEOUTLEN")
      if not is_xfade_right[it.item] then
        det.fadein_items[#det.fadein_items+1]   = {item=it, len=fi_len > EPS and fi_len or nil, use_ms=true}
      end
      if not is_xfade_left[it.item] then
        det.fadeout_items[#det.fadeout_items+1] = {item=it, len=fo_len > EPS and fo_len or nil, use_ms=true}
      end
    end
  end

  -- Build types list
  if #det.fadein_items  > 0 then det.types[#det.types+1] = FADE_IN  end
  if #det.xfade_pairs   > 0 then det.types[#det.types+1] = XFADE   end
  if #det.fadeout_items > 0 then det.types[#det.types+1] = FADE_OUT end

  -- Defaults from existing fades
  if #det.fadein_items  > 0 then
    det.def_fadein_shape  = existing_fadein_shape(det.fadein_items[1].item.item)
  end
  if #det.fadeout_items > 0 then
    det.def_fadeout_shape = existing_fadeout_shape(det.fadeout_items[1].item.item)
  end
  if #det.xfade_pairs   > 0 then
    det.def_xfade_shape   = existing_fadein_shape(det.xfade_pairs[1].right.item)
  end

  return det
end

-- ============================================================
-- APPLY
-- ============================================================
local function apply(det, S)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local function sel_only(item)
    r.Main_OnCommand(40289,0)
    r.SetMediaItemSelected(item,true)
  end

  local is_batch = det.show_length  -- show_length = has ms fields in UI

  for _, fi in ipairs(det.fadein_items) do
    local item = fi.item.item
    local len
    if fi.use_ms then
      len = S.fadein_ms and (S.fadein_ms/1000.0) or fi.len
    else
      len = fi.len  -- use detected length directly
    end
    sel_only(item)
    r.Main_OnCommand(FADEIN_CMDS[S.fadein_shape], 0)
    if len and len > 0 then
      r.SetMediaItemInfo_Value(item, "D_FADEINLEN", len)
    end
  end

  for _, fo in ipairs(det.fadeout_items) do
    local item = fo.item.item
    local len
    if fo.use_ms then
      len = S.fadeout_ms and (S.fadeout_ms/1000.0) or fo.len
    else
      len = fo.len
    end
    sel_only(item)
    r.Main_OnCommand(FADEOUT_CMDS[S.fadeout_shape], 0)
    if len and len > 0 then
      r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", len)
    end
  end

  for _, pair in ipairs(det.xfade_pairs) do
    local left  = pair.left.item
    local right = pair.right.item

    -- Determine target xfade length
    local xlen
    if det.show_length and S.xfade_ms then
      xlen = S.xfade_ms / 1000.0
    elseif pair.overlap > EPS then
      xlen = pair.overlap  -- keep existing overlap length (shape-only mode)
    else
      local existing = r.GetMediaItemInfo_Value(left, "D_FADEOUTLEN")
      xlen = existing > EPS and existing or 0.010
    end

    local current_overlap = pair.overlap
    local needs_resize = math.abs(xlen - current_overlap) > EPS

    if pair.touching then
      -- No overlap yet: extend both items to create xfade
      local half = xlen * 0.5
      local ll   = r.GetMediaItemInfo_Value(left,  "D_LENGTH")
      local rp   = r.GetMediaItemInfo_Value(right, "D_POSITION")
      local rl   = r.GetMediaItemInfo_Value(right, "D_LENGTH")
      local rt   = r.GetActiveTake(right)
      local ro   = rt and r.GetMediaItemTakeInfo_Value(rt,"D_STARTOFFS") or 0
      r.SetMediaItemInfo_Value(left,  "D_LENGTH",   ll + half)
      r.SetMediaItemInfo_Value(right, "D_POSITION", rp - half)
      r.SetMediaItemInfo_Value(right, "D_LENGTH",   rl + half)
      if rt then r.SetMediaItemTakeInfo_Value(rt, "D_STARTOFFS", math.max(0, ro - half)) end
      r.UpdateArrange()

    elseif needs_resize then
      -- Already has overlap but want different length: adjust boundary
      -- Move right item's left edge to achieve target overlap
      local diff   = xlen - current_overlap  -- positive = extend more, negative = shrink
      local rp     = r.GetMediaItemInfo_Value(right, "D_POSITION")
      local rl     = r.GetMediaItemInfo_Value(right, "D_LENGTH")
      local rt     = r.GetActiveTake(right)
      local ro     = rt and r.GetMediaItemTakeInfo_Value(rt,"D_STARTOFFS") or 0
      -- Move right item left by diff/2, and left item right by diff/2
      local half = diff * 0.5
      local ll   = r.GetMediaItemInfo_Value(left, "D_LENGTH")
      r.SetMediaItemInfo_Value(left,  "D_LENGTH",   ll + half)
      r.SetMediaItemInfo_Value(right, "D_POSITION", rp - half)
      r.SetMediaItemInfo_Value(right, "D_LENGTH",   rl + half)
      if rt then r.SetMediaItemTakeInfo_Value(rt, "D_STARTOFFS", math.max(0, ro - half)) end
      r.UpdateArrange()
    end

    -- Apply crossfade shape action
    -- Select both items, apply shape, then enforce lengths
    r.Main_OnCommand(40289,0)
    r.SetMediaItemSelected(left,  true)
    r.SetMediaItemSelected(right, true)

    -- Set lengths BEFORE action so action doesn't reset them
    r.SetMediaItemInfo_Value(left,  "D_FADEOUTLEN", xlen)
    r.SetMediaItemInfo_Value(right, "D_FADEINLEN",  xlen)

    -- Apply shape
    r.Main_OnCommand(XFADE_CMDS[S.xfade_shape], 0)

    -- Re-enforce lengths after action (action may have reset them)
    r.SetMediaItemInfo_Value(left,  "D_FADEOUTLEN", xlen)
    r.SetMediaItemInfo_Value(right, "D_FADEINLEN",  xlen)
  end

  -- Restore original selection
  r.Main_OnCommand(40289,0)
  for _, it in ipairs(det.items) do
    r.SetMediaItemSelected(it.item,true)
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Pro Tools: Create Fades",-1)
end

-- ============================================================
-- GFX HELPERS
-- ============================================================
local function sc(rv,gv,bv,av)
  gfx.set(rv/255,gv/255,bv/255,(av or 255)/255)
end

local function curve_y(t,s)
  if s==1 then
    return t                                        -- Linear
  elseif s==2 then
    return 1-(1-t)*(1-t)                           -- Equal Power: fast start, slow end
  elseif s==3 then
    return t*t                                      -- slow start, fast end (concave)
  elseif s==4 then
    return 1-(1-t)*(1-t)*(1-t)*(1-t)              -- very fast start
  elseif s==5 then
    return t*t*t*t                             -- steeper concave than type 3 (t^4)
  elseif s==6 then
    return t*t*(3-2*t)                             -- gentle S (smooth step)
  elseif s==7 then
    local t2 = t*t*(3-2*t)
    return t2*t2*(3-2*t2)                          -- steeper S
  end
  return t
end

local function draw_preview(x,y,w,h,shape,ft)
  sc(40,40,40); gfx.rect(x,y,w,h,1)
  sc(85,85,85); gfx.rect(x,y,w,h,0)
  local p=5
  local bx,by,bw,bh = x+p,y+p,w-p*2,h-p*2
  sc(52,52,62); gfx.rect(bx,by,bw,bh,1)
  local function plot(cr,cg,cb,tf)
    sc(cr,cg,cb)
    local prev_px, prev_py = nil, nil
    for i=0,bw-1 do
      local t=i/(bw-1)
      local cy=curve_y(tf(t),shape)
      local px=bx+i; local py=by+bh-math.floor(cy*bh)
      if prev_px then gfx.line(prev_px,prev_py,px,py,1) end
      prev_px=px; prev_py=py
    end
  end
  if ft==FADE_IN  then plot(255,80,80,  function(t) return t   end)
  elseif ft==FADE_OUT then plot(80,100,255, function(t) return 1-t end)
  else
    plot(80,100,255, function(t) return 1-t end)
    plot(255,80,80,  function(t) return t   end)
  end
end

local function draw_radio(x,y,w,options,selected)
  local ih=22; local rs=8; local clicked=nil
  local mx,my,mb = gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap&1
  gfx.setfont(1,"Arial",12)
  for i,opt in ipairs(options) do
    local iy=y+(i-1)*ih
    local rx,ry=x+4,iy+ih/2-rs/2
    sc(165,165,165); gfx.circle(rx+rs/2,ry+rs/2,rs/2,false,true)
    if i==selected then sc(75,145,255); gfx.circle(rx+rs/2,ry+rs/2,rs/2-2,true,true) end
    sc(210,210,210); gfx.x=rx+rs+5; gfx.y=iy+4; gfx.drawstr(opt)
    if mb==1 and mx>=x and mx<=x+w and my>=iy and my<iy+ih then clicked=i end
  end
  return clicked
end

local function draw_btn(x,y,w,h,lbl,hc,nc)
  local mx,my,mb = gfx.mouse_x,gfx.mouse_y,gfx.mouse_cap&1
  local hover = mx>=x and mx<=x+w and my>=y and my<=y+h
  local c = hover and (hc or {80,120,200}) or (nc or {58,58,58})
  sc(table.unpack(c)); gfx.rect(x,y,w,h,1)
  sc(120,120,120);     gfx.rect(x,y,w,h,0)
  sc(220,220,220); gfx.setfont(1,"Arial",13)
  local sw=gfx.measurestr(lbl)
  gfx.x=x+w/2-sw/2; gfx.y=y+h/2-7; gfx.drawstr(lbl)
  return hover and mb==1
end

-- ============================================================
-- UI (defer loop)
-- ============================================================
local function run_ui(det)
  if #det.types==0 then
    r.ShowMessageBox(
      "No fade detected.\n\nUsage:\n• Fade In:  time sel starts before item, ends inside\n• Fade Out: time sel starts inside item, ends after\n• Crossfade: select 2 overlapping items\n• Batch:    time sel covers entire item(s) span",
      "Create Fades", 0)
    return
  end

  local types      = det.types
  local show_multi = #types > 1        -- show multiple panels
  local show_len   = det.show_length   -- show ms length fields

  local PANEL_W   = 210
  local PREVIEW_H = 110
  local RADIO_H   = #SHAPE_NAMES * 22
  local PANEL_H   = 24 + PREVIEW_H + 12 + RADIO_H + 8
  local PAD       = 10
  local num       = show_multi and #types or 1
  local WIN_W     = PANEL_W*num + PAD*(num+1)
  local BATCH_ROW = show_len and 36 or 0
  local WIN_H     = PAD + PANEL_H + BATCH_ROW + PAD + 38 + PAD

  local EXT_SEC = "hsuanice_PT2Reaper_CreateFades"

  local function get_remembered_ms(key, fallback)
    local v = tonumber(r.GetExtState(EXT_SEC, key))
    return (v and v > 0) and math.floor(v) or fallback
  end

  local S = {
    fadein_shape  = det.def_fadein_shape,
    fadeout_shape = det.def_fadeout_shape,
    xfade_shape   = det.def_xfade_shape,
    fadein_ms  = get_remembered_ms("fadein_ms",  det.def_batch_ms),
    xfade_ms   = get_remembered_ms("xfade_ms",   det.def_batch_ms),
    fadeout_ms = get_remembered_ms("fadeout_ms",  det.def_batch_ms),
  }
  -- Only expose ms fields if show_length
  if not show_len then
    S.fadein_ms  = nil
    S.xfade_ms   = nil
    S.fadeout_ms = nil
  end

  -- Save ms values to ExtState
  local function save_ms()
    if S.fadein_ms  then r.SetExtState(EXT_SEC, "fadein_ms",  tostring(S.fadein_ms),  true) end
    if S.xfade_ms   then r.SetExtState(EXT_SEC, "xfade_ms",   tostring(S.xfade_ms),   true) end
    if S.fadeout_ms then r.SetExtState(EXT_SEC, "fadeout_ms", tostring(S.fadeout_ms), true) end
  end

  -- Which length field is being edited (nil=none)
  local editing_field = nil
  local editing_str   = ""
  local prev_mb = 0  -- track mouse button edge for click-outside commit

  local done=false; local ok_result=false

  gfx.init("Create Fades", WIN_W, WIN_H, 0, 300, 200)

  local function draw_panel(px,py,pt)
    local sk = pt==FADE_IN and "fadein_shape" or pt==FADE_OUT and "fadeout_shape" or "xfade_shape"
    local title = pt==FADE_IN and "Fade In" or pt==FADE_OUT and "Fade Out" or "Crossfade"

    sc(44,44,44); gfx.rect(px,py,PANEL_W,PANEL_H,1)
    sc(72,72,72); gfx.rect(px,py,PANEL_W,PANEL_H,0)

    gfx.setfont(2,"Arial",13,string.byte("b")); sc(200,200,200)
    local tw=gfx.measurestr(title)
    gfx.x=px+PANEL_W/2-tw/2; gfx.y=py+6; gfx.drawstr(title)

    draw_preview(px+6, py+24, PANEL_W-12, PREVIEW_H, S[sk], pt)

    gfx.setfont(1,"Arial",11); sc(145,145,145)
    gfx.x=px+8; gfx.y=py+24+PREVIEW_H+6; gfx.drawstr("Shape:")

    local clicked = draw_radio(px+8, py+24+PREVIEW_H+18, PANEL_W-16, SHAPE_NAMES, S[sk])
    if clicked then S[sk]=clicked end
  end

  local function frame()
    if done then return end
    local char=gfx.getchar()
    if char==-1 then done=true; ok_result=false; return end
    -- Only close on ESC/Enter if not editing a field
    if char==27 and not editing_field then done=true; ok_result=false; return end
    if char==13 and not editing_field then done=true; ok_result=true;  return end

    local cur_mb = gfx.mouse_cap & 1  -- current mouse button state (frame level)

    local function commit_field()
      if not editing_field then return end
      if editing_str ~= "" then
        local v = tonumber(editing_str)
        if v and v > 0 then S[editing_field] = math.floor(v) end
      end
      -- if empty, keep current S value unchanged
      editing_field = nil; editing_str = ""
    end

    sc(30,30,30); gfx.rect(0,0,WIN_W,WIN_H,1)

    if not show_multi then
      draw_panel(PAD, PAD, types[1])
    else
      for i,pt in ipairs(types) do
        draw_panel(PAD+(i-1)*(PANEL_W+PAD), PAD, pt)
      end
    end

    -- Length row (only when show_len=true)
    if show_len then
      local ly = PAD + PANEL_H + 6
      gfx.setfont(1,"Arial",11)

      local field_defs = {}
      for i,pt in ipairs(types) do
        local fk    = pt==FADE_IN and "fadein_ms" or pt==FADE_OUT and "fadeout_ms" or "xfade_ms"
        local label = pt==FADE_IN and "Fade In" or pt==FADE_OUT and "Fade Out" or "XFade"
        local fx    = PAD + (i-1)*(PANEL_W+PAD)
        field_defs[#field_defs+1] = {key=fk, label=label, x=fx}
      end

      local fmx,fmy,fmb = gfx.mouse_x,gfx.mouse_y,cur_mb
      local just_released = (cur_mb==0 and prev_mb==1)

      for _, fd in ipairs(field_defs) do
        sc(145,145,145)
        gfx.x=fd.x; gfx.y=ly+6; gfx.drawstr(fd.label.." (ms):")
        local bx=fd.x+86; local bw=54; local bh=20
        local is_ed = (editing_field==fd.key)
        if is_ed then sc(35,45,65) else sc(28,28,28) end
        gfx.rect(bx,ly+2,bw,bh,1)
        if is_ed then sc(80,130,220) else sc(85,85,85) end
        gfx.rect(bx,ly+2,bw,bh,0)
        sc(210,210,210)
        local disp = is_ed and (editing_str.."|") or tostring(S[fd.key])
        local dw=gfx.measurestr(disp)
        gfx.x=bx+bw/2-dw/2; gfx.y=ly+5; gfx.drawstr(disp)
        if fmb==1 and fmx>=bx and fmx<=bx+bw and fmy>=ly+2 and fmy<=ly+2+bh then
          if editing_field~=fd.key then
            commit_field()          -- commit previous field first
            editing_field=fd.key
            editing_str=""          -- clear so user types fresh (select-all behaviour)
          end
        end
      end

      -- Keyboard: digits, backspace, enter/tab to commit
      if editing_field and char>0 then
        if char>=48 and char<=57 then
          editing_str=editing_str..string.char(char)
        elseif char==8 and #editing_str>0 then
          editing_str=editing_str:sub(1,-2)
        elseif char==13 or char==9 then
          commit_field()
        elseif char==27 then
          editing_field=nil; editing_str=""; char=0
        end
      end
      -- Click outside on mouse-up: commit
      if just_released and editing_field then
        local on_any=false
        for _,fd in ipairs(field_defs) do
          if fmx>=fd.x+86 and fmx<=fd.x+140 and fmy>=ly+2 and fmy<=ly+22 then on_any=true end
        end
        if not on_any then commit_field() end
      end
    end

    local btn_y = WIN_H - PAD - 32
    if draw_btn(WIN_W-PAD-84,    btn_y, 84, 30, "OK",     {55,95,175},{50,50,50}) then
      commit_field()  -- commit any in-progress edit
      done=true; ok_result=true
    end
    if draw_btn(WIN_W-PAD-84-92, btn_y, 84, 30, "Cancel", {100,50,50},{50,50,50}) then
      done=true; ok_result=false
    end

    prev_mb = cur_mb
    gfx.update()
    if not done then r.defer(frame) end
  end

  r.defer(frame)

  r.atexit(function()
    gfx.quit()
    if ok_result then
      save_ms()
      apply(det, S)
    end
  end)
end

-- ============================================================
-- ENTRY
-- ============================================================
local det = detect()
run_ui(det)