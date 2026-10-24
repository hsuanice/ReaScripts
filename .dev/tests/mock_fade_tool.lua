-- @noindex  (local test for the Fade Tool scripts and Library/hsuanice_Fade Tool Core.lua; not a ReaPack package)
-- Minimal mock of the REAPER API: tracks, items, razor, time selection, mouse, Hover Mode,
-- held keys (JS_VKeys) and Snap. Each test builds its own small project and runs a script.
-- usage (repo root): lua .dev/tests/mock_fade_tool.lua
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/%.dev/tests/") or "."
local ROOT = REPO .. "/../.."           -- REAPER resource path (the repo is Scripts/hsuanice Scripts)
local DIR = REPO .. "/Items Editing/"
local FPS = 24
local fl = 1 / FPS

-- project state -----------------------------------------------------------
local tracks, ext, mb
local mouse, cursor, ts, VIEW, SNAP, CMD = nil, 0, { 0, 0 }, { 0, 60 }, false, false
local TIME, FRAME, MY = 0, 0, 500
local actions, undo_desc, atexit_fn = {}, nil, nil

local function reset()
  tracks, ext, mb = {}, {}, nil
  mouse, cursor, ts, VIEW, SNAP, CMD = nil, 0, { 0, 0 }, { 0, 60 }, false, false
  actions, undo_desc, atexit_fn = {}, nil, nil
