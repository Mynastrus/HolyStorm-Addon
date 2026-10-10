-- Offline contract for declarative module-owned Administration sections.
local root=(arg[0]:gsub("tools[/\\]test_administration_module_contract.lua$","")).."LIVE/Holy_Storm/"
local function copy(value)if type(value)~="table"then return value end;local out={};for key,item in pairs(value)do out[key]=copy(item)end;return out end
local locale=setmetatable({},{__index=function(_,key)return key end})
local emitted={}
local modules={}
local HolyStorm={Utils={DeepCopy=copy},Events={},Modules=modules,metadata={id="core",name="Core",displayName="Core",description="Core",version="1.0.0",category="core",permissions={{id="core-contract-test",category="Core"}}}}
function HolyStorm:GetAddon()return self end
function HolyStorm:GetModule(id)return modules[id]end
function HolyStorm:IterateModules()local key;return function()key=next(modules,key);if key then return key,modules[key]end end end
function HolyStorm.Events:Emit(event,...)emitted[#emitted+1]={event,...}end
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;return HolyStorm end

assert(loadfile(root.."Core/Registry/ModuleRegistry.lua"))()
assert(HolyStorm.pendingModulePermissions.core and HolyStorm.pendingModulePermissions.core.permissions[1].id=="core-contract-test","the root Core permission list enters the same module-contract pipeline")
local fakeModule={enabled=true,GetName=function()return"Example"end,IsEnabled=function(self)return self.enabled end}
modules.Example=fakeModule
local built=function()return{}end
HolyStorm:ApplyModuleMetadata(fakeModule,{id="example",name="Example",displayName="Example",description="Example",version="1.0.0",category="required",permissions={{id="example-manage",defaults={officers=true}}},administration={{id="example-admin",title="Example",build=built}}})
assert(HolyStorm.pendingAdministrationSections["example:example-admin"],"early module section was not queued")
assert(HolyStorm.pendingModulePermissions.example,"early module permissions were not queued")

local registered
HolyStorm.Administration={RegisterSection=function(_,definition)registered=definition;return true end}
assert(HolyStorm:FlushAdministrationSections()==1)
assert(registered and registered.id=="example-admin"and registered.owner=="example"and registered.moduleId=="example"and registered.requires.module=="example"and registered.build==built)
assert(not next(HolyStorm.pendingAdministrationSections))
local permission
HolyStorm.PermissionRegistry={GetPermission=function()end,RegisterPermission=function(_,definition)permission=definition;return true end}
assert(HolyStorm:FlushModulePermissions()==2 and permission.id=="example-manage"and permission.module=="example"and permission.defaults.officers==true)
permission=nil
HolyStorm:RegisterModulePermissions({id="reference-only",name="Reference only",permissions={"permission-owned-elsewhere"}})
assert(permission==nil,"a referenced permission ID must not create a definition without its owning contract")
HolyStorm:RegisterModulePermissions({id="example-owner",name="Example owner",permissions={{id="example-owned",defaults={member=true}}}})
assert(permission and permission.id=="example-owned"and permission.module=="example-owner"and permission.defaults.member==true,"the registry receives complete permission definitions only from owner module contracts")

assert(HolyStorm:RegisterCapability("Example","example.configure",function()end))
assert(HolyStorm:IsModuleAvailable("example",true)and HolyStorm:IsCapabilityAvailable("example.configure","example"))
fakeModule.enabled=false
assert(not HolyStorm:IsModuleAvailable("example",true)and not HolyStorm:IsCapabilityAvailable("example.configure","example"))
fakeModule.enabled=true
assert(HolyStorm:UnregisterCapability("Example","example.configure")and not HolyStorm:IsCapabilityAvailable("example.configure","example"))
assert(emitted[1][1]=="HS_CAPABILITY_REGISTERED"and emitted[#emitted][1]=="HS_CAPABILITY_UNREGISTERED")

print("declarative module administration, module availability and capability lifecycle tests passed")
