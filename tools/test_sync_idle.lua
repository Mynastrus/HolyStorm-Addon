local root=(arg[0]:gsub("tools[/\\]test_sync_idle.lua$","")).."LIVE/Holy_Storm/"
local clock=5000
local timers,queued={},{ }
unpack=unpack or table.unpack

local HolyStorm={
 Utils={
  Now=function()return clock end,
  DeepCopy=function(value)if type(value)~="table"then return value end;local out={};for key,child in pairs(value)do out[key]=child end;return out end,
  TableCount=function(value)local count=0;for _ in pairs(value or{})do count=count+1 end;return count end,
 },
 Logger={Write=function()end},
 PlayerData={GetForeignWatermark=function(_,domain)return domain and 100 or 200 end},
 Tasks={},
}
function HolyStorm:GetAddon()return self end
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end;return HolyStorm end
function UnitGUID()return"Player-Local"end
function IsInGuild()return true end
C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback,cancelled=false};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}
function HolyStorm.Tasks:Queue(id,options)queued[#queued+1]={id=id,options=options};return"task-"..#queued end
function HolyStorm.Tasks:Cancel()return true end

assert(loadfile(root.."Sync/SyncManager.lua"))()
local Sync=HolyStorm.Sync
local domain={getMetadata=function()end,listMetadata=function()return{}end,export=function()end,import=function()return true end}
Sync.domains={character=domain,permissions=domain}

assert(Sync:ScheduleCleanup()==false and#timers==0 and#queued==0,"empty sync state must not schedule cleanup")
assert(Sync:RunCatchUp(),"login catch-up should run while guilded")
local discoveries={};for _,entry in ipairs(queued)do if entry.id=="Sync.Discover"then discoveries[#discoveries+1]=entry end end
assert(#discoveries==2,"login catch-up must create one discovery for each core domain")
local scopes={};for _,entry in ipairs(discoveries)do scopes[entry.options.metadata.domain]=true end
assert(scopes.character and scopes.permissions,"character and permissions discoveries are distinct logical scopes")
assert(#timers==1 and timers[1].delay==60,"expirable discovery state schedules one timer at the existing 60 second timeout")

assert(Sync:RunCatchUp(),"repeated login catch-up should merge")
local repeated=0;for _,entry in ipairs(queued)do if entry.id=="Sync.Discover"then repeated=repeated+1 end end
assert(repeated==2,"repeated catch-up must not duplicate an identical domain/scope discovery")

clock=5059;timers[1].callback();assert(#queued==2,"cleanup must not be queued before state expires")
local currentTimer=timers[#timers];assert(currentTimer~=timers[1]and currentTimer.delay==1,"early timer wake only reschedules the remaining expiry")
clock=5060;currentTimer.callback();local cleanup=queued[#queued]
assert(cleanup.id=="Sync.Cleanup"and cleanup.options.triggerSource=="SYNC_STATE_EXPIRY","cleanup is queued only when sync state is actually expirable")
Sync.cleanupTaskId=nil;assert(Sync:Cleanup());assert(next(Sync.requests)==nil and next(Sync.activeRequests)==nil,"expired discovery state is removed")
assert(Sync:GetNextCleanupAt()==nil,"no cleanup remains scheduled after all expirable state is removed")

Sync.heardAt.offer=clock;Sync.heard.offer={};Sync.knownOnline["Player-Remote"]=clock;assert(Sync:ScheduleCleanup())
assert(Sync:GetNextCleanupAt()==5120,"offer state retains the existing 60 second expiry")
clock=5120;assert(Sync:Cleanup());assert(Sync.heardAt.offer==nil and Sync.heard.offer==nil,"expired offer state is removed")
assert(Sync.knownOnline["Player-Remote"]==5060 and Sync:GetNextCleanupAt()==5360,"presence state retains the existing 300 second expiry")
clock=5360;assert(Sync:Cleanup());assert(next(Sync.knownOnline)==nil and Sync:GetNextCleanupAt()==nil,"expired presence state is removed without recurring cleanup")

print("Sync idle cleanup and login discovery tests passed")
