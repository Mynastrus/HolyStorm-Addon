local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={version="1.0.0",schemas={private="guild-private-notes",notes="guild-shared-notes",absences="guild-absences"}}
local function rootDefault()return{schemaVersion=1,guilds={}}end
local function privateDefault()return{schemaVersion=1,accounts={}}end
local function validRoot(value)return type(value)=="table"and value.schemaVersion==1 and type(value.guilds)=="table"end
local function validPrivate(value)return type(value)=="table"and value.schemaVersion==1 and type(value.accounts)=="table"end

HolyStorm.DataManager:RegisterSchema({id=Store.schemas.private,owner="GuildManagementStore",version=1,storage={backend="database",scope="global",path={"guildManagement","privateNotes"}},default=privateDefault,validate=validPrivate,event="HS_GUILD_PRIVATE_NOTES_COMMITTED"})
HolyStorm.DataManager:RegisterSchema({id=Store.schemas.notes,owner="GuildManagementStore",version=1,storage={backend="database",scope="global",path={"guildManagement","sharedNotes"}},default=rootDefault,validate=validRoot,event="HS_GUILD_SHARED_NOTES_COMMITTED"})
HolyStorm.DataManager:RegisterSchema({id=Store.schemas.absences,owner="GuildManagementStore",version=1,storage={backend="database",scope="global",path={"guildManagement","absences"}},default=rootDefault,validate=validRoot,event="HS_GUILD_ABSENCES_COMMITTED"})

local function get(schema,path)local value=HolyStorm.DataManager:Get(schema,path);return value end
local function commit(schema,path,value,context)local result=HolyStorm.DataManager:Commit(schema,path,value,context);return result and result.ok==true,result end
function Store:GetPrivate(noteId,accountUUID)accountUUID=accountUUID or HolyStorm.GuildManagement:GetLocalAccountUUID();if not accountUUID then return nil end;return get(self.schemas.private,{"accounts",accountUUID,"entries",noteId})end
function Store:GetPrivateEntries(accountUUID)accountUUID=accountUUID or HolyStorm.GuildManagement:GetLocalAccountUUID();if not accountUUID then return{}end;return get(self.schemas.private,{"accounts",accountUUID,"entries"})or{}end
function Store:PutPrivate(entry)return commit(self.schemas.private,{"accounts",entry.localAccountUUID,"entries",entry.noteId},entry,{operation="private-note"})end
function Store:GetShared(noteId,guildId)guildId=guildId or HolyStorm.GuildManagement:GetGuildId();if not guildId then return nil end;return get(self.schemas.notes,{"guilds",guildId,"entries",noteId})end
function Store:GetSharedEntries(guildId)guildId=guildId or HolyStorm.GuildManagement:GetGuildId();if not guildId then return{}end;return get(self.schemas.notes,{"guilds",guildId,"entries"})or{}end
function Store:PutShared(entry)return commit(self.schemas.notes,{"guilds",entry.guildId,"entries",entry.noteId},entry,{operation="shared-note"})end
function Store:GetAbsence(absenceId,guildId)guildId=guildId or HolyStorm.GuildManagement:GetGuildId();if not guildId then return nil end;return get(self.schemas.absences,{"guilds",guildId,"entries",absenceId})end
function Store:GetAbsenceEntries(guildId)guildId=guildId or HolyStorm.GuildManagement:GetGuildId();if not guildId then return{}end;return get(self.schemas.absences,{"guilds",guildId,"entries"})or{}end
function Store:PutAbsence(entry)return commit(self.schemas.absences,{"guilds",entry.guildId,"entries",entry.absenceId},entry,{operation="absence"})end
HolyStorm.Data.GuildManagementStore=Store
