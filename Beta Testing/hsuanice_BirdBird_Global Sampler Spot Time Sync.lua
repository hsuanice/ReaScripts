--[[
@description BirdBird Global Sampler — Spot Time Sync
@version 260503.2120
@author hsuanice
@about
  Spot the most recent play→stop session captured in BirdBird Global
  Sampler's circular buffer onto the timeline at its original project
  position, with pre/post-roll handles preserved.

  Workflow
  --------
    1. Make sure the Time Sync Daemon is ON (paired script).
    2. Press play (or record), do your thing, stop.
    3. Run this action.
    4. The buffer audio captured during that play session appears as
       an item on the GS JSFX track, sized to the play duration and
       positioned at the original play-start project time. Audio
       captured before play started (and after stop, up to the moment
       you ran this action) is preserved as left/right handles — drag
       the item edges to reveal them.
    5. The dumped wav also gets a BWF time_reference written via
       bwfmetaedit, so a later "Spot to BWF time reference" workflow
       will land the item back at its original chronological position.

  Caveats
  -------
    * Only the most recent play→stop session is recoverable. Run this
      before starting another play, or you will lose the previous one.
      (Buffer keeps audio for `len_in_secs` of real time regardless.)
    * Stop the transport before running. If transport is still playing,
      the action will refuse.
    * Item is placed on the track that hosts the GS JSFX. If the JSFX
      is on Master / Monitor FX, the action refuses (REAPER can't put
      items on those).
    * Overlapping items on the target track are NOT auto-routed to
      fixed lanes — they overlap. Set the target track to fixed lanes
      mode yourself if you want lane separation.

  Requires
  --------
    * Daemon running: `hsuanice_BirdBird_Global Sampler Time Sync Daemon.lua`
    * BirdBird Global Sampler JSFX patched to expose:
        gmem[15] = len_in_secs
        gmem[17] = srate
        gmem[18] = play_start (project seconds)
        gmem[19] = play_start_counter (mono buf_pos index at play start)
        gmem[20] = play_counter (mono sample frames since play start;
                                 final value is written on play stop)
    * `hsuanice_Metadata Embed.lua` library + bwfmetaedit CLI
      (auto-resolves on first run)

@changelog
  v260503.2120
    - Fix: spotted item now shows a proper waveform. Previously the
      file rename + source swap left REAPER without a peak file for
      the new path:
        * call PCM_Source_BuildPeaks(new_src, 0) right after
          SetMediaItemTake_Source so peak generation kicks off
        * always run E.Refresh_Items (offline → online toggle) at
          the end of finalize, not just inside the BWF block —
          the toggle is needed for the renamed source even when
          BWF wasn't written
        * additionally call action 40441 (Build any missing peaks)
          since the Library has the peak rebuild commented out
        * inline fallback for the offline/online toggle when the
          Library isn't installed
  v260427.1140
    - Naming order changed to <SOURCE>_<GS_NAME>_<TIMESTAMP>-jsfx
      (source track first). Zero-source case unchanged
      (just <GS_NAME>_<TIMESTAMP>-jsfx).
  v260427.1115
    - Spotted item now reflects its source track in both the wav
      filename and the take display name. Sources are detected as
      tracks that are record-armed AND have a send to the GS track,
      checked at spot time. Multiple armed sources are joined with
      "+", e.g. `Vocal+Guitar`. Naming format:
        <GS_TRACK_NAME>_<SOURCE>_<YYMMDD_HHMM>-jsfx.wav
      (no source segment if zero matches). The original BirdBird
      timestamp is reused so file/take stay consistent. The wav
      file plus its `.reapeaks` are renamed on disk; the take's
      source is replaced via PCM_Source_CreateFromFile so REAPER
      tracks the new path. If file rename fails (e.g. cross-volume),
      the take display name is still updated and the BWF write
      falls back to the original path.
  v260427.0034
    - Auto-detect missing JSFX patch and offer to apply it. When
      gmem[15]/gmem[17] read 0, the script locates the JSFX file under
      reaper.GetResourcePath(), checks for the `hsuanice sync addition`
      marker, and if missing prompts the user to apply the patch
      (5 lines, two splice points). On success the user is asked to
      remove and re-insert the JSFX so the running instance reloads.
      Reports clear errors for missing file, mismatched anchors
      (BirdBird update), and write failures.
  v260427.0025
    - Initial release.
    - Spot the most recent play→stop session from BirdBird's circular
      buffer onto the timeline at its original project position, with
      pre/post-roll handles preserved.
    - Writes BWF time_reference (= project-time of the wav's first
      sample, in samples from project zero) via bwfmetaedit, then
      forces offline → online so REAPER re-reads the new header.
]]--

