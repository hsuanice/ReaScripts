--[[
@description RGWH Core - Render or Glue with Handles
@version 0.2.1
@author hsuanice

@provides
  [main] .

@about
  Core library for handle-aware Render/Glue workflows with clear, single-entry API.
  Features:
    • Handle-aware windows with clamp-to-source.
    • Glue by Item Units (same-track grouping), with optional Glue Cues.
    • Render single items with apply policies and BWF TimeReference embed.
    • One-run overrides via ExtState snapshot/restore (non-destructive defaults).
    • Edge Cues (#in/#out) and Glue Cues (#Glue: <TakeName>) for media cue workflows.

@api
  -- Primary:
  RGWH.core(args) -> (ok:boolean, err?:string)
    args = {
      op = "render" | "glue" | "auto",     -- render = single item only; glue supports scope (see below)
      selection_scope = "auto" | "units" | "ts" | "item",  -- glue/auto only; render ignores it
      item  = MediaItem*,                  -- optional single-item provider (render or glue/item)
      items = { MediaItem*, ... },         -- optional items provider for glue/units

      -- Channel mode (maps to GLUE/RENDER_APPLY_MODE):
      channel_mode = "auto" | "mono" | "multi",

      -- Render-specific toggles:
      take_fx  = true|false,               -- bake take FX (nil = keep ExtState)
      track_fx = true|false,               -- bake track FX (nil = keep ExtState)
      tc_mode  = "previous" | "current" | "off", -- TimeReference embed policy (render only)
      merge_volumes = true|false,          -- merge item volume into take volume before render (default: true)
      merge_to_item = true|false,          -- merge take volume into item volume (mutually exclusive with merge_volumes)
      print_volumes = true|false,          -- bake volumes into rendered audio; false = restore original (default: true)

      -- One-run overrides (fallback: ExtState -> DEFAULTS):
      handle  = { mode="seconds", seconds=5.0 } | "ext" | nil,
      epsilon = { mode="frames", value=0.5 }     | "ext" | nil,
      cues    = { write_edge=true/false, write_glue=true/false },
      policies = {
        glue_single_items = true/false,
        glue_no_trackfx_output_policy   = "preserve"|"force_multi",
        render_no_trackfx_output_policy = "preserve"|"force_multi",
      },
      debug = { level=1..N, no_clear=true/false },
    }

  -- Legacy (kept for compatibility):
  RGWH.glue_selection()
  RGWH.render_selection(take_fx?, track_fx?, mode?, tc_mode?, merge_volumes?, print_volumes?)
  RGWH.apply(args)  -- AudioSweet bridge (unchanged)
  
@notes
  • "render" always processes a single item (selected or provided); selection_scope is ignored.
  • "glue" supports Item Units / TS-Window / single item.
  • "auto": NEW (v251107.0100) - analyzes each unit individually:
      - Single-item units → render
      - Multi-item units (TOUCH/CROSSFADE) → glue
      - Works with mixed unit types in single execution
  • All overrides are one-run only: ExtState is snapshotted and restored after operation.
  • For detailed operation modes guide, see RGWH GUI: Help > Manual (Operation Modes)

@changelog
  0.2.1 [v251224.1318] - GLUE APPLY VOLUME HANDLING
    - CHANGED: Glue-only path uses native volume behavior (item+take printed)
    - CHANGED: Volume rendering options apply only when Apply is executed (render/apply)
]]--
local r = reaper
local M = {}

-- Load Metadata Embed Library (single source of truth for TR math)
local RES_PATH = r.GetResourcePath()
local E = dofile(RES_PATH .. '/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Embed.lua')

------------------------------------------------------------
-- Constants / Commands
------------------------------------------------------------
local NS = "RGWH"  -- ExtState namespace (project-scope)

-- Actions
local ACT_GLUE_TS        = 42432   -- Item: Glue items within time selection
local ACT_TRIM_TO_TS     = 40508   -- Item: Trim items to time selection
local ACT_APPLY_MONO     = 40361   -- Item: Apply track/take FX to items (mono output)
local ACT_APPLY_MULTI    = 41993   -- Item: Apply track/take FX to items (multichannel output)
local ACT_REMOVE_TAKE_FX = 40640   -- Item: Remove FX for item take

------------------------------------------------------------
-- Defaults (used if no ExtState present)
------------------------------------------------------------
local DEFAULTS = {
  GLUE_SINGLE_ITEMS  = true,
  HANDLE_MODE        = "seconds",
  HANDLE_SECONDS     = 5.0,
  EPSILON_MODE       = "frames",
  EPSILON_VALUE      = 0.5,
  DEBUG_LEVEL        = 0,
  -- FX policies (separate for GLUE vs RENDER)
  GLUE_TAKE_FX       = 1,             -- 1=Glue 之後的成品要印入 take FX；0=不印入
  GLUE_TRACK_FX      = 0,             -- 1=Glue 成品再套用 Track/Take FX
  GLUE_APPLY_MODE    = "mono",        -- "mono" | "multi"（給 Glue 後的 apply 用）

  RENDER_TAKE_FX     = 0,             -- 1=Render 直接印入 take FX；0=保留（偏向 non-destructive）
  RENDER_TRACK_FX    = 0,             -- 1=Render 同時印入 Track FX
  RENDER_APPLY_MODE  = "mono",        -- "mono" | "multi"（Render 使用的 apply 模式）
  RENDER_TC_EMBED    = "current",    -- TR embed mode for render: "previous" | "current" | "off"

  -- Volume handling policies
  RENDER_MERGE_VOLUMES = 1,           -- 1=Merge item volume into take volume before render
  RENDER_PRINT_VOLUMES = 1,           -- 1=Bake volumes into rendered audio; 0=restore (non-destructive)
  GLUE_MERGE_VOLUMES   = 1,           -- 1=Merge item volume into take volume before glue
  GLUE_PRINT_VOLUMES   = 1,           -- 1=Bake volumes into glued audio; 0=restore (non-destructive)

  -- Hash markers（#in/#out 以供 Media Cues）
  WRITE_EDGE_CUES   = 1,
  -- ✅ 新增：Glue 成品 take 內是否加 take markers（非 SINGLE 才加）
  WRITE_GLUE_CUES = 1,

  -- Policies when TRACK FX are NOT being printed:
  GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX   = "preserve",   -- "preserve" | "force_multi"
  RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = "preserve",   -- "preserve" | "force_multi"
}

------------------------------------------------------------
-- ExtState helpers (project-scope)
------------------------------------------------------------
local function get_proj() return 0 end

local function get_ext(key, fallback)
  local _, v = r.GetProjExtState(get_proj(), NS, key)
  if v == nil or v == "" then return fallback end
  return v
end

local function get_ext_bool(key, fallback_bool)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_bool and 1 or 0 end
  v = tostring(v)
  if v == "1" or v:lower()=="true" then return 1 end
  return 0
end

local function get_ext_num(key, fallback_num)
  local v = get_ext(key, nil)
  if v == nil or v == "" then return fallback_num end
  local n = tonumber(v)
  return n or fallback_num
end

local function set_ext(key, val)
  r.SetProjExtState(get_proj(), NS, key, tostring(val))
end

function M.read_settings()
  return {
    GLUE_SINGLE_ITEMS  = (get_ext_bool("GLUE_SINGLE_ITEMS",  DEFAULTS.GLUE_SINGLE_ITEMS)==1),
    HANDLE_MODE        = get_ext("HANDLE_MODE",              DEFAULTS.HANDLE_MODE),
    HANDLE_SECONDS     = get_ext_num("HANDLE_SECONDS",       DEFAULTS.HANDLE_SECONDS),
    EPSILON_MODE       = get_ext("EPSILON_MODE",             DEFAULTS.EPSILON_MODE),
    EPSILON_VALUE      = get_ext_num("EPSILON_VALUE",        DEFAULTS.EPSILON_VALUE),
    DEBUG_LEVEL        = get_ext_num("DEBUG_LEVEL",          DEFAULTS.DEBUG_LEVEL),
    GLUE_TAKE_FX       = (get_ext_bool("GLUE_TAKE_FX",      DEFAULTS.GLUE_TAKE_FX)==1),
    GLUE_TRACK_FX      = (get_ext_bool("GLUE_TRACK_FX",     DEFAULTS.GLUE_TRACK_FX)==1),
    GLUE_APPLY_MODE    =  get_ext("GLUE_APPLY_MODE",        DEFAULTS.GLUE_APPLY_MODE),

    RENDER_TAKE_FX     = (get_ext_bool("RENDER_TAKE_FX",    DEFAULTS.RENDER_TAKE_FX)==1),
    RENDER_TRACK_FX    = (get_ext_bool("RENDER_TRACK_FX",   DEFAULTS.RENDER_TRACK_FX)==1),
    RENDER_APPLY_MODE  =  get_ext("RENDER_APPLY_MODE",      DEFAULTS.RENDER_APPLY_MODE),
    -- TR embed mode for Render: "previous" | "current" | "off"
    RENDER_TC_EMBED    = get_ext("RENDER_TC_EMBED", "previous"),

    -- Volume handling policies
    RENDER_MERGE_VOLUMES = (get_ext_bool("RENDER_MERGE_VOLUMES", DEFAULTS.RENDER_MERGE_VOLUMES)==1),
    RENDER_PRINT_VOLUMES = (get_ext_bool("RENDER_PRINT_VOLUMES", DEFAULTS.RENDER_PRINT_VOLUMES)==1),
    GLUE_MERGE_VOLUMES   = (get_ext_bool("GLUE_MERGE_VOLUMES",   DEFAULTS.GLUE_MERGE_VOLUMES)==1),
    GLUE_PRINT_VOLUMES   = (get_ext_bool("GLUE_PRINT_VOLUMES",   DEFAULTS.GLUE_PRINT_VOLUMES)==1),

    WRITE_EDGE_CUES    = (get_ext_bool("WRITE_EDGE_CUES",   DEFAULTS.WRITE_EDGE_CUES)==1),
    -- 🔧 修正：用 DEFAULTS，不是 dflt
    WRITE_GLUE_CUES    = (get_ext_bool("WRITE_GLUE_CUES", DEFAULTS.WRITE_GLUE_CUES)==1),

    GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX   = get_ext("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX",   DEFAULTS.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX),
    RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX = get_ext("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", DEFAULTS.RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX),

    DEBUG_NO_CLEAR = (get_ext_bool("DEBUG_NO_CLEAR", false) == 1),
  }

end

------------------------------------------------------------
-- Utility / Logging
------------------------------------------------------------
local function printf(fmt, ...) r.ShowConsoleMsg(string.format(fmt.."\n", ...)) end
local function dbg(level, want, ...) if level>=want then printf(...) end end

local function frames_to_seconds(frames, sr, fps)
  local fr = (r.TimeMap_curFrameRate and r.TimeMap_curFrameRate(0) or 24.0)
  return (frames or 1) / (fr>0 and fr or 24.0)
end

local function get_sr()
  return r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
end

local function add_take_marker_at(item, rel_pos_sec, label)
  local take = r.GetActiveTake(item)
  if not take then return end
  r.SetTakeMarker(take, -1, label or "", rel_pos_sec, 0) -- -1 append
end


-- 取 base/ext（若無副檔名則 ext=""）
local function split_ext(s)
  local base, ext = s:match("^(.*)(%.[^%./\\]+)$")
  if not base then return s or "", "" end
  return base, ext
end

-- 移除尾端標籤：-takefx / -trackfx / -renderedN（僅針對字尾，避免中段誤刪）
local function strip_tail_tags(s)
  s = s or ""
  while true do
    local before = s
    s = s:gsub("%-takefx$", "")
    s = s:gsub("%-trackfx$", "")
    s = s:gsub("%-rendered%d+$", "")
    s = s:gsub("%-$","")  -- 若剛好留下尾端 '-'，順手清掉
    if s == before then break end
  end
  return s
end

-- 取名字中的 renderedN（僅字尾，允許後面跟 -takefx/-trackfx 再抽回去）
local function extract_rendered_n(name)
  local b = split_ext(name)
  -- 先暫時移除尾端 -takefx/-trackfx，抓 renderedN
  local t = b:gsub("%-takefx$",""):gsub("%-trackfx$","")
  t = t:gsub("%-takefx$",""):gsub("%-trackfx$","")
  local n = t:match("%-rendered(%d+)$")
  return tonumber(n or 0) or 0
end

-- 掃「同一個 item 的所有 takes」找出已存在的最大 renderedN
local function max_rendered_n_on_item(it)
  local maxn = 0
  local tc = reaper.CountTakes(it)
  for i = 0, tc-1 do
    local tk = reaper.GetTake(it, i)
    local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
    local n = extract_rendered_n(nm or "")
    if n > maxn then maxn = n end
  end
  return maxn
end

-- 只改「新產生的 rendered take」的名稱；舊 take 不動
-- base 用「render 前的舊 take 名稱（去掉既有 suffix）」；ext 用「新 take 現名的副檔名」
local function rename_new_render_take(it, orig_take_name, want_takefx, want_trackfx, DBG)
  if not it then return end
  local tc = reaper.CountTakes(it)
  if tc == 0 then return end

  -- New take is appended last (usually becomes active)
  local newtk = reaper.GetTake(it, tc-1)
  if not newtk then return end

  -- Current new-take name (only for logging)
  local _, curNewName = reaper.GetSetMediaItemTakeInfo_String(newtk, "P_NAME", "", false)

  -- Base = old take name without any tail tags and without extension
  local baseOld = strip_tail_tags(select(1, split_ext(orig_take_name or "")))

  -- N = max existing rendered index on this item + 1
  local nextN = max_rendered_n_on_item(it) + 1

  -- Final rule: TakeName-renderedN  (no -takefx/-trackfx, no extension)
  local newname = string.format("%s-rendered%d", baseOld, nextN)

  reaper.GetSetMediaItemTakeInfo_String(newtk, "P_NAME", newname, true)
  dbg(DBG, 1, "[NAME] new take rename '%s' → '%s'", tostring(curNewName or ""), tostring(newname))
end


-- 只快照「offline」布林，不記 bypass
local function snapshot_takefx_offline(tk)
  local n = r.TakeFX_GetCount(tk) or 0
  local snap = {}
  for i = 0, n-1 do
    snap[i] = r.TakeFX_GetOffline(tk, i) and true or false
  end
  return snap
end

-- 暫時把「原本不是 offline」的 FX 設為 offline（不動原本就 offline 的）
local function temp_offline_nonoffline_fx(tk)
  local n = r.TakeFX_GetCount(tk) or 0
  local cnt = 0
  for i = 0, n-1 do
    if not r.TakeFX_GetOffline(tk, i) then
      r.TakeFX_SetOffline(tk, i, true)
      cnt = cnt + 1
    end
  end
  return cnt
end

-- 依快照還原 offline 狀態
local function restore_takefx_offline(tk, snap)
  if not (tk and snap) then return 0 end
  local n = r.TakeFX_GetCount(tk) or 0
  local cnt = 0
  for i = 0, n-1 do
    local want = snap[i]
    if want ~= nil then
      r.TakeFX_SetOffline(tk, i, want and true or false)
      cnt = cnt + 1
    end
  end
  return cnt
end

-- -- Fade snapshot helpers -----------------------------------------
local function snapshot_fades(it)
  return {
    inLen   = r.GetMediaItemInfo_Value(it, "D_FADEINLEN") or 0.0,
    outLen  = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN") or 0.0,
    inAuto  = r.GetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO") or 0.0,
    outAuto = r.GetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO") or 0.0,
    inShape = r.GetMediaItemInfo_Value(it, "C_FADEINSHAPE") or 0,
    outShape= r.GetMediaItemInfo_Value(it, "C_FADEOUTSHAPE") or 0,
    inDir   = r.GetMediaItemInfo_Value(it, "C_FADEINDIR") or 0.0,
    outDir  = r.GetMediaItemInfo_Value(it, "C_FADEOUTDIR") or 0.0,
  }
end

local function zero_fades(it)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO", 0.0)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO", 0.0)
end

