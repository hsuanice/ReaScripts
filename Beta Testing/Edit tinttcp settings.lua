
-- CONSOLE OUTPUT --
function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end

--would be really nice if this script could be simpler, but it's made and should be made to work in the following circumstances:

-- ReaperTheme can be:
  -- a zipped file
  -- a unzipped file
  -- a modified zipped file
  -- a modified unzipped file
  -- a modified zipped file on Reaper startup 
  -- a modified unzipped file on Reaper startup 
  -- only one or the other defined parameter is present in the rtconfig.txt file
  
--these points leads to the complexity. 


local theme_path, file_name, contents, tinttcp_value, peaksedges_value, content, lasttheme, rtconfig_path, _
local antialiased__peak, edges_on_peaks, edges_on_waveforms, edges_on_midi, shownstring
local track_color_peak, item_color_peak, edges_on_midi_peak, track_color_background, item_color_background, edges_on_midi_background
local label_background, panel_background, yes, seen
local whatIs = 0
local inipath = reaper.get_ini_file()


--------------
-- ReaImGui --

if not reaper.ImGui_GetBuiltinPath then
  return reaper.MB('ReaImGui is not installed or too old.', 'My script', 0)
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.3'
local font = ImGui.CreateFont('sans-serif', 13)
local ctx = ImGui.CreateContext('TintTcp Settings')
ImGui.Attach(ctx, font)


---------------
-- Functions --

local function str(y)
  local string_length = ImGui.CalcTextSize(ctx, y, nil, nil, false, -1.0)
  return string_length
end

-- Parse values that may come from config (decimal) or rtconfig (hex string).
local function ParseThemeInt(value, fallback)
  if type(value) == 'number' then return value end
  if type(value) ~= 'string' then return fallback or 0 end
  value = value:match('^%s*(.-)%s*$')
  if value == '' then return fallback or 0 end

  local n = tonumber(value)
  if n then return n end

  if value:match('^[%x]+$') then
    n = tonumber(value, 16)
    if n then return n end
  end

  return fallback or 0
end

local function ExtractRtconfigHex(content, key)
  -- Support keys on the first line and later lines.
  return content:match('^[^;\n]*' .. key .. ' (%x+)')
    or content:match('\n[^;\n]*' .. key .. ' (%x+)')
end

local function UpsertRtconfigValue(content, key, value)
  local replacement = key .. ' ' .. tostring(value)
  local updated, count = content:gsub('^([^;\n]*)' .. key .. ' %x+', '%1' .. replacement, 1)
  if count == 0 then
    updated, count = content:gsub('(\n[^;\n]*)' .. key .. ' %x+', '%1' .. replacement, 1)
  end
  if count == 0 then
    if updated:sub(-1) ~= '\n' then updated = updated .. '\n' end
    updated = updated .. replacement
  end
  return updated
end

-- borrowed from X-Raym, thanks mate
function SplitFileName( strfilename )
  -- Returns the Path, Filename, and Extension as 3 values
  local path, file_name, extension = string.match( strfilename, "(.-)([^\\|/]-([^\\|/%.]+))$" )
  file_name = string.match( file_name, ('(.+)%.(.+)') )
  return path, file_name, extension
end


