--[[
@description FX Alias Build - Build FX Alias JSON from Current Project
@version 0.1.0
@author hsuanice
@provides
  [main] .
@about
  Scan all tracks' Track FX in the current project and populate/merge Settings/fx_alias.json.
  Then you can export to TSV and edit aliases comfortably.

  Part of AudioSweet ReaImGui Tools suite.

@changelog
  0.1.0 [Internal Build 251216.1820] - Settings Directory Safeguard
    - ADDED: Automatically create the Settings folder before writing fx_alias.json to avoid write errors.
    - ADDED: Clear warning dialog if the folder cannot be created so the user knows why the build stops.
  [internal: v251030.1600]
    - Initial Public Beta Release
    - FX Alias database builder tool featuring:
      • Scans all Track FX in current project
      • Creates/updates Settings/fx_alias.json database
      • Accessible from AudioSweet ReaImGui: Settings → FX Alias Tools → Build FX Alias Database
      • Integration with AudioSweet file naming system
    - Initial release [internal: v251007]
]]--

-- ==== tiny dkjson (trimmed) ====
local json=(function()local j={};local function esc(c)local x=string.byte(c)local m={[8]='\\b',[9]='\\t',[10]='\\n',[12]='\\f',[13]='\\r',[34]='\\"',[92]='\\\\'};local e=m[x];if e then return e end;if x<32 then return string.format("\\u%04x",x) end;return c end
local function isarr(t)local n=0 for k in pairs(t)do if type(k)~="number"then return false end if k>n then n=k end end for i=1,n do if t[i]==nil then return false end end return true,n end
local function enc(v)local t=type(v)if t=="nil"then return"null"elseif t=="number"then return string.format("%.14g",v)elseif t=="boolean"then return v and"true"or"false"elseif t=="string"then return'"'..v:gsub('[%z\1-\31\\"]',esc)..'"'elseif t=="table"then local a,n=isarr(v)if a then local o={}for i=1,n do o[#o+1]=enc(v[i])end;return"["..table.concat(o,",").."]"else local o={}for k,val in pairs(v)do o[#o+1]=enc(tostring(k))..":"..enc(val)end;return"{"..table.concat(o,",").."}"end end;return"null"end
local function sw(s,i)local _,j=s:find("^[ \n\r\t]*",i)return(j or i-1)+1 end
local function pv(s,i)i=sw(s,i)local c=s:sub(i,i)if c=="{"then local o={}i=i+1;i=sw(s,i)if s:sub(i,i)=="}"then return o,i+1 end;while true do local k;k,i=pv(s,i)if type(k)~="string"then error("JSON key error")end;i=sw(s,i)if s:sub(i,i)~=":"then error("JSON :")end;i=i+1;local v;v,i=pv(s,i);o[k]=v;i=sw(s,i)local ch=s:sub(i,i)if ch=="}"then return o,i+1 end;if ch~=","then error("JSON ,}")end;i=i+1 end
elseif c=="["then local a={}i=i+1;i=sw(s,i)if s:sub(i,i)=="]"then return a,i+1 end;while true do local v;v,i=pv(s,i);a[#a+1]=v;i=sw(s,i)local ch=s:sub(i,i)if ch=="]"then return a,i+1 end;if ch~=","then error("JSON ,]")end;i=i+1 end
elseif c=='"'then local j1=i+1;local o={}while true do local ch=s:sub(j1,j1)if ch==""then error("JSON string")end;if ch=='"'then return table.concat(o),j1+1 elseif ch=="\\"then local e=s:sub(j1+1,j1+1)if e=="u"then local hex=s:sub(j1+2,j1+5)o[#o+1]=utf8.char(tonumber(hex,16));j1=j1+6 else local m={b="\b",f="\f",n="\n",r="\r",t="\t",['"']='"',['\\']='\\',['/']='/'}o[#o+1]=m[e]or e;j1=j1+2 end else o[#o+1]=ch;j1=j1+1 end end
else local lit=s:match("^true",i)if lit then return true,i+4 end;lit=s:match("^false",i)if lit then return false,i+5 end;lit=s:match("^null",i)if lit then return nil,i+4 end;local num=s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*",i)if num and#num>0 then return tonumber(num),i+#num end;error("JSON unexpected")end end
function j.decode(s)local ok,res=pcall(function()local v,ii=pv(s,1)return v end)return ok and res or nil end
j.encode=enc;return j end)()
-- ============================

local function resource_path() return reaper.GetResourcePath() end
local function settings_dir()  return resource_path().."/Scripts/hsuanice Scripts/Settings" end
local function ensure_settings_dir()
  local dir = settings_dir()
  local ok = reaper.RecursiveCreateDirectory(dir, 0)
  return (ok == 1 or ok == true) and dir or nil
end
local function read_file(p) local f=io.open(p,"rb");if not f then return nil end;local s=f:read("*a");f:close();return s end
local function write_file(p,t) local f=io.open(p,"wb");if not f then return false end;f:write(t or "");f:close();return true end

-- same parser used in your main script
local function trim(s)return (s and s:gsub("^%s+",""):gsub("%s+$",""))or"" end
local function parse_fx_label(raw)
  raw=tostring(raw or"")
  local typ,rest=raw:match("^([%w%+%._-]+):%s*(.+)$");rest=rest or raw
  local core,vendor=rest,nil
  local core_only,v=rest:match("^(.-)%s*%(([^%(%)]+)%)%s*$")
  if core_only then core,vendor=core_only,v end
  return trim(typ),trim(core),trim(vendor)
end
local function normalize_token(s) -- keep alnum only
  return (tostring(s or ""):gsub("[^%w]+","")):lower()
end
local function make_fingerprint(raw_label)
  local typ,core,vendor = parse_fx_label(raw_label)
  local t = normalize_token(typ)
  local c = normalize_token(core)
  local v = normalize_token(vendor)
  return table.concat({t,c,v},"|")
end

-- 預設別名：移除非英數與空白；若 core 為空則用 vendor..core 兜底
local function default_alias(core, vendor)
  local a = tostring(core or ""):gsub("[^%w]+","")
  if a == "" then
    a = (tostring(vendor or "") .. tostring(core or "")):gsub("[^%w]+","")
  end
  return a
end

local function now_iso()
  local t=os.date("!*t") -- UTC 避免時區差異
  return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",t.year,t.month,t.day,t.hour,t.min,t.sec)
end

local function main()
  local dir = ensure_settings_dir()
  if not dir then
    reaper.MB("Failed to create Settings folder:\n"..settings_dir(), "Build FX Alias JSON", 0)
    return
  end
  local json_path = dir.."/fx_alias.json"

  local obj = {}
  local raw = read_file(json_path)
  if raw and raw~="" then
    obj = json.decode(raw) or {}
  end

local added, merged = 0, 0
local scanned = 0

-- 兼容不同 REAPER 版本的 EnumInstalledFX 回傳形式
local function enum_installed_fx(i)
  local a,b = reaper.EnumInstalledFX(i, "")
  if type(a) == "string" and (b == nil or type(b) == "number") then
    -- 舊式：只回傳字串
    return a
  end
  -- 新式：回傳成功布林與字串
  return b
end

for i=0, 1000000 do
  local rawlabel = enum_installed_fx(i)
  if not rawlabel or rawlabel == "" then break end
  scanned = scanned + 1

  local fp = make_fingerprint(rawlabel)
  local typ, core, vendor = parse_fx_label(rawlabel)
  local rec = obj[fp]

  if not rec then
    rec = {
      alias             = default_alias(core, vendor),  -- 只在新建時給預設 alias
      normalized_core   = core,
      normalized_vendor = vendor,
      raw_examples      = { rawlabel },
      seen_types        = (typ and typ~="" and {typ}) or {},
      last_seen         = now_iso(),
    }
    obj[fp] = rec
    added = added + 1
  else
    -- merge 到既有紀錄
    local seen = {}
    for _,s in ipairs(rec.raw_examples or {}) do seen[s]=true end
    if not seen[rawlabel] then
      table.insert(rec.raw_examples, rawlabel)
    end

    local tseen = {}
    for _,s in ipairs(rec.seen_types or {}) do tseen[s]=true end
    if typ and typ~="" and not tseen[typ] then
      table.insert(rec.seen_types, typ)
    end

    if not rec.normalized_core or rec.normalized_core=="" then rec.normalized_core = core end
    if not rec.normalized_vendor or rec.normalized_vendor=="" then rec.normalized_vendor = vendor end

    -- 只在 alias 目前為空時才自動補預設別名；已有內容一律不動
    if not rec.alias or rec.alias == "" then
      rec.alias = default_alias(core, vendor)
    end

    rec.last_seen = now_iso()
    merged = merged + 1
  end
end
  -- 寫回
  if not write_file(json_path, json.encode(obj)) then
    reaper.MB("Failed to write "..json_path, "Build FX Alias JSON", 0)
    return
  end

  reaper.ShowConsoleMsg(("[FX ALIAS][BUILD]\n  scanned plugins: %d\n  added: %d, merged: %d\n  JSON: %s\n"):format(scanned, added, merged, json_path))
end

reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Build FX Alias JSON from Current Project", -1)
