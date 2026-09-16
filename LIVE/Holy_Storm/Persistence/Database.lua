local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Database = { version=addonVersion, areas = {}, initialized = false }
function Database:Initialize()
    self.initialized = false
    local legacy = type(HolyStormDB) == "table" and HolyStormDB.profiles == nil and HolyStorm.Utils.DeepCopy(HolyStormDB) or nil
    HolyStorm.db = LibStub("AceDB-3.0"):New("HolyStormDB", HolyStorm.Data.Schema.defaults, true)
    HS_Player_DB = type(HS_Player_DB) == "table" and HS_Player_DB or {}
    HS_GuildLog_DB = type(HS_GuildLog_DB) == "table" and HS_GuildLog_DB or { entries = {}, snapshot = nil }
    if legacy then
        if legacy.enabled ~= nil then HolyStorm.db.profile.enabled = legacy.enabled == true end
        if type(legacy.optionalModules) == "table" then HolyStorm.db.profile.optionalModules = HolyStorm.Utils.ApplyDefaults(legacy.optionalModules, HolyStorm.Data.Schema.defaults.profile.optionalModules) end
    end
    local ok, err = HolyStorm.Data.Migrations:Run(HolyStorm.db.global, HolyStorm.db.global.schemaVersion, legacy)
    if not ok then error("Holy Storm database: " .. tostring(err)) end
    self.initialized = true
end
function Database:IsInitialized() return self.initialized == true and type(HolyStorm.db) == "table" end
function Database:GetRoot(scope)
    if not self:IsInitialized() then return nil end
    if scope == "character" or scope == "char" then return HolyStorm.db.char end
    return HolyStorm.db[scope or "profile"]
end
function Database:Get(path, scope)
    local value = self:GetRoot(scope)
    if type(value) ~= "table" then return nil end
    for segment in string.gmatch(path or "", "[^%.]+") do if type(value) ~= "table" then return nil end; value = value[segment] end
    return value
end
function Database:Set(path, value, scope)
    local target, segments = self:GetRoot(scope), {}; for segment in string.gmatch(path or "", "[^%.]+") do segments[#segments + 1] = segment end
    if type(target) ~= "table" then return false,"DATABASE_NOT_INITIALIZED" end
    if #segments == 0 then return false end
    for index = 1, #segments - 1 do local key = segments[index]; target[key] = type(target[key]) == "table" and target[key] or {}; target = target[key] end
    local key = segments[#segments]; if target[key] == value then return false end; target[key] = value
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_CONFIG_CHANGED", path, value, scope or "profile") end; return true
end
function Database:RegisterArea(id, scope, defaults) if type(id) ~= "string" or not ({ global=true, profile=true, character=true })[scope] then return false end; self.areas[id] = { scope=scope, defaults=defaults or {} }; return true end
function Database:GetArea(id, guid)
    local area = self.areas[id]; if not area then error("Unknown data area: " .. tostring(id)) end
    if area.scope == "character" then
        guid = guid or UnitGUID("player"); if type(guid) ~= "string" then error("Character data needs a GUID") end
        local record = HolyStorm.Data.CharacterStore:GetOrCreate(guid); record[id] = HolyStorm.Utils.ApplyDefaults(record[id], area.defaults); return record[id]
    end
    local root = self:GetRoot(area.scope); root[id] = HolyStorm.Utils.ApplyDefaults(root[id], area.defaults); return root[id]
end
function Database:SetAreaValue(id, key, value, guid) local area = self:GetArea(id, guid); if area[key] == value then return false end; area[key] = value; HolyStorm.Events:Emit("HS_DATA_CHANGED", id, key, value, guid); return true end
HolyStorm.Database = Database
HolyStorm.DataManager = {
    RegisterArea=function(_,...) return Database:RegisterArea(...) end,
    GetArea=function(_,...) return Database:GetArea(...) end,
    Set=function(_,...) return Database:SetAreaValue(...) end,
}
HolyStorm.ConfigManager = {
    RegisterDefaults=function(_,scope,defaults) local root=Database:GetRoot(scope); HolyStorm.Utils.ApplyDefaults(root,defaults or {}); return true end,
    Get=function(_,...) return Database:Get(...) end,
    Set=function(_,...) return Database:Set(...) end,
}
