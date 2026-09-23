local addonName = ...
local addonVersion = "5.3.0"
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)

local HolyStorm = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceEvent-3.0", "AceTimer-3.0")
HolyStorm.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or addonVersion
HolyStorm.metadata = {
    displayName = L["CORE_DISPLAY_NAME"], internalName = "core", author = "Mynastrus - Norgannon - EU",
    version = HolyStorm.version, category = "core", description = L["CORE_DESCRIPTION"],
    permissions = { "core-settings-read", "core-settings-write" }, dependencies = {}, enabledByDefault = true,
}
HolyStorm.Data, HolyStorm.Modules = {}, {}

function HolyStorm:OnInitialize()
    self.Database:Initialize()
    self.Logger:Initialize(self.Database:Get("debug", "profile") == true)
    self.Events:Initialize(); self.AddonLoader:Initialize(); self.State:Initialize(); self.Tasks:Initialize(); self.Tasks:BeginStartup("INITIALIZE"); self.Workflows:Initialize(); self.Actions:Initialize()
    self.PlayerData:Initialize(); self.Data.PlayerStore:Initialize(); self.Data.CharacterStore:Initialize(); self.Data.GuildStore:Initialize(); self.CharacterScans:Initialize()
    self.Comms:Initialize(); self.Sync:Initialize()
    self.Rules:RegisterField("core","holystorm.version",{type="string",name=L["RULE_FIELD_ADDON_VERSION"],nameKey="RULE_FIELD_ADDON_VERSION",description=L["RULE_FIELD_ADDON_VERSION_DESC"],descriptionKey="RULE_FIELD_ADDON_VERSION_DESC",category=L["CORE_DISPLAY_NAME"],dependencies={"addon"},resolver=function(context)return context.character and context.character.addon and context.character.addon.version end})
    self.Rules:RegisterAlias("core","addonVersion","holystorm.version")
    self.Rules:Initialize(); self.Permissions:Initialize()
    local policyReady,policyError=self.Policy:Initialize()
    if policyReady==false then error("Holy Storm policy initialization: "..tostring(policyError)) end
    self.MapLinks.temporaryMarker=nil
    self.RichContent:Initialize()
    self.Notifications:Initialize()
    self.Hooks:Initialize()
    self.Commands:Initialize()
    if self.ProtectRegisteredModules then self:ProtectRegisteredModules() end
    self.State:Set("addonLoaded", true)
end

function HolyStorm:OnEnable()
    self.Tasks:BeginStartup("LOGIN")
    local function register(event, callback) self.Events:Register(event, "bootstrap", callback) end
    register("PLAYER_LOGIN", function() self.State:Set("playerLoggedIn", true) end)
    register("PLAYER_LEAVING_WORLD", function() self.State:Set("playerReady", false); self.State:Set("loading", true); self.State:Set("zoning", true) end)
    register("PLAYER_ENTERING_WORLD", function() self.State:Set("loading", false); self.State:Set("zoning", false); self.State:Set("playerReady", true) end)
    register("PLAYER_REGEN_DISABLED", function() self.State:Set("inCombat", true) end)
    register("PLAYER_REGEN_ENABLED", function() self.State:Set("inCombat", false); self.Actions:Flush() end)
    if IsLoggedIn() then self.State:Set("playerLoggedIn", true) end
    self.Commands:AnnounceLoaded()
end

function HolyStorm:OnDisable() self.Events:UnregisterOwner("bootstrap"); self.AddonLoader:Shutdown(); if self.Chat then self.Chat:Shutdown() end; self.Sync:Shutdown(); self.Comms:Shutdown(); self.Tasks:CancelAll() end
