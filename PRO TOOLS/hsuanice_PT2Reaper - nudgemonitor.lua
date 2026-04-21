-- PT2Reaper_NudgeMonitor.lua
-- Nudge Monitor v0.2.0
-- Debug tool: capture before/after state snapshots around nudge actions
-- -----------------------------------------------------------------------

local ctx = reaper.ImGui_CreateContext('Nudge Monitor')
local FONT_MONO = reaper.ImGui_CreateFont('Courier New', 15)
reaper.ImGui_Attach(ctx, FONT_MONO)

local UI_FONT_SIZE   = 16  -- 125% of default 13px
local MONO_FONT_SIZE = 15  -- 125% of 12px

-- -----------------------------------------------------------------------
-- State
-- -----------------------------------------------------------------------

local snapBefore = nil
local snapAfter  = nil

local log = {}
local MAX_LOG = 30

-- Auto-capture state
local autoMode = false
local autoPrev = nil

-- Action definitions — cmdStr accepts integer IDs or _RS... named command strings
local ACTIONS = {
  { label = "Nudge Earlier",      cmdStr = "_RSd971c3362533d8b23c61ea3753f145eefd29c6f9" },
  { label = "Nudge Later",        cmdStr = "_RSbb8d6007fe1b69fa643329f3fa6144ba11a25fad" },
  { label = "Start Earlier",      cmdStr = "_RS702791878bed62a3ca17f65ab1cb5b8157e7d4e8" },
  { label = "Start Later",        cmdStr = "_RS698ea32fd380987874162a41044d8bce0d506ce9" },
  { label = "End Earlier",        cmdStr = "_RSed6fbcdc8d99f5aea804e2866cc109352f2056ac" },
  { label = "End Later",          cmdStr = "_RSc0037b826039e2d3102c52ab6002402942305f6d" },
}

-- Resolve _RS... named command or plain integer string → integer ID
local function resolveCmd(cmdStr)
  if cmdStr == "" then return 0 end
  local n = tonumber(cmdStr)
  if n then return math.floor(n) end
  return reaper.NamedCommandLookup(cmdStr)
end

-- Load persisted overrides from ExtState
local EXT_SEC = "NudgeMonitor"
for i, act in ipairs(ACTIONS) do
  local stored = reaper.GetExtState(EXT_SEC, "cmd_" .. i)
  if stored ~= "" then act.cmdStr = stored end
  local storedLabel = reaper.GetExtState(EXT_SEC, "label_" .. i)
  if storedLabel ~= "" then act.label = storedLabel end
  act.cmdBuf   = act.cmdStr
  act.labelBuf = act.label
end

-- -----------------------------------------------------------------------
-- Snapshot helpers
-- -----------------------------------------------------------------------

local function fmtPos(n)
  if n == nil then return "—" end
  return string.format("%.4f s", n)
end

local function captureState()
  local s = {}

  s.cursor = reaper.GetCursorPosition()

  local tsStart, tsEnd = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  s.tsStart = tsStart
  s.tsEnd   = tsEnd

  s.razorStart = nil
  s.razorEnd   = nil
  s.razorTrack = nil
  local numTracks = reaper.CountTracks(0)
  for i = 0, numTracks - 1 do
    local tr = reaper.GetTrack(0, i)
    local ok, rareas = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if ok and rareas ~= "" then
      local rs, re = rareas:match("^([%d%.%-]+)%s+([%d%.%-]+)")
      if rs then
        s.razorStart = tonumber(rs)
        s.razorEnd   = tonumber(re)
        local _, tname = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        s.razorTrack = (tname ~= "") and tname or ("Track " .. tostring(i + 1))
      end
      break
    end
  end

  local item = reaper.GetSelectedMediaItem(0, 0)
  if item then
    s.itemPos    = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    s.itemLen    = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    s.itemEnd    = s.itemPos + s.itemLen
    s.itemFadeIn = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
    s.itemFadeOut= reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")

    local take = reaper.GetActiveTake(item)
    s.itemContentOffset = take and reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or nil

    local track    = reaper.GetMediaItemTrack(item)
    local numItems = reaper.CountTrackMediaItems(track)
    s.crossfadeLeft  = nil
    s.crossfadeRight = nil
    for j = 0, numItems - 1 do
      local it = reaper.GetTrackMediaItem(track, j)
      if it == item then
        if j > 0 then
          local prev    = reaper.GetTrackMediaItem(track, j - 1)
          local prevEnd = reaper.GetMediaItemInfo_Value(prev, "D_POSITION")
                        + reaper.GetMediaItemInfo_Value(prev, "D_LENGTH")
          local ov = prevEnd - s.itemPos
          if ov > 0 then s.crossfadeLeft = ov end
        end
        if j < numItems - 1 then
          local nxt    = reaper.GetTrackMediaItem(track, j + 1)
          local nxtPos = reaper.GetMediaItemInfo_Value(nxt, "D_POSITION")
          local ov = s.itemEnd - nxtPos
          if ov > 0 then s.crossfadeRight = ov end
        end
        break
      end
    end
  else
    s.itemPos = nil; s.itemLen = nil; s.itemEnd = nil
    s.itemFadeIn = nil; s.itemFadeOut = nil
    s.itemContentOffset = nil
    s.crossfadeLeft = nil; s.crossfadeRight = nil
  end

  s.timestamp = os.date("%H:%M:%S")
  return s
