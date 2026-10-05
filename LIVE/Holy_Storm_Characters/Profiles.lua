local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Twinks")
local Profiles = HolyStorm:RegisterRequiredModule("Profiles")

local visibilityOptions = {{value="PRIVATE",key="PROFILE_VISIBILITY_PRIVATE"},{value="GUILD",key="PROFILE_VISIBILITY_GUILD"},{value="PUBLIC",key="PROFILE_VISIBILITY_PUBLIC"}}
local weekdays = {{id="MONDAY",key="PROFILE_DAY_MONDAY"},{id="TUESDAY",key="PROFILE_DAY_TUESDAY"},{id="WEDNESDAY",key="PROFILE_DAY_WEDNESDAY"},{id="THURSDAY",key="PROFILE_DAY_THURSDAY"},{id="FRIDAY",key="PROFILE_DAY_FRIDAY"},{id="SATURDAY",key="PROFILE_DAY_SATURDAY"},{id="SUNDAY",key="PROFILE_DAY_SUNDAY"}}
local playTimes = {{id="MORNING",key="PROFILE_TIME_MORNING"},{id="MIDDAY",key="PROFILE_TIME_MIDDAY"},{id="EVENING",key="PROFILE_TIME_EVENING"},{id="NIGHT",key="PROFILE_TIME_NIGHT"}}
local playerTypes = {{id="CASUAL",key="PROFILE_TYPE_CASUAL"},{id="REGULAR",key="PROFILE_TYPE_REGULAR"},{id="ACTIVE",key="PROFILE_TYPE_ACTIVE"},{id="PROGRESS",key="PROFILE_TYPE_PROGRESS"}}
local classIds={WARRIOR=1,PALADIN=2,HUNTER=3,ROGUE=4,PRIEST=5,DEATHKNIGHT=6,SHAMAN=7,MAGE=8,WARLOCK=9,MONK=10,DRUID=11,DEMONHUNTER=12,EVOKER=13}
local fallbackSpecs={
 WARRIOR={{71,"DAMAGER","SPEC_ARMS"},{72,"DAMAGER","SPEC_FURY"},{73,"TANK","SPEC_PROTECTION"}},
 PALADIN={{65,"HEALER","SPEC_HOLY"},{66,"TANK","SPEC_PROTECTION"},{70,"DAMAGER","SPEC_RETRIBUTION"}},
 HUNTER={{253,"DAMAGER","SPEC_BEAST_MASTERY"},{254,"DAMAGER","SPEC_MARKSMANSHIP"},{255,"DAMAGER","SPEC_SURVIVAL"}},
 ROGUE={{259,"DAMAGER","SPEC_ASSASSINATION"},{260,"DAMAGER","SPEC_OUTLAW"},{261,"DAMAGER","SPEC_SUBTLETY"}},
 PRIEST={{256,"HEALER","SPEC_DISCIPLINE"},{257,"HEALER","SPEC_HOLY"},{258,"DAMAGER","SPEC_SHADOW"}},
 DEATHKNIGHT={{250,"TANK","SPEC_BLOOD"},{251,"DAMAGER","SPEC_FROST"},{252,"DAMAGER","SPEC_UNHOLY"}},
 SHAMAN={{262,"DAMAGER","SPEC_ELEMENTAL"},{263,"DAMAGER","SPEC_ENHANCEMENT"},{264,"HEALER","SPEC_RESTORATION"}},
 MAGE={{62,"DAMAGER","SPEC_ARCANE"},{63,"DAMAGER","SPEC_FIRE"},{64,"DAMAGER","SPEC_FROST"}},
 WARLOCK={{265,"DAMAGER","SPEC_AFFLICTION"},{266,"DAMAGER","SPEC_DEMONOLOGY"},{267,"DAMAGER","SPEC_DESTRUCTION"}},
 MONK={{268,"TANK","SPEC_BREWMASTER"},{270,"HEALER","SPEC_MISTWEAVER"},{269,"DAMAGER","SPEC_WINDWALKER"}},
 DRUID={{102,"DAMAGER","SPEC_BALANCE"},{103,"DAMAGER","SPEC_FERAL"},{104,"TANK","SPEC_GUARDIAN"},{105,"HEALER","SPEC_RESTORATION"}},
 DEMONHUNTER={{577,"DAMAGER","SPEC_HAVOC"},{581,"TANK","SPEC_VENGEANCE"}},
 EVOKER={{1467,"DAMAGER","SPEC_DEVASTATION"},{1468,"HEALER","SPEC_PRESERVATION"},{1473,"DAMAGER","SPEC_AUGMENTATION"}},
}
local accountFields={"realName","birthDate","country","city","playerType","playDays","playTimes"}
local legacyCharacterFields={preferredRole="preferredRole",alternateRoles="alternateRoles",raidInterest="raidInterest",mythicInterest="mythicInterest",delveInterest="delveInterest"}

HolyStorm:ApplyModuleMetadata(Profiles,{
 id="Profiles",displayName=L["PROFILE_NAV"],internalName="profiles",version=addonVersion,category="required",description=L["PROFILE_DESC"],permissions={"player-read"},dependencies={"core"},enabledByDefault=true,
 ruleFields={
  {id="profile.preferredRole",aliases={"preferredRole"},type="string",name=L["RULE_FIELD_PREFERRED_ROLE"],nameKey="RULE_FIELD_PREFERRED_ROLE",description=L["RULE_FIELD_PREFERRED_ROLE_DESC"],descriptionKey="RULE_FIELD_PREFERRED_ROLE_DESC",category=L["PROFILE_NAV"],dependencies={"profile"},resolver=function(context)local character=context and context.character;local guid=character and(character.characterUUID or character.guid);local field=guid and Profiles:GetVisibleCharacterField(guid,"preferredRole");return field and field.state=="VISIBLE"and field.value or nil end},
  {id="profile.raidInterest",type="string",name=L["RULE_FIELD_RAID_INTEREST"],nameKey="RULE_FIELD_RAID_INTEREST",description=L["RULE_FIELD_RAID_INTEREST_DESC"],descriptionKey="RULE_FIELD_RAID_INTEREST_DESC",category=L["PROFILE_NAV"],dependencies={"profile"},resolver=function(context)local character=context and context.character;local guid=character and(character.characterUUID or character.guid);local field=guid and Profiles:GetVisibleCharacterField(guid,"raidInterest");return field and field.state=="VISIBLE"and field.value or nil end},
 }
})

