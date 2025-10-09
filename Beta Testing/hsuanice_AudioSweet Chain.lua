--[[
@description AudioSweet Chain (hsuanice) — Print full Track FX chain via RGWH Core-style flow (selected items); alias-ready naming; TS-window aware
@version 2510090051 — Initial Chain print (auto/sticky/name target), FIFO naming, TS-window path
@author Hsuanice
@notes
  What this does
  • Prints the **entire Track FX chain** of a chosen track onto the selected item(s).
  • Keeps the track FX states intact (no bypass flipping per-FX; we render the full chain).
  • Time Selection aware:
      - If TS intersects ≥2 “units” → Pro Tools-like TS-Window glue (42432) per track, then apply track FX.
      - Else (no TS, or TS == unit) → one-shot “Core-style” glue with handles then apply track FX.
  • Naming: reuses the concise “AS” scheme:
      BaseName-AS{n}-{FX1}_{FX2}_...
    For Chain prints, the token appended each pass is `FXChain` (configurable).
    Respects your AS_MAX_FX_TOKENS FIFO cap (drop oldest tokens when exceeding the cap).
  • Target track resolution (user options below):
      1) auto   : Focused FX track if any; otherwise the first track named “AudioSweet”.
      2) sticky : Always use the track GUID saved in ExtState (cross-project). If missing, falls back to auto.
      3) name   : Always use the first track whose name equals CHAIN_TARGET_NAME.
  • Sticky utilities:
      - If SET_STICKY_ON_RUN=true and exactly one track is selected, we store its GUID to ExtState and proceed.

  Dependencies
  • REAPER 6+.
  • No JSON required (we don’t need alias lookup to render full chain).
  • Uses native actions: 42432, 40361, 41993, 40441.

  Limitations
  • Take FX are ignored (we render **Track FX chain** only).
  • Mixed and multichannel edge-cases follow the same auto-channel logic as AudioSweet: mono → 40361; ≥2ch → 41993 with a temporary I_NCHAN.

@changelog
  v251009_0051
    - New: “AudioSweet Chain” script that renders the full track FX chain onto selected item(s).
    - New: Target track resolution modes:
        • auto   → Focused FX track; else track named “AudioSweet”.
        • sticky → Track GUID stored in ExtState; cross-project persistent.
        • name   → First track matching CHAIN_TARGET_NAME.
    - New: Optional one-click sticky set — if SET_STICKY_ON_RUN=true and one track is selected, store its GUID then run.
    - New: TS-Window behavior:
        • If Time Selection intersects ≥2 units, glue within TS (42432) per-track group, then apply full chain.
        • Else (no TS or TS==unit), run a Core-like one-shot (glue-with-handles style) then apply full chain.
    - New: Naming uses concise AS scheme and appends “FXChain” to record pass order; respects FIFO cap (AS_MAX_FX_TOKENS).
    - Logging: DEBUG toggle via ExtState “hsuanice_AS_CHAIN/DEBUG”; clear step tags for root cause analysis.
]]--

-- ==========================
-- User options
-- ==========================
-- How many FX names to keep in the “-ASn-...” suffix (FIFO).
-- 0 or nil = unlimited; N>0 = keep last N tokens (drop oldest first).
local AS_MAX_FX_TOKENS = 3

-- The token to append each time you print the full chain.
-- Keep it short, alphanumeric if you want strict compactness.
local CHAIN_TOKEN_LABEL = "FXChain"

-- Target-track selection mode: "auto" | "sticky" | "name"
--   auto   : prefer focused FX's track if any; else first track named CHAIN_TARGET_NAME
--   sticky : always use GUID stored in ExtState; if missing → fallback to auto
--   name   : always use the first track whose name equals CHAIN_TARGET_NAME
local CHAIN_TARGET_MODE = "auto"

-- The name to search for when CHAIN_TARGET_MODE == "name", and for auto fallback.
local CHAIN_TARGET_NAME = "AudioSweet"

