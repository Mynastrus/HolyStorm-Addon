local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Positions")

local Map = {
    version = addonVersion,
    worldProvider = nil,
    minimapPins = {},
    renderState = {},
    transformCache = {},
    loggedFailures = {},
    minimapElapsed = 0,
    lastMinimapSignature = nil,
    lastMinimapRefresh = 0,
    initialized = false,
    enabled = false,
    installed = false,
}

local classTexture = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local guildTexture = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

local function age(timestamp)
    return math.max(0, HolyStorm.Utils.Now() - (tonumber(timestamp) or 0))
end

local function visible(entries)
    local seen = {}
    for _, entry in ipairs(entries) do seen[entry.characterUUID] = true end
    return seen
end

local function minimapSignature(context, entries, settings)
    local values = {
        tostring(context.mapID), tostring(context.x), tostring(context.y), tostring(context.width), tostring(context.height),
        tostring(context.radius), tostring(context.pixelRadius), tostring(context.rotate), tostring(context.facing),
        tostring(settings.minimapSize), tostring(settings.currentMapOnly), tostring(settings.markerStyle),
    }
    for _, entry in ipairs(entries) do
        values[#values + 1] = table.concat({
            tostring(entry.characterUUID), tostring(entry.sequence), tostring(entry.mapID), tostring(entry.x), tostring(entry.y),
            tostring(entry.timestamp), tostring(entry.moving == true),
        }, ":")
    end
    return table.concat(values, "|")
end

function Map:GetRenderState(guid)
    self.renderState[guid] = self.renderState[guid] or {}
    return self.renderState[guid]
end

function Map:GetStyle(entry)
    local summary = HolyStorm.GuildPositions:GetCharacterSummary(entry.characterUUID)
    local settings = HolyStorm.GuildPositions:GetSettings()
    if settings.markerStyle == "CLASS" and summary.classFile and CLASS_ICON_TCOORDS
        and CLASS_ICON_TCOORDS[summary.classFile] then
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[summary.classFile] or { r = 0.25, g = 0.78, b = 0.92 }
        return classTexture, CLASS_ICON_TCOORDS[summary.classFile], color
    end
    return guildTexture, { 0, 1, 0, 1 }, { r = 0.25, g = 0.78, b = 0.92 }
end

function Map:ConfigureVisual(frame, entry, size)
    local texture, coords, color = self:GetStyle(entry)
    frame.entry = entry
    frame:SetSize(size, size)
    frame.icon:SetTexture(texture)
    frame.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    frame.border:SetVertexColor(color.r or 1, color.g or 1, color.b or 1, 1)
end

