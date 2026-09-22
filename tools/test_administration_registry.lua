-- Offline contracts for the generic Administration host.
local root=(arg[0]:gsub("tools[/\\]test_administration_registry.lua$","")).."LIVE/Holy_Storm_UI/"
local coreRoot=(arg[0]:gsub("tools[/\\]test_administration_registry.lua$","")).."LIVE/Holy_Storm/"

local function deepCopy(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {}; if seen[value] then return seen[value] end
    local result={}; seen[value]=result
    for key,item in pairs(value) do result[deepCopy(key,seen)]=deepCopy(item,seen) end
    return result
end

local granted={admin=true,featureAdmin=true}
local modules={feature={enabled=true},disabled={enabled=false}}
local capabilities={featureCapability={feature=true}}
local shown={}
local HolyStorm={
    Utils={DeepCopy=deepCopy,SafeCall=function(_,callback,...)local values={pcall(callback,...)};return table.unpack(values)end},
    PermissionEngine={HasPermission=function(_,_,_,permission)return granted[permission]==true end},
    PolicyState={IsGuildModuleEnabled=function(_,id)return not modules[id]or modules[id].guildEnabled~=false end},
    Events={listeners={}}, UI={},
}
function HolyStorm:GetAddon()return self end
function HolyStorm:IsModuleAvailable(id)return modules[id]and modules[id].enabled==true or false end
function HolyStorm:IsCapabilityAvailable(id,moduleId)return capabilities[id]and(not moduleId or capabilities[id][moduleId])or false end
function HolyStorm.Events:Register(event,owner,callback)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=callback end
function HolyStorm.Events:UnregisterOwner(owner)for _,listeners in pairs(self.listeners)do listeners[owner]=nil end end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(self.listeners[event]or{})do callback(event,...)end end
function HolyStorm.UI:ShowPage(id)shown.page=id;return true end
function HolyStorm.UI:AddNavigation(id)shown.navigation=shown.navigation or{};shown.navigation[id]=(shown.navigation[id]or 0)+1 end
function HolyStorm.UI:RemoveNavigation(id)shown.removed=id end
function LibStub(name,silent)if name=="AceAddon-3.0"then return HolyStorm end;if silent then return nil end;return HolyStorm end

assert(loadfile(root.."UI/Administration/AdministrationRegistry.lua"))()
local Admin=HolyStorm.Administration
assert(Admin and Admin.version=="2.1.0")
assert(not Admin:RegisterSection({id="invalid"}))

local lifecycle={build=0,show=0,hide=0,refresh=0,destroy=0}
local function frame()return{shown=false,Show=function(self)self.shown=true end,Hide=function(self)self.shown=false end}end
assert(Admin:RegisterSection({id="core",category="general",title="Core",order=20,permission="admin",build=function()lifecycle.build=lifecycle.build+1;return frame()end,show=function()lifecycle.show=lifecycle.show+1 end,hide=function()lifecycle.hide=lifecycle.hide+1 end,refresh=function()lifecycle.refresh=lifecycle.refresh+1 end,destroy=function()lifecycle.destroy=lifecycle.destroy+1 end}))
assert(not Admin:RegisterSection({id="core",page=frame()}),"duplicate section must be rejected")
assert(Admin:IsSectionAvailable("core"))
assert(Admin:Open("core")and Admin.activeId=="core"and lifecycle.build==1 and lifecycle.show==1 and lifecycle.refresh==1)
Admin:Open("core");assert(lifecycle.build==1,"a section is built once")

assert(Admin:RegisterSection({id="denied",category="general",title="Denied",order=10,permission="denied",page=frame()}))
assert(not Admin:IsSectionAvailable("denied"))
assert(Admin:RegisterSection({id="module",category="modules",title="Module",order=20,permission={"denied","featureAdmin"},requires={module="feature",capability="featureCapability"},page=frame()}))
assert(Admin:IsSectionAvailable("module"),"available module and capability must pass")
assert(Admin:RegisterSection({id="missingModule",category="modules",title="Missing module",order=10,requires={module="missing"},page=frame()}))
assert(not Admin:IsSectionAvailable("missingModule"))
assert(Admin:RegisterSection({id="missingCapability",category="modules",title="Missing capability",order=11,requires={module="feature",capability="missingCapability"},page=frame()}))
assert(not Admin:IsSectionAvailable("missingCapability"))

Admin:RegisterCategory("alpha",{order=5,title="Alpha"})
assert(Admin:RegisterSection({id="zulu",category="alpha",title="Zulu",order=10,page=frame()}))
assert(Admin:RegisterSection({id="alpha",category="alpha",title="Alpha",order=10,page=frame()}))
local visible=Admin:GetSections(true)
assert(visible[1].id=="alpha"and visible[2].id=="zulu"and visible[3].id=="core"and visible[4].id=="module","category, section order and localized-title fallback must be deterministic")

assert(Admin:Open("module")and Admin.activeId=="module")
modules.feature.enabled=false;HolyStorm.Events:Emit("HS_MODULE_AVAILABILITY_CHANGED","feature",false)
assert(not Admin:IsSectionAvailable("module")and Admin.activeId=="alpha","an invalid active section must fall back to the first available section")
modules.feature.enabled=true;modules.feature.guildEnabled=false;Admin:RefreshNavigation();assert(not Admin:IsSectionAvailable("module"),"guild-disabled module must be hidden")
modules.feature.guildEnabled=true;capabilities.featureCapability=nil;Admin:RefreshNavigation();assert(not Admin:IsSectionAvailable("module"),"removed capability must hide a section")
capabilities.featureCapability={feature=true};Admin:RefreshNavigation();assert(Admin:IsSectionAvailable("module"))

for _=1,3 do Admin:RefreshNavigation()end
local seen={};for _,category in ipairs(Admin:GetNavigationModel())do for _,entry in ipairs(category.children)do assert(not seen[entry.id],"duplicate navigation entry: "..entry.id);seen[entry.id]=true end end

assert(Admin:UnregisterSection("core")and lifecycle.destroy==1 and not Admin:GetSection("core"))
assert(not Admin:UnregisterSection("core"))

local source=""
for _,path in ipairs({"Permissions.lua","Rules.lua","Filters.lua","PolicyInspector.lua"})do
    local file=assert(io.open(root.."UI/Administration/"..path,"rb"));local text=file:read("*a");file:close();source=source..text
    assert(text:find("Administration:RegisterSection",1,true),path.." must register through the Administration host")
    assert(text:find("category%s*="),path.." must declare a category")
end
assert(not source:find("HolyStorm%.Policy:")and not source:find("HolyStorm%.Permissions:"),"admin UI must use the component contracts")
assert(source:find("Registry:GetPermissions",1,true),"permission administration must read the active registry")
assert(not source:find('DEFAULT_PERMISSION,"news%-edit"')and not source:find('DEFAULT_PERMISSION%s*=%s*"news%-edit"'),"removed module permissions must not be recreated by a static inspector default")
assert(not source:find("HolyStorm%.db")and not source:find("Database:GetRoot",1,true),"admin UI must not write SavedVariables directly")
for _,name in ipairs({"PermissionRegistry","PermissionEngine","GroupManager","FilterManager","PolicyState"})do assert(source:find(name,1,true),name.." direct UI contract missing")end
local registryFile=assert(io.open(coreRoot.."Core/Registry/ModuleRegistry.lua","rb"));local registrySource=registryFile:read("*a");registryFile:close()
for _,contract in ipairs({"RegisterModuleAdministration","FlushAdministrationSections","IsModuleAvailable","IsCapabilityAvailable","HS_MODULE_AVAILABILITY_CHANGED"})do assert(registrySource:find(contract,1,true),"ModuleRegistry misses administration contract "..contract)end
local hostFile=assert(io.open(root.."UI/Administration/AdministrationRegistry.lua","rb"));local hostSource=hostFile:read("*a");hostFile:close()
for _,optionalName in ipairs({"Equipment","MythicPlus","Raids","Delves","Content","POI","Calendar","TaskManager","SyncManager"})do assert(not hostSource:find(optionalName,1,true),"Administration host hardcodes optional module "..optionalName)end

for _,locale in ipairs({"enUS","deDE"})do
    local file=assert(io.open(root.."UI/Administration/Locales/"..locale..".lua","rb"));local text=file:read("*a");file:close()
    for _,key in ipairs({"ADMINISTRATION_TITLE","ADMINISTRATION_DESCRIPTION","ADMIN_CATEGORY_GENERAL","ADMIN_CATEGORY_PERMISSIONS","ADMIN_CATEGORY_GROUPS","ADMIN_CATEGORY_RULES","ADMIN_CATEGORY_FILTERS","ADMIN_CATEGORY_MODULES","ADMIN_CATEGORY_SYSTEM"})do assert(text:find('["'..key..'"]',1,true),locale.." misses "..key)end
end

local overview=assert(io.open(coreRoot.."../Holy_Storm_Characters/UI/CharacterOverview.lua","rb"));local overviewSource=overview:read("*a");overview:close()
local metadata=overviewSource:match("ApplyModuleMetadata%([^\n]+")or""
assert(metadata:find("permissions={}",1,true),"Character Overview must not declare a basic access permission")
assert(not overviewSource:find('OpenCharacter.-HasPermission'),"Character Overview opening must not have an access gate")

print("administration host registration, gating, lifecycle, fallback, localization and Character Overview tests passed")
