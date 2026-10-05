local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Twinks")
local TwinkCore={version=addonVersion,visibility={ALL="all",GUILD_ONLY="guild-only"},sources={OWNER="owner-confirmed",ADMIN="administrative"},guildMainCache={}}
local function copy(v)return HolyStorm.Utils.DeepCopy(v)end
local function now()return HolyStorm.Utils.Now()end
local function validId(v)return type(v)=="string"and#v>0 and#v<=128 end
local function log(level,message,context)HolyStorm.Logger:Write(level,"TwinkCore","identity",message,context)end
local function syncObjectId(accountUUID,characterUUID)return accountUUID.."\031"..characterUUID end
local function splitObjectId(value)if type(value)~="string"then return nil end;return value:match("^(.-)\031([^\031]+)$")end
local legacyProfileAliases={realName={"realName","displayName"},birthDate={"birthDate","birthdate"},country={"country"},city={"city","location"},playerType={"playerType"},playDays={"playDays"},playTimes={"playTimes"}}
local function profileVisibility(value)if value=="PRIVATE"or value=="PUBLIC"or value=="GUILD"then return value end;return"GUILD"end
local function accountProfileFields(metadata)
 metadata=type(metadata)=="table"and metadata or{};local fields=copy(metadata.profileFields or{})
 for id,aliases in pairs(legacyProfileAliases)do if type(fields[id])~="table"then for _,key in ipairs(aliases)do if metadata[key]~=nil then fields[id]={value=copy(metadata[key]),visibility="GUILD"};break end end end end
 return fields
end
local function exportProfileMetadata(metadata)
 local result=copy(metadata or{});local source=accountProfileFields(result);local fields={}
 for id,entry in pairs(source)do
  entry=type(entry)=="table"and entry or{value=entry};local visibility=profileVisibility(entry.visibility);local value=entry.value
  if entry.state=="WITHHELD"then fields[id]={visibility=visibility,state="WITHHELD"}
  elseif visibility=="PRIVATE"then fields[id]={visibility=visibility,state=value~=nil and value~=""and"WITHHELD"or"EMPTY"}
  elseif value==nil or value==""then fields[id]={visibility=visibility,state="EMPTY"}
  else fields[id]={visibility=visibility,state="SET",value=copy(value)}end
 end
 result.profileFields=fields
 for _,aliases in pairs(legacyProfileAliases)do for _,key in ipairs(aliases)do result[key]=nil end end
 return result
end

function TwinkCore:CreateAccountUUID()
 local value=string.format("account-%08x-%08x-%08x",now()%0xFFFFFFFF,math.random(0,0x7FFFFFFF),math.random(0,0x7FFFFFFF));log("INFO","Account UUID generated",{accountUUID=value});return value
end
function TwinkCore:GetLocalAccountUUID()return self.localAccountUUID end
function TwinkCore:_GetAccount(accountUUID)return validId(accountUUID)and self.accounts and self.accounts[accountUUID]or nil end
function TwinkCore:GetAccount(accountUUID)local account=self:_GetAccount(accountUUID);return account and copy(account)end
function TwinkCore:GetAccountUUIDForCharacter(characterUUID)return validId(characterUUID)and self.relationships and self.relationships[characterUUID]or nil end
function TwinkCore:GetCharactersForAccount(accountUUID)local account=self:_GetAccount(accountUUID);return account and copy(account.characters)or{}end
function TwinkCore:GetRelationshipSource(characterUUID)local account=self:_GetAccount(self:GetAccountUUIDForCharacter(characterUUID));local entry=account and account.characters[characterUUID];return entry and entry.relationship and entry.relationship.source or nil end
function TwinkCore:IsOwnerConfirmed(characterUUID)return self:GetRelationshipSource(characterUUID)==self.sources.OWNER end
function TwinkCore:NormalizeCharacterName(name,realm)
 if type(name)~="string"or name==""then return nil end;local base,embedded=name:match("^([^%-]+)%-(.+)$");base=base or name;realm=embedded or realm;local full=realm and realm~=""and(base.."-"..realm)or base;return{ name=base,realm=realm,fullName=full,normalizedFullName=string.lower(full:gsub("%s+","")) }
end
function TwinkCore:CompactIdentity(characterUUID,source,guildContext)
 local character=HolyStorm.Data.CharacterStore:Get(characterUUID)or{};local guild=guildContext or HolyStorm.Data.GuildStore:GetCurrentRosterSummary();local member=guild and guild.roster and guild.roster[characterUUID];local rawName=character.name or character.fullName or(member and member.name);local normalized=self:NormalizeCharacterName(rawName,character.realm or(member and member.realm))or{}
 return{characterUUID=characterUUID,name=normalized.name or rawName,realm=normalized.realm or character.realm or(member and member.realm),fullName=normalized.fullName or rawName,normalizedFullName=normalized.normalizedFullName,classFile=character.classFile or(member and(member.classFile or member.classFileName)),level=character.level or(member and member.level),guildId=member and guild.id or character.guild,guildRankIndex=member and member.rankIndex or character.guildRankIndex,relationship={source=source,confirmedAt=source==self.sources.OWNER and now()or nil}}
