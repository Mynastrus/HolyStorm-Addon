-- The names and kill counts mirror the Retail observation. Numeric IDs are
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
local raidName="Der Giftige Abgrund"
function EJ_GetNumTiers()return 1 end
function EJ_GetCurrentTier()return 1 end
function EJ_GetTierInfo()return"Fixture Expansion"end
function EJ_SelectTier(tier)selectedTier=tier end
function EJ_GetInstanceByIndex(index,isRaid)if selectedTier==1 and index==1 and isRaid then return 100,raidName end end
function EJ_SelectInstance()end
function EJ_GetInstanceInfo()return nil,nil,nil,nil,nil,nil,nil,nil,true end
local bosses={
 {id=501,name="Nek'zali die Seelenwinderin"},{id=502,name="Eingeschlossene Wächter"},
 {id=503,name="Die verirrten Entdecker"},{id=504,name="Vashnik der Bösartige"},
 {id=505,name="Sszorak"},{id=506,name="Die Zwillingsfänge"},
 {id=507,name="Der Gewundene Altar"},{id=508,name="Ula'tek"},
}
function EJ_GetEncounterInfoByIndex(index)local boss=bosses[index];if boss then return boss.name,nil,boss.id end end
function GetNumSavedInstances()return 0 end
function GetDifficultyInfo(id)return({[17]="Raid Finder",[14]="Normal",[15]="Heroic",[16]="Mythic"})[id]end
local statistics={
 {id=7001,name="Nek'zali die Seelenwinderin (Raid Finder: Der Giftige Abgrund)",value="1"},
 {id=7002,name="Nek'zali die Seelenwinderin (Normal: Der Giftige Abgrund)",value="6"},
 {id=7003,name="Eingeschlossene Wächter (Normal: Der Giftige Abgrund)",value="6"},
 {id=7004,name="Die verirrten Entdecker (Normal: Der Giftige Abgrund)",value="6"},
 {id=7005,name="Vashnik der Bösartige (Normal: Der Giftige Abgrund)",value="7"},
 {id=7006,name="Sszorak (Normal: Der Giftige Abgrund)",value="6"},
 {id=7007,name="Die Zwillingsfänge (Raid Finder: Der Giftige Abgrund)",value="1"},
 {id=7008,name="Die Zwillingsfänge (Normal: Der Giftige Abgrund)",value="4"},
 {id=7009,name="Vashnik der Bösartige (Heroic: Der Giftige Abgrund)",value="--"},
 {id=7010,name="Nek'zali die Seelenwinderin (Heroic: Der Giftige Abgrund)",value=nil},
 {id=7011,name="Unknown boss (Normal: Der Giftige Abgrund)",value="5"},
 {id=7012,name="Vashnik der Bösartige (Normal Der Giftige Abgrund)",value="9"},
 {id=7013,name="Unrelated (Normal: Other Raid)",value="99"},
 {id=7014,name="Vashnik der Bösartige (Challenge: Der Giftige Abgrund)",value="88"},
 {id=7015,name="Vashnik der Bösartige (Normal: Der Giftige Abgrund Extended)",value="99"},
}
local categoryCalls,categoriesReady=0,false
function GetStatisticsCategoryList()categoryCalls=categoryCalls+1;return categoriesReady and{900}or{}end
function GetCategoryInfo(id)assert(id==900);return"Der Giftige Abgrund",-1 end
function GetCategoryNumAchievements(id)assert(id==900);return#statistics end
function GetStatistic(id,index)
 if index then local item=statistics[index];return item.value,false,item.id end
 for _,item in ipairs(statistics)do if item.id==id then return item.value end end
end
function GetAchievementInfo(id)for _,item in ipairs(statistics)do if item.id==id then return item.id,item.name end end end
GetAchievementNumCriteria=nil;GetAchievementCriteriaInfo=nil

