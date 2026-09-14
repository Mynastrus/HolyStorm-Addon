local addonVersion="2.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Comms={version=addonVersion,prefix="HolyStormSync",protocol="HSC1",chunkSize=220,maxQueue=300,incoming={},serial=0,pendingPackets=0,available=false}
function Comms:Initialize()
 if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix or not C_ChatInfo.SendAddonMessage then HolyStorm.Logger:WARN("Comms","Addon communication API unavailable");return false end
 if C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)==false then HolyStorm.Logger:WARN("Comms","Addon prefix registration failed");return false end
 -- DE/EN: Network throttling uses MULTI tasks in the central queue, never a private packet queue.
 HolyStorm.Tasks:RegisterTaskType("Comms.SendPacket",{name=L["TASK_COMMS_SEND"],localizedNameKey="TASK_COMMS_SEND",module="Comms",priority=50,executionMode="MULTI",execute=function(task)local p=task.metadata.packet;if p and Comms.available then C_ChatInfo.SendAddonMessage(Comms.prefix,p.message,p.channel,p.target)end;Comms.pendingPackets=math.max(0,Comms.pendingPackets-1);return true end})
 HolyStorm.Events:Register("CHAT_MSG_ADDON","comms",function(_,...)Comms:OnMessage(...)end);HolyStorm.Events:Register("HS_TASK_CANCELLED","comms-task",function(_,task)if task and task.registryId=="Comms.SendPacket"then Comms.pendingPackets=math.max(0,Comms.pendingPackets-1)end end);HolyStorm.Tasks:ScheduleRecurring("comms.cleanup",5,function()Comms:Cleanup()end,{priority=100,cooldown=5,module="Comms"});self.available=true;return true
end
function Comms:ResolveChannel(preferred,target)if target and target~=""then return"WHISPER",target end;if preferred=="RAID"and IsInRaid()then return"RAID"end;if preferred=="PARTY"and IsInGroup()and not IsInRaid()then return"PARTY"end;if preferred=="GUILD"and IsInGuild()then return"GUILD"end;if IsInRaid()then return"RAID"elseif IsInGroup()then return"PARTY"elseif IsInGuild()then return"GUILD"end end
function Comms:Send(payload,preferred,target,priority)
 if not self.available or type(payload)~="string"or#payload>HolyStorm.Serializer.limits.bytes then return false end;local channel,resolved=self:ResolveChannel(preferred,target);if not channel then return false end;self.serial=self.serial+1;local id=tostring(HolyStorm.Utils.Now()).."-"..self.serial;local total=math.max(1,math.ceil(#payload/self.chunkSize));if self.pendingPackets+total>self.maxQueue then return false end
 for part=1,total do local packet={message=table.concat({self.protocol,id,part,total,payload:sub((part-1)*self.chunkSize+1,part*self.chunkSize)},"|"),channel=channel,target=resolved};self.pendingPackets=self.pendingPackets+1;HolyStorm.Tasks:Queue("Comms.SendPacket",{priority=tonumber(priority)or 50,delay=self.pendingPackets*.08,cooldown=.08,triggerSource="SYNC_SEND",metadata={packet=packet}})end;return true
end
function Comms:OnMessage(prefix,message,channel,sender)
 if prefix~=self.prefix or type(message)~="string"or type(sender)~="string"then return end;local protocol,id,part,total,chunk=message:match("^([^|]+)|([^|]+)|(%d+)|(%d+)|(.*)$");part,total=tonumber(part),tonumber(total);if protocol~=self.protocol or not part or not total or total<1 or total>1500 or part<1 or part>total then return end
 local key=sender.."\031"..id;local packet=self.incoming[key];if not packet then packet={parts={},total=total,receivedAt=HolyStorm.Utils.Now(),channel=channel};self.incoming[key]=packet elseif packet.total~=total then self.incoming[key]=nil;return end;packet.parts[part]=chunk;for i=1,total do if packet.parts[i]==nil then return end end;self.incoming[key]=nil;local payload=table.concat(packet.parts);if#payload<=HolyStorm.Serializer.limits.bytes then HolyStorm.Events:Emit("HS_COMMS_MESSAGE",payload,sender,channel)end
end
function Comms:Cleanup()local n=HolyStorm.Utils.Now();for key,p in pairs(self.incoming)do if n-p.receivedAt>30 then self.incoming[key]=nil end end end
function Comms:Shutdown()HolyStorm.Events:Unregister("CHAT_MSG_ADDON","comms");HolyStorm.Tasks:CancelRecurring("comms.cleanup");for _,task in ipairs(HolyStorm.Tasks:GetLiveTasks())do if task.registryId=="Comms.SendPacket"then HolyStorm.Tasks:Cancel(task.uniqueId,"COMMS_SHUTDOWN")end end;HolyStorm.Events:UnregisterOwner("comms-task");self.pendingPackets=0;self.incoming={};self.available=false end
HolyStorm.Comms=Comms
