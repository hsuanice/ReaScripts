--[[
@description ReaImGui - Count Items/Tracks and Toggle Show Item Details
@version 0.1
@author hsuanice
@about
  A HUD for monitoring selected item and track counts, sorted by type and channel format.  
    - Displays counts of audio, MIDI, and empty items.  
    - Auto-resizes and updates in real time.  
    - Toggle detail view for channel summary (mono, stereo, multichannel).  
    - Right-click inside window to close instantly.
  
    💡 Designed for ReaImGui workflows with minimal screen space usage.  
      Integrates well with hsuanice’s HUD-based editing and selection tools.
  
    This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.  
    hsuanice served as the workflow designer, tester, and integrator for this tool.
  
  Features:
  - Built with ReaImGUI for a compact, responsive UI.
  - Designed for fast, keyboard-light workflows.
  
  References:
  - REAPER ReaScript API (Lua)
  - ReaImGUI (ReaScript ImGui binding)
  
  Note:
  - This is a 0.1 beta release for internal testing.
  
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v0.1 - Beta release
--]]
local align_mode = "left" 
local initial_width = 240
local initial_height = 60
-- -------------------------------------------

local ctx = reaper.ImGui_CreateContext('Selection Monitor Expand')
local window_flags =
    reaper.ImGui_WindowFlags_NoTitleBar() |
    reaper.ImGui_WindowFlags_NoCollapse() |
    reaper.ImGui_WindowFlags_NoResize() |
    reaper.ImGui_WindowFlags_AlwaysAutoResize()

local show_details = false
local white = 0xFFFFFFFF
local first_frame = true

local function draw_aligned_text(ctx, text)
  local width = reaper.ImGui_CalcTextSize(ctx, text)
  local win_width = reaper.ImGui_GetWindowSize(ctx)
  if align_mode == "center" then
    reaper.ImGui_SetCursorPosX(ctx, (win_width - width) / 2)
  elseif align_mode == "right" then
    reaper.ImGui_SetCursorPosX(ctx, win_width - width - 10)
  end
  reaper.ImGui_Text(ctx, text)
end

local function draw_aligned_label(ctx, text, color)
  local width = reaper.ImGui_CalcTextSize(ctx, text)
  local win_width = reaper.ImGui_GetWindowSize(ctx)
  if align_mode == "center" then
    reaper.ImGui_SetCursorPosX(ctx, (win_width - width) / 2)
  elseif align_mode == "right" then
    reaper.ImGui_SetCursorPosX(ctx, win_width - width - 10)
  end
  reaper.ImGui_TextColored(ctx, color or white, text)
end

local function analyze_selection()
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
      local ch = reaper.GetMediaSourceNumChannels(src)
      channel_count[ch] = (channel_count[ch] or 0) + 1
    end
  end

  return {
    item_count = item_count,
    track_count = track_count,
    type_count = type_count,
    channel_count = channel_count
  }
end

local function draw_summary_row(ctx, stats)
  local summary = string.format("Items: %d    Tracks: %d", stats.item_count, stats.track_count)
  local summary_width = reaper.ImGui_CalcTextSize(ctx, summary)
  local win_width = reaper.ImGui_GetWindowSize(ctx)

  if align_mode == "center" then
    reaper.ImGui_SetCursorPosX(ctx, (win_width - summary_width) / 2 - 20)
  elseif align_mode == "right" then
    reaper.ImGui_SetCursorPosX(ctx, win_width - summary_width - 40)
  end

  reaper.ImGui_Text(ctx, summary)
  reaper.ImGui_SameLine(ctx)

  if reaper.ImGui_ArrowButton(ctx, "details_toggle", show_details and reaper.ImGui_Dir_Down() or reaper.ImGui_Dir_Right()) then
    show_details = not show_details
  end
end

local function draw_details(ctx, stats)
  draw_aligned_text(ctx, string.format("MIDI: %d", stats.type_count.midi))
  draw_aligned_text(ctx, string.format("Audio: %d", stats.type_count.audio))
  draw_aligned_text(ctx, string.format("Empty: %d", stats.type_count.empty))

  reaper.ImGui_Dummy(ctx, 0, 5)

  draw_aligned_label(ctx, "Channel Count:", white)

  local ch_list = {}
  for ch, count in pairs(stats.channel_count) do
    table.insert(ch_list, { ch = ch, count = count })
  end
  table.sort(ch_list, function(a, b) return a.ch < b.ch end)

  for _, entry in ipairs(ch_list) do
    local label = (entry.ch == 1 and "Mono") or (entry.ch == 2 and "Stereo") or (entry.ch .. "-Ch")
    draw_aligned_text(ctx, string.format("%s: %d", label, entry.count))
  end
end

local function main_loop()
  if first_frame then
    reaper.ImGui_SetNextWindowSize(ctx, initial_width, initial_height)
    first_frame = false
  end

  local visible, open = reaper.ImGui_Begin(ctx, 'Selection Monitor', true, window_flags)
  if visible then
    local stats = analyze_selection()
    draw_summary_row(ctx, stats)
    if show_details then
      draw_details(ctx, stats)
    end

    
    if reaper.ImGui_IsMouseClicked(ctx, 1) and reaper.ImGui_IsWindowHovered(ctx) then
      open = false
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(main_loop)
  else
    ctx = nil 
  end
end

reaper.defer(main_loop)