local NS = "hsuanice_GS_TimeSync"

----------------------------------------------------------------
-- Library
----------------------------------------------------------------
local SCRIPT_FILE = ({reaper.get_action_context()})[2]
local SCRIPT_DIR  = SCRIPT_FILE:match("^(.*)[/\\]") or ""
local LIB_DIR     = (SCRIPT_DIR:gsub("Beta Testing$", "Library"))
local EMBED_PATH  = LIB_DIR .. "/hsuanice_Metadata Embed.lua"

local E
do
  local ok, lib = pcall(dofile, EMBED_PATH)
  if ok and type(lib) == "table" then E = lib end
end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function err(msg)
  reaper.MB(msg, "GS Spot Time Sync", 0)
end

local function check_daemon_alive()
  local last_hb = tonumber(reaper.GetExtState(NS, "daemon_heartbeat")) or 0
  return (reaper.time_precise() - last_hb) < 1.0
end

local function find_GS_track()
  local fx_name = "Global Sampler"
  local master  = reaper.GetMasterTrack(0)

  if reaper.TrackFX_GetByName(master, fx_name, false) ~= -1 then
    return nil, "GS JSFX is on the Master track. Move it to a regular track to use Spot Time Sync (or use BirdBird's drag instead)."
  end

  if reaper.TrackFX_AddByName(master, fx_name, true, 0) ~= -1 then
    return nil, "GS JSFX is on Monitor FX. Move it to a regular track to use Spot Time Sync (or use BirdBird's drag instead)."
  end

  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if reaper.TrackFX_GetByName(tr, fx_name, false) ~= -1 then
      return tr, nil
    end
  end

  return nil, "Global Sampler JSFX not found in this project."
end

----------------------------------------------------------------
-- JSFX patch detection & auto-apply
----------------------------------------------------------------
local function read_text_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function write_text_file(path, content)
  local f, err_open = io.open(path, "wb")
  if not f then return false, err_open end
  f:write(content)
  f:close()
  return true
end

local function find_jsfx_path()
  local p = reaper.GetResourcePath()
    .. "/Effects/BirdBird ReaScript Testing/Global Sampler/BirdBird_Global Sampler.jsfx"
  if read_text_file(p) then return p end
  return nil
end

local function splice(haystack, needle, replacement)
  local s, e = haystack:find(needle, 1, true)
  if not s then return nil end
  return haystack:sub(1, s - 1) .. replacement .. haystack:sub(e + 1)
end

-- The two anchor strings must match upstream BirdBird's JSFX exactly.
-- If BirdBird ever ships a JSFX whose surrounding code differs, splice
-- returns nil and the patcher reports a clear failure (no silent harm).
local PATCH_ANCHOR_1_OLD = [[  preview_delick_len = 0.01;
  last_srate = srate;
);]]

local PATCH_ANCHOR_1_NEW = [[  preview_delick_len = 0.01;
  last_srate = srate;

  // hsuanice sync addition: expose buffer length and srate for time-sync scripts
  gmem[15] = len_in_secs;
  gmem[17] = srate;
);]]

local PATCH_ANCHOR_2_OLD = [[      play_start_counter = counter;
      playback = 1;
    );
    play_state == 0 ? (
      playback = 0;
    );]]

local PATCH_ANCHOR_2_NEW = [[      play_start_counter = counter;
      playback = 1;

      // hsuanice sync addition: expose play session start
      gmem[18] = play_start;
      gmem[19] = play_start_counter;
      gmem[20] = 0;
    );
    play_state == 0 ? (
      playback = 0;

      // hsuanice sync addition: expose final play_counter on stop
      gmem[20] = play_counter;
    );]]

-- Returns: status, info
--   status = "ok"          → patched successfully (info = path)
--   status = "already"     → already patched on disk (info = path)
--   status = "missing"     → couldn't locate JSFX file (info = expected path)
--   status = "anchor_fail" → file found but anchor strings didn't match (info = path)
--   status = "write_fail"  → couldn't write file (info = error message)
local function ensure_jsfx_patched()
  local jsfx_path = find_jsfx_path()
  if not jsfx_path then
    return "missing",
      reaper.GetResourcePath()
        .. "/Effects/BirdBird ReaScript Testing/Global Sampler/BirdBird_Global Sampler.jsfx"
  end

  local content = read_text_file(jsfx_path)
  if not content then return "missing", jsfx_path end
  if content:find("hsuanice sync addition", 1, true) then
    return "already", jsfx_path
  end

  local r1 = splice(content,            PATCH_ANCHOR_1_OLD, PATCH_ANCHOR_1_NEW)
  if not r1 then return "anchor_fail", jsfx_path end
  local r2 = splice(r1,                 PATCH_ANCHOR_2_OLD, PATCH_ANCHOR_2_NEW)
  if not r2 then return "anchor_fail", jsfx_path end

  local ok, write_err = write_text_file(jsfx_path, r2)
  if not ok then return "write_fail", tostring(write_err or "unknown") end
  return "ok", jsfx_path
