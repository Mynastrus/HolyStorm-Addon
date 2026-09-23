local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")

local Loader = {
    addonsById = {},
    addonsByEvent = {},
    attempted = {},
    loadContexts = {},
}

local function trim(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or nil
end

local function split(value)
    local result = {}
    for token in tostring(value or ""):gmatch("[^,;%s]+") do
        token = trim(token)
        if token and token ~= "" then result[#result + 1] = token end
    end
    return result
end

local function metadataNumber(value)
    local parsed = tonumber(trim(value))
    return parsed
end

local function addonNameAt(index)
    if not C_AddOns or not C_AddOns.GetAddOnInfo then return nil end
    local first = C_AddOns.GetAddOnInfo(index)
    if type(first) == "table" then return first.name end
    return first
end

function Loader:Discover()
    self.addonsById, self.addonsByEvent = {}, {}
    if not C_AddOns or not C_AddOns.GetNumAddOns or not C_AddOns.GetAddOnMetadata then return 0 end
    local count = 0
    for index = 1, C_AddOns.GetNumAddOns() do
        local addonName = addonNameAt(index)
        local id = addonName and trim(C_AddOns.GetAddOnMetadata(addonName, "X-HolyStorm-ID"))
        if id and id ~= "" and not self.addonsById[id] then
            local definition = {
                id = id,
                addonName = addonName,
                requires = split(C_AddOns.GetAddOnMetadata(addonName, "X-HolyStorm-Requires")),
                events = split(C_AddOns.GetAddOnMetadata(addonName, "X-HolyStorm-LoadOnEvent")),
                characterBlock = trim(C_AddOns.GetAddOnMetadata(addonName, "X-HolyStorm-CharacterBlock")),
                characterCapability = trim(C_AddOns.GetAddOnMetadata(addonName, "X-HolyStorm-CharacterCapability")),
                characterOrder = metadataNumber(C_AddOns.GetAddOnMetadata(addonName, "X-HolyStorm-CharacterOrder")),
            }
            self.addonsById[id] = definition
            count = count + 1
            for _, event in ipairs(definition.events) do
                self.addonsByEvent[event] = self.addonsByEvent[event] or {}
                self.addonsByEvent[event][addonName] = definition
            end
        end
    end
    return count
end


function Loader:LoadById(id, context)
    local definition = self.addonsById[id]
    if not definition then return false, "UNKNOWN_ADDON" end
    if self:IsLoaded(definition.addonName) then return true, "ALREADY_LOADED" end
    return self:Load(definition, context)
end

function Loader:GetCharacterDataDefinitions()
    local result = {}
    for _, definition in pairs(self.addonsById) do
        if definition.characterBlock and definition.characterCapability then
            result[#result + 1] = { block=definition.characterBlock, capability=definition.characterCapability, addonId=definition.id, order=definition.characterOrder or 100 }
        end
    end
    table.sort(result, function(left, right) if left.order == right.order then return left.block < right.block end; return left.order < right.order end)
    return result
end

function Loader:GetCharacterDataDefinition(block)
    for _, definition in ipairs(self:GetCharacterDataDefinitions()) do if definition.block == block then return definition end end
end

function Loader:IsLoaded(addonName)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName) == true
end

function Loader:GetLoadedAddonNames()
    local result = {}
    if not C_AddOns or not C_AddOns.GetNumAddOns then return result end
    for index = 1, C_AddOns.GetNumAddOns() do
        local addonName = addonNameAt(index)
        if addonName and (addonName == "Holy_Storm" or addonName:match("^Holy_Storm_")) and self:IsLoaded(addonName) then result[#result + 1] = addonName end
    end
    table.sort(result)
    return result
end

function Loader:Load(definition, context)
    local addonName = definition and definition.addonName
    if not addonName or self.attempted[addonName] or self:IsLoaded(addonName) then return false end
    self.attempted[addonName] = true
    self.loadContexts[definition.id] = HolyStorm.Utils.DeepCopy(context or { reason = "manual" })
    local loaded, reason
    if C_AddOns and C_AddOns.LoadAddOn then loaded, reason = C_AddOns.LoadAddOn(addonName) end
    if not loaded and HolyStorm.Logger then HolyStorm.Logger:WARN("AddonLoader", "Unable to load %s: %s", addonName, tostring(reason)) end
    return loaded == true, reason
end

function Loader:HandleEvent(event)
    local bucket = self.addonsByEvent[event]
    if not bucket then return 0 end
    local loaded = 0
    for _, definition in pairs(bucket) do
        if self:Load(definition, { reason = "event", trigger = event }) then loaded = loaded + 1 end
    end
    return loaded
end

function Loader:GetLoadContext(id)
    local context = self.loadContexts[id]
    return context and HolyStorm.Utils.DeepCopy(context) or nil
end

function Loader:Initialize()
    self:Discover()
    for event in pairs(self.addonsByEvent) do
        HolyStorm.Events:Register(event, "addon-loader:" .. event, function(trigger) Loader:HandleEvent(trigger) end)
    end
end

function Loader:Shutdown()
    for event in pairs(self.addonsByEvent) do HolyStorm.Events:UnregisterOwner("addon-loader:" .. event) end
end

HolyStorm.AddonLoader = Loader

function HolyStorm:GetAddonLoadContext(id) return Loader:GetLoadContext(id) end
function HolyStorm:GetLoadedAddonNames() return Loader:GetLoadedAddonNames() end
