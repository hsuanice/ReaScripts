--[[
@description hsuanice_Review_Edges_Off_Grid
@version 250929_0536
@author hsuanice
@about
  Scan all items in the project. If an item's left/right edge is not aligned to the chosen grid
  (Frame/Beats/Seconds/Samples), add take marker(s) at the edge(s) using source-time coordinates
  and print a concise console report (same Review style as your other scripts).
  Notes:
  - Source-pos mapping honors take rate (D_PLAYRATE) and start offset (D_STARTOFFS).
  - Duplicate suppression: skip if same-name marker already exists near the same source position.
  - Scope: all items in project (no selection required).
  - Console: summary + per-issue lines; uses ShowConsoleMsg (clears at start).
@changelog
  v250929_0536
  - Fixed-markers now placed slightly INSIDE the item edges using project-time inset (MARKER_EDGE_INSET_PROJ_SEC) so they remain visible even when the edge sits on the item boundary.
  - Keeps existing source-boundary inset (MARKER_INSET_SEC) as a secondary safeguard.
  v250929_0508
  - Ensure right-edge take markers are visible when very close to the source end: added MARKER_INSET_SEC to nudge markers slightly inward from 0/end.
  - Remove temporary console debug line for right markers.
  v250929_0456
  - Take marker labels now indicate the operation: "trim to grid" or "extend to grid" for each edge.
  - Ensure Right-edge fixed marker is created after length update and using refreshed pos/len; extra debug log prints marker source position on add.
  v250929_0430
  - Content-lock invariant fix: when moving item start by +Δ, all takes' STARTOFFS must shift by **+Δ×rate** (not −Δ×rate). This keeps source mapping startoffs+(t-pos)*rate unchanged ⇒ content truly stays fixed.
  v250929_0412
  - CONTENT-LOCK fix: when moving item position by +Δ (trim left) the takes' STARTOFFS now shift by **-Δ×rate** so timeline content truly stays fixed.
  - Trim-only logic: compute right-edge target **once from the original right time**; after fixing left edge, snap right to that original target (never re-round upward). Prevents unintended rounding to a later frame.
  v250929_0310
  - After left-edge fix, recompute pos/len and recalc right edge target to avoid overshoot.
  - Right-edge console now prints the NEW right-edge time (pos+len) after the fix.
  v250929_0231
  - Fix: after left-edge adjustment (content_locked may move item position), recompute right edge time before deciding right-edge target. Prevents overshoot.
  - Fix: "Fixed: Right ..." console log now shows the NEW right-edge time (pos+len), not item position.
  v250927_2116
  - Initial release. Modes: Frame (default) / Beats / Seconds / Samples.
    Adds "Review:" take markers at off-grid left/right edges, rate/offset-safe, de-duplicated.
  v250928_2010
  - Switch scope to ALL project items (no selection needed).
  - Add console reporting (header, per-flag lines, and summary).
  - Minor: clearer undo text.
  v250928_2055
  - Add per-mode tolerance to avoid false positives due to float rounding (default: ±0.01 frame).
  - Console now shows Δ vs grid in native units and milliseconds.
  v250928_2122
  - Robustness: clamp marker source position into [0, source_length) and use 5-arg SetTakeMarker(..., color=0).
  - Debug: log when clamping occurs or when SetTakeMarker fails.
  v250928_2335
  - Add ACTION_MODE:
    1 = Review only (no edits),
    2 = Fix to nearest grid (extend or trim),
    3 = Fix by trimming only (never extend).
  - Guaranteed no-move of timeline content: left-edge ops adjust start offset + length (keep item position), right-edge ops adjust length only.
  - Detailed "Fixed:" console logs and per-edge take markers after edits.
  v250928_2359
  - Left-edge edit now updates STARTOFFS for **all takes** in the item (not just the active take).
    * Extend clamp honors the most restrictive take (min available start offset across takes).
    * Trim clamp still honors current item length.
  v250929_0018
  - Console logs for "Fixed:" now include the active take name.
  v250929_0119
  - Add LEFT_EDGE_STRATEGY:
    * "position_locked" (default): keep item start time fixed; left extend impossible, only trim-in or shift content via startoffs/length (previous behavior).
    * "content_locked": move item position by Δ and offset all takes' STARTOFFS by the same Δ*rate to keep absolute timeline content unchanged (left edge truly snaps).
  - Fix-nearest now respects the chosen strategy to ensure visible left-edge movement when desired.
]]--

