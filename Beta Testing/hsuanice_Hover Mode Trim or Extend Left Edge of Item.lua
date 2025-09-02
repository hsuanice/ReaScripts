--[[
@description Hover Mode - Trim or Extend Left Edge of Item (Preserve Fade)
@version 0.2.0
@author hsuanice
@about
  Trims or extends the **left edge** of audio/MIDI/empty items depending on context.  
    - Hover Mode ON: Uses mouse cursor position.  
    - Hover Mode OFF: Uses edit cursor and selected tracks.  
    - 🧠 Special behavior: When the mouse is hovering over the **Ruler (Timeline)** or **TCP area**,  
      the script temporarily switches to **Edit Cursor Mode**, even if Hover Mode is enabled.  
    - Preserves existing fade-in shape and position.  
    - Ignores invisible items; partial visibility is accepted.
  
    💡 Supports extensible hover-edit system. Hover Mode is toggled via ExtState:  
      hsuanice_TrimTools / HoverMode  
  
    Inspired by:
      • X-Raym: Trim Item Edges — Script: X-Raym_Trim left edge of item under mouse or the next one to mouse cursor without changing fade-in end.lua
  
  Features:
  - Designed for fast, keyboard-light workflows.
  - Supports Hover Mode via shared ExtState for cursor-aware actions.
  - Uses SWS extension APIs where available.
  - Optionally leverages js_ReaScriptAPI for advanced interactions.
  
  References:
  - REAPER ReaScript API (Lua)
  - SWS Extension API
  - js_ReaScriptAPI
  
  Note:
  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.
  hsuanice served as the workflow designer, tester, and integrator for this tool.

@changelog
  v0.2.0
    - Added: TCP area behaves like Ruler — temporarily forces Edit Cursor Mode even if Hover Mode is ON.
  v0.1.2
    - Boundary-as-gap policy in Hover mode: when mouse ≈ item edge (± half-pixel), treat UNDER as empty.
      A now consistently EXTENDS the nearest Next-left-edge to mouse in gaps or on boundaries; no trim at edges.
    - Pixel hit at an edge is ignored (falls back to gap handling) to avoid accidental trims.
  v0.1.1
    - Edge-aware boundary resolution with zoom-adaptive half-pixel epsilon (GetHZoomLevel).
    - Pixel-accurate hit using GetItemFromPoint; time-based fallback; SWS helpers when available.
    - Prevents extending the Next item / XFADE when pressing Left repeatedly at a boundary.
    - Preserves fade-in end; respects Hover/Ruler behavior and snap in true hover.
    - Comments rewritten in English.
  v0.1
    - Beta release
--]]

----------------------------------------
-- Config
----------------------------------------
local EXT_NS        = "hsuanice_TrimTools"
local EXT_HOVER_KEY = "HoverMode"

-- epsilon = half a pixel in seconds (zoom-adaptive)
local function half_pixel_sec()
  local pps = reaper.GetHZoomLevel() or 100.0 -- pixels per second
  if pps <= 0 then pps = 100.0 end
  return 0.5 / pps
end

----------------------------------------
-- Small utilities
----------------------------------------
local function is_hover_enabled()
  local v = reaper.GetExtState(EXT_NS, EXT_HOVER_KEY)
  return (v == "true" or v == "1")
end

local function is_mouse_over_ruler_or_tcp()
  if not reaper.JS_Window_FromPoint then return false end
  local x, y = reaper.GetMousePosition()
  local hwnd = reaper.JS_Window_FromPoint(x, y)
  if not hwnd then return false end
  local class = reaper.JS_Window_GetClassName(hwnd)
  return (class == "REAPERTimeDisplay" or class == "REAPERTCPDisplay")
end

local function mouse_timeline_pos()
  if reaper.BR_GetMouseCursorContext_Position then
    reaper.BR_GetMouseCursorContext() -- refresh SWS mouse context
    return reaper.BR_GetMouseCursorContext_Position()
  end
  if reaper.BR_PositionAtMouseCursor then
    return reaper.BR_PositionAtMouseCursor(true)
  end
  return nil
end

local function ensure_visible(item)
  local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local right = pos + len
  local vstart, vend = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  return (right >= vstart and pos <= vend)
end

----------------------------------------
-- Fade preserving (keep fade end time)
----------------------------------------
local function preserve_fade_in(item, old_start, new_start)
  local fade_len = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
  if fade_len <= 0 then
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
    return
  end
  local fade_end = old_start + fade_len
  local new_len = math.max(0, fade_end - new_start)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", new_len)
end

