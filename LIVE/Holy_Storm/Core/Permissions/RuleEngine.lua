local addonVersion = "4.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Rules = {
    version = addonVersion,
    fields = {},
    aliases = {},
    owners = {},
    operators = {},
    maxDepth = 8,
    maxChildren = 32,
    maxListValues = 100,
    Result = { PASS="PASS", FAIL="FAIL", UNKNOWN="UNKNOWN" },
}

local function lower(value) return string.lower(tostring(value or "")) end
local function equals(left,right)
    if type(left)=="number" or type(right)=="number" then return tonumber(left)~=nil and tonumber(left)==tonumber(right) end
    return left==right
end
local function inList(actual,values)
    if type(values)~="table" then return false end
    for _,value in pairs(values) do if equals(actual,value) then return true end end
    return false
end
local function validId(value) return type(value)=="string" and value:match("^[%w%._%-]+$")~=nil end
local function copy(value) return HolyStorm.Utils.DeepCopy(value) end
local function log(level,category,message,context)
    if HolyStorm.Logger and HolyStorm.Logger.Write then HolyStorm.Logger:Write(level,"Rules",category,message,context) end
end

Rules.operators["="] = equals
Rules.operators["!="] = function(a,b) return not equals(a,b) end
Rules.operators[">"] = function(a,b) return tonumber(a) and tonumber(b) and tonumber(a)>tonumber(b) or false end
Rules.operators[">="] = function(a,b) return tonumber(a) and tonumber(b) and tonumber(a)>=tonumber(b) or false end
Rules.operators["<"] = function(a,b) return tonumber(a) and tonumber(b) and tonumber(a)<tonumber(b) or false end
Rules.operators["<="] = function(a,b) return tonumber(a) and tonumber(b) and tonumber(a)<=tonumber(b) or false end
Rules.operators.between = function(a,b)
    local low,high=type(b)=="table" and tonumber(b[1]),type(b)=="table" and tonumber(b[2])
    return tonumber(a) and low and high and tonumber(a)>=low and tonumber(a)<=high or false
