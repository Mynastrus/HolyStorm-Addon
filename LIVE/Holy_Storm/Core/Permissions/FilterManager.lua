local addonVersion = "5.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Core = HolyStorm.PermissionCore
local Filters = { version=addonVersion }

function Filters:GetFilters(scope) return Core.Copy(self:GetStore("filters",scope) or {}) end
function Filters:GetRules(scope) return Core.Copy(self:GetStore("rules",scope) or {}) end
function Filters:GetFilter(id,scope) local value=(self:GetStore("filters",scope) or {})[id]; return value and Core.Copy(value) end
function Filters:GetRule(id,scope) local value=(self:GetStore("rules",scope) or {})[id]; return value and Core.Copy(value) end
function Filters:GetFilterTemplates() return Core.Copy(HolyStorm.db.global.filters.templates or {}) end
function Filters:GetActiveFilters(contextId)
    local root=HolyStorm.db.profile.filters.activeByContext; root[contextId]=root[contextId] or {}; return Core.Copy(root[contextId])
end
function Filters:SetActiveFilters(contextId,filters)
    HolyStorm.db.profile.filters.activeByContext[contextId]=Core.Copy(filters or {}); HolyStorm.Events:Emit("HS_ACTIVE_FILTERS_UPDATED",contextId); return true
