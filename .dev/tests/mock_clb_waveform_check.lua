-- Mock run of Conform/hsuanice_Conform List Browser - CLB Waveform Check.lua
-- Run: lua ".dev/tests/mock_clb_waveform_check.lua"   (from the repository root)
-- AAF items (the editor's audio) over conformed ISO items: in sync, an Auto Align-delayed
-- channel, two frames late, another sound, too short, nothing conformed.
local ROOT = io.popen("pwd"):read("*l")
local function fft(a, n, inverse)
  local j = 0
  for i = 0, n - 2 do
    if i < j then
      a[2 * i + 1], a[2 * j + 1] = a[2 * j + 1], a[2 * i + 1]
      a[2 * i + 2], a[2 * j + 2] = a[2 * j + 2], a[2 * i + 2]
    end
    local m = n >> 1
    while m >= 1 and j & m ~= 0 do j = j ~ m; m = m >> 1 end
    j = j | m
  end
  local len = 2
  while len <= n do
    local ang = (inverse and 2 or -2) * math.pi / len
    local wr, wi = math.cos(ang), math.sin(ang)
    for s = 0, n - 1, len do
      local cr, ci = 1, 0
      for k = 0, len // 2 - 1 do
        local p, q = s + k, s + k + len // 2
        local xr, xi = a[2 * q + 1], a[2 * q + 2]
        local tr, ti = xr * cr - xi * ci, xr * ci + xi * cr
        local ur, ui = a[2 * p + 1], a[2 * p + 2]
        a[2 * p + 1], a[2 * p + 2] = ur + tr, ui + ti
        a[2 * q + 1], a[2 * q + 2] = ur - tr, ui - ti
        cr, ci = cr * wr - ci * wi, cr * wi + ci * wr
      end
    end
    len = len * 2
  end
end
local function new_array(n)
  local a = {}
  for i = 1, n do a[i] = 0 end
  a.clear = function() for i = 1, n do a[i] = 0 end end
  a.fft = function(size) fft(a, size, false) end
  a.ifft = function(size) fft(a, size, true) end
  return a
end
local seed = 777
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
local function make_voice(dur)
  local bursts, t = {}, 0.1
  while t < dur do
    local len = 0.2 + rnd() * 0.8
    bursts[#bursts + 1] = { s = t, e = t + len, f0 = 90 + rnd() * 120, ph = rnd() * 6, amp = 0.3 + rnd() * 0.7 }
    t = t + len + 0.1 + rnd() * 0.6
  end
  return function(x)
    for _, b in ipairs(bursts) do
      if x >= b.s and x < b.e then
        local env = math.sin(math.pi * (x - b.s) / (b.e - b.s))
        local v = 0
        for h = 1, 4 do if b.f0 * h < 450 then v = v + math.sin(2 * math.pi * b.f0 * h * (x - b.s) + b.ph * h) / h end end
        return env * b.amp * v
      end
    end
    return 0
  end
end
local voice, other = make_voice(200), make_voice(200)
local FPS = 24
-- sources: fn(project time) for simplicity; accessor time is relative to item start
local tracks, items_by = {}, {}
local function track(name) local t = { name = name, items = {} }; tracks[#tracks + 1] = t; return t end
local function item(tr, pos, len, fn, ext, name)
  local it = { track = tr, pos = pos, len = len, mute = 0, ext = ext or {}, name = name or "clip", markers = {} }
  it.take = { item = it, fn = function(t) return fn(pos + t) end, file = "x.wav", ext = it.ext, name = it.name }
  it.takes = { it.take }
  tr.items[#tr.items + 1] = it
  return it
end
local AAF, E1, E2 = track("AAF - A1"), track("EDL - A1 - 1"), track("EDL - A1 - 2")
local AAF2 = track("AAF - A2")
local d_aap = 100 / 48000
-- 1: in sync (ch1 exact, ch2 Auto Align-delayed)
item(AAF, 10, 6, voice, nil, "sync")
item(E1, 10, 6, voice, { ["P_EXT:CLB_EVENT"] = "001" })
item(E2, 10, 6, function(t) return voice(t - d_aap) end, { ["P_EXT:CLB_EVENT"] = "001" })
-- 2: only the delayed channel conformed -> "~"
item(AAF, 20, 6, voice, nil, "aap only")
item(E2, 20, 6, function(t) return voice(t - d_aap) end, { ["P_EXT:CLB_EVENT"] = "002" })
-- 3: ISO two frames late
item(AAF, 30, 6, voice, nil, "two late")
item(E1, 30, 6, function(t) return voice(t - 2 / FPS) end, { ["P_EXT:CLB_EVENT"] = "003" })
-- 4: another sound
item(AAF, 40, 6, voice, nil, "other take")
item(E1, 40, 6, other, { ["P_EXT:CLB_EVENT"] = "004" })
-- 5: too short (0.7 s)
item(AAF, 50, 0.7, voice, nil, "short")
item(E1, 50, 0.7, voice, { ["P_EXT:CLB_EVENT"] = "005" })
-- 6: nothing conformed
item(AAF, 60, 4, voice, nil, "no audio")
-- 8: Consolidate moved another track's event under AAF A1; the matching one sits on A3
local E3 = track("EDL - A3")
item(AAF, 70, 6, voice, nil, "packed")
item(E1, 70, 6, other, { ["P_EXT:CLB_EVENT"] = "008" })
item(E3, 70, 6, voice, { ["P_EXT:CLB_EVENT"] = "009" })
-- 9: one item, two takes (ISO channels): active take Auto Align-delayed, second take exact
do
  local it = item(E1, 80, 6, function(t) return voice(t - d_aap) end, { ["P_EXT:CLB_EVENT"] = "010" }, "multi")
  it.takes[2] = { item = it, fn = function(t) return voice(80 + t) end, file = "x.wav",
    ext = { ["P_EXT:CLB_EVENT"] = "010" }, name = "multi.A2" }
  item(AAF, 80, 6, voice, nil, "multi take")
end
-- 7: A2 (other channel of the mix) over audio conformed on A1 only (Remove Dups)
item(AAF2, 10, 6, voice, nil, "a2 dup")

local markers, console, deferred = {}, {}, {}
reaper = {
  GetResourcePath = function() return ROOT:gsub("/Scripts/hsuanice Scripts$", "") end,
  file_exists = function() return true end,
  new_array = new_array,
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetTrackName = function(t) return true, t.name end,
  CountTrackMediaItems = function(t) return #t.items end,
  GetTrackMediaItem = function(t, j) return t.items[j + 1] end,
  GetActiveTake = function(it) return it.take end,
  TakeIsMIDI = function() return false end,
  GetMediaItemTake_Source = function(tk) return tk end,
  GetMediaSourceFileName = function(src) return src.file end,
  GetMediaSourceNumChannels = function() return 1 end,
  GetMediaSourceSampleRate = function() return 48000 end,
  GetSetMediaItemTakeInfo_String = function(tk, k) return true, tk.ext[k] or "" end,
  GetMediaItemInfo_Value = function(it, k)
    if k == "D_POSITION" then return it.pos elseif k == "D_LENGTH" then return it.len elseif k == "B_MUTE" then return it.mute end
    return 0
  end,
  SetMediaItemInfo_Value = function(it, k, v) if k == "B_MUTE" then it.mute = v end end,
  GetMediaItemTakeInfo_Value = function() return 0 end,
  CountSelectedMediaItems = function() return 0 end,
  GetMediaItem_Track = function(it) return it.track end,
  GetSet_LoopTimeRange = function() return 0, 0 end,
  GetTakeName = function(tk) return tk.name or tk.item.name end,
  CountTakes = function(it) return #it.takes end,
  GetTake = function(it, t) return it.takes[t + 1] end,
  GetExtState = function() return "" end, SetExtState = function() end,
  GetUserInputs = function(_, _, _, def) return true, def end,
  TimeMap_curFrameRate = function() return FPS end,
  MB = function(m) print("MB: " .. m) end,
  Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  PreventUIRefresh = function() end, UpdateArrange = function() end,
  CountProjectMarkers = function() return 0, #markers, 0 end,
  EnumProjectMarkers = function(i) local m = markers[i + 1]; return 1, false, m.pos, 0, m.name, i end,
  DeleteProjectMarker = function() end,
  AddProjectMarker2 = function(_, _, pos, _, name) markers[#markers + 1] = { pos = pos, name = name } end,
  ColorToNative = function(r, g, b) return r + g * 256 + b * 65536 end,
  format_timestr_pos = function(p) return string.format("%.2f", p) end,
  ShowConsoleMsg = function(s) console[#console + 1] = s end,
  CreateTakeAudioAccessor = function(tk) return tk end,
  DestroyAudioAccessor = function() end,
  GetAudioAccessorSamples = function(acc, sr, _, t, n, buf)
    for i = 0, n - 1 do buf[i + 1] = acc.fn(t + i / sr) end
    return 1
  end,
  defer = function(f) deferred[#deferred + 1] = f end,
}
gfx = setmetatable({ w = 460, h = 96 }, { __index = function() return function() return 0 end end })
gfx.getchar = function() return 0 end
gfx.measurestr = function(s) return #s * 7 end

dofile("Conform/hsuanice_Conform List Browser - CLB Waveform Check.lua")
while #deferred > 0 do table.remove(deferred, 1)() end
print(table.concat(console))
local expect = { sync = "WC OK", ["aap only"] = "WC ~ ", ["two late"] = "WC SYNC -2f", ["other take"] = "WC NO MATCH",
  short = "WC ?", ["no audio"] = "WC NO AUDIO", ["a2 dup"] = "WC OK", packed = "WC OK EDL - A3", ["multi take"] = "WC OK" }
local pos_name = { [10] = "sync", [20] = "aap only", [30] = "two late", [40] = "other take", [50] = "short", [60] = "no audio", [70] = "packed", [80] = "multi take" }
local fails = 0
for _, m in ipairs(markers) do
  local want = expect[pos_name[math.floor(m.pos + 0.5)]]
  if m.pos == 10 and m.name ~= "WC OK EDL - A1 - 1" then want = "WC OK" end
  local ok = m.name:sub(1, #want) == want
  if not ok then fails = fails + 1 end
  print((ok and "  ok   " or "  FAIL ") .. m.pos .. "  " .. m.name)
end
local muted = {}
for _, it in ipairs(AAF.items) do if it.mute == 1 then muted[#muted + 1] = it.name end end
print("muted: " .. table.concat(muted, ", "))
if table.concat(muted, ",") ~= "sync,aap only,packed,multi take" then fails = fails + 1; print("  FAIL mute") end
if AAF2.items[1].mute ~= 1 then fails = fails + 1; print("  FAIL a2 dup not muted") end
print(fails == 0 and #markers == 9 and "ALL PASS" or (fails .. " FAILED"))
