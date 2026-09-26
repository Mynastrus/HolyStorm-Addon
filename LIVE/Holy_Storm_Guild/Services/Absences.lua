local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local GM=HolyStorm.GuildManagement
local Absences={version="1.0.0",maxTitle=120,maxReason=800}
local function now()return HolyStorm.Utils.Now()end
local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function validId(value)return type(value)=="string"and value~=""and#value<=160 end
local function store()return HolyStorm.Data.GuildManagementStore end
local function account(guid)return GM:GetAccountUUID(guid)end
local function actor()return GM:Actor()end
local function trim(value)return HolyStorm.Utils.Trim(tostring(value or""))end

function Absences:Classify(entry,at)
 at=at or now();if not entry or entry.status=="DELETED"then return"CANCELLED"end;if entry.endAt<at then return"PAST"elseif entry.startAt>at then return"UPCOMING"end;return"ACTIVE"
end
function Absences:Validate(entry)
 if type(entry)~="table"or not validId(entry.absenceId)or not validId(entry.guildId)or not validId(entry.ownerAccountUUID)or not validId(entry.ownerCharacterUUID)or not validId(entry.originCharacterUUID)or not validId(entry.modifiedByCharacterUUID)then return false,"INVALID_IDENTITY"end
 if not tonumber(entry.startAt)or not tonumber(entry.endAt)then return false,"MISSING_DATES"end;if entry.endAt<entry.startAt then return false,"END_BEFORE_START"end
 if type(entry.title)~="string"or#entry.title>self.maxTitle or type(entry.reason)~="string"or#entry.reason>self.maxReason then return false,"TEXT_TOO_LONG"end
 if not tonumber(entry.createdAt)or not tonumber(entry.modifiedAt)or tonumber(entry.revision)<1 then return false,"INVALID_REVISION"end
 return entry.status=="ACTIVE"or entry.status=="DELETED","INVALID_STATUS"
end
function Absences:CanView(viewerAccount,viewerCharacter,target)return GM:Can("guild-absences-view",viewerAccount,viewerCharacter,target)end
function Absences:CanMutate(entry,actorAccount,actorCharacter)
 local own=entry.ownerAccountUUID==actorAccount;return GM:Can(own and"guild-absences-manage-own"or"guild-absences-manage-any",actorAccount,actorCharacter,entry)
