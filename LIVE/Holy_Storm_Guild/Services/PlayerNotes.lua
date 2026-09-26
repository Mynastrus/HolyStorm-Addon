local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L=LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildRoster")
local GM=HolyStorm.GuildManagement
local Notes={version="1.0.0",maxText=2000,maxCategory=48,visibilities={PUBLIC="guild-notes-view",RAID_LEADERSHIP="guild-notes-view-raid-leadership",OFFICERS="guild-notes-view-officers",LEADERSHIP="guild-notes-view-leadership"},categories={}}
local function now()return HolyStorm.Utils.Now()end
local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function validId(value)return type(value)=="string"and value~=""and#value<=160 end
local function store()return HolyStorm.Data.GuildManagementStore end
local function account(guid)return GM:GetAccountUUID(guid)end
local function actor()return GM:Actor()end
local function trim(value)return HolyStorm.Utils.Trim(tostring(value or""))end

function Notes:RegisterCategory(id,labelKey,order)
 if not validId(id)or type(labelKey)~="string"then return false,"INVALID_CATEGORY"end
 self.categories[id]={id=id,labelKey=labelKey,order=tonumber(order)or 100};return true
end
for index,id in ipairs({"GENERAL","RAID","ORGANIZATION","RECRUITMENT","ATTENTION"})do Notes:RegisterCategory(id,"GUILD_NOTE_CATEGORY_"..id,index)end
function Notes:GetCategories()local out={};for _,value in pairs(self.categories)do out[#out+1]=copy(value)end;table.sort(out,function(a,b)return a.order<b.order or a.order==b.order and a.id<b.id end);return out end
function Notes:GetVisibilityPermission(visibility)return self.visibilities[visibility]end
function Notes:CanView(entry,viewerAccount,viewerCharacter)
 if not entry then return false end;if entry.scope=="PRIVATE"then return(entry.localAccountUUID==GM:GetLocalAccountUUID())end
 local permission=self:GetVisibilityPermission(entry.visibility);return permission and GM:Can(permission,viewerAccount,viewerCharacter,entry)or false
end
function Notes:CanMutate(entry,action,actorAccount,actorCharacter)
 if entry and entry.scope=="PRIVATE"then return entry.localAccountUUID==GM:GetLocalAccountUUID()end
 local own=entry and entry.authorAccountUUID==actorAccount;local permission=action..(own and"-own"or"-any");return GM:Can("guild-notes-"..permission,actorAccount,actorCharacter,entry)
end
function Notes:Validate(entry)
 if type(entry)~="table"or not validId(entry.noteId)or(entry.subjectAccountUUID~=nil and not validId(entry.subjectAccountUUID))or not validId(entry.subjectCharacterUUID)or not validId(entry.authorAccountUUID)or not validId(entry.authorCharacterUUID)then return false,"INVALID_IDENTITY"end
 if entry.scope~="PRIVATE"and entry.scope~="SHARED"then return false,"INVALID_SCOPE"end;if entry.scope=="PRIVATE"and not validId(entry.localAccountUUID)then return false,"INVALID_IDENTITY"end
 if not self.categories[entry.category]then return false,"INVALID_CATEGORY"end
 if entry.scope=="SHARED"and(not self.visibilities[entry.visibility]or not validId(entry.guildId))then return false,"INVALID_VISIBILITY"end
 if type(entry.text)~="string"or#entry.text>self.maxText or(entry.status~="DELETED"and#entry.text==0)then return false,"INVALID_TEXT"end
 if not tonumber(entry.createdAt)or not tonumber(entry.modifiedAt)or tonumber(entry.revision)<1 then return false,"INVALID_REVISION"end
 if entry.expiresAt~=nil and(not tonumber(entry.expiresAt)or entry.expiresAt<=entry.createdAt)then return false,"INVALID_EXPIRATION"end
 return entry.status=="ACTIVE"or entry.status=="DELETED","INVALID_STATUS"
end
function Notes:IsExpired(entry,at)return entry and entry.expiresAt~=nil and tonumber(entry.expiresAt)<=(at or now())end
function Notes:Get(noteId,scope,guildId)if scope=="PRIVATE"then return store():GetPrivate(noteId)elseif scope=="SHARED"then return store():GetShared(noteId,guildId)end end
function Notes:List(options)
 options=options or{};local out={};local function include(entry)
  if entry and(self:CanView(entry,options.viewerAccount,options.viewerCharacter))and(not options.subjectAccountUUID or entry.subjectAccountUUID==options.subjectAccountUUID)and(not options.subjectCharacterUUID or entry.subjectCharacterUUID==options.subjectCharacterUUID)then
   local expired=self:IsExpired(entry);if options.includeDeleted or entry.status~="DELETED"then if options.includeExpired or not expired then local item=copy(entry);item.expired=expired;out[#out+1]=item end end
  end
 end
 if options.includePrivate~=false then for _,entry in pairs(store():GetPrivateEntries())do include(entry)end end
 if options.includeShared~=false then for _,entry in pairs(store():GetSharedEntries(options.guildId))do include(entry)end end
 table.sort(out,function(a,b)return(a.modifiedAt or 0)>(b.modifiedAt or 0)end);return out
end
function Notes:SavePrivate(input,expectedRevision)
 input=type(input)=="table"and input or{};local current=input.noteId and store():GetPrivate(input.noteId);if current and tonumber(expectedRevision)~=tonumber(current.revision)or not current and expectedRevision~=nil and tonumber(expectedRevision)~=0 then return false,"CONFLICT",current and current.revision or 0 end
 local expiresAt;if not input.clearExpiration then expiresAt=input.expiresAt~=nil and tonumber(input.expiresAt)or current and current.expiresAt end;local who=actor();local subjectGuid=input.subjectCharacterUUID or(current and current.subjectCharacterUUID)or who.characterUUID;local subjectAccount=input.subjectAccountUUID or(current and current.subjectAccountUUID)or account(subjectGuid);local stamp=now();local entry={noteId=current and current.noteId or GM:NewId("note"),scope="PRIVATE",localAccountUUID=GM:GetLocalAccountUUID(),subjectAccountUUID=subjectAccount,subjectCharacterUUID=subjectGuid,authorAccountUUID=current and current.authorAccountUUID or who.accountUUID,authorCharacterUUID=current and current.authorCharacterUUID or who.characterUUID,lastEditorAccountUUID=who.accountUUID,lastEditorCharacterUUID=who.characterUUID,category=input.category or(current and current.category)or"GENERAL",text=trim(input.text~=nil and input.text or current and current.text),visibility="PRIVATE",createdAt=current and current.createdAt or stamp,modifiedAt=stamp,expiresAt=expiresAt,revision=(current and current.revision or 0)+1,status="ACTIVE"}
 local valid,reason=self:Validate(entry);if not valid then return false,reason end;local ok,result=store():PutPrivate(entry);if ok then HolyStorm.Events:Emit(current and"HS_GUILD_NOTE_UPDATED"or"HS_GUILD_NOTE_CREATED",entry.noteId,"PRIVATE");self:ScheduleExpiration()end;return ok,ok and entry or result
end
function Notes:SaveShared(input,expectedRevision)
 input=type(input)=="table"and input or{};local guildId=input.guildId or GM:GetGuildId();if not guildId then return false,"NO_GUILD"end;local current=input.noteId and store():GetShared(input.noteId,guildId);if current and tonumber(expectedRevision)~=tonumber(current.revision)or not current and expectedRevision~=nil and tonumber(expectedRevision)~=0 then return false,"CONFLICT",current and current.revision or 0 end
 local who=actor();if not current and not GM:Can("guild-notes-create",who.accountUUID,who.characterUUID,input)then return false,"PERMISSION_DENIED"end;if current and not self:CanMutate(current,"edit",who.accountUUID,who.characterUUID)then return false,"PERMISSION_DENIED"end;if current and input.visibility~=nil and input.visibility~=current.visibility then return false,"IMMUTABLE_VISIBILITY"end
 local expiresAt;if not input.clearExpiration then expiresAt=input.expiresAt~=nil and tonumber(input.expiresAt)or current and current.expiresAt end;local subjectGuid=input.subjectCharacterUUID or(current and current.subjectCharacterUUID);local subjectAccount=input.subjectAccountUUID or(current and current.subjectAccountUUID)or account(subjectGuid);local stamp=now();local entry={noteId=current and current.noteId or GM:NewId("note"),guildId=guildId,scope="SHARED",subjectAccountUUID=subjectAccount,subjectCharacterUUID=subjectGuid,authorAccountUUID=current and current.authorAccountUUID or who.accountUUID,authorCharacterUUID=current and current.authorCharacterUUID or who.characterUUID,lastEditorAccountUUID=who.accountUUID,lastEditorCharacterUUID=who.characterUUID,category=input.category or(current and current.category)or"GENERAL",text=trim(input.text~=nil and input.text or current and current.text),visibility=input.visibility or(current and current.visibility)or"PUBLIC",createdAt=current and current.createdAt or stamp,modifiedAt=stamp,expiresAt=expiresAt,revision=(current and current.revision or 0)+1,status="ACTIVE"}
 local valid,reason=self:Validate(entry);if not valid then return false,reason end;if not self:CanView(entry,who.accountUUID,who.characterUUID)then return false,"VISIBILITY_DENIED"end;local ok,result=store():PutShared(entry);if ok then HolyStorm.Sync:Publish("guildNotes",entry.noteId,current and"NOTE_UPDATED"or"NOTE_CREATED");HolyStorm.Events:Emit(current and"HS_GUILD_NOTE_UPDATED"or"HS_GUILD_NOTE_CREATED",entry.noteId,"SHARED");self:ScheduleExpiration()end;return ok,ok and entry or result
end
function Notes:Delete(noteId,scope,expectedRevision)
 local current=self:Get(noteId,scope);if not current then return false,"NOT_FOUND"end;if tonumber(expectedRevision)~=tonumber(current.revision)then return false,"CONFLICT",current.revision end;local who=actor();if not self:CanMutate(current,"delete",who.accountUUID,who.characterUUID)then return false,"PERMISSION_DENIED"end
 local tombstone=copy(current);tombstone.status="DELETED";tombstone.text="";tombstone.modifiedAt=now();tombstone.lastEditorAccountUUID=who.accountUUID;tombstone.lastEditorCharacterUUID=who.characterUUID;tombstone.revision=current.revision+1
 local ok,result=scope=="PRIVATE"and store():PutPrivate(tombstone)or store():PutShared(tombstone);if ok and scope~="PRIVATE"then HolyStorm.Sync:Publish("guildNotes",noteId,"NOTE_DELETED")end;if ok then HolyStorm.Events:Emit("HS_GUILD_NOTE_DELETED",noteId,scope)end;return ok,ok and tombstone or result
end
function Notes:GetMetadata(id)local entry=store():GetShared(id);return entry and{objectId=id,owner=entry.lastEditorCharacterUUID,origin=entry.authorCharacterUUID,version=entry.revision,updatedAt=entry.modifiedAt,visibility=entry.visibility,guildId=entry.guildId}end
function Notes:ListMetadata(since)local out={};for id,entry in pairs(store():GetSharedEntries())do if(entry.modifiedAt or 0)>since then out[#out+1]=self:GetMetadata(id)end end;return out end
function Notes:GetRecipients(meta)local out={};local guild=HolyStorm.Data.GuildStore:GetCurrent();for guid,member in pairs(guild and guild.roster or{})do if guid~=UnitGUID("player")and member.online and self:CanShare(meta,guid)then out[#out+1]={guid=guid,name=member.name}end end;return out end
function Notes:CanShare(meta,recipientGuid)local permission=meta and self.visibilities[meta.visibility];return recipientGuid~=nil and permission~=nil and GM:GetGuildId()==meta.guildId and GM:Can(permission,account(recipientGuid),recipientGuid,meta)or false end
function Notes:ValidateSync(entry,meta,id)local valid=self:Validate(entry);return valid and entry.scope=="SHARED"and entry.noteId==id and entry.guildId==GM:GetGuildId()and entry.lastEditorCharacterUUID==meta.owner and entry.authorCharacterUUID==meta.origin and tonumber(entry.revision)==tonumber(meta.version)end
function Notes:AuthorizeSync(entry,meta)
 if not self:CanView(entry)then return false end;local editorAccount=account(meta.owner);local own=entry.authorAccountUUID==editorAccount;local action=entry.status=="DELETED"and"delete"or entry.revision==1 and"create"or"edit";local permission=action=="create"and"guild-notes-create"or"guild-notes-"..action..(own and"-own"or"-any");return GM:Can(permission,editorAccount,meta.owner,entry)
end
function Notes:Import(id,entry,meta)local current=store():GetShared(id,entry.guildId);if current and tonumber(current.revision)>=tonumber(meta.version)then return false,"STALE"end;entry=copy(entry);entry.receivedFrom=meta.receivedFrom;local ok,result=store():PutShared(entry);if ok then HolyStorm.Events:Emit("HS_GUILD_NOTE_SYNCED",id,entry.status)end;return ok,result end
function Notes:ScheduleExpiration()
 if not HolyStorm.Tasks then return false end;local earliest;for _,entry in ipairs(self:List({includeExpired=false}))do if entry.expiresAt and(not earliest or entry.expiresAt<earliest)then earliest=entry.expiresAt end end;if not earliest then return false end
 if self.expirationTask then HolyStorm.Tasks:Cancel(self.expirationTask,"RESCHEDULED")end;self.expirationTask=HolyStorm.Tasks:Queue("GuildManagement.NoteExpiration",{delay=math.max(0,earliest-now()),priority=95,triggerSource="NOTE_EXPIRATION"});return self.expirationTask~=nil
end
function Notes:Initialize()
 HolyStorm.Tasks:RegisterTaskType("GuildManagement.NoteExpiration",{name=L["GUILD_TASK_NOTE_EXPIRATION"],localizedNameKey="GUILD_TASK_NOTE_EXPIRATION",module="GuildManagement",priority=95,executionMode="UNIQUE",execute=function()Notes.expirationTask=nil;HolyStorm.Events:Emit("HS_GUILD_NOTE_EXPIRATION");Notes:ScheduleExpiration();return true end})
 HolyStorm.Sync:RegisterDomain("guildNotes",{getMetadata=function(id)return Notes:GetMetadata(id)end,listMetadata=function(since)return Notes:ListMetadata(since)end,export=function(id)return store():GetShared(id)end,validate=function(...)return Notes:ValidateSync(...)end,authorize=function(...)return Notes:AuthorizeSync(...)end,import=function(...)return Notes:Import(...)end,canShare=function(...)return Notes:CanShare(...)end,getRecipients=function(...)return Notes:GetRecipients(...)end,updateEvent="HS_GUILD_NOTE_SYNCED",priority=74})
 self:ScheduleExpiration()
end
GM.Notes=Notes
