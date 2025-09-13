--[[
@description ReaImGui - Count Items/Tracks and Toggle Show Item Details (throttled)
@version 0.2.0.1
@author hsuanice
@about
  A tiny HUD for monitoring selected item/track counts, with optional details.
  This version is optimized for large sessions:
    - Throttled scanning (debounced) to avoid per-frame heavy loops
    - Only scans per-item details when the panel is expanded AND selection changed
    - Summary (items/tracks) path is O(1) per frame

@changelog
  v0.2.0.1 (2025-09-13)
    - Fix: Always call ImGui_End() after ImGui_Begin(), regardless of
      the 'visible' flag. Prevents "ImGui_SameLine: expected a valid
      ImGui_Context*" on ReaImGui 0.9.3.2 and ensures proper stack
      balance when the window is collapsed/hidden.
    - No change to UMID generation/embedding; purely UI stability.
  v0.2.0.1
  - Fix reaper.ImGui_End(ctx)
  v0.2.0
  - Performance: throttle/debounce heavy scans (details) to at most every 150 ms
  - Performance: when details panel is collapsed, skip per-item scanning entirely
  - Correctly detect selection changes via project state version + counts
  - Minor UI clean-up; right-click to close preserved
--]]

-------------------------------------------
-- User options
-------------------------------------------
local align_mode     = "left"   -- "left" | "center" | "right"
local initial_width  = 240
local initial_height = 60
local SCAN_INTERVAL  = 0.15     -- seconds, throttle heavy scans
-------------------------------------------

local ctx = reaper.ImGui_CreateContext('Selection Monitor Expand')
local window_flags =
    reaper.ImGui_WindowFlags_NoTitleBar()
  | reaper.ImGui_WindowFlags_NoCollapse()
  | reaper.ImGui_WindowFlags_NoResize()
  | reaper.ImGui_WindowFlags_AlwaysAutoResize()

local show_details   = false
local white          = 0xFFFFFFFF
local first_frame    = true

-- cache / debounce
local last_proj_ver      = -1
local last_item_count    = -1
local last_track_count   = -1
local next_allowed_scan  = 0.0
local cached_stats       = {
  item_count   = 0,
  track_count  = 0,
  type_count   = { midi = 0, audio = 0, empty = 0 },
  channel_count= {}
}

-------------------------------------------
-- UI helpers
-------------------------------------------
local function calc_text_w(ctx, text)
  local w = select(1, reaper.ImGui_CalcTextSize(ctx, text))
  return w or 0
end

local function get_win_w(ctx)
  local w = select(1, reaper.ImGui_GetWindowSize(ctx))
  return w or 0
end

local function draw_aligned_text(ctx, text)
  local width = calc_text_w(ctx, text)
  local win_w = get_win_w(ctx)
  if align_mode == "center" then
    reaper.ImGui_SetCursorPosX(ctx, (win_w - width) / 2)
  elseif align_mode == "right" then
    reaper.ImGui_SetCursorPosX(ctx, win_w - width - 10)
  end
  reaper.ImGui_Text(ctx, text)
end

local function draw_aligned_label(ctx, text, color)
  local width = calc_text_w(ctx, text)
  local win_w = get_win_w(ctx)
  if align_mode == "center" then
    reaper.ImGui_SetCursorPosX(ctx, (win_w - width) / 2)
  elseif align_mode == "right" then
    reaper.ImGui_SetCursorPosX(ctx, win_w - width - 10)
  end
  reaper.ImGui_TextColored(ctx, color or white, text)
end

-------------------------------------------
-- Scanners
-------------------------------------------
local function scan_summary_only()
  -- O(1), no per-item walks
  cached_stats.item_count  = reaper.CountSelectedMediaItems(0)
  cached_stats.track_count = reaper.CountSelectedTracks(0)
end

