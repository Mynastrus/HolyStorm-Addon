local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Positions")

local Positions = {
    version = addonVersion,
    remote = {},
    ownState = nil,
    pendingSnapshot = nil,
    currentGuildId = nil,
    sequence = 0,
    staleTimeout = 90,
    initialized = false,
    featureActive = false,
    movement = {
        active = false,
        bucket = "stationary",
        speed = nil,
        nextEligible = 0,
        lastSent = 0,
        lastCapture = nil,
    },
    metrics = { published = 0, received = 0, coalesced = 0, droppedStale = 0, rejected = 0 },
}

local function now() return HolyStorm.Utils.Now() end
local function clock() return type(GetTime) == "function" and GetTime() or 0 end
local function finite(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end
local function copy(value) return HolyStorm.Utils.DeepCopy(value) end
local function log(level, message, context)
    HolyStorm.Logger:Write(level, "Positions", "live", message, context)
end
local function stateVersion(entry)
    if not entry or not finite(entry.timestamp) or not finite(entry.sequence) then return nil end
    return math.floor(tonumber(entry.timestamp)) * 1000 + (tonumber(entry.sequence) % 1000)
end

function Positions:GetSettings()
    if not self.settingsRegistered then
        HolyStorm.DataManager:RegisterArea("positions", "profile", {
            schemaVersion = 1,
            share = true,
            display = true,
            worldMapEnabled = true,
            minimapEnabled = false,
            currentMapOnly = false,
            worldMapSize = 24,
            minimapSize = 18,
            markerStyle = "CLASS",
        })
        local legacy = HolyStorm.DataManager:GetArea("positions")
        local definitions = {
            {key="share",default=true,scopes={"guild","allGuilds"},scope="guild",type="toggle",nameKey="SHARE",descriptionKey="SHARE_DESC",uiOrder=1,slash={path={"positions","share"}}},
            {key="display",default=true,type="toggle",nameKey="DISPLAY_MEMBERS",descriptionKey="DESCRIPTION",uiOrder=2,slash={path={"positions","display"}}},
            {key="worldMapEnabled",default=true,type="toggle",nameKey="WORLD_MAP",descriptionKey="DESCRIPTION",uiOrder=3,slash={path={"positions","world-map"}}},
            {key="minimapEnabled",default=true,type="toggle",nameKey="MINIMAP",descriptionKey="DESCRIPTION",uiOrder=4,slash={path={"positions","minimap"}}},
            {key="currentMapOnly",default=false,type="toggle",nameKey="CURRENT_MAP_ONLY",descriptionKey="DESCRIPTION",uiOrder=5,slash={path={"positions","current-map-only"}}},
            {key="worldMapSize",default=24,type="range",nameKey="WORLD_SIZE",descriptionKey="DESCRIPTION",uiOrder=6},
            {key="minimapSize",default=18,type="range",nameKey="MINIMAP_SIZE",descriptionKey="DESCRIPTION",uiOrder=7},
            {key="markerStyle",default="CLASS",type="select",nameKey="MARKER_STYLE",descriptionKey="DESCRIPTION",uiOrder=8},
        }
        for _, definition in ipairs(definitions) do
            local entry=definition
            local id="positions."..entry.key
            HolyStorm.Options:RegisterSetting({id=id,module="Positions",type=entry.type,default=entry.default,scope=entry.scope or"account",scopes=entry.scopes or{"account"},nameKey=entry.nameKey,descriptionKey=entry.descriptionKey,uiOrder=entry.uiOrder,name=L[entry.nameKey],description=L[entry.descriptionKey],group="Positions",slash=entry.slash,setter=function(value)return HolyStorm.GuildPositions:SetSetting(entry.key,value)end,validate=entry.key=="worldMapSize"and function(v)return type(v)=="number"and v>=14 and v<=48 and v%1==0 end or entry.key=="minimapSize"and function(v)return type(v)=="number"and v>=12 and v<=36 and v%1==0 end or nil})
            HolyStorm.Settings:ImportLegacy(id,legacy[entry.key],entry.key=="share"and"allGuilds"or"account")
        end
        self.settingsRegistered = true
    end
    local settings=HolyStorm.DataManager:GetArea("positions")
    for key in pairs(settings)do if key~="schemaVersion"then local value=HolyStorm.Settings:Get("positions."..key);if value~=nil then settings[key]=value end end end
    return settings
end

function Positions:IsEnabled()
    return not HolyStorm.Policy or HolyStorm.Policy:IsGuildModuleEnabled("positions")
end

function Positions:GetGuild()
    return HolyStorm.Data.GuildStore:GetCurrent()
end

function Positions:CanShare()
    local guild = self:GetGuild()
    return self.featureActive == true
        and self:GetSettings().share == true
        and self:IsEnabled()
        and guild ~= nil
        and guild.id ~= nil
        and (type(IsInGuild) ~= "function" or IsInGuild())
end

function Positions:CanDisplay()
    return self.featureActive == true
        and self:GetSettings().display == true
        and self:IsEnabled()
end

function Positions:SetSetting(key, value)
    local settings = self:GetSettings()
    if key == "worldMapSize" then
        value = math.max(14, math.min(48, tonumber(value) or 24))
    elseif key == "minimapSize" then
        value = math.max(12, math.min(36, tonumber(value) or 18))
    elseif key == "markerStyle" then
        value = value == "GUILD" and "GUILD" or "CLASS"
    elseif key == "share" or key == "display" or key == "worldMapEnabled"
        or key == "minimapEnabled" or key == "currentMapOnly" then
        value = value == true
    else
        return false
    end

    local oldValue = settings[key]
    local stored,reason = HolyStorm.Settings:Set("positions."..key,value)
    if not stored then return false,reason end
    local newValue=self:GetSettings()[key]
    if oldValue == newValue then return true end
    value=newValue

    if key == "share" and not value then
        local previouslyShared = self.ownState ~= nil or self.pendingSnapshot ~= nil
        local withdrawal
        if previouslyShared and self.ownState and not self.ownState.withdrawn then
            self.sequence = self.sequence + 1
            withdrawal = {
                characterUUID = UnitGUID("player"),
                guildId = self.ownState.guildId,
                timestamp = now(),
                sequence = self.sequence,
                withdrawn = true,
            }
        end
        self.pendingSnapshot = nil
        self.ownState = withdrawal
        self.movement.lastCapture = nil
        self.movement.active = false
        HolyStorm.Tasks:CancelRecurring("Position.MovementSample")
        if withdrawal and self.featureActive then
            HolyStorm.Sync:Publish("guild-position", withdrawal.characterUUID, "POSITION_WITHDRAWN")
        end
        log("INFO", "Guild position sharing disabled", { withdrawalSent = withdrawal ~= nil })
    elseif key == "share" and value then
        self.ownState = nil
        log("INFO", "Guild position sharing enabled", { enabled = true })
        self:QueueCapture("PRIVACY_ENABLED", true, 0.2)
    end

    HolyStorm.Events:Emit("HS_POSITION_SETTINGS_CHANGED", key, value)
    return true
end

function Positions:IsValidMap(mapID)
    return HolyStorm.MapLinks:IsValidMapID(mapID)
end

function Positions:Capture()
    if not self:CanShare() then return nil, "PRIVACY_OR_POLICY" end
    local guild = self:GetGuild()
    local mapID, x, y = HolyStorm.MapLinks:GetPlayerPosition()
    if not mapID or not self:IsValidMap(mapID) or not HolyStorm.MapLinks:IsValidCoordinate(mapID, x, y) then
        log("DEBUG", "No valid local position available", { mapID = mapID, x = x, y = y })
        return nil, "POSITION_UNAVAILABLE"
    end
    local timestamp = now()
    if self.lastTimestamp and timestamp <= self.lastTimestamp then timestamp = self.lastTimestamp + 0.001 end
    self.lastTimestamp = timestamp
    return {
        characterUUID = UnitGUID("player"),
        guildId = guild.id,
        mapID = tonumber(mapID),
        x = tonumber(x),
        y = tonumber(y),
        timestamp = timestamp,
        sequence = self.sequence + 1,
        moving = self.movement.active == true,
    }
end

function Positions:GetMovementPolicy()
    if not self.movement.active then return "stationary", nil, nil end
    if type(GetUnitSpeed) ~= "function" then return "normal", nil, 5 end
    local ok, bucket, speed, interval = pcall(function()
        local value = tonumber(GetUnitSpeed("player"))
        if not value or value <= 0.05 then return "stationary", value, nil end
        if value < 4 then return "slow", value, 8 end
        if value < 10 then return "normal", value, 5 end
        return "fast", value, 3
    end)
    if not ok then return "normal", nil, 5 end
    return bucket, speed, interval
end

function Positions:HasMeaningfulChange(snapshot, previous)
    if not previous or previous.withdrawn then return true end
    if snapshot.mapID ~= previous.mapID or snapshot.moving ~= (previous.moving == true) then return true end
    local dx, dy = snapshot.x - previous.x, snapshot.y - previous.y
    return dx * dx + dy * dy >= 0.0000001225
end

function Positions:SampleMovement(reason, force)
    if not self:CanShare() then return false, "PRIVACY_OR_POLICY" end
    local bucket, speed, interval = self:GetMovementPolicy()
    self.movement.bucket, self.movement.speed = bucket, speed
    if not force and (not interval or clock() < self.movement.nextEligible) then return false, "NOT_DUE" end

    local snapshot, err = self:Capture()
    if not snapshot then return false, err end
    local previous = self.pendingSnapshot or self.ownState
    if not self:HasMeaningfulChange(snapshot, previous) then return false, "UNCHANGED" end

    self.sequence = snapshot.sequence
    self.pendingSnapshot = snapshot
    self.movement.lastCapture = copy(snapshot)
    self.movement.nextEligible = clock() + (interval or 3)
    local _, status = HolyStorm.Tasks:Queue("Position.Publish", {
        mergeKey = snapshot.characterUUID,
        startupPhase = 4,
        delay = 0.15,
        priority = 110,
        triggerSource = reason or "MOVEMENT",
    })
    if status == "MERGED" then self.metrics.coalesced = self.metrics.coalesced + 1 end
    return true, status
end

function Positions:QueueCapture(reason, force, delay)
    if not self.featureActive then return nil, "MODULE_DISABLED" end
    self.captureForce = self.captureForce or force == true
    self.captureReason = reason or self.captureReason
    return HolyStorm.Tasks:Queue("Position.Capture", {
        mergeKey = UnitGUID("player") or "player",
        startupPhase = 4,
        delay = delay or 0,
        priority = 108,
        triggerSource = reason or "CAPTURE",
    })
end

function Positions:RunCapture()
    if not self.featureActive then return false, "MODULE_DISABLED" end
    local force, reason = self.captureForce, self.captureReason
    self.captureForce, self.captureReason = false, nil
    return self:SampleMovement(reason, force)
end

function Positions:RunPublish()
    if not self.featureActive or not self:CanShare() then
        self.pendingSnapshot = nil
        return false, "PRIVACY_OR_POLICY"
    end
    local snapshot = self.pendingSnapshot
    if not snapshot then return false, "NO_POSITION" end
    self.pendingSnapshot = nil
    self.ownState = snapshot
    self.movement.lastSent = clock()
    self.metrics.published = self.metrics.published + 1
    local ok, reason = HolyStorm.Sync:Publish("guild-position", snapshot.characterUUID, "POSITION_LIVE_UPDATE")
    if not ok then log("WARN", "Position publish could not be queued", { reason = reason }) end
    HolyStorm.Events:Emit("HS_OWN_POSITION_UPDATED", copy(snapshot))
    return ok, reason
end

function Positions:StartMovement()
    if not self.featureActive or not self:CanShare() then return false end
    self.movement.active = true
    self.movement.bucket = "normal"
    if not self.movementScheduled then
        self.movementScheduled = HolyStorm.Tasks:ScheduleRecurring("Position.MovementSample", 1, function()
            return Positions:SampleMovement("MOVEMENT_SAMPLE", false)
        end, { priority = 108, cooldown = 1, module = "Positions", combat = "allow" })
    end
    self:QueueCapture("MOVEMENT_STARTED", false, 0.4)
    return true
end

function Positions:StopMovement()
    if not self.featureActive then return false end
    self.movement.active = false
    self.movement.bucket = "stationary"
    self.movement.speed = 0
    self.movementScheduled = false
    HolyStorm.Tasks:CancelRecurring("Position.MovementSample")
    self:QueueCapture("MOVEMENT_STOPPED", true, 0)
    return true
end

function Positions:IsStale(entry)
    if not entry or not finite(entry.timestamp) then return true end
    if tonumber(entry.timestamp) > now() + 300 then return true end
    if entry.withdrawn then return now() - tonumber(entry.timestamp) > self.staleTimeout end
    return entry.moving == true and now() - tonumber(entry.timestamp) > self.staleTimeout
end

function Positions:IsRosterOnline(characterUUID)
    local guild = self:GetGuild()
    local member = guild and guild.roster and guild.roster[characterUUID]
    return member ~= nil and member.online == true
end

function Positions:IsRenderable(entry)
    local guild = self:GetGuild()
    return self:CanDisplay()
        and entry ~= nil
        and entry.guildId == (guild and guild.id)
        and not entry.withdrawn
        and not self:IsStale(entry)
        and self:IsRosterOnline(entry.characterUUID)
end

function Positions:Get(characterUUID)
    local entry = self.remote[characterUUID]
    return self:IsRenderable(entry) and entry or nil
end

function Positions:GetVisible()
    local result = {}
    if not self:CanDisplay() then return result end
    for _, entry in pairs(self.remote) do
        if self:IsRenderable(entry) then result[#result + 1] = entry end
    end
    table.sort(result, function(a, b) return a.characterUUID < b.characterUUID end)
    return result
end

function Positions:Clear(reason)
    local changed = next(self.remote) ~= nil
    self.remote = {}
    if changed then
        HolyStorm.Events:Emit("HS_GUILD_POSITIONS_CLEARED", reason or "CLEAR")
    end
end

function Positions:ReconcileRoster()
    local guild = self:GetGuild()
    local guildId = guild and guild.id
    if guildId ~= self.currentGuildId then
        self:Clear("GUILD_CHANGED")
        self.ownState, self.pendingSnapshot = nil, nil
        self.currentGuildId = guildId
        log("INFO", "Guild position cache changed guild context", { guildId = guildId })
    end
    if not guildId or not self:IsEnabled() then
        self:Clear(not guildId and "NO_GUILD" or "MODULE_DISABLED")
        return true
    end

    local removed = 0
    for guid, entry in pairs(self.remote) do
        if entry.guildId ~= guildId or not self:IsRosterOnline(guid) or self:IsStale(entry) then
            self.remote[guid] = nil
            removed = removed + 1
            if self:IsStale(entry) then self.metrics.droppedStale = self.metrics.droppedStale + 1 end
        end
    end
    if removed > 0 then
        HolyStorm.Events:Emit("HS_GUILD_POSITIONS_RECONCILED", removed)
        self:RefreshMap()
    end
    return true
end

function Positions:ValidatePayload(payload, meta, id)
    if type(payload) ~= "table" then return false, "INVALID_PAYLOAD" end
    local allowed = {
        characterUUID = true, guildId = true, timestamp = true, sequence = true,
        withdrawn = true, mapID = true, x = true, y = true, moving = true,
    }
    for key in pairs(payload) do if not allowed[key] then return false, "NON_COMPACT_PAYLOAD" end end

    local guild = self:GetGuild()
    local member = guild and guild.roster and guild.roster[id]
    local version = stateVersion(payload)
    if type(payload.characterUUID) ~= "string" or payload.characterUUID ~= id or #payload.characterUUID > 160
        or not guild or payload.guildId ~= guild.id or type(meta) ~= "table" or meta.owner ~= id
        or not finite(payload.timestamp) or ((payload.withdrawn == true or payload.moving == true)
            and payload.timestamp < now() - self.staleTimeout)
        or payload.timestamp > now() + 300 or not finite(payload.sequence)
        or payload.sequence < 1 or payload.sequence % 1 ~= 0 or not finite(meta.version)
        or tonumber(meta.version) ~= version or not member or member.online ~= true then
        return false, "INVALID_POSITION"
    end

    if payload.withdrawn == true then
        if payload.mapID ~= nil or payload.x ~= nil or payload.y ~= nil or payload.moving ~= nil then
            return false, "INVALID_WITHDRAWAL"
        end
        return true
    end
    if payload.withdrawn ~= nil and payload.withdrawn ~= false then return false, "INVALID_WITHDRAWAL" end
    if payload.moving ~= nil and type(payload.moving) ~= "boolean" then return false, "INVALID_MOVEMENT_STATE" end
    if not self:IsValidMap(payload.mapID) or not HolyStorm.MapLinks:IsValidCoordinate(payload.mapID, payload.x, payload.y) then
        return false, "INVALID_COORDINATE"
    end
    return true
end

function Positions:Import(id, payload, meta, senderId, sender)
    local current = self.remote[id]
    local incomingVersion = stateVersion(payload)
    local currentVersion = stateVersion(current)
    if currentVersion and incomingVersion and currentVersion >= incomingVersion then return false, "STALE" end

    if payload.withdrawn then
        local hadPosition = current ~= nil
        self.remote[id] = nil
        if hadPosition then
            HolyStorm.Events:Emit("HS_GUILD_POSITIONS_CLEARED", "PRIVACY_WITHDRAWAL")
            self:RefreshMap(id)
        end
        return true
    end

    local entry = copy(payload)
    entry.moving = entry.moving == true
    entry.source = senderId == id and "owner" or "relay"
    entry.receivedFrom = sender
    entry.receivedAt = now()
    self.remote[id] = entry
    self.metrics.received = self.metrics.received + 1
    HolyStorm.Events:Emit("HS_GUILD_POSITION_UPDATED", id, copy(entry))
    self:RefreshMap(id)
    return true
end

function Positions:RefreshMap(characterUUID)
    if characterUUID then
        self.pendingMapRefresh = self.pendingMapRefresh or {}
        self.pendingMapRefresh[characterUUID] = true
    else
        self.refreshAllMap = true
    end
    HolyStorm.Tasks:Queue("Position.MapRefresh", {
        mergeKey = "guild-positions",
        startupPhase = 4,
        priority = 112,
        triggerSource = "POSITION_CHANGED",
        metadata = {},
    })
end

function Positions:Discover()
    if not self:CanDisplay() or not self:GetGuild() then return false end
    return HolyStorm.Sync:Discover("guild-position", nil, {
        channel = "GUILD",
        scope = self:GetGuild().id,
        reason = "POSITION_INITIAL_DISCOVERY",
        priority = 110,
        delay = 0.5,
        startupPhase = 4,
    })
end

function Positions:GetCharacterSummary(characterUUID)
    local characterUI = HolyStorm.CharacterUI
    local context = characterUI and characterUI:ResolveContext(characterUUID)
    if not context then
        local record = HolyStorm.Data.CharacterStore:Get(characterUUID) or {}
        local guild = self:GetGuild()
        local member = guild and guild.roster and guild.roster[characterUUID] or {}
        return {
            characterUUID = characterUUID,
            name = record.fullName or record.name or member.name or characterUUID,
            class = record.class or member.class,
            classFile = record.classFile or member.classFile,
            rank = member.rank,
            status = member.status,
            online = member.online == true,
            itemLevel = tonumber(record.itemLevel),
        }
    end

    local record, member = context.record or {}, context.member or {}
    local main = HolyStorm.TwinkCore and HolyStorm.TwinkCore:GetRosterIdentity(characterUUID, context.guild)
    local mainGuid = main and (main.accountMain or main.guildMain)
    local mainContext = mainGuid and characterUI:ResolveContext(mainGuid)
    local raid = characterUI:GetSnapshot(characterUUID, "raid")
    local raidProgress
    if type(raid) == "table" and raid.snapshotVersion == 3 and raid.catalogReady == true then
        if type(characterUI.GetBestCurrentRaidProgress) == "function" then
            raidProgress = characterUI:GetBestCurrentRaidProgress(raid)
        else
            raidProgress = characterUI:GetBestProgress(raid)
        end
    end
    local mythic = characterUI:GetSnapshot(characterUUID, "mythicPlus")
    local currentSeason
    if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" then
        local ok, season = pcall(C_MythicPlus.GetCurrentSeason)
        if ok then currentSeason = tonumber(season) end
    end
    local mythicScore
    if type(mythic) == "table" and mythic.schemaVersion == 5 and mythic.snapshotVersion == 5
        and currentSeason and tonumber(mythic.seasonId) == currentSeason then
        mythicScore = tonumber(mythic.overallScore)
    end
    local role = record.profile and record.profile.preferredRole
        or record.stats and record.stats.spec and record.stats.spec.role
    return {
        characterUUID = characterUUID,
        name = context.fullName or context.name,
        class = context.className,
        classFile = context.classFile,
        race = record.race,
        role = role,
        rank = member.rank,
        status = member.status,
        online = member.online == true,
        itemLevel = tonumber(record.itemLevel),
        mythicScore = mythicScore,
        raidProgress = raidProgress,
        mainGuid = mainGuid,
        mainName = mainContext and (mainContext.fullName or mainContext.name),
        isShadowMain = main and main.isShadowMain,
    }
end

function Positions:GetDiagnostics()
    local remote = {}
    for guid, entry in pairs(self.remote) do
        local render = HolyStorm.GuildPositionMap and HolyStorm.GuildPositionMap:GetRenderState(guid) or {}
        remote[#remote + 1] = {
            characterUUID = guid, mapID = entry.mapID, x = entry.x, y = entry.y,
            timestamp = entry.timestamp, sequence = entry.sequence, source = entry.source,
            receivedFrom = entry.receivedFrom, stale = self:IsStale(entry), online = self:IsRosterOnline(guid),
            worldPin = render.worldPin == true, minimapPin = render.minimapPin == true,
            viewedMapID = render.viewedMapID, transform = render.transform,
            transformedX = render.transformedX, transformedY = render.transformedY, reason = render.reason,
        }
    end
    table.sort(remote, function(a, b) return a.characterUUID < b.characterUUID end)
    return {
        sharing = self:GetSettings().share,
        enabled = self:IsEnabled(),
        guildId = self.currentGuildId,
        own = copy(self.ownState or self.movement.lastCapture),
        movement = copy(self.movement),
        metrics = copy(self.metrics),
        remote = remote,
        staleTimeout = self.staleTimeout,
    }
end

function Positions:Initialize()
    if self.initialized then return true end
    self:GetSettings()
    HolyStorm.Tasks:RegisterTaskType("Position.Capture", {
        name = L["TASK_POSITION_CAPTURE"], localizedNameKey = "TASK_POSITION_CAPTURE",
        module = "Positions", priority = 108, executionMode = "MERGE_BY_KEY",
        conditions = { "PLAYER_READY", "NOT_LOADING", "NOT_ZONING", "GUILD_AVAILABLE" },
        execute = function() return Positions:RunCapture() end,
    })
    HolyStorm.Tasks:RegisterTaskType("Position.Publish", {
        name = L["TASK_POSITION_PUBLISH"], localizedNameKey = "TASK_POSITION_PUBLISH",
        module = "Positions", priority = 110, executionMode = "MERGE_BY_KEY",
        conditions = { "PLAYER_READY", "NOT_LOADING", "NOT_ZONING", "GUILD_AVAILABLE" },
        execute = function() return Positions:RunPublish() end,
    })
    HolyStorm.Tasks:RegisterTaskType("Position.Reconcile", {
        name = L["TASK_POSITION_RECONCILE"], localizedNameKey = "TASK_POSITION_RECONCILE",
        module = "Positions", priority = 105, executionMode = "UNIQUE",
        execute = function() return Positions:ReconcileRoster() end,
    })
    HolyStorm.Tasks:RegisterTaskType("Position.MapRefresh", {
        name = L["TASK_POSITION_MAP_REFRESH"], localizedNameKey = "TASK_POSITION_MAP_REFRESH",
        module = "Positions", priority = 112, executionMode = "MERGE_BY_KEY",
        execute = function()
            if Positions.featureActive and HolyStorm.GuildPositionMap then
                local pending, refreshAll = Positions.pendingMapRefresh or {}, Positions.refreshAllMap == true
                Positions.pendingMapRefresh, Positions.refreshAllMap = {}, false
                if refreshAll or next(pending) == nil then
                    HolyStorm.GuildPositionMap:Refresh()
                else
                    HolyStorm.GuildPositionMap:RefreshMany(pending)
                end
            end
            return true
        end,
    })
    HolyStorm.Tasks:RegisterTaskType("Position.InitialDiscovery", {
        name = L["TASK_POSITION_DISCOVERY"], localizedNameKey = "TASK_POSITION_DISCOVERY",
        module = "Positions", priority = 110, executionMode = "UNIQUE",
        conditions = { "PLAYER_READY", "NOT_LOADING", "NOT_ZONING", "GUILD_AVAILABLE" },
        execute = function() return Positions:Discover() end,
    })

    HolyStorm.Sync:RegisterDomain("guild-position", {
        live = true,
        catchUp = false,
        priority = 110,
        getChannel = function() return "GUILD" end,
        getMetadata = function(id)
            local entry = id == UnitGUID("player") and Positions.ownState or Positions.remote[id]
            if not entry or Positions:IsStale(entry) then return nil end
            if id == UnitGUID("player") and not entry.withdrawn and not Positions:CanShare() then return nil end
            if id ~= UnitGUID("player") and not Positions:IsRosterOnline(id) then return nil end
            return {
                objectId = id, owner = id, version = stateVersion(entry),
                updatedAt = entry.timestamp, source = "live-position",
            }
        end,
        listMetadata = function()
            local own = Positions.ownState
            if Positions:CanShare() and own and not own.withdrawn and not Positions:IsStale(own) then
                return { {
                    objectId = own.characterUUID, owner = own.characterUUID,
                    version = stateVersion(own), updatedAt = own.timestamp, source = "live-position",
                } }
            end
            return {}
        end,
        export = function(id)
            local own = id == UnitGUID("player") and Positions.ownState
            if not own or Positions:IsStale(own) then return nil end
            if own.withdrawn then return copy(own) end
            return Positions:CanShare() and copy(own) or nil
        end,
        validate = function(payload, meta, id)
            local valid, reason = Positions:ValidatePayload(payload, meta, id)
            if not valid then
                Positions.metrics.rejected = Positions.metrics.rejected + 1
                log("WARN", "Rejected guild position payload", { characterUUID = id, reason = reason })
            end
            return valid, reason
        end,
        authorize = function(_, meta, senderId, _, id)
            return type(meta) == "table" and meta.owner == id and senderId == id
        end,
        import = function(id, payload, meta, senderId, sender)
            return Positions:Import(id, payload, meta, senderId, sender)
        end,
        updateEvent = "HS_GUILD_POSITION_SYNCED",
    })
    self.initialized = true
    return true
end

function Positions:Enable()
    if self.featureActive then return true end
    self.featureActive = true
    HolyStorm.Events:Register("PLAYER_STARTED_MOVING", "positions-service", function() Positions:StartMovement() end)
    HolyStorm.Events:Register("PLAYER_STOPPED_MOVING", "positions-service", function() Positions:StopMovement() end)
    for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
        local eventName = event
        HolyStorm.Events:Register(eventName, "positions-service", function()
            Positions:QueueCapture(eventName, true, 0.2)
        end)
    end
    HolyStorm.Events:Register("PLAYER_ENTERING_WORLD", "positions-service", function()
        HolyStorm.Tasks:Queue("Position.Reconcile", {
            startupPhase = 4, delay = 2, priority = 105, triggerSource = "POSITION_LOGIN",
        })
        Positions:QueueCapture("POSITION_LOGIN", true, 3)
        HolyStorm.Tasks:Queue("Position.InitialDiscovery", {
            startupPhase = 4, delay = 4, priority = 110, triggerSource = "POSITION_LOGIN",
        })
        if type(GetUnitSpeed) == "function" then
            local ok, speed = pcall(GetUnitSpeed, "player")
            if ok and finite(speed) and speed > 0.05 then Positions:StartMovement() end
        end
    end)
    for _, event in ipairs({ "HS_ROSTER_UPDATED", "PLAYER_GUILD_UPDATE", "HS_PERMISSIONS_STATE_UPDATED" }) do
        local eventName = event
        HolyStorm.Events:Register(eventName, "positions-service", function()
            HolyStorm.Tasks:Queue("Position.Reconcile", {
                startupPhase = 4, delay = 0.2, priority = 105, triggerSource = eventName,
            })
            Positions:QueueCapture("GUILD_READY", true, 0.3)
            HolyStorm.Tasks:Queue("Position.InitialDiscovery", {
                startupPhase = 4, delay = 0.5, priority = 110, triggerSource = eventName,
            })
        end)
    end
    HolyStorm.Tasks:ScheduleRecurring("Position.Cleanup", 10, function()
        return Positions:ReconcileRoster()
    end, { priority = 115, cooldown = 10, module = "Positions", combat = "allow" })
    self.currentGuildId = self:GetGuild() and self:GetGuild().id
    self:ReconcileRoster()
    HolyStorm.Tasks:Queue("Position.Reconcile", { startupPhase = 4, delay = 2, priority = 105, triggerSource = "POSITION_ENABLE" })
    self:QueueCapture("POSITION_ENABLE", true, 3)
    HolyStorm.Tasks:Queue("Position.InitialDiscovery", { startupPhase = 4, delay = 4, priority = 110, triggerSource = "POSITION_ENABLE" })
    return true
end

function Positions:Disable()
    if not self.featureActive then return true end
    self.featureActive = false
    self.movement.active = false
    self.movementScheduled = false
    self.pendingSnapshot = nil
    self.pendingMapRefresh, self.refreshAllMap = {}, false
    self.ownState = nil
    self.movement.lastCapture = nil
    HolyStorm.Tasks:CancelRecurring("Position.Cleanup")
    HolyStorm.Tasks:CancelRecurring("Position.MovementSample")
    HolyStorm.Events:UnregisterOwner("positions-service")
    self:Clear("MODULE_DISABLED")
    if HolyStorm.GuildPositionMap then HolyStorm.GuildPositionMap:Disable() end
    return true
end

HolyStorm.GuildPositions = Positions
