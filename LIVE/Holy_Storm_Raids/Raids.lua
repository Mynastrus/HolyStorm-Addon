local addonVersion="5.2.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm");local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Raids")
if HolyStorm.PermissionRegistry then HolyStorm.PermissionRegistry:RegisterLegacyAlias("raids.read","raids-read")end
local function validRaidBlock(s)
 if type(s)~="table"or s.snapshotVersion~=3 or s.catalogReady~=true or type(s.raids)~="table"or type(s.lockouts)~="table"or type(s.lifetime)~="table"or type(s.lifetime.bosses)~="table"then return false,"INVALID_RAID_SNAPSHOT"end
 if #s.raids==0 then return false,"EMPTY_RAID_CATALOG"end
 for _,raid in ipairs(s.raids)do
  if type(raid)~="table"or not tonumber(raid.id)or type(raid.name)~="string"or type(raid.bosses)~="table"or#raid.bosses==0 then return false,"INVALID_RAID_CATALOG"end
  for index,boss in ipairs(raid.bosses)do if type(boss)~="table"or not tonumber(boss.id)or type(boss.name)~="string"or tonumber(boss.order)~=index then return false,"INVALID_RAID_BOSS_CATALOG"end end
 end
 for _,lockout in ipairs(s.lockouts)do if type(lockout)~="table"or type(lockout.name)~="string"or not tonumber(lockout.difficultyId)or type(lockout.bosses)~="table"then return false,"INVALID_RAID_LOCKOUT"end end
 for _,boss in pairs(s.lifetime.bosses)do if type(boss)~="table"or type(boss.difficulties)~="table"then return false,"INVALID_RAID_LIFETIME"end end
 return true
