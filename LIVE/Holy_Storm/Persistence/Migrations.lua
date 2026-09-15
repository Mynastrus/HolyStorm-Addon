local addonVersion = "1.4.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")
local Migrations = { version=addonVersion, steps = {} }
local function identifier(prefix) return string.format("%s-%08x-%08x", prefix, HolyStorm.Utils.Now(), math.random(0, 0x7fffffff)) end

Migrations.steps[1] = function(global, legacy)
    global.installId = type(global.installId) == "string" and global.installId or identifier("install")
    global.localPlayerId = type(global.localPlayerId) == "string" and global.localPlayerId or identifier("player")
    global.data = HolyStorm.Utils.ApplyDefaults(global.data, { guilds = {}, players = {}, characters = {}, characterOwners = {} })
    if type(global.playerProfiles) == "table" then for id, player in pairs(global.playerProfiles) do if type(id) == "string" and type(player) == "table" then global.data.players[id] = HolyStorm.Utils.ApplyDefaults(global.data.players[id], player) end end end
    if type(global.characterOwners) == "table" then for guid, playerId in pairs(global.characterOwners) do if type(guid) == "string" and type(playerId) == "string" then global.data.characterOwners[guid] = playerId end end end
    if type(legacy) == "table" then global.legacySettings = HolyStorm.Utils.DeepCopy(legacy) end
end
Migrations.steps[2] = function(global)
    local localId, data = global.localPlayerId, global.data
    data.players[localId] = HolyStorm.Utils.ApplyDefaults(data.players[localId], { id = localId, installId = global.installId, characters = {}, roles = {}, createdAt = HolyStorm.Utils.Now(), updatedAt = HolyStorm.Utils.Now(), version = 1 })
    local function migrateCharacter(guid, record, preferredOwner)
        if type(guid) ~= "string" or type(record) ~= "table" then return end
        local character = data.characters[guid] or { guid = guid, fieldSources = {} }
        for key, value in pairs(record) do if character[key] == nil and key ~= "knownTwinks" then character[key] = HolyStorm.Utils.DeepCopy(value) end end
        character.guid, character.updatedAt, character.version = guid, character.updatedAt or HolyStorm.Utils.Now(), character.version or 1
        data.characters[guid] = character
        local owner = data.characterOwners[guid] or preferredOwner or (record.playerId and tostring(record.playerId)) or ("legacy-" .. guid)
        data.characterOwners[guid] = owner
        data.players[owner] = HolyStorm.Utils.ApplyDefaults(data.players[owner], { id = owner, characters = {}, roles = {}, createdAt = character.updatedAt, updatedAt = character.updatedAt, version = 1 })
        data.players[owner].characters[guid] = true; character.playerId = owner
    end
    if type(global.twinks) == "table" then for guid, record in pairs(global.twinks) do migrateCharacter(guid, record, localId) end end
    if type(HS_Player_DB) == "table" then for guid, record in pairs(HS_Player_DB) do migrateCharacter(guid, record) end end
    if type(HS_Player_DB)=="table" then for ownerGuid,record in pairs(HS_Player_DB) do
        local ownerId=data.characterOwners[ownerGuid]; local player=ownerId and data.players[ownerId]
        if player and type(record)=="table" then
            if type(record.realName)=="string" or type(record.birthday)=="string" then player.metadata=type(player.metadata)=="table" and player.metadata or {}; player.metadata.realName=type(record.realName)=="string" and record.realName or player.metadata.realName; player.metadata.birthday=type(record.birthday)=="string" and record.birthday or player.metadata.birthday end
            for twinkGuid,known in pairs(type(record.knownTwinks)=="table" and record.knownTwinks or {}) do if known==true and type(twinkGuid)=="string" and data.characters[twinkGuid] then local oldId=data.characterOwners[twinkGuid]; if oldId and data.players[oldId] then data.players[oldId].characters[twinkGuid]=nil; if oldId~=localId and not next(data.players[oldId].characters) then data.players[oldId]=nil end end; data.characterOwners[twinkGuid]=ownerId; player.characters[twinkGuid]=true; data.characters[twinkGuid].playerId=ownerId end end
        end
    end end
    for guid,record in pairs(data.characters) do if not HS_Player_DB[guid] then HS_Player_DB[guid]=HolyStorm.Utils.DeepCopy(record) end end