-- If true AND exactly one track is selected, store its GUID to Sticky and proceed.
local SET_STICKY_ON_RUN = false

-- Naming-only debug (console print before/after renaming).
local AS_DEBUG_NAMING = true

-- Global debug toggle (step logs). Set ExtState key "hsuanice_AS_CHAIN/DEBUG" to "1"
local function debug_enabled()
  return reaper.GetExtState("hsuanice_AS_CHAIN", "DEBUG") == "1"
end
local function log_step(tag, fmt, ...)
  if not debug_enabled() then return end
  local msg = fmt and string.format(fmt, ...) or ""
  reaper.ShowConsoleMsg(string.format("[AS-CHAIN][STEP] %s %s\n", tostring(tag or ""), msg))
end
local function dbg(msg)
  if not debug_enabled() then return end
  reaper.ShowConsoleMsg(tostring(msg) .. "\n")
end

-- ==========================
-- Small helpers: epsilon + ranges
-- ==========================
local function project_epsilon()
  local sr = reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  return (sr and sr > 0) and (1.0 / sr) or 1e-6
end
local function approx_eq(a, b, eps) eps = eps or project_epsilon(); return math.abs(a-b) <= eps end
local function ranges_touch_or_overlap(a0, a1, b0, b1, eps)
  eps = eps or project_epsilon()
  return not (a1 < b0 - eps or b1 < a0 - eps)
end

