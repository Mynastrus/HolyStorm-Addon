local addonVersion="2.0.2"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local localeLibrary=LibStub("AceLocale-3.0",true)
local L=localeLibrary and localeLibrary.GetLocale and localeLibrary:GetLocale("Holy_Storm_CharacterUI")or setmetatable({},{__index=function(_,key)return key end})
local CharacterUI={version=addonVersion,tabs={},tabOrder={},summarySections={},summaryOrder={},context=nil,contextToken=0,history={},maxHistory=20,pendingRefreshBlocks={},pendingRefreshOptions={},liveStats={}}

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
local function classColoredName(context,value)
 local text=tostring(value or(context and(context.fullName or context.name))or"");local classFile=context and context.classFile;local color=getClassColor(classFile);if not color then return text end
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
function CharacterUI:RequestTabData(characterUUID,tabId)
 local definition=self:GetTab(tabId);local sync=HolyStorm.Sync
 if not definition or not sync or not validId(characterUUID)then return false end
 local requested=false
 if characterUUID~=UnitGUID("player")and type(definition.blocks)=="table"and sync:GetDomain("character")then
  for _,block in ipairs(definition.blocks)do if type(block)=="string"and block~=""then requested=sync:Discover("character",characterUUID.."\031"..block,{reason="CHARACTER_OPEN",priorityClass="USER_INTERACTIVE",priority=35})~=nil or requested end end
 end
 if definition.syncDomain and sync:GetDomain(definition.syncDomain)then requested=sync:Discover(definition.syncDomain,definition.syncObjectId,{scope=definition.syncScope,reason="CHARACTER_TAB_OPEN",priorityClass="USER_INTERACTIVE",priority=35})~=nil or requested end
 return requested
