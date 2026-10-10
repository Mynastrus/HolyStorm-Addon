local addonVersion="1.0.1"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Twinks")
local demandsSchema="character-rule-demands"
local function collect(namespace)
    return function(node,demands)
        local id=tonumber(node.argument or node.value)
        if not id then return end
        demands[namespace]=demands[namespace]or{}
        demands[namespace][id]=true
    end
end

local metadata={
    id="CharacterRuleData",name="CharacterRuleData",internalName="characterRuleData",displayName=L["RULE_DATA_PROVIDER"],description=L["RULE_DATA_PROVIDER_DESC"],version=addonVersion,moduleType="feature",category="feature",dependencies={"core"},data={block="demands"},enabledByDefault=true,
    ruleFields={
        {id="quest.completed",aliases={"questCompleted"},type="boolean",name=L["RULE_FIELD_QUEST_COMPLETED"],nameKey="RULE_FIELD_QUEST_COMPLETED",description=L["RULE_FIELD_QUEST_COMPLETED_DESC"],descriptionKey="RULE_FIELD_QUEST_COMPLETED_DESC",category=L["RULE_DATA_PROVIDER"],dependencies={"demands"},demandNamespace="quests",collectDemand=collect("quests"),resolver=function(context)return context.character and context.character.demands and context.character.demands.quests and context.character.demands.quests[tonumber(context.argument)]end},
        {id="achievement.completed",aliases={"achievementCompleted"},type="boolean",name=L["RULE_FIELD_ACHIEVEMENT_COMPLETED"],nameKey="RULE_FIELD_ACHIEVEMENT_COMPLETED",description=L["RULE_FIELD_ACHIEVEMENT_COMPLETED_DESC"],descriptionKey="RULE_FIELD_ACHIEVEMENT_COMPLETED_DESC",category=L["RULE_DATA_PROVIDER"],dependencies={"demands"},demandNamespace="achievements",collectDemand=collect("achievements"),resolver=function(context)return context.character and context.character.demands and context.character.demands.achievements and context.character.demands.achievements[tonumber(context.argument)]end},
    },
}

HolyStorm:RegisterModule(metadata,function(Module)
    function Module:RebuildDemands()
        local demandStore=HolyStorm.DataManager:Get(demandsSchema)
        local seed=type(demandStore)=="table"and demandStore or{}
        seed.quests,seed.achievements={},{}
        local nodes={}
        local function appendObjects(objects)
            for _,object in pairs(objects or{}) do
                if type(object)=="table" and object.enabled~=false then nodes[#nodes+1]=object.root or object.rules or object end
            end
        end
        appendObjects(HolyStorm.FilterManager:GetRules("global"))
        appendObjects(HolyStorm.FilterManager:GetFilters("global"))
        appendObjects(HolyStorm.FilterManager:GetRules("local"))
        appendObjects(HolyStorm.FilterManager:GetFilters("local"))
        for _,group in pairs(HolyStorm.Policy:GetGroups()or{})do appendObjects(group.rules)end
        local demands=HolyStorm.Rules:CollectDemands(nodes,seed)
        local committed=HolyStorm.DataManager:Commit(demandsSchema,nil,demands,{source="CharacterRuleData.RebuildDemands"})
        if not committed or not committed.ok then return false,committed and committed.errorCode or"DEMANDS_COMMIT_FAILED"end
        if committed.changed then HolyStorm.Events:Emit("HS_RULE_DEMANDS_CHANGED",HolyStorm.Utils.DeepCopy(demands))end
        return true
    end
    function Module:Capture(guid)
        guid=guid or UnitGUID("player")
        if not guid then return false end
        local demands=HolyStorm.DataManager:Get(demandsSchema)or{}
        local snapshot={quests={},achievements={},updatedAt=HolyStorm.Utils.Now()}
        for id in pairs(demands.quests or{}) do if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then snapshot.quests[id]=C_QuestLog.IsQuestFlaggedCompleted(id)==true end end
        for id in pairs(demands.achievements or{}) do if GetAchievementInfo then local _,_,_,completed=GetAchievementInfo(id);snapshot.achievements[id]=completed==true end end
        return HolyStorm.Data.CharacterStore:Upsert(guid,{demands=snapshot},"blizzard")
    end
    function Module:OnInitialize()
        HolyStorm.Tasks:RegisterTaskType("CharacterRuleData.RebuildDemands",{name=L["TASK_RULE_DATA_REBUILD"],localizedNameKey="TASK_RULE_DATA_REBUILD",module="CharacterRuleData",priority=24,executionMode="UNIQUE",execute=function()return Module:RebuildDemands()end})
        HolyStorm.Tasks:RegisterTaskType("CharacterRuleData.Capture",{name=L["TASK_RULE_DATA_CAPTURE"],localizedNameKey="TASK_RULE_DATA_CAPTURE",module="CharacterRuleData",priority=25,executionMode="UNIQUE",execute=function()return Module:Capture()end})
    end
    function Module:OnEnable()
        HolyStorm.Events:Register("HS_RULE_DEMANDS_REBUILD_REQUESTED","character-rule-data",function()HolyStorm.Tasks:Queue("CharacterRuleData.RebuildDemands",{triggerSource="HS_RULE_DEMANDS_REBUILD_REQUESTED",debounce=.2})end)
        HolyStorm.Events:Register("HS_RULE_DEMANDS_CHANGED","character-rule-data",function()HolyStorm.Tasks:Queue("CharacterRuleData.Capture",{triggerSource="HS_RULE_DEMANDS_CHANGED",debounce=.5})end)
        HolyStorm.Rules:RebuildDemands()
    end
    function Module:OnDisable()
        HolyStorm.Events:UnregisterOwner("character-rule-data")
        HolyStorm.Tasks:Cancel("CharacterRuleData.RebuildDemands")
        HolyStorm.Tasks:Cancel("CharacterRuleData.Capture")
    end
end)