local function ReadOutValues()
  whatIs = whatIs&~31 -- clear bitfield
  lasttheme = select(2, reaper.BR_Win32_GetPrivateProfileString("reaper", "lastthemefn5", "Error", inipath))
  if lasttheme ~= "*unsaved*" then --if loaded theme is a unzipped ReaperTheme file
    theme_path = reaper.GetLastColorThemeFile()
  else --if loaded theme is modified and values are stored in REAPER.ini
    theme_path = inipath
  end
  local ui_img = select(2, reaper.BR_Win32_GetPrivateProfileString("REAPER", "ui_img", -1, theme_path))
  local ui_img_path = select(2, reaper.BR_Win32_GetPrivateProfileString("REAPER", "ui_img_path", -1, theme_path))
  
  if ui_img_path ~= '-1' and ui_img ~= '-1' then -- if loaded file is not a zip file
    whatIs = whatIs|4
    rtconfig_path = ui_img_path..'/'..ui_img..'/'..'rtconfig.txt'
    local exists = reaper.file_exists(rtconfig_path)
    if exists then
      local file = io.open(rtconfig_path, "r")
      content = file:read('*all')
      file:close()
      tinttcp_value = ExtractRtconfigHex(content, 'tinttcp') -- found several circumstances in older themes where the line entrance didn't start at the beginning, or lines where commented out
      peaksedges_value = ExtractRtconfigHex(content, 'peaksedges')
      if tinttcp_value then
        whatIs = whatIs|1 --values come from a unzipped ReaperTheme file
      else --if tinttcp and peaksedges not found in ReaperTheme file, load from REAPER.ini
        tinttcp_value = select(2, reaper.BR_Win32_GetPrivateProfileString("reaper", "tinttcp", "Error", inipath))
        whatIs = whatIs&~1
      end
      if peaksedges_value then
        whatIs = whatIs|2 -- ReaperTheme is modified and values are read out of REAPER.ini
      else
        peaksedges_value = select(2, reaper.BR_Win32_GetPrivateProfileString("reaper", "peaksedges", "Error", inipath))
        whatIs = whatIs&~2
      end
    else
      whatIs = whatIs|16
    end
  else --if loaded file is zipped 
    if lasttheme == "*unsaved*" and ui_img ~= '-1' and ui_img_path == '-1' then theme_path = reaper.GetResourcePath()..'/ColorThemes/'..ui_img end -- if ReaperTheme was edited on Reaper startup
    --if not theme_path:find("(.-)%Zip") or theme_path:find("(.-)%ZIP") or theme_path:find("(.-)%zip") then -- how could this be made case unsensitive?
    if not theme_path:lower():find("reaperthemezip$") then
      theme_path = theme_path.."Zip"
    end
    local zip = reaper.JS_Zip_Open(theme_path, 'r', 6)
    if zip then -- check if zip is valid
      whatIs = whatIs|8
      local ent_str = select(2, reaper.JS_Zip_ListAllEntries(zip))
      for name in ent_str:gmatch("[^\0]+") do
        local file = name:match("(.-)%/rtconfig.txt$")
        if file then
          file_name = name
          break
        end
      end
      local entries_cnt = reaper.JS_Zip_CountEntries(zip)
      local entry_id_r = reaper.JS_Zip_Entry_OpenByName(zip, file_name)
      _, content = reaper.JS_Zip_Entry_ExtractToMemory(zip)
      tinttcp_value = ExtractRtconfigHex(content, 'tinttcp')
      peaksedges_value = ExtractRtconfigHex(content, 'peaksedges')
      if tinttcp_value then -- found several themes only having present one of the two values
        whatIs = whatIs|1
      else  --if tinttcp not found in zipped ReaperTheme file, load with ConfigVar
        tinttcp_value = reaper.SNM_GetIntConfigVar('tinttcp', -1)
        whatIs = whatIs&~1
      end
      if peaksedges_value then -- found several themes only having present one of the two values
        whatIs = whatIs|2
      else  --if peaksedges not found in zipped ReaperTheme file, load with ConfigVar
        peaksedges_value = reaper.SNM_GetIntConfigVar('peaksedges', -1)
        whatIs = whatIs&~2
      end
    end
  end
  return tinttcp_value, peaksedges_value, content, lasttheme, whatIs
end


-- extract bitfields of peaksedges and tinttcp to boolean for ImGui.Checkbox
local function ExtractValues()
  if whatIs&16 ~= 16 then 
    peaksedges_value = ParseThemeInt(peaksedges_value, 0)
    if peaksedges_value&1     ~= 0    then edges_on_peaks          = true else edges_on_peaks          = false end
    if peaksedges_value&2     ~= 0    then edges_on_waveforms      = true else edges_on_waveforms      = false end
    if peaksedges_value&4     ~= 0    then edges_on_midi           = true else edges_on_midi           = false end
    if peaksedges_value&1024  ~= 1024 then antialiased__peak       = true else antialiased__peak       = false end
    
    tinttcp_value = ParseThemeInt(tinttcp_value, 0)
    if tinttcp_value&1    ~= 0    then label_background        = true else label_background        = false end -- Set track label background to custom track colors
    if tinttcp_value&2    ~= 0    then panel_background        = true else panel_background        = false end -- Tint track panel backgrounds
    if tinttcp_value&4    ~= 4    then track_color_peak        = true else track_color_peak        = false end -- Tint media item waveform peaks to: Track color
    if tinttcp_value&8    ~= 0    then track_color_background  = true else track_color_background  = false end -- Tint media item background to:     Track color
    if tinttcp_value&16   ~= 16   then item_color_peak         = true else item_color_peak         = false end -- Tint media item waveform peaks to: Item color
    if tinttcp_value&32   ~= 0    then item_color_background   = true else item_color_background   = false end -- Tint media item background to:     Item color
    if tinttcp_value&128  ~= 128  then take_color_peak         = true else take_color_peak         = false end -- Tint media item waveform peaks to: Take color
    if tinttcp_value&256  ~= 0    then take_color_background   = true else take_color_background   = false end -- Tint media item background to:     Take color
  end
end


