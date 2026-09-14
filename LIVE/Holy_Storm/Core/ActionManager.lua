local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Actions = { version=addonVersion, definitions = {}, pending = {}, once = {} }
function Actions:Initialize() self.initialized=true; HolyStorm.Events:Register("PLAYER_REGEN_ENABLED","action-manager",function() Actions:Flush() end) end
function Actions:Register(id, owner, callback, options)
    if type(id) ~= "string" or type(callback) ~= "function" then return false end
    self.definitions[id] = { owner = owner, callback = callback, options = options or {} }; return true
end
function Actions:Execute(id, ...)
    local definition = self.definitions[id]; if not definition then return false end
    if definition.options.once and self.once[id] then return true end
    local args = { ... }
    if definition.options.combatSafe == false and InCombatLockdown() then self.pending[id] = args; return true end
    HolyStorm.Tasks:Enqueue("action." .. id, function()
        local ok = HolyStorm.Utils.SafeCall("action:" .. id, definition.callback, unpack(args)); if ok and definition.options.once then Actions.once[id] = true end
    end, { priority = definition.options.priority or 5, debounce = definition.options.delay or 0, combat = definition.options.combatSafe == false and "defer" or "allow" })
    return true
end
function Actions:Flush() local pending = self.pending; self.pending = {}; for id, args in pairs(pending) do self:Execute(id, unpack(args)) end end
HolyStorm.Actions = Actions
