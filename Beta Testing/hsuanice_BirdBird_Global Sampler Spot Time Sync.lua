--[[
@description BirdBird Global Sampler — Spot Time Sync
@version 260427.0034
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
-- Main
----------------------------------------------------------------
local function finalize(track, before_set, params)
  local it = find_new_item(track, before_set)
  if not it then return false end

  reaper.PreventUIRefresh(1)
  reaper.Undo_BeginBlock()

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

  -- BWF time_reference: project-time of the FIRST sample in the wav
  -- = play_start_pp - left_handle_secs, expressed in samples-from-project-zero.
  local active_take = reaper.GetActiveTake(it)
  local wav = take_wav_path(active_take)
  if E and wav and E.CLI_Resolve and E.TR_Write and E.SecToSamples then
    local cli = E.CLI_Resolve()
    if cli then
      local first_sample_pp = params.play_start_pp - startoffs_sec
      if first_sample_pp < 0 then first_sample_pp = 0 end
      local tr_samples = E.SecToSamples(params.srate, first_sample_pp)
      E.TR_Write(cli, wav, tr_samples)
      -- Force offline → online so REAPER re-reads the freshly written
      -- BWF header (a soft refresh isn't enough — the PCM source is cached).
      if E.Refresh_Items then
        E.Refresh_Items({it})
      end
    end
  end

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
