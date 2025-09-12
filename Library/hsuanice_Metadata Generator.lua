--[[
@description hsuanice Metadata Generator (UMID / IDs) — STRICT
@version 0.2.1
@author hsuanice
@noindex
@about
  Strict UMID (SMPTE ST 330) lengths & structured layout:
  - Basic UMID = 32 bytes → 64 hex (UL + material/instance packed; fixed lengths)
  - Extended UMID = 64 bytes → 128 hex (Basic + 32B source pack: time/device/GPS placeholder)
  - Normalization/validation (length & hex)
  - Field breakdown helper (UL / MATERIAL packed)
  - Backward alias: G.generate_umid_basic = G.generate_umid_basic_strict

@changelog
  v0.2.1 (2025-09-12)
    - Added: G.format_umid_protools_style()
      * Formats a 32-byte Basic UMID into Pro Tools display style
        (lowercase hex + dash grouping 26-6-16-12-4).
      * Useful for log/console/debug output to match Pro Tools SMPTE ID field.
    - No changes to UMID generation logic or Embed/Read compatibility.
    - Backward compatibility: existing functions unchanged.

  v0.2.0
    - Strict lengths & segment layout for UMID (Basic 32B / Extended 64B)
    - Configurable UMID Universal Label (UL) constant (16B)
    - Deterministic material/instance packing (material 16B with instance folded into tail 8B)
    - Helper: G.explain_basic_layout()
    - Aliases: G.generate_umid_basic = _strict; G.generate_umid_extended = _strict
]]

local G = {}
G.VERSION = "0.2.1
-- ===== hex helpers =====
local HEX = {}; for i=0,255 do HEX[i]=string.format("%02X",i) end
local function tohex(s) local t={}; for i=1,#s do t[i]=HEX[s:byte(i)] end; return table.concat(t) end
local function fromhex(h)
  h=(tostring(h or "")):gsub("%s+",""); if #h%2==1 then return nil end
  local out={}; for i=1,#h,2 do out[#out+1]=string.char(tonumber(h:sub(i,i+1),16)) end; return table.concat(out)
end

-- ===== light hash & RNG =====
local function u32(x) return x & 0xffffffff end
local function rotl(x,n) return u32(((x<<n)|(x>>(32-n)))) end
local H = {a=0x243F6A88,b=0x85A308D3,c=0x13198A2E,d=0x03707344}
local function mix(s)
  for i=1,#s do
    local b=s:byte(i); H.a=u32(H.a ~ b*0x9E37); H.b=u32(H.b ~ b*0x85EB)
    H.c=rotl(u32(H.c ~ b),5); H.d=u32(H.d ~ b*0xC2B2)
  end
  return string.pack(">I4I4I4I4", H.a, H.b, H.c, H.d) .. string.pack(">I4I4I4I4", H.d, H.c, H.b, H.a) -- 32B pseudo
end
local R={x=0x9E3779B9}; local function seed(extra)
  local t=os.time() or 0; local p=(reaper and reaper.time_precise) and reaper.time_precise() or os.clock()
  R.x = u32(R.x ~ t ~ math.floor((p*1e6)%0xffffffff) ~ (tonumber(extra) or 0))
end
local function ru32() R.x = u32(R.x ~ (R.x<<13)); R.x = u32(R.x ~ (R.x>>17)); R.x = u32(R.x ~ (R.x<<5)); return R.x end
local function randbytes(n) local t={}; for i=1,n do if (i-1)%4==0 then t._=ru32() end; t[i]=string.char((t._>>(8*((i-1)%4)))&0xff) end; t._=nil; return table.concat(t) end

-- ===== constants (strict lengths) =====
local L = { BASIC=32, EXT=64, UL=16, MAT=16, INS=8, EXT_PAD=32 }
-- Default UMID UL (16B). 若你有公司/專案指定 UL，改這裡即可。
local DEFAULT_UMID_UL_HEX = "060E2B340101010101010F1313000000"

-- ===== API: normalize / validate =====
function G.normalize_umid(h) h=(tostring(h or "")):gsub("[%s:;-]",""):upper(); return h end
local function is_hex(s) return s:match("^[0-9A-F]+$")~=nil end
function G.is_umid_basic(h)   h=G.normalize_umid(h); return (#h==L.BASIC*2) and is_hex(h)   end
function G.is_umid_extended(h) h=G.normalize_umid(h); return (#h==L.EXT*2)   and is_hex(h)   end

-- ===== strict builders =====
local function build_material_16B(opts)
  local src = (opts.material or "") .. "|" .. (opts.originatorref or "") .. "|" .. (opts.srcpath or "")
  if src=="" then src = tohex(randbytes(16)) end
  local dig = mix(src)         -- 32B pseudo digest
  return dig:sub(1, L.MAT)     -- take 16B
end
local function build_instance_8B(opts)
  local tag = tostring(opts.instance or "0")
  local d = mix(tag .. "|" .. tostring(opts.seed or "")) -- 32B
  return d:sub(1, L.INS)                                 -- 8B
end

-- Basic 32B = UL(16) + MATERIAL(16 with instance folded)
local function build_basic32_bytes(opts)
  local ul  = fromhex(DEFAULT_UMID_UL_HEX)
  local mat = build_material_16B(opts)
  local ins = build_instance_8B(opts)
  -- 將 instance 摺入 material 後 8B（確保總長 32B；未來如需完全位址化，可改為顯式欄位）
  local head = mat:sub(1, L.MAT - L.INS) -- 8B
  local tail = mat:sub(L.MAT - L.INS + 1) -- 8B
  local xored = {}
  for i=1,L.INS do xored[i]=string.char((tail:byte(i) ~ ins:byte(i)) & 0xFF) end
  local packed = head .. table.concat(xored) -- 16B
  return ul .. packed -- 32B
end

function G.generate_umid_basic_strict(opts) opts=opts or {}; seed(opts.seed); return tohex(build_basic32_bytes(opts)) end

function G.generate_umid_extended_strict(opts)
  local basic = fromhex(G.generate_umid_basic_strict(opts))
  -- 32B source pack：UTC秒(4) + usec(4) + device(8) + geo(16; 預設 0)
  local t=os.time() or 0; local p=(reaper and reaper.time_precise) and reaper.time_precise() or os.clock()
  local secs = string.pack(">I4", t & 0xffffffff)
  local usec = string.pack(">I4", math.floor((p*1e6)%0xffffffff))
  local dev  = mix(reaper and reaper.GetOS() or "unknown"):sub(1,8)
  local geo  = string.rep("\0", 16)
  local sp   = secs .. usec .. dev .. geo
  return tohex(basic .. sp) -- 64B → 128 hex
end

-- helper: breakdown
function G.explain_basic_layout(h)
  h = G.normalize_umid(h); if #h < 64 then return { ok=false, err="length<64" } end
  return { ok=true, UL=h:sub(1,32), MATERIAL_packed=h:sub(33,64),
           note="UL(16B) + material(16B with instance folded into last 8B)." }
end

--- Format UMID like Pro Tools shows (26-6-16-12-4 groups, lowercase + dashes)
function G.format_umid_protools_style(hex)
  local h = G.normalize_umid(hex):lower()
  if #h ~= 64 then return h end -- only valid for Basic 32B
  return table.concat({
    h:sub(1,26),
    h:sub(27,32),
    h:sub(33,48),
    h:sub(49,60),
    h:sub(61,64)
  }, "-")
end

-- backward aliases for drop-in replacement
G.generate_umid_basic    = G.generate_umid_basic_strict
G.generate_umid_extended = G.generate_umid_extended_strict

return G

