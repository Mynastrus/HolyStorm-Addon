local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={version="1.0.0",schema="guild-activity"}
local function default()return{schemaVersion=1,guilds={}}end
local function validate(root)return type(root)=="table"and root.schemaVersion==1 and type(root.guilds)=="table"end

HolyStorm.DataManager:RegisterSchema({id=Store.schema,owner="GuildActivityStore",version=1,storage={backend="database",scope="global",path={"guildManagement","activity"}},default=default,validate=validate,event="HS_GUILD_ACTIVITY_COMMITTED"})

local function guildId(value)return value or HolyStorm.GuildManagement:GetGuildId()end
local function get(path)return HolyStorm.DataManager:Get(Store.schema,path)end
function Store:GetShard(accountUUID,guildUUID)local guild=guildId(guildUUID);if not guild or type(accountUUID)~="string"then return nil end;return get({"guilds",guild,"accounts",accountUUID})end
function Store:GetShards(guildUUID)local guild=guildId(guildUUID);if not guild then return{}end;return get({"guilds",guild,"accounts"})or{}end
function Store:GetSummary(accountUUID,guildUUID)local guild=guildId(guildUUID);if not guild or type(accountUUID)~="string"then return nil end;return get({"guilds",guild,"summaries",accountUUID})end
function Store:GetSummaries(guildUUID)local guild=guildId(guildUUID);if not guild then return{}end;return get({"guilds",guild,"summaries"})or{}end
function Store:PutShard(shard,summary)
 if type(shard)~="table"or type(shard.guildId)~="string"or type(shard.accountUUID)~="string"then return false,"INVALID_SHARD"end
 local result=HolyStorm.DataManager:Transaction(Store.schema,{"guilds",shard.guildId},function(guild)guild=type(guild)=="table"and guild or{};guild.accounts=type(guild.accounts)=="table"and guild.accounts or{};guild.summaries=type(guild.summaries)=="table"and guild.summaries or{};guild.accounts[shard.accountUUID]=shard;if summary then guild.summaries[shard.accountUUID]=summary end;return guild end,{operation="activity-shard-and-summary"});return result and result.ok==true,result and shard or result
end
HolyStorm.Data.GuildActivityStore=Store