end
Rules.operators.not_between = function(a,b) return not Rules.operators.between(a,b) end
Rules.operators.contains = function(a,b) return lower(a):find(lower(b),1,true)~=nil end
Rules.operators.not_contains = function(a,b) return not Rules.operators.contains(a,b) end
Rules.operators.starts_with = function(a,b) return lower(a):sub(1,#lower(b))==lower(b) end
Rules.operators.ends_with = function(a,b) local x,y=lower(a),lower(b);return y=="" or x:sub(-#y)==y end
Rules.operators["in"] = inList
Rules.operators.not_in = function(a,b) return not inList(a,b) end
Rules.operators["true"] = function(a) return a==true end
Rules.operators["false"] = function(a) return a==false end
Rules.operators.exists = function(a) return a~=nil end
Rules.operators.not_exists = function(a) return a==nil end
Rules.operators.range=Rules.operators.between
Rules.operators.in_list=Rules.operators["in"]
Rules.operators.not_in_list=Rules.operators.not_in
Rules.operators.is_true=Rules.operators["true"]
Rules.operators.is_false=Rules.operators["false"]

local defaultOperators = {
    boolean={"=","!=","true","false","exists","not_exists"},
    number={"=","!=",">",">=","<","<=","between","not_between","exists","not_exists"},
    string={"=","!=","contains","not_contains","starts_with","ends_with","in","not_in","exists","not_exists"},
}
defaultOperators.enum=defaultOperators.string
defaultOperators.character=defaultOperators.string
defaultOperators.account=defaultOperators.string
defaultOperators.any={"=","!=","exists","not_exists"}

local function normalizeFieldArguments(owner,fieldID,definition)
    if definition==nil and type(fieldID)=="table" then
        definition=fieldID;fieldID=owner;owner=definition.owner or definition.module or "legacy"
    end
    return owner,fieldID,definition
end

local function normalizeAllowedOperators(definition)
    local source=definition.allowedOperators or defaultOperators[definition.type or "any"] or defaultOperators.any
    local list,set={},{}
    for key,value in pairs(source) do
        local operator=type(key)=="number" and value or value==true and key or nil
        if type(operator)=="string" and Rules.operators[operator] and not set[operator] then set[operator]=true;list[#list+1]=operator end
    end
    return list,set
end

function Rules:RegisterField(owner,fieldID,definition)
    owner,fieldID,definition=normalizeFieldArguments(owner,fieldID,definition)
    local resolver=type(definition)=="table" and (definition.resolver or definition.get)
    if not validId(owner) or not validId(fieldID) or type(definition)~="table" or type(resolver)~="function" then return false,"INVALID_FIELD" end
    local current=self.fields[fieldID]
    if current and current.owner~=owner then return false,"FIELD_ALREADY_REGISTERED" end
    local normalized=copy(definition)
    normalized.id,normalized.owner,normalized.module=fieldID,owner,definition.module or owner
    normalized.type=definition.type or "any"
    normalized.resolver=resolver
    normalized.get=normalized.resolver -- Compatibility for existing consumers.
    normalized.dependencies=type(definition.dependencies)=="table" and copy(definition.dependencies) or {}
    normalized.allowedOperators,normalized._allowedOperatorSet=normalizeAllowedOperators(normalized)
    self.fields[fieldID]=normalized
    self.owners[owner]=self.owners[owner] or {fields={},aliases={}}
    self.owners[owner].fields[fieldID]=true
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_RULE_FIELD_REGISTERED",fieldID,owner);HolyStorm.Events:Emit("HS_RULE_PROVIDER_REGISTERED",fieldID) end
    return true
end

function Rules:RegisterAlias(owner,aliasID,targetID)
    if not validId(owner) or not validId(aliasID) or not validId(targetID) then return false,"INVALID_ALIAS" end
    local target=self.fields[targetID]
    if not target then return false,"FIELD_NOT_FOUND" end
    if target.owner~=owner then return false,"OWNER_MISMATCH" end
    local current=self.aliases[aliasID]
    if (self.fields[aliasID] and self.fields[aliasID].owner~=owner) or (current and current.owner~=owner) then return false,"FIELD_ALREADY_REGISTERED" end
    self.aliases[aliasID]={owner=owner,target=targetID}
    self.owners[owner]=self.owners[owner] or {fields={},aliases={}}
    self.owners[owner].aliases[aliasID]=true
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_RULE_FIELD_REGISTERED",aliasID,owner) end
    return true
end

function Rules:_ResolveField(fieldID)
    local alias=self.aliases[fieldID]
    if alias then return self.fields[alias.target],alias.target,alias end
    return self.fields[fieldID],fieldID,nil
end

function Rules:GetField(fieldID)
    local definition,resolvedID,alias=self:_ResolveField(fieldID)
    if not definition then return nil end
    local result=copy(definition)
    if alias then result.id=fieldID;result.aliasOf=resolvedID;result.owner=alias.owner;result.hidden=true end
    return result
end

function Rules:GetFields()
    local result={}
    for id,definition in pairs(self.fields) do result[id]=copy(definition) end
    for aliasID in pairs(self.aliases) do result[aliasID]=self:GetField(aliasID) end
    return result
end

function Rules:GetFieldsByOwner(owner)
    local result={}
    local owned=self.owners[owner]
    for id in pairs(owned and owned.fields or {}) do if self.fields[id] then result[id]=copy(self.fields[id]) end end
    for id in pairs(owned and owned.aliases or {}) do if self.aliases[id] then result[id]=self:GetField(id) end end
    return result
end

function Rules:UnregisterField(owner,fieldID)
    if fieldID==nil then fieldID=owner;owner=nil end
    local definition=self.fields[fieldID]
    local alias=self.aliases[fieldID]
    local actualOwner=definition and definition.owner or alias and alias.owner
    if not actualOwner then return false,"FIELD_NOT_FOUND" end
    if owner and owner~=actualOwner then return false,"OWNER_MISMATCH" end
    if definition then
        self.fields[fieldID]=nil
        if self.owners[actualOwner] then self.owners[actualOwner].fields[fieldID]=nil end
        local aliases={}
        for aliasID,entry in pairs(self.aliases) do if entry.owner==actualOwner and entry.target==fieldID then aliases[#aliases+1]=aliasID end end
        for _,aliasID in ipairs(aliases) do self:UnregisterField(actualOwner,aliasID) end
    else
        self.aliases[fieldID]=nil
        if self.owners[actualOwner] then self.owners[actualOwner].aliases[fieldID]=nil end
    end
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_RULE_FIELD_UNREGISTERED",fieldID,actualOwner) end
    return true
end

function Rules:UnregisterOwner(owner)
    local owned=self.owners[owner]
    if not owned then return 0 end
    local ids={}
    for id in pairs(owned.aliases) do ids[#ids+1]=id end
    for id in pairs(owned.fields) do ids[#ids+1]=id end
    local removed=0
    for _,id in ipairs(ids) do if self:UnregisterField(owner,id) then removed=removed+1 end end
    self.owners[owner]=nil
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_RULE_OWNER_UNREGISTERED",owner,removed) end
    return removed
end

function Rules:GetAllowedOperators(fieldOrID)
    local definition=type(fieldOrID)=="table" and fieldOrID or self:_ResolveField(fieldOrID)
    return definition and copy(definition.allowedOperators) or copy(defaultOperators.any)
end

local function valueMatchesType(kind,value)
    if kind=="any" or value==nil then return true end
    if kind=="number" then return tonumber(value)~=nil end
    if kind=="boolean" then return type(value)=="boolean" end
    if kind=="string" or kind=="enum" or kind=="character" or kind=="account" then return type(value)=="string" or type(value)=="number" end
    return true
end

function Rules:GetFieldValue(fieldID,context,node)
    local field,resolvedID=self:_ResolveField(fieldID)
    if not field then return nil,"UNKNOWN_FIELD:"..tostring(fieldID) end
    context=context or{}
    local resolverContext={}
    for key,value in pairs(context) do resolverContext[key]=value end
    resolverContext.accountUUID=context.accountUUID or context.playerId
    resolverContext.characterUUID=context.characterUUID or context.guid
    resolverContext.argument=node and (node.argument~=nil and node.argument or node.value)
    if field.availability then
        local ok,available,reason=HolyStorm.Utils.SafeCall("rule.availability:"..resolvedID,field.availability,resolverContext,node)
        if not ok then log("WARN","availability","Rule field availability failed",{field=fieldID,owner=field.owner,error=tostring(available)});return nil,"AVAILABILITY_ERROR:"..fieldID end
        if not available then return nil,reason or "FIELD_UNAVAILABLE:"..fieldID end
    end
    local ok,value,reason=HolyStorm.Utils.SafeCall("rule.field:"..resolvedID,field.resolver,resolverContext,node)
    if not ok then log("ERROR","resolver","Rule field resolver failed",{field=fieldID,owner=field.owner,error=tostring(value)});return nil,"RESOLVER_ERROR:"..fieldID end
    if value==nil then return nil,reason or "MISSING_DATA:"..fieldID end
    if not valueMatchesType(field.type,value) then
        log("WARN","resolver","Rule field resolver returned an invalid type",{field=fieldID,owner=field.owner,expected=field.type,actual=type(value)})
        return nil,"TYPE_MISMATCH:"..fieldID
    end
    return value,nil
end

function Rules:GetDependencies(node)
    local found={}
    local function walk(current)
        if type(current)~="table" then return end
        if current.field then local provider=self:_ResolveField(current.field);for _,dependency in ipairs(provider and provider.dependencies or{}) do found[dependency]=true end end
        for _,child in ipairs(current.children or{}) do walk(child) end
    end
    walk(node)
    local result={};for dependency in pairs(found) do result[#result+1]=dependency end;table.sort(result);return result
end

function Rules:_Validate(node,depth,count,portableOnly)
    depth=depth or 0;count=count or {value=0}
    if type(node)~="table" then return false,"RULE_NOT_TABLE" end
    count.value=count.value+1
    if count.value>256 then return false,"RULE_TOO_LARGE" end
    if depth>self.maxDepth then return false,"RULE_TOO_DEEP" end
    if node.logic then
        local logic=string.upper(tostring(node.logic))
        if logic~="AND" and logic~="OR" and logic~="NOT" then return false,"INVALID_LOGIC" end
        if type(node.children)~="table" or #node.children==0 or #node.children>self.maxChildren or (logic=="NOT" and #node.children~=1) then return false,"INVALID_CHILDREN" end
        for _,child in ipairs(node.children) do local ok,reason=self:_Validate(child,depth+1,count,portableOnly);if not ok then return false,reason end end
        return true
    end
    if not validId(node.field) then return false,"INVALID_FIELD" end
    local operator=node.operator or "="
    if not self.operators[operator] then return false,"UNKNOWN_OPERATOR:"..tostring(operator) end
    if operator~="true" and operator~="false" and operator~="exists" and operator~="not_exists" and node.value==nil then return false,"MISSING_VALUE" end
    if operator=="between" or operator=="not_between" or operator=="in" or operator=="not_in" then
        if type(node.value)~="table" or #node.value==0 or #node.value>self.maxListValues then return false,"INVALID_VALUE" end
        if (operator=="between" or operator=="not_between") and (#node.value~=2 or tonumber(node.value[1])==nil or tonumber(node.value[2])==nil) then return false,"INVALID_VALUE" end
    end
    if portableOnly then return true end
    local field=self:_ResolveField(node.field)
    if not field then return true end -- Unknown optional fields remain structurally portable.
    if not field._allowedOperatorSet[operator] then return false,"INVALID_OPERATOR_FOR_TYPE:"..operator end
    if field.type=="number" and operator~="exists" and operator~="not_exists" and operator~="true" and operator~="false" then
        if type(node.value)=="table" then for _,value in ipairs(node.value) do if tonumber(value)==nil then return false,"INVALID_VALUE_TYPE:number" end end
        elseif tonumber(node.value)==nil then return false,"INVALID_VALUE_TYPE:number" end
    elseif field.type=="boolean" and (operator=="=" or operator=="!=") and type(node.value)~="boolean" then return false,"INVALID_VALUE_TYPE:boolean" end
    return true
end

function Rules:Validate(node) return self:_Validate(node,0,{value=0},false) end
function Rules:ValidatePortable(node) return self:_Validate(node,0,{value=0},true) end
Rules.ValidateStructure=Rules.ValidatePortable

function Rules:EvaluateDetailed(node,context,trace)
    trace=trace or{}
    local PASS,FAIL,UNKNOWN=self.Result.PASS,self.Result.FAIL,self.Result.UNKNOWN
    local valid,validationError=self:Validate(node)
    if not valid then trace[#trace+1]={kind="error",error=validationError,status=UNKNOWN,result=false};log("WARN","validation","Invalid rule",{error=validationError});return UNKNOWN,trace end
    local function evaluate(current)
        if current.logic then
            local logic=string.upper(current.logic);local status
            if logic=="NOT" then local child=evaluate(current.children[1]);status=child==PASS and FAIL or child==FAIL and PASS or UNKNOWN
            elseif logic=="OR" then status=FAIL;for _,childNode in ipairs(current.children) do local child=evaluate(childNode);if child==PASS then status=PASS elseif child==UNKNOWN and status~=PASS then status=UNKNOWN end end
            else status=PASS;for _,childNode in ipairs(current.children) do local child=evaluate(childNode);if child==FAIL then status=FAIL elseif child==UNKNOWN and status~=FAIL then status=UNKNOWN end end end
            trace[#trace+1]={kind="group",logic=logic,status=status,result=status==PASS};return status
        end
        local actual,reason=self:GetFieldValue(current.field,context,current)
        local status=reason and UNKNOWN or (self.operators[current.operator or "="](actual,current.value) and PASS or FAIL)
        trace[#trace+1]={kind="condition",field=current.field,operator=current.operator or "=",expected=current.value,actual=actual,status=status,result=status==PASS,error=reason}
        return status
    end
    local ok,status=HolyStorm.Utils.SafeCall("rule.evaluate",evaluate,node)
    if not ok then log("ERROR","evaluation","Unexpected rule evaluation error",{error=tostring(status)});trace[#trace+1]={kind="error",error=tostring(status),status=UNKNOWN,result=false};return UNKNOWN,trace end
    log("DEBUG","evaluation","Rule evaluated",{result=status});return status,trace
end

function Rules:Evaluate(node,context,trace)
    local status,details=self:EvaluateDetailed(node,context,trace)
    return status==self.Result.PASS,details,status
end

function Rules:CollectDemands(nodes,seed)
    local demands=copy(seed or{})
    local function walk(node)
        if type(node)~="table" then return end
        local field=self:_ResolveField(node.field)
        if field and type(field.collectDemand)=="function" then
            local ok,reason=HolyStorm.Utils.SafeCall("rule.demand:"..tostring(node.field),field.collectDemand,node,demands)
            if not ok then log("WARN","demand","Rule demand collector failed",{field=node.field,owner=field.owner,error=tostring(reason)}) end
        end
        for _,child in ipairs(node.children or{}) do walk(child) end
    end
    for _,node in ipairs(nodes or{}) do walk(node) end
    return demands
end

function Rules:RebuildDemands()
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_RULE_DEMANDS_REBUILD_REQUESTED") end
    local global=HolyStorm.db and HolyStorm.db.global
    return copy(global and global.filters and global.filters.demands or{})
end

function Rules:Initialize() end

HolyStorm.Rules,HolyStorm.RuleEngine=Rules,Rules
Rules.RegisterConditionProvider=Rules.RegisterField
