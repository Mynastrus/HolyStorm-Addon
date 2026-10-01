local root = (arg[0]:gsub("tools[/\\]test_core_version.lua$", "")) .. "LIVE/"
local addon
local metadataVersion

local locale = setmetatable({ CORE_DISPLAY_NAME = "Holy Storm", CORE_DESCRIPTION = "Core" }, { __index = function(_, key) return key end })
LibStub = function(name)
    if name == "AceLocale-3.0" then return { GetLocale = function() return locale end } end
    if name == "AceAddon-3.0" then
        return {
            NewAddon = function(_, name) addon = {}; return addon end,
            GetAddon = function() return addon end,
        }
    end
    error("Unexpected library: " .. tostring(name))
end

local function bootstrap(rawVersion)
    metadataVersion = rawVersion
    C_AddOns = { GetAddOnMetadata = function(name, key) assert(name == "Holy_Storm" and key == "Version"); return metadataVersion end }
    assert(loadfile(root .. "Holy_Storm/Core/Bootstrap/Bootstrap.lua"))("Holy_Storm")
    return addon
end

for _, sample in ipairs({
    { raw = "@project-version@", expected = "DEV" },
    { raw = "@file-version@", expected = "DEV" },
    { raw = "${project-version}", expected = "DEV" },
    { raw = "{{PROJECT_VERSION}}", expected = "DEV" },
    { raw = "%PROJECT_VERSION%", expected = "DEV" },
    { raw = "<project-version>", expected = "DEV" },
    { raw = nil, expected = "DEV" },
    { raw = "", expected = "DEV" },
    { raw = "   \t", expected = "DEV" },
    { raw = "5.9.0", expected = "5.9.0" },
    { raw = "5.10.0-rc.2+build.7", expected = "5.10.0-rc.2+build.7" },
    { raw = "v5.9.0", expected = "v5.9.0" },
    { raw = "release-candidate", expected = "release-candidate" },
}) do
    local current = bootstrap(sample.raw)
    assert(current.version == sample.expected, "metadata resolves to " .. sample.expected)
    assert(current:GetVersion() == sample.expected, "GetVersion returns the canonical resolved version")
    assert(current.metadata.version == sample.expected, "Core module metadata uses the canonical resolved version")
end

local current = bootstrap("@project-version@")
local utils = assert(loadfile(root .. "Holy_Storm/Core/Utils/Utils.lua"))
utils()
assert(current.Utils.CompareSemanticVersions("DEV", "5.9.0") == nil, "DEV is not treated as a semantic release version")
assert(current.Utils.CompareSemanticVersions("5.9.0", "5.9.0") == 0, "valid release version comparisons remain available")

local function read(path)
    local file = assert(io.open(root .. path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local footer = read("Holy_Storm_UI/UI/Framework/MainWindow.lua")
local roster = read("Holy_Storm_Guild/Guild.lua")
local libraries = read("Holy_Storm/Core/Infrastructure/Libraries.lua")
local sync = read("Holy_Storm/Sync/SyncManager.lua")
local commands = read("Holy_Storm/Core/Commands/Commands.lua")
local logs = read("Holy_Storm_UI/UI/Pages/Logs.lua")
assert(footer:find('string.format(L["STATUS_BAR_READY"], HolyStorm.version)', 1, true), "Footer consumes the canonical Core version field")
assert(roster:find('HolyStorm.Sync and HolyStorm.Sync:GetKnownVersion(stored.guid)', 1, true), "all Guild Roster versions come from the canonical Sync version store")
assert(not roster:find('HolyStorm.version', 1, true), "Guild Roster UI does not bypass the version store for the local player")
assert(libraries:find('tostring(HolyStorm.version)', 1, true), "LibDataBroker launcher consumes the canonical Core version")
assert(sync:find('{version=HolyStorm.version,sessionId=sessionId', 1, true) and sync:find('{version=HolyStorm.version,responseTo=data.sessionId', 1, true), "Sync Presence and replies consume the canonical Core version")
assert(commands:find('HolyStorm.version));printMessage', 1, true) and logs:find('HolyStorm.version,L["LOG_EXPORT_TIME"]', 1, true), "loaded and diagnostic version output consumes the canonical Core field")
assert(not footer:find("GetAddOnMetadata", 1, true) and not roster:find("GetAddOnMetadata", 1, true) and not sync:find("GetAddOnMetadata", 1, true), "runtime consumers do not read raw addon metadata")

print("Core runtime version normalization and consumer contract tests passed")
