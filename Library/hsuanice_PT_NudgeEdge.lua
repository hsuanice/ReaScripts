--[[
@description hsuanice_PT_NudgeEdge — Fade-aware clip edge nudge library
@version 0.19.1 [260430.1135]
@author hsuanice
@about
  Shared library for Nudge Clip Start/End Earlier/Later scripts.
  Provides nudge_start and nudge_end with crossfade awareness.

  Fade storage (v0.11.0+):
    REAPER stores auto-crossfade fades in D_FADEINLEN_AUTO / D_FADEOUTLEN_AUTO.
    These override the manual D_FADEINLEN / D_FADEOUTLEN when non-zero.
    All reads use get_fi/get_fo (effective value = AUTO if set, else manual).
    All writes use set_fi/set_fo (writes to whichever property is currently active).

  Crossfade detection:
    Left neighbor  = item on same track whose END falls inside current item (pos < oe < item_e)
                     AND whose effective fo_len > 0
    Right neighbor = item on same track whose START is inside current item's overlap range
                     (>= fo_start when fo_len > 0, or >= pos when fo_len = 0)
                     AND extends past item_e

  Zone C (crossfade boundary) is atomic:
    Both items updated in one pass to prevent REAPER from clamping fade lengths.
    Update order: expand partner overlap first (pos/len), then set own fo/fi_len.

  Double-processing guard:
    When razor covers a crossfade boundary and both items are selected,
    Zone C fires on the first item (left for nudge_start, left for nudge_end P1).
    The second item skips only when sel_s <= lxf_fo_start + EPS AND lxf has fo_len > EPS.
    Bare overlaps (fo_len = 0) do not trigger the skip — right item's P1 handles them.

  nudge_start convention: delta > 0 = Earlier (start moves left), delta < 0 = Later
  nudge_end   convention: delta > 0 = Later  (end moves right),  delta < 0 = Earlier

@changelog
  0.19.1 [260430.1135] - nudge_start P2 atomic: add body-collapse guard for Start Earlier (delta>0).
                        Start Earlier shrinks Left's D_LENGTH (atomic step), so Left.body
                        (= len - fi - fo) eventually collapses. Block when Left.body shrinks to ≤ 1 grid.
                        (Pairs with the existing Start Later guard on current item's body.)
  0.19.0 [260430.1127] - nudge_start P2 + left xfade partner: add atomic update mirroring nudge_end P2.
                        Modify Right (current item) pos/len/STARTOFFS as before, AND atomically
                        update Left.D_LENGTH so item_e_L follows new fi_end_R (= pos_R + fi_len).
                        Left.pos / D_STARTOFFS / fo_len untouched (Left's content stays in timeline,
                        Left only grows/shrinks on right side). Source-bound clamp on Left's right
                        extension for Start Later. Body-collapse guard for current item (Right) on
                        Start Later.
                        Also: nudge_start else now also skips when right xfade partner is selected
                        (mirrors v0.18.5 left-partner skip), preventing Left from over-shifting razor
                        after Right's P2 atomic.
  0.18.6 [260430.1130] - nudge_end P2 atomic: add body-collapse guard for End Later (delta>0).
                        In xfade C-shift, Right.D_LENGTH shrinks each nudge, so Right's body
                        (= len - fi - fo) eventually collapses. Block when body would shrink to 0
                        (preserve at least 1 grid).
  0.18.5 [260430.1101] - nudge_start / nudge_end else branch: skip when xfade partner is selected.
                        Returns (sel_s, sel_e, true) so the script's update_razor isn't called and
                        min_actual isn't dragged. Fixes Test 21 where Right's nudge_end fell to
                        else after Left's atomic update and overwrote the item-track razor with
                        sel_e + delta (shrinking razor by an extra grid).
  0.18.4 [260430.1052] - nudge_end P2 with right xfade: full PT-aligned atomic C-shift.
                        Left.D_LENGTH += total (item_e shifts).
                        Right.D_POSITION += total (pos/fade-in start shifts).
                        Right.D_LENGTH -= total (end preserved).
                        Right.D_STARTOFFS += total (content stays in timeline).
                        Right.fi_len untouched — fi_end_R = pos + fi_len auto-tracks new item_e_L,
                        keeping both C-start (fo_start_L = pos_R) and C-end (item_e_L = fi_end_R) aligned.
                        Source-bound clamp on Right's STARTOFFS for End Earlier (block if no source room).
  0.18.3 [260430.1042] - nudge_end P2 with right xfade: minimal atomic — modify Left.D_LENGTH and
                        atomically shrink/grow Right.fi_len so fi_end_R follows new item_e_L
                        (keeps C-end aligned). Right.D_POSITION / D_LENGTH / D_STARTOFFS untouched
                        so Right's content stays put in timeline. Adds body-collapse guard for
                        End Later (so Right's body doesn't disappear when fi grows).
  0.18.2 [260430.1019] - nudge_end P2: revert atomic crossfade shift. Per Test 21 PT clarification,
                        Right xfade partner stays untouched (no pos/len/STARTOFFS change). Only Left.
                        D_LENGTH changes; the crossfade boundary "shifts" because Left's item_e and
                        fo_start move together. Audio content of Right is preserved in timeline.
  0.18.1 [260430.1012] - nudge_end P2 + right xfade partner atomic C-shift refinements (per Test 21 expected):
                        * Right.D_LENGTH now compensates so Right.end stays put (Right grows on left side
                          for Earlier, shrinks on left for Later). Previously Right shifted whole.
                        * Selection sel_e shifts by total (no more snap-to-fo_start). Removes the asymmetric
                          Earlier/Later return rule.
                        STARTOFFS still unchanged for now (audio shifts with Right's left edge).
  0.18.0 [260425.1216] - nudge_end P2 + right xfade partner: atomic C-shift.
                        When fo_start_L = pos_R (C-start), nudging B-end shifts the entire C-zone:
                        Left.D_LENGTH += total (item_e shifts), Right.D_POSITION += total (pos shifts).
                        Right.D_LENGTH unchanged (Right shifts whole, end follows pos).
                        Fade lengths (fo_L, fi_R) unchanged so C-end = fi_end_R also tracks item_e_L.
                        Selection: Earlier snaps sel_e to new fo_start (selection shrinks to body-only),
                        Later shifts sel_e by total (selection extends with C-zone).
                        Aligns with PT behavior reported in Test 21 ("C 整個平移").
  0.17.0 [260425.1018] - Zone-stay guard: each P2/P3 priority now blocks when the next nudge would
                        leave 0 (or less) of the relevant zone-in-selection grid. Preserves "the
                        last 1 grid" of selection inside its original zone in all 4 mirror cases:
                          * nudge_start P2 (Start Later): block when (sel_e - fi_end) <= |delta|
                          * nudge_start P3 (Start Later): block when (sel_e - fo_start) <= |delta|
                          * nudge_end   P2 (End Earlier): block when (fo_start - sel_s) <= |delta|
                          * nudge_end   P3 (End Earlier): block when (fi_end - sel_s) <= |delta|
                        Existing whole-zone collapse guards still cover their cases; this guard
                        protects the per-selection slice that those didn't see.
  0.16.0 [260425.0924] - PT-aligned fill semantics: fill+nudge now only triggers at the 6 discrete
                        fade-zone edges (I-start, I-end, C-start, C-end, O-start, O-end). When sel_s
                        (or sel_e for nudge_end) is strictly inside fade interior or body interior,
                        fill_amt is forced to 0 and only delta is applied. Selection return values
                        switched from `boundary - total` to `sel_s/sel_e - total`, so razor/TS sync
                        follows item shift correctly even when fill is skipped.
                        Affected: nudge_start P2 (fade-in interior), nudge_start P3 (body interior),
                        nudge_end P2 (fade-out interior), nudge_end P3 (body interior).
  0.15.2 [260424.2213] - nudge_end P3: move "left xfade partner selected" skip check BEFORE the
                        new_fi_len/clip_len_after guards. When partner pre-grew our fi_len, fi_end
                        equals fo_start - 1, so clip_len_after guard would fire (delta>0 case) and
                        return without the skipped marker, dragging min_actual to 0. Fixes Nudge
                        End Later C-end with both crossfade partners selected.
  0.15.1 [260424.2207] - Zone-collapse guard now returns skipped marker when selected left-xfade partner pre-shrunk the razor.
                        Fixes Start Later / End Earlier with two crossfade partners selected: second item's
                        zone-collapse guard fired before its skip guard could mark it as skipped, dragging
                        min_actual to 0 and freezing TS + pure-razor sync.
  0.15.0 [260422.1820] - nudge_start P1 + nudge_end P1/P3 skip guards return 3rd value `true` (skipped marker).
                        Callers can distinguish "skipped" (partner handled) from "blocked" (zone collapse)
                        for correct sync logic with crossfade pairs.
  0.14.0 [260422.1820] - Source-boundary clamp (two-step PT behavior):
                         nudge_start P1/P2/P3 and nudge_end P1/P2/P3 first clamp `total` to the
                         source limit (so a too-large razor still extends to the maximum possible);
                         only the next attempt — when already at the boundary — shows the warning
                         "You cannot extend the fade past the clip boundary." (once per script run).
  0.13.0 [260422.1728] - nudge_end P1: skip when right xfade partner is selected and sel_e covers its right edge (prevents double-processing)
                        - nudge_position: fix right/left sync to always set new overlap (was only shrinking, not growing)
  0.12.0 [260422.1709] - nudge_end P1: add crossfade guard for End Later — prevent right xfade partner's clip body from disappearing
  0.11.0 [260422.1655] - Use effective fades: read D_FADEINLEN_AUTO/D_FADEOUTLEN_AUTO (REAPER auto-crossfade)
                        - get_fi/get_fo: effective = AUTO when non-zero, else manual
                        - set_fi/set_fo: writes to whichever property is currently active
                        - find_left_xfade: use get_fo(other) for detection
                        - find_right_xfade: use get_fo(item); fo_len=0 → search from pos (bare overlap)
                        - All nudge_start/nudge_end fade reads/writes updated to use helpers
                        - P1 skip guard: use get_fo(lxf) + fo_len > EPS check (bare overlaps don't skip)
  0.10.0 [260422.1407] - Fix nudge_start else branch: sel_s + delta → sel_s - delta (Earlier was moving RIGHT)
                        - Fix P1 skip guard: only skip item B when sel_s <= lxf_fo_start + EPS
  0.9.0 [260422.1407] - find_right_xfade: remove fi_len_B > EPS requirement (broke Zone C when fi_len_B = 0)
                       - find_left_xfade: revert to oe < item_e; add o_fo > EPS filter
  0.8.0 [260422.1407] - Zone C atomic update: expand partner pos/len FIRST to prevent REAPER clamping fo_len
                       - nudge_start P1: skip when left xfade partner is selected
  0.7.0 [260422.1214] - P1 nudge_start: only grow fi_len if it was already > 0
  0.5.0 [260422.1214] - P3/P1 nudge_start: skip partner updates when partner is already selected
  0.2.0 [260421.1214] - Expose find_left/right_xfade + nudge_position for Move scripts
  0.1.0 [260421.1214] - Initial release
--]]

local r   = reaper
local EPS = 1e-4
local M   = {}

-- ---------------------------------------------------------------------------
-- Source-boundary helpers
--   max_extend_left  — max amount STARTOFFS can decrease (extend item to the left)
--                       before hitting source start (offs >= 0).
--   max_extend_right — max amount item LENGTH can grow (extend item to the right)
--                       before hitting source end (offs + len*playrate <= src_len).
--   Two-step PT behavior: callers clamp `total` to the max; if max is already
--   essentially zero (item already at the boundary), they call source_warning()
--   instead — so the first attempt fills to the limit, the next attempt warns.
-- ---------------------------------------------------------------------------
local function max_extend_left(take)
  if not take then return math.huge end
  local cur_offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
  return math.max(0, cur_offs)
end

local function max_extend_right(item, take, cur_len)
  if not take then return math.huge end
  local source = r.GetMediaItemTake_Source(take)
  if not source then return math.huge end
  local src_len, is_qn = r.GetMediaSourceLength(source)
  if is_qn or not src_len or src_len <= 0 then return math.huge end
  local pr = r.GetMediaItemTakeInfo_Value(take, 'D_PLAYRATE')
  if pr <= 0 then pr = 1.0 end
  local cur_offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
  return math.max(0, (src_len - cur_offs) / pr - cur_len)
end

-- Show source-boundary warning once per script invocation
local _warned = false
local function source_warning()
  if _warned then return end
  _warned = true
  r.ShowMessageBox("You cannot extend the fade past the clip boundary.", "Nudge", 0)
end

-- ---------------------------------------------------------------------------
-- Effective fade helpers
--   REAPER auto-crossfade stores lengths in _AUTO properties.
--   _AUTO is non-zero → it is the active value (overrides manual).
-- ---------------------------------------------------------------------------
local function get_fi(item)
  local auto = r.GetMediaItemInfo_Value(item, 'D_FADEINLEN_AUTO')
  if auto > EPS then return auto end
  return r.GetMediaItemInfo_Value(item, 'D_FADEINLEN')
end

local function get_fo(item)
  local auto = r.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN_AUTO')
  if auto > EPS then return auto end
  return r.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN')
end

local function set_fi(item, val)
  if r.GetMediaItemInfo_Value(item, 'D_FADEINLEN_AUTO') > EPS then
    r.SetMediaItemInfo_Value(item, 'D_FADEINLEN_AUTO', val)
  else
    r.SetMediaItemInfo_Value(item, 'D_FADEINLEN', val)
  end
end

local function set_fo(item, val)
  if r.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN_AUTO') > EPS then
    r.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN_AUTO', val)
  else
    r.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN', val)
  end
end

-- ---------------------------------------------------------------------------
-- Crossfade neighbour detection
-- ---------------------------------------------------------------------------

-- Find item on same track whose END falls inside current item AND has effective fo_len > EPS.
local function find_left_xfade(track, item)
  local pos    = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local item_e = pos + r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local best, best_end = nil, -math.huge
  for i = 0, r.CountTrackMediaItems(track) - 1 do
    local other = r.GetTrackMediaItem(track, i)
    if other ~= item then
      local op   = r.GetMediaItemInfo_Value(other, 'D_POSITION')
      local oe   = op + r.GetMediaItemInfo_Value(other, 'D_LENGTH')
      local o_fo = get_fo(other)
      if op < pos - EPS and oe > pos + EPS and oe < item_e - EPS and o_fo > EPS then
        if oe > best_end then best = other; best_end = oe end
      end
    end
  end
  return best
end

-- Find item on same track whose START falls inside current item's fade-out zone.
-- When fo_len = 0 (bare overlap), searches the full item span.
local function find_right_xfade(track, item)
  local pos    = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len    = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local fo_len = get_fo(item)
  local item_e      = pos + len
  local fo_start    = item_e - fo_len
  local search_from = fo_len > EPS and fo_start or pos
  local best, best_pos = nil, math.huge
  for i = 0, r.CountTrackMediaItems(track) - 1 do
    local other = r.GetTrackMediaItem(track, i)
    if other ~= item then
      local op = r.GetMediaItemInfo_Value(other, 'D_POSITION')
      local oe = op + r.GetMediaItemInfo_Value(other, 'D_LENGTH')
      if op >= search_from - EPS and op < item_e - EPS and oe > item_e - EPS then
        if op < best_pos then best = other; best_pos = op end
      end
    end
  end
  return best
end

-- ---------------------------------------------------------------------------
-- nudge_start: move the left edge of a clip zone
--   Priority 1 = A start (item pos)       — moves pos + fi_len + STARTOFFS
--   Priority 2 = B start (fi_end)         — moves pos + len + STARTOFFS (fi_end fixed)
--   Priority 3 = C start (fo_start)       — Zone C: grows fo_len + right xfade partner atomically
--   P1 guard: skip if left xfade partner is selected AND it has fo_len > EPS AND
--             sel_s <= lxf_fo_start + EPS (its Zone C covers this position).
-- ---------------------------------------------------------------------------
function M.nudge_start(item, sel_s, sel_e, delta)
  local track  = r.GetMediaItemTrack(item)
  local pos    = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len    = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local fi_len = get_fi(item)
  local fo_len = get_fo(item)
  local item_e   = pos + len
  local fi_end   = pos + fi_len
  local fo_start = item_e - fo_len
  local take     = r.GetActiveTake(item)

  -- Zone-collapse guard
  -- When a selected left-xfade partner already ran its atomic update, our razor was pre-shrunk;
  -- this is partner-mediated (skip), not a real collapse, so return the skipped marker.
  if delta < 0 and (sel_e - sel_s) <= math.abs(delta) + EPS then
    local lxf_chk = find_left_xfade(track, item)
    if lxf_chk and r.IsMediaItemSelected(lxf_chk) then return sel_s, sel_e, true end
    return sel_s, sel_e
  end

  -- Priority 1: A start (pos) in selection
  if sel_s <= pos + EPS and sel_e >= pos - EPS then
    -- Skip if left xfade partner is selected, has a real fade-out, and sel_s is within its Zone C.
    -- Bare-overlap partners (fo_len = 0) do not skip — right item's P1 must run.
    -- Returns (sel_s, sel_e, true) to mark "skipped" so caller can ignore for sync purposes.
    local lxf = find_left_xfade(track, item)
    if lxf and r.IsMediaItemSelected(lxf) then
      local lxf_fo = get_fo(lxf)
      if lxf_fo > EPS then
        local lxf_fo_start = r.GetMediaItemInfo_Value(lxf, 'D_POSITION')
                           + r.GetMediaItemInfo_Value(lxf, 'D_LENGTH')
                           - lxf_fo
        if sel_s <= lxf_fo_start + EPS then return sel_s, sel_e, true end
      end
    end

    local fill_amt = pos - sel_s
    if delta < 0 and (fi_len + fill_amt) <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    -- Source-bound clamp (only when extending left): first attempt clamps to limit, next attempt warns
    if total > 0 and take then
      local max_left = max_extend_left(take)
      if max_left < EPS then
        source_warning()
        return sel_s, sel_e
      end
      if total > max_left then total = max_left end
    end
    local new_pos = pos - total
    local new_len = len + total
    local xf = find_left_xfade(track, item)
    r.SetMediaItemInfo_Value(item, 'D_POSITION', new_pos)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',   new_len)
    if fi_len > EPS then set_fi(item, fi_len + total) end
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs - total)
    end
    if xf then
      local xf_fo = get_fo(xf)
      if xf_fo > EPS then set_fo(xf, xf_fo + total) end
    end
    return new_pos, sel_e

  -- Priority 2: B start (fi_end) in selection
  elseif sel_s <= fi_end + EPS and sel_e >= fi_end - EPS then
    local fill_amt     = fi_end - sel_s
    -- PT semantics: fill only applies when sel_s lands at a fade-zone discrete edge.
    -- If sel_s is strictly inside fade-in interior (between pos and fi_end), skip fill — pure nudge.
    if sel_s > pos + EPS and sel_s < fi_end - EPS then fill_amt = 0 end
    local new_clip_len = (fo_start - fi_end) + fill_amt
    if delta < 0 and new_clip_len <= math.abs(delta) + EPS then return sel_s, sel_e end
    -- Zone-stay guard: preserve at least 1 grid of body-in-selection on the sel_e side
    -- (Start Later moves fi_end right; sel_e in body could fall back into fade-in).
    if delta < 0 and (sel_e - fi_end) <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    local lxf = find_left_xfade(track, item)
    -- Body-collapse guards for atomic xfade C-shift:
    --   Start Later (delta<0): current item (Right)'s D_LENGTH shrinks → Right.body shrinks.
    --   Start Earlier (delta>0): Left.D_LENGTH shrinks (atomic) → Left.body shrinks.
    if delta < 0 and lxf then
      local body_self = len - fi_len - fo_len
      if body_self <= math.abs(delta) + EPS then return sel_s, sel_e end
    end
    if delta > 0 and lxf then
      local lxf_len_chk = r.GetMediaItemInfo_Value(lxf, 'D_LENGTH')
      local lxf_fi_chk  = get_fi(lxf)
      local lxf_fo_chk  = get_fo(lxf)
      local lxf_body    = lxf_len_chk - lxf_fi_chk - lxf_fo_chk
      if lxf_body <= math.abs(delta) + EPS then return sel_s, sel_e end
    end
    -- Source-bound clamp on current item (extending left, total>0)
    if total > 0 and take then
      local max_left = max_extend_left(take)
      if max_left < EPS then
        source_warning()
        return sel_s, sel_e
      end
      if total > max_left then total = max_left end
    end
    -- Source-bound clamp on Left xfade partner (Start Later: Left.D_LENGTH grows right, total<0)
    if total < 0 and lxf then
      local lxf_take = r.GetActiveTake(lxf)
      if lxf_take then
        local lxf_len_chk = r.GetMediaItemInfo_Value(lxf, 'D_LENGTH')
        local max_right = max_extend_right(lxf, lxf_take, lxf_len_chk)
        if max_right < EPS then
          source_warning()
          return sel_s, sel_e
        end
        if math.abs(total) > max_right then total = -max_right end
      end
    end
    local new_len = len + total
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos - total)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',   new_len)
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs - total)
    end
    -- Atomic xfade update: Left.D_LENGTH shifts so item_e_L follows fi_end_R (= new pos + fi_len).
    -- Left.pos / D_STARTOFFS / fo_len untouched.
    if lxf then
      local lxf_len = r.GetMediaItemInfo_Value(lxf, 'D_LENGTH')
      r.SetMediaItemInfo_Value(lxf, 'D_LENGTH', lxf_len - total)
    end
    return sel_s - total, sel_e

  -- Priority 3: C start (fo_start) in selection — Zone C crossfade boundary
  elseif sel_s <= fo_start + EPS and sel_e >= fo_start - EPS then
    local fill_amt       = fo_start - sel_s
    -- PT semantics: skip fill when sel_s is strictly inside body interior (between fi_end and fo_start).
    if sel_s > fi_end + EPS and sel_s < fo_start - EPS then fill_amt = 0 end
    local new_fo_len     = fo_len + fill_amt
    local clip_len_after = (fo_start - fi_end) - fill_amt
    if delta < 0 and new_fo_len    <= math.abs(delta) + EPS then return sel_s, sel_e end
    if delta > 0 and clip_len_after <= math.abs(delta) + EPS then return sel_s, sel_e end
    -- Zone-stay guard: preserve at least 1 grid of fade-out-in-selection on the sel_e side
    -- (Start Later moves fo_start right; sel_e in fade-out could fall back into body).
    if delta < 0 and (sel_e - fo_start) <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    local xf = find_right_xfade(track, item)
    if xf then
      -- Atomic update: expand overlap first (move xf pos/len), THEN set fo_len,
      -- to prevent REAPER from clamping fo_len to the pre-expansion overlap value.
      local xf_pos  = r.GetMediaItemInfo_Value(xf, 'D_POSITION')
      local xf_len  = r.GetMediaItemInfo_Value(xf, 'D_LENGTH')
      local xf_fi   = get_fi(xf)
      local xf_take = r.GetActiveTake(xf)
      -- Source-bound clamp on xf partner (only when extending left)
      if total > 0 and xf_take then
        local max_left = max_extend_left(xf_take)
        if max_left < EPS then
          source_warning()
          return sel_s, sel_e
        end
        if total > max_left then total = max_left end
      end
      r.SetMediaItemInfo_Value(xf, 'D_POSITION', xf_pos - total)
      r.SetMediaItemInfo_Value(xf, 'D_LENGTH',   xf_len + total)
      set_fo(item, fo_len + total)
      if xf_fi > EPS then set_fi(xf, xf_fi + total) end
      if xf_take then
        local offs = r.GetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS')
        r.SetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS', offs - total)
      end
    else
      set_fo(item, fo_len + total)
    end
    return sel_s - total, sel_e

  else
    -- sel_s is past all zone boundaries.
    -- If a selected xfade partner already ran its atomic update, skip — don't overwrite
    -- the razor with another (sel_s - delta) shift.
    local lxf_chk = find_left_xfade(track, item)
    if lxf_chk and r.IsMediaItemSelected(lxf_chk) then return sel_s, sel_e, true end
    local rxf_chk = find_right_xfade(track, item)
    if rxf_chk and r.IsMediaItemSelected(rxf_chk) then return sel_s, sel_e, true end
    -- Earlier: delta > 0 → sel_s - delta moves LEFT ✓   Later: delta < 0 → sel_s - delta moves RIGHT ✓
    return sel_s - delta, sel_e
  end
