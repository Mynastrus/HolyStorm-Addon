local root = (arg[0]:gsub("tools[/\\]test_positions_map.lua$", ""))
local clock, localMap = 100, 84
local localX, localY = 0.5, 0.5
local mapParents = { [84] = 12, [85] = 12, [12] = 1, [1] = nil, [999] = nil }
local currentWorld = {}
local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
function CreateVector2D(x, y) return vec(x, y) end
C_Map = {
    GetBestMapForUnit = function() return localMap end,
    GetPlayerMapPosition = function(mapID)
        if mapID ~= localMap then return nil end
        return vec(localX, localY)
    end,
    GetMapInfo = function(mapID)
        if mapID == 998 then error("map API failure") end
        if mapParents[mapID] == nil and mapID ~= 1 and mapID ~= 999 then return nil end
        return { mapID = mapID, parentMapID = mapParents[mapID] }
    end,
    GetWorldPosFromMapPos = function(mapID, point)
        if mapID == 777 then return nil end
        currentWorld[mapID] = true
        return 1, vec(point.x * 100, point.y * 100)
    end,
    GetMapPosFromWorldPos = function(continentID, world, targetMapID)
        if continentID ~= 1 or targetMapID == 999 then return nil end
        return targetMapID, vec(world.x / 200, world.y / 200)
    end,
    GetMapWorldSize = function() return 10000, 10000 end,
}
C_Minimap = { GetViewRadius = function() return 1000 end }
GetCVarBool = function() return true end
GetPlayerFacing = function() return 0 end
Minimap = {
    width = 200, height = 200,
    GetWidth = function(self) return self.width end,
    GetHeight = function(self) return self.height end,
    GetFrameLevel = function() return 10 end,
}

