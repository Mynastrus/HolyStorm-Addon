local root=(arg[0]:gsub("tools[/\\]test_guild_roster_presence.lua$",""))
local clock=1000
local activeAddon,activeGuid,activeName
local locale=setmetatable({},{__index=function(_,key)return key end})
unpack=unpack or table.unpack

function time()return clock end
function UnitGUID()return activeGuid end
function GetUnitName()return activeName end
function IsInGuild()return true end
function IsLoggedIn()return true end
function GetGuildInfo()return"Storm Guild","Member",5,"Realm"end
function GetNormalizedRealmName()return"Realm"end
function GetRealmName()return"Realm"end
function GuildControlGetNumRanks()return 1 end
function GuildControlGetRankName()return"Member"end
local rosterRows
function GetNumGuildMembers()return #rosterRows end
rosterRows={
 {"Mynastrus-Realm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-Local"},
 {"Maristy-Realm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-A"},
 {"Modus-Realm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-B"},
 {"CrossPeer-OtherRealm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-Cross"},
}
function GetGuildRosterInfo(index)return unpack(rosterRows[index])end
C_Timer={}
function C_Timer.NewTimer(delay,callback)
 local timer={delay=delay,callback=callback,cancelled=false}
 function timer:Cancel()self.cancelled=true end
 return timer
end
local rosterLibrary={}
function rosterLibrary:NormalizeName(name)
 if type(name)~="string"then return nil end
 name=name:match("^%s*(.-)%s*$"):gsub("%s*%-%s*","-")
 local character,realm=name:match("^(.-)%-(.-)$")
 if not character then character=name end
 if character==""then return nil end
 if realm then realm=realm:gsub("%s+","");if realm==""then realm=nil end end
 if not realm and name:lower()~="unknown"then realm="Realm"end
 if realm then return character.."-"..realm end
 return character
end
function LibStub(name,silent)
 if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
 if name=="AceAddon-3.0"then return{GetAddon=function()return activeAddon end,NewAddon=function()return activeAddon end}end
 if name=="LibGuildRoster-1.0"then return rosterLibrary end
 if silent then return nil end
 error("Unexpected library: "..tostring(name))
end

