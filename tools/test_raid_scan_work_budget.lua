-- Deterministic Statistics traversal and cache-work budget regression.
local root=(arg[0]:gsub("tools[/\\]test_raid_scan_work_budget.lua$",""))
local calls={apiCalls=0,categories=0,categoryInfo=0,categoryCounts=0,entries=0,achievementInfo=0,valueReads=0,instances=0,instanceInfo=0,selectInstance=0,encounters=0,savedInstances=0,savedEncounters=0}
local logs,Module={},nil
local locale=setmetatable({UNKNOWN="Unknown"},{__index=function(_,key)return key end})
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,item in pairs(value)do out[copy(key,seen)]=copy(item,seen)end;return out end
local storedSnapshot,commitCount,fakeTime=nil,0,0
local HolyStorm={Utils={DeepCopy=copy,Now=function()return 1000 end},Events={},Logger={},PlayerData={},Tasks={schedulerYieldDelay=1/60},Data={CharacterStore={GetBlock=function()return copy(storedSnapshot)end}},Snapshots={}}
function HolyStorm.Logger:Write(level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.PlayerData:RegisterBlock()return true end
function HolyStorm.PlayerData:WriteOwnedBlock(_,block,snapshot)assert(block=="raid");commitCount=commitCount+1;storedSnapshot=copy(snapshot);return true end
function HolyStorm:RegisterModule(_,factory)Module={};factory(Module)end
function HolyStorm:ApplyModuleMetadata(target,metadata)target.metadata=metadata end
function HolyStorm:RegisterCapability()end
function HolyStorm.Events:Register()end
function HolyStorm.Snapshots:Queue(id,scanner,validator,commit,options)self.id,self.scanner,self.validator,self.commit,self.options=id,scanner,validator,commit,options;return true,"wf-performance"end
function HolyStorm.Data.CharacterStore:GetBlock()return nil end
function HolyStorm.Data.CharacterStore:GetBlockMetadata()return nil end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;error("unexpected library "..tostring(name))end
function UnitGUID()return"Player-Performance"end

local selectedTier=1
local raidName="Storm Test Raid"
local bosses={}
for index=1,8 do bosses[index]={id=5000+index,name="Storm Boss "..index}end
local savedInstances={
 {difficultyId=14,difficultyName="Normal",kills={true,true,true,true,true,true,true,false}},
 {difficultyId=15,difficultyName="Heroic",kills={true,true,true,true,true,true,true,true}},
}
function GetTime()return fakeTime end
function EJ_GetNumTiers()calls.apiCalls=calls.apiCalls+1;return 1 end
function EJ_GetCurrentTier()calls.apiCalls=calls.apiCalls+1;return 1 end
function EJ_GetTierInfo()calls.apiCalls=calls.apiCalls+1;return"Storm Fixture"end
function EJ_SelectTier(tier)calls.apiCalls=calls.apiCalls+1;selectedTier=tier end
function EJ_GetInstanceByIndex(index,isRaid)calls.apiCalls=calls.apiCalls+1;calls.instances=calls.instances+1;if selectedTier==1 and index==1 and isRaid then return 900,raidName end end
function EJ_SelectInstance()calls.apiCalls=calls.apiCalls+1;calls.selectInstance=calls.selectInstance+1 end
function EJ_GetInstanceInfo()calls.apiCalls=calls.apiCalls+1;calls.instanceInfo=calls.instanceInfo+1;return nil,nil,nil,nil,nil,nil,nil,nil,true end
function EJ_GetEncounterInfoByIndex(index)calls.apiCalls=calls.apiCalls+1;calls.encounters=calls.encounters+1;local boss=bosses[index];if boss then return boss.name,nil,boss.id end end
function GetNumSavedInstances()calls.apiCalls=calls.apiCalls+1;return#savedInstances end
function GetSavedInstanceInfo(index)calls.apiCalls=calls.apiCalls+1;calls.savedInstances=calls.savedInstances+1;local instance=savedInstances[index];return raidName,8000+index,3600,instance.difficultyId,true,false,nil,true,20,instance.difficultyName,#instance.kills,0 end
function GetSavedInstanceEncounterInfo(index,bossIndex)calls.apiCalls=calls.apiCalls+1;calls.savedEncounters=calls.savedEncounters+1;local boss=bosses[bossIndex];return boss.name,boss.id,savedInstances[index].kills[bossIndex]end
function GetDifficultyInfo(id)calls.apiCalls=calls.apiCalls+1;return({[17]="Raid Finder",[14]="Normal",[15]="Heroic",[16]="Mythic"})[id]end

local statisticRows,statisticsById={},{}
statisticRows[1]={id=700000,name="Storm Boss 1 (Normal: Storm Test Raid)",value="9"};statisticsById[700000]=statisticRows[1]
for index=2,1025 do statisticRows[index]={id=700000+index,name="Other Boss "..index.." (Mythic: Other Raid "..index..")",value="1"};statisticsById[statisticRows[index].id]=statisticRows[index]end
local categoryIds={};for index=1,96 do categoryIds[index]=index==1 and 9001 or 9000+index end
function GetStatisticsCategoryList()calls.apiCalls=calls.apiCalls+1;calls.categories=calls.categories+1;return categoryIds end
function GetCategoryInfo(id)calls.apiCalls=calls.apiCalls+1;calls.categoryInfo=calls.categoryInfo+1;if id==9001 then return raidName,-1 end;return"Generic Statistics "..id,-1 end
function GetCategoryNumAchievements(id)calls.apiCalls=calls.apiCalls+1;calls.categoryCounts=calls.categoryCounts+1;if id==9001 then return#statisticRows end;return 0 end
function GetStatistic(id,index)
 calls.apiCalls=calls.apiCalls+1;if index~=nil then calls.entries=calls.entries+1;if id~=9001 then return nil,false,nil end;local row=statisticRows[index];return row and row.value,false,row and row.id end
 calls.valueReads=calls.valueReads+1;local row=statisticsById[id];return row and row.value
end
function GetAchievementInfo(id)calls.apiCalls=calls.apiCalls+1;calls.achievementInfo=calls.achievementInfo+1;local row=statisticsById[id];if row then return id,row.name end end

assert(loadfile(root.."LIVE/Holy_Storm_Raids/Raids.lua"))()
local queued,workflowId=Module:Queue(false,0,false,true,"PERFORMANCE_FIXTURE")
assert(queued and workflowId=="wf-performance"and HolyStorm.Snapshots.id=="raids","the Raid producer enters the existing snapshot workflow")
local chunkCount,snapshot=0,nil
while not snapshot do
 chunkCount=chunkCount+1;assert(chunkCount<1000,"the deterministic scan completes in bounded work units")
 fakeTime=fakeTime+1/60;local before={apiCalls=calls.apiCalls,categoryInfo=calls.categoryInfo,categoryCounts=calls.categoryCounts,entries=calls.entries,achievementInfo=calls.achievementInfo}
 local result=HolyStorm.Snapshots.scanner()
 assert(calls.apiCalls-before.apiCalls<=8,"each scheduler step stays within the explicit eight-call work budget (observed "..tostring(calls.apiCalls-before.apiCalls)..")")
 assert(calls.categoryInfo-before.categoryInfo<=8,"each scan task reads at most eight category labels")
 assert(calls.categoryCounts-before.categoryCounts<=8,"each scan task counts at most eight categories")
 assert(calls.entries-before.entries<=8,"each scan task enumerates at most eight Statistics rows")
 assert(calls.achievementInfo-before.achievementInfo<=8,"each scan task reads at most eight statistic labels")
 if type(result)=="table"and result.workflowAction=="GOTO"then assert(result.gotoStep==1 and result.delay==HolyStorm.Tasks.schedulerYieldDelay,"each bounded chunk resumes through the existing delayed TaskManager workflow");assert(commitCount==0 and storedSnapshot==nil,"no intermediate catalog, Statistics or lifetime state is committed")else snapshot=result end
end
assert(chunkCount>100 and calls.categories==1 and calls.categoryInfo==96 and calls.categoryCounts==96 and calls.entries==1025 and calls.achievementInfo==1025,"large Statistics discovery is traversed once, in category and row batches")
assert(Module:Validate(snapshot),"the chunked Raid snapshot validates only after discovery completes")
assert(#snapshot.lockouts==2 and #snapshot.lockouts[1].bosses==8 and #snapshot.lockouts[2].bosses==8,"all lockout instances and encounter records survive chunked collection")
assert(snapshot.bestProgress.killed==8 and snapshot.bestProgress.total==8 and snapshot.bestProgress.difficultyId==15 and snapshot.bestProgress.raidInstanceId==900,"chunked best-progress selection retains the current Raid's highest difficulty and identity")
assert(calls.savedInstances==2 and calls.savedEncounters==16,"lockout info and all saved encounters are collected exactly once")
assert(snapshot.lifetime.bosses[5001].difficulties.NORMAL.kills==9 and snapshot.lifetime.bosses[5001].difficulties.NORMAL.statisticId==700000 and snapshot.lifetime.bosses[5001].difficulties.NORMAL.source=="blizzard-statistic","the runtime mapping retains the Blizzard statistic source and exact value")
local audit;for _,entry in ipairs(logs)do if entry.message=="RAID_LIFETIME_SCAN_SUMMARY"then audit=entry.context end end
assert(audit and audit.categories==96 and audit.categoriesListCalls==1 and audit.categoryInfoReads==96 and audit.categoriesEnumerated==96 and audit.entries==1025 and audit.statisticIds==1025 and audit.labelReads==1025 and audit.candidates==1025 and audit.valueReads==1 and audit.mappingProbes==32 and audit.unmappedCandidateChecks==1025 and audit.candidateComparisons<=1100 and audit.workChunks>0 and audit.workChunks<chunkCount,"audit counters show linear index construction, direct value reads and bounded slot probes")
local performance;for _,entry in ipairs(logs)do if entry.message=="RAID_SCAN_PERFORMANCE"then performance=entry.context end end
assert(performance and performance.schedulerSteps==chunkCount and performance.elapsedSeconds>0 and performance.luaExecutionSeconds>=0 and performance.queueWaitSeconds>=0 and performance.longestStepSeconds>=0,"scan performance reports scheduler steps, wall duration, Lua time, queue wait and longest step")
local valid,validationReason=HolyStorm.Snapshots.validator(snapshot);assert(valid,validationReason)
assert(HolyStorm.Snapshots.commit(snapshot,"fixture-fingerprint")and commitCount==1 and storedSnapshot.snapshotVersion==3,"only the final validated snapshot reaches the commit stage")
local lastValidStored=storedSnapshot

-- Manual and automatic refreshes read current values by the cached IDs without a second tree walk.
local oldCategories,oldInfo,oldCounts,oldEntries,oldNames=calls.categories,calls.categoryInfo,calls.categoryCounts,calls.entries,calls.achievementInfo
local second=Module:Collect(true)
assert(Module:Validate(second)and second.lifetime.bosses[5001].difficulties.NORMAL.kills==9,"a manual refresh still reads current lifetime values")
assert(calls.categories==oldCategories and calls.categoryInfo==oldInfo and calls.categoryCounts==oldCounts and calls.entries==oldEntries and calls.achievementInfo==oldNames,"valid ID mapping cache prevents repeated category and label discovery")
assert(calls.valueReads==2,"each same-catalog scan reads the mapped statistic value directly")

-- Empty discovery is not cached and can recover when Blizzard data becomes available.
Module:InvalidateLifetimeStatisticCache("EMPTY_DISCOVERY_TEST")
local savedCategories=GetStatisticsCategoryList
GetStatisticsCategoryList=function()calls.categories=calls.categories+1;return{}end
local missing,reason=Module:GetLifetimeStatisticCandidates(snapshot.raids,true,"Storm Fixture")
assert(not missing and reason=="STATISTIC_CATEGORIES_EMPTY"and Module.lifetimeStatisticCache==nil,"empty category discovery remains retryable and does not poison the cache")
GetStatisticsCategoryList=savedCategories
local rebuilt,rebuiltReason=Module:GetLifetimeStatisticCandidates(snapshot.raids,true,"Storm Fixture")
assert(rebuilt and not rebuiltReason and Module.lifetimeStatisticCache,"a later complete discovery can rebuild the runtime mapping")

-- An API failure makes the complete Raid scan pending, so no partial snapshot reaches commit.
Module:InvalidateLifetimeStatisticCache("FAILED_DISCOVERY_TEST")
local savedCategoryInfo=GetCategoryInfo
GetCategoryInfo=function(id)if id==9002 then error("temporary category API failure")end;return savedCategoryInfo(id)end
local failedQueued,failedWorkflow=Module:Queue(false,0,false,true,"FAILED_DISCOVERY_TEST");assert(failedQueued and failedWorkflow=="wf-performance")
local failedScan
for index=1,1000 do fakeTime=fakeTime+1/60;local result=HolyStorm.Snapshots.scanner();if type(result)=="table"and result.workflowAction~="GOTO"then failedScan=result;break end end
local failedValid=Module:Validate(failedScan)
assert(failedScan and failedScan.pending and not failedValid and Module.lifetimeStatisticCache==nil and commitCount==1 and storedSnapshot==lastValidStored,"an intermediate discovery failure cannot validate/commit partial data or replace the last valid snapshot")
GetCategoryInfo=savedCategoryInfo
local recovered,recoveredReason=Module:GetLifetimeStatisticCandidates(snapshot.raids,true,"Storm Fixture")
assert(recovered and not recoveredReason and Module.lifetimeStatisticCache,"a later complete discovery can rebuild the runtime mapping")
local savedStatistic=GetStatistic
local injectedFailures=0
GetStatistic=function(id,index)if index==nil then injectedFailures=injectedFailures+1;error("temporary value read failure")end;return savedStatistic(id,index)end
local failedValueQueued=Module:Queue(false,0,false,true,"FAILED_VALUE_READ_TEST");assert(failedValueQueued)
local failedValueScan
for index=1,1000 do fakeTime=fakeTime+1/60;local before=calls.apiCalls;local result=HolyStorm.Snapshots.scanner();assert(calls.apiCalls-before<=8,"failed value-read work also respects the per-pass API budget");if type(result)=="table"and result.workflowAction~="GOTO"then failedValueScan=result;break end end
local failedValueValid=Module:Validate(failedValueScan)
local failedValueAudit;for _,entry in ipairs(logs)do if entry.message=="RAID_LIFETIME_SCAN_SUMMARY"then failedValueAudit=entry.context end end
assert(failedValueScan and failedValueScan.pending and failedValueScan.pendingReason=="STATISTIC_VALUE_READ_FAILED"and injectedFailures==1 and not failedValueValid and commitCount==1 and storedSnapshot==lastValidStored,"a mid-capture API failure preserves the previously committed snapshot and cannot commit a partial update (reason="..tostring(failedValueScan and failedValueScan.pendingReason)..", pending="..tostring(failedValueScan and failedValueScan.pending)..", valid="..tostring(failedValueValid)..", injected="..tostring(injectedFailures)..", valueReads="..tostring(calls.valueReads)..", mapped="..tostring(failedValueAudit and failedValueAudit.valueReads)..", commits="..tostring(commitCount)..")")
GetStatistic=savedStatistic
print("Raid Statistics discovery batches, exact mapping cache and work-count bounds passed")
