local addonVersion="3.5.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Sync={version=addonVersion,protocol=3,domains={},requests={},activeRequests={},heard={},heardAt={},sequence=0,maxOffers=100,knownOnline={},knownVersions={},presenceResolutionDiagnostics={},publishedVersions={},requestTimeout=60,presenceTimeout=300,cleanupTimer=nil,cleanupDue=nil,cleanupTaskId=nil,activityNotifyTimer=nil,activitySequence=0,activeActivities={},activityPublishedActive=false,activityStateMismatch=false,activityMismatchLogged=false,retiredRequestIds={},retiredRequestOrder={},maxRetiredRequests=256,terminalFetches={},terminalFetchOrder={},lastTerminalFetch=nil,terminalFetchRetention=600,maxTerminalFetches=512,loginSessionId=nil,presencePublished=false,peerVersionReceived=false,outdatedNotified=false,catchUpJobs={},catchUpIndex={},catchUpLimit=20000,activeTransfer=nil,pendingPayloads={},pendingPayloadOrder={},maxPendingPayloads=64,maxRetries=3,maxManifestEntries=64,pendingManifestEntries={},maxPendingManifestEntries=256,maxCoalescedRecipients=64,maxRequestIdsPerRecipient=4,requestCoalesceWindow=.75,outboundCoalescing={},outboundSequence=0,offerSnapshots={},runtimeMetrics={requested=0,started=0,completed=0,failed=0,retried=0,byDomain={},byReason={}}}
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
local messageClasses={PRESENCE="discovery",DISCOVER="discovery",ANNOUNCE="metadata",OFFER="metadata",FETCH="request",FETCH_RESULT="request",PAYLOAD="payload",LIVE="payload"}
local function envelopeDiagnostics(envelope,channel,target,correlationId)local data=type(envelope.data)=="table"and envelope.data or{};local meta=type(data.metadata)=="table"and data.metadata or type(data.offers)=="table"and type(data.offers[1])=="table"and data.offers[1]or type(data.currentMetadata)=="table"and data.currentMetadata or{};local objectId=data.objectId or meta.objectId;local characterUUID,blockType;if type(objectId)=="string"then characterUUID,blockType=objectId:match("^(.-)\031([^\031]+)$")end;local destination=audience(channel,target);return{direction="SEND",sender=playerName(),receiver=destination,target=target or destination,from=playerName(),to=destination,channel=channel,domain=envelope.domain,logicalObject=blockType or objectId,blockType=blockType,block=blockType,characterUUID=characterUUID,objectId=objectId,messageKind=envelope.kind,messageClass=messageClasses[envelope.kind]or"control",version=meta.version or data.currentVersion or data.version,revision=meta.revisionID or data.currentRevisionID or data.revisionID,reason=data.reason or data.result,requestId=data.requestId,correlationId=correlationId,originalOwner=meta.owner,relay=meta.owner and meta.owner~=UnitGUID("player")or false,retry=false}end
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
local function sourceDiagnostics(sources)
 local out={};for _,source in ipairs(sources or{})do out[#out+1]={sender=source.sender,senderGuid=source.senderGuid,originOwner=source.owner,isOriginOwner=source.direct==true,revisionID=source.revisionID or(source.meta and source.meta.revisionID)}end;return out
end
local function exhaustedSourceDiagnostics(sources)
 local out={};for _,source in ipairs(sources or{})do out[#out+1]={sender=source.sender,senderGuid=source.senderGuid}end;return out
end
local function readableDedupKey(value)return tostring(value or""):gsub("[%c]","|")end
local function sourceListed(sources,sender,guid)
 for _,source in ipairs(sources or{})do if sameSource(source.sender,source.senderGuid,sender,guid)then return true end end
 return false
end
local function pruneTerminalFetches(sync)
 local current=now()
 for keyValue,entry in pairs(sync.terminalFetches)do if(tonumber(entry.expiresAt)or 0)<=current then sync.terminalFetches[keyValue]=nil end end
 while #sync.terminalFetchOrder>sync.maxTerminalFetches do local oldest=table.remove(sync.terminalFetchOrder,1);if sync.terminalFetches[oldest.key]==oldest.entry then sync.terminalFetches[oldest.key]=nil end end
end
local function rememberTerminalFetch(sync,job,reason)
 local entry={dedupKey=readableDedupKey(job.key),domain=job.domain,entity=job.objectId,revision=job.requiredRevision,version=job.requiredVersion,discoveryGeneration=job.discoveryGeneration,terminalReason=reason or job.terminalReason or"ALL_SOURCES_EXHAUSTED",requeueReason=job.requeueReason,sourceCandidates=sourceDiagnostics(job.allSourceCandidates or job.sourceCandidates),exhaustedSources=exhaustedSourceDiagnostics(job.exhaustedSources),queueLength=#sync.catchUpJobs,createdAt=now(),expiresAt=now()+sync.terminalFetchRetention}
 sync.terminalFetches[job.key]=entry;sync.terminalFetchOrder[#sync.terminalFetchOrder+1]={key=job.key,entry=entry};sync.lastTerminalFetch=copy(entry);pruneTerminalFetches(sync)
 log("WARN","selection","Sync job reached terminal source exhaustion",{domain=entry.domain,entity=entry.entity,revision=entry.revision,requestId=job.requestId,dedupKey=entry.dedupKey,discoveryGeneration=entry.discoveryGeneration,terminalReason=entry.terminalReason,requeueReason=entry.requeueReason,candidateSources=entry.sourceCandidates,exhaustedSources=entry.exhaustedSources,queueLength=entry.queueLength})
end
local function recordRetry(sync,job)
 sync.runtimeMetrics.retried=sync.runtimeMetrics.retried+1
 incrementMetric(sync.runtimeMetrics.byDomain,job.domain,"retried")
 incrementMetric(sync.runtimeMetrics.byReason,job.reason,"retried")
end
local function matchesFetchPayload(transfer,domainId,data,sender)
 local requestMatches=transfer and data.requestId==transfer.requestId
 if not requestMatches and transfer and type(data.requestIds)=="table"then local checked=0;for _,requestId in ipairs(data.requestIds)do checked=checked+1;if checked>Sync.maxCoalescedRecipients*Sync.maxRequestIdsPerRecipient then break end;if requestId==transfer.requestId then requestMatches=true;break end end end
 if not transfer or transfer.kind~="FETCH"or transfer.domain~=domainId or transfer.objectId~=data.objectId or not samePlayerName(transfer.selectedSource,sender)or not requestMatches then return false end
 local resolvedGuid=senderGuid(sender);return not transfer.selectedSourceGuid or not resolvedGuid or transfer.selectedSourceGuid==resolvedGuid
end
local function startupActive()return HolyStorm.Tasks and type(HolyStorm.Tasks.IsStartupActive)=="function" and HolyStorm.Tasks:IsStartupActive()or false end
local function startupPhase(domainId)
 if domainId=="permissions"or domainId=="character"or domainId=="twinks"then return 3 end
 return 4
end

function Sync:RegisterDomain(id,definition)
 if not validDomain(id)or type(definition)~="table"or type(definition.getMetadata)~="function"or type(definition.listMetadata)~="function"or type(definition.export)~="function"or type(definition.import)~="function"or definition.canShare~=nil and type(definition.canShare)~="function"or definition.getRecipients~=nil and type(definition.getRecipients)~="function"or(definition.canShare==nil)~=(definition.getRecipients==nil)or definition.listManifest~=nil and type(definition.listManifest)~="function"or definition.canBroadcast~=nil and type(definition.canBroadcast)~="function"or definition.broadcastSafe~=nil and type(definition.broadcastSafe)~="boolean"then return false,"INVALID_DOMAIN"end
 self.domains[id]={id=id,getMetadata=definition.getMetadata,listMetadata=definition.listMetadata,listManifest=definition.listManifest,export=definition.export,import=definition.import,validate=definition.validate,authorize=definition.authorize,canShare=definition.canShare,getRecipients=definition.getRecipients,getChannel=definition.getChannel,canBroadcast=definition.canBroadcast,broadcastSafe=definition.broadcastSafe==true,updateEvent=definition.updateEvent,freshness=definition.freshness or"metadata",live=definition.live==true,catchUp=definition.catchUp~=false,priority=tonumber(definition.priority)or nil};self:ProcessPendingManifest(id);return true
end
function Sync:GetDomain(id)return self.domains[id]end
local function compactManifestEntry(domainId,metadata)
 if type(metadata)~="table"or not validDomain(domainId)or not validId(metadata.objectId)or not validId(metadata.owner)then return nil end
 local version=tonumber(metadata.version);if not version or version~=version or version==math.huge or version<0 or version%1~=0 then return nil end
 if metadata.revisionID~=nil and not validId(metadata.revisionID)then return nil end
 local result={domain=domainId,objectId=metadata.objectId,owner=metadata.owner,version=version}
 if metadata.revisionID then result.revisionID=metadata.revisionID end
 local schemaVersion=tonumber(metadata.schemaVersion);if schemaVersion and schemaVersion==schemaVersion and schemaVersion~=math.huge and schemaVersion>=0 and schemaVersion%1==0 then result.schemaVersion=schemaVersion end
 local snapshotVersion=tonumber(metadata.snapshotVersion);if snapshotVersion and snapshotVersion==snapshotVersion and snapshotVersion~=math.huge and snapshotVersion>=0 and snapshotVersion%1==0 then result.snapshotVersion=snapshotVersion end
 return result
end
local function sameAuthoritativeRevision(localMeta,remoteMeta)
 if type(localMeta)~="table"or type(remoteMeta)~="table"or localMeta.owner~=remoteMeta.owner then return false end
 if tonumber(localMeta.version)~=tonumber(remoteMeta.version)then return false end
 return localMeta.revisionID==remoteMeta.revisionID
end
local function metadataNeedsFetch(domain,localMeta,remoteMeta)
 if sameAuthoritativeRevision(localMeta,remoteMeta)then return false,"SAME_REVISION"end
 local decision,reason=HolyStorm.PlayerData:CompareMetadata(localMeta,remoteMeta)
 local sibling=domain and domain.freshness=="revision-chain"and localMeta and tonumber(localMeta.version)==tonumber(remoteMeta.version)and localMeta.revisionID~=remoteMeta.revisionID
 if decision>0 or sibling then return true,sibling and"REVISION_CHAIN_SIBLING"or reason end
 return false,localMeta and decision<0 and"LOCAL_NEWER"or reason or"CURRENT"
end
function Sync:BuildManifest()
 local entries,seen={},{};local scanLimit=self.maxManifestEntries*4
 local domainIds={};for domainId,domain in pairs(self.domains)do if type(domain.listManifest)=="function"then domainIds[#domainIds+1]=domainId end end
 table.sort(domainIds,function(a,b)if a=="character"then return b~="character"elseif b=="character"then return false end;return a<b end)
 for _,domainId in ipairs(domainIds)do
  local domain=self.domains[domainId]
  if #entries>=self.maxManifestEntries then break end
  do
   local ok,metadataList=pcall(domain.listManifest,self.maxManifestEntries-#entries)
   if ok and type(metadataList)=="table"then
    local scanned=0
    for _,metadata in pairs(metadataList)do
     scanned=scanned+1;if scanned>scanLimit or #entries>=self.maxManifestEntries then break end
     local entry=compactManifestEntry(domainId,metadata);local dedupe=entry and key(entry.domain,entry.objectId)
     if entry and not seen[dedupe]then seen[dedupe]=true;entries[#entries+1]=entry end
    end
   else log("WARN","metadata","Domain manifest provider failed",{domain=domainId,error=ok and"INVALID_MANIFEST_LIST"or tostring(metadataList)})end
  end
 end
 table.sort(entries,function(a,b)if a.domain==b.domain then return a.objectId<b.objectId end;return a.domain<b.domain end)
 return{schema=1,entries=entries}
end
function Sync:ProcessManifestEntry(entry,sender,senderGuidValue)
 local domain=self.domains[entry.domain];if not domain then return false,"UNKNOWN_DOMAIN"end
 local metadata={objectId=entry.objectId,owner=entry.owner,version=entry.version,revisionID=entry.revisionID,schemaVersion=entry.schemaVersion,snapshotVersion=entry.snapshotVersion,direct=senderGuidValue~=nil and senderGuidValue==entry.owner,senderGuid=senderGuidValue}
 local ok,localMeta=pcall(domain.getMetadata,entry.objectId);if not ok then log("WARN","metadata","Manifest metadata comparison failed",{domain=entry.domain,objectId=entry.objectId,sender=sender,error=tostring(localMeta)});return false,"METADATA_LOOKUP_FAILED"end
 local needed,reason=metadataNeedsFetch(domain,localMeta,metadata)
 if not needed then
  local message=reason=="SAME_REVISION"and"Local revision already matches announced metadata"or reason=="LOCAL_NEWER"and"Local revision is newer; metadata request suppressed"or"Announced metadata does not require a payload"
  log("DEBUG","freshness",message,{domain=entry.domain,objectId=entry.objectId,owner=entry.owner,localVersion=localMeta and localMeta.version,remoteVersion=entry.version,localRevision=localMeta and localMeta.revisionID,remoteRevision=entry.revisionID,decision=reason,sender=sender})
  return false,reason
 end
 log("INFO","metadata","New authoritative revision discovered from Presence manifest",{domain=entry.domain,objectId=entry.objectId,owner=entry.owner,localVersion=localMeta and localMeta.version,remoteVersion=entry.version,revision=entry.revisionID,sender=sender,sourceDirect=metadata.direct==true})
 local requestId,state=self:QueueFetch(entry.domain,entry.objectId,sender,localMeta and localMeta.version or-1,"PRESENCE_MANIFEST",localMeta and localMeta.revisionID,nil,metadata,{priorityClass="MAINTENANCE",notBeforeDelay=.35})
 log(requestId and"DEBUG"or"WARN","request",requestId and"Manifest payload demand registered"or"Manifest payload demand rejected",{domain=entry.domain,objectId=entry.objectId,owner=entry.owner,revision=entry.revisionID,sender=sender,requestId=requestId,state=state})
 return requestId~=nil, state
end
function Sync:ProcessPendingManifest(domainId)
 local pending=self.pendingManifestEntries;local kept={};local current=now()
 for _,item in ipairs(pending)do
  if current-(tonumber(item.receivedAt)or 0)<self.presenceTimeout then
   if item.entry.domain==domainId and self.domains[domainId]then self:ProcessManifestEntry(item.entry,item.sender,item.senderGuid)else kept[#kept+1]=item end
  end
 end
 self.pendingManifestEntries=kept;self:ScheduleCleanup();return true
end
function Sync:ReceiveManifest(manifest,sender,senderGuidValue)
 if type(manifest)~="table"or manifest.schema~=1 or type(manifest.entries)~="table"then log("WARN","validation","Invalid Presence revision manifest rejected",{sender=sender,reason="INVALID_MANIFEST_SCHEMA"});return false end
 local count=0;for index in pairs(manifest.entries)do count=count+1;if count>self.maxManifestEntries or type(index)~="number"or index<1 or index%1~=0 then log("WARN","validation","Invalid Presence revision manifest rejected",{sender=sender,reason="MANIFEST_ENTRY_LIMIT_OR_SHAPE",entryCount=count});return false end end
 if count~=#manifest.entries then log("WARN","validation","Invalid Presence revision manifest rejected",{sender=sender,reason="SPARSE_MANIFEST",entryCount=count});return false end
 log("DEBUG","metadata","Presence revision manifest received",{sender=sender,senderGuid=senderGuidValue,entryCount=count,schema=manifest.schema})
 local pending=self.pendingManifestEntries;local current=now()
 local cleaned={};for _,item in ipairs(pending)do if current-(tonumber(item.receivedAt)or 0)<self.presenceTimeout then cleaned[#cleaned+1]=item end end;self.pendingManifestEntries=cleaned;pending=cleaned
 local seen={}
 for _,raw in ipairs(manifest.entries)do
  local entry=compactManifestEntry(raw and raw.domain,raw);local dedupe=entry and key(entry.domain,entry.objectId)
  if not entry or seen[dedupe]then log("WARN","validation","Invalid or duplicate Presence manifest entry ignored",{sender=sender,domain=raw and raw.domain,objectId=raw and raw.objectId,reason=entry and"DUPLICATE_OBJECT"or"INVALID_ENTRY"})
  else
   seen[dedupe]=true
   if self.domains[entry.domain]then self:ProcessManifestEntry(entry,sender,senderGuidValue)
   elseif #pending<self.maxPendingManifestEntries then pending[#pending+1]={entry=entry,sender=sender,senderGuid=senderGuidValue,receivedAt=current}
   else log("WARN","backpressure","Unknown-domain manifest entry dropped at capacity",{domain=entry.domain,objectId=entry.objectId,limit=self.maxPendingManifestEntries})end
  end
 end
 self:ScheduleCleanup()
 return true
end
function Sync:UnregisterDomain(id)
 if not self.domains[id]then return false end;self.domains[id]=nil
 local transfer=self.activeTransfer;if transfer and transfer.domain==id and transfer.kind~="SEND"then self:ReleaseTransfer(false,"DOMAIN_UNREGISTERED",transfer)end
 return true
end
function Sync:NewRequestId()self.sequence=self.sequence+1;return string.format("%08X-%04X",now()%0xFFFFFFFF,self.sequence%0xFFFF)end
function Sync:RememberRetiredRequest(requestId,reason)
 if type(requestId)~="string"or requestId==""then return false end
 self.retiredRequestIds[requestId]={expiresAt=now()+self.requestTimeout,reason=reason or"TERMINAL"};self.retiredRequestOrder[#self.retiredRequestOrder+1]=requestId
 while #self.retiredRequestOrder>self.maxRetiredRequests do local oldest=table.remove(self.retiredRequestOrder,1);self.retiredRequestIds[oldest]=nil end
 self:ScheduleCleanup();return true
end
function Sync:IsRetiredRequest(requestId)
 local entry=type(requestId)=="string"and self.retiredRequestIds[requestId]
 if not entry then return false end
 if (tonumber(entry.expiresAt)or 0)<=now()then self.retiredRequestIds[requestId]=nil;return false end
 return true
end
function Sync:GetNextCleanupAt()
 local due;local function include(value)if value and(not due or value<due)then due=value end end
 for _,request in pairs(self.requests)do include((tonumber(request.createdAt)or 0)+self.requestTimeout)end
 for _,snapshot in pairs(self.offerSnapshots)do include((tonumber(snapshot.createdAt)or 0)+self.requestTimeout)end
 for _,request in pairs(self.retiredRequestIds)do include(tonumber(request.expiresAt))end
 for _,entry in pairs(self.terminalFetches)do include(tonumber(entry.expiresAt))end
 for _,entry in ipairs(self.pendingManifestEntries)do include((tonumber(entry.receivedAt)or 0)+self.presenceTimeout)end
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
local function activityOwner(record)
 local owner=record and record.owner
 if type(owner)~="table"then return{ownerType="NONE",ownerId=nil}end
 local isTransfer=owner==Sync.activeTransfer or(not owner.activityHandoff and(owner.kind=="FETCH"or owner.kind=="SEND"or owner.kind=="RECEIVE"))
 local job=isTransfer and owner.job or owner
 local ownerType=isTransfer and("TRANSFER_"..tostring(owner.kind or"UNKNOWN"))or(owner.activityHandoff and"CATCHUP_HANDOFF"or"UNKNOWN")
 return{ownerType=ownerType,ownerId=owner.requestId or owner.transmissionId or owner.objectId or owner.entity,requestId=owner.requestId or(job and job.requestId),domain=owner.activityDomain or owner.block or owner.domain,entity=owner.entity or owner.objectId or(job and job.entity),source=owner.selectedSource or owner.sender or(job and job.selectedSource),catchUpJobState=job and job.state,catchUpJobId=job and job.requestId}
end
local function activityTransition(record,transition,reason)
 local owner=activityOwner(record);record.lastTransition=transition;record.lastTransitionAt=now();record.lastReason=reason
 log("DEBUG","activity","Sync activity transition",{transition=transition,activityId=record.id,domain=owner.domain or(record.details and record.details.domain),ownerType=owner.ownerType,ownerId=owner.ownerId,entity=owner.entity,requestId=owner.requestId or(record.details and record.details.requestId),source=owner.source,phase=record.owner and record.owner.phase or(record.details and record.details.phase),ownerLiveness=record.activeReason,createdAt=record.createdAt,lastTransitionAt=record.lastTransitionAt,reason=reason})
end
function Sync:IsTransferActivityAuthoritative(transfer)
 if not transfer or self.activeTransfer~=transfer then return false,"NOT_ACTIVE_TRANSFER"end
 if transfer.kind=="FETCH"then
  if transfer.receiveId and self.pendingPayloads[transfer.receiveId]then return true,"MATCHED_PAYLOAD_PENDING"end
  if transfer.processing==true and transfer.phase=="VALIDATE_COMMIT"then return true,"RECEIVE_PROCESSING"end
  if transfer.awaitingResponse==true and transfer.timeoutTimer~=nil and(tonumber(transfer.timeoutAt)or 0)>now()then return true,"FETCH_TIMEOUT_ARMED"end
  return false,"FETCH_WITHOUT_TIMEOUT_OR_PAYLOAD"
 end
 if transfer.kind=="SEND"then
  if tonumber(transfer.pendingTransmissions or 0)>0 then return true,"COMMS_TRANSMISSION_PENDING"end
  for transmissionId in pairs(transfer.transmissionIds or{})do if HolyStorm.Comms and type(HolyStorm.Comms.IsTransmissionActive)=="function"and HolyStorm.Comms:IsTransmissionActive(transmissionId)==true then return true,"COMMS_TRANSMISSION_ACTIVE"end end
  if transfer.transmissionId and HolyStorm.Comms and type(HolyStorm.Comms.IsTransmissionActive)=="function"and HolyStorm.Comms:IsTransmissionActive(transfer.transmissionId)==true then return true,"COMMS_TRANSMISSION_ACTIVE"end
  return false,"SEND_WITHOUT_ACTIVE_TRANSMISSION"
 end
 if transfer.kind=="RECEIVE"then
  if transfer.processing==true and transfer.phase=="VALIDATE_COMMIT"then return true,"RECEIVE_PROCESSING"end
  if transfer.receiveId and self.pendingPayloads[transfer.receiveId]then return true,"MATCHED_PAYLOAD_PENDING"end
  return false,"RECEIVE_WITHOUT_PENDING_WORKER"
 end
 return false,"UNKNOWN_TRANSFER_KIND"
end
function Sync:IsCatchUpHandoffAuthoritative(job)
 if not job or job.activityHandoff~=true or job.handoffProcessing~=true or not job.activityId then return false,"HANDOFF_NOT_MARKED"end
 if job.state~="DISPATCHING"then return false,"HANDOFF_JOB_NOT_DISPATCHING"end
 for _,queued in ipairs(self.catchUpJobs)do if queued==job then return false,"HANDOFF_JOB_QUEUED"end end
 return true,"SOURCE_HANDOFF_DISPATCHING"
end
function Sync:BeginActivity(details,isActive,owner)
 if type(isActive)~="function"then return nil,"ACTIVITY_OWNER_REQUIRED"end
 details=type(details)=="table"and details or{};self.activitySequence=self.activitySequence+1
 local id=string.format("SYNC-ACT-%08X-%04X",now()%0xFFFFFFFF,self.activitySequence%0xFFFF)
 local createdAt=now();local startedAt=tonumber(details.startedAt)or createdAt;local record={id=id,details=copy(details),startedAt=startedAt,createdAt=createdAt,isActive=isActive,owner=owner}
 self.activeActivities[id]=record;if type(owner)=="table"then owner.activityId=id end;activityTransition(record,"BEGIN","ACTIVITY_REGISTERED")
 self:NotifyActivity(true);return id
end
function Sync:BeginTransferActivity(transfer)
 if not transfer then return nil end
 local id=transfer.activityId
 if id and self.activeActivities[id]then
  local record=self.activeActivities[id];local previousOwner=record.owner;record.owner=transfer;record.isActive=function()return Sync:IsTransferActivityAuthoritative(transfer)end
  if previousOwner~=transfer then activityTransition(record,"OWNER_CHANGE","TRANSFER_OWNER_ASSIGNED")end
 else
  id=self:BeginActivity({domain=transfer.activityDomain or transfer.domain,entity=transfer.entity or transfer.objectId,characterUUID=transfer.characterUUID,direction=transfer.direction,phase=transfer.phase,startedAt=transfer.startedAt},function()return Sync:IsTransferActivityAuthoritative(transfer)end,transfer)
 end
 transfer.activityId=id;return id
end
function Sync:EndActivity(activityId,reason,suppressNotify)
 if not activityId then return false end;local record=self.activeActivities[activityId];if not record then return false end
 self.activeActivities[activityId]=nil;local owner=record.owner
 activityTransition(record,reason=="ACTIVITY_RECONCILED_STALE"and"ORPHAN_RELEASE"or"END",reason or"ACTIVITY_ENDED")
 if type(owner)=="table"and owner.activityId==activityId then owner.activityId=nil;if owner.activityHandoff then owner.activityHandoff=nil end;owner.handoffProcessing=nil end
 if not suppressNotify then self:NotifyActivity(true,true)end
 return true
end
function Sync:ReconcileActivity(reason)
 if self.reconcilingActivity then return false,self.activityStateMismatch end
 self.reconcilingActivity=true;local stale,active={},0;local changed=false
 local transfer=self.activeTransfer
 if transfer and(not transfer.activityId or not self.activeActivities[transfer.activityId])then
  if self:IsTransferActivityAuthoritative(transfer)then self:BeginTransferActivity(transfer);changed=true
  else self:ReleaseTransfer(false,"ACTIVITY_RECONCILED_STALE",transfer);changed=true end
 end
 for id,record in pairs(self.activeActivities)do
  local ok,value,livenessReason=false,false,nil;if type(record.isActive)=="function"then ok,value,livenessReason=pcall(record.isActive)end
  record.activeReason=ok and livenessReason or(ok and"OWNER_INACTIVE"or"OWNER_CHECK_ERROR")
  if ok and value==true then active=active+1 else stale[#stale+1]={id=id,record=record,reason=record.activeReason}end
 end
 local mismatch=self.activityPublishedActive==true and active==0
 self.activityStateMismatch=mismatch
 if mismatch and not self.activityMismatchLogged then
  self.activityMismatchLogged=true;log("WARN","activity","Published Sync activity has no authoritative runtime operation",{reason=reason or"STATE_RECONCILIATION",activityCount=active,registeredActivities=HolyStorm.Utils.TableCount(self.activeActivities),activeTransfer=self.activeTransfer and self.activeTransfer.requestId,activeRequest=HolyStorm.Utils.TableCount(self.activeRequests),activeCatchUpJob=self.activeTransfer and self.activeTransfer.job and self.activeTransfer.job.requestId})
 end
 changed=changed or #stale>0
 for _,entry in ipairs(stale)do
  local owner=entry.record.owner
  if type(owner)=="table"and owner==self.activeTransfer then
   self:ReleaseTransfer(false,"ACTIVITY_RECONCILED_STALE",owner)
  elseif type(owner)=="table"and owner.activityHandoff and owner.activityId==entry.id then
   self:EndActivity(entry.id,"ACTIVITY_RECONCILED_STALE",true)
  else
   local ownerInfo=activityOwner(entry.record)
   log("WARN","activity","Sync activity owner is no longer progress-capable; releasing registration",{transition="ORPHAN_RELEASE",activityId=entry.id,domain=ownerInfo.domain or(entry.record.details and entry.record.details.domain),ownerType=ownerInfo.ownerType,ownerId=ownerInfo.ownerId,requestId=ownerInfo.requestId or(entry.record.details and entry.record.details.requestId),reason=entry.reason})
   self:EndActivity(entry.id,"ACTIVITY_RECONCILED_STALE",true)
  end
 end
 self.reconcilingActivity=false
 if #stale>0 then self.activityNotifyDeferred=nil end
 return changed,mismatch
end
local function activitySnapshot(sync,characterUUID)
 local active,ids={},{};local current=now()
 for id,record in pairs(sync.activeActivities)do
  local details=record.details or{};local owner=record.owner;local ownerInfo=activityOwner(record);local transfer=type(owner)=="table"and owner.activityId==id and owner==sync.activeTransfer and owner or nil
  local job=type(owner)=="table"and owner.activityHandoff and owner.activityId==id and owner or nil
  local item={activityId=id,ownerType=ownerInfo.ownerType,ownerId=ownerInfo.ownerId,catchUpJobState=ownerInfo.catchUpJobState,catchUpJobId=ownerInfo.catchUpJobId,activeReason=record.activeReason,lastTransition=record.lastTransition,lastTransitionAt=record.lastTransitionAt,lastReason=record.lastReason,createdAt=record.createdAt,characterUUID=(transfer and transfer.characterUUID)or(job and job.characterUUID)or details.characterUUID,entity=(transfer and(transfer.entity or transfer.objectId))or(job and(job.entity or job.objectId))or details.entity,domain=(transfer and(transfer.activityDomain or transfer.domain))or(job and(job.block or job.domain))or details.domain,direction=(transfer and transfer.direction)or details.direction,phase=(transfer and transfer.phase)or(job and"SOURCE_FALLBACK")or details.phase,sender=(transfer and transfer.sender)or details.sender,receiver=(transfer and transfer.receiver)or(job and job.target)or details.receiver,source=ownerInfo.source,requestId=(transfer and transfer.requestId)or(job and job.requestId)or details.requestId,revision=(transfer and transfer.revision)or(job and job.requiredRevision)or details.revision,bytes=transfer and transfer.bytes or details.bytes,fragments=transfer and transfer.fragments or details.fragments,fragmentsTotal=transfer and transfer.fragmentsTotal or details.fragmentsTotal,retryCount=(transfer and transfer.retryCount)or(job and job.retryCount)or details.retryCount or 0,maxRetries=(transfer and transfer.maxRetries)or(job and job.maxRetries)or details.maxRetries or sync.maxRetries,priority=(transfer and transfer.priorityClass)or(job and job.priorityClass)or details.priority,startedAt=record.startedAt,activityAge=math.max(0,current-(tonumber(record.startedAt)or current)),queuePosition=1}
  if not characterUUID or item.characterUUID==characterUUID then active[#active+1]=item;ids[#ids+1]=id end
 end
 table.sort(active,function(left,right)if left.startedAt==right.startedAt then return left.activityId<right.activityId end;return left.startedAt<right.startedAt end);table.sort(ids)
 local queued=0;local queuePosition
 for _,job in ipairs(sync.catchUpJobs)do if job.state=="QUEUED"then queued=queued+1;if characterUUID and job.characterUUID==characterUUID and not queuePosition then queuePosition=queued end end end
 return{active=#active>0,activeOperations=active,activeActivityIds=ids,activityCount=#active,queuedJobs=queued,queuePosition=queuePosition,activityDomain=active[1]and active[1].domain,activityPhase=active[1]and active[1].phase,activityAge=active[1]and active[1].activityAge,activityStateMismatch=sync.activityStateMismatch==true}
end
function Sync:NotifyActivity(immediate,alreadyReconciled)
 if self.reconcilingActivity then self.activityNotifyDeferred=true;return end
 if not alreadyReconciled then self:ReconcileActivity("NOTIFY")end
 local function emit()
  Sync.activityNotifyTimer=nil;local activity=activitySnapshot(Sync)
  Sync.activityPublishedActive=activity.active;Sync.activityStateMismatch=false;Sync.activityMismatchLogged=false
  HolyStorm.Events:Emit("HS_SYNC_ACTIVITY_UPDATED",activity)
 end
 if immediate or not C_Timer or type(C_Timer.NewTimer)~="function"then if self.activityNotifyTimer then self.activityNotifyTimer:Cancel();self.activityNotifyTimer=nil end;emit();return end
 if self.activityNotifyTimer then return end
 self.activityNotifyTimer=C_Timer.NewTimer(.2,emit)
end
function Sync:GetActivity(characterUUID)
 local changed,mismatch=self:ReconcileActivity("ACTIVITY_READ");local activity=activitySnapshot(self,characterUUID);activity.activityStateMismatch=mismatch==true or activity.activityStateMismatch
 if changed and not self.notifyingActivity then self:NotifyActivity(true,true)end
 return activity
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
    local localMeta=domain.getMetadata(meta.objectId);local needed,decision=metadataNeedsFetch(domain,localMeta,meta)
    if needed then self:QueueFetch(domainId,meta.objectId,sender,localMeta and localMeta.version or-1,pending.reason or"DISCOVERY",localMeta and localMeta.revisionID,requestId,meta,{priorityClass=pending.priorityClass})
    else log("DEBUG","freshness",decision=="SAME_REVISION"and"Local revision already matches announced metadata"or decision=="LOCAL_NEWER"and"Local revision is newer; fetch suppressed"or"Announced metadata does not require a payload",{domain=domainId,objectId=meta.objectId,owner=meta.owner,localVersion=localMeta and localMeta.version,remoteVersion=meta.version,localRevision=localMeta and localMeta.revisionID,remoteRevision=meta.revisionID,decision=decision,sender=sender})end
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
 local domain=self.domains[domainId];local localMeta=domain and domain.getMetadata(meta.objectId);local needed,reason=metadataNeedsFetch(domain,localMeta,meta);if not needed then log("DEBUG","freshness",reason=="SAME_REVISION"and"Local revision already matches announced metadata"or reason=="LOCAL_NEWER"and"Local revision is newer; passive fetch suppressed"or"Metadata did not require passive healing",{domain=domainId,objectId=meta.objectId,owner=meta.owner,localVersion=localMeta and localMeta.version,remoteVersion=meta.version,localRevision=localMeta and localMeta.revisionID,remoteRevision=meta.revisionID,decision=reason,sender=sender});return false end;local delay=3+math.random()*5;HolyStorm.Tasks:Queue("Sync.PassiveRefresh",{mergeKey=key(domainId,meta.objectId),delay=delay,priority=95,triggerSource="PASSIVE_HEALING",metadata={domain=domainId,objectId=meta.objectId,sender=sender,owner=meta.owner,direct=meta.direct==true,version=meta.version,revisionID=meta.revisionID}});log("DEBUG","passive","Passive refresh scheduled",{domain=domainId,objectId=meta.objectId,owner=meta.owner,remoteVersion=meta.version,localVersion=localMeta and localMeta.version,revision=meta.revisionID});return true
end
function Sync:RunPassive(task)local m=task.metadata;local domain=self.domains[m.domain];if not domain then return false end;local localMeta=domain.getMetadata(m.objectId);local remoteMeta={owner=m.owner,version=m.version,revisionID=m.revisionID,direct=m.direct==true};local needed,reason=metadataNeedsFetch(domain,localMeta,remoteMeta);if not needed then return true end;return self:QueueFetch(m.domain,m.objectId,m.sender,localMeta and localMeta.version or-1,"PASSIVE_HEALING",localMeta and localMeta.revisionID,nil,remoteMeta)~=nil end
function Sync:GetOnlineName(guid)if type(guid)~="string"then return nil end;local guild=HolyStorm.Data.GuildStore:GetCurrent();local member=guild and guild.roster and guild.roster[guid];return member and member.online and member.name or nil end
function Sync:QueueFetch(domainId,objectId,target,knownVersion,reason,knownRevisionID,requestId,desiredMeta,options)
 local domain=self.domains[domainId];if not domain or not validId(objectId)or type(target)~="string"or target==""then return nil,"INVALID_FETCH"end
 desiredMeta=type(desiredMeta)=="table"and desiredMeta or{};options=options or{}
 local candidateGuid=desiredMeta.senderGuid or senderGuid(target);if isLocalSource(target,candidateGuid)then log("DEBUG","selection","Ignoring local player as sync payload source",{domain=domainId,objectId=objectId,sender=target,senderGuid=candidateGuid,requestId=requestId,reason="SELF_SOURCE"});return nil,"SELF_SOURCE"end
 pruneTerminalFetches(self);local version=desiredMeta.version;local revision=desiredMeta.revisionID;local dedupeKey=transferKey(domainId,objectId,version,revision);local job=self.catchUpIndex[dedupeKey]
 if not job then local activeJob=self.activeTransfer and self.activeTransfer.job;if activeJob and activeJob.domain==domainId and activeJob.objectId==objectId and(version==nil or activeJob.requiredVersion==nil or tonumber(activeJob.requiredVersion)==tonumber(version)and activeJob.requiredRevision==revision)then job=activeJob end end
 if not job then for _,candidateJob in ipairs(self.catchUpJobs)do if candidateJob.domain==domainId and candidateJob.objectId==objectId and(candidateJob.state=="QUEUED"or candidateJob.state=="RUNNING")then if version==nil or candidateJob.requiredVersion==nil or tonumber(candidateJob.requiredVersion)==tonumber(version)and(candidateJob.requiredRevision==revision)then job=candidateJob;break end end end end
 if job and job.requiredVersion==nil and version~=nil then self.catchUpIndex[job.key]=nil;job.key=dedupeKey;job.requiredVersion=version;job.requiredRevision=revision;self.catchUpIndex[dedupeKey]=job end
 local class=options.priorityClass or priorityClass(reason);local candidate={sender=target,senderGuid=candidateGuid,owner=desiredMeta.owner,direct=desiredMeta.direct==true,version=version,revisionID=revision,meta=copy(desiredMeta)}
 local terminal=self.terminalFetches[dedupeKey];local jobCreated=false
 if not job and terminal then
  if class=="USER_INTERACTIVE"then self.terminalFetches[dedupeKey]=nil;log("INFO","selection","Explicit refresh cleared terminal Sync source suppression",{domain=domainId,entity=objectId,revision=revision,dedupKey=readableDedupKey(dedupeKey),requeueReason=reason,queueLength=#self.catchUpJobs})
  elseif sourceListed(terminal.exhaustedSources,target,candidateGuid)then
   log("DEBUG","suppression","Unchanged exhausted Sync source suppressed",{domain=domainId,entity=objectId,revision=revision,dedupKey=readableDedupKey(dedupeKey),source=target,sourceGuid=candidateGuid,terminalReason=terminal.terminalReason,requeueReason=reason,discoveryGeneration=terminal.discoveryGeneration,queueLength=#self.catchUpJobs});return nil,"SOURCE_EXHAUSTED"
  else
   job={key=dedupeKey,kind="FETCH",domain=domainId,objectId=objectId,entity=objectId,requiredVersion=version,requiredRevision=revision,knownVersion=knownVersion,knownRevisionID=knownRevisionID,sourceCandidates={},allSourceCandidates=copy(terminal.sourceCandidates or{}),exhaustedSources=copy(terminal.exhaustedSources or{}),sourceAttempts={},priorityClass=class,priority=priorities[class]or priorities.BACKGROUND_CATCHUP,state="QUEUED",queuedAt=now(),retryCount=0,maxRetries=self.maxRetries,requestId=requestId or self:NewRequestId(),reason=reason or"DISCOVERY",requeueReason="NEW_SOURCE",discoveryGeneration=(terminal.discoveryGeneration or 0)+1,notBefore=now()+(tonumber(options.notBeforeDelay)or((class=="USER_INTERACTIVE")and.15 or 1.5))};jobCreated=true
   self.catchUpIndex[dedupeKey]=job;self.catchUpJobs[#self.catchUpJobs+1]=job;recordJobMetric(self,job,"requested");log("INFO","selection","New source reopened terminal Sync job",{domain=domainId,entity=objectId,revision=revision,source=target,dedupKey=readableDedupKey(dedupeKey),discoveryGeneration=job.discoveryGeneration,queueLength=#self.catchUpJobs})
  end
 end
 if not job then
  if#self.catchUpJobs>=self.catchUpLimit then log("WARN","backpressure","Sync catch-up queue is full; job deferred",{domain=domainId,objectId=objectId,revision=revision,queueLimit=self.catchUpLimit,reason="QUEUE_LIMIT"});return nil,"QUEUE_FULL"end
  local characterUUID,block=splitCharacterId(objectId);job={key=dedupeKey,kind="FETCH",domain=domainId,objectId=objectId,characterUUID=characterUUID,block=block,entity=objectId,requiredVersion=version,requiredRevision=revision,knownVersion=knownVersion,knownRevisionID=knownRevisionID,sourceCandidates={},allSourceCandidates={},exhaustedSources={},sourceAttempts={},priorityClass=class,priority=priorities[class]or priorities.BACKGROUND_CATCHUP,state="QUEUED",queuedAt=now(),retryCount=0,maxRetries=self.maxRetries,requestId=requestId or self:NewRequestId(),reason=reason or"DISCOVERY",requeueReason=reason or"DISCOVERY",discoveryGeneration=1,notBefore=now()+(tonumber(options.notBeforeDelay)or((class=="USER_INTERACTIVE")and.15 or 1.5))};jobCreated=true
  self.catchUpIndex[dedupeKey]=job;self.catchUpJobs[#self.catchUpJobs+1]=job;recordJobMetric(self,job,"requested")
 end
 job.exhaustedSources=job.exhaustedSources or{}
 local found=false;local candidateAdded=false;local newJob=jobCreated
 if not sourceExhausted(job,candidate)then
  for _,source in ipairs(job.sourceCandidates)do if sameSource(source.sender,source.senderGuid,candidate.sender,candidate.senderGuid)then found=true;source.direct=source.direct or candidate.direct;if candidate.version and(not source.version or candidate.version>source.version)then source.version=candidate.version;source.revisionID=candidate.revisionID;source.owner=candidate.owner;source.meta=candidate.meta end;break end end
  if not found then if#job.sourceCandidates<5 then job.sourceCandidates[#job.sourceCandidates+1]=candidate;candidateAdded=true elseif candidate.direct then for index,source in ipairs(job.sourceCandidates)do if not source.direct then job.sourceCandidates[index]=candidate;candidateAdded=true;break end end end end
  if not sourceListed(job.allSourceCandidates,candidate.sender,candidate.senderGuid)and#job.allSourceCandidates<16 then job.allSourceCandidates[#job.allSourceCandidates+1]=copy(candidate)end
 end
 if(priorities[class]or 90)<job.priority then job.priorityClass=class;job.priority=priorities[class];job.notBefore=math.min(job.notBefore,now()+.15)end
 if job.state~="RUNNING"and job.state~="DISPATCHING"and requestId then job.requestId=requestId end
 if candidateAdded and not newJob and job.state=="QUEUED"then job.requeueReason="NEW_SOURCE"end
 self:QueuePump(math.max(0,job.notBefore-now()));self:NotifyActivity();return job.key,"MERGED"
end
function Sync:QueueOutbound(domainId,data,sender,meta)
 if type(sender)~="string"or sender==""then return nil,"INVALID_RECIPIENT"end
 local senderId=senderGuid(sender);local recipientKey=tostring(senderId or string.lower(sender));local baseKey=table.concat({"SEND",domainId,data.objectId,tostring(meta.owner or""),tostring(meta.version or"?"),tostring(meta.revisionID or"")},"\030")
 local job=self.outboundCoalescing[baseKey];local state="MERGED"
 if not job or job.state~="QUEUED"or not job.recipients[recipientKey]and#job.recipientOrder>=self.maxCoalescedRecipients then
  if#self.catchUpJobs>=self.catchUpLimit then return nil,"QUEUE_FULL"end
  self.outboundSequence=self.outboundSequence+1;local characterUUID,block=splitCharacterId(data.objectId);local keyValue=baseKey.."\030B"..self.outboundSequence
  job={key=keyValue,coalesceKey=baseKey,kind="SEND",domain=domainId,objectId=data.objectId,characterUUID=characterUUID,block=block,entity=data.objectId,target=sender,requiredOwner=meta.owner,requiredVersion=meta.version,requiredRevision=meta.revisionID,requestId=data.requestId or self:NewRequestId(),recipients={},recipientOrder={},priorityClass="BACKGROUND_CATCHUP",priority=priorities.BACKGROUND_CATCHUP,state="QUEUED",queuedAt=now(),retryCount=0,maxRetries=self.maxRetries,reason="REQUEST_RESPONSE",notBefore=now()+self.requestCoalesceWindow}
  self.outboundCoalescing[baseKey]=job;self.catchUpIndex[keyValue]=job;self.catchUpJobs[#self.catchUpJobs+1]=job;recordJobMetric(self,job,"requested");state="QUEUED"
 end
 local recipient=job.recipients[recipientKey]
 if not recipient then recipient={key=recipientKey,guid=senderId,name=sender,requestIds={}};job.recipients[recipientKey]=recipient;job.recipientOrder[#job.recipientOrder+1]=recipientKey
 else recipient.name=sender;recipient.guid=senderId or recipient.guid end
 local requestId=data.requestId or self:NewRequestId();local known=false;for _,existing in ipairs(recipient.requestIds)do if existing==requestId then known=true;break end end
 if not known then if#recipient.requestIds>=self.maxRequestIdsPerRecipient then table.remove(recipient.requestIds,1)end;recipient.requestIds[#recipient.requestIds+1]=requestId end
 if not job.requestId then job.requestId=requestId end;job.target=job.target or sender
 log("DEBUG","request",state=="MERGED"and"Fetch request merged into revision coalescing window"or"Fetch request opened revision coalescing window",{domain=domainId,objectId=data.objectId,owner=meta.owner,revision=meta.revisionID,receiver=sender,receiverGuid=senderId,receiverCount=#job.recipientOrder,requestCount=#recipient.requestIds,window=self.requestCoalesceWindow,dedupKey=readableDedupKey(job.key),state=state})
 self:QueuePump(math.max(0,job.notBefore-now()));self:NotifyActivity();return job.key,state
end
function Sync:SendFetchResult(domainId,data,sender,result,reason,meta)
 if type(data)~="table"or not validId(data.requestId)or not validId(data.objectId)or type(sender)~="string"or sender==""then return false end
 local details={requestId=data.requestId,objectId=data.objectId,result=result,reason=reason}
 if meta then
  details.currentVersion=meta.version;details.currentRevisionID=meta.revisionID
  details.currentMetadata={objectId=data.objectId,owner=meta.owner,version=meta.version,revisionID=meta.revisionID,previousRevisionID=meta.previousRevisionID,updatedAt=meta.updatedAt,target=meta.target,scope=meta.scope,sessionId=meta.sessionId}
 end
 local queued=self:QueueEnvelope("FETCH_RESULT",domainId,details,"WHISPER",sender,45)
 log(queued and"DEBUG"or"WARN","request",queued and"Sync fetch result queued"or"Sync fetch result could not be queued",{domain=domainId,entity=data.objectId,revision=data.revisionID,requestId=data.requestId,result=result,reason=reason,receiver=sender})
 return queued~=nil and queued~=false
end
function Sync:OnFetch(domainId,data,sender)
 if type(data)~="table"or not validId(data.objectId)or not validId(data.requestId)then return false end
 if data.revisionID~=nil and not validId(data.revisionID)or data.knownVersion~=nil and not tonumber(data.knownVersion)then self:SendFetchResult(domainId,data,sender,"INVALID","INVALID_REQUEST_METADATA");return false end
 local domain=self.domains[domainId];if not domain then self:SendFetchResult(domainId,data,sender,"UNAVAILABLE","UNKNOWN_DOMAIN");return false end
 local metadataOK,meta=pcall(domain.getMetadata,data.objectId);if not metadataOK then self:SendFetchResult(domainId,data,sender,"UNAVAILABLE","METADATA_LOOKUP_FAILED");return false end
 if not meta then self:SendFetchResult(domainId,data,sender,"NOT_FOUND","OBJECT_NOT_FOUND");return false end
 local recipientGuid=senderGuid(sender)
 if domain.canShare then local authOK,canShare,shareReason=pcall(domain.canShare,meta,recipientGuid,sender,"fetch");if not authOK then self:SendFetchResult(domainId,data,sender,"UNAVAILABLE","AUTHORIZATION_CHECK_FAILED");return false elseif not canShare then local result=shareReason=="MODULE_DISABLED"and"UNAVAILABLE"or shareReason=="NOT_FOUND"and"NOT_FOUND"or shareReason=="STALE"and"STALE"or shareReason=="INVALID"and"INVALID"or"NOT_VISIBLE";log("WARN","privacy","Payload request rejected by outbound authorization",{domain=domainId,objectId=data.objectId,receiver=sender,reason=shareReason,result=result});self:SendFetchResult(domainId,data,sender,result,shareReason or"SOURCE_AUTHORIZATION",meta);return false end end
 if data.revisionID and meta.revisionID~=data.revisionID then self:SendFetchResult(domainId,data,sender,"STALE","REVISION_MISMATCH",meta);return false end
 local sibling=domain.freshness=="revision-chain"and data.knownRevisionID and meta.revisionID~=data.knownRevisionID and tonumber(meta.version)==tonumber(data.knownVersion)
 if((tonumber(meta.version)or 0)<=(tonumber(data.knownVersion)or-1)and not sibling)then self:SendFetchResult(domainId,data,sender,"STALE","SOURCE_NOT_NEWER",meta);return false end
 local queueOK,queued,queueReason=pcall(self.QueueOutbound,self,domainId,data,sender,meta);if not queueOK or not queued then self:SendFetchResult(domainId,data,sender,"UNAVAILABLE",queueOK and(queueReason or"OUTBOUND_QUEUE_FAILED")or"OUTBOUND_QUEUE_ERROR",meta);return false end
 return true
end
function Sync:OnFetchResult(domainId,data,sender)
 local transfer=self.activeTransfer
 if type(data)~="table"or not validId(data.requestId)or not validId(data.objectId)or not transfer or transfer.kind~="FETCH"or transfer.awaitingResponse~=true or not transfer.timeoutTimer or transfer.domain~=domainId or transfer.objectId~=data.objectId or transfer.requestId~=data.requestId or not samePlayerName(transfer.selectedSource,sender)then
  log("DEBUG","request","Unmatched or late Sync fetch result ignored",{domain=domainId,entity=type(data)=="table"and data.objectId,requestId=type(data)=="table"and data.requestId,sender=sender,activeRequestId=transfer and transfer.requestId,result="UNMATCHED_REQUEST"});return false,"UNMATCHED_REQUEST"
 end
 local resolved=senderGuid(sender);if transfer.selectedSourceGuid and resolved and transfer.selectedSourceGuid~=resolved then return false,"SOURCE_MISMATCH"end
 local allowed={NOT_FOUND=true,NOT_VISIBLE=true,STALE=true,INVALID=true,UNAVAILABLE=true};if not allowed[data.result]then return false,"INVALID_RESULT"end
 if transfer.timeoutTimer then transfer.timeoutTimer:Cancel();transfer.timeoutTimer=nil end;transfer.awaitingResponse=false
 log("WARN","request","Sync fetch source returned a correlated negative result",{domain=domainId,entity=data.objectId,revision=transfer.revision,requestId=data.requestId,source=sender,result=data.result,reason=data.reason})
 local current=type(data.currentMetadata)=="table"and data.currentMetadata or nil
 if data.result=="STALE"and current and tonumber(current.version)and validId(current.revisionID)and current.revisionID~=transfer.revision then
  current=copy(current);current.senderGuid=senderGuid(sender);current.direct=current.owner==current.senderGuid
  local job=transfer.job;self:QueueFetch(domainId,data.objectId,sender,job and job.knownVersion or-1,job and job.reason or"DISCOVERY",job and job.knownRevisionID,data.requestId,current,{priorityClass=job and job.priorityClass,requeueReason="NEWER_SOURCE_REVISION"})
 end
 return self:ReleaseTransfer(false,"FETCH_RESULT:"..data.result,transfer)
end
function Sync:BestSource(job)
 local best;for _,candidate in ipairs(job.sourceCandidates or{})do if not sourceExhausted(job,candidate)and not isLocalSource(candidate.sender,candidate.senderGuid)then if not best or(candidate.direct and not best.direct)then best=candidate elseif candidate.direct==best.direct then local decision=HolyStorm.PlayerData:CompareMetadata(best.meta or{},candidate.meta or{});if decision>0 then best=candidate end end end end;return best
end
function Sync:ActivityPhase(transfer,phase)
 if not transfer then return end;local previous=transfer.phase;transfer.phase=phase;transfer.lastActivityAt=now()
 if previous~=phase and transfer.activityId then local record=self.activeActivities[transfer.activityId];if record then activityTransition(record,"PHASE_CHANGE",tostring(previous or"UNKNOWN").."->"..tostring(phase))end end
 self:NotifyActivity()
end
function Sync:ReleaseTransfer(result,reason,expectedTransfer)
 local transfer=self.activeTransfer;if not transfer or expectedTransfer and transfer~=expectedTransfer then return false end
 if transfer.timeoutTimer then transfer.timeoutTimer:Cancel();transfer.timeoutTimer=nil end
 if transfer.kind=="FETCH"then self:RememberRetiredRequest(transfer.requestId,reason or"TRANSFER_TERMINATED")end
 transfer.awaitingResponse=false;transfer.processing=false;transfer.sendPending=false
 local job=transfer.job;self.activeTransfer=nil;local preserveActivity=false
 local ok,releaseError=pcall(function()
  if not job then return end
  local retryLimit=tonumber(job.maxRetries)or self.maxRetries
  if result==false and transfer.kind=="FETCH"then
   local immediateSourceFailure=type(reason)=="string"and reason:match("^FETCH_RESULT:")~=nil
   if not immediateSourceFailure and job.retryCount<retryLimit then
    job.retryCount=job.retryCount+1;recordRetry(self,job);job.state="QUEUED";job.notBefore=now()+math.min(16,2^job.retryCount);self.catchUpJobs[#self.catchUpJobs+1]=job
    log("WARN","retries","Sync fetch timed out or failed; retrying the same source",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,recipient=job.target,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,result=reason or"TRANSFER_FAILED"})
   else
    exhaustSource(job,transfer.selectedSource,transfer.selectedSourceGuid);job.retryCount=0;job.terminalReason=reason or"SOURCE_EXHAUSTED"
    local nextSource=self:BestSource(job)
    if nextSource then
     recordRetry(self,job);job.state="QUEUED";job.notBefore=now();job.activityHandoff=true;job.handoffProcessing=true;job.activityId=transfer.activityId;preserveActivity=job.activityId~=nil
     job.requeueReason="SOURCE_FALLBACK";log("WARN","selection","Sync fetch source exhausted; trying another source",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,nextSource=nextSource.sender,priority=job.priorityClass,maxRetries=retryLimit,result=reason or"TRANSFER_FAILED",dedupKey=readableDedupKey(job.key),candidateSources=sourceDiagnostics(job.allSourceCandidates),exhaustedSources=exhaustedSourceDiagnostics(job.exhaustedSources),queueLengthBefore=#self.catchUpJobs,queueLengthAfter=#self.catchUpJobs+1,discoveryGeneration=job.discoveryGeneration})
    else
     job.state="FAILED";recordJobMetric(self,job,"failed");self.catchUpIndex[job.key]=nil;rememberTerminalFetch(self,job,job.terminalReason)
     log("WARN","selection","Sync fetch skipped after all sources were exhausted; existing snapshot retained",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,result=reason or"NO_SOURCE",dedupKey=readableDedupKey(job.key),candidateSources=sourceDiagnostics(job.allSourceCandidates),exhaustedSources=exhaustedSourceDiagnostics(job.exhaustedSources),queueLength=#self.catchUpJobs,discoveryGeneration=job.discoveryGeneration})
    end
   end
  elseif result==false and job.retryCount<retryLimit then
   job.retryCount=job.retryCount+1;recordRetry(self,job);job.state="QUEUED";job.notBefore=now()+math.min(16,2^job.retryCount);self.catchUpJobs[#self.catchUpJobs+1]=job
   log("WARN","retries","Sync domain transfer deferred for retry",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,recipient=job.target,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,result=reason or"TRANSFER_FAILED"})
  else
   job.state=result==false and"FAILED"or"COMPLETED";recordJobMetric(self,job,result==false and"failed"or"completed");self.catchUpIndex[job.key]=nil
   log(result==false and"WARN"or"DEBUG","payload",result==false and"Sync domain transfer failed; existing snapshot retained"or"Sync domain transfer completed",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=job.requiredRevision,source=transfer.selectedSource,recipient=job.target,priority=job.priorityClass,retryCount=job.retryCount,maxRetries=retryLimit,duration=now()-(transfer.startedAt or now()),bytes=transfer.bytes,fragments=transfer.fragmentsTotal,result=result==false and(reason or"FAILED")or"COMPLETED"})
  end
 end)
 local activity=self.activeActivities[transfer.activityId]
 if preserveActivity and activity then
  activity.owner=job;activity.isActive=function()return Sync:IsCatchUpHandoffAuthoritative(job)end
 else self:EndActivity(transfer.activityId,reason or"TRANSFER_TERMINATED",true)end
 if not ok then log("ERROR","activity","Sync transfer finalization failed",{requestId=transfer.requestId,domain=transfer.domain,objectId=transfer.objectId,error=tostring(releaseError),result=reason or"FINALIZATION_ERROR"})end
 if preserveActivity then
  local started,startResult=pcall(function()return self:StartFetch(job)end)
  if not started then
   self:EndActivity(job.activityId,"SOURCE_FALLBACK_START_ERROR",true);job.activityId=nil;job.activityHandoff=nil;job.handoffProcessing=nil;job.state="FAILED";self.catchUpIndex[job.key]=nil
   log("ERROR","activity","Alternate Sync source could not be started",{requestId=job.requestId,domain=job.domain,objectId=job.objectId,error=tostring(startResult),result="SOURCE_FALLBACK_START_ERROR"})
  end
 end
 self:NotifyActivity(true,true);if not self.activeTransfer then self:QueuePump()end;if#self.pendingPayloadOrder>0 then self:SchedulePayloadPump()end;return true
end
function Sync:RetryTimedOut(requestId,expectedTransfer)
 local active=self.activeTransfer;if not active or active.requestId~=requestId or expectedTransfer and active~=expectedTransfer then return end
 log("WARN","retries","Sync payload response timed out",{requestId=requestId,objectId=active.objectId,characterUUID=active.characterUUID,domain=active.domain,source=active.selectedSource,retryCount=active.job and active.job.retryCount or 0,result="TIMEOUT"});self:ReleaseTransfer(false,"TIMEOUT",active)
end
function Sync:StartFetch(job)
 job.state="DISPATCHING"
 local source=self:BestSource(job)
 if not source then job.state="FAILED";recordJobMetric(self,job,"failed");self.catchUpIndex[job.key]=nil;self:EndActivity(job.activityId,"NO_SOURCE",true);job.activityId=nil;job.activityHandoff=nil;log("WARN","selection","No valid source remains for sync job",{requestId=job.requestId,objectId=job.objectId,domain=job.domain,result="NO_SOURCE"});self:NotifyActivity(true,true);self:QueuePump();return false end
 local domain=self.domains[job.domain];local localMeta=domain and domain.getMetadata(job.objectId)
 if not domain then job.state="FAILED";recordJobMetric(self,job,"failed");self.catchUpIndex[job.key]=nil;self:EndActivity(job.activityId,"UNKNOWN_DOMAIN",true);job.activityId=nil;job.activityHandoff=nil;log("WARN","backpressure","Sync job failed because its domain was unloaded",{requestId=job.requestId,objectId=job.objectId,domain=job.domain,result="UNKNOWN_DOMAIN"});self:NotifyActivity(true,true);self:QueuePump();return false end
 if job.requiredVersion~=nil then local offered={version=source.version or job.requiredVersion,revisionID=source.revisionID or job.requiredRevision,owner=source.owner,direct=source.direct};local needed=metadataNeedsFetch(domain,localMeta,offered);if not needed then job.state="COMPLETED";recordJobMetric(self,job,"completed");self.catchUpIndex[job.key]=nil;self:EndActivity(job.activityId,"ALREADY_CURRENT",true);job.activityId=nil;job.activityHandoff=nil;self:NotifyActivity(true,true);self:QueuePump();return true end end
 job.requestId=self:NewRequestId();local sourceKey=tostring(source.senderGuid or string.lower(source.sender));job.sourceAttempts=job.sourceAttempts or{};job.sourceAttempts[sourceKey]=(job.sourceAttempts[sourceKey]or 0)+1;job.attempt=job.sourceAttempts[sourceKey]
 local transfer={kind="FETCH",job=job,key=job.key,objectId=job.objectId,entity=job.entity,characterUUID=job.characterUUID,activityDomain=job.block or job.domain,domain=job.domain,direction="RECEIVE",phase="REQUEST",sender=source.sender,receiver=playerName(),selectedSource=source.sender,selectedSourceGuid=source.senderGuid,requestId=job.requestId,revision=source.revisionID or job.requiredRevision,priorityClass=job.priorityClass,retryCount=job.retryCount,maxRetries=job.maxRetries,startedAt=job.activityStartedAt or now(),bytes=0,fragments=0,preparing=true,awaitingResponse=false}
 self.lastSelection={domain=job.domain,objectId=job.objectId,selectedSource=source.sender,selectedSourceGuid=source.senderGuid,owner=source.owner,direct=source.direct,reason=job.reason,candidateCount=#(job.sourceCandidates or{}),at=now()};log("DEBUG","selection","Selecting payload source",{domain=job.domain,objectId=job.objectId,characterUUID=job.characterUUID,block=job.block,version=source.version or job.requiredVersion,revision=source.revisionID or job.requiredRevision,requestId=job.requestId,reason=job.reason,selectedSource=source.sender,selectedSourceGuid=source.senderGuid,originalOwner=source.owner,relay=source.direct~=true,candidateCount=#(job.sourceCandidates or{}),attempt=job.attempt,dedupKey=readableDedupKey(job.key),discoveryGeneration=job.discoveryGeneration,requeueReason=job.requeueReason,queueLength=#self.catchUpJobs})
 transfer.activityId=job.activityHandoff and job.activityId or nil;job.state="RUNNING";job.startedAt=transfer.startedAt;job.selectedSource=source.sender;job.activityStartedAt=nil;recordJobMetric(self,job,"started");self.activeTransfer=transfer
 transfer.attempt=job.attempt;transfer.timeoutAt=now()+30;local transferRequestId=transfer.requestId;transfer.timeoutTimer=C_Timer.NewTimer(30,function()Sync:RetryTimedOut(transferRequestId,transfer)end);transfer.awaitingResponse=true;transfer.preparing=false;self:BeginTransferActivity(transfer);job.activityHandoff=nil;job.handoffProcessing=nil;job.activityId=nil
 local sent=self:QueueEnvelope("FETCH",job.domain,{objectId=job.objectId,knownVersion=localMeta and localMeta.version or job.knownVersion,knownRevisionID=localMeta and localMeta.revisionID or job.knownRevisionID,revisionID=transfer.revision,reason=job.reason,requestId=job.requestId},"WHISPER",source.sender,job.priorityClass=="USER_INTERACTIVE"and 35 or 55)
 if not sent then return self:ReleaseTransfer(false,"FETCH_QUEUE_REJECTED",transfer)end
 self:NotifyActivity();return true
end
local function latestRecipientRequest(recipient)
 local ids=recipient and recipient.requestIds or{};return ids[#ids]
end
function Sync:SendResultToRecipients(job,result,reason,meta,recipients)
 local sent=false
 for _,entry in ipairs(recipients or job.recipientOrder or{})do
  local recipient=type(entry)=="string"and job.recipients[entry]or entry
  local requestId=latestRecipientRequest(recipient)
  if recipient and requestId then sent=self:SendFetchResult(job.domain,{objectId=job.objectId,requestId=requestId,revisionID=job.requiredRevision},recipient.name,result,reason,meta)or sent end
 end
 return sent
end
function Sync:CanBroadcastToGuild(domain,meta,job,recipients)
 if not IsInGuild()then return false,"GUILD_UNAVAILABLE"end
 local channel=domain.getChannel and domain.getChannel(meta,"response")or"GUILD";if channel~="GUILD"then return false,"NO_SHARED_GUILD_CHANNEL"end
 local guild=HolyStorm.Data.GuildStore and HolyStorm.Data.GuildStore:GetCurrent();local roster=guild and guild.roster
 if type(roster)~="table"then return false,"ROSTER_UNAVAILABLE"end
 local rosterByName={};for _,member in pairs(roster)do if type(member)=="table"and type(member.name)=="string"then rosterByName[string.lower(member.name)]=member end end
 for _,recipient in ipairs(recipients)do
  local member=(recipient.guid and roster[recipient.guid])or rosterByName[string.lower(recipient.name or"")]
  if not member or member.online~=true then return false,"REQUESTER_NOT_CONFIRMED_ONLINE_IN_GUILD_ROSTER"end
 end
 if domain.canBroadcast then
  local ok,allowed,reason=pcall(domain.canBroadcast,meta,roster,recipients)
  if not ok then return false,"BROADCAST_POLICY_ERROR"elseif allowed~=true then return false,reason or"BROADCAST_POLICY_DENIED"end
  return true,"DOMAIN_BROADCAST_POLICY"
 end
 if domain.canShare then
  for guid,member in pairs(roster)do
   if type(member)~="table"or type(member.name)~="string"then return false,"ROSTER_IDENTITY_INCOMPLETE"end
   if member.online~=true and member.online~=false then return false,"ROSTER_ONLINE_STATE_UNKNOWN"end
   if member.online==true then
    local ok,allowed=pcall(domain.canShare,meta,guid,member.name,"fetch")
    if not ok or allowed~=true then return false,"PRIVACY_PERMISSION_FILTER"end
   end
  end
 elseif not domain.broadcastSafe then return false,"BROADCAST_NOT_DECLARED_SAFE"end
 return true,"ALL_GUILD_RECIPIENTS_AUTHORIZED"
end
function Sync:StartSend(job,transfer)
 transfer=transfer or self.activeTransfer;if not transfer or self.activeTransfer~=transfer then return false end
 transfer.kind="SEND";transfer.job=job;transfer.key=job.key;transfer.objectId=job.objectId;transfer.entity=job.entity;transfer.characterUUID=job.characterUUID;transfer.activityDomain=job.block or job.domain;transfer.domain=job.domain;transfer.direction="SEND";transfer.phase="PREPARING";transfer.sender=playerName();transfer.receiver=#(job.recipientOrder or{})==1 and job.target or"Guild request cohort";transfer.requestId=job.requestId;transfer.priorityClass=job.priorityClass;transfer.retryCount=job.retryCount;transfer.maxRetries=job.maxRetries;transfer.startedAt=transfer.startedAt or now();transfer.preparing=true
 if self.outboundCoalescing[job.coalesceKey]==job then self.outboundCoalescing[job.coalesceKey]=nil end
 local domain=self.domains[job.domain];local meta=domain and domain.getMetadata(job.objectId)
 local function rejectAll(reason,result,currentMeta)
  self:SendResultToRecipients(job,result or"UNAVAILABLE",reason,currentMeta)
  log("WARN","request","Coalesced payload demand ended without a payload",{domain=job.domain,objectId=job.objectId,owner=job.requiredOwner,revision=job.requiredRevision,receiverCount=#(job.recipientOrder or{}),reason=reason,result=result})
  return self:ReleaseTransfer(true,reason,transfer)
 end
 if not domain or not meta then return rejectAll("OBJECT_CHANGED","NOT_FOUND",meta)end
 if meta.owner~=job.requiredOwner or tonumber(meta.version)~=tonumber(job.requiredVersion)or job.requiredRevision and meta.revisionID~=job.requiredRevision then return rejectAll("REVISION_CHANGED","STALE",meta)end
 local authorized={}
 for _,recipientKey in ipairs(job.recipientOrder or{})do
  local recipient=job.recipients[recipientKey];local allowed,shareReason=true,nil
  if domain.canShare then local authOK;authOK,allowed,shareReason=pcall(domain.canShare,meta,recipient.guid or senderGuid(recipient.name),recipient.name,"fetch");if not authOK then allowed=false;shareReason="AUTHORIZATION_CHECK_FAILED"end end
  if allowed==true then authorized[#authorized+1]=recipient
  else self:SendFetchResult(job.domain,{objectId=job.objectId,requestId=latestRecipientRequest(recipient),revisionID=job.requiredRevision},recipient.name,shareReason=="MODULE_DISABLED"and"UNAVAILABLE"or"NOT_VISIBLE",shareReason or"SOURCE_AUTHORIZATION",meta);log("WARN","privacy","Queued payload recipient no longer passes outbound authorization",{domain=job.domain,objectId=job.objectId,owner=meta.owner,revision=meta.revisionID,receiver=recipient.name,reason=shareReason or"SOURCE_AUTHORIZATION"})end
 end
 if #authorized==0 then log("DEBUG","payload","Payload suppressed because no authorized receiver still needs this revision",{domain=job.domain,objectId=job.objectId,owner=meta.owner,revision=meta.revisionID,requesterCount=#(job.recipientOrder or{}),reason="NO_AUTHORIZED_DEMAND"});return self:ReleaseTransfer(true,"NO_AUTHORIZED_DEMAND",transfer)end
 local broadcast=false;local broadcastReason="SINGLE_RECIPIENT"
 if #authorized>1 then broadcast,broadcastReason=self:CanBroadcastToGuild(domain,meta,job,authorized)end
 if #authorized>1 and not broadcast then log("INFO","privacy","Shared-channel payload broadcast withheld; using authorized whispers",{domain=job.domain,objectId=job.objectId,owner=meta.owner,revision=meta.revisionID,receiverCount=#authorized,reason=broadcastReason})end
 local payload=domain.export(job.objectId);if payload==nil then return rejectAll("EXPORT_FAILED","NOT_FOUND",meta)end
 local plans={}
 if broadcast then
  local ids={};for _,recipient in ipairs(authorized)do for _,requestId in ipairs(recipient.requestIds)do if#ids<self.maxCoalescedRecipients*self.maxRequestIdsPerRecipient then ids[#ids+1]=requestId end end end
  plans[1]={channel="GUILD",target=nil,recipients=authorized,requestIds=ids,requestId=ids[1]}
  log("INFO","payload","Coalesced payload selected shared guild broadcast",{domain=job.domain,objectId=job.objectId,owner=meta.owner,revision=meta.revisionID,receiverCount=#authorized,requestIdCount=#ids,channel="GUILD",decision="BROADCAST"})
 else
  for _,recipient in ipairs(authorized)do plans[#plans+1]={channel="WHISPER",target=recipient.name,recipients={recipient},requestIds=copy(recipient.requestIds),requestId=latestRecipientRequest(recipient)}end
  log("INFO","payload","Coalesced payload selected recipient whispers",{domain=job.domain,objectId=job.objectId,owner=meta.owner,revision=meta.revisionID,receiverCount=#authorized,channel="WHISPER",decision="WHISPER"})
 end
 local transmissions={};local fragmentsMax,bytesTotal=0,0
 for _,plan in ipairs(plans)do
  local envelope={protocol=self.protocol,kind="PAYLOAD",domain=job.domain,data={objectId=job.objectId,metadata=meta,payload=payload,reason=job.reason,requestId=plan.requestId,requestIds=plan.requestIds},sentAt=now(),sender=UnitGUID("player")}
  local serialized,err=HolyStorm.Serializer:Serialize(envelope)
  if not serialized then self:SendResultToRecipients(job,"UNAVAILABLE","SERIALIZE:"..tostring(err),meta,plan.recipients)
  else
   local fragments=math.max(1,math.ceil(#serialized/HolyStorm.Comms.chunkSize));if#serialized>HolyStorm.Comms.receiveLimits.maxPayloadBytes or fragments>HolyStorm.Comms.receiveLimits.maxFragments then log("ERROR","backpressure","Atomic sync payload exceeds HSC1 transfer limit",{requestId=plan.requestId,objectId=job.objectId,domain=job.domain,revision=meta.revisionID,bytes=#serialized,fragments=fragments,limit=HolyStorm.Comms.receiveLimits.maxFragments,result="DEFERRED_SIZE_LIMIT"});self:SendResultToRecipients(job,"UNAVAILABLE","PAYLOAD_TOO_LARGE",meta,plan.recipients)
   else transmissions[#transmissions+1]={plan=plan,serialized=serialized,fragments=fragments};fragmentsMax=math.max(fragmentsMax,fragments);bytesTotal=bytesTotal+#serialized end
  end
 end
 if#transmissions==0 then return self:ReleaseTransfer(true,"NO_TRANSMITTABLE_PAYLOAD",transfer)end
 transfer.phase="TRANSFER";transfer.bytes=bytesTotal;transfer.fragments=0;transfer.fragmentsTotal=fragmentsMax;transfer.revision=meta.revisionID;transfer.selectedSource=playerName();transfer.sendPending=true;transfer.pendingTransmissions=#transmissions;transfer.transmissionIds={};job.state="RUNNING";job.startedAt=transfer.startedAt;recordJobMetric(self,job,"started")
 if fragmentsMax>=48 then log("WARN","fragmentation","Large atomic sync domain transfer queued",{requestId=job.requestId,objectId=job.objectId,characterUUID=job.characterUUID,domain=job.domain,revision=meta.revisionID,receiverCount=#authorized,bytes=bytesTotal,fragments=fragmentsMax})end
 local function progress(sent,total)if Sync.activeTransfer==transfer then transfer.fragments=math.max(transfer.fragments or 0,sent or 0);transfer.fragmentsTotal=math.max(transfer.fragmentsTotal or 0,total or 0);if transfer.activityId then Sync:NotifyActivity()end end end
 local function completeOne(ok,id,bytes,reason)
  if Sync.activeTransfer~=transfer then return end
  transfer.pendingTransmissions=math.max(0,(transfer.pendingTransmissions or 1)-1);if id then transfer.transmissionIds[id]=true;transfer.transmissionId=id end
  if ok~=true then transfer.failedTransmissions=(transfer.failedTransmissions or 0)+1;transfer.sendFailureReason=reason or"TRANSMISSION_FAILED"end
  if transfer.pendingTransmissions==0 then transfer.sendPending=false;Sync:ReleaseTransfer((transfer.failedTransmissions or 0)==0,transfer.sendFailureReason,transfer)end
 end
 self:BeginTransferActivity(transfer)
 for _,transmission in ipairs(transmissions)do
  local plan=transmission.plan;local diagnostics={domain=job.domain,objectId=job.objectId,characterUUID=job.characterUUID,block=job.block,messageKind="PAYLOAD",messageClass="payload",revision=meta.revisionID,requestId=plan.requestId,selectedSource=playerName(),originalOwner=meta.owner,relay=meta.owner~=UnitGUID("player"),priority=job.priorityClass,receiverCount=#plan.recipients,channel=plan.channel,serializedBytes=#transmission.serialized}
  local queued,id=HolyStorm.Comms:Send(transmission.serialized,plan.channel,plan.target,job.priority,diagnostics,function(okValue,transmissionId,bytes,reason)completeOne(okValue,transmissionId,bytes,reason)end,progress)
  if queued then if id then transfer.transmissionIds[id]=true;transfer.transmissionId=id end
  else self:SendResultToRecipients(job,"UNAVAILABLE","TRANSPORT_QUEUE_REJECTED",meta,plan.recipients);completeOne(true,nil,0,"TRANSPORT_QUEUE_REJECTED")end
 end
 transfer.preparing=false
 if self.activeTransfer~=transfer then return true end
 if not self:IsTransferActivityAuthoritative(transfer)then return self:ReleaseTransfer(false,"TRANSMISSION_NOT_ACTIVE",transfer)end
 log("INFO","payload","Authorized payload transfer queued",{domain=job.domain,objectId=job.objectId,owner=meta.owner,revision=meta.revisionID,receiverCount=#authorized,transmissionCount=#transmissions,decision=broadcast and"BROADCAST"or"WHISPER",bytes=bytesTotal})
 return true
end
function Sync:RunQueuePump()
 if self.activeTransfer then return true end
 local selected,index;local earliest
 for i,job in ipairs(self.catchUpJobs)do if job.state=="QUEUED"then if job.notBefore<=now()then local score=job.priority-math.min(10,math.floor(math.max(0,now()-job.queuedAt)/30));if not selected or score<selected.score or(score==selected.score and job.queuedAt<selected.job.queuedAt)then selected={job=job,score=score};index=i end else earliest=not earliest and job.notBefore or math.min(earliest,job.notBefore)end end end
 if not selected then if earliest then self:QueuePump(math.max(.05,earliest-now()))end;return true end
 local job=selected.job;table.remove(self.catchUpJobs,index)
 local ok,result=pcall(function()
  if job.kind=="SEND"then local transfer={kind="SEND",job=job,key=job.key,objectId=job.objectId,entity=job.entity,characterUUID=job.characterUUID,domain=job.domain,activityDomain=job.block or job.domain,direction="SEND",phase="PREPARING",sender=playerName(),receiver=job.target,requestId=job.requestId,priorityClass=job.priorityClass,retryCount=job.retryCount,maxRetries=job.maxRetries,startedAt=now(),preparing=true};job.state="DISPATCHING";self.activeTransfer=transfer;return self:StartSend(job,transfer)end
  return self:StartFetch(job)
 end)
 if not ok then
  local transfer=self.activeTransfer
  log("ERROR","activity","Sync queue operation raised an error",{requestId=job.requestId,domain=job.domain,objectId=job.objectId,error=tostring(result),result="OPERATION_ERROR"})
  if transfer and transfer.job==job and transfer.kind=="SEND"and job.reason=="REQUEST_RESPONSE"then
   local replyOK,replyQueued=pcall(function()return self:SendResultToRecipients(job,"UNAVAILABLE","SYNC_OPERATION_ERROR")end)
   self:ReleaseTransfer(replyOK and replyQueued==true,"SYNC_OPERATION_ERROR",transfer)
  elseif transfer and transfer.job==job then self:ReleaseTransfer(false,"SYNC_OPERATION_ERROR",transfer)
   else job.state="QUEUED";job.notBefore=now()+1;if not job.activityHandoff then job.activityId=nil end;self.catchUpJobs[#self.catchUpJobs+1]=job;self:QueuePump(1);self:NotifyActivity(true)end
  return false
 end
 return result
end
function Sync:OnPayload(domainId,data,sender,transport,kind)
 local domain=self.domains[domainId];if not domain or type(data)~="table"or not validId(data.objectId)or type(data.metadata)~="table"then return false end
 if data.requestIds~=nil then
  if type(data.requestIds)~="table"then return false,"INVALID_REQUEST_IDS"end
  local count=0;for index,requestId in pairs(data.requestIds)do count=count+1;if count>self.maxCoalescedRecipients*self.maxRequestIdsPerRecipient or type(index)~="number"or index<1 or index%1~=0 or not validId(requestId)then return false,"INVALID_REQUEST_IDS"end end
 end
 transport=type(transport)=="table"and transport or{};kind=kind or"PAYLOAD"
 if kind=="PAYLOAD"and self:IsRetiredRequest(data.requestId)and not matchesFetchPayload(self.activeTransfer,domainId,data,sender)then log("DEBUG","request","Late payload for a retired Sync request ignored",{requestId=data.requestId,domain=domainId,objectId=data.objectId,sender=sender,result="RETIRED_REQUEST"});return false,"RETIRED_REQUEST"end
 if kind=="PAYLOAD"and not matchesFetchPayload(self.activeTransfer,domainId,data,sender)then log("DEBUG","request","Payload does not match the active Sync fetch",{requestId=data.requestId,domain=domainId,objectId=data.objectId,sender=sender,activeRequestId=self.activeTransfer and self.activeTransfer.requestId,result="UNMATCHED_REQUEST"});return false,"UNMATCHED_REQUEST"end
 if kind=="PAYLOAD"and self:IsRetiredRequest(self.activeTransfer and self.activeTransfer.requestId)then log("DEBUG","request","Late payload for a completed Sync request ignored",{requestId=self.activeTransfer and self.activeTransfer.requestId,domain=domainId,objectId=data.objectId,sender=sender,result="RETIRED_REQUEST"});return false,"RETIRED_REQUEST"end
 if kind=="LIVE"and not domain.live then return false,"INVALID_LIVE_DOMAIN"end
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
 local active=self.activeTransfer;if matchesFetchPayload(active,domainId,data,sender)then if active.timeoutTimer then active.timeoutTimer:Cancel();active.timeoutTimer=nil end;active.awaitingResponse=false;active.receiveId=id;active.bytes=transport.bytes or active.bytes;active.fragments=transport.packetTotal or active.fragments;active.fragmentsTotal=transport.packetTotal or active.fragmentsTotal;self:ActivityPhase(active,"VALIDATE_COMMIT")end
 self:SchedulePayloadPump();return true
end
function Sync:OnFragmentProgress(progress)
 -- Fragment events do not carry the logical object/request until the envelope
 -- is assembled, so sender-only correlation can report unrelated data as a fetch.
 local transfer=self.activeTransfer;if not transfer or transfer.kind~="FETCH"or transfer.direction~="RECEIVE"or not progress or not progress.objectId or not progress.requestId or progress.domain~=transfer.domain or progress.objectId~=transfer.objectId or progress.requestId~=transfer.requestId or not samePlayerName(transfer.selectedSource or transfer.sender,progress.sender)then return end
 transfer.fragments=progress.fragments;transfer.fragmentsTotal=progress.fragmentsTotal;transfer.bytes=progress.bytes;self:NotifyActivity()
end
function Sync:ProcessReceivePayload()
 local active=self.activeTransfer;local index,id,pending
 for i,candidate in ipairs(self.pendingPayloadOrder)do local item=self.pendingPayloads[candidate];if item and(not active or matchesFetchPayload(active,item.domain,item.data,item.sender))then index,id,pending=i,candidate,item;break end end
 if not pending then return true end
 table.remove(self.pendingPayloadOrder,index);self.pendingPayloads[id]=nil
 local transfer=active;if not transfer then local meta=pending.data.metadata;local characterUUID=splitCharacterId(pending.data.objectId);transfer={kind="RECEIVE",objectId=pending.data.objectId,entity=pending.data.objectId,characterUUID=characterUUID,domain=pending.domain,activityDomain=characterUUID and select(2,splitCharacterId(pending.data.objectId))or pending.domain,direction="RECEIVE",phase="VALIDATE_COMMIT",sender=pending.sender,receiver=playerName(),requestId=pending.data.requestId,revision=meta and meta.revisionID,startedAt=now(),bytes=pending.bytes or 0,receiveId=id,processing=true};self.activeTransfer=transfer;self:BeginTransferActivity(transfer)end
 transfer.receiveId=id;transfer.processing=true;self:ActivityPhase(transfer,"VALIDATE_COMMIT")
 local ok,result=pcall(function()return self:ApplyPayload(pending.domain,pending.data,pending.sender)end);transfer.processing=false
 if not ok then log("ERROR","activity","Sync payload processing raised an error",{requestId=transfer.requestId,domain=pending.domain,objectId=pending.data.objectId,error=tostring(result),result="RECEIVE_OPERATION_ERROR"})end
 if self.activeTransfer==transfer then self:ReleaseTransfer(ok and result==true,ok and(result and"COMMITTED"or"VALIDATION_OR_IMPORT_FAILED")or"RECEIVE_OPERATION_ERROR",transfer)end
 if#self.pendingPayloadOrder>0 then self:SchedulePayloadPump()end;return true
end
function Sync:RunReceivePayload()
 local ok,result=pcall(function()return self:ProcessReceivePayload()end)
 if ok then return result end
 local transfer=self.activeTransfer
 log("ERROR","activity","Sync receive worker raised an error",{requestId=transfer and transfer.requestId,domain=transfer and transfer.domain,objectId=transfer and transfer.objectId,error=tostring(result),result="RECEIVE_WORKER_ERROR"})
 if transfer and(transfer.kind=="RECEIVE"or transfer.kind=="FETCH"and transfer.phase=="VALIDATE_COMMIT")then self:ReleaseTransfer(false,"RECEIVE_WORKER_ERROR",transfer)end
 return false
end
function Sync:OnTransportCompleted(transmissionId,result,bytes,reason)
 local transfer=self.activeTransfer
 if transfer and transfer.kind=="SEND"and transfer.transmissionId==transmissionId and not self:IsTransferActivityAuthoritative(transfer)then
  return self:ReleaseTransfer(result==true,reason or"TRANSMISSION_COMPLETED_WITHOUT_OWNER_CALLBACK",transfer)
 end
 return false
end
function Sync:ResetActivityState(reason)
 if self.activityNotifyTimer then self.activityNotifyTimer:Cancel();self.activityNotifyTimer=nil end
 if self.activeTransfer and self.activeTransfer.timeoutTimer then self.activeTransfer.timeoutTimer:Cancel();self.activeTransfer.timeoutTimer=nil end
 self.activeTransfer=nil;self.activeActivities={};self.catchUpJobs={};self.catchUpIndex={};self.outboundCoalescing={};self.pendingManifestEntries={};self.pendingPayloads={};self.pendingPayloadOrder={};self.retiredRequestIds={};self.retiredRequestOrder={}
 if reason=="INITIALIZE"or reason=="SYNC_SHUTDOWN"then self.terminalFetches={};self.terminalFetchOrder={};self.lastTerminalFetch=nil end
 self.activityStateMismatch=false;self.activityMismatchLogged=false;self.activityPublishedActive=false;self.activityNotifyDeferred=nil
 if HolyStorm.Events then HolyStorm.Events:Emit("HS_SYNC_ACTIVITY_UPDATED",activitySnapshot(self))end
 return true
end
function Sync:SelectForTestOrDispatch()return self:RunQueuePump()end
function Sync:GetRuntimeMetrics()
 local activity=self:GetActivity();local requests=HolyStorm.Utils.TableCount(self.activeRequests);return{requested=self.runtimeMetrics.requested,started=self.runtimeMetrics.started,completed=self.runtimeMetrics.completed,failed=self.runtimeMetrics.failed,retried=self.runtimeMetrics.retried,byDomain=self.runtimeMetrics.byDomain,byReason=self.runtimeMetrics.byReason,queued=activity.queuedJobs,queuedCatchUpJobs=activity.queuedJobs,pendingPayloads=#self.pendingPayloadOrder,requests=requests,active=activity.active,activityCount=activity.activityCount,activeActivityIds=activity.activeActivityIds}
end
function Sync:ResetRuntimeMetrics()self.runtimeMetrics={requested=0,started=0,completed=0,failed=0,retried=0,byDomain={},byReason={}};return true end
function Sync:GetDiagnostics()
 local candidates=0;for _,request in pairs(self.requests)do for _,peers in pairs(request.candidates or{})do candidates=candidates+HolyStorm.Utils.TableCount(peers)end end
 local activity=self:GetActivity();local transfer=self.activeTransfer;local first
 for _,operation in ipairs(activity.activeOperations)do if transfer and operation.activityId==transfer.activityId then first=operation;break end end
 local activeRequest=transfer and transfer.kind=="FETCH"and transfer.awaitingResponse and{requestId=transfer.requestId,domain=transfer.domain,entity=transfer.objectId,revision=transfer.revision,phase=transfer.phase,source=transfer.selectedSource,currentSource=transfer.selectedSource,candidateSources=sourceDiagnostics(transfer.job and transfer.job.allSourceCandidates or transfer.job and transfer.job.sourceCandidates),exhaustedSources=exhaustedSourceDiagnostics(transfer.job and transfer.job.exhaustedSources),attempt=transfer.attempt,terminalReason=transfer.job and transfer.job.terminalReason,requeueReason=transfer.job and transfer.job.requeueReason,queueLength=#self.catchUpJobs,dedupKey=transfer.key and readableDedupKey(transfer.key),discoveryGeneration=transfer.job and transfer.job.discoveryGeneration,timeoutArmed=transfer.timeoutTimer~=nil,timeoutAt=transfer.timeoutAt,age=math.max(0,now()-(transfer.startedAt or now()))}or nil
 local activeJob=transfer and transfer.job;local handoffJob
 if not activeJob then for _,id in ipairs(activity.activeActivityIds)do local record=self.activeActivities[id];local owner=record and record.owner;if type(owner)=="table"and owner.activityHandoff then handoffJob=owner;break end end end
 activeJob=activeJob or handoffJob;local idle=not activity.active;local queuedJobs={}
 for _,job in ipairs(self.catchUpJobs)do if job.state=="QUEUED"and#queuedJobs<5 then queuedJobs[#queuedJobs+1]={requestId=job.requestId,domain=job.domain,objectId=job.objectId,entity=job.objectId,revision=job.requiredRevision,state=job.state,notBefore=job.notBefore,retryCount=job.retryCount,attempt=job.attempt,sourceCandidates=sourceDiagnostics(job.allSourceCandidates or job.sourceCandidates),currentSource=job.selectedSource,exhaustedSources=exhaustedSourceDiagnostics(job.exhaustedSources),terminalReason=job.terminalReason,requeueReason=job.requeueReason,queueLength=#self.catchUpJobs,dedupKey=readableDedupKey(job.key),discoveryGeneration=job.discoveryGeneration}end end
 local activeCatchUpJob=activeJob and{requestId=activeJob.requestId,domain=activeJob.domain,objectId=activeJob.objectId,entity=activeJob.objectId,revision=activeJob.requiredRevision,state=activeJob.state,queued=activeJob.state=="QUEUED",source=activeJob.selectedSource or(first and first.source),currentSource=activeJob.selectedSource or(first and first.source),candidateSources=sourceDiagnostics(activeJob.allSourceCandidates or activeJob.sourceCandidates),exhaustedSources=exhaustedSourceDiagnostics(activeJob.exhaustedSources),attempt=activeJob.attempt,terminalReason=activeJob.terminalReason,requeueReason=activeJob.requeueReason,queueLength=#self.catchUpJobs,dedupKey=readableDedupKey(activeJob.key),discoveryGeneration=activeJob.discoveryGeneration,phase=first and first.phase or"SOURCE_FALLBACK",activityId=activeJob.activityId}
 return{requests=HolyStorm.Utils.TableCount(self.requests),activeRequests=HolyStorm.Utils.TableCount(self.activeRequests),heard=HolyStorm.Utils.TableCount(self.heard),knownOnline=HolyStorm.Utils.TableCount(self.knownOnline),domains=HolyStorm.Utils.TableCount(self.domains),peerCandidates=candidates,lastSelection=self.lastSelection,lastTerminalFetch=self.lastTerminalFetch,publishedVersions=HolyStorm.Utils.TableCount(self.publishedVersions),catchUpQueued=activity.queuedJobs,catchUpQueueLength=activity.queuedJobs,queuedCatchUpJobs=queuedJobs,activeTransfer=first,activeRequest=activeRequest,activeCatchUpJob=activeCatchUpJob,activeActivityIds=activity.activeActivityIds,activityCount=activity.activityCount,activityDomain=activity.activityDomain,activityPhase=activity.activityPhase,activityAge=activity.activityAge,activityStateMismatch=activity.activityStateMismatch,activity=activity.active,pendingPayloads=#self.pendingPayloadOrder,queueLimit=self.catchUpLimit,cleanupScheduled=self.cleanupTimer~=nil or self.cleanupTaskId~=nil,idle=idle,metrics=self.runtimeMetrics,transport=HolyStorm.Comms and HolyStorm.Comms:GetDiagnostics().transport}
end
function Sync:Cleanup()
 local current=now();local requestCutoff=current-self.requestTimeout;for requestId,request in pairs(self.requests)do if(request.createdAt or 0)<=requestCutoff then self.activeRequests[request.key or key(request.domain,request.objectId)]=nil;self.requests[requestId]=nil end end;for requestId,at in pairs(self.heardAt)do if at<=requestCutoff then self.heardAt[requestId]=nil;self.heard[requestId]=nil end end;for id,snapshot in pairs(self.offerSnapshots)do if(tonumber(snapshot.createdAt)or 0)<=requestCutoff then self.offerSnapshots[id]=nil end end;pruneTerminalFetches(self)
 local pending={};for _,entry in ipairs(self.pendingManifestEntries)do if current-(tonumber(entry.receivedAt)or 0)<self.presenceTimeout then pending[#pending+1]=entry end end;self.pendingManifestEntries=pending
 for requestId,entry in pairs(self.retiredRequestIds)do if(tonumber(entry.expiresAt)or 0)<=current then self.retiredRequestIds[requestId]=nil end end
 local presenceCutoff=current-self.presenceTimeout;for guid,at in pairs(self.knownOnline)do if at<=presenceCutoff then self.knownOnline[guid]=nil end end
 for guid,entry in pairs(self.knownVersions)do if not entry.localPlayer and(not validPresenceVersion(entry.version)or(tonumber(entry.receivedAt)or 0)<=presenceCutoff)then clearKnownVersion(self,guid,entry,validPresenceVersion(entry.version)and"PRESENCE_EXPIRED"or"INVALID_PRESENCE_VERSION")end end
 self:ScheduleCleanup();return true
end
function Sync:RunCatchUp()
 log("DEBUG","catchup","Login catch-up deliberately suppressed",{reason="METADATA_ON_DEMAND",domains=HolyStorm.Utils.TableCount(self.domains)})
 return false,"LOGIN_CATCHUP_SUPPRESSED"
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
 local manifest=self:BuildManifest();local queued=self:QueueEnvelope("PRESENCE",nil,{version=HolyStorm.version,sessionId=sessionId,replyRequested=true,manifest=manifest,reason="LOGIN_PRESENCE"},"GUILD",nil,50)
 log(queued and"INFO"or"WARN","discovery",queued and"Minimal login Presence and revision manifest queued"or"Login Presence could not be queued",{reason="LOGIN_PRESENCE",sessionId=sessionId,manifestEntries=#manifest.entries,channel="GUILD"})
 log("DEBUG","catchup","Login catch-up deliberately suppressed",{reason="METADATA_ON_DEMAND",sessionId=sessionId,domains=HolyStorm.Utils.TableCount(self.domains)})
 return queued~=nil and queued~=false
end
function Sync:RunPresenceHeartbeat()
 if not IsInGuild()then return false end
 self:QueueEnvelope("PRESENCE",nil,{version=HolyStorm.version,reason="PRESENCE_HEARTBEAT"},"GUILD",nil,50)
 log("DEBUG","version","One-shot Presence heartbeat sent without catch-up",{reason="PRESENCE_HEARTBEAT"});return true
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
 if data.manifest~=nil then self:ReceiveManifest(data.manifest,sender,resolved)end
 if data.replyRequested==true and not data.responseTo then self:QueueEnvelope("PRESENCE",nil,{version=HolyStorm.version,responseTo=data.sessionId,reason="PRESENCE_RESPONSE"},"WHISPER",sender,50,.2+math.random()*.6)end
 return true
end
function Sync:Receive(payload,sender,channel,transport)
	local envelope=HolyStorm.Serializer:Deserialize(payload)
	if type(envelope)~="table"or envelope.protocol~=self.protocol or type(envelope.kind)~="string"or envelope.sender==UnitGUID("player")then return false end
	transport=type(transport)=="table"and transport or{}
	local data=type(envelope.data)=="table"and envelope.data or{}
	local meta=type(data.metadata)=="table"and data.metadata or type(data.offers)=="table"and type(data.offers[1])=="table"and data.offers[1]or type(data.currentMetadata)=="table"and data.currentMetadata or{}
	local correlationId=transport.correlationId or transport.transmissionId
	local objectId=data.objectId or meta.objectId
	local characterUUID,blockType
	if type(objectId)=="string"then characterUUID,blockType=objectId:match("^(.-)\031([^\031]+)$")end
	local destination=receiver(channel)
	local resolved,identityReason=senderGuid(sender,envelope.sender)
	log("DEBUG",string.lower(envelope.kind),"Sync envelope received",{direction="RECEIVE",sender=sender,receiver=destination,target=destination,from=sender,to=destination,channel=channel,domain=envelope.domain,logicalObject=blockType or objectId,blockType=blockType,block=blockType,characterUUID=characterUUID,objectId=objectId,messageKind=envelope.kind,messageClass=messageClasses[envelope.kind]or"control",version=meta.version or data.version,revision=meta.revisionID or data.revisionID,reason=data.reason or data.result,requestId=data.requestId,selectedSource=sender,senderGuid=resolved,claimedGuid=envelope.sender,identityReason=identityReason,transmissionId=transport.transmissionId,packetTotal=transport.packetTotal,bytes=transport.bytes,serializedBytes=transport.bytes,correlationId=correlationId,originalOwner=meta.owner,relay=meta.owner and meta.owner~=envelope.sender or false,retry=false},correlationId)
	if resolved and envelope.sender~=resolved then
		log("WARN","authority","Envelope sender identity mismatch",{direction="RECEIVE",from=sender,to=destination,channel=channel,sender=sender,claimed=envelope.sender,resolved=resolved,identityReason=identityReason,transmissionId=transport.transmissionId,correlationId=correlationId},correlationId)
		return false
	end
 if envelope.kind=="PRESENCE"then return self:OnPresence(data,sender,resolved,envelope.sender,identityReason)end
 if envelope.kind=="FETCH"and not self.domains[envelope.domain]then return self:OnFetch(envelope.domain,data,sender)end
 if not self.domains[envelope.domain]then return false end
 if envelope.kind=="DISCOVER"then return self:OnDiscover(envelope.domain,envelope.data,sender,channel)elseif envelope.kind=="OFFER"or envelope.kind=="ANNOUNCE"then return self:RecordOffers(envelope.domain,envelope.data,sender,envelope.kind=="ANNOUNCE")elseif envelope.kind=="FETCH"then return self:OnFetch(envelope.domain,envelope.data,sender)elseif envelope.kind=="FETCH_RESULT"then return self:OnFetchResult(envelope.domain,data,sender)elseif envelope.kind=="PAYLOAD"or envelope.kind=="LIVE"then return self:OnPayload(envelope.domain,envelope.data,sender,transport,envelope.kind)end;return false
end
function Sync:Initialize()
 self:ResetActivityState("INITIALIZE")
 HolyStorm.Tasks:RegisterTaskType("Sync.Send",{name=L["TASK_SYNC_SEND"],localizedNameKey="TASK_SYNC_SEND",module="Sync",priority=70,executionMode="MULTI",maxRetries=2,execute=function(task)return Sync:SendNow(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.LivePublish",{name=L["TASK_SYNC_LIVE_PUBLISH"],localizedNameKey="TASK_SYNC_LIVE_PUBLISH",module="Sync",priority=110,executionMode="MERGE_BY_KEY",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function(task)return Sync:RunLivePublish(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Publish",{name=L["TASK_SYNC_PUBLISH"],localizedNameKey="TASK_SYNC_PUBLISH",module="Sync",priority=65,executionMode="MERGE_BY_KEY",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING"},execute=function(task)return Sync:RunPublish(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Discover",{name=L["TASK_SYNC_DISCOVER"],localizedNameKey="TASK_SYNC_DISCOVER",module="Sync",priority=80,executionMode="MERGE_BY_KEY",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function(task)return Sync:RunDiscover(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Offer",{name=L["TASK_SYNC_OFFER"],localizedNameKey="TASK_SYNC_OFFER",module="Sync",priority=85,executionMode="MERGE_BY_KEY",execute=function(task)return Sync:RunOffer(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.QueuePump",{name="Process sync queue",module="Sync",priority=25,executionMode="UNIQUE",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","NOT_IN_COMBAT"},execute=function()return Sync:RunQueuePump()end})
 HolyStorm.Tasks:RegisterTaskType("Sync.ReceivePayload",{name="Validate and commit sync payload",module="Sync",priority=22,executionMode="UNIQUE",execute=function()return Sync:RunReceivePayload()end})
 HolyStorm.Tasks:RegisterTaskType("Sync.PassiveRefresh",{name=L["TASK_SYNC_PASSIVE"],localizedNameKey="TASK_SYNC_PASSIVE",module="Sync",priority=95,executionMode="MERGE_BY_KEY",execute=function(task)return Sync:RunPassive(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.Cleanup",{name="Sync cleanup",module="Sync",priority=100,executionMode="UNIQUE",execute=function()Sync.cleanupTaskId=nil;return Sync:Cleanup()end})
 HolyStorm.Tasks:RegisterTaskType("Sync.LoginPresence",{name=L["TASK_SYNC_LOGIN_PRESENCE"],localizedNameKey="TASK_SYNC_LOGIN_PRESENCE",module="Sync",priority=98,executionMode="UNIQUE",conditions={"PLAYER_LOGGED_IN","PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function(task)return Sync:RunLoginPresence(task)end})
 HolyStorm.Tasks:RegisterTaskType("Sync.VersionNotice",{name=L["TASK_SYNC_VERSION_NOTICE"],localizedNameKey="TASK_SYNC_VERSION_NOTICE",module="Sync",priority=99,executionMode="UNIQUE",execute=function()return Sync:EvaluateOutdatedVersion()end})
 self:RegisterDomain("character",{freshness="player-block",broadcastSafe=true,listManifest=function(limit)local guid=UnitGUID and UnitGUID("player");local out={};local playerData=HolyStorm.PlayerData;if not guid or not playerData or type(playerData.GetBlockDefinitions)~="function"or type(playerData.GetMetadata)~="function"then return out end;for _,definition in ipairs(playerData:GetBlockDefinitions())do if#out>=math.min(tonumber(limit)or self.maxManifestEntries,self.maxManifestEntries)then break end;if type(definition)=="table"and characterBlockSyncEnabled(definition.id)then local meta=playerData:GetMetadata(guid,definition.id);if meta and meta.owner==guid and tonumber(meta.version)then out[#out+1]=meta end end end;return out end,getMetadata=function(objectId)local guid,block=splitCharacterId(objectId);return guid and HolyStorm.PlayerData:GetMetadata(guid,block)end,listMetadata=function(since)local out={};for guid,record in pairs(HolyStorm.PlayerData:GetCharacters())do for block in pairs(record.blockMeta or{})do if characterBlockSyncEnabled(block)then local meta=HolyStorm.PlayerData:GetMetadata(guid,block);if meta and(meta.committedAt or meta.updatedAt or 0)>since then out[#out+1]=meta end end end end;return out end,export=function(objectId)local guid,block=splitCharacterId(objectId);if not guid or not characterBlockSyncEnabled(block)then return nil end;local data=HolyStorm.PlayerData:GetBlockForExport(guid,block);return data and{guid=guid,block=block,data=data}end,validate=function(payload,meta,objectId)local guid,block=splitCharacterId(objectId);return characterBlockSyncEnabled(block)and type(payload)=="table"and payload.guid==guid and payload.block==block and type(payload.data)=="table"and meta.owner==guid end,authorize=function(_,meta,_,_,objectId)local guid,block=splitCharacterId(objectId);return characterBlockSyncEnabled(block)and meta.owner==guid end,import=function(objectId,payload,meta,senderId,sender)local guid,block=splitCharacterId(objectId);return HolyStorm.PlayerData:AcceptRemoteBlock(guid,block,payload.data,meta,senderId,sender)end,updateEvent="HS_CHARACTER_SYNC_UPDATED"})
  HolyStorm.Events:Register("HS_COMMS_MESSAGE","sync",function(_,payload,sender,channel,transport)Sync:Receive(payload,sender,channel,transport)end)
  HolyStorm.Events:Register("HS_COMMS_FRAGMENT_PROGRESS","sync-activity",function(_,progress)Sync:OnFragmentProgress(progress)end)
  HolyStorm.Events:Register("HS_COMMS_TRANSMISSION_COMPLETED","sync-activity-reconcile",function(_,transmissionId,result,bytes,reason)Sync:OnTransportCompleted(transmissionId,result,bytes,reason)end)
 HolyStorm.Events:Register("HS_PLAYERDATA_OWNED_UPDATED","sync-character",function(_,guid,block)if characterBlockSyncEnabled(block)then Sync:Publish("character",guid.."\031"..block,"OWNED_BLOCK_UPDATED")end end)
 HolyStorm.Events:Register("PLAYER_LOGIN","sync-presence",function()Sync:BeginLoginSession()end)
 HolyStorm.Tasks:RegisterTaskType("Sync.LoginCatchUp",{name=L["TASK_SYNC_CATCHUP"],localizedNameKey="TASK_SYNC_CATCHUP",module="Sync",priority=98,executionMode="UNIQUE",conditions={"PLAYER_READY","NOT_LOADING","NOT_ZONING","GUILD_AVAILABLE"},execute=function()return Sync:RunCatchUp()end})
 HolyStorm.State:Set("syncReady",HolyStorm.Comms.available==true);return true
end
function Sync:Shutdown()self:CancelCleanupTimer();if self.cleanupTaskId then HolyStorm.Tasks:Cancel(self.cleanupTaskId,"SYNC_SHUTDOWN");self.cleanupTaskId=nil end;self:ResetActivityState("SYNC_SHUTDOWN")end
HolyStorm.Sync=Sync
