local addonVersion="3.5.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Sync={version=addonVersion,protocol=3,domains={},requests={},activeRequests={},heard={},heardAt={},sequence=0,maxOffers=100,knownOnline={},knownVersions={},presenceResolutionDiagnostics={},publishedVersions={},requestTimeout=60,presenceTimeout=300,presenceRefreshMin=180,presenceRefreshJitter=60,cleanupTimer=nil,cleanupDue=nil,cleanupTaskId=nil,activityNotifyTimer=nil,loginSessionId=nil,presencePublished=false,peerVersionReceived=false,outdatedNotified=false,catchUpJobs={},catchUpIndex={},catchUpLimit=20000,activeTransfer=nil,pendingPayloads={},pendingPayloadOrder={},maxPendingPayloads=64,maxRetries=3,offerSnapshots={},runtimeMetrics={requested=0,started=0,completed=0,failed=0,retried=0,byDomain={},byReason={}}}
local function copy(v)return HolyStorm.Utils.DeepCopy(v)end
local function now()return HolyStorm.Utils.Now()end
local function validId(v)return type(v)=="string"and#v>0 and#v<=160 end
local function validDomain(v)return type(v)=="string"and#v>0 and#v<=64 and v:match("^[%w_%-]+$")~=nil end
local function validPresenceVersion(value)return value=="DEV"or type(value)=="string"and HolyStorm.Utils.CompareSemanticVersions(value,value)~=nil end
local function key(domain,objectId)return domain.."\030"..tostring(objectId or"*")end
local function log(level,category,message,context,correlationId)HolyStorm.Logger:Write(level,"Sync",category,message,context,correlationId)end
local function incrementMetric(map,key,field)
 key=tostring(key or"UNKNOWN");if#key>96 then key=key:sub(1,96)end;local item=map[key]
 if not item then local count=0;for _ in pairs(map)do count=count+1 end;if count>=128 then key="OTHER";item=map[key]end;if not item then item={};map[key]=item end end
 item[field]=(item[field]or 0)+1
end
local function recordJobMetric(sync,job,field)
 sync.runtimeMetrics[field]=sync.runtimeMetrics[field]+1
 incrementMetric(sync.runtimeMetrics.byDomain,job.domain,field)
 incrementMetric(sync.runtimeMetrics.byReason,job.reason,field)
 if HolyStorm.Tasks and HolyStorm.Tasks.RecordStartupMetric then
  local startupKey=field=="requested"and"syncJobsRequested"or field=="started"and"syncJobsStarted"or field=="completed"and"syncJobsCompleted"or field=="failed"and"syncJobsFailed"
  if startupKey then HolyStorm.Tasks:RecordStartupMetric(startupKey)end
 end
end
local function playerName()return GetUnitName and GetUnitName("player",true)or UnitName and UnitName("player")or"Player"end
local function normalizedCharacter(name)
 local store=HolyStorm.Data and HolyStorm.Data.GuildStore
 return store and store.NormalizeSenderName and store:NormalizeSenderName(name)or name
end
local function logPresenceVersion(character,guid,sender,oldVersion,incomingVersion,result,reason,receivedAt,expiresAt)
 if oldVersion==result then return end
 log("DEBUG","version","Presence version",{character=normalizedCharacter(character)or"UNKNOWN",guid=guid,sender=sender,old=oldVersion or"UNKNOWN",incoming=incomingVersion or"UNKNOWN",result=result or"UNKNOWN",reason=reason,receivedAt=receivedAt,expiresAt=expiresAt})
end
local function clearKnownVersion(sync,guid,entry,reason,incomingVersion)
 sync.knownVersions[guid]=nil
 logPresenceVersion(entry.sender or guid,guid,entry.sender,entry.version,incomingVersion,nil,reason,now())
end
local function logUnresolvedPresence(sync,data,sender,claimedGuid,reason,receivedAt)
 local key=string.lower(tostring(sender or"UNKNOWN"));local previous=sync.presenceResolutionDiagnostics[key]
 if previous and previous.reason==reason and receivedAt-(tonumber(previous.receivedAt)or 0)<sync.presenceTimeout then return end
 sync.presenceResolutionDiagnostics[key]={reason=reason,receivedAt=receivedAt}
 log("DEBUG","version","Presence version",{character=normalizedCharacter(sender)or"UNKNOWN",sender=sender,claimedGuid=claimedGuid,old="UNKNOWN",incoming=data.version or"UNKNOWN",result="UNKNOWN",reason=reason,receivedAt=receivedAt})
end
local function audience(channel,target)if target and target~=""then return target end;local labels={GUILD="Guild",RAID="Raid",PARTY="Party",INSTANCE_CHAT="Instance"};return labels[channel]or"Broadcast"end
local function receiver(channel)return channel=="WHISPER"and playerName()or audience(channel)end
local messageClasses={PRESENCE="discovery",DISCOVER="discovery",ANNOUNCE="metadata",OFFER="metadata",FETCH="request",PAYLOAD="payload",LIVE="payload"}
local function envelopeDiagnostics(envelope,channel,target,correlationId)local data=type(envelope.data)=="table"and envelope.data or{};local meta=type(data.metadata)=="table"and data.metadata or type(data.offers)=="table"and type(data.offers[1])=="table"and data.offers[1]or{};local objectId=data.objectId or meta.objectId;local characterUUID,blockType;if type(objectId)=="string"then characterUUID,blockType=objectId:match("^(.-)\031([^\031]+)$")end;local destination=audience(channel,target);return{direction="SEND",sender=playerName(),receiver=destination,target=target or destination,from=playerName(),to=destination,channel=channel,domain=envelope.domain,logicalObject=blockType or objectId,blockType=blockType,block=blockType,characterUUID=characterUUID,objectId=objectId,messageKind=envelope.kind,messageClass=messageClasses[envelope.kind]or"control",version=meta.version or data.version,revision=meta.revisionID or data.revisionID,reason=data.reason,requestId=data.requestId,correlationId=correlationId,originalOwner=meta.owner,relay=meta.owner and meta.owner~=UnitGUID("player")or false,retry=false}end
local function senderGuid(sender,claimedGuid)return HolyStorm.Data.GuildStore:ResolveSenderGuid(sender,claimedGuid)end
local function samePlayerName(a,b)if not a or not b then return false end;if Ambiguate then return Ambiguate(a,"none")==Ambiguate(b,"none")end;return a==b end
local function splitCharacterId(objectId)if type(objectId)~="string"then return nil end;return objectId:match("^(.-)\031([^\031]+)$")end
local function characterBlockSyncEnabled(block)local data=HolyStorm.PlayerData;return not(data and type(data.IsBlockSyncEnabled)=="function")or data:IsBlockSyncEnabled(block)end
local function isLocalSource(sender,guid)
 local localGuid=UnitGUID and UnitGUID("player");if localGuid and guid then return guid==localGuid end
 if HolyStorm.Comms and type(HolyStorm.Comms.IsSelfSender)=="function"then return HolyStorm.Comms:IsSelfSender(sender)end
 return samePlayerName(sender,playerName())
end
local function sameSource(leftName,leftGuid,rightName,rightGuid)
 if leftGuid and rightGuid then return leftGuid==rightGuid end
 return type(leftName)=="string"and type(rightName)=="string"and string.lower(leftName)==string.lower(rightName)
end
local function sourceExhausted(job,source)
 for _,exhausted in ipairs(job.exhaustedSources or{})do if sameSource(source.sender,source.senderGuid,exhausted.sender,exhausted.senderGuid)then return true end end
 return false
