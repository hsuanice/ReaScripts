-- hsuanice_mouse.lua  (minimal shared mouse guard + click/drag events)
local M = {}

local function hasJS()
  return reaper.APIExists("JS_Mouse_GetState") and reaper.APIExists("JS_Window_Find")
end

local function isPopupOpen()
  if not reaper.APIExists("JS_Window_Find") then return false end
  local h1 = reaper.JS_Window_Find("#32768", true) -- Windows menu
  if h1 and h1 ~= 0 then return true end
  local h2 = reaper.JS_Window_Find("NSMenu",  true) -- macOS menu
  if h2 and h2 ~= 0 then return true end
  return false
end

local function isFocusInMain()
  if not (reaper.APIExists("JS_Window_GetFocus") and reaper.APIExists("JS_Window_IsChild")) then
    return true
  end
  local main = reaper.GetMainHwnd()
  local fh   = reaper.JS_Window_GetFocus()
  if not (main and fh) then return true end
  return (fh == main) or (reaper.JS_Window_IsChild(main, fh) == 1)
end

local function thingAt(x, y)
  local _, info = reaper.GetThingFromPoint(x, y)
  info = tostring(info or "")
  local ctx = "other"
  if info:find("arrange",1,true) then ctx="arrange"
  elseif info:find("tcp",1,true)   then ctx="tcp"
  elseif info:find("env",1,true)   then ctx="envelope"
  elseif info:find("ruler",1,true) then ctx="ruler"
  end
  return info, ctx
end

local function getTrackTCPRect(tr)
  local ok, s = reaper.GetSetMediaTrackInfo_String(tr, "P_UI_RECT:tcp.size", "", false)
  if not ok or s=="" then return end
  local a,b,c,d = s:match("(-?%d+)%s+(-?%d+)%s+(-?%d+)%s+(-?%d+)")
  if not a then return end
  a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
  if c>a and d>b then return a,b,c-a,d-b else return a,b,c,d end
end

local function hitTest(x, y)
  local item = reaper.GetItemFromPoint(x, y, true)
  if item then
    local tr = reaper.GetMediaItem_Track(item)
    local iy = reaper.GetMediaItemInfo_Value(item, "I_LASTY") or 0
    local ih = reaper.GetMediaItemInfo_Value(item, "I_LASTH") or 0
    local _, ty = getTrackTCPRect(tr)
    local upper = false
    if ty and ih and ih>0 then
      local top = ty + iy
      upper = (y <= top + ih*0.5)
    end
    return {
      on_item   = true,
      upper_half= upper,
      track     = tr,
      item      = item,
      in_arrange= true
    }
  end
  local tr = reaper.GetTrackFromPoint(x, y)
  return {
    on_item=false, upper_half=false, item=nil,
    track=tr, in_arrange=(tr ~= nil)
  }
end

local Class = {}
Class.__index = Class

function M.new(opts)
  opts = opts or {}
  local self = {
    tol_px      = opts.tolerance_px or 3,
    drag_thr_px = opts.drag_threshold_px or 4,
    menu_grace  = opts.menu_grace or 0.20,
    rmb_cool    = opts.rmb_cooldown or 0.18,
    focus_grace = opts.focus_grace or 0.20,
    require_fresh_lmb = (opts.require_fresh_lmb ~= false),
    debug   = opts.debug or false,
    prefix  = opts.prefix or "[Mouse] ",
    -- state
    prev_lmb=false, prev_rmb=false, prev_mmb=false,
    lmb=false, rmb=false, mmb=false,
    state="IDLE",
    lmb_armed=true,
    last_btn_change=-1,
    down_x=nil, down_y=nil, down_t=-1,
    last_x=0, last_y=0,
    menu_open=false, menu_closed_t=-1,
    focus_was_main=true, focus_return_t=-1,
    rmb_session=false, rmb_up_t=-1,
  }
  return setmetatable(self, Class)
end

function Class:log(s) if self.debug then reaper.ShowConsoleMsg(("%s%s\n"):format(self.prefix, s)) end end

