-- Static AceLocale contract check across Holy Storm source. Truly computed
-- lookups and prefix proxy tables remain covered by focused feature tests.
local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local function read(path)local f=assert(io.open(path,"rb"),path);local s=f:read("*a");f:close();return s end
local function files(root)
 local out={};local p=assert(io.popen('rg --files "'..root..'" -g "*.lua" -g "!**/Libs/**" -g "!**/_ace3_source/**"',"r"));for path in p:lines()do out[#out+1]=path:gsub("\\","/")end;assert(p:close());return out
end
local definitions,seenAssignments={},{}
local luaFiles=files(workspace.."/LIVE")
for _,path in ipairs(luaFiles)do
 local source=read(path)
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
local skippedPrefixProxy={ ["LIVE/Holy_Storm_Characters/UI/StoredFeatureTabs.lua"]=true }
local skippedFiles={}
for _,path in ipairs(luaFiles)do
 if not path:match("Locales[\\/]?.*%.lua$")then
  local source=read(path);local namespace=source:match('GetLocale%(%s*"([^"]+)"')
  if namespace and not skippedPrefixProxy[path:sub(#workspace+2)]then
   local available=definitions[namespace]
   for key in source:gmatch('L%["([%w_%.%-]+)"%]%s*[^=]')do
    -- A trailing underscore is a computed prefix, not a complete static key.
    if not key:match("_$")then assert(available and available.enUS[key]and available.deDE[key],path.." requests unregistered locale key "..namespace..":"..key)end
   end
  end
  for _,pattern in ipairs({"Ãƒ","Ã‚","Ã¢","ï¿½"})do assert(not source:find(pattern,1,true),"known mojibake in "..path..": "..pattern)end
  assert(not source:find('definition.category or"Core"):gsub',1,true),"locale keys must not be derived from a translated category label: "..path)
 end
end
print("Project AceLocale namespace parity, static requests, duplicate conflicts and mojibake checks passed")
