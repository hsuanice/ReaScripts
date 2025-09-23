--[[
@description Cycle Take SrcStart calculator
@version 250923_2250 OK
@author hsuanice
@about
  Utility helpers for aligning takes by Destination Timecode (DesTC = TimeRef + SrcStart).
  Reads BWF TimeRef (BWF Start Offset), computes/sets SrcStart, and supports loop/non-loop bounds.
@note
  No external CLI. Optionally uses: Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua

@changelog
  v250923_2250
  - Fix: TimeRef is now read from the target take's source (BWF:TimeReference), not item-level metadata; prevents misalignment when the active take differs.
  - Add: SrcStart normalization (non-loop clamp, loop wrap) to keep offsets in valid bounds and avoid empty content.
  - Add: DesTC helpers (DesTC = TimeRef + SrcStart) and a one-call fixer for aligning a target take to a reference DesTC.
  - Improve: Debug info (src_len, item_len, rate, loop) returned from the fixer for easier inspection.
  - Verified: Correct behavior after trim/extend and with looped items.

  v250923_2207
  - Initial release.
]]--

local r = reaper
local M = {}

----------------------------------------------------------------
-- Optional: load your metadata reader (preferred, read-only)
----------------------------------------------------------------
local META do
  local p = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua"
  local ok, ret = pcall(dofile, p)
  if ok and type(ret) == "table" then META = ret end
end

----------------------------------------------------------------
-- Utilities
----------------------------------------------------------------
local function parse_num(s)
  if not s or s == "" then return nil end
  local t = (tostring(s):gsub(",", "")):gsub("%s+", "")
  if t:match("^0[xX]%x+$") then return tonumber(t) or tonumber(t:sub(3), 16) end
  return tonumber(t)
end

local function clamp(v,a,b) if v < a then return a elseif v > b then return b else return v end end

----------------------------------------------------------------
-- Basic getters/setters
----------------------------------------------------------------
function M.get_src(tk) return tk and r.GetMediaItemTake_Source(tk) or nil end
function M.get_sr(src) return (src and r.GetMediaSourceSampleRate(src)) or 0 end
function M.get_sis(tk) return r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0 end
function M.set_sis(tk, v) return r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", v or 0) end
function M.get_item(tk) return tk and r.GetMediaItemTake_Item(tk) or nil end

----------------------------------------------------------------
-- Read TimeRef (seconds) with samplerate; prefer metadata lib
-- returns: timeRef_sec, timeRef_samples, samplerate, src
----------------------------------------------------------------
function M.read_TimeRef(item, take)
  take = take or (item and r.GetActiveTake(item)) or take
  if not take then return 0,0,0,nil end

  local src = M.get_src(take)
  local sr  = M.get_sr(src)
  local tr_smp = 0

  -- ALWAYS read TimeRef from the TAKE'S SOURCE (not from item-level META)
  if src then
    local ok, v = r.GetMediaFileMetadata(src, "BWF:TimeReference")
    if ok and v and v ~= "" and v ~= "[Binary data]" then
      tr_smp = parse_num(v) or 0
    end
    if tr_smp == 0 and r.CF_GetMediaSourceMetadata then
      local out = ""
      for _, k in ipairs({"TimeReference","TIMEREFERENCE","ORIGREF"}) do
        local ok2, vv = r.CF_GetMediaSourceMetadata(src, k, out)
        if ok2 and vv and vv ~= "" then
          tr_smp = parse_num(vv) or 0
          if tr_smp > 0 then break end
        end
      end
    end
  end

  -- If samplerate is missing, optionally consult META just for SR
  if (not sr or sr <= 0) and META and item then
    local f = META.collect_item_fields(item)
    if f and f.samplerate then
      local n = parse_num(f.samplerate) or 0
      if n > 0 then sr = n end
    end
  end

  local tr_sec = (sr > 0 and tr_smp > 0) and (tr_smp / sr) or 0
  return tr_sec, tr_smp, sr, src
