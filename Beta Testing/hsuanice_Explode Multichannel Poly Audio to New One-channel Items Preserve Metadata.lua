--[[
@description hsuanice_Explode Multichannel Poly Audio to New One-channel Items Preserve Metadata
@version 260712.1135
@author hsuanice
@about
  Workflow script for poly WAV production:
    1) Explode selected multichannel items to new one-channel items on new tracks (non-destructive).
    2) Render each exploded mono item to a new take with command 40601.
    3) Re-embed metadata from Take 1 to the rendered active take using hsuanice_Metadata Embed.lua.

  Notes:
    - Explode step preserves the original source in Take 1.
    - Render step creates a new mono file in the active take.
    - Metadata embed is channel-aware, so mono outputs receive the matching track/channel name.
    - Track/take naming currently follows Rodilab-style numeric suffixes for easy later adjustment.

  Requirements:
    - BWF MetaEdit CLI available to the Metadata Embed library.
    - hsuanice_Metadata Embed.lua in the hsuanice Scripts/Library folder.

@changelog
  260712.1135 - Fixed channel 1 mapping and reduced final refresh overhead
             - Corrected mono-of-N chanmode mapping so channel 1 is no longer skipped during explode.
             - Removed an extra final arrange refresh when batch media refresh already ran.

  260711.2323 - Initial version
             - Added explode -> render to new take -> metadata re-embed workflow.
             - Uses non-destructive mono-of-N explode before rendering.
             - Uses shared Metadata Embed library APIs for channel-aware metadata preservation.
]]

local R = reaper

local ACT_UNSELECT_ALL_ITEMS = 40769
local ACT_COPY_ITEMS = 40698
local ACT_PASTE_ITEMS_TRACK = 42398
local ACT_NEXT_TRACK = 40285
local ACT_RENDER_TO_NEW_TAKE_PRESERVE = 40601

local TRACK_NAME_SUFFIX_MODE = "index"
local TAKE_NAME_SUFFIX_MODE = "index"

local function msg(text)
  R.ShowConsoleMsg(tostring(text) .. "\n")
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function load_first(cands)
  for _, path in ipairs(cands) do
    if exists(path) then
      local ok, mod = pcall(dofile, path)
      if ok and type(mod) == "table" then return mod, path end
    end
  end
  return nil, nil
end

local RES = R.GetResourcePath()
local LIB_EMB_CANDS = {
  RES .. "/Scripts/hsuanice Scripts/Library/hsuanice_Metadata Embed.lua",
  RES .. "/Scripts/hsuanice_Scripts/Library/hsuanice_Metadata Embed.lua",
  RES .. "/Scripts/hsuanice/Library/hsuanice_Metadata Embed.lua",
  RES .. "/Scripts/Library/hsuanice_Metadata Embed.lua",
}

local EMB, EMB_PATH = load_first(LIB_EMB_CANDS)
if not EMB then
  R.MB("Cannot load hsuanice_Metadata Embed.lua", "Explode Preserve Metadata", 0)
  return
end

