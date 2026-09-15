local addonVersion = "2.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Logger = { version=addonVersion, levels = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }, threshold = 2, history = {}, paused=false }
function Logger:Initialize(debugEnabled)
    self.threshold = debugEnabled and 1 or 2
    local root=HolyStorm.db.global.logs; root.entries=type(root.entries)=="table" and root.entries or {}; self.history=root.entries
    while #self.history>2000 do table.remove(self.history,1) end
end
function Logger:SetLevel(level) if self.levels[level] then self.threshold = self.levels[level]; return true end; return false end
function Logger:Log(level, source, category, message, context, correlationId, ...)
    local numeric = self.levels[level]; if not numeric then return false end
    if message==nil then message,category=category,"general" end
    context=type(context)=="table"and context or nil;correlationId=correlationId or(context and(context.correlationId or context.transmissionId));local entry = { level=level, source=tostring(source or "Core"), category=tostring(category or "general"), message=tostring(message), context=HolyStorm.Utils.DeepCopy(context), correlationId=correlationId, timestamp=HolyStorm.Utils.Now(),direction=context and context.direction,eventName=context and(context.eventName or context.event),transmissionId=context and context.transmissionId }
    table.insert(self.history, entry); if #self.history > 2000 then table.remove(self.history, 1) end
    if numeric >= self.threshold then print(string.format("|cff3fc7ebHoly Storm|r [%s/%s] %s", level, entry.source, entry.message)) end
    if HolyStorm.Events then HolyStorm.Events:Emit("HS_LOG_ADDED",entry) end
    return true
end
for _, level in ipairs({ "DEBUG", "INFO", "WARN", "ERROR" }) do Logger[level] = function(self,source,message,...) local ok,rendered=pcall(string.format,tostring(message),...);return self:Log(level,source,"general",ok and rendered or tostring(message),nil,nil) end end
function Logger:Write(level,source,category,message,context,correlationId) return self:Log(level,source,category,message,context,correlationId) end
function Logger:GetHistory() return HolyStorm.Utils.DeepCopy(self.history) end
function Logger:Clear() self.history={}; HolyStorm.db.global.logs.entries=self.history; if HolyStorm.Events then HolyStorm.Events:Emit("HS_LOG_CLEARED") end end
HolyStorm.Logger = Logger
