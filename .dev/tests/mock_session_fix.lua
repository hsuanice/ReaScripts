-- @noindex  (local test for Library/hsuanice_Session Fix Core.lua; not a ReaPack package)
-- Minimal mock of the REAPER API with a project that contains one example of every issue.
-- usage (repo root): lua .dev/tests/mock_session_fix.lua
local SR, FPS = 48000, 24
local proj_dir = "/proj/"
local function T(name, opts) opts = opts or {}; opts.name = name; opts.items = {}; opts.env = opts.env or {}; return opts end
local function SRC(file, typ, ch, len, sr) return { file = file, typ = typ or "WAVE", ch = ch or 1, len = len or 100, sr = sr or SR } end
local function TAKE(src, o) o = o or {}; o.src = src; o.vol = o.vol or 1; o.pan = o.pan or 0; o.rate = o.rate or 1; o.pitch = o.pitch or 0; o.offs = o.offs or 0; o.sm = o.sm or 0; o.fx = o.fx or 0; o.env = o.env or {}; o.mode = o.mode or 0; o.name = o.name or (src and src.file or ""); return o end
local function ITEM(tr, pos, len, takes, o) o = o or {}; local it = { vol = o.vol or 1, tr = tr, pos = pos, len = len, takes = takes or {}, fi = o.fi or 0, fo = o.fo or 0, fia = o.fia or -1, foa = o.foa or -1, loop = o.loop or 0, fis = o.fis or 0, fos = o.fos or 0, fid = o.fid or 0, fod = o.fod or 0 }; tr.items[#tr.items+1] = it; return it end
local f = 1/FPS
local wav = SRC(proj_dir.."a.wav"); local wav2 = SRC(proj_dir.."b.wav"); local st = SRC(proj_dir.."st.wav", "WAVE", 2)
local mp3 = SRC("/ext/m.mp3", "MP3"); local sr44 = SRC(proj_dir.."c44.wav","WAVE",1,100,44100); local vid = SRC("/ext/v.mov","VIDEO")
local master = T("MASTER", { env = { { name = "Volume", pts = 3, act = 1 } } })
local tracks = { T("Dial 1"), T("Folder", { depth = 1, compact = 2 }), T("Aux", { sends = 1, hidden = true }), T("Mix"), T("Fx", { depth = -1 }), T("Scene Cut"), T("Video"),
  T("Parent w/ items", { depth = 1 }), T("Child A", { depth = -1 }),
  T("Outer", { depth = 1 }), T("Empty inner", { depth = 1 }), T("DIA PAN 01"), T("DIA PAN 02", { depth = -1 }), T("DIA PAN 05", { depth = -1 }), T("PFX MN C"), T("PFX MN C"), T("PFX MN C"), T("Unique Name"), T("Audio 9_L", { v = { D_PAN = 0 } }), T("Audio 9_R", { v = { I_PANMODE = 6 } }), T("Lone_L", { v = { D_VOL = 2, B_PHASE = 1 } }), T("Dial 1 original") }
local d1, fold, aux, mix, fx, scene, video, pwi, childA, outer, inner, p1, p2, p5 = table.unpack(tracks)
mix.v = { D_VOL = 0.5, D_PAN = 0.25, D_WIDTH = 0.6, B_MUTE = 1 }                -- mix settings left on a track
d1.env = { { name = "Volume", pts = 4, act = 1 }, { name = "Pan", pts = 0, act = 0 } } -- 2nd = unused (inactive, empty)
ITEM(d1, 0, 10*f, { TAKE(wav) })                                        -- clean
ITEM(d1, 20*f, 10*f, { TAKE(wav), TAKE(wav2) })                         -- inactive takes
ITEM(d1, 40*f, 10*f, { TAKE(wav, { vol = 0.5 }) })                      -- take volume
ITEM(d1, 60*f, 10*f, { TAKE(wav, { pan = 0.3 }) })                      -- take pan
ITEM(d1, 80*f, 10*f, { TAKE(wav, { rate = 1.1, fx = 1 }) })             -- needs render
ITEM(d1, 100*f, 10*f, { TAKE(wav, { vol = -1 }) })                      -- polarity
ITEM(d1, 120*f, 10*f, { TAKE(wav, { env = { "Volume" } }) })            -- take envelope (constant -> merged)
ITEM(d1, 125*f, 3*f, { TAKE(wav2, { env = { "Volume*" } }) })           -- take envelope that changes -> print
ITEM(scene, 50*f + 0.003, 10*f, {}, { fi = 6*f, fo = 6*f })               -- empty item: off grid + triangle must be ignored
-- stacked crossfade with a 1.5-frame sliver in the middle (like the RGWH Monitor example)
ITEM(d1, 300*f, 7.5*f, { TAKE(wav) }, { fi = 1*f, fo = 1*f })
ITEM(d1, 306.5*f, 1.5*f, { TAKE(wav2, { offs = 3 }) }, { fi = 1*f, fo = 1*f })
ITEM(d1, 307*f, 20*f, { TAKE(wav, { offs = 5 }) }, { fi = 1*f })
ITEM(d1, 140*f, 10*f, { TAKE(wav) })                                    -- A of hidden duplicate
ITEM(d1, 142*f, 4*f, { TAKE(wav, { offs = 2*f }) })                     -- hidden duplicate (same audio)
ITEM(d1, 160*f, 10*f, { TAKE(wav) }, { fo = 2*f })                       -- crossfade A
ITEM(d1, 168*f, 10*f, { TAKE(wav2) }, { fi = 3*f })                      -- crossfade B misaligned
ITEM(d1, 200*f, 10*f, { TAKE(wav) }, { fi = 5*f, fo = 5*f })             -- triangle
ITEM(d1, 220*f, 10*f, { TAKE(SRC(proj_dir.."short.wav","WAVE",1,0.1)) }) -- past source end
ITEM(d1, 240*f + 0.003, 10*f, { TAKE(wav) })                             -- off grid start
local iso = ITEM(d1, 420*f + 1/SR, 10*f - 1/SR, { TAKE(SRC(proj_dir.."iso.wav","WAVE",8,10*f - 1/SR)) }) -- ISO: TimeReference 1 sample late, plays the whole file
ISO_ITEM = iso
ITEM(d1, 360*f, 10*f, { TAKE(wav, { mode = 2 }) })                          -- channel mode on a mono file: reset
ITEM(d1, 380*f, 10*f, { TAKE(st, { mode = 4 }) })                           -- right channel of a stereo file: print
ITEM(d1, 400*f, 10*f, { TAKE(wav, { mode = 7 }) })                          -- mono channel 5 of a mono file: review
ITEM(d1, 280*f, 10*f, { TAKE(wav) }, { fi = 2*f, fo = 2*f, fis = 3, fod = 0.4 })   -- non-standard fade shapes
ITEM(d1, 290*f, 4*f, { TAKE(wav) }, { foa = 1*f }); ITEM(d1, 293*f, 4*f, { TAKE(wav2) }, { fia = 1*f }) -- auto crossfade, linear
ITEM(d1, 260*f, 10*f, { TAKE(SRC(proj_dir.."s2.wav","WAVE",1,9.5*f)) }, { loop = 1, fi = 1.5*f, fo = 2*f }) -- 0.5 frame past the source: trimmed
ITEM(mix, 0, 10*f, { TAKE(wav) }); ITEM(mix, 20*f, 10*f, { TAKE(st) })    -- mixed channels
ITEM(mix, 40*f, 10*f, { TAKE(st) }); ITEM(mix, 60*f, 10*f, { TAKE(SRC(proj_dir.."six.wav","WAVE",6)) }) -- stereo is the biggest group
ITEM(mix, 80*f, 10*f, { TAKE(SRC(proj_dir.."six.wav","WAVE",6), { mode = 69 }) })  -- stereo pair 3-4 of a 6ch file = plays stereo
ITEM(fx, 0, 10*f, { TAKE(mp3) }); ITEM(fx, 20*f, 10*f, { TAKE(sr44) })   -- media
ITEM(scene, 0, 10*f, {})                                                 -- empty item
ITEM(video, 0, 10*f, { TAKE(vid) })                                      -- video (excluded from media)
ITEM(tracks[#tracks], 80*f, 10*f, { TAKE(wav, { rate = 1.1 }) }, {})    -- backup copy: must be ignored by every check
ITEM(pwi, 0, 10*f, { TAKE(wav) }); ITEM(childA, 0, 10*f, { TAKE(wav) })   -- folder parent that holds an item
ITEM(childA, 20*f, 10*f, { TAKE(wav) }); ITEM(childA, 40*f, 10*f, { TAKE(SRC(proj_dir.."six.wav","WAVE",6)) }) -- last child, mixed: split keeps the folder end
ITEM(outer, 0, 10*f, { TAKE(wav) })
ITEM(p1, 0, 10*f, { TAKE(wav) }); ITEM(p2, 0, 10*f, { TAKE(wav) }); ITEM(p5, 0, 10*f, { TAKE(wav) })
for k = 19, 21 do ITEM(tracks[k], 0, 10*f, { TAKE(wav) }) end                -- Audio 9_L / _R pair + unpaired Lone_L
ITEM(p1, 30*f, 10*f, { TAKE(wav) }, { fo = 9*f, foa = 2*f }); ITEM(p1, 38*f, 10*f, { TAKE(wav2) }, { fi = 2*f }) -- good crossfade via auto length
local items = {}
for _, tr in ipairs(tracks) do for _, it in ipairs(tr.items) do items[#items+1] = it; it.active = it.takes[1] end end
for i, tr in ipairs(tracks) do tr.num = i end
local ITEMKEY = { D_VOL = "vol", D_POSITION = "pos", D_LENGTH = "len", D_FADEINLEN = "fi", D_FADEOUTLEN = "fo", D_FADEINLEN_AUTO = "fia", D_FADEOUTLEN_AUTO = "foa",
  B_LOOPSRC = "loop", B_MUTE = "mute", C_FADEINSHAPE = "fis", C_FADEOUTSHAPE = "fos", D_FADEINDIR = "fid", D_FADEOUTDIR = "fod" }
local TAKEKEY = { D_VOL = "vol", D_PAN = "pan", D_PLAYRATE = "rate", D_PITCH = "pitch", D_STARTOFFS = "offs", I_CHANMODE = "mode" }
local TRACKGET = { IP_TRACKNUMBER = function(t) return t.num or 0 end, I_FOLDERDEPTH = function(t) return t.depth or 0 end,
  B_SHOWINTCP = function(t) return t.hidden and 0 or 1 end, I_FOLDERCOMPACT = function(t) return t.compact or 0 end }
local TRACKDEF = { D_VOL = 1, D_WIDTH = 1, D_DUALPANL = -1, D_DUALPANR = 1 }
local noop = function() end
EXT = {}
CHUNKS = {}
reaper = {
  GetSetProjectInfo = function(_, k) return k == "PROJECT_SRATE_USE" and 1 or SR end,
  GetAudioDeviceInfo = function() return true, "48000" end,
  format_timestr_pos = function(t) return string.format("%.3f", t) end,
  GetMasterTrack = function() return master end,
  GetTrackName = function(tr) return true, tr.name end,
  GetSetMediaTrackInfo_String = function(tr, k, v, set)
    if k == "P_NAME" then if set then tr.name = v end return true, tr.name end
    tr.ext = tr.ext or {}; if set then tr.ext[k] = v end; return true, tr.ext[k] or "" end,
  GetTrackGUID = function(tr) return tostring(tr) end,
  GetSetMediaItemInfo_String = function(it, k, v, set) if k == "GUID" then return true, tostring(it) end; it.ext = it.ext or {}; if set then it.ext[k] = v end; return true, it.ext[k] or "" end,
  GetMediaTrackInfo_Value = function(tr, k) local g = TRACKGET[k]; if g then return g(tr) end
    if tr.v and tr.v[k] ~= nil then return tr.v[k] end; return TRACKDEF[k] or 0 end,
  SetMediaTrackInfo_Value = function(tr, k, v) if k == "B_SHOWINTCP" then tr.hidden = (v == 0) elseif k == "I_FOLDERCOMPACT" then tr.compact = v elseif k == "I_FOLDERDEPTH" then tr.depth = v
    else tr.v = tr.v or {}; tr.v[k] = v end return true end,
  DeleteTrack = function(tr) for i, t in ipairs(tracks) do if t == tr then table.remove(tracks, i) break end end; for i, t in ipairs(tracks) do t.num = i end
    for _, it in ipairs(tr.items) do for i, x in ipairs(items) do if x == it then table.remove(items, i) break end end end end,
  InsertTrackAtIndex = function(idx) table.insert(tracks, idx + 1, T("")); for i, t in ipairs(tracks) do t.num = i end end,
  MoveMediaItemToTrack = function(it, tr) for i, x in ipairs(it.tr.items) do if x == it then table.remove(it.tr.items, i) break end end; it.tr = tr; tr.items[#tr.items + 1] = it; return true end,
  AddMediaItemToTrack = function(tr) local it = ITEM(tr, 0, 1, {}); items[#items + 1] = it; return it end,
  AddTakeToMediaItem = function(it) local tk = TAKE(nil); it.takes[#it.takes + 1] = tk; it.active = it.active or tk; return tk end,
  SetMediaItemTake_Source = function(tk, src) tk.src = src; tk.name = src.file; return true end,
  PCM_Source_CreateFromFile = function(fn) return SRC(fn) end,
  GetItemStateChunk = function(it) CHUNKS[#CHUNKS + 1] = it; return true, "<ITEM\nIGUID {x}\nMOCKREF " .. #CHUNKS .. "\n>" end,
  SetItemStateChunk = function(it, c) local src = CHUNKS[tonumber(c:match("MOCKREF (%d+)"))]
    for _, k in ipairs({ "pos", "len", "fi", "fo", "fia", "foa", "vol", "loop" }) do it[k] = src[k] end
    it.takes = {}; for _, tk in ipairs(src.takes) do local c2 = {}; for k2, v2 in pairs(tk) do c2[k2] = v2 end; it.takes[#it.takes + 1] = c2 end
    it.active = it.takes[1]; return true end,
  DeleteExtState = function(ns, k) EXT[ns .. "/" .. k] = nil end,
  GetActiveTake = function(it) return it.active end,
  GetTakeName = function(tk) return tk.name end,
  GetMediaItem_Track = function(it) return it.tr end,
  GetMediaItemInfo_Value = function(it, k) return it[ITEMKEY[k]] end,
  SetMediaItemInfo_Value = function(it, k, v) it[ITEMKEY[k]] = v; return true end,
  GetMediaItemTakeInfo_Value = function(tk, k) return tk[TAKEKEY[k]] end,
  GetMediaItemTake_Source = function(tk) return tk.src end,
  GetMediaSourceParent = function() return nil end,
  GetMediaSourceFileName = function(s) return s.file end,
  GetMediaSourceType = function(s) return s.typ end,
  GetMediaSourceNumChannels = function(s) return s.ch end,
  GetMediaSourceLength = function(s) return s.len, false end,
  GetMediaSourceSampleRate = function(s) return s.sr end,
  CountTrackMediaItems = function(tr) return #tr.items end,
  GetTrackMediaItem = function(tr, i) return tr.items[i+1] end,
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return tracks[i+1] end,
  CountTakes = function(it) return #it.takes end,
  GetTakeEnvelopeByName = function(tk, n) for _, e in ipairs(tk.env) do if e == n then return { name = e } end end end,
  AddProjectMarker2 = function() return 0 end,
  GetTrackNumSends = function(tr, cat) return cat == 0 and (tr.sends or 0) or 0 end,
  CountTrackEnvelopes = function(tr) return #tr.env end,
  GetTrackEnvelope = function(tr, i) return tr.env[i+1] end,
  GetEnvelopeName = function(e) return true, e.name end,
  CountEnvelopePoints = function(e) return e.pts or 0 end,
  CountAutomationItems = function(e) return 0 end,
  GetEnvelopeStateChunk = function(e) local c = "<ENV\nACT " .. (e.act or 1) .. " -1\nVIS 1 1 1\nARM 0\n"; for k = 1, (e.pts or 0) do c = c .. "PT " .. k .. " 1 0\n" end; return true, c .. ">" end,
  SetEnvelopeStateChunk = function(e, c) e.pts = select(2, c:gsub("\nPT ", "")); e.act = tonumber(c:match("\nACT (%d)")); return true end,
  CountTakeEnvelopes = function(tk) return #tk.env end,
  GetTakeEnvelope = function(tk, i) local n = tk.env[i+1]; tk._envobj = tk._envobj or {}
    tk._envobj[i+1] = tk._envobj[i+1] or { name = n:gsub("%*", ""), pts = 2, act = 1, vals = n:find("%*") and { 0.5, 0.8 } or { 0.5, 0.5 } }; return tk._envobj[i+1] end,
  GetEnvelopeScalingMode = function() return 0 end,
  ScaleFromEnvelopeMode = function(_, v) return v end,
  GetEnvelopePoint = function(e, i) return true, i, (e.vals or {1, 1})[i+1] or 1 end,
  DeleteTrackMediaItem = function(tr, it) for i, x in ipairs(tr.items) do if x == it then table.remove(tr.items, i) break end end; for i, x in ipairs(items) do if x == it then table.remove(items, i) break end end end,
  GetResourcePath = function() return "/nonexistent" end,
  GetMediaItemNumTakes = function(it) return #it.takes end,
  GetTakeNumStretchMarkers = function(tk) return tk.sm end,
  TakeFX_GetCount = function(tk) return tk.fx end,
  file_exists = function(p) return p:sub(1, 5) ~= "/miss" end,
  EnumProjects = function() return 0, proj_dir .. "test.rpp" end,
  TimeMap_curFrameRate = function() return FPS end,
  GetProjectTimeOffset = function() return 0 end,
  CountMediaItems = function() return #items end,
  GetMediaItem = function(_, i) return items[i+1] end,
  ValidatePtr2 = function(_, p) return p ~= nil end,
  SelectAllMediaItems = function(_, v) for _, it in ipairs(items) do it.sel = v end end,
  SetMediaItemSelected = function(it, v) it.sel = v end,
  CountSelectedMediaItems = function() local n = 0; for _, it in ipairs(items) do if it.sel then n = n + 1 end end; return n end,
  GetSelectedMediaItem = function(_, i) local n = -1; for _, it in ipairs(items) do if it.sel then n = n + 1; if n == i then return it end end end end,
  Main_OnCommand = function(cmd)
    if cmd == 40131 then for _, it in ipairs(items) do if it.sel then it.takes = { it.active } end end end
    local FIN = { [41514] = 0, [41515] = 1, [41516] = 2, [41517] = 3, [41518] = 4, [41519] = 5, [41836] = 6 }
    local FOUT = { [41521] = 0, [41522] = 1, [41523] = 2, [41524] = 3, [41525] = 4, [41526] = 5, [41837] = 6 }
    local X = { [41528] = 0, [41529] = 1, [41530] = 2, [41531] = 3, [41532] = 4, [41533] = 5, [41838] = 6 }
    for _, it in ipairs(items) do if it.sel and #it.takes > 0 then -- like (suspected) REAPER: empty items are skipped
      if FIN[cmd] then it.fis = FIN[cmd]; it.fid = 0 end
      if FOUT[cmd] then it.fos = FOUT[cmd]; it.fod = 0 end
      if X[cmd] then for _, o in ipairs(it.tr.items) do if o ~= it and o.sel and o.pos < it.pos and o.pos + o.len > it.pos then
        if (it.fia or -1) > 0 then o.fos = X[cmd] + 6; it.fis = X[cmd] + 6; o.fod = 0; it.fid = 0     -- auto crossfade: undocumented 7
        else o.fos = X[cmd] + 10; it.fis = X[cmd] + 10; o.fod = 0.25; it.fid = -0.25 end end end end -- manual: something else + a curve
    end end
  end,
  GetExtState = function(ns, k) return (EXT[ns .. "/" .. k]) or "" end,
  SetExtState = function(ns, k, v) EXT[ns .. "/" .. k] = v end,
  SetMediaItemTakeInfo_Value = function(tk, k, v) tk[TAKEKEY[k]] = v; return true end,
  UpdateItemInProject = noop,
  GetSet_ArrangeView2 = function(_, set, _, _, s, e) if set then VIEW = { s, e } end return (VIEW or { 0, 10 })[1], (VIEW or { 0, 10 })[2] end,
  SetEditCurPos = noop, GetMainHwnd = function() return {} end,
  GetTake = function(it, i) return it.takes[i+1] end,
  TrackList_AdjustWindows = noop, Undo_BeginBlock = noop, Undo_EndBlock = noop, PreventUIRefresh = noop, UpdateArrange = noop,
}
local M = dofile("Library/hsuanice_Session Fix Core.lua")
local res, sum = M.scan({ keep_folders = true })
local trim_item; for _, it in ipairs(d1.items) do if math.abs(it.pos - 260*f) < 1e-9 then trim_item = it end end
print(M.report(res, sum))
-- confirmation dialogs: only when something gets printed or deleted
do
  local r0 = M.scan({ keep_folders = true })
  local q = {}
  for _, id in ipairs({ "envelopes", "track_mix", "source_range", "channel_mode", "needs_render", "empty_tracks" }) do
    local d = M.rule_by_id(id)
    q[#q + 1] = id .. "=" .. ((d.confirm and d.confirm(r0[id]) ~= nil) and "asks" or "silent")
  end
  print("confirm: " .. table.concat(q, " ") .. "  (expect envelopes/source_range/channel_mode/needs_render/empty_tracks asks, track_mix silent)")
  local only_const = {}
  for _, is in ipairs(r0.envelopes) do if is.item == items[7] then only_const[#only_const + 1] = is end end
  print("confirm envelopes, constant volume only: " .. tostring(M.rule_by_id("envelopes").confirm(only_const)) .. " (expect nil)")
end
-- fixes that exist so far
for _, d in ipairs(M.RULES) do
  local fresh = M.scan({ keep_folders = true })[d.id] -- the GUI rescans after every fix
  if d.fix and #fresh > 0 then
    local n, msg, audit = M.fix(d, fresh, { keep_folders = true, keep_removed = true })
    if d.id == "overlaps" then OVERLAP_LOG = audit.log end
    local after = M.scan({ keep_folders = true })[d.id]
    local a = audit.summary
    print(string.format("FIX %-12s -> %s | issues after: %d | audit: %d changed, %d red, %d yellow", d.id, msg, #after, a.changed, a.red, a.yellow))
    for _, p in ipairs(audit.problems) do print("    [" .. p.level .. "] " .. p.text) end
    for _, e in ipairs(audit.log or {}) do print("    log " .. e.kind .. ": " .. tostring(e.reason) .. " @ " .. table.concat(e.where, " | ")) end
  end
end
local names = {}
for _, t in ipairs(tracks) do names[#names + 1] = t.name .. "(" .. (t.depth or 0) .. ")" end
print("tracks after fixes: " .. table.concat(names, ", "))
for _, is in ipairs(M.scan({ keep_folders = true }).off_grid) do print("  left off_grid:", M.item_label(is.item), is.text, is.item.pos * 24, (is.item.pos + is.item.len) * 24) end
local env_item = items[7]
print(string.format("merged item volume = %.3f (expected 0.500)", env_item.vol))
local function tv(tr, k) return reaper.GetMediaTrackInfo_Value(tr, k) end
local byname = {}; for _, t in ipairs(tracks) do byname[t.name] = t end
local L, R, lone = byname["Audio 09_L"] or byname["Audio 9_L"], byname["Audio 09_R"] or byname["Audio 9_R"], byname["Lone_L"]
print(string.format("track mix: Mix vol %.2f pan %.2f width %.2f | 9_L pan %.0f | 9_R dual %.0f/%.0f | Lone_L vol %.2f phase %d pan %.0f | Dial volume env act %s",
  tv(mix, "D_VOL"), tv(mix, "D_PAN"), tv(mix, "D_WIDTH"), tv(L, "D_PAN"), tv(R, "D_DUALPANL"), tv(R, "D_DUALPANR"), tv(lone, "D_VOL"), tv(lone, "B_PHASE"), tv(lone, "D_PAN"), tostring(d1.env[1].act)))
print(string.format("source_range trim: len %.4f frames, loop %d, fade-in %.2f, fade-out %.2f frames (expect 9, 0, 2 or 1, 2)", trim_item.len * FPS, trim_item.loop, trim_item.fi * FPS, trim_item.fo * FPS))
for _, is in ipairs(M.scan({ keep_folders = true }).channel_mode) do print("  channel_mode left: " .. is.text) end
local again = M.scan({ keep_folders = true }).fade_shapes
print(string.format("fade_shapes after fix + rescan: %d | read: auto %s, manual %s | tracks %d, temp track gone: %s", #again,
  EXT["hsuanice_SessionFix_shapes5/41529 ain"] or "-", EXT["hsuanice_SessionFix_shapes5/41529 in"] or "-", #tracks, tostring(tracks[#tracks].name ~= "")))
print(string.format("ISO 1 sample late: start %.6f frames, offset %.6f s, length %.6f frames (expect start 421, inward to the next frame)",
  ISO_ITEM.pos * FPS, ISO_ITEM.active.offs, ISO_ITEM.len * FPS))
print("mute_solo left (review only): " .. #M.scan({ keep_folders = true }).mute_solo)
-- the audit must catch a fix that moves audio, moves a crossfade or changes a source
local snap0 = M.snapshot()
local it1 = d1.items[1]; it1.active.offs = it1.active.offs + 0.01                 -- content moved
local xa; for _, it in ipairs(p1.items) do if it.pos > 1.2 then xa = it end end; xa.pos = xa.pos + f; xa.active.offs = xa.active.offs + f -- crossfade moved, content kept
outer.items[1].active.src = wav2                                                  -- source swapped
local probs, sm = M.compare(snap0, M.snapshot(), M.rule_by_id("crossfades"))
print(string.format("audit self-test: %d red, %d yellow (expect 3+ red)", sm.red, sm.yellow))
for _, p in ipairs(probs) do print("    [" .. p.level .. "] " .. p.text) end
-- media copied into the project folder (same file name, new path) = relinked, not printed, no warning
local snap1 = M.snapshot()
childA.items[1].active.src = SRC("/proj/Audio Files/a.wav")
local _, sm1 = M.compare(snap1, M.snapshot(), nil)
print(string.format("relink test: relinked %d, printed %d, red %d (expect 1, 0, 0)", sm1.relinked, sm1.rendered, sm1.red))
-- review copies of deleted items: "<track> before" / "<track> removed", then "Reviewed" clears them
local function names_with(sfx) local t = {}; for _, tr in ipairs(tracks) do if tr.name:find(sfx, 1, true) then t[#t + 1] = tr.name .. "(" .. #tr.items .. ")" end end; return table.concat(t, ", ") end
print("review tracks: " .. names_with(" before") .. " | " .. names_with(" removed"))
do local st = M.review_status(); print(string.format("review status: %d copies on %d tracks (before %s, removed %s, original %s)",
  st.items, st.tracks, tostring(st.kinds.before), tostring(st.kinds.removed), tostring(st.kinds.original))) end
local all = {}; for _, e in ipairs(OVERLAP_LOG or {}) do for _, c in ipairs(e.copies or {}) do all[#all + 1] = c end end
print("review copies: " .. #all .. " (expect 2 duplicates + 3 trio + 2 removed = 7); cleared: " .. M.clear_review(all)
  .. "; tracks left: '" .. names_with(" before") .. names_with(" removed") .. "' (expect none)")
print("review status after clearing: " .. M.review_status().items .. " (the old \"Dial 1 original\" mock copy remains: 1)")
do local st = M.review_status(); M.mark_copies_reviewed(st.list)
  print("original marked reviewed: still on its track " .. #tracks[#tracks].items .. ", waiting " .. M.review_status().items .. " (expect 1, 0)") end
-- razor highlight: replaces the previous one (no growing), merges a crossfade into one range
M.highlight({ { track = tracks[1], s = 1, e = 2 }, { track = tracks[2], s = 5, e = 6 } })
M.highlight({ { track = tracks[1], s = 3, e = 4 }, { track = tracks[1], s = 3.5, e = 4.5 } })
local function rz(tr) local _, v = reaper.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false); return v end
print(string.format("razor: track1 '%s' | track2 '%s' (expect one range 3..4.5, track2 empty)", rz(tracks[1]), rz(tracks[2])))
do -- key spot only: a crossfade = its overlap; clamp = the deleted item's span
  local A = ITEM(tracks[1], 100, 10, { TAKE(wav) }); local B = ITEM(tracks[1], 108, 10, { TAKE(wav) }); items[#items + 1] = A; items[#items + 1] = B
  M.highlight_issues({ { item = A, item2 = B } }); local x1 = rz(tracks[1])
  M.highlight_issues({ { item = A }, { item = B } }, 107, 108.5); local x2 = rz(tracks[1])
  print(string.format("zoom: view %.2f..%.2f (expect 106.62..108.88: 107..108.5 = 2/3 of the width, centred)", VIEW[1], VIEW[2]))
  print("razor key spot: crossfade '" .. x1 .. "' (expect 108..110) | clamped '" .. x2 .. "' (expect 107..108.5)")
end
do -- project grid via SWS: a 2-frame grid snaps to 2 frames; the label says so
  local G = 2 * f
  reaper.BR_GetClosestGridDivision = function(t) return math.floor(t / G + 0.5) * G end
  reaper.BR_GetNextGridDivision = function(t) return (math.floor(t / G + 1e-9) + 1) * G end
  reaper.BR_GetPrevGridDivision = function(t) return (math.ceil(t / G - 1e-9) - 1) * G end
  reaper.GetCursorPosition = function() return 0 end
  reaper.TimeMap2_timeToQN = function(_, t) return t * 2 end
  local M2 = dofile("Library/hsuanice_Session Fix Core.lua")
  print(string.format("grid: label '%s' (expect 2 frames) | q(3.1 frames) nearest %.2f floor %.2f ceil %.2f (expect 4, 2, 4 frames)",
    M2.grid_label(), M2.grid_q(3.1 * f) * FPS, M2.grid_q(3.1 * f, "floor") * FPS, M2.grid_q(3.1 * f, "ceil") * FPS))
  reaper.BR_GetClosestGridDivision, reaper.BR_GetNextGridDivision, reaper.BR_GetPrevGridDivision = nil, nil, nil
end
local keep = M.scan({ keep_folders = true })
print("keep_folders: folders issues = " .. #keep.folders)
