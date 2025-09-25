--[[
@description Cycle items to PREVIOUS take and fix SrcStart by DesTC (TimeRef + SrcStart)
@version 250925_1935 Non-loop: preserve position on short sources.
@author hsuanice
@about
  Pre-aligns the target take's SrcStart so its Destination Timecode (DesTC = TimeRef + SrcStart)
  matches the active take before cycling to PREVIOUS take (42350). Handles loop/non-loop bounds.
@note
  Requires library: Scripts/hsuanice Scripts/Library/hsuanice_Cycle Take SrcStart.lua
  Optionally uses:  Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua

@changelog
  v250925_1846
  - Update: Added dual-anchor (left/right) alignment logic in library.
    • Prefers left-edge when both valid.
    • Falls back to right-edge when left is invalid.
    • Fallback overlap detection when both anchors invalid, clamps gracefully.
  - Fix: Corrected behavior when active take’s edge extends beyond target take’s source length.
    • Prevents target take from snapping to 0 start when shorter than reference.
    • Maintains sync for trim/extend operations.
  - Keep: Looping takes remain naturally aligned (no special handling required).
  - Update: Next/Previous scripts now compute both DesTC_refL and DesTC_refR and pass to library.
  - Verified: Works correctly for trim, extend, long vs. short takes, looped/non-looped modes.
  v250923_2250
  - Migrate to shared library (Cycle Take SrcStart) with DesTC alignment (DesTC = TimeRef + SrcStart).
  - Fix: Correct TimeRef resolution per target take; eliminates the 2.583333 clamping bug when switching between takes with different TimeRef.
  - Add: SrcStart normalization for loop/non-loop (wrap/clamp) to prevent out-of-bounds and empty waveforms.
  - Add: Multi-item selection support and detailed debug logs per item.
  - Verified: Works reliably after trim/extend and with looped items.
]]--

local r = reaper

-- ===== User options =====
local DEBUG          = true
local HONOR_BOUNDS   = true
local EPS            = 1e-4
-- ========================

local function log(fmt, ...) if DEBUG then r.ShowConsoleMsg((fmt.."\n"):format(...)) end end

-- Load library
local Lib
do
  local p = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Cycle Take SrcStart.lua"
  local ok, mod = pcall(dofile, p)
  if ok and type(mod) == "table" then Lib = mod end
end
if not Lib then
  r.MB("Library not found:\nScripts/hsuanice Scripts/Library/hsuanice_Cycle Take SrcStart.lua", "Error", 0)
  return
end

r.Undo_BeginBlock()
if DEBUG then r.ClearConsole() end

local N = r.CountSelectedMediaItems(0)
log("=== Cycle PREVIOUS (fix SrcStart by DesTC) | selected=%d ===", N)

for i = 0, N-1 do
  local it  = r.GetSelectedMediaItem(0, i)
  local tka = it and r.GetActiveTake(it)
  if not tka then
    log("[item %d] skip: no active take", i+1)
  else
    local desL, trA, sisA = Lib.read_DesTC(it, tka)
    local rateA  = reaper.GetMediaItemTakeInfo_Value(tka, "D_PLAYRATE") or 1
    local iLen   = reaper.GetMediaItemInfo_Value(it, "D_LENGTH") or 0
    local usedA  = iLen * rateA
    local desR   = (desL or 0) + usedA

    local tgt = Lib.prev_take(it, tka)
    if not tgt then
      log("[item %d] skip: no previous take", i+1)
    else
      local changed, info = Lib.fix_Take_To_DesTC(it, tgt, desL or 0, HONOR_BOUNDS, desR)
      if changed then
        log(("[item %d] fix->prev: TimeRef=%.6f  SrcStart %.6f -> %.6f  DesTC_refL=%.6f  DesTC_refR=%.6f  loop=%s src_len=%.6f item_len=%.6f rate=%.6f"):
            format(i+1, info.TimeRef, info.SrcStart_old, info.SrcStart_new, info.DesTC_ref or 0, info.DesTC_ref_right or 0,
                  tostring(info.loop), (info.src_len or 0), (info.item_len or 0), (info.rate or 1)))
        reaper.UpdateItemInProject(it)
      else
        local delta = math.abs((info.DesTC_now or 0) - (info.DesTC_ref or 0))
        if delta <= EPS then
          log(("[item %d] prev: already aligned (ΔDesTC=%.6f)  TimeRef=%.6f  SrcStart=%.6f"):
              format(i+1, delta, info.TimeRef or 0, info.SrcStart_old or 0))
        else
          log(("[item %d] prev: no change (library reported no write), ΔDesTC=%.6f"):format(i+1, delta))
        end
      end
    end
  end
end

-- Now actually cycle to PREVIOUS
r.Main_OnCommand(42350, 0) -- Take: Cycle items to previous take
r.UpdateArrange()
r.Undo_EndBlock("Cycle items to PREVIOUS take (fix SrcStart by DesTC)", -1)
