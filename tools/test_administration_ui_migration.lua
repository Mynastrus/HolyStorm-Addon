-- Static regression contracts for the shared-framework Administration migration.
local root=(arg[0]:gsub("tools[/\\]test_administration_ui_migration.lua$",""))
local ui=root.."LIVE/Holy_Storm_UI/"
local function read(path)local file=assert(io.open(ui..path,"rb"));local text=file:read("*a");file:close();return text end

local components=read("UI/Framework/Components.lua")
local tableSource=read("UI/Framework/Table.lua")
local policyUI=read("UI/Framework/Components/PolicyUI.lua")
local host=read("UI/Administration/AdministrationRegistry.lua")
local permissions=read("UI/Administration/Permissions.lua")
local rules=read("UI/Administration/Rules.lua")
local filters=read("UI/Administration/Filters.lua")
local inspector=read("UI/Administration/PolicyInspector.lua")
local administration=permissions..rules..filters..inspector

assert(components:find("CreateEditBox",1,true)and components:find("CreateEmptyState",1,true),"shared controls required by Administration are missing")
assert(tableSource:find("SetSelection",1,true)and tableSource:find("isRowSelected",1,true),"shared Table selection state is missing")
assert(policyUI:find("Components:CreateTable",1,true),"policy lists and rule trees must use the shared Table")
assert(not policyUI:find('CreateFrame("CheckButton',1,true),"legacy policy checklist renderer remains")
assert(not policyUI:find('CreateFrame("ScrollFrame',1,true),"legacy policy scroll renderer remains")

for name,source in pairs({Permissions=permissions,Rules=rules,Filters=filters,PolicyInspector=inspector})do
    assert(source:find("build=function(parent)",1,true),name.." must be registered lazily")
    assert(source:find("CreateColumn",1,true)or source:find("CreateRow",1,true),name.." must use UILayout components")
    assert(not source:find('owner%s*=%s*"Core"%s*,%s*page%s*='),name.." still registers an eager compatibility page")
end
assert(host:find("components=HolyStorm.UI and HolyStorm.UI.Components",1,true),"Administration extension context must expose shared components")
assert(host:find("hostLayout:Add",1,true),"Administration host must use shared layout")

for _,contract in ipairs({"Registry:GetPermissions","Engine:GetPermissionMatrix","Engine:GetMembershipReasons","Groups:SaveGroup","Filters:SaveRule","Filters:SaveFilter","State:RestoreDefaults"})do
    assert(administration:find(contract,1,true),"domain API missing from migrated Administration: "..contract)
end
for _,sourceKey in ipairs({"MEMBERSHIP_CHARACTER","MEMBERSHIP_ACCOUNT","MEMBERSHIP_GUILD_RANK","MEMBERSHIP_SYSTEM","FILTERS_TITLE","RULES_TITLE"})do
    assert((permissions..policyUI):find(sourceKey,1,true),"membership source is not represented: "..sourceKey)
end
assert(permissions:find('draft.id==Groups.systemIds.LEADERSHIP',1,true),"protected leadership rendering is missing")
assert(permissions:find("StaticPopupDialogs.HOLYSTORM_PERMISSION_RESET",1,true)and permissions:find("State:RestoreDefaults",1,true),"factory reset confirmation must delegate to PolicyState")
assert(policyUI:find('L["UNAVAILABLE"]',1,true),"unavailable provider state is not rendered")
assert(policyUI:find("MoveSelected",1,true)and policyUI:find("IndentSelected",1,true)and policyUI:find("OutdentSelected",1,true),"nested editor movement controls regressed")

for _,locale in ipairs({"enUS","deDE"})do
    local source=read("UI/Administration/Locales/"..locale..".lua")
    for _,key in ipairs({"EMPTY_MEMBERS","EMPTY_PERMISSIONS","NO_SELECTION","CONFIRM_PERMISSION_RESET","UNAVAILABLE"})do assert(source:find('["'..key..'"]',1,true),locale.." misses migrated Administration text "..key)end
end

print("Administration shared layout, lazy lifecycle, table reuse, domain delegation and localization contracts passed")
