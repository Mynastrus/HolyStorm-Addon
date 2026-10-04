-- Regression coverage for Sync activity ownership, terminal paths and reconciliation.
local clock=5000
local root=(arg[0]:gsub("tools[/\\]test_sync_activity.lua$","")).."LIVE/Holy_Storm/"
local timers,names,metadata={}, {}, {}
unpack=unpack or table.unpack

function UnitGUID()return"Player-Local"end
function GetUnitName()return"Local-Realm"end
function IsInGuild()return true end
C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback,cancelled=false};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}

local HolyStorm={
 version="3.5.0",
 Events={listeners={},emitted={}},Logger={history={}},Tasks={types={},queue={},sequence=0},
 Serializer={},PlayerData={},Data={GuildStore={}},Utils={},
}
function HolyStorm:GetAddon()return self end
function HolyStorm.Events:Register(event,owner,fn)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=fn end
function HolyStorm.Events:Emit(event,...)
 self.emitted[#self.emitted+1]=event
 for _,fn in pairs(self.listeners[event]or{})do fn(event,...)end
end
function HolyStorm.Logger:Write(level,source,category,message,context)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.types[id]=definition end
function HolyStorm.Tasks:GetTaskType(id)return self.types[id]end
function HolyStorm.Tasks:Queue(id,options)self.sequence=self.sequence+1;self.queue[#self.queue+1]={id=id,options=options or{}};return"task-"..self.sequence end
function HolyStorm.Tasks:Cancel()return true end
function HolyStorm.Utils.Now()return clock end
function HolyStorm.Utils.DeepCopy(value)if type(value)~="table"then return value end;local out={};for key,child in pairs(value)do out[key]=HolyStorm.Utils.DeepCopy(child)end;return out end
function HolyStorm.Utils.TableCount(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end
function HolyStorm.Utils.SafeCall(_,fn,...)local values={pcall(fn,...)};if not values[1]then return false,values[2]end;table.remove(values,1);return true,unpack(values)end
function HolyStorm.Data.GuildStore:ResolveSenderGuid(sender,claimed)return names[sender]or claimed end
function HolyStorm.Data.GuildStore:NormalizeSenderName(sender)return sender end
function HolyStorm.PlayerData:CompareMetadata(localMeta,remoteMeta)
 if not localMeta then return 1,"MISSING"end
 local localVersion,remoteVersion=tonumber(localMeta.version)or-1,tonumber(remoteMeta.version)or-1
 if remoteVersion>localVersion then return 1,"NEWER"elseif remoteVersion<localVersion then return-1,"OLDER"end
 return 0,"SAME"
end
function HolyStorm.PlayerData:AdvanceForeignWatermark()end
function HolyStorm.Serializer:Serialize()return string.rep("x",64)end
HolyStorm.Tasks:RegisterTaskType("Sync.QueuePump",{executionMode="UNIQUE"})
HolyStorm.Tasks:RegisterTaskType("Sync.ReceivePayload",{executionMode="UNIQUE"})
HolyStorm.Comms={chunkSize=220,receiveLimits={maxFragments=300,maxPayloadBytes=66000},activeTransmissions={},sendCallbacks={},sendSequence=0}
function HolyStorm.Comms:Send(_,_,_,_,_,onComplete)
 self.sendSequence=self.sendSequence+1;local id="tx-test-"..self.sendSequence;self.activeTransmissions[id]=true;self.sendCallbacks[id]=onComplete;return true,id
end
function HolyStorm.Comms:IsTransmissionActive(id)return self.activeTransmissions[id]==true end
function HolyStorm.Comms:FinishTransmission(id,ok,reason)local callback=self.sendCallbacks[id];self.activeTransmissions[id]=nil;self.sendCallbacks[id]=nil;if callback then callback(ok==true,id,64,reason)end end
function HolyStorm.Comms:GetDiagnostics()return{transport={},activeSyncTransmissions=HolyStorm.Utils.TableCount(self.activeTransmissions)}end

LibStub=function(name)if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end;return HolyStorm end
assert(loadfile(root.."Sync/SyncManager.lua"))()
local Sync=HolyStorm.Sync
local imports=0
Sync:RegisterDomain("poi",{
 freshness="revision-chain",
 getMetadata=function(id)return metadata[id]end,
 listMetadata=function()return{}end,
 export=function()return{}end,
 validate=function(payload,meta,id)return type(payload)=="table"and payload.objectId==id end,
 authorize=function()return true end,
 import=function(id,payload,meta)if metadata.reject then return false,"INVALID_PAYLOAD"end;imports=imports+1;metadata[id]={objectId=id,owner=meta.owner,version=meta.version,revisionID=meta.revisionID};return true end,
})

local function reset()
 Sync:ResetActivityState("TEST_RESET");HolyStorm.Comms.activeTransmissions={};HolyStorm.Comms.sendCallbacks={};Sync.maxRetries=3;Sync.activeRequests={};Sync.requests={};Sync.catchUpJobs={};Sync.catchUpIndex={};Sync.pendingPayloads={};Sync.pendingPayloadOrder={};Sync.retiredRequestIds={};Sync.retiredRequestOrder={}
 for id in pairs(metadata)do metadata[id]=nil end
end
local function makeJob(id,sources,maxRetries)
 local owner="Player-"..id;local desired={version=2,revisionID=id.."-r2",owner=owner,direct=true};local desiredKey
 for index,source in ipairs(sources)do local sourceGuid=index==1 and owner or("Relay-"..id.."-"..index);names[source]=sourceGuid;local candidate={version=desired.version,revisionID=desired.revisionID,owner=owner,direct=sourceGuid==owner,senderGuid=sourceGuid};local key=Sync:QueueFetch("poi",id,source,0,"ON_DEMAND",nil,"seed-"..id.."-"..index,candidate);assert(key,"fetch was rejected");if index==1 then desiredKey=key end end
 local job=assert(Sync.catchUpIndex[desiredKey]);job.maxRetries=maxRetries or Sync.maxRetries;job.notBefore=clock;return job,owner
end
local function start(job)
 assert(Sync:RunQueuePump(),"queue pump did not dispatch")
 assert(Sync.activeTransfer and Sync.activeTransfer.job==job,"expected fetch did not become active")
 return Sync.activeTransfer
end
local function complete(transfer,owner,accepted)
 local data={objectId=transfer.objectId,requestId=transfer.requestId,metadata={owner=owner,version=2,revisionID=transfer.revision,updatedAt=clock},payload={objectId=transfer.objectId}}
 metadata.reject=accepted==false
 assert(Sync:OnPayload("poi",data,transfer.selectedSource,{bytes=120,packetTotal=1}),"matching response was not queued")
 assert(Sync:RunReceivePayload(),"receive task did not complete")
 metadata.reject=nil
end
local function activeIds()
 return table.concat(Sync:GetActivity().activeActivityIds or{},",")
end

-- Successful POI fetch releases its one owned activity and empties the queue.
reset();local successJob,successOwner=makeJob("poi-success",{"Owner-Success-Realm"});local successTransfer=start(successJob);local successId=successTransfer.activityId
assert(Sync:GetActivity().active and Sync:GetActivity().activityCount==1,"fetch request is active")
local activeDiagnostics=Sync:GetDiagnostics();assert(activeDiagnostics.activityCount==1 and activeDiagnostics.activeActivityIds[1]==successId and activeDiagnostics.activeTransfer.requestId==successTransfer.requestId and activeDiagnostics.activeRequest.requestId==successTransfer.requestId and activeDiagnostics.activeCatchUpJob.state=="RUNNING"and activeDiagnostics.catchUpQueueLength==0 and activeDiagnostics.activityDomain=="poi"and activeDiagnostics.activityPhase=="REQUEST"and activeDiagnostics.activityAge>=0,"Sync diagnostics expose only the current authoritative operation")
complete(successTransfer,successOwner,true)
assert(not Sync:GetActivity().active and Sync:GetActivity().activityCount==0,"successful POI fetch returns ACTIVE -> IDLE")
local idleDiagnostics=Sync:GetDiagnostics();assert(Sync:GetActivity().queuedJobs==0 and idleDiagnostics.activeTransfer==nil and idleDiagnostics.activityCount==0 and idleDiagnostics.activeRequest==nil and idleDiagnostics.activeCatchUpJob==nil,"empty queue remains idle after success")
assert(Sync:IsRetiredRequest(successTransfer.requestId)and not Sync.activeActivities[successId],"completed request IDs are cached without retaining activity")

-- Outbound payload sends count only while their own Comms transmission is live.
reset();metadata["poi-send"]={objectId="poi-send",owner="Player-Local",version=1,revisionID="poi-send-r1",updatedAt=clock}
assert(Sync:OnFetch("poi",{objectId="poi-send",knownVersion=0,requestId="peer-fetch"},"Requester-Realm"),"incoming fetch queues one payload send")
local sendJob=Sync.catchUpJobs[1];sendJob.notBefore=clock;assert(Sync:RunQueuePump());local sendTransfer=Sync.activeTransfer;local sendActivity=Sync:GetActivity()
assert(sendTransfer and sendTransfer.kind=="SEND"and sendActivity.active and sendActivity.activityCount==1 and sendActivity.activeOperations[1].direction=="SEND"and HolyStorm.Comms:IsTransmissionActive(sendTransfer.transmissionId),"payload send activity follows the exact outstanding transport ID")
HolyStorm.Comms:FinishTransmission(sendTransfer.transmissionId,true)
assert(not Sync:GetActivity().active and sendJob.state=="COMPLETED","successful payload send releases its activity owner")

-- TaskManager catches operation exceptions, so the Sync task owner must release the slot itself.
reset();metadata["poi-send-error"]={objectId="poi-send-error",owner="Player-Local",version=1,revisionID="poi-send-error-r1",updatedAt=clock};local originalExport=Sync.domains.poi.export
Sync.domains.poi.export=function()error("injected export failure")end
assert(Sync:OnFetch("poi",{objectId="poi-send-error",knownVersion=0,requestId="peer-fetch-error"},"Requester-Realm"),"failing export queues before execution")
local failedSendJob=Sync.catchUpJobs[1];failedSendJob.notBefore=clock;Sync:RunQueuePump();Sync.domains.poi.export=originalExport
assert(not Sync.activeTransfer and not Sync:GetActivity().active and failedSendJob.state=="QUEUED","an exception after transfer registration cannot leak global activity")

-- Timeout clears the activity while its bounded retry waits in the queue.
reset();local timeoutJob=makeJob("poi-timeout",{"Owner-Timeout-Realm"});local timeoutTransfer=start(timeoutJob);clock=timeoutTransfer.timeoutAt
timeoutTransfer.timeoutTimer.callback()
assert(not Sync:GetActivity().active and timeoutJob.state=="QUEUED"and timeoutJob.retryCount==1,"timeout releases activity before retry backoff")

-- Max retries exhausted and no remaining source is terminal and idle.
reset();local maxJob=makeJob("poi-max-retries",{"Owner-Max-Realm"},0);local maxTransfer=start(maxJob);clock=maxTransfer.timeoutAt;maxTransfer.timeoutTimer.callback()
assert(maxJob.state=="FAILED"and not Sync:GetActivity().active,"max retries exhausted releases activity")
reset();local sourceJob=makeJob("poi-no-source",{"Owner-NoSource-Realm"});sourceJob.sourceCandidates={};Sync:RunQueuePump()
assert(not Sync.activeTransfer and sourceJob.state=="FAILED"and not Sync:GetActivity().active,"job with no valid source fails without a leaked activity")

-- Source fallback keeps the same catch-up activity through handoff and next attempt.
reset();local fallbackJob,fallbackOwner=makeJob("poi-fallback",{"Owner-A-Realm","Owner-B-Realm"},0);local firstSource=start(fallbackJob);local fallbackActivity=firstSource.activityId;local firstRequest=firstSource.requestId
clock=firstSource.timeoutAt;firstSource.timeoutTimer.callback()
assert(Sync:GetActivity().active and Sync:GetActivity().activeActivityIds[1]==fallbackActivity,"alternate source handoff retains the job's activity owner")
local secondSource=start(fallbackJob)
assert(secondSource.activityId==fallbackActivity and secondSource.requestId~=firstRequest,"fallback reuses activity ownership and rotates request correlation")
complete(secondSource,fallbackOwner,true)
assert(not Sync:GetActivity().active,"successful alternate source closes the handoff activity")

-- Queue advancement transfers ownership only after the next job actually starts.
reset();local firstJob,firstOwner=makeJob("poi-queue-one",{"Owner-Queue-One-Realm"});local secondJob,secondOwner=makeJob("poi-queue-two",{"Owner-Queue-Two-Realm"});
local queueTransfer=start(firstJob);complete(queueTransfer,firstOwner,true)
assert(not Sync:GetActivity().active and Sync:GetActivity().queuedJobs==1,"waiting queue work does not keep the global activity active")
local nextTransfer=start(secondJob);local current=Sync:GetActivity()
assert(current.activityCount==1 and current.activeOperations[1].entity==secondJob.objectId and current.activeOperations[1].requestId==nextTransfer.requestId,"activity belongs only to the current catch-up job")
complete(nextTransfer,secondOwner,true)
assert(not Sync:GetActivity().active and Sync:GetActivity().queuedJobs==0,"queue becoming empty returns the global state to idle")

-- A late timeout and reply from a retired request cannot touch the next operation.
reset();local oldJob,oldOwner=makeJob("poi-old-request",{"Owner-Old-Realm"});local oldTransfer=start(oldJob);local oldId=oldTransfer.requestId;clock=oldTransfer.timeoutAt;oldTransfer.timeoutTimer.callback()
local currentJob,currentOwner=makeJob("poi-current-request",{"Owner-Current-Realm"});local currentTransfer=start(currentJob)
Sync:RetryTimedOut(oldId,oldTransfer)
local staleAccepted,staleReason=Sync:OnPayload("poi",{objectId=oldTransfer.objectId,requestId=oldId,metadata={owner=oldOwner,version=2,revisionID="old-r2"},payload={objectId=oldTransfer.objectId}},"Owner-Old-Realm",{})
assert(staleAccepted==false and staleReason=="RETIRED_REQUEST"and Sync.activeTransfer==currentTransfer,"late reply cannot clear or reactivate another request")
assert(Sync:GetActivity().activityCount==1 and Sync:GetActivity().activeOperations[1].requestId==currentTransfer.requestId,"late timeout leaves the current owner visible")
complete(currentTransfer,currentOwner,true)

-- Invalid payloads still terminate this attempt and leave only delayed retry work.
reset();local invalidJob,invalidOwner=makeJob("poi-invalid-payload",{"Owner-Invalid-Realm"});local invalidTransfer=start(invalidJob);complete(invalidTransfer,invalidOwner,false)
assert(not Sync:GetActivity().active and invalidJob.state=="QUEUED","invalid payload releases the active request")

-- Debounced maintenance and discovery state do not count as user-facing Sync work.
reset();Sync.requests["metadata-request"]={id="metadata-request",key="poi:*:ALL",domain="poi",createdAt=clock,candidates={}};Sync.activeRequests["poi:*:ALL"]="metadata-request"
HolyStorm.Tasks.queue={{id="Sync.PresenceHeartbeat",status="WAITING"},{id="Position.Cleanup",status="WAITING"}}
assert(not Sync:GetActivity().active and not Sync:GetRuntimeMetrics().active,"waiting Presence, Position.Cleanup and metadata discovery stay idle")

-- Independent activity owners overlap safely; ending A cannot hide B.
reset();local aLive,bLive=true,true
local activityA=Sync:BeginActivity({domain="poi",entity="A",phase="FETCH"},function()return aLive end)
local activityB=Sync:BeginActivity({domain="character",entity="B",phase="REQUEST"},function()return bLive end)
assert(Sync:GetActivity().activityCount==2,"overlapping qualifying work has two explicit owners")
aLive=false;Sync:EndActivity(activityA,"A_DONE")
assert(Sync:GetActivity().active and Sync:GetActivity().activityCount==1 and Sync:GetActivity().activeActivityIds[1]==activityB,"ending A leaves B active")
bLive=false;Sync:EndActivity(activityB,"B_DONE");assert(not Sync:GetActivity().active,"final owner returns global activity to idle")

-- A stale registry owner is reconciled, reported once and released to idle.
reset();local staleJob=makeJob("poi-stale",{"Owner-Stale-Realm"});local staleTransfer=start(staleJob);local warnBefore=0
for _,entry in ipairs(HolyStorm.Logger.history)do if entry.category=="activity"and entry.level=="WARN"then warnBefore=warnBefore+1 end end
staleTransfer.timeoutTimer:Cancel();staleTransfer.timeoutTimer=nil;staleTransfer.awaitingResponse=false
local repaired=Sync:GetActivity()
assert(not repaired.active and repaired.activityStateMismatch and Sync.activeTransfer==nil,"authoritative idle repairs stale active state")
local warnAfter=0;for _,entry in ipairs(HolyStorm.Logger.history)do if entry.category=="activity"and entry.level=="WARN"then warnAfter=warnAfter+1 end end
assert(warnAfter==warnBefore+1,"stale activity reconciliation emits one structured warning")
assert(not Sync:GetActivity().active and not Sync:GetDiagnostics().activityStateMismatch,"reconciled diagnostics report an idle consistent state")

-- Addon init/reset clears all transient active references and never restores them.
Sync:BeginActivity({domain="poi",entity="reload",phase="FETCH"},function()return true end)
assert(Sync:GetActivity().active);Sync:ResetActivityState("RELOAD_TEST")
assert(not Sync:GetActivity().active and next(Sync.activeActivities)==nil and next(Sync.retiredRequestIds)==nil,"reload reset drops transient activity and request state")

print("Sync activity ownership, terminal cleanup, late reply and reconciliation tests passed")
