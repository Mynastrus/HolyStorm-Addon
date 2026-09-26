local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm")

local Libraries = {
    version = addonVersion,
    ADDON_ICON = "Interface\\AddOns\\Holy_Storm\\Images\\minimap_logo.png",
    ADDON_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark",
    definitions = {
        "LibQTip-1.0",
        "LibDataBroker-1.1",
        "LibDBIcon-1.0",
        "LibSharedMedia-3.0",
        "AceComm-3.0",
        "AceCommQueue-1.0",
        "LibGuildRoster-1.0",
    },
}

local broker, icon

local function versionFor(name)
    local minor = LibStub.minors and LibStub.minors[name]
    return type(minor) == "number" and minor or nil
end

function Libraries:GetStatus()
    local status = {}
    for _, name in ipairs(self.definitions) do
        local library = LibStub(name, true)
        status[name] = { loaded = library ~= nil, version = library and versionFor(name) or nil }
    end
    return status
end

function Libraries:GetSharedMedia()
    return LibStub("LibSharedMedia-3.0", true)
end

function Libraries:FetchMedia(category, key, noDefault)
    local media = self:GetSharedMedia()
    return media and media:Fetch(category, key, noDefault) or nil
end

function Libraries:ListMedia(category)
    local media = self:GetSharedMedia()
    return media and media:List(category) or {}
end

function Libraries:RegisterMedia(category, key, path)
    local media = self:GetSharedMedia()
    if not media then return false end
    return media:Register(category, key, path)
end

function Libraries:GetMinimapSettings()
    return HolyStorm.Database:Get("minimap", "profile")
end

function Libraries:GetMinimapVisible()
    local settings = self:GetMinimapSettings()
    return not settings or settings.showIcon ~= false
end

function Libraries:SetMinimapVisible(visible)
    visible = visible == true
    HolyStorm.Database:Set("minimap.showIcon", visible, "profile")
    local settings = self:GetMinimapSettings()
    if settings then settings.hide = not visible end
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if dbIcon and dbIcon:IsRegistered("HolyStorm") then
        if visible then dbIcon:Show("HolyStorm") else dbIcon:Hide("HolyStorm") end
    end
    return true
end

function Libraries:ToggleMainWindow()
    local ui = HolyStorm.UI
    if not ui then return false end
    local driver = ui.driver
    if driver and driver.frame and driver.frame.IsShown and driver.frame:IsShown() then
        driver.frame:Hide()
        return true
    end
    return ui:Open() == true
end

function Libraries:Initialize()
    local ldb = LibStub("LibDataBroker-1.1", true)
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if not ldb or not dbIcon then return false, "LAUNCHER_LIBRARIES_UNAVAILABLE" end

    broker = ldb:NewDataObject("HolyStorm", {
        type = "launcher",
        label = L["CORE_DISPLAY_NAME"],
        text = string.format("%s v%s", L["CORE_DISPLAY_NAME"], tostring(HolyStorm.version)),
        icon = self.ADDON_ICON or self.ADDON_ICON_FALLBACK,
        OnClick = function(_, button)
            if button == "LeftButton" then Libraries:ToggleMainWindow() end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:SetText(L["OPEN_HOLY_STORM"])
            tooltip:AddLine(L["LEFT_CLICK_TO_OPEN_HOLY_STORM"], 1, 1, 1, true)
        end,
    })

    local settings = self:GetMinimapSettings()
    if not settings then return false, "MINIMAP_SETTINGS_UNAVAILABLE" end
    settings.hide = settings.showIcon == false
    dbIcon:Register("HolyStorm", broker, settings)
    icon = dbIcon
    return true
end

HolyStorm.Libraries = Libraries
