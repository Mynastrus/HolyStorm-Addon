local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local uiRoot=workspace.."/LIVE/Holy_Storm_UI/"
local function read(path)local file=assert(io.open(path,"rb"),path);local value=file:read("*a");file:close();return value end

local listeners={}
local HolyStorm={version="test",Events={},CharacterUI={}}
function HolyStorm:RegisterRequiredModule()local module={};self.dashboardDriver=module;return module end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm.Events:Register(event,owner,callback)listeners[event]=listeners[event]or{};listeners[event][owner]=callback end
function UnitGUID()return"Player-Local"end
local locale=setmetatable({DASHBOARD_ITEM_LEVEL="Item Level",DASHBOARD_MYTHICPLUS_RATING="Mythic+ Rating",DASHBOARD_BEST_RAID="Best Raid"},{__index=function(_,key)return key end})
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;error(name)end

function HolyStorm.CharacterUI:GetDashboardSummary(guid)
 assert(guid=="Player-Local","dashboard queries only the logged-in character")
 return{coloredName="|cffff80ccMarithiel|r",className="Paladin",specName="Retribution",specIcon=98765,itemLevel=710.5,mythicPlusRating=2500,bestRaid={difficulty="MYTHIC",killed=2,total=8}}
end
assert(loadfile(uiRoot.."UI/Framework/MainWindow.lua"))()
local UI=HolyStorm.dashboardDriver
local model=UI:BuildDashboardModel()
assert(model.name=="|cffff80ccMarithiel|r"and model.specialization:find("Retribution",1,true)and model.specialization:find("Paladin",1,true)and model.specIcon==98765,"dashboard model retains class-colored name and specialization identity")
assert(model.itemLevel=="710.5"and model.mythicPlusRating=="2500"and model.bestRaid=="M 2/8","dashboard model renders exactly the three authoritative summary values")

local function textWidget()return{text=nil,SetText=function(self,value)self.text=value end}end
local icon={image=nil,SetImage=function(self,value)self.image=value end}
UI.dashboardWidgets={icon=icon,name=textWidget(),specialization=textWidget(),itemLevel=textWidget(),mythicPlusRating=textWidget(),bestRaid=textWidget()}
UI.scroll={DoLayout=function(self)self.laidOut=true end}
assert(UI:RefreshDashboard()and icon.image==98765 and UI.dashboardWidgets.name.text==model.name and UI.dashboardWidgets.bestRaid.text=="M 2/8"and UI.scroll.laidOut,"dashboard refresh updates the existing responsive widgets")

HolyStorm.CharacterUI.GetDashboardSummary=function()return{name="Unknown"}end
local unknown=UI:BuildDashboardModel();for _,key in ipairs({"itemLevel","mythicPlusRating","bestRaid"})do assert(unknown[key]:find("|cff888888",1,true)and unknown[key]~="0","missing dashboard data uses the standard gray unknown state")end

local refreshes=0;UI.RefreshDashboard=function()refreshes=refreshes+1;return true end;UI:RegisterDashboardEvents()
for _,event in ipairs({"HS_CHARACTER_UPDATED","HS_STATS_UPDATED","HS_EQUIPMENT_UPDATED","HS_MYTHICPLUS_UPDATED","HS_RAIDLOCKS_UPDATED"})do assert(listeners[event]and listeners[event]["ui-dashboard"],event.." refresh contract");listeners[event]["ui-dashboard"](event,"Player-Other");listeners[event]["ui-dashboard"](event,"Player-Local")end
assert(refreshes==5,"only current-character producer events refresh the dashboard")

local providerCalls=0;assert(UI:RegisterDashboardProvider("legacy",function()providerCalls=providerCalls+1;return{}end));UI:RefreshDashboardProviders();assert(providerCalls==0,"legacy dashboard providers remain registrable but cannot add home content")
assert(type(UI.ShowNewsPortal)=="function"and type(UI.ShowNewsArticle)=="function","legacy news navigation entry points remain harmless compatibility shims")

local source=read(uiRoot.."UI/Framework/MainWindow.lua")
for _,obsolete in ipairs({"NEWS_WELCOME_TITLE","NEWS_MODULES_TITLE","NEWS_PROFILES_TITLE","MODULE_LIST_TITLE","COMMAND_LIST_TITLE","ReloadUI","InlineGroup"})do assert(not source:find(obsolete,1,true),"obsolete dashboard construction remains: "..obsolete)end
for _,forbidden in ipairs({"HS_Player_DB","HolyStormDB","C_Timer.NewTicker"})do assert(not source:find(forbidden,1,true),"forbidden dashboard dependency: "..forbidden)end
assert(source:find('function UI:CreateRightDock()',1,true)and source:find('self:AddRightDockIcon("home"',1,true)and source:find('self:AddRightDockIcon("options"',1,true),"right dock remains intact")
local en=read(uiRoot.."UI/Locales/enUS.lua");local de=read(uiRoot.."UI/Locales/deDE.lua")
assert(en:find('"Item Level"',1,true)and en:find('"Mythic+ Rating"',1,true)and en:find('"Best Raid"',1,true),"English dashboard labels")
assert(de:find('"Gegenstandsstufe"',1,true)and de:find('"Mythic+ Wertung"',1,true)and de:find('"Bester Raid"',1,true),"German dashboard labels")

print("Compact current-character dashboard, compatibility, refresh and localization tests passed")
