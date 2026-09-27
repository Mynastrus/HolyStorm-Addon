local root=(arg[0]:gsub("tools[/\\]test_guild_roster_presence.lua$",""))
local clock=1000
local activeAddon,activeGuid,activeName
local locale=setmetatable({},{__index=function(_,key)return key end})
unpack=unpack or table.unpack

function time()return clock end
function UnitGUID()return activeGuid end
function GetUnitName()return activeName end
function IsInGuild()return true end
function GetGuildInfo()return"Storm Guild","Member",5,"Realm"end
function GetNormalizedRealmName()return"Realm"end
function GetRealmName()return"Realm"end
function GuildControlGetNumRanks()return 1 end
function GuildControlGetRankName()return"Member"end
function GetNumGuildMembers()return 3 end
local rosterRows={
 {"Mynastrus-Realm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-Local"},
 {"Maristy-Realm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-A"},
 {"Modus-Realm","Member",5,80,"Paladin","City","","",true,0,"PALADIN",0,0,false,false,0,"Player-B"},
}
function GetGuildRosterInfo(index)return unpack(rosterRows[index])end
C_Timer={}
function C_Timer.NewTimer(delay,callback)
 local timer={delay=delay,callback=callback,cancelled=false}
 function timer:Cancel()self.cancelled=true end
 return timer
end
function LibStub(name)
 if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end
 if name=="AceAddon-3.0"then return{GetAddon=function()return activeAddon end}end
 error("Unexpected library: "..tostring(name))
end

local function makeAddon(name,version)
 local addon={version=version,Data={},db={global={data={guilds={}}}},Comms={available=true,sends={}},Tasks={queue={},registry={}},Events={},Logger={},State={},DataManager={},FilterManager={},Modules={}}
 function addon.Tasks:Queue(id,options)self.queue[#self.queue+1]={id=id,options=options or{}};return"task-"..#self.queue end
 function addon.Tasks:RegisterTaskType(id,definition)self.registry[id]=definition;return true end
 function addon.Tasks:Cancel()return true end
 function addon.Events:Register()return true end
 function addon.Events:Emit()return true end
 function addon.Logger:Write()return true end
 function addon.State:Set()return true end
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

local function renderedVersions()
 guildRoster:Refresh()
 local versions={}
 for _,member in ipairs(guildRoster.lastRendered or{})do versions[member.guid]=member.addonVersion end
 return versions
end
local function assertVersion(versions,guid,expected,message)
 assert(versions[guid]==expected,message.." (expected "..tostring(expected)..", got "..tostring(versions[guid])..")")
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
local function receive(addon,guid,name)
 local payload=sendQueued(addon,guid)
 activeAddon,activeGuid,activeName=receiver,"Player-Local","Mynastrus-Realm"
 assert(receiver.Sync:Receive(payload,name,"GUILD",{transmissionId="test-"..guid}),"production Sync receive resolves a guild sender")
end
local function startRemote(guid,name,version)
 local addon=makeAddon(guid,version)
 loadAddonRuntime(addon,guid,name,false)
 addon.Sync.loginSessionId="LOGIN-"..guid
 assert(addon.Sync:RunLoginPresence({metadata={sessionId=addon.Sync.loginSessionId}}),"remote login Presence is published")
 receive(addon,guid,name)
 return addon
end
local function heartbeat(addon,guid,name)
 activeAddon,activeGuid,activeName=addon,guid,name
 local heartbeatTask=assert(addon.Tasks.registry["Sync.PresenceHeartbeat"],"heartbeat task is registered"):execute({metadata={}})
 assert(heartbeatTask,"online peer runs its scheduled Presence refresh")
 receive(addon,guid,name)
end

local versions=renderedVersions()
assertVersion(versions,"Player-Local","DEV","the local character uses the canonical local version")
assertVersion(versions,"Player-A",nil,"remote A is unknown before Presence")
assertVersion(versions,"Player-B",nil,"remote B is unknown before Presence")

local peerA=startRemote("Player-A","Maristy-Realm","5.9.0")
local peerB=startRemote("Player-B","Modus-Realm","5.9.0")
versions=renderedVersions()
assertVersion(versions,"Player-A","5.9.0","initial remote A Presence reaches the roster")
assertVersion(versions,"Player-B","5.9.0","initial remote B Presence reaches the roster")

for _,peer in ipairs({peerA,peerB})do
 local scheduled
 for index=#peer.Tasks.queue,1,-1 do if peer.Tasks.queue[index].id=="Sync.PresenceHeartbeat"then scheduled=peer.Tasks.queue[index];break end end
 assert(scheduled and scheduled.options.delay>=peer.Sync.presenceRefreshMin and scheduled.options.delay<=peer.Sync.presenceRefreshMin+peer.Sync.presenceRefreshJitter,"login refresh is jittered inside the version freshness window")
end
clock=1250
heartbeat(peerA,"Player-A","Maristy-Realm")
heartbeat(peerB,"Player-B","Modus-Realm")
clock=1301
assert(receiver.Data.GuildStore:RefreshFromBlizzard()==false,"ordinary Blizzard roster rebuild keeps the loaded roster stable")
versions=renderedVersions()
assertVersion(versions,"Player-A","5.9.0","ordinary roster rebuild retains refreshed remote A Presence")
assertVersion(versions,"Player-B","5.9.0","ordinary roster rebuild retains refreshed remote B Presence")

activeAddon,activeGuid,activeName=peerA,"Player-A","Maristy-Realm"
peerA.Sync:QueueEnvelope("PRESENCE",nil,{reason="PARTIAL_METADATA_REFRESH"},"GUILD",nil,90)
receive(peerA,"Player-A","Maristy-Realm")
assert(receiver.Sync.knownVersions["Player-A"].version=="5.9.0"and receiver.Sync.knownVersions["Player-A"].receivedAt==1250,"a Presence update without a version preserves the previous version and its freshness")

peerA.version="5.10.0"
peerB.version="DEV"
clock=1303
heartbeat(peerA,"Player-A","Maristy-Realm")
heartbeat(peerB,"Player-B","Modus-Realm")
versions=renderedVersions()
assertVersion(versions,"Player-A","5.10.0","fresh authoritative Presence replaces the cached release version")
assertVersion(versions,"Player-B","DEV","remote DEV remains visible after a fresh Presence")

clock=1400
heartbeat(peerA,"Player-A","Maristy-Realm")
clock=1604
assert(receiver.Sync:Cleanup(),"production Sync cleanup runs")
assert(receiver.Sync.knownVersions["Player-B"]==nil,"cleanup removes an expired remote version at the canonical Presence TTL")
versions=renderedVersions()
assertVersion(versions,"Player-Local","DEV","local DEV remains independent of remote cache expiry")
assertVersion(versions,"Player-A","5.10.0","fresh A Presence remains available")
assertVersion(versions,"Player-B",nil,"an expired remote peer returns to unknown in the roster")

print("Guild roster remote Presence refresh, partial update, replacement, DEV and expiry regression tests passed")
