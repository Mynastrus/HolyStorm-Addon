local addonVersion="2.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_CharacterUI")
local Page=HolyStorm:RegisterRequiredModule("CharacterOverview")
HolyStorm:ApplyModuleMetadata(Page,{displayName=L["WINDOW_TITLE"],internalName="characterOverview",version=addonVersion,category="required",description=L["WINDOW_TITLE"],permissions={},dependencies={"core"},enabledByDefault=true})
local C=HolyStorm.CharacterUI

local tabVisuals={summary={icon="Interface\\Icons\\Achievement_Character_Human_Male"},stats={icon="Interface\\Icons\\INV_Misc_Note_03"},twinks={icon="Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"}}
local function display(value,options)return C:FormatState(value,nil,options)end
local function dateValue(timestamp)return timestamp and date("%d.%m.%Y %H:%M",timestamp)or nil end
local function classColor(classFile)return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]or NORMAL_FONT_COLOR or{r=1,g=1,b=1}end

local function canRender(view,definition)
 local ok,reason=C:CanUseTab(definition);if ok then return true end
 C:SetTableView(view,{}, {emptyText=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]});return false
end

local function summaryRows(context)
 local record=context.record or{};local faction=record.faction
 local rows={
  {label=L["SUMMARY_IDENTITY"],value=display(context.fullName or context.name or context.characterUUID)},
  {label=L["LEVEL"],value=display(context.level)},
  {label=L["COLUMN_CLASS"],value=display(context.className)},
  {label=L["SPECIALIZATION"],value=display(context.spec and context.spec.name)},
  {label=L["FACTION"],value=display(faction and L["FACTION_"..faction:upper()])},
 }
 for _,section in ipairs(C:GetSummarySections())do
  local ok,result=HolyStorm.Utils.SafeCall("character.summary:"..section.id,section.render,context,section)
  if ok and type(result)=="table"then
   local value=result.value;if value==nil then value=result.text end
   rows[#rows+1]={label=result.label or(section.labelKey and L[section.labelKey])or section.id,value=result.formatted or display(value,{emptyText=result.emptyText}),tabId=result.tabId,tooltip=result.tooltip}
  end
 end
 return rows
end

local function buildSummary(parent)
 return C:CreateTableView(parent,{summaryHeight=1,columns={
  {id="label",title=L["COLUMN_OVERVIEW"],width=190},
  {id="value",title=L["COLUMN_VALUE"],weight=1,minWidth=220,truncate=true},
 },rowHeight=28,headerHeight=26,columnGap=1,emptyText=L["NO_DATA"],onRowClick=function(row)if row.tabId then C:SelectTab(row.tabId)end end,rowTooltip=function(row)return row.tooltip end})
end
local function refreshSummary(view,context)C:SetTableView(view,summaryRows(context),{emptyText=L["NO_DATA"]})end

local statKeys={"strength","agility","stamina","intellect"}
local secondaryKeys={"criticalStrike","haste","mastery","versatility"}
local function statTotal(value)
 if type(value)~="table"then return display(nil)end
 local rating=tonumber(value.rating);local percent=tonumber(value.percent)
 if rating==nil and percent==nil then return display(nil)end
 if percent~=nil then return string.format("%s  (%.1f%%)",display(rating or 0),percent)end
 return display(rating)
end
local function buildStats(parent)
 return C:CreateTableView(parent,{summaryHeight=1,columns={
  {id="stat",title=L["COLUMN_STAT"],weight=1,minWidth=170},
  {id="base",title=L["COLUMN_BASE"],width=130,align="RIGHT"},
  {id="additional",title=L["COLUMN_ADDITIONAL"],width=130,align="RIGHT"},
  {id="total",title=L["COLUMN_TOTAL"],width=180,align="RIGHT"},
 },rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_STATS"]})
end
local function refreshStats(view,context,definition)
 if not canRender(view,definition)then return end
 local snapshot=C:GetSnapshot(context.characterUUID,"stats");if not snapshot then C:SetTableView(view,{}, {emptyText=L["NO_STATS"]});return end
 local rows={};local function primary(label,value)
  local baseValue=type(value)=="table"and tonumber(value.base)or nil;local totalValue=type(value)=="table"and tonumber(value.effective)or nil;local additional=baseValue~=nil and totalValue~=nil and totalValue-baseValue or nil
  rows[#rows+1]={stat=label,base=display(baseValue),additional=HolyStorm.UI.Components:FormatDelta(additional),total=display(totalValue)}
 end
 for _,key in ipairs(statKeys)do primary(L["STAT_"..key:upper()],snapshot.primary and snapshot.primary[key])end
 primary(L["STAT_ARMOR"],snapshot.armor)
 for _,key in ipairs(secondaryKeys)do rows[#rows+1]={stat=L["STAT_"..key:upper()],base=display(nil),additional=display(nil),total=statTotal(snapshot.secondary and snapshot.secondary[key])}end
 C:SetTableView(view,rows,{emptyText=L["NO_STATS"]})
end

local function buildTwinks(parent)
 return C:CreateTableView(parent,{columns={
  {id="name",title=L["COLUMN_CHARACTER"],weight=1,minWidth=180,truncate=true,tooltip=function(row,_,_,_,owner)C:ShowTooltip(owner,row.characterUUID);return true end},
  {id="class",title=L["COLUMN_CLASS"],width=120},
  {id="level",title=L["COLUMN_LEVEL"],width=70,align="RIGHT"},
  {id="guild",title=L["COLUMN_GUILD"],width=120},
  {id="relationship",title=L["COLUMN_RELATIONSHIP"],width=180},
 },rowHeight=26,headerHeight=26,columnGap=1,emptyText=L["NO_TWINKS"],onRowClick=function(row)C:OpenCharacter(row.characterUUID,"summary")end})
end
local function refreshTwinks(view,context,definition)
 if not canRender(view,definition)then return end
 local core,accountUUID=HolyStorm.TwinkCore,context.accountUUID;if not accountUUID then C:SetTableView(view,{}, {emptyText=L["NO_TWINKS"]});return end
 local guild=context.guild;local accountMain=core:GetAccountMain(accountUUID,guild);local guildMain,isShadow=core:GetGuildMain(accountUUID,guild);local characters=core:GetVisibleCharactersForViewer(accountUUID,guild);local rows={}
 for _,character in ipairs(characters)do
  local labels={};if character.characterUUID==accountMain then labels[#labels+1]=L["ACCOUNT_MAIN"]end;if character.characterUUID==guildMain then labels[#labels+1]=L[isShadow and"SHADOW_MAIN"or"GUILD_MAIN"]end
  local name=(#labels>0 and("["..table.concat(labels,"/").."] ")or"")..(character.fullName or character.name or character.characterUUID);local inGuild=guild and guild.roster and guild.roster[character.characterUUID]
  rows[#rows+1]={characterUUID=character.characterUUID,name=name,class=display(character.classFile),level=display(character.level),guild=inGuild and L["IN_GUILD"]or L["NOT_IN_GUILD"],relationship=character.relationship and character.relationship.source==core.sources.OWNER and L["OWNER_CONFIRMED"]or L["ADMINISTRATIVE"]}
 end
 C:SetTableView(view,rows,{summary=string.format(L["CHARACTER_COUNT"],#characters),emptyText=L["NO_TWINKS"]})
end

local standardTabs={
 {id="summary",order=1,labelKey="TAB_SUMMARY",icon=tabVisuals.summary.icon,blocks={"identity"},events={"HS_CHARACTER_UPDATED","HS_ROSTER_UPDATED"},build=buildSummary,refresh=refreshSummary},
 {id="stats",order=60,labelKey="TAB_STATS",icon=tabVisuals.stats.icon,permission="player-read",moduleId="characterStats",blocks={"stats"},events={"HS_STATS_UPDATED"},build=buildStats,refresh=refreshStats},
 {id="twinks",order=70,labelKey="TAB_TWINKS",icon=tabVisuals.twinks.icon,permission="player-read",blocks={"identity"},events={"HS_TWINKS_UPDATED","HS_ACCOUNT_MAIN_CHANGED","HS_GUILD_MAIN_CHANGED","HS_TWINK_VISIBILITY_CHANGED"},characterScopedEvents=false,build=buildTwinks,refresh=refreshTwinks},
}
for _,definition in ipairs(standardTabs)do assert(C:RegisterTab(definition))end
C:RegisterSummarySection({id="twinks",order=90,render=function(context)local allowed,reason=C:CanUseTab(C:GetTab("twinks"));if not allowed then return{label=L["SUMMARY_TWINKS"],tabId="twinks",value=reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]}end;local account=context.accountUUID and HolyStorm.TwinkCore:GetAccount(context.accountUUID);local count=account and HolyStorm.Utils.TableCount(account.characters)or 0;return{label=L["SUMMARY_TWINKS"],tabId="twinks",value=count>0 and string.format(L["CHARACTER_COUNT"],count)or""}end})
HolyStorm:RegisterCapability("CharacterOverview","character.open",function(_,characterUUID,tabId)return C:OpenCharacter(characterUUID,tabId or"summary")end)

function Page:UpdateTabVisuals()if self.tabGroup and self.tabGroup.SelectTab and C.activeTab then self.tabGroup:SelectTab(C.activeTab,true)end end
function Page:LayoutTabs()if self.pageLayout then self.pageLayout:Relayout()end;if self.tabGroup and self.tabGroup.LayoutTabs then self.tabGroup:LayoutTabs()end;if C.activeTab and self.views and self.views[C.activeTab]then C:LayoutTabView(self.views[C.activeTab])end end
function Page:SetHeaderVisible(visible)if self.header then self.header:SetShown(visible==true)end end
function Page:IsCharacterPageVisible()return HolyStorm.UI and HolyStorm.UI.GetVisiblePage and HolyStorm.UI:GetVisiblePage()=="character"end
function C:LayoutTabView(view)
 if not view or not view.frame or not Page.tabHost then return end
 if view.frame.SetParent then view.frame:SetParent(Page.tabHost)end;view.frame:ClearAllPoints();view.frame:SetAllPoints(Page.tabHost)
 if view.frame.SetSize and Page.tabHost.GetWidth and Page.tabHost.GetHeight then view.frame:SetSize(math.max(1,Page.tabHost:GetWidth()or 1),math.max(1,Page.tabHost:GetHeight()or 1))end
 if view.layout then view.layout:Relayout()elseif view.table and view.table.Relayout then view.table:Relayout()end
end
function C:RefreshHeader()
 local context=self.context;if not context or not Page.headerName then return end;context=self:ResolveContext(context.characterUUID);context.token=self.contextToken;self.context=context;local color=classColor(context.classFile);Page.headerName:SetText(context.name or context.characterUUID);Page.headerName:SetTextColor(color.r,color.g,color.b);local rank=context.member and context.member.rank or context.record and context.record.guildRank;local parts={context.realm,context.className,context.spec and context.spec.name,context.level and(L["LEVEL"].." "..context.level),rank};local clean={};for _,part in ipairs(parts)do if part and part~=""then clean[#clean+1]=part end end;Page.headerInfo:SetText(table.concat(clean,"  •  "))
 if Page:IsCharacterPageVisible()then Page:SetHeaderVisible(true)end
 if Page.classIcon then self:ApplyClassIconTexture(Page.classIcon,context.classFile)end
 if Page.specIcon then local icon=context.spec and context.spec.icon;if icon then Page.specIcon:SetTexture(icon);Page.specIcon:SetTexCoord(0,1,0,1);Page.specIcon:Show()else Page.specIcon:Hide()end end
 if Page.headerName then Page.headerName:ClearAllPoints();if Page.specIcon and Page.specIcon:IsShown()then Page.headerName:SetPoint("TOPLEFT",Page.specIcon,"TOPRIGHT",12,-2)else Page.headerName:SetPoint("TOPLEFT",Page.classIcon,"TOPRIGHT",12,-2)end;Page.headerName:SetPoint("RIGHT",Page.header,"RIGHT",-250,0)end
 if Page.factionMark then local faction=context.record and context.record.faction;Page.factionMark:SetTexture(faction=="Horde"and"Interface\\FriendsFrame\\PlusManz-Horde"or faction=="Alliance"and"Interface\\FriendsFrame\\PlusManz-Alliance"or nil);Page.factionMark:SetShown(faction=="Horde"or faction=="Alliance")end
 local definition=self:GetTab(self.activeTab or"summary");local activeBlocks=definition and definition.blocks or{};local block=activeBlocks[1];local dataStatus,meta;if block then dataStatus,meta=self:GetDataStatus(context.characterUUID,block)end;Page.headerStatus:SetText(dataStatus and L["STATUS_"..dataStatus]or L["STATUS_CURRENT"]);if Page.headerUpdated then Page.headerUpdated:SetText(meta and meta.updatedAt and string.format(L["LAST_UPDATED"],dateValue(meta.updatedAt))or"")end
 local developerText=HolyStorm.Database:Get("debug","profile")and(context.characterUUID.."  |  "..tostring(context.accountUUID or"-"))or"";Page.developer:SetText(developerText);Page:UpdateTabVisuals()
end
function C:RefreshTab(id)
 local definition=self.tabs[id];if not definition or not self.context then return false end
 local function logFailure(stage,err)local guid=self.context and self.context.characterUUID;local blockId=(definition.blocks or{})[1];local snapshot;if blockId and guid then local readOk,result=pcall(self.GetSnapshot,self,guid,blockId);if readOk then snapshot=result end end;if HolyStorm.Logger and HolyStorm.Logger.Write then HolyStorm.Logger:Write("ERROR","CharacterOverview","ui","Character tab renderer failed",{tabId=id,characterGUID=guid,error=tostring(err),stage=stage,dataBlock=blockId,dataType=type(snapshot),snapshotVersion=type(snapshot)=="table"and snapshot.snapshotVersion or nil})end end
 local view=Page.views[id];if not view then local built,result=HolyStorm.Utils.SafeCall("character.tab.build:"..id,definition.build,Page.tabHost,self.context);local valid=built and type(result)=="table"and result.frame;if valid then view=result else logFailure("build",result);view=C:CreateTableView(Page.tabHost,{columns={{id="message",title=L["TAB_ERROR"],weight=1}},emptyText=L["TAB_ERROR"]})end;view.buildFailed=not valid;Page.views[id]=view;self:LayoutTabView(view);if not valid then self:SetTableView(view,{}, {emptyText=L["TAB_ERROR"]})end end
 if view.buildFailed then return false end
 local ok,err=HolyStorm.Utils.SafeCall("character.tab.refresh:"..id,definition.refresh,view,self.context,definition);if not ok then logFailure("refresh",err);self:SetTableView(view,{}, {emptyText=L["TAB_ERROR"]})end;Page.dirty[id]=nil;return ok
end
function C:SelectTab(id)
 local definition=self.tabs[id]or self.tabs.summary;if not definition then return false end;id=definition.id;self.activeTab=id
 for tabId,view in pairs(Page.views)do view.frame:SetShown(tabId==id)end;Page:UpdateTabVisuals();if not Page.views[id]then self:RefreshTab(id)end;self:LayoutTabView(Page.views[id]);Page.views[id].frame:Show();if Page.dirty[id]then self:RefreshTab(id)end;self:RefreshHeader();return true
end
function C:OpenCharacter(characterUUID,optionalTab,addHistory)
 local context=self:SetContext(characterUUID,addHistory);if not context then return false end;for _,definition in ipairs(self:GetTabs())do Page.dirty[definition.id]=true end;if HolyStorm.UI.ShowView then HolyStorm.UI:ShowView("character")else HolyStorm.UI:ShowPage("character")end;self:RefreshHeader();self:SelectTab(optionalTab or self.activeTab or"summary");self:RequestRefresh(characterUUID,(self:GetTab(optionalTab or self.activeTab or"summary")or{}).blocks,"CHARACTER_OPEN");return true
end
function Page:ScheduleRefresh(tabId,guid)
 if guid and C.context and guid~=C.context.characterUUID then return end;self.dirty[tabId]=true;self.dirty.summary=true;if self.refreshScheduled then return end;local token=C.contextToken;self.refreshScheduled=true;C_Timer.After(.05,function()Page.refreshScheduled=nil;if token~=C.contextToken then return end;C:RefreshHeader();if C.activeTab and Page.dirty[C.activeTab]then C:RefreshTab(C.activeTab)end end)
end
function Page:BuildTabs()
 local tabs={};for _,definition in ipairs(C:GetTabs())do local visual=tabVisuals[definition.id];tabs[#tabs+1]={value=definition.id,text=definition.label or L[definition.labelKey],icon=definition.icon or(visual and visual.icon)}end
 if self.tabGroup and self.tabGroup.SetTabs then self.tabGroup:SetTabs(tabs);self.tabButtons=self.tabGroup.tabButtons or{};self.tabGroup:SelectTab(C.activeTab or(tabs[1]and tabs[1].value),true)end
end
function Page:InitializeUI()
 local UI=HolyStorm:GetModule("UI",true);local page=CreateFrame("Frame",nil,UI.content);self.page=page;self.views,self.tabButtons,self.dirty={},{},{}
 local headerBar=HolyStorm.UIComponents:CreateHeaderBar(UI.frame or page,UI.content or page);self.headerBar=headerBar;self.header=headerBar.frame;self.classIcon=headerBar.primaryIcon;self.portrait=headerBar.primaryIcon;self.specIcon=headerBar.secondaryIcon;self.headerName=headerBar.title;self.headerInfo=headerBar.subtitle;self.factionMark=headerBar.watermark;self.headerStatus=headerBar.status;self.headerUpdated=headerBar.updated;self.developer=headerBar.developer;self.refreshButton=headerBar.refreshButton
 self.refreshButton:SetScript("OnEnter",function(button)GameTooltip:SetOwner(button,"ANCHOR_LEFT");GameTooltip:SetText(L["REFRESH"]);GameTooltip:Show()end);self.refreshButton:SetScript("OnLeave",function()GameTooltip:Hide()end);self.refreshButton:SetScript("OnClick",function()if C.context then C:RequestRefresh(C.context.characterUUID,(C:GetTab(C.activeTab)or{}).blocks,"MANUAL")end end)
 self.pageLayout=HolyStorm.UI.Components:CreateColumn(page,{frame=page,padding={left=12,right=12,top=8,bottom=10}})
 local tabGroup=HolyStorm.UI.Components:CreateTabGroup(page);tabGroup.frame:Show();tabGroup:SetCallback("OnGroupSelected",function(_,_,tabId)if C.context then C:SelectTab(tabId);C:RequestRefresh(C.context.characterUUID,(C:GetTab(tabId)or{}).blocks,"TAB_SELECTED")end end);self.pageLayout:Add(tabGroup,{weight=1});self.tabGroup=tabGroup;self.tabHost=tabGroup:GetContentFrame();self.tabHost:Show();self:BuildTabs()
 page:HookScript("OnShow",function()Page:SetHeaderVisible(true)end);page:HookScript("OnHide",function()Page:SetHeaderVisible(false)end);local refresh=function()Page:SetHeaderVisible(true);if C.context then C:RefreshHeader();C:SelectTab(C.activeTab or"summary")end end;assert(HolyStorm.UI:RegisterView({id="character",owner="characters",title=L["WINDOW_TITLE"],page=page,refresh=refresh}))
 local function registerTabEvents(definition)for _,event in ipairs(definition.events or{})do local owner="character-overview:"..definition.id..":"..event;HolyStorm.Events:Register(event,owner,function(_,guid)Page:ScheduleRefresh(definition.id,definition.characterScopedEvents==false and nil or guid)end)end end
 for _,definition in ipairs(C:GetTabs())do registerTabEvents(definition)end
 HolyStorm.Events:Register("HS_CHARACTER_TAB_REGISTERED","character-overview-tabs",function(_,id)local definition=C:GetTab(id);if definition then registerTabEvents(definition)end;Page:BuildTabs()end)
 HolyStorm.Events:Register("HS_CHARACTER_SUMMARY_SECTION_REGISTERED","character-overview-summary",function()Page:ScheduleRefresh("summary")end)
 HolyStorm.Events:Register("HS_TASK_STARTED","character-overview-task",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page.headerStatus:SetText(L["STATUS_REFRESHING"])end end)
 HolyStorm.Events:Register("HS_TASK_COMPLETED","character-overview-task-complete",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page:ScheduleRefresh(C.activeTab,task.metadata.characterUUID)end end)
 HolyStorm.Events:Register("HS_TASK_FAILED","character-overview-task-failed",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page:ScheduleRefresh(C.activeTab,task.metadata.characterUUID)end end)
end
function Page:OnInitialize()
 HolyStorm.Tasks:RegisterTaskType("Character.Refresh",{name=L["TASK_CHARACTER_REFRESH"],localizedNameKey="TASK_CHARACTER_REFRESH",module="CharacterOverview",priority=30,executionMode="MERGE_BY_KEY",execute=function(task)local metadata=task.metadata or{};return C:ConsumeRefresh(metadata.characterUUID)end})
 HolyStorm:RegisterUIExtension("CharacterOverview",{id="characters.overview",order=4,initialize=function()Page:InitializeUI()end})
end
function Page:OnDisable()HolyStorm.Events:UnregisterOwner("character-overview");for _,definition in ipairs(C:GetTabs())do for _,event in ipairs(definition.events or{})do HolyStorm.Events:UnregisterOwner("character-overview:"..definition.id..":"..event)end end;HolyStorm.Events:UnregisterOwner("character-overview-tabs");HolyStorm.Events:UnregisterOwner("character-overview-summary");HolyStorm.Events:UnregisterOwner("character-overview-task");HolyStorm.Events:UnregisterOwner("character-overview-task-complete");HolyStorm.Events:UnregisterOwner("character-overview-task-failed")end
