local addonVersion="2.3.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Comms={version=addonVersion,prefix="HolyStormSync",protocol="HSC1",chunkSize=220,maxQueue=300,incoming={},serial=0,pendingPackets=0,available=false,fragmentTimeout=30,cleanupTimer=nil,cleanupDue=nil,cleanupTaskId=nil,eventFrame=nil}
local function playerName()return GetUnitName and GetUnitName("player",true)or UnitName and UnitName("player")or"Player"end
local function normalizedName(value)
 if type(value)~="string"or value==""then return nil,nil end
 local full=Ambiguate and Ambiguate(value,"none")or value
 local name,realm=full:match("^([^-]+)%-(.+)$");name=name or full
 local function clean(part)return type(part)=="string"and part:lower():gsub("[%s%-']","")or nil end
 return clean(name),clean(realm)
end
local function audience(channel,target)if target and target~=""then return target end;local labels={GUILD="Guild",RAID="Raid",PARTY="Party",INSTANCE_CHAT="Instance"};return labels[channel]or"Broadcast"end
local function receiver(channel)return channel=="WHISPER"and playerName()or audience(channel)end
local function compact(source)local out={};for _,field in ipairs({"domain","objectId","logicalObject","blockType","block","characterUUID","messageKind","messageClass","version","revision","knownVersion","reason","requestId","correlationId","sender","receiver","target","selectedSource","originalOwner","relay","retry","retryCount","serializedBytes"})do local value=type(source)=="table"and source[field];if type(value)=="string"or type(value)=="number"or type(value)=="boolean"then out[field]=value end end;return out end
function Comms:Initialize()
 if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix then HolyStorm.Logger:WARN("Comms","Addon communication API unavailable");return false end
 if C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)==false then HolyStorm.Logger:WARN("Comms","Addon prefix registration failed");return false end
 local transportReady,transportError=HolyStorm.SyncTransport:Initialize(self)
 if not transportReady then HolyStorm.Logger:WARN("Comms","Queued transport unavailable",{reason=transportError}) end
 HolyStorm.Tasks:RegisterTaskType("Comms.Cleanup",{name="Comms cleanup",module="Comms",priority=100,executionMode="UNIQUE",execute=function()Comms.cleanupTaskId=nil;return Comms:Cleanup()end})
 self.eventFrame=self.eventFrame or CreateFrame("Frame");self.eventFrame:SetScript("OnEvent",function(_,_,prefix,message,channel,sender)if prefix==Comms.prefix then Comms:OnMessage(prefix,message,channel,sender)end end);self.eventFrame:RegisterEvent("CHAT_MSG_ADDON")
 HolyStorm.Events:Register("HS_TASK_CANCELLED","comms-task",function(_,task)if task and task.uniqueId==Comms.cleanupTaskId then Comms.cleanupTaskId=nil;Comms:ScheduleCleanup()end end);self.available=transportReady;return transportReady
end
function Comms:GetNextCleanupAt()
 local due;for _,packet in pairs(self.incoming)do local expiresAt=(tonumber(packet.lastReceivedAt or packet.receivedAt)or 0)+self.fragmentTimeout;if not due or expiresAt<due then due=expiresAt end end;return due
end
function Comms:CancelCleanupTimer()
 if self.cleanupTimer then self.cleanupTimer:Cancel()end;self.cleanupTimer,self.cleanupDue=nil,nil
end
function Comms:ScheduleCleanup()
 local due=self:GetNextCleanupAt();if not due then self:CancelCleanupTimer();if self.cleanupTaskId then HolyStorm.Tasks:Cancel(self.cleanupTaskId,"COMMS_STATE_CLEARED");self.cleanupTaskId=nil end;return false end
 if self.cleanupTaskId then return true end
 if self.cleanupTimer and self.cleanupDue==due then return true end
 self:CancelCleanupTimer();self.cleanupDue=due;self.cleanupTimer=C_Timer.NewTimer(math.max(0,due-HolyStorm.Utils.Now()),function()
  Comms.cleanupTimer,Comms.cleanupDue=nil,nil;local nextDue=Comms:GetNextCleanupAt()
  if nextDue and nextDue<=HolyStorm.Utils.Now()then Comms.cleanupTaskId=HolyStorm.Tasks:Queue("Comms.Cleanup",{priority=100,triggerSource="COMMS_FRAGMENT_EXPIRY"})else Comms:ScheduleCleanup()end
 end);return true
