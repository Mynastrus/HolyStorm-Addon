-- Structural contract for the standalone Holy Storm addon family.
local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local live=workspace.."/LIVE/"
local features={
 {folder="Holy_Storm_Characters",title="Characters",module="Characters.lua"},
 {folder="Holy_Storm_Equipment",title="Equipment",module="Equipment.lua",block="equipment"},
 {folder="Holy_Storm_Raids",title="Raids",module="Raids.lua",block="raid"},
 {folder="Holy_Storm_MythicPlus",title="Mythic+",module="MythicPlus.lua",block="mythicPlus"},
 {folder="Holy_Storm_Delves",title="Delves",module="Delves.lua",block="delves"},
 {folder="Holy_Storm_Calendar",title="Calendar",module="Calendar.lua"},
 {folder="Holy_Storm_Professions",title="Professions",module="Professions.lua",block="professions"},
 {folder="Holy_Storm_Guild",title="Guild",module="Guild.lua"},
 {folder="Holy_Storm_GuildLog",title="Guild Log",module="GuildLog.lua"},
 {folder="Holy_Storm_News",title="News",module="News.lua",store="Persistence/ContentStore.lua"},
 {folder="Holy_Storm_Achievements",title="Achievements",module="Achievements.lua",store="Persistence/AchievementStore.lua"},
 {folder="Holy_Storm_POI",title="POI",module="POI.lua",store="Persistence/POIStore.lua"},
 {folder="Holy_Storm_Positions",title="Positions",module="Positions.lua"},
}
local function read(path)local file=assert(io.open(path,"rb"),path);local value=file:read("*a");file:close();return value end
local function exists(path)local file=io.open(path,"rb");if file then file:close();return true end;return false end
local function tocEntries(root,toc)
 local entries={}
 for line in toc:gmatch("[^\r\n]+")do local value=line:match("^%s*(.-)%s*$");if value~=""and not value:match("^##")then entries[#entries+1]=value:gsub("\\","/")end end
 for _,value in ipairs(entries)do assert(exists(root.."/"..value),"missing TOC file: "..root.."/"..value)end
 return entries
end

local function tocMetadata(toc)
 local metadata={}
 for line in toc:gmatch("[^\r\n]+")do
  local key,value=line:match("^##%s*([^:]+):%s*(.-)%s*$")
  if key then metadata[key]=value end
 end
 return metadata
end
local function splitDependencies(value)
 local dependencies={}
 for dependency in tostring(value or""):gmatch("[^,%s]+")do dependencies[#dependencies+1]=dependency end
 return dependencies
end

local coreRoot=live.."Holy_Storm";local coreToc=read(coreRoot.."/Holy_Storm.toc")
assert(coreToc:find("## Title: Holy Storm",1,true),"core title contract")
assert(coreToc:find("## Category: Holy Storm",1,true),"core category contract")
assert(coreToc:find("## SavedVariables: HolyStormDB, HS_Player_DB",1,true)and not coreToc:find("HS_GuildLog_DB",1,true),"core saved-variable ownership changed")
assert(not coreToc:find("UI\\",1,true)and not coreToc:find("AceGUI",1,true)and not coreToc:find("AceConfigDialog",1,true)and not coreToc:find("AceDBOptions",1,true),"core TOC still loads UI")
local coreEntries=tocEntries(coreRoot,coreToc);for _,entry in ipairs(coreEntries)do assert(not entry:find("Holy_Storm_",1,true),"core TOC crosses addon boundary: "..entry)end

local uiRoot=live.."Holy_Storm_UI";local uiToc=read(uiRoot.."/Holy_Storm_UI.toc")
assert(uiToc:find("## Title: Holy Storm: |cff24a7deUI|r",1,true),"UI title contract")
assert(uiToc:find("## RequiredDeps: Holy_Storm",1,true),"UI must depend only on core")
for _,contract in ipairs({"UI\\Framework\\UIManager.lua","UI\\Framework\\MainWindow.lua","AceGUI-3.0","AceConfigDialog-3.0","AceDBOptions-3.0"})do assert(uiToc:find(contract,1,true),"UI TOC missing "..contract)end
tocEntries(uiRoot,uiToc)

local interface=assert(coreToc:match("## Interface:%s*(%d+)"))
for _,feature in ipairs(features)do
 local root=live..feature.folder;local tocPath=root.."/"..feature.folder..".toc";local toc=read(tocPath)
 assert(toc:match("## Interface:%s*"..interface),feature.folder.." interface mismatch")
 assert(toc:find("## Title: Holy Storm: |cff24a7de"..feature.title.."|r",1,true),feature.folder.." title contract")
 assert(toc:find("## Category: Holy Storm",1,true),feature.folder.." category contract")
 assert(toc:find("## RequiredDeps: Holy_Storm",1,true),feature.folder.." must require only the core")
 if feature.folder=="Holy_Storm_GuildLog"then assert(toc:find("## SavedVariables: HS_GuildLog_DB",1,true),"GuildLog must own its SavedVariables")else assert(not toc:find("## SavedVariables:",1,true),feature.folder.." owns unexpected SavedVariables")end
 assert(toc:find("## X-HolyStorm-ID:",1,true),feature.folder.." lacks discovery metadata")
 tocEntries(root,toc)
 local module=read(root.."/"..feature.module);assert(module:find("RegisterModule",1,true),feature.folder.." does not register dynamically")
 if feature.block then assert(module:find('RegisterBlock("'..feature.block..'"',1,true),feature.folder.." does not own its data block")end
 if feature.store then assert(exists(root.."/"..feature.store),feature.folder.." does not own its store")end
end

for _,path in ipairs({"Modules","UI/Character","Persistence/AchievementStore.lua","Persistence/ContentStore.lua","Persistence/POIStore.lua"})do assert(not exists(coreRoot.."/"..path),"obsolete monolith path remains: "..path)end
local playerData=read(coreRoot.."/Persistence/PlayerDataStore.lua")
for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats","profile","professions","demands"})do assert(not playerData:find('RegisterBlock("'..block..'"',1,true),"core owns feature block "..block)end
local bootstrap=read(coreRoot.."/Core/Bootstrap/Bootstrap.lua");local loader=read(coreRoot.."/Core/Registry/AddonLoader.lua")
for _,name in ipairs({"Holy_Storm_Equipment","Holy_Storm_Raids","Holy_Storm_MythicPlus","Holy_Storm_Delves"})do assert(not loader:find(name,1,true)and not bootstrap:find(name,1,true),"core loader hardcodes feature "..name)end
for _,contract in ipairs({"X-HolyStorm-ID","X-HolyStorm-Requires","X-HolyStorm-LoadOnEvent","C_AddOns.GetNumAddOns","C_AddOns.GetAddOnMetadata","C_AddOns.LoadAddOn"})do assert(loader:find(contract,1,true),"generic loader contract missing: "..contract)end
for _,path in ipairs({"Holy_Storm_Equipment/UI/CharacterTab.lua","Holy_Storm_Raids/UI/CharacterTab.lua","Holy_Storm_MythicPlus/UI/CharacterTab.lua","Holy_Storm_Delves/UI/CharacterTab.lua"})do local source=read(live..path);assert(source:find("RegisterCharacterTab",1,true)and source:find("RegisterCharacterSummarySection",1,true),path.." does not extend Characters dynamically")end
local achievementSource=read(live.."Holy_Storm_Achievements/Achievements.lua");assert(achievementSource:find("RegisterCharacterTab",1,true),"Achievements does not use the late-load character registry")
local characterLocale=read(live.."Holy_Storm_Characters/UI/Locales/enUS.lua");for _,key in ipairs({"TAB_EQUIPMENT","TAB_MYTHICPLUS","TAB_RAID","TAB_DELVES"})do assert(not characterLocale:find(key,1,true),"Characters still owns feature locale "..key)end
local packageMeta=read(coreRoot.."/.pkgmeta");for _,feature in ipairs(features)do assert(packageMeta:find("Holy_Storm/LIVE/"..feature.folder..": "..feature.folder,1,true),"release package omits "..feature.folder)end
assert(packageMeta:find("Holy_Storm/LIVE/Holy_Storm_UI: Holy_Storm_UI",1,true),"release package omits UI addon")

-- Validate the complete addon graph, not only the known feature list above.
local addonNames={"Holy_Storm","Holy_Storm_UI"}
for _,feature in ipairs(features)do addonNames[#addonNames+1]=feature.folder end
local manifests={}
for _,addonName in ipairs(addonNames)do
 local toc=read(live..addonName.."/"..addonName..".toc")
 local metadata=tocMetadata(toc)
 manifests[addonName]={required=splitDependencies(metadata.RequiredDeps),optional=splitDependencies(metadata.OptionalDeps),loadOnDemand=metadata.LoadOnDemand,defaultState=metadata.DefaultState}
end
for _,addonName in ipairs({"Holy_Storm","Holy_Storm_UI"})do
 for _,dependency in ipairs(manifests[addonName].required)do assert(not manifests[dependency]or dependency=="Holy_Storm",addonName.." must not require feature addon "..dependency)end
 for _,dependency in ipairs(manifests[addonName].optional)do assert(not manifests[dependency]or dependency=="Holy_Storm",addonName.." must not optionally depend on feature addon "..dependency)end
end
local visiting,visited={},{}
local function visit(addonName)
 if visiting[addonName]then error("circular addon dependency at "..addonName)end
 if visited[addonName]then return end
 visiting[addonName]=true
 for _,dependency in ipairs(manifests[addonName].required)do if manifests[dependency]then visit(dependency)end end
 for _,dependency in ipairs(manifests[addonName].optional)do if manifests[dependency]then visit(dependency)end end
 visiting[addonName],visited[addonName]=nil,true
end
for _,addonName in ipairs(addonNames)do visit(addonName)end
print("Standalone addon split, TOC, ownership and dynamic-extension contracts passed")
