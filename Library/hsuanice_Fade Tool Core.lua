--[[
@description hsuanice Fade Tool Core (shared razor / cut / edge / fade helpers for the Fade Tool scripts)
@version 26.1023.1800pre1
@author hsuanice
@noindex
@changelog
  - Initial release.
@about
  Shared code for "Fade Tool - Crossfade in Razor", "Fade Tool - Scene Cut to Razor" and
  "Fade Tool - Settings". Settings live in the ExtState section "hsuanice_FadeTool".

  Design inspired by AZ's "Fade tool (work on context of mouse, razor or time selection)"
  (ReaTeam Scripts). No code was copied.
--]]
local r = reaper
local M = {}

M.NS  = "hsuanice_FadeTool"
M.TOL = 0.0005  -- items closer than this are treated as touching (seconds)

M.ALIGNS = { "before", "center", "after" }
-- REAPER fade shape index (C_FADEINSHAPE / C_FADEOUTSHAPE) -> name
M.SHAPE_NAMES = {
  [0] = "Linear", [1] = "Equal Power", [2] = "Slight Concave",
  [3] = "Sharp Convex", [4] = "Sharp Concave", [5] = "S-Curve",
}

M.DEFAULTS = {
  xfade_frames     = 1,
  xfade_align      = "before",
  xfade_shape      = 1,
  scene_in_frames  = 1,
  scene_in_align   = "before",
  scene_out_frames = 1,
  scene_out_align  = "before",
  scene_shape      = 0,
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
  return s
end

function M.save_settings(s)
  for k in pairs(M.DEFAULTS) do
    if s[k] ~= nil then r.SetExtState(M.NS, k, tostring(s[k]), true) end
  end
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

-- side = "IN" / "OUT"; auto = true writes a crossfade (auto fade) length, false a plain fade
function M.set_fade(it, side, len, shape, auto)
  r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN", len)
  r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "LEN_AUTO", auto and len or 0)
  r.SetMediaItemInfo_Value(it, "C_FADE" .. side .. "SHAPE", shape)
  r.SetMediaItemInfo_Value(it, "D_FADE" .. side .. "DIR", 0)
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
