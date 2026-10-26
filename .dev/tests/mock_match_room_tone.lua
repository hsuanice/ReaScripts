-- @noindex  (local test for Items Properties/hsuanice_Match Room Tone of Joined Items.lua; not a ReaPack package)
-- Mock REAPER project with synthetic audio: each item has a room tone level and speech bursts.
-- usage (repo root): lua .dev/tests/mock_match_room_tone.lua
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/%.dev/tests/") or "."
local SCRIPT = REPO .. "/Items Properties/hsuanice_Match Room Tone of Joined Items.lua"

local tracks, mb, VIEW
local function amp(dbv) return 10 ^ (dbv / 20) end
local function new_track(name) local t = { name = name, items = {}, depth = 0 }; tracks[#tracks + 1] = t; return t end
-- noise_db: room tone; speech: fraction of the item that is speech at -20 dB (bursts in the middle)
local function new_item(tr, pos, len, noise_db, speech, o)
  o = o or {}
  local it = { tr = tr, pos = pos, len = len, sel = o.sel ~= false, vol = o.vol or 1, lock = o.lock or 0,
    take = { vol = o.take_vol or 1, noise = amp(noise_db), speech = speech or 0.5, src_ch = o.ch or 1 } }
  it.take.item = it
  tr.items[#tr.items + 1] = it
  return it
end
local function setup() tracks, mb, VIEW = {}, nil, { 0, 100 } end
local function all_items() local o = {}; for _, t in ipairs(tracks) do for _, i in ipairs(t.items) do o[#o + 1] = i end end; return o end
local function sel_items() local o = {}; for _, i in ipairs(all_items()) do if i.sel then o[#o + 1] = i end end; return o end
local function idx_of(t) for i, x in ipairs(tracks) do if x == t then return i end end end

reaper = {
  CountSelectedMediaItems = function() return #sel_items() end,
  GetSelectedMediaItem = function(_, i) return sel_items()[i + 1] end,
  GetMediaItem_Track = function(it) return it.tr end,
  GetMediaItemInfo_Value = function(it, k)
    if k == "D_POSITION" then return it.pos elseif k == "D_LENGTH" then return it.len
    elseif k == "D_VOL" then return it.vol elseif k == "C_LOCK" then return it.lock end
    return 0
  end,
  GetActiveTake = function(it) return it.take end,
  TakeIsMIDI = function() return false end,
  GetMediaItemTake_Source = function(t) return t end,
  GetMediaSourceNumChannels = function(t) return t.src_ch end,
  GetMediaItemTakeInfo_Value = function(t, k) if k == "D_VOL" then return t.vol end return 0 end,
  SetMediaItemTakeInfo_Value = function(t, k, v) if k == "D_VOL" then t.vol = v end end,
  -- the accessor plays the take at its current take volume (worst case for the script)
  CreateTakeAudioAccessor = function(t) return { take = t, gain = t.vol } end,
  DestroyAudioAccessor = function() end,
  new_array = function(n)
    local a = {}
    a.clear = function() for i = 1, n do a[i] = 0 end end
    return a
  end,
  GetAudioAccessorSamples = function(acc, sr, nch, t0, n, buf)
    local tk = acc.take
    local len = tk.item.len
    local s_from, s_to = len * (0.5 - tk.speech / 2), len * (0.5 + tk.speech / 2)
    for i = 0, n - 1 do
      local t = t0 + i / sr
      local a = (t >= s_from and t < s_to) and amp(-20) or tk.noise
      local v = ((i % 2 == 0) and 1 or -1) * a * acc.gain
      for c = 1, nch do buf[i * nch + c] = v end
    end
  end,
  GetTrackName = function(t) return true, t.name end,
  GetMediaTrackInfo_Value = function(t, k)
    if k == "IP_TRACKNUMBER" then return idx_of(t) elseif k == "I_FOLDERDEPTH" then return t.depth end
    return 0
  end,
  SetMediaTrackInfo_Value = function(t, k, v) if k == "I_FOLDERDEPTH" then t.depth = v end end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  InsertTrackAtIndex = function(i) table.insert(tracks, i + 1, { name = "", items = {}, depth = 0 }) end,
  GetSetMediaTrackInfo_String = function(t, _, v, set) if set then t.name = v end; return true, t.name end,
  MoveMediaItemToTrack = function(it, tr)
    for i, x in ipairs(it.tr.items) do if x == it then table.remove(it.tr.items, i) break end end
    it.tr = tr; tr.items[#tr.items + 1] = it
  end,
  GetSet_ArrangeView2 = function() return VIEW[1], VIEW[2] end,
  format_timestr_pos = function(t) return string.format("%.2f", t) end,
  MB = function(m) mb = m end,
  Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  PreventUIRefresh = function() end, UpdateArrange = function() end, TrackList_AdjustWindows = function() end,
}

local fails, passes = 0, 0
local function check(name, cond)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL " .. name) end
end
local function near_db(a, b, tol) return math.abs(20 * math.log(a / b, 10)) < (tol or 0.1) end

-- 1. A group: long reference -60 dB, B 6 dB louder, C (crossfaded) 6 dB quieter, D needs +20 dB
setup()
local t1 = new_track("DIA 1")
local A = new_item(t1, 0, 10, -60, 0.5)
local B = new_item(t1, 10, 4, -54, 0.5)
local C = new_item(t1, 13.5, 2.5, -66, 0.4)        -- overlaps B (crossfade)
local D = new_item(t1, 16, 2, -80, 0.4)
local E = new_item(t1, 30, 3, -40, 0.4)            -- separate group (single item)
local t2 = new_track("DIA 2")
dofile(SCRIPT)
check("reference (longest) untouched", near_db(A.take.vol, 1, 0.01))
check("B 6 dB louder -> take volume -6 dB", near_db(B.take.vol, amp(-6)))
check("C 6 dB quieter (crossfaded) -> +6 dB", near_db(C.take.vol, amp(6)))
check("D needs +20 dB -> moved, not adjusted", D.tr ~= t1 and near_db(D.take.vol, 1, 0.01))
check("mismatch track right below, named after the track", tracks[2].name == "DIA 1 - RT mismatch" and D.tr == tracks[2] and tracks[3] == t2)
check("single item group untouched", near_db(E.take.vol, 1, 0.01))
check("window lists the moved item", mb and mb:find("moved to the mismatch track", 1, true) ~= nil)

-- 2. item volume counts; existing take volume is kept as the starting point
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -60, 0.5, { vol = amp(6) })            -- item volume +6 dB
C = new_item(t1, 14, 4, -63, 0.5, { take_vol = amp(-3) })      -- already -3 dB take volume
dofile(SCRIPT)
check("item volume +6 dB compensated by take volume -6 dB", near_db(B.take.vol, amp(-6)))
check("existing -3 dB take volume (heard -66): +6 dB -> +3 dB", near_db(C.take.vol, amp(3)))
check("no window when nothing was skipped", mb == nil)

-- 3. speech all the way through measures at speech level (-20) -> far off -> mismatch track;
--    a pure room tone item (no speech) is measured normally; the reference must have pauses
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -50, 1.0)
C = new_item(t1, 14, 3, -57, 0)                    -- room tone only
dofile(SCRIPT)
check("speech all through -> moved", B.tr ~= t1 and near_db(B.take.vol, 1, 0.01))
check("room tone only item matched (-3 dB)", near_db(C.take.vol, amp(-3)))
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 12, -50, 1.0)                  -- longest, but speech all the way through
B = new_item(t1, 12, 8, -60, 0.5)                  -- has pauses -> reference
C = new_item(t1, 20, 4, -54, 0.5)
dofile(SCRIPT)
check("reference = longest item with pauses", near_db(B.take.vol, 1, 0.01) and near_db(C.take.vol, amp(-6)) and A.tr ~= t1)

-- 4. never outside the view; unselected items are not part of a group; a gap splits groups
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -54, 0.5)
VIEW = { 0, 12 }
dofile(SCRIPT)
check("group partly outside the view: skipped, listed", near_db(B.take.vol, 1, 0.01) and mb and mb:find("not fully in view", 1, true))
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -54, 0.5, { sel = false })
C = new_item(t1, 14.5, 4, -54, 0.5)                             -- gap after A, B unselected
dofile(SCRIPT)
check("unselected item untouched, gap = separate groups", near_db(B.take.vol, 1, 0.01) and near_db(C.take.vol, 1, 0.01))

-- 5. stereo items, folder end kept on the new track
setup()
local fold = new_track("Folder"); fold.depth = 1
t1 = new_track("DIA"); t1.depth = -1
A = new_item(t1, 0, 10, -60, 0.5, { ch = 2 })
B = new_item(t1, 10, 4, -54, 0.5, { ch = 2 })
D = new_item(t1, 14, 2, -85, 0.4, { ch = 2 })
dofile(SCRIPT)
check("stereo measured", near_db(B.take.vol, amp(-6)))
check("folder end moves to the mismatch track", t1.depth == 0 and tracks[3].name == "DIA - RT mismatch" and tracks[3].depth == -1)

print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
