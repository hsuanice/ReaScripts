--[[
@description Hush Pro Monitor - wait for Hush Pro Split output after Spot to Pro Tools and import it
@version 26.1018.2043
@author hsuanice
@noindex  (kept in the repository as a backup; local REAPER <> Pro Tools tools, not offered on ReaPack)
@about
  Opened automatically by "hsuanice_Reaper Spot to Pro Tools.lua" after a spot (can also be run
  by hand). A small window watches the Hush Pro output folder for the items that were spotted
  (read from the spot manifest, "_ptsync_manifest.json" in the project media folder):

    <item>
      Dialog  ready / writing / waiting
      Reverb  ...
      Noise   ...
    [ Import now ]  [ Cancel ]

  A group is imported as soon as dup1 / dup2 / dup3 are all complete (WAV header consistent
  with the file size, size unchanged for 3 seconds): files moved into the project media folder,
  placed on tracks "Dialog" / "Reverb" / "Noise" below the source item's track at their
  timecode, and Hush Pro's copy of the original goes to the Trash when its audio matches the
  spotted file. The window closes by itself when every spotted item is done.

  Import now: import what is complete right away (no 3-second wait). Cancel / Esc / closing the
  window: stop watching, nothing changes. A new spot while the window is open adds its items to
  the same window. No message box unless something needs attention (details in the console).
  The window remembers its position. Uses "hsuanice_Reaper Hush Pro Import Core.lua".

  Written with Claude Code (AI); designed and tested by hsuanice.
--]]

local r = reaper
local TITLE = "Hush Pro Monitor"
local NS = "hsuanice_HushProMonitor"          -- ExtState: heartbeat + window position
local STABLE_SEC = 3                           -- size unchanged this long = render finished
local POLL_SEC = 0.5
local DIR = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or ""
local C = dofile(DIR .. "hsuanice_Reaper Hush Pro Import Core.lua")
local function msg(s) r.ShowConsoleMsg(tostring(s) .. "\n") end

local dest = r.GetProjectPath("")
local _, proj_file = r.EnumProjects(-1, "")
if not proj_file or proj_file == "" or dest == "" then
  r.MB("Please save the project first: the files are moved into its media folder.", TITLE, 0)
  return
end

------------------------------------------------------------------------------
-- What to wait for: the items of the spot manifest (re-read, so a new spot adds items)
------------------------------------------------------------------------------
local MANIFEST = C.join(dest, "_ptsync_manifest.json")
local rows, by_stem = {}, {}          -- row = { stem, label, files = { [n] = { name, size, since, ok } }, done }
local manifest_text = nil
local report, warnings = {}, {}