local function deep(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in pairs(value) do result[key] = deep(child) end; return result
end
local locale = setmetatable({}, { __index = function(_, key) return key end })
local settings = { worldMapEnabled = true, minimapEnabled = true, currentMapOnly = false,
    worldMapSize = 24, minimapSize = 18, markerStyle = "CLASS", display = true }
local remote = {}
local eventHandlers, updaters = {}, {}
local worldMapID = 84
local worldPool = { created = 0, active = 0, maxActive = 0 }
local worldCanvas = {
    GetMapID = function() return worldMapID end,
    RemoveAllPinsByTemplate = function() worldPool.active = 0 end,
    RemovePin = function() worldPool.active = math.max(0, worldPool.active - 1) end,
    AcquirePin = function()
        worldPool.active = worldPool.active + 1
        worldPool.maxActive = math.max(worldPool.maxActive, worldPool.active)
        if worldPool.active > worldPool.created then worldPool.created = worldPool.active end
        return { SetPosition = function(self, x, y) self.x, self.y = x, y end, Hide = function() end }
    end,
}
WorldMapFrame = {
    AddDataProvider = function(self, provider) self.provider = provider end,
    RemoveDataProvider = function(self, provider) if self.provider == provider then self.provider = nil end end,
}
MapCanvasDataProviderMixin = {}
function CreateFromMixins()
    return { GetMap = function() return worldCanvas end }
end

local function texture()
    return {
        SetTexture = function(self, value) self.texture = value end,
        SetTexCoord = function(self, ...) self.coords = { ... } end,
        SetBlendMode = function() end, SetPoint = function() end, SetAllPoints = function() end,
        SetSize = function(self, w, h) self.width, self.height = w, h end,
        SetVertexColor = function(self, ...) self.color = { ... } end,
    }
end
local minimapFrames = {}
function CreateFrame(kind)
    local frame = {
        kind = kind, shown = false,
        SetFrameLevel = function(self, level) self.frameLevel = level end,
        CreateTexture = function() return texture() end,
        RegisterForClicks = function() end,
        SetScript = function(self, name, callback) self[name] = callback end,
        SetSize = function(self, w, h) self.width, self.height = w, h end,
        ClearAllPoints = function() end,
        SetPoint = function(self, _, _, _, x, y) self.x, self.y = x, y end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    minimapFrames[#minimapFrames + 1] = frame
    return frame
end
GameTooltip = {
    lines = {}, SetOwner = function() end,
    SetText = function(self, value) self.title = value end,
    AddLine = function(self, value) self.lines[#self.lines + 1] = value end,
    AddDoubleLine = function(self, label, value) self.lines[#self.lines + 1] = label .. ":" .. value end,
    Show = function() end, Hide = function() end,
}
CLASS_ICON_TCOORDS = { MAGE = { 0, 0.25, 0, 0.25 } }
RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.6, b = 1 } }

local HolyStorm
HolyStorm = {
    Utils = { Now = function() return clock end },
    Logger = { Write = function() end },
    Events = {
        Register = function(_, event, owner, callback) eventHandlers[event .. ":" .. owner] = callback end,
        UnregisterOwner = function(_, owner)
            for key in pairs(eventHandlers) do if key:sub(-#owner) == owner then eventHandlers[key] = nil end end
        end,
        Emit = function() end,
    },
    MapLinks = nil,
    GuildPositions = {
        remote = {},
        GetSettings = function() return settings end,
        GetVisible = function() local result = {}; for _, entry in ipairs(remote) do result[#result + 1] = entry end; return result end,
        Get = function(_, guid) for _, entry in ipairs(remote) do if entry.characterUUID == guid then return entry end end end,
        GetCharacterSummary = function(_, guid)
            return { name = "Member-" .. guid, class = "Mage", classFile = "MAGE", race = "Human", role = "DPS",
                rank = "Member", status = nil, mainGuid = guid, itemLevel = 650, raidProgress = { killed = 3, total = 8, difficulty = "Heroic" }, mythicScore = 2450 }
        end,
    },
    CharacterActions = {
        CreateContextMenu = function(_, owner, guid, actions) HolyStorm.lastContext = { owner = owner, guid = guid, actions = actions }; return true end,
        Open = function(_, guid) HolyStorm.openedCharacter = guid; return true end,
    },
}
function HolyStorm:IsCapabilityAvailable(id, moduleId)
    return id == "poi.create" and moduleId == "POI" and self.poiAvailable == true
end
function HolyStorm:CallCapability(id, value) self.calledCapability = id; self.capabilityValue = value; return true end
function LibStub(name)
    if name == "AceAddon-3.0" then return { GetAddon = function() return HolyStorm end } end
    if name == "AceLocale-3.0" then return { GetLocale = function() return locale end } end
end

local coreRoot = root .. "LIVE/Holy_Storm/"
assert(loadfile(coreRoot .. "Core/Content/MapLinks.lua"))()
assert(HolyStorm.MapLinks:IsMapRelated(84, 12) and HolyStorm.MapLinks:IsMapRelated(12, 85)
    and HolyStorm.MapLinks:IsMapRelated(84, 84), "map parent/child relationships were not recognized")
assert(not HolyStorm.MapLinks:IsMapRelated(84, 999) and not HolyStorm.MapLinks:GetMapParent(998),
    "unrelated maps or map API failures were guessed")
local x, y, mode = HolyStorm.MapLinks:TransformCoordinate(84, 0.6, 0.4, 84)
assert(x == 0.6 and y == 0.4 and mode == "DIRECT", "exact-map coordinates changed")
x, y, mode = HolyStorm.MapLinks:TransformCoordinate(84, 0.6, 0.4, 12)
assert(x == 0.3 and y == 0.2 and mode == "TRANSFORMED", "parent map transform did not use world position")
assert(not HolyStorm.MapLinks:TransformCoordinate(84, 0.6, 0.4, 999), "unsupported transformation produced guessed coordinates")
assert(not HolyStorm.MapLinks:TransformCoordinate(777, 0.2, 0.2, 12), "missing world position produced guessed coordinates")
local playerMap, playerX, playerY = HolyStorm.MapLinks:GetPlayerPosition()
assert(playerMap == 84 and playerX == localX and playerY == localY, "local position API did not return player map coordinates")

localMap = 12
local context = assert(HolyStorm.MapLinks:GetMinimapContext())
local projectedX, projectedY, projectedMode = HolyStorm.MapLinks:ProjectToMinimap(84, 1, 0.9995, true, context)
assert(projectedX and projectedY and projectedMode == "TRANSFORMED", "minimap parent transform failed")
assert(not HolyStorm.MapLinks:ProjectToMinimap(999, 0.2, 0.2, true, context), "unrelated map got a minimap marker")
local facing = GetPlayerFacing
GetPlayerFacing = nil
local noFacing, facingReason = HolyStorm.MapLinks:GetMinimapContext()
assert(not noFacing and facingReason == "ROTATION_UNAVAILABLE", "rotated minimap guessed its orientation")
C_Minimap.IsRotateMinimapIgnored = function() return true end
assert(HolyStorm.MapLinks:GetMinimapContext(), "ignored minimap rotation should safely use north-up projection")
C_Minimap.IsRotateMinimapIgnored = nil
GetPlayerFacing = facing
localMap = 84
local saved = C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos = nil
local stillMap = HolyStorm.MapLinks:GetPlayerPosition()
assert(stillMap == 84, "current local position remains readable when only transform API is missing")
assert(not HolyStorm.MapLinks:TransformCoordinate(84, 0.2, 0.2, 12), "transform degrades when conversion APIs are missing")
C_Map.GetWorldPosFromMapPos = saved

HolyStorm.MapLinks.RegisterMinimapUpdater = function(_, id, callback) updaters[id] = callback; return true end
HolyStorm.MapLinks.UnregisterMinimapUpdater = function(_, id) updaters[id] = nil end
assert(loadfile(root .. "LIVE/Holy_Storm_Positions/Map.lua"))()
local map = HolyStorm.GuildPositionMap
for index = 1, 3 do
    remote[index] = { characterUUID = "Player-" .. index, guildId = "guild", mapID = 84,
        x = 0.501 + index * 0.0001, y = 0.5, timestamp = clock, sequence = index, moving = false }
    HolyStorm.GuildPositions.remote[remote[index].characterUUID] = remote[index]
end
assert(map:Enable() and WorldMapFrame.provider and updaters["guild-positions"], "map integration did not enable")
assert(worldPool.active == 3 and #minimapFrames == 3, "initial map render did not create the expected bounded marker pool")
local worldAllocated = worldPool.created
local miniAllocated = #minimapFrames
for _ = 1, 25 do
    WorldMapFrame.provider:RefreshAllData()
    map:RefreshMinimap(true)
end
assert(worldPool.active == 3 and worldPool.created == worldAllocated and #minimapFrames == miniAllocated,
    "repeated map updates allocated or leaked pins")

worldMapID = 12
settings.currentMapOnly = true
map:Refresh()
assert(map:GetRenderState("Player-1").worldPin, "child-map player should render on a transformable parent map")
assert(map:GetRenderState("Player-1").transform == "TRANSFORMED", "parent marker should record its official transformation")
settings.worldMapEnabled = false
map:Refresh()
assert(worldPool.active == 0, "disabling world-map markers left pins visible")
settings.worldMapEnabled, settings.minimapEnabled = true, false
map:Refresh()
assert(worldPool.active == 3 and (function() for _, pin in ipairs(minimapFrames) do if pin.shown then return true end end return false end)() == false,
    "world-map and minimap visibility options are not independent")
settings.minimapEnabled = true
settings.worldMapSize, settings.minimapSize = 41, 15
map:Refresh()
assert(minimapFrames[1].width == 15, "minimap size does not use its independent setting")
settings.markerStyle = "GUILD"
map:Refresh()
assert(minimapFrames[1].icon.texture == "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    "guild marker style was not applied")
settings.markerStyle = "CLASS"
map:Refresh()
assert(minimapFrames[1].icon.texture == "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
    and minimapFrames[1].border.color[1] == 0.2, "class marker style/color was not applied")

local tooltipOwner = minimapFrames[1]
map:ShowTooltip(tooltipOwner, tooltipOwner.entry)
assert(GameTooltip.title and #GameTooltip.lines >= 4, "tooltip did not render stored character summary values")
HolyStorm.poiAvailable = false
assert(map:OpenContext(tooltipOwner, tooltipOwner.entry) and HolyStorm.lastContext.actions[1].enabled == false,
    "missing POI capability should leave the reused character menu and disable its POI action")
HolyStorm.poiAvailable = true
assert(map:OpenContext(tooltipOwner, tooltipOwner.entry) and HolyStorm.lastContext.actions[1].enabled == true,
    "available POI capability should enable the shared character context action")
HolyStorm.lastContext.actions[1].callback()
assert(HolyStorm.calledCapability == "poi.create" and HolyStorm.capabilityValue.mapID == 84,
    "POI action did not pass the original map coordinates through the capability")
assert(map:HandleClick(tooltipOwner, "LeftButton") and HolyStorm.openedCharacter == tooltipOwner.entry.characterUUID,
    "left click does not use existing character navigation")

remote = {}
HolyStorm.GuildPositions.remote = {}
map:Refresh()
assert(worldPool.active == 0 and #minimapFrames == miniAllocated, "empty guild did not hide reusable pins")
for index = 1, 500 do
    remote[index] = { characterUUID = string.format("Guild-%03d", index), guildId = "guild", mapID = 84,
        x = 0.5001, y = 0.5, timestamp = clock, sequence = index, moving = false }
    HolyStorm.GuildPositions.remote[remote[index].characterUUID] = remote[index]
end
map:Refresh()
assert(worldPool.active == 500 and worldPool.created == 500 and #minimapFrames == 500,
    "large guild render did not allocate a bounded reusable pool")
local largeWorldFrames, largeMiniFrames = worldPool.created, #minimapFrames
for _ = 1, 5 do map:Refresh(); WorldMapFrame.provider:RefreshAllData() end
assert(worldPool.created == largeWorldFrames and #minimapFrames == largeMiniFrames and worldPool.active == 500,
    "large-guild update burst leaked marker frames")
assert(map:Disable() and not WorldMapFrame.provider and not updaters["guild-positions"], "map disable did not release providers/updater")
assert((function() for _, pin in ipairs(minimapFrames) do if pin.shown then return true end end return false end)() == false,
    "map disable left minimap markers visible")
assert(map:Enable() and map:Disable() and worldPool.created == largeWorldFrames and #minimapFrames == largeMiniFrames,
    "repeated map open/close lifecycle allocated a second marker set")

local tocFile = assert(io.open(root .. "LIVE/Holy_Storm_Positions/Holy_Storm_Positions.toc", "rb"))
local toc = tocFile:read("*a")
tocFile:close()
assert(not toc:find("Holy_Storm_POI", 1, true), "POI module became a hard addon dependency")
print("Positions map hierarchy, safe transforms, minimap projection, pooling, tooltip and optional context tests passed")
