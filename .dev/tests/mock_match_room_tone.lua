-- @noindex  (local test for Items Properties/hsuanice_Match Room Tone of Joined Items.lua; not a ReaPack package)
-- Mock REAPER project with synthetic audio. Each take has a source file: room tone level,
-- speech bursts and movement noise, given in source time; the item plays part of it.
-- usage (repo root): lua .dev/tests/mock_match_room_tone.lua
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/%.dev/tests/") or "."
local SCRIPT = REPO .. "/Items Properties/hsuanice_Match Room Tone of Joined Items.lua"

local tracks, mb, VIEW
local queue, getchar_val, gfx_opened = {}, 0, false
local function amp(dbv) return 10 ^ (dbv / 20) end
local function new_track(name) local t = { name = name, items = {}, depth = 0 }; tracks[#tracks + 1] = t; return t end
-- noise_db: room tone of the file; speech: fraction of the ITEM's part that is speech (-20 dB,
-- in its middle). o.offs / o.src_len: where the item sits in a longer file; o.motion: list of
-- {from, to, db} in source time (louder noise such as movement)
local function new_item(tr, pos, len, noise_db, speech, o)
  o = o or {}
  local offs = o.offs or 0
  local sp = speech or 0.5
  local take = { vol = o.take_vol or 1, noise = amp(noise_db), src_ch = o.ch or 1, offs = offs,
    src_len = o.src_len or (offs + len), rate = 1, motion = o.motion or {}, hum = o.hum,
    speech = { offs + len * (0.5 - sp / 2), offs + len * (0.5 + sp / 2) } }
  local it = { tr = tr, pos = pos, len = len, sel = o.sel ~= false, vol = o.vol or 1, lock = o.lock or 0,
    take = take, fades = { D_FADEINLEN = 0.1, D_FADEOUTLEN = 0.1, D_FADEINLEN_AUTO = 0, D_FADEOUTLEN_AUTO = 0 } }
  take.item = it
  tr.items[#tr.items + 1] = it
  return it
end
local function setup() tracks, mb, VIEW = {}, nil, { 0, 100 } end
local function all_items() local o = {}; for _, t in ipairs(tracks) do for _, i in ipairs(t.items) do o[#o + 1] = i end end; return o end
local function sel_items() local o = {}; for _, i in ipairs(all_items()) do if i.sel then o[#o + 1] = i end end; return o end
local function idx_of(t) for i, x in ipairs(tracks) do if x == t then return i end end end

local function src_amp(tk, ts)
  if ts >= tk.speech[1] and ts < tk.speech[2] then return amp(-20) end
  for _, m in ipairs(tk.motion) do if ts >= m[1] and ts < m[2] then return amp(m[3]) end end
  return tk.noise
end
-- white noise (random signs, exact RMS) + optional hum {hz, db} (e.g. a generator)
local function src_sample(tk, ts, sr)
  local z = math.floor(ts * sr + 0.5) + 0x9E3779B97F4A7C15     -- splitmix64 hash of the sample index
  z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
  z = (z ~ (z >> 27)) * 0x94D049BB133111EB
  z = z ~ (z >> 31)
  local v = ((z & 1) == 0 and 1 or -1) * src_amp(tk, ts)
  if tk.hum then v = v + amp(tk.hum[2]) * math.sqrt(2) * math.sin(2 * math.pi * tk.hum[1] * ts) end
  return v
end
-- REAPER's array.fft_real layout: [1] DC, [2] Nyquist, then (re, im) of bins 1 .. n/2-1
local function fft_real(a, n)
  local re, im = {}, {}
  for i = 0, n - 1 do re[i] = a[i + 1]; im[i] = 0 end
  local j = 0
  for i = 0, n - 2 do
    if i < j then re[i], re[j] = re[j], re[i]; im[i], im[j] = im[j], im[i] end
    local m = n // 2
    while m >= 1 and j >= m do j = j - m; m = m // 2 end
    j = j + m
  end
  local len = 2
  while len <= n do
    local ang = -2 * math.pi / len
    local wr, wi = math.cos(ang), math.sin(ang)
    for i = 0, n - 1, len do
      local cr, ci = 1, 0
      for k = 0, len // 2 - 1 do
        local ar, ai = re[i + k + len // 2], im[i + k + len // 2]
        local tr, ti = ar * cr - ai * ci, ar * ci + ai * cr
        re[i + k + len // 2], im[i + k + len // 2] = re[i + k] - tr, im[i + k] - ti
        re[i + k], im[i + k] = re[i + k] + tr, im[i + k] + ti
        cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
      end
    end
    len = len * 2
  end
  a[1], a[2] = re[0], re[n // 2]
  for k = 1, n // 2 - 1 do a[2 * k + 1], a[2 * k + 2] = re[k], im[k] end
end

reaper = {
  CountSelectedMediaItems = function() return #sel_items() end,
  GetSelectedMediaItem = function(_, i) return sel_items()[i + 1] end,
  GetMediaItem_Track = function(it) return it.tr end,
  GetMediaItemInfo_Value = function(it, k)
    if k == "D_POSITION" then return it.pos elseif k == "D_LENGTH" then return it.len
    elseif k == "D_VOL" then return it.vol elseif k == "C_LOCK" then return it.lock
    elseif it.fades[k] then return it.fades[k] end
    return 0
  end,
  SetMediaItemInfo_Value = function(it, k, v)
    if k == "D_LENGTH" then it.len = v elseif it.fades[k] then it.fades[k] = v end
  end,
  GetActiveTake = function(it) return it.take end,
  TakeIsMIDI = function() return false end,
  GetMediaItemTake_Source = function(t) return t end,
  GetMediaSourceNumChannels = function(t) return t.src_ch end,
  GetMediaSourceLength = function(t) return t.src_len, false end,
  GetMediaItemTakeInfo_Value = function(t, k)
    if k == "D_VOL" then return t.vol elseif k == "D_STARTOFFS" then return t.offs elseif k == "D_PLAYRATE" then return t.rate end
    return 0
  end,
  SetMediaItemTakeInfo_Value = function(t, k, v)
    if k == "D_VOL" then t.vol = v elseif k == "D_STARTOFFS" then t.offs = v end
  end,
  -- the accessor plays the take as it is when created, at its take volume (worst case)
  CreateTakeAudioAccessor = function(t) return { take = t, gain = t.vol, offs = t.offs, len = t.item.len } end,
  DestroyAudioAccessor = function() end,
  new_array = function(n)
    local a = {}
    a.clear = function() for i = 1, n do a[i] = 0 end end
    a.fft_real = function(size) fft_real(a, size) end
    return a
  end,
  GetAudioAccessorSamples = function(acc, sr, nch, t0, n, buf)
    for i = 0, n - 1 do
      local t = t0 + i / sr
      local v = (t < acc.len) and src_sample(acc.take, acc.offs + t, sr) * acc.gain or 0
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
  PreventUIRefresh = function(n) ui_hold = (ui_hold or 0) + n end,
  UpdateArrange = function() end, TrackList_AdjustWindows = function() end,
  GetTakeName = function() return "take" end,
  time_precise = function() return os.clock() end,
  defer = function(f) queue[#queue + 1] = f end,
  atexit = function() end,
}
gfx = { w = 460, h = 96, x = 0, y = 0,
  init = function() gfx_opened = true end, quit = function() end, set = function() end, rect = function() end,
  setfont = function() end, drawstr = function() end, update = function() end,
  measurestr = function(t) return #t * 7, 14 end, getchar = function() return getchar_val end }
-- run the script and its defer cycles until it is done
local function run_script()
  queue, gfx_opened = {}, false
  dofile(SCRIPT)
  local n = 0
  while #queue > 0 and n < 100000 do n = n + 1; table.remove(queue, 1)() end
end

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
run_script()
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
C = new_item(t1, 14, 4, -63, 0.5, { take_vol = amp(-3) })      -- heard -66 dB
run_script()
check("item volume +6 dB compensated by take volume -6 dB", near_db(B.take.vol, amp(-6)))
check("existing -3 dB take volume (heard -66): +6 dB -> +3 dB", near_db(C.take.vol, amp(3)))
check("no window when nothing was skipped", mb == nil)

-- 3. speech all the way through -> far off -> mismatch track; room tone only item measured;
--    the reference must have pauses
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -50, 1.0)
C = new_item(t1, 14, 3, -57, 0)
run_script()
check("speech all through -> moved", B.tr ~= t1 and near_db(B.take.vol, 1, 0.01))
check("room tone only item matched (-3 dB)", near_db(C.take.vol, amp(-3)))
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 12, -50, 1.0)
B = new_item(t1, 12, 8, -60, 0.5)
C = new_item(t1, 20, 4, -54, 0.5)
run_script()
check("reference = longest item with pauses", near_db(B.take.vol, 1, 0.01) and near_db(C.take.vol, amp(-6)) and A.tr ~= t1)

-- 4. the WHOLE file is measured: movement in the item's pauses, clean room tone in the handles
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
-- B plays 30..34 s of a 60 s file whose room tone is -60, but its own pauses are full of movement (-45)
B = new_item(t1, 10, 4, -60, 0.6, { offs = 30, src_len = 60, motion = { { 30, 34, -45 } } })
run_script()
check("movement in the pauses ignored: matched by the whole file (no change)", near_db(B.take.vol, 1, 0.05))
check("listed: own part louder than the quietest of the file", mb and mb:find("louder than the quietest of its file", 1, true) ~= nil)
check("item restored after the measurement", near_db(B.take.offs + 1, 31, 0.001) and math.abs(B.len - 4) < 1e-9
  and math.abs(B.fades.D_FADEINLEN - 0.1) < 1e-9 and math.abs(B.fades.D_FADEOUTLEN - 0.1) < 1e-9)
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -54, 0.5, { offs = 20, src_len = 50 })     -- clean file, 6 dB louder
run_script()
check("longer clean file: -6 dB as before, nothing listed", near_db(B.take.vol, amp(-6)) and mb == nil)

-- 5. never outside the view; unselected items are not part of a group; a gap splits groups
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -54, 0.5)
VIEW = { 0, 12 }
run_script()
check("group partly outside the view: skipped, listed", near_db(B.take.vol, 1, 0.01) and mb and mb:find("not fully in view", 1, true))
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 4, -54, 0.5, { sel = false })
C = new_item(t1, 14.5, 4, -54, 0.5)
run_script()
check("unselected item untouched, gap = separate groups", near_db(B.take.vol, 1, 0.01) and near_db(C.take.vol, 1, 0.01))

-- 6. stereo items, folder end kept on the new track
setup()
local fold = new_track("Folder"); fold.depth = 1
t1 = new_track("DIA"); t1.depth = -1
A = new_item(t1, 0, 10, -60, 0.5, { ch = 2 })
B = new_item(t1, 10, 4, -54, 0.5, { ch = 2 })
D = new_item(t1, 14, 2, -85, 0.4, { ch = 2 })
run_script()
check("stereo measured", near_db(B.take.vol, amp(-6)))
check("folder end moves to the mismatch track", t1.depth == 0 and tracks[3].name == "DIA - RT mismatch" and tracks[3].depth == -1)

-- 7. spectrum: a generator in one shot -> different room tone -> moved, even at the same level
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 6, -57, 0.5)
C = new_item(t1, 16, 5, -60, 0.5, { hum = { 100, -58 } })        -- generator hum at 100 Hz
D = new_item(t1, 21, 6, -63, 0.5)
run_script()
check("generator shot moved, not level-matched", C.tr ~= t1 and near_db(C.take.vol, 1, 0.01))
check("window names the band", mb and mb:find("around 100 Hz", 1, true) ~= nil and mb:find("different room tone", 1, true) ~= nil)
check("the others are still level-matched", near_db(B.take.vol, amp(-3), 0.3) and near_db(D.take.vol, amp(3), 0.3))
-- the generator shot is the longest: it must not become the reference
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 6, -60, 0.5)
B = new_item(t1, 6, 20, -60, 0.5, { hum = { 100, -58 } })
C = new_item(t1, 26, 5, -54, 0.5)
run_script()
check("longest item with a generator is not the reference", B.tr ~= t1 and near_db(C.take.vol, amp(-6), 0.3))
-- only two items that differ: both listed, nothing changed
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5)
B = new_item(t1, 10, 5, -54, 0.5, { hum = { 100, -56 } })
run_script()
check("two different items: both listed, nothing changed", near_db(B.take.vol, 1, 0.01) and A.tr == t1 and B.tr == t1
  and mb and select(2, mb:gsub("the two items' room tone differs", "")) == 2)

-- 8. progress window and cancel
check("progress window opened for a long analysis", gfx_opened)
check("UI refresh released after the analysis", (ui_hold or 0) == 0)
setup()
t1 = new_track("DIA")
A = new_item(t1, 0, 10, -60, 0.5, { offs = 100, src_len = 400 })   -- long files: several cycles
B = new_item(t1, 10, 4, -54, 0.5, { offs = 50, src_len = 400 })
getchar_val = 27                                                     -- Esc
run_script()
getchar_val = 0
check("cancel: nothing changed", near_db(B.take.vol, 1, 0.01) and B.tr == t1 and mb == nil)
check("cancel: item restored, UI refresh released", math.abs(A.len - 10) < 1e-9 and math.abs(A.take.offs - 100) < 1e-9
  and math.abs(B.len - 4) < 1e-9 and (ui_hold or 0) == 0)

print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
