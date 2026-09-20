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
assert(not groups:match('%["news%-view"%]=true'),"feature defaults remain hardcoded in GroupManager")
assert(modules:find("RegisterModulePermissions",1,true),"module permission registration hook missing")
for _,path in ipairs({
    "Holy_Storm_News/News.lua","Holy_Storm_Calendar/Calendar.lua","Holy_Storm_Raids/Raids.lua",
    "Holy_Storm_MythicPlus/MythicPlus.lua","Holy_Storm_Delves/Delves.lua","Holy_Storm_Equipment/Equipment.lua",
    "Holy_Storm_POI/POI.lua","Holy_Storm_Positions/Positions.lua","Holy_Storm_Achievements/Achievements.lua",
    "Holy_Storm_Guild/Guild.lua","Holy_Storm_Professions/Professions.lua",
}) do
    assert(read("LIVE/"..path):find("permissions",1,true),"missing modular permissions: "..path)
end
print("Module-owned feature permission contracts passed")
