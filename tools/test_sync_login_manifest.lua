local root=(arg[0]:gsub("tools[/\\]test_sync_login_manifest.lua$","")).."LIVE/Holy_Storm/"
local clock=1000
local currentGuid="Player-Local"
local names={ ["Local-Realm"]="Player-Local",["Owner-Realm"]="Player-Owner",["A-Realm"]="Player-A",["B-Realm"]="Player-B",["C-Realm"]="Player-C",["Relay-Realm"]="Player-Relay" }
local timers={}
local function copy(value)
 if type(value)~="table"then return value end
 local out={};for key,child in pairs(value)do out[key]=copy(child)end;return out
end
local function count(value)local total=0;for _ in pairs(value or{})do total=total+1 end;return total end
local metadata={}
local blockDefinitions={{id="identity"},{id="equipment"},{id="mythicPlus"},{id="raid"},{id="delves"},{id="stats"}}
metadata["Player-Local\031identity"]={objectId="Player-Local\031identity",owner="Player-Local",version=4,revisionID="identity-r4",schemaVersion=2,snapshotVersion=3}
metadata["Player-Local\031equipment"]={objectId="Player-Local\031equipment",owner="Player-Local",version=8,revisionID="equipment-r8",schemaVersion=4,snapshotVersion=4}

function UnitGUID()return currentGuid end
function GetUnitName()return names[currentGuid]or currentGuid end
function IsInGuild()return true end
C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback,cancelled=false};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}