local function WriteToRtconfig()
  if whatIs&4 ~= 0 then --values could be written back to the unzipped ReaperTheme file
    content = UpsertRtconfigValue(content, 'tinttcp', tinttcp_value)
    content = UpsertRtconfigValue(content, 'peaksedges', peaksedges_value)
    local file = io.open(rtconfig_path, "w")
    file:write(content)
    file:close()
  elseif whatIs&8 ~= 0 then -- values were loaded from a zipped file and should be written back to it
    content = UpsertRtconfigValue(content, 'tinttcp', tinttcp_value)
    content = UpsertRtconfigValue(content, 'peaksedges', peaksedges_value)
    local zipHandle, ok = reaper.JS_Zip_Open(theme_path, 'w', 6)
    local num_deleted = reaper.JS_Zip_DeleteEntries(zipHandle, file_name .. "\00", #file_name)
    local entry_id_w = reaper.JS_Zip_Entry_OpenByName(zipHandle, file_name)
    reaper.JS_Zip_Entry_CompressMemory(zipHandle, content, #content)
    reaper.JS_Zip_Entry_Close(zipHandle)
    reaper.JS_Zip_Close(theme_path)
  end
  if lasttheme == "*unsaved*" then
    --when theme is modified, generate a valid ReaperTheme file by reading out values from REAPER.ini to make loading modified rtconfig possible
    --it's the only way I found to reload the png folder containing the edited rtconfig.txt file when current theme is a modified zipped theme
    local t = {}
    local index = 0
    local file = io.open(inipath, "r")
    for line in io.lines(inipath) do
      if line == '[color theme]'then
        found = true 
      elseif found and line == '' then
        found = false
      end
      if found then 
        index = index+1
        t[index] = line
      end
    end
    index = index+1
    t[index] = ''
    index = index+1
    t[index] = '[REAPER]'
    -- read out fonts from REAPER.ini and cache them to table --
    local fonts_tab = {"lb_font", "lb_font2", "mi_font", "tl_font", "trans_font", "ui_img", "ui_img_path", "user_font0", "user_font1", "user_font2", "user_font3", "user_font4", "user_font5", "user_font6", "user_font7", "user_font8", "user_font9", "user_font10", "user_font11", "user_font12", "user_font13", "user_font14", "user_font15"}
    for k, v in ipairs( fonts_tab ) do
      local retval, font = reaper.BR_Win32_GetPrivateProfileString( "REAPER", v, -1, inipath )
      if font ~= '-1' then -- if original theme file is zipped then "ui_img_path" should not be present in generated tmp ReaperTheme file for proper reloading.
        index = index+1 
        t[index] = v..'='..font
      end
    end
    -- write a tmp file to /Color themes --
    local str = table.concat(t, "\n")
    local resource_path = reaper.GetResourcePath()..'/ColorThemes/temp_file.ReaperTheme'
    file = io.open ( resource_path, 'w+' )
    file:write( str )
    file:close()
    reaper.OpenColorThemeFile(resource_path)
    reaper.BR_Win32_WritePrivateProfileString("reaper", "lastthemefn5", lasttheme, inipath)
  else
    reaper.OpenColorThemeFile(theme_path)
  end
end


----------
-- Main --

local function main()
  if not seen then 
    yes = reaper.MB("Make a backup of your themes!\n\nIf something goes wrong, it could break a file.\n\nDo you want to save your 'ColorThemes configuration'?", "ATTENTION!!", 4)
    seen = true
  end
  if yes==6 then 
    reaper.ViewPrefs(0x08b, '')
    yes = false
  end
    
  local lasttheme_check = select(2, reaper.BR_Win32_GetPrivateProfileString("reaper", "lastthemefn5", "Error", inipath)) -- Hm, yeah, it does check each cycle. How to avoid that? Really that bad?
  if lasttheme_check ~= lasttheme_check_saved then
    tinttcp_value, peaksedges_value, content, lasttheme, whatIs = ReadOutValues()
    ExtractValues()
    lasttheme_check_saved = lasttheme_check
  end
  
  if tinttcp_value and peaksedges_value then
    shownstring = 'tinttcp:  '..(tinttcp_value&~3648)..'      peaksedges:  '..(peaksedges_value&~3064)
  else 
    shownstring = 'Reading out values went wrong!'
  end
  
  if not text_length then text_length = str('Tint media item waveform background to:') end

  -- all this checkboxes could go into a function and loop thru a table for the different values. Will bring line count down, however...
  if ImGui.Checkbox(ctx, 'Antialiased peak and waveform drawing', antialiased__peak) then
    if antialiased__peak then 
      antialiased__peak = false
      peaksedges_value = peaksedges_value|1024
    else
      antialiased__peak = true
      peaksedges_value = peaksedges_value&~1024
    end
  end
  
  if ImGui.Checkbox(ctx, 'Draw edges on peaks', edges_on_peaks) then
    if edges_on_peaks then
      edges_on_peaks = false
      peaksedges_value = peaksedges_value&~1
    else
      edges_on_peaks = true
      peaksedges_value = peaksedges_value|1
    end
  end
  
  ImGui.SameLine(ctx)
  
  if ImGui.Checkbox(ctx, 'Draw edges on waveforms', edges_on_waveforms) then
    if edges_on_waveforms then
      edges_on_waveforms = false
      peaksedges_value = peaksedges_value~2
    else
      edges_on_waveforms = true
      peaksedges_value = peaksedges_value|2
    end
  end
  ImGui.SameLine(ctx)
  
  if ImGui.Checkbox(ctx, 'Draw edges on MIDI events', edges_on_midi) then
    if edges_on_midi then
      edges_on_midi = false
      peaksedges_value = peaksedges_value&~4
    else
      edges_on_midi = true
      peaksedges_value = peaksedges_value|4
    end
  end
  ImGui.Dummy(ctx, 10, 10)
  ImGui.Dummy(ctx, 10, 10)
  ImGui.Text(ctx, 'Custom colors')
  ImGui.Dummy(ctx, 10, 10)
  ImGui.Text(ctx, 'Tint media item waveform peaks to:         ')
  ImGui.SameLine(ctx, 20, text_length)
  if ImGui.Checkbox(ctx, 'Track color##1', track_color_peak) then
    if track_color_peak then
      track_color_peak = false
      tinttcp_value = tinttcp_value|4 
    else
      track_color_peak = true
      tinttcp_value = tinttcp_value&~4 
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Checkbox(ctx, 'Item color##1', item_color_peak) then
    if item_color_peak then
      item_color_peak = false
      tinttcp_value = tinttcp_value|16
    else
      item_color_peak = true
      tinttcp_value = tinttcp_value&~16
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Checkbox(ctx, 'Take color##1', take_color_peak) then
    if take_color_peak then
      take_color_peak = false
      tinttcp_value = tinttcp_value|128
    else
      take_color_peak = true
      tinttcp_value = tinttcp_value&~128
    end
  end
  ImGui.Dummy(ctx, 10, 10)
  ImGui.Text(ctx, 'Tint media item waveform background to:')
  ImGui.SameLine(ctx, 20, text_length)
  if ImGui.Checkbox(ctx, 'Track color##2', track_color_background) then
    if track_color_background then
      track_color_background = false
      tinttcp_value = tinttcp_value&~8
    else
      track_color_background = true
      tinttcp_value = tinttcp_value|8
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Checkbox(ctx, 'Item color##2', item_color_background) then
    if item_color_background then
      item_color_background = false
      tinttcp_value = tinttcp_value&~32
    else
      item_color_background = true
      tinttcp_value = tinttcp_value|32
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Checkbox(ctx, 'Take color##2', take_color_background) then
    if take_color_background then
      take_color_background = false
      tinttcp_value = tinttcp_value&~256
    else
      take_color_background = true
      tinttcp_value = tinttcp_value|256
    end
  end
  ImGui.Dummy(ctx, 10, 10)
  ImGui.Dummy(ctx, 10, 10)
  ImGui.Text(ctx, 'Track control panel settings')
  ImGui.Dummy(ctx, 10, 10)
  if ImGui.Checkbox(ctx, 'Set track label background to custom track colors', label_background) then
    if label_background then
      label_background = false
      tinttcp_value = tinttcp_value&~1
    else
      label_background = true
      tinttcp_value = tinttcp_value|1
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Checkbox(ctx, 'Tint track panel background', panel_background) then
    if panel_background then
      panel_background = false
      tinttcp_value = tinttcp_value&~2
    else
      panel_background = true
      tinttcp_value = tinttcp_value|2
    end
  end
  ImGui.Dummy(ctx, 10, 10)
  ImGui.Dummy(ctx, 10, 10)
  if whatIs&16 ~= 0 then
   button_text = 'unable to load rtconfig.txt'
  elseif whatIs&4 ~= 0 or whatIs&8 ~= 0 then
    button_text = 'write to rtconfig.txt'
  else
    button_text = 'reload theme'
  end
  if ImGui.Button(ctx, button_text, 160, 26) then
    WriteToRtconfig()
  end
  ImGui.SameLine(ctx)
  ImGui.Text(ctx, shownstring)
  local path, file_name2, extension =  SplitFileName(lasttheme)
  ImGui.Dummy(ctx, 10, 10)
  if file_name2 then
    ImGui.Text(ctx, 'Theme:  '..file_name2)
    ImGui.Text(ctx, 'Path:   '..path)
  end
end


----------
-- LOOP --

local function loop()
  ImGui.PushFont(ctx, font)
  ImGui.SetNextWindowSize(ctx, 550, 393, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'TintTcp Settings', true)
  if visible then
    main()
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
  