end
if HolyStorm.PlayerData then HolyStorm.PlayerData:RegisterBlock("raid",{fields={"raidLockouts"},event="HS_RAIDLOCKS_UPDATED",staleAfter=21600,owner="raids",schemaVersion=3,snapshotVersion=3,capability="character.scan.raids",scanProvider="Raids",validate=validRaidBlock})end
local metadata={id="raids",name="Raids",displayName=L["DISPLAY_NAME"],description=L["DESCRIPTION"],version=addonVersion,moduleType="feature",category="feature",permissions={{id="raids-read",category="Raid",defaults={member=true}},"sync-send"},dependencies={"core","synchronization"},capabilities={"character.scan.raids"},ui={characterTab="raid"},data={block="raid",snapshotType="raids",schemaVersion=3,capability="character.scan.raids"},sync={domains={"character"}},enabledByDefault=true,ruleFields={{id="raid.progress",aliases={"raidProgress"},type="number",name=L["RULE_FIELD_PROGRESS"],nameKey="RULE_FIELD_PROGRESS",description=L["RULE_FIELD_PROGRESS_DESC"],descriptionKey="RULE_FIELD_PROGRESS_DESC",category=L["DISPLAY_NAME"],dependencies={"raid"},unit="bosses",resolver=function(context)local block=context.character and context.character.raid or HolyStorm.Data.CharacterStore:GetBlock(context.characterUUID,"raid");local progress=block and block.bestProgress;return progress and tonumber(progress.killed)or nil end}}}
HolyStorm:RegisterModule(metadata,function(Module)
 HolyStorm:ApplyModuleMetadata(Module,metadata)
 local difficultyKeys={[7]="LFR",[17]="LFR",[14]="NORMAL",[15]="HEROIC",[16]="MYTHIC",[33]="TIMEWALKING"};local difficultyOrder={LFR=1,NORMAL=2,HEROIC=3,MYTHIC=4,TIMEWALKING=5}
 local lifetimeDifficultyIds={LFR=17,NORMAL=14,HEROIC=15,MYTHIC=16};local lifetimeDifficultyOrder={"LFR","NORMAL","HEROIC","MYTHIC"}
 local function raidKey(name)
  if type(name)~="string"then return nil end
  local normalized=(name:gsub("\194\160"," "):gsub("’", "'")):lower():gsub("[%s%p%c]+","")
  return normalized
 end
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
  while true do local id,name,_,_,buttonImage=api.EJ_GetInstanceByIndex(index,true);if not id then break end;local raid={id=id,name=name,icon=buttonImage,tier=tier,order=index,bosses={}};api.EJ_SelectInstance(id);local shouldDisplayDifficulty=select(9,api.EJ_GetInstanceInfo());raid.shouldDisplayDifficulty=shouldDisplayDifficulty;if shouldDisplayDifficulty~=false then local encounterIndex=1;while true do local bossName,_,bossId=api.EJ_GetEncounterInfoByIndex(encounterIndex,id);if not bossName then break end;raid.bosses[#raid.bosses+1]={id=bossId or encounterIndex,name=bossName,order=encounterIndex};encounterIndex=encounterIndex+1 end;if #raid.bosses>0 then raids[#raids+1]=raid end end;index=index+1 end
  return raids
 end
 function Module:GetCurrentRaidCatalog()
  local api,reason=ensureEncounterJournal();if not api then return nil,nil,false,reason end;local ok,raids,tier=pcall(function()local current=api.EJ_GetNumTiers();if not current or current<1 then return{},current end;local previousTier=api.EJ_GetCurrentTier and api.EJ_GetCurrentTier();local currentRaids=readRaidTier(api,current);if previousTier and previousTier~=current then api.EJ_SelectTier(previousTier)end;return currentRaids,current end)
  if not ok then reason="Raid catalog unavailable: Encounter Journal scan failed";HolyStorm.Logger:Write("WARN","Raids","catalog",reason,{reason="ENCOUNTER_JOURNAL_SCAN_FAILED",error=tostring(raids)});return nil,nil,false,reason end
  if not tier or tier<1 or#raids==0 then reason="Raid catalog unavailable: Encounter Journal data pending";HolyStorm.Logger:Write("DEBUG","Raids","catalog",reason,{reason="ENCOUNTER_JOURNAL_PENDING",tier=tier,raidCount=#raids});return nil,tier,false,reason end
  return raids,tier,true
 end
 function Module:GetRaidJournalIndex(currentRaids,currentTier)
  local api,reason=ensureEncounterJournal();if not api then return nil,reason end
  currentRaids=currentRaids or select(1,self:GetCurrentRaidCatalog());currentTier=currentTier or api.EJ_GetNumTiers()
  if type(currentRaids)~="table"or not currentTier then return nil,"Raid catalog unavailable: current tier data pending"end
  local signatureParts={tostring(currentTier)};for _,raid in ipairs(currentRaids)do signatureParts[#signatureParts+1]=tostring(raid.id)..":"..tostring(raid.name)end;local signature=table.concat(signatureParts,"\031")
  if self.raidJournalIndex and self.raidJournalIndexKey==signature then return self.raidJournalIndex end
  local ok,result=pcall(function()
   local previousTier=api.EJ_GetCurrentTier and api.EJ_GetCurrentTier();local byName={}
   local function add(raids)for _,raid in ipairs(raids)do local key=raidKey(raid.name);if key then byName[key]=raid end end end
   add(currentRaids)
   for tier=1,(api.EJ_GetNumTiers()or 0)do if tonumber(tier)~=tonumber(currentTier)then add(readRaidTier(api,tier))end end
   if previousTier then api.EJ_SelectTier(previousTier)end;return byName
  end)
  if not ok then reason="Raid catalog unavailable: Encounter Journal index scan failed";HolyStorm.Logger:Write("WARN","Raids","catalog",reason,{reason="ENCOUNTER_JOURNAL_INDEX_FAILED",error=tostring(result)});return nil,reason end
  if not next(result)then return nil,"Raid catalog unavailable: Encounter Journal index empty"end
  self.raidJournalIndex,self.raidJournalIndexKey=result,signature;return result
 end
 function Module:CollectRaidCatalogChunk(state,maxWork)
  local api,reason=ensureEncounterJournal();if not api then return nil,reason end
  if not state.journal then
   local tierCount=tonumber(api.EJ_GetNumTiers())or 0;if tierCount<1 then return nil,"Raid catalog unavailable: Encounter Journal data pending"end
   local currentTier=tierCount;local previousTier=api.EJ_GetCurrentTier and api.EJ_GetCurrentTier()or currentTier
   state.journal={api=api,tierCount=tierCount,currentTier=currentTier,restoreTier=previousTier,tier=1,instance=1,encounter=1,allByName={},raidsByTier={},work=0}
   api.EJ_SelectTier(1)
  end
  local journal=state.journal;local work=0;local budget=math.max(1,tonumber(maxWork)or 32)
  while journal.tier<=journal.tierCount and work<budget do
   if journal.pendingRaid then
    local raid=journal.pendingRaid;local bossName,_,bossId=api.EJ_GetEncounterInfoByIndex(journal.encounter,raid.id);work=work+1;journal.work=journal.work+1
    if bossName then raid.bosses[#raid.bosses+1]={id=bossId or journal.encounter,name=bossName,order=journal.encounter};journal.encounter=journal.encounter+1
    else
     if #raid.bosses>0 then local token=raidKey(raid.name);if token then journal.allByName[token]=raid end;journal.raidsByTier[journal.tier]=journal.raidsByTier[journal.tier]or{};journal.raidsByTier[journal.tier][#journal.raidsByTier[journal.tier]+1]=raid end
     journal.pendingRaid=nil;journal.instance=journal.instance+1;journal.encounter=1
    end
   else
    local id,name,_,_,icon=api.EJ_GetInstanceByIndex(journal.instance,true);work=work+1;journal.work=journal.work+1
    if not id then journal.tier=journal.tier+1;journal.instance=1;if journal.tier<=journal.tierCount then api.EJ_SelectTier(journal.tier)end
    else
     api.EJ_SelectInstance(id);local shouldDisplayDifficulty=select(9,api.EJ_GetInstanceInfo())
     if shouldDisplayDifficulty==false then journal.instance=journal.instance+1
     else journal.pendingRaid={id=id,name=name,icon=icon,tier=journal.tier,order=journal.instance,bosses={}}end
    end
   end
  end
  if journal.tier<=journal.tierCount then return nil,"IN_PROGRESS",journal.work end
  if journal.restoreTier then api.EJ_SelectTier(journal.restoreTier)end
  local raids=journal.raidsByTier[journal.currentTier]or{};if #raids==0 or not next(journal.allByName)then return nil,"Raid catalog unavailable: Encounter Journal data pending",journal.work end
  state.catalogData={raids=raids,tier=journal.currentTier,journalByName=journal.allByName,catalogReady=true,work=journal.work};state.journal=nil
  return state.catalogData
 end
 local function statisticValue(raw)
  if type(raw)=="number"then return raw>=0 and raw or nil end;if type(raw)~="string"or raw==""or raw=="--"then return nil end
  if not raw:match("^[%d%s,%.]+$")then return nil end
  local digits=raw:gsub("[^%d]","");local value=digits~=""and tonumber(digits)or nil;return value and value>=0 and value or nil
 end
 local function parseStatisticLabel(name)
  -- Blizzard's Statistics UI names the row with GetAchievementInfo(statisticId).
  -- Criteria metadata is not part of that display/value contract.
  if type(name)~="string"then return nil,"MISSING_STATISTIC_NAME"end
  local boss,difficulty,raid=name:match("^%s*(.-)%s*%(%s*(.-)%s*:%s*(.-)%s*%)%s*$")
  local bossToken,difficultyToken,raidToken=raidKey(boss),raidKey(difficulty),raidKey(raid)
  if not bossToken or bossToken==""or not difficultyToken or difficultyToken==""or not raidToken or raidToken==""then return nil,"UNKNOWN_STATISTIC_FORMAT"end
  return{bossToken=bossToken,difficultyToken=difficultyToken,raidToken=raidToken}
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
 local function makeLifetimeCacheKey(raids,tierName)
  local parts={tostring(tierName or"")};local difficultyNames={}
  for _,raid in ipairs(raids or{})do
   parts[#parts+1]=tostring(raid.id)..":"..tostring(raid.name)
   for _,boss in ipairs(raid.bosses or{})do parts[#parts+1]=tostring(boss.id)..":"..tostring(boss.name)end
  end
  for _,key in ipairs(lifetimeDifficultyOrder)do local id=lifetimeDifficultyIds[key];local name
   if type(GetDifficultyInfo)=="function"then local ok,value=pcall(GetDifficultyInfo,id);if ok and type(value)=="string"then name=value end end
   difficultyNames[key]=name;parts[#parts+1]=key..":"..tostring(name or"")
  end
  return table.concat(parts,"\031"),difficultyNames
 end
 local function slotKey(raidToken,bossToken,difficultyToken)return tostring(raidToken or"").."\031"..tostring(bossToken or"").."\031"..tostring(difficultyToken or"")end
 local function makeLifetimeLookup(raids,candidates,difficultyNames)
  local lookup={bySlot={},raidTokens={},bossTokens={},difficultyTokens={},slots=0,candidateComparisons=0,indexCandidates=#(candidates or{}),exactMappings=0}
  local difficultyTokens={};for _,difficulty in ipairs(lifetimeDifficultyOrder)do difficultyTokens[difficulty]=raidKey(difficultyNames[difficulty]);if difficultyTokens[difficulty]then lookup.difficultyTokens[difficultyTokens[difficulty]]=true end end
  for _,raid in ipairs(raids or{})do
   local raidToken=raidKey(raid.name);if raidToken then lookup.raidTokens[raidToken]=true end
   for _,boss in ipairs(raid.bosses or{})do
    local bossToken=raidKey(boss.name);if bossToken then lookup.bossTokens[bossToken]=true end
    for _,difficulty in ipairs(lifetimeDifficultyOrder)do
     lookup.slots=lookup.slots+1;local difficultyToken=difficultyTokens[difficulty]
     if raidToken and bossToken and difficultyToken then
      local key=slotKey(raidToken,bossToken,difficultyToken);local matches=lookup.bySlot[key]
      if not matches then matches={};lookup.bySlot[key]=matches end
     end
    end
   end
  end
  for _,candidate in ipairs(candidates or{})do
   local key=slotKey(candidate.raidToken,candidate.bossToken,candidate.difficultyToken);local matches=lookup.bySlot[key]
   if matches then matches[#matches+1]=candidate end
  end
  lookup.candidateComparisons=#(candidates or{})
  for _,matches in pairs(lookup.bySlot)do if #matches>0 then lookup.exactMappings=lookup.exactMappings+1 end end
  return lookup
 end
 function Module:InvalidateLifetimeStatisticCache(reason)
  self.lifetimeStatisticCache=nil;self.raidScanGeneration=(tonumber(self.raidScanGeneration)or 0)+1
  HolyStorm.Logger:Write("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CACHE_INVALIDATED",{reason=reason or"EXPLICIT"})
 end
 function Module:InvalidateRaidCatalogCache(reason)
  self.raidJournalIndex,self.raidJournalIndexKey=nil,nil
  self:InvalidateLifetimeStatisticCache(reason or"CATALOG_INVALIDATED")
 end
 function Module:GetLifetimeStatisticCandidates(raids,manual,tierName,state,maxWork)
  local cacheKey,difficultyNames;if state and state.key then cacheKey,difficultyNames=state.key,state.difficultyNames else cacheKey,difficultyNames=makeLifetimeCacheKey(raids,tierName)end;local cache=self.lifetimeStatisticCache
  if cache and cache.key==cacheKey then local audit=HolyStorm.Utils.DeepCopy(cache.audit);audit.cached=true;return cache.candidates,nil,audit,cache end
  local audit={mapping="CURRENT_CLIENT_STATISTIC_LABEL",categories=0,categoriesListCalls=0,categoryInfoReads=0,categoriesEnumerated=0,entries=0,statisticIds=0,labelReads=0,candidates=0,relevantCategories=0,relevantEntries=0,discoveryRejected=0,apiFailures=0,workChunks=0}
  if type(GetStatisticsCategoryList)~="function"or type(GetCategoryNumAchievements)~="function"or type(GetStatistic)~="function"or type(GetAchievementInfo)~="function"then return nil,"STATISTIC_API_UNAVAILABLE",audit end
  if not state or state.key~=cacheKey then
   audit.categoriesListCalls=audit.categoriesListCalls+1;local listOk,categories=pcall(GetStatisticsCategoryList);if not listOk or type(categories)~="table"then return nil,"STATISTIC_CATEGORIES_UNAVAILABLE",audit end
   audit.categories=#categories;if #categories==0 then return nil,"STATISTIC_CATEGORIES_EMPTY",audit end
   local raidTokens,bossTokens,raidTokenSet,bossTokenSet={},{},{},{}
   for _,raid in ipairs(raids or{})do local token=raidKey(raid.name);if token then raidTokens[#raidTokens+1]=token;raidTokenSet[token]=true end;for _,boss in ipairs(raid.bosses or{})do token=raidKey(boss.name);if token then bossTokens[#bossTokens+1]=token;bossTokenSet[token]=true end end end
   state={key=cacheKey,difficultyNames=difficultyNames,categories=categories,categoryNames={},categoryCursor=1,raidTokens=raidTokens,bossTokens=bossTokens,raidTokenSet=raidTokenSet,bossTokenSet=bossTokenSet,tierToken=raidKey(tierName),result={},seen={},audit=audit,stage="metadata",logged=0,categoryLogged=0,chunkCount=0}
  end
  audit=state.audit;state.chunkCount=state.chunkCount+1;audit.workChunks=state.chunkCount
  local budget=math.max(1,tonumber(maxWork)or math.huge);local rows=0;local categories=0;local categoryReads=0
  local function yieldIfNeeded()
   return nil,"STATISTIC_DISCOVERY_IN_PROGRESS",audit,state
  end
  if state.stage=="metadata"then
   while state.categoryCursor<=#state.categories and categories<budget do
    local id=state.categories[state.categoryCursor];state.categoryCursor=state.categoryCursor+1;categories=categories+1
    if type(GetCategoryInfo)=="function"then audit.categoryInfoReads=audit.categoryInfoReads+1;local ok,name,parent=pcall(GetCategoryInfo,id);if ok then state.categoryNames[id]={name=safeText(name),parent=safeNumber(parent)}else audit.apiFailures=audit.apiFailures+1 end end
   end
   if state.categoryCursor<=#state.categories then return yieldIfNeeded()end
   local function relevant(name)
    local token=raidKey(name);if not token then return false end
    for _,wanted in ipairs(state.raidTokens)do if token:find(wanted,1,true)then return true end end
    for _,wanted in ipairs(state.bossTokens)do if token:find(wanted,1,true)then return true end end
    return false
   end
   local function relevantCategory(id)
    local visited={};while id and not visited[id]do
     visited[id]=true;local item=state.categoryNames[id];if not item then break end
     local token=raidKey(item.name);if token and((state.tierToken and token:find(state.tierToken,1,true))or relevant(item.name))then return true end;id=item.parent
    end
    return false
   end
   state.categoryRelevant={};state.categoryHadRelevant={}
   for _,id in ipairs(state.categories)do if relevantCategory(id)then state.categoryRelevant[id]=true end end
   -- Enumerate every category before caching. Category labels are useful for
   -- diagnostics, but cannot prove that Blizzard placed no current Raid row in
   -- a generically named category.
   state.scanCategories=state.categories;state.stage="statistics";state.categoryCursor=1;state.entryCursor=1;state.entryCount=nil
  end
  while state.stage=="statistics"and state.categoryCursor<=#state.scanCategories and rows<budget and categoryReads<budget do
   local categoryId=state.scanCategories[state.categoryCursor]
   if state.entryCount==nil then
    local countOk,count=pcall(GetCategoryNumAchievements,categoryId);categoryReads=categoryReads+1;audit.categoriesEnumerated=audit.categoriesEnumerated+1;if not countOk then audit.apiFailures=audit.apiFailures+1 end
    state.entryCount=countOk and safeNumber(count)or 0;state.entryCursor=1
    if not countOk then state.entryCount=0 end
   end
   if state.entryCursor>state.entryCount then
    state.categoryCursor=state.categoryCursor+1;state.entryCount=nil
   else
    local index=state.entryCursor;state.entryCursor=index+1;rows=rows+1;audit.entries=audit.entries+1
    local statOk,_,skip,statisticId=pcall(GetStatistic,categoryId,index);if not statOk then audit.apiFailures=audit.apiFailures+1 end
    statisticId=statOk and safeNumber(statisticId)or nil
    if statisticId and not skip and not state.seen[statisticId]then
     state.seen[statisticId]=true;audit.statisticIds=audit.statisticIds+1
     audit.labelReads=audit.labelReads+1;local infoOk,_,name=pcall(GetAchievementInfo,statisticId);if not infoOk then audit.apiFailures=audit.apiFailures+1 end;name=infoOk and safeText(name)or nil
     local parsed,rejectReason=parseStatisticLabel(name);local isRelevant=parsed and(state.raidTokenSet[parsed.raidToken]or state.bossTokenSet[parsed.bossToken])or false
     if not isRelevant and rejectReason and name then local token=raidKey(name);for _,wanted in ipairs(state.raidTokens)do if token and token:find(wanted,1,true)then isRelevant=true;break end end;if not isRelevant then for _,wanted in ipairs(state.bossTokens)do if token and token:find(wanted,1,true)then isRelevant=true;break end end end end
     if isRelevant then audit.relevantEntries=audit.relevantEntries+1;state.categoryHadRelevant[categoryId]=true end
     if parsed then state.result[#state.result+1]={statisticId=statisticId,name=name,categoryId=categoryId,bossToken=parsed.bossToken,raidToken=parsed.raidToken,difficultyToken=parsed.difficultyToken};audit.candidates=audit.candidates+1 end
     if rejectReason and isRelevant then
      audit.discoveryRejected=audit.discoveryRejected+1
      if manual and state.logged<24 then state.logged=state.logged+1;HolyStorm.Logger:Write("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CANDIDATE_REJECTED",{categoryId=categoryId,statisticId=statisticId,name=name,reason=rejectReason})end
     end
    end
   end
  end
  if state.stage=="statistics"and state.categoryCursor<=#state.scanCategories then return yieldIfNeeded()end
  if state.stage=="statistics"then
   local relevantCategoryCount=0;for _,id in ipairs(state.scanCategories)do if state.categoryRelevant[id]or state.categoryHadRelevant[id]then relevantCategoryCount=relevantCategoryCount+1 end end
   audit.relevantCategories=relevantCategoryCount;audit.categoryLogsTruncated=manual and math.max(0,audit.relevantCategories-state.categoryLogged)or 0
   state.lookup={bySlot={},raidTokens={},bossTokens={},difficultyTokens={},slots=0,candidateComparisons=0,indexCandidates=#state.result,exactMappings=0,mappedSlots={}}
   for _,raid in ipairs(raids or{})do local token=raidKey(raid.name);if token then state.lookup.raidTokens[token]=true end end
   for _,raid in ipairs(raids or{})do for _,boss in ipairs(raid.bosses or{})do local token=raidKey(boss.name);if token then state.lookup.bossTokens[token]=true end end end
   for _,difficulty in ipairs(lifetimeDifficultyOrder)do local token=raidKey(difficultyNames[difficulty]);if token then state.lookup.difficultyTokens[token]=true end end
   state.mapRaidCursor,state.mapBossCursor,state.mapDifficultyCursor,state.mapCandidateCursor=1,1,1,1;state.stage="mapping"
  end
  local lookup=state.lookup;local mappingWork=0
  while state.mapRaidCursor<=#(raids or{})and mappingWork<budget do
   local raid=raids[state.mapRaidCursor];local boss=(raid.bosses or{})[state.mapBossCursor]
   if not boss then state.mapRaidCursor=state.mapRaidCursor+1;state.mapBossCursor,state.mapDifficultyCursor=1,1
   else
    lookup.slots=lookup.slots+1;mappingWork=mappingWork+1
    local raidToken,bossToken=raidKey(raid.name),raidKey(boss.name);local difficulty=lifetimeDifficultyOrder[state.mapDifficultyCursor];local difficultyToken=raidKey(difficultyNames[difficulty])
    if raidToken and bossToken and difficultyToken then local key=slotKey(raidToken,bossToken,difficultyToken);lookup.bySlot[key]=lookup.bySlot[key]or{}end
    state.mapDifficultyCursor=state.mapDifficultyCursor+1;if state.mapDifficultyCursor>#lifetimeDifficultyOrder then state.mapDifficultyCursor=1;state.mapBossCursor=state.mapBossCursor+1 end
   end
  end
  if state.mapRaidCursor>#(raids or{})then while state.mapCandidateCursor<=#state.result and mappingWork<budget do
   local candidate=state.result[state.mapCandidateCursor];state.mapCandidateCursor=state.mapCandidateCursor+1;mappingWork=mappingWork+1
   local key=slotKey(candidate.raidToken,candidate.bossToken,candidate.difficultyToken);local matches=lookup.bySlot[key]
   if matches then matches[#matches+1]=candidate;lookup.candidateComparisons=lookup.candidateComparisons+1;if not lookup.mappedSlots[key]then lookup.mappedSlots[key]=true;lookup.exactMappings=lookup.exactMappings+1 end end
  end end
  if state.mapRaidCursor<=#(raids or{})or state.mapCandidateCursor<=#state.result then return yieldIfNeeded()end
  lookup.mappedSlots=nil;audit.slots=lookup.slots;audit.exactMappings=lookup.exactMappings;audit.mappingProbes=lookup.slots;audit.candidateComparisons=lookup.candidateComparisons
  local complete=audit.apiFailures==0 and #state.result>0 and lookup.exactMappings>0;audit.cacheable=complete
  local completed={key=cacheKey,candidates=state.result,audit=HolyStorm.Utils.DeepCopy(audit),difficultyNames=difficultyNames,lookup=lookup}
  if complete then self.lifetimeStatisticCache=completed end
  if manual then for _,id in ipairs(state.scanCategories)do if(state.categoryRelevant[id]or state.categoryHadRelevant[id])and state.categoryLogged<16 then state.categoryLogged=state.categoryLogged+1;local item=state.categoryNames[id];HolyStorm.Logger:Write("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CATEGORY",{categoryId=id,name=item and item.name,parentId=item and item.parent})end end;audit.categoryLogsTruncated=math.max(0,audit.relevantCategories-state.categoryLogged)end
  return state.result,nil,audit,completed
 end
 function Module:CaptureLifetime(raids,previous,manual,tierName,candidatesOverride,auditOverride,cacheOverride)
  local lifetime=HolyStorm.Utils.DeepCopy(type(previous)=="table"and previous or{bosses={},seen={}});lifetime.bosses=type(lifetime.bosses)=="table"and lifetime.bosses or{};lifetime.seen=type(lifetime.seen)=="table"and lifetime.seen or{}
  if manual then HolyStorm.Logger:Write("INFO","Raids","lifetime","RAID_LIFETIME_SCAN_STARTED",{raidCount=#(raids or{}),tierName=tierName})end
  local candidates,candidateReason,audit,cache
  if candidatesOverride~=nil then candidates,audit,cache=candidatesOverride,auditOverride,cacheOverride else candidates,candidateReason,audit,cache=self:GetLifetimeStatisticCandidates(raids,manual,tierName)end
  audit=audit or{};audit.reason=candidateReason or"OK";audit.recognized=0;audit.valueReads=0;audit.reads=0;audit.positive=0;audit.zero=0;audit.unavailable=0;audit.mappedBosses=0;audit.unmapped=0;audit.missingMappings=0;audit.slots=0
  local difficultyNames=cache and cache.difficultyNames or{};if not cache and type(GetDifficultyInfo)=="function"then for key,id in pairs(lifetimeDifficultyIds)do local ok,name=pcall(GetDifficultyInfo,id);if ok and type(name)=="string"then difficultyNames[key]=name end end end
  local lookup=cache and cache.lookup or makeLifetimeLookup(raids,candidates,difficultyNames)
  local difficultyTokens={};for _,difficulty in ipairs(lifetimeDifficultyOrder)do difficultyTokens[difficulty]=raidKey(difficultyNames[difficulty])end
  local mappedIds,mappedBossIds,detailCount={},{},0
  for _,raid in ipairs(raids or{})do
   local raidToken=raidKey(raid.name)
   for _,boss in ipairs(raid.bosses or{})do
    local bossToken=raidKey(boss.name)
    for _,difficulty in ipairs(lifetimeDifficultyOrder)do
     audit.slots=audit.slots+1
     local difficultyName=difficultyNames[difficulty];local key=slotKey(raidToken,bossToken,difficultyTokens[difficulty]);local matches=candidates and lookup.bySlot[key]or{}
     audit.recognized=audit.recognized+#matches
     audit.candidateComparisons=(audit.candidateComparisons or 0)+#matches
     local candidate=#matches==1 and matches[1]or nil;local raw,kills,accepted,why
     if not candidates then why=candidateReason
     elseif not difficultyName then why="DIFFICULTY_NAME_UNAVAILABLE"
     elseif#matches==0 then why="NO_EXACT_STATISTIC";audit.missingMappings=audit.missingMappings+1
     elseif#matches>1 then why="AMBIGUOUS_STATISTIC";audit.missingMappings=audit.missingMappings+1
     else
      mappedIds[candidate.statisticId]=true
      audit.valueReads=audit.valueReads+1;local ok,value=pcall(GetStatistic,candidate.statisticId);raw=ok and value or nil
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
  audit.unmappedCandidateChecks=0;local logged=0
  for _,candidate in ipairs(candidates or{})do
   audit.unmappedCandidateChecks=audit.unmappedCandidateChecks+1
   if not mappedIds[candidate.statisticId]then
    local raidMatch=lookup.raidTokens[candidate.raidToken]==true;local bossMatch=lookup.bossTokens[candidate.bossToken]==true;local difficultyMatch=lookup.difficultyTokens[candidate.difficultyToken]==true
    if raidMatch or bossMatch then
     audit.unmapped=audit.unmapped+1
     local reason=not raidMatch and"RAID_NAME_NOT_FOUND"or not bossMatch and"BOSS_NAME_NOT_FOUND"or not difficultyMatch and"DIFFICULTY_NAME_NOT_FOUND"or"AMBIGUOUS_STATISTIC"
     if manual and logged<24 then logged=logged+1;HolyStorm.Logger:Write("DEBUG","Raids","lifetime","RAID_LIFETIME_UNMAPPED",{categoryId=candidate.categoryId,statisticId=candidate.statisticId,name=candidate.name,reason=reason})end
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
 function Module:Collect(manual,workState)
  workState=workState or{};local generation=tonumber(self.raidScanGeneration)or 0
  if workState.initialized and workState.generation~=generation then for key in pairs(workState)do workState[key]=nil end end
  if not workState.initialized then
   local raids,tier,journalByName,catalogReady,reason
   if workState.chunked then
    local data,status=self:CollectRaidCatalogChunk(workState,32);if status=="IN_PROGRESS"then return nil,"IN_PROGRESS"end
    if not data then return{pending=true,pendingReason=status or"raid catalog pending"}end
    raids,tier,journalByName,catalogReady=data.raids,data.tier,data.journalByName,data.catalogReady
   else
    raids,tier,catalogReady,reason=self:GetCurrentRaidCatalog();if not catalogReady then return{pending=true,pendingReason=reason or"raid catalog pending"}end
    local indexReason;journalByName,indexReason=self:GetRaidJournalIndex(raids,tier);if not journalByName then return{pending=true,pendingReason=indexReason or"raid catalog pending"}end
   end
   local tierName;if type(EJ_GetTierInfo)=="function"then local ok,name=pcall(EJ_GetTierInfo,tier);if ok and type(name)=="string"then tierName=name end end
   local old=self:GetCharacterSnapshot(UnitGUID("player"));workState.initialized=true;workState.generation=generation;workState.raids=raids;workState.tier=tier;workState.tierName=tierName;workState.old=old;workState.journalByName=journalByName;workState.catalogReady=catalogReady
  end
  local candidates,candidateReason,audit,cache=self:GetLifetimeStatisticCandidates(workState.raids,manual,workState.tierName,workState.discovery,workState.chunked and 32 or nil)
  if candidateReason=="STATISTIC_DISCOVERY_IN_PROGRESS"then workState.discovery=cache;return nil,"IN_PROGRESS"end
  local statisticsUnavailable=not candidates and candidateReason=="STATISTIC_API_UNAVAILABLE"
  if not statisticsUnavailable and(not candidates or audit and(audit.apiFailures or 0)>0)then
   local oldLifetime=workState.old and workState.old.lifetime
   return{pending=true,pendingReason=candidateReason or"STATISTIC_DISCOVERY_INCOMPLETE",currentRaid=workState.raids[1]and{id=workState.raids[1].id,name=workState.raids[1].name,tier=workState.tier}or nil,currentTier=workState.tier,catalogReady=workState.catalogReady,raids=workState.raids,lockouts={},lifetime=HolyStorm.Utils.DeepCopy(oldLifetime or{bosses={},seen={}}),snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}
  end
  local raids,tier,journalByName=workState.raids,workState.tier,workState.journalByName
  local latest=raids[1]and{id=raids[1].id,name=raids[1].name,tier=tier}or nil
  local old=workState.old;local lifetime
  if statisticsUnavailable then lifetime=HolyStorm.Utils.DeepCopy(type(old)=="table"and type(old.lifetime)=="table"and old.lifetime or{bosses={},seen={},reliable=false});lifetime.bosses=type(lifetime.bosses)=="table"and lifetime.bosses or{};lifetime.seen=type(lifetime.seen)=="table"and lifetime.seen or{};HolyStorm.Logger:Write("DEBUG","Raids","lifetime","Raid Statistics APIs unavailable; retaining prior lifetime data",{reason=candidateReason})
  else
   local lifetimeAudit;lifetime,lifetimeAudit=self:CaptureLifetime(raids,type(old)=="table"and old.lifetime,manual,workState.tierName,candidates,audit,cache)
   if lifetimeAudit.apiFailures>0 then return{pending=true,pendingReason="STATISTIC_VALUE_READ_FAILED",currentRaid=latest,currentTier=tier,catalogReady=workState.catalogReady,raids=raids,lockouts={},lifetime=HolyStorm.Utils.DeepCopy(type(old)=="table"and type(old.lifetime)=="table"and old.lifetime or{bosses={},seen={},reliable=false}),snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}end
  end
  local weeklyIdentity;local weeklyAPI=C_DateAndTime;if weeklyAPI and type(weeklyAPI.GetWeeklyResetStartTime)=="function"then local ok,value=pcall(weeklyAPI.GetWeeklyResetStartTime);if ok then weeklyIdentity=safeNumber(value)end end
  local s={currentRaid=latest,currentTier=tier,catalogReady=workState.catalogReady,raids=raids,lockouts={},lifetime=lifetime,weeklyIdentity=weeklyIdentity,updatedAt=HolyStorm.Utils.Now(),snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}
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
 function Module:Validate(s)if type(s)=="table"and s.pending then return false,s.pendingReason or"raid catalog pending"end;if type(s)~="table"or type(s.lockouts)~="table"or type(s.raids)~="table"or type(s.lifetime)~="table"or type(s.lifetime.bosses)~="table"then return false,"instance data unavailable"end;for _,r in ipairs(s.lockouts)do if type(r)~="table"or not r.name or not r.difficultyId or type(r.bosses)~="table"then return false,"lockout incomplete"end end;for _,raid in ipairs(s.raids)do if type(raid)~="table"or not tonumber(raid.id)or type(raid.name)~="string"or type(raid.bosses)~="table"or #raid.bosses==0 then return false,"raid catalog incomplete"end;local seen={};for index,boss in ipairs(raid.bosses)do if type(boss)~="table"then return false,"raid boss catalog incomplete"end;local order=tonumber(boss.order);if not tonumber(boss.id)or type(boss.name)~="string"or not order or order<1 or order%1~=0 or seen[order]then return false,"raid boss catalog incomplete"end;seen[order]=true;if order~=index then return false,"raid boss order incomplete"end end end;if not s.catalogReady then return false,"raid catalog pending"end;return true end
 function Module:Commit(s)
  local guid=UnitGUID("player");local ok,reason=HolyStorm.PlayerData:WriteOwnedBlock(guid,"raid",s,"blizzard")
  local stored,meta=self:GetCharacterSnapshot(guid);local records,positive=countLifetime(stored and stored.lifetime)
  HolyStorm.Logger:Write(ok and"INFO"or"WARN","Raids","lifetime","RAID_LIFETIME_COMMIT",{committed=ok==true,reason=not ok and reason or nil,version=meta and meta.version,schema=stored and stored.snapshotVersion,lifetimeBosses=records,positiveBosses=positive})
  return ok,reason
 end
 function Module:Queue(sync,delay,requestRaidInfo,manual,reason)
  -- UPDATE_INSTANCE_INFO is the response to RequestRaidInfo(). Requesting the
  -- data again from that event creates a loop and keeps extending the debounce.
  local run={generation=self.raidScanGeneration or 0,workState={chunked=true}}
  local function scanner()
   if run.generation~=(Module.raidScanGeneration or 0)then run.generation=Module.raidScanGeneration or 0;run.workState={chunked=true}end
   run.workState.generation=run.generation
   local snapshot,status=Module:Collect(manual,run.workState)
   if status=="IN_PROGRESS"then return{workflowAction="GOTO",gotoStep=1,delay=0}end
   run.snapshotGeneration=run.generation;run.scanComplete=true;run.workState={chunked=true};return snapshot
  end
  local function validator(s)if run.snapshotGeneration~=(Module.raidScanGeneration or 0)then return false,"RAID_SCAN_STALE"end;return Module:Validate(s)end
  local function commit(s,f)
   if run.snapshotGeneration~=(Module.raidScanGeneration or 0)then return{workflowAction="RETRY",gotoStep=1,delay=0,maxRetries=5,reason="RAID_SCAN_STALE"}end
   run.commitStarted=true;local committed,commitReason=Module:Commit(s,f,sync);run.committed=committed~=false
   return committed,commitReason
  end
  local queued,workflowId=HolyStorm.Snapshots:Queue("raids",scanner,validator,commit,{source="Raids",triggerSource=reason or"RAID_SCAN",delay=delay or 1,retryDelay=2.5,priority=3,maxRetries=5})
  if queued then run.workflowId=workflowId;self.activeRaidRun=run end
  if queued and requestRaidInfo~=false and RequestRaidInfo then local now=tonumber(GetTime and GetTime())or 0;if not self.raidInfoRequestPendingUntil or self.raidInfoRequestPendingUntil<now then self.raidInfoRequestPendingUntil=now+10;pcall(RequestRaidInfo)end end
  HolyStorm.Logger:Write("DEBUG","Raids","scan","Raid scan queued",{workflowId=workflowId,reason=reason or"UNKNOWN",manual=manual==true,requestRaidInfo=requestRaidInfo~=false},workflowId)
  return queued,workflowId
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
  HolyStorm.CharacterScans:RegisterProvider("Raids",{block="raid",capability="character.scan.raids",addonId="raids",order=30,request=function(sync,reason,reasons)local manual=reason=="MANUAL_COMMAND"or type(reasons)=="table"and reasons.MANUAL_COMMAND==true;local _,workflowId=Module:Queue(sync,1,reason~="UPDATE_INSTANCE_INFO",manual,reason);return workflowId end,status=function()return Module:GetSnapshotStatus()end})
  HolyStorm:RegisterCapability("Raids","character.scan.raids",function(_,sync,reason)return HolyStorm.CharacterScans:Request("raid",reason or"CAPABILITY",sync,{order=30})end)
 end
 local function inRaidInstance()if type(IsInInstance)~="function"then return false end;local inside,instanceType=IsInInstance();return inside==true and instanceType=="raid"end
 local function requestRaidRefresh(event,success,loadContext)
  if not inRaidInstance()then local instanceType;if type(IsInInstance)=="function"then local _,kind=IsInInstance();instanceType=kind end;HolyStorm.Logger:Write("DEBUG","Raids","trigger","Raid refresh ignored outside a Raid instance",{event=event,instanceType=instanceType or"UNKNOWN"});return false end
  if event=="ENCOUNTER_END"and success~=1 then HolyStorm.Logger:Write("DEBUG","Raids","trigger","Unsuccessful encounter end ignored",{event=event,success=success});return false end
  local now=tonumber(GetTime and GetTime())or 0
  local requestedResponse=event=="UPDATE_INSTANCE_INFO"and Module.raidInfoRequestPendingUntil and Module.raidInfoRequestPendingUntil>=now
  if requestedResponse then Module.raidInfoRequestPendingUntil=nil end
  Module.raidScanGeneration=(Module.raidScanGeneration or 0)+1
  local active=HolyStorm.CharacterScans and HolyStorm.CharacterScans.active;local run=Module.activeRaidRun
  local activeScan=run and not run.commitStarted and(not active or active.block=="raid"and active.workflowId==run.workflowId)
  if activeScan then
   HolyStorm.Logger:Write("DEBUG","Raids","trigger",requestedResponse and"Raid info response folded into active refresh"or"Raid refresh merged into active scan",{event=event,workflowId=run.workflowId,generation=Module.raidScanGeneration},run.workflowId)
   return true
  end
  HolyStorm.Logger:Write("DEBUG","Raids","trigger","Raid refresh requested",{event=event,loadContext=loadContext==true,generation=Module.raidScanGeneration})
  return HolyStorm.CharacterScans:Request("raid",event,true,{order=30})
 end
 function Module:OnEnable()
  HolyStorm.Events:Register("UPDATE_INSTANCE_INFO","raids",function(event)requestRaidRefresh(event)end)
  HolyStorm.Events:Register("ENCOUNTER_END","raids",function(event,encounterId,encounterName,difficultyId,groupSize,success)requestRaidRefresh(event,success)end)
  local function releaseRun(_,workflow)if Module.activeRaidRun and workflow and Module.activeRaidRun.workflowId==workflow.workflowId then Module.activeRaidRun=nil end end
  for _,event in ipairs({"HS_WORKFLOW_COMPLETED","HS_WORKFLOW_FAILED","HS_WORKFLOW_CANCELLED"})do HolyStorm.Events:Register(event,"raids-run",releaseRun)end
  local context=self.loadContext
  if context and context.reason=="event"and context.trigger=="ENCOUNTER_END"then local args=context.arguments or{};requestRaidRefresh(context.trigger,args[5],true)end
 end
 function Module:OnDisable()HolyStorm.Events:UnregisterOwner("raids");HolyStorm.Events:UnregisterOwner("raids-run");HolyStorm.Snapshots:Cancel("raids");self.activeRaidRun=nil end
end)
