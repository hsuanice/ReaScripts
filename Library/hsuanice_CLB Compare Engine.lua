--[[
@description hsuanice_CLB Compare Engine.lua
@version 26.1012.1206
@author hsuanice
@noindex
@changelog
  - Released as part of the 26.1012.1206 package update.
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  v0.2.0
  Old-vs-new EDL/XML/AAF comparison engine for Conform List Browser's
  reconform/recut feature. Pure data logic — no REAPER API calls, no UI.
  Pipeline:
    M.dedup(rows, fps, is_drop)
      Collapses rows that are identical in (reel, src_tc_in/out, rec_tc_in/out)
      but live on different tracks (e.g. a stereo pair on A1/A2) into one
      canonical event, recording every track it appeared on. Multi-mic /
      multi-track duplication of the same editorial event must not be
      reported as separate changes.
    M.compare(old_events, new_events, fps)
      Matches each old event to a new event by Reel + Source TC (overlap,
      5-frame tolerance), then classifies purely by each matched pair's own
      absolute REC TC / Source TC — no ripple or base-offset assumption (see
      the function's own doc comment for why that was tried and reverted).
      Returns a flat change list.
    M.group(changes)
      Groups the flat change list by shared "recut signature" (the exact
      transformation applied — e.g. "trim 3s off head, extend 1s off tail")
      so that N events which were all recut identically collapse into one
      reviewable/applicable group instead of N separate line items. Added/
      Deleted entries are grouped by timeline contiguity instead (adjacent
      inserted/removed events are almost always one edit decision).
  Event shape (input to dedup/compare — built from CLB ROWS by the caller):
    { reel, track, src_tc_in, src_tc_out, rec_tc_in, rec_tc_out, clip_name, __row }
    __row is an opaque back-reference to the caller's original row object;
    this module never reads or writes it, only threads it through so the UI
    layer can map a change back to its source row.
  Requires:
    Library/hsuanice_EDL Parser.lua  (for tc_to_seconds / seconds_to_tc)
  Changelog:
    v0.3.1  M.group()'s add_to_group now stamps item.__group = g on every
            item as it's added, so a caller holding just one recut candidate
            (item) can find its own type/label/color without the parent
            group being threaded through separately. Added for CLB's manual
            match-correction feature (Recut Group Details' Assign/Clear).
    v0.3.0  M.group() now relabels a "Moved" group as "Shift" once it's known
            to hold more than one item (g.is_shift=true) — many clips sharing
            the exact same delta are a block displaced together (a global
            base-offset, or the downstream effect of something inserted/
            removed earlier), distinct from a single clip genuinely moved on
            its own. Purely a function of shared vs. unique delta, computed
            after grouping — no ripple/offset detection involved.
    v0.2.0  Removed the ripple-aware / running-offset classification and the
            align_shift compare-view alignment aid: both assumed Added/
            Deleted content causes a downstream cascade, which held for one
            real ripple-insert case but produced a false "Moved" for a plain
            non-rippling single-track delete — the two are indistinguishable
            from EDL data alone. M.compare() is now purely absolute-position
            based; align a genuine base-offset between versions (e.g. via a
            Stage Offset) before comparing rather than relying on detection.
    v0.1.0  Initial release: dedup, Reel+SourceTC matching, ripple-aware
            change classification, signature-based grouping.
--]]
local M = {}
M.VERSION = "0.3.1"

M.TOL_FRAMES = 5

-- ---------------------------------------------------------------------------
-- Path discovery / dependencies
-- ---------------------------------------------------------------------------

local _info    = debug.getinfo(1, "S")
local _lib_dir = _info.source:match("@?(.*[/\\])") or ""
local _edl_path = _lib_dir .. "hsuanice_EDL Parser.lua"

local ok_edl, EDL = pcall(dofile, _edl_path)
if not ok_edl then
  error("CLB Compare Engine: cannot load EDL Parser\n  Expected: " .. _edl_path
        .. "\n  Error: " .. tostring(EDL))
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function to_sec(tc, fps, is_drop)
  return EDL.tc_to_seconds(tc or "00:00:00:00", fps, is_drop)
end

local function overlaps(a_in, a_out, b_in, b_out, tol)
  return a_in <= b_out + tol and b_in <= a_out + tol
end

local function near(a, b, tol)
  return math.abs(a - b) <= tol
end

-- ---------------------------------------------------------------------------
-- Public: event construction (caller builds these from CLB rows)
-- ---------------------------------------------------------------------------

--- Build a compare-engine event from a CLB row.
--- @param row table   A ROWS entry (reel, track, src_tc_in/out, rec_tc_in/out, clip_name)
--- @param fps number
--- @param is_drop boolean
function M.event_from_row(row, fps, is_drop)
  return {
    reel      = row.reel  or "",
    track     = row.track or "",
    src_in    = to_sec(row.src_tc_in,  fps, is_drop),
    src_out   = to_sec(row.src_tc_out, fps, is_drop),
    rec_in    = to_sec(row.rec_tc_in,  fps, is_drop),
    rec_out   = to_sec(row.rec_tc_out, fps, is_drop),
    clip_name = row.clip_name or "",
    __row     = row,
  }
end

-- ---------------------------------------------------------------------------
-- Public: dedup
-- ---------------------------------------------------------------------------

--- Collapse events that are identical in (reel, src_in/out, rec_in/out) but
--- differ only in track (stereo pairs, multi-mic duplicates, etc).
--- @param events table   array of events (see M.event_from_row)
--- @param fps number      used to quantize the identity key to whole frames
--- @return table          array of canonical events, each with a `tracks`
---                         array (sorted) and a `__rows` array of every
---                         original row that collapsed into it
function M.dedup(events, fps)
  local groups, order = {}, {}
  local q = 1.0 / fps / 2  -- half-frame quantization step for the key

  for _, e in ipairs(events) do
    local key = table.concat({
      e.reel,
      math.floor(e.src_in / q + 0.5),
      math.floor(e.src_out / q + 0.5),
      math.floor(e.rec_in / q + 0.5),
      math.floor(e.rec_out / q + 0.5),
    }, "|")
    local g = groups[key]
    if not g then
      g = {
        reel = e.reel, src_in = e.src_in, src_out = e.src_out,
        rec_in = e.rec_in, rec_out = e.rec_out, clip_name = e.clip_name,
        __tracks_set = {}, __rows = {},
      }
      groups[key] = g
      order[#order + 1] = g
    end
    g.__tracks_set[e.track] = true
    g.__rows[#g.__rows + 1] = e.__row
  end

  for _, g in ipairs(order) do
    local tracks = {}
    for t in pairs(g.__tracks_set) do tracks[#tracks + 1] = t end
    table.sort(tracks)
    g.tracks = tracks
    g.__tracks_set = nil
  end

  return order
end

-- ---------------------------------------------------------------------------
-- Public: compare (pure absolute position — no ripple/offset assumptions)
-- ---------------------------------------------------------------------------

--- Compare deduped old vs new event lists.
---
--- Deliberately does NOT try to detect or compensate for ripple / a
--- constant base-offset between the two versions (e.g. different sequence
--- start timecodes) — every classification is based purely on each event's
--- own absolute REC TC. An earlier ripple-aware version existed but was
--- reverted: it correctly collapsed a real ripple-insert's downstream
--- cascade in one dataset, but produced a false "Moved" on a plain single-
--- track lift/delete (no ripple) in another — the two cases are
--- indistinguishable from the EDL data alone, and absolute position is the
--- safer, more predictable default for recut/apply purposes. If the two
--- versions have a genuine base-offset (different project start TC),
--- align them (e.g. via a Stage Offset before recutting) before comparing.
---
--- @param old_events table   output of M.dedup() for the OLD version
--- @param new_events table   output of M.dedup() for the NEW version
--- @param fps number
--- @return table   flat array of changes:
---   { type="Trimmed"|"Extended"|"Moved"|"Added"|"Deleted", old=evt|nil, new=evt|nil,
---     delta=number|nil }   -- delta only set for "Moved" (new.rec_in - old.rec_in, seconds)
--- @return boolean  true if a genuine reordering was detected between the
---                   old-order and new-order of matched pairs (rare; usually
---                   means one clip was manually reordered relative to its
---                   neighbors — informational only, does not affect results)
function M.compare(old_events, new_events, fps)
  local tol = M.TOL_FRAMES / fps

  local by_reel_new = {}
  for i, e in ipairs(new_events) do
    e.__id = i
    by_reel_new[e.reel] = by_reel_new[e.reel] or {}
    table.insert(by_reel_new[e.reel], e)
  end

  local matched_new = {}
  local pairs_list = {}
  local results = {}

  for _, old in ipairs(old_events) do
    local candidates = by_reel_new[old.reel] or {}
    local best, best_ov = nil, -1
    for _, n in ipairs(candidates) do
      if not matched_new[n.__id] and overlaps(old.src_in, old.src_out, n.src_in, n.src_out, tol) then
        local ov = math.min(old.src_out, n.src_out) - math.max(old.src_in, n.src_in)
        if ov > best_ov then best_ov = ov; best = n end
      end
    end

    if not best then
      results[#results + 1] = { type = "Deleted", old = old }
    else
      matched_new[best.__id] = true
      local new = best
      pairs_list[#pairs_list + 1] = { old = old, new = new }

      local src_same = near(old.src_in, new.src_in, tol) and near(old.src_out, new.src_out, tol)
      local rec_same = near(old.rec_in, new.rec_in, tol) and near(old.rec_out, new.rec_out, tol)

      if src_same and rec_same then
        -- Unchanged — not reported
      elseif src_same then
        results[#results + 1] = {
          type = "Moved", old = old, new = new, delta = new.rec_in - old.rec_in,
        }
      else
        local old_len = old.src_out - old.src_in
        local new_len = new.src_out - new.src_in
        local ctype
        if new_len < old_len - tol then
          ctype = "Trimmed"
        elseif new_len > old_len + tol then
          ctype = "Extended"
        else
          ctype = "Moved"
        end
        results[#results + 1] = { type = ctype, old = old, new = new }
      end
    end
  end

  for _, n in ipairs(new_events) do
    if not matched_new[n.__id] then
      results[#results + 1] = { type = "Added", new = n }
    end
  end

  -- Reorder check (informational only): matched pairs should preserve
  -- relative order between old and new.
  local by_old = {}
  for i, p in ipairs(pairs_list) do by_old[i] = p end
  table.sort(by_old, function(a, b) return a.old.rec_in < b.old.rec_in end)
  local by_new = {}
  for i, p in ipairs(pairs_list) do by_new[i] = p end
  table.sort(by_new, function(a, b) return a.new.rec_in < b.new.rec_in end)
  local reordered = false
  for i = 1, #by_old do
    if by_old[i] ~= by_new[i] then reordered = true; break end
  end

  return results, reordered
end

-- ---------------------------------------------------------------------------
-- Public: group (signature-based, with contiguity grouping for Added/Deleted)
-- ---------------------------------------------------------------------------

--- Group a flat change list into "recut classes" — changes that share the
--- exact same transformation collapse into one group so the user can act
--- on all of them at once instead of reviewing N identical line items.
--- @param changes table   output of M.compare()
--- @param fps number       used to round signature deltas to whole frames
--- @return table   array of groups:
---   { type=string, signature=string, label=string, items=table }
function M.group(changes, fps)
  local function fr(sec) return math.floor(sec * fps + 0.5) end

  local groups, order = {}, {}
  local function add_to_group(key, ctype, label, item)
    local g = groups[key]
    if not g then
      g = { type = ctype, signature = key, label = label, items = {} }
      groups[key] = g
      order[#order + 1] = g
    end
    g.items[#g.items + 1] = item
    -- Back-reference to its own group, so any caller holding just an item
    -- (e.g. CLB's Recut Group Details table, one row per item) can look up
    -- its type/label/color without threading the parent group through
    -- separately. Used by manual match-correction (CMP.assign_group_detail_
    -- match) in hsuanice_Conform List Browser.lua.
    item.__group = g
  end

  -- Added/Deleted: group by timeline contiguity (adjacent inserted/removed
  -- events are almost always one editorial decision, not N separate ones).
  local added, deleted, rest = {}, {}, {}
  for _, c in ipairs(changes) do
    if c.type == "Added" then added[#added + 1] = c
    elseif c.type == "Deleted" then deleted[#deleted + 1] = c
    else rest[#rest + 1] = c end
  end

  local function group_contiguous(list, pos_fn, ctype, label_prefix)
    table.sort(list, function(a, b) return pos_fn(a) < pos_fn(b) end)
    local run = {}
    local run_idx = 0
    local prev_end = nil
    local GAP_TOL = 2.0  -- seconds; adjacent within this gap = same insert/remove block
    for _, c in ipairs(list) do
      local evt = c.new or c.old
      if prev_end == nil or (evt.rec_in - prev_end) > GAP_TOL then
        run_idx = run_idx + 1
      end
      local key = string.format("%s#%d", ctype, run_idx)
      add_to_group(key, ctype, label_prefix .. " (block " .. run_idx .. ")", c)
      prev_end = evt.rec_out
    end
  end
  group_contiguous(added, function(c) return c.new.rec_in end, "Added", "Added")
  group_contiguous(deleted, function(c) return c.old.rec_in end, "Deleted", "Deleted")

  -- Trimmed/Extended/Moved: group by exact transformation signature.
  for _, c in ipairs(rest) do
    local key, label
    if c.type == "Moved" then
      local d = fr(c.delta or 0)
      key = string.format("Moved#%d", d)
      label = string.format("Moved %+d frame(s)", d)
    else
      local din  = fr(c.new.src_in  - c.old.src_in)
      local dout = fr(c.new.src_out - c.old.src_out)
      key = string.format("%s#%d,%d", c.type, din, dout)
      label = string.format("%s (head %+d f / tail %+d f)", c.type, din, dout)
    end
    add_to_group(key, c.type, label, c)
  end

  -- Relabel "Moved" groups once final item counts are known: many items
  -- sharing the exact same delta are a "Shift" (a whole block displaced
  -- together — a global base-offset between the two versions, or the
  -- downstream cascade from something inserted/removed earlier in the
  -- timeline); a group of one is a genuine individual "Moved" item. This
  -- distinction is purely a function of shared delta vs. unique delta — no
  -- ripple/offset detection or assumption is involved (see M.compare's doc
  -- comment) — it's just what naturally falls out of the grouping.
  for _, g in ipairs(order) do
    if g.type == "Moved" then
      local d = tonumber(g.signature:match("^Moved#(%-?%d+)$"))
      g.is_shift = #g.items > 1
      if g.is_shift then
        g.label = string.format("Shift %+d frame(s) (%d clips)", d, #g.items)
      end
    end
  end

  return order
end

return M
