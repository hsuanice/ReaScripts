--[[
@description hsuanice Fade Tool Core (shared razor / cut / edge / fade helpers for the Fade Tool scripts)
@version 26.1031.1234
@author hsuanice
@noindex
@changelog
  - Fix: resizing an existing fade or crossfade (Smart Fade and the other Fade Tool scripts) no longer resets its shape and curve to Linear (tested)
@about
  Shared code for "Fade Tool - Crossfade in Razor", "Fade Tool - Scene Cut to Razor" and
  "Fade Tool - Settings". Settings live in the ExtState section "hsuanice_FadeTool".

  Credits: heavily based on AZ's "Fade tool (work on context of mouse, razor or time
  selection)" (ReaTeam Scripts) by AZ - https://forum.cockos.com/member.php?u=135221 ,
  forum thread https://forum.cockos.com/showthread.php?t=293335 . Fade Tool follows its design
  closely: the context order (razor, time selection, mouse), top half = fade-in / bottom half
  = fade-out, the item name bar moving a crossfade (including AZ's way of detecting the name
  bar), razor crossfades and razor fades. The code is a new implementation by hsuanice with
  AI (Claude Code), with hsuanice's changes: frame-based defaults, no pop-up windows, Hover
  Mode support, hold-and-drag crossfade edges and Scene Cut.
--]]
local r = reaper
local M = {}

