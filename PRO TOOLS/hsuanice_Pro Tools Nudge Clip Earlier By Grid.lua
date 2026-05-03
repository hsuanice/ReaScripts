-- @description hsuanice_Pro Tools Nudge Clip Earlier By Grid
-- @version 0.9.12 [260503.1934]
-- @author hsuanice
-- @link https://forum.cockos.com/showthread.php?p=2910884#post2910884
-- @about
--   Replicates Pro Tools: **Nudge Clip Earlier By Grid**
--
--   Selection-aware nudge using Razor area as selection.
--   Each selected item is judged independently based on
--   how the razor area overlaps its fade/clip zones.
--
--   Rules (move later, earlier is reversed):
--   fade_in+clip+fade_out covered -> item position move
--   clip only covered             -> contents +delta, fade_in +delta, fade_out -delta
--   clip+fade_out covered         -> contents +delta, fade_in +delta, right end moves
--   fade_in+clip covered          -> left end moves, fade_out -delta
--   fade_out only covered         -> right end moves, clip gets longer
--   fade_in only covered          -> left end moves, clip gets longer
--   nothing covered               -> selection only moves (no item change)
--
--   Tags: Editing
-- @changelog
--   0.9.12 [260503.1934] - Fix: TimeMap_curFrameRate return order — fps was being read as the
--                          isdrop boolean, causing get_delta() at unit==18 to default to 24
--                          (silent) on non-drop projects and crash ("compare number with boolean")
--                          on drop-frame projects.
--   0.9.11 [260422.1820] - Case 3 with left_xf: add Zone C atomic update (la extends/shrinks with item_e_A = fi_end_B).
--                          Symmetric to Case 4 with right_xf (v0.9.9). Crossfade stays consistent.
--                          Source-bound clamp added for la_take right bound on Later.
--   0.9.10 [260422.1820] - Case 4: remove STARTOFFS adjustment to fix double-shifted content (was 2*delta, now 1*delta).
--                          pos += delta alone shifts content by delta naturally.
--   0.9.9 [260422.1820] - Case 4 with right_xf: add Zone C atomic update (pos_B and crossfade shift with Bl-end).
--                          Previously kept crossfade fixed; now matches PT semantic where I+Bl shifts as a unit
--                          and the Bl-end (= pos_B) follows. Crossfade shrinks for Later, grows for Earlier.
--                          Source-bound clamp added for xf_take left bound on Earlier.
--   0.9.8 [260422.1820] - Two-pass processing: dry-run all items first to detect would-be blocks.
--                          If any item would block, abort all modifications (prevents partial-modification
--                          where one item blocks but another's sync_left/right modifies the blocked item).
--                          Case 7 Later: guard now always checks body (not fi) since fi is restored by sync.
--   0.9.7 [260422.1820] - Pre-capture fade snapshot (fi_len/fo_len) for case detection.
--                          sync_right/sync_left modifying another item's fades no longer breaks
--                          subsequent items' case detection (fixes C-zone Move Later getting stuck).
--                          Case 6 Earlier guard: use body (not fo) since fo is restored by sync_left.
--   0.9.6 [260422.1820] - nudge_item returns false on no-case-match (razor partially covers item but no zone fully).
--                          Main loop: any item blocked overrides track_nudged → razor/TS freeze for that track.
--                          Prevents razor drift when razor doesn't perfectly cover any zone.
--   0.9.5 [260422.1820] - Case 7 Later: split guard by left_xf (fi shrinks if xf, body shrinks otherwise).
--                          Case 3 Later with right_xf: guard body and right item's body (xf grows).
--   0.9.4 [260422.1820] - Case 4 Later guard fix: protect fo (the actually shrinking zone), not buffer.
--                          No right_xf: fo >= 2*delta. With right_xf: body >= 2*delta.
--   0.9.3 [260422.1820] - Zone-preservation guards extended:
--                          Case 3 Earlier: fi >= 2*|delta| (and fo >= 2*|delta| with right_xf).
--                          Case 6 Earlier: body (no xf) or fo (with xf) >= 2*|delta|.
--                          Case 6 Later: right_xf body >= 2*delta (1-grid pattern).
--   0.9.2 [260422.1820] - Zone-preservation guard refined: adjacent zone (in direction of movement)
--                          must stay >= 1 nudge grid after shift. Case 7 Later: body >= 2*delta.
--                          Case 4 Later: (fo+body) >= 2*delta (no xf) or body >= 2*delta (with xf).
--   0.9.1 [260422.1820] - Zone-collapse guard for Case 4/7 Later: prevent fi from extending past item_e
--                          (delta > len - fi_len → block); razor freezes via track_nudged sync.
--   0.9.0 [260422.1820] - Source-bound clamp for Move (two-step PT behavior):
--                        Cases 2/3/4/6/7 first clamp delta to source limit; razor follows actual movement
--                        via min |actual_delta|; next attempt at the boundary shows the warning.
--   0.8.5 [260422.1820] - All razors sync: any blocked track freezes all razors and time selection (not per-track)
--   0.8.4 [260422.1820] - nudge_item returns false on guard block; main loop freezes razor+time-sel when all tracks blocked
--   0.8.3 [260422.1820] - Case 2: unify Earlier fi_len guard — stops when fi_len exhausted (Zone A consumed) for all xf cases
--   0.8.2 [260422.1820] - Case 2: remove STARTOFFS change — zone boundary move must not shift audio content
--   0.8.1 [260422.1820] - Case 2: Zone D stop guard — broaden fo_len guard to cover left_xf-only (no right_xf) Later
--   0.8.0 [260422.1820] - Case 2: Zone D atomic update (item_e_A shifts with fi_end_B — left crossfade consistent)
--                       - Case 2: expanded stop guards covering both Zone B (right_xf) and Zone D (left_xf)
--   0.7.0 [260422.1728] - Case 2: Zone C atomic update (pos_B shifts with fo_start — crossfade consistent)
--                       - Case 2: stop guards — C eating A (Earlier) and crossfade vanishing (Later)
--                       - Case 4: don't change fo_len when right crossfade exists (right edge fixed)
--                       - Case 6: stop guard — Later can't let C eat right item's clip body
--   0.6.0 [260422.1728] - fi_covered/fo_covered require fade > 0; sync always-set; Case 2&4 sync fo
--   0.5.0 [260422.1709] - Use effective fades (AUTO overrides manual) for coverage and sync
--   0.4.0 [260421.1214] - Crossfade-aware nudge via NudgeEdge module
--   0.3.0 [260419.1806] - Rewrite: full PT selection-aware nudge logic
--   0.2.0 [260418.1931] - ApplyNudge via PT_Nudge library

local r = reaper
local info = debug.getinfo(1, "S")
local dir = info.source:match("^@(.*[/\\])") or ""
local ok, Nudge = pcall(dofile, dir .. "hsuanice_PT_Nudge.lua")
if not ok then
  r.ShowMessageBox("Could not load hsuanice_PT_Nudge.lua", "Error", 0)
  return
end
local _, Sync      = pcall(dofile, dir .. "../Library/hsuanice_PT_SelectionSync.lua")
local _, NudgeEdge = pcall(dofile, dir .. "../Library/hsuanice_PT_NudgeEdge.lua")

local EPS = 1e-4

-- Get nudge delta in seconds
local function get_delta()
  local mode, idx = Nudge.get_state()
  local preset = Nudge.get_preset(mode, idx)
  if not preset then return 0 end
  local unit  = preset.unit
  local value = preset.value
  if unit == 0  then return value / 1000.0 end
  if unit == 1  then return value end
  if unit == 17 then
    local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    return value / sr
  end
  if unit == 18 then
    local fps = r.TimeMap_curFrameRate(0)  -- returns (fps, isdrop) — fps FIRST
    fps = (fps and fps > 0) and fps or 24
    return value / fps
  end
  if unit == 16 then
    local pos = r.GetCursorPosition()
    local bpm, _ = r.GetProjectTimeSignature2(0)
    local _, bps = r.TimeMap_GetTimeSigAtTime(0, pos)
    return math.floor(value) * (60.0/bpm) * bps
  end
  if unit >= 3 and unit <= 15 then
    local bpm, _ = r.GetProjectTimeSignature2(0)
    local beat_sec = 60.0 / bpm
    local note_map = {[3]=1/64,[4]=1/32,[5]=1/16,[6]=1/8,[7]=1/4,
      [8]=1/2,[9]=1,[10]=2,[11]=4,[12]=8,[13]=16,[14]=32,[15]=64}
    return beat_sec * (note_map[unit] or 1) * value
  end
  return 0
end

-- Get razor range for a track (guid="" track-level only)
local function get_track_razor(track)
  local _, s = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
  if not s or s == "" then return nil end
  local rs, re = s:match('(%S+)%s+(%S+)%s+""')
  if rs and re then return tonumber(rs), tonumber(re) end
  return nil
end

-- Nudge one item based on razor selection overlap
-- init_state (optional): {fi_len, fo_len} snapshot taken before main loop, used so that
-- case detection sees pre-modification fades (sync_right/sync_left from earlier items
-- can change this item's fade lengths and break detection otherwise).
-- dry_run (optional): when true, run case detection + guards + source clamp but do NOT apply
-- modifications. Returns (true, clamped_delta) if would succeed, (false) if would block.
-- Used by main loop to pre-check all items before applying any (prevents partial modification).
local function nudge_item(item, sel_s, sel_e, delta, init_state, dry_run)
  local track   = r.GetMediaItemTrack(item)
  local pos     = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len     = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  -- Use snapshot fades if provided (consistent case detection across cross-item sync).
  -- Falls back to live values when called without snapshot.
  local fi_len  = (init_state and init_state.fi_len)
                  or (NudgeEdge and NudgeEdge.get_fi(item))
                  or r.GetMediaItemInfo_Value(item, "D_FADEINLEN")
  local fo_len  = (init_state and init_state.fo_len)
                  or (NudgeEdge and NudgeEdge.get_fo(item))
                  or r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  local item_e  = pos + len
  local fi_end  = pos + fi_len
  local fo_start = item_e - fo_len

  local fi_covered   = fi_len > EPS and (sel_s <= pos      + EPS and sel_e >= fi_end    - EPS)
  local fo_covered   = fo_len > EPS and (sel_s <= fo_start + EPS and sel_e >= item_e   - EPS)
  local clip_covered = sel_s <= fi_end   + EPS and sel_e >= fo_start - EPS

  if sel_e <= pos + EPS or sel_s >= item_e - EPS then return end

  local take = r.GetActiveTake(item)

  -- Find crossfade neighbors before any modifications
  local left_xf  = NudgeEdge and NudgeEdge.find_left_xfade(track, item) or nil
  local right_xf = NudgeEdge and NudgeEdge.find_right_xfade(track, item) or nil

  -- Adjust left xfade partner after this item's left edge moves to pos+delta
  local function sync_left()
    if not left_xf then return end
    local la_e   = r.GetMediaItemInfo_Value(left_xf, 'D_POSITION')
                 + r.GetMediaItemInfo_Value(left_xf, 'D_LENGTH')
    local new_ov = math.max(0, la_e - (pos + delta))
    if NudgeEdge then
      NudgeEdge.set_fo(left_xf, new_ov)
      NudgeEdge.set_fi(item, new_ov)
    else
      r.SetMediaItemInfo_Value(left_xf, 'D_FADEOUTLEN', new_ov)
      r.SetMediaItemInfo_Value(item, 'D_FADEINLEN', new_ov)
    end
  end

  -- Adjust right xfade partner after this item's right edge moves to item_e+delta
  local function sync_right()
    if not right_xf then return end
    local rc_pos = r.GetMediaItemInfo_Value(right_xf, 'D_POSITION')
    local new_ov = math.max(0, (item_e + delta) - rc_pos)
    if NudgeEdge then
      NudgeEdge.set_fi(right_xf, new_ov)
      NudgeEdge.set_fo(item, new_ov)
    else
      r.SetMediaItemInfo_Value(right_xf, 'D_FADEINLEN', new_ov)
      r.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN', new_ov)
    end
  end

  local function set_fi_item(v) if NudgeEdge then NudgeEdge.set_fi(item, v) else r.SetMediaItemInfo_Value(item, 'D_FADEINLEN',  v) end end
  local function set_fo_item(v) if NudgeEdge then NudgeEdge.set_fo(item, v) else r.SetMediaItemInfo_Value(item, 'D_FADEOUTLEN', v) end end

  if fi_covered and clip_covered and fo_covered then
    -- Case 1: entire item -> position move (both ends shift by delta)
    if dry_run then return true, delta end
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)
    sync_left(); sync_right()

  elseif clip_covered and not fi_covered and not fo_covered then
    -- Case 2: Zone B or Zone D shift — fi_end and fo_start both move by delta
    -- Zone C right atomic (Zone B): pos_B shifts with fo_start_A
    -- Zone C left atomic (Zone D): item_e_A shifts with fi_end_B
    -- Stop guards
    if delta > 0 and fo_len - delta < EPS then return false end               -- fo_len would be exhausted (Later)
    if delta < 0 and fi_len + delta < EPS then return false end               -- fi_len would be exhausted (Earlier) — Zone A consumed
    if not right_xf and not left_xf and delta < 0 and (fo_start - fi_end) + delta < EPS then return false end
    -- Source-bound clamp: right_xf Earlier shrinks xf STARTOFFS
    if right_xf and delta < 0 and NudgeEdge then
      local xf_take = r.GetActiveTake(right_xf)
      if xf_take then
        local max_left = NudgeEdge.max_extend_left(xf_take)
        if max_left < EPS then NudgeEdge.source_warning(); return false end
        if -delta > max_left then delta = -max_left end
      end
    end
    -- Source-bound clamp: left_xf Later grows la_len (Zone D atomic)
    if left_xf and delta > 0 and NudgeEdge then
      local la_take = r.GetActiveTake(left_xf)
      if la_take then
        local la_len_cur = r.GetMediaItemInfo_Value(left_xf, 'D_LENGTH')
        local max_right = NudgeEdge.max_extend_right(left_xf, la_take, la_len_cur)
        if max_right < EPS then NudgeEdge.source_warning(); return false end
        if delta > max_right then delta = max_right end
      end
    end
    if dry_run then return true, delta end
    -- Left atomic (Zone D): item_e_A moves with fi_end_B
    if left_xf then
      local la_len = r.GetMediaItemInfo_Value(left_xf, 'D_LENGTH')
      local la_fo  = NudgeEdge and NudgeEdge.get_fo(left_xf) or r.GetMediaItemInfo_Value(left_xf, 'D_FADEOUTLEN')
      r.SetMediaItemInfo_Value(left_xf, 'D_LENGTH', la_len + delta)
      if la_fo > EPS then
        if NudgeEdge then NudgeEdge.set_fo(left_xf, la_fo + delta)
        else r.SetMediaItemInfo_Value(left_xf, 'D_FADEOUTLEN', la_fo + delta) end
      end
      set_fi_item(fi_len + delta)
    else
      set_fi_item(math.max(0, fi_len + delta))
    end
    -- Right atomic (Zone B): pos_B moves with fo_start_A
    if right_xf then
      local xf_pos  = r.GetMediaItemInfo_Value(right_xf, 'D_POSITION')
      local xf_len  = r.GetMediaItemInfo_Value(right_xf, 'D_LENGTH')
      local xf_fi   = NudgeEdge and NudgeEdge.get_fi(right_xf) or r.GetMediaItemInfo_Value(right_xf, 'D_FADEINLEN')
      local xf_take = r.GetActiveTake(right_xf)
      r.SetMediaItemInfo_Value(right_xf, 'D_POSITION', xf_pos + delta)
      r.SetMediaItemInfo_Value(right_xf, 'D_LENGTH',   xf_len - delta)
      set_fo_item(fo_len - delta)
      if xf_fi > EPS then
        if NudgeEdge then NudgeEdge.set_fi(right_xf, xf_fi - delta)
        else r.SetMediaItemInfo_Value(right_xf, 'D_FADEINLEN', xf_fi - delta) end
      end
      if xf_take then
        local offs = r.GetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS')
        r.SetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS', offs + delta)
      end
    else
      set_fo_item(math.max(0, fo_len - delta))
    end

  elseif clip_covered and not fi_covered and fo_covered then
    -- Case 3: clip + fade_out shifts (Bl+C left view, or Br+O right view).
    -- With left_xf: fi_end_B = item_e_A is the LEFT edge of selection; Zone C atomic on left side.
    -- Source-bound clamp: Later shrinks STARTOFFS (offs - delta)
    if delta > 0 and take and NudgeEdge then
      local max_left = NudgeEdge.max_extend_left(take)
      if max_left < EPS then NudgeEdge.source_warning(); return false end
      if delta > max_left then delta = max_left end
    end
    -- Source-bound clamp: left_xf Later grows la_len (Zone C atomic on left side)
    if left_xf and delta > 0 and NudgeEdge then
      local la_take_clamp = r.GetActiveTake(left_xf)
      if la_take_clamp then
        local la_len_cur = r.GetMediaItemInfo_Value(left_xf, 'D_LENGTH')
        local max_right = NudgeEdge.max_extend_right(left_xf, la_take_clamp, la_len_cur)
        if max_right < EPS then NudgeEdge.source_warning(); return false end
        if delta > max_right then delta = max_right end
      end
    end
    -- Zone-preservation guard (Later, with right_xf): body shrinks; right item's body also shrinks (xf grows)
    if delta > 0 and right_xf then
      local body = len - fi_len - fo_len
      if body < 2*delta - EPS then return false end
      local xf_len = r.GetMediaItemInfo_Value(right_xf, 'D_LENGTH')
      local xf_fo  = NudgeEdge and NudgeEdge.get_fo(right_xf) or r.GetMediaItemInfo_Value(right_xf, 'D_FADEOUTLEN')
      local xf_fi  = NudgeEdge and NudgeEdge.get_fi(right_xf) or r.GetMediaItemInfo_Value(right_xf, 'D_FADEINLEN')
      local xf_body = xf_len - xf_fi - xf_fo
      if xf_body < 2*delta - EPS then return false end
    end
    -- Zone-preservation guard (Earlier): adjacent fi must stay >= 1 nudge grid; with right_xf fo also shrinks
    if delta < 0 then
      if fi_len < -2*delta - EPS then return false end
      if right_xf and fo_len < -2*delta - EPS then return false end
      -- With left_xf: la_fo (= crossfade) shrinks atomically; keep >= 1 grid
      if left_xf then
        local la_fo_chk = NudgeEdge and NudgeEdge.get_fo(left_xf) or r.GetMediaItemInfo_Value(left_xf, 'D_FADEOUTLEN')
        if la_fo_chk < -2*delta - EPS then return false end
      end
    end
    if dry_run then return true, delta end
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', len + delta)
    set_fi_item(fi_len + delta)
    if left_xf then
      -- Zone C atomic on left side: la extends with item_e_A = fi_end_B
      local la_len = r.GetMediaItemInfo_Value(left_xf, 'D_LENGTH')
      local la_fo  = NudgeEdge and NudgeEdge.get_fo(left_xf) or r.GetMediaItemInfo_Value(left_xf, 'D_FADEOUTLEN')
      r.SetMediaItemInfo_Value(left_xf, 'D_LENGTH', la_len + delta)
      if la_fo > EPS then
        if NudgeEdge then NudgeEdge.set_fo(left_xf, la_fo + delta)
        else r.SetMediaItemInfo_Value(left_xf, 'D_FADEOUTLEN', la_fo + delta) end
      end
      -- la_take STARTOFFS unchanged (left item content stays in absolute timeline)
    end
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs - delta)
    end
    sync_right()

  elseif clip_covered and fi_covered and not fo_covered then
    -- Case 4: I+Bl shifts (item right edge fixed; Bl-end shifts with Bl).
    -- With right_xf: Bl-end = pos_B, so Zone C atomic update applies (pos_B shifts, crossfade shrinks/grows).
    -- Source-bound clamp: Later shrinks STARTOFFS (offs - delta)
    if delta > 0 and take and NudgeEdge then
      local max_left = NudgeEdge.max_extend_left(take)
      if max_left < EPS then NudgeEdge.source_warning(); return false end
      if delta > max_left then delta = max_left end
    end
    -- Source-bound clamp: right_xf Earlier shrinks xf STARTOFFS (when pos_B shifts left)
    if right_xf and delta < 0 and NudgeEdge then
      local xf_take_clamp = r.GetActiveTake(right_xf)
      if xf_take_clamp then
        local max_left_xf = NudgeEdge.max_extend_left(xf_take_clamp)
        if max_left_xf < EPS then NudgeEdge.source_warning(); return false end
        if -delta > max_left_xf then delta = -max_left_xf end
      end
    end
    -- Zone-preservation guard (Later): fo shrinks (regular fo or crossfade) — keep >= 1 nudge grid
    if delta > 0 then
      if fo_len < 2*delta - EPS then return false end
    end
    if dry_run then return true, delta end
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',   len - delta)
    if right_xf then
      -- Zone C atomic: pos_B shifts with Bl-end, fo (= crossfade) shrinks
      local xf_pos  = r.GetMediaItemInfo_Value(right_xf, 'D_POSITION')
      local xf_len  = r.GetMediaItemInfo_Value(right_xf, 'D_LENGTH')
      local xf_fi   = NudgeEdge and NudgeEdge.get_fi(right_xf) or r.GetMediaItemInfo_Value(right_xf, 'D_FADEINLEN')
      local xf_take = r.GetActiveTake(right_xf)
      r.SetMediaItemInfo_Value(right_xf, 'D_POSITION', xf_pos + delta)
      r.SetMediaItemInfo_Value(right_xf, 'D_LENGTH',   xf_len - delta)
      set_fo_item(fo_len - delta)
      if xf_fi > EPS then
        if NudgeEdge then NudgeEdge.set_fi(right_xf, xf_fi - delta)
        else r.SetMediaItemInfo_Value(right_xf, 'D_FADEINLEN', xf_fi - delta) end
      end
      if xf_take then
        local offs = r.GetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS')
        r.SetMediaItemTakeInfo_Value(xf_take, 'D_STARTOFFS', offs + delta)
      end
    else
      set_fo_item(math.max(0, fo_len - delta))
    end
    -- STARTOFFS unchanged: pos shift alone moves content by delta (matching I+Bl shift).
    -- (Adjusting STARTOFFS here would double-shift content by 2*delta.)
    sync_left()

  elseif fo_covered and not clip_covered then
    -- Case 6: fade_out only -> right end moves
    -- Zone-preservation guard (Later, with right_xf): right item's body must stay >= 1 nudge grid
    if delta > 0 and right_xf then
      local xf_len = r.GetMediaItemInfo_Value(right_xf, 'D_LENGTH')
      local xf_fo  = NudgeEdge and NudgeEdge.get_fo(right_xf) or r.GetMediaItemInfo_Value(right_xf, 'D_FADEOUTLEN')
      local xf_fi  = NudgeEdge and NudgeEdge.get_fi(right_xf) or r.GetMediaItemInfo_Value(right_xf, 'D_FADEINLEN')
      local xf_body = xf_len - xf_fo - xf_fi
      if xf_body < 2*delta - EPS then return false end
    end
    -- Source-bound clamp: Later grows item length
    if delta > 0 and take and NudgeEdge then
      local max_right = NudgeEdge.max_extend_right(item, take, len)
      if max_right < EPS then NudgeEdge.source_warning(); return false end
      if delta > max_right then delta = max_right end
    end
    -- Zone-preservation guard (Earlier): body must stay >= 1 nudge grid
    -- (with right_xf, fo is restored by sync_left from the right item, but body still shrinks)
    if delta < 0 then
      local body = len - fi_len - fo_len
      if body < -2*delta - EPS then return false end
    end
    if dry_run then return true, delta end
    r.SetMediaItemInfo_Value(item, 'D_LENGTH', len + delta)
    sync_right()

  elseif fi_covered and not clip_covered then
    -- Case 7: fade_in only -> left end moves
    -- Source-bound clamp: Earlier shrinks STARTOFFS (offs + delta)
    if delta < 0 and take and NudgeEdge then
      local max_left = NudgeEdge.max_extend_left(take)
      if max_left < EPS then NudgeEdge.source_warning(); return false end
      if -delta > max_left then delta = -max_left end
    end
    -- Zone-preservation guard (Later): body must stay >= 1 nudge grid
    -- (with left_xf, fi is restored by sync_left from the left item, but body still shrinks)
    if delta > 0 then
      local body = len - fi_len - fo_len
      if body < 2*delta - EPS then return false end
    end
    if dry_run then return true, delta end
    r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta)
    r.SetMediaItemInfo_Value(item, 'D_LENGTH',   len - delta)
    if take then
      local offs = r.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
      r.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', offs + delta)
    end
    sync_left()

  else
    -- No case matched (razor doesn't fully cover any zone) — treat as blocked
    return false
  end
  return true, delta
end

-- Main
local delta = -get_delta()
if math.abs(delta) < 1e-10 then return end

-- Fallback: no items selected and no razor -> move edit cursor only
local has_items = r.CountSelectedMediaItems(0) > 0
local has_razor = false
for ti = 0, r.CountTracks(0) - 1 do
  local _, s = r.GetSetMediaTrackInfo_String(r.GetTrack(0,ti), 'P_RAZOREDITS', '', false)
  if s and s ~= '' then has_razor = true; break end
end

if not has_items and not has_razor then
  r.SetEditCurPos(r.GetCursorPosition() + delta, true, false)
  r.defer(function() end)
  return
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

-- track_nudged: nil = no item processed, true = moved, false = all blocked
-- min_actual: smallest |actual_delta| across all moved items (for razor sync when items clamp to source bound)
local track_nudged = {}
local min_actual = nil

local function track_actual(d)
  if min_actual == nil or math.abs(d) < math.abs(min_actual) then
    min_actual = d
  end
end

-- Pre-capture fade lengths for all selected items.
-- sync_right/sync_left from one item can modify another item's fade lengths,
-- which would break case detection for items processed later.
local item_state = {}
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item = r.GetSelectedMediaItem(0, i)
  item_state[item] = {
    fi_len = (NudgeEdge and NudgeEdge.get_fi(item)) or r.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
    fo_len = (NudgeEdge and NudgeEdge.get_fo(item)) or r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
  }
end

-- Pass 0 (dry-run): check if any item would block. If so, abort all modifications
-- (prevents partial-modification when one item blocks but another's sync would still
-- modify the blocked item indirectly via sync_left/sync_right).
local pre_block = false
for i = 0, r.CountSelectedMediaItems(0) - 1 do
  local item  = r.GetSelectedMediaItem(0, i)
  local track = r.GetMediaItemTrack(item)
  local sel_s, sel_e = get_track_razor(track)
  local pos   = r.GetMediaItemInfo_Value(item, 'D_POSITION')
  local len   = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
  local item_e = pos + len
  if sel_s and sel_e and sel_e > pos + EPS and sel_s < item_e - EPS then
    local clamped_s = math.max(sel_s, pos)
    local clamped_e = math.min(sel_e, item_e)
    local moved = nudge_item(item, clamped_s, clamped_e, delta, item_state[item], true)  -- dry_run
    if moved == false then pre_block = true; break end
  end
end

-- Pass 1 (apply): only if no item would block
if not pre_block then
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item  = r.GetSelectedMediaItem(0, i)
    local track = r.GetMediaItemTrack(item)
    local sel_s, sel_e = get_track_razor(track)
    local pos   = r.GetMediaItemInfo_Value(item, 'D_POSITION')
    local len   = r.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local item_e = pos + len

    if sel_s and sel_e then
      -- Razor exists: use razor as selection
      if sel_e > pos + EPS and sel_s < item_e - EPS then
        local clamped_s = math.max(sel_s, pos)
        local clamped_e = math.min(sel_e, item_e)
        local moved, actual = nudge_item(item, clamped_s, clamped_e, delta, item_state[item], false)
        if moved == false then
          track_nudged[track] = false
        elseif moved then
          if track_nudged[track] == nil then track_nudged[track] = true end
          track_actual(actual or delta)
        end
      end
    else
      -- No razor: item selection = entire item -> position move
      if NudgeEdge then NudgeEdge.nudge_position(item, delta)
      else r.SetMediaItemInfo_Value(item, 'D_POSITION', pos + delta) end
      track_nudged[track] = true
      track_actual(delta)
    end
  end
else
  -- Pre-block: mark all involved tracks as blocked so razor + TS freeze
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    track_nudged[r.GetMediaItemTrack(item)] = false
  end
end

-- All razors sync: if any track is blocked, freeze all razors and time selection
local any_blocked = false
for _, v in pairs(track_nudged) do
  if v == false then any_blocked = true; break end
end
local do_move = not any_blocked
local effective_delta = min_actual or delta

for ti = 0, r.CountTracks(0) - 1 do
  if do_move then
    local track = r.GetTrack(0, ti)
    local _, s = r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
    if s and s ~= '' then
      local new_s = s:gsub('(%S+)%s+(%S+)%s+""', function(a, b)
        local rs, re = tonumber(a), tonumber(b)
        if rs and re then
          return string.format('%.14f %.14f ""', rs + effective_delta, re + effective_delta)
        end
        return a .. ' ' .. b .. ' ""'
      end)
      r.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', new_s, true)
    end
  end
end

local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
if te > ts + EPS and do_move then
  r.GetSet_LoopTimeRange(true, false, ts + effective_delta, te + effective_delta, false)
end

if Sync then Sync.cursor_follow() end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.Undo_EndBlock('Pro Tools: Nudge Clip Earlier By Grid', -1)
