local addonVersion = "1.2.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store = { version=addonVersion, currentId = nil, normalized = setmetatable({}, {__mode="v"}) }
local function validateGuildData(data)
    return type(data) == "table" and type(data.roster) == "table" and type(data.ranks) == "table"
end
local function flatEqual(left,right)
    if type(left)~="table"or type(right)~="table"then return false end
    for key,value in pairs(left)do if right[key]~=value then return false end end;for key in pairs(right)do if left[key]==nil then return false end end;return true
end
local function rosterEqual(record,name,realm,playerRank,playerRankIndex,roster,ranks)
    if type(record)~="table"or record.name~=name or record.realm~=realm or record.playerRank~=playerRank or record.playerRankIndex~=playerRankIndex or not flatEqual(record.ranks,ranks)then return false end
    if type(record.roster)~="table"then return false end;for guid,member in pairs(record.roster)do if not flatEqual(member,roster[guid])then return false end end;for guid in pairs(roster)do if record.roster[guid]==nil then return false end end;return true
end

HolyStorm.DataManager:RegisterSchema({
    id="guild-roster", owner="GuildStore", version=1, versionField=false, validate=validateGuildData,
    storage={backend="database", scope="global", path={"data", "guilds"}},
})

function Store:Initialize()local data=HolyStorm.db.global.data;data.guilds=type(data.guilds)=="table"and data.guilds or{};self.normalized=setmetatable({},{__mode="v"})end
function Store:_Normalize(id,guild)
    if type(id)~="string"or type(guild)~="table"then return nil end
    if self.normalized[id]~=guild then guild.id=id;guild.roster=type(guild.roster)=="table"and guild.roster or{};guild.ranks=type(guild.ranks)=="table"and guild.ranks or{};guild.version=tonumber(guild.version)or 0;self.normalized[id]=guild end
    return guild
end
function Store:_GetAllLive(normalize)
    local guilds=HolyStorm.db.global.data.guilds
    if normalize then for id,guild in pairs(guilds)do if not self:_Normalize(id,guild)then guilds[id]=nil;self.normalized[id]=nil end end end
    return guilds
end
function Store:_GetLive(id)return id and self:_Normalize(id,self:_GetAllLive()[id])or nil end
function Store:GetAll()return HolyStorm.DataManager:SafeCopy(self:_GetAllLive(true))end
function Store:Get(id)if not self:_GetLive(id)then return nil end;return HolyStorm.DataManager:Get("guild-roster",id)end
function Store:GetCurrent() return self:Get(self.currentId) end
function Store:GetCurrentRosterSummary()
    local guild=self:_GetLive(self.currentId);if not guild then return nil end
    local summary={id=guild.id,roster={}}
    for guid,member in pairs(type(guild.roster)=="table" and guild.roster or{})do
        if type(member)=="table" then summary.roster[guid]={rankIndex=member.rankIndex,classFile=member.classFile,level=member.level} end
    end
    return summary
end
function Store:GetDiagnostics()return{guilds=HolyStorm.Utils.TableCount(self:_GetAllLive()),normalized=HolyStorm.Utils.TableCount(self.normalized),currentId=self.currentId}end
function Store:ResolveSenderGuid(sender)
    if type(sender)~="string" then return nil end; local full,short=string.lower(sender),string.lower(sender:match("^[^-]+")or sender); local qualified=sender:find("-",1,true)~=nil
    local guild=self:GetCurrent(); for guid,member in pairs(guild and guild.roster or {}) do local name=member.name; if name then local candidateFull,candidateShort=string.lower(name),string.lower(name:match("^[^-]+")or name); if candidateFull==full or (not qualified and candidateShort==short) then return guid end end end
end
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
            -- Online presence belongs to the live roster. Reconciliation must not
            -- refresh the authoritative identity timestamp when nothing changed.
            HolyStorm.Data.CharacterStore:Upsert(guid, { name=name, realm=name and name:match("%-([^%-]+)$") or realm, class=class, classFile=classFile, level=level, guild=guildName, guildRank=rank, guildRankIndex=memberRankIndex }, "blizzard")
        end
    end
    local record = self:_GetLive(id)
    if rosterEqual(record,guildName,realm,rankName,rankIndex,roster,ranks)then self.currentId=id;HolyStorm.State:Set("guildRosterReady",true);return false,"UNCHANGED"end
    record = record or { id=id, version=0, createdAt=HolyStorm.Utils.Now() }
    record.name, record.realm, record.playerRank, record.playerRankIndex = guildName, realm, rankName, rankIndex
    record.roster, record.ranks, record.updatedAt, record.updatedBy, record.version = roster, ranks, HolyStorm.Utils.Now(), UnitGUID("player"), (record.version or 0) + 1
    self:_GetAllLive()[id], self.currentId = record, id
    HolyStorm.State:Set("guildRosterReady", true); HolyStorm.Events:Emit("HS_GUILD_UPDATED", id, record); HolyStorm.Events:Emit("HS_ROSTER_UPDATED", id, roster); return true
end
HolyStorm.Data.GuildStore = Store
