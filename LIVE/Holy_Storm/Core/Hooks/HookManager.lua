local addonVersion = "1.0.0"
local HolyStorm = LibStub("AceAddon-3.0"):GetAddon("Holy_Storm")
local Hooks = { version=addonVersion, registered = {}, owners = {}, enabled = {} }
function Hooks:Initialize() self.initialized=true; HolyStorm.Events:Register("PLAYER_REGEN_ENABLED","hook-manager",function() for owner in pairs(Hooks.enabled) do Hooks.enabled[owner]=Hooks.enabled[owner]~=false end end) end
function Hooks:SetOwnerEnabled(owner, enabled) self.enabled[owner] = enabled ~= false end
function Hooks:IsOwnerEnabled(owner) return self.enabled[owner] ~= false end
function Hooks:Secure(id, target, method, callback)
    if type(method) == "function" and callback == nil then callback, method = method, nil end
    if self.registered[id] or type(callback) ~= "function" then return false end
    local owner = id:match("^([^:]+)") or id; self.owners[id], self.enabled[owner] = owner, self.enabled[owner] ~= false
    local wrapped = function(...) if Hooks:IsOwnerEnabled(owner) then HolyStorm.Utils.SafeCall("hook:" .. id, callback, ...) end end
    local ok = method and pcall(hooksecurefunc, target, method, wrapped) or pcall(hooksecurefunc, target, wrapped)
    if ok then self.registered[id] = true else HolyStorm.Logger:WARN("HookManager", "Hook %s could not be installed", id) end
    return ok
end
function Hooks:Script(id, owner, frame, script, callback)
    if self.registered[id] or not frame or type(callback) ~= "function" then return false end
    self.enabled[owner] = self.enabled[owner] ~= false
    frame:HookScript(script, function(...) if Hooks:IsOwnerEnabled(owner) then HolyStorm.Utils.SafeCall("hook:" .. id, callback, ...) end end)
    self.registered[id], self.owners[id] = true, owner; return true
end
HolyStorm.Hooks = Hooks