end
function Absences:Get(id,guildId)return store():GetAbsence(id,guildId)end
function Absences:List(options)
 options=options or{};if not self:CanView(options.viewerAccount,options.viewerCharacter)then return{}end;local out={};for _,entry in pairs(store():GetAbsenceEntries(options.guildId))do local state=self:Classify(entry,options.at);local stateMatches=not options.state or state==options.state or options.state=="PAST"and state=="CANCELLED";if(options.includeDeleted or entry.status~="DELETED")and stateMatches and(not options.ownerAccountUUID or entry.ownerAccountUUID==options.ownerAccountUUID)then local item=copy(entry);item.state=state;out[#out+1]=item end end
 table.sort(out,function(a,b)if a.startAt~=b.startAt then return a.startAt<b.startAt end;return a.absenceId<b.absenceId end);return out
end
function Absences:GetForAccount(accountUUID,at)
 local active,upcoming,past;for _,entry in ipairs(self:List({ownerAccountUUID=accountUUID,at=at}))do if entry.state=="ACTIVE"then active=active or entry elseif entry.state=="UPCOMING"then upcoming=upcoming or entry else past=entry end end;return active,upcoming,past
end
function Absences:Save(input,expectedRevision)
 input=type(input)=="table"and input or{};local guildId=input.guildId or GM:GetGuildId();if not guildId then return false,"NO_GUILD"end;local current=input.absenceId and self:Get(input.absenceId,guildId);if current and tonumber(expectedRevision)~=tonumber(current.revision)or not current and expectedRevision~=nil and tonumber(expectedRevision)~=0 then return false,"CONFLICT",current and current.revision or 0 end
 local who=actor();local ownerGuid=input.ownerCharacterUUID or(current and current.ownerCharacterUUID)or who.characterUUID;local ownerAccount=input.ownerAccountUUID or(current and current.ownerAccountUUID)or account(ownerGuid);local candidate=current or{ownerAccountUUID=ownerAccount};if not self:CanMutate(candidate,who.accountUUID,who.characterUUID)then return false,"PERMISSION_DENIED"end
 if current and(ownerAccount~=current.ownerAccountUUID or ownerGuid~=current.ownerCharacterUUID)then return false,"IMMUTABLE_OWNER"end;local stamp=now();local entry={absenceId=current and current.absenceId or GM:NewId("absence"),guildId=guildId,ownerAccountUUID=ownerAccount,ownerCharacterUUID=ownerGuid,originCharacterUUID=current and current.originCharacterUUID or who.characterUUID,createdByCharacterUUID=current and current.createdByCharacterUUID or who.characterUUID,modifiedByCharacterUUID=who.characterUUID,startAt=tonumber(input.startAt~=nil and input.startAt or current and current.startAt),endAt=tonumber(input.endAt~=nil and input.endAt or current and current.endAt),title=trim(input.title~=nil and input.title or current and current.title),reason=trim(input.reason~=nil and input.reason or current and current.reason),createdAt=current and current.createdAt or stamp,modifiedAt=stamp,revision=(current and current.revision or 0)+1,status="ACTIVE"}
 local valid,reason=self:Validate(entry);if not valid then return false,reason end;local ok,result=store():PutAbsence(entry);if ok then HolyStorm.Sync:Publish("guildAbsences",entry.absenceId,current and"ABSENCE_UPDATED"or"ABSENCE_CREATED");HolyStorm.Events:Emit(current and"HS_GUILD_ABSENCE_UPDATED"or"HS_GUILD_ABSENCE_CREATED",entry.absenceId)end;return ok,ok and entry or result
end
function Absences:Delete(id,expectedRevision)
 local current=self:Get(id);if not current then return false,"NOT_FOUND"end;if tonumber(expectedRevision)~=tonumber(current.revision)then return false,"CONFLICT",current.revision end;local who=actor();if not self:CanMutate(current,who.accountUUID,who.characterUUID)then return false,"PERMISSION_DENIED"end
 local tombstone=copy(current);tombstone.status="DELETED";tombstone.modifiedAt=now();tombstone.modifiedByCharacterUUID=who.characterUUID;tombstone.revision=current.revision+1;local ok,result=store():PutAbsence(tombstone);if ok then HolyStorm.Sync:Publish("guildAbsences",id,"ABSENCE_DELETED");HolyStorm.Events:Emit("HS_GUILD_ABSENCE_DELETED",id)end;return ok,ok and tombstone or result
end
function Absences:GetMetadata(id)local entry=self:Get(id);return entry and{objectId=id,owner=entry.modifiedByCharacterUUID,origin=entry.originCharacterUUID,originAccountUUID=entry.ownerAccountUUID,version=entry.revision,updatedAt=entry.modifiedAt,guildId=entry.guildId}end
function Absences:ListMetadata(since)local out={};for id,entry in pairs(store():GetAbsenceEntries())do if(entry.modifiedAt or 0)>since then out[#out+1]=self:GetMetadata(id)end end;return out end
function Absences:ValidateSync(entry,meta,id)local valid=self:Validate(entry);return valid and entry.absenceId==id and entry.guildId==GM:GetGuildId()and entry.modifiedByCharacterUUID==meta.owner and entry.originCharacterUUID==meta.origin and entry.ownerAccountUUID==meta.originAccountUUID and tonumber(entry.revision)==tonumber(meta.version)end
function Absences:AuthorizeSync(entry,meta)
 if not self:CanView()then return false end;local editorAccount=account(meta.owner);local own=entry.ownerAccountUUID==editorAccount;return GM:Can(own and"guild-absences-manage-own"or"guild-absences-manage-any",editorAccount,meta.owner,entry)
end
function Absences:Import(id,entry,meta)local current=self:Get(id,entry.guildId);if current and tonumber(current.revision)>=tonumber(meta.version)then return false,"STALE"end;entry=copy(entry);entry.receivedFrom=meta.receivedFrom;local ok,result=store():PutAbsence(entry);if ok then HolyStorm.Events:Emit("HS_GUILD_ABSENCE_SYNCED",id,entry.status)end;return ok,result end
function Absences:Initialize()
 HolyStorm.Sync:RegisterDomain("guildAbsences",{getMetadata=function(id)return Absences:GetMetadata(id)end,listMetadata=function(since)return Absences:ListMetadata(since)end,export=function(id)return Absences:Get(id)end,validate=function(...)return Absences:ValidateSync(...)end,authorize=function(...)return Absences:AuthorizeSync(...)end,import=function(...)return Absences:Import(...)end,updateEvent="HS_GUILD_ABSENCE_SYNCED",priority=76})
end
GM.Absences=Absences