local function get_selected_items()
  local items = {}
  local count = R.CountSelectedMediaItems(0)
  for i = 0, count - 1 do
    items[#items + 1] = R.GetSelectedMediaItem(0, i)
  end
  return items
end

local function get_take_name_safe(take)
  if not take then return "" end
  local _, name = R.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  return name or ""
end

local function get_track_name_safe(track)
  if not track then return "" end
  local _, name = R.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return name or ""
end

local function source_channel_count(take)
  if not take then return 0 end
  local source = R.GetMediaItemTake_Source(take)
  return source and (R.GetMediaSourceNumChannels(source) or 0) or 0
end

local function effective_take_channel_count(take)
  if not take then return 0 end
  local source_chan = source_channel_count(take)
  local take_chanmode = R.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0
  if source_chan > 1 and take_chanmode < 2 then
    return source_chan
  elseif source_chan > 1 and take_chanmode > 66 then
    return 2
  else
    return 1
  end
end

local function set_exploded_chanmode(new_take, source_take_chanmode, split_index)
  if source_take_chanmode == 0 then
    R.SetMediaItemTakeInfo_Value(new_take, "I_CHANMODE", split_index + 2)
  elseif source_take_chanmode == 1 then
    R.SetMediaItemTakeInfo_Value(new_take, "I_CHANMODE", split_index + 2)
  elseif source_take_chanmode > 66 then
    R.SetMediaItemTakeInfo_Value(new_take, "I_CHANMODE", (source_take_chanmode - 67) + split_index + 2)
  end
end

local function build_track_name(base_name, chan_index)
  if TRACK_NAME_SUFFIX_MODE == "index" then
    return string.format("%s - %d", base_name, chan_index)
  end
  return base_name
end

local function build_take_name(base_name, chan_index)
  if TAKE_NAME_SUFFIX_MODE == "index" then
    return string.format("%s - %d", base_name, chan_index)
  end
  return base_name
end

local TRACK_PARNAMES = {
  "B_MUTE", "B_PHASE", "B_RECMON_IN_EFFECT", "I_SOLO", "I_FXEN", "I_RECARM",
  "I_RECINPUT", "I_RECMODE", "I_RECMON", "I_RECMONITEMS", "I_AUTOMODE", "I_FOLDERCOMPACT",
  "I_PERFFLAGS", "I_CUSTOMCOLOR", "I_HEIGHTOVERRIDE", "B_HEIGHTLOCK", "D_VOL", "D_PAN",
  "D_WIDTH", "D_DUALPANL", "D_DUALPANR", "I_PANMODE", "D_PANLAW", "B_SHOWINMIXER",
  "B_SHOWINTCP", "B_MAINSEND", "C_MAINSEND_OFFS", "C_BEATATTACHMODE", "F_MCP_FXSEND_SCALE",
  "F_MCP_FXPARM_SCALE", "F_MCP_SENDRGN_SCALE", "F_TCP_FXPARM_SCALE", "I_PLAY_OFFSET_FLAG",
  "D_PLAY_OFFSET",
}

local function copy_track_settings(src_track, dst_track)
  for _, parname in ipairs(TRACK_PARNAMES) do
    R.SetMediaTrackInfo_Value(dst_track, parname, R.GetMediaTrackInfo_Value(src_track, parname))
  end
end

local function select_only_item(item)
  R.SelectAllMediaItems(0, false)
  if item then R.SetMediaItemSelected(item, true) end
end

local function get_selected_item_if_any()
  return R.GetSelectedMediaItem(0, 0)
end

local function explode_selected_items_to_new_tracks(items)
  local new_items = {}
  local new_tracks = {}
  local previous_track = nil
  local track_max_chan = 1

  for _, item in ipairs(items) do
    local take = R.GetActiveTake(item)
    if take then
      local source = R.GetMediaItemTake_Source(take)
      if source and (R.GetMediaSourceSampleRate(source) or 0) > 0 then
        local track = R.GetMediaItem_Track(item)
        local track_id = R.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        local take_name = get_take_name_safe(take)
        local track_name = get_track_name_safe(track)
        local take_chanmode = R.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") or 0
        local take_chan = effective_take_channel_count(take)
        local position = R.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = R.GetMediaItemInfo_Value(item, "D_LENGTH")
        local playrate = R.GetMediaItemInfo_Value(item, "D_PLAYRATE")

        if take_chan > 1 then
          if track == previous_track then
            if track_max_chan < take_chan then
              for j = 0, take_chan - track_max_chan - 1 do
                R.InsertTrackAtIndex(track_id + track_max_chan + j, true)
                local new_track = R.GetTrack(0, track_id + track_max_chan + j)
                new_tracks[#new_tracks + 1] = new_track
                R.GetSetMediaTrackInfo_String(new_track, "P_NAME", build_track_name(track_name, j + track_max_chan + 1), true)
                copy_track_settings(track, new_track)
              end
              track_max_chan = take_chan
            end
          else
            track_max_chan = take_chan
            for j = 0, take_chan - 1 do
              R.InsertTrackAtIndex(track_id + j, true)
              local new_track = R.GetTrack(0, track_id + j)
              new_tracks[#new_tracks + 1] = new_track
              R.GetSetMediaTrackInfo_String(new_track, "P_NAME", build_track_name(track_name, j + 1), true)
              copy_track_settings(track, new_track)
            end
          end

          previous_track = track

          R.Main_OnCommand(ACT_UNSELECT_ALL_ITEMS, 0)
          R.SetMediaItemSelected(item, true)
          R.Main_OnCommand(ACT_COPY_ITEMS, 0)
          R.SetEditCurPos(position, false, false)
          R.SetOnlyTrackSelected(track)

          for split_index = 1, take_chan do
            R.Main_OnCommand(ACT_NEXT_TRACK, 0)
            R.SetEditCurPos(position, false, false)
            R.Main_OnCommand(ACT_PASTE_ITEMS_TRACK, 0)

            local new_item = get_selected_item_if_any()
            if new_item then
              R.SetMediaItemInfo_Value(new_item, "D_POSITION", position)
              R.SetMediaItemInfo_Value(new_item, "D_LENGTH", length)
              R.SetMediaItemInfo_Value(new_item, "D_PLAYRATE", playrate)

              local new_take = R.GetActiveTake(new_item)
              if new_take then
                R.GetSetMediaItemTakeInfo_String(new_take, "P_NAME", build_take_name(take_name, split_index), true)
                set_exploded_chanmode(new_take, take_chanmode, split_index)
              end

              new_items[#new_items + 1] = new_item
            end
          end
        end
      end
    end
  end

  return new_items, new_tracks
end

local function render_item_to_new_take(item)
  if not item then return false, "missing item" end
  local take_before = R.GetActiveTake(item)
  local take_name_before = get_take_name_safe(take_before)

  select_only_item(item)
  R.Main_OnCommand(ACT_RENDER_TO_NEW_TAKE_PRESERVE, 0)

  local take_after = R.GetActiveTake(item)
  local take_count = R.CountTakes(item) or 0
  if not take_after or take_after == take_before or take_count < 2 then
    return false, "render did not create a new active take"
  end

  if take_name_before ~= "" then
    R.GetSetMediaItemTakeInfo_String(take_after, "P_NAME", take_name_before, true)
  end

  return true, nil, take_after
end

local function main()
  local items = get_selected_items()
  if #items == 0 then
    R.MB("Please select at least one multichannel item.", "Explode Preserve Metadata", 0)
    return
  end

  local cli = EMB.CLI_Resolve and EMB.CLI_Resolve() or nil
  if not cli then
    R.MB("Cannot resolve BWF MetaEdit CLI via hsuanice_Metadata Embed.lua", "Explode Preserve Metadata", 0)
    return
  end

  R.ClearConsole()
  msg("=== Explode Multichannel Poly Audio to New One-channel Items Preserve Metadata ===")
  msg(("Metadata Embed: %s"):format(tostring(EMB_PATH or "(unknown)")))
  msg(("Selected items: %d"):format(#items))

  local exploded_items, new_tracks, refreshed = {}, {}, {}
  local did_batch_refresh = false
  local render_ok, render_fail, embed_ok, embed_fail = 0, 0, 0, 0

  R.PreventUIRefresh(1)
  R.Undo_BeginBlock()

  local ok, err = xpcall(function()
    exploded_items, new_tracks = explode_selected_items_to_new_tracks(items)
    msg(("Exploded items: %d"):format(#exploded_items))

    for i, item in ipairs(exploded_items) do
      msg(("Item %d -------------------------"):format(i))
      local take1 = R.GetMediaItemTake(item, 0)
      local src_path = take1 and EMB.Get_Take_Source_Path and EMB.Get_Take_Source_Path(take1) or nil
      msg(("  take1 src      : %s"):format(tostring(src_path or "(nil)")))

      local ok_render, render_reason = render_item_to_new_take(item)
      if not ok_render then
        render_fail = render_fail + 1
        msg(("  render result  : FAIL (%s)"):format(tostring(render_reason)))
      else
        render_ok = render_ok + 1
        msg("  render result  : OK")

        local ok_embed, res = EMB.Copy_Take1_To_Active(item, {
          cli = cli,
          log = function(line) msg(line) end,
          set_embedder = true,
          embedder_name = "BWF MetaEdit",
        })

        if ok_embed then
          embed_ok = embed_ok + 1
          refreshed[#refreshed + 1] = item
          msg("  embed result   : OK")
        else
          embed_fail = embed_fail + 1
          msg(("  embed result   : FAIL (%s)"):format(tostring(res and res.reason or "unknown")))
        end
      end
    end

    if EMB.Refresh_Items and #refreshed > 0 then
      EMB.Refresh_Items(refreshed)
      did_batch_refresh = true
    end

    R.SelectAllMediaItems(0, false)
    for _, item in ipairs(exploded_items) do
      R.SetMediaItemSelected(item, true)
    end

    for i, track in ipairs(new_tracks) do
      if i == 1 then
        R.SetOnlyTrackSelected(track)
      else
        R.SetTrackSelected(track, true)
      end
    end
  end, debug.traceback)

  R.Undo_EndBlock("Explode multichannel poly audio to new one-channel items preserve metadata", 0)
  R.PreventUIRefresh(-1)
  if not did_batch_refresh then
    R.UpdateArrange()
  end

  if not ok then
    msg(err)
    R.MB("Script failed. Check the REAPER console for details.", "Explode Preserve Metadata", 0)
    return
  end

  local summary = string.format(
    "Done. Exploded=%d  Render OK=%d  Render FAIL=%d  Embed OK=%d  Embed FAIL=%d",
    #exploded_items, render_ok, render_fail, embed_ok, embed_fail
  )
  msg(summary)
  R.MB(summary, "Explode Preserve Metadata", 0)
end

main()