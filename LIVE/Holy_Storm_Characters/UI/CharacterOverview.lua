local addonVersion="1.4.2"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_CharacterUI")
local Page=HolyStorm:RegisterRequiredModule("CharacterOverview")
HolyStorm:ApplyModuleMetadata(Page,{displayName=L["WINDOW_TITLE"],internalName="characterOverview",version=addonVersion,category="required",description=L["WINDOW_TITLE"],permissions={},dependencies={"core"},enabledByDefault=true})
local C=HolyStorm.CharacterUI


local function value(v)return v==nil and L["UNKNOWN"]or tostring(v)end
local function number(v,format)return tonumber(v)and string.format(format or"%.1f",tonumber(v))or L["UNKNOWN"]end
local function dateValue(timestamp)return timestamp and date("%d.%m.%Y %H:%M",timestamp)or nil end
local function classColor(classFile)return RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]or NORMAL_FONT_COLOR or{r=1,g=1,b=1}end
local function hyperlink(kind,id,label,difficulty)local text=difficulty and C:ColorDifficulty(difficulty,label)or("|cff3fc7eb"..tostring(label).."|r");return id and("|Hhscharacter:"..kind..":"..tostring(id).."|h"..text.."|h")or text end
local function tableRow(cells,columns,style,maxWidth)return{cells=cells,columns=columns,style=style,maxWidth=maxWidth}end
local statsColumns={{width=.42},{width=.24,align="RIGHT"},{width=.34,align="RIGHT"}}
local twinkColumns={{width=.42},{width=.14},{width=.08,align="RIGHT"},{width=.15},{width=.21}}
local tabVisuals={summary={icon="Interface\\Icons\\Achievement_Character_Human_Male"},stats={icon="Interface\\Icons\\INV_Misc_Note_03"},twinks={icon="Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"}}
local panelBackdrop={bgFile="Interface\\Buttons\\WHITE8x8",edgeFile="Interface\\Buttons\\WHITE8x8",edgeSize=1}
local function stylePanel(frame,r,g,b,a,br,bg,bb,ba)if frame.SetBackdrop then frame:SetBackdrop(panelBackdrop);frame:SetBackdropColor(r or.025,g or.035,b or.05,a or.94);frame:SetBackdropBorderColor(br or.32,bg or.24,bb or.08,ba or.9)end end

function C:CreateTextView(parent)
 local frame=CreateFrame("Frame",nil,parent,"BackdropTemplate");frame:SetAllPoints();stylePanel(frame,.018,.027,.04,.96,.25,.19,.07,.9)
 local heading=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge");heading:Hide()
 local status=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPRIGHT",-12,-8);status:SetJustifyH("RIGHT");status:SetTextColor(.65,.65,.65);status:Hide()
 local scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",8,-8);scroll:SetPoint("BOTTOMRIGHT",-30,8)
 local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content)
 local view={frame=frame,heading=heading,status=status,scroll=scroll,content=content,rows={}}
 scroll:SetScript("OnSizeChanged",function()C:LayoutTextView(view)end)
 return view
end
function C:LayoutTextView(view)
 if not view or not view.scroll then return end
 local width=math.max(1,(view.scroll:GetWidth()or 1)-14);view.content:SetWidth(width)
 local y=4
 for _,row in ipairs(view.rows or{})do
  if row:IsShown()then
   row:SetWidth(width);local textHeight=16
   if row.cellsData then
    local tableWidth=math.min(width,row.maxWidth or width);local x=0
    for index,column in ipairs(row.columns)do local cell=row.cells[index];local cellWidth=index==#row.columns and(tableWidth-x)or math.floor(tableWidth*column.width);cell:ClearAllPoints();cell:SetPoint("TOPLEFT",row,"TOPLEFT",x+8,-4);cell:SetWidth(math.max(1,cellWidth-16));cell:SetJustifyH(column.align or"LEFT");cell:SetJustifyV(row.verticalCenter and"MIDDLE"or"TOP");textHeight=math.max(textHeight,math.ceil(cell:GetStringHeight()or 16));x=x+cellWidth end
   else row.text:SetWidth(math.max(1,width-16));textHeight=math.max(16,math.ceil(row.text:GetStringHeight()or 16))end
   local height=row.blank and 10 or math.max(row.minHeight or 0,textHeight+8)
   row:SetHeight(height);row:ClearAllPoints();row:SetPoint("TOPLEFT",view.content,"TOPLEFT",0,-y);y=y+height
  end
 end
 view.content:SetHeight(math.max(1,y+4))
