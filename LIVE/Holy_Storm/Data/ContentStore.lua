local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={version=addonVersion}

local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
local function now()return HolyStorm.Utils.Now()end

function Store:Initialize()
 local global=HolyStorm.db.global
 global.content=HolyStorm.Utils.ApplyDefaults(global.content,{guilds={},legacyNews={},legacyReads={},schemaVersion=1})
end

function Store:GetRoot()return HolyStorm.db.global.content end
function Store:GetGuildId()local guild=HolyStorm.Data.GuildStore:GetCurrent();return guild and guild.id end
function Store:GetGuild(guildId,create)
 guildId=guildId or self:GetGuildId();if not guildId then return nil end
 local guild=self:GetRoot().guilds[guildId]
 if not guild and create then guild={guildId=guildId,entries={},index={},reads={},history={},version=0};self:GetRoot().guilds[guildId]=guild end
 if guild then guild.entries=type(guild.entries)=="table"and guild.entries or{};guild.index=type(guild.index)=="table"and guild.index or{};guild.reads=type(guild.reads)=="table"and guild.reads or{};guild.history=type(guild.history)=="table"and guild.history or{};guild.version=tonumber(guild.version)or 0 end
 return guild
end
function Store:Get(id,guildId)local guild=self:GetGuild(guildId);return guild and guild.entries[id]end
function Store:GetIndex(guildId)local guild=self:GetGuild(guildId);return guild and guild.index or{}end
function Store:GetEntries(guildId)local guild=self:GetGuild(guildId);return guild and guild.entries or{}end
function Store:Put(entry,guildId)
 local guild=self:GetGuild(guildId or entry.guildId,true);if not guild then return false,"NO_GUILD"end
 guild.entries[entry.id]=copy(entry);guild.index[entry.id]={id=entry.id,guildId=entry.guildId,type=entry.type,category=entry.category,title=entry.title,slug=entry.slug,author=entry.author,authorGuid=entry.authorGuid,modifiedBy=entry.modifiedBy,modifiedAt=entry.modifiedAt,syncedAt=entry.syncedAt,status=entry.status,priority=entry.priority,visibility=copy(entry.visibility),tags=copy(entry.tags),revision=entry.revision,bodyLoaded=entry.body~=nil,source=entry.source or"local"};guild.version=guild.version+1;return true
end
function Store:AddHistory(entry,guildId)
 local guild=self:GetGuild(guildId,true);guild.history[entry.id]=guild.history[entry.id]or{};local history=guild.history[entry.id];history[#history+1]=copy(entry);while#history>10 do table.remove(history,1)end
end
function Store:GetRead(id,guid,guildId)local guild=self:GetGuild(guildId);return guild and guild.reads[id]and guild.reads[id][guid]end
function Store:SetRead(id,guid,revision,guildId)local guild=self:GetGuild(guildId,true);guild.reads[id]=guild.reads[id]or{};guild.reads[id][guid]={revision=revision,readAt=now()};return true end

function Store:MigrateLegacy(guildId)
 local root=self:GetRoot();guildId=guildId or self:GetGuildId();if not guildId or root.legacyMigratedGuild==guildId then return false end
 local legacy=root.legacyNews;local guild=self:GetGuild(guildId,true);local count=0
 for legacyId,old in pairs(type(legacy)=="table"and legacy or{})do if type(old)=="table"then
  local id=type(old.id)=="string"and old.id or("content-legacy-"..tostring(legacyId));if not id:match("^[%w%-_]+$")then id="content-legacy-"..tostring(legacyId):gsub("[^%w%-_]","")end;local status=string.upper(old.status or"DRAFT");if status=="DELETED"then status="ARCHIVED"end
  local ranks=copy(old.targetRanks or{});local fallbackGuid=old.authorGuid or old.updatedBy or(UnitGUID and UnitGUID("player"));local entry={id=id,guildId=guildId,type="NEWS",category=old.category or"GENERAL",title=old.title or id,slug=old.slug,body=old.body or old.content or"",author=old.author,authorGuid=fallbackGuid,modifiedBy=old.modifiedBy or old.updatedBy or fallbackGuid,createdAt=old.createdAt or old.date or now(),modifiedAt=old.modifiedAt or old.updatedAt or old.date or now(),publishedAt=old.publishedAt,priority=old.pinned and"IMPORTANT"or type(old.priority)=="number"and(old.priority>=3 and"URGENT"or old.priority>=2 and"IMPORTANT"or"NORMAL")or string.upper(tostring(old.priority or"NORMAL")),status=({DRAFT=true,PUBLISHED=true,ARCHIVED=true})[status]and status or"DRAFT",revision=tonumber(old.revision or old.version)or 1,tags=copy(old.tags or{}),icon=old.icon,metadata=copy(old.metadata or{}),visibility={scope=next(ranks)and"RANKS"or"GUILD",rankIds=ranks},source="legacy-news"}
  guild.entries[id]=entry;self:Put(entry,guildId);count=count+1
 end end
 for id,readers in pairs(type(root.legacyReads)=="table"and root.legacyReads or{})do for guid,read in pairs(type(readers)=="table"and readers or{})do local revision=tonumber(read.revision or read.version)or 0;if revision>0 then self:SetRead(id,guid,revision,guildId)end end end
 root.legacyMigratedGuild=guildId;return count>0,count
end
HolyStorm.Data.ContentStore=Store
