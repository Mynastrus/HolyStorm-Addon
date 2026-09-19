-- Offline contracts for the canonical PlayerData store and metadata-first sync.
local root=(arg[0]:gsub("tools[/\\]test_playerdata_sync.lua$","")).."LIVE/Holy_Storm/"
local clock=1000
unpack=unpack or table.unpack
function time()return clock end;function GetTime()return clock end;function UnitGUID()return"Player-Local"end;function IsInGuild()return true end
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
assert(loadfile(root.."Persistence/PlayerDataStore.lua"))();HolyStorm.PlayerData:Initialize()
assert(HS_Player_DB.schemaVersion==2 and HS_Player_DB.characters["Player-Legacy"])
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
local raidSnapshot={raids={{id=100,name="Current Raid"}},lockouts={{name="Current Raid",difficultyId=14,killed=4,total=8,bosses={}}},lifetime={bosses={}}};assert(HolyStorm.Data.CharacterStore:SetRaidLockouts("Player-Local",raidSnapshot,nil,"blizzard"));local storedRaid,storedRaidMeta=HolyStorm.Data.CharacterStore:GetBlock("Player-Local","raid");assert(storedRaid.raids[1].id==100 and storedRaid.lockouts[1].killed==4 and storedRaidMeta.version==1,"single-field raid snapshot storage contract")
local goodMythic={seasonId=18,overallScore=2500,dungeons={{name="Dungeon",challengeMapId=1,timeLimit=1800,score=250}},affixes={},ownedKey={level=10},updatedAt=clock,snapshotVersion=3,scoreDataReady=true};assert(HolyStorm.Data.CharacterStore:SetMythicPlus("Player-Local",goodMythic,nil,"blizzard"));local storedMythic,storedMythicMeta=HolyStorm.Data.CharacterStore:GetBlock("Player-Local","mythicPlus");assert(storedMythic.overallScore==2500 and storedMythicMeta.version==1,"valid Mythic+ snapshot is stored")
local invalidMythic,invalidMythicReason=HolyStorm.Data.CharacterStore:SetMythicPlus("Player-Local",{seasonId=18,dungeons="broken",snapshotVersion=3},nil,"blizzard");assert(not invalidMythic and invalidMythicReason=="INVALID_MYTHICPLUS_DUNGEONS","malformed Mythic+ blocks are rejected");local emptyMythic,emptyMythicReason=HolyStorm.Data.CharacterStore:SetMythicPlus("Player-Local",{},nil,"blizzard");assert(not emptyMythic and emptyMythicReason=="EMPTY_MYTHICPLUS_DATA","empty Mythic+ blocks are rejected");storedMythic,storedMythicMeta=HolyStorm.Data.CharacterStore:GetBlock("Player-Local","mythicPlus");assert(storedMythic.overallScore==2500 and storedMythicMeta.version==1,"rejected Mythic+ data leaves last-known-good storage untouched")
clock=1010;ok,meta=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","equipment",{equipment={slots={[1]=true}},itemLevel=701},"blizzard");assert(ok and meta.version==2)
local unchanged,unchangedReason=HolyStorm.PlayerData:WriteOwnedBlock("Player-Local","equipment",{equipment={slots={[1]=true}},itemLevel=701},"blizzard");assert(not unchanged and unchangedReason=="UNCHANGED");assert(HolyStorm.PlayerData:GetMetadata("Player-Local","equipment").version==2)
ok=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"equipment",{equipment={slots={[1]="item"}},itemLevel=710},{owner=foreign,version=17,updatedAt=900,source="blizzard"},"Player-Relay","Relay-Realm");assert(ok)
assert(HolyStorm.PlayerData:GetMetadata(foreign,"equipment").version==17)
local stale,reason=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"equipment",{equipment={slots={}},itemLevel=600},{owner=foreign,version=16,updatedAt=950},"Player-Relay","Relay-Realm");assert(not stale and reason=="STALE_VERSION")
local direct=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"equipment",{equipment={slots={[1]="owner"}},itemLevel=711},{owner=foreign,version=17,updatedAt=901},foreign,"Foreign-Realm");assert(direct)
local protected,protectedReason=HolyStorm.PlayerData:AcceptRemoteBlock("Player-Local","equipment",{equipment={slots={}},itemLevel=999},{owner="Player-Local",version=99,updatedAt=999},"Player-Relay","Relay-Realm");assert(not protected and protectedReason=="LOCAL_OWNER_PROTECTED")
local example="Player-Example";assert(HolyStorm.PlayerData:AcceptRemoteBlock(example,"stats",{primary={v=15}},{owner=example,version=15,updatedAt=800},example,"Example-Realm"));assert(HolyStorm.PlayerData:AcceptRemoteBlock(example,"stats",{primary={v=17}},{owner=example,version=17,updatedAt=850},"Player-Relay","Relay-Realm"));assert(HolyStorm.PlayerData:GetMetadata(example,"stats").version==17)
assert(HolyStorm.PlayerData:GetMetadata("Player-Local","equipment").version==2)
assert(HolyStorm.PlayerData:GetForeignWatermark()==901)
HolyStorm.Data.GuildStore={ResolveSenderGuid=function(_,sender)return sender=="Foreign-Realm"and foreign or sender=="Relay-Realm"and"Player-Relay"end,GetCurrent=function()return{roster={}}end}
HolyStorm.Comms={available=true,Send=function(self,payload,channel,target,priority,diagnostics)self.lastPayload,self.lastChannel,self.lastTarget,self.lastPriority,self.lastDiagnostics=payload,channel,target,priority,diagnostics;return true,"tx-sync-test"end};HolyStorm.Tasks={types={},queued={}}
function HolyStorm.Tasks:RegisterTaskType(id,d)self.types[id]=d;return true end
function HolyStorm.Tasks:Queue(id,o)self.queued[#self.queued+1]={id=id,options=o};return"task"end
function HolyStorm.Tasks:ScheduleRecurring()return true end
assert(loadfile(root.."Sync/SyncManager.lua"))();HolyStorm.Sync:Initialize()
assert(HolyStorm.Sync:Publish("character",foreign.."\031equipment","TEST"))
local publish=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(publish.id=="Sync.Publish");HolyStorm.Sync:RunPublish({metadata=publish.options.metadata,priority=65})
local announce=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(announce.id=="Sync.Send"and announce.options.metadata.envelope.kind=="ANNOUNCE");assert(announce.options.metadata.envelope.data.offers[1].data==nil)
assert(HolyStorm.Sync:SendNow({metadata=announce.options.metadata,priority=70,retryCount=0,maxRetries=2}),"sync envelope was not sent");assert(HolyStorm.Comms.lastDiagnostics.direction=="SEND"and HolyStorm.Comms.lastDiagnostics.messageKind=="ANNOUNCE"and HolyStorm.Comms.lastDiagnostics.domain=="character"and HolyStorm.Comms.lastDiagnostics.transmissionId=="tx-sync-test","structured sync SEND diagnostics missing");assert(HolyStorm.Comms.lastDiagnostics.payload==nil and HolyStorm.Comms.lastDiagnostics.envelope==nil and HolyStorm.Comms.lastDiagnostics.data==nil,"sync SEND diagnostics leaked payload data")
local sawSyncSend=false;for _,entry in ipairs(HolyStorm.Logger.history)do local c=entry.context or{};if entry.source=="Sync"and c.direction=="SEND"and c.transmissionId=="tx-sync-test"then sawSyncSend=true end end;assert(sawSyncSend,"sync SEND log entry missing")
local presence=assert(HolyStorm.Serializer:Serialize({protocol=3,kind="PRESENCE",sender=foreign,data={version=1},sentAt=clock}));assert(HolyStorm.Sync:Receive(presence,"Foreign-Realm","GUILD",{transmissionId="tx-sync-receive",packetTotal=1,bytes=#presence,correlationId="corr-sync-receive"}),"sync PRESENCE receive failed");local presenceIdentity,presenceIdentityMeta=HolyStorm.PlayerData:GetBlock(foreign,"identity");assert(presenceIdentity.name==foreignIdentity.name and presenceIdentityMeta.version==7 and presenceIdentityMeta.updatedAt==900,"presence does not mutate foreign identity")
local sawSyncReceive=false;for _,entry in ipairs(HolyStorm.Logger.history)do local c=entry.context or{};if entry.source=="Sync"and c.direction=="RECEIVE"and c.messageKind=="PRESENCE"and c.transmissionId=="tx-sync-receive"and entry.correlationId=="corr-sync-receive"then sawSyncReceive=true end end;assert(sawSyncReceive,"structured sync RECEIVE log entry missing")
HolyStorm.Tasks.queued={};assert(HolyStorm.Sync:OnFetch("character",{objectId=foreign.."\031equipment",knownVersion=16},"Requester-Realm"),"fetch was not accepted");local payload=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(payload and payload.options.metadata.envelope.kind=="PAYLOAD","payload was not queued");assert(payload.options.metadata.target=="Requester-Realm"and payload.options.metadata.channel=="WHISPER","payload was not whispered")
HolyStorm.Sync:RegisterDomain("revision-test",{freshness="revision-chain",getMetadata=function()return{objectId="guild-test",owner="Player-Local",version=5,updatedAt=clock,revisionID="revision-local"}end,listMetadata=function()return{}end,export=function()return{}end,import=function()return true end})
local siblingOffers=HolyStorm.Sync:MetadataForRequest(HolyStorm.Sync:GetDomain("revision-test"),{objectId="guild-test",knownVersion=5,knownRevisionID="revision-remote"});assert(#siblingOffers==1 and siblingOffers[1].revisionID=="revision-local","same-version sibling was suppressed");HolyStorm.Tasks.queued={};assert(HolyStorm.Sync:OnFetch("revision-test",{objectId="guild-test",knownVersion=5,knownRevisionID="revision-remote"},"Requester-Realm"));assert(HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued].options.metadata.envelope.kind=="PAYLOAD")
local live={characterUUID="Player-Local",timestamp=clock,sequence=1};local imported
HolyStorm.Sync:RegisterDomain("live-test",{live=true,catchUp=false,priority=110,getMetadata=function(id)if id=="Player-Local"then return{objectId=id,owner=id,version=live.sequence,updatedAt=live.timestamp}end end,listMetadata=function()return{}end,export=function(id)return id=="Player-Local"and live end,validate=function(payload)return type(payload)=="table"and payload.characterUUID~=nil end,authorize=function(_,meta,senderId,_,id)return meta.owner==id and senderId==id end,import=function(_,payload)imported=payload;return true end})
HolyStorm.Tasks.queued={};HolyStorm.Comms.lastPayload=nil;assert(HolyStorm.Sync:Publish("live-test","Player-Local","LIVE_TEST"));local liveTask=HolyStorm.Tasks.queued[#HolyStorm.Tasks.queued];assert(liveTask.id=="Sync.LivePublish"and liveTask.options.priority==110,"live domain did not use low-priority coalescing task");assert(HolyStorm.Sync:RunLivePublish({metadata=liveTask.options.metadata}));local liveEnvelope=HolyStorm.Serializer:Deserialize(HolyStorm.Comms.lastPayload);assert(liveEnvelope.kind=="LIVE"and liveEnvelope.data.payload.sequence==1 and HolyStorm.Comms.lastPriority==110,"latest live payload was not sent centrally")
local remoteLive={characterUUID=foreign,timestamp=clock,sequence=2};assert(HolyStorm.Sync:OnPayload("live-test",{objectId=foreign,metadata={objectId=foreign,owner=foreign,version=2,updatedAt=clock},payload=remoteLive},"Foreign-Realm")and imported and imported.characterUUID==foreign,"direct live owner payload was not validated/imported")
assert(HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"identity",{name="Foreign-Newer",realm="Realm",class="Priest",classFile="PRIEST",level=81,guild="Guild"},{owner=foreign,version=8,updatedAt=950,source="blizzard"},foreign,"Foreign-Realm"),"newer owner identity accepted")
local newerIdentity,newerIdentityMeta=HolyStorm.PlayerData:GetBlock(foreign,"identity");assert(newerIdentity.name=="Foreign-Newer" and newerIdentityMeta.version==8 and newerIdentityMeta.updatedAt==950,"newer owner identity replaces the older version")
local staleIdentity,staleIdentityReason=HolyStorm.PlayerData:AcceptRemoteBlock(foreign,"identity",{name="Foreign-Old",realm="Realm",class="Priest",classFile="PRIEST",level=79,guild="Guild"},{owner=foreign,version=7,updatedAt=999},"Player-Relay","Relay-Realm");assert(not staleIdentity and staleIdentityReason=="STALE_VERSION","older relayed identity is rejected")
print("PlayerData/sync tests passed")
