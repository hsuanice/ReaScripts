--[[
@description hsuanice Session Fix Core - checks and fixes for preparing a REAPER session for Interchanger / Pro Tools / Nuendo
@version 26.1014.2216
@author hsuanice
@noindex
@changelog
  - First release: the checks and fixes behind "Session Fix - Interchange Prep".
  - Full history: Changelogs/ in the repository (https://github.com/hsuanice/ReaScripts/tree/master/Changelogs)
@about
  Shared library behind "Session Fix - Interchange Prep".
  Every rule has: id, title, scope ("item" / "track" / "file"), scan() returning issues,
  and (when it can be fixed automatically) fix(); confirm() only asks when audio is printed
  or something is deleted. Also: before / after audit of every fix (audio position, crossfades,
  tracks), change log, review copies ("<track> original / before / removed"), razor-area
  highlight and zoom.

  Printing uses "hsuanice_RGWH Core.lua" (Render or Glue with Handles).

  Merges the checks of the former Session Fix scripts (Edges Off Grid, Looped Source Items,
  Misaligned Crossfades, Overlap Items, Split Items at Fade Edges) and the channel check of
  Split Tracks by Item Channel Count.
--]]

local r = reaper
local M = {}

M.MARK_PREFIX = "Review: "

------------------------------------------------------------
-- Basic helpers
------------------------------------------------------------
local function project_sr()
  local use = r.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false)
  local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if use == 0 or (sr or 0) <= 0 then
    local dev = tonumber(r.GetAudioDeviceInfo("SRATE", "")) or 0
    return dev > 0 and dev or 48000
  end
  return sr
end
M.project_sr = project_sr

local function db(v)
  if not v or v <= 0 then return "-inf dB" end
  return string.format("%+.2f dB", 20 * math.log(v, 10))
end

local function tc(t)
  return r.format_timestr_pos(t, "", 5) -- timecode
end
M.tc = tc

local function track_name(tr)
  if tr == r.GetMasterTrack(0) then return "MASTER" end
  local _, name = r.GetTrackName(tr)
  local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
  return string.format("%d %s", idx, name)
end
M.track_name = track_name

local function item_label(item)
  local take = r.GetActiveTake(item)
  local name = take and r.GetTakeName(take) or "(empty item)"
  return string.format("%s | %s | %s", track_name(r.GetMediaItem_Track(item)),
    tc(r.GetMediaItemInfo_Value(item, "D_POSITION")), name)
end
M.item_label = item_label

-- Change log of the running fix (M.fix collects it): what was deleted or printed, and why, with
-- the track and time range, so the window can list it and jump there afterwards.
local CHANGE_LOG = nil
local function log_item(kind, it, reason, copies)
  if not CHANGE_LOG or not (it and r.ValidatePtr2(0, it, "MediaItem*")) then return end
  local tr = r.GetMediaItem_Track(it)
  local take = r.GetActiveTake(it)
  local s = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local name = take and r.GetTakeName(take) or "(empty item)"
  CHANGE_LOG[#CHANGE_LOG + 1] = { kind = kind, reason = reason, item = (kind == "printed") and it or nil, track = tr,
    s = s, e = s + r.GetMediaItemInfo_Value(it, "D_LENGTH"), where = { track_name(tr), tc(s), name }, copies = copies }
end
local function log_track(tr, reason)
  if not CHANGE_LOG then return end
  CHANGE_LOG[#CHANGE_LOG + 1] = { kind = "deleted track", reason = reason, where = { track_name(tr), "", "" } }
end

-- Effective fade lengths as REAPER plays them: an auto-crossfade length (D_FADE*LEN_AUTO > 0)
-- replaces the manual fade; otherwise the manual length is used (AUTO = -1 / 0 means none).
local function fades(item)
  local fi = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") or 0
  local fo = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") or 0
  local fia = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO") or -1
  local foa = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO") or -1
  return (fia > 0) and fia or fi, (foa > 0) and foa or fo
end
M.fades = fades

local function bounds(item)
  local s = r.GetMediaItemInfo_Value(item, "D_POSITION")
  return s, s + r.GetMediaItemInfo_Value(item, "D_LENGTH")
end

-- project time -> source time of a take (honors D_STARTOFFS and D_PLAYRATE)
local function proj_to_src(take, item, t)
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if not rate or rate == 0 then rate = 1 end
  return r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") + (t - r.GetMediaItemInfo_Value(item, "D_POSITION")) * rate
end

-- Underlying file of a take (unwraps section / reversed sources)
local function take_source_file(take)
  local src = r.GetMediaItemTake_Source(take)
  if not src then return nil, nil end
  local parent = r.GetMediaSourceParent(src)
  while parent do src = parent; parent = r.GetMediaSourceParent(src) end
  return src, r.GetMediaSourceFileName(src, "")
end

local function source_type(src)
  return src and r.GetMediaSourceType(src, "") or ""
end

-- Channel count as heard (downmix / left / right channel modes count as mono)
local function take_channels(take)
  if not take then return nil end
  local src = r.GetMediaItemTake_Source(take)
  if not src or source_type(src) == "MIDI" then return nil end
  local mode = r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0
  if mode == 2 or mode == 3 or mode == 4 then return 1 end
  local n = math.floor(r.GetMediaSourceNumChannels(src) or 0)
  if n <= 1 then return 1 end
  return n
end

local function is_video(src)
  local t = source_type(src)
  return t == "VIDEO" or t == "VIDEOEFFECT"
end

-- A real audio item: active take with an existing audio file (not empty, MIDI, video or offline)
local function is_audio_item(it)
  local take = r.GetActiveTake(it)
  if not take then return false end
  local src, file = take_source_file(take)
  local t = source_type(src)
  return src ~= nil and t ~= "" and t ~= "EMPTY" and t ~= "MIDI" and not is_video(src)
    and file ~= nil and file ~= "" and r.file_exists(file)
end
M.is_audio_item = is_audio_item

local function save_item_selection()
  local sel = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = r.GetSelectedMediaItem(0, i) end
  return sel
end
local function restore_item_selection(sel)
  r.SelectAllMediaItems(0, false)
  for _, it in ipairs(sel) do if r.ValidatePtr2(0, it, "MediaItem*") then r.SetMediaItemSelected(it, true) end end
end

-- Set an item's fade-in / fade-out length on the field REAPER actually uses (auto overrides manual)
local function set_fade(item, which, len)
  local auto = which == "in" and "D_FADEINLEN_AUTO" or "D_FADEOUTLEN_AUTO"
  local manual = which == "in" and "D_FADEINLEN" or "D_FADEOUTLEN"
  if (r.GetMediaItemInfo_Value(item, auto) or -1) > 0 then r.SetMediaItemInfo_Value(item, auto, len)
  else r.SetMediaItemInfo_Value(item, manual, len) end
end

-- All items of a track sorted by position: { {it=, s=, e=}, ... }
local function sorted_items(tr)
  local list = {}
  for i = 0, r.CountTrackMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, i)
    local s, e = bounds(it)
    list[#list + 1] = { it = it, s = s, e = e }
  end
  table.sort(list, function(a, b) return a.s < b.s end)
  return list
end

-- Overlap between A (earlier) and B is a crossfade when A fades out and B fades in
local function crossfade_like(A, B)
  local _, outA = fades(A.it)
  local inB = fades(B.it)
  return outA > 0 and inB > 0
end

-- Remove a folder parent's folder role without touching its children: the track that closes
-- this folder gets one level less of "close", so outer folders stay intact. Then the parent
-- is a normal track (depth 0) and can be deleted safely.
local function unparent(tr)
  local depth = r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
  if depth <= 0 then return end
  local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) -- 1-based
  local level = depth
  for i = idx, r.CountTracks(0) - 1 do -- following tracks (0-based index idx = next track)
    local t = r.GetTrack(0, i)
    local d = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
    level = level + d
    if level <= 0 then
      r.SetMediaTrackInfo_Value(t, "I_FOLDERDEPTH", d + depth)
      break
    end
  end
  r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
end
M.unparent = unparent

-- An envelope matters for conversion when it is active, has points or automation items
local function envelope_in_use(env)
  if r.CountEnvelopePoints(env) > 0 or r.CountAutomationItems(env) > 0 then return true end
  local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
  return ok and chunk:match("\nACT 1") ~= nil
end

