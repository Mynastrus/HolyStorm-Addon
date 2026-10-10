local addonVersion = "2.1.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Options")

local Options = HolyStorm:RegisterRequiredModule("Options")
Options.pendingTabs = Options.pendingTabs or {}
Options.optionRegistry = Options.optionRegistry or {}
HolyStorm:ApplyModuleMetadata(Options, {
    displayName = L["DISPLAY_NAME"],
    internalName = "options",
    version = addonVersion,
    category = "required",
    description = L["DESCRIPTION"],
    permissions = {
        { id = "settings-read", category = "Core" },
        { id = "settings-write", category = "Core" },
    },
    dependencies = {
        "core",
    },
    enabledByDefault = true,
})

function Options:OnInitialize()
    self.optionsTable = {
        type = "group",
        name = L["OPTIONS_TITLE"],
        args = {
            general = {
                type = "group",
                name = L["GENERAL_SETTINGS"],
                order = 1,
                args = {
                    showMinimapIcon = {
                        type = "toggle",
                        name = L["SHOW_MINIMAP_ICON"],
                        order = 1,
                        get = function() return HolyStorm.Libraries:GetMinimapVisible() end,
                        set = function(_, value) HolyStorm.Libraries:SetMinimapVisible(value) end,
                    },
                    savePosition = {
                        type = "toggle",
                        name = L["SAVE_WINDOW_POSITION"],
                        order = 2,
                        get = function()
                            return HolyStorm.Database:Get("window.savePosition", "profile")
                        end,
                        set = function(_, value)
                            HolyStorm.Database:Set("window.savePosition", value, "profile")
                            local uiModule = HolyStorm:GetModule("UI", true)

                            if uiModule then
                                if value then
                                    uiModule:SaveWindowPosition()
                                else
                                    HolyStorm.Database:Set("window.position", nil, "profile")
                                end
                            end
                        end,
                    },
                    saveSize = {
                        type = "toggle",
                        name = L["SAVE_WINDOW_SIZE"],
                        order = 3,
                        get = function()
                            return HolyStorm.Database:Get("window.saveSize", "profile")
                        end,
                        set = function(_, value)
                            HolyStorm.Database:Set("window.saveSize", value, "profile")
                            local uiModule = HolyStorm:GetModule("UI", true)

                            if uiModule then
                                if value then
                                    uiModule:SaveWindowSize()
                                else
                                    HolyStorm.Database:Set("window.size", nil, "profile")
                                end
                            end
                        end,
                    },
                    resetPosition = {
                        type = "execute",
                        name = L["RESET_WINDOW_POSITION"],
                        order = 4,
                        func = function()
                            local uiModule = HolyStorm:GetModule("UI", true)
                            if uiModule then
                                uiModule:ResetWindowPosition()
                            end
                        end,
                    },
                    resetSize = {
                        type = "execute",
                        name = L["RESET_WINDOW_SIZE"],
                        order = 5,
                        func = function()
                            local uiModule = HolyStorm:GetModule("UI", true)
                            if uiModule then
                                uiModule:ResetWindowSize()
                            end
                        end,
                    },
                },
            },
            profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(HolyStorm.Database:GetHandle()),
        },
    }

    for id, options in pairs(self.pendingTabs) do self.optionsTable.args[id] = options end

    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("HolyStormOptions", self.optionsTable)
end

function Options:Open(tab)
    local uiModule = HolyStorm:GetModule("UI", true)

    if uiModule and uiModule.ShowOptions then
        uiModule:ShowOptions("HolyStormOptions")
        if tab and LibStub("AceConfigDialog-3.0").SelectGroup then
            LibStub("AceConfigDialog-3.0"):SelectGroup("HolyStormOptions", tab)
        end
        return true
    end
    return false
end

function Options:RegisterOptionsTab(id, options)
    if type(id) ~= "string" or id == "" or type(options) ~= "table" then return false, "INVALID_OPTIONS_TAB" end
    self.pendingTabs[id] = options
    if not self.optionsTable then return true, "PENDING_UI" end
    self.optionsTable.args[id] = options
    LibStub("AceConfigRegistry-3.0"):NotifyChange("HolyStormOptions")
    return true
end

function Options:RegisterSetting(definition)
    if type(definition) ~= "table" or type(definition.id) ~= "string" or type(definition.module) ~= "string" then
        return false, "INVALID_OPTION_CONTRACT"
    end
    if type(definition.nameKey) ~= "string" or type(definition.descriptionKey) ~= "string" then
        return false, "OPTION_LOCALIZATION_REQUIRED"
    end
    if type(definition.uiOrder) ~= "number" then return false, "OPTION_ORDER_REQUIRED" end
    definition.synchronized = definition.synchronized == true
    if definition.synchronized then return false, "SYNCED_OPTIONS_REQUIRE_ADMINISTRATION_REGISTRY" end
    definition.storage = definition.storage or {backend="Database.global.localSettings", locality="local"}
    local registered, reason = HolyStorm.Settings:Register(definition)
    if not registered then return false, reason end
    self.optionRegistry[definition.id] = HolyStorm.Utils.DeepCopy(definition)
    if definition.slash and HolyStorm.Commands then HolyStorm.Commands:RegisterOption(definition) end
    return true
end

function Options:SetSetting(id, value, scope, key)
    local definition = self.optionRegistry[id]
    if definition and type(definition.setter) == "function" then
        return definition.setter(value, scope, key)
    end
    return HolyStorm.Settings:Set(id, value, scope, key)
end

function Options:GetRegisteredSettings()
    local result = {}
    for _, definition in pairs(self.optionRegistry) do result[#result + 1] = HolyStorm.Utils.DeepCopy(definition) end
    table.sort(result, function(a,b) if a.module ~= b.module then return a.module < b.module end; return a.id < b.id end)
    return result
end

function Options:CreateScopeSelector(settingId, labels, order)
    local definition = HolyStorm.Settings:GetDefinition(settingId)
    local values = {}
    for scope in pairs(definition and definition.scopes or {}) do values[scope] = labels and labels[scope] or scope end
    return {
        type = "select", name = labels and labels.label or "Scope", order = order or 99, values = values,
        get = function() return HolyStorm.Settings:GetSelectedScope(settingId) end,
        set = function(_, scope) HolyStorm.Settings:SetSelectedScope(settingId, scope) end,
        disabled = function() return definition and definition.scopes.guild and not HolyStorm.Data.GuildStore:GetCurrent() or false end,
    }
end

HolyStorm.Options = Options
