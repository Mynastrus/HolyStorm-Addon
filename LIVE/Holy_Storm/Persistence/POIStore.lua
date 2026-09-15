local addonVersion="1.0.0"
local HolyStorm=LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store={version=addonVersion}
local function copy(value)return HolyStorm.Utils.DeepCopy(value)end
function Store:Initialize()HolyStorm.db.global.poi=HolyStorm.Utils.ApplyDefaults(HolyStorm.db.global.poi,{personal={},guilds={},sessions={},schemaVersion=1})end
function Store:GetRoot()return HolyStorm.db.global.poi end
function Store:GetGuildId()local guild=HolyStorm.Data.GuildStore:GetCurrent();return guild and guild.id end
function Store:GetBucket(target,sessionId,create,guildId)
 local root=self:GetRoot();if target=="PERSONAL"then return root.personal end;if target=="GUILD"then guildId=guildId or self:GetGuildId();if not guildId then return nil end;if create and not root.guilds[guildId]then root.guilds[guildId]={}end;return root.guilds[guildId]end;if target=="GROUP"or target=="RAID"then if not sessionId then return nil end;if create and not root.sessions[sessionId]then root.sessions[sessionId]={target=target,entries={}}end;local session=root.sessions[sessionId];return session and session.target==target and session.entries or nil end
end
function Store:Get(id,target,sessionId,guildId)
 if target then local bucket=self:GetBucket(target,sessionId,false,guildId);return bucket and bucket[id]end
 local root=self:GetRoot();if root.personal[id]then return root.personal[id]end;local guild=self:GetBucket("GUILD",nil,false,guildId);if guild and guild[id]then return guild[id]end;for _,session in pairs(root.sessions)do if session.entries[id]then return session.entries[id]end end
end
function Store:Put(entry)local bucket=self:GetBucket(entry.target,entry.sessionId,true,entry.guildId);if not bucket then return false,"NO_SCOPE"end;bucket[entry.poiID]=copy(entry);return true end
function Store:Remove(entry)local bucket=entry and self:GetBucket(entry.target,entry.sessionId,false,entry.guildId);if not bucket or not bucket[entry.poiID]then return false end;bucket[entry.poiID]=nil;return true end
function Store:GetAll(guildId)
 local out,root={},self:GetRoot();for _,entry in pairs(root.personal)do out[#out+1]=entry end;for _,entry in pairs(self:GetBucket("GUILD",nil,false,guildId)or{})do out[#out+1]=entry end;for _,session in pairs(root.sessions)do for _,entry in pairs(session.entries or{})do out[#out+1]=entry end end;return out
end
function Store:RemoveSession(sessionId)local session=self:GetRoot().sessions[sessionId];if not session then return 0 end;local count=HolyStorm.Utils.TableCount(session.entries);self:GetRoot().sessions[sessionId]=nil;return count end
function Store:RemoveOtherSessions(currentId,target)local removed=0;for id,session in pairs(self:GetRoot().sessions)do if id~=currentId and(not target or session.target==target)then removed=removed+self:RemoveSession(id)end end;return removed end
HolyStorm.Data.POIStore=Store
