-- The names and 7/6/1/4 counts mirror the Retail observation. Numeric IDs are
-- isolated mock identities and make no claim about Blizzard's actual IDs.
local root=(arg[0]:gsub("tools[/\\]test_raid_lifetime_pipeline.lua$","")).."LIVE/"
local function copy(value,seen)
 if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end
 local result={};seen[value]=result;for key,item in pairs(value)do result[copy(key,seen)]=copy(item,seen)end;return result
end
local logs={};local module;local tabs={}
local locale=setmetatable({
 RAID_STATUS_NO_SNAPSHOT="Raid snapshot: absent.",RAID_STATUS_VALID="valid",RAID_STATUS_INVALID="invalid",
 RAID_STATUS_SUMMARY="Raid snapshot v%s, block revision %s (%s): catalog %d, weekly %d, lifetime bosses %d (%d positive), updated %s, validation %s.",
 RAID_STATUS_RAID="%s: catalog %d, lifetime mapped %d, best %s.",DIFFICULTY_NORMAL="Normal",
},{__index=function(_,key)return key end})
local HolyStorm={Utils={DeepCopy=copy,Now=function()return 123456 end},db={global={localPlayerId="fixture-owner",data={}}},Data={},Events={},Logger={},tabs=tabs}
function HolyStorm.Logger:Write(level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.Events:Emit()end
function HolyStorm:RegisterModule(_,factory)module={};factory(module)end
function HolyStorm:ApplyModuleMetadata(target,metadata)target.metadata=metadata end
function HolyStorm:RegisterCharacterTab(_,definition)tabs[definition.id]=definition end
function HolyStorm:RegisterCharacterSummarySection()end
function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
 error("unexpected library: "..tostring(name))
end
function UnitGUID(unit)assert(unit=="player");return"Player-Fixture"end
HS_Player_DB={}
assert(loadfile(root.."Holy_Storm/Core/Serialization/Serializer.lua"))()
assert(loadfile(root.."Holy_Storm/Persistence/PlayerDataStore.lua"))()
assert(HolyStorm.PlayerData:Initialize())
assert(loadfile(root.."Holy_Storm/Persistence/CharacterStore.lua"))()
assert(loadfile(root.."Holy_Storm_Characters/UI/CharacterUI.lua"))()
assert(loadfile(root.."Holy_Storm_Characters/UI/StoredFeatureTabs.lua"))()
assert(loadfile(root.."Holy_Storm_Raids/Raids.lua"))()
assert(module and tabs.raid,"Raid producer and stored UI must register")
assert(module:GetSnapshotStatus()[1]=="Raid snapshot: absent.","status command must identify a missing Raid block")

local selectedTier=1
function EJ_GetNumTiers()return 1 end
function EJ_GetCurrentTier()return 1 end
function EJ_GetTierInfo()return"Fixture Expansion"end
function EJ_SelectTier(tier)selectedTier=tier end
function EJ_GetInstanceByIndex(index,isRaid)if selectedTier==1 and index==1 and isRaid then return 100,"Der Giftige Abgrund"end end
function EJ_SelectInstance()end
function EJ_GetInstanceInfo()return nil,nil,nil,nil,nil,nil,nil,nil,true end
local bosses={{id=501,name="Vashnik",creature=9501},{id=502,name="Sszorak",creature=9502},{id=503,name="Die Zwillingsfänge",creature=9503}}
function EJ_GetEncounterInfoByIndex(index)local boss=bosses[index];if boss then return boss.name,nil,boss.id end end
function EJ_GetCreatureInfo(index,id)if index~=1 then return nil end;for _,boss in ipairs(bosses)do if boss.id==id then return boss.creature end end end
function GetNumSavedInstances()return 0 end
function GetDifficultyInfo(id)return({[17]="Raid Finder",[14]="Normal",[15]="Heroic",[16]="Mythic"})[id]end
local statistics={
 {id=7001,name="Vashnik kills (Normal Der Giftige Abgrund)",asset=9501,value="7"},
 {id=7002,name="Sszorak kills (Normal Der Giftige Abgrund)",asset=9502,value="6"},
 {id=7003,name="Die Zwillingsfänge kills (Raid Finder Der Giftige Abgrund)",asset=9503,value="1"},
 {id=7004,name="Die Zwillingsfänge kills (Normal Der Giftige Abgrund)",asset=9503,value="4"},
 {id=7005,name="Vashnik kills (Heroic Der Giftige Abgrund)",asset=9501,value="0"},
 {id=7006,name="Sszorak kills (Heroic Der Giftige Abgrund)",asset=9502,value="--"},
 {id=7007,name="Vashnik kills (Normal Der Giftige Abgrund)",asset=9999,value="5"},
 {id=7008,name="Sszorak kills (Mythic Der Giftige Abgrund)",asset=9502,value="2",criteriaCount=2},
}
local categoryCalls,categoriesReady=0,false
function GetStatisticsCategoryList()categoryCalls=categoryCalls+1;return categoriesReady and{900}or{}end
function GetCategoryInfo(id)assert(id==900);return"Fixture Expansion",-1 end
function GetCategoryNumAchievements(id)assert(id==900);return#statistics end
function GetStatistic(id,index)
 if index then local item=statistics[index];return item.value,false,item.id end
 for _,item in ipairs(statistics)do if item.id==id then return item.value end end
end
function GetAchievementInfo(id)for _,item in ipairs(statistics)do if item.id==id then return item.id,item.name end end end
function GetAchievementNumCriteria(id)for _,item in ipairs(statistics)do if item.id==id then return item.criteriaCount or 1 end end;return 0 end
function GetAchievementCriteriaInfo(id)for _,item in ipairs(statistics)do if item.id==id then return item.name,0,false,0,0,nil,0,item.asset end end end

local unavailable=module:Collect(true)
assert(next(unavailable.lifetime.bosses)==nil,"unavailable category data must remain unknown")
categoriesReady=true
local snapshot=module:Collect(true)
assert(categoryCalls==2,"manual scan must rediscover categories after earlier data was unavailable")
assert(module:Validate(snapshot),"producer snapshot must pass Raid v3 validation")
local missingLifetime=copy(snapshot);missingLifetime.lifetime=nil;assert(not module:Validate(missingLifetime),"Raid v3 validation must reject an entirely missing lifetime structure")
assert(snapshot.lifetime.bosses[501].difficulties.NORMAL.kills==7 and snapshot.lifetime.bosses[502].difficulties.NORMAL.kills==6,"statistic strings must become numeric lifetime kills")
assert(snapshot.lifetime.bosses[503].difficulties.LFR.kills==1 and snapshot.lifetime.bosses[503].difficulties.NORMAL.kills==4,"LFR and Normal must remain separate")
assert(snapshot.lifetime.bosses[501].difficulties.HEROIC.kills==0,"confirmed zero must survive")
assert(snapshot.lifetime.bosses[502].difficulties.HEROIC==nil,"unavailable -- must remain unknown")
local summary
for _,entry in ipairs(logs)do if entry.message=="RAID_LIFETIME_SCAN_SUMMARY"then summary=entry.context end end
assert(summary and summary.categories==1 and summary.relevantCategories==1 and summary.entries==8 and summary.candidates==7 and summary.discoveryRejected==1 and summary.unmapped==1 and summary.reads==5 and summary.positive==4 and summary.zero==1 and summary.unavailable==1 and summary.mappedBosses==3,"manual diagnostic counters must describe discovery and mapping")
local sawUnmapped,sawRejected=false,false
for _,entry in ipairs(logs)do
 if entry.message=="RAID_LIFETIME_UNMAPPED"and entry.context.statisticId==7007 and entry.context.reason=="CREATURE_ASSET_NOT_FOUND"then sawUnmapped=true end
 if entry.message=="RAID_LIFETIME_CANDIDATE_REJECTED"and entry.context.statisticId==7008 and entry.context.reason=="CRITERIA_COUNT_2"then sawRejected=true end
end
assert(sawUnmapped and sawRejected,"manual logs must explain unused and rejected raid-like statistics")
assert(module:Commit(snapshot),"validated snapshot must commit through PlayerData")
local canonical=assert(HS_Player_DB.characters["Player-Fixture"].raidLockouts)
assert(canonical.lifetime.bosses[503].difficulties.NORMAL.statisticId==7004,"canonical HS_Player_DB block must retain statistic provenance")
local stored,meta=HolyStorm.Data.CharacterStore:GetBlock("Player-Fixture","raid")
assert(stored.lifetime.bosses[501].difficulties.NORMAL.kills==7 and meta.version==1,"CharacterStore must return lifetime and owner revision")
local consumed=HolyStorm.CharacterUI:GetSnapshot("Player-Fixture","raid")
local best=HolyStorm.CharacterUI:GetBestProgress(consumed,consumed.raids[1])
assert(best and best.difficulty=="NORMAL"and best.killed==3 and best.total==3,"stored Raid data must reach the real Best calculation")
local rows=HolyStorm.CharacterUI:BuildRaidBestRows(consumed)
local byName={};for _,row in ipairs(rows)do byName[row.bossName]=row end
assert(byName.Vashnik.kills==7 and byName.Sszorak.kills==6 and byName["Die Zwillingsfänge"].kills==4 and byName["Die Zwillingsfänge"].difficulty=="NORMAL","Best tooltip rows must use stored normalized kills")
local view={summary={SetText=function()end},table={SetEmptyText=function()end,SetData=function(self,items)self.rows=items end}}
tabs.raid.refresh(view,{characterUUID="Player-Fixture"})
assert(view.table.rows[1].best:find("N 3/3",1,true),"StoredFeatureTabs must render the persisted Best")
local status=module:GetSnapshotStatus()
assert(#status==2 and status[1]:find("lifetime bosses 3 (3 positive)",1,true)and status[2]:find("best Normal 3/3",1,true),"status command must inspect the stored snapshot and per-raid Best")
module:Collect(true);assert(categoryCalls==3,"subsequent forced scans must rediscover Blizzard statistics")
module:Collect();assert(categoryCalls==3,"automatic scans may reuse a complete same-catalog statistic index")
print("Raid Blizzard API to producer, v3 validation, HS_Player_DB, CharacterStore, StoredFeatureTabs and Best pipeline passed")
