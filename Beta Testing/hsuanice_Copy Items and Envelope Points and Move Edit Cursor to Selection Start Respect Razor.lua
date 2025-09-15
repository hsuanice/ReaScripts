--[[
@description hsuanice_Copy Items and Envelope Points and Move Edit Cursor to Selection Start Respect Razor
@version 0.1.0
@author hsuanice
@changelog Initial release
@about
  Copy items and envelope points only (never tracks). When there is no Razor Selection but items are selected,
  move the edit cursor to the earliest selected item start at the moment of copying; with Razor Selection, respect
  the razor time range and move edit cursor to the earliest razor start. If only envelope points are selected,
  do not move the edit cursor. Designed to paste on a different target track at the same timeline position.
]]--

local r = reaper

--=== helpers ===--

local function save_and_clear_track_selection()
  local sel = {}
  local project = 0
  local track_cnt = r.CountTracks(project)
  for i = 0, track_cnt-1 do
    local tr = r.GetTrack(project, i)
    sel[i] = r.GetMediaTrackInfo_Value(tr, "I_SELECTED")
    if sel[i] == 1 then r.SetMediaTrackInfo_Value(tr, "I_SELECTED", 0) end
  end
  return sel
end

local function restore_track_selection(sel)
  if not sel then return end
  local project = 0
  local track_cnt = r.CountTracks(project)
  for i = 0, track_cnt-1 do
    local tr = r.GetTrack(project, i)
    local v = sel[i] or 0
    if r.GetMediaTrackInfo_Value(tr, "I_SELECTED") ~= v then
      r.SetMediaTrackInfo_Value(tr, "I_SELECTED", v)
    end
  end
end

local function has_selected_items()
  return r.CountSelectedMediaItems(0) > 0
end

-- Return earliest start among selected items (seconds), or nil
local function earliest_selected_item_start()
  local cnt = r.CountSelectedMediaItems(0)
  local earliest = nil
  for i = 0, cnt-1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      if not earliest or pos < earliest then earliest = pos end
    end
  end
  return earliest
end

-- Detect razor selections across all tracks and return earliest start (seconds), or nil if none
local function earliest_razor_start()
  local project = 0
  local track_cnt = r.CountTracks(project)
  local earliest = nil
  for i = 0, track_cnt-1 do
    local tr = r.GetTrack(project, i)
    -- Query razor string (either P_RAZOREDITS or P_RAZOREDITS_EXT if present)
    local _, rz = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if (not rz or rz == "" or rz == " ") and r.GetSetMediaTrackInfo_String then
      -- Some builds also expose P_RAZOREDITS_EXT; try it if basic string is empty
      local _, rz_ext = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
      rz = rz_ext or rz
    end
    if rz and rz ~= "" then
      -- Format is space-separated tokens; segments are triplets (start end flags/guid...) possibly followed by GUIDs.
      -- We can safely parse by scanning tokens and taking any token that can be tonumber and is followed by another number as a start.
      for tok in string.gmatch(rz, "%S+") do
        local s = tonumber(tok)
        if s then
          -- Heuristic: a valid segment begins with start time; accept as candidate
          if not earliest or s < earliest then earliest = s end
        end
      end
    end
  end
  return earliest
end

local function selected_envelope_exists()
  local env = r.GetSelectedEnvelope(0)
  return env ~= nil
end

-- Set cursor context to items or envelopes to avoid track-oriented copy
local function set_cursor_context_for_mode(mode) -- "item" | "env"
  if mode == "env" then
    r.SetCursorContext(2, nil) -- 2=envelope
  else
    r.SetCursorContext(1, nil) -- 1=items
  end
end

--=== main ===--

r.Undo_BeginBlock()

local track_sel_backup = save_and_clear_track_selection()

local razor_start = earliest_razor_start()
local item_mode = false
local env_mode = false

if razor_start then
  -- Razor mode: move cursor to earliest razor start
  r.SetEditCurPos(razor_start, false, false)
  set_cursor_context_for_mode("item") -- Arrange context; REAPER will respect Razor range on copy
else
  if has_selected_items() then
    item_mode = true
    local t0 = earliest_selected_item_start()
    if t0 then r.SetEditCurPos(t0, false, false) end
    set_cursor_context_for_mode("item")
  elseif selected_envelope_exists() then
    env_mode = true
    -- Do NOT move edit cursor
    set_cursor_context_for_mode("env")
  else
    restore_track_selection(track_sel_backup)
    r.Undo_EndBlock("Copy (no selection to process)", -1)
    return
  end
end

-- Perform COPY (40057=Copy, 40059=Cut) — here we use 40057
r.Main_OnCommand(40057, 0) -- Copy items/tracks/envelope points (depending on focus)

restore_track_selection(track_sel_backup)
r.UpdateArrange()
r.Undo_EndBlock("hsuanice: Copy Items+Envelope Points (Cursor to Selection Start, Respect Razor)", -1)
