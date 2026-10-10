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
function Store:GetRules(guildId)guildId=guildId or HolyStorm.GuildManagement:GetGuildId();return guildId and HolyStorm.DataManager:Get(Store.schema,{"guilds",guildId,"rules"})or nil end
function Store:GetScoreData(guildId,accountUUID)
 if not guildId or not accountUUID then return nil end
 local root=HolyStorm.DataManager:GetOwnedRoot(Store.schema,"GuildActivityPointsStore");local guild=root and root.guilds and root.guilds[guildId];if not guild then return nil end
 local ids=guild.ledgerByAccount and guild.ledgerByAccount[accountUUID]or{};local entries={};for _,entryId in ipairs(ids)do local entry=guild.ledger[entryId];if entry then entries[#entries+1]=HolyStorm.Utils.DeepCopy(entry)end end
 return{revision=guild.revision,decay=HolyStorm.Utils.DeepCopy(guild.decay),entries=entries}
end
function Store:PutGuild(guildId,value)
 if type(guildId)~="string"or type(value)~="table"or type(value.rules)~="table"or type(value.ruleHistory)~="table"or type(value.ledger)~="table"or type(value.ledgerByAccount)~="table"or type(value.revision)~="number"or type(value.decay)~="table"then return false,"INVALID_GUILD"end
 value.ledgerByAccount=type(value.ledgerByAccount)=="table"and value.ledgerByAccount or{};for _,ids in pairs(value.ledgerByAccount)do table.sort(ids)end
 local persisted,copyResult=HolyStorm.DataManager:SafeCopy(value);if not persisted then return false,copyResult end
 local root,rootResult=HolyStorm.DataManager:GetOwnedRoot(Store.schema,"GuildActivityPointsStore");if not root then return false,rootResult end;if root.schemaVersion~=1 or type(root.guilds)~="table"then return false,"INVALID_ACTIVITY_POINTS_ROOT"end
 local resultGuild=root.guilds[guildId];if resultGuild~=nil and type(resultGuild)~="table"then return false,"INVALID_ACTIVITY_POINTS_GUILD"end;root.guilds[guildId]=persisted
 local result={ok=true,changed=true,operation="put-guild",schema=Store.schema,version=1};if HolyStorm.Events and type(HolyStorm.Events.Emit)=="function"then pcall(HolyStorm.Events.Emit,HolyStorm.Events,"HS_GUILD_ACTIVITY_POINTS_COMMITTED",Store.schema,result,{operation="activity-points"})end;return true,result
end
function Store:HasEntry(guildId,entryId)if type(guildId)~="string"or type(entryId)~="string"then return false end;return HolyStorm.DataManager:Exists(Store.schema,{"guilds",guildId,"ledger",entryId})==true end
function Store:AppendEntry(guildId,entry)
 if type(guildId)~="string"or type(entry)~="table"or entry.guildId~=guildId or type(entry.entryId)~="string"or entry.entryId==""or type(entry.accountUUID)~="string"or entry.accountUUID==""then return false,"INVALID_LEDGER_ENTRY"end
 local persisted,copyResult=HolyStorm.DataManager:SafeCopy(entry);if not persisted then return false,copyResult end
 local root,rootResult=HolyStorm.DataManager:GetOwnedRoot(Store.schema,"GuildActivityPointsStore");if not root then return false,rootResult end;if root.schemaVersion~=1 or type(root.guilds)~="table"then return false,"INVALID_ACTIVITY_POINTS_ROOT"end;local guild=root.guilds[guildId]
 if type(guild)~="table"or type(guild.ledger)~="table"or type(guild.ledgerByAccount)~="table"then return false,"ACTIVITY_POINTS_GUILD_NOT_READY"end
 if guild.ledger[entry.entryId]then return true,"DUPLICATE"end
 local ids=guild.ledgerByAccount[entry.accountUUID];if ids~=nil and type(ids)~="table"then return false,"INVALID_LEDGER_ACCOUNT_INDEX"end;ids=ids or{};local cache=guild.cache;if cache~=nil and type(cache)~="table"then return false,"INVALID_ACTIVITY_POINTS_CACHE"end
 local low,high=1,#ids+1;while low<high do local middle=math.floor((low+high)/2);if ids[middle]<entry.entryId then low=middle+1 else high=middle end end;if ids[low]==entry.entryId then return false,"LEDGER_INDEX_CONFLICT"end
 guild.ledger[entry.entryId]=persisted;table.insert(ids,low,entry.entryId);guild.ledgerByAccount[entry.accountUUID]=ids;guild.cache=guild.cache or{};guild.cache[entry.accountUUID]=nil
 local result={ok=true,changed=true,operation="append-ledger-entry",schema=Store.schema,version=1};if HolyStorm.Events and type(HolyStorm.Events.Emit)=="function"then pcall(HolyStorm.Events.Emit,HolyStorm.Events,"HS_GUILD_ACTIVITY_POINTS_COMMITTED",Store.schema,result,{operation="activity-points-append"})end;return true,result
end
HolyStorm.Data.GuildActivityPointsStore=Store