local function makeAddon(name,version)
 local addon={version=version,Data={},db={global={data={guilds={}}}},Comms={available=true,sends={}},Tasks={queue={},registry={}},Events={listeners={}},Logger={history={}},State={},DataManager={},FilterManager={},Modules={}}
 function addon.Tasks:Queue(id,options)self.queue[#self.queue+1]={id=id,options=options or{}};return"task-"..#self.queue end
 function addon.Tasks:RegisterTaskType(id,definition)self.registry[id]=definition;return true end
 function addon.Tasks:Cancel()return true end
 function addon.Tasks:Enqueue(id,callback)if callback then callback()end;return"task-"..id end
 function addon.Events:Register(event,owner,callback)self.listeners[event]=self.listeners[event]or{};self.listeners[event][owner]=callback;return true end
 function addon.Events:Emit(event,...)for _,callback in pairs(self.listeners[event]or{})do callback(event,...)end;return true end
 function addon.Logger:Write(level,source,category,message,context)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context};return true end
 function addon.State:Set()return true end
 function addon:GetModule()return nil end
 function addon.DataManager:RegisterSchema()return true end
 function addon.DataManager:SafeCopy(value)return value end
 function addon.DataManager:Get(_,id)return addon.db.global.data.guilds[id]end
 function addon.Comms:Send(payload,channel,target,priority,diagnostics)
  self.sends[#self.sends+1]={payload=payload,channel=channel,target=target,priority=priority,diagnostics=diagnostics}
  return true,"tx-"..#self.sends
 end
 function addon:RegisterModule(definition,initialize)
  local module={id=definition.id,name=definition.name}
  self.Modules[definition.id]=module
  initialize(module)
  return module
 end
 addon.FilterManager.RegisterTemplate=function()return true end
 addon.Data.CharacterStore={}
 function addon.Data.CharacterStore:Upsert()return true end
 function addon.Data.CharacterStore:Get()return nil end
 addon.PlayerData={}
 function addon.PlayerData:GetForeignWatermark()return 0 end
 return addon
end

local function loadAddonRuntime(addon,guid,name,withGuildStore)
 activeAddon,activeGuid,activeName=addon,guid,name
 addon.testGuid,addon.testName=guid,name
 local rawVersion=addon.version
 C_AddOns={GetAddOnMetadata=function(_,key)assert(key=="Version");return rawVersion end}
 assert(loadfile(root.."LIVE/Holy_Storm/Core/Bootstrap/Bootstrap.lua"))("Holy_Storm")
 addon.Data.CharacterStore={}
 function addon.Data.CharacterStore:Upsert()return true end
 function addon.Data.CharacterStore:Get()return nil end
 assert(loadfile(root.."LIVE/Holy_Storm/Core/Utils/Utils.lua"))()
 addon.Utils.Now=function()return clock end
 assert(loadfile(root.."LIVE/Holy_Storm/Core/Serialization/Serializer.lua"))()
 if withGuildStore then
  assert(loadfile(root.."LIVE/Holy_Storm/Persistence/GuildStore.lua"))()
  addon.Data.GuildStore:Initialize()
  assert(addon.Data.GuildStore:RefreshFromBlizzard(),"real GuildStore loads the Blizzard guild roster")
 else
  addon.Data.GuildStore={ResolveSenderGuid=function()return nil end}
 end
 assert(loadfile(root.."LIVE/Holy_Storm/Sync/SyncManager.lua"))()
 addon.Sync.RunCatchUp=function()return true end
 assert(addon.Sync:Initialize(),"production Sync task types initialize")
end

local receiver=makeAddon("receiver","DEV")
loadAddonRuntime(receiver,"Player-Local","Mynastrus-Realm",true)
activeAddon=receiver
assert(loadfile(root.."LIVE/Holy_Storm_Guild/Guild.lua"))()
local guildRoster=receiver.Modules.GuildRoster
guildRoster.page={IsShown=function()return true end}
guildRoster.GetSettings=function()return{showOffline=true,groupTwinks=false}end
guildRoster.RenderRows=function(self,members)self.lastRendered=members end
guildRoster:OnEnable()

local function renderedVersions()
 guildRoster:Refresh()
 local versions={}
 for _,member in ipairs(guildRoster.lastRendered or{})do versions[member.guid]=member.addonVersion end
 return versions
end
local function assertVersion(versions,guid,expected,message)
 assert(versions[guid]==expected,message.." (expected "..tostring(expected)..", got "..tostring(versions[guid])..")")
end
local function versionLogs(addon)
 local matches={};for _,entry in ipairs(addon.Logger.history)do if entry.message=="Presence version"then matches[#matches+1]=entry end end;return matches
end
local function findLog(addon,message)
 for _,entry in ipairs(addon.Logger.history)do if entry.message==message then return entry end end
end
local function findVersionLog(addon,character,reason)
 for _,entry in ipairs(versionLogs(addon))do local context=entry.context or{};if tostring(context.character):lower()==tostring(character):lower()and context.reason==reason then return entry end end
end
local function sendQueued(addon,guid)
 activeAddon,activeGuid=addon,guid
 for index=#addon.Tasks.queue,1,-1 do
  local queued=addon.Tasks.queue[index]
  if queued.id=="Sync.Send"and not queued.sent then
   queued.sent=true
   assert(addon.Sync:SendNow({metadata=queued.options.metadata,priority=queued.options.priority,retryCount=0,maxRetries=2}),"production Sync transport sends the serialized Presence")
   return assert(addon.Comms.sends[#addon.Comms.sends]and addon.Comms.sends[#addon.Comms.sends].payload)
  end
 end
 error("No queued Sync.Send task for "..guid)
end
local function receiveTo(addon,guid,name,target,wireSender)
 local payload=sendQueued(addon,guid)
 target=target or receiver;wireSender=wireSender or name
 activeAddon,activeGuid,activeName=target,target.testGuid,target.testName
 local resolved=target.Data.GuildStore:ResolveSenderGuid(wireSender,guid)
 local savedComms=target.Comms
 assert(loadfile(root.."LIVE/Holy_Storm/Sync/Comms.lua"))()
 local productionComms=target.Comms
 local transmissionId="HSC1-"..tostring(clock).."-"..tostring((target.testCommsSerial or 0)+1)
 target.testCommsSerial=(target.testCommsSerial or 0)+1
 local total=math.max(1,math.ceil(#payload/productionComms.chunkSize))
 for part=1,total do
  local chunk=payload:sub((part-1)*productionComms.chunkSize+1,part*productionComms.chunkSize)
  local frame=table.concat({productionComms.protocol,transmissionId,part,total,chunk},"|")
  assert(productionComms:OnMessage(productionComms.prefix,frame,"GUILD",wireSender),"production Comms reassembles the Presence frame")
 end
 target.Comms=savedComms
 assert(target.Sync.knownOnline[guid]==clock,"production Comms delivery reaches the production Sync Presence handler for "..tostring(wireSender).." resolved as "..tostring(resolved))
 return payload
end
local function receive(addon,guid,name)return receiveTo(addon,guid,name,receiver,name)end
local function startRemote(guid,name,version)
 local addon=makeAddon(guid,version)
 loadAddonRuntime(addon,guid,name,true)
 addon.Sync.loginSessionId="LOGIN-"..guid
 assert(addon.Sync:RunLoginPresence({metadata={sessionId=addon.Sync.loginSessionId}}),"remote login Presence is published")
 local payload=receive(addon,guid,name)
 return addon,payload
end
local function heartbeat(addon,guid,name)
 activeAddon,activeGuid,activeName=addon,guid,name
 local heartbeatTask=assert(addon.Tasks.registry["Sync.PresenceHeartbeat"],"heartbeat task is registered"):execute({metadata={}})
 assert(heartbeatTask,"online peer runs its scheduled Presence refresh")
 receive(addon,guid,name)
end
local function heartbeatTo(addon,guid,name,target)
 activeAddon,activeGuid,activeName=addon,guid,name
 local heartbeatTask=assert(addon.Tasks.registry["Sync.PresenceHeartbeat"],"heartbeat task is registered"):execute({metadata={}})
 assert(heartbeatTask,"online peer runs its scheduled Presence refresh")
 return receiveTo(addon,guid,name,target)
end

local versions=renderedVersions()
assert(receiver.version=="DEV"and receiver:GetVersion()=="DEV","Bootstrap resolves the local development build to DEV")
assertVersion(versions,"Player-Local","DEV","the local character uses the canonical local version")
assert(receiver.Sync.knownVersions["Player-Local"].localPlayer==true,"the local authoritative version is represented in the central Sync version store")
local savedLocalGuid=activeGuid;activeGuid=nil;versions=renderedVersions();assertVersion(versions,"Player-Local","DEV","a roster refresh during transient UnitGUID unavailability retains the cached local authority");activeGuid=savedLocalGuid
assertVersion(versions,"Player-A",nil,"remote A is unknown before Presence")
assertVersion(versions,"Player-B",nil,"remote B is unknown before Presence")
receiver.Events.listeners.PLAYER_LOGIN["sync-presence"]("PLAYER_LOGIN")
versions=renderedVersions();assertVersion(versions,"Player-Local","DEV","login Presence initialization cannot clear the local version")
receiver.version="5.10.0";versions=renderedVersions();assertVersion(versions,"Player-Local","5.10.0","a release build displays its resolved local version through the same store")
receiver.version="DEV";versions=renderedVersions();assertVersion(versions,"Player-Local","DEV","restoring the resolved development version updates the same store")
receiver.Sync:OnPresence({version="8.0.0"},"Mynastrus-Realm","Player-Local")
assert(receiver.Sync:GetKnownVersion("Player-Local")=="DEV","a Presence payload cannot replace the local authoritative build")

local peerA,peerAAnnounce=startRemote("Player-A","Maristy-Realm","5.9.0")
local peerB=startRemote("Player-B","Modus-Realm","5.9.0")
local peerCross=startRemote("Player-Cross","CrossPeer-OtherRealm","8.1.0")
local sentRelease=receiver.Serializer:Deserialize(peerAAnnounce)
assert(sentRelease.kind=="PRESENCE"and sentRelease.data.version=="5.9.0","release clients put their resolved addon version in the actual serialized Presence payload")
local peerAnnounce=findLog(peerA,"Presence announce")
assert(peerAnnounce and peerAnnounce.context.character=="Maristy-Realm"and peerAnnounce.context.version=="5.9.0","a client logs its compact Presence announce with the actual release version")
versions=renderedVersions()
assertVersion(versions,"Player-A","5.9.0","initial remote A Presence reaches the roster")
assertVersion(versions,"Player-B","5.9.0","initial remote B Presence reaches the roster")
assertVersion(versions,"Player-Cross","8.1.0","cross-realm Presence maps into the same GUID key the roster UI reads")
local receivedLog=findLog(receiver,"Sync envelope received")
assert(receivedLog and receivedLog.context.sender=="Maristy-Realm"and receivedLog.context.senderGuid=="Player-A"and receivedLog.context.claimedGuid=="Player-A"and receivedLog.context.version=="5.9.0"and receivedLog.context.identityReason=="GUID_AND_NAME_MATCH","Retail receive diagnostics include the wire sender, claimed/resolved GUID and incoming version")
local learnedLog=findVersionLog(receiver,"maristy-realm","PRESENCE_VERSION_LEARNED")
assert(learnedLog and learnedLog.level=="DEBUG"and learnedLog.context.character=="maristy-realm"and learnedLog.context.guid=="Player-A"and learnedLog.context.sender=="Maristy-Realm"and learnedLog.context.old=="UNKNOWN"and learnedLog.context.incoming=="5.9.0"and learnedLog.context.result=="5.9.0"and learnedLog.context.receivedAt==1000 and learnedLog.context.expiresAt==1300,"new remote versions have one structured DEBUG change log with normalized identity and TTL")
local bareGuid,bareReason=receiver.Data.GuildStore:ResolveSenderGuid("Maristy","Player-A")
assert(bareGuid=="Player-A"and bareReason=="GUID_AND_NAME_MATCH","a bare same-realm addon sender resolves to the canonical roster GUID")
local crossGuid=receiver.Data.GuildStore:ResolveSenderGuid("CrossPeer - Other Realm","Player-Cross")
assert(crossGuid=="Player-Cross","spacing in a qualified cross-realm sender normalizes to the roster identity")
local completeName=rosterRows[2][1];rosterRows[2][1]="Maristy"
assert(receiver.Data.GuildStore:RefreshFromBlizzard(),"roster refresh accepts a same-realm row without an explicit realm")
local qualifiedGuid=receiver.Data.GuildStore:ResolveSenderGuid("Maristy-Realm","Player-A")
assert(qualifiedGuid=="Player-A","a qualified addon sender resolves against the bare same-realm roster row")
activeAddon,activeGuid,activeName=peerA,"Player-A","Maristy-Realm"
local aliasPayload=peerA.Sync:QueueEnvelope("PRESENCE",nil,{version="5.9.0",reason="SENDER_ALIAS_TEST"},"GUILD",nil,90)
assert(aliasPayload,"qualified sender alias Presence is queued")
receiveTo(peerA,"Player-A","Maristy-Realm",receiver,"Maristy-Realm")
rosterRows[2][1]=completeName;assert(receiver.Data.GuildStore:RefreshFromBlizzard(),"roster identity is restored after alias normalization test")
local crossPeerView=renderedVersions();assertVersion(crossPeerView,"Player-Cross","8.1.0","cross-realm peer remains visible after sender normalization checks")
activeAddon,activeGuid,activeName=receiver,"Player-Local","Mynastrus-Realm"
assert(receiver.Sync:RunLoginPresence({metadata={sessionId=receiver.Sync.loginSessionId}}),"local DEV client announces its current resolved version")
local localPayload=receiveTo(receiver,"Player-Local","Mynastrus-Realm",peerA)
local localEnvelope=receiver.Serializer:Deserialize(localPayload)
assert(localEnvelope.data.version=="DEV"and peerA.Sync:GetKnownVersion("Player-Local")=="DEV","client B's real Receive and GuildStore path exposes client A DEV on B's roster")
local localAnnounce=findLog(receiver,"Presence announce")
assert(localAnnounce and localAnnounce.context.character=="Mynastrus-Realm"and localAnnounce.context.version=="DEV","DEV announce is logged once with the transmitted local version")
activeAddon,activeGuid,activeName=peerA,"Player-A","Maristy-Realm"
peerA.Sync:QueueEnvelope("PRESENCE",nil,{version="7.0.0",reason="UNRESOLVED_SENDER_TEST"},"GUILD",nil,90)
local unknownPayload=sendQueued(peerA,"Player-A")
activeAddon,activeGuid,activeName=receiver,"Player-Local","Mynastrus-Realm"
assert(not receiver.Sync:Receive(unknownPayload,"NotAGuildMember","GUILD",{transmissionId="test-unresolved-sender"}),"an unverified sender is not promoted to a confirmed Holy Storm peer")
assert(receiver.Sync:GetKnownVersion("Player-A")=="5.9.0","a version from a sender that cannot map to the roster is not stored")
local unresolvedLog=findVersionLog(receiver,"notaguildmember-realm","CLAIMED_GUID_NAME_MISMATCH")
assert(unresolvedLog and unresolvedLog.context.sender=="NotAGuildMember"and unresolvedLog.context.claimedGuid=="Player-A"and unresolvedLog.context.incoming=="7.0.0"and unresolvedLog.context.result=="UNKNOWN","unresolved Presence logs the sender, claim, incoming version and resolution reason")
local completeRosterRow=rosterRows[2]
rosterRows[2]={"Maristy-Realm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,nil}
receiver.Events.listeners.GUILD_ROSTER_UPDATE["guild-roster"]("GUILD_ROSTER_UPDATE")
assert(receiver.Sync:GetKnownVersion("Player-A")=="5.9.0","an incomplete Blizzard roster row cannot overwrite the independent known Presence version")
rosterRows[2]=completeRosterRow;receiver.Events.listeners.GUILD_ROSTER_UPDATE["guild-roster"]("GUILD_ROSTER_UPDATE")
local localLoginHandler=receiver.Events.listeners.PLAYER_LOGIN["sync-presence"];localLoginHandler("PLAYER_LOGIN")
versions=renderedVersions();assertVersion(versions,"Player-Local","DEV","a repeated login reconciliation preserves the local build");assertVersion(versions,"Player-A","5.9.0","a repeated login reconciliation preserves fresh remote Presence")
assert(receiver.Sync:Discover("character",nil,{reason="VERSION_RETENTION_TEST"}),"Sync.Discover queues its ordinary metadata discovery")
versions=renderedVersions();assertVersion(versions,"Player-Local","DEV","Sync.Discover does not replace local version authority");assertVersion(versions,"Player-A","5.9.0","Sync.Discover does not clear a known peer version")

for _,peer in ipairs({peerA,peerB})do
 local scheduled
 for index=#peer.Tasks.queue,1,-1 do if peer.Tasks.queue[index].id=="Sync.PresenceHeartbeat"then scheduled=peer.Tasks.queue[index];break end end
 assert(scheduled and scheduled.options.delay>=peer.Sync.presenceRefreshMin and scheduled.options.delay<=peer.Sync.presenceRefreshMin+peer.Sync.presenceRefreshJitter,"login refresh is jittered inside the version freshness window")
end
clock=1250
local logsBeforeHeartbeat=#versionLogs(receiver)
heartbeat(peerA,"Player-A","Maristy-Realm")
heartbeat(peerB,"Player-B","Modus-Realm")
assert(#versionLogs(receiver)==logsBeforeHeartbeat,"unchanged Presence heartbeats do not spam version-change logs")
clock=1301
receiver.Events.listeners.GUILD_ROSTER_UPDATE["guild-roster"]("GUILD_ROSTER_UPDATE")
versions=renderedVersions();assertVersion(versions,"Player-Local","DEV","GUILD_ROSTER_UPDATE retains the current local build");assertVersion(versions,"Player-A","5.9.0","GUILD_ROSTER_UPDATE retains the current remote version")
assert(receiver.Data.GuildStore:RefreshFromBlizzard()==false,"ordinary Blizzard roster rebuild keeps the loaded roster stable")
versions=renderedVersions()
assertVersion(versions,"Player-A","5.9.0","ordinary roster rebuild retains refreshed remote A Presence")
assertVersion(versions,"Player-B","5.9.0","ordinary roster rebuild retains refreshed remote B Presence")

activeAddon,activeGuid,activeName=peerA,"Player-A","Maristy-Realm"
local logsBeforeVersionless=#versionLogs(receiver)
peerA.Sync:QueueEnvelope("PRESENCE",nil,{reason="PARTIAL_METADATA_REFRESH"},"GUILD",nil,90)
receive(peerA,"Player-A","Maristy-Realm")
assert(receiver.Sync.knownVersions["Player-A"].version=="5.9.0"and receiver.Sync.knownVersions["Player-A"].receivedAt==1301,"a versionless Presence preserves the known value and refreshes its live-peer expiry")
assert(#versionLogs(receiver)==logsBeforeVersionless,"a versionless Presence that leaves the version unchanged does not spam change logs")
for _,incomingVersion in ipairs({"","UNKNOWN"})do
 activeAddon,activeGuid,activeName=peerA,"Player-A","Maristy-Realm"
 peerA.Sync:QueueEnvelope("PRESENCE",nil,{version=incomingVersion,reason="PARTIAL_METADATA_REFRESH"},"GUILD",nil,90)
 receive(peerA,"Player-A","Maristy-Realm")
 assert(receiver.Sync:GetKnownVersion("Player-A")=="5.9.0","empty and UNKNOWN version fields preserve a known peer version")
end
assert(#versionLogs(receiver)==logsBeforeVersionless,"missing, empty and UNKNOWN Presence versions do not spam change logs")
versions=renderedVersions();assertVersion(versions,"Player-A","5.9.0","versionless Presence still renders the last known remote version")

peerA.version="5.10.0"
peerB.version="DEV"
clock=1303
heartbeat(peerA,"Player-A","Maristy-Realm")
heartbeat(peerB,"Player-B","Modus-Realm")
heartbeatTo(peerB,"Player-B","Modus-Realm",peerA)
activeAddon,activeGuid,activeName=receiver,"Player-Local","Mynastrus-Realm"
versions=renderedVersions()
assertVersion(versions,"Player-A","5.10.0","fresh authoritative Presence replaces the cached release version")
assertVersion(versions,"Player-B","DEV","remote DEV remains visible after a fresh Presence")
assert(peerA.Sync:GetKnownVersion("Player-B")=="DEV","client B's actual DEV Presence reaches client A's GUID-keyed version store")
local changedLog=findVersionLog(receiver,"Maristy-Realm","PRESENCE_VERSION_UPDATED")
assert(changedLog and changedLog.context.old=="5.9.0"and changedLog.context.incoming=="5.10.0"and changedLog.context.result=="5.10.0","a changed remote release is logged with old, incoming and result values")
local savedRemoteVersion=receiver.Sync.knownVersions["Player-A"]
receiver.Sync.knownVersions["Player-A"]=nil
versions=renderedVersions();assertVersion(versions,"Player-A",nil,"the roster UI reads the current Sync store and does not retain a separate version cache")
receiver.Sync.knownVersions["Player-A"]=savedRemoteVersion
versions=renderedVersions();assertVersion(versions,"Player-A","5.10.0","restoring the central Sync record updates the roster UI directly")

clock=1400
heartbeat(peerA,"Player-A","Maristy-Realm")
rosterRows[3][9]=false
assert(receiver.Data.GuildStore:RefreshFromBlizzard(),"Blizzard roster marks an expired peer offline")
assert(receiver.Sync:GetKnownVersion("Player-B")=="DEV","offline roster status alone does not discard a still-fresh confirmed Presence version")
versions=renderedVersions();assertVersion(versions,"Player-B","DEV","offline rows retain the version until the confirmed Presence TTL expires")
clock=1604
assert(receiver.Sync:Cleanup(),"production Sync cleanup runs")
assert(receiver.Sync.knownVersions["Player-B"]==nil,"cleanup removes an expired remote version at the canonical Presence TTL")
assert(receiver.Sync.knownVersions["Player-Local"] and receiver.Sync.knownVersions["Player-Local"].version=="DEV","Presence expiry does not remove the local authoritative version entry")
assert(findVersionLog(receiver,"Modus-Realm","PRESENCE_EXPIRED"),"remote version expiry emits one targeted DEBUG change log")
versions=renderedVersions()
assertVersion(versions,"Player-Local","DEV","local DEV remains independent of remote cache expiry")
assertVersion(versions,"Player-A","5.10.0","fresh A Presence remains available")
assertVersion(versions,"Player-B",nil,"an expired remote peer returns to unknown in the roster")

print("Guild roster remote Presence refresh, partial update, replacement, DEV and expiry regression tests passed")