end
local function exhaustSource(job,sender,guid)
 job.exhaustedSources=job.exhaustedSources or{}
 local source={sender=sender,senderGuid=guid}
 if not sourceExhausted(job,source)then job.exhaustedSources[#job.exhaustedSources+1]=source end
 for index=#(job.sourceCandidates or{}),1,-1 do local candidate=job.sourceCandidates[index];if sameSource(candidate.sender,candidate.senderGuid,sender,guid)then table.remove(job.sourceCandidates,index)end end
end
local function recordRetry(sync,job)
 sync.runtimeMetrics.retried=sync.runtimeMetrics.retried+1
 incrementMetric(sync.runtimeMetrics.byDomain,job.domain,"retried")
 incrementMetric(sync.runtimeMetrics.byReason,job.reason,"retried")
end
local function matchesFetchPayload(transfer,domainId,data,sender)
 if not transfer or transfer.kind~="FETCH"or transfer.domain~=domainId or transfer.objectId~=data.objectId or not samePlayerName(transfer.selectedSource,sender)or(data.requestId~=nil and data.requestId~=transfer.requestId)then return false end
 local resolvedGuid=senderGuid(sender);return not transfer.selectedSourceGuid or not resolvedGuid or transfer.selectedSourceGuid==resolvedGuid
end
local function startupActive()return HolyStorm.Tasks and type(HolyStorm.Tasks.IsStartupActive)=="function" and HolyStorm.Tasks:IsStartupActive()or false end
local function startupPhase(domainId)
 if domainId=="permissions"or domainId=="character"or domainId=="twinks"then return 3 end
 return 4
end

function Sync:RegisterDomain(id,definition)
 if not validDomain(id)or type(definition)~="table"or type(definition.getMetadata)~="function"or type(definition.listMetadata)~="function"or type(definition.export)~="function"or type(definition.import)~="function"or definition.canShare~=nil and type(definition.canShare)~="function"or definition.getRecipients~=nil and type(definition.getRecipients)~="function"or(definition.canShare==nil)~=(definition.getRecipients==nil)then return false,"INVALID_DOMAIN"end
 self.domains[id]={id=id,getMetadata=definition.getMetadata,listMetadata=definition.listMetadata,export=definition.export,import=definition.import,validate=definition.validate,authorize=definition.authorize,canShare=definition.canShare,getRecipients=definition.getRecipients,getChannel=definition.getChannel,updateEvent=definition.updateEvent,freshness=definition.freshness or"metadata",live=definition.live==true,catchUp=definition.catchUp~=false,priority=tonumber(definition.priority)or nil};return true
end
function Sync:GetDomain(id)return self.domains[id]end
function Sync:UnregisterDomain(id)if not self.domains[id]then return false end;self.domains[id]=nil;return true end
function Sync:NewRequestId()self.sequence=self.sequence+1;return string.format("%08X-%04X",now()%0xFFFFFFFF,self.sequence%0xFFFF)end
function Sync:GetNextCleanupAt()
 local due;local function include(value)if value and(not due or value<due)then due=value end end
 for _,request in pairs(self.requests)do include((tonumber(request.createdAt)or 0)+self.requestTimeout)end
 for _,snapshot in pairs(self.offerSnapshots)do include((tonumber(snapshot.createdAt)or 0)+self.requestTimeout)end
 for _,at in pairs(self.heardAt)do include((tonumber(at)or 0)+self.requestTimeout)end
 for _,at in pairs(self.knownOnline)do include((tonumber(at)or 0)+self.presenceTimeout)end
 for _,entry in pairs(self.knownVersions)do if not entry.localPlayer then include((tonumber(entry.receivedAt)or 0)+self.presenceTimeout)end end
 return due
end
function Sync:CancelCleanupTimer()if self.cleanupTimer then self.cleanupTimer:Cancel()end;self.cleanupTimer,self.cleanupDue=nil,nil end
function Sync:ScheduleCleanup()
 local due=self:GetNextCleanupAt();if not due then self:CancelCleanupTimer();if self.cleanupTaskId then HolyStorm.Tasks:Cancel(self.cleanupTaskId,"SYNC_STATE_CLEARED");self.cleanupTaskId=nil end;return false end
 if self.cleanupTaskId then return true end
 if self.cleanupTimer and self.cleanupDue==due then return true end
 self:CancelCleanupTimer();self.cleanupDue=due;self.cleanupTimer=C_Timer.NewTimer(math.max(0,due-now()),function()
  Sync.cleanupTimer,Sync.cleanupDue=nil,nil;local nextDue=Sync:GetNextCleanupAt()
  if nextDue and nextDue<=now()then Sync.cleanupTaskId=HolyStorm.Tasks:Queue("Sync.Cleanup",{priority=100,triggerSource="SYNC_STATE_EXPIRY"})else Sync:ScheduleCleanup()end
 end);return true
end
function Sync:QueueEnvelope(kind,domain,data,channel,target,priority,delay)
 local envelope={protocol=self.protocol,kind=kind,domain=domain,data=data,sentAt=now(),sender=UnitGUID("player")};self.correlationSerial=(self.correlationSerial or 0)+1;local correlationId=type(data)=="table"and data.requestId and("SYNC-"..data.requestId)or string.format("SYNC-%08X-%04X",now()%0xFFFFFFFF,self.correlationSerial%0xFFFF);local diagnostics=envelopeDiagnostics(envelope,channel,target,correlationId);return HolyStorm.Tasks:Queue("Sync.Send",{executionMode="MULTI",priority=priority or 70,delay=delay or 0,triggerSource="SYNC_"..kind,metadata={envelope=envelope,channel=channel,target=target,correlationId=correlationId,diagnostics=diagnostics}})
end
function Sync:SendNow(task)
 local m=task.metadata or{}
 local payload,err=HolyStorm.Serializer:Serialize(m.envelope)
 if not payload then log("WARN","validation","Sync envelope serialization failed",{error=err,messageKind=m.envelope and m.envelope.kind,domain=m.envelope and m.envelope.domain,correlationId=m.correlationId},m.correlationId);return false end
 local diagnostics=m.diagnostics or envelopeDiagnostics(m.envelope,m.channel,m.target,m.correlationId)
 local retryCount=tonumber(task.retryCount)or 0
 diagnostics.bytes=#payload;diagnostics.serializedBytes=#payload;diagnostics.retry=retryCount>0;diagnostics.retryCount=retryCount
 local sent,transmissionId=HolyStorm.Comms:Send(payload,m.channel,m.target,task.priority,diagnostics);diagnostics.transmissionId=transmissionId
 if sent then
  local envelope=m.envelope;local data=envelope and envelope.kind=="PRESENCE"and envelope.data
  if data then
   if data.reason=="LOGIN_PRESENCE"then
    local sessionId=data.sessionId or"LOGIN_PRESENCE"
    if self.presenceAnnounceLoggedSession~=sessionId then
     self.presenceAnnounceLoggedSession=sessionId
     log("DEBUG","version","Presence announce",{character=playerName(),guid=UnitGUID and UnitGUID("player"),version=data.version,sessionId=data.sessionId,reason=data.reason})
    end
   end
   if data.sessionId==self.loginSessionId then self.presencePublished=true;HolyStorm.Tasks:Queue("Sync.VersionNotice",{delay=2,priority=99,triggerSource="PRESENCE_PUBLISHED"})end
  end
  log("DEBUG",string.lower(tostring(diagnostics.messageKind or"sync")),"Sync envelope queued",diagnostics,diagnostics.correlationId)
 else
  log("WARN","retries","Sync envelope was not queued",diagnostics,diagnostics.correlationId)
  if retryCount<(tonumber(task.maxRetries)or 0)then HolyStorm.Tasks:Queue("Sync.Send",{executionMode="MULTI",priority=task.priority,delay=math.min(8,2^(retryCount+1)),retryCount=retryCount+1,maxRetries=task.maxRetries,triggerSource="SYNC_RETRY",metadata=m})end
 end
 return sent
end
function Sync:Publish(domainId,objectId,reason)
 local domain=self.domains[domainId];local meta=domain and domain.getMetadata(objectId);if not meta then return false,"OBJECT_NOT_FOUND"end
 if domain.live then return HolyStorm.Tasks:Queue("Sync.LivePublish",{mergeKey=key(domainId,objectId),delay=.2,priority=domain.priority or 110,triggerSource=reason or"LIVE_UPDATE",metadata={domain=domainId,objectId=objectId}})end
 local channel=domain.getChannel and domain.getChannel(meta,"publish")or"GUILD";return HolyStorm.Tasks:Queue("Sync.Publish",{mergeKey=key(domainId,objectId),delay=1,startupPhase=startupActive() and startupPhase(domainId)or nil,priority=65,triggerSource=reason or"LOCAL_UPDATE",metadata={domain=domainId,objectId=objectId,channel=channel,reason=reason or"LOCAL_UPDATE"}})
end
function Sync:RunLivePublish(task)
 local m=task.metadata or{};local domain=self.domains[m.domain];local meta=domain and domain.getMetadata(m.objectId);local payload=domain and domain.export(m.objectId);if not meta or payload==nil then return false end;local channel=domain.getChannel and domain.getChannel(meta,"live")or"GUILD";local envelope={protocol=self.protocol,kind="LIVE",domain=m.domain,data={objectId=m.objectId,metadata=meta,payload=payload},sentAt=now(),sender=UnitGUID("player")};log("DEBUG","live","Publishing latest ephemeral state",{domain=m.domain,objectId=m.objectId,version=meta.version,channel=channel});return self:SendNow({metadata={envelope=envelope,channel=channel},priority=domain.priority or 110,retryCount=0,maxRetries=1})
end
function Sync:RunPublish(task)
 local m=task.metadata;local domain=self.domains[m.domain];local meta=domain and domain.getMetadata(m.objectId);if not meta then return false end;meta=copy(meta);meta.direct=meta.owner==UnitGUID("player")
 -- nil means the domain uses its normal channel; a list (including empty) is an explicit recipient scope.
 local recipients=domain.getRecipients and domain.getRecipients(meta,"publish")
 if recipients~=nil then
  local names={};for _,recipient in ipairs(recipients)do local name=type(recipient)=="table"and recipient.name or recipient;local guid=type(recipient)=="table"and recipient.guid or senderGuid(name);if type(name)=="string"and name~=""and(not domain.canShare or domain.canShare(meta,guid,name,"publish"))then names[#names+1]=name end end;table.sort(names)
  local publishKey=key(m.domain,m.objectId);local signature=table.concat({tostring(meta.version),tostring(meta.revisionID or""),table.concat(names,string.char(31))},string.char(31));if self.publishedVersions[publishKey]==signature then return true end;if#names==0 then log("DEBUG","discovery","No authorized online recipients for targeted metadata",{domain=m.domain,objectId=m.objectId,version=meta.version,reason=m.reason});return true end
  local queued;for _,name in ipairs(names)do queued=self:QueueEnvelope("ANNOUNCE",m.domain,{offers={meta},reason=m.reason},"WHISPER",name,70)or queued end
  if queued then self.publishedVersions[publishKey]=signature end;log("DEBUG","discovery","Publishing targeted metadata offers",{domain=m.domain,objectId=m.objectId,version=meta.version,recipients=#names,reason=m.reason});return queued~=nil
 end
 local channel=m.channel or(domain.getChannel and domain.getChannel(meta,"publish"))or"GUILD";local publishKey=key(m.domain,m.objectId);local signature=table.concat({tostring(meta.version),tostring(meta.revisionID or""),channel},"\031");if self.publishedVersions[publishKey]==signature then log("DEBUG","suppression","Duplicate metadata publish suppressed",{domain=m.domain,objectId=m.objectId,version=meta.version,revision=meta.revisionID,channel=channel,reason="UNCHANGED_METADATA"});return true end
 log("DEBUG","discovery","Publishing lightweight metadata",{domain=m.domain,objectId=m.objectId,version=meta.version,revision=meta.revisionID,channel=channel,reason=m.reason});local queued=self:QueueEnvelope("ANNOUNCE",m.domain,{offers={meta},reason=m.reason},channel,nil,70);if queued then self.publishedVersions[publishKey]=signature end;return queued~=nil
end
function Sync:RequestObject(domainId,objectId,options)
 local domain=self.domains[domainId];if not domain or not validId(objectId)then return false,"UNKNOWN_OBJECT"end;options=options or{};local localMeta=domain.getMetadata(objectId);local owner=options.owner or(localMeta and localMeta.owner);local target=self:GetOnlineName(owner)
 if target then local requestId=self:NewRequestId();log("DEBUG","request","Requesting payload from online owner",{domain=domainId,objectId=objectId,owner=owner,target=target,requestId=requestId});return self:QueueFetch(domainId,objectId,target,localMeta and localMeta.version or-1,options.reason or"ON_DEMAND",localMeta and localMeta.revisionID,requestId,{owner=owner,direct=true,senderGuid=owner},options)end
 return self:Discover(domainId,objectId,options)
end
function Sync:Discover(domainId,objectId,options)
 if not self.domains[domainId]then return false,"UNKNOWN_DOMAIN"end;options=options or{};local discoveryObject=objectId or("*:"..tostring(options.scope or"ALL")..":"..tostring(options.sessionId or""));local discoveryKey=key(domainId,discoveryObject);local existing=self.activeRequests[discoveryKey];if existing and self.requests[existing]then return existing,"MERGED"end
 local requestId=self:NewRequestId();local localMeta=objectId and self.domains[domainId].getMetadata(objectId);self.requests[requestId]={id=requestId,key=discoveryKey,domain=domainId,objectId=objectId,candidates={},createdAt=now(),reason=options.reason,priorityClass=options.priorityClass or((options.reason=="CHARACTER_OPEN"or options.reason=="MANUAL")and"USER_INTERACTIVE"or"BACKGROUND_CATCHUP"),channel=options.channel,scope=options.scope,sessionId=options.sessionId,knownVersion=localMeta and localMeta.version or-1,knownRevisionID=localMeta and localMeta.revisionID,watermark=options.watermark};self.activeRequests[discoveryKey]=requestId;self:ScheduleCleanup()
 HolyStorm.Tasks:Queue("Sync.Discover",{mergeKey=discoveryKey,startupPhase=options.startupPhase or(startupActive() and startupPhase(domainId)or nil),priority=options.priority or 80,delay=options.delay or 0,triggerSource=options.reason or"DISCOVERY",metadata={requestId=requestId,domain=domainId,objectId=objectId,knownVersion=localMeta and localMeta.version or-1,knownRevisionID=localMeta and localMeta.revisionID,watermark=options.watermark,channel=options.channel or"GUILD",scope=options.scope,sessionId=options.sessionId,page=0}});return requestId,"QUEUED"
end
function Sync:RunDiscover(task)
 local m=task.metadata;log("DEBUG","discovery","Sending metadata discovery",{domain=m.domain,objectId=m.objectId,requestId=m.requestId,watermark=m.watermark,channel=m.channel,page=m.page or 0});self:QueueEnvelope("DISCOVER",m.domain,{requestId=m.requestId,objectId=m.objectId,knownVersion=m.knownVersion,knownRevisionID=m.knownRevisionID,watermark=m.watermark,scope=m.scope,sessionId=m.sessionId,page=m.page or 0,paginationSender=m.paginationSender},m.channel or"GUILD",m.paginationSender,50);return true
end
function Sync:MetadataForRequest(domain,request,recipientGuid,recipientName)
 local entries={};if request.objectId then local meta=domain.getMetadata(request.objectId);if meta then entries[1]=meta end else entries=domain.listMetadata(tonumber(request.watermark)or 0,request)or{}end
 local out={};for _,meta in ipairs(entries)do if type(meta)=="table"and validId(meta.objectId)and validId(meta.owner)and tonumber(meta.version)and(not domain.canShare or domain.canShare(meta,recipientGuid,recipientName,"offer"))then local newer=tonumber(meta.version)>tonumber(request.knownVersion or-1);local sibling=domain.freshness=="revision-chain"and request.knownRevisionID and meta.revisionID~=request.knownRevisionID;if newer or sibling or not request.objectId then local item=copy(meta);item.direct=item.owner==UnitGUID("player");out[#out+1]=item end end end
 table.sort(out,function(a,b)if a.objectId==b.objectId then return tostring(a.revisionID or"")<tostring(b.revisionID or"")end;return a.objectId<b.objectId end);return out
end
function Sync:MetadataPageForRequest(domain,snapshot,request,recipientGuid,recipientName,page)
 local entries=snapshot.entries or snapshot.offers or{};local start=math.max(0,tonumber(page)or 0)*self.maxOffers;local out={};local eligible=0
 for _,meta in ipairs(entries)do
  if type(meta)=="table"and validId(meta.objectId)and validId(meta.owner)and tonumber(meta.version)and(not domain.canShare or domain.canShare(meta,recipientGuid,recipientName,"offer"))then
   local newer=tonumber(meta.version)>tonumber(request.knownVersion or-1);local sibling=domain.freshness=="revision-chain"and request.knownRevisionID and meta.revisionID~=request.knownRevisionID
   if newer or sibling or not request.objectId then eligible=eligible+1;if eligible>start and#out<self.maxOffers then local item=copy(meta);item.direct=item.owner==UnitGUID("player");out[#out+1]=item end end
  end
 end
 return out,eligible>start+#out
end
function Sync:OnDiscover(domainId,request,sender,channel)
 local domain=self.domains[domainId];if not domain or type(request)~="table"or type(request.requestId)~="string"then return false end
 local snapshotKey=table.concat({domainId,request.requestId},"\031");local snapshot=self.offerSnapshots[snapshotKey]
 if not snapshot then local entries;if request.objectId then local meta=domain.getMetadata(request.objectId);entries=meta and{meta}or{}else entries=domain.listMetadata(tonumber(request.watermark)or 0,request)or{}end;table.sort(entries,function(a,b)local aId=type(a)=="table"and tostring(a.objectId or"")or"";local bId=type(b)=="table"and tostring(b.objectId or"")or"";if aId==bId then return tostring(type(a)=="table"and a.revisionID or"")<tostring(type(b)=="table"and b.revisionID or"")end;return aId<bId end);snapshot={entries=entries,createdAt=now()};self.offerSnapshots[snapshotKey]=snapshot end
 local page=math.max(0,tonumber(request.page)or 0);local query=copy(request);query.page=nil;query.paginationSender=nil;local offers,hasMore=self:MetadataPageForRequest(domain,snapshot,query,senderGuid(sender),sender,page);if#offers==0 and not hasMore then return false end
 local delay=.15+(math.random()*1.1);HolyStorm.Tasks:Queue("Sync.Offer",{mergeKey=request.requestId.."\031"..sender,delay=delay,priority=domain.priority or 85,triggerSource="DISCOVERY_RESPONSE",metadata={domain=domainId,request=request,requester=sender,responseChannel=channel,snapshotKey=snapshotKey,page=page}});return true
end
function Sync:RunOffer(task)
 local m=task.metadata;local domain=self.domains[m.domain];local snapshot=self.offerSnapshots[m.snapshotKey];if domain and not snapshot then local query=m.request or{};snapshot={offers=self:MetadataForRequest(domain,query,senderGuid(m.requester),m.requester),createdAt=now()};self.offerSnapshots[m.snapshotKey or("legacy:"..tostring(query.requestId))]=snapshot end;if not domain or not snapshot then return false end
 local pageOffers,hasMore;if snapshot.entries then local query=copy(m.request or{});query.page=nil;query.paginationSender=nil;pageOffers,hasMore=self:MetadataPageForRequest(domain,snapshot,query,senderGuid(m.requester),m.requester,m.page)else local first=(tonumber(m.page)or 0)*self.maxOffers+1;local last=math.min(#snapshot.offers,first+self.maxOffers-1);pageOffers={};for index=first,last do pageOffers[#pageOffers+1]=snapshot.offers[index]end;hasMore=last<#snapshot.offers end
 local filtered={};local heard=self.heard[m.request.requestId]or{};for _,meta in ipairs(pageOffers)do local decision=HolyStorm.PlayerData:CompareMetadata(heard[meta.objectId],meta);if domain.freshness=="revision-chain"then if not heard[meta.objectId]or decision>0 or heard[meta.objectId].revisionID~=meta.revisionID then filtered[#filtered+1]=meta end elseif not heard[meta.objectId]or decision>0 then filtered[#filtered+1]=meta end end
 local supported={GUILD=true,PARTY=true,RAID=true,INSTANCE_CHAT=true};local channel=supported[m.responseChannel]and m.responseChannel or"GUILD";local target;if domain.canShare or m.request.paginationSender then channel,target="WHISPER",m.requester end;self:QueueEnvelope("OFFER",m.domain,{requestId=m.request.requestId,offers=filtered,requester=m.requester,page=m.page or 0,hasMore=hasMore},channel,target,domain.priority or 85);return true
end
local priorities={USER_INTERACTIVE=20,IMPORTANT_CONTROL=50,BACKGROUND_CATCHUP=90,MAINTENANCE=100}
local function priorityClass(reason)
 if reason=="CHARACTER_OPEN"or reason=="MANUAL"or reason=="USER_INTERACTIVE"or reason=="ON_DEMAND"then return"USER_INTERACTIVE"end
 if reason=="PASSIVE_HEALING"or reason=="PASSIVE"then return"MAINTENANCE"end
 return"BACKGROUND_CATCHUP"
end
local function transferKey(domainId,objectId,version,revision)
 return table.concat({domainId,tostring(objectId),tostring(version or"?"),tostring(revision or"")} ,"\030")
end
function Sync:NotifyActivity(immediate)
 local function emit()Sync.activityNotifyTimer=nil;HolyStorm.Events:Emit("HS_SYNC_ACTIVITY_UPDATED",Sync:GetActivity())end
 if immediate or not C_Timer or type(C_Timer.NewTimer)~="function"then if self.activityNotifyTimer then self.activityNotifyTimer:Cancel();self.activityNotifyTimer=nil end;emit();return end
 if self.activityNotifyTimer then return end
 self.activityNotifyTimer=C_Timer.NewTimer(.2,emit)
end
function Sync:GetActivity(characterUUID)
 local active={};local transfer=self.activeTransfer
 if transfer and(not characterUUID or transfer.characterUUID==characterUUID)then
  local item={characterUUID=transfer.characterUUID,entity=transfer.entity or transfer.objectId,domain=transfer.activityDomain or transfer.domain,direction=transfer.direction,phase=transfer.phase,sender=transfer.sender,receiver=transfer.receiver,requestId=transfer.requestId,revision=transfer.revision,bytes=transfer.bytes,fragments=transfer.fragments,fragmentsTotal=transfer.fragmentsTotal,retryCount=transfer.retryCount or 0,maxRetries=transfer.maxRetries or self.maxRetries,priority=transfer.priorityClass,startedAt=transfer.startedAt,queuePosition=1}
  active[1]=item
 end
 local queued=0;local queuePosition
 for _,job in ipairs(self.catchUpJobs)do if job.state=="QUEUED"then queued=queued+1;if characterUUID then if job.characterUUID==characterUUID and not queuePosition then queuePosition=queued end end end end
 return{active=#active>0,activeOperations=active,queuedJobs=queued,queuePosition=queuePosition}
end
function Sync:QueuePump(delay)
 if not HolyStorm.Tasks or not HolyStorm.Tasks.GetTaskType or not HolyStorm.Tasks:GetTaskType("Sync.QueuePump")then return false end
 return HolyStorm.Tasks:Queue("Sync.QueuePump",{priority=25,delay=delay or 0,triggerSource="SYNC_QUEUE_READY"})
end
function Sync:SchedulePayloadPump()
 if HolyStorm.Tasks and HolyStorm.Tasks.GetTaskType and HolyStorm.Tasks:GetTaskType("Sync.ReceivePayload")then return HolyStorm.Tasks:Queue("Sync.ReceivePayload",{priority=22,triggerSource="SYNC_RECEIVE_READY"})end
 return false
end
function Sync:RecordOffers(domainId,data,sender,isAnnouncement)
 if type(data)~="table"or type(data.offers)~="table"then return false end
 local requestId=data.requestId;local senderId=senderGuid(sender);if requestId then self.heard[requestId]=self.heard[requestId]or{};self.heardAt[requestId]=now();self:ScheduleCleanup()end
 local pending=requestId and self.requests[requestId];local domain=self.domains[domainId]
 for _,meta in ipairs(data.offers)do
  if type(meta)=="table"and validId(meta.objectId)and validId(meta.owner)and tonumber(meta.version)and not isLocalSource(sender,senderId)then
   meta=copy(meta);meta.direct=senderId~=nil and senderId==meta.owner;meta.senderGuid=senderId
   if requestId then local old=self.heard[requestId][meta.objectId];if not old or HolyStorm.PlayerData:CompareMetadata(old,meta)>0 then self.heard[requestId][meta.objectId]=meta end end
   if pending and pending.domain==domainId and(not pending.objectId or pending.objectId==meta.objectId)and(not data.requester or samePlayerName(data.requester,GetUnitName("player",true)))then
    pending.candidates[meta.objectId]=pending.candidates[meta.objectId]or{};pending.candidates[meta.objectId][sender]={sender=sender,senderGuid=senderId,meta=meta}
    local localMeta=domain.getMetadata(meta.objectId);local decision=HolyStorm.PlayerData:CompareMetadata(localMeta,meta);local sibling=domain.freshness=="revision-chain"and localMeta and tonumber(localMeta.version)==tonumber(meta.version)and localMeta.revisionID~=meta.revisionID
    if decision>0 or sibling then self:QueueFetch(domainId,meta.objectId,sender,localMeta and localMeta.version or-1,pending.reason or"DISCOVERY",localMeta and localMeta.revisionID,requestId,meta,{priorityClass=pending.priorityClass})end
   elseif not data.requester then self:ConsiderPassive(domainId,meta,sender)end
  end
 end
 if data.hasMore==true and requestId and pending and(not data.requester or samePlayerName(data.requester,GetUnitName("player",true)))then
  pending.nextPage=tonumber(data.page)and(data.page+1)or((pending.nextPage or 0)+1)
  self:QueueEnvelope("DISCOVER",domainId,{requestId=requestId,objectId=pending.objectId,knownVersion=pending.knownVersion or-1,knownRevisionID=pending.knownRevisionID,watermark=pending.watermark,scope=pending.scope,sessionId=pending.sessionId,page=pending.nextPage,paginationSender=sender},"WHISPER",sender,55,.1)
 end
 return true
end
function Sync:ApplyPayload(domainId,data,sender)
 local domain=self.domains[domainId];if not domain or type(data)~="table"or not validId(data.objectId)or type(data.metadata)~="table"then return false end;local senderId=senderGuid(sender);local meta=copy(data.metadata);meta.direct=senderId~=nil and senderId==meta.owner;meta.receivedFrom=sender
 local function logPlayerBlockReject(reason,validationStatus)
  if domain.freshness~="player-block"then return end
  local guid,block=splitCharacterId(data.objectId);if not guid or not block then return end
  local stored=HolyStorm.PlayerData:GetMetadata(guid,block);local storedHeader=HolyStorm.PlayerData:GetBlockHeader(guid,block)
  HolyStorm.PlayerData:LogRemoteBlockDecision("REJECT",reason,guid,block,meta,stored,data.payload and data.payload.data,storedHeader,validationStatus)
 end
 if domain.validate then local ok,result,reason=HolyStorm.Utils.SafeCall("sync.validate:"..domainId,domain.validate,data.payload,meta,data.objectId);if not ok or result==false then logPlayerBlockReject(reason or"INVALID_BLOCK_DATA","FAILED");log("WARN","validation","Synchronized payload rejected",{domain=domainId,objectId=data.objectId,error=reason or result});return false end end
 if domain.authorize then local ok,result=HolyStorm.Utils.SafeCall("sync.authority:"..domainId,domain.authorize,data.payload,meta,senderId,sender,data.objectId);if not ok or result~=true then logPlayerBlockReject("INVALID_OWNER","PASSED");log("WARN","authority","Synchronized payload rejected by authority rule",{domain=domainId,objectId=data.objectId,owner=meta.owner,receivedFrom=sender});return false end end
 local localMeta=domain.getMetadata(data.objectId);if domain.freshness~="revision-chain"and domain.freshness~="player-block"then local decision,reason=HolyStorm.PlayerData:CompareMetadata(localMeta,meta);if decision<=0 then log("DEBUG","freshness","Stale synchronized payload rejected",{domain=domainId,objectId=data.objectId,localVersion=localMeta and localMeta.version,remoteVersion=meta.version,reason=reason});return false end end
 local ok,result,importReason=HolyStorm.Utils.SafeCall("sync.import:"..domainId,domain.import,data.objectId,data.payload,meta,senderId,sender);if not ok or result==false then log("WARN","import","Synchronized payload import failed",{domain=domainId,objectId=data.objectId,error=importReason or result});return false end
 if importReason=="NOOP"then log("DEBUG","freshness","Synchronized payload is already current",{domain=domainId,objectId=data.objectId,version=meta.version,decision="NOOP",reason="SAME_REVISION_IDENTICAL"});return true end
 if not domain.live then HolyStorm.PlayerData:AdvanceForeignWatermark(meta.owner,meta.updatedAt,domainId)end;log("DEBUG","freshness",meta.direct and"Direct owner payload accepted"or"Indirect relay payload accepted",{domain=domainId,objectId=data.objectId,owner=meta.owner,version=meta.version,receivedFrom=sender});HolyStorm.Events:Emit("HS_SYNC_DOMAIN_UPDATED",domainId,data.objectId,meta);if domain.updateEvent then HolyStorm.Events:Emit(domain.updateEvent,data.objectId,meta)end;return true
end
function Sync:ConsiderPassive(domainId,meta,sender)
 local domain=self.domains[domainId];local localMeta=domain and domain.getMetadata(meta.objectId);local decision=HolyStorm.PlayerData:CompareMetadata(localMeta,meta);local sibling=domain and domain.freshness=="revision-chain"and localMeta and tonumber(localMeta.version)==tonumber(meta.version)and localMeta.revisionID~=meta.revisionID;if decision<=0 and not sibling then return false end;local delay=3+math.random()*5;HolyStorm.Tasks:Queue("Sync.PassiveRefresh",{mergeKey=key(domainId,meta.objectId),delay=delay,priority=95,triggerSource="PASSIVE_HEALING",metadata={domain=domainId,objectId=meta.objectId,sender=sender,version=meta.version,revisionID=meta.revisionID}});log("DEBUG","passive","Passive refresh scheduled",{domain=domainId,objectId=meta.objectId,remoteVersion=meta.version,localVersion=localMeta and localMeta.version});return true
end
function Sync:RunPassive(task)local m=task.metadata;local domain=self.domains[m.domain];local localMeta=domain and domain.getMetadata(m.objectId);if localMeta and(tonumber(localMeta.version)or 0)>=(tonumber(m.version)or 0)and not(domain.freshness=="revision-chain"and localMeta.revisionID~=m.revisionID)then return true end;return self:QueueFetch(m.domain,m.objectId,m.sender,localMeta and localMeta.version or-1,"PASSIVE_HEALING",localMeta and localMeta.revisionID,nil,{version=m.version,revisionID=m.revisionID})~=nil end
function Sync:GetOnlineName(guid)if type(guid)~="string"then return nil end;local guild=HolyStorm.Data.GuildStore:GetCurrent();local member=guild and guild.roster and guild.roster[guid];return member and member.online and member.name or nil end
function Sync:QueueFetch(domainId,objectId,target,knownVersion,reason,knownRevisionID,requestId,desiredMeta,options)
 local domain=self.domains[domainId];if not domain or not validId(objectId)or type(target)~="string"or target==""then return nil,"INVALID_FETCH"end
 desiredMeta=type(desiredMeta)=="table"and desiredMeta or{};options=options or{}
 local candidateGuid=desiredMeta.senderGuid or senderGuid(target);if isLocalSource(target,candidateGuid)then log("DEBUG","selection","Ignoring local player as sync payload source",{domain=domainId,objectId=objectId,sender=target,senderGuid=candidateGuid,requestId=requestId,reason="SELF_SOURCE"});return nil,"SELF_SOURCE"end
 local version=desiredMeta.version;local revision=desiredMeta.revisionID;local dedupeKey=transferKey(domainId,objectId,version,revision);local job=self.catchUpIndex[dedupeKey]
 if not job then local activeJob=self.activeTransfer and self.activeTransfer.job;if activeJob and activeJob.domain==domainId and activeJob.objectId==objectId and(version==nil or activeJob.requiredVersion==nil or tonumber(activeJob.requiredVersion)==tonumber(version)and activeJob.requiredRevision==revision)then job=activeJob end end
 if not job then for _,candidateJob in ipairs(self.catchUpJobs)do if candidateJob.domain==domainId and candidateJob.objectId==objectId and(candidateJob.state=="QUEUED"or candidateJob.state=="RUNNING")then if version==nil or candidateJob.requiredVersion==nil or tonumber(candidateJob.requiredVersion)==tonumber(version)and(candidateJob.requiredRevision==revision)then job=candidateJob;break end end end end
 if job and job.requiredVersion==nil and version~=nil then self.catchUpIndex[job.key]=nil;job.key=dedupeKey;job.requiredVersion=version;job.requiredRevision=revision;self.catchUpIndex[dedupeKey]=job end
 local class=options.priorityClass or priorityClass(reason);local candidate={sender=target,senderGuid=candidateGuid,owner=desiredMeta.owner,direct=desiredMeta.direct==true,version=version,revisionID=revision,meta=copy(desiredMeta)}
 if not job then
  if#self.catchUpJobs>=self.catchUpLimit then log("WARN","backpressure","Sync catch-up queue is full; job deferred",{domain=domainId,objectId=objectId,revision=revision,queueLimit=self.catchUpLimit,reason="QUEUE_LIMIT"});return nil,"QUEUE_FULL"end
  local characterUUID,block=splitCharacterId(objectId);job={key=dedupeKey,kind="FETCH",domain=domainId,objectId=objectId,characterUUID=characterUUID,block=block,entity=objectId,requiredVersion=version,requiredRevision=revision,knownVersion=knownVersion,knownRevisionID=knownRevisionID,sourceCandidates={},priorityClass=class,priority=priorities[class]or priorities.BACKGROUND_CATCHUP,state="QUEUED",queuedAt=now(),retryCount=0,maxRetries=self.maxRetries,requestId=requestId or self:NewRequestId(),reason=reason or"DISCOVERY",notBefore=now()+((class=="USER_INTERACTIVE")and.15 or 1.5)}
  self.catchUpIndex[dedupeKey]=job;self.catchUpJobs[#self.catchUpJobs+1]=job;recordJobMetric(self,job,"requested")
 end
 job.exhaustedSources=job.exhaustedSources or{}
 local found=false
 if not sourceExhausted(job,candidate)then
  for _,source in ipairs(job.sourceCandidates)do if sameSource(source.sender,source.senderGuid,candidate.sender,candidate.senderGuid)then found=true;source.direct=source.direct or candidate.direct;if candidate.version and(not source.version or candidate.version>source.version)then source.version=candidate.version;source.revisionID=candidate.revisionID;source.owner=candidate.owner;source.meta=candidate.meta end;break end end
  if not found then if#job.sourceCandidates<5 then job.sourceCandidates[#job.sourceCandidates+1]=candidate elseif candidate.direct then for index,source in ipairs(job.sourceCandidates)do if not source.direct then job.sourceCandidates[index]=candidate;break end end end end
 end
 if(priorities[class]or 90)<job.priority then job.priorityClass=class;job.priority=priorities[class];job.notBefore=math.min(job.notBefore,now()+.15)end
 job.requestId=requestId or job.requestId;self:QueuePump(math.max(0,job.notBefore-now()));self:NotifyActivity();return job.key,"MERGED"
end
function Sync:QueueOutbound(domainId,data,sender,meta)
 local characterUUID,block=splitCharacterId(data.objectId);local keyValue=table.concat({"SEND",string.lower(sender),domainId,data.objectId,tostring(meta.revisionID or meta.version)} ,"\030");if self.catchUpIndex[keyValue]then return keyValue,"MERGED"end
 if#self.catchUpJobs>=self.catchUpLimit then return nil,"QUEUE_FULL"end
 local job={key=keyValue,kind="SEND",domain=domainId,objectId=data.objectId,characterUUID=characterUUID,block=block,entity=data.objectId,target=sender,requiredVersion=meta.version,requiredRevision=meta.revisionID,requestId=data.requestId or self:NewRequestId(),priorityClass="BACKGROUND_CATCHUP",priority=priorities.BACKGROUND_CATCHUP,state="QUEUED",queuedAt=now(),retryCount=0,maxRetries=self.maxRetries,reason="REQUEST_RESPONSE",notBefore=now()}
 self.catchUpIndex[keyValue]=job;self.catchUpJobs[#self.catchUpJobs+1]=job;recordJobMetric(self,job,"requested");self:QueuePump();self:NotifyActivity();return keyValue,"QUEUED"
end
function Sync:OnFetch(domainId,data,sender)
 local domain=self.domains[domainId];if not domain or type(data)~="table"or not validId(data.objectId)then return false end
 local meta=domain.getMetadata(data.objectId);local recipientGuid=senderGuid(sender);if domain.canShare and(not meta or not domain.canShare(meta,recipientGuid,sender,"fetch"))then log("WARN","privacy","Payload request rejected by outbound authorization",{domain=domainId,objectId=data.objectId,receiver=sender});return false end
 local sibling=domain and domain.freshness=="revision-chain"and meta and data.knownRevisionID and meta.revisionID~=data.knownRevisionID and tonumber(meta.version)==tonumber(data.knownVersion)
 if not meta or((tonumber(meta.version)or 0)<=(tonumber(data.knownVersion)or-1)and not sibling)then return false end
 return self:QueueOutbound(domainId,data,sender,meta)~=nil
end
function Sync:BestSource(job)
 local best;for _,candidate in ipairs(job.sourceCandidates or{})do if not sourceExhausted(job,candidate)and not isLocalSource(candidate.sender,candidate.senderGuid)then if not best or(candidate.direct and not best.direct)then best=candidate elseif candidate.direct==best.direct then local decision=HolyStorm.PlayerData:CompareMetadata(best.meta or{},candidate.meta or{});if decision>0 then best=candidate end end end end;return best
end
function Sync:ActivityPhase(transfer,phase)
 if not transfer then return end;transfer.phase=phase;transfer.lastActivityAt=now();self:NotifyActivity()
end
function Sync:ReleaseTransfer(result,reason)
 local transfer=self.activeTransfer;if not transfer then return false end
 if transfer.timeoutTimer then transfer.timeoutTimer:Cancel();transfer.timeoutTimer=nil end
 local job=transfer.job;self.activeTransfer=nil
 if job then
  local retryLimit=tonumber(job.maxRetries)or self.maxRetries
  if result==false and transfer.kind=="FETCH"then
   if job.retryCount<retryLimit then
    job.retryCount=job.retryCount+1;recordRetry(self,job);job.state="QUEUED";job.notBefore=now()+math.min(16,2^job.retryCount);self.catchUpJobs[#self.catchUpJobs+1]=job
    log("WARN","retries","Sync fetch timed out or failed; retrying the same source",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,recipient=job.target,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,result=reason or"TRANSFER_FAILED"})
   else
    exhaustSource(job,transfer.selectedSource,transfer.selectedSourceGuid)
    job.retryCount=0
    local nextSource=self:BestSource(job)
    if nextSource then
     recordRetry(self,job);job.state="QUEUED";job.notBefore=now();self.catchUpJobs[#self.catchUpJobs+1]=job
     log("WARN","selection","Sync fetch source exhausted; trying another source",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,nextSource=nextSource.sender,priority=job.priorityClass,maxRetries=retryLimit,result=reason or"TRANSFER_FAILED"})
    else
     job.state="FAILED";recordJobMetric(self,job,"failed");self.catchUpIndex[job.key]=nil
     log("WARN","selection","Sync fetch skipped after all sources were exhausted; existing snapshot retained",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,result=reason or"NO_SOURCE"})
    end
   end
  elseif result==false and job.retryCount<retryLimit then
   job.retryCount=job.retryCount+1;recordRetry(self,job);job.state="QUEUED";job.notBefore=now()+math.min(16,2^job.retryCount);self.catchUpJobs[#self.catchUpJobs+1]=job
   log("WARN","retries","Sync domain transfer deferred for retry",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,recipient=job.target,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,result=reason or"TRANSFER_FAILED"})
  else
   job.state=result==false and"FAILED"or"COMPLETED";recordJobMetric(self,job,result==false and"failed"or"completed");self.catchUpIndex[job.key]=nil
   log(result==false and"WARN"or"DEBUG","payload",result==false and"Sync domain transfer failed; existing snapshot retained"or"Sync domain transfer completed",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,recipient=job.target,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,duration=now()-(transfer.startedAt or now()),bytes=transfer.bytes,fragments=transfer.fragmentsTotal,result=result==false and(reason or"FAILED")or"COMPLETED"})
  end
 end
 self:NotifyActivity(true);self:QueuePump();if#self.pendingPayloadOrder>0 then self:SchedulePayloadPump()end;return true
end
function Sync:RetryTimedOut(requestId,expectedTransfer)
 local active=self.activeTransfer;if not active or active.requestId~=requestId or expectedTransfer and active~=expectedTransfer then return end
 log("WARN","retries","Sync payload response timed out",{requestId=requestId,objectId=active.objectId,characterUUID=active.characterUUID,domain=active.domain,source=active.selectedSource,retryCount=active.job and active.job.retryCount or 0,result="TIMEOUT"});self:ReleaseTransfer(false,"TIMEOUT")
end
function Sync:StartFetch(job)
 local source=self:BestSource(job);if not source then job.state="FAILED";recordJobMetric(self,job,"failed");self.catchUpIndex[job.key]=nil;log("WARN","selection","No valid source remains for sync job",{requestId=job.requestId,objectId=job.objectId,domain=job.domain,result="NO_SOURCE"});self:QueuePump();return false end
 local domain=self.domains[job.domain];local localMeta=domain and domain.getMetadata(job.objectId);if not domain then job.state="FAILED";recordJobMetric(self,job,"failed");self.catchUpIndex[job.key]=nil;log("WARN","backpressure","Sync job failed because its domain was unloaded",{requestId=job.requestId,objectId=job.objectId,domain=job.domain,result="UNKNOWN_DOMAIN"});self:QueuePump();return false end
 if job.requiredVersion~=nil then local offered={version=source.version or job.requiredVersion,revisionID=source.revisionID or job.requiredRevision,owner=source.owner,direct=source.direct};local decision=HolyStorm.PlayerData:CompareMetadata(localMeta,offered);local sibling=domain.freshness=="revision-chain"and localMeta and tonumber(localMeta.version)==tonumber(offered.version)and localMeta.revisionID~=offered.revisionID;if decision<=0 and not sibling then job.state="COMPLETED";recordJobMetric(self,job,"completed");self.catchUpIndex[job.key]=nil;self:QueuePump();return true end end
 local transfer={kind="FETCH",job=job,key=job.key,objectId=job.objectId,characterUUID=job.characterUUID,activityDomain=job.block or job.domain,domain=job.domain,direction="RECEIVE",phase="REQUEST",sender=source.sender,receiver=playerName(),selectedSource=source.sender,selectedSourceGuid=source.senderGuid,requestId=job.requestId,revision=source.revisionID or job.requiredRevision,priorityClass=job.priorityClass,retryCount=job.retryCount,maxRetries=job.maxRetries,startedAt=now(),bytes=0,fragments=0}
 self.lastSelection={domain=job.domain,objectId=job.objectId,selectedSource=source.sender,selectedSourceGuid=source.senderGuid,owner=source.owner,direct=source.direct,reason=job.reason,candidateCount=#(job.sourceCandidates or{}),at=now()};log("DEBUG","selection","Selecting payload source",{domain=job.domain,objectId=job.objectId,characterUUID=job.characterUUID,block=job.block,version=source.version or job.requiredVersion,revision=source.revisionID or job.requiredRevision,requestId=job.requestId,reason=job.reason,selectedSource=source.sender,selectedSourceGuid=source.senderGuid,originalOwner=source.owner,relay=source.direct~=true,candidateCount=#(job.sourceCandidates or{})})
 job.state="RUNNING";job.startedAt=transfer.startedAt;job.selectedSource=source.sender;recordJobMetric(self,job,"started");self.activeTransfer=transfer;self:NotifyActivity(true)
 local sent=self:QueueEnvelope("FETCH",job.domain,{objectId=job.objectId,knownVersion=localMeta and localMeta.version or job.knownVersion,knownRevisionID=localMeta and localMeta.revisionID or job.knownRevisionID,revisionID=transfer.revision,reason=job.reason,requestId=job.requestId},"WHISPER",source.sender,job.priorityClass=="USER_INTERACTIVE"and 35 or 55)
 if not sent then return self:ReleaseTransfer(false,"FETCH_QUEUE_REJECTED")end
 transfer.timeoutTimer=C_Timer.NewTimer(30,function()Sync:RetryTimedOut(job.requestId,transfer)end);self:NotifyActivity();return true
end
function Sync:StartSend(job)
 local domain=self.domains[job.domain];local meta=domain and domain.getMetadata(job.objectId)
 if not domain or not meta or domain.canShare and not domain.canShare(meta,senderGuid(job.target),job.target,"fetch")then return self:ReleaseTransfer(false,"AUTHORIZATION_OR_OBJECT_CHANGED")end
 local payload=domain.export(job.objectId);if payload==nil then return self:ReleaseTransfer(false,"EXPORT_FAILED")end
 local envelope={protocol=self.protocol,kind="PAYLOAD",domain=job.domain,data={objectId=job.objectId,metadata=meta,payload=payload,reason=job.reason,requestId=job.requestId},sentAt=now(),sender=UnitGUID("player")}
 local serialized,err=HolyStorm.Serializer:Serialize(envelope);if not serialized then return self:ReleaseTransfer(false,"SERIALIZE:"..tostring(err))end
 local fragments=math.max(1,math.ceil(#serialized/HolyStorm.Comms.chunkSize));if#serialized>HolyStorm.Comms.receiveLimits.maxPayloadBytes or fragments>HolyStorm.Comms.receiveLimits.maxFragments then job.maxRetries=0;log("ERROR","backpressure","Atomic sync payload exceeds HSC1 transfer limit",{requestId=job.requestId,objectId=job.objectId,domain=job.domain,revision=meta.revisionID,bytes=#serialized,fragments=fragments,limit=HolyStorm.Comms.receiveLimits.maxFragments,result="DEFERRED_SIZE_LIMIT"});return self:ReleaseTransfer(false,"PAYLOAD_TOO_LARGE")end
 local transfer={kind="SEND",job=job,key=job.key,objectId=job.objectId,characterUUID=job.characterUUID,activityDomain=job.block or job.domain,domain=job.domain,direction="SEND",phase="TRANSFER",sender=playerName(),receiver=job.target,selectedSource=playerName(),requestId=job.requestId,revision=meta.revisionID,priorityClass=job.priorityClass,retryCount=job.retryCount,maxRetries=job.maxRetries,startedAt=now(),bytes=#serialized,fragments=0,fragmentsTotal=fragments}
 self.activeTransfer=transfer;job.state="RUNNING";job.startedAt=transfer.startedAt;recordJobMetric(self,job,"started");self:NotifyActivity(true);if fragments>=48 then log("WARN","fragmentation","Large atomic sync domain transfer queued",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=meta.revisionID,recipient=job.target,priority=job.priorityClass,bytes=#serialized,fragments=fragments})end
 local function progress(sent,total)if Sync.activeTransfer==transfer then transfer.fragments=sent;transfer.fragmentsTotal=total;Sync:NotifyActivity()end end
 local function complete(ok,id,bytes,reason)if Sync.activeTransfer~=transfer then return end;transfer.transmissionId=id;Sync:ReleaseTransfer(ok,reason)end
 local queued,id=HolyStorm.Comms:Send(serialized,"WHISPER",job.target,job.priority,{domain=job.domain,objectId=job.objectId,characterUUID=job.characterUUID,block=job.block,messageKind="PAYLOAD",messageClass="payload",revision=meta.revisionID,requestId=job.requestId,selectedSource=playerName(),originalOwner=meta.owner,relay=meta.owner~=UnitGUID("player"),priority=job.priorityClass,serializedBytes=#serialized},complete,progress)
 if not queued then return self:ReleaseTransfer(false,"TRANSPORT_QUEUE_REJECTED")end;transfer.transmissionId=id;return true
end
function Sync:RunQueuePump()
 if self.activeTransfer then return true end
 local selected,index;local earliest
 for i,job in ipairs(self.catchUpJobs)do if job.state=="QUEUED"then if job.notBefore<=now()then local score=job.priority-math.min(10,math.floor(math.max(0,now()-job.queuedAt)/30));if not selected or score<selected.score or(score==selected.score and job.queuedAt<selected.job.queuedAt)then selected={job=job,score=score};index=i end else earliest=not earliest and job.notBefore or math.min(earliest,job.notBefore)end end end
 if not selected then if earliest then self:QueuePump(math.max(.05,earliest-now()))end;return true end
 local job=selected.job;table.remove(self.catchUpJobs,index);if job.kind=="SEND"then self.activeTransfer={kind="SEND",job=job};return self:StartSend(job)end;return self:StartFetch(job)
end
function Sync:OnPayload(domainId,data,sender,transport,kind)
 local domain=self.domains[domainId];if not domain or type(data)~="table"or not validId(data.objectId)or type(data.metadata)~="table"then return false end
 transport=type(transport)=="table"and transport or{};kind=kind or"PAYLOAD"
 if kind=="LIVE"and domain.live then
  local incomingVersion=tonumber(data.metadata.version)or-1
  for _,pendingId in ipairs(self.pendingPayloadOrder)do
   local pending=self.pendingPayloads[pendingId]
   if pending and pending.kind=="LIVE"and pending.domain==domainId and pending.data.objectId==data.objectId then
    local queuedVersion=tonumber(pending.data.metadata and pending.data.metadata.version)or-1
    if incomingVersion>queuedVersion then pending.data=data;pending.sender=sender;pending.receivedAt=now();pending.bytes=transport.bytes;pending.fragments=transport.packetTotal end
    return true,"COALESCED"
   end
  end
 end
 if#self.pendingPayloadOrder>=self.maxPendingPayloads then log("WARN","backpressure","Complete payload deferred because receive queue is full",{domain=domainId,objectId=data.objectId,sender=sender,result="RECEIVE_QUEUE_FULL"});return false end
 self.sequence=self.sequence+1;local id="RX-"..self:NewRequestId().."-"..self.sequence;self.pendingPayloads[id]={id=id,domain=domainId,data=data,sender=sender,kind=kind,receivedAt=now(),bytes=transport.bytes,fragments=transport.packetTotal};self.pendingPayloadOrder[#self.pendingPayloadOrder+1]=id
 local active=self.activeTransfer;if matchesFetchPayload(active,domainId,data,sender)then if active.timeoutTimer then active.timeoutTimer:Cancel();active.timeoutTimer=nil end;active.receiveId=id;active.bytes=transport.bytes or active.bytes;active.fragments=transport.packetTotal or active.fragments;active.fragmentsTotal=transport.packetTotal or active.fragmentsTotal;self:ActivityPhase(active,"VALIDATE_COMMIT")end
 self:SchedulePayloadPump();return true
end
function Sync:OnFragmentProgress(progress)
 -- Fragment events do not carry the logical object/request until the envelope
 -- is assembled, so sender-only correlation can report unrelated data as a fetch.
 local transfer=self.activeTransfer;if not transfer or transfer.kind~="FETCH"or transfer.direction~="RECEIVE"or not progress or not progress.objectId or not progress.requestId or progress.domain~=transfer.domain or progress.objectId~=transfer.objectId or progress.requestId~=transfer.requestId or not samePlayerName(transfer.selectedSource or transfer.sender,progress.sender)then return end
 transfer.fragments=progress.fragments;transfer.fragmentsTotal=progress.fragmentsTotal;transfer.bytes=progress.bytes;self:NotifyActivity()
end
function Sync:RunReceivePayload()
 local active=self.activeTransfer;local index,id,pending
 for i,candidate in ipairs(self.pendingPayloadOrder)do local item=self.pendingPayloads[candidate];if item and(not active or matchesFetchPayload(active,item.domain,item.data,item.sender))then index,id,pending=i,candidate,item;break end end
 if not pending then return true end
 table.remove(self.pendingPayloadOrder,index);self.pendingPayloads[id]=nil
 local transfer=active;if not transfer then local meta=pending.data.metadata;local characterUUID=splitCharacterId(pending.data.objectId);transfer={kind="RECEIVE",objectId=pending.data.objectId,characterUUID=characterUUID,domain=pending.domain,direction="RECEIVE",phase="VALIDATE_COMMIT",sender=pending.sender,receiver=playerName(),requestId=pending.data.requestId,revision=meta and meta.revisionID,startedAt=now(),bytes=pending.bytes or 0};self.activeTransfer=transfer;self:NotifyActivity(true)end
 local ok=self:ApplyPayload(pending.domain,pending.data,pending.sender);if self.activeTransfer==transfer then
  if transfer.job then self:ReleaseTransfer(ok,ok and"COMMITTED"or"VALIDATION_OR_IMPORT_FAILED")else self.activeTransfer=nil;self:NotifyActivity(true);self:QueuePump()end
 end
 if#self.pendingPayloadOrder>0 then self:SchedulePayloadPump()end;return true
end
function Sync:SelectForTestOrDispatch()return self:RunQueuePump()end
function Sync:GetRuntimeMetrics()
 local activity=self:GetActivity();local requests=HolyStorm.Utils.TableCount(self.activeRequests);local queued=activity.queuedJobs+#self.pendingPayloadOrder;return{requested=self.runtimeMetrics.requested,started=self.runtimeMetrics.started,completed=self.runtimeMetrics.completed,failed=self.runtimeMetrics.failed,retried=self.runtimeMetrics.retried,byDomain=self.runtimeMetrics.byDomain,byReason=self.runtimeMetrics.byReason,queued=queued,requests=requests,active=self.activeTransfer~=nil or requests>0 or queued>0}
end
function Sync:ResetRuntimeMetrics()self.runtimeMetrics={requested=0,started=0,completed=0,failed=0,retried=0,byDomain={},byReason={}};return true end
function Sync:GetDiagnostics()local candidates=0;for _,request in pairs(self.requests)do for _,peers in pairs(request.candidates or{})do candidates=candidates+HolyStorm.Utils.TableCount(peers)end end;local activity=self:GetActivity();local idle=HolyStorm.Utils.TableCount(self.requests)==0 and HolyStorm.Utils.TableCount(self.activeRequests)==0 and activity.queuedJobs==0 and not self.activeTransfer and #self.pendingPayloadOrder==0 and self.cleanupTaskId==nil;return{requests=HolyStorm.Utils.TableCount(self.requests),activeRequests=HolyStorm.Utils.TableCount(self.activeRequests),heard=HolyStorm.Utils.TableCount(self.heard),knownOnline=HolyStorm.Utils.TableCount(self.knownOnline),domains=HolyStorm.Utils.TableCount(self.domains),peerCandidates=candidates,lastSelection=self.lastSelection,publishedVersions=HolyStorm.Utils.TableCount(self.publishedVersions),catchUpQueued=activity.queuedJobs,activeTransfer=activity.activeOperations[1],pendingPayloads=#self.pendingPayloadOrder,queueLimit=self.catchUpLimit,cleanupScheduled=self.cleanupTimer~=nil or self.cleanupTaskId~=nil,idle=idle,metrics=self.runtimeMetrics,transport=HolyStorm.Comms and HolyStorm.Comms:GetDiagnostics().transport}end
function Sync:Cleanup()
 local current=now();local requestCutoff=current-self.requestTimeout;for requestId,request in pairs(self.requests)do if(request.createdAt or 0)<=requestCutoff then self.activeRequests[request.key or key(request.domain,request.objectId)]=nil;self.requests[requestId]=nil end end;for requestId,at in pairs(self.heardAt)do if at<=requestCutoff then self.heardAt[requestId]=nil;self.heard[requestId]=nil end end;for id,snapshot in pairs(self.offerSnapshots)do if(tonumber(snapshot.createdAt)or 0)<=requestCutoff then self.offerSnapshots[id]=nil end end
 local presenceCutoff=current-self.presenceTimeout;for guid,at in pairs(self.knownOnline)do if at<=presenceCutoff then self.knownOnline[guid]=nil end end
 for guid,entry in pairs(self.knownVersions)do if not entry.localPlayer and(not validPresenceVersion(entry.version)or(tonumber(entry.receivedAt)or 0)<=presenceCutoff)then clearKnownVersion(self,guid,entry,validPresenceVersion(entry.version)and"PRESENCE_EXPIRED"or"INVALID_PRESENCE_VERSION")end end
 self:ScheduleCleanup();return true
end
function Sync:RunCatchUp()
 -- Each domain is a distinct logical scope. Discover() merges repeated catch-up requests per domain/scope.
 if not IsInGuild()then return false end;for domainId,domain in pairs(self.domains)do if domain.catchUp~=false then self:Discover(domainId,nil,{reason="LOGIN_CATCHUP",priority=98,watermark=HolyStorm.PlayerData:GetForeignWatermark(domainId)})end end;log("DEBUG","catchup","Delayed login catch-up started",{watermark=HolyStorm.PlayerData:GetForeignWatermark(),domains=HolyStorm.Utils.TableCount(self.domains)});return true
end
function Sync:GetKnownVersion(guid)
 if type(guid)~="string"then return nil end
 local localGuid=UnitGUID and UnitGUID("player")
 if localGuid and guid==localGuid then
  -- Bootstrap's local version is authoritative and must not age out with peer Presence.
  local localVersion=(HolyStorm.GetVersion and HolyStorm:GetVersion())or HolyStorm.version
  if not validPresenceVersion(localVersion)then return nil end
  local entry=self.knownVersions[guid]
  if not entry or not entry.localPlayer or entry.version~=localVersion then
   local receivedAt=now();self.knownVersions[guid]={guid=guid,sender=playerName(),version=localVersion,receivedAt=receivedAt,localPlayer=true}
   logPresenceVersion(playerName(),guid,playerName(),entry and entry.version,localVersion,localVersion,entry and"LOCAL_VERSION_AUTHORITATIVE"or"LOCAL_VERSION_KNOWN",receivedAt)
  end
  return localVersion
 end
 local entry=self.knownVersions[guid]
 if not entry then return nil end
 if entry.localPlayer then
  if localGuid then clearKnownVersion(self,guid,entry,"LOCAL_CHARACTER_CHANGED");return nil end
  return validPresenceVersion(entry.version)and entry.version or nil
 end
 if not validPresenceVersion(entry.version)or now()-(tonumber(entry.receivedAt)or 0)>=self.presenceTimeout then
  clearKnownVersion(self,guid,entry,validPresenceVersion(entry.version)and"PRESENCE_EXPIRED"or"INVALID_PRESENCE_VERSION");return nil
 end
 return entry.version
end
function Sync:BeginLoginSession()
 -- A login refreshes Presence; it does not invalidate still-fresh peer versions.
 self.loginSessionId="LOGIN-"..self:NewRequestId();self.presencePublished=false;self.peerVersionReceived=false;self.outdatedNotified=false
 local localGuid=UnitGUID and UnitGUID("player");if localGuid then self:GetKnownVersion(localGuid)end
 return HolyStorm.Tasks:Queue("Sync.LoginPresence",{delay=1.5,startupPhase=4,priority=98,triggerSource="PLAYER_LOGIN",metadata={sessionId=self.loginSessionId}})
end
function Sync:RunLoginPresence(task)
 if not IsInGuild()then return false end;local sessionId=task.metadata and task.metadata.sessionId or self.loginSessionId
 self:QueueEnvelope("PRESENCE",nil,{version=HolyStorm.version,sessionId=sessionId,replyRequested=true,reason="LOGIN_PRESENCE"},"GUILD",nil,50);self:SchedulePresenceHeartbeat();self:RunCatchUp();return true
end
function Sync:SchedulePresenceHeartbeat()
 local delay=self.presenceRefreshMin+math.random()*self.presenceRefreshJitter
 return HolyStorm.Tasks:Queue("Sync.PresenceHeartbeat",{delay=delay,priority=90,triggerSource="PRESENCE_REFRESH_SCHEDULED"})~=nil
end
function Sync:RunPresenceHeartbeat()
 if IsInGuild()then self:QueueEnvelope("PRESENCE",nil,{version=HolyStorm.version,reason="PRESENCE_HEARTBEAT"},"GUILD",nil,50)end
 self:SchedulePresenceHeartbeat();return IsInGuild()
end
function Sync:EvaluateOutdatedVersion()
 if self.outdatedNotified or not self.presencePublished or not self.peerVersionReceived then return false end
 for _,entry in pairs(self.knownVersions)do local comparison=HolyStorm.Utils.CompareSemanticVersions(entry.version,HolyStorm.version);if comparison==1 then self.outdatedNotified=true;if HolyStorm.Commands and HolyStorm.Commands.PrintUserMessage then HolyStorm.Commands:PrintUserMessage(L["OUTDATED_VERSION_NOTICE"])end;HolyStorm.Logger:Write("INFO","Sync","version","Newer Holy Storm version discovered",{localVersion=HolyStorm.version,remoteVersion=entry.version,sender=entry.sender,characterUUID=entry.guid,sessionId=self.loginSessionId});return true end end
 return false
end
function Sync:OnPresence(data,sender,resolved,claimedGuid,identityReason)
 data=type(data)=="table"and data or{};local receivedAt=now()
 if not resolved then logUnresolvedPresence(self,data,sender,claimedGuid,identityReason or"SENDER_GUID_UNRESOLVED",receivedAt);return false end
 self.presenceResolutionDiagnostics[string.lower(tostring(sender or"UNKNOWN"))]=nil;self.knownOnline[resolved]=receivedAt
 local localGuid=UnitGUID and UnitGUID("player")
 local previous=self.knownVersions[resolved]
 if resolved==localGuid or previous and previous.localPlayer then self:GetKnownVersion(resolved)
 else
  if previous then
   local previousFresh=validPresenceVersion(previous.version)and receivedAt-(tonumber(previous.receivedAt)or 0)<self.presenceTimeout
   if not previousFresh then clearKnownVersion(self,resolved,previous,validPresenceVersion(previous.version)and"PRESENCE_EXPIRED"or"INVALID_PRESENCE_VERSION");previous=nil end
  end
  if validPresenceVersion(data.version)then
   local oldVersion=previous and previous.version
   self.knownVersions[resolved]={guid=resolved,sender=sender,version=data.version,receivedAt=receivedAt}
   if oldVersion~=data.version then logPresenceVersion(sender,resolved,sender,oldVersion,data.version,data.version,oldVersion and"PRESENCE_VERSION_UPDATED"or"PRESENCE_VERSION_LEARNED",receivedAt,receivedAt+self.presenceTimeout)end
   self.peerVersionReceived=true;HolyStorm.Events:Emit("HS_SYNC_VERSION_UPDATED",resolved,data.version,sender);HolyStorm.Tasks:Queue("Sync.VersionNotice",{delay=2,priority=99,triggerSource="PEER_VERSION_RECEIVED"})
  elseif previous then
   -- A versionless Presence still confirms that this peer is alive.
   previous.sender=sender;previous.receivedAt=receivedAt
  end
 end
 self:ScheduleCleanup()
 if data.replyRequested==true and not data.responseTo then self:QueueEnvelope("PRESENCE",nil,{version=HolyStorm.version,responseTo=data.sessionId,reason="PRESENCE_RESPONSE"},"WHISPER",sender,50,.2+math.random()*.6)end
 return true
end
function Sync:Receive(payload,sender,channel,transport)
	local envelope=HolyStorm.Serializer:Deserialize(payload)
	if type(envelope)~="table"or envelope.protocol~=self.protocol or type(envelope.kind)~="string"or envelope.sender==UnitGUID("player")then return false end
	transport=type(transport)=="table"and transport or{}
	local data=type(envelope.data)=="table"and envelope.data or{}
	local meta=type(data.metadata)=="table"and data.metadata or type(data.offers)=="table"and type(data.offers[1])=="table"and data.offers[1]or{}
	local correlationId=transport.correlationId or transport.transmissionId
	local objectId=data.objectId or meta.objectId
	local characterUUID,blockType
	if type(objectId)=="string"then characterUUID,blockType=objectId:match("^(.-)\031([^\031]+)$")end
	local destination=receiver(channel)
	local resolved,identityReason=senderGuid(sender,envelope.sender)
	log("DEBUG",string.lower(envelope.kind),"Sync envelope received",{direction="RECEIVE",sender=sender,receiver=destination,target=destination,from=sender,to=destination,channel=channel,domain=envelope.domain,logicalObject=blockType or objectId,blockType=blockType,block=blockType,characterUUID=characterUUID,objectId=objectId,messageKind=envelope.kind,messageClass=messageClasses[envelope.kind]or"control",version=meta.version or data.version,revision=meta.revisionID or data.revisionID,reason=data.reason,requestId=data.requestId,selectedSource=sender,senderGuid=resolved,claimedGuid=envelope.sender,identityReason=identityReason,transmissionId=transport.transmissionId,packetTotal=transport.packetTotal,bytes=transport.bytes,serializedBytes=transport.bytes,correlationId=correlationId,originalOwner=meta.owner,relay=meta.owner and meta.owner~=envelope.sender or false,retry=false},correlationId)
	if resolved and envelope.sender~=resolved then
		log("WARN","authority","Envelope sender identity mismatch",{direction="RECEIVE",from=sender,to=destination,channel=channel,sender=sender,claimed=envelope.sender,resolved=resolved,identityReason=identityReason,transmissionId=transport.transmissionId,correlationId=correlationId},correlationId)
		return false
	end
 if envelope.kind=="PRESENCE"then return self:OnPresence(data,sender,resolved,envelope.sender,identityReason)end
  if not self.domains[envelope.domain]then return false end
  if envelope.kind=="DISCOVER"then return self:OnDiscover(envelope.domain,envelope.data,sender,channel)elseif envelope.kind=="OFFER"or envelope.kind=="ANNOUNCE"then return self:RecordOffers(envelope.domain,envelope.data,sender,envelope.kind=="ANNOUNCE")elseif envelope.kind=="FETCH"then return self:OnFetch(envelope.domain,envelope.data,sender)elseif envelope.kind=="PAYLOAD"or envelope.kind=="LIVE"then return self:OnPayload(envelope.domain,envelope.data,sender,transport,envelope.kind)end;return false
end
function Sync:Initialize()
 HolyStorm.Tasks:RegisterTaskType("Sync.Send",{name=L["TASK_SYNC_SEND"],localizedNameKey="TASK_SYNC_SEND",module="Sync",priority=70,executionMode="MULTI",maxRetries=2,execute=function(task)return Sync:SendNow(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.LivePublish",{name=L["TASK_SYNC_LIVE_PUBLISH"],localizedNameKey="TASK_SYNC_LIVE_PUBLISH",module="Sync",priority=110,executionMode="MERGE_BY_KEY",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function(task)return Sync:RunLivePublish(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Publish",{name=L["TASK_SYNC_PUBLISH"],localizedNameKey="TASK_SYNC_PUBLISH",module="Sync",priority=65,executionMode="MERGE_BY_KEY",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING"},execute=function(task)return Sync:RunPublish(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Discover",{name=L["TASK_SYNC_DISCOVER"],localizedNameKey="TASK_SYNC_DISCOVER",module="Sync",priority=80,executionMode="MERGE_BY_KEY",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function(task)return Sync:RunDiscover(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Offer",{name=L["TASK_SYNC_OFFER"],localizedNameKey="TASK_SYNC_OFFER",module="Sync",priority=85,executionMode="MERGE_BY_KEY",execute=function(task)return Sync:RunOffer(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.QueuePump",{name="Process sync queue",module="Sync",priority=25,executionMode="UNIQUE",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","NOT_IN_COMBAT"},execute=function()return Sync:RunQueuePump()end})
 HolyStorm.Tasks:RegisterTaskType("Sync.ReceivePayload",{name="Validate and commit sync payload",module="Sync",priority=22,executionMode="UNIQUE",execute=function()return Sync:RunReceivePayload()end})
 HolyStorm.Tasks:RegisterTaskType("Sync.PassiveRefresh",{name=L["TASK_SYNC_PASSIVE"],localizedNameKey="TASK_SYNC_PASSIVE",module="Sync",priority=95,executionMode="MERGE_BY_KEY",execute=function(task)return Sync:RunPassive(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Cleanup",{name="Sync cleanup",module="Sync",priority=100,executionMode="UNIQUE",execute=function()Sync.cleanupTaskId=nil;return Sync:Cleanup()end})
 HolyStorm.Tasks:RegisterTaskType("Sync.LoginPresence",{name=L["TASK_SYNC_CATCHUP"],localizedNameKey="TASK_SYNC_CATCHUP",module="Sync",priority=98,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function(task)return Sync:RunLoginPresence(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.PresenceHeartbeat",{name=L["TASK_SYNC_PRESENCE_HEARTBEAT"],localizedNameKey="TASK_SYNC_PRESENCE_HEARTBEAT",module="Sync",priority=90,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function(task)return Sync:RunPresenceHeartbeat(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.VersionNotice",{name=L["TASK_SYNC_VERSION_NOTICE"],localizedNameKey="TASK_SYNC_VERSION_NOTICE",module="Sync",priority=99,executionMode="UNIQUE",execute=function()return Sync:EvaluateOutdatedVersion()end})
 self:RegisterDomain("character",{freshness="player-block",getMetadata=function(objectId)local guid,block=splitCharacterId(objectId);return guid and HolyStorm.PlayerData:GetMetadata(guid,block)end,listMetadata=function(since)local out={};for guid,record in pairs(HolyStorm.PlayerData:GetCharacters())do for block in pairs(record.blockMeta or{})do if characterBlockSyncEnabled(block)then local meta=HolyStorm.PlayerData:GetMetadata(guid,block);if meta and(meta.committedAt or meta.updatedAt or 0)>since then out[#out+1]=meta end end end end;return out end,export=function(objectId)local guid,block=splitCharacterId(objectId);if not guid or not characterBlockSyncEnabled(block)then return nil end;local data=HolyStorm.PlayerData:GetBlock(guid,block);return data and{guid=guid,block=block,data=data}end,validate=function(payload,meta,objectId)local guid,block=splitCharacterId(objectId);return characterBlockSyncEnabled(block)and type(payload)=="table"and payload.guid==guid and payload.block==block and type(payload.data)=="table"and meta.owner==guid end,authorize=function(_,meta,_,_,objectId)local guid,block=splitCharacterId(objectId);return characterBlockSyncEnabled(block)and meta.owner==guid end,import=function(objectId,payload,meta,senderId,sender)local guid,block=splitCharacterId(objectId);return HolyStorm.PlayerData:AcceptRemoteBlock(guid,block,payload.data,meta,senderId,sender)end,updateEvent="HS_CHARACTER_SYNC_UPDATED"})
 HolyStorm.Events:Register("HS_COMMS_MESSAGE","sync",function(_,payload,sender,channel,transport)Sync:Receive(payload,sender,channel,transport)end)
 HolyStorm.Events:Register("HS_COMMS_FRAGMENT_PROGRESS","sync-activity",function(_,progress)Sync:OnFragmentProgress(progress)end)
 HolyStorm.Events:Register("HS_PLAYERDATA_OWNED_UPDATED","sync-character",function(_,guid,block)if characterBlockSyncEnabled(block)then Sync:Publish("character",guid.."\031"..block,"OWNED_BLOCK_UPDATED")end end)
 HolyStorm.Events:Register("PLAYER_LOGIN","sync-presence",function()Sync:BeginLoginSession()end)
 HolyStorm.Tasks:RegisterTaskType("Sync.LoginCatchUp",{name=L["TASK_SYNC_CATCHUP"],localizedNameKey="TASK_SYNC_CATCHUP",module="Sync",priority=98,executionMode="UNIQUE",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function()return Sync:RunCatchUp()end})
 HolyStorm.State:Set("syncReady",HolyStorm.Comms.available==true);return true
end
function Sync:Shutdown()self:CancelCleanupTimer();if self.activityNotifyTimer then self.activityNotifyTimer:Cancel();self.activityNotifyTimer=nil end;if self.cleanupTaskId then HolyStorm.Tasks:Cancel(self.cleanupTaskId,"SYNC_SHUTDOWN");self.cleanupTaskId=nil end end
HolyStorm.Sync=Sync
