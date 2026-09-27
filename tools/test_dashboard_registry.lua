local root=(arg[0]:gsub("tools[/\\]test_dashboard_registry.lua$","")).."LIVE/Holy_Storm_UI/"
local listeners,events={},{}
local HolyStorm={Utils={},Events={},State={},UILayout={},UIComponents={}}
function HolyStorm.Utils.DeepCopy(value)local copy={};for key,item in pairs(value or{})do copy[key]=item end;return copy end
function HolyStorm.Utils.SafeCall(_,callback,...)local result={pcall(callback,...)};local ok=table.remove(result,1);return ok,table.unpack(result)end
function HolyStorm.Events:Register(event,owner,callback)listeners[event]=listeners[event]or{};listeners[event][owner]=callback end
function HolyStorm.Events:Emit(event,...)events[#events+1]={event,...};for _,callback in pairs(listeners[event]or{})do callback(event,...)end end
function HolyStorm.State:Set(key,value)self[key]=value end
function HolyStorm:GetUIExtensions()return{}end
local locale=setmetatable({},{__index=function(_,key)return key end})
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end end

assert(loadfile(root.."UI/Framework/UIManager.lua"))()
local manager=HolyStorm.UI
local definition={owner="Calendar",order=20,title="Calendar",getItems=function()return{{title="Next event"}}end}
assert(manager:RegisterDashboardProvider("calendar",definition)and manager.dashboardProviders.calendar.owner=="Calendar","provider can register before the UI driver exists")
local legacyCalled=false;assert(manager:RegisterDashboardProvider("legacy",function()legacyCalled=true;return{}end,"News"),"legacy callback providers remain accepted")
assert(manager.dashboardProviders.legacy.owner=="News"and type(manager.dashboardProviders.legacy.getItems)=="function","legacy provider becomes an owned provider definition")

local forwarded,removed={},{}
local driver={RegisterDashboardProvider=function(_,id,item)forwarded[id]=item;return true end,UnregisterDashboardProvider=function(_,id)removed[id]=true;forwarded[id]=nil;return true end,SetStatusText=function()end}
assert(manager:SetDriver(driver),"dashboard provider registry attaches to the main UI driver")
assert(forwarded.calendar==manager.dashboardProviders.calendar and forwarded.legacy==manager.dashboardProviders.legacy,"providers registered before driver setup flush into the driver")
local later={owner="AchievementsUI",order=30,title="Achievement",getItems=function()return{}end}
assert(manager:RegisterDashboardProvider("achievement",later)and forwarded.achievement==manager.dashboardProviders.achievement,"providers registered after driver setup forward immediately")
assert(manager:UnregisterDashboardProviderOwner("Calendar")==1 and removed.calendar and not manager.dashboardProviders.calendar,"owner teardown removes both registry and rendered provider")
assert(manager:UnregisterDashboardProvider("achievement")and removed.achievement,"individual provider teardown is forwarded")
assert(#events>=5,"provider lifecycle emits registry updates for dashboard reflow")
assert(not manager:RegisterDashboardProvider("bad id",{}),"invalid provider identifiers are rejected")

print("Dashboard provider registry supports pre-driver registration, forwarding and owner teardown")
