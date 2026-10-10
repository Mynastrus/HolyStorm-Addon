local function deepcopy(value)
    if type(value)~="table"then return value end
    local result={}
    for key,item in pairs(value)do result[deepcopy(key)]=deepcopy(item)end
    return result
end

local function equal(left,right)
    if type(left)~=type(right)then return false end
    if type(left)~="table"then return left==right end
    for key,value in pairs(left)do if not equal(value,right[key])then return false end end
    for key in pairs(right)do if left[key]==nil then return false end end
    return true
end

local schema,data,commitCount,getCount
local emitted,upserted={},nil
local currentDemands={quests={[42]=true},achievements={[84]=true}}
local module
local locale=setmetatable({},{__index=function(_,key)return key end})
local HolyStorm={
    Utils={DeepCopy=deepcopy,Now=function()return 123 end},
    DataManager={
        RegisterSchema=function(_,definition)schema=definition end,
        Get=function(_,id)assert(id==schema.id);getCount=getCount+1;return deepcopy(data or schema.default())end,
        Commit=function(_,id,_,value)
            assert(id==schema.id)
            commitCount=commitCount+1
            local changed=not equal(data,value)
            if changed then data=deepcopy(value)end
            return{ok=true,changed=changed}
        end,
    },
    FilterManager={GetRules=function()return{}end,GetFilters=function()return{}end},
    Policy={GetGroups=function()return{}end},
    Rules={
        CollectDemands=function(_,_,seed)
            seed.quests,seed.achievements=deepcopy(currentDemands.quests),deepcopy(currentDemands.achievements)
            return seed
        end,
        RebuildDemands=function()end,
    },
    Events={
        Register=function()return true end,
        UnregisterOwner=function()end,
        Emit=function(_,name,value)emitted[#emitted+1]={name=name,value=value}end,
    },
    Tasks={RegisterTaskType=function()return true end,Queue=function()return true end,Cancel=function()return true end},
    Data={CharacterStore={Upsert=function(_,guid,value,source)upserted={guid=guid,value=deepcopy(value),source=source};return true end}},
    RegisterModule=function(_,metadata,initialize)
        module={metadata=metadata}
        initialize(module)
    end,
}

LibStub=function(name)
    if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
    if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
end
UnitGUID=function()return"local-guid"end
C_QuestLog={IsQuestFlaggedCompleted=function(id)return id==42 end}
GetAchievementInfo=function(id)return nil,nil,nil,id==84 end

schema={id="character-rule-demands",storage={path={"filters","demands"}},default=function()return{}end};data,commitCount,getCount=nil,0,0
dofile("LIVE/Holy_Storm_Characters/RuleDataProvider.lua")
assert(schema and schema.storage.path[1]=="filters"and schema.storage.path[2]=="demands","rule-demand schema must be available through DataManager")
assert(module and module.metadata.version=="1.0.1","module registration should expose the bumped feature version")
module:OnInitialize()
module:OnEnable()
module:RebuildDemands()
assert(commitCount==1 and #emitted==1 and emitted[1].name=="HS_RULE_DEMANDS_CHANGED","first demand rebuild should persist and emit once")
module:RebuildDemands()
assert(commitCount==2 and #emitted==1,"unchanged demand rebuild must not emit a duplicate event")
currentDemands.achievements[85]=true
module:RebuildDemands()
assert(commitCount==3 and #emitted==2,"changed demand rebuild should emit one update")
assert(data.quests[42]==true and data.achievements[84]==true and data.achievements[85]==true,"stored demands: q42="..tostring(data.quests and data.quests[42])..", a84="..tostring(data.achievements and data.achievements[84])..", a85="..tostring(data.achievements and data.achievements[85]))
assert(module:Capture("local-guid"),"capture should succeed")
assert(getCount>=4 and upserted and upserted.source=="blizzard","capture should read through DataManager then commit via CharacterStore")
assert(upserted.value.demands.quests[42]==true and upserted.value.demands.achievements[84]==true and upserted.value.demands.achievements[85]==false,"capture values: q42="..tostring(upserted.value.demands.quests[42])..", a84="..tostring(upserted.value.demands.achievements[84])..", a85="..tostring(upserted.value.demands.achievements[85]))
print("Character rule data persistence and event regressions passed")