local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function trim(value)return HolyStorm.Utils.Trim(value or"")end
local function validVisibility(value)return value=="PRIVATE"or value=="GUILD"or value=="PUBLIC"end
local function visibility(value)return validVisibility(value)and value or"GUILD"end
local function field(value,level)return{value=copy(value),visibility=visibility(level)}end
local function dateValid(day,month,year)
 if type(day)~="number"or type(month)~="number"or type(year)~="number"or day%1~=0 or month%1~=0 or year%1~=0 or year<1000 or year>tonumber(date("%Y"))or month<1 or month>12 then return false end
 local days={31,28,31,30,31,30,31,31,30,31,30,31};if year%4==0 and(year%100~=0 or year%400==0)then days[2]=29 end
 return day>=1 and day<=days[month]
end
function Profiles:ParseLegacyBirthdate(value)
 if type(value)~="string"then return nil end
 local year,month,day=value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
 if not year then day,month,year=value:match("^(%d%d)%.(%d%d)%.(%d%d%d%d)$")end
 day,month,year=tonumber(day),tonumber(month),tonumber(year)
 if dateValid(day,month,year)then return{day=day,month=month,year=year}end
 return nil
end
function Profiles:MigrateAccountMetadata(metadata)
 metadata=type(metadata)=="table"and copy(metadata)or{};metadata.profileFields=type(metadata.profileFields)=="table"and metadata.profileFields or{}
 local aliases={realName={"realName","displayName"},country={"country"},city={"city","location"},playerType={"playerType"},playDays={"playDays"},playTimes={"playTimes"}}
 for id,names in pairs(aliases)do if type(metadata.profileFields[id])~="table"then for _,name in ipairs(names)do if metadata[name]~=nil then local value=metadata[name];if id=="country"then value=self:NormalizeCountryCode(value)or value end;metadata.profileFields[id]=field(value,"GUILD");break end end end end
 if type(metadata.profileFields.birthDate)~="table"and metadata.birthdate~=nil then local parsed=self:ParseLegacyBirthdate(metadata.birthdate);metadata.profileMigration=type(metadata.profileMigration)=="table"and metadata.profileMigration or{};if parsed then metadata.profileFields.birthDate=field(parsed,"GUILD");metadata.profileMigration.birthDate="MIGRATED"
  else local firstUnresolved=metadata.profileMigration.birthDate~="UNRESOLVED";metadata.profileMigration.birthDate="UNRESOLVED";if firstUnresolved then HolyStorm.Logger:Write("WARN","PlayerProfile","migration","Legacy birth date could not be parsed; original value retained",{migrationId="player-profile.birthdate.v1",accountUUID=HolyStorm.TwinkCore:GetLocalAccountUUID()})end end end
 for _,id in ipairs(accountFields)do local entry=metadata.profileFields[id];if type(entry)=="table"then entry.visibility=visibility(entry.visibility)end end
 return metadata
end
function Profiles:GetAccount()
 local account=HolyStorm.TwinkCore:GetAccount(HolyStorm.TwinkCore:GetLocalAccountUUID())or{};account.metadata=type(account.metadata)=="table"and account.metadata or{};return account
end
function Profiles:GetAccountField(id)
 local metadata=self:GetAccount().metadata;local entry=metadata.profileFields and metadata.profileFields[id]
 if type(entry)=="table"then return copy(entry.value),visibility(entry.visibility)end
 if id=="realName"then return metadata.realName or metadata.displayName,"GUILD"elseif id=="birthDate"then return self:ParseLegacyBirthdate(metadata.birthdate),"GUILD"elseif id=="country"then return metadata.country,"GUILD"elseif id=="city"then return metadata.city or metadata.location,"GUILD"end
 return nil,"GUILD"
end
function Profiles:GetCharacterProfile(guid)
 local character=HolyStorm.Data.CharacterStore:Get(guid);return character and type(character.profile)=="table"and character.profile or{}
end
function Profiles:GetCharacterField(guid,id)
 local profile=self:GetCharacterProfile(guid);local entry=profile.profileFields and profile.profileFields[id]
 if type(entry)=="table"then return copy(entry.value),visibility(entry.visibility)end
 return copy(profile[id]),"GUILD"
end
function Profiles:GetCountryName(code)
 return code and L.COUNTRIES and L.COUNTRIES[code]or code or""
end