local r = reaper

---------------------------------------
-- Console helpers
---------------------------------------
local function log(s) r.ShowConsoleMsg(tostring(s) .. "\n") end
local function clr() r.ShowConsoleMsg("") end

---------------------------------------
-- User options
---------------------------------------
-- MODE: "frame" | "beats" | "seconds" | "samples"
local MODE = "frame"

-- Per-mode tolerance ("how close is close enough" to consider ON the grid)
-- Frame: frames, Beats: quarter-notes, Seconds: seconds, Samples: samples
local TOL = {
  frame   = 0.001,   -- ±0.01 frame (~0.417 ms @ 24fps)
  beats   = 1e-4,   -- ±0.0001 QN
  seconds = 0.0001,  -- ±1 ms
  samples = 1.0,    -- ±1 sample
}

-- ACTION_MODE: 1=review only; 2=fix to nearest grid (extend or trim); 3=trim-only (never extend)
local ACTION_MODE = 2
-- When fixing, also drop a take marker at new edge
local ADD_FIXED_MARKER = true

local MARKER_INSET_SEC = 0.0000  -- nudge markers inward by ~1.5 ms when at 0 or source end
local MARKER_EDGE_INSET_PROJ_SEC = 0.001  -- project-time inset for fixed markers (~1 ms inside the item edge)

-- LEFT_EDGE_STRATEGY:
--   "position_locked"  → do not move D_POSITION; left extend is emulated via startoffs/length (visual left edge stays put)
--   "content_locked"   → move D_POSITION by Δ and shift all takes' STARTOFFS by Δ*rate so content stays locked to timeline
local LEFT_EDGE_STRATEGY = "content_locked"

-- 時基容差（比對是否「貼齊格線」時的近似容許）
-- 這些是「轉回秒」後的比較會用到的 epsilon（盡量小，但避免浮點誤差造成誤判）
local EPS_SEC = 1e-7

-- 標籤樣式（沿用你的 Review 風格）
local LABEL_LEFT_FMT  = "Review: Left edge off grid (%s)"
local LABEL_RIGHT_FMT = "Review: Right edge off grid (%s)"
local UNDO_TITLE_FMT = "Review: flag off-grid edges (%s) — %d marker(s)"

local FIX_LABEL_LEFT_FMT  = "Fixed: Left edge — %s to grid (%s)"
local FIX_LABEL_RIGHT_FMT = "Fixed: Right edge — %s to grid (%s)"

---------------------------------------
-- Helpers
---------------------------------------
local function safe_takename(tk)
  local name = tk and r.GetTakeName(tk) or ""
  if not name or name == "" then return "(no-take-name)" end
  return name
end
local function safe_trackname(tr)
  local ok, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if ok and name ~= "" then return name end
  return string.format("Track %d", tr and (r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or -1)
end
local function abs(x) return x >= 0 and x or -x end
local function round(x) return math.floor(x + 0.5) end
local function nearly_equal(a, b, eps) return abs(a - b) <= (eps or EPS_SEC) end

-- 取得專案取樣率（若未鎖定，回落到音效裝置 SR 或 48000）
local function get_project_samplerate()
  local use = r.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false)
  local srate = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if use == 0 or (srate or 0) <= 0 then
    local dev_sr = tonumber(r.GetAudioDeviceInfo("SRATE", "")) or 0
    if dev_sr > 0 then return dev_sr end
    return 48000
  end
  return srate
