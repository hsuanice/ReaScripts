-- @description Media Explorer User Column Set Switcher
-- @author hsuanice
-- @version 1.1
-- @about
--   Switch REAPER Media Explorer User Column sets by completely clearing
--   the existing custom User Columns and rebuilding the selected set.
--
--   Sets:
--     1. SoundMiner
--     2. Field Recorder / Post (iXML + BWF)
--     3. Music / ID3
--
--   IMPORTANT:
--     REAPER supports a maximum of 32 User Columns.
--
--   This intentionally differs from:
--     acendan_Add custom user columns for SoundMiner iXML Metadata.lua
--
--   ACendan's script preserves existing User Columns and adds missing
--   SoundMiner columns. This script treats user0..user31 as a disposable
--   32-slot bank:
--
--       CLEAR ALL -> REBUILD SELECTED SET
--
--   Column Order Presets are NOT modified by this script.
--
--   Requires SWS:
--     BR_Win32_GetPrivateProfileString
--     BR_Win32_WritePrivateProfileString
--
-- @changelog
--   v1.1 - Refined sets; SoundMiner list follows ACendan's original
--          33-field list, with OpenTier omitted to fit REAPER's 32-column
--          hard limit. Presets are intentionally untouched.
--   v1.0 - Initial three-set switcher.

-- ============================================================
-- SETTINGS
-- ============================================================

-- REAPER has a 32 User Column limit. We clear a larger range so that
-- old test entries (for example user32+) cannot survive between sets.
local CLEAR_TO = 255

-- Refresh Media Explorer after rebuilding.
local AUTO_REFRESH = true

-- ============================================================
-- COLUMN SETS
-- ============================================================

local SETS = {}

-- ------------------------------------------------------------
-- 1. SOUNDMINER
--
-- Based directly on:
-- acendan_Add custom user columns for SoundMiner iXML Metadata.lua
--
-- ACendan's original list contains 33 fields.
-- REAPER accepts only 32 User Columns, so OpenTier is omitted.
--
-- If you prefer OpenTier, replace another field below with:
-- {"IXML:USER:OpenTier", "OpenTier"}
-- ------------------------------------------------------------

SETS["SoundMiner"] = {
  {"IXML:USER:CatID",          "CatID"},
  {"IXML:USER:Category",       "Category"},
  {"IXML:USER:SubCategory",    "SubCategory"},
  {"IXML:USER:Description",    "Description"},
  {"IXML:USER:Notes",          "Notes"},
  {"IXML:USER:Microphone",     "Microphone"},
  {"IXML:USER:MicPerspective", "MicPerspective"},
  {"IXML:USER:Library",        "Library"},
  {"IXML:USER:Designer",       "Designer"},
  {"IXML:USER:ShootDate",      "ShootDate"},
  {"IXML:USER:CategoryFull",    "CategoryFull"},
  {"IXML:USER:RecType",        "RecType"},
  {"IXML:USER:ShortID",        "ShortID"},
  {"IXML:USER:TrackYear",      "TrackYear"},
  {"IXML:USER:Keywords",       "Keywords"},
  {"IXML:USER:Show",           "Show"},
  {"IXML:USER:Source",         "Source"},
  {"IXML:USER:Location",       "Location"},
  {"IXML:USER:FXName",         "FXName"},
  {"IXML:USER:TrackTitle",     "TrackTitle"},
  {"IXML:USER:Artist",         "Artist"},
  {"IXML:USER:LongID",         "LongID"},
  {"IXML:USER:Volume",         "Volume"},
  {"IXML:USER:Track",          "Track"},
  {"IXML:USER:Manufacturer",   "Manufacturer"},
  {"IXML:USER:RecMedium",      "RecMedium"},
  {"IXML:USER:CDTitle",        "CDTitle"},
  {"IXML:USER:Rating",         "Rating"},
  {"IXML:USER:URL",            "URL"},
  {"IXML:USER:ReleaseDate",    "ReleaseDate"},
  {"IXML:USER:UserCategory",   "UserCategory"},
  {"IXML:USER:VendorCategory", "VendorCategory"},
}

