-- Contract checks for module-owned rule fields and deferred field availability.
local root=(arg[0]:gsub("tools[/\\]test_feature_rule_fields.lua$",""))
local function read(path)local f=assert(io.open(root..path,"r"));local s=f:read("*a");f:close();return s end
local function copy(value)if type(value)~="table"then return value end;local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out end
local HolyStorm={Utils={DeepCopy=copy,SafeCall=function(_,fn,...)return pcall(fn,...)end},Logger={Write=function()end},Events={Emit=function()end},db={global={rules={global={}},filters={global={}}}}}
function LibStub()return{GetAddon=function()return HolyStorm end}end
assert(loadfile(root.."LIVE/Holy_Storm/Core/Permissions/RuleEngine.lua"))()
HolyStorm.Rules.fields={}
assert(not HolyStorm.Rules:GetFields()["equipment.itemLevel"])
local stored={field="equipment.itemLevel",operator=">=",value=700}
local status=HolyStorm.Rules:Evaluate(stored,{characterUUID="Player-1"});assert(status==false)
assert(HolyStorm.Rules:GetFieldValue(stored.field,{characterUUID="Player-1"})==nil)
assert(HolyStorm.Rules:RegisterField("equipment.itemLevel",{type="number",dependencies={"equipment"},get=function(c)return c.character and c.character.equipmentLevel end}))
local pass=HolyStorm.Rules:Evaluate(stored,{characterUUID="Player-1",character={equipmentLevel=710}});assert(pass==true)
local fail=HolyStorm.Rules:Evaluate(stored,{characterUUID="Player-1",character={equipmentLevel=650}});assert(fail==false)
local unknown=HolyStorm.Rules:Evaluate({field="not.loaded.field",operator="exists"},{characterUUID="Player-1"});assert(unknown==false)
for _,entry in ipairs({
 {"Modules/Equipment/Equipment.lua","equipment.itemLevel"},{"Modules/MythicPlus/MythicPlus.lua","mythicplus.rating"},
 {"Modules/Raids/Raids.lua","raid.progress"},{"Modules/Delves/Delves.lua","delves.status"},
})do local source=read("LIVE/Holy_Storm/"..entry[1]);assert(source:find('RegisterField("'..entry[2]..'"',1,true),"missing provider: "..entry[2])end
local core=read("LIVE/Holy_Storm/Core/Permissions/RuleEngine.lua");assert(not core:find('mythicPlus and x%.character',1,false));assert(not core:find('raidLockouts',1,true));assert(not core:find('weeklyProgress',1,true))
print("Feature rule field ownership and deferred evaluation passed")
