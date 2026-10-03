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
 local RAID_SCAN_WORK_BUDGET=8
 local RAID_SCAN_SLICE_SECONDS=.002
 local lifetimeDifficultyIds={LFR=17,NORMAL=14,HEROIC=15,MYTHIC=16};local lifetimeDifficultyOrder={"LFR","NORMAL","HEROIC","MYTHIC"}
 local function performanceClock()
  if type(GetTimePreciseSec)=="function"then return GetTimePreciseSec()end
  if type(GetTime)=="function"then return GetTime()end
  return os.clock()
 end
 local currentSlice
 local function callAPI(counter,fn,...)
  if currentSlice then
   currentSlice.operations=currentSlice.operations+1
   local run=currentSlice.run;if run then run[counter]=run[counter]+1 end
  end
  return fn(...)
 end
 local function withinRaidSlice(work,budget,started)
  -- A costly Blizzard call can exhaust the frame on its own. Never batch a
  -- second API operation, regardless of the remaining numerical work budget.
  return work<budget and performanceClock()-started<RAID_SCAN_SLICE_SECONDS
   and(not currentSlice or currentSlice.operations==0 and performanceClock()-currentSlice.started<RAID_SCAN_SLICE_SECONDS)
 end
 local function diagnostic(level,source,category,message,context)
  if currentSlice and currentSlice.workState then
   local details=currentSlice.workState.diagnostics
   if not details then details={};currentSlice.workState.diagnostics=details end
   if #details<128 then details[#details+1]={message=message,context=context}end
   return
  end
  HolyStorm.Logger:Write(level,source,category,message,context)
 end
 local function raidKey(name)
  if type(name)~="string"then return nil end
  local normalized=(name:gsub("\194\160"," "):gsub("’", "'")):lower():gsub("[%s%p%c]+","")
  return normalized
 end
 local requiredJournalAPIs={{"EJ_GetNumTiers","tier enumeration"},{"EJ_SelectTier","tier selection"},{"EJ_GetInstanceByIndex","instance enumeration"},{"EJ_GetEncounterInfoByIndex","encounter enumeration"},{"EJ_GetInstanceInfo","instance metadata"}}
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
 -- Static current encounters and historical lockout identities share one
 -- catalog builder. Historical bosses are never used by current lifetime/best.
 function Module:CollectRaidCatalogChunk(state,maxWork)
  local started=performanceClock();local journal=state.journal;local api,reason
  if journal then api=journal.api else api,reason=ensureEncounterJournal()end;if not api then return nil,reason end
  if not journal then journal={api=api,stage="count",tier=1,instance=1,encounter=1,allByName={},raids={}};state.journal=journal end
  local budget=math.max(1,tonumber(maxWork)or RAID_SCAN_WORK_BUDGET);local work=0
  while withinRaidSlice(work,budget,started)do
   if journal.stage=="count"then
    journal.currentTier=tonumber(callAPI("ejCalls",api.EJ_GetNumTiers))or 0;work=work+1
    if journal.currentTier<1 then return nil,"Raid catalog unavailable: Encounter Journal data pending"end
    if self.raidCatalogData and self.raidCatalogData.tier==journal.currentTier then state.catalogData=self.raidCatalogData;state.journal=nil;return state.catalogData end
    if currentSlice and currentSlice.run then currentSlice.run.catalogBuilds=currentSlice.run.catalogBuilds+1 end
    journal.stage="previous"
   elseif journal.stage=="previous"then
    journal.restoreTier=api.EJ_GetCurrentTier and callAPI("ejCalls",api.EJ_GetCurrentTier)or journal.currentTier;work=work+1;journal.stage="selectTier"
   elseif journal.stage=="selectTier"then
    callAPI("ejCalls",api.EJ_SelectTier,journal.tier);work=work+1;journal.stage="instance"
   elseif journal.stage=="instance"then
    local id,name,_,_,icon=callAPI("ejCalls",api.EJ_GetInstanceByIndex,journal.instance,true);work=work+1
    if not id then
     journal.tier=journal.tier+1;journal.instance=1;journal.stage=journal.tier>journal.currentTier and"restore"or"selectTier"
    else
     local raid={id=id,name=name,icon=icon,tier=journal.tier,order=journal.instance,bosses={}}
     if journal.tier==journal.currentTier then journal.raid=raid;journal.stage="instanceInfo"
     else local key=raidKey(name);if key then journal.allByName[key]=raid end;journal.instance=journal.instance+1 end
    end
   elseif journal.stage=="instanceInfo"then
    journal.raid.shouldDisplayDifficulty=select(9,callAPI("ejCalls",api.EJ_GetInstanceInfo,journal.raid.id));work=work+1
    if journal.raid.shouldDisplayDifficulty==false then journal.raid=nil;journal.instance=journal.instance+1;journal.stage="instance"else journal.stage="encounter"end
   elseif journal.stage=="encounter"then
    local raid=journal.raid;local name,_,id=callAPI("ejCalls",api.EJ_GetEncounterInfoByIndex,journal.encounter,raid.id);work=work+1
    if name then raid.bosses[#raid.bosses+1]={id=id or journal.encounter,name=name,order=journal.encounter};journal.encounter=journal.encounter+1
    else
     if #raid.bosses>0 then journal.raids[#journal.raids+1]=raid;local key=raidKey(raid.name);if key then journal.allByName[key]=raid end end
     journal.raid=nil;journal.encounter=1;journal.instance=journal.instance+1;journal.stage="instance"
    end
   elseif journal.stage=="restore"then
    if journal.restoreTier then callAPI("ejCalls",api.EJ_SelectTier,journal.restoreTier);work=work+1 end;journal.stage="tierName"
   elseif journal.stage=="tierName"then
    if type(EJ_GetTierInfo)=="function"then local ok,name=pcall(callAPI,"ejCalls",EJ_GetTierInfo,journal.currentTier);if ok and type(name)=="string"then journal.tierName=name end;work=work+1 end;journal.stage="finish"
   else
    if #journal.raids==0 then return nil,"Raid catalog unavailable: Encounter Journal data pending"end
    local data={raids=journal.raids,tier=journal.currentTier,tierName=journal.tierName,journalByName=journal.allByName,catalogReady=true}
    self.raidCatalogData=data;self.raidJournalIndex=journal.allByName;state.catalogData=data;state.journal=nil;return data
   end
  end
  return nil,"IN_PROGRESS"
 end
 function Module:GetCurrentRaidCatalog()
  local state={};local data,reason
  repeat data,reason=self:CollectRaidCatalogChunk(state)until reason~="IN_PROGRESS"
  if not data then return nil,nil,false,reason end
  return data.raids,data.tier,true
 end
 function Module:GetRaidJournalIndex()
  local _,_,ready,reason=self:GetCurrentRaidCatalog();if not ready then return nil,reason end
  return self.raidCatalogData.journalByName
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
 local function makeLifetimeCacheKey(raids,tierName,knownDifficultyNames)
  local parts={tostring(tierName or"")};local difficultyNames=knownDifficultyNames or{}
  for _,raid in ipairs(raids or{})do
   parts[#parts+1]=tostring(raid.id)..":"..tostring(raid.name)
   for _,boss in ipairs(raid.bosses or{})do parts[#parts+1]=tostring(boss.id)..":"..tostring(boss.name)end
  end
  for _,key in ipairs(lifetimeDifficultyOrder)do local id=lifetimeDifficultyIds[key];local name=difficultyNames[key]
   if not knownDifficultyNames and type(GetDifficultyInfo)=="function"then local ok,value=pcall(GetDifficultyInfo,id);if ok and type(value)=="string"then name=value end end
   difficultyNames[key]=name;parts[#parts+1]=key..":"..tostring(name or"")
  end
  return table.concat(parts,"\031"),difficultyNames
 end
 local function slotKey(raidToken,bossToken,difficultyToken)return tostring(raidToken or"").."\031"..tostring(bossToken or"").."\031"..tostring(difficultyToken or"")end
 function Module:InvalidateLifetimeStatisticCache(reason)
  self.lifetimeStatisticCache=nil;self.raidScanGeneration=(tonumber(self.raidScanGeneration)or 0)+1
  HolyStorm.Logger:Write("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CACHE_INVALIDATED",{reason=reason or"EXPLICIT"})
 end
 function Module:InvalidateRaidCatalogCache(reason)
  self.raidDifficultyNames,self.raidCatalogData,self.raidJournalIndex,self.raidJournalIndexKey=nil,nil,nil,nil
  self:InvalidateLifetimeStatisticCache(reason or"CATALOG_INVALIDATED")
 end
 local function collectLifetimeCandidatesChunked(module,raids,manual,tierName,state,maxWork,knownDifficultyNames)
  local sliceStarted=performanceClock()
  local cacheKey,difficultyNames
  if state and state.key then cacheKey,difficultyNames=state.key,state.difficultyNames else cacheKey,difficultyNames=makeLifetimeCacheKey(raids,tierName,knownDifficultyNames or module.raidDifficultyNames)end
  local cache=module.lifetimeStatisticCache
  if cache and cache.key==cacheKey then local audit=HolyStorm.Utils.DeepCopy(cache.audit);audit.cached=true;return cache.candidates,nil,audit,cache end
  local audit=state and state.audit or{mapping="CURRENT_CLIENT_STATISTIC_LABEL",categories=0,categoriesListCalls=0,categoryInfoReads=0,categoriesEnumerated=0,entries=0,statisticIds=0,labelReads=0,candidates=0,relevantCategories=0,relevantEntries=0,discoveryRejected=0,apiFailures=0,workChunks=0}
  if type(GetStatisticsCategoryList)~="function"or type(GetCategoryNumAchievements)~="function"or type(GetStatistic)~="function"or type(GetAchievementInfo)~="function"then return nil,"STATISTIC_API_UNAVAILABLE",audit end
  if not state or state.key~=cacheKey then
   state={key=cacheKey,difficultyNames=difficultyNames,categoryNames={},result={},seen={},audit=audit,stage="categories",tierToken=raidKey(tierName),tokenRaidCursor=1,tokenBossCursor=0,logged=0,categoryLogged=0,chunkCount=0}
  end
  audit=state.audit;state.chunkCount=state.chunkCount+1;audit.workChunks=state.chunkCount
  local budget=math.max(1,tonumber(maxWork)or RAID_SCAN_WORK_BUDGET);local work=0
  local function pending()return nil,"STATISTIC_DISCOVERY_IN_PROGRESS",audit,state end
  if state.stage=="categories"then
   if not withinRaidSlice(work,budget,sliceStarted)then return pending()end
   audit.categoriesListCalls=audit.categoriesListCalls+1;local ok,categories=pcall(callAPI,"statisticCalls",GetStatisticsCategoryList)
   if not ok or type(categories)~="table"then return nil,"STATISTIC_CATEGORIES_UNAVAILABLE",audit end
   audit.categories=#categories;if #categories==0 then return nil,"STATISTIC_CATEGORIES_EMPTY",audit end
   state.categories=categories;state.stage="tokens";return pending()
  end
  if state.stage=="tokens"then
   while state.tokenRaidCursor<=#(raids or{})and withinRaidSlice(work,budget,sliceStarted)do
    local raid=raids[state.tokenRaidCursor]
    if state.tokenBossCursor==0 then local token=raidKey(raid.name);if token then state.raidTokens=state.raidTokens or{};state.raidTokenSet=state.raidTokenSet or{};state.raidTokens[#state.raidTokens+1]=token;state.raidTokenSet[token]=true end;state.tokenBossCursor=1;work=work+1
    else
     local boss=(raid.bosses or{})[state.tokenBossCursor]
     if boss then local token=raidKey(boss.name);if token then state.bossTokens=state.bossTokens or{};state.bossTokenSet=state.bossTokenSet or{};state.bossTokens[#state.bossTokens+1]=token;state.bossTokenSet[token]=true end;state.tokenBossCursor=state.tokenBossCursor+1;work=work+1
     else state.tokenRaidCursor=state.tokenRaidCursor+1;state.tokenBossCursor=0 end
    end
   end
   if state.tokenRaidCursor>#(raids or{})then state.stage="metadata";state.categoryCursor=1 end
   return pending()
  end
  if state.stage=="metadata"then
   while state.categoryCursor<=#state.categories and withinRaidSlice(work,budget,sliceStarted)do
    local id=state.categories[state.categoryCursor];state.categoryCursor=state.categoryCursor+1;work=work+1
    if type(GetCategoryInfo)=="function"then audit.categoryInfoReads=audit.categoryInfoReads+1;local ok,name,parent=pcall(callAPI,"statisticCalls",GetCategoryInfo,id);if ok then state.categoryNames[id]={name=safeText(name),parent=safeNumber(parent)}else audit.apiFailures=audit.apiFailures+1 end end
   end
   if state.categoryCursor>#state.categories then state.stage="relevance";state.categoryCursor=1 end
   return pending()
  end
  if state.stage=="relevance"then
   local function relevant(name)
    local token=raidKey(name);if not token then return false end
    for _,wanted in ipairs(state.raidTokens or{})do if token:find(wanted,1,true)then return true end end
    for _,wanted in ipairs(state.bossTokens or{})do if token:find(wanted,1,true)then return true end end
    return false
   end
   local function relevantCategory(id)
    local visited={};while id and not visited[id]do visited[id]=true;local item=state.categoryNames[id];if not item then break end;local token=raidKey(item.name);if token and((state.tierToken and token:find(state.tierToken,1,true))or relevant(item.name))then return true end;id=item.parent end;return false
   end
   state.categoryRelevant=state.categoryRelevant or{};state.categoryHadRelevant=state.categoryHadRelevant or{}
   while state.categoryCursor<=#state.categories and withinRaidSlice(work,budget,sliceStarted)do local id=state.categories[state.categoryCursor];state.categoryCursor=state.categoryCursor+1;work=work+1;if relevantCategory(id)then state.categoryRelevant[id]=true;audit.relevantCategories=audit.relevantCategories+1 end end
   if state.categoryCursor>#state.categories then state.stage="statistics";state.categoryCursor=1;state.entryCursor=1;state.entryCount=nil end
   return pending()
  end
  if state.stage=="statistics"then
   while state.categoryCursor<=#state.categories and withinRaidSlice(work,budget,sliceStarted)do
    local categoryId=state.categories[state.categoryCursor]
    if state.pendingStatistic then
     local statisticId=state.pendingStatistic;state.pendingStatistic=nil;work=work+1;audit.labelReads=audit.labelReads+1
     local infoOk,_,name=pcall(callAPI,"statisticCalls",GetAchievementInfo,statisticId);if not infoOk then audit.apiFailures=audit.apiFailures+1 end;name=infoOk and safeText(name)or nil
     local parsed,rejectReason=parseStatisticLabel(name);local isRelevant=parsed and(state.raidTokenSet[parsed.raidToken]or state.bossTokenSet[parsed.bossToken])or false
     if not isRelevant and rejectReason and name then local token=raidKey(name);for _,wanted in ipairs(state.raidTokens or{})do if token and token:find(wanted,1,true)then isRelevant=true;break end end;if not isRelevant then for _,wanted in ipairs(state.bossTokens or{})do if token and token:find(wanted,1,true)then isRelevant=true;break end end end end
     if isRelevant then audit.relevantEntries=audit.relevantEntries+1;state.categoryHadRelevant[categoryId]=true end
     -- Unrelated historical rows cannot map a current raid slot. Do not retain,
     -- index or walk those thousands of rows on every subsequent refresh.
     if parsed and isRelevant then state.result[#state.result+1]={statisticId=statisticId,name=name,categoryId=categoryId,bossToken=parsed.bossToken,raidToken=parsed.raidToken,difficultyToken=parsed.difficultyToken};audit.candidates=audit.candidates+1 end
     if rejectReason and isRelevant then audit.discoveryRejected=audit.discoveryRejected+1;if manual and state.logged<24 then state.logged=state.logged+1;diagnostic("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CANDIDATE_REJECTED",{categoryId=categoryId,statisticId=statisticId,name=name,reason=rejectReason})end end
    elseif state.entryCount==nil then
     local countOk,count=pcall(callAPI,"statisticCalls",GetCategoryNumAchievements,categoryId);work=work+1;audit.categoriesEnumerated=audit.categoriesEnumerated+1;if not countOk then audit.apiFailures=audit.apiFailures+1 end;state.entryCount=countOk and safeNumber(count)or 0;state.entryCursor=1;if not countOk then state.entryCount=0 end
    elseif state.entryCursor>state.entryCount then state.categoryCursor=state.categoryCursor+1;state.entryCount=nil
    else
     local index=state.entryCursor;state.entryCursor=index+1;work=work+1;audit.entries=audit.entries+1
     local statOk,_,skip,statisticId=pcall(callAPI,"statisticCalls",GetStatistic,categoryId,index);if not statOk then audit.apiFailures=audit.apiFailures+1 end;statisticId=statOk and safeNumber(statisticId)or nil
     if statisticId and not skip and not state.seen[statisticId]then state.seen[statisticId]=true;audit.statisticIds=audit.statisticIds+1;state.pendingStatistic=statisticId end
    end
   end
   if state.categoryCursor<=#state.categories then return pending()end
   audit.relevantCategories=0;for _,id in ipairs(state.categories)do if state.categoryRelevant[id]or state.categoryHadRelevant[id]then audit.relevantCategories=audit.relevantCategories+1 end end
   state.stage="mapping_init";state.mapRaidCursor,state.mapBossCursor,state.mapDifficultyCursor=1,0,1;state.mapCandidateCursor=1;state.lookup={bySlot={},raidTokens={},bossTokens={},difficultyTokens={},slots=0,candidateComparisons=0,indexCandidates=#state.result,exactMappings=0,mappedSlots={}}
   return pending()
  end
  if state.stage=="mapping_init"then
   local lookup=state.lookup
   while state.mapRaidCursor<=#(raids or{})and withinRaidSlice(work,budget,sliceStarted)do
    local raid=raids[state.mapRaidCursor]
    if state.mapBossCursor==0 then local token=raidKey(raid.name);if token then lookup.raidTokens[token]=true end;state.mapBossCursor=1;work=work+1
    else local boss=(raid.bosses or{})[state.mapBossCursor];if boss then local token=raidKey(boss.name);if token then lookup.bossTokens[token]=true end;state.mapBossCursor=state.mapBossCursor+1;work=work+1 else state.mapRaidCursor=state.mapRaidCursor+1;state.mapBossCursor=0 end end
   end
   if state.mapRaidCursor>#(raids or{})then state.difficultyTokenCursor=state.difficultyTokenCursor or 1;while state.difficultyTokenCursor<=#lifetimeDifficultyOrder and withinRaidSlice(work,budget,sliceStarted)do local difficulty=lifetimeDifficultyOrder[state.difficultyTokenCursor];local token=raidKey(difficultyNames[difficulty]);if token then lookup.difficultyTokens[token]=true end;state.difficultyTokenCursor=state.difficultyTokenCursor+1;work=work+1 end;if state.difficultyTokenCursor>#lifetimeDifficultyOrder then state.stage="mapping_slots";state.mapRaidCursor,state.mapBossCursor,state.mapDifficultyCursor=1,1,1 end end
   return pending()
  end
  if state.stage=="mapping_slots"then
   local lookup=state.lookup
   while state.mapRaidCursor<=#(raids or{})and withinRaidSlice(work,budget,sliceStarted)do
    local raid=raids[state.mapRaidCursor];local boss=(raid.bosses or{})[state.mapBossCursor]
    if not boss then state.mapRaidCursor=state.mapRaidCursor+1;state.mapBossCursor,state.mapDifficultyCursor=1,1
    else local raidToken,bossToken=raidKey(raid.name),raidKey(boss.name);local difficulty=lifetimeDifficultyOrder[state.mapDifficultyCursor];local difficultyToken=raidKey(difficultyNames[difficulty]);lookup.slots=lookup.slots+1;work=work+1;if raidToken and bossToken and difficultyToken then local key=slotKey(raidToken,bossToken,difficultyToken);lookup.bySlot[key]=lookup.bySlot[key]or{}end;state.mapDifficultyCursor=state.mapDifficultyCursor+1;if state.mapDifficultyCursor>#lifetimeDifficultyOrder then state.mapDifficultyCursor=1;state.mapBossCursor=state.mapBossCursor+1 end end
   end
   if state.mapRaidCursor>#(raids or{})then state.stage="mapping_candidates"end
   return pending()
  end
  if state.stage=="mapping_candidates"then
   local lookup=state.lookup
   while state.mapCandidateCursor<=#state.result and withinRaidSlice(work,budget,sliceStarted)do local candidate=state.result[state.mapCandidateCursor];state.mapCandidateCursor=state.mapCandidateCursor+1;work=work+1;local key=slotKey(candidate.raidToken,candidate.bossToken,candidate.difficultyToken);local matches=lookup.bySlot[key];if matches then matches[#matches+1]=candidate;lookup.candidateComparisons=lookup.candidateComparisons+1;if not lookup.mappedSlots[key]then lookup.mappedSlots[key]=true;lookup.exactMappings=lookup.exactMappings+1 end end end
   if state.mapCandidateCursor<=#state.result then return pending()end
   lookup.mappedSlots=nil;audit.slots=lookup.slots;audit.exactMappings=lookup.exactMappings;audit.mappingProbes=lookup.slots;audit.candidateComparisons=lookup.candidateComparisons
   state.stage=manual and"category_logs"or"finish";state.categoryCursor=1;state.categoryLogged=0
   return pending()
  end
  if state.stage=="category_logs"then
   while state.categoryCursor<=#state.categories and withinRaidSlice(work,budget,sliceStarted)and state.categoryLogged<16 do local id=state.categories[state.categoryCursor];state.categoryCursor=state.categoryCursor+1;work=work+1;if state.categoryRelevant[id]or state.categoryHadRelevant[id]then state.categoryLogged=state.categoryLogged+1;local item=state.categoryNames[id];diagnostic("DEBUG","Raids","lifetime-discovery","RAID_LIFETIME_CATEGORY",{categoryId=id,name=item and item.name,parentId=item and item.parent})end end
   audit.categoryLogsTruncated=manual and math.max(0,audit.relevantCategories-state.categoryLogged)or 0
   if state.categoryCursor<=#state.categories and state.categoryLogged<16 then return pending()end
   state.stage="finish";return pending()
  end
  local complete=audit.apiFailures==0 and #state.result>0 and state.lookup.exactMappings>0;audit.cacheable=complete
  local completed={key=cacheKey,candidates=state.result,audit=HolyStorm.Utils.DeepCopy(audit),difficultyNames=difficultyNames,lookup=state.lookup}
  if complete then module.lifetimeStatisticCache=completed end
  return state.result,nil,audit,completed
 end
 function Module:GetLifetimeStatisticCandidates(raids,manual,tierName,state,maxWork,knownDifficultyNames)
  if maxWork~=nil then return collectLifetimeCandidatesChunked(self,raids,manual,tierName,state,maxWork,knownDifficultyNames)end
  local candidates,reason,audit,progress
  repeat candidates,reason,audit,progress=collectLifetimeCandidatesChunked(self,raids,manual,tierName,state,RAID_SCAN_WORK_BUDGET);state=progress until reason~="STATISTIC_DISCOVERY_IN_PROGRESS"
  return candidates,reason,audit,progress
 end
 local function captureLifetimeChunk(module,workState,manual)
  local state=workState.capture
  if not state then
   -- CharacterStore:GetBlock already returns a detached copy. Reuse it so the
   -- lifetime tree is not copied a second time before applying new values.
   local previous=workState.old and workState.old.lifetime;local lifetime=type(previous)=="table"and previous or{bosses={},seen={}};lifetime.bosses=type(lifetime.bosses)=="table"and lifetime.bosses or{};lifetime.seen=type(lifetime.seen)=="table"and lifetime.seen or{};if lifetime.reliable==nil then lifetime.reliable=false end
   state={lifetime=lifetime,candidates=workState.candidates,candidateReason=workState.candidateReason,audit=HolyStorm.Utils.DeepCopy(workState.candidateAudit or{}),cache=workState.candidateCache,unmappedLogged=0};workState.capture=state
   if manual then diagnostic("INFO","Raids","lifetime","RAID_LIFETIME_SCAN_STARTED",{raidCount=#(workState.raids or{}),tierName=workState.tierName})end
   if not state.candidates then
    diagnostic("DEBUG","Raids","lifetime","Raid Statistics APIs unavailable; retaining prior lifetime data",{reason=state.candidateReason})
    state.audit.records,state.audit.positiveBosses=0,0;state.summaryCursor=nil;state.stage="retained_summary";return nil,"IN_PROGRESS"
   end
   local audit=state.audit;audit.reason=state.candidateReason or"OK";audit.recognized=0;audit.valueReads=0;audit.reads=0;audit.positive=0;audit.zero=0;audit.unavailable=0;audit.mappedBosses=0;audit.unmapped=0;audit.missingMappings=0;audit.slots=0
   state.difficultyNames=state.cache and state.cache.difficultyNames or{};state.lookup=state.cache and state.cache.lookup;state.mappedIds={};state.mappedBossIds={};state.detailCount=0;state.raidCursor=1;state.bossCursor=1;state.difficultyCursor=1;state.stage="slots"
  end
  local budget=RAID_SCAN_WORK_BUDGET;local work=0;local sliceStarted=performanceClock();local audit=state.audit;local lifetime=state.lifetime
  if state.stage=="retained_summary"then
   while withinRaidSlice(work,budget,sliceStarted)do local key,boss=next(lifetime.bosses,state.summaryCursor);if key==nil then state.done=true;return lifetime,nil,audit end;state.summaryCursor=key;work=work+1;audit.records=audit.records+1;local found=false;for _,entry in pairs(type(boss)=="table"and type(boss.difficulties)=="table"and boss.difficulties or{})do if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)and(tonumber(entry.kills)or 0)>0 then found=true end end;if found then audit.positiveBosses=audit.positiveBosses+1 end end
   return nil,"IN_PROGRESS"
  end
  if state.stage=="slots"then
   while state.raidCursor<=#workState.raids and withinRaidSlice(work,budget,sliceStarted)do
    local raid=workState.raids[state.raidCursor];local boss=(raid.bosses or{})[state.bossCursor]
    if not boss then state.raidCursor=state.raidCursor+1;state.bossCursor,state.difficultyCursor=1,1
    else
     local difficulty=lifetimeDifficultyOrder[state.difficultyCursor];state.difficultyCursor=state.difficultyCursor+1;if state.difficultyCursor>#lifetimeDifficultyOrder then state.difficultyCursor=1;state.bossCursor=state.bossCursor+1 end
     audit.slots=audit.slots+1;work=work+1
     local raidToken,bossToken=raidKey(raid.name),raidKey(boss.name);local difficultyName=state.difficultyNames[difficulty];local key=slotKey(raidToken,bossToken,raidKey(difficultyName));local matches=state.lookup.bySlot[key]or{}
     audit.recognized=audit.recognized+#matches;audit.candidateComparisons=(audit.candidateComparisons or 0)+#matches
     local candidate=#matches==1 and matches[1]or nil;local raw,kills,accepted,why
     if not difficultyName then why="DIFFICULTY_NAME_UNAVAILABLE"
     elseif #matches==0 then why="NO_EXACT_STATISTIC";audit.missingMappings=audit.missingMappings+1
     elseif #matches>1 then why="AMBIGUOUS_STATISTIC";audit.missingMappings=audit.missingMappings+1
     else
      state.mappedIds[candidate.statisticId]=true;audit.valueReads=audit.valueReads+1;local ok,value=pcall(callAPI,"statisticCalls",GetStatistic,candidate.statisticId);raw=ok and value or nil;if not ok then audit.apiFailures=audit.apiFailures+1 end;kills=ok and safeStatisticValue(value)or nil;accepted=kills~=nil
      if accepted then audit.reads=audit.reads+1;if kills>0 then audit.positive=audit.positive+1 else audit.zero=audit.zero+1 end else audit.unavailable=audit.unavailable+1 end
      why=not ok and"STATISTIC_API_FAILED"or accepted and"ACCEPTED"or"STATISTIC_VALUE_UNAVAILABLE"
     end
     if accepted then local key=boss.id or boss.name;local stored=lifetime.bosses[key]or{};stored.id=boss.id;stored.encounterId=boss.id;stored.name=boss.name;stored.raidInstanceId=raid.id;stored.journalInstanceId=raid.id;stored.raidName=raid.name;stored.difficulties=type(stored.difficulties)=="table"and stored.difficulties or{};stored.difficulties[difficulty]={statisticId=candidate.statisticId,kills=kills,source="blizzard-statistic"};lifetime.bosses[key]=stored;local identity=tostring(raid.id).."\031"..tostring(key);if not state.mappedBossIds[identity]then state.mappedBossIds[identity]=true;audit.mappedBosses=audit.mappedBosses+1 end end
     if manual and state.detailCount<80 then state.detailCount=state.detailCount+1;local rawState,rawValue=safeRawState(raw);diagnostic("DEBUG","Raids","lifetime","RAID_LIFETIME_STAT",{raidInstanceId=raid.id,raidName=raid.name,bossId=boss.id,bossName=boss.name,difficulty=difficulty,statisticId=candidate and candidate.statisticId or 0,categoryId=candidate and candidate.categoryId,rawState=rawState,value=rawValue or"UNKNOWN",kills=kills,accepted=accepted==true,reason=why})end
    end
   end
   if state.raidCursor>#workState.raids then state.stage="unmapped";state.candidateCursor=1 end
   return nil,"IN_PROGRESS"
  end
  if state.stage=="unmapped"then
   while state.candidateCursor<=#(state.candidates or{})and withinRaidSlice(work,budget,sliceStarted)do local candidate=state.candidates[state.candidateCursor];state.candidateCursor=state.candidateCursor+1;work=work+1;audit.unmappedCandidateChecks=(audit.unmappedCandidateChecks or 0)+1
    if not state.mappedIds[candidate.statisticId]then local raidMatch=state.lookup.raidTokens[candidate.raidToken]==true;local bossMatch=state.lookup.bossTokens[candidate.bossToken]==true;local difficultyMatch=state.lookup.difficultyTokens[candidate.difficultyToken]==true;if raidMatch or bossMatch then audit.unmapped=audit.unmapped+1;local reason=not raidMatch and"RAID_NAME_NOT_FOUND"or not bossMatch and"BOSS_NAME_NOT_FOUND"or not difficultyMatch and"DIFFICULTY_NAME_NOT_FOUND"or"AMBIGUOUS_STATISTIC";if manual and state.unmappedLogged<24 then state.unmappedLogged=(state.unmappedLogged or 0)+1;diagnostic("DEBUG","Raids","lifetime","RAID_LIFETIME_UNMAPPED",{categoryId=candidate.categoryId,statisticId=candidate.statisticId,name=candidate.name,reason=reason})end end end
   end
   if state.candidateCursor>#(state.candidates or{})then state.stage="summary";state.summaryCursor=nil;state.records,state.positiveBosses=0,0;state.reliable=false end
   return nil,"IN_PROGRESS"
  end
  if state.stage=="summary"then
   while withinRaidSlice(work,budget,sliceStarted)do local key,boss=next(lifetime.bosses,state.summaryCursor);if key==nil then state.stage=manual and"raid_summary"or"finish";state.raidSummaryCursor,state.raidSummaryBossCursor=1,1;state.raidSummaryMapped,state.raidSummaryPositive=0,0;break end;state.summaryCursor=key;work=work+1;state.records=state.records+1;local found=false;for _,entry in pairs(type(boss)=="table"and type(boss.difficulties)=="table"and boss.difficulties or{})do if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)and(tonumber(entry.kills)or 0)>0 then found=true end;if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)then state.reliable=true end end;if found then state.positiveBosses=state.positiveBosses+1 end end
   if state.stage=="summary"then return nil,"IN_PROGRESS"end
   return nil,"IN_PROGRESS"
  end
  if state.stage=="raid_summary"then
   while state.raidSummaryCursor<=#workState.raids and withinRaidSlice(work,budget,sliceStarted)do local raid=workState.raids[state.raidSummaryCursor];local boss=(raid.bosses or{})[state.raidSummaryBossCursor]
    if not boss then diagnostic("DEBUG","Raids","lifetime","RAID_LIFETIME_RAID_SUMMARY",{raidInstanceId=raid.id,raidName=raid.name,catalogBosses=#(raid.bosses or{}),lifetimeBosses=state.raidSummaryMapped,positiveBosses=state.raidSummaryPositive});state.raidSummaryCursor=state.raidSummaryCursor+1;state.raidSummaryBossCursor=1;state.raidSummaryMapped,state.raidSummaryPositive=0,0
    else state.raidSummaryBossCursor=state.raidSummaryBossCursor+1;work=work+1;local stored=lifetime.bosses[boss.id or boss.name];if stored and tonumber(stored.raidInstanceId)==tonumber(raid.id)then state.raidSummaryMapped=state.raidSummaryMapped+1;for _,entry in pairs(stored.difficulties or{})do if type(entry)=="table"and entry.source=="blizzard-statistic"and tonumber(entry.statisticId)and(tonumber(entry.kills)or 0)>0 then state.raidSummaryPositive=state.raidSummaryPositive+1;break end end end end
   end
   if state.raidSummaryCursor>#workState.raids then state.stage="finish"end
   return nil,"IN_PROGRESS"
  end
  if not state.done then
   audit.records=state.records or 0;audit.positiveBosses=state.positiveBosses or 0;lifetime.reliable=state.reliable==true;audit.detailTruncated=manual and math.max(0,audit.slots-state.detailCount)or 0;lifetime.source=lifetime.reliable and"blizzard-statistic"or(lifetime.source or"legacy-local-observation");diagnostic(manual and"INFO"or"DEBUG","Raids","lifetime","RAID_LIFETIME_SCAN_SUMMARY",audit);state.done=true
  end
  return lifetime,nil,audit
 end
 local function collectLockoutsChunk(state,budget)
  local work=0;local sliceStarted=performanceClock()
  while withinRaidSlice(work,budget,sliceStarted)do
   if state.current then
    local current=state.current
    if current.bossCursor<=current.total then local x=current.bossCursor;current.bossCursor=x+1;local bossName,bossId,done=callAPI("savedInstanceCalls",GetSavedInstanceEncounterInfo,current.index,x);bossName=bossName or(current.name.." #"..x);bossId=bossId or(current.name..":"..x);current.bosses[x]={name=bossName,id=bossId,killed=done==true};if done then current.killed=current.killed+1 end;work=work+1
    else
     current.killed=math.max(current.killed,tonumber(current.encounterProgress)or 0);local catalog=state.journalByName[raidKey(current.name)];local isCurrent=catalog and tonumber(catalog.tier)==tonumber(state.tier);local item={name=current.name,lockoutId=current.id,journalInstanceId=catalog and catalog.id,reset=current.reset,difficultyId=current.difficultyId,difficultyName=current.difficultyName,extended=current.extended,maxPlayers=current.maxPlayers,bosses=current.bosses,killed=current.killed,total=current.total,isCurrent=isCurrent==true};state.snapshot.lockouts[#state.snapshot.lockouts+1]=item
     local currentKey=difficultyKeys[tonumber(item.difficultyId)];local bestKey=difficultyKeys[tonumber(state.snapshot.bestProgress.difficultyId)];local currentOrder,bestOrder=difficultyOrder[currentKey]or 0,difficultyOrder[bestKey]or 0;if item.isCurrent and item.killed>0 and(currentOrder>bestOrder or(currentOrder==bestOrder and item.killed>state.snapshot.bestProgress.killed))then state.snapshot.bestProgress={killed=item.killed,total=item.total,difficultyId=item.difficultyId,difficultyName=item.difficultyName,raidInstanceId=item.journalInstanceId,raidName=item.name}end
     state.current=nil;work=work+1
    end
   elseif state.savedCursor<=state.savedCount then
    local i=state.savedCursor;state.savedCursor=i+1;local name,id,reset,diff,locked,extended,_,isRaid,maxPlayers,diffName,encounters,encounterProgress=callAPI("savedInstanceCalls",GetSavedInstanceInfo,i);work=work+1
    if isRaid and locked then local safeName=name or L["UNKNOWN"];state.current={index=i,name=safeName,id=id,reset=reset,difficultyId=diff,extended=extended,maxPlayers=maxPlayers,difficultyName=diffName,total=math.max(0,tonumber(encounters)or 0),encounterProgress=encounterProgress,bosses={},killed=0,bossCursor=1}end
   else state.complete=true;break end
  end
  return state.complete==true
 end
 function Module:CollectChunked(manual,workState)
  local generation=tonumber(self.raidScanGeneration)or 0
  if not workState.catalogData then local data,status=self:CollectRaidCatalogChunk(workState,RAID_SCAN_WORK_BUDGET);if status=="IN_PROGRESS"then return nil,"IN_PROGRESS"end;if not data then return{pending=true,pendingReason=status or"raid catalog pending"}end;workState.catalogData=data;return nil,"IN_PROGRESS"end
  if not workState.initialized then
   local data=workState.catalogData;local tierName=data.tierName
   workState.initialized=true;workState.generation=generation;workState.raids=data.raids;workState.tier=data.tier;workState.tierName=tierName;workState.old=self:GetCharacterSnapshot(UnitGUID("player"));workState.journalByName=data.journalByName;workState.catalogReady=data.catalogReady;return nil,"IN_PROGRESS"
  end
  if not workState.difficultiesReady then
   workState.difficultyNames=workState.difficultyNames or self.raidDifficultyNames or{}
   if self.raidDifficultyNames then workState.difficultiesReady=true
   else
    local index=workState.difficultyCursor or 1;local key=lifetimeDifficultyOrder[index]
    if key then
     if type(GetDifficultyInfo)=="function"then local ok,name=pcall(callAPI,"statisticCalls",GetDifficultyInfo,lifetimeDifficultyIds[key]);if ok and type(name)=="string"then workState.difficultyNames[key]=name end end
     workState.difficultyCursor=index+1;return nil,"IN_PROGRESS"
    end
    -- Failed metadata remains retryable on a later scan.
    local complete=true;for _,difficulty in ipairs(lifetimeDifficultyOrder)do if not workState.difficultyNames[difficulty]then complete=false end end
    if complete then self.raidDifficultyNames=workState.difficultyNames end
    workState.difficultiesReady=true
   end
  end
  if not workState.candidatesReady then
   local candidates,reason,audit,progress=self:GetLifetimeStatisticCandidates(workState.raids,manual,workState.tierName,workState.discovery,RAID_SCAN_WORK_BUDGET,workState.difficultyNames)
   if reason=="STATISTIC_DISCOVERY_IN_PROGRESS"then workState.discovery=progress;return nil,"IN_PROGRESS"end
   local unavailable=not candidates and reason=="STATISTIC_API_UNAVAILABLE"
   if not unavailable and(not candidates or audit and(audit.apiFailures or 0)>0)then return{pending=true,pendingReason=reason or"STATISTIC_DISCOVERY_INCOMPLETE",currentRaid=workState.raids[1]and{id=workState.raids[1].id,name=workState.raids[1].name,tier=workState.tier}or nil,currentTier=workState.tier,catalogReady=workState.catalogReady,raids=workState.raids,lockouts={},lifetime=workState.old and workState.old.lifetime or{bosses={},seen={},reliable=false},snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}end
   workState.candidatesReady=true;workState.candidates=candidates;workState.candidateReason=reason;workState.candidateAudit=audit;workState.candidateCache=progress;return nil,"IN_PROGRESS"
  end
  if not workState.lifetimeReady then
   local lifetime,_,audit=captureLifetimeChunk(self,workState,manual);if not lifetime then return nil,"IN_PROGRESS"end
   if audit and audit.apiFailures>0 then return{pending=true,pendingReason="STATISTIC_VALUE_READ_FAILED",currentRaid=workState.raids[1]and{id=workState.raids[1].id,name=workState.raids[1].name,tier=workState.tier}or nil,currentTier=workState.tier,catalogReady=workState.catalogReady,raids=workState.raids,lockouts={},lifetime=workState.old and workState.old.lifetime or{bosses={},seen={},reliable=false},snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}end
   workState.lifetime=lifetime;workState.lifetimeReady=true;return nil,"IN_PROGRESS"
  end
  if workState.waitingForRaidInfo and not workState.instanceInfoReady then return nil,"WAITING_INSTANCE_INFO"end
  if not workState.snapshot then
   local latest=workState.raids[1]and{id=workState.raids[1].id,name=workState.raids[1].name,tier=workState.tier}or nil;local weeklyIdentity;local weeklyAPI=C_DateAndTime;if weeklyAPI and type(weeklyAPI.GetWeeklyResetStartTime)=="function"then local ok,value=pcall(weeklyAPI.GetWeeklyResetStartTime);if ok then weeklyIdentity=safeNumber(value)end end
   workState.snapshot={currentRaid=latest,currentTier=workState.tier,catalogReady=workState.catalogReady,raids=workState.raids,lockouts={},lifetime=workState.lifetime,weeklyIdentity=weeklyIdentity,updatedAt=HolyStorm.Utils.Now(),snapshotVersion=3,bestProgress={killed=0,total=0,difficultyId=0}}
   workState.lockouts={snapshot=workState.snapshot,journalByName=workState.journalByName,tier=workState.tier,savedCount=GetNumSavedInstances and math.max(0,tonumber(callAPI("savedInstanceCalls",GetNumSavedInstances))or 0)or 0,savedCursor=1,complete=false};return nil,"IN_PROGRESS"
  end
  if not workState.lockouts.complete then collectLockoutsChunk(workState.lockouts,RAID_SCAN_WORK_BUDGET);if not workState.lockouts.complete then return nil,"IN_PROGRESS"end end
  if manual then local audit=workState.capture and workState.capture.audit or{};diagnostic("INFO","Raids","lifetime","RAID_LIFETIME_SNAPSHOT",{schema=workState.snapshot.snapshotVersion,raids=#workState.snapshot.raids,lockouts=#workState.snapshot.lockouts,lifetimeBosses=audit.records or 0,positiveBosses=audit.positiveBosses or 0,updatedAt=workState.snapshot.updatedAt})end
  return workState.snapshot
 end
 function Module:Collect(manual,workState)
  workState=workState or{}
  local slice=workState.slice or{};workState.slice=slice
  local snapshot,status
  repeat
   slice.operations=0;slice.started=performanceClock();slice.workState=workState;slice.run=workState.metrics;currentSlice=slice
   snapshot,status=self:CollectChunked(manual,workState)
   currentSlice=nil
  until workState.chunked or status~="IN_PROGRESS"
  if status~="IN_PROGRESS"and status~="WAITING_INSTANCE_INFO"then self.lastRaidDiagnostics={audit=workState.capture and workState.capture.audit,details=workState.diagnostics or{}}end
  return snapshot,status
 end
 function Module:CaptureLifetime(raids,previous,manual,tierName,candidatesOverride,auditOverride,cacheOverride)
  local candidates,reason,audit,cache=candidatesOverride,nil,auditOverride,cacheOverride
  if candidates==nil then candidates,reason,audit,cache=self:GetLifetimeStatisticCandidates(raids,manual,tierName)end
  local state={raids=raids,old={lifetime=HolyStorm.Utils.DeepCopy(previous)},tierName=tierName,candidates=candidates,candidateReason=reason,candidateAudit=audit,candidateCache=cache}
  local lifetime,_,resultAudit
  repeat lifetime,_,resultAudit=captureLifetimeChunk(self,state,manual)until lifetime
  return lifetime,resultAudit
 end
 function Module:Validate(s)if type(s)=="table"and s.pending then return false,s.pendingReason or"raid catalog pending"end;if type(s)~="table"or type(s.lockouts)~="table"or type(s.raids)~="table"or type(s.lifetime)~="table"or type(s.lifetime.bosses)~="table"then return false,"instance data unavailable"end;for _,r in ipairs(s.lockouts)do if type(r)~="table"or not r.name or not r.difficultyId or type(r.bosses)~="table"then return false,"lockout incomplete"end end;for _,raid in ipairs(s.raids)do if type(raid)~="table"or not tonumber(raid.id)or type(raid.name)~="string"or type(raid.bosses)~="table"or #raid.bosses==0 then return false,"raid catalog incomplete"end;local seen={};for index,boss in ipairs(raid.bosses)do if type(boss)~="table"then return false,"raid boss catalog incomplete"end;local order=tonumber(boss.order);if not tonumber(boss.id)or type(boss.name)~="string"or not order or order<1 or order%1~=0 or seen[order]then return false,"raid boss catalog incomplete"end;seen[order]=true;if order~=index then return false,"raid boss order incomplete"end end end;if not s.catalogReady then return false,"raid catalog pending"end;return true end
 function Module:Commit(s,_,_,lifetimeAudit)
  local guid=UnitGUID("player");local ok,reason=HolyStorm.PlayerData:WriteOwnedBlock(guid,"raid",s,"blizzard")
  local meta=HolyStorm.Data.CharacterStore and HolyStorm.Data.CharacterStore.GetBlockMetadata and HolyStorm.Data.CharacterStore:GetBlockMetadata(guid,"raid")
  local records,positive;if type(lifetimeAudit)=="table"then records=lifetimeAudit.records or 0;positive=lifetimeAudit.positiveBosses or 0 else records,positive=countLifetime(s and s.lifetime)end
  HolyStorm.Logger:Write(ok and"INFO"or"WARN","Raids","lifetime","RAID_LIFETIME_COMMIT",{committed=ok==true,reason=not ok and reason or nil,version=meta and meta.version,schema=s and s.snapshotVersion,lifetimeBosses=records,positiveBosses=positive})
  return ok,reason
 end
 local performanceFields={"totalWallMs","totalLuaMs","slices","maxSliceMs","taskLifecycleCount","catalogBuilds","ejCalls","statisticCalls","savedInstanceCalls","restarts","followUpQueued","expectedInstanceInfoEvents","unexpectedRaidEvents"}
 function Module:GetScanPerformance()return self.lastScanPerformance and HolyStorm.Utils.DeepCopy(self.lastScanPerformance)end
 local function publishPerformance(run,workflow)
  if run.performancePublished then return end;run.performancePublished=true
  run.totalWallMs=math.max(0,performanceClock()-run.startedClock)*1000
  local measured=0
  for id in pairs(run.taskIds)do local task=HolyStorm.Tasks.tasks[id];measured=measured+(task and task.executionDuration or 0)end
  run.totalLuaMs=math.max(run.totalLuaMs,measured*1000)
  local summary={workflowId=run.workflowId,status=workflow and workflow.status or"UNKNOWN"}
  for _,key in ipairs(performanceFields)do summary[key]=run[key]end
  Module.lastScanPerformance=summary
  HolyStorm.Logger:Write("INFO","Raids","scan","RAID_SCAN_PERFORMANCE",summary,run.workflowId)
 end
 function Module:Queue(sync,delay,requestRaidInfo,manual,reason)
  if self.activeRaidRun then return true,self.activeRaidRun.workflowId end
  local run={generation=self.raidScanGeneration or 0,startedClock=performanceClock(),taskIds={}}
  for _,key in ipairs(performanceFields)do run[key]=0 end
  run.instanceInfoReady=requestRaidInfo==false or type(RequestRaidInfo)~="function"
  local function newWorkState()return{chunked=true,metrics=run,generation=run.generation,waitingForRaidInfo=not run.instanceInfoReady,instanceInfoReady=run.instanceInfoReady}end
  run.workState=newWorkState()
  local function scanner(task)
   local started=performanceClock();run.slices=run.slices+1;run.scanTaskId=task and task.uniqueId or run.scanTaskId
   if run.scanComplete or run.generation~=(Module.raidScanGeneration or 0)then
    run.restarts=run.restarts+1;run.generation=Module.raidScanGeneration or 0;run.workState=newWorkState();run.scanComplete=false
   end
   local ok,snapshot,status=pcall(Module.Collect,Module,manual,run.workState);currentSlice=nil
   local duration=math.max(0,performanceClock()-started)*1000;run.totalLuaMs=run.totalLuaMs+duration;run.maxSliceMs=math.max(run.maxSliceMs,duration)
   if not ok then error(snapshot)end
   if status=="IN_PROGRESS"then return HolyStorm.Tasks:Yield(task)end
   if status=="WAITING_INSTANCE_INFO"then return HolyStorm.Tasks:WaitForResume(task,10)end
   run.snapshotGeneration=run.generation;run.scanComplete=true;run.lifetimeAudit=run.workState.capture and run.workState.capture.audit
   return snapshot
  end
  local function validator(snapshot)
   local started=performanceClock();local valid,why
   if run.snapshotGeneration~=(Module.raidScanGeneration or 0)then valid,why=false,"RAID_SCAN_STALE"else valid,why=Module:Validate(snapshot)end
   run.totalLuaMs=run.totalLuaMs+math.max(0,performanceClock()-started)*1000;return valid,why
  end
  local function commit(snapshot,fingerprint)
   if run.snapshotGeneration~=(Module.raidScanGeneration or 0)then return{workflowAction="RETRY",gotoStep=1,maxRetries=5,reason="RAID_SCAN_STALE"}end
   local started=performanceClock();run.commitStarted=true
   local committed,why=Module:Commit(snapshot,fingerprint,sync,run.lifetimeAudit);run.committed=committed~=false
   run.totalLuaMs=run.totalLuaMs+math.max(0,performanceClock()-started)*1000
   return committed,why
  end
  -- PlayerData owns the atomic comparison/revision contract. The generic
  -- Snapshot fingerprint was an unused extra full traversal for this producer.
  local queued,workflowId=HolyStorm.Snapshots:Queue("raids",scanner,validator,commit,{source="Raids",triggerSource=reason or"RAID_SCAN",delay=delay or 1,retryDelay=2.5,priority=3,maxRetries=5,fingerprint=false})
  if queued then
   run.workflowId=workflowId;self.activeRaidRun=run
   if not run.instanceInfoReady then
    run.raidInfoRequested=true;self.raidInfoRequestPending=true
    local ok=pcall(RequestRaidInfo)
    if not ok then self.raidInfoRequestPending=nil;HolyStorm.Workflows:Cancel(workflowId,"REQUEST_RAID_INFO_FAILED");return false,nil end
   end
  end
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
  local run=Module.activeRaidRun
  -- This response also arrives in cities/world zones. Consume it before Raid
  -- trigger filtering and resume the same waiting task, never another scan.
  if event=="UPDATE_INSTANCE_INFO"and(Module.raidInfoRequestPending or run and run.raidInfoRequested)then
   Module.raidInfoRequestPending=nil
   if not run then return true end
   run.raidInfoRequested=false;run.instanceInfoReady=true;run.workState.instanceInfoReady=true
   run.expectedInstanceInfoEvents=run.expectedInstanceInfoEvents+1
   if run.scanTaskId then HolyStorm.Tasks:ResumeTask(run.scanTaskId)end
   return true
  end
  if not inRaidInstance()then return false end
  if event=="ENCOUNTER_END"and success~=1 then return false end
  if run then
   run.unexpectedRaidEvents=run.unexpectedRaidEvents+1
   if not run.dirtyAfterScan then
    run.dirtyAfterScan=true;run.followUpQueued=run.followUpQueued+1
    HolyStorm.CharacterScans:Request("raid",event,true,{order=30})
   end
   return true
  end
  Module.raidScanGeneration=(Module.raidScanGeneration or 0)+1
  return HolyStorm.CharacterScans:Request("raid",event,true,{order=30})
 end
 function Module:OnEnable()
  HolyStorm.Events:Register("UPDATE_INSTANCE_INFO","raids",function(event)requestRaidRefresh(event)end)
  HolyStorm.Events:Register("ENCOUNTER_END","raids",function(event,encounterId,encounterName,difficultyId,groupSize,success)requestRaidRefresh(event,success)end)
  HolyStorm.Events:Register("HS_TASK_STARTED","raids-run",function(_,task)
   local run=Module.activeRaidRun;if run and task.workflowId==run.workflowId and not run.taskIds[task.uniqueId]then run.taskIds[task.uniqueId]=true;run.taskLifecycleCount=run.taskLifecycleCount+1 end
  end)
  local function releaseRun(_,workflow)
   local run=Module.activeRaidRun
   if run and workflow and run.workflowId==workflow.workflowId then
    publishPerformance(run,workflow);Module.activeRaidRun=nil;currentSlice=nil
   end
  end
  for _,event in ipairs({"HS_WORKFLOW_COMPLETED","HS_WORKFLOW_FAILED","HS_WORKFLOW_CANCELLED"})do HolyStorm.Events:Register(event,"raids-run",releaseRun)end
  local context=self.loadContext
  if context and context.reason=="event"and context.trigger=="ENCOUNTER_END"then local args=context.arguments or{};requestRaidRefresh(context.trigger,args[5],true)end
 end
 function Module:OnDisable()HolyStorm.Snapshots:Cancel("raids");HolyStorm.Events:UnregisterOwner("raids");HolyStorm.Events:UnregisterOwner("raids-run");self.activeRaidRun=nil;self.raidInfoRequestPending=nil end
end)