-- Hover Library: fade line snapshot / shape restore (shape, curve, S-curve intensity)
local okHover, Hover = pcall(dofile, r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua")
if not okHover or type(Hover) ~= "table" or not Hover.restore_fade_shape then Hover = nil end

M.NS  = "hsuanice_FadeTool"
M.TOL = 0.0005  -- items closer than this are treated as touching (seconds)

M.ALIGNS = { "before", "center", "after" }
-- REAPER fade shape index (C_FADEINSHAPE / C_FADEOUTSHAPE, checked on REAPER 7.82) -> name
M.SHAPE_NAMES = {
  [0] = "Linear", [1] = "Slight Convex", [2] = "Slight Concave", [3] = "Sharp Convex",
  [4] = "Sharp Concave", [5] = "Slight S-Curve", [6] = "Sharp S-Curve", [7] = "Equal Power",
}
-- Menu order: the two shapes used most first
M.SHAPE_ORDER = { 0, 7, 1, 2, 3, 4, 5, 6 }

M.DEFAULTS = {
  xfade_frames     = 1,
  xfade_align      = "before",
  xfade_shape      = 7,
  scene_in_frames  = 1,
  scene_in_align   = "before",
  scene_out_frames = 1,
  scene_out_align  = "before",
  scene_shape      = 0,
  fade_shape       = 0,
  use_ts           = 1,
  clear_razor      = 1,
  pull_cuts        = 1,
}

----------------------------------------
-- Settings
----------------------------------------
function M.load_settings()
  local s = {}
  for k, def in pairs(M.DEFAULTS) do
    local v = r.GetExtState(M.NS, k)
    if type(def) == "number" then
      s[k] = tonumber(v) or def
    else
      s[k] = (v ~= "" and v) or def
    end
  end
  -- Releases before 26.1023 used their own shape list (1 = Equal Power, 5 = S-Curve)
  if r.GetExtState(M.NS, "shape_list") ~= "2" then
    local OLD = { [1] = 7, [5] = 5 }
    for _, k in ipairs({ "xfade_shape", "scene_shape" }) do
      if r.HasExtState(M.NS, k) then s[k] = OLD[s[k]] or s[k] end
    end
  end
  if not M.SHAPE_NAMES[s.xfade_shape] then s.xfade_shape = M.DEFAULTS.xfade_shape end
  if not M.SHAPE_NAMES[s.scene_shape] then s.scene_shape = M.DEFAULTS.scene_shape end
  if not M.SHAPE_NAMES[s.fade_shape] then s.fade_shape = M.DEFAULTS.fade_shape end
  return s
end

function M.save_settings(s)
  for k in pairs(M.DEFAULTS) do
    if s[k] ~= nil then r.SetExtState(M.NS, k, tostring(s[k]), true) end
  end
  r.SetExtState(M.NS, "shape_list", "2", true)
end

function M.valid_align(a)
  for _, v in ipairs(M.ALIGNS) do if v == a then return true end end
  return false
end

----------------------------------------
-- Frames
----------------------------------------
function M.frame_len()
  local fps = r.TimeMap_curFrameRate(0)
  if not fps or fps <= 0 then fps = 24 end
  return 1 / fps
end

-- Snap a time to the nearest timecode frame boundary
function M.snap_frame(t)
  local fps = 1 / M.frame_len()
  local off = r.GetProjectTimeOffset(0, false)
  return math.floor((t + off) * fps + 0.5) / fps - off
end

-- Fade range around a boundary time t: "before" ends at t, "after" starts at t
function M.aligned_range(t, len, align)
  if align == "after" then return t, t + len end
  if align == "center" then return t - len / 2, t + len / 2 end
  return t - len, t
end

----------------------------------------
-- Razor areas
----------------------------------------
-- Returns a list of { track, s, e, top, bot } for track-level razor areas (envelope areas skipped)
function M.get_razor_areas()
  local areas = {}
  for ti = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, ti)
    local _, ext = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
    if not ext or ext == "" then
      local _, plain = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
      -- plain form is "s e guid s e guid ..."; turn it into the comma form
      local toks, parts = {}, {}
      for t in (plain or ""):gmatch("%S+") do toks[#toks + 1] = t end
      for i = 1, #toks - 2, 3 do parts[#parts + 1] = toks[i] .. " " .. toks[i + 1] .. " " .. toks[i + 2] end
      ext = table.concat(parts, ",")
    end
    for set in ext:gmatch("[^,]+") do
      local toks = {}
      for t in set:gmatch("%S+") do toks[#toks + 1] = t end
      local s, e, guid = tonumber(toks[1]), tonumber(toks[2]), toks[3] or '""'
      if s and e and e > s and guid == '""' then
        areas[#areas + 1] = { track = tr, s = s, e = e, top = tonumber(toks[4]), bot = tonumber(toks[5]) }
      end
    end
  end
  return areas
end

function M.clear_razors(tracks)
  for tr in pairs(tracks) do
    r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", true)
  end
end

----------------------------------------
-- Items
----------------------------------------
local function item_info(it)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  return { item = it, pos = pos, len = len, fin = pos + len }
end

-- Items of the razor area's track that intersect [ws, we], grouped by lane and sorted.
-- Only items inside the area's vertical range (fixed lanes / free positioning) are used.
-- Returns { [lane] = { info, ... } }
function M.lane_items(area, ws, we)
  local tr = area.track
  local freemode = r.GetMediaTrackInfo_Value(tr, "I_FREEMODE")
  local lanes = {}
  for i = 0, r.CountTrackMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, i)
    local info = item_info(it)
    if info.pos < we + M.TOL and info.fin > ws - M.TOL then
      local inside = true
      if freemode ~= 0 and area.top and area.bot then
        local y = r.GetMediaItemInfo_Value(it, "F_FREEMODE_Y")
        local h = r.GetMediaItemInfo_Value(it, "F_FREEMODE_H")
        inside = (y < area.bot - 1e-6) and (y + h > area.top + 1e-6)
      end
      if inside then
        local lane = (freemode == 2) and r.GetMediaItemInfo_Value(it, "I_FIXEDLANE") or 0
        lanes[lane] = lanes[lane] or {}
        table.insert(lanes[lane], info)
      end
    end
  end
  for _, list in pairs(lanes) do
    table.sort(list, function(a, b) return a.pos < b.pos end)
  end
  return lanes
end

-- Adjacent (touching or overlapping) pairs of a sorted lane list.
-- Each pair: { a, b, js, je, cut } where [js, je] is the junction (js == je for a butt cut)
function M.find_cuts(list)
  local cuts = {}
  for i = 1, #list - 1 do
    local a, b = list[i], list[i + 1]
    if b.pos <= a.fin + M.TOL and b.pos > a.pos + M.TOL and b.fin > a.fin + M.TOL then
      local js, je = math.min(a.fin, b.pos), math.max(a.fin, b.pos)
      local cut = (je - js <= M.TOL) and a.fin or M.snap_frame((js + je) / 2)
      cuts[#cuts + 1] = { a = a, b = b, js = js, je = je, cut = cut }
    end
  end
  return cuts
end

-- Neighbouring items of a sorted lane list with a gap between them: { a, b, js, je, cut }
-- where [js, je] is the gap (a's end to b's start) and cut its middle on the frame grid
function M.find_gaps(list)
  local gaps = {}
  for i = 1, #list - 1 do
    local a, b = list[i], list[i + 1]
    if b.pos > a.fin + M.TOL and b.fin > a.fin then
      gaps[#gaps + 1] = { a = a, b = b, js = a.fin, je = b.pos, cut = M.snap_frame((a.fin + b.pos) / 2) }
    end
  end
  return gaps
end

function M.is_locked(it)
  return (r.GetMediaItemInfo_Value(it, "C_LOCK") & 1) == 1
end

-- Timeline limits of the active take's source: returns lo, hi (nil = unlimited)
function M.source_limits(it)
  local take = r.GetActiveTake(it)
  if not take or r.TakeIsMIDI(take) then return nil, nil end
  if r.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 1 then return nil, nil end
  local src = r.GetMediaItemTake_Source(take)
  local srclen, is_qn = r.GetMediaSourceLength(src)
  if is_qn or not srclen or srclen <= 0 then return nil, nil end
  local pos  = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate <= 0 then rate = 1 end
  return pos - offs / rate, pos + (srclen - offs) / rate
end

-- Returns true, or false + the missing handle length in seconds
function M.can_set_edges(it, new_start, new_end)
  local lo, hi = M.source_limits(it)
  if lo and new_start < lo - M.TOL then return false, lo - new_start end
  if hi and new_end > hi + M.TOL then return false, new_end - hi end
  return true
end

-- Move an item's left edge; the audio stays in place (take offsets and take envelopes follow)
function M.set_start(it, new_pos)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  local delta = new_pos - pos
  if math.abs(delta) < 1e-9 then return end
  for ti = 0, r.CountTakes(it) - 1 do
    local take = r.GetTake(it, ti)
    if take then
      local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
      r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", offs + delta * rate)
      for ei = 0, r.CountTakeEnvelopes(take) - 1 do
        local env = r.GetTakeEnvelope(take, ei)
        for pi = 0, r.CountEnvelopePointsEx(env, -1) - 1 do
          local _, t, v, shape, tension, sel = r.GetEnvelopePointEx(env, -1, pi)
          r.SetEnvelopePointEx(env, -1, pi, t - delta, v, shape, tension, sel, true)
        end
        r.Envelope_SortPointsEx(env, -1)
      end
    end
  end
  r.SetMediaItemInfo_Value(it, "D_POSITION", new_pos)
  r.SetMediaItemInfo_Value(it, "D_LENGTH", len - delta)
end

function M.set_end(it, new_end)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  r.SetMediaItemInfo_Value(it, "D_LENGTH", new_end - pos)
end

local function fade_len(it, side)
  local man  = r.GetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN")
  local auto = r.GetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO")
  return math.max(man, auto)
end

-- Keep a fade on the other side of the item from running past `limit` seconds
local function clamp_fade(it, side, limit)
  if fade_len(it, side) > limit then
    limit = math.max(0, limit)
    local line = (limit > 0) and Hover and Hover.fade_line(it, "FADE" .. side)
    r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN", limit)
    if r.GetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO") > 0 then
      r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO", limit)
    end
    if line then Hover.restore_fade_shape(it, "FADE" .. side, line) end
  end
end

-- Fade shape. Setting D_FADEINDIR / D_FADEOUTDIR after the shape resets the shape to the
-- default (-1, Linear) on REAPER 7.82, so only the shape is written: REAPER sets the matching
-- curvature itself. Slight S-Curve goes through the native action, which also writes the
-- S-curve intensity that a plain C_FADE*SHAPE = 5 leaves out.
local S_CURVE_ACTION = { IN = 41519, OUT = 41526 }

-- shape nil = keep the item's current shape (moving or resizing an existing fade)
function M.set_shape(it, side, shape)
  if not shape then return end
  if shape == 5 then
    local sel = {}
    for i = 0, r.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = r.GetSelectedMediaItem(0, i) end
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(it, true)
    r.Main_OnCommand(S_CURVE_ACTION[side], 0)
    r.SelectAllMediaItems(0, false)
    for _, s in ipairs(sel) do r.SetMediaItemSelected(s, true) end
  else
    r.SetMediaItemInfo_Value(it, "C_FADE" .. side .. "SHAPE", shape)
  end
end

-- Shape for a fade that is about to be written: an existing fade (length > 0) keeps its own
-- shape (nil = do not write it); only a new fade gets the default shape
function M.new_fade_shape(it, side, default)
  if fade_len(it, side) > 0 then return nil end
  return default
end

-- side = "IN" / "OUT"; auto = true writes a crossfade (auto fade) length, false a plain fade.
-- shape nil keeps the current shape: writing the length can reset it to Linear, so the
-- item's fade line is read first and its shape / curve put back afterwards.
function M.set_fade(it, side, len, shape, auto)
  local line = (not shape) and len > 0 and Hover and Hover.fade_line(it, "FADE" .. side)
  r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN", len)
  r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO", auto and len or 0)
  if line then Hover.restore_fade_shape(it, "FADE" .. side, line) end
  M.set_shape(it, side, shape)
end

-- Crossfade a (left) and b (right) over [xs, xe]. Returns true, or false + reason.
function M.crossfade(a, b, xs, xe, shape)
  if M.is_locked(a.item) or M.is_locked(b.item) then return false, "locked item" end
  if a.pos >= xs - M.TOL then return false, "crossfade would start before the left item" end
  if b.fin <= xe + M.TOL then return false, "crossfade would end after the right item" end
  local ok, miss = M.can_set_edges(a.item, a.pos, xe)
  if not ok then return false, string.format("left item needs %.3f s more handle", miss) end
  ok, miss = M.can_set_edges(b.item, xs, b.fin)
  if not ok then return false, string.format("right item needs %.3f s more handle", miss) end

  -- existing fade / crossfade sides keep their shape (read before anything changes)
  local shape_a, shape_b
  if shape then
    shape_a = M.new_fade_shape(a.item, "OUT", shape)
    shape_b = M.new_fade_shape(b.item, "IN", shape)
  end
  M.set_end(a.item, xe)
  M.set_start(b.item, xs)
  local len = xe - xs
  M.set_fade(a.item, "OUT", len, shape_a, true)
  M.set_fade(b.item, "IN", len, shape_b, true)
  clamp_fade(a.item, "IN", xs - a.pos)
  clamp_fade(b.item, "OUT", b.fin - xe)
  return true
end

----------------------------------------
-- Plain fades, crossfade neighbours, moving a crossfade
----------------------------------------
function M.info(it) return item_info(it) end

-- Same-lane item that overlaps (crossfades) the start ("left") or the end ("right") of info
function M.xfade_neighbour(info, side)
  local tr = r.GetMediaItem_Track(info.item)
  local lane
  if r.GetMediaTrackInfo_Value(tr, "I_FREEMODE") == 2 then
    lane = r.GetMediaItemInfo_Value(info.item, "I_FIXEDLANE")
  end
  local best
  for i = 0, r.CountTrackMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, i)
    if it ~= info.item and (not lane or r.GetMediaItemInfo_Value(it, "I_FIXEDLANE") == lane) then
      local o = item_info(it)
      if side == "left" then
        if o.pos < info.pos - M.TOL and o.fin > info.pos + M.TOL and o.fin < info.fin then
          if not best or o.fin > best.fin then best = o end
        end
      else
        if o.fin > info.fin + M.TOL and o.pos < info.fin - M.TOL and o.pos > info.pos then
          if not best or o.pos < best.pos then best = o end
        end
      end
    end
  end
  return best
end

-- Plain fade-in from the item start to t / fade-out from t to the item end
function M.fade_in_to(info, t, S)
  if M.is_locked(info.item) then return false, "locked item" end
  if t <= info.pos + M.TOL or t >= info.fin - M.TOL then return false, "position is outside the item" end
  M.set_fade(info.item, "IN", t - info.pos, M.new_fade_shape(info.item, "IN", S.fade_shape), false)
  clamp_fade(info.item, "OUT", info.fin - t)
  return true
end

function M.fade_out_from(info, t, S)
  if M.is_locked(info.item) then return false, "locked item" end
  if t <= info.pos + M.TOL or t >= info.fin - M.TOL then return false, "position is outside the item" end
  M.set_fade(info.item, "OUT", info.fin - t, M.new_fade_shape(info.item, "OUT", S.fade_shape), false)
  clamp_fade(info.item, "IN", t - info.pos)
  return true
end

-- One-sided fade at t: side "in" = fade-in to t, "out" = fade-out from t.
-- Crossfades are left alone (razor, the name bar or hold-and-drag adjust them): nothing
-- happens when t is inside a crossfade or the faded edge is crossfaded. Returns ok, why.
function M.side_fade(info, t, side, S)
  local left = M.xfade_neighbour(info, "left")
  local right = M.xfade_neighbour(info, "right")
  if (left and t < left.fin + M.TOL) or (right and t > right.pos - M.TOL) then return true end
  if side == "in" then
    if left then return true end
    return M.fade_in_to(info, t, S)
  end
  if right then return true end
  return M.fade_out_from(info, t, S)
end

-- Move an existing crossfade (a over b) so it is centered on t; length and shape are kept
function M.move_crossfade(a, b, t)
  local len = a.fin - b.pos
  if len <= M.TOL then return false, "no crossfade there" end
  return M.crossfade(a, b, t - len / 2, t + len / 2, nil)
end

-- Item under the mouse and the part of it: "label" (name bar), "top" or "bottom" half.
-- Name bar detection taken from AZ's Fade tool (GetTopBottomItemHalf): step down from the
-- mouse by the item height and check whether the same item is still under that point.
function M.mouse_item_part()
  local x, y = r.GetMousePosition()
  local it = r.GetItemFromPoint(x, y, true)
  if not it then return nil end
  local h = r.GetMediaItemInfo_Value(it, "I_LASTH")
  local down = r.GetOS():match("^Win") and 1 or -1
  if r.GetItemFromPoint(x, math.floor(y + (h - 1) * down), true) == it then return it, "label" end
  if r.GetItemFromPoint(x, math.floor(y + h / 2 * down), true) ~= it then return it, "bottom" end
  return it, "top"
end

----------------------------------------
-- Visible area: the editing tools never change anything outside the arrange view
----------------------------------------
function M.view()
  return r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
end

function M.in_view(t1, t2)
  local vs, ve = M.view()
  return (t2 or t1) >= vs and t1 <= ve
end

local arrange_h
local function arrange_height()
  if arrange_h == nil then
    arrange_h = false
    if r.JS_Window_FindChildByID then
      local hwnd = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
      if hwnd then
        local ok, _, h = r.JS_Window_GetClientSize(hwnd)
        if ok then arrange_h = h end
      end
    end
  end
  return arrange_h
end

-- Track shown in the arrange view right now (vertical scroll; needs js_ReaScriptAPI,
-- otherwise every track shown in the TCP counts)
function M.track_visible(tr)
  if not r.IsTrackVisible(tr, false) then return false end
  local h = arrange_height()
  if not h then return true end
  local y = r.GetMediaTrackInfo_Value(tr, "I_TCPY")
  return y + r.GetMediaTrackInfo_Value(tr, "I_TCPH") > 0 and y < h
end

----------------------------------------
-- Razor / time selection areas
----------------------------------------
-- What one lane of one area would do (nothing is changed here):
-- - direct: cuts in the area, and gaps whose both edges the area covers
-- - within: gaps the area lies inside without touching either item (a pull-in)
-- - edges: { info, side } item starts / ends in the area with the other end outside
--   (only when there is no direct cut)
-- - host: the item the area lies inside (no cut or edge), host_joined when it has a neighbour
-- - outside: visible cuts outside the area (candidates for the nearest-cut pull-in)
local function plan_lane(list, rs, re, view_s, view_e)
  local p = { list = list, direct = {}, within = {}, outside = {}, edges = {} }
  local joined = {}
  for _, c in ipairs(M.find_cuts(list)) do
    joined[c.a] = joined[c.a] or {}; joined[c.a].right = true
    joined[c.b] = joined[c.b] or {}; joined[c.b].left = true
    if c.je >= rs - M.TOL and c.js <= re + M.TOL then
      p.direct[#p.direct + 1] = c
    elseif c.je >= view_s and c.js <= view_e then
      p.outside[#p.outside + 1] = c
    end
  end
  -- a gap counts as a cut when the area covers both of its edges, or lies inside it
  -- without touching either item: both items are extended into the crossfade.
  -- An area over just one edge keeps the plain fade.
  for _, g in ipairs(M.find_gaps(list)) do
    local covers = g.js >= rs - M.TOL and g.je <= re + M.TOL
    local within = rs >= g.js - M.TOL and re <= g.je + M.TOL
    if covers or within then
      joined[g.a] = joined[g.a] or {}; joined[g.a].right = true
      joined[g.b] = joined[g.b] or {}; joined[g.b].left = true
      local t = covers and p.direct or p.within
      t[#t + 1] = g
    end
  end
  if #p.direct == 0 and #p.within == 0 then
    for _, info in ipairs(list) do
      local j = joined[info] or {}
      if not j.left and info.pos >= rs - M.TOL and info.pos < re - M.TOL and info.fin > re + M.TOL then
        p.edges[#p.edges + 1] = { info = info, side = "IN" }
      end
      if not j.right and info.fin <= re + M.TOL and info.fin > rs + M.TOL and info.pos < rs - M.TOL then
        p.edges[#p.edges + 1] = { info = info, side = "OUT" }
      end
    end
    if #p.edges == 0 then
      for _, info in ipairs(list) do
        if info.pos < rs - M.TOL and info.fin > re + M.TOL then
          local j = joined[info]
          p.host, p.host_joined = info, (j and (j.left or j.right)) and true or false
          break
        end
      end
    end
  end
  return p
end

-- Plans of every visible lane of an area: rs, re (the area inside the view), { plan, ... }
local function plan_area(area, view_s, view_e)
  local rs, re = math.max(area.s, view_s), math.min(area.e, view_e)
  local plans = {}
  if re - rs > M.TOL and M.track_visible(area.track) then
    for _, list in pairs(M.lane_items(area, view_s, view_e)) do
      plans[#plans + 1] = plan_lane(list, rs, re, view_s, view_e)
    end
  end
  return rs, re, plans
end

-- Per track (and fixed lane) inside each area { track, s, e, top, bot }:
-- - a gap between two items counts as a cut when the area covers both gap edges or lies
--   inside the gap (both items are extended into the crossfade)
-- - one cut in the area: the crossfade fills the area
-- - two or more cuts: each gets the default crossfade (frames + before / center / after)
-- - no cut: an item start / end inside the area whose other end lies outside gets a plain
--   fade over the area; an area inside an item without neighbours fades in / out to it;
--   otherwise the nearest cut in the arrange view is pulled in (two equally near cuts are
--   reported)
-- Pull-ins (an area inside a gap, the nearest cut pulled in) happen only when no lane of any
-- area has a cut, edge or neighbourless item of its own, and Settings allow them (pull_cuts):
-- a razor over several tracks then only works where it touches items.
-- Only the part of each area inside the arrange view is used, and only visible tracks.
-- Returns changed count, skipped lines, touched tracks
function M.fade_areas(areas, S)
  local fl = M.frame_len()
  local view_s, view_e = r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
  local skipped, touched, changed = {}, {}, 0

  local function skip(area, t, why)
    skipped[#skipped + 1] = string.format("%s @ %s: %s", M.track_name(area.track), M.fmt_time(t), why)
  end
  local function xfade(area, c, xs, xe)
    local ok, why = M.crossfade(c.a, c.b, xs, xe, S.xfade_shape)
    if ok then changed = changed + 1 else skip(area, xs, why) end
  end

  -- dry pass: does any lane have work of its own?
  local pull = S.pull_cuts ~= 0
  for _, area in ipairs(areas) do
    if not pull then break end
    local _, _, plans = plan_area(area, view_s, view_e)
    for _, p in ipairs(plans) do
      if #p.direct > 0 or #p.edges > 0 or (p.host and not p.host_joined) then pull = false; break end
    end
  end

  -- each area is planned again here: an earlier area may have changed items of this track
  for _, area in ipairs(areas) do
    touched[area.track] = true
    local rs, re, plans = plan_area(area, view_s, view_e)
    for _, p in ipairs(plans) do
      local inside = p.direct
      if pull then for _, g in ipairs(p.within) do inside[#inside + 1] = g end end

      for _, e in ipairs(p.edges) do
        local info = e.info
        if e.side == "IN" then
          if M.is_locked(info.item) then skip(area, info.pos, "locked item")
          else
            M.set_fade(info.item, "IN", re - info.pos, M.new_fade_shape(info.item, "IN", S.fade_shape), false)
            clamp_fade(info.item, "OUT", info.fin - re)
            changed = changed + 1
          end
        else
          if M.is_locked(info.item) then skip(area, info.fin, "locked item")
          else
            M.set_fade(info.item, "OUT", info.fin - rs, M.new_fade_shape(info.item, "OUT", S.fade_shape), false)
            clamp_fade(info.item, "IN", rs - info.pos)
            changed = changed + 1
          end
        end
      end

      -- Area inside one item that has no neighbour on either side (nothing to crossfade with):
      -- fade in from the item start to the area start, fade out from the area end (as AZ's tool)
      local host = not p.host_joined and p.host or nil
      if host then
        local ok, why = M.fade_in_to(host, rs, S)
        if ok then changed = changed + 1 else skip(area, rs, why) end
        ok, why = M.fade_out_from(M.info(host.item), re, S)
        if ok then changed = changed + 1 else skip(area, re, why) end
      elseif #inside == 1 then
        xfade(area, inside[1], rs, re)
      elseif #inside >= 2 then
        local len = S.xfade_frames * fl
        for _, c in ipairs(inside) do
          local xs, xe = M.aligned_range(c.cut, len, S.xfade_align)
          xfade(area, c, xs, xe)
        end
      elseif pull and #p.edges == 0 and #p.outside > 0 then
        local best, best_d, tie
        for _, c in ipairs(p.outside) do
          local d = (c.js > re) and (c.js - re) or (rs - c.je)
          if not best or d < best_d - M.TOL then
            best, best_d, tie = c, d, false
          elseif math.abs(d - best_d) <= M.TOL then
            tie = true
          end
        end
        if tie then
          skip(area, rs, "two cuts are equally near; put the area over the one you want")
        else
          xfade(area, best, rs, re)
        end
      end
    end
  end
  return changed, skipped, touched
end

-- Time selection on the selected tracks, as areas for fade_areas (nil when there is none)
function M.time_selection_areas()
  local ts, te = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if te - ts <= M.TOL or r.CountSelectedTracks(0) == 0 then return nil end
  local areas = {}
  for i = 0, r.CountSelectedTracks(0) - 1 do
    areas[#areas + 1] = { track = r.GetSelectedTrack(0, i), s = ts, e = te }
  end
  return areas
end

----------------------------------------
-- Reporting
----------------------------------------
function M.fmt_time(t)
  return r.format_timestr_pos(t, "", 5)  -- timecode
end

function M.track_name(tr)
  local _, name = r.GetTrackName(tr)
  return name
end

-- Show skipped spots only when something was skipped (no window on success)
function M.report(title, lines)
  if #lines == 0 then return end
  local max = 20
  local out = {}
  for i = 1, math.min(#lines, max) do out[#out + 1] = lines[i] end
  if #lines > max then out[#out + 1] = string.format("... and %d more", #lines - max) end
  r.MB("These spots were skipped (that edge was not changed):\n\n" .. table.concat(out, "\n"), title, 0)
end

return M
