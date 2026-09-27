local root=(arg[0]:gsub("tools[/\\]test_version_discovery.lua$","")).."LIVE/Holy_Storm/"
unpack=unpack or table.unpack
local notices,queued,emitted={},{},{}
local HolyStorm={version="5.9.0",Data={GuildStore={ResolveSenderGuid=function(_,sender)return sender=="Peer-Realm"and"Player-Peer"or nil end}},Tasks={},Events={},Logger={Write=function()end},Commands={PrintUserMessage=function(_,message)notices[#notices+1]=message;return true end}}
function HolyStorm:GetAddon()return self end
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({OUTDATED_VERSION_NOTICE="outdated"},{__index=function(_,key)return key end})end}end;return HolyStorm end
function time()return 1000 end;function UnitGUID()return"Player-Local"end;function GetUnitName()return"Local-Realm"end
HolyStorm.Tasks.Queue=function(_,id,options)queued[#queued+1]={id=id,options=options};return"task-"..#queued end
HolyStorm.Events.Emit=function(_,event,...)emitted[#emitted+1]={event,...}end
assert(loadfile(root.."Core/Utils/Utils.lua"))();assert(loadfile(root.."Sync/SyncManager.lua"))();local Sync=HolyStorm.Sync;Sync.ScheduleCleanup=function()return true end

assert(HolyStorm.Utils.CompareSemanticVersions("5.10.0","5.9.0")==1,"numeric SemVer components are not compared lexicographically")
assert(HolyStorm.Utils.CompareSemanticVersions("5.10.0-beta.2","5.10.0-beta.11")==-1 and HolyStorm.Utils.CompareSemanticVersions("5.10.0","5.10.0-beta.11")==1,"SemVer prerelease precedence is supported")
assert(HolyStorm.Utils.CompareSemanticVersions("5.10.0+build.2","5.10.0+build.1")==0,"SemVer build metadata does not affect precedence")
assert(HolyStorm.Utils.CompareSemanticVersions("5.10.0-alpha..1","5.10.0")==nil,"invalid empty SemVer identifiers are incomparable")
Sync:QueueEnvelope("PAYLOAD","character",{objectId="Player-Peer\031equipment",metadata={owner="Player-Peer",version=18},reason="REQUEST_RESPONSE",requestId="abc123"},"WHISPER","Peer-Realm",70);local diagnostics=queued[#queued].options.metadata.diagnostics
assert(diagnostics.domain=="character"and diagnostics.blockType=="equipment"and diagnostics.characterUUID=="Player-Peer"and diagnostics.target=="Peer-Realm"and diagnostics.messageKind=="PAYLOAD"and diagnostics.messageClass=="payload"and diagnostics.requestId=="abc123"and diagnostics.reason=="REQUEST_RESPONSE","sync logs retain domain, block, character, target, kind and correlation fields")

Sync.loginSessionId="LOGIN-test";Sync.presencePublished=false;Sync.outdatedNotified=false;Sync.peerVersionReceived=false;Sync.knownVersions={}
assert(Sync:OnPresence({version="5.10.0",responseTo="LOGIN-test"},"Peer-Realm","Player-Peer"));assert(#notices==0 and not Sync:EvaluateOutdatedVersion(),"the update hint waits until this login's own presence was published")
Sync.presencePublished=true;assert(Sync:EvaluateOutdatedVersion()and#notices==1,"a higher peer version triggers the localized update hint")
assert(not Sync:EvaluateOutdatedVersion()and#notices==1,"the update hint is emitted only once per login session")
Sync.outdatedNotified=false;Sync.peerVersionReceived=true;Sync.knownVersions={peer={version="5.8.9",sender="Peer-Realm",guid="Player-Peer",receivedAt=1000}};assert(not Sync:EvaluateOutdatedVersion()and#notices==1,"older peer versions never trigger a hint")
assert(Sync:GetKnownVersion("peer")=="5.8.9","recent presence exposes its known version")
Sync.knownVersions.peer.receivedAt=1000-Sync.presenceTimeout-1
assert(Sync:GetKnownVersion("peer")==nil and Sync.knownVersions.peer==nil,"stale presence no longer supplies a roster version")
local rosterSource=assert(io.open(root.."../Holy_Storm_Guild/Guild.lua","rb")):read("*a")
assert(rosterSource:find("stored.guid==localGuid and HolyStorm.version",1,true),"the local roster character reads the loaded core addon version directly")

local originalCatchUp=Sync.RunCatchUp;Sync.RunCatchUp=function()return true end;IsInGuild=function()return true end
HolyStorm.version="DEV";local beforePresence=#queued
assert(Sync:RunLoginPresence({metadata={sessionId="LOGIN-dev"}}),"development login presence is queued")
local presence=queued[beforePresence+1].options.metadata.envelope
assert(presence.kind=="PRESENCE"and presence.data.version=="DEV","development Presence advertises the canonical DEV value")
assert(HolyStorm.Utils.CompareSemanticVersions("DEV","5.9.0")==nil,"DEV remains explicitly incomparable with release versions")
Sync.knownVersions={};Sync.presencePublished=true;Sync.outdatedNotified=false
assert(Sync:OnPresence({version="DEV",responseTo="LOGIN-dev"},"Peer-Realm","Player-Peer"),"peer DEV Presence is accepted")
assert(Sync:GetKnownVersion("Player-Peer")=="DEV","recent remote development Presence is available to the Guild Roster")
local noticeCount=#notices;assert(not Sync:EvaluateOutdatedVersion()and#notices==noticeCount,"DEV never triggers a false semantic-version update notice")
Sync.knownVersions={};assert(Sync:OnPresence({version="@project-version@"},"Peer-Realm","Player-Peer"),"invalid placeholder Presence is safely ignored")
assert(Sync:GetKnownVersion("Player-Peer")==nil,"unresolved remote placeholders remain unknown")
Sync.knownVersions["Player-Peer"]={version="@project-version@",receivedAt=1000}
assert(Sync:GetKnownVersion("Player-Peer")==nil and Sync.knownVersions["Player-Peer"]==nil,"stale cached placeholders are discarded at read time")
Sync.RunCatchUp=originalCatchUp
print("Semantic version discovery and once-per-login update notice tests passed")
