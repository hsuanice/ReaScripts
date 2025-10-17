--[[
@description AudioSweet Template (hsuanice) — Focused/Chain × Apply/Copy
@version 251017_1700
@author hsuanice
@about
  Minimal, clean template for AudioSweet-style scripts:
  - Track FX only (Take FX → warn & abort)
  - Modes:
      AS_MODE   = focused | chain    (ExtState: hsuanice_AS/AS_MODE)
      AS_ACTION = apply   | copy     (ExtState: hsuanice_AS/AS_ACTION)
  - Copy mode: non-destructive, appends focused FX (or full chain) to selected items' take FX.
  - Apply mode: stubs provided — hook your engine (RGWH Core or native 40361/41993) here.

Usage (example wrappers set before running this script):
  reaper.SetExtState("hsuanice_AS","AS_MODE","focused",false)
  reaper.SetExtState("hsuanice_AS","AS_ACTION","copy",false)

@changelog
  v251017_1700
    • Initial release of AudioSweet Template.
      - Clean base structure for AudioSweet-style scripts (no SWS dependency).
      - Supports Track FX only; warns and aborts for Take FX.
      - Two control axes via ExtState:
          AS_MODE   = focused | chain
          AS_ACTION = apply   | copy
      - Provides Apply stubs (for RGWH Core or native 40361/41993) and non-destructive Copy.

  v251017_1730
    • UX improvement: replaced post-operation summary dialog with a pre-copy confirmation dialog.
      - Shows FX name and selected items list before performing copy.
      - Cancel aborts the process safely (Undo block closed cleanly).
      - Removed “Item units / Operations / Scope / Position” lines from dialog (moved to console log).

  v251017_1810
    • Added item list builder with track name, time range, and active take name.
      - Supports up to 20 lines with “...and N more” overflow message.
    • Updated copy_* helpers to return both (ops, units) for debug and statistics.
    • Improved console logging format: consistent [AS][STEP] prefix and extended info.
  ]]--

----------------------------------------------------------------
-- Debug toggle via ExtState: hsuanice_AS / DEBUG = "1" to enable
----------------------------------------------------------------
local function debug_enabled()
  return reaper.GetExtState("hsuanice_AS","DEBUG") == "1"
end

local function log_step(tag, fmt, ...)
  if not debug_enabled() then return end
  local msg = fmt and string.format(fmt, ...) or ""
  reaper.ShowConsoleMsg(string.format("[AS][STEP] %s %s\n", tostring(tag or ""), msg))
end

---------------------------------------------------------
-- Summary dialog toggle (ExtState: hsuanice_AS/AS_SHOW_SUMMARY)
--   "0" → do NOT show summary dialog
--   others/empty (default) → show
---------------------------------------------------------
local function show_summary_enabled()
  return reaper.GetExtState("hsuanice_AS","AS_SHOW_SUMMARY") ~= "0"
end

---------------------------------------------------------
-- Args: merge from ExtState (with sensible defaults)
---------------------------------------------------------
local function AS_merge_args_with_extstate(args)
  args = args or {}
  local function get_ns(ns, key, def)
    local v = reaper.GetExtState(ns, key)
    if v == "" then return def else return v end
  end
  args.mode        = args.mode        or get_ns("hsuanice_AS","AS_MODE","focused")     -- focused | chain
  args.action      = args.action      or get_ns("hsuanice_AS","AS_ACTION","copy")      -- apply   | copy
  args.scope       = args.scope       or get_ns("hsuanice_AS","AS_COPY_SCOPE","active") -- active  | all_takes
  args.append_pos  = args.append_pos  or get_ns("hsuanice_AS","AS_COPY_POS","tail")     -- tail    | head
  args.warn_takefx = (args.warn_takefx ~= false)  -- default true
  return args
end

---------------------------------------------------------
-- Selection snapshot / restore
---------------------------------------------------------
local function project_epsilon()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end

