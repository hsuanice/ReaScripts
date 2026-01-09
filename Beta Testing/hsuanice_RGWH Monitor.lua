--[[
@description RGWH Monitor - Console Monitor for Items and Units
@version 0.1.1
@author hsuanice
@provides
  [main] Beta Testing/hsuanice_RGWH Monitor.lua
  Library/hsuanice_Metadata Read.lua
@note
Console monitor for units (SINGLE/TOUCH/CROSSFADE/MIXED),
item details, FX states, and # markers.
Linear volume only (no dB).

@changelog
  0.1.1 [v260109.1245]
    - Added: File output option to avoid console truncation
      • Set OUTPUT_TO_FILE = true to write to file instead of console
      • Output file: Scripts/hsuanice Scripts/Tools/RGWH_Monitor_Output.txt
      • File is cleared at each script run (append mode during run)
      • Falls back to console if file write fails
    - Purpose: Enable testing all items at once without console buffer limits
  0.1.0 [v251113.2345]
    - Added: Track channel count display in track summary line
      • Output example: "Track #170: items=2 units=2 track_channels=2"
      • Helps debug channel count changes during operations
      • Uses I_NCHAN property (defaults to 2 if not available)
    - Purpose: Track channel count debugging for multi-channel workflows
    - SourceTR/SIS/ABS display now shows raw domain value first
      • With converted value in parentheses for cross-check
      • e.g. "TR=929132000 smp (19356.9166666667s)"
    - Added run_id() implementation using reaper.time_precise()
    - Improved precision visibility: full double values are kept
    - Added: Read and display BWF:TimeReference (TR), Start-in-Source (SIS), and computed ABS time
    - Integrated hsuanice_Metadata Read.lua for robust metadata parsing
    - Output example: "sourceTC: TR=19459.708333(s) [934066000 smp @ 48000 Hz]  SIS=5.583333(s)  ABS=19465.291667(s)"
    - Added per-member channel info
      • src = media source channel count
      • track = track channel count
      • chanmode = take channel mode (integer)
    - Output example: "channels: src=2  track=6  chanmode=0"
    - Useful to distinguish mono/multi-channel material and routing
]]--


local r = reaper

-- Load metadata helper library (no external tools required)
local META = nil
do
  local meta_path = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Read.lua"
  local ok, ret = pcall(dofile, meta_path)
  if ok and type(ret) == "table" then
    META = ret
  else
    META = nil -- fallback will be used if not available
  end
end


------------------------------------------------------------
-- action IDs (Main section)
------------------------------------------------------------
local CMD_RIPPLE_PER    = 40310  -- Options: Toggle ripple editing per-track
local CMD_RIPPLE_ALL    = 40311  -- Options: Toggle ripple editing all tracks
local CMD_TRIM_BEHIND   = 41117  -- Options: Trim content behind media items when editing

------------------------------------------------------------
-- utils
------------------------------------------------------------
local function printf(fmt, ...)
  local msg = string.format((fmt or "").."\n", ...)

  if OUTPUT_TO_FILE then
    -- Write to file
    local file = io.open(OUTPUT_FILE, "a")  -- append mode
    if file then
      file:write(msg)
      file:close()
    else
      -- Fallback to console if file fails
      r.ShowConsoleMsg("[File write failed, using console] " .. msg)
    end
  else
    -- Write to console
    r.ShowConsoleMsg(msg)
  end
end

-- Clear output file at script start (only when file output is enabled)
local function init_output_file()
  if OUTPUT_TO_FILE then
    local file = io.open(OUTPUT_FILE, "w")  -- overwrite mode to clear
    if file then
      file:write("")  -- write empty content to clear file
      file:close()
      -- Notify user via console that file output is active
      r.ShowConsoleMsg(string.format("[RGWH Monitor] Output redirected to:\n%s\n", OUTPUT_FILE))
    else
      r.ShowConsoleMsg("[RGWH Monitor] ERROR: Cannot create output file. Falling back to console.\n")
    end
  end
