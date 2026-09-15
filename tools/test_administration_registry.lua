-- Offline contracts for the central Administration section registry and migrated admin UI.
local root=(arg[0]:gsub("tools[/\\]test_administration_registry.lua$","")).."LIVE/Holy_Storm/"

local function deepCopy(value,seen)
    if type(value)~="table" then return value end
    seen=seen or {}; if seen[value] then return seen[value] end
    local result={}; seen[value]=result
    for key,item in pairs(value) do result[deepCopy(key,seen)]=deepCopy(item,seen) end
    return result
end

local granted,modules,enabled={admin=true},{},{}
local calls={pages={},navigation={},removedPages={},removedNavigation={}}
local HolyStorm={
    Utils={
        DeepCopy=deepCopy,
        SafeCall=function(_,callback,...) local result={pcall(callback,...)}; return table.unpack(result) end,
    },
    PermissionEngine={HasPermission=function(_,_,_,permission) return granted[permission]==true end},
    PolicyState={IsGuildModuleEnabled=function(_,id) return enabled[id]~=false end},
    Events={listeners={}},
    UI={},
}
function HolyStorm:GetAddon() return self end
function HolyStorm:GetModuleEntry(id) return modules[id] end
function HolyStorm.Events:Register(event,owner,callback) self.listeners[event]=self.listeners[event] or {}; self.listeners[event][owner]=callback end
function HolyStorm.Events:Emit(event,...) for _,callback in pairs(self.listeners[event] or {}) do callback(event,...) end end
function HolyStorm.UI:RegisterPage(id,page,title,render,events) calls.pages[id]={page=page,title=title,render=render,events=events} end
function HolyStorm.UI:AddNavigation(id,order,icon,title,description,callback) calls.navigation[id]={order=order,icon=icon,title=title,description=description,callback=callback} end
function HolyStorm.UI:UnregisterPage(id) calls.removedPages[id]=true; calls.pages[id]=nil end
function HolyStorm.UI:RemoveNavigation(id) calls.removedNavigation[id]=true; calls.navigation[id]=nil end
function HolyStorm.UI:ShowPage(id) calls.shown=id end
function LibStub() return HolyStorm end

assert(loadfile(root.."UI/Administration/AdministrationRegistry.lua"))()
local Admin=HolyStorm.Administration
assert(Admin and Admin.version=="1.0.0")
assert(not Admin:RegisterSection({id="invalid"}))

local rendered,page=0,{id="page"}
assert(Admin:RegisterSection({id="core-admin",displayName="Core admin",description="Core tools",order=20,requiredPermission="admin",owner="Core",page=page,render=function() rendered=rendered+1 end}))
assert(calls.pages["core-admin"] and calls.navigation["core-admin"])
assert(Admin.sections["core-admin"].page==page,"frame/page references must not be deep-copied")
calls.pages["core-admin"].render(); assert(rendered==1)

assert(Admin:RegisterSection({id="denied",displayNameKey="DENIED",descriptionKey="DENIED_DESC",order=10,requiredPermission="denied",page={}}))
assert(not calls.pages.denied and Admin:GetSection("denied").displayNameKey=="DENIED")

local built=0
assert(Admin:RegisterSection({id="module-admin",order=15,moduleId="feature",requiredPermission={"feature-admin","admin"},build=function() built=built+1; return {id="feature-page"} end,isAvailable=function() return true end}))
assert(not calls.pages["module-admin"] and built==0)
modules.feature={internalName="feature"}; enabled.feature=true; Admin:RefreshSections()
assert(calls.pages["module-admin"] and built==1)
Admin:RefreshSections(); assert(built==1,"section must only be built once")

local sections=Admin:GetSections(false)
assert(sections[1].id=="denied" and sections[2].id=="module-admin" and sections[3].id=="core-admin")
enabled.feature=false; Admin:RefreshSections()
assert(not calls.pages["module-admin"] and calls.removedPages["module-admin"] and calls.removedNavigation["module-admin"])
assert(Admin:UnregisterSection("core-admin") and not Admin:GetSection("core-admin"))
assert(not Admin:RegisterSection({id="denied",page={}}) and not Admin:UnregisterSection("missing"))

local migrated={
    "UI/Administration/Permissions.lua",
    "UI/Administration/Rules.lua",
    "UI/Administration/Filters.lua",
    "UI/Administration/PolicyInspector.lua",
    "UI/Framework/Components/PolicyUI.lua",
}
local source=""
for _,path in ipairs(migrated) do local file=assert(io.open(root..path,"rb")); source=source..file:read("*a"); file:close() end
assert(not source:find("HolyStorm%.Policy:") and not source:find("HolyStorm%.Permissions:"),"admin UI must not use compatibility permission facades")
for _,name in ipairs({"PermissionRegistry","PermissionEngine","GroupManager","FilterManager","PolicyState"}) do assert(source:find(name,1,true),name.." direct UI contract missing") end
for _,path in ipairs({"Permissions.lua","Rules.lua","Filters.lua","PolicyInspector.lua"}) do
    local file=assert(io.open(root.."UI/Administration/"..path,"rb")); local text=file:read("*a"); file:close()
    assert(text:find("Administration:RegisterSection",1,true),path.." must register through the Administration host")
end

print("administration registry tests passed")
