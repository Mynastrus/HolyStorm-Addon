-- Structural contract checks for module-owned feature permissions.
local root=(arg[0]:gsub("tools[/\\]test_feature_permissions.lua$",""))
local function read(path)
    local file=assert(io.open(root..path,"r"));local text=file:read("*a");file:close();return text
end
local registry=read("LIVE/Holy_Storm/Core/Permissions/PermissionRegistry.lua")
local groups=read("LIVE/Holy_Storm/Core/Permissions/GroupManager.lua")
local modules=read("LIVE/Holy_Storm/Core/Registry/ModuleRegistry.lua")
assert(not registry:match('%["news%-view"%]="News"'),"news permission remains in central definitions")
assert(not registry:match('%["mythicplus%-read"%]="Mythic%+"'),"Mythic+ permission remains in central definitions")
assert(not registry:find("local definitions = {",1,true),"permission inventory is not seeded by a static registry table")
assert(not groups:match('%["news%-view"%]=true'),"feature defaults remain hardcoded in GroupManager")
assert(modules:find("RegisterModulePermissions",1,true),"module permission registration hook missing")
local bootstrap=read("LIVE/Holy_Storm/Core/Bootstrap/Bootstrap.lua")
for _,id in ipairs({"groups-create","permissions-manage","filters-edit","rules-manage","modules-manage","core-settings-read","sync-send","player-read"})do assert(bootstrap:find('id = "'..id..'"',1,true),"Core permission contract misses "..id)end
for _,entry in ipairs({
 {"LIVE/Holy_Storm_UI/UI/Framework/MainWindow.lua","ui-render"},
 {"LIVE/Holy_Storm_UI/UI/Pages/Options.lua","settings-read"},
 {"LIVE/Holy_Storm_UI/UI/Pages/SavedVariables.lua","savedvariables-read"},
 {"LIVE/Holy_Storm_UI/UI/Pages/Logs.lua","logs-view"},
 {"LIVE/Holy_Storm_UI/UI/Pages/TaskManager.lua","taskmanager-control"},
})do local source=read(entry[1]);assert(source:find('id = "'..entry[2]..'"',1,true)or source:find('id="'..entry[2]..'"',1,true),"module owner contract misses "..entry[2])end
for _,path in ipairs({
    "Holy_Storm_News/News.lua","Holy_Storm_Calendar/Calendar.lua","Holy_Storm_Raids/Raids.lua",
    "Holy_Storm_MythicPlus/MythicPlus.lua","Holy_Storm_Delves/Delves.lua","Holy_Storm_Equipment/Equipment.lua",
    "Holy_Storm_POI/POI.lua","Holy_Storm_Achievements/Achievements.lua",
    "Holy_Storm_Guild/Guild.lua","Holy_Storm_Professions/Professions.lua",
}) do
    assert(read("LIVE/"..path):find("permissions",1,true),"missing modular permissions: "..path)
end
local positions=read("LIVE/Holy_Storm_Positions/Positions.lua")
assert(not positions:find("position-view",1,true)and not positions:find("position-share",1,true),"position display/privacy must not be guild permissions")
print("Module-owned feature permission contracts passed")
