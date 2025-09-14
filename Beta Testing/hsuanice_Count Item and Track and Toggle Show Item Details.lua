--[[
@description ReaImGui - Count Items/Tracks (XR-style GUI, throttled details)
@version 0.3.1
@author hsuanice
@about
  Drop-in GUI refresh of the previous "Count Items/Tracks and Toggle Show Item Details" HUD.
  Functional behavior is unchanged; UI now follows the shared XR-style stack:
    - Shared theme via library: "hsuanice_ReaImGui Theme Color.lua" (applied each frame)
    - 16pt sans-serif font, no title bar, compact auto-resize HUD
    - Right-click inside window to close; warns once if theme lib is missing, then continues
  Performance safeguards are preserved:
    - Summary path is O(1) per frame (no per-item walks)
    - Details scan is throttled (debounced) and runs only when panel expanded AND selection changed


@changelog
  v0.3.1 (2025-09-14)
    - Fix: Guarded Begin/End pairing during docking/undocking and project switching
    - Fix: Theme push/pop balanced, preventing "PushStyleColor/PopStyleColor Mismatch" assertions

  v0.3.0 (2025-09-14)
    - New: XR-style GUI with shared color theme + 16pt font (warn once if theme lib missing)
    - Keep: Same counting logic and throttled details scanning as prior version
    - Fix: Always End() after Begin(), mirroring stability guard in 0.2.0.1
--]]

-------------------------------------------
-- User options
-------------------------------------------
local ALIGN_MODE     = "left"   -- "left" | "center" | "right"
local INITIAL_WIDTH  = 260
local INITIAL_HEIGHT = 64
local SCAN_INTERVAL  = 0.15      -- seconds, throttle heavy scans (unchanged)
-------------------------------------------

-- ReaImGui context
local ctx = reaper.ImGui_CreateContext('Count Items/Tracks HUD')

-- Fonts (XR-style: single readable 16pt)
local FONT_MAIN = reaper.ImGui_CreateFont('sans-serif', 16)
reaper.ImGui_Attach(ctx, FONT_MAIN)

-- Window flags (XR-style)
local window_flags =
    reaper.ImGui_WindowFlags_NoTitleBar()
  | reaper.ImGui_WindowFlags_NoCollapse()
  | reaper.ImGui_WindowFlags_NoResize()
  | reaper.ImGui_WindowFlags_AlwaysAutoResize()

-- Theme library (shared colors)
local THEME_OK, WARNED_ONCE = false, false
local apply_theme, pop_theme, push_title, pop_title

-- ImGui shim (works with both namespaced and underscore APIs)
local IM = rawget(reaper, 'ImGui') or {}
if not IM.PushStyleColor then function IM.PushStyleColor(ctx, idx, col) reaper.ImGui_PushStyleColor(ctx, idx, col) end end
if not IM.PopStyleColor  then function IM.PopStyleColor (ctx, n)   reaper.ImGui_PopStyleColor (ctx, n or 1) end end
IM.Col_Text = IM.Col_Text or (reaper.ImGui_Col_Text and reaper.ImGui_Col_Text())

do
  local theme_path = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/hsuanice_ReaImGui Theme Color.lua'
  local env = setmetatable({ reaper = reaper }, { __index = _G })
  local chunk = loadfile(theme_path, 'bt', env)
  if chunk then
    local ok, M = pcall(chunk)
    if ok and type(M) == 'table' then
      apply_theme = function(ctx) M.apply(ctx, IM) end
      pop_theme   = function(ctx) M.pop(ctx, IM) end
      push_title  = function(ctx) if M.push_title_text then M.push_title_text(ctx, IM) end end
      pop_title   = function(ctx) if M.pop_title_text  then M.pop_title_text (ctx, IM) end end
      THEME_OK = true
    end
  end
  if not THEME_OK then
    apply_theme = function(_) end
    pop_theme   = function(_) end
    push_title  = function(_) end
    pop_title   = function(_) end
  end
end

-- State
local show_details   = false
local first_frame    = true
local white          = 0xFFFFFFFF

-- caches / debounce
local last_proj_ver      = -1
local last_item_count    = -1
local last_track_count   = -1
local next_allowed_scan  = 0.0
local cached_stats       = {
  item_count    = 0,
  track_count   = 0,
  type_count    = { midi = 0, audio = 0, empty = 0 },
  channel_count = {}
}

-------------------------------------------
-- Small helpers
-------------------------------------------
local function calc_text_w(text)
  local w = select(1, reaper.ImGui_CalcTextSize(ctx, text))
  return w or 0
end

local function win_w()
  local w = select(1, reaper.ImGui_GetWindowSize(ctx))
  return w or 0
end