end

----------------------------------------------------------------
-- DesTC = TimeRef + SrcStart  (Destination Timecode / absolute source position)
-- returns: desTC_sec, timeRef_sec, srcStart_sec, samplerate, src
----------------------------------------------------------------
function M.read_DesTC(item, take)
  take = take or (item and r.GetActiveTake(item)) or take
  if not take then return 0,0,0,0,nil end
  local tr_sec, _, sr, src = M.read_TimeRef(item, take)
  local sis = M.get_sis(take)
  return (tr_sec + sis), tr_sec, sis, sr, src
end

----------------------------------------------------------------
-- Normalize SrcStart for loop/non-loop to avoid empty content.
-- If honor_bounds=true:
--   non-loop: clamp to [0, src_len - item_len*rate]
--   loop    : wrap into [0, src_len)
----------------------------------------------------------------
function M.normalize_SrcStart(item, take, src, sis_new, honor_bounds)
  if not honor_bounds then return sis_new end
  local loop     = (r.GetMediaItemInfo_Value(item, "B_LOOPSRC") or 0) == 1
  local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local rate     = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
  local src_len  = select(1, r.GetMediaSourceLength(src)) or 0
  local used     = item_len * rate

  if src_len <= 0 then return math.max(0, sis_new) end
  if loop then
    local m = sis_new % src_len
    if m < 0 then m = m + src_len end
    return m
  else
    local max_start = math.max(0, src_len - used)
    return clamp(sis_new, 0, max_start)
  end
end

----------------------------------------------------------------
-- Compute target SrcStart so that its DesTC equals a reference value.
-- Params:
--   item, target_take, desTC_ref, honor_bounds (bool)
-- Returns:
--   changed(bool), info(table)
--     info = { TimeRef=..., SrcStart_old=..., SrcStart_new=..., DesTC_now=..., DesTC_ref=..., SR=..., src_len=..., loop=..., item_len=..., rate=... }
----------------------------------------------------------------
function M.fix_Take_To_DesTC(item, target_take, desTC_ref, honor_bounds)
  if not target_take then return false, {} end
  local des_now, tr_sec, sis_old, sr, src = M.read_DesTC(item, target_take)
  local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
  local rate     = r.GetMediaItemTakeInfo_Value(target_take, "D_PLAYRATE") or 1
  local src_len  = select(1, r.GetMediaSourceLength(src)) or 0
  local loop     = (r.GetMediaItemInfo_Value(item, "B_LOOPSRC") or 0) == 1

  if math.abs(des_now - desTC_ref) < 1e-4 then
    return false, { TimeRef=tr_sec, SrcStart_old=sis_old, DesTC_now=des_now, DesTC_ref=desTC_ref, SR=sr, src_len=src_len, loop=loop, item_len=item_len, rate=rate }
  end

  local sis_new = desTC_ref - tr_sec
  sis_new = M.normalize_SrcStart(item, target_take, src, sis_new, honor_bounds ~= false)
  M.set_sis(target_take, sis_new)

  return true, {
    TimeRef=tr_sec, SrcStart_old=sis_old, SrcStart_new=sis_new,
    DesTC_now=des_now, DesTC_ref=desTC_ref, SR=sr, src_len=src_len, loop=loop,
    item_len=item_len, rate=rate
  }
end

----------------------------------------------------------------
-- Take navigation helpers
----------------------------------------------------------------
function M.next_take(item, cur_take)
  local n = r.CountTakes(item); if n <= 0 then return nil end
  local idx = r.GetMediaItemTakeInfo_Value(cur_take, "IP_TAKENUMBER")
  return r.GetMediaItemTake(item, (idx + 1) % n)
end

function M.prev_take(item, cur_take)
  local n = r.CountTakes(item); if n <= 0 then return nil end
  local idx = r.GetMediaItemTakeInfo_Value(cur_take, "IP_TAKENUMBER")
  return r.GetMediaItemTake(item, (idx - 1) % n)
end

return M
