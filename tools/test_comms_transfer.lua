local root=(arg[0]:gsub("tools[/\\]test_comms_transfer.lua$","")).."LIVE/Holy_Storm/"
local now=100
local HolyStorm={Serializer={limits={bytes=66000}},Events={emitted={}},Logger={history={}},Tasks={},Utils={}}
function HolyStorm:GetAddon()return self end
function HolyStorm.Utils.Now()return now end
function HolyStorm.Events:Emit(event,...)self.emitted[#self.emitted+1]={event=event,args={...}}end
function HolyStorm.Logger:Write(level,source,category,message,context)self.history[#self.history+1]={level=level,source=source,category=category,message=message,context=context}end
function UnitName()return"Local"end
function GetUnitName()return"Local-Realm"end
function Ambiguate(value)return value end
function IsInGuild()return true end
function IsInRaid()return false end
function IsInGroup()return false end
local timers={}
C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}
LibStub=function(name)if name=="AceLocale-3.0"then return{GetLocale=function()return setmetatable({},{__index=function(_,key)return key end})end}end;return HolyStorm end
local queued={}
HolyStorm.SyncTransport={
 SendGuild=function(_,prefix,message,priority,callback,arg,context)queued[#queued+1]={callback=callback,arg=arg,message=message,context=context};return true end,
 SendWhisper=function(_,prefix,message,target,priority,callback,arg,context)queued[#queued+1]={callback=callback,arg=arg,message=message,context=context};return true end,
 Send=function(_,prefix,message,channel,target,priority,callback,arg,context)queued[#queued+1]={callback=callback,arg=arg,message=message,context=context};return true end,
 GetDiagnostics=function()return{}end,
}
assert(loadfile(root.."Sync/Comms.lua"))()
local Comms=HolyStorm.Comms;Comms.available=true

local progress,completed={},{}
local payload=string.rep("p",500)
local accepted,id=Comms:Send(payload,"GUILD",nil,90,{domain="character",objectId="Character-1\031equipment",requestId="aggregate-test"},function(ok,transmissionId,bytes,reason)completed[#completed+1]={ok=ok,id=transmissionId,bytes=bytes,reason=reason}end,function(sent,total)progress[#progress+1]={sent=sent,total=total}end)
assert(accepted and id and#queued==3 and Comms.pendingPackets==3,"a logical message queues one bounded HSC1 frame per chunk")
assert(#completed==0,"logical completion waits for all transport callbacks")
for index,entry in ipairs(queued)do entry.callback(entry.arg,1,1,true,nil)end
assert(#completed==1 and completed[1].ok and completed[1].bytes==#payload,"the aggregate callback fires once after all frames complete")
assert(#progress==3 and progress[3].sent==3 and progress[3].total==3 and Comms.pendingPackets==0,"fragment progress and pending-frame accounting are aggregated")

local assembledCount,fragmentProgress=0,0
for _,entry in ipairs(HolyStorm.Events.emitted)do if entry.event=="HS_COMMS_MESSAGE"then assembledCount=assembledCount+1 elseif entry.event=="HS_COMMS_FRAGMENT_PROGRESS"then fragmentProgress=fragmentProgress+1 end end
local wire=string.rep("x",400);local chunks={wire:sub(1,220),wire:sub(221)}
assert(Comms:OnMessage(Comms.prefix,"HSC1|HSC1-100-1|1|2|"..chunks[1],"GUILD","Remote-Realm"))
local before=assembledCount;for _,entry in ipairs(HolyStorm.Events.emitted)do if entry.event=="HS_COMMS_MESSAGE"then before=before-1 end end
assert(before==0,"an incomplete fragment set emits no complete message")
assert(Comms:OnMessage(Comms.prefix,"HSC1|HSC1-100-1|2|2|"..chunks[2],"GUILD","Remote-Realm"))
local messages=0;fragmentProgress=0;for _,entry in ipairs(HolyStorm.Events.emitted)do if entry.event=="HS_COMMS_MESSAGE"then messages=messages+1;assert(entry.args[1]==wire,"reassembly preserves the exact serialized payload")elseif entry.event=="HS_COMMS_FRAGMENT_PROGRESS"then fragmentProgress=fragmentProgress+1 end end
assert(messages==1 and fragmentProgress>=2,"one complete message and live fragment progress are emitted after reassembly (messages="..messages..", progress="..fragmentProgress..")")
local tooLarge=string.rep("z",220*Comms.receiveLimits.maxFragments+1)
assert(not Comms:Send(tooLarge,"GUILD",nil,90,{}),"outgoing transfers beyond the HSC1 fragment ceiling are refused")
print("Comms aggregate fragment completion, progress, reassembly and hard limits tests passed")
