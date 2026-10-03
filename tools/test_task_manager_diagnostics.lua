local script=arg[0]:gsub("\\","/")
local workspace=script:match("^(.*)/tools/[^/]+$")or"."
local modules={}
local locale=setmetatable({},{__index=function(_,key)return key end})
local HolyStorm={}
function HolyStorm:GetAddon()return self end
function HolyStorm:RegisterRequiredModule(name)local module={};modules[name]=module;return module end
function HolyStorm:ApplyModuleMetadata()end
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;return HolyStorm end

assert(loadfile(workspace.."/LIVE/Holy_Storm_UI/UI/Pages/TaskManager.lua"))()

local longIdentifier=string.rep("character/object/0123456789abcdef",100)
local taskMetrics={scheduler={wakeRequested=0,runs=0,coalescedWakes=0,budgetExhaustions=0,queueScans=0,queueChecks=0,tasksSelected=0,idleTransitions=0},tasks={byModule={},byTrigger={}}}
local workflowMetrics={byModule={},byTrigger={}}
HolyStorm.Tasks={
 GetRuntimeMetrics=function()return taskMetrics end,
 GetStartupMetrics=function()return{}end,
 GetLiveTasks=function()return{}end,
 IsIdle=function()return false end,
 GetPerformance=function()return{}end,
}
HolyStorm.Workflows={
 GetRuntimeMetrics=function()return workflowMetrics end,
 GetLive=function()return{}end,
 IsIdle=function()return true end,
 GetPerformance=function()return{}end,
}
HolyStorm.Sync={
 GetRuntimeMetrics=function()return{active=true,queued=2}end,
 GetDiagnostics=function()return{
  activeTransfer={characterUUID=longIdentifier,domain="character",direction="SEND",phase="TRANSFER"},
  catchUpQueued=17,pendingPayloads=3,
  transport={backend="test-backend",queued=4,lastFailure=longIdentifier},
 }end,
}
HolyStorm.CharacterScans={
 GetRuntimeMetrics=function()return{byBlock={delves={requested=1,automatic=1,manual=0,completed=0,failed=1,triggers={}}},loginProducerScans=0}end,
 GetDiagnostics=function()return{runtimeStates={delves={lastError="DELVES_WORLD_ACTIVITIES_UNAVAILABLE"}}}end,
 IsIdle=function()return true end,
}

local page=modules.TaskManagerUI
page.view="PERFORMANCE"
page.search={GetText=function()return""end}
page.moduleFilter={GetText=function()return""end}
page.workflowFilter={GetText=function()return""end}
local rows=page:BuildData()
local syncRow,delvesRow
for _,row in ipairs(rows)do
 if row.name=="SYNC_ACTIVITY"then syncRow=row end
 if row.name=="PRODUCER_SCANS PRODUCER_DELVES"then delvesRow=row end
end
assert(syncRow and syncRow.details:find("SYNC_DIAGNOSTIC_ACTIVE_TRANSFER",1,true),"active transfer diagnostics should be visible")
assert(syncRow.details:find("SYNC_DIAGNOSTIC_CATCHUP: 17",1,true),"catch-up count should be visible")
assert(syncRow.details:find("SYNC_DIAGNOSTIC_PENDING_PAYLOADS: 3",1,true),"pending payload count should be visible")
assert(syncRow.details:find("test-backend",1,true),"transport diagnostics should be visible")
assert(#syncRow.details<1800,"long transfer and transport identifiers must be bounded in the details layout")
assert(not syncRow.details:find(longIdentifier,1,true),"complete long identifiers must not be emitted")
assert(syncRow.details:find("...",1,true),"long diagnostic values should be visibly truncated")
assert(delvesRow and delvesRow.details:find("DELVES_WORLD_ACTIVITIES_UNAVAILABLE",1,true),"Delves last error should be exposed")

print("TaskManager sync and Delves diagnostics are visible and bounded")