end

-- -----------------------------------------------------------------------
-- Diff
-- -----------------------------------------------------------------------

local FIELD_DEFS = {
  { key = "cursor",            label = "Edit cursor"    },
  { key = "tsStart",           label = "Time sel start" },
  { key = "tsEnd",             label = "Time sel end"   },
  { key = "razorStart",        label = "Razor start"    },
  { key = "razorEnd",          label = "Razor end"      },
  { key = "itemPos",           label = "Item start"     },
  { key = "itemEnd",           label = "Item end"       },
  { key = "itemLen",           label = "Item length"    },
  { key = "itemFadeIn",        label = "Fade in"        },
  { key = "itemFadeOut",       label = "Fade out"       },
  { key = "crossfadeLeft",     label = "Crossfade left" },
  { key = "crossfadeRight",    label = "Crossfade right"},
  { key = "itemContentOffset", label = "Content offset" },
}

local EPSILON = 1e-7

local function computeDiffs(b, a)
  local diffs = {}
  for _, fd in ipairs(FIELD_DEFS) do
    local bv, av = b[fd.key], a[fd.key]
    local changed
    if type(bv) == "number" and type(av) == "number" then
      changed = math.abs(av - bv) > EPSILON
    else
      changed = (bv ~= av)
    end
    if changed then
      table.insert(diffs, { label = fd.label, before = bv, after = av })
    end
  end
  return diffs
end

local function statesEqual(a, b)
  if a == nil or b == nil then return a == b end
  for _, fd in ipairs(FIELD_DEFS) do
    local av, bv = a[fd.key], b[fd.key]
    if type(av) == "number" and type(bv) == "number" then
      if math.abs(av - bv) > EPSILON then return false end
    elseif av ~= bv then
      return false
    end
  end
  return true
end

-- -----------------------------------------------------------------------
-- Colors  (RRGGBBAA format)
-- -----------------------------------------------------------------------

local COL_LABEL  = 0xAAAAAAFF  -- medium gray
local COL_VALUE  = 0xF0F0F0FF  -- near-white
local COL_BEFORE = 0xE8A040FF  -- amber
local COL_AFTER  = 0x55DD88FF  -- green
local COL_NODIFF = 0x666666FF  -- dark gray
local COL_HEAD   = 0xFFFFFFFF  -- white

-- -----------------------------------------------------------------------
-- UI helpers
-- -----------------------------------------------------------------------

local function pushMono()
  reaper.ImGui_PushFont(ctx, FONT_MONO, MONO_FONT_SIZE)
end
local function popMono()
  reaper.ImGui_PopFont(ctx)
end

local function labelValue(label, value, valCol)
  valCol = valCol or COL_VALUE
  reaper.ImGui_TextColored(ctx, COL_LABEL, label .. ":")
  reaper.ImGui_SameLine(ctx)
  reaper.ImGui_TextColored(ctx, valCol, value)
end