end
function C:AcquireTextRow(view,index)
 local row=view.rows[index];if row then return row end
 row=CreateFrame("Frame",nil,view.content);local background=row:CreateTexture(nil,"BACKGROUND");background:SetAllPoints();background:SetColorTexture(1,1,1,.035);row.background=background
 local line=row:CreateFontString(nil,"OVERLAY","GameFontHighlight");line:SetPoint("TOPLEFT",8,-4);line:SetJustifyH("LEFT");line:SetJustifyV("TOP");line:SetWordWrap(true);if line.SetNonSpaceWrap then line:SetNonSpaceWrap(false)end;row.text=line
 if line.SetHyperlinksEnabled then line:SetHyperlinksEnabled(true);line:SetScript("OnHyperlinkClick",function(_,link,_,button)C:HandleLink(link,button)end);line:SetScript("OnHyperlinkEnter",function(_,link)C:ShowLinkTooltip(line,link)end);line:SetScript("OnHyperlinkLeave",function()GameTooltip:Hide()end)end
 view.rows[index]=row;return row
end
function C:AcquireTableCell(row,index)
 local cell=row.cells[index];if cell then return cell end
 cell=row:CreateFontString(nil,"OVERLAY","GameFontHighlight");cell:SetJustifyV("TOP");cell:SetWordWrap(true);if cell.SetNonSpaceWrap then cell:SetNonSpaceWrap(false)end
 if cell.SetHyperlinksEnabled then cell:SetHyperlinksEnabled(true);cell:SetScript("OnHyperlinkClick",function(_,link,_,button)C:HandleLink(link,button)end);cell:SetScript("OnHyperlinkEnter",function(_,link)C:ShowLinkTooltip(cell,link)end);cell:SetScript("OnHyperlinkLeave",function()GameTooltip:Hide()end)end
 row.cells[index]=cell;return cell
end
function C:SetView(view,heading,lines,status,meta,styles)
 if view.heading then view.heading:SetText("");view.heading:Hide()end;lines=lines or{};styles=styles or{}
 for index,entry in ipairs(lines)do
  local row=self:AcquireTextRow(view,index);local tableEntry=type(entry)=="table"and entry.cells;local style=type(entry)=="table"and entry.style or styles[index];row.blank=entry=="";row.cellsData=tableEntry and entry.cells or nil;row.columns=tableEntry and entry.columns or nil;row.maxWidth=tableEntry and entry.maxWidth or nil;row.minHeight=type(entry)=="table"and entry.minHeight or nil;row.verticalCenter=type(entry)=="table"and entry.verticalCenter or nil;row.cells=row.cells or{}
  row.text:SetShown(not tableEntry);row.text:SetText(tableEntry and""or entry)
  for cellIndex,cellText in ipairs(row.cellsData or{})do local cell=self:AcquireTableCell(row,cellIndex);cell:SetText(cellText or"");cell:SetFontObject(style=="header"and"GameFontNormal"or style=="summary"and"GameFontNormalLarge"or"GameFontHighlight");cell:SetTextColor((style=="header"or style=="summary")and 1 or 1,(style=="header"or style=="summary")and .82 or 1,(style=="header"or style=="summary")and 0 or 1);cell:Show()end
  for cellIndex=#(row.cellsData or{})+1,#row.cells do row.cells[cellIndex]:Hide()end
  row.text:SetFontObject(style=="section"and"GameFontNormalLarge"or style=="header"and"GameFontNormal"or style=="muted"and"GameFontDisable"or"GameFontHighlight")
  if style=="accent"or style=="header"then row.text:SetTextColor(1,.82,0)elseif style=="muted"then row.text:SetTextColor(.65,.65,.65)else row.text:SetTextColor(1,1,1)end
  row.background:SetShown(not row.blank);row.background:SetAlpha(style=="header"and .32 or style=="summary"and .22 or(index%2==0 and .8 or .35));row:Show()
 end
 for index=#lines+1,#view.rows do view.rows[index]:Hide()end
 self:LayoutTextView(view);if C_Timer and C_Timer.After then C_Timer.After(0,function()if view.frame:IsShown()then C:LayoutTextView(view)end end)end
 local statusText=status and L["STATUS_"..status]or"";if meta and meta.updatedAt then statusText=statusText..(statusText~=""and"  •  "or"")..string.format(L["LAST_UPDATED"],dateValue(meta.updatedAt))end;view.status:SetText(statusText)
