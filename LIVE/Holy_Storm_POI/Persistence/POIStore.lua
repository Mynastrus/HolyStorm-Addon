local addonVersion = "1.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store = { version=addonVersion, schema="poi-store", schemaVersion=2 }
local DataManager = HolyStorm.DataManager

local function migrateEntry(entry, target, guildId, sessionId)
    if type(entry) ~= "table" then return end
    entry.schemaVersion = 2
    entry.target = entry.target or target
    entry.scope = entry.scope or entry.target
    entry.guildId = entry.target == "GUILD" and (entry.guildId or guildId) or nil
    entry.sessionId = (entry.target == "GROUP" or entry.target == "RAID") and (entry.sessionId or sessionId) or nil
    entry.revision = math.max(1, math.floor(tonumber(entry.revision) or 1))
    entry.creatorGuid = entry.creatorGuid or entry.modifiedBy or "legacy-unknown"
    entry.modifiedBy = entry.modifiedBy or entry.creatorGuid
    entry.createdAt = tonumber(entry.createdAt) or tonumber(entry.updatedAt) or 0
    entry.updatedAt = tonumber(entry.updatedAt) or entry.createdAt
    entry.revisionID = entry.revisionID or string.format("legacy-%s-%d", tostring(entry.poiID or "unknown"), entry.revision)
    entry.provenance = type(entry.provenance) == "table" and entry.provenance or { kind="MANUAL", metadata={ migrated=true } }
    entry.icon = type(entry.icon) == "string" and entry.icon or "marker"
    entry.category = type(entry.category) == "string" and entry.category or "note"
    entry.color = type(entry.color) == "table" and entry.color or { r=1, g=.82, b=0, a=1 }
    entry.source = nil
    entry.receivedFrom = nil
    entry.syncedAt = nil
end

local function migrateRoot(root)
    root.personal = type(root.personal) == "table" and root.personal or {}
    root.guilds = type(root.guilds) == "table" and root.guilds or {}
    root.sessions = type(root.sessions) == "table" and root.sessions or {}
    for _, entry in pairs(root.personal) do migrateEntry(entry, "PERSONAL") end
    for guildId, entries in pairs(root.guilds) do
        if type(entries) == "table" then for _, entry in pairs(entries) do migrateEntry(entry, "GUILD", guildId) end end
    end
    for sessionId, session in pairs(root.sessions) do
        if type(session) == "table" then
            session.target = session.target == "RAID" and "RAID" or "GROUP"
            session.entries = type(session.entries) == "table" and session.entries or {}
            for _, entry in pairs(session.entries) do migrateEntry(entry, session.target, nil, sessionId) end
        end
    end
    return root
end

DataManager:RegisterSchema({
    id=Store.schema,
    owner="POIStore",
    version=Store.schemaVersion,
    storage={ backend="database", scope="global", path={"poi"} },
    default=function() return { schemaVersion=2, personal={}, guilds={}, sessions={} } end,
    validate=function(root)
        return type(root) == "table" and root.schemaVersion == 2 and type(root.personal) == "table"
            and type(root.guilds) == "table" and type(root.sessions) == "table"
    end,
    migrations={{ fromVersion=1, toVersion=2, migrate=migrateRoot }},
    event="HS_POI_STORE_COMMITTED",
    metadata={ purpose="persistent-local-and-guild-poi-store", rootSchemaVersion=2 },
})

function Store:Initialize()
    local value = DataManager:Get(Store.schema)
    if value then
        local version = tonumber(value.schemaVersion)
        if version and version < Store.schemaVersion then
            local result = DataManager:RunMigrations(Store.schema, { reason="POI_SCHEMA_UPGRADE" })
            if not result or result.ok ~= true then return false, result and result.errorCode or "MIGRATION_FAILED" end
        elseif version and version > Store.schemaVersion then
            return false, "SCHEMA_VERSION_NEWER"
        end
    else
        local result = DataManager:Commit(Store.schema, nil, { schemaVersion=2, personal={}, guilds={}, sessions={} }, { reason="POI_SCHEMA_INITIALIZE" })
        if not result or result.ok ~= true then return false, result and result.errorCode or "INITIALIZE_FAILED" end
    end
    self.root = DataManager:GetOwnedRoot(Store.schema, "POIStore")
    if not self.root then return false,"STORE_UNAVAILABLE" end
    return true
end

function Store:GetRoot()
    if not self.root then self:Initialize() end
    return self.root
end

function Store:GetGuildId()
    local guild = HolyStorm.Data.GuildStore:GetCurrent()
    return guild and guild.id
end

function Store:GetBucket(target, sessionId, create, guildId)
    local root = self:GetRoot()
    if not root then return nil end
    if target == "PERSONAL" then return root.personal end
    if target == "GUILD" then
        guildId = guildId or self:GetGuildId()
        if not guildId then return nil end
        if create and not root.guilds[guildId] then root.guilds[guildId] = {} end
        return root.guilds[guildId]
    end
    if target == "GROUP" or target == "RAID" then
        if not sessionId then return nil end
        if create and not root.sessions[sessionId] then root.sessions[sessionId] = { target=target, entries={} } end
        local session = root.sessions[sessionId]
        return session and session.target == target and session.entries or nil
    end
end

function Store:Get(id, target, sessionId, guildId)
    if target then local bucket=self:GetBucket(target,sessionId,false,guildId);return bucket and bucket[id] end
    local root=self:GetRoot();if not root then return nil end
    if root.personal[id] then return root.personal[id] end
    local guild=self:GetBucket("GUILD",nil,false,guildId);if guild and guild[id] then return guild[id] end
    for _,session in pairs(root.sessions) do if session.entries and session.entries[id] then return session.entries[id] end end
end

function Store:Put(entry)
    local bucket=self:GetBucket(entry.target,entry.sessionId,true,entry.guildId)
    if not bucket then return false,"NO_SCOPE" end
    bucket[entry.poiID]=HolyStorm.Utils.DeepCopy(entry)
    return true
end

function Store:Remove(entry)
    local bucket=entry and self:GetBucket(entry.target,entry.sessionId,false,entry.guildId)
    if not bucket or not bucket[entry.poiID] then return false end
    bucket[entry.poiID]=nil
    return true
end

function Store:GetAll(guildId)
    local out,root={},self:GetRoot();if not root then return out end
    for _,entry in pairs(root.personal) do out[#out+1]=entry end
    for _,entry in pairs(self:GetBucket("GUILD",nil,false,guildId) or {}) do out[#out+1]=entry end
    for _,session in pairs(root.sessions) do for _,entry in pairs(session.entries or {}) do out[#out+1]=entry end end
    return out
end

function Store:RemoveSession(sessionId)
    local root=self:GetRoot();local session=root and root.sessions[sessionId];if not session then return 0 end
    local count=HolyStorm.Utils.TableCount(session.entries);root.sessions[sessionId]=nil;return count
end

function Store:RemoveOtherSessions(currentId,target)
    local removed=0;local root=self:GetRoot();if not root then return 0 end
    for id,session in pairs(root.sessions) do if id~=currentId and (not target or session.target==target) then removed=removed+self:RemoveSession(id) end end
    return removed
end

HolyStorm.Data.POIStore=Store
