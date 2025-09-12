--[[
@description hsuanice Metadata Generator (UMID / IDs)
@version 0.1.0
@author hsuanice
@noindex
@about
  ID generators and validators (standards-lite):
  - Generate Basic UMID (aka SMPTE ID) 32 bytes → 64 hex chars
  - Optional "extended-like" 64 bytes → 128 hex chars (opaque)
  - Normalize / validate helpers
  - Deterministic variant (material/instance) for reproducible builds
  - No filesystem writes; pair with hsuanice_Metadata Embed.lua for BWF bext/iXML

@changelog
  v0.1.0
    - Initial: G.generate_umid_basic(), G.generate_umid_extended()
              G.normalize_umid(), G.is_umid_basic(), G.is_umid_extended()
              G.derive_instance(), G.rand_hex()
]]

local G = {}
G.VERSION = "0.1.0"

-- ====== tiny PRNG helpers (standalone, no OS deps) ======
local function u32(x) return x & 0xffffffff end
local function rotl(x, n) return u32(((x << n) | (x >> (32 - n)))) end

-- xorshift-like seeded generator; we blend multiple seeds
local RNG = { s1 = 0x12345678, s2 = 0x9e3779b9, s3 = 0x243f6a88, s4 = 0xb7e15162 }
local function rng_seed_mix(a)
  a = u32(a or 0)
  RNG.s1 = u32(RNG.s1 ~ a); RNG.s1 = rotl(RNG.s1, 13)
  RNG.s2 = u32(RNG.s2 ~ (a * 0x9e3779b1)); RNG.s2 = rotl(RNG.s2, 17)
  RNG.s3 = u32(RNG.s3 ~ (a * 0x85ebca6b)); RNG.s3 = rotl(RNG.s3, 7)
  RNG.s4 = u32(RNG.s4 ~ (a * 0xc2b2ae35)); RNG.s4 = rotl(RNG.s4, 11)
end
local function rng_u32()
  local t = RNG.s1 ~ (RNG.s1 << 11) & 0xffffffff
  RNG.s1, RNG.s2, RNG.s3 = RNG.s2, RNG.s3, RNG.s4
  RNG.s4 = u32(RNG.s4 ~ (RNG.s4 >> 19) ~ (t ~ (t >> 8)))
  return RNG.s4
end
local function now_ticks()
  local p = (reaper and reaper.time_precise) and reaper.time_precise() or os.clock()
  local s = os.time() or 0
  local hi = math.floor((p * 1e6) % 0xffffffff)
  return u32(s ~ hi)
end

-- Blend diverse runtime salts to avoid collisions
local function seed_default(extra)
  rng_seed_mix(now_ticks())
  rng_seed_mix((math.random(0, 0x7fffffff)))
  rng_seed_mix(tonumber(tostring({}):match("0x(%x+)"), 16) or 0)
  rng_seed_mix(extra or 0)
end

-- Return n random bytes (as a Lua string of length n)
local function randbytes(n)
  local out = {}
  for i = 1, n do
    if (i % 4) == 1 then out._cache = rng_u32() end
    local byte = (out._cache >> (8 * ((i-1) % 4))) & 0xff
    out[i] = string.char(byte)
  end
  out._cache = nil
  return table.concat(out)
end

-- ====== hex helpers ======
local HEX = {}
for i = 0,255 do HEX[i] = string.format("%02X", i) end

local function tohex(s)
  local t = {}
  for i = 1, #s do t[i] = HEX[s:byte(i)] end
  return table.concat(t)
end

-- Public: quick hex generator (lower-level utility)
function G.rand_hex(nbytes, opt_seed)
  seed_default(tonumber(opt_seed) or 0)
  return tohex(randbytes(nbytes or 16))
end

