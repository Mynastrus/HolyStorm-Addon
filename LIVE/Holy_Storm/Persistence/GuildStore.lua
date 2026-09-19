local addonVersion = "1.1.1"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store = { version=addonVersion, currentId = nil }
local function validateGuildData(data)
    return type(data) == "table" and type(data.roster) == "table" and type(data.ranks) == "table"
end

HolyStorm.DataManager:RegisterSchema({
    id="guild-roster", owner="GuildStore", version=1, versionField=false, validate=validateGuildData,
    storage={backend="database", scope="global", path={"data", "guilds"}},
})

function Store:Initialize() local data=HolyStorm.db.global.data; data.guilds=type(data.guilds)=="table" and data.guilds or {}; for id,guild in pairs(data.guilds) do if type(id)~="string" or type(guild)~="table" then data.guilds[id]=nil else guild.id=id; guild.roster=type(guild.roster)=="table" and guild.roster or {}; guild.ranks=type(guild.ranks)=="table" and guild.ranks or {}; guild.version=tonumber(guild.version)or 0 end end end
function Store:_GetAllLive() return HolyStorm.db.global.data.guilds end
function Store:GetAll() return HolyStorm.DataManager:SafeCopy(self:_GetAllLive()) end
function Store:Get(id) return id and HolyStorm.DataManager:Get("guild-roster", id) or nil end
function Store:GetCurrent() return self:Get(self.currentId) end
function Store:ResolveSenderGuid(sender)
    if type(sender)~="string" then return nil end; local full,short=string.lower(sender),string.lower(sender:match("^[^-]+")or sender); local qualified=sender:find("-",1,true)~=nil
    local guild=self:GetCurrent(); for guid,member in pairs(guild and guild.roster or {}) do local name=member.name; if name then local candidateFull,candidateShort=string.lower(name),string.lower(name:match("^[^-]+")or name); if candidateFull==full or (not qualified and candidateShort==short) then return guid end end end
end
function Store:GetLogDatabase() HS_GuildLog_DB=type(HS_GuildLog_DB)=="table" and HS_GuildLog_DB or {entries={},snapshot=nil}; HS_GuildLog_DB.entries=type(HS_GuildLog_DB.entries)=="table" and HS_GuildLog_DB.entries or {}; return HS_GuildLog_DB end
function Store:AddLogEntry(eventType,message)
    local entries=self:GetLogDatabase().entries; table.insert(entries,1,{timestamp=HolyStorm.Utils.Now(),eventType=eventType,message=message}); while #entries>1000 do table.remove(entries) end; HolyStorm.Events:Emit("HS_GUILD_LOG_UPDATED",eventType)
end
function Store:SetLogSnapshot(snapshot) self:GetLogDatabase().snapshot=HolyStorm.Utils.DeepCopy(snapshot) end
function Store:GetGuildId()
    if not IsInGuild() then return nil end
    local guildName, _, _, realm = GetGuildInfo("player"); realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    return guildName and (string.lower((realm or "unknown") .. ":" .. guildName)) or nil
end
function Store:RequestRoster() if IsInGuild() and _G.GuildRoster then _G.GuildRoster(); return true end; return false end
function Store:RefreshFromBlizzard()
    local id = self:GetGuildId(); HolyStorm.State:Set("guildAvailable", id ~= nil)
    if not id then self.currentId = nil; return false end
    local guildName, rankName, rankIndex, realm = GetGuildInfo("player"); realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    local roster, ranks = {}, {}
    if GuildControlGetNumRanks and GuildControlGetRankName then for index = 1, GuildControlGetNumRanks() do ranks[index] = GuildControlGetRankName(index) end end
    for index = 1, GetNumGuildMembers() do
        local name, rank, memberRankIndex, level, class, zone, note, officerNote, online, status, classFile, achievementPoints, achievementRank, mobile, canSoR, reputation, guid = GetGuildRosterInfo(index)
        if guid then
            roster[guid] = { guid=guid, index=index, name=name, rank=rank, rankIndex=memberRankIndex, level=level, class=class, classFile=classFile, zone=zone, note=note, officerNote=officerNote, online=online, status=status, isMobile=mobile, reputation=reputation }
            HolyStorm.Data.CharacterStore:Upsert(guid, { name=name, realm=name and name:match("%-([^%-]+)$") or realm, class=class, classFile=classFile, level=level, guild=guildName, guildRank=rank, guildRankIndex=memberRankIndex, lastSeen=online and HolyStorm.Utils.Now() or nil }, "blizzard")
        end
    end
    local record = self:Get(id) or { id=id, version=0, createdAt=HolyStorm.Utils.Now() }
    record.name, record.realm, record.playerRank, record.playerRankIndex = guildName, realm, rankName, rankIndex
    record.roster, record.ranks, record.updatedAt, record.updatedBy, record.version = roster, ranks, HolyStorm.Utils.Now(), UnitGUID("player"), (record.version or 0) + 1
    self:_GetAllLive()[id], self.currentId = record, id
    HolyStorm.State:Set("guildRosterReady", true); HolyStorm.Events:Emit("HS_GUILD_UPDATED", id, record); HolyStorm.Events:Emit("HS_ROSTER_UPDATED", id, roster); return true
end
HolyStorm.Data.GuildStore = Store