function Map:ShowTooltip(owner, entry)
    local summary = HolyStorm.GuildPositions:GetCharacterSummary(entry.characterUUID)
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    local title = summary.name or entry.characterUUID
    local color = summary.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[summary.classFile]
    if color then
        title = string.format("|cff%02x%02x%02x%s|r", math.floor((color.r or 1) * 255 + 0.5),
            math.floor((color.g or 1) * 255 + 0.5), math.floor((color.b or 1) * 255 + 0.5), title)
    end
    GameTooltip:SetText(title)
    local identity = { summary.class, summary.race, summary.role }
    local compact = {}
    for _, value in ipairs(identity) do
        if value and value ~= "" then compact[#compact + 1] = value end
    end
    if #compact > 0 then GameTooltip:AddLine(table.concat(compact, " · "), 1, 1, 1) end
    if summary.rank then GameTooltip:AddDoubleLine(L["TOOLTIP_RANK"], summary.rank, 1, 0.82, 0, 1, 1, 1) end
    local status = (summary.status == 1 or summary.status == "AFK") and L["STATUS_AFK"]
        or (summary.status == 2 or summary.status == "DND") and L["STATUS_DND"]
    if status then GameTooltip:AddDoubleLine(L["TOOLTIP_STATUS"], status, 1, 0.82, 0, 1, 1, 1) end
    if summary.mainName and summary.mainGuid ~= summary.characterUUID then
        GameTooltip:AddDoubleLine(summary.isShadowMain and L["TOOLTIP_GUILD_MAIN"] or L["TOOLTIP_MAIN"],
            summary.mainName, 1, 0.82, 0, 1, 1, 1)
    end
    if summary.itemLevel and summary.itemLevel > 0 then
        GameTooltip:AddDoubleLine(L["TOOLTIP_ITEM_LEVEL"], string.format("%.1f", summary.itemLevel), 1, 0.82, 0, 1, 1, 1)
    end
    if summary.raidProgress then
        local text = string.format("%d/%d %s", summary.raidProgress.killed or 0,
            summary.raidProgress.total or 0, summary.raidProgress.difficulty or "")
        local colored = HolyStorm.CharacterUI and HolyStorm.CharacterUI:ColorDifficulty(summary.raidProgress.difficulty, text) or text
        GameTooltip:AddDoubleLine(L["TOOLTIP_RAID"], colored, 1, 0.82, 0, 1, 1, 1)
    end
    if summary.mythicScore and summary.mythicScore > 0 then
        GameTooltip:AddDoubleLine(L["TOOLTIP_MYTHIC"], string.format("%.1f", summary.mythicScore), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(L["TOOLTIP_POSITION_AGE"], string.format(L["SECONDS_AGO"], age(entry.timestamp)),
        1, 0.82, 0, 0.75, 0.75, 0.75)
    GameTooltip:Show()
end

function Map:HasPOICapability()
    return HolyStorm.IsCapabilityAvailable and HolyStorm:IsCapabilityAvailable("poi.create", "POI") or false
end

function Map:OpenAsPOI(entry)
    if not self:HasPOICapability() then return false, "POI_UNAVAILABLE" end
    local summary = HolyStorm.GuildPositions:GetCharacterSummary(entry.characterUUID)
    return HolyStorm:CallCapability("poi.create", {
        mapID = entry.mapID,
        x = entry.x,
        y = entry.y,
        name = string.format(L["POI_NAME"], summary.name or entry.characterUUID),
        description = "",
        target = "PERSONAL",
        category = "note",
        icon = "marker",
        color = { r = 1, g = 0.82, b = 0, a = 1 },
        source = "GUILD_PLAYER_POSITION",
        metadata = { characterUUID = entry.characterUUID, characterName = summary.name },
    })
end

function Map:OpenContext(owner, entry)
    if not HolyStorm.CharacterActions then return false end
    return HolyStorm.CharacterActions:CreateContextMenu(owner, entry.characterUUID, {
        {
            text = L["ACTION_CREATE_POI"],
            enabled = self:HasPOICapability(),
            callback = function() return Map:OpenAsPOI(entry) end,
        },
    })
end

function Map:HandleClick(owner, button)
    if not owner.entry then return false end
    if button == "RightButton" then return self:OpenContext(owner, owner.entry) end
    if HolyStorm.CharacterActions then return HolyStorm.CharacterActions:Open(owner.entry.characterUUID) end
    return HolyStorm:CallCapability("character.open", owner.entry.characterUUID, "summary")
end

function Map:PlaceWorldPin(provider, entry)
    local canvas = provider:GetMap()
    local viewed = canvas and canvas.GetMapID and canvas:GetMapID()
    local state = self:GetRenderState(entry.characterUUID)
    state.worldPin = false
    state.viewedMapID = viewed
    if not viewed then state.reason = "VIEWED_MAP_UNAVAILABLE"; return end
    local settings = HolyStorm.GuildPositions:GetSettings()
    if settings.currentMapOnly and not HolyStorm.MapLinks:IsMapRelated(entry.mapID, viewed) then
        state.reason = "CURRENT_MAP_ONLY"
        return
    end
    if not canvas.AcquirePin then state.reason = "WORLD_MAP_PIN_API_UNAVAILABLE"; return end
    local x, y, mode = HolyStorm.MapLinks:TransformCoordinate(entry.mapID, entry.x, entry.y, viewed)
    state.transform = mode
    state.reason = x and nil or mode
    if not x then
        local key = table.concat({ entry.characterUUID, viewed, tostring(mode) }, ":")
        if not self.loggedFailures[key] then
            self.loggedFailures[key] = true
            HolyStorm.Logger:Write("DEBUG", "Positions", "map", "Guild position transformation unavailable", {
                characterUUID = entry.characterUUID, sourceMapID = entry.mapID, viewedMapID = viewed, reason = mode,
            })
        end
        return
    end
    local pin = canvas:AcquirePin("HolyStormGuildPositionPinTemplate", entry)
    if not pin then state.reason = "PIN_ACQUIRE_FAILED"; return end
    pin:SetPosition(x, y)
    provider.pins[entry.characterUUID] = pin
    state.worldPin = true
    state.transformedX, state.transformedY = x, y
end

function Map:InstallWorldMap()
    if self.worldProvider or not WorldMapFrame or not self:IsWorldMapVisible() or not MapCanvasDataProviderMixin or not CreateFromMixins then return false end
    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.pins = {}
    function provider:RemoveGuid(guid)
        local pin = self.pins[guid]
        if not pin then return end
        local canvas = self:GetMap()
        if canvas and type(canvas.RemovePin) == "function" then canvas:RemovePin(pin) else pin:Hide() end
        self.pins[guid] = nil
    end
    function provider:RemoveAllData()
        local canvas = self:GetMap()
        if canvas and type(canvas.RemoveAllPinsByTemplate) == "function" then
            canvas:RemoveAllPinsByTemplate("HolyStormGuildPositionPinTemplate")
        else
            for guid in pairs(self.pins) do self:RemoveGuid(guid) end
        end
        self.pins = {}
    end
    function provider:RefreshGuid(guid)
        if not Map:IsWorldMapVisible() then return end
        self:RemoveGuid(guid)
        if not Map.enabled or not HolyStorm.GuildPositions:GetSettings().worldMapEnabled then
            Map:GetRenderState(guid).worldPin = false
            return
        end
        local entry = HolyStorm.GuildPositions:Get(guid)
        if entry then Map:PlaceWorldPin(self, entry) else Map:GetRenderState(guid).worldPin = false end
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        if not Map.enabled or not Map:IsWorldMapVisible() or not HolyStorm.GuildPositions:GetSettings().worldMapEnabled then return end
        local canvas = self:GetMap()
        if not canvas or not canvas.GetMapID or not canvas:GetMapID() then return end
        for _, entry in ipairs(HolyStorm.GuildPositions:GetVisible()) do Map:PlaceWorldPin(self, entry) end
    end
    if type(WorldMapFrame.AddDataProvider) ~= "function" then return false end
    WorldMapFrame:AddDataProvider(provider)
    self.worldProvider = provider
    self.installed = true
    return true
end

function Map:IsWorldMapVisible()
    local frame = WorldMapFrame
    if not frame then return false end
    local query = frame.IsVisible or frame.IsShown
    if type(query) ~= "function" then return false end
    local ok, visible = pcall(query, frame)
    return ok and visible == true
end

function Map:HookWorldMap()
    if self.worldMapHooked then
        if self:IsWorldMapVisible() then self:InstallWorldMap() end
        return true
    end
    if not WorldMapFrame or type(WorldMapFrame.HookScript) ~= "function" then return false end
    self.worldMapShowHook = function()
        if Map.enabled then
            Map:InstallWorldMap()
            Map:Refresh()
        end
    end
    WorldMapFrame:HookScript("OnShow", self.worldMapShowHook)
    self.worldMapHooked = true
    if self:IsWorldMapVisible() then
        self:InstallWorldMap()
        self:Refresh()
    end
    return true
end

function Map:CreateMinimapPin()
    if not CreateFrame or not Minimap then return nil end
    local pin = CreateFrame("Button", nil, Minimap)
    pin:SetFrameLevel(Minimap:GetFrameLevel() + 7)
    pin.border = pin:CreateTexture(nil, "BACKGROUND")
    pin.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    pin.border:SetBlendMode("ADD")
    pin.border:SetPoint("CENTER")
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints()
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:SetScript("OnEnter", function(frame) if frame.entry then Map:ShowTooltip(frame, frame.entry) end end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(frame, button) Map:HandleClick(frame, button) end)
    return pin
end

function Map:HideMinimapPins()
    for index, pin in ipairs(self.minimapPins) do pin.entry = nil; pin:Hide() end
    for _, state in pairs(self.renderState) do state.minimapPin = false end
    self.lastMinimapSignature = nil
end

function Map:UpdateMinimapUpdater(entries)
    local settings = HolyStorm.GuildPositions:GetSettings()
    entries = entries or HolyStorm.GuildPositions:GetVisible()
    return HolyStorm.MapLinks:SetMinimapUpdaterActive("guild-positions",
        self.enabled and Minimap ~= nil and settings.minimapEnabled == true and type(entries) == "table" and #entries > 0)
end

function Map:RefreshMinimap(force)
    if not self.enabled then return false end
    local settings = HolyStorm.GuildPositions:GetSettings()
    if not settings.minimapEnabled then self:HideMinimapPins(); self:UpdateMinimapUpdater({}); return true end
    local nowClock = type(GetTime) == "function" and GetTime() or 0
    if not force and nowClock - self.lastMinimapRefresh < 1 then return false end
    self.lastMinimapRefresh = nowClock

    local entries = HolyStorm.GuildPositions:GetVisible()
    self:UpdateMinimapUpdater(entries)
    local context, reason = HolyStorm.MapLinks:GetMinimapContext()
    if not context then
        self:HideMinimapPins()
        self.lastMinimapError = reason
        return false
    end
    local signature = minimapSignature(context, entries, settings)
    if not force and signature == self.lastMinimapSignature then return true end
    self.lastMinimapSignature = signature
    self.lastMinimapError = nil

    local used, present = 0, visible(entries)
    for guid, cache in pairs(self.transformCache) do
        if not present[guid] then self.transformCache[guid] = nil end
    end
    for _, entry in ipairs(entries) do
        local state = self:GetRenderState(entry.characterUUID)
        state.minimapPin = false
        local cache = self.transformCache[entry.characterUUID]
        if not cache or cache.sequence ~= entry.sequence or cache.sourceMapID ~= entry.mapID or cache.targetMapID ~= context.mapID then
            local x, y, mode = HolyStorm.MapLinks:TransformCoordinate(entry.mapID, entry.x, entry.y, context.mapID)
            cache = { sequence = entry.sequence, sourceMapID = entry.mapID, targetMapID = context.mapID, x = x, y = y, mode = mode }
            self.transformCache[entry.characterUUID] = cache
        end
        state.minimapTransform = cache.mode
        local x, y, mode, mapID
        if cache.x and cache.y then
            x, y, mode, mapID = HolyStorm.MapLinks:ProjectToMinimap(entry.mapID, entry.x, entry.y,
                settings.currentMapOnly, context, cache.x, cache.y, cache.mode)
        else
            mode = cache.mode or "TRANSFORM_FAILED"
        end
        state.reason = x and nil or mode
        if x then
            used = used + 1
            local pin = self.minimapPins[used]
            if not pin then pin = self:CreateMinimapPin(); if not pin then break end; self.minimapPins[used] = pin end
            self:ConfigureVisual(pin, entry, settings.minimapSize)
            pin.border:SetSize(settings.minimapSize + 14, settings.minimapSize + 14)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", Minimap, "CENTER", x, y)
            pin:Show()
            state.minimapPin = true
            state.viewedMapID = mapID
            state.transformedX, state.transformedY = cache.x, cache.y
        end
    end
    for index = used + 1, #self.minimapPins do self.minimapPins[index].entry = nil; self.minimapPins[index]:Hide() end
    for guid in pairs(self.renderState) do
        if not HolyStorm.GuildPositions.remote[guid] then self.renderState[guid] = nil end
    end
    return true
end

function Map:RefreshMany(guids)
    if not self.enabled then return false end
    local worldVisible = self:IsWorldMapVisible()
    if worldVisible and not self.worldProvider then self:InstallWorldMap() end
    if worldVisible and self.worldProvider then
        if self.worldProvider.RefreshGuid then
            for guid in pairs(guids or {}) do self.worldProvider:RefreshGuid(guid) end
        else
            self.worldProvider:RefreshAllData()
        end
    end
    self:RefreshMinimap(true)
    HolyStorm.Events:Emit("HS_GUILD_POSITION_MAP_REFRESHED")
    return true
end

function Map:Refresh(guid)
    if guid then return self:RefreshMany({ [guid] = true }) end
    if not self.enabled then return false end
    local worldVisible = self:IsWorldMapVisible()
    if worldVisible and not self.worldProvider then self:InstallWorldMap() end
    if worldVisible and self.worldProvider then self.worldProvider:RefreshAllData() end
    self:RefreshMinimap(true)
    HolyStorm.Events:Emit("HS_GUILD_POSITION_MAP_REFRESHED")
    return true
end

function Map:Initialize()
    self.initialized = true
    return true
end

function Map:Enable()
    if self.enabled then return true end
    self.enabled = true
    self:HookWorldMap()
    HolyStorm.MapLinks:RegisterMinimapUpdater("guild-positions", function()
        Map:RefreshMinimap(false)
    end)
    self:UpdateMinimapUpdater()
    HolyStorm.Events:Register("ADDON_LOADED", "guild-position-map", function(_, name)
        if name == "Blizzard_WorldMap" then Map:HookWorldMap(); Map:Refresh() end
    end)
    HolyStorm.Events:Register("HS_GUILD_POSITIONS_CLEARED", "guild-position-map", function() Map:Refresh() end)
    HolyStorm.Events:Register("HS_POSITION_SETTINGS_CHANGED", "guild-position-map", function() Map:Refresh() end)
    self:Refresh()
    return true
end

function Map:Disable()
    if not self.enabled then return true end
    self.enabled = false
    HolyStorm.MapLinks:SetMinimapUpdaterActive("guild-positions", false)
    HolyStorm.MapLinks:UnregisterMinimapUpdater("guild-positions")
    HolyStorm.Events:UnregisterOwner("guild-position-map")
    if self.worldProvider then
        self.worldProvider:RemoveAllData()
        if WorldMapFrame and type(WorldMapFrame.RemoveDataProvider) == "function" then
            WorldMapFrame:RemoveDataProvider(self.worldProvider)
        end
    end
    self.worldProvider = nil
    self.installed = false
    self:HideMinimapPins()
    self.transformCache = {}
    self.renderState = {}
    return true
end

HolyStorm.GuildPositionMap = Map

HolyStormGuildPositionPinMixin = {}
function HolyStormGuildPositionPinMixin:OnAcquired(entry)
    local size = HolyStorm.GuildPositions:GetSettings().worldMapSize
    Map:ConfigureVisual(self, entry, size)
    self.border:SetSize(size + 16, size + 16)
    self:Show()
end
function HolyStormGuildPositionPinMixin:OnReleased()
    self.entry = nil
    self:Hide()
    GameTooltip:Hide()
end
function HolyStormGuildPositionPinMixin:OnEnter()
    if self.entry then Map:ShowTooltip(self, self.entry) end
end
function HolyStormGuildPositionPinMixin:OnLeave() GameTooltip:Hide() end
function HolyStormGuildPositionPinMixin:OnClick(button) Map:HandleClick(self, button) end