end
function Comms:ResolveChannel(preferred,target)if target and target~=""then return"WHISPER",target end;if preferred=="RAID"and IsInRaid()then return"RAID"end;if preferred=="PARTY"and IsInGroup()and not IsInRaid()then return"PARTY"end;if preferred=="GUILD"and IsInGuild()then return"GUILD"end;if IsInRaid()then return"RAID"elseif IsInGroup()then return"PARTY"elseif IsInGuild()then return"GUILD"end end
function Comms:IsSelfSender(sender)local senderName,senderRealm=normalizedName(sender);local ownName,ownRealm=normalizedName(playerName());if not senderName or senderName~=ownName then return false end;if senderRealm and ownRealm then return senderRealm==ownRealm end;return true end
function Comms:Send(payload,preferred,target,priority,diagnostics)
 if not self.available or type(payload)~="string"or#payload>HolyStorm.Serializer.limits.bytes then return false end;local channel,resolved=self:ResolveChannel(preferred,target);if not channel then return false end;self.serial=self.serial+1;local id=tostring(HolyStorm.Utils.Now()).."-"..self.serial;local total=math.max(1,math.ceil(#payload/self.chunkSize));if self.pendingPackets+total>self.maxQueue then return false end
 id=self.protocol.."-"..id;local base=compact(diagnostics);base.direction="SEND";base.from=playerName();base.to=audience(channel,resolved);base.channel=channel;base.transmissionId=id;base.packetTotal=total;base.correlationId=base.correlationId or id
 for part=1,total do
  local chunk=payload:sub((part-1)*self.chunkSize+1,part*self.chunkSize);local packetDiagnostics=compact(base);for field,value in pairs(base)do packetDiagnostics[field]=value end;packetDiagnostics.packetPart=part;packetDiagnostics.bytes=#chunk
  local message=table.concat({self.protocol,id,part,total,chunk},"|");if #message>255 then HolyStorm.Logger:Write("WARN","Comms","send","Legacy frame exceeds addon message limit",packetDiagnostics,packetDiagnostics.correlationId);return false end
  self.pendingPackets=self.pendingPackets+1;local completed=false
  local function onComplete(_,sent,totalBytes,result,reason)
   if completed then return end;completed=true;Comms.pendingPackets=math.max(0,Comms.pendingPackets-1)
   if result==false or(reason and reason~="suppressed")then HolyStorm.Logger:Write("WARN","Comms","send","Queued addon message failed",{direction="SEND",from=playerName(),to=audience(channel,resolved),channel=channel,transmissionId=id,packetPart=part,packetTotal=total,reason=reason or"SEND_REFUSED",bytes=#message},packetDiagnostics.correlationId)
   elseif reason=="suppressed"then return else HolyStorm.Logger:Write("DEBUG","Comms","send","Packet sent",packetDiagnostics,packetDiagnostics.correlationId)end
  end
  local queued,reason;if channel=="WHISPER"then queued,reason=HolyStorm.SyncTransport:SendWhisper(self.prefix,message,resolved,priority,onComplete,nil,packetDiagnostics)elseif channel=="GUILD"then queued,reason=HolyStorm.SyncTransport:SendGuild(self.prefix,message,priority,onComplete,nil,packetDiagnostics)else queued,reason=HolyStorm.SyncTransport:Send(self.prefix,message,channel,resolved,priority,onComplete,nil,packetDiagnostics)end
  if not queued and not completed then completed=true;self.pendingPackets=math.max(0,self.pendingPackets-1);HolyStorm.Logger:Write("WARN","Comms","send","Addon message was not queued",{direction="SEND",from=playerName(),to=audience(channel,resolved),channel=channel,transmissionId=id,packetPart=part,packetTotal=total,reason=reason or"QUEUE_REJECTED",bytes=#message},packetDiagnostics.correlationId);return false end
 end;return true,id
end
function Comms:OnMessage(prefix,message,channel,sender)
 if prefix~=self.prefix or type(message)~="string"or type(sender)~="string"or self:IsSelfSender(sender)then return end;local protocol,id,part,total,chunk=message:match("^([^|]+)|([^|]+)|(%d+)|(%d+)|(.*)$");part,total=tonumber(part),tonumber(total);if protocol~=self.protocol or not part or not total or total<1 or total>1500 or part<1 or part>total then return end
 local context={direction="RECEIVE",from=sender,to=receiver(channel),channel=channel,transmissionId=id,packetPart=part,packetTotal=total,bytes=#chunk,correlationId=id};HolyStorm.Logger:Write("DEBUG","Comms","receive","Packet received",context,id);local key=sender.."\031"..id;local packet=self.incoming[key];local receivedAt=HolyStorm.Utils.Now();if not packet then packet={parts={},total=total,receivedAt=receivedAt,lastReceivedAt=receivedAt,channel=channel,sender=sender};self.incoming[key]=packet elseif packet.total~=total then self.incoming[key]=nil;self:ScheduleCleanup();return else packet.lastReceivedAt=receivedAt end;packet.parts[part]=chunk;self:ScheduleCleanup();for i=1,total do if packet.parts[i]==nil then return end end;self.incoming[key]=nil;self:ScheduleCleanup();local payload=table.concat(packet.parts);if#payload<=HolyStorm.Serializer.limits.bytes then HolyStorm.Events:Emit("HS_COMMS_MESSAGE",payload,sender,channel,{direction="RECEIVE",from=sender,to=receiver(channel),channel=channel,transmissionId=id,packetTotal=total,bytes=#payload,correlationId=id})end
end
function Comms:Cleanup()local n=HolyStorm.Utils.Now();for key,p in pairs(self.incoming)do if n-(tonumber(p.lastReceivedAt or p.receivedAt)or 0)>=self.fragmentTimeout then local received=0;for _ in pairs(p.parts)do received=received+1 end;HolyStorm.Logger:Write("WARN","Comms","receive","Incomplete transmission expired",{direction="RECEIVE",from=p.sender,to=audience(p.channel),channel=p.channel,transmissionId=key:match("\031(.+)$"),packetPart=received,packetTotal=p.total,reason="TIMEOUT"},key:match("\031(.+)$"));self.incoming[key]=nil end end;self:ScheduleCleanup();return true end
function Comms:GetDiagnostics()local transmissions,fragments=0,0;for _,packet in pairs(self.incoming)do transmissions=transmissions+1;for _ in pairs(packet.parts or{})do fragments=fragments+1 end end;return{incomingTransmissions=transmissions,incomingFragments=fragments,pendingPackets=self.pendingPackets,cleanupScheduled=self.cleanupTimer~=nil or self.cleanupTaskId~=nil,transport=HolyStorm.SyncTransport:GetDiagnostics()}end
function Comms:Shutdown()self.available=false;HolyStorm.SyncTransport.available=false;if self.eventFrame then self.eventFrame:UnregisterEvent("CHAT_MSG_ADDON");self.eventFrame:SetScript("OnEvent",nil)end;self:CancelCleanupTimer();if self.cleanupTaskId then HolyStorm.Tasks:Cancel(self.cleanupTaskId,"COMMS_SHUTDOWN");self.cleanupTaskId=nil end;HolyStorm.Events:UnregisterOwner("comms-task");self.pendingPackets=0;self.incoming={} end
HolyStorm.Comms=Comms
