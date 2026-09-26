local addonVersion="2.3.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Comms={version=addonVersion,prefix="HolyStormSync",protocol="HSC1",chunkSize=220,maxQueue=300,incoming={},incomingCount=0,incomingBySender={},serial=0,pendingPackets=0,available=false,cleanupTimer=nil,cleanupDue=nil,cleanupTaskId=nil,eventFrame=nil}
Comms.receiveLimits={maxFragments=300,maxFragmentBytes=220,maxPayloadBytes=math.min(HolyStorm.Serializer.limits.bytes,300*220),maxIncomplete=64,maxPerSender=16,timeout=30}
Comms.receiveCounters={rejectedFragments=0,oversizedFragments=0,oversizedTransfers=0,excessivePartCount=0,globalCapEvictions=0,senderCapEvictions=0,expiredTransfers=0,malformedFrames=0,duplicateFragments=0,completedTransfers=0,peakIncompleteTransfers=0}
Comms.receiveNoticeAt={}
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
local receiveChannels={GUILD=true,OFFICER=true,RAID=true,PARTY=true,INSTANCE_CHAT=true,WHISPER=true,CHANNEL=true}
local function transferKey(sender,channel,id)return table.concat({sender,channel,id},"\031")end
local function senderIdentity(sender)local name,realm=normalizedName(sender);return realm and(name.."-"..realm)or name end
function Comms:LogReceiveNotice(category,message,context,correlationId)
 local current=HolyStorm.Utils.Now();local previous=self.receiveNoticeAt[category]or-math.huge;if current-previous<5 then return end;self.receiveNoticeAt[category]=current;HolyStorm.Logger:Write("WARN","Comms","receive",message,context,correlationId)
end
function Comms:RejectFragment(category,reason,context)
 local counters=self.receiveCounters;counters.rejectedFragments=counters.rejectedFragments+1;if category then counters[category]=(counters[category]or 0)+1 end
 if category then local detail={reason=reason};for key,value in pairs(context or{})do if type(value)=="string"or type(value)=="number"then detail[key]=value end end;self:LogReceiveNotice(category,"HSC1 fragment rejected",detail,detail.transmissionId)end
 return false
end
function Comms:RemoveIncoming(key)
 local packet=self.incoming[key];if not packet then return nil end;self.incoming[key]=nil;self.incomingCount=math.max(0,self.incomingCount-1);local identity=packet.senderIdentity;local count=math.max(0,(self.incomingBySender[identity]or 0)-1);if count==0 then self.incomingBySender[identity]=nil else self.incomingBySender[identity]=count end;return packet
end
function Comms:OldestIncoming(sender)
 local oldestKey,oldest
 for key,packet in pairs(self.incoming)do if not sender or packet.senderIdentity==sender then if not oldest or packet.createdAt<oldest.createdAt or(packet.createdAt==oldest.createdAt and key<oldestKey)then oldestKey,oldest=key,packet end end end
 return oldestKey,oldest
end
function Comms:EvictIncoming(key,scope)
 local packet=self:RemoveIncoming(key);if not packet then return false end;local counter=scope=="sender"and"senderCapEvictions"or"globalCapEvictions";self.receiveCounters[counter]=self.receiveCounters[counter]+1
 self:LogReceiveNotice(counter,"Oldest incomplete HSC1 transfer evicted",{sender=packet.sender,channel=packet.channel,transmissionId=packet.id,part=packet.receivedParts,total=packet.total,receivedBytes=packet.receivedBytes,reason=scope=="sender"and"SENDER_TRANSFER_CAP"or"GLOBAL_TRANSFER_CAP"},packet.id);return true
