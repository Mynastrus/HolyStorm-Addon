local addonVersion="5.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm");local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Raids")
if HolyStorm.PermissionRegistry then HolyStorm.PermissionRegistry:RegisterLegacyAlias("raids.read","raids-read")end
if HolyStorm.PlayerData then HolyStorm.PlayerData:RegisterBlock("raid",{fields={"raidLockouts"},event="HS_RAIDLOCKS_UPDATED",staleAfter=21600})end
local metadata={id="raids",name="Raids",displayName=L["DISPLAY_NAME"],description=L["DESCRIPTION"],version=addonVersion,moduleType="feature",category="feature",permissions={{id="raids-read",category="Raid",defaults={member=true}},"sync-send"},dependencies={"core","synchronization"},capabilities={"character.scan.raids"},ui={characterTab="raid"},data={block="raid",snapshotType="raids",schemaVersion=3,capability="character.scan.raids"},sync={domains={"character"}},enabledByDefault=true,ruleFields={{id="raid.progress",aliases={"raidProgress"},type="number",name=L["RULE_FIELD_PROGRESS"],nameKey="RULE_FIELD_PROGRESS",description=L["RULE_FIELD_PROGRESS_DESC"],descriptionKey="RULE_FIELD_PROGRESS_DESC",category=L["DISPLAY_NAME"],dependencies={"raid"},unit="bosses",resolver=function(context)local block=context.character and context.character.raid or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID,"raid");local progress=block and block.bestProgress;return progress and tonumber(progress.killed)or nil end}}}
HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 local difficultyKeys={[7]="LFR",[17]="LFR",[14]="NORMAL",[15]="HEROIC",[16]="MYTHIC",[33]="TIMEWALKING"};local difficultyOrder={LFR=1,NORMAL=2,HEROIC=3,MYTHIC=4,TIMEWALKING=5}
 local lifetimeDifficultyIds={LFR=17,NORMAL=14,HEROIC=15,MYTHIC=16};local lifetimeDifficultyOrder={"LFR","NORMAL","HEROIC","MYTHIC"}
 local function raidKey(name)return type(name)=="string"and name:lower():gsub("[%s%p%c]+","")or nil end
 local requiredJournalAPIs={{"EJ_GetNumTiers","tier enumeration"},{"EJ_SelectTier","tier selection"},{"EJ_GetInstanceByIndex","instance enumeration"},{"EJ_SelectInstance","instance selection"},{"EJ_GetEncounterInfoByIndex","encounter enumeration"},{"EJ_GetInstanceInfo","instance metadata"}}
 local function readJournalAPIs()
  local api={};for _,definition in ipairs(requiredJournalAPIs)do local name,label=definition[1],definition[2];local fn=_G[name];if type(fn)~="function"then return nil,"Raid catalog unavailable: missing EJ "..label.." API",name end;api[name]=fn end
  api.EJ_GetCurrentTier=type(EJ_GetCurrentTier)=="function"and EJ_GetCurrentTier or nil;api.EJ_GetCreatureInfo=type(EJ_GetCreatureInfo)=="function"and EJ_GetCreatureInfo or nil;return api
 end
 local function ensureEncounterJournal()
  local api,reason,missing=readJournalAPIs();if api then return api end
  local loader=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn;if type(loader)=="function"then pcall(loader,"Blizzard_EncounterJournal")end
  api,reason,missing=readJournalAPIs();if api then return api end
  HolyStorm.Logger:Write("WARN","Raids","catalog",reason,{reason="MISSING_ENCOUNTER_JOURNAL_API",api=missing,addon="Blizzard_EncounterJournal"});return nil,reason
 end
 function Module:GetCharacterSnapshot(guid)return HolyStorm.Data.CharacterStore:GetBlock(guid,"raid"),HolyStorm.Data.CharacterStore:GetBlockMetadata(guid,"raid")end
 function Module:GetLatestRaid()
  local raids,tier=self:GetCurrentRaidCatalog();local raid=raids and raids[1];return raid and{id=raid.id,name=raid.name,tier=tier}or nil
 end
 local function readRaidTier(api,tier)
  api.EJ_SelectTier(tier);local raids={};local index=1
  while true do local id,name,_,_,buttonImage=api.EJ_GetInstanceByIndex(index,true);if not id then break end;local raid={id=id,name=name,icon=buttonImage,tier=tier,order=index,bosses={}};api.EJ_SelectInstance(id);local shouldDisplayDifficulty=select(9,api.EJ_GetInstanceInfo());raid.shouldDisplayDifficulty=shouldDisplayDifficulty;if shouldDisplayDifficulty~=false then local encounterIndex=1;while true do local bossName,_,bossId=api.EJ_GetEncounterInfoByIndex(encounterIndex,id);if not bossName then break end;local boss={id=bossId or encounterIndex,name=bossName,order=encounterIndex,creatureIds={}};if api.EJ_GetCreatureInfo and bossId then local creatureIndex=1;while true do local creatureId=api.EJ_GetCreatureInfo(creatureIndex,bossId);if not creatureId then break end;boss.creatureIds[#boss.creatureIds+1]=creatureId;creatureIndex=creatureIndex+1 end end;raid.bosses[#raid.bosses+1]=boss;encounterIndex=encounterIndex+1 end;raids[#raids+1]=raid end;index=index+1 end
  return raids
 end
 function Module:GetCurrentRaidCatalog()
  local api,reason=ensureEncounterJournal();if not api then return nil,nil,false,reason end;local ok,raids,tier=pcall(function()local current=api.EJ_GetNumTiers();if not current or current<1 then return{},current end;local previousTier=api.EJ_GetCurrentTier and api.EJ_GetCurrentTier();local currentRaids=readRaidTier(api,current);if previousTier and previousTier~=current then api.EJ_SelectTier(previousTier)end;return currentRaids,current end)
  if not ok then reason="Raid catalog unavailable: Encounter Journal scan failed";HolyStorm.Logger:Write("WARN","Raids","catalog",reason,{reason="ENCOUNTER_JOURNAL_SCAN_FAILED",error=tostring(raids)});return nil,nil,false,reason end
  if not tier or tier<1 or#raids==0 then reason="Raid catalog unavailable: Encounter Journal data pending";HolyStorm.Logger:Write("DEBUG","Raids","catalog",reason,{reason="ENCOUNTER_JOURNAL_PENDING",tier=tier,raidCount=#raids});return nil,tier,false,reason end
  return raids,tier,true
 end
 function Module:GetRaidJournalIndex()
  local api,reason=ensureEncounterJournal();if not api then return nil,reason end;local ok,result=pcall(function()local previousTier=api.EJ_GetCurrentTier and api.EJ_GetCurrentTier();local byName={};for tier=1,(api.EJ_GetNumTiers()or 0)do for _,raid in ipairs(readRaidTier(api,tier))do local key=raidKey(raid.name);if key then byName[key]=raid end end end;if previousTier then api.EJ_SelectTier(previousTier)end;return byName end)
  if not ok then reason="Raid catalog unavailable: Encounter Journal index scan failed";HolyStorm.Logger:Write("WARN","Raids","catalog",reason,{reason="ENCOUNTER_JOURNAL_INDEX_FAILED",error=tostring(result)});return nil,reason end;return result
 end
 local function statisticValue(raw)
  if type(raw)=="number"then return raw>=0 and raw or nil end;if type(raw)~="string"or raw==""or raw=="--"then return nil end
  local digits=raw:gsub("[^%d]","");local value=digits~=""and tonumber(digits)or nil;return value and value>=0 and value or nil
 end
 function Module:GetLifetimeStatisticCandidates()
  if self.lifetimeStatisticCandidates then return self.lifetimeStatisticCandidates end
  if type(GetStatisticsCategoryList)~="function"or type(GetCategoryNumAchievements)~="function"or type(GetStatistic)~="function"or type(GetAchievementInfo)~="function"or type(GetAchievementNumCriteria)~="function"or type(GetAchievementCriteriaInfo)~="function"then return nil,"STATISTIC_API_UNAVAILABLE"end
  local categories=GetStatisticsCategoryList();if type(categories)~="table"then return nil,"STATISTIC_CATEGORIES_UNAVAILABLE"end
  local result,seen={},{}
  for _,categoryId in ipairs(categories)do local countOk,count=pcall(GetCategoryNumAchievements,categoryId);if countOk then for index=1,tonumber(count)or 0 do local statOk,_,skip,statisticId=pcall(GetStatistic,categoryId,index);if statOk and not skip and tonumber(statisticId)and not seen[statisticId]then seen[statisticId]=true;local criteriaOk,criteriaCount=pcall(GetAchievementNumCriteria,statisticId);if criteriaOk and criteriaCount==1 then local info={pcall(GetAchievementInfo,statisticId)};local criteria={pcall(GetAchievementCriteriaInfo,statisticId,1)};local name=info[1]and info[3];local criteriaType=criteria[1]and criteria[3];local assetId=criteria[1]and tonumber(criteria[9]);if type(name)=="string"and criteriaType==0 and assetId then result[#result+1]={statisticId=tonumber(statisticId),name=name,assetId=assetId}end end end end end end
  self.lifetimeStatisticCandidates=result;return result
 end
 function Module:CaptureLifetime(raids,previous)
  local lifetime=HolyStorm.Utils.DeepCopy(type(previous)=="table"and previous or{bosses={},seen={}});lifetime.bosses=type(lifetime.bosses)=="table"and lifetime.bosses or{};lifetime.seen=type(lifetime.seen)=="table"and lifetime.seen or{}
  local candidates,candidateReason=self:GetLifetimeStatisticCandidates();local difficultyNames={};if type(GetDifficultyInfo)=="function"then for key,id in pairs(lifetimeDifficultyIds)do local ok,name=pcall(GetDifficultyInfo,id);if ok and type(name)=="string"then difficultyNames[key]=name end end end
  for _,raid in ipairs(raids or{})do for _,boss in ipairs(raid.bosses or{})do local creatures={};for _,id in ipairs(boss.creatureIds or{})do creatures[tonumber(id)]=true end;for _,difficulty in ipairs(lifetimeDifficultyOrder)do
    local matches={};local difficultyName=difficultyNames[difficulty];if candidates and difficultyName and next(creatures)then local bossToken,raidToken,difficultyToken=raidKey(boss.name),raidKey(raid.name),raidKey(difficultyName);for _,candidate in ipairs(candidates)do local nameToken=raidKey(candidate.name);if creatures[candidate.assetId]and nameToken and bossToken and raidToken and difficultyToken and nameToken:find(bossToken,1,true)and nameToken:find(raidToken,1,true)and nameToken:find(difficultyToken,1,true)then matches[#matches+1]=candidate end end end
    local candidate=#matches==1 and matches[1]or nil;local raw,kills,accepted,why
    if not candidates then why=candidateReason elseif not difficultyName then why="DIFFICULTY_NAME_UNAVAILABLE"elseif not next(creatures)then why="CREATURE_MAPPING_UNAVAILABLE"elseif#matches==0 then why="NO_EXACT_STATISTIC"elseif#matches>1 then why="AMBIGUOUS_STATISTIC"else local ok,value=pcall(GetStatistic,candidate.statisticId);raw=ok and value or nil;kills=ok and statisticValue(value)or nil;accepted=kills~=nil;why=accepted and"ACCEPTED"or"STATISTIC_VALUE_UNAVAILABLE"end
    if accepted then local key=boss.id or boss.name;local stored=lifetime.bosses[key]or{};stored.id=boss.id;stored.encounterId=boss.id;stored.name=boss.name;stored.raidInstanceId=raid.id;stored.journalInstanceId=raid.id;stored.raidName=raid.name;stored.difficulties=type(stored.difficulties)=="table"and stored.difficulties or{};stored.difficulties[difficulty]={statisticId=candidate.statisticId,kills=kills,source="blizzard-statistic"};lifetime.bosses[key]=stored end
    HolyStorm.Logger:Write("DEBUG","Raids","lifetime","RAID_LIFETIME_STAT",{raidInstanceId=raid.id,raidName=raid.name,bossId=boss.id,bossName=boss.name,difficulty=difficulty,statisticId=candidate and candidate.statisticId or 0,value=raw or"UNKNOWN",accepted=accepted==true,reason=why})
   end end end
  local reliable=false;for _,boss in pairs(lifetime.bosses)do for _,entry in pairs(type(boss)=="table"and type(boss.difficulties)=="table"and boss.difficulties or{})do if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)then reliable=true;break end end;if reliable then break end end
  lifetime.reliable=reliable;lifetime.source=reliable and"blizzard-statistic"or(lifetime.source or"legacy-local-observation");return lifetime
 end
 function Module:Collect()
  local raids,tier,catalogReady,reason=self:GetCurrentRaidCatalog();if not catalogReady then return{pending=true,pendingReason=reason or"raid catalog pending"}end;local journalByName,indexReason=self:GetRaidJournalIndex();if not journalByName then return{pending=true,pendingReason=indexReason or"raid catalog pending"}end;local latest=raids[1]and{id=raids[1].id,name=raids[1].name,tier=tier}or nil
  local old=self:GetCharacterSnapshot(UnitGUID("player"));local lifetime=self:CaptureLifetime(raids,type(old)=="table"and old.lifetime)
  local s={currentRaid=latest,currentTier=tier,catalogReady=catalogReady,raids=raids,lockouts={},lifetime=lifetime,updatedAt=HolyStorm.Utils.Now(),snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}
  for i=1,(GetNumSavedInstances and GetNumSavedInstances()or 0)do
   local name,id,reset,diff,locked,extended,_,isRaid,maxPlayers,diffName,encounters,encounterProgress=GetSavedInstanceInfo(i)
   if isRaid and locked then
    local bosses,killed={},0
    for x=1,encounters or 0 do
     local bossName,bossId,done=GetSavedInstanceEncounterInfo(i,x);bossName=bossName or((name or L["UNKNOWN"]).." #"..x);bossId=bossId or(name..":"..x);bosses[x]={name=bossName,id=bossId,killed=done==true}
     if done then killed=killed+1 end
    end
    killed=math.max(killed,tonumber(encounterProgress)or 0);local catalog=journalByName[raidKey(name)];local isCurrent=catalog and tonumber(catalog.tier)==tonumber(tier);local item={name=name,lockoutId=id,journalInstanceId=catalog and catalog.id,reset=reset,difficultyId=diff,difficultyName=diffName,extended=extended,maxPlayers=maxPlayers,bosses=bosses,killed=killed,total=encounters or 0,isCurrent=isCurrent==true};s.lockouts[#s.lockouts+1]=item
    local currentKey=difficultyKeys[tonumber(diff)];local bestKey=difficultyKeys[tonumber(s.bestProgress.difficultyId)];local currentOrder,bestOrder=difficultyOrder[currentKey]or 0,difficultyOrder[bestKey]or 0;if item.isCurrent and killed>0 and(currentOrder>bestOrder or(currentOrder==bestOrder and killed>s.bestProgress.killed))then s.bestProgress={killed=killed,total=encounters or 0,difficultyId=diff,difficultyName=diffName,raidInstanceId=item.journalInstanceId,raidName=item.name}end
   end
  end
  return s
 end
 function Module:Validate(s)if type(s)=="table"and s.pending then return false,s.pendingReason or"raid catalog pending"end;if type(s)~="table"or type(s.lockouts)~="table"or type(s.raids)~="table"or type(s.lifetime)~="table"or type(s.lifetime.bosses)~="table"then return false,"instance data unavailable"end;for _,r in ipairs(s.lockouts)do if not r.name or not r.difficultyId or type(r.bosses)~="table"then return false,"lockout incomplete"end end;if not s.catalogReady then return false,"raid catalog pending"end;return true end
 function Module:Commit(s)local guid=UnitGUID("player");return HolyStorm.PlayerData:WriteOwnedBlock(guid,"raid",s,"blizzard")end
 function Module:Queue(sync,delay,requestRaidInfo)
  -- UPDATE_INSTANCE_INFO is the response to RequestRaidInfo(). Requesting the
  -- data again from that event creates a loop and keeps extending the debounce.
  if requestRaidInfo~=false and RequestRaidInfo then RequestRaidInfo()end
  return HolyStorm.Snapshots:Queue("raids",function()return Module:Collect()end,function(s)return Module:Validate(s)end,function(s,f)return Module:Commit(s,f,sync)end,{source="Raids",delay=delay or 1,retryDelay=2.5,priority=3})
 end
 function Module:RefreshPage()if not self.page or not self.page:IsShown()then return end;local r=HolyStorm.Data.CharacterStore:Get(UnitGUID("player"));local d=r and r.raidLockouts;local lines={};for _,raid in ipairs(d and d.lockouts or{})do lines[#lines+1]=string.format("%s — %s (%d/%d)",raid.name or L["UNKNOWN"],raid.difficultyName or"",raid.killed or 0,raid.total or 0)end;self.content:SetText(#lines>0 and table.concat(lines,"\n")or L["NO_LOCKOUTS"])end
 function Module:OnInitialize()
  HolyStorm.CharacterScans:RegisterProvider("Raids",{block="raid",capability="character.scan.raids",addonId="raids",order=30,request=function(sync,reason)local _,workflowId=Module:Queue(sync,reason=="BOSS_KILL"and.5 or 1,reason~="UPDATE_INSTANCE_INFO");return workflowId end})
  HolyStorm:RegisterCapability("Raids","character.scan.raids",function(_,sync,reason)return HolyStorm.CharacterScans:Request("raid",reason or"CAPABILITY",sync,{order=30})end)
 end
 function Module:OnEnable()for _,ev in ipairs({"UPDATE_INSTANCE_INFO","BOSS_KILL","ENCOUNTER_END"})do local event=ev;HolyStorm.Events:Register(event,"raids",function()HolyStorm.CharacterScans:Request("raid",event,true,{order=30})end)end;local context=self.loadContext;if context and context.reason=="event"then HolyStorm.CharacterScans:Request("raid",context.trigger,true,{order=30})end end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("raids");HolyStorm.Snapshots:Cancel("raids")end
end)
