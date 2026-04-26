--[[
@description BirdBird Global Sampler — Time Sync Daemon (toggle)
@version 260427.0025
@author hsuanice
@about
  Companion to BirdBird Global Sampler. While ON (toolbar lit), the
  paired Spot Time Sync action can recover the most recent play→stop
  session from the JSFX buffer and place it on the timeline at the
  correct project position with handles preserved.

  This script is a toggle:
    - First run  : starts the daemon (toolbar lights up)
    - Second run : stops the daemon (toolbar dims)

  The daemon itself does very little — its main job is to publish a
  "sync is enabled" indicator so you know whether the spot action will
  succeed. The actual play-session bookkeeping is done sample-accurately
  by the patched BirdBird JSFX.

  Requires:
    - BirdBird Global Sampler JSFX, patched to expose gmem slots
      15 / 17 / 18 / 19 / 20 (see Spot Time Sync script header).

@changelog
  v260427.0025
    - Initial release.
]]--

local NS = "hsuanice_GS_TimeSync"

local _, _, sectionID, cmdID = reaper.get_action_context()

local function set_toolbar(on)
  reaper.SetToggleCommandState(sectionID, cmdID, on and 1 or 0)
  reaper.RefreshToolbar2(sectionID, cmdID)
end

local function defer_loop()
  if reaper.GetExtState(NS, "daemon_stop_req") == "1" then
    reaper.DeleteExtState(NS, "daemon_stop_req", false)
    reaper.DeleteExtState(NS, "daemon_heartbeat", false)
    set_toolbar(false)
    return
  end
  reaper.SetExtState(NS, "daemon_heartbeat",
    string.format("%.6f", reaper.time_precise()), false)
  reaper.defer(defer_loop)
end

reaper.atexit(function()
  reaper.DeleteExtState(NS, "daemon_heartbeat", false)
  set_toolbar(false)
end)

local function main()
  local last_hb = tonumber(reaper.GetExtState(NS, "daemon_heartbeat")) or 0
  local now = reaper.time_precise()
  local alive = (now - last_hb) < 1.0

  if alive then
    reaper.SetExtState(NS, "daemon_stop_req", "1", false)
    set_toolbar(false)
  else
    reaper.gmem_attach("BB_Sampler")
    set_toolbar(true)
    reaper.defer(defer_loop)
  end
end

main()