local function scan_details_heavy()
  -- Per-item walk, throttled & only when needed
  local item_count = reaper.CountSelectedMediaItems(0)
  local track_count = reaper.CountSelectedTracks(0)

  local type_count = { midi = 0, audio = 0, empty = 0 }
  local channel_count = {}

  for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if not take then
      type_count.empty = type_count.empty + 1
    else
      local src = reaper.GetMediaItemTake_Source(take)
      local srctype = reaper.GetMediaSourceType(src, "")
      if srctype == "MIDI" or srctype == "REX" then
        type_count.midi = type_count.midi + 1
      else
        type_count.audio = type_count.audio + 1
      end
      local ch = reaper.GetMediaSourceNumChannels(src) or 0
      if ch > 0 then channel_count[ch] = (channel_count[ch] or 0) + 1 end
    end
  end

  cached_stats.item_count    = item_count
  cached_stats.track_count   = track_count
  cached_stats.type_count    = type_count
  cached_stats.channel_count = channel_count
end

-------------------------------------------
-- Draw
-------------------------------------------
local function draw_summary_row(ctx, stats)
  local summary = string.format("Items: %d    Tracks: %d", stats.item_count, stats.track_count)
  local summary_w = calc_text_w(ctx, summary)
  local win_w     = get_win_w(ctx)

  if align_mode == "center" then
    reaper.ImGui_SetCursorPosX(ctx, (win_w - summary_w) / 2 - 20)
  elseif align_mode == "right" then
    reaper.ImGui_SetCursorPosX(ctx, win_w - summary_w - 40)
  end

  reaper.ImGui_Text(ctx, summary)
  reaper.ImGui_SameLine(ctx)

  if reaper.ImGui_ArrowButton(ctx, "details_toggle",
      show_details and reaper.ImGui_Dir_Down() or reaper.ImGui_Dir_Right()) then
    show_details = not show_details
  end
end

local function draw_details(ctx, stats)
  draw_aligned_text(ctx, string.format("MIDI: %d",  stats.type_count.midi))
  draw_aligned_text(ctx, string.format("Audio: %d", stats.type_count.audio))
  draw_aligned_text(ctx, string.format("Empty: %d", stats.type_count.empty))

  reaper.ImGui_Dummy(ctx, 0, 5)
  draw_aligned_label(ctx, "Channel Count:", white)

  local ch_list = {}
  for ch, count in pairs(stats.channel_count) do
    ch_list[#ch_list+1] = { ch = ch, count = count }
  end
  table.sort(ch_list, function(a, b) return a.ch < b.ch end)

  for _, entry in ipairs(ch_list) do
    local label = (entry.ch == 1 and "Mono") or (entry.ch == 2 and "Stereo") or (entry.ch .. "-Ch")
    draw_aligned_text(ctx, string.format("%s: %d", label, entry.count))
  end
end

-------------------------------------------
-- Main loop
-------------------------------------------
local function need_heavy_rescan(now)
  -- 依 selection 指紋 + 專案版本 來決定是否要重掃
  local proj_ver    = reaper.GetProjectStateChangeCount(0) or 0
  local item_count  = reaper.CountSelectedMediaItems(0)
  local track_count = reaper.CountSelectedTracks(0)

  local changed = (proj_ver ~= last_proj_ver)
               or (item_count ~= last_item_count)
               or (track_count ~= last_track_count)

  -- 節流：距離上次允許時間之前，不做重掃
  if not changed or now < next_allowed_scan then
    return false
  end

  last_proj_ver    = proj_ver
  last_item_count  = item_count
  last_track_count = track_count
  next_allowed_scan = now + SCAN_INTERVAL
  return true
end

local function main_loop()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, initial_width, initial_height)
    first_frame = false
  end

  local visible, open = reaper.ImGui_Begin(ctx, 'Selection Monitor', true, window_flags)
  if visible then
    local now = reaper.time_precise()

    if show_details then
      if need_heavy_rescan(now) then
        scan_details_heavy()
      end
    else
      -- 純 Summary 路徑：每幀 O(1) 更新，不會做 per-item heavy scan
      scan_summary_only()
    end

    draw_summary_row(ctx, cached_stats)
    if show_details then
      draw_details(ctx, cached_stats)
    end

    -- 右鍵視窗快速關閉
    if reaper.ImGui_IsMouseClicked(ctx, 1) and reaper.ImGui_IsWindowHovered(ctx) then
      open = false
    end
  end
  reaper.ImGui_End(ctx)


  if open then
    reaper.defer(main_loop)
  else
    ctx = nil
  end
end

reaper.defer(main_loop)
