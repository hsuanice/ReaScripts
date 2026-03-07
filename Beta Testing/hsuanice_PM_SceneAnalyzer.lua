--[[
@description PM Scene Analyzer
@version 260307.1500
@author hsuanice
@about
  PM System - Phase 1, single-file implementation.
  No UI, no ImGui. All output goes to the REAPER console.

  Tracks required in project:
    "Scene Cut"   — empty items define scenes
    "Picture Cut" — items define shots (counted per scene)
    "EDL"         — folder track; child tracks hold source media

  Functions (call one at a time from the entry point at the bottom):

    analyze_scenes()
      Scans Scene Cut / Picture Cut / EDL tracks and prints a
      scene summary table with shot count and source item stats.

    set_active_scene()
      Reads the selected item on "Scene Cut" and stores its GUID
      and colour as the active scene via ProjExtState.

    assign_to_active_scene()
      Colours all selected items to match the active scene and
      stamps P_EXT:SCENE_ID on each one.

@changelog
  v260307.1500
    - Change: source attribution Priority 2 now uses I_GROUPID instead of
      colour + position range. If a source item's group matches a scene item's
      group, it is attributed to that scene. Colour is no longer used to
      determine scene membership. scene_ranges pre-computation removed.

  v260307.1434
    - New: apply_scene_colors_by_group() — after analyze_scenes() writes notes,
      propagates each scene item's color to all source items sharing the same
      I_GROUPID. Only colors items whose I_CUSTOMCOLOR is currently 0 (unset);
      user-assigned colors are preserved. Scene items themselves are never modified.
      Wrapped in its own undo block "PM: Apply scene colors to source items".
      Result logged to console ("Colors applied: N item(s)").

  v260307.1400
    - New: apply_scene_colors_by_group() — after analyze_scenes() writes notes,
      propagates each scene item's color to all source items sharing the same
      I_GROUPID. Only colors items whose I_CUSTOMCOLOR is currently 0 (unset);
      user-assigned colors are preserved. Scene items themselves are never modified.
      Wrapped in its own undo block "PM: Apply scene colors to source items".
      Result logged to console ("Colors applied: N item(s)").

  v260305.2100
    - New: write_scene_note() now also sets the scene item's take name (P_NAME)
      from the first line of P_NOTES, so the scene name appears on the timeline.
      If the item has no take, an empty take is added to hold the name.

  v260305.1930
    - New: analyze_scenes() now writes metadata into each Scene Cut item's note.
      Format (first line = scene name, preserved or "(no name)"):
        Range    : <start> - <end>
        Length   : <duration>
        Shots    : <n>
        Src Cnt  : <n>
        Src Len  : <duration>
      Old key=value lines (shots=, src_cnt=, src_len=) are also stripped on update.
    - Selective update: if any Scene Cut items are selected, only those are updated.
      If nothing is selected, all scenes are updated.
    - Undo block wraps the note writes ("PM: Update scene metadata notes").

  v260302.2100
    - Output: replaced fixed-width table with paragraph-style per-scene blocks
      (#index  Name / Range / Length / Shots / Src Cnt / Src Len)

  v260302.1501
    - Fix: format_timestr_len requires 4 args; add missing offset=0
      (signature: tpos, buf, offset, modeoverride)

  v260302.1500
    - Duration TC / Src Length TC: switched from format_timestr to
      format_timestr_len(..., 0, 5) so durations display as project TC
      frame-count (HH:MM:SS:FF) without position offset

  v260302.1400
    - Source attribution: colour fallback now requires BOTH colour match
      AND item position within [prev_scene.start, next_scene.end] range
    - Removed overlap-only colour fallback
    - Time output: Start TC / End TC use format_timestr_pos (project TC);
      Duration TC / Src Length TC use format_timestr (relative duration)
    - Table columns: Scene Name | Start TC | End TC | Duration TC |
      Shots | Src | Src Length TC

  v260302.1200
    - Initial release: analyze_scenes, set_active_scene,
      assign_to_active_scene
]]--

---@diagnostic disable: undefined-global
local r = reaper

-- ── Constants ──────────────────────────────────────────────────────────────
local NS               = "hsuanice_PM"
local SCENE_TRACK_NAME = "Scene Cut"
local SHOT_TRACK_NAME  = "Picture Cut"
local EDL_FOLDER_NAME  = "EDL"

-- ── Utility ────────────────────────────────────────────────────────────────
local function log(msg)
  r.ShowConsoleMsg((msg or "") .. "\n")
end

-- Absolute TC position (includes project TC start offset).
local function tc_pos(pos)
  return r.format_timestr_pos(pos, "", -1)
end

-- Duration in project TC format (frame-accurate, no position offset).
local function tc_dur(dur)
  return r.format_timestr_len(dur, "", 0, 5)
end

local function get_item_guid(item)
  local _, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return guid
end

local function get_item_color(item)
  return math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
end

local function get_item_name(item)
  local take = r.GetActiveTake(item)
  if take then
    local name = r.GetTakeName(take)
    if name and name ~= "" then return name end
  end
  local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  if not notes or notes == "" then return "" end
  -- Return only the first line (scene name); ignore metadata lines below it.
  return notes:match("^([^\n]+)") or ""
end

local function get_item_ext(item, key)
  local ok, val = r.GetSetMediaItemInfo_String(item, "P_EXT:" .. key, "", false)
  if ok and val ~= "" then return val end
  return nil
end

---@diagnostic disable-next-line: unused-local
local function set_item_ext(item, key, val)
  r.GetSetMediaItemInfo_String(item, "P_EXT:" .. key, val, true)
end

local function find_track_by_name(name)
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname == name then return t end
  end
  return nil
end

-- Returns all child tracks (not the folder itself) inside the named folder.
-- Handles nested sub-folders correctly via I_FOLDERDEPTH accumulation.
local function find_folder_children(folder_name)
  local count     = r.CountTracks(0)
  local tracks    = {}
  local in_folder = false
  local depth     = 0

  for i = 0, count - 1 do
    local t  = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    local fd = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"))

    if not in_folder then
      if tname == folder_name and fd == 1 then
        in_folder = true
        depth = 1
        -- Folder header is NOT a source track; skip it.
      end
    else
      table.insert(tracks, t)
      depth = depth + fd
      if depth <= 0 then break end
    end
  end

  return tracks
end

-- ── Scene Note Writer ──────────────────────────────────────────────────────
-- Writes computed scene metadata into the scene item's P_NOTES.
-- First line = scene name (preserved or "(no name)").
-- Remaining metadata lines are overwritten; other user lines are kept.
local function write_scene_note(scene_item, sc)
  local _, note = r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", "", false)

  local lines = {}
  for line in ((note or "") .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  -- First line = scene name; preserve it or default to "(no name)"
  local scene_name = (lines[1] and lines[1] ~= "") and lines[1] or "(no name)"

  -- Strip all known metadata lines (new pretty format + old key=value format)
  local function is_meta(line)
    return line:match("^Range%s*:")
        or line:match("^Length%s*:")
        or line:match("^Shots%s*:")
        or line:match("^Src Cnt%s*:")
        or line:match("^Src Len%s*:")
        or line:match("^[%w_]+=")
  end

  local other = {}
  for i = 2, #lines do
    if not is_meta(lines[i]) and lines[i] ~= "" then
      table.insert(other, lines[i])
    end
  end

  local parts = {
    scene_name,
    "Range    : " .. tc_pos(sc.start_pos) .. " - " .. tc_pos(sc.end_pos),
    "Length   : " .. tc_dur(sc.duration),
    "Shots    : " .. tostring(sc.shot_count),
    "Src Cnt  : " .. tostring(sc.source_item_count),
    "Src Len  : " .. tc_dur(sc.source_total_length),
  }
  for _, l in ipairs(other) do table.insert(parts, l) end

  r.GetSetMediaItemInfo_String(scene_item, "P_NOTES", table.concat(parts, "\n"), true)

  -- Set item name (take P_NAME) from scene name so it shows on the timeline.
  -- If the item has no take, add an empty one to hold the name.
  local take = r.GetActiveTake(scene_item)
  if not take then take = r.AddTakeToMediaItem(scene_item) end
  if take then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", scene_name, true) end

  r.UpdateItemInProject(scene_item)
end

-- ── Scene Color Propagation ────────────────────────────────────────────────
-- For each scene item that has a group and a color, apply that color to any
-- non-scene item sharing the same I_GROUPID, but only if the item has no color
-- yet (I_CUSTOMCOLOR == 0). User-assigned colors are never overwritten.
-- Returns the number of items colored.
local function apply_scene_colors_by_group(scenes)
  -- Build group_id → scene_color lookup (skip scenes with no group or no color).
  local group_color = {}
  for _, sc in ipairs(scenes) do
    local group = math.floor(r.GetMediaItemInfo_Value(sc.item, "I_GROUPID"))
    if group ~= 0 and sc.color ~= 0 then
      group_color[group] = sc.color
    end
  end
  if not next(group_color) then return 0 end

  local colored = 0
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local _, tname = r.GetTrackName(t)
    if tname ~= SCENE_TRACK_NAME then
      for j = 0, r.CountTrackMediaItems(t) - 1 do
        local item  = r.GetTrackMediaItem(t, j)
        local group = math.floor(r.GetMediaItemInfo_Value(item, "I_GROUPID"))
        if group ~= 0 and group_color[group] then
          local src_color = math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
          if src_color == 0 then
            r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", group_color[group])
            r.UpdateItemInProject(item)
            colored = colored + 1
          end
        end
      end
    end
  end
  return colored
end

-- ── Function 1: Scene Analyzer ─────────────────────────────────────────────
local function analyze_scenes()
  r.ClearConsole()
  log("=== hsuanice PM — Scene Analyzer ===")
  log("")

  -- ── Scene Cut track ──────────────────────────────────────────────────
  local scene_track = find_track_by_name(SCENE_TRACK_NAME)
  if not scene_track then
    log("[ERROR] Track not found: '" .. SCENE_TRACK_NAME .. "'")
    return
  end

  -- ── Build scene list ─────────────────────────────────────────────────
  local scenes   = {}
  local guid_map = {}   -- guid → scene (for fast lookup)
  local n_items  = r.CountTrackMediaItems(scene_track)

  for i = 0, n_items - 1 do
    local item = r.GetTrackMediaItem(scene_track, i)
    local pos  = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local len  = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local guid = get_item_guid(item)

    local scene = {
      id                  = guid,
      item                = item,
      name                = get_item_name(item),
      color               = get_item_color(item),
      start_pos           = pos,
      end_pos             = pos + len,
      duration            = len,
      shot_count          = 0,
      source_item_count   = 0,
      source_total_length = 0,
    }

    table.insert(scenes, scene)
    guid_map[guid] = scene
  end

  log(string.format("Scenes found : %d  (track: '%s')", #scenes, SCENE_TRACK_NAME))

  -- ── Build group → scene lookup (for I_GROUPID attribution) ──────────
  local group_scene = {}   -- group_id (int) → scene
  for _, sc in ipairs(scenes) do
    local group = math.floor(r.GetMediaItemInfo_Value(sc.item, "I_GROUPID"))
    if group ~= 0 then
      group_scene[group] = sc
    end
  end

  -- ── Shot count (Picture Cut) ──────────────────────────────────────────
  local shot_track = find_track_by_name(SHOT_TRACK_NAME)
  if shot_track then
    for i = 0, r.CountTrackMediaItems(shot_track) - 1 do
      local item = r.GetTrackMediaItem(shot_track, i)
      local s    = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local e    = s + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      for _, sc in ipairs(scenes) do
        if s < sc.end_pos and e > sc.start_pos then
          sc.shot_count = sc.shot_count + 1
        end
      end
    end
    log(string.format("Shots found  : %d  (track: '%s')",
      r.CountTrackMediaItems(shot_track), SHOT_TRACK_NAME))
  else
    log("[WARN] Track not found: '" .. SHOT_TRACK_NAME .. "' — shot_count will be 0")
  end

  -- ── Source items (EDL folder children) ───────────────────────────────
  local edl_tracks = find_folder_children(EDL_FOLDER_NAME)

  if #edl_tracks == 0 then
    log("[WARN] No child tracks found inside folder: '"
      .. EDL_FOLDER_NAME .. "' — source stats will be 0")
  else
    local total_src = 0
    for _, t in ipairs(edl_tracks) do
      total_src = total_src + r.CountTrackMediaItems(t)
    end
    log(string.format("EDL tracks   : %d  |  source items: %d", #edl_tracks, total_src))

    for _, t in ipairs(edl_tracks) do
      for i = 0, r.CountTrackMediaItems(t) - 1 do
        local item     = r.GetTrackMediaItem(t, i)
        local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")

        -- Priority 1: P_EXT:SCENE_ID exact match
        local scene_id = get_item_ext(item, "SCENE_ID")
        if scene_id and guid_map[scene_id] then
          local sc = guid_map[scene_id]
          sc.source_item_count   = sc.source_item_count   + 1
          sc.source_total_length = sc.source_total_length + item_len

        -- Priority 2: I_GROUPID match
        else
          local item_group = math.floor(r.GetMediaItemInfo_Value(item, "I_GROUPID"))
          if item_group ~= 0 and group_scene[item_group] then
            local sc = group_scene[item_group]
            sc.source_item_count   = sc.source_item_count   + 1
            sc.source_total_length = sc.source_total_length + item_len
          end
        end
      end
    end
  end

  -- ── Print per-scene blocks ────────────────────────────────────────────
  log("")

  for idx, sc in ipairs(scenes) do
    log("--------------------------------------------------")
    log("#" .. idx .. "  " .. (sc.name ~= "" and sc.name or "(unnamed)"))
    log("    Range   : " .. tc_pos(sc.start_pos) .. " - " .. tc_pos(sc.end_pos))
    log("    Length  : " .. tc_dur(sc.duration))
    log("    Shots   : " .. sc.shot_count)
    log("    Src Cnt : " .. sc.source_item_count)
    log("    Src Len : " .. tc_dur(sc.source_total_length))
  end

  log("")
  log("=== Done ===")

  -- ── Write metadata into scene item notes ─────────────────────────────────
  -- If any scene items are selected → update only those.
  -- If none selected → update all scenes.
  local selected_guids = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local sel = r.GetSelectedMediaItem(0, i)
    if r.GetMediaItemTrack(sel) == scene_track then
      selected_guids[get_item_guid(sel)] = true
    end
  end
  local has_selection = next(selected_guids) ~= nil

  r.Undo_BeginBlock()
  local written = 0
  for _, sc in ipairs(scenes) do
    if not has_selection or selected_guids[sc.id] then
      write_scene_note(sc.item, sc)
      written = written + 1
    end
  end
  r.Undo_EndBlock("PM: Update scene metadata notes", -1)

  if written > 0 then
    r.ShowConsoleMsg(string.format("Notes written: %d scene(s)\n", written))
  end

  -- ── Apply scene colors to grouped source items ────────────────────────────
  r.Undo_BeginBlock()
  local colored = apply_scene_colors_by_group(scenes)
  r.Undo_EndBlock("PM: Apply scene colors to source items", -1)
  if colored > 0 then
    r.UpdateArrange()
    r.ShowConsoleMsg(string.format("Colors applied: %d item(s)\n", colored))
  end

  return scenes
end

-- ── Function 2: Set Active Scene ───────────────────────────────────────────
---@diagnostic disable-next-line: unused-local
local function set_active_scene()
  log("=== hsuanice PM — Set Active Scene ===")

  local scene_track = find_track_by_name(SCENE_TRACK_NAME)
  if not scene_track then
    log("[ERROR] Track not found: '" .. SCENE_TRACK_NAME .. "'")
    return
  end

  -- Find the first selected item that lives on the Scene Cut track.
  local sel_item = nil
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    if r.GetMediaItemTrack(item) == scene_track then
      sel_item = item
      break
    end
  end

  if not sel_item then
    log("[ERROR] Please select an item on the '" .. SCENE_TRACK_NAME .. "' track first.")
    return
  end

  local guid  = get_item_guid(sel_item)
  local color = get_item_color(sel_item)
  local name  = get_item_name(sel_item)

  r.SetProjExtState(0, NS, "ACTIVE_SCENE_ID",    guid)
  r.SetProjExtState(0, NS, "ACTIVE_SCENE_COLOR", tostring(color))

  log(string.format("Active scene  : '%s'", name ~= "" and name or "(unnamed)"))
  log(string.format("  ID    : %s", guid))
  log(string.format("  Color : %d (0x%08X)", color, color))
  log("")
  log("=== Done ===")
end

-- ── Function 3: Assign Selected Items To Active Scene ──────────────────────
---@diagnostic disable-next-line: unused-local
local function assign_to_active_scene()
  log("=== hsuanice PM — Assign to Active Scene ===")

  local ok_id, active_id        = r.GetProjExtState(0, NS, "ACTIVE_SCENE_ID")
  local _,     active_color_str = r.GetProjExtState(0, NS, "ACTIVE_SCENE_COLOR")

  if ok_id == 0 or active_id == "" then
    log("[ERROR] No active scene found. Run 'Set Active Scene' first.")
    return
  end

  local active_color = tonumber(active_color_str) or 0
  local sel_count    = r.CountSelectedMediaItems(0)

  if sel_count == 0 then
    log("[ERROR] No items selected.")
    return
  end

  r.Undo_BeginBlock()

  local assigned = 0
  for i = 0, sel_count - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", active_color)
    set_item_ext(item, "SCENE_ID", active_id)
    r.UpdateItemInProject(item)
    assigned = assigned + 1
  end

  r.Undo_EndBlock("PM: Assign items to active scene", -1)
  r.UpdateArrange()

  log(string.format("Assigned     : %d item(s)", assigned))
  log(string.format("Scene ID     : %s", active_id))
  log(string.format("Color applied: %d (0x%08X)", active_color, active_color))
  log("")
  log("=== Done ===")
end

-- ── Entry Point ────────────────────────────────────────────────────────────
-- Uncomment the function you want to run, then execute via Actions.
--
analyze_scenes()
-- set_active_scene()
-- assign_to_active_scene()