end

-- Return deviation in both seconds and native units for MODE
-- (dev_sec, dev_units). dev_units is in frames/beats/seconds/samples.
local function grid_deviation(t)
  if MODE == "seconds" then
    local nearest = round(t)
    local dev_sec = t - nearest
    return dev_sec, dev_sec
  elseif MODE == "samples" then
    local sr = get_project_samplerate()
    local samples = t * sr
    local nearest = round(samples)
    local dev_samples = samples - nearest
    return dev_samples / sr, dev_samples
  elseif MODE == "frame" then
    local fps = r.TimeMap_curFrameRate(0) or 30
    local frames = t * fps
    local nearest = round(frames)
    local dev_frames = frames - nearest
    return dev_frames / fps, dev_frames
  elseif MODE == "beats" then
    -- whole-beat grid by default
    local qn = r.TimeMap_timeToQN(t)
    local nearest_qn = round(qn)
    local dev_qn = qn - nearest_qn
    local nearest_t = r.TimeMap_QNToTime(nearest_qn)
    return t - nearest_t, dev_qn
  else
    return 0.0, 0.0
  end
end

-- Compute nearest/floor/ceil grid times for the current MODE
local function grid_round_time(t)
  if MODE == "seconds" then
    return round(t)
  elseif MODE == "samples" then
    local sr = get_project_samplerate()
    return round(t * sr) / sr
  elseif MODE == "frame" then
    local fps = r.TimeMap_curFrameRate(0) or 30
    return round(t * fps) / fps
  elseif MODE == "beats" then
    local qn = r.TimeMap_timeToQN(t)
    local nr = round(qn)
    return r.TimeMap_QNToTime(nr)
  else
    return t
  end
end
local function grid_floor_time(t)
  if MODE == "seconds" then
    return math.floor(t)
  elseif MODE == "samples" then
    local sr = get_project_samplerate()
    return math.floor(t * sr) / sr
  elseif MODE == "frame" then
    local fps = r.TimeMap_curFrameRate(0) or 30
    return math.floor(t * fps) / fps
  elseif MODE == "beats" then
    local qn = r.TimeMap_timeToQN(t)
    local fl = math.floor(qn)
    return r.TimeMap_QNToTime(fl)
  else
    return t
  end
end
local function grid_ceil_time(t)
  if MODE == "seconds" then
    return math.ceil(t)
  elseif MODE == "samples" then
    local sr = get_project_samplerate()
    return math.ceil(t * sr) / sr
  elseif MODE == "frame" then
    local fps = r.TimeMap_curFrameRate(0) or 30
    return math.ceil(t * fps) / fps
  elseif MODE == "beats" then
    local qn = r.TimeMap_timeToQN(t)
    local cl = math.ceil(qn)
    return r.TimeMap_QNToTime(cl)
  else
    return t
  end
end

local function is_off_grid(dev_units)
  local tol = TOL[MODE] or 0
  return abs(dev_units) > tol
end

-- project time → take/source time（位置映射）
local function projtime_to_taketime(take, item, proj_t)
  local item_pos  = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local rate      = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
  if rate == 0 then rate = 1 end
  local startoffs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
  return startoffs + (proj_t - item_pos) * rate
end

-- 取偏好的 take（優先 active，否則回落第一個有效 take）
local function get_preferred_take(it)
  local tk = r.GetActiveTake(it)
  if tk and r.ValidatePtr2(0, tk, "MediaItem_Take*") then return tk end
  local n = r.CountTakes(it)
  for i = 0, n - 1 do
    local tki = r.GetTake(it, i)
    if tki and r.ValidatePtr2(0, tki, "MediaItem_Take*") then return tki end
  end
  return nil
end