end
function Comms:ExpireIncoming(current)
 current=current or HolyStorm.Utils.Now();local expired={}
 for key,packet in pairs(self.incoming)do if current-(tonumber(packet.lastUpdatedAt)or 0)>=self.receiveLimits.timeout then expired[#expired+1]={key=key,packet=packet}end end
 table.sort(expired,function(a,b)if a.packet.lastUpdatedAt==b.packet.lastUpdatedAt then return a.key<b.key end;return a.packet.lastUpdatedAt<b.packet.lastUpdatedAt end)
 for _,item in ipairs(expired)do local packet=self:RemoveIncoming(item.key);if packet then self.receiveCounters.expiredTransfers=self.receiveCounters.expiredTransfers+1;self:LogReceiveNotice("expiredTransfers","Incomplete transmission expired",{direction="RECEIVE",from=packet.sender,to=audience(packet.channel),channel=packet.channel,transmissionId=packet.id,packetPart=packet.receivedParts,packetTotal=packet.total,receivedBytes=packet.receivedBytes,reason="TIMEOUT"},packet.id)end end
 return #expired
end
function Comms:MakeRoomForIncoming(sender)
 if(self.incomingBySender[sender]or 0)>=self.receiveLimits.maxPerSender then local key=self:OldestIncoming(sender);if key then self:EvictIncoming(key,"sender")end end
 if self.incomingCount>=self.receiveLimits.maxIncomplete then local key=self:OldestIncoming();if key then self:EvictIncoming(key,"global")end end
end
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
 local due;for _,packet in pairs(self.incoming)do local expiresAt=(tonumber(packet.lastUpdatedAt)or 0)+self.receiveLimits.timeout;if not due or expiresAt<due then due=expiresAt end end;return due
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
 if prefix~=self.prefix then return false end
 if type(message)~="string"then return self:RejectFragment("malformedFrames","NON_STRING_FRAME",{})end
 if type(sender)~="string"or sender==""or#sender>128 or not normalizedName(sender)then return self:RejectFragment("malformedFrames","INVALID_SENDER",{channel=type(channel)=="string"and#channel<=32 and channel or nil})end
 if self:IsSelfSender(sender)then return false end
 if type(channel)~="string"or#channel>32 or not receiveChannels[channel]then return self:RejectFragment("malformedFrames","INVALID_CHANNEL",{sender=sender,channel=type(channel)=="string"and#channel<=32 and channel or nil})end
 local context={direction="RECEIVE",from=sender,to=receiver(channel),channel=channel}
 if #message>255 then return self:RejectFragment("oversizedFragments","FRAME_TOO_LARGE",context)end
 local protocol,id,partText,totalText,chunk=message:match("^([^|]+)|([^|]+)|(%d+)|(%d+)|(.*)$")
 if protocol~=self.protocol or not id or#id>40 or not id:match("^HSC1%-%d+%-%d+$")or not partText or#partText>3 or not totalText or#totalText>3 then
  context.transmissionId=id;return self:RejectFragment("malformedFrames","INVALID_HSC1_HEADER",context)
 end
 local part,total=tonumber(partText),tonumber(totalText)
 if not part or part%1~=0 or part<1 or not total or total%1~=0 or total<1 then context.transmissionId=id;return self:RejectFragment("malformedFrames","INVALID_FRAGMENT_INDEX",context)end
 context.transmissionId=id;context.packetPart=part;context.packetTotal=total;context.bytes=#chunk
 local identity=senderIdentity(sender);local key=transferKey(identity,channel,id);local existing=self.incoming[key]
 if existing and existing.total~=total then self:RemoveIncoming(key);self:ScheduleCleanup();return self:RejectFragment("malformedFrames","PART_COUNT_CHANGED",context)end
 if total>self.receiveLimits.maxFragments then return self:RejectFragment("excessivePartCount","PART_COUNT_LIMIT",context)end
 if part>total then return self:RejectFragment("malformedFrames","PART_EXCEEDS_TOTAL",context)end
 if #chunk>self.receiveLimits.maxFragmentBytes then return self:RejectFragment("oversizedFragments","FRAGMENT_TOO_LARGE",context)end
 local receivedAt=HolyStorm.Utils.Now();self:ExpireIncoming(receivedAt);local packet=self.incoming[key]
 if packet and packet.total~=total then self:RemoveIncoming(key);self:ScheduleCleanup();return self:RejectFragment("malformedFrames","PART_COUNT_CHANGED",context)end
 local previous=packet and packet.parts[part];local receivedBytes=(packet and packet.receivedBytes or 0)-(previous and#previous or 0)+#chunk
 if receivedBytes>self.receiveLimits.maxPayloadBytes then if packet then self:RemoveIncoming(key);self:ScheduleCleanup()end;context.receivedBytes=receivedBytes;return self:RejectFragment("oversizedTransfers","PAYLOAD_LIMIT",context)end
 if not packet then
  self:MakeRoomForIncoming(identity);packet={id=id,parts={},total=total,receivedParts=0,receivedBytes=0,createdAt=receivedAt,lastUpdatedAt=receivedAt,channel=channel,sender=sender,senderIdentity=identity};self.incoming[key]=packet;self.incomingCount=self.incomingCount+1;self.incomingBySender[identity]=(self.incomingBySender[identity]or 0)+1;self.receiveCounters.peakIncompleteTransfers=math.max(self.receiveCounters.peakIncompleteTransfers or 0,self.incomingCount)
 end
 if previous then self.receiveCounters.duplicateFragments=self.receiveCounters.duplicateFragments+1 else packet.receivedParts=packet.receivedParts+1 end
 packet.parts[part]=chunk;packet.receivedBytes=receivedBytes;packet.lastUpdatedAt=receivedAt
 context.receivedBytes=receivedBytes;HolyStorm.Logger:Write("DEBUG","Comms","receive","Packet received",context,id)
 if packet.receivedParts~=packet.total then self:ScheduleCleanup();return true end
 for index=1,packet.total do if packet.parts[index]==nil then self:ScheduleCleanup();return true end end
 self:RemoveIncoming(key);local completePayload=table.concat(packet.parts);self:ScheduleCleanup()
 if #completePayload>self.receiveLimits.maxPayloadBytes or#completePayload>HolyStorm.Serializer.limits.bytes then context.receivedBytes=#completePayload;return self:RejectFragment("oversizedTransfers","ASSEMBLED_PAYLOAD_LIMIT",context)end
 self.receiveCounters.completedTransfers=self.receiveCounters.completedTransfers+1;HolyStorm.Events:Emit("HS_COMMS_MESSAGE",completePayload,sender,channel,{direction="RECEIVE",from=sender,to=receiver(channel),channel=channel,transmissionId=id,packetTotal=total,bytes=#completePayload,correlationId=id});return true
end
function Comms:Cleanup()self:ExpireIncoming(HolyStorm.Utils.Now());self:ScheduleCleanup();return true end
function Comms:GetDiagnostics()local fragments=0;for _,packet in pairs(self.incoming)do fragments=fragments+(packet.receivedParts or 0)end;local result={incomingTransmissions=self.incomingCount,incomingFragments=fragments,activeIncompleteTransfers=self.incomingCount,pendingPackets=self.pendingPackets,cleanupScheduled=self.cleanupTimer~=nil or self.cleanupTaskId~=nil,receiveLimits=self.receiveLimits,transport=HolyStorm.SyncTransport:GetDiagnostics()};for name,value in pairs(self.receiveCounters)do result[name]=value end;return result end
function Comms:Shutdown()self.available=false;HolyStorm.SyncTransport.available=false;if self.eventFrame then self.eventFrame:UnregisterEvent("CHAT_MSG_ADDON");self.eventFrame:SetScript("OnEvent",nil)end;self:CancelCleanupTimer();if self.cleanupTaskId then HolyStorm.Tasks:Cancel(self.cleanupTaskId,"COMMS_SHUTDOWN");self.cleanupTaskId=nil end;HolyStorm.Events:UnregisterOwner("comms-task");self.pendingPackets=0;self.incoming={};self.incomingCount=0;self.incomingBySender={} end
HolyStorm.Comms=Comms