end

local function sec_to_hhmmss(sec)
  if not sec then return "00:00:00.000" end
  local n = math.max(0, sec)
  local h = math.floor(n/3600); n = n - h*3600
  local m = math.floor(n/60);   n = n - m*60
  return string.format("%02d:%02d:%06.3f", h, m, n)
end

-- random run id
math.randomseed(os.time() + math.floor(reaper.time_precise()*1000))
local function run_id()
  local x = math.random(0, 0xFFFF)
end

-- ===== OUTPUT OPTIONS (declare before function definitions) =====
OUTPUT_TO_FILE = true  -- Set to true to write to file instead of console
OUTPUT_FILE = r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Tools/RGWH_Monitor_Output.txt"

-- ===== User display options =====
local UI_DECIMALS = 10  -- seconds printed with this many decimals

-- ===== Formatting helpers (display only) =====
local function fmt_sec_d(sec)
  return string.format("%."..UI_DECIMALS.."f", (sec or 0))
end

local function sec_to_int_samples(sec, sr)
  sr = (sr and sr > 0) and sr or (reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000)
  return math.floor((sec or 0) * sr + 0.5)
end

local function fmt_secs_from_samples(smp, sr, decimals)
  sr = (sr and sr > 0) and sr or (reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 48000)
  decimals = decimals or UI_DECIMALS
  local sec = (smp or 0) / sr
  local s   = string.format("%."..decimals.."f", sec)
  -- Append ellipsis when formatting lost sample-level fidelity
  local back = math.floor(sec * sr + 0.5)
  local ell  = (back ~= (smp or 0)) and "…" or ""
  return s .. ell
end

------------------------------------------------------------
-- ExtState (namespace RGWH)
------------------------------------------------------------
local NS = "RGWH"

local function get_ext_str(k, d)
  local ok, val = r.GetProjExtState(0, NS, k)
  if ok == 1 and val ~= "" then return val end
  return d
end

local function get_ext_num(k, d)
  local s = get_ext_str(k, nil)
  if not s then return d end
  local v = tonumber(s)
  return v or d
end

local DEFAULTS = {
  HANDLE_MODE    = "seconds",
  HANDLE_SECONDS = 3.0,
  EPSILON_MODE   = "frames",
  EPSILON_VALUE  = 0.5,
  DEBUG_LEVEL    = 1,
}

local function current_settings()
  local fps = r.TimeMap_curFrameRate and (r.TimeMap_curFrameRate(0) or 30.0) or 30.0
  local sr  = r.GetSetProjectInfo and (r.GetSetProjectInfo(0,"PROJECT_SRATE",0,false) or 48000) or 48000

  local HANDLE_MODE    = get_ext_str("HANDLE_MODE",    DEFAULTS.HANDLE_MODE)
  local HANDLE_SECONDS = get_ext_num("HANDLE_SECONDS", DEFAULTS.HANDLE_SECONDS)
  local EPSILON_MODE   = get_ext_str("EPSILON_MODE",   DEFAULTS.EPSILON_MODE)
  local EPSILON_VALUE  = get_ext_num("EPSILON_VALUE",  DEFAULTS.EPSILON_VALUE)
  local DEBUG_LEVEL    = get_ext_num("DEBUG_LEVEL",    DEFAULTS.DEBUG_LEVEL)

  local eps_s = 0.001
  if EPSILON_MODE == "frames" then
    eps_s = (fps > 0) and (EPSILON_VALUE / fps) or 0.0005
  elseif EPSILON_MODE == "seconds" then
    eps_s = EPSILON_VALUE
  else
    eps_s = 0.0005
  end

  return {
    HANDLE_MODE    = HANDLE_MODE,
    HANDLE_SECONDS = HANDLE_SECONDS,
    EPSILON_MODE   = EPSILON_MODE,
    EPSILON_VALUE  = EPSILON_VALUE,
    EPSILON_SEC    = eps_s,
    FPS            = fps,
    SR             = sr,
    DEBUG_LEVEL    = DEBUG_LEVEL,
  }
