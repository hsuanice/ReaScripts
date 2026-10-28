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
local env = setmetatable({ r = r, gfx = gfx, NS = "hsuanice_PM",
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
check("typed name added with file spelling as alias", readf():find("New Film = NewFilm", 1, true) and ext.PROJECT_NAME == "New Film")
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
  readf():find("\nPoint Up = Point, PointUp_AAP\n", 1, true) and M.lookup("POINT") == "Point Up")
ext = { PROJECT_NAME = "POINT" }; proj_fn = "/x/R5/261026----POINT----R5----dialog.RPP"
check("rename: saved old name resolves to the new one", M.official("POINT") == "Point Up" and M.prefix() == "Point Up R5 Dialog | ")
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
print(pass .. " passed, " .. fail .. " failed")
os.execute('rm -rf "' .. WL_DIR .. '"')
if fail > 0 then os.exit(1) end
