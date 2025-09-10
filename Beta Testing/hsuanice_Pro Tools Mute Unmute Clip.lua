-- @description Pro Tools-style Item Mute/Unmute Toggle (uniformize mixed -> unmute)
-- @version 0.1.0
-- @author hsuanice
-- @about
--   Single item = normal toggle.
--   Multiple items:
--     - mixed mute states -> unify to UNMUTE
--     - uniform state     -> toggle all
-- @changelog
--   0.1.0 - Initial release: mixed selection becomes unmute; uniform selection toggles.

local r = reaper

local function get_selected_items()
  local t = {}
  local proj = 0
  local cnt = r.CountSelectedMediaItems(proj)
  for i = 0, cnt-1 do
    t[#t+1] = r.GetSelectedMediaItem(proj, i)
  end
  return t
end

local function is_item_muted(item)
  -- B_MUTE: bool (1 muted / 0 not muted)
  return r.GetMediaItemInfo_Value(item, "B_MUTE") > 0.5
end

local function set_item_muted(item, muted)
  -- Setting B_MUTE will also clear C_MUTE_SOLO per API behavior.
  r.SetMediaItemInfo_Value(item, "B_MUTE", muted and 1 or 0)
end

local function main()
  local items = get_selected_items()
  if #items == 0 then return end

  local muted_count, unmuted_count = 0, 0
  for _, it in ipairs(items) do
    if is_item_muted(it) then
      muted_count = muted_count + 1
    else
      unmuted_count = unmuted_count + 1
    end
  end

  local desc = "Item Mute Toggle (uniformize mixed->unmute)"
  r.Undo_BeginBlock()

  if #items == 1 then
    -- Single item: regular toggle
    local it = items[1]
    local target = not is_item_muted(it)
    set_item_muted(it, target)
  else
    if muted_count > 0 and unmuted_count > 0 then
      -- Mixed states: unify to UNMUTE
      for _, it in ipairs(items) do
        set_item_muted(it, false)
      end
    else
      -- Uniform: toggle all
      local currently_muted = (muted_count == #items)
      local target = not currently_muted
      for _, it in ipairs(items) do
        set_item_muted(it, target)
      end
    end
  end

  r.UpdateArrange()
  r.Undo_EndBlock(desc, -1)
end

main()
