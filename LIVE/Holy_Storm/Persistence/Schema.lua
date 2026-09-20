local addonVersion = "2.4.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
HolyStorm.Data.Schema = {
    fileVersion = addonVersion,
    version = 12,
    defaults = {
        profile = {
            enabled = true, debug = false,
            optionalModules = {},
            window = { savePosition = false, saveSize = false },
            logs = { autoScroll = true, level = "ALL", module = "ALL", category = "ALL", direction = "ALL", event = "ALL", search = "", maxEntries = 2000, columns = {} },
            taskManager = { historyLimit = 250, workflowHistoryLimit = 100, eventHistoryLimit = 300, triggerHistoryLimit = 20, columns = {}, filters = {} },
            filters = { localFilters = {}, active = {}, activeByContext = {}, combine = "AND" },
            rules = { localRules = {} },
        },
        global = {
            schemaVersion = 0, installId = nil, localPlayerId = nil, localAccountUUID = nil,
            data = { guilds = {}, players = {}, characters = {}, characterOwners = {} },
            permissions = { groups = {}, roles = {}, assignments = {}, version = 1 },
            rules = { global = {}, version = 1 },
            filters = { global = {}, templates = {}, version = 1, demands = { quests = {}, achievements = {} } },
            policy = { version = 1, tombstones = { groups = {}, rules = {}, filters = {} } },
            permissionStates = {},
            logs = { entries = {} },
        },
        char = { characters = {} },
    },
}
