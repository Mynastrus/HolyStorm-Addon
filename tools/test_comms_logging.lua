local root=(arg[0]:gsub("tools[/\\]test_comms_logging.lua$","")).."LIVE/Holy_Storm/"
local clock=2000
local logs,queued,sent,events,timers={},{},{},{},{}
local eventFrame,recurringCalls
local locale=setmetatable({},{__index=function(_,key)return key end})
local HolyStorm={Utils={Now=function()return clock end},Serializer={limits={bytes=262144}},Logger={},Tasks={definitions={}},Events={listeners={}}}
HolyStorm.SyncTransport={Initialize=function(self)self.available=true;return true end,GetDiagnostics=function()return{backend="mock"}end,Send=function(self,prefix,message,channel,target,priority,callback,arg,context)queued[#queued+1]={prefix=prefix,message=message,channel=channel,target=target,priority=priority,callback=callback,arg=arg};return true end,SendGuild=function(self,prefix,message,priority,callback,arg,context)return self:Send(prefix,message,"GUILD",nil,priority,callback,arg,context)end,SendWhisper=function(self,prefix,message,target,priority,callback,arg,context)return self:Send(prefix,message,"WHISPER",target,priority,callback,arg,context)end}
function HolyStorm:GetAddon()return self end
function HolyStorm:GetLocale()return locale end
function LibStub(name)if name=="AceLocale-3.0"then return{GetLocale=function()return locale end}end;return HolyStorm end
function HolyStorm.Logger:Write(level,source,category,message,context,correlationId)logs[#logs+1]={level=level,source=source,category=category,message=message,context=context,correlationId=correlationId}end
function HolyStorm.Logger:WARN(source,message)self:Write("WARN",source,"general",message)end
function HolyStorm.Tasks:RegisterTaskType(id,definition)self.definitions[id]=definition end
function HolyStorm.Tasks:Queue(id,options)queued[#queued+1]={id=id,options=options};return"task-"..#queued end
function HolyStorm.Tasks:ScheduleRecurring()recurringCalls=(recurringCalls or 0)+1 end
function HolyStorm.Tasks:Cancel()return true end
function HolyStorm.Tasks:GetLiveTasks()return{}end
function HolyStorm.Tasks:CancelRecurring()end
function HolyStorm.Events:Register(event,_,callback)self.listeners[event]=callback end
function HolyStorm.Events:Emit(event,...)events[#events+1]={event,...};local callback=self.listeners[event];if callback then callback(event,...)end end
function HolyStorm.Events:Unregister()end;function HolyStorm.Events:UnregisterOwner()end
function CreateFrame()local frame={};function frame:SetScript(_,callback)self.callback=callback end;function frame:RegisterEvent(event)self.event=event end;function frame:UnregisterEvent()self.event=nil end;eventFrame=frame;return frame end
C_Timer={NewTimer=function(delay,callback)local timer={delay=delay,callback=callback,cancelled=false};function timer:Cancel()self.cancelled=true end;timers[#timers+1]=timer;return timer end}
function GetUnitName()return"Alpha-Realm"end;function Ambiguate(name,mode)if mode=="none"and not name:find("-",1,true)then return name.."-Realm"elseif mode=="short"then return name:match("^[^-]+")end;return name end;function IsInGuild()return true end;function IsInRaid()return false end;function IsInGroup()return false end
C_ChatInfo={RegisterAddonMessagePrefix=function()return true end,SendAddonMessage=function(prefix,message,channel,target)sent[#sent+1]={prefix=prefix,message=message,channel=channel,target=target}end}
assert(loadfile(root.."Sync/Comms.lua"))();local Comms=HolyStorm.Comms;assert(Comms:Initialize());Comms.chunkSize=3
assert((recurringCalls or 0)==0 and#timers==0,"idle Comms must not schedule recurring or expiry cleanup")
local deserializes=0;HolyStorm.Events:Register("HS_COMMS_MESSAGE","deserialize-probe",function()deserializes=deserializes+1 end)
local selfPacket="HSC1|HSC1-self|1|1|payload"
for _,sender in ipairs({"Alpha","Alpha-Realm"})do local logCount,eventCount,timerCount=#logs,#events,#timers;eventFrame.callback(eventFrame,"CHAT_MSG_ADDON",Comms.prefix,selfPacket,"GUILD",sender);assert(#logs==logCount and#events==eventCount and#timers==timerCount and next(Comms.incoming)==nil and deserializes==0,"self traffic must stop before logging, fragment state, timers, events, and deserialize")end
assert(not Comms:IsSelfSender("Alpha-OtherRealm"),"a qualified same-name character on another realm must not be treated as self")
local handled=0;local onMessage=Comms.OnMessage;Comms.OnMessage=function(self,...)handled=handled+1;return onMessage(self,...)end
eventFrame.callback(eventFrame,"CHAT_MSG_ADDON","OtherAddon","ignored","GUILD","Noise-Realm");assert(handled==0 and#logs==0 and#queued==0,"foreign addon traffic must be filtered before Comms processing")
eventFrame.callback(eventFrame,"CHAT_MSG_ADDON",Comms.prefix,"invalid","GUILD","Beta-Realm");assert(handled==1,"Holy Storm addon traffic must reach Comms processing");Comms.OnMessage=onMessage
local sendLogStart=#logs;local ok,transmissionId=Comms:Send("1234567890123456789","WHISPER","Beta-Realm",50,{domain="character",objectId="Player-A\031equipment",messageKind="PAYLOAD",version=14,correlationId="corr-sync"});assert(ok and#queued==7 and transmissionId:find("HSC1%-"),"multipart send queues seven AceComm transport frames")
for part,packet in ipairs(queued)do assert(packet.prefix=="HolyStormSync"and packet.message==table.concat({"HSC1",transmissionId,part,7,string.sub("1234567890123456789",(part-1)*3+1,part*3)},"|"),"outbound physical frame remains byte-compatible HSC1");sent[#sent+1]={prefix=packet.prefix,message=packet.message,channel=packet.channel,target=packet.target};packet.callback(packet.arg,#packet.message,#packet.message,true,nil)end
assert(#sent==7,"all multipart packets are sent");local sendTransmission;for part=1,7 do local entry=logs[sendLogStart+part];local c=entry.context;assert(entry.level=="DEBUG"and entry.source=="Comms"and entry.category=="send"and c.direction=="SEND"and c.from=="Alpha-Realm"and c.to=="Beta-Realm"and c.packetPart==part and c.packetTotal==7 and c.bytes<=3,"SEND packet diagnostics are complete");assert(not c.payload and not c.data and not c.envelope and not c.packet,"SEND context contains no payload");sendTransmission=sendTransmission or c.transmissionId;assert(c.transmissionId==sendTransmission and entry.correlationId=="corr-sync","SEND chunks share transmission and correlation IDs")end
local sendLogCount=#logs
for _,packet in ipairs(sent)do Comms:OnMessage(packet.prefix,packet.message,"WHISPER","Beta-Realm")end
assert(#logs==sendLogCount+7,"every received multipart packet is logged");for index=1,7 do local entry=logs[sendLogCount+index];local c=entry.context;assert(entry.level=="DEBUG"and entry.category=="receive"and c.direction=="RECEIVE"and c.from=="Beta-Realm"and c.to=="Alpha-Realm"and c.packetPart==index and c.packetTotal==7,"RECEIVE packet diagnostics are complete");assert(c.transmissionId==transmissionId and entry.correlationId==transmissionId,"RECEIVE chunks share their transmission correlation");assert(not c.payload and not c.data and not c.message,"RECEIVE context contains no payload")end
local completed;for _,event in ipairs(events)do if event[1]=="HS_COMMS_MESSAGE"then completed=event end end;assert(completed and completed[5].transmissionId==transmissionId and completed[5].packetTotal==7,"reassembled message forwards compact transport diagnostics")
assert(deserializes==1,"foreign multipart traffic must still reach the deserialize listener exactly once")
assert(#timers==1 and timers[1].cancelled,"completed transmissions cancel their fragment expiry timer")
local secondOk,secondTransmission=Comms:Send("x","WHISPER","Beta-Realm",50,{correlationId="unique-probe"});assert(secondOk and secondTransmission~=transmissionId,"parallel outgoing transfers receive distinct transmission IDs");table.remove(queued);Comms.pendingPackets=Comms.pendingPackets-1
local activeKey="beta-realm\031GUILD\031HSC1-2028-1";local lostKey="beta-realm\031GUILD\031HSC1-2028-2"
Comms:OnMessage(Comms.prefix,"HSC1|HSC1-2028-1|1|3|abc","GUILD","Beta-Realm");Comms:OnMessage(Comms.prefix,"HSC1|HSC1-2028-2|1|2|xyz","GUILD","Beta-Realm");assert(Comms.incoming[activeKey]and Comms.incoming[lostKey]and#timers==2 and not timers[2].cancelled,"parallel incoming transfers remain separated by sender, channel, and transmission ID")
clock=2029;Comms:OnMessage(Comms.prefix,"HSC1|HSC1-2028-1|2|3|def","GUILD","Beta-Realm");assert(Comms.incoming[activeKey].lastUpdatedAt==2029,"active fragment receipt refreshes transfer activity")
clock=2030;timers[2].callback();local cleanup=queued[#queued];assert(cleanup.id=="Comms.Cleanup"and cleanup.options.triggerSource=="COMMS_FRAGMENT_EXPIRY","expired fragment state queues cleanup exactly when due")
HolyStorm.Tasks.definitions[cleanup.id].execute();assert(Comms.incoming[activeKey]and not Comms.incoming[lostKey],"cleanup drops the chunk-lost transfer without deleting another active transfer")
local activeTimer=timers[#timers];assert(activeTimer.delay==29,"active transfer expiry is based on its most recent fragment without increasing the timeout");clock=2059;activeTimer.callback();cleanup=queued[#queued];HolyStorm.Tasks.definitions[cleanup.id].execute();assert(next(Comms.incoming)==nil,"an inactive incomplete transfer eventually expires cleanly")
local sawLost,sawActive=false,false;for _,entry in ipairs(logs)do if entry.message=="Incomplete transmission expired"then if entry.context.transmissionId=="HSC1-2028-2"then sawLost=entry.context.packetPart==1 and entry.context.packetTotal==2 elseif entry.context.transmissionId=="HSC1-2028-1"then sawActive=entry.context.packetPart==2 and entry.context.packetTotal==3 end end end;assert(sawLost and sawActive,"chunk-loss diagnostics retain transmission identity and received/total chunk counts")
print("Comms multipart SEND/RECEIVE logging tests passed")
