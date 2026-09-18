local addonVersion = "4.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Rules = {
    version = addonVersion,
    fields = {},
    aliases = {},
    owners = {},
    operators = {},
    operatorDefinitions = {},
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
local function validOperatorId(value) return type(value)=="string" and #value>0 and #value<=32 and value:match("^[%w_<>!=%-]+$")~=nil end
local function copy(value) return HolyStorm.Utils.DeepCopy(value) end
local function log(level,category,message,context)
    if HolyStorm.Logger and HolyStorm.Logger.Write then HolyStorm.Logger:Write(level,"Rules",category,message,context) end
end

function Rules:RegisterOperator(id,definition,evaluator)
    if type(definition)=="function" and evaluator==nil then evaluator=definition;definition={} end
    if not validOperatorId(id) or type(definition)~="table" or type(evaluator)~="function" then return false,"INVALID_OPERATOR" end
    local normalized=copy(definition)
    normalized.id=id
    normalized.types=type(normalized.types)=="table" and copy(normalized.types) or {"any"}
    normalized.requiresValue=normalized.requiresValue~=false
    normalized.multiple=normalized.multiple==true
    self.operators[id]=evaluator
    self.operatorDefinitions[id]=normalized
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_RULE_OPERATOR_REGISTERED",id) end
    return true
end

function Rules:GetOperator(id)
    local definition=self.operatorDefinitions[id]
    return definition and copy(definition) or nil
end

function Rules:GetOperators()
    local result={}
    for id,definition in pairs(self.operatorDefinitions) do result[id]=copy(definition) end
    return result
end