end

-- Called when gmem[15] / gmem[17] read 0 — JSFX not exposing sync slots.
-- Returns true if user opted to retry (after applying patch + reloading).
local function offer_patch_dialog()
  local jsfx_path = find_jsfx_path()
  if jsfx_path then
    local content = read_text_file(jsfx_path)
    if content and content:find("hsuanice sync addition", 1, true) then
      err(
        "JSFX file is already patched, but the running instance hasn't picked it up.\n\n"
        .. "Remove and re-insert the Global Sampler JSFX (right-click the FX → Remove,\n"
        .. "then re-add it), then run this action again.\n\nFile: " .. jsfx_path
      )
      return false
    end
  end

  local prompt =
    "BirdBird Global Sampler JSFX is not patched for time sync.\n\n"
    .. "The patch adds 5 lines to the JSFX exposing buffer length, srate, and the\n"
    .. "current play-session counters via gmem. It does not change any of BirdBird's\n"
    .. "existing behavior.\n\n"
    .. "Apply the patch automatically?"
  local ans = reaper.MB(prompt, "Spot Time Sync — JSFX patch needed", 4) -- 4 = Yes/No
  if ans ~= 6 then return false end

  local status, info = ensure_jsfx_patched()
  if status == "ok" then
    err(
      "JSFX patched successfully.\n\n"
      .. "Now remove and re-insert the Global Sampler JSFX (right-click the FX → Remove,\n"
      .. "then re-add it) so the running instance picks up the changes.\n\n"
      .. "After that, run Spot Time Sync again.\n\nFile: " .. info
    )
  elseif status == "already" then
    err("JSFX is already patched on disk. Remove and re-insert the JSFX to load it.\nFile: " .. info)
  elseif status == "missing" then
    err(
      "Could not locate the Global Sampler JSFX file. Expected at:\n" .. info
      .. "\n\nIf BirdBird is installed in a non-standard location, apply the patch\n"
      .. "manually — see the Spot Time Sync script header for the 5 lines."
    )
  elseif status == "anchor_fail" then
    err(
      "JSFX file found but its source does not match the expected layout.\n"
      .. "(BirdBird may have shipped an update.)\n\n"
      .. "Apply the patch manually — see the Spot Time Sync script header.\n\nFile: " .. info
    )
  elseif status == "write_fail" then
    err("Failed to write JSFX file (permissions?): " .. info)
  end
  return false
end

local function snapshot_item_guids(track)
  local set = {}
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    set[g] = true
  end
  return set
end

local function find_new_item(track, before_set)
  for i = 0, reaper.CountTrackMediaItems(track) - 1 do
    local it = reaper.GetTrackMediaItem(track, i)
    local _, g = reaper.GetSetMediaItemInfo_String(it, "GUID", "", false)
    if not before_set[g] then return it end
  end
  return nil
end

local function take_wav_path(take)
  if not take then return nil end
  local src = reaper.GetMediaItemTake_Source(take)
  if not src then return nil end
  local fn = reaper.GetMediaSourceFileName(src, "")
  if fn and fn ~= "" then return fn end
  return nil
end

----------------------------------------------------------------
-- Source-track detection & file/take renaming
----------------------------------------------------------------
local function track_name_or_default(tr, fallback)
  local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  if name and name ~= "" then return name end
  return fallback
end

local function track_index_1based(tr)
  return math.floor(reaper.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))
end

