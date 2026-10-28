-- @noindex  (local test for the project master list in Various/hsuanice_Project Manager - PM Timer.lua)
-- Runs the "Project master list" block and the project prefix functions with a stubbed REAPER:
-- PM Projects.txt create / alias / rename-by-hand / typed name / cancel.
-- usage (repo root): lua .dev/tests/mock_pm_timer_projects.lua
local REPO = debug.getinfo(1, "S").source:match("^@(.*)/%.dev/tests/") or "."
local OUT = os.tmpname(); os.remove(OUT)
local WL_DIR = OUT .. "_wl"
os.execute('mkdir -p "' .. WL_DIR .. '"')
arg = { REPO .. "/Various/hsuanice_Project Manager - PM Timer.lua", WL_DIR }
local SRC, WL = arg[1], arg[2]
local env
local src = io.open(SRC):read("a")
local a = src:find("-- ── Project master list", 1, true)
local b = src:find("local function build_project_process_name", 1, true)
local chunk = src:sub(a, b - 1)
local ext, gext, proj_fn, menu_choice, inputs = {}, {}, "", 0, nil
local menus = {}
r = {
  GetExtState = function(ns, k) return gext[k] or "" end,
  SetExtState = function(ns, k, v) gext[k] = v end,
  EnumProjects = function(i) if i == -1 or i == 0 then return {}, proj_fn end return nil end,
  GetUserFileNameForRead = function() return true, WL .. "/Work Log.RPP" end,
  GetUserInputs = function(_, _, _, def) return true, inputs or def end,
}
gfx = { showmenu = function(m) menus[#menus + 1] = m; return menu_choice end }
env = setmetatable({ r = r, gfx = gfx, NS = "hsuanice_PM",
  get_extstate = function(k) return ext[k] end, set_extstate = function(k, v) ext[k] = v end,
  get_proj_identity = function() return proj_fn end }, { __index = _G })
local fn = assert(load(chunk .. "\nreturn { check = check_project_name, prefix = get_proj_prefix, wf = get_project_workflow_prefix_fallback, task = get_proj_task, official = official_project_name, load = load_master, lookup = master_lookup, rename = master_rename, merge = master_merge, save = save_master }", "chunk", "t", env))
local M = fn()
local pass, fail = 0, 0
local function check(name, c) if c then pass = pass + 1 else fail = fail + 1; print("FAIL " .. name) end end
local function readf() local f = io.open(WL .. "/PM Projects.txt"); if not f then return "" end local t = f:read("a"); f:close(); return t end

-- 1. no Work Log known yet -> asks for Work Log.RPP; unknown name -> menu; pick "Add as new: Point"
proj_fn = "/x/ISO AAP/261028----Point----AAP.RPP"; menu_choice = 2
M.check()
check("work log dir remembered", gext.WORK_LOG_DIR == WL)
check("menu asked", #menus == 1 and menus[1]:find("file name: Point", 1, true))
check("new project saved", readf():find("\nPoint\n", 1, true) and ext.PROJECT_NAME == "Point")
-- asked once per run
M.check(); check("asked only once per project", #menus == 1)

-- 2a. "POINT" differs only in case -> known, no menu
ext = {}; proj_fn = "/x/R5/261026----POINT----R5----dialog.RPP"; menus = {}
M.check()
check("case-only difference: no menu", #menus == 0 and ext.PROJECT_NAME == "Point")
-- 2b. "PointUp" (other spelling) -> pick existing "Point" (choice 5 = first project in the list)
ext = {}; proj_fn = "/x/old/260820----PointUp----AAP.RPP"; menu_choice = 5; menus = {}
M.check()
check("menu lists projects with the current one checked", menus[1] and menus[1]:find("|Point", 1, true))
check("alias added to existing", readf():find("Point = PointUp", 1, true) and ext.PROJECT_NAME == "Point")

-- 3. user renames the official name by hand: "POINT = Point, PointUp_AAP" ; files with any spelling resolve
local f = io.open(WL .. "/PM Projects.txt", "w"); f:write("# c\nPOINT = Point, PointUp_AAP\nFishTown\nTheFixer\n"); f:close()
M.load()
ext = { PROJECT_NAME = "Point" }  -- saved before the rename
proj_fn = "/x/ISO AAP/261028----Point----AAP.RPP"
check("saved name follows the master (Point -> POINT)", M.official("Point") == "POINT")
check("AAP prefix uses official name", M.wf() == "POINT AAP | ")
ext = {}; proj_fn = "/x/R5/261026----point----R5----dialog.RPP"; menus = {}
M.check()
check("known spelling: no menu, saved", #menus == 0 and ext.PROJECT_NAME == "POINT")
check("dialog prefix: official name + Dialog", M.prefix() == "POINT R5 Dialog | " and M.task() == "Dialog")
ext = {}; proj_fn = "/x/old/PointUp_AAP.RPP"
check("plain file name: no parts, no menu", (function() menus = {}; M.check(); return #menus == 0 end)())

-- 4. typed new name
ext = {}; proj_fn = "/x/y/261101----NewFilm----R1----Dialog.RPP"; menu_choice = 3; inputs = "New Film"; menus = {}
M.check()
check("typed name (spaces -> _) added with file spelling as alias", readf():find("New_Film = NewFilm", 1, true) and ext.PROJECT_NAME == "New_Film")
check("file keeps the header comment", readf():find("^# PM Projects"))
-- 5. cancel
ext = {}; proj_fn = "/x/z/261101----Other----R1----Dialog.RPP"; menu_choice = 0
M.check(); check("cancel: nothing saved", ext.PROJECT_NAME == nil and not readf():find("Other", 1, true))
check("cancel: prefix keeps the file-name name", M.prefix() == "Other R1 Dialog | ")
-- 6. rename: old name becomes an alias; a saved old name follows
local function setlist(txt) local f = io.open(WL .. "/PM Projects.txt", "w"); f:write(txt); f:close(); M.load() end
setlist("POINT = Point, PointUp_AAP\nFishTown\nTheFixer\n")
check("rename", M.rename("POINT", "Point Up") == "renamed" and M.save())
check("rename: old name is an alias (POINT is covered by Point - case-insensitive)",
  readf():find("\nPoint_Up = Point, PointUp_AAP\n", 1, true) and M.lookup("POINT") == "Point_Up")
ext = { PROJECT_NAME = "POINT" }; proj_fn = "/x/R5/261026----POINT----R5----dialog.RPP"
check("rename: spaces become _ (one word, the first word of an item name is the project)", M.lookup("point_up") == "Point_Up")
check("rename: saved old name resolves to the new one", M.official("POINT") == "Point_Up" and M.prefix() == "Point_Up R5 Dialog | ")
check("rename: change of case only adds no alias", M.rename("TheFixer", "THEFIXER") == "renamed" and M.save()
  and readf():find("\nTHEFIXER\n", 1, true))
check("rename to another project's name -> exists", M.rename("FishTown", "point up") == "exists")
check("rename to the same name -> nothing", M.rename("FishTown", "FishTown") == nil)
-- 7. merge: name + aliases move, entry removed
setlist("POINT = Point\nPointUp_AAP = PointUp\nFishTown\n")
check("merge", M.merge("PointUp_AAP", "POINT") and M.save())
check("merge: list", readf():find("\nPOINT = Point, PointUp_AAP, PointUp\nFishTown\n", 1, true) and not readf():find("\nPointUp_AAP =", 1, true))
check("merge: old name resolves", M.lookup("pointup") == "POINT" and M.lookup("PointUp_AAP") == "POINT")
check("merge into itself -> false", M.merge("POINT", "point") == false)
-- 8. apply the list to the Work Log (latest names everywhere)
setlist("TEST = POINT, Point, PointUp_AAP\nFishTown\n")
do
  local a2 = src:find("-- ── Apply the project list to the Work Log", 1, true)
  local b2 = src:find("local function action_apply_names_to_work_log", 1, true)
  local items = {}
  local function it(n, lock) local x = { name = n, lock = lock or 1 }; items[#items + 1] = x; return x end
  local tr = { { name = "2026-10-20", items = { it("POINT R5 Dialog | editing"), it("PointUp_AAP | aap"), it("aap | aap"),
    it("TheFixer EP10 Dialog | denoise"), it("TEST R5 Dialog | check"), it("261020 POINT R5 | mic select"), it("no prefix") } },
    { name = "Point", items = {} } }
  local undo = 0
  r.EnumProjects = function(i) if i == 0 then return "WLPROJ", WL .. "/Work Log.RPP" end end
  r.CountTracks = function() return #tr end
  r.GetTrack = function(_, i) return tr[i + 1] end
  r.GetTrackName = function(t) return true, t.name end
  r.GetSetMediaTrackInfo_String = function(t, _, v) t.name = v end
  r.CountTrackMediaItems = function(t) return #t.items end
  r.GetTrackMediaItem = function(t, j) return t.items[j + 1] end
  r.GetActiveTake = function(x) return x end
  r.GetTakeName = function(x) return x.name end
  r.GetSetMediaItemTakeInfo_String = function(x, _, v) x.name = v end
  r.GetMediaItemInfo_Value = function(x) return x.lock end
  r.SetMediaItemInfo_Value = function(x, _, v) x.lock = v end
  r.Undo_BeginBlock2 = function() undo = undo + 1 end
  r.Undo_EndBlock2 = function() undo = undo + 1 end
  env.find_work_log_project = function() return "WLPROJ" end
  env.load_master, env.master_lookup = M.load, M.lookup
  local fn2 = assert(load(src:sub(a2, b2 - 1) .. "\nreturn apply_master_to_work_log", "apply", "t", env))()
  local n = fn2()
  local names = {}
  for _, x in ipairs(tr[1].items) do names[#names + 1] = x.name end
  check("Work Log: 2 items renamed", n == 2)
  check("Work Log: POINT and PointUp_AAP -> TEST", names[1] == "TEST R5 Dialog | editing" and names[2] == "TEST | aap")
  check("Work Log: unknown names left alone", names[3] == "aap | aap" and names[4] == "TheFixer EP10 Dialog | denoise"
    and names[6] == "261020 POINT R5 | mic select" and names[7] == "no prefix")
  check("Work Log: lock restored, one undo block", tr[1].items[1].lock == 1 and undo == 2)
  check("Work Log: DurationOnly project track renamed", tr[2].name == "TEST")
end
print(pass .. " passed, " .. fail .. " failed")
os.execute('rm -rf "' .. WL_DIR .. '"')
if fail > 0 then os.exit(1) end
