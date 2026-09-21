local addonVersion = "2.2.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Twinks")
if HolyStorm.PermissionRegistry then HolyStorm.PermissionRegistry:RegisterLegacyAlias("twinks.assign","twinks-assign");HolyStorm.PermissionRegistry:RegisterLegacyAlias("twinks.remove","twinks-remove")end
if HolyStorm.PlayerData then
 HolyStorm.PlayerData:RegisterBlock("stats",{fields={"stats"},event="HS_STATS_UPDATED",staleAfter=21600})
 HolyStorm.PlayerData:RegisterBlock("profile",{fields={"profile"},event="HS_PROFILE_UPDATED",staleAfter=604800})
 HolyStorm.PlayerData:RegisterBlock("demands",{fields={"demands"},event="HS_CHARACTER_UPDATED",staleAfter=86400})
end
local function registerRichLinkTypes()
 local function render(target,label)local record=HolyStorm.Data.CharacterStore:Get(target);return label or(record and(record.fullName or record.name))or target end
 local function chatText(target)local record=HolyStorm.Data.CharacterStore:Get(target);local name=record and(record.name or record.fullName)or target;return tostring(name):match("^([^%-]+)")or tostring(name)end
 local function click(target,button,owner)if button=="RightButton"then return HolyStorm.CharacterActions:CreateContextMenu(owner or DEFAULT_CHAT_FRAME or UIParent,target)end;return HolyStorm:CallCapability("character.open",target,"summary")end
 local function tooltip(target)local record=HolyStorm.Data.CharacterStore:Get(target);return record and(record.fullName or record.name)or target,record and record.class end
 local function showTooltip(owner,target)return HolyStorm.CharacterUI:ShowTooltip(owner,target)end
 HolyStorm.RichLinks:RegisterType({type="character",render=render,chatText=chatText,onClick=click,tooltip=tooltip,showTooltip=showTooltip,owner="Characters"})
 HolyStorm.RichLinks:RegisterType({type="player",render=render,chatText=chatText,onClick=click,tooltip=tooltip,showTooltip=showTooltip,owner="Characters"})
