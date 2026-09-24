local root=(arg[0]:gsub("tools[/\\]test_raid_snapshot.lua$","")).."LIVE/Holy_Storm/"
local featureRoot=(arg[0]:gsub("tools[/\\]test_raid_snapshot.lua$","")).."LIVE/Holy_Storm_Raids/"
local oldSnapshot
local logs={}
local HolyStorm={Utils={},Logger={}}
function HolyStorm.Logger:Write(level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.Utils.DeepCopy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[HolyStorm.Utils.DeepCopy(key,seen)]=HolyStorm.Utils.DeepCopy(child,seen)end;return out end
function HolyStorm.Utils.Now()return 123456 end
function HolyStorm:RegisterModule(_,factory)local module={};factory(module);self.raidModule=module end
function HolyStorm:ApplyModuleMetadata(module,metadata)module.metadata=metadata end
function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}
end
HolyStorm.Data={CharacterStore={}}
local blockReads=0
function HolyStorm.Data.CharacterStore:GetBlock(guid,blockId)assert(guid=="Player-GUID"and blockId=="raid","Raid snapshot must use the generic raid block API");blockReads=blockReads+1;return oldSnapshot,{version=3}end
function HolyStorm.Data.CharacterStore:GetBlockMetadata(guid,blockId)assert(guid=="Player-GUID"and blockId=="raid","Raid metadata must use the generic block API");return{version=3}end

function UnitGUID()return"Player-GUID"end
local tierCount,currentTier,selectedTier,selectedInstance=1,1,1,nil
function EJ_GetNumTiers()return tierCount end
function EJ_SelectTier(tier)selectedTier=tier end
function EJ_GetCurrentTier()return currentTier end
local raidCatalog={{id=100,name="Raid One",icon=12345}}
local raidCatalogByTier={}
function EJ_GetInstanceByIndex(index,isRaid)local catalog=raidCatalogByTier[selectedTier]or raidCatalog;local raid=isRaid and catalog[index];if raid then return raid.id,raid.name,nil,nil,raid.icon end end
function EJ_SelectInstance(id)selectedInstance=id end
function EJ_GetInstanceInfo()local catalog=raidCatalogByTier[selectedTier]or raidCatalog;for _,raid in ipairs(catalog)do if raid.id==selectedInstance then return nil,nil,nil,nil,nil,nil,nil,nil,raid.shouldDisplayDifficulty~=false end end end
function EJ_GetEncounterInfoByIndex(index)if index==1 then return"Boss A",nil,501 elseif index==2 then return"Boss B",nil,502 end end

local lockoutId=9001
local lockoutName="Raid One"
local instances={
 {difficultyId=17,difficultyName="Raid Finder",kills={true,false}},
 {difficultyId=14,difficultyName="Normal",kills={true,true}},
 {difficultyId=15,difficultyName="Heroic",kills={true,false}},
 {difficultyId=16,difficultyName="Mythic",kills={true,false}},
}
function GetNumSavedInstances()return#instances end
function GetSavedInstanceInfo(index)local x=instances[index];return lockoutName,lockoutId+index,3600,x.difficultyId,true,false,nil,true,20,x.difficultyName,#x.kills end
function GetSavedInstanceEncounterInfo(index,bossIndex)local x=instances[index];return bossIndex==1 and"Boss A"or"Boss B",bossIndex==1 and 501 or 502,x.kills[bossIndex]end

