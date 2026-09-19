local addonVersion = "2.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Logger = { version=addonVersion, levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }, threshold = 2, history = {}, paused=false, _schemaRegistered=false }
local _committing = false

local function validateLogEntry(entry)
    if type(entry) ~= "table" then return false end
    if type(entry.level) ~= "string" or type(entry.source) ~= "string" or type(entry.category) ~= "string" or type(entry.message) ~= "string" or type(entry.timestamp) ~= "number" then return false end
    if entry.context ~= nil and type(entry.context) ~= "table" then return false end
    return true
end

function Logger:Initialize(debugEnabled)
    self.threshold = debugEnabled and 1 or 2

    local DataManager = HolyStorm.DataManager
    if DataManager and not self._schemaRegistered then
        DataManager:RegisterSchema({
            id = "core-logs",
            owner = "Logger",
            version = 1,
            versionField = false,
            validate = function(data)
                if type(data) ~= "table" then return false, "INVALID_ROOT" end
                if data.entries ~= nil and type(data.entries) ~= "table" then return false, "INVALID_ENTRIES" end
                if data.entries then
                    for _, entry in ipairs(data.entries) do
                        if not validateLogEntry(entry) then return false, "INVALID_ENTRY" end
                    end
                end
                return true
            end,
            default = function() return { entries = {} } end,
            storage = { backend = "database", scope = "global", path = "logs" }
        })
        self._schemaRegistered = true
    end

    if self._schemaRegistered then
        local data, result = DataManager:Get("core-logs")
        if data and data.entries then
            self.history = data.entries
            local changed = false
            while #self.history > 2000 do table.remove(self.history, 1); changed = true end
            if changed then
                _committing = true
                DataManager:Update("core-logs", nil, function(draft)
                    draft.entries = draft.entries or {}
                    while #draft.entries > 2000 do table.remove(draft.entries, 1) end
                end)
                _committing = false
            end
        else
            self.history = {}
        end
    end
end

function Logger:SetLevel(level) if self.levels[level] then self.threshold = self.levels[level]; return true end; return false end

function Logger:Log(level, source, category, message, context, correlationId, ...)
    local numeric = self.levels[level]; if not numeric then return false end
    if message==nil then message,category=category,"general" end
    context=type(context)=="table"and context or nil;correlationId=correlationId or(context and(context.correlationId or context.transmissionId));local entry = { level=level, source=tostring(source or "Core"), category=tostring(category or "general"), message=tostring(message), context=HolyStorm.Utils.DeepCopy(context), correlationId=correlationId, timestamp=HolyStorm.Utils.Now(),direction=context and context.direction,eventName=context and(context.eventName or context.event),transmissionId=context and context.transmissionId }

    table.insert(self.history, entry); if #self.history > 2000 then table.remove(self.history, 1) end
    if numeric >= self.threshold then print(string.format("|cff3fc7ebHoly Storm|r [%s/%s] %s", level, entry.source, entry.message)) end

    if self._schemaRegistered and not _committing then
        _committing = true
        local result = HolyStorm.DataManager:Update("core-logs", nil, function(draft)
            draft.entries = draft.entries or {}
            table.insert(draft.entries, entry)
            while #draft.entries > 2000 do table.remove(draft.entries, 1) end
        end)
        _committing = false
        if result and result.ok and type(result.value) == "table" and type(result.value.entries) == "table" then
            self.history = result.value.entries
        end
    end

    if HolyStorm.Events then HolyStorm.Events:Emit("HS_LOG_ADDED",entry) end
    return true
end

for _, level in ipairs({ "DEBUG", "INFO", "WARN", "ERROR" }) do Logger[level] = function(self,source,message,...) local ok,rendered=pcall(string.format,tostring(message),...);return self:Log(level,source,"general",ok and rendered or tostring(message),nil,nil) end end
function Logger:Write(level,source,category,message,context,correlationId) return self:Log(level,source,category,message,context,correlationId) end
function Logger:GetHistory() return HolyStorm.Utils.DeepCopy(self.history) end
function Logger:Clear()
    self.history={}
    if self._schemaRegistered and not _committing then
        _committing = true
        local result = HolyStorm.DataManager:Commit("core-logs", nil, { entries = {} })
        _committing = false
        if result and result.ok and result.value and result.value.entries then
            self.history = result.value.entries
        end
    end
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_LOG_CLEARED") end
end
HolyStorm.Logger = Logger