-- Remove an envelope's content: all points and automation items, then turn it off and hide it
-- (an envelope object cannot be deleted through the API; inactive + empty = no automation)
local function clear_envelope(env)
  local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
  if not ok then return false end
  local out = {}
  local skip = 0
  for line in (chunk .. "\n"):gmatch("([^\n]*)\n") do
    local t = line:match("^%s*(.-)%s*$")
    if skip > 0 then
      if t:sub(1, 1) == "<" then skip = skip + 1 elseif t == ">" then skip = skip - 1 end
    elseif t:match("^PT ") or t:match("^POOLEDENVINST") then
      -- drop points and automation item instances
    elseif t:match("^<POOLEDENV") then
      skip = 1
    elseif t:match("^ACT ") then
      out[#out + 1] = line:gsub("ACT %S+", "ACT 0", 1)
    elseif t:match("^VIS ") then
      out[#out + 1] = line:gsub("VIS %S+", "VIS 0", 1)
    elseif t:match("^ARM ") then
      out[#out + 1] = line:gsub("ARM %S+", "ARM 0", 1)
    else
      out[#out + 1] = line
    end
  end
  return r.SetEnvelopeStateChunk(env, table.concat(out, "\n"), false)
end
M.clear_envelope = clear_envelope

-- Value of an envelope that never changes (all points equal, no automation items), as the
-- envelope's real value (e.g. an amplitude for volume); nil when it changes over time.
local function envelope_constant(env)
  if r.CountAutomationItems(env) > 0 then return nil end
  local mode = r.GetEnvelopeScalingMode(env)
  local n = r.CountEnvelopePoints(env)
  if n == 0 then return nil end -- active but empty: caller decides (default value)
  local _, _, v0 = r.GetEnvelopePoint(env, 0)
  for i = 1, n - 1 do
    local _, _, v = r.GetEnvelopePoint(env, i)
    if math.abs(v - v0) > 1e-9 then return nil end
  end
  return r.ScaleFromEnvelopeMode(mode, v0)
end

local VOLUME_ENVS = { ["Volume"] = true, ["Volume (Pre-FX)"] = true }

-- Backup ("<track> original") tracks / items are tagged so every check ignores them
local BACKUP_KEY = "P_EXT:hsuanice_SessionFix"
-- Review tracks made by the fixes (all muted, ignored by every check and by Verify):
--   "<track> original" = an item before it was printed with RGWH
--   "<track> before"   = the items around a deleted one, as they were (optional, Settings)
--   "<track> removed"  = the deleted item itself (optional, Settings)
local BACKUP_KINDS = { original = true, before = true, removed = true }
local function is_backup_track(tr)
  local _, tag = r.GetSetMediaTrackInfo_String(tr, BACKUP_KEY, "", false)
  if BACKUP_KINDS[tag] then return true end
  local _, name = r.GetTrackName(tr)
  return name:match(" original$") ~= nil -- backups made before tagging existed
end
M.is_backup_track = is_backup_track

-- Copy an item, muted, to "<track name> <kind>" (created right below its track, reused when it
-- exists), so what was there before a fix stays in the session for comparison.
local function backup_copy(item, kind)
  local tr = r.GetMediaItem_Track(item)
  local _, base = r.GetTrackName(tr)
  local want = base .. " " .. kind
  local dst
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, n = r.GetTrackName(t)
    if n == want then dst = t break end
  end
  if not dst then
    local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) -- 1-based = index of the next slot
    r.InsertTrackAtIndex(idx, true)
    dst = r.GetTrack(0, idx)
    r.GetSetMediaTrackInfo_String(dst, "P_NAME", want, true)
  end
  r.GetSetMediaTrackInfo_String(dst, BACKUP_KEY, kind, true)
  local ok, chunk = r.GetItemStateChunk(item, "", false)
  if not ok then return nil end
  chunk = chunk:gsub("\n%s*IGUID [^\n]*", ""):gsub("\n%s*GUID [^\n]*", "") -- new GUIDs for the copy
  local copy = r.AddMediaItemToTrack(dst)
  r.SetItemStateChunk(copy, chunk, false)
  r.SetMediaItemSelected(copy, false) -- the chunk carries the selection state; never render the copy
  r.SetMediaItemInfo_Value(copy, "B_MUTE", 1)
  r.GetSetMediaItemInfo_String(copy, BACKUP_KEY, kind, true)
  return copy
end
local function backup_original(item) return backup_copy(item, "original") end

-- A review copy that was checked but stays (originals of printed items): tagged on the copy itself
local REVIEWED_KEY = "P_EXT:hsuanice_SessionFix_reviewed"
local function copy_reviewed(it)
  local _, v = r.GetSetMediaItemInfo_String(it, REVIEWED_KEY, "", false)
  return v == "1"
end
function M.mark_copies_reviewed(copies)
  local n = 0
  for _, c in ipairs(copies or {}) do
    if r.ValidatePtr2(0, c, "MediaItem*") then r.GetSetMediaItemInfo_String(c, REVIEWED_KEY, "1", true); n = n + 1 end
  end
  return n
end
-- Kind of review track an item sits on ("original" / "before" / "removed")
function M.copy_kind(it)
  local tr = r.GetMediaItem_Track(it)
  local _, tag = r.GetSetMediaTrackInfo_String(tr, BACKUP_KEY, "", false)
  return BACKUP_KINDS[tag] and tag or "original"
end

-- Review copies still waiting in the project (survives closing the window); reviewed originals
-- are not counted: { items =, tracks =, kinds = { before = n, ... }, list = { copy items } }
function M.review_status()
  local st = { items = 0, tracks = 0, kinds = {}, list = {} }
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if is_backup_track(tr) then
      local _, tag = r.GetSetMediaTrackInfo_String(tr, BACKUP_KEY, "", false)
      tag = BACKUP_KINDS[tag] and tag or "original"
      local waiting = 0
      for k = 0, r.CountTrackMediaItems(tr) - 1 do
        local it = r.GetTrackMediaItem(tr, k)
        if not copy_reviewed(it) then st.list[#st.list + 1] = it; waiting = waiting + 1 end
      end
      if waiting > 0 then
        st.tracks = st.tracks + 1
        st.kinds[tag] = (st.kinds[tag] or 0) + waiting
        st.items = st.items + waiting
      end
    end
  end
  return st
end

-- Review done: delete the review copies of a change, and review tracks that are empty then
function M.clear_review(copies)
  local tracks, n = {}, 0
  for _, c in ipairs(copies or {}) do
    if r.ValidatePtr2(0, c, "MediaItem*") then
      local tr = r.GetMediaItem_Track(c)
      tracks[tr] = true
      r.DeleteTrackMediaItem(tr, c)
      n = n + 1
    end
  end
  for tr in pairs(tracks) do
    if r.ValidatePtr2(0, tr, "MediaTrack*") and is_backup_track(tr) and r.CountTrackMediaItems(tr) == 0 then r.DeleteTrack(tr) end
  end
  return n
end

local RGWH_CORE
local function rgwh()
  if not RGWH_CORE then
    local ok, mod = pcall(dofile, r.GetResourcePath() .. "/Scripts/hsuanice Scripts/Library/hsuanice_RGWH Core.lua")
    if ok and type(mod) == "table" and mod.core then RGWH_CORE = mod end
  end
  return RGWH_CORE
end

-- Print an item with RGWH Render (take FX, take envelopes, playrate / pitch as heard; handles
-- from the RGWH settings). Item / take volume end up as item volume (clip gain), not printed;
-- an inverted polarity is printed into the audio. The original is backed up first and a
-- project marker marks the spot.
local function render_with_backup(item, reason, no_backup)
  local R = rgwh()
  if not R then return false, "RGWH Core not found (hsuanice Library)" end
  local take = r.GetActiveTake(item)
  if not take then return false, "no take" end
  local copy = (not no_backup) and backup_original(item) or nil -- channel mode: no original kept
  if reason and reason ~= "" then -- volume-only changes get no marker
    r.AddProjectMarker2(0, false, r.GetMediaItemInfo_Value(item, "D_POSITION"), 0, "Render: " .. reason, -1, 0)
  end
  local function source_file(tk)
    local src = tk and r.GetMediaItemTake_Source(tk)
    return src and r.GetMediaSourceFileName(src, "") or ""
  end
  local before = source_file(take)
  -- RGWH renders the selected items (op = "render" ignores args.item): select only this one
  local sel = save_item_selection()
  r.SelectAllMediaItems(0, false)
  r.SetMediaItemSelected(item, true)
  local ok, err
  local tv = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
  if tv < 0 then
    -- polarity: render with only the inversion as gain, then restore the level as item volume
    local level = r.GetMediaItemInfo_Value(item, "D_VOL") * math.abs(tv)
    r.SetMediaItemInfo_Value(item, "D_VOL", 1)
    r.SetMediaItemTakeInfo_Value(take, "D_VOL", -1)
    ok, err = R.core({ op = "render", item = item, take_fx = true, track_fx = false,
      merge_volumes = true, print_volumes = true })
    r.SetMediaItemInfo_Value(item, "D_VOL", level)
    local nt = r.GetActiveTake(item)
    if nt then r.SetMediaItemTakeInfo_Value(nt, "D_VOL", 1) end
  else
    ok, err = R.core({ op = "render", item = item, take_fx = true, track_fx = false,
      merge_to_item = true, merge_volumes = false, print_volumes = false })
  end
  restore_item_selection(sel)
  if not ok then return false, tostring(err) end
  local nt = r.GetActiveTake(item)
  if not nt or source_file(nt) == before then
    return false, "RGWH did not print the item (the source is unchanged)"
  end
  log_item("printed", item, (reason and reason ~= "") and reason or "volume automation", copy and { copy } or nil)
  -- the channel selection is printed now: every take (also the old one and the muted copy on
  -- "<track> original") goes back to normal, so Interchanger does not warn about it again
  for _, it in ipairs({ item, copy }) do
    if it and r.ValidatePtr2(0, it, "MediaItem*") then
      for t = 0, r.CountTakes(it) - 1 do
        local tk = r.GetTake(it, t)
        if (r.GetMediaItemTakeInfo_Value(tk, "I_CHANMODE") or 0) ~= 0 then r.SetMediaItemTakeInfo_Value(tk, "I_CHANMODE", 0) end
      end
    end
  end
  if nt then
    local rate = r.GetMediaItemTakeInfo_Value(nt, "D_PLAYRATE")
    local pitch = r.GetMediaItemTakeInfo_Value(nt, "D_PITCH")
    if math.abs(rate - 1) > 1e-9 or math.abs(pitch) > 1e-9 then
      return false, string.format("printed, but the new take still has playrate %.4f / pitch %+.2f", rate, pitch)
    end
  end
  return true
end
M.render_with_backup = render_with_backup

local function all_tracks(include_master)
  local list = {}
  if include_master then list[#list + 1] = r.GetMasterTrack(0) end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if not is_backup_track(tr) then list[#list + 1] = tr end
  end
  return list
end

------------------------------------------------------------
-- Rules (scan only). Each scan returns issues:
--   { item=MediaItem? , track=MediaTrack?, pos=project time?, text=string }
------------------------------------------------------------
local RULES = {}
local function rule(def) RULES[#RULES + 1] = def; def.index = #RULES end

-- Fixes return (changed_count, message). Each fix runs inside its own undo block (see M.fix).

rule {
  id = "visibility", title = "Hidden or collapsed tracks (show and expand everything first)", scope = "track",
  fix_note = "Show every track in the TCP and expand every folder (the folder structure itself is kept)",
  scan = function(ctx)
    local out = {}
    for _, tr in ipairs(ctx.tracks) do
      local why = {}
      if r.GetMediaTrackInfo_Value(tr, "B_SHOWINTCP") == 0 then why[#why + 1] = "hidden in TCP" end
      if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") > 0 and r.GetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT") ~= 0 then
        why[#why + 1] = "folder collapsed"
      end
      if #why > 0 then out[#out + 1] = { track = tr, text = table.concat(why, ", ") } end
    end
    return out
  end,
  fix = function(issues)
    local n = 0
    for _, is in ipairs(issues) do
      local tr = is.track
      if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
        r.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1)
        if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") > 0 then r.SetMediaTrackInfo_Value(tr, "I_FOLDERCOMPACT", 0) end
        n = n + 1
      end
    end
    r.TrackList_AdjustWindows(false)
    return n, string.format("%d track%s shown / expanded", n, n == 1 and "" or "s")
  end,
}

rule {
  id = "take_volume", title = "Take volume not 0 dB", scope = "item",
  fix_note = "Multiply into item volume, set take volume to 0 dB (take +3 dB, item -1 dB -> item +2 dB)",
  fix = function(issues)
    local n = 0
    for _, is in ipairs(issues) do
      local it = is.item
      local take = it and r.ValidatePtr2(0, it, "MediaItem*") and r.GetActiveTake(it)
      if take then
        local tv = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
        if tv >= 0 then -- negative = polarity, handled by "Needs render"
          r.SetMediaItemInfo_Value(it, "D_VOL", r.GetMediaItemInfo_Value(it, "D_VOL") * tv)
          r.SetMediaItemTakeInfo_Value(take, "D_VOL", 1)
          r.UpdateItemInProject(it)
          n = n + 1
        end
      end
    end
    return n, string.format("%d take volume%s merged into item volume", n, n == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      if take then
        local v = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
        if v >= 0 and math.abs(v - 1) > 1e-6 then
          out[#out + 1] = { item = it, text = "take volume " .. db(v) }
        end
      end
    end
    return out
  end,
}

rule {
  id = "take_pan", title = "Take pan not centered", scope = "item",
  fix_note = "Review only; option: reset to center (also removes the take pan envelope)",
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      if take then
        local p = r.GetMediaItemTakeInfo_Value(take, "D_PAN")
        local env = r.GetTakeEnvelopeByName(take, "Pan")
        if math.abs(p) > 1e-6 or env then
          out[#out + 1] = { item = it, text = string.format("take pan %.0f%%%s", p * 100, env and " + pan envelope" or "") }
        end
      end
    end
    return out
  end,
}

rule {
  id = "mixed_channels", title = "Track mixes mono / stereo / multichannel items", scope = "track",
  fix_note = "Split into one track per channel count",
  scan = function(ctx)
    local out = {}
    for _, tr in ipairs(ctx.tracks) do
      local seen, kinds = {}, {}
      for i = 0, r.CountTrackMediaItems(tr) - 1 do
        local ch = take_channels(r.GetActiveTake(r.GetTrackMediaItem(tr, i)))
        if ch and not seen[ch] then seen[ch] = true; kinds[#kinds + 1] = ch end
      end
      if #kinds > 1 then
        table.sort(kinds)
        local names = {}
        for _, k in ipairs(kinds) do names[#names + 1] = k == 1 and "mono" or (k == 2 and "stereo" or (k .. "ch")) end
        out[#out + 1] = { track = tr, text = table.concat(names, " + ") }
      end
    end
    return out
  end,
}

rule {
  id = "folders", title = "Folder tracks", scope = "track",
  fix_note = "Flatten the folder structure (skipped when \"Keep folder structure\" is on)",
  scan = function(ctx)
    local out = {}
    if ctx.opts.keep_folders then return out end
    for _, tr in ipairs(ctx.tracks) do
      if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") > 0 then
        local n = r.CountTrackMediaItems(tr)
        out[#out + 1] = { track = tr, text = n > 0 and string.format("folder parent with %d items (kept as a normal track)", n)
          or "folder parent (removed, children kept)" }
      end
    end
    return out
  end,
  -- Flatten: every track becomes a top-level track (children are never deleted), then the
  -- former parents that hold no items are removed. Deleting a folder parent in REAPER's UI
  -- would delete its children too, so this never deletes before flattening.
  fix = function(issues, ctx)
    local parents = {}
    for _, is in ipairs(issues) do
      if is.track and r.ValidatePtr2(0, is.track, "MediaTrack*") then parents[#parents + 1] = is.track end
    end
    for _, tr in ipairs(ctx.tracks) do
      if r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") ~= 0 then r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0) end
    end
    local removed, kept = 0, 0
    for k = #parents, 1, -1 do
      local tr = parents[k]
      if r.CountTrackMediaItems(tr) == 0 then r.DeleteTrack(tr); removed = removed + 1 else kept = kept + 1 end
    end
    r.TrackList_AdjustWindows(false)
    return #parents, string.format("%d folder%s flattened: %d empty parent track%s removed, %d kept (they hold items); all children kept",
      #parents, #parents == 1 and "" or "s", removed, removed == 1 and "" or "s", kept)
  end,
}

rule {
  id = "empty_tracks", title = "Tracks without items (aux, buses, empty)", scope = "track",
  fix_note = "Delete (the list is shown for confirmation first)",
  confirm = function(issues)
    local names = {}
    for k, is in ipairs(issues) do
      if k > 30 then names[#names + 1] = string.format("... and %d more", #issues - 30) break end
      names[#names + 1] = "  " .. track_name(is.track) .. "  (" .. is.text .. ")"
    end
    return string.format("Delete these %d track%s without items?\n\n%s", #issues, #issues == 1 and "" or "s", table.concat(names, "\n"))
  end,
  fix = function(issues)
    local list = {}
    for _, is in ipairs(issues) do
      if is.track and r.ValidatePtr2(0, is.track, "MediaTrack*") and r.CountTrackMediaItems(is.track) == 0 then list[#list + 1] = is.track end
    end
    -- Deleting a folder parent in REAPER's UI deletes its children too: here the parent first
    -- gives up its folder role (children stay where they are), then only the track is deleted.
    for k = #list, 1, -1 do
      log_track(list[k], "no items (" .. (r.GetTrackNumSends(list[k], 0) + r.GetTrackNumSends(list[k], -1) > 0 and "routing / aux" or "empty") .. ")")
      unparent(list[k])
      r.DeleteTrack(list[k])
    end
    r.TrackList_AdjustWindows(false)
    return #list, string.format("%d track%s deleted", #list, #list == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    for _, tr in ipairs(ctx.tracks) do
      if r.CountTrackMediaItems(tr) == 0 then
        local sends = r.GetTrackNumSends(tr, 0) + r.GetTrackNumSends(tr, -1)
        out[#out + 1] = { track = tr, text = sends > 0 and "routing / aux" or "no items" }
      end
    end
    return out
  end,
}

-- Track numbering per name group, in track order. A group = tracks with the same name apart
-- from a trailing number ("PFX MN C", "PFX MN C", "PFX MN C 07" -> PFX MN C 01 / 02 / 03).
-- A single track with a unique name and no number is left alone.
local function split_name(tr)
  local _, name = r.GetTrackName(tr)
  local base, num = name:match("^(.-)%s+(%d+)$")
  if base and base ~= "" then return base, num end
  return name, nil
end

rule {
  id = "renumber", title = "Track numbering (same-name tracks numbered in order)", scope = "track",
  fix_note = "Number each same-name group in track order with the chosen format (1 2 3 / 01 02 03 / 001 002 003)",
  scan = function(ctx)
    local out, groups, order = {}, {}, {}
    local width = ctx.opts.number_width or 2
    for _, tr in ipairs(ctx.tracks) do
      local base, num = split_name(tr)
      if base ~= "" then
        if not groups[base] then groups[base] = { numbered = false }; order[#order + 1] = base end
        local g = groups[base]
        g[#g + 1] = { tr = tr, num = num }
        if num then g.numbered = true end
      end
    end
    for _, base in ipairs(order) do
      local g = groups[base]
      if #g >= 2 or g.numbered then
        for k, e in ipairs(g) do
          local want = string.format("%0" .. width .. "d", k)
          if e.num ~= want then
            out[#out + 1] = { track = e.tr, new_name = base .. " " .. want,
              text = string.format("%s -> %s %s", e.num and (base .. " " .. e.num) or base, base, want) }
          end
        end
      end
    end
    return out
  end,
  fix = function(issues)
    local n = 0
    for _, is in ipairs(issues) do
      if is.track and r.ValidatePtr2(0, is.track, "MediaTrack*") and is.new_name then
        r.GetSetMediaTrackInfo_String(is.track, "P_NAME", is.new_name, true)
        n = n + 1
      end
    end
    return n, string.format("%d track%s renamed", n, n == 1 and "" or "s")
  end,
}

-- L/R pair detection, same logic as "Tracks/hsuanice_Auto Pan LR tracks.lua": the name ends with
-- _L/_R, -L/-R, .L/.R or " L"/" R", and the R track is the next track with the same base name.
local function parse_lr(name)
  name = name:gsub("%s+$", "")
  local base, side = name:match("^(.-)[_%-%. ]([LlRr])$")
  if not base then return nil end
  base = base:gsub("%s+$", "")
  if base == "" then return nil end
  return base:lower(), side:upper()
end

-- Target pan per track: -1 / +1 for the tracks of an L/R pair, 0 for everything else.
-- Returns { [track] = { pan =, note = } } for the given track list (in track order).
local function pan_targets(tracks)
  local info = {}
  for k, tr in ipairs(tracks) do
    local _, name = r.GetTrackName(tr)
    local base, side = parse_lr(name)
    info[k] = { tr = tr, base = base, side = side }
  end
  local out = {}
  local k = 1
  while k <= #info do
    local t, nxt = info[k], info[k + 1]
    if t.side == "L" and nxt and nxt.side == "R" and nxt.base == t.base then
      out[t.tr] = { pan = -1 }
      out[nxt.tr] = { pan = 1 }
      k = k + 2
    else
      out[t.tr] = { pan = 0, note = t.side and "L/R name without a pair -> centered, please check" or nil }
      k = k + 1
    end
  end
  return out
end

-- Track envelopes that belong to the mix settings this rule resets (the envelopes rule skips them)
local MIX_ENVS = { ["Volume"] = true, ["Volume (Pre-FX)"] = true, ["Trim Volume"] = true, ["Pan"] = true,
  ["Pan (Pre-FX)"] = true, ["Width"] = true, ["Width (Pre-FX)"] = true }

local function pan_text(p)
  if math.abs(p) < 1e-6 then return "C" end
  return string.format("%d%%%s", math.floor(math.abs(p) * 100 + 0.5), p < 0 and "L" or "R")
end

rule {
  id = "track_mix", title = "Track volume / pan / width / polarity not at default (L/R pairs hard left / right)", scope = "track",
  fix_note = "Reset in one click: volume 0 dB, pan center (L/R pairs 100% left / right), width 100%, polarity normal; track volume / pan / width envelopes removed",
  scan = function(ctx)
    local out = {}
    local targets = pan_targets(ctx.tracks)
    for _, tr in ipairs(ctx.tracks) do
      local want = targets[tr]
      local why, envs = {}, {}
      local vol = r.GetMediaTrackInfo_Value(tr, "D_VOL")
      if math.abs(vol - 1) > 1e-6 then why[#why + 1] = "volume " .. db(vol) end
      local mode = r.GetMediaTrackInfo_Value(tr, "I_PANMODE")
      if mode == 6 then -- dual pan: both knobs to the pair side, or the default spread (L -100 / R +100)
        local wl, wr = -1, 1
        if want.pan ~= 0 then wl, wr = want.pan, want.pan end
        local pl, pr = r.GetMediaTrackInfo_Value(tr, "D_DUALPANL"), r.GetMediaTrackInfo_Value(tr, "D_DUALPANR")
        if math.abs(pl - wl) > 1e-6 or math.abs(pr - wr) > 1e-6 then
          why[#why + 1] = string.format("dual pan %s / %s (want %s / %s)", pan_text(pl), pan_text(pr), pan_text(wl), pan_text(wr))
        end
      else
        local pan = r.GetMediaTrackInfo_Value(tr, "D_PAN")
        if math.abs(pan - want.pan) > 1e-6 then why[#why + 1] = string.format("pan %s (want %s)", pan_text(pan), pan_text(want.pan)) end
        local width = r.GetMediaTrackInfo_Value(tr, "D_WIDTH")
        if math.abs(width - 1) > 1e-6 then why[#why + 1] = string.format("width %d%%", math.floor(width * 100 + 0.5)) end
      end
      if r.GetMediaTrackInfo_Value(tr, "B_PHASE") ~= 0 then why[#why + 1] = "polarity inverted" end
      local names = {}
      for e = 0, r.CountTrackEnvelopes(tr) - 1 do
        local env = r.GetTrackEnvelope(tr, e)
        local _, name = r.GetEnvelopeName(env)
        if MIX_ENVS[name] and envelope_in_use(env) then envs[#envs + 1] = env; names[#names + 1] = name end
      end
      if #names > 0 then why[#why + 1] = "envelope " .. table.concat(names, ", ") end
      if #why > 0 then
        if want.note then why[#why + 1] = want.note end
        out[#out + 1] = { track = tr, pan = want.pan, envs = envs, text = table.concat(why, "; ") }
      end
    end
    return out
  end,
  fix = function(issues)
    local n, ne = 0, 0
    for _, is in ipairs(issues) do
      local tr = is.track
      if tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
        for _, env in ipairs(is.envs or {}) do
          if r.ValidatePtr2(0, env, "TrackEnvelope*") and clear_envelope(env) then ne = ne + 1 end
        end
        r.SetMediaTrackInfo_Value(tr, "D_VOL", 1)
        r.SetMediaTrackInfo_Value(tr, "D_PAN", is.pan)
        r.SetMediaTrackInfo_Value(tr, "D_WIDTH", 1)
        r.SetMediaTrackInfo_Value(tr, "B_PHASE", 0)
        if r.GetMediaTrackInfo_Value(tr, "I_PANMODE") == 6 then
          r.SetMediaTrackInfo_Value(tr, "D_DUALPANL", is.pan ~= 0 and is.pan or -1)
          r.SetMediaTrackInfo_Value(tr, "D_DUALPANR", is.pan ~= 0 and is.pan or 1)
        end
        n = n + 1
      end
    end
    return n, string.format("%d track%s reset, %d envelope%s removed", n, n == 1 and "" or "s", ne, ne == 1 and "" or "s")
  end,
}

rule {
  id = "mute_solo", title = "Muted / soloed tracks (review only)", scope = "track",
  fix_note = "Review only: a mute can be on purpose",
  scan = function(ctx)
    local out = {}
    for _, tr in ipairs(ctx.tracks) do
      local muted = r.GetMediaTrackInfo_Value(tr, "B_MUTE") ~= 0
      local solo = r.GetMediaTrackInfo_Value(tr, "I_SOLO") ~= 0
      if muted or solo then
        out[#out + 1] = { track = tr, text = (muted and solo) and "muted and soloed" or (muted and "muted" or "soloed") }
      end
    end
    return out
  end,
}

rule {
  id = "envelopes", title = "Automation / envelopes (track and take)", scope = "item",
  fix_note = "Take envelopes: a single value -> merged into item volume; changing -> printed with RGWH Render (original kept muted on \"<track> original\"). Other track envelopes (mute, sends, FX...): removed; track volume / pan / width envelopes are reset by the track mix check",
  confirm = function(issues) -- only when something gets printed; merging / removing needs no question
    local per_item, np = {}, 0
    for _, is in ipairs(issues) do
      if is.item then per_item[is.item] = per_item[is.item] or {}; table.insert(per_item[is.item], is.env) end
    end
    for _, envs in pairs(per_item) do
      for _, env in ipairs(envs) do
        local _, name = r.GetEnvelopeName(env)
        local empty = r.CountEnvelopePoints(env) == 0 and r.CountAutomationItems(env) == 0
        if not (VOLUME_ENVS[name] and (empty or envelope_constant(env))) then np = np + 1 break end
      end
    end
    if np == 0 then return nil end
    return string.format("Print %d item%s with changing take automation using RGWH Render?\n\n"
      .. "The original is copied (muted) to \"<track> original\" and a marker is added.\n"
      .. "Single-value volume envelopes are merged into item volume, track envelopes removed.\n\nContinue?",
      np, np == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    for _, tr in ipairs(all_tracks(true)) do
      for e = 0, r.CountTrackEnvelopes(tr) - 1 do
        local env = r.GetTrackEnvelope(tr, e)
        local _, name = r.GetEnvelopeName(env)
        local is_master = tr == r.GetMasterTrack(0)
        if (is_master or not MIX_ENVS[name]) and envelope_in_use(env) then -- mix envelopes: track_mix rule
          out[#out + 1] = { track = tr, env = env, text = string.format("track envelope \"%s\" (%d points)", name, r.CountEnvelopePoints(env)) }
        end
      end
    end
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      if take then
        for e = 0, r.CountTakeEnvelopes(take) - 1 do
          local env = r.GetTakeEnvelope(take, e)
          local _, name = r.GetEnvelopeName(env)
          if name ~= "Pan" and envelope_in_use(env) then -- take pan has its own rule
            out[#out + 1] = { item = it, env = env, text = string.format("take envelope \"%s\" (%d points)", name, r.CountEnvelopePoints(env)) }
          end
        end
      end
    end
    return out
  end,
  fix = function(issues)
    local removed, merged, printed, failed = 0, 0, 0, {}
    local per_item, order = {}, {}
    for _, is in ipairs(issues) do
      if is.item then
        if not per_item[is.item] then per_item[is.item] = {}; order[#order + 1] = is.item end
        table.insert(per_item[is.item], is.env)
      elseif is.env and r.ValidatePtr2(0, is.env, "TrackEnvelope*") and clear_envelope(is.env) then
        removed = removed + 1
      end
    end
    for _, it in ipairs(order) do
      if r.ValidatePtr2(0, it, "MediaItem*") then
        local take = r.GetActiveTake(it)
        local gain, constant = 1, true
        for _, env in ipairs(per_item[it]) do
          local _, name = r.GetEnvelopeName(env)
          local v = envelope_constant(env)
          if r.CountEnvelopePoints(env) == 0 and r.CountAutomationItems(env) == 0 then v = VOLUME_ENVS[name] and 1 or v end
          if VOLUME_ENVS[name] and v then gain = gain * v else constant = false end
        end
        local kinds = {}
        for _, env in ipairs(per_item[it]) do
          local _, name = r.GetEnvelopeName(env)
          if not VOLUME_ENVS[name] then kinds[#kinds + 1] = name end
        end
        if constant then
          r.SetMediaItemInfo_Value(it, "D_VOL", r.GetMediaItemInfo_Value(it, "D_VOL") * gain)
          for _, env in ipairs(per_item[it]) do clear_envelope(env) end
          merged = merged + 1
        else
          local ok, err = render_with_backup(it, #kinds > 0 and ("take automation " .. table.concat(kinds, ", ")) or "")
          if ok then printed = printed + 1 else failed[#failed + 1] = err end
        end
        if take then r.UpdateItemInProject(it) end
      end
    end
    local msg = string.format("%d take envelope item%s merged into item volume, %d printed with RGWH, %d track envelope%s removed",
      merged, merged == 1 and "" or "s", printed, removed, removed == 1 and "" or "s")
    if #failed > 0 then msg = msg .. string.format("; %d failed (%s)", #failed, failed[1]) end
    return merged + printed + removed, msg
  end,
}

rule {
  id = "needs_render", title = "Needs render: playrate / pitch / stretch markers / take FX / polarity", scope = "item",
  fix_note = "Copy the original (muted) to \"<track> original\", add a project marker, print with RGWH Render",
  confirm = function(issues)
    return string.format("Print %d item%s with RGWH Render?\n\n"
      .. "Each original is copied (muted) to \"<track> original\" right below its track and a project\n"
      .. "marker \"Render: <reason>\" is added. Handles follow your RGWH settings.\n"
      .. "The old take stays inactive until \"Inactive takes\" crops it.", #issues, #issues == 1 and "" or "s")
  end,
  fix = function(issues)
    local done, failed = 0, {}
    for _, is in ipairs(issues) do
      if is.item and r.ValidatePtr2(0, is.item, "MediaItem*") then
        local ok, err = render_with_backup(is.item, is.text or "")
        if ok then done = done + 1 else failed[#failed + 1] = err end
      end
    end
    local msg = string.format("%d item%s printed with RGWH Render", done, done == 1 and "" or "s")
    if #failed > 0 then msg = msg .. string.format("; %d failed (%s)", #failed, failed[1]) end
    return done, msg
  end,
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      if take and source_type(r.GetMediaItemTake_Source(take)) ~= "MIDI" then
        local why = {}
        local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        if math.abs(rate - 1) > 1e-9 then why[#why + 1] = string.format("rate %s%%", (string.format("%.2f", rate * 100):gsub("%.?0+$", ""))) end
        local pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH")
        if math.abs(pitch) > 1e-9 then why[#why + 1] = string.format("pitch %+.2f st", pitch) end
        local sm = r.GetTakeNumStretchMarkers(take)
        if sm > 0 then why[#why + 1] = sm .. " stretch markers" end
        local fx = r.TakeFX_GetCount(take)
        if fx > 0 then
          local names = {}
          for k = 0, fx - 1 do
            local ok, nm = true, ""
            if r.TakeFX_GetFXName then ok, nm = r.TakeFX_GetFXName(take, k, "") end
            nm = (ok and nm or ""):gsub("^%u+i?: ", ""):gsub(" %(.-%)$", "") -- "VST: ReaEQ (Cockos)" -> "ReaEQ"
            names[#names + 1] = nm ~= "" and nm or "FX " .. (k + 1)
          end
          why[#why + 1] = "take FX " .. table.concat(names, ", ")
        end
        if r.GetMediaItemTakeInfo_Value(take, "D_VOL") < 0 then why[#why + 1] = "polarity" end
        if #why > 0 then out[#out + 1] = { item = it, text = table.concat(why, ", ") } end
      end
    end
    return out
  end,
}

rule {
  id = "overlaps", title = "Hidden / overlapping items, stacked crossfades, slivers", scope = "item",
  fix_note = "Stacked crossfades: delete the shortest of the 3 items (editing leftover) and rebuild the crossfade between the other two; identical hidden duplicates: delete. Other overlaps: review only",
  confirm = function(issues)
    local n = 0
    for _, is in ipairs(issues) do if is.trio or is.duplicate then n = n + 1 end end
    return string.format("Delete %d leftover item%s (the shortest item of each stacked crossfade, and identical\n"
      .. "hidden duplicates)? The two items around each deleted sliver get a clean crossfade.\n"
      .. "Other overlaps are only listed.", n, n == 1 and "" or "s")
  end,
  fix = function(issues, ctx)
    local deleted, seen = 0, {}
    local keep = ctx and ctx.opts.keep_removed -- Settings: keep review copies of what is deleted
    local function del(it, reason, group)
      if it and not seen[it] and r.ValidatePtr2(0, it, "MediaItem*") then
        seen[it] = true
        local copies
        if keep then
          copies = {}
          for _, g in ipairs(group or {}) do -- the items around it, as they were
            if r.ValidatePtr2(0, g, "MediaItem*") then copies[#copies + 1] = backup_copy(g, "before") end
          end
          copies[#copies + 1] = backup_copy(it, "removed") -- and the deleted item itself
        end
        log_item("deleted", it, reason, copies)
        r.DeleteTrackMediaItem(r.GetMediaItem_Track(it), it)
        deleted = deleted + 1
      end
    end
    local repaired = 0
    for _, is in ipairs(issues) do
      if is.trio then
        local shortest, best = nil, math.huge
        for _, it in ipairs(is.trio) do
          if r.ValidatePtr2(0, it, "MediaItem*") and not seen[it] then
            local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
            if len < best then best, shortest = len, it end
          end
        end
        del(shortest, string.format("leftover in a stacked crossfade (shortest of 3 overlapping items, %.0f ms)", best * 1000), is.trio)
        -- the two remaining items now overlap directly: make that a clean crossfade
        local rest = {}
        for _, it in ipairs(is.trio) do
          if it ~= shortest and r.ValidatePtr2(0, it, "MediaItem*") then rest[#rest + 1] = it end
        end
        if #rest == 2 then
          table.sort(rest, function(a, b) return r.GetMediaItemInfo_Value(a, "D_POSITION") < r.GetMediaItemInfo_Value(b, "D_POSITION") end)
          local A, B = rest[1], rest[2]
          local _, ae = bounds(A)
          local bs, be = bounds(B)
          local ov = math.min(ae, be) - bs
          if ov > 0 then
            set_fade(A, "out", ov)
            set_fade(B, "in", ov)
            repaired = repaired + 1
          end
        end
      elseif is.duplicate then
        del(is.item, "hidden duplicate (same audio as the item covering it)", { is.cover, is.item })
      end
    end
    return deleted, string.format("%d leftover item%s deleted, %d crossfade%s rebuilt between the neighbours",
      deleted, deleted == 1 and "" or "s", repaired, repaired == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    local tol = ctx.sample_sec
    for _, tr in ipairs(ctx.tracks) do
      local list = sorted_items(tr)
      for i = 1, #list do
        local A = list[i]
        for j = i + 1, #list do
          local B = list[j]
          if B.s >= A.e - tol then break end
          if not crossfade_like(A, B) then
            local kind
            if B.e <= A.e + tol then
              local ta, tb = r.GetActiveTake(A.it), r.GetActiveTake(B.it)
              local same = ta and tb and select(2, take_source_file(ta)) == select(2, take_source_file(tb))
                and math.abs(proj_to_src(ta, A.it, B.s) - proj_to_src(tb, B.it, B.s)) <= tol
              kind = same and "hidden duplicate (same audio)" or "completely covered by another item"
            else
              kind = "partial overlap without crossfade"
            end
            out[#out + 1] = { item = B.it, pos = B.s, text = kind, duplicate = (kind == "hidden duplicate (same audio)"), cover = A.it }
          end
        end
      end
      -- 3 or more items sounding at once (e.g. a sliver left inside a crossfade) and slivers
      local flagged = {}
      for i, B in ipairs(list) do
        local why = {}
        local prev, nxt = list[i - 1], list[i + 1]
        if prev and nxt and prev.e > nxt.s + tol and B.s < prev.e and B.e > nxt.s then
          why[#why + 1] = "3 items overlap here (stacked crossfade, e.g. a leftover sliver)"
        end
        local len_frames = (B.e - B.s) * ctx.fps
        if len_frames < 2 and is_audio_item(B.it) then why[#why + 1] = string.format("tiny item (%.1f frames)", len_frames) end
        if #why > 0 and not flagged[B.it] then
          flagged[B.it] = true
          local stacked = prev and nxt and prev.e > nxt.s + tol and B.s < prev.e and B.e > nxt.s
          out[#out + 1] = { item = B.it, pos = B.s, text = table.concat(why, "; "),
            trio = stacked and { prev.it, B.it, nxt.it } or nil }
        end
      end
    end
    return out
  end,
}

rule {
  id = "crossfades", title = "Broken crossfades (fades do not match the overlap)", scope = "item",
  fix_note = "Set both fades to the overlap length (no grid snapping)",
  fix = function(issues)
    local n = 0
    for _, is in ipairs(issues) do
      local A, B = is.item2, is.item
      if A and B and r.ValidatePtr2(0, A, "MediaItem*") and r.ValidatePtr2(0, B, "MediaItem*") then
        local _, ae = bounds(A)
        local bs, be = bounds(B)
        local ov = math.min(ae, be) - bs
        if ov > 0 then
          -- an auto-crossfade length overrides the manual fade, so set whichever is in use
          if (r.GetMediaItemInfo_Value(A, "D_FADEOUTLEN_AUTO") or -1) > 0 then
            r.SetMediaItemInfo_Value(A, "D_FADEOUTLEN_AUTO", ov)
          else
            r.SetMediaItemInfo_Value(A, "D_FADEOUTLEN", ov)
          end
          if (r.GetMediaItemInfo_Value(B, "D_FADEINLEN_AUTO") or -1) > 0 then
            r.SetMediaItemInfo_Value(B, "D_FADEINLEN_AUTO", ov)
          else
            r.SetMediaItemInfo_Value(B, "D_FADEINLEN", ov)
          end
          n = n + 1
        end
      end
    end
    return n, string.format("%d crossfade%s aligned to the overlap", n, n == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    local tol = ctx.sample_sec
    for _, tr in ipairs(ctx.tracks) do
      local list = sorted_items(tr)
      for i = 1, #list - 1 do
        local A, B = list[i], list[i + 1]
        local ov = math.min(A.e, B.e) - B.s
        if ov > tol and crossfade_like(A, B) then
          local _, outA = fades(A.it)
          local inB = fades(B.it)
          if math.abs(outA - ov) > tol or math.abs(inB - ov) > tol then
            out[#out + 1] = { item = B.it, item2 = A.it, pos = B.s, text = string.format(
              "overlap %.3f s, fade-out %.3f s, fade-in %.3f s", ov, outA, inB) }
          end
        end
      end
    end
    return out
  end,
}

rule {
  id = "fade_meet", title = "Fade-in and fade-out meet or overlap (triangle)", scope = "item",
  fix_note = "Shorten both fades proportionally so they no longer meet (1 frame gap)",
  fix = function(issues, ctx)
    local n = 0
    local frame = 1 / ctx.fps
    for _, is in ipairs(issues) do
      local it = is.item
      if it and r.ValidatePtr2(0, it, "MediaItem*") then
        local fi, fo = fades(it)
        local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
        local target = (len > 2 * frame) and (len - frame) or (len * 0.5)
        if fi + fo > target then
          local k = target / (fi + fo)
          set_fade(it, "in", fi * k)
          set_fade(it, "out", fo * k)
          n = n + 1
        end
      end
    end
    return n, string.format("%d item%s: fades shortened", n, n == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local fi, fo = fades(it)
      local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if fi > 0 and fo > 0 and fi + fo >= len - ctx.sample_sec and is_audio_item(it) then
        out[#out + 1] = { item = it, text = string.format("fade-in %.3f + fade-out %.3f >= length %.3f s", fi, fo, len) }
      end
    end
    return out
  end,
}

-- Fade shapes = REAPER's own "Item: Set fade-in / fade-out / crossfade shape to ..." actions.
-- The fix runs those native actions (like a custom action of them, crossfade last), so the result
-- is exactly REAPER's. What the actions write (C_FADE*SHAPE value AND curve D_FADE*DIR; sessions
-- contain undocumented values such as 7) is read once from REAPER itself: the actions are run on
-- temporary audio items on a temporary track, which is deleted again (see calibrate_shapes).
-- Manual-length and auto-crossfade fades are read separately (REAPER may store them differently).
M.FADE_SHAPES = {
  { name = "linear",         fin = 41514, fout = 41521, x = 41528, xname = "linear, equal gain",         guess = 0 },
  { name = "slight convex",  fin = 41515, fout = 41522, x = 41529, xname = "slight convex, equal power", guess = 1 },
  { name = "slight concave", fin = 41516, fout = 41523, x = 41530, xname = "slight concave",             guess = 2 },
  { name = "sharp convex",   fin = 41517, fout = 41524, x = 41531, xname = "sharp convex",               guess = 3 },
  { name = "sharp concave",  fin = 41518, fout = 41525, x = 41532, xname = "sharp concave",              guess = 4 },
  { name = "slight S-curve", fin = 41519, fout = 41526, x = 41533, xname = "slight S-curve",             guess = 5 },
  { name = "sharp S-curve",  fin = 41836, fout = 41837, x = 41838, xname = "sharp S-curve",              guess = 6 },
}
local SHAPE_NS = "hsuanice_SessionFix_shapes5"
-- keys: "<fade-in id>", "<fade-out id>", "<crossfade id> in|out" (manual length), "<crossfade id> ain|aout" (auto crossfade)

local function shape_get(key)
  local a, b = r.GetExtState(SHAPE_NS, key):match("^([^,]+),([^,]+)$")
  if a then return { tonumber(a), tonumber(b) } end
end
local function shape_keys()
  local keys = {}
  for _, sh in ipairs(M.FADE_SHAPES) do
    for _, k in ipairs({ tostring(sh.fin), tostring(sh.fout), sh.x .. " in", sh.x .. " out", sh.x .. " ain", sh.x .. " aout" }) do keys[#keys + 1] = k end
  end
  return keys
end
function M.reset_fade_shapes()
  for _, k in ipairs(shape_keys()) do r.DeleteExtState(SHAPE_NS, k, true) end
end

-- Run every shape action once on temporary audio items (A/B manual crossfade, C alone, D/E auto
-- crossfade) on a temporary track, read what REAPER wrote, delete the track again. Done once and
-- remembered; nothing is stored when the actions did not change anything (returns an error).
local function calibrate_shapes(ctx)
  local missing = false
  for _, k in ipairs(shape_keys()) do if not shape_get(k) then missing = true break end end
  if not missing then return true end
  local file
  for _, it in ipairs(ctx.items) do
    if is_audio_item(it) then file = select(2, take_source_file(r.GetActiveTake(it))) break end
  end
  if not file then return false, "no audio item in the project to read the fade shapes with" end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local sel = save_item_selection()
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, false)
  local tr = r.GetTrack(0, idx)
  local function mk(pos, len, fi, fo, auto)
    local it = r.AddMediaItemToTrack(tr)
    local tk = r.AddTakeToMediaItem(it)
    r.SetMediaItemTake_Source(tk, r.PCM_Source_CreateFromFile(file))
    r.SetMediaItemInfo_Value(it, "D_POSITION", pos)
    r.SetMediaItemInfo_Value(it, "D_LENGTH", len)
    r.SetMediaItemInfo_Value(it, auto and "D_FADEINLEN_AUTO" or "D_FADEINLEN", fi)
    r.SetMediaItemInfo_Value(it, auto and "D_FADEOUTLEN_AUTO" or "D_FADEOUTLEN", fo)
    return it
  end
  local A, B, C = mk(0, 2, 0, 0.5), mk(1.5, 2, 0.5, 0), mk(10, 2, 0.5, 0.5)
  local D, E = mk(20, 2, 0, 0.5, true), mk(21.5, 2, 0.5, 0, true)
  r.SelectAllMediaItems(0, false)
  for _, it in ipairs({ A, B, C, D, E }) do r.SetMediaItemSelected(it, true) end
  local vals = {}
  local function get(key, it, which)
    vals[key] = { r.GetMediaItemInfo_Value(it, which == "in" and "C_FADEINSHAPE" or "C_FADEOUTSHAPE"),
      r.GetMediaItemInfo_Value(it, which == "in" and "D_FADEINDIR" or "D_FADEOUTDIR") }
  end
  for _, sh in ipairs(M.FADE_SHAPES) do
    r.Main_OnCommand(sh.fin, 0);  get(tostring(sh.fin), C, "in")
    r.Main_OnCommand(sh.fout, 0); get(tostring(sh.fout), C, "out")
    for _, pr in ipairs({ { A, B }, { D, E } }) do -- one crossfade per run (see the fix)
      r.SelectAllMediaItems(0, false)
      r.SetMediaItemSelected(pr[1], true); r.SetMediaItemSelected(pr[2], true)
      r.Main_OnCommand(sh.x, 0)
    end
    get(sh.x .. " in", B, "in"); get(sh.x .. " out", A, "out")
    get(sh.x .. " ain", E, "in"); get(sh.x .. " aout", D, "out")
    r.SelectAllMediaItems(0, false)
    for _, it in ipairs({ A, B, C, D, E }) do r.SetMediaItemSelected(it, true) end
  end
  r.DeleteTrack(tr)
  restore_item_selection(sel)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Session Fix: read fade shapes from REAPER's actions", -1)
  -- sanity: the 7 fade-in actions must not all have written the same thing
  local first, differ = vals[tostring(M.FADE_SHAPES[1].fin)], false
  for _, sh in ipairs(M.FADE_SHAPES) do
    local v = vals[tostring(sh.fin)]
    if v[1] ~= first[1] or math.abs(v[2] - first[2]) > 1e-3 then differ = true end
  end
  if not differ then return false, "REAPER's fade shape actions did not change the test items" end
  for k, v in pairs(vals) do r.SetExtState(SHAPE_NS, k, string.format("%.6g,%.6g", v[1], v[2]), true) end
  return true
end

local function shape_targets(ctx)
  local ok, err = calibrate_shapes(ctx)
  local o = ctx.opts
  local SI, SO, SX = M.FADE_SHAPES[o.fade_in_shape or 1] or M.FADE_SHAPES[1], M.FADE_SHAPES[o.fade_out_shape or 1] or M.FADE_SHAPES[1],
    M.FADE_SHAPES[o.xfade_shape or 2] or M.FADE_SHAPES[2]
  return { ok = ok, err = err, SI = SI, SO = SO, SX = SX, fin = shape_get(tostring(SI.fin)), fout = shape_get(tostring(SO.fout)),
    xin = shape_get(SX.x .. " in"), xout = shape_get(SX.x .. " out"), xain = shape_get(SX.x .. " ain"), xaout = shape_get(SX.x .. " aout") }
end

local function same_shape(shape, dir, want)
  return want ~= nil and shape == want[1] and math.abs(dir - want[2]) < 1e-3
end
local function sv(shape, dir) return string.format("[%g/%g]", shape, dir) end -- raw value, for checking

-- Readable name of a shape / curve pair as REAPER's actions name it
local function shape_name(shape, dir, crossfade)
  for _, sh in ipairs(M.FADE_SHAPES) do
    if crossfade then
      for _, k in ipairs({ " in", " out", " ain", " aout" }) do
        if same_shape(shape, dir, shape_get(sh.x .. k)) then return sh.xname end
      end
    elseif same_shape(shape, dir, shape_get(tostring(sh.fin))) or same_shape(shape, dir, shape_get(tostring(sh.fout))) then
      return sh.name
    end
  end
  return "custom"
end

-- Fade edges of each audio item, with crossfade neighbours: { it, fi, fo, x_in = prev, x_out = next }
local function fade_edges(ctx)
  local out = {}
  for _, tr in ipairs(ctx.tracks) do
    local list = sorted_items(tr)
    for k, e in ipairs(list) do
      if is_audio_item(e.it) then
        local prev, nxt = list[k - 1], list[k + 1]
        e.fi, e.fo = fades(e.it)
        e.x_in = prev and prev.e > e.s + ctx.sample_sec and crossfade_like(prev, e) and prev.it or nil
        e.x_out = nxt and e.e > nxt.s + ctx.sample_sec and crossfade_like(e, nxt) and nxt.it or nil
        out[#out + 1] = e
      end
    end
  end
  return out
end

rule {
  id = "fade_shapes", title = "Fade shapes not standard (fade in / fade out / crossfade, see Settings)", scope = "item",
  fix_note = "Run REAPER's own \"Set fade-in / fade-out / crossfade shape\" actions chosen in Settings (crossfade last, like a custom action); fade lengths are not changed",
  scan = function(ctx)
    local out = {}
    local T = shape_targets(ctx)
    if not T.ok then return { { text = "Could not read the fade shapes from REAPER: " .. tostring(T.err) .. " (nothing checked)" } } end
    for _, e in ipairs(fade_edges(ctx)) do
      local why = {}
      local si, di = r.GetMediaItemInfo_Value(e.it, "C_FADEINSHAPE"), r.GetMediaItemInfo_Value(e.it, "D_FADEINDIR")
      local so, dout = r.GetMediaItemInfo_Value(e.it, "C_FADEOUTSHAPE"), r.GetMediaItemInfo_Value(e.it, "D_FADEOUTDIR")
      local ain = (r.GetMediaItemInfo_Value(e.it, "D_FADEINLEN_AUTO") or -1) > 0
      local aout = (r.GetMediaItemInfo_Value(e.it, "D_FADEOUTLEN_AUTO") or -1) > 0
      -- a crossfade side is fine in either of REAPER's forms (auto crossfade / manual length)
      local wi = e.x_in and (ain and T.xain or T.xin) or T.fin
      local wo = e.x_out and (aout and T.xaout or T.xout) or T.fout
      local alt_i = e.x_in and (ain and T.xin or T.xain) or nil
      local alt_o = e.x_out and (aout and T.xout or T.xaout) or nil
      if e.fi > 0 and not same_shape(si, di, wi) and not same_shape(si, di, alt_i) then
        why[#why + 1] = string.format("%s: %s %s (want %s %s)", e.x_in and "crossfade (in)" or "fade-in", shape_name(si, di, e.x_in), sv(si, di),
          e.x_in and T.SX.xname or T.SI.name, wi and sv(wi[1], wi[2]) or "")
      end
      if e.fo > 0 and not same_shape(so, dout, wo) and not same_shape(so, dout, alt_o) then
        why[#why + 1] = string.format("%s: %s %s (want %s %s)", e.x_out and "crossfade (out)" or "fade-out", shape_name(so, dout, e.x_out), sv(so, dout),
          e.x_out and T.SX.xname or T.SO.name, wo and sv(wo[1], wo[2]) or "")
      end
      if #why > 0 then
        out[#out + 1] = { item = e.it, item2 = e.x_out or e.x_in, text = table.concat(why, "; ") }
      end
    end
    return out
  end,
  fix = function(issues, ctx)
    local T = shape_targets(ctx)
    if not T.ok then return 0, "fade shapes could not be read from REAPER: " .. tostring(T.err) end
    -- the items and their crossfade partners (the crossfade action needs both sides selected)
    local want = {}
    for _, is in ipairs(issues) do
      if is.item and r.ValidatePtr2(0, is.item, "MediaItem*") then want[is.item] = true end
    end
    local edges = fade_edges(ctx)
    for _, e in ipairs(edges) do
      if want[e.it] then
        if e.x_in then want[e.x_in] = true end
        if e.x_out then want[e.x_out] = true end
      end
    end
    local sel = save_item_selection()
    r.SelectAllMediaItems(0, false)
    local n = 0
    for it in pairs(want) do r.SetMediaItemSelected(it, true); n = n + 1 end
    r.Main_OnCommand(T.SI.fin, 0)
    r.Main_OnCommand(T.SO.fout, 0)
    -- the crossfade action changes only one crossfade per run when many items are selected:
    -- run it once per crossfade, with just its two items selected
    local pairs_done, nx = {}, 0
    for _, e in ipairs(edges) do
      if want[e.it] then
        for _, pr in ipairs({ e.x_in and { e.x_in, e.it } or false, e.x_out and { e.it, e.x_out } or false }) do
          if pr then
            local key = tostring(pr[1]) .. "|" .. tostring(pr[2])
            if not pairs_done[key] then
              pairs_done[key] = true
              r.SelectAllMediaItems(0, false)
              r.SetMediaItemSelected(pr[1], true)
              r.SetMediaItemSelected(pr[2], true)
              r.Main_OnCommand(T.SX.x, 0)
              nx = nx + 1
            end
          end
        end
      end
    end
    for it in pairs(want) do r.UpdateItemInProject(it) end
    restore_item_selection(sel)
    return n, string.format("%d item%s, %d crossfade%s: fade shapes set with REAPER's actions (in: %s, out: %s, crossfade: %s)",
      n, n == 1 and "" or "s", nx, nx == 1 and "" or "s", T.SI.name, T.SO.name, T.SX.xname)
  end,
}

-- How an item past its source gets fixed: "trim" (up to 1 frame, edge not in a crossfade) or
-- "print". Returns plan, timeline seconds before the source start / past its end, item start / end.
local function overrun_plan(it, take, frame, eps)
  local srclen = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take))
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"); if rate <= 0 then rate = 1 end
  local s, e = bounds(it)
  local over_s = math.max(0, -proj_to_src(take, it, s)) / rate
  local over_e = math.max(0, proj_to_src(take, it, e) - srclen) / rate
  -- a trimmed edge inside a crossfade would move the crossfade: print instead
  local x_s, x_e = false, false
  local tr = r.GetMediaItem_Track(it)
  for i = 0, r.CountTrackMediaItems(tr) - 1 do
    local o = r.GetTrackMediaItem(tr, i)
    if o ~= it then
      local os_, oe = bounds(o)
      if over_s > eps and os_ < s - eps and oe > s + eps then x_s = true end
      if over_e > eps and os_ < e - eps and oe > e + eps then x_e = true end
    end
  end
  local trim = over_s <= frame + eps and over_e <= frame + eps and not x_s and not x_e
  return trim and "trim" or "print", over_s, over_e, s, e
end

rule {
  id = "source_range", title = "Item extends beyond its source (looped or past the file)", scope = "item",
  fix_note = "Up to 1 frame past the source (accidental): trimmed. More (e.g. an ambience loop), or the edge is in a crossfade: printed with RGWH Render (original kept muted on \"<track> original\"). Loop source is turned off afterwards",
  confirm = function(issues) -- only when something gets printed; trimming needs no question
    local frame, eps = 1 / r.TimeMap_curFrameRate(0), 1 / project_sr()
    local np = 0
    for _, is in ipairs(issues) do
      local take = is.item and r.ValidatePtr2(0, is.item, "MediaItem*") and r.GetActiveTake(is.item)
      if take and overrun_plan(is.item, take, frame, eps) == "print" then np = np + 1 end
    end
    if np == 0 then return nil end
    return string.format("Print %d item%s with RGWH Render (more than 1 frame past the source, e.g. an\n"
      .. "ambience loop, or the edge sits in a crossfade)?\n\n"
      .. "The original is copied (muted) to \"<track> original\" and a marker is added.\n"
      .. "Items up to 1 frame past the source are simply trimmed. Loop source is turned off afterwards.\n\nContinue?",
      np, np == 1 and "" or "s")
  end,
  fix = function(issues, ctx)
    local frame, eps = 1 / ctx.fps, ctx.sample_sec
    local trimmed, printed, failed = 0, 0, {}
    for _, is in ipairs(issues) do
      local it = is.item
      local take = it and r.ValidatePtr2(0, it, "MediaItem*") and r.GetActiveTake(it)
      if take then
        local plan, over_s, over_e, s, e = overrun_plan(it, take, frame, eps)
        if plan == "trim" then
          -- trim to the source, then inward to the frame grid; fade edges stay on the grid
          local off = ctx.time_offset
          local function q(t, mode)
            local f = (t + off) * ctx.fps
            local g = mode == "floor" and math.floor(f + 1e-6) or (mode == "ceil" and math.ceil(f - 1e-6) or math.floor(f + 0.5))
            return g / ctx.fps - off
          end
          local fi, fo = fades(it)
          local ns = over_s > 0 and q(s + over_s, "ceil") or s
          local ne = over_e > 0 and q(e - over_e, "floor") or e
          if ne - ns < frame then ns, ne = s + over_s, e - over_e end -- too short for the grid: exact trim
          local d = ns - s
          if d > 0 then
            r.SetMediaItemInfo_Value(it, "D_POSITION", ns)
            for t = 0, r.CountTakes(it) - 1 do
              local tk = r.GetTake(it, t)
              local tr_rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"); if tr_rate <= 0 then tr_rate = 1 end
              r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") + d * tr_rate)
            end
          end
          local len = ne - ns
          r.SetMediaItemInfo_Value(it, "D_LENGTH", len)
          if fi > 0 then -- same fade length, its end on the nearest frame, inside the item
            local fe = math.min(math.max(q(ns + fi), ns + frame), ne)
            set_fade(it, "in", math.max(fe - ns, 0))
          end
          if fo > 0 then -- same for the fade-out start
            local fs = math.max(math.min(q(ne - fo), ne - frame), ns)
            set_fade(it, "out", math.max(ne - fs, 0))
          end
          local nfi, nfo = fades(it)
          if nfi + nfo > len then local k = len / (nfi + nfo); set_fade(it, "in", nfi * k); set_fade(it, "out", nfo * k) end
          r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
          trimmed = trimmed + 1
        else
          local looped = r.GetMediaItemInfo_Value(it, "B_LOOPSRC") ~= 0
          local reason = string.format("%s %.2f s past the source", looped and "loop" or "silence", over_s + over_e)
          local ok, err = render_with_backup(it, reason)
          if ok then
            r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
            printed = printed + 1
          else
            failed[#failed + 1] = err
          end
        end
        r.UpdateItemInProject(it)
      end
    end
    local msg = string.format("%d item%s trimmed, %d printed with RGWH Render", trimmed, trimmed == 1 and "" or "s", printed)
    if #failed > 0 then msg = msg .. string.format("; %d failed (%s)", #failed, failed[1]) end
    return trimmed + printed, msg
  end,
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      local audio = is_audio_item(it)
      local srclen = audio and r.GetMediaSourceLength(r.GetMediaItemTake_Source(take)) or 0
      if audio and srclen > 0 then
        local s, e = bounds(it)
        local a, b = proj_to_src(take, it, s), proj_to_src(take, it, e)
        if a < -ctx.sample_sec or b > srclen + ctx.sample_sec then
          out[#out + 1] = { item = it, pos = (b > srclen) and (s + (srclen - a) / math.max(r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"), 1e-9)) or s,
            text = string.format("source %.3f s, item uses %.3f .. %.3f s", srclen, a, b) }
        end
      end
    end
    return out
  end,
}

rule {
  id = "media", title = "Media: outside the project folder / not WAV / sample rate / missing (video excluded)", scope = "file",
  banner = true, -- shown as a reminder at the top of the window, not in the checklist
  fix_note = "Save the project with File > Save project as... and tick \"Copy all media into project directory\" (or collect the files with the Media Explorer)",
  instructions = "Media outside the project folder:\n\n"
    .. "Use File > Save project as... and tick \"Copy all media into project directory\"\n"
    .. "(optionally \"Convert media\" to WAV at the project sample rate).\n"
    .. "This copies every file into the project and relinks the items.\n\n"
    .. "Open \"Save project as\" now?",
  scan = function(ctx)
    local out = {}
    local per_file = {}
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      local src, file = nil, nil
      if take then src, file = take_source_file(take) end
      if src and file and file ~= "" and source_type(src) ~= "MIDI" and not is_video(src) then
        local f = per_file[file]
        if not f then
          f = { why = {}, item = it, kinds = {} }
          per_file[file] = f
          local exists = r.file_exists(file)
          if not exists then f.why[#f.why + 1] = "file missing"; f.kinds.missing = true end
          if ctx.project_dir == "" then
            f.why[#f.why + 1] = "project not saved yet"; f.kinds.outside = true
          elseif file:sub(1, #ctx.project_dir) ~= ctx.project_dir then
            f.why[#f.why + 1] = "outside the project folder"; f.kinds.outside = true
          end
          local t = source_type(src)
          if t ~= "WAVE" then f.why[#f.why + 1] = "type " .. t; f.kinds.format = true end
          local sr = r.GetMediaSourceSampleRate(src)
          if exists and sr > 0 and math.abs(sr - ctx.sr) > 0.5 then f.why[#f.why + 1] = string.format("%d Hz", sr); f.kinds.rate = true end
          if #f.why > 0 then out[#out + 1] = { item = it, file = file, kinds = f.kinds, text = file .. "  — " .. table.concat(f.why, ", ") } end
        end
      end
    end
    return out
  end,
}

rule {
  id = "off_grid", title = "Item / fade edges not on the frame grid (crossfades excluded)", scope = "item",
  fix_note = "Snap to the nearest frame, content stays in place; crossfades are never moved. Falls back to snapping inward when outward would pass the source or touch a neighbor",
  fix = function(issues, ctx)
    local fps = ctx.fps
    local off = ctx.time_offset
    local function q(t, mode) -- nearest / floor / ceil frame time
      local f = (t + off) * fps
      local g = mode == "floor" and math.floor(f + 1e-9) or (mode == "ceil" and math.ceil(f - 1e-9) or math.floor(f + 0.5))
      return g / fps - off
    end
    local eps = ctx.sample_sec
    local n = 0
    for _, is in ipairs(issues) do
      local it = is.item
      local take = it and r.ValidatePtr2(0, it, "MediaItem*") and r.GetActiveTake(it)
      if take then
        local tr = r.GetMediaItem_Track(it)
        local prev_e, next_s = -math.huge, math.huge
        for _, o in ipairs(sorted_items(tr)) do
          if o.it ~= it then
            local s0 = r.GetMediaItemInfo_Value(it, "D_POSITION")
            if o.s < s0 then prev_e = math.max(prev_e, o.e) else next_s = math.min(next_s, o.s) end
          end
        end
        local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"); if rate <= 0 then rate = 1 end
        local srclen = r.GetMediaSourceLength(r.GetMediaItemTake_Source(take))
        local s, e = bounds(it)
        local fi, fo = fades(it)
        local fin_end, fout_start = s + fi, e - fo -- absolute fade points, kept unless snapped
        if not is.xin then
          local ns = q(s)
          local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
          if ns < s and (offs - (s - ns) * rate < -eps or ns < prev_e - eps) then ns = q(s, "ceil") end
          if math.abs(ns - s) > eps then
            local d = ns - s
            r.SetMediaItemInfo_Value(it, "D_POSITION", ns)
            r.SetMediaItemInfo_Value(it, "D_LENGTH", e - ns)
            for k = 0, r.CountTakes(it) - 1 do
              local tk = r.GetTake(it, k)
              local tr_rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE"); if tr_rate <= 0 then tr_rate = 1 end
              r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") + d * tr_rate)
            end
            s = ns
          end
        end
        if not is.xout then
          local ne = q(e)
          local offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
          if ne > e and (offs + (ne - s) * rate > srclen + eps or ne > next_s + eps) then ne = q(e, "floor") end
          if math.abs(ne - e) > eps and ne > s then r.SetMediaItemInfo_Value(it, "D_LENGTH", ne - s); e = ne end
        end
        if not is.xin and fi > 0 then
          local t = q(math.max(fin_end, s)); if t <= s + eps then t = q(s + eps, "ceil") end
          set_fade(it, "in", math.min(t, e) - s)
        end
        if not is.xout and fo > 0 then
          local t = q(math.min(fout_start, e)); if t >= e - eps then t = q(e - eps, "floor") end
          set_fade(it, "out", e - math.max(t, s))
        end
        r.UpdateItemInProject(it)
        n = n + 1
      end
    end
    return n, string.format("%d item%s snapped to the frame grid", n, n == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    local fps = ctx.fps
    local off = ctx.time_offset
    local tol = 0.5 / ctx.sr -- half a sample
    local function off_grid(t)
      local f = (t + off) * fps
      return math.abs(f - math.floor(f + 0.5)) / fps > tol
    end
    for _, tr in ipairs(ctx.tracks) do
      local list = sorted_items(tr)
      for i, A in ipairs(list) do
        if not is_audio_item(A.it) then goto continue end
        local prev, nxt = list[i - 1], list[i + 1]
        local xin = prev and prev.e > A.s + ctx.sample_sec and crossfade_like(prev, A)
        local xout = nxt and A.e > nxt.s + ctx.sample_sec and crossfade_like(A, nxt)
        local fi, fo = fades(A.it)
        local bad, at = {}, {}
        local function add(cond, label, t) if cond then bad[#bad + 1] = label; at[#at + 1] = t end end
        add(not xin and off_grid(A.s), "start", A.s)
        add(not xin and fi > 0 and off_grid(A.s + fi), "fade-in end", A.s + fi)
        add(not xout and fo > 0 and off_grid(A.e - fo), "fade-out start", A.e - fo)
        add(not xout and off_grid(A.e), "end", A.e)
        if #bad > 0 then out[#out + 1] = { item = A.it, pos = at[1], positions = at, labels = bad, xin = xin, xout = xout, text = table.concat(bad, ", ") } end
        ::continue::
      end
    end
    return out
  end,
}

rule {
  id = "empty_midi", title = "Empty items and MIDI items (e.g. Scene Cut, PM work logs)", scope = "item",
  fix_note = "Ask: convert to audio items, or delete",
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      if not take then
        out[#out + 1] = { item = it, text = "empty item" }
      elseif source_type(r.GetMediaItemTake_Source(take)) == "MIDI" then
        out[#out + 1] = { item = it, text = "MIDI item" }
      end
    end
    return out
  end,
}

-- Take channel mode (I_CHANMODE): 0 normal, 1 reverse stereo, 2 mono downmix, 3.. = mono channel
-- (mode - 2), 67.. = stereo pair starting at channel (mode - 66). Returns a label and the highest
-- source channel the mode reads.
local function chanmode_info(mode)
  if mode == 1 then return "reverse stereo", 2 end
  if mode == 2 then return "mono downmix", 1 end
  if mode >= 3 and mode <= 66 then return "mono channel " .. (mode - 2), mode - 2 end
  if mode >= 67 then return string.format("stereo channels %d-%d", mode - 66, mode - 65), mode - 65 end
  return "mode " .. mode, 1
end
M.chanmode_info = chanmode_info

rule {
  id = "channel_mode", title = "Take channel mode not normal (mono: reset; stereo / poly: print)", scope = "item",
  fix_note = "Mono source: reset to normal (sounds the same). Stereo / poly source playing other channels: print with RGWH Render (original kept muted on \"<track> original\"), then normal. A mode that reads a channel the file does not have is left for review (it may be silent)",
  confirm = function(issues) -- only when something gets printed
    local reset, print_n = 0, 0
    for _, is in ipairs(issues) do if is.action == "reset" then reset = reset + 1 elseif is.action == "render" then print_n = print_n + 1 end end
    if print_n == 0 then return nil end
    return string.format("Channel mode:\n\n- %d mono item%s: reset to normal (sounds the same).\n"
      .. "- %d stereo / poly item%s: printed with RGWH Render (the original is copied, muted, to\n"
      .. "  \"<track> original\" and a marker is added), then set to normal.\n"
      .. "Items whose mode reads a missing channel are not changed (review).\n\nContinue?",
      reset, reset == 1 and "" or "s", print_n, print_n == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local take = r.GetActiveTake(it)
      local src = take and r.GetMediaItemTake_Source(take)
      if src and source_type(src) ~= "MIDI" and not is_video(src) then
        local mode = math.floor(r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0)
        if mode ~= 0 then
          local nch = math.max(1, math.floor(r.GetMediaSourceNumChannels(src) or 1))
          local label, need = chanmode_info(mode)
          local is = { item = it }
          if nch == 1 and (need <= 1 or mode == 1) then
            is.action, is.text = "reset", string.format("%s on a mono file (sounds the same)", label)
          elseif need > nch then
            is.action, is.text = "review", string.format("%s, but the file has %d channel%s - may be silent, please check", label, nch, nch == 1 and "" or "s")
          else
            is.action, is.text = "render", string.format("%s of a %d-channel file", label, nch)
          end
          out[#out + 1] = is
        end
      end
    end
    return out
  end,
  fix = function(issues)
    local reset, printed, failed = 0, 0, {}
    for _, is in ipairs(issues) do
      local it = is.item
      local take = it and r.ValidatePtr2(0, it, "MediaItem*") and r.GetActiveTake(it)
      if take and is.action == "reset" then
        r.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", 0)
        r.UpdateItemInProject(it)
        reset = reset + 1
      elseif take and is.action == "render" then
        local label = chanmode_info(math.floor(r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE")))
        local ok, err = render_with_backup(it, "channel mode " .. label, true)
        if ok then printed = printed + 1 else failed[#failed + 1] = err end
      end
    end
    local msg = string.format("%d mono item%s reset, %d printed with RGWH Render", reset, reset == 1 and "" or "s", printed)
    if #failed > 0 then msg = msg .. string.format("; %d failed (%s)", #failed, failed[1]) end
    return reset + printed, msg
  end,
}

rule {
  id = "inactive_takes", title = "Inactive takes", scope = "item",
  fix_note = "Last step: crop to the active take (after printing, the old take is not needed: the original is kept on \"<track> original\")",
  fix = function(issues)
    local sel = save_item_selection()
    r.SelectAllMediaItems(0, false)
    local n = 0
    for _, is in ipairs(issues) do
      if is.item and r.ValidatePtr2(0, is.item, "MediaItem*") then r.SetMediaItemSelected(is.item, true); n = n + 1 end
    end
    if n > 0 then r.Main_OnCommand(40131, 0) end -- Take: Crop to active take in items
    restore_item_selection(sel)
    return n, string.format("%d item%s cropped to the active take", n, n == 1 and "" or "s")
  end,
  scan = function(ctx)
    local out = {}
    for _, it in ipairs(ctx.items) do
      local n = r.CountTakes(it)
      if n > 1 then out[#out + 1] = { item = it, text = string.format("%d takes", n) } end
    end
    return out
  end,
}

M.RULES = RULES
function M.rule_by_id(id)
  for _, d in ipairs(RULES) do if d.id == id then return d end end
end

-- What each fix is allowed to change, for the before / after check (see Audit below)
M.rule_by_id("overlaps").may_delete = true      -- deletes leftover slivers and hidden duplicates
M.rule_by_id("off_grid").moves_edges = true     -- trims edges by up to one frame
M.rule_by_id("needs_render").renders = true     -- new source file (RGWH print)
M.rule_by_id("envelopes").renders = true
M.rule_by_id("channel_mode").renders = true
M.rule_by_id("source_range").moves_edges = true -- trims up to one frame ...
M.rule_by_id("source_range").renders = true     -- ... or prints longer overruns

------------------------------------------------------------
-- Scan
------------------------------------------------------------
function M.make_context(opts)
  local sr = project_sr()
  local _, proj_path = r.EnumProjects(-1, "")
  local dir = (proj_path or ""):match("^(.*[/\\])") or ""
  local ctx = {
    sr = sr, sample_sec = 1 / sr,
    fps = r.TimeMap_curFrameRate(0),
    time_offset = r.GetProjectTimeOffset(0, false),
    project_dir = dir,
    opts = opts or {},
    tracks = all_tracks(false),
    items = {},
  }
  for i = 0, r.CountMediaItems(0) - 1 do
    local it = r.GetMediaItem(0, i)
    if not is_backup_track(r.GetMediaItem_Track(it)) then ctx.items[#ctx.items + 1] = it end
  end
  ctx.backup_tracks = 0
  for i = 0, r.CountTracks(0) - 1 do if is_backup_track(r.GetTrack(0, i)) then ctx.backup_tracks = ctx.backup_tracks + 1 end end
  return ctx
end

-- Returns { [rule.id] = issues }, plus a summary { total=, items=, tracks= }
function M.scan(opts)
  local ctx = M.make_context(opts)
  local results, total = {}, 0
  for _, d in ipairs(RULES) do
    local ok, res = pcall(d.scan, ctx)
    if not ok then res = { { text = "SCAN ERROR: " .. tostring(res) } } end
    results[d.id] = res
    total = total + #res
  end
  return results, { total = total, items = #ctx.items, tracks = #ctx.tracks, fps = ctx.fps, sr = ctx.sr }
end

------------------------------------------------------------
-- Fix: run one rule's fix in its own undo block
------------------------------------------------------------
-- Returns changed count, message and the before / after audit { problems =, summary = }
function M.fix(d, issues, opts)
  if not d.fix then return 0, "no automatic fix for this check yet" end
  local before = M.snapshot()
  CHANGE_LOG = {}
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, n, msg = pcall(d.fix, issues, M.make_context(opts))
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Session Fix: " .. d.title, -1)
  r.UpdateArrange()
  local problems, summary = M.compare(before, M.snapshot(), d)
  local audit = { problems = problems, summary = summary, log = CHANGE_LOG }
  CHANGE_LOG = nil
  if not ok then return 0, "FIX ERROR: " .. tostring(n), audit end
  return n or 0, msg or "", audit
end

------------------------------------------------------------
-- Select / Mark / Report
------------------------------------------------------------
function M.select_issues(issues)
  r.PreventUIRefresh(1)
  local any_item, any_track = false, false
  for _, is in ipairs(issues) do
    if is.item and r.ValidatePtr2(0, is.item, "MediaItem*") then any_item = true end
    if is.track and not is.item and r.ValidatePtr2(0, is.track, "MediaTrack*") then any_track = true end
  end
  if any_item then r.SelectAllMediaItems(0, false) end
  if any_track then r.Main_OnCommand(40297, 0) end -- Track: Unselect all tracks
  for _, is in ipairs(issues) do
    if is.item and r.ValidatePtr2(0, is.item, "MediaItem*") then
      r.SetMediaItemSelected(is.item, true)
      if is.item2 and r.ValidatePtr2(0, is.item2, "MediaItem*") then r.SetMediaItemSelected(is.item2, true) end
    elseif is.track and r.ValidatePtr2(0, is.track, "MediaTrack*") then
      r.SetTrackSelected(is.track, true)
    end
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

-- Bring an issue into view: horizontally (time) and vertically (its track).
-- Vertical scrolling uses "Track: Vertical scroll selected tracks into view", so the track is
-- selected for a moment and the previous track selection is restored afterwards.
function M.reveal(is, at)
  if M._focused then -- the highlight already zoomed / scrolled there
    M._focused = false
    local p = at or is.pos or (is.item and r.ValidatePtr2(0, is.item, "MediaItem*") and r.GetMediaItemInfo_Value(is.item, "D_POSITION"))
    if p then r.SetEditCurPos(p, false, false) end
    r.UpdateArrange()
    return
  end
  local item = is.item and r.ValidatePtr2(0, is.item, "MediaItem*") and is.item or nil
  local track = item and r.GetMediaItem_Track(item) or (is.track and r.ValidatePtr2(0, is.track, "MediaTrack*") and is.track)
    or (is.scroll_track and r.ValidatePtr2(0, is.scroll_track, "MediaTrack*") and is.scroll_track)
  local pos = at or is.pos or (item and r.GetMediaItemInfo_Value(item, "D_POSITION"))
  if pos then
    local v0, v1 = r.GetSet_ArrangeView2(0, false, 0, 0)
    local len = (v1 or 0) - (v0 or 0)
    if len > 0 and (pos < v0 or pos > v1) then
      r.GetSet_ArrangeView2(0, true, 0, 0, pos - len / 3, pos - len / 3 + len)
    end
    r.SetEditCurPos(pos, false, false)
  end
  if track and track ~= r.GetMasterTrack(0) then
    local prev = {}
    for i = 0, r.CountSelectedTracks(0) - 1 do prev[#prev + 1] = r.GetSelectedTrack(0, i) end
    r.SetOnlyTrackSelected(track)
    r.Main_OnCommand(40913, 0) -- Track: Vertical scroll selected tracks into view
    r.SetTrackSelected(track, false)
    for _, t in ipairs(prev) do r.SetTrackSelected(t, true) end
    if is.track and not is.item then r.SetTrackSelected(track, true) end
  end
  r.UpdateArrange()
end

-- Zoom so the highlighted spot sits in the middle of the arrange view: horizontally the range
-- takes about 2/3 of the width; vertically the tracks of the range are zoomed (REAPER's own
-- vertical zoom, actions 40111 / 40112) so about two more tracks show above and below, then
-- scrolled to the centre. Vertical needs the js_ReaScriptAPI extension (arrange height, scroll).
M.auto_zoom = true
M._focused = false
function M.focus(ranges)
  if not ranges or #ranges == 0 then return false end
  local s, e = math.huge, -math.huge
  local first, last
  for _, g in ipairs(ranges) do
    s, e = math.min(s, g.s), math.max(e, g.e)
    local n = r.GetMediaTrackInfo_Value(g.track, "IP_TRACKNUMBER")
    if not first or n < r.GetMediaTrackInfo_Value(first, "IP_TRACKNUMBER") then first = g.track end
    if not last or n > r.GetMediaTrackInfo_Value(last, "IP_TRACKNUMBER") then last = g.track end
  end
  local view = math.max(e - s, 0.05) * 1.5
  local mid = (s + e) / 2
  r.GetSet_ArrangeView2(0, true, 0, 0, mid - view / 2, mid + view / 2)
  if not (r.JS_Window_FindChildByID and r.JS_Window_GetClientSize and r.JS_Window_SetScrollPos) then return true end
  local arrange = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
  if not arrange then return true end
  local _, _, h = r.JS_Window_GetClientSize(arrange)
  if not h or h <= 0 then return true end
  local ntr = math.floor(r.GetMediaTrackInfo_Value(last, "IP_TRACKNUMBER") - r.GetMediaTrackInfo_Value(first, "IP_TRACKNUMBER")) + 1
  local want = h / (ntr + 4) -- the range's tracks + about two above and two below
  if r.GetMediaTrackInfo_Value(first, "I_HEIGHTOVERRIDE") == 0 then -- a fixed track height ignores zoom
    for _ = 1, 40 do
      local th = r.GetMediaTrackInfo_Value(first, "I_TCPH")
      local cmd = (th > want * 1.2) and 40112 or ((th < want * 0.85) and 40111 or nil) -- zoom out / in vertical
      if not cmd then break end
      r.Main_OnCommand(cmd, 0)
      if r.GetMediaTrackInfo_Value(first, "I_TCPH") == th then break end -- at the limit
    end
  end
  r.TrackList_AdjustWindows(false)
  local top = r.GetMediaTrackInfo_Value(first, "I_TCPY")
  local bottom = r.GetMediaTrackInfo_Value(last, "I_TCPY") + r.GetMediaTrackInfo_Value(last, "I_TCPH")
  local ok, pos = r.JS_Window_GetScrollInfo(arrange, "v")
  if ok then
    r.JS_Window_SetScrollPos(arrange, "v", math.max(0, math.floor(pos + top - (h - (bottom - top)) / 2)))
  end
  return true
end

-- Highlight with razor areas: { { track =, s =, e = }, ... }. Every other razor area is cleared
-- first; time selection and track selection are not touched (track / razor link scripts stay calm).
function M.highlight(ranges)
  local per = {}
  for _, g in ipairs(ranges) do
    if g.track and r.ValidatePtr2(0, g.track, "MediaTrack*") and g.s and g.e and g.e > g.s then
      per[g.track] = per[g.track] or {}
      table.insert(per[g.track], { g.s, g.e })
    end
  end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local _, cur = r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", false)
    if cur ~= "" and not per[tr] then r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", "", true) end
  end
  for tr, list in pairs(per) do
    table.sort(list, function(x, y) return x[1] < y[1] end)
    local merged = {}
    for _, g in ipairs(list) do -- overlapping ranges (e.g. a crossfade) become one
      local last = merged[#merged]
      if last and g[1] <= last[2] then last[2] = math.max(last[2], g[2]) else merged[#merged + 1] = { g[1], g[2] } end
    end
    local parts = {}
    for _, g in ipairs(merged) do parts[#parts + 1] = string.format('%.12f %.12f ""', g[1], g[2]) end
    r.GetSetMediaTrackInfo_String(tr, "P_RAZOREDITS", table.concat(parts, " "), true)
  end
  if M.auto_zoom then
    local list = {}
    for _, g in ipairs(ranges) do if g.track and r.ValidatePtr2(0, g.track, "MediaTrack*") and g.e > g.s then list[#list + 1] = g end end
    M._focused = M.focus(list) -- the next reveal() only moves the edit cursor
  end
  r.UpdateArrange()
end

-- Razor areas on the key spot of these issues only: the item, or for two items (a crossfade) just
-- their overlap. clamp_s / clamp_e (optional) cut every range to that span (e.g. a deleted sliver).
function M.highlight_issues(issues, clamp_s, clamp_e)
  local ranges = {}
  local function add(tr, s, e)
    if clamp_s then s, e = math.max(s, clamp_s), math.min(e, clamp_e) end
    if e > s then ranges[#ranges + 1] = { track = tr, s = s, e = e } end
  end
  for _, is in ipairs(issues) do
    local A = is.item and r.ValidatePtr2(0, is.item, "MediaItem*") and is.item or nil
    local B = is.item2 and r.ValidatePtr2(0, is.item2, "MediaItem*") and is.item2 or nil
    if A and B and r.GetMediaItem_Track(A) == r.GetMediaItem_Track(B) then
      local as, ae = bounds(A)
      local bs, be = bounds(B)
      local s, e = math.max(as, bs), math.min(ae, be)
      if e > s then add(r.GetMediaItem_Track(A), s, e) -- the crossfade itself
      else add(r.GetMediaItem_Track(A), as, ae); add(r.GetMediaItem_Track(B), bs, be) end
    elseif A then
      local s, e = bounds(A)
      add(r.GetMediaItem_Track(A), s, e)
    elseif is.range_track then
      add(is.range_track, is.s, is.e)
    end
  end
  M.highlight(ranges)
end

-- Jump to where something was (e.g. a deleted item): razor area on that track and time range
function M.reveal_range(track, s, e)
  M.highlight({ { track = track, s = s, e = e } })
  M.reveal({ pos = s, scroll_track = track }, s)
end

-- Take marker "Review: <title>" on each issue item (skips items without a take / existing marker)
function M.mark_issues(issues, d)
  local name = M.MARK_PREFIX .. d.title
  local added = 0
  r.Undo_BeginBlock()
  for _, is in ipairs(issues) do
    local it = is.item
    local take = it and r.ValidatePtr2(0, it, "MediaItem*") and r.GetActiveTake(it)
    if take then
      local pos = is.pos or r.GetMediaItemInfo_Value(it, "D_POSITION")
      local srcpos = proj_to_src(take, it, pos)
      local exists = false
      for k = 0, r.GetNumTakeMarkers(take) - 1 do
        local _, mname, mpos = r.GetTakeMarker(take, k)
        if mname == name and math.abs(mpos - srcpos) < 0.001 then exists = true break end
      end
      if not exists and r.SetTakeMarker(take, -1, name, srcpos, 0) >= 0 then added = added + 1 end
    end
  end
  r.Undo_EndBlock("Session Fix: mark " .. d.title, -1)
  r.UpdateArrange()
  return added
end

-- Columns for the issue table: track, position, name
function M.issue_where(is)
  if is.where then return is.where[1], is.where[2], is.where[3] end -- e.g. an item that was deleted
  if is.item and r.ValidatePtr2(0, is.item, "MediaItem*") then
    local take = r.GetActiveTake(is.item)
    return track_name(r.GetMediaItem_Track(is.item)), tc(is.pos or r.GetMediaItemInfo_Value(is.item, "D_POSITION")),
      take and r.GetTakeName(take) or "(empty item)"
  elseif is.track and r.ValidatePtr2(0, is.track, "MediaTrack*") then
    return track_name(is.track), "", ""
  end
  return "", "", ""
end

------------------------------------------------------------
-- Audit: snapshot the project before a fix and compare afterwards, so a fix can never
-- silently move audio. Per item: track, timeline edges, source file and the "sync point"
-- (where source time 0 lands on the timeline: position - offset / playrate). Per track:
-- every crossfade (overlap of two neighbours). Backup ("<track> original") tracks are ignored.
------------------------------------------------------------
local function item_guid(it) local _, g = r.GetSetMediaItemInfo_String(it, "GUID", "", false); return g end

function M.snapshot()
  local snap = { items = {}, xf = {}, time = os.date("%H:%M:%S") }
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if not is_backup_track(tr) then
      local tg = r.GetTrackGUID(tr)
      local list = sorted_items(tr)
      for k, e in ipairs(list) do
        local take = r.GetActiveTake(e.it)
        local rec = { item = e.it, track = tg, track_ptr = tr, s = e.s, e = e.e, src = "", sync = nil,
          where = { track_name(tr), tc(e.s), take and r.GetTakeName(take) or "(empty item)" } }
        if take then
          rec.src = select(2, take_source_file(take)) or ""
          local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"); if rate <= 0 then rate = 1 end
          rec.sync = e.s - r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") / rate
        end
        e.g = item_guid(e.it)
        snap.items[e.g] = rec
        local prev = list[k - 1]
        if prev and prev.e > e.s then snap.xf[prev.g .. "|" .. e.g] = { s = e.s, e = math.min(prev.e, e.e), a = prev.g, b = e.g } end
      end
    end
  end
  return snap
end

-- Compare two snapshots. d = the rule that ran (nil = everything allowed: "verify vs. start").
-- Returns problems { level = "red" | "yellow", item=, where=, pos=, text= } and a summary.
function M.compare(before, after, d)
  local sr = project_sr()
  local eps = 1.5 / sr -- a sample and a half
  local frame = 1 / r.TimeMap_curFrameRate(0)
  local may_delete = (d == nil) or d.may_delete
  local moves_edges = (d == nil) or d.moves_edges
  local renders = (d == nil) or d.renders
  local out, changed, deleted, rendered, snapped, relinked = {}, 0, 0, 0, 0, 0
  local function base(path) return (path or ""):match("([^/\\]+)$") or "" end
  local function add(level, rec, cur, text)
    out[#out + 1] = { level = level, item = cur and cur.item or nil, where = (not cur) and rec.where or nil,
      pos = (cur or rec).s, text = text, range_track = rec.track_ptr, s = rec.s, e = rec.e }
  end
  local function ms(x) return string.format("%.1f ms", x * 1000) end
  for g, b in pairs(before.items) do
    local a = after.items[g]
    if not a then
      deleted = deleted + 1
      add(may_delete and "yellow" or "red", b, nil, may_delete and "item deleted (expected for this fix, please check)" or "item deleted")
    else
      local any = false
      if a.track ~= b.track then add("red", b, a, "item moved to another track"); any = true end
      local ds, de = a.s - b.s, a.e - b.e
      if math.abs(ds) > eps or math.abs(de) > eps then
        any = true
        local edge = (math.abs(ds) > eps and "start " .. ms(ds) or "") .. ((math.abs(ds) > eps and math.abs(de) > eps) and ", " or "")
          .. (math.abs(de) > eps and "end " .. ms(de) or "")
        if moves_edges and math.abs(ds) <= frame + eps and math.abs(de) <= frame + eps then
          snapped = snapped + 1
        else
          add(a.src ~= b.src and "red" or "yellow", b, a, "edge moved: " .. edge)
        end
      end
      local same_file = a.src == b.src or (a.src ~= "" and base(a.src) == base(b.src)) -- same file name: copied / relinked
      if a.src ~= b.src and same_file then relinked = relinked + 1; any = true end
      if not same_file then
        any = true
        if renders then rendered = rendered + 1 else add("red", b, a, "source file changed: " .. b.src .. " -> " .. a.src) end
      elseif a.sync and b.sync and math.abs(a.sync - b.sync) > eps then
        add("red", b, a, "audio content moved by " .. ms(a.sync - b.sync)); any = true
      end
      if any then changed = changed + 1 end
    end
  end
  for g, a in pairs(after.items) do
    if not before.items[g] then add("yellow", a, a, "new item"); changed = changed + 1 end
  end
  for key, x in pairs(before.xf) do
    if after.items[x.a] and after.items[x.b] then
      local y = after.xf[key]
      if not y then
        out[#out + 1] = { level = "red", item = after.items[x.b].item, pos = x.s, text = "crossfade removed (the two items no longer overlap)" }
      elseif math.abs(y.s - x.s) > eps or math.abs(y.e - x.e) > eps then
        out[#out + 1] = { level = "red", item = after.items[x.b].item, pos = x.s,
          text = string.format("crossfade moved: start %s, end %s", ms(y.s - x.s), ms(y.e - x.e)) }
      end
    end
  end
  table.sort(out, function(p, q) if p.level ~= q.level then return p.level == "red" end return (p.pos or 0) < (q.pos or 0) end)
  local reds = 0
  for _, p in ipairs(out) do if p.level == "red" then reds = reds + 1 end end
  return out, { changed = changed, deleted = deleted, rendered = rendered, snapped = snapped, relinked = relinked, red = reds, yellow = #out - reds }
end

-- Plain-text report (for BEFORE / AFTER comparisons)
function M.report(results, summary)
  local _, proj_path = r.EnumProjects(-1, "")
  local lines = {
    "Session Fix - Interchange Prep report",
    "Project : " .. ((proj_path ~= "" and proj_path) or "(unsaved)"),
    "Date    : " .. os.date("%Y-%m-%d %H:%M:%S"),
    string.format("Scanned : %d tracks, %d items, %.3f fps, %d Hz", summary.tracks, summary.items, summary.fps, summary.sr),
    string.format("Issues  : %d", summary.total),
    "",
  }
  for _, d in ipairs(RULES) do
    local list = results[d.id] or {}
    lines[#lines + 1] = string.format("[%s] %s: %d", #list == 0 and "OK" or "!!", d.title, #list)
    for _, is in ipairs(list) do
      local where = is.item and r.ValidatePtr2(0, is.item, "MediaItem*") and item_label(is.item)
        or (is.track and r.ValidatePtr2(0, is.track, "MediaTrack*") and track_name(is.track)) or ""
      lines[#lines + 1] = "    " .. (where ~= "" and (where .. "  —  ") or "") .. (is.text or "")
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