end

-- ---------------------------------------------------------------------------
-- nudge_end: move the right edge of a clip zone
--   Priority 1 = C end (item_e)           — moves len + fo_len; updates right xfade fi_len atomically
--   Priority 2 = B end (fo_start)         — moves len only (fo_start fixed)
--   Priority 3 = A end (fi_end)           — Zone C: grows fi_len + left xfade partner atomically
--   P3 guard: skip if left xfade partner is selected (its P1 already handled this item).
-- ---------------------------------------------------------------------------
function M.nudge_end(item, sel_s, sel_e, delta)
  local track  = r.GetMediaItemTrack(item)
  local pos    = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len    = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local fi_len = get_fi(item)
  local fo_len = get_fo(item)
  local item_e   = pos + len
  local fi_end   = pos + fi_len
  local fo_start = item_e - fo_len
  local take     = r.GetActiveTake(item)

  -- Zone-collapse guard
  -- When a selected left-xfade partner already ran its atomic update, our razor was pre-shrunk;
  -- this is partner-mediated (skip), not a real collapse, so return the skipped marker.
  if delta < 0 and (sel_e - sel_s) <= math.abs(delta) + EPS then
    local lxf_chk = find_left_xfade(track, item)
    if lxf_chk and r.IsMediaItemSelected(lxf_chk) then return sel_s, sel_e, true end
    return sel_s, sel_e
  end

  -- Priority 1: C end (item_e) in selection
  if sel_s <= item_e + EPS and sel_e >= item_e - EPS then
    -- Skip if right xfade partner is selected AND sel_e covers its right edge.
    -- Let the right item handle its own end nudge (mirrors nudge_start P1 guard).
    -- Returns (sel_s, sel_e, true) to mark "skipped" for caller's sync logic.
    local xf_skip = find_right_xfade(track, item)
    if xf_skip and r.IsMediaItemSelected(xf_skip) then
      local xf_e = r.GetMediaItemInfo_Value(xf_skip, 'D_POSITION')
                 + r.GetMediaItemInfo_Value(xf_skip, 'D_LENGTH')
      if sel_e >= xf_e - EPS then return sel_s, sel_e, true end
    end
    local fill_amt   = sel_e - item_e
    local new_fo_len = fo_len + fill_amt
    if delta < 0 and new_fo_len <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    local xf = find_right_xfade(track, item)
    -- Guard: End Later grows fi_len_B → clip body of right xfade partner shrinks.
    -- clip_body_B = len_B - fo_B - fi_B; after nudge it shrinks by total.
    if delta > 0 and xf then
      local xf_fi = get_fi(xf)
      if xf_fi > EPS then
        local xf_len = r.GetMediaItemInfo_Value(xf, 'D_LENGTH')
        local xf_fo  = get_fo(xf)
        if xf_len - xf_fo - xf_fi - total <= EPS then return sel_s, sel_e end
      end
    end
    -- Source-bound clamp (only when extending right)
    if total > 0 and take then
      local max_right = max_extend_right(item, take, len)
      if max_right < EPS then
        source_warning()
        return sel_s, sel_e
      end
      if total > max_right then total = max_right end
    end
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', len + total)
    set_fo(item, fo_len + total)
    if xf then
      local xf_fi = get_fi(xf)
      if xf_fi > EPS then set_fi(xf, xf_fi + total) end
    end
    return sel_s, item_e + total

  -- Priority 2: B end (fo_start) in selection
  elseif sel_s <= fo_start + EPS and sel_e >= fo_start - EPS then
    local fill_amt     = sel_e - fo_start
    -- PT semantics: skip fill when sel_e is strictly inside fade-out interior (between fo_start and item_e).
    if sel_e > fo_start + EPS and sel_e < item_e - EPS then fill_amt = 0 end
    local new_clip_len = (fo_start - fi_end) + fill_amt
    if delta < 0 and new_clip_len <= math.abs(delta) + EPS then return sel_s, sel_e end
    -- Zone-stay guard: preserve at least 1 grid of body-in-selection.
    -- Block when (fo_start - sel_s) <= |delta| (would leave 0 or less body inside selection).
    if delta < 0 and (fo_start - sel_s) <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    local xf = find_right_xfade(track, item)
    -- Body-collapse guard: in xfade End Later, Right.D_LENGTH shrinks (atomic step).
    -- Block when Right's body would collapse (body = len - fi - fo, must stay ≥ 1 grid).
    if delta > 0 and xf then
      local xf_len_chk = r.GetMediaItemInfo_Value(xf, 'D_LENGTH')
      local xf_fi_chk  = get_fi(xf)
      local xf_fo_chk  = get_fo(xf)
      local xf_body    = xf_len_chk - xf_fi_chk - xf_fo_chk
      if xf_body <= math.abs(delta) + EPS then return sel_s, sel_e end
    end
    -- Source-bound clamp on Left (extending right, total>0)
    if total > 0 and take then
      local max_right = max_extend_right(item, take, len)
      if max_right < EPS then
        source_warning()
        return sel_s, sel_e
      end
      if total > max_right then total = max_right end
    end
    -- Source-bound clamp on Right (extending left, total<0): need STARTOFFS room to decrease
    if total < 0 and xf then
      local xf_take = r.GetActiveTake(xf)
      if xf_take then
        local max_left = max_extend_left(xf_take)
        if max_left < EPS then
          source_warning()
          return sel_s, sel_e
        end
        if math.abs(total) > max_left then total = -max_left end
      end
    end
    -- Atomic C-shift (PT behavior):
    -- Left:  D_LENGTH += total (item_e shifts)
    -- Right: D_POSITION += total, D_LENGTH -= total (end stays), D_STARTOFFS += total (content stays in timeline)
    --        fi_len unchanged (fi_end_R = pos+fi_len auto-tracks new item_e_L → C-end aligned)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', len + total)
    if xf then
      local xf_pos = r.GetMediaItemInfo_Value(xf, 'D_POSITION')
      local xf_len = r.GetMediaItemInfo_Value(xf, 'D_LENGTH')
      r.SetMediaItemInfo_Value(xf, 'D_POSITION', xf_pos + total)
      r.SetMediaItemInfo_Value(xf, 'D_LENGTH', xf_len - total)
      local xf_take = r.GetActiveTake(xf)
      if xf_take then
        local offs = r.GetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS')
        r.SetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS', offs + total)
      end
    end
    return sel_s, sel_e + total

  -- Priority 3: A end (fi_end) in selection — Zone C crossfade boundary
  elseif sel_s <= fi_end + EPS and sel_e >= fi_end - EPS then
    -- Skip if left xfade partner is selected — its P1 already handled the crossfade boundary.
    -- Must run BEFORE collapse/clip-len guards: when partner pre-grew our fi_len, fi_end now
    -- equals fo_start - 1, so clip_len_after guard would fire and mask the skip.
    local xf = find_left_xfade(track, item)
    if xf and r.IsMediaItemSelected(xf) then return sel_s, sel_e, true end
    local fill_amt       = sel_e - fi_end
    -- PT semantics: skip fill when sel_e is strictly inside body interior (between fi_end and fo_start).
    if sel_e > fi_end + EPS and sel_e < fo_start - EPS then fill_amt = 0 end
    local new_fi_len     = fi_len + fill_amt
    local clip_len_after = (fo_start - fi_end) - fill_amt
    if delta < 0 and new_fi_len    <= math.abs(delta) + EPS then return sel_s, sel_e end
    if delta > 0 and clip_len_after <= math.abs(delta) + EPS then return sel_s, sel_e end
    -- Zone-stay guard: preserve at least 1 grid of fade-in-in-selection on the sel_s side
    -- (End Earlier moves fi_end left; sel_s in fade-in could fall forward into body).
    if delta < 0 and (fi_end - sel_s) <= math.abs(delta) + EPS then return sel_s, sel_e end
    local total = fill_amt + delta
    if xf then
      -- Atomic: expand overlap first (grow xf len), THEN set fi_len, THEN grow xf fo_len
      local xf_len = r.GetMediaItemInfo_Value(xf, 'D_LENGTH')
      local xf_fo  = get_fo(xf)
      local xf_take = r.GetActiveTake(xf)
      -- Source-bound clamp on xf partner (only when extending right)
      if total > 0 and xf_take then
        local max_right = max_extend_right(xf, xf_take, xf_len)
        if max_right < EPS then
          source_warning()
          return sel_s, sel_e
        end
        if total > max_right then total = max_right end
      end
      r.SetMediaItemInfo_Value(xf, 'D_LENGTH', xf_len + total)
      set_fi(item, fi_len + total)
      if xf_fo > EPS then set_fo(xf, xf_fo + total) end
    else
      set_fi(item, fi_len + total)
    end
    return sel_s, sel_e + total

  else
    -- sel_e is past all zone boundaries.
    -- If left xfade partner is selected, its atomic update already handled this iteration —
    -- skip (no razor/min_actual mutation) so we don't overwrite the partner's correct result.
    local lxf_chk = find_left_xfade(track, item)
    if lxf_chk and r.IsMediaItemSelected(lxf_chk) then return sel_s, sel_e, true end
    return sel_s, sel_e + delta
  end