end

------------------------------------------------------------
-- Edit modes: Ripple & Trim Behind
------------------------------------------------------------
local function get_ripple_state()
  local per = r.GetToggleCommandStateEx(0, CMD_RIPPLE_PER) == 1
  local all = r.GetToggleCommandStateEx(0, CMD_RIPPLE_ALL) == 1
  local mode = "off"
  if all then mode = "all"
  elseif per then mode = "per" end
  return mode, per, all
end

local function get_trimbehind_on()
  return r.GetToggleCommandStateEx(0, CMD_TRIM_BEHIND) == 1
end

------------------------------------------------------------
-- FX listing
------------------------------------------------------------
local function list_take_fx_lines(tk)
  local lines = {}
  if not tk then return lines end
  local n = r.TakeFX_GetCount(tk)
  for i = 0, n-1 do
    local _, name = r.TakeFX_GetFXName(tk, i, "")
    local enabled = r.TakeFX_GetEnabled(tk, i)     -- true = not bypassed
    local offline = r.TakeFX_GetOffline(tk, i)     -- true = offline
    local status  = offline and "offline" or (enabled and "on" or "byp")
    lines[#lines+1] = string.format("takeFX#%d  %s  [%s]", i+1, name or "(unnamed FX)", status)
  end
  return lines
end

local function list_track_fx_lines(tr)
  local lines = {}
  if not tr then return lines end
  local n = r.TrackFX_GetCount(tr)
  for i = 0, n-1 do
    local _, name = r.TrackFX_GetFXName(tr, i, "")
    local enabled = r.TrackFX_GetEnabled(tr, i)
    local offline = r.TrackFX_GetOffline(tr, i)
    local status  = offline and "offline" or (enabled and "on" or "byp")
    lines[#lines+1] = string.format("trackFX#%d  %s  [%s]", i+1, name or "(unnamed FX)", status)
  end
  return lines
end

------------------------------------------------------------
-- Project markers starting with '#'
------------------------------------------------------------
local function project_hash_markers_in_span(L, R)
  local out = {}
  local idx = 0
  while true do
    local rv, isrgn, pos, rgnend, name = r.EnumProjectMarkers3(0, idx)
    if rv == 0 or rv == false then break end
    if not isrgn and name and name:sub(1,1) == "#" then
      if pos >= L - 1e-9 and pos <= R + 1e-9 then
        out[#out+1] = { pos = pos, name = name }
      end
    end
    idx = idx + 1
  end
  return out
end

------------------------------------------------------------
-- Take / source info, handle headroom
------------------------------------------------------------
local function get_take_name(it)
  local tk = r.GetActiveTake(it)
  if not tk then return nil end
  local _, nm = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return nm
end

local function get_take_active_index(item)
  local tk = r.GetActiveTake(item)
  if not tk then return 0, r.CountTakes(item) end
  local n = r.CountTakes(item)
  for i=0, n-1 do
    if r.GetTake(item, i) == tk then return (i+1), n end
  end
  return 0, n
end

-- compute how much we can extend L/R in timeline seconds
local function compute_extend_headroom_seconds(it)
  local tk = r.GetActiveTake(it)
  if not tk then return 0.0, 0.0 end
  local src = r.GetMediaItemTake_Source(tk)
  if not src then return 0.0, 0.0 end

  local item_len = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0.0
  local rate     = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1.0
  local offs     = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0.0

  local src_len  = r.GetMediaSourceLength(src) or 0.0  -- seconds @ base rate
  local src_used = item_len * rate

  local left_src  = math.max(0.0, offs)
  local right_src = math.max(0.0, src_len - (offs + src_used))

  local left_tl  = left_src  / math.max(1e-9, rate)
  local right_tl = right_src / math.max(1e-9, rate)
  return left_tl, right_tl
end

------------------------------------------------------------
-- BWF TimeReference (TR) + Start-in-Source (SIS) helpers
-- Prefer library (META.collect_item_fields) → fallback to old native read
------------------------------------------------------------

-- Legacy low-level reader (kept as fallback)
local function _legacy_try_read_tr_samples(src)
  if not src then return nil end
  -- primary: native metadata (use "BWF:TimeReference" is more robust than bext:)
  local ok, val = r.GetMediaFileMetadata(src, "BWF:TimeReference")
  if ok and val and val ~= "" and val ~= "[Binary data]" then
    val = val:gsub(",", ""):gsub("%s+", "")
    local n = tonumber(val) or (val:match("^0[xX]%x+$") and tonumber(val))
    if n then return n end
  end
  -- optional SWS/GUtilities fallback if present
  if r.CF_GetMediaSourceMetadata then
    local out = ""
    for _, k in ipairs({ "TimeReference", "TIMEREFERENCE", "ORIGREF" }) do
      local ok2, v = r.CF_GetMediaSourceMetadata(src, k, out)
      if ok2 and v and v ~= "" then
        v = v:gsub(",", ""):gsub("%s+", "")
        local n = tonumber(v) or (v:match("^0[xX]%x+$") and tonumber(v))
        if n then return n end
      end
    end
  end
  return nil
end

local function _legacy_get_tr_sec(src)
  local sr  = (src and r.GetMediaSourceSampleRate(src)) or 0
  local smp = _legacy_try_read_tr_samples(src)
  if not smp or smp <= 0 or sr <= 0 then return 0, sr, smp or 0 end
  return smp / sr, sr, smp
end

-- Unified reader:
-- returns tr_sec, tr_samples, sr, sis_sec, abs_sec
local function rgwh_read_TR_SIS(item, take)
  take = take or (item and r.GetActiveTake(item)) or take
  if not take then return 0,0,0,0,0 end

  local src = r.GetMediaItemTake_Source(take)
  local sr  = (src and r.GetMediaSourceSampleRate(src)) or 0
  local sis = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0

  -- 1) Prefer library (if loaded)
  if META and item then
    local f = META.collect_item_fields(item)   -- provides: f.timereference, f.samplerate, srcpath, etc.
    local tr_smp = 0

    -- Safely parse timereference (samples)
    if f and f.timereference and f.timereference ~= "" then
      local s = (f.timereference or "")
      -- keep only the first return of gsub; remove commas and spaces
      local cleaned = (s:gsub(",", "")):gsub("%s+", "")
      -- support hex like "0x1A2B" if any tool writes it that way
      if cleaned:match("^0[xX]%x+$") then
        tr_smp = tonumber(cleaned) or tonumber(cleaned:sub(3), 16) or 0
      else
        tr_smp = tonumber(cleaned) or 0
      end
    end

    -- Sample rate fallback from library (if REAPER SR unreadable)
    if (not sr or sr <= 0) and f and f.samplerate then
      local n = tonumber(tostring(f.samplerate):gsub("%s+", "")) or 0
      if n > 0 then sr = n end
    end

    local tr_sec = (sr and sr > 0 and tr_smp and tr_smp > 0) and (tr_smp / sr) or 0
    return tr_sec, tr_smp, sr or 0, sis, tr_sec + (sis or 0)
  end

  -- 2) Fallback: legacy native reader
  local tr_sec, sr2, tr_smp = _legacy_get_tr_sec(src)
  return tr_sec, tr_smp, (sr>0 and sr or sr2), sis, tr_sec + sis
end


------------------------------------------------------------
-- unit detection on a single track
-- Merge adjacent/touching/overlapping items into a single unit.
------------------------------------------------------------
local function detect_units_on_track(items, eps)
  table.sort(items, function(a,b)
    local La = r.GetMediaItemInfo_Value(a, "D_POSITION")
    local Lb = r.GetMediaItemInfo_Value(b, "D_POSITION")
    if La == Lb then
      local Ra = La + (r.GetMediaItemInfo_Value(a, "D_LENGTH") or 0)
      local Rb = Lb + (r.GetMediaItemInfo_Value(b, "D_LENGTH") or 0)
      return Ra < Rb
    end
    return La < Lb
  end)

  local units = {}
  local cur = nil

  local function close_cur()
    if cur then
      local kind = "SINGLE"
      if #cur.members == 1 then
        kind = "SINGLE"
      else
        local anyOverlap, anyTouch = false, false
        for i=1,#cur.members-1 do
          local mA = cur.members[i]
          local mB = cur.members[i+1]
          local g = mB.L - mA.R
          if g < -eps then anyOverlap = true
          elseif math.abs(g) <= eps then anyTouch = true end
        end
        if anyOverlap and anyTouch then kind = "MIXED"
        elseif anyOverlap then kind = "CROSSFADE"
        else kind = "TOUCH"
        end
      end
      cur.kind = kind
      cur.start = cur.UL
      cur.finish = cur.UR
      units[#units+1] = cur
      cur = nil
    end
  end

  for _, it in ipairs(items) do
    local L = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
    local R = L + (r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0.0)
    if not cur then
      cur = { UL = L, UR = R, members = { {it=it, L=L, R=R} } }
    else
      if L <= (cur.UR + eps) then
        cur.members[#cur.members+1] = { it=it, L=L, R=R }
        if L < cur.UL then cur.UL = L end
        if R > cur.UR then cur.UR = R end
      else
        close_cur()
        cur = { UL = L, UR = R, members = { {it=it, L=L, R=R} } }
      end
    end
  end
  close_cur()
  return units
end

------------------------------------------------------------
-- main
------------------------------------------------------------
local function main()
  -- Initialize output (clear file if file output is enabled)
  init_output_file()

  local S = current_settings()
  local tp = reaper.time_precise() or 0
  local id = string.format("%08X", math.floor(tp * 1000 + 0.5))
  printf("[RGWH][Monitor][RunID=%s] DEBUG=%d  eps=%.5fs (mode=%s, value=%.3f)  sr=%.0f  fps=%.3f",
    id, S.DEBUG_LEVEL, S.EPSILON_SEC, S.EPSILON_MODE, S.EPSILON_VALUE, S.SR, S.FPS)

  -- print edit mode states
  local rmode, rper, rall = get_ripple_state()
  local trim_on = get_trimbehind_on()
  printf("[RGWH][Monitor] Ripple=%s (per=%s, all=%s)  TrimBehind=%s",
         rmode, tostring(rper), tostring(rall), tostring(trim_on))

  -- collect selected items by track
  local by_tr = {}
  local n_it = r.CountSelectedMediaItems(0)
  for i = 0, n_it-1 do
    local it = r.GetSelectedMediaItem(0, i)
    local tr = r.GetMediaItem_Track(it)
    by_tr[tr] = by_tr[tr] or {}
    table.insert(by_tr[tr], it)
  end

  -- ordered tracks
  local tr_list = {}
  for tr,_ in pairs(by_tr) do tr_list[#tr_list+1] = tr end
  table.sort(tr_list, function(a,b)
    local ia = r.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") or 0
    local ib = r.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER") or 0
    return ia < ib
  end)

  local sum_tracks, sum_items, sum_units = 0, 0, 0

  for _, tr in ipairs(tr_list) do
    local items = by_tr[tr]
    local tnum = r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or -1
    local track_channels = r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2
    local units = detect_units_on_track(items, S.EPSILON_SEC)
    printf("[RGWH][Monitor] Track #%d: items=%d units=%d track_channels=%d", tnum, #items, #units, track_channels)
    sum_tracks = sum_tracks + 1
    sum_items  = sum_items + #items
    sum_units  = sum_units + #units

    for ui, u in ipairs(units) do
      printf("  unit#%d  kind=%s  members=%d  span=%.3f..%.3f  dur=%.3f",
        ui, u.kind, #u.members, u.UL, u.UR, u.UR - u.UL)

      for mi, m in ipairs(u.members) do
        local it = m.it
        local L, R = m.L, m.R
        local tk = r.GetActiveTake(it)
        local nm = get_take_name(it) or "(no take name)"
        local ai, an = get_take_active_index(it)

        local iv = r.GetMediaItemInfo_Value(it, "D_VOL") or 1.0
        local tv = tk and (r.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1.0) or 1.0

        local fin_len   = r.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0.0
        local fin_dir   = r.GetMediaItemInfo_Value(it, "D_FADEINDIR") or 0.0
        local fin_shape = r.GetMediaItemInfo_Value(it, "C_FADEINSHAPE") or 0
        local fout_len   = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0.0
        local fout_dir   = r.GetMediaItemInfo_Value(it, "D_FADEOUTDIR") or 0.0
        local fout_shape = r.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") or 0

        local Hleft, Hright = compute_extend_headroom_seconds(it)
        local clampL = (S.HANDLE_SECONDS or 0) > (Hleft + 1e-9)
        local clampR = (S.HANDLE_SECONDS or 0) > (Hright + 1e-9)

        printf("    member#%d  %.3f..%.3f (%s)  len=%.3f  take='%s'  take#=%d/%d",
          mi, L, R, sec_to_hhmmss(L), (R-L), nm, ai, an)
        printf("    vols: itemVol=%.3f  takeVol=%.3f", iv, tv)
        printf("    fades: in=%.3f(s) dir=%.3f shape=%d  out=%.3f(s) dir=%.3f shape=%d",
          fin_len, fin_dir, fin_shape, fout_len, fout_dir, fout_shape)
        printf("    handles: maxL=%.3f maxR=%.3f  req=%.3f  clampL=%s clampR=%s",
          Hleft, Hright, S.HANDLE_SECONDS or 0, tostring(clampL), tostring(clampR))

        do
          local tr_ch    = (r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2)
          local chanmode = tk and (r.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0) or 0
          local src      = tk and r.GetMediaItemTake_Source(tk) or nil
          local src_ch   = (src and r.GetMediaSourceNumChannels and r.GetMediaSourceNumChannels(src)) or 0
          printf("    channels: src=%d  track=%d  chanmode=%d", src_ch, tr_ch, chanmode)
        end

        
        do
          local tr_sec, tr_smp, sr, sis, abs = rgwh_read_TR_SIS(it, tk)
          -- Display raw domain first, then converted in parentheses:
          --  TR   : samples first (raw from BWF), then seconds (ellipsis if truncated)
          --  SIS/ABS: seconds first (raw from REAPER), then integer samples
          local sis_smp = math.floor((sis or 0) * (sr or 48000) + 0.5)
          local abs_smp = math.floor((abs or 0) * (sr or 48000) + 0.5)
          printf("    sourceTC: TR=%s smp (%ss)  SIS=%ss (%d smp)  ABS=%ss (%d smp)",
            tostring(tr_smp),
            fmt_secs_from_samples(tr_smp or 0, sr, UI_DECIMALS),
            fmt_sec_d(sis or 0), sis_smp,
            fmt_sec_d(abs or 0), abs_smp)
        end  -- <<< 補這個，關閉第二個 do 區塊

        for _, line in ipairs(list_take_fx_lines(tk)) do
          printf("    %s", line)
        end
        for _, line in ipairs(list_track_fx_lines(tr)) do
          printf("    %s", line)
        end


        local cues = project_hash_markers_in_span(L, R)
        if #cues == 0 then
          printf("    # markers: (none)")
        else
          for _, mkr in ipairs(cues) do
            printf("    # marker @ %.3f (%s) : %s", mkr.pos, sec_to_hhmmss(mkr.pos), mkr.name)
          end
        end
      end
    end
  end

  printf("[RGWH][Monitor][Summary] tracks=%d  items=%d  units=%d",
    sum_tracks, sum_items, sum_units)
end

main()