end
function C:HandleLink(link,button)
 local kind,id=link:match("^hscharacter:([^:]+):(.+)$")
 if kind=="tab"then self:SelectTab(id)elseif kind=="character"then self:OpenCharacter(id,"summary")elseif kind then local handler=self:GetLinkHandler(kind);if handler and handler.onClick then handler.onClick(id,button)end end
 if link:match("^item:")then if SetItemRef then SetItemRef(link,link,button or"LeftButton")elseif HandleModifiedItemClick then HandleModifiedItemClick(link)end end
end
function C:ShowLinkTooltip(owner,link)
 GameTooltip:SetOwner(owner,"ANCHOR_CURSOR")
 if link:match("^item:")then GameTooltip:SetHyperlink(link)
 else local kind,id=link:match("^hscharacter:([^:]+):(.+)$");local handler=kind and self:GetLinkHandler(kind);if handler and handler.tooltip then handler.tooltip(id,owner)elseif kind=="character"then GameTooltip:SetText(L["WINDOW_TITLE"])end end
 GameTooltip:Show()
end

local function statusFor(guid,block)local status,meta=C:GetDataStatus(guid,block);return status,meta end
local function blocked(view,definition)
 local ok,reason=C:CanUseTab(definition);if ok then return false end;C:SetView(view,L[definition.labelKey],{reason=="PERMISSION"and L["PERMISSION_DENIED"]or L["MODULE_DISABLED"]});return true