end
function TwinkCore:EnsureAccount(accountUUID)
 if not validId(accountUUID)then return nil end;local account=self.accounts[accountUUID];if not account then account={accountUUID=accountUUID,characters={},visibility=self.visibility.ALL,ownerVersion=0,version=0,updatedAt=0};self.accounts[accountUUID]=account end
 account.accountUUID=accountUUID;account.characters=type(account.characters)=="table"and account.characters or{};account.visibility=account.visibility==self.visibility.GUILD_ONLY and self.visibility.GUILD_ONLY or self.visibility.ALL;account.ownerVersion=tonumber(account.ownerVersion or account.version)or 0;account.version=account.ownerVersion;return account
end
function TwinkCore:TouchOwner(account,reason)
 if not account or account.accountUUID~=self.localAccountUUID then return false,"NOT_LOCAL_ACCOUNT"end;account.ownerVersion=(account.ownerVersion or 0)+1;account.version=account.ownerVersion;account.updatedAt=now();account.issuedBy=UnitGUID("player");account.relayable=true
 HolyStorm.Events:Emit("HS_ACCOUNT_UPDATED",account.accountUUID,reason);HolyStorm.Events:Emit("HS_TWINKS_UPDATED",account.accountUUID);if HolyStorm.Sync:GetDomain("twinks")then HolyStorm.Sync:Publish("twinks",account.accountUUID,reason or"ACCOUNT_UPDATED")end;return true
end
local identityKeys={"characterUUID"}
local function identityChanged(left,right)
 for _,key in ipairs(identityKeys)do if left[key]~=right[key]then return true end end
 local leftRelationship=left.relationship and left.relationship.source;local rightRelationship=right.relationship and right.relationship.source
 return leftRelationship~=rightRelationship
end
function TwinkCore:ConfirmLocalCharacter(characterUUID)
 if not validId(characterUUID)or characterUUID~=UnitGUID("player")then return false,"NOT_CURRENT_CHARACTER"end;local account=self:EnsureAccount(self.localAccountUUID);local fresh=self:CompactIdentity(characterUUID,self.sources.OWNER);local oldAccountUUID=self.relationships[characterUUID];local oldAccount=oldAccountUUID and self.accounts[oldAccountUUID];local old=account.characters[characterUUID];local changed=not old or oldAccountUUID~=self.localAccountUUID or old.relationship.source~=self.sources.OWNER or identityChanged(old,fresh)
 if oldAccount and oldAccount~=account then local previous=oldAccount.characters[characterUUID];if previous then oldAccount.characters[characterUUID]=nil;if oldAccount.mainCharacterUUID==characterUUID then oldAccount.mainCharacterUUID=nil;oldAccount.mainIsManual=false end;log("INFO","Character relationship conflict resolved by owner proof",{characterUUID=characterUUID,fromAccount=oldAccountUUID,toAccount=account.accountUUID,previousSource=previous.relationship and previous.relationship.source})end end
 fresh.relationship.confirmedAt=changed and now()or old.relationship.confirmedAt;account.characters[characterUUID]=fresh;self.relationships[characterUUID]=account.accountUUID;HolyStorm.PlayerData:SetCharacterOwner(characterUUID,account.accountUUID)
 if changed then self:TouchOwner(account,old and"OWNER_RELATIONSHIP_CONFIRMED"or"CHARACTER_DISCOVERED");HolyStorm.Events:Emit("HS_CHARACTER_RELATIONSHIP_UPDATED",characterUUID,account.accountUUID,self.sources.OWNER);log("INFO",old and"Owner-confirmed relationship received"or"Character discovered for account",{accountUUID=account.accountUUID,characterUUID=characterUUID})else log("DEBUG","Character already known for account",{accountUUID=account.accountUUID,characterUUID=characterUUID})end;return true,changed
end
local function candidateSort(left,right)
 local lr,rr=tonumber(left.rankIndex)or math.huge,tonumber(right.rankIndex)or math.huge;if lr~=rr then return lr<rr end;local ln,rn=left.normalizedFullName or"",right.normalizedFullName or"";if ln~=rn then return ln<rn end;return left.characterUUID<right.characterUUID