local unavailable=module:Collect(true)
assert(next(unavailable.lifetime.bosses)==nil,"unavailable category data must remain unknown")
categoriesReady=true
local snapshot=module:Collect(true)
assert(categoryCalls==2,"manual scan must rediscover categories after earlier data was unavailable")
assert(module:Validate(snapshot),"producer snapshot must pass Raid v3 validation")
local missingLifetime=copy(snapshot);missingLifetime.lifetime=nil;assert(not module:Validate(missingLifetime),"Raid v3 validation must reject an entirely missing lifetime structure")
assert(#snapshot.raids[1].bosses==8,"the Retail raid fixture must contain all eight catalog bosses")
for id=501,506 do assert(snapshot.lifetime.bosses[id].difficulties.NORMAL.kills==({6,6,6,7,6,4})[id-500],"each observed Normal statistic must become a numeric lifetime count")end
assert(snapshot.lifetime.bosses[501].difficulties.LFR.kills==1 and snapshot.lifetime.bosses[506].difficulties.LFR.kills==1 and snapshot.lifetime.bosses[506].difficulties.NORMAL.kills==4,"multiple difficulties remain separate")
assert(snapshot.lifetime.bosses[504].difficulties.HEROIC==nil and snapshot.lifetime.bosses[501].difficulties.HEROIC==nil,"-- and nil remain unknown")
assert(snapshot.lifetime.bosses[507]==nil and snapshot.lifetime.bosses[508]==nil,"unobserved boss counts are not invented")
local summary
for _,entry in ipairs(logs)do if entry.message=="RAID_LIFETIME_SCAN_SUMMARY"then summary=entry.context end end
assert(summary and summary.categories==1 and summary.relevantCategories==1 and summary.entries==15 and summary.candidates==14 and summary.discoveryRejected==1 and summary.unmapped==3 and summary.reads==8 and summary.positive==8 and summary.zero==0 and summary.unavailable==2 and summary.mappedBosses==6,"manual diagnostic counters must describe discovery and mapping")
local sawUnmapped,sawRejected,sawDifficulty,sawRaid=false,false,false,false
for _,entry in ipairs(logs)do
 if entry.message=="RAID_LIFETIME_UNMAPPED"and entry.context.statisticId==7011 and entry.context.reason=="BOSS_NAME_NOT_FOUND"then sawUnmapped=true end
 if entry.message=="RAID_LIFETIME_CANDIDATE_REJECTED"and entry.context.statisticId==7012 and entry.context.reason=="UNKNOWN_STATISTIC_FORMAT"then sawRejected=true end
 if entry.message=="RAID_LIFETIME_UNMAPPED"and entry.context.statisticId==7014 and entry.context.reason=="DIFFICULTY_NAME_NOT_FOUND"then sawDifficulty=true end
 if entry.message=="RAID_LIFETIME_UNMAPPED"and entry.context.statisticId==7015 and entry.context.reason=="RAID_NAME_NOT_FOUND"then sawRaid=true end
end
assert(sawUnmapped and sawRejected and sawDifficulty and sawRaid,"manual logs must explain unused and rejected raid-like statistics")
assert(module:Commit(snapshot),"validated snapshot must commit through PlayerData")
local canonical=assert(HS_Player_DB.characters["Player-Fixture"].raidLockouts)
assert(canonical.lifetime.bosses[506].difficulties.NORMAL.statisticId==7008,"canonical HS_Player_DB block must retain statistic provenance")
local stored,meta=HolyStorm.Data.CharacterStore:GetBlock("Player-Fixture","raid")
assert(stored.lifetime.bosses[504].difficulties.NORMAL.kills==7 and meta.version==1,"CharacterStore must return lifetime and owner revision")
local consumed=HolyStorm.CharacterUI:GetSnapshot("Player-Fixture","raid")
local best=HolyStorm.CharacterUI:GetBestProgress(consumed,consumed.raids[1])
assert(best and best.difficulty=="NORMAL"and best.killed==6 and best.total==8,"stored Raid data must reach the real Best calculation")
local rows=HolyStorm.CharacterUI:BuildRaidBestRows(consumed)
local byName={};for _,row in ipairs(rows)do byName[row.bossName]=row end
assert(#rows==6 and byName["Vashnik der Bösartige"].kills==7 and byName.Sszorak.kills==6 and byName["Die Zwillingsfänge"].kills==4 and byName["Die Zwillingsfänge"].difficulty=="NORMAL","Best tooltip rows must use stored normalized kills")
local view={summary={SetText=function()end},table={SetEmptyText=function()end,SetData=function(self,items)self.rows=items end}}
tabs.raid.refresh(view,{characterUUID="Player-Fixture"})
assert(view.table.rows[1].best:find("N 6/8",1,true),"StoredFeatureTabs must render the persisted Best")
local status=module:GetSnapshotStatus()
assert(#status==2 and status[1]:find("lifetime bosses 6 (6 positive)",1,true)and status[2]:find("best Normal 6/8",1,true),"status command must inspect the stored snapshot and per-raid Best")
module:Collect(true);assert(categoryCalls==2,"manual scans refresh mapped values without rediscovering a valid Statistics index")
module:Collect();assert(categoryCalls==2,"automatic scans may reuse a complete same-catalog statistic index")
statistics[9].value="0";statistics[10].value=0
local withZero=module:CaptureLifetime(snapshot.raids,nil,true,"Fixture Expansion")
assert(withZero.bosses[504].difficulties.HEROIC.kills==0 and withZero.bosses[501].difficulties.HEROIC.kills==0,"string and numeric zero are known values")
statistics[9].value="malformed 9";statistics[10].value=nil
local malformed=module:CaptureLifetime(snapshot.raids,nil,true,"Fixture Expansion")
assert(malformed.bosses[504].difficulties.HEROIC==nil and malformed.bosses[501].difficulties.HEROIC==nil,"malformed and nil values remain unknown")
statistics[9].value=2
local numeric=module:CaptureLifetime(snapshot.raids,nil,true,"Fixture Expansion")
assert(numeric.bosses[504].difficulties.HEROIC.kills==2,"positive numeric API values remain numeric")
statistics[9].value="--"

local englishDifficulty=GetDifficultyInfo
GetDifficultyInfo=function(id)return({[17]="Schlachtzugsbrowser",[14]="Normal",[15]="Heroisch",[16]="Mythisch"})[id]end
for _,stat in ipairs(statistics)do stat.name=stat.name:gsub("Raid Finder:","Schlachtzugsbrowser:"):gsub("Heroic:","Heroisch:")end
local german=module:Collect(true)
local germanFresh=module:CaptureLifetime(german.raids,nil,true,"Fixture Expansion")
assert(germanFresh.bosses[501].difficulties.LFR.statisticId==7001 and germanFresh.bosses[506].difficulties.NORMAL.statisticId==7008,"deDE Blizzard difficulty labels map without English literals")

GetDifficultyInfo=englishDifficulty;raidName="Fixture Raid"
for index,boss in ipairs(bosses)do boss.name="Fixture Boss "..index end
statistics={}
local englishValues={{1,"Raid Finder",1},{1,"Normal",6},{2,"Normal",6},{3,"Normal",6},{4,"Normal",7},{5,"Normal",6},{6,"Raid Finder",1},{6,"Normal",4}}
for index,row in ipairs(englishValues)do statistics[index]={id=8000+index,name=bosses[row[1]].name.." ("..row[2]..": "..raidName..")",value=tostring(row[3])}end
local english=module:Collect(true)
local englishFresh=module:CaptureLifetime(english.raids,nil,true,"Fixture Expansion")
local freshSnapshot=copy(english);freshSnapshot.lifetime=englishFresh
assert(HolyStorm.CharacterUI:GetBestProgress(freshSnapshot,english.raids[1]).killed==6 and englishFresh.bosses[506].difficulties.NORMAL.statisticId==8008,"enUS fixture resolves current-client names to statistic IDs")
print("Raid Blizzard API to producer, v3 validation, HS_Player_DB, CharacterStore, StoredFeatureTabs and Best pipeline passed")
