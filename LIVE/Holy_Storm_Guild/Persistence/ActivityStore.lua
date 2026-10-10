local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={version="1.0.0",schema="guild-activity"}
local function default()return{schemaVersion=1,guilds={}}end
local function validate(root)return type(root)=="table"and root.schemaVersion==1 and type(root.guilds)=="table"end

HolyStorm.DataManager:RegisterSchema({id=Store.schema,owner="GuildActivityStore",version=1,storage={backend="database",scope="global",path={"guildManagement","activity"}},default=default,validate=validate,event="HS_GUILD_ACTIVITY_COMMITTED"})

local function guildId(value)return value or HolyStorm.GuildManagement:GetGuildId()end
local function get(path)return HolyStorm.DataManager:Get(Store.schema,path)end
function Store:GetShard(accountUUID,guildUUID)local guild=guildId(guildUUID);if not guild or type(accountUUID)~="string"then return nil end;return get({"guilds",guild,"accounts",accountUUID})end
function Store:HasEvent(accountUUID,eventId,guildUUID)local guild=guildId(guildUUID);if not guild or type(accountUUID)~="string"or type(eventId)~="string"then return false end;return HolyStorm.DataManager:Exists(Store.schema,{"guilds",guild,"accounts",accountUUID,"details",eventId})==true end
function Store:GetShards(guildUUID)local guild=guildId(guildUUID);if not guild then return{}end;return get({"guilds",guild,"accounts"})or{}end
function Store:GetAccountIds(guildUUID)local guild=guildId(guildUUID);if not guild then return{}end;local root=HolyStorm.DataManager:GetOwnedRoot(Store.schema,"GuildActivityStore");local accounts=root and root.guilds and root.guilds[guild]and root.guilds[guild].accounts;local ids={};for accountUUID in pairs(type(accounts)=="table"and accounts or{})do if type(accountUUID)=="string"then ids[#ids+1]=accountUUID end end;table.sort(ids);return ids end
function Store:GetSummary(accountUUID,guildUUID)local guild=guildId(guildUUID);if not guild or type(accountUUID)~="string"then return nil end;return get({"guilds",guild,"summaries",accountUUID})end
function Store:GetSummaries(guildUUID)local guild=guildId(guildUUID);if not guild then return{}end;return get({"guilds",guild,"summaries"})or{}end
function Store:PutShard(shard,summary)
 if type(shard)~="table"or type(shard.guildId)~="string"or type(shard.accountUUID)~="string"then return false,"INVALID_SHARD"end
 local persisted,copyResult=HolyStorm.DataManager:SafeCopy(shard);if not persisted then return false,copyResult end
 local persistedSummary;if summary then persistedSummary,copyResult=HolyStorm.DataManager:SafeCopy(summary);if not persistedSummary then return false,copyResult end end
 local root,rootResult=HolyStorm.DataManager:GetOwnedRoot(Store.schema,"GuildActivityStore");if not root then return false,rootResult end
 if root.schemaVersion~=1 or type(root.guilds)~="table"then return false,"INVALID_ACTIVITY_ROOT"end
 local guild=root.guilds[shard.guildId];if guild~=nil and type(guild)~="table"then return false,"INVALID_ACTIVITY_GUILD"end
 guild=guild or{};if guild.accounts~=nil and type(guild.accounts)~="table"then return false,"INVALID_ACTIVITY_ACCOUNTS"end;if guild.summaries~=nil and type(guild.summaries)~="table"then return false,"INVALID_ACTIVITY_SUMMARIES"end
 guild.accounts=guild.accounts or{};guild.summaries=guild.summaries or{};guild.accounts[shard.accountUUID]=persisted;if persistedSummary then guild.summaries[shard.accountUUID]=persistedSummary end;root.guilds[shard.guildId]=guild
 local result={ok=true,changed=true,operation="put-shard",schema=Store.schema,version=1}
 if HolyStorm.Events and type(HolyStorm.Events.Emit)=="function"then pcall(HolyStorm.Events.Emit,HolyStorm.Events,"HS_GUILD_ACTIVITY_COMMITTED",Store.schema,result,{operation="activity-shard-and-summary"})end
 return true,shard
end
HolyStorm.Data.GuildActivityStore=Store
