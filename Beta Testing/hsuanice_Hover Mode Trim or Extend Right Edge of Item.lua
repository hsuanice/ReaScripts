--[[
@description Hover Mode - Trim or Extend Right Edge of Item (Preserve Fade)
@version 0.1.2
@author hsuanice
@about
  Trims or extends the **right edge** of audio/MIDI/empty items depending on context.
    - Hover Mode ON : uses mouse timeline position (pixel-accurate hit test preferred).
    - Hover Mode OFF: uses edit cursor on selected tracks.
    - 🧠 Special behavior: when the mouse is over the **Ruler (Timeline)**, the script temporarily switches
      to **Edit Cursor Mode**, even if Hover Mode is enabled.
    - Preserves the existing fade-out end-time (keeps fade start), adjusting only its length.
    - Ignores fully invisible items; partial visibility is accepted.

    💡 Hover Mode is toggled via ExtState:
      hsuanice_TrimTools / HoverMode

  Notes:
    - Snap-to-grid is respected in true Hover mode (not when forced to Edit Cursor via Ruler).
    - Boundary-as-gap for RIGHT tool: if mouse ≈ any item edge (± half-pixel), treat UNDER as empty.
      S now consistently EXTENDS the nearest Prev-right-edge to mouse in gaps or on boundaries; no trim at edges.

  Inspired by:
    • X-Raym - Trim right edge under mouse or previous one without changing fade-out start.

@changelog
  v0.1.2
    - Boundary-as-gap policy in Hover mode identical to Left tool: edges never trim; S extends Prev to mouse.
    - Pixel hit at an edge is ignored to avoid accidental trims; only strictly-inside hits trim.
  v0.1.1
    - Edge-aware boundary resolution with zoom-adaptive half-pixel epsilon (GetHZoomLevel).
    - Pixel-accurate hit using GetItemFromPoint; time-based fallback; optional SWS mouse position.
    - Prevents accidentally extending the Next item/XFADE when pressing Right repeatedly at a boundary.
    - Preserves fade-out start; respects Hover/Ruler behavior and snap in true hover.
  v0.1
    - Beta release.
--]]

----------------------------------------
-- Config / helpers
----------------------------------------
local EXT_NS, EXT_HOVER_KEY = "hsuanice_TrimTools", "HoverMode"

local function half_pixel_sec()
  local pps = reaper.GetHZoomLevel() or 100.0 -- pixels per second
  if pps <= 0 then pps = 100.0 end
  return 0.5 / pps
end

local function is_hover_enabled()
  local v = reaper.GetExtState(EXT_NS, EXT_HOVER_KEY)
  return (v == "true" or v == "1")
end

local function mouse_over_ruler()
  if not reaper.JS_Window_FromPoint then return false end
  local x, y = reaper.GetMousePosition()
  local hwnd = reaper.JS_Window_FromPoint(x, y)
  return hwnd and reaper.JS_Window_GetClassName(hwnd) == "REAPERTimeDisplay"
end

local function mouse_timeline_pos()
  if reaper.BR_GetMouseCursorContext_Position then
    reaper.BR_GetMouseCursorContext()
    return reaper.BR_GetMouseCursorContext_Position()
  end
  if reaper.BR_PositionAtMouseCursor then
    return reaper.BR_PositionAtMouseCursor(true)
  end
  return nil
end

local function item_visible(item)
  local st = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local en = st + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local v0, v1 = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  return (en >= v0 and st <= v1)
end

----------------------------------------
-- Fade-out preservation: keep fade start time
----------------------------------------
local function preserve_fade_out(item, old_end, new_end)
  local fl = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
  if fl <= 0 then
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
    return
  end
  local fade_start = old_end - fl
  local new_len = math.max(0, new_end - fade_start)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", new_len)
end