local function drawSnapshotPanel(title, snap)
  reaper.ImGui_TextColored(ctx, COL_HEAD, title)
  if snap == nil then
    reaper.ImGui_TextColored(ctx, COL_NODIFF, "  (no snapshot)")
    return
  end
  reaper.ImGui_TextColored(ctx, COL_LABEL, "  @ " .. snap.timestamp)
  reaper.ImGui_Separator(ctx)
  pushMono()

  labelValue("  Cursor      ", fmtPos(snap.cursor))
  labelValue("  TS start    ", fmtPos(snap.tsStart))
  labelValue("  TS end      ", fmtPos(snap.tsEnd))

  if snap.razorStart then
    labelValue("  Razor start ", fmtPos(snap.razorStart))
    labelValue("  Razor end   ", fmtPos(snap.razorEnd))
    if snap.razorTrack then
      labelValue("  Razor track ", snap.razorTrack)
    end
  else
    reaper.ImGui_TextColored(ctx, COL_LABEL, "  Razor: —")
  end

  if snap.itemPos then
    labelValue("  Item start  ", fmtPos(snap.itemPos))
    labelValue("  Item end    ", fmtPos(snap.itemEnd))
    labelValue("  Item len    ", fmtPos(snap.itemLen))
    labelValue("  Fade in     ", fmtPos(snap.itemFadeIn))
    labelValue("  Fade out    ", fmtPos(snap.itemFadeOut))
    labelValue("  XF left     ", snap.crossfadeLeft  and fmtPos(snap.crossfadeLeft)  or "—")
    labelValue("  XF right    ", snap.crossfadeRight and fmtPos(snap.crossfadeRight) or "—")
    labelValue("  Content off ", snap.itemContentOffset and fmtPos(snap.itemContentOffset) or "—")
  else
    reaper.ImGui_TextColored(ctx, COL_LABEL, "  Item: (none selected)")
  end

  popMono()
end

local function drawDiffTable(diffs)
  if #diffs == 0 then
    reaper.ImGui_TextColored(ctx, COL_NODIFF, "  no changes detected")
    return
  end
  pushMono()
  reaper.ImGui_TextColored(ctx, COL_HEAD, string.format("  %-20s  %-18s  %-18s", "field", "before", "after"))
  reaper.ImGui_Separator(ctx)
  for _, d in ipairs(diffs) do
    local bStr = (d.before == nil) and "—" or fmtPos(d.before)
    local aStr = (d.after  == nil) and "—" or fmtPos(d.after)
    reaper.ImGui_TextColored(ctx, COL_LABEL,  string.format("  %-20s", d.label))
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, COL_BEFORE, string.format("  %-18s", bStr))
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, COL_AFTER,  string.format("  %-18s", aStr))
  end
  popMono()
end

-- -----------------------------------------------------------------------
-- Main loop
-- -----------------------------------------------------------------------

