local root = "LIVE/Holy_Storm/"
local clock = 1000
unpack = unpack or table.unpack
local function copy(value, seen)
    if type(value) ~= "table" then return value end; seen = seen or {}; if seen[value] then return seen[value] end; local out = {}; seen[value] =
        out; for key, child in pairs(value) do out[copy(key, seen)] = copy(child, seen) end; return out
end

local HolyStorm = {
    version = "5.3.2",
    db = { global = { logs = { entries = {} } } },
    Utils = {
        DeepCopy = copy,
        Now = function()
            clock = clock + 1; return clock
        end
    },
    Data = { PersistenceBinding = "database" },
    Events = { Emit = function() end }
}
HolyStormDB = {}
HS_Player_DB = {}
HS_GuildLog_DB = {}

function LibStub(name) if name == "AceAddon-3.0" then return { GetAddon = function() return HolyStorm end } end end

assert(loadfile(root .. "Persistence/Schema.lua"))()
-- Needs Database for DataManager
local Database = {
    GetRoot = function(self) return HolyStorm.db end,
    SetAreaValue = function(self, binding, scope, path, value)
        HolyStorm.db[scope][path] = value
    end,
    GetArea = function(self, binding, scope, path)
        HolyStorm.db[scope] = HolyStorm.db[scope] or {}
        HolyStorm.db[scope][path] = type(HolyStorm.db[scope][path]) == "table" and HolyStorm.db[scope][path] or {}
        return HolyStorm.db[scope][path]
    end
}
HolyStorm.Database = Database
assert(loadfile(root .. "Persistence/Database.lua"))()
HolyStorm.Database.initialized = true
local DataManager = HolyStorm.DataManager

assert(loadfile(root .. "Core/Logging/Logger.lua"))()
local Logger = HolyStorm.Logger

local pass = 0

-- 1. Legacy Data without schema version is loaded properly on init
HolyStorm.db.global.logs = {
    entries = {
        { level = "INFO", source = "Legacy", category = "general", message = "Old", timestamp = 123 }
    }
}
-- Init
Logger:Initialize(false)
assert(Logger._schemaRegistered == true, "core-logs schema should be registered")
pass = pass + 1

local hInit = Logger:GetHistory()
assert(#hInit == 1, "Legacy unversioned data loaded on init")
assert(hInit[1].message == "Old", "Legacy content preserved")

-- 1 (formerly Empty db tests)
Logger:Clear()
assert(#Logger:GetHistory() == 0, "Empty DB should yield empty history")
pass = pass + 1

-- 2. Log single entry
local ok = Logger:Write("INFO", "Test", "general", "First message")
assert(ok, "Log should return true")
local h1 = Logger:GetHistory()
assert(#h1 == 1, "History length should be 1")
assert(h1[1].message == "First message", "Message should match")
assert(h1[1].level == "INFO", "Level should match")
pass = pass + 1

-- 3. Log mutiple entries, order preserved
Logger:Write("WARN", "Test2", "general", "Second message")
Logger:Write("ERROR", "Test3", "general", "Third message")
local h2 = Logger:GetHistory()
assert(#h2 == 3, "History length should be 3")
assert(h2[1].message == "First message", "Oldest first")
assert(h2[3].message == "Third message", "Newest last")
pass = pass + 1

-- 4. Safe Read - mutation does not affect persistence
local h3 = Logger:GetHistory()
h3[1].message = "HACKED"
h3[1].level = "CRITICAL"
table.remove(h3, 2)
local h4 = Logger:GetHistory()
assert(h4[1].message == "First message", "Safe read should project deep copy")
assert(h4[1].level == "INFO", "Safe read should project deep copy")
assert(#h4 == 3, "Safe read should not allow deletion of data")
pass = pass + 1

-- 5. Missing optional fields
Logger:Log("DEBUG", "Test", nil, "No category") -- defaults to general, nil context
local h5 = Logger:GetHistory()
assert(h5[4].category == "general", "Defaults applied")
assert(h5[4].context == nil, "Context is nil")
pass = pass + 1

-- 6. Nested context safe copied
local nested = { foo = "bar", deeply = { nested = true } }
Logger:Write("INFO", "CtxTest", "cat", "Msg", nested)
local h6 = Logger:GetHistory()
assert(h6[5].context.deeply.nested == true, "nested ctx exists")
-- Mutate local context
nested.foo = "mutated"
nested.deeply.nested = false
local h7 = Logger:GetHistory()
assert(h7[5].context.foo == "bar", "Internal context should be a deep copy on write")
assert(h7[5].context.deeply.nested == true, "Internal context deep copy depth check")
pass = pass + 1

-- 7. Retention limit
HolyStorm.db = { global = { logs = { entries = {} } } }
Logger._schemaRegistered = false
Logger:Initialize(false)
for i = 1, 2005 do
    Logger:Write("DEBUG", "Spam", "general", "Msg " .. i)
end
local h8 = Logger:GetHistory()
assert(#h8 == 2000, "Retention limit exactly 2000")
assert(h8[1].message == "Msg 6", "Oldest entries evicted (1-5 gone)")
assert(h8[2000].message == "Msg 2005", "Newest entry remains")
pass = pass + 1

-- 8. Valid structure after Clear
Logger:Clear()
local h9 = Logger:GetHistory()
assert(#h9 == 0, "Clear should empty history")
-- verify local db directly, DataManager mock sometimes returns nil if no defaults are set
local rawLogs = HolyStorm.db.global.logs
assert(rawLogs.entries and #rawLogs.entries == 0, "storage root entries cleared")
pass = pass + 1

-- 9. (Moved to Test 1 for clean init testing)
pass = pass + 1

-- 10. Recursion Guard: DataManager validation error prevents write but runtime log works
local h11_before = #Logger:GetHistory()

-- Simulate being halfway inside a DataManager commit by using a mock mutator that writes a log
HolyStorm.DataManager:Update("core-logs", nil, function(draft)
    -- when failing, simulate datamanager emitting a log itself
    Logger:Write("ERROR", "DataManager", "persistence", "Validation failed inside commit!")
    error("FORCED_FAIL")
end)

local h11 = Logger:GetHistory()
assert(#h11 == h11_before + 2, "Runtime buffer holds nested error and DataManager failure")
assert(h11[h11_before + 1].message == "Validation failed inside commit!", "Nested error remains in buffer")
assert(h11[h11_before + 2].message == "DataManager operation failed", "DataManager failure remains in buffer")

-- now log something normal
local okLog = Logger:Write("INFO", "Normal", "foo", "Normal message")
assert(okLog, "Log API should return true")
local h12 = Logger:GetHistory()
assert(#h12 == h11_before + 3, "Recovery message added to runtime buffer")
pass = pass + 1

print(string.format("Core-Logs Schema, Migration, Safe Read, Retention, Recursion Guard tests passed (%d/10 suites)",
    pass))