local function snapshot_selection()
  local list = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i = 0, n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local tr = reaper.GetMediaItem_Track(it)
      local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      list[#list+1] = { tr=tr, L=p, R=p+l }
    end
  end
  return list
end

local function restore_selection(snap)
  if not snap then return end
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  local eps = project_epsilon()
  for _, rec in ipairs(snap) do
    local tr = rec.tr
    if tr then
      local n = reaper.CountTrackMediaItems(tr)
      for j = 0, n-1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if it then
          local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local q = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          if p <= rec.L + eps and q >= rec.R - eps then
            reaper.SetMediaItemSelected(it, true); break
          end
        end
      end
    end
  end
end
---------------------------------------------------------
-- Build a human-readable list of selected items
-- Uses the selection snapshot to stay stable during the run
---------------------------------------------------------
local function build_selected_items_list(snap, max_lines)
  max_lines = max_lines or 20
  if type(snap) ~= "table" or #snap == 0 then return "(no items selected)" end
  local eps = project_epsilon()
  local lines, shown = {}, 0

  for i, rec in ipairs(snap) do
    if shown >= max_lines then break end
    local tr = rec.tr
    local track_name = ""
    if tr then
      local _, tn = reaper.GetTrackName(tr, "")
      track_name = tn or ""
    end

    -- try to find the actual media item back and get its active take name
    local take_name = ""
    if tr then
      local n = reaper.CountTrackMediaItems(tr)
      for j = 0, n - 1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if it then
          local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local q = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          if p <= rec.L + eps and q >= rec.R - eps then
            local tk = reaper.GetActiveTake(it)
            if tk then
              local _, nm = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
              take_name = nm or ""
            end
            break
          end
        end
      end
    end

    local track_num = tr and (reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or 0
    lines[#lines + 1] = string.format(
      "%02d) #%d %s | %s - %s%s",
      i,
      track_num,
      track_name,
      reaper.format_timestr(rec.L, ""),
      reaper.format_timestr(rec.R, ""),
      (take_name ~= "" and (" | Take: " .. take_name) or "")
    )
    shown = shown + 1
  end

  if #snap > max_lines then
    lines[#lines + 1] = string.format("... and %d more", #snap - max_lines)
  end

  return table.concat(lines, "\n")
end
---------------------------------------------------------
-- Focused Track FX resolver (Track FX only)
---------------------------------------------------------
local function normalize_focused_fx_index(idx)
  -- Strip container (0x2000000) and input/floating (0x1000000) flags
  if idx >= 0x2000000 then idx = idx - 0x2000000 end
  if idx >= 0x1000000 then idx = idx - 0x1000000 end
  return idx
end

local function get_focused_track_fx_or_warn(args)
  local retval, trackOut, itemOut, fxOut = reaper.GetFocusedFX()
  log_step("FOCUS", "retval=%s trackOut=%s itemOut=%s fxOut=%s", retval, trackOut, itemOut, fxOut)

  if retval ~= 1 then
    if retval == 2 and args.warn_takefx then
      reaper.MB("Focused FX is a TAKE FX.\nThis script supports Track FX only.", "AudioSweet Template", 0)
    else
      reaper.MB("No focused Track FX found.\nOpen FX window and focus a Track FX.", "AudioSweet Template", 0)
    end
    return false
  end

  local tr = reaper.GetTrack(0, math.max(0, (trackOut or 1)-1))
  if not tr then
    reaper.MB("Cannot resolve source track from focused FX.", "AudioSweet Template", 0)
    return false
  end
  local fx_index = normalize_focused_fx_index(fxOut or 0)
  local _, raw = reaper.TrackFX_GetFXName(tr, fx_index, "")
  return true, tr, fx_index, raw or ""
end

---------------------------------------------------------
-- COPY helpers (non-destructive)
---------------------------------------------------------
local function for_each_dest_take(item, scope, fn)
  if scope == "all_takes" then
    local tc = reaper.CountTakes(item) or 0
    for t = 0, tc-1 do
      local tk = reaper.GetMediaItemTake(item, t)
      if tk then fn(tk) end
    end
  else
    local tk = reaper.GetActiveTake(item)
    if tk then fn(tk) end
  end
end

local function copy_focused_fx_to_selected_items(src_track, fx_index, args)
  -- ops: number of takes affected
  -- units: number of items that received at least one operation
  local selN, ops, units = reaper.CountSelectedMediaItems(0), 0, 0
  for i = 0, selN-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local before = ops
      for_each_dest_take(it, args.scope, function(tk)
        local dest = (args.append_pos == "head") and 0 or (reaper.TakeFX_GetCount(tk) or 0)
        reaper.TrackFX_CopyToTake(src_track, fx_index, tk, dest, false)
        ops = ops + 1
      end)
      if ops > before then units = units + 1 end
    end
  end
  return ops, units
end

local function copy_chain_to_selected_items(src_track, args)
  -- ops: number of takes affected
  -- units: number of items that received at least one operation
  local chainN = reaper.TrackFX_GetCount(src_track) or 0
  local selN, ops, units = reaper.CountSelectedMediaItems(0), 0, 0
  for i = 0, selN-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local before = ops
      for_each_dest_take(it, args.scope, function(tk)
        if args.append_pos == "head" then
          for fx = chainN-1, 0, -1 do
            reaper.TrackFX_CopyToTake(src_track, fx, tk, 0, false); ops = ops + 1
          end
        else
          for fx = 0, chainN-1 do
            local dest = reaper.TakeFX_GetCount(tk) or 0
            reaper.TrackFX_CopyToTake(src_track, fx, tk, dest, false); ops = ops + 1
          end
        end
      end)
      if ops > before then units = units + 1 end
    end
  end
  return ops, units
end

---------------------------------------------------------
-- APPLY stubs (hook your engine here)
-- - Focused: apply only the focused FX
-- - Chain:   apply the whole Track FX chain
---------------------------------------------------------
local function apply_focused_stub(src_track, fx_index, focused_fx_name)
  -- ⬇️ 這裡接你要的引擎（例如 RGWH Core 或 40361/41993）
  -- 目前先示意：只顯示訊息，不做任何變更。
  reaper.MB(("Apply Focused FX (stub)\n\nFX: %s"):format(focused_fx_name or "(unknown)"),
            "AudioSweet Template — APPLY", 0)
end

local function apply_chain_stub(src_track, focused_fx_name)
  reaper.MB(("Apply FULL CHAIN (stub)\n\nFocused FX for reference: %s")
              :format(focused_fx_name or "(unknown)"),
            "AudioSweet Template — APPLY", 0)
end

---------------------------------------------------------
-- MAIN
---------------------------------------------------------
local function main()
  local args = AS_merge_args_with_extstate({})

  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)

  local sel_snap = snapshot_selection()

  local ok, src_track, fx_index, raw_name = get_focused_track_fx_or_warn(args)
  if not ok then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet Template (no focused Track FX)", -1)
    return
  end
  log_step("FOCUSED", "fx_index=%d raw='%s'", fx_index, raw_name or "")

-- Early branch: COPY (non-destructive)
if args.action == "copy" then
  -- Build confirmation dialog body
  local what = (args.mode == "focused") and "Focused FX" or "FX Chain"
  local item_list = build_selected_items_list(sel_snap, 20)
  local confirm_body = (
    "Copy\n\n" ..
    string.format("FX: %s\n\n", raw_name or "(unknown)") ..
    "to\n" ..
    "Items:\n" .. item_list
  )

  -- OK/Cancel dialog (type=1 -> MB_OKCANCEL)
  local resp = reaper.MB(confirm_body, "AudioSweet — Confirm Copy", 1)
  if resp ~= 1 then
    -- Cancel pressed: abort gracefully
    log_step("COPY", "cancelled by user (mode=%s)", tostring(args.mode))
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet Template: Copy (cancelled)", -1)
    return
  end

  -- Proceed with copy
  -- ops: takes affected; units: items affected (items that received at least one op)
  local ops, units = (args.mode == "focused")
    and copy_focused_fx_to_selected_items(src_track, fx_index, args)
    or  copy_chain_to_selected_items(src_track, args)

  -- Console summary (dialog no longer shows ops/scope/pos)
  log_step("COPY", "mode=%s scope=%s pos=%s ops=%s units=%s",
           tostring(args.mode), tostring(args.scope), tostring(args.append_pos),
           tostring(ops or 0), tostring(units or 0))

  reaper.UpdateArrange()
  restore_selection(sel_snap)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(string.format("AudioSweet Template: Copy %s (%d op)",
                        (args.mode=="focused" and "focused FX" or "FX chain"),
                        tonumber(ops) or 0), 0)
  return
end

  -- APPLY flow (stub)
  if args.mode == "focused" then
    apply_focused_stub(src_track, fx_index, raw_name)
  else
    apply_chain_stub(src_track, raw_name)
  end

  restore_selection(sel_snap)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("AudioSweet Template: Apply (stub)", 0)
end

main()