----------------------------------------
-- Find targets (Edit-Cursor mode)
--  • If cursor is inside the item (strictly away from edges): TRIM.
--  • Else: EXTEND the nearest item to the right.
----------------------------------------
local function find_items_edit_mode(tracks)
  local pos = reaper.GetCursorPosition()
  local eps = half_pixel_sec()
  local picks = {}

  for _, tr in ipairs(tracks) do
    local inside, extend_target = nil, nil
    local best_right = math.huge

    local n = reaper.CountTrackMediaItems(tr)
    for i = 0, n - 1 do
      local it = reaper.GetTrackMediaItem(tr, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")

      local inside_open = (pos > st + eps and pos < en - eps)

      if inside_open then
        inside = it; break
      elseif st >= pos and st < best_right then
        extend_target = it; best_right = st
      end
    end

    if inside then
      table.insert(picks, { item = inside, mode = "trim" })
    elseif extend_target then
      table.insert(picks, { item = extend_target, mode = "extend" })
    end
  end

  return pos, picks
end

----------------------------------------
-- Find targets (Hover mode, mouse-based, SINGLE track)
--  Boundary-as-gap policy:
--   - If mouse is within ±ε of any item edge, treat UNDER as empty (no trim).
--   - A (Left tool) in gap/boundary → EXTEND the nearest Next (start >= mouse).
--   - Only when mouse is strictly inside an item do we TRIM its left edge.
----------------------------------------
local function find_items_hover_mode()
  local x, y = reaper.GetMousePosition()
  local pos = mouse_timeline_pos()
  if not pos then return pos, {} end

  local tr = reaper.GetTrackFromPoint(x, y)
  if not tr then return pos, {} end

  local eps = half_pixel_sec()

  -- 1) Pixel hit — ignore if at boundary (treat as gap)
  local hit = reaper.GetItemFromPoint(x, y, false)
  if hit and reaper.GetMediaItem_Track(hit) == tr then
    local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
    local near_left  = math.abs(pos - st) <= eps
    local near_right = math.abs(pos - en) <= eps
    if not (near_left or near_right) then
      -- strictly inside → trim
      if pos > st + eps and pos < en - eps then
        return pos, { { item = hit, mode = "trim" } }
      end
    end
    -- else: boundary → fallthrough to gap handling
  end

  -- 2) Time-based scan (boundary treated as gap)
  local inside, extend_target = nil, nil
  local best_right = math.huge

  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")

    local inside_open = (pos > st + eps and pos < en - eps)

    if inside_open then
      inside = it; break
    elseif st >= pos and st < best_right then
      extend_target = it; best_right = st
    end
  end

  if inside then
    return pos, { { item = inside, mode = "trim" } }
  elseif extend_target then
    return pos, { { item = extend_target, mode = "extend" } }
  else
    return pos, {}
  end
end

----------------------------------------
-- Apply: Trim/Extend LEFT edge to target_pos (preserve fade end)
----------------------------------------
local function apply_left_edge(entry, target_pos)
  local it = entry.item
  if not ensure_visible(it) then return end

  local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local ln = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local en = st + ln
  if target_pos >= en - 1e-6 then return end -- ignore degenerate

  local take = reaper.GetActiveTake(it)
  local is_midi = take and reaper.TakeIsMIDI(take)
  local is_empty = not take

  -- earliest allowed start (audio limited by source offset)
  local max_left
  if (not is_empty) and (not is_midi) then
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    max_left = st - offs
  else
    max_left = -math.huge
  end

  local new_st = math.min(math.max(target_pos, max_left), en - 1e-6)
  if math.abs(new_st - st) < 1e-9 then return end -- no-op

  local new_ln = en - new_st

  -- adjust source start offset for audio
  if (not is_empty) and (not is_midi) then
    local offs  = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local rate  = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    local d_src = (new_st - st) * (rate > 0 and rate or 1.0)
    local new_offs = math.max(0, offs + d_src)
    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offs)
  end

  reaper.SetMediaItemInfo_Value(it, "D_POSITION", new_st)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",  new_ln)
  preserve_fade_in(it, st, new_st)
end

----------------------------------------
-- Main
----------------------------------------
local function get_selected_tracks()
  local t = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    t[#t+1] = reaper.GetSelectedTrack(0, i)
  end
  return t
end

local hover_on = is_hover_enabled()
local target_pos, picks
local from_ruler = false

if hover_on then
  if is_mouse_over_ruler_or_tcp() then
    target_pos, picks = find_items_edit_mode(get_selected_tracks())
    from_ruler = true
  else
    target_pos, picks = find_items_hover_mode()
  end
else
  target_pos, picks = find_items_edit_mode(get_selected_tracks())
end

-- Snap only in true hover-with-mouse (not when using the Ruler/EditCursor)
if hover_on and not from_ruler and reaper.GetToggleCommandState(1157) == 1 then
  target_pos = reaper.SnapToGrid(0, target_pos)
end

if not target_pos or #picks == 0 then return end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
for _, entry in ipairs(picks) do
  apply_left_edge(entry, target_pos)
end
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Trim or extend item left edge (hover/edit mode)", -1)
