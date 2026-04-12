-- @description ProTools Create Memory Location on Ruler
-- @author hsuanice
-- @version 260412.1930
-- @changelog
--   260412.1930 — Fix: swap commands (playing/recording → 40157; stopped → 40171)
--   260412.1928 — Initial release
-- @about
--   Mimics Pro Tools' Create Memory Location behavior.
--   - Playing or recording: Insert marker at current position (40157)
--   - Not playing/recording: Insert and/or edit marker at current position (40171)

local play_state = reaper.GetPlayState()
-- play_state bits: 1=playing, 2=paused, 4=recording

local is_playing   = (play_state & 1) ~= 0
local is_recording = (play_state & 4) ~= 0

if is_playing or is_recording then
  reaper.Main_OnCommand(40157, 0) -- Insert marker at current position
else
  reaper.Main_OnCommand(40171, 0) -- Insert and/or edit marker at current position
end