-- ------------------------------------------------------------
-- 2. FIELD RECORDER / POST
--
-- Based on the iXML + BWF structure supplied by the user.
-- Exactly 32 columns, prioritizing information useful for
-- location sound / dialogue / post workflows.
--
-- Intentionally omitted from this 32-column profile:
--   SPEED:CURRENT_SPEED
--   SPEED:MASTER_SPEED
--   SPEED:TIMESTAMP_SAMPLE_RATE:2
--
-- These are redundant with the other speed/sample-rate fields
-- for the normal field-recorder workflow.
-- ------------------------------------------------------------

SETS["Field Recorder / Post"] = {
  {"IXML:TAPE",                                         "TAPE(ixml)"},
  {"IXML:SCENE",                                        "SCENE(ixml)"},
  {"IXML:TAKE",                                         "TAKE(ixml)"},
  {"IXML:PROJECT",                                      "PROJECT(ixml)"},
  {"IXML:CIRCLED",                                      "CIRCLED(ixml)"},

  {"IXML:FILE_SET:FAMILY_UID",                          "FAMILY_UID(ixml)"},
  {"IXML:FILE_SET:FILE_SET_INDEX",                      "FILE_SET_INDEX(ixml)"},
  {"IXML:FILE_SET:TOTAL_FILES",                         "TOTAL_FILES(ixml)"},
  {"IXML:FILE_UID",                                     "FILE_UID(ixml)"},

  {"IXML:HISTORY:CURRENT_FILENAME",                     "CURRENT_FILENAME(ixml)"},
  {"IXML:HISTORY:ORIGINAL_FILENAME",                    "ORIGINAL_FILENAME(ixml)"},
  {"IXML:IXML_VERSION",                                 "IXML_VERSION(ixml)"},

  {"IXML:SPEED:AUDIO_BIT_DEPTH",                        "AUDIO_BIT_DEPTH(ixml)"},
  {"IXML:SPEED:DIGITIZER_SAMPLE_RATE",                  "DIGITIZER_SAMPLE_RATE(ixml)"},
  {"IXML:SPEED:FILE_SAMPLE_RATE",                       "FILE_SAMPLE_RATE(ixml)"},
  {"IXML:SPEED:TIMECODE_FLAG",                          "TIMECODE_FLAG(ixml)"},
  {"IXML:SPEED:TIMECODE_RATE",                          "TIMECODE_RATE(ixml)"},
  {"IXML:SPEED:TIMESTAMP_SAMPLE_RATE",                  "TIMESTAMP_SAMPLE_RATE(ixml)"},
  {"IXML:SPEED:TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_HI",    "SAMPLES_MIDNIGHT_HI(ixml)"},
  {"IXML:SPEED:TIMESTAMP_SAMPLES_SINCE_MIDNIGHT_LO",    "SAMPLES_MIDNIGHT_LO(ixml)"},

  {"IXML:TRACK_LIST:TRACK:CHANNEL_INDEX",               "CHANNEL_INDEX(ixml)"},
  {"IXML:TRACK_LIST:TRACK:INTERLEAVE_INDEX",            "INTERLEAVE_INDEX(ixml)"},
  {"IXML:TRACK_LIST:TRACK:NAME",                        "TRACK_NAME(ixml)"},
  {"IXML:TRACK_LIST:TRACK_COUNT",                       "TRACK_COUNT(ixml)"},

  {"IXML:UBITS",                                        "UBITS(ixml)"},

  {"BWF:Description",                                   "Description(bwf)"},
  {"BWF:OriginationDate",                               "OriginationDate(bwf)"},
  {"BWF:OriginationTime",                               "OriginationTime(bwf)"},
  {"BWF:Originator",                                    "Originator(bwf)"},
  {"BWF:OriginatorReference",                           "OriginatorReference(bwf)"},
  {"BWF:TimeReference",                                 "TimeReference(bwf)"},
  {"BWF:CodingHistory",                                 "CodingHistory(bwf)"},
}