end
local function new_track(name, razor)
  local tr = { name = name, items = {}, razor = razor or "", sel = false }
  tracks[#tracks + 1] = tr
  return tr
end
-- item at pos/len whose source starts at src_start on the timeline and lasts src_len
local function new_item(tr, pos, len, src_start, src_len)
  local take = { offs = pos - src_start, rate = 1, src = { len = src_len } }
  local it = { tr = tr, take = take, v = { D_POSITION = pos, D_LENGTH = len, C_LOCK = 0, B_LOOPSRC = 0,
    D_FADEINLEN = 0, D_FADEOUTLEN = 0, D_FADEINLEN_AUTO = 0, D_FADEOUTLEN_AUTO = 0,
    C_FADEINSHAPE = 0, C_FADEOUTSHAPE = 0, D_FADEINDIR = 0, D_FADEOUTDIR = 0,
    F_FREEMODE_Y = 0, F_FREEMODE_H = 1, I_FIXEDLANE = 0, I_LASTH = 40 } }
  tr.items[#tr.items + 1] = it
  return it
end
local function all_items() local o = {}; for _, t in ipairs(tracks) do for _, i in ipairs(t.items) do o[#o + 1] = i end end; return o end

reaper = {
  GetResourcePath = function() return ROOT end,
  file_exists = function() return true end,
  TimeMap_curFrameRate = function() return FPS end,
  GetProjectTimeOffset = function() return 0 end,
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i + 1] end,
  GetSetMediaTrackInfo_String = function(tr, k, v, set)
    if set then tr.razor = v; return true, v end
    if k == "P_RAZOREDITS_EXT" then return true, tr.razor end
    return true, ""
  end,
  GetMediaTrackInfo_Value = function(tr, k) return (tr.v and tr.v[k]) or 0 end,
  GetTakeName = function(t) return t.name or "" end,
  IsTrackVisible = function(tr) return not tr.hidden end,
  CountTrackMediaItems = function(tr) return #tr.items end,
  GetTrackMediaItem = function(tr, i) return tr.items[i + 1] end,
  GetMediaItem_Track = function(it) return it.tr end,
  GetMediaItemInfo_Value = function(it, k) return it.v[k] end,
  SetMediaItemInfo_Value = function(it, k, v) it.v[k] = v end,
  GetActiveTake = function(it) return it.take end,
  CountTakes = function() return 1 end,
  GetTake = function(it) return it.take end,
  TakeIsMIDI = function() return false end,
  GetMediaItemTake_Source = function(t) return t.src end,
  GetMediaSourceLength = function(s) return s.len, false end,
  GetMediaItemTakeInfo_Value = function(t, k) return k == "D_PLAYRATE" and t.rate or t.offs end,
  SetMediaItemTakeInfo_Value = function(t, _, v) t.offs = v end,
  CountTakeEnvelopes = function() return 0 end,
  IsMediaItemSelected = function(it) return it.sel == true end,
  SetMediaItemSelected = function(it, on) it.sel = on end,
  SelectAllMediaItems = function(_, on) for _, i in ipairs(all_items()) do i.sel = on end end,
  CountSelectedMediaItems = function() local n = 0; for _, i in ipairs(all_items()) do if i.sel then n = n + 1 end end; return n end,
  GetSelectedMediaItem = function(_, k) local n = 0; for _, i in ipairs(all_items()) do if i.sel then if n == k then return i end; n = n + 1 end end end,
  CountSelectedTracks = function() local n = 0; for _, t in ipairs(tracks) do if t.sel then n = n + 1 end end; return n end,
  GetSelectedTrack = function(_, k) local n = 0; for _, t in ipairs(tracks) do if t.sel then if n == k then return t end; n = n + 1 end end end,
  GetTrackName = function(tr) return true, tr.name end,
  GetSet_ArrangeView2 = function() return VIEW[1], VIEW[2] end,
  GetSet_LoopTimeRange2 = function() return ts[1], ts[2] end,
  GetCursorPosition = function() return cursor end,
  GetHZoomLevel = function() return 100 end,
  GetToggleCommandState = function(id) return (id == 1157 and SNAP) and 1 or 0 end,
  SnapToGrid = function(_, t) if SNAP then return math.floor(t * FPS + 0.5) / FPS end return t end,
  BR_GetClosestGridDivision = function(t) return math.floor(t * FPS + 0.5) / FPS end,
  GetMousePosition = function() return 100, MY end,
  GetOS = function() return "macOS-arm64" end,
  -- mouse.part decides what the name-bar / half probes of mouse_item_part() see
  GetItemFromPoint = function(_, y)
    if not mouse then return nil end
    local off = MY - y
    if off == 0 then return mouse.item end
    if off == 39 then return (mouse.part == "label") and mouse.item or nil end
    if off == 20 then return (mouse.part ~= "bottom") and mouse.item or nil end
  end,
  BR_GetMouseCursorContext = function() return mouse and (mouse.window or "arrange") or "unknown" end,
  BR_GetMouseCursorContext_Position = function() return mouse and mouse.t end,
  BR_PositionAtMouseCursor = function() return mouse and mouse.t or -1 end,
  JS_Mouse_GetState = function() return CMD and 4 or 0 end,
  time_precise = function() return TIME end,
  atexit = function(f) atexit_fn = f end,
  Undo_OnStateChange = function(d) undo_desc = d end,
  format_timestr_pos = function(t) return string.format("%.4f", t) end,
  MB = function(m) mb = m end,
  GetExtState = function(_, k) return ext[k] or "" end,
  SetExtState = function(_, k, v) ext[k] = v end,
  HasExtState = function(_, k) return ext[k] ~= nil end,
  Main_OnCommand = function(id)
    actions[#actions + 1] = id
    for _, i in ipairs(all_items()) do
      if i.sel then
        if id == 41519 then i.v.C_FADEINSHAPE = 5 elseif id == 41526 then i.v.C_FADEOUTSHAPE = 5 end
      end
    end
  end,
  Undo_BeginBlock = function() end, Undo_EndBlock = function() end,
  PreventUIRefresh = function() end, UpdateArrange = function() end,
  defer = function() end,
}

-- helpers -------------------------------------------------------------------
local fails, passes = 0, 0
local function near(a, b) return math.abs(a - b) < 1e-6 end
local function check(name, cond)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL " .. name) end
end
local function S(it) return it.v.D_POSITION end
local function E(it) return it.v.D_POSITION + it.v.D_LENGTH end
local function run(name) dofile(DIR .. "hsuanice_Fade Tool - " .. name .. ".lua") end
local function SF() run("Smart Fade at Mouse or Edit Cursor") end
-- crossfade 10..11 between two items with long handles
local function xpair(name, hover)
  reset(); if hover then ext.HoverMode = "true" end
  local tr = new_track(name, "")
  local a = new_item(tr, 0, 11, -5, 40)
  local b = new_item(tr, 10, 10, 5, 40)
  a.v.D_FADEOUTLEN_AUTO, b.v.D_FADEINLEN_AUTO = 1, 1
  return a, b, tr
end
-- hold the shortcut for frames_down defer cycles while the mouse follows path
local function hold_run(frames_down, path, dt)
  local q, frame = {}, 0
  FRAME = 0
  reaper.defer = function(f) q[#q + 1] = f end
  local intercept = 0
  reaper.JS_VKeys_Intercept = function(_, v) intercept = intercept + v end
  reaper.JS_VKeys_GetState = function()
    local st = string.rep("\0", 255)
    if frame < frames_down then st = st:sub(1, 69) .. "\1" .. st:sub(71) end  -- key 'F'
    return st
  end
  undo_desc = nil
  mouse.t = path[1]
  SF()
  while #q > 0 do
    frame = frame + 1
    FRAME = frame
    TIME = TIME + (dt or 0.05)
    mouse.t = path[math.min(frame + 1, #path)]
    table.remove(q, 1)()
  end
  if atexit_fn then atexit_fn() end
  reaper.defer = function() end
  return intercept
end
local function no_hold() reaper.JS_VKeys_GetState, reaper.JS_VKeys_Intercept = nil, nil end

local A, B, C, D, t

-- Crossfade in Razor --------------------------------------------------------
reset()
t = new_track("T1", string.format('%.10f 10 ""', 10 - fl))
A = new_item(t, 0, 10, -5, 30); B = new_item(t, 10, 10, 5, 30)
run("Crossfade in Razor")
check("1 one cut: crossfade fills the razor", near(E(A), 10) and near(S(B), 10 - fl) and near(B.take.offs, 5 - fl))
check("1 Equal Power, razor cleared, no popup", A.v.C_FADEOUTSHAPE == 7 and B.v.C_FADEINSHAPE == 7 and t.razor == "" and mb == nil)

reset()
t = new_track("T2", '5 6 ""')
A = new_item(t, 0, 10, -5, 30); B = new_item(t, 10, 10, 5, 30)
run("Crossfade in Razor")
check("2 no cut: nearest cut pulled into the razor", near(E(A), 6) and near(S(B), 5))

reset()
t = new_track("T3", '5 25 ""')
A = new_item(t, 0, 10, -5, 40); B = new_item(t, 10, 10, 5, 40); C = new_item(t, 20, 10, 15, 40)
run("Crossfade in Razor")
check("3 several cuts: 1 frame before each", near(S(B), 10 - fl) and near(S(C), 20 - fl) and near(E(A), 10))

reset()
t = new_track("T4", string.format('%.10f 10 ""', 10 - fl))
A = new_item(t, 0, 10, -5, 30); B = new_item(t, 10, 10, 10, 30)
run("Crossfade in Razor")
check("4 no handle: skipped and listed", near(S(B), 10) and mb and mb:find("handle"))

reset()
t = new_track("T5", '14 16 ""')
A = new_item(t, 0, 10, -5, 40); B = new_item(t, 10, 10, 5, 40); C = new_item(t, 20, 10, 15, 40)
run("Crossfade in Razor")
check("5 two equally near cuts: reported, nothing moved", mb ~= nil and near(E(A), 10) and near(S(C), 20))

reset()
t = new_track("T6", '0 2 ""')
A = new_item(t, 0.5, 9.5, 0, 30)
run("Crossfade in Razor")
check("6 free item start: plain fade-in over the razor", near(A.v.D_FADEINLEN, 1.5) and near(S(A), 0.5))

-- gaps between two items (26.1024)
reset()
t = new_track("G1", '9.9 10.2 ""')
A = new_item(t, 0, 9.8, -5, 40); B = new_item(t, 10.3, 9.7, 5, 40)
run("Crossfade in Razor")
check("7 razor inside a gap: both items extended, crossfade = razor",
  near(E(A), 10.2) and near(S(B), 9.9) and near(A.v.D_FADEOUTLEN_AUTO, 0.3) and near(B.v.D_FADEINLEN_AUTO, 0.3))
reset()
t = new_track("G2", '9.5 10.5 ""')
A = new_item(t, 0, 9.9, -5, 40); B = new_item(t, 10.1, 9.9, 5, 40)
run("Crossfade in Razor")
check("8 razor over both gap edges: one crossfade, not two fades",
  near(E(A), 10.5) and near(S(B), 9.5) and near(B.v.D_FADEINLEN_AUTO, 1) and A.v.D_FADEOUTLEN_AUTO > 0)
reset()
t = new_track("G3", '10 11 ""')
A = new_item(t, 0, 5, -5, 40); B = new_item(t, 10, 10, 5, 40)
run("Crossfade in Razor")
check("9 razor over one edge only: plain fade-in, far item untouched",
  near(B.v.D_FADEINLEN, 1) and B.v.D_FADEINLEN_AUTO == 0 and near(E(A), 5))
reset()
t = new_track("G4", '9.9 10.2 ""')
A = new_item(t, 0, 9.8, 0, 9.8); B = new_item(t, 10.3, 9.7, 5, 40)
run("Crossfade in Razor")
check("10 gap but no handle: skipped and listed", near(E(A), 9.8) and near(S(B), 10.3) and mb ~= nil)
reset()
t = new_track("G5", '5 25 ""')
A = new_item(t, 0, 9.9, -5, 40); B = new_item(t, 10.1, 9.9, 5, 40); C = new_item(t, 20, 10, 15, 40)
run("Crossfade in Razor")
check("11 several cuts incl. a gap: default crossfade on each",
  near(E(A), 10) and near(S(B), 10 - fl) and near(S(C), 20 - fl))

-- visible area
reset()
t = new_track("V1", '5 15 ""')
A = new_item(t, 0, 10, -5, 40); B = new_item(t, 10, 10, 5, 40)
VIEW = { 0, 12 }
run("Crossfade in Razor")
check("12 razor clipped to the view", near(S(B), 5) and near(E(A), 12))
reset()
t = new_track("V2", '9 11 ""'); t.hidden = true
A = new_item(t, 0, 10, -5, 40); B = new_item(t, 10, 10, 5, 40)
run("Crossfade in Razor")
check("13 hidden track untouched", near(E(A), 10) and near(S(B), 10))

-- Scene Cut -----------------------------------------------------------------
reset()
t = new_track("RT", '3 20 ""')
local P1, P2, P3 = new_item(t, 0, 8, -10, 60), new_item(t, 8, 8, -2, 60), new_item(t, 16, 8, 6, 60)
run("Scene Cut to Razor")
check("14 scene: first / last items only, 1 frame fades",
  near(S(P1), 3 - fl) and near(P1.v.D_FADEINLEN, fl) and near(S(P2), 8) and near(E(P2), 16) and near(E(P3), 20) and near(P3.v.D_FADEOUTLEN, fl))
reset()
t = new_track("Dlg", '3 20 ""')
D = new_item(t, 5, 10, -10, 60)
ext.scene_in_align, ext.scene_in_frames, ext.scene_out_align, ext.scene_out_frames = "center", "2", "center", "2"
run("Scene Cut to Razor")
check("15 scene centered 2 frames", near(S(D), 3 - fl) and near(E(D), 20 + fl) and near(D.v.D_FADEINLEN, 2 * fl))

-- Settings / shapes -----------------------------------------------------------
reset()
ext.xfade_shape = "1"
t = new_track("T8", string.format('%.10f 10 ""', 10 - fl))
A = new_item(t, 0, 10, -5, 30); B = new_item(t, 10, 10, 5, 30)
run("Crossfade in Razor")
check("16 old shape list 1 -> Equal Power 7", A.v.C_FADEOUTSHAPE == 7)
reset()
ext.scene_shape, ext.shape_list = "5", "2"
t = new_track("T9", '3 20 ""')
D = new_item(t, 5, 10, -10, 60)
local other = new_item(t, 40, 5, 0, 60); other.sel = true
run("Scene Cut to Razor")
check("17 Slight S-Curve via native actions, selection kept", D.v.C_FADEINSHAPE == 5 and #actions == 2 and other.sel and not D.sel)

-- Smart Fade: taps --------------------------------------------------------------
no_hold()
reset(); ext.HoverMode = "true"
t = new_track("H", "")
A = new_item(t, 0, 10, -5, 30)
mouse = { item = A, part = "top", t = 3 }; SF()
mouse = { item = A, part = "bottom", t = 7 }; SF()
check("18 hover top = fade-in, bottom = fade-out", near(A.v.D_FADEINLEN, 3) and near(A.v.D_FADEOUTLEN, 3))

A, B = xpair("X", true)
mouse = { item = B, part = "top", t = 12 }; SF()
check("19 tap on a crossfaded edge: nothing changes", near(E(A), 11) and near(S(B), 10) and B.v.D_FADEINLEN == 0)
A, B = xpair("X2", true)
mouse = { item = A, part = "top", t = 10.5 }; SF()
check("20 tap inside a crossfade: nothing changes", near(E(A), 11) and near(S(B), 10) and A.v.D_FADEINLEN == 0 and mb == nil)

A, B = xpair("L", true)
A.v.C_FADEOUTSHAPE, B.v.C_FADEINSHAPE = 3, 3
mouse = { item = B, part = "label", t = 12 }; SF()
check("21 name bar: crossfade centered on the mouse, length + shape kept",
  near(E(A), 12.5) and near(S(B), 11.5) and near(B.v.D_FADEINLEN_AUTO, 1) and B.v.C_FADEINSHAPE == 3)

reset()
t = new_track("C", ""); t.sel = true
A = new_item(t, 0, 10, -5, 30)
cursor = 8; SF()
check("22 edit cursor, no mouse side: nearer edge -> fade-out", near(A.v.D_FADEOUTLEN, 2) and A.v.D_FADEINLEN == 0)
reset()
t = new_track("M", ""); t.sel = true
A = new_item(t, 0, 10, -5, 30)
cursor = 8; mouse = { t = 6 }; SF()
check("23 mouse left of the cursor = fade-in", near(A.v.D_FADEINLEN, 8) and A.v.D_FADEOUTLEN == 0)
reset()
t = new_track("M2", ""); t.sel = true
A = new_item(t, 0, 10, -5, 30)
cursor = 2; mouse = { t = 5 }; SF()
check("24 mouse right of the cursor = fade-out", near(A.v.D_FADEOUTLEN, 8))
A, B = xpair("M4")
cursor = 12; mouse = { item = B, part = "label", t = 15 }; SF()
check("25 hover off, name bar: crossfade centered on the cursor", near(S(B), 11.5) and near(E(A), 12.5))
reset()
t = new_track("V3", ""); t.sel = true
A = new_item(t, 0, 100, -5, 400)
cursor = 80; SF()
check("26 edit cursor outside the view: nothing", A.v.D_FADEINLEN == 0 and A.v.D_FADEOUTLEN == 0)

reset()
t = new_track("TS", ""); t.sel = true
A = new_item(t, 0, 10, -5, 40); B = new_item(t, 10, 10, 5, 40)
ts = { 9, 11 }; SF()
check("27 time selection + selected track", near(E(A), 11) and near(S(B), 9))
reset()
t = new_track("P", '9.5 10.5 ""'); t.sel = true
A = new_item(t, 0, 10, -5, 40); B = new_item(t, 10, 10, 5, 40)
ts = { 5, 15 }; SF()
check("28 razor wins over time selection", near(E(A), 10.5) and near(S(B), 9.5))
reset()
t = new_track("GS", '9.9 10.2 ""')
A = new_item(t, 0, 9.8, -5, 40); B = new_item(t, 10.3, 9.7, 5, 40)
SF()
check("29 Smart Fade razor in a gap: crossfade", near(E(A), 10.2) and near(S(B), 9.9))

reset(); ext.HoverMode = "true"
local t1, t2 = new_track("S1", ""), new_track("S2", "")
A = new_item(t1, 0, 10, -5, 30); A.sel = true
B = new_item(t2, 1, 10, -5, 30); B.sel = true
C = new_item(t2, 30, 5, 0, 30); C.sel = true
mouse = { item = A, part = "top", t = 4 }; SF()
check("30 hover on a selected item: all selected items under the mouse", near(A.v.D_FADEINLEN, 4) and near(B.v.D_FADEINLEN, 3) and C.v.D_FADEINLEN == 0)

-- Smart Fade: hold and drag ---------------------------------------------------------
local released
A, B = xpair("D1"); mouse = { item = B, part = "top" }
released = hold_run(3, { 10.02, 10.2, 10.6, 10.6 })
check("31 drag the start edge", near(S(B), 10.6) and near(E(A), 11) and undo_desc ~= nil and released == 0)
A, B = xpair("D2"); mouse = { item = A, part = "bottom" }
hold_run(3, { 10.98, 11.5, 12.4, 12.4 })
check("32 drag the end edge", near(E(A), 12.4) and near(S(B), 10))
A, B = xpair("D3"); mouse = { item = B, part = "label" }
hold_run(3, { 10.5, 12, 14.5, 14.5 })
check("33 drag the whole crossfade from the name bar", near(S(B), 14) and near(E(A), 15))
A, B = xpair("D4"); mouse = { item = B, part = "top" }
hold_run(3, { 10.02, 10.5, 13, 13 })
check("34 edges stop 1 frame apart", near(S(B), 11 - fl))
A, B = xpair("D5", true); mouse = { item = B, part = "label" }
hold_run(0, { 12 })
check("35 short press = tap", near(S(B), 11.5) and undo_desc == nil)

SNAP = true
A, B = xpair("K1"); SNAP = true; mouse = { item = B, part = "top" }
hold_run(3, { 10.02, 10.3, 10.53, 10.53 })
check("36 snap on: frame grid", near(S(B), 253 / FPS))
local function cmd_frames(from, to)
  reaper.JS_Mouse_GetState = function() return (FRAME >= from and FRAME <= to) and 4 or 0 end
end
A, B = xpair("K2"); SNAP = true; mouse = { item = B, part = "top" }
cmd_frames(1, 99); hold_run(4, { 10.02, 10.53, 10.53, 10.53, 10.53 })
check("37 snap on + Cmd: free, kept when the shortcut is released first", near(S(B), 10.53))
A, B = xpair("K3"); SNAP = true; mouse = { item = B, part = "top" }
cmd_frames(1, 3); hold_run(5, { 10.02, 10.53, 10.53, 10.53, 10.53, 10.53 })
check("38 Cmd released just before the shortcut: kept", near(S(B), 10.53))
A, B = xpair("K4"); SNAP = true; mouse = { item = B, part = "top" }
cmd_frames(1, 2); hold_run(8, { 10.02, 10.53, 10.53, 10.53, 10.53, 10.53, 10.53, 10.53, 10.53 }, 0.1)
check("39 dragging on after Cmd is released: snaps again", near(S(B), 253 / FPS))
A, B = xpair("K5"); SNAP = false; mouse = { item = B, part = "top" }
cmd_frames(1, 99); hold_run(4, { 10.02, 10.53, 10.53, 10.53, 10.53 })
check("40 snap off + Cmd: grid", near(S(B), 253 / FPS))

-- Scene Cut from the Scene Cut track (no razor, selected items) ---------------------
local function scene_project()
  reset()
  local sct = new_track("Scene Cut", ""); sct.v = { I_FOLDERDEPTH = 1 }
  local log = new_track("2026-10-20", ""); log.v = { I_FOLDERDEPTH = -1 }
  for i, r_ in ipairs({ { 0, 10, "80" }, { 10, 20, "81" }, { 20, 24, "33" }, { 24, 40, "82" } }) do
    local it = new_item(sct, r_[1], r_[2] - r_[1], r_[1], 100); it.take.name = r_[3]
  end
  local rt = new_track("RT", "")
  return sct, log, rt
end
local sct, log, rt, rt2
sct, log, rt = scene_project()
A = new_item(rt, 8, 6, -10, 100); A.sel = true          -- pieces covering scene 81 (10..20)
B = new_item(rt, 14, 4, -10, 100)                        -- middle piece, not selected
C = new_item(rt, 18, 4.5, -10, 100); C.sel = true
D = new_item(rt, 30, 5, -10, 100)                        -- other scene, untouched
run("Scene Cut to Razor")
check("41 selection covering scene 81: first / last selected trimmed to it",
  near(S(A), 10 - fl) and near(A.v.D_FADEINLEN, fl) and near(E(C), 20) and near(C.v.D_FADEOUTLEN, fl))
check("41 partly covered neighbours ignored, unselected items untouched",
  near(S(B), 14) and near(E(B), 18) and near(S(D), 30) and mb == nil)

sct, log, rt = scene_project()
A = new_item(rt, 12, 7, -10, 100); A.sel = true          -- inside 81, not covering it
run("Scene Cut to Razor")
check("42 only part of a scene: nothing, listed", near(S(A), 12) and mb and mb:find("whole scene"))

sct, log, rt = scene_project()
A = new_item(rt, 9, 16, -10, 100); A.sel = true          -- covers 81 and 33 completely
run("Scene Cut to Razor")
check("43 several whole scenes: nothing, listed with names", near(S(A), 9) and mb and mb:find("81, 33"))

sct, log, rt = scene_project()
rt.razor = '2 6 ""'
A = new_item(rt, 0, 9, -10, 100); A.sel = true
run("Scene Cut to Razor")
check("44 razor wins over the selection", near(S(A), 2 - fl) and near(E(A), 6))

sct, log, rt = scene_project()
rt2 = new_track("RT2", "")
A = new_item(rt, 9, 12, -10, 100); A.sel = true
B = new_item(rt2, 19.5, 5.5, 0, 100); B.sel = true      -- covers scene 33 (20..24) on its own track
sct.items[1].sel = true                                  -- a selected scene item itself
local L = new_item(log, 0, 5, 0, 5); L.sel = true        -- a work-log item in the folder
run("Scene Cut to Razor")
check("45 each track its own scene", near(S(A), 10 - fl) and near(E(A), 20) and near(S(B), 20 - fl) and near(E(B), 24))
check("45 Scene Cut track and its folder never cut", near(S(sct.items[1]), 0) and near(E(sct.items[1]), 10) and near(S(L), 0))

print(string.format("%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
