local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local State = { version=addonVersion, values = {} }
local defaults = { addonLoaded = false, playerLoggedIn = false, playerReady = false, loading = false, zoning = false, guildAvailable = false, guildRosterReady = false, inCombat = false, uiReady = false, syncReady = false }
function State:Initialize() self.values = HolyStorm.Utils.DeepCopy(defaults); self.values.inCombat = InCombatLockdown and InCombatLockdown() or false; self.values.guildAvailable = IsInGuild and IsInGuild() or false end
function State:Get(key) return self.values[key] end
function State:Is(key) return self.values[key] == true end
function State:Set(key, value)
    if defaults[key] == nil then return false end
    value = value == true; if self.values[key] == value then return false end
    local previous = self.values[key]; self.values[key] = value; HolyStorm.Events:Emit("HS_STATE_CHANGED", key, value, previous); HolyStorm.Events:Emit("HS_STATE_" .. string.upper(key), value, previous); return true
end
function State:Snapshot() return HolyStorm.Utils.DeepCopy(self.values) end
HolyStorm.State = State