local function aligned_text(text, color)
  local width = calc_text_w(text)
  local ww = win_w()
  if ALIGN_MODE == 'center' then
    reaper.ImGui_SetCursorPosX(ctx, (ww - width) / 2)
  elseif ALIGN_MODE == 'right' then
    reaper.ImGui_SetCursorPosX(ctx, ww - width - 10)
  end
  if color then
    reaper.ImGui_TextColored(ctx, color, text)
  else
    reaper.ImGui_Text(ctx, text)
  end
end

-------------------------------------------
-- Scanners (unchanged behavior)
-------------------------------------------
local function scan_summary_only()
  cached_stats.item_count  = reaper.CountSelectedMediaItems(0)
  cached_stats.track_count = reaper.CountSelectedTracks(0)
end

local function scan_details_heavy()
  local item_count  = reaper.CountSelectedMediaItems(0)
  local track_count = reaper.CountSelectedTracks(0)

  local type_count    = { midi = 0, audio = 0, empty = 0 }
  local channel_count = {}

  for i = 0, item_count - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if not take then
      type_count.empty = type_count.empty + 1
    else
      local src     = reaper.GetMediaItemTake_Source(take)
      local srctype = reaper.GetMediaSourceType(src, '')
      if srctype == 'MIDI' or srctype == 'REX' then
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
-- UI draw
-------------------------------------------
local function draw_summary_row()
  local s = string.format('Items: %d    Tracks: %d', cached_stats.item_count, cached_stats.track_count)
  local sw = calc_text_w(s)
  local ww = win_w()
  if ALIGN_MODE == 'center' then
    reaper.ImGui_SetCursorPosX(ctx, (ww - sw) / 2 - 20)
  elseif ALIGN_MODE == 'right' then
    reaper.ImGui_SetCursorPosX(ctx, ww - sw - 40)
  end
  reaper.ImGui_Text(ctx, s)
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_ArrowButton(ctx, 'details_toggle', show_details and reaper.ImGui_Dir_Down() or reaper.ImGui_Dir_Right()) then
    show_details = not show_details
  end
end

local function draw_details()
  aligned_text(string.format('MIDI: %d',  cached_stats.type_count.midi))
  aligned_text(string.format('Audio: %d', cached_stats.type_count.audio))
  aligned_text(string.format('Empty: %d', cached_stats.type_count.empty))

  reaper.ImGui_Dummy(ctx, 0, 5)
  aligned_text('Channel Count:', white)

  local ch_list = {}
  for ch, count in pairs(cached_stats.channel_count) do
    ch_list[#ch_list+1] = { ch = ch, count = count }
  end
  table.sort(ch_list, function(a, b) return a.ch < b.ch end)
  for _, e in ipairs(ch_list) do
    local label = (e.ch == 1 and 'Mono') or (e.ch == 2 and 'Stereo') or (e.ch .. '-Ch')
    aligned_text(string.format('%s: %d', label, e.count))
  end
end

-------------------------------------------
-- Throttle gate
-------------------------------------------
local function need_heavy_rescan(now)
  local proj_ver    = reaper.GetProjectStateChangeCount(0) or 0
  local item_count  = reaper.CountSelectedMediaItems(0)
  local track_count = reaper.CountSelectedTracks(0)

  local changed = (proj_ver ~= last_proj_ver)
               or (item_count ~= last_item_count)
               or (track_count ~= last_track_count)

  if not changed or now < next_allowed_scan then
    return false
  end

  last_proj_ver     = proj_ver
  last_item_count   = item_count
  last_track_count  = track_count
  next_allowed_scan = now + SCAN_INTERVAL
  return true
end

-------------------------------------------
-- Main loop
-------------------------------------------
local function main()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, INITIAL_WIDTH, INITIAL_HEIGHT)
    first_frame = false
  end

  local visible, open
  reaper.ImGui_PushFont(ctx, FONT_MAIN)
  apply_theme(ctx)

  visible, open = reaper.ImGui_Begin(ctx, 'Selection Monitor', true, window_flags)
  if visible then
    if not THEME_OK and not WARNED_ONCE then
      reaper.ImGui_TextColored(ctx, 0xFFAAAAFF, 'Theme lib not found: hsuanice_ReaImGui Theme Color.lua')
      WARNED_ONCE = true
    end

    local now = reaper.time_precise()
    if show_details then
      if need_heavy_rescan(now) then
        scan_details_heavy()
      end
    else
      scan_summary_only()
    end

    draw_summary_row()
    if show_details then draw_details() end

    if reaper.ImGui_IsMouseClicked(ctx, 1) and reaper.ImGui_IsWindowHovered(ctx) then
      open = false
    end

    reaper.ImGui_End(ctx)   -- ✅ 只在 visible=true 時呼叫
  else
    -- 如果 Begin 失敗，不呼叫 End
  end

  pop_theme(ctx)
  reaper.ImGui_PopFont(ctx)


  if open then
    reaper.defer(main)
  end
end

reaper.defer(main)