function Profiles:GetSpecializations(classFile)
 classFile=type(classFile)=="string"and classFile:upper()or nil;if not classFile then return{}end
 local specs={};local classId=classIds[classFile]
 if classId and type(GetNumSpecializationsForClassID)=="function"and type(GetSpecializationInfoForClassID)=="function"then
  local ok,count=pcall(GetNumSpecializationsForClassID,classId)
  if ok and type(count)=="number"then for index=1,count do local success,id,name,_,icon,role=pcall(GetSpecializationInfoForClassID,classId,index);if success and type(id)=="number"then specs[#specs+1]={id=id,name=name or L["SPEC_"..id]or tostring(id),icon=icon,role=role}end end end
 end
 if #specs==0 then for _,entry in ipairs(fallbackSpecs[classFile]or{})do specs[#specs+1]={id=entry[1],role=entry[2],name=L[entry[3]],icon=nil}end end
 return specs
end
function Profiles:FormatRoles(roles)
 local labels={TANK=L["PROFILE_ROLE_TANK"],HEALER=L["PROFILE_ROLE_HEALER"],DAMAGER=L["PROFILE_ROLE_DAMAGER"]}
 local result={};for _,role in ipairs(roles or{})do result[#result+1]=labels[role]or role end;return table.concat(result,", ")
end
function Profiles:GetPreferredRoles(classFile,specIds)
 local selected={};for _,id in ipairs(type(specIds)=="table"and specIds or{})do selected[tonumber(id)or id]=true end
 local roles={};for _,spec in ipairs(self:GetSpecializations(classFile))do if selected[spec.id]and spec.role then roles[spec.role]=true end end
 local result={};for _,role in ipairs({"TANK","HEALER","DAMAGER"})do if roles[role]then result[#result+1]=role end end;return result
end

local function dropdown(parent,width,options,onSelect)
 local frame=CreateFrame("Frame",nil,parent,"UIDropDownMenuTemplate");UIDropDownMenu_SetWidth(frame,width)
 UIDropDownMenu_Initialize(frame,function(_,level)
  for _,option in ipairs(options)do local info=UIDropDownMenu_CreateInfo();info.text=option.label;info.value=option.value;info.func=function()UIDropDownMenu_SetSelectedValue(frame,option.value);UIDropDownMenu_SetText(frame,option.label);onSelect(option.value)end;UIDropDownMenu_AddButton(info,level)end
 end)
 frame.SetValue=function(_,value)local label=L["PROFILE_SELECT_NONE"];for _,option in ipairs(options)do if option.value==value then label=option.label;break end end;UIDropDownMenu_SetSelectedValue(frame,value or"");UIDropDownMenu_SetText(frame,label)end
 return frame
end
local function optional(label, value)return{label=label,value=value}end
function Profiles:VisibilityDropdown(parent,id,x,y)
 local options={};for _,entry in ipairs(visibilityOptions)do options[#options+1]=optional(L[entry.key],entry.value)end
 local frame=dropdown(parent,130,options,function(value)Profiles.visibilityEdits[id]=value end);frame:SetPoint("TOPLEFT",x,y);Profiles.visibilityMenus[id]=frame;return frame
end
local function makeLabel(parent,key,x,y,font)
 local value=parent:CreateFontString(nil,"OVERLAY",font or"GameFontNormalSmall");value:SetPoint("TOPLEFT",x,y);value:SetText(L[key]);return value
end
local function makeEdit(parent,x,y,width,maxLetters)
 local value=CreateFrame("EditBox",nil,parent,"InputBoxTemplate");value:SetPoint("TOPLEFT",x,y);value:SetSize(width,24);value:SetAutoFocus(false);value:SetMaxLetters(maxLetters or 160);return value
end
function Profiles:BuildUI()
 local UI=HolyStorm:GetModule("UI",true);local page=CreateFrame("Frame",nil,UI.content);local title=page:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge");title:SetPoint("TOPLEFT",18,-16);title:SetText(L["PROFILE_TITLE"])
 local scroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",14,-50);scroll:SetPoint("BOTTOMRIGHT",-30,14);local content=CreateFrame("Frame",nil,scroll);content:SetSize(850,1250);scroll:SetScrollChild(content)
 self.page,self.scroll,self.content=page,scroll,content;self.visibilityEdits={};self.visibilityMenus={};self.dayChecks={};self.timeChecks={};self.countryButtons={};self.characterRows={};self.specChecks={};self.pendingSpecs={};self.characterFieldEdits={};self.characterFieldRows={}
 makeLabel(content,"PROFILE_VOLUNTARY_NOTICE",18,-12,"GameFontNormal");makeLabel(content,"PROFILE_ACCOUNT",18,-40,"GameFontNormalLarge")
 makeLabel(content,"PROFILE_REAL_NAME",18,-78);self.realNameEdit=makeEdit(content,180,-72,360,120);self:VisibilityDropdown(content,"realName",635,-70)
 makeLabel(content,"PROFILE_BIRTHDATE",18,-120);local dayOptions={optional(L["PROFILE_DAY"],"")};for day=1,31 do dayOptions[#dayOptions+1]=optional(tostring(day),day)end;self.birthDay=dropdown(content,70,dayOptions,function(value)Profiles.birthDayValue=value end);self.birthDay:SetPoint("TOPLEFT",178,-112)
 local monthOptions={optional(L["PROFILE_MONTH"],"")};for month=1,12 do monthOptions[#monthOptions+1]=optional(L["PROFILE_MONTH_"..month],month)end;self.birthMonth=dropdown(content,120,monthOptions,function(value)Profiles.birthMonthValue=value end);self.birthMonth:SetPoint("TOPLEFT",255,-112);self.birthYearEdit=makeEdit(content,390,-108,90,4);self.birthYearEdit:SetNumeric(true);self:VisibilityDropdown(content,"birthDate",635,-110)
 makeLabel(content,"PROFILE_COUNTRY",18,-160);self.countrySearch=makeEdit(content,180,-154,260,80);self.countrySearch:SetScript("OnTextChanged",function(box,userInput)if userInput then Profiles.countryCode=nil;Profiles:UpdateCountryLabel()end;Profiles:UpdateCountryResults()end);self.countrySearch:SetScript("OnEditFocusGained",function()Profiles:UpdateCountryResults()end);self.countrySearch:SetScript("OnEditFocusLost",function()Profiles.countryResultFrame:Hide()end);self.countrySelected=content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");self.countrySelected:SetPoint("TOPLEFT",450,-158);self.countrySelected:SetWidth(160);self:VisibilityDropdown(content,"country",635,-152)
 self.countryResultFrame=CreateFrame("Frame",nil,content);self.countryResultFrame:SetPoint("TOPLEFT",180,-180);self.countryResultFrame:SetSize(420,120);self.countryResultFrame:Hide()
 for index=1,5 do local button=CreateFrame("Button",nil,self.countryResultFrame,"UIPanelButtonTemplate");button:SetSize(380,22);button:SetPoint("TOPLEFT",0,-(index-1)*23);button:SetScript("OnClick",function()Profiles.countryCode=button.countryCode;Profiles:UpdateCountryLabel();Profiles.countryResultFrame:Hide()end);self.countryButtons[index]=button end
 makeLabel(content,"PROFILE_CITY",18,-312);self.cityEdit=makeEdit(content,180,-306,360,120);self:VisibilityDropdown(content,"city",635,-304)
 makeLabel(content,"PROFILE_PLAYER_TYPE",18,-352);local typeOptions={optional(L["PROFILE_SELECT_NONE"],"")};for _,entry in ipairs(playerTypes)do typeOptions[#typeOptions+1]=optional(L[entry.key],entry.id)end;self.playerType=dropdown(content,220,typeOptions,function(value)Profiles.playerTypeValue=value end);self.playerType:SetPoint("TOPLEFT",170,-344);self:VisibilityDropdown(content,"playerType",635,-344)
 makeLabel(content,"PROFILE_PLAY_DAYS",18,-392);for index,entry in ipairs(weekdays)do local check=CreateFrame("CheckButton",nil,content,"UICheckButtonTemplate");check:SetSize(24,24);check:SetPoint("TOPLEFT",170+(index-1)*91,-390);check.text:SetText(L[entry.key]);check.id=entry.id;self.dayChecks[#self.dayChecks+1]=check end;self:VisibilityDropdown(content,"playDays",635,-388)
 makeLabel(content,"PROFILE_PLAY_TIMES",18,-430);for index,entry in ipairs(playTimes)do local check=CreateFrame("CheckButton",nil,content,"UICheckButtonTemplate");check:SetSize(24,24);check:SetPoint("TOPLEFT",170+(index-1)*115,-428);check.text:SetText(L[entry.key]);check.id=entry.id;self.timeChecks[#self.timeChecks+1]=check end;self:VisibilityDropdown(content,"playTimes",635,-426)
 makeLabel(content,"PROFILE_CHARACTERS",18,-474,"GameFontNormalLarge");makeLabel(content,"PROFILE_CHARACTER_TABLE_HINT",18,-498,"GameFontHighlightSmall")
 local headers={{"PROFILE_COLUMN_MAIN",18},{"PROFILE_COLUMN_CLASS",54},{"PROFILE_COLUMN_NAME",86},{"PROFILE_COLUMN_REALM",265},{"PROFILE_COLUMN_GUILD",405},{"PROFILE_COLUMN_SPECS",555}}
 for _,header in ipairs(headers)do makeLabel(content,header[1],header[2],-526,"GameFontNormal")end
 self.characterTableTop=-552
 self.emptyCharacters=content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");self.emptyCharacters:SetPoint("TOPLEFT",18,-560);self.emptyCharacters:SetText(L["NO_CHARACTERS"])
 self.specTitle=content:CreateFontString(nil,"OVERLAY","GameFontNormal");self.specTitle:SetPoint("TOPLEFT",18,-580);self.specTitle:SetText(L["PROFILE_PREFERRED_SPECS"])
 self.specHint=content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");self.specHint:SetPoint("TOPLEFT",18,-602);self.specHint:SetText(L["PROFILE_SPEC_HINT"])
 self.specHost=CreateFrame("Frame",nil,content);self.specHost:SetPoint("TOPLEFT",18,-628);self.specHost:SetSize(780,70);self:VisibilityDropdown(content,"preferredSpecs",635,-578)
 local roleRow={id="preferredRole",label=makeLabel(content,"PROFILE_PREFERRED_ROLE",18,0),edit=content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"),visibility=self:VisibilityDropdown(content,"preferredRole",635,0)};roleRow.edit:SetPoint("TOPLEFT",180,0);self.characterFieldRows[#self.characterFieldRows+1]=roleRow
 for index,definition in ipairs({{"alternateRoles","PROFILE_ALT_ROLES"},{"raidInterest","PROFILE_RAID"},{"mythicInterest","PROFILE_MYTHIC"},{"delveInterest","PROFILE_DELVES"}})do
  local id,key=definition[1],definition[2];local row={id=id,label=makeLabel(content,key,18,0),edit=makeEdit(content,180,0,360,120),visibility=self:VisibilityDropdown(content,id,635,0)}
  self.characterFieldEdits[id]=row.edit;self.characterFieldRows[#self.characterFieldRows+1]=row
 end
 self.birthWarning=content:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");self.birthWarning:SetWidth(800);self.birthWarning:SetJustifyH("LEFT");self.birthWarning:SetText(L["PROFILE_BIRTHDATE_LEGACY_UNRESOLVED"]);self.birthWarning:SetTextColor(1,.65,.2);self.birthWarning:Hide()
 self.status=content:CreateFontString(nil,"OVERLAY","GameFontNormal");self.status:SetPoint("TOPLEFT",18,-712);self.saveButton=CreateFrame("Button",nil,content,"UIPanelButtonTemplate");self.saveButton:SetSize(190,28);self.saveButton:SetPoint("TOPLEFT",18,-740);self.saveButton:SetText(L["PROFILE_SAVE"]);self.saveButton:SetScript("OnClick",function()local ok,reason=Profiles:Save();self.status:SetText(ok and L["PROFILE_SAVED"]or reason=="INVALID_BIRTHDATE"and L["PROFILE_INVALID_DATE"]or L["PROFILE_SAVE_FAILED"]);if not ok then HolyStorm.Logger:Write("WARN","PlayerProfile","validation","Profile save failed",{reason=reason})end end)
 HolyStorm.UI:RegisterPage("profiles",page,L["PROFILE_TITLE"],function()Profiles:Select(Profiles.selected or UnitGUID("player"));Profiles:RefreshCharacters()end,{"HS_PROFILE_UPDATED","HS_ACCOUNT_UPDATED","HS_ACCOUNT_MAIN_CHANGED"})
 HolyStorm.UI:AddNavigation("profiles",4,"Interface\\Icons\\Achievement_Character_Human_Male",L["PROFILE_NAV"],L["PROFILE_DESC"],function()HolyStorm.UI:ShowPage("profiles")end)
end
function Profiles:UpdateCountryLabel()
 self.countrySelected:SetText(self:GetCountryName(self.countryCode))
end
function Profiles:UpdateCountryResults()
 local query=trim(self.countrySearch:GetText()):lower();local countries=L.COUNTRIES or{};local matches={}
 if query==""then self.countryResultFrame:Hide();return end
 for code,name in pairs(countries)do if query==""or tostring(code):lower():find(query,1,true)or tostring(name):lower():find(query,1,true)then matches[#matches+1]={code=code,name=name}end end
 table.sort(matches,function(a,b)return a.name<b.name end);for index,button in ipairs(self.countryButtons)do local entry=matches[index];if entry then button.countryCode=entry.code;button:SetText(entry.name.." ("..entry.code..")");button:Show()else button:Hide()end end
 self.countryResultFrame:SetShown(#matches>0)
end
function Profiles:ReadBirthdate()
 local day,month=tonumber(self.birthDayValue),tonumber(self.birthMonthValue);local yearText=trim(self.birthYearEdit:GetText());local year=yearText==""and nil or tonumber(yearText)
 if not day and not month and not year then return nil end
 if not day or not month or not year or #yearText~=4 or not dateValid(day,month,year)then return false end
 return{day=day,month=month,year=year}
end
function Profiles:Select(guid)
 if type(guid)~="string"then return false end;self.selected=guid;local account=self:GetAccount();local day;local value
 self.legacyBirthdateUnresolved=account.metadata.profileMigration and account.metadata.profileMigration.birthDate=="UNRESOLVED"
 value=self:GetAccountField("realName");self.realNameEdit:SetText(type(value)=="string"and value or"")
 local birth;birth=self:GetAccountField("birthDate");self.birthDayValue=birth and birth.day;self.birthMonthValue=birth and birth.month;self.birthDay:SetValue(self.birthDayValue);self.birthMonth:SetValue(self.birthMonthValue);self.birthYearEdit:SetText(birth and tostring(birth.year)or"")
 value=self:GetAccountField("country");self.countryCode=self:NormalizeCountryCode(value);self.countrySearch:SetText("");self:UpdateCountryLabel();if value and not self.countryCode then self.countrySelected:SetText(tostring(value))end
 value=self:GetAccountField("city");self.cityEdit:SetText(type(value)=="string"and value or"")
 value=self:GetAccountField("playerType");self.playerTypeValue=value;local playerTypeLabel=L["PROFILE_SELECT_NONE"];for _,entry in ipairs(playerTypes)do if entry.id==value then playerTypeLabel=L[entry.key]end end;self.playerType:SetValue(value or"")
 local fields={realName="realName",birthDate="birthDate",country="country",city="city",playerType="playerType",playDays="playDays",playTimes="playTimes"}
 for id in pairs(fields)do local _,level=self:GetAccountField(id);self.visibilityEdits[id]=visibility(level);self.visibilityMenus[id]:SetValue(self.visibilityEdits[id])end
 self:LoadCharacterFields(guid)
 local days;days=self:GetAccountField("playDays");local selectedDays={};for _,item in ipairs(type(days)=="table"and days or{})do selectedDays[item]=true end;for _,check in ipairs(self.dayChecks)do check:SetChecked(selectedDays[check.id]==true)end
 local times;times=self:GetAccountField("playTimes");local selectedTimes={};for _,item in ipairs(type(times)=="table"and times or{})do selectedTimes[item]=true end;for _,check in ipairs(self.timeChecks)do check:SetChecked(selectedTimes[check.id]==true)end
 self:RefreshCharacters();return true
end
function Profiles:LoadCharacterFields(guid)
 for id,edit in pairs(self.characterFieldEdits)do local value,level=self:GetCharacterField(guid,id);edit:SetText(type(value)=="string"and value or"");self.visibilityEdits[id]=visibility(level);self.visibilityMenus[id]:SetValue(self.visibilityEdits[id])end
 for _,id in ipairs({"preferredRole","preferredSpecs"})do local _,level=self:GetCharacterField(guid,id);self.visibilityEdits[id]=visibility(level);self.visibilityMenus[id]:SetValue(self.visibilityEdits[id])end
end
function Profiles:GetCharacterRecord(guid)
 return HolyStorm.Data.CharacterStore:Get(guid)or{}
end
function Profiles:GetCharacterClassFile(guid)
 local account=HolyStorm.TwinkCore:GetAccount(HolyStorm.TwinkCore:GetLocalAccountUUID());local entry=account and account.characters[guid]or{}
 return entry.classFile or self:GetCharacterRecord(guid).classFile
end
function Profiles:GetAccountCharacters()
 local account=HolyStorm.TwinkCore:GetAccount(HolyStorm.TwinkCore:GetLocalAccountUUID());local list={}
 for guid,entry in pairs(account and account.characters or{})do if entry.relationship and entry.relationship.source==HolyStorm.TwinkCore.sources.OWNER then list[#list+1]={guid=guid,entry=entry}end end
 table.sort(list,function(a,b)local an=a.entry.fullName or a.entry.name or a.guid;local bn=b.entry.fullName or b.entry.name or b.guid;if a.guid==HolyStorm.TwinkCore:GetAccountMain(HolyStorm.TwinkCore:GetLocalAccountUUID())then return true elseif b.guid==HolyStorm.TwinkCore:GetAccountMain(HolyStorm.TwinkCore:GetLocalAccountUUID())then return false end;return an<bn end);return list
end
function Profiles:CharacterGuild(entry,record)
 local guildId=entry.guildId or record.guildId;local guild=guildId and HolyStorm.Data.GuildStore:Get(guildId)
 return guild and guild.name or record.guildName or record.guild or L["UNKNOWN_VALUE"]
end
function Profiles:ClassNameColor(classFile,name)
 local color=RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
 if not color then return name end
 return string.format("|cff%02x%02x%02x%s|r",math.floor(color.r*255),math.floor(color.g*255),math.floor(color.b*255),name)
end
function Profiles:GetSelectedSpecs(guid)
 local value=self.pendingSpecs[guid]
 if value==nil then value=self:GetCharacterField(guid,"preferredSpecs")end
 local selected={};for _,id in ipairs(type(value)=="table"and value or{})do selected[tonumber(id)or id]=true end
 local result={};for _,spec in ipairs(self:GetSpecializations(self:GetCharacterClassFile(guid)))do if selected[spec.id]then result[#result+1]=spec.id end end
 return result
end
function Profiles:FormatSpecs(guid,classFile)
 local selected={};for _,id in ipairs(self:GetSelectedSpecs(guid))do selected[tonumber(id)or id]=true end
 local names={};for _,spec in ipairs(self:GetSpecializations(classFile))do if selected[spec.id]then names[#names+1]=spec.name end end;return #names>0 and table.concat(names,", ")or L["PROFILE_NO_SPECS"]
end
function Profiles:RefreshCharacters()
 if not self.content then return end
 local chars=self:GetAccountCharacters()
 local accountUUID=HolyStorm.TwinkCore:GetLocalAccountUUID()
 local account=HolyStorm.TwinkCore:GetAccount(accountUUID)or{characters={}}
 local main=HolyStorm.TwinkCore:GetAccountMain(accountUUID)
 self.emptyCharacters:SetShown(#chars==0)
 for _,row in ipairs(self.characterRows)do row:Hide()end
 for index,item in ipairs(chars)do
  local guid,entry=item.guid,item.entry
  local row=self.characterRows[index]
  if not row then
   row=CreateFrame("Button",nil,self.content);row:SetSize(800,28)
   row.main=CreateFrame("Button",nil,row);row.main:SetSize(24,24);row.main:SetPoint("LEFT",15,0)
   row.mainIcon=row.main:CreateTexture(nil,"ARTWORK");row.mainIcon:SetAllPoints();row.mainIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
   row.icon=row:CreateTexture(nil,"ARTWORK");row.icon:SetSize(22,22);row.icon:SetPoint("LEFT",48,0)
   row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.name:SetPoint("LEFT",78,0);row.name:SetWidth(170);row.name:SetJustifyH("LEFT")
   row.realm=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.realm:SetPoint("LEFT",260,0);row.realm:SetWidth(130)
   row.guild=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.guild:SetPoint("LEFT",400,0);row.guild:SetWidth(145)
   row.specs=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");row.specs:SetPoint("LEFT",555,0);row.specs:SetWidth(235);row.specs:SetJustifyH("LEFT")
   self.characterRows[index]=row
  end
  row.guid=guid;row:ClearAllPoints();row:SetPoint("TOPLEFT",0,self.characterTableTop-(index-1)*30)
  row:SetScript("OnClick",function()Profiles.selected=guid;Profiles:LoadCharacterFields(guid);Profiles:RenderSpecOptions();Profiles:RefreshCharacters()end)
  row.main:SetScript("OnClick",function()local ok=HolyStorm.TwinkCore:SetAccountMain(guid);if ok then Profiles:RefreshCharacters()end end)
  row.main:SetScript("OnEnter",function(button)GameTooltip:SetOwner(button,"ANCHOR_RIGHT");GameTooltip:SetText(guid==main and L["PROFILE_ACCOUNT_MAIN"]or L["PROFILE_SET_ACCOUNT_MAIN"]);GameTooltip:Show()end)
  row.main:SetScript("OnLeave",function()GameTooltip:Hide()end)
  row.main:SetAlpha(guid==main and 1 or .35);row.main:SetEnabled(guid~=main)
  local record=self:GetCharacterRecord(guid)
  local classFile=entry.classFile or record.classFile
  local coords=classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
  row.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
  if coords then row.icon:SetTexCoord(coords[1],coords[2],coords[3],coords[4])else row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")end
  local name=entry.name or record.name or entry.fullName or guid
  row.name:SetText(self:ClassNameColor(classFile,name))
  row.realm:SetText(entry.realm or record.realm or L["UNKNOWN_VALUE"])
  row.guild:SetText(self:CharacterGuild(entry,record))
  row.specs:SetText(self:FormatSpecs(guid,classFile))
  row:Show()
 end
 self.selected=self.selected or UnitGUID("player")
 local selectedCharacter=self:GetCharacterRecord(self.selected)
 local selectedEntry=account.characters[self.selected]or{}
 self.specTitle:SetText(string.format(L["PROFILE_PREFERRED_SPECS_FOR"],selectedCharacter.name or selectedEntry.name or self.selected or""))
 self:RenderSpecOptions()
 local specStart=self.characterTableTop-(#chars*30)-38
 self.specTitle:ClearAllPoints();self.specTitle:SetPoint("TOPLEFT",18,specStart)
 self.specHint:ClearAllPoints();self.specHint:SetPoint("TOPLEFT",18,specStart-22)
 self.specHost:ClearAllPoints();self.specHost:SetPoint("TOPLEFT",18,specStart-46)
 local fieldStart=specStart-64-self.specHost:GetHeight()
 for index,row in ipairs(self.characterFieldRows)do
  local y=fieldStart-(index-1)*34
  row.label:ClearAllPoints();row.label:SetPoint("TOPLEFT",18,y)
  row.edit:ClearAllPoints();row.edit:SetPoint("TOPLEFT",180,y+6)
  row.visibility:ClearAllPoints();row.visibility:SetPoint("TOPLEFT",635,y+2)
 end
 local roles=self:GetPreferredRoles(self:GetCharacterClassFile(self.selected),self:GetSelectedSpecs(self.selected));local roleText=#roles>0 and self:FormatRoles(roles)or L["PROFILE_ROLE_NONE"]
 local legacyRole=self:GetCharacterField(self.selected,"preferredRole");local profile=self:GetCharacterProfile(self.selected)
 if profile.profileFields==nil or profile.profileFields.preferredSpecs==nil and self.pendingSpecs[self.selected]==nil then roleText=legacyRole or roleText end
 self.characterFieldRows[1].edit:SetText(roleText)
 self.visibilityMenus.preferredSpecs:ClearAllPoints();self.visibilityMenus.preferredSpecs:SetPoint("TOPLEFT",635,specStart+2)
 local saveY=fieldStart-#self.characterFieldRows*34-24
 if self.legacyBirthdateUnresolved then self.birthWarning:ClearAllPoints();self.birthWarning:SetPoint("TOPLEFT",18,saveY);self.birthWarning:Show();saveY=saveY-38 else self.birthWarning:Hide()end
 self.status:ClearAllPoints();self.status:SetPoint("TOPLEFT",18,saveY)
 self.saveButton:ClearAllPoints();self.saveButton:SetPoint("TOPLEFT",18,saveY-28)
 self.content:SetHeight(math.max(800,math.abs(saveY)+100))
end
function Profiles:RenderSpecOptions()
 if not self.specHost or not self.selected then return end
 for _,check in ipairs(self.specChecks)do check:Hide()end
 local classFile=self:GetCharacterClassFile(self.selected);local specs=self:GetSpecializations(classFile);local selected={};for _,id in ipairs(self:GetSelectedSpecs(self.selected))do selected[tonumber(id)or id]=true end
 for index,spec in ipairs(specs)do local check=self.specChecks[index];if not check then check=CreateFrame("CheckButton",nil,self.specHost,"UICheckButtonTemplate");check:SetSize(24,24);check.text:SetWidth(175);self.specChecks[index]=check end;check:ClearAllPoints();check:SetPoint("TOPLEFT",((index-1)%4)*190,-math.floor((index-1)/4)*26);check.text:SetText(spec.name);check:SetChecked(selected[spec.id]==true);check.specId=spec.id;check:SetScript("OnClick",function(button)local current={};for _,id in ipairs(Profiles:GetSelectedSpecs(Profiles.selected))do current[tonumber(id)or id]=true end;current[button.specId]=button:GetChecked()or nil;local values={};for _,available in ipairs(Profiles:GetSpecializations(classFile))do if current[available.id]then values[#values+1]=available.id end end;Profiles.pendingSpecs[Profiles.selected]=values;Profiles:RefreshCharacters()end);check:Show()end
 for index=#specs+1,#self.specChecks do self.specChecks[index]:Hide()end
 self.specHost:SetHeight(math.max(30,math.ceil(#specs/4)*26))
end

function Profiles:NormalizeCountryCode(code)
 if type(code)~="string"then return nil end
 local countries=L.COUNTRIES or{};local value=trim(code);local normalized=value:upper()
 if countries[normalized]then return normalized end
 for countryCode,name in pairs(countries)do if tostring(name):lower()==value:lower()then return countryCode end end
 return nil
end

function Profiles:Save()
 local birth=self:ReadBirthdate()
 if birth==false then return false,"INVALID_BIRTHDATE"end
 local guid=self.selected or UnitGUID("player")
 if type(guid)~="string"then return false,"NO_SELECTED_CHARACTER"end
 local account=self:GetAccount()
 local metadata=self:MigrateAccountMetadata(account.metadata)
 metadata.profileFields=type(metadata.profileFields)=="table"and metadata.profileFields or{}
 local function setAccountField(id,value)metadata.profileFields[id]=field(value,self.visibilityEdits[id])end
 local realName=trim(self.realNameEdit:GetText())
 setAccountField("realName",realName~=""and realName or nil)
 setAccountField("birthDate",birth)
 setAccountField("country",self:NormalizeCountryCode(self.countryCode))
 local city=trim(self.cityEdit:GetText())
 setAccountField("city",city~=""and city or nil)
 setAccountField("playerType",self.playerTypeValue~=""and self.playerTypeValue or nil)
 local days={};for _,check in ipairs(self.dayChecks)do if check:GetChecked()then days[#days+1]=check.id end end
 setAccountField("playDays",#days>0 and days or nil)
 local times={};for _,check in ipairs(self.timeChecks)do if check:GetChecked()then times[#times+1]=check.id end end
 setAccountField("playTimes",#times>0 and times or nil)
 HolyStorm.Data.PlayerStore:SetLocalMetadata(metadata)
 local profile=copy(self:GetCharacterProfile(guid))
 profile.profileFields=type(profile.profileFields)=="table"and profile.profileFields or{}
 local hadPreferredSpecs=profile.profileFields.preferredSpecs~=nil or self.pendingSpecs[guid]~=nil
 local preferredSpecs=self:GetSelectedSpecs(guid)
 profile.profileFields.preferredSpecs=field(preferredSpecs,self.visibilityEdits.preferredSpecs)
 for id,edit in pairs(self.characterFieldEdits)do
  local value=trim(edit:GetText())
  profile.profileFields[id]=field(value~=""and value or nil,self.visibilityEdits[id])
 end
 local legacyRole,legacyRoleVisibility=self:GetCharacterField(guid,"preferredRole")
 local hasPreferredSpecs=hadPreferredSpecs
 local roles=self:GetPreferredRoles(self:GetCharacterClassFile(guid),preferredSpecs)
 local preferredRole=#roles>0 and table.concat(roles,",")or nil
 if not hasPreferredSpecs and type(legacyRole)=="string"and legacyRole~=""then
  preferredRole=legacyRole
  self.visibilityEdits.preferredRole=self.visibilityEdits.preferredRole or legacyRoleVisibility
 end
 profile.profileFields.preferredRole=field(preferredRole,self.visibilityEdits.preferredRole)
 profile.preferredRole=preferredRole
 local committed,reason=HolyStorm.PlayerData:WriteOwnedBlock(guid,"profile",profile,"local")
 if committed==false and reason~="UNCHANGED"then return false,reason end
 self.pendingSpecs[guid]=nil
 HolyStorm.Events:Emit("HS_PROFILE_UPDATED",guid)
 HolyStorm.Events:Emit("HS_UI_STATUS_REQUESTED",L["PROFILE_SAVED"])
 self:RefreshCharacters()
 return true
end

function Profiles:SanitizeCharacterProfile(profile)
 local clean=copy(type(profile)=="table"and profile or{});local fields=type(clean.profileFields)=="table"and copy(clean.profileFields)or{}
 local aliases={preferredRole="preferredRole",alternateRoles="alternateRoles",raidInterest="raidInterest",mythicInterest="mythicInterest",delveInterest="delveInterest",preferredSpecs="preferredSpecs"}
 for key,id in pairs(aliases)do if type(fields[id])~="table"and clean[key]~=nil then fields[id]=field(clean[key],"GUILD")end;clean[key]=nil end
 for id,entry in pairs(fields)do entry=type(entry)=="table"and entry or field(entry,"GUILD");local level=visibility(entry.visibility);local value=entry.value
  if entry.state=="WITHHELD"then fields[id]={visibility=level,state="WITHHELD"}elseif level=="PRIVATE"then fields[id]={visibility=level,state=value~=nil and value~=""and"WITHHELD"or"EMPTY"}elseif value==nil or value==""or type(value)=="table"and next(value)==nil then fields[id]={visibility=level,state="EMPTY"}else fields[id]={visibility=level,state="SET",value=copy(value)}end
 end
 clean.profileFields=fields
 for id,entry in pairs(fields)do if entry.state=="SET"then clean[id]=copy(entry.value)else clean[id]=nil end end
 return clean
end
function Profiles:GetVisibleCharacterField(guid,id,viewerGuildId)
 local profile=self:GetCharacterProfile(guid);local entry=profile.profileFields and profile.profileFields[id]
 if type(entry)~="table"then if profile[id]==nil then return{state="NOT_ENTERED",visibility="GUILD"}end;entry={value=profile[id],visibility="GUILD"}end
 local level=visibility(entry.visibility);local value=entry.value;local empty=value==nil or value==""or type(value)=="table"and next(value)==nil
 if entry.state=="WITHHELD"then return{state="HIDDEN",visibility=level}end
 if level=="PRIVATE"then return{state=empty and"NOT_ENTERED"or"HIDDEN",visibility=level}end
 if level=="GUILD"then
  if viewerGuildId==nil then local guild=HolyStorm.Data.GuildStore:GetCurrent();viewerGuildId=guild and(guild.id or guild.guildId)end
  local accountUUID=HolyStorm.TwinkCore:GetAccountUUIDForCharacter(guid)
  if not accountUUID and HolyStorm.TwinkCore.IsOwnerConfirmed and HolyStorm.TwinkCore:IsOwnerConfirmed(guid)then accountUUID=HolyStorm.TwinkCore:GetLocalAccountUUID()end
  local account=accountUUID and HolyStorm.TwinkCore:GetAccount(accountUUID);local member=false
  for charGuid,identity in pairs(account and account.characters or{})do if viewerGuildId and identity.guildId==viewerGuildId then member=true;break end end
  local guild=viewerGuildId and HolyStorm.Data.GuildStore:Get(viewerGuildId);if guild and guild.roster and guild.roster[guid]then member=true end
  if not member then return{state=empty and"NOT_ENTERED"or"HIDDEN",visibility=level}end
 end
 return{state=empty and"NOT_ENTERED"or"VISIBLE",value=copy(value),visibility=level}
end
function Profiles:OnInitialize()
 local account=self:GetAccount();local migrated=self:MigrateAccountMetadata(account.metadata)
 if HolyStorm.Serializer:Serialize(migrated)~=HolyStorm.Serializer:Serialize(account.metadata or{})then HolyStorm.Data.PlayerStore:SetLocalMetadata(migrated)end
 HolyStorm.PlayerData:RegisterBlockExportSanitizer("profile","PlayerProfile",function(profile)return Profiles:SanitizeCharacterProfile(profile)end)
 HolyStorm:RegisterUIExtension("PlayerProfile",{id="characters.player-profile",order=4,initialize=function()Profiles:BuildUI();Profiles:Select(UnitGUID("player"))end})
end
function Profiles:OnDisable()if HolyStorm.UI and HolyStorm.UI.UnregisterPage then HolyStorm.UI:UnregisterPage("profiles")end;if HolyStorm.PlayerData then HolyStorm.PlayerData:UnregisterBlockExportSanitizer("profile","PlayerProfile")end end
HolyStorm.Profiles=Profiles
