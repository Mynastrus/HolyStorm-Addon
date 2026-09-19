-- Baseline guard for Phase 1. Existing legacy access remains allowlisted until
-- each owner is migrated; new files or additional raw accesses fail the test.
local allow = {
    ["LIVE/Holy_Storm/Core/Logging/Logger.lua"]={0,0,0,2},
    ["LIVE/Holy_Storm/Core/Permissions/FilterManager.lua"]={0,0,0,7},
    ["LIVE/Holy_Storm/Core/Permissions/RuleEngine.lua"]={0,0,0,2},
    ["LIVE/Holy_Storm/Core/Tasks/TaskManager.lua"]={0,0,0,3},
    ["LIVE/Holy_Storm/Core/Workflows/WorkflowManager.lua"]={0,0,0,1},
    ["LIVE/Holy_Storm/Modules/Characters/RuleDataProvider.lua"]={0,0,0,8},
    ["LIVE/Holy_Storm/Modules/Characters/TwinkCore.lua"]={0,0,0,4},
    ["LIVE/Holy_Storm/Modules/News/Content.lua"]={0,0,0,1},
    ["LIVE/Holy_Storm/Modules/POI/POIService.lua"]={0,0,0,4},
    ["LIVE/Holy_Storm/Modules/Positions/GuildPositions.lua"]={0,0,0,3},
    ["LIVE/Holy_Storm/Persistence/AchievementStore.lua"]={0,0,0,2},
    ["LIVE/Holy_Storm/Persistence/ContentStore.lua"]={0,0,0,2},
    ["LIVE/Holy_Storm/Persistence/Database.lua"]={4,6,6,8},
    ["LIVE/Holy_Storm/Persistence/GuildStore.lua"]={0,0,7,2},
    ["LIVE/Holy_Storm/Persistence/Migrations.lua"]={1,40,0,0},
    ["LIVE/Holy_Storm/Persistence/PlayerDataStore.lua"]={1,8,0,3},
    ["LIVE/Holy_Storm/Persistence/PlayerStore.lua"]={0,0,0,3},
    ["LIVE/Holy_Storm/Persistence/POIStore.lua"]={0,0,0,3},
    ["LIVE/Holy_Storm/UI/Pages/Logs.lua"]={0,0,0,4},
    ["LIVE/Holy_Storm/UI/Pages/Options.lua"]={0,0,0,1},
    ["LIVE/Holy_Storm/UI/Pages/SavedVariables.lua"]={2,1,1,0},
    ["LIVE/Holy_Storm/UI/Pages/TaskManager.lua"]={0,0,0,2},
    ["LIVE/Holy_Storm/UI/Pages/SavedVariablesLocales/deDE.lua"]={3,1,1,0},
    ["LIVE/Holy_Storm/UI/Pages/SavedVariablesLocales/enUS.lua"]={3,1,1,0},
}

local tokens = { "HolyStormDB", "HS_Player_DB", "HS_GuildLog_DB", "HolyStorm.db" }
local function countPlain(content, token)
    local count, start = 0, 1
    while true do
        local first, last = string.find(content, token, start, true)
        if not first then return count end
        count = count + 1
        start = last + 1
    end
end

local process = assert(io.popen('rg --files "LIVE/Holy_Storm" -g "*.lua"', "r"))
for path in process:lines() do
    path = path:gsub("\\", "/")
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    local baseline = allow[path]
    for index, token in ipairs(tokens) do
        local count = countPlain(content, token)
        local maximum = baseline and baseline[index] or 0
        assert(count <= maximum, string.format("new raw persistence access: %s contains %d x %s (allowed %d)", path, count, token, maximum))
    end
end
assert(process:close(), "rg file enumeration failed")

print("Persistence raw-access boundary baseline passed")