end
function TwinkCore:BuildCandidates(account,guild,onlyGuild)
 local out={};for guid,entry in pairs(account and account.characters or{})do local member=guild and guild.roster and guild.roster[guid];if not onlyGuild or member then out[#out+1]={characterUUID=guid,rankIndex=member and member.rankIndex or nil,normalizedFullName=entry.normalizedFullName or string.lower(entry.fullName or guid),entry=entry,member=member}end end;table.sort(out,candidateSort);return out
end
function TwinkCore:GetAccountMain(accountUUID,guildContext,candidates)
 local account=self:_GetAccount(accountUUID);if not account then return nil end;if account.mainIsManual and account.mainCharacterUUID and account.characters[account.mainCharacterUUID]then return account.mainCharacterUUID,"manual"end;if not candidates then candidates=self:BuildCandidates(account,guildContext or HolyStorm.Data.GuildStore:GetCurrentRosterSummary(),false)end;return candidates[1]and candidates[1].characterUUID or nil,"fallback"
end
function TwinkCore:SetAccountMain(characterUUID)
 local account=self:_GetAccount(self.localAccountUUID);local entry=account and account.characters[characterUUID];if not entry or entry.relationship.source~=self.sources.OWNER then return false,"CHARACTER_NOT_OWNER_CONFIRMED",L["TWINK_ERROR_NOT_OWNER_CONFIRMED"]end;if account.mainIsManual and account.mainCharacterUUID==characterUUID then return false,"UNCHANGED"end;account.mainCharacterUUID=characterUUID;account.mainIsManual=true;self:TouchOwner(account,"ACCOUNT_MAIN_CHANGED");HolyStorm.Events:Emit("HS_ACCOUNT_MAIN_CHANGED",account.accountUUID,characterUUID);self:QueueGuildMainRecalculation("ACCOUNT_MAIN_CHANGED");log("INFO","Account main changed",{accountUUID=account.accountUUID,characterUUID=characterUUID});return true
end
function TwinkCore:CalculateGuildMain(accountUUID,guildContext)
 local account=self:_GetAccount(accountUUID);local guild=guildContext or HolyStorm.Data.GuildStore:GetCurrentRosterSummary();if not account or not guild or type(guild.roster)~="table"then return nil,false end;local candidates=self:BuildCandidates(account,guild,false);local accountMain=self:GetAccountMain(accountUUID,guild,candidates);if accountMain and guild.roster[accountMain]then return accountMain,false end;for _,candidate in ipairs(candidates)do if candidate.member then return candidate.characterUUID,true end end;return nil,true
end
function TwinkCore:GetGuildMain(accountUUID,guildContext)local guid,shadow=self:CalculateGuildMain(accountUUID,guildContext);return guid,shadow end
function TwinkCore:GetGuildCharacters(accountUUID,guildContext)
 local account=self:_GetAccount(accountUUID);local guild=guildContext or HolyStorm.Data.GuildStore:GetCurrentRosterSummary();local candidates=self:BuildCandidates(account,guild,true);local main=self:GetGuildMain(accountUUID,guild);table.sort(candidates,function(a,b)if a.characterUUID==main then return true elseif b.characterUUID==main then return false end;return candidateSort(a,b)end);local out={};for _,candidate in ipairs(candidates)do out[#out+1]=candidate.characterUUID end;return out
end
function TwinkCore:GetRosterIdentity(characterUUID,guildContext)
 local accountUUID=self:GetAccountUUIDForCharacter(characterUUID);if not accountUUID then return nil end;local accountMain,mainSource=self:GetAccountMain(accountUUID,guildContext);local guildMain,shadow=self:GetGuildMain(accountUUID,guildContext);return{accountUUID=accountUUID,accountMain=accountMain,guildMain=guildMain,isAccountMain=characterUUID==accountMain,isGuildMain=characterUUID==guildMain,isShadowMain=shadow and characterUUID==guildMain,mainSource=mainSource,relationshipSource=self:GetRelationshipSource(characterUUID)}
end
function TwinkCore:RecalculateGuildMains()
 local guild=HolyStorm.Data.GuildStore:GetCurrentRosterSummary();for accountUUID in pairs(self.accounts)do local main,shadow=self:CalculateGuildMain(accountUUID,guild);local old=self.guildMainCache[accountUUID];local token=tostring(main)..":"..tostring(shadow);if old~=token then self.guildMainCache[accountUUID]=token;HolyStorm.Events:Emit("HS_GUILD_MAIN_CHANGED",accountUUID,main,shadow);log("DEBUG",shadow and"Shadow main determined"or"Guild main recalculated",{accountUUID=accountUUID,characterUUID=main,shadow=shadow})end end;return true
end
function TwinkCore:QueueGuildMainRecalculation(reason)local startup=HolyStorm.Tasks and type(HolyStorm.Tasks.IsStartupActive)=="function" and HolyStorm.Tasks:IsStartupActive();local dependencies={"guild.roster"};if startup then dependencies[#dependencies+1]="Policy.RecalculateEffectiveMemberships"end;return HolyStorm.Tasks:Queue("TwinkCore.RecalculateGuildMains",{debounce=.2,priority=30,startupPhase=3,dependencies=dependencies,triggerSource=reason or"ACCOUNT_UPDATED"})end
function TwinkCore:GetVisibility(accountUUID)local account=self:_GetAccount(accountUUID);return account and account.visibility or self.visibility.ALL end
function TwinkCore:SetVisibility(value)
 if value~=self.visibility.ALL and value~=self.visibility.GUILD_ONLY then return false,"INVALID_VISIBILITY",L["TWINK_ERROR_INVALID_VISIBILITY"]end;local account=self:_GetAccount(self.localAccountUUID);if account.visibility==value then return false,"UNCHANGED"end;account.visibility=value;self:TouchOwner(account,"TWINK_VISIBILITY_CHANGED");HolyStorm.Events:Emit("HS_TWINK_VISIBILITY_CHANGED",account.accountUUID,value);log("INFO","Twink visibility changed",{accountUUID=account.accountUUID,visibility=value});return true
end
function TwinkCore:SetAccountMetadata(metadata)
 local account=self:_GetAccount(self.localAccountUUID);if not account or type(metadata)~="table"then return false,"INVALID_METADATA"end;if HolyStorm.Serializer:Serialize(account.metadata or{})==HolyStorm.Serializer:Serialize(metadata)then return false,"UNCHANGED"end;account.metadata=copy(metadata);self:TouchOwner(account,"ACCOUNT_METADATA_CHANGED");return true
end
function TwinkCore:GetProfileField(accountUUID,fieldId,viewerGuildId,ownerView)
 local account=self:_GetAccount(accountUUID);if not account then return{state="NOT_ENTERED",visibility="GUILD"}end
 local entry=accountProfileFields(account.metadata)[fieldId];if type(entry)~="table"then return{state="NOT_ENTERED",visibility="GUILD"}end
 local visibility=profileVisibility(entry.visibility);local value=entry.value
 if accountUUID==self.localAccountUUID and ownerView~=false then return{state=value~=nil and value~=""and"VISIBLE"or"NOT_ENTERED",visibility=visibility,value=copy(value)}end
 if entry.state=="WITHHELD"or visibility=="PRIVATE"then local state=(entry.state=="WITHHELD"or value~=nil)and"HIDDEN"or"NOT_ENTERED";return{state=state,visibility=visibility}end
 if visibility=="GUILD"then
  local guildId=viewerGuildId or(HolyStorm.Data.GuildStore:GetCurrent()or{}).id;local member=false
  if guildId then for guid,character in pairs(account.characters or{})do if character.guildId==guildId then member=true;break end;local guild=HolyStorm.Data.GuildStore:Get(guildId);if guild and guild.roster and guild.roster[guid]then member=true;break end end end
  if not member then return{state=value~=nil and"HIDDEN"or"NOT_ENTERED",visibility=visibility}end
 end
 return{state=value~=nil and"VISIBLE"or"NOT_ENTERED",visibility=visibility,value=copy(value)}
end
function TwinkCore:GetVisibleCharactersForViewer(accountUUID,guildContext)
 local account=self:_GetAccount(accountUUID);if not account then return{}end;local guild=guildContext or HolyStorm.Data.GuildStore:GetCurrentRosterSummary();local accountMain=self:GetAccountMain(accountUUID,guild);local out={};for guid,entry in pairs(account.characters)do if account.visibility==self.visibility.ALL or guid==accountMain or(guild and guild.roster and guild.roster[guid])then out[#out+1]=copy(entry)end end;table.sort(out,function(a,b)if a.characterUUID==accountMain then return true elseif b.characterUUID==accountMain then return false end;return candidateSort({characterUUID=a.characterUUID,rankIndex=a.guildRankIndex,normalizedFullName=a.normalizedFullName},{characterUUID=b.characterUUID,rankIndex=b.guildRankIndex,normalizedFullName=b.normalizedFullName})end);return out
end
function TwinkCore:CanAdmin(permission,actorGuid)actorGuid=actorGuid or UnitGUID("player");local playerStore=HolyStorm.Data.PlayerStore;local playerId=actorGuid and(playerStore and playerStore.GetCharacterOwner and playerStore:GetCharacterOwner(actorGuid)or actorGuid);local engine=HolyStorm.PermissionEngine or HolyStorm.Policy;return engine:Can(permission,playerId,actorGuid)end
function TwinkCore:AssignCharacterAdministrative(accountUUID,characterUUID,identity,note)
 if not self:CanAdmin("twinks-manage-manual-assignments")then return false,"PERMISSION_DENIED",L["TWINK_ERROR_PERMISSION"]end;if not validId(accountUUID)or not validId(characterUUID)then return false,"INVALID_IDENTITY",L["TWINK_ERROR_INVALID_IDENTITY"]end;local existingAccountUUID=self.relationships[characterUUID];local existingAccount=existingAccountUUID and self.accounts[existingAccountUUID];local existing=existingAccount and existingAccount.characters[characterUUID];if existing and existing.relationship.source==self.sources.OWNER then log("WARN","Administrative assignment rejected for owner-confirmed character",{characterUUID=characterUUID,accountUUID=existingAccountUUID});return false,"OWNER_CONFIRMED",L["TWINK_ERROR_OWNER_CONFIRMED"]end
 local actor=UnitGUID("player");local oldObjectId=existingAccountUUID and syncObjectId(existingAccountUUID,characterUUID);local oldVersion=existingAccountUUID and self:GetAdministrativeVersion(existingAccountUUID,characterUUID)or 0
 if existingAccount and existingAccountUUID~=accountUUID then existingAccount.characters[characterUUID]=nil;if oldObjectId then self.adminTombstones[oldObjectId]={accountUUID=existingAccountUUID,characterUUID=characterUUID,operation="REMOVE",source=self.sources.ADMIN,assignedBy=actor,assignedAt=now(),version=oldVersion+1}end end
 local account=self:EnsureAccount(accountUUID);local previous=account.characters[characterUUID];local version=math.max(tonumber(previous and previous.relationship and previous.relationship.adminVersion)or 0,self:GetAdministrativeVersion(accountUUID,characterUUID))+1;local entry=self:CompactIdentity(characterUUID,self.sources.ADMIN);for key,value in pairs(type(identity)=="table"and identity or{})do if(key=="name"or key=="realm"or key=="fullName"or key=="classFile"or key=="level"or key=="guildId")and(type(value)=="string"or type(value)=="number")then entry[key]=value end end;entry.relationship={source=self.sources.ADMIN,assignedBy=actor,assignedAt=now(),adminVersion=version,note=type(note)=="string"and note or nil};account.characters[characterUUID]=entry;self.relationships[characterUUID]=accountUUID;HolyStorm.PlayerData:SetCharacterOwner(characterUUID,accountUUID);self.adminTombstones[syncObjectId(accountUUID,characterUUID)]=nil
 if oldObjectId then HolyStorm.Sync:Publish("twinkAdmin",oldObjectId,"ADMINISTRATIVE_REASSIGNMENT_REMOVAL")end;HolyStorm.Sync:Publish("twinkAdmin",syncObjectId(accountUUID,characterUUID),"ADMINISTRATIVE_ASSIGNMENT");HolyStorm.Events:Emit("HS_CHARACTER_RELATIONSHIP_UPDATED",characterUUID,accountUUID,self.sources.ADMIN);HolyStorm.Events:Emit("HS_TWINKS_UPDATED",accountUUID);self:QueueGuildMainRecalculation("ADMINISTRATIVE_ASSIGNMENT");log("INFO","Administrative relationship created",{accountUUID=accountUUID,characterUUID=characterUUID,assignedBy=actor,version=version});return true
end
function TwinkCore:GetAdministrativeVersion(accountUUID,characterUUID)local account=self:_GetAccount(accountUUID);local entry=account and account.characters[characterUUID];local relation=entry and entry.relationship;local tombstone=self.adminTombstones[syncObjectId(accountUUID,characterUUID)];return math.max(tonumber(relation and relation.adminVersion)or 0,tonumber(tombstone and tombstone.version)or 0)end
function TwinkCore:RemoveAdministrativeAssignment(accountUUID,characterUUID)
 if not self:CanAdmin("twinks-manage-manual-assignments")then return false,"PERMISSION_DENIED",L["TWINK_ERROR_PERMISSION"]end;local account=self:_GetAccount(accountUUID);local entry=account and account.characters[characterUUID];if not entry then return false,"NOT_FOUND",L["TWINK_ERROR_NOT_FOUND"]end;if entry.relationship.source==self.sources.OWNER then log("WARN","Owner-confirmed relationship removal rejected",{accountUUID=accountUUID,characterUUID=characterUUID});return false,"OWNER_CONFIRMED",L["TWINK_ERROR_OWNER_CONFIRMED"]end;local actor=UnitGUID("player");local version=self:GetAdministrativeVersion(accountUUID,characterUUID)+1;account.characters[characterUUID]=nil;if self.relationships[characterUUID]==accountUUID then self.relationships[characterUUID]=nil;HolyStorm.PlayerData:SetCharacterOwner(characterUUID,nil)end;self.adminTombstones[syncObjectId(accountUUID,characterUUID)]={accountUUID=accountUUID,characterUUID=characterUUID,operation="REMOVE",source=self.sources.ADMIN,assignedBy=actor,assignedAt=now(),version=version};HolyStorm.Sync:Publish("twinkAdmin",syncObjectId(accountUUID,characterUUID),"ADMINISTRATIVE_REMOVAL");HolyStorm.Events:Emit("HS_CHARACTER_RELATIONSHIP_UPDATED",characterUUID,nil,self.sources.ADMIN);HolyStorm.Events:Emit("HS_TWINKS_UPDATED",accountUUID);self:QueueGuildMainRecalculation("ADMINISTRATIVE_REMOVAL");log("INFO","Administrative relationship removed",{accountUUID=accountUUID,characterUUID=characterUUID,assignedBy=actor,version=version});return true
end
function TwinkCore:ValidateOwnerSnapshot(payload)
 if type(payload)~="table"or not validId(payload.accountUUID)or type(payload.characters)~="table"or(payload.visibility~=self.visibility.ALL and payload.visibility~=self.visibility.GUILD_ONLY)then return false end;if payload.mainCharacterUUID and(not validId(payload.mainCharacterUUID)or not payload.characters[payload.mainCharacterUUID])then return false end;local count=0;for guid,entry in pairs(payload.characters)do count=count+1;if count>200 or not validId(guid)or type(entry)~="table"or entry.characterUUID~=guid or type(entry.relationship)~="table"or(entry.relationship.source~=self.sources.OWNER and entry.relationship.source~=self.sources.ADMIN)then return false end;if entry.relationship.source==self.sources.ADMIN and(not validId(entry.relationship.assignedBy)or not tonumber(entry.relationship.assignedAt))then return false end end;return true
end
function TwinkCore:ExportOwnerSnapshot(accountUUID)local account=self:_GetAccount(accountUUID);if not account or account.relayable==false then return nil end;local characters={};for guid,entry in pairs(account.characters)do if entry.relationship and entry.relationship.source==self.sources.OWNER then characters[guid]=copy(entry)end end;local main=account.mainCharacterUUID and characters[account.mainCharacterUUID]and account.mainCharacterUUID or nil;return{accountUUID=account.accountUUID,characters=characters,mainCharacterUUID=main,mainIsManual=account.mainIsManual==true and main~=nil,visibility=account.visibility,metadata=exportProfileMetadata(account.metadata),ownerVersion=account.ownerVersion,updatedAt=account.updatedAt,issuedBy=account.issuedBy}end
function TwinkCore:GetOwnerMetadata(accountUUID)local account=self:_GetAccount(accountUUID);if not account or account.relayable==false or not validId(account.issuedBy)then return nil end;return{objectId=accountUUID,owner=account.issuedBy,version=tonumber(account.ownerVersion)or 0,updatedAt=tonumber(account.updatedAt)or 0,source="twinks-owner"}end
function TwinkCore:MergeOwnerSnapshot(accountUUID,payload,meta)
 if accountUUID==self.localAccountUUID then return false,"LOCAL_OWNER_PROTECTED"end
 local account=self:EnsureAccount(accountUUID)
 for guid,incoming in pairs(payload.characters)do
  local oldAccountUUID=self.relationships[guid];local oldAccount=oldAccountUUID and self.accounts[oldAccountUUID];local old=oldAccount and oldAccount.characters[guid]
  if incoming.relationship.source==self.sources.OWNER then
   local localAutoConflict=old and old.relationship.source==self.sources.OWNER and oldAccountUUID==self.localAccountUUID and oldAccountUUID~=accountUUID
   local newerAuto=not old or old.relationship.source~=self.sources.OWNER or oldAccountUUID==accountUUID
   if old and old.relationship.source==self.sources.OWNER and oldAccountUUID~=accountUUID and not localAutoConflict then
    local incomingAt=tonumber(incoming.relationship.confirmedAt)or 0;local currentAt=tonumber(old.relationship.confirmedAt)or 0
    newerAuto=incomingAt>currentAt or incomingAt==currentAt and accountUUID<oldAccountUUID
   end
   if not localAutoConflict and newerAuto then
    if oldAccount and oldAccount~=account then oldAccount.characters[guid]=nil;log("INFO","Character conflict resolved by synchronized owner proof",{characterUUID=guid,fromAccount=oldAccountUUID,toAccount=accountUUID,previousSource=old and old.relationship and old.relationship.source})end
    account.characters[guid]=copy(incoming);self.relationships[guid]=accountUUID;HolyStorm.PlayerData:SetCharacterOwner(guid,accountUUID);HolyStorm.Events:Emit("HS_CHARACTER_RELATIONSHIP_UPDATED",guid,accountUUID,self.sources.OWNER)
   end
  end
 end
 account.mainCharacterUUID=payload.mainCharacterUUID;account.mainIsManual=payload.mainIsManual==true;account.visibility=payload.visibility;account.metadata=type(payload.metadata)=="table"and copy(payload.metadata)or{};account.ownerVersion=meta.version;account.version=meta.version;account.updatedAt=meta.updatedAt;account.issuedBy=meta.owner;account.relayable=true;HolyStorm.Events:Emit("HS_ACCOUNT_UPDATED",accountUUID,"SYNC");HolyStorm.Events:Emit("HS_TWINKS_UPDATED",accountUUID);HolyStorm.Events:Emit("HS_ACCOUNT_MAIN_CHANGED",accountUUID,self:GetAccountMain(accountUUID));HolyStorm.Events:Emit("HS_TWINK_VISIBILITY_CHANGED",accountUUID,account.visibility);self:QueueGuildMainRecalculation("TWINK_SYNC");log("INFO","Twink account synchronized",{accountUUID=accountUUID,version=meta.version,receivedFrom=meta.receivedFrom});return true
end
function TwinkCore:GetManualAssignmentTargets()
 local out={};for accountUUID,account in pairs(self.accounts or{})do local characters=self:BuildCandidates(account,nil,false);if#characters>0 then local main=self:GetAccountMain(accountUUID,nil,characters);local entry=main and account.characters[main];out[#out+1]={accountUUID=accountUUID,mainCharacterUUID=main,label=entry and(entry.fullName or entry.name)or accountUUID}end end
 table.sort(out,function(a,b)if a.label~=b.label then return a.label<b.label end;return a.accountUUID<b.accountUUID end);return out
end
function TwinkCore:GetAdminPayload(objectId)local accountUUID,guid=splitObjectId(objectId);local tombstone=self.adminTombstones[objectId];if tombstone then return copy(tombstone)end;local account=self:_GetAccount(accountUUID);local entry=account and account.characters[guid];if entry and entry.relationship.source==self.sources.ADMIN then return{accountUUID=accountUUID,characterUUID=guid,operation="ASSIGN",entry=copy(entry),source=self.sources.ADMIN,assignedBy=entry.relationship.assignedBy,assignedAt=entry.relationship.assignedAt,version=entry.relationship.adminVersion}end end
function TwinkCore:GetAdminMetadata(objectId)local payload=self:GetAdminPayload(objectId);return payload and{objectId=objectId,owner=payload.assignedBy,version=tonumber(payload.version)or 0,updatedAt=tonumber(payload.assignedAt)or 0,source="twinks-administrative"}end
function TwinkCore:ValidateAdminPayload(payload,meta,objectId)local accountUUID,guid=splitObjectId(objectId);if type(payload)~="table"or not validId(accountUUID)or not validId(guid)or not validId(payload.assignedBy)or payload.accountUUID~=accountUUID or payload.characterUUID~=guid or payload.source~=self.sources.ADMIN or(payload.operation~="ASSIGN"and payload.operation~="REMOVE")or payload.assignedBy~=meta.owner or not tonumber(payload.assignedAt)or tonumber(payload.version)~=tonumber(meta.version)then return false end;if payload.operation=="ASSIGN"then return type(payload.entry)=="table"and payload.entry.characterUUID==guid and payload.entry.relationship and payload.entry.relationship.source==self.sources.ADMIN end;return true end
function TwinkCore:ApplyAdministrativePayload(objectId,payload)
 local account=self:EnsureAccount(payload.accountUUID);local existingAccountUUID=self.relationships[payload.characterUUID];local existingAccount=existingAccountUUID and self.accounts[existingAccountUUID];local existing=existingAccount and existingAccount.characters[payload.characterUUID];if existing and existing.relationship.source==self.sources.OWNER then return false end
 if payload.operation=="REMOVE"then if existingAccountUUID==payload.accountUUID and existing then account.characters[payload.characterUUID]=nil;self.relationships[payload.characterUUID]=nil;HolyStorm.PlayerData:SetCharacterOwner(payload.characterUUID,nil) end;self.adminTombstones[objectId]=copy(payload)else if existingAccount and existingAccount~=account then existingAccount.characters[payload.characterUUID]=nil end;account.characters[payload.characterUUID]=copy(payload.entry);self.relationships[payload.characterUUID]=payload.accountUUID;HolyStorm.PlayerData:SetCharacterOwner(payload.characterUUID,payload.accountUUID);self.adminTombstones[objectId]=nil end
 HolyStorm.Events:Emit("HS_CHARACTER_RELATIONSHIP_UPDATED",payload.characterUUID,payload.operation=="ASSIGN"and payload.accountUUID or nil,self.sources.ADMIN);HolyStorm.Events:Emit("HS_TWINKS_UPDATED",payload.accountUUID);self:QueueGuildMainRecalculation("ADMINISTRATIVE_SYNC");return true
end
function TwinkCore:RegisterSyncDomains()
 HolyStorm.Sync:RegisterDomain("twinks",{
  getMetadata=function(id)return TwinkCore:GetOwnerMetadata(id)end,
  listMetadata=function(since)local out={};for id in pairs(TwinkCore.accounts)do local meta=TwinkCore:GetOwnerMetadata(id);if meta and(meta.updatedAt or 0)>since then out[#out+1]=meta end end;return out end,
  export=function(id)return TwinkCore:ExportOwnerSnapshot(id)end,
  validate=function(payload,meta,id)return payload.accountUUID==id and tonumber(payload.ownerVersion)==tonumber(meta.version)and payload.issuedBy==meta.owner and TwinkCore:ValidateOwnerSnapshot(payload)end,
  authorize=function(payload,meta)local issuer=payload.characters[meta.owner];return issuer~=nil and issuer.relationship.source==TwinkCore.sources.OWNER end,
  import=function(id,payload,meta)return TwinkCore:MergeOwnerSnapshot(id,payload,meta)end,
  updateEvent="HS_TWINK_SYNC_UPDATED",
 })
 HolyStorm.Sync:RegisterDomain("twinkAdmin",{
  getMetadata=function(id)return TwinkCore:GetAdminMetadata(id)end,
  listMetadata=function(since)
   local out,seen={},{}
   for accountUUID,account in pairs(TwinkCore.accounts)do for guid,entry in pairs(account.characters)do if entry.relationship and entry.relationship.source==TwinkCore.sources.ADMIN then local id=syncObjectId(accountUUID,guid);local meta=TwinkCore:GetAdminMetadata(id);if meta and(meta.updatedAt or 0)>since then out[#out+1]=meta;seen[id]=true end end end end
   for id in pairs(TwinkCore.adminTombstones)do if not seen[id]then local meta=TwinkCore:GetAdminMetadata(id);if meta and(meta.updatedAt or 0)>since then out[#out+1]=meta end end end
   return out
  end,
  export=function(id)return TwinkCore:GetAdminPayload(id)end,
  validate=function(payload,meta,id)return TwinkCore:ValidateAdminPayload(payload,meta,id)end,
  authorize=function(payload,meta)return TwinkCore:CanAdmin("twinks-manage-manual-assignments",meta.owner)end,
  import=function(id,payload)return TwinkCore:ApplyAdministrativePayload(id,payload)end,
  updateEvent="HS_TWINK_ADMIN_SYNC_UPDATED",
 })
end
function TwinkCore:MigrateAccounts()
 local candidates={}
 for accountUUID,account in pairs(self.accounts)do
  if type(accountUUID)~="string"or type(account)~="table"then self.accounts[accountUUID]=nil else
   account=self:EnsureAccount(accountUUID);local migrated={}
   for guid,value in pairs(account.characters)do if validId(guid)then
    local entry
    if type(value)=="table"and value.characterUUID==guid and type(value.relationship)=="table"then entry=value else
     local source=accountUUID==self.localAccountUUID and self.sources.OWNER or account.ownerGuid and self.sources.OWNER or self.sources.ADMIN
     entry=self:CompactIdentity(guid,source);if source==self.sources.ADMIN then entry.relationship={source=source,assignedBy="legacy-migration",assignedAt=tonumber(account.updatedAt)or now(),adminVersion=1}end
    end
    migrated[guid]=entry;local prior=candidates[guid];local rank=entry.relationship.source==self.sources.OWNER and 1 or 2;local priorRank=prior and prior.entry.relationship.source==self.sources.OWNER and 1 or 2
    local freshness=tonumber(entry.relationship.confirmedAt or entry.relationship.assignedAt)or 0;local priorFreshness=prior and(tonumber(prior.entry.relationship.confirmedAt or prior.entry.relationship.assignedAt)or 0)or 0
    if not prior or rank<priorRank or rank==priorRank and(freshness>priorFreshness or freshness==priorFreshness and accountUUID<prior.accountUUID)then candidates[guid]={accountUUID=accountUUID,entry=entry}end
   end end
   account.characters=migrated;account.mainCharacterUUID=account.mainCharacterUUID or account.mainCharacter;account.mainCharacter=nil;account.mainIsManual=account.mainIsManual==true or account.mainCharacterUUID~=nil;account.visibility=account.visibility==self.visibility.GUILD_ONLY and self.visibility.GUILD_ONLY or self.visibility.ALL;account.ownerVersion=tonumber(account.ownerVersion or account.version)or 0;account.version=account.ownerVersion;account.issuedBy=account.issuedBy or account.ownerGuid or account.mainCharacterUUID or next(account.characters);account.relayable=account.relayable~=false
  end
 end
 for guid in pairs(self.relationships)do self.relationships[guid]=nil end;for _,account in pairs(self.accounts)do account.characters={}end
 for guid,candidate in pairs(candidates)do self.accounts[candidate.accountUUID].characters[guid]=candidate.entry;self.relationships[guid]=candidate.accountUUID;HolyStorm.PlayerData:SetCharacterOwner(guid,candidate.accountUUID)end
end
function TwinkCore:Initialize()
 local state=HolyStorm.PlayerData:GetTwinkState();self.accounts,self.relationships,self.adminTombstones=state.accounts,state.relationships,state.tombstones
 local accountUUID=state.localAccountUUID;if not validId(accountUUID)then accountUUID=self:CreateAccountUUID()end;HolyStorm.PlayerData:SetLocalAccountUUID(accountUUID);self.localAccountUUID=accountUUID;self:EnsureAccount(accountUUID);self:MigrateAccounts()
 if HolyStorm.Rules then
  HolyStorm.Rules:RegisterField("twink-core","account.uuid",{type="string",name=L["RULE_FIELD_ACCOUNT_UUID"],nameKey="RULE_FIELD_ACCOUNT_UUID",description=L["RULE_FIELD_ACCOUNT_UUID_DESC"],descriptionKey="RULE_FIELD_ACCOUNT_UUID_DESC",category=L["ACCOUNT_MAIN"],dependencies={"twinks"},resolver=function(context)return context.accountUUID end})
  HolyStorm.Rules:RegisterField("twink-core","account.isMain",{type="boolean",name=L["RULE_FIELD_ACCOUNT_MAIN"],nameKey="RULE_FIELD_ACCOUNT_MAIN",description=L["RULE_FIELD_ACCOUNT_MAIN_DESC"],descriptionKey="RULE_FIELD_ACCOUNT_MAIN_DESC",category=L["ACCOUNT_MAIN"],dependencies={"twinks"},resolver=function(context)local account=context.accountUUID;if not account or not context.characterUUID then return nil,"MISSING_IDENTITY"end;return context.characterUUID==TwinkCore:GetAccountMain(account)end})
  HolyStorm.Rules:RegisterField("twink-core","character.mainTwinkStatus",{type="enum",name=L["RULE_FIELD_MAIN_STATUS"],nameKey="RULE_FIELD_MAIN_STATUS",description=L["RULE_FIELD_MAIN_STATUS_DESC"],descriptionKey="RULE_FIELD_MAIN_STATUS_DESC",category=L["ACCOUNT_MAIN"],dependencies={"twinks"},values={"MAIN","TWINK"},resolver=function(context)local guid=context.characterUUID or context.character and context.character.guid;local account=guid and TwinkCore:GetAccountUUIDForCharacter(guid);local main=account and TwinkCore:GetAccountMain(account);return guid and main and(main==guid and"MAIN"or"TWINK")or nil end})
  HolyStorm.Rules:RegisterAlias("twink-core","mainTwinkStatus","character.mainTwinkStatus")
 end
 HolyStorm.Tasks:RegisterTaskType("TwinkCore.RecalculateGuildMains",{name=L["TASK_TWINK_RECALCULATE_GUILD_MAINS"],localizedNameKey="TASK_TWINK_RECALCULATE_GUILD_MAINS",module="TwinkCore",priority=30,executionMode="UNIQUE",execute=function()return TwinkCore:RecalculateGuildMains()end})
 HolyStorm.Events:Register("HS_ROSTER_UPDATED","twink-core",function()TwinkCore:QueueGuildMainRecalculation("HS_ROSTER_UPDATED")end);HolyStorm.Events:Register("HS_CHARACTER_UPDATED","twink-core-identity",function(_,guid)if guid==UnitGUID("player")then TwinkCore:ConfirmLocalCharacter(guid)end end)
 self:RegisterSyncDomains();local guid=UnitGUID("player");if guid then self:ConfirmLocalCharacter(guid)end;return true
end
HolyStorm.TwinkCore=TwinkCore
HolyStorm.Accounts=TwinkCore
