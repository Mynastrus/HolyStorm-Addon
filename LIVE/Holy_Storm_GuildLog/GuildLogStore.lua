local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Store = { version = "2.0.0", schemaId = "guild-log", owner = "GuildLogStore", maxEvents = 5000, maxAgeSeconds = 730 * 86400 }

local function now() return HolyStorm.Utils.Now() end
local function validId(value, limit) return type(value) == "string" and value ~= "" and #value <= (limit or 160) end
local function safeNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
local function copy(value) return HolyStorm.Utils.DeepCopy(value) end
local function eventYear(timestamp)
    local year = date and tonumber(date("%Y", timestamp))
    return year or math.floor(timestamp / 31557600)
end
local function log(level, message, context)
    if HolyStorm.Logger and HolyStorm.Logger.Write then HolyStorm.Logger:Write(level, "GuildLog", "events", message, context) end
end
local function logHidden(event, reason)
    Store.hiddenEventsLogged = Store.hiddenEventsLogged or {}
    if Store.hiddenEventsLogged[event.eventId] then return end
    Store.hiddenEventsLogged[event.eventId] = true
    log("DEBUG", "Permission-sensitive GuildLog event hidden", { eventId = event.eventId, eventType = event.type, requiredPermission = event.requiredPermission, reason = reason })
end

local function validateTree(value, depth, budget)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" then return true end
    if kind == "string" then
        if #value > 8192 then return false end
        budget.size = budget.size + #value
        return budget.size <= 16384
    end
    if kind ~= "table" or depth > 10 then return false end
    budget.items = budget.items + 1
    if budget.items > 1200 then return false end
    for key, child in pairs(value) do
        if type(key) ~= "string" and type(key) ~= "number" then return false end
        if type(key) == "string" and #key > 128 then return false end
        if not validateTree(child, depth + 1, budget) then return false end
    end
    return true
end

local function validateDatabase(value)
    if type(value) ~= "table" or tonumber(value.schemaVersion) ~= 1 or type(value.guilds) ~= "table" then return false end
    if value.retention ~= nil and type(value.retention) ~= "table" then return false end
    for guildId, guild in pairs(value.guilds) do
        if not validId(guildId) or type(guild) ~= "table" or type(guild.entries) ~= "table" or type(guild.order) ~= "table" or type(guild.aliases) ~= "table" then return false end
    end
    return true
end

HolyStorm.DataManager:RegisterSchema({
    id = Store.schemaId,
    owner = Store.owner,
    version = 1,
    storage = { backend = "database", scope = "global", path = { "guildLog" } },
    default = function() return { schemaVersion = 1, guilds = {}, retention = { maxEntries = Store.maxEvents, maxAgeSeconds = Store.maxAgeSeconds } } end,
    validate = validateDatabase,
    event = "HS_GUILD_LOG_COMMITTED",
})

function Store:Initialize()
    local root, result = HolyStorm.DataManager:GetOwnedRoot(self.schemaId, self.owner)
    if type(root) ~= "table" then log("ERROR", "GuildLog persistence initialization failed", { reason = result and result.errorCode }); return false end
    root.schemaVersion = 1
    root.guilds = type(root.guilds) == "table" and root.guilds or {}
    root.retention = type(root.retention) == "table" and root.retention or {}
    root.retention.maxEntries = math.max(100, math.min(20000, math.floor(tonumber(root.retention.maxEntries) or self.maxEvents)))
    root.retention.maxAgeSeconds = math.max(30 * 86400, math.min(3650 * 86400, math.floor(tonumber(root.retention.maxAgeSeconds) or self.maxAgeSeconds)))
    self.root = root
    return true
end

function Store:_Root()
    if self.root then return self.root end
    self:Initialize()
    return self.root
end

function Store:_Guild(guildId, create)
    if not validId(guildId) then return nil end
    local root = self:_Root()
    if not root then return nil end
    local guild = root.guilds[guildId]
    if not guild and create then
        guild = { entries = {}, order = {}, aliases = {}, rosterSnapshot = nil }
        root.guilds[guildId] = guild
    end
    if guild and create then
        guild.entries = type(guild.entries) == "table" and guild.entries or {}
        guild.order = type(guild.order) == "table" and guild.order or {}
        guild.aliases = type(guild.aliases) == "table" and guild.aliases or {}
    end
    return guild
end

