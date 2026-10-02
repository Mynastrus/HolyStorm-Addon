-- Offline regression coverage for GuildLog's structured store, integrations,
-- reconciliation, permissions, filtering, export and bounded performance.
local clock = 1800000000
local selectedLocale = "enUS"
local locales = { Holy_Storm_GuildLog = {} }
local listeners, taskTypes, queuedTasks, commands, publications = {}, {}, {}, {}, {}
local db = { global = {} }
local officerPermission, absencePermission = true, true
local openRequests = 0
local guild = { id = "guild-test", roster = {} }

function time(value) return os.time(value) end
function date(format, value) return os.date(format, value) end
function UnitGUID(unit) return unit == "player" and "Player-Local" or nil end
function IsInGuild() return true end
C_GuildInfo = { CanViewOfficerNote = function() return officerPermission end }
RAID_CLASS_COLORS = {}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}; if seen[value] then return seen[value] end
    local result = {}; seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local HolyStorm = {
    Utils = { DeepCopy = copy, Now = function() clock = clock + 1; return clock end, Trim = function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end },
    Data = {
        GuildStore = { GetCurrent = function() return guild end, Get = function(_, id) return id == guild.id and guild or nil end },
        CharacterStore = { Get = function() return nil end },
    },
    Events = {
        Emit = function(_, event, ...)
            for _, callback in pairs(listeners[event] or {}) do callback(event, ...) end
        end,
        Register = function(_, event, owner, callback)
            listeners[event] = listeners[event] or {}; listeners[event][owner] = callback
        end,
        UnregisterOwner = function(_, owner)
            for _, callbacks in pairs(listeners) do callbacks[owner] = nil end
        end,
    },
    Logger = { Write = function() end },
    Tasks = {
        RegisterTaskType = function(_, id, definition) taskTypes[id] = definition; return true end,
        GetTaskType = function(_, id) return taskTypes[id] end,
        Queue = function(_, id, options)
            local meta = options and options.metadata or {}
            local key = id .. "\031" .. tostring(options and options.mergeKey or meta.guildId or #queuedTasks + 1)
            queuedTasks[key] = { registryId = id, metadata = copy(meta), options = copy(options) }
            return { uniqueId = key }
        end,
        ScheduleRecurring = function(_, id, interval, callback) taskTypes[id] = { interval = interval, callback = callback }; return true end,
        CancelRecurring = function() return true end,
        GetLiveTasks = function() return {} end,
        Cancel = function() return true end,
    },
    Sync = {
        Publish = function(_, domain, objectId, reason) publications[#publications + 1] = { domain = domain, objectId = objectId, reason = reason }; return true end,
        RegisterDomain = function(self, id, definition) self.domains = self.domains or {}; self.domains[id] = definition; return true end,
        UnregisterDomain = function(self, id) self.domains[id] = nil; return true end,
    },
    Commands = {
        RegisterSubcommand = function(_, id, definition) commands[id] = definition; return true end,
        UnregisterSubcommand = function(_, id) commands[id] = nil; return true end,
        PrintUserMessage = function() end,
    },
    GuildManagement = {
        UI = nil,
        GetGuildId = function() return guild.id end,
        GetAccountUUID = function(_, character) return "account:" .. tostring(character) end,
        Can = function(_, permission)
            if permission == "guild-absences-view" then return absencePermission end
            if permission == "officer-notes-view" then return officerPermission end
            return true
        end,
        Open = function(_, feature) openRequests = openRequests + 1; return feature ~= nil end,
    },
}

HolyStorm.DataManager = {
    RegisterSchema = function(_, definition) HolyStorm.DataManager.schema = definition; return true end,
    GetOwnedRoot = function(_, schemaId, owner)
        assert(schemaId == "guild-log" and owner == "GuildLogStore")
        if not db.global.guildLog then db.global.guildLog = HolyStorm.DataManager.schema.default() end
        return db.global.guildLog
    end,
}
function HolyStorm:RegisterModule(metadata, factory)
    assert(metadata.id == "guildLog"); self.moduleMetadata = metadata
    local module = {}; factory(module); self.GuildLog = module; return module
end
function HolyStorm:ApplyModuleMetadata() end
function HolyStorm:GetModule(id) return id == "Options" and self.Options or nil end
function HolyStorm:RegisterCapability(_, id, callback) self.capabilities = self.capabilities or {}; self.capabilities[id] = callback; return true end
function HolyStorm:UnregisterCapability(_, id) self.capabilities[id] = nil end

function LibStub(name)
    if name == "AceAddon-3.0" then return { GetAddon = function() return HolyStorm end } end
    if name == "AceLocale-3.0" then
        return {
            NewLocale = function(_, namespace, locale, default)
                locales[namespace] = locales[namespace] or {}; locales[namespace][locale] = locales[namespace][locale] or {}
                if default or locale == selectedLocale then return locales[namespace][locale] end
            end,
            GetLocale = function(_, namespace) return locales[namespace] and locales[namespace][selectedLocale] or {} end,
        }
    end
end

assert(loadfile("LIVE/Holy_Storm_GuildLog/Locales/enUS.lua"))()
selectedLocale = "deDE"; assert(loadfile("LIVE/Holy_Storm_GuildLog/Locales/deDE.lua"))(); selectedLocale = "enUS"
assert(loadfile("LIVE/Holy_Storm_GuildLog/GuildLogStore.lua"))()
assert(HolyStorm.Data.GuildLogStore:Initialize())
assert(loadfile("LIVE/Holy_Storm_GuildLog/GuildLogUI.lua"))()
assert(loadfile("LIVE/Holy_Storm_GuildLog/GuildLog.lua"))()
local Store, GuildLog, UI = HolyStorm.Data.GuildLogStore, HolyStorm.GuildLog, HolyStorm.GuildLogUI
GuildLog:OnInitialize(); GuildLog:OnEnable()

local passed = 0
local function test(name, callback)
    local ok, reason = pcall(callback)
    if not ok then error("GuildLog regression failed [" .. name .. "]: " .. tostring(reason), 0) end
    passed = passed + 1
end
local function event(kind, subject, timestamp, data, extra)
    local result = { type = kind, timestamp = timestamp or clock, timestampSource = "SERVER_EVENT", resolutionState = "AUTHORITATIVE", subject = { guid = subject, name = subject }, data = data or {}, provenance = { kind = "MODULE_EVENT", source = "test" } }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end
local function list(guildId) return Store:List(guildId or guild.id) end
local function countType(rows, kind)
    local count = 0; for _, row in ipairs(rows) do if row.type == kind then count = count + 1 end end; return count
end

test("module contract and isolated persistence", function()
    assert(HolyStorm.moduleMetadata.id == "guildLog")
    assert(#HolyStorm.moduleMetadata.dependencies == 1 and HolyStorm.moduleMetadata.dependencies[1] == "core")
    assert(HolyStorm.Achievements == nil and HolyStorm.Calendar == nil, "producer add-ons must remain optional")
    assert(Store.root == db.global.guildLog and Store.root.guilds)
    assert(HolyStorm.DataManager.schema.storage.path[1] == "guildLog")
    assert(not HolyStorm.moduleMetadata.permissions[1], "ordinary GuildLog reading needs no synthetic permission")
end)

test("retention settings register through the optional shared Options module", function()
    local tabs = {}
    HolyStorm.Options = { RegisterOptionsTab = function(_, id, definition) tabs[id] = definition; return true end }
    HolyStorm.Events:Emit("HS_MODULE_AVAILABILITY_CHANGED", "Options", true, "lifecycle")
    local retention = assert(tabs.guildLog.args.retention)
    local maxEntries = retention.args.maxEntries
    local maxAgeDays = retention.args.maxAgeDays
    assert(maxEntries.get() == 5000 and maxAgeDays.get() == 730)
    maxEntries.set(nil, 6100); maxAgeDays.set(nil, 900)
    assert(Store:GetRetention().maxEntries == 6100 and Store:GetRetention().maxAgeSeconds == 900 * 86400)
end)

test("join, leave, promotion, demotion and level-up", function()
    assert(Store:Submit(guild.id, event("GUILD_JOINED", "joiner")))
    assert(Store:Submit(guild.id, event("GUILD_LEFT", "leaver")))
    assert(Store:Submit(guild.id, event("RANK_CHANGED", "promoted", clock, { oldRank = "Member", newRank = "Officer", direction = "PROMOTION" })))
    assert(Store:Submit(guild.id, event("RANK_CHANGED", "demoted", clock + 1, { oldRank = "Officer", newRank = "Member", direction = "DEMOTION" })))
    assert(Store:Submit(guild.id, event("RANK_CHANGED", "unknown-rank", clock + 2, { oldRank = "Rank A", newRank = "Rank C" })))
    assert(Store:Submit(guild.id, event("LEVEL_UP", "leveler", clock, { oldLevel = 69, newLevel = 70 })))
    local rows = list()
    assert(countType(rows, "GUILD_JOINED") == 1 and countType(rows, "GUILD_LEFT") == 1)
    assert(countType(rows, "RANK_CHANGED") == 3 and countType(rows, "LEVEL_UP") == 1)
    assert(GuildLog:GetCategory(rows[1]) ~= nil)
    for _, row in ipairs(rows) do if row.subject.guid == "unknown-rank" then assert(GuildLog:GetCategory(row) == "rank" and GuildLog:FormatEvent(row, false):find("changed rank", 1, true)) end end
    for _, row in ipairs(rows) do if row.type == "GUILD_JOINED" and row.subject.guid == "joiner" then assert(row.originGuid == "Player-Local" and row.recordedByGuid == "Player-Local") end end
end)

test("note changes store hashes, not note text; officer visibility gates reads and writes", function()
    assert(Store:Submit(guild.id, event("PUBLIC_NOTE_CHANGED", "noted", clock, { oldValueHash = "oldhash", newValueHash = "newhash" })))
    local noteTime = math.floor(clock / 300) * 300 + 299
    local function reconstructedNote(timestamp, from, to)
        return event("PUBLIC_NOTE_CHANGED", "note-reconstructed", timestamp, { oldValueHash = "before", newValueHash = "after" }, {
            timestampSource = "ROSTER_DELTA_CAPTURE", resolutionState = "RECONSTRUCTED",
            provenance = { kind = "ROSTER_DELTA", source = "note-test", observation = { from = from, to = to } },
        })
    end
    assert(Store:Submit(guild.id, reconstructedNote(noteTime, noteTime - 20, noteTime + 5)))
    assert(Store:Submit(guild.id, reconstructedNote(noteTime + 2, noteTime - 10, noteTime + 10)))
    local note = event("OFFICER_NOTE_CHANGED", "officer-noted", clock, { oldValueHash = "secret-old", newValueHash = "secret-new" })
    officerPermission = true; assert(Store:Submit(guild.id, note))
    officerPermission = false
    assert(countType(list(), "OFFICER_NOTE_CHANGED") == 0, "officer note event hidden from an unauthorized viewer")
    assert(Store:GetMetadata(Store:_NewEvent(guild.id, note, GuildLog:GetEventType("OFFICER_NOTE_CHANGED")).eventId) == nil, "officer note metadata is never synced")
    assert(not Store:Submit(guild.id, event("OFFICER_NOTE_CHANGED", "blocked", clock, { oldValueHash = "x", newValueHash = "y" })), "unauthorized sensitive event submission rejected")
    officerPermission = true
    assert(countType(list(), "OFFICER_NOTE_CHANGED") == 1)
    local public
    local reconstructedCount = 0
    for _, row in ipairs(list()) do if row.type == "PUBLIC_NOTE_CHANGED" then public = row end end
    assert(public and not tostring(public.data.oldValueHash):find("note text", 1, true))
    for _, row in ipairs(list()) do if row.subject.guid == "note-reconstructed" and row.type == "PUBLIC_NOTE_CHANGED" then reconstructedCount = reconstructedCount + 1 end end
    assert(reconstructedCount == 1, "note changes from overlapping roster observations deduplicate across timestamp buckets")
    local sync = HolyStorm.Sync.domains.guildLog
    assert(sync.getRecipients(Store:GetMetadata(public.eventId)) == nil, "normal events use the guild broadcast route")
end)

test("achievement event producer", function()
    guild.roster.achiever = { name = "Guild Achiever" }
    assert(GuildLog:ConsumeAchievementAwards({ achievementID = 777, achievementName = "Guild Triumph", awardInstanceID = "award-1", awardedAt = clock, awards = { { status = "AWARDED", characterUUID = "achiever", awardedBy = "leader", awardID = "award-row-1", awardedAt = clock }, { status = "AWARDED", characterUUID = "outsider", awardedBy = "leader", awardID = "award-row-2", awardedAt = clock } } }))
    local found
    for _, row in ipairs(list()) do if row.type == "ACHIEVEMENT_EARNED" and row.subject.guid == "achiever" then found = row end end
    assert(found and found.data.achievementName == "Guild Triumph" and found.actor.guid == "leader")
    assert(countType(list(), "ACHIEVEMENT_EARNED") == 1, "only current guild members become guild history events")
end)

test("absence event uses creation timestamp and detail range", function()
    local createdAt, startAt, endAt = clock, clock + 86400, clock + 172800
    HolyStorm.Events:Emit("HS_GUILD_ABSENCE_CREATED", "absence-1", { absenceId = "absence-1", ownerCharacterUUID = "away", createdByCharacterUUID = "manager", createdAt = createdAt, startAt = startAt, endAt = endAt, revision = 1, title = "Away" })
    local found
    for _, row in ipairs(list()) do if row.type == "ABSENCE_CREATED" then found = row end end
    assert(found and found.timestamp == createdAt and found.data.startAt == startAt and found.data.endAt == endAt)
    assert(found.requiredPermission == "guild-absences-view")
    local domain = HolyStorm.Sync.domains.guildLog
    assert(domain.getMetadata(found.eventId), "permitted absence has per-event metadata for targeted sync")
    guild.roster.allowed = { name = "Allowed-Realm", online = true }
    local recipients = domain.getRecipients(domain.getMetadata(found.eventId))
    assert(#recipients == 1 and recipients[1].guid == "allowed")
    assert(domain.canShare(domain.getMetadata(found.eventId), "recipient", "Member-Realm", "offer"))
    absencePermission = false
    assert(not domain.canShare(domain.getMetadata(found.eventId), "recipient", "Member-Realm", "offer"))
    absencePermission = true
end)

test("roster baseline and idempotent join/leave/rank/level/note deltas", function()
    guild.roster = { ["stay"] = { name = "Stay", rank = "Member", rankIndex = 3, level = 69, note = "old", officerNote = "old officer" }, ["gone"] = { name = "Gone", rank = "Member", rankIndex = 3, level = 70, note = "", officerNote = "" } }
    officerPermission = true
    local first = { capturedAt = clock, members = {
        stay = { name = "Stay", rank = "Member", rankIndex = 3, level = 69, publicNoteHash = "p-old", officerNoteHash = "o-old" },
        gone = { name = "Gone", rank = "Member", rankIndex = 3, level = 70, publicNoteHash = "", officerNoteHash = "" },
    } }
    assert(GuildLog:ScanRoster(guild.id, first))
    local second = { capturedAt = clock + 100, members = {
        stay = { name = "Stay", rank = "Officer", rankIndex = 1, level = 70, publicNoteHash = "p-new", officerNoteHash = "o-new" },
        fresh = { name = "Fresh", rank = "Member", rankIndex = 3, level = 60, publicNoteHash = "", officerNoteHash = "" },
    } }
    assert(GuildLog:ScanRoster(guild.id, second))
    local before = list()
    assert(countType(before, "GUILD_JOINED") == 2 and countType(before, "GUILD_LEFT") == 2)
    assert(countType(before, "RANK_CHANGED") == 4 and countType(before, "LEVEL_UP") >= 2)
    assert(countType(before, "PUBLIC_NOTE_CHANGED") == 3 and countType(before, "OFFICER_NOTE_CHANGED") == 2)
    local reconstructed
    for _, row in ipairs(before) do if row.type == "RANK_CHANGED" and row.subject.guid == "stay" then reconstructed = row end end
    assert(reconstructed and reconstructed.resolutionState == "RECONSTRUCTED" and reconstructed.timestampSource == "ROSTER_DELTA_CAPTURE")
    assert(reconstructed.timestamp == second.capturedAt and reconstructed.provenance.observation.from == first.capturedAt)
    assert(GuildLog:ScanRoster(guild.id, second))
    assert(#list() == #before, "repeated roster refresh creates no duplicate events")
    assert(Store:GetRosterSnapshot(guild.id).capturedAt == second.capturedAt)
end)

test("reconstructed transition upgrades to authoritative event", function()
    local from, to = clock - 10, clock + 10
    local reconstructed = event("RANK_CHANGED", "merge-subject", to, { oldRank = "A", newRank = "C", direction = "DEMOTION" }, {
        timestampSource = "ROSTER_DELTA_CAPTURE", resolutionState = "RECONSTRUCTED",
        provenance = { kind = "ROSTER_DELTA", source = "test-snapshot", observation = { from = from, to = to } },
    })
    assert(Store:Submit(guild.id, reconstructed))
    local oldId
    for _, row in ipairs(list()) do if row.subject.guid == "merge-subject" and row.type == "RANK_CHANGED" then oldId = row.eventId end end
    assert(oldId)
    local direct = event("RANK_CHANGED", "merge-subject", clock, { oldRank = "A", newRank = "C", direction = "DEMOTION" }, { actor = { guid = "rank-author", name = "Rank Author" } })
    assert(Store:Submit(guild.id, direct))
    local rows, matches = list(), 0
    for _, row in ipairs(rows) do if row.subject.guid == "merge-subject" and row.type == "RANK_CHANGED" then matches = matches + 1; assert(row.resolutionState == "AUTHORITATIVE" and row.actor.guid == "rank-author") end end
    assert(matches == 1 and Store:GetEvent(guild.id, oldId).resolutionState == "AUTHORITATIVE")
end)

test("A-to-C reconstruction resolves into observed A-to-B and B-to-C", function()
    local from, to = clock - 20, clock + 20
    local inferred = event("RANK_CHANGED", "chain-subject", clock, { oldRank = "A", newRank = "C", direction = "DEMOTION" }, {
        timestampSource = "ROSTER_DELTA_CAPTURE", resolutionState = "RECONSTRUCTED",
        provenance = { kind = "ROSTER_DELTA", source = "chain-test", observation = { from = from, to = to } },
    })
    assert(Store:Submit(guild.id, inferred)); local inferredId
    for _, row in ipairs(list()) do if row.subject.guid == "chain-subject" then inferredId = row.eventId end end
    assert(inferredId)
    assert(Store:Submit(guild.id, event("RANK_CHANGED", "chain-subject", clock + 1, { oldRank = "A", newRank = "B", direction = "DEMOTION" }, { actor = { guid = "first-ranker" } })))
    assert(Store:Submit(guild.id, event("RANK_CHANGED", "chain-subject", clock + 2, { oldRank = "B", newRank = "C", direction = "DEMOTION" }, { actor = { guid = "second-ranker" } })))
    local replacementCount = 0
    for _, row in ipairs(list()) do if row.subject.guid == "chain-subject" then replacementCount = replacementCount + 1; assert(row.resolutionState == "AUTHORITATIVE") end end
    assert(replacementCount == 2 and Store:GetEvent(guild.id, inferredId).resolutionState == "SUPERSEDED")
end)

test("cross-client level observations deduplicate; per-event import is idempotent", function()
    local one = event("LEVEL_UP", "shared-level", clock, { oldLevel = 79, newLevel = 80 }, { actor = { guid = "client-one" } })
    local two = event("LEVEL_UP", "shared-level", clock + 240, { oldLevel = 79, newLevel = 80 }, { actor = { guid = "client-two" } })
    assert(Store:Submit(guild.id, one)); assert(Store:Submit(guild.id, two))
    local matches = 0; for _, row in ipairs(list()) do if row.type == "LEVEL_UP" and row.subject.guid == "shared-level" then matches = matches + 1 end end
    assert(matches == 1)
    local payload = assert(Store:_NewEvent(guild.id, event("GUILD_JOINED", "sync-subject", clock, {}, { actor = { guid = "sync-owner" } }), GuildLog:GetEventType("GUILD_JOINED")))
    local meta = { objectId = payload.eventId, owner = payload.originGuid, guildId = guild.id, revisionID = payload.revisionId, version = 1, updatedAt = payload.updatedAt }
    local domain = HolyStorm.Sync.domains.guildLog
    assert(domain.validate(payload, meta, payload.eventId))
    assert(Store:Import(payload.eventId, copy(payload), meta))
    local ok, result = Store:Import(payload.eventId, copy(payload), meta)
    assert(ok and result == "NOOP")
    local syncMatches = 0; for _, row in ipairs(list()) do if row.type == "GUILD_JOINED" and row.subject.guid == "sync-subject" then syncMatches = syncMatches + 1 end end
    assert(syncMatches == 1)
end)

test("central commands use the same Guild Management open route", function()
    commands.guild.execute("log"); commands.glog.execute("")
    assert(openRequests == 2)
    assert(commands.guild.help == locales.Holy_Storm_GuildLog.enUS.COMMAND_GUILD_HELP)
end)

test("locale rendering is client-local and structured data stays unchanged", function()
    local row = event("GUILD_JOINED", "locale-subject", clock)
    local before = copy(row)
    selectedLocale = "deDE"; assert(loadfile("LIVE/Holy_Storm_GuildLog/GuildLog.lua"))()
    local german = HolyStorm.GuildLog
    assert(german:GetEventType("GUILD_JOINED"), "German GuildLog should register built-in event types")
    local renderedGerman = german:FormatEvent(row, false)
    selectedLocale = "enUS"; assert(loadfile("LIVE/Holy_Storm_GuildLog/GuildLog.lua"))()
    GuildLog = HolyStorm.GuildLog
    local renderedEnglish = GuildLog:FormatEvent(row, false)
    assert(renderedGerman:find("Gilde", 1, true) and renderedEnglish:find("guild", 1, true), renderedGerman .. " / " .. renderedEnglish)
    assert(row.type == before.type and row.timestamp == before.timestamp and row.data.newLevel == before.data.newLevel)
end)

test("search and date filters operate over derived structured text", function()
    local first = event("RANK_CHANGED", "filter-first", time({ year = 2026, month = 1, day = 10 }), { oldRank = "Member", newRank = "Officer", direction = "PROMOTION" })
    first.subject.name = "Mynastrus"
    local second = event("LEVEL_UP", "filter-second", time({ year = 2026, month = 2, day = 10 }), { oldLevel = 69, newLevel = 70 })
    UI.filters = { categories = { promotion = true }, state = "ALL", fromText = "2026-01-01", toText = "2026-01-31", actor = "", subject = "" }
    UI.sourceDirty, UI.filterDirty, UI.indexing = false, false, nil
    UI.search = { GetText = function() return "mynastrus" end }
    UI.sourceEvents = { first, second }
    UI.searchIndex = { GuildLog:BuildSearchText(first), GuildLog:BuildSearchText(second) }
    assert(UI:ApplyFilters(GuildLog))
    assert(#UI.filteredEvents == 1 and UI.filteredEvents[1].subject.guid == "filter-first")
    UI.filters.fromText = "2026-02-31"; assert(not UI:ApplyFilters(GuildLog) or #UI.filteredEvents == 0)
end)

test("filtered and full exports escape formats and strip WoW control strings", function()
    local ok = GuildLog:RegisterCategory("custom", "CATEGORY_OTHER", "7190b8"); assert(ok)
    ok = GuildLog:RegisterEventType({ id = "EXPORT_TEST", labelKey = "CATEGORY_OTHER", category = "custom", identityKey = function(value) return "export:" .. value.data.eventKey end, render = function() return '|cffff0000[Export]|r says "hello" & <script> |Hcharacter:guid|h[linked]|h |TInterface\\Icons\\INV_Misc_Note_01:16|t' end }); assert(ok)
    local exportEvent = event("EXPORT_TEST", "export-subject", clock, { eventKey = "one" })
    UI.frame, UI.sourceDirty = nil, true
    local capabilityExport = assert(UI:Export(GuildLog, "csv", { scope = "ALL" }))
    assert(capabilityExport:find("Guild joins", 1, true), "export capability queries persistent visible events without opening the page")
    UI.frame = {}
    UI.module, UI.sourceDirty, UI.filterDirty, UI.indexing = GuildLog, false, false, nil
    UI.sourceEvents, UI.filteredEvents = { exportEvent, event("GUILD_LEFT", "excluded", clock) }, { exportEvent }
    local filtered = assert(UI:Export(GuildLog, "csv", { scope = "FILTERED" }))
    local full = assert(UI:Export(GuildLog, "csv", { scope = "ALL" }))
    assert(select(2, filtered:gsub("\r\n", "")) == 1 and select(2, full:gsub("\r\n", "")) == 2)
    assert(filtered:find('""hello""', 1, true) and not filtered:find("|cffff", 1, true))
    local html = assert(UI:Export(GuildLog, "html", { scope = "FILTERED" }))
    assert(html:find("&lt;script&gt;", 1, true) and html:find("&amp;", 1, true) and not html:find("|Hcharacter", 1, true))
    local bbcode = assert(UI:Export(GuildLog, "bbcode", { scope = "FILTERED" }))
    assert(bbcode:find("&#91;Export&#93;", 1, true) and not bbcode:find("|TInterface", 1, true) and not bbcode:find("|cffff", 1, true))
    UI.frame = nil
end)

test("retention is bounded, deterministic, and persistent across store reinitialization", function()
    assert(Store:ConfigureRetention(100, 30 * 86400))
    local baseTimestamp = clock
    local inputs = {}
    for index = 1, 105 do inputs[index] = event("LEVEL_UP", "retention-" .. index, baseTimestamp + index, { newLevel = 60 }) end
    assert(Store:SubmitMany("guild-retention", inputs)); assert(Store:Prune("guild-retention"))
    local retained = Store:List("guild-retention")
    assert(#retained == 100 and not Store:GetEvent("guild-retention", "missing"))
    local firstTimestamp = math.huge; for _, row in ipairs(retained) do firstTimestamp = math.min(firstTimestamp, row.timestamp) end
    assert(firstTimestamp == baseTimestamp + 6, "oldest timestamps pruned first")
    local old = event("GUILD_JOINED", "expired", clock - 31 * 86400)
    local fresh = event("GUILD_LEFT", "kept", clock)
    assert(Store:SubmitMany("guild-retention-age", { old, fresh })); assert(Store:Prune("guild-retention-age"))
    assert(#Store:List("guild-retention-age") == 1 and Store:List("guild-retention-age")[1].subject.guid == "kept")
    local before = Store:GetEvent(guild.id, list()[1].eventId)
    Store.root = nil; assert(Store:Initialize())
    assert(Store:GetEvent(guild.id, before.eventId) ~= nil, "DataManager-owned state survives Store reload")
end)

test("5,000-event GuildLog query completes within the offline work budget", function()
    assert(Store:ConfigureRetention(6000, 730 * 86400))
    local inputs = {}
    for index = 1, 5000 do inputs[index] = event("LEVEL_UP", "synthetic-" .. index, clock + index, { oldLevel = 69, newLevel = 70 }) end
    local started = os.clock(); assert(Store:SubmitMany("guild-performance", inputs))
    local rows = Store:List("guild-performance")
    guild.id = "guild-performance"; UI.frame, UI.sourceDirty = nil, true
    local export = assert(UI:Export(GuildLog, "csv", { scope = "ALL" }))
    local elapsed = os.clock() - started
    assert(#rows == 5000 and export:find("synthetic-1", 1, true) and elapsed < 8, string.format("5,000 event query and CSV export took %.3f seconds", elapsed))
    guild.id = "guild-test"
end)

test("no raw SavedVariables or custom GuildLog transport path", function()
    local function read(path) local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value end
    local storeSource = read("LIVE/Holy_Storm_GuildLog/GuildLogStore.lua")
    local toc = read("LIVE/Holy_Storm_GuildLog/Holy_Storm_GuildLog.toc")
    local moduleSource = read("LIVE/Holy_Storm_GuildLog/GuildLog.lua")
    assert(not storeSource:find("HS_GuildLog_DB", 1, true) and not storeSource:find("SavedVariables", 1, true))
    assert(not toc:find("SavedVariables:", 1, true))
    assert(not moduleSource:find("SendCommMessage", 1, true) and not moduleSource:find("C_ChatInfo.SendAddonMessage", 1, true))
    assert(moduleSource:find('HolyStorm.Sync:RegisterDomain("guildLog"', 1, true))
end)

print(string.format("GuildLog structured event, permission, sync, UI, export and performance regressions passed (%d suites)", passed))
