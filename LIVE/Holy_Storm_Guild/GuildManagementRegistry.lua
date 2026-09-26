local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local GuildManagement={version="1.0.0",features={},featureOrder={},sequence=0}

local function validId(value)return type(value)=="string"and value~=""and#value<=96 and value:match("^[%w_%.%-:]+$")~=nil end
function GuildManagement:RegisterFeature(definition)
 if type(definition)~="table"or not validId(definition.id)or type(definition.build)~="function"then return false,"INVALID_FEATURE"end
 if self.features[definition.id]then return false,"FEATURE_EXISTS"end
 definition.owner=definition.owner or"GuildManagement";definition.order=tonumber(definition.order)or 100;self.features[definition.id]=definition;self.featureOrder[#self.featureOrder+1]=definition.id
 table.sort(self.featureOrder,function(left,right)local a,b=self.features[left],self.features[right];return a.order<b.order or a.order==b.order and left<right end)
 if HolyStorm.Events then HolyStorm.Events:Emit("HS_GUILD_MANAGEMENT_FEATURE_REGISTERED",definition.id)end;return true
end
function GuildManagement:UnregisterFeature(id)if not self.features[id]then return false end;self.features[id]=nil;for index,value in ipairs(self.featureOrder)do if value==id then table.remove(self.featureOrder,index);break end end;return true end
function GuildManagement:GetFeatures()
 local out={};for _,id in ipairs(self.featureOrder)do out[#out+1]=self.features[id]end;return out
end
function GuildManagement:GetFeature(id)return self.features[id]end
function GuildManagement:GetGuildId()local guild=HolyStorm.Data.GuildStore:GetCurrent();return guild and guild.id end
function GuildManagement:GetLocalAccountUUID()return HolyStorm.Accounts and HolyStorm.Accounts:GetLocalAccountUUID()or HolyStorm.Data.PlayerStore:GetLocalPlayerId()end
function GuildManagement:GetAccountUUID(characterUUID)return characterUUID and((HolyStorm.Accounts and HolyStorm.Accounts:GetAccountUUIDForCharacter(characterUUID))or HolyStorm.Data.PlayerStore:GetCharacterOwner(characterUUID))end
function GuildManagement:Actor()local guid=UnitGUID("player");return{accountUUID=self:GetLocalAccountUUID(),characterUUID=guid}end
function GuildManagement:Can(permission,accountUUID,characterUUID,target)return(HolyStorm.PermissionEngine or HolyStorm.Policy):Can(permission,accountUUID,characterUUID,target)end
function GuildManagement:NewId(prefix)
 self.sequence=self.sequence+1;return string.format("%s-%08x-%04x-%04x",prefix,HolyStorm.Utils.Now()%0xffffffff,self.sequence%0xffff,math.random(0,0xffff))
end
function GuildManagement:Open(featureId,characterUUID,mode)
 local shown=HolyStorm.UI and HolyStorm.UI:ShowView("guildManagement")or false;HolyStorm.Events:Emit("HS_GUILD_MANAGEMENT_OPEN_REQUESTED",featureId,characterUUID,mode);return shown
end

HolyStorm.GuildManagement=GuildManagement
