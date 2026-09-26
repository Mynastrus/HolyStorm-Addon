local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={schema="guild-activity-points"}
local function default()return{schemaVersion=1,guilds={}}end
local function validate(root)
 if type(root)~="table"or root.schemaVersion~=1 or type(root.guilds)~="table"then return false end
 for guildId,guild in pairs(root.guilds)do
  if type(guildId)~="string"or type(guild)~="table"or type(guild.rules)~="table"or type(guild.ruleHistory)~="table"or type(guild.ledger)~="table"or type(guild.ledgerByAccount)~="table"or type(guild.revision)~="number"or type(guild.decay)~="table"then return false end
 end
 return true
end
HolyStorm.DataManager:RegisterSchema({id=Store.schema,owner="GuildActivityPointsStore",version=1,storage={backend="database",scope="global",path={"guildManagement","activityPoints"}},default=default,validate=validate,event="HS_GUILD_ACTIVITY_POINTS_COMMITTED"})
function Store:GetRoot()return HolyStorm.DataManager:Get(Store.schema)or default()end
function Store:GetGuild(guildId)return guildId and HolyStorm.DataManager:Get(Store.schema,{"guilds",guildId})or nil end
function Store:GetScoreData(guildId,accountUUID)
 if not guildId or not accountUUID then return nil end
 local root=HolyStorm.DataManager:GetOwnedRoot(Store.schema,"GuildActivityPointsStore");local guild=root and root.guilds and root.guilds[guildId];if not guild then return nil end
 local ids=guild.ledgerByAccount and guild.ledgerByAccount[accountUUID]or{};local entries={};for _,entryId in ipairs(ids)do local entry=guild.ledger[entryId];if entry then entries[#entries+1]=HolyStorm.Utils.DeepCopy(entry)end end
 return{revision=guild.revision,decay=HolyStorm.Utils.DeepCopy(guild.decay),entries=entries}
end
function Store:PutGuild(guildId,value)
 if type(guildId)~="string"or type(value)~="table"then return false,"INVALID_GUILD"end
 value.ledgerByAccount=type(value.ledgerByAccount)=="table"and value.ledgerByAccount or{};for _,ids in pairs(value.ledgerByAccount)do table.sort(ids)end
 local result=HolyStorm.DataManager:Commit(Store.schema,{"guilds",guildId},value,{operation="activity-points"});return result and result.ok==true,result
end
HolyStorm.Data.GuildActivityPointsStore=Store
