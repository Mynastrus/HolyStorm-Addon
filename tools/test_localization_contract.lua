-- Static AceLocale contract check across Holy Storm source. Literal lookups,
-- including keys reached through a locale(prefix) proxy, are checked here.
-- Runtime-computed keys such as STATUS_<state>, STAT_<name>, FACTION_<faction>,
-- and RAID_DIFFICULTY_<id> remain covered by focused feature tests.
local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local function read(path)local f=assert(io.open(path,"rb"),path);local s=f:read("*a");f:close();return s end
local function files(root)
 local out={};local p=assert(io.popen('rg --files "'..root..'" -g "*.lua" -g "!**/Libs/**" -g "!**/_ace3_source/**"',"r"));for path in p:lines()do out[#out+1]=path:gsub("\\","/")end;assert(p:close());return out
end
local definitions,seenAssignments={},{}
local luaFiles=files(workspace.."/LIVE")
local commonMojibake={"\195\131\198\146","\195\131\226\128\154","\195\131\194\162","\195\175\194\191\194\189"}
for _,path in ipairs(luaFiles)do
 local source=read(path)
 for _,pattern in ipairs(commonMojibake)do assert(not source:find(pattern,1,true),"common mojibake in "..path)end
 for _,pattern in ipairs({"Ãƒ","Ã‚","Ã¢","ï¿½"})do assert(not source:find(pattern,1,true),"known mojibake in "..path..": "..pattern)end
  local namespace,locale=source:match('NewLocale%(%s*"([^"]+)"%s*,%s*"([^"]+)"')
  if not namespace then locale=path:match("([%a]+)%.lua$");if path:find("/Holy_Storm/Locales/",1,true)then namespace="Holy_Storm"end end
  if namespace and(locale=="enUS"or locale=="deDE")then
   definitions[namespace]=definitions[namespace]or{enUS={},deDE={}};local target=definitions[namespace][locale]
   for key,value in source:gmatch('L%["([%w_%.%-]+)"%]%s*=%s*"([^"]*)"')do
    local signature=namespace.."\031"..locale.."\031"..key;assert(not seenAssignments[signature]or seenAssignments[signature]==value,"conflicting duplicate locale registration: "..signature);seenAssignments[signature]=value;target[key]=true
   end
  end
end
for namespace,pair in pairs(definitions)do
 for key in pairs(pair.enUS)do assert(pair.deDE[key],namespace.." deDE missing "..key)end
 for key in pairs(pair.deDE)do assert(pair.enUS[key],namespace.." enUS missing "..key)end
end
local dynamicLookupPrefixes={
 ["LIVE/Holy_Storm_Characters/UI/CharacterUI.lua"]={"FACTION_","STATUS_","STAT_"},
 ["LIVE/Holy_Storm_Characters/UI/CharacterOverview.lua"]={"FACTION_","STAT_"},
 ["LIVE/Holy_Storm_Characters/UI/StoredFeatureTabs.lua"]={"RAID_DIFFICULTY_"},
 ["LIVE/Holy_Storm_Guild/Guild.lua"]={"ROSTER_STATUS_","ROSTER_ADDON_"},
 ["LIVE/Holy_Storm_UI/UI/Framework/Dashboard.lua"]={{namespace="Holy_Storm_CharacterUI",prefix="RAID_DIFFICULTY_"}},
}
for _,path in ipairs(luaFiles)do
 if not path:match("Locales[\\/]?.*%.lua$")then
  local source=read(path);local namespace=source:match('GetLocale%(%s*"([^"]+)"')
  for _,pattern in ipairs(commonMojibake)do assert(not source:find(pattern,1,true),"common mojibake in "..path)end
  if namespace then
   local available=definitions[namespace]
   local prefix="";local relativePath=path:sub(#workspace+2):gsub("\\","/")
   for line in source:gmatch("[^\r\n]+")do
    local declaredPrefix=line:match('local%s+L%s*=%s*locale%(%s*"([^"]+)"')
    if declaredPrefix then prefix=declaredPrefix end
    for key in line:gmatch('L%["([%w_%.%-]+)"%]%s*[^=]')do
     -- Prefix proxy access uses the literal suffix; concatenated lookups do
     -- not match this pattern and are documented in dynamicLookupPrefixes.
     local resolved=prefix..key
     if not resolved:match("_$")then assert(available and available.enUS[resolved]and available.deDE[resolved],path.." requests unregistered locale key "..namespace..":"..resolved)end
    end
   end
   for _,dynamicEntry in ipairs(dynamicLookupPrefixes[relativePath]or{})do
    local dynamicNamespace,dynamicPrefix
    if type(dynamicEntry)=="table"then dynamicNamespace,dynamicPrefix=dynamicEntry.namespace,dynamicEntry.prefix else dynamicNamespace,dynamicPrefix=namespace,dynamicEntry end
    local found=false
    local dynamicDefinitions=definitions[dynamicNamespace]
    for key in pairs(dynamicDefinitions and dynamicDefinitions.enUS or{})do if key:sub(1,#dynamicPrefix)==dynamicPrefix then found=true;break end end
    assert(found,path.." documents dynamic locale prefix without registered entries: "..tostring(dynamicNamespace)..":"..tostring(dynamicPrefix))
   end
  end
  for _,pattern in ipairs({"Ãƒ","Ã‚","Ã¢","ï¿½"})do assert(not source:find(pattern,1,true),"known mojibake in "..path..": "..pattern)end
  assert(not source:find('definition.category or"Core"):gsub',1,true),"locale keys must not be derived from a translated category label: "..path)
 end
end
print("Project AceLocale namespace parity, static and prefixed requests, documented dynamic lookups, duplicate conflicts and mojibake checks passed")