-- ==========================
-- Selection snapshot / restore
-- ==========================
local function snapshot_selection()
  local out = {}
  local n = reaper.CountSelectedMediaItems(0)
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local tr = reaper.GetMediaItem_Track(it)
      local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      out[#out+1] = { tr=tr, L=p, R=p+l }
    end
  end
  return out
end
local function restore_selection(snap)
  if not snap then return end
  reaper.Main_OnCommand(40289, 0) -- Unselect all
  local eps = project_epsilon()
  for _,rec in ipairs(snap) do
    local tr = rec.tr
    if tr then
      local n = reaper.CountTrackMediaItems(tr)
      for j=0,n-1 do
        local it = reaper.GetTrackMediaItem(tr, j)
        if it then
          local p = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
          local q = p + reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
          if p <= rec.L + eps and q >= rec.R - eps then
            reaper.SetMediaItemSelected(it, true)
            break
          end
        end
      end
    end
  end
end

-- ==========================
-- Unit builder (by track, touching/overlap merged)
-- ==========================
local function build_units_from_selection()
  local n = reaper.CountSelectedMediaItems(0)
  local by_tr = {}
  for i=0,n-1 do
    local it = reaper.GetSelectedMediaItem(0, i)
    if it then
      local tr = reaper.GetMediaItem_Track(it)
      local p  = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
      local l  = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
      local q  = p + l
      by_tr[tr] = by_tr[tr] or {}
      table.insert(by_tr[tr], {item=it, p=p, q=q})
    end
  end
  local units = {}
  local eps = project_epsilon()
  for tr, arr in pairs(by_tr) do
    table.sort(arr, function(a,b) return a.p < b.p end)
    local cur = nil
    for _,e in ipairs(arr) do
      if not cur then
        cur = { track=tr, items={e.item}, UL=e.p, UR=e.q }
      else
        if ranges_touch_or_overlap(cur.UL, cur.UR, e.p, e.q, eps) then
          table.insert(cur.items, e.item)
          if e.p < cur.UL then cur.UL = e.p end
          if e.q > cur.UR then cur.UR = e.q end
        else
          units[#units+1] = cur
          cur = { track=tr, items={e.item}, UL=e.p, UR=e.q }
        end
      end
    end
    if cur then units[#units+1] = cur end
  end
  log_step("UNITS", "count=%d", #units)
  if debug_enabled() then
    for i,u in ipairs(units) do
      reaper.ShowConsoleMsg(string.format("  unit#%d track=%s members=%d span=%.3f..%.3f\n",
        i, tostring(u.track), #u.items, u.UL, u.UR))
    end
  end
  return units
end

local function collect_units_intersecting_ts(units, L, R)
  local out = {}
  for _,u in ipairs(units) do
    if ranges_touch_or_overlap(u.UL, u.UR, L, R, project_epsilon()) then
      out[#out+1] = u
    end
  end
  log_step("TS-INTERSECT", "TS=[%.3f..%.3f] hit_units=%d", L, R, #out)
  return out
end
local function ts_equals_unit(u, L, R) return approx_eq(u.UL, L) and approx_eq(u.UR, R) end

-- ==========================
-- Item/channel helpers
-- ==========================
local function get_item_channels(it)
  if not it then return 2 end
  local tk = reaper.GetActiveTake(it)
  if not tk then return 2 end
  local src = reaper.GetMediaItemTake_Source(tk)
  if not src then return 2 end
  return reaper.GetMediaSourceNumChannels(src) or 2
end
local function unit_max_channels(u)
  local maxch = 1
  for _,it in ipairs(u.items) do
    local ch = get_item_channels(it)
    if ch > maxch then maxch = ch end
  end
  return maxch
end
local function select_only_items(items)
  reaper.Main_OnCommand(40289, 0)
  for _,it in ipairs(items) do
    if it and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, it, "MediaItem*")) then
      reaper.SetMediaItemSelected(it, true)
    end
  end
end
local function move_items_to_track(items, tr)
  for _,it in ipairs(items) do
    if it and (reaper.ValidatePtr2 == nil or reaper.ValidatePtr2(0, it, "MediaItem*")) then
      reaper.MoveMediaItemToTrack(it, tr)
    end
  end
end

-- ==========================
-- Naming helpers (AS scheme)
-- ==========================
local function debug_naming_enabled() return AS_DEBUG_NAMING == true end
local function strip_extension(s) return (s or ""):gsub("%.[A-Za-z0-9]+$", "") end
local function strip_glue_render_and_trailing_label(name)
  local s = name or ""
  s = s:gsub("[_%-%s]*glue[dD]?[%s_%-%d]*", "")
       :gsub("[_%-%s]*render[eE]?[dD]?[%s_%-%d]*", "")
       :gsub("%s+%-[%s%-].*$", "")
       :gsub("%s+$","")
       :gsub("[_%-%s]+$","")
  return s
end
local function is_noise_token(tok)
  local t = tostring(tok or ""):lower()
  if t == "" then return true end
  if t == "glue" or t == "glued" or t == "render" or t == "rendered" then return true end
  if t:match("^ed%d*$")  then return true end
  if t:match("^dup%d*$") then return true end
  return false
end
local function parse_as_tag(full)
  local s = tostring(full or "")
  local base, n, tail = s:match("^(.-)[-_]AS(%d+)[-_](.+)$")
  if not base or not n then return nil, nil, nil end
  base = base:gsub("%s+$","")
  local first_tail = tail:match("^(.-)[-_]AS%d+[-_].*$") or tail
  local cleaned = first_tail
  cleaned = cleaned
              :gsub("[_%-%s]*glue[dD]?[%s_%-%d]*", "")
              :gsub("[_%-%s]*render[eE]?[dD]?[%s_%-%d]*", "")
              :gsub("ed%d+", "")
              :gsub("dup%d+", "")
              :gsub("%s+%-[%s%-].*$", "")
              :gsub("^[_%-%s]+","")
              :gsub("[_%-%s]+$","")
  local fx_tokens = {}
  for tok in cleaned:gmatch("([%w]+)") do
    if tok ~= "" and not tok:match("^AS%d+$") and not is_noise_token(tok) then
      fx_tokens[#fx_tokens+1] = tok
    end
  end
  return base, tonumber(n), fx_tokens
end
local function max_fx_tokens()
  local n = tonumber(AS_MAX_FX_TOKENS)
  if not n or n < 1 then return math.huge end
  return math.floor(n)
end
local function append_fx_to_take_name(item, token)
  if not item or not token or token == "" then return end
  local take = reaper.GetActiveTake(item)
  if not take then return end
  local _, tn0 = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local tn_noext = strip_extension(tn0 or "")
  if debug_naming_enabled() then
    reaper.ShowConsoleMsg(("[AS-CHAIN][NAME] before='%s'\n"):format(tn0 or ""))
  end

  local baseAS, nAS, fx_tokens = parse_as_tag(tn_noext)
  local base, n, tokens
  if baseAS and nAS then
    base   = strip_glue_render_and_trailing_label(baseAS)
    n      = nAS + 1
    tokens = fx_tokens or {}
  else
    base   = strip_glue_render_and_trailing_label(tn_noext)
    n      = 1
    tokens = {}
  end

  tokens[#tokens+1] = token

  local cap = max_fx_tokens()
  if cap ~= math.huge and #tokens > cap then
    local start = #tokens - cap + 1
    local trimmed = {}
    for i=start,#tokens do trimmed[#trimmed+1] = tokens[i] end
    tokens = trimmed
  end

  local new_name = string.format("%s-AS%d-%s", base, n, table.concat(tokens, "_"))
  if debug_naming_enabled() then
    reaper.ShowConsoleMsg(("[AS-CHAIN][NAME] after ='%s'\n"):format(new_name))
  end
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
end

-- ==========================
-- TS and loop state
-- ==========================
local function get_time_sel()
  local isSet, isLoop = false, false
  local L, R = reaper.GetSet_LoopTimeRange(isSet, isLoop, 0, 0, false)
  if (L == 0 and R == 0) then return false, 0, 0 end
  return true, L, R
end

-- ==========================
-- Target track resolution (auto / sticky / name)
-- ==========================
local ES_NS = "hsuanice_AS_CHAIN"
local ES_KEY_STICKY = "STICKY_GUID"

local function track_guid_string(tr)
  if not tr then return nil end
  local _, g = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
  return g ~= "" and g or nil
end
local function track_from_guid_string(guid_str)
  if not guid_str or guid_str == "" then return nil end
  local n = reaper.CountTracks(0)
  for i=0,n-1 do
    local tr = reaper.GetTrack(0, i)
    local _, g = reaper.GetSetMediaTrackInfo_String(tr, "GUID", "", false)
    if g == guid_str then return tr end
  end
  return nil
end
local function store_sticky_from_selected_if_requested()
  if not SET_STICKY_ON_RUN then return end
  local n = reaper.CountSelectedTracks(0)
  if n == 1 then
    local tr = reaper.GetSelectedTrack(0, 0)
    local g  = track_guid_string(tr)
    if g then
      reaper.SetExtState(ES_NS, ES_KEY_STICKY, g, true) -- persist
      log_step("STICKY", "Stored GUID=%s", g)
    end
  end
end
local function find_track_by_name_exact(name)
  local n = reaper.CountTracks(0)
  for i=0,n-1 do
    local tr = reaper.GetTrack(0, i)
    local _, tn = reaper.GetTrackName(tr)
    if (tn or "") == name then return tr end
  end
  return nil
end
local function focused_fx_track()
  local retval, trOut, itemOut, fxOut = reaper.GetFocusedFX()
  if retval == 1 and trOut ~= nil and trOut > 0 then
    local tr = reaper.GetTrack(0, trOut - 1)
    if tr then return tr end
  end
  return nil
end
local function resolve_target_track()
  if CHAIN_TARGET_MODE == "sticky" then
    local g = reaper.GetExtState(ES_NS, ES_KEY_STICKY)
    if g and g ~= "" then
      local tr = track_from_guid_string(g)
      if tr then
        log_step("TARGET", "sticky GUID hit")
        return tr
      else
        log_step("TARGET", "sticky GUID missing in project; fallback to auto")
        -- fall through to auto
      end
    else
      log_step("TARGET", "sticky empty; fallback to auto")
      -- fall through to auto
    end
  end

  if CHAIN_TARGET_MODE == "name" then
    local tr = find_track_by_name_exact(CHAIN_TARGET_NAME)
    if tr then
      log_step("TARGET", "name='%s' hit", CHAIN_TARGET_NAME)
      return tr
    else
      log_step("TARGET", "name='%s' not found; fallback to auto", CHAIN_TARGET_NAME)
      -- fall through to auto
    end
  end

  -- auto
  do
    local tr = focused_fx_track()
    if tr then
      log_step("TARGET", "auto: focused-FX track")
      return tr
    end
    tr = find_track_by_name_exact(CHAIN_TARGET_NAME)
    if tr then
      log_step("TARGET", "auto: by name='%s'", CHAIN_TARGET_NAME)
      return tr
    end
  end

  return nil
end

-- ==========================
-- Apply full chain to a single item
-- ==========================
local function apply_full_chain_to_item_on_track(item, FXtrack)
  if not item or not FXtrack then return false end

  -- Move item to FX track
  local origTR = reaper.GetMediaItem_Track(item)
  reaper.MoveMediaItemToTrack(item, FXtrack)

  -- Decide mono vs multi by source channels, adjust I_NCHAN for multi
  local ch = get_item_channels(item)
  local prev_nchan = tonumber(reaper.GetMediaTrackInfo_Value(FXtrack, "I_NCHAN")) or 2
  local cmd = 41993
  local changed = false
  if ch <= 1 then
    cmd = 40361
  else
    local desired = (ch % 2 == 0) and ch or (ch + 1)
    if prev_nchan ~= desired then
      reaper.SetMediaTrackInfo_Value(FXtrack, "I_NCHAN", desired)
      changed = true
      log_step("APPLY", "I_NCHAN %d → %d", prev_nchan, desired)
    end
  end

  -- Apply
  reaper.Main_OnCommand(40289, 0)
  reaper.SetMediaItemSelected(item, true)
  reaper.Main_OnCommand(cmd, 0) -- Apply track FX to items (new take) / multichannel variant

  -- Restore I_NCHAN if changed
  if changed then
    reaper.SetMediaTrackInfo_Value(FXtrack, "I_NCHAN", prev_nchan)
    log_step("APPLY", "I_NCHAN restore → %d", prev_nchan)
  end

  -- Pick output (newly processed item should be selected)
  local out = reaper.GetSelectedMediaItem(0, 0) or item

  -- Rename and move back
  append_fx_to_take_name(out, CHAIN_TOKEN_LABEL)
  reaper.MoveMediaItemToTrack(out, origTR)

  return true
end

-- ==========================
-- Main
-- ==========================
local function main()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
  if debug_enabled() then reaper.ShowConsoleMsg("\n=== AudioSweet Chain run ===\n") end

  -- Optional: store sticky if requested
  store_sticky_from_selected_if_requested()

  -- Resolve target track
  local FXtrack = resolve_target_track()
  if not FXtrack then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet Chain (no target track)", -1)
    reaper.MB(
      "No target track resolved.\n\n" ..
      "• sticky : set a sticky GUID or\n" ..
      "• name   : create/rename a track to \"" .. CHAIN_TARGET_NAME .. "\" or\n" ..
      "• auto   : focus a Track FX or keep a track named \"" .. CHAIN_TARGET_NAME .. "\".",
      "AudioSweet Chain", 0
    )
    return
  end

  -- Ensure we have selected items
  local units = build_units_from_selection()
  if #units == 0 then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("AudioSweet Chain (no items)", -1)
    reaper.MB("No media items selected.", "AudioSweet Chain", 0)
    return
  end

  -- Time selection state
  local hasTS, tsL, tsR = get_time_sel()
  log_step("PATH", "hasTS=%s TS=[%.3f..%.3f]", tostring(hasTS), tsL or -1, tsR or -1)

  local outputs = {}

  if hasTS then
    local hits = collect_units_intersecting_ts(units, tsL, tsR)
    if #hits >= 2 then
      -- =========================
      -- TS-Window (GLOBAL) path
      -- =========================
      log_step("TSW-GLOBAL", "begin (hits=%d)", #hits)
      -- Select all items of all hit units (on their original tracks)
      reaper.Main_OnCommand(40289, 0)
      for _,u in ipairs(hits) do
        for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      end
      log_step("TSW-GLOBAL", "pre-42432 selected=%d", reaper.CountSelectedMediaItems(0))
      reaper.Main_OnCommand(42432, 0) -- Glue items within time selection (no handles)
      log_step("TSW-GLOBAL", "post-42432 selected=%d", reaper.CountSelectedMediaItems(0))

      -- Snapshot glued results
      local glued = {}
      local n = reaper.CountSelectedMediaItems(0)
      for i=0,n-1 do glued[#glued+1] = reaper.GetSelectedMediaItem(0, i) end

      for idx, it in ipairs(glued) do
        local ok = apply_full_chain_to_item_on_track(it, FXtrack)
        if ok then
          log_step("TSW-GLOBAL", "applied chain to glued#%d", idx)
          outputs[#outputs+1] = reaper.GetSelectedMediaItem(0, 0) or it
        else
          log_step("TSW-GLOBAL", "apply failed on glued#%d", idx)
        end
      end

      reaper.PreventUIRefresh(-1)
      reaper.Undo_EndBlock("AudioSweet Chain — TS-Window (global)", 0)
      return
    end
    -- else: fall through to per-unit (TS==unit or only one unit hit)
  end

  -- =========================
  -- Per-unit path
  -- =========================
  for _,u in ipairs(units) do
    log_step("UNIT", "UL=%.3f UR=%.3f members=%d", u.UL, u.UR, #u.items)
    if hasTS and not ts_equals_unit(u, tsL, tsR) then
      -- --- TS-Window (UNIT) ---
      reaper.Main_OnCommand(40289, 0)
      for _,it in ipairs(u.items) do reaper.SetMediaItemSelected(it, true) end
      reaper.Main_OnCommand(42432, 0) -- Glue within TS
      local glued = reaper.GetSelectedMediaItem(0, 0)
      if glued then
        if apply_full_chain_to_item_on_track(glued, FXtrack) then
          outputs[#outputs+1] = reaper.GetSelectedMediaItem(0, 0) or glued
        end
      else
        log_step("TSW-UNIT", "no item after 42432")
      end
    else
      -- --- Core-like (handles) ---
      -- Move unit to FX track, apply, then move back
      move_items_to_track(u.items, FXtrack)

      -- Choose command by MAX channels across unit
      local ch = unit_max_channels(u)
      local prev_nchan = tonumber(reaper.GetMediaTrackInfo_Value(FXtrack, "I_NCHAN")) or 2
      local cmd = 41993
      local changed = false
      if ch <= 1 then
        cmd = 40361
      else
        local desired = (ch % 2 == 0) and ch or (ch + 1)
        if prev_nchan ~= desired then
          reaper.SetMediaTrackInfo_Value(FXtrack, "I_NCHAN", desired)
          changed = true
          log_step("CORE", "I_NCHAN %d → %d", prev_nchan, desired)
        end
      end

      select_only_items(u.items)
      reaper.Main_OnCommand(cmd, 0)

      if changed then
        reaper.SetMediaTrackInfo_Value(FXtrack, "I_NCHAN", prev_nchan)
        log_step("CORE", "I_NCHAN restore → %d", prev_nchan)
      end

      -- Pick processed (first selected), rename, move back
      local post = reaper.GetSelectedMediaItem(0, 0)
      if post then
        append_fx_to_take_name(post, CHAIN_TOKEN_LABEL)
        reaper.MoveMediaItemToTrack(post, u.track)
        outputs[#outputs+1] = post
      end

      -- Move any leftovers back (safety)
      move_items_to_track(u.items, u.track)
    end
  end

  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock("AudioSweet Chain — per-unit", 0)
end

-- ==========================
-- Run
-- ==========================
reaper.PreventUIRefresh(1)
main()
reaper.PreventUIRefresh(-1)