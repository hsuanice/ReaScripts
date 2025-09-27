--[[
@description hsuanice_Review_Edges_Off_Grid
@version 250928_2122
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
  frame   = 0.01,   -- ±0.01 frame (~0.417 ms @ 24fps)
  beats   = 1e-4,   -- ±0.0001 QN
  seconds = 0.001,  -- ±1 ms
  samples = 1.0,    -- ±1 sample
}

-- 時基容差（比對是否「貼齊格線」時的近似容許）
-- 這些是「轉回秒」後的比較會用到的 epsilon（盡量小，但避免浮點誤差造成誤判）
local EPS_SEC = 1e-7

-- 標籤樣式（沿用你的 Review 風格）
local LABEL_LEFT_FMT  = "Review: Left edge off grid (%s)"
local LABEL_RIGHT_FMT = "Review: Right edge off grid (%s)"
local UNDO_TITLE_FMT = "Review: flag off-grid edges (%s) — %d marker(s)"

---------------------------------------
-- Helpers
---------------------------------------
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
    if clamped_pos < 0 then
      clamped_pos = 0
      log(string.format("  (clamped srcpos < 0 → 0.000000)"))
    elseif clamped_pos > src_len - 1e-6 then
      clamped_pos = src_len - 1e-6
      log(string.format("  (clamped srcpos to source end: %.6f / %.6f)", clamped_pos, src_len))
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
  if not (offL or offR) then return added_counter end

  local tk = get_preferred_take(it)
  if not tk then return added_counter end

  -- prepare printable item info (track index, item pos/len)
  local tr = r.GetMediaItem_Track(it)
  local tr_idx = tr and (r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or 0

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
  r.Undo_EndBlock(string.format(UNDO_TITLE_FMT, mode_title, added), -1)

  -- Summary
  log("--------------------------------------------------")
  log(string.format("Done. Markers added: %d (mode=%s)", added, mode_title))
end

main()