function Class:tick()
  local now = reaper.time_precise()
  local x,y = reaper.GetMousePosition()
  self.last_x, self.last_y = x,y

  local st = hasJS() and reaper.JS_Mouse_GetState(1+2+64) or 0
  self.lmb = (st & 1)==1
  self.rmb = (st & 2)==2
  self.mmb = (st & 64)==64

  if (self.lmb~=self.prev_lmb) or (self.rmb~=self.prev_rmb) or (self.mmb~=self.prev_mmb) then
    self.last_btn_change = now
  end

  -- Focus guard
  local in_main = isFocusInMain()
  if in_main and not self.focus_was_main then
    self.focus_return_t = now; self.lmb_armed=false
    self:log("focus: latch")
  end
  self.focus_was_main = in_main
  if self.focus_return_t>=0 and (now-self.focus_return_t)<self.focus_grace then
    self:log(("focus: grace dt=%.3f"):format(now-self.focus_return_t))
    self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
    return { blocked=true }
  end

  -- Popup/menu guard
  if isPopupOpen() then
    self.menu_open=true; self.lmb_armed=false
    self:log("menu: open")
    self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
    return { blocked=true }
  elseif self.menu_open then
    self.menu_open=false; self.menu_closed_t=now; self.lmb_armed=false
    self:log("menu: closed_latch")
    self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
    return { blocked=true }
  end
  if self.menu_closed_t>=0 and (now-self.menu_closed_t)<self.menu_grace then
    self:log(("menu: grace dt=%.3f"):format(now-self.menu_closed_t))
    self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
    return { blocked=true }
  end

  -- RMB session/cooldown
  if (not self.rmb_session) and (not self.prev_rmb) and self.rmb then
    self.rmb_session=true; self.rmb_up_t=-1; self.lmb_armed=false
    self:log("rmb: start")
  end
  if self.rmb_session then
    if self.rmb then
      self:log("rmb: hold")
      self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
      return { blocked=true }
    end
    if (not self.rmb) and self.prev_rmb and self.rmb_up_t<0 then
      self.rmb_up_t = now
    end
    if self.rmb_up_t>=0 and (now-self.rmb_up_t)<self.rmb_cool then
      self:log(("rmb: cooldown rem=%.3f"):format(self.rmb_cool-(now-self.rmb_up_t)))
      self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
      return { blocked=true }
    else
      if self.rmb_up_t>=0 then
        self.rmb_session=false; self.rmb_up_t=-1; self.lmb_armed=true
        self:log("rmb: clear")
      end
    end
  end

  -- require fresh LMB after guards
  if self.require_fresh_lmb and not self.lmb_armed then
    local idle_ok = (self.last_btn_change>=0) and ((now-self.last_btn_change)>=0.12)
    if self.lmb and idle_ok then
      self.lmb_armed=true
      self:log("lmb: re-armed")
    else
      self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
      return { blocked=true }
    end
  end

  local l_down = ( self.lmb and not self.prev_lmb)
  local l_up   = ((not self.lmb) and self.prev_lmb)

  local ev = { blocked=false, x=x, y=y }

  if l_down then
    self.state="LMB_G"; self.down_x, self.down_y, self.down_t = x,y,now
  end

  if self.state=="LMB_G" then
    local dx = math.abs(x-(self.down_x or x))
    local dy = math.abs(y-(self.down_y or y))
    ev.drag_dx, ev.drag_dy = dx, dy
    if (dx>=self.drag_thr_px) or (dy>=self.drag_thr_px) then ev.lmb_drag=true end
    if l_up then
      if dx<=self.tol_px and dy<=self.tol_px then ev.lmb_click=true end
      self.state="IDLE"
    end
  end

  if not self.lmb and not self.rmb and not self.mmb and self.state~="LMB_G" then
    self.state="IDLE"
  end

  self.prev_lmb, self.prev_rmb, self.prev_mmb = self.lmb, self.rmb, self.mmb
  return ev
end

function Class:hit()
  local _, ctx = thingAt(self.last_x, self.last_y)
  if ctx ~= "arrange" then return {context=ctx, in_arrange=false} end
  local h = hitTest(self.last_x, self.last_y)
  h.context="arrange"
  return h
end

return M
