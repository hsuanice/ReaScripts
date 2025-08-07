--[[
@description ReaImGui - Show Project Frame Rate
@version 1.0
@author hsuanice

@about
  Displays current project frame rate in a minimal HUD.  
  - Auto-resizes to fit content.  
  - Updates in real time.  
  - Right-click inside window to close instantly.

  💡 Useful for video-sync workflows and visual debugging.  
    Designed for ReaImGui environments where timeline FPS feedback is critical.

  This script was generated using ChatGPT based on design concepts and iterative testing by hsuanice.  
  hsuanice served as the workflow designer, tester, and integrator for this tool.
@changelog
  v1.0 - Initial release
--]]

local ctx = reaper.ImGui_CreateContext('FrameRateDisplay')

local window_flags =
    reaper.ImGui_WindowFlags_NoTitleBar() |
    reaper.ImGui_WindowFlags_NoCollapse() |
    reaper.ImGui_WindowFlags_NoResize() |
    reaper.ImGui_WindowFlags_AlwaysAutoResize()

function loop()
  local visible, open = reaper.ImGui_Begin(ctx, 'Project Frame Rate', true, window_flags)

  if visible then
    local fps = reaper.TimeMap_curFrameRate(0)
    local fps_str = string.format("Frame Rate: %.3f fps", fps)
    reaper.ImGui_Text(ctx, fps_str)

    
    if reaper.ImGui_IsMouseClicked(ctx, 1) and reaper.ImGui_IsWindowHovered(ctx) then
      open = false
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  else
    
    
    ctx = nil
  end
end

reaper.defer(loop)

