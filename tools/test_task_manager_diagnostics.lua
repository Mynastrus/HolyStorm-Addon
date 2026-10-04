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
local delvesLastError="PROVIDER_UNAVAILABLE"
local delvesRuntimeState={state="ERROR",reason="MANUAL_COMMAND",lastError=delvesLastError,lastFailureStage="ADMISSION"}
local taskMetrics={scheduler={wakeRequested=0,runs=0,coalescedWakes=0,budgetExhaustions=0,queueScans=0,queueChecks=0,tasksSelected=0,idleTransitions=0},tasks={byModule={},byTrigger={}}}
local raidPerformance={runs=115,totalDuration=.2,totalElapsed=2.5,totalQueueWait=2.3,averageQueueWait=.02,maxQueueWait=.04,averageDuration=.0017,maxDuration=.006,module="Raids"}
local workflowMetrics={byModule={},byTrigger={}}
HolyStorm.Tasks={
 GetRuntimeMetrics=function()return taskMetrics end,
 GetStartupMetrics=function()return{}end,
 GetLiveTasks=function()return{}end,
 IsIdle=function()return false end,
 GetPerformance=function()return{["Snapshot.raids.Scan"]=raidPerformance}end,
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
 GetRuntimeMetrics=function()return{byBlock={delves={requested=1,automatic=0,manual=1,started=0,completed=0,failed=0,failedAfterStart=0,startFailed=1,startFailure=1,admissionFailure=1,cancelled=0,retryCount=0,triggers={}}},loginProducerScans=0}end,
 GetDiagnostics=function()delvesRuntimeState.lastError=delvesLastError;return{runtimeStates={delves=delvesRuntimeState}}end,
 IsIdle=function()return true end,
}

function HolyStorm:GetLoadedModuleById(id)
 if id~="raids"then return end
 return{GetScanPerformance=function()return{totalWallMs=1000,totalLuaMs=12,slices=57,maxSliceMs=.6,taskLifecycleCount=3,catalogBuilds=1,ejCalls=18,statisticCalls=22,savedInstanceCalls=17,restarts=0,followUpQueued=1,expectedInstanceInfoEvents=1,unexpectedRaidEvents=8,status="COMPLETED"}end}
end
local page=modules.TaskManagerUI
page.view="PERFORMANCE"
page.search={GetText=function()return""end}
page.moduleFilter={GetText=function()return""end}
page.workflowFilter={GetText=function()return""end}
local rows=page:BuildData()
local syncRow,delvesRow,delvesRuntimeRow,raidPerformanceRow
for _,row in ipairs(rows)do
 if row.name=="SYNC_ACTIVITY"then syncRow=row end
 if row.name=="PRODUCER_SCANS PRODUCER_DELVES"then delvesRow=row end
 if row.name=="PRODUCER_DELVES_RUNTIME"then delvesRuntimeRow=row end
 if row.name=="Snapshot.raids.Scan"then raidPerformanceRow=row end
end
assert(syncRow and syncRow.details:find("SYNC_DIAGNOSTIC_ACTIVE_TRANSFER",1,true),"active transfer diagnostics should be visible")
assert(syncRow.details:find("SYNC_DIAGNOSTIC_CATCHUP: 17",1,true),"catch-up count should be visible")
assert(syncRow.details:find("SYNC_DIAGNOSTIC_PENDING_PAYLOADS: 3",1,true),"pending payload count should be visible")
assert(syncRow.details:find("test-backend",1,true),"transport diagnostics should be visible")
assert(#syncRow.details<1800,"long transfer and transport identifiers must be bounded in the details layout")
assert(not syncRow.details:find(longIdentifier,1,true),"complete long identifiers must not be emitted")
assert(syncRow.details:find("...",1,true),"long diagnostic values should be visibly truncated")
assert(delvesRow and delvesRow.started==0 and delvesRow.failed==0 and delvesRow.details:find("METRIC_FAILED_AFTER_START: 0",1,true)and delvesRow.details:find("METRIC_START_FAILURES: 1",1,true),"pre-start Delves errors must not be counted as a failed running scan")
assert(delvesRow.details:find("PROVIDER_UNAVAILABLE",1,true),"Delves admission reason is exposed in Producer scan details")
assert(delvesRuntimeRow and delvesRuntimeRow.details:find("ADMISSION",1,true),"Delves runtime diagnostics expose the preflight failure stage")
assert(raidPerformanceRow and raidPerformanceRow.details:find("METRIC_RUNS: 115",1,true)and raidPerformanceRow.details:find("METRIC_TOTAL_EXECUTION: 0.200s",1,true)and raidPerformanceRow.details:find("METRIC_TOTAL_ELAPSED: 2.500s",1,true)and raidPerformanceRow.details:find("METRIC_TOTAL_QUEUE_WAIT: 2.300s",1,true)and raidPerformanceRow.details:find("METRIC_MAX_QUEUE_WAIT: 0.040s",1,true)and raidPerformanceRow.details:find("METRIC_MAXIMUM: 0.006s",1,true),"Raid scheduler steps, total elapsed/runtime, queue wait and longest step are visible in Developer performance details")

page.detail={SetText=function(self,value)self.text=value end};page.data=rows;page.selected=delvesRow
local selectedBeforeRefresh=delvesRow;delvesLastError="DELVES_API_NOT_READY";delvesRuntimeState.lastFailureStage="SEASON";delvesRuntimeState.lastFailureAPI="C_DelvesUI.GetCurrentDelvesSeasonNumber";delvesRuntimeState.lastFailureDetail="NOT_READY";delvesRuntimeState.retryCount=3;local refreshedRows=page:BuildData();page.data=refreshedRows;page:ShowDetails(selectedBeforeRefresh)
assert(page.selected~=selectedBeforeRefresh and page.detail.text:find("DELVES_API_NOT_READY",1,true),"refreshing a selected Producer row replaces stale data with the latest exact error")
local refreshedRuntimeRow;for _,row in ipairs(refreshedRows)do if row.name=="PRODUCER_DELVES_RUNTIME"then refreshedRuntimeRow=row end end;page:ShowDetails(refreshedRuntimeRow)
assert(page.detail.text:find("SEASON",1,true)and page.detail.text:find("C_DelvesUI.GetCurrentDelvesSeasonNumber",1,true)and page.detail.text:find("NOT_READY",1,true)and page.detail.text:find("3",1,true),"Delves runtime details expose the exact terminal stage, API, cause, and retry count: "..tostring(page.detail.text))

local raidSummaryRow
for _,row in ipairs(rows)do if row.name=="RAID_SCAN_PERFORMANCE"then raidSummaryRow=row end end
assert(raidSummaryRow and raidSummaryRow.module=="Raid")
for _,key in ipairs({"totalWallMs","totalLuaMs","slices","maxSliceMs","taskLifecycleCount","catalogBuilds","ejCalls","statisticCalls","savedInstanceCalls","restarts","followUpQueued","expectedInstanceInfoEvents","unexpectedRaidEvents"})do assert(raidSummaryRow.details:find(key.."=",1,true),"Raid summary misses "..key)end
print("TaskManager existing diagnostics and the completed Raid summary are visible and bounded")