-- 同名且同源位置附近已有 marker 就略過（避免重複）
local function has_similar_marker(take, name, srcpos, src_eps)
  local n = r.GetNumTakeMarkers(take) or 0
  for i = 0, n - 1 do
    local _, mk_name, mk_srcpos = r.GetTakeMarker(take, i)
    if mk_name == name then
      if nearly_equal((mk_srcpos or 0), (srcpos or 0), (src_eps or EPS_SEC) * 1000) then
        return true
      end
    end
  end
  return false
end

local function add_take_marker_if_needed(take, name, srcpos, src_eps)
  if has_similar_marker(take, name, srcpos, src_eps) then return false end
  -- Clamp to source length to ensure visibility
  local src = r.GetMediaItemTake_Source(take)
  local ok_len, src_len = false, 0.0
  if src and r.ValidatePtr2(0, src, "PCM_source*") then
    src_len = ({r.GetMediaSourceLength(src)})[1] or 0.0
    ok_len = src_len and src_len > 0
  end
  local clamped_pos = srcpos
  if ok_len then
    -- If very close to boundaries, nudge inward so marker remains visible in item
    if clamped_pos < MARKER_INSET_SEC then
      clamped_pos = math.max(0, MARKER_INSET_SEC)
    elseif (src_len - clamped_pos) < MARKER_INSET_SEC then
      clamped_pos = math.max(0, src_len - MARKER_INSET_SEC)
    end
    -- Hard clamp just in case
    if clamped_pos < 0 then
      clamped_pos = 0
    elseif clamped_pos > src_len - 1e-6 then
      clamped_pos = src_len - 1e-6
    end
  end
  -- Use 5-arg API (some REAPER versions require explicit color param)
  local idx = r.SetTakeMarker(take, -1, name, clamped_pos, 0)
  if not idx or idx < 0 then
    log("  !! SetTakeMarker failed (take marker not created).")
    return false
  end
  return true
end

-- Fetch source length (seconds) for a take
local function get_source_len_sec(take)
  local src = r.GetMediaItemTake_Source(take)
  if not (src and r.ValidatePtr2(0, src, "PCM_source*")) then return 0 end
  return ({r.GetMediaSourceLength(src)})[1] or 0
end

-- For left extension (moving left edge left), find the maximum allowed extension across ALL takes
-- based on each take's available start offset (offs/rate). Returns seconds.
local function calc_max_left_extend_all_takes(item)
  local n = r.CountTakes(item)
  local max_ext = math.huge
  for i = 0, n - 1 do
    local tk = r.GetTake(item, i)
    if tk and r.ValidatePtr2(0, tk, "MediaItem_Take*") then
      local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1
      if rate == 0 then rate = 1 end
      local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
      local ext = offs / rate
      if ext < max_ext then max_ext = ext end
    end
  end
  if max_ext == math.huge then max_ext = 0 end
  return max_ext
end

-- Shift all takes' STARTOFFS by +delta_sec * rate, clamped to [0, src_len]
local function shift_all_takes_startoffs(item, delta_sec)
  local n = r.CountTakes(item)
  for i = 0, n - 1 do
    local tk = r.GetTake(item, i)
    if tk and r.ValidatePtr2(0, tk, "MediaItem_Take*") then
      local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1
      if rate == 0 then rate = 1 end
      local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
      local new_offs = offs + delta_sec * rate
      local src_len = get_source_len_sec(tk)
      if new_offs < 0 then new_offs = 0 end
      if src_len > 0 and new_offs > src_len then new_offs = src_len end
      r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", new_offs)
    end
  end
end

