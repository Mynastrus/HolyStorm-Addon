local addonVersion = "5.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Core = HolyStorm.PermissionCore

local templateDefinitions,templateOwners={},{}
local referenceProviders,referenceOwners={},{}
local Filters = {
    version=addonVersion,
    templateDefinitions=templateDefinitions,
    templateOwners=templateOwners,
    referenceProviders=referenceProviders,
}

local function emit(event,...)
    if HolyStorm.Events then HolyStorm.Events:Emit(event,...) end
end

local function validText(value,maximum,allowEmpty)
    return type(value)=="string" and #value<=maximum and (allowEmpty or value:match("%S")~=nil)
end

local function newObjectId(kind)
    return string.format("%s-%08x-%04x",kind=="rules"and"rule"or"filter",Core.Now()%0xffffffff,math.random(0,0xffff))
end

function Filters:RegisterTemplate(owner,template)
    if type(owner)~="string" or type(template)~="table" or not Core.ValidId(template.id) or not validText(template.name,128,false) then return false,"INVALID_TEMPLATE" end
    local root=template.root or template.rules
    local valid,reason=HolyStorm.Rules:ValidatePortable(root)
    if not valid then return false,reason end
    local current=templateDefinitions[template.id]
    if current and current.owner~=owner then return false,"TEMPLATE_ALREADY_REGISTERED" end
    local value=Core.Copy(template)
    value.owner,value.scope=owner,"template"
    templateDefinitions[value.id]=value
    templateOwners[owner]=templateOwners[owner]or{}
    templateOwners[owner][value.id]=true
    emit("HS_FILTER_TEMPLATE_REGISTERED",value.id,owner)
    return true
end

function Filters:UnregisterTemplateOwner(owner)
    local removed=0
    for id in pairs(templateOwners[owner]or{})do templateDefinitions[id]=nil;removed=removed+1 end
    templateOwners[owner]=nil
    if removed>0 then emit("HS_FILTER_TEMPLATES_CHANGED",owner) end
    return removed
end

function Filters:RegisterReferenceProvider(owner,id,provider)
    if not Core.ValidId(owner) or not Core.ValidId(id) or type(provider)~="function" then return false,"INVALID_REFERENCE_PROVIDER" end
    local current=referenceProviders[id]
    if current and current.owner~=owner then return false,"REFERENCE_PROVIDER_EXISTS" end
    referenceProviders[id]={owner=owner,resolve=provider}
    referenceOwners[owner]=referenceOwners[owner]or{}
    referenceOwners[owner][id]=true
    emit("HS_FILTER_REFERENCE_PROVIDER_CHANGED",id,owner,true)
    return true
end

function Filters:UnregisterReferenceOwner(owner)
    local removed=0
    for id in pairs(referenceOwners[owner]or{})do referenceProviders[id]=nil;removed=removed+1;emit("HS_FILTER_REFERENCE_PROVIDER_CHANGED",id,owner,false)end
    referenceOwners[owner]=nil
    return removed
end

