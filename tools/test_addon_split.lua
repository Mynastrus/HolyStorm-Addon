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

local coreRoot=live.."Holy_Storm";local coreToc=read(coreRoot.."/Holy_Storm.toc")
assert(coreToc:find("## Title: Holy Storm: |cff24a7deCore|r",1,true),"core title contract")
assert(coreToc:find("## Category: Holy Storm",1,true),"core category contract")
assert(coreToc:find("## SavedVariables: HolyStormDB, HS_Player_DB, HS_GuildLog_DB",1,true),"saved-variable ownership changed")
assert(not coreToc:find("Modules\\",1,true)and not coreToc:find("UI\\Character",1,true),"core TOC still loads feature runtime/UI")
local coreEntries=tocEntries(coreRoot,coreToc);for _,entry in ipairs(coreEntries)do assert(not entry:find("Holy_Storm_",1,true),"core TOC crosses addon boundary: "..entry)end

local interface=assert(coreToc:match("## Interface:%s*(%d+)"))
for _,feature in ipairs(features)do
 local root=live..feature.folder;local tocPath=root.."/"..feature.folder..".toc";local toc=read(tocPath)
 assert(toc:match("## Interface:%s*"..interface),feature.folder.." interface mismatch")
 assert(toc:find("## Title: Holy Storm: |cff24a7de"..feature.title.."|r",1,true),feature.folder.." title contract")
 assert(toc:find("## Category: Holy Storm",1,true),feature.folder.." category contract")
 assert(toc:find("## RequiredDeps: Holy_Storm",1,true),feature.folder.." must require only the core")
 assert(not toc:find("## SavedVariables:",1,true),feature.folder.." must not split the established SavedVariables")
 tocEntries(root,toc)
 local module=read(root.."/"..feature.module);assert(module:find("RegisterModule",1,true),feature.folder.." does not register dynamically")
 if feature.block then assert(module:find('RegisterBlock("'..feature.block..'"',1,true),feature.folder.." does not own its data block")end
 if feature.store then assert(exists(root.."/"..feature.store),feature.folder.." does not own its store")end
end

for _,path in ipairs({"Modules","UI/Character","Persistence/AchievementStore.lua","Persistence/ContentStore.lua","Persistence/POIStore.lua"})do assert(not exists(coreRoot.."/"..path),"obsolete monolith path remains: "..path)end
local playerData=read(coreRoot.."/Persistence/PlayerDataStore.lua")
for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats","profile","professions","demands"})do assert(not playerData:find('RegisterBlock("'..block..'"',1,true),"core owns feature block "..block)end
local bootstrap=read(coreRoot.."/Core/Bootstrap/Bootstrap.lua")
for _,capability in ipairs({"character.scan.equipment","character.scan.raids","character.scan.mythicplus","character.scan.additional"})do assert(not bootstrap:find(capability,1,true),"hardcoded feature startup branch: "..capability)end
assert(bootstrap:find('capability:match("^character%.scan%.")',1,true),"generic feature startup discovery missing")
for _,path in ipairs({"Holy_Storm_Equipment/UI/CharacterTab.lua","Holy_Storm_Raids/UI/CharacterTab.lua","Holy_Storm_MythicPlus/UI/CharacterTab.lua","Holy_Storm_Delves/UI/CharacterTab.lua"})do local source=read(live..path);assert(source:find("RegisterCharacterTab",1,true)and source:find("RegisterCharacterSummarySection",1,true),path.." does not extend Characters dynamically")end
local achievementSource=read(live.."Holy_Storm_Achievements/Achievements.lua");assert(achievementSource:find("RegisterCharacterTab",1,true),"Achievements does not use the late-load character registry")
local characterLocale=read(live.."Holy_Storm_Characters/UI/Locales/enUS.lua");for _,key in ipairs({"TAB_EQUIPMENT","TAB_MYTHICPLUS","TAB_RAID","TAB_DELVES"})do assert(not characterLocale:find(key,1,true),"Characters still owns feature locale "..key)end
local packageMeta=read(coreRoot.."/.pkgmeta");for _,feature in ipairs(features)do assert(packageMeta:find("Holy_Storm/LIVE/"..feature.folder..": "..feature.folder,1,true),"release package omits "..feature.folder)end
print("Standalone addon split, TOC, ownership and dynamic-extension contracts passed")