-- Left-edge change with CONTENT LOCK: move item position and shift all takes' start offset by -Δ×rate; keep length unchanged.
-- Positive delta → move start later (trim), Negative delta → move start earlier (extend).
local function apply_left_delta_content_locked(item, take_hint, delta_sec)
  if delta_sec == 0 then return 0, 0 end
  local pos  = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len  = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local applied = delta_sec
  -- Clamp when extending earlier than available media across ALL takes
  if delta_sec < 0 then
    local max_ext_all = calc_max_left_extend_all_takes(item)
    if -delta_sec > max_ext_all then
      applied = -max_ext_all
      log(string.format("  (left extend clamped by ALL takes' start offset [content_locked]: %.6f → %.6f)", -delta_sec, -applied))
    end
  else
    -- trim: cannot trim more than length
    if delta_sec > len - 1e-9 then
      applied = len - 1e-9
      log(string.format("  (left trim clamped by item length [content_locked]: %.6f → %.6f)", delta_sec, applied))
    end
  end
  -- Move item position and shift all takes' start offset by -Δ×rate; keep length unchanged.
  r.SetMediaItemInfo_Value(item, "D_POSITION", pos + applied)
  shift_all_takes_startoffs(item, applied)
  return applied, 0
end

-- Keep item position fixed while altering left edge:
-- delta_sec > 0 => trim-in by delta (move left edge right)
-- delta_sec < 0 => extend-out by -delta (move left edge left)
local function apply_left_delta_keep_pos(item, take_for_rate_hint, delta_sec)
  if delta_sec == 0 then return 0, 0 end
  local pos  = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
  local len  = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  -- For min/max computations use the provided take's rate if needed, but we will update ALL takes.
  local rate_hint = r.GetMediaItemTakeInfo_Value(take_for_rate_hint, "D_PLAYRATE") or 1
  if rate_hint == 0 then rate_hint = 1 end
  local applied = delta_sec
  if delta_sec < 0 then
    -- extend left: limited by available start offset across ALL takes
    local max_ext_all = calc_max_left_extend_all_takes(item)
    if -delta_sec > max_ext_all then
      applied = -max_ext_all
      log(string.format("  (left extend clamped by ALL takes' start offset: %.6f → %.6f)", -delta_sec, -applied))
    end
  else
    -- trim left: limited by current length
    if delta_sec > len - 1e-9 then
      applied = len - 1e-9
      log(string.format("  (left trim clamped by item length: %.6f → %.6f)", delta_sec, applied))
    end
  end
  -- Update ALL takes' start offset according to each take's rate; item position unchanged
  local n = r.CountTakes(item)
  for i = 0, n - 1 do
    local tk = r.GetTake(item, i)
    if tk and r.ValidatePtr2(0, tk, "MediaItem_Take*") then
      local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1
      if rate == 0 then rate = 1 end
      local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
      local new_offs = offs + applied * rate
      -- Soft clamp to [0, src_len], to be safe
      local src_len = get_source_len_sec(tk)
      if new_offs < 0 then new_offs = 0 end
      if src_len > 0 and new_offs > src_len then new_offs = src_len end
      r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", new_offs)
    end
  end
  -- Adjust item length to keep position fixed
  r.SetMediaItemInfo_Value(item, "D_LENGTH",      len - applied)
  return applied, (len - (len - applied))
end
-- Keep item position fixed while altering right edge:
-- delta_sec > 0 => extend right by delta, delta_sec < 0 => trim right by -delta
local function apply_right_delta_keep_pos(item, take, delta_sec)
  if delta_sec == 0 then return 0, 0 end
  local len  = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
  if rate == 0 then rate = 1 end
  local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
  local src_len = get_source_len_sec(take)
  local applied = delta_sec
  if delta_sec > 0 then
    -- extend right: limited by source tail
    local used_src = offs + len * rate
    local tail = src_len - used_src
    local max_ext = math.max(0, tail / rate)
    if delta_sec > max_ext then
      applied = max_ext
      log(string.format("  (right extend clamped by source tail: %.6f → %.6f)", delta_sec, applied))
    end
  else
    -- trim right: limited by current length
    if -delta_sec > len - 1e-9 then
      applied = -(len - 1e-9)
      log(string.format("  (right trim clamped by item length: %.6f → %.6f)", -delta_sec, -applied))
    end
  end
  r.SetMediaItemInfo_Value(item, "D_LENGTH", len + applied)
  return applied, ((len + applied) - len)
end

