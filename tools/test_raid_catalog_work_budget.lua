-- Synthetic Encounter Journal history verifies the Raid workflow yields while
-- it maps stable instance/encounter IDs and orders across tiers.
local root=(arg[0]:gsub("tools[/\\]test_raid_catalog_work_budget.lua$",""))
local Module,selectedTier= nil,1
local calls={instances=0,encounters=0,metadata=0,creatures=0,selectInstance=0,selectTier=0,tierCount=0,currentTier=0,tierInfo=0}
local logs={}
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,item in pairs(value)do out[copy(key,seen)]=copy(item,seen)end;return out end
local HolyStorm={Utils={DeepCopy=copy,Now=function()return 42 end},Logger={},Events={},Data={CharacterStore={GetBlock=function()end,GetBlockMetadata=function()end}},PlayerData={RegisterBlock=function()end}}
function HolyStorm.Logger:Write(level,source,category,message,context)logs[#logs+1]={message=message,context=context}end
function HolyStorm:RegisterModule(_,factory)Module={};factory(Module)end
function HolyStorm:ApplyModuleMetadata(module,metadata)module.metadata=metadata end
function HolyStorm:RegisterCapability()end
function HolyStorm.Events:Register()end
function LibStub(name)if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}elseif name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end;error("unexpected library "..tostring(name))end
function UnitGUID()return"Player-Catalog-Budget"end
function EJ_GetNumTiers()calls.tierCount=calls.tierCount+1;return 24 end
function EJ_GetCurrentTier()calls.currentTier=calls.currentTier+1;return 24 end
function EJ_GetTierInfo(tier)calls.tierInfo=calls.tierInfo+1;return"Fixture Tier "..tier end
function EJ_SelectTier(tier)calls.selectTier=calls.selectTier+1;selectedTier=tier end
function EJ_GetInstanceByIndex(index,isRaid)calls.instances=calls.instances+1;if not isRaid or index>3 then return nil end;return selectedTier*100+index,"Fixture Raid "..selectedTier.."-"..index,nil,nil,index end
local selectedInstance
function EJ_SelectInstance(id)calls.selectInstance=calls.selectInstance+1;selectedInstance=id end
function EJ_GetInstanceInfo(instanceId)assert(instanceId>=2401 and instanceId<=2403);calls.metadata=calls.metadata+1;return nil,nil,nil,nil,nil,nil,nil,nil,true end
function EJ_GetEncounterInfoByIndex(index,instanceId)calls.encounters=calls.encounters+1;if index>8 then return nil end;local raidIndex=instanceId%100;return"Fixture Boss "..raidIndex.."-"..index,nil,instanceId*100+index end
function EJ_GetCreatureInfo()calls.creatures=calls.creatures+1;error("unused CreatureInfo traversal")end
function GetNumSavedInstances()return 0 end
function GetDifficultyInfo(id)return({[17]="Raid Finder",[14]="Normal",[15]="Heroic",[16]="Mythic"})[id]end
function GetStatisticsCategoryList()return{}end
function GetCategoryNumAchievements()return 0 end
function GetStatistic()end
function GetAchievementInfo()end

assert(loadfile(root.."LIVE/Holy_Storm_Raids/Raids.lua"))()
local state={chunked=true};local steps=0;local result
repeat
 steps=steps+1;assert(steps<500,"large Encounter Journal discovery completes over bounded workflow steps (tier="..tostring(state.journal and state.journal.tier)..", instance="..tostring(state.journal and state.journal.instance)..", encounter="..tostring(state.journal and state.journal.encounter)..", calls="..tostring(calls.instances).."/"..tostring(calls.encounters)..")")
 local beforeInstances,beforeEncounters,beforeMetadata,beforeSelectInstance,beforeSelectTier,beforeTierCount,beforeCurrentTier,beforeTierInfo=calls.instances,calls.encounters,calls.metadata,calls.selectInstance,calls.selectTier,calls.tierCount,calls.currentTier,calls.tierInfo
 local snapshot,status=Module:Collect(true,state)
 local work=(calls.instances-beforeInstances)+(calls.encounters-beforeEncounters)
 local apiWork=work+(calls.metadata-beforeMetadata)+(calls.selectInstance-beforeSelectInstance)+(calls.selectTier-beforeSelectTier)+(calls.tierCount-beforeTierCount)+(calls.currentTier-beforeCurrentTier)+(calls.tierInfo-beforeTierInfo)
 assert(work<=1,"a single Raid workflow step processes at most eight EJ instances/encounters (observed "..work..")")
 assert(apiWork<=1,"Encounter Journal setup/selection/metadata calls share the same per-step API budget (observed "..apiWork..")")
 if status=="IN_PROGRESS"then result=nil else result=snapshot end
until result~=nil
assert(result.pending and state.catalogData and #state.catalogData.raids==3,"all three current-tier Raid identities are cached in the persisted catalog payload")
assert(#state.catalogData.raids[1].bosses==8 and state.catalogData.raids[1].bosses[8].id==240108,"stable encounter IDs and EJ ordering survive catalog construction")
assert(calls.encounters==3*9 and calls.selectInstance==0 and calls.metadata==3 and calls.creatures==0,"only current-tier bosses are queried; history retains lockout identities")
assert(steps>1,"historic tiers were not processed in one task")
local before=calls.encounters+calls.instances+calls.metadata+calls.selectInstance+calls.selectTier
local cachedState={chunked=true}
for _=1,500 do local _,status=Module:Collect(true,cachedState);if status~="IN_PROGRESS"then break end end
assert(calls.encounters+calls.instances+calls.metadata+calls.selectInstance+calls.selectTier==before,"a second scan reuses the static catalog")
Module:InvalidateRaidCatalogCache("EXPLICIT_TEST")
local invalidatedState={chunked=true}
for _=1,500 do local _,status=Module:Collect(true,invalidatedState);if status~="IN_PROGRESS"then break end end
assert(calls.encounters==3*9*2,"explicit invalidation rebuilds current encounters once")
print("Raid catalog: one API per slice, cached current encounters and historic identities passed")