-- ------------------------------------------------------------
-- 3. MUSIC / ID3
--
-- A practical ID3 profile rather than trying to mirror every
-- possible ID3 frame. REAPER exposes common music metadata such
-- as Title, Artist, Album, Date, Genre, Comment, BPM and Key,
-- and custom ID3 frame keys can also be used in Media Explorer.
--
-- The first 16 are the fields most likely to be useful in normal
-- music-library work. The remaining fields are secondary.
-- ------------------------------------------------------------

SETS["Music / ID3"] = {
  {"ID3:TIT2", "Title(id3)"},
  {"ID3:TPE1", "Artist(id3)"},
  {"ID3:TALB", "Album(id3)"},
  {"ID3:TPE2", "AlbumArtist(id3)"},
  {"ID3:TCOM", "Composer(id3)"},
  {"ID3:TCON", "Genre(id3)"},
  {"ID3:TBPM", "BPM(id3)"},
  {"ID3:TKEY", "Key(id3)"},
  {"ID3:TRCK", "TrackNumber(id3)"},
  {"ID3:TPOS", "DiscNumber(id3)"},
  {"ID3:TDRC", "RecordingDate(id3)"},
  {"ID3:TYER", "Year(id3)"},
  {"ID3:TCOP", "Copyright(id3)"},
  {"ID3:TPUB", "Publisher(id3)"},
  {"ID3:TSRC", "ISRC(id3)"},
  {"ID3:COMM", "Comment(id3)"},
  {"ID3:TEXT", "Lyricist(id3)"},
  {"ID3:TIT1", "ContentGroup(id3)"},
  {"ID3:TIT3", "Subtitle(id3)"},
  {"ID3:TOAL", "OriginalAlbum(id3)"},
  {"ID3:TOPE", "OriginalArtist(id3)"},
  {"ID3:TORY", "OriginalYear(id3)"},
  {"ID3:TENC", "EncodedBy(id3)"},
  {"ID3:TSSE", "Encoder(id3)"},
  {"ID3:TLAN", "Language(id3)"},
  {"ID3:TMED", "MediaType(id3)"},
  {"ID3:TOWN", "FileOwner(id3)"},
  {"ID3:WOAR", "ArtistURL(id3)"},
  {"ID3:WXXX", "UserURL(id3)"},
  {"ID3:APIC_TYPE", "PictureType(id3)"},
  {"ID3:APIC_DESC", "PictureDescription(id3)"},
  {"ID3:APIC_FILE", "PictureFile(id3)"},
}

-- ============================================================
-- HELPERS
-- ============================================================

local function get_ini_section()
  if reaper.GetOS():match("Win") then
    return "reaper_explorer"
  end
  return "reaper_sexplorer"
end

local ini_file = reaper.get_ini_file()
local ini_section = get_ini_section()

local function write_ini(key, value)
  return reaper.BR_Win32_WritePrivateProfileString(
    ini_section, key, value, ini_file
  )
end

local function delete_ini_key(key)
  -- SWS accepts an empty string as the value for deleting an INI key.
  local ok, result = pcall(
    reaper.BR_Win32_WritePrivateProfileString,
    ini_section, key, "", ini_file
  )
  return ok and result ~= false
end

local function clear_all_user_columns()
  local deleted = 0

  for i = 0, CLEAR_TO do
    if delete_ini_key("user" .. i .. "_key") then
      deleted = deleted + 1
    end

    delete_ini_key("user" .. i .. "_desc")
    delete_ini_key("user" .. i .. "_flags")
  end

  return deleted
end

local function build_set(columns)
  if #columns > 32 then
    return false, "SET_TOO_LARGE"
  end

  for i, col in ipairs(columns) do
    local n = i - 1

    local ok1 = write_ini("user" .. n .. "_key", col[1])
    local ok2 = write_ini("user" .. n .. "_desc", col[2])
    local ok3 = write_ini("user" .. n .. "_flags", "1")

    if not (ok1 and ok2 and ok3) then
      return false, {
        index = n,
        key = col[1],
        desc = col[2],
      }
    end
  end

  return true