---------------------------------------
-- Core
---------------------------------------
local function check_item_edges_and_log(it, mode_title, added_counter)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0
  if (len or 0) <= 0 then return added_counter end

  local left_t  = pos
  local right_t = pos + len

  local devL_sec, devL_units = grid_deviation(left_t)
  local devR_sec, devR_units = grid_deviation(right_t)

  local offL = is_off_grid(devL_units)
  local offR = is_off_grid(devR_units)

  local do_fix = (ACTION_MODE == 2) or (ACTION_MODE == 3)
  local trimmed_only = (ACTION_MODE == 3)
  local targetL, targetR
  if do_fix then
    if offL then
      if trimmed_only then
        targetL = grid_ceil_time(left_t)      -- inward for left edge
      else
        targetL = grid_round_time(left_t)     -- nearest
      end
    end
    if offR then
      if trimmed_only then
        targetR = grid_floor_time(right_t)    -- inward for right edge
      else
        targetR = grid_round_time(right_t)    -- nearest
      end
    end
  end

  if not do_fix and not (offL or offR) then return added_counter end

  local tk = get_preferred_take(it)
  if not tk then return added_counter end

  -- prepare printable item info (track index, item pos/len)
  local tr = r.GetMediaItem_Track(it)
  local tr_idx = tr and (r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or 0
  local tr_name = safe_trackname(tr)
  local tk_name = safe_takename(tk)

  local appliedL, appliedR = 0, 0
  if do_fix then
    if offL and targetL then
      local deltaL = targetL - left_t
      if trimmed_only and deltaL < 0 then
        -- would extend; cancel in trim-only mode
        deltaL = 0
      end
      if deltaL ~= 0 then
        if LEFT_EDGE_STRATEGY == "content_locked" then
          local applied = apply_left_delta_content_locked(it, tk, deltaL)
          appliedL = applied
        else
          local applied = apply_left_delta_keep_pos(it, tk, deltaL)
          appliedL = applied
        end
        local applied = appliedL
        if math.abs(applied) > 0 then
          if ADD_FIXED_MARKER then
            local pos_now = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0
            local len_now = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0
            -- Place marker slightly inside the item (project-time) to guarantee visibility
            local left_proj = math.min(pos_now + MARKER_EDGE_INSET_PROJ_SEC, pos_now + math.max(0, len_now - 1e-6))
            local src_newL = projtime_to_taketime(tk, it, left_proj)
            local op = (applied < 0 and "extend" or "trim")
            add_take_marker_if_needed(tk, string.format(FIX_LABEL_LEFT_FMT, op, mode_title), src_newL, EPS_SEC)
          end
          log(string.format("Fixed: %s [%s] Left %s by %.6f sec (%.3f ms) → %.6f",
                            tr_name, tk_name,
                            (applied < 0 and "extend" or "trim"),
                            math.abs(applied), math.abs(applied)*1000.0,
                            (r.GetMediaItemInfo_Value(it, "D_POSITION") or 0)))
        end
      end
    end
    -- Refresh times after left-edge edits (content_locked may have moved item position)
    pos = r.GetMediaItemInfo_Value(it, "D_POSITION") or pos
    len = r.GetMediaItemInfo_Value(it, "D_LENGTH") or len
    left_t  = pos
    right_t = pos + len
    -- Do NOT recompute targetR; use the original right_t-based target
    devR_sec, devR_units = grid_deviation(right_t)
    offR = is_off_grid(devR_units)
    if offR and targetR then
      local deltaR = targetR - right_t
      if trimmed_only and deltaR > 0 then
        -- would extend; cancel in trim-only mode
        deltaR = 0
      end
      if deltaR ~= 0 then
        local applied = apply_right_delta_keep_pos(it, tk, deltaR)
        appliedR = applied
        if ADD_FIXED_MARKER then
          local pos_now = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0
          local len_now = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0
          local right_proj = math.max(pos_now, pos_now + len_now - MARKER_EDGE_INSET_PROJ_SEC)
          local src_newR = projtime_to_taketime(tk, it, right_proj)
          local opR = (applied < 0 and "trim" or "extend")
          add_take_marker_if_needed(tk, string.format(FIX_LABEL_RIGHT_FMT, opR, mode_title), src_newR, EPS_SEC)
        end
        local pos_after = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0
        local len_after = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0
        local right_after = pos_after + len_after
        log(string.format("Fixed: %s [%s] Right %s by %.6f sec (%.3f ms) → %.6f",
                          tr_name, tk_name,
                          (applied < 0 and "trim" or "extend"),
                          math.abs(applied), math.abs(applied)*1000.0,
                          right_after))
      end
    end
  end

  if ACTION_MODE == 1 then
    if offL then
      local srcL = projtime_to_taketime(tk, it, left_t)
      local name = string.format(LABEL_LEFT_FMT, mode_title)
      if add_take_marker_if_needed(tk, name, srcL, EPS_SEC) then
        log(string.format("• Track %d  Left off-grid @ %.6f sec  (Δ=%.6f %s, %.3f ms)  src=%.6f",
                          tr_idx, left_t,
                          devL_units, (MODE == "frame" and "fr" or MODE == "beats" and "qn" or MODE == "samples" and "smp" or "s"),
                          devL_sec * 1000.0,
                          srcL))
        added_counter = added_counter + 1
      end
    end
    if offR then
      local srcR = projtime_to_taketime(tk, it, right_t)
      local name = string.format(LABEL_RIGHT_FMT, mode_title)
      if add_take_marker_if_needed(tk, name, srcR, EPS_SEC) then
        log(string.format("• Track %d  Right off-grid @ %.6f sec  (Δ=%.6f %s, %.3f ms)  src=%.6f",
                          tr_idx, right_t,
                          devR_units, (MODE == "frame" and "fr" or MODE == "beats" and "qn" or MODE == "samples" and "smp" or "s"),
                          devR_sec * 1000.0,
                          srcR))
        added_counter = added_counter + 1
      end
    end
  end

  return added_counter
end

local function main()
  local mode_title = (MODE:gsub("^%l", string.upper))

  -- Console header
  r.ClearConsole()
  log(string.format("[Review] Edges Off Grid — Mode: %s", mode_title))
  if MODE == "frame" then
    local fps = r.TimeMap_curFrameRate(0) or 30
    log(string.format("Frame rate: %.3f fps", fps))
  elseif MODE == "samples" then
    log(string.format("Sample rate: %.0f Hz", get_project_samplerate()))
  end
  log(string.format("Tolerance: ±%s",
    (MODE == "frame"   and (string.format("%.3f fr", TOL.frame)))   or
    (MODE == "beats"   and (string.format("%.5f qn", TOL.beats)))   or
    (MODE == "samples" and (string.format("%.0f smp", TOL.samples)))or
    (MODE == "seconds" and (string.format("%.3f s",  TOL.seconds))) or "—"))
  log("Scanning: entire project (all items)")
  log(string.format("Action: %s", (ACTION_MODE==1 and "Review only") or (ACTION_MODE==2 and "Fix to nearest") or "Trim-only (never extend)"))
  log("--------------------------------------------------")

  local total = r.CountMediaItems(0)
  if total == 0 then
    log("No items in project.")
    return
  end

  local added = 0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  for i = 0, total - 1 do
    local it = r.GetMediaItem(0, i)
    if it then
      added = check_item_edges_and_log(it, mode_title, added)
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock(string.format("%s — %s", string.format(UNDO_TITLE_FMT, mode_title, added),
    (ACTION_MODE==1 and "review") or (ACTION_MODE==2 and "fix-nearest") or "fix-trim-only"), -1)

  -- Summary
  log("--------------------------------------------------")
  log(string.format("Done. Markers added: %d (mode=%s)", added, mode_title))
end

main()
