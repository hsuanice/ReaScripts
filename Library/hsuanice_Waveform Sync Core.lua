--[[
@description Waveform Sync Core - find the time offset between two recordings of the same sound
@version 26.1103.1536pre1
@author hsuanice
@noindex
@about
  Shared library (used by Dual Recorder Sync; meant for Conform List Browser later).

  WS.find_offset(ref, tgt, span_start, span_end, opts)
    ref, tgt : lists of { take = MediaItem_Take, pos = item position (s) } - each list is summed
               to mono (e.g. the three lavs of a second recorder against its mix-in)
    span     : project time range of the target to analyse
    returns  { ok, offset (s, add to the target position), samples, sr, ratio, checks = {...},
               drift (s) or nil, reason }

  Method: GCC-PHAT cross-correlation (phase transform: only timing counts, not level or EQ).
  Coarse pass at 1 kHz over up to +/- MAX_LAG_SEC on the loudest 10 s near the start and near the
  end of the target, then 8 kHz on the loudest 4 s (+/- 3 ms), then the source rate on the
  loudest 0.6 s (+/- 0.3 ms) for the exact sample.
  Both checks must agree within one video frame, else nothing is returned as ok (drift or wrong
  match - shown for human review, never guessed); when only one of the two matches, it must be
  very clear (peak ratio >= 2 x MIN_RATIO).
  REAPER's audio accessor reads nothing inside a Lua coroutine: call from a plain defer cycle.

  Written with Claude Code (AI); designed and tested by hsuanice.
--]]
local r = reaper
local M = {}

M.COARSE_SR      = 1000   -- coarse analysis rate (Hz)
M.CHUNK_SEC      = 10     -- target chunk length for the coarse pass
M.MAX_LAG_SEC    = 10     -- search range +/- (s)
-- Refining passes after the coarse one: rate (nil = source rate), search +/- (s), window (s).
-- The 8 kHz pass uses a long window so a voiced (periodic) sound cannot lock one pitch period off;
-- the last pass only has to pick the exact sample.
M.REFINE = { { sr = 8000, lag = 0.003, win = 4 }, { sr = nil, lag = 0.0003, win = 0.6 } }
M.MIN_RATIO      = 2.0    -- peak / next peak (outside +/- 20 ms) needed to trust a match
M.FFT_MAX        = 32768  -- REAPER array FFT limit (complex points)
local READ_BLOCK = 8192

local function open(list)
  for _, s in ipairs(list) do
    s.acc = r.CreateTakeAudioAccessor(s.take)
    local src = r.GetMediaItemTake_Source(s.take)
    s.nch = math.max(1, src and r.GetMediaSourceNumChannels(src) or 1)
  end
end

local function close(list)
  for _, s in ipairs(list) do
    if s.acc then r.DestroyAudioAccessor(s.acc); s.acc = nil end
  end
end

-- Mono sum of all sources from project time t0, n samples at sr -> plain table (1-based)
local function read_mono(list, t0, n, sr)
  local out = {}
  for i = 1, n do out[i] = 0 end
  for _, s in ipairs(list) do
    local nch = s.nch
    local buf = r.new_array(READ_BLOCK * nch)
    local done = 0
    while done < n do
      local cnt = math.min(READ_BLOCK, n - done)
      buf.clear()
      r.GetAudioAccessorSamples(s.acc, sr, nch, t0 + done / sr - s.pos, cnt, buf)
      for i = 0, cnt - 1 do
        local v = 0
        for c = 1, nch do v = v + buf[i * nch + c] end
        out[done + i + 1] = out[done + i + 1] + v
      end
      done = done + cnt
    end
  end
  return out
end

local function next_pow2(n)
  local p = 16
  while p < n do p = p * 2 end
  return p
end