assert(loadfile(featureRoot.."Raids.lua"))()
local module=assert(HolyStorm.raidModule)
local first=module:Collect()
assert(blockReads==1 and HolyStorm.Data.CharacterStore.GetRaidLockouts==nil,"Raid collect uses only the current CharacterStore API surface")
assert(first.snapshotVersion==3 and#first.raids==1 and#first.raids[1].bosses==2,"current raid catalog")
assert(#first.lockouts==4 and first.bestProgress.difficultyId==16,"logical difficulty ordering")
assert(first.lifetime.reliable==false and next(first.lifetime.bosses)==nil,"lockout scans never fabricate Blizzard lifetime kills")

oldSnapshot=first
local repeated=module:Collect()
assert(next(repeated.lifetime.bosses)==nil,"repeated scans do not create a lifetime count")

oldSnapshot=repeated;lockoutId=10001
local nextLockout=module:Collect()
assert(next(nextLockout.lifetime.bosses)==nil,"a new lockout still does not increment a local lifetime count")
assert(module:Validate(nextLockout))

raidCatalog={{id=999,name="Outdoor collection",icon=99999,shouldDisplayDifficulty=false},{id=100,name="Raid One",icon=12345},{id=200,name="Raid Two",icon=23456}};lockoutName="Raid Two";instances={{difficultyId=14,difficultyName="Normal",kills={true,false}}};oldSnapshot=nil
local secondCurrent=module:Collect()
assert(#secondCurrent.raids==2 and secondCurrent.raids[1].id==100 and secondCurrent.raids[2].id==200 and secondCurrent.lockouts[1].isCurrent,"Encounter Journal outdoor collections are excluded by instance metadata without filtering real raids")
assert(secondCurrent.lockouts[1].journalInstanceId==200,"lockout is linked to its encounter-journal raid")

tierCount=2;currentTier=2;selectedTier=2;raidCatalogByTier={[1]={{id=300,name="Firelands",icon=34567}},[2]=raidCatalog};lockoutName="Firelands";instances={{difficultyId=33,difficultyName="Timewalking",kills={true,false}}};oldSnapshot=nil
local timewalking=module:Collect()
assert(#timewalking.raids==2 and timewalking.lockouts[1].journalInstanceId==300,"an older-tier lockout is resolved across all encounter-journal tiers")
assert(timewalking.lockouts[1].difficultyId==33 and not timewalking.lockouts[1].isCurrent,"Timewalking remains a distinct non-current difficulty")

local savedEJ={EJ_GetNumTiers,EJ_SelectTier,EJ_GetInstanceByIndex,EJ_GetCurrentTier,EJ_SelectInstance,EJ_GetInstanceInfo,EJ_GetEncounterInfoByIndex}
local function clearJournal()EJ_GetNumTiers=nil;EJ_SelectTier=nil;EJ_GetInstanceByIndex=nil;EJ_GetCurrentTier=nil;EJ_SelectInstance=nil;EJ_GetInstanceInfo=nil;EJ_GetEncounterInfoByIndex=nil end
local function restoreJournal()EJ_GetNumTiers,EJ_SelectTier,EJ_GetInstanceByIndex,EJ_GetCurrentTier,EJ_SelectInstance,EJ_GetInstanceInfo,EJ_GetEncounterInfoByIndex=table.unpack(savedEJ)end

clearJournal();local loadCalls=0;C_AddOns={LoadAddOn=function(name)assert(name=="Blizzard_EncounterJournal");loadCalls=loadCalls+1;restoreJournal();return true end}
local loaded=module:Collect();assert(loadCalls==1 and module:Validate(loaded),"an unloaded Encounter Journal is loaded through C_AddOns and then rescanned")

clearJournal();C_AddOns.LoadAddOn=function()return false,"temporarily unavailable"end;oldSnapshot=loaded;instances={{difficultyId=14,difficultyName="Normal",kills={true,true,false,false}}}
local ok,pending=pcall(function()return module:Collect()end);assert(ok and pending.pending,"missing Encounter Journal APIs never raise a Lua error")
local valid,reason=module:Validate(pending);assert(not valid and reason:find("tier enumeration",1,true),"an unavailable Encounter Journal enters retry/pending")
assert(oldSnapshot==loaded,"the last valid raid snapshot remains intact while the catalog is pending")
local commits=0;HolyStorm.PlayerData={WriteOwnedBlock=function()commits=commits+1 end};if valid then module:Commit(pending)end;assert(commits==0,"a pending catalog never commits an empty replacement snapshot")

restoreJournal();EJ_GetInstanceByIndex=nil;C_AddOns.LoadAddOn=function()return true end;pending=module:Collect();valid,reason=module:Validate(pending);assert(not valid and reason=="Raid catalog unavailable: missing EJ instance enumeration API","a successful pcall does not hide a missing instance enumeration API")
assert(logs[#logs].context.api=="EJ_GetInstanceByIndex","structured raid logging names the missing instance API")

restoreJournal();EJ_GetEncounterInfoByIndex=nil;pending=module:Collect();valid,reason=module:Validate(pending);assert(not valid and reason=="Raid catalog unavailable: missing EJ encounter enumeration API","a missing encounter enumeration API causes retry instead of a scan")
assert(logs[#logs].context.api=="EJ_GetEncounterInfoByIndex","structured raid logging names the missing encounter API")
restoreJournal();C_AddOns=nil
oldSnapshot={lifetime={bosses={historic={id=501,name="Boss A",raidInstanceId=100,difficulties={MYTHIC={kills=7,source="blizzard-statistic",statisticId=42}}}},seen={historic=true}},lockouts={{name="Raid One",difficultyId=16,killed=2,total=2,bosses={}}}}
instances={};tierCount=1;currentTier=1;selectedTier=1;raidCatalogByTier={};raidCatalog={{id=100,name="Raid One",icon=12345}}
local expired=module:Collect();assert(#expired.lockouts==0,"a fresh raid snapshot omits an expired lockout that Blizzard no longer returns")
assert(expired.lifetime.bosses.historic.difficulties.MYTHIC.kills==7 and expired.lifetime.seen.historic,"historical raid best data survives while weekly lockouts are rebuilt")

local statistics={
 {id=7001,name="Boss A kills (Normal Raid One)",assetId=9501,value="27"},
 {id=7002,name="Boss A kills (Heroic Raid One)",assetId=9501,value="1"},
 {id=7003,name="Boss A kills (Mythic Raid One)",assetId=9501,value="--"},
 {id=7004,name="Boss B kills (Normal Raid One)",assetId=9502,value="4"},
 {id=7005,name="Boss B kills (Normal Raid One)",assetId=9502,value="5"},
 {id=7006,name="Boss A kills (Raid Finder Other Raid)",assetId=9501,value="99"},
}
function EJ_GetCreatureInfo(index,encounterId)if index~=1 then return nil end;if encounterId==501 then return 9501 elseif encounterId==502 then return 9502 end end
function GetStatisticsCategoryList()return{900}end
function GetCategoryNumAchievements(categoryId)assert(categoryId==900);return#statistics end
function GetStatistic(categoryOrId,index)
 if index then local statistic=statistics[index];return statistic.value,false,statistic.id end
 for _,statistic in ipairs(statistics)do if statistic.id==categoryOrId then return statistic.value end end
end
function GetAchievementInfo(statisticId)for _,statistic in ipairs(statistics)do if statistic.id==statisticId then return statistic.id,statistic.name end end end
function GetAchievementNumCriteria(statisticId)return GetAchievementInfo(statisticId)and 1 or 0 end
function GetAchievementCriteriaInfo(statisticId)for _,statistic in ipairs(statistics)do if statistic.id==statisticId then return statistic.name,0,false,0,0,nil,0,statistic.assetId end end end
function GetDifficultyInfo(difficultyId)return({[17]="Raid Finder",[14]="Normal",[15]="Heroic",[16]="Mythic"})[difficultyId]end

oldSnapshot=nil;instances={};module.lifetimeStatisticCandidates=nil;logs={}
local statistical=module:Collect();local bossA=assert(statistical.lifetime.bosses[501])
assert(bossA.difficulties.NORMAL.kills==27 and bossA.difficulties.NORMAL.statisticId==7001 and bossA.difficulties.NORMAL.source=="blizzard-statistic","the exact Blizzard statistic ID and its real multi-kill value are stored")
assert(bossA.difficulties.HEROIC.kills==1 and bossA.difficulties.MYTHIC==nil and bossA.difficulties.LFR==nil,"unknown or unavailable statistics remain unknown")
assert(statistical.lifetime.bosses[502]==nil,"ambiguous statistics are rejected instead of guessed")
local accepted,ambiguous=false,false
for _,entry in ipairs(logs)do if entry.message=="RAID_LIFETIME_STAT"then local context=entry.context or{};assert(context.raidInstanceId and context.bossId and context.difficulty and context.statisticId~=nil and context.value~=nil and context.accepted~=nil and context.reason,"lifetime debug entries expose the complete mapping decision");accepted=accepted or(context.statisticId==7001 and context.accepted==true and context.value=="27"and context.reason=="ACCEPTED");ambiguous=ambiguous or(context.bossId==502 and context.difficulty=="NORMAL"and context.accepted==false and context.reason=="AMBIGUOUS_STATISTIC")end end
assert(accepted and ambiguous,"RAID_LIFETIME_STAT logs both accepted and rejected mappings")
print("Raid catalog availability, retry preservation, difficulty ordering and lifetime deduplication tests passed")
