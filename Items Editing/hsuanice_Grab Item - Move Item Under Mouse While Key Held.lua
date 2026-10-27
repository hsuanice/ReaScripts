--[[
@description Grab Item - Move Item Under Mouse While Key Held (hold the shortcut to drag one item, Snap aware, Cmd inverts Snap)
@version 26.1027.1547
@author hsuanice
@changelog
  - Release: tested in REAPER.
@provides
  [main] .
  [main] hsuanice_Grab Item - Move Item Under Mouse Vertically While Key Held.lua
@about
  # Grab Item

  Move one item without selecting it first: hold the shortcut with the mouse over an item,
  move the mouse, release the shortcut to drop the item. Item selection is left as it is,
  and only the item under the mouse moves (even when other items are selected).

  - Move Item Under Mouse While Key Held: the item follows the mouse in time and across
    tracks. The item start (or its snap offset) follows Snap; hold Cmd (Ctrl on Windows)
    while dragging to invert Snap: free movement when Snap is on, grid snapping when it is off.
  - Move Item Under Mouse Vertically While Key Held: the item only changes track and keeps
    its timeline position (Snap does not apply).

  While dragging:
  - Below the last track, a new track is added for the item (removed again when the mouse
    goes back up).
  - Esc cancels: the item goes back to where it was.
  - On release, existing items on the destination track under the dropped item are trimmed
    away, like REAPER's "Trim content behind media items" (locked items are left alone).
    One undo point.

  Locked items are not grabbed. Requires js_ReaScriptAPI (key hold detection) and SWS
  (mouse position).

  ## Suggested shortcuts
  None: pick any key that is free in your setup. Shortcuts are suggestions only — nothing is
  assigned automatically.

  Hold-the-shortcut detection follows Sexan's "VT_SWIPE to Comp HOLD" (Virtual Track,
  Sexan_Scripts). Designed and tested by hsuanice; written with AI (Claude Code).
--]]
local r = reaper
-- the vertical-only script sets this global before loading this file
local VERTICAL = GRAB_ITEM_VERTICAL == true
GRAB_ITEM_VERTICAL = nil
local TITLE = VERTICAL and "Grab Item - Move Item Vertically" or "Grab Item - Move Item"

if not (r.JS_VKeys_GetState and r.JS_VKeys_Intercept and r.BR_GetMouseCursorContext) then
  r.MB("This script needs js_ReaScriptAPI and SWS.\n\n"
    .. "Please install them with ReaPack (Extensions > ReaPack > Browse packages).", TITLE, 0)
  return
end

-- on: true / false forces snapping on or off (same as Fade Tool - Smart Fade)
local function snap(t, on)
  local project_on = r.GetToggleCommandState(1157) == 1
  if t and on then
    if not project_on and r.BR_GetClosestGridDivision then return r.BR_GetClosestGridDivision(t) end
    return r.SnapToGrid(0, t)
  end
  return t
end

-- Cmd (macOS) / Ctrl (Windows) held right now
local function cmd_down()
  return (r.JS_Mouse_GetState(4) & 4) == 4
end

local function mouse_time()
  local t = r.BR_PositionAtMouseCursor(false)
  if t and t >= 0 then return t end
  return nil
end

-- Track under the mouse, "below" for the empty space under the last track, else nil
local function mouse_track()
  local x, y = r.GetMousePosition()
  local tr = r.GetTrackFromPoint(x, y)
  if tr then
    if tr == r.GetMasterTrack(0) then return nil end
    return tr
  end
  local win, seg = r.BR_GetMouseCursorContext()
  if (win == "arrange" or win == "tcp") and seg == "empty" then return "below" end
  return nil
end

