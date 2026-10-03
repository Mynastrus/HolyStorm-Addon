local repository=(arg[0]:gsub("tools[/\\]test_achievement_ui.lua$",""))
local components={}
function components:CreateTable()
 local frame={shown=true};function frame:Show()self.shown=true end;function frame:Hide()self.shown=false end;function frame:IsShown()return self.shown end
 local list={frame=frame};function list:SetData(data)self.data=data end;function list:SetSelection(value)self.selection=value end
 return list
end
local HolyStorm={UIComponents=components,Data={AchievementStore={GetAwardsFor=function()return{}end}},RichContent={Render=function()end},Events={}}
function UnitGUID()return"Player-Test"end
function HolyStorm:GetAddon()return self end
function HolyStorm:GetLocale()return setmetatable({},{__index=function(_,key)return key end})end
function HolyStorm:RegisterModule(_,factory)local module={};factory(module);self.AchievementsPage=module;return module end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end;return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
assert(loadfile(repository.."LIVE/Holy_Storm_UI/UI/Framework/Components/PolicyUI.lua"))()
local list=HolyStorm.PolicyUI:CreateList({},function()end);list:SetShown(false);assert(not list:IsShown(),"PolicyUI list wrapper hides its backing frame through SetShown");list:SetShown(true);assert(list:IsShown(),"PolicyUI list wrapper shows its backing frame through SetShown")
HolyStorm.Achievements={Can=function()return true end,IsEarned=function()return false end}
assert(loadfile(repository.."LIVE/Holy_Storm_Achievements/Achievements.lua"))()
local page=HolyStorm.AchievementsPage
local function shownWidget()return{SetShown=function(self,value)self.shown=value end}end
page.browser=shownWidget();page.editor=shownWidget();page.preview=shownWidget();page.search=shownWidget();page.stateFilter=shownWidget();page.typeFilter=shownWidget();page.categoryFilter=shownWidget();page.statusFilter=shownWidget();page.newButton=shownWidget();page.detail=shownWidget();page.detailIcon={SetTexture=function()end};page.detailTitle={SetText=function()end};page.detailState={SetText=function()end};page.detailMeta={SetText=function()end};page.rich={};page.recipientList=list;page.noAwards=shownWidget()
for _,key in ipairs({"editButton","activateButton","archiveButton","awardButton","testButton","revokeButton"})do page[key]={SetEnabled=function(self,value)self.enabled=value end}end
function page:ShowMode(mode)self.mode=mode;self.browser:SetShown(mode=="browser");self.editor:SetShown(mode=="editor");self.preview:SetShown(mode=="preview")end
page:Select({achievementID="hs-test",name="Test",description="",icon=1,category="General",type="MANUAL",status="ACTIVE",revision=1})
assert(page.selected and page.mode=="browser"and page.detail.shown,"selecting an achievement opens its browser detail view")
assert(not page.recipientList:IsShown()and page.noAwards.shown,"an achievement without recipients renders the empty-recipient state without a nil call")
local file=assert(io.open(repository.."LIVE/Holy_Storm_Achievements/Achievements.lua","rb"));local source=file:read("*a");file:close();local serviceFile=assert(io.open(repository.."LIVE/Holy_Storm_Achievements/AchievementService.lua","rb"));local service=serviceFile:read("*a");serviceFile:close();assert(source:find('dependencies={"core","synchronization","ui"}',1,true)and source:find('RegisterCapability("AchievementsUI","achievement.ui.open"',1,true)and source:find('Page:Select(definition)',1,true)and source:find('UnregisterCapability("AchievementsUI","achievement.ui.open")',1,true),"the optional UI declares, registers, opens, and unregisters its capability");assert(service:find('HS_ACHIEVEMENT_OPEN_REQUESTED',1,true)and service:find('ACHIEVEMENT_UI_UNAVAILABLE',1,true),"the service reports when the optional UI capability is unavailable")
print("Achievement UI capability, open path, and recipient-list visibility contract passed")