-- GCC-PHAT of a (longer, starts lag_range samples earlier) against b.
-- Returns lag in samples (a time = b time + lag), peak ratio, or nil when it cannot run.
local function gcc_phat(a, b, lag_range)
  local N = next_pow2(#a)
  if N > M.FFT_MAX or 2 * lag_range > N - #b then return nil end
  local A, B = r.new_array(2 * N), r.new_array(2 * N)
  A.clear(); B.clear()
  for i = 1, #a do A[2 * i - 1] = a[i] end
  for i = 1, #b do B[2 * i - 1] = b[i] end
  A.fft(N, true); B.fft(N, true)
  local peak_mag = 0
  for k = 0, N - 1 do
    local ar, ai, br, bi = A[2 * k + 1], A[2 * k + 2], B[2 * k + 1], B[2 * k + 2]
    local re, im = ar * br + ai * bi, ai * br - ar * bi
    local m = math.sqrt(re * re + im * im)
    if m > peak_mag then peak_mag = m end
    A[2 * k + 1], A[2 * k + 2] = re, im
  end
  if peak_mag <= 0 then return nil end
  local eps = peak_mag * 1e-4
  for k = 0, N - 1 do
    local re, im = A[2 * k + 1], A[2 * k + 2]
    local m = math.sqrt(re * re + im * im) + eps
    A[2 * k + 1], A[2 * k + 2] = re / m, im / m
  end
  A.ifft(N, true)
  local best, best_l = -1, 0
  for l = 0, 2 * lag_range do
    local v = math.abs(A[2 * l + 1])
    if v > best then best, best_l = v, l end
  end
  return best_l, best, A
end

-- Peak ratio against the best value outside +/- excl samples of the peak
local function peak_ratio(A, lag_range, peak_l, peak, excl)
  local second = 0
  for l = 0, 2 * lag_range do
    if math.abs(l - peak_l) > excl then
      local v = math.abs(A[2 * l + 1])
      if v > second then second = v end
    end
  end
  return second > 0 and peak / second or math.huge
end

-- Start of the loudest window of len samples inside env[from .. to] (1-based, inclusive)
local function loudest(env, from, to, len)
  if to - from + 1 <= len then return from end
  local sum = 0
  for i = from, from + len - 1 do sum = sum + env[i] end
  local best, best_i = sum, from
  for i = from + 1, to - len + 1 do
    sum = sum + env[i + len - 1] - env[i - 1]
    if sum > best then best, best_i = sum, i end
  end
  return best_i
end

local function ref_rate(ref)
  local src = r.GetMediaItemTake_Source(ref[1].take)
  local sr = src and r.GetMediaSourceSampleRate(src) or 0
  return (sr and sr > 0) and sr or 48000
end

-- One check: coarse pass on the chunk starting at project time t0 (chunk_sec long), then the
-- refining passes, each on the loudest window inside the chunk (env = 100 Hz energy, env_t0)
local function check(ref, tgt, t0, chunk_sec, env, env_t0, sr)
  local cs, L = M.COARSE_SR, math.floor(M.MAX_LAG_SEC * M.COARSE_SR)
  local S = math.floor(chunk_sec * cs)
  local b = read_mono(tgt, t0, S, cs)
  local a = read_mono(ref, t0 - L / cs, S + 2 * L, cs)
  local l, peak, A = gcc_phat(a, b, L)
  if not l then return nil, "silent or too long" end
  local ratio = peak_ratio(A, L, l, peak, math.floor(0.02 * cs))
  if ratio < M.MIN_RATIO then return nil, string.format("no clear match (%.1f)", ratio), ratio end
  local offset = (l - L) / cs
  local smp
  local first = math.floor((t0 - env_t0) * 100) + 1
  local last = math.min(#env, first + math.floor(chunk_sec * 100) - 1)
  for _, pass in ipairs(M.REFINE) do
    local rate = pass.sr or sr
    local Lp = math.max(2, math.floor(pass.lag * rate + 0.5))
    local n = math.floor(math.min(pass.win * rate, chunk_sec * rate, M.FFT_MAX - 2 * Lp - 64))
    local w0 = loudest(env, first, last, math.max(1, math.floor(n / rate * 100)))
    local ft0 = env_t0 + (w0 - 1) / 100
    local bf = read_mono(tgt, ft0, n, rate)
    local af = read_mono(ref, ft0 + offset - Lp / rate, n + 2 * Lp, rate)
    local lf = gcc_phat(af, bf, Lp)
    if not lf then return nil, "refining pass failed", ratio end
    offset = offset + (lf - Lp) / rate
    if not pass.sr then smp = math.floor(offset * rate + 0.5) end
  end
  smp = smp or math.floor(offset * sr + 0.5)
  return { samples = smp, offset = smp / sr, ratio = ratio, at = t0 }
end

function M.find_offset(ref, tgt, span_start, span_end, opts)
  opts = opts or {}
  local fps = opts.fps or 24
  local res = { ok = false, checks = {} }
  if #ref == 0 or #tgt == 0 then res.reason = "nothing to compare"; return res end
  local sr = ref_rate(ref)
  res.sr = sr
  open(ref); open(tgt)
  local ok, err = pcall(function()
    local cs = M.COARSE_SR
    local span = span_end - span_start
    local n = math.floor(span * cs)
    if n < cs then res.reason = "too short"; return end
    -- 10 ms energy envelope of the target to place the chunks
    local mono = read_mono(tgt, span_start, n, cs)
    local hop = math.floor(cs / 100)
    local env = {}
    for i = 1, math.floor(n / hop) do
      local e = 0
      for j = (i - 1) * hop + 1, i * hop do e = e + mono[j] * mono[j] end
      env[i] = e
    end
    local chunk = math.min(M.CHUNK_SEC, span)
    local clen = math.floor(chunk * 100)
    local starts
    if span >= 2.5 * chunk then
      local half = math.floor(#env / 2)
      starts = { loudest(env, 1, half, clen), loudest(env, half + 1, #env, clen) }
    else
      starts = { loudest(env, 1, #env, clen) }
    end
    for _, st in ipairs(starts) do
      local t0 = span_start + (st - 1) / 100
      local c, why, ratio = check(ref, tgt, t0, chunk, env, span_start, sr)
      res.checks[#res.checks + 1] = c or { failed = why, ratio = ratio, at = t0 }
    end
  end)
  close(ref); close(tgt)
  if not ok then res.reason = tostring(err); return res end
  if res.reason then return res end

  local good = {}
  for _, c in ipairs(res.checks) do if not c.failed then good[#good + 1] = c end end
  if #good == 0 then
    res.reason = res.checks[1] and res.checks[1].failed or "no clear match"
    return res
  end
  if #good == 2 then
    res.drift = good[2].offset - good[1].offset
    if math.abs(res.drift) > 1 / fps then
      res.reason = "start and end disagree by more than 1 frame (drift or wrong match)"
      return res
    end
    res.samples = math.floor((good[1].samples + good[2].samples) / 2 + 0.5)
  else
    -- one check only: trusted when it was the only one, or when it is very clear
    if #res.checks > 1 and good[1].ratio < 2 * M.MIN_RATIO then
      res.reason = "only one of two checks matched, and not clearly"
      return res
    end
    res.samples = good[1].samples
  end
  res.ratio = good[1].ratio
  for _, c in ipairs(good) do res.ratio = math.min(res.ratio, c.ratio) end
  res.offset = res.samples / sr
  res.ok = true
  return res
end

return M
