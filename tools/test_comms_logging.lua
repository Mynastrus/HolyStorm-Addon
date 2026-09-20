local root=(arg[0]:gsub("tools[/\\]test_comms_logging.lua$","")).."LIVE/Holy_Storm/"
local clock=2000
local logs,queued,sent,events,timers={},{},{},{},{}
local eventFrame,recurringCalls
local locale=setmetatable({},{__index=function(_,key)return key end})
local HolyStorm={Utils={Now=function()return clock end},Serializer={limits={bytes=262144}},Logger={},Tasks={definitions={}},Events={listeners={}}}
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
function GetUnitName()return"Alpha-Realm"end;function IsInGuild()return true end;function IsInRaid()return false end;function IsInGroup()return false end
C_ChatInfo={RegisterAddonMessagePrefix=function()return true end,SendAddonMessage=function(prefix,message,channel,target)sent[#sent+1]={prefix=prefix,message=message,channel=channel,target=target}end}
assert(loadfile(root.."Sync/Comms.lua"))();local Comms=HolyStorm.Comms;assert(Comms:Initialize());Comms.chunkSize=3
assert((recurringCalls or 0)==0 and#timers==0,"idle Comms must not schedule recurring or expiry cleanup")
local handled=0;local onMessage=Comms.OnMessage;Comms.OnMessage=function(self,...)handled=handled+1;return onMessage(self,...)end
eventFrame.callback(eventFrame,"CHAT_MSG_ADDON","OtherAddon","ignored","GUILD","Noise-Realm");assert(handled==0 and#logs==0 and#queued==0,"foreign addon traffic must be filtered before Comms processing")
eventFrame.callback(eventFrame,"CHAT_MSG_ADDON",Comms.prefix,"invalid","GUILD","Beta-Realm");assert(handled==1,"Holy Storm addon traffic must reach Comms processing");Comms.OnMessage=onMessage
local ok,transmissionId=Comms:Send("1234567890123456789","WHISPER","Beta-Realm",50,{domain="character",objectId="Player-A\031equipment",messageKind="PAYLOAD",version=14,correlationId="corr-sync"});assert(ok and#queued==7 and transmissionId:find("HSC1%-"),"multipart send queues seven existing Comms.SendPacket tasks")
for _,task in ipairs(queued)do HolyStorm.Tasks.definitions[task.id].execute({metadata=task.options.metadata})end
assert(#sent==7,"all multipart packets are sent");local sendTransmission;for part,entry in ipairs(logs)do local c=entry.context;assert(entry.level=="DEBUG"and entry.source=="Comms"and entry.category=="send"and c.direction=="SEND"and c.from=="Alpha-Realm"and c.to=="Beta-Realm"and c.packetPart==part and c.packetTotal==7 and c.bytes<=3,"SEND packet diagnostics are complete");assert(not c.payload and not c.data and not c.envelope and not c.packet,"SEND context contains no payload");sendTransmission=sendTransmission or c.transmissionId;assert(c.transmissionId==sendTransmission and entry.correlationId=="corr-sync","SEND chunks share transmission and correlation IDs")end
local sendLogCount=#logs
for _,packet in ipairs(sent)do Comms:OnMessage(packet.prefix,packet.message,"WHISPER","Beta-Realm")end
assert(#logs==sendLogCount+7,"every received multipart packet is logged");for index=1,7 do local entry=logs[sendLogCount+index];local c=entry.context;assert(entry.level=="DEBUG"and entry.category=="receive"and c.direction=="RECEIVE"and c.from=="Beta-Realm"and c.to=="Alpha-Realm"and c.packetPart==index and c.packetTotal==7,"RECEIVE packet diagnostics are complete");assert(c.transmissionId==transmissionId and entry.correlationId==transmissionId,"RECEIVE chunks share their transmission correlation");assert(not c.payload and not c.data and not c.message,"RECEIVE context contains no payload")end
local completed;for _,event in ipairs(events)do if event[1]=="HS_COMMS_MESSAGE"then completed=event end end;assert(completed and completed[5].transmissionId==transmissionId and completed[5].packetTotal==7,"reassembled message forwards compact transport diagnostics")
assert(#timers==1 and timers[1].cancelled,"completed transmissions cancel their fragment expiry timer")
Comms:OnMessage(Comms.prefix,"HSC1|HSC1-partial|1|2|abc","GUILD","Beta-Realm");assert(next(Comms.incoming)and#timers==2 and not timers[2].cancelled,"partial transmission schedules one state-based expiry timer")
clock=2030;timers[2].callback();local cleanup=queued[#queued];assert(cleanup.id=="Comms.Cleanup"and cleanup.options.triggerSource=="COMMS_FRAGMENT_EXPIRY","expired fragment state queues cleanup exactly when due")
HolyStorm.Tasks.definitions[cleanup.id].execute();assert(next(Comms.incoming)==nil,"expired fragment state is removed")
print("Comms multipart SEND/RECEIVE logging tests passed")