end
function Filters:AttachFilter(groupId,filterId)
    local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end
    if not (self:GetStore("filters") or {})[filterId] then return false,"FILTER_NOT_FOUND" end
    if Core.ArrayContains(group.filterIds,filterId) then return false,"UNCHANGED" end
    group.filterIds[#group.filterIds+1]=filterId; table.sort(group.filterIds); return self:SaveGroup(group)
end
function Filters:DetachFilter(groupId,filterId)
    local group=self:GetGroup(groupId); if not group then return false,"NOT_FOUND" end
    local result={}; for _,id in ipairs(group.filterIds) do if id~=filterId then result[#result+1]=id end end
    if #result==#group.filterIds then return false,"UNCHANGED" end; group.filterIds=result; return self:SaveGroup(group)
end
function Filters:ValidateObject(kind,object)
    if (kind~="filters" and kind~="rules") or type(object)~="table" or not Core.ValidId(object.id) or type(object.name)~="string" then return false,"INVALID_OBJECT" end
    return HolyStorm.Rules:Validate(object.root or object.rules)
end
function Filters:SaveObject(kind,object,scope)
    if scope=="local" then
        local valid,err=self:ValidateObject(kind,object); if not valid then return false,err end
        local store=self:GetStore(kind,"local"); local saved=Core.Copy(object); saved.version=((store[saved.id] and store[saved.id].version) or 0)+1; saved.updatedAt=Core.Now(); store[saved.id]=saved; HolyStorm.Rules:RebuildDemands(); HolyStorm.Events:Emit(kind=="filters" and "HS_FILTER_UPDATED" or "HS_RULE_UPDATED",saved.id); return true,Core.Copy(saved)
    end
    if kind~="filters" and kind~="rules" then return false,"INVALID_KIND" end
    local valid,err=self:ValidateObject(kind,object); if not valid then return false,err end
    local current=(self:GetStore(kind) or {})[object.id]; local saved=Core.Copy(object); saved.id=object.id; saved.name=object.name; saved.creator=current and current.creator or object.creator or UnitGUID("player"); saved.createdAt=current and current.createdAt or object.createdAt or Core.Now()
    if current then local comparable=Core.Copy(saved); comparable.modifiedAt=current.modifiedAt; comparable.modifiedBy=current.modifiedBy; if Core.Same(comparable,current) then return false,"UNCHANGED" end end
    saved.modifiedAt=Core.Now(); saved.modifiedBy=UnitGUID("player")
    local change=kind=="filters" and {action="FILTER_UPSERT",filter=saved} or {action="RULE_UPSERT",rule=saved}
    local ok,result=self:CommitChange(change); return ok,ok and Core.Copy(saved) or result
end
function Filters:DeleteObject(kind,id,scope)
    if scope=="local" then local store=self:GetStore(kind,"local"); if not store[id] then return false,"NOT_FOUND" end; store[id]=nil; HolyStorm.Rules:RebuildDemands(); return true end
    if kind=="filters" then for _,group in pairs(self:GetStore("groups")) do if Core.ArrayContains(group.filterIds,id) then return false,"FILTER_IN_USE" end end; return self:CommitChange({action="FILTER_DELETE",filterId=id}) end
    if kind=="rules" then for _,group in pairs(self:GetStore("groups")) do if Core.ArrayContains(group.ruleIds,id) then return false,"RULE_IN_USE" end end; return self:CommitChange({action="RULE_DELETE",ruleId=id}) end
    return false,"INVALID_KIND"
end
function Filters:Save(kind,object,scope) if kind=="groups" then return self:SaveGroup(object) end; return self:SaveObject(kind,object,scope) end
function Filters:Delete(kind,id,scope) if kind=="groups" then return self:DeleteGroup(id) end; return self:DeleteObject(kind,id,scope) end
function Filters:SaveRule(rule,scope) return self:SaveObject("rules",rule,scope) end
function Filters:DeleteRule(id,scope) return self:DeleteObject("rules",id,scope) end
function Filters:SaveFilter(filter,scope) return self:SaveObject("filters",filter,scope) end
function Filters:DeleteFilter(id,scope) return self:DeleteObject("filters",id,scope) end
function Filters:CreateFilter(filter) return self:SaveFilter(filter,"global") end
function Filters:UpdateFilter(id,changes)
    local filter=Core.Copy((self:GetStore("filters") or {})[id]); if not filter then return false,"NOT_FOUND" end
    for key,value in pairs(changes or {}) do if key~="id" then filter[key]=Core.Copy(value) end end
    return self:SaveFilter(filter,"global")
end
function Filters:EvaluateRule(ruleOrId,context,scope)
    local rule=type(ruleOrId)=="string" and self:GetRule(ruleOrId,scope) or ruleOrId
    if not rule then return false,{{kind="error",error="RULE_NOT_FOUND"}},HolyStorm.Rules.Result.UNKNOWN end
    return HolyStorm.Rules:Evaluate(rule.root or rule.rules or rule,context)
end
function Filters:ApplyFilter(filterOrId,value,scope)
    local filter=type(filterOrId)=="string" and self:GetFilter(filterOrId,scope) or filterOrId
    if not filter then return false,{{kind="error",error="FILTER_NOT_FOUND"}},HolyStorm.Rules.Result.UNKNOWN end
    local context=value and value.character and value or self:BuildContext(value and (value.accountUUID or value.playerId),value and (value.guid or value.characterGuid))
    if value and not value.character then context.character=value.characterRecord or HolyStorm.Data.CharacterStore:Get(value.guid); context.member=value.member or context.member; context.target=value end
    return HolyStorm.Rules:Evaluate(filter.root or filter.rules,context)
end
function Filters:ApplyFilters(active,value,combine)
    local mode=string.upper(combine or "AND"); local result=mode~="OR"; local trace={}; local sawUnknown=false
    for _,entry in ipairs(active or {}) do
        local id,scope=type(entry)=="table" and entry.id or entry,type(entry)=="table" and entry.scope or nil
        local ok,detail,status=self:ApplyFilter(id,value,scope); trace[#trace+1]={id=id,result=ok,status=status,trace=detail}
        if status==HolyStorm.Rules.Result.UNKNOWN then sawUnknown=true end
        if mode=="OR" then result=result or ok elseif not ok then result=false end
    end
    return result,trace,sawUnknown and HolyStorm.Rules.Result.UNKNOWN or (result and HolyStorm.Rules.Result.PASS or HolyStorm.Rules.Result.FAIL)
end
function Filters:GetUsage(kind,id)
    local usage={}; for groupId,group in pairs(self:GetStore("groups") or {}) do for _,candidate in ipairs(group.filterIds or {}) do if kind=="filters" and candidate==id then usage[#usage+1]={kind="group",id=groupId} end end; for _,candidate in ipairs(group.ruleIds or {}) do if kind=="rules" and candidate==id then usage[#usage+1]={kind="group",id=groupId} end end end; return usage
end
function Filters:GetObjectSummary(kind,id,scope)
    local store=scope=="template" and kind=="filters" and HolyStorm.db.global.filters.templates or self:GetStore(kind,scope); local object=(store or {})[id]; if not object then return nil end
    local conditions=0; local function walk(node) if type(node)~="table" then return end; if node.field then conditions=conditions+1 end; for _,child in ipairs(node.children or {}) do walk(child) end end; walk(object.root or object.rules)
    return {id=id,name=object.name,description=object.description,creator=object.creator,createdAt=object.createdAt,modifiedAt=object.modifiedAt or object.updatedAt,conditions=conditions,references=#self:GetUsage(kind,id)}
end
function Filters:RestoreTemplates()
    local templates=HolyStorm.db.global.filters.templates
    local definitions={{id="template-max-level",name=L["FILTER_TEMPLATE_MAX_LEVEL"],description=L["FILTER_TEMPLATE_MAX_LEVEL_DESC"],scope="template",rules={field="character.maxLevel",operator="true"}},{id="template-main",name=L["FILTER_TEMPLATE_MAIN"],description=L["FILTER_TEMPLATE_MAIN_DESC"],scope="template",rules={field="character.mainTwinkStatus",operator="=",value="MAIN"}},{id="template-online",name=L["FILTER_TEMPLATE_ONLINE"],description=L["FILTER_TEMPLATE_ONLINE_DESC"],scope="template",rules={field="player.online",operator="true"}}}
    for _,template in ipairs(definitions) do if not templates[template.id] then templates[template.id]=template end end
end

HolyStorm.PermissionComponents = HolyStorm.PermissionComponents or {}
HolyStorm.PermissionComponents.Filters = Filters
