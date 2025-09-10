--[[
@description hsuanice Hover Library (Shared helpers for Hover Mode editing tools)
@version 0.1.0
@author hsuanice
@about
  Common utilities for Hover Mode scripts (Split / Trim / Extend).
  Centralizes hover/edit cursor decision, snap behavior, pixel epsilon,
  and target item selection (hover, edit, or selection priority).
  
  Path: REAPER/Scripts/hsuanice Scripts/Library/hsuanice_Hover.lua
@changelog
  v0.1.0 - Initial skeleton:
    • Unified function naming (is_/build_/resolve_/apply_ separation).
    • Provides hover state, ruler detection, mouse timeline pos,
      snap-in-hover, half-pixel epsilon, item visibility.
    • Target builders for Split and Trim/Extend.
--]]

local M = {}

----------------------------------------
-- Config
----------------------------------------
M.EXT_NS        = "hsuanice_TrimTools"
M.EXT_HOVER_KEY = "HoverMode"

----------------------------------------
-- Basic state & geometry
----------------------------------------

-- Check if Hover Mode is enabled via ExtState
function M.is_hover_enabled()
  local v = reaper.GetExtState(M.EXT_NS, M.EXT_HOVER_KEY)
  return (v == "true" or v == "1")
end

-- Check if mouse is over Ruler or TCP (forces Edit Cursor mode)
function M.is_mouse_over_ruler_or_tcp()
  if not reaper.JS_Window_FromPoint then return false end
  local x, y = reaper.GetMousePosition()
  local hwnd = reaper.JS_Window_FromPoint(x, y)
  if not hwnd then return false end
  local class = reaper.JS_Window_GetClassName(hwnd)
  return (class == "REAPERTimeDisplay" or class == "REAPERTCPDisplay")
end

-- Timeline position under mouse (SWS preferred)
function M.mouse_timeline_pos()
  if reaper.BR_GetMouseCursorContext_Position then
    reaper.BR_GetMouseCursorContext()
    return reaper.BR_GetMouseCursorContext_Position()
  end
  if reaper.BR_PositionAtMouseCursor then
    return reaper.BR_PositionAtMouseCursor(true)
  end
  return nil
end

-- Half pixel in seconds (zoom adaptive)
function M.half_pixel_sec()
  local pps = reaper.GetHZoomLevel() or 100.0
  if pps <= 0 then pps = 100.0 end
  return 0.5 / pps
end

-- Check if item is visible in arrange view (partial ok)
function M.is_item_visible(item)
  local st = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local en = st + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
  local v0, v1 = reaper.GetSet_ArrangeView2(0, false, 0, 0)
  return (en >= v0 and st <= v1)
end

----------------------------------------
-- Position resolution & snap
----------------------------------------

-- Decide working position (pos, is_true_hover)
-- • Hover ON + not ruler/tcp → mouse pos
-- • Else → edit cursor
function M.resolve_target_pos()
  if M.is_hover_enabled() and not M.is_mouse_over_ruler_or_tcp() then
    local pos = M.mouse_timeline_pos()
    return pos, true
  else
    return reaper.GetCursorPosition(), false
  end
end

-- Apply snap only in true hover mode
function M.snap_in_true_hover(pos, is_true_hover)
  if is_true_hover and reaper.GetToggleCommandState(1157) == 1 then
    return reaper.SnapToGrid(0, pos)
  end
  return pos
end

----------------------------------------
-- Target builders
----------------------------------------

-- Build target items for Split
--   opts: { prefer_selection_when_hover=true }
function M.build_targets_for_split(pos, opts)
  local items = {}
  local eps = M.half_pixel_sec()
  local prefer_sel = opts and opts.prefer_selection_when_hover

  if prefer_sel and reaper.CountSelectedMediaItems(0) > 0 and M.is_hover_enabled() then
    -- Use selection if it overlaps pos
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local it = reaper.GetSelectedMediaItem(0, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      if pos > st + eps and pos < en - eps then
        table.insert(items, it)
      end
    end
  else
    -- Single item under mouse
    local x, y = reaper.GetMousePosition()
    local hit = reaper.GetItemFromPoint(x, y, false)
    if hit then
      local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
      if pos > st + eps and pos < en - eps then
        table.insert(items, hit)
      end
    end
  end

  return items
end

-- Build picks for Trim/Extend
--   side = "left" or "right"
--   returns { {item=..., mode="trim|extend"}, ... }
function M.build_targets_for_trim_extend(side, pos, opts)
  local picks = {}
  local eps = M.half_pixel_sec()
  local prefer_sel = opts and opts.prefer_selection_when_hover

  if prefer_sel and reaper.CountSelectedMediaItems(0) > 0 and M.is_hover_enabled() then
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
      local it = reaper.GetSelectedMediaItem(0, i)
      local st = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local inside = (pos > st + eps and pos < en - eps)

      if side == "left" then
        if inside then
          table.insert(picks, { item = it, mode = "trim" })
        elseif st >= pos then
          table.insert(picks, { item = it, mode = "extend" })
        end
      elseif side == "right" then
        if inside then
          table.insert(picks, { item = it, mode = "trim" })
        elseif en <= pos then
          table.insert(picks, { item = it, mode = "extend" })
        end
      end
    end
  else
    -- Fallback: single item under mouse (hover) or edit cursor (handled outside)
    local x, y = reaper.GetMousePosition()
    local hit = reaper.GetItemFromPoint(x, y, false)
    if hit then
      local st = reaper.GetMediaItemInfo_Value(hit, "D_POSITION")
      local en = st + reaper.GetMediaItemInfo_Value(hit, "D_LENGTH")
      local inside = (pos > st + eps and pos < en - eps)
      if inside then
        table.insert(picks, { item = hit, mode = "trim" })
      elseif side == "left" and st >= pos then
        table.insert(picks, { item = hit, mode = "extend" })
      elseif side == "right" and en <= pos then
        table.insert(picks, { item = hit, mode = "extend" })
      end
    end
  end

  return picks
end

----------------------------------------
return M
