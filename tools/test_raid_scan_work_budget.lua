-- Deterministic Statistics traversal and cache-work budget regression.
local root=(arg[0]:gsub("tools[/\\]test_raid_scan_work_budget.lua$",""))
local calls={categories=0,categoryInfo=0,categoryCounts=0,entries=0,achievementInfo=0,valueReads=0}
local logs,Module={},nil
local locale=setmetatable({UNKNOWN="Unknown"},{__index=function(_,key)return key end})
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,item in pairs(value)do out[copy(key,seen)]=copy(item,seen)end;return out end
local HolyStorm={Utils={DeepCopy=copy,Now=function()return 1000 end},Events={},Logger={},Data={CharacterStore={GetBlock=function()end}},Snapshots={}}
function HolyStorm.Logger:Write(level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end
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
function EJ_GetNumTiers()return 1 end
function EJ_GetCurrentTier()return 1 end
function EJ_GetTierInfo()return"Storm Fixture"end
function EJ_SelectTier(tier)selectedTier=tier end
function EJ_GetInstanceByIndex(index,isRaid)if selectedTier==1 and index==1 and isRaid then return 900,raidName end end
function EJ_SelectInstance()end
function EJ_GetInstanceInfo()return nil,nil,nil,nil,nil,nil,nil,nil,true end
function EJ_GetEncounterInfoByIndex(index)local boss=bosses[index];if boss then return boss.name,nil,boss.id end end
function GetNumSavedInstances()return 0 end
function GetDifficultyInfo(id)return({[17]="Raid Finder",[14]="Normal",[15]="Heroic",[16]="Mythic"})[id]end

local statisticRows,statisticsById={},{}
statisticRows[1]={id=700000,name="Storm Boss 1 (Normal: Storm Test Raid)",value="9"};statisticsById[700000]=statisticRows[1]
for index=2,1025 do statisticRows[index]={id=700000+index,name="Other Boss "..index.." (Mythic: Other Raid "..index..")",value="1"};statisticsById[statisticRows[index].id]=statisticRows[index]end
local categoryIds={};for index=1,96 do categoryIds[index]=index==1 and 9001 or 9000+index end
function GetStatisticsCategoryList()calls.categories=calls.categories+1;return categoryIds end
function GetCategoryInfo(id)calls.categoryInfo=calls.categoryInfo+1;if id==9001 then return raidName,-1 end;return"Generic Statistics "..id,-1 end
function GetCategoryNumAchievements(id)calls.categoryCounts=calls.categoryCounts+1;if id==9001 then return#statisticRows end;return 0 end
function GetStatistic(id,index)
 if index~=nil then calls.entries=calls.entries+1;if id~=9001 then return nil,false,nil end;local row=statisticRows[index];return row and row.value,false,row and row.id end
 calls.valueReads=calls.valueReads+1;local row=statisticsById[id];return row and row.value
end
function GetAchievementInfo(id)calls.achievementInfo=calls.achievementInfo+1;local row=statisticsById[id];if row then return id,row.name end end

assert(loadfile(root.."LIVE/Holy_Storm_Raids/Raids.lua"))()
local queued,workflowId=Module:Queue(false,0,false,true,"PERFORMANCE_FIXTURE")
assert(queued and workflowId=="wf-performance"and HolyStorm.Snapshots.id=="raids","the Raid producer enters the existing snapshot workflow")
local chunkCount,snapshot=0,nil
while not snapshot do
 chunkCount=chunkCount+1;assert(chunkCount<100,"the deterministic scan completes in bounded work units")
 local before={categoryInfo=calls.categoryInfo,categoryCounts=calls.categoryCounts,entries=calls.entries,achievementInfo=calls.achievementInfo}
 local result=HolyStorm.Snapshots.scanner()
 assert(calls.categoryInfo-before.categoryInfo<=32,"each scan task reads at most 32 category labels (observed "..tostring(calls.categoryInfo-before.categoryInfo)..")")
 assert(calls.categoryCounts-before.categoryCounts<=32,"each scan task counts at most 32 categories")
 assert(calls.entries-before.entries<=32,"each scan task enumerates at most 32 Statistics rows")
 assert(calls.achievementInfo-before.achievementInfo<=32,"each scan task reads at most 32 statistic labels")
 if type(result)=="table"and result.workflowAction=="GOTO"then assert(result.gotoStep==1,"a yielded chunk resumes the same scan task");else snapshot=result end
end
assert(chunkCount>30 and calls.categories==1 and calls.categoryInfo==96 and calls.categoryCounts==96 and calls.entries==1025 and calls.achievementInfo==1025,"large Statistics discovery is traversed once, in category and row batches")
assert(Module:Validate(snapshot),"the chunked Raid snapshot validates only after discovery completes")
assert(snapshot.lifetime.bosses[5001].difficulties.NORMAL.kills==9 and snapshot.lifetime.bosses[5001].difficulties.NORMAL.statisticId==700000 and snapshot.lifetime.bosses[5001].difficulties.NORMAL.source=="blizzard-statistic","the runtime mapping retains the Blizzard statistic source and exact value")
local audit;for _,entry in ipairs(logs)do if entry.message=="RAID_LIFETIME_SCAN_SUMMARY"then audit=entry.context end end
assert(audit and audit.categories==96 and audit.categoriesListCalls==1 and audit.categoryInfoReads==96 and audit.categoriesEnumerated==96 and audit.entries==1025 and audit.statisticIds==1025 and audit.labelReads==1025 and audit.candidates==1025 and audit.valueReads==1 and audit.mappingProbes==32 and audit.unmappedCandidateChecks==1025 and audit.candidateComparisons<=1100 and audit.workChunks==chunkCount,"audit counters show linear index construction, direct value reads and bounded slot probes")

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
for index=1,100 do local result=HolyStorm.Snapshots.scanner();if type(result)=="table"and result.workflowAction~="GOTO"then failedScan=result;break end end
local failedValid=Module:Validate(failedScan)
assert(failedScan and failedScan.pending and not failedValid and Module.lifetimeStatisticCache==nil,"a failed or incomplete discovery stays retryable and cannot validate or cache partial state")
GetCategoryInfo=savedCategoryInfo
print("Raid Statistics discovery batches, exact mapping cache and work-count bounds passed")