end
local function summary(view,context,definition)
 local lines={L["SUMMARY_IDENTITY"],string.format("  %s — %s %s",context.fullName or context.name or context.characterUUID,L["LEVEL"],value(context.level))}
 local styles={[1]="section"}
 for _,section in ipairs(C:GetSummarySections())do
  local ok,result=HolyStorm.Utils.SafeCall("character.summary:"..section.id,section.render,context,section)
  if ok and type(result)=="table"then
   lines[#lines+1]="";local heading=result.label or(section.labelKey and L[section.labelKey])or section.id;lines[#lines+1]=result.tabId and hyperlink("tab",result.tabId,heading)or heading;styles[#lines]="section"
   local details=type(result.lines)=="table"and result.lines or{result.text};for _,line in ipairs(details)do if line~=nil then lines[#lines+1]=line end end
  end
 end
 C:SetView(view,L[definition.labelKey],lines,nil,nil,styles)
end
local function stats(view,context,definition)
 if blocked(view,definition)then return end;local snapshot,meta=C:GetSnapshot(context.characterUUID,"stats");local status=statusFor(context.characterUUID,"stats");if not snapshot then C:SetView(view,L[definition.labelKey],{L["NO_STATS"]},status);return end
 local lines={tableRow({L["COLUMN_STAT"],L["COLUMN_BASE"],L["COLUMN_EFFECTIVE"]},statsColumns,"header",760)};for _,key in ipairs({"strength","agility","stamina","intellect"})do local x=snapshot.primary and snapshot.primary[key];lines[#lines+1]=tableRow({L["STAT_"..key:upper()],value(x and x.base),value(x and x.effective)},statsColumns,nil,760)end
 if snapshot.armor then lines[#lines+1]=tableRow({L["STAT_ARMOR"],value(snapshot.armor.base),value(snapshot.armor.effective)},statsColumns,nil,760)end;for _,key in ipairs({"criticalStrike","haste","mastery","versatility"})do local x=snapshot.secondary and snapshot.secondary[key];local percent=x and tonumber(x.percent);lines[#lines+1]=tableRow({L["STAT_"..key:upper()],value(x and x.rating),percent and string.format("%.1f%%",percent)or L["UNKNOWN"]},statsColumns,nil,760)end;lines[#lines+1]="";lines[#lines+1]=L["COLUMN_LIVE_BUFFS"]..": "..L["LIVE_BUFFS_UNAVAILABLE"];C:SetView(view,L[definition.labelKey],lines,status,meta,{[#lines]="muted"})
end
local function twinks(view,context,definition)
 local core,accountUUID=HolyStorm.TwinkCore,context.accountUUID;if not accountUUID then C:SetView(view,L[definition.labelKey],{L["NO_TWINKS"]});return end;local guild=context.guild;local accountMain=core:GetAccountMain(accountUUID,guild);local guildMain,isShadow=core:GetGuildMain(accountUUID,guild);local characters=core:GetVisibleCharactersForViewer(accountUUID,guild);local lines={string.format(L["CHARACTER_COUNT"],#characters),L["ACCOUNT_MAIN"]..": "..value(accountMain),L[isShadow and"SHADOW_MAIN"or"GUILD_MAIN"]..": "..value(guildMain),"",tableRow({L["COLUMN_CHARACTER"],L["COLUMN_CLASS"],L["COLUMN_LEVEL"],L["COLUMN_GUILD"],L["COLUMN_RELATIONSHIP"]},twinkColumns,"header",1450)}
 for _,character in ipairs(characters)do local labels={};if character.characterUUID==accountMain then labels[#labels+1]=L["ACCOUNT_MAIN"]end;if character.characterUUID==guildMain then labels[#labels+1]=L[isShadow and"SHADOW_MAIN"or"GUILD_MAIN"]end;local label=(#labels>0 and("["..table.concat(labels,"/").."] ")or"")..(character.fullName or character.name or character.characterUUID);local inGuild=guild and guild.roster and guild.roster[character.characterUUID];local source=character.relationship and character.relationship.source==core.sources.OWNER and L["OWNER_CONFIRMED"]or L["ADMINISTRATIVE"];lines[#lines+1]=tableRow({hyperlink("character",character.characterUUID,label),value(character.classFile),value(character.level),inGuild and L["IN_GUILD"]or L["NOT_IN_GUILD"],source},twinkColumns,nil,1450)end;C:SetView(view,L[definition.labelKey],#characters>0 and lines or{L["NO_TWINKS"]},nil,nil,#characters>0 and{[1]="accent"}or nil)
end

local standardTabs={
 {id="summary",order=1,labelKey="TAB_SUMMARY",icon=tabVisuals.summary.icon,blocks={"identity"},events={"HS_CHARACTER_UPDATED","HS_ROSTER_UPDATED"},refresh=summary},
 {id="stats",order=60,labelKey="TAB_STATS",icon=tabVisuals.stats.icon,permission="player-read",moduleId="characterStats",blocks={"stats"},events={"HS_STATS_UPDATED"},refresh=stats},
 {id="twinks",order=70,labelKey="TAB_TWINKS",icon=tabVisuals.twinks.icon,permission="player-read",blocks={"identity"},events={"HS_TWINKS_UPDATED","HS_ACCOUNT_MAIN_CHANGED","HS_GUILD_MAIN_CHANGED","HS_TWINK_VISIBILITY_CHANGED"},characterScopedEvents=false,refresh=twinks},
}
for _,definition in ipairs(standardTabs)do definition.build=function(parent)return C:CreateTextView(parent)end;assert(C:RegisterTab(definition))end
C:RegisterSummarySection({id="twinks",order=90,render=function(context)local account=context.accountUUID and HolyStorm.TwinkCore:GetAccount(context.accountUUID);local count=account and HolyStorm.Utils.TableCount(account.characters)or 0;return{label=L["SUMMARY_TWINKS"],tabId="twinks",text="  "..(count>0 and string.format(L["CHARACTER_COUNT"],count)or L["NO_TWINKS"])}end})
HolyStorm:RegisterCapability("CharacterOverview","character.open",function(_,characterUUID,tabId)return C:OpenCharacter(characterUUID,tabId or"summary")end)

function Page:UpdateTabVisuals()
 if self.tabGroup and self.tabGroup.SelectTab and C.activeTab then self.tabGroup:SelectTab(C.activeTab,true)end
end
function Page:LayoutTabs()
 if self.tabGroup and self.tabGroup.LayoutTabs then self.tabGroup:LayoutTabs()end;if C.activeTab and self.views and self.views[C.activeTab]then C:LayoutTabView(self.views[C.activeTab])end
end
function Page:SetHeaderVisible(visible)
 if self.header then self.header:SetShown(visible==true)end
end
function Page:IsCharacterPageVisible()
 return HolyStorm.UI and HolyStorm.UI.GetVisiblePage and HolyStorm.UI:GetVisiblePage()=="character"
end
function C:LayoutTabView(view)
 if not view or not view.frame or not Page.tabHost then return end
 if view.frame.SetParent then view.frame:SetParent(Page.tabHost)end;view.frame:ClearAllPoints();view.frame:SetPoint("TOPLEFT",Page.tabHost,"TOPLEFT",0,0);view.frame:SetPoint("BOTTOMRIGHT",Page.tabHost,"BOTTOMRIGHT",0,0);if view.frame.SetSize and Page.tabHost.GetWidth and Page.tabHost.GetHeight then view.frame:SetSize(math.max(1,Page.tabHost:GetWidth()or 1),math.max(1,Page.tabHost:GetHeight()or 1))end;if view.scroll then self:LayoutTextView(view)end
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
 local definition=self.tabs[id];if not definition or not self.context then return false end;local function logFailure(stage,err)local guid=self.context and self.context.characterUUID;local blockId=(definition.blocks or{})[1];local snapshot;if blockId and guid then local readOk,result=pcall(self.GetSnapshot,self,guid,blockId);if readOk then snapshot=result end end;if HolyStorm.Logger and HolyStorm.Logger.Write then HolyStorm.Logger:Write("ERROR","CharacterOverview","ui","Character tab renderer failed",{tabId=id,characterGUID=guid,error=tostring(err),stage=stage,dataBlock=blockId,dataType=type(snapshot),snapshotVersion=type(snapshot)=="table"and snapshot.snapshotVersion or nil})end end;local view=Page.views[id];if not view then local built,result=HolyStorm.Utils.SafeCall("character.tab.build:"..id,definition.build,Page.tabHost,self.context);local valid=built and type(result)=="table"and result.frame;if valid then view=result else logFailure("build",result);view=self:CreateTextView(Page.tabHost)end;view.buildFailed=not valid;Page.views[id]=view;self:LayoutTabView(view);local visual=tabVisuals[id];if view.sectionIcon and view.sectionIcon.SetTexture then view.sectionIcon:SetTexture(definition.icon or(visual and visual.icon)or"Interface\\Icons\\INV_Misc_QuestionMark")end;if not valid then self:SetView(view,L[definition.labelKey],{L["TAB_ERROR"]})end end;if view.buildFailed then return false end
 local ok,err=HolyStorm.Utils.SafeCall("character.tab.refresh:"..id,definition.refresh,view,self.context,definition);if not ok then logFailure("refresh",err);self:SetView(view,L[definition.labelKey],{L["TAB_ERROR"]})end;Page.dirty[id]=nil;return ok
end
function C:SelectTab(id)
 local definition=self.tabs[id]or self.tabs.summary;if not definition then return false end;id=definition.id;self.activeTab=id
 for tabId,view in pairs(Page.views)do view.frame:SetShown(tabId==id)end;Page:UpdateTabVisuals()
 if not Page.views[id]then self:RefreshTab(id)end;self:LayoutTabView(Page.views[id]);Page.views[id].frame:Show();if Page.dirty[id]then self:RefreshTab(id)end;self:RefreshHeader();return true
end
function C:OpenCharacter(characterUUID,optionalTab,addHistory)
 local context=self:SetContext(characterUUID,addHistory);if not context then return false end;for _,definition in ipairs(self:GetTabs())do Page.dirty[definition.id]=true end;HolyStorm.UI:ShowPage("character");self:RefreshHeader();self:SelectTab(optionalTab or self.activeTab or"summary");self:RequestRefresh(characterUUID,(self:GetTab(optionalTab or self.activeTab or"summary")or{}).blocks,"CHARACTER_OPEN");return true
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
 self.refreshButton:SetScript("OnEnter",function(b)GameTooltip:SetOwner(b,"ANCHOR_LEFT");GameTooltip:SetText(L["REFRESH"]);GameTooltip:Show()end);self.refreshButton:SetScript("OnLeave",function()GameTooltip:Hide()end);self.refreshButton:SetScript("OnClick",function()if C.context then C:RequestRefresh(C.context.characterUUID,(C:GetTab(C.activeTab)or{}).blocks,"MANUAL")end end)
 local aceGUI=LibStub("AceGUI-3.0");local tabGroup=aceGUI:Create("HolyStormTabGroup");tabGroup.frame:SetParent(page);tabGroup.frame:SetPoint("TOPLEFT",12,-8);tabGroup.frame:SetPoint("BOTTOMRIGHT",-12,10);tabGroup.frame:Show();tabGroup:SetCallback("OnGroupSelected",function(_,_,tabId)if C.context then C:SelectTab(tabId);C:RequestRefresh(C.context.characterUUID,(C:GetTab(tabId)or{}).blocks,"TAB_SELECTED")end end);self.tabGroup=tabGroup;self.tabHost=tabGroup:GetContentFrame();self.tabHost:Show();self:BuildTabs();page:HookScript("OnSizeChanged",function()Page:LayoutTabs()end);page:HookScript("OnShow",function()Page:SetHeaderVisible(true)end);page:HookScript("OnHide",function()Page:SetHeaderVisible(false)end);HolyStorm.UI:RegisterPage("character",page,L["WINDOW_TITLE"],function()Page:SetHeaderVisible(true);if C.context then C:RefreshHeader();C:SelectTab(C.activeTab or"summary")end end)
 local function registerTabEvents(definition)
  for _,event in ipairs(definition.events or{})do local owner="character-overview:"..definition.id..":"..event;HolyStorm.Events:Register(event,owner,function(_,guid)Page:ScheduleRefresh(definition.id,definition.characterScopedEvents==false and nil or guid)end)end
 end
 for _,definition in ipairs(C:GetTabs())do registerTabEvents(definition)end
 HolyStorm.Events:Register("HS_CHARACTER_TAB_REGISTERED","character-overview-tabs",function(_,id)local definition=C:GetTab(id);if definition then registerTabEvents(definition)end;Page:BuildTabs()end)
 HolyStorm.Events:Register("HS_CHARACTER_SUMMARY_SECTION_REGISTERED","character-overview-summary",function()Page:ScheduleRefresh("summary")end)
 HolyStorm.Events:Register("HS_TASK_STARTED","character-overview-task",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page.headerStatus:SetText(L["STATUS_REFRESHING"])end end)
 HolyStorm.Events:Register("HS_TASK_COMPLETED","character-overview-task-complete",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page:ScheduleRefresh(C.activeTab,task.metadata.characterUUID)end end)
 HolyStorm.Events:Register("HS_TASK_FAILED","character-overview-task-failed",function(_,task)if task.registryId=="Character.Refresh"and C:IsCurrent(task.metadata.characterUUID)then Page:ScheduleRefresh(C.activeTab,task.metadata.characterUUID)end end)
end
function Page:OnInitialize()
 HolyStorm.Tasks:RegisterTaskType("Character.Refresh",{name=L["TASK_CHARACTER_REFRESH"],localizedNameKey="TASK_CHARACTER_REFRESH",module="CharacterOverview",priority=30,executionMode="MERGE_BY_KEY",execute=function(task)local m=task.metadata or{};return C:ConsumeRefresh(m.characterUUID)end})
 HolyStorm:RegisterUIExtension("CharacterOverview",{id="characters.overview",order=4,initialize=function()Page:InitializeUI()end})
end
function Page:OnDisable()HolyStorm.Events:UnregisterOwner("character-overview");for _,definition in ipairs(C:GetTabs())do for _,event in ipairs(definition.events or{})do HolyStorm.Events:UnregisterOwner("character-overview:"..definition.id..":"..event)end end;HolyStorm.Events:UnregisterOwner("character-overview-tabs");HolyStorm.Events:UnregisterOwner("character-overview-summary");HolyStorm.Events:UnregisterOwner("character-overview-task");HolyStorm.Events:UnregisterOwner("character-overview-task-complete");HolyStorm.Events:UnregisterOwner("character-overview-task-failed")end
