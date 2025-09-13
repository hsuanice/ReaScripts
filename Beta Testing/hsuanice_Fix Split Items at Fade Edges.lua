--[[
@description hsuanice_Fix Split Items at Fade Edges
@version 0.2.0
@author hsuanice
@about
  Flag items whose fade-in or fade-out length is (nearly) the same as the item length.
  For each hit, add take marker(s) and print a console report.

  Notes:
  - Scans all tracks (no selection needed).
  - Uses the larger of manual/auto fade lengths (AUTO = -1 means none).
  - Tolerances configurable below (samples and relative %).
--]]

local r = reaper

-- ================= User options =================
local ABS_TOL_SAMPLES = 64     -- 絕對容差（samples）
local REL_TOL_FRAC    = 0.01   -- 相對容差（0.01 = 1%）
local OPEN_AND_CLEAR_CONSOLE = true

local LABEL_IN  = "Review: Fade-in spans entire item"
local LABEL_OUT = "Review: Fade-out spans entire item"

-- ================= Helpers =================
local function msg(s) r.ShowConsoleMsg(tostring(s) .. "\n") end

local function project_sr()
  local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if not sr or sr <= 0 then sr = 48000 end
  return sr
end

local SR = project_sr()

local function toSamples(sec) return math.floor(sec * SR + 0.5) end
local function fmtTC(sec)    return r.format_timestr_pos(sec, "", 5) end  -- h:m:s:f

-- 手動/AUTO 淡變取最大（秒）
local function effective_fades_sec(item)
  local fi  = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") or 0
  local fo  = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") or 0
  local fia = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO") or -1
  local foa = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO") or -1
  if fia < 0 then fia = 0 end
  if foa < 0 then foa = 0 end
  return math.max(fi, fia), math.max(fo, foa) -- inSec, outSec
end

-- 專案時間 -> take 時間（SetTakeMarker 用）
local function proj_to_take_time(take, item, project_pos)
  if not take or not item then return 0 end
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local rate     = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate == 0 then rate = 1 end
  local offs     = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local tpos     = (project_pos - item_pos) / rate + offs
  if tpos < 0 then tpos = 0 end
  return tpos
end

local function add_marker_at_item_edge(item, edge, label)
  -- edge: "start" or "end"（在 item 起點或終點放 marker）
  local take = r.GetActiveTake(item)
  if not take then return end
  local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local proj_pos = (edge == "end") and (item_pos + item_len) or item_pos
  local tpos     = proj_to_take_time(take, item, proj_pos)
  r.SetTakeMarker(take, -1, label, tpos)
end

local function take_name(item)
  local tk = r.GetActiveTake(item)
  if not tk then return "" end
  local _, name = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return name or ""
end

-- ================= Main =================
if OPEN_AND_CLEAR_CONSOLE then r.ShowConsoleMsg("") end
msg(("=== Fade ~ full-length detector (SR=%d) ==="):format(SR))
msg(("Tolerances: abs=%d smp, rel=%.2f%%\n"):format(ABS_TOL_SAMPLES, REL_TOL_FRAC*100))
msg("Track\tTake\tStart(TC)\tItemLen(smp)\tFadeIn(smp)\tFadeOut(smp)\tWhich")

local hits = 0
local tr_count = r.CountTracks(0)

r.Undo_BeginBlock()
r.PreventUIRefresh(1)

for ti = 0, tr_count-1 do
  local tr = r.GetTrack(0, ti)
  local _, trName = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  local it_count = r.CountTrackMediaItems(tr)

  for ii = 0, it_count-1 do
    local it   = r.GetTrackMediaItem(tr, ii)
    local pos  = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local lenS = toSamples(r.GetMediaItemInfo_Value(it, "D_LENGTH"))
    if lenS > 0 then
      local inSec, outSec = effective_fades_sec(it)
      local finS  = toSamples(inSec)
      local foutS = toSamples(outSec)

      local tol = math.max(ABS_TOL_SAMPLES, math.floor(lenS * REL_TOL_FRAC + 0.5))
      local near_in  = (finS  >= lenS - tol and finS  > 0)
      local near_out = (foutS >= lenS - tol and foutS > 0)

      if near_in or near_out then
        hits = hits + 1
        local which =
          (near_in and near_out) and "fade-in & fade-out" or
          (near_in and "fade-in" or "fade-out")

        -- 標記：淡入命中 → item 起點；淡出命中 → item 終點（兩者都命中就各放一個）
        if near_in  then add_marker_at_item_edge(it, "start", LABEL_IN)  end
        if near_out then add_marker_at_item_edge(it, "end",   LABEL_OUT) end

        msg(("%s\t%s\t%s\t%d\t%d\t%d\t%s"):format(
          trName or "", take_name(it), fmtTC(pos), lenS, finS, foutS, which
        ))
      end
    end
  end
end

r.PreventUIRefresh(-1)
r.Undo_EndBlock("Flag items whose fade spans (nearly) the entire item", -1)

msg(("\n=== Summary ===\nFound: %d item(s)."):format(hits))
