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
local locale=setmetatable({TABLE_EMPTY="No entries",TABLE_UNKNOWN="Unknown",DASHBOARD_SPEC_CLASS="%s - %s",DASHBOARD_SEASON="Season %d",DASHBOARD_DELVE_ACTIVITIES="%d activities this week",DASHBOARD_ACHIEVEMENTS_COUNT="%d / %d",DASHBOARD_BIRTHDAY="Birthday: %s",DASHBOARD_PREFERRED_ROLE="Role: %s",DASHBOARD_ROLE_HEALER="Healer",DASHBOARD_ROLE_TANK="Tank"},{__index=function(_,key)return key end})
function LibStub(name,silent)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}
 elseif name=="AceLocale-3.0"then return{GetLocale=function(_,id)return id=="Holy_Storm_CharacterUI"and raidLocale or locale end}end
 if silent then return nil end;error(name)
end

local latestSnapshot={
 coloredName="|cff70c0ffTestdruid|r",name="Testdruid",className="Druid",classFile="DRUID",specName="Balance",specIcon=12345,level=90,realm="Norgannon",guildRank="Council",
 itemLevel=312.6,mythicPlusRating=2009,mythicPlusSeasonId=18,equipment={slots={head={itemLevel=312},chest={itemLevel=310},legs=false}},
 bestRaid={difficulty="NORMAL",killed=6,total=8,raidName="The Poisonous Abyss",raidInstanceId=500},bestRaidRows={{bossName="Current Boss",difficulty="NORMAL",kills=5,raidInstanceId=500},{bossName="Old Boss",difficulty="MYTHIC",kills=8,raidInstanceId=100}},snapshotStatus={equipment="CURRENT",mythicPlus="CURRENT",raidLifetime="CURRENT",delves="CURRENT",stats="CURRENT"},
 delves={snapshotVersion=3,seasonNumber=4,greatVaultWorld={progress=4,activities={{},{}}}},stats={snapshotVersion=2,schemaVersion=2,primary={strength={baseline=10},agility={baseline=20}},secondary={haste={rating=30}}},
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
assert(model.delvesValue=="DASHBOARD_DELVE_STORED_SEASON"and model.delvesSubtitle=="DASHBOARD_DELVE_SEASON","Delves card identifies the stored season without mislabeling Vault activity as Delves progress")
assert(model.statsValue=="3"and model.twinksValue=="2","Stats and additional-character counts are based on their existing data APIs")
local completeStats=latestSnapshot.stats;latestSnapshot.stats={snapshotVersion=2,schemaVersion=2,primary={strength={baseline=95},agility={baseline=50}},secondary={},armor={},capture={eligible=true,partial=true,reason="TIMED_AURA_ACTIVE"}};local partialStats=UI:BuildDashboardModel();assert(partialStats.statsValue=="2","the Dashboard counts persisted primary baselines in a valid partial Stats snapshot instead of showing unknown")
latestSnapshot.stats=completeStats
assert(model.snapshotStatus.equipment=="CURRENT"and model.snapshotStatus.raidLifetime=="CURRENT","dashboard consumes producer-owned status states from the shared summary")
assert(model.profileAvailable and#model.profileRows==3 and model.profileRows[1].text=="Richard"and model.profileRows[3].text=="Role: Healer","only configured local profile fields are displayed")
assert(not model.achievementsAvailable,"optional Achievements tab stays hidden while its feature module is disabled")

providersEnabled.AchievementsUI=true;local withAchievement=UI:BuildDashboardModel();assert(withAchievement.achievementsAvailable and withAchievement.achievementValue=="1 / 2","Achievements card appears only with the existing enabled feature and reports actual earned definitions")
HolyStorm.Achievements.GetDefinitions=function()return{}end;local emptyAchievements=UI:BuildDashboardModel();assert(emptyAchievements.achievementValue=="0"and emptyAchievements.achievementSubtitle==locale.DASHBOARD_ACHIEVEMENTS_NONE,"confirmed empty achievement catalogs display zero instead of an ambiguous 0 / 0")
HolyStorm.Achievements.GetDefinitions=function()return{{achievementID="one"},{achievementID="two"}}end
context.record.profile={};HolyStorm.Data.PlayerStore.Get=function()return{metadata={}}end;local noProfile=UI:BuildDashboardModel();assert(not noProfile.profileAvailable and#noProfile.profileRows==0,"an empty profile collapses the personal panel")
context.record.profile={preferredRole="HEALER"};HolyStorm.Data.PlayerStore.Get=function()return{metadata={displayName="Richard",birthdate="14 March"}}end
context.record.profile={preferredRole="TANK"};local changedProfile=UI:BuildDashboardModel();assert(changedProfile.profileAvailable and changedProfile.profileRows[3].text=="Role: Tank","profile role changes appear on the next data driven dashboard rebuild");context.record.profile={preferredRole="HEALER"}

local unknownSnapshot={name="Unknown",className=nil,specName=nil,specIcon=nil,itemLevel=nil,mythicPlusRating=nil,bestRaid=nil,bestRaidRows={}}
HolyStorm.CharacterUI.GetDashboardSummary=function()return unknownSnapshot end
local unknown=UI:BuildDashboardModel()
for _,value in ipairs({unknown.itemLevel,unknown.mythicPlusRating,unknown.raidValue,unknown.statsValue})do assert(value=="|cff888888\226\128\147|r","unknown summary values stay neutral and do not become zero")end
HolyStorm.CharacterUI.GetDashboardSummary=function()return latestSnapshot end

local layout450=UI:CalculateDashboardLayout(860,450);assert(layout450.navButtonWidth>89 and layout450.widgetHeight>100 and layout450.primaryHeight==94,"standard-size page keeps labeled tabs, primary cards and a useful dynamic area")
assert(layout450.headerHeight>=75 and layout450.headerHeight<=90,"identity header remains compact at the standard window size")
assert(UI:CalculateDashboardProfileHeight(0)==34 and UI:CalculateDashboardProfileHeight(1)==51 and UI:CalculateDashboardProfileHeight(3)==85,"profile panel height grows only with actual profile rows")
assert(UI:CalculateDashboardProfileWidth(900)==300 and UI:CalculateDashboardProfileWidth(650)==247 and UI:CalculateDashboardProfileWidth(560)==220,"profile width scales with available content width and keeps a compact readable floor")
assert(UI:CalculateDashboardProfileTextWidth(120)==75 and UI:CalculateDashboardProfileTextWidth(220)==175 and UI:CalculateDashboardProfileTextWidth(300)==255,"profile title and row widths reserve both the icon and right inset at narrow and wide sizes")
for _,width in ipairs({900,650,560,500,280})do local header=UI:CalculateDashboardHeaderLayout(width,true);assert(header.profileWidth+10+header.identityWidth==width and header.textWidth>=1 and header.textLeft+header.textWidth<=header.identityWidth,"profile and identity bounds stay disjoint at header width "..width)end
local noProfileHeader=UI:CalculateDashboardHeaderLayout(560,false);assert(noProfileHeader.profileWidth==0 and noProfileHeader.identityWidth==556 and noProfileHeader.textWidth>0,"missing profile releases the right header area for character identity")
assert(not UI:CalculateDashboardHeaderLayout(280,true).showSpecIcon and UI:CalculateDashboardHeaderLayout(280,true).classSize==44,"very narrow headers hide the secondary icon without distorting the portrait")
local dashboardSource=read(uiRoot.."UI/Framework/Dashboard.lua")
assert(dashboardSource:find('profile:SetHeight(self:CalculateDashboardProfileHeight(#self.dashboardModel.profileRows))',1,true)and dashboardSource:find('row.icon:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-(25+(index-1)*17))',1,true),"profile fields are anchored from the card's top inset rather than its vertical center")
assert(dashboardSource:find('CreateFrame("Button",nil,headerContent,"BackdropTemplate")',1,true)and dashboardSource:find('identityText:SetWidth(headerLayout.textWidth)',1,true)and not dashboardSource:find('math.max(120,identity.frame:GetWidth()-150)',1,true),"profile and identity share their header parent and use the measured non-overflowing identity width")
assert(dashboardSource:find('profile:SetShown(profileAvailable);profile:EnableMouse(profileAvailable==true)',1,true)and dashboardSource:find('profile:SetClipsChildren(true)',1,true),"unavailable profile data leaves no visible or interactive overlay")
assert(dashboardSource:find('profile:SetPoint("TOPRIGHT",headerContent,"TOPRIGHT"',1,true)and not dashboardSource:find('profile:SetPoint("TOP",headerContent,"TOP"',1,true),"profile uses one top-right anchor rather than conflicting horizontal constraints")
assert(dashboardSource:find('profile.title:SetWidth(math.max(1,headerLayout.profileWidth-24))',1,true)and dashboardSource:find('row.text:SetWidth(self:CalculateDashboardProfileTextWidth(headerLayout.profileWidth))',1,true),"profile text widths are recalculated when the dashboard header resizes")
assert(dashboardSource:find('local function styleDashboardHeading(region)',1,true)and dashboardSource:find('local function styleDashboardBody(region)',1,true)and dashboardSource:find('styleDashboardHeading(frame.title)',1,true)and dashboardSource:find('styleDashboardBody(row.text)',1,true),"profile heading and body use shared canonical dashboard styles")
assert(dashboardSource:find('frame.icon:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-7)',1,true)and dashboardSource:find('frame.title:SetPoint("TOPLEFT",frame,"TOPLEFT",38,-9)',1,true),"provider header icons and labels are anchored inside their owning card")
assert(dashboardSource:find('DASHBOARD_GUILD_RANK_SHORT',1,true),"character identity shows the localized rank value without a redundant label")
assert(dashboardSource:find('positioner=function(activeOwner,tooltip)UI:PositionDashboardTooltip(activeOwner,tooltip)end',1,true),"LibQTip Dashboard cards use the shared screen-aware tooltip positioner")
do
	local oldTooltip,oldParent=GameTooltip,UIParent;local oldCanvas,oldPrimary,oldSecondary,oldProfile,oldHeader,oldNav,oldWidgets=UI.dashboardCanvas,UI.primaryCards,UI.secondaryCards,UI.profilePanel,UI.headerPanel,UI.navFrame,UI.widgetFrames
	local tooltip={width=300,height=160}
	function tooltip:GetWidth()return self.width end;function tooltip:GetHeight()return self.height end
	function tooltip:SetClampedToScreen(value)self.clamped=value end
	function tooltip:ClearAllPoints()self.point=nil end;function tooltip:SetPoint(...)self.point={...}end
	GameTooltip=tooltip;UI.dashboardCanvas=nil;UI.primaryCards=nil;UI.secondaryCards=nil;UI.profilePanel=nil;UI.headerPanel=nil;UI.navFrame=nil;UI.widgetFrames=nil
	local function owner(left,right,top,bottom)return{GetLeft=function()return left end,GetRight=function()return right end,GetTop=function()return top end,GetBottom=function()return bottom end}end
	local function screen(width,height)UIParent={GetWidth=function()return width end,GetHeight=function()return height end}end
	screen(1920,1080)
	local _,leftSide,leftX,leftY=UI:PositionDashboardTooltip(owner(1800,1880,1060,1000));assert(leftSide=="LEFT"and leftX==1492 and leftY==1072,"near-right and top-edge tooltip flips left and clamps vertically")
	local _,rightSide,rightX,rightY=UI:PositionDashboardTooltip(owner(20,80,600,500));assert(rightSide=="RIGHT"and rightX==88 and rightY==630,"open space to the right wins for a centered card")
	screen(320,800);tooltip.width=200;tooltip.height=100
	local _,topSide,topX,topY=UI:PositionDashboardTooltip(owner(110,210,300,200));assert(topSide=="TOP"and topX==60 and topY==408,"a narrow scaled viewport uses the clear space above when both horizontal sides are too small")
	local _,bottomSide,bottomX,bottomY=UI:PositionDashboardTooltip(owner(110,210,700,600));assert(bottomSide=="BOTTOM"and bottomX==60 and bottomY==592,"tooltip placement checks available space below as well")
	assert(tooltip.clamped==true,"native GameTooltip remains clamped to the screen")

	local function rect(left,right,top,bottom)return{GetLeft=function()return left end,GetRight=function()return right end,GetTop=function()return top end,GetBottom=function()return bottom end,IsShown=function()return true end}end
	local scaleChoices={.75,1,1.25}
	for _,scale in ipairs(scaleChoices)do
		local factor=1/scale;screen(1920*factor,1080*factor);tooltip.width=300*factor;tooltip.height=160*factor
		local canvas=rect(510*factor,1410*factor,900*factor,200*factor);local equipment=rect(520*factor,800*factor,700*factor,606*factor);local mythic=rect(807*factor,1097*factor,700*factor,606*factor);local raid=rect(1104*factor,1400*factor,700*factor,606*factor)
		UI.dashboardCanvas=canvas;UI.primaryCards={equipment=equipment,mythicPlus=mythic,raid=raid};UI.secondaryCards={}
		local _,cardSide,cardX,cardY=UI:PositionDashboardTooltip(equipment)
		assert(cardSide=="LEFT"and cardX>=8 and cardX+tooltip.width<=UIParent:GetWidth()-8 and cardY>=tooltip.height+8 and cardY<=UIParent:GetHeight()-8,"equipment tooltip uses open space outside the full card row at UI scale "..scale)
		local function overlaps(x,y,w,h,other)return math.min(x+w,other:GetRight())>math.max(x,other:GetLeft())and math.min(y,other:GetTop())>math.max(y-h,other:GetBottom())end
		assert(not overlaps(cardX,cardY,tooltip.width,tooltip.height,mythic)and not overlaps(cardX,cardY,tooltip.width,tooltip.height,raid),"equipment tooltip avoids the adjacent Mythic+ and Raid cards")
		local _,mythicSide,mx,my=UI:PositionDashboardTooltip(mythic);assert(mythicSide=="TOP"and not overlaps(mx,my,tooltip.width,tooltip.height,equipment)and not overlaps(mx,my,tooltip.width,tooltip.height,raid),"Mythic+ tooltip avoids both neighboring metric cards at UI scale "..scale)
	end
	UI.dashboardCanvas,UI.primaryCards,UI.secondaryCards,UI.profilePanel,UI.headerPanel,UI.navFrame,UI.widgetFrames=oldCanvas,oldPrimary,oldSecondary,oldProfile,oldHeader,oldNav,oldWidgets
	GameTooltip,UIParent=oldTooltip,oldParent
end
GameFontNormal={name="GameFontNormal"};GameFontHighlightSmall={name="GameFontHighlightSmall"}
local dimColor={.2,.2,.2,0}
local function mockRegion()
 local region={state={}}
 function region:SetFontObject(value)self.state.font=value;self.state.color=dimColor;self.state.alpha=0 end
 function region:SetTextColor(r,g,b,a)self.state.color={r,g,b,a}end
 function region:SetAlpha(value)self.state.alpha=value end
	function region:SetText(value)self.state.text=value end
	function region:ClearAllPoints()self.state.points={}end;function region:SetPoint(...)self.state.points=self.state.points or{};self.state.points[#self.state.points+1]={...}end;function region:SetJustifyH()end;function region:SetWordWrap(value)self.state.wordWrap=value end;function region:SetNonSpaceWrap(value)self.state.nonSpaceWrap=value end;function region:SetMaxLines(value)self.state.maxLines=value end
 function region:SetSize()end;function region:SetWidth(value)self.state.width=value end;function region:SetTexture(value)self.state.texture=value end;function region:SetTexCoord()end;function region:Show()self.state.shown=true end;function region:Hide()self.state.shown=false end
 return region
end
local profileMock={title=mockRegion(),rows={}}
function profileMock:SetAlpha(value)self.alpha=value end
function profileMock:GetWidth()return 220 end
function profileMock:CreateTexture()return mockRegion()end
function profileMock:CreateFontString()return mockRegion()end
UI.profilePanel=profileMock;UI:UpdateProfilePanel(model)
assert(profileMock.alpha==1 and profileMock.title.state.font==GameFontNormal and profileMock.title.state.color[1]==1 and profileMock.title.state.alpha==1,"profile heading reapplies its canonical gold style after font-object assignment")
assert(profileMock.rows[1].text.state.font==GameFontHighlightSmall and profileMock.rows[1].text.state.color[1]==.92 and profileMock.rows[1].text.state.alpha==1 and profileMock.rows[1].icon.state.alpha==1,"profile rows and icons finish refresh in the canonical visible state")
assert(#profileMock.rows==3 and profileMock.title.state.text==locale.DASHBOARD_PROFILE_TITLE,"the complete profile displays its heading and all three configured rows")
assert(profileMock.title.state.width==196 and profileMock.title.state.wordWrap==false and profileMock.title.state.maxLines==1,"profile title stays within the panel's horizontal inset")
for index,row in ipairs(profileMock.rows)do local point=row.icon.state.points[1];local textPoint=row.text.state.points[1];assert(row.icon.state.shown and row.text.state.shown and point[1]=="TOPLEFT"and point[2]==profileMock and point[5]==-(25+(index-1)*17),"profile row "..index.." stays top-anchored and visible in order");assert(#row.text.state.points==1 and textPoint[1]=="LEFT"and textPoint[2]==row.icon and row.text.state.width==175,"profile row "..index.." text aligns to its icon and stays inside the right inset")end
assert(profileMock.rows[1].text.state.wordWrap==false and profileMock.rows[1].text.state.nonSpaceWrap==false and profileMock.rows[1].text.state.maxLines==1,"profile text stays on one line within its measured width")
local priorContext=context;local priorUnitGUID=UnitGUID;local priorSummary=HolyStorm.CharacterUI.GetDashboardSummary;local priorResolve=HolyStorm.CharacterUI.ResolveContext;local selectedGUID="Player-Other";UnitGUID=function()return selectedGUID end
HolyStorm.CharacterUI.GetDashboardSummary=function(_,guid)assert(guid==selectedGUID);return latestSnapshot end;HolyStorm.CharacterUI.ResolveContext=function(_,guid)assert(guid==selectedGUID);return context end
context={characterUUID="Player-Other",accountUUID="Account-1",record={profile={}}};local switched=UI:BuildDashboardModel();assert(switched.guid=="Player-Other"and#switched.profileRows==2 and switched.profileRows[1].kind=="name"and switched.profileRows[2].kind=="birthday","switching to a character with missing profile fields keeps the available account rows")
UI:UpdateProfilePanel(switched);assert(profileMock.rows[1].text.state.shown and profileMock.rows[2].text.state.shown and not profileMock.rows[3].text.state.shown and not profileMock.rows[3].icon.state.shown,"character switch hides stale role data while preserving the available rows")
context={characterUUID="Player-Local",accountUUID="Account-1",record={profile={}}};HolyStorm.Data.PlayerStore.Get=function()return{metadata={displayName="Richard"}}end;local sparse=UI:BuildDashboardModel();assert(#sparse.profileRows==1 and sparse.profileRows[1].kind=="name","profile with birthday and role absent returns only its configured name")
UI:UpdateProfilePanel(sparse);assert(profileMock.rows[1].text.state.shown and not profileMock.rows[2].text.state.shown,"partial profile keeps its available value visible without stale fields")
HolyStorm.Data.PlayerStore.Get=function()return{metadata={}}end;local emptyProfile=UI:BuildDashboardModel();assert(not emptyProfile.profileAvailable and#emptyProfile.profileRows==0,"profile with all optional fields absent is unavailable")
UI:UpdateProfilePanel(emptyProfile);assert(not profileMock.rows[1].text.state.shown and not profileMock.rows[1].icon.state.shown,"switching to a character with no profile information clears every old row")
selectedGUID="Player-Local";context=priorContext;HolyStorm.CharacterUI.GetDashboardSummary=priorSummary;HolyStorm.CharacterUI.ResolveContext=priorResolve;UnitGUID=priorUnitGUID;HolyStorm.Data.PlayerStore.Get=function()return{metadata={displayName="Richard",birthdate="14 March"}}end;UI:UpdateProfilePanel(model)
local compactLayout=UI:CalculateDashboardLayout(600,380);assert(compactLayout.navButtonWidth<89,"narrow layouts have a clear icon-only tab threshold")
local none,zeroColumns=UI:CalculateDashboardProviderLayout(0,800);local one,oneColumn=UI:CalculateDashboardProviderLayout(1,800);local two,twoColumns=UI:CalculateDashboardProviderLayout(2,800);local three,threeColumns=UI:CalculateDashboardProviderLayout(3,800)
assert(#none==0 and zeroColumns==0 and oneColumn==1 and one[1].width==800,"no providers leave no placeholder; one widget uses the full row")
assert(twoColumns==2 and two[2].x>two[1].x and threeColumns==2 and three[3].y>three[1].y,"multiple providers use two balanced columns and continue on a second row")

local skippedCalls=0
assert(UI:RegisterDashboardProvider("calendar-test",{owner="Calendar",moduleName="Calendar",optional=true,getItems=function()skippedCalls=skippedCalls+1;return{{title="Should stay hidden"}}end}))
local absent=UI:BuildDynamicProviderItems();assert(#absent==0 and skippedCalls==0,"a disabled optional Calendar provider is neither called nor rendered")
assert(UI:RegisterDashboardProvider("news-test",{owner="News",order=10,title="News",available=function()return true end,getItems=function()return{{title="Season update",summary="Published today"}}end}))
local visible=UI:BuildDynamicProviderItems();assert(#visible==1 and visible[1].id=="news-test"and visible[1].items[1].title=="Season update","available providers contribute data-backed widget entries")
local originalRefresh=HolyStorm.CharacterUI.RequestRefresh;local targeted
HolyStorm.CharacterUI.RequestRefresh=function(_,guid,blocks,reason)targeted={guid=guid,blocks=blocks,reason=reason};return true end
assert(UI:ActivateSnapshotCard("mythicPlus","mythicPlus","STALE")and targeted.guid=="Player-Local"and#targeted.blocks==1 and targeted.blocks[1]=="mythicPlus"and targeted.reason=="MANUAL"and not openedTab,"a stale tile starts only its producer through the existing manual refresh contract")
assert(UI:ActivateSnapshotCard("delves","delves","MISSING")and targeted.blocks[1]=="delves"and#targeted.blocks==1,"a missing tile targets only its own producer")
assert(UI:ActivateSnapshotCard("stats","stats","ERROR")and targeted.blocks[1]=="stats"and#targeted.blocks==1,"an error tile retries only its producer")
for _,entry in ipairs({{"equipment","equipment"},{"mythicPlus","mythicPlus"},{"raid","raid"},{"delves","delves"},{"stats","stats"}})do local tab,block=entry[1],entry[2];assert(UI:ActivateSnapshotCard(tab,block,"MISSING")and#targeted.blocks==1 and targeted.blocks[1]==block,"missing snapshot action targets only "..block);assert(UI:ActivateSnapshotCard(tab,block,"STALE")and#targeted.blocks==1 and targeted.blocks[1]==block,"stale snapshot action targets only "..block);assert(UI:ActivateSnapshotCard(tab,block,"ERROR")and#targeted.blocks==1 and targeted.blocks[1]==block,"error retry targets only "..block)end
HolyStorm.CharacterUI.RequestRefresh=originalRefresh
local subtitle={value="",wrapped=false};function subtitle:SetText(value)self.value=value end;function subtitle:SetWordWrap(value)self.wrapped=value end;function subtitle:SetTextColor()end
local stateKeys={MISSING="DASHBOARD_SCAN_MISSING",STALE="DASHBOARD_SCAN_STALE",DIRTY="DASHBOARD_SNAPSHOT_DIRTY",REFRESHING="DASHBOARD_SNAPSHOT_REFRESHING",ERROR="DASHBOARD_SCAN_ERROR"}
for _,entry in ipairs({{"equipment","equipment","itemLevel"},{"mythicPlus","mythicPlus","mythicPlusRating"},{"raid","raidLifetime","raidValue"},{"delves","delves","delvesValue"},{"stats","stats","statsValue"}})do
 local tab,statusKey,valueKey=entry[1],entry[2],entry[3]
 for state,key in pairs(stateKeys)do
  latestSnapshot.snapshotStatus[statusKey]=state;local stateModel=UI:BuildDashboardModel();local storedValue=stateModel[valueKey]
  assert(storedValue and storedValue~="|cff888888\226\128\147|r","cached dashboard value remains available for "..tab.." while "..state)
  local value={text=storedValue};function value:SetText(text)self.text=text end
  UI:SetSnapshotCardStatus({value=value,subtitle=subtitle},state,"cached subtitle")
  assert(value.text==storedValue and subtitle.value==locale[key],"dashboard "..tab.." preserves its cached value and renders "..state)
 end
 latestSnapshot.snapshotStatus[statusKey]="CURRENT";UI:SetSnapshotCardStatus({subtitle=subtitle},"CURRENT","cached summary");assert(subtitle.value=="cached summary","current "..tab.." snapshot retains its existing subtitle")
end
latestSnapshot.snapshotStatus.equipment="MISSING";unknownSnapshot.snapshotStatus={equipment="MISSING",mythicPlus="MISSING",raidLifetime="MISSING",delves="MISSING",stats="MISSING"};HolyStorm.CharacterUI.GetDashboardSummary=function()return unknownSnapshot end;local missingModel=UI:BuildDashboardModel();assert(missingModel.itemLevel=="|cff888888\226\128\147|r"and missingModel.mythicPlusRating=="|cff888888\226\128\147|r"and missingModel.raidValue=="|cff888888\226\128\147|r"and missingModel.delvesValue=="|cff888888\226\128\147|r"and missingModel.statsValue=="|cff888888\226\128\147|r","missing snapshot cards retain the standard unknown marker");HolyStorm.CharacterUI.GetDashboardSummary=function()return latestSnapshot end;latestSnapshot.snapshotStatus.equipment="CURRENT"
assert(UI:CalculateDashboardLayout(900,560).widgetHeight<=184,"dashboard providers use a bounded content area at the standard window size")
local oneWidgetHeight=UI:CalculateDashboardWidgetHeight({{items={{title="One",summary="Today"}}}},184)
local multiWidgetHeight=UI:CalculateDashboardWidgetHeight({{items={{title="One"},{title="Two",summary="Tomorrow"}}},{items={{title="Guild award"}}}},184)
assert(oneWidgetHeight==70 and multiWidgetHeight==96 and UI:CalculateDashboardWidgetHeight({},184)==0,"single-provider height follows its entries and multi-provider rows share the tallest content height")
local tooltipRows=UI:BuildRaidTooltipRows({raid=latestSnapshot.bestRaid,raidRows=latestSnapshot.bestRaidRows});assert(#tooltipRows==1 and tooltipRows[1].cells[1]=="Current Boss"and tooltipRows[1].cells[2]=="N"and tooltipRows[1].cells[3]==5,"Raid tooltip reuses trusted lifetime boss rows scoped to the displayed raid")
local completeRaidRows={{bossName="Zeta",raidInstanceId=500,difficulty="HEROIC",kills=1},{bossName="Alpha",raidInstanceId=500,difficulty="NORMAL",kills=6},{bossName="Yankee",raidInstanceId=500,difficulty="NORMAL",kills=7},{bossName="Bravo",raidInstanceId=500},{bossName="Xray",raidInstanceId=500},{bossName="Charlie",raidInstanceId=500},{bossName="Whiskey",raidInstanceId=500},{bossName="Delta",raidInstanceId=500}}
local completeTooltip=UI:BuildRaidTooltipRows({raid=latestSnapshot.bestRaid,raidRows=completeRaidRows});assert(#completeTooltip==8 and completeTooltip[1].cells[1]=="Zeta"and completeTooltip[2].cells[1]=="Alpha"and completeTooltip[1].cells[2]=="H"and completeTooltip[1].cells[3]==1 and completeTooltip[2].cells[2]=="N"and completeTooltip[2].cells[3]==6,"dashboard tooltip retains all catalog bosses and their ordered per-boss Best")
assert(completeTooltip[7].cells[2]:find("–",1,true)and completeTooltip[7].cells[3]:find("–",1,true)and completeTooltip[8].cells[2]:find("–",1,true),"dashboard tooltip displays unknown markers for unmapped catalog bosses")
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
for _,key in ipairs({"DASHBOARD_PROFILE_TITLE","DASHBOARD_BIRTHDAY","DASHBOARD_PREFERRED_ROLE","DASHBOARD_REFRESH","DASHBOARD_RAID_TOOLTIP","DASHBOARD_VIEW_ALL","DASHBOARD_SCAN_MISSING","DASHBOARD_SCAN_STALE","DASHBOARD_SCAN_ERROR","DASHBOARD_SNAPSHOT_DIRTY","DASHBOARD_SNAPSHOT_REFRESHING","DASHBOARD_CLICK_TO_SCAN"})do assert(en:find('L["'..key..'"]',1,true)and de:find('L["'..key..'"]',1,true),"both locales include "..key)end
assert(en:find('L["DASHBOARD_SCAN_MISSING"] = "Scan to retrieve data"',1,true)and en:find('L["DASHBOARD_SCAN_STALE"] = "Please rescan for current data"',1,true)and de:find('L["DASHBOARD_SCAN_MISSING"] = "Scannen, um Daten zu erhalten"',1,true)and de:find('L["DASHBOARD_SCAN_STALE"] = "Bitte neu scannen f\\195\\188r aktuelle Daten"',1,true),"missing and stale card prompts match the requested English and German copy")
assert(source:find("function UI:BuildHomeDashboard",1,true)and source:find("function UI:LayoutDashboard",1,true)and source:find("function UI:RefreshDashboardProviders",1,true),"native dashboard construction, resize layout and provider refresh are connected")

print("Interactive responsive dashboard model, optional providers, reflow, lifetime raid tooltip, navigation and refresh tests passed")
