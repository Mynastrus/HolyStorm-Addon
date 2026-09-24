local addonVersion="2.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local localeLibrary=LibStub("AceLocale-3.0",true)
local L=localeLibrary and localeLibrary.GetLocale and localeLibrary:GetLocale("Holy_Storm_CharacterUI")or setmetatable({},{__index=function(_,key)return key end})
local CharacterUI={version=addonVersion,tabs={},tabOrder={},summarySections={},summaryOrder={},context=nil,contextToken=0,history={},maxHistory=20,pendingRefreshBlocks={}}

CharacterUI.raidDifficulties={
 LFR={id="LFR",order=1,color={r=1,g=.82,b=0},difficultyIds={[7]=true,[17]=true}},
 NORMAL={id="NORMAL",order=2,color={r=.20,g=1,b=.20},difficultyIds={[14]=true}},
 HEROIC={id="HEROIC",order=3,color={r=.25,g=.55,b=1},difficultyIds={[15]=true}},
 MYTHIC={id="MYTHIC",order=4,color={r=.70,g=.30,b=1},difficultyIds={[16]=true}},
 TIMEWALKING={id="TIMEWALKING",order=5,color={r=.20,g=.80,b=1},difficultyIds={[33]=true}},
}

local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function validId(value)return type(value)=="string"and value~=""end
local unpack=unpack or table.unpack
local function className(classFile)return(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile])or(LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classFile])or classFile end
local function getClassColor(classFile)return(C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(classFile))or(RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])end
local classIconTexture="Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local classIconFallback="Interface\\Icons\\INV_Misc_QuestionMark"
local function classColoredName(context)
 local text=tostring(context and(context.fullName or context.name)or"");local classFile=context and context.classFile;local color=getClassColor(classFile);if not color then return text end
 if color.WrapTextInColorCode then return color:WrapTextInColorCode(text)end;local hex=color.GenerateHexColor and color:GenerateHexColor();if type(hex)=="string"and(#hex==6 or#hex==8)then return"|c"..(#hex==6 and"ff"or"")..hex..text.."|r"end;return string.format("|cff%02x%02x%02x%s|r",math.floor((color.r or 1)*255+.5),math.floor((color.g or 1)*255+.5),math.floor((color.b or 1)*255+.5),text)
end
local function shortName(value)return tostring(value or""):match("^([^%-]+)")or tostring(value or"")end
local function splitNameRealm(value)local name,realm=tostring(value or""):match("^([^%-]+)%-(.+)$");return name,realm end
local function factionIndicator(faction)
 if faction=="Horde"then return"|TInterface\\FriendsFrame\\PlusManz-Horde:14:14|t "..L["FACTION_HORDE"]elseif faction=="Alliance"then return"|TInterface\\FriendsFrame\\PlusManz-Alliance:14:14|t "..L["FACTION_ALLIANCE"]end
end

function CharacterUI:RegisterTab(definition)
 if type(definition)~="table"or not validId(definition.id)or type(definition.labelKey)~="string"or type(definition.build)~="function"or type(definition.refresh)~="function"then return false,"INVALID_CHARACTER_TAB"end
 local isNew=self.tabs[definition.id]==nil;self.tabs[definition.id]=definition
 if isNew then self.tabOrder[#self.tabOrder+1]=definition.id end
 table.sort(self.tabOrder,function(a,b)local x,y=self.tabs[a],self.tabs[b];if(x.order or 100)==(y.order or 100)then return a<b end;return(x.order or 100)<(y.order or 100)end);if isNew and HolyStorm.Events then HolyStorm.Events:Emit("HS_CHARACTER_TAB_REGISTERED",definition.id)end;return true
end
function CharacterUI:GetTabs()local out={};for _,id in ipairs(self.tabOrder)do out[#out+1]=self.tabs[id]end;return out end
function CharacterUI:GetTab(id)return self.tabs[id]end
function CharacterUI:RegisterSummarySection(definition)
 if type(definition)~="table"or not validId(definition.id)or type(definition.render)~="function"then return false,"INVALID_CHARACTER_SUMMARY_SECTION"end
 local isNew=self.summarySections[definition.id]==nil;self.summarySections[definition.id]=definition;if isNew then self.summaryOrder[#self.summaryOrder+1]=definition.id end
 table.sort(self.summaryOrder,function(a,b)local x,y=self.summarySections[a],self.summarySections[b];if(x.order or 100)==(y.order or 100)then return a<b end;return(x.order or 100)<(y.order or 100)end);if HolyStorm.Events then HolyStorm.Events:Emit("HS_CHARACTER_SUMMARY_SECTION_REGISTERED",definition.id)end;return true
end
function CharacterUI:GetSummarySections()local out={};for _,id in ipairs(self.summaryOrder)do out[#out+1]=self.summarySections[id]end;return out end
function CharacterUI:FormatState(value,state,options)
 local components=HolyStorm.UI and HolyStorm.UI.Components or HolyStorm.UIComponents
 return components and components:FormatState(value,state,options)or(value==nil and"|cff888888–|r"or tostring(value))
end
function CharacterUI:CreateTableView(parent,options)
 options=options or{};local components=assert(HolyStorm.UI and HolyStorm.UI.Components,"Holy Storm UI components unavailable")
 local layout=components:CreateColumn(parent,{gap=6,padding=options.padding or{left=8,right=8,top=8,bottom=8}})
 local summary=components:CreateText(layout.frame,{font=options.summaryFont or"GameFontNormalLarge",text="",align="LEFT",wrap=false})
 local dataTable=components:CreateTable(layout.frame,options)
 layout:Add(summary,{height=options.summaryHeight or 24});layout:Add(dataTable,{weight=1,minHeight=80})
 return{kind="declarative",frame=layout.frame,layout=layout,summary=summary,table=dataTable}
end
function CharacterUI:SetTableView(view,rows,options)
 options=options or{};if not(view and view.table)then return false end
 view.summary:SetText(options.summary or"");view.table:SetEmptyText(options.emptyText or self:FormatState(nil));view.table:SetData(type(rows)=="table"and rows or{});return true
end
function CharacterUI:ApplyClassIconTexture(texture,classFile)
 if not texture or not texture.SetTexture then return false end
 local coords=CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
 if coords then texture:SetTexture(classIconTexture);if texture.SetTexCoord then texture:SetTexCoord(unpack(coords))end;return true end
 texture:SetTexture(classIconFallback);if texture.SetTexCoord then texture:SetTexCoord(0,1,0,1)end;return false
end

function CharacterUI:ResolveContext(characterUUID)
 if not validId(characterUUID)then return nil end
 local record=HolyStorm.Data.CharacterStore:Get(characterUUID)or{guid=characterUUID};local guild=HolyStorm.Data.GuildStore:GetCurrent();local member=guild and guild.roster and guild.roster[characterUUID]
 local accountUUID=HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetAccountUUIDForCharacter(characterUUID)or HolyStorm.Data.PlayerStore:GetCharacterOwner(characterUUID);local classFile=record.classFile or(member and(member.classFile or member.classFileName))
 local rawName=record.name or(member and member.name)or characterUUID;local splitName,embeddedRealm=splitNameRealm(rawName);local name=splitName or rawName;local realm=record.realm or embeddedRealm
 local storedSpec=record.stats and record.stats.spec;local spec
 if type(storedSpec)=="table"then for _,key in ipairs({"id","name","icon","index","role"})do if storedSpec[key]~=nil then spec=spec or{};spec[key]=storedSpec[key]end end end
 return{characterUUID=characterUUID,guid=characterUUID,accountUUID=accountUUID,name=name,realm=realm,fullName=record.fullName or(rawName~=name and rawName or name),level=record.level or(member and member.level),classFile=classFile,className=record.class or(member and member.class)or className(classFile),spec=spec,guild=guild,member=member,record=record}
end
function CharacterUI:SetContext(characterUUID,addHistory)
 local context=self:ResolveContext(characterUUID);if not context then return nil end
 if addHistory~=false and self.context and self.context.characterUUID~=characterUUID then self.history[#self.history+1]={characterUUID=self.context.characterUUID,tabId=self.activeTab};while#self.history>self.maxHistory do table.remove(self.history,1)end end
 self.contextToken=self.contextToken+1;context.token=self.contextToken;self.context=context;return context
end
function CharacterUI:GetContext()return self.context end
function CharacterUI:IsCurrent(characterUUID,token)return self.context and self.context.characterUUID==characterUUID and(token==nil or self.contextToken==token)end
function CharacterUI:Back()local target=table.remove(self.history);if not target then return false end;return self:OpenCharacter(target.characterUUID,target.tabId,false)end

function CharacterUI:ShowTooltip(owner,characterUUID)
 local context=self:ResolveContext(characterUUID);if not context or not GameTooltip then return false end
 local record=context.record or{};local member=context.member;local main=context.accountUUID and HolyStorm.TwinkCore:GetRosterIdentity(characterUUID,context.guild)
 local title=shortName(context.fullName or context.name or characterUUID);local color=getClassColor(context.classFile);GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(title,color and color.r or 1,color and color.g or 1,color and color.b or 1)
 local clean={};local function add(part)if part and part~=""then clean[#clean+1]=tostring(part)end end;add(context.realm);add(context.className);add(context.level and((LEVEL or"Level").." "..context.level));add(member and member.rank);add(factionIndicator(record.faction));if#clean>0 then GameTooltip:AddLine(table.concat(clean," | "),1,1,1,false)end
 if main then local accountMain=main.accountMain and self:ResolveContext(main.accountMain);if accountMain then GameTooltip:AddLine(L["ACCOUNT_MAIN"]..": "..classColoredName(accountMain),.7,.85,1)end;if main.guildMain and main.guildMain~=main.accountMain then local guildMain=self:ResolveContext(main.guildMain);if guildMain then GameTooltip:AddLine(L[main.isShadowMain and"SHADOW_MAIN"or"GUILD_MAIN"]..": "..classColoredName(guildMain),.7,.85,1)end end end
 if record.itemLevel then GameTooltip:AddLine((ITEM_LEVEL or"Item level")..": "..tostring(record.itemLevel),.8,.8,.8)end
 GameTooltip:Show();return true
end

local storedSnapshotFields={equipment="equipment",mythicPlus="mythicPlus",raid="raidLockouts",delves="delves",stats="stats"}
function CharacterUI:GetSnapshot(characterUUID,blockId)
 local store=HolyStorm.Data.CharacterStore;local data,meta=store:GetBlock(characterUUID,blockId)
 if data==nil then local field=storedSnapshotFields[blockId];local record=field and store:Get(characterUUID);data=record and record[field];meta=store.GetBlockMetadata and store:GetBlockMetadata(characterUUID,blockId)or meta end
 if data==nil then return nil,meta end
 if blockId=="equipment"and type(data)=="table"and data.equipment~=nil then return data.equipment,meta end
 return data,meta
end
function CharacterUI:GetDataStatus(characterUUID,blockId)
 local data,meta=self:GetSnapshot(characterUUID,blockId);if not data then return"MISSING",nil end
 return HolyStorm.PlayerData:IsStale(characterUUID,blockId)and"STALE"or"CURRENT",meta
end
function CharacterUI:GetDifficultyById(difficultyId)
 for _,key in ipairs({"LFR","NORMAL","HEROIC","MYTHIC","TIMEWALKING"})do local definition=self.raidDifficulties[key];if definition.difficultyIds[tonumber(difficultyId)]then return definition end end
end
function CharacterUI:GetDifficultyColor(key)local d=self.raidDifficulties[key];return d and d.color end
function CharacterUI:ColorDifficulty(key,text)local c=self:GetDifficultyColor(key);return c and string.format("|cff%02x%02x%02x%s|r",math.floor(c.r*255+.5),math.floor(c.g*255+.5),math.floor(c.b*255+.5),tostring(text))or tostring(text)end

function CharacterUI:BuildRaidBestRows(snapshot)
 local result={};local lifetime=type(snapshot)=="table"and snapshot.lifetime
 for bossKey,boss in pairs(type(lifetime)=="table"and type(lifetime.bosses)=="table"and lifetime.bosses or{})do
  local best
  for _,key in ipairs({"LFR","NORMAL","HEROIC","MYTHIC"})do local entry=type(boss.difficulties)=="table"and boss.difficulties[key];local definition=self.raidDifficulties[key];local trusted=type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId);local kills=trusted and tonumber(entry.kills)or nil;if definition and kills and kills>0 then best={difficulty=key,order=definition.order,kills=kills}end end
  if best then result[#result+1]={bossId=boss.id or bossKey,bossIdStable=boss.id~=nil,bossName=boss.name or tostring(bossKey),raidInstanceId=boss.raidInstanceId or boss.journalInstanceId,raidName=boss.raidName,difficulty=best.difficulty,kills=best.kills,order=best.order}end
 end
 table.sort(result,function(a,b)return tostring(a.bossName)<tostring(b.bossName)end);return result
end
function CharacterUI:RaidIdentityMatches(value,identity)
 if identity==nil then return true end
 local wantedId=type(identity)=="table"and tonumber(identity.instanceId or identity.id or identity.journalInstanceId)or nil;local valueId=type(value)=="table"and tonumber(value.raidInstanceId or value.instanceId or value.id or value.journalInstanceId)or nil
 if wantedId and valueId then return wantedId==valueId end
 local wantedName=type(identity)=="table"and(identity.name or identity.raidName)or identity;local valueName=type(value)=="table"and(value.raidName or value.name)or value
 return type(wantedName)=="string"and type(valueName)=="string"and wantedName==valueName
end
function CharacterUI:GetBestProgress(snapshot,raidIdentity)
 local totals,seen={},{};local lifetime=type(snapshot)=="table"and snapshot.lifetime
 for bossKey,boss in pairs(type(lifetime)=="table"and type(lifetime.bosses)=="table"and lifetime.bosses or{})do if self:RaidIdentityMatches(boss,raidIdentity)then local identity=tostring(boss.raidInstanceId or boss.journalInstanceId or boss.raidName or"").."\031"..tostring(boss.id or boss.name or bossKey);for _,key in ipairs({"LFR","NORMAL","HEROIC","MYTHIC"})do local entry=type(boss.difficulties)=="table"and boss.difficulties[key];local trusted=type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId);local kills=trusted and tonumber(entry.kills)or nil;seen[key]=seen[key]or{};if kills and kills>0 and not seen[key][identity]then seen[key][identity]=true;totals[key]=(totals[key]or 0)+1 end end end end
 local best;for _,key in ipairs({"LFR","NORMAL","HEROIC","MYTHIC"})do if totals[key]and totals[key]>0 then best={difficulty=key,killed=totals[key],total=totals[key]}end end
 local total=0;for _,raid in ipairs(type(snapshot)=="table"and snapshot.raids or{})do if self:RaidIdentityMatches(raid,raidIdentity)then total=math.max(total,#(raid.bosses or{}))end end;if best then best.total=total>0 and total or best.killed end
 return best
end
function CharacterUI:CanUseTab(definition)
 if definition.permission and HolyStorm.Policy and not HolyStorm.Policy:Can(definition.permission)then return false,"PERMISSION"end
 if definition.moduleName and HolyStorm.IsOptionalModuleEnabled and not HolyStorm:IsOptionalModuleEnabled(definition.moduleName)then return false,"MODULE_DISABLED"end
 if definition.moduleId and HolyStorm.Policy and not HolyStorm.Policy:IsGuildModuleEnabled(definition.moduleId)then return false,"MODULE_DISABLED"end
 if definition.availability then local ok,available,reason=HolyStorm.Utils.SafeCall("character.tab.availability:"..definition.id,definition.availability,self.context);if not ok or available==false then return false,reason or"UNAVAILABLE"end end
 return true
end
function CharacterUI:RunRefresh(characterUUID,blocks)
 local wanted={};for _,block in ipairs(blocks or{})do wanted[block]=true end;local all=next(wanted)==nil
 if characterUUID==UnitGUID("player")then if all or wanted.identity then HolyStorm.Data.CharacterStore:CaptureCurrent()end;if all or wanted.equipment then HolyStorm:CallCapability("character.scan.equipment",true)end;if all or wanted.raid then HolyStorm:CallCapability("character.scan.raids",true)end;if all or wanted.mythicPlus then HolyStorm:CallCapability("character.scan.mythicplus",true)end;if all or wanted.delves then HolyStorm:CallCapability("character.scan.delves",true)end;if all or wanted.stats then HolyStorm:CallCapability("character.scan.stats",true)end;return true end
 return HolyStorm.Data.CharacterStore:RequestRefresh(characterUUID,blocks)
end
function CharacterUI:RequestRefresh(characterUUID,blocks,reason)
 characterUUID=characterUUID or(self.context and self.context.characterUUID);if not characterUUID then return false end
 local requested={};for _,block in ipairs(blocks or{})do if reason=="MANUAL"or self:GetDataStatus(characterUUID,block)~="CURRENT"then requested[#requested+1]=block end end;if#requested==0 then return true end
 local pending=self.pendingRefreshBlocks[characterUUID]or{};for _,block in ipairs(requested)do pending[block]=true end;self.pendingRefreshBlocks[characterUUID]=pending
 if HolyStorm.Tasks:GetTaskType("Character.Refresh")then return HolyStorm.Tasks:Queue("Character.Refresh",{mergeKey=characterUUID,metadata={characterUUID=characterUUID},triggerSource=reason or"CHARACTER_OPEN",debounce=.2})end
 self.pendingRefreshBlocks[characterUUID]=nil;return self:RunRefresh(characterUUID,requested)
end
function CharacterUI:ConsumeRefresh(characterUUID)
 local pending=self.pendingRefreshBlocks[characterUUID]or{};self.pendingRefreshBlocks[characterUUID]=nil;local blocks={};for block in pairs(pending)do blocks[#blocks+1]=block end;table.sort(blocks);return self:RunRefresh(characterUUID,blocks)
end

HolyStorm.CharacterUI=CharacterUI
if HolyStorm.FlushCharacterExtensions then HolyStorm:FlushCharacterExtensions()end