-- Remove the parts of other items on the item's track that lie under it. All cuts go through
-- SplitMediaItem so the kept pieces keep their source alignment (as in Move Selected Items to
-- Track Under Mouse, Overwrite).
local function trim_behind(item)
  local tr = r.GetMediaItem_Track(item)
  local mv_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local mv_end = mv_pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local existing = {}
  for i = 0, r.CountTrackMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, i)
    if it ~= item and (r.GetMediaItemInfo_Value(it, "C_LOCK") & 1) == 0 then
      existing[#existing + 1] = it
    end
  end
  for _, ex in ipairs(existing) do
    local exp = r.GetMediaItemInfo_Value(ex, "D_POSITION")
    local exe = exp + r.GetMediaItemInfo_Value(ex, "D_LENGTH")
    if mv_pos < exe and exp < mv_end then
      local mid = ex
      if exp < mv_pos then mid = r.SplitMediaItem(ex, mv_pos) end
      if mid then
        if exe > mv_end then r.SplitMediaItem(mid, mv_end) end
        r.DeleteTrackMediaItem(tr, mid)
      end
    end
  end
end

-- Hold-and-drag: follow the mouse until every key is released (pattern from Sexan's
-- "VT_SWIPE to Comp HOLD": JS_VKeys state since launch, keys intercepted meanwhile)
local VK_LO, VK_HI, VK_ESC = 8, 0xFE, 0x1B
-- Modifier keys do not keep a drag alive: Shift, Ctrl, Alt, Win (left / right variants)
local VK_MOD = { [0x10] = true, [0x11] = true, [0x12] = true, [0x5B] = true, [0x5C] = true,
  [0xA0] = true, [0xA1] = true, [0xA2] = true, [0xA3] = true, [0xA4] = true, [0xA5] = true }
local CMD_GRACE = 0.2  -- Cmd released this short before the shortcut keeps the free position

local function hold(item)
  local start = r.time_precise()
  local src_tr = r.GetMediaItem_Track(item)
  local pos0 = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local snapoffs = r.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
  local t0 = mouse_time()
  local new_tr = nil  -- track added below the last track while dragging
  local intercepted = true
  local project_snap = r.GetToggleCommandState(1157) == 1
  local cmd0 = cmd_down()  -- Cmd that is part of the shortcut itself does not count
  local inverted, cmd_up_at = false, nil

  local function release_keys()
    if intercepted then intercepted = false; r.JS_VKeys_Intercept(-1, -1) end
  end
  local function drop_new_track()
    if new_tr and r.ValidatePtr(new_tr, "MediaTrack*") and r.GetMediaItem_Track(item) ~= new_tr then
      r.DeleteTrack(new_tr)
    end
    new_tr = nil
  end
  local function move_to(tr)
    if r.GetMediaItem_Track(item) ~= tr then r.MoveMediaItemToTrack(item, tr) end
  end
  local function changed()
    return r.GetMediaItem_Track(item) ~= src_tr
      or math.abs(r.GetMediaItemInfo_Value(item, "D_POSITION") - pos0) > 1e-9
  end
  r.JS_VKeys_Intercept(-1, 1)
  r.atexit(release_keys)

  local function step()
    local st = r.JS_VKeys_GetState(start - 0.5)
    -- Esc: put the item back, no undo point
    if st:byte(VK_ESC) ~= 0 then
      release_keys()
      r.PreventUIRefresh(1)
      move_to(src_tr)
      r.SetMediaItemInfo_Value(item, "D_POSITION", pos0)
      drop_new_track()
      r.PreventUIRefresh(-1)
      r.UpdateArrange()
      return
    end
    -- releasing the shortcut drops the item where it is
    local held = false
    for vk = VK_LO, VK_HI do
      if not VK_MOD[vk] and st:byte(vk) ~= 0 then held = true break end
    end
    if not held then
      release_keys()
      if changed() then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        trim_behind(item)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
        r.Undo_EndBlock(TITLE, -1)
      end
      return
    end

    r.PreventUIRefresh(1)
    local tr = mouse_track()
    if tr == "below" then
      if not new_tr then
        r.InsertTrackAtIndex(r.CountTracks(0), true)
        new_tr = r.GetTrack(0, r.CountTracks(0) - 1)
      end
      tr = new_tr
    end
    if tr then
      move_to(tr)
      if tr ~= new_tr then drop_new_track() end
    end

    if not VERTICAL then
      -- Cmd / Ctrl inverts Snap (snap on -> free, snap off -> grid); after Cmd is
      -- released the snap comes back only once CMD_GRACE has passed
      local now = r.time_precise()
      if cmd_down() ~= cmd0 then
        inverted, cmd_up_at = true, nil
      elseif inverted then
        cmd_up_at = cmd_up_at or now
        if now - cmd_up_at >= CMD_GRACE then inverted = false end
      end
      local t = mouse_time()
      if t and t0 then
        local p = snap(pos0 + (t - t0) + snapoffs, project_snap ~= inverted) - snapoffs
        p = math.max(p, 0)
        if math.abs(p - r.GetMediaItemInfo_Value(item, "D_POSITION")) > 1e-9 then
          r.SetMediaItemInfo_Value(item, "D_POSITION", p)
        end
      end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.defer(step)
  end
  step()
end

local x, y = r.GetMousePosition()
local item = r.GetItemFromPoint(x, y, false)  -- false: locked items are not grabbed
if item then hold(item) end
