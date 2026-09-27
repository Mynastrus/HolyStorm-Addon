local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_UI")
local raidLocale=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_CharacterUI")
local UI=HolyStorm:GetModule("UI",true)
local unpack=unpack or table.unpack
local PANEL_TEXTURE="Interface\\FrameGeneral\\UI-Background-Rock"
local BORDER_TEXTURE="Interface\\Tooltips\\UI-Tooltip-Border"
local WHITE_TEXTURE="Interface\\Buttons\\WHITE8x8"
local CLASS_TEXTURE="Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local CLASS_FALLBACK="Interface\\Icons\\INV_Misc_QuestionMark"
local ROLE_COORDS={TANK={0,19/64,22/64,41/64},HEALER={20/64,39/64,1/64,20/64},DAMAGER={20/64,39/64,22/64,41/64}}
local RAID_SHORT={LFR="LFR",NORMAL="N",HEROIC="H",MYTHIC="M"}
local ROLE_KEYS={TANK="DASHBOARD_ROLE_TANK",HEALER="DASHBOARD_ROLE_HEALER",MELEE="DASHBOARD_ROLE_MELEE",MELEE_DPS="DASHBOARD_ROLE_MELEE",RANGED="DASHBOARD_ROLE_RANGED",RANGED_DPS="DASHBOARD_ROLE_RANGED",DAMAGER="DASHBOARD_ROLE_DAMAGER"}
local function text(value)return type(value)=="string"and value~=""and value or nil end
local function colorText(value,r,g,b)return string.format("|cff%02x%02x%02x%s|r",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5),tostring(value or""))end
local function styleDashboardHeading(region)
 region:SetFontObject(GameFontNormal);region:SetTextColor(1,.78,.18,1);region:SetAlpha(1)
end
local function styleDashboardBody(region)
 region:SetFontObject(GameFontHighlightSmall);region:SetTextColor(.92,.95,1,1);region:SetAlpha(1)
end
local function unknown()local components=HolyStorm.UIComponents;return components and components.FormatState and components:FormatState(nil)or"|cff888888\226\128\147|r"end
local function numberText(value)
 value=tonumber(value);if not value then return unknown()end
 return value%1==0 and tostring(value)or string.format("%.1f",value)
