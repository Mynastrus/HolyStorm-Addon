local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Settings = { version=addonVersion, definitions={}, schemaVersion=1 }
local validScopes = { character=true, account=true, guild=true, allGuilds=true }

local function copy(value)
    return HolyStorm.Utils.DeepCopy(value)
end

local function listScopes(value)
    local result = {}
    for _, scope in ipairs(value or {}) do
        if validScopes[scope] then result[scope] = true end
    end
    return result
end

local function root()
    local database = HolyStorm.Database and HolyStorm.Database:GetHandle()
    if not database then return nil end
    local global = database.global
    global.localSettings = type(global.localSettings) == "table" and global.localSettings or {}
    local store = global.localSettings
    store.character = type(store.character) == "table" and store.character or {}
    store.account = type(store.account) == "table" and store.account or {}
    store.guild = type(store.guild) == "table" and store.guild or {}
    store.allGuilds = type(store.allGuilds) == "table" and store.allGuilds or {}
    store.selectedScopes = type(store.selectedScopes) == "table" and store.selectedScopes or {}
    return store
end

local function currentCharacter()
    return type(UnitGUID) == "function" and UnitGUID("player") or nil
end

local function currentGuild()
    local guild = HolyStorm.Data and HolyStorm.Data.GuildStore and HolyStorm.Data.GuildStore:GetCurrent()
    return guild and (guild.id or guild.guildId) or nil
end

function Settings:Register(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string" or definition.id == "" then
        return false, "INVALID_SETTING_DEFINITION"
    end
    if type(definition.module) ~= "string" or type(definition.type) ~= "string" or definition.default == nil then
        return false, "INCOMPLETE_SETTING_DEFINITION"
    end
    local scopes = listScopes(definition.scopes or {definition.scope or "account"})
    if not next(scopes) or definition.synchronized == true then return false, "INVALID_LOCAL_SETTING_SCOPE" end
    if self.definitions[definition.id] then
        local old = self.definitions[definition.id]
        if old.module == definition.module then return true, "ALREADY_REGISTERED" end
        return false, "SETTING_ID_EXISTS"
    end
    local normalized = copy(definition)
    normalized.scopes = scopes
    normalized.scope = validScopes[definition.scope] and definition.scope or (scopes.account and "account" or scopes.character and "character" or scopes.guild and "guild" or "allGuilds")
    normalized.locality = "local"
    self.definitions[definition.id] = normalized
    return true
end

function Settings:GetDefinition(id)
    local definition = self.definitions[id]
    return definition and copy(definition) or nil
end

function Settings:GetDefinitions()
    local result = {}
    for _, definition in pairs(self.definitions) do result[#result+1] = copy(definition) end
    table.sort(result, function(a,b) return a.id < b.id end)
    return result
end

function Settings:GetSelectedScope(id)
    local definition = self.definitions[id]
    local store = root()
    if not definition or not store then return nil end
    local selected = store.selectedScopes[id]
    return selected and definition.scopes[selected] and selected or definition.scope
end

function Settings:SetSelectedScope(id, scope)
    local definition, store = self.definitions[id], root()
    if not definition or not store then return false, "UNKNOWN_SETTING" end
    if not definition.scopes[scope] then return false, "SCOPE_NOT_ALLOWED" end
    if scope == "guild" and not currentGuild() then return false, "NO_CURRENT_GUILD" end
    store.selectedScopes[id] = scope
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_LOCAL_SETTING_CHANGED", id, self:Get(id), scope) end
    return true
end

local function stored(store, id, scope, key)
    local bucket = store[scope]
    if scope == "character" then
        local character = key or currentCharacter()
        bucket = character and (bucket[character] or {}) or {}
    elseif scope == "guild" then
        local guild = key or currentGuild()
        bucket = guild and (bucket[guild] or {}) or {}
    end
    if type(bucket) == "table" then return bucket[id] end
    return nil
end

function Settings:GetStored(id, scope, key)
    local definition, store = self.definitions[id], root()
    if not definition or not store or not definition.scopes[scope] then return nil end
    return stored(store, id, scope, key)
end

function Settings:Get(id)
    local definition, store = self.definitions[id], root()
    if not definition then return nil, "UNKNOWN_SETTING" end
    if not store then return copy(definition.default), "DATABASE_NOT_INITIALIZED" end
    local function value(scope)
        if not definition.scopes[scope] then return nil end
        return stored(store, id, scope)
    end
    local result
    if definition.scopes.guild or definition.scopes.allGuilds then
        result = value("guild")
        if result == nil then result = value("allGuilds") end
    end
    if result == nil then result = value("character") end
    if result == nil then result = value("account") end
    if result == nil then result = copy(definition.default) end
    return copy(result)
end

function Settings:Set(id, value, scope, key)
    local definition, store = self.definitions[id], root()
    if not definition then return false, "UNKNOWN_SETTING" end
    scope = scope or self:GetSelectedScope(id)
    if not store then return false, "DATABASE_NOT_INITIALIZED" end
    if not definition.scopes[scope] then return false, "SCOPE_NOT_ALLOWED" end
    if scope == "guild" and not (key or currentGuild()) then return false, "NO_CURRENT_GUILD" end
    if scope == "character" and not (key or currentCharacter()) then return false, "NO_CURRENT_CHARACTER" end
    if type(definition.validate) == "function" then
        local ok, valid, normalized = pcall(definition.validate, value)
        if not ok or valid == false then return false, normalized or "INVALID_SETTING_VALUE" end
        if normalized ~= nil then value = normalized end
    elseif type(value) ~= type(definition.default) then
        return false, "INVALID_SETTING_VALUE"
    end
    local bucket = store[scope]
    if scope == "character" then local owner = key or currentCharacter(); bucket[owner] = type(bucket[owner]) == "table" and bucket[owner] or {}; bucket = bucket[owner] end
    if scope == "guild" then local owner = key or currentGuild(); bucket[owner] = type(bucket[owner]) == "table" and bucket[owner] or {}; bucket = bucket[owner] end
    local previous = bucket[id]
    if previous ~= nil and HolyStorm.Serializer then
        local previousText = HolyStorm.Serializer:Serialize(previous)
        local nextText = HolyStorm.Serializer:Serialize(value)
        if previousText ~= nil and previousText == nextText then return true, "UNCHANGED" end
    end
    bucket[id] = copy(value)
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_LOCAL_SETTING_CHANGED", id, copy(value), scope) end
    return true
end

function Settings:ImportLegacy(id, value, scope)
    if value == nil then return false, "NO_LEGACY_VALUE" end
    scope = scope or "account"
    if self:GetStored(id, scope) ~= nil then return false, "ALREADY_MIGRATED" end
    return self:Set(id, value, scope)
end

HolyStorm.Settings = Settings
