-- Static contracts for the central rule/filter administration integration.
local root=(arg[0]:gsub("tools[/\\]test_rule_filter_administration.lua$",""))
local addon=root.."LIVE/Holy_Storm/"
local function read(path)local file=assert(io.open(addon..path,"rb"));local text=file:read("*a");file:close();return text end
local function readUI(path)local file=assert(io.open(root.."LIVE/Holy_Storm_UI/"..path,"rb"));local text=file:read("*a");file:close();return text end

local ruleEngine=read("Core/Permissions/RuleEngine.lua")
local filters=read("Core/Permissions/FilterManager.lua")
local state=read("Core/Permissions/PolicyState.lua")
local policyUI=readUI("UI/Framework/Components/PolicyUI.lua")
local filterUI=readUI("UI/Administration/Filters.lua")
local ruleUI=readUI("UI/Administration/Rules.lua")
local moduleRegistry=read("Core/Registry/ModuleRegistry.lua")
local toc=read("Holy_Storm.toc")

-- One central engine of each kind; UI coordinates their public contracts only.
local _,ruleEngineCount=toc:gsub("Core\\Permissions\\RuleEngine%.lua","")
local _,filterEngineCount=toc:gsub("Core\\Permissions\\FilterManager%.lua","")
assert(ruleEngineCount==1,"TOC must load exactly one RuleEngine")
assert(filterEngineCount==1,"TOC must load exactly one FilterManager")
assert(not filterUI:find("function%s+.-Evaluate")and not ruleUI:find("function%s+.-Evaluate"),"administration must not implement an evaluator")
assert(filterUI:find("Filters:Preview",1,true)and ruleUI:find("Filters:Preview",1,true),"administration preview must use FilterManager")

-- Rule fields remain provider-owned and never become a static feature list in Core/UI.
for _,featureField in ipairs({"equipment.itemLevel","mythicplus.rating","raid.progress","delves.status","quest.completed","achievement.completed"})do
    assert(not ruleEngine:find(featureField,1,true),"RuleEngine hardcodes feature field "..featureField)
    assert(not policyUI:find(featureField,1,true)and not filterUI:find(featureField,1,true)and not ruleUI:find(featureField,1,true),"UI hardcodes feature field "..featureField)
end
for _,contract in ipairs({"RegisterField","GetFieldDiagnostics","RegisterOperator","GetOperators","EvaluateDetailed","Result = { PASS=\"PASS\", FAIL=\"FAIL\", UNKNOWN=\"UNKNOWN\" }"})do assert(ruleEngine:find(contract,1,true),"RuleEngine contract missing: "..contract)end

-- Filter objects, references, duplication and previews stay in the existing manager/state chain.
for _,contract in ipairs({"RegisterReferenceProvider","GetReferences","DuplicateFilter","DuplicateRule","Preview","FILTER_IN_USE","RULE_IN_USE"})do assert(filters:find(contract,1,true),"FilterManager contract missing: "..contract)end
for _,action in ipairs({"FILTER_UPSERT","FILTER_DELETE","RULE_UPSERT","RULE_DELETE"})do assert(state:find(action,1,true),"PolicyState action missing: "..action)end
assert(moduleRegistry:find("Rules:UnregisterOwner",1,true)and moduleRegistry:find("HS_MODULE_AVAILABILITY_CHANGED",1,true),"module lifecycle must refresh the field registry")

-- Editor supports full existing tree semantics, typed values and deterministic movement controls.
for _,contract in ipairs({"ADD_CONDITION","ADD_AND_GROUP","ADD_OR_GROUP","LOGIC_NOT","MoveSelected","IndentSelected","OutdentSelected","CreateMultiSelector","FieldValueItems"})do assert(policyUI:find(contract,1,true),"rule builder contract missing: "..contract)end
for _,event in ipairs({"HS_RULE_FIELD_REGISTERED","HS_RULE_FIELD_UNREGISTERED","HS_MODULE_AVAILABILITY_CHANGED","HS_CHARACTER_UPDATED","HS_GROUP_UPDATED"})do assert(filterUI:find(event,1,true)or ruleUI:find(event,1,true),"administration refresh event missing: "..event)end

-- UI never bypasses manager/state persistence and forbidden basic-access permissions stay absent.
local uiSource=policyUI..filterUI..ruleUI
assert(not uiSource:find("HolyStorm.db",1,true)and not uiSource:find("Database:GetRoot",1,true),"rule/filter UI bypasses persistence APIs")
for _,permission in ipairs({"view-character-overview","share-equipment","share-raids","share-mythicplus","view-player-data"})do
    local all=ruleEngine..filters..state..uiSource
    assert(not all:find(permission,1,true),"forbidden basic-access permission found: "..permission)
end

-- Every newly visible administration label exists in both locales.
for _,locale in ipairs({"enUS","deDE"})do
    local source=readUI("UI/Administration/Locales/"..locale..".lua")
    for _,key in ipairs({"REFERENCES","NO_REFERENCES","EMPTY_FILTERS","EMPTY_RULES","EMPTY_FIELDS","EMPTY_PREVIEW_ENTITIES","FIELD_PROVIDERS","RESULT_PASS","RESULT_FAIL","RESULT_UNKNOWN","TRACE_CONDITION","TRACE_REASON","ADD_AND_GROUP","ADD_OR_GROUP","MOVE_UP","MOVE_DOWN","INDENT","OUTDENT","CONFIRM_FILTER_DELETE","CONFIRM_RULE_DELETE"})do
        assert(source:find('L["'..key..'"]',1,true),locale.." is missing "..key)
    end
end

print("Rule/filter administration architecture, lifecycle, UI and localization contracts passed")
