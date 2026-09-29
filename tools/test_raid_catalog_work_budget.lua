-- Synthetic Encounter Journal history verifies the Raid workflow yields while
-- it maps stable instance/encounter IDs and orders across tiers.
local root=(arg[0]:gsub("tools[/\\]test_raid_catalog_work_budget.lua$",""))
local Module,selectedTier= nil,1
local calls={instances=0,encounters=0,metadata=0,creatures=0}
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
function EJ_GetNumTiers()return 24 end
function EJ_GetCurrentTier()return 24 end
function EJ_GetTierInfo(tier)return"Fixture Tier "..tier end
function EJ_SelectTier(tier)selectedTier=tier end
function EJ_GetInstanceByIndex(index,isRaid)calls.instances=calls.instances+1;if not isRaid or index>3 then return nil end;return selectedTier*100+index,"Fixture Raid "..selectedTier.."-"..index,nil,nil,index end
local selectedInstance
function EJ_SelectInstance(id)selectedInstance=id end
function EJ_GetInstanceInfo()calls.metadata=calls.metadata+1;return nil,nil,nil,nil,nil,nil,nil,nil,true end
function EJ_GetEncounterInfoByIndex(index,instanceId)calls.encounters=calls.encounters+1;if instanceId~=selectedInstance or index>8 then return nil end;local raidIndex=instanceId%100;return"Fixture Boss "..raidIndex.."-"..index,nil,instanceId*100+index end
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
 steps=steps+1;assert(steps<100,"large Encounter Journal discovery completes over bounded workflow steps")
 local beforeInstances,beforeEncounters=calls.instances,calls.encounters
 local snapshot,status=Module:Collect(true,state)
 local work=(calls.instances-beforeInstances)+(calls.encounters-beforeEncounters)
 assert(work<=32,"a single Raid workflow step enumerates at most 32 EJ instances/encounters (observed "..work..")")
 if status=="IN_PROGRESS"then result=nil else result=snapshot end
until result~=nil
assert(result.pending and state.catalogData and #state.catalogData.raids==3,"all three current-tier Raid identities are cached in the persisted catalog payload")
assert(#state.catalogData.raids[1].bosses==8 and state.catalogData.raids[1].bosses[8].id==240108,"stable encounter IDs and EJ ordering survive catalog construction")
assert(calls.encounters==24*3*9 and calls.creatures==0,"the full synthetic EJ history was traversed without unnecessary creature enumeration")
assert(steps>1,"historic tiers were not processed in one task")
print("Raid Encounter Journal traversal is chunked and avoids unused CreatureInfo scans")