end
local function panel(parent)
 local frame=CreateFrame("Frame",nil,parent,"BackdropTemplate")
 frame:SetBackdrop({bgFile=PANEL_TEXTURE,edgeFile=BORDER_TEXTURE,tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 frame:SetBackdropColor(.035,.045,.06,.96);frame:SetBackdropBorderColor(.42,.32,.12,.88)
 return frame
end
local function buttonPanel(parent)
 local frame=CreateFrame("Button",nil,parent,"BackdropTemplate")
 frame:RegisterForClicks("LeftButtonUp","RightButtonUp")
 frame:SetBackdrop({bgFile=PANEL_TEXTURE,edgeFile=BORDER_TEXTURE,tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
 frame:SetBackdropColor(.025,.035,.05,.96);frame:SetBackdropBorderColor(.36,.31,.21,.95)
 frame.hover=frame:CreateTexture(nil,"HIGHLIGHT");frame.hover:SetAllPoints();frame.hover:SetTexture(WHITE_TEXTURE);frame.hover:SetVertexColor(1,.72,.13,.12);frame.hover:SetBlendMode("ADD")
 frame:SetScript("OnEnter",function(self)self:SetBackdropBorderColor(1,.78,.25,1);if self.tooltip then self:tooltip()end end)
 frame:SetScript("OnLeave",function(self)self:SetBackdropBorderColor(.36,.31,.21,.95);if GameTooltip then GameTooltip:Hide()end;local tooltips=HolyStorm.Tooltips;if tooltips then tooltips:Release("raid-best")end end)
 return frame
end
local function setTexture(texture,value)
 if not texture then return end
 local ok=pcall(texture.SetTexture,texture,value or CLASS_FALLBACK);if not ok then texture:SetTexture(CLASS_FALLBACK)end
end
local function openProfile()
 local profiles=HolyStorm:GetModule("Profiles",true)
 if not profiles or not HolyStorm.UI then return false end
 profiles.selected=UnitGUID and UnitGUID("player")or profiles.selected
 return HolyStorm.UI:ShowPage("profiles")~=false
end

function UI:RegisterDashboardProvider(id,definition)
 if type(id)~="string"or id==""or(type(definition)~="table"and type(definition)~="function")then return false,"INVALID_DASHBOARD_PROVIDER"end
 if type(definition)=="function"then definition={owner=id,title=id,order=100,getItems=definition}else definition.owner=definition.owner or id end
 self.dashboardProviders=self.dashboardProviders or{};self.dashboardProviders[id]=definition
 if HolyStorm.Events then HolyStorm.Events:Emit("HS_UI_DASHBOARD_PROVIDER_CHANGED",id,"REGISTERED",definition.owner)end
 if self.dashboardCanvas then self:RefreshDashboardProviders()end
 return true
end
function UI:UnregisterDashboardProvider(id)
 local definition=self.dashboardProviders and self.dashboardProviders[id];if not definition then return false end
 self.dashboardProviders[id]=nil;if HolyStorm.Events then HolyStorm.Events:Emit("HS_UI_DASHBOARD_PROVIDER_CHANGED",id,"UNREGISTERED",definition.owner)end
 self:RefreshDashboardProviders();return true
end
function UI:UnregisterDashboardProviderOwner(owner)
 local ids={};for id,definition in pairs(self.dashboardProviders or{})do if definition.owner==owner then ids[#ids+1]=id end end;table.sort(ids)
 for _,id in ipairs(ids)do self:UnregisterDashboardProvider(id)end;return#ids
end
function UI:OpenCharacterTab(tabId)
 local characterUI=HolyStorm.CharacterUI;local guid=UnitGUID and UnitGUID("player");if not characterUI or not guid or type(tabId)~="string"then return false end
 return characterUI:OpenCharacter(guid,tabId)
end
function UI:OpenProfileSettings()return openProfile()end

function UI:BuildDashboardModel()
 local characterUI=HolyStorm.CharacterUI;local guid=UnitGUID and UnitGUID("player");local summary=characterUI and characterUI.GetDashboardSummary and characterUI:GetDashboardSummary(guid)
 local context=characterUI and characterUI.ResolveContext and guid and characterUI:ResolveContext(guid)
 local account,profile={},{}
 local playerStore=HolyStorm.Data and HolyStorm.Data.PlayerStore
 if playerStore and playerStore.GetLocalPlayerId and playerStore.Get then local ok,result=pcall(playerStore.Get,playerStore,playerStore:GetLocalPlayerId());if ok and type(result)=="table"then account=type(result.metadata)=="table"and result.metadata or{}end end
 if context and type(context.record)=="table"and type(context.record.profile)=="table"then profile=context.record.profile end
 local best=summary and summary.bestRaid;local raidValue=unknown();local raidSubtitle=""
 if best and RAID_SHORT[best.difficulty]and tonumber(best.killed)and tonumber(best.total)then
  local difficulty=raidLocale["RAID_DIFFICULTY_"..best.difficulty]or best.difficulty
  raidValue=string.format("%s %d/%d",difficulty,best.killed,best.total);raidSubtitle=text(best.raidName)or""
  if characterUI.ColorDifficulty then raidValue=characterUI:ColorDifficulty(best.difficulty,raidValue)end
 end
 local equipment=summary and summary.equipment;local equipped=0
 for _,item in pairs(type(equipment)=="table"and type(equipment.slots)=="table"and equipment.slots or{})do if type(item)=="table"then equipped=equipped+1 end end
 -- C_MythicPlus.GetCurrentSeason exposes Blizzard's internal season ID, not a stable display number.
 local mythicSubtitle=L["DASHBOARD_MYTHIC_CURRENT"]
 local delve=summary and summary.delves;local delveValue=unknown();local delveSubtitle=""
 if type(delve)=="table"then
  local progress=delve.weeklyProgress
  if type(progress)=="table"then progress=progress.value or progress.count or progress.progress or progress.level end
  if type(progress)=="number"or type(progress)=="string"then delveValue=tostring(progress)
  elseif tonumber(delve.seasonNumber)then delveValue=string.format(L["DASHBOARD_SEASON"],tonumber(delve.seasonNumber))end
  local activityCount=type(delve.activities)=="table"and#delve.activities or 0
  if activityCount>0 then delveSubtitle=string.format(L["DASHBOARD_DELVE_ACTIVITIES"],activityCount)elseif delve.weeklyRewardAvailable==true then delveSubtitle=L["DASHBOARD_DELVE_REWARD"]end
 end
 local achievementValue=unknown();local achievementSubtitle=L["DASHBOARD_ACHIEVEMENTS"]
 local achievementService=HolyStorm.Achievements
 local achievementModule=HolyStorm:GetModule("AchievementsUI",true);local achievementAvailable=achievementService and achievementService.GetDefinitions and achievementService.IsEarned and achievementModule and achievementModule.IsEnabled and achievementModule:IsEnabled()and characterUI and characterUI.GetTab and characterUI:GetTab("achievements")~=nil
 if achievementAvailable then
  local definitions=achievementService:GetDefinitions(false,guid);local earned=0
  for _,definition in ipairs(definitions or{})do if achievementService:IsEarned(definition.achievementID,guid)then earned=earned+1 end end
  achievementValue=#(definitions or{})==0 and "0" or string.format(L["DASHBOARD_ACHIEVEMENTS_COUNT"],earned,#(definitions or{}));achievementSubtitle=#(definitions or{})==0 and L["DASHBOARD_ACHIEVEMENTS_NONE"] or L["DASHBOARD_ACHIEVEMENTS_EARNED"]
 end
 local stats=summary and summary.stats;local statsCount=0
 if type(stats)=="table"then
  for _,value in pairs(type(stats.primary)=="table"and stats.primary or{})do if type(value)=="table"and tonumber(value.effective)then statsCount=statsCount+1 end end
  for _,value in pairs(type(stats.secondary)=="table"and stats.secondary or{})do if type(value)=="table"and(tonumber(value.rating)or tonumber(value.percent))then statsCount=statsCount+1 end end
 end
 local twinksCount
 if context and context.accountUUID and HolyStorm.TwinkCore and HolyStorm.TwinkCore.GetVisibleCharactersForViewer then local list=HolyStorm.TwinkCore:GetVisibleCharactersForViewer(context.accountUUID,context.guild);twinksCount=math.max(0,#(list or{})-1)end
 local birthday=text(account.birthdate);local displayName=text(account.displayName);local preferredRole=text(profile.preferredRole)
 local profileRows={}
 if displayName then profileRows[#profileRows+1]={kind="name",text=displayName}end
 if birthday then profileRows[#profileRows+1]={kind="birthday",text=string.format(L["DASHBOARD_BIRTHDAY"],birthday)}end
 if preferredRole then local roleCode=string.upper(preferredRole:gsub("[%s%-]","_"));local roleKey=ROLE_KEYS[roleCode];local roleText=roleKey and L[roleKey]or preferredRole;profileRows[#profileRows+1]={kind="role",text=string.format(L["DASHBOARD_PREFERRED_ROLE"],roleText),role=ROLE_COORDS[roleCode]or((roleCode=="MELEE_DPS"or roleCode=="RANGED_DPS")and ROLE_COORDS.DAMAGER or nil)}end
 return{
  summary=summary,context=context,guid=guid,name=summary and(summary.coloredName or summary.name)or unknown(),specification=summary and summary.specName and summary.className and string.format(L["DASHBOARD_SPEC_CLASS"],summary.specName,summary.className)or(summary and(summary.specName or summary.className)or unknown()),specIcon=summary and summary.specIcon,classFile=summary and summary.classFile,level=summary and summary.level,realm=summary and summary.realm,guildRank=summary and summary.guildRank,
  profileRows=profileRows,profileAvailable=#profileRows>0,itemLevel=numberText(summary and summary.itemLevel),itemLevelRaw=summary and summary.itemLevel,equippedCount=equipped,mythicPlusRating=numberText(summary and summary.mythicPlusRating),mythicPlusRaw=summary and summary.mythicPlusRating,mythicPlusSubtitle=mythicSubtitle,raid=best,raidValue=raidValue,raidSubtitle=raidSubtitle,raidRows=summary and summary.bestRaidRows,
  delvesValue=delveValue,delvesSubtitle=delveSubtitle,achievementsAvailable=not not achievementAvailable,achievementValue=achievementValue,achievementSubtitle=achievementSubtitle,statsValue=statsCount>0 and tostring(statsCount)or unknown(),statsSubtitle=L["DASHBOARD_STATS_TRACKED"],twinksValue=twinksCount~=nil and tostring(twinksCount)or unknown(),twinksSubtitle=L["DASHBOARD_MORE_CHARACTERS"],
  lastUpdatedAt=summary and summary.lastUpdatedAt,
 }
end

function UI:CalculateDashboardProviderLayout(count,width,providers)
 count=math.max(0,tonumber(count)or 0);width=math.max(0,tonumber(width)or 0);if count==0 then return{},0,0 end
 local columns=count==1 and 1 or 2;local gap=8;local cardWidth=math.max(1,(width-gap*(columns-1))/columns);local layout={};local rowHeights={}
 for index=1,math.min(count,3)do
  local row=math.floor((index-1)/columns)+1;local height=self:CalculateDashboardWidgetHeight({(providers or{})[index]},184)
  rowHeights[row]=math.max(rowHeights[row]or 0,height)
  layout[index]={x=((index-1)%columns)*(cardWidth+gap),width=cardWidth,column=((index-1)%columns)+1,row=row}
 end
 local y=0;for row=1,#rowHeights do for index=1,math.min(count,3)do if layout[index].row==row then layout[index].y=y;layout[index].height=rowHeights[row]end end;y=y+rowHeights[row]+gap end
 return layout,columns,math.max(0,y-gap)
end
function UI:CalculateDashboardProfileHeight(rowCount)
 return 34+math.max(0,tonumber(rowCount)or 0)*17
end
function UI:CalculateDashboardProfileWidth(width)
 width=math.max(1,tonumber(width)or 900)
 return math.min(310,math.max(280,width*.32))
end
function UI:CalculateDashboardWidgetHeight(providers,availableHeight)
 local count=math.min(3,#(providers or{}));if count==0 then return 0 end
 local columns=count==1 and 1 or 2;local rows={}
 for index=1,count do local height=36;local provider=providers[index]
  for itemIndex=1,math.min(4,#(provider.items or{}))do height=height+(text(provider.items[itemIndex].summary)and 34 or 26)end
  local row=math.floor((index-1)/columns)+1;rows[row]=math.max(rows[row]or 0,height)
 end
 local required=math.max(0,#rows-1)*8;for _,height in ipairs(rows)do required=required+height end
 return math.min(math.max(0,tonumber(availableHeight)or 1000000),required)
end
function UI:CalculateDashboardLayout(width,height)
 width=math.max(1,tonumber(width)or 1);height=math.max(380,tonumber(height)or 440)
 local margin,gap=7,7;local available=width-margin*2
 local widgetTop,widgetBottom=306,math.max(350,height-margin)
 return{width=width,height=height,margin=margin,gap=gap,headerTop=margin,headerHeight=86,navTop=100,navHeight=28,primaryTop=137,primaryHeight=94,secondaryTop=239,secondaryHeight=62,widgetTop=widgetTop,widgetBottom=widgetBottom,widgetHeight=math.min(184,widgetBottom-widgetTop),navButtonWidth=math.max(1,(available-4*7)/8)}
end

local function makeMetricCard(parent,kind)
 local frame=buttonPanel(parent);frame.kind=kind
 frame.icon=frame:CreateTexture(nil,"ARTWORK");frame.icon:SetSize(46,46);frame.icon:SetPoint("LEFT",frame,"LEFT",12,0);frame.icon:SetTexCoord(.08,.92,.08,.92)
 frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal");frame.title:SetPoint("TOPLEFT",frame,"TOPLEFT",73,-13);styleDashboardHeading(frame.title);frame.title:SetJustifyH("LEFT")
 frame.value=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge");frame.value:SetPoint("TOPLEFT",frame.title,"BOTTOMLEFT",0,-1);frame.value:SetPoint("RIGHT",frame,"RIGHT",-29,0);frame.value:SetJustifyH("LEFT");frame.value:SetWordWrap(false)
 frame.subtitle=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");frame.subtitle:SetPoint("BOTTOMLEFT",frame,"BOTTOMLEFT",73,10);frame.subtitle:SetPoint("RIGHT",frame,"RIGHT",-12,0);frame.subtitle:SetJustifyH("LEFT");frame.subtitle:SetWordWrap(false);frame.subtitle:SetTextColor(.72,.78,.86)
 frame.arrow=frame:CreateFontString(nil,"OVERLAY","GameFontHighlight");frame.arrow:SetPoint("RIGHT",frame,"RIGHT",-9,0);frame.arrow:SetText("›");frame.arrow:SetTextColor(.9,.68,.2)
 frame:SetScript("OnClick",function(self,button)if button=="RightButton"then if self.settings then self.settings()end;return end;if self.action then self.action()end end)
 return frame
end

local function profileTooltip(owner,model)
 if not GameTooltip then return end
 GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(colorText(L["DASHBOARD_PROFILE_TITLE"],1,.78,.18))
 for _,row in ipairs(model.profileRows or{})do GameTooltip:AddLine(row.text,.9,.95,1,true)end
 GameTooltip:AddLine(L["DASHBOARD_PROFILE_TOOLTIP"],.75,.82,.92,true);GameTooltip:Show()
end

local function createWidget(parent)
 local frame=panel(parent);frame.entries={}
 frame.title=frame:CreateFontString(nil,"OVERLAY","GameFontNormal");frame.title:SetPoint("TOPLEFT",frame,"TOPLEFT",38,-9);styleDashboardHeading(frame.title)
 frame.icon=frame:CreateTexture(nil,"ARTWORK");frame.icon:SetSize(20,20);frame.icon:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-7)
 frame.more=CreateFrame("Button",nil,frame);frame.more:SetSize(84,20);frame.more:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-10,-7)
 frame.more.text=frame.more:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");frame.more.text:SetPoint("RIGHT");frame.more.text:SetTextColor(.25,.78,.92);frame.more.text:SetText(L["DASHBOARD_VIEW_ALL"])
 frame.more:SetScript("OnEnter",function(owner)owner.text:SetTextColor(1,.82,.25)end);frame.more:SetScript("OnLeave",function(owner)owner.text:SetTextColor(.25,.78,.92)end)
 return frame
end

function UI:RebuildDashboardNavigation()
 if not self.navFrame then return false end
 local previous=self.navButtons or{};local buttons={};local tabs=HolyStorm.CharacterUI and HolyStorm.CharacterUI.GetTabs and HolyStorm.CharacterUI:GetTabs()or{}
 local locale=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_CharacterUI")
 for index,definition in ipairs(tabs)do
  local button=previous[index]
  if not button then
   button=CreateFrame("Button",nil,self.navFrame,"BackdropTemplate");button:RegisterForClicks("LeftButtonUp");button:SetBackdrop({bgFile=PANEL_TEXTURE,edgeFile=BORDER_TEXTURE,tile=true,tileSize=16,edgeSize=10,insets={left=2,right=2,top=2,bottom=2}});button:SetBackdropColor(.025,.035,.05,.96);button:SetBackdropBorderColor(.34,.30,.22,.9)
   button.icon=button:CreateTexture(nil,"ARTWORK");button.icon:SetSize(21,21)
   button.label=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");button.label:SetJustifyH("CENTER")
   button:SetScript("OnClick",function(self)UI:OpenCharacterTab(self.definition.id)end)
   button:SetScript("OnEnter",function(self)self:SetBackdropBorderColor(1,.78,.25,1);if GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText(self.label:GetText());GameTooltip:AddLine(L["DASHBOARD_OPEN_CHARACTER_TAB"],.85,.88,.94,true);GameTooltip:Show()end end)
   button:SetScript("OnLeave",function(self)self:SetBackdropBorderColor(.34,.30,.22,.9);if GameTooltip then GameTooltip:Hide()end end)
  end
  local achievementModule=definition.id=="achievements"and HolyStorm:GetModule("AchievementsUI",true)or nil
  if definition.id~="achievements"or(achievementModule and achievementModule.IsEnabled and achievementModule:IsEnabled())then button.definition=definition;setTexture(button.icon,definition.icon);button.label:SetText(definition.label or(definition.labelKey and locale[definition.labelKey])or definition.id);button:Show();buttons[#buttons+1]=button else button:Hide()end
 end
 for index=#tabs+1,#previous do previous[index]:Hide()end
 self.navButtons=buttons;self:LayoutDashboard();return true
end

function UI:BuildHomeDashboard(parent,widgets)
 local canvas=CreateFrame("Frame",nil,parent);canvas:SetAllPoints(parent);self.dashboardCanvas=canvas;self.dashboardWidgets=widgets;self.providerWidgets={}
 local header=panel(canvas);self.headerPanel=header
 local headerContent=CreateFrame("Frame",nil,canvas);self.headerContent=headerContent
 local profile=CreateFrame("Button",nil,canvas,"BackdropTemplate");profile:RegisterForClicks("LeftButtonUp","RightButtonUp");profile:SetBackdrop({bgFile=PANEL_TEXTURE,edgeFile=BORDER_TEXTURE,tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}});profile:SetBackdropColor(.025,.035,.05,.95);profile:SetBackdropBorderColor(.46,.36,.16,.9);self.profilePanel=profile
 profile.title=profile:CreateFontString(nil,"OVERLAY","GameFontNormal");profile.title:SetPoint("TOPLEFT",profile,"TOPLEFT",12,-9);styleDashboardHeading(profile.title)
 profile.rows={}
 profile:SetScript("OnClick",function(_,button)if button=="RightButton"or button=="LeftButton"then UI:OpenProfileSettings()end end)
 profile:SetScript("OnEnter",function(owner)owner:SetBackdropBorderColor(1,.78,.25,1);profileTooltip(owner,self.dashboardModel or{})end)
 profile:SetScript("OnLeave",function(owner)owner:SetBackdropBorderColor(.46,.36,.16,.9);if GameTooltip then GameTooltip:Hide()end end)
 self.navFrame=CreateFrame("Frame",nil,canvas);self.navButtons={}
 self.primaryCards={
  equipment=makeMetricCard(canvas,"equipment"),mythicPlus=makeMetricCard(canvas,"mythicPlus"),raid=makeMetricCard(canvas,"raid"),
 }
 self.secondaryCards={
  delves=makeMetricCard(canvas,"delves"),achievements=makeMetricCard(canvas,"achievements"),stats=makeMetricCard(canvas,"stats"),twinks=makeMetricCard(canvas,"twinks"),
 }
 self.widgetFrames={}
 self:RebuildDashboardNavigation()
local function action(tab)return function()UI:OpenCharacterTab(tab)end end
 local cards=self.primaryCards
 cards.equipment.icon:SetTexture("Interface\\Icons\\INV_Helmet_08");cards.equipment.title:SetText(L["DASHBOARD_ITEM_LEVEL"]);cards.equipment.action=action("equipment")
 cards.mythicPlus.icon:SetTexture("Interface\\Icons\\Achievement_ChallengeMode_Gold");cards.mythicPlus.title:SetText(L["DASHBOARD_MYTHICPLUS_RATING"]);cards.mythicPlus.action=action("mythicPlus")
 cards.raid.icon:SetTexture("Interface\\Icons\\INV_Sword_27");cards.raid.title:SetText(L["DASHBOARD_BEST_RAID"]);cards.raid.action=action("raid")
 self.secondaryCards.delves.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01");self.secondaryCards.delves.title:SetText(L["DASHBOARD_DELVES"]);self.secondaryCards.delves.action=action("delves")
 self.secondaryCards.achievements.icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend");self.secondaryCards.achievements.title:SetText(L["DASHBOARD_ACHIEVEMENTS"]);self.secondaryCards.achievements.action=action("achievements")
 self.secondaryCards.stats.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_03");self.secondaryCards.stats.title:SetText(L["DASHBOARD_STATS"]);self.secondaryCards.stats.action=action("stats")
 self.secondaryCards.twinks.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking");self.secondaryCards.twinks.title:SetText(L["DASHBOARD_TWINKS"]);self.secondaryCards.twinks.action=action("twinks")
 for _,card in pairs(cards)do local current=card;current.tooltip=function()self:ShowMetricTooltip(current.kind,current)end end
 for _,card in pairs(self.secondaryCards)do local current=card;current.tooltip=function()self:ShowSecondaryTooltip(current.kind,current)end end
 self:LayoutDashboard();self:RefreshDashboardProviders();return true
end

function UI:LayoutDashboard()
 local canvas=self.dashboardCanvas;if not canvas then return end
 local width=math.max(1,canvas:GetWidth()or 1);local height=math.max(380,canvas:GetHeight()or 440);local layout=self:CalculateDashboardLayout(width,height);local margin,gap=layout.margin,layout.gap
 local header=self.headerPanel;header:ClearAllPoints();header:SetPoint("TOPLEFT",canvas,"TOPLEFT",margin,-layout.headerTop);header:SetPoint("TOPRIGHT",canvas,"TOPRIGHT",-margin,-layout.headerTop);header:SetHeight(layout.headerHeight)
 local headerContent=self.headerContent;headerContent:ClearAllPoints();headerContent:SetPoint("TOPLEFT",header,"TOPLEFT",5,-4);headerContent:SetPoint("BOTTOMRIGHT",header,"BOTTOMRIGHT",-5,4)
 local profile=self.profilePanel;local profileAvailable=self.dashboardModel and self.dashboardModel.profileAvailable==true
 profile:SetShown(profileAvailable);if profileAvailable then
  profile:ClearAllPoints();profile:SetWidth(self:CalculateDashboardProfileWidth(width))
  profile:SetHeight(self:CalculateDashboardProfileHeight(#self.dashboardModel.profileRows));profile:SetClipsChildren(true)
  profile:SetPoint("TOPRIGHT",headerContent,"TOPRIGHT",-2,-(headerContent:GetHeight()-profile:GetHeight())/2)
 end
 local identity=self.dashboardWidgets.identity;identity.frame:SetParent(headerContent);identity.frame:ClearAllPoints();identity.frame:SetPoint("TOPLEFT",headerContent,"TOPLEFT",0,0);if profileAvailable then identity.frame:SetPoint("BOTTOMRIGHT",profile,"BOTTOMLEFT",-8,0)else identity.frame:SetPoint("BOTTOMRIGHT",headerContent,"BOTTOMRIGHT",-4,0)end;identity.frame:Show()
 local classIcon=self.dashboardWidgets.classIcon;classIcon.frame:ClearAllPoints();classIcon.frame:SetParent(identity.frame);classIcon.frame:SetSize(68,68);classIcon.frame:SetPoint("LEFT",identity.frame,"LEFT",3,0);classIcon.frame:Show();classIcon.image:ClearAllPoints();classIcon.image:SetSize(62,62);classIcon.image:SetPoint("CENTER",classIcon.frame,"CENTER")
 local specIcon=self.dashboardWidgets.specIcon;specIcon.frame:ClearAllPoints();specIcon.frame:SetParent(identity.frame);specIcon.frame:SetSize(52,52);specIcon.frame:SetPoint("LEFT",classIcon.frame,"RIGHT",8,0);specIcon.frame:Show();specIcon.image:ClearAllPoints();specIcon.image:SetSize(46,46);specIcon.image:SetPoint("CENTER",specIcon.frame,"CENTER")
 local identityText=self.dashboardWidgets.identityText;identityText.frame:SetParent(identity.frame);identityText.frame:ClearAllPoints();identityText.frame:SetPoint("TOPLEFT",specIcon.frame,"TOPRIGHT",8,-3);identityText.frame:SetPoint("BOTTOMRIGHT",identity.frame,"BOTTOMRIGHT",-4,3);identityText.frame:SetHeight(68);identityText:SetWidth(math.max(120,identity.frame:GetWidth()-150));identityText.frame:Show()
 local name=self.dashboardWidgets.name;name:SetFontObject(GameFontHighlightLarge);name:SetJustifyH("LEFT")
 local spec=self.dashboardWidgets.specialization;spec:SetFontObject(GameFontHighlight);spec:SetJustifyH("LEFT")
 local nav= self.navFrame;nav:ClearAllPoints();nav:SetPoint("TOPLEFT",canvas,"TOPLEFT",margin,-layout.navTop);nav:SetPoint("TOPRIGHT",canvas,"TOPRIGHT",-margin,-layout.navTop);nav:SetHeight(layout.navHeight)
 local navWidth=math.max(1,width-2*margin);local navGap=4;local itemWidth=math.max(1,(navWidth-navGap*math.max(0,#self.navButtons-1))/math.max(1,#self.navButtons))
 for index,button in ipairs(self.navButtons)do button:ClearAllPoints();button:SetPoint("TOPLEFT",nav,"TOPLEFT",(index-1)*(itemWidth+navGap),0);button:SetSize(itemWidth,29);if itemWidth>=89 then button.label:Show()else button.label:Hide()end;button.icon:SetPoint("LEFT",button,itemWidth>=89 and"LEFT"or"CENTER",itemWidth>=89 and 7 or 0,0);button.label:ClearAllPoints();button.label:SetPoint("LEFT",button.icon,"RIGHT",5,0);button.label:SetPoint("RIGHT",button,"RIGHT",-5,0)end
 local primaryTop=layout.primaryTop;local primaryHeight=layout.primaryHeight;local primaryWidth=(width-2*margin-2*gap)/3
 local order={self.primaryCards.equipment,self.primaryCards.mythicPlus,self.primaryCards.raid}
 for index,card in ipairs(order)do card:ClearAllPoints();card:SetPoint("TOPLEFT",canvas,"TOPLEFT",margin+(index-1)*(primaryWidth+gap),-primaryTop);card:SetSize(primaryWidth,primaryHeight)end
 local secondaryTop=layout.secondaryTop;local secondaryHeight=layout.secondaryHeight;local secondary={self.secondaryCards.delves,self.secondaryCards.achievements,self.secondaryCards.stats,self.secondaryCards.twinks};local shown={}
 if not self.dashboardModel or self.dashboardModel.achievementsAvailable then shown[#shown+1]=self.secondaryCards.achievements end
 shown[#shown+1]=self.secondaryCards.delves;shown[#shown+1]=self.secondaryCards.stats;shown[#shown+1]=self.secondaryCards.twinks
 local secondaryWidth=(width-2*margin-gap*math.max(0,#shown-1))/math.max(1,#shown)
 for index,card in ipairs(secondary)do
  local visible=false;for _,entry in ipairs(shown)do if entry==card then visible=true;break end end
  card:SetShown(visible)
 end
 for index,card in ipairs(shown)do
  card:ClearAllPoints();card:SetPoint("TOPLEFT",canvas,"TOPLEFT",margin+(index-1)*(secondaryWidth+gap),-secondaryTop);card:SetSize(secondaryWidth,secondaryHeight)
  card.icon:SetSize(36,36);card.icon:ClearAllPoints();card.icon:SetPoint("LEFT",card,"LEFT",8,0)
  card.title:ClearAllPoints();card.title:SetPoint("TOPLEFT",card,"TOPLEFT",52,-6);card.title:SetPoint("RIGHT",card,"RIGHT",-10,0)
  card.value:ClearAllPoints();card.value:SetFontObject(GameFontHighlight);card.value:SetPoint("TOPLEFT",card.title,"BOTTOMLEFT",0,-1);card.value:SetPoint("RIGHT",card,"RIGHT",-10,0)
  card.subtitle:ClearAllPoints();card.subtitle:SetPoint("BOTTOMLEFT",card,"BOTTOMLEFT",52,5);card.subtitle:SetPoint("RIGHT",card,"RIGHT",-10,0)
 end
 local widgetTop=layout.widgetTop;local providerLayouts,providerColumns,widgetHeight=self:CalculateDashboardProviderLayout(#(self.visibleDashboardProviders or{}),width-2*margin,self.visibleDashboardProviders)
 for index,provider in ipairs(self.visibleDashboardProviders or{})do
  local frame=self.widgetFrames[index];local slot=providerLayouts[index]
  if frame and slot and index<=3 then frame:ClearAllPoints();frame:SetPoint("TOPLEFT",canvas,"TOPLEFT",margin+slot.x,-(widgetTop+slot.y));frame:SetSize(slot.width,slot.height);frame:Show();self:LayoutProviderWidget(frame,provider,slot.height)
  elseif frame then frame:Hide()end
 end
 for index=#(self.visibleDashboardProviders or{})+1,#self.widgetFrames do self.widgetFrames[index]:Hide()end
 layout.primaryHeight=primaryHeight;layout.secondaryHeight=secondaryHeight;layout.widgetHeight=widgetHeight;layout.providerColumns=providerColumns;self.dashboardLayout=layout
end

function UI:UpdateProfilePanel(model)
 local frame=self.profilePanel;frame:SetAlpha(1);frame.title:SetText(L["DASHBOARD_PROFILE_TITLE"]);styleDashboardHeading(frame.title);frame.title:ClearAllPoints();frame.title:SetPoint("TOPLEFT",frame,"TOPLEFT",12,-8)
 for _,row in ipairs(frame.rows)do row.icon:Hide();row.text:Hide()end
 local rows=model.profileRows or{}
 for index,value in ipairs(rows)do
  local row=frame.rows[index]
  if not row then row={icon=frame:CreateTexture(nil,"ARTWORK"),text=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")};row.icon:SetSize(17,17);frame.rows[index]=row end
  row.icon:ClearAllPoints();row.icon:SetPoint("LEFT",frame,"LEFT",12,-(25+(index-1)*17));row.text:ClearAllPoints();row.text:SetPoint("LEFT",row.icon,"RIGHT",6,0);row.text:SetPoint("RIGHT",frame,"RIGHT",-10,0);row.text:SetJustifyH("LEFT");row.text:SetWordWrap(false);row.text:SetText(value.text);styleDashboardBody(row.text)
  if value.role then row.icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES");row.icon:SetTexCoord(unpack(value.role))elseif value.kind=="birthday"then row.icon:SetTexture("Interface\\Calendar\\UI-Calendar-Event-PVP");row.icon:SetTexCoord(0,1,0,1)elseif value.kind=="name"then row.icon:SetTexture("Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon");row.icon:SetTexCoord(0,1,0,1)else row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark");row.icon:SetTexCoord(0,1,0,1)end
  row.icon:SetAlpha(1);row.icon:Show();row.text:Show()
 end
 for index=#rows+1,#frame.rows do frame.rows[index].icon:Hide();frame.rows[index].text:Hide()end
end

function UI:BuildDynamicProviderItems()
 local visible={};local providers={}
 for id,definition in pairs(self.dashboardProviders or{})do providers[#providers+1]={id=id,definition=definition}end
 table.sort(providers,function(a,b)local x,y=tonumber(a.definition.order)or 100,tonumber(b.definition.order)or 100;if x==y then return a.id<b.id end;return x<y end)
 local context=self.dashboardModel and self.dashboardModel.context
 for _,entry in ipairs(providers)do
  local definition=entry.definition;local available=true
  if type(definition.available)=="function"then local ok,value=HolyStorm.Utils.SafeCall("ui.dashboard.available:"..entry.id,definition.available,context);available=ok and value~=false else
   local owner=definition.moduleName or definition.owner
   if owner and HolyStorm.IsOptionalModuleEnabled and definition.optional==true then available=HolyStorm:IsOptionalModuleEnabled(owner)end
  end
  if available and type(definition.getItems)=="function"then
   local ok,items=HolyStorm.Utils.SafeCall("ui.dashboard.provider:"..entry.id,definition.getItems,context,definition)
   if ok and type(items)=="table"and#items>0 then local clean={};for _,item in ipairs(items)do if type(item)=="table"and text(item.title)then clean[#clean+1]=item end end;if#clean>0 then visible[#visible+1]={id=entry.id,definition=definition,items=clean}end end
  end
 end
 return visible
end

function UI:LayoutProviderWidget(frame,provider,height)
 frame.title:SetText(provider.definition.title or provider.id);frame.icon:SetTexture(provider.definition.icon or"Interface\\Icons\\INV_Misc_Note_05");frame.more.text:SetText(provider.definition.moreLabel or L["DASHBOARD_VIEW_ALL"]);frame.more:SetShown(type(provider.definition.moreAction)=="function");frame.more:SetScript("OnClick",function()provider.definition.moreAction()end)
 frame.title:ClearAllPoints();frame.title:SetPoint("TOPLEFT",frame,"TOPLEFT",38,-9);frame.title:SetPoint("RIGHT",frame.more,"LEFT",-5,0);styleDashboardHeading(frame.title)
 local rows=math.min(4,#provider.items);local rowHeight=math.max(26,math.min(31,(height-32)/math.max(1,rows)))
 for index=1,rows do
  local item=provider.items[index];local row=frame.entries[index]
  if not row then
   row=CreateFrame("Button",nil,frame);row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(26,26);row.icon:SetPoint("LEFT",row,"LEFT",2,0);row.title=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.title:SetPoint("TOPLEFT",row.icon,"TOPRIGHT",7,-1);row.title:SetPoint("RIGHT",row,"RIGHT",-6,0);row.title:SetJustifyH("LEFT");row.title:SetWordWrap(false);row.summary=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.summary:SetPoint("TOPLEFT",row.title,"BOTTOMLEFT",0,-1);row.summary:SetPoint("RIGHT",row,"RIGHT",-6,0);row.summary:SetJustifyH("LEFT");row.summary:SetWordWrap(false);frame.entries[index]=row
   row:SetScript("OnEnter",function(self)self.title:SetTextColor(1,.85,.4);if self.item and self.item.tooltip and GameTooltip then GameTooltip:SetOwner(self,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(colorText(self.item.title,1,.78,.18));GameTooltip:AddLine(self.item.tooltip,.88,.9,.94,true);GameTooltip:Show()end end)
   row:SetScript("OnLeave",function(self)self.title:SetTextColor(.84,.92,1);if GameTooltip then GameTooltip:Hide()end end)
   row:SetScript("OnClick",function(self)if self.item and type(self.item.onClick)=="function"then self.item.onClick()end end)
  end
  local compactHeight=text(item.summary)and math.min(34,rowHeight)or math.min(26,rowHeight)
  row:ClearAllPoints();row:SetPoint("TOPLEFT",frame,"TOPLEFT",10,-29-(index-1)*rowHeight);row:SetPoint("TOPRIGHT",frame,"TOPRIGHT",-10,-29-(index-1)*rowHeight);row:SetHeight(compactHeight);row.icon:SetTexture(item.icon or provider.definition.icon or"Interface\\Icons\\INV_Misc_Note_05");row.title:SetText(item.title);row.title:SetTextColor(.84,.92,1);row.summary:SetText(item.summary or"");if text(item.summary)then row.summary:Show()else row.summary:Hide()end;row.item=item;row:Show()
 end
 for index=rows+1,#frame.entries do frame.entries[index]:Hide()end
end

function UI:BuildRaidTooltipRows(model)
 model=model or self.dashboardModel or{};local rows={};local C=HolyStorm.CharacterUI
 for _,boss in ipairs(model.raidRows or{})do
  if model.raid and C and C.RaidIdentityMatches and C:RaidIdentityMatches(boss,model.raid)then rows[#rows+1]={cells={boss.bossName or unknown(),RAID_SHORT[boss.difficulty]or unknown(),boss.kills or unknown()},colors={[2]=C:GetDifficultyColor(boss.difficulty)}}end
 end
 return rows
end

function UI:RefreshDashboardProviders()
 if not self.dashboardCanvas then return false end
 self.visibleDashboardProviders=self:BuildDynamicProviderItems()
 for index,provider in ipairs(self.visibleDashboardProviders)do
  local frame=self.widgetFrames[index]or createWidget(self.dashboardCanvas);self.widgetFrames[index]=frame;frame:Show()
  frame:SetScript("OnEnter",function(owner)owner:SetBackdropBorderColor(1,.78,.25,1)end);frame:SetScript("OnLeave",function(owner)owner:SetBackdropBorderColor(.42,.32,.12,.88)end)
  frame.definition=provider.definition;frame.providerId=provider.id
 end
 self:LayoutDashboard();return true
end

function UI:ShowMetricTooltip(kind,owner)
 local model=self.dashboardModel or{};if not GameTooltip then return false end
 if kind=="raid"then
  local rows=self:BuildRaidTooltipRows(model)
  local tooltips=HolyStorm.Tooltips
  if#rows>0 and tooltips then return tooltips:ShowTable("raid-best",owner,{anchor={point="LEFT",relativePoint="RIGHT",x=8,y=0},columns={{align="LEFT"},{align="CENTER"},{align="RIGHT"}},headers={{raidLocale["RAID_COLUMN_BOSS"],raidLocale["RAID_COLUMN_BEST"],raidLocale["RAID_COLUMN_KILLS"]}},separator=true,rows=rows})end
 end
 GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(colorText(self.primaryCards[kind].title:GetText(),1,.78,.18))
 if kind=="equipment"then
  GameTooltip:AddLine(string.format(L["DASHBOARD_EQUIPMENT_TOOLTIP"],model.equippedCount or 0),.9,.94,1,true)
 elseif kind=="mythicPlus"then GameTooltip:AddLine(model.mythicPlusSubtitle or"",.9,.94,1,true)
 elseif kind=="raid"then GameTooltip:AddLine(L["DASHBOARD_RAID_TOOLTIP"],.9,.94,1,true);if model.raidSubtitle~=""then GameTooltip:AddLine(model.raidSubtitle,.8,.86,.94,true)end end
 GameTooltip:AddLine(L["DASHBOARD_CLICK_TO_OPEN"],.25,.78,.92,true);GameTooltip:Show();return true
end

function UI:ShowSecondaryTooltip(kind,owner)
 local card=self.secondaryCards[kind];if not GameTooltip or not card then return false end
 GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(colorText(card.title:GetText(),1,.78,.18));GameTooltip:AddLine(L["DASHBOARD_CLICK_TO_OPEN"],.25,.78,.92,true);GameTooltip:Show();return true
end

function UI:RefreshCharacterData()
 local characterUI=HolyStorm.CharacterUI;local guid=UnitGUID and UnitGUID("player");if not characterUI or not guid then return false end
 self:SetStatusText(L["DASHBOARD_REFRESHING"]);self.refreshing=true;self.refreshButton:SetEnabled(false)
 local ok=characterUI:RequestRefresh(guid,{"identity","equipment","mythicPlus","raid","delves","stats"},"MANUAL")
 if not ok then self.refreshing=false;self.refreshButton:SetEnabled(true);self:SetReadyStatus()
 elseif not HolyStorm.Tasks or not HolyStorm.Tasks.GetTaskType or not HolyStorm.Tasks:GetTaskType("Character.Refresh")then self.refreshing=false;self.refreshButton:SetEnabled(true);self:SetReadyStatus();self:RefreshDashboard()end
 return ok
end

function UI:RefreshDashboard()
 if not self.dashboardCanvas then return false end
 local model=self:BuildDashboardModel();self.dashboardModel=model;local widgets=self.dashboardWidgets
 widgets.name:SetText(model.name);widgets.specialization:SetText(model.specification);widgets.specIcon:SetImage(model.specIcon or"Interface\\Icons\\INV_Misc_QuestionMark")
 local details={};if model.level then details[#details+1]=string.format(L["DASHBOARD_LEVEL"],model.level)end;if text(model.realm)then details[#details+1]=model.realm end;if text(model.guildRank)then details[#details+1]=string.format(L["DASHBOARD_GUILD_RANK_SHORT"],model.guildRank)end
 widgets.details:SetText(table.concat(details,"  •  "))
 if model.guid and UnitGUID and model.guid==UnitGUID("player")and SetPortraitTexture then
  local ok=pcall(SetPortraitTexture,widgets.classIcon.image,"player");if not ok then widgets.classIcon:SetImage(CLASS_FALLBACK)end
 elseif model.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[model.classFile]then local coords=CLASS_ICON_TCOORDS[model.classFile];widgets.classIcon:SetImage(CLASS_TEXTURE,unpack(coords))
 else widgets.classIcon:SetImage(CLASS_FALLBACK)end
 self:UpdateProfilePanel(model)
 local primary=self.primaryCards;primary.equipment.value:SetText(model.itemLevel);primary.equipment.subtitle:SetText(model.equippedCount>0 and string.format(L["DASHBOARD_EQUIPPED_COUNT"],model.equippedCount)or L["DASHBOARD_ITEM_LEVEL"])
 primary.mythicPlus.value:SetText(model.mythicPlusRating);primary.mythicPlus.subtitle:SetText(model.mythicPlusSubtitle or"")
 local width=self.dashboardCanvas:GetWidth()or 900;local raidValue=model.raidValue
 if width<760 and model.raid and RAID_SHORT[model.raid.difficulty]then raidValue=string.format("%s %d/%d",RAID_SHORT[model.raid.difficulty],model.raid.killed,model.raid.total);local C=HolyStorm.CharacterUI;if C and C.ColorDifficulty then raidValue=C:ColorDifficulty(model.raid.difficulty,raidValue)end end
 primary.raid.value:SetText(raidValue);primary.raid.subtitle:SetText(model.raidSubtitle or"")
 local secondary=self.secondaryCards;secondary.delves.value:SetText(model.delvesValue);secondary.delves.subtitle:SetText(model.delvesSubtitle~=""and model.delvesSubtitle or L["DASHBOARD_CURRENT_PROGRESS"])
 secondary.achievements.value:SetText(model.achievementValue);secondary.achievements.subtitle:SetText(model.achievementSubtitle)
 secondary.stats.value:SetText(model.statsValue);secondary.stats.subtitle:SetText(model.statsSubtitle)
 secondary.twinks.value:SetText(model.twinksValue);secondary.twinks.subtitle:SetText(model.twinksSubtitle)
 if model.mythicPlusRaw and C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then local color=C_ChallengeMode.GetDungeonScoreRarityColor(model.mythicPlusRaw);if color then primary.mythicPlus.value:SetTextColor(color.r or 1,color.g or 1,color.b or 1)end else primary.mythicPlus.value:SetTextColor(1,1,1)end
 if self.updatedStatus then self.updatedStatus:SetText(model.lastUpdatedAt and string.format(L["DASHBOARD_UPDATED"],date(L["DASHBOARD_DATE_FORMAT"],model.lastUpdatedAt))or L["DASHBOARD_UPDATE_UNKNOWN"])end
 self:LayoutDashboard();self:RefreshDashboardProviders();return true
end

function UI:RegisterDashboardEvents()
 HolyStorm.Events:Register("HS_CHARACTER_TAB_REGISTERED","ui-dashboard-tabs",function()UI:RebuildDashboardNavigation();UI:RefreshDashboard()end)
 for _,event in ipairs({"HS_CHARACTER_UPDATED","HS_STATS_UPDATED","HS_EQUIPMENT_UPDATED","HS_MYTHICPLUS_UPDATED","HS_RAIDLOCKS_UPDATED","HS_DELVES_UPDATED","HS_PROFILE_UPDATED","HS_TWINKS_UPDATED","HS_ACCOUNT_MAIN_CHANGED","HS_TWINK_VISIBILITY_CHANGED"})do
  HolyStorm.Events:Register(event,"ui-dashboard",function(_,guid)if not guid or guid==(UnitGUID and UnitGUID("player"))then UI:RefreshDashboard()end end)
 end
 HolyStorm.Events:Register("HS_UI_DASHBOARD_PROVIDER_CHANGED","ui-dashboard-provider",function()UI:RebuildDashboardNavigation();UI:RefreshDashboardProviders();UI:RefreshDashboard()end)
 HolyStorm.Events:Register("HS_CALENDAR_UPDATED","ui-dashboard-calendar",function()UI:RefreshDashboardProviders()end)
 for _,event in ipairs({"HS_ACHIEVEMENT_DEFINITION_UPDATED","HS_ACHIEVEMENT_AWARDS_UPDATED","HS_ACHIEVEMENT_SYNC_UPDATED","HS_CONTENT_CREATED","HS_CONTENT_UPDATED","HS_CONTENT_PUBLISHED","HS_CONTENT_ARCHIVED","HS_CONTENT_DELETED"})do HolyStorm.Events:Register(event,"ui-dashboard-dynamic:"..event,function()UI:RefreshDashboardProviders();UI:RefreshDashboard()end)end
 HolyStorm.Events:Register("HS_TASK_STARTED","ui-dashboard-refresh",function(_,task)if task and task.registryId=="Character.Refresh"and task.metadata and task.metadata.characterUUID==(UnitGUID and UnitGUID("player"))then UI.refreshing=true;UI:SetStatusText(L["DASHBOARD_REFRESHING"])end end)
 for _,event in ipairs({"HS_TASK_COMPLETED","HS_TASK_FAILED"})do HolyStorm.Events:Register(event,"ui-dashboard-refresh:"..event,function(_,task)if task and task.registryId=="Character.Refresh"and task.metadata and task.metadata.characterUUID==(UnitGUID and UnitGUID("player"))then UI.refreshing=false;UI.refreshButton:SetEnabled(true);UI:SetReadyStatus();UI:RefreshDashboard()end end)end
end
