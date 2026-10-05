local root=(arg[0]:gsub("tools[/\\]test_character_scan_manager.lua$","")).."LIVE/Holy_Storm/"
local repository=arg[0]:gsub("tools[/\\]test_character_scan_manager.lua$","")
unpack=unpack or table.unpack
local queued,logs,listeners,emitted,startupMetrics={},{},{},{},{}
local clock=100000
function GetTime()return clock end
local HolyStorm={Utils={},Tasks={definitions={},tasks={}},Events={},PlayerData={},AddonLoader={}}
function HolyStorm:GetAddon()return self end
function LibStub(name)if name=="AceAddon-3.0"then return HolyStorm end;return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
function HolyStorm.Utils.DeepCopy(value)if type(value)~="table"then return value end;local out={};for key,child in pairs(value)do out[key]=HolyStorm.Utils.DeepCopy(child)end;return out end
function HolyStorm.Utils.TableCount(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end
function HolyStorm.Utils.Now()return clock end
function HolyStorm.Utils.SafeCall(_,callback,...)return pcall(callback,...)end
HolyStorm.Logger={Write=function(_,level,source,category,message,context)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context}end}
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.definitions[id]=definition end
function HolyStorm.Tasks:Queue(id,options)queued[#queued+1]={id=id,options=options};return"task-"..#queued,"QUEUED"end
function HolyStorm.Tasks:RecordStartupMetric(key,amount)startupMetrics[key]=(startupMetrics[key]or 0)+(amount or 1)end
function HolyStorm.Events:Register(event,_,callback)listeners[event]=callback end
function HolyStorm.Events:Emit(event,...)emitted[#emitted+1]={event=event,args={...}};if listeners[event]then listeners[event](event,...)end end
function HolyStorm.AddonLoader:GetCharacterDataDefinitions()return{{block="equipment",capability="character.scan.equipment",addonId="equipment",order=10},{block="mythicPlus",capability="character.scan.mythicplus",addonId="mythicPlus",order=20},{block="raid",capability="character.scan.raids",addonId="raids",order=30},{block="delves",capability="character.scan.delves",addonId="delves",order=40},{block="stats",capability="character.scan.stats",addonId="characters",order=50}}end
function UnitGUID()return"Player-Local"end
assert(loadfile(root.."Core/Tasks/CharacterScanManager.lua"))();local scans=HolyStorm.CharacterScans;scans:Initialize()
local initialMetrics=scans:GetRuntimeMetrics();for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats"})do assert(initialMetrics.byBlock[block]and initialMetrics.byBlock[block].requested==0,"zero-valued startup metrics expose the "..block.." producer")end
assert(not HolyStorm.Tasks.definitions["CharacterScan.InitialBootstrap"],"the delayed login bootstrap task is removed")
assert(HolyStorm.Tasks.definitions["CharacterScan.Advance"],"explicit and event-driven work keeps the shared serialized advance task")
local declarations=scans:GetDeclarations();assert(#declarations==5 and declarations[1].block=="equipment"and declarations[5].block=="stats"and declarations[3].addonId=="raids","manual scan declarations are discovered in producer order without loading the providers")
local before=#queued;listeners.PLAYER_LOGIN();assert(#queued==before and scans.loginSession==1 and scans:GetDiagnostics().loginProducerScans==0,"login resets transient scan diagnostics without queuing producer work")
assert(not scans.QueueBootstrapBlocks,"no callable missing/stale bootstrap path remains")

local started={}
for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats"})do local name=block;assert(scans:RegisterProvider(name,{block=name,capability="character.scan."..name,request=function(sync,reason,reasons)started[#started+1]={block=name,reason=reason,reasons=reasons};return"wf-"..name.."-"..#started end}))end
local function markStarted(taskId)local active=scans.active;assert(active,"test workflow is active before its first task");local id=taskId or active.workflowId;HolyStorm.Tasks.tasks[id]={executionDuration=.0015};HolyStorm.Events:Emit("HS_WORKFLOW_STARTED",{workflowId=active.workflowId});HolyStorm.Events:Emit("HS_TASK_STARTED",{workflowId=active.workflowId,uniqueId=id,registryId="Test.Task",workflowStep=1,executionDuration=.0015})end
assert(not scans:RegisterProvider("BadStatus",{block="bad",capability="character.scan.bad",request=function()return"wf-bad"end,status=true}),"status callback must be a function when declared")
HolyStorm.Data={CharacterStore={blocks={equipment={snapshotVersion=4},mythicPlus={snapshotVersion=5},raid={snapshotVersion=3},delves={snapshotVersion=3},stats={snapshotVersion=2}}}}
function HolyStorm.Data.CharacterStore:GetBlock(_,block)return self.blocks[block]end
local beforeLoginCases=#queued
for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats"})do local before=#queued;listeners.PLAYER_LOGIN();assert(#queued==before and not scans.pending[block]and not scans.active,"login with an existing "..block.." snapshot queues no producer")end
HolyStorm.Data.CharacterStore.blocks={}
for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats"})do local before=#queued;listeners.PLAYER_LOGIN();assert(#queued==before and not scans.pending[block]and not scans.active,"login with a missing "..block.." snapshot queues no producer")end
assert(#queued==beforeLoginCases and scans:GetDiagnostics().loginProducerScans==0,"neither a warm nor empty local cache causes login work or scan-all")

local beforeEvent=#queued;scans:Request("equipment","PLAYER_EQUIPMENT_CHANGED",true,{order=10});assert(#queued==beforeEvent+1 and queued[#queued].id=="CharacterScan.Advance"and scans:GetRuntimeState("Player-Local","equipment").state=="DIRTY","a relevant Blizzard event marks the block dirty and uses the central queue")
local activeRequest=scans.queue[1];assert(activeRequest.block=="equipment"and activeRequest.reason=="PLAYER_EQUIPMENT_CHANGED","event reason survives queuing")
local advanceOptions=queued[#queued].options;assert(advanceOptions.priority==30,"automatic event scans keep normal background priority")
assert(scans:Advance()and scans.active.block=="equipment"and scans:GetRuntimeState("Player-Local","equipment").state=="DIRTY"and started[1].reason=="PLAYER_EQUIPMENT_CHANGED","the accepted workflow stays DIRTY while its debounced first task has not started")
markStarted("task-equipment-first");assert(scans:GetRuntimeState("Player-Local","equipment").state=="REFRESHING","the actual first task start transitions the provider to REFRESHING")
local activeId=scans.active.workflowId
scans:Request("equipment","SOCKET_INFO_UPDATE",true,{order=10});scans:Request("mythicPlus","MANUAL",true,{order=20,manual=true});scans:Request("raid","ENCOUNTER_END",true,{order=30});scans:Request("raid","MANUAL_COMMAND",true,{order=30});assert(scans.active.workflowId==activeId and scans.pending.equipment.reasons.SOCKET_INFO_UPDATE and scans.pending.raid.reasons.ENCOUNTER_END and scans.pending.raid.reasons.MANUAL_COMMAND,"events and user requests merge without parallel scans")
assert(queued[#queued].options.priority==15,"an interactive request raises the shared advance task priority")
assert(scans:Finish({workflowId=activeId},"COMPLETED")and scans:GetRuntimeState("Player-Local","equipment").state=="DIRTY","an event received during a scan remains dirty until its queued follow-up starts")
assert(scans:Advance()and scans.active.block=="mythicPlus"and started[#started].reason=="MANUAL","manual Mythic+ scans stay serialized");markStarted("task-mythic-first")
assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"));assert(scans:Advance()and scans.active.block=="raid"and started[#started].reason=="ENCOUNTER_END"and started[#started].reasons.MANUAL_COMMAND,"a manual Raid request merges with the pending event");markStarted("task-raid-first")
assert(scans:Finish({workflowId=scans.active.workflowId,lastError="EXPECTED_DIAGNOSTIC"},"FAILED")and scans:GetRuntimeState("Player-Local","raid").state=="ERROR"and scans:GetRuntimeState("Player-Local","raid").lastError=="EXPECTED_DIAGNOSTIC","failed refresh retains its diagnostic in the ERROR runtime state")
assert(scans:Advance()and scans.active.block=="equipment"and started[#started].reason=="SOCKET_INFO_UPDATE","same-producer follow-up remains serialized after higher-priority blocks");markStarted("task-equipment-second")
assert(scans:GetRuntimeState("Player-Remote","raid")==nil,"local scan state is not exposed as a remote character state")
local producerMetrics=scans:GetRuntimeMetrics().byBlock;assert(producerMetrics.equipment.requested==2 and producerMetrics.equipment.automatic==2 and producerMetrics.equipment.started==2 and producerMetrics.equipment.completed==1,"accepted automatic producer workflows count as started and completed by block");assert(producerMetrics.mythicPlus.manual==1 and producerMetrics.mythicPlus.started==1 and producerMetrics.mythicPlus.completed==1 and producerMetrics.raid.manual==1 and producerMetrics.raid.started==1 and producerMetrics.raid.failed==1,"workflow failures are counted only after an accepted producer start")
 local activeBeforeReset,queuedBeforeReset=scans.active,#scans.queue;assert(scans:ResetRuntimeMetrics()and scans.active==activeBeforeReset and#scans.queue==queuedBeforeReset and scans:GetRuntimeMetrics().byBlock.equipment.requested==0 and scans:GetRuntimeMetrics().loginProducerScans==0,"producer metric reset preserves active/queued work while restoring visible zero rows")
local resetWorkflowId=scans.active.workflowId;assert(scans:Finish({workflowId=resetWorkflowId,lastError="RESET_WINDOW_FAILURE"},"FAILED"));local resetWindowMetrics=scans:GetRuntimeMetrics().byBlock.equipment;assert(resetWindowMetrics.started==0 and resetWindowMetrics.failedAfterStart==0 and resetWindowMetrics.failed==0,"an in-flight scan from before a metrics reset cannot create failed=1/started=0 in the new window")
scans:ResetRuntimeMetrics();assert(scans:Request("stats","DIAGNOSTIC_FAILURE",false));assert(scans:Advance());markStarted("task-stats-failure");local diagnosticWorkflow=scans.active.workflowId;assert(scans:Finish({workflowId=diagnosticWorkflow,lastError="SNAPSHOT_INVALID",failureContext={currentStepId="validate",failedTask="Snapshot.stats.Validate",candidateReason="STATS_UNAVAILABLE",retryCount=2,reason="SNAPSHOT_INVALID"}},"FAILED"));local statsFailure=scans:GetDiagnostics().runtimeStates.stats;assert(statsFailure.state=="ERROR"and statsFailure.lastFailureStage=="validate"and statsFailure.lastFailureDetail=="STATS_UNAVAILABLE"and statsFailure.retryCount==2,"terminal workflows retain their final stage, candidate reason, and retry count in producer runtime diagnostics")
local tileOk,tileCount=scans:RequestBlocks({"stats"},"MANUAL",true);assert(tileOk and tileCount==1 and scans.pending.stats and not scans.pending.equipment,"a single tile request remains limited to its one selected producer")
local allOk,allCount=scans:RequestAll("MANUAL",true);assert(allOk and allCount==5,"RequestAll targets every declaration")
for _,block in ipairs({"equipment","mythicPlus","raid","delves","stats"})do local request=scans.pending[block];assert(request and request.reason=="MANUAL"and request.sync and request.manual,"all producer requests remain explicit and manual regardless of cache freshness")end

scans.active=nil;scans.queue={};scans.pending={};scans:ResetRuntimeMetrics();for key in pairs(startupMetrics)do startupMetrics[key]=nil end;scans.providers.delves=nil
assert(scans:Request("delves","MANUAL_COMMAND",true,{manual=true})and scans:Advance()==false,"an unavailable Delves producer fails before creating a workflow")
local failedStart=scans:GetRuntimeMetrics().byBlock.delves;local delvesState=scans:GetDiagnostics().runtimeStates.delves
assert(failedStart.requested==1 and failedStart.started==0 and failedStart.failedAfterStart==0 and failedStart.failed==0 and failedStart.startFailure==1 and failedStart.admissionFailure==1 and failedStart.cancelled==0,"pre-start producer failures stay separate from scans that actually ran")
assert(delvesState.state=="ERROR"and delvesState.lastError=="PROVIDER_UNAVAILABLE"and delvesState.lastFailureStage=="ADMISSION"and startupMetrics.producerScanStartFailures==1 and not startupMetrics.producerScansFailed,"the pre-start reason and admission stage are preserved")

scans:ResetRuntimeMetrics();assert(scans:RegisterProvider("Delves",{block="delves",capability="character.scan.delves",request=function()return"wf-delves-cancel"end}));assert(scans:Request("delves","MANUAL_COMMAND",true,{manual=true})and scans:Advance()and scans.active.workflowId=="wf-delves-cancel","accepted Delves work records its queued workflow before cancellation")
assert(scans:Finish({workflowId="wf-delves-cancel"},"CANCELLED"));local cancelled=scans:GetRuntimeMetrics().byBlock.delves;assert(cancelled.started==0 and cancelled.cancelled==1 and cancelled.failedAfterStart==0 and cancelled.startFailure==0,"cancellation before the first task is not counted as a started scan")

scans:ResetRuntimeMetrics();assert(scans:Request("delves","METRICS_NOOP",false));clock=clock+1;assert(scans:Advance());markStarted("task-delves-noop");assert(scans:RecordSnapshotResult("delves","UNCHANGED"));clock=clock+2;assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"));local noOpMetrics=scans:GetRuntimeMetrics().byBlock.delves
assert(noOpMetrics.requested==1 and noOpMetrics.logicalScans==1 and noOpMetrics.started==1 and noOpMetrics.taskLifecycles==1 and noOpMetrics.completed==1 and noOpMetrics.commits==0 and noOpMetrics.noOpScans==1 and noOpMetrics.lastQueueWait==1 and noOpMetrics.lastDuration==2 and noOpMetrics.lastLuaMs==1.5 and noOpMetrics.totalLuaMs==1.5 and noOpMetrics.maxLuaMs==1.5 and noOpMetrics.maxTaskMs==1.5,"logical scan, task lifecycle, no-op, queue wait, wall time, and aggregated task Lua time are measured at their lifecycle boundaries")
scans:ResetRuntimeMetrics();assert(scans:Request("delves","METRICS_COMMIT",false));assert(scans:Advance());markStarted("task-delves-commit");assert(scans:RecordSnapshotResult("delves","COMMITTED"));assert(scans:Finish({workflowId=scans.active.workflowId},"COMPLETED"));local commitMetrics=scans:GetRuntimeMetrics().byBlock.delves;assert(commitMetrics.commits==1 and commitMetrics.noOpScans==0,"a validated authoritative write is distinguished from an unchanged scan")
scans:RecordFailure("delves","DELVES_API_NOT_READY","SEASON",2,{api="C_DelvesUI.GetCurrentDelvesSeasonNumber",cause="API_ERROR",error="season API delayed"});local apiFailure=scans:GetDiagnostics().runtimeStates.delves;assert(apiFailure.lastFailureDetail=="API_ERROR: season API delayed","the Developer diagnostic retains a concise Blizzard API error detail")

local contracts={
 {path="LIVE/Holy_Storm_Equipment/Equipment.lua",events={"PLAYER_EQUIPMENT_CHANGED","UNIT_INVENTORY_CHANGED","SOCKET_INFO_SUCCESS"},absentEvents={"SOCKET_INFO_UPDATE"}},
 {path="LIVE/Holy_Storm_Raids/Raids.lua",events={"UPDATE_INSTANCE_INFO","ENCOUNTER_END"}},
 {path="LIVE/Holy_Storm_MythicPlus/MythicPlus.lua",events={"CHALLENGE_MODE_COMPLETED","MYTHIC_PLUS_NEW_WEEKLY_RECORD","WEEKLY_REWARDS_UPDATE"}},
 {path="LIVE/Holy_Storm_Delves/Delves.lua",events={"WEEKLY_REWARDS_UPDATE"}},
}
for _,contract in ipairs(contracts)do local file=assert(io.open(repository..contract.path,"rb"));local source=file:read("*a");file:close();assert(source:find("CharacterScans:Request",1,true),contract.path.." routes refreshes through the serialized manager");for _,event in ipairs(contract.events)do assert(source:find(event,1,true),contract.path.." keeps the verified relevant trigger "..event)end;for _,event in ipairs(contract.absentEvents or{})do assert(not source:find(event,1,true),contract.path.." excludes non-change event "..event)end end
local statsFile=assert(io.open(repository.."LIVE/Holy_Storm_Characters/Stats.lua","rb"));local stats=statsFile:read("*a");statsFile:close();assert(not stats:find('"PLAYER_ENTERING_WORLD"',1,true)and not stats:find('metadata.snapshotVersion',1,true),"Stats does not create login/missing-baseline scans")
local characterManagerFile=assert(io.open(repository.."LIVE/Holy_Storm/Core/Tasks/CharacterScanManager.lua","rb"));local managerSource=characterManagerFile:read("*a");characterManagerFile:close();assert(not managerSource:find("INITIAL_MISSING_BLOCK",1,true)and not managerSource:find("INITIAL_STALE_BLOCK",1,true)and not managerSource:find("CharacterStore",1,true)and not managerSource:find("staleAfter",1,true),"the central scan manager does not inspect persisted presence/age to synthesize producer work")
print("Cache-first login, central serialization, event routing, admission, cancellation, and transient producer-state tests passed")