-- ====== UMID (standards-lite) ======
-- NOTE:
-- * This produces a 32-byte "Basic-like" UMID: a 64-hex, globally-unique opaque token.
-- * It is NOT claiming strict SMPTE ST 330 field structure (UL/material/instance components),
--   but the length/format matches common DAW/BWF tools' expectations for SMPTE ID (=UMID).
-- * For strict conformance, a future v0.2.x can swap the constructor with a spec-accurate builder.

local function mix_entropy(buf, tag)
  -- XOR some runtime entropy into the first 16 bytes to reduce birthday risks
  local x = now_ticks() ~ (tonumber(tag or 0) or 0)
  local b = {}
  for i = 1, 16 do
    local xi = (x >> (((i-1) % 4) * 8)) & 0xff
    b[i] = string.char(xi)
  end
  return (buf:sub(1,16) ~ table.concat(b)) .. buf:sub(17)
end

-- Lua 5.3+: string XOR helper
getmetatable("").__bxor = function(a, b)
  local out = {}
  for i = 1, #a do out[i] = string.char((a:byte(i) ~ b:byte(i))) end
  return table.concat(out)
end

--- Normalize: remove spaces/colons, force uppercase
function G.normalize_umid(s)
  s = tostring(s or "")
  s = s:gsub("[%s:;-]", "")
  s = s:upper()
  return s
end

--- Validate: 64 hex chars (Basic) or 128 (Extended)
local function is_hex(s)
  return s:match("^[0-9A-F]+$") ~= nil
end
function G.is_umid_basic(s)
  s = G.normalize_umid(s)
  return (#s == 64) and is_hex(s)
end
function G.is_umid_extended(s)
  s = G.normalize_umid(s)
  return (#s == 128) and is_hex(s)
end

--- Generate Basic-like UMID (32 bytes → 64 hex chars)
-- @param opts table|nil: { seed=number|string, material=string, instance=number }
function G.generate_umid_basic(opts)
  opts = opts or {}
  local seed_tag = 0
  if type(opts.seed) == "number" then seed_tag = opts.seed
  elseif type(opts.seed) == "string" then
    local acc = 0
    for i = 1, #opts.seed do acc = u32(acc ~ (opts.seed:byte(i) << ((i-1)%24))) end
    seed_tag = acc
  end
  seed_default(seed_tag)

  -- Construct 32 bytes:
  -- [0..15]: material-ish (random + material hash)
  -- [16..31]: instance-ish (random + instance counter/hash)
  local mat = randbytes(16)
  local ins = randbytes(16)

  -- option: fold "material" string (e.g., srcbase/srcfile) to bias mat
  if type(opts.material) == "string" and #opts.material > 0 then
    local acc = 0
    for i = 1, #opts.material do
      acc = u32(acc ~ ((opts.material:byte(i) or 0) * 0x9e3779b1))
    end
    rng_seed_mix(acc)
    mat = mix_entropy(mat, acc)
  end

  -- option: fold instance number
  if type(opts.instance) == "number" and opts.instance >= 0 then
    ins = mix_entropy(ins, opts.instance)
  end

  local raw = mat .. ins
  return tohex(raw) -- 64 hex
end

--- Generate Extended-like UMID (64 bytes → 128 hex chars)
function G.generate_umid_extended(opts)
  opts = opts or {}
  local basic = G.generate_umid_basic(opts) -- 32B
  seed_default(#basic)
  local extra = randbytes(32)
  return basic .. tohex(extra) -- 128 hex
end

--- Derive a new "instance" UMID from an existing (material-preserving vibe)
-- keeps the first 32 hex, replaces the last 32 with fresh entropy mixed by salt
function G.derive_instance(umid_hex, salt)
  local h = G.normalize_umid(umid_hex or "")
  if #h ~= 64 then return nil, "not a basic UMID" end
  seed_default(tonumber(salt) or 0)
  local tail = tohex(randbytes(16))
  return h:sub(1, 32) .. h:sub(33, 32+32)  -- keep 16B material (32 hex) + old next 16B?
         :gsub(".*", function(_) return h:sub(1,64-32) .. tail end) -- replace last 16B
end

return G
