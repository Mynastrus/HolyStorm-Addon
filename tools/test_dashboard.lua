local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local uiRoot=workspace.."/LIVE/Holy_Storm_UI/"
local function read(path)local file=assert(io.open(path,"rb"),path);local value=file:read("*a");file:close();return value end

local listeners={};local providersEnabled={News=true,Calendar=false,AchievementsUI=false};local openedTab,openedPage,request
local UI={dashboardProviders={}}
local profiles={selected=nil}
local unknown="|cff888888\226\128\147|r"
local HolyStorm={version="test",Events={},Utils={},State={},Data={}}
HolyStorm.UIComponents={FormatState=function()return unknown end}
HolyStorm.Utils.SafeCall=function(_,callback,...)
 local values={pcall(callback,...)};local ok=table.remove(values,1);return ok,table.unpack(values)
end
function HolyStorm:RegisterRequiredModule()return UI end
function HolyStorm:ApplyModuleMetadata()end
function HolyStorm:GetModule(id)
 if id=="UI"then return UI end
 if id=="Profiles"then return profiles end
 if id=="AchievementsUI"then return{IsEnabled=function()return providersEnabled.AchievementsUI end}end
end
function HolyStorm:IsOptionalModuleEnabled(id)return providersEnabled[id]==true end
function HolyStorm.Events:Register(event,owner,callback)listeners[event]=listeners[event]or{};listeners[event][owner]=callback end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(listeners[event]or{})do callback(event,...)end end
function UI:ShowPage(id)openedPage=id;return true end
function UnitGUID()return"Player-Local"end
HolyStorm.UI=UI
local raidLocale={RAID_DIFFICULTY_NORMAL="Normal",RAID_COLUMN_BOSS="Boss",RAID_COLUMN_BEST="Best",RAID_COLUMN_KILLS="Kills"}
local locale=setmetatable({TABLE_EMPTY="No entries",TABLE_UNKNOWN="Unknown",DASHBOARD_SPEC_CLASS="%s - %s",DASHBOARD_SEASON="Season %d",DASHBOARD_DELVE_ACTIVITIES="%d activities this week",DASHBOARD_ACHIEVEMENTS_COUNT="%d / %d",DASHBOARD_BIRTHDAY="Birthday: %s",DASHBOARD_PREFERRED_ROLE="Preferred role: %s",DASHBOARD_ROLE_HEALER="Healer"},{__index=function(_,key)return key end})
function LibStub(name,silent)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}
 elseif name=="AceLocale-3.0"then return{GetLocale=function(_,id)return id=="Holy_Storm_CharacterUI"and raidLocale or locale end}end
 if silent then return nil end;error(name)
end

local latestSnapshot={
 coloredName="|cff70c0ffTestdruid|r",name="Testdruid",className="Druid",classFile="DRUID",specName="Balance",specIcon=12345,level=90,realm="Norgannon",guildRank="Council",
 itemLevel=312.6,mythicPlusRating=2009,mythicPlusSeasonId=18,equipment={slots={head={itemLevel=312},chest={itemLevel=310},legs=false}},
 bestRaid={difficulty="NORMAL",killed=6,total=8,raidName="The Poisonous Abyss",raidInstanceId=500},bestRaidRows={{bossName="Current Boss",difficulty="NORMAL",kills=5,raidInstanceId=500},{bossName="Old Boss",difficulty="MYTHIC",kills=8,raidInstanceId=100}},
 delves={weeklyProgress=4,activities={{},{}}},stats={primary={strength={effective=10},agility={effective=20}},secondary={haste={rating=30}}},
}
local context={characterUUID="Player-Local",accountUUID="Account-1",name="Testdruid",classFile="DRUID",record={profile={preferredRole="HEALER"}},guild={}}
HolyStorm.CharacterUI={
 GetDashboardSummary=function(_,guid)assert(guid=="Player-Local");return latestSnapshot end,
 ResolveContext=function(_,guid)assert(guid=="Player-Local");return context end,
 GetTab=function(_,id)return id=="achievements"and providersEnabled.AchievementsUI and{}or nil end,
 OpenCharacter=function(_,guid,id)openedTab={guid=guid,id=id};return true end,
 RequestRefresh=function(_,guid,blocks,reason)request={guid=guid,blocks=blocks,reason=reason};return true end,
 RaidIdentityMatches=function(_,row,identity)return row.raidInstanceId==identity.raidInstanceId end,
 GetDifficultyColor=function(_,key)return key=="NORMAL"and{r=.2,g=1,b=.2}or nil end,
 ColorDifficulty=function(_,key,value)return"|cff33ff33"..value.."|r"end,
}
HolyStorm.Data.PlayerStore={GetLocalPlayerId=function()return"Player-Local"end,Get=function()return{metadata={displayName="Richard",birthdate="14 March"}}end}
HolyStorm.TwinkCore={GetVisibleCharactersForViewer=function(_,account)return account=="Account-1"and{"Player-Local","AltOne","AltTwo"}or{}end}
HolyStorm.Achievements={
 GetDefinitions=function()return{{achievementID="one"},{achievementID="two"}}end,
 IsEarned=function(_,id)return id=="one"end,
}
HolyStorm.Tasks={GetTaskType=function(_,id)return id=="Character.Refresh"end}

