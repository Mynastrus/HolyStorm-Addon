local addonVersion = "2.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local L = LibStub("AceLocale-3.0"):GetLocale("Holy_Storm_Options")

local Options = HolyStorm:RegisterRequiredModule("Options")
Options.pendingTabs = Options.pendingTabs or {}
HolyStorm:ApplyModuleMetadata(Options, {
    displayName = L["DISPLAY_NAME"],
    internalName = "options",
    version = addonVersion,
    category = "required",
    description = L["DESCRIPTION"],
    permissions = {
        "settings-read",
        "settings-write",
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
                    savePosition = {
                        type = "toggle",
                        name = L["SAVE_WINDOW_POSITION"],
                        order = 1,
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
                        order = 2,
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
                        order = 3,
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
                        order = 4,
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

function Options:Open()
    local uiModule = HolyStorm:GetModule("UI", true)

    if uiModule and uiModule.ShowOptions then
        uiModule:ShowOptions("HolyStormOptions")
    end
end

function Options:RegisterOptionsTab(id, options)
    if type(id) ~= "string" or id == "" or type(options) ~= "table" then return false, "INVALID_OPTIONS_TAB" end
    self.pendingTabs[id] = options
    if not self.optionsTable then return true, "PENDING_UI" end
    self.optionsTable.args[id] = options
    LibStub("AceConfigRegistry-3.0"):NotifyChange("HolyStormOptions")
    return true
end
