-- Synthetic large-guild regression for the centralized Sync v2 planner.
local clock=1000
local root=(arg[0]:gsub("tools[/\\]test_sync_v2.lua$","")).."LIVE/Holy_Storm/"
local timers={}
function UnitGUID()return"Player-Local"end
function GetUnitName()return"Local-Realm"end
function IsInGuild()return true end
C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}
local function deep(value)if type(value)~="table"then return value end;local out={};for k,v in pairs(value)do out[k]=deep(v)end;return out end
local HolyStorm={version="3.5.0",Events={listeners={},emitted={}},Logger={history={}},Data={GuildStore={}},Tasks={types={},queue={},sequence=0},Serializer={},PlayerData={},Utils={}}
function HolyStorm:GetAddon()return self end
function HolyStorm.Events:Register(event,owner,fn)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=fn end
function HolyStorm.Events:Emit(event,...)self.emitted[#self.emitted+1]=event;for _,fn in pairs(self.listeners[event]or{})do fn(event,...)end end
function HolyStorm.Logger:Write(level,source,category,message,context)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.types[id]=definition end
function HolyStorm.Tasks:GetTaskType(id)return self.types[id]end
function HolyStorm.Tasks:Queue(id,options)
 options=options or{};local mode=options.executionMode or(self.types[id]and self.types[id].executionMode)
 if mode=="UNIQUE"or mode=="MERGE_BY_KEY"then for _,task in ipairs(self.queue)do if task.id==id and(mode=="UNIQUE"or task.options.mergeKey==options.mergeKey)then return task.id,"MERGED"end end end
 self.sequence=self.sequence+1;local task={id=id,uid="task-"..self.sequence,options=options};self.queue[#self.queue+1]=task;return task.uid,"QUEUED"
end
function HolyStorm.Utils.Now()return clock end
function HolyStorm.Utils.DeepCopy(value)return deep(value)end
function HolyStorm.Utils.TableCount(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end
function HolyStorm.Utils.SafeCall(_,fn,... )local values={pcall(fn,...)};if not values[1]then return false,values[2]end;table.remove(values,1);return true,table.unpack(values)end
local names={}
function HolyStorm.Data.GuildStore:ResolveSenderGuid(sender,claimed)return names[sender]or claimed end
function HolyStorm.Data.GuildStore:NormalizeSenderName(sender)return sender end
function HolyStorm.Data.GuildStore:GetCurrent()return{roster={}}end
function HolyStorm.PlayerData:CompareMetadata(localMeta,remoteMeta)
 if not localMeta then return 1,"MISSING"end
 local lv,rv=tonumber(localMeta.version)or-1,tonumber(remoteMeta.version)or-1;if rv>lv then return 1,"NEWER"elseif rv<lv then return-1,"OLDER"end
 if remoteMeta.direct and not localMeta.direct then return 1,"DIRECT"elseif localMeta.direct and not remoteMeta.direct then return-1,"RELAY"end
 return 0,"SAME"
end
function HolyStorm.PlayerData:AdvanceForeignWatermark()end
function HolyStorm.Serializer:Serialize(envelope)
 self.lastEnvelope=envelope;local payload=envelope and envelope.data and envelope.data.payload
 local bytes=type(payload)=="table"and tonumber(payload.bytes)or nil
 return string.rep("x",bytes or 64)
end
local sendCallbacks={}
HolyStorm.Comms={available=true,chunkSize=220,receiveLimits={maxFragments=300,maxPayloadBytes=66000},sent={}}
function HolyStorm.Comms:Send(payload,channel,target,priority,diagnostics,onComplete,onProgress)
 self.sent[#self.sent+1]={bytes=#payload,channel=channel,target=target,priority=priority,diagnostics=diagnostics}
 local total=math.max(1,math.ceil(#payload/self.chunkSize));if onProgress then onProgress(math.floor(total/2),total);onProgress(total,total)end
 if onComplete then sendCallbacks[#sendCallbacks+1]=onComplete end
 if self.autoComplete and onComplete then onComplete(true,"tx-test",#payload)end
 return true,"tx-test"
end
LibStub=function(name)if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end;return HolyStorm end

assert(loadfile(root.."Sync/SyncManager.lua"))()
local Sync=HolyStorm.Sync
HolyStorm.Tasks:RegisterTaskType("Sync.QueuePump",{executionMode="UNIQUE"})
HolyStorm.Tasks:RegisterTaskType("Sync.ReceivePayload",{executionMode="UNIQUE"})
HolyStorm.Tasks:RegisterTaskType("Sync.Send",{executionMode="MULTI"})
HolyStorm.Tasks:RegisterTaskType("Sync.Offer",{executionMode="MERGE_BY_KEY"})
local metadata,cached,remoteEntries,commits={}, {}, {}, 0
local function makeCharacter(index)
 local guid=string.format("Character-%04d",index);local ownerName=string.format("Owner-%04d-Realm",index);names[ownerName]=guid
 for _,block in ipairs({"equipment","mythicPlus","raid"})do
  local objectId=guid.."\031"..block;metadata[objectId]={objectId=objectId,owner=guid,version=1,revisionID="r1",updatedAt=900,direct=true};cached[objectId]={cached=true}
  local offered={objectId=objectId,owner=guid,version=2,revisionID="r2",updatedAt=clock+1};remoteEntries[#remoteEntries+1]=offered
 end
 return guid,ownerName
end
for index=1,1000 do makeCharacter(index)end
names["Relay-One-Realm"]="Player-RelayOne";names["Relay-Two-Realm"]="Player-RelayTwo";names["Owner-Local-Realm"]="Player-Local"
local exportIds,exportSize={},300
Sync:RegisterDomain("character",{
 freshness="metadata",
 getMetadata=function(id)return metadata[id]end,
 listMetadata=function()return remoteEntries end,
 export=function(id)exportIds[#exportIds+1]=id;return{objectId=id,snapshot={owner=metadata[id]and metadata[id].owner},bytes=exportSize}end,
 validate=function(payload,meta,id)return type(payload)=="table"and payload.objectId==id and type(payload.snapshot)=="table"and payload.multiCharacter~=true,"INVALID_OBJECT_SNAPSHOT"end,
 authorize=function(_,meta,_,_,id)return meta.owner==id:match("^(.-)\031")end,
 import=function(id,payload,meta)
  local allowed=HolyStorm.PlayerData:CompareMetadata(metadata[id],meta);if allowed<=0 then return false,"STALE"end
  local nextSnapshot=deep(payload.snapshot);local nextMeta=deep(meta);cached[id]=nextSnapshot;metadata[id]=nextMeta;commits=commits+1;return true
 end,
})
local activityEvents=0;HolyStorm.Events:Register("HS_SYNC_ACTIVITY_UPDATED","test",function()activityEvents=activityEvents+1 end)

-- Outbound responses stay one entity per logical PAYLOAD and complete through Comms.
HolyStorm.Comms.autoComplete=true
local outboundId=remoteEntries[1].objectId
assert(Sync:OnFetch("character",{objectId=outboundId,knownVersion=0,requestId="outbound-one"},"Requester-Realm"))
assert(#Sync.catchUpJobs==1 and Sync.catchUpJobs[1].kind=="SEND")
assert(Sync:RunQueuePump() and #exportIds==1 and exportIds[1]==outboundId,"one FETCH exports exactly one entity")
assert(HolyStorm.Serializer.lastEnvelope.kind=="PAYLOAD"and HolyStorm.Serializer.lastEnvelope.data.objectId==outboundId and HolyStorm.Serializer.lastEnvelope.data.payload.objectId==outboundId,"outbound snapshots never combine multiple characters")
assert(not Sync:GetActivity().active,"send completion callback closes the active transfer")
HolyStorm.Comms.autoComplete=false;Sync.catchUpJobs={};Sync.catchUpIndex={}
exportSize=66001;local sentBeforeOversize=#HolyStorm.Comms.sent;local oversizeId=remoteEntries[2].objectId
assert(Sync:OnFetch("character",{objectId=oversizeId,knownVersion=0,requestId="oversize"} ,"Requester-Realm"));local oversizeJob=Sync.catchUpJobs[1];assert(Sync:RunQueuePump())
assert(#HolyStorm.Comms.sent==sentBeforeOversize and oversizeJob.state=="FAILED","oversized atomic snapshot is failed before transport enqueue")
exportSize=300;Sync.catchUpJobs={};Sync.catchUpIndex={};Sync.activeTransfer=nil

-- Discovery coalesces, while metadata paging covers every entity without a bulk payload.
local requestId,state=Sync:Discover("character",nil,{scope="ALL",reason="LOGIN_CATCHUP",watermark=0})
local sameId,sameState=Sync:Discover("character",nil,{scope="ALL",reason="GUILD_ROSTER",watermark=0})
assert(requestId==sameId and state=="QUEUED"and sameState=="MERGED","duplicate login/roster discovery coalesces")
local discoverTasks=0;for _,task in ipairs(HolyStorm.Tasks.queue)do if task.id=="Sync.Discover"then discoverTasks=discoverTasks+1 end end
assert(discoverTasks==1,"coalesced discovery queues one broadcast task")
local query={requestId="large-page",knownVersion=0,watermark=0,page=0}
assert(Sync:OnDiscover("character",query,"Relay-One-Realm","GUILD"))
local snapshotKey="character\031large-page"
local seen={};for page=0,math.ceil(#remoteEntries/Sync.maxOffers)-1 do
 local before=#HolyStorm.Tasks.queue
 assert(Sync:RunOffer({metadata={domain="character",request={requestId="large-page",knownVersion=0,watermark=0,page=page},requester="Local-Realm",responseChannel="GUILD",snapshotKey=snapshotKey,page=page}}))
 local message;for index=before+1,#HolyStorm.Tasks.queue do local task=HolyStorm.Tasks.queue[index];if task.id=="Sync.Send"then message=task.options.metadata.envelope end end
 assert(message and message.kind=="OFFER"and#message.data.offers<=100,"metadata page is bounded to 100 entries")
 for _,offer in ipairs(message.data.offers)do seen[offer.objectId]=true end
 if page<math.ceil(#remoteEntries/Sync.maxOffers)-1 then assert(message.data.hasMore==true,"intermediate metadata page announces continuation")end
end
assert(HolyStorm.Utils.TableCount(seen)==3000,"all 1,000 characters and three stale domains are reachable through pages")
Sync.requests["large-page"]={id="large-page",key="character:*:ALL",domain="character",objectId=nil,candidates={},createdAt=clock,knownVersion=0,watermark=0,reason="LOGIN_CATCHUP",priorityClass="BACKGROUND_CATCHUP"}
local beforeNextPage=#HolyStorm.Tasks.queue
assert(Sync:RecordOffers("character",{requestId="large-page",requester="Local-Realm",page=0,hasMore=true,offers={}},"Relay-One-Realm"))
local nextPageRequest;for index=beforeNextPage+1,#HolyStorm.Tasks.queue do local task=HolyStorm.Tasks.queue[index];if task.id=="Sync.Send"and task.options.metadata.envelope.kind=="DISCOVER"then nextPageRequest=task.options.metadata end end
assert(nextPageRequest and nextPageRequest.target=="Relay-One-Realm"and nextPageRequest.envelope.data.page==1,"a page continuation requests only the next bounded metadata page from its responder")
Sync.requests["large-page"]=nil

-- Thousands of discoveries are stored in one coalescing memory queue, not thousands of tasks.
local pending=Sync.requests[requestId];pending.reason="LOGIN_CATCHUP";pending.priorityClass="BACKGROUND_CATCHUP"
local offers={};for index,entry in ipairs(remoteEntries)do offers[index]=entry end
assert(Sync:RecordOffers("character",{requestId=requestId,requester="Local-Realm",offers=offers},"Relay-One-Realm"))
assert(#Sync.catchUpJobs==3000,"1,000 characters by three domains produce only domain-scoped jobs")
assert(Sync:RecordOffers("character",{requestId=requestId,requester="Local-Realm",offers=offers},"Relay-Two-Realm"))
assert(#Sync.catchUpJobs==3000,"a second relay coalesces every duplicate logical job")
assert(Sync:RecordOffers("character",{requestId=requestId,requester="Local-Realm",offers=offers},"Relay-One-Realm"))
assert(#Sync.catchUpJobs==3000,"repeated discovery does not duplicate jobs")
local pumpCount=0;local legacyPerJobTasks=0
for _,task in ipairs(HolyStorm.Tasks.queue)do if task.id=="Sync.QueuePump"then pumpCount=pumpCount+1 end;if task.id=="Sync.SelectSource"or task.id=="Sync.Fetch"then legacyPerJobTasks=legacyPerJobTasks+1 end end
assert(pumpCount<=1 and legacyPerJobTasks==0,"backpressure keeps TaskManager work constant while 3,000 jobs wait")

-- Interactive work promotes a queued revision and elects the owner before two relays.
local userGuid,userOwner="Character-0500","Owner-0500-Realm";local userObject=userGuid.."\031equipment"
local userKey,userQueueState=Sync:QueueFetch("character",userObject,"Owner-0500-Realm",1,"CHARACTER_OPEN",nil,"interactive-500",{version=2,revisionID="r2",owner=userGuid,direct=true,senderGuid=userGuid},{priorityClass="USER_INTERACTIVE"})
local userJob=Sync.catchUpIndex[userKey];local selected=Sync:BestSource(userJob)
assert(userQueueState=="MERGED"and userJob.priorityClass=="USER_INTERACTIVE"and selected.sender==userOwner and selected.direct,"interactive request promotes the job and direct owner wins source election")
clock=1001;assert(Sync:RunQueuePump());assert(Sync.activeTransfer and Sync.activeTransfer.characterUUID==userGuid and Sync.activeTransfer.selectedSource==userOwner,"interactive character starts ahead of background catch-up")
local activity=Sync:GetActivity();assert(activity.active and activity.activeOperations[1].characterUUID==userGuid and activity.queuedJobs==2999,"activity model exposes one active transfer and bounded queue state")

-- Presence/control can still update while the data slot is occupied.
assert(Sync:OnPresence({version="DEV"},"Relay-One-Realm","Player-RelayOne","Player-RelayOne"))
assert(Sync:GetKnownVersion("Player-RelayOne")=="DEV","Presence remains independent of the serialized data slot")

-- Receive only imports a complete object on the TaskManager worker; failure keeps cache.
local payload={objectId=userObject,snapshot={new=true}}
assert(Sync:OnPayload("character",{objectId=userObject,metadata={owner=userGuid,version=2,revisionID="r2",updatedAt=clock},payload=payload},userOwner,{bytes=4096,packetTotal=19}))
assert(commits==0 and cached[userObject].cached==true,"uncommitted data is not visible before validation/import")
assert(Sync:RunReceivePayload() and commits==1 and cached[userObject].new==true,"complete revision atomically replaces its cached snapshot")
assert(not Sync:GetActivity(userGuid).active,"character activity clears after commit")

local stalePayload={objectId=userObject,snapshot={stale=true}}
assert(Sync:OnPayload("character",{objectId=userObject,metadata={owner=userGuid,version=1,revisionID="r1",updatedAt=clock+100},payload=stalePayload},"Relay-One-Realm"))
Sync:RunReceivePayload();assert(commits==1 and cached[userObject].new==true,"stale relay cannot replace the committed snapshot")

-- Live domains coalesce queued receipts to their latest object version and do not advance durable watermarks.
local liveGuid,liveOwner="Character-Live","Live-Owner-Realm";names[liveOwner]=liveGuid
local liveState,liveImports=nil,0
Sync:RegisterDomain("live-test",{
 live=true,catchUp=false,priority=110,
 getMetadata=function(id)return liveState and{objectId=id,owner=id,version=liveState.version,updatedAt=clock,direct=true}or nil end,
 listMetadata=function()return{}end,
 export=function()return nil end,
 validate=function(payload,meta,id)return type(payload)=="table"and payload.characterUUID==id end,
 authorize=function(_,meta,senderId,_,id)return meta.owner==id and senderId==id end,
 import=function(id,payload,meta)liveState={version=meta.version,value=payload.value};liveImports=liveImports+1;return true end,
})
local watermarkCalls=0;local oldAdvance=HolyStorm.PlayerData.AdvanceForeignWatermark
HolyStorm.PlayerData.AdvanceForeignWatermark=function()watermarkCalls=watermarkCalls+1 end
local function livePayload(version,value)
 return{objectId=liveGuid,metadata={owner=liveGuid,version=version,updatedAt=clock},payload={characterUUID=liveGuid,value=value}}
end
local liveQueueStart=#Sync.pendingPayloadOrder
assert(Sync:OnPayload("live-test",livePayload(1,"old"),liveOwner,{bytes=80,packetTotal=1},"LIVE"))
assert(Sync:OnPayload("live-test",livePayload(3,"latest"),liveOwner,{bytes=82,packetTotal=1},"LIVE"))
assert(Sync:OnPayload("live-test",livePayload(2,"late-old"),liveOwner,{bytes=81,packetTotal=1},"LIVE"))
assert(#Sync.pendingPayloadOrder==liveQueueStart+1,"queued live states for one object must occupy one bounded receive slot")
local queuedLive=Sync.pendingPayloads[Sync.pendingPayloadOrder[#Sync.pendingPayloadOrder]]
assert(queuedLive.kind=="LIVE"and queuedLive.data.metadata.version==3 and queuedLive.data.payload.value=="latest",
 "live receive queue did not retain the newest object state")
assert(Sync:RunReceivePayload()and liveImports==1 and liveState.value=="latest","latest queued live state was not imported")
assert(watermarkCalls==0,"ephemeral live data must not update durable catch-up watermarks")
HolyStorm.PlayerData.AdvanceForeignWatermark=oldAdvance

-- A burst of position publications is one low-priority live task, exported at execution time.
HolyStorm.Tasks:RegisterTaskType("Sync.LivePublish",{executionMode="MERGE_BY_KEY"})
local outboundPosition={version=0,value=0}
Sync:RegisterDomain("live-out-test",{
 live=true,catchUp=false,priority=110,
 getMetadata=function(id)return{objectId=id,owner="Player-Local",version=outboundPosition.version,updatedAt=clock}end,
 listMetadata=function()return{}end,
 export=function()return{value=outboundPosition.value}end,
 import=function()return true end,
})
local queuedPositionTasks=0;local positionTask
for version=1,500 do
 outboundPosition.version,outboundPosition.value=version,version
 local _,queueState=Sync:Publish("live-out-test","Player-Local","POSITION_LIVE_UPDATE")
 if queueState=="QUEUED"then queuedPositionTasks=queuedPositionTasks+1 end
end
for _,task in ipairs(HolyStorm.Tasks.queue)do if task.id=="Sync.LivePublish"and task.options.metadata.domain=="live-out-test"then positionTask=task end end
assert(queuedPositionTasks==1 and positionTask and positionTask.options.priority==110,
 "500 pending position updates must coalesce into one low-priority live task")
assert(Sync:RunLivePublish({metadata=positionTask.options.metadata})
 and HolyStorm.Serializer.lastEnvelope.kind=="LIVE"
 and HolyStorm.Serializer.lastEnvelope.data.payload.value==500,
 "coalesced live task must export only the newest position at dispatch time")
assert(HolyStorm.Comms.sent[#HolyStorm.Comms.sent].priority==110,
 "position traffic must retain its low Sync transport priority")

-- A lost response retries finitely and does not block the next eligible character.
clock=1002
assert(Sync:RunQueuePump());local timedOut=Sync.activeTransfer;assert(timedOut and timedOut.kind=="FETCH")
timedOut.timeoutTimer.callback();assert(timedOut.job.retryCount==1 and timedOut.job.state=="QUEUED","response timeout returns the job to bounded retry state")
assert(Sync:RunQueuePump() and Sync.activeTransfer and Sync.activeTransfer.characterUUID~=userGuid,"queue advances to another stale character while the failed job backs off")
Sync.activeTransfer=nil;Sync.catchUpJobs={};Sync.catchUpIndex={};Sync:NotifyActivity();assert(not Sync:GetActivity().active and Sync:GetActivity().queuedJobs==0,"idle activity model is empty after the queue drains")
assert(activityEvents>0,"central activity changes emit update events")
local syncMetrics=Sync:GetRuntimeMetrics();assert(syncMetrics.requested>0 and syncMetrics.started>0 and syncMetrics.completed>0 and syncMetrics.retried>0 and next(syncMetrics.byDomain)and next(syncMetrics.byReason),"sync lifecycle metrics include bounded domain and reason aggregates")
local requestsBeforeReset=Sync.requests;assert(Sync:ResetRuntimeMetrics()and Sync:GetRuntimeMetrics().requested==0 and next(Sync:GetRuntimeMetrics().byDomain)==nil and Sync.requests==requestsBeforeReset,"sync metrics reset preserves protocol request state")
print("Sync v2 large-guild queue, paging, priority, serialization and atomic receive tests passed")