end
HolyStorm:RegisterModule({
 id="Twinks",name="Twinks",displayName=L["DISPLAY_NAME"],internalName="twinks",version=addonVersion,
 moduleType="feature",category="feature",description=L["DESCRIPTION"],
 permissions={"player-read","savedvariables-write",{id="twinks-assign",category="Characters"},{id="twinks-remove",category="Characters"}},dependencies={"core"},
 ui={page="twinks",navigation=true},data={stores={"PlayerDataStore","CharacterStore","GuildStore"}},
 sync={domains={"twinks","twinkAdmin"}},enabledByDefault=true,
 ruleFields={
  {id="character.level",aliases={"level"},type="number",name=L["RULE_FIELD_LEVEL"],nameKey="RULE_FIELD_LEVEL",description=L["RULE_FIELD_LEVEL_DESC"],descriptionKey="RULE_FIELD_LEVEL_DESC",category=L["DISPLAY_NAME"],dependencies={"identity"},resolver=function(context)return context.character and context.character.level end},
  {id="character.class",aliases={"class"},type="string",name=L["RULE_FIELD_CLASS"],nameKey="RULE_FIELD_CLASS",description=L["RULE_FIELD_CLASS_DESC"],descriptionKey="RULE_FIELD_CLASS_DESC",category=L["DISPLAY_NAME"],dependencies={"identity"},resolver=function(context)return context.character and context.character.classFile end},
  {id="character.maxLevel",aliases={"maxLevel"},type="boolean",name=L["RULE_FIELD_MAX_LEVEL"],nameKey="RULE_FIELD_MAX_LEVEL",description=L["RULE_FIELD_MAX_LEVEL_DESC"],descriptionKey="RULE_FIELD_MAX_LEVEL_DESC",category=L["DISPLAY_NAME"],dependencies={"identity"},resolver=function(context)if not(context.character and context.character.level)then return nil,"MISSING_LEVEL"end;local maximum=GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()or GetMaxPlayerLevel and GetMaxPlayerLevel();if not maximum then return nil,"MAX_LEVEL_UNAVAILABLE"end;return context.character.level==maximum end},
 },
},function(Twinks)

HolyStorm.FilterManager:RegisterTemplate("Twinks",{id="template-max-level",name=L["FILTER_TEMPLATE_MAX_LEVEL"],description=L["FILTER_TEMPLATE_MAX_LEVEL_DESC"],rules={field="character.maxLevel",operator="true"}})
HolyStorm.FilterManager:RegisterTemplate("Twinks",{id="template-main",name=L["FILTER_TEMPLATE_MAIN"],description=L["FILTER_TEMPLATE_MAIN_DESC"],rules={field="character.mainTwinkStatus",operator="=",value="MAIN"}})

function Twinks:StoreCurrentCharacter()
 local character=HolyStorm.Data.CharacterStore:CaptureCurrent();if character then HolyStorm.TwinkCore:ConfirmLocalCharacter(character.guid)end;return character
end
function Twinks:CreateColumn(parent,left,right)local text=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");text:SetPoint("LEFT",parent,left<0 and"RIGHT"or"LEFT",left,0);text:SetPoint("RIGHT",parent,"RIGHT",right,0);text:SetJustifyH("LEFT");return text end
function Twinks:CreateRow(parent)
 local row=CreateFrame("Button",nil,parent);row:SetHeight(22);row:RegisterForClicks("LeftButtonUp")
 row.name=self:CreateColumn(row,10,-390);row.class=self:CreateColumn(row,-380,-285);row.level=self:CreateColumn(row,-275,-225);row.guild=self:CreateColumn(row,-215,-115);row.source=self:CreateColumn(row,-105,-10)
 row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD");row:SetScript("OnClick",function(button)Twinks.selectedCharacterUUID=button.characterUUID;Twinks.mainButton:SetEnabled(HolyStorm.TwinkCore:IsOwnerConfirmed(button.characterUUID));HolyStorm.CharacterUI:OpenCharacter(button.characterUUID,"summary")end);return row
end
function Twinks:CreateHeader(parent)
 local header=CreateFrame("Frame",nil,parent);header:SetHeight(24);header:SetPoint("TOPLEFT",parent,"TOPLEFT",0,-116);header:SetPoint("TOPRIGHT",parent,"TOPRIGHT",0,-116)
 header.name=self:CreateColumn(header,10,-390);header.class=self:CreateColumn(header,-380,-285);header.level=self:CreateColumn(header,-275,-225);header.guild=self:CreateColumn(header,-215,-115);header.source=self:CreateColumn(header,-105,-10)
 for _,column in ipairs({"name","class","level","guild","source"})do header[column]:SetFontObject(GameFontNormalSmall);header[column]:SetText(L["COLUMN_"..string.upper(column)]);header[column]:SetTextColor(1,.82,0)end
end
function Twinks:CreateVisibilityRadio(parent,label,value,anchor,x)
 local check=CreateFrame("CheckButton",nil,parent,"UIRadioButtonTemplate");check:SetPoint("TOPLEFT",anchor,"BOTTOMLEFT",x,-8);check.text:SetText(label);check:SetScript("OnClick",function()HolyStorm.TwinkCore:SetVisibility(value);Twinks:Refresh()end);return check
end
function Twinks:InitializeUI()
 local UI=HolyStorm:GetModule("UI",true);local page=CreateFrame("Frame",nil,UI.content);local heading=page:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge");heading:SetPoint("TOPLEFT",page,"TOPLEFT",20,-20);heading:SetText(L["HEADING"]);heading:SetTextColor(.25,.78,.92)
 local count=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");count:SetPoint("TOPLEFT",heading,"BOTTOMLEFT",0,-8);local visibility=page:CreateFontString(nil,"OVERLAY","GameFontNormal");visibility:SetPoint("TOPLEFT",count,"BOTTOMLEFT",0,-10);visibility:SetText(L["VISIBILITY"])
 self.allRadio=self:CreateVisibilityRadio(page,L["VISIBILITY_ALL"],HolyStorm.TwinkCore.visibility.ALL,visibility,0);self.guildRadio=self:CreateVisibilityRadio(page,L["VISIBILITY_GUILD_ONLY"],HolyStorm.TwinkCore.visibility.GUILD_ONLY,visibility,190)
 local mainButton=CreateFrame("Button",nil,page,"UIPanelButtonTemplate");mainButton:SetSize(150,22);mainButton:SetPoint("TOPRIGHT",page,"TOPRIGHT",-20,-78);mainButton:SetText(L["SET_ACCOUNT_MAIN"]);mainButton:SetEnabled(false);mainButton:SetScript("OnClick",function()if Twinks.selectedCharacterUUID then HolyStorm.TwinkCore:SetAccountMain(Twinks.selectedCharacterUUID);Twinks:Refresh()end end);self.mainButton=mainButton;self:CreateHeader(page)
 local scroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",page,"TOPLEFT",0,-140);scroll:SetPoint("BOTTOMRIGHT",page,"BOTTOMRIGHT",-28,16);local content=CreateFrame("Frame",nil,scroll);content:SetSize(1,1);scroll:SetScrollChild(content);scroll:SetScript("OnSizeChanged",function(frame)content:SetWidth(frame:GetWidth())end)
 self.page,self.count,self.content,self.rows=page,count,content,{};HolyStorm.UI:RegisterPage("twinks",page,L["WINDOW_TITLE"],function()Twinks:Refresh()end,{"HS_CHARACTER_UPDATED","HS_ROSTER_UPDATED","HS_TWINKS_UPDATED","HS_ACCOUNT_MAIN_CHANGED","HS_GUILD_MAIN_CHANGED","HS_TWINK_VISIBILITY_CHANGED"});HolyStorm.UI:AddNavigation("twinks",5,"Interface\\Icons\\INV_Misc_GroupLooking",L["NAVIGATION_TITLE"],L["NAVIGATION_DESCRIPTION"],function()Twinks:RequestAndRefresh();HolyStorm.UI:ShowPage("twinks")end)
end
function Twinks:OnInitialize()
 HolyStorm.TwinkCore:Initialize();HolyStorm.CharacterActions:Initialize();registerRichLinkTypes();HolyStorm.CharacterDirectory:Initialize("Twinks")
 HolyStorm:RegisterUIExtension("Twinks",{id="characters.twinks",order=5,initialize=function()Twinks:InitializeUI()end})
end
function Twinks:QueueCollection(trigger)
 HolyStorm.Tasks:Enqueue("character.identity",function()local character=Twinks:StoreCurrentCharacter();if character then HolyStorm.Data.PlayerStore:LinkLocalCharacter(character.guid)end end,{priority=1,debounce=.2})
 local capabilities={};for capability in pairs(HolyStorm.moduleCapabilities or{})do if capability:match("^character%.scan%.")then capabilities[#capabilities+1]=capability end end;table.sort(capabilities)
 for index,capability in ipairs(capabilities)do local current=capability;HolyStorm.Tasks:Enqueue("capability."..current,function()HolyStorm:CallCapability(current,false)end,{priority=index+1,debounce=.5+(index*.25),dependencies={"character.identity"},triggerSource=trigger})end
end
function Twinks:OnEnable()if not HolyStorm.CharacterDirectory.owner then HolyStorm.CharacterDirectory:Initialize("Twinks")end;HolyStorm.Events:Register("PLAYER_LOGIN","characters",function(event)Twinks:QueueCollection(event)end);HolyStorm.Events:Register("PLAYER_ENTERING_WORLD","characters",function(event)Twinks:QueueCollection(event)end);if IsLoggedIn()then self:QueueCollection("CHARACTERS_ENABLE")end end
function Twinks:OnDisable()HolyStorm.Events:UnregisterOwner("characters");HolyStorm.CharacterDirectory:Shutdown()end
function Twinks:RequestAndRefresh()self:StoreCurrentCharacter();if _G.GuildRoster then _G.GuildRoster()end;self:Refresh()end
function Twinks:Refresh()
 local core,accountUUID=HolyStorm.TwinkCore,HolyStorm.TwinkCore:GetLocalAccountUUID();local guild=HolyStorm.Data.GuildStore:GetCurrent();local visibility=core:GetVisibility(accountUUID);self.allRadio:SetChecked(visibility==core.visibility.ALL);self.guildRadio:SetChecked(visibility==core.visibility.GUILD_ONLY)
 local accountMain=core:GetAccountMain(accountUUID,guild);local guildMain,isShadow=core:GetGuildMain(accountUUID,guild);local characters=core:GetVisibleCharactersForViewer(accountUUID,guild);self.count:SetText(#characters>0 and string.format(L["MEMBER_COUNT"],#characters)or L["NO_CHARACTERS"]);for _,row in ipairs(self.rows)do row:Hide()end
 for index,character in ipairs(characters)do local row=self.rows[index];if not row then row=self:CreateRow(self.content);self.rows[index]=row end;row:ClearAllPoints();row:SetPoint("TOPLEFT",self.content,"TOPLEFT",0,-((index-1)*22));row:SetPoint("TOPRIGHT",self.content,"TOPRIGHT",0,-((index-1)*22));row.characterUUID=character.characterUUID
  local labels={};if character.characterUUID==accountMain then labels[#labels+1]=L["ACCOUNT_MAIN"]end;if character.characterUUID==guildMain then labels[#labels+1]=isShadow and L["SHADOW_MAIN"]or L["GUILD_MAIN"]end;local prefix=#labels>0 and("["..table.concat(labels,"/").."] ")or"";local classColor=RAID_CLASS_COLORS[character.classFile]or NORMAL_FONT_COLOR
  row.name:SetText(prefix..(character.fullName or character.name or L["UNKNOWN_VALUE"]));row.name:SetTextColor(classColor.r,classColor.g,classColor.b);row.class:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[character.classFile])or character.classFile or L["UNKNOWN_VALUE"]);row.level:SetText(character.level or L["UNKNOWN_VALUE"]);local inGuild=guild and guild.roster and guild.roster[character.characterUUID];row.guild:SetText(inGuild and L["IN_GUILD"]or L["NOT_IN_GUILD"]);row.guild:SetTextColor(inGuild and.25 or.7,inGuild and.9 or.7,inGuild and.25 or.7);row.source:SetText(character.relationship and character.relationship.source==core.sources.OWNER and L["OWNER_CONFIRMED"]or L["ADMINISTRATIVE"]);row:Show()
 end;self.content:SetHeight(math.max(1,#characters*22));self.mainButton:SetEnabled(self.selectedCharacterUUID and core:IsOwnerConfirmed(self.selectedCharacterUUID)or false)
end
end)