local function restore_fades(it, f)
  if not f then return end
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN",        f.inLen)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN",       f.outLen)
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN_AUTO",   f.inAuto)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN_AUTO",  f.outAuto)
  r.SetMediaItemInfo_Value(it, "C_FADEINSHAPE",      f.inShape)
  r.SetMediaItemInfo_Value(it, "C_FADEOUTSHAPE",     f.outShape)
  r.SetMediaItemInfo_Value(it, "C_FADEINDIR",        f.inDir)
  r.SetMediaItemInfo_Value(it, "C_FADEOUTDIR",       f.outDir)
end

------------------------------------------------------------
-- Volume handling helpers
------------------------------------------------------------
-- Snapshot item and all takes' volumes
-- Returns: { item_vol, take_vols={}, merged_vol }
local function snapshot_item_volumes(item)
  local snap = {
    item_vol = r.GetMediaItemInfo_Value(item, "D_VOL") or 1.0,
    take_vols = {},
    merged_vol = 1.0
  }

  local nt = r.GetMediaItemNumTakes(item) or 0
  for ti = 0, nt-1 do
    local tk = r.GetTake(item, ti)
    if tk then
      snap.take_vols[ti] = r.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1.0
    end
  end

  return snap
end

-- Pre-process volumes before render/apply
-- Handles merge_volumes, merge_to_item, and print_volumes logic
-- Modifies item/take volumes in-place
-- Returns: volume_snap with merged_vol calculated
local function preprocess_item_volumes(item, merge_volumes, print_volumes, merge_to_item, DBG)
  merge_to_item = merge_to_item or false
  local volume_snap = snapshot_item_volumes(item)
  local tk_orig = r.GetActiveTake(item)

  if not tk_orig then
    return volume_snap
  end

  local item_vol = volume_snap.item_vol
  local nt = r.GetMediaItemNumTakes(item) or 0

  -- Get active take index
  local tk_orig_idx = nil
  for ti = 0, nt-1 do
    if r.GetTake(item, ti) == tk_orig then
      tk_orig_idx = ti
      break
    end
  end

  -- === MERGE TO ITEM ===
  -- NOTE: Print ON is NOT supported with merge_to_item (GUI auto-switches to merge_to_take)
  -- REAPER can only print take volume, not item volume
  if merge_to_item then
    local tv_orig = volume_snap.take_vols[tk_orig_idx] or 1.0
    local combined = item_vol * tv_orig
    volume_snap.merged_vol = combined

    -- PRINT OFF ONLY: Set both item and take to 1.0 for render, restore item volume in postprocess
    -- REAPER renders with item×take volume, so both must be 1.0 to preserve original audio
    -- Step 1: Set item to 1.0 temporarily
    r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)

    -- Step 2: Set ALL takes to 1.0
    for ti = 0, nt-1 do
      local tk = r.GetTake(item, ti)
      if tk then
        r.SetMediaItemTakeInfo_Value(tk, "D_VOL", 1.0)
      end
    end

    if DBG and DBG >= 2 then
      dbg(DBG,2,"[GAIN] merge_to_item: item=1.0 (temp), all takes=1.0, will restore item=%.3f in postprocess",
          combined)
    end

  -- === MERGE TO TAKE (ORIGINAL) ===
  elseif merge_volumes then
    if math.abs(item_vol - 1.0) > 1e-9 then
      -- Multiply item volume into EVERY take's volume
      for ti = 0, nt-1 do
        local tk = r.GetTake(item, ti)
        if tk then
          local tv = r.GetMediaItemTakeInfo_Value(tk, "D_VOL") or 1.0
          local merged_tv = tv * item_vol
          r.SetMediaItemTakeInfo_Value(tk, "D_VOL", merged_tv)
        end
      end

      -- Remember merged value for active take
      local tv_orig = volume_snap.take_vols[tk_orig_idx] or 1.0
      volume_snap.merged_vol = tv_orig * item_vol
      r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)

      if DBG and DBG >= 2 then
        dbg(DBG,2,"[GAIN] pre-merged itemVol=%.3f into ALL takes; active take (%.3f → %.3f)",
            item_vol, tv_orig, volume_snap.merged_vol)
      end
    else
      -- Item already at 1.0
      volume_snap.merged_vol = r.GetMediaItemTakeInfo_Value(tk_orig, "D_VOL") or 1.0
    end

    -- If print_volumes=false, reset active take to 1.0 before render/apply
    if not print_volumes then
      local current_tv = r.GetMediaItemTakeInfo_Value(tk_orig, "D_VOL") or 1.0
      volume_snap.merged_vol = current_tv
      r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", 1.0)
      if DBG and DBG >= 2 then
        dbg(DBG,2,"[GAIN] print_volumes=false; reset active take %.3f→1.0", current_tv)
      end
    end
  else
    -- merge_volumes=false: don't merge, remember original values
    volume_snap.merged_vol = r.GetMediaItemTakeInfo_Value(tk_orig, "D_VOL") or 1.0
    if DBG and DBG >= 2 then
      dbg(DBG,2,"[GAIN] merge_volumes=false; keeping item=%.3f, take=%.3f separate",
          item_vol, volume_snap.merged_vol)
    end

    -- If print_volumes=false, reset active take to 1.0
    if not print_volumes then
      r.SetMediaItemTakeInfo_Value(tk_orig, "D_VOL", 1.0)
      if DBG and DBG >= 2 then
        dbg(DBG,2,"[GAIN] print_volumes=false; reset active take %.3f→1.0", volume_snap.merged_vol)
      end
    end
  end

  return volume_snap
end

-- Restore/set volumes after render/apply
-- item: the processed item
-- volume_snap: snapshot from preprocess_item_volumes
-- new_take: the newly created take (from render/apply) - may be nil
-- old_take: the original take - may be nil
-- merge_volumes, print_volumes, merge_to_item: settings
local function postprocess_item_volumes(item, volume_snap, new_take, old_take, merge_volumes, print_volumes, merge_to_item, DBG)
  merge_to_item = merge_to_item or false

  if merge_to_item then
    -- === MERGE TO ITEM POSTPROCESS ===
    -- NOTE: Print ON is NOT supported with merge_to_item (GUI auto-switches to merge_to_take)
    -- PRINT OFF ONLY: Restore item volume (was set to 1.0 in preprocess)
    -- REAPER rendered with item×take = 1.0×1.0, audio is at original level
    -- Now restore item to combined, keep all takes at 1.0
    r.SetMediaItemInfo_Value(item, "D_VOL", volume_snap.merged_vol)
    -- Takes already at 1.0, no need to change
    if DBG and DBG >= 2 then
      dbg(DBG,2,"[GAIN] merge_to_item: restored item=%.3f, all takes=1.0", volume_snap.merged_vol)
    end

  elseif merge_volumes then
    -- === MERGE TO TAKE POSTPROCESS (ORIGINAL) ===
    if print_volumes then
      -- Merged+Print: item=1.0, new take=1.0, old takes keep merged
      r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
      if new_take then
        r.SetMediaItemTakeInfo_Value(new_take, "D_VOL", 1.0)
      end
      -- old_take already has merged volume from pre-merge phase
      if DBG and DBG >= 2 then
        local old_vol = old_take and r.GetMediaItemTakeInfo_Value(old_take, "D_VOL") or 0
        dbg(DBG,2,"[GAIN] print+merge; item=1.0, new=1.0, old=%.3f (kept)", old_vol)
      end
    else
      -- Merged: item=1.0, all takes=merged_vol
      r.SetMediaItemInfo_Value(item, "D_VOL", 1.0)
      if new_take then
        r.SetMediaItemTakeInfo_Value(new_take, "D_VOL", volume_snap.merged_vol)
      end
      if old_take then
        r.SetMediaItemTakeInfo_Value(old_take, "D_VOL", volume_snap.merged_vol)
      end
      if DBG and DBG >= 2 then
        dbg(DBG,2,"[GAIN] non-print+merge; item=1.0, takes=%.3f", volume_snap.merged_vol)
      end
    end

  else
    -- === NO MERGE (NATIVE REAPER BEHAVIOR) ===
    if print_volumes then
      -- Not merged: restore original item volume
      r.SetMediaItemInfo_Value(item, "D_VOL", volume_snap.item_vol)
      if new_take then
        r.SetMediaItemTakeInfo_Value(new_take, "D_VOL", 1.0)
      end
      if old_take then
        r.SetMediaItemTakeInfo_Value(old_take, "D_VOL", volume_snap.merged_vol)
      end
      if DBG and DBG >= 2 then
        dbg(DBG,2,"[GAIN] print; item=%.3f, new=1.0, old=%.3f",
            volume_snap.item_vol, volume_snap.merged_vol)
      end
    else
      -- Not merged: restore original volumes
      r.SetMediaItemInfo_Value(item, "D_VOL", volume_snap.item_vol)
      if new_take then
        r.SetMediaItemTakeInfo_Value(new_take, "D_VOL", volume_snap.merged_vol)
      end
      if old_take then
        r.SetMediaItemTakeInfo_Value(old_take, "D_VOL", volume_snap.merged_vol)
      end
      if DBG and DBG >= 2 then
        dbg(DBG,2,"[GAIN] non-print; item=%.3f, takes=%.3f",
            volume_snap.item_vol, volume_snap.merged_vol)
      end
    end
  end
end

------------------------------------------------------------
-- FX handling helpers
------------------------------------------------------------
-- Snapshot track FX enabled states
-- Returns: array of enabled states indexed by FX number
local function snapshot_track_fx(track)
  local snap = {}
  local fxn = r.TrackFX_GetCount(track) or 0
  for i = 0, fxn-1 do
    snap[i] = r.TrackFX_GetEnabled(track, i)
  end
  return snap
end

-- Restore track FX enabled states from snapshot
local function restore_track_fx(track, snap)
  if not snap then return end
  for i, enabled in pairs(snap) do
    r.TrackFX_SetEnabled(track, i, enabled)
  end
end

-- Disable all track FX
local function disable_all_track_fx(track)
  local fxn = r.TrackFX_GetCount(track) or 0
  for i = 0, fxn-1 do
    r.TrackFX_SetEnabled(track, i, false)
  end
  return fxn
end

