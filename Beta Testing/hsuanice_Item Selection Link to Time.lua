--[[
@description hsuanice_Item Selection and link to Time
@version 0.1.1
@author hsuanice
@about
  Background watcher that mirrors current ITEM SELECTION to the TIME SELECTION:
    • When item selection changes, set time selection to [min(item.start) .. max(item.end)].
    • Pauses when any Razor Areas exist in the project (respect Razor).
    • Ultra lightweight, no UI, no lag.

  Conventions:
    • Auto-terminate previous instance on relaunch; keep toolbar toggle in sync (same pattern as Razor-Link).
    • Publishes a per-project enabled flag for interoperability if needed.

@changelog
  v0.1.1 - Respect Razor Areas: if any Razor exists (track-level or fallback), do not link item → time.
           Keeps original light watcher, only adds a cheap Razor presence check per cycle.
  v0.1.0 - Initial release. Ultra-light item→time selection link with state-change gating and toolbar sync.
]]

-------------------- USER OPTIONS --------------------
-- If true, clear time selection when no items are selected; otherwise keep previous range.
local CLEAR_WHEN_EMPTY = false

-- Tiny tolerance in seconds to avoid floating-point edge issues.
local EPS = 1e-12
------------------------------------------------------

-- Auto-terminate previous instance and toggle ON (1=auto-terminate, 4=toggle ON).
if reaper.set_action_options then reaper.set_action_options(1 | 4) end

-- Mark enabled for this project; and ensure toggle OFF on exit.
reaper.atexit(function()
  if reaper.set_action_options then reaper.set_action_options(8) end -- 8=toggle OFF
  reaper.SetProjExtState(0, "hsuanice_ItemTimeLink", "enabled", "0")
end)
reaper.SetProjExtState(0, "hsuanice_ItemTimeLink", "enabled", "1")

-- Build a tiny signature for current item selection to detect changes cheaply.
local function selection_signature()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then return "0|" end
  local min_pos, max_end = math.huge, -math.huge
  for i = 0, n-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos < min_pos then min_pos = pos end
    local iend = pos + len
    if iend > max_end then max_end = iend end
  end
  return string.format("%d|%.12f|%.12f", n, min_pos, max_end)
end

-- Apply time selection from current item selection.
local function apply_time_from_selection()
  local n = reaper.CountSelectedMediaItems(0)
  if n == 0 then
    if CLEAR_WHEN_EMPTY then
      reaper.GetSet_LoopTimeRange(true, false, 0, 0, false)
    end
    return
  end

  local min_pos, max_end = math.huge, -math.huge
  for i = 0, n-1 do
    local it  = reaper.GetSelectedMediaItem(0, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos < min_pos then min_pos = pos end
    local iend = pos + len
    if iend > max_end then max_end = iend end
  end

  if min_pos < (max_end - EPS) then
    reaper.GetSet_LoopTimeRange(true, false, min_pos, max_end, false)
  end
end

-- ----- Razor presence (project-wide) -----
-- We respect *any* track-level Razor segments. We read EXT first, then fallback.
local function razor_signature()
  local parts = {}
  local tcnt = reaper.CountTracks(0)
  for i = 0, tcnt-1 do
    local tr = reaper.GetTrack(0, i)
    local _, s1 = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS_EXT", "", false)
    local _, s2 = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    parts[#parts+1] = s1 or ""
    parts[#parts+1] = s2 or ""
  end
  return table.concat(parts, "|")
end

local function razor_exists(sig)
  -- Any pair of numbers like "<start> <end>" indicates presence.
  -- We do not parse GUIDs here; any numeric pair is enough to pause linking.
  return sig:find("[-%d%.]+%s+[-%d%.]+") ~= nil
end
-- ----------------------------------------

-- Gated main loop: only run when project state or selection sig changes.
local last_psc = -1
local last_sel_sig = ""
local last_razor_sig = ""
local last_razor_has = false

local function mainloop()
  local psc = reaper.GetProjectStateChangeCount(0)  -- cheap global change counter

  -- Update razor presence only when its signature changes (cheap join of strings).
  local r_sig = razor_signature()
  if r_sig ~= last_razor_sig then
    last_razor_sig = r_sig
    last_razor_has = razor_exists(r_sig)
  end

  local s_sig = selection_signature()

  if psc ~= last_psc or s_sig ~= last_sel_sig then
    last_psc = psc
    if s_sig ~= last_sel_sig then
      last_sel_sig = s_sig
      -- Respect Razor: if any Razor exists, do nothing.
      if not last_razor_has then
        apply_time_from_selection()
      end
      -- else paused while Razor exists
    end
  end

  reaper.defer(mainloop)
end

mainloop()
