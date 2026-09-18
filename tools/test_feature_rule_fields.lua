-- Contract checks for the owner-based rule-field registry and optional modules.
local root=(arg[0]:gsub("tools[/\\]test_feature_rule_fields.lua$",""))
local function read(path)local f=assert(io.open(root..path,"r"));local value=f:read("*a");f:close();return value end
local function copy(value,seen)if type(value)~="table"then return value end;seen=seen or{};if seen[value]then return seen[value]end;local out={};seen[value]=out;for key,child in pairs(value)do out[copy(key,seen)]=copy(child,seen)end;return out end
local logs,events={},{}
local HolyStorm={Utils={DeepCopy=copy,SafeCall=function(_,fn,...)return pcall(fn,...)end},Logger={Write=function(_,level,module,category,message,context)logs[#logs+1]={level=level,module=module,category=category,message=message,context=context}end},Events={Emit=function(_,event)events[#events+1]=event end},db={global={rules={global={}},filters={global={},demands={}}},profile={rules={localRules={}},filters={localFilters={}}}}}
function LibStub()return{GetAddon=function()return HolyStorm end}end
assert(loadfile(root.."LIVE/Holy_Storm/Core/Permissions/RuleEngine.lua"))()
local Rules=HolyStorm.Rules

-- The compatibility refresh API only requests provider work; core remains read-only.
HolyStorm.db.global.filters.demands={sentinel=true};Rules:RebuildDemands();assert(HolyStorm.db.global.filters.demands.sentinel==true and events[#events]=="HS_RULE_DEMANDS_REBUILD_REQUESTED")

-- A/E: a module can register and evaluate a known field.
assert(Rules:RegisterField("module-a","example.score",{type="number",name="Score",description="Stored score",category="Example",dependencies={"example"},resolver=function(context)return context.score end}))
local pass,_,passStatus=Rules:Evaluate({field="example.score",operator=">=",value=10},{score=12});assert(pass and passStatus==Rules.Result.PASS)
local fail,_,failStatus=Rules:Evaluate({field="example.score",operator=">=",value=10},{score=2});assert(not fail and failStatus==Rules.Result.FAIL)
assert(Rules:GetField("example.score").owner=="module-a" and Rules:GetFieldsByOwner("module-a")["example.score"])

-- B/C/J: unknown optional fields are structurally valid, portable and UNKNOWN.
local storedFilter={id="optional-filter",name="Optional",root={field="optional.notLoaded",operator=">=",value=5}}
assert(Rules:Validate(storedFilter.root));assert(Rules:ValidatePortable(storedFilter.root));local persisted=copy(storedFilter);assert(persisted.root.field=="optional.notLoaded")
local unknown,trace,unknownStatus=Rules:Evaluate(storedFilter.root,{});assert(not unknown and unknownStatus==Rules.Result.UNKNOWN and trace[1].error:match("UNKNOWN_FIELD"))

-- D: malformed structure is still rejected independently of field availability.
assert(not Rules:Validate({logic="NOT",children={{field="optional.notLoaded",operator="exists"},{field="other",operator="exists"}}}))
assert(not Rules:Validate({field="bad field",operator="=" ,value=1}))

-- F/G: owners are independent and cleanup removes only one owner's fields/aliases.
assert(Rules:RegisterField("module-b","example.flag",{type="boolean",resolver=function()return true end}))
assert(not Rules:RegisterField("module-b","example.invalidOperators",{type="number",allowedOperators={"contains"},resolver=function()return 1 end}))
assert(Rules:RegisterAlias("module-a","legacyScore","example.score"));assert(Rules:GetField("legacyScore").aliasOf=="example.score")
assert(Rules:UnregisterOwner("module-a")==2);assert(not Rules:GetField("example.score")and not Rules:GetField("legacyScore"));assert(Rules:GetField("example.flag"))

-- H: resolver and availability errors degrade to UNKNOWN and are logged.
assert(Rules:RegisterField("module-errors","example.error",{type="number",resolver=function()error("boom")end}))
local _,_,errorStatus=Rules:Evaluate({field="example.error",operator=">",value=1},{});assert(errorStatus==Rules.Result.UNKNOWN and #logs>0)
assert(Rules:RegisterField("module-errors","example.unavailable",{type="number",availability=function()return false,"NOT_READY"end,resolver=function()return 5 end}))
local _,availabilityReason=Rules:GetFieldValue("example.unavailable",{});assert(availabilityReason=="NOT_READY")
local availabilityDiagnostics=Rules:GetFieldDiagnostics({});local unavailableDiagnostic;for _,entry in ipairs(availabilityDiagnostics)do if entry.id=="example.unavailable"then unavailableDiagnostic=entry end end;assert(unavailableDiagnostic and not unavailableDiagnostic.available and unavailableDiagnostic.reason=="NOT_READY")

-- I: Kleene-style AND/OR/NOT semantics preserve or short-circuit UNKNOWN correctly.
local unknownNode={field="optional.missing",operator="exists"}
local trueNode={field="example.flag",operator="true"}
local falseNode={field="example.flag",operator="false"}
assert(Rules:EvaluateDetailed({logic="AND",children={unknownNode,falseNode}},{})==Rules.Result.FAIL)
assert(Rules:EvaluateDetailed({logic="OR",children={unknownNode,trueNode}},{})==Rules.Result.PASS)
assert(Rules:EvaluateDetailed({logic="NOT",children={unknownNode}},{})==Rules.Result.UNKNOWN)

-- K: feature declarations live in modules; the core has no feature IDs or scans.
for _,entry in ipairs({
 {"Modules/Equipment/Equipment.lua","equipment.itemLevel"},{"Modules/MythicPlus/MythicPlus.lua","mythicplus.rating"},
 {"Modules/Raids/Raids.lua","raid.progress"},{"Modules/Delves/Delves.lua","delves.status"},
})do local source=read("LIVE/Holy_Storm/"..entry[1]);assert(source:find('id="'..entry[2]..'"',1,true),"missing module field: "..entry[2])end
local core=read("LIVE/Holy_Storm/Core/Permissions/RuleEngine.lua")
for _,term in ipairs({"equipment.itemLevel","mythicplus.rating","raid.progress","delves.status","quest.completed","achievement.completed","C_QuestLog","GetAchievementInfo","CharacterStore"})do assert(not core:find(term,1,true),"core feature coupling: "..term)end
local demandProvider=read("LIVE/Holy_Storm/Modules/Characters/RuleDataProvider.lua");assert(demandProvider:find("CharacterRuleData.RebuildDemands",1,true)and demandProvider:find("CharacterRuleData.Capture",1,true)and demandProvider:find("CharacterStore:Upsert",1,true),"demand acquisition must be task/store owned")
print("Rule registry ownership, portability, UNKNOWN behavior and module decoupling passed")
