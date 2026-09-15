local addonVersion = "2.4.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
HolyStorm.Data.Schema = {
    fileVersion = addonVersion,
    version = 12,
    defaults = {
        profile = {
            enabled = true, debug = false,
            optionalModules = { GuildLog = true, GuildEvents = false, Equipment = true, Raids = true, MythicPlus = true, CharacterStats = true, Delves = true, Professions = false },
            window = { savePosition = false, saveSize = false },
            guildRoster = { showOffline = true, groupTwinks = true },
            logs = { autoScroll = true, level = "ALL", module = "ALL", category = "ALL", direction = "ALL", event = "ALL", search = "", maxEntries = 2000, columns = {} },
            taskManager = { historyLimit = 250, workflowHistoryLimit = 100, eventHistoryLimit = 300, triggerHistoryLimit = 20, columns = {}, filters = {} },
            filters = { localFilters = {}, active = {}, activeByContext = {}, combine = "AND" },
            rules = { localRules = {} },
            poi = { worldMapEnabled=true, minimapEnabled=true, worldMapSize=22, minimapSize=18, maxSynced=500, hidden={}, categoryVisible={}, targetVisible={} },
            positions = { share=false, display=true, worldMapEnabled=true, minimapEnabled=false, currentMapOnly=false, worldMapSize=24, minimapSize=18, markerStyle="CLASS" },
            chat = {
                enabled=true, playerEnrichment=true, classColors=true, playerTooltips=true,
                showMain=false, showRealName=false, links=true, urls=true,
                mentions={enabled=true, characterName=true, realName=false, sound="TELL_MESSAGE", cooldown=2.5, ownMessages=false},
                channels={GUILD=true,OFFICER=true,PARTY=true,PARTY_LEADER=true,RAID=true,RAID_LEADER=true,INSTANCE_CHAT=true,INSTANCE_CHAT_LEADER=true,WHISPER=true,WHISPER_INFORM=true,SAY=true,YELL=true},
            },
        },
        global = {
            schemaVersion = 0, installId = nil, localPlayerId = nil, localAccountUUID = nil,
            data = { guilds = {}, players = {}, characters = {}, characterOwners = {} },
            permissions = { groups = {}, roles = {}, assignments = {}, version = 1 },
            rules = { global = {}, version = 1 },
            filters = { global = {}, templates = {}, version = 1, demands = { quests = {}, achievements = {} } },
            policy = { version = 1, tombstones = { groups = {}, rules = {}, filters = {} } },
            permissionStates = {},
            content = { guilds = {}, legacyNews = {}, legacyReads = {}, schemaVersion = 1 },
            poi = { personal={}, guilds={}, sessions={}, schemaVersion=1 },
            achievements = { guilds={}, schemaVersion=1 },
            logs = { entries = {} },
            guildEvents = { snapshot = nil, unread = false },
        },
        char = { characters = {} },
    },
    characterFields = { name=true, realm=true, class=true, classFile=true, race=true, raceFile=true, sex=true, level=true, faction=true, guild=true, guildRank=true, guildRankIndex=true, equipment=true, itemLevel=true, raidLockouts=true, mythicPlus=true, professions=true, delves=true, stats=true, profile=true, addon=true, demands=true, lastSeen=true },
}
