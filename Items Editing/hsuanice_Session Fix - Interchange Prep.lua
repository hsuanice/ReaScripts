--[[
@description Session Fix - Interchange Prep: check and fix a REAPER session before converting it with Interchanger
@version 26.1015.1125
@author hsuanice
@noindex
@changelog
  - Change: each check shows a short coloured title and a one-line description; colour = impact on the sound in an editing session (red print / delete, orange big change, yellow small change, green sound unchanged, grey review only), with a legend above the list.
@about
  # Session Fix - Interchange Prep

  One checklist for preparing a REAPER session for Interchanger (Pro Tools / Nuendo / Cubase):
  hidden / collapsed tracks, take volume / pan, mixed channel tracks, folders and empty tracks,
  track numbering, track volume / pan / width / polarity (L/R pairs hard left / right), mute /
  solo, envelopes, items that need a render (playrate, pitch, stretch markers, take FX,
  polarity), hidden overlaps and slivers, broken crossfades, meeting fades, fade shapes, items
  past their source, frame-grid edges, empty and MIDI items, take channel mode, inactive takes.
  Media outside the project folder / not WAV / other sample rate is shown at the top.

  Workflow: Save as Interchange copy -> Scan -> Fix (each check, or Fix All) -> review -> Verify
  vs. start -> convert with Interchanger.

  - Select / Mark / Fix act on all issues of a check. Open a list to Fix / Mark only the issues
    selected in it (click, Cmd+click, Shift+click).
  - Clicking a list entry selects it, highlights the key spot with a razor area and zooms there.
  - Printing uses RGWH Render; the original is kept muted on "<track> original" and a project
    marker "Render: <reason>" is added. Deleted items can be kept for review on
    "<track> before / removed" (Settings).
  - Every fix is checked before / after (audio position, crossfades, tracks); Fix All stops at
    the first problem. "Verify vs. start" compares the whole session with the moment the window
    opened (right-click: set a new start point).
  - Done in this session: what each fix deleted / printed, with Reviewed buttons.
  - Settings: fade shapes (REAPER's own shape actions), track number format, keep deleted items
    for review, zoom to the clicked spot, allow docking, font size.

  Requires ReaImGui and the "hsuanice Library" package (Session Fix Core, RGWH Core).
  js_ReaScriptAPI is optional (vertical zoom / centring when a list entry is clicked).
--]]

-- hsuanice Library is a separate ReaPack package: tell the user if it is missing
do
  local lib_dir = reaper.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/'
  for _, name in ipairs({ 'hsuanice_Session Fix Core.lua' }) do
    if not reaper.file_exists(lib_dir .. name) then
      reaper.MB('This script needs the "hsuanice Library" package.\n\n'
        .. 'Please install it with ReaPack (Extensions > ReaPack > Browse packages),\n'
        .. 'then run this script again.\n\nMissing file: ' .. name,
        'hsuanice Library not found', 0)
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages('hsuanice Library') end
      return
    end
  end
end

local r = reaper
if not r.ImGui_GetBuiltinPath then
  r.MB("This script needs ReaImGui (install it with ReaPack: ReaTeam Extensions).", "Session Fix - Interchange Prep", 0)
  return
end
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10'

local CORE = dofile(r.GetResourcePath() .. '/Scripts/hsuanice Scripts/Library/hsuanice_Session Fix Core.lua')

-- Version: read from the @version tag in the header (single source of truth)
local VERSION = "unknown"
do
  local f = io.open(debug.getinfo(1, "S").source:match("^@(.+)$") or "", "r")
  if f then
    for line in f:lines() do
      local ver = line:match("^@version%s+(.+)$")
      if ver then VERSION = ver break end
      if line:match("^@changelog") then break end
    end
    f:close()
  end
end

local TITLE = "Session Fix - Interchange Prep"
local MAX_LIST = 500 -- issues listed per check in the window (the report lists all)

-- Preferences (remembered between sessions)
local EXT_NS = "hsuanice_SessionFixPrep"
local FONT_BASE = 13
local function pref_get(key, default)
  local v = r.GetExtState(EXT_NS, key)
  if v == "" then return default end
  return v
end
local prefs = {
  font_scale = tonumber(pref_get("font_scale", "1.25")) or 1.25, -- 125% by default
  allow_docking = pref_get("allow_docking", "0") == "1",
  keep_folders = pref_get("keep_folders", "0") == "1",
  number_width = tonumber(pref_get("number_width", "2")) or 2, -- track numbering: 1 / 01 / 001
  -- fade shapes: index into CORE.FADE_SHAPES (REAPER's native shape actions)
  -- default = linear / linear / crossfade "slight convex, equal power" (actions 41514 + 41521 + 41529)
  fade_in_shape = tonumber(pref_get("fade_in_idx", "1")) or 1,
  fade_out_shape = tonumber(pref_get("fade_out_idx", "1")) or 1,
  xfade_shape = tonumber(pref_get("xfade_idx", "2")) or 2,
  keep_removed = pref_get("keep_removed", "0") == "1", -- review copies of deleted items (<track> before / removed)
  auto_zoom = pref_get("auto_zoom", "1") == "1", -- clicking a list entry zooms to it (centre, ~2/3 wide)
}
local function save_prefs()
  r.SetExtState(EXT_NS, "font_scale", tostring(prefs.font_scale), true)
  r.SetExtState(EXT_NS, "allow_docking", prefs.allow_docking and "1" or "0", true)
  r.SetExtState(EXT_NS, "keep_folders", prefs.keep_folders and "1" or "0", true)
  r.SetExtState(EXT_NS, "number_width", tostring(prefs.number_width), true)
  r.SetExtState(EXT_NS, "fade_in_idx", tostring(prefs.fade_in_shape), true)
  r.SetExtState(EXT_NS, "fade_out_idx", tostring(prefs.fade_out_shape), true)
  r.SetExtState(EXT_NS, "xfade_idx", tostring(prefs.xfade_shape), true)
  r.SetExtState(EXT_NS, "keep_removed", prefs.keep_removed and "1" or "0", true)
  r.SetExtState(EXT_NS, "auto_zoom", prefs.auto_zoom and "1" or "0", true)
  CORE.auto_zoom = prefs.auto_zoom
end
local function S(v) return math.floor(v * prefs.font_scale + 0.5) end -- scale a pixel size with the font
local function scan_opts()
  return { keep_folders = prefs.keep_folders, number_width = prefs.number_width,
    fade_in_shape = prefs.fade_in_shape, fade_out_shape = prefs.fade_out_shape, xfade_shape = prefs.xfade_shape,
    keep_removed = prefs.keep_removed }
end

local ctx = ImGui.CreateContext(TITLE)
local state = {
  results = nil, summary = nil,
  scanned_change = nil, -- project state change count at scan time
  status = "Press Scan to check the session.",
  sel = {},    -- [rule id] = { [issue index] = true }
  anchor = {}, -- [rule id] = last clicked index (for Shift+click)
  audit = nil,    -- last before / after check { title=, problems=, summary=, undo= }
  history = {},   -- [rule id] = { deleted / printed entries } from the fixes of this session
  history_proj = nil,
  force_open = {}, -- [rule id] = true: open its list on the next frame (after a fix that deleted / printed)
  open_all = nil,  -- true / false: open / close every list on the next frame
  baseline = nil, -- snapshot of the project when the script opened ("Verify vs. start")
  baseline_proj = nil,
}

local COL_OK   = 0x7FD37FFF
local COL_BAD  = 0xFF9B4AFF
local COL_INFO = 0xA0A0A0FF
local COL_RED  = 0xFF5050FF
local COL_YEL  = 0xF0D040FF
local COL_ORG  = 0xFF9B4AFF
local COL_GREY = 0x9A9A9AFF
-- impact level of a check (see CORE: red / orange / yellow / green / review)
local LEVEL_COL = { red = COL_RED, orange = COL_ORG, yellow = COL_YEL, green = COL_OK, review = COL_GREY }

local function project_key()
  local proj, path = r.EnumProjects(-1, "")
  return tostring(proj) .. "|" .. (path or "")
end

local function do_scan()
  state.results, state.summary = CORE.scan(scan_opts())
  state.scanned_change = r.GetProjectStateChangeCount(0)
  state.sel, state.anchor = {}, {}
  state.status = string.format("Scanned %d tracks, %d items: %d issue%s.",
    state.summary.tracks, state.summary.items, state.summary.total, state.summary.total == 1 and "" or "s")
end

-- Selecting / marking changes REAPER's state counter but not the scan result
local function keep_scan_fresh()
  if state.results then state.scanned_change = r.GetProjectStateChangeCount(0) end
end

local function save_report()
  if not state.results then do_scan() end
  local text = CORE.report(state.results, state.summary)
  local _, proj_path = r.EnumProjects(-1, "")
  local dir = (proj_path or ""):match("^(.*[/\\])")
  if not dir then dir = r.GetResourcePath() .. "/" end
  local path = dir .. "SessionFix_report_" .. os.date("%y%m%d_%H%M%S") .. ".txt"
  local f = io.open(path, "w")
  if not f then
    r.MB("Could not write the report:\n" .. path, TITLE, 0)
    return
  end
  f:write(text)
  f:close()
  state.status = "Report saved: " .. path
end

-- Issues a button acts on: all of them, or (selected_only) the ones selected in the list
local function target_issues(d, selected_only)
  local list = state.results and state.results[d.id] or {}
  local sel = state.sel[d.id]
  if not selected_only then return list, false end
  if not sel or not next(sel) then return {}, true end
  local out = {}
  for k, is in ipairs(list) do if sel[k] then out[#out + 1] = is end end
  return out, true
end

local function count_sel(id)
  local n = 0
  for _ in pairs(state.sel[id] or {}) do n = n + 1 end
  return n
end

local function reveal_issue(is)
  local at = nil
  if is.positions and #is.positions > 0 then
    -- several edges (e.g. start and end): each click jumps to the next one
    is._next = ((is._next or 0) % #is.positions) + 1
    at = is.positions[is._next]
    state.status = "Showing: " .. (is.labels and is.labels[is._next] or "") ..
      (#is.positions > 1 and string.format("  (%d / %d, click again for the next edge)", is._next, #is.positions) or "")
  end
  CORE.reveal(is, at) -- scroll horizontally and vertically to the item / track
end

-- Click handling in an issue list: plain = single, Cmd = toggle, Shift = range
local function click_issue(d, k, list)
  local mods = ImGui.GetKeyMods(ctx)
  local sel = state.sel[d.id] or {}
  if (mods & ImGui.Mod_Shift) ~= 0 and state.anchor[d.id] then
    local a, b = state.anchor[d.id], k
    if a > b then a, b = b, a end
    if (mods & ImGui.Mod_Ctrl) == 0 then sel = {} end
    for i = a, b do sel[i] = true end
  elseif (mods & ImGui.Mod_Ctrl) ~= 0 then -- Cmd on macOS
    sel[k] = (not sel[k]) or nil
    state.anchor[d.id] = k
  else
    sel = { [k] = true }
    state.anchor[d.id] = k
  end
  state.sel[d.id] = sel
  local picked = {}
  for i, is in ipairs(list) do if sel[i] then picked[#picked + 1] = is end end
  if #picked > 0 then CORE.select_issues(picked); CORE.highlight_issues(picked) end
  if sel[k] then reveal_issue(list[k]) end
  keep_scan_fresh()
end

-- Remember what a fix deleted / printed, listed under its check
local function add_history(d, audit)
  if state.history_proj ~= project_key() then state.history, state.history_proj = {}, project_key() end
  if not (audit and audit.log and #audit.log > 0) then return end
  local h = state.history[d.id] or {}
  for _, e in ipairs(audit.log) do h[#h + 1] = e end
  state.history[d.id] = h
  state.force_open[d.id] = true -- show what was done / what to review right away
end

local function history_of(d)
  if state.history_proj ~= project_key() then return {} end
  return state.history[d.id] or {}
end

local function run_fix(d, selected_only)
  local issues, partial = target_issues(d, selected_only)
  if #issues == 0 then return end
  if d.instructions then
    if r.MB(d.instructions, TITLE, 4) == 6 then r.Main_OnCommand(40022, 0) end -- File: Save project as...
    return
  end
  local question = d.confirm and d.confirm(issues) -- nil = nothing printed / deleted: no question
  if question and r.MB(question, TITLE, 1) ~= 1 then return end
  local _, msg, audit = CORE.fix(d, issues, scan_opts())
  add_history(d, audit)
  if audit then state.audit = { title = "After \"" .. d.title .. "\"", problems = audit.problems, summary = audit.summary, undo = "Session Fix: " .. d.title } end
  do_scan()
  state.status = string.format("Fixed \"%s\"%s: %s. Rescanned: %d issue%s left in total.",
    d.title, partial and " (selected only)" or "", msg, state.summary.total, state.summary.total == 1 and "" or "s")
end

-- Fix All: every check that has an automatic fix, in list order, rescanning after each one.
-- One confirmation up front; stops at the first fix whose before / after check finds a problem.
local function run_fix_all()
  do_scan()
  local plan = {}
  for _, d in ipairs(CORE.RULES) do
    local n = #(state.results[d.id] or {})
    if d.fix and not d.instructions and n > 0 then plan[#plan + 1] = { d = d, n = n } end
  end
  if #plan == 0 then state.status = "Fix All: nothing left that can be fixed automatically."; return end
  local lines = {}
  for _, p in ipairs(plan) do
    local asks = p.d.confirm and p.d.confirm(state.results[p.d.id] or {}) ~= nil
    lines[#lines + 1] = string.format("  %s%s: %d", asks and "* " or "", p.d.title, p.n)
  end
  local text = "Fix All will run these fixes in order (rescanning after each):\n\n" .. table.concat(lines, "\n")
    .. "\n\n* deletes tracks / items or prints audio with RGWH Render\n"
    .. "  (printed originals are kept, muted, on \"<track> original\"). Hover a check for details.\n\n"
    .. "Every fix is checked before / after; Fix All stops at the first one that moves audio,\n"
    .. "a crossfade or a track. Review-only checks and instructions (media) are skipped.\n\nContinue?"
  if r.MB(text, TITLE, 1) ~= 1 then return end
  local log, problems = {}, {}
  local total = { changed = 0, snapped = 0, rendered = 0, deleted = 0, red = 0, yellow = 0 }
  for _, p in ipairs(plan) do
    local d = p.d
    local issues = state.results[d.id] or {}
    if #issues > 0 then
      local _, msg, audit = CORE.fix(d, issues, scan_opts())
      add_history(d, audit)
      do_scan()
      log[#log + 1] = d.title .. ": " .. msg
      if audit then
        if audit.summary.red > 0 then
          state.audit = { title = "Fix All stopped at \"" .. d.title .. "\"", problems = audit.problems,
            summary = audit.summary, undo = "Session Fix: " .. d.title, log = log }
          state.status = string.format("Fix All STOPPED after %d fix%s: \"%s\" changed audio, a crossfade or a track. See the warning above.",
            #log, #log == 1 and "" or "es", d.title)
          return
        end
        for k, v in pairs(audit.summary) do total[k] = (total[k] or 0) + v end
        for _, pr in ipairs(audit.problems) do pr.text = "[" .. d.title .. "] " .. pr.text; problems[#problems + 1] = pr end
      end
    end
  end
  state.audit = { title = string.format("Fix All (%d fix%s)", #log, #log == 1 and "" or "es"), problems = problems,
    summary = total, undo = false, log = log }
  state.status = string.format("Fix All done: %d fix%s run. Rescanned: %d issue%s left (review-only checks, instructions, failures).",
    #log, #log == 1 and "" or "es", state.summary.total, state.summary.total == 1 and "" or "s")
end

local function set_start()
  state.baseline, state.baseline_proj = CORE.snapshot(), project_key()
  state.status = "Start point set at " .. state.baseline.time .. ": Verify compares the session with this moment."
end

local function verify_vs_start()
  local problems, summary = CORE.compare(state.baseline, CORE.snapshot(), nil)
  state.audit = { title = "Since the start (" .. state.baseline.time .. ")", problems = problems, summary = summary, undo = false }
end

-- Before / after check of the last fix (or of the whole session since the start)
local function draw_audit()
  local a = state.audit
  if not a then return end
  local sm = a.summary
  local info = string.format("%s: %d item%s changed (%d snapped to the grid, %d printed, %d media copied / relinked, %d deleted)",
    a.title, sm.changed, sm.changed == 1 and "" or "s", sm.snapped, sm.rendered, sm.relinked or 0, sm.deleted)
  if sm.red > 0 then
    ImGui.TextColored(ctx, COL_RED, string.format("WARNING: %d problem%s - audio, crossfade or track changed. Check before you continue.", sm.red, sm.red == 1 and "" or "s"))
  elseif sm.yellow > 0 then
    ImGui.TextColored(ctx, COL_YEL, string.format("Please check %d change%s.", sm.yellow, sm.yellow == 1 and "" or "s"))
  else
    ImGui.TextColored(ctx, COL_OK, "Check OK: no audio moved, no crossfade moved, no item changed track.")
  end
  ImGui.TextColored(ctx, COL_INFO, info)
  if a.undo then
    local last = r.Undo_CanUndo2(0)
    local can = last == a.undo -- only while this fix is still the last undo point
    ImGui.BeginDisabled(ctx, not can)
    if ImGui.Button(ctx, "Undo this fix") then
      r.Main_OnCommand(40029, 0) -- Edit: Undo
      state.audit = nil
      do_scan()
      state.status = "Undone: " .. (last or "")
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
  end
  if ImGui.Button(ctx, "Dismiss") then state.audit = nil; return end
  if a.log and #a.log > 0 and ImGui.TreeNode(ctx, "What each fix did##auditlog") then
    for _, line in ipairs(a.log) do ImGui.TextColored(ctx, COL_INFO, line) end
    ImGui.TreePop(ctx)
  end
  if #a.problems > 0 then
    local h = math.min(#a.problems, 6) * ImGui.GetTextLineHeightWithSpacing(ctx) + S(30)
    local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_ScrollY
    if ImGui.BeginTable(ctx, "audit", 3, flags, 0, h) then
      ImGui.TableSetupColumn(ctx, "Change", ImGui.TableColumnFlags_WidthStretch, 3)
      ImGui.TableSetupColumn(ctx, "Track", ImGui.TableColumnFlags_WidthStretch, 1.4)
      ImGui.TableSetupColumn(ctx, "Position", ImGui.TableColumnFlags_WidthFixed, S(90))
      ImGui.TableSetupScrollFreeze(ctx, 0, 1)
      ImGui.TableHeadersRow(ctx)
      for k, p in ipairs(a.problems) do
        if k > MAX_LIST then break end
        local trk, pos = CORE.issue_where(p)
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, p.level == "red" and COL_RED or COL_YEL)
        if ImGui.Selectable(ctx, p.text .. "##audit" .. k, false, ImGui.SelectableFlags_SpanAllColumns) then
          if p.item and r.ValidatePtr2(0, p.item, "MediaItem*") then CORE.select_issues({ p }) end
          CORE.highlight_issues({ p })
          CORE.reveal(p.item and p or { pos = p.pos, scroll_track = p.range_track }, p.pos)
          keep_scan_fresh()
        end
        ImGui.PopStyleColor(ctx)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, trk)
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, pos ~= "" and pos or CORE.tc(p.pos or 0))
      end
      ImGui.EndTable(ctx)
    end
  end
  ImGui.Separator(ctx)
end

local function draw_issue_table(d, list)
  local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_Resizable
  if not ImGui.BeginTable(ctx, "issues_" .. d.id, 4, flags) then return end
  ImGui.TableSetupColumn(ctx, "Issue", ImGui.TableColumnFlags_WidthStretch, 3)
  ImGui.TableSetupColumn(ctx, "Track", ImGui.TableColumnFlags_WidthStretch, 1.4)
  ImGui.TableSetupColumn(ctx, "Position", ImGui.TableColumnFlags_WidthFixed, S(90))
  ImGui.TableSetupColumn(ctx, "Take / item", ImGui.TableColumnFlags_WidthStretch, 2.4)
  ImGui.TableHeadersRow(ctx)
  local sel = state.sel[d.id] or {}
  for k, is in ipairs(list) do
    if k > MAX_LIST then
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.TextDisabled(ctx, string.format("... %d more (see the report)", #list - MAX_LIST))
      break
    end
    local trk, pos, name = CORE.issue_where(is)
    ImGui.TableNextRow(ctx)
    ImGui.TableNextColumn(ctx)
    if ImGui.Selectable(ctx, (is.text or "") .. "##" .. k, sel[k] == true, ImGui.SelectableFlags_SpanAllColumns) then
      click_issue(d, k, list)
    end
    ImGui.TableNextColumn(ctx); ImGui.Text(ctx, trk)
    ImGui.TableNextColumn(ctx); ImGui.Text(ctx, pos)
    ImGui.TableNextColumn(ctx); ImGui.Text(ctx, name)
  end
  ImGui.EndTable(ctx)
end

-- What the fixes of this check deleted / printed (this session): click = jump there
-- Review done: delete the review copies (before / removed / original) of these changes
local function mark_reviewed(entries)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local n = 0
  local kept = 0
  for _, e in ipairs(entries) do
    if e.copies and not e.reviewed then
      if e.kind == "printed" then kept = kept + CORE.mark_copies_reviewed(e.copies) -- the original stays
      else n = n + CORE.clear_review(e.copies); e.copies = nil end
    end
    e.reviewed = true
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Session Fix: reviewed, review copies removed", -1)
  keep_scan_fresh()
  state.status = string.format("Reviewed: %d review cop%s removed, %d original%s kept (the list stays).",
    n, n == 1 and "y" or "ies", kept, kept == 1 and "" or "s")
end

local function draw_history_table(d, hist)
  ImGui.TextColored(ctx, COL_INFO, "Done in this session (click to jump there):")
  local pending = {}
  for _, e in ipairs(hist) do if e.copies and not e.reviewed then pending[#pending + 1] = e end end
  if #pending > 0 then
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, string.format("All reviewed (%d)##allrev", #pending)) then mark_reviewed(pending) end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Deleted items: remove their review copies (<track> before / removed).\nPrinted items: the original stays, marked as reviewed. The list stays.") end
  end
  local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_Resizable
  if not ImGui.BeginTable(ctx, "hist_" .. d.id, 5, flags) then return end
  ImGui.TableSetupColumn(ctx, "Done", ImGui.TableColumnFlags_WidthStretch, 3)
  ImGui.TableSetupColumn(ctx, "Track", ImGui.TableColumnFlags_WidthStretch, 1.4)
  ImGui.TableSetupColumn(ctx, "Position", ImGui.TableColumnFlags_WidthFixed, S(90))
  ImGui.TableSetupColumn(ctx, "Take / item", ImGui.TableColumnFlags_WidthStretch, 2.4)
  ImGui.TableSetupColumn(ctx, "Review", ImGui.TableColumnFlags_WidthFixed, 0)
  ImGui.TableHeadersRow(ctx)
  for k, e in ipairs(hist) do
    if k > MAX_LIST then break end
    ImGui.TableNextRow(ctx)
    ImGui.TableNextColumn(ctx)
    local label = (e.kind == "printed" and "PRINTED: " or "DELETED: ") .. (e.reason or "")
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, e.kind == "printed" and COL_OK or COL_YEL)
    -- AllowOverlap: the row spans all columns, the Reviewed button at its end must still get clicks
    local sflags = ImGui.SelectableFlags_SpanAllColumns | (ImGui.SelectableFlags_AllowOverlap or ImGui.SelectableFlags_AllowItemOverlap or 0)
    if ImGui.Selectable(ctx, label .. "##h" .. k, false, sflags) then
      local live = {}
      for _, c in ipairs(e.copies or {}) do if r.ValidatePtr2(0, c, "MediaItem*") then live[#live + 1] = { item = c } end end
      if #live > 0 then -- show the review copies (before / removed, or the kept original)
        CORE.select_issues(live)
        -- razor only on the key spot: where the deleted / printed item was (not the whole long neighbours)
        CORE.highlight_issues(live, e.s, e.e)
        CORE.reveal({ item = live[1].item }, e.s)
        state.status = (e.kind == "printed" and "Original before printing: " or "Before / removed: ") .. (e.reason or "")
          .. " - press Reviewed when it is fine."
      elseif e.kind == "printed" and e.item and r.ValidatePtr2(0, e.item, "MediaItem*") then
        CORE.select_issues({ { item = e.item } }) -- the item with its new, printed take
        CORE.highlight_issues({ { item = e.item } })
        CORE.reveal({ item = e.item })
        state.status = "Printed item: " .. (e.reason or "") .. " (the original is on \"<track> original\")"
      elseif e.kind == "deleted" then
        r.SelectAllMediaItems(0, false)
        CORE.reveal_range(e.track, e.s, e.e) -- where it was: razor area on that track
        state.status = "Deleted here: " .. (e.reason or "") .. " (razor area = where the item was)"
      else
        state.status = "Deleted track: " .. (e.where and e.where[1] or "") .. " - " .. (e.reason or "")
      end
      keep_scan_fresh()
    end
    ImGui.PopStyleColor(ctx)
    ImGui.TableNextColumn(ctx); ImGui.Text(ctx, e.where and e.where[1] or "")
    ImGui.TableNextColumn(ctx); ImGui.Text(ctx, e.where and e.where[2] or "")
    ImGui.TableNextColumn(ctx); ImGui.Text(ctx, e.where and e.where[3] or "")
    ImGui.TableNextColumn(ctx)
    if e.copies and not e.reviewed then
      if ImGui.SmallButton(ctx, "Reviewed##rev" .. k) then mark_reviewed({ e }) end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, e.kind == "printed" and "Checked: the original stays on \"<track> original\", marked as reviewed"
          or "Checked: remove its review copies (the list entry stays)")
      end
    elseif e.reviewed then
      ImGui.TextColored(ctx, COL_OK, "reviewed")
    end
  end
  ImGui.EndTable(ctx)
end

local function draw_rules()
  -- NoSavedSettings: column widths are not remembered in the ImGui ini (a stale wide column stuck)
  local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_ScrollY | ImGui.TableFlags_NoSavedSettings
  -- right above the checklist, on the left: open / close every list
  if ImGui.Button(ctx, "Open all") then state.open_all = true end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Open the list of every check that has issues or done items") end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Close all") then state.open_all = false end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Close every list (lists with items to review stay open)") end
  -- colour legend: what a fix does to the sound (rated for an editing session)
  ImGui.SameLine(ctx, 0, S(18))
  ImGui.TextColored(ctx, COL_INFO, CORE.SESSION_TYPE .. ":")
  for _, l in ipairs({ { "red", "print / delete" }, { "orange", "big change" }, { "yellow", "small change" },
      { "green", "sound unchanged" }, { "review", "review only" } }) do
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, LEVEL_COL[l[1]], l[2])
  end
  local _, avail_h = ImGui.GetContentRegionAvail(ctx)
  if not ImGui.BeginTable(ctx, "rules", 4, flags, 0, avail_h) then return end
  ImGui.TableSetupScrollFreeze(ctx, 0, 1) -- keep the header row visible
  -- fixed columns with width 0 fit their content (the buttons / numbers) every frame
  ImGui.TableSetupColumn(ctx, "Actions", ImGui.TableColumnFlags_WidthFixed, 0)
  ImGui.TableSetupColumn(ctx, "Issues", ImGui.TableColumnFlags_WidthFixed, 0)
  ImGui.TableSetupColumn(ctx, "#", ImGui.TableColumnFlags_WidthFixed, 0)
  ImGui.TableSetupColumn(ctx, "Check", ImGui.TableColumnFlags_WidthStretch)
  ImGui.TableHeadersRow(ctx)

  local shown = 0
  for _, d in ipairs(CORE.RULES) do
    if d.banner then goto next_rule end -- shown at the top (e.g. media outside the project)
    shown = shown + 1
    local list = state.results and state.results[d.id]
    local n = list and #list or nil
    local nsel = count_sel(d.id)
    ImGui.PushID(ctx, d.id)
    ImGui.TableNextRow(ctx)

    -- Actions (left)
    ImGui.TableNextColumn(ctx)
    ImGui.BeginDisabled(ctx, not (n and n > 0))
    if ImGui.Button(ctx, "Select##sel") then
      CORE.select_issues((target_issues(d))); keep_scan_fresh()
    end
    ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, d.scope == "track")
    if ImGui.Button(ctx, "Mark##mark") then
      local added = CORE.mark_issues((target_issues(d)), d)
      state.status = string.format("%s: %d take marker%s added.", d.title, added, added == 1 and "" or "s")
      keep_scan_fresh()
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    local can_fix = d.fix ~= nil or d.instructions ~= nil
    ImGui.BeginDisabled(ctx, not can_fix)
    if ImGui.Button(ctx, "Fix##fix") then run_fix(d) end
    ImGui.EndDisabled(ctx)
    if not can_fix and ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
      ImGui.SetTooltip(ctx, "Automatic fix comes in a later version")
    end
    ImGui.EndDisabled(ctx)

    -- Issues (right next to the buttons: the biggest problems are easy to spot)
    ImGui.TableNextColumn(ctx)
    if n == nil then
      ImGui.TextColored(ctx, COL_INFO, "-")
    elseif n == 0 then
      ImGui.TextColored(ctx, COL_OK, "OK")
    else
      ImGui.TextColored(ctx, COL_BAD, tostring(n))
    end

    -- #
    ImGui.TableNextColumn(ctx)
    ImGui.Text(ctx, tostring(shown))

    -- Check (+ issue table when open)
    ImGui.TableNextColumn(ctx)
    local open = false
    local hist = history_of(d)
    if (n and n > 0) or #hist > 0 then
      local todo = 0
      for _, e in ipairs(hist) do if e.copies and not e.reviewed then todo = todo + 1 end end
      local tag = #hist > 0 and (todo > 0 and string.format("   (%d done, %d to review)", #hist, todo) or string.format("   (%d done)", #hist)) or ""
      if todo > 0 then ImGui.SetNextItemOpen(ctx, true) -- something to review: the list stays open
      elseif state.open_all ~= nil then ImGui.SetNextItemOpen(ctx, state.open_all)
      elseif state.force_open[d.id] then ImGui.SetNextItemOpen(ctx, true) end
      state.force_open[d.id] = nil
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, LEVEL_COL[d.level] or COL_GREY)
      open = ImGui.TreeNode(ctx, d.short .. "###tree")
      ImGui.PopStyleColor(ctx)
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, d.title .. "\nFix: " .. d.fix_note) end
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, COL_INFO, d.desc .. tag)
      if todo > 0 and state.scroll_to_review then ImGui.SetScrollHereY(ctx, 0.1); state.scroll_to_review = nil end
    else
      ImGui.Indent(ctx, ImGui.GetTreeNodeToLabelSpacing(ctx)) -- line up with the titles that have an arrow
      ImGui.TextColored(ctx, LEVEL_COL[d.level] or COL_GREY, d.short)
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, d.title .. "\nFix: " .. d.fix_note) end
      ImGui.SameLine(ctx)
      ImGui.TextColored(ctx, COL_INFO, d.desc)
      ImGui.Unindent(ctx, ImGui.GetTreeNodeToLabelSpacing(ctx))
    end

    if open then
      ImGui.TableNextRow(ctx)
      -- Actions for the issues selected in the open list (the buttons above always act on all)
      ImGui.TableNextColumn(ctx)
      local can_fix = d.fix ~= nil or d.instructions ~= nil
      ImGui.BeginDisabled(ctx, nsel == 0)
      ImGui.BeginDisabled(ctx, not can_fix)
      if ImGui.Button(ctx, string.format("Fix selected (%d)##fixsel", nsel)) then run_fix(d, true) end
      ImGui.EndDisabled(ctx)
      ImGui.BeginDisabled(ctx, d.scope == "track")
      if ImGui.Button(ctx, string.format("Mark selected (%d)##marksel", nsel)) then
        local added = CORE.mark_issues((target_issues(d, true)), d)
        state.status = string.format("%s: %d take marker%s added (selected only).", d.title, added, added == 1 and "" or "s")
        keep_scan_fresh()
      end
      ImGui.EndDisabled(ctx)
      if nsel > 0 and ImGui.Button(ctx, "Clear selection##clr") then state.sel[d.id] = {} end
      ImGui.EndDisabled(ctx)
      if nsel == 0 then ImGui.TextDisabled(ctx, "Click / Cmd / Shift\nin the list") end
      ImGui.TableNextColumn(ctx) -- Issues
      ImGui.TableNextColumn(ctx) -- #
      ImGui.TableNextColumn(ctx) -- Check: the issue list
      if list and #list > 0 then draw_issue_table(d, list) end
      if #hist > 0 then draw_history_table(d, hist) end
      ImGui.TreePop(ctx)
    end
    ImGui.PopID(ctx)
    ::next_rule::
  end
  state.open_all = nil
  state.scroll_to_review = nil -- one-shot, even when no list has anything to review (e.g. after a restart)
  ImGui.EndTable(ctx)
end

local FONT_SIZES = { 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0 }

local function draw_settings_popup()
  if not ImGui.BeginPopup(ctx, "settings") then return end
  local rv, v = ImGui.MenuItem(ctx, "Allow docking", nil, prefs.allow_docking, true)
  if rv then prefs.allow_docking = v; save_prefs() end
  local rz, vz = ImGui.MenuItem(ctx, "Zoom to the clicked spot", nil, prefs.auto_zoom, true)
  if rz then prefs.auto_zoom = vz; save_prefs() end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Clicking a list entry zooms there: the highlighted range about 2/3 of the width,\n"
      .. "its tracks in the middle with about two more tracks above and below.\nOff: only scroll, keep the zoom.")
  end
  local rk, vk = ImGui.MenuItem(ctx, "Keep deleted items for review (<track> before / removed)", nil, prefs.keep_removed, true)
  if rk then prefs.keep_removed = vk; save_prefs() end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "When a fix deletes an item: the items around it are copied as they were to \"<track> before\",\n"
      .. "the deleted item to \"<track> removed\" (muted). Press Reviewed in the list to remove the copies.")
  end
  if ImGui.BeginMenu(ctx, "Font size") then
    for _, sc in ipairs(FONT_SIZES) do
      local label = string.format("%d%%", math.floor(sc * 100 + 0.5)) .. (sc == 1.0 and " (ImGui default)" or "")
      if ImGui.MenuItem(ctx, label, nil, math.abs(prefs.font_scale - sc) < 0.01, true) then
        prefs.font_scale = sc; save_prefs()
      end
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Fade shapes") then
    for _, f in ipairs({ { "Fade in", "fade_in_shape", "name" }, { "Fade out", "fade_out_shape", "name" }, { "Crossfade", "xfade_shape", "xname" } }) do
      local cur = CORE.FADE_SHAPES[prefs[f[2]]] or CORE.FADE_SHAPES[1]
      if ImGui.BeginMenu(ctx, f[1] .. ": " .. cur[f[3]]) then
        for k, sh in ipairs(CORE.FADE_SHAPES) do
          if ImGui.MenuItem(ctx, sh[f[3]] .. "##" .. f[2] .. k, nil, prefs[f[2]] == k, true) then
            prefs[f[2]] = k; save_prefs()
            if state.results then do_scan() end
          end
        end
        ImGui.EndMenu(ctx)
      end
    end
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "Fix runs REAPER's own \"Item: Set ... shape to ...\" actions")
    if ImGui.MenuItem(ctx, "Re-read fade shapes from REAPER", nil, false, true) then
      CORE.reset_fade_shapes()
      if state.results then do_scan() end
      state.status = "Fade shapes will be read again from REAPER's actions" .. (state.results and " (rescanned)." or " at the next scan.")
    end
    ImGui.EndMenu(ctx)
  end
  if ImGui.BeginMenu(ctx, "Track number format") then
    for _, w in ipairs({ 1, 2, 3 }) do
      local sample = {}
      for k = 1, 3 do sample[#sample + 1] = string.format("%0" .. w .. "d", k) end
      if ImGui.MenuItem(ctx, table.concat(sample, " "), nil, prefs.number_width == w, true) then
        prefs.number_width = w; save_prefs()
        if state.results then do_scan() end
      end
    end
    ImGui.EndMenu(ctx)
  end
  ImGui.EndPopup(ctx)
end

-- Review copies waiting in the project (counted from the project itself, so it also works after
-- the window was closed); refreshed when the project changes
local review_cache = { change = -1, st = nil }
local function review_status()
  local cc = r.GetProjectStateChangeCount(0)
  if review_cache.change ~= cc or review_cache.key ~= project_key() then
    review_cache.st, review_cache.change, review_cache.key = CORE.review_status(), cc, project_key()
  end
  return review_cache.st
end

local function pending_history()
  local out = {}
  for _, d in ipairs(CORE.RULES) do
    for _, e in ipairs(history_of(d)) do if e.copies and not e.reviewed then out[#out + 1] = e end end
  end
  return out
end

local function draw_review_banner()
  local st = review_status()
  if st.items == 0 then return end
  local parts = {}
  for _, k in ipairs({ "before", "removed", "original" }) do
    if st.kinds[k] then parts[#parts + 1] = st.kinds[k] .. " " .. k end
  end
  ImGui.TextColored(ctx, COL_YEL, string.format("To review: %d cop%s on %d review track%s (%s). They would go to Interchanger too.",
    st.items, st.items == 1 and "y" or "ies", st.tracks, st.tracks == 1 and "" or "s", table.concat(parts, ", ")))
  ImGui.PushID(ctx, "review")
  if ImGui.Button(ctx, "Open lists to review") then
    -- the checks with entries to review are always open; jump to the first copy waiting
    local nxt = st.list[1]
    for _, e in ipairs(pending_history()) do
      for _, c in ipairs(e.copies or {}) do if r.ValidatePtr2(0, c, "MediaItem*") then nxt = c break end end
      if nxt ~= st.list[1] then break end
    end
    state.scroll_to_review = true
    if nxt then
      CORE.select_issues({ { item = nxt } })
      CORE.highlight_issues({ { item = nxt } })
      CORE.reveal({ item = nxt })
      state.status = "Review copy on \"" .. CORE.track_name(r.GetMediaItem_Track(nxt)) .. "\". Press Reviewed in its check's list when it is fine."
    end
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Scroll the checklist to the lists with items to review (they stay open until reviewed)\n"
      .. "and jump to the first review copy in REAPER")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "All reviewed...") then
    if r.MB(string.format("Mark all %d review copies (%s) as reviewed?\n\n"
      .. "- Copies of deleted items (<track> before / removed) are removed with their tracks.\n"
      .. "- Originals of printed items stay on \"<track> original\".\n\n"
      .. "Only do this when you have checked them. The lists keep what was done.",
      st.items, table.concat(parts, ", ")), TITLE, 1) == 1 then
      r.Undo_BeginBlock(); r.PreventUIRefresh(1)
      local del, keep = {}, {}
      for _, it in ipairs(st.list) do
        if CORE.copy_kind(it) == "original" then keep[#keep + 1] = it else del[#del + 1] = it end
      end
      local n = CORE.clear_review(del)
      local kept = CORE.mark_copies_reviewed(keep)
      for _, e in ipairs(pending_history()) do
        e.reviewed = true
        if e.kind ~= "printed" then e.copies = nil end
      end
      r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
      r.Undo_EndBlock("Session Fix: all reviewed", -1)
      keep_scan_fresh()
      state.status = string.format("All reviewed: %d review cop%s removed, %d original%s kept.", n, n == 1 and "y" or "ies", kept, kept == 1 and "" or "s")
    end
  end
  ImGui.PopID(ctx)
end

-- Media reminder (outside the project folder / not WAV / sample rate / missing): first thing to
-- sort out, with File > Save project as... + "Copy all media into project directory"
local function draw_media_banner()
  local d = CORE.rule_by_id("media")
  local list = state.results and state.results.media
  if not d or not list then return end
  if #list == 0 then
    ImGui.TextColored(ctx, COL_OK, "Media OK: every file is in the project folder, WAV, at the project sample rate.")
    return
  end
  local c = { outside = 0, format = 0, rate = 0, missing = 0 }
  for _, is in ipairs(list) do for k in pairs(is.kinds or {}) do c[k] = (c[k] or 0) + 1 end end
  local parts = {}
  if c.outside > 0 then parts[#parts + 1] = c.outside .. " outside the project folder" end
  if c.missing > 0 then parts[#parts + 1] = c.missing .. " missing" end
  if c.format > 0 then parts[#parts + 1] = c.format .. " not WAV" end
  if c.rate > 0 then parts[#parts + 1] = c.rate .. " at another sample rate" end
  ImGui.TextColored(ctx, COL_BAD, string.format("Media: %d file%s to sort out first - %s.", #list, #list == 1 and "" or "s", table.concat(parts, ", ")))
  ImGui.PushID(ctx, "media")
  if ImGui.Button(ctx, "Copy media into project...") then run_fix(d) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, d.fix_note) end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Select items") then CORE.select_issues(list); keep_scan_fresh() end
  ImGui.SameLine(ctx)
  if ImGui.TreeNode(ctx, "Files") then
    if ImGui.BeginChild(ctx, "medialist", 0, S(160)) then
      draw_issue_table(d, list)
      ImGui.EndChild(ctx)
    end
    ImGui.TreePop(ctx)
  end
  ImGui.PopID(ctx)
end

-- Top bar: stays in place, the checklist below scrolls
local function draw_top_bar()
  if ImGui.Button(ctx, "Save as Interchange copy...") then
    r.Main_OnCommand(40022, 0) -- File: Save project as...
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Fixes delete tracks and change items: work on a copy (e.g. name_IC.rpp), keep the original untouched.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Scan") then do_scan() end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, state.results == nil)
  if ImGui.Button(ctx, "Fix All") then run_fix_all() end
  ImGui.EndDisabled(ctx)
  if ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_AllowWhenDisabled) then
    ImGui.SetTooltip(ctx, "Run every automatic fix in order (one confirmation). Stops at the first fix that moves audio, a crossfade or a track.")
  end
  ImGui.SameLine(ctx)
  local rvk, keep = ImGui.Checkbox(ctx, "Keep Folder", prefs.keep_folders)
  if rvk then prefs.keep_folders = keep; save_prefs(); if state.results then do_scan() end end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "On: folders are kept (only expanded). Off: folders are flattened, children kept.") end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Settings") then ImGui.OpenPopup(ctx, "settings") end
  draw_settings_popup()
  ImGui.SameLine(ctx)
  -- one button: "Set start" until there is a start point for this project, then "Verify vs. start"
  local has_start = state.baseline ~= nil and state.baseline_proj == project_key()
  if has_start then
    if ImGui.Button(ctx, "Verify vs. start (" .. state.baseline.time .. ")###verify") then verify_vs_start() end
  elseif ImGui.Button(ctx, "Set start###verify") then
    set_start()
  end
  if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) then ImGui.OpenPopup(ctx, "startmenu") end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, has_start and "Compare the whole session with the start point: audio position in every item, crossfades, tracks.\nRight-click: set a new start point."
      or "Remember the session as it is now, to verify all fixes against it later.")
  end
  if ImGui.BeginPopup(ctx, "startmenu") then
    if ImGui.MenuItem(ctx, "Set new start point (now)", nil, false, true) then set_start() end
    ImGui.EndPopup(ctx)
  end
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, state.results == nil)
  if ImGui.Button(ctx, "Save report") then save_report() end

  ImGui.EndDisabled(ctx)
  if state.results and r.GetProjectStateChangeCount(0) ~= state.scanned_change then
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, COL_BAD, "Project changed since the scan - press Scan again")
  end
  ImGui.TextColored(ctx, COL_INFO, state.status)
  if state.summary then
    ImGui.TextColored(ctx, COL_INFO, string.format("Frame rate %.3f fps, project %d Hz. Hover a check to see how it will be fixed.",
      state.summary.fps, state.summary.sr))
  end
  draw_media_banner()
  draw_review_banner()
  ImGui.Separator(ctx)
end

local function loop()
  ImGui.SetNextWindowSize(ctx, S(860), S(600), ImGui.Cond_FirstUseEver)
  local wflags = prefs.allow_docking and 0 or ImGui.WindowFlags_NoDocking
  local visible, open = ImGui.Begin(ctx, TITLE .. "  v" .. VERSION .. "###sessionfixprep", true, wflags)
  if visible then
    ImGui.PushFont(ctx, nil, math.floor(FONT_BASE * prefs.font_scale + 0.5))
    draw_top_bar()
    draw_audit()
    draw_rules()
    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end
  if open then r.defer(loop) end
end

CORE.auto_zoom = prefs.auto_zoom
set_start() -- the session as it was when the script opened
state.status = "Press Scan to check the session. Start point for Verify: " .. state.baseline.time .. " (script opened)."
r.defer(loop)
