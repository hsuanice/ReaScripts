-- @description hsuanice_PT2Reaper - Debug Grid Size v2
-- @version 0.1.0 [260415]
-- @author hsuanice

local r = reaper
r.ShowConsoleMsg("=== Grid Debug v2 ===\n")

local cursor = r.GetCursorPosition()
r.ShowConsoleMsg("Cursor: " .. tostring(cursor) .. "\n")

-- Method A: prev → next from cursor (current approach, gives 2x)
local prev_g = r.BR_GetPrevGridDivision(cursor)
local next_g = r.BR_GetNextGridDivision(cursor)
r.ShowConsoleMsg("A: prev=" .. tostring(prev_g) .. " next=" .. tostring(next_g) .. "\n")
r.ShowConsoleMsg("A interval (next-prev): " .. tostring(next_g - prev_g) .. "\n")

-- Method B: snap cursor to grid, then get next from there
local snapped = r.SnapToGrid(0, cursor)
local next_from_snap = r.BR_GetNextGridDivision(snapped)
r.ShowConsoleMsg("B: snapped=" .. tostring(snapped) .. " next=" .. tostring(next_from_snap) .. "\n")
r.ShowConsoleMsg("B interval (next-snapped): " .. tostring(next_from_snap - snapped) .. "\n")

-- Method C: prev of prev_g
local prev_prev = r.BR_GetPrevGridDivision(prev_g - 0.0001)
r.ShowConsoleMsg("C: prev_prev=" .. tostring(prev_prev) .. "\n")
r.ShowConsoleMsg("C interval (prev-prev_prev): " .. tostring(prev_g - prev_prev) .. "\n")

-- Method D: next of prev_g  
local next_of_prev = r.BR_GetNextGridDivision(prev_g + 0.0001)
r.ShowConsoleMsg("D: next_of_prev=" .. tostring(next_of_prev) .. "\n")
r.ShowConsoleMsg("D interval (next_of_prev - prev_g): " .. tostring(next_of_prev - prev_g) .. "\n")

r.ShowConsoleMsg("=== Done ===\n")