function Filters:GetReferences(kind,id,scope,referenceState)
    local references={}
    for providerId,provider in pairs(referenceProviders)do
        local ok,result=HolyStorm.Utils.SafeCall("filter.references:"..providerId,provider.resolve,kind,id,scope,referenceState)
        if ok and type(result)=="table"then
            for _,entry in ipairs(result)do
                if type(entry)=="table"then
                    local value=Core.Copy(entry)
                    value.provider=value.provider or providerId
                    value.owner=value.owner or provider.owner
                    references[#references+1]=value
                end
            end
        elseif not ok then
            Core.Log("WARN","references","Reference provider failed",{provider=providerId,kind=kind,id=id,error=tostring(result)})
        end
    end
    table.sort(references,function(a,b)return tostring(a.kind)<tostring(b.kind)or a.kind==b.kind and tostring(a.id)<tostring(b.id)end)
    return references
end

function Filters:GetFilters(scope)return Core.Copy(self:GetStore("filters",scope)or{})end
function Filters:GetRules(scope)return Core.Copy(self:GetStore("rules",scope)or{})end
function Filters:GetFilter(id,scope)local value=(self:GetStore("filters",scope)or{})[id];return value and Core.Copy(value)end
function Filters:GetRule(id,scope)local value=(self:GetStore("rules",scope)or{})[id];return value and Core.Copy(value)end
function Filters:GetFilterTemplates()return Core.Copy(HolyStorm.db.global.filters.templates or{})end

function Filters:GetActiveFilters(contextId)
    local root=HolyStorm.db.profile.filters.activeByContext
    root[contextId]=root[contextId]or{}
    return Core.Copy(root[contextId])
end

function Filters:SetActiveFilters(contextId,filters)
    HolyStorm.db.profile.filters.activeByContext[contextId]=Core.Copy(filters or{})
    emit("HS_ACTIVE_FILTERS_UPDATED",contextId)
    return true
end

function Filters:AttachFilter(groupId,filterId)
    local group=self:GetGroup(groupId)
    if not group then return false,"NOT_FOUND" end
    if not(self:GetStore("filters")or{})[filterId]then return false,"FILTER_NOT_FOUND" end
    if Core.ArrayContains(group.filterIds,filterId)then return false,"UNCHANGED" end
    group.filterIds[#group.filterIds+1]=filterId
    table.sort(group.filterIds)
    return self:SaveGroup(group)
end

function Filters:DetachFilter(groupId,filterId)
    local group=self:GetGroup(groupId)
    if not group then return false,"NOT_FOUND" end
    local result={}
    for _,id in ipairs(group.filterIds)do if id~=filterId then result[#result+1]=id end end
    if #result==#group.filterIds then return false,"UNCHANGED" end
    group.filterIds=result
    return self:SaveGroup(group)
end

function Filters:ValidateObject(kind,object)
    if(kind~="filters"and kind~="rules")or type(object)~="table"or not Core.ValidId(object.id)then return false,"INVALID_OBJECT"end
    if not validText(object.name,128,false)then return false,"INVALID_OBJECT_NAME"end
    if object.description~=nil and not validText(object.description,1024,true)then return false,"INVALID_OBJECT_DESCRIPTION"end
    if object.category~=nil and not validText(object.category,96,true)then return false,"INVALID_OBJECT_CATEGORY"end
    if object.scope~=nil and object.scope~="local"and object.scope~="global"and object.scope~="template"then return false,"INVALID_OBJECT_SCOPE"end
    return HolyStorm.Rules:Validate(object.root or object.rules)
end

function Filters:SaveObject(kind,object,scope)
    scope=scope=="local"and"local"or"global"
    local valid,err=self:ValidateObject(kind,object)
    if not valid then return false,err end
    local current=(self:GetStore(kind,scope)or{})[object.id]
    if scope=="local"then
        local permission=kind=="rules"and"rules-manage"or current and"filters-edit"or"filters-create"
        if not HolyStorm.PermissionEngine:HasPermission(nil,nil,permission)then return false,"PERMISSION_DENIED"end
    end
    local saved=Core.Copy(object)
    saved.root=Core.Copy(saved.root or saved.rules)
    saved._summary,saved.tooltip=nil,nil
    saved.scope=scope
    saved.creator=current and current.creator or UnitGUID("player")
    saved.createdAt=current and current.createdAt or Core.Now()
    saved.modifiedAt=Core.Now()
    saved.modifiedBy=UnitGUID("player")
    saved.version=(tonumber(current and current.version)or 0)+1
    saved.rules=nil
    if current then
        local comparable=Core.Copy(saved)
        comparable.version=current.version
        comparable.modifiedAt=current.modifiedAt
        comparable.modifiedBy=current.modifiedBy
        if Core.Same(comparable,current)then return false,"UNCHANGED"end
    end
    if scope=="local"then
        self:GetStore(kind,"local")[saved.id]=saved
        HolyStorm.Rules:RebuildDemands()
        emit(kind=="filters"and"HS_FILTER_UPDATED"or"HS_RULE_UPDATED",saved.id,"local")
        return true,Core.Copy(saved)
    end
    local change=kind=="filters"and{action="FILTER_UPSERT",filter=saved}or{action="RULE_UPSERT",rule=saved}
    local ok,result=self:CommitChange(change)
    return ok,ok and Core.Copy(saved)or result
end

function Filters:DuplicateObject(kind,id,scope,overrides)
    if kind~="filters"and kind~="rules"then return false,"INVALID_KIND"end
    local object=kind=="filters"and self:GetFilter(id,scope)or kind=="rules"and self:GetRule(id,scope)
    if not object then return false,"NOT_FOUND"end
    local duplicate=Core.Copy(object)
    duplicate.id=nil
    for _=1,16 do local candidate=newObjectId(kind);local existing;if kind=="filters"then existing=self:GetFilter(candidate,scope)else existing=self:GetRule(candidate,scope)end;if not existing then duplicate.id=candidate;break end end
    if not duplicate.id then return false,"ID_GENERATION_FAILED"end
    duplicate.name=(overrides and overrides.name)or duplicate.name
    duplicate.description=(overrides and overrides.description)or duplicate.description
    duplicate.creator,duplicate.createdAt,duplicate.modifiedBy,duplicate.modifiedAt,duplicate.version=nil,nil,nil,nil,nil
    if overrides then for key,value in pairs(overrides)do if key~="id"then duplicate[key]=Core.Copy(value)end end end
    return self:SaveObject(kind,duplicate,scope)
end

function Filters:DeleteObject(kind,id,scope)
    scope=scope=="local"and"local"or"global"
    if kind~="filters"and kind~="rules"then return false,"INVALID_KIND"end
    local store=self:GetStore(kind,scope)
    if not store or not store[id]then return false,"NOT_FOUND"end
    if scope=="local"then
        local permission=kind=="rules"and"rules-manage"or"filters-delete"
        if not HolyStorm.PermissionEngine:HasPermission(nil,nil,permission)then return false,"PERMISSION_DENIED"end
    end
    local references=self:GetReferences(kind,id,scope)
    if #references>0 then return false,kind=="filters"and"FILTER_IN_USE"or"RULE_IN_USE",references end
    if scope=="local"then
        store[id]=nil
        HolyStorm.Rules:RebuildDemands()
        emit(kind=="filters"and"HS_FILTER_DELETED"or"HS_RULE_DELETED",id,"local")
        return true
    end
    if kind=="filters"then return self:CommitChange({action="FILTER_DELETE",filterId=id})end
    return self:CommitChange({action="RULE_DELETE",ruleId=id})
end

function Filters:Save(kind,object,scope)if kind=="groups"then return self:SaveGroup(object)end;return self:SaveObject(kind,object,scope)end
function Filters:Delete(kind,id,scope)if kind=="groups"then return self:DeleteGroup(id)end;return self:DeleteObject(kind,id,scope)end
function Filters:SaveRule(rule,scope)return self:SaveObject("rules",rule,scope)end
function Filters:DeleteRule(id,scope)return self:DeleteObject("rules",id,scope)end
function Filters:SaveFilter(filter,scope)return self:SaveObject("filters",filter,scope)end
function Filters:DeleteFilter(id,scope)return self:DeleteObject("filters",id,scope)end
function Filters:DuplicateFilter(id,scope,overrides)return self:DuplicateObject("filters",id,scope,overrides)end
function Filters:DuplicateRule(id,scope,overrides)return self:DuplicateObject("rules",id,scope,overrides)end
function Filters:CreateFilter(filter)return self:SaveFilter(filter,"global")end

function Filters:UpdateFilter(id,changes)
    local filter=self:GetFilter(id,"global")
    if not filter then return false,"NOT_FOUND"end
    for key,value in pairs(changes or{})do if key~="id"then filter[key]=Core.Copy(value)end end
    return self:SaveFilter(filter,"global")
end

function Filters:EvaluateRule(ruleOrId,context,scope)
    local rule=type(ruleOrId)=="string"and self:GetRule(ruleOrId,scope)or ruleOrId
    if not rule then return false,{{kind="error",error="RULE_NOT_FOUND",reason="RULE_NOT_FOUND",status=HolyStorm.Rules.Result.UNKNOWN,result=false}},HolyStorm.Rules.Result.UNKNOWN end
    return HolyStorm.Rules:Evaluate(rule.root or rule.rules or rule,context)
end

function Filters:ApplyFilter(filterOrId,value,scope)
    local filter=type(filterOrId)=="string"and self:GetFilter(filterOrId,scope)or filterOrId
    if not filter then return false,{{kind="error",error="FILTER_NOT_FOUND",reason="FILTER_NOT_FOUND",status=HolyStorm.Rules.Result.UNKNOWN,result=false}},HolyStorm.Rules.Result.UNKNOWN end
    local context=value and value.character and value or self:BuildContext(value and(value.accountUUID or value.playerId),value and(value.guid or value.characterGuid))
    if value and not value.character then
        context.character=value.characterRecord or HolyStorm.Data.CharacterStore:Get(value.guid or value.characterGuid)
        context.member=value.member or context.member
        context.target=value
    end
    return HolyStorm.Rules:Evaluate(filter.root or filter.rules,context)
end

function Filters:Preview(kind,objectOrId,entity,scope)
    if kind~="filters"and kind~="rules"then return false,"INVALID_KIND"end
    local beforeState=self:GetPermissionStateStatus()
    local beforeRevision=beforeState and beforeState.revisionID
    local object=type(objectOrId)=="table"and Core.Copy(objectOrId)or kind=="filters"and self:GetFilter(objectOrId,scope)or self:GetRule(objectOrId,scope)
    if not object then return false,"NOT_FOUND"end
    local context=entity and entity.character and entity or self:BuildContext(entity and entity.accountUUID,entity and(entity.characterUUID or entity.guid))
    if entity and not entity.character then
        local guid=entity.characterUUID or entity.guid
        context.character=entity.characterRecord or(guid and HolyStorm.Data.CharacterStore:Get(guid))
        context.member=entity.member or context.member
        context.target=Core.Copy(entity)
    end
    local result,trace,status
    if kind=="filters"then result,trace,status=self:ApplyFilter(object,context,scope)else result,trace,status=self:EvaluateRule(object,context,scope)end
    local afterState=self:GetPermissionStateStatus()
    if beforeRevision~=(afterState and afterState.revisionID)then return false,"PREVIEW_MUTATED_STATE"end
    return true,{kind=kind,id=object.id,entityId=context.characterUUID or context.guid,result=result,status=status,trace=Core.Copy(trace),evaluatedAt=Core.Now()}
end

function Filters:ApplyFilters(active,value,combine)
    local mode=string.upper(combine or"AND")
    local status=mode=="OR"and HolyStorm.Rules.Result.FAIL or HolyStorm.Rules.Result.PASS
    local trace={}
    for _,entry in ipairs(active or{})do
        local id,scope=type(entry)=="table"and entry.id or entry,type(entry)=="table"and entry.scope or nil
        local ok,detail,childStatus=self:ApplyFilter(id,value,scope)
        trace[#trace+1]={id=id,result=ok,status=childStatus,trace=detail}
        if mode=="OR"then
            if childStatus==HolyStorm.Rules.Result.PASS then status=HolyStorm.Rules.Result.PASS elseif childStatus==HolyStorm.Rules.Result.UNKNOWN and status~=HolyStorm.Rules.Result.PASS then status=HolyStorm.Rules.Result.UNKNOWN end
        elseif childStatus==HolyStorm.Rules.Result.FAIL then status=HolyStorm.Rules.Result.FAIL elseif childStatus==HolyStorm.Rules.Result.UNKNOWN and status~=HolyStorm.Rules.Result.FAIL then status=HolyStorm.Rules.Result.UNKNOWN end
    end
    return status==HolyStorm.Rules.Result.PASS,trace,status
end

function Filters:GetUsage(kind,id,scope)return self:GetReferences(kind,id,scope)end

function Filters:GetObjectSummary(kind,id,scope)
    local store=scope=="template"and kind=="filters"and HolyStorm.db.global.filters.templates or self:GetStore(kind,scope)
    local object=(store or{})[id]
    if not object then return nil end
    local conditions,providers,missing=0,{},{}
    local function walk(node)
        if type(node)~="table"then return end
        if node.field then
            conditions=conditions+1
            local field=HolyStorm.Rules:GetField(node.field)
            if field then
                providers[field.owner or field.module or"unknown"]=true
                local context=self.BuildContext and self:BuildContext(nil,UnitGUID("player"))or{}
                local available=HolyStorm.Rules:GetFieldAvailability(node.field,context,node)
                if not available then missing[node.field]=true end
            else missing[node.field]=true end
        end
        for _,child in ipairs(node.children or{})do walk(child)end
    end
    walk(object.root or object.rules)
    return{id=id,name=object.name,description=object.description,category=object.category,creator=object.creator,createdAt=object.createdAt,modifiedBy=object.modifiedBy,modifiedAt=object.modifiedAt or object.updatedAt,version=object.version,conditions=conditions,references=#self:GetReferences(kind,id,scope),providers=Core.TableKeys(providers),missingFields=Core.TableKeys(missing),status=next(missing)and"UNAVAILABLE"or"AVAILABLE",scope=scope or object.scope or"global"}
end

function Filters:RestoreTemplates()
    local templates=HolyStorm.db.global.filters.templates
    for _,template in pairs(templateDefinitions)do if not templates[template.id]then templates[template.id]=Core.Copy(template)end end
end

Filters:RegisterReferenceProvider("core","groups",function(kind,id,scope,referenceState)
    local usage={}
    if scope=="local"then return usage end
    local groups=referenceState and referenceState.groups or HolyStorm.PolicyState and HolyStorm.PolicyState:GetStore("groups")or{}
    for groupId,group in pairs(groups)do
        local ids=kind=="filters"and group.filterIds or kind=="rules"and group.ruleIds or{}
        for _,candidate in ipairs(ids or{})do if candidate==id then usage[#usage+1]={kind="group",id=groupId,name=group.name}end end
    end
    return usage
end)

Filters:RegisterReferenceProvider("core","active-contexts",function(kind,id,scope)
    local usage={}
    if kind~="filters"then return usage end
    local profile=HolyStorm.db and HolyStorm.db.profile
    for contextId,entries in pairs(profile and profile.filters and profile.filters.activeByContext or{})do
        for _,entry in ipairs(entries or{})do
            local entryId=type(entry)=="table"and entry.id or entry
            local entryScope=type(entry)=="table"and(entry.scope or"global")or"global"
            if entryId==id and entryScope==(scope or"global")then usage[#usage+1]={kind="context",id=contextId,name=contextId}end
        end
    end
    return usage
end)

HolyStorm.PermissionComponents=HolyStorm.PermissionComponents or{}
HolyStorm.PermissionComponents.Filters=Filters
