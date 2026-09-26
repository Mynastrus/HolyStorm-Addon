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
 local function safeStatisticValue(raw)
  local ok,value=pcall(statisticValue,raw);return ok and value or nil
 end
 local function safeNumber(raw)local ok,value=pcall(tonumber,raw);return ok and value or nil end
 local function safeText(raw)
  local ok,value=pcall(function()
   if type(issecretvalue)=="function"and issecretvalue(raw)then return nil end
   return type(raw)=="string"and #raw<=160 and raw or nil
  end)
  return ok and value or nil
 end
 local function safeRawState(raw)
  local ok,state,value=pcall(function()
   if type(issecretvalue)=="function"then local checked,secret=pcall(issecretvalue,raw);if not checked or secret then return"PROTECTED",nil end end
   if type(raw)=="number"then return"NUMBER",raw end
   if type(raw)~="string"then return"UNAVAILABLE",nil end
   if raw=="--"or raw==""then return"UNAVAILABLE",raw end
   if #raw<=32 and raw:match("^[%d%s,%.%-]+$")then return"STRING",raw end
   return"STRING_REDACTED",nil
  end)
  return ok and state or"PROTECTED",ok and value or nil
 end
 local function countLifetime(snapshot)
  local records,positive=0,0
  for _,boss in pairs(type(snapshot)=="table"and type(snapshot.bosses)=="table"and snapshot.bosses or{})do
   records=records+1;local found=false
   for _,entry in pairs(type(boss)=="table"and type(boss.difficulties)=="table"and boss.difficulties or{})do
    if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)and (tonumber(entry.kills)or 0)>0 then found=true end
   end
   if found then positive=positive+1 end
  end
  return records,positive
 end
 function Module:GetLifetimeStatisticCandidates(raids,manual,tierName)
  local ids={};for _,raid in ipairs(raids or{})do ids[#ids+1]=tostring(raid.id)end
  local cacheKey=tostring(tierName or"")..":"..table.concat(ids,",")
  if not manual and self.lifetimeStatisticCandidates and self.lifetimeStatisticKey==cacheKey then
   local cached=HolyStorm.Utils.DeepCopy(self.lifetimeStatisticAudit);cached.cached=true;return self.lifetimeStatisticCandidates,nil,cached
  end
  if manual then self.lifetimeStatisticCandidates,self.lifetimeStatisticAudit,self.lifetimeStatisticKey=nil,nil,nil end
  local audit={categories=0,entries=0,statisticIds=0,candidates=0,relevantCategories=0,relevantEntries=0,discoveryRejected=0,apiFailures=0}
  if type(GetStatisticsCategoryList)~="function"or type(GetCategoryNumAchievements)~="function"or type(GetStatistic)~="function"or type(GetAchievementInfo)~="function"or type(GetAchievementNumCriteria)~="function"or type(GetAchievementCriteriaInfo)~="function"then return nil,"STATISTIC_API_UNAVAILABLE",audit end
  local listOk,categories=pcall(GetStatisticsCategoryList);if not listOk or type(categories)~="table"then return nil,"STATISTIC_CATEGORIES_UNAVAILABLE",audit end
  audit.categories=#categories
  if #categories==0 then return nil,"STATISTIC_CATEGORIES_EMPTY",audit end
  local result,seen,raidTokens,bossTokens={},{},{},{}
  for _,raid in ipairs(raids or{})do
   raidTokens[#raidTokens+1]=raidKey(raid.name)
   for _,boss in ipairs(raid.bosses or{})do bossTokens[#bossTokens+1]=raidKey(boss.name)end
  end
  local function relevant(name)
   local token=raidKey(name);if not token then return false end
   for _,wanted in ipairs(raidTokens)do if wanted and token:find(wanted,1,true)then return true end end
   for _,wanted in ipairs(bossTokens)do if wanted and token:find(wanted,1,true)then return true end end
   return false
  end
  local tierToken=raidKey(tierName)
  local categoryNames={}
  if type(GetCategoryInfo)=="function"then for _,id in ipairs(categories)do local ok,name,parent=pcall(GetCategoryInfo,id);if ok then categoryNames[id]={name=safeText(name),parent=safeNumber(parent)}end end end
  local function relevantCategory(id)
   local visited={};while id and not visited[id]do
    visited[id]=true;local item=categoryNames[id];if not item then break end
    local token=raidKey(item.name)
    if token and((tierToken and token:find(tierToken,1,true))or relevant(item.name))then return true end
    id=item.parent
   end
   return false
  end
  local logged,categoryLogged=0,0
  for _,categoryId in ipairs(categories)do
   local countOk,count=pcall(GetCategoryNumAchievements,categoryId);if not countOk then audit.apiFailures=audit.apiFailures+1 end
   local relevantCount,candidateCount=0,0
   for index=1,(countOk and safeNumber(count)or 0)do
    audit.entries=audit.entries+1
    local statOk,_,skip,statisticId=pcall(GetStatistic,categoryId,index)
    if not statOk then audit.apiFailures=audit.apiFailures+1 end
    statisticId=statOk and safeNumber(statisticId)or nil
    if statisticId and not skip and not seen[statisticId]then
     seen[statisticId]=true;audit.statisticIds=audit.statisticIds+1
     local infoOk,_,name=pcall(GetAchievementInfo,statisticId)
     if not infoOk then audit.apiFailures=audit.apiFailures+1 end
     name=infoOk and safeText(name)or nil
     local isRelevant=name and relevant(name)
     if isRelevant then audit.relevantEntries=audit.relevantEntries+1;relevantCount=relevantCount+1 end
     local criteriaOk,criteriaCount=pcall(GetAchievementNumCriteria,statisticId)
     local reason
     if not criteriaOk then audit.apiFailures=audit.apiFailures+1;reason="CRITERIA_API_FAILED"
     elseif safeNumber(criteriaCount)~=1 then reason="CRITERIA_COUNT_"..tostring(safeNumber(criteriaCount)or"UNAVAILABLE")
     else
      local ok,_,criteriaType,_,_,_,_,_,assetId=pcall(GetAchievementCriteriaInfo,statisticId,1)
      if not ok then audit.apiFailures=audit.apiFailures+1;reason="CRITERIA_API_FAILED"
      elseif safeNumber(criteriaType)~=0 then reason="CRITERIA_TYPE_"..tostring(safeNumber(criteriaType)or"UNAVAILABLE")
      elseif not safeNumber(assetId)then reason="MISSING_CREATURE_ASSET"
      elseif type(name)~="string"then reason="MISSING_STATISTIC_NAME"
      else result[#result+1]={statisticId=statisticId,name=name,assetId=safeNumber(assetId),categoryId=categoryId};audit.candidates=audit.candidates+1;candidateCount=candidateCount+1 end
     end
     if reason and isRelevant then
      audit.discoveryRejected=audit.discoveryRejected+1
      if manual and logged<24 then logged=logged+1;HolyStorm.Logger:Write("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CANDIDATE_REJECTED",{categoryId=categoryId,statisticId=statisticId,name=name,reason=reason})end
     end
    end
   end
   if relevantCount>0 or relevantCategory(categoryId)then
    audit.relevantCategories=audit.relevantCategories+1
    if manual and categoryLogged<16 then categoryLogged=categoryLogged+1;HolyStorm.Logger:Write("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CATEGORY",{categoryId=categoryId,name=categoryNames[categoryId]and categoryNames[categoryId].name,parentId=categoryNames[categoryId]and categoryNames[categoryId].parent,entries=countOk and count or 0,relevantEntries=relevantCount,candidates=candidateCount})end
   end
  end
  audit.categoryLogsTruncated=manual and math.max(0,audit.relevantCategories-categoryLogged)or 0
  if #result>0 then self.lifetimeStatisticCandidates=result;self.lifetimeStatisticAudit=HolyStorm.Utils.DeepCopy(audit);self.lifetimeStatisticKey=cacheKey end
  return result,nil,audit
 end
 function Module:CaptureLifetime(raids,previous,manual,tierName)
  local lifetime=HolyStorm.Utils.DeepCopy(type(previous)=="table"and previous or{bosses={},seen={}});lifetime.bosses=type(lifetime.bosses)=="table"and lifetime.bosses or{};lifetime.seen=type(lifetime.seen)=="table"and lifetime.seen or{}
  if manual then HolyStorm.Logger:Write("INFO","Raids","lifetime","RAID_LIFETIME_SCAN_STARTED",{raidCount=#(raids or{}),tierName=tierName})end
  local candidates,candidateReason,audit=self:GetLifetimeStatisticCandidates(raids,manual,tierName)
  audit=audit or{};audit.reason=candidateReason or"OK";audit.recognized=0;audit.reads=0;audit.positive=0;audit.zero=0;audit.unavailable=0;audit.mappedBosses=0;audit.unmapped=0;audit.missingMappings=0;audit.slots=0
  local difficultyNames={};if type(GetDifficultyInfo)=="function"then for key,id in pairs(lifetimeDifficultyIds)do local ok,name=pcall(GetDifficultyInfo,id);if ok and type(name)=="string"then difficultyNames[key]=name end end end
  local mappedIds,mappedBossIds,detailCount={},{},0
  for _,raid in ipairs(raids or{})do
   for _,boss in ipairs(raid.bosses or{})do
    local creatures={};for _,id in ipairs(boss.creatureIds or{})do creatures[tonumber(id)]=true end
    for _,difficulty in ipairs(lifetimeDifficultyOrder)do
     audit.slots=audit.slots+1
     local matches={};local difficultyName=difficultyNames[difficulty]
     if candidates and difficultyName and next(creatures)then
      local bossToken,raidToken,difficultyToken=raidKey(boss.name),raidKey(raid.name),raidKey(difficultyName)
      for _,candidate in ipairs(candidates)do
       local nameToken=raidKey(candidate.name)
       if creatures[candidate.assetId]and nameToken and bossToken and raidToken and difficultyToken and nameToken:find(bossToken,1,true)and nameToken:find(raidToken,1,true)and nameToken:find(difficultyToken,1,true)then matches[#matches+1]=candidate end
      end
     end
     audit.recognized=audit.recognized+#matches
     local candidate=#matches==1 and matches[1]or nil;local raw,kills,accepted,why
     if not candidates then why=candidateReason
     elseif not difficultyName then why="DIFFICULTY_NAME_UNAVAILABLE"
     elseif not next(creatures)then why="CREATURE_MAPPING_UNAVAILABLE"
     elseif#matches==0 then why="NO_EXACT_STATISTIC";audit.missingMappings=audit.missingMappings+1
     elseif#matches>1 then why="AMBIGUOUS_STATISTIC";audit.missingMappings=audit.missingMappings+1
     else
      mappedIds[candidate.statisticId]=true
      local ok,value=pcall(GetStatistic,candidate.statisticId);raw=ok and value or nil
      if not ok then audit.apiFailures=audit.apiFailures+1 end
      kills=ok and safeStatisticValue(value)or nil;accepted=kills~=nil
      if accepted then audit.reads=audit.reads+1;if kills>0 then audit.positive=audit.positive+1 else audit.zero=audit.zero+1 end
      else audit.unavailable=audit.unavailable+1 end
      why=not ok and"STATISTIC_API_FAILED"or accepted and"ACCEPTED"or"STATISTIC_VALUE_UNAVAILABLE"
     end
     if accepted then
      local key=boss.id or boss.name;local stored=lifetime.bosses[key]or{}
      stored.id=boss.id;stored.encounterId=boss.id;stored.name=boss.name;stored.raidInstanceId=raid.id;stored.journalInstanceId=raid.id;stored.raidName=raid.name
      stored.difficulties=type(stored.difficulties)=="table"and stored.difficulties or{}
      stored.difficulties[difficulty]={statisticId=candidate.statisticId,kills=kills,source="blizzard-statistic"};lifetime.bosses[key]=stored
      local identity=tostring(raid.id).."\031"..tostring(key)
      if not mappedBossIds[identity]then mappedBossIds[identity]=true;audit.mappedBosses=audit.mappedBosses+1 end
     end
     if manual and detailCount<80 then
      detailCount=detailCount+1
      local rawState,rawValue=safeRawState(raw)
      HolyStorm.Logger:Write("DEBUG","Raids","lifetime","RAID_LIFETIME_STAT",{raidInstanceId=raid.id,raidName=raid.name,bossId=boss.id,bossName=boss.name,difficulty=difficulty,statisticId=candidate and candidate.statisticId or 0,categoryId=candidate and candidate.categoryId,rawState=rawState,value=rawValue or"UNKNOWN",kills=kills,accepted=accepted==true,reason=why})
     end
    end
   end
  end
  local logged=0
  for _,candidate in ipairs(candidates or{})do
   if not mappedIds[candidate.statisticId]then
    local candidateToken=raidKey(candidate.name);local raidMatch,bossMatch,assetMatch=false,false,false
    for _,raid in ipairs(raids or{})do
     local raidToken=raidKey(raid.name)
     if candidateToken and raidToken and candidateToken:find(raidToken,1,true)then raidMatch=true end
     for _,boss in ipairs(raid.bosses or{})do
      local bossToken=raidKey(boss.name)
      if candidateToken and bossToken and candidateToken:find(bossToken,1,true)then bossMatch=true end
      for _,id in ipairs(boss.creatureIds or{})do if tonumber(id)==candidate.assetId then assetMatch=true end end
     end
    end
    if raidMatch or bossMatch or assetMatch then
     audit.unmapped=audit.unmapped+1
     local reason=not raidMatch and"RAID_NAME_NOT_FOUND"or not assetMatch and"CREATURE_ASSET_NOT_FOUND"or not bossMatch and"BOSS_NAME_NOT_FOUND"or"DIFFICULTY_OR_AMBIGUOUS_NAME"
     if manual and logged<24 then logged=logged+1;HolyStorm.Logger:Write("DEBUG","Raids","lifetime","RAID_LIFETIME_UNMAPPED",{categoryId=candidate.categoryId,statisticId=candidate.statisticId,name=candidate.name,assetId=candidate.assetId,reason=reason})end
    end
   end
  end
  local records,positiveBosses=countLifetime(lifetime)
  audit.records=records;audit.positiveBosses=positiveBosses
  local reliable=false
  for _,boss in pairs(lifetime.bosses)do for _,entry in pairs(type(boss)=="table"and type(boss.difficulties)=="table"and boss.difficulties or{})do
   if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)then reliable=true;break end
  end;if reliable then break end end
  lifetime.reliable=reliable
  audit.detailTruncated=manual and math.max(0,audit.slots-detailCount)or 0
  lifetime.source=lifetime.reliable and"blizzard-statistic"or(lifetime.source or"legacy-local-observation")
  HolyStorm.Logger:Write(manual and"INFO"or"DEBUG","Raids","lifetime","RAID_LIFETIME_SCAN_SUMMARY",audit)
  if manual then for _,raid in ipairs(raids or{})do
   local mapped,positive=0,0
   for _,catalogBoss in ipairs(raid.bosses or{})do
    local boss=lifetime.bosses[catalogBoss.id or catalogBoss.name]
    if boss and tonumber(boss.raidInstanceId)==tonumber(raid.id)then
     mapped=mapped+1
     for _,entry in pairs(boss.difficulties or{})do if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)and (tonumber(entry.kills)or 0)>0 then positive=positive+1;break end end
    end
   end
   HolyStorm.Logger:Write("DEBUG","Raids","lifetime","RAID_LIFETIME_RAID_SUMMARY",{raidInstanceId=raid.id,raidName=raid.name,catalogBosses=#(raid.bosses or{}),lifetimeBosses=mapped,positiveBosses=positive})
  end end
  return lifetime,audit
 end
 function Module:Collect(manual)
  local raids,tier,catalogReady,reason=self:GetCurrentRaidCatalog();if not catalogReady then return{pending=true,pendingReason=reason or"raid catalog pending"}end;local journalByName,indexReason=self:GetRaidJournalIndex();if not journalByName then return{pending=true,pendingReason=indexReason or"raid catalog pending"}end;local latest=raids[1]and{id=raids[1].id,name=raids[1].name,tier=tier}or nil
  local tierName;if type(EJ_GetTierInfo)=="function"then local ok,name=pcall(EJ_GetTierInfo,tier);if ok and type(name)=="string"then tierName=name end end
  local old=self:GetCharacterSnapshot(UnitGUID("player"));local lifetime=self:CaptureLifetime(raids,type(old)=="table"and old.lifetime,manual,tierName)
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
  if manual then local records,positive=countLifetime(s.lifetime);HolyStorm.Logger:Write("INFO","Raids","lifetime","RAID_LIFETIME_SNAPSHOT",{schema=s.snapshotVersion,raids=#s.raids,lockouts=#s.lockouts,lifetimeBosses=records,positiveBosses=positive,updatedAt=s.updatedAt,valid=self:Validate(s)})end
  return s
 end
 function Module:Validate(s)if type(s)=="table"and s.pending then return false,s.pendingReason or"raid catalog pending"end;if type(s)~="table"or type(s.lockouts)~="table"or type(s.raids)~="table"or type(s.lifetime)~="table"or type(s.lifetime.bosses)~="table"then return false,"instance data unavailable"end;for _,r in ipairs(s.lockouts)do if type(r)~="table"or not r.name or not r.difficultyId or type(r.bosses)~="table"then return false,"lockout incomplete"end end;if not s.catalogReady then return false,"raid catalog pending"end;return true end
 function Module:Commit(s)
  local guid=UnitGUID("player");local ok,reason=HolyStorm.PlayerData:WriteOwnedBlock(guid,"raid",s,"blizzard")
  local stored,meta=self:GetCharacterSnapshot(guid);local records,positive=countLifetime(stored and stored.lifetime)
  HolyStorm.Logger:Write(ok and"INFO"or"WARN","Raids","lifetime","RAID_LIFETIME_COMMIT",{committed=ok==true,reason=not ok and reason or nil,version=meta and meta.version,schema=stored and stored.snapshotVersion,lifetimeBosses=records,positiveBosses=positive})
  return ok,reason
 end
 function Module:Queue(sync,delay,requestRaidInfo,manual)
  -- UPDATE_INSTANCE_INFO is the response to RequestRaidInfo(). Requesting the
  -- data again from that event creates a loop and keeps extending the debounce.
  if requestRaidInfo~=false and RequestRaidInfo then RequestRaidInfo()end
  return HolyStorm.Snapshots:Queue("raids",function()return Module:Collect(manual)end,function(s)return Module:Validate(s)end,function(s,f)return Module:Commit(s,f,sync)end,{source="Raids",delay=delay or 1,retryDelay=2.5,priority=3})
 end
 function Module:GetSnapshotStatus()
  local snapshot,meta=self:GetCharacterSnapshot(UnitGUID("player"))
  if type(snapshot)~="table"then return{L["RAID_STATUS_NO_SNAPSHOT"]}end
  local valid,reason=self:Validate(snapshot)
  local records,positive=countLifetime(snapshot.lifetime)
  local raids=type(snapshot.raids)=="table"and snapshot.raids or{}
  local lockouts=type(snapshot.lockouts)=="table"and snapshot.lockouts or{}
  local lifetimeBosses=type(snapshot.lifetime)=="table"and type(snapshot.lifetime.bosses)=="table"and snapshot.lifetime.bosses or{}
  local difficultyLabels={LFR=L["DIFFICULTY_LFR"],NORMAL=L["DIFFICULTY_NORMAL"],HEROIC=L["DIFFICULTY_HEROIC"],MYTHIC=L["DIFFICULTY_MYTHIC"]}
  local lines={string.format(L["RAID_STATUS_SUMMARY"],tostring(snapshot.snapshotVersion or"-"),tostring(meta and meta.version or snapshot.version or"-"),tostring(meta and meta.source or"-"),#raids,#lockouts,records,positive,tostring(snapshot.updatedAt or meta and meta.updatedAt or"-"),valid and L["RAID_STATUS_VALID"]or tostring(reason or L["RAID_STATUS_INVALID"]))}
  for _,raid in ipairs(raids)do if type(raid)=="table"then
   local catalogBosses=type(raid.bosses)=="table"and raid.bosses or{}
   local mapped=0
   for _,catalogBoss in ipairs(catalogBosses)do
    local boss=type(catalogBoss)=="table"and lifetimeBosses[catalogBoss.id or catalogBoss.name]
    if type(boss)=="table"and tonumber(boss.raidInstanceId)==tonumber(raid.id)then mapped=mapped+1 end
   end
   local best;if HolyStorm.CharacterUI then local ok,value=pcall(HolyStorm.CharacterUI.GetBestProgress,HolyStorm.CharacterUI,snapshot,raid);if ok then best=value end end
   local bestText=best and string.format("%s %d/%d",difficultyLabels[best.difficulty]or best.difficulty,best.killed,best.total)or"-"
   lines[#lines+1]=string.format(L["RAID_STATUS_RAID"],tostring(raid.name or raid.id),#catalogBosses,mapped,bestText)
  end end
  return lines
 end
 function Module:OnInitialize()
  HolyStorm.CharacterScans:RegisterProvider("Raids",{block="raid",capability="character.scan.raids",addonId="raids",order=30,request=function(sync,reason,reasons)local manual=reason=="MANUAL_COMMAND"or type(reasons)=="table"and reasons.MANUAL_COMMAND==true;local _,workflowId=Module:Queue(sync,reason=="BOSS_KILL"and.5 or 1,reason~="UPDATE_INSTANCE_INFO",manual);return workflowId end,status=function()return Module:GetSnapshotStatus()end})
  HolyStorm:RegisterCapability("Raids","character.scan.raids",function(_,sync,reason)return HolyStorm.CharacterScans:Request("raid",reason or"CAPABILITY",sync,{order=30})end)
 end
 function Module:OnEnable()for _,ev in ipairs({"UPDATE_INSTANCE_INFO","BOSS_KILL","ENCOUNTER_END"})do local event=ev;HolyStorm.Events:Register(event,"raids",function()HolyStorm.CharacterScans:Request("raid",event,true,{order=30})end)end;local context=self.loadContext;if context and context.reason=="event"then HolyStorm.CharacterScans:Request("raid",context.trigger,true,{order=30})end end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("raids");HolyStorm.Snapshots:Cancel("raids")end
end)