end
Migrations.steps[3] = function(global)
    global.permissions = HolyStorm.Utils.ApplyDefaults(global.permissions, { roles = {}, assignments = {} })
    local leader = global.permissions.roles.guild_leader or {}
    leader.id, leader.name, leader.system, leader.permissions = "guild_leader", leader.name or L["ROLE_GUILD_LEADER"], true, { ["*"] = true }
    leader.version, leader.updatedAt = leader.version or 1, leader.updatedAt or HolyStorm.Utils.Now(); global.permissions.roles.guild_leader = leader
    for id, player in pairs(global.data.players) do player.id = id; player.characters = type(player.characters) == "table" and player.characters or {}; player.roles = type(player.roles) == "table" and player.roles or {} end
end
Migrations.steps[4] = function(global)
    global.filters = HolyStorm.Utils.ApplyDefaults(global.filters, { global={}, version=1, demands={quests={},achievements={}} })
    global.news = HolyStorm.Utils.ApplyDefaults(global.news, { entries={}, reads={}, firstSeenMembers={}, version=1 })
    global.logs = HolyStorm.Utils.ApplyDefaults(global.logs, { entries={} })
    global.permissions = HolyStorm.Utils.ApplyDefaults(global.permissions, { groups={}, roles={}, assignments={}, version=1 })
    -- Keep legacy roles intact; the permission service migrates them into editable groups.
end
Migrations.steps[5] = function(global)
    global.rules = HolyStorm.Utils.ApplyDefaults(global.rules, { global={}, version=1 })
    global.filters = HolyStorm.Utils.ApplyDefaults(global.filters, { global={}, templates={}, version=1, demands={quests={},achievements={}} })
    global.policy = HolyStorm.Utils.ApplyDefaults(global.policy, { version=1, tombstones={groups={},rules={},filters={}} })
    local permissions = HolyStorm.Utils.ApplyDefaults(global.permissions, { groups={},roles={},assignments={},version=1 })
    local aliases = { guild_leader="SYSTEM_GUILD_MASTER", officers="SYSTEM_OFFICERS", users="SYSTEM_USERS" }
    for oldId,newId in pairs(aliases) do
        local old = permissions.groups[oldId] or permissions.roles[oldId]
        if type(old)=="table" and not permissions.groups[newId] then old=HolyStorm.Utils.DeepCopy(old);old.id=newId;permissions.groups[newId]=old end
    end
    permissions.roles=permissions.groups
end
Migrations.steps[6] = function(global)
    -- HS_Player_DB v2 becomes canonical. Preserve both the historical flat
    -- layout and the HolyStormDB character/player records, preferring an
    -- already-present canonical record so migration cannot overwrite it.
    HS_Player_DB=type(HS_Player_DB)=="table"and HS_Player_DB or{}
    local old=HS_Player_DB.characters==nil and HS_Player_DB or nil
    local root=old and{}or HS_Player_DB
    root.schemaVersion=2;root.characters=type(root.characters)=="table"and root.characters or{};root.players=type(root.players)=="table"and root.players or{};root.characterOwners=type(root.characterOwners)=="table"and root.characterOwners or{};root.sync=type(root.sync)=="table"and root.sync or{foreignWatermark=0}
    if old then for guid,record in pairs(old)do if type(guid)=="string"and type(record)=="table"then root.characters[guid]=HolyStorm.Utils.DeepCopy(record)end end end
    local data=type(global.data)=="table"and global.data or{}
    for guid,record in pairs(type(data.characters)=="table"and data.characters or{})do if type(guid)=="string"and type(record)=="table"and not root.characters[guid]then root.characters[guid]=HolyStorm.Utils.DeepCopy(record)end end
    for id,record in pairs(type(data.players)=="table"and data.players or{})do if type(id)=="string"and type(record)=="table"and not root.players[id]then root.players[id]=HolyStorm.Utils.DeepCopy(record)end end
    for guid,id in pairs(type(data.characterOwners)=="table"and data.characterOwners or{})do if type(guid)=="string"and type(id)=="string"and not root.characterOwners[guid]then root.characterOwners[guid]=id end end
    HS_Player_DB=root