-- Tracks that are record-armed AND have at least one send to gs_track.
local function find_armed_source_tracks(gs_track)
  local out = {}
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr ~= gs_track and reaper.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then
      local n = reaper.GetTrackNumSends(tr, 0) -- 0 = sends from this track
      for s = 0, n - 1 do
        local dest = reaper.GetTrackSendInfo_Value(tr, 0, s, "P_DESTTRACK")
        if dest == gs_track then
          out[#out + 1] = tr
          break
        end
      end
    end
  end
  return out
end

-- Strip filesystem-illegal chars and control chars; trim whitespace.
local function sanitize_for_filename(s)
  s = (s or ""):gsub('[\\/:*?"<>|]', "_")
  s = s:gsub("%c", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- Compose the new basename (no extension). Format:
--   <GS_NAME>_<SRC1+SRC2+...>_<YYMMDD_HHMM>-jsfx
-- If no source tracks: <GS_NAME>_<YYMMDD_HHMM>-jsfx
-- Timestamp is reused from the original BirdBird filename when possible
-- so file/take/JSFX-side timestamps stay consistent.
local function compute_new_basename(gs_track, source_tracks, original_basename)
  local gs_name = sanitize_for_filename(
    track_name_or_default(gs_track, "Global Sampler"))

  local source_str = ""
  if #source_tracks > 0 then
    local names = {}
    for _, tr in ipairs(source_tracks) do
      local fb = "Track" .. tostring(track_index_1based(tr))
      names[#names + 1] = sanitize_for_filename(track_name_or_default(tr, fb))
    end
    source_str = table.concat(names, "+")
  end

  local ts = original_basename and original_basename:match("(%d+_%d+)%-jsfx") or nil
  if not ts then ts = os.date("%y%m%d_%H%M") end

  if source_str ~= "" then
    return string.format("%s_%s_%s-jsfx", source_str, gs_name, ts)
  end
  return string.format("%s_%s-jsfx", gs_name, ts)
end

-- Rename the wav (and .reapeaks) on disk and replace the take's source.
-- Returns the new path on success, or (nil, errmsg) on failure. Caller
-- should still update the take display name regardless of return.
local function rename_dumped_file(take, new_basename)
  local cur_src = reaper.GetMediaItemTake_Source(take)
  if not cur_src then return nil, "no source" end
  local cur_path = reaper.GetMediaSourceFileName(cur_src, "")
  if not cur_path or cur_path == "" then return nil, "no path" end

  local cur_dir = cur_path:match("^(.*[/\\])") or ""
  local new_path = cur_dir .. new_basename .. ".wav"
  if cur_path == new_path then return new_path end

  local ok, rename_err = os.rename(cur_path, new_path)
  if not ok then return nil, rename_err or "os.rename failed" end
  os.rename(cur_path .. ".reapeaks", new_path .. ".reapeaks") -- best effort

  local new_src = reaper.PCM_Source_CreateFromFile(new_path)
  if not new_src then return nil, "PCM_Source_CreateFromFile failed" end
  reaper.SetMediaItemTake_Source(take, new_src)
  -- Kick off async peak generation for the freshly-assigned source.
  -- Without this, REAPER may not auto-trigger peaks for sources that
  -- were swapped in via SetMediaItemTake_Source (vs. files it created
  -- itself), leaving the spotted item with a blank waveform.
  reaper.PCM_Source_BuildPeaks(new_src, 0)

  return new_path
end

----------------------------------------------------------------
-- Main
----------------------------------------------------------------
local function finalize(track, before_set, params)
  local it = find_new_item(track, before_set)
  if not it then return false end

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

  local active_take = reaper.GetActiveTake(it)

  -- 1. Rename file + take to include source track name(s).
  local cur_path     = take_wav_path(active_take) or ""
  local cur_basename = cur_path:match("([^/\\]+)%.wav$") or ""
  local sources      = find_armed_source_tracks(track)
  local new_basename = compute_new_basename(track, sources, cur_basename)
  local new_path     = rename_dumped_file(active_take, new_basename) or cur_path
  if active_take then
    reaper.GetSetMediaItemTakeInfo_String(active_take, "P_NAME", new_basename, true)
  end

  -- 2. Position, length, source-start offset (= left handle).
  local startoffs_sec = params.left_handle_frames / params.srate
  local visible_sec   = params.play_counter      / params.srate

  reaper.SetMediaItemInfo_Value(it, "D_POSITION", params.play_start_pp)
  reaper.SetMediaItemInfo_Value(it, "D_LENGTH",   visible_sec)
  for t = 0, reaper.CountTakes(it) - 1 do
    local tk = reaper.GetTake(it, t)
    if tk then
      reaper.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", startoffs_sec)
    end
  end

  -- 3. BWF time_reference = project-time of the wav's FIRST sample,
  --    expressed in samples from project zero.
  if E and new_path ~= "" and E.CLI_Resolve and E.TR_Write and E.SecToSamples then
    local cli = E.CLI_Resolve()
    if cli then
      local first_sample_pp = params.play_start_pp - startoffs_sec
      if first_sample_pp < 0 then first_sample_pp = 0 end
      local tr_samples = E.SecToSamples(params.srate, first_sample_pp)
      E.TR_Write(cli, new_path, tr_samples)
    end
  end

  -- 4. Refresh source: forces REAPER to re-read the BWF header (when
  --    written above) AND triggers peak rebuild for the renamed source.
  --    Always run, regardless of BWF availability — without this the
  --    spotted item shows a blank waveform.
  if E and E.Refresh_Items then
    E.Refresh_Items({it})
  else
    -- Inline fallback when the Library isn't available
    reaper.SelectAllMediaItems(0, false)
    reaper.SetMediaItemSelected(it, true)
    reaper.UpdateArrange()
    reaper.Main_OnCommand(42356, 0) -- Toggle force media offline
    reaper.Main_OnCommand(42356, 0) -- Toggle back online
  end
  reaper.Main_OnCommand(40441, 0) -- Item: Build any missing peaks for selected items

  reaper.SetMediaItemSelected(it, true)

  reaper.Undo_EndBlock("GS Spot Time Sync", -1)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  return true
end

local function main()
  if not check_daemon_alive() then
    return err("Time Sync Daemon is not running. Toggle it ON first.")
  end

  local ps = reaper.GetPlayState()
  if (ps & 1) == 1 or (ps & 4) == 4 then
    return err("Stop the transport before running Spot Time Sync.")
  end

  reaper.gmem_attach("BB_Sampler")

  if reaper.gmem_read(5) ~= 1 then
    return err("BirdBird Global Sampler JSFX not initialized. Insert it first (run BirdBird's main script once).")
  end

  local len_in_secs = reaper.gmem_read(15)
  local srate       = reaper.gmem_read(17)
  if len_in_secs <= 0 or srate <= 0 then
    offer_patch_dialog()
    return
  end

  local play_start_pp      = reaper.gmem_read(18)
  local play_start_counter = reaper.gmem_read(19)
  local play_counter       = reaper.gmem_read(20)
  local counter_norm       = reaper.gmem_read(4)

  if play_counter <= 0 then
    return err("No completed play→stop session in buffer.\nPress play, do something, stop, then run this again.")
  end

  local track, msg = find_GS_track()
  if not track then return err(msg) end

  -- Buffer math
  local buf_len_mono   = len_in_secs * srate * 2          -- mono indices in buf_pos[]
  local total_frames   = len_in_secs * srate              -- stereo frames in buffer
  local counter_mono   = math.floor(counter_norm * buf_len_mono + 0.5)

  -- The dumped wav (type-3, sn=counter_norm, wn=1.0) starts at the current
  -- writer position and proceeds in chronological order, wrapping the ring.
  -- The first sample in the wav corresponds to buf_pos[counter_mono].
  -- play_start_counter is also a mono index. The play-start audio sits at
  -- offset (play_start_counter - counter_mono) mod buf_len_mono in the wav.
  local left_offset_mono   = (play_start_counter - counter_mono) % buf_len_mono
  local left_handle_frames = math.floor(left_offset_mono / 2 + 0.5)

  if play_counter >= total_frames then
    play_counter = total_frames - left_handle_frames - 1
    if play_counter <= 0 then
      return err("Play session was longer than the JSFX buffer; nothing to spot.")
    end
  end

  if left_handle_frames + play_counter > total_frames then
    return err("Buffer math sanity check failed (offsets out of range).")
  end

  -- Snapshot current items so we can find the new one
  local before_set = snapshot_item_guids(track)

  local track_num = math.floor(reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  if track_num <= 0 then
    return err("Could not resolve target track number.")
  end

  -- Trigger BirdBird dump (type 3 = normalized range).
  -- Start at current writer position, width = full buffer → chronological dump.
  reaper.gmem_write(2, track_num)
  reaper.gmem_write(6, counter_norm)
  reaper.gmem_write(7, 1.0)
  reaper.gmem_write(1, 3)
  reaper.gmem_write(0, 1)

  local params = {
    play_start_pp      = play_start_pp,
    play_counter       = play_counter,
    left_handle_frames = left_handle_frames,
    srate              = srate,
  }

  local deadline = reaper.time_precise() + 5.0

  local function wait_loop()
    if reaper.time_precise() > deadline then
      return err("Dump timed out (5 s). The JSFX may not be processing — check that audio is flowing through it.")
    end
    if reaper.gmem_read(0) ~= 0 then
      return reaper.defer(wait_loop)
    end
    if not finalize(track, before_set, params) then
      return reaper.defer(wait_loop)
    end
  end

  reaper.defer(wait_loop)
end

main()