end

local function refresh_media_explorer()
  if not AUTO_REFRESH then
    return
  end

  -- Same refresh method used by the ACendan reference script.
  reaper.Main_OnCommand(50124, 0)
  reaper.Main_OnCommand(50124, 0)
  reaper.OpenMediaExplorer("", false)
end

local function switch_set(set_name)
  local columns = SETS[set_name]

  if not columns then
    reaper.MB(
      "Unknown User Column set:\n\n" .. tostring(set_name),
      "Media Explorer User Columns",
      0
    )
    return
  end

  if #columns > 32 then
    reaper.MB(
      "This set contains " .. tostring(#columns) ..
      " columns.\n\nREAPER supports a maximum of 32 User Columns.\n\n" ..
      "Nothing was changed.",
      "Too Many User Columns",
      0
    )
    return
  end

  -- IMPORTANT:
  -- Do NOT touch Column Order Presets here.
  -- This script only clears/rebuilds userN_key/desc/flags.
  reaper.PreventUIRefresh(1)

  local deleted = clear_all_user_columns()
  local ok, failure = build_set(columns)

  reaper.PreventUIRefresh(-1)

  refresh_media_explorer()

  if not ok then
    local detail

    if failure == "SET_TOO_LARGE" then
      detail = "The selected set has more than 32 columns."
    else
      detail =
        "Failed at user" .. tostring(failure.index) ..
        ":\n" .. tostring(failure.key) ..
        "\n\nThe User Column set may be incomplete."
    end

    reaper.ShowConsoleMsg(
      "\n========== USER COLUMN SET ERROR ==========\n" ..
      "Set: " .. set_name .. "\n" ..
      detail .. "\n" ..
      "===========================================\n"
    )

    reaper.MB(
      "The User Column set was not written completely.\n\n" ..
      detail,
      "Media Explorer User Columns",
      0
    )
    return
  end

  reaper.ShowConsoleMsg(
    "\n========== USER COLUMN SET ==========\n" ..
    "Set: " .. set_name .. "\n" ..
    "Columns: " .. tostring(#columns) .. "\n" ..
    "Old entries cleared: " .. tostring(deleted) .. "\n" ..
    "Column Order Presets: UNCHANGED\n" ..
    "=====================================\n"
  )

  reaper.MB(
    "User Column set switched to:\n\n" ..
    set_name ..
    "\n\n" .. tostring(#columns) ..
    " User Columns rebuilt.\n\n" ..
    "Column Order Presets were not changed.",
    "Media Explorer User Columns",
    0
  )
end

-- ============================================================
-- MENU
-- ============================================================

local function choose_set()
  local menu =
    "SoundMiner" ..
    "|Field Recorder / Post" ..
    "|Music / ID3"

  gfx.init(
    "hsuanice Media Explorer User Column Set",
    1, 1, 0,
    0, 0
  )

  gfx.x = 0
  gfx.y = 0

  local choice = gfx.showmenu(menu)

  gfx.quit()

  if choice == 1 then
    return "SoundMiner"
  elseif choice == 2 then
    return "Field Recorder / Post"
  elseif choice == 3 then
    return "Music / ID3"
  end

  return nil
end

-- ============================================================
-- MAIN
-- ============================================================

if not reaper.BR_Win32_GetPrivateProfileString
   or not reaper.BR_Win32_WritePrivateProfileString then

  reaper.MB(
    "This script requires the SWS extension.\n\n" ..
    "Missing:\n" ..
    "BR_Win32_GetPrivateProfileString\n" ..
    "BR_Win32_WritePrivateProfileString",
    "SWS Required",
    0
  )
  return
end

local selected = choose_set()

if selected then
  switch_set(selected)
end
