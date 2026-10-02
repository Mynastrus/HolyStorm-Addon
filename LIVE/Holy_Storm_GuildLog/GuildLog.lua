local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_GuildLog")

local metadata = {
    id = "guildLog", name = "GuildLog", internalName = "guildLog", displayName = L["DISPLAY_NAME"],
    description = L["DESCRIPTION"], version = addonVersion, moduleType = "feature", category = "feature",
    permissions = {}, dependencies = { "core" }, ui = { page = "guildManagement", navigation = false },
    data = { stores = { "GuildLogStore" }, schemaVersion = 1 }, sync = { domains = { "guildLog" } },
    capabilities = { "guild.log.submit", "guild.log.registerType", "guild.log.query", "guild.log.export" }, enabledByDefault = true,
}

HolyStorm:RegisterModule(metadata, function(GuildLog)
    HolyStorm:ApplyModuleMetadata(GuildLog, metadata)
    GuildLog.version = addonVersion
    GuildLog.eventTypes = {}
    GuildLog.categoryColors = {
        join = "35c759", leave = "ff5b57", promotion = "38c878", demotion = "ff9950", rank = "8d83dd",
        notes = "e6a23c", achievement = "b18cff", level = "45b9e8", birthday = "ff7eb6",
        anniversary = "f2cf50", absence = "67b7c7", other = "a6adbb",
    }
    GuildLog.categoryLabels = {
        join = "CATEGORY_JOIN", leave = "CATEGORY_LEAVE", rank = "CATEGORY_RANK",
        promotion = "CATEGORY_PROMOTION", demotion = "CATEGORY_DEMOTION", notes = "CATEGORY_NOTES",
        achievement = "CATEGORY_ACHIEVEMENT", level = "CATEGORY_LEVEL", birthday = "CATEGORY_BIRTHDAY",
        anniversary = "CATEGORY_ANNIVERSARY", absence = "CATEGORY_ABSENCE", other = "CATEGORY_OTHER",
    }

    local builtinTypes = {
        { id = "GUILD_JOINED", labelKey = "CATEGORY_JOIN", category = "join", template = "EVENT_JOIN" },
        { id = "GUILD_LEFT", labelKey = "CATEGORY_LEAVE", category = "leave", template = "EVENT_LEAVE" },
        { id = "RANK_CHANGED", labelKey = "CATEGORY_RANK", category = "rank" },
        { id = "LEVEL_UP", labelKey = "CATEGORY_LEVEL", category = "level", template = "EVENT_LEVEL" },
        { id = "PUBLIC_NOTE_CHANGED", labelKey = "CATEGORY_NOTES", category = "notes", template = "EVENT_PUBLIC_NOTE" },
        { id = "OFFICER_NOTE_CHANGED", labelKey = "CATEGORY_NOTES", category = "notes", template = "EVENT_OFFICER_NOTE", sensitive = true },
        { id = "ACHIEVEMENT_EARNED", labelKey = "CATEGORY_ACHIEVEMENT", category = "achievement", template = "EVENT_ACHIEVEMENT" },
        { id = "ABSENCE_CREATED", labelKey = "CATEGORY_ABSENCE", category = "absence", template = "EVENT_ABSENCE_CREATED", requiredPermission = "guild-absences-view" },
        { id = "ABSENCE_UPDATED", labelKey = "CATEGORY_ABSENCE", category = "absence", template = "EVENT_ABSENCE_UPDATED", requiredPermission = "guild-absences-view" },
        { id = "ABSENCE_ENDED", labelKey = "CATEGORY_ABSENCE", category = "absence", template = "EVENT_ABSENCE_ENDED", requiredPermission = "guild-absences-view" },
        { id = "BIRTHDAY", labelKey = "CATEGORY_BIRTHDAY", category = "birthday", template = "EVENT_BIRTHDAY" },
        { id = "GUILD_ANNIVERSARY", labelKey = "CATEGORY_ANNIVERSARY", category = "anniversary", template = "EVENT_ANNIVERSARY" },
    }

    function GuildLog:RegisterEventType(definition)
        if type(definition) ~= "table" or type(definition.id) ~= "string" or not definition.id:match("^[A-Z][A-Z0-9_]*$") or type(definition.labelKey) ~= "string" or not definition.labelKey:match("^[A-Z][A-Z0-9_]*$") or type(definition.category) ~= "string" or not definition.category:match("^[a-z][a-z0-9_%-]*$") then return false, "INVALID_EVENT_TYPE" end
        if self.eventTypes[definition.id] then return false, "EVENT_TYPE_EXISTS" end
        if definition.render ~= nil and type(definition.render) ~= "function" then return false, "INVALID_RENDERER" end
        if definition.identityKey ~= nil and type(definition.identityKey) ~= "function" then return false, "INVALID_IDENTITY_KEY" end
        if not self.categoryColors[definition.category] then
            local registered, reason = self:RegisterCategory(definition.category, definition.labelKey, definition.color)
            if not registered then return false, reason end
        end
        self.eventTypes[definition.id] = {
            id = definition.id, labelKey = definition.labelKey, category = definition.category,
            template = definition.template, render = definition.render, identityKey = definition.identityKey,
            sensitive = definition.sensitive == true, requiredPermission = definition.requiredPermission,
        }
        return true
    end

    function GuildLog:RegisterCategory(id, labelKey, color)
        if type(id) ~= "string" or not id:match("^[a-z][a-z0-9_%-]*$") or type(labelKey) ~= "string" or type(color) ~= "string" or not color:match("^%x%x%x%x%x%x$") then return false, "INVALID_CATEGORY" end
        if self.categoryColors[id] then return false, "CATEGORY_EXISTS" end
        self.categoryColors[id], self.categoryLabels[id] = string.lower(color), labelKey
        return true
    end

    function GuildLog:GetCategories()
        local result, seen = { "join", "leave", "rank", "promotion", "demotion", "notes", "achievement", "level", "birthday", "anniversary", "absence", "other" }, {}
        for _, category in ipairs(result) do seen[category] = true end
        for _, definition in pairs(self.eventTypes) do
            if definition.category ~= "rank" and not seen[definition.category] then result[#result + 1] = definition.category; seen[definition.category] = true end
        end
        table.sort(result)
        return result
    end

    function GuildLog:GetCategoryLabel(category)
        if category == "promotion" or category == "demotion" then return L["CATEGORY_" .. string.upper(category)] end
        local key = self.categoryLabels[category]
        return L[key or ("CATEGORY_" .. string.upper(category or "other"))] or L["CATEGORY_OTHER"]
    end

    function GuildLog:GetEventType(id) return self.eventTypes[id] end
    for _, definition in ipairs(builtinTypes) do assert(GuildLog:RegisterEventType(definition)) end

    local function visibleName(guid, fallback, linked)
        if not guid then return fallback or L["UNKNOWN_CHARACTER"] end
        local guild = HolyStorm.Data.GuildStore:GetCurrent()
        local member = guild and guild.roster and guild.roster[guid]
        local character = HolyStorm.Data.CharacterStore:Get(guid)
        local name = (member and member.name) or (character and (character.fullName or character.name)) or fallback or guid
        name = tostring(name):gsub("|", " "):gsub("[\r\n]", " ")
        local characterLink = HolyStorm.RichLinks and (HolyStorm.RichLinks:GetType("character") or HolyStorm.RichLinks:GetType("player"))
        if linked and characterLink then
            local classFile = (member and member.classFile) or (character and character.classFile)
            local colors = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
            local color = colors and string.format("%02x%02x%02x", math.floor(colors.r * 255 + .5), math.floor(colors.g * 255 + .5), math.floor(colors.b * 255 + .5))
            return HolyStorm.RichLinks:MakeHyperlink(characterLink.type or "character", guid, name, color)
        end
        return name
    end

    function GuildLog:GetCategory(event)
        if event.type == "RANK_CHANGED" then
            if event.data and (event.data.direction == "PROMOTION" or event.data.direction == "DEMOTION") then return string.lower(event.data.direction) end
            return "rank"
        end
        local definition = self:GetEventType(event.type)
        return definition and definition.category or "other"
    end

    function GuildLog:FormatEvent(event, linkedPlayers)
        local definition = self:GetEventType(event.type)
        if definition and definition.render then
            local ok, value = pcall(definition.render, event, function(identity)
                if type(identity) ~= "table" then return tostring(identity or L["UNKNOWN_CHARACTER"]) end
                return visibleName(identity.guid, identity.name, linkedPlayers)
            end, L)
            if ok and type(value) == "string" then return value end
        end
        local subject = type(event.subject) == "table" and visibleName(event.subject.guid, event.subject.name, linkedPlayers) or L["UNKNOWN_CHARACTER"]
        local actor = type(event.actor) == "table" and visibleName(event.actor.guid, event.actor.name, linkedPlayers) or nil
        local data = event.data or {}
        local template = definition and definition.template
        if event.type == "RANK_CHANGED" then
            local direction = data.direction == "PROMOTION" and "PROMOTION" or data.direction == "DEMOTION" and "DEMOTION" or nil
            local key = direction and (actor and ("EVENT_" .. direction .. "_BY") or ("EVENT_" .. direction)) or nil
            if actor and key then return string.format(L[key], subject, actor, tostring(data.newRank or L["UNKNOWN_VALUE"])) end
            return string.format(L[key or "EVENT_RANK"], subject, tostring(data.oldRank or L["UNKNOWN_VALUE"]), tostring(data.newRank or L["UNKNOWN_VALUE"]))
        elseif event.type == "PUBLIC_NOTE_CHANGED" then
            return actor and string.format(L["EVENT_PUBLIC_NOTE_BY"], actor, subject) or string.format(L["EVENT_PUBLIC_NOTE"], subject)
        elseif event.type == "OFFICER_NOTE_CHANGED" then
            return actor and string.format(L["EVENT_OFFICER_NOTE_BY"], actor, subject) or string.format(L["EVENT_OFFICER_NOTE"], subject)
        elseif event.type == "ABSENCE_CREATED" or event.type == "ABSENCE_UPDATED" or event.type == "ABSENCE_ENDED" then
            local range = string.format(L["ABSENCE_RANGE"], data.startAt and date(L["DATE_FORMAT"], data.startAt) or L["UNKNOWN_VALUE"], data.endAt and date(L["DATE_FORMAT"], data.endAt) or L["UNKNOWN_VALUE"])
            return string.format(L[template], subject, range)
        elseif event.type == "ACHIEVEMENT_EARNED" then
            return string.format(L[template], subject, tostring(data.achievementName or data.achievementId or L["UNKNOWN_VALUE"]))
        elseif event.type == "BIRTHDAY" then
            return string.format(L[template], subject, tostring(data.age or L["UNKNOWN_VALUE"]))
        elseif event.type == "GUILD_ANNIVERSARY" then
            return string.format(L[template], tostring(data.years or L["UNKNOWN_VALUE"]))
        elseif template then
            if event.type == "LEVEL_UP" then return string.format(L[template], subject, tonumber(data.newLevel) or 0) end
            return string.format(L[template], subject)
        end
        return string.format(L["EVENT_UNKNOWN"], tostring(event.type))
    end

    function GuildLog:BuildSearchText(event)
        local definition = self:GetEventType(event.type)
        local parts = { self:FormatEvent(event, false), event.type, L[definition and definition.labelKey or "CATEGORY_OTHER"] or event.type }
        local function add(value)
            if type(value) == "string" or type(value) == "number" then parts[#parts + 1] = tostring(value) end
        end
        add(event.actor and event.actor.name); add(event.actor and event.actor.guid)
        add(event.subject and event.subject.name); add(event.subject and event.subject.guid)
        local function collect(value, depth)
            if type(value) == "string" or type(value) == "number" then add(value)
            elseif type(value) == "table" and depth < 4 then for key, child in pairs(value) do add(key); collect(child, depth + 1) end end
        end
        collect(event.data, 0)
        return string.lower(table.concat(parts, " "))
    end

    function GuildLog:FormatTimestamp(timestamp, includeDate)
        return date(includeDate and L["DATE_TIME_FORMAT"] or L["TIME_FORMAT"], timestamp)
    end

    function GuildLog:CanReadOfficerNote()
        local api = _G.C_GuildInfo and _G.C_GuildInfo.CanViewOfficerNote or _G.CanViewOfficerNote
        if type(api) ~= "function" then return false end
        local ok, result = pcall(api)
        return ok and result == true
    end

    local function shortHash(value)
        local first, second = 5381, 52711
        value = tostring(value or "")
        for index = 1, #value do local byte = string.byte(value, index); first = (first * 33 + byte) % 2147483647; second = (second * 65599 + byte + index) % 2147483629 end
        return string.format("%08x%08x", first, second)
    end

    local function safeText(value)
        if issecretvalue then local ok, secret = pcall(issecretvalue, value); if not ok or secret then return nil end end
        return type(value) == "string" and value or nil
    end

    function GuildLog:MakeRosterSnapshot(guild)
        local snapshot = { capturedAt = HolyStorm.Utils.Now(), members = {} }
        local canReadOfficer = self:CanReadOfficerNote()
        for guid, member in pairs(guild and guild.roster or {}) do
            if type(guid) == "string" and type(member) == "table" then
                local note, officerNote = safeText(member.note), canReadOfficer and safeText(member.officerNote) or nil
                local record = {
                    name = safeText(member.name) or guid,
                    rank = safeText(member.rank) or "-",
                    rankIndex = tonumber(member.rankIndex),
                    level = tonumber(member.level) or 0,
                    publicNoteHash = note and shortHash(note) or nil,
                }
                if officerNote ~= nil then record.officerNoteHash = shortHash(officerNote) end
                snapshot.members[guid] = record
            end
        end
        return snapshot
    end

    function GuildLog:ScanRoster(guildId, capturedSnapshot)
        local guild = HolyStorm.Data.GuildStore:Get(guildId)
        if not guild or type(guild.roster) ~= "table" then return false end
        local current = capturedSnapshot or self:MakeRosterSnapshot(guild)
        local previous = HolyStorm.Data.GuildLogStore:GetRosterSnapshot(guildId)
        if not previous or type(previous.members) ~= "table" then
            HolyStorm.Data.GuildLogStore:SetRosterSnapshot(guildId, current)
            return true, "BASELINE"
        end
        local events, capturedAt = {}, current.capturedAt
        local observedFrom = tonumber(previous.capturedAt) or capturedAt
        local function append(eventType, subjectGuid, old, new, data, sensitive)
            local identity = new or old
            events[#events + 1] = {
                type = eventType, timestamp = capturedAt, timestampSource = "ROSTER_DELTA_CAPTURE", capturedAt = capturedAt,
            resolutionState = "RECONSTRUCTED", subject = { guid = subjectGuid, name = identity and identity.name },
                data = data or {}, sensitive = sensitive == true,
                provenance = { kind = "ROSTER_DELTA", source = "guild-roster-snapshot", observation = { from = observedFrom, to = capturedAt }, details = { previous = old, current = new } },
            }
        end
        for guid, member in pairs(current.members) do
            local old = previous.members[guid]
            if not old then
                append("GUILD_JOINED", guid, nil, member)
            else
                if old.rank ~= member.rank or old.rankIndex ~= member.rankIndex then
                    local direction
                    if old.rankIndex and member.rankIndex then
                        if member.rankIndex < old.rankIndex then direction = "PROMOTION" elseif member.rankIndex > old.rankIndex then direction = "DEMOTION" end
                    end
                    append("RANK_CHANGED", guid, old, member, { oldRank = old.rank, newRank = member.rank, oldRankIndex = old.rankIndex, newRankIndex = member.rankIndex, direction = direction })
                end
                if (tonumber(member.level) or 0) > (tonumber(old.level) or 0) then append("LEVEL_UP", guid, old, member, { oldLevel = old.level, newLevel = member.level }) end
                if old.publicNoteHash ~= member.publicNoteHash then append("PUBLIC_NOTE_CHANGED", guid, old, member, { oldValueHash = old.publicNoteHash, newValueHash = member.publicNoteHash }) end
                if self:CanReadOfficerNote() and old.officerNoteHash ~= nil and member.officerNoteHash ~= nil and old.officerNoteHash ~= member.officerNoteHash then
                    append("OFFICER_NOTE_CHANGED", guid, old, member, { oldValueHash = old.officerNoteHash, newValueHash = member.officerNoteHash }, true)
                end
            end
        end
        for guid, member in pairs(previous.members) do if not current.members[guid] then append("GUILD_LEFT", guid, member, nil) end end
        local ok, result = #events == 0 and true or HolyStorm.Data.GuildLogStore:SubmitMany(guildId, events)
        if ok then HolyStorm.Data.GuildLogStore:SetRosterSnapshot(guildId, current) end
        return ok, result
    end

    local function absenceEvent(eventName, eventId, entry)
        if type(entry) ~= "table" then return end
        local eventType = eventName == "HS_GUILD_ABSENCE_CREATED" and "ABSENCE_CREATED" or eventName == "HS_GUILD_ABSENCE_UPDATED" and "ABSENCE_UPDATED" or "ABSENCE_ENDED"
        local subjectGuid = entry.ownerCharacterUUID
        local actorGuid = eventType == "ABSENCE_CREATED" and (entry.createdByCharacterUUID or entry.modifiedByCharacterUUID) or entry.modifiedByCharacterUUID
        local store = HolyStorm.Data.GuildLogStore
        store:Submit(HolyStorm.GuildManagement:GetGuildId(), {
            type = eventType, timestamp = eventType == "ABSENCE_CREATED" and entry.createdAt or entry.modifiedAt,
            timestampSource = "SERVER_EVENT", resolutionState = "AUTHORITATIVE",
            originGuid = actorGuid,
            actor = actorGuid and { guid = actorGuid }, subject = subjectGuid and { guid = subjectGuid },
            data = { absenceId = entry.absenceId or eventId, revision = entry.revision, action = eventType, startAt = entry.startAt, endAt = entry.endAt, title = entry.title },
            requiredPermission = "guild-absences-view",
            provenance = { kind = "MODULE_EVENT", source = "GuildManagement.Absences", sourceEvent = eventName },
        })
    end

    function GuildLog:ConsumeAchievementAwards(event)
        if type(event) ~= "table" or type(event.awards) ~= "table" then return false end
        local guild = HolyStorm.Data.GuildStore:GetCurrent()
        if not guild then return false end
        local inputs = {}
        for _, award in ipairs(event.awards) do
            if type(award) == "table" and award.status == "AWARDED" and award.characterUUID and guild.roster and guild.roster[award.characterUUID] then
                inputs[#inputs + 1] = {
                    type = "ACHIEVEMENT_EARNED", timestamp = award.awardedAt or event.awardedAt,
                    timestampSource = "SERVER_EVENT", resolutionState = "AUTHORITATIVE",
                    actor = award.awardedBy and { guid = award.awardedBy }, originGuid = award.awardedBy or event.awardedBy, subject = { guid = award.characterUUID },
                    data = { achievementId = event.achievementID or award.achievementID, achievementName = event.achievementName, awardInstanceId = event.awardInstanceID, awardId = award.awardID },
                    provenance = { kind = "MODULE_EVENT", source = "Achievements", awardInstanceId = event.awardInstanceID },
                }
            end
        end
        if #inputs == 0 then return true end
        return HolyStorm.Data.GuildLogStore:SubmitMany(guild.id, inputs)
    end

    function GuildLog:InstallManagementFeature()
        local manager = HolyStorm.GuildManagement
        if not manager or type(manager.RegisterFeature) ~= "function" or self.featureRegistered then return false end
        local feature = {
            id = "guildLog", order = 40, title = L["DISPLAY_NAME"], icon = "Interface\\Icons\\INV_Misc_Note_05", owner = "guildLog",
            build = function(parent) return HolyStorm.GuildLogUI:Build(self, parent) end,
            refresh = function() return HolyStorm.GuildLogUI:Refresh(self) end,
        }
        local ok = manager:RegisterFeature(feature)
        self.featureRegistered = ok == true
        return self.featureRegistered
    end

    function GuildLog:InstallOptions()
        if self.optionsRegistered then return true end
        local options = HolyStorm:GetModule("Options", true)
        if not options or type(options.RegisterOptionsTab) ~= "function" then return false end
        local function retention() return HolyStorm.Data.GuildLogStore:GetRetention() or {} end
        local definition = {
            type = "group", name = L["DISPLAY_NAME"], order = 36,
            args = {
                retention = {
                    type = "group", name = L["RETENTION_TITLE"], inline = true, order = 10,
                    args = {
                        help = { type = "description", name = L["RETENTION_HELP"], order = 1 },
                        maxEntries = {
                            type = "range", name = L["RETENTION_MAX_ENTRIES"], min = 100, max = 20000, step = 100, order = 2,
                            get = function() return tonumber(retention().maxEntries) or 5000 end,
                            set = function(_, value) local current = retention(); HolyStorm.Data.GuildLogStore:ConfigureRetention(value, current.maxAgeSeconds or (730 * 86400)) end,
                        },
                        maxAgeDays = {
                            type = "range", name = L["RETENTION_MAX_AGE_DAYS"], min = 30, max = 3650, step = 1, order = 3,
                            get = function() return math.floor((tonumber(retention().maxAgeSeconds) or (730 * 86400)) / 86400) end,
                            set = function(_, value) local current = retention(); HolyStorm.Data.GuildLogStore:ConfigureRetention(current.maxEntries or 5000, value * 86400) end,
                        },
                    },
                },
            },
        }
        self.optionsRegistered = options:RegisterOptionsTab("guildLog", definition) == true
        return self.optionsRegistered
    end

    function GuildLog:Open()
        HolyStorm.Events:Emit("HS_GUILD_LOG_OPEN_REQUESTED", "guildManagement", "guildLog")
        if not (HolyStorm.GuildManagement and HolyStorm.GuildManagement.Open) then
            HolyStorm.Commands:PrintUserMessage(L["COMMAND_UNAVAILABLE"])
            return false
        end
        return true
    end

    function GuildLog:OnInitialize()
        if not HolyStorm.Data.GuildLogStore:Initialize() then return end
        HolyStorm.Tasks:RegisterTaskType("GuildLog.RosterDelta", {
            name = L["TASK_ROSTER_DELTA"], module = "guildLog", priority = 22, executionMode = "MERGE_BY_KEY",
            execute = function(task) local meta = task.metadata or {}; if meta.guildId then return GuildLog:ScanRoster(meta.guildId, meta.snapshot) end; return false end,
        })
        HolyStorm.Tasks:RegisterTaskType("GuildLog.Filter", {
            name = L["TASK_FILTER"], module = "guildLog", priority = 28, executionMode = "MERGE_BY_KEY",
            execute = function() return HolyStorm.GuildLogUI:RunFilterTask() end,
        })
        HolyStorm.Tasks:RegisterTaskType("GuildLog.Prune", {
            name = L["TASK_PRUNE"], module = "guildLog", priority = 72, executionMode = "MERGE_BY_KEY",
            execute = function(task) local guildId = task.metadata and task.metadata.guildId; return guildId and HolyStorm.Data.GuildLogStore:Prune(guildId) or false end,
        })
        HolyStorm.Sync:RegisterDomain("guildLog", {
            freshness = "revision-chain", priority = 73,
            getMetadata = function(eventId)
                local meta = HolyStorm.Data.GuildLogStore:GetMetadata(eventId)
                local guild = HolyStorm.Data.GuildStore:GetCurrent()
                return guild and meta and meta.guildId == guild.id and meta or nil
            end,
            listMetadata = function(since)
                local guild = HolyStorm.Data.GuildStore:GetCurrent(); local result = {}
                if not guild then return result end
                for _, meta in ipairs(HolyStorm.Data.GuildLogStore:ListMetadata(since)) do if meta.guildId == guild.id then result[#result + 1] = meta end end
                return result
            end,
            export = function(eventId)
                local guild = HolyStorm.Data.GuildStore:GetCurrent()
                local event = guild and HolyStorm.Data.GuildLogStore:GetEvent(guild.id, eventId)
                return event and not event.sensitive and HolyStorm.Data.GuildLogStore:CanView(event) and event or nil
            end,
            validate = function(event, meta, objectId)
                local guild = HolyStorm.Data.GuildStore:GetCurrent()
                if not guild or type(event) ~= "table" or event.guildId ~= guild.id or event.eventId ~= objectId or meta.objectId ~= objectId or meta.owner ~= event.originGuid or meta.revisionID ~= event.revisionId then return false, "GUILD_OR_EVENT_MISMATCH" end
                return HolyStorm.Data.GuildLogStore:ValidateEvent(event)
            end,
            authorize = function(event, meta)
                local guild = HolyStorm.Data.GuildStore:GetCurrent()
                if not guild or event.guildId ~= guild.id or event.sensitive or event.type == "OFFICER_NOTE_CHANGED" then return false end
                if meta.owner ~= event.originGuid then return false end
                return HolyStorm.Data.GuildLogStore:CanView(event)
            end,
            import = function(eventId, event, meta) return HolyStorm.Data.GuildLogStore:Import(eventId, event, meta) end,
            canShare = function(meta, recipientGuid)
                if meta.guildId ~= (HolyStorm.Data.GuildStore:GetCurrent() or {}).id then return false end
                local event = HolyStorm.Data.GuildLogStore:GetEvent(meta.guildId, meta.objectId)
                if not event or event.sensitive then return false end
                if event.requiredPermission then
                    local manager = HolyStorm.GuildManagement
                    local account = manager and manager.GetAccountUUID and manager:GetAccountUUID(recipientGuid)
                    return account ~= nil and manager:Can(event.requiredPermission, account, recipientGuid, event) == true
                end
                return true
            end,
            getRecipients = function(meta)
                local event = HolyStorm.Data.GuildLogStore:GetEvent(meta.guildId, meta.objectId)
                if not event or not event.requiredPermission then return nil end
                local guild = HolyStorm.Data.GuildStore:GetCurrent(); local out = {}
                for guid, member in pairs(guild and guild.roster or {}) do if guid ~= UnitGUID("player") and member.online then out[#out + 1] = { guid = guid, name = member.name } end end
                return out
            end,
            updateEvent = "HS_GUILD_LOG_SYNCED",
        })
    end

    function GuildLog:OnEnable()
        HolyStorm:RegisterCapability("guildLog", "guild.log.submit", function(_, event) return HolyStorm.Data.GuildLogStore:Submit(nil, event) end)
        HolyStorm:RegisterCapability("guildLog", "guild.log.registerType", function(_, definition) return GuildLog:RegisterEventType(definition) end)
        HolyStorm:RegisterCapability("guildLog", "guild.log.query", function(_, options) local guild = HolyStorm.Data.GuildStore:GetCurrent(); return HolyStorm.Data.GuildLogStore:List(guild and guild.id, options) end)
        HolyStorm:RegisterCapability("guildLog", "guild.log.export", function(_, format, options)
            local content, reason = HolyStorm.GuildLogUI:Export(GuildLog, format, options)
            return content or { errorCode = reason or "EXPORT_FAILED" }
        end)
        self:InstallManagementFeature()
        HolyStorm.Events:Register("HS_ROSTER_UPDATED", "guild-log-roster", function(_, guildId)
            local guild = HolyStorm.Data.GuildStore:Get(guildId)
            local snapshot = guild and GuildLog:MakeRosterSnapshot(guild)
            HolyStorm.Tasks:Queue("GuildLog.RosterDelta", { executionMode = "MULTI", triggerSource = "GUILD_ROSTER_DELTA", metadata = { guildId = guildId, snapshot = snapshot } })
        end)
        HolyStorm.Events:Register("HS_GUILD_ABSENCE_CREATED", "guild-log-absence", absenceEvent)
        HolyStorm.Events:Register("HS_GUILD_ABSENCE_UPDATED", "guild-log-absence", absenceEvent)
        HolyStorm.Events:Register("HS_GUILD_ABSENCE_DELETED", "guild-log-absence", absenceEvent)
        HolyStorm.Events:Register("HS_GUILD_ABSENCE_SYNCED", "guild-log-absence", function(_, id, status, event)
            if event then local source = event.status == "DELETED" and "HS_GUILD_ABSENCE_DELETED" or tonumber(event.revision) == 1 and "HS_GUILD_ABSENCE_CREATED" or "HS_GUILD_ABSENCE_UPDATED"; absenceEvent(source, id or event.absenceId, event) end
        end)
        HolyStorm.Events:Register("HS_ACHIEVEMENT_AWARDS_COMMITTED", "guild-log-achievement", function(_, event) GuildLog:ConsumeAchievementAwards(event) end)
        HolyStorm.Events:Register("HS_GUILD_LOG_UPDATED", "guild-log-ui-refresh", function(_, guildId)
            local manager = HolyStorm.GuildManagement
            if manager and manager.UI and manager.UI.selected == "guildLog" then manager.UI:Refresh() end
        end)
        HolyStorm.Events:Register("HS_GUILD_LOG_OPEN_REQUESTED", "guild-log-open", function() local manager = HolyStorm.GuildManagement; if manager then manager:Open("guildLog") end end)
        HolyStorm.Events:Register("HS_MODULE_AVAILABILITY_CHANGED", "guild-log-management-feature", function(_, id, enabled)
            if enabled and id == "GuildManagement" then self:InstallManagementFeature()
            elseif enabled and (id == "Options" or id == "options") then self:InstallOptions() end
        end)
        self:InstallOptions()
        local command = function(arguments)
            if HolyStorm.Utils.Trim(arguments or ""):lower() ~= "log" then return false end
            GuildLog:Open(); return true
        end
        HolyStorm.Commands:RegisterSubcommand("guild", { help = L["COMMAND_GUILD_HELP"], execute = function(arguments) if not command(arguments) then HolyStorm.Commands:PrintUserMessage(L["COMMAND_GUILD_USAGE"]) end end })
        HolyStorm.Commands:RegisterSubcommand("glog", { help = L["COMMAND_GLOG_HELP"], execute = function() GuildLog:Open() end })
        HolyStorm.Tasks:ScheduleRecurring("GuildLog.Retention", 86400, function() HolyStorm.Data.GuildLogStore:PruneAll() end, { priority = 72, module = "guildLog" })
        for _, guildId in ipairs(HolyStorm.Data.GuildLogStore:GetGuildIds()) do HolyStorm.Data.GuildLogStore:SchedulePrune(guildId, "GUILD_LOG_STARTUP_PRUNE") end
        if IsInGuild() then
            local guild = HolyStorm.Data.GuildStore:GetCurrent()
            if guild then HolyStorm.Tasks:Queue("GuildLog.RosterDelta", { mergeKey = tostring(guild.id), delay = 1, triggerSource = "GUILD_LOG_LOGIN_BASELINE", metadata = { guildId = guild.id } }) end
        end
    end

    function GuildLog:OnDisable()
        HolyStorm.Events:UnregisterOwner("guild-log-roster"); HolyStorm.Events:UnregisterOwner("guild-log-absence"); HolyStorm.Events:UnregisterOwner("guild-log-achievement")
        HolyStorm.Events:UnregisterOwner("guild-log-ui-refresh"); HolyStorm.Events:UnregisterOwner("guild-log-open"); HolyStorm.Events:UnregisterOwner("guild-log-management-feature")
        for _, task in ipairs(HolyStorm.Tasks:GetLiveTasks()) do
            if task.registryId == "GuildLog.RosterDelta" or task.registryId == "GuildLog.Filter" or task.registryId == "GuildLog.Prune" or task.registryId == "GuildLog.Retention" then HolyStorm.Tasks:Cancel(task.uniqueId, "GUILD_LOG_DISABLED") end
        end
        HolyStorm.Tasks:CancelRecurring("GuildLog.Retention")
        HolyStorm.Commands:UnregisterSubcommand("guild"); HolyStorm.Commands:UnregisterSubcommand("glog")
        for _, capability in ipairs({ "guild.log.submit", "guild.log.registerType", "guild.log.query", "guild.log.export" }) do HolyStorm:UnregisterCapability("guildLog", capability) end
        if self.featureRegistered and HolyStorm.GuildManagement then HolyStorm.GuildManagement:UnregisterFeature("guildLog") end
        self.featureRegistered = false
        HolyStorm.Sync:UnregisterDomain("guildLog")
    end
end)