local builtinOperators={
    ["="]={{"any"},function(a,b)return equals(a,b)end},
    ["!="]={{"any"},function(a,b)return not equals(a,b)end},
    [">"]={{"number"},function(a,b)return tonumber(a) and tonumber(b) and tonumber(a)>tonumber(b) or false end},
    [">="]={{"number"},function(a,b)return tonumber(a) and tonumber(b) and tonumber(a)>=tonumber(b) or false end},
    ["<"]={{"number"},function(a,b)return tonumber(a) and tonumber(b) and tonumber(a)<tonumber(b) or false end},
    ["<="]={{"number"},function(a,b)return tonumber(a) and tonumber(b) and tonumber(a)<=tonumber(b) or false end},
}
for id,entry in pairs(builtinOperators) do Rules:RegisterOperator(id,{types=entry[1]},entry[2]) end
Rules:RegisterOperator("between",{types={"number"},multiple=true,valueCount=2},function(a,b)
    local low,high=type(b)=="table" and tonumber(b[1]),type(b)=="table" and tonumber(b[2])
    return tonumber(a) and low and high and tonumber(a)>=low and tonumber(a)<=high or false
end)
Rules:RegisterOperator("not_between",{types={"number"},multiple=true,valueCount=2},function(a,b)return not Rules.operators.between(a,b)end)
Rules:RegisterOperator("contains",{types={"string"}},function(a,b)return lower(a):find(lower(b),1,true)~=nil end)
Rules:RegisterOperator("not_contains",{types={"string"}},function(a,b)return not Rules.operators.contains(a,b)end)
Rules:RegisterOperator("starts_with",{types={"string"}},function(a,b)return lower(a):sub(1,#lower(b))==lower(b)end)
Rules:RegisterOperator("ends_with",{types={"string"}},function(a,b)local x,y=lower(a),lower(b);return y==""or x:sub(-#y)==y end)
Rules:RegisterOperator("in",{types={"string","enum","character","account"},multiple=true},inList)
Rules:RegisterOperator("not_in",{types={"string","enum","character","account"},multiple=true},function(a,b)return not inList(a,b)end)
Rules:RegisterOperator("true",{types={"boolean"},requiresValue=false},function(a)return a==true end)
Rules:RegisterOperator("false",{types={"boolean"},requiresValue=false},function(a)return a==false end)
Rules:RegisterOperator("exists",{types={"any"},requiresValue=false},function(a)return a~=nil end)
Rules:RegisterOperator("not_exists",{types={"any"},requiresValue=false},function(a)return a==nil end)
Rules.operators.range=Rules.operators.between
Rules.operators.in_list=Rules.operators["in"]
Rules.operators.not_in_list=Rules.operators.not_in
Rules.operators.is_true=Rules.operators["true"]
Rules.operators.is_false=Rules.operators["false"]
Rules.operatorDefinitions.range=copy(Rules.operatorDefinitions.between);Rules.operatorDefinitions.range.id="range"
Rules.operatorDefinitions.in_list=copy(Rules.operatorDefinitions["in"]);Rules.operatorDefinitions.in_list.id="in_list"
Rules.operatorDefinitions.not_in_list=copy(Rules.operatorDefinitions.not_in);Rules.operatorDefinitions.not_in_list.id="not_in_list"
Rules.operatorDefinitions.is_true=copy(Rules.operatorDefinitions["true"]);Rules.operatorDefinitions.is_true.id="is_true"
Rules.operatorDefinitions.is_false=copy(Rules.operatorDefinitions["false"]);Rules.operatorDefinitions.is_false.id="is_false"

local defaultOperators = {
    boolean={"=","!=","true","false","exists","not_exists"},
    number={"=","!=",">",">=","<","<=","between","not_between","exists","not_exists"},
    string={"=","!=","contains","not_contains","starts_with","ends_with","in","not_in","exists","not_exists"},
}
defaultOperators.enum={"=","!=","in","not_in","exists","not_exists"}
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
        local operatorDefinition=type(operator)=="string"and Rules.operatorDefinitions[operator]
        local supported=false
        for _,kind in ipairs(operatorDefinition and operatorDefinition.types or{})do
            if kind=="any"or kind==definition.type or kind=="string"and(definition.type=="character"or definition.type=="account")then supported=true;break end
        end
        if supported and Rules.operators[operator] and not set[operator] then set[operator]=true;list[#list+1]=operator end
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
    normalized.name=definition.name or fieldID
    normalized.description=definition.description or normalized.name
    normalized.resolver=resolver
    normalized.get=normalized.resolver -- Compatibility for existing consumers.
    normalized.dependencies=type(definition.dependencies)=="table" and copy(definition.dependencies) or {}
    normalized.allowedOperators,normalized._allowedOperatorSet=normalizeAllowedOperators(normalized)
    if #normalized.allowedOperators==0 then return false,"INVALID_FIELD_OPERATORS" end
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

function Rules:GetFieldDiagnostics(context)
    local result={}
    for id,definition in pairs(self.fields) do
        local available,reason=self:GetFieldAvailability(id,context)
        result[#result+1]={id=id,name=definition.name,nameKey=definition.nameKey,description=definition.description,descriptionKey=definition.descriptionKey,owner=definition.owner,module=definition.module,type=definition.type,category=definition.category,operators=copy(definition.allowedOperators),available=available,reason=reason}
    end
    table.sort(result,function(a,b)return tostring(a.category or"")<tostring(b.category or"")or a.category==b.category and tostring(a.name or a.id)<tostring(b.name or b.id)end)
    return result
end

function Rules:GetFieldAvailability(fieldID,context,node)
    local field,resolvedID=self:_ResolveField(fieldID)
    if not field then return false,"UNKNOWN_FIELD:"..tostring(fieldID)end
    if not field.availability then return true end
    local resolverContext={}
    for key,value in pairs(context or{})do resolverContext[key]=value end
    resolverContext.accountUUID=resolverContext.accountUUID or resolverContext.playerId
    resolverContext.characterUUID=resolverContext.characterUUID or resolverContext.guid
    resolverContext.argument=node and(node.argument~=nil and node.argument or node.value)
    local ok,available,reason=HolyStorm.Utils.SafeCall("rule.availability:"..resolvedID,field.availability,resolverContext,node)
    if not ok then log("WARN","availability","Rule field availability failed",{field=fieldID,owner=field.owner,error=tostring(available)});return false,"AVAILABILITY_ERROR:"..fieldID end
    if not available then return false,reason or"FIELD_UNAVAILABLE:"..fieldID end
    return true
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
    local available,availabilityReason=self:GetFieldAvailability(fieldID,resolverContext,node)
    if not available then return nil,availabilityReason end
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
    local operatorDefinition=self.operatorDefinitions[operator]
    if (not operatorDefinition or operatorDefinition.requiresValue~=false) and node.value==nil then return false,"MISSING_VALUE" end
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
    if operatorDefinition and operatorDefinition.requiresValue~=false and field.type~="number" and field.type~="any" then
        local values=type(node.value)=="table"and node.value or{node.value}
        for _,value in ipairs(values)do if not valueMatchesType(field.type,value)then return false,"INVALID_VALUE_TYPE:"..field.type end end
        if field.type=="enum"and type(field.values)=="table"and#field.values>0 then
            for _,value in ipairs(values)do
                local found=false
                for _,candidate in ipairs(field.values)do local allowed=type(candidate)=="table"and(candidate.value~=nil and candidate.value or candidate.id)or candidate;if equals(value,allowed)then found=true;break end end
                if not found then return false,"INVALID_ENUM_VALUE:"..tostring(value)end
            end
        end
    end
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
    local function evaluate(current,depth)
        depth=depth or 0
        if current.logic then
            local logic=string.upper(current.logic);local status
            if logic=="NOT" then local child=evaluate(current.children[1],depth+1);status=child==PASS and FAIL or child==FAIL and PASS or UNKNOWN
            elseif logic=="OR" then status=FAIL;for _,childNode in ipairs(current.children) do local child=evaluate(childNode,depth+1);if child==PASS then status=PASS elseif child==UNKNOWN and status~=PASS then status=UNKNOWN end end
            else status=PASS;for _,childNode in ipairs(current.children) do local child=evaluate(childNode,depth+1);if child==FAIL then status=FAIL elseif child==UNKNOWN and status~=FAIL then status=UNKNOWN end end end
            trace[#trace+1]={kind="group",logic=logic,status=status,result=status==PASS,depth=depth};return status
        end
        local actual,reason=self:GetFieldValue(current.field,context,current)
        local status=reason and UNKNOWN or (self.operators[current.operator or "="](actual,current.value) and PASS or FAIL)
        local field=self:_ResolveField(current.field)
        trace[#trace+1]={kind="condition",field=current.field,operator=current.operator or "=",expected=copy(current.value),actual=copy(actual),status=status,result=status==PASS,error=reason,reason=reason,provider=field and field.owner,module=field and field.module,valueType=field and field.type,depth=depth}
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
