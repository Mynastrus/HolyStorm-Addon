local root = (arg[0]:gsub("tools[/\\]test_positions.lua$", ""))
local featureRoot = root .. "LIVE/Holy_Storm_Positions/"
local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}; seen[value] = result
    for key, child in pairs(value) do result[copy(key, seen)] = copy(child, seen) end
    return result
end

local wall, mono = 1000, 100
local localGuid = "Player-Local"
local remoteGuid = "Player-Remote"
local pos = { map = 84, x = 0.2, y = 0.3 }
local speed = 0
local moduleEnabled = true
local inGuild = true
local guild = {
    id = "realm:guild",
    roster = {
        [localGuid] = { guid = localGuid, name = "Local-Realm", online = true },
        [remoteGuid] = { guid = remoteGuid, name = "Remote-Realm", online = true },
    },
}

local locale = setmetatable({}, { __index = function(_, key) return key end })
local settingsArea
local HolyStorm = {
    DataManager = {},
    Data = { GuildStore = {}, PlayerStore = {}, CharacterStore = {} },
    Policy = {},
    Utils = {},
    Tasks = { types = {}, queued = {}, pending = {}, recurring = {} },
    Sync = { domains = {}, published = {}, discovered = {} },
    Events = { handlers = {}, emitted = {} },
    Logger = { rows = {} },
    MapLinks = {},
}
local localSettings, settingDefinitions = {}, {}
HolyStorm.Settings = {
    Register = function(_, definition) settingDefinitions[definition.id] = definition; return true end,
    GetDefinition = function(_, id) return settingDefinitions[id] end,
    Get = function(_, id)
        local definition = settingDefinitions[id]
        if not definition then return nil end
        local value = localSettings[id]
        return value == nil and copy(definition.default) or copy(value)
    end,
    Set = function(_, id, value)
        if not settingDefinitions[id] then return false, "UNKNOWN_SETTING" end
        localSettings[id] = copy(value)
        return true
    end,
    ImportLegacy = function(self, id, value)
        if value == nil or localSettings[id] ~= nil then return false end
        return self:Set(id, value)
    end,
}
HolyStorm.Options = {
    RegisterSetting = function(_, definition) return HolyStorm.Settings:Register(definition) end,
    RegisterOptionsTab = function() return true end,
    CreateScopeSelector = function(_, id, labels) local definition = HolyStorm.Settings:GetDefinition(id); local values = {}; for key, item in pairs(definition and definition.scopes or {}) do local scope = type(key) == "number" and item or key; values[scope] = labels and labels[scope] or scope end; return { type = "select", values = values } end,
}
HolyStorm.Commands = { RegisterOption = function() return true end }

function LibStub(name)
    if name == "AceAddon-3.0" then return { GetAddon = function() return HolyStorm end } end
    if name == "AceLocale-3.0" then return { GetLocale = function() return locale end } end
end
function HolyStorm.Utils.DeepCopy(value) return copy(value) end
function HolyStorm.Utils.ApplyDefaults(target, defaults)
    target = type(target) == "table" and target or {}
    for key, value in pairs(defaults) do if target[key] == nil then target[key] = copy(value) end end
    return target
end
function HolyStorm.Utils.Now() return wall end
function HolyStorm.Utils.TableCount(value) local count = 0; for _ in pairs(value or {}) do count = count + 1 end; return count end
function HolyStorm.DataManager:RegisterArea(id, scope, defaults)
    assert(id == "positions" and scope == "profile")
    settingsArea = settingsArea or copy(defaults)
end
function HolyStorm.DataManager:GetArea(id) assert(id == "positions"); return copy(settingsArea) end
function HolyStorm.DataManager:Set(id, key, value)
    assert(id == "positions"); settingsArea[key] = value; return true
