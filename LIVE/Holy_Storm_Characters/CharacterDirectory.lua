local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Directory={capabilities={"character.directory","character.describe"}}

function Directory:GetEntries()
 local entries={}
 local guild=HolyStorm.Data.GuildStore:GetCurrent()
 for characterUUID,record in pairs(HolyStorm.Data.CharacterStore:GetAll())do
  local name=record and(record.fullName or record.name)
  if type(name)=="string"and name~=""then
   local member=guild and guild.roster and guild.roster[characterUUID]
   entries[#entries+1]={characterUUID=characterUUID,name=record.name,fullName=record.fullName,realm=record.realm,classFile=record.classFile,guildMember=member~=nil,guildRankIndex=member and member.rankIndex}
  end
 end
 return entries
end

function Directory:Describe(characterUUID)
 local record=HolyStorm.Data.CharacterStore:Get(characterUUID)
 if not record then return nil end
 local guild=HolyStorm.Data.GuildStore:GetCurrent()
 local description={characterUUID=characterUUID,name=record.name,fullName=record.fullName,realm=record.realm,classFile=record.classFile}
 local identity=HolyStorm.TwinkCore:GetRosterIdentity(characterUUID,guild)
 local mainUUID=identity and identity.accountMain
 local mainRecord=mainUUID and mainUUID~=characterUUID and HolyStorm.Data.CharacterStore:Get(mainUUID)
 if mainRecord then description.accountMainName=mainRecord.name or mainRecord.fullName end
 local accountUUID=HolyStorm.TwinkCore:GetAccountUUIDForCharacter(characterUUID)
 if not accountUUID then return description end
 local visible=false
 for _,entry in ipairs(HolyStorm.TwinkCore:GetVisibleCharactersForViewer(accountUUID,guild))do if entry.characterUUID==characterUUID then visible=true;break end end
 if visible then
  local account=HolyStorm.TwinkCore:GetAccount(accountUUID)
  local realName=account and account.metadata and account.metadata.realName
  if type(realName)=="string"and HolyStorm.Utils.Trim(realName)~=""then description.realName=HolyStorm.Utils.Trim(realName)end
 end
 return description
end

function Directory:Initialize(owner)
 owner=owner or"Twinks"
 HolyStorm:RegisterCapability(owner,"character.directory",function()return Directory:GetEntries()end)
 HolyStorm:RegisterCapability(owner,"character.describe",function(_,characterUUID)return Directory:Describe(characterUUID)end)
 self.owner=owner
end

function Directory:Shutdown()
 if not self.owner then return end
 for _,capability in ipairs(self.capabilities)do HolyStorm:UnregisterCapability(self.owner,capability)end
 self.owner=nil
end

HolyStorm.CharacterDirectory=Directory
