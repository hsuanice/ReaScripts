--[[
@description RGWH Core ExtState Set (project-scope)
@version 250922_1750 update renamed functino glue and edge cues
@author hsuanice
@about
  快速設定 RGWH Core 用到的 ExtState（寫在當前專案）。
]]--
local r = reaper
local NS = "RGWH" -- namespace

-- 想改什麼就改這裡
local CFG = {
  GLUE_SINGLE_ITEMS  = 1,
  HANDLE_MODE        = "seconds",
  HANDLE_SECONDS     = 5,
  EPSILON_MODE       = "frames",
  EPSILON_VALUE      = 0.5,
  DEBUG_LEVEL        = 2,

  -- GLUE 專屬
  GLUE_TAKE_FX       = 1,
  GLUE_TRACK_FX      = 0,
  GLUE_APPLY_MODE    = "mono",   -- "mono" | "multi"

  -- RENDER 專屬
  RENDER_TAKE_FX     = 0,
  RENDER_TRACK_FX    = 0,
  RENDER_APPLY_MODE  = "mono",   -- "mono" | "multi"

  RENAME_OP_MODE     = "auto",
  WRITE_EDGE_CUES    = 1,
  WRITE_GLUE_CUES    = 1,
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
  "GLUE_TAKE_FX=%s\nGLUE_TRACK_FX=%s\nGLUE_APPLY_MODE=%s\n"..
  "RENDER_TAKE_FX=%s\nRENDER_TRACK_FX=%s\nRENDER_APPLY_MODE=%s\n"..
  "RENAME_OP_MODE=%s\nWRITE_EDGE_CUES=%s\nWRITE_GLUE_CUES=%s\n",
  NS,
  CFG.GLUE_SINGLE_ITEMS, CFG.HANDLE_MODE, CFG.HANDLE_SECONDS,
  CFG.EPSILON_MODE, CFG.EPSILON_VALUE, CFG.DEBUG_LEVEL,
  CFG.GLUE_TAKE_FX, CFG.GLUE_TRACK_FX, CFG.GLUE_APPLY_MODE,
  CFG.RENDER_TAKE_FX, CFG.RENDER_TRACK_FX, CFG.RENDER_APPLY_MODE,
  CFG.RENAME_OP_MODE, CFG.WRITE_EDGE_CUES, CFG.WRITE_GLUE_CUES
))
