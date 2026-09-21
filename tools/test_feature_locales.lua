-- Feature addons must own complete, paired enUS/deDE locale definitions.
local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local live=workspace.."/LIVE"
local folders={"Achievements","Calendar","Characters","Chat","Delves","Equipment","Guild","GuildLog","MythicPlus","News","POI","Positions","Professions","Raids"}
local function read(path)local file=assert(io.open(path,"rb"),path);local value=file:read("*a");file:close();return value end
local function keys(source)local out={};for key in source:gmatch('L%["([^"\r\n]+)"%]')do out[key]=true end;return out end
local function files(root)
 local result={};local process=assert(io.popen('rg --files "'..root..'" -g "*.lua"',"r"));for path in process:lines()do result[#result+1]=path:gsub("\\","/")end;assert(process:close(),"locale file enumeration failed");return result
end
for _,name in ipairs(folders)do
 local root=live.."/Holy_Storm_"..name;local definitions={};local luaFiles=files(root)
 for _,path in ipairs(luaFiles)do
  if path:match("/Locales/enUS%.lua$")then
   local german=path:gsub("/enUS%.lua$","/deDE.lua");local en,de=keys(read(path)),keys(read(german))
   for key in pairs(en)do assert(de[key],german.." missing "..key)end
   for key in pairs(de)do assert(en[key],path.." missing "..key)end
   for key in pairs(en)do definitions[key]=true end
  end
 end
 for _,path in ipairs(luaFiles)do if not path:match("/Locales/")then local source=read(path);if not source:find('GetLocale("Holy_Storm")',1,true)then for key in pairs(keys(source))do assert(definitions[key],path.." uses undefined feature locale "..key)end end end end
end
print("Feature locale ownership and enUS/deDE parity passed")
