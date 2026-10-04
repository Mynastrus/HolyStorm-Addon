-- Offline contracts for the canonical PlayerData store and metadata-first sync.
local root=(arg[0]:gsub("tools[/\\]test_playerdata_sync.lua$","")).."LIVE/Holy_Storm/"
local clock=1000
local timers={}
unpack=unpack or table.unpack
local activeGuid="Player-Local"
function time()return clock end;function GetTime()return clock end;function UnitGUID()return activeGuid end;function GetUnitName()return"Local-Realm"end;function IsInGuild()return true end
C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback,cancelled=false};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}
local HolyStorm={db={global={localPlayerId="account-local",installId="install",data={characters={},players={},characterOwners={}}}},Data={},State={Set=function()end}}
function HolyStorm:GetAddon()return self end
local locale=setmetatable({}, {__index=function(_,key)return key end})
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;return HolyStorm end
assert(loadfile(root.."Core/Utils/Utils.lua"))();assert(loadfile(root.."Core/Serialization/Serializer.lua"))()
HolyStorm.Logger={history={}}
function HolyStorm.Logger:Write(level,source,category,message,context,correlationId)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context,correlationId=correlationId}end
HolyStorm.Events={listeners={},emitted={}}
function HolyStorm.Events:Register(event,owner,fn)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=fn end
function HolyStorm.Events:Emit(event,...)self.emitted[#self.emitted+1]=event;for _,fn in pairs(self.listeners[event]or{})do fn(event,...)end end
HS_Player_DB={ ["Player-Legacy"]={guid="Player-Legacy",equipment={slots={},version=4},mythicPlus={seasonId=18,dungeons={{name="Legacy Dungeon",challengeMapId=1,timeLimit=1800}},version=4,updatedAt=900},version=4,updatedAt=400} }
assert(loadfile(root.."Persistence/PlayerDataStore.lua"))()
HolyStorm.PlayerData:RegisterBlock("equipment",{fields={"equipment","itemLevel"},event="HS_EQUIPMENT_UPDATED",owner="equipment",schemaVersion=4,snapshotVersion=4})
HolyStorm.PlayerData:RegisterBlock("raid",{fields={"raidLockouts"},event="HS_RAIDLOCKS_UPDATED",staleAfter=100})
HolyStorm.PlayerData:RegisterBlock("stats",{fields={"stats"},event="HS_STATS_UPDATED"})
HolyStorm.PlayerData:RegisterBlock("mythicPlus",{fields={"mythicPlus"},event="HS_MYTHICPLUS_UPDATED",validate=function(data)if type(data)~="table"then return false,"INVALID_MYTHICPLUS_DATA"end;if data.dungeons~=nil and type(data.dungeons)~="table"then return false,"INVALID_MYTHICPLUS_DUNGEONS"end;local count=0;for _,dungeon in pairs(type(data.dungeons)=="table"and data.dungeons or{})do if type(dungeon)~="table"then return false,"INVALID_MYTHICPLUS_DUNGEON"end;count=count+1 end;if data.seasonId==nil and data.overallScore==nil and data.ownedKey==nil and count==0 then return false,"EMPTY_MYTHICPLUS_DATA"end;return true end})
local function validDelves(data)return type(data)=="table"and type(data.runs)=="table","INVALID_DELVES_DATA"end
HolyStorm.PlayerData:RegisterBlock("delves",{fields={"delves"},event="HS_DELVES_UPDATED",validate=validDelves})
HolyStorm.PlayerData:RegisterBlock("localOnly",{fields={"localOnly"},syncEnabled=false,schemaVersion=2,snapshotVersion=1})
local invalidBlock,invalidBlockReason=HolyStorm.PlayerData:RegisterBlock("invalidVersion",{fields={"invalidField"},schemaVersion=0});assert(not invalidBlock and invalidBlockReason=="INVALID_BLOCK_VERSION"and HolyStorm.PlayerData.fieldToBlock.invalidField==nil,"invalid descriptors do not partially claim fields")
HolyStorm.PlayerData:Initialize()
assert(HS_Player_DB.schemaVersion==2 and HS_Player_DB.characters["Player-Legacy"])
assert(HS_Player_DB.normalizationVersion==1 and HS_Player_DB.normalizedBlocks.mythicPlus==true,"player data migration work is persistently marked after the combined normalization pass")
local playerDiagnostics=HolyStorm.PlayerData:GetDiagnostics();assert(playerDiagnostics.characters==1 and playerDiagnostics.blocks>=1,"player data diagnostics expose record and block counts")
local legacyMythic,legacyMythicMeta=HolyStorm.PlayerData:GetBlock("Player-Legacy","mythicPlus");assert(legacyMythic and legacyMythic.seasonId==18 and legacyMythicMeta.updatedAt==900,"legacy Mythic+ snapshot survives reload with its block timestamp")
assert(loadfile(root.."Persistence/CharacterStore.lua"))();assert(loadfile(root.."Persistence/PlayerStore.lua"))();HolyStorm.Data.PlayerStore:Initialize();HolyStorm.Data.CharacterStore:Initialize();HolyStorm.Data.PlayerStore:LinkLocalCharacter("Player-Local")
local ok,meta=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","equipment",{equipment={slots={}},itemLevel=700},"blizzard");assert(ok and meta.version==1)
local localIdentity={name="Local-Realm",realm="Realm",class="Paladin",classFile="PALADIN",level=80,guild="Guild"}
local localIdentityOk,localIdentityMeta=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","identity",localIdentity,"blizzard")
assert(localIdentityOk and localIdentityMeta.version==1,"local identity uses the authoritative owner commit")
local localIdentityTimestamp=localIdentityMeta.updatedAt
local foreign="Player-Foreign"
local foreignIdentity={name="Foreign-Realm",realm="Realm",class="Priest",classFile="PRIEST",level=80,guild="Guild"}
assert(HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"identity",foreignIdentity,{owner=foreign,version=7,updatedAt=900,source="blizzard"},foreign,"Foreign-Realm"),"foreign owner identity accepted")
local foreignLegacyMeta=HolyStorm.PlayerData:GetCharacter(foreign).blockMeta.identity;foreignLegacyMeta.receivedAt=nil
local unknownForeignFreshness=HolyStorm.PlayerData:GetBlockFreshness(foreign,"identity");assert(unknownForeignFreshness.state=="UNKNOWN"and unknownForeignFreshness.stale and unknownForeignFreshness.age==nil,"legacy foreign snapshots without receiver-clock metadata are unknown and eligible for refresh")
local foreignIdentityBefore,foreignIdentityMetaBefore=HolyStorm.PlayerData:GetBlock(foreign,"identity")
local emittedBefore=#HolyStorm.Events.emitted
assert(not HolyStorm.PlayerData:ObserveIdentity(foreign,{name="Observed-Realm",level=81},"blizzard"),"foreign observation must not mutate identity")
local foreignIdentityAfter,foreignIdentityMetaAfter=HolyStorm.PlayerData:GetBlock(foreign,"identity")
assert(foreignIdentityAfter.name==foreignIdentityBefore.name and foreignIdentityAfter.level==foreignIdentityBefore.level,"foreign observation preserves authoritative identity")
assert(foreignIdentityMetaAfter.version==foreignIdentityMetaBefore.version and foreignIdentityMetaAfter.updatedAt==foreignIdentityMetaBefore.updatedAt,"foreign observation preserves owner freshness")
assert(#HolyStorm.Events.emitted==emittedBefore,"foreign observation emits no persistence event")
HolyStorm.Data.GuildStore={GetCurrent=function()return{roster={[foreign]={name="Observed-Realm",realm="Realm",class="Priest",level=81,online=true}}}end}
local rosterMember=HolyStorm.Data.GuildStore:GetCurrent().roster[foreign]
assert(rosterMember.name=="Observed-Realm" and rosterMember.level==81 and rosterMember.online,"roster observation remains available for display")
local rosterEventsBefore=#HolyStorm.Events.emitted
assert(not HolyStorm.Data.CharacterStore:Upsert(foreign,{name="Observed-Realm",level=81},"blizzard"),"foreign roster upsert must not mutate identity")
assert(#HolyStorm.Events.emitted==rosterEventsBefore,"foreign roster observation emits no owner event")
assert(HolyStorm.PlayerData:GetMetadata("Player-Local","identity").version==1 and HolyStorm.PlayerData:GetMetadata("Player-Local","identity").updatedAt==localIdentityTimestamp,"local identity revision remains authoritative")
local raidSnapshot={raids={{id=100,name="Current Raid"}},lockouts={{name="Current Raid",difficultyId=14,killed=4,total=8,bosses={}}},lifetime={bosses={[501]={id=501,raidInstanceId=100,difficulties={NORMAL={kills=7,source="blizzard-statistic",statisticId=7001}}}}}};assert(HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","raid",raidSnapshot,"blizzard"));local storedRaid,storedRaidMeta=HolyStorm.Data.CharacterStore:GetBlock("Player-Local","raid");assert(storedRaid.raids[1].id==100 and storedRaid.lockouts[1].killed==4 and storedRaidMeta.version==1 and storedRaid.lifetime.bosses[501].difficulties.NORMAL.kills==7,"single-field raid snapshot storage contract preserves lifetime")
local raidFreshness=HolyStorm.PlayerData:GetBlockFreshness("Player-Local","raid");assert(raidFreshness.metadataExists and not raidFreshness.stale and raidFreshness.updatedAt==clock and raidFreshness.staleAfter==100 and raidFreshness.age==0,"block freshness uses the registered staleAfter and authoritative block commit timestamp")
clock=1101;raidFreshness=HolyStorm.PlayerData:GetBlockFreshness("Player-Local","raid");assert(raidFreshness.stale and raidFreshness.age==101 and HolyStorm.PlayerData:IsStale("Player-Local","raid"),"block freshness becomes stale only after the registered interval")
local missingFreshness=HolyStorm.PlayerData:GetBlockFreshness("Player-Local","stats");assert(not missingFreshness.metadataExists and missingFreshness.stale,"missing block metadata is centrally classified as stale")
clock=1000
local goodMythic={seasonId=18,overallScore=2500,dungeons={{name="Dungeon",challengeMapId=1,timeLimit=1800,score=250}},dungeonCount=1,poolComplete=true,updatedAt=clock,schemaVersion=5,snapshotVersion=5,scoreDataReady=true};assert(HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","mythicPlus",goodMythic,"blizzard"));local storedMythic,storedMythicMeta=HolyStorm.Data.CharacterStore:GetBlock("Player-Local","mythicPlus");assert(storedMythic.overallScore==2500 and storedMythicMeta.version==1,"valid Mythic+ v5 snapshot is stored")
local invalidMythic,invalidMythicReason=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","mythicPlus",{seasonId=18,dungeons="broken",snapshotVersion=3},"blizzard");assert(not invalidMythic and invalidMythicReason=="INVALID_MYTHICPLUS_DUNGEONS","malformed Mythic+ blocks are rejected");local emptyMythic,emptyMythicReason=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","mythicPlus",{},"blizzard");assert(not emptyMythic and emptyMythicReason=="EMPTY_MYTHICPLUS_DATA","empty Mythic+ blocks are rejected");storedMythic,storedMythicMeta=HolyStorm.Data.CharacterStore:GetBlock("Player-Local","mythicPlus");assert(storedMythic.overallScore==2500 and storedMythicMeta.version==1,"rejected Mythic+ data leaves last-known-good storage untouched")
clock=1010;ok,meta=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","equipment",{equipment={slots={[1]=true}},itemLevel=701},"blizzard");assert(ok and meta.version==2)
local unchanged,unchangedReason=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","equipment",{equipment={slots={[1]=true}},itemLevel=701},"blizzard");assert(not unchanged and unchangedReason=="UNCHANGED");assert(HolyStorm.PlayerData:GetMetadata("Player-Local","equipment").version==2)
local timestampOnly,timestampOnlyReason=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","equipment",{equipment={slots={[1]=true},updatedAt=999,snapshotVersion=77},itemLevel=701},"blizzard");assert(not timestampOnly and timestampOnlyReason=="UNCHANGED"and HolyStorm.PlayerData:GetMetadata("Player-Local","equipment").version==2,"nested block snapshot timestamps and version metadata do not create an authoritative revision")
local nestedSemanticA=HolyStorm.PlayerData:FingerprintSnapshot({value={updatedAt=1}});local nestedSemanticB=HolyStorm.PlayerData:FingerprintSnapshot({value={updatedAt=2}});assert(nestedSemanticA~=nestedSemanticB,"metadata filtering applies to the snapshot envelope while nested domain values remain semantic")
ok=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"equipment",{equipment={slots={[1]="item"}},itemLevel=710},{owner=foreign,version=17,updatedAt=900,source="blizzard"},"Player-Relay","Relay-Realm");assert(ok)
assert(HolyStorm.PlayerData:GetMetadata(foreign,"equipment").version==17)
local stale,reason=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"equipment",{equipment={slots={}},itemLevel=600},{owner=foreign,version=16,updatedAt=950},"Player-Relay","Relay-Realm");assert(not stale and reason=="STALE_REVISION")
local direct=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"equipment",{equipment={slots={[1]="item"}},itemLevel=710},{owner=foreign,version=17,updatedAt=900},foreign,"Foreign-Realm");assert(direct and HolyStorm.PlayerData:GetMetadata(foreign,"equipment").direct,"same-revision identical direct copy upgrades relay authority as a no-op")
local protected,protectedReason=HolyStorm.PlayerData:AcceptRemoteBlock("Player-Local","equipment",{equipment={slots={}},itemLevel=999},{owner="Player-Local",version=99,updatedAt=999},"Player-Relay","Relay-Realm");assert(not protected and protectedReason=="SELF_OWNED_REMOTE_REJECT")
local protectedDirect,protectedDirectReason=HolyStorm.PlayerData:AcceptRemoteBlock("Player-Local","equipment",{equipment={slots={}},itemLevel=999},{owner="Player-Local",version=99,updatedAt=999},"Player-Local","Local-Realm");assert(not protectedDirect and protectedDirectReason=="SELF_OWNED_REMOTE_REJECT","remote higher revisions never replace locally owned data, even with claimed direct provenance")
local example="Player-Example";assert(HolyStorm.PlayerData:AcceptRemoteBlock(example,"stats",{primary={v=15}},{owner=example,version=15,updatedAt=800},example,"Example-Realm"));assert(HolyStorm.PlayerData:AcceptRemoteBlock(example,"stats",{primary={v=17}},{owner=example,version=17,updatedAt=850},"Player-Relay","Relay-Realm"));assert(HolyStorm.PlayerData:GetMetadata(example,"stats").version==17)
assert(HolyStorm.PlayerData:GetMetadata("Player-Local","equipment").version==2)
local equipmentDescriptor=HolyStorm.PlayerData:GetBlockDefinition("equipment");local equipmentEnvelope=HolyStorm.PlayerData:GetMetadata("Player-Local","equipment");assert(equipmentDescriptor.owner=="equipment"and equipmentDescriptor.schemaVersion==4 and equipmentDescriptor.snapshotVersion==4,"PlayerData exposes the central feature block descriptor");assert(equipmentEnvelope.block=="equipment"and equipmentEnvelope.guid=="Player-Local"and equipmentEnvelope.schemaVersion==4 and equipmentEnvelope.snapshotVersion==4,"block envelope exposes character identity and schema versions")
assert(HolyStorm.PlayerData:GetForeignWatermark()==900)
HolyStorm.Data.GuildStore={ResolveSenderGuid=function(_,sender)return sender=="Foreign-Realm"and foreign or sender=="Relay-Realm"and"Player-Relay"end,GetCurrent=function()return{roster={}}end}
HolyStorm.Comms={available=true,chunkSize=220,receiveLimits={maxFragments=300,maxPayloadBytes=66000},Send=function(self,payload,channel,target,priority,diagnostics,onComplete,onProgress)self.lastPayload,self.lastChannel,self.lastTarget,self.lastPriority,self.lastDiagnostics=payload,channel,target,priority,diagnostics;if onProgress then onProgress(1,1)end;if onComplete then onComplete(true,"tx-sync-test",#payload)end;return true,"tx-sync-test"end};HolyStorm.Tasks={types={},queued={},sequence=0}
function HolyStorm.Tasks:RegisterTaskType(id,d)self.types[id]=d;return true end
function HolyStorm.Tasks:Queue(id,o)o=o or{};local definition=self.types[id]or{};local mode=o.executionMode or definition.executionMode;if mode=="MERGE_BY_KEY"or mode=="UNIQUE"then for _,entry in ipairs(self.queued)do if entry.id==id and(mode=="UNIQUE"or entry.options.mergeKey==o.mergeKey)then return entry.uid,"MERGED"end end end;self.sequence=self.sequence+1;local uid="task-"..self.sequence;self.queued[#self.queued+1]={id=id,uid=uid,status="QUEUED",options=o};return uid,"QUEUED"end
function HolyStorm.Tasks:GetTask(id)for _,entry in ipairs(self.queued)do if entry.uid==id then return{uniqueId=id,status=entry.status,metadata=entry.options.metadata}end end end
function HolyStorm.Tasks:Cancel()return true end
function HolyStorm.Tasks:ScheduleRecurring()error("Sync must not register an idle recurring cleanup")end
assert(loadfile(root.."Sync/SyncManager.lua"))();HolyStorm.Sync:Initialize();assert(#timers==0,"Sync initialization must not schedule cleanup without expirable state")
local syncQueueBeforeLocalOnly=#HolyStorm.Tasks.queued;assert(HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","localOnly",{value=1},"test"));assert(#HolyStorm.Tasks.queued==syncQueueBeforeLocalOnly,"a block with sync disabled is never published after a local commit");assert(HolyStorm.Sync:GetDomain("character").export("Player-Local\031localOnly")==nil,"sync-disabled blocks are not exported");local disabledRemote,disabledRemoteReason=HolyStorm.PlayerData:AcceptRemoteBlock("Player-Disabled","localOnly",{value=2},{owner="Player-Disabled",version=1,updatedAt=900},"Player-Disabled","Disabled-Realm");assert(not disabledRemote and disabledRemoteReason=="SYNC_DISABLED","sync-disabled blocks reject remote imports")
local raidPayload=HolyStorm.Sync:GetDomain("character").export("Player-Local\031raid");assert(raidPayload and raidPayload.data.lifetime.bosses[501].difficulties.NORMAL.statisticId==7001,"generic character Sync export retains nested Raid statistic provenance")
local queuedBeforeRemote=#HolyStorm.Tasks.queued;assert(HolyStorm.PlayerData:AcceptRemoteBlock("Player-NoPingPong","stats",{primary={v=1}},{owner="Player-NoPingPong",version=1,updatedAt=clock},"Player-NoPingPong","NoPingPong-Realm"));assert(#HolyStorm.Tasks.queued==queuedBeforeRemote,"an incoming character payload does not emit the owned-update event or queue an outgoing sync")
local eventsBeforeNoop=#HolyStorm.Events.emitted;local queuedBeforeNoop=#HolyStorm.Tasks.queued;local noChange,noChangeReason=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","equipment",{equipment={slots={[1]=true}},itemLevel=701},"blizzard");assert(not noChange and noChangeReason=="UNCHANGED"and#HolyStorm.Events.emitted==eventsBeforeNoop and#HolyStorm.Tasks.queued==queuedBeforeNoop,"a no-op owner write changes no revision, emits no owned update and queues no publish")
local selfEnvelope=assert(HolyStorm.Serializer:Serialize({protocol=3,kind="PRESENCE",sender="Player-Local",data={version=1},sentAt=clock}));local selfLogCount=#HolyStorm.Logger.history;assert(not HolyStorm.Sync:Receive(selfEnvelope,"Local-Realm","GUILD")and#HolyStorm.Logger.history==selfLogCount,"Sync receive must retain the UnitGUID sender defense")
assert(HolyStorm.Sync:Publish("character",foreign.."\031equipment","TEST"))
local publish=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(publish.id=="Sync.Publish");HolyStorm.Sync:RunPublish({metadata=publish.options.metadata,priority=65})
local announce=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(announce.id=="Sync.Send"and announce.options.metadata.envelope.kind=="ANNOUNCE");assert(announce.options.metadata.envelope.data.offers[1].data==nil)
local beforeDuplicatePublish=#HolyStorm.Tasks.queued;assert(HolyStorm.Sync:RunPublish({metadata=publish.options.metadata,priority=65})and#HolyStorm.Tasks.queued==beforeDuplicatePublish,"an identical metadata version is not broadcast twice")
assert(HolyStorm.Sync:SendNow({metadata=announce.options.metadata,priority=70,retryCount=0,maxRetries=2}),"sync envelope was not sent");assert(HolyStorm.Comms.lastDiagnostics.direction=="SEND"and HolyStorm.Comms.lastDiagnostics.messageKind=="ANNOUNCE"and HolyStorm.Comms.lastDiagnostics.domain=="character"and HolyStorm.Comms.lastDiagnostics.transmissionId=="tx-sync-test","structured sync SEND diagnostics missing");assert(HolyStorm.Comms.lastDiagnostics.payload==nil and HolyStorm.Comms.lastDiagnostics.envelope==nil and HolyStorm.Comms.lastDiagnostics.data==nil,"sync SEND diagnostics leaked payload data")
local sawSyncSend=false;for _,entry in ipairs(HolyStorm.Logger.history)do local c=entry.context or{};if entry.source=="Sync"and c.direction=="SEND"and c.transmissionId=="tx-sync-test"then sawSyncSend=true end end;assert(sawSyncSend,"sync SEND log entry missing")
local presence=assert(HolyStorm.Serializer:Serialize({protocol=3,kind="PRESENCE",sender=foreign,data={version=1},sentAt=clock}));assert(HolyStorm.Sync:Receive(presence,"Foreign-Realm","GUILD",{transmissionId="tx-sync-receive",packetTotal=1,bytes=#presence,correlationId="corr-sync-receive"}),"sync PRESENCE receive failed");local presenceIdentity,presenceIdentityMeta=HolyStorm.PlayerData:GetBlock(foreign,"identity");assert(presenceIdentity.name==foreignIdentity.name and presenceIdentityMeta.version==7 and presenceIdentityMeta.updatedAt==900,"presence does not mutate foreign identity")
local sawSyncReceive=false;for _,entry in ipairs(HolyStorm.Logger.history)do local c=entry.context or{};if entry.source=="Sync"and c.direction=="RECEIVE"and c.messageKind=="PRESENCE"and c.transmissionId=="tx-sync-receive"and entry.correlationId=="corr-sync-receive"then sawSyncReceive=true end end;assert(sawSyncReceive,"structured sync RECEIVE log entry missing")
HolyStorm.Tasks.queued={};HolyStorm.Sync.catchUpJobs={};HolyStorm.Sync.catchUpIndex={};assert(HolyStorm.Sync:OnFetch("character",{objectId=foreign.."\031equipment",knownVersion=16,requestId="owner-fetch"},"Requester-Realm"),"fetch was not accepted");local outbound=HolyStorm.Sync.catchUpJobs[1];assert(outbound and outbound.kind=="SEND"and outbound.target=="Requester-Realm"and outbound.objectId==foreign.."\031equipment","outbound payload is queued as one object-scoped job without eager export")
local invalidPrivacy,invalidPrivacyReason=HolyStorm.Sync:RegisterDomain("invalid-privacy-test",{getMetadata=function()end,listMetadata=function()return{}end,export=function()end,import=function()end,canShare=function()return true end});assert(not invalidPrivacy and invalidPrivacyReason=="INVALID_DOMAIN","recipient-aware domains require both authorization and recipient enumeration")
local privacyMeta={objectId="private-object",owner="Player-Local",version=1,updatedAt=clock,visibility="OFFICERS"};local privacyExports=0
HolyStorm.Sync:RegisterDomain("privacy-test",{getMetadata=function(id)return id=="private-object"and privacyMeta end,listMetadata=function()return{privacyMeta}end,export=function()privacyExports=privacyExports+1;return{secret="payload"}end,import=function()return true end,canShare=function(_,recipientGuid)return recipientGuid==foreign end,getRecipients=function()return{{guid=foreign,name="Foreign-Realm"},{guid="Player-Blocked",name="Blocked-Realm"}}end})
assert(#HolyStorm.Sync:MetadataForRequest(HolyStorm.Sync:GetDomain("privacy-test"),{objectId="private-object",knownVersion=0},nil,"Blocked-Realm")==0,"unauthorized metadata is not offered")
assert(#HolyStorm.Sync:MetadataForRequest(HolyStorm.Sync:GetDomain("privacy-test"),{objectId="private-object",knownVersion=0},foreign,"Foreign-Realm")==1,"authorized metadata is offered")
HolyStorm.Tasks.queued={};assert(HolyStorm.Sync:RunOffer({metadata={domain="privacy-test",request={requestId="privacy-request",objectId="private-object",knownVersion=0},requester="Foreign-Realm",responseChannel="GUILD"}}));local targetedOffer=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(targetedOffer.options.metadata.channel=="WHISPER"and targetedOffer.options.metadata.target=="Foreign-Realm","visibility-filtered discovery offers are not guild-broadcast")
HolyStorm.Tasks.queued={};assert(not HolyStorm.Sync:OnFetch("privacy-test",{objectId="private-object",knownVersion=0},"Blocked-Realm")and#HolyStorm.Tasks.queued==0 and privacyExports==0,"unauthorized fetch is rejected before export")
HolyStorm.Tasks.queued={};HolyStorm.Sync.catchUpJobs={};HolyStorm.Sync.catchUpIndex={};assert(HolyStorm.Sync:OnFetch("privacy-test",{objectId="private-object",knownVersion=0,requestId="private-fetch"},"Foreign-Realm")and HolyStorm.Sync.catchUpJobs[1].target=="Foreign-Realm"and privacyExports==0,"authorized response is queued for targeted export without eager work")
HolyStorm.Tasks.queued={};assert(HolyStorm.Sync:Publish("privacy-test","private-object","PRIVACY_TEST"));local privacyPublish=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];HolyStorm.Sync:RunPublish({metadata=privacyPublish.options.metadata});local privateOffers=0;for _,entry in ipairs(HolyStorm.Tasks.queued)do if entry.id=="Sync.Send"and entry.options.metadata.envelope.domain=="privacy-test"then privateOffers=privateOffers+1;assert(entry.options.metadata.channel=="WHISPER"and entry.options.metadata.target=="Foreign-Realm","sensitive metadata publish targets only authorized recipients")end end;assert(privateOffers==1,"exactly one authorized private offer")
HolyStorm.Sync:RegisterDomain("revision-test",{freshness="revision-chain",getMetadata=function()return{objectId="guild-test",owner="Player-Local",version=5,updatedAt=clock,revisionID="revision-local"}end,listMetadata=function()return{}end,export=function()return{}end,import=function()return true end})
local siblingOffers=HolyStorm.Sync:MetadataForRequest(HolyStorm.Sync:GetDomain("revision-test"),{objectId="guild-test",knownVersion=5,knownRevisionID="revision-remote"});assert(#siblingOffers==1 and siblingOffers[1].revisionID=="revision-local","same-version sibling was suppressed");HolyStorm.Tasks.queued={};HolyStorm.Sync.catchUpJobs={};HolyStorm.Sync.catchUpIndex={};assert(HolyStorm.Sync:OnFetch("revision-test",{objectId="guild-test",knownVersion=5,knownRevisionID="revision-remote",requestId="revision-fetch"},"Requester-Realm"));assert(HolyStorm.Sync.catchUpJobs[1].kind=="SEND"and HolyStorm.Sync.catchUpJobs[1].objectId=="guild-test","revision-chain sibling response remains an object-scoped queued transfer")
local live={characterUUID="Player-Local",timestamp=clock,sequence=1};local imported
HolyStorm.Sync:RegisterDomain("live-test",{live=true,catchUp=false,priority=110,getMetadata=function(id)if id=="Player-Local"then return{objectId=id,owner=id,version=live.sequence,updatedAt=live.timestamp}end end,listMetadata=function()return{}end,export=function(id)return id=="Player-Local"and live end,validate=function(payload)return type(payload)=="table"and payload.characterUUID~=nil end,authorize=function(_,meta,senderId,_,id)return meta.owner==id and senderId==id end,import=function(_,payload)imported=payload;return true end})
HolyStorm.Tasks.queued={};HolyStorm.Comms.lastPayload=nil;assert(HolyStorm.Sync:Publish("live-test","Player-Local","LIVE_TEST"));local liveTask=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(liveTask.id=="Sync.LivePublish"and liveTask.options.priority==110,"live domain did not use low-priority coalescing task");assert(HolyStorm.Sync:RunLivePublish({metadata=liveTask.options.metadata}));local liveEnvelope=HolyStorm.Serializer:Deserialize(HolyStorm.Comms.lastPayload);assert(liveEnvelope.kind=="LIVE"and liveEnvelope.data.payload.sequence==1 and HolyStorm.Comms.lastPriority==110,"latest live payload was not sent centrally")
local remoteLive={characterUUID=foreign,timestamp=clock,sequence=2};assert(HolyStorm.Sync:OnPayload("live-test",{objectId=foreign,metadata={objectId=foreign,owner=foreign,version=2,updatedAt=clock},payload=remoteLive},"Foreign-Realm",nil,"LIVE"));assert(not imported,"payload is not visible to domain import until the receive task runs");assert(HolyStorm.Sync:RunReceivePayload()and imported and imported.characterUUID==foreign,"complete live owner payload is validated/imported by the TaskManager receive step")
HolyStorm.Tasks.queued={};HolyStorm.Sync.catchUpJobs={};HolyStorm.Sync.catchUpIndex={};local offerRequest="fanout-request";HolyStorm.Sync.requests[offerRequest]={id=offerRequest,key="fanout",domain="character",candidates={},createdAt=clock,reason="LOGIN_CATCHUP"};local offeredObjects={foreign.."\031identity",foreign.."\031equipment",foreign.."\031stats"};local offers={};for _,objectId in ipairs(offeredObjects)do local localMeta=HolyStorm.Sync:GetDomain("character").getMetadata(objectId);offers[#offers+1]={objectId=objectId,owner=foreign,version=(localMeta and localMeta.version or 0)+1,updatedAt=clock+1}end;offers[#offers+1]=offers[2];assert(HolyStorm.Sync:RecordOffers("character",{requestId=offerRequest,requester="Local-Realm",offers=offers},"Foreign-Realm"))
local selectTasks=0;for _,entry in ipairs(HolyStorm.Tasks.queued)do if entry.id=="Sync.SelectSource"then selectTasks=selectTasks+1 end end;assert(selectTasks==0,"metadata reconciliation adds jobs to the central queue without per-object selector tasks");assert(#HolyStorm.Sync.catchUpJobs==3,"three distinct offered blocks produce three bounded logical jobs")
local duplicateId,duplicateState=HolyStorm.Sync:QueueFetch("character",offeredObjects[2],"Foreign-Realm",17,"LOGIN_CATCHUP",nil,offerRequest,offers[2]);assert(duplicateId==HolyStorm.Sync.catchUpJobs[2].key and duplicateState=="MERGED"and#HolyStorm.Sync.catchUpJobs==3,"an identical character/domain/revision request is coalesced")
local selectedSource=HolyStorm.Sync:BestSource(HolyStorm.Sync.catchUpJobs[2]);assert(selectedSource and selectedSource.sender=="Foreign-Realm"and selectedSource.version==18,"central source election retains the freshest valid owner candidate")
assert(HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"identity",{name="Foreign-Newer",realm="Realm",class="Priest",classFile="PRIEST",level=81,guild="Guild"},{owner=foreign,version=8,updatedAt=950,source="blizzard"},foreign,"Foreign-Realm"),"newer owner identity accepted")
local newerIdentity,newerIdentityMeta=HolyStorm.PlayerData:GetBlock(foreign,"identity");assert(newerIdentity.name=="Foreign-Newer" and newerIdentityMeta.version==8 and newerIdentityMeta.updatedAt==950,"newer owner identity replaces the older version")
local staleIdentity,staleIdentityReason=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"identity",{name="Foreign-Old",realm="Realm",class="Priest",classFile="PRIEST",level=79,guild="Guild"},{owner=foreign,version=7,updatedAt=999},"Player-Relay","Relay-Realm");assert(not staleIdentity and staleIdentityReason=="STALE_REVISION","older relayed identity is rejected")

-- Simulate origin commits produced after /hs scan all, then restore the receiver
-- database and deliver real serialized Sync envelopes through Sync:Receive.
local receiverDB=HS_Player_DB
local noway="Player-Nowaynowak"
local originSnapshots={}
HS_Player_DB={}
activeGuid=noway;clock=50
assert(loadfile(root.."Persistence/PlayerDataStore.lua"))()
HolyStorm.PlayerData:RegisterBlock("equipment",{fields={"equipment","itemLevel"},event="HS_EQUIPMENT_UPDATED",owner="equipment",schemaVersion=4,snapshotVersion=4})
HolyStorm.PlayerData:RegisterBlock("raid",{fields={"raidLockouts"},event="HS_RAIDLOCKS_UPDATED",staleAfter=100})
HolyStorm.PlayerData:RegisterBlock("stats",{fields={"stats"},event="HS_STATS_UPDATED"})
HolyStorm.PlayerData:RegisterBlock("mythicPlus",{fields={"mythicPlus"},event="HS_MYTHICPLUS_UPDATED"})
HolyStorm.PlayerData:RegisterBlock("delves",{fields={"delves"},event="HS_DELVES_UPDATED",validate=validDelves})
HolyStorm.PlayerData:Initialize()
local sawCommittedBeforePublish=false
HolyStorm.Events:Register("HS_PLAYERDATA_OWNED_UPDATED","freshness-test",function(_,guid,block,metadata)
 if guid==noway then local persisted=HolyStorm.PlayerData:GetMetadata(guid,block);sawCommittedBeforePublish=persisted and persisted.version==metadata.version and persisted.originCreatedAt==metadata.originCreatedAt end
end)
assert(HolyStorm.PlayerData:WriteOwnedBlock(noway,"equipment",{equipment={slots={[1]="old"}},itemLevel=700},"blizzard"))
clock=60
assert(HolyStorm.PlayerData:WriteOwnedBlock(noway,"equipment",{equipment={slots={[1]="new"}},itemLevel=710},"blizzard"))
assert(HolyStorm.PlayerData:WriteOwnedBlock(noway,"stats",{primary={strength=1234},snapshotVersion=2},"blizzard"))
assert(HolyStorm.PlayerData:WriteOwnedBlock(noway,"delves",{runs={{level=10}},snapshotVersion=1},"blizzard"))
assert(sawCommittedBeforePublish,"owned sync event fires only after revision and snapshot metadata are committed")
for _,block in ipairs({"equipment","stats","delves"})do
 local objectId=noway.."\031"..block
 originSnapshots[block]={metadata=HolyStorm.PlayerData:GetMetadata(noway,block),payload=HolyStorm.Sync:GetDomain("character").export(objectId)}
 assert(originSnapshots[block].metadata.version==(block=="equipment"and 2 or 1))
end
local queuedCommitted=0
for _,task in ipairs(HolyStorm.Tasks.queued)do if task.id=="Sync.Publish"then queuedCommitted=queuedCommitted+1 end end
assert(queuedCommitted>=2,"committed blocks queue downstream Sync.Publish tasks")

HS_Player_DB=receiverDB;activeGuid="Player-Local";clock=1000
assert(loadfile(root.."Persistence/PlayerDataStore.lua"))()
HolyStorm.PlayerData:RegisterBlock("equipment",{fields={"equipment","itemLevel"},event="HS_EQUIPMENT_UPDATED",owner="equipment",schemaVersion=4,snapshotVersion=4})
HolyStorm.PlayerData:RegisterBlock("raid",{fields={"raidLockouts"},event="HS_RAIDLOCKS_UPDATED",staleAfter=100})
HolyStorm.PlayerData:RegisterBlock("stats",{fields={"stats"},event="HS_STATS_UPDATED"})
HolyStorm.PlayerData:RegisterBlock("mythicPlus",{fields={"mythicPlus"},event="HS_MYTHICPLUS_UPDATED"})
HolyStorm.PlayerData:RegisterBlock("delves",{fields={"delves"},event="HS_DELVES_UPDATED",validate=validDelves})
HolyStorm.PlayerData:Initialize()
assert(HolyStorm.PlayerData:AcceptRemoteBlock(noway,"equipment",{equipment={slots={[1]="relay-old"}},itemLevel=690},{owner=noway,version=1,updatedAt=999999,source="blizzard"},"Player-Relay","Relay-Realm"))
HolyStorm.Data.GuildStore.ResolveSenderGuid=function(_,sender)if sender=="Nowaynowak-Blackmoore"then return noway elseif sender=="RelayCopy-Realm"then return"Player-RelayCopy"elseif sender=="Relay-Realm"then return"Player-Relay"elseif sender=="Foreign-Realm"then return foreign end end
local requestSequence=0
local function primeIncomingFetch(objectId,sender,senderGuid)
 HolyStorm.Sync:ResetActivityState("PLAYERDATA_RECEIVE_FIXTURE");requestSequence=requestSequence+1;local requestId="freshness-"..requestSequence;local transfer={kind="FETCH",objectId=objectId,characterUUID=objectId:match("^(.-)\031"),domain="character",activityDomain=objectId:match("\031([^\031]+)$"),direction="RECEIVE",phase="REQUEST",selectedSource=sender,selectedSourceGuid=senderGuid,requestId=requestId,startedAt=clock,awaitingResponse=true,timeoutAt=clock+30};HolyStorm.Sync.activeTransfer=transfer;transfer.timeoutTimer=C_Timer.NewTimer(30,function()HolyStorm.Sync:RetryTimedOut(requestId,transfer)end);HolyStorm.Sync:BeginTransferActivity(transfer);return requestId
end
local function receiveOriginBlock(block)
 local snapshot=originSnapshots[block];local objectId=noway.."\031"..block;local requestId=primeIncomingFetch(objectId,"Nowaynowak-Blackmoore",noway)
 local envelope={protocol=3,kind="PAYLOAD",domain="character",sender=noway,data={objectId=objectId,requestId=requestId,metadata=snapshot.metadata,payload=snapshot.payload}}
 local wire=assert(HolyStorm.Serializer:Serialize(envelope))
 return HolyStorm.Sync:Receive(wire,"Nowaynowak-Blackmoore","GUILD",{transmissionId="retail-freshness-"..block,packetTotal=19,bytes=#wire})and HolyStorm.Sync:RunReceivePayload()
end
assert(receiveOriginBlock("equipment"),"a direct current origin revision imports over an older relayed block despite differing clock values")
assert(receiveOriginBlock("stats"),"a second independently committed character block imports through the same envelope path")
assert(receiveOriginBlock("delves"),"a third independently committed character block imports through the same envelope path")
local newEquipment,newEquipmentMeta=HolyStorm.PlayerData:GetBlock(noway,"equipment")
assert(newEquipment.itemLevel==710 and newEquipmentMeta.version==2 and newEquipmentMeta.owner==noway and newEquipmentMeta.receivedFrom=="Nowaynowak-Blackmoore" and newEquipmentMeta.originCreatedAt==60 and newEquipmentMeta.receivedAt==clock,"accepted origin metadata stays separate from receiver time and relay provenance")
local newStats,newStatsMeta=HolyStorm.PlayerData:GetBlock(noway,"stats")
assert(newStats.primary.strength==1234 and newStatsMeta.version==1 and newStatsMeta.originCreatedAt==60 and newStatsMeta.receivedAt==clock,"multiple post-scan block snapshots retain their own revisions and origin timestamps")
local newDelves,newDelvesMeta=HolyStorm.PlayerData:GetBlock(noway,"delves");assert(#newDelves.runs==1 and newDelvesMeta.version==1,"optional Delves snapshot is independently accepted")
local invalidOptionalId=primeIncomingFetch(noway.."\031delves","Nowaynowak-Blackmoore",noway);local invalidOptionalWire=assert(HolyStorm.Serializer:Serialize({protocol=3,kind="PAYLOAD",domain="character",sender=noway,data={objectId=noway.."\031delves",requestId=invalidOptionalId,metadata=originSnapshots.delves.metadata,payload={guid=noway,block="delves",data={runs="malformed"}}}}))
assert(HolyStorm.Sync:Receive(invalidOptionalWire,"Nowaynowak-Blackmoore","GUILD"),"complete transport payload is queued for the receive task");assert(HolyStorm.Sync:RunReceivePayload());local retainedDelves=HolyStorm.PlayerData:GetBlock(noway,"delves");assert(#retainedDelves.runs==1,"invalid optional block envelope is rejected atomically and leaves the previous snapshot intact")
assert(HolyStorm.PlayerData:GetBlock(noway,"equipment").itemLevel==710 and HolyStorm.PlayerData:GetBlock(noway,"stats").primary.strength==1234,"one invalid block does not roll back independently committed character blocks")

-- Equal revision and identical content is an idempotent successful receive;
-- direct provenance upgrades a relayed copy without changing origin metadata.
local relayGuid="Player-RelayCopy"
local relayData={equipment={slots={[1]="same"}},itemLevel=720}
assert(HolyStorm.PlayerData:AcceptRemoteBlock(relayGuid,"equipment",relayData,{owner=relayGuid,version=42,updatedAt=400,source="blizzard"},"Player-Relay","Relay-Realm"))
local directId=primeIncomingFetch(relayGuid.."\031equipment","RelayCopy-Realm",relayGuid);local directWire=assert(HolyStorm.Serializer:Serialize({protocol=3,kind="PAYLOAD",domain="character",sender=relayGuid,data={objectId=relayGuid.."\031equipment",requestId=directId,metadata={owner=relayGuid,version=42,updatedAt=400,source="blizzard"},payload={guid=relayGuid,block="equipment",data=relayData}}}))
assert(HolyStorm.Sync:Receive(directWire,"RelayCopy-Realm","GUILD")and HolyStorm.Sync:RunReceivePayload(),"same revision direct copy succeeds as an idempotent no-op after relay")
local relayDirectMeta=HolyStorm.PlayerData:GetMetadata(relayGuid,"equipment");assert(relayDirectMeta.version==42 and relayDirectMeta.direct and relayDirectMeta.receivedFrom=="RelayCopy-Realm" and relayDirectMeta.updatedAt==400,"direct provenance upgrades without rewriting origin revision or timestamp: "..HolyStorm.Serializer:Serialize(relayDirectMeta))
local conflictOk,conflictReason=HolyStorm.PlayerData:AcceptRemoteBlock(relayGuid,"equipment",{equipment={slots={[1]="conflict"}},itemLevel=721},{owner=relayGuid,version=42,updatedAt=500},relayGuid,"RelayCopy-Realm")
assert(not conflictOk and conflictReason=="SAME_REVISION_CONFLICT","same revision with different content is rejected deterministically")
local staleRelayOk,staleRelayReason=HolyStorm.PlayerData:AcceptRemoteBlock(relayGuid,"equipment",{equipment={slots={}},itemLevel=700},{owner=relayGuid,version=41,updatedAt=999999},"Player-Relay","Relay-Realm")
assert(not staleRelayOk and staleRelayReason=="STALE_REVISION","later received stale relay cannot replace a newer origin revision")
local conflictLogged=false
for _,entry in ipairs(HolyStorm.Logger.history)do local c=entry.context or{};if entry.source=="PlayerData"and c.reason=="SAME_REVISION_CONFLICT"and c.character==relayGuid and c.block=="equipment"then conflictLogged=c.decision=="REJECT"and c.incomingRevision==42 and c.storedRevision==42 and c.incomingOriginCreatedAt==500 and c.validationStatus=="PASSED"end end
assert(conflictLogged,"same-revision conflicts produce bounded block-specific structured diagnostics")

local noopId=primeIncomingFetch(relayGuid.."\031equipment","RelayCopy-Realm",relayGuid);local noopWire=assert(HolyStorm.Serializer:Serialize({protocol=3,kind="PAYLOAD",domain="character",sender=relayGuid,data={objectId=relayGuid.."\031equipment",requestId=noopId,metadata={owner=relayGuid,version=42,updatedAt=400,source="blizzard"},payload={guid=relayGuid,block="equipment",data=relayData}}}))
assert(HolyStorm.Sync:Receive(noopWire,"RelayCopy-Realm","GUILD")and HolyStorm.Sync:RunReceivePayload(),"identical same-revision envelope is not surfaced as an import failure")
local persistedRevision=HolyStorm.PlayerData:GetMetadata(noway,"equipment").version
assert(loadfile(root.."Persistence/PlayerDataStore.lua"))()
for _,definition in ipairs({
 {"equipment",{fields={"equipment","itemLevel"},event="HS_EQUIPMENT_UPDATED"}},
 {"raid",{fields={"raidLockouts"},event="HS_RAIDLOCKS_UPDATED",staleAfter=100}},
 {"stats",{fields={"stats"},event="HS_STATS_UPDATED"}},
 {"mythicPlus",{fields={"mythicPlus"},event="HS_MYTHICPLUS_UPDATED"}},
 {"delves",{fields={"delves"},event="HS_DELVES_UPDATED",validate=validDelves}}
})do HolyStorm.PlayerData:RegisterBlock(definition[1],definition[2])end
HolyStorm.PlayerData:Initialize()
local reloadedMeta=HolyStorm.PlayerData:GetMetadata(noway,"equipment")
assert(reloadedMeta.version==persistedRevision and reloadedMeta.originCreatedAt==60 and reloadedMeta.receivedFrom=="Nowaynowak-Blackmoore" and reloadedMeta.receivedAt==1000,"revision, origin and receiver metadata survive PlayerData reload")
print("PlayerData/sync freshness regressions passed")
print("PlayerData/sync tests passed")