----------------------------------------
-- Edit-cursor mode: per selected track
--  • strictly inside → TRIM
--  • otherwise       → EXTEND nearest left item (end ≤ pos)
----------------------------------------
local function find_items_edit_mode()
  local pos = reaper.GetCursorPosition()
  local eps = half_pixel_sec()
  local picks = {}

  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    local tr = reaper.GetSelectedTrack(0, i)
    local inside, extend_from = nil, nil
    local best_left_end = -math.huge

    local n = reaper.CountTrackMediaItems(tr)
    for j = 0, n - 1 do
      local it = reaper.GetTrackMediaItem(tr, j)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")

      local inside_open = (pos > st + eps and pos < en - eps)

      if inside_open then
        inside = it; break
      elseif en <= pos and en > best_left_end then
        extend_from = it; best_left_end = en
      end
    end

    if inside then
      picks[#picks+1] = { item = inside, mode = "trim" }
    elseif extend_from then
      picks[#picks+1] = { item = extend_from, mode = "extend" }
    end
  end

  return pos, picks
end

----------------------------------------
-- Hover mode (single track under mouse)
-- Boundary-as-gap:
--  1) If pixel-hit is at an edge (±ε), ignore the hit → treat as gap.
--  2) Only strictly-inside items trim; otherwise extend Prev (end ≤ mouse).
----------------------------------------
local function find_items_hover_mode()
  local x, y = reaper.GetMousePosition()
  local pos = mouse_timeline_pos()
  if not pos then return pos, {} end

  local tr = reaper.GetTrackFromPoint(x, y)
  if not tr then return pos, {} end

  local eps = half_pixel_sec()

  -- 1) Pixel-accurate hit, but ignore when near edges (boundary-as-gap)
  local hit = reaper.GetItemFromPoint(x, y, false)
  if hit and reaper.GetMediaItem_Track(hit) == tr then
    local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
    local near_left  = math.abs(pos - st) <= eps
    local near_right = math.abs(pos - en) <= eps
    if not (near_left or near_right) then
      -- strictly inside → TRIM
      if pos > st + eps and pos < en - eps then
        return pos, { { item = hit, mode = "trim" } }
      end
    end
    -- else: treat as gap
  end

  -- 2) Time-based with boundary-as-gap
  local inside, extend_from = nil, nil
  local best_left_end = -math.huge

  local n = reaper.CountTrackMediaItems(tr)
  for i = 0, n - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")

    local inside_open = (pos > st + eps and pos < en - eps)

    if inside_open then
      inside = it; break
    elseif en <= pos and en > best_left_end then
      extend_from = it; best_left_end = en
    end
  end

  if inside then
    return pos, { { item = inside, mode = "trim" } }
  elseif extend_from then
    return pos, { { item = extend_from, mode = "extend" } }
  else
    return pos, {}
  end
end

----------------------------------------
-- Apply: set right edge to target_pos (preserve fade start)
----------------------------------------
local function apply_right_edge(entry, target_pos)
  local it = entry.item
  if not item_visible(it) then return end

  local st  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
  local ln  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
  local en0 = st + ln

  local take = reaper.GetActiveTake(it)
  local is_midi = take and reaper.TakeIsMIDI(take)
  local is_empty = not take
  local loops = (reaper.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 1)

  -- compute max right end (non-loop audio cannot exceed source tail)
  local max_right = math.huge
  if take and (not is_midi) and (not loops) then
    local src = reaper.GetMediaItemTake_Source(take)
    local src_len, isQN = reaper.GetMediaSourceLength(src)
    if isQN then src_len = reaper.TimeMap_QNToTime(src_len) end
    local offs = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    max_right = st + math.max(0, (src_len - offs)) / (rate ~= 0 and rate or 1.0)
  end

  local new_en = math.min(target_pos, max_right)
  if new_en <= st + 1e-9 then new_en = st + 1e-9 end
  if math.abs(new_en - en0) < 1e-9 then return end -- no-op

  local new_ln = new_en - st
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH", new_ln)
  preserve_fade_out(it, en0, new_en)
end

----------------------------------------
-- Main
----------------------------------------
local hover_on = is_hover_enabled()
local target_pos, picks
local forced_cursor = false

if hover_on then
  if mouse_over_ruler() then
    target_pos, picks = find_items_edit_mode()
    forced_cursor = true
  else
    target_pos, picks = find_items_hover_mode()
  end
else
  target_pos, picks = find_items_edit_mode()
end

-- Snap only in true hover-with-mouse
if hover_on and (not forced_cursor) and reaper.GetToggleCommandState(1157) == 1 then
  target_pos = reaper.SnapToGrid(0, target_pos)
end

if not target_pos or #picks == 0 then return end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
for _, entry in ipairs(picks) do
  apply_right_edge(entry, target_pos)
end
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock("Trim or extend item right edge (hover/edit mode)", -1)