local function stable(value, depth)
    depth = depth or 0
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if depth > 10 then return "!depth" end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = { "{" }
    for _, key in ipairs(keys) do out[#out + 1] = stable(key, depth + 1); out[#out + 1] = "="; out[#out + 1] = stable(value[key], depth + 1); out[#out + 1] = ";" end
    out[#out + 1] = "}"
    return table.concat(out)
end

local function hash(value)
    local first, second = 5381, 52711
    for index = 1, #value do
        local byte = string.byte(value, index)
        first = (first * 33 + byte) % 2147483647
        second = (second * 65599 + byte + index) % 2147483629
    end
    return string.format("%08x%08x", first, second)
end

local function actorOrSubject(event)
    local actor = type(event.actor) == "table" and event.actor.guid
    local subject = type(event.subject) == "table" and event.subject.guid
    return actor or subject or event.originGuid or "unknown"
end

function Store:ValidateEvent(event)
    if type(event) ~= "table" or tonumber(event.schemaVersion) ~= 1 or not validId(event.eventId) or not validId(event.guildId) or not validId(event.type, 96) then return false, "INVALID_IDENTITY" end
    if not safeNumber(event.timestamp) or event.timestamp < 0 or not safeNumber(event.capturedAt) or event.capturedAt < 0 or not safeNumber(event.updatedAt) or event.updatedAt < 0 then return false, "INVALID_TIMESTAMP" end
    if not validId(event.originGuid) or not validId(event.recordedByGuid) or type(event.data) ~= "table" or type(event.provenance) ~= "table" then return false, "INVALID_EVENT_DATA" end
    if event.resolutionState ~= "RECONSTRUCTED" and event.resolutionState ~= "AUTHORITATIVE" and event.resolutionState ~= "SUPERSEDED" then return false, "INVALID_RESOLUTION_STATE" end
    if event.timestampSource ~= "SERVER_EVENT" and event.timestampSource ~= "ROSTER_DELTA_CAPTURE" and event.timestampSource ~= "PRODUCER" then return false, "INVALID_TIMESTAMP_SOURCE" end
    if type(event.revisionId) ~= "string" or #event.revisionId > 80 then return false, "INVALID_REVISION" end
    if not validId(event.identityKey, 512) or event.eventId ~= "gl1-" .. hash(event.guildId .. "\031" .. event.identityKey) then return false, "INVALID_EVENT_ID" end
    if event.requiredPermission ~= nil and (not validId(event.requiredPermission, 96) or not event.requiredPermission:match("^[%w_.%-]+$")) then return false, "INVALID_PERMISSION" end
    if event.sensitive ~= nil and type(event.sensitive) ~= "boolean" then return false, "INVALID_SENSITIVITY" end
    if event.supersededBy ~= nil then
        if type(event.supersededBy) ~= "table" or #event.supersededBy > 2 then return false, "INVALID_RECONCILIATION" end
        for _, replacement in ipairs(event.supersededBy) do if not validId(replacement) then return false, "INVALID_RECONCILIATION" end end
    end
    local budget = { items = 0, size = 0 }
    if not validateTree(event.data, 0, budget) or not validateTree(event.provenance, 0, budget) then return false, "INVALID_EVENT_SHAPE" end
    for _, identity in ipairs({ "actor", "subject" }) do
        local value = event[identity]
        if value ~= nil and (type(value) ~= "table" or value.guid ~= nil and not validId(value.guid) or value.name ~= nil and (type(value.name) ~= "string" or #value.name > 160)) then return false, "INVALID_CHARACTER_IDENTITY" end
    end
    return true
end

function Store:_IdentityKey(event, descriptor)
    local data = event.data or {}
    local subject = type(event.subject) == "table" and event.subject.guid or "unknown"
    local kind = event.type
    local bucket = math.floor(event.timestamp / 300)
    if descriptor and type(descriptor.identityKey) == "function" then
        local ok, value = pcall(descriptor.identityKey, event)
        if ok and validId(value, 512) then return value end
        return nil
    end
    if kind == "GUILD_JOINED" or kind == "GUILD_LEFT" then return table.concat({ kind, subject, bucket }, ":") end
    if kind == "RANK_CHANGED" then return table.concat({ kind, subject, tostring(data.oldRank or "?"), tostring(data.newRank or "?"), bucket }, ":") end
    if kind == "LEVEL_UP" then return table.concat({ kind, subject, tostring(data.newLevel or "?") }, ":") end
    if kind == "PUBLIC_NOTE_CHANGED" or kind == "OFFICER_NOTE_CHANGED" then return table.concat({ kind, subject, tostring(data.oldValueHash or "?"), tostring(data.newValueHash or "?"), bucket }, ":") end
    if kind == "ACHIEVEMENT_EARNED" then return table.concat({ kind, subject, tostring(data.achievementId or "?"), tostring(data.awardInstanceId or data.instanceId or "?") }, ":") end
    if kind:match("^ABSENCE_") then return table.concat({ kind, subject, tostring(data.absenceId or "?"), tostring(data.revision or "?") }, ":") end
    if kind == "BIRTHDAY" then return table.concat({ kind, subject, tostring(data.calendarYear or eventYear(event.timestamp)) }, ":") end
    if kind == "GUILD_ANNIVERSARY" then return table.concat({ kind, event.guildId, tostring(data.calendarYear or eventYear(event.timestamp)) }, ":") end
    return validId(data.eventKey, 512) and (kind .. ":" .. data.eventKey) or nil
end

function Store:_RevisionId(event)
    local identity = {
        type = event.type, guildId = event.guildId, timestamp = event.timestamp,
        timestampSource = event.timestampSource, actor = event.actor, subject = event.subject,
        data = event.data, provenance = event.provenance, resolutionState = event.resolutionState,
        originGuid = event.originGuid, recordedByGuid = event.recordedByGuid,
        requiredPermission = event.requiredPermission, sensitive = event.sensitive,
        supersededBy = event.supersededBy,
    }
    return "gl1-" .. hash(stable(identity))
end

local function normalizeIdentity(value)
    if value == nil then return nil end
    if type(value) == "string" then return { name = value:sub(1, 160) } end
    if type(value) ~= "table" then return nil end
    local identity = {}
    if validId(value.guid) then identity.guid = value.guid end
    if type(value.name) == "string" then identity.name = value.name:sub(1, 160) end
    return next(identity) and identity or nil
end

function Store:_NewEvent(guildId, input, descriptor)
    local capturedAt = now()
    local event = {
        schemaVersion = 1,
        type = input.type or input.eventType,
        guildId = guildId,
        timestamp = safeNumber(input.timestamp) or capturedAt,
        timestampSource = input.timestampSource or (input.resolutionState == "RECONSTRUCTED" and "ROSTER_DELTA_CAPTURE" or "PRODUCER"),
        capturedAt = safeNumber(input.capturedAt) or capturedAt,
        updatedAt = safeNumber(input.updatedAt) or capturedAt,
        actor = normalizeIdentity(input.actor),
        subject = normalizeIdentity(input.subject),
        data = copy(input.data or {}),
        provenance = copy(input.provenance or { kind = input.resolutionState == "RECONSTRUCTED" and "ROSTER_DELTA" or "MODULE_EVENT", source = input.source or "guildLog.submit" }),
        resolutionState = input.resolutionState == "RECONSTRUCTED" and "RECONSTRUCTED" or input.resolutionState == "SUPERSEDED" and "SUPERSEDED" or "AUTHORITATIVE",
        originGuid = input.originGuid or input.recordedByGuid or (UnitGUID and UnitGUID("player")) or actorOrSubject(input),
        requiredPermission = input.requiredPermission,
        sensitive = input.sensitive == true,
        recordedByGuid = input.recordedByGuid or (UnitGUID and UnitGUID("player")) or "unknown",
        revision = math.max(1, math.floor(tonumber(input.revision) or 1)),
    }
    if not validId(event.originGuid) then event.originGuid = event.recordedByGuid end
    local identityKey = validId(input.identityKey, 512) and input.identityKey or self:_IdentityKey(event, descriptor)
    if not identityKey then return nil, "MISSING_STABLE_EVENT_KEY" end
    event.identityKey = identityKey
    event.eventId = "gl1-" .. hash(guildId .. "\031" .. identityKey)
    event.supersededBy = type(input.supersededBy) == "table" and copy(input.supersededBy) or nil
    event.revisionId = self:_RevisionId(event)
    local valid, reason = self:ValidateEvent(event)
    if not valid then return nil, reason end
    return event
end

local function rankPair(event)
    local data = event.data or {}
    return event.type == "RANK_CHANGED" and type(event.subject) == "table" and event.subject.guid and data.oldRank ~= nil and data.newRank ~= nil
end
local function isDirect(event) return event.resolutionState == "AUTHORITATIVE" end
local function observationWindow(event)
    local observation = event.provenance and event.provenance.observation
    if type(observation) ~= "table" then return nil end
    local first, last = safeNumber(observation.from), safeNumber(observation.to)
    if first and last then return math.min(first, last), math.max(first, last) end
end
local function inObservation(event, timestamp)
    local first, last = observationWindow(event)
    if first and last then return timestamp >= first - 60 and timestamp <= last + 60 end
    return math.abs((event.timestamp or 0) - timestamp) <= 600
end
local function sameRankTransition(a, b)
    return rankPair(a) and rankPair(b) and a.subject.guid == b.subject.guid and a.data.oldRank == b.data.oldRank and a.data.newRank == b.data.newRank
end
local function sameMembershipTransition(a, b)
    return a.type == b.type and (a.type == "GUILD_JOINED" or a.type == "GUILD_LEFT") and type(a.subject) == "table" and type(b.subject) == "table" and a.subject.guid == b.subject.guid
end
local function sameNoteTransition(a, b)
    if a.type ~= b.type or (a.type ~= "PUBLIC_NOTE_CHANGED" and a.type ~= "OFFICER_NOTE_CHANGED") or type(a.subject) ~= "table" or type(b.subject) ~= "table" then return false end
    return a.subject.guid == b.subject.guid and a.data.oldValueHash == b.data.oldValueHash and a.data.newValueHash == b.data.newValueHash
end
local function tolerantObservationMatch(existing, incoming)
    if isDirect(existing) and isDirect(incoming) then return math.abs(existing.timestamp - incoming.timestamp) <= 120 end
    if not isDirect(existing) and not isDirect(incoming) then
        local firstA, lastA = observationWindow(existing)
        local firstB, lastB = observationWindow(incoming)
        if firstA and firstB then return firstA <= lastB + 60 and firstB <= lastA + 60 end
        return math.abs(existing.timestamp - incoming.timestamp) <= 300
    end
    if not isDirect(existing) then return inObservation(existing, incoming.timestamp) end
    return inObservation(incoming, existing.timestamp)
end

function Store:_FindMatch(guild, incoming)
    if guild.entries[incoming.eventId] then return incoming.eventId end
    if incoming.type ~= "RANK_CHANGED" and incoming.type ~= "GUILD_JOINED" and incoming.type ~= "GUILD_LEFT" and incoming.type ~= "PUBLIC_NOTE_CHANGED" and incoming.type ~= "OFFICER_NOTE_CHANGED" then return nil end
    for _, existingId in ipairs(guild.order) do
        local existing = guild.entries[existingId]
        if existing then
            if existing.identityKey == incoming.identityKey then return existingId end
            if sameRankTransition(existing, incoming) then
                if isDirect(existing) and isDirect(incoming) and math.abs(existing.timestamp - incoming.timestamp) <= 120 then return existingId end
                if not isDirect(existing) and not isDirect(incoming) then
                    local firstA, lastA = observationWindow(existing)
                    local firstB, lastB = observationWindow(incoming)
                    if firstA and firstB and firstA <= lastB + 60 and firstB <= lastA + 60 or math.abs(existing.timestamp - incoming.timestamp) <= 300 then return existingId end
                elseif not isDirect(existing) and isDirect(incoming) and inObservation(existing, incoming.timestamp) then return existingId
                elseif isDirect(existing) and not isDirect(incoming) and inObservation(incoming, existing.timestamp) then return existingId end
            elseif sameMembershipTransition(existing, incoming) and tolerantObservationMatch(existing, incoming) then
                return existingId
            elseif sameNoteTransition(existing, incoming) and tolerantObservationMatch(existing, incoming) then
                return existingId
            end
        end
    end
end

local function preferredEvent(left, right)
    local stateScore = { RECONSTRUCTED = 1, SUPERSEDED = 2, AUTHORITATIVE = 3 }
    local leftState, rightState = stateScore[left.resolutionState] or 0, stateScore[right.resolutionState] or 0
    if leftState ~= rightState then return leftState > rightState and left or right end
    local leftDirect, rightDirect = isDirect(left), isDirect(right)
    if leftDirect ~= rightDirect then return leftDirect and left or right end
    if left.revision ~= right.revision then return left.revision > right.revision and left or right end
    if left.revisionId ~= right.revisionId then return left.revisionId < right.revisionId and left or right end
    return left.eventId < right.eventId and left or right
end

function Store:_MergeEvents(left, right)
    local preferred = preferredEvent(left, right)
    local merged = copy(preferred)
    local other = preferred == left and right or left
    for _, identity in ipairs({ "actor", "subject" }) do
        if type(merged[identity]) ~= "table" then merged[identity] = copy(other[identity])
        elseif type(other[identity]) == "table" then
            if not merged[identity].guid then merged[identity].guid = other[identity].guid end
            if not merged[identity].name then merged[identity].name = other[identity].name end
        end
    end
    merged.data = type(merged.data) == "table" and merged.data or {}
    for key, value in pairs(other.data or {}) do if merged.data[key] == nil then merged.data[key] = copy(value) end end
    if isDirect(left) and isDirect(right) then
        -- Equal authority observations converge on the same payload on every peer.
        for key, value in pairs(right.data or {}) do
            if left.data[key] ~= nil and value ~= nil and stable(left.data[key]) ~= stable(value) then
                merged.data[key] = stable(left.data[key]) < stable(value) and copy(left.data[key]) or copy(value)
            end
        end
        if left.actor and right.actor and left.actor.guid and right.actor.guid and left.actor.guid ~= right.actor.guid then merged.actor = copy(left.actor.guid < right.actor.guid and left.actor or right.actor) end
        if left.originGuid ~= right.originGuid then merged.originGuid = left.originGuid < right.originGuid and left.originGuid or right.originGuid end
        if left.recordedByGuid ~= right.recordedByGuid then merged.recordedByGuid = left.recordedByGuid < right.recordedByGuid and left.recordedByGuid or right.recordedByGuid end
        if left.timestamp ~= right.timestamp then merged.timestamp = math.min(left.timestamp, right.timestamp) end
    end
    merged.capturedAt = math.min(left.capturedAt, right.capturedAt)
    merged.updatedAt = math.max(left.updatedAt, right.updatedAt)
    merged.revision = math.max(left.revision or 1, right.revision or 1)
    merged.eventId = preferred.eventId
    merged.identityKey = preferred.identityKey
    merged.revisionId = self:_RevisionId(merged)
    return merged
end

function Store:_ResolveRankChains(guild)
    local direct = {}
    for _, eventId in ipairs(guild.order) do
        local event = guild.entries[eventId]
        if event and rankPair(event) and isDirect(event) then direct[#direct + 1] = event end
    end
    local changed = false
    for _, eventId in ipairs(guild.order) do
        local reconstructed = guild.entries[eventId]
        if reconstructed and reconstructed.type == "RANK_CHANGED" and reconstructed.resolutionState == "RECONSTRUCTED" and rankPair(reconstructed) then
            local oldRank, newRank = reconstructed.data.oldRank, reconstructed.data.newRank
            local resolvedBy
            for _, first in ipairs(direct) do
                if first.subject.guid == reconstructed.subject.guid and first.data.oldRank == oldRank and first.data.newRank ~= newRank and inObservation(reconstructed, first.timestamp) then
                    for _, second in ipairs(direct) do
                        if second.eventId ~= first.eventId and second.subject.guid == reconstructed.subject.guid and second.data.oldRank == first.data.newRank and second.data.newRank == newRank and second.timestamp >= first.timestamp and inObservation(reconstructed, second.timestamp) then
                            local candidate = { first.eventId, second.eventId }; table.sort(candidate)
                            if not resolvedBy or table.concat(candidate, ":") < table.concat(resolvedBy, ":") then resolvedBy = candidate end
                        end
                    end
                end
            end
            if resolvedBy then
                reconstructed.resolutionState = "SUPERSEDED"
                reconstructed.supersededBy = resolvedBy
                reconstructed.updatedAt = now()
                reconstructed.revisionId = self:_RevisionId(reconstructed)
                changed = true
                log("INFO", "Reconstructed rank delta resolved by authoritative rank changes", { eventId = reconstructed.eventId, replacements = resolvedBy })
            end
        end
    end
    return changed
end

function Store:_Prune(guild, guildId)
    local root = self:_Root()
    local maximum = tonumber(root.retention.maxEntries) or self.maxEvents
    local current = now()
    if #guild.order <= maximum and guild.lastPrunedAt and current - guild.lastPrunedAt < 86400 then return 0 end
    local cutoff = current - (tonumber(root.retention.maxAgeSeconds) or self.maxAgeSeconds)
    local ordered = {}
    for _, eventId in ipairs(guild.order) do
        local event = guild.entries[eventId]
        if event and event.timestamp >= cutoff then ordered[#ordered + 1] = event end
    end
    table.sort(ordered, function(a, b)
        if a.timestamp ~= b.timestamp then return a.timestamp < b.timestamp end
        return a.eventId < b.eventId
    end)
    local removed = 0
    while #ordered > maximum do table.remove(ordered, 1); removed = removed + 1 end
    local keep, nextOrder = {}, {}
    for _, event in ipairs(ordered) do keep[event.eventId] = true; nextOrder[#nextOrder + 1] = event.eventId end
    for eventId in pairs(guild.entries) do if not keep[eventId] then guild.entries[eventId] = nil; if self.hiddenEventsLogged then self.hiddenEventsLogged[eventId] = nil end; removed = removed + 1 end end
    for alias, target in pairs(guild.aliases) do if not keep[target] then guild.aliases[alias] = nil; if self.hiddenEventsLogged then self.hiddenEventsLogged[alias] = nil end end end
    guild.order = nextOrder
    guild.lastPrunedAt = current
    if removed > 0 then log("INFO", "GuildLog retention pruned old events", { guildId = guildId, removed = removed, retained = #nextOrder, maxEntries = maximum }) end
    return removed
end

function Store:_ResolveId(guild, eventId)
    local seen = {}
    while guild.aliases[eventId] and not seen[eventId] do seen[eventId] = true; eventId = guild.aliases[eventId] end
    return eventId
end

function Store:_MergeInto(guild, incoming)
    local matchId = self:_FindMatch(guild, incoming)
    if not matchId then
        guild.entries[incoming.eventId] = incoming
        guild.order[#guild.order + 1] = incoming.eventId
        return incoming, true, false
    end
    local existing = guild.entries[matchId]
    local merged = self:_MergeEvents(existing, incoming)
    local oldRevision = existing.revisionId
    local oldState = existing.resolutionState
    local oldId = existing.eventId
    local oldTimestamp, oldCapture = existing.timestamp, existing.capturedAt
    if merged.eventId ~= oldId then
        guild.entries[oldId] = nil
        guild.aliases[oldId] = merged.eventId
        for alias, target in pairs(guild.aliases) do if target == oldId then guild.aliases[alias] = merged.eventId end end
        for index, value in ipairs(guild.order) do if value == oldId then guild.order[index] = merged.eventId; break end end
    end
    guild.entries[merged.eventId] = merged
    if merged.timestamp ~= oldTimestamp or merged.capturedAt ~= oldCapture then
        for index, value in ipairs(guild.order) do if value == merged.eventId then table.remove(guild.order, index); break end end
        guild.order[#guild.order + 1] = merged.eventId
    end
    if oldRevision == merged.revisionId then return merged, false, false end
    return merged, true, oldState == "RECONSTRUCTED" and merged.resolutionState == "AUTHORITATIVE"
end

function Store:CanView(event, viewerAccount, viewerCharacter)
    if type(event) ~= "table" then return false end
    if event.sensitive == true or event.type == "OFFICER_NOTE_CHANGED" then
        local api = _G.C_GuildInfo and _G.C_GuildInfo.CanViewOfficerNote or _G.CanViewOfficerNote
        if type(api) ~= "function" then logHidden(event, "OFFICER_NOTE_PERMISSION_UNAVAILABLE"); return false end
        local ok, allowed = pcall(api)
        if not ok or allowed ~= true then logHidden(event, "OFFICER_NOTE_PERMISSION_DENIED"); return false end
    end
    if event.requiredPermission then
        local manager = HolyStorm.GuildManagement
        if not manager or not manager.Can or not manager:Can(event.requiredPermission, viewerAccount, viewerCharacter, event) then logHidden(event, "REQUIRED_PERMISSION_DENIED"); return false end
    end
    return true
end

function Store:List(guildId, options)
    options = options or {}
    local guild = self:_Guild(guildId, false)
    if not guild then return {} end
    local output = {}
    for _, eventId in ipairs(guild.order) do
        local event = guild.entries[eventId]
        if event and event.resolutionState ~= "SUPERSEDED" and self:CanView(event, options.viewerAccount, options.viewerCharacter) then
            if not options.from or event.timestamp >= options.from then
                if not options.to or event.timestamp <= options.to then output[#output + 1] = copy(event) end
            end
        end
    end
    table.sort(output, function(a, b) if a.timestamp ~= b.timestamp then return a.timestamp > b.timestamp end; return a.eventId > b.eventId end)
    return output
end

function Store:GetEvent(guildId, eventId)
    local guild = self:_Guild(guildId, false)
    if not guild then return nil end
    local canonical = self:_ResolveId(guild, eventId)
    local event = guild.entries[canonical]
    return event and copy(event) or nil
end

function Store:_CommitEvents(guildId, eventInputs, options)
    local guild = self:_Guild(guildId, true)
    if not guild then return false, "NO_GUILD" end
    local module = HolyStorm.GuildLog
    local prepared = {}
    for _, original in ipairs(eventInputs or {}) do
        if type(original) ~= "table" then return false, "INVALID_EVENT" end
        local input = copy(original)
        local descriptor = module and module:GetEventType(input.type or input.eventType)
        if not options or options.localSubmit ~= false then
            if not descriptor then log("WARN", "GuildLog rejected an unregistered local event type", { type = input.type or input.eventType }); return false, "UNREGISTERED_EVENT_TYPE" end
            if descriptor.sensitive == true then input.sensitive = true end
            if descriptor.requiredPermission and input.requiredPermission == nil then input.requiredPermission = descriptor.requiredPermission end
        end
        local event, reason = self:_NewEvent(guildId, input, descriptor)
        if not event then log("WARN", "GuildLog rejected invalid event", { reason = reason, type = input.type or input.eventType }); return false, reason end
        if not self:CanView(event) then
            log("WARN", "GuildLog rejected permission-sensitive event", { type = event.type, guildId = guildId, requiredPermission = event.requiredPermission })
            return false, "PERMISSION_DENIED"
        end
        prepared[#prepared + 1] = event
    end
    local accepted, changedEvents, duplicates, reconciled = {}, {}, 0, 0
    for _, event in ipairs(prepared) do
        local merged, changed, upgraded = self:_MergeInto(guild, event)
        if changed then
            accepted[#accepted + 1] = merged.eventId
            changedEvents[#changedEvents + 1] = merged
            if upgraded then reconciled = reconciled + 1 end
            log("DEBUG", "GuildLog event accepted", { eventId = merged.eventId, eventType = merged.type, guildId = guildId, resolutionState = merged.resolutionState })
        else
            duplicates = duplicates + 1
            log("DEBUG", "Duplicate GuildLog event merged or discarded", { eventId = merged.eventId, eventType = merged.type, guildId = guildId })
        end
    end
    if self:_ResolveRankChains(guild) then
        for _, eventId in ipairs(guild.order) do
            local event = guild.entries[eventId]
            if event and event.resolutionState == "SUPERSEDED" then
                local found
                for index, changed in ipairs(changedEvents) do if changed.eventId == eventId then changedEvents[index], found = event, true; break end end
                if not found then changedEvents[#changedEvents + 1] = event end
            end
        end
    end
    local retention = self:_Root().retention
    if #guild.order > (tonumber(retention.maxEntries) or self.maxEvents) or not guild.lastPrunedAt or now() - guild.lastPrunedAt >= 86400 then
        if HolyStorm.Tasks and HolyStorm.Tasks:GetTaskType("GuildLog.Prune") then
            HolyStorm.Tasks:Queue("GuildLog.Prune", { mergeKey = guildId, delay = .05, priority = 72, triggerSource = "GUILD_LOG_RETENTION", metadata = { guildId = guildId } })
        else
            self:_Prune(guild, guildId)
        end
    end
    if #changedEvents > 0 then
        HolyStorm.Events:Emit("HS_GUILD_LOG_UPDATED", guildId, changedEvents)
        if not options or options.localSubmit ~= false then
            for _, event in ipairs(changedEvents) do
                if not event.sensitive then HolyStorm.Sync:Publish("guildLog", event.eventId, "GUILD_LOG_EVENT") end
            end
        end
    end
    if reconciled > 0 then log("INFO", "GuildLog reconstructed event reconciled", { guildId = guildId, count = reconciled }) end
    if duplicates > 0 then log("DEBUG", "GuildLog duplicate events merged", { guildId = guildId, count = duplicates }) end
    return true, { accepted = accepted, changed = #changedEvents, duplicates = duplicates, reconciled = reconciled }
end

function Store:Submit(guildId, input)
    if type(guildId) == "table" and input == nil then input, guildId = guildId, guildId.guildId end
    if type(input) ~= "table" then return false, "INVALID_EVENT" end
    local current = HolyStorm.Data.GuildStore:GetCurrent()
    local target = guildId or input.guildId or (current and current.id)
    if not current or not target then return false, "NO_GUILD" end
    if target ~= current.id then return false, "GUILD_MISMATCH" end
    return self:_CommitEvents(target, { input }, { localSubmit = true })
end

function Store:SubmitMany(guildId, inputs)
    if type(inputs) ~= "table" then return false, "INVALID_EVENTS" end
    return self:_CommitEvents(guildId, inputs, { localSubmit = true })
end

function Store:SetRosterSnapshot(guildId, snapshot)
    if type(snapshot) ~= "table" then return false end
    local guild = self:_Guild(guildId, true)
    if not guild then return false end
    guild.rosterSnapshot = copy(snapshot)
    return true
end

function Store:GetRosterSnapshot(guildId)
    local guild = self:_Guild(guildId, false)
    return guild and guild.rosterSnapshot and copy(guild.rosterSnapshot) or nil
end

function Store:Import(eventId, incoming, metadata)
    if type(incoming) ~= "table" then return false, "INVALID_PAYLOAD" end
    local guildId = incoming.guildId
    local valid, reason = self:ValidateEvent(incoming)
    if not valid or not validId(eventId) or incoming.eventId ~= eventId and (not self:_Guild(guildId, false) or self:_ResolveId(self:_Guild(guildId, false), eventId) ~= incoming.eventId) then
        log("WARN", "GuildLog sync rejected invalid event", { eventId = eventId, reason = reason or "OBJECT_ID_MISMATCH" })
        return false, reason or "OBJECT_ID_MISMATCH"
    end
    if metadata and (metadata.guildId ~= guildId or metadata.objectId ~= eventId or metadata.owner ~= incoming.originGuid or metadata.revisionID ~= incoming.revisionId) then
        log("WARN", "GuildLog sync rejected mismatched metadata", { eventId = eventId, guildId = guildId })
        return false, "METADATA_MISMATCH"
    end
    local ok, result = self:_CommitEvents(guildId, { incoming }, { localSubmit = false })
    if not ok then return false, result end
    log("DEBUG", "GuildLog sync accepted", { eventId = eventId, guildId = guildId, changed = result.changed })
    return true, result.changed == 0 and "NOOP" or result
end

function Store:GetMetadata(eventId)
    -- Event IDs are opaque and independent of the guild key, so resolve them
    -- through the small guild index while keeping one sync object per event.
    local root = self:_Root()
    if not root or not eventId then return nil end
    for id, guild in pairs(root.guilds) do
        local canonical = self:_ResolveId(guild, eventId)
        local event = guild.entries[canonical]
        if event and not event.sensitive then
            return { objectId = eventId, owner = event.originGuid, origin = event.originGuid, version = 1, revisionID = event.revisionId, updatedAt = event.updatedAt, guildId = id }
        end
    end
end

function Store:ListMetadata(since)
    local result, root = {}, self:_Root()
    if not root then return result end
    for guildId, guild in pairs(root.guilds) do
        for eventId, event in pairs(guild.entries) do
            if not event.sensitive and (tonumber(event.updatedAt) or 0) > (tonumber(since) or 0) then
                result[#result + 1] = { objectId = eventId, owner = event.originGuid, origin = event.originGuid, version = 1, revisionID = event.revisionId, updatedAt = event.updatedAt, guildId = guildId }
            end
        end
    end
    table.sort(result, function(a, b) if a.updatedAt ~= b.updatedAt then return a.updatedAt < b.updatedAt end; return a.objectId < b.objectId end)
    return result
end

function Store:ConfigureRetention(maxEntries, maxAgeSeconds)
    local root = self:_Root()
    if not root then return false, "PERSISTENCE_UNAVAILABLE" end
    maxEntries, maxAgeSeconds = tonumber(maxEntries), tonumber(maxAgeSeconds)
    if not maxEntries or maxEntries < 100 or maxEntries > 20000 or not maxAgeSeconds or maxAgeSeconds < 30 * 86400 or maxAgeSeconds > 3650 * 86400 then return false, "INVALID_RETENTION" end
    root.retention.maxEntries, root.retention.maxAgeSeconds = math.floor(maxEntries), math.floor(maxAgeSeconds)
    for guildId in pairs(root.guilds) do self:SchedulePrune(guildId, "RETENTION_CONFIGURED") end
    return true
end

function Store:SchedulePrune(guildId, reason)
    if not self:_Guild(guildId, false) then return false end
    if HolyStorm.Tasks and HolyStorm.Tasks:GetTaskType("GuildLog.Prune") then
        return HolyStorm.Tasks:Queue("GuildLog.Prune", { mergeKey = guildId, delay = .05, priority = 72, triggerSource = reason or "GUILD_LOG_RETENTION", metadata = { guildId = guildId } }) ~= nil
    end
    return self:Prune(guildId)
end

function Store:Prune(guildId)
    local guild = self:_Guild(guildId, false)
    if not guild then return false end
    guild.lastPrunedAt = nil
    self:_Prune(guild, guildId)
    HolyStorm.Events:Emit("HS_GUILD_LOG_UPDATED", guildId, {})
    return true
end

function Store:PruneAll()
    local root = self:_Root(); if not root then return false end
    for guildId in pairs(root.guilds) do self:Prune(guildId) end
    return true
end

function Store:GetGuildIds()
    local result, root = {}, self:_Root()
    for guildId in pairs(root and root.guilds or {}) do result[#result + 1] = guildId end
    table.sort(result)
    return result
end

function Store:GetRetention()
    local root = self:_Root()
    return root and copy(root.retention) or nil
end

function Store:ResolveEventId(guildId, eventId)
    local guild = self:_Guild(guildId, false)
    return guild and self:_ResolveId(guild, eventId) or eventId
end

HolyStorm.Data.GuildLogStore = Store
