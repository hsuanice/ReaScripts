-- Mock test for Library/hsuanice_Waveform Sync Core.lua
-- Run: lua ".dev/tests/mock_waveform_sync.lua"   (from the repository root)
-- Synthetic "speech": bursts of low partials (kept under 500 Hz so the 1 kHz mock read does not
-- alias - REAPER's accessor resamples properly). Reference = mix of 3 lavs + noise; target =
-- the 3 lavs (other gains), recorded late by a known offset.

local function fft(a, n, inverse)
  -- in-place iterative radix-2 complex FFT on 1-based interleaved array
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
  a.fft = function(size, permute) assert(size <= 32768 and permute); fft(a, size, false) end
  a.ifft = function(size, permute) assert(size <= 32768 and permute); fft(a, size, true) end
  return a
end

-- deterministic random
local seed = 12345
local function rnd() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end

local function make_voice(dur)
  local bursts, t = {}, 0.3 + rnd()
  while t < dur do
    local len = 0.2 + rnd() * 1.2
    local f0 = 90 + rnd() * 120
    bursts[#bursts + 1] = { s = t, e = t + len, f0 = f0, ph = rnd() * 6, amp = 0.3 + rnd() * 0.7,
      vib = rnd() * 3 }
    t = t + len + 0.2 + rnd() * 2.5
  end
  return function(x)
    for _, b in ipairs(bursts) do
      if x >= b.s and x < b.e then
        local env = math.sin(math.pi * (x - b.s) / (b.e - b.s))
        local f = b.f0 * (1 + 0.03 * math.sin(2 * math.pi * b.vib * x))
        local v = 0
        for h = 1, 4 do
          if f * h < 450 then v = v + math.sin(2 * math.pi * f * h * (x - b.s) + b.ph * h) / h end
        end
        return env * b.amp * v
      end
    end
    return 0
  end
end

local function run_case(name, true_offset, opts)
  opts = opts or {}
  local dur = opts.dur or 140
  local voices = { make_voice(dur + 20), make_voice(dur + 20), make_voice(dur + 20) }
  local unrelated = opts.unrelated and { make_voice(dur + 20), make_voice(dur + 20), make_voice(dur + 20) }
  local A_start_true = 5            -- true time when recorder A started
  local P = 1000                    -- project position of both items (same TC)
  local B_start_true = A_start_true + true_offset
  local rate = opts.rate or 1       -- B clock speed (drift)
  -- sources: functions of source time
  local ref_src = function(ts)
    local tau = ts + A_start_true
    local vs = unrelated or voices
    local n = (rnd() - 0.5) * 0.02
    return 0.8 * vs[1](tau) + 0.6 * vs[2](tau) + 0.7 * vs[3](tau) + n
  end
  local lav = function(k)
    return function(ts)
      local tau = ts * rate + B_start_true
      return (k == 1 and 1.3 or k == 2 and 0.5 or 0.9) * voices[k](tau) + (rnd() - 0.5) * 0.01
    end
  end
  local takes = {
    ref = { fn = ref_src, pos = P },
    l1 = { fn = lav(1), pos = P }, l2 = { fn = lav(2), pos = P }, l3 = { fn = lav(3), pos = P },
  }
  reaper = {
    new_array = new_array,
    CreateTakeAudioAccessor = function(take) return take end,
    DestroyAudioAccessor = function() end,
    GetMediaItemTake_Source = function(take) return take end,
    GetMediaSourceNumChannels = function() return 1 end,
    GetMediaSourceSampleRate = function() return 48000 end,
    GetAudioAccessorSamples = function(acc, sr, nch, t, n, buf)
      for i = 0, n - 1 do buf[i + 1] = acc.fn(t + i / sr) end
      return 1
    end,
  }
  local WS = dofile("Library/hsuanice_Waveform Sync Core.lua")
  local t0 = os.clock()
  local res = WS.find_offset({ { take = takes.ref, pos = P } },
    { { take = takes.l1, pos = P }, { take = takes.l2, pos = P }, { take = takes.l3, pos = P } },
    P, P + dur - true_offset, { fps = 24 })
  local err_ms = res.offset and (res.offset - true_offset) * 1000
  print(string.format("%-28s ok=%-5s offset=%s err=%s ms ratio=%s drift=%s reason=%s  (%.1fs)",
    name, tostring(res.ok), res.offset and string.format("%.5f", res.offset) or "-",
    err_ms and string.format("%.3f", err_ms) or "-", res.ratio and string.format("%.1f", res.ratio) or "-",
    res.drift and string.format("%.4f", res.drift) or "-", tostring(res.reason), os.clock() - t0))
  for _, c in ipairs(res.checks) do
    print("    check", c.offset and string.format("%.5f", c.offset) or c.failed, c.ratio and string.format("%.1f", c.ratio))
  end
  return res
end

local fails = 0
local function expect(cond, msg) if not cond then fails = fails + 1; print("  FAIL: " .. msg) end end

local r1 = run_case("late 3s16f", 3 + 16 / 24)
expect(r1.ok and math.abs(r1.offset - (3 + 16 / 24)) < 1 / 48000 * 2, "3s16f within 2 samples")
local r2 = run_case("early -2.1 s", -2.1)
expect(r2.ok and math.abs(r2.offset + 2.1) < 1 / 48000 * 2, "-2.1 s within 2 samples")
local r3 = run_case("short take 12 s", 1.234, { dur = 12 })
expect(r3.ok and math.abs(r3.offset - 1.234) < 1 / 48000 * 2, "short take")
local r4 = run_case("unrelated audio", 3, { unrelated = true })
expect(not r4.ok, "unrelated must not be ok")
local r5 = run_case("drift 0.1%", 3, { rate = 1.001 })
expect(not r5.ok and r5.reason, "drift must not be moved")
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