assert(loadfile(uiRoot.."UI/Framework/MainWindow.lua"))()
assert(loadfile(uiRoot.."UI/Framework/Dashboard.lua"))()

local model=UI:BuildDashboardModel()
assert(model.name==latestSnapshot.coloredName and model.specification=="Balance - Druid"and model.classFile=="DRUID","class-colored identity and spec/class use stored Character data")
assert(model.itemLevel=="312.6"and model.equippedCount==2,"equipment value and slot summary come from the stored Equipment block")
assert(model.mythicPlusRating=="2009"and model.mythicPlusSubtitle==locale.DASHBOARD_MYTHIC_CURRENT,"Mythic+ rating uses the stored current-season score without exposing Blizzard's internal season ID")
assert(model.raidValue:find("Normal 6/8",1,true)and model.raidSubtitle=="The Poisonous Abyss","Raid card shows catalog-scoped lifetime progress, not weekly lockouts")
assert(model.delvesValue=="4"and model.delvesSubtitle=="2 activities this week","Delves card reflects stored weekly progress")
assert(model.statsValue=="3"and model.twinksValue=="2","Stats and additional-character counts are based on their existing data APIs")
assert(model.profileAvailable and#model.profileRows==3 and model.profileRows[1].text=="Richard"and model.profileRows[3].text=="Preferred role: Healer","only configured local profile fields are displayed")
assert(not model.achievementsAvailable,"optional Achievements tab stays hidden while its feature module is disabled")

providersEnabled.AchievementsUI=true;local withAchievement=UI:BuildDashboardModel();assert(withAchievement.achievementsAvailable and withAchievement.achievementValue=="1 / 2","Achievements card appears only with the existing enabled feature and reports actual earned definitions")
HolyStorm.Achievements.GetDefinitions=function()return{}end;local emptyAchievements=UI:BuildDashboardModel();assert(emptyAchievements.achievementValue=="0"and emptyAchievements.achievementSubtitle==locale.DASHBOARD_ACHIEVEMENTS_NONE,"confirmed empty achievement catalogs display zero instead of an ambiguous 0 / 0")
HolyStorm.Achievements.GetDefinitions=function()return{{achievementID="one"},{achievementID="two"}}end
context.record.profile={};HolyStorm.Data.PlayerStore.Get=function()return{metadata={}}end;local noProfile=UI:BuildDashboardModel();assert(not noProfile.profileAvailable and#noProfile.profileRows==0,"an empty profile collapses the personal panel")
context.record.profile={preferredRole="HEALER"};HolyStorm.Data.PlayerStore.Get=function()return{metadata={displayName="Richard",birthdate="14 March"}}end

local unknownSnapshot={name="Unknown",className=nil,specName=nil,specIcon=nil,itemLevel=nil,mythicPlusRating=nil,bestRaid=nil,bestRaidRows={}}
HolyStorm.CharacterUI.GetDashboardSummary=function()return unknownSnapshot end
local unknown=UI:BuildDashboardModel()
for _,value in ipairs({unknown.itemLevel,unknown.mythicPlusRating,unknown.raidValue,unknown.statsValue})do assert(value=="|cff888888\226\128\147|r","unknown summary values stay neutral and do not become zero")end
HolyStorm.CharacterUI.GetDashboardSummary=function()return latestSnapshot end

local layout450=UI:CalculateDashboardLayout(860,450);assert(layout450.navButtonWidth>89 and layout450.widgetHeight>100 and layout450.primaryHeight==94,"standard-size page keeps labeled tabs, primary cards and a useful dynamic area")
assert(layout450.headerHeight>=75 and layout450.headerHeight<=90,"identity header remains compact at the standard window size")
assert(UI:CalculateDashboardProfileHeight(0)==34 and UI:CalculateDashboardProfileHeight(1)==51 and UI:CalculateDashboardProfileHeight(3)==85,"profile panel height grows only with actual profile rows")
assert(UI:CalculateDashboardProfileWidth(900)==288 and UI:CalculateDashboardProfileWidth(650)==280,"profile width remains bounded in the requested range at standard and narrow window sizes")
local dashboardSource=read(uiRoot.."UI/Framework/Dashboard.lua")
assert(dashboardSource:find('profile:SetHeight(self:CalculateDashboardProfileHeight(#self.dashboardModel.profileRows))',1,true)and dashboardSource:find('row.icon:SetPoint("LEFT",frame,"LEFT",12,-(25+(index-1)*17))',1,true),"profile fields are anchored to the content-sized card rather than the tab region")
assert(dashboardSource:find('profile:SetPoint("TOPRIGHT",headerContent,"TOPRIGHT"',1,true)and not dashboardSource:find('profile:SetPoint("TOP",headerContent,"TOP"',1,true),"profile uses one top-right anchor rather than conflicting horizontal constraints")
assert(dashboardSource:find('local function styleDashboardHeading(region)',1,true)and dashboardSource:find('local function styleDashboardBody(region)',1,true)and dashboardSource:find('styleDashboardHeading(frame.title)',1,true)and dashboardSource:find('styleDashboardBody(row.text)',1,true),"profile heading and body use shared canonical dashboard styles")
assert(dashboardSource:find('frame.icon:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-7)',1,true)and dashboardSource:find('frame.title:SetPoint("TOPLEFT",frame,"TOPLEFT",38,-9)',1,true),"provider header icons and labels are anchored inside their owning card")
assert(dashboardSource:find('DASHBOARD_GUILD_RANK_SHORT',1,true),"character identity shows the localized rank value without a redundant label")
GameFontNormal={name="GameFontNormal"};GameFontHighlightSmall={name="GameFontHighlightSmall"}
local dimColor={.2,.2,.2,0}
local function mockRegion()
 local region={state={}}
 function region:SetFontObject(value)self.state.font=value;self.state.color=dimColor;self.state.alpha=0 end
 function region:SetTextColor(r,g,b,a)self.state.color={r,g,b,a}end
 function region:SetAlpha(value)self.state.alpha=value end
 function region:SetText(value)self.state.text=value end
 function region:ClearAllPoints()end;function region:SetPoint()end;function region:SetJustifyH()end;function region:SetWordWrap()end
 function region:SetSize()end;function region:SetTexture(value)self.state.texture=value end;function region:SetTexCoord()end;function region:Show()self.state.shown=true end;function region:Hide()self.state.shown=false end
 return region
end
local profileMock={title=mockRegion(),rows={}}
function profileMock:SetAlpha(value)self.alpha=value end
function profileMock:CreateTexture()return mockRegion()end
function profileMock:CreateFontString()return mockRegion()end
UI.profilePanel=profileMock;UI:UpdateProfilePanel(model)
assert(profileMock.alpha==1 and profileMock.title.state.font==GameFontNormal and profileMock.title.state.color[1]==1 and profileMock.title.state.alpha==1,"profile heading reapplies its canonical gold style after font-object assignment")
assert(profileMock.rows[1].text.state.font==GameFontHighlightSmall and profileMock.rows[1].text.state.color[1]==.92 and profileMock.rows[1].text.state.alpha==1 and profileMock.rows[1].icon.state.alpha==1,"profile rows and icons finish refresh in the canonical visible state")
local compactLayout=UI:CalculateDashboardLayout(600,380);assert(compactLayout.navButtonWidth<89,"narrow layouts have a clear icon-only tab threshold")
local none,zeroColumns=UI:CalculateDashboardProviderLayout(0,800);local one,oneColumn=UI:CalculateDashboardProviderLayout(1,800);local two,twoColumns=UI:CalculateDashboardProviderLayout(2,800);local three,threeColumns=UI:CalculateDashboardProviderLayout(3,800)
assert(#none==0 and zeroColumns==0 and oneColumn==1 and one[1].width==800,"no providers leave no placeholder; one widget uses the full row")
assert(twoColumns==2 and two[2].x>two[1].x and threeColumns==2 and three[3].y>three[1].y,"multiple providers use two balanced columns and continue on a second row")

local skippedCalls=0
assert(UI:RegisterDashboardProvider("calendar-test",{owner="Calendar",moduleName="Calendar",optional=true,getItems=function()skippedCalls=skippedCalls+1;return{{title="Should stay hidden"}}end}))
local absent=UI:BuildDynamicProviderItems();assert(#absent==0 and skippedCalls==0,"a disabled optional Calendar provider is neither called nor rendered")
assert(UI:RegisterDashboardProvider("news-test",{owner="News",order=10,title="News",available=function()return true end,getItems=function()return{{title="Season update",summary="Published today"}}end}))
local visible=UI:BuildDynamicProviderItems();assert(#visible==1 and visible[1].id=="news-test"and visible[1].items[1].title=="Season update","available providers contribute data-backed widget entries")
assert(UI:CalculateDashboardLayout(900,560).widgetHeight<=184,"dashboard providers use a bounded content area at the standard window size")
local oneWidgetHeight=UI:CalculateDashboardWidgetHeight({{items={{title="One",summary="Today"}}}},184)
local multiWidgetHeight=UI:CalculateDashboardWidgetHeight({{items={{title="One"},{title="Two",summary="Tomorrow"}}},{items={{title="Guild award"}}}},184)
assert(oneWidgetHeight==70 and multiWidgetHeight==96 and UI:CalculateDashboardWidgetHeight({},184)==0,"single-provider height follows its entries and multi-provider rows share the tallest content height")
local tooltipRows=UI:BuildRaidTooltipRows({raid=latestSnapshot.bestRaid,raidRows=latestSnapshot.bestRaidRows});assert(#tooltipRows==1 and tooltipRows[1].cells[1]=="Current Boss"and tooltipRows[1].cells[2]=="N"and tooltipRows[1].cells[3]==5,"Raid tooltip reuses trusted lifetime boss rows scoped to the displayed raid")
assert(UI:UnregisterDashboardProviderOwner("News")==1 and UI:BuildDynamicProviderItems()[1]==nil,"providers unregister cleanly with their owning module")
assert(UI:UnregisterDashboardProvider("calendar-test"),"optional provider can be removed")

assert(UI:OpenCharacterTab("raid")and openedTab.guid=="Player-Local"and openedTab.id=="raid","dashboard navigation opens the established Character tab")
HolyStorm.UI={ShowPage=function(_,id)openedPage=id;return true end}
UI:OpenProfileSettings();assert(openedPage=="profiles"and profiles.selected=="Player-Local","personal profile interaction opens the existing settings page and selects the current character")
local status="";UI.SetStatusText=function(_,value)status=value end;UI.refreshButton={enabled=true,SetEnabled=function(self,value)self.enabled=value end}
assert(UI:RefreshCharacterData()and request.guid=="Player-Local"and request.reason=="MANUAL"and status=="DASHBOARD_REFRESHING"and not UI.refreshButton.enabled,"refresh routes through the existing central Character.Refresh workflow")
local source=read(uiRoot.."UI/Framework/Dashboard.lua")
for _,forbidden in ipairs({"HS_Player_DB","HolyStormDB","PlayerData:WriteOwnedBlock","PlayerStore:SetLocalMetadata","C_Timer.NewTicker","CallCapability(\"character.scan"})do assert(not source:find(forbidden,1,true),"dashboard must consume APIs and avoid direct writes, extra scans or polling: "..forbidden)end
local en=read(uiRoot.."UI/Locales/enUS.lua");local de=read(uiRoot.."UI/Locales/deDE.lua")
for _,key in ipairs({"DASHBOARD_PROFILE_TITLE","DASHBOARD_BIRTHDAY","DASHBOARD_PREFERRED_ROLE","DASHBOARD_REFRESH","DASHBOARD_RAID_TOOLTIP","DASHBOARD_VIEW_ALL"})do assert(en:find('L["'..key..'"]',1,true)and de:find('L["'..key..'"]',1,true),"both locales include "..key)end
assert(source:find("function UI:BuildHomeDashboard",1,true)and source:find("function UI:LayoutDashboard",1,true)and source:find("function UI:RefreshDashboardProviders",1,true),"native dashboard construction, resize layout and provider refresh are connected")

print("Interactive responsive dashboard model, optional providers, reflow, lifetime raid tooltip, navigation and refresh tests passed")
