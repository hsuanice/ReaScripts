-- @noindex  (local test for Selection/hsuanice_Toggle Track and Razor Item Link like Pro Tools.lua; not a ReaPack package)
-- Mock REAPER project; the watcher's defer loop is stepped by hand, with "user" changes between
-- steps. JS / SWS are absent, so the mouse guards stay off.
-- usage (repo root): lua .dev/tests/mock_track_link.lua
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/%.dev/tests/") or "."
local SCRIPT = REPO .. "/Selection/hsuanice_Toggle Track and Razor Item Link like Pro Tools.lua"

local tracks, items, queue, psc, ts
local function setup()
  tracks, items, queue, psc, ts = {}, {}, {}, 0, { 0, 0 }
  for i = 1, 4 do tracks[i] = { guid = "{T" .. i .. "}", sel = false, razor = "", items = {} } end
  local function add(t, pos, len)
    local it = { tr = tracks[t], pos = pos, len = len, sel = false, guid = "{I" .. (#items + 1) .. "}" }
    items[#items + 1] = it; table.insert(tracks[t].items, it)
    return it
  end
  add(1, 0, 10); add(2, 0, 10); add(3, 20, 10)   -- track 4 is empty
end
local function sel_items() local o = {}; for _, i in ipairs(items) do if i.sel then o[#o + 1] = i end end; return o end
local function sel_tracks() local o = {}; for _, t in ipairs(tracks) do if t.sel then o[#o + 1] = t end end; return o end

reaper = {
  APIExists = function() return false end,
  set_action_options = function() end, atexit = function() end,
  SetProjExtState = function() end, GetProjExtState = function() return 0, "" end, SetExtState = function() end,
  ShowConsoleMsg = function() end,
  defer = function(f) queue[#queue + 1] = f end,
  time_precise = function() return 0 end,
  GetProjectStateChangeCount = function() return psc end,
  GetCursorPosition = function() return 0 end,
  GetSet_LoopTimeRange = function() return ts[1], ts[2] end,
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetTrackGUID = function(t) return t.guid end,
  CountSelectedTracks = function() return #sel_tracks() end,
  GetSelectedTrack = function(_, i) return sel_tracks()[i + 1] end,
  SetTrackSelected = function(t, v) t.sel = v end,
  GetMediaTrackInfo_Value = function(t, k) if k == "I_SELECTED" then return t.sel and 1 or 0 end; return 0 end,
  GetSetMediaTrackInfo_String = function(t, k, v, set)
    if set then t.razor = v; psc = psc + 1; return true, v end
    return true, t.razor
  end,
  CountTrackMediaItems = function(t) return #t.items end,
  GetTrackMediaItem = function(t, i) return t.items[i + 1] end,
  CountSelectedMediaItems = function() return #sel_items() end,
  GetSelectedMediaItem = function(_, i) return sel_items()[i + 1] end,
  GetMediaItem_Track = function(i) return i.tr end,
  GetMediaItemInfo_Value = function(i, k)
    if k == "D_POSITION" then return i.pos elseif k == "D_LENGTH" then return i.len elseif k == "B_UISEL" then return i.sel and 1 or 0 end
    return 0
  end,
  SetMediaItemInfo_Value = function(i, k, v) if k == "B_UISEL" then i.sel = (v == 1) end end,
  GetSetMediaItemInfo_String = function(i) return true, i.guid end,
  PreventUIRefresh = function() end, UpdateArrange = function() end, TrackList_AdjustWindows = function() end,
  GetMainHwnd = function() return {} end,
}

local function step(n)
  for _ = 1, n or 1 do
    local f = table.remove(queue, 1)
    if f then f() end
  end
end
local fails, passes = 0, 0
local function check(name, cond)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL " .. name) end
end
local function tsel(...)
  local want = {}; for _, i in ipairs({ ... }) do want[i] = true end
  for i, t in ipairs(tracks) do if t.sel ~= (want[i] or false) then return false end end
  return true
end

-- 1. Arrange -> TCP: selecting items selects their tracks
setup(); dofile(SCRIPT); step()
items[1].sel, items[2].sel = true, true
step(3)
check("items selected -> their tracks selected", tsel(1, 2))

-- 2. The reported chain: Option+double-click on the TCP (mouse modifier "Select all tracks")
--    click 1 clears the selection, click 2 selects every track; the items of the latched
--    range get selected (D), and that must not shrink the track selection again (B)
for _, i in ipairs(items) do i.sel = false end
for _, t in ipairs(tracks) do t.sel = false end
step()
for _, t in ipairs(tracks) do t.sel = true end
step(4)
check("Select all tracks stays all tracks", tsel(1, 2, 3, 4))
check("D selected the items in the range (TCP -> Arrange)", items[1].sel and items[2].sel and not items[3].sel)

-- 3. Select all tracks with the items still selected (Action 40296 keeps them)
setup(); dofile(SCRIPT); step()
items[1].sel, items[2].sel = true, true
step(3)
for _, t in ipairs(tracks) do t.sel = true end
step(4)
check("40296 with items selected: still all tracks", tsel(1, 2, 3, 4))

-- 4. TCP -> Arrange: one more track joins the range
setup(); dofile(SCRIPT); step()
items[1].sel = true
step(3)
check("one item -> its track", tsel(1))
tracks[2].sel = true
step(4)
check("track added -> its item in the range selected", items[2].sel and not items[3].sel)
check("and the track selection is left as the user set it", tsel(1, 2))

-- 5. Arrange -> TCP still follows a new item selection afterwards
items[1].sel, items[2].sel, items[3].sel = false, false, true
step(3)
check("later item selection still drives the tracks", tsel(3))

print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