end
function HolyStorm.Data.GuildStore:GetCurrent() return guild end
function HolyStorm.Data.PlayerStore:GetCharacterOwner(guid) return "account-" .. tostring(guid) end
function HolyStorm.Data.CharacterStore:Get() return nil end
function HolyStorm.Policy:IsGuildModuleEnabled() return moduleEnabled end
function HolyStorm.Tasks:RegisterTaskType(id, definition) self.types[id] = definition end
function HolyStorm.Tasks:Queue(id, options)
    options = options or {}
    local key = id .. ":" .. tostring(options.mergeKey or "")
    local status = self.pending[key] and "MERGED" or "QUEUED"
    self.pending[key] = true
    self.queued[#self.queued + 1] = { id = id, options = copy(options), status = status }
    return "task", status
end
function HolyStorm.Tasks:ScheduleRecurring(id, interval, callback, options)
    self.recurring[id] = { interval = interval, callback = callback, options = options }
    return true
end
function HolyStorm.Tasks:CancelRecurring(id) local existed = self.recurring[id] ~= nil; self.recurring[id] = nil; return existed end
function HolyStorm.Sync:RegisterDomain(id, definition) self.domains[id] = definition; return true end
function HolyStorm.Sync:Publish(domain, id, reason)
    self.published[#self.published + 1] = { domain = domain, id = id, reason = reason }
    return true
end
function HolyStorm.Sync:Discover(domain, since, options)
    self.discovered[#self.discovered + 1] = { domain = domain, since = since, options = options }
    return true
end
function HolyStorm.Events:Register(event, owner, callback) self.handlers[event .. ":" .. owner] = callback end
function HolyStorm.Events:UnregisterOwner(owner)
    for key in pairs(self.handlers) do if key:sub(-#owner) == owner then self.handlers[key] = nil end end
end
function HolyStorm.Events:Emit(event, ...)
    self.emitted[#self.emitted + 1] = { event = event, args = { ... } }
end
function HolyStorm.Logger:Write(level, module, category, message, context)
    self.rows[#self.rows + 1] = { level = level, module = module, category = category, message = message, context = context }
end
function HolyStorm.MapLinks:GetPlayerPosition() return pos.map, pos.x, pos.y end
function HolyStorm.MapLinks:IsValidMapID(mapID) return tonumber(mapID) and mapID > 0 and mapID % 1 == 0 end
function HolyStorm.MapLinks:IsValidCoordinate(mapID, x, y)
    return self:IsValidMapID(mapID) and tonumber(x) and x >= 0 and x <= 1 and tonumber(y) and y >= 0 and y <= 1
end

function UnitGUID() return localGuid end
function IsInGuild() return inGuild end
function GetTime() return mono end
function GetUnitSpeed() return speed end

assert(loadfile(featureRoot .. "GuildPositions.lua"))()
local positions = HolyStorm.GuildPositions
assert(positions:Initialize())
assert(positions:Enable())
local domain = HolyStorm.Sync.domains["guild-position"]
assert(domain and domain.live and domain.catchUp == false and domain.priority == 110, "live domain contract missing")

local settings = positions:GetSettings()
assert(settings.share == true and settings.display == true, "sharing and visibility default to enabled")
assert(settings.minimapEnabled == false and settings.worldMapEnabled == true, "map output defaults are independent")
assert(positions:CanShare() and positions:CanDisplay(), "default-visible member has no artificial permission gate")
assert(positions:SampleMovement("INITIAL", true), "initial position capture should succeed")
assert(positions.pendingSnapshot and positions.pendingSnapshot.characterUUID == localGuid)
local keys = 0; for _ in pairs(positions.pendingSnapshot) do keys = keys + 1 end
assert(keys == 8 and positions.pendingSnapshot.name == nil and positions.pendingSnapshot.class == nil,
    "position snapshot must only contain identity, guild, coordinates, freshness, sequence and movement state")
assert(positions:RunPublish() and HolyStorm.Sync.published[#HolyStorm.Sync.published].domain == "guild-position",
    "initial state must publish through Sync v2")
assert(HolyStorm.Sync.published[#HolyStorm.Sync.published].reason == "POSITION_LIVE_UPDATE")

local queued = #HolyStorm.Tasks.queued
mono, wall = mono + 600, wall + 600
assert(not positions:SampleMovement("STATIONARY", false) and #HolyStorm.Tasks.queued == queued,
    "stationary players do not generate periodic updates")

positions:StartMovement(); speed = 2; pos.x = 0.21; mono = mono + 8
assert(positions:SampleMovement("SLOW", false) and positions.movement.bucket == "slow"
    and positions.movement.nextEligible == mono + 8, "slow movement interval is not automatic")
pos.x = 0.22; mono = mono + 1
assert(not positions:SampleMovement("TOO_SOON", false), "slow movement sample exceeded its interval")
speed = 14; mono = mono + 7
assert(positions:SampleMovement("FAST", false) and positions.movement.bucket == "fast"
    and positions.movement.nextEligible == mono + 3, "fast movement interval is not automatic")
assert(positions.metrics.coalesced >= 1, "latest local position did not merge into the pending publish")
assert(HolyStorm.Tasks.recurring["Position.MovementSample"] and HolyStorm.Tasks.recurring["Position.MovementSample"].interval == 1,
    "movement sampling must use the central one-second TaskManager recurring work")
assert(positions.movementScheduled == true, "central movement recurring work was not registered")

pos.map, pos.x = 85, 0.4
local zoneHandler = HolyStorm.Events.handlers["ZONE_CHANGED_NEW_AREA:positions-service"]
assert(zoneHandler, "zone changes are registered")
zoneHandler()
assert(positions.captureForce == true, "map/zone change must force an immediate sample")
assert(positions:RunCapture(), "forced map-change capture failed")
assert(positions.pendingSnapshot.mapID == 85, "map-change snapshot did not use the new map")
assert(positions:RunPublish(), "map-change snapshot did not publish")

local remote = {
    characterUUID = remoteGuid, guildId = guild.id, mapID = 84, x = 0.4, y = 0.5,
    timestamp = wall, sequence = 1, moving = false,
}
local function metadata(payload)
    return { owner = payload.characterUUID,
        version = math.floor(payload.timestamp) * 1000 + payload.sequence % 1000,
        updatedAt = payload.timestamp }
end
local meta = metadata(remote)
assert(domain.validate(remote, meta, remoteGuid), "valid online guild position rejected")
assert(domain.authorize(remote, meta, remoteGuid, "Remote-Realm", remoteGuid), "direct owner authority rejected")
assert(domain.import(remoteGuid, remote, meta, remoteGuid, "Remote-Realm") and positions:Get(remoteGuid),
    "remote position not imported/renderable")
assert(HolyStorm.Utils.TableCount(positions.remote) == 1, "remote state must retain only one latest position per GUID")

local bloated = copy(remote); bloated.itemLevel = 900
assert(not domain.validate(bloated, meta, remoteGuid), "character details were accepted in position payload")
local invalid = copy(remote); invalid.x = 2
assert(not domain.validate(invalid, metadata(invalid), remoteGuid), "invalid coordinates were accepted")
local oldStationary = copy(remote); oldStationary.timestamp = wall - 600
assert(domain.validate(oldStationary, metadata(oldStationary), remoteGuid),
    "online stationary position should survive missing movement updates")

wall = wall + 91
positions:ReconcileRoster()
assert(positions:Get(remoteGuid), "online stationary member disappeared only because no movement update arrived")
remote = copy(remote); remote.timestamp = wall; remote.sequence = 2; remote.moving = true; remote.x = 0.45
meta = metadata(remote)
assert(domain.import(remoteGuid, remote, meta, remoteGuid, "Remote-Realm"), "fresh moving state was not imported")
wall = wall + 91
positions:ReconcileRoster()
assert(not positions.remote[remoteGuid] and positions.metrics.droppedStale > 0,
    "moving position must expire after the documented stale window")

wall = wall + 1
remote = copy(remote); remote.timestamp = wall; remote.sequence = 3; remote.moving = false
meta = metadata(remote)
assert(domain.import(remoteGuid, remote, meta, remoteGuid, "Remote-Realm"), "stationary state should be accepted")
guild.roster[remoteGuid].online = false
positions:ReconcileRoster()
assert(not positions.remote[remoteGuid], "offline roster member marker was not removed immediately")
guild.roster[remoteGuid].online = true

local currentState = positions.ownState
assert(currentState and not currentState.withdrawn, "local shared snapshot missing")
local publishedBeforeOptOut = #HolyStorm.Sync.published
assert(positions:SetSetting("share", false), "privacy opt-out failed")
assert(not positions:CanShare() and positions.ownState.withdrawn and positions.ownState.x == nil,
    "opt-out must clear coordinates and prevent further sharing")
assert(#HolyStorm.Sync.published == publishedBeforeOptOut + 1
    and HolyStorm.Sync.published[#HolyStorm.Sync.published].reason == "POSITION_WITHDRAWN",
    "privacy opt-out must send only the coordinate-free withdrawal needed to remove old markers")
local withdrawal = domain.export(localGuid)
assert(withdrawal and withdrawal.withdrawn and withdrawal.x == nil and withdrawal.mapID == nil,
    "withdrawal must contain no location data")
local withdrawnMeta = domain.getMetadata(localGuid)
assert(domain.validate(withdrawal, withdrawnMeta, localGuid), "coordinate-free withdrawal was rejected")
local publishCount = #HolyStorm.Sync.published
assert(not positions:RunPublish() and #HolyStorm.Sync.published == publishCount,
    "a queued position publish must not send after privacy opt-out")

local update = copy(remote); update.sequence = 4; update.timestamp = wall + 1
assert(domain.import(remoteGuid, update, metadata(update), remoteGuid, "Remote-Realm"))
local tombstone = copy(withdrawal); tombstone.timestamp = wall + 2; tombstone.sequence = withdrawal.sequence + 1
assert(domain.import(localGuid, tombstone, metadata(tombstone), localGuid, "Local-Realm"))

assert(positions:SetSetting("share", true) and positions:GetSettings().share == true,
    "sharing can be re-enabled by the local user")
positions.captureForce, positions.captureReason = true, "REENABLED"
assert(positions:RunCapture() and positions:RunPublish(), "re-enabled sharing did not publish current state")
assert(positions.ownState.timestamp > currentState.timestamp, "re-enabled state must supersede withdrawal")

positions:SetSetting("worldMapEnabled", false)
positions:SetSetting("minimapEnabled", true)
positions:SetSetting("worldMapSize", 40)
positions:SetSetting("minimapSize", 15)
positions:SetSetting("currentMapOnly", true)
positions:SetSetting("markerStyle", "GUILD")
settings = positions:GetSettings()
assert(not settings.worldMapEnabled and settings.minimapEnabled and settings.worldMapSize == 40
    and settings.minimapSize == 15 and settings.currentMapOnly and settings.markerStyle == "GUILD",
    "independent visual settings did not persist through DataManager")

settingsArea.share = false; localSettings["positions.share"] = nil; positions.settingsRegistered = false
settings = positions:GetSettings(); assert(settings.share == false, "legacy explicit share=false migrates without being replaced by the enabled default")
assert(positions:SetSetting("share", true), "position sharing can be restored after legacy migration")

moduleEnabled = false
assert(not positions:CanShare() and not positions:CanDisplay(), "administrative module disable did not gate feature")
moduleEnabled = true
assert(positions:Disable() and not positions.featureActive and not HolyStorm.Tasks.recurring["Position.Cleanup"]
    and not HolyStorm.Tasks.recurring["Position.MovementSample"], "module disable left recurring work active")

local permissionFile = assert(io.open(root .. "LIVE/Holy_Storm_Positions/Positions.lua", "rb"))
local permissionRegistry = permissionFile:read("*a")
permissionFile:close()
local metadataCapture, registeredPositionsModule
HolyStorm.RegisterModule = function(_, metadata, initialize) metadataCapture = metadata; registeredPositionsModule = {}; initialize(registeredPositionsModule) end
HolyStorm.RegisterUIExtension = function() end
HolyStorm.GetModule = function() return nil end
assert(loadfile(featureRoot .. "Positions.lua"))()
assert(metadataCapture and metadataCapture.internalName == "positions" and metadataCapture.moduleType == "feature",
    "positions module metadata was not registered")
local dependencies = {}; for _, dependency in ipairs(metadataCapture.dependencies) do dependencies[dependency] = true end
assert(dependencies.ui and dependencies.options and dependencies.synchronization,
    "module contract is missing UI/options/sync dependencies")
assert(metadataCapture.permissions == nil and not permissionRegistry:find("position%-view")
    and not permissionRegistry:find("position%-share"), "artificial view/share permissions remain")
local positionOptions = registeredPositionsModule:BuildOptions()
assert(positionOptions.args.privacy.args.share and positionOptions.args.privacy.args.shareScope.values.guild
    and positionOptions.args.privacy.args.shareScope.values.allGuilds
    and not positionOptions.args.privacy.args.shareScope.values.account,
    "position sharing keeps its central control and offers only this-guild or all-guild scopes")

print("Guild-position defaults, privacy, movement, coalescing, live sync, freshness, module and settings tests passed")