end

-- ---------------------------------------------------------------------------
-- Exposed helpers for Move scripts
-- ---------------------------------------------------------------------------
M.find_left_xfade  = find_left_xfade
M.find_right_xfade = find_right_xfade
M.get_fi           = get_fi
M.get_fo           = get_fo
M.set_fi           = set_fi
M.set_fo           = set_fo
M.max_extend_left  = max_extend_left
M.max_extend_right = max_extend_right
M.source_warning   = source_warning

-- Simple position nudge with left+right crossfade adjustment.
function M.nudge_position(item, delta)
  local track  = r.GetMediaItemTrack(item)
  local pos    = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len    = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local item_e = pos + len
  local left_xf  = find_left_xfade(track, item)
  local right_xf = find_right_xfade(track, item)
  r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)
  if left_xf then
    local la_e   = r.GetMediaItemInfo_Value(left_xf, 'D_POSITION')
                 + r.GetMediaItemInfo_Value(left_xf, 'D_LENGTH')
    local new_ov = math.max(0, la_e - (pos + delta))
    set_fo(left_xf, new_ov)
    set_fi(item, new_ov)
  end
  if right_xf then
    local rc_pos = r.GetMediaItemInfo_Value(right_xf, 'D_POSITION')
    local new_ov = math.max(0, (item_e + delta) - rc_pos)
    set_fi(right_xf, new_ov)
    set_fo(item, new_ov)
  end
end

return M
