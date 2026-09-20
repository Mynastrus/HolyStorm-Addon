local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Notifications={version="1.0.0",types={},history={},maxHistory=50,sequence=0}
function Notifications:RegisterType(id,definition)if type(id)~="string"or type(definition)~="table"or type(definition.title)~="function"then return false,"INVALID_NOTIFICATION_TYPE"end;self.types[id]=definition;return true end
function Notifications:Push(typeId,payload)
 local definition=self.types[typeId];if not definition then return false,"UNKNOWN_NOTIFICATION_TYPE"end;self.sequence=self.sequence+1;local entry={id=string.format("notification-%08x-%04x",HolyStorm.Utils.Now()%0xffffffff,self.sequence%0xffff),type=typeId,payload=HolyStorm.Utils.DeepCopy(payload),createdAt=HolyStorm.Utils.Now()};self.history[#self.history+1]=entry;while#self.history>self.maxHistory do table.remove(self.history,1)end;self.current=entry;if definition.sound then definition.sound(payload)end;HolyStorm.Events:Emit("HS_NOTIFICATION_PUSHED",typeId,entry);return true,entry
end
function Notifications:GetType(id)return self.types[id]end
function Notifications:GetHistory()return HolyStorm.Utils.DeepCopy(self.history)end
function Notifications:Initialize()return true end
HolyStorm.Notifications=Notifications