local function loop()
  reaper.ImGui_SetNextWindowSize(ctx, 680, 860, reaper.ImGui_Cond_FirstUseEver())
  reaper.ImGui_PushFont(ctx, nil, UI_FONT_SIZE)
  local visible, open = reaper.ImGui_Begin(ctx, 'Nudge Monitor v0.2', true)

  if visible then

    -- ── Auto-capture polling ──────────────────────────────────────────
    if autoMode then
      local cur = captureState()
      if autoPrev ~= nil and not statesEqual(autoPrev, cur) then
        local diffs = computeDiffs(autoPrev, cur)
        snapBefore = autoPrev
        snapAfter  = cur
        table.insert(log, 1, { label = "[auto]", before = autoPrev, after = cur, diffs = diffs })
        if #log > MAX_LOG then table.remove(log) end
      end
      autoPrev = cur
    end

    -- ── Auto-capture toggle ───────────────────────────────────────────
    local btnCol     = autoMode and 0x229944FF or 0x444444FF
    local btnHovCol  = autoMode and 0x33BB66FF or 0x666666FF
    local btnLabel   = autoMode and "● Auto ON " or "○ Auto OFF"
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),        btnCol)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), btnHovCol)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  btnHovCol)
    if reaper.ImGui_Button(ctx, btnLabel) then
      autoMode = not autoMode
      autoPrev = autoMode and captureState() or nil
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, COL_LABEL,
      autoMode and "Watching for state changes…" or "Manual capture mode")

    reaper.ImGui_Separator(ctx)

    -- ── Live state ────────────────────────────────────────────────────
    if reaper.ImGui_CollapsingHeader(ctx, "Live State") then
      local live = captureState()
      pushMono()
      labelValue("  Cursor    ", fmtPos(live.cursor))
      labelValue("  TS        ", fmtPos(live.tsStart) .. " → " .. fmtPos(live.tsEnd))
      if live.razorStart then
        labelValue("  Razor     ", fmtPos(live.razorStart) .. " → " .. fmtPos(live.razorEnd))
      else
        reaper.ImGui_TextColored(ctx, COL_LABEL, "  Razor: —")
      end
      if live.itemPos then
        labelValue("  Item      ", fmtPos(live.itemPos) .. " → " .. fmtPos(live.itemEnd))
        labelValue("  Fade in   ", fmtPos(live.itemFadeIn))
        labelValue("  Fade out  ", fmtPos(live.itemFadeOut))
        labelValue("  XF left   ", live.crossfadeLeft  and fmtPos(live.crossfadeLeft)  or "—")
        labelValue("  XF right  ", live.crossfadeRight and fmtPos(live.crossfadeRight) or "—")
        labelValue("  Cont.off  ", live.itemContentOffset and fmtPos(live.itemContentOffset) or "—")
      else
        reaper.ImGui_TextColored(ctx, COL_LABEL, "  Item: (none selected)")
      end
      popMono()
    end

    reaper.ImGui_Separator(ctx)

    -- ── Manual capture buttons ────────────────────────────────────────
    if reaper.ImGui_Button(ctx, "  Capture BEFORE  ") then
      snapBefore = captureState()
      snapAfter  = nil
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, COL_LABEL,
      snapBefore and ("@ " .. snapBefore.timestamp) or "—")

    reaper.ImGui_SameLine(ctx, 0, 24)

    if reaper.ImGui_Button(ctx, "  Capture AFTER  ") then
      snapAfter = captureState()
      if snapBefore and snapAfter then
        local diffs = computeDiffs(snapBefore, snapAfter)
        table.insert(log, 1, { label = "(manual)", before = snapBefore, after = snapAfter, diffs = diffs })
        if #log > MAX_LOG then table.remove(log) end
      end
    end
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, COL_LABEL,
      snapAfter and ("@ " .. snapAfter.timestamp) or "—")

    reaper.ImGui_Separator(ctx)

    -- ── Action buttons ────────────────────────────────────────────────
    reaper.ImGui_TextColored(ctx, COL_HEAD, "Actions")
    local btnW = 140
    for i, act in ipairs(ACTIONS) do
      if (i - 1) % 2 ~= 0 then reaper.ImGui_SameLine(ctx) end
      if reaper.ImGui_Button(ctx, act.label, btnW, 0) then
        local cmdID = resolveCmd(act.cmdStr)
        local before = captureState()
        if cmdID ~= 0 then
          reaper.Main_OnCommand(cmdID, 0)
        else
          reaper.ShowMessageBox(
            "Command ID for '" .. act.label .. "' is not set.\nOpen 'Configure Actions' below to enter it.",
            "Nudge Monitor", 0)
        end
        local after = captureState()
        local diffs = computeDiffs(before, after)
        snapBefore = before
        snapAfter  = after
        table.insert(log, 1, { label = act.label, before = before, after = after, diffs = diffs })
        if #log > MAX_LOG then table.remove(log) end
      end
    end

    reaper.ImGui_Separator(ctx)

    -- ── Configure Actions ─────────────────────────────────────────────
    if reaper.ImGui_CollapsingHeader(ctx, "Configure Actions") then
      reaper.ImGui_TextColored(ctx, COL_LABEL,
        "Paste an integer ID or _RS... named command string.")
      reaper.ImGui_Spacing(ctx)

      for i, act in ipairs(ACTIONS) do
        -- Label field
        reaper.ImGui_SetNextItemWidth(ctx, 130)
        local rv, newLabel = reaper.ImGui_InputText(ctx, "##label" .. i, act.labelBuf)
        if rv then
          act.labelBuf = newLabel
          if newLabel ~= "" then
            act.label = newLabel
            reaper.SetExtState(EXT_SEC, "label_" .. i, newLabel, true)
          end
        end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, COL_LABEL, "→ ID:")
        reaper.ImGui_SameLine(ctx)

        -- Command ID field
        reaper.ImGui_SetNextItemWidth(ctx, 340)
        local rc, newCmd = reaper.ImGui_InputText(ctx, "##cmd" .. i, act.cmdBuf)
        if rc then
          act.cmdBuf = newCmd
          act.cmdStr = newCmd
          reaper.SetExtState(EXT_SEC, "cmd_" .. i, newCmd, true)
        end

        -- Show resolved status
        reaper.ImGui_SameLine(ctx)
        local resolved = resolveCmd(act.cmdStr)
        if resolved ~= 0 then
          reaper.ImGui_TextColored(ctx, COL_AFTER, "✓ " .. tostring(resolved))
        elseif act.cmdStr ~= "" then
          reaper.ImGui_TextColored(ctx, COL_BEFORE, "! not found")
        else
          reaper.ImGui_TextColored(ctx, COL_NODIFF, "(not set)")
        end
      end

      reaper.ImGui_Spacing(ctx)
      if reaper.ImGui_Button(ctx, "Reset all to defaults") then
        for i, act in ipairs(ACTIONS) do
          act.cmdStr  = ""
          act.cmdBuf  = ""
          reaper.SetExtState(EXT_SEC, "cmd_" .. i, "", true)
        end
      end
    end

    reaper.ImGui_Separator(ctx)

    -- ── Snapshot panels ───────────────────────────────────────────────
    reaper.ImGui_BeginGroup(ctx)
    drawSnapshotPanel("BEFORE", snapBefore)
    reaper.ImGui_EndGroup(ctx)

    reaper.ImGui_SameLine(ctx, 0, 8)

    reaper.ImGui_BeginGroup(ctx)
    drawSnapshotPanel("AFTER", snapAfter)
    reaper.ImGui_EndGroup(ctx)

    reaper.ImGui_Separator(ctx)

    -- ── Diff of most recent pair ──────────────────────────────────────
    if snapBefore and snapAfter then
      reaper.ImGui_TextColored(ctx, COL_HEAD, "Diff (latest)")
      drawDiffTable(computeDiffs(snapBefore, snapAfter))
    end

    reaper.ImGui_Separator(ctx)

    -- ── Log ───────────────────────────────────────────────────────────
    if reaper.ImGui_CollapsingHeader(ctx, string.format("Log  (%d entries)", #log)) then
      if reaper.ImGui_Button(ctx, "Clear log") then log = {} end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Copy log to clipboard") then
        local lines = { "Nudge Monitor Log — " .. os.date("%Y-%m-%d %H:%M:%S"), "" }
        for idx, entry in ipairs(log) do
          table.insert(lines, string.format("[%d] %s  before:%s  after:%s",
            idx, entry.label, entry.before.timestamp, entry.after.timestamp))
          if #entry.diffs == 0 then
            table.insert(lines, "    (no changes)")
          else
            for _, d in ipairs(entry.diffs) do
              local bStr = (d.before == nil) and "—" or fmtPos(d.before)
              local aStr = (d.after  == nil) and "—" or fmtPos(d.after)
              table.insert(lines, string.format("    %-20s  %s  →  %s", d.label, bStr, aStr))
            end
          end
          table.insert(lines, "")
        end
        reaper.ImGui_SetClipboardText(ctx, table.concat(lines, "\n"))
      end
      for idx, entry in ipairs(log) do
        local header = string.format("[%d] %s  before:%s  after:%s",
          idx, entry.label, entry.before.timestamp, entry.after.timestamp)
        local hasDiff = #entry.diffs > 0
        reaper.ImGui_TextColored(ctx, hasDiff and COL_AFTER or COL_NODIFF, header)
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_BeginTooltip(ctx)
          drawDiffTable(entry.diffs)
          reaper.ImGui_EndTooltip(ctx)
        end
        if hasDiff then
          pushMono()
          for _, d in ipairs(entry.diffs) do
            local bStr = (d.before == nil) and "—" or fmtPos(d.before)
            local aStr = (d.after  == nil) and "—" or fmtPos(d.after)
            reaper.ImGui_TextColored(ctx, COL_LABEL,  string.format("    %-20s", d.label))
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, COL_BEFORE, string.format("%-16s", bStr))
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, COL_AFTER,  string.format("%-16s", aStr))
          end
          popMono()
        end
      end
    end

    reaper.ImGui_End(ctx)
  end
  reaper.ImGui_PopFont(ctx)

  if open then reaper.defer(loop) end
end

reaper.defer(loop)
