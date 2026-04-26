--[[
@description BirdBird Global Sampler — Spot Time Sync
@version 260427.0025
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
    return err("Global Sampler JSFX is not patched for time sync.\nExpected gmem[15]=len_in_secs and gmem[17]=srate to be populated.\nSee the Spot Time Sync script header for the patch.")
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
