--[[
@description RGWH Core ExtState Set (project-scope)
@version 250920_1950
@author hsuanice
@about
  快速設定 RGWH Core 用到的 ExtState（寫在當前專案）。
]]--
local r = reaper
local NS = "RGWH" -- namespace

-- 想改什麼就改這裡
local CFG = {
  GLUE_SINGLE_ITEMS  = 1,          -- 1/0
  HANDLE_MODE        = "seconds",  -- "seconds"
  HANDLE_SECONDS     = 1.5,        -- handles 秒數
  EPSILON_MODE       = "frames",   -- "frames" or "seconds"
  EPSILON_VALUE      = 0.5,        -- 以 frames 模式時：frame 數；seconds 模式時：秒
  DEBUG_LEVEL        = 2,          -- 0/1/2
  RENDER_TAKE_FX     = 1,          -- 1=保留/印入 take FX；0=Glue/Render 時不印入
  RENDER_TRACK_FX    = 0,          -- 1=Glue 後對成品 Apply Track/Take FX；Render 時控制暫停/恢復
  APPLY_FX_MODE      = "mono",     -- "mono" | "multi"
  RENAME_OP_MODE     = "auto",     -- "auto" | "glue" | "render"
  WRITE_MEDIA_CUES   = 1,          -- 1=寫 #in/#out project markers（Media Cues）
  WRITE_TAKE_MARKERS = 1,          -- ✅ 1=Glue 成品 take 內加標記（非 SINGLE）
}

local function set(k, v) r.SetProjExtState(0, NS, k, tostring(v)) end

r.Undo_BeginBlock()
for k, v in pairs(CFG) do set(k, v) end
r.Undo_EndBlock("RGWH Core - Set ExtState", -1)

-- 顯示目前設定
r.ShowConsoleMsg(string.format(
  "[RGWH] ExtState updated (project) — namespace=%s\n"..
  "GLUE_SINGLE_ITEMS=%s\nHANDLE_MODE=%s\nHANDLE_SECONDS=%s\n"..
  "EPSILON_MODE=%s\nEPSILON_VALUE=%s\nDEBUG_LEVEL=%s\n"..
  "RENDER_TAKE_FX=%s\nRENDER_TRACK_FX=%s\nAPPLY_FX_MODE=%s\n"..
  "RENAME_OP_MODE=%s\nWRITE_MEDIA_CUES=%s\nWRITE_TAKE_MARKERS=%s\n",
  NS,
  CFG.GLUE_SINGLE_ITEMS, CFG.HANDLE_MODE, CFG.HANDLE_SECONDS,
  CFG.EPSILON_MODE, CFG.EPSILON_VALUE, CFG.DEBUG_LEVEL,
  CFG.RENDER_TAKE_FX, CFG.RENDER_TRACK_FX, CFG.APPLY_FX_MODE,
  CFG.RENAME_OP_MODE, CFG.WRITE_MEDIA_CUES, CFG.WRITE_TAKE_MARKERS
))
