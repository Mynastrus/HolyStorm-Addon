-- Reproduces the full-tree fingerprint pass that the character producers do
-- not use. Counts are deterministic; wall-clock timing is intentionally not
-- treated as a Retail Lua performance result.
local root=(arg[0]:gsub("tools[/\\]test_snapshot_fingerprint_budget.lua$","")).."LIVE/Holy_Storm/"
local tasks={}
local HolyStorm={Tasks={},Workflows={workflows={}},PlayerData={},Utils={}}
function LibStub(name)
 if name=="AceAddon-3.0"then return{GetAddon=function()return HolyStorm end}end
 if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
 error("Unexpected library: "..tostring(name))
end
function HolyStorm.Tasks:RegisterTaskType(id,definition)tasks[id]=definition;return true end
function HolyStorm.Workflows:Register(id,definition)self.definition=definition;return true end
assert(loadfile(root.."Core/Serialization/Serializer.lua"))()
local measured={calls=0,tableNodes=0,serializedBytes=0}
local function countTables(value)
 if type(value)~="table"then return 0 end
 local count=1;for _,child in pairs(value)do count=count+countTables(child)end;return count
end
function HolyStorm.PlayerData:FingerprintSnapshot(value)
 measured.calls=measured.calls+1;measured.tableNodes=measured.tableNodes+countTables(value)
 local serialized,reason=HolyStorm.Serializer:Serialize(value);assert(serialized,reason)
 measured.serializedBytes=measured.serializedBytes+#serialized;return serialized
end
assert(loadfile(root.."Persistence/SnapshotManager.lua"))()
assert(HolyStorm.Snapshots:Register("budget"))

local fixture={snapshotVersion=1,characters={}}
for index=1,500 do
 fixture.characters[string.format("Character-%04d",index)]={
  equipment={itemLevel=700+index%100,slots={head="item:"..index,chest="item:"..(index+1)}},
  achievements={points=index%1000,earned={index,index+1,index+2}},
  identity={class="PALADIN",level=80,realm="Norgannon"},
 }
end
local fixtureTables=countTables(fixture)
local function validateWithFingerprint(enabled)
 measured={calls=0,tableNodes=0,serializedBytes=0}
 HolyStorm.Workflows.workflows.budget={context={
  data={validator=function()return true end,options={fingerprint=enabled}},
  results={scan={snapshot=fixture}},retryCounts={},
 }}
 local result=tasks["Snapshot.budget.Validate"].execute({workflowId="budget",metadata={stepId="validate"},retryCount=0})
 assert(result.valid==true)
 return{calls=measured.calls,tableNodes=measured.tableNodes,serializedBytes=measured.serializedBytes}
end

local before=validateWithFingerprint(true)
local after=validateWithFingerprint(false)
assert(before.calls==1 and before.tableNodes==fixtureTables and before.serializedBytes>0,"legacy/default mode performs one complete fingerprint traversal")
assert(after.calls==0 and after.tableNodes==0 and after.serializedBytes==0,"disabled fingerprint mode performs no extra snapshot traversal")
print(string.format("Snapshot fingerprint budget: before=%d table nodes, 1 serializer pass, %d encoded bytes; after=0 extra nodes, 0 extra passes, 0 bytes (fixture tables=%d)",before.tableNodes,before.serializedBytes,fixtureTables))
