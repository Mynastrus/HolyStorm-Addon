local root=(arg[0]:gsub("tools[/\\]test_raid_snapshot.lua$","")).."LIVE/Holy_Storm/"
local featureRoot=(arg[0]:gsub("tools[/\\]test_raid_snapshot.lua$","")).."LIVE/Holy_Storm_Raids/"
local oldSnapshot
local HolyStorm={Utils={}}
function HolyStorm.Utils.DeepCopy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[HolyStorm.Utils.DeepCopy(key,seen)]=HolyStorm.Utils.DeepCopy(child,seen)end;return out end
function HolyStorm.Utils.Now()return 123456 end
function HolyStorm:RegisterModule(_,factory)local module={};factory(module);self.raidModule=module end
function HolyStorm:ApplyModuleMetadata(module,metadata)module.metadata=metadata end
function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}
end
HolyStorm.Data={CharacterStore={}}
function HolyStorm.Data.CharacterStore:GetRaidLockouts()return oldSnapshot end
function HolyStorm.Data.CharacterStore:GetBlockMetadata()return{version=3}end

function UnitGUID()return"Player-GUID"end
local tierCount,currentTier,selectedTier=1,1,1
function EJ_GetNumTiers()return tierCount end
function EJ_SelectTier(tier)selectedTier=tier end
function EJ_GetCurrentTier()return currentTier end
local raidCatalog={{id=100,name="Raid One",icon=12345}}
local raidCatalogByTier={}
function EJ_GetInstanceByIndex(index,isRaid)local catalog=raidCatalogByTier[selectedTier]or raidCatalog;local raid=isRaid and catalog[index];if raid then return raid.id,raid.name,nil,nil,raid.icon end end
function EJ_SelectInstance()end
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

raidCatalog={{id=100,name="Raid One",icon=12345},{id=200,name="Raid Two",icon=23456}};lockoutName="Raid Two";instances={{difficultyId=14,difficultyName="Normal",kills={true,false}}};oldSnapshot=nil
local secondCurrent=module:Collect()
assert(#secondCurrent.raids==2 and secondCurrent.lockouts[1].isCurrent,"every raid in the latest expansion tier is current")
assert(secondCurrent.lockouts[1].journalInstanceId==200,"lockout is linked to its encounter-journal raid")

tierCount=2;currentTier=2;selectedTier=2;raidCatalogByTier={[1]={{id=300,name="Firelands",icon=34567}},[2]=raidCatalog};lockoutName="Firelands";instances={{difficultyId=33,difficultyName="Timewalking",kills={true,false}}};oldSnapshot=nil
local timewalking=module:Collect()
assert(#timewalking.raids==2 and timewalking.lockouts[1].journalInstanceId==300,"an older-tier lockout is resolved across all encounter-journal tiers")
assert(timewalking.lockouts[1].difficultyId==33 and not timewalking.lockouts[1].isCurrent,"Timewalking remains a distinct non-current difficulty")

local savedEJ={EJ_GetNumTiers,EJ_SelectTier,EJ_GetInstanceByIndex,EJ_GetCurrentTier,EJ_SelectInstance,EJ_GetEncounterInfoByIndex}
EJ_GetNumTiers=nil;EJ_SelectTier=nil;EJ_GetInstanceByIndex=nil;EJ_GetCurrentTier=nil;EJ_SelectInstance=nil;EJ_GetEncounterInfoByIndex=nil
oldSnapshot=nil;instances={{difficultyId=14,difficultyName="Normal",kills={true,true,false,false}}}
local lockoutOnly=module:Collect()
assert(#lockoutOnly.raids==0 and#lockoutOnly.lockouts==1,"active lockout survives unavailable journal catalog")
assert(lockoutOnly.lockouts[1].killed==2 and module:Validate(lockoutOnly),"active raid ID must be cacheable without journal data")
instances={};local emptyPending=module:Collect();local valid,reason=module:Validate(emptyPending);assert(not valid and reason=="raid catalog pending","empty scans retry while the catalog is loading")
EJ_GetNumTiers,EJ_SelectTier,EJ_GetInstanceByIndex,EJ_GetCurrentTier,EJ_SelectInstance,EJ_GetEncounterInfoByIndex=table.unpack(savedEJ)
print("Raid catalog, lockout fallback, difficulty ordering and lifetime deduplication tests passed")
