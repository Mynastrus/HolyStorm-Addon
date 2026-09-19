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
    self.Events:Initialize(); self.State:Initialize(); self.Tasks:Initialize(); self.Tasks:BeginStartup("INITIALIZE"); self.Workflows:Initialize(); self.Actions:Initialize()
    self.PlayerData:Initialize(); self.Data.PlayerStore:Initialize(); self.Data.CharacterStore:Initialize(); self.Data.GuildStore:Initialize()
    self.Comms:Initialize(); self.Sync:Initialize()
    self.Rules:RegisterField("core","holystorm.version",{type="string",name=L["RULE_FIELD_ADDON_VERSION"],nameKey="RULE_FIELD_ADDON_VERSION",description=L["RULE_FIELD_ADDON_VERSION_DESC"],descriptionKey="RULE_FIELD_ADDON_VERSION_DESC",category=L["CORE_DISPLAY_NAME"],dependencies={"addon"},resolver=function(context)return context.character and context.character.addon and context.character.addon.version end})
    self.Rules:RegisterAlias("core","addonVersion","holystorm.version")
    self.Rules:Initialize(); self.Permissions:Initialize()
    self.TwinkCore:Initialize()
    local policyReady,policyError=self.Policy:Initialize()
    if policyReady==false then error("Holy Storm policy initialization: "..tostring(policyError)) end
    self.MapLinks.temporaryMarker=nil
    self.RichContent:Initialize()
    self.Notifications:Initialize()
    self.Achievements:Initialize()
    self.Content:Initialize()
    self.POI:Initialize()
    self.POIMap:Initialize()
    self.CharacterActions:Initialize()
    self.GuildPositions:Initialize()
    self.GuildPositionMap:Initialize()
    self.Hooks:Initialize()
    self.Chat:Initialize()
    self.Commands:Initialize()
    if self.LoadConfiguredOptionalModules then self:LoadConfiguredOptionalModules() end
    if self.ProtectRegisteredModules then self:ProtectRegisteredModules() end
    self.State:Set("addonLoaded", true)
end

function HolyStorm:OnEnable()
    self.Tasks:BeginStartup("LOGIN")
    local function register(event, callback) self.Events:Register(event, "bootstrap", callback) end
    register("PLAYER_LOGIN", function() self.State:Set("playerLoggedIn", true); self:QueueInitialCollection() end)
    register("PLAYER_LEAVING_WORLD", function() self.State:Set("playerReady", false); self.State:Set("loading", true); self.State:Set("zoning", true) end)
    register("PLAYER_ENTERING_WORLD", function() self.State:Set("loading", false); self.State:Set("zoning", false); self.State:Set("playerReady", true); self:QueueInitialCollection() end)
    register("PLAYER_GUILD_UPDATE", function() self:QueueGuildCollection(true) end)
    register("GUILD_ROSTER_UPDATE", function() self.State:Set("guildRosterReady", IsInGuild()); self:QueueGuildCollection(false) end)
    register("PLAYER_REGEN_DISABLED", function() self.State:Set("inCombat", true) end)
    register("PLAYER_REGEN_ENABLED", function() self.State:Set("inCombat", false); self.Actions:Flush() end)
    if IsLoggedIn() then self.State:Set("playerLoggedIn", true); self:QueueInitialCollection() end
    self.Commands:AnnounceLoaded()
end

function HolyStorm:QueueInitialCollection()
    self.Tasks:Enqueue("character.identity", function()
        local character = self.Data.CharacterStore:CaptureCurrent()
        if character then self.Data.PlayerStore:LinkLocalCharacter(character.guid) end
    end, { priority = 1, debounce = 0.2, startupPhase = 1 })
    self.Tasks:Enqueue("character.equipment", function() self:CallCapability("character.scan.equipment", false) end, { priority = 2, debounce = 0.5, startupPhase = 2, dependencies = { "character.identity" } })
    self.Tasks:Enqueue("character.raids", function() self:CallCapability("character.scan.raids", false) end, { priority = 3, debounce = 1, startupPhase = 2, dependencies = { "character.identity" } })
    self.Tasks:Enqueue("character.mythicplus", function() self:CallCapability("character.scan.mythicplus", false) end, { priority = 4, debounce = 1.5, startupPhase = 3, dependencies = { "character.identity" } })
    self.Tasks:Enqueue("character.additional", function() self:CallCapability("character.scan.additional", false) end, { priority = 5, debounce = 2, startupPhase = 3, dependencies = { "character.identity" } })
    self:QueueGuildCollection(true)
end

function HolyStorm:QueueGuildCollection(requestRoster)
    if requestRoster then self.Data.GuildStore:RequestRoster() end
    self.Tasks:Enqueue("guild.roster", function() self.Data.GuildStore:RefreshFromBlizzard() end, { priority = 6, debounce = 0.5, cooldown = 5, startupPhase = 2, conditions = { "PLAYER_LOGGED_IN", "PLAYER_READY", "NOT_LOADING", "NOT_ZONING" } })
end

function HolyStorm:OnDisable() self.Events:UnregisterOwner("bootstrap"); if self.Chat then self.Chat:Shutdown() end; self.Tasks:CancelAll(); self.Comms:Shutdown() end