local roster={
 ["Player-Local"]={guid="Player-Local",name="Local-Realm",online=true},
 ["Player-A"]={guid="Player-A",name="A-Realm",online=true},
 ["Player-B"]={guid="Player-B",name="B-Realm",online=true},
 ["Player-C"]={guid="Player-C",name="C-Realm",online=true},
 ["Player-Owner"]={guid="Player-Owner",name="Owner-Realm",online=true},
 ["Player-Relay"]={guid="Player-Relay",name="Relay-Realm",online=true},
}
local HolyStorm={version="5.9.0",Events={listeners={}},Logger={history={}},Tasks={types={},queue={}},Data={GuildStore={roster=roster}},PlayerData={},Utils={},Comms={available=true,chunkSize=220,receiveLimits={maxFragments=300,maxPayloadBytes=66000},sent={}},Serializer={byPayload={}},State={}}
function HolyStorm:GetAddon()return self end
function HolyStorm:GetVersion()return self.version end
function HolyStorm.Events:Register(event,owner,callback)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=callback;return true end
function HolyStorm.Events:Emit(event,...)for _,callback in pairs(self.listeners[event]or{})do callback(event,...)end end
function HolyStorm.Logger:Write(level,source,category,message,context)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context}end
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.types[id]=definition;return true end
function HolyStorm.Tasks:GetTaskType(id)return self.types[id]end
function HolyStorm.Tasks:Queue(id,options)self.queue[#self.queue+1]={id=id,options=options or{}};return"task-"..#self.queue end
function HolyStorm.Tasks:Cancel()return true end
function HolyStorm.Tasks:IsStartupActive()return false end
function HolyStorm.State:Set()return true end
function HolyStorm.Data.GuildStore:ResolveSenderGuid(sender,claimed)return names[sender]or claimed end
function HolyStorm.Data.GuildStore:GetCurrent()return{id="test:guild",roster=roster}end
function HolyStorm.PlayerData:GetBlockDefinitions()return blockDefinitions end
function HolyStorm.PlayerData:GetMetadata(guid,block)return metadata[guid.."\031"..block]end
function HolyStorm.PlayerData:GetCharacters()return{}end
function HolyStorm.PlayerData:IsBlockSyncEnabled()return true end
function HolyStorm.PlayerData:CompareMetadata(localMeta,remoteMeta)
 if not localMeta then return 1,"MISSING"end
 local localVersion,remoteVersion=tonumber(localMeta.version)or-1,tonumber(remoteMeta.version)or-1
 if localVersion~=remoteVersion then return remoteVersion>localVersion and 1 or-1,remoteVersion>localVersion and"NEWER_VERSION"or"STALE_VERSION"end
 if localMeta.direct~=remoteMeta.direct then return remoteMeta.direct and 1 or-1,"PROVENANCE"end
 return 0,"SAME_VERSION"
end
function HolyStorm.Serializer:Serialize(envelope)self.sequence=(self.sequence or 0)+1;local payload="wire-"..self.sequence..string.rep("x",128);self.lastEnvelope=copy(envelope);self.byPayload[payload]=copy(envelope);return payload end
function HolyStorm.Comms:Send(payload,channel,target,priority,diagnostics,onComplete,onProgress)
 self.sent[#self.sent+1]={payload=payload,channel=channel,target=target,priority=priority,diagnostics=copy(diagnostics),envelope=copy(HolyStorm.Serializer.byPayload[payload])}
 if onProgress then onProgress(1,1)end
 if onComplete then onComplete(true,"tx-"..#self.sent,#payload)end
 return true,"tx-"..#self.sent
end
function LibStub(name)
 if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end
 return HolyStorm
end
assert(loadfile(root.."Core/Utils/Utils.lua"))()
HolyStorm.Utils.Now=function()return clock end
HolyStorm.Utils.DeepCopy=copy
HolyStorm.Utils.TableCount=count
assert(loadfile(root.."Sync/SyncManager.lua"))()
local Sync=HolyStorm.Sync
local scans={started=0}
function scans:BeginLogin()self.started=self.started+1 end
function scans:Queue()self.started=self.started+1 end
assert(Sync:Initialize())

-- PLAYER_LOGIN queues one Presence task and never queues domain discovery or producer work.
local scanCount=scans.started
HolyStorm.Events:Emit("PLAYER_LOGIN")
assert(scans.started==scanCount,"Sync login handling does not invoke character producer scans")
local loginTask
for _,task in ipairs(HolyStorm.Tasks.queue)do if task.id=="Sync.LoginPresence"then loginTask=task end end
assert(loginTask,"PLAYER_LOGIN queues the minimal Presence handshake")
local discoveryCount=0;for _,task in ipairs(HolyStorm.Tasks.queue)do if task.id=="Sync.Discover"then discoveryCount=discoveryCount+1 end end
assert(discoveryCount==0,"PLAYER_LOGIN does not queue global domain discovery")
assert(Sync:RunCatchUp()==false,"legacy catch-up entry point reports deliberate suppression")
assert(Sync:RunLoginPresence(loginTask),"login Presence is queued")
local presence
for index=#HolyStorm.Tasks.queue,1,-1 do local task=HolyStorm.Tasks.queue[index];if task.id=="Sync.Send"then presence=task.options.metadata.envelope;break end end
assert(presence.kind=="PRESENCE"and presence.data.version=="5.9.0"and presence.data.sessionId==Sync.loginSessionId,"login advertises only the resolved build and session identity")
assert(presence.data.manifest.schema==1 and#presence.data.manifest.entries==2,"login advertises only available current character block metadata")
for _,entry in ipairs(presence.data.manifest.entries)do assert(entry.payload==nil and entry.snapshot==nil and entry.data==nil,"manifest entries contain metadata only")end
assert(presence.data.equipment==nil and presence.data.raid==nil and presence.data.achievements==nil,"Presence never embeds feature payloads")
assert(Sync:RunCatchUp()==false,"a repeat catch-up request remains suppressed")

-- Equal and older metadata do not fetch; newer or absent local state creates one bounded demand.
local localRevisions={
 ["same"]={objectId="same",owner="Player-Owner",version=5,revisionID="r5",direct=true},
 ["older"]={objectId="older",owner="Player-Owner",version=10,revisionID="r10",direct=false},
 ["newer"]={objectId="newer",owner="Player-Owner",version=1,revisionID="r1",direct=false},
}
local function registerProbe(domainId,sharePolicy)
 local definition={getMetadata=function(objectId)return localRevisions[objectId]end,listMetadata=function()return{}end,export=function()return{ok=true}end,import=function()return true end,broadcastSafe=true}
 if sharePolicy then definition.canShare=sharePolicy;definition.getRecipients=function()return nil end end
 assert(Sync:RegisterDomain(domainId,definition))
end
registerProbe("probe")
local sameAndStale={schema=1,entries={
 {domain="probe",objectId="same",owner="Player-Owner",version=5,revisionID="r5"},
 {domain="probe",objectId="older",owner="Player-Owner",version=9,revisionID="r9"},
}}
assert(Sync:ReceiveManifest(sameAndStale,"Owner-Realm","Player-Owner"))
assert(#Sync.catchUpJobs==0,"same and older owner revisions do not create fetch jobs")
assert(Sync:ReceiveManifest({schema=1,entries={{domain="probe",objectId="newer",owner="Player-Owner",version=2,revisionID="r2"},{domain="probe",objectId="missing",owner="Player-Owner",version=1,revisionID="r1"}}},"Owner-Realm","Player-Owner"))
assert(#Sync.catchUpJobs==2,"newer and missing local revisions register payload demand")
local queuedJob=Sync.catchUpJobs[1]
assert(Sync:ReceiveManifest({schema=1,entries={{domain="probe",objectId="newer",owner="Player-Owner",version=2,revisionID="r2"}}},"Owner-Realm","Player-Owner"))
assert(#Sync.catchUpJobs==2 and Sync.catchUpJobs[1]==queuedJob,"repeated announcements for one revision coalesce into an existing fetch job")

-- Unknown optional domains are held within a cap and replayed when their module registers.
assert(Sync:ReceiveManifest({schema=1,entries={{domain="futureFeature",objectId="future-object",owner="Player-Owner",version=1,revisionID="future-r1"}}},"Owner-Realm","Player-Owner"))
assert(#Sync.pendingManifestEntries==1,"unloaded optional domain metadata is deferred without a runtime error")
local futureMeta
assert(Sync:RegisterDomain("futureFeature",{getMetadata=function()return futureMeta end,listMetadata=function()return{}end,export=function()return{}end,import=function()return true end}))
assert(#Sync.pendingManifestEntries==0 and #Sync.catchUpJobs==3,"pending optional metadata is considered when its domain becomes available")
Sync.catchUpJobs={};Sync.catchUpIndex={};Sync.outboundCoalescing={}

local pendingStart=clock
for batch=1,5 do
 local entries={};for index=1,64 do entries[index]={domain="notLoaded"..batch,objectId="pending-"..batch.."-"..index,owner="Player-Owner",version=1,revisionID="pending-r1"}end
 assert(Sync:ReceiveManifest({schema=1,entries=entries},"Owner-Realm","Player-Owner"))
end
assert(#Sync.pendingManifestEntries==Sync.maxPendingManifestEntries,"unloaded optional metadata is capped across successive bounded manifests")
assert(Sync:GetNextCleanupAt()==pendingStart+Sync.presenceTimeout,"pending optional metadata uses the existing Presence TTL cleanup")
clock=pendingStart+Sync.presenceTimeout
assert(Sync:Cleanup()and#Sync.pendingManifestEntries==0,"unloaded metadata expires through the existing one-shot cleanup path")

-- Outbound identical requests merge for 750ms, use one Whisper for one peer,
-- and broadcast once only when the whole online guild may receive the block.
local outbound={
 ["single"]={objectId="single",owner="Player-Origin",version=2,revisionID="single-r2"},
 ["shared"]={objectId="shared",owner="Player-Origin",version=3,revisionID="shared-r3"},
 ["private"]={objectId="private",owner="Player-Origin",version=4,revisionID="private-r4"},
}
local function registerOutbound(domainId,id,broadcastSafe,sharePolicy)
 local definition={getMetadata=function(objectId)return objectId==id and outbound[id]or nil end,listMetadata=function()return{}end,export=function(objectId)return{objectId=objectId,payload="one-block"}end,import=function()return true end,broadcastSafe=broadcastSafe}
 if sharePolicy then definition.canShare=sharePolicy;definition.getRecipients=function()return nil end end
 assert(Sync:RegisterDomain(domainId,definition))
end
registerOutbound("outboundOne","single",true)
local sendsBefore=#HolyStorm.Comms.sent
assert(Sync:OnFetch("outboundOne",{objectId="single",knownVersion=0,revisionID="single-r2",requestId="single-a"},"A-Realm"))
local oneJob=Sync.catchUpJobs[#Sync.catchUpJobs]
assert(Sync:OnFetch("outboundOne",{objectId="single",knownVersion=0,revisionID="single-r2",requestId="single-b"},"A-Realm"))
assert(Sync.catchUpJobs[#Sync.catchUpJobs]==oneJob and #oneJob.recipientOrder==1 and #oneJob.recipients["Player-A"].requestIds==2,"duplicate recipient requests coalesce by exact revision")
assert(Sync.requestCoalesceWindow>=.5 and Sync.requestCoalesceWindow<=1,"outbound collection window stays within the requested bound")
clock=clock+1
assert(Sync:RunQueuePump())
assert(#HolyStorm.Comms.sent==sendsBefore+1 and HolyStorm.Comms.sent[#HolyStorm.Comms.sent].channel=="WHISPER"and HolyStorm.Comms.sent[#HolyStorm.Comms.sent].target=="A-Realm","one requester receives exactly one targeted Whisper")
local singleEnvelope=HolyStorm.Comms.sent[#HolyStorm.Comms.sent].envelope
assert(singleEnvelope.data.requestIds[1]=="single-a"and singleEnvelope.data.requestIds[2]=="single-b","the Whisper correlates every merged request ID")
assert(singleEnvelope.data.metadata.owner=="Player-Origin","relaying a payload preserves original owner metadata")

registerOutbound("outboundShared","shared",true)
sendsBefore=#HolyStorm.Comms.sent
assert(Sync:OnFetch("outboundShared",{objectId="shared",knownVersion=0,revisionID="shared-r3",requestId="shared-a"},"A-Realm"))
assert(Sync:OnFetch("outboundShared",{objectId="shared",knownVersion=0,revisionID="shared-r3",requestId="shared-b"},"B-Realm"))
clock=clock+1
assert(Sync:RunQueuePump())
assert(#HolyStorm.Comms.sent==sendsBefore+1 and HolyStorm.Comms.sent[#HolyStorm.Comms.sent].channel=="GUILD","identical authorized requests share one guild transmission")
local sharedEnvelope=HolyStorm.Comms.sent[#HolyStorm.Comms.sent].envelope
assert(sharedEnvelope.data.metadata.revisionID=="shared-r3"and#sharedEnvelope.data.requestIds==2,"the shared payload retains exact revision and all requester correlations")

local function privateShare(_,guid)return guid=="Player-A"or guid=="Player-B","RECIPIENT_SCOPE"end
registerOutbound("outboundPrivate","private",false,privateShare)
sendsBefore=#HolyStorm.Comms.sent
assert(Sync:OnFetch("outboundPrivate",{objectId="private",knownVersion=0,revisionID="private-r4",requestId="private-a"},"A-Realm"))
assert(Sync:OnFetch("outboundPrivate",{objectId="private",knownVersion=0,revisionID="private-r4",requestId="private-b"},"B-Realm"))
assert(not Sync:OnFetch("outboundPrivate",{objectId="private",knownVersion=0,revisionID="private-r4",requestId="private-c"},"C-Realm"),"a requester outside the scope cannot fetch the private payload")
clock=clock+1
assert(Sync:RunQueuePump())
assert(#HolyStorm.Comms.sent==sendsBefore+2,"different recipient permissions use two authorized whispers")
for index=sendsBefore+1,#HolyStorm.Comms.sent do assert(HolyStorm.Comms.sent[index].channel=="WHISPER"and HolyStorm.Comms.sent[index].target~="C-Realm","privacy policy prevents an unauthorized guild broadcast")end

local originalLimit=Sync.catchUpLimit
Sync.catchUpLimit=2;Sync.catchUpJobs={};Sync.catchUpIndex={};Sync.outboundCoalescing={}
outbound.boundedOne={objectId="boundedOne",owner="Player-Origin",version=1,revisionID="bounded-r1"}
outbound.boundedTwo={objectId="boundedTwo",owner="Player-Origin",version=1,revisionID="bounded-r1"}
outbound.boundedThree={objectId="boundedThree",owner="Player-Origin",version=1,revisionID="bounded-r1"}
local bounded={getMetadata=function(objectId)return outbound[objectId]end,listMetadata=function()return{}end,export=function()return{payload="bounded"}end,import=function()return true end,broadcastSafe=true}
assert(Sync:RegisterDomain("boundedOut",bounded))
for index=1,3 do local objectId="bounded"..({"One","Two","Three"})[index];local accepted=Sync:OnFetch("boundedOut",{objectId=objectId,knownVersion=0,revisionID="bounded-r1",requestId="bounded-"..index},"A-Realm");if index<=2 then assert(accepted)else assert(not accepted,"outbound work beyond the configured job limit is rejected")end end
assert(#Sync.catchUpJobs==2 and #Sync.catchUpJobs<=Sync.catchUpLimit,"coalesced outbound work never exceeds the shared Sync queue bound")
Sync.catchUpLimit=originalLimit

-- Bounded queues and the existing HSC1/AceCommQueue contract remain in force.
assert(Sync.catchUpLimit==20000 and Sync.maxPendingManifestEntries==256 and Sync.maxCoalescedRecipients==64,"Sync work and pending metadata have explicit finite bounds")
local protocolFile=assert(io.open(root.."Sync/Comms.lua","rb"));local protocolSource=protocolFile:read("*a");protocolFile:close()
assert(protocolSource:find('protocol="HSC1"',1,true)and protocolSource:find('chunkSize=220',1,true),"coalescing keeps the existing HSC1 framing and transport contract")
assert(not HolyStorm.Tasks.types["Sync.PresenceHeartbeat"],"the Sync core registers no recurring Presence heartbeat task")
for _,task in ipairs(HolyStorm.Tasks.queue)do assert(task.id~="Sync.PresenceHeartbeat","the Sync core queues no recurring Presence heartbeat")end

print("Minimal login Presence, manifest freshness, optional domains, bounded request coalescing, privacy routing and payload transfer tests passed")
