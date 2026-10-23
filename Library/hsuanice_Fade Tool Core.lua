--[[
@description hsuanice Fade Tool Core (shared razor / cut / edge / fade helpers for the Fade Tool scripts)
@version 26.1023.2008pre1
@author hsuanice
@noindex
@changelog
  - Add: side_fade() - one-sided fade or crossfade end / start adjustment.
  - Credits: written out in full - Fade Tool is heavily based on AZ's Fade tool (ReaTeam Scripts).
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
  Mode support, one-sided crossfade adjustment and Scene Cut.
--]]
local r = reaper
local M = {}

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
    r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN", limit)
    if r.GetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO") > 0 then
      r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO", limit)
    end
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

-- side = "IN" / "OUT"; auto = true writes a crossfade (auto fade) length, false a plain fade
function M.set_fade(it, side, len, shape, auto)
  r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN", len)
  r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO", auto and len or 0)
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

  M.set_end(a.item, xe)
  M.set_start(b.item, xs)
  local len = xe - xs
  M.set_fade(a.item, "OUT", len, shape, true)
  M.set_fade(b.item, "IN", len, shape, true)
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

-- Fade-in from the item start to t. A crossfaded start keeps its start point and the
-- crossfade is stretched or shortened to end at t (shape kept).
function M.fade_in_to(info, t, S)
  if M.is_locked(info.item) then return false, "locked item" end
  if t <= info.pos + M.TOL or t >= info.fin - M.TOL then return false, "position is outside the item" end
  local left = M.xfade_neighbour(info, "left")
  if left then return M.crossfade(left, info, info.pos, t, nil) end
  M.set_fade(info.item, "IN", t - info.pos, S.fade_shape, false)
  clamp_fade(info.item, "OUT", info.fin - t)
  return true
end

-- Fade-out from t to the item end (a crossfaded end: the crossfade now starts at t)
function M.fade_out_from(info, t, S)
  if M.is_locked(info.item) then return false, "locked item" end
  if t <= info.pos + M.TOL or t >= info.fin - M.TOL then return false, "position is outside the item" end
  local right = M.xfade_neighbour(info, "right")
  if right then return M.crossfade(info, right, t, info.fin, nil) end
  M.set_fade(info.item, "OUT", info.fin - t, S.fade_shape, false)
  clamp_fade(info.item, "IN", t - info.pos)
  return true
end

-- One-sided fade at t: side "in" = fade-in to t, "out" = fade-out from t.
-- Inside a crossfade of the item, "in" moves the crossfade end to t and "out" its start.
-- Returns ok, why, partner (the other item of the crossfade, if one was changed)
function M.side_fade(info, t, side, S)
  local left = M.xfade_neighbour(info, "left")
  if left and t > info.pos + M.TOL and t < left.fin - M.TOL then
    local xs, xe = info.pos, left.fin
    if side == "in" then xe = t else xs = t end
    local ok, why = M.crossfade(left, info, xs, xe, nil)
    return ok, why, left.item
  end
  local right = M.xfade_neighbour(info, "right")
  if right and t > right.pos + M.TOL and t < info.fin - M.TOL then
    local xs, xe = right.pos, info.fin
    if side == "in" then xe = t else xs = t end
    local ok, why = M.crossfade(info, right, xs, xe, nil)
    return ok, why, right.item
  end
  if side == "in" then
    local ok, why = M.fade_in_to(info, t, S)
    return ok, why, left and left.item
  end
  local ok, why = M.fade_out_from(info, t, S)
  return ok, why, right and right.item
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
-- Razor / time selection areas
----------------------------------------
-- Per track (and fixed lane) inside each area { track, s, e, top, bot }:
-- - one cut in the area: the crossfade fills the area
-- - two or more cuts: each gets the default crossfade (frames + before / center / after)
-- - no cut: an item start / end inside the area whose other end lies outside gets a plain
--   fade over the area; otherwise the nearest cut in the arrange view is pulled in
--   (two equally near cuts are reported)
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

  for _, area in ipairs(areas) do
    touched[area.track] = true
    local rs, re = area.s, area.e
    for _, list in pairs(M.lane_items(area, math.min(rs, view_s), math.max(re, view_e))) do
      local cuts = M.find_cuts(list)
      local inside, outside, joined = {}, {}, {}
      for _, c in ipairs(cuts) do
        joined[c.a] = joined[c.a] or {}; joined[c.a].right = true
        joined[c.b] = joined[c.b] or {}; joined[c.b].left = true
        if c.je >= rs - M.TOL and c.js <= re + M.TOL then
          inside[#inside + 1] = c
        elseif c.je >= view_s and c.js <= view_e then
          outside[#outside + 1] = c
        end
      end

      local edges = 0
      if #inside == 0 then
        for _, info in ipairs(list) do
          local j = joined[info] or {}
          if not j.left and info.pos >= rs - M.TOL and info.pos < re - M.TOL and info.fin > re + M.TOL then
            edges = edges + 1
            if M.is_locked(info.item) then skip(area, info.pos, "locked item")
            else
              M.set_fade(info.item, "IN", re - info.pos, S.fade_shape, false)
              clamp_fade(info.item, "OUT", info.fin - re)
              changed = changed + 1
            end
          end
          if not j.right and info.fin <= re + M.TOL and info.fin > rs + M.TOL and info.pos < rs - M.TOL then
            edges = edges + 1
            if M.is_locked(info.item) then skip(area, info.fin, "locked item")
            else
              M.set_fade(info.item, "OUT", info.fin - rs, S.fade_shape, false)
              clamp_fade(info.item, "IN", rs - info.pos)
              changed = changed + 1
            end
          end
        end
      end

      if #inside == 1 then
        xfade(area, inside[1], rs, re)
      elseif #inside >= 2 then
        local len = S.xfade_frames * fl
        for _, c in ipairs(inside) do
          local xs, xe = M.aligned_range(c.cut, len, S.xfade_align)
          xfade(area, c, xs, xe)
        end
      elseif edges == 0 and #outside > 0 then
        local best, best_d, tie
        for _, c in ipairs(outside) do
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
