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

-- ========= tiny PRNG (standalone, no OS deps) =========
local function u32(x) return x & 0xffffffff end
local function rotl(x, n) return u32(((x << n) | (x >> (32 - n)))) end
local RNG = { s1 = 0x12345678, s2 = 0x9e3779b9, s3 = 0x243f6a88, s4 = 0xb7e15162 }
local function rng_seed_mix(a)
  a = u32(tonumber(a or 0))
  RNG.s1 = rotl(u32(RNG.s1 ~ a), 13)
  RNG.s2 = rotl(u32(RNG.s2 ~ (a * 0x9e3779b1)), 17)
  RNG.s3 = rotl(u32(RNG.s3 ~ (a * 0x85ebca6b)), 7)
  RNG.s4 = rotl(u32(RNG.s4 ~ (a * 0xc2b2ae35)), 11)
end
local function rng_u32()
  local t = RNG.s1 ~ ((RNG.s1 << 11) & 0xffffffff)
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
local function seed_default(extra)
  rng_seed_mix(now_ticks())
  rng_seed_mix(math.random(0, 0x7fffffff))
  rng_seed_mix(tonumber(tostring({}):match("0x(%x+)"), 16) or 0)
  rng_seed_mix(tonumber(extra) or 0)
end
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

-- ========= hex helpers =========
local HEX = {}; for i=0,255 do HEX[i]=string.format("%02X",i) end
local function tohex(s) local t={}; for i=1,#s do t[i]=HEX[s:byte(i)] end; return table.concat(t) end

-- Public low-level
function G.rand_hex(nbytes, opt_seed) seed_default(opt_seed); return tohex(randbytes(nbytes or 16)) end

-- ========= normalize / validate =========
function G.normalize_umid(s) s=tostring(s or ""):gsub("[%s:;-]",""):upper(); return s end
local function is_hex(s) return s:match("^[0-9A-F]+$") ~= nil end
function G.is_umid_basic(s) s=G.normalize_umid(s); return (#s==64) and is_hex(s) end
function G.is_umid_extended(s) s=G.normalize_umid(s); return (#s==128) and is_hex(s) end

-- ========= UMID generators (standards-lite) =========
local function mix_entropy(buf, tag)
  local x = now_ticks() ~ (tonumber(tag or 0) or 0)
  local b = {}; for i=1,16 do local xi=(x>>(((i-1)%4)*8))&0xff; b[i]=string.char(xi) end
  local pre = buf:sub(1,16); local post = buf:sub(17)
  local xored = {}
  for i=1,16 do xored[i]=string.char(pre:byte(i) ~ b[i]:byte(1)) end
  return table.concat(xored) .. post
end

function G.generate_umid_basic(opts)
  opts = opts or {}
  local seed_tag = 0
  if type(opts.seed)=="number" then seed_tag=opts.seed
  elseif type(opts.seed)=="string" then
    for i = 1, #opts.seed do seed_tag = u32(seed_tag ~ (opts.seed:byte(i) << ((i-1)%24))) end
  end
  seed_default(seed_tag)

  local mat = randbytes(16)
  local ins = randbytes(16)

  if type(opts.material)=="string" and #opts.material>0 then
    local acc=0; for i=1,#opts.material do acc=u32(acc ~ ((opts.material:byte(i) or 0)*0x9e3779b1)) end
    rng_seed_mix(acc); mat = mix_entropy(mat, acc)
  end
  if type(opts.instance)=="number" and opts.instance>=0 then
    ins = mix_entropy(ins, opts.instance)
  end

  return tohex(mat .. ins) -- 32 bytes → 64 hex
end

function G.generate_umid_extended(opts)
  local basic = G.generate_umid_basic(opts)             -- 64 hex
  seed_default(#basic)
  local extra = tohex(randbytes(32))                    -- 32 bytes → 64 hex
  return basic .. extra                                 -- 128 hex
end

-- Derive: keep first 32 hex, replace last 32 hex
function G.derive_instance(umid_hex, salt)
  local h = G.normalize_umid(umid_hex or "")
  if #h ~= 64 then return nil, "not a basic UMID" end
  seed_default(tonumber(salt) or 0)
  local tail = G.rand_hex(16)
  return h:sub(1, 32) .. h:sub(33, 64):gsub(".*", function() return tail end)
end

return G