end
Migrations.steps[7] = function(global)
    HS_Player_DB=type(HS_Player_DB)=="table"and HS_Player_DB or{}
    HS_Player_DB.accounts=type(HS_Player_DB.accounts)=="table"and HS_Player_DB.accounts or type(HS_Player_DB.players)=="table"and HS_Player_DB.players or{}
    HS_Player_DB.players=HS_Player_DB.accounts
    HS_Player_DB.characterAccounts=type(HS_Player_DB.characterAccounts)=="table"and HS_Player_DB.characterAccounts or type(HS_Player_DB.characterOwners)=="table"and HS_Player_DB.characterOwners or{}
    HS_Player_DB.characterOwners=HS_Player_DB.characterAccounts
    HS_Player_DB.localAccountUUID=type(HS_Player_DB.localAccountUUID)=="string"and HS_Player_DB.localAccountUUID or type(global.localAccountUUID)=="string"and global.localAccountUUID or global.localPlayerId
    global.localAccountUUID=HS_Player_DB.localAccountUUID;global.localPlayerId=HS_Player_DB.localAccountUUID
    HS_Player_DB.adminTwinkTombstones=type(HS_Player_DB.adminTwinkTombstones)=="table"and HS_Player_DB.adminTwinkTombstones or{}
    HS_Player_DB.twinkSchemaVersion=1
end
Migrations.steps[8] = function(global)
    -- Guild-scoped revision states are created lazily once a stable current
    -- guild identity and Blizzard roster trust anchor are available. Legacy
    -- groups/filters remain here as one-time migration input for Policy.
    global.permissionStates = type(global.permissionStates) == "table" and global.permissionStates or {}
    global.permissionSchemaVersion = 1
end
Migrations.steps[9] = function(global)
    local old=type(global.news)=="table"and global.news or{}
    global.content=HolyStorm.Utils.ApplyDefaults(global.content,{guilds={},legacyNews={},legacyReads={},schemaVersion=1})
    for id,entry in pairs(type(old.entries)=="table"and old.entries or{})do if global.content.legacyNews[id]==nil then global.content.legacyNews[id]=HolyStorm.Utils.DeepCopy(entry)end end
    for id,readers in pairs(type(old.reads)=="table"and old.reads or{})do if global.content.legacyReads[id]==nil then global.content.legacyReads[id]=HolyStorm.Utils.DeepCopy(readers)end end
    global.news=nil
end
Migrations.steps[10] = function(global)
    global.poi=HolyStorm.Utils.ApplyDefaults(global.poi,{personal={},guilds={},sessions={},schemaVersion=1})
end
Migrations.steps[11] = function()
    -- Live positions stay ephemeral; profile defaults are applied by AceDB.
end
Migrations.steps[12] = function(global)
 global.achievements=HolyStorm.Utils.ApplyDefaults(global.achievements,{guilds={},schemaVersion=1});local achievementPermissions={"achievement-view","achievement-create","achievement-edit","achievement-delete","achievement-publish","achievement-award","achievement-revoke","achievement-admin","achievement-test"}
 for _,state in pairs(type(global.permissionStates)=="table"and global.permissionStates or{})do local groups=type(state)=="table"and state.groups;if groups then local member=groups["guild-member"];if member then member.permissions=type(member.permissions)=="table"and member.permissions or{};member.permissions["achievement-view"]=true end;local officers=groups.officers;if officers then officers.permissions=type(officers.permissions)=="table"and officers.permissions or{};for _,permission in ipairs(achievementPermissions)do officers.permissions[permission]=true end end end end
end
function Migrations:Run(global, fromVersion, legacy)
    local target = HolyStorm.Data.Schema.version
    for version = math.max(0, tonumber(fromVersion) or 0) + 1, target do
        local migration = self.steps[version]; if migration then
            local ok, err = pcall(migration, global, legacy); if not ok then return false, string.format("migration %d failed: %s", version, tostring(err)) end
        end
        global.schemaVersion = version
    end
    return true
end
HolyStorm.Data.Migrations = Migrations