end
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
 if GameTooltip and GameTooltip.Hide then GameTooltip:Hide()end
 if HolyStorm.Tooltips then HolyStorm.Tooltips:Release("raid-best")end
 if HolyStorm.Tooltips then HolyStorm.Tooltips:Release("raid-weekly")end
 if HolyStorm.Tooltips then HolyStorm.Tooltips:Release("mythicplus-best-run")end
 local context=self:ResolveContext(characterUUID);if not context then return nil end
 if addHistory~=false and self.context and self.context.characterUUID~=characterUUID then self.history[#self.history+1]={characterUUID=self.context.characterUUID,tabId=self.activeTab};while#self.history>self.maxHistory do table.remove(self.history,1)end end
 self.contextToken=self.contextToken+1;context.token=self.contextToken;self.context=context;return context
end
function CharacterUI:GetContext()return self.context end
function CharacterUI:IsCurrent(characterUUID,token)return self.context and self.context.characterUUID==characterUUID and(token==nil or self.contextToken==token)end
function CharacterUI:Back()local target=table.remove(self.history);if not target then return false end;return self:OpenCharacter(target.characterUUID,target.tabId,false)end

function CharacterUI:ShowTooltip(owner,characterUUID)
 local context=self:ResolveContext(characterUUID);if not context or not GameTooltip then return false end
 if GameTooltip.SetClampedToScreen then GameTooltip:SetClampedToScreen(true)end
 local record=context.record or{};local member=context.member;local main=context.accountUUID and HolyStorm.TwinkCore:GetRosterIdentity(characterUUID,context.guild)
 local title=shortName(context.fullName or context.name or characterUUID);GameTooltip:SetOwner(owner,"ANCHOR_CURSOR_RIGHT");GameTooltip:SetText(classColoredName(context,title))
 local clean={};local function add(part)if part and part~=""then clean[#clean+1]=tostring(part)end end;add(context.realm);add(context.className);add(context.level and((LEVEL or"Level").." "..context.level));add(member and member.rank);add(factionIndicator(record.faction));if#clean>0 then GameTooltip:AddLine(table.concat(clean," | "),1,1,1,false)end
 if main then local accountMain=main.accountMain and self:ResolveContext(main.accountMain);if accountMain then GameTooltip:AddLine(L["ACCOUNT_MAIN"]..": "..classColoredName(accountMain),.7,.85,1)end;if main.guildMain and main.guildMain~=main.accountMain then local guildMain=self:ResolveContext(main.guildMain);if guildMain then GameTooltip:AddLine(L[main.isShadowMain and"SHADOW_MAIN"or"GUILD_MAIN"]..": "..classColoredName(guildMain),.7,.85,1)end end end
 if record.itemLevel then GameTooltip:AddLine((ITEM_LEVEL or"Item level")..": "..tostring(record.itemLevel),.8,.8,.8)end
 GameTooltip:Show();return true
end

local storedSnapshotFields={equipment="equipment",mythicPlus="mythicPlus",raid="raidLockouts",delves="delves",stats="stats"}
local expectedSnapshotVersions={equipment=4,mythicPlus=5,raid=3,delves=3,stats=2}
function CharacterUI:GetSnapshot(characterUUID,blockId)
 local store=HolyStorm.Data.CharacterStore;local data,meta=store:GetBlock(characterUUID,blockId)
 if data==nil then local field=storedSnapshotFields[blockId];local record=field and store:Get(characterUUID);data=record and record[field];meta=store.GetBlockMetadata and store:GetBlockMetadata(characterUUID,blockId)or meta end
 if data==nil then return nil,meta end
 if blockId=="equipment"and type(data)=="table"and data.equipment~=nil then return data.equipment,meta end
 return data,meta
end
function CharacterUI:GetLiveStats(characterUUID)
 if not UnitGUID or characterUUID~=UnitGUID("player")then return nil end
 return self.liveStats[characterUUID]
end
function CharacterUI:SetLiveStats(characterUUID,snapshot)
 if not validId(characterUUID)or type(snapshot)~="table"or not UnitGUID or characterUUID~=UnitGUID("player")then return false end
 self.liveStats[characterUUID]=snapshot;return true
end
local function statusNumber(value)
 if issecretvalue then local ok,secret=pcall(issecretvalue,value);if not ok or secret then return nil end end
 local ok,number=pcall(tonumber,value);return ok and number or nil
end
local function statusCurrentValue(api,method)
 if type(api)~="table"or type(api[method])~="function"then return nil end
 local ok,value=pcall(api[method]);return ok and statusNumber(value)or nil
end
function CharacterUI:GetDataStatus(characterUUID,blockId,scope,snapshotSource)
 local data,meta
 if type(snapshotSource)=="table"then data,meta=snapshotSource.data,snapshotSource.meta else data,meta=self:GetSnapshot(characterUUID,blockId)end
 local runtime=HolyStorm.CharacterScans and HolyStorm.CharacterScans.GetRuntimeState and HolyStorm.CharacterScans:GetRuntimeState(characterUUID,blockId)
 if not data then if runtime and(runtime.state=="DIRTY"or runtime.state=="REFRESHING"or runtime.state=="ERROR")then return runtime.state,meta,runtime end;return"MISSING",meta end
 local snapshotVersion=expectedSnapshotVersions[blockId]
 if snapshotVersion and(type(data)~="table"or data.snapshotVersion~=snapshotVersion)then return"UNSUPPORTED",meta end
 if(blockId=="mythicPlus"or blockId=="delves"or blockId=="stats")and data.schemaVersion~=snapshotVersion then return"UNSUPPORTED",meta end
 local week
 if blockId=="mythicPlus"or blockId=="delves"or(blockId=="raid"and scope~="lifetime")then week=statusCurrentValue(C_DateAndTime,"GetWeeklyResetStartTime")end
 if blockId=="mythicPlus"then
  local season=statusCurrentValue(C_MythicPlus,"GetCurrentSeason");local storedSeason=statusNumber(data.seasonId)
  if not season or not storedSeason then return"UNKNOWN",meta,runtime,"SEASON_UNKNOWN"end
  if season and storedSeason and season~=storedSeason then return"STALE",meta,runtime,"SEASON"end
  local storedWeek=statusNumber(data.weeklyIdentity);if week and storedWeek and week~=storedWeek then return"STALE",meta,runtime,"WEEKLY"end
 elseif blockId=="delves"then
  local season=statusCurrentValue(C_DelvesUI,"GetCurrentDelvesSeasonNumber");local storedSeason=statusNumber(data.seasonNumber)
  if season and storedSeason and season~=storedSeason then return"STALE",meta,runtime,"SEASON"end
  local storedWeek=statusNumber(data.weeklyIdentity);if week and storedWeek and week~=storedWeek then return"STALE",meta,runtime,"WEEKLY"end
 elseif blockId=="raid"and scope~="lifetime"and week then
  local storedWeek=statusNumber(data.weeklyIdentity)
  if storedWeek and week~=storedWeek then return"STALE",meta,runtime,"WEEKLY"end
  local updatedAt=statusNumber(data.updatedAt or(meta and(meta.originCreatedAt or meta.updatedAt)))
  if not storedWeek and updatedAt and updatedAt<week then return"STALE",meta,runtime,"WEEKLY"end
 end
 if runtime and(runtime.state=="DIRTY"or runtime.state=="REFRESHING"or runtime.state=="ERROR")then return runtime.state,meta,runtime end
 return"CURRENT",meta,runtime
end
function CharacterUI:GetDifficultyById(difficultyId)
 for _,key in ipairs({"LFR","NORMAL","HEROIC","MYTHIC","TIMEWALKING"})do local definition=self.raidDifficulties[key];if definition.difficultyIds[tonumber(difficultyId)]then return definition end end
end
function CharacterUI:GetDifficultyColor(key)local d=self.raidDifficulties[key];return d and d.color end
function CharacterUI:ColorDifficulty(key,text)local c=self:GetDifficultyColor(key);return c and string.format("|cff%02x%02x%02x%s|r",math.floor(c.r*255+.5),math.floor(c.g*255+.5),math.floor(c.b*255+.5),tostring(text))or tostring(text)end

local lifetimeDifficulties={"LFR","NORMAL","HEROIC","MYTHIC"}
local function bestLifetimeKill(boss)
 local best;local allZero=true
 for _,key in ipairs(lifetimeDifficulties)do
  local entry=type(boss)=="table"and type(boss.difficulties)=="table"and boss.difficulties[key]
  local trusted=type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)~=nil
  local kills=trusted and tonumber(entry.kills)or nil
  if not kills then allZero=false
  elseif kills>0 then best={difficulty=key,kills=kills}
  elseif kills~=0 then allZero=false end
 end
 if best then return best end
 if allZero then return{kills=0}end
end
function CharacterUI:BuildRaidBestRows(snapshot,raidIdentity)
 local result={};local lifetime=type(snapshot)=="table"and snapshot.lifetime
 local lifetimeBosses=type(lifetime)=="table"and type(lifetime.bosses)=="table"and lifetime.bosses or{}
 for _,raid in ipairs(type(snapshot)=="table"and type(snapshot.raids)=="table"and snapshot.raids or{})do
  if self:RaidIdentityMatches(raid,raidIdentity)then
   local byId,byName={},{}
   for bossKey,boss in pairs(lifetimeBosses)do
    if type(boss)=="table"and self:RaidIdentityMatches(boss,raid)then
     local id=boss.id or(type(bossKey)=="number"and bossKey)
     if id then byId[tostring(id)]=boss end
     if boss.name then byName[boss.name]=boss end
    end
   end
   local ordered={}
   for index,boss in ipairs(type(raid.bosses)=="table"and raid.bosses or{})do ordered[#ordered+1]={boss=boss,index=index}end
   table.sort(ordered,function(a,b)local x,y=tonumber(a.boss.order)or a.index,tonumber(b.boss.order)or b.index;if x==y then return a.index<b.index end;return x<y end)
   for _,item in ipairs(ordered)do
    local catalogBoss=item.boss;local stored=catalogBoss.id~=nil and byId[tostring(catalogBoss.id)]or byName[catalogBoss.name]
    if not stored and catalogBoss.id~=nil then local named=byName[catalogBoss.name];if named and named.id==nil then stored=named end end
    local best=bestLifetimeKill(stored)
    result[#result+1]={bossId=catalogBoss.id,bossIdStable=catalogBoss.id~=nil,bossName=catalogBoss.name,raidInstanceId=raid.id,raidName=raid.name,difficulty=best and best.difficulty,kills=best and best.kills,order=tonumber(catalogBoss.order)or item.index}
   end
  end
 end
 return result
end
function CharacterUI:RaidIdentityMatches(value,identity)
 if identity==nil then return true end
 local wantedId=type(identity)=="table"and tonumber(identity.instanceId or identity.id or identity.journalInstanceId)or nil;local valueId=type(value)=="table"and tonumber(value.raidInstanceId or value.instanceId or value.id or value.journalInstanceId)or nil
 if wantedId and valueId then return wantedId==valueId end
 local wantedName=type(identity)=="table"and(identity.name or identity.raidName)or identity;local valueName=type(value)=="table"and(value.raidName or value.name)or value
 return type(wantedName)=="string"and type(valueName)=="string"and wantedName==valueName
end
function CharacterUI:GetBestProgress(snapshot,raidIdentity)
 if raidIdentity==nil then return self:GetBestCurrentRaidProgress(snapshot)end
 local raid
 for _,candidate in ipairs(type(snapshot)=="table"and type(snapshot.raids)=="table"and snapshot.raids or{})do if self:RaidIdentityMatches(candidate,raidIdentity)then raid=candidate;break end end
 if not raid then return nil end
 local totals={}
 for _,boss in ipairs(self:BuildRaidBestRows(snapshot,raid))do if boss.difficulty then totals[boss.difficulty]=(totals[boss.difficulty]or 0)+1 end end
 local best;for _,key in ipairs(lifetimeDifficulties)do if(totals[key]or 0)>0 then best={difficulty=key,killed=totals[key],total=#(raid.bosses or{})}end end
 return best
end
function CharacterUI:GetBestCurrentRaidProgress(snapshot)
 local best
 for index,raid in ipairs(type(snapshot)=="table"and type(snapshot.raids)=="table"and snapshot.raids or{})do
  local progress=self:GetBestProgress(snapshot,raid);local definition=progress and self.raidDifficulties[progress.difficulty]
  if progress and definition then
   local candidate={difficulty=progress.difficulty,killed=progress.killed,total=progress.total,raidName=raid.name,raidInstanceId=raid.id,raidOrder=raid.order or index,difficultyOrder=definition.order}
   if not best or candidate.difficultyOrder>best.difficultyOrder or(candidate.difficultyOrder==best.difficultyOrder and candidate.killed>best.killed)then best=candidate end
  end
 end
 return best
end
local function safeNumeric(value)
 if issecretvalue then local safe,secret=pcall(issecretvalue,value);if not safe or secret then return nil end end
 local converted,number=pcall(tonumber,value);return converted and number or nil
end
local function currentMythicPlusSeason()
 local api=C_MythicPlus;if not api or type(api.GetCurrentSeason)~="function"then return nil end
 local ok,value=pcall(api.GetCurrentSeason);return ok and safeNumeric(value)or nil
end
function CharacterUI:GetDashboardSummary(characterUUID)
 characterUUID=characterUUID or(UnitGUID and UnitGUID("player"));local context=characterUUID and self:ResolveContext(characterUUID)
 if not context then return nil end
 local equipment,equipmentMeta=self:GetSnapshot(characterUUID,"equipment");local mythicPlus,mythicMeta=self:GetSnapshot(characterUUID,"mythicPlus");local raid,raidMeta=self:GetSnapshot(characterUUID,"raid");local delves,delvesMeta=self:GetSnapshot(characterUUID,"delves");local stats,statsMeta=self:GetSnapshot(characterUUID,"stats")
 local equipmentV4=type(equipment)=="table"and equipment.snapshotVersion==4
 local itemLevel=equipmentV4 and safeNumeric(equipment.equippedItemLevel or equipment.itemLevel)or nil;if itemLevel and itemLevel<=0 then itemLevel=nil end
 local mythicPlusV5=type(mythicPlus)=="table"and mythicPlus.schemaVersion==5 and mythicPlus.snapshotVersion==5
 local storedSeason=mythicPlusV5 and safeNumeric(mythicPlus.seasonId)
 local mythicPlusStatus,_,_,mythicPlusStaleReason=self:GetDataStatus(characterUUID,"mythicPlus",nil,{data=mythicPlus,meta=mythicMeta})
 local rating=mythicPlusV5 and mythicPlusStaleReason~="SEASON"and mythicPlusStaleReason~="SEASON_UNKNOWN"and safeNumeric(mythicPlus.overallScore)or nil
 local lastUpdatedAt=0;for _,meta in ipairs({equipmentMeta or{},mythicMeta or{},raidMeta or{},delvesMeta or{},statsMeta or{}})do lastUpdatedAt=math.max(lastUpdatedAt,tonumber(meta.updatedAt)or 0)end
 local bestRaid=type(raid)=="table"and raid.snapshotVersion==3 and raid.catalogReady==true and self:GetBestCurrentRaidProgress(raid)or nil
 return{characterUUID=characterUUID,name=context.name,coloredName=classColoredName(context,context.name),classFile=context.classFile,className=context.className,specName=context.spec and context.spec.name,specIcon=context.spec and context.spec.icon,level=context.level,realm=context.realm,guildRank=context.member and context.member.rank,itemLevel=itemLevel,mythicPlusRating=rating,mythicPlusSeasonId=storedSeason,bestRaid=bestRaid,bestRaidRows=bestRaid and self:BuildRaidBestRows(raid,bestRaid)or{},equipment=equipment,mythicPlus=mythicPlus,raid=raid,delves=delves,stats=stats,snapshotStatus={equipment=self:GetDataStatus(characterUUID,"equipment",nil,{data=equipment,meta=equipmentMeta}),mythicPlus=mythicPlusStatus,raidLifetime=self:GetDataStatus(characterUUID,"raid","lifetime",{data=raid,meta=raidMeta}),delves=self:GetDataStatus(characterUUID,"delves",nil,{data=delves,meta=delvesMeta}),stats=self:GetDataStatus(characterUUID,"stats",nil,{data=stats,meta=statsMeta})},lastUpdatedAt=lastUpdatedAt>0 and lastUpdatedAt or nil}
end
function CharacterUI:CanUseTab(definition)
 if definition.permission and HolyStorm.Policy and not HolyStorm.Policy:Can(definition.permission)then return false,"PERMISSION"end
 if definition.moduleName and HolyStorm.IsOptionalModuleEnabled and not HolyStorm:IsOptionalModuleEnabled(definition.moduleName)then return false,"MODULE_DISABLED"end
 if definition.moduleId and HolyStorm.Policy and not HolyStorm.Policy:IsGuildModuleEnabled(definition.moduleId)then return false,"MODULE_DISABLED"end
 if definition.availability then local ok,available,reason=HolyStorm.Utils.SafeCall("character.tab.availability:"..definition.id,definition.availability,self.context);if not ok or available==false then return false,reason or"UNAVAILABLE"end end
 return true
end
function CharacterUI:RunRefresh(characterUUID,blocks,options)
 options=options or{};local reason=options.reason or"MANUAL"
 local wanted={};for _,block in ipairs(blocks or{})do wanted[block]=true end;local all=next(wanted)==nil
 if characterUUID==UnitGUID("player")then
  if all or wanted.identity then HolyStorm.Data.CharacterStore:CaptureCurrent()end
  local scans=HolyStorm.CharacterScans
  if scans then
   local declarations=scans:GetDeclarations();local producerBlocks={};local allProducers=#declarations>0
   for _,definition in ipairs(declarations)do if wanted[definition.block]then producerBlocks[#producerBlocks+1]=definition.block else allProducers=false end end
   if all or allProducers then return scans:RequestAll(reason,true)end
   if #producerBlocks==0 then return all or wanted.identity end
   return scans:RequestBlocks(producerBlocks,reason,true)
  end
  return false
 end
 options.force=reason=="MANUAL"or options.force==true;return HolyStorm.Data.CharacterStore:RequestRefresh(characterUUID,blocks,options)
end
function CharacterUI:RequestRefresh(characterUUID,blocks,reason)
 characterUUID=characterUUID or(self.context and self.context.characterUUID);if not characterUUID then return false end
 local requested={};for _,block in ipairs(blocks or{})do if reason=="MANUAL"or self:GetDataStatus(characterUUID,block)~="CURRENT"then requested[#requested+1]=block end end;if#requested==0 then return true end
 local pending=self.pendingRefreshBlocks[characterUUID]or{};for _,block in ipairs(requested)do pending[block]=true end;self.pendingRefreshBlocks[characterUUID]=pending
 local priorityClass=reason=="MANUAL"and"USER_INTERACTIVE"or"BACKGROUND_CATCHUP";local previous=self.pendingRefreshOptions[characterUUID];if not previous or priorityClass=="USER_INTERACTIVE"then self.pendingRefreshOptions[characterUUID]={reason=reason or"MANUAL",priorityClass=priorityClass,force=reason=="MANUAL"}end
 if HolyStorm.Tasks:GetTaskType("Character.Refresh")then return HolyStorm.Tasks:Queue("Character.Refresh",{mergeKey=characterUUID,metadata={characterUUID=characterUUID},triggerSource=reason or"MANUAL",debounce=.2,priority=reason=="MANUAL"and 15 or 30})end
 local options=self.pendingRefreshOptions[characterUUID];self.pendingRefreshBlocks[characterUUID]=nil;self.pendingRefreshOptions[characterUUID]=nil;return self:RunRefresh(characterUUID,requested,options)
end
function CharacterUI:ConsumeRefresh(characterUUID)
 local pending=self.pendingRefreshBlocks[characterUUID]or{};local options=self.pendingRefreshOptions[characterUUID];self.pendingRefreshBlocks[characterUUID]=nil;self.pendingRefreshOptions[characterUUID]=nil;local blocks={};for block in pairs(pending)do blocks[#blocks+1]=block end;table.sort(blocks);return self:RunRefresh(characterUUID,blocks,options)
end

HolyStorm.CharacterUI=CharacterUI
if HolyStorm.Events and type(HolyStorm.Events.Register)=="function"then HolyStorm.Events:Register("HS_STATS_LIVE_UPDATED","character-ui-live-stats",function(_,guid,snapshot)if CharacterUI:SetLiveStats(guid,snapshot)then HolyStorm.Events:Emit("HS_CHARACTER_LIVE_STATS_UPDATED",guid)end end)end
if HolyStorm.FlushCharacterExtensions then HolyStorm:FlushCharacterExtensions()end
