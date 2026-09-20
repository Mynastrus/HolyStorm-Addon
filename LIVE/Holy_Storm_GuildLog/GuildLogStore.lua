local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store = {}

function Store:Initialize()
    HS_GuildLog_DB = type(HS_GuildLog_DB) == "table" and HS_GuildLog_DB or {}
    HS_GuildLog_DB.entries = type(HS_GuildLog_DB.entries) == "table" and HS_GuildLog_DB.entries or {}
    HolyStorm.Database:RegisterDiagnosticSource("HS_GuildLog_DB",function()return HS_GuildLog_DB end)
    return HS_GuildLog_DB
end

function Store:GetDatabase()
    return self:Initialize()
end

function Store:Add(eventType, message)
    local entries = self:GetDatabase().entries
    table.insert(entries, 1, { timestamp=HolyStorm.Utils.Now(), eventType=eventType, message=message })
    while #entries > 1000 do table.remove(entries) end
    HolyStorm.Events:Emit("HS_GUILD_LOG_UPDATED", eventType)
end

function Store:SetSnapshot(snapshot)
    self:GetDatabase().snapshot = HolyStorm.Utils.DeepCopy(snapshot)
end

HolyStorm.Data.GuildLogStore = Store
