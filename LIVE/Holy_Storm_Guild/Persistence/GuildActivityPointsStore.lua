local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={schema="guild-activity-points"}
local function default()return{schemaVersion=1,guilds={}}end
local function validate(root)
 if type(root)~="table"or root.schemaVersion~=1 or type(root.guilds)~="table"then return false end
 for guildId,guild in pairs(root.guilds)do
  if type(guildId)~="string"or type(guild)~="table"or type(guild.rules)~="table"or type(guild.ruleHistory)~="table"or type(guild.ledger)~="table"or type(guild.revision)~="number"or type(guild.decay)~="table"then return false end
 end
 return true
end
HolyStorm.DataManager:RegisterSchema({id=Store.schema,owner="GuildActivityPointsStore",version=1,storage={backend="database",scope="global",path={"guildManagement","activityPoints"}},default=default,validate=validate,event="HS_GUILD_ACTIVITY_POINTS_COMMITTED"})
function Store:GetRoot()return HolyStorm.DataManager:Get(Store.schema)or default()end
function Store:GetGuild(guildId)return guildId and HolyStorm.DataManager:Get(Store.schema,{"guilds",guildId})or nil end
function Store:PutGuild(guildId,value)
 if type(guildId)~="string"or type(value)~="table"then return false,"INVALID_GUILD"end
 local result=HolyStorm.DataManager:Commit(Store.schema,{"guilds",guildId},value,{operation="activity-points"});return result and result.ok==true,result
end
HolyStorm.Data.GuildActivityPointsStore=Store