local function read_manifest()
  local f = io.open(MANIFEST, "rb")
  if not f then return end
  local text = f:read("a")
  f:close()
  if text == manifest_text then return end
  manifest_text = text
  for raw in text:gmatch('"source_path"%s*:%s*"(.-[^\\])"') do
    local path = raw:gsub('\\/', '/'):gsub('\\"', '"'):gsub('\\\\', '\\')
    local stem = C.stem_of(C.basename(path))
    if not by_stem[stem] then
      local label = stem:gsub("__pt%d+$", "")
      local row = { stem = stem, label = label, files = {}, done = false }
      rows[#rows + 1] = row
      by_stem[stem] = row
    end
  end
end

------------------------------------------------------------------------------
-- File states
------------------------------------------------------------------------------
local function poll_files()
  r.EnumerateFiles(C.HUSH_DIR, -1) -- re-read the folder (REAPER caches listings)
  local files = C.list_files(C.HUSH_DIR)
  local now = r.time_precise()
  for _, name in ipairs(files) do
    local stem, n = C.split_name(name)
    local row = stem and by_stem[stem]
    if row and not row.done and n and C.DUP_TRACKS[n] then
      local st = row.files[n]
      if not st or st.name ~= name then st = { name = name }; row.files[n] = st end
      local size, complete = C.file_state(C.join(C.HUSH_DIR, name))
      if size ~= st.size or not complete then st.size, st.since = size, now end
      st.complete = complete
      st.ok = complete and (now - st.since) >= STABLE_SEC
    end
  end
  return files
end

local function import_row(row, files, force)
  local names = {}
  local n_ok = 0
  for n, st in pairs(row.files) do
    if st.ok or (force and st.complete) then names[n] = st.name; n_ok = n_ok + 1 end
  end
  if n_ok == 0 then return false end
  local rep, warn = C.import_group(row.stem, names, dest)
  for _, l in ipairs(rep) do report[#report + 1] = l end
  for _, w in ipairs(warn) do warnings[#warnings + 1] = w end
  for k = 1, 3 do
    if not names[k] then warnings[#warnings + 1] = string.format("%s: %s not imported (%s)", row.label, C.DUP_TRACKS[k],
      row.files[k] and "still being written" or "not found") end
  end
  -- Hush Pro's copy of this item's original: Trash when the audio matches the spotted file
  local originals = {}
  for _, name in ipairs(files) do if C.is_original_copy(name) then originals[#originals + 1] = name end end
  local rep2, warn2 = C.handle_originals(originals, { row.stem }, dest, false)
  for _, l in ipairs(rep2) do report[#report + 1] = l end
  for _, w in ipairs(warn2) do warnings[#warnings + 1] = w end
  row.done = true
  return true
end

------------------------------------------------------------------------------
-- Window (native gfx)
------------------------------------------------------------------------------
local start = r.time_precise()
local last_poll, last_manifest = 0, 0
local mouse_down = false
local buttons = {}

local function save_position()
  local _, x, y = gfx.dock(-1, 0, 0, 0, 0)
  r.SetExtState(NS, "x", tostring(math.floor(x)), true)
  r.SetExtState(NS, "y", tostring(math.floor(y)), true)
end

local function finish(cancelled)
  save_position()
  gfx.quit()
  r.DeleteExtState(NS, "alive", false)
  if #report + #warnings > 0 then
    msg("=== " .. TITLE .. " ===")
    for _, l in ipairs(report) do msg("  " .. l) end
    for _, w in ipairs(warnings) do msg("  ! " .. w) end
  end
  if #warnings > 0 then
    r.MB(string.format("%d warning%s while importing Hush Pro files - see the console.", #warnings, #warnings == 1 and "" or "s"), TITLE, 0)
  elseif cancelled then
    msg(TITLE .. ": cancelled.")
  end
end

local function button(id, label, x, y, w, h)
  gfx.set(0.25, 0.32, 0.45, 1); gfx.rect(x, y, w, h, 1)
  gfx.set(1, 1, 1, 1)
  local tw, th = gfx.measurestr(label)
  gfx.x, gfx.y = x + (w - tw) / 2, y + (h - th) / 2
  gfx.drawstr(label)
  buttons[id] = { x = x, y = y, w = w, h = h }
end

local function clicked()
  local down = (gfx.mouse_cap & 1) == 1
  local hit = nil
  if down and not mouse_down then
    for id, b in pairs(buttons) do
      if gfx.mouse_x >= b.x and gfx.mouse_x <= b.x + b.w and gfx.mouse_y >= b.y and gfx.mouse_y <= b.y + b.h then hit = id end
    end
  end
  mouse_down = down
  return hit
end

local function draw()
  local s = gfx.ext_retina or 1
  gfx.set(0.13, 0.13, 0.14, 1); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  gfx.setfont(1, "Arial", 15 * s)
  local lh = gfx.texth + 4 * s
  local x, y = 12 * s, 10 * s
  local t = math.floor(r.time_precise() - start)
  gfx.set(1, 1, 1, 1); gfx.x, gfx.y = x, y
  gfx.drawstr(string.format("Waiting for Hush Pro  (%02d:%02d)", t // 60, t % 60))
  y = y + lh * 1.4
  if #rows == 0 then
    gfx.set(0.7, 0.7, 0.7, 1); gfx.x, gfx.y = x, y
    gfx.drawstr("No spotted items found in the manifest.")
    y = y + lh
  end
  for _, row in ipairs(rows) do
    gfx.set(row.done and 0.5 or 0.95, row.done and 0.85 or 0.95, row.done and 0.5 or 0.95, 1)
    gfx.x, gfx.y = x, y
    gfx.drawstr((row.done and "imported  " or "") .. row.label)
    y = y + lh
    if not row.done then
      for k = 1, 3 do
        local st = row.files[k]
        local state, cr, cg, cb = "waiting", 0.6, 0.6, 0.6
        if st and st.ok then state, cr, cg, cb = "ready", 0.5, 0.85, 0.5
        elseif st then state, cr, cg, cb = "writing", 0.95, 0.8, 0.3 end
        gfx.set(cr, cg, cb, 1)
        gfx.x, gfx.y = x + 18 * s, y
        gfx.drawstr(string.format("%-7s %s", C.DUP_TRACKS[k], state))
        y = y + lh
      end
    end
  end
  y = y + lh * 0.5
  local bw, bh = 110 * s, 26 * s
  button("import", "Import now", x, y, bw, bh)
  button("cancel", "Cancel", x + bw + 10 * s, y, bw, bh)
  return y + bh + 10 * s
end

local function loop()
  local now = r.time_precise()
  r.SetExtState(NS, "alive", tostring(now), false) -- heartbeat: Spot to Pro Tools sees the window is open
  if now - last_manifest > 2 then read_manifest(); last_manifest = now end
  local files
  if now - last_poll > POLL_SEC then
    files = poll_files()
    last_poll = now
    for _, row in ipairs(rows) do
      if not row.done then
        local all = row.files[1] and row.files[2] and row.files[3]
        if all and row.files[1].ok and row.files[2].ok and row.files[3].ok then import_row(row, files, false) end
      end
    end
  end
  local need_h = draw()
  local sc = gfx.ext_retina or 1 -- gfx.w / gfx.h are in pixels, gfx.init takes points
  if math.abs(need_h - gfx.h) > 2 * sc then gfx.init("", gfx.w / sc, need_h / sc) end
  local hit = clicked()
  local ch = gfx.getchar()
  if hit == "cancel" or ch == 27 or ch < 0 then finish(true) return end
  if hit == "import" then
    files = poll_files()
    local any = false
    for _, row in ipairs(rows) do if not row.done and import_row(row, files, true) then any = true end end
    if not any then msg(TITLE .. ": nothing complete to import yet.") end
  end
  local open = false
  for _, row in ipairs(rows) do if not row.done then open = true end end
  if #rows > 0 and not open then finish(false) return end
  gfx.update()
  r.defer(loop)
end

read_manifest()
gfx.ext_retina = 1
local wx, wy = tonumber(r.GetExtState(NS, "x")), tonumber(r.GetExtState(NS, "y"))
gfx.init(TITLE, 420, 160, 0, wx or 200, wy or 200)
r.atexit(function() r.DeleteExtState(NS, "alive", false) end)
loop()