-- Snapshot take FX offline states
-- Returns: array of offline states indexed by FX number
local function snapshot_take_fx_offline(take)
  if not take then return nil end
  local snap = {}
  local n = r.TakeFX_GetCount(take) or 0
  for i = 0, n-1 do
    snap[i] = r.TakeFX_GetOffline(take, i)
  end
  return snap
end

-- Restore take FX offline states from snapshot
local function restore_take_fx_offline(take, snap)
  if not (take and snap) then return end
  for i, offline in pairs(snap) do
    r.TakeFX_SetOffline(take, i, offline)
  end
end

-- Offline all non-offline take FX
-- Returns: count of FX that were offlined
local function offline_all_online_take_fx(take)
  if not take then return 0 end
  local n = r.TakeFX_GetCount(take) or 0
  local count = 0
  for i = 0, n-1 do
    if not r.TakeFX_GetOffline(take, i) then
      r.TakeFX_SetOffline(take, i, true)
      count = count + 1
    end
  end
  return count
end

------------------------------------------------------------
-- Selection / grouping helpers
------------------------------------------------------------
local function count_selected_items() return r.CountSelectedMediaItems(0) end
local function get_sel_items()
  local t, n = {}, r.CountSelectedMediaItems(0)
  for i=0,n-1 do t[#t+1] = r.GetSelectedMediaItem(0,i) end
  return t
end

local function item_span(it)
  local pos = r.GetMediaItemInfo_Value(it,"D_POSITION")
  local len = r.GetMediaItemInfo_Value(it,"D_LENGTH")
  return pos, pos+len, len
end

local function get_take_name(it)
  local tk = r.GetActiveTake(it)
  if not tk then return nil end
  local _, nm = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
  return nm
end

local function set_take_name(it, newn)
  local tk = r.GetActiveTake(it)
  if tk and newn and newn~="" then
    r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", newn, true)
  end
end

local function select_only_items(items)
  r.SelectAllMediaItems(0,false)
  for _,it in ipairs(items) do
    if r.ValidatePtr2(0,it,"MediaItem*") then r.SetMediaItemSelected(it, true) end
  end
  r.UpdateArrange()
end

local function find_item_by_span_on_track(tr, L, R, tol)
  tol = tol or 0.002
  local n = r.CountTrackMediaItems(tr)
  for i=0,n-1 do
    local it = r.GetTrackMediaItem(tr,i)
    local p0,p1 = item_span(it)
    if math.abs(p0-L)<=tol and math.abs(p1-R)<=tol then return it end
  end
  return nil
end

------------------------------------------------------------
-- Unit detection (same track)
------------------------------------------------------------
local function sort_items_by_pos(items)
  table.sort(items, function(a,b)
    local aL = r.GetMediaItemInfo_Value(a,"D_POSITION")
    local bL = r.GetMediaItemInfo_Value(b,"D_POSITION")
    if aL~=bL then return aL<bL end
    local aR = aL + r.GetMediaItemInfo_Value(a,"D_LENGTH")
    local bR = bL + r.GetMediaItemInfo_Value(b,"D_LENGTH")
    return aR<bR
  end)
end

local function detect_units_same_track(items, eps_s)
  local units = {}
  if #items==0 then return units end
  sort_items_by_pos(items)

  local i=1
  while i<=#items do
    local a = items[i]
    local aL,aR = item_span(a)
    if i==#items then
      units[#units+1] = {kind="SINGLE", members={{it=a,L=aL,R=aR}}, start=aL, finish=aR}
      break
    end

    local members = { {it=a,L=aL,R=aR} }
    local anyTouch, anyOverlap = false, false
    local cur_start, cur_end = aL, aR

    local j=i+1
    while j<=#items do
      local itj = items[j]
      local L,R = item_span(itj)
      if L - cur_end > eps_s then break end
      if L >= cur_end - eps_s and L <= cur_end + eps_s then anyTouch=true end
      if L <  cur_end - eps_s then anyOverlap=true end
      members[#members+1] = {it=itj,L=L,R=R}
      if R>cur_end then cur_end=R end
      j=j+1
    end

    local kind
    if #members==1 then kind="SINGLE"
    elseif anyOverlap and anyTouch then kind="MIXED"
    elseif anyOverlap then kind="CROSSFADE"
    else kind="TOUCH" end

    units[#units+1] = {kind=kind, members=members, start=cur_start, finish=cur_end}
    i=j
  end
  return units
end

local function collect_by_track_from_selection()
  local by_tr, tracks = {}, {}
  local sel = get_sel_items()
  for _,it in ipairs(sel) do
    local tr = r.GetMediaItem_Track(it)
    if not by_tr[tr] then by_tr[tr]={}; tracks[#tracks+1]=tr end
    by_tr[tr][#by_tr[tr]+1] = it
  end
  table.sort(tracks, function(a,b)
    return (r.GetMediaTrackInfo_Value(a,"IP_TRACKNUMBER") or 0) < (r.GetMediaTrackInfo_Value(b,"IP_TRACKNUMBER") or 0)
  end)
  return by_tr, tracks
end

-- Time Selection helpers --------------------------------------------
local function get_current_ts()
  local L, R = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has = (R - L) > 1e-9
  return L, R, has
end

local function span_of_selected_items()
  local items = get_sel_items()
  if #items == 0 then return nil, nil, 0 end
  local L, R = math.huge, -math.huge
  for _, it in ipairs(items) do
    local iL, iR = item_span(it)
    if iL < L then L = iL end
    if iR > R then R = iR end
  end
  if L == math.huge then return nil, nil, 0 end
  return L, R, #items
end

local function approximately_equal_span(aL, aR, bL, bR, tol)
  tol = tol or 0.002
  return (math.abs((aL or 0) - (bL or 0)) <= tol)
     and (math.abs((aR or 0) - (bR or 0)) <= tol)
end

local function item_intersects_ts(it, L, R)
  local iL, iR = item_span(it)
  return (iR > L) and (iL < R)
end

local function collect_items_intersect_ts_by_track(tsL, tsR)
  local by_tr, tracks = {}, {}
  local sel = get_sel_items()
  for _, it in ipairs(sel) do
    if item_intersects_ts(it, tsL, tsR) then
      local tr = r.GetMediaItem_Track(it)
      if not by_tr[tr] then by_tr[tr] = {}; tracks[#tracks+1] = tr end
      by_tr[tr][#by_tr[tr]+1] = it
    end
  end
  table.sort(tracks, function(a,b)
    return (r.GetMediaTrackInfo_Value(a,"IP_TRACKNUMBER") or 0) < (r.GetMediaTrackInfo_Value(b,"IP_TRACKNUMBER") or 0)
  end)
  return by_tr, tracks
end
------------------------------------------------------------
-- Handle window / clamp
------------------------------------------------------------
local function per_member_window_lr(it, L, R, H_left, H_right)
  local tk   = r.GetActiveTake(it)
  local rate = tk and (r.GetMediaItemTakeInfo_Value(tk,"D_PLAYRATE") or 1.0) or 1.0
  local offs = tk and (r.GetMediaItemTakeInfo_Value(tk,"D_STARTOFFS") or 0.0) or 0.0
  local src  = tk and r.GetMediaItemTake_Source(tk) or nil
  local src_len = src and ({r.GetMediaSourceLength(src)})[1] or math.huge

  local cur_len = R - L

  local max_left_ext  = offs / rate
  local wantL         = L - (H_left or 0.0)
  local gotL          = (wantL < (L - max_left_ext)) and (L - max_left_ext) or wantL

  local max_right_ext = ((src_len - offs) / rate) - cur_len
  if max_right_ext < 0 then max_right_ext = 0 end
  local wantR = R + (H_right or 0.0)
  local gotR  = (wantR > (R + max_right_ext)) and (R + max_right_ext) or wantR

  local clampL = (gotL > wantL + 1e-9)
  local clampR = (gotR < wantR - 1e-9)

  return {
    tk=tk, rate=rate, offs=offs,
    L=L, R=R, wantL=wantL, wantR=wantR, gotL=gotL, gotR=gotR,
    clampL=clampL, clampR=clampR,
    leftH=H_left or 0.0, rightH=H_right or 0.0,
    name=get_take_name(it)
  }
end

------------------------------------------------------------
-- #in/#out edge cues (kept for media-cue workflows)
------------------------------------------------------------
local function add_edge_cues(UL, UR, color)
  local proj = 0
  color = color or 0
  local in_id  = r.AddProjectMarker2(proj, false, UL, 0, "#in",  -1, color)
  local out_id = r.AddProjectMarker2(proj, false, UR, 0, "#out", -1, color)
  return {in_id, out_id}
end

------------------------------------------------------------
-- Glue Cues: #Glue: <TakeName> markers (shared function)
------------------------------------------------------------
-- Analyzes members, builds source sequence, writes project markers
-- Returns: array of marker IDs (or nil if no markers written)
-- Parameters:
--   members: array of {it=MediaItem*, L=pos, ...}
--   unit_start: unit start position (for head cue if needed)
--   DBG: debug level
--   tag: optional debug tag (e.g., "GAP", "TS")
local function add_glue_cues(members, unit_start, DBG, tag)
  if not members or #members < 2 then return nil end

  tag = tag or ""

  -- Helper: get source file path
  local function src_path_of(it)
    local tk  = reaper.GetActiveTake(it)
    if not tk then return nil end
    local src = reaper.GetMediaItemTake_Source(tk)
    if not src then return nil end
    local p   = reaper.GetMediaSourceFileName(src, "") or ""
    p = p:gsub("\\","/"):gsub("^%s+",""):gsub("%s+$","")
    return (p ~= "") and p or nil
  end

  -- Helper: get take name
  local function take_name_of(it)
    local tk = reaper.GetActiveTake(it)
    if not tk then return nil end
    local ok, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
    return (ok and nm ~= "" and nm) or reaper.GetTakeName(tk) or nil
  end

  -- Build source sequence
  local seq, uniq = {}, {}
  for _, m in ipairs(members) do
    local p = src_path_of(m.it) or ("<no-src>")
    seq[#seq+1] = { L = m.L, path = p, it = m.it }
    uniq[p] = true
  end

  -- Count unique sources
  local unique_count = 0
  for _ in pairs(uniq) do unique_count = unique_count + 1 end

  -- Only write cues if there are 2+ different sources
  if unique_count < 2 then return nil end

  -- Build marks_abs array
  local marks_abs = {}

  -- Head cue (at unit start)
  local head_name = take_name_of(members[1].it) or ((seq[1].path or ""):match("([^/]+)$") or "")
  marks_abs[#marks_abs+1] = { abs = unit_start, name = head_name }

  -- Boundary cues where source changes
  for i = 1, (#seq - 1) do
    if seq[i].path ~= seq[i+1].path then
      local next_name = take_name_of(members[i+1].it) or ((seq[i+1].path or ""):match("([^/]+)$") or "")
      marks_abs[#marks_abs+1] = { abs = seq[i+1].L, name = next_name }
    end
  end

  -- Write project markers
  if #marks_abs == 0 then return nil end

  local glue_ids = {}
  for _, mk in ipairs(marks_abs) do
    local raw = mk.name or ""
    raw = raw:gsub("^%s*GlueCue:%s*", "")  -- strip legacy prefix if any
    local label = ("#Glue: %s"):format(raw)
    local id = reaper.AddProjectMarker2(0, false, mk.abs or unit_start, 0, label, -1, 0)
    glue_ids[#glue_ids+1] = id
    if DBG >= 2 then
      local debug_tag = (tag ~= "") and ("[GLUE-CUE][" .. tag .. "]") or "[GLUE-CUE]"
      dbg(DBG, 2, "%s add @ %.3f  label=%s  id=%s", debug_tag, mk.abs or unit_start, label, tostring(id))
    end
  end

  return glue_ids
end

local function remove_markers_by_ids(ids)
  if not ids then return end
  local proj = 0
  for _,id in ipairs(ids) do r.DeleteProjectMarker(proj, id, false) end
end

--[[
------------------------------------------------------------
-- Rename helpers
------------------------------------------------------------
local function strip_suffixes(base)
  if not base then return base, 0, false, false end
  local n=0
  base = base:gsub("[-_]TakeFX_TrackFX$", function() return "" end)
  base = base:gsub("[-_]TrackFX$",        function() return "" end)
  base = base:gsub("[-_]TakeFX$",         function() return "" end)
  base = base:gsub("[-_]rendered(%d+)$",  function(d) n=tonumber(d) or n; return "" end)
  base = base:gsub("[-_]glued(%d+)$",     function(d) n=tonumber(d) or n; return "" end)
  return base, n, false, false
end

-- 把 -takefx / -trackfx 插在真正的音訊副檔名（.wav/.aif/.aiff/...）之前
-- 若找不到副檔名，就附加在字串尾端。已存在就不重複加（冪等）。
local _KNOWN_EXTS = { ".wav", ".aif", ".aiff", ".flac", ".mp3", ".ogg", ".wv", ".caf", ".m4a" }

local function _split_name_by_audio_ext(nm)
  if not nm or nm == "" then return "", "", "" end
  local lower = string.lower(nm)
  local s_best, e_best = nil, nil
  for _, ext in ipairs(_KNOWN_EXTS) do
    local s, e = 1, 0
    while true do
      s, e = lower:find(ext, e + 1, true)
      if not s then break end
      s_best, e_best = s, e
    end
  end
  if s_best then
    -- stem | .ext | tail（例如 "foo" | ".wav" | "-rendered1-TrackFX"）
    return nm:sub(1, s_best - 1), nm:sub(s_best, e_best), nm:sub(e_best + 1)
  else
    return nm, "", ""
  end
end

local function _has_tag_in_stem(stem, tag)
  if not stem or stem == "" then return false end
  return stem:lower():find("-" .. tag:lower(), 1, true) ~= nil
end

local function _add_tag_once_in_stem(stem, tag)
  if _has_tag_in_stem(stem, tag) then return stem end
  return (stem or "") .. "-" .. tag
end

-- op 參數保留相容性；實際不再分 glue/render 模式
function compute_new_name(op, oldn, flags)
  local stem, ext, tail = _split_name_by_audio_ext(oldn or "")

  local want_take  = flags and flags.takePrinted  == true
  local want_track = flags and flags.trackPrinted == true

  -- 固定順序：takefx → trackfx
  if want_take  then stem = _add_tag_once_in_stem(stem, "takefx")  end
  if want_track then stem = _add_tag_once_in_stem(stem, "trackfx") end

  return stem .. ext .. tail
end
]]--

------------------------------------------------------------
-- FX utilities
------------------------------------------------------------
local function get_apply_cmd(mode) return (mode=="multi") and ACT_APPLY_MULTI or ACT_APPLY_MONO end

local function clear_take_fx_for_items(items)
  if #items==0 then return end
  select_only_items(items)
  r.Main_OnCommand(ACT_REMOVE_TAKE_FX, 0)
end

local function apply_track_take_fx_to_item(it, apply_mode, dbg_level)
  r.SelectAllMediaItems(0,false)
  r.SetMediaItemSelected(it,true)
  local cmd = get_apply_cmd(apply_mode)
  dbg(dbg_level,1,"[RUN] Apply Track/Take FX (%s) to 1 item.", apply_mode)
  r.Main_OnCommand(cmd, 0)
end

-- Disable all TRACK FX on a track and return a snapshot of enabled states
local function disable_trackfx_with_snapshot(tr)
  if not tr then return nil end
  local n = r.TrackFX_GetCount(tr) or 0
  local snap = {}
  for i = 0, n-1 do
    local on = r.TrackFX_GetEnabled(tr, i)
    snap[i] = on and true or false
    if on then r.TrackFX_SetEnabled(tr, i, false) end
  end
  return snap
end

local function restore_trackfx_from_snapshot(tr, snap)
  if not (tr and snap) then return end
  for i, on in pairs(snap) do r.TrackFX_SetEnabled(tr, i, on and true or false) end
end

-- Apply multichannel (41993) WITHOUT baking any TRACK FX, and only bake TAKE FX when keep_take_fx=true
-- preserve_track_ch: if true, restore track channel count after apply (default: true for backward compatibility)
--                    if false, allow track channel count to change (for AudioSweet Multi-Channel Policy)
--                    Can also be controlled via ExtState: RGWH_PRESERVE_TRACK_CH = "0" (disable) or "1" (enable, default)
local function apply_multichannel_no_fx_preserve_take(it, keep_take_fx, dbg_level, preserve_track_ch)
  if not it then return end
  local tr = r.GetMediaItem_Track(it)
  local tk = r.GetActiveTake(it)

  -- Check ExtState first (allows AudioSweet to control without API change)
  if preserve_track_ch == nil then
    local ext_preserve = r.GetExtState("hsuanice_AS", "RGWH_PRESERVE_TRACK_CH")
    if ext_preserve == "0" then
      preserve_track_ch = false
    else
      preserve_track_ch = true  -- Default true for backward compatibility
    end
  end

  -- Snapshot original track channel count
  -- Issue: Track FX may auto-expand when processing multichannel sources
  local orig_track_ch = tr and (r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2) or 2

  local tr_snap = disable_trackfx_with_snapshot(tr)
  local tk_snap = snapshot_takefx_offline(tk)
  if tk and (not keep_take_fx) then
    temp_offline_nonoffline_fx(tk)
  end

  local fade_snap = snapshot_fades(it)
  zero_fades(it)

  r.SelectAllMediaItems(0,false)
  r.SetMediaItemSelected(it,true)
  dbg(dbg_level,1,"[APPLY] multi(no-FX) via 41993 (keep_take_fx=%s, preserve_track_ch=%s)", tostring(keep_take_fx), tostring(preserve_track_ch))
  r.Main_OnCommand(ACT_APPLY_MULTI, 0)

  -- Restore original track channel count if it was auto-expanded (only if preserve_track_ch is true)
  -- This can happen when Track FX expand to accommodate wider source
  if preserve_track_ch then
    local new_track_ch = tr and (r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2) or 2
    if tr and new_track_ch ~= orig_track_ch then
      r.SetMediaTrackInfo_Value(tr, "I_NCHAN", orig_track_ch)
      dbg(dbg_level,1,"[APPLY] Track channel auto-expanded %d→%d, restored to %d (preserve policy)", orig_track_ch, new_track_ch, orig_track_ch)
    end
  else
    local new_track_ch = tr and (r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2) or 2
    if new_track_ch ~= orig_track_ch then
      dbg(dbg_level,1,"[APPLY] Track channel changed %d→%d (preserve disabled for AudioSweet)", orig_track_ch, new_track_ch)
    end
  end

  -- restore states
  restore_trackfx_from_snapshot(tr, tr_snap)
  restore_takefx_offline(tk, tk_snap)
  restore_fades(it, fade_snap)
end

-- Central helper: embed CURRENT BWF TimeReference for a given item/take
-- Used after GLUE + Apply (40361/41993) to emulate native Glue behavior.
local function embed_current_tc_for_item(item, ref_pos, DBG)
  if not (item and ref_pos) then return end
  local tk = r.GetActiveTake(item)
  if not tk then return end
  local smp = E.TR_FromItemStart(tk, ref_pos)
  local src = r.GetMediaItemTake_Source(tk)
  local path = src and r.GetMediaSourceFileName(src, "") or ""
  if path ~= "" and path:lower():sub(-4) == ".wav" then
    local ok = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
    if DBG and DBG >= 2 then dbg(DBG, 2, "[TR][EMBED] current write=%s  samples=%d  path=%s", tostring(ok), smp, path) end
    -- Force REAPER to reload newly embedded metadata (offline -> online)
    if ok then
      E.Refresh_Items({ tk })
      if DBG and DBG >= 2 then dbg(DBG, 2, "[TR][REFRESH] toggled offline/online for 1 take") end
    end
  end
end
------------------------------------------------------------
-- GLUE FLOW (per unit)
------------------------------------------------------------
local function glue_unit(tr, u, cfg)
  local DBG    = cfg.DEBUG_LEVEL or 1
  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0
  local eps_s  = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  -- Per-unit channel mode detection when GLUE_APPLY_MODE=="auto"
  local unit_apply_mode = cfg.GLUE_APPLY_MODE
  if cfg.GLUE_APPLY_MODE == "auto" then
    -- Determine mono/multi based on max channels across all members in this unit
    local function get_item_playback_channels(it)
      if not it then return 2 end
      local tk = reaper.GetActiveTake(it)
      if not tk then return 2 end

      -- Check take's channel mode setting
      local chanmode = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE")
      -- chanmode 2=downmix, 3=left only, 4=right only → mono
      if chanmode == 2 or chanmode == 3 or chanmode == 4 then
        return 1
      end

      -- Otherwise use source channels
      local src = reaper.GetMediaItemTake_Source(tk)
      return src and (reaper.GetMediaSourceNumChannels(src) or 2) or 2
    end

    local maxch = 1
    for _, m in ipairs(u.members or {}) do
      local ch = get_item_playback_channels(m.it)
      if ch > maxch then maxch = ch end
    end
    unit_apply_mode = (maxch >= 2) and "multi" or "mono"
  end

  -- Special handling for GAP units (multiple items with gaps)
  -- Use simplified glue without handle extension (like native 42432)
  if u.kind == "GAP" then
    dbg(DBG,1,"[RUN] GAP unit: %d items, span=%.3f..%.3f (using native glue behavior)", #u.members, u.start, u.finish)

    -- Select all items (without modification)
    local items_sel = {}
    for i,m in ipairs(u.members) do items_sel[i]=m.it end
    select_only_items(items_sel)

    -- Clear take FX if policy says so
    if not cfg.GLUE_TAKE_FX then
      clear_take_fx_for_items(items_sel)
      dbg(DBG,1,"[TAKE-FX] cleared (policy=OFF) for GAP unit.")
    end

    -- Prepare Glue Cues for GAP unit using shared function
    local gap_glue_ids = nil
    if cfg.WRITE_GLUE_CUES then
      gap_glue_ids = add_glue_cues(u.members, u.start, DBG, "GAP")
    end

    -- Set TS to overall span and glue
    r.GetSet_LoopTimeRange(true, false, u.start, u.finish, false)
    r.Main_OnCommand(ACT_GLUE_TS, 0)

    -- Clean up project markers (now embedded in media)
    if gap_glue_ids and #gap_glue_ids > 0 then
      remove_markers_by_ids(gap_glue_ids)
      if DBG >= 2 then dbg(DBG,2,"[GLUE-CUE] GAP removed %d temp markers.", #gap_glue_ids) end
    end

    -- Find glued item
    local glued = find_item_by_span_on_track(tr, u.start, u.finish, 0.002)
    if glued and cfg.GLUE_TRACK_FX then
      r.SetMediaItemInfo_Value(glued, "D_FADEINLEN", 0)
      r.SetMediaItemInfo_Value(glued, "D_FADEINLEN_AUTO", 0)
      r.SetMediaItemInfo_Value(glued, "D_FADEOUTLEN", 0)
      r.SetMediaItemInfo_Value(glued, "D_FADEOUTLEN_AUTO", 0)
      apply_track_take_fx_to_item(glued, unit_apply_mode, DBG)
      embed_current_tc_for_item(glued, u.start, DBG)
    elseif glued
       and (unit_apply_mode == "multi")
       and (cfg.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi") then
      apply_multichannel_no_fx_preserve_take(glued, (cfg.GLUE_TAKE_FX == true), DBG)
      embed_current_tc_for_item(glued, u.start, DBG)
    end

    r.GetSet_LoopTimeRange(true, false, 0, 0, false)
    dbg(DBG,1,"[RUN] GAP unit glued: %.3f..%.3f", u.start, u.finish)
    return
  end

  -- Prepare Glue Cues using shared function (skipped for SINGLE units)
  -- Rule: write a cue only when adjacent items switch to a different file source.

  -- 保存左右邊界淡入淡出（之後還原）
  local members = {}
  for i,m in ipairs(u.members) do members[i]=m end
  local first_it = members[1] and members[1].it or nil
  local last_it  = members[#members] and members[#members].it or nil

  local fin_len, fin_dir, fin_shape, fin_auto = 0,0,0,0
  local fout_len, fout_dir, fout_shape, fout_auto = 0,0,0,0
  if first_it then
    fin_len   = r.GetMediaItemInfo_Value(first_it,"D_FADEINLEN") or 0
    fin_dir   = r.GetMediaItemInfo_Value(first_it,"D_FADEINDIR") or 0
    fin_shape = r.GetMediaItemInfo_Value(first_it,"C_FADEINSHAPE") or 0
    fin_auto  = r.GetMediaItemInfo_Value(first_it,"D_FADEINLEN_AUTO") or 0
  end
  if last_it then
    fout_len   = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTLEN") or 0
    fout_dir   = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTDIR") or 0
    fout_shape = r.GetMediaItemInfo_Value(last_it,"C_FADEOUTSHAPE") or 0
    fout_auto  = r.GetMediaItemInfo_Value(last_it,"D_FADEOUTLEN_AUTO") or 0
  end

  -- 計算 UL/UR（handles + clamp）
  -- If TS exists and its edge is outside unit edge, extend handle to TS edge
  local tsL, tsR, hasTS = get_current_ts()

  -- Calculate unit's natural span (before handles)
  local unitL, unitR = math.huge, -math.huge
  for _, m in ipairs(members) do
    if m.L < unitL then unitL = m.L end
    if m.R > unitR then unitR = m.R end
  end

  -- Debug: show TS vs unit relationship
  if hasTS then
    dbg(DBG,1,"[TS-UNIT] TS=%.3f..%.3f, unit=%.3f..%.3f, eps=%.5f", tsL, tsR, unitL, unitR, eps_s)
    local ts_left_at_or_outside = (tsL <= unitL + eps_s)  -- At edge or outside
    local ts_right_at_or_outside = (tsR >= unitR - eps_s)  -- At edge or outside
    dbg(DBG,1,"[TS-UNIT] TS_left %s unit_left (%.3f %s %.3f), TS_right %s unit_right (%.3f %s %.3f)",
        ts_left_at_or_outside and "AT/OUTSIDE" or "INSIDE",
        tsL, ts_left_at_or_outside and "<=" or ">", unitL + eps_s,
        ts_right_at_or_outside and "AT/OUTSIDE" or "INSIDE",
        tsR, ts_right_at_or_outside and ">=" or "<", unitR - eps_s)
  else
    dbg(DBG,1,"[TS-UNIT] No TS, unit=%.3f..%.3f", unitL, unitR)
  end

  -- Determine handle size for each edge
  -- NEW LOGIC: Only apply handles when TS exactly equals unit edges (both sides aligned)
  local H_left_final = 0.0
  local H_right_final = 0.0

  if hasTS then
    -- Check if TS equals unit on both sides (within epsilon)
    local ts_equals_unit_left  = math.abs(tsL - unitL) <= eps_s
    local ts_equals_unit_right = math.abs(tsR - unitR) <= eps_s
    local ts_equals_unit = ts_equals_unit_left and ts_equals_unit_right

    if ts_equals_unit then
      -- TS exactly matches unit → apply default handles
      H_left_final = HANDLE
      H_right_final = HANDLE
      dbg(DBG,1,"[HANDLE] TS=Unit (%.3f..%.3f ≈ %.3f..%.3f) → Left: %.3f, Right: %.3f",
          tsL, tsR, unitL, unitR, H_left_final, H_right_final)
    else
      -- TS doesn't match unit → no handles
      dbg(DBG,1,"[HANDLE] TS≠Unit (TS=%.3f..%.3f, unit=%.3f..%.3f) → No handles (0.0)",
          tsL, tsR, unitL, unitR)
    end
  else
    -- No TS → use default handles
    H_left_final = HANDLE
    H_right_final = HANDLE
    dbg(DBG,1,"[HANDLE] No TS → Left: %.3f, Right: %.3f (config default)", H_left_final, H_right_final)
  end

  local UL, UR = math.huge, -math.huge
  local details = {}
  for idx, m in ipairs(members) do
    local H_left  = (idx==1) and H_left_final or 0.0
    local H_right = (idx==#members) and H_right_final or 0.0
    local d = per_member_window_lr(m.it, m.L, m.R, H_left, H_right)
    UL = math.min(UL, d.gotL)
    UR = math.max(UR, d.gotR)
    details[idx] = d
  end

  dbg(DBG,1,"[RUN] unit kind=%s members=%d UL=%.3f UR=%.3f dur=%.3f", u.kind,#members,UL,UR,UR-UL)
  if DBG>=2 then
    for i,d in ipairs(details) do
      dbg(DBG,2,"       member#%d want=%.3f..%.3f -> got=%.3f..%.3f  clampL=%s clampR=%s  name=%s",
        i, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), d.name or "(none)")
    end
  end

  -- RENDER_TAKE_FX=0 → 先清空成員的 take FX（避免被 Glue 印入）
  if not cfg.GLUE_TAKE_FX then
    local items = {}
    for i,m in ipairs(members) do items[i]=m.it end
    clear_take_fx_for_items(items)
    dbg(DBG,1,"[TAKE-FX] cleared (policy=OFF) for this unit.")
  end

  -- Write #in/#out (unit span) as media cues when enabled
  local edge_ids = nil
  if cfg.WRITE_EDGE_CUES then
    edge_ids = add_edge_cues(u.start, u.finish, 0)
    dbg(DBG,1,"[EDGE-CUE] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", u.start, u.finish, tostring(edge_ids[1]), tostring(edge_ids[2]))
  end

  -- Pre-embed Glue Cues using shared function
  local glue_ids = nil
  if cfg.WRITE_GLUE_CUES and u.kind ~= "SINGLE" then
    glue_ids = add_glue_cues(members, u.start, DBG)
  end




  -- 選取並暫時把左右最外側 item 撐到 UL/UR 以吃到 handles
  local items_sel = {}
  for i,m in ipairs(members) do items_sel[i]=m.it end
  select_only_items(items_sel)

  for idx, m in ipairs(members) do
    local it = m.it
    local d  = details[idx]
    local newL = (idx==1) and d.gotL or m.L
    local newR = (idx==#members) and d.gotR or m.R
    r.SetMediaItemInfo_Value(it,"D_POSITION", newL)
    r.SetMediaItemInfo_Value(it,"D_LENGTH",   newR - newL)

    -- CRITICAL: Adjust D_STARTOFFS when extending LEFT
    -- When item extends left (e.g., from 16.458 to 11.458), we need to adjust offset
    -- so that the extended portion reads from earlier in the source.
    -- Formula: new_offset = old_offset - (left_extension * playrate)
    if d.tk and idx == 1 then
      local deltaL = (m.L - newL)
      if deltaL > eps_s then
        -- Left side extended, adjust offset
        local new_off = d.offs - (deltaL * d.rate)
        r.SetMediaItemTakeInfo_Value(d.tk,"D_STARTOFFS", new_off)
        dbg(DBG,1,"[PRE-GLUE] member#%d: extended LEFT by %.3f (%.3f → %.3f)",
            idx, deltaL, m.L, newL)
        dbg(DBG,1,"[PRE-GLUE] Adjusted D_STARTOFFS: %.6f → %.6f (delta=%.6f, rate=%.3f)",
            d.offs, new_off, -deltaL * d.rate, d.rate)
      else
        dbg(DBG,2,"[PRE-GLUE] member#%d: No left extension, keeping original offs=%.6f",
            idx, d.offs)
      end
    end

    if DBG >= 2 and idx == #members then
      local deltaR = (newR - m.R)
      if deltaR > eps_s then
        dbg(DBG,2,"[PRE-GLUE] member#%d: extended RIGHT by %.3f (%.3f → %.3f)",
            idx, deltaR, m.R, newR)
      end
    end
  end

  -- Unified logic for ALL modes (mono/multi/auto): Glue → (conditionally) Apply
  -- 時選=UL..UR → Glue → (必要時)對成品 Apply → Trim 回 UL..UR

  -- Glue always uses native volume behavior (item+take printed).

  -- Snapshot track channel count before Glue
  -- Issue: Action 42432 (Glue) can auto-expand track channels when source > track channels
  local orig_track_ch = tr and (r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2) or 2

  r.GetSet_LoopTimeRange(true, false, UL, UR, false)
  r.Main_OnCommand(ACT_GLUE_TS, 0)

  -- Restore track channel count if Glue auto-expanded it
  local new_track_ch = tr and (r.GetMediaTrackInfo_Value(tr, "I_NCHAN") or 2) or 2
  if tr and new_track_ch ~= orig_track_ch then
    r.SetMediaTrackInfo_Value(tr, "I_NCHAN", orig_track_ch)
    dbg(DBG,1,"[GLUE] Track channel auto-expanded %d→%d by 42432, restored to %d", orig_track_ch, new_track_ch, orig_track_ch)
  end

  local glued_pre = find_item_by_span_on_track(tr, UL, UR, 0.002)

  -- Determine if we need Apply render
  local need_apply = false
  if cfg.GLUE_TRACK_FX and glued_pre then
    -- Need to print track FX
    need_apply = true
    dbg(DBG,1,"[APPLY] Need Apply to print track FX (mode=%s)", unit_apply_mode)
  elseif glued_pre
     and (unit_apply_mode == "multi")
     and (cfg.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi") then
    -- Need to force multi-channel output
    need_apply = true
    dbg(DBG,1,"[APPLY] Need Apply to force multi-channel output")
  else
    dbg(DBG,1,"[SKIP APPLY] No need to Apply - Glue already preserves take name → filename")
  end

  if need_apply and glued_pre then
    local merge_volumes = (cfg.GLUE_MERGE_VOLUMES == true)
    local print_volumes = (cfg.GLUE_PRINT_VOLUMES == true)
    local volume_snap = preprocess_item_volumes(glued_pre, merge_volumes, print_volumes, false, DBG)

    -- 清掉 fades（40361/41993 會把 fade 烘進音檔）
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN",       0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN_AUTO",  0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN",      0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN_AUTO", 0)

    if cfg.GLUE_TRACK_FX then
      apply_track_take_fx_to_item(glued_pre, unit_apply_mode, DBG)
      -- Emulate Glue's TC when GLUE+APPLY: embed CURRENT TC at unit start
      embed_current_tc_for_item(glued_pre, u.start, DBG)
    else
      -- force_multi without track FX
      apply_multichannel_no_fx_preserve_take(glued_pre, (cfg.GLUE_TAKE_FX == true), DBG)
      -- Emulate Glue's TC in force-multi no-track-FX path as well
      embed_current_tc_for_item(glued_pre, u.start, DBG)
    end

    if volume_snap then
      local gtk_final = r.GetActiveTake(glued_pre)
      postprocess_item_volumes(glued_pre, volume_snap, gtk_final, nil, merge_volumes, print_volumes, false, DBG)
    end
  end

  r.Main_OnCommand(ACT_TRIM_TO_TS, 0)

  -- 找到最後成品（UL..UR），移回 u.start..u.finish 並寫入 offset
  local glued = find_item_by_span_on_track(tr, UL, UR, 0.002)
  if glued then
    local left_total  = u.start - UL
    local right_total = UR - u.finish
    if left_total  < 0 then left_total  = 0 end
    if right_total < 0 then right_total = 0 end

    r.SetMediaItemInfo_Value(glued,"D_POSITION", u.start)
    r.SetMediaItemInfo_Value(glued,"D_LENGTH",   u.finish - u.start)
    local gtk = r.GetActiveTake(glued)
    if gtk then r.SetMediaItemTakeInfo_Value(gtk,"D_STARTOFFS", left_total) end
    r.UpdateItemInProject(glued)

    -- NEW: keep StartInSource consistent across ALL takes on the glued item
    do
      local tc = reaper.CountTakes(glued) or 0
      for ti = 0, tc-1 do
        local tk = reaper.GetTake(glued, ti)
        if tk then
          reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", left_total)
        end
      end
    end

    -- 還原邊界淡入淡出
    r.SetMediaItemInfo_Value(glued,"D_FADEINLEN",      fin_len)
    r.SetMediaItemInfo_Value(glued,"D_FADEINDIR",      fin_dir)
    r.SetMediaItemInfo_Value(glued,"C_FADEINSHAPE",    fin_shape)
    r.SetMediaItemInfo_Value(glued,"D_FADEINLEN_AUTO", fin_auto)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTLEN",      fout_len)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTDIR",      fout_dir)
    r.SetMediaItemInfo_Value(glued,"C_FADEOUTSHAPE",    fout_shape)
    r.SetMediaItemInfo_Value(glued,"D_FADEOUTLEN_AUTO", fout_auto)
    r.UpdateItemInProject(glued)

    -- Volume handling intentionally skipped for Glue (native behavior already prints item+take volume).

    -- (Removed legacy take-marker emission. Glue cues are now pre-written as project markers with '#'.)


    -- [GLUE NAME] Do not rename glued items; let REAPER auto-name (e.g. "...-glued-XX").
    -- (Intentionally no-op here to preserve REAPER's default glued naming.)
    -- dbg(DBG,2,"[NAME] Skip renaming glued item; keep REAPER's default.")


    dbg(DBG,1,"       post-glue: trimmed to [%.3f..%.3f], offs=%.3f (L=%.3f R=%.3f)",
      u.start, u.finish, left_total, left_total, right_total)
  else
    dbg(DBG,1,"       WARNING: glued item not found by span (UL=%.3f UR=%.3f)", UL, UR)
  end

  -- Clear time selection
  r.GetSet_LoopTimeRange(true, false, 0, 0, false)

  -- Clean up temporary project markers (common for both mono and multi/auto paths)
  if edge_ids then
    remove_markers_by_ids(edge_ids)
    dbg(DBG,1,"[EDGE-CUE] removed ids: %s, %s", tostring(edge_ids[1]), tostring(edge_ids[2]))
  end
  if glue_ids and #glue_ids>0 then
    remove_markers_by_ids(glue_ids)
    dbg(DBG,1,"[GLUE-CUE] removed %d temp markers.", #glue_ids)
  end




end

-- GLUE by explicit Time Selection window for a single track (NO handles; TS-Window parity with AudioSweet). Uses members_snapshot (original selection) to avoid selection churn.
local function glue_by_ts_window_on_track(tr, tsL, tsR, cfg, members_snapshot)
  local DBG = cfg.DEBUG_LEVEL or 1
  -- TS-Window rules:
  --   • No handles
  --   • Never write EDGE_CUES
  --   • WRITE_GLUE_CUES allowed (adjacent-different-source within TS)
  --   • If GLUE_TAKE_FX==false → clear take FX before glue (do not bake take-FX)
  --   • If GLUE_TRACK_FX==1    → Apply after glue (mono/multi/auto); else skip

  dbg(DBG,1,"[TS-GLUE] track#%d  GLUE_TAKE_FX=%s  GLUE_TRACK_FX=%s  apply_mode=%s  write_glue_cues=%s",
      r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1,
      tostring(cfg.GLUE_TAKE_FX), tostring(cfg.GLUE_TRACK_FX),
      tostring(cfg.GLUE_APPLY_MODE), tostring(cfg.WRITE_GLUE_CUES))

  -- use the original selection snapshot for this track (do NOT depend on live selection)
  local members = {}
  if type(members_snapshot) == "table" then
    for _, it in ipairs(members_snapshot) do
      if reaper.ValidatePtr2(0, it, "MediaItem*") then
        -- intersect with TS; keep original item span (L/R) and clamped span (iL/iR)
        local L, R = item_span(it)
        if item_intersects_ts(it, tsL, tsR) then
          local iL = (L < tsL) and tsL or L
          local iR = (R > tsR) and tsR or R
          members[#members+1] = { it = it, L = L, R = R, iL = iL, iR = iR }
        end
      end
    end
  end
  if #members == 0 then
    dbg(DBG,1,"[RUN] TS glue: no members on this track.")
    return
  end
  table.sort(members, function(a,b) return a.iL < b.iL end)

  -- SPLIT items at TS boundaries if edges cut through item interior (non-destructive behavior like native glue)
  -- This ensures items outside TS remain intact after glue operation
  local split_threshold = 0.002 -- tolerance for edge detection (2ms)
  for _, m in ipairs(members) do
    local it = m.it
    local L, R = m.L, m.R  -- original item span

    -- Check if tsL cuts through item interior (not at edge)
    if tsL > (L + split_threshold) and tsL < (R - split_threshold) then
      local new_item = r.SplitMediaItem(it, tsL)
      if new_item and DBG >= 2 then
        dbg(DBG, 2, "[TS-SPLIT] Split item at tsL=%.3f (track #%d)", tsL, r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1)
      end
    end

    -- Check if tsR cuts through item interior (not at edge)
    -- Note: After splitting at tsL, we need to find the correct item piece that contains tsR
    if tsR > (L + split_threshold) and tsR < (R - split_threshold) then
      -- Find the item at tsR position (might be the original or the right piece after tsL split)
      local item_at_tsR = nil
      local track_item_count = r.CountTrackMediaItems(tr)
      for i = 0, track_item_count - 1 do
        local candidate = r.GetTrackMediaItem(tr, i)
        local cL, cR = item_span(candidate)
        if cL <= tsR and cR >= tsR then
          item_at_tsR = candidate
          break
        end
      end

      if item_at_tsR then
        local new_item = r.SplitMediaItem(item_at_tsR, tsR)
        if new_item and DBG >= 2 then
          dbg(DBG, 2, "[TS-SPLIT] Split item at tsR=%.3f (track #%d)", tsR, r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1)
        end
      end
    end
  end

  -- After splitting, rebuild members list to include new split items within TS
  members = {}
  if type(members_snapshot) == "table" then
    for _, orig_it in ipairs(members_snapshot) do
      -- Check all items on track (original + splits) that intersect with TS
      local track_item_count = r.CountTrackMediaItems(tr)
      for i = 0, track_item_count - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        if reaper.ValidatePtr2(0, it, "MediaItem*") then
          local L, R = item_span(it)
          if item_intersects_ts(it, tsL, tsR) then
            -- Check if this item is within TS range (fully or partially)
            local iL = (L < tsL) and tsL or L
            local iR = (R > tsR) and tsR or R
            -- Only add if not already in members list
            local already_added = false
            for _, existing in ipairs(members) do
              if existing.it == it then
                already_added = true
                break
              end
            end
            if not already_added then
              members[#members+1] = { it = it, L = L, R = R, iL = iL, iR = iR }
            end
          end
        end
      end
    end
  end
  table.sort(members, function(a,b) return a.iL < b.iL end)

  if DBG >= 1 then
    dbg(DBG, 1, "[TS-GLUE] After boundary splits: %d items to glue within TS [%.3f, %.3f]", #members, tsL, tsR)
  end

  -- Check if TS exactly equals unit edges after split → use Units glue with handles instead
  if #members == 1 then
    local m = members[1]
    local eps_ts = 0.002  -- epsilon for TS=unit comparison
    if math.abs(m.L - tsL) < eps_ts and math.abs(m.R - tsR) < eps_ts then
      -- TS = unit edges after split → delegate to Units glue with handles
      dbg(DBG, 1, "[TS-GLUE] TS matches unit edges after split → delegating to Units glue with handles")
      -- Clear TS to trigger Units mode
      r.GetSet_LoopTimeRange(true, false, 0, 0, false)
      -- Build unit object for glue_unit
      local unit = {
        kind = "SINGLE",
        members = { { it = m.it, L = m.L, R = m.R } },
        start = m.L,
        finish = m.R
      }
      -- Call glue_unit (which will add handles)
      glue_unit(tr, unit, cfg)
      return
    end
  end

  -- Optional: WRITE_GLUE_CUES inside TS when sources switch
  -- Note: TS-Window uses clamped positions (iL) instead of original positions (L)
  -- We need to remap members for add_glue_cues() to use iL as L
  local glue_ids = nil
  if cfg.WRITE_GLUE_CUES and #members >= 2 then
    local remapped_members = {}
    for _, m in ipairs(members) do
      remapped_members[#remapped_members+1] = { it = m.it, L = m.iL }
    end
    glue_ids = add_glue_cues(remapped_members, tsL, DBG, "TS")
  end

  -- select only intersecting members for this track
  local items_sel = {}
  for i, m in ipairs(members) do items_sel[i] = m.it end
  select_only_items(items_sel)

  -- If policy says "do NOT bake take FX", clear take FX before glue
  if not cfg.GLUE_TAKE_FX then
    clear_take_fx_for_items(items_sel)
    dbg(DBG,1,"[TS-GLUE] cleared TAKE FX on %d item(s) (policy off)", #items_sel)
  end

  -- Glue strictly within TS (no handle extension)
  r.GetSet_LoopTimeRange(true, false, tsL, tsR, false)
  r.Main_OnCommand(ACT_GLUE_TS, 0)

  -- Apply (Track/Take) per policy: TS-Window treats GLUE_TAKE_FX as ON by design.
  local glued_pre = find_item_by_span_on_track(tr, tsL, tsR, 0.002)
  if cfg.GLUE_TRACK_FX and glued_pre then
    -- clear fades to avoid baking during apply
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN",       0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEINLEN_AUTO",  0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN",      0)
    r.SetMediaItemInfo_Value(glued_pre, "D_FADEOUTLEN_AUTO", 0)
    apply_track_take_fx_to_item(glued_pre, unit_apply_mode, DBG)
    -- Emulate Glue's TC when GLUE+APPLY (TS-Window): embed CURRENT TC at tsL
    embed_current_tc_for_item(glued_pre, tsL, DBG)
  elseif glued_pre
     and (unit_apply_mode == "multi")
     and (cfg.GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi") then
    apply_multichannel_no_fx_preserve_take(glued_pre, true, DBG)  -- keep take FX
    -- Emulate Glue’s TC in force-multi no-track-FX path as well (TS-Window)
    embed_current_tc_for_item(glued_pre, tsL, DBG)
  end

  -- Ensure exact TS window
  r.GetSet_LoopTimeRange(true, false, tsL, tsR, false)
  r.Main_OnCommand(ACT_TRIM_TO_TS, 0)

  local glued = find_item_by_span_on_track(tr, tsL, tsR, 0.002)
  if glued then
    r.SetMediaItemInfo_Value(glued, "D_POSITION", tsL)
    r.SetMediaItemInfo_Value(glued, "D_LENGTH",   tsR - tsL)
    r.UpdateItemInProject(glued)
    -- Re-select the glued item to ensure correct selection state
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(glued, true)
  else
    dbg(DBG,1,"[WARN] TS glue: glued item not found by span.")
  end

  -- clear TS and temporary markers
  r.GetSet_LoopTimeRange(true, false, 0, 0, false)
  if glue_ids and #glue_ids>0 then remove_markers_by_ids(glue_ids) end
end
------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------
-- Auto-scope glue: Units vs TS-Window
-- mode: "glue" = always use TS when present (no handles); "auto" = use original logic (units with handles)
local function glue_auto_scope(cfg, mode)
  local DBG = cfg.DEBUG_LEVEL or 1
  local tsL, tsR, hasTS = get_current_ts()
  local selL, selR, nsel = span_of_selected_items()

  if not hasTS then
    dbg(DBG,1,"[SCOPE] TS empty → Units glue.")
    return "units"
  end
  if nsel == 0 then
    dbg(DBG,1,"[SCOPE] No selection but TS present → TS glue.")
    return "ts", tsL, tsR
  end

  -- Both GLUE and AUTO modes: check if TS ≈ selection
  -- If TS ≈ selection → Units glue (with handles)
  -- If TS ≠ selection → TS glue (no handles)
  if approximately_equal_span(tsL, tsR, selL, selR, 0.002) then
    dbg(DBG,1,"[SCOPE] TS ≈ selection span → Units glue (with handles).")
    return "units"
  else
    dbg(DBG,1,"[SCOPE] TS differs from selection → TS glue (no handles).")
    return "ts", tsL, tsR
  end
end

function M.glue_selection(force_units)
  local cfg = M.read_settings()
  cfg.OP = "glue"  -- Set operation mode for glue_unit()
  local DBG = cfg.DEBUG_LEVEL or 1

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end

  local nsel = count_selected_items()
  if nsel==0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Glue (no selection)", -1); return
  end

  local eps_s = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  -- Note: When GLUE_APPLY_MODE=="auto", channel mode is now determined per-unit in glue_unit()

  dbg(DBG,1,"[RUN] Glue start  handles=%.3fs  epsilon=%.5fs  GLUE_SINGLE_ITEMS=%s  GLUE_TAKE_FX=%s  GLUE_TRACK_FX=%s  GLUE_APPLY_MODE=%s  WRITE_EDGE_CUES=%s  WRITE_GLUE_CUES=%s  GLUE_CUE_POLICY=%s",
    cfg.HANDLE_SECONDS or 0, eps_s, tostring(cfg.GLUE_SINGLE_ITEMS), tostring(cfg.GLUE_TAKE_FX),
    tostring(cfg.GLUE_TRACK_FX), cfg.GLUE_APPLY_MODE, tostring(cfg.WRITE_EDGE_CUES), tostring(cfg.WRITE_GLUE_CUES),
    "adjacent-different-source")

  -- Auto-detect scope: TS-Window vs Units glue
  -- If force_units=true, always use units glue (for core() API scope="units")
  -- Otherwise use auto-scope logic (TS exists → TS-Window, no TS → Units)
  local scope, tsL, tsR
  if force_units then
    scope = "units"
    dbg(DBG,1,"[SCOPE] Forced Units glue (via parameter)")
  else
    scope, tsL, tsR = glue_auto_scope(cfg, "glue")
  end

  if scope == "ts" then
    -- TS-Window glue path
    dbg(DBG,1,"[RUN] Using TS-Window glue: [%.3f, %.3f]", tsL, tsR)
    local by_tr, tracks = collect_items_intersect_ts_by_track(tsL, tsR)
    for _, tr in ipairs(tracks) do
      local snapshot = by_tr[tr]
      glue_by_ts_window_on_track(tr, tsL, tsR, cfg, snapshot)
    end
  else
    -- Units glue path
    dbg(DBG,1,"[RUN] Using Units glue")
    local by_tr, tr_list = collect_by_track_from_selection()
    for _,tr in ipairs(tr_list) do
      local list  = by_tr[tr]
      local units = detect_units_same_track(list, eps_s)
      dbg(DBG,1,"[RUN] Track #%d: units=%d", r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1, #units)

      -- When multiple units with gaps AND TS exists, treat them as one GAP unit
      -- Without TS: keep units separate for individual handle-aware processing
      local currentTsL, currentTsR, hasTS = get_current_ts()

      if #units > 1 and hasTS then
        -- Sort items by position
        table.sort(list, function(a,b)
          return r.GetMediaItemInfo_Value(a,"D_POSITION") < r.GetMediaItemInfo_Value(b,"D_POSITION")
        end)

        -- Calculate this track's items span
        local trackItemsL, trackItemsR = math.huge, -math.huge
        for _, it in ipairs(list) do
          local L, R = item_span(it)
          if L < trackItemsL then trackItemsL = L end
          if R > trackItemsR then trackItemsR = R end
        end

        -- Use TS edge if it's outside (or equal to) items edge
        local overallL = (currentTsL <= trackItemsL + eps_s) and currentTsL or trackItemsL
        local overallR = (currentTsR >= trackItemsR - eps_s) and currentTsR or trackItemsR
        dbg(DBG,1,"[RUN] GAP unit span: %.3f..%.3f (TS=%.3f..%.3f, items=%.3f..%.3f)",
            overallL, overallR, currentTsL, currentTsR, trackItemsL, trackItemsR)

        -- Create one synthetic unit containing all items (without modifying item lengths)
        local members = {}
        for _, it in ipairs(list) do
          local L, R = item_span(it)
          members[#members+1] = {it=it, L=L, R=R}
        end

        local synthetic_unit = {
          kind = "GAP",  -- Mark as having gaps
          members = members,
          start = overallL,
          finish = overallR
        }

        units = {synthetic_unit}
        dbg(DBG,1,"[RUN] Multiple units merged into GAP unit (span=%.3f..%.3f, %d items with gaps, TS exists)", overallL, overallR, #members)
      elseif #units > 1 then
        -- Multiple units but no TS: process each unit individually with handles
        dbg(DBG,1,"[RUN] Multiple units (%d) without TS → processing individually with handles", #units)
      end

      for ui,u in ipairs(units) do
        if u.kind=="SINGLE" and (not cfg.GLUE_SINGLE_ITEMS) then
          dbg(DBG,2,"[TRACE] unit#%d SINGLE skipped (option off).", ui)
        else
          glue_unit(tr, u, cfg)
        end
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("RGWH Core - Glue selection", -1)
end

function M.auto_selection(merge_volumes, print_volumes, merge_to_item)
  -- AUTO mode: Render single-item units, Glue multi-item units
  local cfg = M.read_settings()
  cfg.OP = "auto"  -- Set operation mode for glue_unit()
  local DBG = cfg.DEBUG_LEVEL or 1

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end

  local nsel = count_selected_items()
  if nsel==0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Auto (no selection)", -1); return
  end

  local eps_s = (cfg.EPSILON_MODE=="frames") and frames_to_seconds(cfg.EPSILON_VALUE, get_sr(), nil) or (cfg.EPSILON_VALUE or 0.002)

  dbg(DBG,1,"[RUN] Auto start  handles=%.3fs  epsilon=%.5fs", cfg.HANDLE_SECONDS or 0, eps_s)

  -- Collect all items by track and detect units
  local by_tr, tr_list = collect_by_track_from_selection()
  local multi_units = {}   -- Multi-item units (to glue)
  local has_single = false -- Flag to check if there are single-item units

  for _,tr in ipairs(tr_list) do
    local list  = by_tr[tr]
    local units = detect_units_same_track(list, eps_s)
    dbg(DBG,1,"[RUN] Track #%d: units=%d", r.GetMediaTrackInfo_Value(tr,"IP_TRACKNUMBER") or -1, #units)

    for ui,u in ipairs(units) do
      if u.kind == "SINGLE" then
        dbg(DBG,2,"[TRACE] unit#%d SINGLE → keep selected for render", ui)
        has_single = true
        -- Keep single items selected (don't deselect them)
      else
        dbg(DBG,2,"[TRACE] unit#%d %s → will glue", ui, u.kind)
        table.insert(multi_units, {track=tr, unit=u})
        -- Deselect items in multi-item units (will be glued)
        for _, member in ipairs(u.members) do
          r.SetMediaItemSelected(member.it, false)
        end
      end
    end
  end

  -- First: Render single-item units (they are still selected)
  if has_single then
    local single_count = r.CountSelectedMediaItems(0)
    dbg(DBG,1,"[RUN] Rendering %d single items...", single_count)

    -- Call render_selection for currently selected items (single units)
    local merge_vols = (merge_volumes == nil) and true or (merge_volumes == true)
    local print_vols = (print_volumes == nil) and true or (print_volumes == true)
    local merge_to_i = (merge_to_item == nil) and false or (merge_to_item == true)

    -- render_selection has its own undo block, so we need to end ours first
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("RGWH Core - Auto (render phase)", -1)

    M.render_selection(nil, nil, nil, nil, merge_vols, print_vols, merge_to_i)

    -- Start new undo block for glue phase
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
  end

  -- Second: Glue all multi-item units
  if #multi_units > 0 then
    dbg(DBG,1,"[RUN] Gluing %d multi-item units...", #multi_units)

    -- AUTO mode: clear any existing TS to ensure Units glue with handles
    -- (TS may have been set by render phase or left over from previous operations)
    r.GetSet_LoopTimeRange(true, false, 0, 0, false)

    -- Reselect multi-item units for gluing
    r.SelectAllMediaItems(0, false)
    for _, mu in ipairs(multi_units) do
      for _, member in ipairs(mu.unit.members) do
        r.SetMediaItemSelected(member.it, true)
      end
    end

    -- Note: When GLUE_APPLY_MODE=="auto", channel mode is now determined per-unit in glue_unit()

    for _, mu in ipairs(multi_units) do
      glue_unit(mu.track, mu.unit, cfg)
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("RGWH Core - Auto selection", -1)
end

function M.render_selection(take_fx, track_fx, mode, tc_mode, merge_volumes, print_volumes, merge_to_item)
  local cfg = M.read_settings()
  local DBG = cfg.DEBUG_LEVEL or 1
  local items = get_sel_items()
  local nsel  = #items
  local r = reaper

  -- Optional parameter overrides (enable call-site control)
  if take_fx ~= nil then
    cfg.RENDER_TAKE_FX = (take_fx == 1 or take_fx == true)
  end
  if track_fx ~= nil then
    cfg.RENDER_TRACK_FX = (track_fx == 1 or track_fx == true)
  end
  if mode ~= nil then
    cfg.RENDER_APPLY_MODE = tostring(mode)
  end
  if tc_mode ~= nil then
    cfg.RENDER_TC_EMBED = tostring(tc_mode)
  end
  -- NEW: Volume control overrides (default: merge=true, print=true)
  if merge_volumes == nil then merge_volumes = true end
  if print_volumes == nil then print_volumes = true end
  if merge_to_item == nil then merge_to_item = false end
  cfg.RENDER_MERGE_VOLUMES = (merge_volumes == true)
  cfg.RENDER_PRINT_VOLUMES = (print_volumes == true)
  cfg.RENDER_MERGE_TO_ITEM = (merge_to_item == true)

  -- Note: When RENDER_APPLY_MODE=="auto", channel mode is now determined per-item in the render loop

  -- helpers (local to this function) -----------------------------------------
  local function snapshot_takefx_offline(tk)
    if not tk then return nil end
    local n = r.TakeFX_GetCount(tk) or 0
    local snap = {}
    for i = 0, n-1 do snap[i] = r.TakeFX_GetOffline(tk, i) and true or false end
    return snap
  end

  -- temporarily set offline=true ONLY for FX that were online
  local function temp_offline_nonoffline_fx(tk)
    if not tk then return 0 end
    local n = r.TakeFX_GetCount(tk) or 0
    local cnt = 0
    for i = 0, n-1 do
      if not r.TakeFX_GetOffline(tk, i) then
        r.TakeFX_SetOffline(tk, i, true)
        cnt = cnt + 1
      end
    end
    return cnt
  end

  local function restore_takefx_offline(tk, snap)
    if not (tk and snap) then return 0 end
    local n = r.TakeFX_GetCount(tk) or 0
    local cnt = 0
    for i = 0, n-1 do
      local want = snap[i]
      if want ~= nil then
        r.TakeFX_SetOffline(tk, i, want and true or false)
        cnt = cnt + 1
      end
    end
    return cnt
  end

  -- clone whole take-FX chain (states included) from src to dst
  local function clone_takefx_chain(src_tk, dst_tk)
    if not (src_tk and dst_tk) or src_tk == dst_tk then return 0 end
    -- clear dst first to avoid duplicates
    for i = (r.TakeFX_GetCount(dst_tk) or 0)-1, 0, -1 do r.TakeFX_Delete(dst_tk, i) end
    local n = r.TakeFX_GetCount(src_tk) or 0
    for i = 0, n-1 do r.TakeFX_CopyToTake(src_tk, i, dst_tk, i, false) end
    return n
  end

  -- fade helpers (shared with GLUE)
  -- snapshot_fades(it) -> table
  -- zero_fades(it)
  -- restore_fades(it, snap)
  -----------------------------------------------------------------------------

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end

  if nsel == 0 then
    dbg(DBG,1,"[RUN] No selected items.")
    r.PreventUIRefresh(-1); r.Undo_EndBlock("RGWH Core - Render (no selection)", -1); return
  end

  local HANDLE = (cfg.HANDLE_MODE=="seconds") and (cfg.HANDLE_SECONDS or 0.0) or 0.0

  dbg(DBG,1,"[RUN] Render start  mode=%s  TAKE=%s TRACK=%s  items=%d  handles=%.3fs  WRITE_EDGE_CUES=%s  GLUE_CUE_POLICY=%s",
      cfg.RENDER_APPLY_MODE, tostring(cfg.RENDER_TAKE_FX), tostring(cfg.RENDER_TRACK_FX),
      nsel, HANDLE, tostring(cfg.WRITE_EDGE_CUES), "adjacent-different-source")

  -- snapshot per-track FX enabled state (TRACK path has been stable)
  local tr_map = {}
  for _, it in ipairs(items) do
    local tr = r.GetMediaItem_Track(it)
    if tr and not tr_map[tr] then
      local fxn = r.TrackFX_GetCount(tr) or 0
      local rec = { track = tr, enabled = {} }
      for i = 0, fxn-1 do rec.enabled[i] = r.TrackFX_GetEnabled(tr, i) end
      tr_map[tr] = rec
    end
  end

  local need_track = (cfg.RENDER_TRACK_FX == true)
  local need_take  = (cfg.RENDER_TAKE_FX  == true)

  if not need_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      local fxn = r.TrackFX_GetCount(tr) or 0
      for i = 0, fxn-1 do r.TrackFX_SetEnabled(tr, i, false) end
    end
    dbg(DBG,1,"[RUN] Temporarily disabled TRACK FX (policy TRACK=0).")
  end

  -- pick render command
  local ACT_APPLY_MONO  = 40361 -- Apply track/take FX to items (mono)
  local ACT_APPLY_MULTI = 41993 -- Apply track/take FX to items (multichannel)
  local ACT_RENDER_PRES = 40601 -- Render items to new take (preserve source type)

  -- Helper function: determine mono/multi for a single item (used when RENDER_APPLY_MODE=="auto")
  local function get_item_apply_mode(it)
    if not it then return "mono" end
    local tk = reaper.GetActiveTake(it)
    if not tk then return "mono" end

    -- Check take's channel mode setting
    local chanmode = reaper.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE")
    -- chanmode 2=downmix, 3=left only, 4=right only → mono
    if chanmode == 2 or chanmode == 3 or chanmode == 4 then
      return "mono"
    end

    -- Otherwise use source channels
    local src = reaper.GetMediaItemTake_Source(tk)
    local ch = src and (reaper.GetMediaSourceNumChannels(src) or 2) or 2
    return (ch >= 2) and "multi" or "mono"
  end

  for _, it in ipairs(items) do
    local tk_orig = r.GetActiveTake(it)
    local orig_name = ""
    if tk_orig then
      _, orig_name = r.GetSetMediaItemTakeInfo_String(tk_orig, "P_NAME", "", false)
    end
    -- snapshot original StartInSource (seconds) before we stretch window
    local orig_startoffs_sec = tk_orig and (r.GetMediaItemTakeInfo_Value(tk_orig, "D_STARTOFFS") or 0.0) or nil

    -- When TAKE FX are excluded, temporarily offline only those that were online.
    local snap_off = nil
    if tk_orig and (not need_take) then
      snap_off = snapshot_takefx_offline(tk_orig)
      local n_off = temp_offline_nonoffline_fx(tk_orig)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] temp-offline %d FX on '%s'", n_off, orig_name) end
    end

    -- >>>> Volume handling: snapshot, optional merge, optional reset <<<<
    local volume_snap = preprocess_item_volumes(it, cfg.RENDER_MERGE_VOLUMES, cfg.RENDER_PRINT_VOLUMES, cfg.RENDER_MERGE_TO_ITEM, DBG)

    local L0, R0 = item_span(it)
    local name0  = get_take_name(it) or ""
    local d      = per_member_window_lr(it, L0, R0, HANDLE, HANDLE)

    if DBG >= 2 then
      dbg(DBG,2,"[REN] item@%.3f..%.3f want=%.3f..%.3f -> got=%.3f..%.3f clampL=%s clampR=%s name=%s",
          L0, R0, d.wantL, d.wantR, d.gotL, d.gotR, tostring(d.clampL), tostring(d.clampR), name0)
    end

    local edge_ids = nil
    if cfg.WRITE_EDGE_CUES then
      -- Keep #in/#out (unit span) for downstream media-cue workflows.
      edge_ids = add_edge_cues(L0, R0, 0)
      dbg(DBG,1,"[EDGE-CUE] add #in @ %.3f  #out @ %.3f  ids=(%s,%s)", L0, R0, tostring(edge_ids and edge_ids[1]), tostring(edge_ids and edge_ids[2]))
    end


    -- move to render window and align take offset
    r.SetMediaItemInfo_Value(it, "D_POSITION", d.gotL)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   d.gotR - d.gotL)
    if d.tk then
      local deltaL  = (L0 - d.gotL)
      local new_off = d.offs - (deltaL * d.rate)
      r.SetMediaItemTakeInfo_Value(d.tk, "D_STARTOFFS", new_off)
    end

    -- If we are going to apply TRACK FX (01/11), or we are forcing multi without TRACK FX,
    -- clear fades (40361/41993 will bake them). Otherwise (00/10 => 40601) keep fades.
    local fade_snap = nil

    -- Per-item channel mode detection when RENDER_APPLY_MODE=="auto"
    local item_apply_mode = cfg.RENDER_APPLY_MODE
    if cfg.RENDER_APPLY_MODE == "auto" then
      item_apply_mode = get_item_apply_mode(it)
    end

    local force_multi = (not need_track)
                    and (item_apply_mode == "multi")
                    and (cfg.RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX == "force_multi")

    -- When channel_mode="mono", always use Apply (40361) to force mono output
    local force_mono = (item_apply_mode == "mono")

    local use_apply = (need_track == true) or (force_multi == true) or (force_mono == true)
    if use_apply then
      if force_multi then
        dbg(DBG,1,"[APPLY] force multi (no track FX path)")
      elseif force_mono then
        dbg(DBG,1,"[APPLY] force mono (channel_mode=mono)")
      end
      fade_snap = snapshot_fades(it)
      zero_fades(it)
    end

    -- Determine command for this specific item
    local cmd_apply = (item_apply_mode == "multi") and ACT_APPLY_MULTI or ACT_APPLY_MONO

    -- render
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(it, true)
    r.Main_OnCommand(use_apply and cmd_apply or ACT_RENDER_PRES, 0)

    -- remove temporary # markers (if any)
    if edge_ids then
      remove_markers_by_ids(edge_ids)
      dbg(DBG,1,"[EDGE-CUE] removed ids: %s, %s", tostring(edge_ids[1]), tostring(edge_ids[2]))
    end

    -- restore fades if we cleared them for 40361/41993
    if use_apply and fade_snap then
      restore_fades(it, fade_snap)
    end


    -- restore item window and offset
    local left_total = L0 - d.gotL
    if left_total < 0 then left_total = 0 end
    r.SetMediaItemInfo_Value(it, "D_POSITION", L0)
    r.SetMediaItemInfo_Value(it, "D_LENGTH",   R0 - L0)
    local newtk = r.GetActiveTake(it)  -- the freshly rendered take
    if newtk then r.SetMediaItemTakeInfo_Value(newtk, "D_STARTOFFS", left_total) end
    r.UpdateItemInProject(it)

    -- Volume handling after render: print or restore
    postprocess_item_volumes(it, volume_snap, newtk, tk_orig, cfg.RENDER_MERGE_VOLUMES, cfg.RENDER_PRINT_VOLUMES, cfg.RENDER_MERGE_TO_ITEM, DBG)

    -- Rename only the new rendered take
    rename_new_render_take(
      it,
      orig_name,
      cfg.RENDER_TAKE_FX == true,
      cfg.RENDER_TRACK_FX == true,
      DBG
    )

    -- Restore original take's offline snapshot first...
    if tk_orig and snap_off then
      restore_takefx_offline(tk_orig, snap_off)
    end
    -- ...then clone the original take FX chain to the NEW take when TAKE FX were excluded
    if newtk and tk_orig and (not need_take) then
      local ncl = clone_takefx_chain(tk_orig, newtk)
      if DBG >= 2 then dbg(DBG,2,"[TAKEFX] cloned %d FX from old→new on '%s'", ncl, orig_name) end
    end

    ----------------------------------------------------------------
    -- Always restore previous take's StartInSource (SIS),
    -- regardless of tc_mode ("previous" | "current" | "off").
    ----------------------------------------------------------------
    if tk_orig and orig_startoffs_sec ~= nil then
      r.SetMediaItemTakeInfo_Value(tk_orig, "D_STARTOFFS", orig_startoffs_sec)
    end

    -- === TimeReference embed (via Library) =========================
    -- ExtState: RENDER_TC_EMBED = "previous" | "current" | "off"
    do
      local mode = cfg.RENDER_TC_EMBED or "previous"
      if newtk and mode ~= "off" then
        local ok_write = false

        if mode == "previous" and tk_orig then
          -- Embed TR from previous (original) take, handle-aware and cross-SR safe
          local smp = E.TR_PrevToActive(tk_orig, newtk)
          local src = r.GetMediaItemTake_Source(newtk)
          local path = src and r.GetMediaSourceFileName(src, "") or ""
          if path ~= "" and path:lower():sub(-4) == ".wav" then
            ok_write = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
            if DBG >= 2 then dbg(DBG,2,"[RGWH-TR] mode=previous  write=%s  samples=%d  path=%s", tostring(ok_write), smp, path) end
          end

        elseif mode == "current" then
          -- Embed TR from current project position (item start → active)
          local smp = E.TR_FromItemStart(newtk, L0)
          local src = r.GetMediaItemTake_Source(newtk)
          local path = src and r.GetMediaSourceFileName(src, "") or ""
          if path ~= "" and path:lower():sub(-4) == ".wav" then
            ok_write = (select(1, E.TR_Write(E.CLI_Resolve(), path, smp)) == true)
            if DBG >= 2 then dbg(DBG,2,"[RGWH-TR] mode=current   write=%s  samples=%d  path=%s", tostring(ok_write), smp, path) end
          end
        end

        -- collect for batch refresh if TR was written
        if ok_write then
          collected_new_takes = collected_new_takes or {}
          collected_new_takes[#collected_new_takes+1] = newtk
        end
      end
    end
    -- ==============================================================
  end
  -- restore TRACK FX enabled states if we disabled them
  if not need_track then
    for _, rec in pairs(tr_map) do
      local tr = rec.track
      for fx, was_on in pairs(rec.enabled) do
        r.TrackFX_SetEnabled(tr, fx, was_on and true or false)
      end
    end
  end

  r.PreventUIRefresh(-1)
  r.UpdateArrange()

  -- refresh items that had TR written (batch)
  if collected_new_takes and #collected_new_takes > 0 then
    E.Refresh_Items(collected_new_takes)
  end

  r.Undo_EndBlock("RGWH Core - Render (Apply FX per item w/ handles)", -1)
end

------------------------------------------------------------
-- PUBLIC ENTRY (single callsite)
------------------------------------------------------------
function M.core(args)
  if type(args) ~= "table" then return false, "bad_args" end
  local op = tostring(args.op or "auto")  -- "render" | "glue" | "auto"

  -- Snapshot keys we may override (one-run)
  local prev = {
    HANDLE_MODE     = get_ext("HANDLE_MODE",     ""),
    HANDLE_SECONDS  = get_ext("HANDLE_SECONDS",  ""),
    EPSILON_MODE    = get_ext("EPSILON_MODE",    ""),
    EPSILON_VALUE   = get_ext("EPSILON_VALUE",   ""),
    WRITE_EDGE_CUES = get_ext("WRITE_EDGE_CUES", ""),
    WRITE_GLUE_CUES = get_ext("WRITE_GLUE_CUES", ""),
    DEBUG_LEVEL     = get_ext("DEBUG_LEVEL",     ""),
    DEBUG_NO_CLEAR  = get_ext("DEBUG_NO_CLEAR",  ""),

    GLUE_SINGLE_ITEMS  = get_ext("GLUE_SINGLE_ITEMS",  ""),
    GLUE_TAKE_FX       = get_ext("GLUE_TAKE_FX",       ""),
    GLUE_TRACK_FX      = get_ext("GLUE_TRACK_FX",      ""),
    GLUE_APPLY_MODE    = get_ext("GLUE_APPLY_MODE",    ""),
    GLUE_OUT_NO_TRFX   = get_ext("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX", ""),

    RENDER_TAKE_FX     = get_ext("RENDER_TAKE_FX",     ""),
    RENDER_TRACK_FX    = get_ext("RENDER_TRACK_FX",    ""),
    RENDER_APPLY_MODE  = get_ext("RENDER_APPLY_MODE",  ""),
    RENDER_OUT_NO_TRFX = get_ext("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", ""),
    RENDER_TC_EMBED    = get_ext("RENDER_TC_EMBED",    ""),
  }
  local function set_opt(k, v) if v ~= nil then set_ext(k, v) end end

  -- One-run overrides ------------------------------------------------
  -- handle / epsilon
  if args.handle and args.handle ~= "ext" then
    set_opt("HANDLE_MODE",    args.handle.mode or DEFAULTS.HANDLE_MODE)
    set_opt("HANDLE_SECONDS", tostring(args.handle.seconds or DEFAULTS.HANDLE_SECONDS))
  end
  if args.epsilon and args.epsilon ~= "ext" then
    set_opt("EPSILON_MODE",   args.epsilon.mode or DEFAULTS.EPSILON_MODE)
    set_opt("EPSILON_VALUE",  tostring(args.epsilon.value or DEFAULTS.EPSILON_VALUE))
  end

  -- cues
  if args.cues then
    if args.cues.write_edge ~= nil then set_opt("WRITE_EDGE_CUES", args.cues.write_edge and "1" or "0") end
    if args.cues.write_glue ~= nil then set_opt("WRITE_GLUE_CUES", args.cues.write_glue and "1" or "0") end
  end

  -- debug
  if args.debug then
    if args.debug.level ~= nil then set_opt("DEBUG_LEVEL", tostring(args.debug.level)) end
    if args.debug.no_clear ~= nil then set_opt("DEBUG_NO_CLEAR", args.debug.no_clear and "1" or "0") end
  end

  -- channel mode (maps to GLUE/RENDER_APPLY_MODE)
  local ch = args.channel_mode
  if ch == "auto" or ch == "mono" or ch == "multi" then
    set_opt("GLUE_APPLY_MODE",   ch)
    set_opt("RENDER_APPLY_MODE", ch)
  end

  -- toggles (apply to BOTH render & glue; TS-Window needs GLUE_* too)
  if args.take_fx  ~= nil then
    set_opt("RENDER_TAKE_FX", args.take_fx and "1" or "0")
    set_opt("GLUE_TAKE_FX",   args.take_fx and "1" or "0")
  end
  if args.track_fx ~= nil then
    set_opt("RENDER_TRACK_FX", args.track_fx and "1" or "0")
    set_opt("GLUE_TRACK_FX",   args.track_fx and "1" or "0")
  end
  if args.tc_mode  ~= nil then
    set_opt("RENDER_TC_EMBED", tostring(args.tc_mode))
  end

  -- policies
  if args.policies then
    if args.policies.glue_single_items ~= nil then
      set_opt("GLUE_SINGLE_ITEMS", args.policies.glue_single_items and "1" or "0")
    end
    if args.policies.glue_no_trackfx_output_policy then
      set_opt("GLUE_OUTPUT_POLICY_WHEN_NO_TRACKFX", args.policies.glue_no_trackfx_output_policy)
    end
    if args.policies.render_no_trackfx_output_policy then
      set_opt("RENDER_OUTPUT_POLICY_WHEN_NO_TRACKFX", args.policies.render_no_trackfx_output_policy)
    end
  end

  -- Run --------------------------------------------------------------
  local ok, err
  if op == "render" then
    -- Extract volume control params from args (defaults: merge=true, print=true, merge_to_item=false)
    local merge_vols = (args.merge_volumes == nil) and true or (args.merge_volumes == true)
    local print_vols = (args.print_volumes == nil) and true or (args.print_volumes == true)
    local merge_to_i = (args.merge_to_item == nil) and false or (args.merge_to_item == true)
    -- Pass volume params as positional args: (take_fx, track_fx, mode, tc_mode, merge_volumes, print_volumes, merge_to_item)
    ok, err = pcall(M.render_selection, nil, nil, nil, nil, merge_vols, print_vols, merge_to_i)

  elseif op == "auto" then
    -- NEW AUTO MODE: Render single-item units, Glue multi-item units
    local merge_vols = (args.merge_volumes == nil) and true or (args.merge_volumes == true)
    local print_vols = (args.print_volumes == nil) and true or (args.print_volumes == true)
    local merge_to_i = (args.merge_to_item == nil) and false or (args.merge_to_item == true)
    ok, err = pcall(M.auto_selection, merge_vols, print_vols, merge_to_i)

  elseif op == "glue" then
    local cfg = M.read_settings()

    if op == "glue" then
      local scope = tostring(args.selection_scope or "auto")  -- "auto"|"units"|"ts"|"item"
      if scope == "units" then
        ok, err = pcall(M.glue_selection, true)  -- force_units=true

      elseif scope == "ts" then
        local tsL, tsR, hasTS = get_current_ts()
        if not hasTS then ok, err = false, "no_time_selection" else
          local by_tr, tracks = collect_items_intersect_ts_by_track(tsL, tsR)
          r.Undo_BeginBlock(); r.PreventUIRefresh(1)
          if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end
          for _, tr in ipairs(tracks) do
            glue_by_ts_window_on_track(tr, tsL, tsR, cfg, by_tr[tr])
          end
          r.PreventUIRefresh(-1); r.UpdateArrange(); r.Undo_EndBlock("RGWH Core - Glue TS", -1)
          ok, err = true, nil
        end

      elseif scope == "item" then
        ok, err = pcall(M.glue_selection)

      else -- "auto"
        local which, tsL, tsR = glue_auto_scope(cfg, "auto")
        if which == "units" then
          ok, err = pcall(M.glue_selection)
        else
          local by_tr, tracks = collect_items_intersect_ts_by_track(tsL, tsR)
          r.Undo_BeginBlock(); r.PreventUIRefresh(1)
          if not cfg.DEBUG_NO_CLEAR then r.ClearConsole() end
          for _, tr in ipairs(tracks) do
            glue_by_ts_window_on_track(tr, tsL, tsR, cfg, by_tr[tr])
          end
          r.PreventUIRefresh(-1); r.UpdateArrange(); r.Undo_EndBlock("RGWH Core - Glue TS(auto)", -1)
          ok, err = true, nil
        end
      end
    end
  else
    ok, err = false, "unsupported_op"
  end

  -- restore snapshot
  for k, v in pairs(prev) do set_opt(k, v) end
  if not ok then return false, tostring(err) end
  return true
end

return M
